#!/usr/bin/env bash
set -euo pipefail

# Compose runs this as root so we can publish Unraid's 0600 SSH config, then
# drop to the same uid 1000 / gid 100 / docker group the image used before.
if [ "$(id -u)" -eq 0 ]; then
  # OpenViking runs in api_key mode. Its source ovcli.conf is root-only and
  # also contains an admin-only root key, so derive a node-readable client
  # config containing only the agent API key and the Docker-network endpoint.
  if [ -f /mnt/openviking/ovcli.conf ]; then
    install -d -o 1000 -g 100 -m 700 /home/t3/.openviking
    node -e '
      const fs = require("fs");
      const source = JSON.parse(fs.readFileSync("/mnt/openviking/ovcli.conf", "utf8"));
      if (!source.api_key) throw new Error("OpenViking ovcli.conf has no api_key");
      const target = {
        url: process.env.OPENVIKING_URL || "http://openviking:1933",
        api_key: source.api_key,
        timeout: source.timeout ?? 120,
        output: source.output ?? "table",
      };
      fs.writeFileSync("/home/t3/.openviking/ovcli.conf", JSON.stringify(target, null, 2) + "\n", { mode: 0o600 });
    '
    chown 1000:100 /home/t3/.openviking/ovcli.conf
    chmod 600 /home/t3/.openviking/ovcli.conf
    echo "deepseek-harness: published OpenViking agent credentials"
  fi
  if [ -f /mnt/unraid-ssh/config ]; then
    mkdir -p /etc/ssh/ssh_config.d
    install -m 644 /mnt/unraid-ssh/config /etc/ssh/ssh_config.d/unraid.conf
    echo "deepseek-harness: published Unraid SSH config to /etc/ssh/ssh_config.d/unraid.conf"
  fi
  # Image user is `node` with passwd home /home/node. OpenSSH reads
  # ~/.ssh/config from the passwd home, not $HOME — so without this, Host
  # aliases under /home/t3/.ssh/config are invisible to `ssh`.
  if getent passwd node >/dev/null 2>&1; then
    usermod -d /home/t3 node 2>/dev/null \
      || sed -i 's|^node:x:1000:100::/home/node:|node:x:1000:100::/home/t3:|' /etc/passwd
    echo "deepseek-harness: set node passwd home to /home/t3 for OpenSSH"
  fi

  # A macvlan child cannot reach its parent host through the macvlan NIC.
  # Keep normal LAN traffic on br0_docker, but send Tower's host IP through
  # npm_services' bridge gateway so host-published dev ports remain reachable.
  if [ -n "${TOWER_HOST_IP:-}" ] || [ -n "${TOWER_HOST_ROUTE_VIA:-}" ]; then
    : "${TOWER_HOST_IP:?TOWER_HOST_IP is required when configuring the Tower host route}"
    : "${TOWER_HOST_ROUTE_VIA:?TOWER_HOST_ROUTE_VIA is required when configuring the Tower host route}"
    ip route replace "${TOWER_HOST_IP}/32" via "${TOWER_HOST_ROUTE_VIA}"
    tower_route="$(ip -4 route get "${TOWER_HOST_IP}")"
    case "${tower_route}" in
      *" via ${TOWER_HOST_ROUTE_VIA} "*) ;;
      *)
        echo "deepseek-harness: Tower host route verification failed: ${tower_route}" >&2
        exit 1
        ;;
    esac
    echo "deepseek-harness: routed ${TOWER_HOST_IP}/32 via bridge gateway ${TOWER_HOST_ROUTE_VIA}"
  fi
  exec setpriv --reuid=1000 --regid=100 --init-groups --inh-caps=-all -- "$0" "$@"
fi

DSH_PORT="${DSH_PORT:-13080}"
PROXY_PORT="${PROXY_PORT:-3080}"
TRUSTED_HOST="${TRUSTED_HOST:-code.netbird.hjacke.com}"
DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
AGENTS_SKILLS="${HOME}/.agents/skills"
VENDOR_DIR="${DSH_HOME}/vendor"
PATCHES_DIR="${DSH_PATCHES_DIR:-/opt/dsh/patches}"
BUNDLED_SKILLS="${DSH_BUNDLED_SKILLS:-/opt/dsh/skills}"
REMOTE_VSCODE_INSTALLER="${DSH_REMOTE_VSCODE_INSTALLER:-/opt/dsh/scripts/install-remote-vscode-cli.sh}"
REMOTE_VSCODE_HOSTS="${DSH_REMOTE_VSCODE_HOSTS:-tower}"
REMOTE_SSH_PROXY_JUMPS="${DSH_REMOTE_SSH_PROXY_JUMPS:-}"

