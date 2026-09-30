# Introduction

DevOps is a cultural philosophy, set of practices, and tools that merges software development (Dev) and IT operations (Ops) teams to shorten the development lifecycle.

## Docker (rootful with user namespace remapping)

[Docker](https://www.docker.com/) is an essential tool in DevOps. The existing `docker.sh` installer runs the Docker daemon as root and enables user namespace remapping. Follow these steps to install it.

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

## Rootless Docker

`docker-rootless.sh` installs Rootless Docker on Debian or Ubuntu. Run it as the user who will own the Docker daemon, or use `sudo` and specify an existing or new target user.

```shell []
cd DevOps

# Install for the current user (recommended)
./scripts/docker-rootless.sh

# Or install for a specified user
sudo ./scripts/docker-rootless.sh alice
```

Optional environment variables:

| Variable | Description |
| --- | --- |
| `ROOTLESS_USER` | Target user; a command-line username takes precedence. |
| `DOCKER_VERSION` | Docker Engine version. Default: `29.8.1-1`. |
| `DOCKER_CLI_VERSION` | Docker CLI version. Default: `DOCKER_VERSION`. |
| `DOCKER_ROOTLESS_EXTRAS_VERSION` | Rootless extras version. Default: `DOCKER_VERSION`. |
| `CONTAINERD_IO_VERSION` | containerd.io version. Default: `2.3.6-1`. |
| `DOCKER_BUILDX_VERSION` | Buildx version. Default: `0.37.1-1`. |
| `DOCKER_COMPOSE_VERSION` | Compose version. Default: `5.5.1-1`. |
| `ROOTFUL_DOCKER_MODE` | Rootful Docker handling: `coexist`, `stop`, or `abort`. |
| `REMOVE_CONFLICTING_PACKAGES` | Set to `1` to approve removal of detected conflicting packages without prompting. |

For example:

```shell []
sudo env ROOTLESS_USER=alice ROOTFUL_DOCKER_MODE=coexist \
  ./scripts/docker-rootless.sh
```

Only set `REMOVE_CONFLICTING_PACKAGES=1` after reviewing the packages that will be removed. Run `./scripts/docker-rootless.sh --help` for details.

Docker's package versions are not published uniformly for every architecture. Before using `armhf`, `ppc64el`, or `s390x`, check the packages available for that distribution and override the pinned version variables when necessary.

When the target user does not exist, the script creates a dedicated `nologin` system user and lets `useradd` create `/home/<user>` with the distribution defaults. Installation stops before creating the user if that path already exists.

> Last Updated: 2026-10-01

## Gitea Runner with Rootless Docker

`gitea-runner.sh` installs the latest stable Gitea Runner binary, verifies its published SHA-256 checksum, registers it when requested, and creates `gitea-runner.service`. The service and its Job containers use the same Unix user's Rootless Docker daemon.

Install `jq`, then install Rootless Docker before installing the Runner:

```shell []
cd DevOps

sudo apt-get update
sudo apt-get install -y jq

# Create or configure the dedicated user and its Rootless Docker daemon
sudo ./scripts/docker-rootless.sh gitea-runner

# Registration URL and token are requested before installation starts
sudo ./scripts/gitea-runner.sh --register \
  --user gitea-runner \
  --instance-url https://gitea.example.com/ \
  --disable-health-metrics
```

For an upgrade that keeps `/var/lib/gitea-runner/.runner`:

```shell []
sudo ./scripts/gitea-runner.sh --skip-register \
  --user gitea-runner \
  --disable-health-metrics
```

The default configuration is copied from `conf/gitea-runner.yaml` to `/etc/gitea-runner/config.yaml`. It runs `ubuntu-latest` Jobs in `docker.gitea.com/runner-images:ubuntu-latest`, does not mount the Rootless Docker socket into Job containers, disables privileged containers and host-volume mounts, and disables the Actions cache. Use `--enable-health-metrics` to add local `/metrics`, `/healthz`, and `/readyz` endpoints on `127.0.0.1:9101`.

Optional environment variables:

| Variable | Description |
| --- | --- |
| `GITEA_RUNNER_USER` | Unix user shared by the Runner service and Rootless Docker. |
| `GITEA_RUNNER_VERSION` | Exact Runner version; otherwise the latest stable release is selected. |
| `GITEA_RUNNER_REGISTRATION_TOKEN` | Registration token for non-interactive installation. |

Use this Runner only for trusted repositories. Job containers share the selected user's Docker daemon even though its socket is not mounted into them. Run `./scripts/gitea-runner.sh --help` for all flags.

Verify the service and its Rootless Docker connection from the repository root:

```shell []
sudo systemctl status gitea-runner.service
sudo bash Scripts/show-docker-info.sh
```

> Last Updated: 2026-10-01

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
