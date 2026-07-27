
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
}