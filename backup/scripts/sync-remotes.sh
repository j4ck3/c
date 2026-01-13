#!/bin/bash
# =============================================================================
# Remote Sync Script - Sync Restic Repository to OneDrive and Main PC
# =============================================================================
# This script uses rclone to sync your local restic backup repository to:
# 1. OneDrive (cloud backup)
# 2. Main PC via SFTP (local network backup)
#
# Usage:
#   ./sync-remotes.sh              # Sync to all remotes
#   ./sync-remotes.sh onedrive     # Sync to OneDrive only
#   ./sync-remotes.sh mainpc       # Sync to main PC only
#   ./sync-remotes.sh --dry-run    # Show what would be synced
#
# Run via Docker:
#   docker compose run --rm rclone /scripts/sync-remotes.sh
# =============================================================================

set -e

# =============================================================================
# CONFIGURATION
# =============================================================================
# Try cache path first (preferred), then user path
if [ -d "/mnt/cache/backups/restic" ]; then
    BACKUP_SOURCE="/mnt/cache/backups/restic"
elif [ -d "/mnt/user/backups/restic" ]; then
    BACKUP_SOURCE="/mnt/user/backups/restic"
else
    BACKUP_SOURCE="/mnt/user/backups/restic"  # Default, will fail with clear error
fi

# Try to find rclone.conf in common locations
if [ -f "/mnt/cache/documents/compose/backup/rclone.conf" ]; then
    RCLONE_CONFIG="/mnt/cache/documents/compose/backup/rclone.conf"
elif [ -f "/mnt/user/documents/compose/backup/rclone.conf" ]; then
    RCLONE_CONFIG="/mnt/user/documents/compose/backup/rclone.conf"
else
    RCLONE_CONFIG="/mnt/user/documents/compose/backup/rclone.conf"  # Default
fi

# Remote destinations (must match names in rclone.conf)
ONEDRIVE_REMOTE="onedrive"
ONEDRIVE_PATH="${ONEDRIVE_PATH:-Backups/unraid}"

MAINPC_REMOTE="mainpc"
MAINPC_PATH="${MAINPC_PATH:-/home/user/backups/unraid}"

# Bandwidth limits (optional, set to 0 for unlimited)
BANDWIDTH_LIMIT_ONEDRIVE="0"      # e.g., "10M" for 10 MB/s
BANDWIDTH_LIMIT_MAINPC="0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# =============================================================================
# Helper Functions
# =============================================================================

