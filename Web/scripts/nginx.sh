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
  echo "|                   Scripts to install Nginx on Linux                    |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Version: 1.0.0  Last Updated: 2026-06-13                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                      https://repos.echocolate.xyz                      |"
  echo "+------------------------------------------------------------------------+"
  sleep 2
}

determine_path() {
  Nginx_Parent_PATH="$(dirname $0)/.."

  if [[ "$Nginx_Parent_PATH" != /* ]]; then
    echo -e "${ERROR} ${Nginx_Parent_PATH} 不是绝对路径，尝试获取绝对路径"
    Nginx_Parent_PATH="$(pwd)/$(dirname $0)/.."
  fi

  if [[ "$Nginx_Parent_PATH" == /* ]] && [[ -n "$Nginx_Parent_PATH" ]]; then
    echo -e "${INFO} ${Nginx_Parent_PATH}"
  else
    echo -e "${ERROR} 获取绝对路径失败"
    exit 1
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv6l) echo "armv6" ;;
    i?86)          echo "386" ;;
    *)             echo "unknown" ;;
  esac
}

get_github_latest() {
  local repo_name=$1
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
  echo -e $version
}

get_nginx_latest() {
  # 获取最新 mainline 版本
  local version=$(curl -s https://nginx.org/en/CHANGES | grep -oE '^Changes with nginx [0-9]+\.[0-9]+\.[0-9]+[[:space:]]+[0-3][0-9] [A-Z][a-z]{2} [0-9]{4}$' | grep -oP '\d+\.\d+\.\d+' | sort -Vr | head -n 1)
  [ -z "${version}" ] && {
    echo -e "${ERROR} Cant get version for Nginx."
    exit 1
  }
  echo -e $version
}

read_parameters() {
  # 是否作为Apache的反向代理
  read -p $'\e[0;33mUsing Nginx as a reverse proxy for Apache(y,n default n): \e[0m' -n1 nginx_proxy_apache
  echo
  # 是否启用 gunzip
  read -p $'\e[0;33mEnable Nginx gunzip module(y,n default n): \e[0m' -n1 nginx_gunzip
  echo
  # 是否启用 Lua
  read -p $'\e[0;33mEnable Nginx Lua module(y,n default y): \e[0m' -n1 nginx_lua
  echo
  # 是否启用 Brotli
  read -p $'\e[0;33mEnable Nginx Brotli module(y,n default n): \e[0m' -n1 nginx_brotli
  echo
  # 是否启用 VTS
  read -p $'\e[0;33mEnable Nginx VTS module(y,n default n): \e[0m' -n1 nginx_vts
  echo
  # 是否启用 GeoIP
  read -p $'\e[0;33mEnable Nginx geoip2 module(y,n default n): \e[0m' -n1 nginx_geoip
  echo
  # 是否启用 ModSecurity
  read -p $'\e[0;33mEnable Nginx ModSecurity module(y,n default n): \e[0m' -n1 nginx_modsecurity
  echo
  # 是否启用 Cloudfalre CDN
  read -p $'\e[0;33mDo you use cloudflare as CDN(y,n default n): \e[0m' -n1 nginx_cloudflare
  echo

  while :;do
    echo -en "\e[0;33mPlease enter your email address: \e[0m"
    read email_address
    if [[ "${email_address}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,4}$ ]]; then
      echo "Email address ${email_address} is valid."
      break
    else
      echo "Email address ${email_address} is invalid! Please re-enter."
    fi
  done
}

add_user() {
  # groupadd -g 2000 www && useradd -M -g www -u 2000 www -s /sbin/nologin
  if id www >/dev/null 2>&1; then
    echo -e "${INFO} User www already exists."
  else
    useradd -r -s /sbin/nologin www
  fi
}

download_nginx() {
  cd "${VT_download}"
  mkdir -p nginx

  local nginx_version="${nginx_ver:-$(get_nginx_latest)}"
  wget -c -nv "https://nginx.org/download/nginx-${nginx_version}.tar.gz" -O nginx/nginx_${nginx_version}.tar.gz
  if [ $? -ne 0 ]; then
    echo -e "${ERROR} Download Nginx failed."
    exit 1
  fi

  cd ${VT_build}
  rm -rf nginx && mkdir -p nginx/{nginx,lua,module,dependency}
  tar zxf "${VT_download}/nginx/nginx_${nginx_version}.tar.gz" --strip-components=1 --directory=nginx/nginx
}

download_nginx_dependency() {
  cd "${VT_download}/nginx"

  local status=0
  # zlib
  wget -c -nv https://zlib.net/current/zlib.tar.gz -O zlib.tar.gz
  status=$((status + $?))
  # OpenSSL
  local openssl_version="${openssl_ver:-$(get_github_latest 'openssl/openssl')}"
  wget -c -nv https://github.com/openssl/openssl/releases/download/${openssl_version}/${openssl_version}.tar.gz -O openssl.tar.gz
  status=$((status + $?))
  # Pcre
  local pcre2_version="${pcre2_ver:-$(get_github_latest 'PCRE2Project/pcre2')}"
  wget -c -nv https://github.com/PCRE2Project/pcre2/releases/download/${pcre2_version}/${pcre2_version}.tar.gz -O pcre2.tar.gz
  status=$((status + $?))

  if [ $status -ne 0 ]; then
    echo -e "${ERROR} Download Nginx failed."
    exit 1
  fi

  cd ${VT_build}
  mkdir -p nginx/dependency/{zlib,openssl,pcre2}

  tar zxf "${VT_download}/nginx/zlib.tar.gz" --strip-components=1 --directory=nginx/dependency/zlib
  tar zxf "${VT_download}/nginx/openssl.tar.gz" --strip-components=1 --directory=nginx/dependency/openssl
  tar zxf "${VT_download}/nginx/pcre2.tar.gz" --strip-components=1 --directory=nginx/dependency/pcre2
}

build_luajit() {
  cd "${VT_build}/nginx/lua"
  rm -rf luajit2

  git clone https://github.com/openresty/luajit2.git
  cd luajit2

  make -j `grep 'processor' /proc/cpuinfo | wc -l` && make install PREFIX=/usr/local/luajit

  echo "/usr/local/luajit/lib" > /etc/ld.so.conf.d/luajit.conf

  ln -sf /usr/local/luajit/lib/libluajit-5.1.so.2 /lib64/libluajit-5.1.so.2

  echo "export LUAJIT_LIB=/usr/local/luajit/lib" > /etc/profile.d/luajit.sh
  echo "export LUAJIT_INC=/usr/local/luajit/include/luajit-2.1" >> /etc/profile.d/luajit.sh

  cd -
}

download_nginx_lua() {
  cd "${VT_download}/nginx"
  local status=0

  # NDK
  local ngx_devel_kit_version="${NDK_ver:-$(get_github_latest 'vision5/ngx_devel_kit')}"
  wget -c -nv https://github.com/vision5/ngx_devel_kit/archive/refs/tags/${ngx_devel_kit_version}.tar.gz -O ngx_devel_kit.tar.gz
  status=$((status + $?))
  # Ngx_Lua
  local lua_nginx_module_version="${Ngx_Lua_ver:-$(get_github_latest 'openresty/lua-nginx-module')}"
  wget -c -nv https://github.com/openresty/lua-nginx-module/archive/refs/tags/${lua_nginx_module_version}.tar.gz -O lua-nginx-module.tar.gz
  status=$((status + $?))

  # Ngx_Stream_Lua
  local stream_lua_nginx_module_version="${Ngx_Stream_Lua_ver:-$(get_github_latest 'openresty/stream-lua-nginx-module')}"
  wget -c -nv https://github.com/openresty/stream-lua-nginx-module/archive/refs/tags/${stream_lua_nginx_module_version}.tar.gz -O stream-lua-nginx-module.tar.gz
  status=$((status + $?))

  # LuaRestyLrucache
  local lua_resty_lrucache_version="${LuaRestyLrucache_ver:-$(get_github_latest 'openresty/lua-resty-lrucache')}"
  wget -c -nv https://github.com/openresty/lua-resty-lrucache/archive/refs/tags/${lua_resty_lrucache_version}.tar.gz -O lua-resty-lrucache.tar.gz
  status=$((status + $?))

  # LuaRestCore
  local lua_resty_core_version="${LuaRestCore_ver:-$(get_github_latest 'openresty/lua-resty-core')}"
  wget -c -nv https://github.com/openresty/lua-resty-core/archive/refs/tags/${lua_resty_core_version}.tar.gz -O lua-resty-core.tar.gz
  status=$((status + $?))

  if [ $status -ne 0 ]; then
    echo -e "${ERROR} Download lua modules failed."
    exit 1
  fi

  cd ${VT_build}
  mkdir -p nginx/lua/{ngx_devel_kit,lua-nginx-module,stream-lua-nginx-module,lua-resty-lrucache,lua-resty-core}

  tar zxf "${VT_download}/nginx/ngx_devel_kit.tar.gz" --strip-components=1 --directory=nginx/lua/ngx_devel_kit
  tar zxf "${VT_download}/nginx/lua-nginx-module.tar.gz" --strip-components=1 --directory=nginx/lua/lua-nginx-module
  tar zxf "${VT_download}/nginx/stream-lua-nginx-module.tar.gz" --strip-components=1 --directory=nginx/lua/stream-lua-nginx-module
  tar zxf "${VT_download}/nginx/lua-resty-lrucache.tar.gz" --strip-components=1 --directory=nginx/lua/lua-resty-lrucache
  tar zxf "${VT_download}/nginx/lua-resty-core.tar.gz" --strip-components=1 --directory=nginx/lua/lua-resty-core
}

configure_lua() {
  cd "${VT_build}/nginx/lua"

  cd lua-resty-lrucache
  make install PREFIX=/usr/local/nginx LUA_LIB_DIR=/usr/local/nginx/lib/lua
  cd -

  cd lua-resty-core
  make install PREFIX=/usr/local/nginx LUA_LIB_DIR=/usr/local/nginx/lib/lua
  cd -
}

download_nginx_brotli() {
  cd "${VT_build}/nginx/module"

  git clone --recurse-submodules -j8 https://github.com/google/ngx_brotli
  cd ngx_brotli/deps/brotli/
  git fetch --all --tags
  git checkout v1.2.0

  mkdir out && cd out
  # cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=./installed ..
  cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_C_FLAGS="-Ofast -m64 -march=native -mtune=native -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections" -DCMAKE_CXX_FLAGS="-Ofast -m64 -march=native -mtune=native -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections" -DCMAKE_INSTALL_PREFIX=./installed ..
  # cmake --build . --config Release --target install
  cmake --build . --config Release --target brotlienc
  cd ../../../..
  export CFLAGS="-m64 -march=native -mtune=native -Ofast -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections"
  export LDFLAGS="-m64 -Wl,-s -Wl,-Bsymbolic -Wl,--gc-sections"
}

download_nginx_vts() {
  cd "${VT_build}/nginx/module"
  git clone https://github.com/vozlt/nginx-module-vts.git
}

build_libmaxminddb() {
  cd "${VT_download}/nginx"

  local libmaxminddb_version="${libmaxminddb_ver:-$(get_github_latest 'maxmind/libmaxminddb')}"
  wget -c -nv https://github.com/maxmind/libmaxminddb/releases/download/${libmaxminddb_version}/libmaxminddb-${libmaxminddb_version}.tar.gz -O libmaxminddb.tar.gz
  if [ $? -ne 0 ]; then
    echo -e "${ERROR} Download libmaxminddb failed."
    exit 1
  fi

  cd "${VT_build}/nginx/dependency"
  mkdir libmaxminddb && tar zxf "${VT_download}/nginx/libmaxminddb.tar.gz" --strip-components=1 --directory=libmaxminddb

  cd libmaxminddb
  ./configure
  make
  # make check
  make install
  ldconfig

  cd -
}

install_geoipupdate() {
  cd "${VT_download}/nginx"
  local ARCH=$(detect_arch)
  local geoipupdate_version="${geoipupdate_ver:-$(get_github_latest 'maxmind/geoipupdate')}"
  wget -c -nv "https://github.com/maxmind/geoipupdate/releases/download/${geoipupdate_version}/geoipupdate_${geoipupdate_version#v}_linux_${ARCH}.tar.gz" -O geoipupdate.tar.gz
  if [ $? -ne 0 ]; then
    echo -e "${ERROR} Download geoipupdate failed. Try download geoipupdate by yourself later."
    return 1
  fi
  mkdir -p /usr/local/geoipupdate && tar zxf geoipupdate.tar.gz --strip-components=1 --directory=/usr/local/geoipupdate
  chown root:root /usr/local/geoipupdate/*
  rm geoipupdate.tar.gz

  # 配置 API
  local status=0
  [ -z "${maxmind_account_id:-}" ] && status=$((status + 1)) || sed -i 's|^AccountID.*|AccountID '"$maxmind_account_id"'|' /usr/local/geoipupdate/GeoIP.conf
  [ -z "${maxmind_license_key:-}" ] && status=$((status + 1)) || sed -i 's|^LicenseKey.*|LicenseKey '"$maxmind_license_key"'|' /usr/local/geoipupdate/GeoIP.conf
  sed -i 's|^\(# DatabaseDirectory.*\)|\1\nDatabaseDirectory /usr/local/nginx/geoip|g' /usr/local/geoipupdate/GeoIP.conf
  if [ $status -ne 0 ]; then
    echo -e "${ERROR} Invaild Maxmind API, please check your LicenseKey in \`/usr/local/geoipupdate/GeoIP.conf\`."
    return 1
  fi
  # 下载数据文件并设置定时任务
  /usr/local/geoipupdate/geoipupdate -f /usr/local/geoipupdate/GeoIP.conf
  geoipupdate_job="
# Update GeoLite Databases twice a week
3 6 * * 1,3 /usr/local/geoipupdate/geoipupdate -f /usr/local/geoipupdate/GeoIP.conf"
  (crontab -l 2>/dev/null; echo "$geoipupdate_job") | awk '!seen[$0]++' | crontab -
}

download_nginx_geoip2() {
  cd "${VT_build}/nginx/module"
  git clone https://github.com/leev/ngx_http_geoip2_module.git
}

download_nginx_modsecurity() {
  cd "${VT_build}/nginx/dependency"
  git clone --depth 1 -b v3/master --single-branch https://github.com/owasp-modsecurity/ModSecurity
  cd ModSecurity
  git submodule update --init --recursive
  ./build.sh
  ./configure --prefix=/usr/local/modsecurity
  make -j$(nproc) && make install
  cd -

  cd "${VT_build}/nginx/module"
  git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx
}

download_nginx_fancy() {
  cd "${VT_download}/nginx"

  local fancyindex_version=$(get_github_latest "aperezdc/ngx-fancyindex")
  local fancyindex_download_version=$(echo $fancyindex_version | sed 's/v//g')
  wget -c -nv https://github.com/aperezdc/ngx-fancyindex/releases/download/${fancyindex_version}/ngx-fancyindex-${fancyindex_download_version}.tar.xz -O ngx-fancyindex.tar.gz
  if [ $? -ne 0 ]; then
    echo -e "${ERROR} Download fancy module failed."
    exit 1
  fi

  cd "${VT_build}/nginx/module"
  mkdir ngx-fancyindex && tar xf "${VT_download}/nginx/ngx-fancyindex.tar.gz" --strip-components=1 --directory=ngx-fancyindex
}

make_nginx() {
  local with_lua="--add-module=${VT_build}/nginx/lua/ngx_devel_kit \
                  --add-module=${VT_build}/nginx/lua/lua-nginx-module \
                  --add-module=${VT_build}/nginx/lua/stream-lua-nginx-module"
  [ "${nginx_lua}" = 'n' ] && with_lua='' || {
    download_nginx_lua
    configure_lua
  }
  [ "${nginx_brotli}" = 'y' ] && {
    apt-get --no-install-recommends install -y brotli
    download_nginx_brotli
    local with_brotli="--add-module=${VT_build}/nginx/module/ngx_brotli"
  }
  [ "${nginx_vts}" = 'y' ] && {
    download_nginx_vts
    local with_vts="--add-module=${VT_build}/nginx/module/nginx-module-vts"
  }
  [ "${nginx_geoip}" = 'y' ] && {
    build_libmaxminddb
    install_geoipupdate
    download_nginx_geoip2
    local with_geoip="--add-module=${VT_build}/nginx/module/ngx_http_geoip2_module"
  }
  [ "${nginx_modsecurity}" = 'y' ] && {
    download_nginx_modsecurity
    local with_modsecurity="--add-module=${VT_build}/nginx/module/ModSecurity-nginx"
  }
  [ "${nginx_gunzip}" = 'y' ] && local with_http_gunzip='--with-http_gunzip_module'

  download_nginx_fancy
  cd ${VT_build}/nginx/nginx
  source /etc/profile.d/luajit.sh

  ./configure \
    --http-client-body-temp-path=/usr/local/nginx/client_body_temp \
    --http-proxy-temp-path=/usr/local/nginx/proxy_temp \
    --http-fastcgi-temp-path=/usr/local/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/usr/local/nginx/uwsgi_temp \
    --http-scgi-temp-path=/usr/local/nginx/scgi_temp \
    --user=www --group=www \
    --prefix=/usr/local/nginx\
    --with-http_stub_status_module \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_gzip_static_module \
    ${with_http_gunzip} \
    --with-http_sub_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-openssl=${VT_build}/nginx/dependency/openssl \
    --with-openssl-opt='enable-weak-ssl-ciphers' \
    --with-pcre=${VT_build}/nginx/dependency/pcre2 --with-pcre-jit \
    --with-zlib=${VT_build}/nginx/dependency/zlib \
    --with-ld-opt=-Wl,-rpath,/usr/local/luajit/lib \
    ${with_lua} \
    ${with_brotli} \
    ${with_vts} \
    ${with_geoip} \
    ${with_modsecurity} \
    --add-module=${VT_build}/nginx/module/ngx-fancyindex

  make -j `grep 'processor' /proc/cpuinfo | wc -l`
  make install
  ln -sf /usr/local/nginx/sbin/nginx /usr/bin/nginx
}

fastcgi() {
  cat >${websites_path}/.user.ini<<EOF
open_basedir=${websites_path}:/tmp/:/proc/
EOF
  chown www:www ${websites_path}/.user.ini && chmod 644 ${websites_path}/.user.ini
  # chattr +i ${websites_path}/.user.ini
  cat >>/usr/local/nginx/conf/fastcgi.conf<<EOF
fastcgi_param PHP_ADMIN_VALUE "open_basedir=\$document_root/:/tmp/:/proc/";
EOF
}

conf_apache() {
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/proxy-pass-php.conf"          /usr/local/nginx/conf/
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/proxy-apache.conf"            /usr/local/nginx/conf/proxy/apache.conf
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/nginx-proxy-apache.conf"      /usr/local/nginx/conf/nginx.conf
}

conf_nginx() {
  [ ! -d "$websites_path" ] && mkdir -p "${websites_path}"
  [ ! -d "$web_logs_path" ] && mkdir -p "${web_logs_path}"
  chown -R www:www ${websites_path} && chmod -R 755 ${websites_path}
  chown -R www:www $web_logs_path && chmod -R 755 $web_logs_path

  mkdir -p /usr/local/nginx/conf/{proxy,module}
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/404.conf"                     /usr/local/nginx/conf/
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/enable-php-pathinfo.conf"     /usr/local/nginx/conf/
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/enable-php.conf"              /usr/local/nginx/conf/
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/pathinfo.conf"                /usr/local/nginx/conf/
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/nginx.conf"                   /usr/local/nginx/conf/
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/proxy.conf"                   /usr/local/nginx/conf/proxy/
  \cp -a "${Nginx_Parent_PATH}/conf/nginx/ngx_http_lua_module.conf"     /usr/local/nginx/conf/module/lua.conf
  [ "$nginx_proxy_apache" = 'y' ] && conf_apache || fastcgi

  cat > /usr/local/nginx/conf/auth.conf <<EOF
        # password
        auth_basic "Please input password";
        auth_basic_user_file $(cd "${websites_path}"/.. && pwd)/.passwd;
EOF
  cat /dev/null > $(cd "${websites_path}"/.. && pwd)/.passwd
  chown www:www $(cd "${websites_path}"/.. && pwd)/.passwd && chmod 400 $(cd "${websites_path}"/.. && pwd)/.passwd
  cat /dev/null > /usr/local/nginx/conf/blacklist.conf
  # Lua
  [ "$nginx_lua" = 'n' ] && {
    sed -i 's|\([[:space:]]\{1,\}\)\(lua_package_path.*\)$|\1# \2|g' /usr/local/nginx/conf/nginx.conf
    sed -i '/[[:space:]]*{ngx_http_lua_module}/d' /usr/local/nginx/conf/nginx.conf
  } || sed -i 's|\([[:space:]]*\){ngx_http_lua_module}|\1include module/lua.conf;|g' /usr/local/nginx/conf/nginx.conf

  # Brotli
  [ "$nginx_brotli" = 'y' ] && {
    sed -i '/\([[:space:]]*\){ngx_http_brotli_module}/c\
        # --- Brotli 配置 ---\
        brotli on;\
        brotli_static on;           # 开启静态预压缩检测\
        brotli_min_length 1k;\
        brotli_buffers    16 8k;\
        brotli_comp_level 5;        # 动态压缩等级(1-11)\
        brotli_types\
            text/plain text/css\
            application/javascript application/x-javascript text/javascript\
            application/xml application/xml+rss\
            application/json\
            image/svg+xml font/woff;\n' /usr/local/nginx/conf/nginx.conf
  } || sed -i '/[[:space:]]*{ngx_http_brotli_module}/d' /usr/local/nginx/conf/nginx.conf

  # VTS
  [ "$nginx_vts" = 'y' ] && {
    \cp -a "${Nginx_Parent_PATH}/conf/nginx/ngx_http_vts_module.conf"   /usr/local/nginx/conf/module/vts.conf
    sed -i 's|\([[:space:]]*\)# *vhost_traffic_status_zone;|\1vhost_traffic_status_zone;|g' /usr/local/nginx/conf/nginx.conf
    sed -i 's|\([[:space:]]*\){ngx_http_vts_module}|\1include module/vts.conf;|g' /usr/local/nginx/conf/nginx.conf
  } || sed -i '/[[:space:]]*{ngx_http_vts_module}/d'  /usr/local/nginx/conf/nginx.conf

  # GeoIP
  [ "$nginx_geoip" = 'y' ] && {
    \cp -a "${Nginx_Parent_PATH}/conf/nginx/ngx_http_geoip2_module.conf"   /usr/local/nginx/conf/module/geoip2.conf
    sed -i 's|\([[:space:]]*\)# include module/geoip2.conf;|\1include module/geoip2.conf;|g' /usr/local/nginx/conf/nginx.conf
    sed -i 's|{GeoIP2LOG}|($geoip2_data_country_code/$geoip2_data_city_name)|g' /usr/local/nginx/conf/nginx.conf
  } || sed -i 's/{GeoIP2LOG}//g' /usr/local/nginx/conf/nginx.conf

  # CDN
  [ "$nginx_cloudflare" = 'y' ] && {
    conf_cloudflare /usr/local/nginx/conf/cloudflare_real_ip.conf
    sed -i 's|\([[:space:]]\{1,\}\)# include[[:space:]]\{1,\}cloudflare_real_ip.conf;$|\1include       cloudflare_real_ip.conf;|g' /usr/local/nginx/conf/nginx.conf
  }
  sed -i "s|root  {websites_path};|root  ${websites_path};|g" /usr/local/nginx/conf/nginx.conf
  sed -i "s|{web_logs_path}|${web_logs_path}|g" /usr/local/nginx/conf/nginx.conf
  # 404
  echo '<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx</center>
</body>
</html>' > /usr/local/nginx/html/404.html
  mkdir -p /usr/local/nginx/conf/vhost
  chown -R root:root /usr/local/nginx/conf/
  cat "${Nginx_Parent_PATH}/service/nginx.service" > /etc/systemd/system/nginx.service
}

conf_cloudflare() {
  echo "# Cloudflare Real IP Configuration" > $1
  echo "# Generated at $(date)" >> $1
  echo "" >> $1

  # 获取并格式化 IPv4
  echo "# IPv4" >> $1
  curl -s "https://www.cloudflare.com/ips-v4" | sed 's/^/set_real_ip_from /; s/$/;/' >> $1

  # 获取并格式化 IPv6
  echo -e "\n" >> $1
  echo "# IPv6" >> $1
  curl -s "https://www.cloudflare.com/ips-v6" | sed 's/^/set_real_ip_from /; s/$/;/' >> $1

  # 写入核心指令
  echo -e "\n" >> $1

  cat >> $1 <<EOF
#use any of the following two
real_ip_header CF-Connecting-IP;
#real_ip_header X-Forwarded-For;

real_ip_recursive on;
EOF

  # 检查下载是否成功（防止由于网络问题导致配置文件被清空）
  if [ $(grep -c "set_real_ip_from" $1) -le 10 ]; then
    echo -e "${ERROR} 获取的 IP 数量异常，请检查网络连接。"
    cat /dev/null > $1
  fi
}

install_acme() {
  [ -f /usr/local/acme.sh/acme.sh ] && return 0

  cd ${HOME}/nginx
  if env | grep -q SUDO; then
    acme_sh_sudo="-f"
  fi
  git clone --depth 1 https://github.com/acmesh-official/acme.sh.git
  cd ./acme.sh
  ./acme.sh --install ${acme_sh_sudo} --log \
            --home /usr/local/acme.sh/ \
            --certhome /usr/local/nginx/conf/ssl \
            --accountemail "$email_address"
  cd -
  rm -rf acme.sh
}

check_nginx()
{
  echo "============================== Check install =============================="
  echo "Checking ..."
  if [[ -s /usr/local/nginx/conf/nginx.conf && -s /usr/local/nginx/sbin/nginx ]]; then
    systemctl daemon-reload
    systemctl enable --now nginx.service
    echo -e "${INFO} Nginx: OK"
    nginx -V 2>&1 | sed 's|--|\n--|g'
    reminder
  else
    echo -e "${ERROR} Nginx install failed."
  fi
}

reminder() {
  echo "Nginx webs dir: ${websites_path}"
  echo "Nginx logs dir: ${web_logs_path}"
  echo "HTTP Basic Authentication file: $(cd ${websites_path}/.. && pwd)/.passwd"
  [ "${nginx_geoip}" = 'y' ] && echo "Ensure that you have downloaded Maxmind GeoLite2 Database file."
}

install() {
  print_version
  determine_path
  read_parameters
  echo -e "[Starting time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_START=$(date +%s)
  add_user
  download_nginx
  download_nginx_dependency
  build_luajit
  make_nginx
  conf_nginx
  install_acme
  check_nginx
  echo -e "[End time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_END=$(date +%s)
  echo -e "${INFO} Successfully done! Command takes $((TIME_END-TIME_START)) seconds."
}

websites_path="${nginx_web_path:-/usr/local/nginx/html}"
web_logs_path="${nginx_logs_path:-/usr/local/nginx/logs}"

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

install 2>&1 | tee "${VT_log}/nginx.log"
