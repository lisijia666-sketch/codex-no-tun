$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = if ($env:INSTALL_DIR) {
  $env:INSTALL_DIR
} else {
  Join-Path $env:LOCALAPPDATA "Programs\codex-no-tun"
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item -LiteralPath (Join-Path $RootDir "bin\codex-proxy.ps1") -Destination (Join-Path $InstallDir "codex-proxy.ps1") -Force

$cmd = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-proxy.ps1" %*
"@
Set-Content -LiteralPath (Join-Path $InstallDir "codex-proxy.cmd") -Value $cmd -Encoding ASCII

Write-Host "Installed: $InstallDir\codex-proxy.ps1"
Write-Host "Run: powershell -ExecutionPolicy Bypass -File `"$InstallDir\codex-proxy.ps1`" doctor"
Write-Host "Optional: add $InstallDir to PATH to use codex-proxy.cmd"
