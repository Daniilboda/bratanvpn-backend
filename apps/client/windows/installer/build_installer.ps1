#Requires -Version 5.1
<#
.SYNOPSIS
  Build BratanVPN Windows release + Inno Setup installer (.exe).

.EXAMPLE
  .\build_installer.ps1
  .\build_installer.ps1 -SkipFlutterBuild
  .\build_installer.ps1 -ApiBaseUrl "https://api.bratanvpn.com"
#>
[CmdletBinding()]
param(
  [string]$ApiBaseUrl = "https://api.bratanvpn.com",
  [switch]$SkipFlutterBuild,
  [switch]$SkipHelperBuild
)

$ErrorActionPreference = "Stop"

$InstallerDir = $PSScriptRoot
$ClientRoot = (Resolve-Path (Join-Path $InstallerDir "..\..")).Path
$HelperDir = Join-Path $ClientRoot "windows\helper"
$AmneziaDir = Join-Path $ClientRoot "windows\amneziawg"
$ReleaseDir = Join-Path $ClientRoot "build\windows\x64\runner\Release"
$IssPath = Join-Path $InstallerDir "bratanvpn.iss"
$OutDir = Join-Path $InstallerDir "output"

function Find-ISCC {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
  )
  foreach ($p in $candidates) {
    if ($p -and (Test-Path -LiteralPath $p)) {
      return $p
    }
  }
  $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }
  return $null
}

function Assert-File([string]$Path, [string]$Hint) {
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing required file: $Path`n$Hint"
  }
}

Write-Host "==> BratanVPN installer build" -ForegroundColor Cyan

$iscc = Find-ISCC
if (-not $iscc) {
  throw @"
Inno Setup 6 (ISCC.exe) not found.
Install from https://jrsoftware.org/isinfo.php or:
  winget install --id JRSoftware.InnoSetup -e
"@
}
Write-Host "ISCC: $iscc"

if (-not $SkipHelperBuild) {
  Write-Host "==> Building helper..." -ForegroundColor Cyan
  & (Join-Path $HelperDir "build_helper.ps1")
  if ($LASTEXITCODE -ne 0) {
    throw "build_helper.ps1 failed with exit $LASTEXITCODE"
  }
}

Assert-File (Join-Path $HelperDir "bratanvpn_helper.exe") `
  "Run apps\client\windows\helper\build_helper.ps1"
Assert-File (Join-Path $AmneziaDir "amneziawg.exe") `
  "Run apps\client\windows\amneziawg\sync_from_install.ps1"
Assert-File (Join-Path $AmneziaDir "wintun.dll") `
  "Run apps\client\windows\amneziawg\sync_from_install.ps1"

if (-not $SkipFlutterBuild) {
  Write-Host "==> flutter build windows --release..." -ForegroundColor Cyan
  Push-Location $ClientRoot
  try {
    flutter build windows --release --dart-define="API_BASE_URL=$ApiBaseUrl"
    if ($LASTEXITCODE -ne 0) {
      throw "flutter build failed with exit $LASTEXITCODE"
    }
  }
  finally {
    Pop-Location
  }
}

Assert-File (Join-Path $ReleaseDir "client.exe") `
  "Release build missing. Run without -SkipFlutterBuild."
Assert-File (Join-Path $ReleaseDir "bratanvpn_helper.exe") `
  "Helper was not copied into Release (CMake install). Rebuild Flutter."
Assert-File (Join-Path $ReleaseDir "amneziawg\amneziawg.exe") `
  "AmneziaWG sidecar missing in Release. Sync sidecar and rebuild."

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Write-Host "==> Compiling Inno Setup script..." -ForegroundColor Cyan
& $iscc $IssPath
if ($LASTEXITCODE -ne 0) {
  throw "ISCC failed with exit $LASTEXITCODE"
}

$setup = Get-ChildItem -LiteralPath $OutDir -Filter "BratanVPN-Setup-*.exe" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if (-not $setup) {
  throw "Installer .exe not found in $OutDir"
}

Write-Host ""
Write-Host "OK: $($setup.FullName)" -ForegroundColor Green
Write-Host ("Size: {0:N1} MB" -f ($setup.Length / 1MB))
