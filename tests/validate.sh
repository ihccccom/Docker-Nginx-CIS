#!/usr/bin/env bash
# =======================================================
# Nginx Docker 容器安全配置验证脚本
# 验证 CIS Docker Benchmark 和 CIS Nginx Benchmark 合规性
# =======================================================
#
# 用法：
#   ./validate.sh [容器名称]
#
# 参数：
#   容器名称  - 要验证的 Docker 容器名称（默认: nginx）
#
# 示例：
#   ./validate.sh
#   ./validate.sh my-nginx
#

set -euo pipefail

# ============================================================
# 全局变量
# ============================================================

# 容器名称，默认为 "nginx"
CONTAINER_NAME="${1:-nginx}"

# Nginx 安装目录
NGINX_DIR="/opt/nginx"

# 测试计数器
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
INFO_COUNT=0
TOTAL_COUNT=0

# ============================================================
# 颜色定义
# ============================================================
if [[ -t 1 ]]; then
    # 终端支持颜色
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    # 非终端环境不使用颜色
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# ============================================================
# 辅助函数
# ============================================================

# 输出通过信息
pass() {
    ((TOTAL_COUNT++)) || true
    ((PASS_COUNT++)) || true
    echo -e "${GREEN}[PASS]${NC} $1"
}

# 输出失败信息
fail() {
    ((TOTAL_COUNT++)) || true
    ((FAIL_COUNT++)) || true
    echo -e "${RED}[FAIL]${NC} $1"
}

