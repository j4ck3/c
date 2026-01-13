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
# =============================================================================

set -e

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
NC='\033[0m'

# Logging
LOG_FILE="/mnt/user/backups/logs/backup-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

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
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --no-vm      Skip VM backup (no shutdown)"
            echo "  --no-sync    Skip remote sync (OneDrive/PC)"
            echo "  --dry-run    Show what would be done"
            echo "  --help       Show this help"
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
    
    # =========================================================================
    # Step 1: Regular Directory Backup
    # =========================================================================
    log_section "Step 1: Regular Directory Backup"
    
    cd "$BACKUP_DIR"
    
    if [ "$DRY_RUN" = true ]; then
        docker compose run --rm backup-runner /scripts/backup.sh --dry-run 2>&1 | tee -a "$LOG_FILE" || {
            log_error "Regular backup dry-run failed"
            ((errors++))
        }
    else
        docker compose run --rm backup-runner 2>&1 | tee -a "$LOG_FILE" || {
            log_error "Regular backup failed"
            ((errors++))
        }
    fi
    
    # =========================================================================
    # Step 2: Windows VM Backup
    # =========================================================================
    if [ "$SKIP_VM" = true ]; then
        log_section "Step 2: Windows VM Backup (SKIPPED)"
    else
        log_section "Step 2: Windows VM Backup"
        
        if [ "$DRY_RUN" = true ]; then
            log_info "Would shut down VM, backup disk, restart VM"
        else
            # VM backup runs on host (not in container) because it needs virsh
            bash "$SCRIPT_DIR/vm-backup.sh" 2>&1 | tee -a "$LOG_FILE" || {
                log_error "VM backup failed"
                ((errors++))
            }
        fi
    fi
    
    # =========================================================================
    # Step 3: Sync to Remote Destinations
    # =========================================================================
    if [ "$SKIP_SYNC" = true ]; then
        log_section "Step 3: Remote Sync (SKIPPED)"
    else
        log_section "Step 3: Sync to OneDrive"
        
        local sync_flags=""
        if [ "$DRY_RUN" = true ]; then
            sync_flags="--dry-run"
        fi
        
        docker compose run --rm rclone /scripts/sync-remotes.sh $sync_flags onedrive 2>&1 | tee -a "$LOG_FILE" || {
            log_error "OneDrive sync failed"
            ((errors++))
        }
        
        log_section "Step 4: Sync to Main PC"
        
        docker compose run --rm rclone /scripts/sync-remotes.sh $sync_flags mainpc 2>&1 | tee -a "$LOG_FILE" || {
            log_error "Main PC sync failed"
            ((errors++))
        }
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
    
    # Clean up old logs (keep last 30 days)
    find /mnt/user/backups/logs -name "backup-*.log" -mtime +30 -delete 2>/dev/null || true
    
    return $errors
}

main "$@"

