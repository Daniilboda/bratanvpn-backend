# Copies AmneziaWG binaries into this sidecar folder for Flutter Windows builds.
# Run once after installing AmneziaWG MSI, or when updating AmneziaWG.
#
# Usage (PowerShell):
#   cd apps\client\windows\amneziawg
#   .\sync_from_install.ps1

$ErrorActionPreference = 'Stop'

$dest = $PSScriptRoot
$candidates = @(
    "${env:ProgramFiles}\AmneziaWG",
    "${env:ProgramFiles(x86)}\AmneziaWG"
)

$src = $candidates | Where-Object { Test-Path (Join-Path $_ 'amneziawg.exe') } | Select-Object -First 1
if (-not $src) {
    Write-Error @"
AmneziaWG not found under Program Files.
Install amneziawg-amd64-*.msi from:
https://github.com/amnezia-vpn/amneziawg-windows-client/releases
Then re-run this script.
"@
}

$files = @('amneziawg.exe', 'wintun.dll', 'awg.exe')
foreach ($name in $files) {
    $from = Join-Path $src $name
    if (-not (Test-Path $from)) {
        Write-Error "Missing required file: $from"
    }
    Copy-Item -Path $from -Destination (Join-Path $dest $name) -Force
    Write-Host "copied $name"
}

Write-Host "Sidecar ready: $dest"
Write-Host "Next: flutter run -d windows   OR   flutter build windows"
