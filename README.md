# codex-no-tun

让 Codex 在不开启 TUN 的情况下，通过本地 HTTP 代理稳定连接。支持 macOS 和 Windows。

适合这样的情况：

- 本地代理客户端已经运行；
- 开启 TUN 后 Codex 正常，但关闭 TUN 会反复显示 `reconnecting`；
- 希望以后直接从 Dock、Finder、开始菜单或桌面图标打开 Codex，不依赖终端启动参数。

> 这个工具不会修改 Codex 程序本体，也不会绕过账号、地区或组织策略。它只配置本机代理、Codex 的本地配置，以及 Windows 上 Codex 访问 `127.0.0.1` 所需的 loopback 豁免。

## 工作原理

Codex 桌面端包含 Electron 与后台服务，它们不一定会自动读取项目里的 `.env` 或当前终端环境变量。

macOS 版本会：

1. 检测当前默认网络服务，例如 Wi-Fi；
2. 检查本地代理端口是否正在监听；
3. 备份现有 HTTP/HTTPS 代理设置；
4. 将系统 HTTP/HTTPS 代理指向本地回环地址；
5. 在需要时恢复原设置。

Windows 版本会：

1. 检查本地代理端口是否正在监听；
2. 备份当前 Windows 用户代理、用户环境变量和 Codex 配置；
3. 设置 Windows 当前用户系统代理；
4. 设置用户级 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY`；
5. 给 Microsoft Store/MSIX 版 Codex 添加 loopback 豁免，让它能访问 `127.0.0.1`；
6. 写入当前 Codex 版本识别的 `[network_proxy]` 配置；
7. 在需要时恢复原设置。

默认代理为 `http://127.0.0.1:10808`，适用于许多 v2rayN/Xray 配置。其他客户端请按实际端口调整。

## macOS 快速开始

要求：macOS、Bash、一个正在运行的本地 HTTP 代理。

```bash
git clone https://github.com/lisijia666-sketch/codex-no-tun.git
cd codex-no-tun
./install.sh
```

先检查代理：

```bash
~/.local/bin/codex-proxy doctor
```

启用系统代理：

```bash
~/.local/bin/codex-proxy enable
```

然后完全退出 Codex，再从 Dock 或 Finder 正常打开。

恢复原设置：

```bash
~/.local/bin/codex-proxy restore
```

## Windows 快速开始

要求：Windows、PowerShell、一个正在运行的本地 HTTP 代理。

```powershell
git clone https://github.com/lisijia666-sketch/codex-no-tun.git
cd codex-no-tun
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

先检查代理：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\codex-no-tun\codex-proxy.ps1" doctor
```

启用修复：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\codex-no-tun\codex-proxy.ps1" enable
```

然后完全退出 Codex，再从开始菜单或桌面图标重新打开。

恢复原设置：

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\codex-no-tun\codex-proxy.ps1" restore
```

如果你把安装目录加入 PATH，也可以直接运行：

```powershell
codex-proxy doctor
codex-proxy enable
codex-proxy restore
```

## 自定义端口

macOS 示例：

```bash
PROXY_PORT=7897 ~/.local/bin/codex-proxy enable
```

Windows 示例：

```powershell
$env:PROXY_PORT = "7897"
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\codex-no-tun\codex-proxy.ps1" enable
```

如果要使用非本机代理，需要显式允许：

```bash
ALLOW_REMOTE_PROXY=1 PROXY_HOST=192.168.1.10 ~/.local/bin/codex-proxy enable
```

```powershell
$env:ALLOW_REMOTE_PROXY = "1"
$env:PROXY_HOST = "192.168.1.10"
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\codex-no-tun\codex-proxy.ps1" enable
```

## 可用命令

```text
doctor   检查本地代理和 Codex 连接条件
status   查看当前代理状态
enable   备份原配置并启用本地代理
restore  恢复 enable 之前的配置
launch   检查连通性后打开 Codex
```

## 常见问题

### 本地端口不存在

先启动代理客户端，确认其提供的是 HTTP 代理，并核对端口。SOCKS-only 端口不能直接作为 HTTP 系统代理使用。

### Windows 启用后 Codex 仍在重连

1. 完全退出 Codex，包括托盘里的 Codex；
2. 重新打开 Codex；
3. 运行 `codex-proxy doctor`；
4. 如果提示 `Cloudflare challenge` 或 `403`，说明代理节点能连上但出口被挑战，换一个节点；
5. 确认 `C:\Users\<你>\.codex\config.toml` 里存在 `[network_proxy]`。

### macOS 启用后 Codex 仍在重连

1. 完全退出 Codex，使用 `Cmd+Q`；
2. 运行 `codex-proxy doctor`；
3. 检查代理节点是否支持 HTTPS 与长连接；
4. 查看 Codex 日志中是否有 `ERR_PROXY_CONNECTION_FAILED`。

### 切换了 Wi-Fi 或有线网络

macOS 系统代理按网络服务保存。先执行 `restore`，切换网络后再次执行 `enable`；也可以通过 `NETWORK_SERVICE` 指定服务。

## 安全设计

- 默认只允许 `127.0.0.1` 或 `localhost`，避免意外使用不可信远程代理；
- 第一次执行 `enable` 时备份现有代理设置；
- `restore` 只恢复本工具保存的设置；
- 不读取或保存 GitHub、OpenAI、Codex 的令牌。

## 开发与测试

macOS/Linux shell 测试：

```bash
bash -n bin/codex-proxy install.sh tests/test.sh
./tests/test.sh
```

Windows PowerShell 测试：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\test-windows.ps1
```

测试使用 mock 或 dry-run，不会修改真实系统代理。

## License

[MIT](LICENSE)
