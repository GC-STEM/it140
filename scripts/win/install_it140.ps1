#requires -Version 5.1
<#
.SYNOPSIS
Installs or repairs the system-level IT 140 Course IDE on Windows.

.DESCRIPTION
Installs or repairs Windows Package Manager when required and installs or
repairs the manifest-declared system software for IT 140. Windows updates are
completed manually before the course automation lifecycle; this script does
not run Windows Update. It does not configure personal GitHub, Git,
Python-environment, VS Code-extension, or editor settings.

Run this script from an elevated Windows PowerShell terminal opened by the
intended student or faculty user.

Artifact version: 0.10.0-beta.1
Version date-time group: 2026-08-09-23-59
Development status: Beta Testing

Version basis:
    Version 0.1.0 represents the initial Windows setup baseline.
    Version 0.2.0 adopts SemVer and manifest schema 2.0, and removes
    operating-system update automation from the course lifecycle.
    Version 0.2.1 removes an unsupported WinGet source-update option.

    Version 0.3.0 adds support for Windows 10, version 22H2, while preserving
    manifest-controlled Windows 11 release validation.


.NOTES
Exit codes:
  0 Success
  1 Required operation failed
  2 Unsupported Windows platform or release
  3 Required administrator privilege is unavailable
  4 Required network or package-retrieval operation failed
  5 Controlled manifest or managed asset validation failed
  6 User canceled before managed state changed
  7 Managed state changed before the operation stopped

Logs are written under ~/it140/logs/.

.USAGE
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
install_it140.ps1

#>

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Version,
    [switch]$NonInteractive,
    [ValidateSet("windows_bare_metal")]
    [string]$DeploymentProfile = "windows_bare_metal"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ScriptVersion = "0.3.0"
$VersionDate = "2026-07-29"
$DevelopmentStatus = "Beta Testing"
$PlatformId = "windows"
$PlatformAbbreviation = "win"
$ScriptDirectory = $PSScriptRoot
$ScriptRoot = Split-Path -Parent $ScriptDirectory
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
$RestartRequired = $false
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
IT 140 Windows install script

Usage:
  powershell.exe -ExecutionPolicy Bypass -File .\install_it140.ps1
  powershell.exe -ExecutionPolicy Bypass -File .\install_it140.ps1 -NonInteractive
  powershell.exe -ExecutionPolicy Bypass -File .\install_it140.ps1 -Help
  powershell.exe -ExecutionPolicy Bypass -File .\install_it140.ps1 -Version

Run from an elevated Windows PowerShell terminal opened by the intended user.
Update Windows manually before starting the course automation lifecycle. This
script installs or repairs only manifest-declared course IDE components.

Deployment profile: windows_bare_metal
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
        "Open a new PowerShell window before running another script so it " +
        "loads the latest PATH and environment settings."
    )
}

function Test-IsAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
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
        "automation_release_date_time_group",
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
    if ([string]$Manifest.schema_version -ne "2.2") {
        throw "Unsupported manifest schema version: $($Manifest.schema_version)"
    }

    $AutomationRelease = [string]$Manifest.automation_release
    $SemVerPattern = [string]$Schema.'$defs'.automationRelease.pattern
        if ($AutomationRelease -notmatch $SemVerPattern) {
        throw "The manifest automation release is not strict SemVer: $AutomationRelease"
    }

    $ParsedReleaseDate = [datetime]::MinValue
    $ReleaseDateIsValid = [datetime]::TryParseExact(
        [string]$Manifest.automation_release_date_time_group,
        "yyyy-MM-dd-HH-mm",
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$ParsedReleaseDate
    )
    if (-not $ReleaseDateIsValid) {
        throw (
            "The manifest automation release date-time group is not valid YYYY-MM-DD-HH-MM: " +
            [string]$Manifest.automation_release_date_time_group
        )
    }

    if ([string]$Schema.'$schema' -ne "https://json-schema.org/draft/2020-12/schema") {
        throw "The manifest schema is not the approved Draft 2020-12 format."
    }

    $Platform = Get-PropertyValue -Object $Manifest.platforms -Name $PlatformId
    $ProfileRecord = Get-PropertyValue `
        -Object $Manifest.deployment_profiles `
        -Name $DeploymentProfile

    if ($null -eq $Platform -or -not [bool]$Platform.enabled) {
        throw "The Windows platform is not enabled in the controlled manifest."
    }
    if ($null -eq $ProfileRecord -or -not [bool]$ProfileRecord.enabled) {
        throw "The deployment profile is not enabled: $DeploymentProfile"
    }
    if ([string]$ProfileRecord.platform_id -ne $PlatformId) {
        throw "The deployment profile does not select the Windows platform."
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
    $DisplayVersion = [string]$CurrentVersion.DisplayVersion

    if ([int]$BuildNumber -ge 22000 -and $Caption -notmatch "Windows 11") {
        $Caption = $Caption -replace "Windows 10", "Windows 11"
    }
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

    $IsWindows10 = $WindowsFacts.Caption -match "Windows 10"
    $IsWindows11 = $WindowsFacts.Caption -match "Windows 11"

    if (-not ($IsWindows10 -or $IsWindows11)) {
        throw (
            "This script supports Microsoft Windows 10 or Windows 11. " +
            "Detected: $($WindowsFacts.Caption)"
        )
    }
    if ($WindowsFacts.Architecture -notmatch "64-bit") {
        throw "This release supports only x64 Windows. Detected: $($WindowsFacts.Architecture)"
    }

    if ($IsWindows10) {
        if ($WindowsFacts.DisplayVersion -ne "22H2") {
            throw (
                "Windows 10 release {0} is not enabled. Supported Windows 10 " +
                "release: 22H2." -f $WindowsFacts.DisplayVersion
            )
        }
        return
    }

    $SupportedWindows11Releases = @(
        $Platform.os.releases | ForEach-Object { [string]$_.release_id }
    )
    if ($WindowsFacts.DisplayVersion -notin $SupportedWindows11Releases) {
        throw (
            "Windows 11 release {0} is not enabled. Supported Windows 11 " +
            "releases: {1}" -f
            $WindowsFacts.DisplayVersion,
            ($SupportedWindows11Releases -join ", ")
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
        [Parameter(Mandatory = $true)][string]$Operation
    )

    Write-Info $Operation
    & $FilePath @ArgumentList
    $CommandExitCode = $LASTEXITCODE
    if ($CommandExitCode -ne 0) {
        throw "$Operation failed with exit code $CommandExitCode."
    }
}

function Invoke-CurlDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $PartialPath = "$Destination.part"
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force |
        Out-Null

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
        throw "Download failed: $Uri"
    }

    Move-Item -LiteralPath $PartialPath -Destination $Destination -Force
}

