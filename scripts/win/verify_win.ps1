#requires -Version 5.1
<#
.SYNOPSIS
Verifies the Windows IT 140 Course IDE without repairing it.

.DESCRIPTION
Performs read-only checks of the supported Windows release, required software,
Python course environment, VS Code extensions and settings, GitHub
authentication, privacy-preserving Git identity, course paths, and managed
assets. The script writes a diagnostic log under ~/it140/logs.

An optional support bundle is created only after explicit confirmation.
#>

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Version,
    [ValidateSet("windows_bare_metal")]
    [string]$DeploymentProfile = "windows_bare_metal",
    [switch]$NonInteractive,
    [switch]$SupportBundle,
    [switch]$ConfirmSupportBundle
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ScriptVersion = "2026.07.25.2"
$PlatformId = "windows"
$CourseRoot = Join-Path $HOME "it140"
$ScriptRoot = Join-Path $CourseRoot "scripts"
$WindowsScriptDirectory = Join-Path $ScriptRoot "win"
$ManifestPath = Join-Path $ScriptRoot ".manifest\it140_manifest.json"
$SchemaPath = Join-Path $ScriptRoot ".manifest\it140_manifest.schema.json"
$LogDirectory = Join-Path $CourseRoot "logs"
$LogPath = Join-Path $LogDirectory (
    "verify_win_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss")
)
$VenvDirectory = Join-Path $CourseRoot ".venv"
$VenvPython = Join-Path $VenvDirectory "Scripts\python.exe"
$VenvScripts = Join-Path $VenvDirectory "Scripts"
$VsCodeSettings = Join-Path $env:APPDATA "Code\User\settings.json"
$TranscriptStarted = $false
$ExitCode = 0
$ManifestFailure = $false
$UnsupportedFailure = $false
$Results = New-Object Collections.Generic.List[object]

function Write-Info {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-Notice {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[NOTICE] $Message"
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $Property = $Object.PSObject.Properties[$Name]
    if ($null -eq $Property) {
        return $null
    }
    return $Property.Value
}

function Add-CheckResult {
    param(
        [Parameter(Mandatory = $true)][string]$CheckId,
        [Parameter(Mandatory = $true)]
        [ValidateSet("PASS", "WARNING", "FAIL", "NOT APPLICABLE")]
        [string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail,
        [Parameter(Mandatory = $true)][string]$Remediation
    )

    $Result = [pscustomobject]@{
        CheckId = $CheckId
        Status = $Status
        Detail = $Detail
        Remediation = $Remediation
    }
    $Results.Add($Result)

    $Label = "[$Status]"
    Write-Host ("{0,-16} {1,-34} {2}" -f $Label, $CheckId, $Detail)
}

function Read-ControlledManifest {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "The controlled manifest is missing."
    }
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
        throw "The manifest schema is missing."
    }

    try {
        $Manifest = Get-Content -LiteralPath $ManifestPath -Raw |
            ConvertFrom-Json
        $null = Get-Content -LiteralPath $SchemaPath -Raw |
            ConvertFrom-Json
    }
    catch {
        throw "The manifest or schema is not valid JSON."
    }

    if ([string]$Manifest.schema_version -ne "1.0") {
        throw "The manifest schema version is not supported."
    }

    $Platform = Get-PropertyValue -Object $Manifest.platforms -Name $PlatformId
    $DeploymentProfileRecord = Get-PropertyValue `
        -Object $Manifest.deployment_profiles `
        -Name $DeploymentProfile
    if ($null -eq $Platform -or $null -eq $DeploymentProfileRecord) {
        throw "The Windows platform or deployment profile is missing."
    }

    return [pscustomobject]@{
        Manifest = $Manifest
        Platform = $Platform
        Profile = $DeploymentProfileRecord
    }
}