mkdir -p "${DSH_HOME}" "${AGENTS_SKILLS}" "${VENDOR_DIR}"

# Some LAN hosts reject direct connections from this macvlan container while
# remaining reachable through another configured SSH host. Persist explicit
# ProxyJump routes without replacing user-managed host options.
ssh_config="${HOME}/.ssh/config"
if [ -n "${REMOTE_SSH_PROXY_JUMPS}" ] && [ -f "${ssh_config}" ]; then
  read -r -a remote_ssh_proxy_jumps <<< "${REMOTE_SSH_PROXY_JUMPS}"
  for route in "${remote_ssh_proxy_jumps[@]}"; do
    target="${route%%=*}"
    jump="${route#*=}"
    if [ -z "${target}" ] || [ -z "${jump}" ] || [ "${target}" = "${jump}" ]; then
      echo "deepseek-harness: warning: invalid Remote SSH proxy route '${route}'" >&2
      continue
    fi
    if ! awk -v target="${target}" '
      BEGIN { active = 0; found = 0 }
      /^[[:space:]]*[Hh][Oo][Ss][Tt][[:space:]]+/ {
        active = 0
        for (i = 2; i <= NF; i++) if ($i == target) active = 1
        next
      }
      active && /^[[:space:]]*[Pp][Rr][Oo][Xx][Yy][Jj][Uu][Mm][Pp][[:space:]]+/ { found = 1 }
      END { exit(found ? 0 : 1) }
    ' "${ssh_config}"; then
      awk -v target="${target}" -v jump="${jump}" '
        BEGIN { active = 0; inserted = 0 }
        /^[[:space:]]*[Hh][Oo][Ss][Tt][[:space:]]+/ {
          if (active && !inserted) { print "  ProxyJump " jump; inserted = 1 }
          active = 0
          for (i = 2; i <= NF; i++) if ($i == target) active = 1
        }
        { print }
        END { if (active && !inserted) print "  ProxyJump " jump }
      ' "${ssh_config}" > "${ssh_config}.tmp"
      mv "${ssh_config}.tmp" "${ssh_config}"
      chmod 600 "${ssh_config}"
      echo "deepseek-harness: routed Remote SSH host ${target} through ${jump}"
    fi
  done
fi

# The Remote SSH bundle prefers its private official CLI. Do not rewrite
# settings.yaml at boot: server rows can be added dynamically, and a previous
# text-based injection placed remoteCodeCommand under workspaces, breaking all
# settings (including the user's model catalog).

# dsh-remote-ssh needs the official VS Code CLI on each target. Unraid rebuilds
# /root in RAM on every boot, so the installer also restores its link to the
# persistent cache-pool copy before DSH accepts any requests.
if [ -x "${REMOTE_VSCODE_INSTALLER}" ] && [ -n "${REMOTE_VSCODE_HOSTS}" ] && grep -q '"dsh-remote-ssh"' "${DSH_HOME}/profiles/web/package.json" 2>/dev/null; then
  read -r -a remote_vscode_hosts <<< "${REMOTE_VSCODE_HOSTS}"
  echo "deepseek-harness: ensuring VS Code Agent Host on ${remote_vscode_hosts[*]}"
  if ! "${REMOTE_VSCODE_INSTALLER}" "${remote_vscode_hosts[@]}"; then
    echo "deepseek-harness: warning: remote VS Code Agent Host setup failed; Remote SSH will retry after the next container restart" >&2
  fi
fi

# Harness 0.1.7 stores settings in the active profile. Never recreate
# settings.yaml: the one-time migration renamed it to settings.yaml.imported.

