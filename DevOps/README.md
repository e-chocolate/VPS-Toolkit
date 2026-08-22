# Introduction

DevOps is a cultural philosophy, set of practices, and tools that merges software development (Dev) and IT operations (Ops) teams to shorten the development lifecycle.

## Docker

[Docker](https://www.docker.com/) is an essential tool in DevOps. Follow the following steps to install.

1. Go to [Docker packages](https://download.docker.com/linux/) to determine the version of packages that you want to install.
2. Add the version info to the environment variables(Optional).

```shell []
cd DevOps

# switch to root first
sudo su

# Add environment variables
export containerd_io_ver='2.3.3-1'
export docker_ce_ver='29.7.2-1'
export docker_ce_cli_ver='29.7.2-1'
export docker_buildx_plugin_ver='0.36.1-1'
export docker_compose_plugin_ver='5.4.0-1'

./scripts/docker.sh
```

> Last Updated: 2026-08-16

## Code-Server

[Code-Server](https://github.com/coder/code-server) allows you to run VS Code on any machine anywhere and access it in the browser.

```shell []
cd DevOps
# Replace [user] with the user running the code-server.
sudo ./scripts/code_server.sh [user]
```

> Last Updated: 2026-08-16

## Gitea

[Gitea](https://docs.gitea.com/category/installation) is a painless, self-hosted, all-in-one software development service. Run the following commands to install.

```shell []
cd DevOps
sudo ./scripts/gitea.sh 
```

> Last Updated: 2026-08-22

## Fail2Ban

[Fail2Ban](https://github.com/fail2ban/fail2ban) is an intrusion prevention framework for Linux that protects servers from brute-force attacks by monitoring system logs (e.g., SSH, Nginx) for repeated failures.

```shell []
cd DevOps

# switch to root first
sudo su

# Add environment variables to choose the jail that you want to enable
export sshd_jail='y'
export nginx_jail='y'
export mail_jail='y'

./scripts/fail2ban.sh 
```

> Last Updated: 2026-08-22
