#requires -Version 5.1
<#
.SYNOPSIS
Establishes or repairs the system-level IT 140 Course IDE on Windows.

.DESCRIPTION
Installs or repairs WinGet, Git, GitHub CLI, Python 3.12, and Visual Studio Code
for the current supported Windows 11 release. This script does not configure
personal Git identity, GitHub authentication, Python course tools, VS Code
extensions, or user preferences.

Run this script from an elevated Windows PowerShell terminal.
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
$ManifestPath = Join-Path $ScriptRoot ".manifest\it140_manifest.json"
$SchemaPath = Join-Path $ScriptRoot ".manifest\it140_manifest.schema.json"
$LogDirectory = Join-Path $CourseRoot "logs"
$LogPath = Join-Path $LogDirectory (
    "setup_win_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss")
)
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

    [Environment]::GetEnvironmentVariables("Machine").GetEnumerator() |
        ForEach-Object {
            Set-Item -Path ("Env:\{0}" -f $_.Key) -Value $_.Value
        }

    [Environment]::GetEnvironmentVariables("User").GetEnumerator() |
        ForEach-Object {
            Set-Item -Path ("Env:\{0}" -f $_.Key) -Value $_.Value
        }
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
    if ($null -eq $Platform -or -not [bool]$Platform.enabled) {
        throw "The Windows platform is not enabled in the controlled manifest."
    }

    $DeploymentProfileRecord = Get-PropertyValue `
        -Object $Manifest.deployment_profiles `
        -Name $DeploymentProfile
    if (
        $null -eq $DeploymentProfileRecord -or
        -not [bool]$DeploymentProfileRecord.enabled
    ) {
        throw "The deployment profile is not enabled: $DeploymentProfile"
    }
    if ([string]$DeploymentProfileRecord.platform_id -ne $PlatformId) {
        throw "The deployment profile does not select the Windows platform."
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
        throw (
            "Windows release {0} is not enabled. Supported releases: {1}" -f
            $WindowsFacts.DisplayVersion,
            ($SupportedReleases -join ", ")
        )
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

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    Write-Info $Operation
    & $FilePath @ArgumentList
    $Result = $LASTEXITCODE
    if ($Result -ne 0) {
        throw "$Operation failed with exit code $Result."
    }
}

