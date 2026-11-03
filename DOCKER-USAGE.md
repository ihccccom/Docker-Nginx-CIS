# Nginx Docker 使用教程

基于 CIS Docker Benchmark、CIS Nginx Benchmark 标准的 Nginx 安全容器化部署方案。

> 本文档适用于直接拉取预构建镜像或本地 compose 部署。  
> 编译构建细节见仓库根目录 [README.md](README.md)。

## 目录

- [快速开始](#快速开始)
- [卷挂载说明](#卷挂载说明)
- [配置结构](#配置结构)
- [ModSecurity WAF](#modsecurity-waf)
- [PHP 集成](#php-集成)
- [添加网站](#添加网站)
- [SSL 证书](#ssl-证书)
- [HTTP/3](#http3)
- [安全配置](#安全配置)
- [日常运维](#日常运维)
- [常见问题](#常见问题)

## 快速开始

### 预构建镜像（推荐）

```bash
git clone https://github.com/ihccccom/Docker-Nginx-CIS.git
cd Docker-Nginx-CIS

# 按需修改 docker-compose.hub.yml 中的 image
docker compose -f docker-compose.hub.yml up -d

curl http://localhost/nginx-health
curl -k https://localhost/
```

> `docker-compose.ghcr.yml` 是历史兼容文件名，内容与 `docker-compose.hub.yml` 相同（实际拉取 Docker Hub，不是 GHCR）。

### 本地构建

```bash
docker compose build
docker compose up -d
bash tests/validate.sh
```

### 私有镜像登录

```bash
echo "你的TOKEN" > ~/.dockerhub_token
cat ~/.dockerhub_token | docker login -u 你的DockerHub用户名 --password-stdin
rm ~/.dockerhub_token
```

## 卷挂载说明

| 宿主机 / 卷 | 容器路径 | 说明 |
|-------------|---------|------|
| `./conf` 或 `nginx-conf` | `/opt/nginx/conf` | 主配置、proxy、ModSecurity |
| `./conf.d` 或 `nginx-confd` | `/opt/nginx/conf.d` | sites-available / sites-enabled |
| `./ssl` 或 `nginx-ssl` | `/opt/nginx/ssl` | 证书 |
| `./logs` 或 `nginx-logs` | `/opt/nginx/logs` | 访问/错误/WAF 审计日志 |
| `./wwwroot` 或 `wwwroot` | `/www/wwwroot` | 网站根目录 |
| tmpfs | `/var/cache/nginx` | 缓存与 ModSecurity 临时目录（默认 512m） |

**重要**：仓库 `conf/modsecurity/` 不含 OWASP CRS `rules/`（构建时下载进镜像）。若 bind-mount `./conf` 导致规则目录缺失，`docker-entrypoint.sh` 会从 `/opt/config-seed` 自动补齐 `rules/`、`plugins/` 与 `unicode.mapping`。

## 配置结构

```
/opt/nginx/
├── conf/
│   ├── nginx.conf
│   ├── proxy.conf
│   ├── security-headers-common.conf
│   ├── php/enable-php-84.conf
│   └── modsecurity/
│       ├── main.conf
│       ├── modsecurity.conf
│       ├── crs-setup.conf
│       ├── hosts.allow / hosts.deny   # 默认仅注释示例
│       ├── rules/                    # OWASP CRS（镜像种子）
│       └── plugins/
├── conf.d/
│   ├── sites-available/
│   └── sites-enabled/
├── ssl/
└── logs/
```

## ModSecurity WAF

全局默认启用（`nginx.conf`）：

```nginx
modsecurity on;
modsecurity_rules_file /opt/nginx/conf/modsecurity/main.conf;
```

- 引擎默认 `SecRuleEngine on`（阻断模式）
- 审计日志默认 `SecAuditLogParts AIJDEFHZ`（不含请求头 B 段，降低 Cookie/Token 泄露）
- IP 黑白名单见 `hosts.allow` / `hosts.deny`（默认无生效规则，按需取消注释）

查看审计：

```bash
docker exec nginx ls -la /opt/nginx/logs/modsec_audit/
```

WordPress 排除插件（可选）：取消 `main.conf` 末尾 wordpress 插件两行注释。

## PHP 集成

在站点 `server` 中引入：

```nginx
include /opt/nginx/conf/php/enable-php-84.conf;
```

默认 `fastcgi_pass php:36000;`，需在同一 Docker 网络中提供名为 `php` 的 PHP-FPM 服务。

## 添加网站

可用 `site.sh`（交互式：DNS API + 通配符证书 + WordPress），或手动：

```bash
cp conf/example.com.conf.template conf.d/sites-available/example.com.conf
# 编辑 server_name / 证书路径后：
ln -sf ../sites-available/example.com.conf conf.d/sites-enabled/example.com.conf
docker exec nginx /opt/nginx/sbin/nginx -t
docker exec nginx /opt/nginx/sbin/nginx -s reload
```

模板默认：

- `ssl_session_tickets off`
- 使用主配置 `limit_req` / `limit_conn` zone
- CSP 偏严格（按业务调整）
- UA 黑名单不含 `curl`/`wget`/`python`

## SSL 证书

证书建议放在 `/opt/nginx/ssl/<domain>/`：

```
fullchain.pem
privkey.pem
ca.pem          # OCSP stapling
```

Secrets 示例见 `security/secrets/docker-compose-secrets.yml`。

## HTTP/3

镜像已启用 `http_v3`。站点模板含 `listen 443 quic`。  
Compose 需同时映射：

```yaml
ports:
  - "80:80"
  - "443:443"
  - "443:443/udp"
```

仅映射 TCP 443 时 Alt-Svc 无法真正协商 HTTP/3。

## 安全配置

Compose 默认启用：

- `cap_drop: ALL` + 最小 `cap_add`
- `read_only: true` + tmpfs
- `no-new-privileges`
- 资源限制与健康检查

可选增强（默认注释）：

```yaml
security_opt:
  - no-new-privileges:true
  - seccomp=./security/seccomp/nginx-seccomp.json
  - apparmor=docker-nginx
```

启用 AppArmor 前：

```bash
sudo apparmor_parser -r -W security/apparmor/nginx-apparmor-profile
```

完整验收：

```bash
bash tests/validate.sh
sudo bash security/cis-docker-benchmark/docker-bench-check.sh
```

## 日常运维

```bash
# 更新预构建镜像
docker compose -f docker-compose.hub.yml pull
docker compose -f docker-compose.hub.yml up -d

# 重载配置
docker exec nginx /opt/nginx/sbin/nginx -t
docker exec nginx /opt/nginx/sbin/nginx -s reload

# 日志
docker compose -f docker-compose.hub.yml logs -f nginx
docker exec nginx tail -f /opt/nginx/logs/nginx_error.log
```


## 企业生产

```bash
# 预构建 + 企业叠加（Seccomp / ulimit / 优雅停机）
docker compose -f docker-compose.hub.yml -f docker-compose.enterprise.yml up -d
```

- 真实客户端 IP：`conf/real-ip.conf`（默认关闭，防伪造）
- DNS：`conf/resolvers.conf`（改为内网 DNS）
- 日志：`nginx_access.log` + `nginx_access.json`；宿主机轮转见 `security/logrotate/`
- CRS：默认 Paranoia Level 2；健康检查仅允许 `127.0.0.1`/`::1`
- 镜像：生产改用 `nginx-<version>` 或 digest，勿长期 `latest`

## 常见问题

**Q: bind-mount 后 ModSecurity 报找不到 rules？**  
A: 确认 entrypoint 已同步种子；或手动从运行中的命名卷/`docker create` 拷贝 `rules/`。

**Q: 容器因只读根无法写缓存？**  
A: 确认 compose 含 `/var/cache/nginx` tmpfs。

**Q: 为什么不是全程非 root？**  
A: master 需绑定 80/443；worker 为 `www-data`。若改用高位端口+映射，可再评估 `USER`。

**Q: 默认 HTTPS 站点为什么没有 HSTS？**  
A: 自签名 catch-all 不下发 HSTS，避免锁定本地测试域名；真实站点请用 `security-headers-common.conf`。
