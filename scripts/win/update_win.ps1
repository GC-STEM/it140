#requires -Version 5.1
<#
.SYNOPSIS
Updates the Windows IT 140 Course IDE within the current Windows release.

.DESCRIPTION
Synchronizes validated student-facing Windows lifecycle assets, updates or
repairs manifest-required WinGet packages through a separate UAC-elevated
phase, upgrades the course Python environment and VS Code extensions, and
refreshes managed user settings and shortcuts.

Windows updates are completed manually outside the course automation lifecycle;
this script does not run Windows Update. It never removes student source files,
assignment repositories, Git history, optional VS Code extensions, or unrelated
user settings.

Run this script from a normal, non-elevated Windows PowerShell terminal.

Artifact version:
    0.3.0

Version date:
    2026-07-29

Development status:
    Alpha Testing

Version basis:
    Version 0.1.0 represents the initial Windows update baseline.
    Version 0.2.0 adopts SemVer and manifest schema 2.0, and limits periodic
    maintenance to course IDE components.
    Version 0.2.1 removes an unsupported WinGet source-update option.
    Version 0.2.2 prevents expected native-command probe failures from
    terminating Windows PowerShell 5.1.

    Version 0.3.0 adds support for Windows 10, version 22H2, while preserving
    manifest-controlled Windows 11 release validation.


.NOTES
Exit codes:
  0 Success
  1 Required operation failed before managed state changed
  2 Unsupported Windows platform, release, or option
  3 Required elevation was unavailable or used incorrectly
  4 Required network or package-retrieval operation failed
  5 Controlled manifest or managed asset validation failed
  6 User canceled before managed state changed
  7 Update completed partially or managed state changed before failure

Logs are written under ~/it140/logs/. The elevated course-component phase
writes a separate update_win_system log in the same directory.

.USAGE
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
update_win.ps1

#>

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Version,
    [switch]$NonInteractive,
    [ValidateSet("windows_bare_metal")]
    [string]$DeploymentProfile = "windows_bare_metal",
    [switch]$SystemPhase,
    [string]$TransactionRoot,
    [string]$CourseRootOverride
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ScriptVersion = "0.3.0"
$VersionDate = "2026-07-29"
$DevelopmentStatus = "Alpha Testing"
$PlatformId = "windows"
$PlatformAbbreviation = "win"
if (-not [string]::IsNullOrWhiteSpace($CourseRootOverride)) {
    $CourseRoot = [IO.Path]::GetFullPath($CourseRootOverride)
    $ScriptRoot = Join-Path $CourseRoot "scripts"
    $ScriptDirectory = Join-Path $ScriptRoot $PlatformAbbreviation
}
else {
    $ScriptDirectory = $PSScriptRoot
    $ScriptRoot = Split-Path -Parent $ScriptDirectory
    $CourseRoot = Split-Path -Parent $ScriptRoot
}
$WindowsScriptDirectory = Join-Path $ScriptRoot $PlatformAbbreviation
$ManifestPath = Join-Path $ScriptRoot ".manifest\it140_manifest.json"
$SchemaPath = Join-Path $ScriptRoot ".manifest\it140_manifest.schema.json"
$LogDirectory = Join-Path $CourseRoot "logs"
$LogPath = Join-Path $LogDirectory (
    "update_{0}_{1}.log" -f $PlatformAbbreviation, (Get-Date -Format "yyyyMMdd_HHmmss")
)
$VenvDirectory = Join-Path $CourseRoot ".venv"
$VenvScriptsDirectory = Join-Path $VenvDirectory "Scripts"
$VenvPython = Join-Path $VenvScriptsDirectory "python.exe"
$VsCodeSettings = Join-Path $env:APPDATA "Code\User\settings.json"
$CourseShortcutPath = Join-Path (
    [Environment]::GetFolderPath("Desktop")
) "IT 140.lnk"
$VsCodeShortcutPath = Join-Path (
    [Environment]::GetFolderPath("Desktop")
) "Visual Studio Code - IT 140.lnk"
$StartTime = Get-Date
$TranscriptStarted = $false
$MutationMutex = $null
$Transaction = $null
$Changed = $false
$Partial = $false
$WarningCount = 0
$FailureCount = 0
$ExitCode = 0
$FailureExitCode = 1
$ConfigurationComplete = $false
$WorkflowName = "First use or reset environment"

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

