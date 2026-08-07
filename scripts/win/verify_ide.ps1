#requires -Version 5.1
<#
.SYNOPSIS
Verifies the Windows IT 140 Course IDE without repairing it.

.DESCRIPTION
Performs read-only checks of the supported Windows release, controlled
manifest assets, required software, course Python environment, VS Code
extensions and settings, GitHub authentication, privacy-preserving Git
identity, Windows PATH, the separate Repos development workspace, desktop integration, and lifecycle scripts.

The script never elevates privilege or repairs failed checks. It requires a
normal, non-elevated context on a regular Windows computer and recognizes the
administrative Windows Sandbox container context as an intentional exception.
It creates only the required transcript and, when explicitly requested and
confirmed, a sanitized support bundle under ~/it140/logs.

Artifact version:
    0.8.0-alpha.1

Version date-time group:
    2026-08-07-10-44

Development status:
    Alpha Testing

Version basis:
    Version 0.1.0 represents the initial Windows verification baseline.
    Version 0.2.0 adopts SemVer metadata and manifest schema 2.0.
    Version 0.2.1 prevents expected native-command probe failures from
    terminating Windows PowerShell 5.1.

    Version 0.3.0 adds support for Windows 10, version 22H2, while preserving
    manifest-controlled Windows 11 release validation.
    Version 0.8.0-alpha.1 adds read-only verification of the separate Repos
    workspace, Explorer development icon metadata, and desktop Repos shortcut.


.NOTES
Exit codes:
  0 All required checks passed; warnings may be present
  1 One or more required checks failed
  2 The Windows platform or release is unsupported
  5 Controlled manifest or managed asset validation failed

Logs and explicitly requested support bundles are written under
~/it140/logs/.

.USAGE
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
verify_ide.ps1

#>

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Version,
    [switch]$NonInteractive,
    [ValidateSet("windows_bare_metal", "windows_sandbox")]
    [string]$DeploymentProfile,
    [switch]$SupportBundle,
    [Alias("ConfirmSupportBundle")]
    [switch]$Yes,
    [switch]$SkipNetwork
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ScriptVersion = "0.8.0-alpha.1"
$VersionDate = "2026-08-07-10-44"
$DevelopmentStatus = "Alpha Testing"
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
    "verify_{0}_{1}.log" -f $PlatformAbbreviation, (Get-Date -Format "yyyyMMdd_HHmmss")
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
$ManifestFailure = $false
$UnsupportedFailure = $false
$ExitCode = 0
$Controlled = $null
$WindowsFacts = $null
$Results = [Collections.Generic.List[object]]::new()
$Remediations = [Collections.Generic.List[string]]::new()

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

function Write-Notice {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[NOTICE] $Message"
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
IT 140 Windows verification script

Usage:
  powershell.exe -ExecutionPolicy Bypass -File .\verify_ide.ps1
  powershell.exe -ExecutionPolicy Bypass -File .\verify_ide.ps1 -SkipNetwork
  powershell.exe -ExecutionPolicy Bypass -File .\verify_ide.ps1 -SupportBundle
  powershell.exe -ExecutionPolicy Bypass -File .\verify_ide.ps1 -SupportBundle -Yes
  powershell.exe -ExecutionPolicy Bypass -File .\verify_ide.ps1 -Help
  powershell.exe -ExecutionPolicy Bypass -File .\verify_ide.ps1 -Version

This script does not elevate privilege, install, repair, update, remove, or
rewrite managed course state. Regular Windows requires a non-elevated context;
Windows Sandbox uses its expected administrative container context. When the
profile is omitted, the script selects it from the detected environment.
Support-bundle creation requires explicit confirmation unless -Yes is supplied.

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
        "Open a new PowerShell window before running another script or " +
        "command so it uses the intended PATH and environment settings."
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

function Get-ConfigRemediation {
    if ($DeploymentProfile -eq "windows_sandbox") {
        return "Run configure_ide.ps1 in the Windows Sandbox PowerShell window."
    }
    return "Run configure_ide.ps1 from a normal PowerShell window."
}

function Get-BootstrapRemediation {
    if ($DeploymentProfile -eq "windows_sandbox") {
        return (
            "Start a fresh Windows Sandbox session with it140_wsb.wsb, then " +
            "rerun configure_ide.ps1."
        )
    }
    return "Run prepare_ide.ps1 again, then configure_ide.ps1."
}

function Get-SystemSetupRemediation {
    if ($DeploymentProfile -eq "windows_sandbox") {
        return "Run setup_wsb.ps1 in the Windows Sandbox PowerShell window."
    }
    return "Run install_ide.ps1 from an elevated PowerShell window."
}

function Get-SystemRepairRemediation {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("package", "command")]
        [string]$CapabilityType
    )

    if ($DeploymentProfile -eq "windows_sandbox") {
        return "Run setup_wsb.ps1 in the Windows Sandbox PowerShell window."
    }
    if ($CapabilityType -eq "package") {
        return (
            "Run update_ide.ps1; if it cannot repair the package, " +
            "run install_ide.ps1."
        )
    }
    return (
        "Run update_ide.ps1; if it cannot repair the command, " +
        "run install_ide.ps1."
    )
}

