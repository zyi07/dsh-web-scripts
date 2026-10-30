# dsh-scripts

DSH（DeepSeek Harness）Web 服务运维脚本集：一键安装、升级、重启、获取访问链接。

## 适用环境

- Linux：Debian / Ubuntu（aarch64 或 x86_64）
- Windows：WSL2 + Ubuntu（需启用 systemd，见 [docs/WSL.md](docs/WSL.md)）
- Node.js >= 20（脚本会自动装）
- systemd

## 一键安装（新机器）

### 方式 A：没有域名 / 本机使用（含 Windows + WSL）

```bash
git clone https://github.com/zyi07/dsh-web-scripts.git && cd dsh-web-scripts
sudo bash install.sh
```

**不传 `DSH_DOMAIN` 即可**：服务只监听 `127.0.0.1`，本地回环天然受 DSH
信任，无需 `--trusted-host`，安装结束直接输出 `http://127.0.0.1:3080/?token=...`。

Windows 用户走 WSL2 部署：**详见 [docs/WSL.md](docs/WSL.md)**（含 systemd
启用、localhost 转发排障、防止 WSL 自动关机等）。

### 方式 B：有域名 / 对外提供服务

```bash
git clone https://github.com/zyi07/dsh-web-scripts.git && cd dsh-web-scripts
sudo DSH_DOMAIN=你的域名 bash install.sh
```

域名会作为 `--trusted-host` 传入，配合反向代理从外网访问：

- **CF 托管（DNS/代理/内网穿透）**：**详见 [docs/CLOUDFLARE.md](docs/CLOUDFLARE.md)** —— 含 CF 代理 + nginx 和 **Cloudflare Tunnel（无公网 IP 也能用）** 两套方案
- 纯 nginx 反代配置见下文

`install.sh` 会依次完成：

1. 检查/安装 Node.js >= 20（NodeSource，仅 apt 系统）
2. `npm install -g @deepseek-ai/dsh@latest` 安装 DSH 核心
3. 修复 npm 拦截的原生模块构建（node-pty / koffi 预编译）
4. 安装 `dsh-restart` / `dsh-url` / `dsh-upgrade` 到 `/usr/local/bin`
5. 生成 systemd 单元（若已有则保留现有配置）
6. 启动并开机自启
7. 打印带 token 的访问链接

### 环境变量

| 变量 | 默认值 | 说明 |
|---|---|---|
| `DSH_DOMAIN` | 空 | 外网域名，传入后会加 `--trusted-host`；**留空 = 纯本机使用**（127.0.0.1，无需域名） |
| `DSH_PORT` | `3080` | 监听端口 |
| `DSH_PROFILE` | `web` | profile 名 |

幂等：重复执行 = 升级核心 + 修复原生模块 + 重启，`~/.dsh` 数据不受影响。

## 日常命令

| 命令 | 作用 |
|---|---|
| `dsh-url` | 输出当前带 token 的访问链接（只认当前进程的日志，不会拿旧 token） |
| `dsh-restart` | 重启服务，轮询等待就绪，输出新链接；失败时打印 journal 末尾 |
| `dsh-upgrade` | 升级核心 → 补跑原生模块预编译 → 配置冒烟测试 → 通过才重启 |

### 升级的安全性

`dsh-upgrade` 在重启前会用 `dsh --dump-config` 做冒烟测试：

- 测试失败 → **不重启**，服务继续跑旧版本，并打印回滚命令
- 测试通过 → 重启并输出新链接

### 关于 token 与登录

- token 只在当前进程存活期间有效，**每次重启都会更换**
- 首次用 `?token=` 链接打开后，会换取 30 天有效的浏览器 cookie，之后直接访问域名即可
- 重启不会使已有 cookie 失效（签名密钥持久化在 `~/.dsh/.credentials.yaml`）
- 从 DSH 会话内部执行 `dsh-restart` 会把自己也杀掉（进程树属于 dsh），其输出会丢失——这是预期现象，请从 SSH 终端执行

## 反向代理（nginx）参考

```nginx
server {
    listen 443 ssl;
    server_name ddsh.example.com;
    # ssl_certificate ...;

    location / {
        proxy_pass http://127.0.0.1:3080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
    }
}
```

注意：DSH 只信任直连/白名单 Host，nginx 层务必保持 `proxy_set_header Host $host;`，并把域名传给 `install.sh` 的 `DSH_DOMAIN`（即 dsh 启动参数 `--trusted-host`）。

## 环境变量覆盖（命令行工具）

`dsh-url` / `dsh-restart` / `dsh-upgrade` 均支持：

| 变量 | 默认值 |
|---|---|
| `DSH_SERVICE` | `dsh` |
| `DSH_DOMAIN` | `ddsh.zyiii.dpdns.org`（建议改掉） |
| `DSH_START_TIMEOUT` | `30`（dsh-restart） |
| `DSH_NPM_PACKAGE` | `@deepseek-ai/dsh`（dsh-upgrade） |

## 许可

MIT
