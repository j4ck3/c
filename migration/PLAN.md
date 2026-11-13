# tower: Unraid 7.0 → Proxmox VE 9 migration plan

Status: draft, written 2026-10-29 from a live audit of tower. Nothing has been
executed except a read-only dry run of `00-export.sh` (output in
`/mnt/cache/migration/dryrun`, 3.7 GB, 0 failures).

Run the migration from a laptop with a monitor and keyboard on tower. The
DeepSeek Harness, NetBird and Pi-hole all run on tower and go down with it.

## Decisions this plan rests on

| Decision | Choice | Why |
|---|---|---|
| Target | Proxmox VE 9.x on Debian 13 Trixie | User choice. |
| Install disk | Repartition the existing Samsung 980 PRO 2 TB (`nvme0n1`) | User choice; it is the only disk. |
| Off-box copy | OneDrive restic repo only | No 1.3 TB staging disk available. |
| How data survives | Shrink the btrfs partition in place and install PVE into the freed tail of the disk | Media, downloads, VM disks and `docker.img` (~760 GB) are not in restic. OneDrive measured ~5 MB/s up and ~17 MB/s down, so restoring even the restic part takes hours. |
| Where Docker runs | On the PVE host, with the existing `docker.img` loop-mounted at `/var/lib/docker` exactly as Unraid does | Zero-copy. Every image, container, volume, macvlan IP and `/dev/dri` mapping comes back unchanged. Proxmox does not support Docker on the host; section 11 covers moving it into a VM later. |

If any decision changes, phases 2–5 change with it.

## 1. Current state (measured 2026-10-29)

### Hardware

- i7-12700 (20 threads: 0–15 P-core threads, 16–19 E-cores), 62 GiB RAM.
- iGPU AlderLake-S GT1 `8086:4680`, used by Plex through `/dev/dri`.
- GTX 1060 6 GB `10de:1c03` + HDMI audio `10de:10f1` at `01:00.x`, IOMMU group 11, bound to vfio.
- 4× Renesas uPD720202 USB 3 controllers `1912:0015` at `05:00.0`–`08:00.0`, one IOMMU group each, bound to vfio.
- RTL8125 2.5 GbE (`r8169`), MAC `a8:a1:59:ac:9b:f9`. Predictable name on Debian: `enp9s0`.
- Boot: 32 GB Philips USB stick (Unraid flash). No array, no ZFS.
- `nvme0n1`: DOS label, one partition `nvme0n1p1` (start sector 2048) = btrfs UUID `54e146b8-aa5b-4cac-b225-470ae17d33e1`, 1.82 TiB, 1.17 TiB used, 659 GiB free. SMART PASSED, 26 % wear, 0 media errors, btrfs device stats all zero, last scrub clean.

### Data on `/mnt/cache` (Unraid's `/mnt/user/*` is the same tree)

| Path | Size | In restic? |
|---|---|---|
| `media/` (Movies 279G, TV 37G, Youtube 58G) | 372 G | no |
| `system/docker/docker.img` | 200 G sparse, ~109 G used | no (`*.img` excluded) |
| `backups/restic` (local restic repo) | 154 G | is the backup |
| `documents/` | 114 G | yes |
| `appdata/` | 44 G | yes |
| `domains/` (VM disks) | 119 G | no (`*.img` excluded) |
| `downloads/` | 30 G | no |
| `system/libvirt/libvirt.img` | 1 G | no |
| `podcasts/` | 10 G | no |
| `trilium/` | 0.1 G | yes |

OneDrive (`onedrive:Backups/unraid`) holds a synced copy of the restic repo:
154 GiB, 16 snapshots, newest `6741ea21` from 2026-10-29 03:00 with 144.6 GiB
of source data.

### Workloads

- 76 containers. About 65 come from compose projects under `/mnt/user/documents/compose` (git `git@github.com:j4ck3/c.git`) or `/mnt/user/documents/work/*`.
- Not IaC: UptimeKuma, flaresolverr, fivefilters, lidarr, prowlarr, nicotine (Unraid dockerMan); `3dcommerce-app` and `3dcommerce_postgres` (`docker run`); `buildx_buildkit_builder0`.
- 7 libvirt VMs, all q35 + OVMF, virtio-net on `br0`:

| VM | Disk | Autostart | Passthrough | Other | LAN IP |
|---|---|---|---|---|---|
| Home Assistant | qcow2, 32 G, virtio | yes | USB `10c4:ea60` (radio stick) | MAC `ac:87:a3:d2:12:94`, 2 vCPU, 4 GiB, VARS 64 KiB | 10.0.0.23 |
| CachyOS (htpc) | raw, 100 G, virtio | yes | GPU `01:00.0/.1`, USB ctrl `06:00.0`, `07:00.0` | MAC `52:54:00:f1:fa:d7`, 12 vCPU pinned to host 8–19, 6 GiB locked, Limine, VARS 128 KiB | 10.0.0.164 |
| Windows 11 IoT LTSC | raw, 64 G, **SATA** | no | GPU + all 4 USB ctrls | MAC `52:54:00:d1:e5:2e`, 16 GiB, swtpm TPM 2.0, VARS 528 KiB | – |
| Arch endeavourOS, Mint, NixOS | raw, 15–20 G | no | none | | – |
| Arch | no disk file (empty dir) | no | none | | – |

CachyOS and Windows share the GPU and `06:00.0`/`07:00.0`, so only one of them can run at a time.

### Host config that lives only on the flash drive

- `/boot/config/go` runs:
  - `term-unknown-fallback.sh`
  - `start-deepseek-stack.sh`: waits for Docker and for NetBird IP `100.113.194.104` on `wt0`, then starts `tower-ssh-proxy`, `deepseek-harness`, `dockhand-netbird-proxy`.
  - `pihole-host-access.sh`: macvlan shim `shim-pihole` 10.0.0.251 on `br0`, host route to Pi-hole 10.0.0.53.
  - `install-docker-buildx.sh`
- `vfio-pci.cfg` binds the GPU and the 4 Renesas controllers.
- `docker.cfg`: `DOCKER_OPTS="-H unix:///var/run/docker.sock -H tcp://0.0.0.0:2375"`. This is an unauthenticated root API on every interface. Log rotation 50 MB × 1.
- User Scripts: `otp_cleanup` daily at 10:00, `delete_dangling_images` Sundays at 04:00.
- SMB shares: appdata, backups, documents, domains, downloads, media, music, podcasts, trilium. User `jacob` (uid 1000). `backups` and `documents` are public.
- `/root/.ssh` (persisted from `/boot/config/ssh/root`): `id_ed25519`, `github_privatekey`, `codeberg_privatekey`, `authorized_keys`, `config`. SSH host keys in `/boot/config/ssh/`.
- Users: `nobody` = 99:100, `jacob` = 1000:100. Most appdata is owned by 99:100.

## 2. Target design

```
nvme0n1 (DOS label converted to GPT in place, no data moved)
├─ p1  start 2048, shrunk to 1736 GiB   btrfs data, UUID 54e146b8-…, contents untouched
├─ p2  1 GiB                             ESP (vfat)
└─ p3  ~126 GiB                          Debian 13 + PVE root (ext4)
```

The data partition keeps its start sector, so its contents never move. ESP and
root go into the tail of the disk that the shrink frees. UEFI and Linux do not
care about partition order. `sgdisk -g` converts MBR to GPT without moving
partitions: the primary GPT fits in sectors 1–33 before sector 2048, and the
backup GPT fits in the last 33 sectors, which the shrink frees.

On the running system:

- `/mnt/cache` = btrfs p1. `/mnt/user` is a symlink to `/mnt/cache`, so every compose path still works.
- `/var/lib/docker` = loop mount of `/mnt/cache/system/docker/docker.img` (btrfs storage driver), same as on Unraid.
- Bridge `vmbr0` on `enp9s0`, static 10.0.0.24/24, gateway 10.0.0.1. PVE needs a fixed address in `/etc/hosts`, so no DHCP on the host.
- macvlan `br0_docker` recreated with parent `vmbr0`, keeping the static container IPs .25 traefik, .26 t3code, .27 deepseek-harness, .53 pihole.
- VMs imported into PVE `dir` storage on `/mnt/cache/domains`. EFI vars and (best effort) TPM state are imported from the Unraid files.
- Host config is kept as files in `migration/host/` in this repo and applied by a script, replacing `/boot/config`.

