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

print_version() {
  detect_os
  clear
  echo "+------------------------------------------------------------------------+"
  echo "|      VT-System-Init for Debian like Linux, Written by Echocolate       |"
  echo "+------------------------------------------------------------------------+"
  echo "|              A script to configure the newly deployed VPS              |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Version: 1.0.3  Last Updated: 2026-05-21                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                      https://repos.echocolate.xyz                      |"
  echo "+------------------------------------------------------------------------+"
  printf "%s %36s%-12s%24s\n" "|" "Your OS: " "$os" "|"
  echo "+------------------------------------------------------------------------+"
  sleep 2
}

detect_os() {
  if [ -f /etc/os-release ]; then
    source /etc/os-release
    case "$ID" in
      ubuntu) os='Ubuntu' ;;
      debian) os='Debian' ;;
      *)      os="Unknown distribution: $ID" ;;
    esac
  else
    os="Unknown"
  fi
}

update() {
  apt-get update -q

  apt-get upgrade -y -q \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"

  apt-get autoremove -y -q
  apt-get clean -q
  [ "$os"='Debian' ] && apt-get install curl fuse3 git
}

add_non_root_user() {
  [ -z "${non_root_user}" ] && {
    echo -e "${ERROR} Invaild username."
    return 1
  }
  if id "${non_root_user}" >/dev/null 2>&1; then
    echo -e "${INFO} User ${non_root_user} already exists."
  else
    useradd -m -U -s /bin/bash "${non_root_user}"
  fi
  [ "$os"='Debian' ] && echo -e '\n# set PATH for normal user\nPATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH"' >> /home/${non_root_user}/.profile
  cat > /etc/sudoers.d/normal-users <<EOF
# User privilege specification
${non_root_user}	ALL=(ALL:ALL) ALL
EOF
}

configure_sshd() {
  [ -z "${ssh_port}" ] && ssh_port='22'
  cat > /etc/ssh/sshd_config.d/custom_sshd.conf << EOF
Port ${ssh_port}
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
EOF
}

add_swap() {
  [ "${enable_swap}" = 'n' ] && return 0
  local MemTotal=$(free -m | awk '/^Mem:/ {print $2}')
  local Disk_Avail=$(df -mP /var | awk 'NR==2 {print int($4/1024)}')
  local Swap_Total=$(free -m | awk '/^Swap:/ {print $2}')

  # 判断空闲空间是否足够
  local DD_Count=1024
  local Req_Disk=5
  if [[ "${MemTotal}" -ge 16384 ]]; then
    DD_Count=8192; Req_Disk=27
  elif [[ "${MemTotal}" -ge 4096 ]]; then
    DD_Count=8192; Req_Disk=19
  elif [[ "${MemTotal}" -ge 2048 ]]; then
    DD_Count=4096; Req_Disk=17
  elif [[ "${MemTotal}" -ge 1024 ]]; then
    DD_Count=2048; Req_Disk=13
  fi

  # 空间不足
  if [[ "${Disk_Avail}" -lt "${Req_Disk}" ]]; then
    echo -e "${ERROR} Need more space for swapfile!"
    return 1
  fi

  # swap 分区或文件存在则
  if [[ "${Swap_Total}" -gt 512 ]] || [[ -s /swapfile ]]; then
    echo -e "${INFO} No need to create swapfile, skip..."
    return 0
  fi

  dd if=/dev/zero of=/swapfile bs=1M count=${DD_Count} status=none
  chmod 0600 /swapfile

  # 格式化 Swap
  if /sbin/mkswap /swapfile >/dev/null 2>&1; then
    cp -a /etc/fstab /etc/fstab.bk
    grep -q '^\s*/swapfile' /etc/fstab || echo "/swapfile none swap defaults 0 0" >> /etc/fstab
    echo "Swap Added Successfully!"
  else
    rm -f /swapfile
    echo "Add Swap Failed!"
  fi
}

firewall() {
  [ "${enable_nftables}" != 'y' ] && return 0
  uninstall_ufw
  install_nftables
}

uninstall_ufw() {
  if command -v ufw >/dev/null 2>&1; then
    ufw status verbose > /root/logs/ufw_status_backup_$(date +%F).txt 2>/dev/null
    ufw disable
    ufw --force reset
    apt-get purge -y -q ufw
    rm -rf /etc/ufw
    echo -e "${INFO} UFW successfully removed. System is ready for nftables."
  else
    echo -e "${INFO} UFW is not installed. Skip..."
  fi
}

