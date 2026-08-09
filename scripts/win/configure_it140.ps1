#requires -Version 5.1
<#
.SYNOPSIS
Configures or repairs the current Windows user for the IT 140 Course IDE.

.DESCRIPTION
Configures the intended user's course folders and PATH, GitHub authentication,
privacy-preserving Git identity, course Python virtual environment, required
VS Code extensions and settings, and a separate Windows Repos development workspace with desktop access. The script
preserves unrelated user settings and does not install or update system-level
software.

Run this script from a normal, non-elevated Windows PowerShell terminal on a
regular Windows computer. Windows Sandbox intentionally uses its administrative
container account with the windows_sandbox deployment profile.

Artifact version: 0.10.0-beta.1
Version date-time group: 2026-08-09-23-59
Development status: Beta Testing

Version basis:
    Version 0.1.0 represents the initial Windows configuration baseline.
    Version 0.2.0 adopts SemVer metadata and manifest schema 2.0.
    Version 0.2.1 prevents expected native-command probe failures from
    terminating Windows PowerShell 5.1.
    Version 0.3.0 adds clipboard-assisted GitHub web authentication.

    Version 0.4.0 adds support for Windows 10, version 22H2, while preserving
    manifest-controlled Windows 11 release validation.
    Version 0.8.0-alpha.1 adds the separate Repos development workspace,
    Explorer development icon, and desktop Repos shortcut while preserving
    all repositories and files beneath the workspace.


.NOTES
Exit codes:
  0 Success
  1 Required operation failed
  2 Unsupported Windows platform or release
  3 Privilege context is invalid for the selected deployment
  4 Required network or package-retrieval operation failed
  5 Controlled manifest or managed asset validation failed
  6 User canceled before managed state changed
  7 Managed state changed before the operation stopped

Logs are written under ~/it140/logs/.

.USAGE
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
configure_it140.ps1

#>

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Version,
    [switch]$NonInteractive,
    [ValidateSet("windows_bare_metal", "windows_sandbox")]
    [string]$DeploymentProfile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ScriptVersion = "0.10.0-beta.1"
$VersionDate = "2026-08-09-23-59"
$DevelopmentStatus = "Beta Testing"
$PlatformId = "windows"
$PlatformAbbreviation = "win"
$ScriptDirectory = $PSScriptRoot
$ScriptRoot = Split-Path -Parent $ScriptDirectory
$CourseRoot = Split-Path -Parent $ScriptRoot
$ReposRoot = Join-Path ([Environment]::GetFolderPath("UserProfile")) "Repos"
$WindowsScriptDirectory = Join-Path $ScriptRoot $PlatformAbbreviation
$ManifestPath = Join-Path $ScriptRoot ".manifest\it140_manifest.json"
$SchemaPath = Join-Path $ScriptRoot ".manifest\it140_manifest.schema.json"
$LogDirectory = Join-Path $CourseRoot "logs"
$LogPath = Join-Path $LogDirectory (
    "config_{0}_{1}.log" -f $PlatformAbbreviation, (Get-Date -Format "yyyyMMdd_HHmmss")
)
$VenvDirectory = Join-Path $CourseRoot ".venv"
$VenvScriptsDirectory = Join-Path $VenvDirectory "Scripts"
$VenvPython = Join-Path $VenvScriptsDirectory "python.exe"
$VsCodeSettings = Join-Path $env:APPDATA "Code\User\settings.json"
$ReposShortcutPath = Join-Path (
    [Environment]::GetFolderPath("Desktop")
) "Repos.lnk"
$ReposDesktopIniPath = Join-Path $ReposRoot "desktop.ini"
$StartTime = Get-Date
$TranscriptStarted = $false
$MutationMutex = $null
$Changed = $false
$WarningCount = 0
$ExitCode = 0
$FailureExitCode = 1
$GitHubUser = "unknown"

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

function Test-NativeCommandExitSuccess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $PreviousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & $FilePath @ArgumentList *> $null
        return $LASTEXITCODE -eq 0
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }
}