## 3. Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| Shrink or repartition goes wrong | Everything not in restic is lost: media, downloads, VM disks, docker.img | Phase 0 shrinks what is at risk (convert volumes to binds, copy what cannot be re-downloaded). Phase 2 has explicit stop conditions. restic on OneDrive covers appdata, documents, system, trilium. |
| Power loss during `btrfs resize` | Filesystem damage | Check that the UPS works, or accept the risk. The resize is quick once the tail of the device is empty. |
| PVE ISO installer wipes the disk | Total loss | Do not use the PVE ISO. It only installs to whole disks. Install Debian 13 by hand into p2/p3, then add the PVE packages. |
| Docker on the PVE host cuts VM networking | VMs lose LAN | `"ip-forward-no-drop": true` in `daemon.json` stops Docker setting FORWARD to DROP ([Docker docs](https://docs.docker.com/engine/network/packet-filtering-firewalls/)). Leave the PVE firewall off until verified. |
| Docker 29 requires client API ≥ 1.44 | traefik v2.11 (API 1.24) loses every route | `DOCKER_MIN_API_VERSION=1.24` in a systemd drop-in ([traefik#12253](https://github.com/traefik/traefik/issues/12253)). Remove it after upgrading traefik to v3.6+. |
| Docker 29 defaults new installs to the containerd image store | Existing btrfs-driver images in docker.img are not seen | `"features": {"containerd-snapshotter": false}` ([Docker docs](https://docs.docker.com/engine/storage/containerd/)) plus explicit `"storage-driver": "btrfs"`. |
| Docker 29 opens state written by Unraid's Docker 27.0.3 | Containers fail to start | The on-disk format is forward compatible. Fallback: `docker compose up -d --force-recreate` per project, volumes come from docker.img or the Phase 1 tars. |
| Win11 TPM state not importable | BitLocker recovery prompt, Hello PIN reset | Get the BitLocker recovery key from the Microsoft account first. |
| CachyOS boot entry lost | VM drops to the UEFI shell | Import the 2m-class VARS file. Fallback: OVMF Boot Manager → Boot From File → `\EFI\limine\limine_x64.efi`. |
| NetBird mesh lost | Remote access and `*.netbird.hjacke.com` down | `netbird_data` and `netbird_client_data` travel inside docker.img. Phase 1 also writes tar copies. |

## 4. Phase 0: prepare (days before, system stays up)

Every step here is safe on the running Unraid box.

1. **Git.** Commit and push everything. Current state from the dry run's `git-report.txt`:
   - `compose`: 401 dirty paths, 2 unpushed commits, and origin is ahead (`f3c76f4..7af4b7a`). Pull with rebase, then push.
     - Untrack `filebrowser/data/` (database plus 265 cache files) and add it to `.gitignore`.
     - Commit the untracked stacks worth keeping: `firefly/` compose only, `roundcube/`, `browser-agent/`, `3dcommerce-worker/`, `deepseek-harness/patches/*`, `migration/`.
     - Add `firefly/.api_token`, `firefly/.db.env` and `firefly/.importer.env` to `.gitignore`.
   - `work/3dcommerce`: 6 unpushed commits, 3 dirty files. `work/projectx`: 26 dirty. `work/mammas-hemsida`: 70 dirty.
   - No git at all: `work/3dcommerce-umami`, `work/bolaget`, `work/dev`, `work/dsh-mobile-composer`, `work/muddra assets`, `projects/custom keyboard`, `projects/pixelbot`. They are in restic through `documents`. Decide whether any need a repo.
2. **Write compose for the non-IaC containers.** Done 2026-11-05:
   `uptime-kuma/`, `flaresolverr/`, `fivefilters/`, `3dcommerce/`, and `lidarr` +
   `prowlarr` added to `arrs/`. qBittorrent and nicotine now come from
   `gluetun-torrents/` (created, not started; they were stopped before too).
   The old containers are kept stopped as `*-unraid-old` / `*-old` until removed.
3. **Move named volumes with real data to bind mounts under `/mnt/user/appdata`.** This is not needed for the migration itself, because docker.img travels whole. It puts this data under restic and makes the later docker.img retirement trivial. Do it for: `projetx_app-convex-data` (2.5 G), `projetx_rustfs-data`, `projetx_vehicle-vision-model`, `3dcommerce_postgres_data`, `netbird_data`, `netbird_client_data`, `deepseek-harness_open_design_data`, `netbird_dockhand_caddy_data`, `trilium_trilium-ts-state`, and `erpnext_*` if ERPNext stays.
   For each volume:
   1. Stop the stack.
   2. `cp -a /var/lib/docker/volumes/<v>/_data/. /mnt/user/appdata/<stack>/<name>/`
   3. Edit the compose file to use the bind path.
   4. `up -d` and verify.
   5. Keep the old volume until after the migration.
4. **Write a recipe for `dockhand-caddy-cloudflare:local`.** Add `netbird/Dockerfile.caddy`:
   ```dockerfile
   FROM caddy:2-builder AS build
   RUN xcaddy build --with github.com/caddy-dns/cloudflare
   FROM caddy:2
   COPY --from=build /usr/bin/caddy /usr/bin/caddy
   ```
   Point the compose service at it with `build:`. The dry run already saved the current image with `docker save`.
5. **Home Assistant backup.** In HA, create a full backup and download it to the laptop.
6. **Remove dead weight.** This frees space for the shrink. Review each item before deleting.
   - Containers: `guacamole_compose`, `guacd_compose`, `postgres_guacamole_compose`, `nginx_guacamole_compose`, `hermes`, `zeroclaw`, `qBittorrent` (old, exited), `projetx-rustfs-init-1`, `projetx-rustfs-perms-1`, `projetx-dev-firewall-1`.
   - Images: `docker image prune -a` after the container cleanup (55.9 GB reclaimable). Also the `deepseek-harness:rollback-*` and `:before-*` tags, `openclaw:varlock` (5.5 G), `netbird-rollback/*` and `netbird-update-rollback/*`.
   - Volumes:
     - `nextcloud_aio_*`: decide first, it holds 946 M of Nextcloud data. A tar copy is already in `dryrun/`.
     - Remove without review: `gitlab-runner_*`, `runner-*`, `projectx_*` (stale duplicates of `projetx_*`), `z-ollama_ollama`, `tsd_proxy_tsdproxydata`, `buildx_buildkit_builder0_state` (4.5 G of build cache).
   - `docker builder prune -a` (1.3 G).
   - VMs: decide on Arch (no disk), Arch endeavourOS, Mint and NixOS. Each one dropped is one less import.
   - `appdata/`: `deepseek-upgrade-backups` (2.6 G), and dirs of stacks that no longer exist. Keep `Nginx-Proxy-Manager-Official`, because traefik mounts its `letsencrypt` folder.
7. **Store the secrets that cannot be recovered from the disk** in Bitwarden. Without the restic password the OneDrive copy is useless.
   - `RESTIC_PASSWORD` from `backup/.env`
   - OneDrive token in `backup/config/rclone.conf`
   - Cloudflare token in `traefik/.env.local`
   - NetBird setup key
   - Win11 BitLocker recovery key
8. **Test a restore from OneDrive:**
   ```bash
   docker exec backup-scheduler sh -c 'export RCLONE_CONFIG=/config/rclone.conf;
     restic -r rclone:onedrive:Backups/unraid restore latest --target /tmp/rtest --include /data/appdata/pihole'
   docker exec backup-scheduler ls -la /tmp/rtest/data/appdata/pihole    # files present = restore works
   docker exec backup-scheduler rm -rf /tmp/rtest
   ```
9. **Copy off-box what is not in restic and cannot be re-downloaded.**
   - Media can be re-fetched by the *arr stack, so decide per folder.
   - Copy `podcasts/` if it holds anything self-made.
   - Copy `media/Youtube` if those videos are gone upstream.
   - The main PC (10.0.0.146, rclone remote `mainpc:`) was offline during the audit.
10. **Install media.** Write SystemRescue to one USB stick and the Debian 13 netinst image to another. Keep the Unraid stick untouched; it is the rollback path.
11. **Router.**
    - Check the DHCP reservations for 10.0.0.23 (HA, MAC `ac:87:a3:d2:12:94`) and 10.0.0.164 (CachyOS, MAC `52:54:00:f1:fa:d7`).
    - On cutover day, set the router's DHCP DNS to 9.9.9.9 so the LAN keeps resolving while Pi-hole is down.

## 5. Phase 1: final backup and export (cutover day)

```bash
# 1. Final restic snapshot + OneDrive sync while everything still runs.
docker exec backup-scheduler /bin/bash /scripts/scheduled-backup.sh
docker exec restic restic check
docker exec backup-scheduler sh -c 'export RCLONE_CONFIG=/config/rclone.conf;
  restic -r rclone:onedrive:Backups/unraid snapshots --latest 1'

# 2. Record what is running. Containers stopped with `docker stop` stay stopped
#    after a daemon restart, so Phase 6 restarts exactly this list.
mkdir -p /mnt/cache/migration
docker ps --format '{{.Names}}' | sort > /mnt/cache/migration/running-before.txt
virsh list --name > /mnt/cache/migration/vms-running-before.txt

# 3. Stop VMs, then containers (consistent databases for the volume tars).
virsh shutdown "Home Assistant"; virsh shutdown CachyOS
virsh list --all          # repeat until both are 'shut off'
docker stop $(docker ps -q)

# 4. Export. Writes /mnt/cache/migration/<timestamp>/ on the partition that is kept.
bash /mnt/user/documents/compose/migration/00-export.sh
```

Copy the export off-box as well. It holds `/boot/config`, libvirt XML, NVRAM,
TPM state, volume tars and the three images without a recipe:

```bash
docker run --rm -v /mnt/cache/migration:/m:ro -v /mnt/user/documents/compose/backup/config:/config \
  rclone/rclone:latest --config /config/rclone.conf copy /m onedrive:Backups/tower-migration -P \
  --exclude 'dryrun/**'
```

Also copy `/mnt/cache/migration/<ts>/flash/` to the laptop (a few MB).

Last step on Unraid: Settings → Docker → Enable Docker: No, then Settings → VM
Manager → Enable VMs: No. This unmounts `docker.img` and `libvirt.img` cleanly.
Shut down.

## 6. Phase 2: repartition without moving the data

Boot [SystemRescue](https://www.system-rescue.org/) from a USB stick in **UEFI**
mode. It ships `btrfs-progs`, `gdisk` and `util-linux`; the Debian installer's
rescue shell does not have `btrfs` or `sgdisk`. Connect the monitor to the
motherboard output (iGPU).

```bash
DISK=/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_with_Heatsink_2TB_S6WRNS0W612088Z
lsblk -o NAME,SIZE,FSTYPE,UUID $DISK      # expect one partition, btrfs, UUID 54e146b8-…
sfdisk -d $DISK                           # expect: start=2048, size=3907027120, type=83
```

STOP if either check differs.

```bash
# 1. Shrink btrfs to 1730 GiB (used is ~1.17 TiB before Phase 0 cleanup).
mount /dev/nvme0n1p1 /mnt
btrfs balance start -dusage=50 /mnt        # compact half-empty chunks
btrfs filesystem resize 1730G /mnt
btrfs filesystem show --raw /mnt           # devid 1 size must be 1857573355520 (1730 GiB)
umount /mnt
```

STOP if the resize failed. Do not touch the partition table.

```bash
# 2. Shrink the partition to 1736 GiB, keeping start sector 2048.
#    1736 GiB = 3640655872 sectors; it ends at sector 3640657919.
echo ',3640655872' | sfdisk -N 1 $DISK      # empty start field = keep 2048
sfdisk -d $DISK                            # expect: start=2048, size=3640655872

# 3. MBR -> GPT in place, then grow btrfs to fill the partition exactly.
sgdisk -g $DISK
sgdisk -t 1:8300 -c 1:data $DISK
partprobe $DISK
mount /dev/nvme0n1p1 /mnt && btrfs filesystem resize max /mnt && umount /mnt

# 4. ESP and root in the freed tail (~127 GiB).
sgdisk -n 2:0:+1G -t 2:EF00 -c 2:ESP     $DISK
sgdisk -n 3:0:0   -t 3:8300 -c 3:pveroot $DISK
partprobe $DISK
mkfs.vfat -F32 -n ESP /dev/nvme0n1p2
mkfs.ext4 -L pveroot /dev/nvme0n1p3

# 5. Verify the data before installing anything.
mount -o ro /dev/nvme0n1p1 /mnt
ls /mnt                                  # appdata backups documents domains ... system
btrfs scrub start -B -r /mnt             # must report no errors
umount /mnt
```

## 7. Phase 3: install Debian 13 and Proxmox VE

Debian installer, **manual partitioning**:

- `nvme0n1p3`: use as ext4, mount point `/`, format.
- `nvme0n1p2`: use as EFI System Partition.
- `nvme0n1p1`: **do not use.** Leave it untouched.

Software selection: only "SSH server" and "standard system utilities". Hostname
`tower`. Static IP 10.0.0.24/24, gateway 10.0.0.1, DNS 9.9.9.9 (Pi-hole is down).

Then follow [Install Proxmox VE on Debian 13 Trixie](https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie):

```bash
# /etc/hosts must map tower to 10.0.0.24, not 127.0.1.1
cat > /etc/apt/sources.list.d/pve-install-repo.sources <<'EOF'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
wget https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
  -O /usr/share/keyrings/proxmox-archive-keyring.gpg
sha256sum /usr/share/keyrings/proxmox-archive-keyring.gpg
# expect 136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45
apt update && apt full-upgrade -y
apt install -y proxmox-default-kernel && reboot
apt install -y proxmox-ve postfix open-iscsi chrony
apt remove -y linux-image-amd64 'linux-image-6.12*' os-prober && update-grub
```

Remove `os-prober`. It would otherwise scan the VM disks and add GRUB entries for them.

`/etc/network/interfaces`:

```
auto lo
iface lo inet loopback

iface enp9s0 inet manual

auto vmbr0
iface vmbr0 inet static
    address 10.0.0.24/24
    gateway 10.0.0.1
    bridge-ports enp9s0
    bridge-stp off
    bridge-fd 0
    hwaddress a8:a1:59:ac:9b:f9
```

`ifreload -a`, then open `https://10.0.0.24:8006`.

## 8. Phase 4: host config

Save every file below in `migration/host/` and apply it with a script. This is
the IaC replacement for `/boot/config`.

### Data partition and Unraid-compatible paths

```bash
cat >> /etc/fstab <<'EOF'
UUID=54e146b8-aa5b-4cac-b225-470ae17d33e1  /mnt/cache       btrfs  noatime,ssd,discard=async,space_cache=v2  0 0
/mnt/cache/system/docker/docker.img         /var/lib/docker  btrfs  loop,noatime,x-systemd.requires-mounts-for=/mnt/cache  0 0
EOF
mkdir -p /mnt/cache /var/lib/docker
systemctl daemon-reload && mount -a
ln -s /mnt/cache /mnt/user
ls /var/lib/docker            # expect btrfs containers image network volumes ...
```

### Users matching existing file ownership

Debian's `users` group is already gid 100. Debian's `nobody` is 65534, so uid 99 is free.

```bash
useradd -u 99   -g 100 -M -s /usr/sbin/nologin -d /nonexistent unraidnobody
useradd -u 1000 -g 100 -m -s /bin/bash jacob
```

### VFIO and IOMMU

`/etc/default/grub`: `GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"`, then `update-grub`.

```
# /etc/modprobe.d/vfio.conf
options vfio-pci ids=10de:1c03,10de:10f1,1912:0015
softdep nouveau pre: vfio-pci
softdep snd_hda_intel pre: vfio-pci
softdep xhci_pci pre: vfio-pci
```

```
# /etc/modules-load.d/vfio.conf
vfio
vfio_iommu_type1
vfio_pci
```

`update-initramfs -u -k all && reboot`. After that, `lspci -nnk -s 01:00` and
`lspci -nnk -s 05:00` must show `Kernel driver in use: vfio-pci`. The Intel
XHCI controller stays with the host, along with the keyboard and the HA radio stick.

### Docker CE

Install from [Docker's Debian repository](https://docs.docker.com/engine/install/debian/)
(`docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`,
`docker-compose-plugin`). Before the first start of the daemon:

```json
// /etc/docker/daemon.json
{
  "storage-driver": "btrfs",
  "features": { "containerd-snapshotter": false },
  "ip-forward-no-drop": true,
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "1" }
}
```

```ini
# /etc/systemd/system/docker.service.d/override.conf
[Unit]
RequiresMountsFor=/var/lib/docker /mnt/cache
[Service]
Environment=DOCKER_MIN_API_VERSION=1.24
```

There is no `tcp://0.0.0.0:2375` listener. Dockhand uses the socket it already
mounts; reach other hosts through SSH contexts or a socket proxy on NetBird.

```bash
systemctl daemon-reload && systemctl enable --now docker
docker info --format '{{.Driver}} {{.DockerRootDir}}'   # expect: btrfs /var/lib/docker
docker ps -a | wc -l                                    # expect ~74
```

### Recreate the macvlan network on the new bridge

The copied network `br0_docker` still has parent `br0`, which no longer exists.

```bash
for c in $(docker network inspect br0_docker -f '{{range .Containers}}{{.Name}} {{end}}'); do
  docker network disconnect -f br0_docker "$c"; done
docker network rm br0_docker
docker network create -d macvlan --subnet 10.0.0.0/24 --gateway 10.0.0.1 \
  -o parent=vmbr0 br0_docker
```

Save these commands, and the creation of `npm_services` (172.25.0.0/16) and
`searxng_gluetun_net` (192.168.144.0/20), as `compose/networks/bootstrap.sh` so
that they become IaC. The containers on `br0_docker` (pihole, traefik,
deepseek-harness, t3code) are recreated with `docker compose up -d
--force-recreate` in Phase 6.

### Replacements for `/boot/config/go`

Turn each script into a systemd unit in `migration/host/systemd/`:

- `pihole-host-access.service`: oneshot, `After=network-online.target docker.service`. Same script with `PARENT=vmbr0`.
- `deepseek-boot.service`: oneshot, `After=docker.service`. Runs `start-deepseek-stack.sh` unchanged.
- `term-unknown-fallback.sh`: copy it to `/etc/profile.d/` once.
- `install-docker-buildx.sh`: drop it. Docker CE ships a current buildx.

`/etc/cron.d/tower`:

```
0 10 * * *  root  /mnt/cache/appdata/otp-cleanup/run.sh >> /mnt/cache/appdata/otp-cleanup/logs/otp-cleanup.log 2>&1
0 4  * * 0  root  docker image prune -f
```

### SSH and Samba

- Restore `/root/.ssh` from `migration/<ts>/flash/config/ssh/root/`. Copy `flash/config/ssh/ssh_host_*` into `/etc/ssh/` and restart sshd. Clients and `tower-ssh-proxy` then see the same host key.
- `apt install samba`. Define the 9 shares in `/etc/samba/smb.conf` with `path = /mnt/cache/<share>`, `valid users = jacob`, `force user = unraidnobody`, `force group = users`. That keeps new files at 99:100. Run `smbpasswd -a jacob`.

## 9. Phase 5: import the VMs

```bash
pvesm add dir domains --path /mnt/cache/domains --content images,iso --is_mountpoint /mnt/cache
E=/mnt/cache/migration/<ts>      # the Phase 1 export
```

Import copies each disk into `/mnt/cache/domains/images/<vmid>/` ([qm docs](https://pve.proxmox.com/pve-docs/qm.1.html), `import-from`).
Free space is ample once the Phase 0 cleanup is done. Delete each old `vdisk1.img` after its VM boots.

EFI variable stores must match the firmware size class:

| VM | VARS size | PVE setting |
|---|---|---|
| Home Assistant | 64 KiB (old OVMF) | fresh efidisk; HA OS boots from its fallback `\EFI\BOOT\BOOTX64.EFI` |
| CachyOS | 128 KiB | `efitype=2m`, import |
| Windows 11 | 528 KiB | `efitype=4m`, import |

```bash
# Home Assistant: VMID 100. Same MAC, so DHCP hands out 10.0.0.23 again.
qm create 100 --name home-assistant --machine q35 --bios ovmf --ostype l26 \
  --cpu host --cores 2 --memory 4096 --scsihw virtio-scsi-single \
  --net0 virtio=AC:87:A3:D2:12:94,bridge=vmbr0 --onboot 1 --startup order=1 --agent 1
qm set 100 --efidisk0 domains:1,efitype=4m,pre-enrolled-keys=0
qm set 100 --virtio0 "domains:0,import-from=/mnt/cache/domains/Home Assistant/vdisk1.img,format=qcow2"
qm set 100 --boot order=virtio0
qm set 100 --usb0 host=10c4:ea60
```

```bash
# CachyOS / htpc: VMID 110. GPU plus two Renesas controllers. Same MAC (10.0.0.164).
qm create 110 --name cachyos --machine q35 --bios ovmf --ostype l26 \
  --cpu host --cores 12 --memory 6144 --balloon 0 --scsihw virtio-scsi-single \
  --net0 virtio=52:54:00:F1:FA:D7,bridge=vmbr0 --onboot 1 --startup order=2 --vga none \
  --affinity 8-19
qm set 110 --efidisk0 "domains:0,efitype=2m,import-from=$E/libvirt/nvram/353d5f5f-12fb-346c-584c-da91227e4804_VARS-pure-efi.fd"
qm set 110 --virtio0 domains:0,import-from=/mnt/cache/domains/CachyOS/vdisk1.img,format=raw,discard=on,iothread=1
qm set 110 --boot order=virtio0
qm set 110 --hostpci0 0000:01:00,pcie=1,x-vga=1 --hostpci1 0000:06:00.0,pcie=1 --hostpci2 0000:07:00.0,pcie=1
```

`--affinity 8-19` keeps Unraid's pinning to host threads 8–19 (4 P-cores plus
the 4 E-cores). Unraid also locked the VM's RAM. With PCI passthrough, PVE pins
all guest RAM anyway.

```bash
# Windows 11 IoT LTSC: VMID 120. The disk was on SATA; keep sata0 so Windows boots without driver changes.
qm create 120 --name win11 --machine q35 --bios ovmf --ostype win11 \
  --cpu host --cores 12 --memory 16384 --balloon 0 \
  --net0 virtio=52:54:00:D1:E5:2E,bridge=vmbr0 --onboot 0 --vga none --affinity 8-19
qm set 120 --efidisk0 "domains:0,efitype=4m,import-from=$E/libvirt/nvram/e492d079-83be-7633-210a-863eab73d6be_VARS-pure-efi-tpm.fd"
qm set 120 --tpmstate0 "domains:0,version=v2.0,import-from=$E/libvirt/swtpm/tpm-states/e492d079-83be-7633-210a-863eab73d6be/tpm2/tpm2-00.permall"
qm set 120 --sata0 "domains:0,import-from=/mnt/cache/domains/Windows 11 Enterprise IoT LTSC/vdisk1.img,format=raw"
qm set 120 --boot order=sata0
qm set 120 --hostpci0 0000:01:00,pcie=1,x-vga=1 --hostpci1 0000:05:00.0,pcie=1 \
  --hostpci2 0000:06:00.0,pcie=1 --hostpci3 0000:07:00.0,pcie=1 --hostpci4 0000:08:00.0,pcie=1
```

libvirt's `tpm2-00.permall` uses swtpm's directory backend format. PVE stores
TPM state as a raw volume. If the import is rejected or the TPM comes up empty,
drop `--tpmstate0` and recreate it with `domains:1,version=v2.0`. Windows then
boots, BitLocker asks for the recovery key, and Hello PINs need re-enrolling.

Mint, NixOS and Arch endeavourOS (if kept): same as HA but without USB, with
`--onboot 0` and `--cores 4`.

Boot order: Docker (Pi-hole, traefik, NetBird) must be up before the VMs, then
HA (order 1), then CachyOS (order 2). Enforce it with a drop-in:

```ini
# /etc/systemd/system/pve-guests.service.d/after-docker.conf
[Unit]
After=docker.service
```

## 10. Phase 6: bring the stack up and verify

```bash
E=/mnt/cache/migration/<ts>
cd /mnt/user/documents/compose
for p in dns traefik deepseek-harness t3code; do
  [ -d "$p" ] && (cd "$p" && docker compose up -d --force-recreate)
done
xargs -r docker start < /mnt/cache/migration/running-before.txt
docker ps --format '{{.Names}}' | sort > /root/running-after.txt
diff /mnt/cache/migration/running-before.txt /root/running-after.txt   # empty = every container is back
systemctl enable --now pihole-host-access deepseek-boot
qm start 100; qm start 110
```

Checklist. Tick every item before calling the migration done.

- [ ] `dig @10.0.0.53 google.com` from the LAN and from the host.
- [ ] Router DHCP DNS switched back to 10.0.0.53.
- [ ] A `https://*.hjacke.com` site loads through traefik (10.0.0.25) with a valid certificate.
- [ ] `ip -4 addr show wt0` shows `100.113.194.104`, `dockhand-netbird-proxy` is up, and a `*.netbird.hjacke.com` URL loads from a phone off the LAN.
- [ ] NetBird dashboard lists all peers.
- [ ] Plex transcodes in hardware (`/dev/dri/renderD128` exists; the dashboard shows "(hw)").
- [ ] `gluetun_torrents` is healthy and qBittorrent loads at `torrent.hjacke.com`.
- [ ] Home Assistant at 10.0.0.23, radio devices respond.
- [ ] CachyOS boots to Limine, the TV shows output, 10.0.0.164 answers.
- [ ] Firefly, Roundcube, Trilium, OpenViking and DSH load with their data.
- [ ] `projetx` Convex data is present.
- [ ] SMB shares mount from the main PC as `jacob`.
- [ ] `docker exec backup-scheduler /bin/bash /scripts/scheduled-backup.sh` finishes without errors and syncs to OneDrive.
- [ ] Reboot the host once. Everything above comes back with no manual steps.

## 11. Phase 7: after the move

1. Delete `/mnt/cache/system/libvirt/libvirt.img`, the old `domains/*/vdisk1.img` files (after each VM is verified), and `/mnt/cache/migration/dryrun`.
2. VM backups: add a PVE `vzdump` job (Datacenter → Backup) for VMIDs 100 and 110 to a `dir` storage on `/mnt/cache/backups/vzdump`, weekly, keep 4. Add that path to restic. Retire `backup/scripts/vm-backup.sh`; it targets a VM that no longer exists.
3. Add `/var/lib/pve-cluster/config.db` (backs `/etc/pve`) and `/etc` to restic.
4. Upgrade traefik to v3.6+ and remove `DOCKER_MIN_API_VERSION`.
5. Enable the PVE host firewall: 8006 and 22 from the LAN and NetBird only.
6. Retire `docker.img`. Point Docker's `data-root` at a btrfs subvolume (`/mnt/cache/system/docker-root`), then rebuild with `docker compose up -d` per project. Phase 0 step 3 makes this painless because no data lives in named volumes any more. Delete the 200 GB image afterwards.
7. Replace the ~200 hard-coded `/mnt/user` and `/mnt/cache` paths with `${DATA}` from a root `.env`. Then drop the `/mnt/user` symlink.
8. Optional: move Docker into a dedicated VM with the data shared over virtiofs. That is cleaner for PVE support and snapshots, but it means reworking macvlan and `/dev/dri`. SQLite-heavy apps (the *arr stack, Plex) can hit mmap and locking problems on virtiofs, so test before committing.

## Rollback

- **Before Phase 2 step 2:** Unraid is untouched. Plug in the Unraid USB stick and boot.
- **After repartitioning:** the btrfs filesystem and its data are unchanged, but Unraid may refuse the shrunk GPT partition as its cache pool. Boot Unraid, assign `nvme0n1p1` to a pool, and never let it format. If Unraid insists on formatting, stop and boot the PVE install instead; the data is still readable there.
- **Last resort:** restore appdata, documents, system and trilium from OneDrive restic onto any fresh install: ~145 GiB at ~17 MB/s, about 2.5 hours.

## Time budget

| Phase | Estimate |
|---|---|
| 0: prepare, system up | 1–3 evenings |
| 1: final backup, stop, export | 1 h |
| 2: repartition | 30 min |
| 3: Debian + PVE | 1 h |
| 4: host config | 1 h |
| 5: VM import (~120 GB local copy) | 1 h |
| 6: bring up and verify | 1 h |

Expected house-wide downtime (DNS, HA, Plex): 5–6 hours.
