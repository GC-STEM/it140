#requires -Version 5.1
<#
.SYNOPSIS
Configures the current Windows user for the IT 140 Course IDE.

.DESCRIPTION
Creates the course folders and Python virtual environment, authenticates GitHub
CLI when needed, applies privacy-preserving Git identity, installs required
course Python tools and VS Code extensions, merges managed editor settings,
adds the Windows scripts to the user PATH, and creates an IT 140 shortcut.

Run this script from a normal, non-elevated PowerShell terminal.
#>

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Version,
    [ValidateSet("windows_bare_metal")]
    [string]$DeploymentProfile = "windows_bare_metal",
    [switch]$NonInteractive
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
    "configure_win_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss")
)
$VenvDirectory = Join-Path $CourseRoot ".venv"
$VenvPython = Join-Path $VenvDirectory "Scripts\python.exe"
$VenvScripts = Join-Path $VenvDirectory "Scripts"
$VsCodeSettings = Join-Path $env:APPDATA "Code\User\settings.json"
$TranscriptStarted = $false
$MutationMutex = $null
$ExitCode = 0

function Write-Info {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-Success {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[SUCCESS] $Message"
}

function Write-Notice {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[NOTICE] $Message"
}

function Write-ErrorMessage {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Test-IsAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Update-ProcessEnvironment {
    $MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = @($MachinePath, $UserPath) -join ";"
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

function Read-ControlledManifest {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "The controlled manifest is missing: $ManifestPath"
    }
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
        throw "The manifest schema is missing: $SchemaPath"
    }

    try {
        $Manifest = Get-Content -LiteralPath $ManifestPath -Raw |
            ConvertFrom-Json
        $null = Get-Content -LiteralPath $SchemaPath -Raw |
            ConvertFrom-Json
    }
    catch {
        throw "The manifest or schema is not valid JSON. $($_.Exception.Message)"
    }

    if ([string]$Manifest.schema_version -ne "1.0") {
        throw "Unsupported manifest schema version: $($Manifest.schema_version)"
    }

    $Platform = Get-PropertyValue -Object $Manifest.platforms -Name $PlatformId
    $DeploymentProfileRecord = Get-PropertyValue `
        -Object $Manifest.deployment_profiles `
        -Name $DeploymentProfile

    if ($null -eq $Platform -or -not [bool]$Platform.enabled) {
        throw "The Windows platform is not enabled."
    }
    if (
        $null -eq $DeploymentProfileRecord -or
        -not [bool]$DeploymentProfileRecord.enabled
    ) {
        throw "The deployment profile is not enabled: $DeploymentProfile"
    }
    if ([string]$DeploymentProfileRecord.platform_id -ne $PlatformId) {
        throw "The deployment profile does not select Windows."
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
    }
}

function Assert-SupportedWindows {
    param(
        [Parameter(Mandatory = $true)]$WindowsFacts,
        [Parameter(Mandatory = $true)]$Platform
    )

    if ($WindowsFacts.Caption -notmatch "Windows 11") {
        throw "This script supports only Microsoft Windows 11."
    }
    if ($WindowsFacts.Architecture -notmatch "64-bit") {
        throw "This release supports only x64 Windows."
    }

    $SupportedReleases = @(
        $Platform.os.releases | ForEach-Object { [string]$_.release_id }
    )
    if ($WindowsFacts.DisplayVersion -notin $SupportedReleases) {
        throw "Windows release $($WindowsFacts.DisplayVersion) is not enabled."
    }
}

function Enter-MutationLock {
    $CreatedNew = $false
    $Mutex = New-Object Threading.Mutex(
        $false,
        "Global\IT140AutomationMutation",
        [ref]$CreatedNew
    )

    try {
        if (-not $Mutex.WaitOne(0)) {
            $Mutex.Dispose()
            throw "Another IT 140 setup, configure, or update operation is running."
        }
    }
    catch [Threading.AbandonedMutexException] {
        Write-Notice "Recovered an abandoned IT 140 operation lock."
    }

    return $Mutex
}

function Assert-SystemLayer {
    Update-ProcessEnvironment
    $RequiredCommands = @("git.exe", "gh.exe", "python.exe", "code.cmd")
    $Missing = @()

    foreach ($Command in $RequiredCommands) {
        if ($null -eq (Get-Command $Command -ErrorAction SilentlyContinue)) {
            $Missing += $Command
        }
    }

    if ($Missing.Count -gt 0) {
        throw (
            "Required system commands are missing: {0}. Run setup_win.ps1." -f
            ($Missing -join ", ")
        )
    }

    $PythonVersion = & python.exe -c (
        "import sys; print('.'.join(map(str, sys.version_info[:2])))"
    )
    if ($LASTEXITCODE -ne 0 -or [string]$PythonVersion -ne "3.12") {
        throw "Python 3.12 is not the active Windows Python runtime."
    }
}

function Initialize-CourseRepository {
    if (
        (Test-Path -LiteralPath $ManifestPath -PathType Leaf) -and
        (Test-Path -LiteralPath $WindowsScriptDirectory -PathType Container)
    ) {
        return
    }

    Write-Info "Retrieving the controlled IT 140 course package."
    $TemporaryRoot = Join-Path `
        ([IO.Path]::GetTempPath()) `
        ([IO.Path]::GetRandomFileName())
    $CloneDirectory = Join-Path $TemporaryRoot "it140"

    New-Item -ItemType Directory -Path $CourseRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $TemporaryRoot -Force | Out-Null

    try {
        & git.exe clone `
            --depth 1 `
            "https://github.com/GC-STEM/it140.git" `
            $CloneDirectory
        if ($LASTEXITCODE -ne 0) {
            throw "The course repository could not be retrieved."
        }

        Remove-Item `
            -LiteralPath (Join-Path $CloneDirectory ".git") `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue

        Get-ChildItem -LiteralPath $CloneDirectory -Force |
            Copy-Item -Destination $CourseRoot -Recurse -Force

        Remove-Item `
            -LiteralPath (Join-Path $CourseRoot ".git") `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
    finally {
        Remove-Item -LiteralPath $TemporaryRoot -Recurse -Force `
            -ErrorAction SilentlyContinue
    }
}

function Add-UserPathEntry {
    param([Parameter(Mandatory = $true)][string]$PathEntry)

    $CanonicalEntry = [IO.Path]::GetFullPath($PathEntry).TrimEnd("\")
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $Entries = @(
        $UserPath -split ";" |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $Exists = $false
    foreach ($Entry in $Entries) {
        try {
            if (
                [IO.Path]::GetFullPath($Entry).TrimEnd("\") -ieq $CanonicalEntry
            ) {
                $Exists = $true
                break
            }
        }
        catch {
            if ($Entry.TrimEnd("\") -ieq $CanonicalEntry) {
                $Exists = $true
                break
            }
        }
    }

    if (-not $Exists) {
        $NewPath = (@($Entries) + $CanonicalEntry) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
    }

    if ($CanonicalEntry -notin @($env:Path -split ";")) {
        $env:Path = "$CanonicalEntry;$env:Path"
    }
}

function Initialize-PythonEnvironment {
    if (-not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
        Write-Info "Creating the IT 140 Python virtual environment."
        & python.exe -m venv $VenvDirectory
        if ($LASTEXITCODE -ne 0) {
            throw "The course Python virtual environment could not be created."
        }
    }

    Write-Info "Installing or repairing course Python tools."
    & $VenvPython -m pip install `
        --upgrade `
        pip `
        pytest `
        pytest-cov `
        ruff
    if ($LASTEXITCODE -ne 0) {
        throw "The course Python tools could not be installed."
    }
}

function Set-GitHubIdentity {
    param([Parameter(Mandatory = $true)]$Manifest)

    & gh.exe auth status --hostname github.com *> $null
    if ($LASTEXITCODE -ne 0) {
        if ($NonInteractive) {
            throw "GitHub authentication requires an interactive configure run."
        }

        Write-Notice "GitHub authentication is required."
        Write-Notice (
            "A browser window will open. Complete the GitHub device flow and " +
            "return to this terminal."
        )
        $Confirmation = Read-Host "Press ENTER to continue, or type CANCEL"
        if ($Confirmation -match "^(?i:cancel)$") {
            throw [OperationCanceledException]::new(
                "GitHub authentication was canceled."
            )
        }

        & gh.exe auth login `
            --hostname github.com `
            --git-protocol https `
            --web
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub authentication did not complete."
        }

        & gh.exe auth status --hostname github.com *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub authentication could not be verified."
        }
    }

    $GitHubUser = (& gh.exe api user --jq ".login").Trim()
    $GitHubId = (& gh.exe api user --jq ".id").Trim()
    if ($LASTEXITCODE -ne 0 -or -not $GitHubUser -or -not $GitHubId) {
        throw "The GitHub account identity could not be retrieved."
    }

    if ($NonInteractive) {
        $GitDisplayName = $GitHubUser
    }
    else {
        Write-Host ""
        Write-Notice (
            "The Git display name is public in version-control history."
        )
        $InputName = Read-Host (
            "Press ENTER to use '$GitHubUser', or enter another display name"
        )
        if ([string]::IsNullOrWhiteSpace($InputName)) {
            $GitDisplayName = $GitHubUser
        }
        else {
            $GitDisplayName = $InputName.Trim()
        }
    }

    if ($GitDisplayName.Length -gt 100 -or $GitDisplayName -match "[`r`n]") {
        throw "The Git display name is not valid."
    }

    $PrivateEmail = "{0}+{1}@users.noreply.github.com" -f `
        $GitHubId, $GitHubUser

    & git.exe config --global user.name $GitDisplayName
    & git.exe config --global user.email $PrivateEmail
    if ($LASTEXITCODE -ne 0) {
        throw "The privacy-preserving Git identity could not be configured."
    }

    $GitSettings = Get-PropertyValue `
        -Object $Manifest.managed_settings `
        -Name "git_course_defaults"

    if ($null -eq $GitSettings) {
        throw "The controlled Git settings profile is missing."
    }

    foreach ($Property in $GitSettings.values.PSObject.Properties) {
        $Value = $Property.Value
        if ($Value -is [bool]) {
            $Value = $Value.ToString().ToLowerInvariant()
        }
        & git.exe config --global $Property.Name ([string]$Value)
        if ($LASTEXITCODE -ne 0) {
            throw "Git setting failed: $($Property.Name)"
        }
    }

    Write-Success "GitHub authentication and private Git identity are configured."
    Write-Info "GitHub user     : $GitHubUser"
    Write-Info "Git display name: $GitDisplayName"
    Write-Info "Git email       : private GitHub noreply address configured"
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

function Install-VsCodeExtensions {
    param([Parameter(Mandatory = $true)][string[]]$Extensions)

    $env:NODE_NO_WARNINGS = "1"
    try {
        foreach ($Extension in $Extensions) {
            Write-Info "Installing or repairing VS Code extension: $Extension"
            & code.cmd --install-extension $Extension --force
            if ($LASTEXITCODE -ne 0) {
                throw "VS Code extension installation failed: $Extension"
            }
        }
    }
    finally {
        Remove-Item Env:NODE_NO_WARNINGS -ErrorAction SilentlyContinue
    }
}

function Merge-Hashtable {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Target,
        [Parameter(Mandatory = $true)][hashtable]$Source
    )

    foreach ($Key in $Source.Keys) {
        if (
            $Source[$Key] -is [hashtable] -and
            $Target.ContainsKey($Key) -and
            $Target[$Key] -is [hashtable]
        ) {
            Merge-Hashtable -Target $Target[$Key] -Source $Source[$Key]
        }
        else {
            $Target[$Key] = $Source[$Key]
        }
    }
}

function ConvertTo-Hashtable {
    param($InputObject)

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [Collections.IDictionary]) {
        $Result = @{}
        foreach ($Key in $InputObject.Keys) {
            $Result[$Key] = ConvertTo-Hashtable $InputObject[$Key]
        }
        return $Result
    }
    if ($InputObject -is [pscustomobject]) {
        $Result = @{}
        foreach ($Property in $InputObject.PSObject.Properties) {
            $Result[$Property.Name] = ConvertTo-Hashtable $Property.Value
        }
        return $Result
    }
    if (
        $InputObject -is [Collections.IEnumerable] -and
        $InputObject -isnot [string]
    ) {
        return @($InputObject | ForEach-Object { ConvertTo-Hashtable $_ })
    }
    return $InputObject
}

function Merge-VsCodeSettings {
    param([Parameter(Mandatory = $true)]$Manifest)

    $SettingsProfile = Get-PropertyValue `
        -Object $Manifest.managed_settings `
        -Name "vscode_course_defaults"
    if ($null -eq $SettingsProfile) {
        throw "The controlled VS Code settings profile is missing."
    }

    $SettingsDirectory = Split-Path -Parent $VsCodeSettings
    New-Item -ItemType Directory -Path $SettingsDirectory -Force | Out-Null

    $Existing = @{}
    if (Test-Path -LiteralPath $VsCodeSettings -PathType Leaf) {
        try {
            $ExistingObject = Get-Content -LiteralPath $VsCodeSettings -Raw |
                ConvertFrom-Json
            $Existing = ConvertTo-Hashtable $ExistingObject
        }
        catch {
            $DiagnosticPath = "$VsCodeSettings.invalid.$(
                Get-Date -Format 'yyyyMMdd_HHmmss'
            )"
            Copy-Item `
                -LiteralPath $VsCodeSettings `
                -Destination $DiagnosticPath `
                -Force
            throw (
                "VS Code settings are invalid JSON. A diagnostic copy was " +
                "saved as $DiagnosticPath."
            )
        }
    }

    $Managed = ConvertTo-Hashtable $SettingsProfile.values
    $Managed["python.defaultInterpreterPath"] = $VenvPython
    Merge-Hashtable -Target $Existing -Source $Managed

    $StagedPath = "$VsCodeSettings.it140.tmp"
    $BackupPath = "$VsCodeSettings.it140.bak"
    $Existing | ConvertTo-Json -Depth 50 |
        Set-Content -LiteralPath $StagedPath -Encoding UTF8

    try {
        $null = Get-Content -LiteralPath $StagedPath -Raw | ConvertFrom-Json
        if (Test-Path -LiteralPath $VsCodeSettings -PathType Leaf) {
            Copy-Item `
                -LiteralPath $VsCodeSettings `
                -Destination $BackupPath `
                -Force
        }
        Move-Item `
            -LiteralPath $StagedPath `
            -Destination $VsCodeSettings `
            -Force
    }
    catch {
        Remove-Item -LiteralPath $StagedPath -Force `
            -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $BackupPath -PathType Leaf) {
            Copy-Item `
                -LiteralPath $BackupPath `
                -Destination $VsCodeSettings `
                -Force
        }
        throw
    }
}

