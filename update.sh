#!/bin/bash
# update.sh — 一键更新：拉取仓库最新代码并重装脚本到 /usr/local/bin
# 用法：在仓库目录内执行  bash update.sh
# 说明：先 git pull，再安装 bin/ 下全部脚本；最后自检是否存在硬编码隐私域名。
set -euo pipefail

# git pull 可能改到本脚本自身（bash 边执行边读文件有竞态），先复制到 /tmp 再重新执行
if [ -z "${DSH_UPDATE_REEXEC:-}" ]; then
    TMP="$(mktemp /tmp/dsh-update.XXXXXX.sh)"
    cp "$0" "$TMP"
    DSH_UPDATE_REEXEC=1 exec bash "$TMP" "$(cd "$(dirname "$0")" && pwd)"
fi

REPO_DIR="${1:-}"
if [ -z "$REPO_DIR" ]; then
    echo "用法：bash update.sh（在 dsh-web-scripts 仓库目录内执行）" >&2
    exit 1
fi
cd "$REPO_DIR"

# root 免 sudo
SUDO=""
[ "$(id -u)" != "0" ] && SUDO="sudo"

echo "==> 拉取最新代码"
git pull --ff-only

echo "==> 重装脚本到 /usr/local/bin"
$SUDO install -m 755 bin/dsh-url bin/dsh-restart bin/dsh-upgrade bin/dsh-start bin/dsh-stop /usr/local/bin/

echo "==> 防泄露自检（扫描脚本中是否有硬编码域名）"
LEAK="$(grep -rnE '[a-z0-9-]+\.(com|net|org|cn|dev|app|io|dpdns\.org)' bin/ install.sh update.sh 2>/dev/null \
    | grep -v 'ddsh\.example\.com' | grep -v 'example\.com' | grep -v 'github\.com' \
    | grep -v 'nodesource\.com' | grep -v 'npmjs' || true)"
if [ -n "$LEAK" ]; then
    echo "⚠️ 发现疑似硬编码域名，请检查：" >&2
    echo "$LEAK" >&2
    exit 1
fi
echo "✓ 未发现硬编码隐私域名"

echo ""
echo "✅ 更新完成，当前版本：$(git log --oneline -1)"
echo "   可用命令：dsh-url / dsh-restart / dsh-start / dsh-stop / dsh-upgrade"
