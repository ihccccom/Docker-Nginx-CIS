#!/usr/bin/env bash
# =============================================================================
# CIS Docker Benchmark v1.6.0 安全检查脚本
# 针对运行中的 Docker/Nginx 容器进行合规性检查
# =============================================================================

set -euo pipefail

# 默认容器名称
CONTAINER_NAME="${1:-nginx}"

# ----------------------------- 颜色定义 --------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# ----------------------------- 计数器 ----------------------------------------
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
INFO_COUNT=0

# ----------------------------- 辅助函数 --------------------------------------

# 输出通过信息
pass_check() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "${GREEN}[PASS]${NC} $1"
}

# 输出警告信息
warn_check() {
  WARN_COUNT=$((WARN_COUNT + 1))
  echo -e "${YELLOW}[WARN]${NC} $1"
}

# 输出失败信息
fail_check() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  echo -e "${RED}[FAIL]${NC} $1"
}

# 输出提示信息
info_check() {
  INFO_COUNT=$((INFO_COUNT + 1))
  echo -e "${BLUE}[INFO]${NC} $1"
}

# 检查命令是否存在
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

# ----------------------------- 前置检查 --------------------------------------

# 确认 docker 命令可用
if ! command_exists docker; then
  echo -e "${RED}错误: 未找到 docker 命令，请先安装 Docker${NC}"
  exit 1
fi

# 确认目标容器正在运行
if ! docker ps --format '{{.Names}}' | grep -qw "${CONTAINER_NAME}"; then
  echo -e "${RED}错误: 容器 '${CONTAINER_NAME}' 未在运行中${NC}"
  exit 1
fi

# 获取容器 ID
CONTAINER_ID=$(docker inspect --format '{{.Id}}' "${CONTAINER_NAME}" 2>/dev/null)

echo "============================================================================="
echo " CIS Docker Benchmark v1.6.0 安全检查"
echo " 目标容器: ${CONTAINER_NAME} (${CONTAINER_ID:0:12})"
echo " 检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================================="
echo ""

# =============================================================================
# 第一部分: 主机配置 (Host Configuration)
# =============================================================================
echo "---------------------------------------------------------------------"
echo " 1 - 主机配置 (Host Configuration)"
echo "---------------------------------------------------------------------"

# 1.1.1 - 确保容器使用独立的存储分区
check_1_1_1() {
  local id="1.1.1"
  local desc="确保容器使用独立的存储分区 (Ensure a separate partition for containers exists)"
  local docker_root
  docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)

  if mountpoint -q "${docker_root}" 2>/dev/null; then
    pass_check "${id} - ${desc}"
  else
    warn_check "${id} - ${desc} - Docker 根目录 '${docker_root}' 未挂载在独立分区上"
  fi
}

# 1.1.2 - 确保只有受信任的用户在 docker 组中
check_1_1_2() {
  local id="1.1.2"
  local desc="确保只有受信任的用户在 docker 组中 (Ensure only trusted users are in docker group)"

  if getent group docker > /dev/null 2>&1; then
    local docker_users
    docker_users=$(getent group docker | cut -d: -f4)
    if [ -z "${docker_users}" ]; then
      pass_check "${id} - ${desc} - docker 组中无额外用户"
    else
      info_check "${id} - ${desc} - docker 组中的用户: ${docker_users}，请确认均为受信任用户"
    fi
  else
    info_check "${id} - ${desc} - docker 组不存在"
  fi
}

# 1.2.1 - 确保容器宿主机已进行安全加固
check_1_2_1() {
  local id="1.2.1"
  local desc="确保容器宿主机已进行安全加固 (Ensure the container host has been hardened)"
  local hardened=0

  # 检查是否存在常见的安全加固工具
  if command_exists aide || command_exists tripwire; then
    hardened=$((hardened + 1))
  fi
  if command_exists aa-status || command_exists getenforce; then
    hardened=$((hardened + 1))
  fi

  if [ "${hardened}" -ge 1 ]; then
    pass_check "${id} - ${desc} - 检测到安全加固工具"
  else
    warn_check "${id} - ${desc} - 未检测到常见的安全加固工具 (aide/tripwire/apparmor/selinux)"
  fi
}

check_1_1_1
check_1_1_2
check_1_2_1
echo ""

