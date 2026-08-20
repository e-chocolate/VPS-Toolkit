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
  echo "|         VT-Redis for Debian like Linux, Written by Echocolate          |"
  echo "+------------------------------------------------------------------------+"
  echo "|                 A script to install the redis on Linux                 |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Version: 1.0.2  Last Updated: 2026-08-20                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                      https://repos.echocolate.xyz                      |"
  echo "+------------------------------------------------------------------------+"
  sleep 2
}

determine_path() {
  Redis_Parent_PATH="$(dirname $0)/.."

  if [[ "$Redis_Parent_PATH" != /* ]]; then
    echo -e "${ERROR} ${Redis_Parent_PATH} 不是绝对路径，尝试获取绝对路径"
    Redis_Parent_PATH="$(pwd)/$(dirname $0)/.."
  fi

  if [[ "$Redis_Parent_PATH" == /* ]] && [[ -n "$Redis_Parent_PATH" ]]; then
    echo -e "${INFO} ${Redis_Parent_PATH}"
  else
    echo -e "${ERROR} 获取绝对路径失败"
    exit 1
  fi
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
  sleep 5
  echo -e $version
}

check_VT_INIT() {
  [ ! -f "${VT_log}/VT_INIT_FLAG" ] && return 0
  return 1
}

init() {
  apt-get update
  apt-get install -y sudo
  for packages in \
          ca-certificates \
          wget \
          dpkg-dev \
          gcc \
          g++ \
          libc6-dev \
          libssl-dev \
          make \
          git \
          cmake \
          python3 \
          python3-pip \
          python3-venv \
          python3-dev \
          unzip \
          rsync \
          clang \
          automake \
          autoconf \
          libtool \
  ;
  do apt-get --no-install-recommends install -y $packages; done
}

enter_overcommit() {
  echo -e "Redis need to enable overcommit_memory, or redis background save and replication may fail under low memory condition.\nMore info see https://github.com/jemalloc/jemalloc/issues/1328."
  echo -en "\e[0;33mEnable always overcommit memory(y/n, default y): \e[0m"
  read -n1 overcommit_memory
  echo
  [ "${overcommit_memory}" != 'n' ] && check_overcommit
}

check_overcommit() {
  if grep -qE "vm.overcommit_memory.*=.*1" /etc/sysctl.conf; then
    echo -e "${INFO} Already enabled overcommit memory..."
  else
    echo -e "\n# Redis\nvm.overcommit_memory = 1" >> /etc/sysctl.conf
    sysctl -p
  fi
}

enter_unix_socket() {
  echo -en "\e[0;33mListen on a unix socket(y/n, deafult n): \e[0m"
  read -n1 enable_unix_socket
  echo
}

install_llvm() {
  LLVM_version="${LLVM_ver:-}"
  [ -z ${LLVM_version} ] && {
    echo -e "${INFO} No need to install/update LLVM."
    return 0
  }
  apt-get update
  for packages in \
    lsb-release \
    wget \
    software-properties-common \
    gnupg \
  ;
  do apt-get --no-install-recommends install -y $packages; done
  # Using the LLVM repository setup script
  bash <(curl -L https://apt.llvm.org/llvm.sh) "${LLVM_version}"
  [ $? -ne 0 ] && {
    echo -e "${ERROR} Failed to install LLVM."
    exit 1
  }
}

export_make_env() {
  export CC=$(which gcc)
  export CXX=$(which g++)

  export AR=$(which gcc-ar)
  export RANLIB=$(which gcc-ranlib)

  export CMAKE_C_COMPILER_AR=$(which gcc-ar)
  export CMAKE_CXX_COMPILER_AR=$(which gcc-ar)
  export CMAKE_C_COMPILER_RANLIB=$(which gcc-ranlib)
  export CMAKE_CXX_COMPILER_RANLIB=$(which gcc-ranlib)
}

add_user() {
  if id redis >/dev/null 2>&1; then
    echo -e "${INFO} User redis already exists."
  else
    if getent group redis &>/dev/null; then
      useradd -r -g redis -s /sbin/nologin -d "${Redis_Persistence}" -M redis 
    else
      useradd -r -s /sbin/nologin -d "${Redis_Persistence}" -M redis
    fi
  fi
  [ ! -d "${Redis_Persistence}" ] && mkdir -p "${Redis_Persistence}"
}

make_redis() {
  apt-get --no-install-recommends install -y libsystemd-dev
  cd "${VT_download}"
  echo "Build Redis from source..."
  local redis_version="${redis_ver:-$(get_github_latest 'redis/redis')}"
  wget -c -nv https://github.com/redis/redis/archive/refs/tags/${redis_version}.tar.gz -O redis.tar.gz
  if [ $? -ne 0 ]; then
    echo -e "${ERROR} Download Redis failed."
    exit 1
  fi

  cd "${VT_build}"
  rm -rf redis && mkdir redis
  tar zxf "${VT_download}/redis.tar.gz" --strip-components=1 --directory=redis

  cd redis
  export BUILD_TLS=yes
  export BUILD_WITH_MODULES=yes
  export INSTALL_RUST_TOOLCHAIN=yes
  export DISABLE_WERRORS=yes

  # export_make_env
  make -j `grep 'processor' /proc/cpuinfo | wc -l` all USE_SYSTEMD=yes
  make PREFIX=/usr/local/redis install
  mkdir -p "${Redis_HOME}/etc/"
  mkdir -p "${Redis_Persistence}"/modules/{redisbloom,redisearch,redisjson,redistimeseries}
  \cp redis.conf "${Redis_HOME}/etc/"
  [ -f 'redis-full.conf' ] && \cp redis-full.conf "${Redis_HOME}/etc/"
  chmod 644 "${Redis_HOME}/etc/"*.conf

  [[ -f './modules/redisbloom/redisbloom.so' ]] && cp -a ./modules/redisbloom/redisbloom.so  "${Redis_Persistence}/modules/redisbloom/redisbloom.so"
  [[ -f './modules/redisearch/redisearch.so' ]] && cp -a ./modules/redisearch/redisearch.so "${Redis_Persistence}/modules/redisearch/redisearch.so"
  [[ -f './modules/redisjson/rejson.so' ]] && cp -a ./modules/redisjson/rejson.so "${Redis_Persistence}/modules/redisjson/rejson.so"
  [[ -f './modules/redistimeseries/redistimeseries.so' ]] && cp -a ./modules/redistimeseries/redistimeseries.so "${Redis_Persistence}/modules/redistimeseries/redistimeseries.so"

  sed -i 's|\(^pidfile /var/run/redis_6379.pid\)|# \1\npidfile /run/redis/redis.pid|g' "${Redis_HOME}/etc/redis.conf"
  sed -i 's|\(^# supervised.*\)|\1\nsupervised systemd|g' "${Redis_HOME}/etc/redis.conf"
  sed -i "s|\(^dir.*\)|# \1\n dir ${Redis_Persistence}/|g" "${Redis_HOME}/etc/redis.conf"
  [ "${enable_unix_socket}" = 'y' ] && {
    sed -i 's|\(^# \+unixsocket .*\)|\1\nunixsocket /run/redis/redis.sock|g' "${Redis_HOME}/etc/redis.conf"
    sed -i 's/\(^# \+unixsocketperm .*\)/\1\nunixsocketperm 770/g' "${Redis_HOME}/etc/redis.conf"
  }
  [ -f "${Redis_HOME}/etc/redis-full.conf" ] && {
    sed -i 's#include redis.conf#include ./etc/redis.conf#g' "${Redis_HOME}/etc/redis-full.conf"
    sed -i 's#loadmodule .*\/#loadmodule ./lib/redis/modules/#g' "${Redis_HOME}/etc/redis-full.conf"
  }
}

install_redis_service() {
  chown -R redis:redis "${Redis_Persistence}" && chmod 750 "${Redis_Persistence}"
  \cp "${Redis_Parent_PATH}/bin/VTRedis" /bin/VTRedis
  chown root:root /bin/VTRedis && chmod +x /bin/VTRedis

  cat "${Redis_Parent_PATH}/service/redis.service" > /etc/systemd/system/redis.service
  [ -f "${Redis_HOME}/etc/redis-full.conf" ] && sed -i 's/redis.conf/redis-full.conf/g' /etc/systemd/system/redis.service
  [ "${enable_acl}" = 'y' ] && sed -i 's|\(^ExecStop.*\)|# \1\nExecStop=/bin/kill -s TERM $MAINPID|g' /etc/systemd/system/redis.service
  systemctl daemon-reload && systemctl enable redis.service
  systemctl start redis.service
  sleep 5
}

check_redis() {
  if [[ -s "${Redis_HOME}/bin/redis-server" && -s "${Redis_HOME}/bin/redis-cli" && -s "${Redis_HOME}/etc/redis.conf" ]]; then
    [ "${enable_acl}" = 'y' ] \
    && echo -e "\e[0;32m`"${Redis_HOME}/bin/redis-cli" -h 127.0.0.1 -p 6379 --user admin INFO`\e[0m" \
    || echo -e "\e[0;32m`"${Redis_HOME}/bin/redis-cli" INFO`\e[0m"
  else
    echo -e "${ERROR} Redis install failed. Check ${VT_log}/redis.log for more info."
  fi
}

enter_acl() {
  echo -e "Enable Redis Access Control List?\nMore info see https://redis.io/docs/latest/operate/oss_and_stack/management/security/acl/"
  echo -en "\e[0;33mEnable Redis ACL (y/n, deafult n): \e[0m"
  read -n1 enable_acl
  echo
}

acl() {
  echo "user default off" > "${Redis_Persistence}/users.acl"
  sed -i 's|\(# aclfile /etc/redis/users.acl\)|\1\naclfile ./users.acl|g' "${Redis_HOME}/etc/redis.conf"
  printf "\e[0;32m%-20s : %s\e[0m\n" 'username' 'password'
  acl_user 'admin' '~*' '&*' '+@all'
  acl_user 'readonly' '~app:* ~stats:*' '&app.' '+@read +@pubsub -publish -flushall -flushdb -config -debug -module -slaveof'
}

acl_user() {
  user=$1
  if [ -z "${user}" ]; then
    echo -e " ${ERROR} Wrong: No username."
    return 1
  fi
  keys=$2
  if [ -z "${keys}" ]; then
    keys='~app:* ~session:* ~cache:*'
  fi
  channels=$3
  if [ -z "${channels}" ]; then
    channels='&app.* &notifications.*'
  fi
  commands=$4
  if [ -z "${commands}" ]; then
    commands='+@read +@write +@pubsub -flushall -flushdb -config -debug -module -slaveof -save -bgsave'
  fi
  local pd=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c 12)
  local sha256pd=$(echo -n "${pd}" | sha256sum | awk '{print $1}')
  echo "user ${user} on #${sha256pd} ${keys} ${channels} ${commands}" >> "${Redis_Persistence}/users.acl"
  printf "%-20s : %s\n" $1 $pd
  [ ${user} = 'admin' ] && export REDISCLI_AUTH=${pd}
}

install() {
  print_version
  determine_path
  enter_overcommit
  enter_unix_socket
  enter_acl
  echo -e "[Starting time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_START=$(date +%s)
  if check_VT_INIT; then
    echo -e "${INFO} Installing all required packages..."
    init
  else
    echo -e "${INFO} VT init packages installation found, skip."
  fi
  install_llvm
  make_redis
  add_user
  [ "${enable_acl}" = 'y' ] && acl
  install_redis_service
  check_redis
  echo -e "[End time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_END=$(date +%s)
  echo -e "${INFO} Successfully done! Command takes $((TIME_END-TIME_START)) seconds."
}

VT_HOME="${HOME}/VT-Data"
VT_log="${VT_HOME}/logs"
VT_download="${VT_HOME}/source"
VT_build="${VT_HOME}/build"

[ ! -d "${VT_HOME}/" ] && mkdir ${VT_HOME}
[ ! -d "${VT_log}/" ] && mkdir ${VT_log}
[ ! -d "${VT_download}/" ] && mkdir ${VT_download}
[ ! -d "${VT_build}/" ] && mkdir ${VT_build}

Redis_HOME='/usr/local/redis'
Redis_Persistence='/var/lib/redis'
install 2>&1 | tee "${VT_log}/redis.log"