function Invoke-CurlDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $Partial = "$Destination.part"
    New-Item -ItemType Directory -Path (Split-Path $Destination) -Force |
        Out-Null

    & curl.exe `
        --location `
        --fail `
        --show-error `
        --retry 10 `
        --retry-delay 5 `
        --retry-all-errors `
        --continue-at - `
        --output $Partial `
        $Uri

    if ($LASTEXITCODE -ne 0) {
        throw "Download failed: $Uri"
    }

    Move-Item -LiteralPath $Partial -Destination $Destination -Force
}

function Install-WinGetFallback {
    $TemporaryRoot = Join-Path $env:TEMP "it140-winget-install"
    $DependenciesZip = Join-Path $TemporaryRoot (
        "DesktopAppInstaller_Dependencies.zip"
    )
    $DependenciesDirectory = Join-Path $TemporaryRoot "Dependencies"
    $RuntimeInstaller = Join-Path $TemporaryRoot (
        "WindowsAppRuntimeInstall-x64.exe"
    )
    $WinGetBundle = Join-Path $TemporaryRoot (
        "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    )

    Remove-Item -LiteralPath $TemporaryRoot -Recurse -Force `
        -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $TemporaryRoot -Force | Out-Null

    try {
        Write-Info "Downloading the Windows App Runtime dependency."
        Invoke-CurlDownload `
            -Uri (
                "https://aka.ms/windowsappsdk/1.8/latest/" +
                "windowsappruntimeinstall-x64.exe"
            ) `
            -Destination $RuntimeInstaller

        Write-Info "Installing the Windows App Runtime dependency."
        $RuntimeProcess = Start-Process `
            -FilePath $RuntimeInstaller `
            -ArgumentList "--quiet" `
            -Wait `
            -PassThru
        if ($RuntimeProcess.ExitCode -ne 0) {
            throw (
                "Windows App Runtime installation failed with exit code {0}." -f
                $RuntimeProcess.ExitCode
            )
        }

        Write-Info "Downloading WinGet package dependencies."
        Invoke-CurlDownload `
            -Uri (
                "https://github.com/microsoft/winget-cli/releases/latest/" +
                "download/DesktopAppInstaller_Dependencies.zip"
            ) `
            -Destination $DependenciesZip

        Write-Info "Downloading Microsoft App Installer."
        Invoke-CurlDownload `
            -Uri (
                "https://github.com/microsoft/winget-cli/releases/latest/" +
                "download/Microsoft.DesktopAppInstaller_" +
                "8wekyb3d8bbwe.msixbundle"
            ) `
            -Destination $WinGetBundle

        Expand-Archive `
            -LiteralPath $DependenciesZip `
            -DestinationPath $DependenciesDirectory `
            -Force

        Get-ChildItem `
            -LiteralPath $DependenciesDirectory `
            -Recurse `
            -Filter "*.appx" |
            ForEach-Object {
                Add-AppxPackage -Path $_.FullName
            }

        Add-AppxPackage -Path $WinGetBundle
    }
    finally {
        Remove-Item -LiteralPath $TemporaryRoot -Recurse -Force `
            -ErrorAction SilentlyContinue
    }
}

function Initialize-WinGet {
    Update-ProcessEnvironment
    if ($null -ne (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Success "Windows Package Manager is available."
        return
    }

    Write-Info "Attempting to register Microsoft App Installer."
    try {
        Add-AppxPackage `
            -RegisterByFamilyName `
            -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
    }
    catch {
        Write-Notice (
            "App Installer registration did not complete: {0}" -f
            $_.Exception.Message
        )
    }

    Update-ProcessEnvironment
    if ($null -ne (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Success "Windows Package Manager was registered successfully."
        return
    }

    Write-Info "Attempting WinGet repair through Microsoft.WinGet.Client."
    try {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.SecurityProtocolType]::Tls12
        Install-PackageProvider -Name NuGet -Force | Out-Null
        Install-Module `
            -Name Microsoft.WinGet.Client `
            -Force `
            -Repository PSGallery `
            -Scope AllUsers `
            -AllowClobber
        Import-Module Microsoft.WinGet.Client -Force
        Repair-WinGetPackageManager -AllUsers
    }
    catch {
        Write-Notice (
            "The WinGet repair module did not complete: {0}" -f
            $_.Exception.Message
        )
    }

    Update-ProcessEnvironment
    if ($null -ne (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Success "Windows Package Manager was repaired successfully."
        return
    }

    Write-Notice "Using the direct Microsoft App Installer fallback."
    Install-WinGetFallback
    Update-ProcessEnvironment

    if ($null -eq (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "Windows Package Manager is still unavailable after repair."
    }

    Write-Success "Windows Package Manager was installed successfully."
}

function Get-SystemPackageBindings {
    param([Parameter(Mandatory = $true)]$Platform)

    $PreferredOrder = @(
        "version_control_system",
        "source_hosting_client",
        "programming_language_runtime",
        "source_code_ide"
    )

    $Bindings = @()
    foreach ($Role in $PreferredOrder) {
        $Binding = Get-PropertyValue `
            -Object $Platform.course_ide_bindings `
            -Name $Role
        if ($null -eq $Binding) {
            throw "Required Windows capability binding is missing: $Role"
        }
        if ([string]$Binding.installation_scope -ne "system") {
            continue
        }

        $Bindings += [pscustomobject]@{
            Role = $Role
            PackageIdentifier = [string]$Binding.package_identifier
        }
    }
    return $Bindings
}

function Install-SystemPackages {
    param([Parameter(Mandatory = $true)]$Bindings)

    Invoke-ExternalCommand `
        -FilePath "winget.exe" `
        -ArgumentList @(
            "source",
            "update",
            "--accept-source-agreements",
            "--disable-interactivity"
        ) `
        -Operation "Updating WinGet package sources."

    foreach ($Binding in $Bindings) {
        Invoke-ExternalCommand `
            -FilePath "winget.exe" `
            -ArgumentList @(
                "install",
                "--id", $Binding.PackageIdentifier,
                "--exact",
                "--source", "winget",
                "--scope", "machine",
                "--silent",
                "--disable-interactivity",
                "--accept-source-agreements",
                "--accept-package-agreements",
                "--verbose-logs"
            ) `
            -Operation (
                "Installing or repairing {0}." -f $Binding.PackageIdentifier
            )
    }

    Update-ProcessEnvironment
}

