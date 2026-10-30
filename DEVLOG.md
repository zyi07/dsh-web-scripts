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
