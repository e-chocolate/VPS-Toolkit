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
  echo "|      VT-Transmission for Debian like Linux, Written by Echocolate      |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Scripts to install Transmission on Linux                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Version: 1.0.0  Last Updated: 2026-06-14                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                      https://repos.echocolate.xyz                      |"
  echo "+------------------------------------------------------------------------+"
  sleep 2
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

mkdir_not_exists() {
  if [ ! -d $1 ]; then
    mkdir -p $1
  fi
}

enter_parameters() {
  # 需要用户手动设置的参数
  echo -en "\e[0;33mRunning transmission-daemon with another user(y/n, default n): \e[0m"
  read choose_transmission_daemon_user

  if [ ! -z $choose_transmission_daemon_user ] && [ $choose_transmission_daemon_user = 'y' ]; then
    echo -en "\e[0;33mInput the user that will run transmission-daemon: \e[0m"
    read my_transmission_daemon_user
    if [ ! -z $my_transmission_daemon_user ]; then
      id $my_transmission_daemon_user
      [ $? -ne 0 ] && {
        echo -e "${ERROR} Invaild user. Use 'debian-transmission' as default."
        my_transmission_daemon_user='debian-transmission'
      }
      my_download_dir="/home/$my_transmission_daemon_user/transmission"
    fi
  fi

  [ -z $my_transmission_daemon_user ] && my_transmission_daemon_user='debian-transmission'

  echo -en "\e[0;33mEanble incomplete directory(y/n, default n): \e[0m"
  read my_incomplete_dir_enabled

  echo -en "\e[0;33mEnter transmission high peer port: \e[0m"
  read my_peer_port_random_high

  echo -en "\e[0;33mEnter transmission low peer port: \e[0m"
  read my_peer_port_random_low

  echo -en "\e[0;33mEnter transmission rpc port: \e[0m"
  read my_rpc_port

  echo -en "\e[0;33mSet rpc username: \e[0m"
  read my_rpc_username
  
  echo -en "\e[0;33mEnable DIY Web Control(y/n, default n): \e[0m"
  read my_web_control
}

install_transmission() {
  for packages in \
    jq unzip \
    transmission-daemon \
  ;
  do apt-get --no-install-recommends install -y $packages; done
  sleep 2
  systemctl stop transmission-daemon
}

update_service() {
  echo "Updating transmission-daemon service file."
  echo -e "Check \e[0;32mhttps://github.com/transmission/transmission/issues/6991\e[0m for more info."
  sed -i 's|Type=notify|Type=simple|g' /usr/lib/systemd/system/transmission-daemon.service
}

