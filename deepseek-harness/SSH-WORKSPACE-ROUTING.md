# SSH workspace routing fix — 2026-10-23

## Cause

`@zhangfengshun/dsh-remote-ssh@2.4.36` represents each remote workspace with a
local mirror directory containing `.remote-ssh.json`. It supplies explicit
`remote_ssh_*` tools and remote UI endpoints. It does **not** route ordinary
`bash` through SSH. Its filesystem bridge can prefer an existing local mirror
file over the remote file. Thus a model choosing normal tools operates locally,
even if the UI is displaying a remote workspace. This is not an SSH idle timeout.

Reproduced with the real stock tool registry, subprocess/bash/fs implementations,
and the installed SSH plugin: ordinary `bash` returned `deepseek-harness` and the
mirror path, while `remote_ssh_exec` returned the Web host and `/home/ubuntu/c`.
Earlier API/profile tests did not cover ordinary agent tool dispatch.

## Deployment-owned fix

Files under `patches/`:
- `remote-workspace-guard.mjs`: capability-boundary routing and session binding.
- `remote-workspace-fs.py`: remote filesystem operations over SSH, requiring Python 3.
- `patch-remote-workspace-guard.mjs`: reviewed, idempotent integration into the SSH
  plugin. Refuses any unreviewed upstream version other than 2.4.36.

The entrypoint runs the integration patch before starting Harness. These files
are included by the Dockerfile's existing `COPY patches` step. The container was
rebuilt and recreated; this is not merely an edit inside a running container.

### Execution behavior

- A session is bound by its original mirror directory/marker, not by the model
  remembering to select an SSH tool. Effective cwd changes cannot switch hosts.
- Child agents inherit their runtime parent's binding. Bindings are persisted
  under `$DSH_HOME/remote-ssh/session-bindings/` for resume, storing only the
  mirror root (not keys or tokens). Unrelated local sessions remain local.
- Ordinary `bash`, `grep`, and `glob` subprocesses run through OpenSSH on the
  selected target. Shell specs carry their binding into deferred background jobs.
- Ordinary filesystem tools operate on the remote filesystem directly, including
  absolute paths, rather than writing the container mirror and later syncing it.
  Local stale copies are not authoritative. Atomic writes, literal edits, and
  optimistic version guards run on the remote host.
- SSH failure, missing binding metadata, and filesystem errors are visible errors.
  There is no retry on the container filesystem. Commands require a successful
  remote `cd` before execution.
- Async-local execution context keeps concurrent local/remote sessions separate.
- PTC orchestration and existing explicit SSH tools are not double-wrapped;
  nested ordinary tool calls receive their own session routing.
- The model, web server, browser MCP, and orchestration still run in the container.
  This does not install a second Harness runtime on the SSH target.
- Remote shell environment is the target's own environment; container credentials
  and development environment variables are not copied to it.

The filesystem adapter has a 16 MiB text/byte-operation cap and a 60-second SSH
operation deadline. Use remote bash for larger files. Remote file watching is
explicitly unsupported. A future sandboxed FS backend requires review rather
than silently bypassing local confinement.

Web and 10.0.0.165 already provide ripgrep. Tower's matching x86_64 executable is
persisted at `/mnt/user/appdata/deepseek-tools/bin/rg`; the guard uses that as a
fallback if the target has no `rg` in PATH. Python 3 is present on all reachable
targets. The optional `DSH_REMOTE_RG_FALLBACK` env var can override this path.

## Tests

Run on Tower:

```sh
docker exec -i -u node deepseek-harness node --input-type=module - \
  wmuo2hn5j1gvx wmuo2ied2vdxb wmvd7ucf6fyco \
  < scripts/verify-remote-workspace-routing.mjs
python3 scripts/verify-upgrade.py compare
```

The first test uses the actual installed plugin, native working-directory service,
stock tools, native job registry, and real SSH. Only unique temporary test files
are written, and they are cleaned up. Verified on Web, 10.0.0.165, and Tower:

- Native foreground and background bash match explicit SSH hostname/cwd.
- Changing cwd stays remote; child-agent and resumed bindings stay remote.
- Native read/write/edit/grep/glob operate remotely, ignoring a stale local decoy.
- Remote writes do not create local mirror files; stale overwrites are rejected.
- Concurrent local/remote calls remain isolated; ordinary local sessions stay local.
- An intentionally offline SSH fixture and missing marker fail closed.
- All four saved profiles and workspaces, trusted-host rejection, and Codex/Claude
  login state remain intact. Container healthy, zero restarts after deployment.

An actual live Claude session also used ordinary `bash` (no explicit SSH tool or
SSH command) and returned Web's hostname `instance-20251201-2024` and directory
`/home/ubuntu/c`. It is retained as `SSH routing verification (read-only)`, session
`session-5c7d1f67-7af7-4970-9d25-272edeb70a51`.

HTPC 10.0.0.164 remains offline. Its saved workspace remains, but operations must
fail rather than run locally.

## Legacy-layout recovery (2026-10-23)