function Install-WinGetFallback {
    $TemporaryRoot = Join-Path $env:TEMP (
        "it140-winget-{0}" -f ([guid]::NewGuid().ToString("N"))
    )
    $DependenciesZip = Join-Path $TemporaryRoot "DesktopAppInstaller_Dependencies.zip"
    $DependenciesDirectory = Join-Path $TemporaryRoot "Dependencies"
    $RuntimeInstaller = Join-Path $TemporaryRoot "WindowsAppRuntimeInstall-x64.exe"
    $WinGetBundle = Join-Path $TemporaryRoot (
        "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    )

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
        if ($RuntimeProcess.ExitCode -notin @(0, 3010)) {
            throw (
                "Windows App Runtime installation failed with exit code {0}." -f
                $RuntimeProcess.ExitCode
            )
        }
        if ($RuntimeProcess.ExitCode -eq 3010) {
            $script:RestartRequired = $true
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

        $X64Directory = Get-ChildItem `
            -LiteralPath $DependenciesDirectory `
            -Directory `
            -Recurse `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ieq "x64" } |
            Select-Object -First 1

        if ($null -ne $X64Directory) {
            $DependencyPackages = @(
                Get-ChildItem -LiteralPath $X64Directory.FullName -Filter "*.appx" -File
            )
        }
        else {
            $DependencyPackages = @(
                Get-ChildItem `
                    -LiteralPath $DependenciesDirectory `
                    -Filter "*.appx" `
                    -File `
                    -Recurse |
                    Where-Object {
                        $_.FullName -notmatch "[\\/](arm64|x86)[\\/]"
                    }
            )
        }

        foreach ($DependencyPackage in $DependencyPackages) {
            try {
                Add-AppxPackage -Path $DependencyPackage.FullName
            }
            catch {
                Write-Notice (
                    "A WinGet dependency did not require replacement: {0}" -f
                    $DependencyPackage.Name
                )
            }
        }

        Add-AppxPackage -Path $WinGetBundle
        $script:Changed = $true
    }
    finally {
        Remove-Item -LiteralPath $TemporaryRoot -Recurse -Force `
            -ErrorAction SilentlyContinue
    }
}

function Install-WinGet {
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
            "Microsoft App Installer registration did not complete: {0}" -f
            $_.Exception.Message
        )
    }

    Update-ProcessEnvironment
    if ($null -ne (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Success "Windows Package Manager was registered successfully."
        return
    }

    Write-Notice "Using the direct Microsoft App Installer fallback."
    Install-WinGetFallback
    Update-ProcessEnvironment

    if ($null -eq (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "Windows Package Manager is unavailable after the repair attempt."
    }

    Write-Success "Windows Package Manager was installed successfully."
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

    Invoke-ExternalCommand `
        -FilePath "winget.exe" `
        -ArgumentList @(
            "source",
            "update",
            "--disable-interactivity"
        ) `
        -Operation "Updating WinGet package sources."

    foreach ($Binding in $Bindings) {
        $PackageIdentifier = [string]$Binding.PackageIdentifier
        if (Test-WinGetPackageInstalled -PackageIdentifier $PackageIdentifier) {
            Write-Info "Updating or verifying $PackageIdentifier."
            & winget.exe upgrade `
                --id $PackageIdentifier `
                --exact `
                --source winget `
                --scope machine `
                --silent `
                --disable-interactivity `
                --accept-source-agreements `
                --accept-package-agreements `
                --verbose-logs

            if ($LASTEXITCODE -ne 0) {
                if (Test-WinGetPackageInstalled -PackageIdentifier $PackageIdentifier) {
                    Write-Notice (
                        "No WinGet upgrade was applied to $PackageIdentifier; " +
                        "the installed package remains available."
                    )
                }
                else {
                    throw "Required package is unavailable: $PackageIdentifier"
                }
            }
        }
        else {
            Invoke-ExternalCommand `
                -FilePath "winget.exe" `
                -ArgumentList @(
                    "install",
                    "--id", $PackageIdentifier,
                    "--exact",
                    "--source", "winget",
                    "--scope", "machine",
                    "--silent",
                    "--disable-interactivity",
                    "--accept-source-agreements",
                    "--accept-package-agreements",
                    "--verbose-logs"
                ) `
                -Operation "Installing $PackageIdentifier."
            $script:Changed = $true
        }
    }

    Update-ProcessEnvironment
    $script:Changed = $true
    Write-Success "Manifest-required Windows software is installed."
}

function Test-SystemLayer {
    param(
        [Parameter(Mandatory = $true)]$Bindings,
        [Parameter(Mandatory = $true)]$Platform
    )

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
    Write-Host "Artifact version   : $ScriptVersion"
    Write-Host "Version date       : $VersionDate"
    Write-Host "Development status : $DevelopmentStatus"
    exit 0
}

try {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    Start-Transcript -Path $LogPath -Append -Force | Out-Null
    $TranscriptStarted = $true
    Remove-ExpiredLog

    Write-Header "IT 140 WINDOWS SETUP"
    Write-Info "Script version   : $ScriptVersion"
    Write-Info "Version date     : $VersionDate"
    Write-Info "Status           : $DevelopmentStatus"
    Write-Info "Deployment       : $DeploymentProfile"
    Write-Info "Current user     : $([Environment]::UserName)"
    Write-Info "Course root      : $CourseRoot"
    Write-Info "Log file         : $LogPath"
    Write-Notice "This script installs or repairs required course IDE software."
    Write-Notice "Windows updates are not installed by this script."
    Write-Notice "It does not configure personal GitHub, Git, Python, or VS Code settings."

    if (-not (Test-IsAdministrator)) {
        $FailureExitCode = 3
        throw (
            "Setup requires an elevated Windows PowerShell terminal. " +
            "Open Windows PowerShell as administrator under the intended user, " +
            "then rerun install_it140.ps1."
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
    Write-Info "Manifest DTG     : $($Controlled.Manifest.automation_release_date_time_group)"

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
    Install-WinGet

    $FailureExitCode = 1
    $Bindings = Get-SystemPackageBinding -Platform $Controlled.Platform
    Install-SystemPackage -Bindings $Bindings
    Test-SystemLayer -Bindings $Bindings -Platform $Controlled.Platform

    $Elapsed = (Get-Date) - $StartTime
    Write-Header "SETUP SUMMARY"
    Write-Success "The system-level IT 140 Course IDE is installed."
    Write-Info "Result           : PASS"
    Write-Info "Script version   : $ScriptVersion"
    Write-Info "Version date     : $VersionDate"
    Write-Info "Status           : $DevelopmentStatus"
    Write-Info "Manifest release : $($Controlled.Manifest.automation_release)"
    Write-Info "Manifest DTG     : $($Controlled.Manifest.automation_release_date_time_group)"
    Write-Info "Git              : $(Get-CommandVersionLine -CommandName 'git.exe')"
    Write-Info "GitHub CLI       : $(Get-CommandVersionLine -CommandName 'gh.exe')"
    Write-Info "Python           : $(Get-CommandVersionLine -CommandName 'python.exe')"
    Write-Info "VS Code          : $(Get-CommandVersionLine -CommandName 'code.cmd')"
    Write-Info "Warnings         : $WarningCount"
    Write-Info "Failures         : 0"
    Write-Info ("Elapsed time     : {0:hh\:mm\:ss}" -f $Elapsed)
    Write-Info "Log file         : $LogPath"

    if ($RestartRequired) {
        Write-Notice "Next step: save your work and restart Windows."
        Write-Notice (
            "After Windows restarts, open a normal PowerShell window and " +
            "run configure_it140.ps1."
        )
    }
    else {
        Write-Notice (
            "Next step: close this window, open a normal PowerShell window, " +
            "and run configure_it140.ps1."
        )
    }
    Write-Info "Exit code        : 0"
    Write-ClosingNotice
    $ExitCode = 0
}
catch {
    $LineNumber = $_.InvocationInfo.ScriptLineNumber
    Write-ErrorMessage $_.Exception.Message
    if ($LineNumber) {
        Write-ErrorMessage "Setup stopped near line $LineNumber."
    }
    Write-Info "Setup log: $LogPath"
    if ($Changed) {
        Write-Notice (
            "Managed system state changed before setup stopped. " +
            "Rerun install_it140.ps1 to repair it."
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
