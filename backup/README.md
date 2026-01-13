# Unraid Backup System

Automated backup solution using **Restic** (deduplicated local backups) and **Rclone** (cloud sync to OneDrive + local network PC).

## Features

- **Deduplicated backups** - Restic only stores changed data
- **Encrypted** - All backups are encrypted with your password
- **Multi-destination** - Local, OneDrive, and network PC
- **VM-aware** - Safely shuts down Windows VM before backup
- **Retention policy** - Automatically cleans old backups

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
- `/mnt/user/system` - System configs
- `/mnt/user/trilium` - Trilium notes

### VM Backup (Daily, with shutdown)
- `/mnt/user/domains/Windows 10 Enterprise IoT LTSC_v2/vdisk1.img`

### Excluded (large media)
- `/mnt/user/media`
- `/mnt/user/music`
- `/mnt/user/isos`
- `/mnt/user/podcasts`
- `/mnt/user/downloads`


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


### Check logs
```bash
cat /mnt/user/backups/logs/backup-*.log | tail -100
```
