# Unraid Backup System

Automated backup solution using **Restic** (deduplicated local backups) and **Rclone** (cloud sync to OneDrive + local network PC).

## Features

- **Deduplicated backups** - Restic only stores changed data
- **Encrypted** - All backups are encrypted with your password
- **Multi-destination** - Local, OneDrive, and network PC
- **VM-aware** - Safely shuts down Windows VM before backup
- **Retention policy** - Automatically cleans old backups

## Quick Start

### 1. Set Your Restic Password

```bash
cd /mnt/user/documents/compose/backup
nano .env
```

Change `RESTIC_PASSWORD=CHANGE_ME_TO_A_STRONG_PASSWORD` to a strong password.

**IMPORTANT**: Save this password somewhere safe! You cannot recover backups without it.

### 2. Initialize the Restic Repository

```bash
cd /mnt/user/documents/compose/backup
docker compose run --rm restic init
```

### 3. Configure Rclone Remotes

#### OneDrive Setup:

```bash
docker compose run --rm rclone config
```

1. Select `n` for new remote
2. Name it `onedrive`
3. Select `Microsoft OneDrive`
4. Leave client_id and client_secret blank (press Enter)
5. Choose `1` for Microsoft Cloud Global
6. Select `n` for advanced config
7. Select `y` for auto config - this will open a browser for Microsoft login
8. Choose `1` for OneDrive Personal or `2` for Business
9. Confirm the drive
10. Select `y` to confirm, then `q` to quit

#### Main PC (SFTP) Setup:

First, on your main PC (10.0.0.146):

```bash
# Install SSH server (if not installed)
sudo apt install openssh-server

# Create backup directory
mkdir -p ~/backups/unraid
```

Then configure rclone:

```bash
docker compose run --rm rclone config
```

1. Select `n` for new remote
2. Name it `mainpc`
3. Select `SFTP`
4. Enter host: `10.0.0.146`
5. Enter your username
6. Enter port: `22`
7. Choose password or key authentication
8. Complete the setup

### 4. Test the Backup

```bash
# Test regular backup (dry-run)
docker compose run --rm backup-runner /scripts/backup.sh --dry-run

# Run actual backup
docker compose run --rm backup-runner
```

### 5. Set Up Scheduled Backups

#### Option A: Unraid User Scripts (Recommended)

1. Go to Unraid Web UI → Settings → User Scripts
2. Click "Add New Script"
3. Name it: `Daily Backup`
4. Click the script name, then "Edit Script"
5. Paste:
   ```bash
   #!/bin/bash
   /mnt/user/documents/compose/backup/scripts/run-all-backups.sh
   ```
6. Set schedule: Custom → `0 3 * * *` (3:00 AM daily)

#### Option B: Crontab

```bash
crontab -e
# Add this line:
0 3 * * * /mnt/user/documents/compose/backup/scripts/run-all-backups.sh
```

## Directory Structure

```
/mnt/user/documents/compose/backup/
├── compose.yml           # Docker services
├── .env                   # Passwords and config
├── rclone.conf            # Rclone remote configs
├── crontab                # Schedule reference
├── README.md              # This file
└── scripts/
    ├── backup.sh          # Regular directory backup
    ├── vm-backup.sh       # VM backup with shutdown
    ├── sync-remotes.sh    # Rclone sync operations
    └── run-all-backups.sh # Master orchestrator

/mnt/user/backups/
├── restic/                # Restic repository (encrypted)
└── logs/                  # Backup logs
```

## What Gets Backed Up

### Regular Backup (Daily)
- `/mnt/user/appdata` - Docker container data
- `/mnt/user/documents` - Documents
- `/mnt/user/domains` - VM configs (excluding disk images)
- `/mnt/user/downloads` - Downloads
- `/mnt/user/syncthing` - Syncthing data
- `/mnt/user/system` - System configs
- `/mnt/user/trilium` - Trilium notes

### VM Backup (Daily, with shutdown)
- `/mnt/user/domains/Windows 10 Enterprise IoT LTSC_v2/vdisk1.img`

### Excluded (large media)
- `/mnt/user/media`
- `/mnt/user/music`
- `/mnt/user/isos`
- `/mnt/user/podcasts`

## Common Commands

```bash
cd /mnt/user/documents/compose/backup

# Run full backup manually
./scripts/run-all-backups.sh

# Run backup without VM shutdown
./scripts/run-all-backups.sh --no-vm

# Run backup without remote sync
./scripts/run-all-backups.sh --no-sync

# List all snapshots
docker compose run --rm restic snapshots

# Check repository health
docker compose run --rm restic check

# Show repository stats
docker compose run --rm restic stats

# Restore a file
docker compose run --rm restic restore latest --target /restore --include "/data/documents/important.txt"

# Test rclone connection
docker compose run --rm rclone lsd onedrive:
docker compose run --rm rclone lsd mainpc:
```

## Restoring Backups

### Restore from Local Restic Repository

```bash
# List available snapshots
docker compose run --rm restic snapshots

# Restore specific snapshot to /mnt/user/restore
docker compose run --rm -v /mnt/user/restore:/restore restic restore <snapshot-id> --target /restore

# Restore specific files
docker compose run --rm -v /mnt/user/restore:/restore restic restore latest --target /restore --include "/data/documents/"
```

### Restore from OneDrive

If your local backup is lost, you can restore from OneDrive:

```bash
# Sync back from OneDrive
docker compose run --rm rclone sync onedrive:Backups/unraid /backup

# Then restore from the synced repository
docker compose run --rm restic snapshots
```

## Retention Policy

Restic automatically keeps:
- **7 daily** snapshots
- **4 weekly** snapshots  
- **6 monthly** snapshots

Older snapshots are pruned automatically after each backup.

## Troubleshooting

### "Repository not found" error
Run `docker compose run --rm restic init` to initialize.

### OneDrive authentication expired
Run `docker compose run --rm rclone config reconnect onedrive:` to re-authenticate.

### VM doesn't shut down
Check the VM name matches exactly:
```bash
virsh list --all
```
Update `VM_NAME` in `.env` if needed.

### Backup is slow
- First backup is always slow (full backup)
- Subsequent backups only transfer changes
- Consider excluding more directories

### Check logs
```bash
cat /mnt/user/backups/logs/backup-*.log | tail -100
```

## Security Notes

1. **Protect your `.env` file** - It contains your encryption password
2. **Store password separately** - Keep a copy of RESTIC_PASSWORD in a safe place
3. **SSH keys recommended** - More secure than password for SFTP
4. **OneDrive encryption** - Restic encrypts before upload, so OneDrive can't read your data

