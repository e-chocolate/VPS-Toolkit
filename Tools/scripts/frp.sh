#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# Check if user is root
if [[ $(id -u) -ne 0 ]]; then
  echo "Error: You must be root to run this script"
  exit 1
fi

INFO="\e[0;32m[INFO]\e[0m"
ERROR="\e[0;31m[ERROR]\e[0m"

print_version() {
  clear
  echo "+------------------------------------------------------------------------+"
  echo "|          VT-Frp for Debian like Linux, Written by Echocolate           |"
  echo "+------------------------------------------------------------------------+"
  echo "|                    Scripts to install Frp on Linux                     |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Version: 1.0.0  Last Updated: 2026-08-30                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                      https://repos.echocolate.xyz                      |"
  echo "+------------------------------------------------------------------------+"
  sleep 2
}

detect_arch() {
  case "$(uname -m 2>/dev/null || true)" in
    x86_64|amd64)             echo 'amd64' ;;
    aarch64|arm64)            echo 'arm64' ;;
    armv7l|armv7*)            echo 'arm_hf' ;;
    armv5*|armv6*|arm|armel)  echo 'arm' ;;
    loongarch64|loong64)      echo 'loong64' ;;
    mips64el|mips64le)        echo 'mips64le' ;;
    mips64)                   echo 'mips64' ;;
    mipsel|mipsle)            echo 'mipsle' ;;
    mips)                     echo 'mips' ;;
    riscv64)                  echo 'riscv64' ;;
    *)
      echo "unknown"
      return 1
      ;;
  esac
}

mkdir_not_exists() {
  local dir=$1
  mkdir -p -- "$dir"
}

read_choice() {
  printf '%s\n' \
      '1. 安装服务端和客户端' \
      '2. 仅安装服务端' \
      '3. 仅安装客户端'
  read -p $'\e[0;33mPlease input your choice(1-3, default 1): \e[0m' -n1 install_choice
  echo
  case "$install_choice" in
    2)
      install_mode="server"
      ;;
    3)
      install_mode="client"
      ;;
    *)
      install_mode="both"
      ;;
    esac
}