# DSH 0.1.2 moved trusted-host authorization into the built-in Connection
# service. The old workaround imports dsh-host-apiproxy, which 0.1.2 removed,
# so migrate it out of persistent profiles before boot.
profile_pkg="${DSH_HOME}/profiles/web/package.json"
if grep -q 'dsh-trusted-host-proxy-403-fix' "${profile_pkg}" 2>/dev/null; then
  echo "deepseek-harness: removing obsolete trusted-host workaround"
  dsh plugin --profile web remove dsh-trusted-host-proxy-403-fix
fi

profile_plugin_version() {
  local package="$1" manifest="${DSH_HOME}/profiles/web/node_modules/${1}/package.json"
  [ -f "${manifest}" ] \
    && node -p "JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).version" "${manifest}" 2>/dev/null \
    || true
}

ensure_profile_plugin() {
  local package="$1" version="$2" installed
  installed="$(profile_plugin_version "${package}")"
  if [ "${installed}" = "${version}" ]; then
    return
  fi
  echo "deepseek-harness: installing ${package}@${version} (was ${installed:-missing})"
  dsh plugin --profile web add "${package}@${version}" \
    || echo "deepseek-harness: warning: ${package}@${version} install failed; keeping ${installed:-absent}" >&2
}

# dsh-remote-ssh@0.2.4 uses the pre-0.1.7 settings interface and disables
# the stock filesystem/shell routes. Keep its local checkout and saved remote
# mappings for future migration, but do not install it on Harness 0.1.7.

# dsh-better-sidebar is optional for the fork's remote-workspace, SSH tool,
# and terminal features. Keep its checkout for a later Files-tab deployment,
# but do not reinstall the inactive sidebar bundle at boot.

# Keep registry-backed profile plugins on reviewed versions. Disable plugins
# that fail composition with this Harness release rather than forcing them.
# Local/link plugins remain deployment-owned.
# Task board 0.3.24 requires the removed settingsScope service on 0.1.7;
# keep ~/.dsh/task-board data, but do not install the incompatible plugin.
ensure_profile_plugin "@liustack/modsearch" "5.10.10"
ensure_profile_plugin "@openviking/dsh-memory-plugin" "0.5.28"
ensure_profile_plugin "dsh-context" "0.74.0"
ensure_profile_plugin "dshmarket" "1.69.0"
ensure_profile_plugin "@canary-builds/dsh-mobile-ui" "1.1.2"
# This fork declares compatibility with the Harness 0.2.1 release line.
# The former dsh-remote-ssh@0.2.4 must remain disabled.
ensure_profile_plugin "@zhangfengshun/dsh-remote-ssh" "2.4.36"

# Subscription OAuth providers (ChatGPT/Codex, Claude, Grok, Copilot,
# Antigravity) via dsh-plugin-subscriptions. Supersedes the old
# birat-chapagain/dsh-codex-oauth bundle, which only covered Codex.
# Credentials do not migrate: re-authorize under Settings -> Subscriptions.
# 0.9.12 is the first release whose peer ranges admit Harness 0.2.1-rc.5.
ensure_profile_plugin "dsh-plugin-subscriptions" "0.9.12"

# Migrate away from the retired dsh-codex-oauth plugin.
if grep -q dsh-codex-oauth "${profile_pkg}" 2>/dev/null; then
  echo "deepseek-harness: removing obsolete dsh-codex-oauth plugin"
  dsh plugin --profile web remove dsh-codex-oauth \
    || echo "deepseek-harness: warning: dsh-codex-oauth removal failed" >&2
fi

# Local patch: sanitize Anthropic tool_use/tool_result ids; DSH history from
# other providers can carry characters outside ^[a-zA-Z0-9_-]+$ which the
# Claude API rejects with HTTP 400. Idempotent.
SUBS_ID_PATCH="/opt/dsh/patches/patch-subscriptions-tool-ids.mjs"
if [ -f "${SUBS_ID_PATCH}" ]; then
  node "${SUBS_ID_PATCH}"
fi

# A remote workspace must route ordinary tools, not merely offer optional SSH
# tools. Fail startup if the reviewed routing patch cannot be installed.
node "${PATCHES_DIR}/migrate-legacy-ssh-workspaces.mjs"
node "${PATCHES_DIR}/patch-remote-workspace-guard.mjs"

# Saved model choices now live in the profile patch (migrated by Harness).
# Do not append model rows to the retired settings.yaml file.

