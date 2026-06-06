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
  Dovecot_Parent_PATH="$(dirname $0)/.."

  if [[ "$Dovecot_Parent_PATH" != /* ]]; then
    echo -e "${ERROR} ${Dovecot_Parent_PATH} 不是绝对路径，尝试获取绝对路径"
    Dovecot_Parent_PATH="$(pwd)/$(dirname $0)/.."
  fi

  if [[ "$Dovecot_Parent_PATH" == /* ]] && [[ -n "$Dovecot_Parent_PATH" ]]; then
    echo -e "${INFO} ${Dovecot_Parent_PATH}"
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

db=("mysql" "postgresql")
db_packages=("dovecot-mysql" "dovecot-pgsql")

enter_domains() {
  domains=()
  echo "Input domains (one per line), press Ctrl+D when done:"

  while read -r domain; do
    [[ -n "$domain" ]] && domains+=("$domain")
  done

  echo -e "${INFO} Received ${#domains[@]} domains."
}

choose_database() {
  echo -e "You have the following options for lookup tables."
  for ((i=0; i<${#db[@]}; i++)); do
    echo -e "\e[0;32m$((i+1))\e[0m: ${db[i]}"
  done
  echo -en "Enter your choice(default 1): "
  read -r db_select
  if [[ ! "$db_select" =~ ^[0-9]+$ ]] || [ "$db_select" -lt 1 ] || [ "$db_select" -gt "$i" ]; then
    echo -e "\e[0;31mInvalid choice\e[0m, default 1"
    db_select=1
  fi
  if [ ${db[$((db_select-1))]} = 'mysql' ]; then
    db_type='mysql'
  elif [ ${db[$((db_select-1))]} = 'postgresql' ]; then
    db_type='pgsql'
  else
    db_type='none'
  fi
  enter_db_prameters
}

enter_db_prameters() {
  echo -en "\e[0;33mEnter the host(Default 127.0.0.1): \e[0m"
  read -r host
  [ -z "${host}" ] && host='127.0.0.1'
  if [ "${db_type}" = 'mysql' ]; then
    enter_db_port "3306"
  elif [ "${db_type}" = 'pgsql' ]; then
    enter_db_port "5432"
    db_type='pgsql'
  else
 echo -en "" # PASS
  fi
  echo -en "\e[0;33mEnter the username: \e[0m"
  read -r user
  echo -en "\e[0;33mEnter the password: \e[0m"
  read -r password
  echo -en "\e[0;33mEnter the dbname: \e[0m"
  read -r dbname
}

enter_db_port() {
  echo -en "\e[0;33mEnter the port(Default $1): \e[0m"
  read -r port
  [ -z ${port} ] && port=$1
}

install_dovecot() {
  for packages in \
    dovecot-core \
    dovecot-imapd \
    dovecot-pop3d \
    dovecot-lmtpd \
    "dovecot-${db_type}" \
  ;
  do apt-get --no-install-recommends install -y $packages; done
  sleep 2
  systemctl stop dovecot
}

add_user() {
  # groupadd -g 3000 vmail && useradd -g vmail -u 3000 vmail -d /var/mail/ -s /sbin/nologin
  id vmail && echo -e "${INFO} user vmail already exists." || {
    useradd -d /var/mail/ -r -s /sbin/nologin vmail
    echo -e "${INFO} user vmail created."
  }
}

create_mail_dir() {
  # 设置邮件存储路径
  for domain in "${domains[@]}"; do
    mkdir -p "/var/mail/vhosts/${domain}"
  done
  chown -R vmail:vmail /var/mail/vhosts
}

configure_dovecot() {
  local dovecot_conf_path='/etc/dovecot'

  for file in $(ls "${dovecot_conf_path}"); do
    [ -f "${dovecot_conf_path}/${file}" ] && cat "${dovecot_conf_path}/${file}" > "${Dovecot_Parent_PATH}/conf-default/dovecot/${file}"
  done

  for file in $(ls "${Dovecot_Parent_PATH}/conf/dovecot"); do
    [ -f "${Dovecot_Parent_PATH}/conf/dovecot/${file}" ] && cat "${Dovecot_Parent_PATH}/conf/dovecot/${file}" > "${dovecot_conf_path}/${file}"
  done

  for file in $(ls "${dovecot_conf_path}/conf.d"); do
    [ -f "${dovecot_conf_path}/conf.d/${file}" ] && cat "${dovecot_conf_path}/conf.d/${file}" > "${Dovecot_Parent_PATH}/conf-default/dovecot/conf.d/${file}"
  done

  for file in $(ls "${Dovecot_Parent_PATH}/conf/dovecot/conf.d"); do
    [ -f "${Dovecot_Parent_PATH}/conf/dovecot/conf.d/${file}" ] && cat "${Dovecot_Parent_PATH}/conf/dovecot/conf.d/${file}" > "${dovecot_conf_path}/conf.d/${file}"
  done

  sed -i "s|driver = {driver}|driver = ${db_type}|g" "${dovecot_conf_path}/dovecot-sql.conf.ext"
  sed -i "s|connect = host={host} port={port} dbname={dbname} user={user} password={password} connect_timeout=10|connect = host=${host} port=${port} dbname=${dbname} user=${user} password=${password} connect_timeout=10|g" "${dovecot_conf_path}/dovecot-sql.conf.ext"
  chown -R vmail:dovecot /etc/dovecot
  chmod -R o-rwx /etc/dovecot
  create_mail_dir
  systemctl start dovecot
}

install() {
  detect_os
  [ $? -ne 0 ] && {
    echo -e "${ERROR} Only support Ubuntu and Debian."
    exit 1
  }
  [ -z ${db_type} ] && {
    enter_domains
    choose_database
  }
  install_dovecot
  determine_path
  add_user
  configure_dovecot
}

[ $# -ge 6 ] && {
  db_type="$1"
  host="$2"
  port="$3"
  user="$4"
  password="$5"
  dbname="$6"

  shift 6
  domains=("$@")
}

VT_HOME="${HOME}/VT-Data"
VT_log="${VT_HOME}/logs"

[ ! -d "${VT_HOME}/" ] && mkdir ${VT_HOME}
[ ! -d "${VT_log}/" ] && mkdir ${VT_log}

mkdir -p "${VT_log}/mail"
install 2>&1 | tee "${VT_log}/mail/dovecot.log"
