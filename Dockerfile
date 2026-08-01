# =======================================================
# Nginx Docker 构建文件
# 基于 nginx-install.sh 编写
# 符合 CIS Docker Benchmark 和 CIS Nginx Benchmark
# 高安全、高性能配置
# =======================================================
#
# 构建示例:
#   docker build -t nginx .
#   docker build --build-arg USE_modsecurity=false -t nginx .
#   docker build --build-arg NGINX_FAKE_NAME="MyServer" -t nginx .
#
# 运行示例:
#   docker run -d -p 80:80 -p 443:443 --name nginx nginx
#   docker compose up -d
#

###############################################
# 第三方插件开关 (Third-party Plugin Toggles)
# 设置为 "true" 启用，"false" 禁用
# 构建时可通过 --build-arg 覆盖
###############################################

# ngx-fancyindex 美化目录浏览模块
ARG USE_ngx_fancyindex=true

# PCRE2 正则表达式模块
ARG USE_PCRE2=true

# ngx_cache_purge 缓存清除模块
ARG USE_ngx_cache_purge=true

# ngx_http_headers_more_filter_module 自定义响应头模块
ARG USE_ngx_http_headers_more_filter_module=true

# ngx_brotli 压缩模块
ARG USE_ngx_brotli=true

# openssl 使用自编译 OpenSSL（高版本/高性能）
ARG USE_openssl=true

# modsecurity Web 应用防火墙引擎
ARG USE_modsecurity=true

# OWASP 核心规则集
ARG USE_owasp=true

# modsecurity-nginx 连接器模块
ARG USE_modsecurity_nginx=true

###############################################
# 版本配置 (Version Configuration)
# 留空 "" 表示自动获取最新版本
# 填写具体版本号表示使用指定版本
# 构建时可通过 --build-arg 覆盖
###############################################

# Nginx 版本 (必须手动指定)
ARG NGINX_VERSION=1.30.4

# OpenSSL 版本 (必须手动指定)
ARG OPENSSL_VERSION=3.5.7

# PCRE2 版本 (留空自动获取最新版, 例如: "pcre2-10.45")
ARG PCRE2_VERSION="pcre2-10.47"

# ngx-fancyindex 版本 (留空自动获取最新版, 例如: "0.5.2")
ARG FANCYINDEX_VERSION=0.6.0

# ngx_cache_purge 版本 (留空自动获取最新版, 例如: "2.3")
ARG NGX_CACHE_PURGE_VERSION="2.3"

# headers-more-nginx-module 版本 (留空自动获取最新版, 例如: "0.38")
ARG HEADERS_MORE_VERSION="0.40"

# ModSecurity-nginx 连接器版本 (留空使用最新版, 例如: "v1.0.3")
ARG MODSECURITY_NGINX_VERSION="v1.0.4"

# OWASP CRS 规则集版本 (留空自动获取最新版, 例如: "v4.8.0")
ARG OWASP_CRS_VERSION="v4.28.0"

# ModSecurity 核心引擎版本
ARG MODSECURITY_VERSION="v3.0.16"


###############################################
# 自定义模块入口 (Extra Nginx Modules)
# 1. EXTRA_NGINX_MODULES: 可添加额外的 --add-module 或 --add-dynamic-module 参数
# 2. EXTRA_GITHUB_MODULES: 可通过 GitHub 动态下载并编译模块
#    格式: "作者/仓库名/分支或标签[/static|dynamic]" (多个用空格隔开)
#    第4段可省略，省略时默认按 dynamic（动态）编译
# 填写示例:
#   ARG EXTRA_NGINX_MODULES="--add-dynamic-module=/opt/nginx/src/my-custom-module"
#   ARG EXTRA_GITHUB_MODULES="chobits/ngx_http_proxy_connect_module/v0.0.5/static simplified/ngx_devel_kit/master"
###############################################
ARG EXTRA_NGINX_MODULES=""
ARG EXTRA_GITHUB_MODULES=""

###############################################
# Nginx 伪装配置 (Server Identity)
# 隐藏真实 Nginx 版本信息，增强安全性
###############################################

# 自定义服务器名称 (例如: "OWASP WAF")，留空使用默认值
ARG NGINX_FAKE_NAME="CloudFlare"

# 自定义版本号 (例如: "5.1.24")，留空使用默认版本号
ARG NGINX_VERSION_NUMBER="8.2.6"


