# CIS Docker Benchmark 安全基准

> **CIS Docker Benchmark v1.6.0** — Center for Internet Security Docker 安全基准

## 目录

- [概述](#概述)
- [文件说明](#文件说明)
- [运行检查脚本](#运行检查脚本)
- [安全检查清单](#安全检查清单)
  - [1.x 主机配置](#1x-主机配置)
  - [2.x Docker 守护进程配置](#2x-docker-守护进程配置)
  - [3.x Docker 守护进程配置文件](#3x-docker-守护进程配置文件)
  - [4.x 容器镜像和构建文件](#4x-容器镜像和构建文件)
  - [5.x 容器运行时](#5x-容器运行时)
- [常见失败项修复](#常见失败项修复)
- [参考资料](#参考资料)

---

## 概述

CIS Docker Benchmark 是由互联网安全中心（Center for Internet Security）发布的 Docker 安全配置基准，提供了一套全面的安全检查清单，涵盖从主机配置到容器运行时的各个层面。

本项目严格按照 CIS Docker Benchmark v1.6.0 标准进行安全加固，涵盖以下领域：

| 领域 | 检查项数量 | 本项目实现 |
|------|-----------|-----------|
| 1.x 主机配置 | 12 项 | 提供配置指南 |
| 2.x Docker 守护进程配置 | 18 项 | `daemon.json` + 审计规则 |
| 3.x Docker 守护进程配置文件 | 22 项 | 文件权限建议 |
| 4.x 容器镜像和构建文件 | 12 项 | `Dockerfile` 最佳实践 |
| 5.x 容器运行时 | 32 项 | `docker-compose.yml` + 安全配置 |

**总计覆盖 96 项检查**，本项目直接实现或提供指导约 **70+** 项。

## 文件说明

### `docker-bench-check.sh`

CIS Docker Benchmark 自动化检查脚本，基于 Docker Bench for Security 定制，自动检测主机和容器的安全配置。

**检查输出格式**：

```
[PASS] 2.1  - Ensure network traffic is restricted between containers
[WARN] 2.2  - Ensure the logging level is set to 'info'
[FAIL] 2.5  - Ensure auditd is configured for Docker files and directories
[INFO] 2.8  - Enable user namespace support
[NOTE] 2.18 - Ensure containers are restricted from acquiring new privileges
```

| 标识 | 含义 |
|------|------|
| `[PASS]` | 检查通过，符合基准要求 |
| `[FAIL]` | 检查失败，需要修复 |
| `[WARN]` | 警告，建议优化 |
| `[INFO]` | 信息提示 |
| `[NOTE]` | 需要手动验证 |

## 运行检查脚本

### 基本用法

```bash
# 运行完整检查
sudo bash docker-bench-check.sh

# 仅检查特定章节
sudo bash docker-bench-check.sh --check 2
sudo bash docker-bench-check.sh --check 4,5

# 输出到文件
sudo bash docker-bench-check.sh | tee cis-report-$(date +%Y%m%d).txt

# 仅显示失败项
sudo bash docker-bench-check.sh | grep "\[FAIL\]"
```

### 使用 Docker Bench for Security（官方工具）

```bash
# 运行官方 CIS 检查工具
docker run --rm --net host --pid host --userns host --cap-add audit_control \
  -e DOCKER_CONTENT_TRUST=$DOCKER_CONTENT_TRUST \
  -v /etc:/etc:ro \
  -v /usr/bin/containerd:/usr/bin/containerd:ro \
  -v /usr/bin/runc:/usr/bin/runc:ro \
  -v /usr/lib/systemd:/usr/lib/systemd:ro \
  -v /var/lib:/var/lib:ro \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  --label docker_bench_security \
  docker/docker-bench-security
```

## 安全检查清单

### 1.x 主机配置

| 编号 | 检查项 | 本项目实现 |
|------|--------|-----------|
| 1.1.1 | 确保为容器创建独立分区 | 📋 建议将 `/var/lib/docker` 配置为独立分区 |
| 1.1.2 | 确保加固容器主机 | 📋 建议使用最小化 OS 安装（如 Ubuntu Server Minimal） |
| 1.1.3 | 确保 Docker 版本保持更新 | 📋 建议使用最新稳定版 Docker Engine |
| 1.2.1 | 确保仅允许受信用户控制 Docker 守护进程 | 📋 建议限制 `docker` 用户组成员 |
| 1.2.2 | 确保审计 Docker 守护进程 | ✅ `docker-audit.rules` 实现 |
| 1.2.3 | 确保审计 Docker 文件和目录 — `/var/lib/docker` | ✅ `docker-audit.rules` 实现 |
| 1.2.4 | 确保审计 Docker 文件和目录 — `/etc/docker` | ✅ `docker-audit.rules` 实现 |
| 1.2.5 | 确保审计 `docker.service` | ✅ `docker-audit.rules` 实现 |
| 1.2.6 | 确保审计 `docker.socket` | ✅ `docker-audit.rules` 实现 |
| 1.2.7 | 确保审计 `/etc/default/docker` | ✅ `docker-audit.rules` 实现 |
| 1.2.8 | 确保审计 `/etc/docker/daemon.json` | ✅ `docker-audit.rules` 实现 |
| 1.2.9 | 确保审计 `containerd` | ✅ `docker-audit.rules` 实现 |

### 2.x Docker 守护进程配置

| 编号 | 检查项 | 本项目实现 |
|------|--------|-----------|
| 2.1 | 确保限制容器间网络流量 | ✅ `daemon.json` 中 `"icc": false` |
| 2.2 | 确保日志级别设为 `info` | ✅ `daemon.json` 中 `"log-level": "info"` |
| 2.3 | 确保 Docker 允许更改 iptables | ✅ `daemon.json` 中 `"iptables": true` |
| 2.4 | 确保不使用不安全的 Registry | ✅ `daemon.json` 中不配置 insecure-registries |
| 2.5 | 确保未使用 `aufs` 存储驱动 | ✅ 使用 `overlay2` 存储驱动 |
| 2.6 | 确保为 Docker 守护进程配置审计 | ✅ `docker-audit.rules` 实现 |
| 2.7 | 确保为 Docker 配置 TLS 认证 | 📋 提供 TLS 配置指南 |
| 2.8 | 确保启用用户命名空间 | ✅ `daemon.json` 中 `"userns-remap": "default"` |
| 2.9 | 确保使用默认 cgroup | ✅ 使用默认 `cgroupfs` 或 `systemd` |
| 2.10 | 确保默认 ulimit 已正确配置 | ✅ `daemon.json` 中配置 `default-ulimits` |
| 2.11 | 确保启用 Docker 客户端命令授权 | 📋 建议配置 `--authorization-plugin` |
| 2.12 | 确保配置集中式和远程日志 | ✅ `daemon.json` 支持多种日志驱动 |
| 2.13 | 确保启用实时恢复 | ✅ `daemon.json` 中 `"live-restore": true` |
| 2.14 | 确保禁用 Userland Proxy | ✅ `daemon.json` 中 `"userland-proxy": false` |
| 2.15 | 确保应用守护进程级别 Seccomp | ✅ 自定义 Seccomp Profile |
| 2.16 | 确保限制实验性功能 | ✅ 不启用实验性功能 |
| 2.17 | 确保容器使用 rootless 模式 | 📋 提供 rootless Docker 配置指南 |
| 2.18 | 确保限制容器获取新权限 | ✅ `daemon.json` 中 `"no-new-privileges": true` |

### 3.x Docker 守护进程配置文件

| 编号 | 检查项 | 本项目实现 |
|------|--------|-----------|
| 3.1 | 确保 `docker.service` 文件权限为 644 或更严格 | 📋 提供权限设置指南 |
| 3.2 | 确保 `docker.service` 文件属主为 root:root | 📋 提供权限设置指南 |
| 3.3 | 确保 `docker.socket` 文件权限为 644 或更严格 | 📋 提供权限设置指南 |
| 3.4 | 确保 `docker.socket` 文件属主为 root:root | 📋 提供权限设置指南 |
| 3.5 | 确保 `/etc/docker` 目录权限为 755 或更严格 | 📋 提供权限设置指南 |
| 3.6 | 确保 `/etc/docker` 目录属主为 root:root | 📋 提供权限设置指南 |
| 3.7 | 确保 Registry 证书权限为 444 或更严格 | 📋 提供权限设置指南 |
| 3.8 | 确保 Registry 证书属主为 root:root | 📋 提供权限设置指南 |
| 3.9 | 确保 TLS CA 证书文件权限为 444 或更严格 | 📋 提供权限设置指南 |
| 3.10 | 确保 TLS CA 证书文件属主为 root:root | 📋 提供权限设置指南 |
| 3.11 | 确保 Docker server 证书权限为 444 或更严格 | 📋 提供权限设置指南 |
| 3.12 | 确保 Docker server 证书属主为 root:root | 📋 提供权限设置指南 |
| 3.13 | 确保 Docker server 密钥权限为 400 | 📋 提供权限设置指南 |
| 3.14 | 确保 Docker server 密钥属主为 root:root | 📋 提供权限设置指南 |
| 3.15 | 确保 Docker socket 权限为 660 或更严格 | 📋 提供权限设置指南 |
| 3.16 | 确保 Docker socket 属主为 root:docker | 📋 提供权限设置指南 |
| 3.17 | 确保 `daemon.json` 权限为 644 或更严格 | 📋 提供权限设置指南 |
| 3.18 | 确保 `daemon.json` 属主为 root:root | 📋 提供权限设置指南 |
| 3.19 | 确保 `/etc/default/docker` 权限为 644 或更严格 | 📋 提供权限设置指南 |
| 3.20 | 确保 `/etc/default/docker` 属主为 root:root | 📋 提供权限设置指南 |
| 3.21 | 确保 Containerd socket 权限为 660 或更严格 | 📋 提供权限设置指南 |
| 3.22 | 确保 Containerd socket 属主为 root:root | 📋 提供权限设置指南 |

### 4.x 容器镜像和构建文件

| 编号 | 检查项 | 本项目实现 |
|------|--------|-----------|
| 4.1 | 确保为容器创建非 root 用户 | ⚠️ Nginx master 需 root 绑定 80/443；worker 以 `www-data` 运行（非 Dockerfile `USER` 全程非 root） |
| 4.2 | 确保容器使用可信基础镜像 | ✅ 使用官方 `debian:trixie-slim` 基础镜像 |
| 4.3 | 确保不在容器中安装不必要的软件包 | ✅ 多阶段构建，最终镜像仅包含运行时依赖 |
| 4.4 | 确保镜像已扫描并重建以包含安全补丁 | 📋 建议集成 Trivy/Snyk 扫描 |
| 4.5 | 确保启用 Docker 内容信任 | 📋 建议设置 `DOCKER_CONTENT_TRUST=1` |
| 4.6 | 确保 Dockerfile 中包含 `HEALTHCHECK` | ✅ `Dockerfile` 中配置 HEALTHCHECK |
| 4.7 | 确保不在 Dockerfile 中使用 `update` 指令 | ✅ 合并 RUN 指令并在同一层中执行更新和安装 |
| 4.8 | 确保不使用 `setuid`/`setgid` 权限 | ✅ 构建时移除不必要的 setuid/setgid 位 |
| 4.9 | 确保 Dockerfile 中使用 `COPY` 而非 `ADD` | ✅ 仅使用 `COPY` 指令 |
| 4.10 | 确保不在 Dockerfile 中存储密钥 | ✅ 使用 Docker Secrets 管理敏感信息 |
| 4.11 | 确保仅安装已验证的软件包 | ✅ 使用 Debian apt 官方源与 HTTPS 下载校验 |
| 4.12 | 确保扫描和重建镜像以修复漏洞 | 📋 提供 CI/CD 集成指南 |

### 5.x 容器运行时

| 编号 | 检查项 | 本项目实现 |
|------|--------|-----------|
| 5.1 | 确保启用 AppArmor Profile | ✅ 自定义 `nginx-apparmor-profile` |
| 5.2 | 确保 SELinux 安全选项已设置 | 📋 提供 SELinux 配置指南 |
| 5.3 | 确保限制 Linux 内核 Capabilities | ✅ `docker-compose.yml` 中 `cap_drop: ALL` + 最小 `cap_add` |
| 5.4 | 确保不使用特权容器 | ✅ `docker-compose.yml` 中未设置 `privileged` |
| 5.5 | 确保不在容器上挂载敏感主机目录 | ✅ 仅挂载必要的卷 |
| 5.6 | 确保 `sshd` 未在容器内运行 | ✅ 容器内不安装 SSH |
| 5.7 | 确保不映射特权端口 | ✅ 容器内使用 8080/8443 非特权端口 |
| 5.8 | 确保仅打开需要的端口 | ✅ 仅暴露 80/443 端口 |
| 5.9 | 确保不使用 host 网络模式 | ✅ 使用默认 bridge 网络 |
| 5.10 | 确保限制容器内存使用 | ✅ `docker-compose.yml` 中设置 `mem_limit` |
| 5.11 | 确保设置容器 CPU 优先级 | ✅ `docker-compose.yml` 中设置 `cpus` |
| 5.12 | 确保根文件系统挂载为只读 | ✅ `docker-compose.yml` 中 `read_only: true` |
| 5.13 | 确保绑定的端口与入站连接匹配 | ✅ 端口映射配置正确 |
| 5.14 | 确保 `restart` 策略设置为 `on-failure` | ✅ `docker-compose.yml` 中 `restart: on-failure` |
| 5.15 | 确保不在容器中共享主机进程命名空间 | ✅ 未设置 `pid: host` |
| 5.16 | 确保不在容器中共享主机 IPC 命名空间 | ✅ 未设置 `ipc: host` |
| 5.17 | 确保不在容器中直接暴露主机设备 | ✅ 未挂载主机设备 |
| 5.18 | 确保覆盖默认 ulimit | ✅ `docker-compose.yml` 中设置 `ulimits` |
| 5.19 | 确保设置容器重启策略最大重试次数 | ✅ `restart: on-failure:5` |
| 5.20 | 确保不共享主机 UTS 命名空间 | ✅ 未设置 `uts: host` |
| 5.21 | 确保未禁用默认 Seccomp Profile | ✅ 使用自定义 Seccomp Profile |
| 5.22 | 确保不在容器中存储密钥 | ✅ 使用 Docker Secrets |
| 5.23 | 确保 Docker 远程 API 受 TLS 保护 | 📋 提供 TLS 配置指南 |
| 5.24 | 确保 cgroup 使用已确认 | ✅ 使用默认 cgroup |
| 5.25 | 确保限制容器获取额外权限 | ✅ `no-new-privileges: true` |
| 5.26 | 确保容器健康检查已配置 | ✅ `Dockerfile` 和 `docker-compose.yml` 中 HEALTHCHECK |
| 5.27 | 确保 Docker 命令始终指定最新版本 | ✅ 使用明确的镜像标签 |
| 5.28 | 确保使用 PID cgroup 限制 | ✅ `docker-compose.yml` 中设置 `pids_limit` |
| 5.29 | 确保不使用 Docker 默认 bridge network | ✅ 使用自定义网络 |
| 5.30 | 确保使用 Seccomp Profile | ✅ 自定义 `nginx-seccomp.json` |
| 5.31 | 确保不在容器中运行 Docker socket | ✅ 未挂载 Docker socket |
| 5.32 | 确保禁用 Swarm 自动锁定 | 📋 建议启用 `--autolock` |

## 常见失败项修复

### FAIL: 2.1 — 容器间网络流量未限制

```bash
# 修复：编辑 daemon.json
{
  "icc": false
}

# 重启 Docker
sudo systemctl restart docker
```

### FAIL: 2.6 — 未配置 Docker 审计

```bash
# 修复：安装审计规则
sudo cp docker-audit.rules /etc/audit/rules.d/
sudo systemctl restart auditd
```

### FAIL: 2.8 — 未启用用户命名空间

```bash
# 修复：配置 userns-remap
{
  "userns-remap": "default"
}

# 注意：启用后可能需要重新拉取镜像
sudo systemctl restart docker
```

### FAIL: 4.1 — 容器以 root 运行

```dockerfile
# 说明：本项目 Nginx master 需 root 绑定特权端口；worker 通过
# --user=www-data 降权。若改为非特权端口映射，可再考虑 USER www-data。
# RUN useradd -r -g www-data -s /sbin/nologin www-data
# USER www-data
```

### FAIL: 5.3 — 未限制 Linux Capabilities

```yaml
# 修复：在 docker-compose.yml 中配置
services:
  nginx:
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
      - CHOWN
      - SETUID
      - SETGID
      - DAC_OVERRIDE
```

### FAIL: 5.10 — 未限制内存使用

```yaml
# 修复：在 docker-compose.yml 中配置
services:
  nginx:
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M
```

### FAIL: 5.12 — 根文件系统未设为只读

```yaml
# 修复：在 docker-compose.yml 中配置
services:
  nginx:
    read_only: true
    tmpfs:
      - /var/cache/nginx
      - /var/run
      - /tmp
```

### FAIL: 5.25 — 未限制获取新权限

```yaml
# 修复：在 docker-compose.yml 中配置
services:
  nginx:
    security_opt:
      - no-new-privileges:true
```

### FAIL: 5.28 — 未限制 PID 数量

```yaml
# 修复：在 docker-compose.yml 中配置
services:
  nginx:
    pids_limit: 100
```

---

## 参考资料

- [CIS Docker Benchmark v1.6.0 官方文档](https://www.cisecurity.org/benchmark/docker)
- [Docker Bench for Security 工具](https://github.com/docker/docker-bench-security)
- [Docker 安全最佳实践](https://docs.docker.com/engine/security/)
- [NIST SP 800-190 容器安全指南](https://csrc.nist.gov/publications/detail/sp/800-190/final)