get_github_latest() {
  local repo_name=$1
  local version=$(curl -s https://api.github.com/repos/${repo_name}/releases/latest | grep tag_name | head -n 1 | cut -d '"' -f 4)
  [ -z $version ] && {
    sleep 5
    version=$(curl -s https://api.github.com/repos/${repo_name}/tags | grep "name" | grep -vEi ".*(rc|r).*" | cut -d '"' -f 4 | sort -Vr | head -n 1)
  }
  [ -z $version ] && {
    echo -e "${ERROR} Cant get version for repo: ${repo_name}."
    exit 1
  }
  echo -e $version
}

create_frp_user() {
  if ! getent group frp >/dev/null 2>&1; then
    groupadd --system frp || return 1
  fi

  if ! id frp >/dev/null 2>&1; then
    useradd \
      --system \
      --gid frp \
      --home-dir /var/lib/frp \
      --create-home \
      --shell /usr/sbin/nologin \
      frp || return 1
  fi
}

install_frp() {
  local frp_version="${frp_ver:-$(get_github_latest 'fatedier/frp')}"
  local ARCH
  if ! ARCH=$(detect_arch); then
    echo -e "${ERROR} Unsupported architecture: $(uname -m)"
    return 1
  fi

  mkdir_not_exists "${frp_HOME}/backup"
  mkdir_not_exists "${VT_download}/frp"
  wget -c -nv "https://github.com/fatedier/frp/releases/download/${frp_version}/frp_${frp_version#v}_linux_${ARCH}.tar.gz" -O "${VT_download}/frp/frp_${frp_version#v}_linux_${ARCH}.tar.gz"
  [ $? -ne 0 ] && {
    echo -e "${ERROR} Download Frp failed."
    return 1
  }

  [[ -f "$frp_HOME"/frps.toml ]] && \cp "$frp_HOME"/frps.toml "$frp_HOME/backup/frps.toml.backup.$(date +%Y%m%d%H%M%S)"
  [[ -f "$frp_HOME"/frpc.toml ]] && \cp "$frp_HOME"/frpc.toml "$frp_HOME/backup/frpc.toml.backup.$(date +%Y%m%d%H%M%S)"
  \rm -f "${frp_HOME}"/frp*
  if ! tar -xzf "${VT_download}/frp/frp_${frp_version#v}_linux_${ARCH}.tar.gz" --strip-components=1 -C "${frp_HOME}"; then
    echo -e "${ERROR} Extract Frp failed."
    return 1
  fi

  chown -R root:root "${frp_HOME}" && chmod 755 "${frp_HOME}/frps" "${frp_HOME}/frpc"
  mkdir -p "${frp_LOG_PATH}"

  if [[ "${install_mode}" = 'server' ]]; then
    \rm -f "${frp_HOME}"/frpc*
    install_server_service
  elif [[ "${install_mode}" = 'client' ]]; then
    \rm -f "${frp_HOME}"/frps*
    install_client_service
  else
    install_server_service
    install_client_service
  fi
  chown -R frp:frp "${frp_LOG_PATH}"
}

install_server_service() {
  cat > /etc/systemd/system/frps.service <<EOF
[Unit]
Description=Frp Server Service
Documentation=https://github.com/fatedier/frp
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=frp
Group=frp
Restart=on-failure
RestartSec=5s
ExecStart=${frp_HOME}/frps -c ${frp_HOME}/frps.toml

StateDirectory=frp
StateDirectoryMode=0750
LogsDirectory=frp
LogsDirectoryMode=0750

[Install]
WantedBy=multi-user.target

EOF
  systemctl daemon-reload && systemctl enable frps.service
  chown root:frp "${frp_HOME}/frps.toml" && chmod 640 "${frp_HOME}/frps.toml"
  touch "${frp_LOG_PATH}/frps.log" && chown frp:frp "${frp_LOG_PATH}/frps.log"
}

install_client_service() {
  cat > /etc/systemd/system/frpc.service <<EOF
[Unit]
Description=Frp Client Service
Documentation=https://github.com/fatedier/frp
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=frp
Group=frp
Restart=on-failure
RestartSec=5s
ExecStart=${frp_HOME}/frpc -c ${frp_HOME}/frpc.toml

StateDirectory=frp
StateDirectoryMode=0750
LogsDirectory=frp
LogsDirectoryMode=0750

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload && systemctl enable frpc.service
  chown root:frp "${frp_HOME}/frpc.toml" && chmod 640 "${frp_HOME}/frpc.toml"
  touch "${frp_LOG_PATH}/frpc.log" && chmod 640 "${frp_LOG_PATH}/frpc.log"
}

reminder() {
  if [[ "${install_mode}" = 'server' ]]; then
    echo -e "Please check the \e[0;33mfrps.toml\e[0m file in ${frp_HOME} before you start the frps service."
  elif [[ "${install_mode}" = 'client' ]]; then
    echo -e "Please check the \e[0;33mfrpc.toml\e[0m file in ${frp_HOME} before you start the frpc service."
  else
    echo -e "Please check the \e[0;33mfrps.toml\e[0m file in ${frp_HOME} before you start the frps service."
    echo -e "Please check the \e[0;33mfrpc.toml\e[0m file in ${frp_HOME} before you start the frpc service."
  fi
}

install() {
  print_version
  read_choice
  if ! create_frp_user; then
    echo -e "${ERROR} Create user <frp> failed."
    return 1
  fi
  if ! install_frp; then
    echo -e "${ERROR} Install frp failed."
    return 1
  fi
  echo -e "${INFO} Install frp in ${install_mode} mode successfully."
  reminder
}

VT_HOME="${HOME}/VT-Data"
VT_log="${VT_HOME}/logs"
VT_download="${VT_HOME}/source"

mkdir_not_exists "${VT_HOME}"
mkdir_not_exists "${VT_log}"
mkdir_not_exists "${VT_download}"

frp_HOME='/usr/local/frp'
frp_LOG_PATH='/var/log/frp'

install 2>&1 | tee "${VT_log}/frp.log"
