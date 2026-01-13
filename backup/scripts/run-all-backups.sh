#!/bin/bash
# =============================================================================
# Master Backup Orchestrator
# =============================================================================
# This script runs the complete backup workflow:
# 1. Regular directory backup (restic)
# 2. Windows VM backup (with shutdown/restart)
# 3. Sync to OneDrive
# 4. Sync to Main PC
#
# This is the script to schedule with cron or Unraid User Scripts!
#
# Usage:
#   ./run-all-backups.sh              # Run full backup
#   ./run-all-backups.sh --no-vm      # Skip VM backup
#   ./run-all-backups.sh --no-sync    # Skip remote sync
#   ./run-all-backups.sh --dry-run    # Show what would be done
#   ./run-all-backups.sh --silent     # No Telegram notifications
# =============================================================================

set -e
set -o pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$BACKUP_DIR/.env" ]; then
    set -a
    source "$BACKUP_DIR/.env"
    set +a
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
LOG_FILE="/mnt/user/backups/logs/backup-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

# =============================================================================
# Telegram Configuration
# =============================================================================
# Set these in your .env file:
#   TELEGRAM_BOT_TOKEN=your_bot_token
#   TELEGRAM_CHAT_ID=your_chat_id
#   TELEGRAM_ENABLED=true
# =============================================================================

TELEGRAM_ENABLED=${TELEGRAM_ENABLED:-false}
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-""}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID:-""}
HOSTNAME=$(hostname)

# =============================================================================
# Telegram Functions
# =============================================================================

telegram_send() {
    local message="$1"
    local parse_mode="${2:-HTML}"
    
    if [ "$TELEGRAM_ENABLED" != "true" ] || [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        return 0
    fi
    
    if [ "$SILENT_MODE" = true ]; then
        return 0
    fi
    
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "parse_mode=${parse_mode}" \
        -d "text=${message}" \
        -d "disable_web_page_preview=true" \
        > /dev/null 2>&1 || true
}

telegram_start() {
    local mode=""
    [ "$DRY_RUN" = true ] && mode=" (DRY RUN)"
    [ "$SKIP_VM" = true ] && mode="$mode (NO VM)"
    [ "$SKIP_SYNC" = true ] && mode="$mode (NO SYNC)"
    
    telegram_send "🚀 <b>Backup Started</b>${mode}

🖥️ <b>Server:</b> ${HOSTNAME}
📅 <b>Time:</b> $(date '+%Y-%m-%d %H:%M:%S')
📁 <b>Log:</b> <code>${LOG_FILE}</code>"
}

telegram_step() {
    local step_num="$1"
    local step_name="$2"
    local status="$3"  # start, success, failed, skipped
    
    local icon=""
    case "$status" in
        start)   icon="⏳" ;;
        success) icon="✅" ;;
        failed)  icon="❌" ;;
        skipped) icon="⏭️" ;;
    esac
    
    telegram_send "${icon} <b>Step ${step_num}:</b> ${step_name}
<i>Status: ${status}</i>"
}

telegram_error() {
    local step="$1"
    local error_msg="$2"
    
    telegram_send "🚨 <b>Error in ${step}</b>

<code>${error_msg}</code>

🖥️ Server: ${HOSTNAME}
📅 Time: $(date '+%Y-%m-%d %H:%M:%S')"
}

telegram_summary() {
    local duration_min="$1"
    local duration_sec="$2"
    local errors="$3"
    local details="$4"
    
    local status_icon="✅"
    local status_text="SUCCESS"
    
    if [ "$errors" -gt 0 ]; then
        status_icon="⚠️"
        status_text="COMPLETED WITH ${errors} ERROR(S)"
    fi
    
    telegram_send "${status_icon} <b>Backup ${status_text}</b>

🖥️ <b>Server:</b> ${HOSTNAME}
⏱️ <b>Duration:</b> ${duration_min}m ${duration_sec}s
📅 <b>Finished:</b> $(date '+%Y-%m-%d %H:%M:%S')

${details}

📁 <b>Log:</b> <code>${LOG_FILE}</code>"
}

# =============================================================================
# Logging Functions
# =============================================================================

log() {
    local level=$1
    local color=$2
    local message=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${color}[${level}]${NC} ${timestamp} - ${message}" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$BLUE" "$1"; }
