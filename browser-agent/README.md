# browser-agent

Headless browser automation with [browser-use](https://github.com/browser-use/browser-use) and credential injection with [Bitwarden Agent Access](https://github.com/bitwarden/agent-access) (`aac`).

## Services

| Service | Container | Purpose |
|---|---|---|
| `chrome` | `browser-agent-chrome` | Headless Chromium from the browser-use image. CDP listens on `127.0.0.1:9222` inside the container's network namespace and is not published to the host. |
| `agent` | `browser-agent` | browser-use CLI 3.x plus `aac`. It shares Chrome's network namespace and attaches through `BU_CDP_URL=http://127.0.0.1:9222`. |

Persistent data lives in `/mnt/user/appdata/browser-agent/`:

- `chrome/profile`: the Chromium profile (cookies and logins survive restarts)
- `aac`: the `aac` identity, PSKs and cached connections (`~/.access-protocol`)
- `workspace`: the working directory for scripts and output

## Build and start

```sh
docker compose build --pull   # pulls browseruse/browseruse and bakes in aac
docker compose up -d
```

Versions are pinned in `.env` (`BROWSER_USE_TAG`, `AAC_VERSION`). `docker compose build` needs buildx 0.17 or newer. Unraid ships v0.15.1, so `/boot/config/go` runs `/boot/config/scripts/install-docker-buildx.sh` at boot to install the newer copy from `/boot/config/docker-cli-plugins/`.

## browser-use

The CLI runs Python piped on stdin against a persistent browser session:

```sh
docker compose exec -T agent browser-use <<'PY'
new_tab("https://example.com")
wait_for_load()
print(page_info())
PY
```

`browser-use skill show` prints the full helper reference. To use the LLM `Agent` Python API, put a provider key in `.env` and run the script with `docker compose exec agent python script.py`.

## Agent Access

`aac` is the remote side. The trusted side (`aac listen`, with the Bitwarden CLI unlocked) runs on your own machine.

1. On your desktop: `aac listen`, then `/unlock` and `/pair` to get a pairing token.
2. Pair this container once:

   ```sh
   docker compose exec agent aac connect --token <pairing-token> --output json
   ```

3. Fetch or inject credentials; each request is approved on the desktop:

   ```sh
   docker compose exec agent aac connect --domain github.com --output json
   docker compose exec agent aac run --domain github.com --env-all -- python login.py
   ```

`aac run` passes secrets only through the child process environment (`AAC_USERNAME`, `AAC_PASSWORD`, `AAC_TOTP`, ...), which keeps them out of LLM context and logs.

Both sides use the public relay `wss://ap.lesspassword.dev` by default. The project is an early preview, so treat the protocol and CLI as unstable.