diy_parameters() {
  # alt-speed-up/down 是备用时段限速
  alt_speed_down=$(jq '.["alt-speed-down"]' $deafult_transmission_config_file)
  alt_speed_time_begin=$(jq '.["alt-speed-time-begin"]' $deafult_transmission_config_file)
  alt_speed_time_day=$(jq '.["alt-speed-time-day"]' $deafult_transmission_config_file)
  # alt_speed_time_enabled=$(jq '.["alt-speed-time-enabled"]' $deafult_transmission_config_file)
  alt_speed_time_enabled='true'
  alt_speed_time_end=$(jq '.["alt-speed-time-end"]' $deafult_transmission_config_file)
  alt_speed_up=$(jq '.["alt-speed-up"]' $deafult_transmission_config_file)
  # 是否启用防暴力破解
  # anti_brute_force_enabled=$(jq '.["anti-brute-force-enabled"]' $deafult_transmission_config_file)
  anti_brute_force_enabled='true'
  # 允许失败次数
  # anti_brute_force_threshold=$(jq '.["anti-brute-force-threshold"]' $deafult_transmission_config_file)
  anti_brute_force_threshold='10'
  # 是否启用 IP 黑名单
  # blocklist_enabled=$(jq '.["blocklist-enabled"]' $deafult_transmission_config_file)
  blocklist_enabled='true'
  # 黑名单网址
  # blocklist_url=$(jq '.["blocklist-url"]' $deafult_transmission_config_file)
  blocklist_url='"https://raw.githubusercontent.com/Naunter/BT_BlockLists/master/bt_blocklists.gz"'
  # 缓存大小
  cache_size_mb='16'
  # 不少PT站要求关闭DHT功能，默认开启该功能
  dht_enabled=$(jq '.["dht-enabled"]' $deafult_transmission_config_file)
  # 已完成下载的 torrent 文件的默认保存目录
  download_dir=$(jq -r '.["download-dir"]' $deafult_transmission_config_file)
  # 做种任务的最大空闲时间（分钟）
  # idle_seeding_limit=$(jq '.["idle-seeding-limit"]' $deafult_transmission_config_file)
  idle_seeding_limit=30
  # 是否启用“空闲做种超时”功能
  # idle_seeding_limit_enabled=$(jq '.["idle-seeding-limit-enabled"]' $deafult_transmission_config_file)
  idle_seeding_limit_enabled='true'
  # 未完成下载的临时文件存放目录
  incomplete_dir=$(jq -r '.["incomplete-dir"]' $deafult_transmission_config_file)
  # 是否启用未完成文件的独立目录
  incomplete_dir_enabled=$(jq '.["incomplete-dir-enabled"]' $deafult_transmission_config_file)
  # 是否启用 Local Peer Discovery (LPD)，即局域网内的 peer 自动发现
  # lpd_enabled=$(jq '.["lpd-enabled"]' $deafult_transmission_config_file)
  lpd_enabled='false'
  # 日志 0:无日志, 1:error, 2:info, 3:debug
  message_level=$(jq '.["message-level"]' $deafult_transmission_config_file)
  # [Deprecated] A setting for how long your Transmission client's unique Peer ID remains valid before being regenerated.
  # peer-id-ttl-hours=6
  # Transmission 监听 BitTorrent 协议连接的端口
  peer_port=$(jq '.["peer-port"]' $deafult_transmission_config_file)
  # 启用随机端口时，可用的端口范围上限
  peer_port_random_high=$(jq '.["peer-port-random-high"]' $deafult_transmission_config_file)
  # 启用随机端口时，可用的端口范围下限
  peer_port_random_low=$(jq '.["peer-port-random-low"]' $deafult_transmission_config_file)
  # 是否在每次启动 Transmission 时随机选择一个 peer 端口
  # peer_port_random_on_start=$(jq '.["peer-port-random-on-start"]' $deafult_transmission_config_file)
  peer_port_random_on_start='true'
  # 设置 peer socket 的 Type of Service (ToS) 或 Differentiated Services Code Point (DSCP) 值
  # default:操作系统默认, mincost/lowcost: 最小开销, reliability:高可靠性, throughput:高吞吐, le/lowdelay:低延迟
  peer_socket_tos=$(jq '.["peer-socket-tos"]' $deafult_transmission_config_file)
  # 分享率上限
  # ratio_limit=$(jq '.["ratio-limit"]' $deafult_transmission_config_file)
  ratio_limit=2
  # 是否启用“分享率上限”限制
  # ratio_limit_enabled=$(jq '.["ratio-limit-enabled"]' $deafult_transmission_config_file)
  ratio_limit_enabled='true'
  # 是否在下载过程中给未完成文件加上 `.part` 后缀
  # rename_partial_files=$(jq '.["rename-partial-files"]' $deafult_transmission_config_file)
  rename_partial_files='true'
  # Web UI（RPC 接口）监听的 IP 地址
  # rpc_bind_address=$(jq '.["rpc-bind-address"]' $deafult_transmission_config_file)
  rpc_bind_address='"127.0.0.1"'
  # 允许的 Host 值列表（逗号分隔）
  # rpc_host_whitelist=$(jq '.["rpc-host-whitelist"]' $deafult_transmission_config_file)
  rpc_host_whitelist='"localhost,127.0.0.1"'
  # 是否启用 Host 白名单
  # rpc_host_whitelist_enabled=$(jq '.["rpc-host-whitelist-enabled"]' $deafult_transmission_config_file)
  rpc_host_whitelist_enabled='true'
  # Web UI 登录密码（会被加密存储）
  # rpc_password=$(jq '.["rpc-password"]' $deafult_transmission_config_file)
  rpc_password=''
  # Web UI 的监听端口
  rpc_port=$(jq '.["rpc-port"]' $deafult_transmission_config_file)
  # Web UI 登录用户名
  rpc_username=$(jq '.["rpc-username"]' $deafult_transmission_config_file)
  # 允许通过 RPC 连接的客户端 IP 地址
  # rpc_whitelist=$(jq '.["rpc-whitelist"]' $deafult_transmission_config_file)
  rpc_whitelist='"127.0.0.1"'
  # 是否启用 RPC 访问 IP 白名单
  # rpc_whitelist_enabled=$(jq '.["rpc-whitelist-enabled"]' $deafult_transmission_config_file)
  rpc_whitelist_enabled='true'
  # speed-limit-* 是主时段限速
  # speed_limit_down=$(jq '.["speed-limit-down"]' $deafult_transmission_config_file)
  speed_limit_down=250
  # speed_limit_down_enabled=$(jq '.["speed-limit-down-enabled"]' $deafult_transmission_config_file)
  speed_limit_down_enabled='true'
  # speed_limit_up=$(jq '.["speed-limit-up"]' $deafult_transmission_config_file)
  speed_limit_up=100
  # speed_limit_up_enabled=$(jq '.["speed-limit-up-enabled"]' $deafult_transmission_config_file)
  speed_limit_up_enabled='true'
  echo "Setting transmission-daemon settings parameters."
  echo -e "Check \e[0;32mhttps://github.com/transmission/transmission/blob/main/docs/Editing-Configuration-Files.md\e[0m for more info."
}

