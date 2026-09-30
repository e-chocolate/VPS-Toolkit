#!/usr/bin/env bash

set -Eeuo pipefail

RUNNER_USER="$(systemctl show gitea-runner.service \
  --property=User --value)"

RUNNER_UID="$(id -u "$RUNNER_USER")"
RUNNER_GROUP="$(id -gn "$RUNNER_USER")"
RUNNER_HOME="$(getent passwd "$RUNNER_USER" | cut -d: -f6)"

runner_docker() {
  runuser \
    -u "$RUNNER_USER" \
    -g "$RUNNER_GROUP" \
    -- env \
      HOME="$RUNNER_HOME" \
      USER="$RUNNER_USER" \
      LOGNAME="$RUNNER_USER" \
      XDG_RUNTIME_DIR="/run/user/$RUNNER_UID" \
      DOCKER_HOST="unix:///run/user/$RUNNER_UID/docker.sock" \
      docker "$@"
}

runner_docker info --format '{{json .SecurityOptions}}'
