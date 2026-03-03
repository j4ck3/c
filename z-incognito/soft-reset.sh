#!/bin/sh
# Soft reset: clear browser data, clipboard, DNS cache. Runs inside neko container.

set -e

echo "Clearing X clipboard..."
DISPLAY="${DISPLAY:-:99}" xclip -selection clipboard -c 2>/dev/null || \
  echo -n | DISPLAY="${DISPLAY:-:99}" xclip -selection clipboard 2>/dev/null || true

echo "Clearing DNS cache..."
resolvectl flush-caches 2>/dev/null || \
  nscd -i hosts 2>/dev/null || \
  true

echo "Stopping Chromium..."
supervisorctl stop chromium

echo "Clearing browser history and data..."
BRAVE_DIR="/home/neko/.config/BraveSoftware/Brave-Browser"
rm -rf "${BRAVE_DIR}/Default"
rm -rf "${BRAVE_DIR}/GrShaderCache" "${BRAVE_DIR}/ShaderCache"
rm -rf "${BRAVE_DIR}/GraphiteDawnCache" "${BRAVE_DIR}/DawnGraphiteCache" "${BRAVE_DIR}/DawnWebGPUCache" 2>/dev/null || true
rm -rf "${BRAVE_DIR}/component_crx_cache" "${BRAVE_DIR}/extensions_crx_cache"
rm -rf "${BRAVE_DIR}/Crash Reports" "${BRAVE_DIR}/Safe Browsing" 2>/dev/null || true

echo "Starting Chromium..."
supervisorctl start chromium

echo "Soft reset complete."
