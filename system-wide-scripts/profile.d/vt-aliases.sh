#!/bin/bash
# This file is sourced by /etc/profile for interactive Bash shells
# Only run in Bash
[ -z "$BASH_VERSION" ] && return 0

alias grep='grep --color=auto'

alias ll='ls -alF'
alias rm='rm -i'
alias rmf='rm -rf'
alias cp='cp -i'
alias cpa='cp -a'
alias mv='mv -i'
alias mkdir='mkdir -p'
alias ..='cd ..'
alias ...='cd ../..'

alias h='history'
alias j='jobs'

alias ps='ps auxf'
alias ps10='ps auxf | sort -nr -k 4 | head -10'
alias cpu='top -c -o %CPU'
alias df='df -h'
alias du='du -sh'

alias brc='source ~/.bashrc'
alias update='sudo apt update && sudo apt upgrade'

alias myip='curl ifconfig.me'
alias myipv4='curl -4 ifconfig.me'
alias myipv6='curl -6 ifconfig.me'
alias ports='netstat -tulanp'
alias ping='ping -c 5'

if nano --help 2>&1 | grep -q '\-\-linenumbers'; then
  alias nano='nano --linenumbers'
fi

alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'
