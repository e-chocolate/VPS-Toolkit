#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# Check if user is root
if [ $(id -u) != "0" ]; then
  echo "Error: You must be root to run this script"
  exit 1
fi

INFO="\e[0;32m[INFO]\e[0m"
ERROR="\e[0;31m[ERROR]\e[0m"

print_version() {
  clear
  echo "+------------------------------------------------------------------------+"
  echo "|         VT-Gitea for Debian like Linux, Written by Echocolate          |"
  echo "+------------------------------------------------------------------------+"
  echo "|                   Scripts to install Gitea on Linux                    |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Version: 1.0.0  Last Updated: 2026-08-22                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                      https://repos.echocolate.xyz                      |"
  echo "+------------------------------------------------------------------------+"
  sleep 2
}

read_parameters() {
  read -p $'\e[0;33mChoose whether to listen on a Unix socket instead of TCP (y/n, default n): \e[0m' -n1 socket
  echo
  read -p $'\e[0;33mChoose whether to use gitea builtin SSH (y/n, default n): \e[0m' -n1 builtin
  echo
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    armv7l|armv6l)
      echo "arm-6"
      ;;
    armv5tel|armv5tejl)
      echo "arm-5"
      ;;
    i386|i686)
      echo "386"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

download_gitea() {
  local ARCH=$(detect_arch)
  local latest=$(curl -s https://api.github.com/repos/go-gitea/gitea/releases/latest | grep tag_name | head -n 1 | cut -d '"' -f 4 | sed 's/v//g')
  local status=0
  echo -e "${INFO} Install gitea v${latest}"
  wget -nv "https://dl.gitea.com/gitea/${latest}/gitea-${latest}-linux-${ARCH}" -O /tmp/gitea
  status=$((status + $?))
  wget -nv "https://raw.githubusercontent.com/go-gitea/gitea/refs/heads/release/v${latest%.*}/custom/conf/app.example.ini" -O /tmp/app.ini
  status=$((status + $?))
  [ "${status}" -ne 0 ] && {
    echo -e "${ERROR} Download Gitea failed."
    clean_with_error
  }
}

check_git() {
  if id git &>/dev/null; then
    echo -e "${INFO} User git already exists."
  else
    useradd -r -s /bin/bash -c 'Git Version Control' -U -p '!' -d /home/git git
  fi

  [ ! -d /home/git ] && mkdir /home/git
  chown git:git /home/git && chmod 755 /home/git

  if ! id git > /dev/null 2>&1; then
    echo -e "${ERROR} Failed to create git user."
    clean_with_error
  fi
}

configure_gitea() {
  mv /tmp/gitea /usr/local/bin/gitea
  chmod +x /usr/local/bin/gitea
  mkdir -p /var/lib/gitea/{custom,data,log}
  chown -R git:git /var/lib/gitea/
  chmod -R 750 /var/lib/gitea/
  mkdir -p /etc/gitea
  mv /tmp/app.ini /etc/gitea/app.ini
  chown -R root:git /etc/gitea
  chmod 770 /etc/gitea
  chmod 660 /etc/gitea/app.ini
  [[ "${socket}" = 'y' ]] && configure_socket
  [[ "${builtin}" = 'y' ]] && sed -i 's/;START_SSH_SERVER = false/;START_SSH_SERVER = false\nSTART_SSH_SERVER = true/g' /etc/gitea/app.ini
}

configure_socket() {
  sed -i 's/;PROTOCOL = http/;PROTOCOL = http\nPROTOCOL = http+unix/g' /etc/gitea/app.ini
  sed -i 's|\(^;HTTP_ADDR.*\)|\1\nHTTP_ADDR = /run/gitea/gitea.socket|g' /etc/gitea/app.ini
  sed -i 's/\(^;UNIX_SOCKET_PERMISSION.*\)/\1\nUNIX_SOCKET_PERMISSION = 666/g' /etc/gitea/app.ini
  cat > /etc/tmpfiles.d/gitea_run_dir.conf <<EOF
# 类型  路径             模式  用户  组    寿命(空白表示不自动清理)
d       /run/gitea       0755  git   git   -
EOF
  systemd-tmpfiles --create /etc/tmpfiles.d/gitea_run_dir.conf
  [ $? -ne 0 ] && {
    echo -e "${ERROR} Unable to set socket."
    clean_with_error
  }
}

install_service() {
  cat > /etc/systemd/system/gitea.service <<EOF
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target

[Service]
RestartSec=2s
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/gitea/
ExecStartPre=+/usr/bin/install -d -m 2750 -o git -g www /run/gitea
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=/var/lib/gitea

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

clean_with_error() {
  rm -f /tmp/gitea /tmp/app.ini
  rm -rf /usr/local/bin/gitea /var/lib/gitea /etc/gitea
  rm -f /etc/tmpfiles.d/gitea_run_dir.conf
  exit 1
}

reminder() {
  echo
  cat <<EOF
Follow the following steps to start gitea:
1. Ensure all configuration details are set correctly in $(echo -e "\e[0;33m/etc/gitea/app.ini\e[0m")
2. Run $(echo -e "\e[0;33m\`systemctl enable --now gitea\`\e[0m") to start gitea service
3. After the installation is finished, run $(echo -e "\e[0;33m\`chmod -R 750 /etc/gitea && chmod 640 /etc/gitea/app.ini\`\e[0m")
EOF
}

install() {
  print_version
  read_parameters
  download_gitea
  check_git
  configure_gitea
  install_service
  reminder
}

VT_HOME="${HOME}/VT-Data"
VT_log="${VT_HOME}/logs"

[ ! -d "${VT_HOME}/" ] && mkdir ${VT_HOME}
[ ! -d "${VT_log}/" ] && mkdir ${VT_log}

install 2>&1 | tee "${VT_log}/gitea.log"
