#!/usr/bin/env bash
# Install the official VS Code CLI to ~/.dsh-remote-ssh/cli/bin/code on a host
# reachable via SSH from deepseek-harness. On Unraid, keep the data on the
# cache pool and recreate the volatile /root link after every boot. Usage:
#   ./install-remote-vscode-cli.sh htpc web tower
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <ssh-host>..." >&2
  exit 1
fi

failed=0
for host in "$@"; do
  echo "=== $host ==="
  if ! ssh -o BatchMode=yes -o ConnectTimeout=15 -T "$host" 'set -e
arch=$(uname -m)
case "$arch" in
  x86_64) os=cli-alpine-x64 ;;
  aarch64|arm64) os=cli-alpine-arm64 ;;
  *) echo "unsupported arch: $arch" >&2; exit 1 ;;
esac
runtime_root="$HOME/.dsh-remote-ssh"
if [ -r /etc/os-release ] && grep -qx '\''ID="unraid-os"'\'' /etc/os-release; then
  persistent_root=/mnt/cache/appdata/dsh-remote-ssh/root
  if ! mountpoint -q /mnt/cache; then
    echo "Unraid cache pool is not mounted: /mnt/cache" >&2
    exit 1
  fi
  mkdir -p "$persistent_root"
  chmod 700 "$persistent_root"
  if [ -L "$runtime_root" ]; then
    current_target=$(readlink "$runtime_root")
    if [ "$current_target" != "$persistent_root" ]; then
      rm "$runtime_root"
      ln -s "$persistent_root" "$runtime_root"
    fi
  elif [ -e "$runtime_root" ]; then
    legacy_root="$runtime_root.pre-persistent.$(date +%s)"
    mv "$runtime_root" "$legacy_root"
    ln -s "$persistent_root" "$runtime_root"
    cp -a "$legacy_root/." "$runtime_root/"
  else
    ln -s "$persistent_root" "$runtime_root"
  fi
  echo "persistent root: $persistent_root"
else
  mkdir -p "$runtime_root"
fi
dest="$runtime_root/cli/bin"
mkdir -p "$dest"
if [ -x "$dest/code" ] && "$dest/code" agent host --help >/dev/null 2>&1; then
  echo "already installed: $dest/code"
  "$dest/code" --version
  exit 0
fi
tmpdir=$(mktemp -d)
trap "rm -rf $tmpdir" EXIT
url="https://update.code.visualstudio.com/latest/$os/stable"
echo "downloading $url"
curl -fsSL \
  --retry 5 \
  --retry-delay 2 \
  --retry-all-errors \
  --connect-timeout 15 \
  --max-time 300 \
  "$url" -o "$tmpdir/vscode-cli.tar.gz"
tar -xzf "$tmpdir/vscode-cli.tar.gz" -C "$tmpdir"
bin=$(find "$tmpdir" -type f -name code -perm -u+x | head -1)
if [ -z "$bin" ]; then
  echo "no code binary in archive" >&2
  exit 1
fi
install -m 755 "$bin" "$dest/code"
"$dest/code" --version
"$dest/code" agent host --help | head -3
'; then
    echo "warning: VS Code CLI setup failed on $host; continuing with other hosts" >&2
    failed=1
  fi
done
exit "$failed"
