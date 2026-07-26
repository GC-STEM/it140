#requires -Version 5.1
<#
.SYNOPSIS
Updates the Windows IT 140 Course IDE within the current Windows release.

.DESCRIPTION
Stages and validates controlled repository assets, updates current-release
Windows quality and security updates, upgrades the manifest-declared WinGet
packages, updates the course Python environment and required VS Code
extensions, preserves optional extensions, refreshes managed settings, and
reports restart guidance.

Run this script from a normal, non-elevated PowerShell terminal. It launches a
separate elevated system phase only for Windows and machine-package updates.
#>

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Version,
    [ValidateSet("windows_bare_metal")]
    [string]$DeploymentProfile = "windows_bare_metal",
    [switch]$NonInteractive,
    [switch]$SystemPhase,
    [string]$TransactionRoot
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
    "update_win_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss")
)
$VenvDirectory = Join-Path $CourseRoot ".venv"
$VenvPython = Join-Path $VenvDirectory "Scripts\python.exe"
$VsCodeSettings = Join-Path $env:APPDATA "Code\User\settings.json"
$TranscriptStarted = $false
$MutationMutex = $null
$ExitCode = 0
$PartialFailure = $false

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

function Refresh-ProcessEnvironment {
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

function Read-ManifestAtPath {
    param(
        [Parameter(Mandatory = $true)][string]$CandidateManifest,
        [Parameter(Mandatory = $true)][string]$CandidateSchema
    )

    if (-not (Test-Path -LiteralPath $CandidateManifest -PathType Leaf)) {
        throw "The controlled manifest is missing: $CandidateManifest"
    }
    if (-not (Test-Path -LiteralPath $CandidateSchema -PathType Leaf)) {
        throw "The manifest schema is missing: $CandidateSchema"
    }

    try {
        $Manifest = Get-Content -LiteralPath $CandidateManifest -Raw |
            ConvertFrom-Json
        $null = Get-Content -LiteralPath $CandidateSchema -Raw |
            ConvertFrom-Json
    }
    catch {
        throw "The manifest or schema is not valid JSON."
    }

    if ([string]$Manifest.schema_version -ne "1.0") {
        throw "Unsupported manifest schema version: $($Manifest.schema_version)"
    }

    $Platform = Get-PropertyValue -Object $Manifest.platforms -Name $PlatformId
    $Profile = Get-PropertyValue `
        -Object $Manifest.deployment_profiles `
        -Name $DeploymentProfile
    if ($null -eq $Platform -or -not [bool]$Platform.enabled) {
        throw "The Windows platform is not enabled."
    }
    if ($null -eq $Profile -or -not [bool]$Profile.enabled) {
        throw "The deployment profile is not enabled."
    }
    if ([string]$Profile.platform_id -ne $PlatformId) {
        throw "The deployment profile does not select Windows."
    }

    return [pscustomobject]@{
        Manifest = $Manifest
        Platform = $Platform
        Profile = $Profile
    }
}

function Read-ControlledManifest {
    return Read-ManifestAtPath `
        -CandidateManifest $ManifestPath `
        -CandidateSchema $SchemaPath
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

function Test-PowerShellScript {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Tokens = $null
    $Errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile(
        $Path,
        [ref]$Tokens,
        [ref]$Errors
    )

    if ($Errors.Count -gt 0) {
        $Messages = @($Errors | ForEach-Object { $_.Message }) -join "; "
        throw "PowerShell validation failed for $Path. $Messages"
    }
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

    $RelativeName = (
        $Destination.Replace($CourseRoot, "").TrimStart("\") -replace
        "[\\:]", "_"
    )
    $BackupPath = Join-Path $BackupDirectory $RelativeName
    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
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
        }
        elseif ($Destination -like "*.json") {
            $null = Get-Content -LiteralPath $StagedPath -Raw |
                ConvertFrom-Json
        }

        Move-Item `
            -LiteralPath $StagedPath `
            -Destination $Destination `
            -Force
    }
    catch {
        Remove-Item -LiteralPath $StagedPath -Force `
            -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $BackupPath -PathType Leaf) {
            Copy-Item `
                -LiteralPath $BackupPath `
                -Destination $Destination `
                -Force
        }
        throw
    }
}

function Invoke-AssetTransaction {
    $TemporaryRoot = Join-Path `
        ([IO.Path]::GetTempPath()) `
        ("it140-update-{0}" -f ([guid]::NewGuid().ToString("N")))
    $CloneDirectory = Join-Path $TemporaryRoot "repository"
    $BackupDirectory = Join-Path $TemporaryRoot "backup"
    $SystemPhaseScript = Join-Path $TemporaryRoot "update_system_phase.ps1"

    New-Item -ItemType Directory -Path $TemporaryRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null
    Copy-Item -LiteralPath $PSCommandPath -Destination $SystemPhaseScript -Force

    Write-Info "Staging the current controlled course package."
    & git.exe clone `
        --depth 1 `
        "https://github.com/GC-STEM/it140.git" `
        $CloneDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "The controlled course package could not be retrieved."
    }

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

    foreach ($ScriptName in @(
        "setup_win.ps1",
        "configure_win.ps1",
        "verify_win.ps1",
        "update_win.ps1"
    )) {
        $CandidateScript = Join-Path `
            $CloneDirectory `
            ("scripts\win\{0}" -f $ScriptName)
        if (-not (Test-Path -LiteralPath $CandidateScript -PathType Leaf)) {
            throw "The candidate package is missing $ScriptName."
        }
        Test-PowerShellScript -Path $CandidateScript
    }

    $ActivationPairs = @(
        [pscustomobject]@{
            Source = $CandidateSchema
            Destination = $SchemaPath
        },
        [pscustomobject]@{
            Source = $CandidateManifest
            Destination = $ManifestPath
        }
    )

    foreach ($ScriptName in @(
        "setup_win.ps1",
        "configure_win.ps1",
        "verify_win.ps1",
        "update_win.ps1"
    )) {
        $ActivationPairs += [pscustomobject]@{
            Source = Join-Path `
                $CloneDirectory `
                ("scripts\win\{0}" -f $ScriptName)
            Destination = Join-Path $WindowsScriptDirectory $ScriptName
        }
    }

    Write-Info "Activating validated managed assets."
    foreach ($Pair in $ActivationPairs) {
        Copy-FileAtomically `
            -Source $Pair.Source `
            -Destination $Pair.Destination `
            -BackupDirectory $BackupDirectory
    }

    $Activated = Read-ControlledManifest
    if (
        [string]$Activated.Manifest.automation_release -ne
        [string]$CandidateControlled.Manifest.automation_release
    ) {
        throw "The activated manifest release does not match the candidate."
    }

    return [pscustomobject]@{
        TemporaryRoot = $TemporaryRoot
        SystemPhaseScript = $SystemPhaseScript
        Manifest = $Activated.Manifest
        Platform = $Activated.Platform
    }
}

function Get-SystemPackageIdentifiers {
    param([Parameter(Mandatory = $true)]$Platform)

    $Identifiers = @()
    foreach ($Property in $Platform.course_ide_bindings.PSObject.Properties) {
        $Binding = $Property.Value
        if ([string]$Binding.installation_scope -eq "system") {
            $Identifiers += [string]$Binding.package_identifier
        }
    }
    return @($Identifiers | Sort-Object -Unique)
}

function Invoke-CurrentReleaseWindowsUpdates {
    Write-Info "Searching for current-release Windows quality and security updates."

    $Session = New-Object -ComObject Microsoft.Update.Session
    $Searcher = $Session.CreateUpdateSearcher()
    $SearchResult = $Searcher.Search(
        "IsInstalled=0 and IsHidden=0 and Type='Software'"
    )

    $Updates = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($Update in $SearchResult.Updates) {
        $Title = [string]$Update.Title
        $IsFeatureUpgrade = (
            $Title -match "Feature update to Windows" -or
            $Title -match "Upgrade to Windows" -or
            $Title -match "Windows 11, version [0-9]+H[0-9]+"
        )
        if ($IsFeatureUpgrade) {
            Write-Notice "Skipping Windows release upgrade: $Title"
            continue
        }

        if (-not $Update.EulaAccepted) {
            $Update.AcceptEula()
        }
        $null = $Updates.Add($Update)
    }

    if ($Updates.Count -eq 0) {
        Write-Success "No applicable current-release Windows updates were found."
        return [pscustomobject]@{
            ResultCode = 0
            RebootRequired = $false
        }
    }

    Write-Info ("Downloading {0} Windows update(s)." -f $Updates.Count)
    $Downloader = $Session.CreateUpdateDownloader()
    $Downloader.Updates = $Updates
    $DownloadResult = $Downloader.Download()
    if ([int]$DownloadResult.ResultCode -notin @(2, 3)) {
        throw (
            "Windows Update download returned result code {0}." -f
            $DownloadResult.ResultCode
        )
    }

    Write-Info "Installing current-release Windows updates."
    $Installer = $Session.CreateUpdateInstaller()
    $Installer.Updates = $Updates
    $InstallResult = $Installer.Install()
    if ([int]$InstallResult.ResultCode -notin @(2, 3)) {
        throw (
            "Windows Update installation returned result code {0}." -f
            $InstallResult.ResultCode
        )
    }

    return [pscustomobject]@{
        ResultCode = [int]$InstallResult.ResultCode
        RebootRequired = [bool]$InstallResult.RebootRequired
    }
}

function Invoke-WinGetPackageUpdates {
    param([Parameter(Mandatory = $true)][string[]]$PackageIdentifiers)

    & winget.exe source update `
        --accept-source-agreements `
        --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "WinGet package sources could not be updated."
    }

    foreach ($PackageIdentifier in $PackageIdentifiers) {
        Write-Info "Updating or repairing $PackageIdentifier."
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
            Write-Notice (
                "WinGet did not complete an upgrade for $PackageIdentifier. " +
                "The installed package will be verified."
            )
            & winget.exe list `
                --id $PackageIdentifier `
                --exact `
                --source winget `
                --accept-source-agreements `
                --disable-interactivity *> $null
            if ($LASTEXITCODE -ne 0) {
                throw "Required package is unavailable: $PackageIdentifier"
            }
        }
    }
}

