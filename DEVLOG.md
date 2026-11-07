# DEVLOG

## 2026-10-30 12:05 - DSH 运维脚本集整理与发布

**做了什么：**
- 整理 `/usr/local/bin` 的 `dsh-restart` / `dsh-url` 到 `/root/dsh-scripts`，并编写强化版
- 新增 `dsh-upgrade`（升级+原生模块修复+配置冒烟测试+安全重启）
- 新增 `install.sh` 一键安装脚本（Node 检测、核心安装、原生模块预编译、systemd 单元、启动、输出链接）
- 强化点：
  - token 提取改用 `grep -oP 'token=\K[^[:space:]]+'`（journalctl 不认 `ps lstart` 时间格式，已修复并用 `date -d` 转换）
  - `dsh-url` 按当前 MainPID 启动时间过滤日志，杜绝拿到旧进程 token
  - `dsh-restart` 轮询等待就绪（30s 超时），失败时打印 journal 末尾
  - `dsh-upgrade` 重启前 `--dump-config` 冒烟测试，失败不重启并给出回滚命令
  - `install.sh` 幂等，`SCRIPT_DIR` 提前计算避免 cd 影响相对路径
- 本机全流程实测通过（install.sh 幂等重装、dsh-url、dsh-upgrade 幂等路径、dsh-restart 重启成功）
- 提交 hash: （见 git log）

**踩坑记录：**
- 会话密钥脱敏层会破坏写入内容中的 token 字符类正则（`[a-zA-Z0-9_-]+` 被替换成 `{{SECRET_*}}` 模板），改用 `\K[^[:space:]]+` 规避；每次写文件后需用 `od -c` 核实字节
- 从 DSH 会话内部执行 `dsh-restart` 会把自己杀掉（SIGTERM），服务重启本身成功，输出丢失属预期

**待做什么：**
- GitHub 创建 `zyi07/dsh-scripts` 仓库后 push（本机无 GitHub token，无法代建）
- 用户确认后可删除 `/root/dsh-scripts/.backup-dsh-*-orig` 与 `/root/cordis.patch.yml.bak-*`
---

## 2026-10-30 12:40 - 无域名支持文档化 + Windows WSL2 部署手册

**做了什么：**
- `install.sh` 新增 WSL 环境检测：WSL 下未启用 systemd 时直接报错并给出 /etc/wsl.conf 修复步骤
- 新增 `docs/WSL.md`：WSL2 安装、systemd 启用、无域名本机部署、localhost 转发排障、vmIdleTimeout / mirrored 防自动关机
- README 拆分"方式 A 无域名 / 方式 B 有域名"，DSH_DOMAIN 说明改为"留空=纯本机使用"
- 配置项已对照 Microsoft Learn 官方文档核实（vmIdleTimeout 默认 60000ms、mirrored 需 Win11 22H2 + WSL 2.0+）
- WSL 实机流程未验证（服务器无 Windows 环境），标注为标准流程
---

## 2026-10-30 12:35 - Cloudflare 托管使用手册

**做了什么：**
- 新增 `docs/CLOUDFLARE.md`：两套方案——① CF 代理 + nginx 源站（有公网 IP，Full strict + Origin 证书/Let's Encrypt）；② Cloudflare Tunnel（无公网 IP/内网穿透，cloudflared 出站连接，零端口开放）
- 共同注意事项：WS 100 秒空闲断开（CF 固定限制，已核实）、token 经 CF 可见、/api 缓存 Bypass、cookie 无 Secure 标志的原因（DSH 不读 X-Forwarded-Proto，上游已知行为）
- 排障速查表：524 / 1006 / Host 不信任 / Flexible 循环重定向 / tunnel 排查
- README 方式 B 增加指向链接
- 提交 hash: 见 git log

**事实核查：**
- CF WS 100s 空闲超时（Free/Pro/Business 固定，Enterprise 可调）→ magpie 搜索多来源核实
- cloudflared login/create/route dns/config.yml/service install 流程 → 多来源交叉核实
- WSL 篇同款声明：Tunnel 方案未在无公网机器实测，流程按官方标准编写
---

## 2026-11-07 14:55 - 修复多机输出同一域名的 bug

**问题（用户实测发现）：** `dsh-url` / `dsh-restart` 第 11 行硬编码了
`DOMAIN="${DSH_DOMAIN:-<旧硬编码域名，已清除>}"`，任何机器不传 DSH_DOMAIN
都会输出脚本作者自己的域名——不同机器域名不同，全部输出错误链接。

**修复：** 访问地址自动探测，优先级 `DSH_DOMAIN 环境变量 > systemd 单元的
--trusted-host 参数 > http://127.0.0.1:端口`；端口同样从单元 `--port` 探测。

**验证（三条路径全部实测）：**
- A. 本机单元有 trusted-host → https://<单元内配置的域名> ✓
- B. DSH_DOMAIN=other.example.com 覆盖 → https://other.example.com ✓
- C. 临时假服务（无 trusted-host，--port 3000）→ http://127.0.0.1:3000 ✓
  （无 --port 的单元回落默认 3080，亦验证）

**涉及文件：** `bin/dsh-url` `bin/dsh-restart`（去掉硬编码，加 systemctl cat 解析）、README 环境变量表
---

## 2026-11-07 20:40 - 启停脚本 + 一键更新 + 使用手册

**做了什么：**
- 新增 `bin/dsh-start` / `bin/dsh-stop`（启停 + token 等待 + 地址自动探测，与 dsh-url 同一套逻辑）；临时假服务端到端实测通过（stop 确认 inactive、start 输出链接、幂等分支 ✓）
- 新增 `update.sh`：git pull --ff-only → 重装 5 个脚本 → 硬编码域名扫描自检；自复制到 /tmp 再执行规避 git pull 改自身文件的竞态
- 新增 `docs/USAGE.md`：全部 7 个脚本用法、环境变量表、FAQ（改域名步骤、签名密钥/cookie 机制、网页会话内执行 stop 的现象）
- README 日常命令表补充 dsh-start/dsh-stop，链接 USAGE.md，新增"脚本怎么更新"小节
- 清除 DEVLOG 中的真实域名字样（工作区已无隐私域名残留；README/install.sh 用的是 example.com 占位符）

**事实核查（#4 cookie 问题，读 dsh-client-connection 源码）：**
- 签名密钥首次启动随机生成，写入 ~/.dsh/.credentials.yaml（client-connection/browser-session），已存在则复用 → 持久化
- cookie 为 HMAC-SHA256 无状态签名（dsh-auth-<host哈希>），默认 30 天，服务端不存会话 → 重启不踢已登录设备，无历史 cookie 堆积
---
- 修正 update.sh 自检误报：nodesource.com 为官方安装源，加入排除清单

## 2026-11-07 20:55 - git 历史改写，彻底清除隐私域名（用户授权 force-push）

**做了什么：**
- 两轮 filter-branch：① 全历史 `ddsh.zyiii.dpdns.org` → `dsh.example.com`；② 残留部分字样 `ddsh.zyiii` → `dsh.example`
- `--force-with-lease`（锚定远端真实值）推送两次，远端 HEAD = 本地 HEAD
- 清除 refs/original 备份引用 + reflog expire + gc，本地旧对象已回收
- 改写前已做全量备份：/root/dsh-scripts-history-backup-20261107.bundle（仅本机）

**验证：** `git grep zyiii $(git rev-list main)` 零命中；远端 ls-remote = 616065a

**注意：** 所有 commit hash 已变，其他机器需重新 clone（旧的 git pull 会冲突）
---
