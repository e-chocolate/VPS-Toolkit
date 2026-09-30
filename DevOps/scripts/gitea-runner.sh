#!/usr/bin/env bash

set -Eeuo pipefail
umask 027

readonly state_dir="/var/lib/gitea-runner"
readonly registration_file="$state_dir/.runner"
readonly config_dir="/etc/gitea-runner"
readonly config_dest="$config_dir/config.yaml"
readonly binary_path="/usr/local/bin/gitea-runner"
readonly service_name="gitea-runner.service"
readonly service_path="/etc/systemd/system/$service_name"
readonly latest_release_api_url="https://gitea.com/api/v1/repos/gitea/runner/releases/latest"
readonly downloads_url="https://dl.gitea.com/gitea-runner"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly default_config_source="$script_dir/../conf/gitea-runner.yaml"

runner_user="${GITEA_RUNNER_USER:-}"
runner_group=""
runner_gid=""
runner_home=""
runner_runtime_dir=""
docker_socket=""
docker_host=""
docker_binary=""
runner_version="${GITEA_RUNNER_VERSION:-}"
config_source="$default_config_source"
instance_url=""
registration_token="${GITEA_RUNNER_REGISTRATION_TOKEN:-}"
unset GITEA_RUNNER_REGISTRATION_TOKEN
runner_name=""
skip_register=-1
enable_health_metrics=-1
start_service=1
download_dir=""

usage() {
  cat <<'EOF'
Install the Gitea Runner binary and a hardened systemd service that uses the
selected Unix user's Rootless Docker daemon.

Usage:
  sudo ./scripts/gitea-runner.sh \
    [--register | --skip-register] \
    [--enable-health-metrics | --disable-health-metrics] \
    [--user USER] \
    [--instance-url https://gitea.example.com/] \
    [--name org-runner-01] \
    [--version VERSION] \
    [--config ./conf/gitea-runner.yaml] \
    [--no-start]

Options:
  --register          Register a missing Runner. Without either registration
                      option, the script asks for the registration mode first.
  --skip-register     Do not register a missing Runner. When no existing
                      registration is present, the service is not started.
  --enable-health-metrics
                      Enable local health checks and the metrics HTTP listener.
  --disable-health-metrics
                      Leave health checks and metrics disabled. Without either
                      option, the script asks before installation starts.
  --user USER         Unix user that runs both Gitea Runner and Rootless Docker.
                      When omitted, the script prompts before performing
                      installation work. The GITEA_RUNNER_USER environment
                      variable is also supported.
  --instance-url URL  Gitea ROOT_URL. Prompted for when registration is selected.
                      The registration token is then read using a hidden prompt,
                      or from GITEA_RUNNER_REGISTRATION_TOKEN for non-interactive
                      execution.
  --name NAME         Runner name. Defaults to the machine's FQDN or hostname.
  --version VERSION   Install this exact version. When omitted, resolve the latest
                      stable release from the official repository Release API.
  --config PATH       Source file copied to /etc/gitea-runner/config.yaml.
                      Defaults to ./conf/gitea-runner.yaml.
  --no-start          Install and optionally register, but do not enable/start it.
  -h, --help          Show this help.

For an upgrade, the existing /var/lib/gitea-runner/.runner registration is kept;
select --skip-register to avoid entering registration parameters.
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

cleanup() {
  if [[ -n "$download_dir" && -d "$download_dir" ]]; then
    rm -rf -- "$download_dir"
  fi
}
trap cleanup EXIT

require_argument() {
  local option="$1"
  local remaining="$2"

  if (( remaining < 2 )); then
    die "$option requires a value"
  fi
}

while (( $# > 0 )); do
  case "$1" in
    --user)
      require_argument "$1" "$#"
      runner_user="$2"
      shift 2
      ;;
    --instance-url)
      require_argument "$1" "$#"
      instance_url="$2"
      shift 2
      ;;
    --name)
      require_argument "$1" "$#"
      runner_name="$2"
      shift 2
      ;;
    --version)
      require_argument "$1" "$#"
      runner_version="$2"
      shift 2
      ;;
    --config)
      require_argument "$1" "$#"
      config_source="$2"
      shift 2
      ;;
    --register)
      (( skip_register == -1 )) || die "choose only one of --register and --skip-register"
      skip_register=0
      shift
      ;;
    --skip-register)
      (( skip_register == -1 )) || die "choose only one of --register and --skip-register"
      skip_register=1
      shift
      ;;
    --enable-health-metrics)
      (( enable_health_metrics == -1 )) ||
        die "choose only one of --enable-health-metrics and --disable-health-metrics"
      enable_health_metrics=1
      shift
      ;;
    --disable-health-metrics)
      (( enable_health_metrics == -1 )) ||
        die "choose only one of --enable-health-metrics and --disable-health-metrics"
      enable_health_metrics=0
      shift
      ;;
    --no-start)
      start_service=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if (( EUID != 0 )); then
  die "run this script as root (for example, with sudo)"
