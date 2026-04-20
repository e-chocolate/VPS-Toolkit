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
  echo "|         VT-Init for Ubuntu Linux Server, Written by Echocolate         |"
  echo "+------------------------------------------------------------------------+"
  echo "|           A script to install the required packages on Linux           |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Version: 1.0.0  Last Updated: 2026-04-20                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                      https://repos.echocolate.xyz                      |"
  echo "+------------------------------------------------------------------------+"
  sleep 2
}

check_VT_INIT() {
  [ ! -f "${HOME}/VT-logs/VT_INIT_FLAG" ] && return 0
  return 1
}

check_parallel() {
  local MemTotal=$(awk '/MemTotal/ {printf( "%d\n", $2 / 1024 )}' /proc/meminfo)
  if [ "$MemTotal" -lt 2048 ]; then
    JOBS=2
  else
    JOBS=$(grep 'processor' /proc/cpuinfo | wc -l)
  fi
}

safe_make() {
  echo -e "${INFO} Start building ..."
  if ! make -j"${JOBS}"; then
    echo -e "${INFO} Parallel build failed, try serial build."
    make clean && make
  fi
  if [ $? -eq 0 ]; then
    make install
    return $?
  else
    echo -e "${ERROR} All build attempts failed."
    return 1
  fi
}

download() {
  local url="$1" file="$2" n=1 max_retries=3
  while [ $n -le $max_retries ]; do
    if wget -nv "$url" -O "$file"; then
      return 0
    fi
    sleep 2
    ((n++))
  done
  echo -e "${ERROR} Download $file failed!"
  return 1
}

install_packages() {
  apt-get update -y
  [[ $? -ne 0 ]] && apt-get update --allow-releaseinfo-change -y
  apt-get autoremove -y
  apt-get -fy install

  for packages in \
    build-essential \
    git autoconf automake libtool m4 make gcc g++ cmake \
    pkg-config \
    rsync \
    clang \
    libc6-dev \
    bzip2 unzip \
    libbz2-dev \
    libjpeg-dev \
    libpng-dev \
    zlib1g \
    zlib1g-dev \
    curl \
    libcurl3-gnutls \
    libcurl4-gnutls-dev \
    libcurl4-openssl-dev \
    libpcre3-dev \
    gzip \
    openssl libssl-dev \
    libexpat1-dev \
    libpcre2-dev \
    libldap2-dev \
    libsasl2-dev \
    libzip-dev \
    libsodium-dev \
    libc-client-dev \
    libkrb5-dev \
    bison re2c \
    libicu-dev \
    libxml2-dev \
    libsqlite3-dev \
    libwebp-dev \
    libonig-dev \
    libxslt1.1 libxslt1-dev \
    rsync clang libboost-all-dev \
    python3 python3-pip \
  ;
  do apt-get --no-install-recommends install -y $packages; done
}

install_dependency() {
  cd ${HOME}
  check_parallel
  echo -e "${INFO} Proc num: $JOBS"
  status=0
  install_libiconv
  install_mhash
  install_libmcrypt
  install_mcrypt
  install_freetype
  if [ $status -eq 0 ]; then
    # VPS-Toolkit Init Flag
    date -Iseconds > "${HOME}/VT-logs/VT_INIT_FLAG"
    echo -e "${INFO} All dependencies installed successfully."
  else
    echo -e "${ERROR} Failed to install some dependencies. Check '${HOME}/VT-logs/init.log' for details."
  fi
}

install_libiconv() {
  cd ${HOME}/init
  download "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-${libiconv_version}.tar.gz" "libiconv.tar.gz"
  [ $? -ne 0 ] && {
    ((status+=1))
    return 1
  }
  mkdir libiconv && tar zxf libiconv.tar.gz --strip-components=1 --directory=libiconv
  rm libiconv.tar.gz && cd libiconv

  ./configure --enable-static
  safe_make
  [ $? -ne 0 ] && {
    ((status+=1))
    echo -e "${ERROR} Failed to install libiconv."
  }

  cd -
}

install_mhash() {
  cd ${HOME}/init
  download "https://downloads.sourceforge.net/project/mhash/mhash/${mhash_version}/mhash-${mhash_version}.tar.bz2" "mhash.tar.bz2"
  [ $? -ne 0 ] && {
    ((status+=1))
    return 1
  }
  mkdir mhash && tar jxf mhash.tar.bz2 --strip-components=1 --directory=mhash
  rm mhash.tar.bz2 && cd mhash

  ./configure
  safe_make
  [ $? -ne 0 ] && {
    ((status+=1))
    echo -e "${ERROR} Failed to install mhash."
  }

  cd -

  ln -sf /usr/local/lib/libmhash.a         /usr/lib/libmhash.a
  ln -sf /usr/local/lib/libmhash.la        /usr/lib/libmhash.la
  ln -sf /usr/local/lib/libmhash.so        /usr/lib/libmhash.so
  ln -sf /usr/local/lib/libmhash.so.2      /usr/lib/libmhash.so.2
  ln -sf /usr/local/lib/libmhash.so.2.0.1  /usr/lib/libmhash.so.2.0.1
  ldconfig
}

