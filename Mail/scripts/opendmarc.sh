#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# Check if user is root
if [ $(id -u) != "0" ]; then
  echo "Error: You must be root to run this script"
  exit 1
fi

document() {
  <<EOF
0. 询问是否启用数据库特性。不启用则不管；如果启用则继续询问数据库信息
1. 安装 opendamrc
2. 备份默认配置文件
3. 手动创建数据库
4. 更新配置文件
EOF
}

INFO="\e[0;32m[INFO]\e[0m"
ERROR="\e[0;31m[ERROR]\e[0m"

determine_path() {
  OpenDMARC_Parent_PATH="$(dirname $0)/.."

  if [[ "$OpenDMARC_PARENT_PATH" != /* ]]; then
    echo -e "${ERROR} ${OpenDMARC_PARENT_PATH} 不是绝对路径，尝试获取绝对路径"
    OpenDMARC_PARENT_PATH="$(pwd)/$(dirname $0)/.."
  fi

  if [[ "$OpenDMARC_PARENT_PATH" == /* ]] && [[ -n "$OpenDMARC_PARENT_PATH" ]]; then
    echo -e "${INFO} ${OpenDMARC_PARENT_PATH}"
  else
    echo -e "${ERROR} 获取绝对路径失败"
    exit 1
  fi
}

detect_os() {
  if [ -f /etc/os-release ]; then
    source /etc/os-release
    case "$ID" in
      ubuntu) os='Ubuntu' ;;
      debian) os='Debian' ;;
      *)      return 2 ;;
    esac
  else
    return 2
  fi
}

enter_opendmarc_db() {
  echo -en "Enable the SQL features in OpenDMARC(y/n, default n): "
  read enable
  [ -z "${enable}" ] && enable='n'
}

enter_domains() {
  domains=()
  echo "Input trust domains (one per line), press Ctrl+D when done:"

  while read -r domain; do
    [[ -n "$domain" ]] && domains+=("$domain")
  done

  echo -e "${INFO} Received ${#domains[@]} domains."
}

install_opendmarc() {
  for packages in \
    dbconfig-no-thanks \
    opendmarc \
  ;
  do apt-get --no-install-recommends install -y $packages; done
  sleep 2
  systemctl stop opendmarc
}

genHosts() {
  echo '127.0.0.1' > /etc/opendmarc/ignore.hosts
  for domain in "${domains[@]}"; do
    echo $domain >> /etc/opendmarc/ignore.hosts
    trustedAuthservIDs="${trustedAuthservIDs},${domain}"
  done
}

configure_opendmarc() {
  cat /etc/opendmarc.conf > ${OpenDMARC_Parent_PATH}/conf-default/opendmarc.conf
  cat ${OpenDMARC_Parent_PATH}/conf/opendmarc.conf > /etc/opendmarc.conf
  mkdir -p /etc/opendmarc
  genHosts
  sed -i "s/^\(TrustedAuthservIDs HOSTNAME\)$/\1${trustedAuthservIDs}/g" /etc/opendmarc.conf
  mkdir -p /var/spool/postfix/opendmarc
  chown -R opendmarc:opendmarc /var/spool/postfix/opendmarc
  # chmod -R 770 /var/spool/postfix/opendmarc/
  usermod -aG opendmarc postfix

  systemctl start opendmarc
  systemctl status opendmarc | cat
}

print_reports_readme() {
  echo -e "Following \e[0;32mhttp://www.trusteddomain.org/opendmarc/reports-README\e[0m to enable opendmarc-reports."
}

install() {
  detect_os
  [ $? -ne 0 ] && {
    echo -e "${ERROR} Only support Ubuntu and Debian."
    exit 1
  }
  [ -z ${flag} ] && {
    enter_opendmarc_db
    enter_domains
  }
  determine_path
  install_opendmarc
  configure_opendmarc
  [ $enable = 'y' ] && print_reports_readme
}

VT_HOME="${HOME}/VT-Data"
VT_log="${VT_HOME}/logs"

[ ! -d "${VT_HOME}/" ] && mkdir ${VT_HOME}
[ ! -d "${VT_log}/" ] && mkdir ${VT_log}

[ $# -ne 0 ] && {
  flag="$1"
  shift
  domains=("$@")
  enable='n'
}

mkdir -p "${VT_log}/mail"
install 2>&1 | tee "${VT_log}/mail/opendmarc.log"