fi

if [[ "$(uname -s)" != "Linux" ]]; then
  die "this installer supports Linux with systemd only"
fi

# Collect every interactive value before any installation or service operation.
# The registration choice is deliberately the first prompt.
if (( skip_register == -1 )); then
  if [[ ! -t 0 ]]; then
    die "non-interactive installation requires --register or --skip-register"
  fi

  while true; do
    read -r -p "Skip Gitea Runner registration? [y/N]: " skip_register_answer ||
      die "cannot read the registration choice"
    case "$skip_register_answer" in
      y|Y|yes|YES|Yes)
        skip_register=1
        break
        ;;
      ""|n|N|no|NO|No)
        skip_register=0
        break
        ;;
      *)
        printf 'Please answer yes or no.\n' >&2
        ;;
    esac
  done
fi

if (( skip_register == 0 )); then
  if [[ -z "$instance_url" ]]; then
    [[ -t 0 ]] || die "non-interactive registration requires --instance-url"
    while [[ -z "$instance_url" ]]; do
      read -r -p "Enter the Gitea instance URL: " instance_url ||
        die "cannot read the Gitea instance URL"
    done
  fi

  [[ "$instance_url" =~ ^https?://[^[:space:]]+/?$ ]] ||
    die "--instance-url must be a valid http(s) URL"

  if [[ -z "$registration_token" ]]; then
    [[ -t 0 ]] ||
      die "non-interactive registration requires GITEA_RUNNER_REGISTRATION_TOKEN"
    while [[ -z "$registration_token" ]]; do
      read -r -s -p "Enter the Gitea Runner registration token: " registration_token ||
        die "cannot read the registration token"
      printf '\n' >&2
    done
  fi
else
  # Ignore registration values inherited from the environment or command line.
  instance_url=""
  registration_token=""
fi

if [[ -z "$runner_user" ]]; then
  if [[ ! -t 0 ]]; then
    die "non-interactive installation requires --user or GITEA_RUNNER_USER"
  fi

  while [[ -z "$runner_user" ]]; do
    read -r -p "Enter the Unix user that will run Gitea Runner: " runner_user ||
      die "cannot read the runner user"
  done
fi

[[ "$runner_user" != -* \
  && "$runner_user" != *:* \
  && "$runner_user" != */* \
  && "$runner_user" != *[[:space:]]* ]] ||
  die "invalid runner user name: $runner_user"

if (( enable_health_metrics == -1 )); then
  if [[ ! -t 0 ]]; then
    die "non-interactive installation requires --enable-health-metrics or --disable-health-metrics"
  fi

  while true; do
    read -r -p "Enable Gitea Runner health checks and metrics? [y/N]: " health_metrics_answer ||
      die "cannot read the health checks and metrics choice"
    case "$health_metrics_answer" in
      y|Y|yes|YES|Yes)
        enable_health_metrics=1
        break
        ;;
      ""|n|N|no|NO|No)
        enable_health_metrics=0
        break
        ;;
      *)
        printf 'Please answer yes or no.\n' >&2
        ;;
    esac
  done
fi

# No interactive input is permitted below this point.
info "Input collection complete; starting automated installation"

required_commands=(
  chown
  curl
  docker
  env
  getent
  id
  install
  jq
  mktemp
  runuser
  sha256sum
  stat
  systemctl
  uname
  useradd
)

for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    if [[ "$command_name" == "jq" ]]; then
      die "missing command: jq (install jq before running this script)"
    fi
    die "missing command: $command_name"
  fi
done
docker_binary="$(command -v docker)"
[[ "$docker_binary" == /* && -x "$docker_binary" ]] ||
  die "docker must resolve to an executable absolute path"

if getent passwd "$runner_user" >/dev/null; then
  info "Using the existing Unix user $runner_user"
else
  [[ ${#runner_user} -le 32 && "$runner_user" =~ ^[a-z_][a-z0-9_.-]*[$]?$ ]] ||
    die "cannot create $runner_user: use a conventional lowercase Unix user name of at most 32 characters"

  if [[ -x /usr/sbin/nologin ]]; then
    nologin_shell="/usr/sbin/nologin"
  elif [[ -x /sbin/nologin ]]; then
    nologin_shell="/sbin/nologin"
  else
    die "cannot find a nologin shell"
  fi

  new_runner_home="/home/$runner_user"
  [[ ! -e "$new_runner_home" || -d "$new_runner_home" ]] ||
    die "runner home path exists but is not a directory: $new_runner_home"

  info "Creating system user $runner_user"
  if getent group "$runner_user" >/dev/null; then
    useradd \
      --system \
      --create-home \
      --home-dir "$new_runner_home" \
      --gid "$runner_user" \
      --shell "$nologin_shell" \
      "$runner_user"
  else
    useradd \
      --system \
      --create-home \
      --home-dir "$new_runner_home" \
      --user-group \
      --shell "$nologin_shell" \
      "$runner_user"
  fi
fi

runner_passwd_entry="$(getent passwd "$runner_user")" ||
  die "cannot read the passwd entry for $runner_user"
IFS=: read -r -a runner_passwd_fields <<<"$runner_passwd_entry"
(( ${#runner_passwd_fields[@]} >= 7 )) ||
  die "invalid passwd entry for $runner_user"

runner_uid="${runner_passwd_fields[2]}"
runner_gid="${runner_passwd_fields[3]}"
runner_home="${runner_passwd_fields[5]}"
[[ "$runner_uid" =~ ^[0-9]+$ ]] || die "cannot resolve the UID for $runner_user"
[[ "$runner_gid" =~ ^[0-9]+$ ]] || die "cannot resolve the GID for $runner_user"
if (( runner_uid == 0 )); then
  die "$runner_user must not have UID 0"
fi

[[ "$runner_home" == /* && -d "$runner_home" ]] ||
  die "$runner_user has no usable home directory: $runner_home"
runuser -u "$runner_user" -- test -w "$runner_home" ||
  die "$runner_user cannot write to its home directory: $runner_home"

runner_group="$(id -gn "$runner_user")" ||
  die "cannot resolve the primary group for $runner_user"
[[ -n "$runner_group" ]] || die "the primary group for $runner_user is empty"

runner_runtime_dir="/run/user/$runner_uid"
docker_socket="$runner_runtime_dir/docker.sock"
docker_host="unix://$docker_socket"

run_as_runner() {
  runuser \
    -u "$runner_user" \
    -g "$runner_group" \
    -- \
    env \
      -u DOCKER_CONTEXT \
      -u DOCKER_TLS_VERIFY \
      -u DOCKER_CERT_PATH \
      "HOME=$runner_home" \
      "USER=$runner_user" \
      "LOGNAME=$runner_user" \
      "XDG_RUNTIME_DIR=$runner_runtime_dir" \
      "DBUS_SESSION_BUS_ADDRESS=unix:path=$runner_runtime_dir/bus" \
      "DOCKER_HOST=$docker_host" \
      "$@"
}

if [[ -z "$runner_version" ]]; then
  info "Resolving the latest stable Gitea Runner release"
  latest_release_json="$(
    curl --fail --location --silent --show-error \
      --proto '=https' --proto-redir '=https' --tlsv1.2 \
      --header 'Accept: application/json' \
      "$latest_release_api_url"
  )" || die "cannot query the official Gitea Runner Release API; use --version to select a release explicitly"

  runner_tag="$(
    printf '%s' "$latest_release_json" |
      jq --exit-status --raw-output '
        if .draft == false and
           .prerelease == false and
           (.tag_name | type) == "string" and
           ((.tag_name | length) > 0)
        then .tag_name
        else error("latest release is a draft, prerelease, or has no tag")
        end
      '
  )" || die "the Release API did not return a valid stable release; use --version to select a release explicitly"

  runner_version="${runner_tag#v}"
  info "Latest stable Gitea Runner release: $runner_version"
else
  runner_version="${runner_version#v}"
  info "Using the requested Gitea Runner version: $runner_version"
fi

if [[ ! "$runner_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "invalid runner version: $runner_version"
fi

[[ -f "$config_source" ]] || die "config file not found: $config_source"
if grep -Eq '^(health_check|metrics):[[:space:]]*($|#)' "$config_source"; then
  die "base config must omit top-level health_check and metrics sections; this installer manages them"
fi

# Fail closed if the supplied config no longer contains the security boundaries
# selected for this deployment model.
grep -Eq '^[[:space:]]*file:[[:space:]]*/var/lib/gitea-runner/\.runner[[:space:]]*$' "$config_source" ||
  die "config must set runner.file to /var/lib/gitea-runner/.runner"
grep -Eq '^[[:space:]]*docker_host:[[:space:]]*"-"[[:space:]]*$' "$config_source" ||
  die 'config must set container.docker_host to "-"'
grep -Eq '^[[:space:]]*privileged:[[:space:]]*false[[:space:]]*$' "$config_source" ||
  die "config must disable privileged Job containers"
grep -Eq '^[[:space:]]*valid_volumes:[[:space:]]*\[\][[:space:]]*$' "$config_source" ||
  die "config must set container.valid_volumes to []"
grep -Eq '^[[:space:]]*bind_workdir:[[:space:]]*false[[:space:]]*$' "$config_source" ||
  die "config must disable container.bind_workdir"
grep -Eq '^[[:space:]]*require_docker:[[:space:]]*true[[:space:]]*$' "$config_source" ||
  die "config must require a reachable Docker daemon"

if [[ ! -d "$runner_runtime_dir" ]]; then
  die "Rootless Docker runtime directory not found: $runner_runtime_dir; install and start it first with: sudo $script_dir/docker-rootless.sh $runner_user"
fi

runtime_dir_uid="$(stat -c '%u' "$runner_runtime_dir")"
[[ "$runtime_dir_uid" == "$runner_uid" ]] ||
  die "$runner_runtime_dir must be owned by UID $runner_uid"

if [[ ! -S "$docker_socket" ]]; then
  die "Rootless Docker socket not found: $docker_socket; install and start it first with: sudo $script_dir/docker-rootless.sh $runner_user"
fi

docker_socket_uid="$(stat -c '%u' "$docker_socket")"
[[ "$docker_socket_uid" == "$runner_uid" ]] ||
  die "$docker_socket must be owned by UID $runner_uid"

run_as_runner systemctl --user is-enabled --quiet docker.service ||
  die "the Rootless Docker user service is not enabled for $runner_user"
run_as_runner systemctl --user is-active --quiet docker.service ||
  die "the Rootless Docker user service is not active for $runner_user"

docker_security_options="$(
  run_as_runner "$docker_binary" info --format '{{json .SecurityOptions}}'
)" || die "cannot query Rootless Docker through $docker_host as $runner_user"

if [[ "$docker_security_options" != *'name=rootless'* ]]; then
  die "the Docker daemon reachable at $docker_host is not running in rootless mode"
fi

case "$(uname -m)" in
  x86_64|amd64)
    runner_arch="amd64"
    ;;
  aarch64|arm64)
    runner_arch="arm64"
    ;;
  armv7l|armv7)
    runner_arch="arm-7"
    ;;
  loongarch64)
    runner_arch="loong64"
    ;;
  riscv64|s390x)
    runner_arch="$(uname -m)"
    ;;
  *)
    die "unsupported CPU architecture: $(uname -m)"
    ;;
