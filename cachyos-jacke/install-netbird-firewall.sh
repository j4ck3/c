#!/usr/bin/env bash
# Allow Netdata (19999) only from Netbird CGNAT + localhost.
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

if ! command -v ufw >/dev/null 2>&1; then
  echo "ufw not installed. Install with: pacman -S ufw" >&2
  exit 1
fi

ufw allow from 100.64.0.0/10 to any port 19999 proto tcp comment 'netdata netbird'
ufw allow from 127.0.0.0/8 to any port 19999 proto tcp comment 'netdata localhost'
ufw deny 19999/tcp comment 'netdata deny others'

echo "Netdata port 19999 restricted to Netbird mesh + localhost."
echo "Enable UFW if needed: ufw enable && ufw status"