# The old VS Code Agent Host plugin and its sidebar patch remain disabled.
# The replacement uses OpenSSH directly and needs no VS Code Server.

# Sparse clone: only the skills/ tree. Repos are large (especially caveman).
sync_repo() {
  local url="$1" dest="$2"
  if [ -d "${dest}/.git" ]; then
    echo "deepseek-harness: updating $(basename "${dest}")"
    git -C "${dest}" fetch --depth 1 origin 2>/dev/null || return 0
    git -C "${dest}" reset --hard FETCH_HEAD 2>/dev/null || true
  else
    echo "deepseek-harness: cloning ${url} (skills/ only)"
    git clone --depth 1 --filter=blob:none --sparse "${url}" "${dest}"
    git -C "${dest}" sparse-checkout set skills
  fi
}

# Link each <dir>/SKILL.md into ~/.agents/skills/<dir-name> so dsh discovers it.
# Skip caveman's plugins/ mirror (same skills as skills/).
link_skill_tree() {
  local root="$1"
  [ -d "${root}" ] || return 0
  find "${root}" -name SKILL.md -type f | while read -r skill; do
    local dir name
    dir="$(dirname "${skill}")"
    case "${dir}" in
      */plugins/*) continue ;;
    esac
    name="$(basename "${dir}")"
    ln -sfn "${dir}" "${AGENTS_SKILLS}/${name}"
  done
}

sync_repo https://github.com/mattpocock/skills.git "${VENDOR_DIR}/mattpocock-skills"
sync_repo https://github.com/JuliusBrussee/caveman.git "${VENDOR_DIR}/caveman"

link_skill_tree "${VENDOR_DIR}/mattpocock-skills/skills"
link_skill_tree "${VENDOR_DIR}/caveman/skills"

if [ -d "${BUNDLED_SKILLS}" ]; then
  find "${BUNDLED_SKILLS}" -mindepth 1 -maxdepth 1 -type d | while read -r dir; do
    ln -sfn "${dir}" "${AGENTS_SKILLS}/$(basename "${dir}")"
  done
fi

echo "deepseek-harness: skills in ${AGENTS_SKILLS}"
ls -1 "${AGENTS_SKILLS}" | sed 's/^/  /' || true

PATCH_ARGS=()
if [ -f "${PATCHES_DIR}/reliability.cordis.yml" ]; then
  PATCH_ARGS+=(--patch "${PATCHES_DIR}/reliability.cordis.yml")
  echo "deepseek-harness: agent reliability overlay ${PATCHES_DIR}/reliability.cordis.yml"
fi
if [ -f "${PATCHES_DIR}/context7.cordis.yml" ]; then
  PATCH_ARGS+=(--patch "${PATCHES_DIR}/context7.cordis.yml")
  echo "deepseek-harness: Context7 MCP overlay ${PATCHES_DIR}/context7.cordis.yml"
  if [ -z "${CONTEXT7_API_KEY:-}" ]; then
    echo "deepseek-harness: CONTEXT7_API_KEY unset (works, higher limits with a key from https://context7.com/dashboard)"
  fi
fi
if [ -f "${PATCHES_DIR}/chrome-devtools.cordis.yml" ]; then
  PATCH_ARGS+=(--patch "${PATCHES_DIR}/chrome-devtools.cordis.yml")
  echo "deepseek-harness: Chrome DevTools MCP overlay ${PATCHES_DIR}/chrome-devtools.cordis.yml"
fi
if [ -f "${PATCHES_DIR}/openviking.cordis.yml" ]; then
  PATCH_ARGS+=(--patch "${PATCHES_DIR}/openviking.cordis.yml")
  echo "deepseek-harness: OpenViking memory overlay ${PATCHES_DIR}/openviking.cordis.yml"
fi

# DSH provider routes in this profile target Headroom on loopback. Start and
# supervise it in this container; without this process model requests fail as
# Connection errors before reaching OpenRouter or DeepSeek.
HEADROOM_STARTER="${DSH_HEADROOM_STARTER:-${HOME}/.headroom/start-dsh-proxy.sh}"
headroom_pid=""
if [ -x "${HEADROOM_STARTER}" ]; then
  if ! curl -fsS --max-time 1 http://127.0.0.1:8788/readyz >/dev/null 2>&1; then
    echo "deepseek-harness: starting Headroom provider proxy on 127.0.0.1:8788"
    "${HEADROOM_STARTER}" &
    headroom_pid=$!
    for _ in $(seq 1 60); do
      if curl -fsS --max-time 1 http://127.0.0.1:8788/readyz >/dev/null 2>&1; then
        break
      fi
      if ! kill -0 "${headroom_pid}" 2>/dev/null; then
        echo "deepseek-harness: Headroom proxy exited before becoming ready" >&2
        wait "${headroom_pid}" || true
        exit 1
      fi
      sleep 1
    done
    if ! curl -fsS --max-time 1 http://127.0.0.1:8788/readyz >/dev/null 2>&1; then
      echo "deepseek-harness: Headroom proxy did not become ready" >&2
      exit 1
    fi
  else
    echo "deepseek-harness: Headroom provider proxy already ready"
  fi
else
  echo "deepseek-harness: warning: Headroom proxy launcher missing at ${HEADROOM_STARTER}" >&2
fi

# Invalid settings must fail startup visibly, not silently hide saved models.
if [ -f "${DSH_HOME}/settings.yaml" ]; then
  node - "${DSH_HOME}/settings.yaml" <<'JS'
const fs = require('node:fs');
const { createRequire } = require('node:module');
const yaml = createRequire('/usr/local/lib/node_modules/@deepseek-ai/dsh/package.json')('yaml');
const document = yaml.parseDocument(fs.readFileSync(process.argv[2], 'utf8'));
if (document.errors.length) {
  console.error('deepseek-harness: invalid settings.yaml:', document.errors.map(error => `${error.code} at line ${error.linePos?.[0]?.line ?? '?'}`).join(', '));
  process.exit(1);
}
JS
fi

echo "deepseek-harness: starting dsh on 127.0.0.1:${DSH_PORT}"
echo "deepseek-harness: trusted host ${TRUSTED_HOST}"
echo "deepseek-harness: proxying 0.0.0.0:${PROXY_PORT} -> 127.0.0.1:${DSH_PORT}"

# --patch is a launcher flag used with --profile, not with the `web` alias.
# dsh refuses --host 0.0.0.0; keep loopback and front with socat for the reverse proxy.
dsh \
  --profile web \
  "${PATCH_ARGS[@]}" \
  --no-open \
  --host 127.0.0.1 \
  --port "${DSH_PORT}" \
  --trusted-host "${TRUSTED_HOST}" \
  --trusted-host "127.0.0.1:${DSH_PORT}" \
  &
dsh_pid=$!

cleanup() {
  kill "${dsh_pid}" 2>/dev/null || true
  kill "${proxy_pid:-}" 2>/dev/null || true
  if [ -n "${headroom_pid}" ]; then
    # start-dsh-proxy.sh spawns the proxy and stats bridge as direct children.
    pkill -TERM -P "${headroom_pid}" 2>/dev/null || true
    kill "${headroom_pid}" 2>/dev/null || true
  fi
  wait "${dsh_pid}" 2>/dev/null || true
  wait "${proxy_pid:-}" 2>/dev/null || true
  wait "${headroom_pid:-}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Wait until loopback accepts connections before advertising the proxy port.
for _ in $(seq 1 60); do
  # DSH 0.1.2 returns 401 at / until the browser exchanges its launch token.
  # Any HTTP response proves the listener is ready; transport failures do not.
  if curl -sS --max-time 1 "http://127.0.0.1:${DSH_PORT}/" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "${dsh_pid}" 2>/dev/null; then
    echo "deepseek-harness: dsh exited before becoming ready" >&2
    wait "${dsh_pid}" || true
    exit 1
  fi
  sleep 1
done

# Keep the launcher as PID 1's child. If either the web server or its proxy
# exits, exit too so Docker's restart policy restores a working pair rather
# than reporting a live proxy that can only return connection refusals.
socat "TCP-LISTEN:${PROXY_PORT},fork,reuseaddr,bind=0.0.0.0" "TCP:127.0.0.1:${DSH_PORT}" &
proxy_pid=$!
wait -n "${dsh_pid}" "${proxy_pid}"
exit 1
