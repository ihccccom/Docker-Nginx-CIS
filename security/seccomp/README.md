# Seccomp Profile 安全配置

> **CIS Docker Benchmark 5.30** — 确保使用 Seccomp Profile 限制容器系统调用

## 目录

- [什么是 Seccomp](#什么是-seccomp)
- [为什么需要 Seccomp](#为什么需要-seccomp)
- [文件说明](#文件说明)
- [使用方法](#使用方法)
- [系统调用策略](#系统调用策略)
- [验证 Seccomp 是否生效](#验证-seccomp-是否生效)
- [自定义配置](#自定义配置)
- [故障排除](#故障排除)

---

## 什么是 Seccomp

Seccomp（Secure Computing Mode）是 Linux 内核提供的安全机制，用于限制进程可以执行的系统调用（syscall）。通过定义白名单/黑名单策略，可以有效减小容器的攻击面。

Docker 默认包含一个 Seccomp 配置文件，会阻止约 44 个系统调用。本项目提供了针对 Nginx 优化的自定义 Seccomp 配置，在默认配置基础上进一步收紧权限，仅保留 Nginx 运行所需的最小系统调用集。

## 为什么需要 Seccomp

| 风险场景 | Seccomp 防护效果 |
|---------|----------------|
| 容器逃逸攻击 | 阻止 `unshare`、`mount` 等危险系统调用 |
| 内核漏洞利用 | 减少暴露的内核攻击面约 60% |
| 权限提升 | 阻止 `ptrace`、`keyctl` 等敏感操作 |
| 信息泄露 | 阻止 `syslog`、`kexec_load` 等信息获取途径 |

**基准数据**：

- Docker 默认 Seccomp 配置阻止 **~44** 个系统调用
- 本项目自定义配置仅允许 **~80** 个系统调用（Linux 内核共有 **~330+** 个）
- 攻击面缩减约 **75%**

## 文件说明

### `nginx-seccomp.json`

Nginx 专用 Seccomp 配置文件，采用白名单模式（`defaultAction: SCMP_ACT_ERRNO`），仅允许 Nginx 正常运行所需的系统调用。

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_AARCH64"],
  "syscalls": [
    {
      "names": ["accept4", "bind", "listen", ...],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

- **defaultAction**：默认拒绝所有未明确允许的系统调用
- **architectures**：支持 x86_64、x86 和 ARM64 架构
- **syscalls**：白名单中的系统调用列表

## 使用方法

### 方式一：docker run 命令

```bash
docker run -d \
  --name nginx-secure \
  --security-opt seccomp=./security/seccomp/nginx-seccomp.json \
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
      - seccomp=./security/seccomp/nginx-seccomp.json
    ports:
      - "443:8443"
```

启动服务：

```bash
docker compose up -d
```

### 方式三：Docker Swarm

```bash
docker service create \
  --name nginx \
  --security-opt seccomp=./security/seccomp/nginx-seccomp.json \
  nginx-hardened:latest
```

## 系统调用策略

### ✅ 允许的系统调用（按类别）

#### 网络操作（Nginx 核心需求）

| 系统调用 | 用途 |
|---------|------|
| `accept4` | 接受新的客户端连接 |
| `bind` | 绑定监听端口 |
| `connect` | 建立上游连接（反向代理） |
| `listen` | 开始监听端口 |
| `socket` | 创建网络套接字 |
| `sendto` / `recvfrom` | 发送和接收网络数据 |
| `sendmsg` / `recvmsg` | 发送和接收带控制信息的数据 |
| `setsockopt` / `getsockopt` | 设置和获取套接字选项 |
| `shutdown` | 关闭连接 |
| `epoll_create1` / `epoll_ctl` / `epoll_wait` | I/O 多路复用（事件驱动模型） |

#### 文件操作

| 系统调用 | 用途 |
|---------|------|
| `open` / `openat` | 打开配置文件、日志文件、静态文件 |
| `read` / `write` | 读写文件和套接字 |
| `close` | 关闭文件描述符 |
| `fstat` / `stat` / `lstat` | 获取文件状态信息 |
| `lseek` | 文件偏移操作 |
| `unlink` | 删除临时文件（如 PID 文件） |
| `rename` | 日志轮转时重命名文件 |
| `mkdir` | 创建临时目录 |
| `sendfile` | 高效零拷贝文件传输 |

#### 进程管理

| 系统调用 | 用途 |
|---------|------|
| `clone` | 创建 worker 进程 |
| `fork` | 创建子进程 |
| `wait4` / `waitpid` | 等待子进程状态变更 |
| `kill` | 发送信号（优雅重载、关闭） |
| `exit_group` | 进程退出 |
| `getpid` / `getppid` | 获取进程 ID |
| `setuid` / `setgid` | 降权运行（master → worker） |

#### 内存管理

| 系统调用 | 用途 |
|---------|------|
| `mmap` / `munmap` | 内存映射和释放 |
| `mprotect` | 设置内存保护属性 |
| `brk` | 调整堆空间 |
| `futex` | 用户空间互斥锁 |

#### 时间和信号

| 系统调用 | 用途 |
|---------|------|
| `clock_gettime` | 获取当前时间（日志时间戳） |
| `rt_sigaction` / `rt_sigprocmask` | 信号处理（SIGHUP 重载、SIGTERM 关闭） |
| `nanosleep` | 休眠等待 |

### ❌ 阻止的系统调用（高危操作）

| 系统调用 | 风险说明 |
|---------|---------|
| `mount` / `umount2` | 防止容器挂载文件系统 |
| `unshare` | 防止创建新的命名空间（容器逃逸） |
| `ptrace` | 防止进程跟踪和调试注入 |
| `kexec_load` | 防止加载新内核 |
| `keyctl` | 防止操作内核密钥环 |
| `add_key` / `request_key` | 防止密钥管理操作 |
| `init_module` / `finit_module` | 防止加载内核模块 |
| `delete_module` | 防止删除内核模块 |
| `reboot` | 防止重启系统 |
| `swapon` / `swapoff` | 防止操作交换分区 |
| `syslog` | 防止读取内核日志 |
| `acct` | 防止进程记账操作 |
| `settimeofday` / `clock_settime` | 防止修改系统时间 |
| `pivot_root` | 防止切换根文件系统 |
| `personality` | 防止更改执行域 |

## 验证 Seccomp 是否生效

### 方法一：检查容器进程状态

```bash
# 查看容器内进程的 Seccomp 模式
docker exec nginx-secure cat /proc/1/status | grep -i seccomp
```

预期输出：

```
Seccomp:         2
Seccomp_filters: 1
```

- `Seccomp: 2` 表示 Seccomp 以 filter 模式运行
- `Seccomp_filters: 1` 表示加载了 1 个过滤器

### 方法二：使用 docker inspect

```bash
docker inspect --format '{{.HostConfig.SecurityOpt}}' nginx-secure
```

预期输出：

```
[seccomp=./security/seccomp/nginx-seccomp.json]
```

### 方法三：尝试执行被阻止的系统调用

```bash
# 尝试在容器内执行 mount（应被阻止）
docker exec nginx-secure mount /dev/sda1 /mnt 2>&1

# 预期输出：mount: permission denied (are you root?)
# 或：mount: /mnt: operation not permitted.
```

### 方法四：使用 strace 审计

```bash
# 在测试环境中跟踪系统调用
docker run --rm --security-opt seccomp=unconfined \
  nginx-hardened:latest strace -c -f nginx -t 2>&1 | head -50
```

## 自定义配置

### 添加新的系统调用

如果 Nginx 模块需要额外的系统调用，可以编辑 `nginx-seccomp.json`：

```json
{
  "names": ["新的系统调用名称"],
  "action": "SCMP_ACT_ALLOW",
  "comment": "说明为什么需要这个系统调用"
}
```

### 调试模式（记录而非阻止）

将 `defaultAction` 改为 `SCMP_ACT_LOG` 可以记录被阻止的系统调用而非直接拒绝：

```json
{
  "defaultAction": "SCMP_ACT_LOG",
  ...
}
```

然后通过 `dmesg` 或 `journalctl` 查看被记录的调用：

```bash
dmesg | grep -i seccomp
journalctl -k | grep -i seccomp
```

### 生成自定义配置的步骤

1. **先用 unconfined 模式运行**，收集 Nginx 实际使用的系统调用：

   ```bash
   docker run --rm --security-opt seccomp=unconfined \
     nginx-hardened:latest strace -c -f nginx 2>&1
   ```

2. **分析输出**，将所需系统调用添加到白名单

3. **逐步收紧**，每次移除一个系统调用并测试功能是否正常

4. **压力测试**，确保在高负载下所有功能正常：

   ```bash
   ab -n 10000 -c 100 https://localhost:8443/
   ```

## 故障排除

### 问题：容器启动后立即退出

**原因**：Seccomp 配置缺少 Nginx 启动所需的关键系统调用。

**解决方法**：

```bash
# 1. 查看容器退出日志
docker logs nginx-secure

# 2. 用 unconfined 模式测试
docker run --rm --security-opt seccomp=unconfined nginx-hardened:latest

# 3. 用 SCMP_ACT_LOG 模式找出被阻止的调用
# 修改 defaultAction 为 SCMP_ACT_LOG 后重启
dmesg | grep seccomp
```

### 问题：Nginx 无法绑定端口

**原因**：缺少 `bind` 或 `listen` 系统调用。

**解决方法**：确保配置文件包含以下系统调用：

```json
{
  "names": ["bind", "listen", "socket", "setsockopt"],
  "action": "SCMP_ACT_ALLOW"
}
```

### 问题：日志文件无法写入

**原因**：缺少文件操作相关系统调用。

**解决方法**：确保白名单包含 `open`、`openat`、`write`、`fstat`、`lseek` 等调用。

### 问题：SSL/TLS 连接失败

**原因**：OpenSSL 可能需要额外的系统调用（如 `getrandom`、`getentropy`）。

**解决方法**：

```json
{
  "names": ["getrandom"],
  "action": "SCMP_ACT_ALLOW"
}
```

### 问题：反向代理无法连接上游

**原因**：缺少 `connect` 系统调用或 DNS 解析相关调用。

**解决方法**：确保白名单包含 `connect`、`sendto`、`recvfrom`（DNS 查询需要）。

---

## 参考资料

- [CIS Docker Benchmark v1.6.0 — 5.30](https://www.cisecurity.org/benchmark/docker)
- [Docker Seccomp 文档](https://docs.docker.com/engine/security/seccomp/)
- [Linux Seccomp 手册](https://man7.org/linux/man-pages/man2/seccomp.2.html)
- [Nginx 系统调用分析](https://github.com/moby/moby/blob/master/profiles/seccomp/default.json)
