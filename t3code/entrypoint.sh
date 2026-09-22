#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/home/t3}"
export PATH="${HOME}/.local/bin:/usr/local/bin:/opt/cursor-cli:${PATH}"

mkdir -p \
  "${HOME}/.local/bin" \
  "${HOME}/.t3" \
  "${HOME}/.cursor" \
  "${HOME}/.config/gh" \
  "${HOME}/.ssh" \
  /var/run/sshd

# T3 looks for `cursor-agent`; Cursor installer ships `agent`.
if [[ -x "${HOME}/.local/bin/agent" ]]; then
  ln -sf "${HOME}/.local/bin/agent" "${HOME}/.local/bin/cursor-agent"
elif [[ -x /opt/cursor-cli/cursor-agent ]]; then
  mkdir -p "${HOME}/.local/bin"
  ln -sf /opt/cursor-cli/cursor-agent "${HOME}/.local/bin/agent"
  ln -sf /opt/cursor-cli/cursor-agent "${HOME}/.local/bin/cursor-agent"
elif [[ -x /opt/cursor-cli/agent ]]; then
  mkdir -p "${HOME}/.local/bin"
  ln -sf /opt/cursor-cli/agent "${HOME}/.local/bin/agent"
  ln -sf /opt/cursor-cli/agent "${HOME}/.local/bin/cursor-agent"
fi

chmod 700 "${HOME}/.ssh" 2>/dev/null || true
# Unraid array mounts are often 777; OpenSSH StrictModes rejects that. Tighten what we can.
chmod 755 "${HOME}" 2>/dev/null || true
chown t3:users "${HOME}" /workspace 2>/dev/null || true
chown -R t3:users "${HOME}/.ssh" 2>/dev/null || true

# Build authorized_keys from known private keys + optional T3_SSH_PUBKEY.
auth_keys="${HOME}/.ssh/authorized_keys"
tmp_keys="$(mktemp)"
touch "${tmp_keys}"
if [[ -f "${auth_keys}" ]]; then
  cat "${auth_keys}" >> "${tmp_keys}" || true
fi
for keyfile in github_privatekey codeberg_privatekey gitlab_privatekey id_ed25519 id_rsa; do
  if [[ -f "${HOME}/.ssh/${keyfile}" ]]; then
    chmod 600 "${HOME}/.ssh/${keyfile}" || true
    if pub="$(ssh-keygen -y -f "${HOME}/.ssh/${keyfile}" 2>/dev/null)"; then
      echo "${pub}" >> "${tmp_keys}"
    fi
  fi
done
if [[ -n "${T3_SSH_PUBKEY:-}" ]]; then
  echo "${T3_SSH_PUBKEY}" >> "${tmp_keys}"
fi
if [[ -s "${tmp_keys}" ]]; then
  sort -u "${tmp_keys}" > "${auth_keys}"
  chmod 600 "${auth_keys}"
  chown t3:users "${auth_keys}"
fi
rm -f "${tmp_keys}"

# Persistent SSH host keys (so desktop SSH launch fingerprints stay stable).
mkdir -p /etc/ssh/host-keys
if [[ ! -f /etc/ssh/host-keys/ssh_host_ed25519_key ]]; then
  ssh-keygen -q -N "" -t ed25519 -f /etc/ssh/host-keys/ssh_host_ed25519_key
  ssh-keygen -q -N "" -t rsa -b 4096 -f /etc/ssh/host-keys/ssh_host_rsa_key
fi
cp -a /etc/ssh/host-keys/ssh_host_* /etc/ssh/ 2>/dev/null || true
chmod 600 /etc/ssh/ssh_host_*_key 2>/dev/null || true
chmod 644 /etc/ssh/ssh_host_*_key.pub 2>/dev/null || true

# Non-interactive SSH (T3 desktop launcher uses `sh -lc`) must see node/npm/t3.
if ! grep -q '/usr/local/bin' /home/t3/.bashrc 2>/dev/null; then
  cat >> /home/t3/.bashrc <<'EOF'
export HOME=/home/t3
export PATH="/home/t3/.local/bin:/usr/local/bin:/opt/cursor-cli:$PATH"
cd /workspace 2>/dev/null || true
EOF
  chown t3:users /home/t3/.bashrc
fi
# login shells via sh -lc source profile
if [[ ! -f /home/t3/.profile ]]; then
  cat > /home/t3/.profile <<'EOF'
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
EOF
  chown t3:users /home/t3/.profile
fi

# node image locks the default user (! in shadow); * keeps pubkey SSH working.
usermod -p '*' t3 2>/dev/null || true

# Daemonize sshd before exec'ing the main process. Orphans from SSH sessions and
# agent subprocesses must be reaped by container init (`init: true` / tini).
/usr/sbin/sshd

echo "=== t3code container ==="
echo "workspace: /workspace"
echo "  compose  -> /workspace/compose"
echo "  dev      -> /workspace/dev"
echo "  work     -> /workspace/work"
echo "  projects -> /workspace/projects"
echo
echo "Desktop SSH launch target:    t3@100.113.194.104 -p 2223"
echo "  Settings → Connections → Add environment → SSH launch"
echo

if command -v agent >/dev/null 2>&1; then
  echo -n "cursor-agent: "
  agent --version 2>/dev/null || echo "installed"
  if [[ -n "${CURSOR_API_KEY:-}" ]]; then
    echo "cursor auth: CURSOR_API_KEY is set"
  else
    echo "cursor auth: run  docker exec -it t3code agent login"
  fi
fi

if command -v gh >/dev/null 2>&1; then
  if gosu t3 env HOME=/home/t3 gh auth status >/dev/null 2>&1; then
    echo "github: authenticated"
  else
    echo "github: run  docker exec -it -u t3 t3code gh auth login"
  fi
fi

if [[ -S /var/run/docker.sock ]]; then
  if docker info >/dev/null 2>&1; then
    echo "docker: host socket OK"
  else
    echo "WARNING: docker.sock mounted but not usable"
  fi
fi

echo
# Drop privileges for the long-running T3 server.
exec gosu t3 env HOME=/home/t3 PATH="/home/t3/.local/bin:/usr/local/bin:/opt/cursor-cli:${PATH}" "$@"
