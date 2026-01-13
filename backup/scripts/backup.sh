#!/bin/sh
# =============================================================================
# Main Backup Script - Regular Directory Backup with Restic
# =============================================================================
# This script performs incremental backups of your data directories using restic.
# It excludes the Windows VM disk (handled separately by vm-backup.sh).
#
# Usage:
#   ./backup.sh              # Run backup
#   ./backup.sh --dry-run    # Show what would be backed up
#
# Run manually:
#   docker compose run --rm backup-runner
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if restic repository exists
check_repo() {
    log_info "Checking restic repository..."
    if ! restic snapshots > /dev/null 2>&1; then
        log_warn "Repository not initialized or inaccessible"
        log_info "Initializing repository..."
        restic init
        log_success "Repository initialized"
    else
        log_success "Repository is accessible"
    fi
}

# Perform backup
run_backup() {
    log_info "Starting backup of regular directories..."
    
    # Directories to backup (relative to /data mount point)
    # TESTING: Only appdata for now
    BACKUP_DIRS="/data/appdata"
    
    # Build exclude arguments
    EXCLUDE_ARGS=""
    # VM disk files
    EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude=*.img --exclude=*.qcow2 --exclude=*.vmdk --exclude=*.vdi"
    # Kasm Docker-in-Docker data
    EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude=kasm/data/docker --exclude=kasm/docker --exclude=kasm/containerd --exclude=kasm/data/containerd"
    # Common exclusions
    EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude=*.tmp --exclude=*.temp --exclude=*.log --exclude=.cache --exclude=__pycache__"
    EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude=node_modules --exclude=.git --exclude=Thumbs.db --exclude=.DS_Store --exclude=*.iso"
    
    # Check for dry-run flag
    DRY_RUN=""
    if [[ "$1" == "--dry-run" ]]; then
        DRY_RUN="--dry-run"
        log_info "DRY RUN MODE - No changes will be made"
    fi
    
    # Run the backup
    log_info "Backing up: $BACKUP_DIRS"
    
    restic backup \
        $DRY_RUN \
        $EXCLUDE_ARGS \
        --verbose \
        --tag "regular" \
        --tag "automated" \
        $BACKUP_DIRS
    
    log_success "Backup completed successfully"
}

# Clean up old snapshots (retention policy)
run_forget() {
    log_info "Applying retention policy..."
    
    restic forget \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 6 \
        --prune \
        --verbose
    
    log_success "Retention policy applied"
}

# Check repository integrity
run_check() {
    log_info "Checking repository integrity..."
    
    restic check
    
    log_success "Repository integrity verified"
}

# Show backup statistics
show_stats() {
    log_info "Backup Statistics:"
    echo ""
    restic stats
    echo ""
    log_info "Recent Snapshots:"
    restic snapshots --last 5
}

# Main execution
main() {
    echo "=============================================="
    echo "  Restic Backup - Regular Directories"
    echo "  Started: $(date)"
    echo "=============================================="
    echo ""
    
    check_repo
    run_backup "$1"
    
    # Only run forget and check if not dry-run
    if [[ "$1" != "--dry-run" ]]; then
        run_forget
        # Run check occasionally (every Sunday)
        if [[ $(date +%u) -eq 7 ]]; then
            run_check
        fi
    fi
    
    show_stats
    
    echo ""
    echo "=============================================="
    echo "  Backup Completed: $(date)"
    echo "=============================================="
}

main "$@"