esac

if [[ -z "$runner_name" ]]; then
  runner_name="$(hostname -f 2>/dev/null || hostname)"
fi
[[ -n "$runner_name" ]] || die "runner name cannot be empty"

asset_name="gitea-runner-$runner_version-linux-$runner_arch"
download_url="$downloads_url/$runner_version/$asset_name"
download_dir="$(mktemp -d /tmp/gitea-runner-install.XXXXXX)"

info "Downloading Gitea Runner $runner_version for linux/$runner_arch"
curl --fail --location --silent --show-error \
  --proto '=https' --proto-redir '=https' --tlsv1.2 \
  --output "$download_dir/$asset_name" "$download_url"
curl --fail --location --silent --show-error \
  --proto '=https' --proto-redir '=https' --tlsv1.2 \
  --output "$download_dir/$asset_name.sha256" "$download_url.sha256"

info "Verifying the published SHA-256 checksum"
(
  cd "$download_dir"
  sha256sum --check "$asset_name.sha256"
)

install -d -o "$runner_user" -g "$runner_group" -m 0700 "$state_dir"

# The Runner may read its configuration through its primary group, but only
# root may modify the installed directory or file.
install -d -o root -g "$runner_group" -m 0750 "$config_dir"

info "Installing $binary_path"
install -o root -g root -m 0755 "$download_dir/$asset_name" "$binary_path.new"
mv -f -- "$binary_path.new" "$binary_path"
"$binary_path" --version

