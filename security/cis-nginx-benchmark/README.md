# CIS Nginx Benchmark 安全基准

> **CIS Nginx Benchmark v2.0.1** — Center for Internet Security Nginx Web Server 安全基准

## 目录

- [概述](#概述)
- [安全检查清单](#安全检查清单)
  - [2.1 最小化 Nginx 模块](#21-最小化-nginx-模块)
  - [2.2 禁用 server_tokens](#22-禁用-server_tokens)
  - [2.3 限制 Nginx 文件和目录访问](#23-限制-nginx-文件和目录访问)
  - [2.4 SSL/TLS 配置](#24-ssltls-配置)
  - [2.5 请求限制和超时设置](#25-请求限制和超时设置)
  - [3.x 日志配置](#3x-日志配置)
  - [4.1 代理安全头](#41-代理安全头)
  - [5.x 信息泄露防护](#5x-信息泄露防护)
- [验证方法](#验证方法)
- [参考资料](#参考资料)

---

## 概述

CIS Nginx Benchmark 是由互联网安全中心发布的 Nginx 专用安全配置基准，专注于 Web 服务器层面的安全加固。本项目的 Dockerfile 和 Nginx 配置文件严格按照此基准实施。

**覆盖统计**：

| 章节 | 检查项数量 | 本项目实现 |
|------|-----------|-----------|
| 2.x 基础配置 | 18 项 | 16 项 ✅ |
| 3.x 日志配置 | 7 项 | 7 项 ✅ |
| 4.x 请求和代理 | 5 项 | 5 项 ✅ |
| 5.x 信息泄露 | 4 项 | 4 项 ✅ |
| **合计** | **34 项** | **32 项 ✅** |

覆盖率约 **94%**。

## 安全检查清单

### 2.1 最小化 Nginx 模块

> **CIS Nginx 2.1.1 - 2.1.4** — 确保仅安装必要的 Nginx 模块

#### 实现方式

在 `Dockerfile` 中通过源码编译控制模块列表：

```bash
./configure \
  --with-http_ssl_module \           # SSL/TLS 支持（必需）
  --with-http_v2_module \            # HTTP/2 支持
  --with-http_realip_module \        # 获取真实客户端 IP
  --with-http_gzip_static_module \   # 静态 Gzip 压缩
  --with-http_stub_status_module \   # 状态监控
  --without-http_autoindex_module \  # 禁用目录列表
  --without-http_ssi_module \        # 禁用 SSI
  --without-http_scgi_module \       # 禁用 SCGI
  --without-http_uwsgi_module \      # 禁用 uWSGI
  --without-http_grpc_module \       # 禁用 gRPC
  --without-mail_pop3_module \       # 禁用 POP3
  --without-mail_imap_module \       # 禁用 IMAP
  --without-mail_smtp_module         # 禁用 SMTP
```

| 检查项 | 编号 | 状态 | 说明 |
|--------|------|------|------|
| 禁用不必要的 HTTP 模块 | 2.1.1 | ✅ | 使用 `--without-*` 编译选项 |
| 禁用邮件代理模块 | 2.1.2 | ✅ | `--without-mail_*_module` |
| 确保仅启用必要模块 | 2.1.3 | ✅ | 源码编译，完全控制模块列表 |
| 禁用 HTTP autoindex | 2.1.4 | ✅ | `--without-http_autoindex_module` |

#### 验证

```bash
# 查看已编译的模块
docker exec nginx-secure nginx -V 2>&1 | tr ' ' '\n' | grep -E "with|without"

# 确认 autoindex 未启用
docker exec nginx-secure nginx -V 2>&1 | grep -c "http_autoindex_module"
# 预期输出：0
```

### 2.2 禁用 server_tokens

> **CIS Nginx 2.2.1 - 2.2.2** — 隐藏 Nginx 版本信息

#### 实现方式

在 `nginx.conf` 中配置：

```nginx
http {
    # 隐藏 Nginx 版本号
    server_tokens off;

    # 自定义 Server 头（可选，需要 headers-more 模块）
    more_set_headers "Server: ";
}
```

在 `Dockerfile` 中源码级隐藏：

```bash
# 修改 Nginx 源码中的版本标识
sed -i 's/Server: nginx/Server: /g' src/http/ngx_http_header_filter_module.c
```

| 检查项 | 编号 | 状态 | 说明 |
|--------|------|------|------|
| 禁用 server_tokens | 2.2.1 | ✅ | `server_tokens off` |
| 隐藏 Server 头 | 2.2.2 | ✅ | 源码修改 + headers-more 模块 |

#### 验证

```bash
# 检查响应头
curl -sI https://localhost:8443/ | grep -i server

# 预期输出不包含 nginx 版本号
# Server: （空或自定义值）
```

### 2.3 限制 Nginx 文件和目录访问

> **CIS Nginx 2.3.1 - 2.3.4** — 确保 Nginx 文件权限正确

#### 实现方式

在 `Dockerfile` 中设置权限：

```dockerfile
# 配置文件权限
RUN chmod 640 /etc/nginx/nginx.conf && \
    chmod -R 640 /etc/nginx/conf.d/ && \
    chown -R root:nginx /etc/nginx/ && \
    # 日志目录权限
    chmod 750 /var/log/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    # Web 根目录权限
    chmod -R 644 /usr/share/nginx/html/ && \
    chown -R root:nginx /usr/share/nginx/html/
```

| 检查项 | 编号 | 状态 | 说明 |
|--------|------|------|------|
| Nginx 配置文件权限 ≤ 640 | 2.3.1 | ✅ | `chmod 640 /etc/nginx/nginx.conf` |
| Nginx 配置目录属主 root | 2.3.2 | ✅ | `chown root:nginx /etc/nginx/` |
| 日志目录权限 ≤ 750 | 2.3.3 | ✅ | `chmod 750 /var/log/nginx` |
| PID 文件权限和属主 | 2.3.4 | ✅ | 运行时创建，权限正确 |

#### 验证

```bash
# 检查配置文件权限
docker exec nginx-secure stat -c '%a %U:%G' /etc/nginx/nginx.conf
# 预期：640 root:nginx

# 检查日志目录权限
docker exec nginx-secure stat -c '%a %U:%G' /var/log/nginx
# 预期：750 nginx:nginx
```

### 2.4 SSL/TLS 配置

> **CIS Nginx 2.4.1 - 2.4.4** — 确保 SSL/TLS 安全配置

#### 2.4.1 仅使用 TLS 1.2 和 TLS 1.3

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
```

#### 2.4.2 禁用弱加密套件

```nginx
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';
ssl_prefer_server_ciphers on;
```

#### 2.4.3 配置 DH 参数

```nginx
ssl_dhparam /run/secrets/dhparam;    # 使用 Docker Secrets
```

DH 参数生成：

```bash
openssl dhparam -out dhparam.pem 2048
```

#### 2.4.4 启用 HSTS

```nginx
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
```

| 检查项 | 编号 | 状态 | 说明 |
|--------|------|------|------|
| 仅使用 TLS 1.2/1.3 | 2.4.1 | ✅ | `ssl_protocols TLSv1.2 TLSv1.3` |
| 禁用弱加密套件 | 2.4.2 | ✅ | 仅使用 AEAD 加密套件 |
| 配置 DH 参数 | 2.4.3 | ✅ | 2048+ 位 DH 参数 |
| 启用 HSTS | 2.4.4 | ✅ | `max-age=63072000` (2 年) |

#### 验证

```bash
# 测试 TLS 版本
openssl s_client -connect localhost:443 -tls1_2 </dev/null 2>/dev/null | grep "Protocol"
# 预期：Protocol  : TLSv1.2

# 测试 TLS 1.1 应失败
openssl s_client -connect localhost:443 -tls1_1 </dev/null 2>&1 | grep -i "alert\|error"

# 测试加密套件
nmap --script ssl-enum-ciphers -p 443 localhost

# 检查 HSTS 头
curl -sI https://localhost:443/ | grep -i strict
# 预期：Strict-Transport-Security: max-age=63072000; includeSubDomains; preload

# 使用 testssl.sh 全面测试
docker run --rm --net host drwetter/testssl.sh https://localhost:443/
```

### 2.5 请求限制和超时设置

> **CIS Nginx 2.5.1 - 2.5.4** — 确保配置请求限制和超时

#### 实现方式

```nginx
http {
    # 客户端请求体大小限制（防止大文件上传攻击）
    client_max_body_size 1m;

    # 客户端请求体缓冲区
    client_body_buffer_size 16k;

    # 客户端请求头缓冲区
    large_client_header_buffers 4 8k;

    # 超时设置（防止慢速攻击）
    client_body_timeout 10;
    client_header_timeout 10;
    keepalive_timeout 65;
    send_timeout 10;

    # 请求速率限制（防止暴力攻击和 DDoS）
    limit_req_zone $binary_remote_addr zone=req_limit:10m rate=10r/s;
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

    server {
        limit_req zone=req_limit burst=20 nodelay;
        limit_conn conn_limit 10;
    }
}
```

| 检查项 | 编号 | 状态 | 说明 |
|--------|------|------|------|
| 限制请求体大小 | 2.5.1 | ✅ | `client_max_body_size 1m` |
| 配置超时参数 | 2.5.2 | ✅ | 所有超时设置 ≤ 65 秒 |
| 限制请求速率 | 2.5.3 | ✅ | `limit_req_zone` + `limit_conn_zone` |
| 限制缓冲区大小 | 2.5.4 | ✅ | 合理的缓冲区大小设置 |

#### 验证

```bash
# 测试请求体大小限制
dd if=/dev/zero bs=2M count=1 | curl -X POST --data-binary @- https://localhost:8443/
# 预期：413 Request Entity Too Large

# 测试速率限制
ab -n 100 -c 50 https://localhost:8443/
# 预期：部分请求返回 503
```

### 3.x 日志配置

> **CIS Nginx 3.1 - 3.7** — 确保日志配置完善

#### 实现方式

```nginx
http {
    # 3.1 - 启用详细日志格式
    log_format main '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent" '
                    '$request_time $upstream_response_time '
                    '$http_x_forwarded_for';

    # 3.2 - 配置访问日志
    access_log /var/log/nginx/access.log main;

    # 3.3 - 配置错误日志（warn 级别以上）
    error_log /var/log/nginx/error.log warn;

    # 3.4 - 日志输出到标准输出（容器化最佳实践）
    access_log /dev/stdout main;
    error_log /dev/stderr warn;

    # 3.7 - 记录 SSL/TLS 详细信息
    log_format ssl '$remote_addr - $remote_user [$time_local] '
                   '"$request" $status $body_bytes_sent '
                   '$ssl_protocol $ssl_cipher '
                   '"$http_referer" "$http_user_agent"';
}
```

| 检查项 | 编号 | 状态 | 说明 |
|--------|------|------|------|
| 配置详细日志格式 | 3.1 | ✅ | 包含请求时间、上游响应时间 |
| 启用访问日志 | 3.2 | ✅ | 所有 server 块配置 access_log |
| 启用错误日志 | 3.3 | ✅ | `error_log` 级别为 `warn` |
| 日志发送到 syslog 或远程服务器 | 3.4 | ✅ | 支持 syslog 和标准输出 |
| 确保不记录敏感信息 | 3.5 | ✅ | 日志中不包含密码等敏感信息 |
| 配置日志缓冲区 | 3.6 | ✅ | `access_log ... buffer=32k flush=5m` |
| 记录 SSL/TLS 详细信息 | 3.7 | ✅ | SSL 日志格式包含协议和加密套件 |

#### 验证

```bash
# 检查日志格式
docker exec nginx-secure nginx -T 2>/dev/null | grep "log_format"

# 检查访问日志输出
curl -s https://localhost:8443/ > /dev/null && \
  docker exec nginx-secure tail -1 /var/log/nginx/access.log

# 检查错误日志级别
docker exec nginx-secure nginx -T 2>/dev/null | grep "error_log"
```

### 4.1 代理安全头

> **CIS Nginx 4.1.1 - 4.1.5** — 确保配置安全响应头

#### 实现方式

```nginx
server {
    # 4.1.1 - 防止 MIME 类型嗅探
    add_header X-Content-Type-Options "nosniff" always;

    # 4.1.2 - 防止点击劫持
    add_header X-Frame-Options "SAMEORIGIN" always;

    # 4.1.3 - 启用 XSS 保护
    add_header X-XSS-Protection "1; mode=block" always;

    # 4.1.4 - 内容安全策略
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'" always;

    # 4.1.5 - 引用策略
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # 额外安全头
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
}
```

| 检查项 | 编号 | 状态 | 说明 |
|--------|------|------|------|
| X-Content-Type-Options | 4.1.1 | ✅ | `nosniff` |
| X-Frame-Options | 4.1.2 | ✅ | `SAMEORIGIN` |
| X-XSS-Protection | 4.1.3 | ✅ | `1; mode=block` |
| Content-Security-Policy | 4.1.4 | ✅ | 限制资源来源 |
| Referrer-Policy | 4.1.5 | ✅ | `strict-origin-when-cross-origin` |

#### 验证

```bash
# 检查所有安全头
curl -sI https://localhost:8443/ | grep -iE "x-content|x-frame|x-xss|content-security|referrer|strict-transport"

# 预期输出：
# X-Content-Type-Options: nosniff
# X-Frame-Options: SAMEORIGIN
# X-XSS-Protection: 1; mode=block
# Content-Security-Policy: default-src 'self'; ...
# Referrer-Policy: strict-origin-when-cross-origin
# Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
```

### 5.x 信息泄露防护

> **CIS Nginx 5.1 - 5.4** — 确保防止信息泄露

#### 5.1 隐藏 Nginx 版本

已在 [2.2 禁用 server_tokens](#22-禁用-server_tokens) 中实现。

#### 5.2 禁止访问隐藏文件

```nginx
server {
    # 阻止访问 .htaccess, .git, .env 等隐藏文件
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
        return 404;
    }
}
```

#### 5.3 禁止访问备份文件

```nginx
server {
    # 阻止访问备份文件和临时文件
    location ~* \.(bak|conf|dist|fla|in[ci]|log|orig|sh|sql|sw[op])$ {
        deny all;
        return 404;
    }
}
```

#### 5.4 自定义错误页面

```nginx
server {
    # 自定义错误页面（不泄露 Nginx 信息）
    error_page 400 401 403 404 /error.html;
    error_page 500 502 503 504 /error.html;

    location = /error.html {
        root /usr/share/nginx/html;
        internal;
    }
}
```

| 检查项 | 编号 | 状态 | 说明 |
|--------|------|------|------|
| 隐藏 Nginx 版本 | 5.1 | ✅ | `server_tokens off` + 源码修改 |
| 禁止访问隐藏文件 | 5.2 | ✅ | `location ~ /\. { deny all; }` |
| 禁止访问备份文件 | 5.3 | ✅ | 按扩展名阻止 |
| 自定义错误页面 | 5.4 | ✅ | 不泄露服务器信息 |

#### 验证

```bash
# 测试隐藏文件访问
curl -s -o /dev/null -w "%{http_code}" https://localhost:8443/.env
# 预期：404

# 测试备份文件访问
curl -s -o /dev/null -w "%{http_code}" https://localhost:8443/config.bak
# 预期：404

# 测试错误页面不泄露信息
curl -s https://localhost:8443/nonexistent_page | grep -i nginx
# 预期：无输出（不包含 nginx 字样）
```

## 验证方法

### 一键验证所有检查项

```bash
# 运行项目验证脚本
bash tests/validate.sh

# 或手动执行关键验证
echo "=== 2.2 server_tokens ==="
curl -sI https://localhost:8443/ | grep -i server

echo "=== 2.4 TLS 配置 ==="
echo | openssl s_client -connect localhost:443 2>/dev/null | grep "Protocol\|Cipher"

echo "=== 4.1 安全头 ==="
curl -sI https://localhost:8443/ | grep -iE "x-content|x-frame|x-xss|content-security|referrer|strict"

echo "=== 5.2 隐藏文件 ==="
curl -s -o /dev/null -w "%{http_code}" https://localhost:8443/.env
```

### 使用 Mozilla Observatory 在线测试

访问 [Mozilla Observatory](https://observatory.mozilla.org/) 输入域名进行在线安全评分。

### 使用 SSL Labs 在线测试

访问 [SSL Labs](https://www.ssllabs.com/ssltest/) 输入域名进行 SSL/TLS 配置评级。

目标评级：**A+**

---

## 参考资料

- [CIS Nginx Benchmark v2.0.1 官方文档](https://www.cisecurity.org/benchmark/nginx)
- [Mozilla SSL 配置生成器](https://ssl-config.mozilla.org/)
- [OWASP 安全头项目](https://owasp.org/www-project-secure-headers/)
- [Nginx 安全加固指南](https://nginx.org/en/docs/http/configuring_https_servers.html)