generate_jq_filter() {
  [ ! -z $my_download_dir ] && download_dir=$my_download_dir

  if [ ! -z $my_incomplete_dir_enabled ] && [ $my_incomplete_dir_enabled = 'y' ]; then
    incomplete_dir_enabled='true'
    incomplete_dir="${download_dir}/cache"
  fi

  if [ ! -z $my_peer_port_random_high ] && [ ! -z $my_peer_port_random_low ]; then
    if [ $my_peer_port_random_high -le $my_peer_port_random_low ]; then
      echo -e "${ERROR}'peer_port_random_high' must bigger than 'peer_port_random_low', use default ports."
    else
      peer_port=$my_peer_port_random_high
      peer_port_random_high=$my_peer_port_random_high
      peer_port_random_low=$my_peer_port_random_low
    fi
  fi

  [ ! -z $my_rpc_port ] && rpc_port=$my_rpc_port

  if [ -z $my_rpc_username ] || [ $my_rpc_username = '' ]; then
    rpc_username=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 4)
  else
    rpc_username=$my_rpc_username
  fi
  rpc_password=$(tr -dc 'A-Za-z0-9@%^&_+-=' < /dev/urandom | head -c 12)

  # 更新多个字段
  cat > /tmp/filter.jq <<EOF
  ."alt-speed-down" = $alt_speed_down |
  ."alt-speed-time-begin" = $alt_speed_time_begin |
  ."alt-speed-time-day" = $alt_speed_time_day |
  ."alt-speed-time-enabled" = $alt_speed_time_enabled |
  ."alt-speed-time-end" = $alt_speed_time_end |
  ."alt-speed-up" = $alt_speed_up |
  ."anti-brute-force-enabled" = $anti_brute_force_enabled |
  ."anti-brute-force-threshold" = $anti_brute_force_threshold |
  ."blocklist-enabled" = $blocklist_enabled |
  ."blocklist-url" = $blocklist_url |
  ."cache-size-mb" = $cache_size_mb |
  ."dht-enabled" = $dht_enabled |
  ."download-dir" = "$download_dir" |
  ."idle-seeding-limit" = $idle_seeding_limit |
  ."idle-seeding-limit-enabled" = $idle_seeding_limit_enabled |
  ."incomplete-dir" = "$incomplete_dir" |
  ."incomplete-dir-enabled" = $incomplete_dir_enabled |
  ."lpd-enabled" = $lpd_enabled |
  ."message-level" = $message_level |
  ."peer-port" = $peer_port |
  ."peer-port-random-high" = $peer_port_random_high |
  ."peer-port-random-low" = $peer_port_random_low |
  ."peer-port-random-on-start" = $peer_port_random_on_start |
  ."peer-socket-tos" = $peer_socket_tos |
  ."ratio-limit" = $ratio_limit |
  ."ratio-limit-enabled" = $ratio_limit_enabled |
  ."rename-partial-files" = $rename_partial_files |
  ."rpc-bind-address" = $rpc_bind_address |
  ."rpc-host-whitelist" = $rpc_host_whitelist |
  ."rpc-host-whitelist-enabled" = $rpc_host_whitelist_enabled |
  ."rpc-password" = "$rpc_password" |
  ."rpc-port" = $rpc_port |
  ."rpc-username" = "$rpc_username" |
  ."rpc-whitelist" = $rpc_whitelist |
  ."rpc-whitelist-enabled" = $rpc_whitelist_enabled |
  ."speed-limit-down" = $speed_limit_down |
  ."speed-limit-down-enabled" = $speed_limit_down_enabled |
  ."speed-limit-up" = $speed_limit_up |
  ."speed-limit-up-enabled" = $speed_limit_up_enabled