info "Installing $config_dest"
rendered_config="$download_dir/config.yaml"
install -m 0600 "$config_source" "$rendered_config"

if (( enable_health_metrics == 1 )); then
  info "Enabling local health checks and metrics on 127.0.0.1:9101"
  cat >> "$rendered_config" <<'EOF'

health_check:
  enabled: true
  min_free_disk_space_mb: 1024
  script: ""
  interval: "30s"
  timeout: "10s"

metrics:
  enabled: true
  addr: "127.0.0.1:9101"
  readiness_grace: "30s"
EOF
fi

install -o root -g "$runner_group" -m 0640 "$rendered_config" "$config_dest"

[[ "$(stat -c '%u:%g:%a' "$config_dir")" == "0:$runner_gid:750" ]] || \
  die "Unexpected ownership or mode on $config_dir; expected root:$runner_group with mode 0750."
[[ "$(stat -c '%u:%g:%a' "$config_dest")" == "0:$runner_gid:640" ]] || \
  die "Unexpected ownership or mode on $config_dest; expected root:$runner_group with mode 0640."

unit_source="$download_dir/$service_name"
cat > "$unit_source" <<EOF
[Unit]
Description=Gitea Actions runner with Rootless Docker
Documentation=https://docs.gitea.com/runner/
After=network-online.target user@${runner_uid}.service
Wants=network-online.target
Requires=user@${runner_uid}.service