function Show-Usage {
    @"
IT 140 Windows configure script

Usage:
  powershell.exe -ExecutionPolicy Bypass -File .\configure_it140.ps1
  powershell.exe -ExecutionPolicy Bypass -File .\configure_it140.ps1 -NonInteractive
  powershell.exe -ExecutionPolicy Bypass -File .\configure_it140.ps1 -Help
  powershell.exe -ExecutionPolicy Bypass -File .\configure_it140.ps1 -Version

Use a normal, non-elevated PowerShell terminal on a regular Windows computer.
Windows Sandbox uses its expected administrative container context. When the
profile is omitted, the script selects the profile from the detected environment.
Noninteractive mode requires an existing GitHub login and uses the current Git
display name, or the GitHub username when no display name is configured.

Deployment profile: $DeploymentProfile
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

function Test-IsWindowsSandbox {
    return [Environment]::UserName -eq "WDAGUtilityAccount"
}

function Resolve-DeploymentProfile {
    if (-not [string]::IsNullOrWhiteSpace($DeploymentProfile)) {
        return
    }

    $script:DeploymentProfile = if (Test-IsWindowsSandbox) {
        "windows_sandbox"
    }
    else {
        "windows_bare_metal"
    }
}

function Update-ProcessEnvironment {
    $MachinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = @($MachinePath, $UserPath) -join ";"
}

function Get-NormalizedPathEntry {
    param([Parameter(Mandatory = $true)][string]$PathEntry)

    try {
        $ExpandedPath = [Environment]::ExpandEnvironmentVariables($PathEntry)
        return [IO.Path]::GetFullPath($ExpandedPath).TrimEnd("\")
    }
    catch {
        return $PathEntry.Trim().TrimEnd("\")
    }
}

function Set-ManagedUserPath {
    $ManagedEntries = @($VenvScriptsDirectory, $WindowsScriptDirectory)
    $ExistingUserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $PreservedEntries = [Collections.Generic.List[string]]::new()

    foreach ($ExistingEntry in @($ExistingUserPath -split ";")) {
        if ([string]::IsNullOrWhiteSpace($ExistingEntry)) {
            continue
        }

        $NormalizedExisting = Get-NormalizedPathEntry -PathEntry $ExistingEntry
        $IsManagedEntry = $false
        foreach ($ManagedEntry in $ManagedEntries) {
            if (
                $NormalizedExisting -ieq
                (Get-NormalizedPathEntry -PathEntry $ManagedEntry)
            ) {
                $IsManagedEntry = $true
                break
            }
        }
        if (-not $IsManagedEntry) {
            $PreservedEntries.Add($ExistingEntry.Trim())
        }
    }

    $NewUserPath = (@($ManagedEntries) + @($PreservedEntries)) -join ";"
    if ($NewUserPath -cne [string]$ExistingUserPath) {
        [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
        $script:Changed = $true
    }

    Update-ProcessEnvironment
    Write-Success "The course Python and Windows script directories are first in the user PATH."
}

function Test-PathContainsEntry {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$ExpectedEntry
    )

    $NormalizedExpected = Get-NormalizedPathEntry -PathEntry $ExpectedEntry
    foreach ($ObservedEntry in @($PathValue -split ";")) {
        if ([string]::IsNullOrWhiteSpace($ObservedEntry)) {
            continue
        }
        if (
            (Get-NormalizedPathEntry -PathEntry $ObservedEntry) -ieq
            $NormalizedExpected
        ) {
            return $true
        }
    }
    return $false
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
        "provider_profiles",
        "managed_settings"
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
    if ($null -eq (Get-PropertyValue -Object $Manifest.provider_profiles -Name "github_com")) {
        throw "The required GitHub provider profile is unavailable."
    }

    return [pscustomobject]@{
        Manifest = $Manifest
        Platform = $Platform
        Profile = $ProfileRecord
    }
}

function Get-OperatingSystemFact {
    if (
        $DeploymentProfile -eq "windows_sandbox" -and
        (Test-IsWindowsSandbox)
    ) {
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

        $Architecture = if ([Environment]::Is64BitOperatingSystem) {
            "64-bit"
        }
        else {
            "32-bit"
        }

        return [pscustomobject]@{
            Caption = $Caption
            Architecture = $Architecture
            DisplayVersion = $DisplayVersion
            BuildNumber = $BuildNumber
        }
    }

    $OperatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
    $CurrentVersion = Get-ItemProperty `
        -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    $DisplayVersion = [string]$CurrentVersion.DisplayVersion
    if ([string]::IsNullOrWhiteSpace($DisplayVersion)) {
        $DisplayVersion = [string]$CurrentVersion.ReleaseId
    }

    return [pscustomobject]@{
        Caption = [string]$OperatingSystem.Caption
        Architecture = [string]$OperatingSystem.OSArchitecture
        DisplayVersion = $DisplayVersion
        BuildNumber = [string]$OperatingSystem.BuildNumber
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

function Test-SystemLayer {
    param([Parameter(Mandatory = $true)]$Platform)

    Update-ProcessEnvironment
    $MissingCommands = @()
    foreach ($PropertyRecord in $Platform.course_ide_bindings.PSObject.Properties) {
        $Binding = $PropertyRecord.Value
        if (
            [bool]$Binding.required -and
            [string]$Binding.installation_scope -eq "system"
        ) {
            foreach ($ExecutableName in @($Binding.verification.executable_names)) {
                if ($null -eq (Get-Command $ExecutableName -ErrorAction SilentlyContinue)) {
                    $MissingCommands += [string]$ExecutableName
                }
            }
        }
    }

    if ($MissingCommands.Count -gt 0) {
        throw (
            "Required system commands are missing: {0}. Run install_it140.ps1." -f
            ($MissingCommands -join ", ")
        )
    }

    $RuntimeBinding = Get-PropertyValue `
        -Object $Platform.course_ide_bindings `
        -Name "programming_language_runtime"
    $RuntimeExecutable = [string]$RuntimeBinding.verification.executable_names[0]
    $PythonVersion = & $RuntimeExecutable -c (
        "import sys; print('.'.join(map(str, sys.version_info[:2])))"
    )
    if ($LASTEXITCODE -ne 0 -or [string]$PythonVersion -ne "3.12") {
        throw "Python 3.12 is not the active Windows system runtime. Run install_it140.ps1."
    }

    Write-Success "Required system components are present."
}

function Get-RequiredPythonPackage {
    param([Parameter(Mandatory = $true)]$Platform)

    $Packages = @()
    foreach ($PropertyRecord in $Platform.course_ide_bindings.PSObject.Properties) {
        $Binding = $PropertyRecord.Value
        if (
            [bool]$Binding.required -and
            [string]$Binding.installation_scope -eq "user" -and
            [string]$Binding.installer_adapter_id -eq "python_venv_package"
        ) {
            $Packages += [string]$Binding.package_identifier
        }
    }

    $CodeQualityBinding = Get-PropertyValue `
        -Object $Platform.course_ide_bindings `
        -Name "code_quality_tool"
    if ($null -ne $CodeQualityBinding -and [bool]$CodeQualityBinding.required) {
        $Packages += "ruff"
    }

    return @($Packages | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-RequiredExtension {
    param([Parameter(Mandatory = $true)]$Platform)

    $Extensions = @()
    foreach ($PropertyRecord in $Platform.course_ide_bindings.PSObject.Properties) {
        $Binding = $PropertyRecord.Value
        if (
            [bool]$Binding.required -and
            [string]$Binding.installation_scope -eq "user" -and
            [string]$Binding.installer_adapter_id -eq "vscode_extension"
        ) {
            $Extensions += [string]$Binding.package_identifier
        }
    }
    return @($Extensions | Where-Object { $_ } | Sort-Object -Unique)
}

function Test-VenvPython {
    if (-not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
        return $false
    }

    try {
        $VenvVersion = & $VenvPython -c (
            "import sys; print('.'.join(map(str, sys.version_info[:2])))"
        )
        return $LASTEXITCODE -eq 0 -and [string]$VenvVersion -eq "3.12"
    }
    catch {
        return $false
    }
}

function Install-CoursePythonEnvironment {
    param([Parameter(Mandatory = $true)][string[]]$RequiredPackages)

    if (-not (Test-VenvPython)) {
        if (Test-Path -LiteralPath $VenvDirectory) {
            Write-Notice "Replacing the unusable course Python environment."
            Remove-Item -LiteralPath $VenvDirectory -Recurse -Force
        }

        Write-Info "Creating the IT 140 Python 3.12 virtual environment."
        & python.exe -m venv $VenvDirectory
        if ($LASTEXITCODE -ne 0 -or -not (Test-VenvPython)) {
            throw "The course Python virtual environment could not be created."
        }
        $script:Changed = $true
    }

    if (-not (Test-NativeCommandExitSuccess `
        -FilePath $VenvPython `
        -ArgumentList @("-m", "pip", "--version")
    )) {
        Write-Info "Repairing pip in the course Python environment."
        & $VenvPython -m ensurepip --upgrade
        if ($LASTEXITCODE -ne 0) {
            throw "pip could not be repaired in the course Python environment."
        }
        $script:Changed = $true
    }

    $MissingPackages = @()
    foreach ($PackageName in $RequiredPackages) {
        $PackageIsInstalled = Test-NativeCommandExitSuccess `
            -FilePath $VenvPython `
            -ArgumentList @("-m", "pip", "show", $PackageName)
        if (-not $PackageIsInstalled) {
            $MissingPackages += $PackageName
        }
    }

    if ($MissingPackages.Count -gt 0) {
        Write-Info (
            "Installing missing course Python packages: {0}" -f
            ($MissingPackages -join ", ")
        )
        & $VenvPython -m pip install @MissingPackages
        if ($LASTEXITCODE -ne 0) {
            throw "One or more required course Python packages could not be installed."
        }
        $script:Changed = $true
    }
    else {
        Write-Success "Required course Python packages are already installed."
    }

    Write-Success "The course Python environment is configured."
}

function Get-GitConfigValue {
    param([Parameter(Mandatory = $true)][string]$Key)

    $ObservedOutput = @(& git.exe config --global --get $Key 2>$null)
    if ($LASTEXITCODE -ne 0 -or $ObservedOutput.Count -eq 0) {
        return ""
    }
    return ([string]$ObservedOutput[0]).Trim()
}

function Set-GitHubIdentity {
    param([Parameter(Mandatory = $true)]$Manifest)

    $GitHubIsAuthenticated = Test-NativeCommandExitSuccess `
        -FilePath "gh.exe" `
        -ArgumentList @("auth", "status", "--hostname", "github.com")
    if (-not $GitHubIsAuthenticated) {
        if ($NonInteractive) {
            throw "GitHub authentication requires an existing login in noninteractive mode."
        }

        Write-Notice "GitHub authentication is required."
        Write-Notice (
            "GitHub CLI will copy a one-time code to the clipboard and open " +
            "GitHub's secure web sign-in flow."
        )
        Write-Notice "Paste the one-time code into the browser when prompted."
        $Confirmation = Read-Host "Press ENTER to continue, or type CANCEL"
        if ($Confirmation -match "^(?i:cancel)$") {
            throw [OperationCanceledException]::new(
                "GitHub authentication was canceled."
            )
        }

        & gh.exe auth login `
            --hostname github.com `
            --git-protocol https `
            --web `
            --clipboard
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub authentication did not complete."
        }
        $script:Changed = $true
    }

    $GitHubIsAuthenticated = Test-NativeCommandExitSuccess `
        -FilePath "gh.exe" `
        -ArgumentList @("auth", "status", "--hostname", "github.com")
    if (-not $GitHubIsAuthenticated) {
        throw "GitHub authentication could not be verified."
    }

    & gh.exe auth setup-git --hostname github.com
    if ($LASTEXITCODE -ne 0) {
        throw "Git could not be connected to the authenticated GitHub CLI session."
    }

    $GitHubUserOutput = @(& gh.exe api user --jq ".login")
    $GitHubIdOutput = @(& gh.exe api user --jq ".id")
    if (
        $LASTEXITCODE -ne 0 -or
        $GitHubUserOutput.Count -eq 0 -or
        $GitHubIdOutput.Count -eq 0
    ) {
        throw "The authenticated GitHub account identity could not be retrieved."
    }

    $script:GitHubUser = ([string]$GitHubUserOutput[0]).Trim()
    $GitHubId = ([string]$GitHubIdOutput[0]).Trim()
    if (
        [string]::IsNullOrWhiteSpace($GitHubUser) -or
        $GitHubId -notmatch "^[0-9]+$"
    ) {
        throw "The authenticated GitHub account identity is invalid."
    }

    $ExistingDisplayName = Get-GitConfigValue -Key "user.name"
    if ([string]::IsNullOrWhiteSpace($ExistingDisplayName)) {
        $DefaultDisplayName = $GitHubUser
    }
    else {
        $DefaultDisplayName = $ExistingDisplayName
    }

    if ($NonInteractive) {
        $GitDisplayName = $DefaultDisplayName
    }
    else {
        Write-Host ""
        Write-Notice "Your Git display name is public in version-control history."
        Write-Notice (
            "Press Enter to accept the displayed default, or enter a " +
            "different author name."
        )
        $InputName = Read-Host "Git display name [$DefaultDisplayName]"
        if ([string]::IsNullOrWhiteSpace($InputName)) {
            $GitDisplayName = $DefaultDisplayName
        }
        else {
            $GitDisplayName = $InputName.Trim()
        }
    }

    if (
        [string]::IsNullOrWhiteSpace($GitDisplayName) -or
        $GitDisplayName.Length -gt 100 -or
        $GitDisplayName -match "[`r`n]"
    ) {
        throw "The Git display name is not valid."
    }

    $PrivateEmail = "{0}+{1}@users.noreply.github.com" -f $GitHubId, $GitHubUser

    & git.exe config --global user.name $GitDisplayName
    if ($LASTEXITCODE -ne 0) {
        throw "The Git display name could not be configured."
    }
    & git.exe config --global user.email $PrivateEmail
    if ($LASTEXITCODE -ne 0) {
        throw "The privacy-preserving Git email could not be configured."
    }

    $GitSettings = Get-PropertyValue `
        -Object $Manifest.managed_settings `
        -Name "git_course_defaults"
    if ($null -eq $GitSettings) {
        throw "The controlled Git settings profile is missing."
    }

    foreach ($PropertyRecord in $GitSettings.values.PSObject.Properties) {
        $SettingValue = $PropertyRecord.Value
        if ($SettingValue -is [bool]) {
            $SettingValue = $SettingValue.ToString().ToLowerInvariant()
        }
        & git.exe config --global $PropertyRecord.Name ([string]$SettingValue)
        if ($LASTEXITCODE -ne 0) {
            throw "Git setting failed: $($PropertyRecord.Name)"
        }
    }

    $script:Changed = $true
    Write-Success "GitHub authentication and the privacy-preserving Git identity are configured."
    Write-Info "GitHub user      : $GitHubUser"
    Write-Info "Git display name : $GitDisplayName"
    Write-Info "Git email        : private GitHub noreply address configured"
}

function Install-VsCodeExtension {
    param([Parameter(Mandatory = $true)][string[]]$RequiredExtensions)

    $InstalledExtensions = @(
        & code.cmd --list-extensions 2>$null |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() }
    )
    if ($LASTEXITCODE -ne 0) {
        throw "The installed VS Code extensions could not be listed."
    }

    $MissingExtensions = @()
    foreach ($ExtensionId in $RequiredExtensions) {
        if ($ExtensionId.ToLowerInvariant() -notin $InstalledExtensions) {
            $MissingExtensions += $ExtensionId
        }
    }

    if ($MissingExtensions.Count -eq 0) {
        Write-Success "Required VS Code extensions are already installed."
        return
    }

    $PreviousNodeWarnings = [Environment]::GetEnvironmentVariable(
        "NODE_NO_WARNINGS",
        "Process"
    )
    $env:NODE_NO_WARNINGS = "1"
    try {
        foreach ($ExtensionId in $MissingExtensions) {
            Write-Info "Installing required VS Code extension: $ExtensionId"
            & code.cmd --install-extension $ExtensionId
            if ($LASTEXITCODE -ne 0) {
                throw "VS Code extension installation failed: $ExtensionId"
            }
            $script:Changed = $true
        }
    }
    finally {
        if ($null -eq $PreviousNodeWarnings) {
            Remove-Item Env:NODE_NO_WARNINGS -ErrorAction SilentlyContinue
        }
        else {
            $env:NODE_NO_WARNINGS = $PreviousNodeWarnings
        }
    }

    Write-Success "Required VS Code extensions are installed."
}

function ConvertTo-Hashtable {
    param($InputObject)

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [Collections.IDictionary]) {
        $OutputTable = @{}
        foreach ($Key in $InputObject.Keys) {
            $OutputTable[$Key] = ConvertTo-Hashtable -InputObject $InputObject[$Key]
        }
        return $OutputTable
    }
    if ($InputObject -is [pscustomobject]) {
        $OutputTable = @{}
        foreach ($PropertyRecord in $InputObject.PSObject.Properties) {
            $OutputTable[$PropertyRecord.Name] = ConvertTo-Hashtable `
                -InputObject $PropertyRecord.Value
        }
        return $OutputTable
    }
    if (
        $InputObject -is [Collections.IEnumerable] -and
        $InputObject -isnot [string]
    ) {
        return @(
            $InputObject | ForEach-Object {
                ConvertTo-Hashtable -InputObject $_
            }
        )
    }
    return $InputObject
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

function Get-ManagedVsCodeSetting {
    param([Parameter(Mandatory = $true)]$Manifest)

    $SettingsProfile = Get-PropertyValue `
        -Object $Manifest.managed_settings `
        -Name "vscode_course_defaults"
    if ($null -eq $SettingsProfile) {
        throw "The controlled VS Code settings profile is missing."
    }

    $ManagedSettings = ConvertTo-Hashtable -InputObject $SettingsProfile.values
    $ImplementationSettings = @{
        "files.autoSave" = "afterDelay"
        "files.autoSaveDelay" = 1000
        "files.trimTrailingWhitespace" = $true
        "files.insertFinalNewline" = $true
        "terminal.integrated.defaultProfile.windows" = "PowerShell"
        "python.defaultInterpreterPath" = $VenvPython
        "python.testing.pytestArgs" = @(".")
        "cSpell.language" = "en"
        "workbench.editorAssociations" = @{
            "README.md" = "vscode.markdown.preview.editor"
            "*_srs.md" = "vscode.markdown.preview.editor"
            "*_sdd.md" = "vscode.markdown.preview.editor"
        }
        "settingsSync.ignoredSettings" = @(
            "python.defaultInterpreterPath"
        )
    }
    Merge-Hashtable -Target $ManagedSettings -Source $ImplementationSettings
    return $ManagedSettings
}

function Write-Utf8LfFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $LfContent = $Content -replace "`r`n", "`n"
    $Utf8NoBom = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($Path, $LfContent, $Utf8NoBom)
}

function Set-VsCodeSetting {
    param([Parameter(Mandatory = $true)]$Manifest)

    $SettingsDirectory = Split-Path -Parent $VsCodeSettings
    New-Item -ItemType Directory -Path $SettingsDirectory -Force | Out-Null

    $ExistingSettings = @{}
    if (Test-Path -LiteralPath $VsCodeSettings -PathType Leaf) {
        try {
            $ExistingObject = Get-Content -LiteralPath $VsCodeSettings -Raw |
                ConvertFrom-Json
            if ($null -eq $ExistingObject -or $ExistingObject -isnot [pscustomobject]) {
                throw "The root value is not a JSON object."
            }
            $ExistingSettings = ConvertTo-Hashtable -InputObject $ExistingObject
        }
        catch {
            $DiagnosticPath = Join-Path `
                $LogDirectory `
                "invalid_vscode_settings_diagnostic.txt"
            $DiagnosticText = @(
                "The existing VS Code settings file is invalid and was not changed."
                "Settings path: $VsCodeSettings"
                "Parser result: $($_.Exception.GetType().Name)"
            ) -join "`n"
            Write-Utf8LfFile `
                -Path $DiagnosticPath `
                -Content ("$DiagnosticText`n")
            throw (
                "Existing VS Code settings are invalid. The original file was " +
                "preserved; a content-free diagnostic was written to $DiagnosticPath."
            )
        }
    }

    $ManagedSettings = Get-ManagedVsCodeSetting -Manifest $Manifest
    Merge-Hashtable -Target $ExistingSettings -Source $ManagedSettings

    $SerializedSettings = (
        $ExistingSettings | ConvertTo-Json -Depth 50
    ) -replace "`r`n", "`n"
    $SerializedSettings += "`n"

    $StagedPath = "$VsCodeSettings.it140.tmp"
    $BackupPath = "$VsCodeSettings.it140.bak"
    Write-Utf8LfFile -Path $StagedPath -Content $SerializedSettings

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
        Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue
        $script:Changed = $true
    }
    catch {
        Remove-Item -LiteralPath $StagedPath -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $BackupPath -PathType Leaf) {
            Copy-Item `
                -LiteralPath $BackupPath `
                -Destination $VsCodeSettings `
                -Force
            Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }

    Write-Success "Course-managed VS Code settings were merged without removing unrelated settings."
}

function Get-VsCodeExecutablePath {
    $CodeCommand = Get-Command code.cmd -ErrorAction SilentlyContinue
    if ($null -eq $CodeCommand) {
        return $null
    }

    $CodeBinDirectory = Split-Path -Parent $CodeCommand.Source
    $CandidatePath = Join-Path (Split-Path -Parent $CodeBinDirectory) "Code.exe"
    if (Test-Path -LiteralPath $CandidatePath -PathType Leaf) {
        return $CandidatePath
    }

    $CodeExecutable = Get-Command Code.exe -ErrorAction SilentlyContinue
    if ($null -ne $CodeExecutable) {
        return $CodeExecutable.Source
    }
    return $null
}

function Test-ShortcutTargetsRepos {
    param([Parameter(Mandatory = $true)][string]$ShortcutPath)

    if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) {
        return $false
    }
    try {
        $ShellApplication = New-Object -ComObject WScript.Shell
        $Shortcut = $ShellApplication.CreateShortcut($ShortcutPath)
        $ExpectedExplorer = Join-Path $env:SystemRoot "explorer.exe"
        return (
            [string]::Equals(
                [IO.Path]::GetFullPath($Shortcut.TargetPath),
                [IO.Path]::GetFullPath($ExpectedExplorer),
                [StringComparison]::OrdinalIgnoreCase
            ) -and
            $Shortcut.Arguments -like "*$ReposRoot*"
        )
    }
    catch {
        return $false
    }
}

function Set-RepositoryWorkspace {
    if (-not (Test-Path -LiteralPath $ReposRoot -PathType Container)) {
        if (Test-Path -LiteralPath $ReposRoot) {
            throw "The required repository workspace path exists but is not a directory: $ReposRoot"
        }
        New-Item -ItemType Directory -Path $ReposRoot | Out-Null
        $script:Changed = $true
    }

    # The parent directory is automation-managed only for existence and its
    # icon metadata. Never recurse into, enumerate for repair, or permission-
    # reset student repositories stored beneath it.
    $VsCodeExecutable = Get-VsCodeExecutablePath
    if ([string]::IsNullOrWhiteSpace($VsCodeExecutable)) {
        Write-WarningMessage (
            "Visual Studio Code could not be resolved for the optional Repos " +
            "folder icon. The development workspace itself remains usable."
        )
    }
    else {
        $DesktopIni = @(
            "[.ShellClassInfo]"
            "IconResource=$VsCodeExecutable,0"
            "InfoTip=IT 140 development repositories"
            ""
        ) -join "`r`n"
        Set-Content -LiteralPath $ReposDesktopIniPath -Value $DesktopIni -Encoding Unicode -Force
        & attrib.exe +h +s $ReposDesktopIniPath 2>$null
        & attrib.exe +r $ReposRoot 2>$null
        $script:Changed = $true
    }

    $DesktopDirectory = [Environment]::GetFolderPath("Desktop")
    if ([string]::IsNullOrWhiteSpace($DesktopDirectory)) {
        throw "The Windows Desktop directory could not be resolved."
    }
    New-Item -ItemType Directory -Path $DesktopDirectory -Force | Out-Null

    if (Test-Path -LiteralPath $ReposShortcutPath -PathType Leaf) {
        if (-not (Test-ShortcutTargetsRepos -ShortcutPath $ReposShortcutPath)) {
            throw (
                "An unmanaged desktop shortcut already uses the name Repos.lnk. " +
                "It was preserved: $ReposShortcutPath"
            )
        }
    }
    elseif (Test-Path -LiteralPath $ReposShortcutPath) {
        throw (
            "An unmanaged desktop item already uses the required Repos shortcut " +
            "name and was preserved: $ReposShortcutPath"
        )
    }

    $ShellApplication = New-Object -ComObject WScript.Shell
    $ReposShortcut = $ShellApplication.CreateShortcut($ReposShortcutPath)
    $ReposShortcut.TargetPath = "$env:SystemRoot\explorer.exe"
    $ReposShortcut.Arguments = ('"{0}"' -f $ReposRoot)
    $ReposShortcut.WorkingDirectory = $ReposRoot
    if ($VsCodeExecutable) {
        $ReposShortcut.IconLocation = "$VsCodeExecutable,0"
    }
    else {
        $ReposShortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,3"
    }
    $ReposShortcut.Description = "Open the IT 140 development repository workspace"
    $ReposShortcut.Save()
    $script:Changed = $true

    if (-not (Test-ShortcutTargetsRepos -ShortcutPath $ReposShortcutPath)) {
        throw "The Repos desktop shortcut did not validate after configuration."
    }

    Write-Success "The repository workspace and desktop Repos shortcut are configured: $ReposRoot"
}

function Test-ManagedSettingValue {
    param(
        [Parameter(Mandatory = $true)]$Observed,
        [Parameter(Mandatory = $true)]$Expected
    )

    if ($Expected -is [hashtable]) {
        if ($Observed -isnot [pscustomobject] -and $Observed -isnot [hashtable]) {
            return $false
        }
        foreach ($Key in $Expected.Keys) {
            if ($Observed -is [hashtable]) {
                if (-not $Observed.ContainsKey($Key)) {
                    return $false
                }
                $ObservedValue = $Observed[$Key]
            }
            else {
                $ObservedProperty = $Observed.PSObject.Properties[$Key]
                if ($null -eq $ObservedProperty) {
                    return $false
                }
                $ObservedValue = $ObservedProperty.Value
            }
            if (-not (
                Test-ManagedSettingValue `
                    -Observed $ObservedValue `
                    -Expected $Expected[$Key]
            )) {
                return $false
            }
        }
        return $true
    }

    return (
        ($Observed | ConvertTo-Json -Compress -Depth 30) -ceq
        ($Expected | ConvertTo-Json -Compress -Depth 30)
    )
}

function Test-ConfiguredUserLayer {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string[]]$RequiredPackages,
        [Parameter(Mandatory = $true)][string[]]$RequiredExtensions
    )

    foreach ($RequiredDirectory in @(
        $CourseRoot,
        $ReposRoot,
        $LogDirectory,
        $WindowsScriptDirectory,
        $VenvDirectory
    )) {
        if (-not (Test-Path -LiteralPath $RequiredDirectory -PathType Container)) {
            throw "Required course directory is missing: $RequiredDirectory"
        }
    }
    if (-not (Test-VenvPython)) {
        throw "The course Python 3.12 virtual environment is not usable."
    }

    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    foreach ($ManagedPath in @($VenvScriptsDirectory, $WindowsScriptDirectory)) {
        if (-not (Test-PathContainsEntry -PathValue $UserPath -ExpectedEntry $ManagedPath)) {
            throw "The user PATH is missing: $ManagedPath"
        }
        if (-not (Test-PathContainsEntry -PathValue $env:Path -ExpectedEntry $ManagedPath)) {
            throw "The current process PATH is missing: $ManagedPath"
        }
    }

    foreach ($PackageName in $RequiredPackages) {
        $PackageIsInstalled = Test-NativeCommandExitSuccess `
            -FilePath $VenvPython `
            -ArgumentList @("-m", "pip", "show", $PackageName)
        if (-not $PackageIsInstalled) {
            throw "Required course Python package is missing: $PackageName"
        }
    }

    $InstalledExtensions = @(
        & code.cmd --list-extensions 2>$null |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() }
    )
    foreach ($ExtensionId in $RequiredExtensions) {
        if ($ExtensionId.ToLowerInvariant() -notin $InstalledExtensions) {
            throw "Required VS Code extension is missing: $ExtensionId"
        }
    }

    $GitHubIsAuthenticated = Test-NativeCommandExitSuccess `
        -FilePath "gh.exe" `
        -ArgumentList @("auth", "status", "--hostname", "github.com")
    if (-not $GitHubIsAuthenticated) {
        throw "GitHub authentication is not valid."
    }
    if ([string]::IsNullOrWhiteSpace((Get-GitConfigValue -Key "user.name"))) {
        throw "The Git display name is missing."
    }
    if (
        (Get-GitConfigValue -Key "user.email") -notmatch
        "^[0-9]+\+[^@\s]+@users\.noreply\.github\.com$"
    ) {
        throw "The privacy-preserving GitHub noreply identity is not configured."
    }

    $GitSettings = Get-PropertyValue `
        -Object $Manifest.managed_settings `
        -Name "git_course_defaults"
    foreach ($PropertyRecord in $GitSettings.values.PSObject.Properties) {
        $ExpectedValue = $PropertyRecord.Value
        if ($ExpectedValue -is [bool]) {
            $ExpectedValue = $ExpectedValue.ToString().ToLowerInvariant()
        }
        if ((Get-GitConfigValue -Key $PropertyRecord.Name) -cne [string]$ExpectedValue) {
            throw "Managed Git setting is not configured: $($PropertyRecord.Name)"
        }
    }

    if (-not (Test-Path -LiteralPath $VsCodeSettings -PathType Leaf)) {
        throw "The VS Code settings file is missing."
    }
    $ObservedSettings = Get-Content -LiteralPath $VsCodeSettings -Raw |
        ConvertFrom-Json
    $ExpectedSettings = Get-ManagedVsCodeSetting -Manifest $Manifest
    if (-not (Test-ManagedSettingValue -Observed $ObservedSettings -Expected $ExpectedSettings)) {
        throw "One or more course-managed VS Code settings are missing or different."
    }

    if (-not (Test-ShortcutTargetsRepos -ShortcutPath $ReposShortcutPath)) {
        throw "The required desktop Repos shortcut does not target the repository workspace."
    }

    if (Test-Path -LiteralPath $ReposDesktopIniPath -PathType Leaf) {
        $DesktopIniText = Get-Content -LiteralPath $ReposDesktopIniPath -Raw
        if ($DesktopIniText -notmatch '(?m)^IconResource=.+,0\s*$') {
            throw "The repository workspace development icon metadata is invalid."
        }
    }

    $VerifyScript = Join-Path $WindowsScriptDirectory "verify_it140.ps1"
    if (-not (Test-Path -LiteralPath $VerifyScript -PathType Leaf)) {
        throw "The Windows verification script is missing: $VerifyScript"
    }

    Write-Success "User-layer post-validation passed."
}

Resolve-DeploymentProfile

if ($Help) {
    Show-Usage
    exit 0
}
if ($Version) {
    Write-Host "Artifact version   : $ScriptVersion"
    Write-Host "Version DTG        : $VersionDate"
    Write-Host "Development status : $DevelopmentStatus"
    exit 0
}

try {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    Start-Transcript -Path $LogPath -Append -Force | Out-Null
    $TranscriptStarted = $true
    Remove-ExpiredLog

    Write-Header "IT 140 WINDOWS CONFIGURATION"
    Write-Info "Script version   : $ScriptVersion"
    Write-Info "Version DTG      : $VersionDate"
    Write-Info "Status           : $DevelopmentStatus"
    Write-Info "Deployment       : $DeploymentProfile"
    Write-Info "Current user     : $([Environment]::UserName)"
    Write-Info "Course root      : $CourseRoot"
    Write-Info "Repository root  : $ReposRoot"
    Write-Info "Log file         : $LogPath"
    Write-Notice "This script changes only the current user's IT 140 environment."
    Write-Notice "It does not install or update system-wide software."

    $IsWindowsSandbox = Test-IsWindowsSandbox
    $IsAdministrator = Test-IsAdministrator

    if ($DeploymentProfile -eq "windows_sandbox" -and -not $IsWindowsSandbox) {
        $FailureExitCode = 2
        throw (
            "The windows_sandbox deployment profile can be used only inside " +
            "Windows Sandbox."
        )
    }
    if ($DeploymentProfile -eq "windows_bare_metal" -and $IsWindowsSandbox) {
        $FailureExitCode = 2
        throw "Windows Sandbox requires the windows_sandbox deployment profile."
    }

    if ($DeploymentProfile -eq "windows_bare_metal" -and $IsAdministrator) {
        $FailureExitCode = 3
        throw (
            "Do not run configure_it140.ps1 from an elevated terminal on a regular " +
            "Windows computer. Open a normal Windows PowerShell window under " +
            "the intended user and rerun it."
        )
    }
    if ($DeploymentProfile -eq "windows_sandbox" -and -not $IsAdministrator) {
        $FailureExitCode = 3
        throw (
            "The Windows Sandbox deployment requires its administrative " +
            "container account."
        )
    }

    if ($DeploymentProfile -eq "windows_sandbox") {
        Write-Notice (
            "Windows Sandbox uses its administrative container account. This " +
            "context is expected for the windows_sandbox deployment."
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

    $FailureExitCode = 1
    Test-SystemLayer -Platform $Controlled.Platform

    New-Item -ItemType Directory -Path $CourseRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $WindowsScriptDirectory -Force | Out-Null

    Set-ManagedUserPath

    $FailureExitCode = 4
    $RequiredPackages = Get-RequiredPythonPackage -Platform $Controlled.Platform
    Install-CoursePythonEnvironment -RequiredPackages $RequiredPackages
    Set-ManagedUserPath

    Set-GitHubIdentity -Manifest $Controlled.Manifest

    $RequiredExtensions = Get-RequiredExtension -Platform $Controlled.Platform
    Install-VsCodeExtension -RequiredExtensions $RequiredExtensions

    $FailureExitCode = 1
    Set-RepositoryWorkspace
    Set-VsCodeSetting -Manifest $Controlled.Manifest

    Test-ConfiguredUserLayer `
        -Manifest $Controlled.Manifest `
        -RequiredPackages $RequiredPackages `
        -RequiredExtensions $RequiredExtensions

    $Elapsed = (Get-Date) - $StartTime
    Write-Header "CONFIGURATION SUMMARY"
    Write-Success "The current Windows user is configured for IT 140."
    Write-Info "Result            : PASS"
    Write-Info "Script version    : $ScriptVersion"
    Write-Info "Version DTG       : $VersionDate"
    Write-Info "Status            : $DevelopmentStatus"
    Write-Info "Manifest release  : $($Controlled.Manifest.automation_release)"
    Write-Info "Manifest DTG      : $($Controlled.Manifest.automation_release_date_time_group)"
    Write-Info "GitHub login      : $GitHubUser"
    Write-Info "Course folder     : $CourseRoot"
    Write-Info "Repository folder : $ReposRoot"
    Write-Info "Course interpreter: $VenvPython"
    Write-Info "Warnings          : $WarningCount"
    Write-Info "Failures          : 0"
    Write-Info ("Elapsed time      : {0:hh\:mm\:ss}" -f $Elapsed)
    Write-Info "Log file          : $LogPath"
    Write-Notice (
        "Next step: close this window, open a new PowerShell window, and " +
        "run verify_it140.ps1."
    )
    Write-Info "Exit code         : 0"
    Write-ClosingNotice
    $ExitCode = 0
}
catch [OperationCanceledException] {
    Write-Notice $_.Exception.Message
    Write-Info "Configuration log: $LogPath"
    if ($Changed) {
        Write-Notice (
            "Managed user state changed before configuration was canceled. " +
            "Rerun configure_it140.ps1."
        )
        $ExitCode = 7
    }
    else {
        $ExitCode = 6
    }
}
catch {
    $LineNumber = $_.InvocationInfo.ScriptLineNumber
    Write-ErrorMessage $_.Exception.Message
    if ($LineNumber) {
        Write-ErrorMessage "Configuration stopped near line $LineNumber."
    }
    Write-Info "Configuration log: $LogPath"
    if ($Changed) {
        Write-Notice (
            "Managed user state changed before configuration stopped. " +
            "Rerun configure_it140.ps1 to repair it."
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
