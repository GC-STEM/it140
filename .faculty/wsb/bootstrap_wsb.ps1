#requires -Version 5.1
<#
.SYNOPSIS
Retrieves the current IT 140 automation package and starts Windows Sandbox setup.

.DESCRIPTION
Performs only the bootstrap work required in a fresh Windows Sandbox session:
creates the course and log folders, downloads the current repository archive,
extracts it under ~/it140, and starts setup_wsb.ps1 in a separate Windows
PowerShell process. WinGet and course software are installed by setup_wsb.ps1.

This script is suitable for direct use or automatic execution from the IT 140
Windows Sandbox configuration file.

Artifact version:
    0.2.0

Version date:
    2026-07-29

Development status:
    Alpha Testing

Version basis:
    Version 0.1.0 represents the initial Windows Sandbox bootstrap baseline.
    Version 0.2.0 adopts SemVer metadata and current transcript reporting.

.NOTES
Logs are written under ~/it140/logs/.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ArtifactVersion = "0.2.0"
$VersionDate = "2026-07-29"
$DevelopmentStatus = "Beta Testing"
$RepositoryArchive = "https://github.com/GC-STEM/it140/archive/refs/heads/main.zip"
$CourseRoot = Join-Path ([Environment]::GetFolderPath("UserProfile")) "it140"
$LogDirectory = Join-Path $CourseRoot "logs"
$LogPath = Join-Path $LogDirectory (
    "bootstrap_wsb_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss")
)
$TemporaryRoot = Join-Path (
    [IO.Path]::GetTempPath()
) ("it140-wsb-bootstrap-{0}" -f ([guid]::NewGuid().ToString("N")))
$ArchivePath = Join-Path $TemporaryRoot "it140-main.zip"
$PartialArchivePath = "$ArchivePath.part"
$ExtractRoot = Join-Path $TemporaryRoot "extract"
$SetupPath = Join-Path $CourseRoot "scripts\win\wsb\setup_wsb.ps1"
$TranscriptStarted = $false
$ExitCode = 1

try {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    Start-Transcript -Path $LogPath -Force | Out-Null
    $TranscriptStarted = $true

    Write-Host ""
    Write-Host "============================================================"
    Write-Host "IT 140 WINDOWS SANDBOX BOOTSTRAP"
    Write-Host "============================================================"
    Write-Host "[INFO] Artifact version : $ArtifactVersion"
    Write-Host "[INFO] Version DTG      : $VersionDate"
    Write-Host "[INFO] Status           : $DevelopmentStatus"
    Write-Host "[INFO] Current user     : $([Environment]::UserName)"
    Write-Host "[INFO] Purpose          : Retrieve and start the WSB automation package"
    Write-Host "[INFO] Course root      : $CourseRoot"
    Write-Host "[INFO] Log file         : $LogPath"

    if ([Environment]::UserName -ne "WDAGUtilityAccount") {
        throw "This bootstrap supports only Windows Sandbox."
    }

    New-Item -ItemType Directory -Path $TemporaryRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $ExtractRoot -Force | Out-Null

    Write-Host "[INFO] Downloading the current IT 140 automation package."
    & curl.exe `
        --location `
        --fail `
        --show-error `
        --retry 5 `
        --retry-delay 5 `
        --retry-all-errors `
        --continue-at - `
        --output $PartialArchivePath `
        $RepositoryArchive
    if ($LASTEXITCODE -ne 0) {
        throw "The IT 140 automation package download failed with curl exit code $LASTEXITCODE."
    }

    Move-Item `
        -LiteralPath $PartialArchivePath `
        -Destination $ArchivePath `
        -Force
    Expand-Archive `
        -LiteralPath $ArchivePath `
        -DestinationPath $ExtractRoot `
        -Force

    $DownloadedRoot = Get-ChildItem -LiteralPath $ExtractRoot -Directory |
        Select-Object -First 1
    if ($null -eq $DownloadedRoot) {
        throw "The downloaded IT 140 automation package is not valid."
    }

    Write-Host "[INFO] Installing the automation package under $CourseRoot."
    New-Item -ItemType Directory -Path $CourseRoot -Force | Out-Null
    Get-ChildItem -LiteralPath $DownloadedRoot.FullName -Force |
        Copy-Item -Destination $CourseRoot -Recurse -Force
    Remove-Item `
        -LiteralPath (Join-Path $CourseRoot ".git") `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

    if (-not (Test-Path -LiteralPath $SetupPath -PathType Leaf)) {
        throw "The downloaded package does not contain setup_wsb.ps1."
    }

    Write-Host "[SUCCESS] The current IT 140 automation package is available."
    Write-Host "[INFO] Starting Windows Sandbox setup."

    & powershell.exe `
        -NoLogo `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $SetupPath
    $SetupExitCode = $LASTEXITCODE
    if ($SetupExitCode -ne 0) {
        throw "setup_wsb.ps1 failed with exit code $SetupExitCode."
    }

    Write-Host "[SUCCESS] Windows Sandbox bootstrap and setup completed."
    Write-Host "[NOTICE] Continue in the normal PowerShell window opened by setup_wsb.ps1."
    Write-Host "[NOTICE] Bootstrap log: $LogPath"
    $ExitCode = 0
}
catch {
    $LineNumber = $_.InvocationInfo.ScriptLineNumber
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    if ($LineNumber) {
        Write-Host "[ERROR] Bootstrap stopped near line $LineNumber." -ForegroundColor Red
    }
    Write-Host "[INFO] Bootstrap log: $LogPath"
    $ExitCode = 1
}
finally {
    Remove-Item `
        -LiteralPath $TemporaryRoot `
        -Recurse `
        -Force `
        -ErrorAction SilentlyContinue

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