# =======================================================
# Stage 1: 编译阶段 (Build Stage)
# 使用完整 Debian 进行编译，最终镜像只保留运行时文件
# =======================================================
FROM debian:trixie-slim AS builder

# hadolint ignore=DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 重新声明所有 ARGs（FROM 之后 ARG 需要重新声明）
ARG USE_ngx_fancyindex
ARG USE_PCRE2
ARG USE_ngx_cache_purge
ARG USE_ngx_http_headers_more_filter_module
ARG USE_ngx_brotli
ARG USE_openssl
ARG USE_modsecurity
ARG USE_owasp
ARG USE_modsecurity_nginx
ARG OPENSSL_VERSION
ARG NGINX_VERSION
ARG PCRE2_VERSION
ARG FANCYINDEX_VERSION
ARG NGX_CACHE_PURGE_VERSION
ARG HEADERS_MORE_VERSION
ARG MODSECURITY_NGINX_VERSION
ARG OWASP_CRS_VERSION
ARG EXTRA_NGINX_MODULES
ARG NGINX_FAKE_NAME
ARG NGINX_VERSION_NUMBER
ARG MODSECURITY_VERSION
ARG EXTRA_GITHUB_MODULES

ENV DEBIAN_FRONTEND=noninteractive \
    OPT_DIR=/opt \
    NGINX_DIR=/opt/nginx \
    NGINX_SRC_DIR=/opt/nginx/src