# Check if running in Docker
in_docker() {
    [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null
}

# Get rclone command (native or docker)
get_rclone_cmd() {
    if command -v rclone &> /dev/null; then
        echo "rclone"
    elif in_docker; then
        echo "rclone"
    elif command -v docker &> /dev/null; then
        echo "docker run --rm -v ${RCLONE_CONFIG}:/config/rclone.conf -v ${BACKUP_SOURCE}:/backup:ro rclone/rclone --config /config/rclone.conf"
    else
        log_error "rclone not found!"
        exit 1
    fi
}

# Check if remote is configured
check_remote() {
    local remote=$1
    local rclone_cmd=$(get_rclone_cmd)
    
    if ! $rclone_cmd listremotes 2>/dev/null | grep -q "^${remote}:$"; then
        return 1
    fi
    return 0
}

# =============================================================================
# Sync Functions
# =============================================================================

sync_to_onedrive() {
    log_info "Syncing to OneDrive..."
    
    local rclone_cmd=$(get_rclone_cmd)
    local dry_run_flag=""
    local bwlimit=""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run_flag="--dry-run"
    fi
    
    if [[ "$BANDWIDTH_LIMIT_ONEDRIVE" != "0" ]]; then
        bwlimit="--bwlimit $BANDWIDTH_LIMIT_ONEDRIVE"
    fi
    
    # Check if remote is configured
    if ! check_remote "$ONEDRIVE_REMOTE"; then
        log_warn "OneDrive remote not configured. Run: docker compose run --rm rclone config"
        return 1
    fi
    
    log_info "Source: $BACKUP_SOURCE"
    log_info "Destination: ${ONEDRIVE_REMOTE}:${ONEDRIVE_PATH}"
    
    # Use sync to mirror the backup repository
    # --fast-list: Use fewer API calls (good for large directories)
    # --transfers: Number of parallel transfers
    # --checkers: Number of parallel checkers
    local rclone_exit=0
    local source_path="$BACKUP_SOURCE"
    
    # When running via docker, the source is mounted at /backup
    if in_docker || [[ "$rclone_cmd" == *"docker"* ]]; then
        source_path="/backup"
    fi
    
    if in_docker; then
        rclone sync \
            "$source_path" \
            "${ONEDRIVE_REMOTE}:${ONEDRIVE_PATH}" \
            $dry_run_flag \
            $bwlimit \
            --transfers 4 \
            --checkers 8 \
            --fast-list \
            --progress \
            --stats 30s \
            --stats-one-line \
            -v || rclone_exit=$?
    else
        $rclone_cmd sync \
            "$source_path" \
            "${ONEDRIVE_REMOTE}:${ONEDRIVE_PATH}" \
            $dry_run_flag \
            $bwlimit \
            --transfers 4 \
            --checkers 8 \
            --fast-list \
            --progress \
            --stats 30s \
            --stats-one-line \
            -v || rclone_exit=$?
    fi
    
    if [ $rclone_exit -ne 0 ]; then
        log_error "OneDrive sync failed (exit code: $rclone_exit)"
        return $rclone_exit
    fi
    
    log_success "OneDrive sync completed"
}

sync_to_mainpc() {
    log_info "Syncing to Main PC via SFTP..."
    
    local rclone_cmd=$(get_rclone_cmd)
    local dry_run_flag=""
    local bwlimit=""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        dry_run_flag="--dry-run"
    fi
    
    if [[ "$BANDWIDTH_LIMIT_MAINPC" != "0" ]]; then
        bwlimit="--bwlimit $BANDWIDTH_LIMIT_MAINPC"
    fi
    
    # Check if remote is configured
    if ! check_remote "$MAINPC_REMOTE"; then
        log_warn "Main PC remote not configured. Run: docker compose run --rm rclone config"
        return 1
    fi
    
    log_info "Source: $BACKUP_SOURCE"
    log_info "Destination: ${MAINPC_REMOTE}:${MAINPC_PATH}"
    
    # Use sync to mirror the backup repository
    local rclone_exit=0
    local source_path="$BACKUP_SOURCE"
    
    # When running via docker, the source is mounted at /backup
    if in_docker || [[ "$rclone_cmd" == *"docker"* ]]; then
        source_path="/backup"
    fi
    
    if in_docker; then
        rclone sync \
            "$source_path" \
            "${MAINPC_REMOTE}:${MAINPC_PATH}" \
            $dry_run_flag \
            $bwlimit \
            --transfers 4 \
            --checkers 8 \
            --progress \
            --stats 30s \
            --stats-one-line \
            -v || rclone_exit=$?
    else
        $rclone_cmd sync \
            "$source_path" \
            "${MAINPC_REMOTE}:${MAINPC_PATH}" \
            $dry_run_flag \
            $bwlimit \
            --transfers 4 \
            --checkers 8 \
            --progress \
            --stats 30s \
            --stats-one-line \
            -v || rclone_exit=$?
    fi
    
    if [ $rclone_exit -ne 0 ]; then
        log_error "Main PC sync failed (exit code: $rclone_exit)"
        return $rclone_exit
    fi
    
    log_success "Main PC sync completed"
}

# =============================================================================
# Main Execution
# =============================================================================

show_usage() {
    echo "Usage: $0 [options] [target]"
    echo ""
    echo "Targets:"
    echo "  onedrive    Sync to OneDrive only"
    echo "  mainpc      Sync to main PC only"
    echo "  all         Sync to all remotes (default)"
    echo ""
    echo "Options:"
    echo "  --dry-run   Show what would be synced without making changes"
    echo "  --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Sync to all remotes"
    echo "  $0 onedrive           # Sync to OneDrive only"
    echo "  $0 --dry-run mainpc   # Dry run sync to main PC"
}

main() {
    echo "=============================================="
    echo "  Rclone Remote Sync"
    echo "  Started: $(date)"
    echo "=============================================="
    echo ""
    
    # Parse arguments
    DRY_RUN="false"
    TARGET="all"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN="true"
                log_info "DRY RUN MODE - No changes will be made"
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            onedrive|mainpc|all)
                TARGET="$1"
                shift
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Check source exists
    if [ ! -d "$BACKUP_SOURCE" ]; then
        log_error "Backup source not found: $BACKUP_SOURCE"
        log_info "Make sure you've run at least one restic backup first!"
        exit 1
    fi
    
    # Run syncs based on target
    local exit_code=0
    
    case $TARGET in
        onedrive)
            sync_to_onedrive || exit_code=$?
            ;;
        mainpc)
            sync_to_mainpc || exit_code=$?
            ;;
        all)
            # Sync to both, continue even if one fails
            sync_to_onedrive || { log_error "OneDrive sync failed"; exit_code=1; }
            sync_to_mainpc || { log_error "Main PC sync failed"; exit_code=1; }
            ;;
    esac
    
    echo ""
    echo "=============================================="
    if [ $exit_code -eq 0 ]; then
        echo "  Sync Completed Successfully: $(date)"
    else
        echo "  Sync Completed with Errors: $(date)"
    fi
    echo "=============================================="
    
    return $exit_code
}

main "$@"

