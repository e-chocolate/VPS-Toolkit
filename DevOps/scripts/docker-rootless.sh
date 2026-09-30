#!/usr/bin/env bash
set -Eeuo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

readonly SCRIPT_VERSION="1.8.4"
readonly MIN_SUBID_COUNT=65536

if [[ -t 1 ]]; then
  readonly GREEN=$'\033[0;32m'
  readonly YELLOW=$'\033[0;33m'
  readonly RED=$'\033[0;31m'
  readonly RESET=$'\033[0m'
else
  readonly GREEN=""
  readonly YELLOW=""
  readonly RED=""
  readonly RESET=""
fi

info() {
  printf '%s[INFO]%s %s\n' "$GREEN" "$RESET" "$*"
}

warn() {
  printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$*" >&2
}

die() {
  printf '%s[ERROR]%s %s\n' "$RED" "$RESET" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
安装并配置 Debian/Ubuntu 上的 Rootless Docker。

用法：
  ./docker-rootless.sh [普通用户名]
  sudo ./docker-rootless.sh [普通用户名]

推荐直接由需要使用 Docker 的普通用户运行。脚本会通过 sudo 安装系统包，
并为该用户创建和启动 systemd 用户服务。

使用 root 或 sudo 运行时，可以通过命令行参数或 ROOTLESS_USER 指定目标用户。
如果没有指定，脚本会从终端读取用户名。用户已存在时会验证现有账号；
用户不存在时会创建一个使用 /sbin/nologin 的专用系统用户，并由 useradd
按照发行版默认规则创建 /home/<用户名> 主目录，然后执行相同验证。

也可以由 root 为使用 nologin/false shell 的现有服务账号安装。脚本不会依赖
交互式登录，而会实际验证该账号的 HOME、systemd 用户管理器、运行时目录和 DBus。
所有需要用户输入或确认的项目都会在只读预检阶段一次性完成，
确认完成后脚本才会创建用户、移除软件包或修改服务状态。

可选环境变量：
  ROOTLESS_USER                   Rootless Docker 的目标用户名。
  DOCKER_VERSION                  Docker Engine 基础版本，默认 29.8.1-1。
  DOCKER_CLI_VERSION              Docker CLI 版本，默认与 Engine 相同。
  DOCKER_ROOTLESS_EXTRAS_VERSION  Rootless extras 版本，默认与 Engine 相同。
  CONTAINERD_IO_VERSION           containerd.io 版本，默认 2.3.6-1。
  DOCKER_BUILDX_VERSION           Buildx 插件版本，默认 0.37.1-1。
  DOCKER_COMPOSE_VERSION          Compose 插件版本，默认 5.5.1-1。
  ROOTFUL_DOCKER_MODE             检测到 rootful Docker 时的处理方式：
                                  coexist（共存）、stop（停止）或 abort（终止）。
  REMOVE_CONFLICTING_PACKAGES=1   非交互确认移除与 Docker CE 冲突的软件包。

示例：
  ./docker-rootless.sh
  sudo ./docker-rootless.sh
  sudo ./docker-rootless.sh alice
  sudo env ROOTLESS_USER=alice ./docker-rootless.sh
  ROOTFUL_DOCKER_MODE=coexist ./docker-rootless.sh
  sudo env ROOTFUL_DOCKER_MODE=coexist ./docker-rootless.sh alice
EOF
}

confirm_action() {
  local approved="$1"
  local prompt="$2"
  local reply

  if [[ "$approved" == "1" ]]; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    die "当前为非交互执行。${prompt} 如确认继续，请设置对应的确认环境变量为 1。"
  fi

  read -r -p "${prompt} [y/N] " reply
  case "$reply" in
    y|Y|yes|YES|Yes) ;;
    *) die "操作已取消。" ;;
  esac
}