install_libmcrypt() {
  cd ${HOME}/init
  download "https://downloads.sourceforge.net/project/mcrypt/Libmcrypt/${libmcrypt_verison}/libmcrypt-${libmcrypt_verison}.tar.gz" "libmcrypt.tar.gz"
  [ $? -ne 0 ] && {
    ((status+=1))
    return 1
  }
  mkdir libmcrypt && tar zxf libmcrypt.tar.gz --strip-components=1 --directory=libmcrypt
  rm -rf libmcrypt.tar.gz && cd libmcrypt

  ./configure
  safe_make
  [ $? -ne 0 ] && {
    ((status+=1))
    echo -e "${ERROR} Failed to install Libmcrypt."
  }

  ldconfig

  cd libltdl/

  ./configure --enable-ltdl-install
  safe_make
  [ $? -ne 0 ] && {
    ((status+=1))
    echo -e "${ERROR} Failed to install Libmcrypt/libltdl."
  }

  ln -sf /usr/local/lib/libmcrypt.la        /usr/lib/libmcrypt.la
  ln -sf /usr/local/lib/libmcrypt.so        /usr/lib/libmcrypt.so
  ln -sf /usr/local/lib/libmcrypt.so.4      /usr/lib/libmcrypt.so.4
  ln -sf /usr/local/lib/libmcrypt.so.4.4.8  /usr/lib/libmcrypt.so.4.4.8
  ldconfig

  cd -
  cd ..
}

install_mcrypt() {
  cd ${HOME}/init
  download "https://downloads.sourceforge.net/project/mcrypt/MCrypt/${mcrypt_version}/mcrypt-${mcrypt_version}.tar.gz" "mcrypt.tar.gz"
  [ $? -ne 0 ] && {
    ((status+=1))
    return 1
  }
  mkdir mcrypt && tar zxf mcrypt.tar.gz --strip-components=1 --directory=mcrypt
  rm mcrypt.tar.gz && cd mcrypt

  ./configure
  safe_make
  [ $? -ne 0 ] && {
    ((status+=1))
    echo -e "${ERROR} Failed to install MCrypt."
  }

  cd -
}

install_freetype() {
  cd ${HOME}/init
  download "https://downloads.sourceforge.net/project/freetype/freetype2/${freetype_version}/freetype-${freetype_version}.tar.xz" "freetype.tar.xz"
  [ $? -ne 0 ] && {
    ((status+=1))
    return 1
  }
  mkdir freetype && tar Jxf freetype.tar.xz --strip-components=1 --directory=freetype
  rm freetype.tar.xz && cd freetype

  ./configure --prefix=/usr/local/freetype --enable-freetype-config
  safe_make
  [ $? -ne 0 ] && {
    ((status+=1))
    echo -e "${ERROR} Failed to install freetype2."
  }

  cd -

  \cp /usr/local/freetype/lib/pkgconfig/freetype2.pc /usr/lib/pkgconfig/
  echo "/usr/local/freetype/lib" > /etc/ld.so.conf.d/freetype.conf

  ldconfig
  ln -sf /usr/local/freetype/include/freetype2/* /usr/include/
}

check_kernel() {
  echo "=== 共享内存 ==="
  echo "shmmax: $(cat /proc/sys/kernel/shmmax)"
  echo "shmall: $(cat /proc/sys/kernel/shmall)"

  echo -e "\n=== 网络参数 ==="
  echo "somaxconn: $(cat /proc/sys/net/core/somaxconn)"
  echo "tcp_max_syn_backlog: $(cat /proc/sys/net/ipv4/tcp_max_syn_backlog)"

  echo -e "\n=== 文件描述符 ==="
  echo "file-max: $(cat /proc/sys/fs/file-max)"
}

init() {
  libiconv_version="${libiconv_ver:-1.18}"
  mhash_version="${mhash_ver:-0.9.9.9}"
  libmcrypt_verison="${libmcrypt_ver:-2.5.8}"
  mcrypt_version="${mcrypt_ver:-2.6.8}"
  freetype_version="${freetype_ver:-2.14.1}"

  print_version
  echo -e "[Starting time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_START=$(date +%s)
  install_packages
  if ! check_VT_INIT; then
    echo -e "${INFO} Install dependency successfully at $(cat ${HOME}/VT-logs/VT_INIT_FLAG), skipping ..."
  else
    install_dependency
  fi
  echo -e "[End time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_END=$(date +%s)
  echo -e "${INFO} Successfully done! Command takes $((TIME_END-TIME_START)) seconds."
  check_kernel
}

[ -d "${HOME}/init" ] && mv ${HOME}/init ${HOME}/init-$(date +'%Y-%m-%d')
[ ! -d "${HOME}/init" ] && mkdir ${HOME}/init
[ ! -d "${HOME}/VT-logs" ] && mkdir ${HOME}/VT-logs

init 2>&1 | tee ${HOME}/VT-logs/init.log