# =============================================================================
# 第二部分: Docker 守护进程配置 (Docker Daemon Configuration)
# =============================================================================
echo "---------------------------------------------------------------------"
echo " 2 - Docker 守护进程配置 (Docker Daemon Configuration)"
echo "---------------------------------------------------------------------"

# 获取 Docker 守护进程配置（缓存以减少重复调用）
DOCKER_INFO=$(docker info --format '{{json .}}' 2>/dev/null || echo "{}")
DAEMON_JSON=""
if [ -f /etc/docker/daemon.json ]; then
  DAEMON_JSON=$(cat /etc/docker/daemon.json 2>/dev/null || echo "{}")
fi

# 2.1 - 确保以非 root 用户运行 Docker 守护进程（无根模式检查）
check_2_1() {
  local id="2.1"
  local desc="确保以非 root 用户运行 Docker 守护进程 (Run the Docker daemon as a non-root user)"

  # 检查 rootless 模式
  if echo "${DOCKER_INFO}" | grep -qi '"rootless"' 2>/dev/null || \
     docker info 2>/dev/null | grep -qi "rootless"; then
    pass_check "${id} - ${desc} - 已启用 rootless 模式"
  else
    # 检查 dockerd 进程是否以 root 运行
    local dockerd_user
    dockerd_user=$(ps -eo user,comm 2>/dev/null | grep dockerd | awk '{print $1}' | head -1)
    if [ "${dockerd_user}" = "root" ]; then
      warn_check "${id} - ${desc} - Docker 守护进程以 root 用户运行，建议启用 rootless 模式"
    else
      info_check "${id} - ${desc} - Docker 守护进程运行用户: ${dockerd_user:-未知}"
    fi
  fi
}

# 2.2 - 确保限制容器之间的网络流量 (icc)
check_2_2() {
  local id="2.2"
  local desc="确保限制容器之间的网络流量 (Ensure network traffic is restricted between containers)"

  # 检查默认桥接网络的 ICC 设置
  local icc_setting
  icc_setting=$(docker network inspect bridge --format '{{index .Options "com.docker.network.bridge.enable_icc"}}' 2>/dev/null || echo "")

  if [ "${icc_setting}" = "false" ]; then
    pass_check "${id} - ${desc} - 容器间通信 (ICC) 已禁用"
  else
    warn_check "${id} - ${desc} - 默认桥接网络的容器间通信 (ICC) 未禁用"
  fi
}

