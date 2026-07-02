$ErrorActionPreference = "Stop"

$InstallDirectory = Join-Path $env:LOCALAPPDATA "codex-no-tun"
$Source = Join-Path $PSScriptRoot "codex-proxy.ps1"
$Destination = Join-Path $InstallDirectory "codex-proxy.ps1"

New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
Copy-Item -Path $Source -Destination $Destination -Force

Write-Output "Installed: $Destination"
Write-Output "Example: powershell -NoProfile -ExecutionPolicy Bypass -File `"$Destination`" doctor"