choose_rootful_mode() {
  local choice

  printf '\n检测到系统级 rootful Docker，请选择处理方式：\n' >&2
  printf '  1) coexist  保留 rootful Docker，并与 rootless Docker 同时运行\n' >&2
  printf '  2) stop     停止并禁用 rootful Docker，然后安装 rootless Docker\n' >&2
  printf '  3) abort    不做更改，终止本次安装\n' >&2

  while true; do
    if ! read -r -p '请选择 [1/2/3]：' choice; then
      die "无法读取选择，安装已终止。"
    fi
    case "$choice" in
      1|coexist|c|C)
        rootful_mode="coexist"
        return 0
        ;;
      2|stop|s|S)
        rootful_mode="stop"
        return 0
        ;;
      3|abort|a|A|q|Q)
        die "操作已取消。"
        ;;
      *)
        warn "无效选择，请输入 1、2 或 3。"
        ;;
    esac
  done
}

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo -- "$@"
  fi
}

load_target_user() {
  local user_name="$1"

  passwd_entry="$(getent passwd "$user_name" || true)"
  [[ -n "$passwd_entry" ]] || return 1
  IFS=: read -r target_user _ target_uid target_gid _ target_home target_shell <<<"$passwd_entry"
}

validate_target_user() {
  [[ "$target_uid" =~ ^[0-9]+$ ]] || die "无法确定用户 ${target_user} 的 UID。"
  [[ "$target_gid" =~ ^[0-9]+$ ]] || die "无法确定用户 ${target_user} 的 GID。"
  (( target_uid != 0 )) || die "Rootless Docker 不能安装给 root 用户。"
  [[ "$target_home" == /* && -d "$target_home" ]] || die "用户主目录不存在或不是绝对路径：${target_home}"

  if (( EUID != 0 )) && [[ "$(id -u)" != "$target_uid" ]]; then
    die "普通用户只能为自己安装；当前用户 UID=$(id -u)，目标用户 UID=${target_uid}。"
  fi
  if (( EUID == 0 )); then
    command -v runuser >/dev/null 2>&1 || die "缺少必要命令：runuser"
    as_root runuser -u "$target_user" -- test -w "$target_home" \
      || die "用户 ${target_user} 无法写入其主目录 ${target_home}。"
  else
    [[ -w "$target_home" ]] || die "用户 ${target_user} 无法写入其主目录 ${target_home}。"
  fi
}

TEMP_DIRS=()
cleanup() {
  local path
  for path in "${TEMP_DIRS[@]:-}"; do
    if [[ -n "$path" && -d "$path" ]]; then
      rm -rf -- "$path"
    fi
  done
}
trap cleanup EXIT

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
(( $# <= 1 )) || die "参数过多。请运行 $0 --help 查看用法。"

[[ -r /etc/os-release ]] || die "无法读取 /etc/os-release。"
# shellcheck disable=SC1091
. /etc/os-release

case "${ID:-}" in
  debian|ubuntu) readonly OS_ID="$ID" ;;
  *) die "仅支持 Debian 和 Ubuntu；当前系统 ID=${ID:-unknown}。" ;;
esac

[[ -n "${VERSION_CODENAME:-}" ]] || die "/etc/os-release 缺少 VERSION_CODENAME。"
[[ "$VERSION_CODENAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "VERSION_CODENAME 包含非法字符。"
readonly OS_CODENAME="$VERSION_CODENAME"
[[ -n "${VERSION_ID:-}" ]] || die "/etc/os-release 缺少 VERSION_ID。"
[[ "$VERSION_ID" =~ ^[A-Za-z0-9._-]+$ ]] || die "VERSION_ID 包含非法字符。"
readonly OS_VERSION_ID="$VERSION_ID"

for command_name in apt-get awk chmod dpkg dpkg-deb dpkg-query getent loginctl mktemp systemctl useradd usermod; do
  command -v "$command_name" >/dev/null 2>&1 || die "缺少必要命令：${command_name}"
done

if (( EUID != 0 )); then
  command -v sudo >/dev/null 2>&1 || die "需要 sudo 来安装系统软件包。"
  sudo -v
fi

[[ -d /run/systemd/system ]] || die "需要以 systemd 作为 init 系统；当前环境无法创建 Rootless Docker 用户服务。"

# 阶段 1：仅执行只读检查，并集中收集所有用户输入。
info "进入只读预检与集中确认阶段；此阶段不会修改用户、软件包或服务。"

requested_user="${1:-${ROOTLESS_USER:-}}"
if [[ -z "$requested_user" ]]; then
  if (( EUID == 0 )); then
    [[ -t 0 ]] \
      || die "root/sudo 非交互执行时必须通过参数或 ROOTLESS_USER 指定目标用户。"

    while [[ -z "$requested_user" ]]; do
      if ! read -r -p '请输入运行 Rootless Docker 的用户名：' requested_user; then
        die "无法读取目标用户名。"
      fi
      if [[ -z "$requested_user" ]]; then
        warn "用户名不能为空，请重新输入。"
      fi
    done
  fi
  if (( EUID != 0 )); then
    requested_user="$(id -un)"
  fi
fi

[[ "$requested_user" != -* \
  && "$requested_user" != *:* \
  && "$requested_user" != */* \
  && "$requested_user" != *[[:space:]]* ]] \
  || die "用户名格式无效：${requested_user}"

target_user_created=0
target_user_needs_creation=0
if load_target_user "$requested_user"; then
  validate_target_user
  target_user_plan="复用现有用户 ${target_user}（UID ${target_uid}，HOME ${target_home}）"
else
  (( EUID == 0 )) \
    || die "用户不存在：${requested_user}。只有使用 root 或 sudo 运行脚本时才能创建目标用户。"
  [[ ${#requested_user} -le 32 \
    && "$requested_user" =~ ^[a-z_][a-z0-9_.-]*[$]?$ ]] \
    || die "无法创建用户 ${requested_user}：请使用以小写字母或下划线开头、长度不超过 32 的常规 Linux 用户名。"
  [[ -x /sbin/nologin ]] || die "无法创建用户：未找到 /sbin/nologin。"
  new_user_home="/home/${requested_user}"

  if [[ -e "$new_user_home" || -L "$new_user_home" ]]; then
    die "用户主目录路径已存在：${new_user_home}"
  fi
  target_user_needs_creation=1
  target_user_plan="创建专用系统用户 ${requested_user}（HOME ${new_user_home}，SHELL /sbin/nologin）"
fi

rootful_detected=0
if as_root systemctl is-active --quiet docker.service 2>/dev/null \
  || as_root systemctl is-active --quiet docker.socket 2>/dev/null \
  || as_root systemctl is-enabled --quiet docker.service 2>/dev/null \
  || as_root systemctl is-enabled --quiet docker.socket 2>/dev/null \
  || [[ -S /var/run/docker.sock ]]; then
  rootful_detected=1
fi

rootful_mode="${ROOTFUL_DOCKER_MODE:-}"
case "$rootful_mode" in
  ""|coexist|stop|abort) ;;
  *) die "ROOTFUL_DOCKER_MODE 只能是 coexist、stop 或 abort；当前值为 ${rootful_mode}。" ;;
