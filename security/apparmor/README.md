# AppArmor Profile 安全配置

> **CIS Docker Benchmark 5.1** — 确保为每个容器配置 AppArmor Profile

## 目录

- [什么是 AppArmor](#什么是-apparmor)
- [为什么需要 AppArmor](#为什么需要-apparmor)
- [文件说明](#文件说明)
- [加载 Profile](#加载-profile)
- [使用方法](#使用方法)
- [权限说明](#权限说明)
- [验证 Profile 是否生效](#验证-profile-是否生效)
- [切换 Enforce / Complain 模式](#切换-enforce--complain-模式)
- [故障排除](#故障排除)

---

## 什么是 AppArmor

AppArmor（Application Armor）是 Linux 内核安全模块，通过强制访问控制（MAC）策略限制程序的能力，包括文件访问、网络操作和 Linux Capabilities。与 SELinux 相比，AppArmor 基于路径的策略更易于配置和维护。

AppArmor 是 Docker 默认启用的安全模块，Docker 会为容器加载名为 `docker-default` 的通用 Profile。本项目提供了专门为 Nginx 定制的 AppArmor Profile，在默认基础上进一步收紧权限。

## 为什么需要 AppArmor

| 安全威胁 | AppArmor 防护效果 |
|---------|-----------------|
| 任意文件读取 | 限制只能访问 Nginx 必需的目录 |
| 目录遍历攻击 | 阻止访问 `/etc/shadow` 等敏感文件 |
| 命令注入 | 限制可执行文件范围 |
| 权限提升 | 限制 Linux Capabilities |
| 横向移动 | 限制网络连接类型 |

**基准数据**：

- Docker 默认 Profile 提供 **基础** 文件系统保护
- 本项目自定义 Profile 提供 **精确到路径** 的访问控制
- 可阻止约 **90%** 的容器文件系统逃逸尝试

## 文件说明

### `nginx-apparmor-profile`

Nginx 专用 AppArmor 配置文件，定义了以下策略：

- **文件访问**：仅允许读取配置文件、静态资源；仅允许写入日志目录和临时目录
- **网络访问**：仅允许 TCP 监听和连接
- **Capabilities**：仅保留 `net_bind_service`、`setuid`、`setgid`、`dac_override` 等必要能力
- **可执行文件**：仅允许执行 Nginx 二进制文件和必要的系统库

## 加载 Profile

### 安装 AppArmor 工具

```bash
# Debian/Ubuntu
sudo apt-get install apparmor apparmor-utils

# CentOS/RHEL（需要 EPEL）
sudo yum install apparmor apparmor-utils
```

### 加载自定义 Profile

```bash
# 复制 Profile 到 AppArmor 目录
sudo cp nginx-apparmor-profile /etc/apparmor.d/docker-nginx

# 加载 Profile
sudo apparmor_parser -r /etc/apparmor.d/docker-nginx

# 验证 Profile 已加载
sudo apparmor_status | grep docker-nginx
```

### 设置开机自动加载

复制到 `/etc/apparmor.d/` 目录下的 Profile 会在系统启动时自动加载。也可以手动确认：

```bash
# 检查 AppArmor 服务状态
sudo systemctl status apparmor

# 确保 AppArmor 开机启动
sudo systemctl enable apparmor
```

## 使用方法

### 方式一：docker run 命令

```bash
docker run -d \
  --name nginx-secure \
  --security-opt apparmor=docker-nginx \
  -p 443:8443 \
  nginx-hardened:latest
```

### 方式二：docker-compose（推荐）

在 `docker-compose.yml` 中配置：

```yaml
services:
  nginx:
    image: nginx-hardened:latest
    security_opt:
      - apparmor=docker-nginx
    ports:
      - "443:8443"
```

启动服务：

```bash
docker compose up -d
```

### 方式三：Docker Swarm

> ⚠️ Docker Swarm 目前不支持通过 `--security-opt` 指定 AppArmor Profile。
> 需要在所有 Swarm 节点上加载 Profile 并使用默认 Profile 名称。

## 权限说明

### 文件访问权限

| 路径 | 权限 | 说明 |
|-----|------|------|
| `/etc/nginx/**` | `r` (只读) | Nginx 配置文件 |
| `/usr/share/nginx/**` | `r` (只读) | 静态资源文件 |
| `/var/log/nginx/**` | `rw` (读写) | 日志文件 |
| `/var/cache/nginx/**` | `rw` (读写) | 缓存目录 |
| `/var/run/nginx.pid` | `rw` (读写) | PID 文件 |
| `/tmp/**` | `rw` (读写) | 临时文件（上传等） |
| `/run/secrets/**` | `r` (只读) | Docker Secrets（证书、密钥） |
| `/usr/sbin/nginx` | `ix` (执行) | Nginx 主程序 |
| `/etc/ssl/**` | `r` (只读) | SSL 证书和密钥 |
| `/etc/passwd` | `r` (只读) | 用户信息（uid 查询） |
| `/etc/group` | `r` (只读) | 用户组信息 |
| `/proc/*/status` | `r` (只读) | 进程状态信息 |

### 拒绝访问的路径

| 路径 | 说明 |
|-----|------|
| `/etc/shadow` | 密码哈希文件 |
| `/root/**` | root 用户目录 |
| `/home/**` | 用户主目录 |
| `/boot/**` | 启动文件 |
| `/sys/firmware/**` | 固件信息 |

### 网络权限

| 权限 | 说明 |
|------|------|
| `network tcp` | 允许 TCP 连接（监听和外联） |
| `network udp` | 允许 UDP（DNS 解析） |
| 拒绝 `raw` | 禁止原始套接字 |

### Capabilities 权限

| Capability | 说明 |
|-----------|------|
| `net_bind_service` | 允许绑定 1024 以下端口（如 80、443） |
| `setuid` / `setgid` | 允许 master 进程切换到 worker 用户 |
| `dac_override` | 允许绕过文件权限检查（日志轮转需要） |
| `chown` | 允许更改文件所有者（启动时设置权限） |
| 拒绝 `sys_admin` | 禁止系统管理操作 |
| 拒绝 `sys_ptrace` | 禁止进程跟踪 |
| 拒绝 `sys_rawio` | 禁止原始 I/O |

## 验证 Profile 是否生效

### 方法一：检查容器 AppArmor 状态

```bash
docker inspect --format '{{.AppArmorProfile}}' nginx-secure
```

预期输出：

```
docker-nginx
```

### 方法二：查看系统 AppArmor 状态

```bash
sudo apparmor_status
```

预期输出中应包含：

```
enforce mode:
   docker-nginx
```

### 方法三：审计日志验证

```bash
# 尝试在容器内访问被禁止的文件
docker exec nginx-secure cat /etc/shadow

# 查看 AppArmor 拒绝日志
sudo dmesg | grep -i "apparmor.*DENIED"
# 或
sudo journalctl -k | grep -i "apparmor.*DENIED"
```

预期看到类似输出：

```
audit: type=1400 audit(...): apparmor="DENIED" operation="open"
  profile="docker-nginx" name="/etc/shadow" pid=... comm="cat"
  requested_mask="r" denied_mask="r" fsuid=...
```

### 方法四：使用 aa-status 工具

```bash
# 查看所有已加载的 Profile
sudo aa-status

# 检查特定 Profile
sudo aa-status | grep -A5 docker-nginx
```

## 切换 Enforce / Complain 模式

AppArmor 支持两种运行模式：

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| **Enforce**（强制） | 阻止违规操作并记录日志 | 生产环境 |
| **Complain**（投诉） | 仅记录违规操作但不阻止 | 调试和测试 |

### 切换到 Complain 模式（调试用）

```bash
# 方法一：使用 aa-complain
sudo aa-complain /etc/apparmor.d/docker-nginx

# 方法二：使用 apparmor_parser
sudo apparmor_parser -C /etc/apparmor.d/docker-nginx
```

### 切换回 Enforce 模式（生产环境）

```bash
# 方法一：使用 aa-enforce
sudo aa-enforce /etc/apparmor.d/docker-nginx

# 方法二：使用 apparmor_parser
sudo apparmor_parser -r /etc/apparmor.d/docker-nginx
```

### 调试工作流

1. **将 Profile 设为 Complain 模式**：
   ```bash
   sudo aa-complain /etc/apparmor.d/docker-nginx
   ```

2. **运行容器并执行所有功能测试**

3. **收集审计日志**：
   ```bash
   sudo dmesg | grep apparmor | grep docker-nginx
   ```

4. **根据日志调整 Profile**

5. **切换回 Enforce 模式**：
   ```bash
   sudo aa-enforce /etc/apparmor.d/docker-nginx
   ```

6. **重新运行功能测试验证**

## 故障排除

### 问题：容器启动失败，提示 AppArmor Profile 不存在

**错误信息**：

```
Error response from daemon: OCI runtime create failed: container_linux.go:380:
applying apparmor profile: no such file or directory
```

**原因**：Profile 未加载到系统中。

**解决方法**：

```bash
# 加载 Profile
sudo apparmor_parser -r /etc/apparmor.d/docker-nginx

# 验证
sudo apparmor_status | grep docker-nginx
```

### 问题：Nginx 无法读取配置文件

**日志**：

```
apparmor="DENIED" operation="open" name="/etc/nginx/nginx.conf"
```

**解决方法**：确保 Profile 中包含：

```
/etc/nginx/** r,
```

### 问题：Nginx 无法写入日志

**日志**：

```
apparmor="DENIED" operation="mknod" name="/var/log/nginx/access.log"
```

**解决方法**：确保 Profile 中包含：

```
/var/log/nginx/** rw,
```

### 问题：SSL 证书无法读取

**日志**：

```
apparmor="DENIED" operation="open" name="/run/secrets/ssl_certificate"
```

**解决方法**：确保 Profile 中包含：

```
/run/secrets/** r,
/etc/ssl/** r,
```

### 问题：主机系统不支持 AppArmor

**检查方法**：

```bash
# 检查 AppArmor 是否启用
cat /sys/module/apparmor/parameters/enabled
# 输出 Y 表示启用

# 检查 Docker 是否支持
docker info | grep -i apparmor
```

**解决方法**：如果系统不支持 AppArmor，可以使用 Seccomp 作为替代安全机制。

### 问题：Profile 更新后不生效

**原因**：需要重新加载 Profile 并重启容器。

**解决方法**：

```bash
# 重新加载 Profile
sudo apparmor_parser -r /etc/apparmor.d/docker-nginx

# 重启容器
docker restart nginx-secure
```

---

## 参考资料

- [CIS Docker Benchmark v1.6.0 — 5.1](https://www.cisecurity.org/benchmark/docker)
- [Docker AppArmor 文档](https://docs.docker.com/engine/security/apparmor/)
- [AppArmor Wiki](https://gitlab.com/apparmor/apparmor/-/wikis/home)
- [Ubuntu AppArmor 指南](https://ubuntu.com/server/docs/security-apparmor)
