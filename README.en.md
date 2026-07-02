# codex-no-tun

English | [简体中文](README.md)

Use the Codex desktop app on macOS or Windows through a local HTTP system proxy, without enabling TUN mode or launching Codex from a terminal.

This project is useful when Codex works with TUN enabled but repeatedly shows `reconnecting` without it. The helper checks the local proxy, backs up the current system proxy settings, enables the loopback proxy, and can restore the original settings later.

> This tool does not modify Codex or bypass account, region, or organization policies. It only configures the current user's operating-system HTTP/HTTPS proxy.

The default proxy is `http://127.0.0.1:10808`. Your local proxy client must keep running.

## macOS

```bash
git clone https://github.com/lisijia666-sketch/codex-no-tun.git
cd codex-no-tun
./macos/install.sh

~/.local/bin/codex-proxy doctor
~/.local/bin/codex-proxy enable
```

Quit Codex completely, then open it normally from Dock or Finder. Restore the previous settings with:

```bash
~/.local/bin/codex-proxy restore
```

Use another port or network service when needed:

```bash
PROXY_PORT=7897 ~/.local/bin/codex-proxy enable
NETWORK_SERVICE="Wi-Fi" ~/.local/bin/codex-proxy enable
```

## Windows

Run in PowerShell:

```powershell
git clone https://github.com/lisijia666-sketch/codex-no-tun.git
cd codex-no-tun
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\install.ps1

$tool = "$env:LOCALAPPDATA\codex-no-tun\codex-proxy.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $tool doctor
powershell -NoProfile -ExecutionPolicy Bypass -File $tool enable
```

Quit Codex completely, then open it normally from Start or the taskbar. Restore the previous settings with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $tool restore
```

Use another port with `-ProxyPort 7897`.

The Windows helper changes only the current user's WinINet proxy settings under HKCU and does not require administrator privileges.

## Commands

| Command | Purpose |
| --- | --- |
| `doctor` | Check the local port and OpenAI connectivity |
| `status` | Show the current system proxy |
| `enable` | Back up the current settings and enable the local proxy |
| `restore` | Restore the settings saved by `enable` |

## Safety

- Loopback proxies only by default (`127.0.0.1` or `localhost`).
- Existing proxy settings are backed up before changes.
- Failed connectivity checks do not change system settings.
- No GitHub, OpenAI, or Codex tokens are read or stored.

Set `ALLOW_REMOTE_PROXY=1` only when you intentionally use a trusted remote proxy.

## License

[MIT](LICENSE)
