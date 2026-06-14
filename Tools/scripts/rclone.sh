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
  echo "|         VT-Rclone for Debian like Linux, Written by Echocolate         |"
  echo "+------------------------------------------------------------------------+"
  echo "|                   Scripts to install Rclone on Linux                   |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Version: 1.0.0  Last Updated: 2026-06-14                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                      https://repos.echocolate.xyz                      |"
  echo "+------------------------------------------------------------------------+"
  sleep 2
}

determine_path() {
  Rclone_Parent_PATH="$(dirname $0)/.."

  if [[ "$Rclone_Parent_PATH" != /* ]]; then
    echo -e "${ERROR} ${Rclone_Parent_PATH} 不是绝对路径，尝试获取绝对路径"
    Rclone_Parent_PATH="$(pwd)/$(dirname $0)/.."
  fi

  if [[ "$Rclone_Parent_PATH" == /* ]] && [[ -n "$Rclone_Parent_PATH" ]]; then
    echo -e "${INFO} ${Rclone_Parent_PATH}"
  else
    echo -e "${ERROR} 获取绝对路径失败"
    exit 1
  fi
}

create_user() {
  if id rclone >/dev/null 2>&1; then
    echo -e "${INFO} User rclone already exists."
  else
    useradd -d /home/rclone -r -s /sbin/nologin rclone
  fi
  [ ! -d '/home/rclone' ] && {
    echo -e "${INFO} Create rclone HOME."
    mkdir /home/rclone
  }
  chown -R rclone:rclone /home/rclone
}

install_rclone() {
  curl https://rclone.org/install.sh | bash
}

config_rclone() {
  sudo -u rclone mkdir -p "${Rclone_CONF_PATH}/rclone"
  echo "" | sudo -u rclone tee -a "${Rclone_CONF_PATH}/rclone/rclone.conf"
  cat /dev/null > "${Rclone_CONF_PATH}/rclone/rclone.conf"
  mkdir -p /usr/local/rcloned 
  \cp -a "$Rclone_Parent_PATH/bin/rcloned" /usr/local/rcloned/rcloned
  chmod -R +x /usr/local/rcloned/ && chown -R root:root /usr/local/rcloned/
}

service_rclone() {
  cat > /etc/systemd/system/rcloned.service << EOF
[Unit]
Description=Rclone
After=network-online.target

[Service]
User=rclone
Type=oneshot
ExecStart=/usr/local/rcloned/rcloned systemd_mount
ExecStop=/usr/local/rcloned/rcloned stop
Restart=on-abort
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
}

configure_fuse() {
  \cp -a /etc/fuse.conf /etc/fuse.conf.bk
  if ! grep -qE "^user_allow_other" /etc/fuse.conf; then
    sed -i 's/^#user_allow_other$/user_allow_other/g' /etc/fuse.conf
  fi
  if ! grep -qE "^user_allow_other" /etc/fuse.conf; then
    echo -e "\nuser_allow_other" >> /etc/fuse.conf
  fi
}

install() {
  determine_path
  create_user
  install_rclone
  config_rclone
  service_rclone
  systemctl daemon-reload && systemctl enable rcloned
  configure_fuse
  echo -e "${INFO} Run 'rclone config' first then run 'systemctl start rcloned'"
}

Rclone_CONF_PATH="/home/rclone/.config"

VT_HOME="${HOME}/VT-Data"
VT_log="${VT_HOME}/logs"

[ ! -d "${VT_HOME}/" ] && mkdir ${VT_HOME}
[ ! -d "${VT_log}/" ] && mkdir ${VT_log}

install 2>&1 | tee "${VT_log}/rclone.log"