# 安装编译依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    build-essential \
    libfuzzy-dev \
    doxygen \
    ruby \
    libssl-dev \
    zlib1g-dev \
    libaio-dev \
    libjemalloc-dev \
    libgd-dev \
    libgeoip-dev \
    libxslt1-dev \
    libbrotli-dev \
    libcurl4-openssl-dev \
    libyaml-dev \
    unzip \
    git \
    cmake \
    gcc \
    g++ \
    make \
    wget \
    pkg-config \
    libpcre2-dev \
    libpcre2-8-0 \
    liblua5.3-dev \
    libmaxminddb0 \
    libmaxminddb-dev \
    liblmdb-dev \
    libtool \
    liblzma-dev \
    autoconf \
    automake \
    gawk \
    libyajl-dev \
    libxml2-dev \
    ca-certificates \
    curl \
    patch \
    && rm -rf /var/lib/apt/lists/*

# 创建构建目录
RUN mkdir -p ${NGINX_SRC_DIR} \
    && chmod 750 ${NGINX_SRC_DIR} \
    && chown root:root ${NGINX_SRC_DIR}

# 下载 Nginx 源码
RUN cd ${NGINX_DIR} \
    && wget --tries=5 --waitretry=2 \
       "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
    && tar -zxf "nginx-${NGINX_VERSION}.tar.gz" \
    && mv "nginx-${NGINX_VERSION}" nginx \
    && rm -f "nginx-${NGINX_VERSION}.tar.gz" \
    && chown -R root:root ${NGINX_DIR}/nginx

# 应用 Nginx 伪装名称补丁（隐藏服务器标识，CIS 合规）
RUN set -eux; \
    if [ -n "${NGINX_FAKE_NAME}" ]; then \
      safe_name=$(printf '%s' "${NGINX_FAKE_NAME}" | sed 's/[&/\\]/\\&/g'); \
      sed -i "s/static u_char ngx_http_server_string\[\] = \"Server: nginx\" CRLF;/static u_char ngx_http_server_string\[\] = \"Server: ${safe_name}\" CRLF;/g" \
        ${NGINX_DIR}/nginx/src/http/ngx_http_header_filter_module.c; \
      sed -i "s/static u_char ngx_http_server_full_string\[\] = \"Server: \" NGINX_VER CRLF;/static u_char ngx_http_server_full_string\[\] = \"Server: ${safe_name}\" CRLF;/g" \
        ${NGINX_DIR}/nginx/src/http/ngx_http_header_filter_module.c; \
      sed -i "s/static u_char ngx_http_server_build_string\[\] = \"Server: \" NGINX_VER_BUILD CRLF;/static u_char ngx_http_server_build_string\[\] = \"Server: ${safe_name}\" CRLF;/g" \
        ${NGINX_DIR}/nginx/src/http/ngx_http_header_filter_module.c; \
      sed -i "s/<hr><center>\" NGINX_VER_BUILD \"<\/center>\" CRLF/<hr><center>${safe_name}<\/center>\" CRLF/" \
        ${NGINX_DIR}/nginx/src/http/ngx_http_special_response.c; \
      sed -i "s/<hr><center>nginx<\/center>\" CRLF/<hr><center>${safe_name}<\/center>\" CRLF/" \
        ${NGINX_DIR}/nginx/src/http/ngx_http_special_response.c; \
      sed -i "s/<hr><center>\" NGINX_VER \"<\/center>\" CRLF/<hr><center>${safe_name}<\/center>\" CRLF/" \
        ${NGINX_DIR}/nginx/src/http/ngx_http_special_response.c; \
    fi
#   这个是影响 nginx -v 或 nginx -V 时，显示的 注释掉
#    if [ -n "${NGINX_VERSION_NUMBER}" ]; then \
#      safe_version=$(printf '%s' "${NGINX_VERSION_NUMBER}" | sed 's/[&/\\]/\\&/g'); \
#      sed -i "s/#define NGINX_VERSION.*\".*\"/#define NGINX_VERSION     \"${safe_version}\"/" \
#        ${NGINX_DIR}/nginx/src/core/nginx.h; \
#    fi; \

# 下载 PCRE2 模块
RUN set -eux; \
    if [ "${USE_PCRE2}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      if [ -n "${PCRE2_VERSION}" ]; then \
        pcre2_version="${PCRE2_VERSION}"; \
      else \
        pcre2_version=$(curl -sSL --retry 5 --retry-delay 2 --retry-connrefused \
          "https://api.github.com/repos/PhilipHazel/pcre2/releases/latest" \
          | grep -oP '"tag_name":\s*"\K[^"]+') || true; \
        if [ -z "$pcre2_version" ]; then pcre2_version="pcre2-10.45"; fi; \
      fi; \
      wget --tries=5 --waitretry=2 \
        "https://github.com/PhilipHazel/pcre2/releases/download/$pcre2_version/$pcre2_version.tar.gz"; \
      tar -zxf "$pcre2_version.tar.gz"; \
      mv "$pcre2_version" pcre2; \
      rm -f "$pcre2_version.tar.gz"; \
    fi

# 下载 OpenSSL
RUN set -eux; \
    if [ "${USE_openssl}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      wget --tries=5 --waitretry=2 \
        "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"; \
      tar -zxf "openssl-${OPENSSL_VERSION}.tar.gz"; \
      mv "openssl-${OPENSSL_VERSION}" openssl; \
      rm -f "openssl-${OPENSSL_VERSION}.tar.gz"; \
    fi

# 下载 ngx_brotli 压缩模块
RUN set -eux; \
    if [ "${USE_ngx_brotli}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      git clone --recursive --depth 1 https://github.com/google/ngx_brotli.git; \
      cd ngx_brotli; \
      git submodule update --init; \
    fi

# 下载 ngx_cache_purge 缓存清除模块
RUN set -eux; \
    if [ "${USE_ngx_cache_purge}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      if [ -n "${NGX_CACHE_PURGE_VERSION}" ]; then \
        version="${NGX_CACHE_PURGE_VERSION}"; \
      else \
        version=$(curl -s --retry 5 --retry-delay 2 --retry-connrefused \
          "https://api.github.com/repos/FRiCKLE/ngx_cache_purge/tags" \
          | grep -o '"name": "[^"]*' | head -n 1 | cut -d '"' -f 4) || true; \
        if [ -z "$version" ]; then version="2.3"; fi; \
      fi; \
      wget --tries=5 --waitretry=2 \
        "https://github.com/FRiCKLE/ngx_cache_purge/archive/refs/tags/$version.zip"; \
      unzip "$version.zip"; \
      mv "ngx_cache_purge-$version" ngx_cache_purge; \
      rm -f "$version.zip"; \
    fi

# 下载 ngx_http_headers_more_filter_module 自定义响应头模块
RUN set -eux; \
    if [ "${USE_ngx_http_headers_more_filter_module}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      if [ -n "${HEADERS_MORE_VERSION}" ]; then \
        version="${HEADERS_MORE_VERSION}"; \
      else \
        version=$(curl -s --retry 5 --retry-delay 2 --retry-connrefused \
          "https://api.github.com/repos/openresty/headers-more-nginx-module/tags" \
          | grep -o '"name": "[^"]*' | head -n 1 | cut -d '"' -f 4 | sed 's/^v//') || true; \
        if [ -z "$version" ]; then version="0.38"; fi; \
      fi; \
      wget --tries=5 --waitretry=2 \
        "https://github.com/openresty/headers-more-nginx-module/archive/refs/tags/v${version}.tar.gz"; \
      tar -xzf "v${version}.tar.gz"; \
      mv "headers-more-nginx-module-${version}" headers-more-nginx-module; \
      rm -f "v${version}.tar.gz"; \
    fi

# 通用 GitHub 第三方模块动态下载逻辑（支持通过 EXTRA_GITHUB_MODULES 传入并下载）
RUN set -eux; \
    if [ -n "${EXTRA_GITHUB_MODULES}" ]; then \
      cd ${NGINX_SRC_DIR}; \
      for mod_item in ${EXTRA_GITHUB_MODULES}; do \
        repo_owner=$(echo "${mod_item}" | cut -d'/' -f1); \
        repo_name=$(echo "${mod_item}" | cut -d'/' -f2); \
        repo_tag=$(echo "${mod_item}" | cut -d'/' -f3); \
        \
        if [ -z "${repo_tag}" ]; then \
          repo_tag="main"; \
        fi; \
        \
        echo "正在下载第三方模块: ${repo_owner}/${repo_name} (${repo_tag})..."; \
        wget --tries=5 --waitretry=2 \
          "https://github.com/${repo_owner}/${repo_name}/archive/refs/tags/${repo_tag}.zip" \
          -O "${repo_name}-${repo_tag}.zip" || \
        wget --tries=5 --waitretry=2 \
          "https://github.com/${repo_owner}/${repo_name}/archive/refs/heads/${repo_tag}.zip" \
          -O "${repo_name}-${repo_tag}.zip"; \
        \
        unzip "${repo_name}-${repo_tag}.zip"; \
        rm -f "${repo_name}-${repo_tag}.zip"; \
        \
        unzipped_dir=$(ls -d ${repo_name}-* | grep -v '\.zip$' | head -n 1); \
        if [ -d "${unzipped_dir}" ] && [ "${unzipped_dir}" != "${repo_name}" ]; then \
          mv "${unzipped_dir}" "${repo_name}"; \
        fi; \
      done; \
    fi

# 下载 ngx_fancyindex 美化目录浏览模块
RUN set -eux; \
    if [ "${USE_ngx_fancyindex}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      wget --tries=5 --waitretry=2 \
        "https://github.com/aperezdc/ngx-fancyindex/releases/download/v${FANCYINDEX_VERSION}/ngx-fancyindex-${FANCYINDEX_VERSION}.tar.xz"; \
      tar -xJf "ngx-fancyindex-${FANCYINDEX_VERSION}.tar.xz"; \
      mv "ngx-fancyindex-${FANCYINDEX_VERSION}" ngx_fancyindex; \
      rm -f "ngx-fancyindex-${FANCYINDEX_VERSION}.tar.xz"; \
    fi

# 编译安装 ModSecurity WAF 引擎
RUN set -eux; \
    if [ "${USE_modsecurity}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      git clone --depth 1 --recursive -b "${MODSECURITY_VERSION}" --single-branch \
        https://github.com/owasp-modsecurity/ModSecurity ModSecurity; \
      cd ModSecurity; \
      ARCH=$(gcc -print-multiarch); \
      sed -ie "s/i386-linux-gnu/${ARCH}/g" build/msc_find_lib.m4; \
      ./build.sh; \
      ./configure --with-yajl --with-ssdeep --with-lmdb --with-pcre2 --with-maxmind --enable-silent-rules; \
      make -j$(nproc) || make; \
      make install; \
      strip /usr/local/modsecurity/lib/lib*.so*; \
    fi

# 下载 ModSecurity-nginx 连接器
RUN set -eux; \
    if [ "${USE_modsecurity_nginx}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      if [ -n "${MODSECURITY_NGINX_VERSION}" ]; then \
        git clone --depth 1 -b "${MODSECURITY_NGINX_VERSION}" \
          https://github.com/owasp-modsecurity/ModSecurity-nginx.git; \
      else \
        git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx.git; \
      fi; \
      chown -R root:root ${NGINX_SRC_DIR}/ModSecurity-nginx; \
    fi

# 确保 ModSecurity 目录存在（即使未编译，COPY 不会失败）
RUN mkdir -p /usr/local/modsecurity/lib

# 配置、编译、安装 Nginx
# 注意：Docker 镜像中去除 -march=native -mtune=native 以保证镜像可移植性
# 如需针对特定 CPU 优化，可通过 --build-arg 传入 EXTRA_CC_OPT="-march=native -mtune=native"
ARG EXTRA_CC_OPT=""
RUN set -eux; \
    cd ${NGINX_DIR}/nginx; \
    EXTRA_ARGS=""; \
    [ "${USE_ngx_cache_purge}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --add-module=${NGINX_SRC_DIR}/ngx_cache_purge" || true; \
    [ "${USE_ngx_brotli}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --add-dynamic-module=${NGINX_SRC_DIR}/ngx_brotli" || true; \
    [ "${USE_ngx_http_headers_more_filter_module}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --add-dynamic-module=${NGINX_SRC_DIR}/headers-more-nginx-module" || true; \
    [ "${USE_modsecurity_nginx}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --add-dynamic-module=${NGINX_SRC_DIR}/ModSecurity-nginx" || true; \
    [ "${USE_openssl}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --with-openssl=${NGINX_SRC_DIR}/openssl" || true; \
    [ "${USE_PCRE2}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --with-pcre=${NGINX_SRC_DIR}/pcre2" || true; \
    [ "${USE_ngx_fancyindex}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --add-dynamic-module=${NGINX_SRC_DIR}/ngx_fancyindex" || true; \
    \
    # 动态把通过 EXTRA_GITHUB_MODULES 下载的模块追加到编译参数中
    if [ -n "${EXTRA_GITHUB_MODULES}" ]; then \
      for mod_item in ${EXTRA_GITHUB_MODULES}; do \
        repo_name=$(echo "${mod_item}" | cut -d'/' -f2); \
        mod_mode=$(echo "${mod_item}" | cut -d'/' -f4); \
        [ -z "${mod_mode}" ] && mod_mode="dynamic"; \
        if [ -d "${NGINX_SRC_DIR}/${repo_name}" ]; then \
          if [ "${mod_mode}" = "static" ]; then \
            EXTRA_ARGS="$EXTRA_ARGS --add-module=${NGINX_SRC_DIR}/${repo_name}"; \
          else \
            EXTRA_ARGS="$EXTRA_ARGS --add-dynamic-module=${NGINX_SRC_DIR}/${repo_name}"; \
          fi; \
        fi; \
      done; \
    fi; \
    \
    if [ -n "${EXTRA_NGINX_MODULES}" ]; then \
      EXTRA_ARGS="$EXTRA_ARGS ${EXTRA_NGINX_MODULES}"; \
    fi; \
    \
    ./configure \
      --prefix=${NGINX_DIR} \
      --user=www-data \
      --group=www-data \
      --with-threads \
      --with-file-aio \
      --with-pcre-jit \
      --with-http_ssl_module \
      --with-http_v2_module \
      --with-http_v3_module \
      --with-http_gzip_static_module \
      --with-http_stub_status_module \
      --with-http_realip_module \
      --with-http_auth_request_module \
      --with-http_sub_module \
      --with-http_addition_module \
      --with-http_image_filter_module \
      --with-http_gunzip_module \
      --with-stream \
      --with-stream_ssl_module \
      --with-stream_ssl_preread_module \
      --with-compat \
      --with-cc-opt="-O3 -pipe -fPIE -fPIC -flto=auto -fstack-protector-strong -Wformat -Werror=format-security -D_FORTIFY_SOURCE=3 ${EXTRA_CC_OPT}" \
      --with-ld-opt='-ljemalloc -flto=auto -fPIE -fPIC -pie -Wl,-z,relro,-z,now -Wl,-O2 -Wl,--as-needed' \
      $EXTRA_ARGS; \
    make -j$(nproc); \
    strip objs/nginx; \
    make install; \
    # 安全地裁剪所有动态模块的符号表，减小体积（如果没有动态模块则跳过）
    if ls ${NGINX_DIR}/modules/*.so 1>/dev/null 2>&1; then \
      strip ${NGINX_DIR}/modules/*.so; \
    fi


# =======================================================
# Stage 2: 运行阶段 (Runtime Stage)
# CIS Docker Benchmark 合规 - 最小化镜像
# =======================================================
FROM debian:trixie-slim

# hadolint ignore=DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# OCI 镜像标签（用于 Docker Hub 展示）
LABEL org.opencontainers.image.title="Nginx" \
      org.opencontainers.image.description="Security-hardened Nginx with ModSecurity WAF, CIS Benchmark compliant" \
      org.opencontainers.image.source="https://github.com/ihccccom/Docker-Nginx-CIS" \
      org.opencontainers.image.licenses="BSD-3-Clause"

# 重新声明运行时需要的 ARGs
ARG USE_modsecurity
ARG USE_modsecurity_nginx
ARG USE_owasp
ARG USE_ngx_brotli
ARG OWASP_CRS_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    OPT_DIR=/opt \
    NGINX_DIR=/opt/nginx \
    NGINX_SRC_DIR=/opt/nginx/src \
    PATH="/opt/nginx/sbin:${PATH}"

# CIS Docker 4.1 - 创建非 root 运行用户
RUN groupadd -r www-data 2>/dev/null || true \
    && useradd -r -g www-data -s /sbin/nologin -d /nonexistent www-data 2>/dev/null || true

# CIS Docker 4.3 - 仅安装必要的运行时依赖（最小化）
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libjemalloc2 \
    libgd3 \
    libgeoip1 \
    libbrotli1 \
    libpcre2-8-0 \
    libfuzzy2 \
    libmaxminddb0 \
    liblmdb0 \
    libyajl2 \
    libxml2 \
    libcurl4 \
    liblua5.3-0 \
    zlib1g \
    openssl \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# CIS Docker 4.8 - 移除不必要的 setuid/setgid 权限
RUN find / -perm /6000 -type f -exec chmod a-s {} \; 2>/dev/null || true

# 从编译阶段复制 Nginx 二进制文件和默认页面
COPY --from=builder /opt/nginx/sbin ${NGINX_DIR}/sbin
COPY --from=builder /opt/nginx/html ${NGINX_DIR}/html
COPY --from=builder /opt/nginx/modules ${NGINX_DIR}/modules

# 从编译阶段复制 Nginx 自带配置文件（mime.types、fastcgi 相关等）
COPY --from=builder /opt/nginx/conf/mime.types ${NGINX_DIR}/conf/mime.types
COPY --from=builder /opt/nginx/conf/fastcgi.conf ${NGINX_DIR}/conf/fastcgi.conf
COPY --from=builder /opt/nginx/conf/fastcgi_params ${NGINX_DIR}/conf/fastcgi_params
COPY --from=builder /opt/nginx/conf/uwsgi_params ${NGINX_DIR}/conf/uwsgi_params
COPY --from=builder /opt/nginx/conf/scgi_params ${NGINX_DIR}/conf/scgi_params

# 从编译阶段复制 ModSecurity 库文件
COPY --from=builder /usr/local/modsecurity /usr/local/modsecurity

# 配置 ModSecurity 动态链接库路径
RUN echo "/usr/local/modsecurity/lib" > /etc/ld.so.conf.d/modsecurity.conf \
    && ldconfig

# 创建目录结构（CIS Nginx 合规）
RUN mkdir -p \
    ${NGINX_DIR}/conf \
    ${NGINX_DIR}/conf.d/sites-available \
    ${NGINX_DIR}/conf.d/sites-enabled \
    ${NGINX_DIR}/ssl/default \
    ${NGINX_DIR}/logs \
    /www/wwwroot/html \
    /var/cache/nginx/client_temp \
    /var/cache/nginx/proxy_temp \
    /var/cache/nginx/proxy_cache \
    /var/cache/nginx/fastcgi_temp \
    /var/cache/nginx/uwsgi_temp \
    /var/cache/nginx/scgi_temp

# 根据 CIS Nginx 2.4.2 - 创建默认自签名 SSL 证书
# PCI DSS 4.1 - 生成 DH 参数（>= 2048 位）用于 TLS 密钥交换
RUN openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout ${NGINX_DIR}/ssl/default/default.key \
      -out ${NGINX_DIR}/ssl/default/default.pem \
      -subj "/C=XX/ST=Default/L=Default/O=Default/CN=localhost" \
    && chmod 400 ${NGINX_DIR}/ssl/default/default.key \
    && chmod 600 ${NGINX_DIR}/ssl/default/default.pem \
    && openssl dhparam -out ${NGINX_DIR}/ssl/dhparam.pem 2048 \
    && chmod 600 ${NGINX_DIR}/ssl/dhparam.pem

# ============================================================
# 复制本地配置文件
# ============================================================

# 复制 Nginx 主配置文件并替换路径占位符
COPY conf/nginx.conf ${NGINX_DIR}/conf/nginx.conf
COPY conf/proxy.conf ${NGINX_DIR}/conf/proxy.conf
COPY conf/security-headers-common.conf ${NGINX_DIR}/conf/security-headers-common.conf
COPY conf/example.com.conf.template ${NGINX_DIR}/conf.d/sites-available/example.com.conf.template
COPY conf/php/ ${NGINX_DIR}/conf/php/
RUN sed -i "s|%NGINX_DIR%|${NGINX_DIR}|g" ${NGINX_DIR}/conf/nginx.conf \
    && sed -i "s|%NGINX_DIR%|${NGINX_DIR}|g" ${NGINX_DIR}/conf.d/sites-available/example.com.conf.template \
    && sed -i '/^\s*daemon\b/d' ${NGINX_DIR}/conf/nginx.conf

# 根据编译选项条件性禁用 nginx.conf 中的模块配置
# 如果 Brotli 未编译，注释掉 brotli 指令（避免 "unknown directive" 错误）
# 如果 ModSecurity 未编译，注释掉 modsecurity 指令
RUN if [ "${USE_ngx_brotli}" != "true" ]; then \
      sed -i '/\[BROTLI_START\]/,/\[BROTLI_END\]/{ /\[BROTLI_START\]/d; /\[BROTLI_END\]/d; s/^/# /; }' \
        ${NGINX_DIR}/conf/nginx.conf; \
    fi \
    && if [ "${USE_modsecurity_nginx}" != "true" ]; then \
      sed -i '/\[MODSECURITY_START\]/,/\[MODSECURITY_END\]/{ /\[MODSECURITY_START\]/d; /\[MODSECURITY_END\]/d; s/^/# /; }' \
        ${NGINX_DIR}/conf/nginx.conf; \
    fi

# 复制 ModSecurity 配置文件并替换路径占位符
COPY conf/modsecurity/ ${NGINX_DIR}/conf/modsecurity/
RUN sed -i "s|%NGINX_DIR%|${NGINX_DIR}|g" ${NGINX_DIR}/conf/modsecurity/modsecurity.conf \
    && sed -i "s|%NGINX_DIR%|${NGINX_DIR}|g" ${NGINX_DIR}/conf/modsecurity/main.conf \
    && chown -R root:root ${NGINX_DIR}/conf/modsecurity/ \
    && chmod 600 ${NGINX_DIR}/conf/modsecurity/*.conf

# 创建 ModSecurity 审计日志目录
RUN mkdir -p ${NGINX_DIR}/logs/modsec_audit \
    && chown -R www-data:www-data ${NGINX_DIR}/logs/modsec_audit

# 下载 OWASP 核心规则集（条件执行 - 需要从 GitHub 下载规则库）
RUN set -eux; \
    if [ "${USE_owasp}" = "true" ]; then \
      cd /opt; \
      if [ -n "${OWASP_CRS_VERSION}" ]; then \
        owasp_VERSION="${OWASP_CRS_VERSION}"; \
      else \
        owasp_VERSION=$(curl -s --retry 5 --retry-delay 2 --retry-connrefused \
          "https://api.github.com/repos/coreruleset/coreruleset/releases/latest" \
          | grep -Po '"tag_name": "\K.*?(?=")') || true; \
        if [ -z "$owasp_VERSION" ]; then owasp_VERSION="v4.8.0"; fi; \
      fi; \
      owasp_VERSION_NO_V=$(echo "$owasp_VERSION" | sed 's/^v//'); \
      owasp_DOWNLOAD_URL="https://github.com/coreruleset/coreruleset/archive/refs/tags/${owasp_VERSION}.tar.gz"; \
      curl -L --retry 5 --retry-delay 2 --retry-connrefused \
        -o "coreruleset-${owasp_VERSION}.tar.gz" "$owasp_DOWNLOAD_URL"; \
      tar -zxf "coreruleset-${owasp_VERSION}.tar.gz"; \
      # mv -f "coreruleset-${owasp_VERSION_NO_V}/docs" ${NGINX_DIR}/conf/modsecurity/docs; \
      mv -f "coreruleset-${owasp_VERSION_NO_V}/plugins" ${NGINX_DIR}/conf/modsecurity/plugins; \
      # mv -f "coreruleset-${owasp_VERSION_NO_V}/regex-assembly" ${NGINX_DIR}/conf/modsecurity/regex-assembly; \
      mv -f "coreruleset-${owasp_VERSION_NO_V}/rules" ${NGINX_DIR}/conf/modsecurity/rules; \
      rm -rf "coreruleset-${owasp_VERSION_NO_V}"; \
      rm -f "coreruleset-${owasp_VERSION}.tar.gz"; \
      # 使用内置的 crs-setup.conf 覆盖默认配置
      # cp ${NGINX_DIR}/conf/modsecurity/crs-setup.conf ${NGINX_DIR}/conf/modsecurity/crs-setup.conf; \
      # 下载 WordPress 规则排除插件（可选）
      curl -sSL --retry 5 --retry-delay 2 --retry-connrefused \
        -o ${NGINX_DIR}/conf/modsecurity/plugins/wordpress-rule-exclusions-before.conf \
        "https://raw.githubusercontent.com/coreruleset/wordpress-rule-exclusions-plugin/master/plugins/wordpress-rule-exclusions-before.conf" || true; \
      curl -sSL --retry 5 --retry-delay 2 --retry-connrefused \
        -o ${NGINX_DIR}/conf/modsecurity/plugins/wordpress-rule-exclusions-config.conf \
        "https://raw.githubusercontent.com/coreruleset/wordpress-rule-exclusions-plugin/master/plugins/wordpress-rule-exclusions-config.conf" || true; \
      # 重命名排除规则样例文件
      if [ -f ${NGINX_DIR}/conf/modsecurity/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example ]; then \
        mv ${NGINX_DIR}/conf/modsecurity/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example \
           ${NGINX_DIR}/conf/modsecurity/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf; \
      fi; \
      if [ -f ${NGINX_DIR}/conf/modsecurity/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example ]; then \
        mv ${NGINX_DIR}/conf/modsecurity/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example \
           ${NGINX_DIR}/conf/modsecurity/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf; \
      fi; \
    fi; \
    { find ${NGINX_DIR}/conf/modsecurity -type f -name "*.conf" -exec chmod 600 {} \; -exec chown root:root {} \; 2>/dev/null || true; }

# 复制默认首页
COPY conf/index.html /www/wwwroot/html/index.html

# ============================================================
# 文件权限设置（CIS Nginx Benchmark 合规）
# 合并为单个 RUN 层以减小镜像体积
# ============================================================
RUN touch ${NGINX_DIR}/logs/nginx.pid \
    # CIS Nginx - 配置文件权限
    && find ${NGINX_DIR}/conf -type d -exec chmod 700 {} \; \
    && find ${NGINX_DIR}/conf -type f -exec chmod 600 {} \; \
    && find ${NGINX_DIR}/conf.d -type d -exec chmod 700 {} \; \
    && find ${NGINX_DIR}/conf.d -type f -exec chmod 600 {} \; \
    # CIS Nginx - SSL 证书权限
    && chmod 700 ${NGINX_DIR}/ssl \
    && chmod 700 ${NGINX_DIR}/ssl/default \
    # CIS Nginx - 日志目录权限
    && chmod 750 ${NGINX_DIR}/logs \
    && chmod u-x,go-wx ${NGINX_DIR}/logs/nginx.pid \
    # CIS Nginx - 模块目录权限
    && { [ -d "${NGINX_DIR}/modules" ] && chmod 750 ${NGINX_DIR}/modules || true; } \
    # OWASP 规则文件权限
    && { find ${NGINX_DIR}/conf/modsecurity -type d -exec chmod 700 {} \; 2>/dev/null || true; } \
    && { find ${NGINX_DIR}/conf/modsecurity -type f -name "*.conf" -exec chmod 600 {} \; -exec chown root:root {} \; 2>/dev/null || true; } \
    && { chown -R root:root ${NGINX_DIR}/conf/modsecurity 2>/dev/null || true; } \
    # CIS Nginx 2.5.2 - 默认网站目录权限
    && chown -R www-data:www-data /www/wwwroot/html \
    && chmod 755 /www/wwwroot/html \
    && find /www/wwwroot/html -type f -exec chmod 444 {} \; \
    # Nginx 目录属主
    && chown root:root ${NGINX_DIR} \
    && chown -R root:www-data ${NGINX_DIR}/logs \
    && chown -R www-data:www-data ${NGINX_DIR}/logs/modsec_audit \
    # Nginx 缓存目录权限
    && chown -R www-data:www-data /var/cache/nginx

# CIS Docker 4.9 - 使用 COPY 而非 ADD
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 500 /docker-entrypoint.sh

# CIS Docker 4.6 - 健康检查
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
    CMD curl -sf http://127.0.0.1/nginx-health || exit 1

EXPOSE 80 443

# 优雅停止信号
STOPSIGNAL SIGQUIT

ENTRYPOINT ["/docker-entrypoint.sh"]

# 前台运行 Nginx（Docker 要求主进程在前台运行）
CMD ["/opt/nginx/sbin/nginx", "-g", "daemon off;"]
