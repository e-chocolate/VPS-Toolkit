# VPS-Toolkit

**Stop repeating yourself. Deploy, monitor, and secure your server with scripts.**

-----

🛠️ A curated collection of automation scripts to simplify software installation and configuration on VPS.

> All scripts are only tested on Ubuntu noble until now.

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

> Last Updated: 2026-05-05
