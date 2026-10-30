# Cloudflare 托管部署 DSH 教程

适用于域名 DNS 托管在 Cloudflare 的场景，按你的服务器环境二选一：

| 方案 | 适用场景 | 需要公网 IP | 需要源站 TLS | 推荐度 |
|---|---|---|---|---|
| 方案一：CF 代理 + nginx | 有公网 VPS，想蹭 CF 的 CDN/防护 | 需要 | 需要（nginx） | 常规选择 |
| 方案二：Cloudflare Tunnel | 家用宽带/无公网 IP/不想开端口 | **不需要** | 不需要 | 内网部署首选 |

> 两个方案的共同点：域名都解析到 Cloudflare（橙云代理），`install.sh` 都必须传
> `DSH_DOMAIN=你的域名`，否则 DSH 的浏览器信任围栏会拒绝 `/api` 请求。

## 前置：把域名托管到 Cloudflare

1. 注册/登录 [dash.cloudflare.com](https://dash.cloudflare.com)，Add a site 添加你的域名
2. 到域名注册商处把 NS 记录改成 Cloudflare 分配的两个 NS（等待生效，几分钟到几小时）
3. 进入该域名的管理页，后续操作都在这里

---

## 方案一：CF 代理 + nginx 源站（有公网 IP 的服务器）

架构：`浏览器 → Cloudflare(HTTPS) → 源站 nginx(443) → 127.0.0.1:3080 (dsh)`

### 1.1 DNS 记录

DNS → Records → Add record：

- 类型 `A`，名称 `dsh`（即 `dsh.你的域名.com`），内容 = 服务器公网 IP
- **Proxy status 开启橙色云朵**（Proxied）——开了才是 CF 代理，灰云只是 DNS 解析

### 1.2 SSL/TLS 模式（关键，配错会循环重定向）

SSL/TLS → Overview → 选 **Full (strict)**：

| 模式 | 结果 |
|---|---|
| Flexible | CF 用 HTTP 回源，配合 nginx 80 跳转 443 会**无限重定向**，❌ 别用 |
| Full | 允许自签证书，能用但不校验 |
| **Full (strict)** | CF 校验源站证书，✅ 推荐 |

源站证书两种来源任选：

```bash
# 选项 A：Let's Encrypt（Certbot，需临时放行 80 端口）
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d dsh.你的域名.com

# 选项 B：CF Origin Certificate（15年有效期，仅 CF 信任）
# dash.cloudflare.com → SSL/TLS → Origin Server → Create Certificate
# 把证书和私钥存到 /etc/nginx/ssl/ 下
```

### 1.3 安装 DSH 并配置 nginx

```bash
git clone https://github.com/zyi07/dsh-web-scripts.git && cd dsh-web-scripts
sudo DSH_DOMAIN=dsh.你的域名.com bash install.sh
```

nginx 站点配置（`/etc/nginx/sites-available/dsh.你的域名.com`）：

```nginx
server {
    listen 443 ssl http2;
    server_name dsh.你的域名.com;

    ssl_certificate     /etc/nginx/ssl/证书路径;   # certbot 会自动填，或 Origin 证书路径
    ssl_certificate_key /etc/nginx/ssl/私钥路径;

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

```bash
sudo ln -s /etc/nginx/sites-available/dsh.你的域名.com /etc/nginx/sites-enabled/
sudo nginx -t && sudo nginx -s reload
```

然后浏览器打开 `dsh-url` 输出的链接即可。

---

## 方案二：Cloudflare Tunnel（无公网 IP / 家用内网 / 不想开端口）

架构：`浏览器 → Cloudflare ←（cloudflared 出站隧道）← 127.0.0.1:3080 (dsh)`

cloudflared 从服务器**主动向外**连接 CF 边缘，无需公网 IP、无需端口转发、
无需源站证书，防火墙零配置。家宽/NAT 后的机器也能对外提供服务。

### 2.1 安装 cloudflared

```bash
# Debian/Ubuntu（x86_64）
curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
    -o /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared
# aarch64 把 amd64 换成 arm64
cloudflared --version
```

### 2.2 授权并创建隧道

```bash
cloudflared tunnel login          # 浏览器打开输出的 URL，选择域名授权
cloudflared tunnel create dsh     # 记下输出的 Tunnel UUID
cloudflared tunnel route dns dsh dsh.你的域名.com   # 自动建 CNAME 记录
```

### 2.3 配置 ingress 并注册为系统服务

`/etc/cloudflared/config.yml`：

```yaml
tunnel: <Tunnel-UUID>
credentials-file: /root/.cloudflared/<Tunnel-UUID>.json

ingress:
  - hostname: dsh.你的域名.com
    service: http://127.0.0.1:3080
  - service: http_status:404      # 兜底规则，必须放最后
```

```bash
cloudflared tunnel ingress validate                  # 语法检查
sudo cloudflared --config /etc/cloudflared/config.yml service install
sudo systemctl enable --now cloudflared
```

### 2.4 安装 DSH 并取链接

```bash
git clone https://github.com/zyi07/dsh-web-scripts.git && cd dsh-web-scripts
sudo DSH_DOMAIN=dsh.你的域名.com bash install.sh
dsh-url    # 拿到 https://dsh.你的域名.com/?token=xxx
```

---

## 两种方案都适用的注意事项

### WebSocket 空闲 100 秒断开（已知限制）

Cloudflare 代理（Free/Pro/Business 套餐）对空闲 WebSocket 连接有 **100 秒
强制断开**的固定限制（Enterprise 才可调）。空闲超 100 秒无任何帧交换，连接
会被掐断（浏览器侧表现为 code 1006）。

- DSH 前端有活动心跳的话通常无感（未验证具体间隔，如遇频繁断线可反馈）
- 服务端/nginx 侧的 `proxy_read_timeout 3600s` 管不了 CF 这一跳
- 临时缓解：让页面保持交互（有输入输出就不会空闲）

（来源：Cloudflare 社区与实测总结，见 [stackharbor 的分析](https://stackharbor.com)）

### token 与隐私

- `?token=xxx` 会经过 Cloudflare（CF 边缘日志/分析能看到查询串）
- 首次登录换取 30 天 cookie 后，日常访问不再带 token
- 不放心可在 `install.sh` 后用 `dsh-restart` 换新 token，并尽快完成首次 cookie 交换

### 缓存

CF 默认不缓存 HTML 和 API 响应，一般无需配置。若你给域名加了缓存规则，
务必对 `/api/*` 和 WebSocket 路径设置 **Bypass cache**，否则会看到别人的会话
或页面不更新。

### cookie 的 Secure 标志

DSH 不读 `X-Forwarded-Proto`，经反代/Tunnel 访问时它以为自己是 HTTP，签发的
cookie 不带 `Secure` 标志（传输层仍全程 HTTPS，中间人看不到内容，但浏览器
允许该 cookie 在 HTTP 请求中附带）。这是 DSH 上游的已知行为，个人使用风险
可接受，介意的话向 DSH 反馈。

## 排障速查

| 现象 | 原因 | 处理 |
|---|---|---|
| 浏览器 524 超时 | 源站 100 秒内没响应（CF 回源超时） | 查 `systemctl status dsh` 是否卡死 |
| WS 频繁 1006 断开 | CF 100 秒空闲超时 | 见上文 WebSocket 一节 |
| 页面能开但 /api 全部拒绝 | Host 不受信任 | 确认 install.sh 传了 `DSH_DOMAIN`，`dsh-restart` 后重试 |
| 无限重定向 | SSL 模式设成了 Flexible | 改成 Full (strict) |
| Tunnel 方案连接不上 | cloudflared 没跑起来 / ingress 没配 | `systemctl status cloudflared`；`cloudflared tunnel ingress validate` |
| Tunnel 方案 DNS 不生效 | route dns 没执行 | 重新执行 `cloudflared tunnel route dns <名> <域名>` |