install_nftables() {
  if ! command -v nft >/dev/null 2>&1; then
    apt-get install -y -q \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      nftables
  fi

  configure_nftables
  [ "${nftables_cdn_mode}" = '2' ] && configure_nftables_cloudflare

  [ "${nftables_ssh_mode}" = '1' ] && {
    sed -i 's|\([[:space:]]\)# \(ip saddr.*counter.*\)|\1\2|g' /etc/nftables.conf
  } || {
    sed -i 's|\([[:space:]]\)# \(.*ct state new limit.*\)|\1\2|g' /etc/nftables.conf
  }

  [ "${nftables_mail_mode}" = 'y' ] && {
    sed -i '/{mail_rule}/c\
        # 邮件服务\
        tcp dport { 25, 587, 465, 993, 995 } counter accept\n' /etc/nftables.conf
  } || {
    sed -i '/{mail_rule}/d' /etc/nftables.conf
  }

  [ "${nftables_docker_mode}" = 'y' ] && {
    sed -i '/{docker_vars}/c\
# ==========================================\
# 定义网卡变量，方便维护\
# ==========================================\
define WAN_IF = "eth0"                    # 网卡名称\
define DOCKER_IFS = { "docker0", "br-*" } # Docker 默认网桥和自定义网桥\n' /etc/nftables.conf

    sed -i '/{docker_chain}/c\
    chain docker_defense {\
        # 优先级 -1 保证在 Docker (0) 之前进行拦截检查\
        type filter hook forward priority -1; policy accept;\
\
        # 允许已建立的连接\
        ct state established,related accept\
\
        # 允许 Docker 容器主动访问公网 (容器上网)\
        iifname $DOCKER_IFS oifname $WAN_IF accept\
\
        # 允许 Docker 内部的各个容器互相通信\
        iifname $DOCKER_IFS oifname $DOCKER_IFS accept\
\
        # ----------------------------------------------------\
        # 【白名单】\
        # 注意：这里放行的是容器的“内部端口”，而不是外网映射端口！\
        # 示例：如果你运行了 `docker run -p 8080:80 nginx`\
        # iifname $WAN_IF oifname $DOCKER_IFS tcp dport 80 accept\
        # ----------------------------------------------------\
\
        # 默认禁止所有其他从公网企图进入 Docker 的未经授权流量\
        iifname $WAN_IF oifname $DOCKER_IFS log prefix "NFT-DOCKER-BLOCK: " drop\
    }\n' /etc/nftables.conf

    sed -i 's|\([[:space:]]*\# \)默认策略：拦截转发流量$|\1forward 流量必须允许，否则 Docker 无法正常运行|g' /etc/nftables.conf
    sed -i 's|\([[:space:]]*\)type filter hook forward priority filter; policy drop;$|\1type filter hook forward priority filter; policy accept;|g' /etc/nftables.conf
  } || {
    sed -i '/{docker_chain}/d' /etc/nftables.conf
    sed -i '/{docker_vars}/d'  /etc/nftables.conf
  }

  nft -c -f /etc/nftables.conf
  [ $? -eq 0 ] && {
    nft -f /etc/nftables.conf
    systemctl enable nftables
    systemctl restart nftables
  } || echo -e "${ERROR} invaild nftables config"
}

configure_nftables() {
cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f

# 清理当前所有规则
flush ruleset

{docker_vars}
table inet filter {
    chain input {
        # 默认策略：拦截所有入站流量 (白名单模式)
        type filter hook input priority filter; policy drop;

        # 基础规则
        ct state established,related accept    # 允许已建立的连接
        ct state invalid drop                  # 丢弃无效包
        iifname "lo" accept                    # 允许本地回环

        # 允许 IPv6 NDP，否则 IPv6 无法正常通信
        icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert } accept

        # 允许 ICMP (Ping) - 方便网络诊断
        icmp type echo-request limit rate 4/second accept
        icmpv6 type echo-request limit rate 4/second accept

        # 仅允许从信任 IP 访问 SSH 端口
        # ip saddr ${ssh_allow_ip} tcp dport ${ssh_port} ct state new counter accept
        # 开放 SSH 端口
        # tcp dport ${ssh_port} ct state new limit rate 3/minute burst 5 packets counter accept

        # 允许 HTTP (80) 和 HTTPS (443)
        tcp dport { 80, 443 } ct state new counter accept
        # 若启用 HTTP/3 (QUIC)，需额外放行 UDP 443
        udp dport 443 ct state new limit rate 50/second burst 100 packets counter accept

        {mail_rule}
        # (可选) 记录并限速拦截其他所有非法入站请求
        limit rate 3/minute counter log prefix "nftables-DENIED: " drop
    }

{docker_chain}
    chain forward {
        # 默认策略：拦截转发流量
        type filter hook forward priority filter; policy drop;
    }

    chain output {
        # 默认策略：允许所有出站流量
        type filter hook output priority filter; policy accept;
    }
}
EOF
}

