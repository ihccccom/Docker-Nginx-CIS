# 日志与审计配置

> **CIS Docker Benchmark 2.6** — 确保为 Docker 守护进程配置审计  
> **CIS Docker Benchmark 2.12** — 确保配置集中式和远程日志记录  
> **PCI DSS 10.1** — 实施审计追踪以链接对系统组件的所有访问  
> **PCI DSS 10.2** — 记录所有审计追踪事件  
> **PCI DSS 10.3** — 为所有审计追踪条目记录特定信息

## 目录

- [概述](#概述)
- [文件说明](#文件说明)
- [Auditd 审计规则](#auditd-审计规则)
- [Docker 守护进程日志配置](#docker-守护进程日志配置)
- [应用 daemon.json 配置](#应用-daemonjson-配置)
- [日志轮转配置](#日志轮转配置)
- [查询审计日志](#查询审计日志)
- [远程日志传输](#远程日志传输)
- [监控建议](#监控建议)

---

## 概述

完善的日志和审计机制是安全运维的基石，也是 CIS Docker Benchmark 和 PCI DSS 合规的核心要求。本项目的审计配置涵盖三个层面：

| 层面 | 工具 | 目的 |
|------|------|------|
| **操作系统层** | auditd | 审计 Docker 相关文件和目录的访问 |
| **Docker 守护进程层** | daemon.json | 配置日志驱动、存储限制和安全选项 |
| **应用层** | Nginx 日志 | 记录 HTTP 访问和错误信息 |

**合规覆盖**：

| 标准 | 条款 | 本项目实现 |
|------|------|-----------|
| CIS Docker 2.6 | 审计 Docker 守护进程 | `docker-audit.rules` |
| CIS Docker 2.12 | 集中式日志 | `daemon.json` 中配置日志驱动 |
| PCI DSS 10.1 | 审计追踪 | auditd + Docker 日志 |
| PCI DSS 10.2 | 记录安全事件 | 审计规则覆盖所有关键操作 |
| PCI DSS 10.3 | 日志字段完整性 | 时间戳、用户、操作、结果 |

## 文件说明

### `docker-audit.rules`

Linux auditd 审计规则文件，监控所有 Docker 相关的文件、目录和操作。

**审计范围**：

| 审计对象 | 规则键值 | 说明 |
|---------|---------|------|
| `/usr/bin/dockerd` | `docker` | Docker 守护进程二进制文件 |
| `/usr/bin/docker` | `docker` | Docker 客户端二进制文件 |
| `/var/lib/docker` | `docker` | Docker 数据目录 |
| `/etc/docker` | `docker` | Docker 配置目录 |
| `/etc/default/docker` | `docker` | Docker 默认配置 |
| `/etc/docker/daemon.json` | `docker` | Docker 守护进程配置文件 |
| `/usr/bin/containerd` | `docker` | containerd 运行时 |
| `/usr/bin/runc` | `docker` | runc 容器运行时 |
| `/var/run/docker.sock` | `docker` | Docker Unix 套接字 |
| `/lib/systemd/system/docker.service` | `docker` | Docker systemd 服务文件 |
| `/lib/systemd/system/docker.socket` | `docker` | Docker systemd 套接字文件 |

### `daemon.json`

Docker 守护进程配置文件，包含日志、安全和网络相关的配置项。

**关键配置**：

| 配置项 | 值 | 说明 |
|--------|---|------|
| `log-driver` | `json-file` | 日志驱动类型 |
| `log-opts.max-size` | `10m` | 单个日志文件最大 10MB |
| `log-opts.max-file` | `3` | 最多保留 3 个日志文件 |
| `userns-remap` | `default` | 用户命名空间隔离 |
| `no-new-privileges` | `true` | 禁止获取新权限 |
| `icc` | `false` | 禁止容器间通信 |
| `live-restore` | `true` | 守护进程重启时保持容器运行 |

### `daemon.json.comments`

`daemon.json` 的详细注释说明文件（因 JSON 不支持注释），逐项解释每个配置的作用、安全意义和对应的 CIS 基准条款。

## Auditd 审计规则

### 安装和配置

```bash
# 安装 auditd
sudo apt-get install auditd audispd-plugins    # Debian/Ubuntu
sudo yum install audit audit-libs               # CentOS/RHEL

# 复制审计规则
sudo cp docker-audit.rules /etc/audit/rules.d/docker-audit.rules

# 重新加载审计规则
sudo auditctl -R /etc/audit/rules.d/docker-audit.rules

# 或重启 auditd 服务
sudo systemctl restart auditd
```

### 验证规则已加载

```bash
# 列出当前所有审计规则
sudo auditctl -l

# 检查 Docker 相关规则
sudo auditctl -l | grep docker
```

预期输出：

```
-w /usr/bin/dockerd -p rwxa -k docker
-w /usr/bin/docker -p rwxa -k docker
-w /var/lib/docker -p rwxa -k docker
-w /etc/docker -p rwxa -k docker
-w /etc/default/docker -p rwxa -k docker
-w /etc/docker/daemon.json -p rwxa -k docker
-w /usr/bin/containerd -p rwxa -k docker
-w /usr/bin/runc -p rwxa -k docker
-w /var/run/docker.sock -p rwxa -k docker
-w /lib/systemd/system/docker.service -p rwxa -k docker
-w /lib/systemd/system/docker.socket -p rwxa -k docker
```

### 规则参数说明

| 参数 | 说明 |
|------|------|
| `-w` | 监控的文件或目录路径 |
| `-p rwxa` | 监控的操作类型：r=读取、w=写入、x=执行、a=属性变更 |
| `-k docker` | 审计日志的键值标识，便于检索 |

## Docker 守护进程日志配置

### 配置步骤

```bash
# 备份现有配置
sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak

# 复制新配置
sudo cp daemon.json /etc/docker/daemon.json

# 验证配置语法
python3 -c "import json; json.load(open('/etc/docker/daemon.json'))"
```

### 可选日志驱动

| 日志驱动 | 适用场景 | 说明 |
|---------|---------|------|
| `json-file` | 单机部署 | 默认驱动，支持 `docker logs` 命令 |
| `syslog` | 传统运维 | 发送到 syslog 服务器 |
| `journald` | systemd 系统 | 集成 systemd journal |
| `fluentd` | 容器化日志收集 | 发送到 Fluentd 收集器 |
| `gelf` | ELK/Graylog | 发送 GELF 格式日志 |
| `splunk` | Splunk 平台 | 直接发送到 Splunk HEC |

### Syslog 驱动配置示例

```json
{
  "log-driver": "syslog",
  "log-opts": {
    "syslog-address": "tcp://logserver:514",
    "syslog-facility": "daemon",
    "tag": "docker/{{.Name}}"
  }
}
```

### Fluentd 驱动配置示例

```json
{
  "log-driver": "fluentd",
  "log-opts": {
    "fluentd-address": "fluentd:24224",
    "tag": "docker.{{.Name}}",
    "fluentd-async-connect": "true",
    "fluentd-retry-wait": "1s",
    "fluentd-max-retries": "30"
  }
}
```

## 应用 daemon.json 配置

### 步骤

```bash
# 1. 复制配置文件
sudo cp daemon.json /etc/docker/daemon.json

# 2. 验证 JSON 格式正确
sudo python3 -c "import json; json.load(open('/etc/docker/daemon.json')); print('配置格式正确')"

# 3. 重新加载 Docker 守护进程
sudo systemctl daemon-reload
sudo systemctl restart docker

# 4. 验证配置已生效
docker info | grep -E "Logging Driver|Storage Driver|Cgroup Driver"
```

### 验证要点

```bash
# 验证日志驱动
docker info --format '{{.LoggingDriver}}'
# 预期输出：json-file

# 验证日志选项
docker info --format '{{.LoggingDriver}}' && \
docker inspect --format='{{.HostConfig.LogConfig}}' <container_id>

# 验证安全选项
docker info | grep -i "no-new-privileges"
# 预期输出：No New Privileges: true
```

## 日志轮转配置

### Docker 日志轮转（daemon.json）

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "compress": "true"
  }
}
```

| 参数 | 推荐值 | 说明 |
|------|-------|------|
| `max-size` | `10m` | 单个日志文件不超过 10MB |
| `max-file` | `3` | 最多保留 3 个轮转文件 |
| `compress` | `true` | 压缩归档的日志文件 |

**磁盘占用计算**：每个容器最多使用 `max-size × max-file = 10MB × 3 = 30MB` 日志空间。

### Nginx 日志轮转（logrotate）

创建 `/etc/logrotate.d/nginx-docker`：

```
/var/lib/docker/containers/*/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    maxsize 50M
}
```

### Auditd 日志轮转

编辑 `/etc/audit/auditd.conf`：

```ini
# 日志文件大小限制（MB）
max_log_file = 50

# 达到限制后的处理方式
max_log_file_action = ROTATE

# 保留的日志文件数量
num_logs = 10

# 磁盘空间不足时的处理
space_left_action = SYSLOG
admin_space_left_action = HALT
```

## 查询审计日志

### 使用 ausearch

```bash
# 查询所有 Docker 相关的审计事件
sudo ausearch -k docker

# 查询特定时间范围的事件
sudo ausearch -k docker --start today
sudo ausearch -k docker --start "2024-01-01" --end "2024-01-31"

# 查询特定文件的访问记录
sudo ausearch -f /etc/docker/daemon.json

# 查询特定用户的操作
sudo ausearch -k docker -ui 1000

# 查询特定操作类型（如写入）
sudo ausearch -k docker -sc open -i

# 以更可读的格式输出
sudo ausearch -k docker -i
```

### 使用 aureport

```bash
# 生成审计报告概要
sudo aureport -k --summary

# 生成文件访问报告
sudo aureport -f --summary

# 生成可执行文件报告
sudo aureport -x --summary

# 生成异常事件报告
sudo aureport --anomaly
```

### 使用 Docker 日志命令

```bash
# 查看容器日志
docker logs nginx-secure

# 实时跟踪日志
docker logs -f nginx-secure

# 查看最近 100 行
docker logs --tail 100 nginx-secure

# 带时间戳显示
docker logs -t nginx-secure

# 查看特定时间范围
docker logs --since "2024-01-01T00:00:00" --until "2024-01-02T00:00:00" nginx-secure
```

## 远程日志传输

### 方案一：Syslog 远程传输

```json
{
  "log-driver": "syslog",
  "log-opts": {
    "syslog-address": "tcp+tls://logserver.example.com:6514",
    "syslog-tls-ca-cert": "/etc/docker/ca.pem",
    "syslog-tls-cert": "/etc/docker/client-cert.pem",
    "syslog-tls-key": "/etc/docker/client-key.pem",
    "syslog-facility": "daemon",
    "tag": "docker/{{.Name}}/{{.ID}}"
  }
}
```

### 方案二：ELK Stack 集成

#### Filebeat 配置

```yaml
# filebeat.yml
filebeat.inputs:
  - type: container
    paths:
      - /var/lib/docker/containers/*/*.log
    processors:
      - add_docker_metadata: ~

output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  index: "docker-logs-%{+yyyy.MM.dd}"

# 或输出到 Logstash
output.logstash:
  hosts: ["logstash:5044"]
```

#### Docker Compose 集成 Filebeat

```yaml
services:
  filebeat:
    image: elastic/filebeat:8.12.0
    volumes:
      - ./filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
    user: root
    depends_on:
      - nginx
```

### 方案三：Fluentd / Fluent Bit

```yaml
services:
  fluent-bit:
    image: fluent/fluent-bit:latest
    volumes:
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - ./fluent-bit.conf:/fluent-bit/etc/fluent-bit.conf:ro
```

### 方案四：Auditd 远程传输

编辑 `/etc/audisp/plugins.d/syslog.conf`：

```ini
active = yes
direction = out
path = builtin_syslog
type = builtin
args = LOG_INFO LOG_LOCAL6
format = string
```

然后配置 rsyslog 将 `local6` 转发到远程服务器：

```
local6.* @@logserver.example.com:514
```

## 监控建议

### 关键告警指标

| 指标 | 阈值 | 说明 |
|------|------|------|
| Docker 守护进程异常退出 | 任何一次 | 立即告警 |
| 审计日志被清空或删除 | 任何一次 | 立即告警（可能是入侵迹象） |
| 容器异常重启次数 | > 3 次/小时 | 可能存在稳定性问题或攻击 |
| 权限拒绝事件 | > 10 次/分钟 | 可能是暴力攻击尝试 |
| 日志磁盘使用率 | > 80% | 警告，需要清理或扩容 |
| Docker 配置文件变更 | 任何一次 | 需要审核确认 |
| 非授权用户执行 docker 命令 | 任何一次 | 立即告警 |

### Prometheus + Grafana 监控

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'docker'
    static_configs:
      - targets: ['localhost:9323']    # Docker metrics endpoint
```

在 `daemon.json` 中启用 metrics：

```json
{
  "metrics-addr": "127.0.0.1:9323",
  "experimental": true
}
```

### 日志保留策略（PCI DSS 10.7）

| 日志类型 | 在线保留 | 归档保留 | 说明 |
|---------|---------|---------|------|
| Docker 容器日志 | 90 天 | 1 年 | PCI DSS 要求至少保留 1 年 |
| Auditd 审计日志 | 90 天 | 1 年 | 需要随时可查询最近 3 个月数据 |
| Nginx 访问日志 | 90 天 | 1 年 | 按 PCI DSS 10.7 要求 |
| Nginx 错误日志 | 90 天 | 1 年 | 用于安全事件调查 |

---

## 参考资料

- [CIS Docker Benchmark v1.6.0 — 2.6, 2.12](https://www.cisecurity.org/benchmark/docker)
- [PCI DSS v4.0 — Requirement 10](https://www.pcisecuritystandards.org/)
- [Docker 日志驱动文档](https://docs.docker.com/config/containers/logging/)
- [Linux Audit 系统文档](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/security_guide/chap-system_auditing)
- [ELK Stack 文档](https://www.elastic.co/guide/index.html)
