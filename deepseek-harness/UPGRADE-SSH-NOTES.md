# Harness 0.2.1-rc.2 deployment — 2026-10-23

Upgraded Tower's `deepseek-harness` from 0.1.7-rc.2 to npm's current latest,
0.2.1-rc.2. Dockerfile and Compose defaults now pin this release.

Reviewed registry plugin updates:
- @zhangfengshun/dsh-remote-ssh: 2.4.18 -> 2.4.36
- dsh-plugin-subscriptions (Codex + Claude): 0.9.9 -> 0.9.10
- @openviking/dsh-memory-plugin: 0.5.2 -> 0.5.28
- dshmarket: 1.59.0 -> 1.69.0
- dsh-context: 0.55.0 -> 0.74.0
- @liustack/modsearch: 5.10.4 -> 5.10.10

Installed together through the new runtime's `dsh plugin` command; did not
bypass compatibility guards. Entrypoint pins match the installed versions.
Existing local plugins and mobile UI remain unchanged.

## Required settings migration

The persisted `profiles/web/cordis.patch.yml` connection override used
`trustedHosts: !!js ctx.webRuntime.trustedHosts`. Harness 0.2 removed that
service; the new shipped web bundle uses `ctx.webStartup.trustedHosts`.
Changed that exact expression, retaining the existing cookie lifetime.
Without this change the required connection plugin fails startup.
The updated SSH plugin works without the former local trust-source patch.

## Verification

- Healthy container, no restart loop after migration.
- `scripts/verify-upgrade.py compare live`: all 4 saved profile IDs and all
  4 saved workspace IDs preserved; API works with loopback and public Host;
  untrusted Host rejected; both subscription accounts still present.
- SSH plugin testConnection succeeds for Tower, Web, and 10.0.0.165.
- Directory listing and remote shell succeed for all 3 workspaces on those
  reachable hosts.
- HTPC 10.0.0.164 was unreachable before the upgrade and remains unreachable
  from the container, Tower itself, and the operator's workstation. Its saved
  profile/workspace are retained; fix host availability separately.
- `scripts/verify-subscription-inference.mjs`: real inference through each
  installed subscription adapter, using its account token manager and live
  model discovery. Codex and Claude both returned the expected OK response.
- Public HTTPS frontend responds 401 without a browser cookie (expected).

`verify-upgrade.py` creates a temporary browser cookie inside the container
from its launch URL; do not print the cookie or launch token. Account checks
print counts only. `upgrade-baseline.json` contains IDs, not credentials.
The inference helper removes its temporary module-export shim in `finally`.
Claude CLI detection can log ENOENT: the plugin uses registry/fallback version
metadata; the Claude CLI executable is not required for subscription inference.

## Rollback backup

`/mnt/user/appdata/deepseek-upgrade-backups/20261023-011259/`
contains the original deployment, full pre-upgrade DSH archive, a second
`dsh-cutover.tar` captured after stopping the old runtime, and container
metadata. Original image retained as `deepseek-harness:rollback-20261023-011259`.
Backups contain credentials: directory is root-only (0700).
Rollback must restore both the old image/config and the DSH profile/plugins;
restoring only the image leaves newer plugins and the new settings expression.
