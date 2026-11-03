# Nginx Docker 安全部署

基于 CIS Docker Benchmark、CIS Nginx Benchmark 标准的 Nginx 安全容器化部署方案。

> 此目录提供可独立分发的部署文件。镜像由源码仓库 GitHub Actions 构建并推送到 Docker Hub。  
> 源码与构建说明：[ihccccom/Docker-Nginx-CIS](https://github.com/ihccccom/Docker-Nginx-CIS)

## 快速开始

```bash
# 1. 进入本目录（或复制本目录文件到工作区）
cd deploy

# 2. 修改 docker-compose.yml 中的 image 地址（如需要）
# image: ihccccom/nginx:latest

# 3. 启动容器
docker compose up -d

# 4. 验证
curl http://localhost/nginx-health
curl -k https://localhost/
```

## 详细教程

完整使用说明见 **[DOCKER-USAGE.md](DOCKER-USAGE.md)**，包括卷挂载、WAF、PHP、站点、SSL、HTTP/3、Seccomp/AppArmor 与运维。

## 安全特性

| 安全层面 | 实现方式 |
|---------|---------|
| 内核级 | Seccomp / AppArmor（可选启用） |
| 容器级 | 能力最小化、只读根、资源限制 |
| 应用级 | ModSecurity + CRS、TLS 1.2/1.3、安全头 |
| 运维级 | 健康检查、审计日志、Secrets 示例 |

## 文件结构

```
deploy/
├── docker-compose.yml
├── DOCKER-USAGE.md
├── README.md
└── security/
    ├── apparmor/nginx-apparmor-profile
    └── seccomp/nginx-seccomp.json
```

首次启动若使用 bind-mount 空目录，entrypoint 会从镜像种子初始化配置；若挂载的 `conf` 缺少 CRS `rules/`，也会自动补齐。
