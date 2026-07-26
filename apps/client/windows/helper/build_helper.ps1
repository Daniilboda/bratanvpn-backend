# Builds bratanvpn_helper.exe (Go). Requires Go on PATH.
# Usage:
#   cd apps\client\windows\helper
#   .\build_helper.ps1

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    Write-Error 'Go is not installed or not on PATH. https://go.dev/dl/'
}

go mod tidy
go build -ldflags='-s -w' -o bratanvpn_helper.exe .
Write-Host "Built $(Join-Path $PSScriptRoot 'bratanvpn_helper.exe')"