EOF
}

configure_transmission() {
  if [ $my_transmission_daemon_user = 'debian-transmission' ]; then
    \cp -a $deafult_transmission_config_file "${deafult_transmission_config_file}.bk"
    my_settings_path='/etc/transmission-daemon'
    jq -f /tmp/filter.jq "${deafult_transmission_config_file}.bk" > "$my_settings_path/settings.json"
  else
    mkdir_not_exists "/home/$my_transmission_daemon_user/.config/transmission"
    chown -R $my_transmission_daemon_user:$my_transmission_daemon_user /home/$my_transmission_daemon_user/.config/transmission
    \cp -a $deafult_transmission_config_file /home/$my_transmission_daemon_user/.config/transmission/settings.json
    my_settings_path="/home/$my_transmission_daemon_user/.config/transmission"
    jq -f /tmp/filter.jq $deafult_transmission_config_file > "$my_settings_path/settings.json"
    sed -i "s|User=.*|User=$my_transmission_daemon_user|g" /usr/lib/systemd/system/transmission-daemon.service
    sed -i "s|ExecStart=/usr/bin/transmission-daemon|ExecStart=/usr/bin/transmission-daemon -g $my_settings_path|g" /usr/lib/systemd/system/transmission-daemon.service
  fi
  rm -f /tmp/filter.jq
  chown $my_transmission_daemon_user:$my_transmission_daemon_user "$my_settings_path/settings.json"

  mkdir_not_exists $download_dir
  chown -R $my_transmission_daemon_user:$my_transmission_daemon_user $download_dir

  mkdir_not_exists $incomplete_dir
  chown -R $my_transmission_daemon_user:$my_transmission_daemon_user $incomplete_dir
}

