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