esac

if (( rootful_detected == 1 )); then
  warn "检测到正在运行、已启用或提供 /var/run/docker.sock 的 rootful Docker。"
  if [[ -z "$rootful_mode" ]]; then
    if [[ -t 0 ]]; then
      choose_rootful_mode
    else
      die "非交互执行必须设置 ROOTFUL_DOCKER_MODE=coexist|stop|abort。"
    fi
  fi
elif [[ -z "$rootful_mode" ]]; then
  rootful_mode="stop"
fi

[[ "$rootful_mode" != "abort" ]] || die "根据 ROOTFUL_DOCKER_MODE=abort 终止安装。"
readonly ROOTFUL_MODE="$rootful_mode"

conflicting_candidates=(
  docker.io
  docker-compose
  docker-compose-v2
  docker-doc
  docker-buildx
  podman-docker
  containerd
  runc
)
conflicting_installed=()
for package_name in "${conflicting_candidates[@]}"; do
  if [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$package_name" 2>/dev/null || true)" == "ii " ]]; then
    conflicting_installed+=("$package_name")
  fi
done

remove_conflicting_packages=0
if (( ${#conflicting_installed[@]} > 0 )); then
  warn "检测到与 Docker CE 冲突的软件包：${conflicting_installed[*]}"
  warn "移除软件包不会自动删除其镜像、容器或卷数据，但可能影响依赖它们的服务。"
  confirm_action "${REMOVE_CONFLICTING_PACKAGES:-0}" \
    "是否允许移除上述冲突软件包？"
  remove_conflicting_packages=1
  conflicting_plan="移除 ${conflicting_installed[*]}"
else
  conflicting_plan="未检测到冲突软件包"
fi

printf '\n安装执行摘要：\n'
printf '  目标用户：%s\n' "$target_user_plan"
printf '  Rootful 模式：%s\n' "$ROOTFUL_MODE"
printf '  冲突包处理：%s\n\n' "$conflicting_plan"

# 阶段 2：从这里开始修改系统，后续代码不得再请求交互式输入。
info "所有用户输入和确认已完成，开始执行安装。"

if (( target_user_needs_creation == 1 )); then

  info "用户 ${requested_user} 不存在，正在创建 Rootless Docker 专用系统用户。"
  if getent group "$requested_user" >/dev/null 2>&1; then
    info "复用已存在的同名用户组 ${requested_user}。"
    as_root useradd --system --create-home --home-dir "$new_user_home" \
      --gid "$requested_user" --shell /sbin/nologin "$requested_user"
  else
    as_root useradd --system --create-home --home-dir "$new_user_home" \
      --user-group --shell /sbin/nologin "$requested_user"
  fi
  load_target_user "$requested_user" \
    || die "已执行 useradd，但仍无法查询用户：${requested_user}"
  target_user_created=1
  validate_target_user
fi
if (( target_user_created == 1 )); then
  info "已创建系统用户 ${target_user}：UID=${target_uid}，HOME=${target_home}。"
fi
case "$target_shell" in
  */nologin|*/false)
    warn "目标用户 ${target_user} 使用非登录 shell ${target_shell}；将通过 systemd 用户管理器配置 Rootless Docker。"
    ;;
esac

readonly TARGET_USER="$target_user"
readonly TARGET_UID="$target_uid"
readonly TARGET_HOME="$target_home"
readonly TARGET_RUNTIME_DIR="/run/user/${TARGET_UID}"

printf '%s\n' \
  '+------------------------------------------------------------------------+' \
  '|            Rootless Docker installer for Debian and Ubuntu             |' \
  '+------------------------------------------------------------------------+'
printf '  Version: %s\n  OS: %s %s\n  Target user: %s (UID %s)\n\n' \
  "$SCRIPT_VERSION" "$OS_ID" "$OS_CODENAME" "$TARGET_USER" "$TARGET_UID"

case "$ROOTFUL_MODE" in
  coexist)
    info "已选择共存模式：将保留 rootful Docker，并安装独立的 rootless daemon。"
    ;;
  stop)
    info "已选择 rootless-only 模式：将停止并禁用 rootful Docker，但不会删除 /var/lib/docker。"
    ;;
