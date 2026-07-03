$ErrorActionPreference = "Stop"

$RootDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("codex-no-tun-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

try {
  $config = Join-Path $Tmp "config.toml"
  @"
[proxy]
http_proxy = "http://127.0.0.1:9"
https_proxy = "http://127.0.0.1:9"

[projects.'c:\broken]
trust_level = "trusted"
"@ | Set-Content -LiteralPath $config -Encoding UTF8

  $env:CODEX_PROXY_DRY_RUN = "1"
  $env:CODEX_PROXY_STATE_DIR = $Tmp
  $env:CODEX_CONFIG_PATH = $config
  $env:LOCALAPPDATA = $Tmp
  $env:USERPROFILE = $Tmp
  $env:CODEX_PACKAGE_FAMILY_NAME = "OpenAI.Codex_test"

  & (Join-Path $RootDir "bin\codex-proxy.ps1") enable | Out-Null
  $text = Get-Content -LiteralPath $config -Raw
  if ($text -notmatch '\[network_proxy\]') { throw "network_proxy block was not written" }
  if ($text -match '\[proxy\]') { throw "old proxy block was not removed" }
  if ($text -notmatch "proxy_url = `"http://127.0.0.1:10808`"") { throw "proxy_url was not written" }
  if ($text -notmatch "\[projects\.'c:\\broken'\]") { throw "common malformed project table was not repaired" }

  & (Join-Path $RootDir "bin\codex-proxy.ps1") restore | Out-Null
  $restored = Get-Content -LiteralPath $config -Raw
  if ($restored -notmatch '\[proxy\]') { throw "config backup was not restored" }

  Write-Host "All Windows tests passed."
}
finally {
  Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item Env:\CODEX_PROXY_DRY_RUN -ErrorAction SilentlyContinue
  Remove-Item Env:\CODEX_PROXY_STATE_DIR -ErrorAction SilentlyContinue
  Remove-Item Env:\CODEX_CONFIG_PATH -ErrorAction SilentlyContinue
  Remove-Item Env:\CODEX_PACKAGE_FAMILY_NAME -ErrorAction SilentlyContinue
}