function Get-ManagedAssetRemediation {
    if ($DeploymentProfile -eq "windows_sandbox") {
        return (
            "Start a fresh Windows Sandbox session with it140_wsb.wsb. " +
            "Windows Sandbox does not use update_ide.ps1."
        )
    }
    return "Run prepare_ide.ps1 again, then update_ide.ps1."
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

function Add-CheckResult {
    param(
        [Parameter(Mandatory = $true)][string]$CheckId,
        [Parameter(Mandatory = $true)]
        [ValidateSet("PASS", "WARNING", "FAIL", "NOT APPLICABLE")]
        [string]$Status,
        [Parameter(Mandatory = $true)][string]$Detail,
        [string]$Remediation = ""
    )

    $ResultRecord = [pscustomobject]@{
        CheckId = $CheckId
        Status = $Status
        Detail = $Detail
        Remediation = $Remediation
    }
    $Results.Add($ResultRecord)

    $Label = "[$Status]"
    Write-Host ("{0,-18} {1,-40} {2}" -f $Label, $CheckId, $Detail)

    if (
        $Status -in @("FAIL", "WARNING") -and
        -not [string]::IsNullOrWhiteSpace($Remediation) -and
        $Remediation -notin $Remediations
    ) {
        $Remediations.Add($Remediation)
    }
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
    $SemVerPattern = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
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

function Test-CommandAvailable {
    param([Parameter(Mandatory = $true)][string]$CommandName)
    return $null -ne (Get-Command $CommandName -ErrorAction SilentlyContinue)
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
    return $Bindings
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

function Get-GitConfigValue {
    param([Parameter(Mandatory = $true)][string]$Key)

    $ObservedOutput = @(& git.exe config --global --get $Key 2>$null)
    if ($LASTEXITCODE -ne 0 -or $ObservedOutput.Count -eq 0) {
        return ""
    }
    return ([string]$ObservedOutput[0]).Trim()
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

function Test-PowerShellScript {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Tokens = $null
    $ParseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$Tokens,
        [ref]$ParseErrors
    )
    if ($ParseErrors.Count -gt 0) {
        $Messages = @($ParseErrors | ForEach-Object { $_.Message }) -join "; "
        throw "PowerShell validation failed. $Messages"
    }
}

function Get-ScriptVersion {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowLegacyCalendarVersion
    )

    $ScriptText = Get-Content -LiteralPath $Path -Raw
    $StrictSemVer = (
        '(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
    )
    foreach ($VariableName in @("ScriptVersion", "ArtifactVersion")) {
        $VersionMatch = [regex]::Match(
            $ScriptText,
            '(?m)^\$' + $VariableName + '\s*=\s*"(?<version>' +
            $StrictSemVer + ')"\s*$'
        )
        if ($VersionMatch.Success) {
            return $VersionMatch.Groups["version"].Value
        }
    }

    if ($AllowLegacyCalendarVersion) {
        $LegacyCalendarVersion = '20[0-9]{2}\.[0-9]{2}\.[0-9]{2}\.[1-9][0-9]*'
        foreach ($VariableName in @("ScriptVersion", "ArtifactVersion")) {
            $VersionMatch = [regex]::Match(
                $ScriptText,
                '(?m)^\$' + $VariableName + '\s*=\s*"(?<version>' +
                $LegacyCalendarVersion + ')"\s*$'
            )
            if ($VersionMatch.Success) {
                return $VersionMatch.Groups["version"].Value
            }
        }
    }

    throw "A recognized script or artifact version could not be read."
}

function Get-ShortcutDefinition {
    param([Parameter(Mandatory = $true)][string]$Path)

    $ShellApplication = New-Object -ComObject WScript.Shell
    $Shortcut = $ShellApplication.CreateShortcut($Path)
    return [pscustomobject]@{
        TargetPath = [string]$Shortcut.TargetPath
        Arguments = [string]$Shortcut.Arguments
        WorkingDirectory = [string]$Shortcut.WorkingDirectory
    }
}

function Test-PendingRestart {
    $RestartRegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )
    foreach ($RegistryPath in $RestartRegistryPaths) {
        if (Test-Path -LiteralPath $RegistryPath) {
            return $true
        }
    }

    try {
        $SessionManager = Get-ItemProperty `
            -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
        if ($null -ne $SessionManager.PendingFileRenameOperations) {
            return $true
        }
    }
    catch {
        # Best-effort operation; preserve the primary result.
    }
    return $false
}

function Test-WinGetPackageInstalled {
    param([Parameter(Mandatory = $true)][string]$PackageIdentifier)

    return Test-NativeCommandExitSuccess `
        -FilePath "winget.exe" `
        -ArgumentList @(
            "list",
            "--id",
            $PackageIdentifier,
            "--exact",
            "--source",
            "winget",
            "--accept-source-agreements",
            "--disable-interactivity"
        )
}

function Test-PlatformContext {
    param(
        [Parameter(Mandatory = $true)]$Platform,
        [Parameter(Mandatory = $true)]$ObservedWindowsFacts
    )

    $IsWindowsSandbox = Test-IsWindowsSandbox
    $IsAdministrator = Test-IsAdministrator

    if ($DeploymentProfile -eq "windows_sandbox" -and -not $IsWindowsSandbox) {
        $script:UnsupportedFailure = $true
        Add-CheckResult `
            -CheckId "verify.deployment_context" `
            -Status "FAIL" `
            -Detail "windows_sandbox was selected outside Windows Sandbox" `
            -Remediation "Use windows_bare_metal on a regular Windows computer."
    }
    elseif ($DeploymentProfile -eq "windows_bare_metal" -and $IsWindowsSandbox) {
        $script:UnsupportedFailure = $true
        Add-CheckResult `
            -CheckId "verify.deployment_context" `
            -Status "FAIL" `
            -Detail "Windows Sandbox was assigned the bare-metal profile" `
            -Remediation "Rerun verify_ide.ps1 with windows_sandbox."
    }
    else {
        Add-CheckResult `
            -CheckId "verify.deployment_context" `
            -Status "PASS" `
            -Detail "The selected deployment profile matches the environment"
    }

    if ($DeploymentProfile -eq "windows_sandbox") {
        if ($IsWindowsSandbox -and $IsAdministrator) {
            Add-CheckResult `
                -CheckId "verify.user_context" `
                -Status "PASS" `
                -Detail "Windows Sandbox administrative container context"
        }
        else {
            Add-CheckResult `
                -CheckId "verify.user_context" `
                -Status "FAIL" `
                -Detail "The expected Windows Sandbox administrator context is unavailable" `
                -Remediation (
                    "Start a fresh Windows Sandbox session with it140_wsb.wsb " +
                    "and rerun the lifecycle."
                )
        }
    }
    elseif ($IsAdministrator) {
        Add-CheckResult `
            -CheckId "verify.user_context" `
            -Status "FAIL" `
            -Detail "Verification is running from an elevated terminal." `
            -Remediation (
                "Close this window and rerun verify_ide.ps1 from a normal " +
                "PowerShell window."
            )
    }
    else {
        Add-CheckResult `
            -CheckId "verify.user_context" `
            -Status "PASS" `
            -Detail "Normal, non-elevated user context"
    }

    $IsWindows10 = $ObservedWindowsFacts.Caption -match "Windows 10"
    $IsWindows11 = $ObservedWindowsFacts.Caption -match "Windows 11"

    if ($IsWindows10 -or $IsWindows11) {
        Add-CheckResult `
            -CheckId "verify.operating_system" `
            -Status "PASS" `
            -Detail $ObservedWindowsFacts.Caption
    }
    else {
        $script:UnsupportedFailure = $true
        Add-CheckResult `
            -CheckId "verify.operating_system" `
            -Status "FAIL" `
            -Detail $ObservedWindowsFacts.Caption `
            -Remediation (
                "Use Windows 10, version 22H2, or a supported Windows 11 " +
                "computer."
            )
    }

    $SupportedWindows11Releases = @(
        $Platform.os.releases | ForEach-Object { [string]$_.release_id }
    )
    $ReleaseIsSupported = (
        ($IsWindows10 -and $ObservedWindowsFacts.DisplayVersion -eq "22H2") -or
        (
            $IsWindows11 -and
            $ObservedWindowsFacts.DisplayVersion -in $SupportedWindows11Releases
        )
    )

    if ($ReleaseIsSupported) {
        Add-CheckResult `
            -CheckId "verify.os_release" `
            -Status "PASS" `
            -Detail $ObservedWindowsFacts.DisplayVersion
    }
    else {
        $script:UnsupportedFailure = $true
        Add-CheckResult `
            -CheckId "verify.os_release" `
            -Status "FAIL" `
            -Detail "Unsupported Windows release: $($ObservedWindowsFacts.DisplayVersion)" `
            -Remediation (
                "Use Windows 10, version 22H2, or a manifest-supported " +
                "Windows 11 release."
            )
    }

    if ($ObservedWindowsFacts.Architecture -match "64-bit") {
        Add-CheckResult `
            -CheckId "verify.architecture" `
            -Status "PASS" `
            -Detail $ObservedWindowsFacts.Architecture
    }
    else {
        $script:UnsupportedFailure = $true
        Add-CheckResult `
            -CheckId "verify.architecture" `
            -Status "FAIL" `
            -Detail $ObservedWindowsFacts.Architecture `
            -Remediation "Use a supported x64 Windows computer or contact technical support."
    }
}

function Test-DiskAndNetwork {
    param([Parameter(Mandatory = $true)]$Manifest)

    $FreeBytes = (Get-PSDrive -Name $env:SystemDrive.TrimEnd(":")).Free
    $MinimumBytes = [int64]$Manifest.policy.minimum_free_space_bytes
    if ($FreeBytes -ge $MinimumBytes) {
        Add-CheckResult `
            -CheckId "verify.disk_space" `
            -Status "PASS" `
            -Detail ("{0:N1} GB free" -f ($FreeBytes / 1GB))
    }
    else {
        Add-CheckResult `
            -CheckId "verify.disk_space" `
            -Status "FAIL" `
            -Detail ("{0:N1} GB free" -f ($FreeBytes / 1GB)) `
            -Remediation (
                "Remove unneeded user-owned files until at least 5 GB is " +
                "free, then rerun verify_ide.ps1."
            )
    }

    if ($SkipNetwork) {
        Add-CheckResult `
            -CheckId "verify.network" `
            -Status "NOT APPLICABLE" `
            -Detail "Network check skipped by request"
        return
    }

    try {
        $TimeoutSeconds = [int]$Manifest.policy.network_timeout_seconds
        $Response = Invoke-WebRequest `
            -Uri "https://github.com/GC-STEM/it140" `
            -Method Head `
            -TimeoutSec $TimeoutSeconds `
            -UseBasicParsing
        Add-CheckResult `
            -CheckId "verify.network" `
            -Status "PASS" `
            -Detail ("Course repository responded with HTTP {0}" -f $Response.StatusCode)
    }
    catch {
        Add-CheckResult `
            -CheckId "verify.network" `
            -Status "WARNING" `
            -Detail "The course repository did not respond within the verification check." `
            -Remediation (
                "Confirm internet access and retry later if update or " +
                "authentication also fails."
            )
    }
}

function Test-SystemLayer {
    param([Parameter(Mandatory = $true)]$Platform)

    if (Test-CommandAvailable "winget.exe") {
        Add-CheckResult `
            -CheckId "verify.package_manager" `
            -Status "PASS" `
            -Detail "Windows Package Manager is available"
    }
    else {
        Add-CheckResult `
            -CheckId "verify.package_manager" `
            -Status "FAIL" `
            -Detail "Windows Package Manager is missing" `
            -Remediation (Get-SystemSetupRemediation)
    }

    $SystemBindings = Get-SystemPackageBinding -Platform $Platform
    foreach ($Binding in $SystemBindings) {
        if (
            (Test-CommandAvailable "winget.exe") -and
            (Test-WinGetPackageInstalled -PackageIdentifier $Binding.PackageIdentifier)
        ) {
            Add-CheckResult `
                -CheckId ("verify.package.{0}" -f $Binding.Role) `
                -Status "PASS" `
                -Detail $Binding.PackageIdentifier
        }
        else {
            Add-CheckResult `
                -CheckId ("verify.package.{0}" -f $Binding.Role) `
                -Status "FAIL" `
                -Detail "Missing or not reported: $($Binding.PackageIdentifier)" `
                -Remediation (Get-SystemRepairRemediation -CapabilityType "package")
        }

        foreach ($ExecutableName in @($Binding.ExecutableNames)) {
            if (Test-CommandAvailable $ExecutableName) {
                $VersionOutput = @(& $ExecutableName --version 2>&1)
                $VersionDetail = if ($VersionOutput.Count -gt 0) {
                    [string]$VersionOutput[0]
                }
                else {
                    "Available"
                }
                Add-CheckResult `
                    -CheckId ("verify.capability.{0}" -f $Binding.Role) `
                    -Status "PASS" `
                    -Detail $VersionDetail
            }
            else {
                Add-CheckResult `
                    -CheckId ("verify.capability.{0}" -f $Binding.Role) `
                    -Status "FAIL" `
                    -Detail "Required command is missing: $ExecutableName" `
                    -Remediation (Get-SystemRepairRemediation -CapabilityType "command")
            }
        }
    }

    if (Test-CommandAvailable "python.exe") {
        $PythonVersion = & python.exe -c (
            "import sys; print('.'.join(map(str, sys.version_info[:2])))"
        )
        if ($LASTEXITCODE -eq 0 -and [string]$PythonVersion -eq "3.12") {
            Add-CheckResult `
                -CheckId "verify.python_version" `
                -Status "PASS" `
                -Detail "Python 3.12"
        }
        else {
            Add-CheckResult `
                -CheckId "verify.python_version" `
                -Status "FAIL" `
                -Detail "Python 3.12 is not the active Windows runtime." `
                -Remediation (Get-SystemSetupRemediation)
        }
    }
}

function Test-UserLayer {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)]$Platform
    )

    $FoldersPresent = $true
    foreach ($RequiredDirectory in @($CourseRoot, $LogDirectory, $WindowsScriptDirectory)) {
        if (-not (Test-Path -LiteralPath $RequiredDirectory -PathType Container)) {
            $FoldersPresent = $false
        }
    }
    if ($FoldersPresent) {
        Add-CheckResult `
            -CheckId "verify.course_folders" `
            -Status "PASS" `
            -Detail "Course root, log, and Windows script directories are present"
    }
    else {
        Add-CheckResult `
            -CheckId "verify.course_folders" `
            -Status "FAIL" `
            -Detail "One or more required course directories are missing." `
            -Remediation (Get-BootstrapRemediation)
    }

    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $UserPathReady = $true
    foreach ($ManagedPath in @($VenvScriptsDirectory, $WindowsScriptDirectory)) {
        if (-not (Test-PathContainsEntry -PathValue $UserPath -ExpectedEntry $ManagedPath)) {
            $UserPathReady = $false
        }
    }
    if ($UserPathReady) {
        Add-CheckResult `
            -CheckId "verify.user_path" `
            -Status "PASS" `
            -Detail "Course Python and Windows script directories are in the user PATH"
    }
    else {
        Add-CheckResult `
            -CheckId "verify.user_path" `
            -Status "FAIL" `
            -Detail "The persistent user PATH is incomplete." `
            -Remediation (Get-ConfigRemediation)
    }

    $CurrentPathReady = $true
    foreach ($ManagedPath in @($VenvScriptsDirectory, $WindowsScriptDirectory)) {
        if (-not (Test-PathContainsEntry -PathValue $env:Path -ExpectedEntry $ManagedPath)) {
            $CurrentPathReady = $false
        }
    }
    if ($CurrentPathReady) {
        Add-CheckResult `
            -CheckId "verify.current_path" `
            -Status "PASS" `
            -Detail "The current PowerShell PATH contains both course directories"
    }
    else {
        Add-CheckResult `
            -CheckId "verify.current_path" `
            -Status "FAIL" `
            -Detail "The current PowerShell window has an outdated PATH." `
            -Remediation "Close this PowerShell window, open a new one, and rerun verify_ide.ps1."
    }

    if (Test-Path -LiteralPath $VenvPython -PathType Leaf) {
        $VenvVersion = & $VenvPython -c (
            "import sys; print('.'.join(map(str, sys.version_info[:2])))"
        )
        if ($LASTEXITCODE -eq 0 -and [string]$VenvVersion -eq "3.12") {
            Add-CheckResult `
                -CheckId "verify.virtual_environment" `
                -Status "PASS" `
                -Detail $VenvDirectory
        }
        else {
            Add-CheckResult `
                -CheckId "verify.virtual_environment" `
                -Status "FAIL" `
                -Detail "The course virtual environment does not use Python 3.12." `
                -Remediation (Get-ConfigRemediation)
        }
    }
    else {
        Add-CheckResult `
            -CheckId "verify.virtual_environment" `
            -Status "FAIL" `
            -Detail "The course virtual environment is missing." `
            -Remediation (Get-ConfigRemediation)
    }

    if (Test-Path -LiteralPath $VenvPython -PathType Leaf) {
        foreach ($PackageName in (Get-RequiredPythonPackage -Platform $Platform)) {
            $PackageIsInstalled = Test-NativeCommandExitSuccess `
                -FilePath $VenvPython `
                -ArgumentList @("-m", "pip", "show", $PackageName)
            if ($PackageIsInstalled) {
                Add-CheckResult `
                    -CheckId ("verify.user_tool.{0}" -f $PackageName) `
                    -Status "PASS" `
                    -Detail "Installed"
            }
            else {
                Add-CheckResult `
                    -CheckId ("verify.user_tool.{0}" -f $PackageName) `
                    -Status "FAIL" `
                    -Detail "Missing" `
                    -Remediation (Get-ConfigRemediation)
            }
        }
    }

    if (Test-CommandAvailable "code.cmd") {
        $InstalledExtensions = @(
            & code.cmd --list-extensions 2>$null |
                ForEach-Object { ([string]$_).Trim().ToLowerInvariant() }
        )
        foreach ($ExtensionId in (Get-RequiredExtension -Platform $Platform)) {
            if ($ExtensionId.ToLowerInvariant() -in $InstalledExtensions) {
                Add-CheckResult `
                    -CheckId ("verify.extension.{0}" -f $ExtensionId) `
                    -Status "PASS" `
                    -Detail "Installed"
            }
            else {
                Add-CheckResult `
                    -CheckId ("verify.extension.{0}" -f $ExtensionId) `
                    -Status "FAIL" `
                    -Detail "Missing" `
                    -Remediation (Get-ConfigRemediation)
            }
        }
    }

    if (Test-CommandAvailable "gh.exe") {
        $GitHubIsAuthenticated = Test-NativeCommandExitSuccess `
            -FilePath "gh.exe" `
            -ArgumentList @("auth", "status", "--hostname", "github.com")
        if ($GitHubIsAuthenticated) {
            Add-CheckResult `
                -CheckId "verify.github_authentication" `
                -Status "PASS" `
                -Detail "Authenticated to github.com"
        }
        else {
            Add-CheckResult `
                -CheckId "verify.github_authentication" `
                -Status "FAIL" `
                -Detail "GitHub CLI is not authenticated." `
                -Remediation (Get-ConfigRemediation)
        }
    }

    if (Test-CommandAvailable "git.exe") {
        $GitDisplayName = Get-GitConfigValue -Key "user.name"
        if ([string]::IsNullOrWhiteSpace($GitDisplayName)) {
            Add-CheckResult `
                -CheckId "verify.git_display_name" `
                -Status "FAIL" `
                -Detail "The Git display name is missing." `
                -Remediation (Get-ConfigRemediation)
        }
        else {
            Add-CheckResult `
                -CheckId "verify.git_display_name" `
                -Status "PASS" `
                -Detail "Configured"
        }

        $GitEmail = Get-GitConfigValue -Key "user.email"
        if ($GitEmail -match "^[0-9]+\+[^@\s]+@users\.noreply\.github\.com$") {
            Add-CheckResult `
                -CheckId "verify.git_private_identity" `
                -Status "PASS" `
                -Detail "Private GitHub noreply identity configured"
        }
        else {
            Add-CheckResult `
                -CheckId "verify.git_private_identity" `
                -Status "FAIL" `
                -Detail "The privacy-preserving GitHub noreply identity is not configured." `
                -Remediation (Get-ConfigRemediation)
        }

        $GitSettings = Get-PropertyValue `
            -Object $Manifest.managed_settings `
            -Name "git_course_defaults"
        foreach ($PropertyRecord in $GitSettings.values.PSObject.Properties) {
            $ExpectedValue = $PropertyRecord.Value
            if ($ExpectedValue -is [bool]) {
                $ExpectedValue = $ExpectedValue.ToString().ToLowerInvariant()
            }
            $ObservedValue = Get-GitConfigValue -Key $PropertyRecord.Name
            if ($ObservedValue -ceq [string]$ExpectedValue) {
                Add-CheckResult `
                    -CheckId ("verify.git_setting.{0}" -f $PropertyRecord.Name) `
                    -Status "PASS" `
                    -Detail ([string]$ExpectedValue)
            }
            else {
                Add-CheckResult `
                    -CheckId ("verify.git_setting.{0}" -f $PropertyRecord.Name) `
                    -Status "FAIL" `
                    -Detail "Expected '$ExpectedValue'; observed '$ObservedValue'" `
                    -Remediation (Get-ConfigRemediation)
            }
        }
    }

    if (Test-Path -LiteralPath $VsCodeSettings -PathType Leaf) {
        try {
            $ObservedSettings = Get-Content -LiteralPath $VsCodeSettings -Raw |
                ConvertFrom-Json
            $ExpectedSettings = Get-ManagedVsCodeSetting -Manifest $Manifest
            if (Test-ManagedSettingValue -Observed $ObservedSettings -Expected $ExpectedSettings) {
                Add-CheckResult `
                    -CheckId "verify.vscode_settings" `
                    -Status "PASS" `
                    -Detail "All course-managed settings are present"
            }
            else {
                Add-CheckResult `
                    -CheckId "verify.vscode_settings" `
                    -Status "FAIL" `
                    -Detail "One or more course-managed settings are missing or different." `
                    -Remediation (Get-ConfigRemediation)
            }
        }
        catch {
            Add-CheckResult `
                -CheckId "verify.vscode_settings" `
                -Status "FAIL" `
                -Detail "The VS Code settings file is not a valid JSON object." `
                -Remediation (
                    "Preserve the file and contact course or technical " +
                    "support before rerunning configure_ide.ps1."
                )
        }
    }
    else {
        Add-CheckResult `
            -CheckId "verify.vscode_settings" `
            -Status "FAIL" `
            -Detail "The VS Code settings file is missing." `
            -Remediation (Get-ConfigRemediation)
    }

    if (Test-Path -LiteralPath $ReposRoot -PathType Container) {
        Add-CheckResult `
            -CheckId "verify.repository_workspace" `
            -Status "PASS" `
            -Detail $ReposRoot
    }
    else {
        Add-CheckResult `
            -CheckId "verify.repository_workspace" `
            -Status "FAIL" `
            -Detail "The repository workspace is missing or is not a directory." `
            -Remediation (Get-ConfigRemediation)
    }

    if (Test-Path -LiteralPath $ReposShortcutPath -PathType Leaf) {
        try {
            $ReposShortcut = Get-ShortcutDefinition -Path $ReposShortcutPath
            if (
                $ReposShortcut.TargetPath -ieq "$env:SystemRoot\explorer.exe" -and
                $ReposShortcut.Arguments -like "*$ReposRoot*"
            ) {
                Add-CheckResult `
                    -CheckId "verify.repository_workspace_desktop" `
                    -Status "PASS" `
                    -Detail "Desktop Repos shortcut targets the repository workspace"
            }
            else {
                throw "The desktop Repos shortcut does not target the repository workspace."
            }
        }
        catch {
            Add-CheckResult `
                -CheckId "verify.repository_workspace_desktop" `
                -Status "FAIL" `
                -Detail $_.Exception.Message `
                -Remediation (Get-ConfigRemediation)
        }
    }
    else {
        Add-CheckResult `
            -CheckId "verify.repository_workspace_desktop" `
            -Status "FAIL" `
            -Detail "The desktop Repos shortcut is missing." `
            -Remediation (Get-ConfigRemediation)
    }

    if (Test-Path -LiteralPath $ReposDesktopIniPath -PathType Leaf) {
        try {
            $DesktopIniText = Get-Content -LiteralPath $ReposDesktopIniPath -Raw
            if ($DesktopIniText -match '(?m)^IconResource=.+,0\s*$') {
                Add-CheckResult `
                    -CheckId "verify.repository_workspace_marker" `
                    -Status "PASS" `
                    -Detail "Explorer development icon metadata is present"
            }
            else {
                throw "The Repos folder icon metadata does not contain a valid IconResource."
            }
        }
        catch {
            Add-CheckResult `
                -CheckId "verify.repository_workspace_marker" `
                -Status "FAIL" `
                -Detail $_.Exception.Message `
                -Remediation (Get-ConfigRemediation)
        }
    }
    else {
        Add-CheckResult `
            -CheckId "verify.repository_workspace_marker" `
            -Status "FAIL" `
            -Detail "The Repos folder development icon metadata is missing." `
            -Remediation (Get-ConfigRemediation)
    }

    if ($DeploymentProfile -eq "windows_sandbox") {
        $LifecycleScripts = @(
            [pscustomobject]@{
                Name = "bootstrap_wsb.ps1"
                Path = Join-Path $WindowsScriptDirectory "wsb\bootstrap_wsb.ps1"
            },
            [pscustomobject]@{
                Name = "setup_wsb.ps1"
                Path = Join-Path $WindowsScriptDirectory "wsb\setup_wsb.ps1"
            },
            [pscustomobject]@{
                Name = "configure_ide.ps1"
                Path = Join-Path $WindowsScriptDirectory "configure_ide.ps1"
            },
            [pscustomobject]@{
                Name = "verify_ide.ps1"
                Path = Join-Path $WindowsScriptDirectory "verify_ide.ps1"
            }
        )
        $LifecycleRemediation = (
            "Start a fresh Windows Sandbox session with it140_wsb.wsb. " +
            "Windows Sandbox does not use update_ide.ps1."
        )
    }
    else {
        $LifecycleScripts = @(
            [pscustomobject]@{
                Name = "install_ide.ps1"
                Path = Join-Path $WindowsScriptDirectory "install_ide.ps1"
            },
            [pscustomobject]@{
                Name = "configure_ide.ps1"
                Path = Join-Path $WindowsScriptDirectory "configure_ide.ps1"
            },
            [pscustomobject]@{
                Name = "update_ide.ps1"
                Path = Join-Path $WindowsScriptDirectory "update_ide.ps1"
            },
            [pscustomobject]@{
                Name = "verify_ide.ps1"
                Path = Join-Path $WindowsScriptDirectory "verify_ide.ps1"
            }
        )
        $LifecycleRemediation = "Run update_ide.ps1 from a normal PowerShell window."
    }

    foreach ($LifecycleRecord in $LifecycleScripts) {
        if (-not (Test-Path -LiteralPath $LifecycleRecord.Path -PathType Leaf)) {
            Add-CheckResult `
                -CheckId ("verify.script.{0}" -f $LifecycleRecord.Name) `
                -Status "FAIL" `
                -Detail "Missing" `
                -Remediation $LifecycleRemediation
            continue
        }

        try {
            Test-PowerShellScript -Path $LifecycleRecord.Path
            $AllowLegacyVersion = (
                $DeploymentProfile -eq "windows_sandbox" -and
                $LifecycleRecord.Name -in @("bootstrap_wsb.ps1", "setup_wsb.ps1")
            )
            $LifecycleVersion = Get-ScriptVersion `
                -Path $LifecycleRecord.Path `
                -AllowLegacyCalendarVersion:$AllowLegacyVersion
            Add-CheckResult `
                -CheckId ("verify.script.{0}" -f $LifecycleRecord.Name) `
                -Status "PASS" `
                -Detail ("Valid; version {0}" -f $LifecycleVersion)
        }
        catch {
            Add-CheckResult `
                -CheckId ("verify.script.{0}" -f $LifecycleRecord.Name) `
                -Status "FAIL" `
                -Detail $_.Exception.Message `
                -Remediation $LifecycleRemediation
        }
    }
}

function Test-ManagedAsset {
    foreach ($AssetRecord in @(
        [pscustomobject]@{
            CheckId = "verify.asset.course_manifest"
            Path = $ManifestPath
        },
        [pscustomobject]@{
            CheckId = "verify.asset.manifest_schema"
            Path = $SchemaPath
        }
    )) {
        if (Test-Path -LiteralPath $AssetRecord.Path -PathType Leaf) {
            Add-CheckResult `
                -CheckId $AssetRecord.CheckId `
                -Status "PASS" `
                -Detail "Readable"
        }
        else {
            Add-CheckResult `
                -CheckId $AssetRecord.CheckId `
                -Status "FAIL" `
                -Detail "Missing" `
                -Remediation (Get-ManagedAssetRemediation)
        }
    }
}

function Get-ResolvedExitCode {
    if ($ManifestFailure) {
        return 5
    }
    if ($UnsupportedFailure) {
        return 2
    }
    if (@($Results | Where-Object { $_.Status -eq "FAIL" }).Count -gt 0) {
        return 1
    }
    return 0
}

function Write-VerificationSummary {
    param([Parameter(Mandatory = $true)][int]$ResolvedExitCode)

    $PassCount = @($Results | Where-Object { $_.Status -eq "PASS" }).Count
    $WarningCount = @($Results | Where-Object { $_.Status -eq "WARNING" }).Count
    $FailCount = @($Results | Where-Object { $_.Status -eq "FAIL" }).Count
    $NotApplicableCount = @(
        $Results | Where-Object { $_.Status -eq "NOT APPLICABLE" }
    ).Count
    $Elapsed = (Get-Date) - $StartTime

    Write-Header "VERIFICATION SUMMARY"
    Write-Info "Script version   : $ScriptVersion"
    Write-Info "Version DTG      : $VersionDate"
    Write-Info "Status           : $DevelopmentStatus"
    if ($null -ne $Controlled) {
        Write-Info "Manifest release : $($Controlled.Manifest.automation_release)"
        Write-Info "Manifest DTG     : $($Controlled.Manifest.automation_release_date_time_group)"
    }
    Write-Info "Passed           : $PassCount"
    Write-Info "Warnings         : $WarningCount"
    Write-Info "Failed           : $FailCount"
    Write-Info "Not applicable   : $NotApplicableCount"
    Write-Info ("Elapsed time     : {0:hh\:mm\:ss}" -f $Elapsed)
    Write-Info "Log file         : $LogPath"

    if ($Remediations.Count -gt 0) {
        Write-Host ""
        Write-Host "Remediation and follow-up:"
        foreach ($Remediation in $Remediations) {
            Write-Host "- $Remediation"
        }
    }

    if ($ResolvedExitCode -eq 0) {
        Write-Host "[SUCCESS] The Windows course environment passed all required checks."
    }
    else {
        Write-ErrorMessage "One or more required checks failed."
        Write-Notice "Complete the listed remediation, then rerun verify_ide.ps1."
    }
    Write-Info "Exit code        : $ResolvedExitCode"
    Write-ClosingNotice
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

function Get-SanitizedText {
    param([Parameter(Mandatory = $true)][string]$Text)

    $SanitizedText = $Text
    $UserProfile = [Environment]::GetFolderPath("UserProfile")
    if (-not [string]::IsNullOrWhiteSpace($UserProfile)) {
        $SanitizedText = $SanitizedText -replace (
            [regex]::Escape($UserProfile)
        ), "<USER_HOME>"
    }
    $SanitizedText = $SanitizedText -replace (
        "[0-9]+\+[^@\s]+@users\.noreply\.github\.com"
    ), "<GITHUB_NOREPLY_EMAIL>"
    $SanitizedText = $SanitizedText -replace (
        "(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"
    ), "<EMAIL>"
    return $SanitizedText
}

function New-SupportBundle {
    if (-not $SupportBundle) {
        return $null
    }

    Write-Host ""
    Write-Header "OPTIONAL SANITIZED SUPPORT BUNDLE"
    Write-Notice "The bundle will contain:"
    Write-Host "- A sanitized copy of this verification log"
    Write-Host "- A sanitized verification-result report"
    Write-Host "- Manifest and script release information"
    Write-Host "- Supported Windows platform facts"
    Write-Host "- Required capability version information"
    Write-Notice (
        "The bundle will not contain course work, repositories, Git " +
        "history, credentials, or browser data."
    )

    if ($NonInteractive -and -not $Yes) {
        Write-Notice (
            "Support-bundle creation was skipped because noninteractive " +
            "mode requires -Yes."
        )
        return $null
    }
    if (-not $Yes) {
        $Answer = Read-Host "Type YES to create the support bundle"
        if ($Answer -cne "YES") {
            Write-Notice "Support-bundle creation was canceled."
            return $null
        }
    }

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $StagingDirectory = Join-Path $env:TEMP "it140-support-$Timestamp"
    $BundlePath = Join-Path $LogDirectory "it140_support_win_$Timestamp.zip"
    New-Item -ItemType Directory -Path $StagingDirectory -Force | Out-Null

    try {
        if (Test-Path -LiteralPath $LogPath -PathType Leaf) {
            $LogText = Get-Content -LiteralPath $LogPath -Raw
            Write-Utf8LfFile `
                -Path (Join-Path $StagingDirectory "verify_win_sanitized.log") `
                -Content (Get-SanitizedText -Text $LogText)
        }

        $SanitizedResults = @(
            $Results | ForEach-Object {
                [pscustomobject]@{
                    CheckId = $_.CheckId
                    Status = $_.Status
                    Detail = Get-SanitizedText -Text ([string]$_.Detail)
                    Remediation = Get-SanitizedText -Text ([string]$_.Remediation)
                }
            }
        )
        $ResultsJson = $SanitizedResults | ConvertTo-Json -Depth 10
        Write-Utf8LfFile `
            -Path (Join-Path $StagingDirectory "verification_results.json") `
            -Content ("$ResultsJson`n")

        $ManifestReleaseValue = "unavailable"
        $ManifestReleaseDateValue = "unavailable"
        if ($null -ne $Controlled) {
            $ManifestReleaseValue = [string]$Controlled.Manifest.automation_release
            $ManifestReleaseDateValue = [string](
                $Controlled.Manifest.automation_release_date
            )
        }
        $LifecycleVersionSummary = @{}
        if ($DeploymentProfile -eq "windows_sandbox") {
            $LifecycleRecords = @(
                [pscustomobject]@{
                    Name = "bootstrap_wsb.ps1"
                    Path = Join-Path $WindowsScriptDirectory "wsb\bootstrap_wsb.ps1"
                },
                [pscustomobject]@{
                    Name = "setup_wsb.ps1"
                    Path = Join-Path $WindowsScriptDirectory "wsb\setup_wsb.ps1"
                },
                [pscustomobject]@{
                    Name = "configure_ide.ps1"
                    Path = Join-Path $WindowsScriptDirectory "configure_ide.ps1"
                },
                [pscustomobject]@{
                    Name = "verify_ide.ps1"
                    Path = Join-Path $WindowsScriptDirectory "verify_ide.ps1"
                }
            )
        }
        else {
            $LifecycleRecords = @(
                [pscustomobject]@{
                    Name = "install_ide.ps1"
                    Path = Join-Path $WindowsScriptDirectory "install_ide.ps1"
                },
                [pscustomobject]@{
                    Name = "configure_ide.ps1"
                    Path = Join-Path $WindowsScriptDirectory "configure_ide.ps1"
                },
                [pscustomobject]@{
                    Name = "update_ide.ps1"
                    Path = Join-Path $WindowsScriptDirectory "update_ide.ps1"
                },
                [pscustomobject]@{
                    Name = "verify_ide.ps1"
                    Path = Join-Path $WindowsScriptDirectory "verify_ide.ps1"
                }
            )
        }

        foreach ($LifecycleRecord in $LifecycleRecords) {
            try {
                $AllowLegacyVersion = (
                    $DeploymentProfile -eq "windows_sandbox" -and
                    $LifecycleRecord.Name -in @(
                        "bootstrap_wsb.ps1",
                        "setup_wsb.ps1"
                    )
                )
                $LifecycleVersionSummary[$LifecycleRecord.Name] = [string](
                    Get-ScriptVersion `
                        -Path $LifecycleRecord.Path `
                        -AllowLegacyCalendarVersion:$AllowLegacyVersion
                )
            }
            catch {
                $LifecycleVersionSummary[$LifecycleRecord.Name] = "unavailable"
            }
        }

        if ($DeploymentProfile -eq "windows_sandbox") {
            $ReleaseSummary = [pscustomobject]@{
                ManifestRelease = $ManifestReleaseValue
                ManifestReleaseDate = $ManifestReleaseDateValue
                VerificationArtifactVersion = $ScriptVersion
                VerificationArtifactVersionDate = $VersionDate
                VerificationArtifactDevelopmentStatus = $DevelopmentStatus
                BootstrapScriptVersion = $LifecycleVersionSummary["bootstrap_wsb.ps1"]
                SetupScriptVersion = $LifecycleVersionSummary["setup_wsb.ps1"]
                ConfigScriptVersion = $LifecycleVersionSummary["configure_ide.ps1"]
                UpdateScriptVersion = "not applicable"
                VerifyScriptVersion = $LifecycleVersionSummary["verify_ide.ps1"]
            } | ConvertTo-Json -Depth 5
        }
        else {
            $ReleaseSummary = [pscustomobject]@{
                ManifestRelease = $ManifestReleaseValue
                ManifestReleaseDate = $ManifestReleaseDateValue
                VerificationArtifactVersion = $ScriptVersion
                VerificationArtifactVersionDate = $VersionDate
                VerificationArtifactDevelopmentStatus = $DevelopmentStatus
                SetupScriptVersion = $LifecycleVersionSummary["install_ide.ps1"]
                ConfigScriptVersion = $LifecycleVersionSummary["configure_ide.ps1"]
                UpdateScriptVersion = $LifecycleVersionSummary["update_ide.ps1"]
                VerifyScriptVersion = $LifecycleVersionSummary["verify_ide.ps1"]
            } | ConvertTo-Json -Depth 5
        }
        Write-Utf8LfFile `
            -Path (Join-Path $StagingDirectory "release_summary.json") `
            -Content ("$ReleaseSummary`n")

        $CaptionValue = "unavailable"
        $DisplayVersionValue = "unavailable"
        $BuildNumberValue = "unavailable"
        $ArchitectureValue = "unavailable"
        if ($null -ne $WindowsFacts) {
            $CaptionValue = $WindowsFacts.Caption
            $DisplayVersionValue = $WindowsFacts.DisplayVersion
            $BuildNumberValue = $WindowsFacts.BuildNumber
            $ArchitectureValue = $WindowsFacts.Architecture
        }
        $PlatformSummary = [pscustomobject]@{
            Platform = "windows"
            DeploymentProfile = $DeploymentProfile
            Caption = $CaptionValue
            DisplayVersion = $DisplayVersionValue
            BuildNumber = $BuildNumberValue
            Architecture = $ArchitectureValue
        } | ConvertTo-Json -Depth 5
        Write-Utf8LfFile `
            -Path (Join-Path $StagingDirectory "platform_facts.json") `
            -Content ("$PlatformSummary`n")

        $VersionLines = @()
        foreach ($CommandName in @(
            "winget.exe",
            "git.exe",
            "gh.exe",
            "python.exe",
            "code.cmd"
        )) {
            if (Test-CommandAvailable $CommandName) {
                $VersionOutput = @(& $CommandName --version 2>&1)
                $FirstLine = if ($VersionOutput.Count -gt 0) {
                    [string]$VersionOutput[0]
                }
                else {
                    "available"
                }
                $VersionLines += "$CommandName : $FirstLine"
            }
            else {
                $VersionLines += "$CommandName : unavailable"
            }
        }
        Write-Utf8LfFile `
            -Path (Join-Path $StagingDirectory "versions.txt") `
            -Content (($VersionLines -join "`n") + "`n")

        $Inventory = @(
            "it140 sanitized support bundle"
            "Included: sanitized verification log"
            "Included: sanitized verification results"
            "Included: release summary"
            "Included: platform facts"
            "Included: capability versions"
            "Excluded: student source files"
            "Excluded: repository contents and version-control history"
            "Excluded: authentication data and browser data"
        ) -join "`n"
        Write-Utf8LfFile `
            -Path (Join-Path $StagingDirectory "inventory.txt") `
            -Content ("$Inventory`n")

        $ProhibitedPatterns = @(
            "github_pat_[A-Za-z0-9_]{20,}",
            "gh[pousr]_[A-Za-z0-9_]{20,}",
            "-----BEGIN [A-Z ]*PRIVATE KEY-----",
            "(?i)authorization:\s*bearer\s+[A-Za-z0-9._-]{20,}",
            "(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"
        )
        foreach ($StagedFile in (Get-ChildItem -LiteralPath $StagingDirectory -File)) {
            $StagedText = Get-Content -LiteralPath $StagedFile.FullName -Raw
            foreach ($Pattern in $ProhibitedPatterns) {
                if ($StagedText -match $Pattern) {
                    throw "The support bundle failed its prohibited-content scan."
                }
            }
        }

        Compress-Archive `
            -Path (Join-Path $StagingDirectory "*") `
            -DestinationPath $BundlePath `
            -Force
    }
    finally {
        Remove-Item -LiteralPath $StagingDirectory -Recurse -Force `
            -ErrorAction SilentlyContinue
    }

    return $BundlePath
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

    Write-Header "IT 140 WINDOWS VERIFICATION"
    Write-Info "Script version   : $ScriptVersion"
    Write-Info "Version DTG      : $VersionDate"
    Write-Info "Status           : $DevelopmentStatus"
    Write-Info "Deployment       : $DeploymentProfile"
    Write-Info "Current user     : $([Environment]::UserName)"
    Write-Info "Course root      : $CourseRoot"
    Write-Info "Repository root  : $ReposRoot"
    Write-Info "Log file         : $LogPath"
    Write-Notice "Verification does not elevate privilege or repair failed checks."

    try {
        $Controlled = Read-ControlledManifest
        Add-CheckResult `
            -CheckId "verify.manifest" `
            -Status "PASS" `
            -Detail ("Release {0}" -f $Controlled.Manifest.automation_release)
    }
    catch {
        $ManifestFailure = $true
        Add-CheckResult `
            -CheckId "verify.manifest" `
            -Status "FAIL" `
            -Detail $_.Exception.Message `
            -Remediation $(
                if ($DeploymentProfile -eq "windows_sandbox") {
                    "Start a fresh Windows Sandbox session with it140_wsb.wsb; " +
                    "if the problem remains, contact course support."
                }
                else {
                    "Run prepare_ide.ps1 again; if the problem remains, " +
                    "contact course support."
                }
            )
    }

    if (-not $ManifestFailure) {
        try {
            $WindowsFacts = Get-OperatingSystemFact
            Test-PlatformContext `
                -Platform $Controlled.Platform `
                -ObservedWindowsFacts $WindowsFacts
            Test-DiskAndNetwork -Manifest $Controlled.Manifest
            Test-SystemLayer -Platform $Controlled.Platform
            Test-UserLayer `
                -Manifest $Controlled.Manifest `
                -Platform $Controlled.Platform
            Test-ManagedAsset

            if (Test-PendingRestart) {
                Add-CheckResult `
                    -CheckId "verify.restart" `
                    -Status "WARNING" `
                    -Detail "Windows reports that a restart is pending." `
                    -Remediation "Save your work and restart Windows before continuing coursework."
            }
            else {
                Add-CheckResult `
                    -CheckId "verify.restart" `
                    -Status "PASS" `
                    -Detail "No pending Windows restart was detected"
            }
        }
        catch {
            Add-CheckResult `
                -CheckId "verify.unhandled_check" `
                -Status "FAIL" `
                -Detail $_.Exception.Message `
                -Remediation "Review the verification log and contact course or technical support."
        }
    }

    $ExitCode = Get-ResolvedExitCode
    Write-VerificationSummary -ResolvedExitCode $ExitCode
}
catch {
    Write-ErrorMessage $_.Exception.Message
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
            # Best-effort operation; preserve the primary result.
        }
    }
}

if ($SupportBundle) {
    try {
        $BundlePath = New-SupportBundle
        if ($BundlePath) {
            Write-Host "[SUCCESS] Sanitized support bundle created: $BundlePath"
        }
    }
    catch {
        Write-ErrorMessage ("Support bundle creation failed: {0}" -f $_.Exception.Message)
        if ($ExitCode -eq 0) {
            $ExitCode = 1
        }
    }
}

exit $ExitCode
