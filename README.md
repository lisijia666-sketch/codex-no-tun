# codex-no-tun

[English](README.en.md) | 简体中文

让 macOS 和 Windows 上的 Codex 在**不开启 TUN**的情况下，通过本地 HTTP 系统代理稳定连接。

适合以下情况：

- 本地代理客户端已经运行；
- 开启 TUN 后 Codex 正常，但关闭 TUN 会反复显示 `reconnecting`；
- 希望直接从 Dock、Finder、开始菜单或任务栏打开 Codex，不依赖特殊启动参数。

> 本工具不会修改 Codex，也不会绕过账号、地区或组织策略。它只配置操作系统当前用户的 HTTP/HTTPS 代理。

## 原理

Codex 桌面端包含 GUI 与后台服务，它们不一定会自动读取项目中的 `.env`。系统代理能覆盖直接点击启动的 GUI 应用，因此比终端环境变量更稳定。

工具会检查本地代理、备份原设置、启用系统代理，并支持一键恢复。默认代理为 `http://127.0.0.1:10808`，其他端口可自行指定。

## macOS

```bash
git clone https://github.com/lisijia666-sketch/codex-no-tun.git
cd codex-no-tun
./macos/install.sh
```

检查并启用：

```bash
~/.local/bin/codex-proxy doctor
~/.local/bin/codex-proxy enable
```

完全退出 Codex，然后从 Dock 或 Finder 正常打开。恢复原设置：

```bash
~/.local/bin/codex-proxy restore
```

自定义端口或网络服务：

```bash
PROXY_PORT=7897 ~/.local/bin/codex-proxy enable
NETWORK_SERVICE="Wi-Fi" ~/.local/bin/codex-proxy enable
```

## Windows

在 PowerShell 中执行：

```powershell
git clone https://github.com/lisijia666-sketch/codex-no-tun.git
cd codex-no-tun
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\install.ps1
```

检查并启用：

```powershell
$tool = "$env:LOCALAPPDATA\codex-no-tun\codex-proxy.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $tool doctor
powershell -NoProfile -ExecutionPolicy Bypass -File $tool enable
```

完全退出 Codex，然后从开始菜单或任务栏正常打开。恢复原设置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $tool restore
```

自定义端口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File $tool enable -ProxyPort 7897
```

Windows 脚本只修改当前用户的 WinINet 代理注册表项，不需要管理员权限，并会通知系统代理配置已经变化。

## 命令

| 命令 | 作用 |
| --- | --- |
| `doctor` | 检查本地端口与 OpenAI 连通性 |
| `status` | 查看当前系统代理 |
| `enable` | 备份原配置并启用本地代理 |
| `restore` | 恢复 `enable` 之前的配置 |

## 安全设计

- 默认只允许 `127.0.0.1` 或 `localhost`；
- 第一次执行 `enable` 时备份原有代理设置；
- `restore` 只恢复本工具保存的设置；
- 不读取或保存 GitHub、OpenAI、Codex 的令牌；
- 检测失败时不会修改系统代理。

如确实需要可信远程代理，可显式设置环境变量 `ALLOW_REMOTE_PROXY=1`。

## 常见问题

### 本地端口不存在

先启动代理客户端，确认其提供的是 **HTTP 代理**并核对端口。SOCKS-only 端口不能直接作为 HTTP 系统代理使用。

### 启用后仍然 reconnecting

1. 完全退出 Codex，再重新打开；
2. 运行 `doctor`；
3. 检查节点是否支持 HTTPS 与长连接；
4. 检查日志中是否有 `ERR_PROXY_CONNECTION_FAILED`。

### 代理客户端可以关闭吗？

不可以。TUN 可以关闭，但本地代理客户端仍需在后台运行。

## 开发与测试

macOS 测试使用模拟的 `networksetup`，不会修改真实系统代理：

```bash
bash -n macos/codex-proxy macos/install.sh tests/test-macos.sh
./tests/test-macos.sh
```

Windows 脚本以 Windows PowerShell 5.1 与 PowerShell 7 为兼容目标。建议首次使用时依次运行 `status`、`doctor`、`enable`、`restore` 验证环境。

## License

[MIT](LICENSE)
