#!/bin/bash
# This file is sourced by /etc/profile for interactive Bash shells
# Only run in Bash
[ -z "$BASH_VERSION" ] && return 0

sudoi() {
  if [ $# -lt 2 ]; then
    echo "Usage: sudoi <username> <command> [args...]" >&2
    return 1
  fi

  local user="$1"
  shift

  if ! getent passwd "$user" &>/dev/null; then
    echo "Error: User '$user' does not exist." >&2
    return 1
  fi

  local cmd
  cmd="$(printf '%q ' "$@")"

  sudo -u "$user" bash --login -c "$cmd"
}

is_valid_port() {
  local port="$1"

  if [[ -z "$port" ]]; then
    return 1
  fi

  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  if (( 10#$port < 1 || 10#$port > 65535 )); then
    return 1
  fi

  return 0
}

sssh() {
  if [ $# -eq 0 ]; then
    echo "Usage: sssh [port] <destination>" >&2
    return 1
  fi

  local port="${vt_sshPort:-22}"

  if [ $# -eq 2 ]; then
    port="$1"
    shift
  fi

  if ! is_valid_port "$port"; then
    echo "Error: Invalid port '$port'." >&2
    return 1
  fi

  local dst="$1"

  ssh -p "$port" "$dst"
}

ssync() {
  # 用法：ssync [port] <source> <destination>
  if [ $# -lt 2 ]; then
    echo "Usage: ssync [port] <source> [source2...] <destination>" >&2
    echo "Example: ssync 2222 file.txt user@host:/tmp/" >&2
    return 1
  fi

  # 检查 rsync 是否安装
  if ! command -v rsync &>/dev/null; then
    echo "Error: 'rsync' command not found. Please install it." >&2
    echo "  Ubuntu/Debian: sudo apt install rsync" >&2
    echo "  CentOS/RHEL:   sudo yum install rsync" >&2
    return 1
  fi

  local port="${vt_sshPort:-22}"

  # 如果第一个参数是数字且在有效范围内，视为端口；否则视为文件源
  if [[ "$1" =~ ^[0-9]+$ ]] && is_valid_port "$1"; then
    port="$1"
    shift
  fi

  if [ $# -lt 2 ]; then
    echo "Error: Missing source or destination." >&2
    return 1
  fi

  # 构建源文件数组
  local srcs=()
  while [[ $# -gt 1 ]]; do
    srcs+=("$1")
    shift
  done

  # 获取目标文件路径
  local dst="$1"

  # 构造 ssh 命令
  local ssh_cmd="ssh -p $port"

  echo "Syncing to $dst via port $port..."
  # 使用 rsync -avzP: 归档 + 详细 + 压缩 + 进度/断点
  rsync -avzP -e "$ssh_cmd" "${srcs[@]}" "$dst"
  
  local status=$?
  if [ $status -ne 0 ]; then
    echo "Error: Rsync transfer failed with exit code $status." >&2
  fi
  return $status
}

showUser() {
  # 查看Linux用户信息
  local user=$(whoami)
  [ ! -z $1 ] && user="$1"

  if ! id "$user" &>/dev/null; then
    echo "User '$user' does not exist."
    return 1
  fi

  echo "=== User: $user ==="
  getent passwd "$user" | {
    IFS=: read -r name _ uid gid gecos home shell
    echo "UID:          $uid"
    echo "GID:          $gid"
    echo "Home Dir:     $home"
    echo "Shell:        $shell"
    echo "Full Name:    ${gecos:-N/A}"  # 若 gecos 为空，则显示N/A
  }
  local user_groups=$(groups "$user" | cut -d: -f2 | xargs)
  echo "Groups:       $user_groups"
}

showGroup() {
  # 如果没有提供参数，查询当前用户的主组
  local groupname="${1:-$(id -gn)}"
 
  local gid=$(getent group "$groupname" | cut -d: -f3)
  if [ -z "$gid" ]; then
    echo "Group '$groupname' does not exist."
    return 1
  fi

  echo "Users in group '$groupname' (GID $gid):"

  # 1. 附属组成员（来自 /etc/group）
  local supplementary_members=$(getent group "$groupname" | cut -d: -f4)
  if [ -n "$supplementary_members" ]; then
    echo "$supplementary_members" | tr ',' '\n' | while read -r member; do
      [ -n "$member" ] && echo "  - $member (supplementary)"
    done
  fi

  # 2. 主组成员（来自 /etc/passwd）
  local primary_members=$(getent passwd | awk -F: -v gid="$gid" '$4 == gid {print $1}')
  if [ -n "$primary_members" ]; then
    echo "$primary_members" | while read -r member; do
      echo "  - $member (primary)"
    done
  fi
}

null() {
  local path="$1"
  [ -z "$path" ] && {
    echo "Usage: null/nullNano [file]"
    return 1
  }
  if [ -e "$path" ] && [ ! -f "$path" ]; then
    echo "Error: $path is not a file"
    return 1
  fi
  cat /dev/null > "$path"
}

nullNano() {
  local path="$1"
  if nano --help 2>&1 | grep -q '\-\-linenumbers'; then
    local options='--linenumbers'
  fi
  null "$path"
  [ $? -eq 0 ] && nano "$options" "$path"
}

nullDir() {
  local path="$1"
  [ -z "$path" ] && {
    echo "Usage: nullDir [directory]"
    return 1
  }
  if [ -e "$path" ] && [ ! -d "$path" ]; then
    echo "Error: $path is not a directory"
    return 1
  fi
  find "$path" -maxdepth 1 -type f -print0 -exec truncate -s 0 {} \;
  echo ""
}

nullDirRec() {
  local path="$1"
  [ -z "$path" ] && {
    echo "Usage: nullDirRec [directory]"
    return 1
  }
  if [ -e "$path" ] && [ ! -d "$path" ]; then
    echo "Error: $path is not a directory"
    return 1
  fi
  find "$path" -type f -print0 -exec truncate -s 0 {} \;
  echo ""
}

gen_str() {
  local length=${1:-16}
  tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c $length
  echo
}

gen_hex() {
  local length=${1:-8}
  tr -dc '0-9A-F' < /dev/urandom | head -c $length
  echo
}
