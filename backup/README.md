# Unraid Backup System

Automated backup using **Restic** (deduplicated encrypted backups) and **Rclone** (sync to OneDrive + Main PC). Scheduled runs happen inside the stack at 3 AM. **GoBackup** runs alongside as a complementary layer with Web UI and its own schedule.

## How the stack works / when services run

| Service | When it runs | What it does |
|--------|----------------|--------------|
| **backup-scheduler** | Always on (`up`). Every minute it checks the time; at **3:00 AM** it runs one full backup (restic → OneDrive sync → Main PC sync) and sends one Telegram report. | Long-lived loop: sleep 60s, at 03:00 run `scheduled-backup.sh`, then sleep again. |
| **gobackup** | Always on (`up`). Web UI on port **2703**; its own schedule (e.g. 4 AM) is in `gobackup/gobackup.yml`. | Runs in foreground (`gobackup run`); serves Web UI and runs scheduled models. |
| **restic** | Always on (`up`). No schedule; it just keeps the container alive. | Use **exec** for ad-hoc commands: `docker compose exec restic restic snapshots`, `restic check`, etc. |
| **rclone** | Always on (`up`). No schedule; container stays alive. | Use **exec** for ad-hoc sync/config: `docker compose exec rclone rclone lsd onedrive:`, etc. |
| **backup-runner** | Only when you use the `backup` profile: `docker compose --profile backup run --rm backup-runner`. | One-shot: runs `backup.sh` once (restic backup only), then container exits. |

So: **Start the stack with `docker compose up -d`**. That starts the scheduler (3 AM backups), gobackup (Web UI + 4 AM archive), and the restic/rclone containers (for exec). No need to “run” restic or rclone on a schedule—the scheduler does the real work.

## Features

- **Deduplicated backups** - Restic only stores changed data
- **Encrypted** - All backups encrypted with your password
- **Multi-destination** - Local, OneDrive, and network PC
- **Scheduled in Compose** - No Unraid User Scripts needed; `backup-scheduler` runs nightly at 3 AM
- **Wide-event Telegram** - One structured message per backup run with full context
- **GoBackup** - Web UI (port 2703), archive of configs/compose, optional Telegram notifications
- **Retention policy** - Restic keeps 7 daily, 4 weekly, 6 monthly

## Directory Structure

```
/mnt/user/documents/compose/backup/
├── compose.yml           # Docker services
├── Dockerfile             # backup-scheduler image (restic + rclone)
├── .env                   # Passwords and config
├── README.md
├── gobackup/
│   └── gobackup.yml       # GoBackup config (Web UI, archive model, schedule)
└── scripts/
    ├── backup.sh          # Restic directory backup
    ├── scheduled-backup.sh # Orchestrator for 3 AM run (no VM), wide-event Telegram
    ├── crontab            # 0 3 * * * for backup-scheduler
    ├── sync-remotes.sh    # Rclone sync to OneDrive / Main PC
    ├── vm-backup.sh       # VM backup with shutdown (run via User Scripts if needed)
    └── run-all-backups.sh # Full manual run (restic + VM + sync, multiple Telegram msgs)
```

## Services

| Service | Purpose |
|--------|---------|
| **backup-scheduler** | Long-running; runs `scheduled-backup.sh` at 3 AM (restic → OneDrive → Main PC). One Telegram message per run. |
| **gobackup** | Complementary backups + Web UI at `http://<server>:2703`. Schedule in `gobackup/gobackup.yml` (e.g. 4 AM). |
| **restic** | Ad-hoc restic commands (snapshots, check, restore). |
| **rclone** | Ad-hoc rclone commands (sync, config). |
| **backup-runner** | One-shot restic backup: `docker compose --profile backup run --rm backup-runner`. |

## What Gets Backed Up

### Scheduled backup (3 AM, no VM)
- Restic: `/mnt/user/appdata`, `/mnt/user/documents`, `/mnt/user/system`, `/mnt/user/trilium`
- Then rclone syncs the restic repo to OneDrive (and Main PC if `SYNC_MAINPC_SCHEDULED=true`)

### GoBackup (configurable in `gobackup/gobackup.yml`)
- Default model `unraid_configs`: archives `compose` + `system` to local storage (tgz), keep 14, run at 4 AM

### VM backup (optional)
- Use **User Scripts** to run `./scripts/run-all-backups.sh` (includes VM shutdown) or `./scripts/vm-backup.sh` alone.

## Required setup

1. **Rclone**: generate config (e.g. `docker compose run --rm rclone config`) and put `rclone.conf` in `config/`.
2. **.env**: set at least:
   - `RESTIC_PASSWORD`
   - `MAINPC_HOST`, `MAINPC_USER`, `MAINPC_PATH`, `ONEDRIVE_PATH`
   - `SYNC_MAINPC_SCHEDULED` (default `false`; set `true` to include Main PC sync in 3 AM run)
   - `TELEGRAM_ENABLED`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` (for wide-event report)
   - `GOBACKUP_WEB_PASSWORD` (for GoBackup Web UI; username: admin)

## Common commands

```bash
cd /mnt/user/documents/compose/backup

# Build backup-scheduler image (use legacy builder if compose build fails with buildx)
./build-scheduler.sh

# Start the stack (scheduler + gobackup + restic/rclone for ad-hoc use)
docker compose up -d

# Run scheduled backup once by hand (inside scheduler)
docker compose exec backup-scheduler /scripts/scheduled-backup.sh

# List restic snapshots (restic container is already running)
docker compose exec restic restic snapshots

# Check repository health
docker compose exec restic restic check

# Manual sync to Main PC (when PC is on; 3 AM run skips this unless SYNC_MAINPC_SCHEDULED=true)
docker compose exec backup-scheduler /scripts/sync-remotes.sh mainpc
# Or from rclone container: docker compose exec rclone /scripts/sync-remotes.sh mainpc

# One-shot full backup including VM (multiple Telegram messages)
./scripts/run-all-backups.sh

# GoBackup Web UI
# Open http://<unraid-ip>:2703 (admin / GOBACKUP_WEB_PASSWORD)
```

## Logs

- **Scheduled backup**: inside `backup-scheduler` at `/var/log/backup/` (volume `backup-logs`). To tail:  
  `docker compose exec backup-scheduler tail -f /var/log/backup/cron.log`
- **GoBackup**: check the Web UI or container logs.

## Restoring

### From local Restic repo

```bash
docker compose exec restic restic snapshots
# Restore (run a one-off container with a restore mount)
docker compose run --rm -v /mnt/user/restore:/restore restic restic restore <snapshot-id> --target /restore
```

### From OneDrive

```bash
docker compose exec rclone rclone sync onedrive:Backups/unraid /backup
docker compose exec restic restic snapshots
```

## Retention (Restic)

- 7 daily, 4 weekly, 6 monthly (prune runs after each backup).