esac

if (( remove_conflicting_packages == 1 )); then
  info "按照预检阶段的确认结果移除冲突软件包。"
  as_root env DEBIAN_FRONTEND=noninteractive apt-get remove -y "${conflicting_installed[@]}"
fi

info "安装下载和运行 Rootless Docker 所需的基础组件。"
as_root apt-get update
as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl uidmap dbus-user-session iptables

architecture="$(dpkg --print-architecture)"
case "${OS_ID}:${architecture}" in
  debian:amd64|debian:armhf|debian:arm64|debian:ppc64el) ;;
  ubuntu:amd64|ubuntu:armhf|ubuntu:arm64|ubuntu:ppc64el|ubuntu:s390x) ;;
  *) die "Docker 官方不支持当前系统与架构组合：${OS_ID}/${architecture}" ;;
esac

containerd_io_version="${CONTAINERD_IO_VERSION:-${containerd_io_ver:-2.3.6-1}}"
docker_ce_version="${DOCKER_VERSION:-${docker_ce_ver:-29.8.1-1}}"
docker_ce_cli_version="${DOCKER_CLI_VERSION:-${docker_ce_cli_ver:-${docker_ce_version}}}"
docker_rootless_extras_version="${DOCKER_ROOTLESS_EXTRAS_VERSION:-${docker_ce_rootless_extras_ver:-${docker_ce_version}}}"
docker_buildx_version="${DOCKER_BUILDX_VERSION:-${docker_buildx_plugin_ver:-0.37.1-1}}"
docker_compose_version="${DOCKER_COMPOSE_VERSION:-${docker_compose_plugin_ver:-5.5.1-1}}"

