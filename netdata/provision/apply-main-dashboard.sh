#!/usr/bin/env bash
# Generate dashboard JSON and copy into the Netdata web root (custom/).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WEB_DIR="${COMPOSE_DIR}/web"
PROVISION_DIR="${SCRIPT_DIR}"
CACHE_WEB_DIR="/mnt/cache/appdata/netdata/web/custom"
CACHE_CHARTS_DIR="/mnt/cache/appdata/netdata/charts.d"

mkdir -p "${WEB_DIR}/custom" "${CACHE_WEB_DIR}" "${CACHE_CHARTS_DIR}"
python3 "${PROVISION_DIR}/generate-main-dashboard.py" > "${PROVISION_DIR}/main-dashboard.json"
cp "${PROVISION_DIR}/main-dashboard.json" "${WEB_DIR}/custom/main-dashboard.json"
cp "${WEB_DIR}/provision-main.html" "${WEB_DIR}/custom/provision-main.html"
cp "${PROVISION_DIR}/main-dashboard.json" "${CACHE_WEB_DIR}/main-dashboard.json"
cp "${WEB_DIR}/provision-main.html" "${CACHE_WEB_DIR}/provision-main.html"
cp "${COMPOSE_DIR}/charts.d/"* "${CACHE_CHARTS_DIR}/"

echo "Generated ${WEB_DIR}/custom/main-dashboard.json"
echo "Deployed to ${CACHE_WEB_DIR}/main-dashboard.json"
echo "Synced charts.d to ${CACHE_CHARTS_DIR}/"
echo ""
echo "Next steps:"
echo "  1. docker compose -f ${COMPOSE_DIR}/compose.yml up -d"
echo "  2. Open once: https://netdata.hjacke.com/custom/provision-main.html"
echo "     (or http://<host>:19999/custom/provision-main.html)"
echo "  3. You will be redirected to the 'main' dashboard."
