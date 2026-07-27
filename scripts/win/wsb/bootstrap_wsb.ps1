# IT 140 Windows Sandbox bootstrap command set
#
# Repository path:
#   scripts/win/wsb/bootstrap_wsb.ps1
#
# Purpose:
#   Prepare a Windows Sandbox (WSB) environment to run the IT 140 lifecycle
#   scripts. This script is intended to be run from a fresh Windows Sandbox
#   session. After running this script, run the following Windows lifecycle
#   scripts to complete the setup:
#      1. scripts/win/bootstrap_win.ps1
#      2. scripts/win/setup_win.ps1
#      3. scripts/win/config_win.ps1
#      4. scripts/win/verify_win.ps1
#      5. scripts/win/update_win.ps1
#
# Artifact version:
#   2026.07.27.2
#
# This file models the commands testers copy and run before setup. It is not a
# managed lifecycle script and therefore does not create a transcript or accept
# command-line options. Copy the commands below and paste them into a Windows
# Sandbox Administrator PowerShell session to bootstrap the WSB.

$LogDir = Join-Path $env:USERPROFILE 'it140\logs'; New-Item -ItemType Directory -Path $LogDir -Force | Out-Null; Start-Transcript -Path (Join-Path $LogDir "setup_win_$(Get-Date -Format 'yyyyMMdd_HHmmss').log") -Force
try {
$ErrorActionPreference = 'Stop'
$TempDir = Join-Path $env:TEMP 'winget-install'
$DependenciesZip = Join-Path $TempDir 'DesktopAppInstaller_Dependencies.zip'
$WingetBundle = Join-Path $TempDir 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
$DependenciesDir = Join-Path $TempDir 'Dependencies'
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
Write-Host "Downloading WinGet dependencies and installer..."
if (!(Test-Path $DependenciesZip)) {
curl.exe --location --fail --show-error --retry 10 --retry-delay 5 --retry-all-errors --continue-at - --output "$DependenciesZip.part" 'https://github.com/microsoft/winget-cli/releases/latest/download/DesktopAppInstaller_Dependencies.zip'
if ($LASTEXITCODE -ne 0) { throw "WinGet dependencies download failed with curl exit code $LASTEXITCODE." }
Move-Item "$DependenciesZip.part" $DependenciesZip -Force
}
if (!(Test-Path $WingetBundle)) {
curl.exe --location --fail --show-error --retry 10 --retry-delay 5 --retry-all-errors --continue-at - --output "$WingetBundle.part" 'https://github.com/microsoft/winget-cli/releases/latest/download/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
if ($LASTEXITCODE -ne 0) { throw "WinGet download failed with curl exit code $LASTEXITCODE." }
Move-Item "$WingetBundle.part" $WingetBundle -Force
}
if (Test-Path $DependenciesDir) { Remove-Item $DependenciesDir -Recurse -Force }
Write-Host "Installing WinGet dependencies and installer..."
Expand-Archive -Path $DependenciesZip -DestinationPath $DependenciesDir -Force
Get-ChildItem -Path $DependenciesDir -Recurse -File | Where-Object { $_.Extension -in '.appx','.msix' -and $_.FullName -match '(?i)x64' } | ForEach-Object { Add-AppxPackage -Path $_.FullName }
Add-AppxPackage -Path $WingetBundle
Write-Host "Installing Microsoft Edit..."
$WinGetPath = Join-Path (Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction Stop).InstallLocation 'winget.exe'
$EditPath = Get-Command edit.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
if ([string]::IsNullOrWhiteSpace($EditPath)) {
& $WinGetPath install --id Microsoft.Edit --exact --source winget --scope user --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
if ($LASTEXITCODE -ne 0) { throw "Microsoft Edit installation failed with WinGet exit code $LASTEXITCODE." }
$EditPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\edit.exe'
if (!(Test-Path $EditPath)) {
$EditPath = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages') -Filter 'edit.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}
}
if ([string]::IsNullOrWhiteSpace($EditPath) -or !(Test-Path $EditPath)) {
throw "Microsoft Edit was installed, but edit.exe could not be located."
}
Write-Host "Associating .log files with Microsoft Edit..."
$LogFileClass = 'IT140.LogFile'
New-Item -Path 'HKCU:\Software\Classes\.log' -Force | Out-Null
Set-Item -Path 'HKCU:\Software\Classes\.log' -Value $LogFileClass
New-Item -Path "HKCU:\Software\Classes\$LogFileClass" -Force | Out-Null
Set-Item -Path "HKCU:\Software\Classes\$LogFileClass" -Value 'IT 140 log file'
New-Item -Path "HKCU:\Software\Classes\$LogFileClass\shell\open\command" -Force | Out-Null
Set-Item -Path "HKCU:\Software\Classes\$LogFileClass\shell\open\command" -Value "`"$EditPath`" `"%1`""
}
catch {
Remove-Item "$DependenciesZip.part","$WingetBundle.part" -Force -ErrorAction SilentlyContinue
Write-Error "Windows Sandbox bootstrap failed: $($_.Exception.Message)" -ErrorAction Continue
}
Stop-Transcript