function Test-SystemCommands {
    $RequiredCommands = @("git.exe", "gh.exe", "python.exe", "code.cmd")
    $Missing = @()

    foreach ($Command in $RequiredCommands) {
        if ($null -eq (Get-Command $Command -ErrorAction SilentlyContinue)) {
            $Missing += $Command
        }
    }

    if ($Missing.Count -gt 0) {
        throw "Required commands are missing: $($Missing -join ', ')"
    }

    $PythonVersion = & python.exe -c (
        "import sys; print('.'.join(map(str, sys.version_info[:2])))"
    )
    if ($LASTEXITCODE -ne 0 -or [string]$PythonVersion -ne "3.12") {
        throw "The required Python 3.12 runtime is not active."
    }
}

function Remove-ExpiredLogs {
    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        return
    }

    Get-ChildItem -LiteralPath $LogDirectory -File |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-180) } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $Logs = @(
        Get-ChildItem -LiteralPath $LogDirectory -File |
            Sort-Object LastWriteTime -Descending
    )
    if ($Logs.Count -gt 50) {
        $Logs | Select-Object -Skip 50 |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Show-Usage {
    @"
IT 140 Windows setup script

Usage:
  powershell.exe -ExecutionPolicy Bypass -File .\setup_win.ps1
  powershell.exe -ExecutionPolicy Bypass -File .\setup_win.ps1 -Help
  powershell.exe -ExecutionPolicy Bypass -File .\setup_win.ps1 -Version

Run this script from an elevated Windows PowerShell terminal.
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
    Write-Host "IT 140 WINDOWS SETUP"
    Write-Host "============================================================"
    Write-Info "Script version   : $ScriptVersion"
    Write-Info "Deployment       : $DeploymentProfile"
    Write-Info "Current user     : $([Environment]::UserName)"
    Write-Info "Log file         : $LogPath"
    Write-Notice (
        "This script installs system software only. Run config_win.ps1 " +
        "after setup completes."
    )

    if (-not (Test-IsAdministrator)) {
        Write-ErrorMessage (
            "Setup requires an elevated Windows PowerShell terminal."
        )
        $ExitCode = 3
        return
    }

    $Controlled = Read-ControlledManifest
    $WindowsFacts = Get-WindowsFacts
    Assert-SupportedWindows `
        -WindowsFacts $WindowsFacts `
        -Platform $Controlled.Platform

    Write-Info "Operating system : $($WindowsFacts.Caption)"
    Write-Info "Release          : $($WindowsFacts.DisplayVersion)"
    Write-Info "Build            : $($WindowsFacts.BuildNumber)"
    Write-Info "Architecture     : $($WindowsFacts.Architecture)"
    Write-Info "Manifest release : $($Controlled.Manifest.automation_release)"

    $FreeSpace = (Get-PSDrive -Name $env:SystemDrive.TrimEnd(":")).Free
    if ($FreeSpace -lt [int64]$Controlled.Manifest.policy.minimum_free_space_bytes) {
        Write-ErrorMessage "The system drive does not have enough free space."
        $ExitCode = 1
        return
    }

    $MutationMutex = Enter-MutationLock
    Initialize-WinGet

    $Bindings = Get-SystemPackageBindings -Platform $Controlled.Platform
    Install-SystemPackages -Bindings $Bindings
    Test-SystemCommands

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "SETUP SUMMARY"
    Write-Host "============================================================"
    Write-Success "The system-level IT 140 Course IDE is installed."
    Write-Info "Git            : $(& git.exe --version)"
    Write-Info "GitHub CLI     : $((& gh.exe --version)[0])"
    Write-Info "Python         : $(& python.exe --version)"
    Write-Info "VS Code        : $((& code.cmd --version)[0])"
    Write-Info "Log file       : $LogPath"
    Write-Notice "Next step: run config_win.ps1 as the normal user."
    $ExitCode = 0
}
catch {
    Write-ErrorMessage $_.Exception.Message
    Write-Notice "Review the setup log and WinGet logs before requesting support."
    Write-Info "Setup log: $LogPath"
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
