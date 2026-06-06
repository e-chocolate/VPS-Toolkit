#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export DEBIAN_FRONTEND=noninteractive

# Check if user is root
if [ $(id -u) != "0" ]; then
  echo "Error: You must be root to run this script"
  exit 1
fi

INFO="\e[0;32m[INFO]\e[0m"
ERROR="\e[0;31m[ERROR]\e[0m"

detect_os() {
  if [ -f /etc/os-release ]; then
    source /etc/os-release
    case "$ID" in
      ubuntu) os='Ubuntu' ;;
      debian) os='Debian/GNU' ;;
      *)      return 2 ;;
    esac
  else
    return 2
  fi
}

determine_path() {
  Postfix_Parent_PATH="$(dirname $0)/.."

  if [[ "$Postfix_Parent_PATH" != /* ]]; then
    echo -e "${ERROR} ${Postfix_Parent_PATH} 不是绝对路径，尝试获取绝对路径"
    Postfix_Parent_PATH="$(pwd)/$(dirname $0)/.."
  fi

  if [[ "$Postfix_Parent_PATH" == /* ]] && [[ -n "$Postfix_Parent_PATH" ]]; then
    echo -e "${INFO} ${Postfix_Parent_PATH}"
  else
    echo -e "${ERROR} 获取绝对路径失败"
    exit 1
  fi
}

db=("mysql" "postgresql")
db_packages=("postfix-mysql" "postfix-pgsql")

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

sleep_stop() {
  [ -z $1 ] && local t=3 || local t=$1
  sleep $t
  systemctl stop postfix
}

sleep_start() {
  [ -z $1 ] && local t=3 || local t=$1
  sleep $t
  systemctl start postfix
}

install_postfix() {
  for packages in \
    postfix \
    postfix-doc \
    postfix-policyd-spf-python \
    "postfix-${db_type}" \
  ;
  do apt-get --no-install-recommends install -y $packages; done
}

db_lookups() {
  base_db_info=$(cat <<EOF
hosts = ${host}:${port}
user = ${user}
password = ${password}
dbname = ${dbname}
EOF
  )
  common_lookups "${db_type}"
  if [ "${db_type}" = 'mysql' ]; then
    mysql_lookups
  elif [ "${db_type}" = 'pgsql' ]; then
    postgresql_lookups
  else
    echo -en "" # PASS
  fi
}

common_lookups() {
  cat > "/etc/postfix/$1-virtual-mailbox-domains.cf" <<EOF
$base_db_info
query = SELECT 1 FROM virtual_domains WHERE name='%s';
EOF

  cat > "/etc/postfix/$1-virtual-mailbox-maps.cf" <<EOF
$base_db_info
query = SELECT 1 FROM virtual_users WHERE email='%s';
EOF
}

mysql_lookups() {
  cat > /etc/postfix/mysql-virtual-alias-maps.cf <<EOF
$base_db_info
query = SELECT destination
        FROM virtual_aliases
        WHERE source=concat(
          REGEXP_REPLACE(REGEXP_SUBSTR('%s', '^(.*)@'),  '\\+[A-Za-z]{2,}@', ''),
          REGEXP_SUBSTR('%s', '@(.*)$')
        );
EOF
}

postgresql_lookups() {
  cat > "/etc/postfix/pgsql-virtual-alias-maps.cf" <<EOF
$base_db_info
query = SELECT destination
        FROM virtual_aliases
        WHERE source=regexp_replace(substring('%s' FROM '^(.*)@'), '\+[A-Za-z][A-Za-z]', '', 'g') ||
                     '@' ||
                     substring('%s' FROM '^.*@(.*)')
        ;
EOF
}

getFQDN() {
  fqdn=$(hostname -f)
  [ $? -eq 0 ] && fqdn=$(echo "${fqdn}" | sed 's|mail\.||g') || return 1
}

configure_postfix() {
  db_lookups
  cat /etc/postfix/main.cf > ${Postfix_Parent_PATH}/conf-default/postfix/main.cf
  cat /etc/postfix/master.cf > ${Postfix_Parent_PATH}/conf-default/postfix/master.cf
  cat "${Postfix_Parent_PATH}/conf/postfix/main.cf" > /etc/postfix/main.cf
  cat "${Postfix_Parent_PATH}/conf/postfix/master.cf" > /etc/postfix/master.cf
  sed -i "s/{OS}/${os}/g" /etc/postfix/main.cf
  sed -i "s|virtual_mailbox_domains =.*|virtual_mailbox_domains = ${db_type}:/etc/postfix/${db_type}-virtual-mailbox-domains.cf|g" /etc/postfix/main.cf
  sed -i "s|virtual_mailbox_maps =.*|virtual_mailbox_maps = ${db_type}:/etc/postfix/${db_type}-virtual-mailbox-maps.cf|g" /etc/postfix/main.cf
  sed -i "s|virtual_alias_maps =.*|virtual_alias_maps = ${db_type}:/etc/postfix/${db_type}-virtual-alias-maps.cf|g" /etc/postfix/main.cf
  getFQDN
  [ $? -eq 0 ] && sed -i "s|example\.org|$fqdn|g" /etc/postfix/main.cf || {
    echo -e "${ERROR} Cannot determin FQDN, using postfix default config."
    cat ${Postfix_Parent_PATH}/conf-default/postfix/main.cf > /etc/postfix/main.cf
    cat ${Postfix_Parent_PATH}/conf-default/postfix/master.cf > /etc/postfix/master.cf
  }
  chmod -R o-rwx /etc/postfix
}

install() {
  [ -z ${db_type} ] && {
    choose_database
    echo -e "${INFO} Ensure that you have configured the database, opendkim, opendmarc, dovecot before starting postfix."
    read -p $'\e[0;33mStart postfix immediately (y/n, default n): \e[0m' -n1 start_now
  }
  determine_path
  detect_os
  [ $? -ne 0 ] && {
    echo -e "${ERROR} Only support Ubuntu and Debian."
    exit 1
  }
  install_postfix
  sleep_stop 3
  configure_postfix
  [ "${start_now}" = "y" ] && sleep_start 3
}

[ $# -eq 6 ] && {
  db_type="$1"
  host="$2"
  port="$3"
  user="$4"
  password="$5"
  dbname="$6"
}

VT_HOME="${HOME}/VT-Data"
VT_log="${VT_HOME}/logs"

[ ! -d "${VT_HOME}/" ] && mkdir ${VT_HOME}
[ ! -d "${VT_log}/" ] && mkdir ${VT_log}

mkdir -p "${VT_log}/mail"
install 2>&1 | tee "${VT_log}/mail/postfix.log"
