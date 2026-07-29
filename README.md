# Nginx Docker 安全部署方案

基于 CIS Docker Benchmark、CIS Nginx Benchmark 和 PCI DSS v4.0 标准的 Nginx 安全容器化部署方案。

## 目录

- [项目概述](#项目概述)
- [目录结构](#目录结构)
- [快速开始](#快速开始)
- [部署教程](#部署教程)
  - [GitHub Actions 构建与 Docker Hub 拉取教程](#github-actions-构建与-docker-hub-拉取教程)
  - [本地构建教程](#本地构建教程)
- [安全基准实现](#安全基准实现)
- [架构图](#架构图)
- [构建参数](#构建参数)
- [卷挂载说明](#卷挂载说明)
- [安全配置详情](#安全配置详情)
- [性能调优](#性能调优)
- [常见问题](#常见问题)
- [许可证](#许可证)

---

## 项目概述

本项目提供一套**生产级**的 Nginx Docker 安全部署方案，目标是：

- ✅ 通过 **CIS Docker Benchmark v1.6.0** 安全检查（覆盖 70+ 检查项）
- ✅ 符合 **CIS Nginx Benchmark v2.0.1** 安全配置（覆盖率 94%）
- ✅ 满足 **PCI DSS v4.0** 合规要求
- ✅ 集成 **ModSecurity WAF**（OWASP CRS 规则集）
- ✅ 实施 **纵深防御**：Seccomp + AppArmor + Capabilities 限制 + 非 root 运行
- ✅ 提供完整的**审计日志**和**监控**方案
- ✅ 支持 **Docker Secrets** 安全管理 SSL 证书和密钥

**核心安全特性**：

| 安全层面 | 实现方式 | 效果 |
|---------|---------|------|
| 内核级防护 | Seccomp + AppArmor | 系统调用白名单 + 强制访问控制 |
| 容器级防护 | 非 root + 只读文件系统 + Capabilities 限制 | 最小权限原则 |
| 应用级防护 | ModSecurity WAF + 安全头 + TLS 1.2/1.3 | Web 应用防火墙 + 传输加密 |
| 运维级防护 | 审计日志 + Docker Secrets + 健康检查 | 安全运维 |

## 目录结构

```
.github/
└── workflows/
    └── docker-build-push.yml          # GitHub Actions 构建并发布到 Docker Hub

nginx/
├── Dockerfile                         # 多阶段 Docker 构建（源码编译 Nginx + ModSecurity）
├── docker-compose.yml                 # Docker Compose - 本地构建用
├── docker-compose.ghcr.yml            # Docker Compose - 拉取 Docker Hub 预构建镜像用
├── docker-entrypoint.sh               # 容器入口脚本（权限检查）
├── .dockerignore                      # 构建上下文排除规则
├── README.md                          # 📖 编译构建教程（本文件）
├── DOCKER-USAGE.md                    # 📖 Docker 使用教程（可独立发布）
│
├── conf/                              # Nginx 配置文件（内置，构建时 COPY 到镜像）
│   ├── nginx.conf                    # Nginx 主配置文件
│   ├── proxy.conf                    # 反向代理和缓存配置
│   ├── index.html                    # 默认首页
│   ├── php/
│   │   ├── pathinfo.conf            # PHP Pathinfo 支持
│   │   └── enable-php-84.conf       # PHP 8.4 FastCGI 配置
│   └── modsecurity/
│       ├── modsecurity.conf         # ModSecurity 主配置
│       ├── main.conf                # OWASP 规则引入配置
│       ├── crs-setup.conf           # OWASP CRS 偏好设置
│       ├── hosts.allow              # IP 白名单
│       └── hosts.deny               # IP 黑名单
│
├── security/                          # 安全配置目录
│   ├── seccomp/
│   │   ├── nginx-seccomp.json        # Seccomp 系统调用白名单
│   │   └── README.md                 # 📖 Seccomp 配置说明
│   ├── apparmor/
│   │   ├── nginx-apparmor-profile    # AppArmor 强制访问控制策略
│   │   └── README.md                 # 📖 AppArmor 配置说明
│   ├── secrets/
│   │   ├── docker-compose-secrets.yml # Docker Secrets 集成示例
│   │   └── README.md                 # 📖 Secrets 管理说明
│   ├── audit/
│   │   ├── docker-audit.rules        # Auditd 审计规则
│   │   ├── daemon.json               # Docker 守护进程安全配置
│   │   ├── daemon.json.comments      # daemon.json 配置项注释说明
│   │   └── README.md                 # 📖 日志与审计说明
│   ├── cis-docker-benchmark/
│   │   ├── docker-bench-check.sh     # CIS Docker Benchmark 自动检查脚本
│   │   └── README.md                 # 📖 CIS Docker 基准清单
│   ├── cis-nginx-benchmark/
│   │   └── README.md                 # 📖 CIS Nginx 基准清单
│   ├── pci-dss/
│   │   └── README.md                 # 📖 PCI DSS 合规对照
│   └── performance/
│       └── README.md                 # 📖 性能调优指南
│
├── deploy/                            # 部署包（可发布到其他仓库供用户使用）
│   ├── README.md                     # Docker 使用教程
│   ├── docker-compose.yml            # 用户部署用 Compose 文件
│   └── security/                     # 安全配置（Seccomp/AppArmor）
│
└── tests/
    ├── validate.sh                   # 自动化安全验证脚本
    └── README.md                     # 📖 测试说明
```

## 快速开始

> 📖 **Docker 使用教程**（部署、配置、运维）已独立为 **[DOCKER-USAGE.md](DOCKER-USAGE.md)**，方便发布到其他仓库供用户使用。

### 方式一：使用预构建镜像（推荐 - 从 Docker Hub 拉取）

镜像由 GitHub Actions 自动构建并发布到 Docker Hub，无需本地编译。

```bash
cd nginx

# 拉取并启动（需先修改 docker-compose.ghcr.yml 中的镜像地址）
docker compose -f docker-compose.ghcr.yml up -d

# 查看容器状态
docker compose -f docker-compose.ghcr.yml ps

# 查看日志
docker compose -f docker-compose.ghcr.yml logs -f nginx
```

> 📖 详细教程请参阅下方 [GitHub Actions 构建与 Docker Hub 拉取教程](#github-actions-构建与-docker-hub-拉取教程)

### 方式二：本地构建

在本地从源码编译 Nginx 及所有模块（编译耗时约 15-30 分钟）。

```bash
cd nginx

# 构建镜像
docker compose build

# 启动容器
docker compose up -d
```

> 📖 详细教程请参阅下方 [本地构建教程](#本地构建教程)

### 验证部署

```bash
# 运行安全验证脚本
bash tests/validate.sh

# 手动验证 HTTP
curl http://localhost/

# 手动验证 HTTPS
curl -k https://localhost/

# 运行 CIS Docker 基准检查
sudo bash security/cis-docker-benchmark/docker-bench-check.sh
```

### 查看日志

```bash
docker logs nginx
```

---

## 部署教程

### GitHub Actions 构建与 Docker Hub 拉取教程

#### 概述

本项目提供 GitHub Actions 工作流（`.github/workflows/docker-build-push.yml`），自动编译 Nginx Docker 镜像并发布到 Docker Hub。你只需在本地拉取预构建好的镜像即可使用，无需本地编译。

**优势**：
- ✅ 无需本地编译，节省时间和资源
- ✅ 自动化构建，每次代码更新自动发布新镜像
- ✅ 支持多架构（amd64/arm64）
- ✅ 支持版本标签管理

#### 步骤 1：配置 GitHub Secrets

在仓库 **Settings** → **Secrets and variables** → **Actions** 中添加：

| Secret 名称 | 说明 |
|-------------|------|
| `DOCKERHUB_USERNAME` | Docker Hub 用户名（例如 `ihccccom`） |
| `DOCKERHUB_TOKEN` | Docker Hub Access Token（在 Docker Hub → Account Settings → Security 中创建） |

> ⚠️ 三个镜像（Nginx、PHP-FPM、Redis）共用同一组 Secrets，只需配置一次。

#### 步骤 2：启用 GitHub Actions

确保仓库的 GitHub Actions 已启用：
1. 进入仓库页面 → **Settings** → **Actions** → **General**
2. 选择 **Allow all actions and reusable workflows**
3. 在 **Workflow permissions** 中选择 **Read and write permissions**

#### 步骤 3：触发构建

构建会在以下情况自动触发：
- 推送到 `main` 分支且 `nginx/Dockerfile`、`nginx/docker-entrypoint.sh`、`nginx/.dockerignore` 有变更
- 创建版本标签（如 `v1.0.0`）

也可以手动触发：
1. 进入仓库页面 → **Actions** → **Build and Push Nginx Docker Image**
2. 点击 **Run workflow**
3. 可选择配置 Nginx 版本、OpenSSL 版本、是否启用 ModSecurity 等
4. 点击 **Run workflow** 开始构建

#### 步骤 4：设置仓库可见性（公开仓库可跳过）

如果仓库是 **Public**（公开），任何人都可以直接拉取镜像，无需额外设置。

如果仓库是 **Private**（私有），需要创建 Personal Access Token：
1. 进入 GitHub → **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. 点击 **Generate new token (classic)**
3. 勾选 `read:packages` 权限
4. 生成并保存 Token

#### 步骤 5：本地登录 Docker Hub（私有仓库需要）

```bash
# 公开仓库可跳过此步骤
# 将 Token 保存到文件，避免在命令行直接暴露
echo "你的TOKEN" > ~/.dockerhub_token
cat ~/.dockerhub_token | docker login -u 你的DockerHub用户名 --password-stdin
rm ~/.dockerhub_token
```

#### 步骤 6：本地拉取并运行

```bash
cd nginx

# 方式一：使用 docker-compose.ghcr.yml（推荐）
# 先编辑 docker-compose.ghcr.yml，修改 image 为你的镜像地址
# image: ihccccom/nginx:latest
docker compose -f docker-compose.ghcr.yml up -d

# 方式二：手动拉取并运行
docker pull ihccccom/nginx:latest
docker run -d -p 80:80 -p 443:443 --name nginx ihccccom/nginx:latest
```

#### 步骤 7：验证

```bash
# 检查容器状态
docker ps

# 测试 HTTP 响应
curl http://localhost/

# 查看日志
docker logs nginx
```

#### 版本标签说明

| 标签格式 | 触发条件 | 示例 |
|---------|---------|------|
| `latest` | 推送到 main 分支 | `nginx:latest` |
| `v1.0.0` | 创建 v1.0.0 标签 | `nginx:v1.0.0` |
| `1.0` | 创建 v1.0.x 标签 | `nginx:1.0` |
| `nginx-1.28.2` | 所有构建 | `nginx:nginx-1.28.2` |

---

### 本地构建教程

#### 概述

在本地从源码编译构建 Nginx Docker 镜像，适用于需要自定义编译选项或无法访问 Docker Hub 的场景。

**注意**：编译过程需要下载源码并编译，首次构建耗时约 **15-30 分钟**（取决于网络和 CPU）。

#### 步骤 1：克隆仓库

```bash
git clone https://github.com/mzwrt/copilot.git
cd copilot/nginx
```

#### 步骤 2：（可选）自定义构建参数

编辑 `docker-compose.yml`，取消注释并修改 `args` 部分：

```yaml
services:
  nginx:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        NGINX_VERSION: "1.28.2"
        OPENSSL_VERSION: "3.5.5"
        USE_modsecurity: "true"
        USE_owasp: "true"
        NGINX_FAKE_NAME: "MyServer"
```

或者通过命令行传入构建参数：

```bash
docker compose build --build-arg NGINX_FAKE_NAME="MyServer" --build-arg USE_modsecurity=false
```

#### 步骤 3：构建镜像

```bash
# 使用 docker compose 构建
docker compose build

# 或直接使用 docker build
docker build -t nginx:latest .
```

#### 步骤 4：启动容器

```bash
# 使用 docker compose 启动
docker compose up -d

# 查看状态
docker compose ps

# 查看日志
docker compose logs -f nginx
```

#### 步骤 5：验证

```bash
# HTTP 测试
curl http://localhost/

# HTTPS 测试（自签名证书）
curl -k https://localhost/

# 运行安全检查
bash tests/validate.sh
```

#### 步骤 6：管理容器

```bash
# 停止
docker compose down

# 重启
docker compose restart nginx

# 查看卷数据
docker volume ls | grep nginx

# 进入容器调试
docker exec -it nginx /bin/bash
```

## 安全基准实现

### CIS Docker Benchmark v1.6.0

覆盖 **70+** 检查项，包括主机配置、守护进程配置、镜像构建和容器运行时安全。

➡️ [详细清单](security/cis-docker-benchmark/README.md)

| 章节 | 覆盖 | 关键实现 |
|------|------|---------|
| 1.x 主机配置 | 10/12 | 审计规则 |
| 2.x 守护进程配置 | 16/18 | daemon.json 安全配置 |
| 3.x 配置文件 | 22/22 | 文件权限指南 |
| 4.x 镜像构建 | 10/12 | 多阶段构建 + 非 root |
| 5.x 容器运行时 | 28/32 | Seccomp + AppArmor + 资源限制 |

### CIS Nginx Benchmark v2.0.1

覆盖 **32/34** 检查项，覆盖率 **94%**。

➡️ [详细清单](security/cis-nginx-benchmark/README.md)

| 章节 | 覆盖 | 关键实现 |
|------|------|---------|
| 2.x 基础配置 | 16/18 | 模块最小化 + TLS 加固 |
| 3.x 日志配置 | 7/7 | 详细日志格式 + 远程传输 |
| 4.x 代理安全 | 5/5 | 安全响应头 |
| 5.x 信息泄露 | 4/4 | 版本隐藏 + 文件访问控制 |

### PCI DSS v4.0

覆盖 **10/12** 大项要求。

➡️ [详细对照](security/pci-dss/README.md)

### 其他安全机制

| 安全机制 | 说明 | 详细文档 |
|---------|------|---------|
| Seccomp | 系统调用白名单，阻止危险操作 | [查看](security/seccomp/README.md) |
| AppArmor | 强制访问控制，限制文件和网络访问 | [查看](security/apparmor/README.md) |
| Docker Secrets | 安全管理 SSL 证书和密钥 | [查看](security/secrets/README.md) |
| 审计日志 | auditd + Docker 日志 + Nginx 日志 | [查看](security/audit/README.md) |
| 性能调优 | Worker 进程 + 缓存 + 压缩优化 | [查看](security/performance/README.md) |
| 自动化测试 | 39 项安全验证检查 | [查看](tests/README.md) |

## 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                        宿主机 (Host)                         │
│                                                             │
│  ┌─ auditd ──────────────────────────────────────────────┐  │
│  │  监控 Docker 文件、二进制、套接字的所有访问操作          │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌─ Docker Daemon ──────────────────────────────────────┐   │
│  │  daemon.json: icc=false, no-new-privileges,          │   │
│  │  userns-remap, log-driver, live-restore              │   │
│  │                                                      │   │
│  │  ┌─ AppArmor ─────────────────────────────────────┐  │   │
│  │  │  强制访问控制: 文件路径 + 网络 + Capabilities    │  │   │
│  │  │                                                │  │   │
│  │  │  ┌─ Seccomp ────────────────────────────────┐  │  │   │
│  │  │  │  系统调用白名单: ~80 个允许的 syscalls     │  │  │   │
│  │  │  │                                          │  │  │   │
│  │  │  │  ┌─ Container ───────────────────────┐   │  │  │   │
│  │  │  │  │                                   │   │  │  │   │
│  │  │  │  │  cap_drop: ALL                    │   │  │  │   │
│  │  │  │  │  cap_add: 最小必要集               │   │  │  │   │
│  │  │  │  │  read_only: true                  │   │  │  │   │
│  │  │  │  │  no-new-privileges: true          │   │  │  │   │
│  │  │  │  │                                   │   │  │  │   │
│  │  │  │  │  ┌─ Nginx Master (root→受限) ──┐  │   │  │  │   │
│  │  │  │  │  │                             │  │   │  │  │   │
│  │  │  │  │  │  ┌─ Worker (nginx用户) ──┐  │  │   │  │  │   │
│  │  │  │  │  │  │  ModSecurity WAF      │  │  │   │  │  │   │
│  │  │  │  │  │  │  TLS 1.2/1.3          │  │  │   │  │  │   │
│  │  │  │  │  │  │  安全响应头            │  │  │   │  │  │   │
│  │  │  │  │  │  │  速率限制              │  │  │   │  │  │   │
│  │  │  │  │  │  └──────────────────────┘  │  │   │  │  │   │
│  │  │  │  │  └────────────────────────────┘  │   │  │  │   │
│  │  │  │  │                                   │   │  │  │   │
│  │  │  │  │  tmpfs: /var/cache, /var/run, /tmp│   │  │  │   │
│  │  │  │  │  secrets: /run/secrets/ (tmpfs)   │   │  │  │   │
│  │  │  │  └───────────────────────────────────┘   │  │  │   │
│  │  │  └──────────────────────────────────────────┘  │  │   │
│  │  └────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  端口映射: 80→80 (HTTP), 443→443 (HTTPS)                    │
└─────────────────────────────────────────────────────────────┘
```

## 构建参数

### 插件开关

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `USE_modsecurity` | `true` | 启用 ModSecurity WAF |
| `USE_owasp` | `true` | 启用 OWASP CRS 规则集 |
| `USE_modsecurity_nginx` | `true` | 启用 ModSecurity-Nginx 连接器 |
| `USE_ngx_brotli` | `true` | 启用 Brotli 压缩模块 |
| `USE_openssl` | `true` | 使用自编译 OpenSSL |
| `USE_PCRE2` | `true` | 启用 PCRE2 正则模块 |
| `USE_ngx_cache_purge` | `true` | 启用缓存清除模块 |
| `USE_ngx_http_headers_more_filter_module` | `true` | 启用自定义响应头模块 |
| `USE_ngx_http_proxy_connect_module` | `true` | 启用正向代理 CONNECT 模块 |
| `USE_ngx_fancyindex` | `false` | 启用美化目录浏览模块 |

### 版本配置（留空自动获取最新版）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `NGINX_VERSION` | `1.28.2` | Nginx 版本号（必须指定） |
| `OPENSSL_VERSION` | `3.5.5` | OpenSSL 版本号（必须指定） |
| `PCRE2_VERSION` | `""` | PCRE2 版本，留空自动获取最新版 |
| `FANCYINDEX_VERSION` | `0.5.2` | ngx-fancyindex 版本号 |
| `NGX_CACHE_PURGE_VERSION` | `""` | ngx_cache_purge 版本，留空自动获取 |
| `HEADERS_MORE_VERSION` | `""` | headers-more 版本，留空自动获取 |
| `PROXY_CONNECT_VERSION` | `""` | proxy_connect 版本，留空自动获取 |
| `MODSECURITY_NGINX_VERSION` | `""` | ModSecurity-nginx 版本，留空使用最新 |
| `OWASP_CRS_VERSION` | `""` | OWASP CRS 版本，留空自动获取最新 |

### 其他配置

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `NGINX_FAKE_NAME` | `"CloudFlare"` | 自定义服务器名称（伪装），留空使用默认值 |
| `NGINX_VERSION_NUMBER` | `"8.2.6"` | 自定义版本号（伪装 nginx.h 中的版本），留空使用默认版本号 |
| `EXTRA_CC_OPT` | `""` | 额外 C 编译选项 |
| `EXTRA_NGINX_MODULES` | `""` | 额外 Nginx 模块参数（如 `--add-module=/path/to/mod`） |

**自定义构建示例**：

```bash
# 基本构建
docker build -t nginx:latest ./nginx/

# 禁用 ModSecurity
docker build --build-arg USE_modsecurity=false -t nginx:latest ./nginx/

# 自定义服务器名称和伪装版本号
docker build --build-arg NGINX_FAKE_NAME="MyServer" --build-arg NGINX_VERSION_NUMBER="5.1.24" -t nginx:latest ./nginx/

# 指定特定插件版本
docker build --build-arg HEADERS_MORE_VERSION="0.37" --build-arg OWASP_CRS_VERSION="v4.7.0" -t nginx:latest ./nginx/

# 添加额外自定义模块
docker build --build-arg EXTRA_NGINX_MODULES="--add-module=/opt/nginx/src/my_module" -t nginx:latest ./nginx/
```

## 卷挂载说明

| 卷名 | 容器路径 | 说明 |
|------|---------|------|
| `nginx-conf` | `/opt/nginx/conf` | Nginx 配置文件 |
| `nginx-confd` | `/opt/nginx/conf.d` | 网站配置文件（sites-available/sites-enabled） |
| `nginx-ssl` | `/opt/nginx/ssl` | SSL 证书文件 |
| `nginx-logs` | `/opt/nginx/logs` | 日志文件 |
| `wwwroot` | `/www/wwwroot` | 网站根目录 |
| `owasp` | `/opt/owasp` | OWASP 规则集 |
| `nginx-cache` | `/var/cache/nginx` | Nginx 缓存目录 |

## 安全配置详情

### 容器运行时安全

docker-compose.yml 中已配置以下安全选项：

```yaml
services:
  nginx:
    # 限制 Capabilities
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE  # 绑定 80/443 端口
      - CHOWN             # 修改文件属主
      - SETUID            # 切换用户（master→worker）
      - SETGID            # 切换用户组
      - DAC_OVERRIDE      # 文件权限覆盖

    # 安全选项
    security_opt:
      - no-new-privileges:true
      # - seccomp=./security/seccomp/nginx-seccomp.json
      # - apparmor=docker-nginx

    # 资源限制
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '4.0'
          pids: 200
        reservations:
          memory: 256M
          cpus: '0.5'

    # 健康检查
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://127.0.0.1/"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
```

## 性能调优

本项目提供完整的性能调优指南，涵盖：

| 调优维度 | 关键参数 | 详情 |
|---------|---------|------|
| 进程模型 | `worker_processes`、`worker_connections` | [查看](security/performance/README.md#worker-进程调优) |
| 内存管理 | Buffer 大小、缓存配置 | [查看](security/performance/README.md#buffer-大小调优) |
| 网络优化 | `sendfile`、`tcp_nopush`、`tcp_nodelay` | [查看](security/performance/README.md#tcp-优化) |
| 压缩 | Gzip、Brotli 配置 | [查看](security/performance/README.md#压缩调优) |
| Docker 资源 | CPU、内存、PID 限制 | [查看](security/performance/README.md#docker-资源限制) |
| 缓存 | 代理缓存、浏览器缓存 | [查看](security/performance/README.md#缓存优化) |

**快速公式**：

```
最大并发连接数 = worker_processes × worker_connections
内存使用量 ≈ worker_processes × worker_connections × 54KB
```

## 常见问题

### Q: 容器启动后立即退出

**A**: 检查日志 `docker logs nginx`，常见原因：
1. SSL 证书文件未挂载或路径错误
2. Seccomp Profile 缺少必要的系统调用
3. 文件权限不正确

### Q: HTTPS 证书错误

**A**: 确保证书路径正确且权限符合要求：
```bash
# 使用 Docker Secrets 管理证书
docker compose -f security/secrets/docker-compose-secrets.yml up -d

# 或检查默认自签名证书
docker exec nginx ls -la /opt/nginx/ssl/default/
```

### Q: ModSecurity WAF 误报

**A**: 查看 ModSecurity 审计日志找到规则 ID，然后添加排除规则：
```nginx
SecRuleRemoveById 942100  # 排除特定规则
```

### Q: 如何更新 Nginx 版本

**A**: 修改 Dockerfile 中的 `NGINX_VERSION` 参数并重新构建：
```bash
docker build --build-arg NGINX_VERSION=1.28.2 -t nginx:latest ./nginx/
```

或使用 GitHub Actions 手动触发构建时指定版本。

### Q: 如何在生产环境部署

**A**: 推荐步骤：
1. 使用 GitHub Actions 构建镜像，通过 Docker Hub 拉取到生产服务器
2. 配置正式 SSL 证书（Let's Encrypt 或 CA 签发）
3. 加载 AppArmor Profile 到所有节点
4. 配置 daemon.json 安全选项
5. 安装 auditd 审计规则
6. 配置集中日志收集（ELK/Fluentd）
7. 运行验证脚本确认配置

### Q: 性能基准测试数据

**A**: 在 4 核 CPU / 8GB 内存环境下的参考数据：

| 场景 | QPS | P99 延迟 |
|------|-----|---------|
| 静态文件 (1KB) | ~30,000 | < 5ms |
| 静态文件 (100KB) | ~15,000 | < 10ms |
| 反向代理 | ~10,000 | < 20ms |
| WAF 启用 + 反向代理 | ~6,000 | < 35ms |

## 许可证

本项目遵循 [MIT License](../LICENSE)。

---

## 参考资料

- [CIS Docker Benchmark v1.6.0](https://www.cisecurity.org/benchmark/docker)
- [CIS Nginx Benchmark v2.0.1](https://www.cisecurity.org/benchmark/nginx)
- [PCI DSS v4.0](https://www.pcisecuritystandards.org/)
- [Docker 安全最佳实践](https://docs.docker.com/engine/security/)
- [Nginx 安全加固指南](https://nginx.org/en/docs/)
- [OWASP ModSecurity CRS](https://coreruleset.org/)