# 2.3 - 确保日志级别设置为 info
check_2_3() {
  local id="2.3"
  local desc="确保日志级别设置为 info (Ensure logging level is set to info)"
  local log_level
  log_level=$(docker info --format '{{.LoggingDriver}}' 2>/dev/null || echo "")

  # 检查 daemon.json 中的日志级别
  local daemon_log_level=""
  if [ -n "${DAEMON_JSON}" ]; then
    daemon_log_level=$(echo "${DAEMON_JSON}" | grep -oP '"log-level"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
  fi

  # 检查 dockerd 进程参数
  local process_log_level=""
  process_log_level=$(ps -ef 2>/dev/null | grep '[d]ockerd' | grep -oP '(?<=--log-level[= ])\w+' || echo "")

  if [ "${daemon_log_level}" = "info" ] || [ "${process_log_level}" = "info" ]; then
    pass_check "${id} - ${desc} - 日志级别已设置为 info"
  elif [ -z "${daemon_log_level}" ] && [ -z "${process_log_level}" ]; then
    pass_check "${id} - ${desc} - 使用默认日志级别 (info)"
  else
    warn_check "${id} - ${desc} - 日志级别: ${daemon_log_level}${process_log_level}"
  fi
}

# 2.4 - 确保允许 Docker 修改 iptables 规则
check_2_4() {
  local id="2.4"
  local desc="确保允许 Docker 修改 iptables 规则 (Ensure Docker is allowed to make changes to iptables)"

  local iptables_disabled=""
  if [ -n "${DAEMON_JSON}" ]; then
    iptables_disabled=$(echo "${DAEMON_JSON}" | grep -oP '"iptables"\s*:\s*\K(true|false)' 2>/dev/null || echo "")
  fi

  if [ "${iptables_disabled}" = "false" ]; then
    fail_check "${id} - ${desc} - Docker 被禁止修改 iptables"
  else
    pass_check "${id} - ${desc} - Docker 可以管理 iptables 规则"
  fi
}

# 2.5 - 确保未使用不安全的镜像仓库
check_2_5() {
  local id="2.5"
  local desc="确保未使用不安全的镜像仓库 (Ensure insecure registries are not used)"
  local insecure_registries
  insecure_registries=$(docker info --format '{{.RegistryConfig.InsecureRegistryCIDRs}}' 2>/dev/null || echo "")

  # 默认值 127.0.0.0/8 是可以接受的
  if [ -z "${insecure_registries}" ] || [ "${insecure_registries}" = "[127.0.0.0/8]" ]; then
    pass_check "${id} - ${desc} - 未配置不安全的镜像仓库"
  else
    fail_check "${id} - ${desc} - 发现不安全的镜像仓库: ${insecure_registries}"
  fi
}

# 2.6 - 确保 auditd 已配置审计 Docker 相关文件
check_2_6() {
  local id="2.6"
  local desc="确保 auditd 已配置审计 Docker 相关文件 (Ensure auditd is configured for Docker files)"
  local audit_ok=true

  # 需要审计的文件和目录列表
  local audit_targets=(
    "/usr/bin/dockerd"
    "/etc/docker"
    "/var/lib/docker"
    "/etc/default/docker"
    "/usr/bin/containerd"
  )

  if ! command_exists auditctl; then
    warn_check "${id} - ${desc} - auditctl 未安装，无法验证审计配置"
    return
  fi

  local missing_audits=()
  for target in "${audit_targets[@]}"; do
    if [ -e "${target}" ]; then
      if ! auditctl -l 2>/dev/null | grep -q "${target}"; then
        missing_audits+=("${target}")
        audit_ok=false
      fi
    fi
  done

  if [ "${audit_ok}" = true ]; then
    pass_check "${id} - ${desc} - 所有 Docker 相关文件已配置审计规则"
  else
    warn_check "${id} - ${desc} - 以下文件缺少审计规则: ${missing_audits[*]}"
  fi
}

# 2.8 - 确保启用用户命名空间支持
check_2_8() {
  local id="2.8"
  local desc="确保启用用户命名空间支持 (Enable user namespace support)"
  local userns
  userns=$(docker info --format '{{.SecurityOptions}}' 2>/dev/null || echo "")

  if echo "${userns}" | grep -q "userns"; then
    pass_check "${id} - ${desc} - 用户命名空间已启用"
  else
    warn_check "${id} - ${desc} - 用户命名空间未启用"
  fi
}

# 2.11 - 确保启用了 Docker 客户端命令的授权
check_2_11() {
  local id="2.11"
  local desc="确保启用了 Docker 客户端命令的授权 (Ensure authorization for Docker client commands is enabled)"
  local auth_plugin=""

  if [ -n "${DAEMON_JSON}" ]; then
    auth_plugin=$(echo "${DAEMON_JSON}" | grep -oP '"authorization-plugins"\s*:\s*\[\K[^\]]+' 2>/dev/null || echo "")
  fi

  if [ -n "${auth_plugin}" ]; then
    pass_check "${id} - ${desc} - 授权插件已配置: ${auth_plugin}"
  else
    warn_check "${id} - ${desc} - 未配置 Docker 授权插件"
  fi
}

# 2.14 - 确保限制容器获取新权限
check_2_14() {
  local id="2.14"
  local desc="确保限制容器获取新权限 (Ensure containers are restricted from acquiring new privileges)"
  local no_new_privs=""

  if [ -n "${DAEMON_JSON}" ]; then
    no_new_privs=$(echo "${DAEMON_JSON}" | grep -oP '"no-new-privileges"\s*:\s*\K(true|false)' 2>/dev/null || echo "")
  fi

  if [ "${no_new_privs}" = "true" ]; then
    pass_check "${id} - ${desc} - 守护进程级别已启用 no-new-privileges"
  else
    warn_check "${id} - ${desc} - 守护进程级别未启用 no-new-privileges 默认设置"
  fi
}

# 2.15 - 确保启用实时恢复功能
check_2_15() {
  local id="2.15"
  local desc="确保启用实时恢复功能 (Ensure live restore is enabled)"
  local live_restore
  live_restore=$(docker info --format '{{.LiveRestoreEnabled}}' 2>/dev/null || echo "false")

  if [ "${live_restore}" = "true" ]; then
    pass_check "${id} - ${desc} - Live Restore 已启用"
  else
    warn_check "${id} - ${desc} - Live Restore 未启用"
  fi
}

# 2.17 - 确保应用守护进程级别的自定义 seccomp 配置
check_2_17() {
  local id="2.17"
  local desc="确保应用守护进程级别的自定义 seccomp 配置 (Ensure daemon-wide custom seccomp profile is applied)"
  local seccomp_profile=""

  if [ -n "${DAEMON_JSON}" ]; then
    seccomp_profile=$(echo "${DAEMON_JSON}" | grep -oP '"seccomp-profile"\s*:\s*"\K[^"]+' 2>/dev/null || echo "")
  fi

  if [ -n "${seccomp_profile}" ]; then
    if [ -f "${seccomp_profile}" ]; then
      pass_check "${id} - ${desc} - 自定义 seccomp 配置: ${seccomp_profile}"
    else
      fail_check "${id} - ${desc} - seccomp 配置文件不存在: ${seccomp_profile}"
    fi
  else
    info_check "${id} - ${desc} - 使用默认 seccomp 配置（建议使用自定义配置）"
  fi
}

check_2_1
check_2_2
check_2_3
check_2_4
check_2_5
check_2_6
check_2_8
check_2_11
check_2_14
check_2_15
check_2_17
echo ""

# =============================================================================
# 第五部分: 容器运行时 (Container Runtime)
# =============================================================================
echo "---------------------------------------------------------------------"
echo " 5 - 容器运行时 (Container Runtime)"
echo "---------------------------------------------------------------------"

# 获取容器详细信息（缓存）
CONTAINER_INSPECT=$(docker inspect "${CONTAINER_NAME}" 2>/dev/null || echo "{}")

# 5.1 - 确保启用了 AppArmor 配置
check_5_1() {
  local id="5.1"
  local desc="确保启用了 AppArmor 配置 (Ensure an AppArmor Profile is enabled)"
  local apparmor
  apparmor=$(echo "${CONTAINER_INSPECT}" | grep -oP '"AppArmorProfile"\s*:\s*"\K[^"]*' 2>/dev/null | head -1)

  if [ -n "${apparmor}" ]; then
    pass_check "${id} - ${desc} - AppArmor 配置: ${apparmor}"
  else
    warn_check "${id} - ${desc} - 容器未启用 AppArmor 配置"
  fi
}

# 5.2 - 确保设置了 SELinux 安全选项
check_5_2() {
  local id="5.2"
  local desc="确保设置了 SELinux 安全选项 (Ensure SELinux security options are set)"
  local selinux_opts
  selinux_opts=$(docker inspect --format '{{.HostConfig.SecurityOpt}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

  if echo "${selinux_opts}" | grep -qi "label"; then
    pass_check "${id} - ${desc} - SELinux 标签已设置"
  else
    # 如果系统运行 AppArmor 而非 SELinux，这不算失败
    if command_exists getenforce && [ "$(getenforce 2>/dev/null)" != "Disabled" ]; then
      warn_check "${id} - ${desc} - SELinux 已启用但容器未设置 SELinux 标签"
    else
      info_check "${id} - ${desc} - 系统未使用 SELinux（可能使用 AppArmor）"
    fi
  fi
}

# 5.3 - 确保限制了 Linux 内核能力
check_5_3() {
  local id="5.3"
  local desc="确保限制了 Linux 内核能力 (Ensure Linux kernel capabilities are restricted)"
  local cap_add
  local cap_drop
  cap_add=$(docker inspect --format '{{.HostConfig.CapAdd}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")
  cap_drop=$(docker inspect --format '{{.HostConfig.CapDrop}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

  if echo "${cap_drop}" | grep -qi "all"; then
    pass_check "${id} - ${desc} - 已丢弃所有能力 (CapDrop=ALL)"
  elif [ "${cap_add}" = "[]" ] || [ "${cap_add}" = "<no value>" ] || [ -z "${cap_add}" ]; then
    warn_check "${id} - ${desc} - 未显式丢弃能力，建议使用 --cap-drop=ALL 并只添加所需能力"
  else
    warn_check "${id} - ${desc} - 已添加额外能力: ${cap_add}，请确认是否必要"
  fi
}

# 5.4 - 确保未使用特权容器
check_5_4() {
  local id="5.4"
  local desc="确保未使用特权容器 (Ensure privileged containers are not used)"
  local privileged
  privileged=$(docker inspect --format '{{.HostConfig.Privileged}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

  if [ "${privileged}" = "true" ]; then
    fail_check "${id} - ${desc} - 容器以特权模式运行！"
  else
    pass_check "${id} - ${desc} - 容器未以特权模式运行"
  fi
}

# 5.5 - 确保未挂载敏感的宿主机系统目录
check_5_5() {
  local id="5.5"
  local desc="确保未挂载敏感的宿主机系统目录 (Ensure sensitive host system directories are not mounted)"
  local mounts
  mounts=$(docker inspect --format '{{range .Mounts}}{{.Source}} {{end}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

  # 敏感目录列表
  local sensitive_dirs=("/" "/boot" "/dev" "/etc" "/lib" "/proc" "/sys" "/usr")
  local found_sensitive=()

  for dir in "${sensitive_dirs[@]}"; do
    for mount in ${mounts}; do
      if [ "${mount}" = "${dir}" ]; then
        found_sensitive+=("${dir}")
      fi
    done
  done

  if [ ${#found_sensitive[@]} -eq 0 ]; then
    pass_check "${id} - ${desc} - 未挂载敏感系统目录"
  else
    fail_check "${id} - ${desc} - 挂载了敏感系统目录: ${found_sensitive[*]}"
  fi
}

# 5.7 - 确保未映射特权端口
check_5_7() {
  local id="5.7"
  local desc="确保未映射特权端口 (Ensure privileged ports are not mapped)"
  local ports
  ports=$(docker inspect --format '{{range $p, $conf := .NetworkSettings.Ports}}{{range $conf}}{{.HostPort}} {{end}}{{end}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

  local priv_ports=()
  for port in ${ports}; do
    if [ -n "${port}" ] && [ "${port}" -lt 1024 ] 2>/dev/null; then
      priv_ports+=("${port}")
    fi
  done

  if [ ${#priv_ports[@]} -eq 0 ]; then
    pass_check "${id} - ${desc} - 未映射特权端口 (<1024)"
  else
    warn_check "${id} - ${desc} - 映射了特权端口: ${priv_ports[*]}"
  fi
}

# 5.9 - 确保未共享宿主机的网络命名空间
check_5_9() {
  local id="5.9"
  local desc="确保未共享宿主机的网络命名空间 (Ensure host's network namespace is not shared)"
  local net_mode
  net_mode=$(docker inspect --format '{{.HostConfig.NetworkMode}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

  if [ "${net_mode}" = "host" ]; then
    fail_check "${id} - ${desc} - 容器使用了宿主机网络命名空间"
  else
    pass_check "${id} - ${desc} - 容器使用独立网络命名空间 (${net_mode})"
  fi
}

# 5.10 - 确保限制了容器的内存使用量
check_5_10() {
  local id="5.10"
  local desc="确保限制了容器的内存使用量 (Ensure memory usage for containers is limited)"
  local memory
  memory=$(docker inspect --format '{{.HostConfig.Memory}}' "${CONTAINER_NAME}" 2>/dev/null || echo "0")

  if [ "${memory}" != "0" ] && [ -n "${memory}" ]; then
    local memory_mb=$((memory / 1024 / 1024))
    pass_check "${id} - ${desc} - 内存限制: ${memory_mb}MB"
  else
    warn_check "${id} - ${desc} - 未设置内存限制"
  fi
}

# 5.11 - 确保适当设置了 CPU 优先级
check_5_11() {
  local id="5.11"
  local desc="确保适当设置了 CPU 优先级 (Ensure CPU priority is set appropriately)"
  local cpu_shares
  cpu_shares=$(docker inspect --format '{{.HostConfig.CpuShares}}' "${CONTAINER_NAME}" 2>/dev/null || echo "0")

  if [ "${cpu_shares}" != "0" ] && [ -n "${cpu_shares}" ]; then
    pass_check "${id} - ${desc} - CPU 份额: ${cpu_shares}"
  else
    warn_check "${id} - ${desc} - 未设置 CPU 优先级（使用默认值）"
  fi
}

# 5.12 - 确保容器根文件系统以只读方式挂载
check_5_12() {
  local id="5.12"
  local desc="确保容器根文件系统以只读方式挂载 (Ensure root filesystem is mounted as read only)"
  local read_only
  read_only=$(docker inspect --format '{{.HostConfig.ReadonlyRootfs}}' "${CONTAINER_NAME}" 2>/dev/null || echo "false")

  if [ "${read_only}" = "true" ]; then
    pass_check "${id} - ${desc} - 根文件系统为只读"
  else
    warn_check "${id} - ${desc} - 根文件系统可写，建议设置为只读"
  fi
}

# 5.13 - 确保入站容器流量绑定到特定的宿主机接口
check_5_13() {
  local id="5.13"
  local desc="确保入站流量绑定到特定的宿主机接口 (Ensure incoming traffic is bound to a specific host interface)"
  local ports
  ports=$(docker inspect --format '{{range $p, $conf := .NetworkSettings.Ports}}{{range $conf}}{{.HostIp}}:{{.HostPort}} {{end}}{{end}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

  local bind_all=false
  for binding in ${ports}; do
    local ip="${binding%%:*}"
    if [ -z "${ip}" ] || [ "${ip}" = "0.0.0.0" ] || [ "${ip}" = "::" ]; then
      bind_all=true
      break
    fi
  done

  if [ -z "${ports}" ]; then
    info_check "${id} - ${desc} - 容器未暴露端口"
  elif [ "${bind_all}" = true ]; then
    warn_check "${id} - ${desc} - 端口绑定到所有接口 (0.0.0.0)，建议绑定到特定接口"
  else
    pass_check "${id} - ${desc} - 端口已绑定到特定接口"
  fi
}

# 5.14 - 确保容器重启策略设置为 on-failure 且最大重试次数为 5
check_5_14() {
  local id="5.14"
  local desc="确保重启策略设置为 on-failure:5 (Ensure on-failure restart policy is set to 5)"
  local restart_policy
  local max_retry
  restart_policy=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")
  max_retry=$(docker inspect --format '{{.HostConfig.RestartPolicy.MaximumRetryCount}}' "${CONTAINER_NAME}" 2>/dev/null || echo "0")

  if [ "${restart_policy}" = "on-failure" ]; then
    if [ "${max_retry}" -le 5 ] 2>/dev/null; then
      pass_check "${id} - ${desc} - 重启策略: on-failure, 最大重试: ${max_retry}"
    else
      warn_check "${id} - ${desc} - 最大重试次数过高: ${max_retry}（建议不超过 5）"
    fi
  elif [ "${restart_policy}" = "always" ] || [ "${restart_policy}" = "unless-stopped" ]; then
    warn_check "${id} - ${desc} - 重启策略为 '${restart_policy}'，建议使用 on-failure:5"
  elif [ "${restart_policy}" = "no" ] || [ -z "${restart_policy}" ]; then
    info_check "${id} - ${desc} - 未设置重启策略"
  else
    info_check "${id} - ${desc} - 重启策略: ${restart_policy}"
  fi
}

# 5.15 - 确保未共享宿主机的进程命名空间
check_5_15() {
  local id="5.15"
  local desc="确保未共享宿主机的进程命名空间 (Ensure host's process namespace is not shared)"
  local pid_mode
  pid_mode=$(docker inspect --format '{{.HostConfig.PidMode}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

  if [ "${pid_mode}" = "host" ]; then
    fail_check "${id} - ${desc} - 容器共享了宿主机的 PID 命名空间"
  else
    pass_check "${id} - ${desc} - 容器使用独立 PID 命名空间"
  fi
}

# 5.16 - 确保未共享宿主机的 IPC 命名空间
check_5_16() {
  local id="5.16"
  local desc="确保未共享宿主机的 IPC 命名空间 (Ensure host's IPC namespace is not shared)"
  local ipc_mode
  ipc_mode=$(docker inspect --format '{{.HostConfig.IpcMode}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

  if [ "${ipc_mode}" = "host" ]; then
    fail_check "${id} - ${desc} - 容器共享了宿主机的 IPC 命名空间"
  else
    pass_check "${id} - ${desc} - 容器使用独立 IPC 命名空间"
  fi
}

# 5.25 - 确保限制容器获取额外权限
check_5_25() {
  local id="5.25"
  local desc="确保限制容器获取额外权限 (Ensure container is restricted from acquiring additional privileges)"
  local security_opts
  security_opts=$(docker inspect --format '{{.HostConfig.SecurityOpt}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

  if echo "${security_opts}" | grep -q "no-new-privileges"; then
    pass_check "${id} - ${desc} - 已设置 no-new-privileges"
  else
    warn_check "${id} - ${desc} - 未设置 no-new-privileges 安全选项"
  fi
}

# 5.26 - 确保在运行时检查容器健康状态
check_5_26() {
  local id="5.26"
  local desc="确保在运行时检查容器健康状态 (Ensure container health is checked at runtime)"
  local healthcheck
  healthcheck=$(docker inspect --format '{{.Config.Healthcheck}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

  if [ -n "${healthcheck}" ] && [ "${healthcheck}" != "<nil>" ] && [ "${healthcheck}" != "{[]  0 0 0 0}" ]; then
    pass_check "${id} - ${desc} - 已配置健康检查"
  else
    warn_check "${id} - ${desc} - 未配置健康检查"
  fi
}

# 5.28 - 确保使用了 PIDs cgroup 限制
check_5_28() {
  local id="5.28"
  local desc="确保使用了 PIDs cgroup 限制 (Ensure PIDs cgroup limit is used)"
  local pids_limit
  pids_limit=$(docker inspect --format '{{.HostConfig.PidsLimit}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

  if [ -n "${pids_limit}" ] && [ "${pids_limit}" != "0" ] && [ "${pids_limit}" != "-1" ] && [ "${pids_limit}" != "<nil>" ]; then
    pass_check "${id} - ${desc} - PID 限制: ${pids_limit}"
  else
    warn_check "${id} - ${desc} - 未设置 PID 限制"
  fi
}

# 5.30 - 确保未共享宿主机的用户命名空间
check_5_30() {
  local id="5.30"
  local desc="确保未共享宿主机的用户命名空间 (Ensure host's user namespaces are not shared)"
  local userns_mode
  userns_mode=$(docker inspect --format '{{.HostConfig.UsernsMode}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

  if [ "${userns_mode}" = "host" ]; then
    fail_check "${id} - ${desc} - 容器共享了宿主机的用户命名空间"
  else
    pass_check "${id} - ${desc} - 容器未共享宿主机的用户命名空间"
  fi
}

# 5.31 - 确保 Docker socket 未挂载到容器内部
check_5_31() {
  local id="5.31"
  local desc="确保 Docker socket 未挂载到容器内部 (Ensure Docker socket is not mounted inside any containers)"
  local mounts
  mounts=$(docker inspect --format '{{range .Mounts}}{{.Source}} {{end}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

  if echo "${mounts}" | grep -q "/var/run/docker.sock"; then
    fail_check "${id} - ${desc} - Docker socket 已挂载到容器中！"
  else
    pass_check "${id} - ${desc} - Docker socket 未挂载到容器中"
  fi
}

check_5_1
check_5_2
check_5_3
check_5_4
check_5_5
check_5_7
check_5_9
check_5_10
check_5_11
check_5_12
check_5_13
check_5_14
check_5_15
check_5_16
check_5_25
check_5_26
check_5_28
check_5_30
check_5_31
echo ""

# =============================================================================
# 检查结果汇总
# =============================================================================
TOTAL=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT + INFO_COUNT))
echo "============================================================================="
echo " 检查结果汇总 (Summary)"
echo "============================================================================="
echo -e " ${GREEN}[PASS]${NC} 通过: ${PASS_COUNT}"
echo -e " ${YELLOW}[WARN]${NC} 警告: ${WARN_COUNT}"
echo -e " ${RED}[FAIL]${NC} 失败: ${FAIL_COUNT}"
echo -e " ${BLUE}[INFO]${NC} 信息: ${INFO_COUNT}"
echo "---------------------------------------------------------------------"
echo " 总计: ${TOTAL} 项检查"
echo "============================================================================="

# 如果存在失败项则返回非零退出码
if [ "${FAIL_COUNT}" -gt 0 ]; then
  exit 1
fi

exit 0