function Write-RequiredFailure {
    param([Parameter(Mandatory = $true)][string]$Message)

    $script:FailureCount++
    $script:Partial = $true
    Write-Host "[ERROR] $Message" -ForegroundColor Red
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
IT 140 Windows update script

Usage:
  powershell.exe -ExecutionPolicy Bypass -File .\update_win.ps1
  powershell.exe -ExecutionPolicy Bypass -File .\update_win.ps1 -NonInteractive
  powershell.exe -ExecutionPolicy Bypass -File .\update_win.ps1 -Help
  powershell.exe -ExecutionPolicy Bypass -File .\update_win.ps1 -Version

Run from a normal, non-elevated Windows PowerShell terminal. A UAC prompt
appears only for targeted maintenance of machine-wide course IDE packages.
Windows Update is not run by this script.

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

function Read-ManifestAtPath {
    param(
        [Parameter(Mandatory = $true)][string]$CandidateManifest,
        [Parameter(Mandatory = $true)][string]$CandidateSchema
    )

    if (-not (Test-Path -LiteralPath $CandidateManifest -PathType Leaf)) {
        throw "The controlled manifest is missing: $CandidateManifest"
    }
    if (-not (Test-Path -LiteralPath $CandidateSchema -PathType Leaf)) {
        throw "The controlled manifest schema is missing: $CandidateSchema"
    }

    Test-JsonDuplicateKey -Path $CandidateManifest
    Test-JsonDuplicateKey -Path $CandidateSchema

    try {
        $Manifest = Get-Content -LiteralPath $CandidateManifest -Raw |
            ConvertFrom-Json
        $Schema = Get-Content -LiteralPath $CandidateSchema -Raw |
            ConvertFrom-Json
    }
    catch {
        throw "The controlled manifest or schema is not valid JSON. $($_.Exception.Message)"
    }

    $RequiredKeys = @(
        "schema_version",
        "automation_release",
        "automation_release_date",
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
    if ([string]$Manifest.schema_version -ne "2.0") {
        throw "Unsupported manifest schema version: $($Manifest.schema_version)"
    }

    $AutomationRelease = [string]$Manifest.automation_release
    $SemVerPattern = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
    if ($AutomationRelease -notmatch $SemVerPattern) {
        throw "The manifest automation release is not strict SemVer: $AutomationRelease"
    }

    $ParsedReleaseDate = [datetime]::MinValue
    $ReleaseDateIsValid = [datetime]::TryParseExact(
        [string]$Manifest.automation_release_date,
        "yyyy-MM-dd",
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$ParsedReleaseDate
    )
    if (-not $ReleaseDateIsValid) {
        throw (
            "The manifest automation release date is not valid YYYY-MM-DD: " +
            [string]$Manifest.automation_release_date
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

function Read-ControlledManifest {
    return Read-ManifestAtPath `
        -CandidateManifest $ManifestPath `
        -CandidateSchema $SchemaPath
}

function Get-OperatingSystemFact {
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
        throw "PowerShell validation failed for $Path. $Messages"
    }
}

function Get-ScriptVersion {
    param([Parameter(Mandatory = $true)][string]$Path)

    $ScriptText = Get-Content -LiteralPath $Path -Raw
    $VersionMatch = [regex]::Match(
        $ScriptText,
        '(?m)^\$ScriptVersion\s*=\s*"(?<version>' +
        '(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))"\s*$'
    )
    if (-not $VersionMatch.Success) {
        throw "A strict SemVer script version could not be read from $Path"
    }

    return [version]$VersionMatch.Groups["version"].Value
}

function Copy-FileAtomically {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$BackupDirectory
    )

    $DestinationDirectory = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Path $DestinationDirectory -Force |
        Out-Null
    New-Item -ItemType Directory -Path $BackupDirectory -Force |
        Out-Null

    $RelativeName = (
        $Destination.Replace($CourseRoot, "").TrimStart("\") -replace
        "[\\:]", "_"
    )
    $BackupPath = Join-Path $BackupDirectory $RelativeName
    $HadOriginal = Test-Path -LiteralPath $Destination -PathType Leaf
    if ($HadOriginal) {
        Copy-Item `
            -LiteralPath $Destination `
            -Destination $BackupPath `
            -Force
    }

    $StagedPath = "$Destination.it140.new"
    Copy-Item -LiteralPath $Source -Destination $StagedPath -Force

    try {
        if ($Destination -like "*.ps1") {
            Test-PowerShellScript -Path $StagedPath
            $null = Get-ScriptVersion -Path $StagedPath
        }
        elseif ($Destination -like "*.json") {
            $null = Get-Content -LiteralPath $StagedPath -Raw |
                ConvertFrom-Json
        }

        Move-Item `
            -LiteralPath $StagedPath `
            -Destination $Destination `
            -Force
        $script:Changed = $true

        return [pscustomobject]@{
            Destination = $Destination
            BackupPath = $BackupPath
            HadOriginal = $HadOriginal
        }
    }
    catch {
        Remove-Item -LiteralPath $StagedPath -Force `
            -ErrorAction SilentlyContinue
        if ($HadOriginal -and (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
            Copy-Item `
                -LiteralPath $BackupPath `
                -Destination $Destination `
                -Force
        }
        elseif (-not $HadOriginal) {
            Remove-Item -LiteralPath $Destination -Force `
                -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Invoke-GitCloneWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryUrl,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $MaximumAttempts = 5
    $DelaySeconds = 5
    for ($Attempt = 1; $Attempt -le $MaximumAttempts; $Attempt++) {
        Remove-Item -LiteralPath $Destination -Recurse -Force `
            -ErrorAction SilentlyContinue
        & git.exe clone --depth 1 $RepositoryUrl $Destination
        if ($LASTEXITCODE -eq 0) {
            return
        }

        if ($Attempt -lt $MaximumAttempts) {
            Write-Notice (
                "Repository retrieval attempt {0} of {1} failed; retrying in {2} seconds." -f
                $Attempt,
                $MaximumAttempts,
                $DelaySeconds
            )
            Start-Sleep -Seconds $DelaySeconds
            $DelaySeconds = [Math]::Min($DelaySeconds * 2, 60)
        }
    }

    throw "The controlled IT 140 course package could not be retrieved."
}

function Invoke-AssetTransaction {
    $TemporaryRoot = Join-Path `
        ([IO.Path]::GetTempPath()) `
        ("it140-update-{0}" -f ([guid]::NewGuid().ToString("N")))
    $CloneDirectory = Join-Path $TemporaryRoot "repository"
    $BackupDirectory = Join-Path $TemporaryRoot "backup"
    $SystemPhaseScript = Join-Path $TemporaryRoot "update_win_system_phase.ps1"
    $ActivationJournal = [Collections.Generic.List[object]]::new()

    New-Item -ItemType Directory -Path $TemporaryRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
    Copy-Item -LiteralPath $PSCommandPath -Destination $SystemPhaseScript -Force

    Write-Info "Staging the current controlled IT 140 course package."
    Invoke-GitCloneWithRetry `
        -RepositoryUrl "https://github.com/GC-STEM/it140.git" `
        -Destination $CloneDirectory

    Remove-Item `
        -LiteralPath (Join-Path $CloneDirectory ".git") `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    $CandidateManifest = Join-Path $CloneDirectory (
        "scripts\.manifest\it140_manifest.json"
    )
    $CandidateSchema = Join-Path $CloneDirectory (
        "scripts\.manifest\it140_manifest.schema.json"
    )
    $CandidateControlled = Read-ManifestAtPath `
        -CandidateManifest $CandidateManifest `
        -CandidateSchema $CandidateSchema

    $LifecycleScripts = @(
        "setup_win.ps1",
        "config_win.ps1",
        "update_win.ps1",
        "verify_win.ps1"
    )

    try {
        foreach ($ScriptName in $LifecycleScripts) {
            $CandidateScript = Join-Path `
                $CloneDirectory `
                ("scripts\win\{0}" -f $ScriptName)
            $InstalledScript = Join-Path $WindowsScriptDirectory $ScriptName

            if (-not (Test-Path -LiteralPath $CandidateScript -PathType Leaf)) {
                if (Test-Path -LiteralPath $InstalledScript -PathType Leaf) {
                    try {
                        Test-PowerShellScript -Path $InstalledScript
                        $null = Get-ScriptVersion -Path $InstalledScript
                        Write-WarningMessage (
                            "The repository release omitted $ScriptName; " +
                            "the valid installed copy was preserved."
                        )
                        continue
                    }
                    catch {
                        # Best-effort operation; preserve the primary result.
                    }
                }
                throw "The candidate package is missing required script: $ScriptName"
            }

            Test-PowerShellScript -Path $CandidateScript
            $CandidateVersion = Get-ScriptVersion -Path $CandidateScript

            if (Test-Path -LiteralPath $InstalledScript -PathType Leaf) {
                try {
                    $InstalledVersion = Get-ScriptVersion -Path $InstalledScript
                    if ($CandidateVersion -lt $InstalledVersion) {
                        Write-Notice (
                            "A downgrade of $ScriptName from " +
                            "$InstalledVersion to $CandidateVersion was " +
                            "prevented."
                        )
                        continue
                    }
                }
                catch {
                    Write-Notice (
                        "The installed version metadata for $ScriptName is " +
                        "invalid and will be replaced."
                    )
                }
            }

            $JournalRecord = Copy-FileAtomically `
                -Source $CandidateScript `
                -Destination $InstalledScript `
                -BackupDirectory $BackupDirectory
            $ActivationJournal.Add($JournalRecord)
        }

        Write-Info "Activating validated manifest assets."
        $JournalRecord = Copy-FileAtomically `
            -Source $CandidateSchema `
            -Destination $SchemaPath `
            -BackupDirectory $BackupDirectory
        $ActivationJournal.Add($JournalRecord)

        $JournalRecord = Copy-FileAtomically `
            -Source $CandidateManifest `
            -Destination $ManifestPath `
            -BackupDirectory $BackupDirectory
        $ActivationJournal.Add($JournalRecord)

        $Activated = Read-ControlledManifest
        if (
            [string]$Activated.Manifest.automation_release -ne
            [string]$CandidateControlled.Manifest.automation_release
        ) {
            throw "The activated manifest release does not match the validated candidate."
        }
    }
    catch {
        Write-Notice "Asset activation failed; restoring the pre-update managed assets."
        for ($Index = $ActivationJournal.Count - 1; $Index -ge 0; $Index--) {
            $JournalRecord = $ActivationJournal[$Index]
            if (
                [bool]$JournalRecord.HadOriginal -and
                (Test-Path -LiteralPath $JournalRecord.BackupPath -PathType Leaf)
            ) {
                Copy-Item `
                    -LiteralPath $JournalRecord.BackupPath `
                    -Destination $JournalRecord.Destination `
                    -Force
            }
            else {
                Remove-Item `
                    -LiteralPath $JournalRecord.Destination `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }
        $script:Changed = $false
        throw
    }

    Write-Success "Validated student-facing Windows automation assets are active."
    return [pscustomobject]@{
        TemporaryRoot = $TemporaryRoot
        BackupDirectory = $BackupDirectory
        SystemPhaseScript = $SystemPhaseScript
        Manifest = $Activated.Manifest
        Platform = $Activated.Platform
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
    return $Bindings
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

function Invoke-WinGetPackageMaintenance {
    param([Parameter(Mandatory = $true)]$Bindings)

    & winget.exe source update `
        --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "WinGet package sources could not be updated."
    }

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
            Write-Info "Installing missing required package $PackageIdentifier."
            & winget.exe install `
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
                throw "Required package installation failed: $PackageIdentifier"
            }
        }
    }
}

function Test-SystemCommand {
    param([Parameter(Mandatory = $true)]$Bindings)

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
        throw (
            "Required commands are missing after system maintenance: {0}" -f
            ($MissingCommands -join ", ")
        )
    }
}

function Invoke-SystemPhase {
    if (-not (Test-IsAdministrator)) {
        Write-ErrorMessage "The Windows update system phase requires elevation."
        exit 3
    }
    if (
        [string]::IsNullOrWhiteSpace($TransactionRoot) -or
        -not (Test-Path -LiteralPath $TransactionRoot -PathType Container)
    ) {
        Write-ErrorMessage "The update transaction directory is invalid."
        exit 5
    }
    if (
        [string]::IsNullOrWhiteSpace($CourseRootOverride) -or
        -not (Test-Path -LiteralPath $CourseRootOverride -PathType Container)
    ) {
        Write-ErrorMessage "The course root supplied to the system phase is invalid."
        exit 5
    }

    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    $SystemLog = Join-Path $LogDirectory (
        "update_win_system_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss")
    )
    Start-Transcript -Path $SystemLog -Append -Force | Out-Null

    $SystemExitCode = 0
    try {
        Write-Header "IT 140 WINDOWS UPDATE - ELEVATED COURSE COMPONENTS"
        Write-Info "Script version   : $ScriptVersion"
        Write-Info "Version date     : $VersionDate"
        Write-Info "Status           : $DevelopmentStatus"
        Write-Info "Course root      : $CourseRoot"
        Write-Info "System log       : $SystemLog"
        Write-Notice "Windows updates are not installed by this phase."

        $Controlled = Read-ControlledManifest
        $WindowsFacts = Get-OperatingSystemFact
        Test-SupportedOperatingSystem `
            -WindowsFacts $WindowsFacts `
            -Platform $Controlled.Platform

        $Bindings = Get-SystemPackageBinding -Platform $Controlled.Platform
        Invoke-WinGetPackageMaintenance -Bindings $Bindings
        Test-SystemCommand -Bindings $Bindings

        Write-Success "The elevated course IDE package phase completed."
        Write-Info "System log: $SystemLog"
        $SystemExitCode = 0
    }
    catch {
        Write-ErrorMessage $_.Exception.Message
        Write-Info "System log: $SystemLog"
        $SystemExitCode = 1
    }
    finally {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
            # Best-effort operation; preserve the primary result.
        }
    }

    exit $SystemExitCode
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

function Update-UserTool {
    param([Parameter(Mandatory = $true)]$Platform)

    Update-ProcessEnvironment
    if (-not (Test-VenvPython)) {
        if (Test-Path -LiteralPath $VenvDirectory) {
            Write-WarningMessage "The course Python environment was unusable and will be replaced."
            Remove-Item -LiteralPath $VenvDirectory -Recurse -Force
        }
        else {
            Write-Notice "The course Python environment is missing and will be created."
        }

        & python.exe -m venv $VenvDirectory
        if ($LASTEXITCODE -ne 0 -or -not (Test-VenvPython)) {
            throw "The course Python virtual environment could not be repaired."
        }
        $script:Changed = $true
    }

    $RequiredPackages = Get-RequiredPythonPackage -Platform $Platform
    Write-Info "Updating the course Python package installer and required packages."
    & $VenvPython -m pip install --upgrade pip @RequiredPackages
    if ($LASTEXITCODE -ne 0) {
        throw "The required course Python packages could not be updated."
    }
    $script:Changed = $true

    $RequiredExtensions = Get-RequiredExtension -Platform $Platform
    $PreviousNodeWarnings = [Environment]::GetEnvironmentVariable(
        "NODE_NO_WARNINGS",
        "Process"
    )
    $env:NODE_NO_WARNINGS = "1"
    try {
        & code.cmd --update-extensions
        if ($LASTEXITCODE -ne 0) {
            Write-WarningMessage "One or more optional VS Code extensions did not update."
        }

        foreach ($ExtensionId in $RequiredExtensions) {
            Write-Info "Installing or updating required VS Code extension: $ExtensionId"
            & code.cmd --install-extension $ExtensionId --force
            if ($LASTEXITCODE -ne 0) {
                Write-RequiredFailure "Required VS Code extension update failed: $ExtensionId"
            }
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

    $script:Changed = $true
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
        "files.defaultFolder" = $CourseRoot
        "workbench.editorAssociations" = @{
            "README.md" = "vscode.markdown.preview.editor"
            "*_srs.md" = "vscode.markdown.preview.editor"
            "*_sdd.md" = "vscode.markdown.preview.editor"
        }
        "settingsSync.ignoredSettings" = @(
            "python.defaultInterpreterPath",
            "files.defaultFolder"
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

function Update-ManagedGitSetting {
    param([Parameter(Mandatory = $true)]$Manifest)

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
            throw "Managed Git setting refresh failed: $($PropertyRecord.Name)"
        }
    }
    $script:Changed = $true
}

function Update-ManagedVsCodeSetting {
    param([Parameter(Mandatory = $true)]$Manifest)

    if (-not (Test-Path -LiteralPath $VsCodeSettings -PathType Leaf)) {
        Write-Notice "VS Code settings are not configured; config_win.ps1 will create them."
        return
    }

    try {
        $ExistingObject = Get-Content -LiteralPath $VsCodeSettings -Raw |
            ConvertFrom-Json
        if ($null -eq $ExistingObject -or $ExistingObject -isnot [pscustomobject]) {
            throw "The root value is not a JSON object."
        }
        $ExistingSettings = ConvertTo-Hashtable -InputObject $ExistingObject
    }
    catch {
        Write-WarningMessage "Existing VS Code settings are invalid and were preserved unchanged."
        $script:Partial = $true
        return
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
        Copy-Item `
            -LiteralPath $VsCodeSettings `
            -Destination $BackupPath `
            -Force
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
        Write-WarningMessage "Course-managed VS Code settings could not be refreshed."
        $script:Partial = $true
    }
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

function Set-DesktopShortcut {
    $DesktopDirectory = [Environment]::GetFolderPath("Desktop")
    $VsCodeExecutable = Get-VsCodeExecutablePath
    if (
        [string]::IsNullOrWhiteSpace($DesktopDirectory) -or
        [string]::IsNullOrWhiteSpace($VsCodeExecutable)
    ) {
        throw "Windows desktop shortcuts could not be refreshed."
    }

    $ShellApplication = New-Object -ComObject WScript.Shell
    $CourseShortcut = $ShellApplication.CreateShortcut($CourseShortcutPath)
    $CourseShortcut.TargetPath = "$env:SystemRoot\explorer.exe"
    $CourseShortcut.Arguments = ('"{0}"' -f $CourseRoot)
    $CourseShortcut.WorkingDirectory = $CourseRoot
    $CourseShortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,3"
    $CourseShortcut.Description = "Open the IT 140 course folder"
    $CourseShortcut.Save()

    $VsCodeShortcut = $ShellApplication.CreateShortcut($VsCodeShortcutPath)
    $VsCodeShortcut.TargetPath = $VsCodeExecutable
    $VsCodeShortcut.Arguments = ('"{0}"' -f $CourseRoot)
    $VsCodeShortcut.WorkingDirectory = $CourseRoot
    $VsCodeShortcut.IconLocation = "$VsCodeExecutable,0"
    $VsCodeShortcut.Description = "Open the IT 140 course folder in Visual Studio Code"
    $VsCodeShortcut.Save()
    $script:Changed = $true
}

function Get-GitConfigValue {
    param([Parameter(Mandatory = $true)][string]$Key)

    $ObservedOutput = @(& git.exe config --global --get $Key 2>$null)
    if ($LASTEXITCODE -ne 0 -or $ObservedOutput.Count -eq 0) {
        return ""
    }
    return ([string]$ObservedOutput[0]).Trim()
}

function Test-ConfigurationState {
    param([Parameter(Mandatory = $true)]$Manifest)

    if (-not (Test-VenvPython)) {
        return $false
    }

    $GitHubIsAuthenticated = Test-NativeCommandExitSuccess `
        -FilePath "gh.exe" `
        -ArgumentList @("auth", "status", "--hostname", "github.com")
    if (-not $GitHubIsAuthenticated) {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace((Get-GitConfigValue -Key "user.name"))) {
        return $false
    }
    if (
        (Get-GitConfigValue -Key "user.email") -notmatch
        "^[0-9]+\+[^@\s]+@users\.noreply\.github\.com$"
    ) {
        return $false
    }

    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    foreach ($ManagedPath in @($VenvScriptsDirectory, $WindowsScriptDirectory)) {
        if (-not (Test-PathContainsEntry -PathValue $UserPath -ExpectedEntry $ManagedPath)) {
            return $false
        }
    }

    if (-not (Test-Path -LiteralPath $VsCodeSettings -PathType Leaf)) {
        return $false
    }
    try {
        $ObservedSettings = Get-Content -LiteralPath $VsCodeSettings -Raw |
            ConvertFrom-Json
        $InterpreterProperty = $ObservedSettings.PSObject.Properties[
            "python.defaultInterpreterPath"
        ]
        if (
            $null -eq $InterpreterProperty -or
            [string]$InterpreterProperty.Value -cne $VenvPython
        ) {
            return $false
        }
    }
    catch {
        return $false
    }

    foreach ($ShortcutPath in @($CourseShortcutPath, $VsCodeShortcutPath)) {
        if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) {
            return $false
        }
    }

    return $true
}

function Update-ManagedIntegration {
    param([Parameter(Mandatory = $true)]$Manifest)

    Update-ManagedGitSetting -Manifest $Manifest
    Update-ManagedVsCodeSetting -Manifest $Manifest

    if (
        $ConfigurationComplete -or
        (Test-Path -LiteralPath $CourseShortcutPath -PathType Leaf) -or
        (Test-Path -LiteralPath $VsCodeShortcutPath -PathType Leaf)
    ) {
        try {
            Set-DesktopShortcut
            Write-Success "Course-managed Windows shortcuts were refreshed."
        }
        catch {
            Write-WarningMessage $_.Exception.Message
            $script:Partial = $true
        }
    }
    else {
        Write-Notice "Desktop shortcuts are not configured; config_win.ps1 will create them."
    }
}

function Test-PostUpdateState {
    param([Parameter(Mandatory = $true)]$Platform)

    try {
        $null = Read-ControlledManifest
    }
    catch {
        Write-RequiredFailure "The active manifest or schema is invalid after update."
    }

    foreach ($ScriptName in @(
        "setup_win.ps1",
        "config_win.ps1",
        "update_win.ps1",
        "verify_win.ps1"
    )) {
        $ScriptPath = Join-Path $WindowsScriptDirectory $ScriptName
        if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
            Write-RequiredFailure "Required lifecycle script is missing: $ScriptName"
            continue
        }
        try {
            Test-PowerShellScript -Path $ScriptPath
            $null = Get-ScriptVersion -Path $ScriptPath
        }
        catch {
            Write-RequiredFailure "Required lifecycle script is invalid: $ScriptName"
        }
    }

    $SystemBindings = Get-SystemPackageBinding -Platform $Platform
    try {
        Test-SystemCommand -Bindings $SystemBindings
    }
    catch {
        Write-RequiredFailure $_.Exception.Message
    }

    if (-not (Test-VenvPython)) {
        Write-RequiredFailure "The course Python 3.12 virtual environment is not usable."
    }
    else {
        foreach ($PackageName in (Get-RequiredPythonPackage -Platform $Platform)) {
            $PackageIsInstalled = Test-NativeCommandExitSuccess `
                -FilePath $VenvPython `
                -ArgumentList @("-m", "pip", "show", $PackageName)
            if (-not $PackageIsInstalled) {
                Write-RequiredFailure "Required course Python package is missing: $PackageName"
            }
        }
    }

    $InstalledExtensions = @(
        & code.cmd --list-extensions 2>$null |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() }
    )
    foreach ($ExtensionId in (Get-RequiredExtension -Platform $Platform)) {
        if ($ExtensionId.ToLowerInvariant() -notin $InstalledExtensions) {
            Write-RequiredFailure "Required VS Code extension is missing: $ExtensionId"
        }
    }
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

if ($SystemPhase) {
    Invoke-SystemPhase
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

    Write-Header "IT 140 WINDOWS UPDATE"
    Write-Info "Script version   : $ScriptVersion"
    Write-Info "Version date     : $VersionDate"
    Write-Info "Status           : $DevelopmentStatus"
    Write-Info "Deployment       : $DeploymentProfile"
    Write-Info "Current user     : $([Environment]::UserName)"
    Write-Info "Course root      : $CourseRoot"
    Write-Info "Log file         : $LogPath"
    Write-Notice "Keep this PowerShell window open until the update completes."
    Write-Notice "Windows updates are not installed by this script."
    Write-Notice (
        "Student files, repositories, Git history, optional extensions, " +
        "and unrelated settings will be preserved."
    )

    if (Test-IsAdministrator) {
        $FailureExitCode = 3
        throw (
            "Run update_win.ps1 from a normal, non-elevated PowerShell window. " +
            "The script will request UAC elevation only for machine-wide " +
            "course IDE package maintenance."
        )
    }

    $MutationMutex = Enter-MutationLock
    Update-ProcessEnvironment

    $FailureExitCode = 5
    $Controlled = Read-ControlledManifest

    $FailureExitCode = 2
    $WindowsFacts = Get-OperatingSystemFact
    Test-SupportedOperatingSystem `
        -WindowsFacts $WindowsFacts `
        -Platform $Controlled.Platform

    $FailureExitCode = 1
    foreach ($RequiredCommand in @(
        "git.exe",
        "winget.exe",
        "gh.exe",
        "python.exe",
        "code.cmd"
    )) {
        if ($null -eq (Get-Command $RequiredCommand -ErrorAction SilentlyContinue)) {
            throw "Required update command is missing: $RequiredCommand. Run setup_win.ps1."
        }
    }

    $FreeSpace = (Get-PSDrive -Name $env:SystemDrive.TrimEnd(":")).Free
    $MinimumSpace = [int64]$Controlled.Manifest.policy.minimum_free_space_bytes
    if ($FreeSpace -lt $MinimumSpace) {
        throw (
            "The system drive has {0:N1} GB free; at least {1:N1} GB is required." -f
            ($FreeSpace / 1GB),
            ($MinimumSpace / 1GB)
        )
    }

    $ConfigurationComplete = Test-ConfigurationState `
        -Manifest $Controlled.Manifest
    if ($ConfigurationComplete) {
        $WorkflowName = "Periodic maintenance"
    }
    else {
        $WorkflowName = "First use or reset environment"
        Write-Notice (
            "User configuration is incomplete; the summary will direct " +
            "you to config_win.ps1."
        )
    }
    Write-Info "Workflow         : $WorkflowName"

    $FailureExitCode = 4
    $Transaction = Invoke-AssetTransaction

    Write-Info "Starting elevated maintenance of machine-wide course IDE packages."
    $SystemArguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $Transaction.SystemPhaseScript),
        "-SystemPhase",
        "-TransactionRoot", ('"{0}"' -f $Transaction.TemporaryRoot),
        "-CourseRootOverride", ('"{0}"' -f $CourseRoot),
        "-DeploymentProfile", $DeploymentProfile
    )
    if ($NonInteractive) {
        $SystemArguments += "-NonInteractive"
    }

    try {
        $SystemProcess = Start-Process `
            -FilePath "powershell.exe" `
            -Verb RunAs `
            -ArgumentList ($SystemArguments -join " ") `
            -Wait `
            -PassThru
        if ($SystemProcess.ExitCode -ne 0) {
            Write-RequiredFailure (
                "The elevated system phase returned exit code {0}." -f
                $SystemProcess.ExitCode
            )
        }
    }
    catch [System.ComponentModel.Win32Exception] {
        Write-RequiredFailure "The elevated system phase was canceled or could not start."
    }

    try {
        Write-Info "Updating current-user course tools and extensions."
        $ActiveControlled = Read-ControlledManifest
        Update-UserTool -Platform $ActiveControlled.Platform
        Update-ManagedIntegration -Manifest $ActiveControlled.Manifest
        Write-Success "Current-user course components were updated."
    }
    catch {
        Write-RequiredFailure $_.Exception.Message
    }

    $ActiveControlled = Read-ControlledManifest
    Test-PostUpdateState -Platform $ActiveControlled.Platform

    $Elapsed = (Get-Date) - $StartTime
    Write-Header "UPDATE SUMMARY"
    Write-Info "Workflow          : $WorkflowName"
    Write-Info "Script version    : $ScriptVersion"
    Write-Info "Version date      : $VersionDate"
    Write-Info "Status            : $DevelopmentStatus"
    Write-Info "Windows           : $($WindowsFacts.Caption)"
    Write-Info "Release           : $($WindowsFacts.DisplayVersion)"
    Write-Info "Manifest release  : $($ActiveControlled.Manifest.automation_release)"
    Write-Info "Manifest date     : $($ActiveControlled.Manifest.automation_release_date)"
    Write-Info "Git               : $(Get-CommandVersionLine -CommandName 'git.exe')"
    Write-Info "GitHub CLI        : $(Get-CommandVersionLine -CommandName 'gh.exe')"
    Write-Info "Python            : $(Get-CommandVersionLine -CommandName 'python.exe')"
    Write-Info "VS Code           : $(Get-CommandVersionLine -CommandName 'code.cmd')"
    Write-Info "Warnings          : $WarningCount"
    Write-Info "Failures          : $FailureCount"
    Write-Info ("Elapsed time      : {0:hh\:mm\:ss}" -f $Elapsed)
    Write-Info "Log file          : $LogPath"

    Write-Notice "Close and reopen Visual Studio Code before continuing coursework."

    if ($Partial -or $FailureCount -gt 0) {
        Write-ErrorMessage "The update completed partially."
        if ($ConfigurationComplete) {
            Write-Notice (
                "Next step: run verify_win.ps1 and follow its " +
                "remediation guidance."
            )
        }
        else {
            Write-Notice (
                "Next step: run config_win.ps1, then verify_win.ps1."
            )
        }
        Write-Info "Exit code         : 7"
        Write-ClosingNotice
        $ExitCode = 7
    }
    else {
        Write-Success "The IT 140 Windows update completed successfully."
        if ($ConfigurationComplete) {
            Write-Notice "Next step: run verify_win.ps1."
        }
        else {
            Write-Notice "Next step: run config_win.ps1."
        }
        Write-Info "Exit code         : 0"
        Write-ClosingNotice
        $ExitCode = 0
    }
}
catch {
    $LineNumber = $_.InvocationInfo.ScriptLineNumber
    Write-ErrorMessage $_.Exception.Message
    if ($LineNumber) {
        Write-ErrorMessage "Update stopped near line $LineNumber."
    }
    Write-Info "Update log: $LogPath"
    if ($Changed) {
        Write-Notice (
            "Managed state changed before update stopped. " +
            "Rerun update_win.ps1 to repair it."
        )
        $ExitCode = 7
    }
    else {
        $ExitCode = $FailureExitCode
    }
}
finally {
    if ($null -ne $Transaction) {
        Remove-Item `
            -LiteralPath $Transaction.TemporaryRoot `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }

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
