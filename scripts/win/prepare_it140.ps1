# IT 140 Windows bootstrap command set
#
# Repository path:
#     scripts/win/prepare_it140.ps1
#
# Purpose:
#     Retrieve the current course automation package and make the Windows
#     lifecycle scripts available from this PowerShell session and future
#     PowerShell sessions.
#
# Artifact version:
#     0.2.0
#
# Version date:
#     2026-07-29
#
# Development status:
#     Alpha Testing
#
# Version basis:
#     Version 0.1.0 represents the initial Windows bootstrap baseline.
#     Version 0.2.0 adopts SemVer metadata and transcript reporting.
#
# This file models the commands students copy and run before setup. It is not a
# managed lifecycle script and therefore does not accept command-line options,
# use the manifest, acquire a lifecycle lock, or display a managed summary.

$LogDirectory = Join-Path ([Environment]::GetFolderPath("UserProfile")) "it140\logs"
$LogPath = Join-Path $LogDirectory (
    "prepare_ide_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
Start-Transcript -Path $LogPath -Force | Out-Null

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ArtifactVersion = "0.2.0"
$VersionDate = "2026-07-29"
$DevelopmentStatus = "Alpha Testing"
$PlatformAbbreviation = "win"
$RepositoryArchive = "https://github.com/GC-STEM/it140/archive/refs/heads/main.zip"
$CourseRoot = Join-Path ([Environment]::GetFolderPath("UserProfile")) "it140"
$TemporaryRoot = Join-Path (
    [IO.Path]::GetTempPath()
) ("it140-bootstrap-{0}" -f ([guid]::NewGuid().ToString("N")))
$ArchivePath = Join-Path $TemporaryRoot "it140-main.zip"
$ExtractRoot = Join-Path $TemporaryRoot "extract"
$PlatformScriptDirectory = Join-Path $CourseRoot "scripts\$PlatformAbbreviation"

Write-Host ""
Write-Host "============================================================"
Write-Host "IT 140 WINDOWS BOOTSTRAP"
Write-Host "============================================================"
Write-Host "[INFO] Artifact version : $ArtifactVersion"
Write-Host "[INFO] Version date     : $VersionDate"
Write-Host "[INFO] Status           : $DevelopmentStatus"
Write-Host "[INFO] Current user     : $([Environment]::UserName)"
Write-Host "[INFO] Purpose          : Retrieve the IT 140 automation package"
Write-Host "[INFO] Log file         : $LogPath"

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
    [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")

    $CurrentEntries = @(
        $env:Path -split ";" |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $CurrentContainsTarget = $false
    foreach ($Entry in $CurrentEntries) {
        if ((Get-NormalizedPathEntry -PathEntry $Entry) -ieq $NormalizedTarget) {
            $CurrentContainsTarget = $true
            break
        }
    }
    if (-not $CurrentContainsTarget) {
        $env:Path = "$PathEntry;$env:Path"
    }
}

try {
    New-Item -ItemType Directory -Path $CourseRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $TemporaryRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $ExtractRoot -Force | Out-Null

    if ($null -ne (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        $PartialPath = "$ArchivePath.part"
        & curl.exe `
            --location `
            --fail `
            --show-error `
            --retry 5 `
            --retry-delay 5 `
            --retry-all-errors `
            --continue-at - `
            --output $PartialPath `
            $RepositoryArchive
        if ($LASTEXITCODE -ne 0) {
            throw "The IT 140 course package could not be downloaded."
        }
        Move-Item -LiteralPath $PartialPath -Destination $ArchivePath -Force
    }
    else {
        Invoke-WebRequest -Uri $RepositoryArchive -OutFile $ArchivePath -UseBasicParsing
    }

    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $ExtractRoot -Force
    $DownloadedRoot = Get-ChildItem -LiteralPath $ExtractRoot -Directory |
        Select-Object -First 1
    if ($null -eq $DownloadedRoot) {
        throw "The downloaded IT 140 course package is not valid."
    }

    Get-ChildItem -LiteralPath $DownloadedRoot.FullName -Force |
        Copy-Item -Destination $CourseRoot -Recurse -Force

    Remove-Item -LiteralPath (Join-Path $CourseRoot ".git") -Recurse -Force `
        -ErrorAction SilentlyContinue

    if (-not (Test-Path -LiteralPath $PlatformScriptDirectory -PathType Container)) {
        throw "The downloaded package does not contain the Windows scripts."
    }

    Set-UserPathEntry -PathEntry $PlatformScriptDirectory

    Write-Host "[SUCCESS] The current IT 140 course package is available at:"
    Write-Host "[SUCCESS] $CourseRoot"
    Write-Host (
        "[NOTICE] The Windows lifecycle scripts are now available in this " +
        "PowerShell session."
    )
    Write-Host (
        "[NOTICE] Next step: open an elevated Windows PowerShell terminal " +
        "and run install_it140.ps1."
    )
    Write-Host "[NOTICE] Bootstrap log: $LogPath"
}
finally {
    Remove-Item -LiteralPath $TemporaryRoot -Recurse -Force `
        -ErrorAction SilentlyContinue
}

Stop-Transcript
