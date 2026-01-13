#!/bin/bash
# =============================================================================
# VM Backup Script - Windows VM Disk Backup with VM Shutdown
# =============================================================================
# This script safely backs up the Windows VM disk by:
# 1. Shutting down the VM gracefully
# 2. Waiting for VM to fully stop
# 3. Running restic backup on the disk image
# 4. Starting the VM again
#
# IMPORTANT: This script must be run on the Unraid HOST, not in a container!
#
# Usage:
#   ./vm-backup.sh                    # Full backup with shutdown/restart
#   ./vm-backup.sh --skip-shutdown    # Backup without VM management (risky!)
#
# Requirements:
#   - virsh command available (Unraid has this)
#   - restic installed on host or use Docker
#   - RESTIC_PASSWORD environment variable set
# =============================================================================

set -e

# =============================================================================
# CONFIGURATION - Edit these values or set via environment
# =============================================================================
VM_NAME="${VM_NAME:-Windows 10 Enterprise IoT LTSC_v2}"
VM_DISK="/mnt/user/domains/Windows 10 Enterprise IoT LTSC_v2/vdisk1.img"
RESTIC_REPO="${RESTIC_REPO:-/mnt/user/backups/restic}"
SHUTDOWN_TIMEOUT=300  # 5 minutes to wait for graceful shutdown
STARTUP_WAIT=60       # Wait 60 seconds after starting VM

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
# VM Management Functions
# =============================================================================

# Check if VM is running
is_vm_running() {
    virsh list --name | grep -q "^${VM_NAME}$"
}

# Get VM state
get_vm_state() {
    virsh domstate "$VM_NAME" 2>/dev/null || echo "unknown"
}

# Gracefully shutdown VM
shutdown_vm() {
    log_info "Initiating graceful shutdown of VM: $VM_NAME"
    
    if ! is_vm_running; then
        log_info "VM is not running, skipping shutdown"
        return 0
    fi
    
    # Send ACPI shutdown signal (graceful)
    virsh shutdown "$VM_NAME"
    
    log_info "Waiting for VM to shut down (timeout: ${SHUTDOWN_TIMEOUT}s)..."
    
    local waited=0
    while is_vm_running && [ $waited -lt $SHUTDOWN_TIMEOUT ]; do
        sleep 5
        waited=$((waited + 5))
        echo -n "."
    done
    echo ""
    
    if is_vm_running; then
        log_warn "VM did not shut down gracefully, forcing power off..."
        virsh destroy "$VM_NAME"
        sleep 5
    fi
    
    log_success "VM is now stopped"
}

# Start VM
start_vm() {
    log_info "Starting VM: $VM_NAME"
    
    if is_vm_running; then
        log_info "VM is already running"
        return 0
    fi
    
    virsh start "$VM_NAME"
    
    log_info "Waiting ${STARTUP_WAIT}s for VM to initialize..."
    sleep $STARTUP_WAIT
    
    if is_vm_running; then
        log_success "VM started successfully"
    else
        log_error "VM failed to start!"
        return 1
    fi
}

# =============================================================================
# Backup Functions
# =============================================================================

# Check if restic is available
check_restic() {
    if command -v restic &> /dev/null; then
        return 0
    fi
    
    # Try Docker
    if command -v docker &> /dev/null; then
        log_info "Using restic via Docker"
        RESTIC_CMD="docker run --rm -v ${RESTIC_REPO}:/repo -v /mnt/user/domains:/data -e RESTIC_REPOSITORY=/repo -e RESTIC_PASSWORD restic/restic"
        return 0
    fi
    
    log_error "restic not found! Install restic or Docker"
    return 1
}

# Backup VM disk
backup_vm_disk() {
    log_info "Starting backup of VM disk: $VM_DISK"
    
    if [ ! -f "$VM_DISK" ]; then
        log_error "VM disk not found: $VM_DISK"
        return 1
    fi
    
    local disk_size=$(du -h "$VM_DISK" | cut -f1)
    log_info "Disk size: $disk_size"
    
    # Export for restic
    export RESTIC_REPOSITORY="$RESTIC_REPO"
    
    # Run restic backup
    if [ -n "$RESTIC_CMD" ]; then
        # Docker mode
        $RESTIC_CMD backup \
            --verbose \
            --tag "vm" \
            --tag "windows" \
            --tag "automated" \
            "/data/Windows 10 Enterprise IoT LTSC_v2/vdisk1.img"
    else
        # Native mode
        restic backup \
            --verbose \
            --tag "vm" \
            --tag "windows" \
            --tag "automated" \
            "$VM_DISK"
    fi
    
    log_success "VM disk backup completed"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo "=============================================="
    echo "  Windows VM Backup Script"
    echo "  Started: $(date)"
    echo "=============================================="
    echo ""
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    
    if ! command -v virsh &> /dev/null; then
        log_error "virsh command not found! This script must run on Unraid host."
        exit 1
    fi
    
    check_restic
    
    # Check VM exists
    if ! virsh dominfo "$VM_NAME" &> /dev/null; then
        log_error "VM not found: $VM_NAME"
        log_info "Available VMs:"
        virsh list --all
        exit 1
    fi
    
    # Track if VM was running (to restore state later)
    VM_WAS_RUNNING=false
    if is_vm_running; then
        VM_WAS_RUNNING=true
    fi
    
    log_info "VM '$VM_NAME' state: $(get_vm_state)"
    
    # Handle skip-shutdown flag
    if [[ "$1" == "--skip-shutdown" ]]; then
        log_warn "Skipping VM shutdown - backup may be inconsistent!"
        backup_vm_disk
    else
        # Normal flow: shutdown -> backup -> start
        if [ "$VM_WAS_RUNNING" = true ]; then
            shutdown_vm
        fi
        
        backup_vm_disk
        
        # Only restart if it was running before
        if [ "$VM_WAS_RUNNING" = true ]; then
            start_vm
        else
            log_info "VM was not running before backup, leaving it stopped"
        fi
    fi
    
    echo ""
    echo "=============================================="
    echo "  VM Backup Completed: $(date)"
    echo "=============================================="
}

# Trap to ensure VM is restarted even if script fails
cleanup() {
    if [ "$VM_WAS_RUNNING" = true ] && ! is_vm_running; then
        log_warn "Script interrupted, attempting to restart VM..."
        start_vm || log_error "Failed to restart VM!"
    fi
}

trap cleanup EXIT

main "$@"

