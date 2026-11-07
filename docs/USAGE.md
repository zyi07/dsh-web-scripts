# 脚本使用手册

`dsh-web-scripts` 仓库内全部脚本的完整用法。一键安装见 [README](../README.md)，
无域名/WSL 见 [docs/WSL.md](WSL.md)，Cloudflare 托管见 [docs/CLOUDFLARE.md](CLOUDFLARE.md)。

## 脚本总览

| 脚本 | 安装位置 | 作用 |
|---|---|---|
| `install.sh` | 仓库内 | 新机器一键安装（Node + DSH 核心 + 原生模块 + systemd 单元 + 启动） |
| `update.sh` | 仓库内 | **老机器一键更新**：`git pull` + 重装全部脚本 + 防泄露自检 |
| `dsh-url` | `/usr/local/bin` | 输出当前带 token 的访问链接 |
| `dsh-restart` | `/usr/local/bin` | 重启服务并输出新链接 |
| `dsh-start` | `/usr/local/bin` | 启动服务并输出链接 |
| `dsh-stop` | `/usr/local/bin` | 停止服务 |
| `dsh-upgrade` | `/usr/local/bin` | 升级 DSH 核心（先冒烟测试，通过才重启） |

---

## install.sh — 新机器一键安装

```bash
git clone https://github.com/zyi07/dsh-web-scripts.git && cd dsh-web-scripts
sudo bash install.sh              # 方式 A：纯本机（127.0.0.1，无域名）
sudo DSH_DOMAIN=域名 bash install.sh   # 方式 B：有域名（加 --trusted-host）
```

幂等：重复执行安全（已有 systemd 单元会保留，不会被覆盖）。

## update.sh — 老机器一键更新

```bash
cd dsh-web-scripts    # 之前克隆的仓库目录
bash update.sh
```

自动完成：`git pull --ff-only` → 重装 5 个命令到 `/usr/local/bin` →
扫描脚本确认没有硬编码隐私域名 → 打印当前 commit。以后升级脚本就这一条命令。

---

## dsh-url — 获取访问链接

```bash
dsh-url                     # 输出 https://域名/?token=... 或 http://127.0.0.1:3080/?token=...
DSH_SERVICE=我的服务 dsh-url   # 单元名不是 dsh 时
```

- 只认**当前进程**启动后打印的 token（按 MainPID 过滤 journal），不会拿到旧 token
- token 只在当前进程存活期间有效，重启后会更换
- 首次打开链接后浏览器换取 30 天 cookie，之后直接访问域名，不再需要 token

## dsh-restart — 重启服务

```bash
dsh-restart
```

- 轮询等待就绪（默认最多 30s），就绪即输出新链接；失败打印 journal 末尾 15 行
- ⚠️ **不要在 DSH 网页会话里执行**：重启会中断你所在的会话（重启本身成功，只是你看不到输出），请用 SSH

## dsh-start / dsh-stop — 启停服务

```bash
dsh-stop      # 停止；已停止时提示无需操作
dsh-start     # 启动；等待就绪并输出带 token 链接；已运行时提示用 dsh-url
```

- 显式 `stop` 后 systemd **不会**自动拉起（`Restart=always` 只管异常退出），要再次使用需 `dsh-start`
- 同样建议从 SSH 执行（在网页会话里 stop 会立刻断开自己的连接）
- 停机期间所有访问中断；`~/.dsh` 数据不受影响

## dsh-upgrade — 升级 DSH 核心

```bash
dsh-upgrade
```

流程：比较版本 → `npm install -g @deepseek-ai/dsh@latest` → 补跑原生模块预编译 →
对**新代码**做 `--dump-config` 冒烟测试 → 测试通过才重启（失败不重启，并给出回滚命令）。

---

## 环境变量（所有脚本通用）

| 变量 | 默认值 | 适用 |
|---|---|---|
| `DSH_DOMAIN` | 自动探测 | url/restart/start：覆盖输出域名 |
| `DSH_SERVICE` | `dsh` | 全部：systemd 单元名 |
| `DSH_PORT` | 自动探测（无则 3080） | url/restart/start：回环地址端口 |
| `DSH_START_TIMEOUT` | `30` | restart/start：等待就绪秒数 |
| `DSH_NPM_PACKAGE` | `@deepseek-ai/dsh` | upgrade：npm 包名 |

**访问地址探测优先级**：`DSH_DOMAIN` 环境变量 > systemd 单元里的
`--trusted-host` 参数 > `http://127.0.0.1:端口`。不硬编码任何域名，多台机器各自输出各自的。

---

## FAQ

### 怎么修改域名？

1. 改 systemd 单元：`sudo systemctl edit --full dsh`，把 `ExecStart` 里的
   `--trusted-host 旧域名` 改成新域名（或直接编辑 `/etc/systemd/system/dsh.service`）
2. `sudo systemctl daemon-reload && sudo dsh-restart`
3. 改反代/解析侧：nginx 的 `server_name` 或 CF 的 DNS 记录同步换成新域名
4. **浏览器需要重新登录**：cookie 按域名绑定（cookie 名含 host 哈希），换域名后旧 cookie 不被认，用 `dsh-url` 的新链接登录即可
5. 注意 `install.sh` 对已存在的单元是"保留不覆盖"，所以改域名走上面第 1 步，而不是重跑 install.sh

### 签名密钥与 cookie 的机制（重启会不会让登录失效？会不会堆积历史 cookie？）

机制（依据 DSH `dsh-client-connection` 源码）：

- **签名密钥**：首次启动随机生成一次，写入 `~/.dsh/.credentials.yaml`
  （记录 `client-connection/browser-session`），**之后重启/升级一直复用同一个**
- **cookie**：HMAC-SHA256 无状态签名（`dsh-auth-<host哈希>`），有效期 30 天
  （配置项 `cookieMaxAgeDays` 默认 30），校验在本地完成，**服务端不保存任何会话记录**

结论：

- 重启/升级 **不会**把已登录设备踢下线（密钥没变，旧 cookie 依然有效）
- **不存在**"历史 cookie 堆积"——服务端无状态，每台浏览器每个域名只有一个 cookie，重新登录时旧的自然被覆盖
- cookie 满 30 天自然过期，届时用 `dsh-url` 的新链接重新登录一次
- 每次重启更换的只是**启动 token**（URL 里那个），只影响"还没登录的新设备"
- 想强制所有设备下线：删除 `~/.dsh/.credentials.yaml` 里 `client-connection/browser-session` 对应记录（或整个文件）后 `dsh-restart`，所有 cookie 立即失效
