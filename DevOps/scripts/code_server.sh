#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin

# Check if user is root
if [ $(id -u) != "0" ]; then
  echo "Error: You must be root to run this script"
  exit 1
fi

INFO="\e[0;32m[INFO]\e[0m"
ERROR="\e[0;31m[ERROR]\e[0m"

enter_parameters() {
  clear
  echo "+------------------------------------------------------------------------+"
  echo "|         VT-coder for Debian like Linux, Written by Echocolate          |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Scripts to install coder server on Linux                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                Version: 1.0.0  Last Updated: 2026-06-18                |"
  echo "+------------------------------------------------------------------------+"
  echo "|                      https://repos.echocolate.xyz                      |"
  echo "+------------------------------------------------------------------------+"
  sleep 2
  # 需要手动设置的参数
  echo -en "\e[0;33mEnter the address that code-server binds(default 0.0.0.0): \e[0m"
  read bind_addr
  echo -en "\e[0;33mEnter the port that code-server binds(default 60000): \e[0m"
  read bind_port
  echo -en "\e[0;33mEnter the login password: \e[0m"
  read pd
  [ -z ${bind_addr} ] && bind_addr='0.0.0.0'
  [ -z ${bind_port} ] && bind_port='60000'
  [ -z ${pd} ] && pd=$(tr -dc 'A-Za-z0-9_+-' < /dev/urandom | head -c 12)
}

reminder() {
  printf "\e[0;32m%-12s : %s\n\e[0m" 'parameter' 'value'
  printf "%-12s : %s\n" "bind address" "$bind_addr"
  printf "%-12s : %s\n" "bind port" "$bind_port"
  printf "%-12s : %s\n" "password" "$pd"
}

get_github_latest(){
  # get the latest stable version
  local repo_name=$1
  curl -s https://api.github.com/repos/${repo_name}/releases/latest | grep tag_name | head -n 1 | cut -d '"' -f 4
}

clean_cache_dir() {
  if [ -d "${XDG_CACHE_HOME-}" ]; then
    rm -rf "$XDG_CACHE_HOME/code-server"
  fi
  if [ -d "${coder_user_HOME-}" ]; then
    rm -rf "${coder_user_HOME}/.cache/code-server"
  fi
  if [ -d "/tmp/code-server-cache" ]; then
    rm -rf "/tmp/code-server-cache"
  fi
  echo -e "\e[34m"`date +%Y-%m-%d` `date +%H:%M:%S`"\e[0m" "Successfully cleanned the cache..."
}

check_user() {
  if ! id "${coder_user}" > /dev/null 2>&1; then
    echo -e "${INFO} User ${coder_user} 用户不存在"
    useradd -m -U -s /bin/bash "${coder_user}"
  fi

  [ ! -d "${coder_user_HOME}" ] && {
    echo -e "${INFO} Create ${coder_user} HOME"
    mkdir "${coder_user_HOME}"
    chown -R ${coder_user}:${coder_user} "${coder_user_HOME}"
  }
}

config(){
  if [ ! -d "${coder_user_HOME}/.config/code-server" ]; then
    sudo -u ${coder_user} mkdir -p "${coder_user_HOME}/.config/code-server"
  fi
  cat > ${coder_user_HOME}/.config/code-server/config.yaml << EOF
bind-addr: ${bind_addr}:${bind_port}
auth: password
password: ${pd}
cert: false
EOF
  chown ${coder_user}:${coder_user} ${coder_user_HOME}/.config/code-server/config.yaml
}

install(){
  enter_parameters
  # use default script
  bash <(curl -fsSL https://code-server.dev/install.sh)
  clean_cache_dir
  config
  systemctl enable --now code-server@${coder_user}
  reminder
  echo -e "\e[34m"`date +%Y-%m-%d` `date +%H:%M:%S`"\e[0m" "Successfully installed code-server."
}

restart(){
  # restart code-server
  systemctl daemon-reload
  # rm -rf $HOME/.local/share/code-server/User/workspaceStorage
  systemctl restart code-server@${coder_user}.service
  echo -e "\e[34m"`date +%Y-%m-%d` `date +%H:%M:%S`"\e[0m" "Successfully restart code-server."
}

update(){
  local current_version=$(code-server -v | head -n 1 | awk '{print $1}')
  local stable_version=$(get_github_latest "coder/code-server" | sed 's/v//g')

  printf "%-33s : \e[0;32m%s\n\e[0m" "local code-server version" "$current_version"
  printf "%-33s : \e[0;32m%s\n\e[0m" "latest stable code-server version" "$stable_version"

  if [ $current_version != $stable_version ]; then
    # use default script
    bash <(curl -fsSL https://code-server.dev/install.sh)
    clean_cache_dir
    echo -e "\e[34m"`date +%Y-%m-%d` `date +%H:%M:%S`"\e[0m" "Successfully updated code-server."
    restart
  else
    echo "You are using the latest_stable_version, exiting..."
  fi
}

check_service() {
  systemctl cat code-server@${coder_user}.service >/dev/null && flag=0 || flag=1
  if [ $flag -eq 0 ] && [ -f "${coder_user_HOME}/.config/code-server/config.yaml" ]; then
    return 0
  fi
  return 1
}

main() {
  check_user
  check_service
  if [ $? -eq 0 ]; then
    echo -e "\e[34m[Info]\e[0m find code-server@${coder_user}.service, updating..."
    update ${coder_user}
  else
    echo -e "\e[34m[Info]\e[0m Cannot find code-server@${coder_user}.service, installing..."
    install ${coder_user}
  fi
}

VT_HOME="${HOME}/VT-Data"
VT_log="${VT_HOME}/logs"

[ ! -d "${VT_HOME}/" ] && mkdir ${VT_HOME}
[ ! -d "${VT_log}/" ] && mkdir ${VT_log}

if [[ $1 != "" && $1 != "root" ]]; then
  coder_user=$1
  coder_user_HOME="/home/$1"
else
  coder_user=root
  coder_user_HOME=/root
fi

main 2>&1 | tee "${VT_log}/coder-server.log"
