#!/bin/bash
set -euo pipefail

echo "[$(date -Iseconds)] docker prune start"
docker image prune -f
docker builder prune -f
echo "[$(date -Iseconds)] docker prune done"
