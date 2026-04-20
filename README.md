# VPS-Toolkit

**Stop repeating yourself. Deploy, monitor, and secure your server with one command.**

-----

🛠️ A curated collection of automation scripts to simplify software installation and configuration on VPS.

> All scripts are only tested on Ubuntu noble until now.

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