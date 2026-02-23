# ZeroClaw (Arch Linux + OSINT tools)

ZeroClaw runs in a headless Arch Linux container with OSINT CLI tools, exposed at **https://zeroclaw.hjacke.com** via Traefik. Telegram is used as the messaging channel.

## Prerequisites

- Docker and Docker Compose
- Traefik on `npm_services` with `letsencrypt` cert resolver
- **DNS:** `zeroclaw.hjacke.com` must resolve to the host where Traefik receives HTTPS (same IP as your other `*.hjacke.com` services, e.g. 10.0.0.25 or your public IP).

### DNS: make zeroclaw.hjacke.com resolve

Add a DNS record so `zeroclaw.hjacke.com` points to the same IP as your other subdomains (e.g. gitea.hjacke.com, openclaw.hjacke.com):

| Type | Name      | Value        | TTL (optional) |
|------|-----------|--------------|----------------|
| A    | zeroclaw  | \<Traefik IP\> | 300 or default |

- **If you use a wildcard:** `*.hjacke.com` → \<Traefik IP\> already covers zeroclaw; no new record needed (unless the wildcard is not set).
- **If you add each subdomain by name:** Create an **A** record with name **zeroclaw** (host/subdomain), value = the IP where Traefik is reachable (from [traefik/compose.yml](traefik/compose.yml) that is often a dedicated IP like **10.0.0.25**).

After saving, wait for TTL or flush DNS (`ipconfig /flushdns` on Windows, `sudo dscacheutil -flushcache` on macOS, or just wait a few minutes). Check with: `ping zeroclaw.hjacke.com` or `nslookup zeroclaw.hjacke.com`.

## Quick start

1. **Create appdata and env**

   ```bash
   mkdir -p /mnt/user/appdata/zeroclaw/workspace
   cp zeroclaw/.env.example zeroclaw/.env
   # Edit zeroclaw/.env: set API_KEY, PROVIDER, TELEGRAM_BOT_TOKEN
   ```

2. **Optional: put TOOLS.md in workspace**  
   So the agent can use the CLI tools reference:

   ```bash
   cp zeroclaw/workspace/TOOLS.md /mnt/user/appdata/zeroclaw/workspace/
   ```

   Or add a read-only mount in `compose.yml` (under `volumes`):

   ```yaml
   - ./workspace:/zeroclaw-data/workspace:ro
   ```

   (If you use this mount, the repo’s `workspace/` becomes the container workspace; remove or adjust the single `/mnt/user/appdata/zeroclaw` mount if you want only the repo workspace.)

3. **Build and run**

   ```bash
   cd /mnt/user/documents/compose/zeroclaw
   docker compose build
   docker compose up -d
   ```

   **If you see "pull access denied" for zeroclaw:** build the image first (step above), then run `docker compose up -d` again.

   **If you see "compose build requires buildx 0.17 or later":** build with the legacy Docker builder, then start Compose (no buildx needed):

   ```bash
   cd /mnt/user/documents/compose/zeroclaw
   DOCKER_BUILDKIT=0 docker build -t zeroclaw:local .
   docker compose up -d
   ```

4. **Health check**

   Open https://zeroclaw.hjacke.com/health (or run `zeroclaw status` inside the container).

### Persistent downloads (pages/files)

The compose bind-mounts **`/mnt/user/appdata/zeroclaw/downloads`** into the container at **`/zeroclaw-data/downloads`**. The AI can save downloaded pages (wget, curl, or browser) there; files persist on the host. Ensure the directory exists and is writable by the zeroclaw user (uid 1000):

```bash
mkdir -p /mnt/user/appdata/zeroclaw/downloads && chown 1000:1000 /mnt/user/appdata/zeroclaw/downloads
```

### Memory and persistent chats

Memory and chat history are **persistent** because the whole appdata dir is bind-mounted:

- **`/mnt/user/appdata/zeroclaw`** → **`/zeroclaw-data`** in the container.
- The memory backend is **SQLite**; the DB lives at **`/zeroclaw-data/.zeroclaw/workspace/memory/brain.db`** (i.e. on the host under `appdata/zeroclaw`).
- In **`config.toml`** under **`[memory]`** you can set:
  - **`conversation_retention_days`** — how long to keep conversation history (default 90).
  - **`purge_after_days`** — when to purge old memory entries (default 90).
  - **`embedding_provider = "openai"`** — uses your OpenAI key for semantic memory recall across chats.
  - **`response_cache_enabled = true`** — caches LLM responses for repeated prompts (saves cost).

Restarting the container or the host does not clear memory or chats; they stay in the sqlite DB on the host.

## Migrating from OpenClaw

OpenClaw state lives at `/mnt/user/appdata/openclaw/config` (the `~/.openclaw` equivalent).

### One-off migration inside the ZeroClaw container

1. In `zeroclaw/compose.yml`, temporarily add a read-only volume for OpenClaw config:

   ```yaml
   volumes:
     - /mnt/user/appdata/zeroclaw:/zeroclaw-data
     - /mnt/user/appdata/openclaw/config:/mnt/openclaw-state:ro
   ```

2. Start the stack and run migration:

   ```bash
   cd /mnt/user/documents/compose/zeroclaw
   docker compose up -d
   docker compose exec zeroclaw zeroclaw migrate openclaw --source /mnt/openclaw-state
   ```

3. If the migration tool expects the **parent** of the config dir (a directory named `.openclaw`), mount the parent instead:

   ```yaml
   - /mnt/user/appdata/openclaw:/mnt/openclaw-state:ro
   ```

   and again: `zeroclaw migrate openclaw --source /mnt/openclaw-state`.

4. **Telegram:** Ensure `[channels_config.telegram]` in ZeroClaw’s config has the correct `bot_token` (e.g. from `openclaw/.env` as `TELEGRAM_BOT_TOKEN`). Migration may copy this; if not, set it in `/mnt/user/appdata/zeroclaw/.zeroclaw/config.toml` or via env.

5. **Allowlist:** Start with `allowed_users = []` (deny-by-default). After sending a message from Telegram, check logs for the sender identity, then run:

   ```bash
   docker compose exec zeroclaw zeroclaw channel bind-telegram <IDENTITY>
   ```

   Or set `allowed_users = ["*"]` only for quick testing.

6. Remove the temporary OpenClaw volume from `compose.yml`, then:

   ```bash
   docker compose exec zeroclaw zeroclaw doctor
   docker compose restart zeroclaw
   ```

## Telegram configuration

In `~/.zeroclaw/config.toml` (i.e. `/mnt/user/appdata/zeroclaw/.zeroclaw/config.toml` inside the container or on the host):

```toml
[channels_config.telegram]
bot_token = "<from TELEGRAM_BOT_TOKEN in .env or set here>"
allowed_users = []   # use zeroclaw channel bind-telegram <id> after first message, or ["*"] for testing
```

Telegram uses **polling**; no public URL or tunnel is required for the Telegram channel. The subdomain zeroclaw.hjacke.com is for the gateway (health, pairing, webhook).

## Security

- Do not commit `zeroclaw/.env`. Use `.env.example` as a template.
- For production, set `allowed_users` to explicit Telegram user IDs and avoid `["*"]`.
- Gateway pairing: if you use the web UI at zeroclaw.hjacke.com, complete pairing (e.g. POST /pair with the one-time code).

## OpenClaw coexistence

You can keep OpenClaw running on openclaw.hjacke.com. ZeroClaw uses its own config and data under `appdata/zeroclaw`; the migration only reads from `appdata/openclaw/config` once.
