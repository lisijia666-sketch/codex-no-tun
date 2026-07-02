[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("doctor", "status", "enable", "restore", "help")]
    [string]$Command = "help",

    [string]$ProxyHost = $(if ($env:PROXY_HOST) { $env:PROXY_HOST } else { "127.0.0.1" }),

    [int]$ProxyPort = $(if ($env:PROXY_PORT) { [int]$env:PROXY_PORT } else { 10808 })
)

$ErrorActionPreference = "Stop"
$RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$StateDirectory = Join-Path $env:LOCALAPPDATA "codex-no-tun"
$StateFile = Join-Path $StateDirectory "system-proxy-backup.json"

function Fail([string]$Message) {
    Write-Error $Message
    exit 1
}

function Assert-ProxySettings {
    if ($ProxyPort -lt 1 -or $ProxyPort -gt 65535) {
        Fail "ProxyPort must be between 1 and 65535."
    }

    if ($ProxyHost -notin @("127.0.0.1", "localhost") -and $env:ALLOW_REMOTE_PROXY -ne "1") {
        Fail "Refusing a non-loopback proxy. Set ALLOW_REMOTE_PROXY=1 only if you trust it."
    }
}

function Get-InternetSettings {
    Get-ItemProperty -Path $RegistryPath
}

function Has-Property($Settings, [string]$Name) {
    return $null -ne $Settings.PSObject.Properties[$Name]
}

function Set-RegistryValue([string]$Name, $Value, [string]$Type) {
    $settings = Get-InternetSettings
    if (Has-Property $settings $Name) {
        Set-ItemProperty -Path $RegistryPath -Name $Name -Value $Value
    }
    else {
        New-ItemProperty -Path $RegistryPath -Name $Name -PropertyType $Type -Value $Value | Out-Null
    }
}

function Save-CurrentSettings {
    if (Test-Path $StateFile) {
        return
    }

    $settings = Get-InternetSettings
    $state = [ordered]@{
        HasProxyEnable   = Has-Property $settings "ProxyEnable"
        ProxyEnable      = if (Has-Property $settings "ProxyEnable") { [int]$settings.ProxyEnable } else { 0 }
        HasProxyServer   = Has-Property $settings "ProxyServer"
        ProxyServer      = if (Has-Property $settings "ProxyServer") { [string]$settings.ProxyServer } else { "" }
        HasProxyOverride = Has-Property $settings "ProxyOverride"
        ProxyOverride    = if (Has-Property $settings "ProxyOverride") { [string]$settings.ProxyOverride } else { "" }
    }

    New-Item -ItemType Directory -Path $StateDirectory -Force | Out-Null
    $state | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8
}

function Notify-SystemProxyChanged {
    if (-not ("Native.WinInet" -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
namespace Native {
    public static class WinInet {
        [DllImport("wininet.dll", SetLastError = true)]
        public static extern bool InternetSetOption(IntPtr hInternet, int option, IntPtr buffer, int bufferLength);
    }
}
"@
    }

    [void][Native.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)
    [void][Native.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)
}

function Test-LocalProxy {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $result = $client.BeginConnect($ProxyHost, $ProxyPort, $null, $null)
        if (-not $result.AsyncWaitHandle.WaitOne(3000)) {
            return $false
        }
        $client.EndConnect($result)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Test-OpenAIThroughProxy {
    try {
        $request = [System.Net.WebRequest]::Create("https://developers.openai.com/")
        $request.Method = "HEAD"
        $request.Timeout = 12000
        $request.Proxy = New-Object System.Net.WebProxy("http://${ProxyHost}:${ProxyPort}")
        $response = $request.GetResponse()
        $response.Close()
        return $true
    }
    catch {
        return $false
    }
}

function Show-Status {
    $settings = Get-InternetSettings
    $enabled = if ((Has-Property $settings "ProxyEnable") -and $settings.ProxyEnable -eq 1) { "Yes" } else { "No" }
    $server = if (Has-Property $settings "ProxyServer") { $settings.ProxyServer } else { "-" }
    $override = if (Has-Property $settings "ProxyOverride") { $settings.ProxyOverride } else { "-" }
    Write-Output "System proxy enabled: $enabled"
    Write-Output "Proxy server: $server"
    Write-Output "Proxy bypass: $override"
    Write-Output "Expected local proxy: http://${ProxyHost}:${ProxyPort}"
}

function Enable-SystemProxy {
    if (-not (Test-LocalProxy)) {
        Fail "Nothing is listening at ${ProxyHost}:${ProxyPort}. Start your proxy client first."
    }

    Save-CurrentSettings
    Set-RegistryValue "ProxyServer" "${ProxyHost}:${ProxyPort}" "String"
    Set-RegistryValue "ProxyOverride" "<local>;localhost;127.*;::1" "String"
    Set-RegistryValue "ProxyEnable" 1 "DWord"
    Notify-SystemProxyChanged

    Write-Output "Enabled the Windows system proxy: http://${ProxyHost}:${ProxyPort}"
    Write-Output "Original settings saved to: $StateFile"
    Write-Output "Quit Codex completely, then open it normally from Start or the taskbar."
}

function Restore-Property([string]$Name, [bool]$Exists, $Value, [string]$Type) {
    if ($Exists) {
        Set-RegistryValue $Name $Value $Type
    }
    else {
        Remove-ItemProperty -Path $RegistryPath -Name $Name -ErrorAction SilentlyContinue
    }
}

function Restore-SystemProxy {
    if (-not (Test-Path $StateFile)) {
        Fail "No backup exists at $StateFile; nothing was changed."
    }

    $state = Get-Content -Raw -Path $StateFile | ConvertFrom-Json
    Restore-Property "ProxyServer" ([bool]$state.HasProxyServer) ([string]$state.ProxyServer) "String"
    Restore-Property "ProxyOverride" ([bool]$state.HasProxyOverride) ([string]$state.ProxyOverride) "String"
    Restore-Property "ProxyEnable" ([bool]$state.HasProxyEnable) ([int]$state.ProxyEnable) "DWord"
    Notify-SystemProxyChanged
    Remove-Item -Path $StateFile -Force
    Write-Output "Restored the original Windows system proxy settings."
}

function Invoke-Doctor {
    if (Test-LocalProxy) {
        Write-Output "[ok] Local proxy is listening at ${ProxyHost}:${ProxyPort}"
    }
    else {
        Fail "Nothing is listening at ${ProxyHost}:${ProxyPort}. Start your proxy client first."
    }

    if (Test-OpenAIThroughProxy) {
        Write-Output "[ok] OpenAI is reachable through the local proxy"
    }
    else {
        Fail "The local proxy is running, but OpenAI is not reachable through it."
    }

    Show-Status
}

function Show-Help {
    @"
Usage: .\codex-proxy.ps1 <command> [-ProxyHost 127.0.0.1] [-ProxyPort 10808]

Commands:
  doctor    Check the local proxy and OpenAI connectivity
  status    Show the current Windows system proxy settings
  enable    Back up current settings and enable the local system proxy
  restore   Restore the settings saved by enable
"@
}

Assert-ProxySettings
switch ($Command) {
    "doctor"  { Invoke-Doctor }
    "status"  { Show-Status }
    "enable"  { Enable-SystemProxy }
    "restore" { Restore-SystemProxy }
    default   { Show-Help }
}
