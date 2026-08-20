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
  echo "|       VT-PostgreSQL for Debian like Linux, Written by Echocolate       |"
  echo "+------------------------------------------------------------------------+"
  echo "|                A script to install PostgreSQL on Linux                 |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Version: 1.0.0  Last Updated: 2026-08-20                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                      https://repos.echocolate.xyz                      |"
  echo "+------------------------------------------------------------------------+"
  sleep 2
}

determine_path() {
  PostgreSQL_Parent_PATH="$(dirname $0)/.."

  if [[ "$PostgreSQL_Parent_PATH" != /* ]]; then
    echo -e "${ERROR} ${PostgreSQL_Parent_PATH} 不是绝对路径，尝试获取绝对路径"
    PostgreSQL_Parent_PATH="$(pwd)/$(dirname $0)/.."
  fi

  if [[ "$PostgreSQL_Parent_PATH" == /* ]] && [[ -n "$PostgreSQL_Parent_PATH" ]]; then
    echo -e "${INFO} ${PostgreSQL_Parent_PATH}"
  else
    echo -e "${ERROR} 获取绝对路径失败"
    exit 1
  fi
}

enter_version() {
  version=$(apt-cache show postgresql | grep -i 'version:' | sed -e 's/Version: \?//g' | head -n 1)
  echo -e "The dedault postgresql version for your os is: \e[0;33m${version}\e[0m"
  sleep 1
  while :;do
    echo -en "Please input the version of postgresql that you want to install: (16, 17, 18): "
    read diy_version
    if [[ "${diy_version}" =~ ^1[6,7,8]$ ]]; then
      break
    else
      echo -e "\e[0;31mOnly support (16, 17, 18)!\e[0m"
    fi
  done
}

enter_password() {
  echo -en "\e[0;33mPlease setup password for user<postgres>: \e[0m"
  read DB_Admin_Password
  if [ -z ${DB_Admin_Password} ] || [ "${DB_Admin_Password}" = "" ]; then
    echo "NO input,password will be generated randomly."
    DB_Admin_Password=$(tr -dc 'A-Za-z0-9@#%()_+-=' < /dev/urandom | head -c 16)
  fi
}

print_choose_array() {
  local -a arr=("$@")  # 将所有参数存入新数组
  for i in "${!arr[@]}"; do
    if [ "$i" -eq 0 ]; then
      desc="${arr[i]}"
      echo "index | ${desc}"
      echo "------+------------------"
    else
      printf "%-5s | %s\n" "$i" "${arr[i]}"
    fi
  done
  echo -en "Enter the ${desc}(deafault 1): "
  read index
  [ -z ${index} ] && index=1
  if (( index >= 1 && index < ${#arr[@]} )); then
    echo "You choose ${arr[index]}"
  else
    index=1
    echo -e "${ERROR} Invalid index, choose ${arr[1]}"
  fi
  ((index--))
}

enter_parameters() {
  dbVersion=${diy_version}

  local db_type_detail=("Web application" "Online transaction processing system" "Data warehouse" "Desktop application" "Mixed type of application")
  local db_type_abbr=("web" "oltp" "dw" "desktop" "mixed")
  print_choose_array "database type" "${db_type_detail[@]}"
  dbType=${db_type_abbr[${index}]}

  totalMemory=$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)
  echo -en "How much memory can PostgreSQL use (deafault ${totalMemory}): "
  read totalMemory
  [ -z ${totalMemory} ] && totalMemory=$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)

  cpuNum=$(grep -c "^processor" /proc/cpuinfo)
  echo -en "Enter the number of CPUs that PostgreSQL can use(deafault ${cpuNum}): "
  read cpuNum
  [ -z ${cpuNum} ] && cpuNum=$(grep -c "^processor" /proc/cpuinfo)

  echo -en "Enter the maximum number of PostgreSQL client connections(deafult 100): "
  read connectionNum
  [ -z ${connectionNum} ] && connectionNum=100

  local data_storage_detail=("SSD storage" "Network (SAN) storage" "HDD storage")
  local data_storage_abbr=("ssd" "san" "hdd")
  print_choose_array "data storage type" "${data_storage_detail[@]}"
  hdType=${data_storage_abbr[${index}]}
  configs=$(curl -sSf "${pgtune_url}/?\
dbVersion=${dbVersion}&\
dbType=${dbType}&\
cpuNum=${cpuNum}&\
totalMemory=${totalMemory}&\
connectionNum=${connectionNum}&\
hdType=${hdType}")
  [ $? -eq 0 ] && enable_config='y' || enable_config='n'
}

enter_pgvector() {
  echo -en "Enable pgvector extension(y/n, default n): "
  read -n1 pgvector
  echo ""
}

enter_replication() {
  echo -en "Enable Streaming replication(y/n, default n): "
  read -n1 replication
  echo ""
  [ "${replication}" = 'y' ] && {
    enter_listen_addresses
    enter_standby_ip
  }
}

enter_listen_addresses() {
  while :;do
    echo -n "Which ip postgresql will listen(default localhost): "
    read listen_addresses
    [ -z "${listen_addresses}" ] && listen_addresses='127.0.0.1'
    Check_IPv4 "${listen_addresses}" && break || echo -e "${ERROR} Invalid IPv4 address."
  done
}

enter_standby_ip() {
  while :;do
    echo -n "Which host will you use to as Standby Replication(default localhost): "
    read standby_host
    [ -z "${standby_host}" ] && standby_host='127.0.0.1'
    Check_IPv4 "${standby_host}" && break || echo -e "${ERROR} Invalid IPv4 address."
  done
}

Check_IPv4() {
  local IP=$1
  # 判断标准为 0 <= $i <= 255 且不能有前导0
  echo "${IP}" | awk -F. '{
    # 字段数必须为4
    if (NF != 4) exit(1);
    for (i = 1; i <= NF; i++) {
      if ($i !~ /^[0-9]{1,3}$/) exit(1);
      if (length($i) > 1 && $i ~ /^0/) exit(1);
      if ($i < 0 || $i > 255) exit(1);
    }
  }'
  return $?
}

install_stop_pg() {
  apt-get --no-install-recommends install -y jq
  if [ `echo ${version} | grep "${diy_version}"` ]; then
    echo -e "${INFO} Install version: ${diy_version}(default)"
    apt-get --no-install-recommends install -y postgresql
  else
    echo -e "${INFO} Install version: ${diy_version}"
    apt-get --no-install-recommends install -y postgresql-common
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
    apt-get --no-install-recommends install -y postgresql-${diy_version}
  fi
  [ "${pgvector}" = 'y' ] && apt-get --no-install-recommends install -y postgresql-${diy_version}-pgvector
  sleep 10
  systemctl stop postgresql
  \cp -a /etc/postgresql/${diy_version}/main/postgresql.conf /etc/postgresql/${diy_version}/main/postgresql.conf.bk
  \cp -a /etc/postgresql/${diy_version}/main/pg_hba.conf     /etc/postgresql/${diy_version}/main/pg_hba.conf.bk
}

optimize() {

  cat > /etc/security/limits.d/01-postgresql.conf <<EOF
# postgres
postgres soft nofile 65535
postgres hard nofile 65536
postgres soft nproc 65535
postgres hard nproc 65536
EOF
  # optimize_pam_limits "postgres soft nofile" "65535"

  # 优化pg运行参数，根据用户输入的 DB 分配信息，以最佳的配置更新配置文件
  if [ "${enable_config}" = 'y' ]; then
    echo -e "${INFO} Configuring postgresql with recommend parameters..."
    for key in $(echo $configs | jq -r 'keys[]'); do
      value=$(echo $configs | jq -r ".$key")
      configure_pg $key $value
    done
   else
    echo -e "${INFO} Configuring postgresql with default parameters..."
  fi
}

optimize_pam_limits() {
  # [Deprecated]
  if grep -qE "$1" /etc/security/limits.conf; then
    sed -i "s|^$1.*|$1 $2|g" /etc/security/limits.conf
  else
    echo "$1 $2" >> /etc/security/limits.conf
  fi
}

configure_pg() {
  # 如果在文件中找到则替换；找不到则新增一行
  if grep -qE "^#?$1" /etc/postgresql/${diy_version}/main/postgresql.conf; then
    sed -i "s|^#\{0,1\}\($1 .*\)|#\1\n$1 = $2|g" /etc/postgresql/${diy_version}/main/postgresql.conf
  else
    echo "$1 = $2" >> /etc/postgresql/${diy_version}/main/postgresql.conf
  fi
}

confssl() {
  echo -e "${INFO} Default enable ssl. Nothing need to do..."
}

enable_replication() {
  # 配置主从复制的主库
  sed -i "s|^#\{0,1\}\(listen_addresses.*\)|listen_addresses = 'localhost,$listen_addresses'\n#\1|g" /etc/postgresql/${diy_version}/main/postgresql.conf
  sed -i "s|^#\{0,1\}\(wal_level.*\)|#\1\nwal_level = replica|g" /etc/postgresql/${diy_version}/main/postgresql.conf
  sed -i "s|^#\{0,1\}\(max_wal_senders.*\)|#\1\nmax_wal_senders = 10|g" /etc/postgresql/${diy_version}/main/postgresql.conf
  sed -i "s|^#\{0,1\}\(max_replication_slots.*\)|#\1\nmax_replication_slots = 5|g" /etc/postgresql/${diy_version}/main/postgresql.conf
  sed -i "s|^#\{0,1\}\(wal_keep_size.*\)|#\1\nwal_keep_size = 2GB|g" /etc/postgresql/${diy_version}/main/postgresql.conf
  printf "%-8s%-16s%-16s%-24s%s\n" 'hostssl' 'replication' 'standby' "${standby_host}/32" 'scram-sha-256' >> /etc/postgresql/${diy_version}/main/pg_hba.conf
}

set_pgvector() {
  local n=$(($(ls -a /tmp/ | grep -E ".pg.tmp" | sed 's/\.pg\.tmp//g' | sort -nr | head -n 1) + 1))
  cat > /tmp/.pg.tmp${n} <<EOF
-- 启用 pgvector
CREATE EXTENSION vector;
EOF
  sudo -i -u postgres psql -tf /tmp/.pg.tmp${n}
  sleep 2
}

set_replication_user() {
  replication_pd=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c 16)
  local n=$(($(ls -a /tmp/ | grep -E ".pg.tmp" | sed 's/\.pg\.tmp//g' | sort -nr | head -n 1) + 1))
  cat > /tmp/.pg.tmp${n} <<EOF
-- 创建复制用户
CREATE USER standby REPLICATION LOGIN ENCRYPTED PASSWORD '${replication_pd}';
-- 创建复制槽
SELECT pg_create_physical_replication_slot('standby1_slot');
SELECT pg_reload_conf();
EOF
  sudo -i -u postgres psql -tf /tmp/.pg.tmp${n}
  sleep 2
}

set_passwd() {
  local n=$(($(ls -a /tmp/ | grep -E ".pg.tmp" | sed 's/\.pg\.tmp//g' | sort -nr | head -n 1) + 1))
  cat > /tmp/.pg.tmp${n} <<EOF
-- 修改管理员密码
ALTER USER postgres PASSWORD '${DB_Admin_Password}';
SELECT pg_reload_conf();
EOF
  sudo -i -u postgres psql -tf /tmp/.pg.tmp${n}
  sleep 2
}

revoke_template1_public_schema() {
  local n=$(($(ls -a /tmp/ | grep -E ".pg.tmp" | sed 's/\.pg\.tmp//g' | sort -nr | head -n 1) + 1))
  cat > /tmp/.pg.tmp${n} <<EOF
-- 连接模板数据库1
\c template1
-- 取消默认的public对任何用户的权限
revoke all on schema public from public;
SELECT pg_reload_conf();
EOF
  sudo -i -u postgres psql -tf /tmp/.pg.tmp${n}
  sleep 2
}

reminder() {
  echo "SHOW listen_addresses;" > /tmp/.pg.tmp
  address=$(sudo -i -u postgres psql -tf /tmp/.pg.tmp)
  rm -f /tmp/.pg.tmp*
  echo -e "postgres password: \e[0;32m${DB_Admin_Password}\e[0m"
  echo -e "listen addresses: \e[0;32m${address}\e[0m"
  if [ "${replication}" = 'y' ]; then
    echo -e "\e[0;33mREPLICATION INFO as follows \e[0m:"
    echo -e "\e[0;32m  Username \e[0m: standby"
    echo -e "\e[0;32m  Password \e[0m: ${replication_pd}"
    echo -e "\e[0;32m  primary_slot_name \e[0m: standby1_slot"
  fi
  cat /etc/postgresql/${diy_version}/main/postgresql.conf > "${PostgreSQL_Parent_PATH}/conf/postgresql/postgresql.conf"
  cat /etc/postgresql/${diy_version}/main/pg_hba.conf > "${PostgreSQL_Parent_PATH}/conf/postgresql/pg_hba.conf"
}

install() {
  print_version
  enter_version
  enter_password
  enter_parameters
  enter_pgvector
  enter_replication
  determine_path
  install_stop_pg
  optimize
  confssl
  [ "${replication}" = 'y' ] && enable_replication
  systemctl start postgresql
  sleep 5
  [ "${pgvector}" = 'y' ] && set_pgvector
  [ "${replication}" = 'y' ] && set_replication_user
  set_passwd
  revoke_template1_public_schema
  reminder
}

VT_HOME="${HOME}/VT-Data"
VT_log="${VT_HOME}/logs"

[ ! -d "${VT_HOME}/" ] && mkdir ${VT_HOME}
[ ! -d "${VT_log}/" ] && mkdir ${VT_log}

pgtune_url="https://damp-feather-a1a6.echocolate.workers.dev"

install 2>&1 | tee "${VT_log}/postgresql.log"
