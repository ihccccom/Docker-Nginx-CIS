#!/bin/sh
# =======================================================
# Nginx Docker 入口脚本
# 负责运行时初始化和权限检查
# =======================================================

set -e

NGINX_DIR="/opt/nginx"

# 0. 首次运行 / 手动清空重置时，从镜像内置种子自动初始化 conf 和 conf.d
SEED_ROOT="/opt/config-seed"
for d in conf conf.d; do
    LIVE_DIR="${NGINX_DIR}/${d}"
    SEED_DIR="${SEED_ROOT}/${d}"
    if [ -d "${SEED_DIR}" ] && [ -z "$(ls -A "${LIVE_DIR}" 2>/dev/null)" ]; then
        echo "检测到 ${LIVE_DIR} 为空，正在从镜像内置副本初始化..."
        cp -a "${SEED_DIR}/." "${LIVE_DIR}/"
    fi
done

# 1. 同步 sites-available → sites-enabled（仅为从未处理过的新配置创建软链，不覆盖用户手动禁用的站点）
AVAILABLE_DIR="${NGINX_DIR}/conf.d/sites-available"
ENABLED_DIR="${NGINX_DIR}/conf.d/sites-enabled"
if [ -d "${AVAILABLE_DIR}" ]; then
    for conf_file in "${AVAILABLE_DIR}"/*.conf; do
        [ -e "${conf_file}" ] || continue   # 目录为空时 glob 不展开，防止把字面量当文件名处理
        base_name=$(basename "${conf_file}")
        link_path="${ENABLED_DIR}/${base_name}"
        marker_path="${ENABLED_DIR}/.${base_name}.seen"
        # 只有从没见过这个文件（无标记文件）时才自动建链，用户手动删除软链后不会被重新加回
        if [ ! -e "${marker_path}" ]; then
            ln -sf "../sites-available/${base_name}" "${link_path}"
            touch "${marker_path}"
        fi
    done
    # 清理软链目标已不存在的悬空链接（站点被彻底从 available 删除时同步清理）
    find "${ENABLED_DIR}" -maxdepth 1 -name "*.conf" -xtype l -delete 2>/dev/null || true
fi

# 2. 修复主配置与子目录权限
find ${NGINX_DIR}/conf -type d -exec chmod 700 {} \;
find ${NGINX_DIR}/conf -type f -exec chmod 600 {} \;
find ${NGINX_DIR}/conf.d -type d -exec chmod 700 {} \;
find ${NGINX_DIR}/conf.d -type f -exec chmod 600 {} \;

# 3. 修复 SSL 证书及密钥权限
[ -d "${NGINX_DIR}/ssl" ] && chmod 700 ${NGINX_DIR}/ssl
[ -d "${NGINX_DIR}/ssl/default" ] && chmod 700 ${NGINX_DIR}/ssl/default
find ${NGINX_DIR}/ssl -type f -name "*.key" -exec chmod 400 {} \;
find ${NGINX_DIR}/ssl -type f -name "*.pem" -exec chmod 600 {} \;
[ -f "${NGINX_DIR}/ssl/dhparam.pem" ] && chmod 600 ${NGINX_DIR}/ssl/dhparam.pem

# 4. 修复 ModSecurity 规则与日志权限
mkdir -p ${NGINX_DIR}/logs/modsec_audit
find ${NGINX_DIR}/conf/modsecurity -type d -exec chmod 700 {} \;
find ${NGINX_DIR}/conf/modsecurity -type f -name "*.conf" -exec chmod 600 {} \;
chown -R root:root ${NGINX_DIR}/conf/modsecurity 
chown -R www-data:www-data ${NGINX_DIR}/logs/modsec_audit


# 5. 修复日志与缓存目录权限
mkdir -p ${NGINX_DIR}/logs
touch ${NGINX_DIR}/logs/nginx.pid

chmod 750 ${NGINX_DIR}/logs
chown -R root:www-data ${NGINX_DIR}/logs
touch ${NGINX_DIR}/logs/nginx.pid && chmod u-x,go-wx ${NGINX_DIR}/logs/nginx.pid
chown -R www-data:www-data /var/cache/nginx

# =======================================================
# 6. 初始化网站根目录（如果不存在则创建并赋予权限）
# =======================================================
if [ ! -d "/www/wwwroot/html" ]; then
    mkdir -p /www/wwwroot/html
    chown -R www-data:www-data /www/wwwroot/html
    chmod 755 /www/wwwroot/html
fi

# 如果里面有文件需要确保只读，也可以加上判断（可选）
if [ -d "/www/wwwroot/html" ]; then
    find /www/wwwroot/html -type f ! -perm 444 -exec chmod 444 {} \; 2>/dev/null || true
fi


# 7. 确保缓存目录存在且权限正确
# 注意：容器以 root 运行（nginx master 需要 root 绑定端口），workers 以 www-data 运行
for dir in client_temp proxy_temp proxy_cache fastcgi_temp uwsgi_temp scgi_temp; do
    mkdir -p /var/cache/nginx/${dir} 2>/dev/null || true
    chown www-data:www-data /var/cache/nginx/${dir}
done

# 8. Nginx 配置测试
if [ "$1" = "${NGINX_DIR}/sbin/nginx" ] || [ "$1" = "nginx" ]; then
    echo "正在验证 Nginx 配置..."
    if ! ${NGINX_DIR}/sbin/nginx -t 2>&1; then
        echo "错误: Nginx 配置验证未通过，请检查配置文件" >&2
        exit 1
    fi
fi

# 执行主命令
exec "$@"
