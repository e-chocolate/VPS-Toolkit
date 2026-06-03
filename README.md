# VPS-Toolkit

**Stop repeating yourself. Deploy, monitor, and secure your server with scripts.**

-----

🛠️ A curated collection of automation scripts to simplify software installation and configuration on VPS.

> All scripts are only tested on Ubuntu(noble) and Debian(bookworm) until now.

## System-init

The `system-init.sh` is a first-run security hardening script for newly deployed VPS. It automates essential security configurations to protect your server from common threats.

```shell
# Optional
export non_root_user='normal'
export ssh_port='22'
export enable_swap='y'
export enable_nftables='n'

bash <(curl -L https://github.com/e-chocolate/VPS-Toolkit/raw/master/system-init.sh)
```

> Last Updated: 2026-05-21

## [System-Wide-Scripts](./system-wide-scripts/README.md)

Provide some interesting functions for Linux.

> Last Updated: 2026-06-03

## Init

The `init.sh` script will install common but essential packages on the VPS, we highly recommend you to run `init.sh` once before running the other scripts provided by VPS-Toolkit.

```shell
# Specify packages' versions as needed, or leave them blank
export libiconv_ver='1.19'
export mhash_ver=''
export libmcrypt_ver=''
export mcrypt_ver=''
export freetype_ver=''

sudo ./init.sh
```

> Last Updated: 2026-06-03