function Set-CourseShortcut {
    $Desktop = [Environment]::GetFolderPath("Desktop")
    $ShortcutPath = Join-Path $Desktop "IT 140.lnk"
    $Shell = New-Object -ComObject WScript.Shell
    $Shortcut = $Shell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $CourseRoot
    $Shortcut.WorkingDirectory = $CourseRoot
    $Shortcut.IconLocation = "%SystemRoot%\System32\shell32.dll,3"
    $Shortcut.Save()
}

function Remove-ExpiredLogs {
    Get-ChildItem -LiteralPath $LogDirectory -File `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-180) } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $Logs = @(
        Get-ChildItem -LiteralPath $LogDirectory -File `
            -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )
    if ($Logs.Count -gt 50) {
        $Logs | Select-Object -Skip 50 |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Show-Usage {
    @"
IT 140 Windows configure script

Usage:
  powershell.exe -ExecutionPolicy Bypass -File .\configure_win.ps1
  powershell.exe -ExecutionPolicy Bypass -File .\configure_win.ps1 -NonInteractive
  powershell.exe -ExecutionPolicy Bypass -File .\configure_win.ps1 -Help

Run this script from a normal, non-elevated PowerShell terminal.
Deployment profile: windows_bare_metal
Logs: $LogDirectory
"@ | Write-Host
}

try {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    Start-Transcript -Path $LogPath -Append -Force | Out-Null
    $TranscriptStarted = $true
    Remove-ExpiredLogs

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
    Write-Host "IT 140 WINDOWS CONFIGURATION"
    Write-Host "============================================================"
    Write-Info "Script version   : $ScriptVersion"
    Write-Info "Deployment       : $DeploymentProfile"
    Write-Info "Current user     : $([Environment]::UserName)"
    Write-Info "Log file         : $LogPath"

    if (Test-IsAdministrator) {
        Write-ErrorMessage (
            "Do not run configure_win.ps1 from an elevated terminal."
        )
        $ExitCode = 3
        return
    }

    $MutationMutex = Enter-MutationLock
    Update-ProcessEnvironment
    Assert-SystemLayer
    Initialize-CourseRepository

    $Controlled = Read-ControlledManifest
    $WindowsFacts = Get-WindowsFacts
    Assert-SupportedWindows `
        -WindowsFacts $WindowsFacts `
        -Platform $Controlled.Platform

    New-Item -ItemType Directory -Path $CourseRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

    Add-UserPathEntry -PathEntry $WindowsScriptDirectory
    Initialize-PythonEnvironment
    Add-UserPathEntry -PathEntry $VenvScripts

    Set-GitHubIdentity -Manifest $Controlled.Manifest

    $Extensions = Get-RequiredExtensions -Platform $Controlled.Platform
    Install-VsCodeExtensions -Extensions $Extensions
    Merge-VsCodeSettings -Manifest $Controlled.Manifest
    Set-CourseShortcut

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "CONFIGURATION SUMMARY"
    Write-Host "============================================================"
    Write-Success "The current Windows user is configured for IT 140."
    Write-Info "Course folder    : $CourseRoot"
    Write-Info "Python environment: $VenvDirectory"
    Write-Info "VS Code settings : $VsCodeSettings"
    Write-Info "Log file         : $LogPath"
    Write-Notice "Next step: run verify_win.ps1."
    $ExitCode = 0
}
catch [OperationCanceledException] {
    Write-Notice $_.Exception.Message
    Write-Info "Configuration log: $LogPath"
    $ExitCode = 6
}
catch {
    Write-ErrorMessage $_.Exception.Message
    Write-Notice "Review the configuration log before requesting support."
    Write-Info "Configuration log: $LogPath"
    $ExitCode = 1
}
finally {
    if ($null -ne $MutationMutex) {
        try {
            $MutationMutex.ReleaseMutex()
        }
        catch {
        }
        $MutationMutex.Dispose()
    }

    if ($TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
        }
    }
}

exit $ExitCode
