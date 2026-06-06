#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# Check if user is root
if [ $(id -u) != "0" ]; then
  echo "Error: You must be root to run this script"
  exit 1
fi

INFO="\e[0;32m[INFO]\e[0m"
ERROR="\e[0;31m[ERROR]\e[0m"

determine_path() {
  DKIM_Parent_PATH="$(dirname $0)/.."

  if [[ "$DKIM_Parent_PATH" != /* ]]; then
    echo -e "${ERROR} ${DKIM_Parent_PATH} 不是绝对路径，尝试获取绝对路径"
    DKIM_Parent_PATH="$(pwd)/$(dirname $0)/.."
  fi

  if [[ "$DKIM_Parent_PATH" == /* ]] && [[ -n "$DKIM_Parent_PATH" ]]; then
    echo -e "${INFO} ${DKIM_Parent_PATH}"
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

enter_domains() {
  [ ! -z "${domains}" ] && return 0
  domains=()
  echo "Input domains (one per line), press Ctrl+D when done:"

  while read -r domain; do
    [[ -n "$domain" ]] && domains+=("$domain")
  done

  echo -e "${INFO} Received ${#domains[@]} domains."
}

install_opendkim() {
  for packages in \
    opendkim opendkim-tools \
  ;
  do apt-get --no-install-recommends install -y $packages; done
  mkdir -p /etc/opendkim/keys
  \cp -a /etc/opendkim.conf /etc/opendkim.conf.bk
  cat /dev/null > /etc/opendkim/key.table
  cat /dev/null > /etc/opendkim/signing.table
  cat > /etc/opendkim/trusted.hosts <<EOF
127.0.0.1
localhost

EOF
}

set_domain_table() {
  printf "%-40s%s\n" "default._domainkey.$1" "$1:default:/etc/opendkim/keys/$1/default.private" >> /etc/opendkim/key.table
  printf "%-24s%s\n" "*@$1" "default._domainkey.$1" >> /etc/opendkim/signing.table
  echo "*.$1" >> /etc/opendkim/trusted.hosts
}

genkey() {
  mkdir -p /etc/opendkim/keys/$1
  opendkim-genkey -s default -d $1 -D /etc/opendkim/keys/$1 -v
  chown opendkim:opendkim /etc/opendkim/keys/$1/default.private
  chmod 600 /etc/opendkim/keys/$1/default.private
}

reminder() {
  echo -e 'Add the DNS TXT record to dns provider first. Then use the following command to check:'
  for domain in "${domains[@]}"; do
    echo -e "  opendkim-testkey -d ${domain} -s default -vvv"
  done
}

set_keys() {
  for domain in "${domains[@]}"; do
    set_domain_table "$domain"
    genkey "$domain"
  done
  chown -R opendkim:opendkim /etc/opendkim/keys
}

conf_MTA() {
  cat /etc/opendkim.conf > "${DKIM_Parent_PATH}/conf-default/opendkim.conf"
  cat "${DKIM_Parent_PATH}/conf/opendkim.conf" > /etc/opendkim.conf
  mkdir -p /var/spool/postfix/opendkim
  chown -R opendkim:opendkim /var/spool/postfix/opendkim
  usermod -aG opendkim postfix
}

check_status() {
  systemctl restart opendkim
  sleep 3
  systemctl is-active --quiet opendkim
  [ $? -eq 0 ] && echo -e "${INFO} opendkim is running." || echo -e "${ERROR} opendkim failed to start."
}

install() {
  detect_os
  [ $? -ne 0 ] && {
    echo -e "${ERROR} Only support Ubuntu and Debian."
    exit 1
  }
  [ -z ${flag} ] && enter_domains
  determine_path
  install_opendkim
  set_keys
  conf_MTA
  check_status
  echo "-------------------------------------------done------------------------------------------"
  echo -e "Check \e[0;32mpublic key\e[0m and \e[0;32mDNS TXT record\e[0m in '/etc/opendkim/keys/'"
  reminder
}

VT_HOME="${HOME}/VT-Data"
VT_log="${VT_HOME}/logs"

[ ! -d "${VT_HOME}/" ] && mkdir ${VT_HOME}
[ ! -d "${VT_log}/" ] && mkdir ${VT_log}

[ $# -ne 0 ] && {
  flag="$1"
  shift
  domains=("$@")
}

mkdir -p "${VT_log}/mail"
install 2>&1 | tee "${VT_log}/mail/opendkim.log"