[Service]
Type=simple
User=$runner_user
Group=$runner_group
WorkingDirectory=$state_dir
Environment=XDG_RUNTIME_DIR=$runner_runtime_dir
Environment=DOCKER_HOST=$docker_host
UnsetEnvironment=DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH
ExecStartPre=$docker_binary --host=$docker_host info
ExecStart=$binary_path daemon --config $config_dest
Restart=on-failure
RestartSec=5s
TimeoutStopSec=10m
UMask=0077

# Rootless Docker limits daemon authority to this Unix user. Access to its
# socket still grants control over that user's containers, images and volumes.
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$state_dir
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6

[Install]
WantedBy=multi-user.target
EOF

info "Installing $service_path"
install -o root -g root -m 0644 "$unit_source" "$service_path"
systemctl daemon-reload

if [[ -L "$registration_file" ]]; then
  die "$registration_file must not be a symbolic link"
elif [[ -e "$registration_file" && ! -f "$registration_file" ]]; then
  die "$registration_file must be a regular file"
elif [[ -f "$registration_file" ]]; then
  info "Keeping the existing runner registration"
  registration_token=""
  chown "$runner_user:$runner_group" "$registration_file"
  chmod 0600 "$registration_file"
elif (( skip_register == 1 )); then
  info "Registration skipped; the service will not be started"
  start_service=0
else
  info "Registering $runner_name"
  (
    cd "$state_dir"
    run_as_runner \
      "$binary_path" register \
      --config "$config_dest" \
      --no-interactive \
      --instance "$instance_url" \
      --token "$registration_token" \
      --name "$runner_name"
  )
  registration_token=""

  [[ -s "$registration_file" ]] || die "registration did not create $registration_file"
  chown "$runner_user:$runner_group" "$registration_file"
  chmod 0600 "$registration_file"
fi

if (( start_service == 1 )); then
  info "Enabling and starting $service_name"
  systemctl enable "$service_name"
  systemctl restart "$service_name"
  systemctl is-active --quiet "$service_name" ||
    die "$service_name did not become active; inspect it with journalctl"
  info "$service_name is active"
else
  info "Service start skipped"
fi

printf '\nInstallation complete.\n'
printf '  Runner user:  %s (UID %s)\n' "$runner_user" "$runner_uid"
printf '  Binary:       %s\n' "$binary_path"
printf '  Configuration: %s\n' "$config_dest"
printf '  Registration: %s\n' "$registration_file"
printf '  Service:       %s\n' "$service_path"
printf '  Rootless Docker: %s\n' "$docker_host"
if (( enable_health_metrics == 1 )); then
  printf '  Health/metrics: enabled at http://127.0.0.1:9101\n'
else
  printf '  Health/metrics: disabled\n'
fi
