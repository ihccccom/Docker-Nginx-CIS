# 性能调优与进程调优

## 目录

- [概述](#概述)
- [Worker 进程调优](#worker-进程调优)
  - [worker_processes 配置](#worker_processes-配置)
  - [worker_connections 配置](#worker_connections-配置)
  - [最大并发客户端数](#最大并发客户端数)
- [内存使用估算](#内存使用估算)
- [Keepalive 超时优化](#keepalive-超时优化)
- [Buffer 大小调优](#buffer-大小调优)
- [文件描述符限制](#文件描述符限制)
- [TCP 优化](#tcp-优化)
- [压缩调优](#压缩调优)
- [Docker 资源限制](#docker-资源限制)
- [缓存优化](#缓存优化)
- [场景化配置示例](#场景化配置示例)
- [性能测试方法](#性能测试方法)

---

## 概述

Nginx 性能调优是一个系统工程，需要从进程模型、网络参数、内存管理、缓存策略等多个维度综合考虑。在容器化环境中，还需要将 Docker 资源限制纳入调优范围。

**性能调优核心公式**：

```
最大并发连接数 = worker_processes × worker_connections
内存使用量 ≈ worker_processes × worker_connections × (请求缓冲 + 响应缓冲)
```

## Worker 进程调优

### worker_processes 配置

`worker_processes` 决定 Nginx 启动多少个工作进程来处理请求。

**核心公式**：

```
worker_processes = CPU 核心数
```

| 配置值 | 适用场景 | 说明 |
|--------|---------|------|
| `auto` | 通用（推荐） | 自动检测 CPU 核心数 |
| `1` | 单核 CPU 或轻量应用 | 最小开销 |
| `2-4` | 小型应用 | 2-4 核 CPU |
| `8-16` | 中大型应用 | 8-16 核 CPU |
| `CPU 核心数 × 2` | CPU 密集型 + I/O 密集型 | SSL 解密等场景 |

**配置示例**：

```nginx
# 推荐：自动检测
worker_processes auto;

# 手动设置
worker_processes 4;

# 绑定 CPU 亲和性（减少上下文切换）
worker_cpu_affinity auto;
# 或手动绑定
worker_cpu_affinity 0001 0010 0100 1000;  # 4 核 CPU
```

**在容器中获取 CPU 数量**：

```bash
# 查看分配的 CPU 核心数
nproc
# 或
cat /proc/cpuinfo | grep processor | wc -l

# 在 Docker 中查看 CPU 限制
cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us
cat /sys/fs/cgroup/cpu/cpu.cfs_period_us
# 有效 CPU 数 = quota / period
```

> ⚠️ **注意**：在容器中使用 `auto` 时，Nginx 可能检测到宿主机的全部 CPU 核心数。如果使用 Docker CPU 限制（如 `cpus: 2`），建议手动设置 `worker_processes` 与限制匹配。

### worker_connections 配置

`worker_connections` 决定每个 worker 进程能处理的最大并发连接数。

**核心公式**：

```
worker_connections = (ulimit -n) / worker_processes
```

| 场景 | worker_connections | 说明 |
|------|-------------------|------|
| 小型站点 | `512` | 日均 PV < 10 万 |
| 中型站点 | `1024` | 日均 PV 10-100 万 |
| 大型站点 | `4096` | 日均 PV 100-1000 万 |
| 超大型站点 | `8192-65535` | 日均 PV > 1000 万 |

**配置示例**：

```nginx
events {
    worker_connections 1024;

    # 使用 epoll 事件模型（Linux 推荐）
    use epoll;

    # 允许一个 worker 同时接受多个连接
    multi_accept on;

    # 接受互斥锁（高并发时关闭可提升性能）
    accept_mutex off;
}
```

### 最大并发客户端数

**核心公式**：

```
max_clients = worker_processes × worker_connections
```

**反向代理场景**（每个客户端请求消耗 2 个连接——1 个客户端连接 + 1 个上游连接）：

```
max_clients = (worker_processes × worker_connections) / 2
```

**计算示例**：

| worker_processes | worker_connections | 静态文件场景 | 反向代理场景 |
|-----------------|-------------------|------------|------------|
| 1 | 512 | 512 | 256 |
| 2 | 1024 | 2,048 | 1,024 |
| 4 | 1024 | 4,096 | 2,048 |
| 4 | 4096 | 16,384 | 8,192 |
| 8 | 4096 | 32,768 | 16,384 |
| 16 | 8192 | 131,072 | 65,536 |

## 内存使用估算

**核心公式**：

```
内存使用 ≈ worker_processes × worker_connections × (request_buffer + response_buffer)
```

**各缓冲区默认大小**：

| 缓冲区 | 默认大小 | 说明 |
|--------|---------|------|
| `client_header_buffer_size` | 1 KB | 客户端请求头缓冲 |
| `large_client_header_buffers` | 4 × 8 KB = 32 KB | 大请求头缓冲 |
| `client_body_buffer_size` | 16 KB | 客户端请求体缓冲 |
| `proxy_buffer_size` | 4-8 KB | 代理响应头缓冲 |
| `proxy_buffers` | 8 × 4 KB = 32 KB | 代理响应体缓冲 |
| 每连接开销 | ~2-5 KB | Nginx 内部数据结构 |

**估算示例**：

```
场景：4 worker × 1024 connections
每连接内存 ≈ 1KB + 16KB + 32KB + 5KB = ~54 KB

最大内存使用 ≈ 4 × 1024 × 54 KB = ~216 MB

实际使用（通常只有 10-30% 连接活跃）：
实际内存 ≈ 216 MB × 0.2 = ~43 MB
```

| 场景 | 配置 | 估算最大内存 | 实际内存(20%活跃) |
|------|------|------------|------------------|
| 小型 | 2 × 512 | ~54 MB | ~11 MB |
| 中型 | 4 × 1024 | ~216 MB | ~43 MB |
| 大型 | 8 × 4096 | ~1.7 GB | ~345 MB |
| 超大型 | 16 × 8192 | ~6.9 GB | ~1.4 GB |

## Keepalive 超时优化

```nginx
http {
    # 客户端 Keepalive 超时
    keepalive_timeout 65;

    # 单个 Keepalive 连接允许的最大请求数
    keepalive_requests 100;

    # 上游 Keepalive 连接池大小
    upstream backend {
        server 10.0.0.1:8080;
        keepalive 32;            # 每个 worker 保持 32 个空闲连接
        keepalive_requests 1000; # 单个连接最大请求数
        keepalive_timeout 60s;   # 空闲超时
    }
}
```

**调优建议**：

| 参数 | 推荐值 | 说明 |
|------|--------|------|
| `keepalive_timeout` | `30-65` | CDN 场景可设低（15-30），直连场景 65 |
| `keepalive_requests` | `100-1000` | 高流量站点可增大 |
| upstream `keepalive` | `16-64` | 取决于上游服务器数量和流量 |
| `reset_timedout_connection` | `on` | 快速释放超时连接资源 |

## Buffer 大小调优

```nginx
http {
    # 客户端请求体缓冲区（POST 数据）
    client_body_buffer_size 16k;       # 一般 API：16k
    # client_body_buffer_size 128k;    # 文件上传场景

    # 客户端请求头缓冲区
    client_header_buffer_size 1k;
    large_client_header_buffers 4 8k;  # Cookie 较大时增加

    # 最大请求体大小
    client_max_body_size 1m;           # 安全限制
    # client_max_body_size 100m;       # 文件上传场景

    # 反向代理缓冲区
    proxy_buffer_size 4k;              # 响应头缓冲
    proxy_buffers 8 16k;               # 响应体缓冲
    proxy_busy_buffers_size 32k;       # 忙碌缓冲
    proxy_temp_file_write_size 64k;    # 临时文件写入大小

    # FastCGI 缓冲区（PHP 等）
    # fastcgi_buffer_size 4k;
    # fastcgi_buffers 8 16k;
}
```

**调优原则**：

| 场景 | client_body_buffer | proxy_buffers | 说明 |
|------|-------------------|---------------|------|
| API 网关 | `16k` | `8 × 16k` | 请求和响应都较小 |
| Web 应用 | `32k` | `8 × 32k` | 中等请求和响应 |
| 文件上传 | `128k` | `4 × 8k` | 大请求体，小响应 |
| 流媒体 | `8k` | `16 × 64k` | 小请求，大响应 |

## 文件描述符限制

每个网络连接消耗一个文件描述符，Nginx 还需要文件描述符用于日志文件、静态文件等。

**核心公式**：

```
worker_rlimit_nofile ≥ worker_connections × 2
```

```nginx
# 每个 worker 进程的最大文件描述符数
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
}
```

**系统级配置**：

```bash
# 查看当前限制
ulimit -n

# 临时设置
ulimit -n 65535

# 永久设置（/etc/security/limits.conf）
nginx soft nofile 65535
nginx hard nofile 65535

# 或在 Docker 中设置
docker run --ulimit nofile=65535:65535 nginx-hardened:latest
```

**docker-compose.yml 配置**：

```yaml
services:
  nginx:
    ulimits:
      nofile:
        soft: 65535
        hard: 65535
```

## TCP 优化

```nginx
http {
    # 启用 sendfile（零拷贝文件传输）
    sendfile on;

    # 启用 TCP_NOPUSH（与 sendfile 配合使用）
    # 将响应头和文件开头合并到一个 TCP 包中发送
    tcp_nopush on;

    # 启用 TCP_NODELAY（禁用 Nagle 算法）
    # 减少小数据包的延迟
    tcp_nodelay on;

    # 连接重置（释放超时连接资源）
    reset_timedout_connection on;
}
```

**TCP 优化参数说明**：

| 参数 | 值 | 效果 |
|------|---|------|
| `sendfile` | `on` | 文件传输绕过用户空间，性能提升约 **30-50%** |
| `tcp_nopush` | `on` | 减少 TCP 包数量，提升大文件传输效率 |
| `tcp_nodelay` | `on` | 减少延迟，适合 API 和小文件 |
| `reset_timedout_connection` | `on` | 快速释放超时连接，节省内存 |

**内核参数调优**（宿主机）：

```bash
# /etc/sysctl.conf
net.core.somaxconn = 65535              # 监听队列最大长度
net.core.netdev_max_backlog = 65535     # 网络设备积压队列大小
net.ipv4.tcp_max_syn_backlog = 65535    # SYN 队列大小
net.ipv4.tcp_tw_reuse = 1              # 允许 TIME-WAIT 套接字重用
net.ipv4.tcp_fin_timeout = 15          # FIN-WAIT-2 超时（默认 60 秒）
net.ipv4.tcp_keepalive_time = 300      # Keepalive 探测间隔
net.ipv4.tcp_keepalive_probes = 3      # Keepalive 探测次数
net.ipv4.tcp_keepalive_intvl = 15      # 探测间隔
net.ipv4.ip_local_port_range = 1024 65535  # 本地端口范围

# 应用配置
sudo sysctl -p
```

## 压缩调优

### Gzip 压缩

```nginx
http {
    # 启用 Gzip 压缩
    gzip on;

    # 压缩级别（1-9，推荐 4-6）
    gzip_comp_level 5;

    # 最小压缩大小（小于此值不压缩）
    gzip_min_length 256;

    # 压缩缓冲区
    gzip_buffers 16 8k;

    # 需要压缩的 MIME 类型
    gzip_types
        text/plain
        text/css
        text/javascript
        text/xml
        application/json
        application/javascript
        application/xml
        application/xml+rss
        application/x-javascript
        image/svg+xml;

    # 为代理请求启用压缩
    gzip_proxied any;

    # 在响应中添加 Vary: Accept-Encoding
    gzip_vary on;

    # 预压缩静态文件（需要 gzip_static 模块）
    gzip_static on;
}
```

**压缩级别对比**：

| 级别 | 压缩率 | CPU 开销 | 适用场景 |
|------|--------|---------|---------|
| 1-2 | 低 (~50%) | 极低 | CPU 密集型应用 |
| 3-4 | 中 (~60%) | 低 | 通用场景 |
| **5-6** | **较高 (~70%)** | **中等** | **推荐值** |
| 7-8 | 高 (~75%) | 较高 | 带宽受限场景 |
| 9 | 最高 (~78%) | 很高 | 极端带宽受限 |

> 💡 级别 5-6 是性价比最优选择。从 6 到 9 压缩率仅提升 ~5%，但 CPU 开销增加约 100%。

### Brotli 压缩（需编译模块）

```nginx
http {
    # 启用 Brotli 压缩
    brotli on;

    # 压缩级别（1-11，推荐 4-6）
    brotli_comp_level 6;

    # 最小压缩大小
    brotli_min_length 256;

    # 需要压缩的 MIME 类型
    brotli_types
        text/plain
        text/css
        text/javascript
        text/xml
        application/json
        application/javascript
        application/xml
        image/svg+xml;

    # 预压缩静态文件
    brotli_static on;
}
```

**Gzip vs Brotli 压缩率对比**：

| 文件类型 | 原始大小 | Gzip (级别 6) | Brotli (级别 6) | Brotli 优势 |
|---------|---------|---------------|----------------|------------|
| HTML | 100 KB | 28 KB | 23 KB | ~18% 更小 |
| CSS | 80 KB | 18 KB | 15 KB | ~17% 更小 |
| JavaScript | 200 KB | 62 KB | 51 KB | ~18% 更小 |
| JSON | 50 KB | 12 KB | 10 KB | ~17% 更小 |

## Docker 资源限制

Docker 资源限制与 Nginx 调优密切相关，需要协调配置。

### CPU 限制

```yaml
services:
  nginx:
    # CPU 限制
    cpus: '4.0'           # 限制使用 4 个 CPU 核心
    cpu_shares: 1024       # CPU 权重（默认 1024）

    # 或使用 deploy 配置
    deploy:
      resources:
        limits:
          cpus: '4.0'
        reservations:
          cpus: '2.0'
```

**CPU 限制与 worker_processes 的关系**：

| Docker cpus | 建议 worker_processes | 说明 |
|------------|----------------------|------|
| 1.0 | 1 | 单核限制 |
| 2.0 | 2 | 双核限制 |
| 4.0 | 4 | 四核限制 |
| 不限制 | auto | 使用全部核心 |

### 内存限制

```yaml
services:
  nginx:
    # 内存限制
    mem_limit: 512m        # 硬限制
    mem_reservation: 256m  # 软限制

    # 或使用 deploy 配置
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M
```

**内存限制与 Nginx 配置的关系**：

| Docker mem_limit | 建议 worker × connections | 估算活跃内存 |
|-----------------|--------------------------|------------|
| 128M | 1 × 512 | ~30 MB |
| 256M | 2 × 1024 | ~60 MB |
| 512M | 4 × 1024 | ~120 MB |
| 1G | 4 × 4096 | ~350 MB |
| 2G | 8 × 4096 | ~700 MB |

> ⚠️ 预留约 30-50% 内存给操作系统和 Nginx 共享库。

### PID 限制

```yaml
services:
  nginx:
    pids_limit: 100
```

**PID 限制公式**：

```
pids_limit ≥ worker_processes + master_process + cache_manager + cache_loader + 额外进程
pids_limit ≥ worker_processes + 10（预留）
```

### 文件描述符限制

```yaml
services:
  nginx:
    ulimits:
      nofile:
        soft: 65535
        hard: 65535
```

## 缓存优化

### 代理缓存

```nginx
http {
    # 定义缓存区域
    proxy_cache_path /var/cache/nginx/proxy
        levels=1:2                    # 两级目录结构
        keys_zone=proxy_cache:10m     # 内存中的键空间（10MB ≈ 80000 个键）
        max_size=1g                   # 磁盘缓存最大 1GB
        inactive=60m                  # 60 分钟未访问则淘汰
        use_temp_path=off;            # 不使用临时目录（减少 I/O）

    server {
        location / {
            proxy_cache proxy_cache;
            proxy_cache_valid 200 302 10m;   # 200/302 缓存 10 分钟
            proxy_cache_valid 404 1m;        # 404 缓存 1 分钟
            proxy_cache_use_stale error timeout updating http_500 http_502 http_503;
            proxy_cache_lock on;             # 防止缓存击穿
            proxy_cache_lock_timeout 5s;

            # 添加缓存状态头（调试用）
            add_header X-Cache-Status $upstream_cache_status;
        }
    }
}
```

### FastCGI 缓存

```nginx
http {
    fastcgi_cache_path /var/cache/nginx/fastcgi
        levels=1:2
        keys_zone=fastcgi_cache:10m
        max_size=512m
        inactive=30m;

    server {
        location ~ \.php$ {
            fastcgi_cache fastcgi_cache;
            fastcgi_cache_key "$scheme$request_method$host$request_uri";
            fastcgi_cache_valid 200 5m;
            fastcgi_cache_use_stale error timeout;
        }
    }
}
```

### 静态文件缓存

```nginx
server {
    # 浏览器缓存控制
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff2)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;                # 减少日志 I/O
    }

    # 打开文件缓存（减少 stat 系统调用）
    open_file_cache max=10000 inactive=60s;
    open_file_cache_valid 120s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;
}
```

**缓存效果预估**：

| 缓存类型 | 命中率 | 响应时间改善 | 上游负载降低 |
|---------|--------|------------|------------|
| 代理缓存 | 60-80% | 50-90% | 60-80% |
| FastCGI 缓存 | 40-70% | 70-95% | 40-70% |
| 浏览器缓存 | 80-95% | 99%（无请求） | 80-95% |
| 打开文件缓存 | 90%+ | 10-30%（减少 syscall） | 无 |

## 场景化配置示例

### 小型站点（1-2 核 CPU，512MB 内存）

```nginx
worker_processes 1;
worker_rlimit_nofile 4096;

events {
    worker_connections 512;
    use epoll;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 30;
    keepalive_requests 100;

    client_body_buffer_size 8k;
    client_max_body_size 1m;

    gzip on;
    gzip_comp_level 5;
    gzip_min_length 256;
}
```

**预期性能**：

- 最大并发：**512** 连接
- 静态文件 QPS：**2,000-5,000**
- 内存使用：**~30-50 MB**

### 中型站点（4 核 CPU，2GB 内存）

```nginx
worker_processes 4;
worker_rlimit_nofile 32768;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
    accept_mutex off;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 500;
    reset_timedout_connection on;

    client_body_buffer_size 16k;
    client_max_body_size 10m;
    proxy_buffers 8 16k;
    proxy_buffer_size 8k;

    gzip on;
    gzip_comp_level 5;
    gzip_min_length 256;

    proxy_cache_path /var/cache/nginx levels=1:2
        keys_zone=cache:10m max_size=500m inactive=30m;

    open_file_cache max=5000 inactive=60s;
    open_file_cache_valid 120s;
}
```

**预期性能**：

- 最大并发：**16,384** 连接
- 静态文件 QPS：**10,000-30,000**
- 反向代理 QPS：**5,000-15,000**
- 内存使用：**~200-500 MB**

### 大型站点（16 核 CPU，8GB 内存）

```nginx
worker_processes 16;
worker_rlimit_nofile 65535;
worker_cpu_affinity auto;

events {
    worker_connections 8192;
    use epoll;
    multi_accept on;
    accept_mutex off;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 1000;
    reset_timedout_connection on;

    client_body_buffer_size 32k;
    client_max_body_size 50m;
    proxy_buffers 16 32k;
    proxy_buffer_size 16k;
    proxy_busy_buffers_size 64k;

    gzip on;
    gzip_comp_level 4;
    gzip_min_length 256;

    proxy_cache_path /var/cache/nginx levels=1:2
        keys_zone=cache:50m max_size=5g inactive=60m;

    open_file_cache max=20000 inactive=120s;
    open_file_cache_valid 300s;
    open_file_cache_min_uses 2;

    upstream backend {
        least_conn;
        server 10.0.0.1:8080 weight=5;
        server 10.0.0.2:8080 weight=5;
        server 10.0.0.3:8080 weight=5;
        keepalive 64;
        keepalive_requests 1000;
    }
}
```

**预期性能**：

- 最大并发：**131,072** 连接
- 静态文件 QPS：**50,000-100,000+**
- 反向代理 QPS：**20,000-50,000**
- 内存使用：**~1-3 GB**

## 性能测试方法

### 使用 ab（Apache Bench）

```bash
# 基础测试：1000 次请求，100 并发
ab -n 1000 -c 100 https://localhost:8443/

# 长时间测试：60 秒，200 并发
ab -t 60 -c 200 https://localhost:8443/

# POST 请求测试
ab -n 1000 -c 50 -p post_data.json -T "application/json" https://localhost:8443/api/
```

### 使用 wrk（推荐）

```bash
# 基础测试：2 线程，100 连接，30 秒
wrk -t2 -c100 -d30s https://localhost:8443/

# 高并发测试
wrk -t4 -c1000 -d60s https://localhost:8443/

# 带 Lua 脚本的复杂测试
wrk -t4 -c100 -d30s -s post.lua https://localhost:8443/api/
```

### 使用 siege

```bash
# 模拟 100 个用户，持续 60 秒
siege -c100 -t60s https://localhost:8443/
```

### 关键性能指标

| 指标 | 说明 | 目标值 |
|------|------|--------|
| RPS / QPS | 每秒请求数 | 根据业务需求 |
| Latency P50 | 50% 请求的响应时间 | < 50ms |
| Latency P99 | 99% 请求的响应时间 | < 200ms |
| Error Rate | 错误率 | < 0.1% |
| CPU Usage | CPU 使用率 | < 80% |
| Memory Usage | 内存使用率 | < 70% |
| Connection Timeout | 连接超时率 | < 0.01% |

---

## 参考资料

- [Nginx 性能调优官方文档](https://nginx.org/en/docs/http/ngx_http_core_module.html)
- [Nginx 性能调优指南](https://www.nginx.com/blog/tuning-nginx/)
- [Linux TCP 调优](https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt)
- [Docker 资源约束](https://docs.docker.com/config/containers/resource_constraints/)
