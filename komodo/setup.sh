#!/usr/bin/env bash
# Clone Komodo into ./app and build/run with Docker Compose
set -e
cd "$(dirname "$0")"
if [[ ! -d app/.git ]]; then
  echo "Cloning https://github.com/moghtech/komodo into ./app ..."
  git clone --depth 1 https://github.com/moghtech/komodo.git app
fi
docker compose up -d --build
