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
  echo "|          VT-Web for Debian like Linux, Written by Echocolate           |"
  echo "+------------------------------------------------------------------------+"
  echo "|                    Scripts to install PHP on Linux                     |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Version: 1.0.0  Last Updated: 2026-06-13                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                      https://repos.echocolate.xyz                      |"
  echo "+------------------------------------------------------------------------+"
  sleep 2
}

determine_path() {
  PHP_Parent_PATH="$(dirname $0)/.."

  if [[ "$PHP_Parent_PATH" != /* ]]; then
    echo -e "${ERROR} ${PHP_Parent_PATH} 不是绝对路径，尝试获取绝对路径"
    PHP_Parent_PATH="$(pwd)/$(dirname $0)/.."
  fi

  if [[ "$PHP_Parent_PATH" == /* ]] && [[ -n "$PHP_Parent_PATH" ]]; then
    echo -e "${INFO} ${PHP_Parent_PATH}"
  else
    echo -e "${ERROR} 获取绝对路径失败"
    exit 1
  fi
}

get_php_latest() {
  local repo_name='php/php-src'
  local version=$(curl -s https://api.github.com/repos/${repo_name}/releases/latest | grep tag_name | head -n 1 | cut -d '"' -f 4)
  [ -z "${version}" ] && {
    sleep 5
    version=$(curl -s https://api.github.com/repos/${repo_name}/tags | grep "name" | grep -vEi ".*(rc|r).*" | cut -d '"' -f 4 | sort -Vr | head -n 1)
  }
  [ -z "${version}" ] && {
    echo -e "${ERROR} Cant get version for repo: ${repo_name}."
    exit 1
  }
  sleep 5
  echo -e "${version#php-}"
}

read_parameters() {
  cat <<EOF
There are two PHP execution modes:
1. PHP-FPM: Works with any web server that supports FastCGI (e.g., Nginx, Apache).
2. mod_php: Works only with Apache.
EOF
  read -p $'\e[0;33mPlease enter your choice (1 or 2, default 1): \e[0m' -n 1 php_execution_modes
  echo

  if [ "${php_execution_modes}" = '2' ]; then
    apache_home="${apache_path:-}"
    if [ -z "${apache_home}" ] || [ "${apache_home}" = '' ]; then
      enter_apache_home
    fi
    if [ -s "${apache_home}/bin/httpd" ] && [ -s "${apache_home}/conf/httpd.conf" ]; then
      echo -e "${INFO} Apache Home Path: ${apache_home}"
    else
      echo -e "${ERROR} Cannnot find httpd in ${apache_home}"
      exit 1
    fi
    php_mode='mod_php'
    with_php_mode="--with-apxs2=${apache_home}/bin/apxs"
  else
    php_mode='php-fpm'
    with_php_mode='--enable-fpm --with-fpm-user=www --with-fpm-group=www'
  fi
}

enter_apache_home() {
  local n=0
  while [ $n -lt 3 ] ;do
    ((n++))
    read -p $'\e[0;33mEnter Your Apache Home PATH: \e[0m' apache_home
    if [ -z "${apache_home}" ] || [ "${apache_home}" = '' ]; then
      echo -e "${ERROR} Apache Home can't be empty!"
    else
      return 0
    fi
  done
  echo -e "${ERROR} Invaild input too many times!"
  exit 1
}

add_user() {
  # groupadd -g 2000 www && useradd -M -g www -u 2000 www -s /sbin/nologin
  if id www >/dev/null 2>&1; then
    echo -e "${INFO} User www already exists."
  else
    useradd -r -s /sbin/nologin www
  fi
}

make_php() {
  apt-get --no-install-recommends install -y libpq-dev

  cd "${VT_download}"
  local PHP_Version="${PHP_ver:-$(get_php_latest)}"
  wget -c -nv "https://www.php.net/distributions/php-${PHP_Version}.tar.gz" -O "php-${PHP_Version}.tar.gz"
  if [ $? -ne 0 ]; then
    echo -e "${ERROR} Download PHP failed."
    exit 1
  fi

  cd ${VT_build}
  rm -rf php
  mkdir php && tar zxf "${VT_download}/php-${PHP_Version}.tar.gz" --strip-components=1 --directory=php

  cd php
  if pkg-config --modversion icu-i18n | grep -Eqi '^6[89]|7[0-9]'; then
    export CXX="g++ -DTRUE=1 -DFALSE=0"
    export  CC="gcc -DTRUE=1 -DFALSE=0"
  fi

  ./configure \
    --prefix=${PHP_Path} \
    --with-config-file-path=${PHP_Path}/etc \
    --with-config-file-scan-dir=${PHP_Path}/conf.d \
    ${with_php_mode} \
    --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd \
    --with-pgsql --with-pdo-pgsql \
    --with-iconv=/usr/local \
    --with-freetype=/usr/local/freetype \
    --with-jpeg \
    --with-zlib \
    --enable-xml \
    --disable-rpath \
    --enable-bcmath \
    --enable-shmop \
    --enable-sysvsem \
    --with-curl \
    --enable-mbregex \
    --enable-mbstring \
    --enable-intl \
    --enable-pcntl \
    --enable-ftp \
    --enable-gd \
    --with-openssl \
    --with-mhash \
    --enable-sockets \
    --with-zip \
    --enable-soap \
    --with-gettext \
    --with-xsl \
    --with-pear \
    --with-webp \
    --enable-exif \
    --with-ldap --with-ldap-sasl \
    --with-bz2 \
    --with-sodium

    make ZEND_EXTRA_LIBS='-liconv' -j `grep 'processor' /proc/cpuinfo | wc -l`
    if [ $? -ne 0 ]; then
      make ZEND_EXTRA_LIBS='-liconv'
    fi
    make install

  # 路径
  ln -sf ${PHP_Path}/bin/php    /usr/bin/php
  ln -sf ${PHP_Path}/bin/phpize /usr/bin/phpize
  ln -sf ${PHP_Path}/bin/pear   /usr/bin/pear
  ln -sf ${PHP_Path}/bin/pecl   /usr/bin/pecl
}

configure_php_fpm() {
  ln -sf ${PHP_Path}/sbin/php-fpm /usr/bin/php-fpm
  echo "Creating new php-fpm configure file..."
  cat >${PHP_Path}/etc/php-fpm.conf<<EOF
[global]
pid = ${PHP_Path}/var/run/php-fpm.pid
error_log = ${PHP_Path}/var/log/php-fpm.log
log_level = notice

[www]
listen = /tmp/php-cgi.sock
listen.backlog = -1
listen.allowed_clients = 127.0.0.1
listen.owner = www
listen.group = www
listen.mode = 0666
user = www
group = www
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 6
pm.max_requests = 1024
pm.process_idle_timeout = 10s
request_terminate_timeout = 100
request_slowlog_timeout = 0
slowlog = var/log/slow.log
EOF

  echo "Copy php-fpm init.d file..."
  \cp sapi/fpm/init.d.php-fpm /etc/init.d/php-fpm
  chown root:root /etc/init.d/php-fpm && chmod +x /etc/init.d/php-fpm
  cat "${PHP_Parent_PATH}/service/php-fpm.service" > /etc/systemd/system/php-fpm.service
}

configure_php() {
  echo "Copy new php configure file..."
  rm -f ${PHP_Path}/conf.d/*
  mkdir -p ${PHP_Path}/{etc,conf.d}
  \cp php.ini-production ${PHP_Path}/etc/php.ini

  [ "$php_mode" = 'php-fpm' ] && configure_php_fpm

  echo "Modify php.ini......"
  sed -i 's/post_max_size =.*/post_max_size = 50M/g' ${PHP_Path}/etc/php.ini
  sed -i 's/upload_max_filesize =.*/upload_max_filesize = 50M/g' ${PHP_Path}/etc/php.ini
  sed -i 's/;date.timezone =.*/date.timezone = PRC/g' ${PHP_Path}/etc/php.ini
  sed -i 's/short_open_tag =.*/short_open_tag = On/g' ${PHP_Path}/etc/php.ini
  sed -i 's/;cgi.fix_pathinfo=.*/cgi.fix_pathinfo=0/g' ${PHP_Path}/etc/php.ini
  sed -i 's/max_execution_time =.*/max_execution_time = 300/g' ${PHP_Path}/etc/php.ini
  sed -i 's/disable_functions =.*/disable_functions = passthru,exec,system,chroot,chgrp,chown,shell_exec,proc_open,proc_get_status,popen,ini_alter,ini_restore,dl,openlog,syslog,readlink,symlink,popepassthru,stream_socket_server/g' ${PHP_Path}/etc/php.ini

  pear config-set php_ini ${PHP_Path}/etc/php.ini
  pecl config-set php_ini ${PHP_Path}/etc/php.ini
}

install_composer() {
  wget --progress=dot:giga --prefer-family=IPv4 --no-check-certificate -T 120 -t3 https://getcomposer.org/download/latest-stable/composer.phar -O /usr/local/bin/composer
  chmod +x /usr/local/bin/composer
}

install_pie() {
  curl -fL --output /tmp/pie.phar https://github.com/php/pie/releases/latest/download/pie.phar && \
  mv /tmp/pie.phar /usr/local/bin/pie && \
  chmod +x /usr/local/bin/pie
  if [ -f '/usr/local/bin/pie' ]; then
    # allow the following functions and then pie can install successfully : proc_open, proc_get_status
    sed -i 's/disable_functions =.*/disable_functions = passthru,exec,system,chroot,chgrp,chown,shell_exec,popen,ini_alter,ini_restore,dl,openlog,syslog,readlink,symlink,popepassthru,stream_socket_server/g' ${PHP_Path}/etc/php.ini
    echo "Usage: pie install <vendor>/<package>"
  fi
}

Opt_PHP() {
  local MemTotal=$(awk '/MemTotal/ {printf( "%d\n", $2 / 1024 )}' /proc/meminfo)

  if [[ ${MemTotal} -gt 1024 && ${MemTotal} -le 2048 ]]; then
    sed -i "s#pm.max_children.*#pm.max_children = 20#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.start_servers.*#pm.start_servers = 10#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.min_spare_servers.*#pm.min_spare_servers = 10#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.max_spare_servers.*#pm.max_spare_servers = 20#" ${PHP_Path}/etc/php-fpm.conf
  elif [[ ${MemTotal} -gt 2048 && ${MemTotal} -le 4096 ]]; then
    sed -i "s#pm.max_children.*#pm.max_children = 40#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.start_servers.*#pm.start_servers = 20#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.min_spare_servers.*#pm.min_spare_servers = 20#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.max_spare_servers.*#pm.max_spare_servers = 40#" ${PHP_Path}/etc/php-fpm.conf
  elif [[ ${MemTotal} -gt 4096 && ${MemTotal} -le 8192 ]]; then
    sed -i "s#pm.max_children.*#pm.max_children = 60#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.start_servers.*#pm.start_servers = 30#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.min_spare_servers.*#pm.min_spare_servers = 30#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.max_spare_servers.*#pm.max_spare_servers = 60#" ${PHP_Path}/etc/php-fpm.conf
  elif [[ ${MemTotal} -gt 8192 ]]; then
    sed -i "s#pm.max_children.*#pm.max_children = 80#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.start_servers.*#pm.start_servers = 40#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.min_spare_servers.*#pm.min_spare_servers = 40#" ${PHP_Path}/etc/php-fpm.conf
    sed -i "s#pm.max_spare_servers.*#pm.max_spare_servers = 80#" ${PHP_Path}/etc/php-fpm.conf
  fi
}

opt_opcache() {
  cat >${PHP_Path}/conf.d/004-opcache.ini<<EOF
[Zend Opcache]
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=4000
opcache.revalidate_freq=60
opcache.fast_shutdown=1
opcache.enable_cli=1

opcache.jit = 1255
opcache.jit_buffer_size = 64M
EOF

  echo "Copy Opcache Control Panel..."
  curl -L 'https://raw.githubusercontent.com/mlazarov/ocp/refs/heads/master/ocp.php' -o ${Web_Dir}/ocp.php
  chown www:www ${Web_Dir}/ocp.php
}

end_php() {
  echo "Create PHP Info Script..."
  cat >${Web_Dir}/phpinfo.php<<EOF
<?php
phpinfo();
?>
EOF
  chown www:www ${Web_Dir}/phpinfo.php
}

start_php() {
  if [ "$php_mode" = 'mod_php' ]; then
    echo "Restarting Apache......"
    "${apache_home}/bin/httpd" -k restart
  else
    echo "Start php-fpm......"
    systemctl daemon-reload && systemctl enable --now php-fpm
  fi
}

check_php() {
  if [[ -s ${PHP_Path}/bin/php && -s ${PHP_Path}/etc/php.ini ]]; then
    if [ "$php_mode" = 'mod_php' ] && [ -s "${apache_home}/modules/libphp.so" ]; then
      echo -e "${INFO} PHP: OK, running in mode: ${php_mode}."
      return 0
    fi
    if [ "$php_mode" = 'php-fpm' ] && [ -s ${PHP_Path}/sbin/php-fpm ]; then
      echo -e "${INFO} PHP: OK, running in mode: ${php_mode}."
      return 0
    fi
  fi
  echo -e "${ERROR} PHP install failed."
}

install() {
  print_version
  determine_path
  read_parameters
  echo -e "[Starting time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_START=$(date +%s)
  add_user
  make_php
  configure_php
  install_composer
  install_pie
  Opt_PHP
  opt_opcache
  end_php
  start_php
  check_php
  echo -e "[End time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_END=$(date +%s)
  echo -e "${INFO} Successfully done! Command takes $((TIME_END-TIME_START)) seconds."
}

PHP_Path='/usr/local/php'
Web_Dir="${web_path:-/home/wwwroot/default}"
[ ! -d ${Web_Dir} ] && mkdir -p ${Web_Dir}

VT_HOME="${HOME}/VT-Data"
VT_log="${VT_HOME}/logs"
VT_bk="${VT_HOME}/backup"
VT_download="${VT_HOME}/source"
VT_build="${VT_HOME}/build"

[ ! -d "${VT_HOME}/" ] && mkdir ${VT_HOME}
[ ! -d "${VT_log}/" ] && mkdir ${VT_log}
[ ! -d "${VT_bk}/" ] && mkdir ${VT_bk}
[ ! -d "${VT_download}/" ] && mkdir ${VT_download}
[ ! -d "${VT_build}/" ] && mkdir ${VT_build}

install 2>&1 | tee "${VT_log}/php.log"
