param(
  [Parameter(Position = 0)]
  [ValidateSet("doctor", "status", "enable", "restore", "launch", "help")]
  [string] $Command = "help"
)

$ErrorActionPreference = "Stop"

$ProxyHost = if ($env:PROXY_HOST) { $env:PROXY_HOST } else { "127.0.0.1" }
$ProxyPort = if ($env:PROXY_PORT) { [int] $env:PROXY_PORT } else { 10808 }
$AllowRemoteProxy = $env:ALLOW_REMOTE_PROXY -eq "1"
$DryRun = $env:CODEX_PROXY_DRY_RUN -eq "1"

$StateDir = if ($env:CODEX_PROXY_STATE_DIR) {
  $env:CODEX_PROXY_STATE_DIR
} else {
  Join-Path $env:LOCALAPPDATA "codex-no-tun"
}
$StateFile = Join-Path $StateDir "windows-state.json"
$ConfigPath = if ($env:CODEX_CONFIG_PATH) {
  $env:CODEX_CONFIG_PATH
} else {
  Join-Path $env:USERPROFILE ".codex\config.toml"
}

function Write-Info {
  param([string] $Message)
  Write-Host $Message
}

function Fail {
  param([string] $Message)
  throw $Message
}

function Validate-Proxy {
  if ($ProxyPort -lt 1 -or $ProxyPort -gt 65535) {
    Fail "PROXY_PORT must be between 1 and 65535."
  }

  if (($ProxyHost -ne "127.0.0.1") -and ($ProxyHost -ne "localhost") -and -not $AllowRemoteProxy) {
    Fail "Refusing a non-loopback proxy. Set ALLOW_REMOTE_PROXY=1 only if you trust it."
  }
}

function Test-ProxyPort {
  if ($DryRun) { return $true }
  $result = Test-NetConnection -ComputerName $ProxyHost -Port $ProxyPort -WarningAction SilentlyContinue
  return [bool] $result.TcpTestSucceeded
}

function Get-CodexPackageFamilyName {
  if ($env:CODEX_PACKAGE_FAMILY_NAME) { return $env:CODEX_PACKAGE_FAMILY_NAME }
  $pkg = Get-AppxPackage OpenAI.Codex -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($pkg) { return $pkg.PackageFamilyName }
  return $null
}

