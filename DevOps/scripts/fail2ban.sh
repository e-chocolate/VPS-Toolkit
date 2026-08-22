#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# Check if user is root
if [ $(id -u) != "0" ]; then
  echo "Error: You must be root to run this script"
  exit 1
fi

INFO="\e[0;32m[INFO]\e[0m"
ERROR="\e[0;31m[ERROR]\e[0m"

jail_path='/etc/fail2ban/jail.d'
filter_path='/etc/fail2ban/filter.d'

print_version() {
  clear
  echo "+------------------------------------------------------------------------+"
  echo "|        VT-fail2ban for Debian like Linux, Written by Echocolate        |"
  echo "+------------------------------------------------------------------------+"
  echo "|       Scripts to install fail2ban and add nginx filters on Linux       |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Version: 1.0.0  Last Updated: 2026-08-22                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                      https://repos.echocolate.xyz                      |"
  echo "+------------------------------------------------------------------------+"
  sleep 2
}

enter_info() {
  read -p $'\e[0;33mEnable diy nginx filters (y/n, default n): \e[0m' -n1 nginx_filter
  echo

  whitelists=()
  echo "Input whitelist IPv4 (one per line), press Ctrl+D when done:"
  while read -r whitelist; do
    [[ -n "$whitelist" ]] && whitelists+=("$whitelist")
  done
  local n=${#whitelists[@]}
  echo -e "${INFO} Received ${#whitelists[@]} IPv4."
  echo "Input whitelist IPv6 (one per line), press Ctrl+D when done:"
  while read -r whitelist; do
    [[ -n "$whitelist" ]] && whitelists+=("$whitelist")
  done
  echo -e "${INFO} Received $((${#whitelists[@]} - $n)) IPv6."
}

install_fail2ban() {
  for packages in \
    fail2ban \
    python3-systemd \
    python3-pyinotify \
  ;
  do apt-get --no-install-recommends install -y $packages; done
  [ ! -d "${jail_path}" ] && mkdir -p "${jail_path}"
  [ ! -d "${filter_path}" ] && mkdir -p "${filter_path}"
  systemctl enable fail2ban
}

backup_nginx_filter() {
  [ ! -f "${filter_path}/nginx-bad-request.conf.bk" ] && cp -a "${filter_path}/nginx-bad-request.conf" "${filter_path}/nginx-bad-request.conf.bk"
  [ ! -f "${filter_path}/nginx-botsearch.conf.bk" ]   && cp -a "${filter_path}/nginx-botsearch.conf" "${filter_path}/nginx-botsearch.conf.bk"
  [ ! -f "${filter_path}/nginx-http-auth.conf.bk" ]   && cp -a "${filter_path}/nginx-http-auth.conf" "${filter_path}/nginx-http-auth.conf.bk"
  [ ! -f "${filter_path}/nginx-limit-req.conf.bk" ]   && cp -a "${filter_path}/nginx-limit-req.conf" "${filter_path}/nginx-limit-req.conf.bk"
}

generate_nginx_filter() {
  cat > "${filter_path}/nginx-http-auth.conf" << EOF
[Definition]
datepattern = %%Y-%%m-%%dT%%H:%%M:%%S%%z
# 匹配 HTTP 401 认证失败
failregex = ^IP:<HOST>[^,]*,Time:[^,]*,Request:"(?:GET|POST|HEAD)\s+[^"]*",Referer:"[^"]*",Status:401,Bytes:[\d\.-]+,IPChain:"[^"]*",UserAgent:"[^"]*",RT:\[[\d\.-]+\],UCT:\[[\d\.-]+\],UHT:\[[\d\.-]+\],URT:\[[\d\.-]+\]
ignoreregex =
EOF

  cat > "${filter_path}/nginx-limit-req.conf" << EOF
[Definition]
datepattern = %%Y-%%m-%%dT%%H:%%M:%%S%%z
# 匹配 Nginx 限流日志
failregex = ^IP:<HOST>[^,]*,Time:[^,]*,Request:"(?:GET|POST|HEAD)\s+[^"]*",Referer:"[^"]*",Status:429,Bytes:[\d\.-]+,IPChain:"[^"]*",UserAgent:"[^"]*",RT:\[[\d\.-]+\],UCT:\[[\d\.-]+\],UHT:\[[\d\.-]+\],URT:\[[\d\.-]+\]
ignoreregex =
EOF

  cat > "${filter_path}/nginx-login.conf" << EOF
[Definition]
datepattern = %%Y-%%m-%%dT%%H:%%M:%%S%%z
# 匹配登录接口失败（需要应用层返回特定状态码）
failregex = ^IP:<HOST>[^,]*,Time:[^,]*,Request:"(?:GET|POST|HEAD)\s+?(?:/wp-login\.php|/admin|/login|/user/login|/auth|/signin|/api/login)(?:[/\s?][^"]*)?",Referer:"[^"]*",Status:(?:401|403|404|429|500),Bytes:[\d\.-]+,IPChain:"[^"]*",UserAgent:"[^"]*",RT:\[[\d\.-]+\],UCT:\[[\d\.-]+\],UHT:\[[\d\.-]+\],URT:\[[\d\.-]+\]
ignoreregex =
EOF

  cat > "${filter_path}/nginx-botsearch.conf" << EOF
[Definition]
datepattern = %%Y-%%m-%%dT%%H:%%M:%%S%%z
# 匹配敏感文件探测请求
failregex = ^IP:<HOST>[^,]*,Time:[^,]*,Request:"(?:GET|POST|HEAD)\s+[^"]*?(?i:/\.git|/\.env|/\.bak|/\.sql|/\.log|/wp-config|/config\.php|/\.htaccess|/\.htpasswd|/admin|/phpmyadmin|/manager|/console|/\.svn|/\.DS_Store|/backup|/db|/database|/\.idea|/\.vscode)(?:[/\s?][^"]*)?",Referer:"[^"]*",Status:(?:404|403|400),Bytes:[\d\.-]+,IPChain:"[^"]*",UserAgent:"[^"]*",RT:\[[\d\.-]+\],UCT:\[[\d\.-]+\],UHT:\[[\d\.-]+\],URT:\[[\d\.-]+\]
ignoreregex =
EOF

  cat > "${filter_path}/nginx-badbots.conf" << EOF
[Definition]
datepattern = %%Y-%%m-%%dT%%H:%%M:%%S%%z
# 匹配恶意爬虫/扫描器 User-Agent
failregex = ^IP:<HOST>[^,]*,Time:[^,]*,Request:"(?:GET|POST|HEAD)\s+[^"]*",Referer:"[^"]*",Status:[0-9]+,Bytes:[\d\.-]+,IPChain:"[^"]*",UserAgent:"[^"]*?(?i:python-requests|go-http|java|nikto|nmap|sqlmap|nessus|openvas|w3af|acunetix|netsparker|burp|dirbuster|gobuster|wfuzz|hydra|zmeu|masscan|pangolin|zgrab|censys|shodan|curl|wget|libwww|perl|php|ruby|mj12bot|bytespider)[^"]*",RT:\[[\d\.-]+\],UCT:\[[\d\.-]+\],UHT:\[[\d\.-]+\],URT:\[[\d\.-]+\]
ignoreregex =
EOF

  cat > "${filter_path}/nginx-noscript.conf" << EOF