package_version_for_filename() {
  local package_name="$1"
  local requested_version="$2"
  local version_without_epoch="${requested_version#*:}"

  [[ "$version_without_epoch" =~ ^[A-Za-z0-9.+~_-]+$ ]] \
    || die "${package_name} 版本包含非法字符：${requested_version}"

  if [[ "$version_without_epoch" == *"~${OS_ID}.${OS_VERSION_ID}~${OS_CODENAME}" ]]; then
    printf '%s\n' "$version_without_epoch"
  else
    printf '%s~%s.%s~%s\n' \
      "$version_without_epoch" "$OS_ID" "$OS_VERSION_ID" "$OS_CODENAME"
  fi
}

download_deb() {
  local package_name="$1"
  local requested_version="$2"
  local destination="$3"
  local file_version filename url
  local actual_package actual_version actual_architecture

  file_version="$(package_version_for_filename "$package_name" "$requested_version")"
  filename="${package_name}_${file_version}_${architecture}.deb"
  url="${docker_download_base}/${filename}"

  info "下载 ${package_name} ${file_version}：${url}"
  if ! curl --fail --location --silent --show-error \
    --retry 3 --retry-delay 2 --connect-timeout 20 \
    --output "$destination" "$url"; then
    die "无法从 Docker 官方地址下载：${url}"
  fi
  [[ -s "$destination" ]] || die "下载文件为空：${url}"

  actual_package="$(dpkg-deb --field "$destination" Package)"
  actual_version="$(dpkg-deb --field "$destination" Version)"
  actual_architecture="$(dpkg-deb --field "$destination" Architecture)"

  [[ "$actual_package" == "$package_name" ]] \
    || die "软件包名称不匹配：期望 ${package_name}，实际 ${actual_package}。"
  [[ "${actual_version#*:}" == "$file_version" ]] \
    || die "${package_name} 版本不匹配：期望 ${file_version}，实际 ${actual_version}。"
  [[ "$actual_architecture" == "$architecture" || "$actual_architecture" == "all" ]] \
    || die "${package_name} 架构不匹配：期望 ${architecture}，实际 ${actual_architecture}。"
}

readonly docker_download_base="https://download.docker.com/linux/${OS_ID}/dists/${OS_CODENAME}/pool/stable/${architecture}"
package_temp_dir="$(mktemp -d -t docker-rootless.XXXXXXXX)"
TEMP_DIRS+=("$package_temp_dir")

local_debs=(
  "${package_temp_dir}/containerd.io.deb"
  "${package_temp_dir}/docker-ce.deb"
  "${package_temp_dir}/docker-ce-cli.deb"
  "${package_temp_dir}/docker-buildx-plugin.deb"
  "${package_temp_dir}/docker-compose-plugin.deb"
  "${package_temp_dir}/docker-ce-rootless-extras.deb"
)

download_deb containerd.io "$containerd_io_version" "${local_debs[0]}"
download_deb docker-ce "$docker_ce_version" "${local_debs[1]}"
download_deb docker-ce-cli "$docker_ce_cli_version" "${local_debs[2]}"
download_deb docker-buildx-plugin "$docker_buildx_version" "${local_debs[3]}"
download_deb docker-compose-plugin "$docker_compose_version" "${local_debs[4]}"
download_deb docker-ce-rootless-extras "$docker_rootless_extras_version" "${local_debs[5]}"

info "设置本地 DEB 的读取权限，允许 APT 使用 _apt 沙箱访问。"
chmod 0755 "$package_temp_dir"
chmod 0644 "${local_debs[@]}"

info "安装从 Docker 官方下载地址获取的本地 DEB 软件包。"
as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${local_debs[@]}"

command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1 \
  || die "docker-ce-rootless-extras 已安装，但找不到 dockerd-rootless-setuptool.sh。"

rootful_docker_healthy() {
  as_root env -u DOCKER_HOST -u DOCKER_CONTEXT \
    docker --host unix:///var/run/docker.sock info >/dev/null 2>&1
}