A subsequent screenshot exposed another layout:
`$DSH_HOME/remote-ssh/workspaces/<uuid>`. Those folders lacked markers and were
not registered in the replacement SSH plugin. The original guard recognized only
`$DSH_HOME/remote-workspaces/`, so unbound legacy folders were mistakenly local.

`patches/migrate-legacy-ssh-workspaces.mjs` now runs before Harness starts. It
recovers only unambiguous mappings explicitly saved in `settings.yaml.imported`,
matching saved SSH aliases to current profiles, restoring markers and adding the
old workspace IDs/paths to the current plugin's workspace list. It does not copy
or synchronize user files. It is idempotent; `--check` reports pending recovery
without writing. Unknown/conflicting mappings are never guessed.

Recovered three original mappings (in addition to the four current workspaces):
- `abbde517-701f-4fca-9414-efdb1eb2f63c`: 10.0.0.165, `/home/jacke/dotfiles`.
- `985c331b-911e-45f6-93b2-feeaaa64194b`: Tower, `/mnt/user/documents/compose`.
- `911e58bd-2ec1-4df8-a603-7477c656176c`: HTPC, `/home/tv/dotfiles` (offline).

The guard now fails closed for **both** layouts when metadata is missing.
The regression harness discovers both layouts, checks the recovered reachable
workspaces with stock shell/file/search/background tools, and explicitly tests
an unbound legacy folder. Before this correction that last test failed by
executing locally; afterward it returns a visible error.

The baseline now intentionally contains seven workspace IDs; the original four
were verified retained before updating it. Legacy recovery backup is recorded in
`/mnt/user/appdata/deepseek-upgrade-backups/latest-legacy-ssh`, including the old
profile and all legacy mirror contents. Image retained as
`deepseek-harness:before-legacy-ssh-recovery`.

Existing chats retain their original legacy cwd and now resolve through the
restored mapping. No chat recreation is required. Refresh the browser to
reconnect and issue a new tool call; an old assistant answer is not re-executed
by refreshing the page.

## Existing local work and rollback

No existing mirror files were deleted or automatically pushed to remote hosts.
Old locally misdirected work may still exist in the mirror; inspect and reconcile
it deliberately to avoid overwriting newer remote files.

Backup: `/mnt/user/appdata/deepseek-upgrade-backups/ssh-routing-20261023-020046/`
(root-only directory). It contains the pre-fix deployment, original SSH plugin
`index.js`, and `remote-workspaces-and-sessions.tar` captured before the restart.
Original image retained as `deepseek-harness:before-ssh-routing`.

Rollback requires restoring both the deployment/image and the original SSH plugin
source: otherwise its import of the guard remains in the persistent home volume.
Session-binding sidecars can be retained; they are read only by the guard.

## File preview and read on the sandbox backend (2026-11-11)

### Symptom

In remote-workspace sessions the Web file preview showed "File not found. It may
have been moved or deleted." for files the model had just created on the target.
Native `read` also returned not-found for remote paths while `bash`, `grep` and
`glob` correctly ran on the target.

### Cause

The DSH base bundle mounts `@deepseek-ai/dsh-fs-sandbox` as `ctx.fs`, and that
backend exposes `sandboxMode`. The guard's filesystem hook refused to wrap any
backend with `sandboxMode` set, and threw inside the `fs` injection, so the
filesystem half of the guard never installed. Only the subprocess half (bash,
grep, glob) was active. The preview RPC and native read/write/edit then fell
through to the SSH plugin's read shadow, which only answers for paths inside a
local mirror directory, so remote absolute paths were not found.

`scripts/verify-remote-workspace-routing.mjs` mounted `dsh-fs-local`, which has
no `sandboxMode`, so it passed while production was broken.

### Fix

- `patches/remote-workspace-guard.mjs` wraps the sandbox backend too. Remote
  mutations enforce the per-call sandbox policy on the target: `read-only`
  denies, `workspace-write` requires the resolved remote path to be inside the
  workspace root, `danger-full-access` passes. Local targets keep the backend's
  own fence.
- `scripts/verify-remote-workspace-routing.mjs` now mounts `dsh-sandbox-policy`
  plus `dsh-fs-sandbox`, matching production. `TEST_MODE` selects the mode.
- New `scripts/verify-remote-preview.mjs` drives `WorkspaceFiles.read` and
  `readBytes` (the preview service) against a remote absolute path outside the
  mirror. It fails with `workspace-file/not-found` on the old guard and passes
  on the new one. With `TEST_MODE=workspace-write` it also checks the fence.

```sh
docker exec -i -u node deepseek-harness node --input-type=module - \
  wmvd7ucf6fyco < scripts/verify-remote-preview.mjs
docker exec -i -u node -e TEST_MODE=workspace-write deepseek-harness \
  node --input-type=module - wmvd7ucf6fyco < scripts/verify-remote-preview.mjs
```

Previous deployed guard is kept in the container at
`/opt/dsh/patches/remote-workspace-guard.mjs.before-sandbox-fs` until rebuild.
The running Harness process loads the guard once at startup, so the fix takes
effect after the container is recreated.
