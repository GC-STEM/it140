#requires -Version 5.1
<#
.SYNOPSIS
Prepares Windows Sandbox for the IT 140 Windows user configuration workflow.

.DESCRIPTION
Validates the controlled IT 140 manifest and its windows_sandbox deployment
profile, installs Windows Package Manager when the sandbox image does not
provide it, and installs the manifest-required Windows software. The script
does not run Windows Update and does not configure personal GitHub, Git,
Python-environment, or VS Code settings.

After successful setup, the sandbox is ready for config_win.ps1 and
verify_win.ps1. A normal PowerShell continuation shortcut is created on the
desktop and opened automatically for interactive runs.

.NOTES
Exit codes:
  0 Success
  1 Required operation failed
  2 Unsupported Windows Sandbox platform or Windows release
  3 Administrator privilege is unavailable
  4 Required network or package-retrieval operation failed
  5 Controlled manifest or managed asset validation failed
  7 Managed state changed before the operation stopped

Logs are written under ~/it140/logs/.
#>

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Version,
    [switch]$NonInteractive,
    [ValidateSet("windows_sandbox")]
    [string]$DeploymentProfile = "windows_sandbox"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ScriptVersion = "2026.07.27.3"
$PlatformId = "windows"
$PlatformAbbreviation = "wsb"
$ScriptDirectory = $PSScriptRoot
$WindowsScriptDirectory = Split-Path -Parent $ScriptDirectory
$ScriptRoot = Split-Path -Parent $WindowsScriptDirectory
$CourseRoot = Split-Path -Parent $ScriptRoot
$ManifestPath = Join-Path $ScriptRoot ".manifest\it140_manifest.json"
$SchemaPath = Join-Path $ScriptRoot ".manifest\it140_manifest.schema.json"
$LogDirectory = Join-Path $CourseRoot "logs"
$LogPath = Join-Path $LogDirectory (
    "setup_{0}_{1}.log" -f $PlatformAbbreviation, (Get-Date -Format "yyyyMMdd_HHmmss")
)
$ContinuationShortcutPath = Join-Path (
    [Environment]::GetFolderPath("Desktop")
) "Continue IT 140 Setup.lnk"
$StartTime = Get-Date
$TranscriptStarted = $false
$MutationMutex = $null
$Changed = $false
$WarningCount = 0
$ExitCode = 0
$FailureExitCode = 1
$WinGetExecutable = $null

function Write-Header {
    param([Parameter(Mandatory = $true)][string]$Title)

    Write-Host ""
    Write-Host "============================================================"
    Write-Host $Title
    Write-Host "============================================================"
}

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

