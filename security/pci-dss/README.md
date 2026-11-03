# PCI DSS 合规配置

> **PCI DSS v4.0** — 支付卡行业数据安全标准

## 目录

- [概述](#概述)
- [合规要求对照](#合规要求对照)
  - [要求 1：安装和维护网络安全控制](#要求-1安装和维护网络安全控制)
  - [要求 2：对所有系统组件应用安全配置](#要求-2对所有系统组件应用安全配置)
  - [要求 3：保护存储的账户数据](#要求-3保护存储的账户数据)
  - [要求 4：使用强加密保护传输中的持卡人数据](#要求-4使用强加密保护传输中的持卡人数据)
  - [要求 5：保护所有系统免受恶意软件侵害](#要求-5保护所有系统免受恶意软件侵害)
  - [要求 6：开发和维护安全的系统和软件](#要求-6开发和维护安全的系统和软件)
  - [要求 7：按业务需要限制对系统组件的访问](#要求-7按业务需要限制对系统组件的访问)
  - [要求 8：识别用户并验证对系统组件的访问](#要求-8识别用户并验证对系统组件的访问)
  - [要求 10：记录和监控对系统组件的所有访问](#要求-10记录和监控对系统组件的所有访问)
  - [要求 11：定期测试安全系统和流程](#要求-11定期测试安全系统和流程)
  - [要求 12：通过策略支持信息安全](#要求-12通过策略支持信息安全)
- [验证 PCI DSS 合规](#验证-pci-dss-合规)
- [参考资料](#参考资料)

---

## 概述

PCI DSS（Payment Card Industry Data Security Standard）是支付卡行业的全球安全标准，适用于所有处理、存储或传输持卡人数据的实体。本项目的 Nginx 安全部署方案实现了 PCI DSS v4.0 中与 Web 服务器相关的多项要求。

**合规覆盖概要**：

| PCI DSS 要求 | 相关性 | 本项目覆盖 |
|-------------|--------|-----------|
| 要求 1：网络安全控制 | 高 | ✅ Docker 网络隔离 + iptables |
| 要求 2：安全配置 | 高 | ✅ CIS 基准加固 |
| 要求 3：保护存储数据 | 中 | ✅ Docker Secrets |
| 要求 4：传输加密 | 高 | ✅ TLS 1.2/1.3 + 强加密套件 |
| 要求 5：恶意软件防护 | 高 | ✅ ModSecurity WAF |
| 要求 6：安全开发和维护 | 高 | ✅ 安全构建 + 补丁管理 |
| 要求 7：最小权限 | 高 | ✅ 非 root + Capabilities 限制 |
| 要求 8：认证和访问 | 中 | ✅ 非 root 用户 + 权限分离 |
| 要求 10：日志和监控 | 高 | ✅ 文本+JSON 访问日志 + 审计日志 |
| 要求 11：安全测试 | 高 | ✅ 自动化验证脚本 |
| 要求 12：安全策略 | 中 | 📋 提供策略模板和指南 |

## 合规要求对照

### 要求 1：安装和维护网络安全控制

> 安装和维护防火墙配置以保护持卡人数据

| PCI DSS 条款 | 要求说明 | 本项目实现 | 实现文件 |
|-------------|---------|-----------|---------|
| 1.2.1 | 限制入站和出站流量 | Docker 网络策略限制容器间通信 | `docker-compose.yml`、`daemon.json` |
| 1.2.5 | 限制网络连接 | `icc: false` 禁止容器间通信 | `daemon.json` |
| 1.3.1 | 入站流量限制在必要端口 | 仅暴露 80/443 端口 | `docker-compose.yml` |
| 1.3.2 | 出站流量限制在必要范围 | Seccomp 限制网络系统调用 | `nginx-seccomp.json` |
| 1.4.1 | 在不可信网络间实施防火墙 | Docker 自定义 bridge 网络隔离 | `docker-compose.yml` |

**验证方法**：

```bash
# 验证容器间通信已禁止
docker network inspect bridge | grep "com.docker.network.bridge.enable_icc"

# 验证仅暴露必要端口
docker port nginx-secure

# 验证 iptables 规则
sudo iptables -L DOCKER -n
```

### 要求 2：对所有系统组件应用安全配置

> 不使用供应商提供的默认密码和其他安全参数

| PCI DSS 条款 | 要求说明 | 本项目实现 | 实现文件 |
|-------------|---------|-----------|---------|
| 2.2.1 | 仅启用必要的功能和服务 | 最小化 Nginx 模块编译 | `Dockerfile` |
| 2.2.2 | 仅启用必要的协议和端口 | 仅启用 HTTP/HTTPS 协议 | `nginx.conf` |
| 2.2.3 | 使用安全配置标准 | CIS Docker + CIS Nginx 基准 | 项目全部文件 |
| 2.2.4 | 配置系统安全参数 | 内核参数、sysctl 调优 | `docker-compose.yml` |
| 2.2.5 | 删除不必要的功能 | 多阶段构建移除开发工具 | `Dockerfile` |
| 2.2.7 | 加密所有非控制台管理访问 | 强制 HTTPS 重定向 | `nginx.conf` |

**验证方法**：

```bash
# 验证最小化模块
docker exec nginx-secure nginx -V 2>&1 | grep -c "without"

# 验证无默认页面泄露
curl -s https://localhost:8443/ | grep -i "welcome to nginx"
# 预期：无输出

# 验证强制 HTTPS
curl -sI http://localhost:8080/ | grep "Location"
# 预期：Location: https://...
```

### 要求 3：保护存储的账户数据

> 保护存储的持卡人数据

| PCI DSS 条款 | 要求说明 | 本项目实现 | 实现文件 |
|-------------|---------|-----------|---------|
| 3.4.1 | 使用强加密保护存储的数据 | SSL 证书和密钥通过 Docker Secrets 管理 | `docker-compose-secrets.yml` |
| 3.5.1 | 保护加密密钥 | 密钥存储在 tmpfs 内存文件系统中 | `docker-compose-secrets.yml` |
| 3.5.1.2 | 限制密钥访问 | 文件权限限制为仅 root 可读 | `Dockerfile`、`docker-entrypoint.sh` |

**验证方法**：

```bash
# 验证 Secrets 挂载为 tmpfs
docker exec nginx-secure mount | grep secrets

# 验证密钥文件权限
docker exec nginx-secure ls -la /run/secrets/
# 预期：密钥文件权限为 400 或 440

# 验证环境变量中没有密钥
docker inspect nginx-secure | grep -iE "key|password|secret" | grep -v "SecurityOpt\|secret_"
```

### 要求 4：使用强加密保护传输中的持卡人数据

> 在开放的公共网络上传输持卡人数据时使用强加密

| PCI DSS 条款 | 要求说明 | 本项目实现 | 实现文件 |
|-------------|---------|-----------|---------|
| 4.2.1 | 使用强加密协议保护传输 | TLS 1.2/1.3 + 强加密套件 | `nginx.conf` |
| 4.2.1.1 | 仅使用可信证书 | 支持 Let's Encrypt / CA 签发证书 | `docker-compose-secrets.yml` |
| 4.2.1.2 | 禁用弱加密协议和算法 | 禁用 SSL 3.0、TLS 1.0、TLS 1.1 | `nginx.conf` |
| 4.2.2 | 确保无线传输加密 | HSTS 强制浏览器使用 HTTPS | `nginx.conf` |

**TLS 配置详细参数**：

| 参数 | 配置值 | PCI DSS 要求 |
|------|--------|-------------|
| `ssl_protocols` | `TLSv1.2 TLSv1.3` | 仅允许 TLS 1.2+ |
| `ssl_ciphers` | ECDHE + AEAD 套件 | 禁止 RC4、DES、3DES |
| `ssl_prefer_server_ciphers` | `on` | 服务器端决定加密套件 |
| `ssl_session_timeout` | `1d` | 合理的会话超时 |
| `ssl_session_tickets` | `off` | 禁用会话票据（前向保密） |
| `ssl_stapling` | `on` | OCSP Stapling |
| `ssl_dhparam` | `2048+ bit` | DH 参数 ≥ 2048 位 |

**验证方法**：

```bash
# 全面 TLS 测试
echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -text | grep -E "Signature|Public-Key"

# 验证禁用弱协议
openssl s_client -connect localhost:443 -tls1 </dev/null 2>&1 | grep -i "error\|alert"
openssl s_client -connect localhost:443 -tls1_1 </dev/null 2>&1 | grep -i "error\|alert"
# 预期：连接失败

# 验证加密套件强度
nmap --script ssl-enum-ciphers -p 443 localhost 2>/dev/null | grep -E "TLSv|cipher"

# 在线测试（生产环境）
# 访问 https://www.ssllabs.com/ssltest/
# 目标评级：A+
```

### 要求 5：保护所有系统免受恶意软件侵害

> 保护所有系统和网络免受恶意软件侵害

| PCI DSS 条款 | 要求说明 | 本项目实现 | 实现文件 |
|-------------|---------|-----------|---------|
| 5.2.1 | 部署防恶意软件解决方案 | ModSecurity WAF + OWASP CRS 规则集 | `Dockerfile` |
| 5.2.2 | 检测和阻止已知攻击 | WAF 规则阻止 SQL 注入、XSS 等 | `nginx.conf` |
| 5.3.1 | 防恶意软件机制保持活跃 | ModSecurity 运行时检测 | `docker-compose.yml` |
| 5.3.2 | 定期更新签名 | OWASP CRS 规则集定期更新 | 运维流程 |

**ModSecurity WAF 防护范围**：

| 攻击类型 | WAF 规则 | 防护效果 |
|---------|---------|---------|
| SQL 注入 | OWASP CRS 942xxx | 阻止 SQL 注入尝试 |
| XSS 跨站脚本 | OWASP CRS 941xxx | 阻止反射型和存储型 XSS |
| 远程命令执行 | OWASP CRS 932xxx | 阻止 OS 命令注入 |
| 路径遍历 | OWASP CRS 930xxx | 阻止目录遍历攻击 |
| 文件包含 | OWASP CRS 931xxx | 阻止本地/远程文件包含 |
| 请求走私 | OWASP CRS 921xxx | 阻止 HTTP 请求走私 |

**验证方法**：

```bash
# 测试 SQL 注入防护
curl -s "https://localhost:8443/?id=1' OR '1'='1" -o /dev/null -w "%{http_code}"
# 预期：403

# 测试 XSS 防护
curl -s "https://localhost:8443/?q=<script>alert(1)</script>" -o /dev/null -w "%{http_code}"
# 预期：403

# 测试路径遍历防护
curl -s "https://localhost:8443/../../../etc/passwd" -o /dev/null -w "%{http_code}"
# 预期：403 或 400
```

### 要求 6：开发和维护安全的系统和软件

> 开发和维护安全的系统和软件

| PCI DSS 条款 | 要求说明 | 本项目实现 | 实现文件 |
|-------------|---------|-----------|---------|
| 6.2.1 | 定义和实施安全的软件开发流程 | 多阶段 Docker 构建 + 最小化镜像 | `Dockerfile` |
| 6.2.4 | 防止常见的软件攻击 | 安全头 + WAF + 输入验证 | `nginx.conf` |
| 6.3.1 | 识别和管理安全漏洞 | 镜像漏洞扫描 | CI/CD 集成 |
| 6.3.2 | 维护软件组件清单 | Dockerfile 明确版本号 | `Dockerfile` |
| 6.3.3 | 及时安装安全补丁 | 定期重建镜像 | 运维流程 |
| 6.4.1 | 面向公众的 Web 应用防护 | ModSecurity WAF | `Dockerfile`、`nginx.conf` |
| 6.4.2 | 自动化技术检测和防止攻击 | WAF + 速率限制 | `nginx.conf` |

**补丁管理流程**：

```bash
# 1. 检查基础镜像更新
docker pull alpine:latest

# 2. 扫描镜像漏洞
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image nginx-hardened:latest

# 3. 重建镜像
docker build --no-cache -t nginx-hardened:latest .

# 4. 运行验证测试
bash tests/validate.sh

# 5. 滚动更新部署
docker compose up -d --force-recreate
```

### 要求 7：按业务需要限制对系统组件的访问

> 按业务知其所需限制对持卡人数据的访问

| PCI DSS 条款 | 要求说明 | 本项目实现 | 实现文件 |
|-------------|---------|-----------|---------|
| 7.1.1 | 定义访问控制策略 | 最小权限原则 | 项目全部文件 |
| 7.2.1 | 基于角色的访问控制 | Nginx 以非 root 用户运行 | `Dockerfile` |
| 7.2.2 | 分配最小必要权限 | `cap_drop: ALL` + 最小 `cap_add` | `docker-compose.yml` |
| 7.2.4 | 限制管理员权限 | Docker 用户组限制 + 审计 | `docker-audit.rules` |
| 7.2.5 | 访问权限定期审查 | 验证脚本检查权限配置 | `validate.sh` |

**权限架构**：

```
主机层面
├── Docker 守护进程（root）
│   ├── 审计所有操作（auditd）
│   └── 限制 docker 用户组
│
容器层面
├── Master 进程（root → 受限）
│   ├── cap_drop: ALL
│   ├── cap_add: 仅必要 Capabilities
│   ├── no-new-privileges: true
│   └── read_only: true
│
├── Worker 进程（nginx 用户）
│   ├── 非特权用户运行
│   ├── 无 shell 访问
│   └── 文件系统只读
│
└── Seccomp + AppArmor（内核层面限制）
```

**验证方法**：

```bash
# 验证非 root 运行
docker exec nginx-secure id
# 或
docker exec nginx-secure ps aux | head -5

# 验证 Capabilities
docker inspect --format '{{.HostConfig.CapDrop}}' nginx-secure
# 预期：[ALL]

docker inspect --format '{{.HostConfig.CapAdd}}' nginx-secure
# 预期：仅包含必要的 Capabilities

# 验证只读文件系统
docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' nginx-secure
# 预期：true
```

### 要求 8：识别用户并验证对系统组件的访问

> 识别和验证对系统组件的访问

| PCI DSS 条款 | 要求说明 | 本项目实现 | 实现文件 |
|-------------|---------|-----------|---------|
| 8.2.1 | 为所有用户分配唯一 ID | 容器使用专用 nginx 用户 (UID 101) | `Dockerfile` |
| 8.2.2 | 管理共享/组账户 | 禁止 root 直接登录容器 | `Dockerfile` |
| 8.3.1 | 使用强认证方式 | 无密码认证（基于 Secrets 的证书认证） | `docker-compose-secrets.yml` |
| 8.6.1 | 管理系统和应用账户 | 非 root 用户 + 无 shell | `Dockerfile` |

**验证方法**：

```bash
# 验证用户配置
docker exec nginx-secure cat /etc/passwd | grep nginx
# 预期：nginx:x:101:101:...:/nonexistent:/sbin/nologin

# 验证无法以 root 执行命令
docker exec -u root nginx-secure whoami 2>&1
# 注意：如果设置了 user: nginx，则只能以 nginx 用户执行
```

### 要求 10：记录和监控对系统组件的所有访问

> 记录和监控对网络资源和持卡人数据的所有访问

| PCI DSS 条款 | 要求说明 | 本项目实现 | 实现文件 |
|-------------|---------|-----------|---------|
| 10.1.1 | 实施审计追踪 | auditd + Docker 日志 + Nginx 日志 | `docker-audit.rules`、`daemon.json` |
| 10.2.1 | 记录所有用户访问 | Nginx 访问日志 | `nginx.conf` |
| 10.2.1.1 | 记录管理操作 | auditd 监控 Docker 命令 | `docker-audit.rules` |
| 10.2.1.2 | 记录特权操作 | auditd 监控 Docker 文件 | `docker-audit.rules` |
| 10.2.1.3 | 记录审计日志的访问和修改 | auditd 保护机制 | `docker-audit.rules` |
| 10.2.2 | 记录异常活动 | ModSecurity WAF 审计日志 | `nginx.conf` |
| 10.3.1 | 日志保护不被修改 | 只读文件系统 + 日志转发 | `docker-compose.yml` |
| 10.3.3 | 日志及时备份 | 支持远程日志传输 | `daemon.json` |
| 10.4.1 | 审查日志以识别异常 | 集中日志分析 | `daemon.json` |
| 10.5.1 | 日志保留至少 12 个月 | 日志归档策略 | 运维流程 |
| 10.7.1 | 及时响应安全事件 | 告警规则配置 | 监控系统集成 |

**验证方法**：

```bash
# 验证审计规则已加载
sudo auditctl -l | grep docker | wc -l
# 预期：>= 10

# 验证 Docker 日志可用
docker logs nginx-secure | head -5

# 验证 Nginx 访问日志格式
docker exec nginx-secure tail -1 /var/log/nginx/access.log
# 预期：包含 IP、时间、请求、状态码等字段
```

### 要求 11：定期测试安全系统和流程

> 定期测试安全系统和网络

| PCI DSS 条款 | 要求说明 | 本项目实现 | 实现文件 |
|-------------|---------|-----------|---------|
| 11.3.1 | 定期执行内部漏洞扫描 | 镜像漏洞扫描（Trivy） | CI/CD 集成 |
| 11.3.2 | 定期执行外部漏洞扫描 | SSL Labs / Mozilla Observatory | 在线测试 |
| 11.4.1 | 执行渗透测试 | 自动化安全验证脚本 | `validate.sh` |
| 11.5.1 | 检测关键文件变更 | 只读文件系统 + auditd | `docker-compose.yml`、`docker-audit.rules` |

**验证方法**：

```bash
# 运行自动化验证
bash tests/validate.sh

# 镜像漏洞扫描
docker run --rm aquasec/trivy image nginx-hardened:latest

# CIS Docker 基准检查
sudo bash security/cis-docker-benchmark/docker-bench-check.sh
```

### 要求 12：通过策略支持信息安全

> 维护解决信息安全的策略和程序

| PCI DSS 条款 | 要求说明 | 本项目实现 |
|-------------|---------|-----------|
| 12.1.1 | 维护信息安全策略 | 📋 项目 README 和安全文档作为策略参考 |
| 12.3.1 | 记录和确认风险评估 | 📋 CIS 基准检查报告 |
| 12.3.4 | 管理加密实现 | ✅ TLS 配置文档和验证方法 |
| 12.6.1 | 安全意识培训 | 📋 各 README 包含安全说明和最佳实践 |

## 验证 PCI DSS 合规

### 自动化合规检查

```bash
#!/bin/bash
echo "========================================="
echo "PCI DSS 合规快速检查"
echo "========================================="

echo ""
echo "[要求 1] 网络安全控制"
echo -n "  容器间通信已禁止: "
docker network inspect bridge 2>/dev/null | grep -q '"com.docker.network.bridge.enable_icc": "false"' && echo "PASS" || echo "FAIL"

echo ""
echo "[要求 2] 安全配置"
echo -n "  非默认配置: "
curl -s https://localhost:8443/ | grep -qi "welcome to nginx" && echo "FAIL" || echo "PASS"

echo ""
echo "[要求 4] 传输加密"
echo -n "  TLS 1.2 支持: "
echo | openssl s_client -connect localhost:443 -tls1_2 2>/dev/null | grep -q "Verify" && echo "PASS" || echo "FAIL"

echo -n "  TLS 1.0 已禁用: "
echo | openssl s_client -connect localhost:443 -tls1 2>&1 | grep -qi "error\|alert" && echo "PASS" || echo "FAIL"

echo ""
echo "[要求 5] WAF 防护"
echo -n "  SQL 注入阻止: "
STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://localhost:8443/?id=1%27%20OR%20%271%27=%271")
[ "$STATUS" = "403" ] && echo "PASS" || echo "FAIL"

echo ""
echo "[要求 7] 最小权限"
echo -n "  Capabilities 限制: "
CAPS=$(docker inspect --format '{{.HostConfig.CapDrop}}' nginx-secure 2>/dev/null)
echo "$CAPS" | grep -q "ALL" && echo "PASS" || echo "FAIL"

echo -n "  只读文件系统: "
RO=$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' nginx-secure 2>/dev/null)
[ "$RO" = "true" ] && echo "PASS" || echo "FAIL"

echo ""
echo "[要求 10] 日志和监控"
echo -n "  审计规则已加载: "
RULES=$(sudo auditctl -l 2>/dev/null | grep -c docker)
[ "$RULES" -ge 10 ] && echo "PASS ($RULES rules)" || echo "FAIL ($RULES rules)"

echo ""
echo "========================================="
echo "检查完成"
echo "========================================="
```

### 合规报告生成

建议定期（至少每季度）生成以下报告：

1. **CIS Docker Benchmark 报告**：`sudo bash docker-bench-check.sh > report.txt`
2. **漏洞扫描报告**：`trivy image nginx-hardened:latest --format json > vuln-report.json`
3. **SSL/TLS 评估报告**：通过 SSL Labs 在线测试
4. **日志审计报告**：`sudo aureport --summary > audit-report.txt`

---

## 参考资料

- [PCI DSS v4.0 官方文档](https://www.pcisecuritystandards.org/document_library/)
- [PCI DSS 快速参考指南](https://www.pcisecuritystandards.org/pdfs/pci_ssc_quick_guide.pdf)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [CIS Nginx Benchmark](https://www.cisecurity.org/benchmark/nginx)
- [OWASP 安全测试指南](https://owasp.org/www-project-web-security-testing-guide/)
