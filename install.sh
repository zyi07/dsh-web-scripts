#!/bin/bash
# install.sh — DSH Web 一键安装/升级脚本
#
# 用法（新机器上）：
#   git clone https://github.com/zyi07/dsh-scripts.git && cd dsh-scripts
#   sudo bash install.sh                      # 默认：端口 3080，无外网域名
#   sudo DSH_DOMAIN=ddsh.example.com bash install.sh
#
# 环境变量：
#   DSH_DOMAIN   外网访问域名（可选，会作为 --trusted-host 传入）
#   DSH_PORT     监听端口，默认 3080
#   DSH_PROFILE  profile 名，默认 web
#
# 幂等：重复执行等同于"升级核心 + 修复原生模块 + 重启"，不会覆盖已有的
# systemd 单元和 profile 数据（~/.dsh 不受影响）。
set -euo pipefail

DSH_DOMAIN="${DSH_DOMAIN:-}"
DSH_PORT="${DSH_PORT:-3080}"
DSH_PROFILE="${DSH_PROFILE:-web}"
PKG="@deepseek-ai/dsh"
SERVICE="dsh"

[ "$(id -u)" = 0 ] || { echo "❌ 请用 sudo / root 运行" >&2; exit 1; }

# 尽早固定脚本自身目录，防止后续 cd 影响相对路径解析
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> 1/7 检查 Node.js"
NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v\([0-9]*\).*/\1/' || echo 0)"
if [ "$NODE_MAJOR" -lt 20 ]; then
    echo "   Node >= 20 未安装或过旧（当前: ${NODE_MAJOR}），尝试通过 NodeSource 安装 Node 24..."
    if command -v apt-get >/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
        apt-get install -y nodejs
    else
        echo "❌ 仅支持 apt 系统（Debian/Ubuntu）自动安装 Node，请手动安装 Node >= 20 后重试" >&2
        exit 1
    fi
fi
echo "   ✓ Node $(node --version)"

echo "==> 2/7 安装 DSH 核心"
OLD_VER="$(dsh --version 2>/dev/null || echo '（未安装）')"
LATEST="$(npm view "$PKG" dist-tags.latest)"
echo "   $OLD_VER → $LATEST"
npm install -g "$PKG@$LATEST" 2>&1 | grep -v "^npm warn" || true

echo "==> 3/7 修复原生模块（npm 可能拦截了构建脚本）"
GLOBAL_ROOT="$(npm root -g)"
APP_DIR="$GLOBAL_ROOT/@deepseek-ai/dsh/node_modules"
(cd "$APP_DIR/node-pty" 2>/dev/null && node scripts/prebuild.js >/dev/null 2>&1) || true
(cd "$APP_DIR/koffi" 2>/dev/null && node cnoke.cjs -P . -D src/koffi --prebuild --release >/dev/null 2>&1) || true
cd "$APP_DIR" 2>/dev/null || true
node -e "require('koffi')" >/dev/null 2>&1 && echo "   ✓ koffi OK" || echo "   ⚠️ koffi 加载失败"
node -e "require('node-pty')" >/dev/null 2>&1 && echo "   ✓ node-pty OK" || echo "   ⚠️ node-pty 加载失败"

echo "==> 4/7 安装命令行工具到 /usr/local/bin"
install -m 755 "$SCRIPT_DIR/bin/dsh-restart" /usr/local/bin/dsh-restart
install -m 755 "$SCRIPT_DIR/bin/dsh-url" /usr/local/bin/dsh-url
install -m 755 "$SCRIPT_DIR/bin/dsh-upgrade" /usr/local/bin/dsh-upgrade
echo "   ✓ dsh-restart / dsh-url / dsh-upgrade"

echo "==> 5/7 配置 systemd 服务"
UNIT=/etc/systemd/system/${SERVICE}.service
if [ -f "$UNIT" ]; then
    echo "   已有 $UNIT，保留现有配置（如需重置请删除后重跑）"
    if ! grep -q "dsh-url" <(systemctl cat "$SERVICE" 2>/dev/null) && \
       ! systemctl cat "$SERVICE" 2>/dev/null | grep -q "ExecStart"; then
        echo "   ⚠️ 现有单元文件异常，请检查"
    fi
else
    TRUSTED=""
    [ -n "$DSH_DOMAIN" ] && TRUSTED="--trusted-host $DSH_DOMAIN"
    cat > "$UNIT" <<EOF
[Unit]
Description=DSH (DeepSeek Harness) Web Service
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/dsh --profile $DSH_PROFILE --no-open --port $DSH_PORT $TRUSTED
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    echo "   ✓ 已创建 $UNIT（profile=$DSH_PROFILE port=$DSH_PORT trusted-host=${DSH_DOMAIN:-无}）"
fi

echo "==> 6/7 启动服务"
systemctl daemon-reload
systemctl enable --now "$SERVICE" 2>/dev/null || systemctl restart "$SERVICE"

echo "==> 7/7 等待就绪并输出访问链接"
# 等服务打印 token，最多 30 秒
TOKEN=""
for _ in $(seq 1 30); do
    sleep 1
    TOKEN="$(journalctl -u "$SERVICE" -n 30 --no-pager -o cat 2>/dev/null \
        | grep -oP 'token=\K[^[:space:]]+' | tail -n 1 || true)"
    [ -n "$TOKEN" ] && break
done

echo ""
if [ -n "$TOKEN" ]; then
    HOST="${DSH_DOMAIN:-127.0.0.1:$DSH_PORT}"
    echo "✅ 安装完成！访问链接："
    echo "   http://$HOST/?token=$TOKEN"
else
    echo "⚠️ 服务已启动但未捕获到 token，请执行 dsh-url 获取。"
fi
echo ""
echo "常用命令："
echo "   dsh-url      查看当前访问链接"
echo "   dsh-restart  重启并输出新链接"
echo "   dsh-upgrade  升级到最新版"
