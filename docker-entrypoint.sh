#!/bin/sh
# =======================================================
# Nginx Docker 入口脚本
# 负责运行时初始化和权限检查
# =======================================================

set -e

NGINX_DIR="/opt/nginx"

# 确保日志目录存在且可写
mkdir -p ${NGINX_DIR}/logs 2>/dev/null || true
mkdir -p ${NGINX_DIR}/logs/modsec_audit 2>/dev/null || true
touch ${NGINX_DIR}/logs/nginx.pid 2>/dev/null || true

# 确保缓存目录存在且权限正确
# 注意：容器以 root 运行（nginx master 需要 root 绑定端口），workers 以 www-data 运行
for dir in client_temp proxy_temp proxy_cache fastcgi_temp uwsgi_temp scgi_temp; do
    mkdir -p /var/cache/nginx/${dir} 2>/dev/null || true
    chown www-data:www-data /var/cache/nginx/${dir} 2>/dev/null || true
done

# 确保网站目录存在
mkdir -p /www/wwwroot/html 2>/dev/null || true

# Nginx 配置测试
if [ "$1" = "/opt/nginx/sbin/nginx" ] || [ "$1" = "nginx" ]; then
    echo "正在验证 Nginx 配置..."
    if ! /opt/nginx/sbin/nginx -t 2>&1; then
        echo "错误: Nginx 配置验证未通过，请检查配置文件" >&2
        exit 1
    fi
fi

# 执行主命令
exec "$@"
