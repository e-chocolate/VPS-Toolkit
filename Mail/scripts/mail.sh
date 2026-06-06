#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
# export DEBIAN_FRONTEND=noninteractive

# Check if user is root
if [ $(id -u) != "0" ]; then
  echo "Error: You must be root to run this script"
  exit 1
fi

INFO="\e[0;32m[INFO]\e[0m"
ERROR="\e[0;31m[ERROR]\e[0m"

determine_path() {
  Mail_Current_PATH="$(dirname $0)"

  if [[ "$Mail_Current_PATH" != /* ]]; then
    echo -e "${ERROR} ${Mail_Current_PATH} 不是绝对路径，尝试获取绝对路径"
    Mail_Current_PATH="$(pwd)/$(dirname $0)"
  fi

  if [[ "$Mail_Current_PATH" == /* ]] && [[ -n "$Mail_Current_PATH" ]]; then
    echo -e "${INFO} ${Mail_Current_PATH}"
  else
    echo -e "${ERROR} 获取绝对路径失败"
    exit 1
  fi
}

db=("mysql" "postgresql")

document() {
<<EOF
设计思路：
1. 用户输入 邮件域名 等基本信息
2. 安装 postfix
3. 安装 opendkim 和 opendmarc
4. 安装 dovecot
5. 启动 postfix 和 dovecot
EOF
}

print_version() {
  echo "+------------------------------------------------------------------------+"
  echo "|          VT-Mail for Debian like Linux, Written by Echocolate          |"
  echo "+------------------------------------------------------------------------+"
  echo "|               Scripts to install mail packages on Linux                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Version: 1.0.0  Last Updated: 2026-06-05                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                      https://repos.echocolate.xyz                      |"
  echo "+------------------------------------------------------------------------+"
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

choose_database() {
  echo -e "You have the following options for backend database."
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

enter_domains() {
  [ ! -z "${domains}" ] && return 0
  domains=()
  echo "Input domains (one per line), press Ctrl+D when done:"

  while read -r domain; do
    [[ -n "$domain" ]] && domains+=("$domain")
  done

  echo -e "${INFO} Received ${#domains[@]} domains."
}

add_user() {
  # groupadd -g 3000 vmail && useradd -g vmail -u 3000 vmail -d /var/mail/ -s /sbin/nologin
  id vmail && echo -e "${INFO} user vmail already exists." || {
    useradd -d /var/mail/ -r -s /sbin/nologin vmail
    echo -e "${INFO} user vmail created."
  }
}

check() {
  local services=('postfix' 'opendkim' 'opendmarc' 'dovecot')
  printf "\e[0;32m%-10s%-10s%-10s\e[0m\n" "Service" "Enabled" "Active"

  for service in "${services[@]}"; do
    systemctl is-enabled --quiet $service
    [ $? -eq 0 ] && enabled='Yes' || enabled='no'
    systemctl is-active --quiet $service
    [ $? -eq 0 ] && active='Yes' || active='no'
    printf "%-10s%-10s%-10s\n" "${service}" "${enabled}" "${active}"
  done
}

reminder() {
  if [ "${db_type}" = 'mysql' ]; then
    echo -e "Check the db examples in: \e[0;33m${Mail_Current_PATH}/../examples/mysql/\e[0m"
  elif [ "${db_type}" = 'pgsql' ]; then
    echo -e "Check the db examples in: \e[0;33m${Mail_Current_PATH}/../examples/postgresql/\e[0m"
  else
    echo -en ""
  fi
  echo -e "${INFO} Ensure that you have correctly configured the SPF, DFIM, and DMARC records in your DNS provider."
}

clear
print_version
detect_os
[ $? -ne 0 ] && {
  echo -e "${ERROR} Only support Ubuntu and Debian."
  exit 1
}
choose_database
enter_domains
echo -e "[Starting time: `date +'%Y-%m-%d %H:%M:%S'`]"
TIME_START=$(date +%s)
determine_path
add_user

"${Mail_Current_PATH}/postfix.sh" ${db_type} ${host} ${port} ${user} ${password} ${dbname}
[ $? -eq 0 ] && echo -e "${INFO} postfix 安装成功."

"${Mail_Current_PATH}/opendkim.sh" "VT" "${domains[@]}"
[ $? -eq 0 ] && echo -e "${INFO} opendkim 安装成功."

"${Mail_Current_PATH}/opendmarc.sh" "VT" "${domains[@]}"
[ $? -eq 0 ] && echo -e "${INFO} opendmarc 安装成功."

"${Mail_Current_PATH}/dovecot.sh" ${db_type} ${host} ${port} ${user} ${password} ${dbname} "${domains[@]}"
[ $? -eq 0 ] && echo -e "${INFO} dovecot 安装成功."

systemctl start postfix
echo -e "[End time: `date +'%Y-%m-%d %H:%M:%S'`]"
TIME_END=$(date +%s)
echo -e "Command takes $((TIME_END-TIME_START)) seconds."
check
reminder
