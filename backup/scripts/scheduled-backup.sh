#!/bin/bash
# =============================================================================
# Scheduled Backup Orchestrator (no VM backup)
# =============================================================================
# Runs: restic directory backup -> rclone sync OneDrive -> rclone sync Main PC.
# Sends ONE wide-event style Telegram message at the end with full context.
# Invoked by crond at 3 AM nightly.
# =============================================================================

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/backup"
mkdir -p "$LOG_DIR"

# When running in backup-scheduler container: restic repo is at /repo and /backup, rclone config at /config
export RCLONE_CONFIG="${RCLONE_CONFIG:-/config/rclone.conf}"
LOG_FILE="${LOG_DIR}/backup-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# -----------------------------------------------------------------------------
# Wide-event payload (collect as we go)
# -----------------------------------------------------------------------------
START_TIME=$(date +%s)
REPORT_HOST="${HOSTNAME:-UnraidBackup}"
REPORT_TIME=$(date '+%Y-%m-%d %H:%M')
STEP1_NAME="Directory Backup"
STEP1_DURATION=""
STEP1_STATUS=""
STEP1_DETAIL=""
STEP2_NAME="OneDrive Sync"
STEP2_DURATION=""
STEP2_STATUS=""
STEP2_DETAIL=""
STEP3_NAME="Main PC Sync"
STEP3_DURATION=""
STEP3_STATUS=""
STEP3_DETAIL=""
ERROR_COUNT=0

# -----------------------------------------------------------------------------
# Telegram (single message at end)
# -----------------------------------------------------------------------------
TELEGRAM_ENABLED="${TELEGRAM_ENABLED:-false}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

telegram_send() {
    local text="$1"
    if [ "$TELEGRAM_ENABLED" != "true" ] || [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        return 0
    fi
    # Truncate to ~4000 chars; send as plain text so report formatting is preserved
    local body
    body=$(printf '%s' "$text" | head -c 4000)
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${body}" \
        -d "disable_web_page_preview=true" \
        > /dev/null 2>&1 || true
}

# -----------------------------------------------------------------------------
# Step 1: Restic directory backup
# -----------------------------------------------------------------------------
echo "=============================================="
echo "  Step 1: Directory Backup (restic)"
echo "=============================================="
STEP1_START=$(date +%s)
STEP1_OUTPUT="${LOG_DIR}/step1.$$.log"
if /bin/bash /scripts/backup.sh 2>&1 | tee "$STEP1_OUTPUT"; then
    STEP1_STATUS="OK"
else
    STEP1_STATUS="FAILED"
    STEP1_DETAIL=$(tail -3 "$STEP1_OUTPUT" 2>/dev/null | tr '\n' ' ' || echo "see log")
    ((ERROR_COUNT++)) || true
fi
rm -f "$STEP1_OUTPUT"
STEP1_END=$(date +%s)
STEP1_DURATION=$((STEP1_END - STEP1_START))

# -----------------------------------------------------------------------------
# Step 2: Rclone sync to OneDrive
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Step 2: OneDrive Sync"
echo "=============================================="
STEP2_START=$(date +%s)
STEP2_OUTPUT="${LOG_DIR}/step2.$$.log"
if /bin/bash /scripts/sync-remotes.sh onedrive 2>&1 | tee "$STEP2_OUTPUT"; then
    STEP2_STATUS="OK"
else
    STEP2_STATUS="FAILED"
    STEP2_DETAIL=$(tail -3 "$STEP2_OUTPUT" 2>/dev/null | tr '\n' ' ' || echo "see log")
    ((ERROR_COUNT++)) || true
fi
rm -f "$STEP2_OUTPUT"
STEP2_END=$(date +%s)
STEP2_DURATION=$((STEP2_END - STEP2_START))

# -----------------------------------------------------------------------------
# Step 3: Rclone sync to Main PC
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Step 3: Main PC Sync"
echo "=============================================="
STEP3_START=$(date +%s)
STEP3_OUTPUT="${LOG_DIR}/step3.$$.log"
if /bin/bash /scripts/sync-remotes.sh mainpc 2>&1 | tee "$STEP3_OUTPUT"; then
    STEP3_STATUS="OK"
else
    STEP3_STATUS="FAILED"
    STEP3_DETAIL=$(tail -3 "$STEP3_OUTPUT" 2>/dev/null | tr '\n' ' ' || echo "see log")
    ((ERROR_COUNT++)) || true
fi
rm -f "$STEP3_OUTPUT"
STEP3_END=$(date +%s)
STEP3_DURATION=$((STEP3_END - STEP3_START))

# -----------------------------------------------------------------------------
# Build wide-event report and send single Telegram message
# -----------------------------------------------------------------------------
END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))
TOTAL_MIN=$((TOTAL_DURATION / 60))
TOTAL_SEC=$((TOTAL_DURATION % 60))
if [ $ERROR_COUNT -eq 0 ]; then
    OVERALL_STATUS="OK"
else
    OVERALL_STATUS="ERRORS ($ERROR_COUNT/3 steps)"
fi

REPORT="BACKUP REPORT | ${REPORT_HOST}
${REPORT_TIME} | Duration: ${TOTAL_MIN}m ${TOTAL_SEC}s | Status: ${OVERALL_STATUS}

--- ${STEP1_NAME} (${STEP1_DURATION}s) ---  ${STEP1_STATUS}
${STEP1_DETAIL:+  ${STEP1_DETAIL}}

--- ${STEP2_NAME} (${STEP2_DURATION}s) ---  ${STEP2_STATUS}
${STEP2_DETAIL:+  ${STEP2_DETAIL}}

--- ${STEP3_NAME} (${STEP3_DURATION}s) ---  ${STEP3_STATUS}
${STEP3_DETAIL:+  ${STEP3_DETAIL}}

Log: $(basename "$LOG_FILE")"

echo ""
echo "=============================================="
echo "  Scheduled backup finished: $(date)"
echo "  Duration: ${TOTAL_MIN}m ${TOTAL_SEC}s | Errors: ${ERROR_COUNT}/3"
echo "=============================================="

telegram_send "$REPORT"

# Clean old logs (keep last 30 days)
find "$LOG_DIR" -name "backup-*.log" -mtime +30 -delete 2>/dev/null || true

exit $ERROR_COUNT
