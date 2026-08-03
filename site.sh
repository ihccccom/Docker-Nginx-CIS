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

SITE_TEMPLATE_FILE="$SITE_CONF_DIR/example.com.conf.template"

SITE_NGINX_ROOT_DIR="$SITE_DIR/wwwroot"


SITE_ACME_HOME="$HOME/.acme.sh"

ACME_BIN=""

DNS_API=""



# =====================================================
# 获取 acme.sh
# =====================================================


get_acme_bin()
{

    if command -v acme.sh >/dev/null 2>&1
    then
        command -v acme.sh
        return
    fi


    if [ -x "$SITE_ACME_HOME/acme.sh" ]
    then
        echo "$SITE_ACME_HOME/acme.sh"
        return
    fi

}



# =====================================================
# 安装 acme.sh
# =====================================================


setup_acme()
{


    local bin

    bin=$(get_acme_bin || true)



    if [ -z "$bin" ]
    then

        echo "❌ 未检测到 acme.sh"


        read -r -p "请输入 acme.sh 注册邮箱: " email



        curl https://get.acme.sh | \
        sh -s email="$email"



        bin=$(get_acme_bin || true)



        if [ -z "$bin" ]
        then

            echo "❌ acme.sh 安装失败"

            exit 1

        fi

    fi



    ACME_BIN="$bin"



    echo

    echo "✅ acme.sh:"
    echo "$ACME_BIN"



    "$ACME_BIN" \
    --set-default-ca \
    --server letsencrypt



}




# =====================================================
# DNS API
# =====================================================



select_dns()
{

echo

echo "支持:"
echo "dns_cf"
echo "dns_ali"
echo "dns_dp"

echo


read -r -p "请输入 DNS API: " DNS_API



if [ -z "$DNS_API" ]
then

echo "DNS API不能为空"

exit 1

fi


}



setup_dns_env()
{


echo

echo "请输入 DNS API 环境变量"

echo

echo "例如:"
echo 'export CF_Token="xxxx"'


read -r -p "> " ENV_CMD



if [ -n "$ENV_CMD" ]
then

eval "$ENV_CMD"

fi


}




# =====================================================
# 域名验证
# =====================================================


check_domain()
{

[[ "$1" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]

}




# =====================================================
# 获取根域名
# =====================================================


root_domain()
{

echo "$1" | awk -F. '{print $(NF-1)"."$NF}'

}




# =====================================================
# SSL证书处理
# =====================================================


issue_ssl()
{


DOMAIN="$1"


ROOT=$(root_domain "$DOMAIN")


SSL_DIR="$SITE_SSL_BASE_DIR/$ROOT"



mkdir -p "$SSL_DIR"



echo

echo "检查证书:"
echo "$ROOT"



# -----------------------------------------------------
# 判断已有证书
# -----------------------------------------------------


if "$ACME_BIN" --list | grep -q "$ROOT"
then


echo "✅ 已存在证书"

echo "跳过申请"


else


echo "申请新证书"

echo "*.$ROOT"
echo "$ROOT"



"$ACME_BIN" \
--issue \
-d "*.$ROOT" \
-d "$ROOT" \
--dns "$DNS_API" \
--keylength ec-256



fi




# -----------------------------------------------------
# 安装证书
# -----------------------------------------------------


echo

echo "安装证书"



"$ACME_BIN" \
--install-cert \
-d "*.$ROOT" \
-d "$ROOT" \
\
--key-file "$SSL_DIR/privkey.pem" \
\
--cert-file "$SSL_DIR/cert.pem" \
\
--fullchain-file "$SSL_DIR/fullchain.pem" \
\
--ca-file "$SSL_DIR/ca.pem" \
\
--reloadcmd "docker exec nginx nginx -s reload"



echo

echo "✅ SSL完成"

ls -lh "$SSL_DIR"


}




# =====================================================
# 创建网站
# =====================================================


create_site()
{


DOMAINS="$1"



for DOMAIN in $DOMAINS
do



if ! check_domain "$DOMAIN"
then

echo "❌ 非法域名:"
echo "$DOMAIN"

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





# -----------------------------------------------------
# nginx配置
# -----------------------------------------------------


if [ ! -f "$CONF_FILE" ]
then


if [ ! -f "$SITE_TEMPLATE_FILE" ]
then

echo "❌ 模板不存在:"
echo "$SITE_TEMPLATE_FILE"

exit 1

fi



cp "$SITE_TEMPLATE_FILE" "$CONF_FILE"



ln -sf \
"../sites-available/$DOMAIN.conf" \
"$SITE_ENABLED_DIR/$DOMAIN.conf"



fi




sed -i \
"s/%DOMAIN%/$DOMAIN/g" \
"$CONF_FILE"



sed -i \
"s/%ROOT_DOMAIN%/$ROOT/g" \
"$CONF_FILE"





# -----------------------------------------------------
# ModSecurity
# -----------------------------------------------------


if [ ! -f "$MODSEC_FILE" ]
then


cat > "$MODSEC_FILE" <<EOF

SecRuleEngine On

SecRequestBodyAccess On

SecResponseBodyAccess On

EOF


fi





# -----------------------------------------------------
# WordPress
# -----------------------------------------------------


if [ ! -d "$WEB_ROOT/wp-admin" ]
then


echo

echo "下载 WordPress"



curl -L \
https://wordpress.org/latest.tar.gz \
-o /tmp/latest-wordpress.tar.gz




tar xf \
/tmp/latest-wordpress.tar.gz \
-C "$WEB_ROOT" \
--strip-components=1




rm -f \
/tmp/latest-wordpress.tar.gz



else


echo "✅ WordPress 已存在，跳过"


fi





# -----------------------------------------------------
# SSL
# -----------------------------------------------------


issue_ssl "$DOMAIN"





echo

echo "=============================="

echo "网站完成"

echo "域名:"
echo "$DOMAIN"

echo "目录:"
echo "$WEB_ROOT"

echo "配置:"
echo "$CONF_FILE"

echo "=============================="



done



}






# =====================================================
# 主菜单
# =====================================================


while true
do


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
