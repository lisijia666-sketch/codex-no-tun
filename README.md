# codex-macos-no-tun

让 macOS 上的 Codex 在**不开启 TUN**的情况下，通过本地 HTTP 系统代理稳定连接。

它适合这样的情况：

- 本地代理客户端已经运行；
- 开启 TUN 后 Codex 正常，但关闭 TUN 会反复显示 `reconnecting`；
- 希望以后直接从 Dock 或 Finder 打开 Codex，不依赖终端启动参数。

> 这个工具不会修改 Codex，也不会绕过账号、地区或组织策略。它只配置 macOS 的 HTTP/HTTPS 系统代理。

## 工作原理

Codex 桌面端包含 Electron 与后台服务，它们不一定会自动读取项目里的 `.env`。macOS 系统代理对直接点击启动的 GUI 应用更可靠。

本工具会：

1. 检测当前默认网络服务（例如 Wi-Fi）；
2. 检查本地代理端口是否正在监听；
3. 备份现有 HTTP/HTTPS 代理设置；
4. 将系统代理指向本地回环地址；
5. 在需要时恢复原设置。

默认代理为 `http://127.0.0.1:10808`，适用于许多 v2rayN/Xray 配置。其他客户端请按实际端口调整。

## 快速开始

要求：macOS、Bash、一个正在运行的本地 HTTP 代理。

```bash
git clone https://github.com/lisijia666-sketch/codex-macos-no-tun.git
cd codex-macos-no-tun
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

然后完全退出 Codex，再从 Dock 或 Finder 正常打开。此后不需要用终端启动 Codex，但本地代理客户端仍需在后台运行。

恢复原设置：

```bash
~/.local/bin/codex-proxy restore
```

## 自定义端口或网络服务

例如本地 HTTP 代理监听 `7897`：

```bash
PROXY_PORT=7897 ~/.local/bin/codex-proxy enable
```

无法自动识别网络服务时：

```bash
NETWORK_SERVICE="Wi-Fi" ~/.local/bin/codex-proxy enable
```

可用命令：

```text
doctor   检查端口与 OpenAI 连通性
status   查看当前 HTTP/HTTPS 系统代理
enable   备份原配置并启用本地代理
restore  恢复 enable 之前的配置
launch   检查连通性后打开 Codex
```

## 安全设计

- 默认只允许 `127.0.0.1` 或 `localhost`，避免意外使用不可信远程代理；
- 第一次执行 `enable` 时备份现有代理设置；
- `restore` 只恢复本工具保存的设置；
- 不读取或保存 GitHub、OpenAI、Codex 的令牌。

如果确实需要可信的远程代理，可显式设置 `ALLOW_REMOTE_PROXY=1`。

## 常见问题

### 本地端口不存在

先启动代理客户端，确认其提供的是 **HTTP 代理**，并核对端口。SOCKS-only 端口不能直接作为 HTTP 系统代理使用。

### 启用后 Codex 仍在重连

1. 完全退出 Codex（`Cmd+Q`），再重新打开；
2. 运行 `codex-proxy doctor`；
3. 检查代理节点是否支持 HTTPS 与长连接；
4. 查看 Codex 日志中是否有 `ERR_PROXY_CONNECTION_FAILED`。

### 切换了 Wi-Fi 或有线网络

系统代理按网络服务保存。先执行 `restore`，切换网络后再次执行 `enable`；也可以通过 `NETWORK_SERVICE` 指定服务。

## 开发与测试

```bash
bash -n bin/codex-proxy install.sh tests/test.sh
./tests/test.sh
```

测试使用模拟的 `networksetup`，不会修改真实系统代理。

## License

[MIT](LICENSE)
