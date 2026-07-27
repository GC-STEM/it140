#requires -Version 5.1
<#
.SYNOPSIS
Installs the system-level IT 140 Course IDE in Windows Sandbox.

.DESCRIPTION
Installs missing manifest-declared Windows software required by the IT 140
Course IDE in a fresh Windows Sandbox session. The script is intended for
course SMEs, faculty, and technical-support testing after bootstrap_wsb.ps1 and
bootstrap_win.ps1 have completed.

Unlike setup_win.ps1, this Windows Sandbox variant does not run Windows Update,
upgrade installed software, or force machine-scope WinGet installation. It
installs only missing packages and otherwise preserves the current ephemeral
sandbox image. Personal GitHub, Git, Python-environment, VS Code-extension, and
editor settings remain the responsibility of config_win.ps1.

Run this script from the Windows Sandbox Administrator PowerShell session.

.NOTES
Exit codes:
  0 Success
  1 Required operation failed
  2 Unsupported Windows Sandbox platform or Windows release
  3 Required administrator privilege is unavailable
  4 Required network or package-retrieval operation failed
  5 Controlled manifest or managed asset validation failed
  7 Managed state changed before the operation stopped

Logs are written under ~/it140/logs/.

.USAGE
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
& "$HOME\it140\scripts\win\wsb\setup_wsb.ps1"

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

$ScriptVersion = "2026.07.27.1"
$PlatformId = "windows"
$PlatformAbbreviation = "wsb"
$ManifestDeploymentProfile = "windows_bare_metal"
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
$StartTime = Get-Date
$TranscriptStarted = $false
$MutationMutex = $null
$Changed = $false
$WarningCount = 0
$ExitCode = 0
$FailureExitCode = 1

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
  powershell.exe -ExecutionPolicy Bypass -File "$HOME\it140\scripts\win\wsb\setup_wsb.ps1"
  powershell.exe -ExecutionPolicy Bypass -File "$HOME\it140\scripts\win\wsb\setup_wsb.ps1" -NonInteractive
  powershell.exe -ExecutionPolicy Bypass -File "$HOME\it140\scripts\win\wsb\setup_wsb.ps1" -Help
  powershell.exe -ExecutionPolicy Bypass -File "$HOME\it140\scripts\win\wsb\setup_wsb.ps1" -Version

Run from the Windows Sandbox Administrator PowerShell session after:
  1. bootstrap_wsb.ps1
  2. bootstrap_win.ps1

This script installs missing system software only. It does not run Windows
Update and does not upgrade software that WinGet already reports as installed.

Deployment profile: $DeploymentProfile
Manifest package profile: $ManifestDeploymentProfile
Log directory: $LogDirectory
"@ | Write-Host
}

function Write-ClosingNotice {
    Write-Notice "A log containing all output displayed while this script ran is available here:"
    Write-Notice $LogPath
    Write-Notice (
        "After reviewing the summary, type 'exit' and press Enter to " +
        "close this PowerShell window."
    )
    Write-Notice (
        "Open a new, normal PowerShell window before running config_win.ps1 " +
        "so it loads the latest PATH and environment settings."
    )
}