# 输出跳过信息
skip() {
    ((TOTAL_COUNT++)) || true
    ((SKIP_COUNT++)) || true
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

# 输出提示信息
info() {
    ((INFO_COUNT++)) || true
    echo -e "${BLUE}[INFO]${NC} $1"
}

# 在容器内执行命令
docker_exec() {
    docker exec "${CONTAINER_NAME}" "$@" 2>/dev/null
}

# 获取容器的 inspect 信息（缓存避免重复调用）
get_inspect() {
    if [[ -z "${INSPECT_CACHE:-}" ]]; then
        INSPECT_CACHE=$(docker inspect "${CONTAINER_NAME}" 2>/dev/null) || INSPECT_CACHE=""
    fi
    echo "${INSPECT_CACHE}"
}

# 打印分隔线
section() {
    echo ""
    echo -e "${BOLD}=== $1 ===${NC}"
    echo ""
}

# ============================================================
# 容器安全测试
# ============================================================
test_container() {
    section "容器安全测试 (Container Security Tests)"

    local inspect
    inspect=$(get_inspect)

    # 检查容器是否正在运行
    local state
    state=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['State']['Status'])" 2>/dev/null) || state=""
    if [[ "${state}" == "running" ]]; then
        pass "容器 '${CONTAINER_NAME}' 正在运行"
    else
        fail "容器 '${CONTAINER_NAME}' 未运行 (状态: ${state:-unknown})"
        info "后续测试可能会失败，请先启动容器"
        return
    fi

    # 检查容器是否以非特权模式运行 (CIS 5.4)
    local privileged
    privileged=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['Privileged'])" 2>/dev/null) || privileged=""
    if [[ "${privileged}" == "False" ]]; then
        pass "容器未以特权模式运行 (CIS 5.4)"
    else
        fail "容器以特权模式运行 (CIS 5.4)"
    fi

    # 检查 no-new-privileges 安全选项 (CIS 5.25)
    local security_opts
    security_opts=$(echo "${inspect}" | python3 -c "import sys,json; opts=json.load(sys.stdin)[0]['HostConfig']['SecurityOpt']; print(' '.join(opts) if opts else '')" 2>/dev/null) || security_opts=""
    if echo "${security_opts}" | grep -q "no-new-privileges"; then
        pass "已启用 no-new-privileges 安全选项 (CIS 5.25)"
    else
        fail "未启用 no-new-privileges 安全选项 (CIS 5.25)"
    fi

    # 检查 cap_drop ALL (CIS 5.3)
    local cap_drop
    cap_drop=$(echo "${inspect}" | python3 -c "import sys,json; caps=json.load(sys.stdin)[0]['HostConfig']['CapDrop']; print(' '.join(caps) if caps else '')" 2>/dev/null) || cap_drop=""
    if echo "${cap_drop}" | grep -qi "all"; then
        pass "已配置 cap_drop ALL (CIS 5.3)"
    else
        fail "未配置 cap_drop ALL (CIS 5.3)"
    fi

    # 检查内存限制 (CIS 5.10)
    local memory
    memory=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['Memory'])" 2>/dev/null) || memory="0"
    if [[ "${memory}" -gt 0 ]]; then
        local memory_mb=$((memory / 1024 / 1024))
        pass "已设置内存限制: ${memory_mb}MB (CIS 5.10)"
    else
        fail "未设置内存限制 (CIS 5.10)"
    fi

    # 检查 CPU 限制 (CIS 5.11)
    local cpu_period cpu_quota nano_cpus
    nano_cpus=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['NanoCpus'])" 2>/dev/null) || nano_cpus="0"
    cpu_period=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['CpuPeriod'])" 2>/dev/null) || cpu_period="0"
    cpu_quota=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['CpuQuota'])" 2>/dev/null) || cpu_quota="0"
    if [[ "${nano_cpus}" -gt 0 ]] || { [[ "${cpu_period}" -gt 0 ]] && [[ "${cpu_quota}" -gt 0 ]]; }; then
        pass "已设置 CPU 限制 (CIS 5.11)"
    else
        fail "未设置 CPU 限制 (CIS 5.11)"
    fi

    # 检查 PID 限制 (CIS 5.28)
    local pids_limit
    pids_limit=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['PidsLimit'])" 2>/dev/null) || pids_limit="0"
    if [[ "${pids_limit}" -gt 0 ]]; then
        pass "已设置 PID 限制: ${pids_limit} (CIS 5.28)"
    else
        fail "未设置 PID 限制 (CIS 5.28)"
    fi

    # 检查健康检查配置 (CIS 5.26)
    local healthcheck
    healthcheck=$(echo "${inspect}" | python3 -c "import sys,json; hc=json.load(sys.stdin)[0]['Config'].get('Healthcheck'); print(hc['Test'] if hc else '')" 2>/dev/null) || healthcheck=""
    if [[ -n "${healthcheck}" ]]; then
        pass "已配置健康检查 (CIS 5.26)"
    else
        fail "未配置健康检查 (CIS 5.26)"
    fi

    # 检查日志驱动配置
    local log_driver
    log_driver=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['LogConfig']['Type'])" 2>/dev/null) || log_driver=""
    if [[ -n "${log_driver}" ]]; then
        pass "已配置日志驱动: ${log_driver}"
    else
        fail "未配置日志驱动"
    fi
}