log_success() { log "SUCCESS" "$GREEN" "$1"; }
log_warn() { log "WARN" "$YELLOW" "$1"; }
log_error() { log "ERROR" "$RED" "$1"; }

log_section() { 
    echo "" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}========================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}  $1${NC}" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}========================================${NC}" | tee -a "$LOG_FILE"
}

# =============================================================================
# Parse Arguments
# =============================================================================
SKIP_VM=false
SKIP_SYNC=false
DRY_RUN=false
SILENT_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-vm)
            SKIP_VM=true
            shift
            ;;
        --no-sync)
            SKIP_SYNC=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --silent)
            SILENT_MODE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --no-vm      Skip VM backup (no shutdown)"
            echo "  --no-sync    Skip remote sync (OneDrive/PC)"
            echo "  --dry-run    Show what would be done"
            echo "  --silent     Disable Telegram notifications"
            echo "  --help       Show this help"
            echo ""
            echo "Telegram Setup:"
            echo "  Add these to your .env file:"
            echo "    TELEGRAM_ENABLED=true"
            echo "    TELEGRAM_BOT_TOKEN=your_bot_token"
            echo "    TELEGRAM_CHAT_ID=your_chat_id"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# =============================================================================
# Main Backup Workflow
# =============================================================================

main() {
    local start_time=$(date +%s)
    local errors=0
    local step_results=""
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║           UNRAID BACKUP SYSTEM - FULL BACKUP RUN                  ║"
    echo "║           Started: $(date)                       ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    log_info "Log file: $LOG_FILE"
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN MODE - No changes will be made"
    fi
    
    # Check Telegram configuration
    if [ "$TELEGRAM_ENABLED" = "true" ] && [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        log_info "Telegram notifications: ENABLED"
    else
        log_info "Telegram notifications: DISABLED"
    fi
    
    # Send start notification
    telegram_start
    
    # =========================================================================
    # Step 1: Regular Directory Backup
    # =========================================================================
    log_section "Step 1: Regular Directory Backup"
    telegram_step "1" "Regular Directory Backup" "start"
    
    cd "$BACKUP_DIR"
    
    local step1_start=$(date +%s)
    if [ "$DRY_RUN" = true ]; then
        docker compose run --rm backup-runner /scripts/backup.sh --dry-run 2>&1 | tee -a "$LOG_FILE"
        local step1_exit=${PIPESTATUS[0]}
    else
        docker compose run --rm backup-runner 2>&1 | tee -a "$LOG_FILE"
        local step1_exit=${PIPESTATUS[0]}
    fi
    local step1_duration=$(($(date +%s) - step1_start))
    
    if [ $step1_exit -eq 0 ]; then
        log_success "Regular backup completed (${step1_duration}s)"
        telegram_step "1" "Regular Directory Backup" "success"
        step_results="${step_results}✅ Directory Backup: OK (${step1_duration}s)\n"
    else
        log_error "Regular backup failed (exit code: $step1_exit)"
        telegram_step "1" "Regular Directory Backup" "failed"
        telegram_error "Directory Backup" "Backup failed after ${step1_duration}s (exit: $step1_exit)"
        step_results="${step_results}❌ Directory Backup: FAILED\n"
        ((errors++))
    fi
    
    # =========================================================================
    # Step 2: Windows VM Backup
    # =========================================================================
    if [ "$SKIP_VM" = true ]; then
        log_section "Step 2: Windows VM Backup (SKIPPED)"
        telegram_step "2" "Windows VM Backup" "skipped"
        step_results="${step_results}⏭️ VM Backup: Skipped\n"
    else
        log_section "Step 2: Windows VM Backup"
        telegram_step "2" "Windows VM Backup" "start"
        
        local step2_start=$(date +%s)
        if [ "$DRY_RUN" = true ]; then
            log_info "Would shut down VM, backup disk, restart VM"
            telegram_step "2" "Windows VM Backup" "success"
            step_results="${step_results}✅ VM Backup: OK (dry-run)\n"
        else
            # VM backup runs on host (not in container) because it needs virsh
            bash "$SCRIPT_DIR/vm-backup.sh" 2>&1 | tee -a "$LOG_FILE"
            local step2_exit=${PIPESTATUS[0]}
            local step2_duration=$(($(date +%s) - step2_start))
            
            if [ $step2_exit -eq 0 ]; then
                log_success "VM backup completed (${step2_duration}s)"
                telegram_step "2" "Windows VM Backup" "success"
                step_results="${step_results}✅ VM Backup: OK (${step2_duration}s)\n"
            else
                log_error "VM backup failed (exit code: $step2_exit)"
                telegram_step "2" "Windows VM Backup" "failed"
                telegram_error "VM Backup" "Backup failed after ${step2_duration}s (exit: $step2_exit)"
                step_results="${step_results}❌ VM Backup: FAILED\n"
                ((errors++))
            fi
        fi
    fi
    
    # =========================================================================
    # Step 3: Sync to Remote Destinations
    # =========================================================================
    if [ "$SKIP_SYNC" = true ]; then
        log_section "Step 3: Remote Sync (SKIPPED)"
        telegram_step "3" "OneDrive Sync" "skipped"
        telegram_step "4" "Main PC Sync" "skipped"
        step_results="${step_results}⏭️ OneDrive Sync: Skipped\n"
        step_results="${step_results}⏭️ Main PC Sync: Skipped\n"
    else
        log_section "Step 3: Sync to OneDrive"
        telegram_step "3" "OneDrive Sync" "start"
        
        local sync_flags=""
        if [ "$DRY_RUN" = true ]; then
            sync_flags="--dry-run"
        fi
        
        local step3_start=$(date +%s)
        # Run sync script on host (it handles docker internally if needed)
        bash "$SCRIPT_DIR/sync-remotes.sh" $sync_flags onedrive 2>&1 | tee -a "$LOG_FILE"
        local step3_exit=${PIPESTATUS[0]}
        local step3_duration=$(($(date +%s) - step3_start))
        
        if [ $step3_exit -eq 0 ]; then
            log_success "OneDrive sync completed (${step3_duration}s)"
            telegram_step "3" "OneDrive Sync" "success"
            step_results="${step_results}✅ OneDrive Sync: OK (${step3_duration}s)\n"
        else
            log_error "OneDrive sync failed (exit code: $step3_exit)"
            telegram_step "3" "OneDrive Sync" "failed"
            telegram_error "OneDrive Sync" "Sync failed after ${step3_duration}s (exit: $step3_exit)"
            step_results="${step_results}❌ OneDrive Sync: FAILED\n"
            ((errors++))
        fi
        
        log_section "Step 4: Sync to Main PC"
        telegram_step "4" "Main PC Sync" "start"
        
        local step4_start=$(date +%s)
        # Run sync script on host (it handles docker internally if needed)
        bash "$SCRIPT_DIR/sync-remotes.sh" $sync_flags mainpc 2>&1 | tee -a "$LOG_FILE"
        local step4_exit=${PIPESTATUS[0]}
        local step4_duration=$(($(date +%s) - step4_start))
        
        if [ $step4_exit -eq 0 ]; then
            log_success "Main PC sync completed (${step4_duration}s)"
            telegram_step "4" "Main PC Sync" "success"
            step_results="${step_results}✅ Main PC Sync: OK (${step4_duration}s)\n"
        else
            log_error "Main PC sync failed (exit code: $step4_exit)"
            telegram_step "4" "Main PC Sync" "failed"
            telegram_error "Main PC Sync" "Sync failed after ${step4_duration}s (exit: $step4_exit)"
            step_results="${step_results}❌ Main PC Sync: FAILED\n"
            ((errors++))
        fi
    fi
    
    # =========================================================================
    # Summary
    # =========================================================================
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local duration_min=$((duration / 60))
    local duration_sec=$((duration % 60))
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║                      BACKUP COMPLETE                              ║"
    echo "╠═══════════════════════════════════════════════════════════════════╣"
    echo "║  Finished: $(date)                       ║"
    echo "║  Duration: ${duration_min}m ${duration_sec}s                                           ║"
    if [ $errors -gt 0 ]; then
        echo "║  Status: COMPLETED WITH $errors ERROR(S)                            ║"
    else
        echo "║  Status: SUCCESS                                                ║"
    fi
    echo "║  Log: $LOG_FILE"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    
    # Send final summary to Telegram
    telegram_summary "$duration_min" "$duration_sec" "$errors" "$(echo -e "$step_results")"
    
    # Clean up old logs (keep last 30 days)
    find /mnt/user/backups/logs -name "backup-*.log" -mtime +30 -delete 2>/dev/null || true
    
    return $errors
}

main "$@"
