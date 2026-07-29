# 验证与测试

## 目录

- [概述](#概述)
- [文件说明](#文件说明)
- [运行验证脚本](#运行验证脚本)
- [测试类别](#测试类别)
  - [容器安全测试](#容器安全测试)
  - [Nginx 功能测试](#nginx-功能测试)
  - [文件权限测试](#文件权限测试)
  - [ModSecurity WAF 测试](#modsecurity-waf-测试)
- [测试结果解读](#测试结果解读)
- [添加自定义测试](#添加自定义测试)
- [CI/CD 集成](#cicd-集成)
- [示例输出](#示例输出)

---

## 概述

验证脚本用于自动化检测 Nginx 安全容器的配置是否符合预期标准，涵盖容器安全、Nginx 功能、文件权限和 WAF 防护四个维度。

**测试覆盖统计**：

| 测试类别 | 测试数量 | 说明 |
|---------|---------|------|
| 容器安全测试 | ~15 项 | 非 root、Capabilities、只读文件系统等 |
| Nginx 功能测试 | ~10 项 | TLS、安全头、重定向等 |
| 文件权限测试 | ~8 项 | 配置文件、日志目录权限等 |
| ModSecurity WAF 测试 | ~6 项 | SQL 注入、XSS、路径遍历等 |
| **合计** | **~39 项** | |

## 文件说明

### `validate.sh`

自动化验证脚本，检测以下安全配置：

- 容器是否以非 root 用户运行
- Linux Capabilities 是否正确限制
- 文件系统是否为只读
- Seccomp Profile 是否已加载
- TLS 配置是否安全
- 安全响应头是否正确
- WAF 规则是否生效
- 文件权限是否符合 CIS 基准

## 运行验证脚本

### 前置条件

确保容器已构建并运行：

```bash
# 构建镜像
docker build -t nginx-hardened:latest .

# 启动容器
docker compose up -d

# 等待容器就绪
sleep 5
```

### 运行测试

```bash
# 运行全部测试
bash tests/validate.sh

# 仅显示失败项
bash tests/validate.sh | grep "\[FAIL\]"

# 输出到文件
bash tests/validate.sh | tee test-report-$(date +%Y%m%d).txt

# 返回退出码（适合 CI/CD）
bash tests/validate.sh
echo "Exit code: $?"
# 0 = 全部通过
# 1 = 存在失败项
```

### 指定容器名称

```bash
# 默认检查名为 nginx-secure 的容器
CONTAINER_NAME=my-nginx bash tests/validate.sh
```

## 测试类别

### 容器安全测试

| 测试项 | 对应基准 | 测试方法 |
|--------|---------|---------|
| 非 root 用户运行 | CIS Docker 4.1 | 检查容器内进程 UID |
| Capabilities 已限制 | CIS Docker 5.3 | 检查 `CapDrop` 和 `CapAdd` |
| 只读根文件系统 | CIS Docker 5.12 | 检查 `ReadonlyRootfs` |
| no-new-privileges | CIS Docker 5.25 | 检查安全选项 |
| 内存限制已设置 | CIS Docker 5.10 | 检查 `Memory` 限制 |
| CPU 限制已设置 | CIS Docker 5.11 | 检查 `NanoCpus` |
| PID 限制已设置 | CIS Docker 5.28 | 检查 `PidsLimit` |
| 非特权容器 | CIS Docker 5.4 | 检查 `Privileged` |
| 未使用 host 网络 | CIS Docker 5.9 | 检查 `NetworkMode` |
| 未挂载 Docker socket | CIS Docker 5.31 | 检查 `Binds` |
| 健康检查已配置 | CIS Docker 5.26 | 检查 `Healthcheck` |
| Seccomp Profile 已加载 | CIS Docker 5.30 | 检查 `SecurityOpt` |
| 重启策略已设置 | CIS Docker 5.14 | 检查 `RestartPolicy` |
| tmpfs 挂载已配置 | — | 检查 `Tmpfs` |

### Nginx 功能测试

| 测试项 | 对应基准 | 测试方法 |
|--------|---------|---------|
| HTTPS 正常响应 | — | `curl -k https://localhost:8443/` |
| HTTP 重定向到 HTTPS | — | `curl -sI http://localhost:8080/` |
| TLS 1.2 支持 | CIS Nginx 2.4.1 | `openssl s_client -tls1_2` |
| TLS 1.1 已禁用 | CIS Nginx 2.4.1 | `openssl s_client -tls1_1`（应失败） |
| server_tokens 已关闭 | CIS Nginx 2.2.1 | 检查响应头 Server 字段 |
| X-Content-Type-Options | CIS Nginx 4.1.1 | 检查响应头 |
| X-Frame-Options | CIS Nginx 4.1.2 | 检查响应头 |
| HSTS 已启用 | CIS Nginx 2.4.4 | 检查 Strict-Transport-Security |
| 隐藏文件不可访问 | CIS Nginx 5.2 | 访问 `/.env`（应返回 403/404） |
| 请求体大小限制 | CIS Nginx 2.5.1 | 发送大请求体（应返回 413） |

### 文件权限测试

| 测试项 | 对应基准 | 预期权限 |
|--------|---------|---------|
| `/etc/nginx/nginx.conf` 权限 | CIS Nginx 2.3.1 | ≤ 640 |
| `/etc/nginx/` 目录属主 | CIS Nginx 2.3.2 | root:nginx |
| `/var/log/nginx/` 权限 | CIS Nginx 2.3.3 | ≤ 750 |
| `/usr/sbin/nginx` 权限 | — | 755，属主 root |
| `/usr/share/nginx/html/` 权限 | — | 644，属主 root |
| `/run/secrets/` 权限（如存在） | — | ≤ 440 |
| 无 SUID/SGID 文件 | CIS Docker 4.8 | 无 setuid/setgid 位 |
| `/tmp` 目录存在且可写 | — | tmpfs 挂载 |

### ModSecurity WAF 测试

| 测试项 | 攻击类型 | 测试载荷 | 预期结果 |
|--------|---------|---------|---------|
| SQL 注入检测 | SQL Injection | `?id=1' OR '1'='1` | 403 |
| XSS 检测 | Cross-Site Scripting | `?q=<script>alert(1)</script>` | 403 |
| 路径遍历检测 | Path Traversal | `/../../../etc/passwd` | 403/400 |
| 命令注入检测 | Command Injection | `?cmd=;cat /etc/passwd` | 403 |
| 文件包含检测 | File Inclusion | `?file=http://evil.com/shell` | 403 |
| User-Agent 异常 | Scanner Detection | `Nikto` UA 头 | 403 |

## 测试结果解读

### 输出标识

| 标识 | 含义 | 说明 |
|------|------|------|
| `[PASS]` | ✅ 通过 | 配置符合安全基准 |
| `[FAIL]` | ❌ 失败 | 配置不符合要求，需要修复 |
| `[SKIP]` | ⏭️ 跳过 | 测试条件不满足（如容器未运行） |
| `[INFO]` | ℹ️ 信息 | 提示信息，不影响结果 |

### 退出码

| 退出码 | 含义 |
|--------|------|
| `0` | 所有测试通过 |
| `1` | 存在失败的测试项 |
| `2` | 脚本执行错误（如容器不存在） |

### 失败处理流程

1. **查看失败项描述**，了解问题原因
2. **参考对应的安全基准文档**，了解修复方法
3. **修改配置并重新部署**
4. **重新运行验证脚本**，确认修复

## 添加自定义测试

### 测试函数模板

在 `validate.sh` 中添加自定义测试函数：

```bash
check_custom_test() {
    local description="自定义测试描述"

    # 执行测试逻辑
    result=$(docker exec ${CONTAINER_NAME} some_command 2>/dev/null)

    if [ "$result" = "expected_value" ]; then
        echo "[PASS] ${description}"
    else
        echo "[FAIL] ${description}"
        echo "       预期: expected_value"
        echo "       实际: ${result}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}
```

### 添加 HTTP 测试

```bash
check_custom_endpoint() {
    local url="https://localhost:8443/api/health"
    local expected_code="200"

    status_code=$(curl -sk -o /dev/null -w "%{http_code}" "$url")

    if [ "$status_code" = "$expected_code" ]; then
        echo "[PASS] 健康检查端点返回 $expected_code"
    else
        echo "[FAIL] 健康检查端点返回 $status_code，预期 $expected_code"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}
```

### 添加容器检查

```bash
check_custom_container() {
    local key="HostConfig.SecurityOpt"
    local value=$(docker inspect --format "{{.${key}}}" ${CONTAINER_NAME} 2>/dev/null)

    if echo "$value" | grep -q "no-new-privileges"; then
        echo "[PASS] no-new-privileges 已启用"
    else
        echo "[FAIL] no-new-privileges 未启用"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}
```

## CI/CD 集成

### GitHub Actions

```yaml
name: Security Validation
on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build Docker image
        run: docker build -t nginx-hardened:latest ./nginx/

      - name: Start container
        run: docker compose -f nginx/docker-compose.yml up -d

      - name: Wait for container
        run: sleep 10

      - name: Run validation
        run: bash nginx/tests/validate.sh

      - name: Upload test report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-report
          path: test-report-*.txt
```

### GitLab CI

```yaml
security-validation:
  stage: test
  image: docker:latest
  services:
    - docker:dind
  script:
    - docker build -t nginx-hardened:latest ./nginx/
    - docker compose -f nginx/docker-compose.yml up -d
    - sleep 10
    - bash nginx/tests/validate.sh
  artifacts:
    when: always
    paths:
      - test-report-*.txt
```

### Jenkins Pipeline

```groovy
pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                sh 'docker build -t nginx-hardened:latest ./nginx/'
            }
        }
        stage('Deploy') {
            steps {
                sh 'docker compose -f nginx/docker-compose.yml up -d'
                sh 'sleep 10'
            }
        }
        stage('Validate') {
            steps {
                sh 'bash nginx/tests/validate.sh | tee test-report.txt'
            }
        }
    }
    post {
        always {
            archiveArtifacts artifacts: 'test-report.txt'
            sh 'docker compose -f nginx/docker-compose.yml down'
        }
    }
}
```

## 示例输出

```
==========================================
  Nginx 安全容器验证报告
  日期: 2024-01-15 10:30:00
  容器: nginx-secure
==========================================

--- 容器安全测试 ---
[PASS] 容器以非 root 用户运行 (nginx, UID=101)
[PASS] Capabilities 已限制 (cap_drop: ALL)
[PASS] 仅添加必要的 Capabilities (NET_BIND_SERVICE, CHOWN, SETUID, SETGID, DAC_OVERRIDE)
[PASS] 根文件系统为只读
[PASS] no-new-privileges 已启用
[PASS] 内存限制已设置 (512MB)
[PASS] CPU 限制已设置 (4 cores)
[PASS] PID 限制已设置 (100)
[PASS] 非特权容器
[PASS] 未使用 host 网络模式
[PASS] 未挂载 Docker socket
[PASS] 健康检查已配置
[PASS] Seccomp Profile 已加载
[PASS] 重启策略: on-failure (max: 5)
[PASS] tmpfs 已挂载 (/var/cache/nginx, /var/run, /tmp)

--- Nginx 功能测试 ---
[PASS] HTTPS 正常响应 (状态码: 200)
[PASS] HTTP 重定向到 HTTPS (状态码: 301)
[PASS] TLS 1.2 连接成功
[PASS] TLS 1.3 连接成功
[PASS] TLS 1.1 已禁用 (连接被拒绝)
[PASS] TLS 1.0 已禁用 (连接被拒绝)
[PASS] server_tokens 已关闭 (Server 头不包含版本号)
[PASS] X-Content-Type-Options: nosniff
[PASS] X-Frame-Options: SAMEORIGIN
[PASS] Strict-Transport-Security 已配置

--- 文件权限测试 ---
[PASS] /etc/nginx/nginx.conf 权限: 640
[PASS] /etc/nginx/ 属主: root:nginx
[PASS] /var/log/nginx/ 权限: 750
[PASS] /usr/sbin/nginx 权限: 755, 属主: root
[PASS] 未发现 SUID/SGID 文件

--- ModSecurity WAF 测试 ---
[PASS] SQL 注入被阻止 (403)
[PASS] XSS 攻击被阻止 (403)
[PASS] 路径遍历被阻止 (403)
[PASS] 命令注入被阻止 (403)
[PASS] 隐藏文件不可访问 (404)

==========================================
  测试结果: 34 通过 / 0 失败 / 0 跳过
  总计: 34 项测试
  状态: 全部通过 ✅
==========================================
```

---

## 参考资料

- [CIS Docker Benchmark v1.6.0](https://www.cisecurity.org/benchmark/docker)
- [CIS Nginx Benchmark v2.0.1](https://www.cisecurity.org/benchmark/nginx)
- [Docker Bench for Security](https://github.com/docker/docker-bench-security)
- [OWASP 测试指南](https://owasp.org/www-project-web-security-testing-guide/)