if [[ "$ROOTFUL_MODE" == "coexist" ]]; then
  info "启用、启动并验证系统级 rootful Docker。"
  if ! as_root systemctl enable --now docker.service docker.socket; then
    as_root systemctl --no-pager --full status docker.service docker.socket || true
    die "无法启用或启动系统级 rootful Docker。"
  fi

  rootful_verified=0
  for _ in {1..20}; do
    if rootful_docker_healthy; then
      rootful_verified=1
      break
    fi
    sleep 1
  done

  if (( rootful_verified != 1 )); then
    warn "rootful Docker 未通过验证，以下是系统服务状态："
    as_root systemctl --no-pager --full status docker.service docker.socket || true
    die "共存模式要求 rootful Docker 可通过 /var/run/docker.sock 访问。"
  fi
else
  info "停止并禁用软件包默认启动的 rootful Docker 服务。"
  as_root systemctl disable --now docker.service docker.socket
  as_root rm -f -- /var/run/docker.sock
fi

subid_has_sufficient_range() {
  local file="$1"
  awk -F: -v user="$TARGET_USER" -v uid="$TARGET_UID" -v required="$MIN_SUBID_COUNT" '
    ($1 == user || $1 == uid) && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $3 >= required {
      found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "$file"
}

next_subid_start() {
  local file="$1"
  awk -F: '
    $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {
      end = $2 + $3
      if (end > max) max = end
    }
    END {
      if (max < 100000) max = 100000
      printf "%.0f\n", max
    }
  ' "$file"
}

ensure_subid_range() {
  local file="$1"
  local usermod_option="$2"
  local label="$3"
  local start end

  as_root touch "$file"
  if subid_has_sufficient_range "$file"; then
    info "${TARGET_USER} 已有至少 ${MIN_SUBID_COUNT} 个 subordinate ${label}。"
    return 0
  fi

  start="$(next_subid_start "$file")"
  end=$((start + MIN_SUBID_COUNT - 1))
  (( end <= 4294967295 )) || die "无法为 ${TARGET_USER} 分配 subordinate ${label}：ID 空间不足。"

  info "为 ${TARGET_USER} 分配 subordinate ${label}：${start}-${end}。"
  as_root usermod "$usermod_option" "${start}-${end}" "$TARGET_USER"
  subid_has_sufficient_range "$file" \
    || die "写入 ${file} 后未找到有效的 subordinate ${label} 范围。"
}

# Debian/Ubuntu 上 useradd --system 默认不为系统用户分配 subordinate IDs，
# 因此无论目标是新建系统用户还是现有用户，都在这里显式补齐。
ensure_subid_range /etc/subuid --add-subuids UIDs
ensure_subid_range /etc/subgid --add-subgids GIDs

info "启用 ${TARGET_USER} 的 linger，并启动 systemd 用户管理器。"
as_root loginctl enable-linger "$TARGET_USER"
if ! as_root systemctl start "user@${TARGET_UID}.service"; then
  as_root systemctl --no-pager --full status "user@${TARGET_UID}.service" || true
  die "无法启动 ${TARGET_USER} 的 systemd 用户管理器。"
fi

for _ in {1..50}; do
  if [[ -d "$TARGET_RUNTIME_DIR" ]]; then
    break
  fi
  sleep 0.2
done
[[ -d "$TARGET_RUNTIME_DIR" ]] \
  || die "systemd 未创建运行时目录 ${TARGET_RUNTIME_DIR}。"

run_as_target() {
  local -a target_environment=(
    env
    -u DOCKER_HOST
    -u DOCKER_CONTEXT
    "HOME=${TARGET_HOME}"
    "USER=${TARGET_USER}"
    "LOGNAME=${TARGET_USER}"
    "XDG_RUNTIME_DIR=${TARGET_RUNTIME_DIR}"
    "DBUS_SESSION_BUS_ADDRESS=unix:path=${TARGET_RUNTIME_DIR}/bus"
    "PATH=${PATH}"
  )

  if (( EUID == TARGET_UID )); then
    "${target_environment[@]}" "$@"
  else
    as_root runuser -u "$TARGET_USER" -- "${target_environment[@]}" "$@"
  fi
}

run_as_target test -w "$TARGET_RUNTIME_DIR" \
  || die "用户 ${TARGET_USER} 无法写入 ${TARGET_RUNTIME_DIR}。"

if ! as_root systemctl is-active --quiet "user@${TARGET_UID}.service"; then
  as_root systemctl --no-pager --full status "user@${TARGET_UID}.service" || true
  die "${TARGET_USER} 的 systemd 用户管理器未处于 active 状态。"
fi

if ! run_as_target systemctl --user show-environment >/dev/null 2>&1; then
  as_root systemctl --no-pager --full status "user@${TARGET_UID}.service" || true
  die "无法以 ${TARGET_USER} 连接 systemd 用户管理器。"
fi

if ! run_as_target systemctl --user start dbus.socket; then
  run_as_target systemctl --user --no-pager --full status dbus.socket || true
  die "无法为 ${TARGET_USER} 启动 DBus 用户 socket。"
fi

for _ in {1..50}; do
  if [[ -S "${TARGET_RUNTIME_DIR}/bus" ]]; then
    break
  fi
  sleep 0.2
done
[[ -S "${TARGET_RUNTIME_DIR}/bus" ]] \
  || die "未找到 ${TARGET_USER} 的 DBus socket：${TARGET_RUNTIME_DIR}/bus"

info "为 ${TARGET_USER} 安装并启动 Rootless Docker 用户服务。"
rootless_setup_args=(install)
if [[ "$ROOTFUL_MODE" == "coexist" ]]; then
  rootless_setup_args+=(--force)
fi
run_as_target dockerd-rootless-setuptool.sh "${rootless_setup_args[@]}"

rootless_verified=0
for _ in {1..20}; do
  security_options="$(run_as_target docker --context rootless info --format '{{json .SecurityOptions}}' 2>/dev/null || true)"
  if [[ "$security_options" == *"name=rootless"* ]]; then
    rootless_verified=1
    break
  fi
  sleep 1
done

if (( rootless_verified != 1 )); then
  warn "Rootless Docker 未通过验证，以下是用户服务状态："
  run_as_target systemctl --user --no-pager --full status docker.service || true
  die "无法确认 Docker daemon 正以 rootless 模式运行。"
fi

run_as_target docker --context rootless buildx version >/dev/null
run_as_target docker --context rootless compose version >/dev/null

if [[ "$ROOTFUL_MODE" == "coexist" ]]; then
  rootful_result="保留并运行（unix:///var/run/docker.sock）"
else
  rootful_result="已停止并禁用"
fi

cat <<EOF

安装完成。

  用户：       ${TARGET_USER}
  Docker 上下文：rootless
  Socket：     unix://${TARGET_RUNTIME_DIR}/docker.sock
  数据目录：   ${TARGET_HOME}/.local/share/docker
  Rootful：    ${rootful_result}

管理员可在不登录专用用户的情况下验证：
  runuser -u ${TARGET_USER} -- env HOME=${TARGET_HOME} XDG_RUNTIME_DIR=${TARGET_RUNTIME_DIR} docker --context rootless info
  runuser -u ${TARGET_USER} -- env HOME=${TARGET_HOME} XDG_RUNTIME_DIR=${TARGET_RUNTIME_DIR} docker --context rootless run --rm hello-world

管理用户服务：
  runuser -u ${TARGET_USER} -- env XDG_RUNTIME_DIR=${TARGET_RUNTIME_DIR} DBUS_SESSION_BUS_ADDRESS=unix:path=${TARGET_RUNTIME_DIR}/bus systemctl --user status docker
  runuser -u ${TARGET_USER} -- env XDG_RUNTIME_DIR=${TARGET_RUNTIME_DIR} DBUS_SESSION_BUS_ADDRESS=unix:path=${TARGET_RUNTIME_DIR}/bus systemctl --user restart docker

EOF

if [[ "$ROOTFUL_MODE" == "coexist" ]]; then
  cat <<'EOF'
访问 rootful Docker：
  sudo docker --host unix:///var/run/docker.sock info

EOF
fi

cat <<'EOF'
注意：hello-world 验证会从网络拉取镜像，本脚本没有自动执行该步骤。
EOF