function Test-IsAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
    return $Principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Test-IsWindowsSandbox {
    return [Environment]::UserName -eq "WDAGUtilityAccount"
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

function Test-JsonDuplicateKey {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($null -eq ("It140Automation.JsonDuplicateKeyValidator" -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace It140Automation
{
    public static class JsonDuplicateKeyValidator
    {
        public static void Validate(string json)
        {
            if (json == null)
            {
                throw new ArgumentNullException("json");
            }

            int index = 0;
            ParseValue(json, ref index, 0);
            SkipWhitespace(json, ref index);
            if (index != json.Length)
            {
                throw new FormatException("Unexpected content after the JSON value.");
            }
        }

        private static void ParseValue(string json, ref int index, int depth)
        {
            if (depth > 256)
            {
                throw new FormatException("JSON nesting exceeds the supported depth.");
            }

            SkipWhitespace(json, ref index);
            if (index >= json.Length)
            {
                throw new FormatException("Unexpected end of JSON input.");
            }

            char current = json[index];
            if (current == '{')
            {
                ParseObject(json, ref index, depth + 1);
            }
            else if (current == '[')
            {
                ParseArray(json, ref index, depth + 1);
            }
            else if (current == '"')
            {
                ParseString(json, ref index);
            }
            else
            {
                ParsePrimitive(json, ref index);
            }
        }

        private static void ParseObject(string json, ref int index, int depth)
        {
            index++;
            SkipWhitespace(json, ref index);
            HashSet<string> keys = new HashSet<string>(StringComparer.Ordinal);

            if (index < json.Length && json[index] == '}')
            {
                index++;
                return;
            }

            while (true)
            {
                SkipWhitespace(json, ref index);
                if (index >= json.Length || json[index] != '"')
                {
                    throw new FormatException("Expected a JSON object key.");
                }

                string key = ParseString(json, ref index);
                if (!keys.Add(key))
                {
                    throw new FormatException("duplicate key: " + key);
                }

                SkipWhitespace(json, ref index);
                if (index >= json.Length || json[index] != ':')
                {
                    throw new FormatException("Expected ':' after a JSON object key.");
                }
                index++;

                ParseValue(json, ref index, depth);
                SkipWhitespace(json, ref index);
                if (index >= json.Length)
                {
                    throw new FormatException("Unexpected end of JSON object.");
                }
                if (json[index] == '}')
                {
                    index++;
                    return;
                }
                if (json[index] != ',')
                {
                    throw new FormatException("Expected ',' or '}' in a JSON object.");
                }
                index++;
            }
        }

        private static void ParseArray(string json, ref int index, int depth)
        {
            index++;
            SkipWhitespace(json, ref index);
            if (index < json.Length && json[index] == ']')
            {
                index++;
                return;
            }

            while (true)
            {
                ParseValue(json, ref index, depth);
                SkipWhitespace(json, ref index);
                if (index >= json.Length)
                {
                    throw new FormatException("Unexpected end of JSON array.");
                }
                if (json[index] == ']')
                {
                    index++;
                    return;
                }
                if (json[index] != ',')
                {
                    throw new FormatException("Expected ',' or ']' in a JSON array.");
                }
                index++;
            }
        }

        private static string ParseString(string json, ref int index)
        {
            if (index >= json.Length || json[index] != '"')
            {
                throw new FormatException("Expected a JSON string.");
            }
            index++;
            StringBuilder value = new StringBuilder();

            while (index < json.Length)
            {
                char current = json[index++];
                if (current == '"')
                {
                    return value.ToString();
                }
                if (current == '\\')
                {
                    if (index >= json.Length)
                    {
                        throw new FormatException("Incomplete JSON escape sequence.");
                    }
                    char escaped = json[index++];
                    switch (escaped)
                    {
                        case '"': value.Append('"'); break;
                        case '\\': value.Append('\\'); break;
                        case '/': value.Append('/'); break;
                        case 'b': value.Append('\b'); break;
                        case 'f': value.Append('\f'); break;
                        case 'n': value.Append('\n'); break;
                        case 'r': value.Append('\r'); break;
                        case 't': value.Append('\t'); break;
                        case 'u':
                            if (index + 4 > json.Length)
                            {
                                throw new FormatException("Incomplete JSON Unicode escape.");
                            }
                            int codePoint;
                            if (!Int32.TryParse(
                                json.Substring(index, 4),
                                NumberStyles.HexNumber,
                                CultureInfo.InvariantCulture,
                                out codePoint))
                            {
                                throw new FormatException("Invalid JSON Unicode escape.");
                            }
                            value.Append((char)codePoint);
                            index += 4;
                            break;
                        default:
                            throw new FormatException("Invalid JSON escape sequence.");
                    }
                }
                else
                {
                    if (current < 0x20)
                    {
                        throw new FormatException("Unescaped control character in JSON string.");
                    }
                    value.Append(current);
                }
            }

            throw new FormatException("Unterminated JSON string.");
        }

        private static void ParsePrimitive(string json, ref int index)
        {
            int start = index;
            while (index < json.Length)
            {
                char current = json[index];
                if (
                    Char.IsWhiteSpace(current) ||
                    current == ',' ||
                    current == ']' ||
                    current == '}')
                {
                    break;
                }
                index++;
            }
            if (index == start)
            {
                throw new FormatException("Invalid JSON primitive value.");
            }
        }

        private static void SkipWhitespace(string json, ref int index)
        {
            while (index < json.Length && Char.IsWhiteSpace(json[index]))
            {
                index++;
            }
        }
    }
}
'@
    }

    try {
        $JsonText = Get-Content -LiteralPath $Path -Raw
        [It140Automation.JsonDuplicateKeyValidator]::Validate($JsonText)
    }
    catch {
        throw "JSON duplicate-key validation failed for $Path. $($_.Exception.Message)"
    }
}

function Read-ControlledManifest {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "The controlled manifest is missing: $ManifestPath"
    }
    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
        throw "The controlled manifest schema is missing: $SchemaPath"
    }

    Test-JsonDuplicateKey -Path $ManifestPath
    Test-JsonDuplicateKey -Path $SchemaPath

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
        "platforms",
        "deployment_profiles",
        "managed_settings",
        "managed_assets",
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
    $ProfileRecord = Get-PropertyValue `
        -Object $Manifest.deployment_profiles `
        -Name $ManifestDeploymentProfile

    if ($null -eq $Platform -or -not [bool]$Platform.enabled) {
        throw "The Windows platform is not enabled in the controlled manifest."
    }
    if ($null -eq $ProfileRecord -or -not [bool]$ProfileRecord.enabled) {
        throw "The manifest package profile is not enabled: $ManifestDeploymentProfile"
    }
    if ([string]$ProfileRecord.platform_id -ne $PlatformId) {
        throw "The manifest package profile does not select the Windows platform."
    }

    return [pscustomobject]@{
        Manifest = $Manifest
        Platform = $Platform
        Profile = $ProfileRecord
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

    return [pscustomobject]@{
        Caption = $Caption
        Architecture = if ([Environment]::Is64BitOperatingSystem) {
            "64-bit"
        }
        else {
            "32-bit"
        }
        DisplayVersion = [string]$CurrentVersion.DisplayVersion
        BuildNumber = $BuildNumber
    }
}

function Test-SupportedOperatingSystem {
    param(
        [Parameter(Mandatory = $true)]$WindowsFacts,
        [Parameter(Mandatory = $true)]$Platform
    )

    if (-not (Test-IsWindowsSandbox)) {
        throw (
            "This script supports only a fresh Windows Sandbox session using " +
            "WDAGUtilityAccount. Use setup_win.ps1 on regular Windows."
        )
    }
    if ($WindowsFacts.Caption -notmatch "Windows 11") {
        throw "This script supports only Microsoft Windows 11. Detected: $($WindowsFacts.Caption)"
    }
    if ($WindowsFacts.Architecture -notmatch "64-bit") {
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

function Invoke-ExternalCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$Operation,
        [int[]]$SuccessExitCode = @(0)
    )

    Write-Info $Operation
    & $FilePath @ArgumentList
    $CommandExitCode = $LASTEXITCODE
    if ($CommandExitCode -notin $SuccessExitCode) {
        throw "$Operation failed with exit code $CommandExitCode."
    }
}

function Confirm-WinGetAvailable {
    Update-ProcessEnvironment

    if ($null -ne (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Success "Windows Package Manager is available."
        return
    }

    $AppInstaller = Get-AppxPackage `
        -Name Microsoft.DesktopAppInstaller `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -ne $AppInstaller) {
        $WinGetExecutable = Join-Path $AppInstaller.InstallLocation "winget.exe"
        if (Test-Path -LiteralPath $WinGetExecutable -PathType Leaf) {
            $env:Path = "$($AppInstaller.InstallLocation);$env:Path"
        }
    }

    if ($null -eq (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw (
            "Windows Package Manager is unavailable. Run bootstrap_wsb.ps1 " +
            "again in a fresh Windows Sandbox session."
        )
    }

    Write-Success "Windows Package Manager is available."
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

    & winget.exe list `
        --id $PackageIdentifier `
        --exact `
        --source winget `
        --accept-source-agreements `
        --disable-interactivity *> $null

    return $LASTEXITCODE -eq 0
}

function Install-SystemPackage {
    param([Parameter(Mandatory = $true)]$Bindings)

    foreach ($Binding in $Bindings) {
        $PackageIdentifier = [string]$Binding.PackageIdentifier

        if (Test-WinGetPackageInstalled -PackageIdentifier $PackageIdentifier) {
            Write-Success "$PackageIdentifier is already installed; no upgrade was requested."
            continue
        }

        Invoke-ExternalCommand `
            -FilePath "winget.exe" `
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
        $MissingCommands += "winget.exe"
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
        # Best-effort operation; preserve the primary result.
    }

    return "unavailable"
}

if ($Help) {
    Show-Usage
    exit 0
}
if ($Version) {
    Write-Host $ScriptVersion
    exit 0
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
    Write-Notice "This script installs missing course software in Windows Sandbox."
    Write-Notice "It does not run Windows Update or upgrade installed software."
    Write-Notice "It does not configure personal GitHub, Git, Python, or VS Code settings."

    if (-not (Test-IsAdministrator)) {
        $FailureExitCode = 3
        throw (
            "Setup requires the Windows Sandbox Administrator PowerShell session. " +
            "Rerun setup_wsb.ps1 from that elevated session."
        )
    }

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
    Confirm-WinGetAvailable

    $Bindings = Get-SystemPackageBinding -Platform $Controlled.Platform
    Install-SystemPackage -Bindings $Bindings

    $FailureExitCode = 1
    Test-SystemLayer -Bindings $Bindings -Platform $Controlled.Platform

    $Elapsed = (Get-Date) - $StartTime
    Write-Header "SETUP SUMMARY"
    Write-Success "The Windows Sandbox system layer for the IT 140 Course IDE is installed."
    Write-Info "Result           : PASS"
    Write-Info "Git              : $(Get-CommandVersionLine -CommandName 'git.exe')"
    Write-Info "GitHub CLI       : $(Get-CommandVersionLine -CommandName 'gh.exe')"
    Write-Info "Python           : $(Get-CommandVersionLine -CommandName 'python.exe')"
    Write-Info "VS Code          : $(Get-CommandVersionLine -CommandName 'code.cmd')"
    Write-Info "Warnings         : $WarningCount"
    Write-Info "Failures         : 0"
    Write-Info ("Elapsed time     : {0:hh\:mm\:ss}" -f $Elapsed)
    Write-Info "Log file         : $LogPath"
    Write-Notice (
        "Next step: close this Administrator PowerShell window, open a normal " +
        "PowerShell window, and run config_win.ps1."
    )
    Write-Info "Exit code        : 0"
    Write-ClosingNotice
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
            "Rerun setup_wsb.ps1 in this session or begin with a fresh sandbox."
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
            # Best-effort operation; preserve the primary result.
        }
        $MutationMutex.Dispose()
    }

    if ($TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
            # Best-effort operation; preserve the primary result.
        }
    }
}

exit $ExitCode