configure_nftables_cloudflare() {
cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f

# 清理当前所有规则
flush ruleset

{docker_vars}
table inet filter {
    # ============================================================
    # Cloudflare IP 集合
    # ============================================================
    set cloudflare_v4 {
        type ipv4_addr; flags interval;
        elements = {
            173.245.48.0/20,
            103.21.244.0/22,
            103.22.200.0/22,
            103.31.4.0/22,
            141.101.64.0/18,
            108.162.192.0/18,
            190.93.240.0/20,
            188.114.96.0/20,
            197.234.240.0/22,
            198.41.128.0/17,
            162.158.0.0/15,
            104.16.0.0/13,
            104.24.0.0/14,
            172.64.0.0/13,
            131.0.72.0/22
        }
    }

    set cloudflare_v6 {
        type ipv6_addr; flags interval;
        elements = {
            2400:cb00::/32,
            2606:4700::/32,
            2803:f800::/32,
            2405:b500::/32,
            2405:8100::/32,
            2a06:98c0::/29,
            2c0f:f248::/32
        }
    }

    chain input {
        # 默认策略：拦截所有入站流量 (白名单模式)
        type filter hook input priority filter; policy drop;

        # 基础规则
        ct state established,related accept    # 允许已建立的连接
        ct state invalid drop                  # 丢弃无效包
        iifname "lo" accept                    # 允许本地回环

        # 允许 IPv6 NDP，否则 IPv6 无法正常通信
        icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert } accept

        # 允许 ICMP (Ping) - 方便网络诊断
        icmp type echo-request limit rate 4/second accept
        icmpv6 type echo-request limit rate 4/second accept

        # 仅允许从信任 IP 访问 SSH 端口
        # ip saddr ${ssh_allow_ip} tcp dport ${ssh_port} ct state new counter accept
        # 开放 SSH 端口
        # tcp dport ${ssh_port} ct state new limit rate 3/minute burst 5 packets counter accept

        # 仅限 Cloudflare IP 段访问 80/443, QUIC
        ip saddr @cloudflare_v4 tcp dport { 80, 443 } ct state new counter accept
        ip6 saddr @cloudflare_v6 tcp dport { 80, 443 } ct state new counter accept
        ip saddr @cloudflare_v4 udp dport 443 ct state new counter accept
        ip6 saddr @cloudflare_v6 udp dport 443 ct state new counter accept

        {mail_rule}
        # (可选) 记录并限速拦截其他所有非法入站请求
        limit rate 3/minute counter log prefix "nftables-DENIED: " drop
    }

{docker_chain}
    chain forward {
        # 默认策略：拦截转发流量
        type filter hook forward priority filter; policy drop;
    }

    chain output {
        # 默认策略：允许所有出站流量
        type filter hook output priority filter; policy accept;
    }
}
EOF
}

reminder() {
  [ "${enable_nftables}" = 'y' ] && {
    systemctl status nftables --no-pager | grep Active
    nft list ruleset
  }
  echo -e "${INFO} Remember to use \`passwd\` && \`passwd ${non_root_user}\` to change the password."
}

read_env() {
  # 从环境变量或者用户输入确定要配置的参数值
  # 用户名
  [ -z "${non_root_user}" ] && read -p 'enter the non_root_username: ' non_root_user
  # ssh 端口
  [ -z "${ssh_port}" ] && read -p 'enter the ssh port (default 22): ' ssh_port
  # 开启 swap
  [ -z "${enable_swap}" ] && read -p 'enable swap or not (y/n, default y): ' -n1 enable_swap
  echo
  # 启用 nftables
  [ -z "${enable_nftables}" ] && read -p 'Use nftables as default firewall (y/n, default n): ' -n1 enable_nftables
  echo
  [ "${enable_nftables}" = 'y' ] && {
    # ssh 白名单
    read -p 'Enter the client IP address authorized for SSH access (default 0.0.0.0/0): ' ssh_allow_ip
    check_ipv4 && nftables_ssh_mode='1' || {
      echo -e "${ERROR} Invaild IP, use default IP."
      nftables_ssh_mode='2'
      ssh_allow_ip='1.1.1.1'
    }
    echo -e "There are 2 ntfables mode:\n1. Allow http && https from all ip.\n2. Just allow http && https from cloudflare ip."
    read -p 'Enter nftables mode (1/2, default 1): ' -n1 nftables_cdn_mode
    echo
    read -p 'Will you use this machine as a mail server? (y/n, default n): ' -n1 nftables_mail_mode
    echo
    read -p 'Will you use Docker on this system in the future? Your answer will determine how nftables is configured to avoid rule conflicts. (y/n, default n): ' -n1 nftables_docker_mode
    echo
  }
}

check_ipv4() {
  echo "${ssh_allow_ip}" | awk -F. '{
    if (NF != 4) exit(1);
    for (i = 1; i <= NF; i++) {
      if ($i !~ /^[0-9]{1,3}$/) exit(1);
      if (length($i) > 1 && $i ~ /^0/) exit(1);
      if ($i < 0 || $i > 255) exit(1);
    }
  }'
  return $?
}

sys_init() {
  print_version
  read_env
  update
  add_non_root_user
  configure_sshd
  add_swap
  firewall
  reminder
}

sys_init
