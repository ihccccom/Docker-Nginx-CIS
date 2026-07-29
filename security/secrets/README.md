# Docker Secrets 管理

> **CIS Docker Benchmark 5.22** — 确保不在容器中存储密钥（Secrets）

## 目录

- [什么是 Docker Secrets](#什么是-docker-secrets)
- [为什么不能使用环境变量](#为什么不能使用环境变量)
- [文件说明](#文件说明)
- [创建 Secrets](#创建-secrets)
- [在 docker-compose 中使用](#在-docker-compose-中使用)
- [在容器内访问 Secrets](#在容器内访问-secrets)
- [SSL 证书和密钥管理](#ssl-证书和密钥管理)
- [Secrets 轮换策略](#secrets-轮换策略)
- [完整工作流示例](#完整工作流示例)
- [最佳实践](#最佳实践)

---

## 什么是 Docker Secrets

Docker Secrets 是 Docker 提供的安全密钥管理机制，用于在容器运行时安全地传递敏感信息（如 SSL 证书、密码、API 密钥等）。Secrets 以 tmpfs 内存文件系统的形式挂载到容器的 `/run/secrets/` 目录，不会写入磁盘，也不会出现在镜像层中。

**核心特性**：

| 特性 | 说明 |
|------|------|
| 加密存储 | Secrets 在 Swarm 集群中以加密形式存储在 Raft 日志中 |
| 内存挂载 | 以 tmpfs 挂载到容器内，不落盘 |
| 最小权限 | 仅授权的容器可以访问指定的 Secrets |
| 不可变性 | Secrets 创建后不可修改，只能删除后重建 |
| 透明传输 | 通过 TLS 加密通道在集群节点间传输 |

## 为什么不能使用环境变量

| 对比项 | 环境变量 ❌ | Docker Secrets ✅ |
|--------|-----------|------------------|
| 存储位置 | 进程环境，可被 `/proc/*/environ` 读取 | tmpfs 内存文件系统 |
| 镜像历史 | `docker history` 可能暴露 | 不存在于镜像中 |
| inspect 可见 | `docker inspect` 明文显示 | `docker inspect` 不显示内容 |
| 日志泄露 | 调试日志可能打印环境变量 | 文件路径不会被意外打印 |
| 子进程继承 | 自动继承所有环境变量 | 需要显式挂载 |
| 传输安全 | 明文传递 | TLS 加密传输（Swarm 模式） |
| 权限控制 | 无细粒度控制 | 可指定哪些服务可以访问 |

**风险示例**：

```bash
# 环境变量方式（不安全！）
docker run -e "DB_PASSWORD=secret123" nginx

# 任何有 docker 权限的用户都能看到密码
docker inspect <container_id> | grep DB_PASSWORD
```

## 文件说明

### `docker-compose-secrets.yml`

Docker Compose Secrets 集成示例，展示如何在 Compose 环境中定义和使用 Secrets：

```yaml
services:
  nginx:
    image: nginx-hardened:latest
    secrets:
      - ssl_certificate
      - ssl_certificate_key
      - dhparam

secrets:
  ssl_certificate:
    file: ./certs/server.crt
  ssl_certificate_key:
    file: ./certs/server.key
  dhparam:
    file: ./certs/dhparam.pem
```

## 创建 Secrets

### 方式一：从文件创建（推荐）

```bash
# 创建 SSL 证书 Secret
docker secret create ssl_certificate ./certs/server.crt

# 创建 SSL 密钥 Secret
docker secret create ssl_certificate_key ./certs/server.key

# 创建 DH 参数 Secret
docker secret create dhparam ./certs/dhparam.pem
```

### 方式二：从标准输入创建

```bash
# 从管道创建（密码不出现在命令行历史中）
echo -n "my_secure_password" | docker secret create db_password -

# 从文件内容创建
cat /path/to/secret_file | docker secret create my_secret -
```

### 方式三：使用 Docker Compose（开发环境）

在非 Swarm 模式下，Docker Compose 支持基于文件的 Secrets：

```yaml
secrets:
  ssl_certificate:
    file: ./certs/server.crt    # 从本地文件读取
  ssl_certificate_key:
    file: ./certs/server.key
```

### 管理 Secrets

```bash
# 列出所有 Secrets
docker secret ls

# 查看 Secret 元数据（不显示内容）
docker secret inspect ssl_certificate

# 删除 Secret
docker secret rm ssl_certificate
```

## 在 docker-compose 中使用

### 基本用法

```yaml
version: "3.8"

services:
  nginx:
    image: nginx-hardened:latest
    ports:
      - "443:8443"
    secrets:
      - ssl_certificate
      - ssl_certificate_key
      - dhparam
    environment:
      # 告诉 entrypoint 脚本 Secrets 的位置
      SSL_CERT_PATH: /run/secrets/ssl_certificate
      SSL_KEY_PATH: /run/secrets/ssl_certificate_key

secrets:
  ssl_certificate:
    file: ./certs/server.crt
  ssl_certificate_key:
    file: ./certs/server.key
  dhparam:
    file: ./certs/dhparam.pem
```

### 高级用法：指定挂载路径和权限

```yaml
services:
  nginx:
    image: nginx-hardened:latest
    secrets:
      - source: ssl_certificate
        target: /run/secrets/ssl_cert
        uid: "101"        # nginx 用户 UID
        gid: "101"        # nginx 用户 GID
        mode: 0440        # 只读权限
      - source: ssl_certificate_key
        target: /run/secrets/ssl_key
        uid: "101"
        gid: "101"
        mode: 0400        # 仅所有者可读
```

### Swarm 模式用法

```yaml
secrets:
  ssl_certificate:
    external: true        # 引用已通过 docker secret create 创建的 Secret
  ssl_certificate_key:
    external: true
```

## 在容器内访问 Secrets

Secrets 挂载在容器的 `/run/secrets/` 目录下，以文件形式存在：

```bash
# 查看容器内的 Secrets
docker exec nginx-secure ls -la /run/secrets/

# 输出示例：
# -r--r----- 1 root root 1234 Jan 01 00:00 ssl_certificate
# -r-------- 1 root root  567 Jan 01 00:00 ssl_certificate_key
# -r--r----- 1 root root  424 Jan 01 00:00 dhparam
```

### 在 Nginx 配置中引用

```nginx
server {
    listen 8443 ssl;

    ssl_certificate     /run/secrets/ssl_certificate;
    ssl_certificate_key /run/secrets/ssl_certificate_key;
    ssl_dhparam         /run/secrets/dhparam;
}
```

### 在 entrypoint 脚本中读取

```bash
#!/bin/sh
# docker-entrypoint.sh

# 读取 Secret 文件内容
if [ -f /run/secrets/ssl_certificate ]; then
    echo "SSL certificate found"
    export SSL_CERT_PATH=/run/secrets/ssl_certificate
fi

if [ -f /run/secrets/ssl_certificate_key ]; then
    echo "SSL key found"
    export SSL_KEY_PATH=/run/secrets/ssl_certificate_key
fi
```

## SSL 证书和密钥管理

### 生成自签名证书（测试用）

```bash
# 生成私钥和证书
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout certs/server.key \
  -out certs/server.crt \
  -subj "/CN=localhost"

# 生成 DH 参数（推荐 2048 位或以上）
openssl dhparam -out certs/dhparam.pem 2048

# 设置正确的文件权限
chmod 600 certs/server.key
chmod 644 certs/server.crt
chmod 644 certs/dhparam.pem
```

### 使用 Let's Encrypt 证书

```bash
# 1. 获取证书
certbot certonly --standalone -d example.com

# 2. 创建 Secrets
docker secret create ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem
docker secret create ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem
```

### 证书文件权限要求

| 文件 | 权限 | 所有者 | 说明 |
|------|------|--------|------|
| `server.crt` | `0644` / `0440` | root:nginx | 证书可被 Nginx worker 读取 |
| `server.key` | `0600` / `0400` | root:root | 私钥仅 root 可读 |
| `dhparam.pem` | `0644` / `0440` | root:nginx | DH 参数可被读取 |

## Secrets 轮换策略

Docker Secrets 创建后不可修改，轮换需要以下步骤：

### 手动轮换流程

```bash
# 1. 创建新版本的 Secret（使用版本化命名）
docker secret create ssl_certificate_v2 ./certs/new-server.crt
docker secret create ssl_certificate_key_v2 ./certs/new-server.key

# 2. 更新服务使用新 Secret
docker service update \
  --secret-rm ssl_certificate \
  --secret-add source=ssl_certificate_v2,target=ssl_certificate \
  --secret-rm ssl_certificate_key \
  --secret-add source=ssl_certificate_key_v2,target=ssl_certificate_key \
  nginx-service

# 3. 验证新证书生效
openssl s_client -connect localhost:443 -servername example.com </dev/null 2>/dev/null | \
  openssl x509 -noout -dates

# 4. 删除旧 Secret
docker secret rm ssl_certificate ssl_certificate_key
```

### Docker Compose 轮换

```bash
# 1. 更新 Compose 文件中的证书路径
# 2. 重新部署
docker compose down
docker compose up -d

# 3. 验证
docker exec nginx-secure openssl x509 -in /run/secrets/ssl_certificate -noout -dates
```

### 自动化轮换脚本

```bash
#!/bin/bash
# rotate-secrets.sh

CERT_DIR="./certs"
DATE=$(date +%Y%m%d)

# 续期证书
certbot renew --quiet

# 重新创建 Secrets
docker secret rm ssl_certificate ssl_certificate_key 2>/dev/null
docker secret create ssl_certificate ${CERT_DIR}/fullchain.pem
docker secret create ssl_certificate_key ${CERT_DIR}/privkey.pem

# 滚动更新服务
docker service update --force nginx-service

echo "[${DATE}] Secrets rotated successfully"
```

建议配置 crontab 定期执行：

```bash
# 每月 1 日凌晨 3 点轮换证书
0 3 1 * * /path/to/rotate-secrets.sh >> /var/log/secret-rotation.log 2>&1
```

## 完整工作流示例

以下是从零开始配置 Docker Secrets 的完整步骤：

### 步骤 1：准备证书文件

```bash
mkdir -p certs

# 生成证书（生产环境使用 Let's Encrypt 或 CA 签发的证书）
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout certs/server.key \
  -out certs/server.crt \
  -subj "/CN=example.com"

openssl dhparam -out certs/dhparam.pem 2048
```

### 步骤 2：构建安全镜像

```bash
docker build -t nginx-hardened:latest .
```

### 步骤 3：使用 Docker Compose 部署

```bash
# 使用 Secrets 配置启动
docker compose -f docker-compose-secrets.yml up -d
```

### 步骤 4：验证 Secrets 已正确挂载

```bash
# 检查 Secrets 文件
docker exec nginx-secure ls -la /run/secrets/

# 验证 SSL 连接
curl -k https://localhost:8443/
```

### 步骤 5：验证安全性

```bash
# 确认环境变量中没有敏感信息
docker inspect nginx-secure | grep -i "password\|secret\|key"

# 确认 Secrets 不在镜像层中
docker history nginx-hardened:latest
```

## 最佳实践

| 实践 | 说明 |
|------|------|
| ✅ 使用 Docker Secrets 而非环境变量 | 环境变量易被 inspect、日志等暴露 |
| ✅ 设置最严格的文件权限 | 私钥使用 `0400`，证书使用 `0440` |
| ✅ 使用版本化命名 | `ssl_cert_v1`、`ssl_cert_v2` 便于轮换 |
| ✅ 定期轮换 Secrets | 建议至少每 90 天轮换一次 |
| ✅ 使用 `.dockerignore` 排除证书目录 | 避免证书被打包到镜像中 |
| ✅ 在 CI/CD 中安全注入 Secrets | 使用 CI/CD 平台的密钥管理功能 |
| ❌ 不要在 Dockerfile 中硬编码密钥 | `ENV PASSWORD=xxx` 会留在镜像层中 |
| ❌ 不要在构建参数中传递密钥 | `--build-arg` 同样会留在镜像历史中 |
| ❌ 不要将证书提交到版本控制 | 使用 `.gitignore` 排除证书文件 |
| ❌ 不要在日志中打印 Secret 内容 | 避免 `cat /run/secrets/*` 等操作 |

---

## 参考资料

- [CIS Docker Benchmark v1.6.0 — 5.22](https://www.cisecurity.org/benchmark/docker)
- [Docker Secrets 文档](https://docs.docker.com/engine/swarm/secrets/)
- [Docker Compose Secrets](https://docs.docker.com/compose/how-tos/use-secrets/)
- [OWASP Secrets Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
