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

> Last Updated: 2026-08-13

## [System-Wide-Scripts](./system-wide-scripts/README.md)

Provide some interesting functions for Linux.

> Last Updated: 2026-08-23

## Init

The `init.sh` script will install common but essential packages on the VPS, we highly recommend you to run `init.sh` once before running the other scripts provided by VPS-Toolkit.

```shell
# Specify packages' versions as needed, or leave them blank
export libiconv_ver='1.19'
export freetype_ver='2.14.3'
# mhash & mcrypt will be installed only when setting specified version
export mhash_ver='0.9.9.9'
export libmcrypt_ver='2.5.8'
export mcrypt_ver='2.6.8'

sudo ./init.sh
```

> Last Updated: 2026-08-19

## [Database](./Database/README.md)

Scripts for installing common databases packages.

> Last Updated: 2026-08-20

## [DevOps](./DevOps/README.md)

Scripts for installing common DevOps tools(e.g., docker).

> Last Updated: 2026-08-22

## [Mail](./Mail/README.md)

Scripts for installing MTA, MDA packages.

> Last Updated: 2026-08-09

## [Tools](./Tools/README.md)

Scripts for installing useful tools.

> Last Updated: 2026-06-14

## [Web](./Web/README.md)

Scripts for installing web hosting stacks.

> Last Updated: 2026-07-19
