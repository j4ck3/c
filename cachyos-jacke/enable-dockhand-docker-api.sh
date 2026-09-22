#!/usr/bin/env bash
set -euo pipefail

NETBIRD_IP="${NETBIRD_IP:-100.113.53.57}"
LISTEN_PORT="${LISTEN_PORT:-2375}"
SOCKET_PATH="${DOCKER_SOCKET:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock}"
SERVICE_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SERVICE_DIR}/dockhand-docker-api.service"

if ! command -v socat >/dev/null 2>&1; then
  echo "socat is missing. Install it first:"
  echo "  sudo pacman -S socat"
  exit 1
fi

if [ ! -S "${SOCKET_PATH}" ]; then
  echo "Docker socket not found at ${SOCKET_PATH}"
  echo "Start rootless Docker first, then rerun this script."
  exit 1
fi

mkdir -p "${SERVICE_DIR}"

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Expose rootless Docker API to Dockhand over NetBird
After=docker.service docker.socket

[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:${LISTEN_PORT},bind=${NETBIRD_IP},reuseaddr,fork UNIX-CONNECT:${SOCKET_PATH}
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now dockhand-docker-api.service

echo "Dockhand Docker API listener enabled:"
echo "  http://${NETBIRD_IP}:${LISTEN_PORT}/_ping"
echo
echo "Test from tower:"
echo "  curl http://${NETBIRD_IP}:${LISTEN_PORT}/_ping"
