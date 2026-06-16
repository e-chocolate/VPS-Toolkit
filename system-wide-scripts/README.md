# Introduction

The `/etc/profile.d` directory in Linux contains scripts that are used to set system-wide environment variables and configuration settings for all users. These scripts are sourced automatically when a user logs in via a login shell.

VT(VPS-ToolKit) system-wide-script will install some useful scripts in the VPS.

## How to install

```shell
cd system-wide-scripts
sudo ./system-wide-scripts.sh
```

# Index of Functions

This is a brief introduction of what the functions in `vt-functions.sh` can do.

| Name                     | Description                                                   |
| ------------------------ | ------------------------------------------------------------- |
| `sudoi`                  | Execute the command as the specified user.                    |
| `sssh`                   | Connect to the server with the specified port.                |
| `ssync`                  | Transfer files to the specified server.                       |
| `showUser`               | Display the specified user information.                       |
| `showGroup`              | Display the specified user group information.                 |
| `null`                   | Truncate the specified file.                                  |
| `nullNano`               | Truncate the specified file and edit that file with nano.     |
| `nullDir`                | Truncate all files in specified folder.                       |
| `nullDirRec`             | Recursively truncate all files in specified folder.           |
| `gen_str`                | Generate a random string of the specified length.             |
| `gen_hex`                | Generate a random hexadecimal string of the specified length. |
| `fix_webroot_permission` | Fix permissions for NGINX Web Dir.                            |