function Get-WindowsFacts {
    $OperatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
    $CurrentVersion = Get-ItemProperty `
        -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"

    return [pscustomobject]@{
        Caption = [string]$OperatingSystem.Caption
        Architecture = [string]$OperatingSystem.OSArchitecture
        DisplayVersion = [string]$CurrentVersion.DisplayVersion
        BuildNumber = [string]$OperatingSystem.BuildNumber
    }
}

function Test-CommandAvailable {
    param([Parameter(Mandatory = $true)][string]$CommandName)
    return $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Get-RequiredExtensions {
    param([Parameter(Mandatory = $true)]$Platform)

    $Extensions = @()
    foreach ($Property in $Platform.course_ide_bindings.PSObject.Properties) {
        $Binding = $Property.Value
        if (
            [string]$Binding.installation_scope -eq "user" -and
            [string]$Binding.installer_adapter_id -eq "vscode_extension"
        ) {
            $Extensions += [string]$Binding.package_identifier
        }
    }
    return @($Extensions | Sort-Object -Unique)
}

function Test-JsonSettingValue {
    param(
        [Parameter(Mandatory = $true)]$Settings,
        [Parameter(Mandatory = $true)][string]$PropertyName,
        [Parameter(Mandatory = $true)]$Expected
    )

    $Property = $Settings.PSObject.Properties[$PropertyName]
    if ($null -eq $Property) {
        return $false
    }

    return (
        ($Property.Value | ConvertTo-Json -Compress -Depth 20) -eq
        ($Expected | ConvertTo-Json -Compress -Depth 20)
    )
}

function Test-PendingRestart {
    $Paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\" +
            "Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\" +
            "WindowsUpdate\Auto Update\RebootRequired"
    )

    foreach ($Path in $Paths) {
        if (Test-Path -LiteralPath $Path) {
            return $true
        }
    }

    try {
        $SessionManager = Get-ItemProperty `
            -LiteralPath (
                "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
            )
        if ($null -ne $SessionManager.PendingFileRenameOperations) {
            return $true
        }
    }
    catch {
    }

    return $false
}

function New-SupportBundle {
    param([Parameter(Mandatory = $true)]$WindowsFacts)

    if (-not $SupportBundle) {
        return $null
    }

    if ($NonInteractive -and -not $ConfirmSupportBundle) {
        Write-Notice (
            "Support-bundle creation requires -ConfirmSupportBundle in " +
            "noninteractive mode."
        )
        return $null
    }

    if (-not $ConfirmSupportBundle) {
        Write-Host ""
        Write-Notice (
            "The bundle will contain only the sanitized verification report, " +
            "platform facts, and version summary."
        )
        Write-Notice (
            "It will not contain student files, repository contents, Git " +
            "history, credentials, tokens, browser data, or a complete email."
        )
        $Answer = Read-Host "Type YES to create the support bundle"
        if ($Answer -cne "YES") {
            Write-Notice "Support-bundle creation was canceled."
            return $null
        }
    }

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $Staging = Join-Path $env:TEMP "it140-support-$Timestamp"
    $ZipPath = Join-Path $LogDirectory "it140_support_win_$Timestamp.zip"

    New-Item -ItemType Directory -Path $Staging -Force | Out-Null
    try {
        $Results |
            Select-Object CheckId, Status, Detail, Remediation |
            ConvertTo-Json -Depth 10 |
            Set-Content `
                -LiteralPath (Join-Path $Staging "verification.json") `
                -Encoding UTF8

        [pscustomobject]@{
            Platform = "windows"
            DeploymentProfile = $DeploymentProfile
            Caption = $WindowsFacts.Caption
            DisplayVersion = $WindowsFacts.DisplayVersion
            BuildNumber = $WindowsFacts.BuildNumber
            Architecture = $WindowsFacts.Architecture
            ScriptVersion = $ScriptVersion
        } |
            ConvertTo-Json |
            Set-Content `
                -LiteralPath (Join-Path $Staging "platform.json") `
                -Encoding UTF8

        $VersionLines = @()
        foreach ($Command in @("git.exe", "gh.exe", "python.exe", "code.cmd")) {
            if (Test-CommandAvailable $Command) {
                $Output = & $Command --version 2>&1
                $VersionLines += "$Command : $($Output[0])"
            }
        }
        $VersionLines |
            Set-Content `
                -LiteralPath (Join-Path $Staging "versions.txt") `
                -Encoding UTF8

        Compress-Archive `
            -Path (Join-Path $Staging "*") `
            -DestinationPath $ZipPath `
            -Force
    }
    finally {
        Remove-Item -LiteralPath $Staging -Recurse -Force `
            -ErrorAction SilentlyContinue
    }

    return $ZipPath
}