function Get-LoopbackExemptNames {
  if ($DryRun) { return @() }
  $output = & CheckNetIsolation.exe LoopbackExempt -s 2>$null
  @($output | Where-Object { $_ -match '^\s*Name:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim().ToLowerInvariant() })
}

function Get-ProxyRegistryState {
  $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
  $value = Get-ItemProperty -Path $key
  [pscustomobject]@{
    ProxyEnable = [int]($value.ProxyEnable)
    ProxyServer = [string]($value.ProxyServer)
    ProxyOverride = [string]($value.ProxyOverride)
    AutoConfigURL = [string]($value.AutoConfigURL)
  }
}

function Get-UserEnvState {
  $names = @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "GIT_HTTP_PROXY", "GIT_HTTPS_PROXY")
  $state = @{}
  foreach ($name in $names) {
    $state[$name] = [Environment]::GetEnvironmentVariable($name, "User")
  }
  $state
}

function Save-State {
  param([string] $PackageFamilyName, [bool] $LoopbackWasPresent)

  if (Test-Path $StateFile) { return }

  New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
  $configBackup = $null
  if (Test-Path $ConfigPath) {
    $configBackup = Join-Path $StateDir "config.toml.backup"
    Copy-Item -LiteralPath $ConfigPath -Destination $configBackup -Force
  }

  $state = [pscustomobject]@{
    CreatedAt = (Get-Date).ToString("o")
    ProxyRegistry = Get-ProxyRegistryState
    UserEnvironment = Get-UserEnvState
    PackageFamilyName = $PackageFamilyName
    LoopbackWasPresent = $LoopbackWasPresent
    ConfigPath = $ConfigPath
    ConfigBackup = $configBackup
  }

  $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function Set-SystemProxy {
  if ($DryRun) { return }
  $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
  $proxy = "${ProxyHost}:${ProxyPort}"
  Set-ItemProperty -Path $key -Name ProxyEnable -Value 1
  Set-ItemProperty -Path $key -Name ProxyServer -Value $proxy
  Set-ItemProperty -Path $key -Name ProxyOverride -Value "localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>"
}

function Set-UserProxyEnvironment {
  if ($DryRun) { return }
  $proxyUrl = "http://${ProxyHost}:${ProxyPort}"
  [Environment]::SetEnvironmentVariable("HTTP_PROXY", $proxyUrl, "User")
  [Environment]::SetEnvironmentVariable("HTTPS_PROXY", $proxyUrl, "User")
  [Environment]::SetEnvironmentVariable("ALL_PROXY", $proxyUrl, "User")
  [Environment]::SetEnvironmentVariable("NO_PROXY", "127.0.0.1,localhost,::1", "User")
  [Environment]::SetEnvironmentVariable("GIT_HTTP_PROXY", $proxyUrl, "User")
  [Environment]::SetEnvironmentVariable("GIT_HTTPS_PROXY", $proxyUrl, "User")
}

function Enable-CodexLoopback {
  param([string] $PackageFamilyName, [bool] $LoopbackWasPresent)
  if (-not $PackageFamilyName) {
    Write-Info "[warn] OpenAI.Codex package was not found; skipping loopback exemption."
    return
  }
  if ($LoopbackWasPresent) { return }
  if ($DryRun) { return }
  & CheckNetIsolation.exe LoopbackExempt -a -n="$PackageFamilyName" | Out-Null
}

function Remove-TomlTable {
  param([string] $Text, [string] $TableName)
  $escaped = [regex]::Escape($TableName)
  [regex]::Replace($Text, "(?ms)^\[$escaped\]\s*.*?(?=^\[|\z)", "")
}

function Repair-CommonTomlDamage {
  param([string[]] $Lines)
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    $line = $Lines[$i]
    if ($line.StartsWith("[projects.'") -and $line.EndsWith("]") -and -not $line.EndsWith("']")) {
      $Lines[$i] = $line.TrimEnd("]") + "']"
    }
  }
  $Lines
}

function Set-CodexNetworkProxyConfig {
  if (-not (Test-Path $ConfigPath)) {
    $dir = Split-Path -Parent $ConfigPath
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    "" | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
  }

  $lines = Get-Content -LiteralPath $ConfigPath
  $text = (Repair-CommonTomlDamage -Lines $lines) -join "`r`n"
  $text = Remove-TomlTable -Text $text -TableName "proxy"
  $text = Remove-TomlTable -Text $text -TableName "network_proxy"
  $block = "[network_proxy]`r`nenabled = true`r`nproxy_url = `"http://${ProxyHost}:${ProxyPort}`"`r`n`r`n"
  Set-Content -LiteralPath $ConfigPath -Value ($block + $text.TrimStart()) -Encoding UTF8
}

function Restore-SystemProxy {
  param($State)
  if ($DryRun) { return }
  $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
  Set-ItemProperty -Path $key -Name ProxyEnable -Value ([int]$State.ProxyRegistry.ProxyEnable)
  Set-ItemProperty -Path $key -Name ProxyServer -Value ([string]$State.ProxyRegistry.ProxyServer)
  Set-ItemProperty -Path $key -Name ProxyOverride -Value ([string]$State.ProxyRegistry.ProxyOverride)
  if ($State.ProxyRegistry.AutoConfigURL) {
    Set-ItemProperty -Path $key -Name AutoConfigURL -Value ([string]$State.ProxyRegistry.AutoConfigURL)
  } else {
    Remove-ItemProperty -Path $key -Name AutoConfigURL -ErrorAction SilentlyContinue
  }
}

function Restore-UserProxyEnvironment {
  param($State)
  if ($DryRun) { return }
  foreach ($property in $State.UserEnvironment.PSObject.Properties) {
    [Environment]::SetEnvironmentVariable($property.Name, $property.Value, "User")
  }
}

function Restore-CodexConfig {
  param($State)
  if ($State.ConfigBackup -and (Test-Path $State.ConfigBackup)) {
    Copy-Item -LiteralPath $State.ConfigBackup -Destination $State.ConfigPath -Force
  }
}

function Restore-CodexLoopback {
  param($State)
  if ($State.PackageFamilyName -and -not $State.LoopbackWasPresent -and -not $DryRun) {
    & CheckNetIsolation.exe LoopbackExempt -d -n="$($State.PackageFamilyName)" | Out-Null
  }
}

function Command-Status {
  $reg = Get-ProxyRegistryState
  Write-Info "Windows system proxy: enabled=$($reg.ProxyEnable) server=$($reg.ProxyServer)"
  Write-Info "Expected local proxy: http://${ProxyHost}:${ProxyPort}"
  $package = Get-CodexPackageFamilyName
  if ($package) {
    $hasLoopback = (Get-LoopbackExemptNames) -contains $package.ToLowerInvariant()
    Write-Info "Codex package: $package loopbackExempt=$hasLoopback"
  } else {
    Write-Info "Codex package: not found"
  }
  Write-Info "Codex config: $ConfigPath"
}

function Command-Doctor {
  if (Test-ProxyPort) {
    Write-Info "[ok] Local proxy is listening at ${ProxyHost}:${ProxyPort}"
  } else {
    Fail "Nothing is listening at ${ProxyHost}:${ProxyPort}. Start your proxy client first."
  }

  $proxyUrl = "http://${ProxyHost}:${ProxyPort}"
  if (-not $DryRun) {
    $result = & curl.exe -I --max-time 15 --proxy $proxyUrl https://chatgpt.com/backend-api/ 2>&1
    $joined = $result -join "`n"
    if ($LASTEXITCODE -eq 0 -and $joined -match "HTTP/1\.1 200 Connection established") {
      Write-Info "[ok] HTTPS can tunnel through the local proxy"
      if ($joined -match "Cf-Mitigated:\s*challenge") {
        Write-Info "[warn] chatgpt.com returned a Cloudflare challenge. Change proxy node if Codex still reconnects."
      }
    } else {
      Fail "The local proxy is running, but HTTPS tunneling failed through it."
    }
  }

  Command-Status
}

function Command-Enable {
  if (-not (Test-ProxyPort)) {
    Fail "Nothing is listening at ${ProxyHost}:${ProxyPort}. Start your proxy client first."
  }

  $package = Get-CodexPackageFamilyName
  $loopbackWasPresent = $false
  if ($package) {
    $loopbackWasPresent = (Get-LoopbackExemptNames) -contains $package.ToLowerInvariant()
  }

  Save-State -PackageFamilyName $package -LoopbackWasPresent $loopbackWasPresent
  Set-SystemProxy
  Set-UserProxyEnvironment
  Enable-CodexLoopback -PackageFamilyName $package -LoopbackWasPresent $loopbackWasPresent
  Set-CodexNetworkProxyConfig

  Write-Info "Enabled Windows system proxy and Codex network_proxy."
  Write-Info "Proxy: http://${ProxyHost}:${ProxyPort}"
  Write-Info "Backup: $StateFile"
  Write-Info "Quit Codex completely, then open it again."
}

function Command-Restore {
  if (-not (Test-Path $StateFile)) {
    Fail "No backup exists at $StateFile; nothing was changed."
  }
  $state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
  Restore-SystemProxy -State $state
  Restore-UserProxyEnvironment -State $state
  Restore-CodexConfig -State $state
  Restore-CodexLoopback -State $state
  Remove-Item -LiteralPath $StateFile -Force
  Write-Info "Restored previous Windows proxy and Codex settings."
}

function Command-Launch {
  Command-Doctor
  Start-Process "codex:"
}

function Command-Help {
  @"
Usage: .\codex-proxy.ps1 <command>

Commands:
  doctor    Check the local proxy, Codex package, and ChatGPT tunnel
  status    Show current Windows proxy and Codex status
  enable    Back up current settings and enable Codex through local proxy
  restore   Restore settings saved by enable
  launch    Run doctor, then open Codex

Environment overrides:
  PROXY_HOST=127.0.0.1
  PROXY_PORT=10808
  ALLOW_REMOTE_PROXY=1
"@ | Write-Host
}

Validate-Proxy

switch ($Command) {
  "doctor" { Command-Doctor }
  "status" { Command-Status }
  "enable" { Command-Enable }
  "restore" { Command-Restore }
  "launch" { Command-Launch }
  default { Command-Help }
}