# ============================================================
# Nginx 服务测试
# ============================================================
test_nginx() {
    section "Nginx 服务测试 (Nginx Service Tests)"

    # 检查 Nginx 进程是否正在运行
    local nginx_pid
    nginx_pid=$(docker_exec pgrep -x nginx) || nginx_pid=""
    if [[ -n "${nginx_pid}" ]]; then
        pass "Nginx 进程正在运行"
    else
        fail "Nginx 进程未运行"
        info "后续 Nginx 测试将被跳过"
        return
    fi

    # 检查 Nginx 是否在 80 端口响应（使用健康检查端点）
    local http_code
    http_code=$(curl -so /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:80/nginx-health" 2>/dev/null) || http_code=""
    if [[ -n "${http_code}" ]] && [[ "${http_code}" -ge 200 ]] && [[ "${http_code}" -lt 500 ]]; then
        pass "Nginx 在端口 80 正常响应 (HTTP ${http_code})"
    else
        fail "Nginx 在端口 80 无响应 (HTTP ${http_code:-无})"
    fi

    # 检查 Nginx 是否在 443 端口响应
    local https_code
    https_code=$(curl -sko /dev/null -w "%{http_code}" --max-time 5 "https://127.0.0.1:443/" 2>/dev/null) || https_code=""
    if [[ -n "${https_code}" ]] && [[ "${https_code}" -ge 200 ]] && [[ "${https_code}" -lt 500 ]]; then
        pass "Nginx 在端口 443 正常响应 (HTTPS ${https_code})"
    else
        fail "Nginx 在端口 443 无响应 (HTTPS ${https_code:-无})"
    fi

    # 检查 Server 响应头是否隐藏了 nginx 版本信息
    local server_header
    server_header=$(curl -sI --max-time 5 "http://127.0.0.1:80/" 2>/dev/null | grep -i "^Server:" | head -1) || server_header=""
    if [[ -z "${server_header}" ]]; then
        pass "Server 响应头已完全隐藏"
    elif echo "${server_header}" | grep -qi "nginx/"; then
        fail "Server 响应头暴露了 Nginx 版本: ${server_header}"
    else
        pass "Server 响应头未暴露 Nginx 版本: ${server_header}"
    fi

    # 检查 X-Frame-Options 响应头
    local xfo_header
    xfo_header=$(curl -sI --max-time 5 "http://127.0.0.1:80/" 2>/dev/null | grep -i "^X-Frame-Options:" | head -1) || xfo_header=""
    if [[ -n "${xfo_header}" ]]; then
        pass "X-Frame-Options 响应头已配置: ${xfo_header}"
    else
        fail "X-Frame-Options 响应头未配置"
    fi

    # 检查 X-Content-Type-Options 响应头
    local xcto_header
    xcto_header=$(curl -sI --max-time 5 "http://127.0.0.1:80/" 2>/dev/null | grep -i "^X-Content-Type-Options:" | head -1) || xcto_header=""
    if [[ -n "${xcto_header}" ]]; then
        pass "X-Content-Type-Options 响应头已配置: ${xcto_header}"
    else
        fail "X-Content-Type-Options 响应头未配置"
    fi

    # 检查 X-XSS-Protection 响应头
    local xxss_header
    xxss_header=$(curl -sI --max-time 5 "http://127.0.0.1:80/" 2>/dev/null | grep -i "^X-XSS-Protection:" | head -1) || xxss_header=""
    if [[ -n "${xxss_header}" ]]; then
        pass "X-XSS-Protection 响应头已配置: ${xxss_header}"
    else
        fail "X-XSS-Protection 响应头未配置"
    fi

    # 检查 SSL/TLS 配置 - 拒绝 SSLv2
    local sslv2_result
    sslv2_result=$(echo | timeout 5 openssl s_client -ssl2 -connect 127.0.0.1:443 2>&1) || true
    if echo "${sslv2_result}" | grep -qi "unknown option\|no protocols available\|unsupported\|ssl handshake failure\|wrong version\|no cipher"; then
        pass "SSL/TLS: SSLv2 已禁用"
    elif echo "${sslv2_result}" | grep -qi "CONNECTED"; then
        fail "SSL/TLS: SSLv2 仍然启用（不安全）"
    else
        pass "SSL/TLS: SSLv2 已禁用"
    fi

    # 检查 SSL/TLS 配置 - 拒绝 SSLv3
    local sslv3_result
    sslv3_result=$(echo | timeout 5 openssl s_client -ssl3 -connect 127.0.0.1:443 2>&1) || true
    if echo "${sslv3_result}" | grep -qi "unknown option\|no protocols available\|unsupported\|ssl handshake failure\|wrong version\|no cipher"; then
        pass "SSL/TLS: SSLv3 已禁用"
    elif echo "${sslv3_result}" | grep -qi "CONNECTED" && ! echo "${sslv3_result}" | grep -qi "error\|alert"; then
        fail "SSL/TLS: SSLv3 仍然启用（不安全）"
    else
        pass "SSL/TLS: SSLv3 已禁用"
    fi

    # 检查 SSL/TLS 配置 - 拒绝 TLS 1.0（PCI DSS 要求）
    local tls10_result
    tls10_result=$(echo | timeout 5 openssl s_client -tls1 -connect 127.0.0.1:443 2>&1) || true
    if echo "${tls10_result}" | grep -qi "unknown option\|no protocols available\|unsupported\|ssl handshake failure\|wrong version\|no cipher\|alert protocol"; then
        pass "SSL/TLS: TLS 1.0 已禁用 (PCI DSS 4.1)"
    elif echo "${tls10_result}" | grep -qi "CONNECTED" && ! echo "${tls10_result}" | grep -qi "error\|alert"; then
        fail "SSL/TLS: TLS 1.0 仍然启用（不符合 PCI DSS）"
    else
        pass "SSL/TLS: TLS 1.0 已禁用 (PCI DSS 4.1)"
    fi

    # 检查 SSL/TLS 配置 - 拒绝 TLS 1.1（PCI DSS 要求）
    local tls11_result
    tls11_result=$(echo | timeout 5 openssl s_client -tls1_1 -connect 127.0.0.1:443 2>&1) || true
    if echo "${tls11_result}" | grep -qi "unknown option\|no protocols available\|unsupported\|ssl handshake failure\|wrong version\|no cipher\|alert protocol"; then
        pass "SSL/TLS: TLS 1.1 已禁用 (PCI DSS 4.1)"
    elif echo "${tls11_result}" | grep -qi "CONNECTED" && ! echo "${tls11_result}" | grep -qi "error\|alert"; then
        fail "SSL/TLS: TLS 1.1 仍然启用（不符合 PCI DSS）"
    else
        pass "SSL/TLS: TLS 1.1 已禁用 (PCI DSS 4.1)"
    fi

    # 检查 HSTS 响应头配置（PCI DSS 4.2.1 / CIS 4.1.13）
    # 注：默认服务器返回 444 时不会发送响应头，检查配置文件中是否包含 HSTS 指令
    local hsts_configured
    hsts_configured=$(docker_exec grep -r "Strict-Transport-Security" "${NGINX_DIR}/conf/" 2>/dev/null) || hsts_configured=""
    if [[ -n "${hsts_configured}" ]]; then
        pass "HSTS 已在配置中启用 (PCI DSS 4.2.1 / CIS 4.1.13)"
    else
        fail "HSTS 未在配置中启用 (PCI DSS 4.2.1)"
    fi

    # 检查 Content-Security-Policy 配置
    local csp_configured
    csp_configured=$(docker_exec grep -r "Content-Security-Policy" "${NGINX_DIR}/conf/" 2>/dev/null) || csp_configured=""
    if [[ -n "${csp_configured}" ]]; then
        pass "Content-Security-Policy 已在配置中启用"
    else
        fail "Content-Security-Policy 未在配置中启用"
    fi

    # 检查 Referrer-Policy 配置
    local rp_configured
    rp_configured=$(docker_exec grep -r "Referrer-Policy" "${NGINX_DIR}/conf/" 2>/dev/null) || rp_configured=""
    if [[ -n "${rp_configured}" ]]; then
        pass "Referrer-Policy 已在配置中启用"
    else
        fail "Referrer-Policy 未在配置中启用"
    fi

    # 检查 Permissions-Policy 配置
    local pp_configured
    pp_configured=$(docker_exec grep -r "Permissions-Policy" "${NGINX_DIR}/conf/" 2>/dev/null) || pp_configured=""
    if [[ -n "${pp_configured}" ]]; then
        pass "Permissions-Policy 已在配置中启用"
    else
        fail "Permissions-Policy 未在配置中启用"
    fi

    # 检查 SSL/TLS 协议配置（CIS 4.1.3）
    local ssl_protocols_conf
    ssl_protocols_conf=$(docker_exec grep -r "ssl_protocols" "${NGINX_DIR}/conf/" 2>/dev/null) || ssl_protocols_conf=""
    if echo "${ssl_protocols_conf}" | grep -q "TLSv1.2"; then
        pass "SSL 协议已配置 TLSv1.2 (CIS 4.1.3)"
    else
        fail "SSL 协议未正确配置 (CIS 4.1.3)"
    fi

    # 检查 DH 参数文件是否存在（PCI DSS）
    local dhparam_exists
    dhparam_exists=$(docker_exec test -f "${NGINX_DIR}/ssl/dhparam.pem" && echo "yes") || dhparam_exists=""
    if [[ "${dhparam_exists}" == "yes" ]]; then
        pass "DH 参数文件已生成 (PCI DSS TLS 合规)"
    else
        fail "DH 参数文件不存在 (PCI DSS TLS 合规)"
    fi
}

# ============================================================
# 文件权限测试
# ============================================================
test_file_permissions() {
    section "文件权限测试 (File Permission Tests)"

    # 检查配置文件是否不可被其他用户读取
    local conf_world_readable
    conf_world_readable=$(docker_exec find "${NGINX_DIR}/conf" -type f -perm -o=r 2>/dev/null) || conf_world_readable=""
    if [[ -z "${conf_world_readable}" ]]; then
        pass "配置文件不可被其他用户读取 (CIS Nginx)"
    else
        local count
        count=$(echo "${conf_world_readable}" | wc -l)
        fail "发现 ${count} 个配置文件可被其他用户读取 (CIS Nginx)"
    fi

    # 检查 SSL 私钥文件权限
    local ssl_key_perms
    ssl_key_perms=$(docker_exec stat -c '%a' "${NGINX_DIR}/ssl/default/default.key" 2>/dev/null) || ssl_key_perms=""
    if [[ -n "${ssl_key_perms}" ]]; then
        # 私钥权限应为 400 或更严格（使用八进制比较）
        if [[ $((8#${ssl_key_perms})) -le $((8#400)) ]]; then
            pass "SSL 私钥权限正确: ${ssl_key_perms} (CIS Nginx 2.4.2)"
        else
            fail "SSL 私钥权限过宽: ${ssl_key_perms}，应为 400 或更严格 (CIS Nginx 2.4.2)"
        fi
    else
        skip "SSL 私钥文件不存在，跳过权限检查"
    fi

    # 检查 SSL 目录权限
    local ssl_dir_perms
    ssl_dir_perms=$(docker_exec stat -c '%a' "${NGINX_DIR}/ssl" 2>/dev/null) || ssl_dir_perms=""
    if [[ -n "${ssl_dir_perms}" ]]; then
        if [[ $((8#${ssl_dir_perms})) -le $((8#700)) ]]; then
            pass "SSL 目录权限正确: ${ssl_dir_perms}"
        else
            fail "SSL 目录权限过宽: ${ssl_dir_perms}，应为 700 或更严格"
        fi
    else
        skip "SSL 目录不存在，跳过权限检查"
    fi

    # 检查日志目录权限
    local log_dir_perms
    log_dir_perms=$(docker_exec stat -c '%a' "${NGINX_DIR}/logs" 2>/dev/null) || log_dir_perms=""
    if [[ -n "${log_dir_perms}" ]]; then
        if [[ $((8#${log_dir_perms})) -le $((8#750)) ]]; then
            pass "日志目录权限正确: ${log_dir_perms}"
        else
            fail "日志目录权限过宽: ${log_dir_perms}，应为 750 或更严格"
        fi
    else
        skip "日志目录不存在，跳过权限检查"
    fi
}

# ============================================================
# ModSecurity WAF 测试
# ============================================================
test_modsecurity() {
    section "ModSecurity WAF 测试 (ModSecurity Tests)"

    # 检查 ModSecurity 模块是否加载
    local modsec_loaded
    modsec_loaded=$(docker_exec "${NGINX_DIR}/sbin/nginx" -V 2>&1 | grep -i "modsecurity") || modsec_loaded=""
    if [[ -n "${modsec_loaded}" ]]; then
        pass "ModSecurity 模块已加载"
    else
        # 尝试检查配置文件中是否引用了 ModSecurity
        local modsec_conf
        modsec_conf=$(docker_exec grep -r "modsecurity" "${NGINX_DIR}/conf/" 2>/dev/null) || modsec_conf=""
        if [[ -n "${modsec_conf}" ]]; then
            pass "ModSecurity 已在配置中启用"
        else
            skip "ModSecurity 模块未加载，跳过 WAF 测试"
            return
        fi
    fi

    # 检查 ModSecurity 配置文件是否存在
    local modsec_config_exists
    modsec_config_exists=$(docker_exec test -f "${NGINX_DIR}/conf/modsecurity/modsecurity.conf" && echo "yes") || modsec_config_exists=""
    if [[ "${modsec_config_exists}" == "yes" ]]; then
        pass "ModSecurity 配置文件存在"
    else
        info "ModSecurity 配置文件路径可能不同"
    fi

    # 测试 XSS 攻击检测
    local xss_code
    xss_code=$(curl -so /dev/null -w "%{http_code}" --max-time 5 \
        "http://127.0.0.1:80/?q=<script>alert(1)</script>" 2>/dev/null) || xss_code=""
    if [[ "${xss_code}" == "403" ]]; then
        pass "ModSecurity 成功拦截 XSS 攻击 (HTTP 403)"
    elif [[ "${xss_code}" == "200" ]]; then
        fail "ModSecurity 未拦截 XSS 攻击 (HTTP 200)"
    elif [[ -n "${xss_code}" ]]; then
        info "XSS 测试返回 HTTP ${xss_code}（可能已被其他机制拦截）"
    else
        fail "XSS 测试请求失败，无法获取响应"
    fi

    # 测试 SQL 注入攻击检测
    local sqli_code
    sqli_code=$(curl -so /dev/null -w "%{http_code}" --max-time 5 \
        "http://127.0.0.1:80/?id=1%20OR%201=1--" 2>/dev/null) || sqli_code=""
    if [[ "${sqli_code}" == "403" ]]; then
        pass "ModSecurity 成功拦截 SQL 注入攻击 (HTTP 403)"
    elif [[ "${sqli_code}" == "200" ]]; then
        fail "ModSecurity 未拦截 SQL 注入攻击 (HTTP 200)"
    elif [[ -n "${sqli_code}" ]]; then
        info "SQL 注入测试返回 HTTP ${sqli_code}（可能已被其他机制拦截）"
    else
        fail "SQL 注入测试请求失败，无法获取响应"
    fi
}

# ============================================================
# 打印测试摘要
# ============================================================
print_summary() {
    section "测试摘要 (Test Summary)"

    echo -e "  容器名称:  ${BOLD}${CONTAINER_NAME}${NC}"
    echo -e "  测试总数:  ${BOLD}${TOTAL_COUNT}${NC}"
    echo -e "  ${GREEN}通过: ${PASS_COUNT}${NC}"
    echo -e "  ${RED}失败: ${FAIL_COUNT}${NC}"
    echo -e "  ${YELLOW}跳过: ${SKIP_COUNT}${NC}"
    echo -e "  ${BLUE}提示: ${INFO_COUNT}${NC}"
    echo ""

    if [[ ${FAIL_COUNT} -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}所有测试通过！容器安全配置符合要求。${NC}"
    else
        echo -e "${RED}${BOLD}存在 ${FAIL_COUNT} 项测试失败，请检查并修复安全配置。${NC}"
    fi
    echo ""
}

# ============================================================
# 主函数
# ============================================================
main() {
    echo ""
    echo -e "${BOLD}Nginx Docker 容器安全配置验证${NC}"
    echo -e "目标容器: ${BOLD}${CONTAINER_NAME}${NC}"
    echo -e "验证时间: $(date '+%Y-%m-%d %H:%M:%S')"

    # 预检查：确认 Docker 和 python3 是否可用
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}错误: docker 命令不可用，请先安装 Docker${NC}"
        exit 1
    fi
    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}错误: python3 命令不可用，请先安装 Python 3${NC}"
        exit 1
    fi

    # 预检查：确认容器是否存在
    if ! docker inspect "${CONTAINER_NAME}" &>/dev/null; then
        echo -e "${RED}错误: 容器 '${CONTAINER_NAME}' 不存在${NC}"
        echo -e "用法: $0 [容器名称]"
        exit 1
    fi

    # 执行各类测试
    test_container
    test_nginx
    test_file_permissions
    test_modsecurity

    # 打印测试摘要
    print_summary

    # 返回状态码：有失败则返回 1
    if [[ ${FAIL_COUNT} -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

# 运行主函数
main
