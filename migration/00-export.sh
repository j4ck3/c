#!/bin/bash
# Pre-migration export for tower (Unraid 7.0 -> Proxmox VE 9).
#
# Writes only under $OUT. Nothing on the system is modified or deleted.
# Run it twice:
#   1. Days before cutover, as a dry run (volume tars of running databases are
#      then crash-consistent at best).
#   2. At cutover, after every container and VM is stopped (Phase 2 in PLAN.md).
#
# Usage: bash 00-export.sh            # OUT defaults to /mnt/cache/migration/<timestamp>
#        OUT=/some/dir bash 00-export.sh
set -uo pipefail

OUT="${OUT:-/mnt/cache/migration/$(date +%Y%m%d-%H%M)}"
# Volumes that hold only rebuildable caches or belong to dead stacks.
SKIP_RE='(node[-_]modules|_next$|svelte-kit|buildkit|^runner-|restic-cache|netdata_cache|act-toolcache|^gitlab-runner|^projectx_|^tsd_proxy|^z-ollama)'

mkdir -p "$OUT"/{host,flash,libvirt,docker/volumes,docker/images}
log() { printf '%s %s\n' "$(date +%T)" "$*" | tee -a "$OUT/export.log"; }

log "host facts -> $OUT/host"
sfdisk -d /dev/nvme0n1 > "$OUT/host/nvme0n1.sfdisk"
btrfs filesystem show --raw /mnt/cache > "$OUT/host/btrfs-show.txt"
btrfs filesystem usage -T /mnt/cache > "$OUT/host/btrfs-usage.txt"
blkid > "$OUT/host/blkid.txt"
lspci -nnk > "$OUT/host/lspci.txt"
ip -d addr > "$OUT/host/ip-addr.txt"
ip route > "$OUT/host/ip-route.txt"
for g in /sys/kernel/iommu_groups/*; do
  echo "$(basename "$g"): $(ls "$g/devices" | tr '\n' ' ')"
done > "$OUT/host/iommu-groups.txt"

log "flash /boot/config"
cp -a /boot/config "$OUT/flash/"

log "libvirt XML, NVRAM, swtpm"
virsh list --all --name | while IFS= read -r vm; do
  [ -n "$vm" ] && virsh dumpxml --security-info "$vm" > "$OUT/libvirt/$vm.xml"
done
cp -a /etc/libvirt/qemu/nvram /etc/libvirt/qemu/swtpm "$OUT/libvirt/"

log "docker metadata"
docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | sort > "$OUT/docker/containers-before.tsv"
docker inspect $(docker ps -aq) > "$OUT/docker/containers-inspect.json"
docker network inspect $(docker network ls -q) > "$OUT/docker/networks-inspect.json"
docker volume ls --format '{{.Name}}' | sort > "$OUT/docker/volumes.txt"
docker images --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}' | sort > "$OUT/docker/images.txt"

log "named volumes (safety copy; docker.img stays the primary carrier)"
while read -r v; do
  if [[ "$v" =~ $SKIP_RE ]]; then log "skip $v"; continue; fi
  src="/var/lib/docker/volumes/$v/_data"
  [ -d "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ] || continue
  if tar -C "$src" --numeric-owner -I 'zstd -T0' -cf "$OUT/docker/volumes/$v.tar.zst" .; then
    log "ok $v"
  else
    log "FAIL $v"
  fi
done < "$OUT/docker/volumes.txt"

log "images without a build recipe in git"
for img in dockhand-caddy-cloudflare:local watchtower-defer:local backup-scheduler:latest; do
  if docker save "$img" | zstd -T0 > "$OUT/docker/images/${img//[:\/]/_}.tar.zst"; then
    log "ok $img"
  else
    log "FAIL $img"
  fi
done

log "git report"
for repo in /mnt/user/documents/compose /mnt/user/documents/work/*/ /mnt/user/documents/projects/*/ /mnt/user/documents/dev/*/; do
  [ -d "$repo" ] || continue
  if [ ! -e "$repo/.git" ]; then echo "NO-GIT  $repo"; continue; fi
  gitq() { git -c safe.directory='*' -C "$repo" "$@"; }
  printf 'dirty=%-4s unpushed=%-4s %s  %s\n' \
    "$(gitq status --porcelain | wc -l)" \
    "$(gitq log --branches --not --remotes --oneline | wc -l)" \
    "$repo" "$(gitq remote get-url origin 2>/dev/null || echo NO-REMOTE)"
done > "$OUT/git-report.txt"

log "checksums"
(cd "$OUT" && find . -type f ! -name SHA256SUMS ! -name export.log -print0 | xargs -0 sha256sum > SHA256SUMS)

log "done: $OUT ($(du -sh "$OUT" | cut -f1))"
if grep -q FAIL "$OUT/export.log"; then
  log "WARNING: some steps failed, see export.log"
fi
exit 0