function Write-WarningMessage {
    param([Parameter(Mandatory = $true)][string]$Message)

    $script:WarningCount++
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorMessage {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Show-Usage {
    @"
IT 140 Windows Sandbox setup script

Usage:
  powershell.exe -ExecutionPolicy Bypass -File "$PSCommandPath"
  powershell.exe -ExecutionPolicy Bypass -File "$PSCommandPath" -NonInteractive
  powershell.exe -ExecutionPolicy Bypass -File "$PSCommandPath" -Help
  powershell.exe -ExecutionPolicy Bypass -File "$PSCommandPath" -Version

This script installs WinGet when needed and then installs missing
manifest-required Windows software. It does not run Windows Update or configure
personal user settings.

Deployment profile: $DeploymentProfile
Log directory: $LogDirectory
"@ | Write-Host
}

function Test-IsAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
    return $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Invoke-ElevatedSelf {
    $ArgumentText = (
        '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f
        $PSCommandPath
    )
    if ($NonInteractive) {
        $ArgumentText += " -NonInteractive"
    }

    try {
        $ElevatedProcess = Start-Process `
            -FilePath "powershell.exe" `
            -Verb RunAs `
            -ArgumentList $ArgumentText `
            -Wait `
            -PassThru
        exit $ElevatedProcess.ExitCode
    }
    catch {
        Write-ErrorMessage (
            "Administrator privilege is required and elevation failed. " +
            $_.Exception.Message
        )
        exit 3
    }
}

function Test-IsWindowsSandbox {
    return [Environment]::UserName -eq "WDAGUtilityAccount"
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }

    $PropertyRecord = $Object.PSObject.Properties[$Name]
    if ($null -eq $PropertyRecord) {
        return $null
    }

    return $PropertyRecord.Value
}

function Get-NormalizedPathEntry {
    param([Parameter(Mandatory = $true)][string]$PathEntry)

    try {
        $Expanded = [Environment]::ExpandEnvironmentVariables($PathEntry)
        return [IO.Path]::GetFullPath($Expanded).TrimEnd("\")
    }
    catch {
        return $PathEntry.Trim().TrimEnd("\")
    }
}

function Set-UserPathEntry {
    param([Parameter(Mandatory = $true)][string]$PathEntry)

    $NormalizedTarget = Get-NormalizedPathEntry -PathEntry $PathEntry
    $ExistingUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $PreservedEntries = [Collections.Generic.List[string]]::new()

    foreach ($Entry in @($ExistingUserPath -split ";")) {
        if ([string]::IsNullOrWhiteSpace($Entry)) {
            continue
        }
        if ((Get-NormalizedPathEntry -PathEntry $Entry) -ieq $NormalizedTarget) {
            continue
        }
        $PreservedEntries.Add($Entry.Trim())
    }

    $NewUserPath = (@($PathEntry) + @($PreservedEntries)) -join ";"
    if ($NewUserPath -cne [string]$ExistingUserPath) {
        [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
        $script:Changed = $true
    }
}

function Update-ProcessEnvironment {
    $MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = @($MachinePath, $UserPath) -join ";"

    $CandidateDirectories = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312"),
        (Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\Scripts"),
        (Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\bin"),
        (Join-Path $env:ProgramFiles "Git\cmd"),
        (Join-Path $env:ProgramFiles "GitHub CLI"),
        (Join-Path $env:ProgramFiles "Microsoft VS Code\bin")
    )

    foreach ($CandidateDirectory in $CandidateDirectories) {
        if (
            (Test-Path -LiteralPath $CandidateDirectory -PathType Container) -and
            $CandidateDirectory -notin @($env:Path -split ";")
        ) {
            $env:Path = "$CandidateDirectory;$env:Path"
        }
    }
}

function Read-ControlledManifest {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "The controlled manifest is missing: $ManifestPath"
    }
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
        throw "The controlled manifest schema is missing: $SchemaPath"
    }

    try {
        $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
        $Schema = Get-Content -LiteralPath $SchemaPath -Raw | ConvertFrom-Json
    }
    catch {
        throw "The controlled manifest or schema is not valid JSON. $($_.Exception.Message)"
    }

    $RequiredKeys = @(
        "schema_version",
        "automation_release",
        "policy",
        "software_sources",
        "platforms",
        "deployment_profiles",
        "logging"
    )
    foreach ($RequiredKey in $RequiredKeys) {
        if ($null -eq $Manifest.PSObject.Properties[$RequiredKey]) {
            throw "The controlled manifest is missing required key: $RequiredKey"
        }
    }

    if ([string]$Manifest.schema_version -ne "1.0") {
        throw "Unsupported manifest schema version: $($Manifest.schema_version)"
    }
    if ([string]$Schema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema") {
        throw "The manifest schema is not the approved Draft 2020-12 format."
    }

    $Platform = Get-PropertyValue -Object $Manifest.platforms -Name $PlatformId
    $Profile = Get-PropertyValue `
        -Object $Manifest.deployment_profiles `
        -Name $DeploymentProfile

    if ($null -eq $Platform -or -not [bool]$Platform.enabled) {
        throw "The Windows platform is not enabled in the controlled manifest."
    }
    if ($null -eq $Profile -or -not [bool]$Profile.enabled) {
        throw "The deployment profile is not enabled: $DeploymentProfile"
    }
    if ([string]$Profile.platform_id -ne $PlatformId) {
        throw "The Windows Sandbox deployment profile does not select the Windows platform."
    }
    if ([string]$Profile.profile_adapter_id -ne "windows_sandbox") {
        throw "The deployment profile does not select the windows_sandbox adapter."
    }
    if ([string]$Profile.architecture -ne "x86_64") {
        throw "The Windows Sandbox deployment profile is not enabled for x86_64."
    }

    return [pscustomobject]@{
        Manifest = $Manifest
        Platform = $Platform
        Profile = $Profile
    }
}

function Get-OperatingSystemFact {
    $CurrentVersion = Get-ItemProperty `
        -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"

    $BuildNumber = [string][Environment]::OSVersion.Version.Build
    $Caption = [string]$CurrentVersion.ProductName
    if ([int]$BuildNumber -ge 22000 -and $Caption -notmatch "Windows 11") {
        $Caption = $Caption -replace "Windows 10", "Windows 11"
    }

    $DisplayVersion = [string]$CurrentVersion.DisplayVersion
    if ([string]::IsNullOrWhiteSpace($DisplayVersion)) {
        $DisplayVersion = [string]$CurrentVersion.ReleaseId
    }

    return [pscustomobject]@{
        Caption = $Caption
        Architecture = if ([Environment]::Is64BitOperatingSystem) {
            "64-bit"
        }
        else {
            "32-bit"
        }
        DisplayVersion = $DisplayVersion
        BuildNumber = $BuildNumber
    }
}

function Test-SupportedOperatingSystem {
    param(
        [Parameter(Mandatory = $true)]$WindowsFacts,
        [Parameter(Mandatory = $true)]$Platform
    )

    if (-not (Test-IsWindowsSandbox)) {
        throw "This script supports only Windows Sandbox using WDAGUtilityAccount."
    }
    if ($WindowsFacts.Caption -notmatch "Windows 11") {
        throw "This script supports only Microsoft Windows 11. Detected: $($WindowsFacts.Caption)"
    }
    if ($WindowsFacts.Architecture -ne "64-bit") {
        throw "This release supports only x64 Windows. Detected: $($WindowsFacts.Architecture)"
    }

    $SupportedReleases = @(
        $Platform.os.releases | ForEach-Object { [string]$_.release_id }
    )
    if ($WindowsFacts.DisplayVersion -notin $SupportedReleases) {
        throw (
            "Windows release {0} is not enabled. Supported releases: {1}" -f
            $WindowsFacts.DisplayVersion,
            ($SupportedReleases -join ", ")
        )
    }
}

function Enter-MutationLock {
    $CreatedNew = $false
    $Mutex = [Threading.Mutex]::new(
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

function Remove-ExpiredLog {
    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        return
    }

    Get-ChildItem -LiteralPath $LogDirectory -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-180) } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $LogFiles = @(
        Get-ChildItem -LiteralPath $LogDirectory -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )
    if ($LogFiles.Count -gt 50) {
        $LogFiles | Select-Object -Skip 50 |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $PartialPath = "$Destination.part"
    Remove-Item -LiteralPath $PartialPath -Force -ErrorAction SilentlyContinue

    Write-Info "Downloading $Description."
    & curl.exe `
        --location `
        --fail `
        --show-error `
        --retry 10 `
        --retry-delay 5 `
        --retry-all-errors `
        --continue-at - `
        --output $PartialPath `
        $Uri
    if ($LASTEXITCODE -ne 0) {
        throw "$Description download failed with curl exit code $LASTEXITCODE."
    }

    Move-Item `
        -LiteralPath $PartialPath `
        -Destination $Destination `
        -Force
}

function Get-WinGetExecutable {
    Update-ProcessEnvironment

    $WinGetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($null -ne $WinGetCommand) {
        return $WinGetCommand.Source
    }

    $AppInstaller = Get-AppxPackage `
        -Name Microsoft.DesktopAppInstaller `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $AppInstaller) {
        $CandidatePath = Join-Path $AppInstaller.InstallLocation "winget.exe"
        if (Test-Path -LiteralPath $CandidatePath -PathType Leaf) {
            $env:Path = "$($AppInstaller.InstallLocation);$env:Path"
            return $CandidatePath
        }
    }

    return $null
}

function Get-DependencyPriority {
    param([Parameter(Mandatory = $true)][string]$FileName)

    if ($FileName -match "(?i)VCLibs") {
        return 10
    }
    if ($FileName -match "(?i)UI.Xaml") {
        return 20
    }
    if ($FileName -match "(?i)WindowsAppRuntime") {
        return 30
    }
    return 40
}

function Install-WinGet {
    param([Parameter(Mandatory = $true)]$Manifest)

    $script:WinGetExecutable = Get-WinGetExecutable
    if (-not [string]::IsNullOrWhiteSpace($script:WinGetExecutable)) {
        Write-Success "Windows Package Manager is available."
        return
    }

    $AppInstallerSource = Get-PropertyValue `
        -Object $Manifest.software_sources `
        -Name "microsoft_app_installer"
    if ($null -eq $AppInstallerSource) {
        throw "The manifest does not define the Microsoft App Installer source."
    }

    $TemporaryDirectory = Join-Path (
        [IO.Path]::GetTempPath()
    ) ("it140-winget-{0}" -f ([guid]::NewGuid().ToString("N")))
    $DependenciesZip = Join-Path $TemporaryDirectory "DesktopAppInstaller_Dependencies.zip"
    $DependenciesDirectory = Join-Path $TemporaryDirectory "Dependencies"
    $AppInstallerBundle = Join-Path $TemporaryDirectory "Microsoft.DesktopAppInstaller.msixbundle"
    $DependenciesUri = (
        "https://github.com/microsoft/winget-cli/releases/latest/download/" +
        "DesktopAppInstaller_Dependencies.zip"
    )
    $BundleUri = [string]$AppInstallerSource.base_uri

    try {
        New-Item -ItemType Directory -Path $TemporaryDirectory -Force | Out-Null
        New-Item -ItemType Directory -Path $DependenciesDirectory -Force | Out-Null

        Invoke-Download `
            -Uri $DependenciesUri `
            -Destination $DependenciesZip `
            -Description "WinGet dependencies"
        Invoke-Download `
            -Uri $BundleUri `
            -Destination $AppInstallerBundle `
            -Description "Microsoft App Installer"

        Write-Info "Expanding and installing WinGet dependencies."
        Expand-Archive `
            -LiteralPath $DependenciesZip `
            -DestinationPath $DependenciesDirectory `
            -Force

        $DependencyPackages = @(
            Get-ChildItem `
                -LiteralPath $DependenciesDirectory `
                -Recurse `
                -File |
                Where-Object {
                    $_.Extension -in ".appx", ".msix" -and
                    $_.FullName -match "(?i)(x64|neutral)"
                } |
                ForEach-Object {
                    [pscustomobject]@{
                        Path = $_.FullName
                        Name = $_.Name
                        Priority = Get-DependencyPriority -FileName $_.Name
                    }
                } |
                Sort-Object Priority, Name
        )
        if ($DependencyPackages.Count -eq 0) {
            throw "The WinGet dependency archive contains no x64 packages."
        }

        foreach ($DependencyPackage in $DependencyPackages) {
            try {
                Add-AppxPackage `
                    -Path $DependencyPackage.Path `
                    -ErrorAction Stop
            }
            catch {
                if ($_.Exception.Message -match "0x80073D06|higher version") {
                    Write-Notice "$($DependencyPackage.Name) is already satisfied."
                }
                else {
                    throw
                }
            }
        }

        Write-Info "Installing Microsoft App Installer."
        Add-AppxPackage -Path $AppInstallerBundle -ErrorAction Stop
        $script:Changed = $true

        $script:WinGetExecutable = Get-WinGetExecutable
        if ([string]::IsNullOrWhiteSpace($script:WinGetExecutable)) {
            throw "Microsoft App Installer completed, but winget.exe is unavailable."
        }

        Write-Success "Windows Package Manager was installed."
    }
    finally {
        Remove-Item `
            -LiteralPath $TemporaryDirectory `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

function Invoke-WinGet {
    param(
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$Operation,
        [int[]]$SuccessExitCode = @(0)
    )

    if ([string]::IsNullOrWhiteSpace($script:WinGetExecutable)) {
        throw "winget.exe has not been initialized."
    }

    Write-Info $Operation
    & $script:WinGetExecutable @ArgumentList
    $CommandExitCode = $LASTEXITCODE
    if ($CommandExitCode -notin $SuccessExitCode) {
        throw "$Operation failed with exit code $CommandExitCode."
    }
}

function Get-SystemPackageBinding {
    param([Parameter(Mandatory = $true)]$Platform)

    $Bindings = @()
    foreach ($PropertyRecord in $Platform.course_ide_bindings.PSObject.Properties) {
        $Binding = $PropertyRecord.Value
        if (
            [bool]$Binding.required -and
            [string]$Binding.installation_scope -eq "system" -and
            [string]$Binding.installer_adapter_id -eq "winget_package"
        ) {
            $Bindings += [pscustomobject]@{
                Role = $PropertyRecord.Name
                PackageIdentifier = [string]$Binding.package_identifier
                ExecutableNames = @($Binding.verification.executable_names)
            }
        }
    }

    if ($Bindings.Count -eq 0) {
        throw "The controlled manifest declares no required Windows system packages."
    }

    return $Bindings
}

function Test-WinGetPackageInstalled {
    param([Parameter(Mandatory = $true)][string]$PackageIdentifier)

    $Output = @(
        & $script:WinGetExecutable `
            list `
            --id $PackageIdentifier `
            --exact `
            --source winget `
            --accept-source-agreements `
            --disable-interactivity 2>&1
    )
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return (($Output -join "`n") -match [regex]::Escape($PackageIdentifier))
}

function Install-SystemPackage {
    param([Parameter(Mandatory = $true)]$Bindings)

    foreach ($Binding in $Bindings) {
        $PackageIdentifier = [string]$Binding.PackageIdentifier

        if (Test-WinGetPackageInstalled -PackageIdentifier $PackageIdentifier) {
            Write-Success "$PackageIdentifier is already installed."
            continue
        }

        Invoke-WinGet `
            -ArgumentList @(
                "install",
                "--id", $PackageIdentifier,
                "--exact",
                "--source", "winget",
                "--silent",
                "--disable-interactivity",
                "--accept-source-agreements",
                "--accept-package-agreements",
                "--verbose-logs"
            ) `
            -Operation "Installing $PackageIdentifier."

        $script:Changed = $true
        Update-ProcessEnvironment
    }

    Write-Success "Manifest-required Windows software is installed."
}

function Test-SystemLayer {
    param(
        [Parameter(Mandatory = $true)]$Bindings,
        [Parameter(Mandatory = $true)]$Platform
    )

    Update-ProcessEnvironment

    $MissingCommands = @()
    foreach ($Binding in $Bindings) {
        foreach ($ExecutableName in @($Binding.ExecutableNames)) {
            if ($null -eq (Get-Command $ExecutableName -ErrorAction SilentlyContinue)) {
                $MissingCommands += [string]$ExecutableName
            }
        }
    }
    if ($null -eq (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        if (-not (Test-Path -LiteralPath $script:WinGetExecutable -PathType Leaf)) {
            $MissingCommands += "winget.exe"
        }
    }
    if ($MissingCommands.Count -gt 0) {
        throw "Required commands are missing: $($MissingCommands -join ', ')"
    }

    $RuntimeBinding = Get-PropertyValue `
        -Object $Platform.course_ide_bindings `
        -Name "programming_language_runtime"
    $RuntimeExecutable = [string]$RuntimeBinding.verification.executable_names[0]
    $PythonVersion = & $RuntimeExecutable -c (
        "import sys; print('.'.join(map(str, sys.version_info[:2])))"
    )
    if ($LASTEXITCODE -ne 0 -or [string]$PythonVersion -ne "3.12") {
        throw "The required Python 3.12 runtime is not active."
    }

    foreach ($Binding in $Bindings) {
        if (-not (Test-WinGetPackageInstalled -PackageIdentifier $Binding.PackageIdentifier)) {
            throw "WinGet does not report the required package: $($Binding.PackageIdentifier)"
        }
    }

    Write-Success "System-layer post-validation passed."
}

function Get-CommandVersionLine {
    param([Parameter(Mandatory = $true)][string]$CommandName)

    try {
        $VersionOutput = @(& $CommandName --version 2>&1)
        if ($LASTEXITCODE -eq 0 -and $VersionOutput.Count -gt 0) {
            return [string]$VersionOutput[0]
        }
    }
    catch {
        # Best-effort reporting; preserve the primary result.
    }

    return "unavailable"
}

function New-ContinuationShortcut {
    $DesktopDirectory = [Environment]::GetFolderPath("Desktop")
    if ([string]::IsNullOrWhiteSpace($DesktopDirectory)) {
        throw "The Windows Desktop directory could not be resolved."
    }

    $PowerShellPath = Join-Path `
        $env:SystemRoot `
        "System32\WindowsPowerShell\v1.0\powershell.exe"
    $CommandText = (
        "Set-Location -LiteralPath '$CourseRoot'; " +
        "Write-Host ''; " +
        "Write-Host 'IT 140 Windows Sandbox is ready.' -ForegroundColor Green; " +
        "Write-Host 'Run config_win.ps1 to configure the current user.' -ForegroundColor Cyan; " +
        "Write-Host 'After configuration, open a new PowerShell window and run verify_win.ps1.' -ForegroundColor Cyan"
    )

    $ShellApplication = New-Object -ComObject WScript.Shell
    $Shortcut = $ShellApplication.CreateShortcut($ContinuationShortcutPath)
    $Shortcut.TargetPath = $PowerShellPath
    $Shortcut.Arguments = (
        '-NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass -Command "{0}"' -f
        $CommandText
    )
    $Shortcut.WorkingDirectory = $CourseRoot
    $Shortcut.IconLocation = "$PowerShellPath,0"
    $Shortcut.Description = "Continue the IT 140 Windows Sandbox setup"
    $Shortcut.Save()

    Write-Success "The continuation shortcut is available on the desktop."
}

function Start-ContinuationShell {
    try {
        & "$env:SystemRoot\explorer.exe" $ContinuationShortcutPath
        Write-Notice "A normal PowerShell continuation window is opening."
    }
    catch {
        Write-WarningMessage (
            "The continuation window could not be opened automatically. " +
            "Use the desktop shortcut instead."
        )
    }
}

if ($Help) {
    Show-Usage
    exit 0
}
if ($Version) {
    Write-Host $ScriptVersion
    exit 0
}
if (-not (Test-IsWindowsSandbox)) {
    Write-ErrorMessage "This script supports only Windows Sandbox."
    exit 2
}
if (-not (Test-IsAdministrator)) {
    Invoke-ElevatedSelf
}

try {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    Start-Transcript -Path $LogPath -Append -Force | Out-Null
    $TranscriptStarted = $true
    Remove-ExpiredLog

    Write-Header "IT 140 WINDOWS SANDBOX SETUP"
    Write-Info "Script version   : $ScriptVersion"
    Write-Info "Deployment       : $DeploymentProfile"
    Write-Info "Current user     : $([Environment]::UserName)"
    Write-Info "Course root      : $CourseRoot"
    Write-Info "Log file         : $LogPath"
    Write-Notice "This script prepares the Windows Sandbox system layer."
    Write-Notice "It does not run Windows Update or configure personal settings."

    $MutationMutex = Enter-MutationLock

    $FailureExitCode = 5
    $Controlled = Read-ControlledManifest

    $FailureExitCode = 2
    $WindowsFacts = Get-OperatingSystemFact
    Test-SupportedOperatingSystem `
        -WindowsFacts $WindowsFacts `
        -Platform $Controlled.Platform

    Write-Info "Operating system : $($WindowsFacts.Caption)"
    Write-Info "Release          : $($WindowsFacts.DisplayVersion)"
    Write-Info "Build            : $($WindowsFacts.BuildNumber)"
    Write-Info "Architecture     : $($WindowsFacts.Architecture)"
    Write-Info "Manifest release : $($Controlled.Manifest.automation_release)"

    $SystemDriveRoot = [IO.Path]::GetPathRoot($env:SystemRoot)
    $SystemDriveInfo = [IO.DriveInfo]::new($SystemDriveRoot)
    if (-not $SystemDriveInfo.IsReady) {
        throw "The system drive is not ready: $SystemDriveRoot"
    }

    $FreeSpace = [int64]$SystemDriveInfo.AvailableFreeSpace
    $MinimumSpace = [int64]$Controlled.Manifest.policy.minimum_free_space_bytes
    if ($FreeSpace -lt $MinimumSpace) {
        throw (
            "The system drive has {0:N1} GB free; at least {1:N1} GB is required." -f
            ($FreeSpace / 1GB),
            ($MinimumSpace / 1GB)
        )
    }

    $FailureExitCode = 4
    Install-WinGet -Manifest $Controlled.Manifest

    $Bindings = Get-SystemPackageBinding -Platform $Controlled.Platform
    Install-SystemPackage -Bindings $Bindings

    $FailureExitCode = 1
    Set-UserPathEntry -PathEntry $WindowsScriptDirectory
    Update-ProcessEnvironment
    Test-SystemLayer -Bindings $Bindings -Platform $Controlled.Platform
    New-ContinuationShortcut

    $Elapsed = (Get-Date) - $StartTime
    Write-Header "SETUP SUMMARY"
    Write-Success "Windows Sandbox is ready for config_win.ps1 and verify_win.ps1."
    Write-Info "Result           : PASS"
    Write-Info "Deployment       : $DeploymentProfile"
    Write-Info "Git              : $(Get-CommandVersionLine -CommandName 'git.exe')"
    Write-Info "GitHub CLI       : $(Get-CommandVersionLine -CommandName 'gh.exe')"
    Write-Info "Python           : $(Get-CommandVersionLine -CommandName 'python.exe')"
    Write-Info "VS Code          : $(Get-CommandVersionLine -CommandName 'code.cmd')"
    Write-Info "Warnings         : $WarningCount"
    Write-Info "Failures         : 0"
    Write-Info ("Elapsed time     : {0:hh\:mm\:ss}" -f $Elapsed)
    Write-Info "Log file         : $LogPath"
    Write-Notice "Next step: run config_win.ps1 from a normal PowerShell window."
    Write-Info "Exit code        : 0"

    if (-not $NonInteractive) {
        Start-ContinuationShell
    }

    $ExitCode = 0
}
catch {
    $LineNumber = $_.InvocationInfo.ScriptLineNumber
    Write-ErrorMessage $_.Exception.Message
    if ($LineNumber) {
        Write-ErrorMessage "Windows Sandbox setup stopped near line $LineNumber."
    }
    Write-Info "Setup log: $LogPath"

    if ($Changed) {
        Write-Notice (
            "Managed Windows Sandbox state changed before setup stopped. " +
            "Rerun setup_wsb.ps1 in this session or start a fresh sandbox."
        )
        $ExitCode = 7
    }
    else {
        $ExitCode = $FailureExitCode
    }
}
finally {
    if ($null -ne $MutationMutex) {
        try {
            $MutationMutex.ReleaseMutex()
        }
        catch {
            # Best-effort cleanup; preserve the primary result.
        }
        $MutationMutex.Dispose()
    }

    if ($TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
            # Best-effort cleanup; preserve the primary result.
        }
    }
}

exit $ExitCode
