#!/bin/sh
# =======================================================
# Nginx Docker 入口脚本
# 负责运行时初始化和权限检查
# =======================================================

set -e

NGINX_DIR="/opt/nginx"
SEED_ROOT="/opt/config-seed"

# 0. 首次运行 / 手动清空重置时，从镜像内置种子自动初始化 conf / conf.d / ssl
for d in conf ssl conf.d; do
    LIVE_DIR="${NGINX_DIR}/${d}"
    SEED_DIR="${SEED_ROOT}/${d}"
    if [ -d "${SEED_DIR}" ] && [ -z "$(ls -A "${LIVE_DIR}" 2>/dev/null)" ]; then
        echo "检测到 ${LIVE_DIR} 为空，正在从镜像内置副本初始化..."
        cp -a "${SEED_DIR}/." "${LIVE_DIR}/"
    fi
done

# 0b. 宿主机 bind-mount ./conf 时，仓库内通常没有 OWASP CRS rules/plugins。
#     若运行时缺失，从镜像种子补齐，避免盖掉镜像内 WAF 规则。
MODSEC_LIVE="${NGINX_DIR}/conf/modsecurity"
MODSEC_SEED="${SEED_ROOT}/conf/modsecurity"
if [ -d "${MODSEC_SEED}" ]; then
    for asset in rules plugins; do
        if [ -d "${MODSEC_SEED}/${asset}" ] && [ ! -d "${MODSEC_LIVE}/${asset}" ]; then
            echo "检测到 ModSecurity ${asset} 缺失，正在从镜像种子同步..."
            mkdir -p "${MODSEC_LIVE}"
            cp -a "${MODSEC_SEED}/${asset}" "${MODSEC_LIVE}/"
        fi
    done
    # unicode.mapping 等二进制映射文件缺失时也会导致 WAF 启动失败
    if [ -f "${MODSEC_SEED}/unicode.mapping" ] && [ ! -f "${MODSEC_LIVE}/unicode.mapping" ]; then
        cp -a "${MODSEC_SEED}/unicode.mapping" "${MODSEC_LIVE}/unicode.mapping"
    fi
fi

# 1. 同步 sites-available → sites-enabled（仅为从未处理过的新配置创建软链，不覆盖用户手动禁用的站点）
AVAILABLE_DIR="${NGINX_DIR}/conf.d/sites-available"
ENABLED_DIR="${NGINX_DIR}/conf.d/sites-enabled"
mkdir -p "${AVAILABLE_DIR}" "${ENABLED_DIR}"
if [ -d "${AVAILABLE_DIR}" ]; then
    for conf_file in "${AVAILABLE_DIR}"/*.conf; do
        [ -e "${conf_file}" ] || continue
        base_name=$(basename "${conf_file}")
        link_path="${ENABLED_DIR}/${base_name}"
        marker_path="${ENABLED_DIR}/.${base_name}.seen"
        if [ ! -e "${marker_path}" ]; then
            ln -sf "../sites-available/${base_name}" "${link_path}"
            touch "${marker_path}"
        fi
    done
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
if [ -d "${NGINX_DIR}/conf/modsecurity" ]; then
    find ${NGINX_DIR}/conf/modsecurity -type d -exec chmod 700 {} \;
    find ${NGINX_DIR}/conf/modsecurity -type f -name "*.conf" -exec chmod 600 {} \;
    chown -R root:root ${NGINX_DIR}/conf/modsecurity
fi
chown -R www-data:www-data ${NGINX_DIR}/logs/modsec_audit

# 5. 修复日志与缓存目录权限
mkdir -p ${NGINX_DIR}/logs
touch ${NGINX_DIR}/logs/nginx.pid

chmod 750 ${NGINX_DIR}/logs
chown -R root:www-data ${NGINX_DIR}/logs
chmod u-x,go-wx ${NGINX_DIR}/logs/nginx.pid

# 6. 批量检查并修正 /www/wwwroot 下网站根目录属主
WWWROOT_BASE="/www/wwwroot"
TARGET_USER="www-data"
TARGET_GROUP="www-data"

if [ -d "$WWWROOT_BASE" ]; then
    echo "正在检查 $WWWROOT_BASE 下的网站根目录..."
    for site_dir in "$WWWROOT_BASE"/*; do
        if [ -d "$site_dir" ]; then
            CURRENT_OWNER=$(stat -c '%U:%G' "$site_dir" 2>/dev/null || stat -f '%Su:%Sg' "$site_dir" 2>/dev/null)
            if [ "$CURRENT_OWNER" != "$TARGET_USER:$TARGET_GROUP" ]; then
                echo "目录 $(basename "$site_dir") 属主为 [$CURRENT_OWNER]，修正为 [$TARGET_USER:$TARGET_GROUP]..."
                chown -R "$TARGET_USER:$TARGET_GROUP" "$site_dir"
            fi
            chmod 755 "$site_dir"
        fi
    done
else
    echo "目录 $WWWROOT_BASE 不存在，跳过检查。"
fi

if [ -d "/www/wwwroot/html" ]; then
    find /www/wwwroot/html -type f ! -perm 444 -exec chmod 444 {} \; 2>/dev/null || true
fi

# 7. 确保缓存与 ModSecurity 临时目录存在（只读根 + tmpfs 场景必需）
# 注意：容器以 root 运行（nginx master 绑定 80/443），workers 以 www-data 运行
mkdir -p /var/cache/nginx
for dir in client_temp proxy_temp proxy_cache fastcgi_temp uwsgi_temp scgi_temp modsec; do
    mkdir -p "/var/cache/nginx/${dir}" 2>/dev/null || true
    chown www-data:www-data "/var/cache/nginx/${dir}" 2>/dev/null || true
done
chown -R www-data:www-data /var/cache/nginx 2>/dev/null || true

# 8. Nginx 配置测试
if [ "$1" = "${NGINX_DIR}/sbin/nginx" ] || [ "$1" = "nginx" ]; then
    echo "正在验证 Nginx 配置..."
    if ! ${NGINX_DIR}/sbin/nginx -t 2>&1; then
        echo "错误: Nginx 配置验证未通过，请检查配置文件" >&2
        exit 1
    fi
fi

exec "$@"