function Invoke-SystemPhase {
    if (-not (Test-IsAdministrator)) {
        Write-ErrorMessage "The update system phase requires elevation."
        exit 3
    }
    if (
        [string]::IsNullOrWhiteSpace($TransactionRoot) -or
        -not (Test-Path -LiteralPath $TransactionRoot -PathType Container)
    ) {
        Write-ErrorMessage "The update transaction directory is invalid."
        exit 5
    }

    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    $SystemLog = Join-Path $LogDirectory (
        "update_win_system_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss")
    )
    Start-Transcript -Path $SystemLog -Append -Force | Out-Null

    $SystemExit = 0
    try {
        Write-Host ""
        Write-Host "============================================================"
        Write-Host "IT 140 WINDOWS UPDATE - ELEVATED SYSTEM PHASE"
        Write-Host "============================================================"
        $Controlled = Read-ControlledManifest
        $WindowsFacts = Get-WindowsFacts
        Assert-SupportedWindows `
            -WindowsFacts $WindowsFacts `
            -Platform $Controlled.Platform

        $UpdateResult = Invoke-CurrentReleaseWindowsUpdates
        $PackageIdentifiers = Get-SystemPackageIdentifiers `
            -Platform $Controlled.Platform
        Invoke-WinGetPackageUpdates `
            -PackageIdentifiers $PackageIdentifiers

        if ($UpdateResult.RebootRequired) {
            Set-Content `
                -LiteralPath (Join-Path $TransactionRoot "reboot-required") `
                -Value "true" `
                -Encoding ASCII
        }

        Write-Success "The elevated system update phase completed."
        Write-Info "System log: $SystemLog"
        $SystemExit = 0
    }
    catch {
        Write-ErrorMessage $_.Exception.Message
        Write-Info "System log: $SystemLog"
        $SystemExit = 1
    }
    finally {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
        }
    }

    exit $SystemExit
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

function Update-UserTools {
    Refresh-ProcessEnvironment

    if (-not (Test-Path -LiteralPath $VenvPython -PathType Leaf)) {
        Write-Notice "The course virtual environment is missing; repairing it."
        & python.exe -m venv $VenvDirectory
        if ($LASTEXITCODE -ne 0) {
            throw "The course virtual environment could not be repaired."
        }
    }

    & $VenvPython -m pip install `
        --upgrade `
        pip `
        pytest `
        pytest-cov `
        ruff
    if ($LASTEXITCODE -ne 0) {
        throw "The course Python tools could not be updated."
    }

    $env:NODE_NO_WARNINGS = "1"
    try {
        & code.cmd --update-extensions
        if ($LASTEXITCODE -ne 0) {
            Write-Notice (
                "One or more optional VS Code extensions did not update."
            )
        }

        $Controlled = Read-ControlledManifest
        foreach ($Extension in Get-RequiredExtensions $Controlled.Platform) {
            & code.cmd --install-extension $Extension --force
            if ($LASTEXITCODE -ne 0) {
                throw "Required extension update failed: $Extension"
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

function Refresh-ManagedSettings {
    $Controlled = Read-ControlledManifest
    $GitSettings = Get-PropertyValue `
        -Object $Controlled.Manifest.managed_settings `
        -Name "git_course_defaults"

    foreach ($Property in $GitSettings.values.PSObject.Properties) {
        $Value = $Property.Value
        if ($Value -is [bool]) {
            $Value = $Value.ToString().ToLowerInvariant()
        }
        & git.exe config --global $Property.Name ([string]$Value)
        if ($LASTEXITCODE -ne 0) {
            throw "Git setting refresh failed: $($Property.Name)"
        }
    }

    $SettingsProfile = Get-PropertyValue `
        -Object $Controlled.Manifest.managed_settings `
        -Name "vscode_course_defaults"
    $Existing = @{}
    if (Test-Path -LiteralPath $VsCodeSettings -PathType Leaf) {
        $Existing = ConvertTo-Hashtable (
            Get-Content -LiteralPath $VsCodeSettings -Raw |
                ConvertFrom-Json
        )
    }

    $Managed = ConvertTo-Hashtable $SettingsProfile.values
    $Managed["python.defaultInterpreterPath"] = $VenvPython
    Merge-Hashtable -Target $Existing -Source $Managed

    $Staged = "$VsCodeSettings.it140.tmp"
    New-Item -ItemType Directory -Path (Split-Path $VsCodeSettings) -Force |
        Out-Null
    $Existing | ConvertTo-Json -Depth 50 |
        Set-Content -LiteralPath $Staged -Encoding UTF8
    $null = Get-Content -LiteralPath $Staged -Raw | ConvertFrom-Json
    Move-Item -LiteralPath $Staged -Destination $VsCodeSettings -Force
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

function Show-Usage {
    @"
IT 140 Windows update script

Usage:
  powershell.exe -ExecutionPolicy Bypass -File .\update_win.ps1
  powershell.exe -ExecutionPolicy Bypass -File .\update_win.ps1 -Help

Run this script from a normal, non-elevated PowerShell terminal. A UAC prompt
appears only for the Windows and machine-package update phase.
The script never performs a Windows feature-version upgrade.
Logs: $LogDirectory
"@ | Write-Host
}

if ($SystemPhase) {
    Invoke-SystemPhase
}

$Transaction = $null
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
    Write-Host "IT 140 WINDOWS UPDATE"
    Write-Host "============================================================"
    Write-Info "Script version : $ScriptVersion"
    Write-Info "Deployment     : $DeploymentProfile"
    Write-Info "Current user   : $([Environment]::UserName)"
    Write-Info "Log file       : $LogPath"
    Write-Notice (
        "Save open coursework before continuing. The script will not " +
        "upgrade Windows to a different feature release."
    )

    if (Test-IsAdministrator) {
        Write-ErrorMessage (
            "Run update_win.ps1 from a normal terminal. The script will " +
            "request elevation only for its system phase."
        )
        $ExitCode = 3
        return
    }

    $MutationMutex = Enter-MutationLock
    Refresh-ProcessEnvironment

    $Controlled = Read-ControlledManifest
    $WindowsFacts = Get-WindowsFacts
    Assert-SupportedWindows `
        -WindowsFacts $WindowsFacts `
        -Platform $Controlled.Platform

    foreach ($Command in @("git.exe", "winget.exe", "python.exe", "code.cmd")) {
        if ($null -eq (Get-Command $Command -ErrorAction SilentlyContinue)) {
            throw "Required command is missing: $Command"
        }
    }

    $FreeSpace = (Get-PSDrive -Name $env:SystemDrive.TrimEnd(":")).Free
    if ($FreeSpace -lt [int64]$Controlled.Manifest.policy.minimum_free_space_bytes) {
        throw "The system drive does not have enough free space."
    }

    $Transaction = Invoke-AssetTransaction

    Write-Info "Starting the elevated Windows and machine-package update phase."
    $SystemArguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ('"{0}"' -f $Transaction.SystemPhaseScript),
        "-SystemPhase",
        "-TransactionRoot", ('"{0}"' -f $Transaction.TemporaryRoot),
        "-DeploymentProfile", $DeploymentProfile
    )
    $SystemProcess = Start-Process `
        -FilePath "powershell.exe" `
        -Verb RunAs `
        -ArgumentList ($SystemArguments -join " ") `
        -Wait `
        -PassThru

    if ($SystemProcess.ExitCode -ne 0) {
        Write-Notice (
            "The elevated system phase returned exit code {0}." -f
            $SystemProcess.ExitCode
        )
        $PartialFailure = $true
    }

    try {
        Write-Info "Updating current-user course tools and extensions."
        Update-UserTools
        Refresh-ManagedSettings
        Write-Success "Current-user course components are current."
    }
    catch {
        Write-ErrorMessage $_.Exception.Message
        $PartialFailure = $true
    }

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "UPDATE SUMMARY"
    Write-Host "============================================================"
    Write-Info "Windows        : $($WindowsFacts.Caption)"
    Write-Info "Release        : $($WindowsFacts.DisplayVersion)"
    Write-Info "Python         : $(& python.exe --version)"
    Write-Info "Git            : $(& git.exe --version)"
    Write-Info "GitHub CLI     : $((& gh.exe --version)[0])"
    Write-Info "VS Code        : $((& code.cmd --version)[0])"
    Write-Info "Log file       : $LogPath"

    $TransactionRestart = $false
    if ($null -ne $Transaction) {
        $TransactionRestart = Test-Path -LiteralPath (
            Join-Path $Transaction.TemporaryRoot "reboot-required"
        )
    }

    if ($TransactionRestart -or (Test-PendingRestart)) {
        Write-Notice "A Windows restart is required to finish applying updates."
        Write-Notice "Save work, close applications, and restart Windows."
    }
    else {
        Write-Notice "Windows does not currently report a required restart."
        Write-Notice "Close and reopen VS Code before continuing coursework."
    }

    if ($PartialFailure) {
        Write-ErrorMessage (
            "The update completed partially. Run verify_win.ps1 and follow " +
            "its remediation guidance."
        )
        $ExitCode = 7
    }
    else {
        Write-Success "The IT 140 Windows update completed successfully."
        Write-Notice "Run verify_win.ps1 when convenient."
        $ExitCode = 0
    }
}
catch {
    Write-ErrorMessage $_.Exception.Message
    Write-Notice "Review the update log before requesting support."
    Write-Info "Update log: $LogPath"
    $ExitCode = 1
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