function Show-Usage {
    @"
IT 140 Windows verification script

Usage:
  powershell.exe -ExecutionPolicy Bypass -File .\verify_win.ps1
  powershell.exe -ExecutionPolicy Bypass -File .\verify_win.ps1 -SupportBundle
  powershell.exe -ExecutionPolicy Bypass -File .\verify_win.ps1 -Help

This script does not install, repair, update, or rewrite managed settings.
Logs: $LogDirectory
"@ | Write-Host
}

try {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    Start-Transcript -Path $LogPath -Append -Force | Out-Null
    $TranscriptStarted = $true

    if ($Help) {
        Show-Usage
        $ExitCode = 0
        return
    }

    if ($Version) {
        Write-Host $ScriptVersion
        $ExitCode = 0
        return
    }

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "IT 140 WINDOWS VERIFICATION"
    Write-Host "============================================================"
    Write-Info "Script version : $ScriptVersion"
    Write-Info "Log file       : $LogPath"

    try {
        $Controlled = Read-ControlledManifest
        Add-CheckResult `
            -CheckId "manifest" `
            -Status "PASS" `
            -Detail (
                "Release {0}" -f $Controlled.Manifest.automation_release
            ) `
            -Remediation "update"
    }
    catch {
        $ManifestFailure = $true
        Add-CheckResult `
            -CheckId "manifest" `
            -Status "FAIL" `
            -Detail $_.Exception.Message `
            -Remediation "update"
        throw
    }

    $WindowsFacts = Get-WindowsFacts
    $SupportedReleases = @(
        $Controlled.Platform.os.releases |
            ForEach-Object { [string]$_.release_id }
    )

    if ($WindowsFacts.Caption -match "Windows 11") {
        Add-CheckResult `
            -CheckId "operating_system" `
            -Status "PASS" `
            -Detail $WindowsFacts.Caption `
            -Remediation "technical_support"
    }
    else {
        $UnsupportedFailure = $true
        Add-CheckResult `
            -CheckId "operating_system" `
            -Status "FAIL" `
            -Detail $WindowsFacts.Caption `
            -Remediation "technical_support"
    }

    if ($WindowsFacts.DisplayVersion -in $SupportedReleases) {
        Add-CheckResult `
            -CheckId "os_release" `
            -Status "PASS" `
            -Detail $WindowsFacts.DisplayVersion `
            -Remediation "technical_support"
    }
    else {
        $UnsupportedFailure = $true
        Add-CheckResult `
            -CheckId "os_release" `
            -Status "FAIL" `
            -Detail (
                "Unsupported release: {0}" -f $WindowsFacts.DisplayVersion
            ) `
            -Remediation "technical_support"
    }

    if ($WindowsFacts.Architecture -match "64-bit") {
        Add-CheckResult `
            -CheckId "architecture" `
            -Status "PASS" `
            -Detail $WindowsFacts.Architecture `
            -Remediation "technical_support"
    }
    else {
        $UnsupportedFailure = $true
        Add-CheckResult `
            -CheckId "architecture" `
            -Status "FAIL" `
            -Detail $WindowsFacts.Architecture `
            -Remediation "technical_support"
    }

    $FreeBytes = (Get-PSDrive -Name $env:SystemDrive.TrimEnd(":")).Free
    $MinimumBytes = [int64]$Controlled.Manifest.policy.minimum_free_space_bytes
    if ($FreeBytes -ge $MinimumBytes) {
        Add-CheckResult `
            -CheckId "disk_space" `
            -Status "PASS" `
            -Detail ("{0:N1} GB free" -f ($FreeBytes / 1GB)) `
            -Remediation "technical_support"
    }
    else {
        Add-CheckResult `
            -CheckId "disk_space" `
            -Status "FAIL" `
            -Detail ("{0:N1} GB free" -f ($FreeBytes / 1GB)) `
            -Remediation "technical_support"
    }

    try {
        $Response = Invoke-WebRequest `
            -Uri "https://github.com/GC-STEM/it140" `
            -Method Head `
            -TimeoutSec 15 `
            -UseBasicParsing
        Add-CheckResult `
            -CheckId "network" `
            -Status "PASS" `
            -Detail ("HTTP {0}" -f $Response.StatusCode) `
            -Remediation "technical_support"
    }
    catch {
        Add-CheckResult `
            -CheckId "network" `
            -Status "WARNING" `
            -Detail "The course repository did not respond within the check." `
            -Remediation "technical_support"
    }

    foreach ($Command in @("winget.exe", "git.exe", "gh.exe", "python.exe", "code.cmd")) {
        if (Test-CommandAvailable $Command) {
            Add-CheckResult `
                -CheckId ("command.{0}" -f $Command) `
                -Status "PASS" `
                -Detail "Available" `
                -Remediation "setup"
        }
        else {
            Add-CheckResult `
                -CheckId ("command.{0}" -f $Command) `
                -Status "FAIL" `
                -Detail "Missing" `
                -Remediation "setup"
        }
    }

    if (Test-CommandAvailable "python.exe") {
        $PythonVersion = & python.exe -c (
            "import sys; print('.'.join(map(str, sys.version_info[:2])))"
        )
        if ($LASTEXITCODE -eq 0 -and [string]$PythonVersion -eq "3.12") {
            Add-CheckResult `
                -CheckId "python.version" `
                -Status "PASS" `
                -Detail "Python 3.12" `
                -Remediation "setup"
        }
        else {
            Add-CheckResult `
                -CheckId "python.version" `
                -Status "FAIL" `
                -Detail "Python 3.12 is not active." `
                -Remediation "setup"
        }
    }

    if (Test-Path -LiteralPath $VenvPython -PathType Leaf) {
        Add-CheckResult `
            -CheckId "python.venv" `
            -Status "PASS" `
            -Detail $VenvDirectory `
            -Remediation "configure"

        foreach ($Package in @("pytest", "pytest-cov", "ruff")) {
            & $VenvPython -m pip show $Package *> $null
            if ($LASTEXITCODE -eq 0) {
                Add-CheckResult `
                    -CheckId ("python.package.{0}" -f $Package) `
                    -Status "PASS" `
                    -Detail "Installed" `
                    -Remediation "configure"
            }
            else {
                Add-CheckResult `
                    -CheckId ("python.package.{0}" -f $Package) `
                    -Status "FAIL" `
                    -Detail "Missing" `
                    -Remediation "configure"
            }
        }
    }
    else {
        Add-CheckResult `
            -CheckId "python.venv" `
            -Status "FAIL" `
            -Detail "Course virtual environment is missing." `
            -Remediation "configure"
    }

    if (Test-CommandAvailable "code.cmd") {
        $InstalledExtensions = @(
            & code.cmd --list-extensions 2>$null |
                ForEach-Object { $_.Trim().ToLowerInvariant() }
        )
        foreach ($Extension in Get-RequiredExtensions $Controlled.Platform) {
            if ($Extension.ToLowerInvariant() -in $InstalledExtensions) {
                Add-CheckResult `
                    -CheckId ("extension.{0}" -f $Extension) `
                    -Status "PASS" `
                    -Detail "Installed" `
                    -Remediation "configure"
            }
            else {
                Add-CheckResult `
                    -CheckId ("extension.{0}" -f $Extension) `
                    -Status "FAIL" `
                    -Detail "Missing" `
                    -Remediation "configure"
            }
        }
    }

    if (Test-CommandAvailable "gh.exe") {
        & gh.exe auth status --hostname github.com *> $null
        if ($LASTEXITCODE -eq 0) {
            Add-CheckResult `
                -CheckId "github.authentication" `
                -Status "PASS" `
                -Detail "Authenticated" `
                -Remediation "configure"
        }
        else {
            Add-CheckResult `
                -CheckId "github.authentication" `
                -Status "FAIL" `
                -Detail "Not authenticated" `
                -Remediation "configure"
        }
    }

    if (Test-CommandAvailable "git.exe") {
        $GitName = (& git.exe config --global --get user.name).Trim()
        $GitEmail = (& git.exe config --global --get user.email).Trim()

        if ($GitName) {
            Add-CheckResult `
                -CheckId "git.user_name" `
                -Status "PASS" `
                -Detail "Configured" `
                -Remediation "configure"
        }
        else {
            Add-CheckResult `
                -CheckId "git.user_name" `
                -Status "FAIL" `
                -Detail "Missing" `
                -Remediation "configure"
        }

        if (
            $GitEmail -match
            "^[0-9]+\+[^@\s]+@users\.noreply\.github\.com$"
        ) {
            Add-CheckResult `
                -CheckId "git.private_email" `
                -Status "PASS" `
                -Detail "Private GitHub noreply address configured" `
                -Remediation "configure"
        }
        else {
            Add-CheckResult `
                -CheckId "git.private_email" `
                -Status "FAIL" `
                -Detail "Privacy-preserving address is not configured." `
                -Remediation "configure"
        }

        $GitSettings = Get-PropertyValue `
            -Object $Controlled.Manifest.managed_settings `
            -Name "git_course_defaults"
        foreach ($Property in $GitSettings.values.PSObject.Properties) {
            $Observed = (& git.exe config --global --get $Property.Name).Trim()
            $Expected = $Property.Value
            if ($Expected -is [bool]) {
                $Expected = $Expected.ToString().ToLowerInvariant()
            }
            if ($Observed -ceq [string]$Expected) {
                $Status = "PASS"
                $Detail = [string]$Expected
            }
            else {
                $Status = "FAIL"
                $Detail = "Expected '$Expected'; observed '$Observed'"
            }
            Add-CheckResult `
                -CheckId ("git.setting.{0}" -f $Property.Name) `
                -Status $Status `
                -Detail $Detail `
                -Remediation "configure"
        }
    }

    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User") -split ";"
    foreach ($Entry in @($WindowsScriptDirectory, $VenvScripts)) {
        if ($Entry -in $UserPath) {
            Add-CheckResult `
                -CheckId ("path.{0}" -f (Split-Path $Entry -Leaf)) `
                -Status "PASS" `
                -Detail "Present in user PATH" `
                -Remediation "configure"
        }
        else {
            Add-CheckResult `
                -CheckId ("path.{0}" -f (Split-Path $Entry -Leaf)) `
                -Status "FAIL" `
                -Detail "Missing from user PATH" `
                -Remediation "configure"
        }
    }

    if (Test-Path -LiteralPath $VsCodeSettings -PathType Leaf) {
        try {
            $Settings = Get-Content -LiteralPath $VsCodeSettings -Raw |
                ConvertFrom-Json
            $SettingsProfile = Get-PropertyValue `
                -Object $Controlled.Manifest.managed_settings `
                -Name "vscode_course_defaults"

            foreach ($Property in $SettingsProfile.values.PSObject.Properties) {
                if (
                    Test-JsonSettingValue `
                        -Settings $Settings `
                        -PropertyName $Property.Name `
                        -Expected $Property.Value
                ) {
                    $Status = "PASS"
                    $Detail = "Managed value present"
                }
                else {
                    $Status = "FAIL"
                    $Detail = "Managed value missing or different"
                }

                Add-CheckResult `
                    -CheckId ("vscode.setting.{0}" -f $Property.Name) `
                    -Status $Status `
                    -Detail $Detail `
                    -Remediation "configure"
            }

            if (
                Test-JsonSettingValue `
                    -Settings $Settings `
                    -PropertyName "python.defaultInterpreterPath" `
                    -Expected $VenvPython
            ) {
                Add-CheckResult `
                    -CheckId "vscode.python_path" `
                    -Status "PASS" `
                    -Detail "Course virtual environment selected" `
                    -Remediation "configure"
            }
            else {
                Add-CheckResult `
                    -CheckId "vscode.python_path" `
                    -Status "FAIL" `
                    -Detail "Course virtual environment is not selected." `
                    -Remediation "configure"
            }
        }
        catch {
            Add-CheckResult `
                -CheckId "vscode.settings" `
                -Status "FAIL" `
                -Detail "settings.json is not valid JSON." `
                -Remediation "technical_support"
        }
    }
    else {
        Add-CheckResult `
            -CheckId "vscode.settings" `
            -Status "FAIL" `
            -Detail "settings.json is missing." `
            -Remediation "configure"
    }

    $ShortcutPath = Join-Path `
        ([Environment]::GetFolderPath("Desktop")) `
        "IT 140.lnk"
    if (Test-Path -LiteralPath $ShortcutPath -PathType Leaf) {
        Add-CheckResult `
            -CheckId "desktop.shortcut" `
            -Status "PASS" `
            -Detail "IT 140 shortcut exists" `
            -Remediation "configure"
    }
    else {
        Add-CheckResult `
            -CheckId "desktop.shortcut" `
            -Status "FAIL" `
            -Detail "IT 140 shortcut is missing." `
            -Remediation "configure"
    }

    foreach ($ScriptName in @(
        "setup_win.ps1",
        "configure_win.ps1",
        "verify_win.ps1",
        "update_win.ps1"
    )) {
        $ScriptPath = Join-Path $WindowsScriptDirectory $ScriptName
        if (Test-Path -LiteralPath $ScriptPath -PathType Leaf) {
            Add-CheckResult `
                -CheckId ("script.{0}" -f $ScriptName) `
                -Status "PASS" `
                -Detail "Present" `
                -Remediation "update"
        }
        else {
            Add-CheckResult `
                -CheckId ("script.{0}" -f $ScriptName) `
                -Status "FAIL" `
                -Detail "Missing" `
                -Remediation "update"
        }
    }

    if (Test-PendingRestart) {
        Add-CheckResult `
            -CheckId "restart" `
            -Status "WARNING" `
            -Detail "Windows reports that a restart is pending." `
            -Remediation "restart"
    }
    else {
        Add-CheckResult `
            -CheckId "restart" `
            -Status "PASS" `
            -Detail "No pending restart was detected." `
            -Remediation "none"
    }

    $FailCount = @($Results | Where-Object { $_.Status -eq "FAIL" }).Count
    $WarningCount = @(
        $Results | Where-Object { $_.Status -eq "WARNING" }
    ).Count
    $PassCount = @($Results | Where-Object { $_.Status -eq "PASS" }).Count

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "VERIFICATION SUMMARY"
    Write-Host "============================================================"
    Write-Info "Passed          : $PassCount"
    Write-Info "Warnings        : $WarningCount"
    Write-Info "Failed          : $FailCount"
    Write-Info "Log file        : $LogPath"

    if ($FailCount -eq 0) {
        Write-Host "[SUCCESS] The Windows course environment passed all required checks."
        $ExitCode = 0
    }
    else {
        Write-Host "[ERROR] One or more required checks failed." -ForegroundColor Red
        Write-Notice (
            "Run the remediation script named in each failed result, then " +
            "run verify_win.ps1 again."
        )
        $ExitCode = 1
    }
}
catch {
    if (-not $ManifestFailure) {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }

    if ($ManifestFailure) {
        $ExitCode = 5
    }
    elseif ($UnsupportedFailure) {
        $ExitCode = 2
    }
    else {
        $ExitCode = 1
    }
}
finally {
    if ($TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
        }
    }
}

if ($SupportBundle -and $null -ne $WindowsFacts) {
    try {
        $BundlePath = New-SupportBundle -WindowsFacts $WindowsFacts
        if ($BundlePath) {
            Write-Host "[SUCCESS] Support bundle created: $BundlePath"
        }
    }
    catch {
        Write-Host (
            "[ERROR] Support bundle creation failed: {0}" -f
            $_.Exception.Message
        ) -ForegroundColor Red
        if ($ExitCode -eq 0) {
            $ExitCode = 1
        }
    }
}

exit $ExitCode
