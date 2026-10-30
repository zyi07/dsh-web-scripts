# Windows + WSL2 部署 DSH 教程

无需域名、无需公网 IP，本地浏览器直连即可使用。

## 0. 原理说明

```
Windows 浏览器  ──(localhost 转发)──>  WSL2 内 127.0.0.1:3080 (dsh 服务)
```

WSL2 自带 localhost 端口转发：WSL 内监听 `127.0.0.1` 的服务，Windows 浏览器
直接访问 `http://127.0.0.1:3080` 即可到达，**不需要任何网络配置**。

## 1. 安装 WSL2（已装可跳过）

以管理员身份打开 PowerShell：

```powershell
wsl --install
```

这会安装 WSL2 + 默认 Ubuntu 发行版。完成后**重启电脑**，再从开始菜单打开
Ubuntu，首次进入会让你创建 Linux 用户名和密码。

> 前置要求：Windows 10 2004+ 或 Windows 11。可在 PowerShell 里执行
> `wsl --version` 确认，报错说明需要 `wsl --update` 或启用"虚拟机平台"。

## 2. 启用 systemd（关键步骤，必做）

本脚本集依赖 `systemctl` 管理 dsh 服务，而 WSL 默认**不启用** systemd。
在 Ubuntu 里执行：

```bash
sudo tee /etc/wsl.conf <<'EOF'
[boot]
systemd=true
EOF
```

然后在 **Windows PowerShell**（不是 Ubuntu 里）执行：

```powershell
wsl --shutdown
```

再重新打开 Ubuntu 终端，验证：

```bash
ps -p 1 -o comm=
# 输出 systemd 即成功
```

> 要求 WSL 版本 >= 0.67.6（2022 年 9 月后的版本都满足，`wsl --update` 可升级）。

## 3. 一键安装 DSH

在 Ubuntu 里：

```bash
git clone https://github.com/zyi07/dsh-web-scripts.git && cd dsh-web-scripts
sudo bash install.sh
```

**不要传 `DSH_DOMAIN`** —— 没有域名就不传，脚本会：

- 以 `http://127.0.0.1:3080` 访问（无需 `--trusted-host`，本地回环天然受信任）
- 结束时直接打印 `✅ 安装完成！访问链接：http://127.0.0.1:3080/?token=xxxx`

安装脚本会自动检测 WSL 并提前检查 systemd（第 2 步没做会直接报错提示）。

## 4. 在 Windows 浏览器打开

复制安装结束输出的链接，在 Windows 的浏览器（Edge/Chrome 均可）里打开：

```
http://127.0.0.1:3080/?token=xxxx
```

首次打开后浏览器会换取 30 天有效的 cookie，之后直接访问
`http://127.0.0.1:3080` 即可，不用再带 token。

## 5. 日常使用

都在 **Ubuntu 终端**里执行：

| 命令 | 作用 |
|---|---|
| `dsh-url` | 查看/找回当前访问链接 |
| `dsh-restart` | 重启服务并输出新 token 链接 |
| `dsh-upgrade` | 升级到最新版 |

## 6. WSL 特有的注意事项

### 6.1 WSL 关机后服务会停

WSL 虚拟机在没有任何活动时会自动关闭（默认约 8 秒无连接即开始关闭计时），
关机后 dsh 服务自然停止。**下次打开 Ubuntu 终端时 systemd 会自动把 dsh
拉起来**（安装时已 `enable`），无需手动干预。

如果发现浏览器连不上：

1. 先随便打开一个 Ubuntu 终端（唤醒 WSL）
2. 等几秒让服务自启
3. 仍不行就在 Ubuntu 里执行 `systemctl status dsh` 查看

### 6.2 想让 WSL 常驻不关机（可选）

Windows 用户目录新建 `%UserProfile%\.wslconfig`：

```ini
[wsl2]
# WSL 空闲自动关机超时（毫秒，默认 60000）
# 86400000 = 24 小时；-1 = 永不自动关机
vmIdleTimeout=86400000
```

然后 `wsl --shutdown` 重新打开生效。
（来源：[Microsoft Learn .wslconfig 文档](https://learn.microsoft.com/en-us/windows/wsl/wsl-config)）

### 6.3 浏览器连不上 127.0.0.1:3080？

Windows 11 22H2+ 可以改用镜像网络模式（更稳），`%UserProfile%\.wslconfig`：

```ini
[wsl2]
networkingMode=mirrored
```

`wsl --shutdown` 后重开。镜像模式下 WSL 和 Windows 共享网络栈，localhost
转发不再依赖 NAT。

仍不通时的排查顺序：

```bash
# Ubuntu 里：服务活着吗？
systemctl status dsh
# 端口在监听吗？
ss -tlnp | grep 3080
# 服务日志有报错吗？
journalctl -u dsh -n 30 --no-pager
```

服务正常但浏览器不通 → 基本是 localhost 转发问题，用 6.3 的 mirrored 模式。

### 6.4 不要改绑 0.0.0.0

DSH 的配置校验拒绝通配地址（0.0.0.0 / ::），只接受一个具体 IP。保持默认的
`127.0.0.1` 即可，Windows 侧通过 localhost 转发访问，这正是设计好的路径。

### 6.5 想让局域网其他设备访问？

本地个人使用不建议。确实需要时：Windows 侧 `netsh interface portproxy` 把
WSL 端口转发到局域网网卡，并给 install.sh 传你用来访问的主机名作
`DSH_DOMAIN`（否则会撞上 DSH 的浏览器信任围栏，`/api` 请求会被拒）。

## 7. 常见问题

**Q: `sudo bash install.sh` 报"检测到 WSL 但未启用 systemd"？**
→ 回到第 2 步做 systemd 启用，`wsl --shutdown` 后重开再跑。

**Q: token 链接打开后一直 401？**
→ 确认地址栏是 `127.0.0.1:3080` 而不是别的 IP/域名 —— cookie 和 token 都
绑定访问时用的主机名，换了主机名要重新用 token 登录。

**Q: 升级 Windows 侧的 Node 需要吗？**
→ 不需要。Node 装在 WSL（Ubuntu）里，Windows 侧无需任何依赖。

**Q: 想重装/重置？**
→ `sudo systemctl stop dsh && sudo rm /etc/systemd/system/dsh.service` 后重跑
   install.sh；`~/.dsh` 数据目录不动就不丢配置。
