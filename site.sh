#!/bin/bash
set -euo pipefail

# =====================================================
# Nginx Docker 网站自动化管理
# acme.sh + DNS API + Wildcard SSL + WordPress
# =====================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE_DIR="$SCRIPT_DIR"

SITE_CONF_DIR="$SITE_DIR/conf.d/sites-available"
SITE_ENABLED_DIR="$SITE_DIR/conf.d/sites-enabled"
SITE_MODSEC_DIR="$SITE_DIR/conf/modsecurity"
SITE_SSL_BASE_DIR="$SITE_DIR/ssl"
SITE_NGINX_ROOT_DIR="$SITE_DIR/wwwroot"

# 优先使用 conf.d 中的模板；若不存在则回退到仓库 conf/ 模板
SITE_TEMPLATE_FILE="$SITE_CONF_DIR/example.com.conf.template"
if [ ! -f "$SITE_TEMPLATE_FILE" ]; then
    SITE_TEMPLATE_FILE="$SITE_DIR/conf/example.com.conf.template"
fi

SITE_ACME_HOME="$HOME/.acme.sh"
ACME_BIN=""
DNS_API=""

# 已知多级公共后缀（简化版；复杂场景请改用 publicsuffix 库）
MULTI_PART_TLDS="co.uk|org.uk|ac.uk|gov.uk|com.au|net.au|org.au|com.br|com.cn|com.hk|com.tw|co.jp|co.kr|co.in|com.sg"

get_acme_bin() {
    if command -v acme.sh >/dev/null 2>&1; then
        command -v acme.sh
        return
    fi
    if [ -x "$SITE_ACME_HOME/acme.sh" ]; then
        echo "$SITE_ACME_HOME/acme.sh"
        return
    fi
}

setup_acme() {
    local bin
    bin=$(get_acme_bin || true)

    if [ -z "$bin" ]; then
        echo "未检测到 acme.sh"
        read -r -p "请输入 acme.sh 注册邮箱: " email
        curl -fsSL https://get.acme.sh | sh -s email="$email"
        bin=$(get_acme_bin || true)
        if [ -z "$bin" ]; then
            echo "acme.sh 安装失败"
            exit 1
        fi
    fi

    ACME_BIN="$bin"
    echo
    echo "acme.sh: $ACME_BIN"
    "$ACME_BIN" --set-default-ca --server letsencrypt
}

select_dns() {
    echo
    echo "支持:"
    echo "dns_cf"
    echo "dns_ali"
    echo "dns_dp"
    echo
    read -r -p "请输入 DNS API: " DNS_API
    if [ -z "$DNS_API" ]; then
        echo "DNS API不能为空"
        exit 1
    fi
}

# 安全地设置 DNS API 凭证：只接受 KEY=VALUE，禁止任意 shell
setup_dns_env() {
    echo
    echo "请输入 DNS API 环境变量（格式 KEY=VALUE，可多行，空行结束）"
    echo "例如:"
    echo "CF_Token=xxxx"
    echo "CF_Account_ID=yyyy"
    echo

    while true; do
        read -r -p "> " ENV_LINE || true
        if [ -z "${ENV_LINE:-}" ]; then
            break
        fi
        # 拒绝命令替换、管道、分号等
        case "$ENV_LINE" in
            *'$('*|*'`'*|*';'*|*'|'*|*'&'*|*'>'*|*'<'*|*"'"*|*'\'* )
                echo "拒绝不安全输入，请只使用 KEY=VALUE"
                exit 1
                ;;
        esac
        if [[ ! "$ENV_LINE" =~ ^[A-Za-z_][A-Za-z0-9_]*=.+$ ]]; then
            echo "格式无效，请使用 KEY=VALUE"
            exit 1
        fi
        local key="${ENV_LINE%%=*}"
        local val="${ENV_LINE#*=}"
        export "$key=$val"
        echo "已设置: $key"
    done
}

