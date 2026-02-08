#!/bin/sh
# Build backup-scheduler image with legacy Docker builder (avoids buildx 0.17+ requirement).
# Run once, then: docker compose up -d
set -e
cd "$(dirname "$0")"
DOCKER_BUILDKIT=0 docker build -t backup-scheduler:latest .