getTransmissionPath() {
  # 这个函数的代码来自项目 https://github.com/ronggang/transmission-web-control/raw/master/release/install-tr-control-cn.sh
  # 指定一次当前系统的默认目录，存在则避免搜索所有目录
  ROOT_FOLDER="/usr/local/transmission/share/transmission"
  # Fedora 或 Debian 发行版的默认 ROOT_FOLDER 目录
  if [ ! -d "$ROOT_FOLDER" ]; then
    if [ -f "/etc/fedora-release" ] || [ -f "/etc/debian_version" ] || [ -f "/etc/openwrt_release" ]; then
      ROOT_FOLDER="/usr/share/transmission"
    fi

    if [ -f "/bin/freebsd-version" ]; then
      ROOT_FOLDER="/usr/local/share/transmission"
    fi

    # 群晖
    if [ -f "/etc/synoinfo.conf" ]; then
      ROOT_FOLDER="/var/packages/transmission/target/share/transmission"
    fi
  fi

  if [ ! -d "$ROOT_FOLDER" ]; then
    infos=`ps -Aww -o command= | sed -r -e '/[t]ransmission-da/!d' -e 's/ .+//'`
    if [ "$infos" != "" ]; then
      echo " √"
      search="bin/transmission-daemon"
      replace="share/transmission"
      path=${infos//$search/$replace}
      if [ -d "$path" ]; then
        ROOT_FOLDER=$path
      fi
    else
      echo " × 识别失败，请确认 Transmission 已启动。"
      return 1
    fi
  fi
}

download_latest_web() {
  # 更多第三方 Web Control 可以参考 https://transmissionbt.com/addons
  local repo_name='openscopeproject/TrguiNG'
  local version=$(curl -fsSLI -o /dev/null -w "%{url_effective}" https://github.com/${repo_name}/releases/latest | sed "s|https://github.com/${repo_name}/releases/tag/||g")
  URL="https://github.com/${repo_name}/releases/download/$version/trguing-web-$version.zip"
  FILE="trguing-web-$version.zip"
  curl -#fL -o "/tmp/$FILE" -C - "$URL"
}

set_tr_web() {
  getTransmissionPath
  if [ $? -ne 0 ]; then
    return 1
  fi
  WEB_FOLDER="$ROOT_FOLDER/web"
  rm -rf $WEB_FOLDER
  mkdir_not_exists $WEB_FOLDER
  unzip -o "/tmp/$FILE" -d $WEB_FOLDER
  rm -f "/tmp/$FILE"
}

print_configuration() {
  printf "\e[0;32m%-20s : %s\n\e[0m" 'parameter' 'value'
  printf "%-20s : %s\n" "rpc-username" $rpc_username
  printf "%-20s : %s\n" "rpc-password" $rpc_password
  printf "%-20s : %s\n" "rpc-port" $rpc_port
}

install() {
  detect_os
  [ $? -ne 0 ] && {
    echo -e "${ERROR} Only support Ubuntu and Debian."
    exit 1
  }
  enter_parameters
  echo -e "[Starting time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_START=$(date +%s)
  install_transmission
  # Only for Ubuntu to avoid the issue
  [ ${os} = 'Ubuntu' ] && update_service
  diy_parameters
  generate_jq_filter
  configure_transmission
  if [ ! -z $my_web_control ] && [ $my_web_control = 'y' ]; then
    download_latest_web
    set_tr_web
    sed -i "s|\[Service\]|[Service]\nEnvironment=TRANSMISSION_WEB_HOME=\"$WEB_FOLDER\"|g" /usr/lib/systemd/system/transmission-daemon.service
  fi
  systemctl daemon-reload && systemctl start transmission-daemon
  print_configuration
  echo -e "[End time: `date +'%Y-%m-%d %H:%M:%S'`]"
  TIME_END=$(date +%s)
  echo -e "${INFO} Successfully done! Command takes $((TIME_END-TIME_START)) seconds."
}

VT_HOME="${HOME}/VT-Data"
VT_log="${VT_HOME}/logs"
mkdir_not_exists "${VT_log}"

deafult_transmission_config_file="/etc/transmission-daemon/settings.json"
install 2>&1 | tee "${VT_log}/transmission.log"