[Definition]
datepattern = %%Y-%%m-%%dT%%H:%%M:%%S%%z
failregex =
  # 匹配 SQL 注入尝试
  ^IP:<HOST>[^,]*,Time:[^,]*,Request:"(?:GET|POST|HEAD)\s+[^"]*?(?i:union[\s\+\/\*]*?select|select[\s\+\/\*\w\.,]*?from|insert[\s\+\/\*\w\.,]*?into|delete[\s\+\/\*\w\.,]*?from|drop[\s\+\/\*\w\.,]*?table|update[\s\+\/\*\w\.,]*?set|exec[^"]*?\(|execute[^"]*?\(|xp_|sp_|0x[0-9a-f]+|char\(|concat\(|benchmark\(|sleep\(|waitfor|load_file|into[^"]*?outfile|into[^"]*?dumpfile).*",Referer:"[^"]*",Status:[\d\.-]+,Bytes:[\d\.-]+,IPChain:"[^"]*",UserAgent:"[^"]*",RT:\[[\d\.-]+\],UCT:\[[\d\.-]+\],UHT:\[[\d\.-]+\],URT:\[[\d\.-]+\]
  # 匹配 XSS 尝试
  ^IP:<HOST>[^,]*,Time:[^,]*,Request:"(?:GET|POST|HEAD)\s+[^"]*?(?i:<script|%%3Cscript|javascript:|<svg|%%3Csvg|<iframe|%%3Ciframe|onerror|onload|onclick|onfocus|onscroll|onmouseover|src=|eval(?:\(|%%28)|alert(?:\(|%%28)|prompt(?:\(|%%28)|confirm(?:\(|%%28)|document\.|window\.)[^"]*",Referer:"[^"]*",Status:[\d\.-]+,Bytes:[\d\.-]+,IPChain:"[^"]*",UserAgent:"[^"]*",RT:\[[\d\.-]+\],UCT:\[[\d\.-]+\],UHT:\[[\d\.-]+\],URT:\[[\d\.-]+\]
ignoreregex =
EOF

  cat > "${filter_path}/nginx-all-in-one.conf" << EOF
[Definition]
datepattern = %%Y-%%m-%%dT%%H:%%M:%%S%%z

failregex =
  # [A] Authentication failed
  ^IP:<HOST>[^,]*,Time:[^,]*,Request:"(?:GET|POST|HEAD)\s+[^"]*",Referer:"[^"]*",Status:401,Bytes:[\d\.-]+,IPChain:"[^"]*",UserAgent:"[^"]*",RT:\[[\d\.-]+\],UCT:\[[\d\.-]+\],UHT:\[[\d\.-]+\],URT:\[[\d\.-]+\]

  # [B] Limit request
  ^IP:<HOST>[^,]*,Time:[^,]*,Request:"(?:GET|POST|HEAD)\s+[^"]*",Referer:"[^"]*",Status:429,Bytes:[\d\.-]+,IPChain:"[^"]*",UserAgent:"[^"]*",RT:\[[\d\.-]+\],UCT:\[[\d\.-]+\],UHT:\[[\d\.-]+\],URT:\[[\d\.-]+\]

  # [C] Login failed
  ^IP:<HOST>[^,]*,Time:[^,]*,Request:"(?:GET|POST|HEAD)\s+?(?:/wp-login\.php|/admin|/login|/user/login|/auth|/signin|/api/login)(?:[/\s?][^"]*)?",Referer:"[^"]*",Status:(?:401|403|404|429|500),Bytes:[\d\.-]+,IPChain:"[^"]*",UserAgent:"[^"]*",RT:\[[\d\.-]+\],UCT:\[[\d\.-]+\],UHT:\[[\d\.-]+\],URT:\[[\d\.-]+\]

  # [D] Sensitive Files (Locked to 404/403/400)
  ^IP:<HOST>[^,]*,Time:[^,]*,Request:"(?:GET|POST|HEAD)\s+[^"]*?(?i:/\.git|/\.env|/\.bak|/\.sql|/\.log|/wp-config|/config\.php|/\.htaccess|/\.htpasswd|/admin|/phpmyadmin|/manager|/console|/\.svn|/\.DS_Store|/backup|/db|/database|/\.idea|/\.vscode)(?:[/\s?][^"]*)?",Referer:"[^"]*",Status:(?:404|403|400),Bytes:[\d\.-]+,IPChain:"[^"]*",UserAgent:"[^"]*",RT:\[[\d\.-]+\],UCT:\[[\d\.-]+\],UHT:\[[\d\.-]+\],URT:\[[\d\.-]+\]

  # [E] Bot & Scanners
  ^IP:<HOST>[^,]*,Time:[^,]*,Request:"(?:GET|POST|HEAD)\s+[^"]*",Referer:"[^"]*",Status:[0-9]+,Bytes:[\d\.-]+,IPChain:"[^"]*",UserAgent:"[^"]*?(?i:python-requests|go-http|java|nikto|nmap|sqlmap|nessus|openvas|w3af|acunetix|netsparker|burp|dirbuster|gobuster|wfuzz|hydra|zmeu|masscan|pangolin|zgrab|censys|shodan|curl|wget|libwww|perl|php|ruby|mj12bot|bytespider)[^"]*",RT:\[[\d\.-]+\],UCT:\[[\d\.-]+\],UHT:\[[\d\.-]+\],URT:\[[\d\.-]+\]

  # [F] SQL Injection
  ^IP:<HOST>[^,]*,Time:[^,]*,Request:"(?:GET|POST|HEAD)\s+[^"]*?(?i:union[\s\+\/\*]*?select|select[\s\+\/\*\w\.,]*?from|insert[\s\+\/\*\w\.,]*?into|delete[\s\+\/\*\w\.,]*?from|drop[\s\+\/\*\w\.,]*?table|update[\s\+\/\*\w\.,]*?set|exec[^"]*?\(|execute[^"]*?\(|xp_|sp_|0x[0-9a-f]+|char\(|concat\(|benchmark\(|sleep\(|waitfor|load_file|into[^"]*?outfile|into[^"]*?dumpfile).*",Referer:"[^"]*",Status:[\d\.-]+,Bytes:[\d\.-]+,IPChain:"[^"]*",UserAgent:"[^"]*",RT:\[[\d\.-]+\],UCT:\[[\d\.-]+\],UHT:\[[\d\.-]+\],URT:\[[\d\.-]+\]

  # [G] XSS (Cross-Site Scripting)
  ^IP:<HOST>[^,]*,Time:[^,]*,Request:"(?:GET|POST|HEAD)\s+[^"]*?(?i:<script|%%3Cscript|javascript:|<svg|%%3Csvg|<iframe|%%3Ciframe|onerror|onload|onclick|onfocus|onscroll|onmouseover|src=|eval(?:\(|%%28)|alert(?:\(|%%28)|prompt(?:\(|%%28)|confirm(?:\(|%%28)|document\.|window\.)[^"]*",Referer:"[^"]*",Status:[\d\.-]+,Bytes:[\d\.-]+,IPChain:"[^"]*",UserAgent:"[^"]*",RT:\[[\d\.-]+\],UCT:\[[\d\.-]+\],UHT:\[[\d\.-]+\],URT:\[[\d\.-]+\]

ignoreregex =
EOF
}

configure_default() {
  cat > "${jail_path}/default.conf" <<EOF
[DEFAULT]
# 白名单
ignoreip = 127.0.0.1/8 ::1 ${whitelists[*]}
# 封禁时间
bantime  = 24h
# 10分钟内失败3次就封禁
findtime  = 10m
maxretry = 3
# Increase ban time for repeat offenders
bantime.increment = true
# Eventually ban forever
bantime.maxtime = -1
# "backend" specifies the backend used to get files modification.
backend = auto
# 设置防火墙
banaction = $ACTION
banaction_allports = $ALLPORTS
EOF
}

configure_sshd() {
  echo -e "${INFO} Enable sshd jail"
  cat > "${jail_path}/sshd.conf" <<EOF
[sshd]
enabled   = true
port      = ssh
filter    = sshd
mode      = aggressive
backend   = systemd
# 1天内尝试5次就永久封禁
maxretry  = 5
findtime  = 1d
bantime   = -1
EOF
}

configure_nginx() {
  echo -e "${INFO} Enable nginx jail"
  cat > "${jail_path}/nginx.conf" <<EOF
[nginx]
enabled   = true
port      = http,https
filter    = nginx-all-in-one
backend   = pyinotify
logpath   = /home/wwwlogs/nginx_access.log
            /home/wwwlogs/nginx_error.log
            /home/wwwlogs/nginx_login.log
# 1小时内尝试3次则封禁24小时
maxretry  = 3
findtime  = 1h
bantime   = 24h
EOF
}

configure_mail() {
  echo -e "${INFO} Enable mail jail"
  cat > "${jail_path}/mail.conf" <<EOF
[postfix]
enabled   = true
port      = smtp,ssmtp,submission
filter    = postfix
# backend   = pyinotify
# logpath   = /var/log/mail.log
backend   = systemd
journalmatch = _SYSTEMD_UNIT=postfix.service
# 邮件服务的暴力破解通常更具针对性，可以缩短 findtime
maxretry  = 3
findtime  = 10m
bantime   = 24h

[postfix-sasl]
enabled   = true
port      = smtp,ssmtp,submission,imap,imaps,pop3,pop3s
filter    = postfix[mode=auth]
# backend   = pyinotify
# logpath   = /var/log/mail.log
backend   = systemd
journalmatch = _SYSTEMD_UNIT=postfix.service
# 认证失败
maxretry  = 3
findtime  = 10m
bantime   = 48h

[dovecot]
enabled   = true
port      = pop3,pop3s,imap,imaps,submission,smtps,sieve
filter    = dovecot
# backend   = pyinotify
# logpath   = /var/log/mail.log
backend   = systemd
journalmatch = _SYSTEMD_UNIT=dovecot.service
# 给正常用户 5 次机会，防止因为移动端配置错误导致误封
maxretry  = 5
findtime  = 20m
bantime   = 24h
EOF
}

detect_fail2ban_banaction() {
  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ACTION="ufw"
    ALLPORTS="ufw"
    return 0
  fi

  if command -v nft &> /dev/null; then
    ACTION="nftables"
    ALLPORTS="nftables-allports"
    return 0
  fi

  if iptables --version 2>/dev/null | grep -q "nf_tables"; then
    ACTION="nftables"
    ALLPORTS="nftables-allports"
    return 0
  fi

  ACTION="iptables-multiport"
  ALLPORTS="iptables-allports"
}

configure() {
  # 从环境变量确定需要启用的 jail
  local sshd="${sshd_jail:-y}"
  local nginx="${nginx_jail:-n}"
  local mail="${mail_jail:-n}"
  configure_default
  [ "${sshd}" = 'y' ] && configure_sshd
  [ "${nginx}" = 'y' ] && configure_nginx
  [ "${mail}" = 'y' ] && configure_mail
  systemctl restart fail2ban
  sleep 3
}

check_status() {
  fail2ban-client status
  case "$ACTION" in
    ufw)      ufw status ;;
    nftables) nft list ruleset ;;
    *)        iptables -L -n -v ;;
  esac
}

install() {
  print_version
  enter_info
  install_fail2ban
  [ "${nginx_filter}" = 'y' ] && {
    backup_nginx_filter
    generate_nginx_filter
  }
  # 先确定防火墙
  detect_fail2ban_banaction
  configure
  check_status
}

VT_HOME="${HOME}/VT-Data"
VT_log="${VT_HOME}/logs"

[ ! -d "${VT_HOME}/" ] && mkdir ${VT_HOME}
[ ! -d "${VT_log}/" ] && mkdir ${VT_log}

install 2>&1 | tee "${VT_log}/fail2ban.log"