check_domain() {
    [[ "$1" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]
}

root_domain() {
    local host="$1"
    local labels parts
    IFS='.' read -r -a parts <<< "$host"
    local n=${#parts[@]}
    if [ "$n" -lt 2 ]; then
        echo "$host"
        return
    fi
    local last2="${parts[$((n-2))]}.${parts[$((n-1))]}"
    if [ "$n" -ge 3 ] && echo "$last2" | grep -Eq "^($MULTI_PART_TLDS)$"; then
        echo "${parts[$((n-3))]}.${last2}"
    else
        echo "$last2"
    fi
}

issue_ssl() {
    DOMAIN="$1"
    ROOT=$(root_domain "$DOMAIN")
    SSL_DIR="$SITE_SSL_BASE_DIR/$ROOT"
    mkdir -p "$SSL_DIR"

    echo
    echo "检查证书: $ROOT"

    if ! "$ACME_BIN" --list | grep -q "$ROOT"; then
        echo "申请新证书: $ROOT / *.$ROOT"
        "$ACME_BIN" \
            --issue \
            -d "*.$ROOT" \
            -d "$ROOT" \
            --dns "$DNS_API" \
            --keylength ec-256
    else
        echo "已存在证书，跳过申请"
    fi

    echo "安装证书到 $SSL_DIR"
    "$ACME_BIN" \
        --install-cert \
        -d "*.$ROOT" \
        -d "$ROOT" \
        --key-file "$SSL_DIR/privkey.pem" \
        --cert-file "$SSL_DIR/cert.pem" \
        --fullchain-file "$SSL_DIR/fullchain.pem" \
        --ca-file "$SSL_DIR/ca.pem" \
        --reloadcmd "docker exec nginx /opt/nginx/sbin/nginx -s reload || true"

    chmod 600 "$SSL_DIR/fullchain.pem" "$SSL_DIR/cert.pem" "$SSL_DIR/ca.pem" 2>/dev/null || true
    chmod 400 "$SSL_DIR/privkey.pem" 2>/dev/null || true
    echo "SSL 完成"
    ls -lh "$SSL_DIR"
}

download_wordpress() {
    local dest="$1"
    local tmp archive expected
    tmp="$(mktemp -d)"
    archive="$tmp/latest-wordpress.tar.gz"
    expected="$tmp/wordpress.tar.gz.sha1"

    echo "下载 WordPress（带 SHA1 校验）..."
    curl -fsSL "https://wordpress.org/latest.tar.gz" -o "$archive"
    curl -fsSL "https://wordpress.org/latest.tar.gz.sha1" -o "$expected" || true

    if [ -s "$expected" ]; then
        local got want
        got=$(sha1sum "$archive" | awk '{print $1}')
        want=$(tr -d ' \t\r\n' < "$expected")
        if [ "$got" != "$want" ]; then
            echo "WordPress 校验失败: got=$got want=$want"
            rm -rf "$tmp"
            exit 1
        fi
        echo "WordPress SHA1 校验通过"
    else
        echo "警告: 未能获取官方 SHA1，跳过校验继续安装"
    fi

    tar xf "$archive" -C "$dest" --strip-components=1
    rm -rf "$tmp"
}

create_site() {
    DOMAINS="$1"

    for DOMAIN in $DOMAINS; do
        if ! check_domain "$DOMAIN"; then
            echo "非法域名: $DOMAIN"
            continue
        fi

        ROOT=$(root_domain "$DOMAIN")
        WEB_ROOT="$SITE_NGINX_ROOT_DIR/$DOMAIN"
        CONF_FILE="$SITE_CONF_DIR/$DOMAIN.conf"
        MODSEC_FILE="$SITE_MODSEC_DIR/$DOMAIN.conf"

        mkdir -p \
            "$WEB_ROOT" \
            "$SITE_CONF_DIR" \
            "$SITE_ENABLED_DIR" \
            "$SITE_MODSEC_DIR" \
            "$SITE_SSL_BASE_DIR"

        if [ ! -f "$CONF_FILE" ]; then
            if [ ! -f "$SITE_TEMPLATE_FILE" ]; then
                echo "模板不存在: $SITE_TEMPLATE_FILE"
                exit 1
            fi
            cp "$SITE_TEMPLATE_FILE" "$CONF_FILE"
            ln -sf "../sites-available/$DOMAIN.conf" "$SITE_ENABLED_DIR/$DOMAIN.conf"
        fi

        sed -i "s/%DOMAIN%/$DOMAIN/g" "$CONF_FILE"
        sed -i "s/%ROOT_DOMAIN%/$ROOT/g" "$CONF_FILE"

        if [ ! -f "$MODSEC_FILE" ]; then
            cat > "$MODSEC_FILE" <<'EOF'
# 站点级 ModSecurity 覆盖（按需启用）
# SecRuleEngine On
# SecRequestBodyAccess On
EOF
        fi

        if [ ! -d "$WEB_ROOT/wp-admin" ]; then
            echo
            download_wordpress "$WEB_ROOT"
        else
            echo "WordPress 已存在，跳过"
        fi

        issue_ssl "$DOMAIN"

        echo
        echo "=============================="
        echo "网站完成"
        echo "域名: $DOMAIN"
        echo "目录: $WEB_ROOT"
        echo "配置: $CONF_FILE"
        echo "=============================="
    done
}

while true; do
    echo
    echo "================================"
    echo " Nginx Docker 网站管理"
    echo "================================"
    echo "1) 创建网站"
    echo "0) 退出"
    read -r -p "> " ACTION

    case "$ACTION" in
        1)
            setup_acme
            read -r -p "请输入域名: " DOMAIN_INPUT
            select_dns
            setup_dns_env
            create_site "$DOMAIN_INPUT"
            ;;
        0)
            exit 0
            ;;
        *)
            echo "错误"
            ;;
    esac
done
