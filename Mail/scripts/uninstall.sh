#!/usr/bin/env bash
export PATH=$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export DEBIAN_FRONTEND=noninteractive

# Check if user is root
if [ $(id -u) != "0" ]; then
  echo "Error: You must be root to run this script"
  exit 1
fi

apt purge -y postfix postfix-* && apt autoremove -y
apt purge -y dovecot-* && rm -rf /var/lib/dovecot /etc/dovecot/conf.d
apt purge -y opendkim && apt autoremove -y
apt purge -y opendmarc && apt autoremove -y