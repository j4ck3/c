# Komodo in Docker Compose

[Komodo](https://github.com/moghtech/komodo) – build and deploy software across many servers.

- **Docs:** https://komo.do  
- **Demo:** https://demo.komo.do (`demo` / `demo`)

## Quick start

### Option 1: One-shot setup (clone + build + run)

```bash
cd /home/ubuntu/c/komodo
chmod +x setup.sh
./setup.sh
```

This clones the Komodo repo into `./app` and runs `docker compose up -d --build`.

### Option 2: Manual

```bash
cd /home/ubuntu/c/komodo
git clone --depth 1 https://github.com/moghtech/komodo.git app
cp .env.example .env
# Edit .env and set KOMODO_JWT_SECRET for production
docker compose up -d --build
```

## Access

- **Web UI:** http://localhost:9120

New users are allowed by default (`KOMODO_ENABLE_NEW_USERS=true`). For production, set a strong `KOMODO_JWT_SECRET` in `.env`.

## Services

| Service   | Role                          | Port |
|----------|--------------------------------|------|
| core     | Web UI + API                   | 9120 |
| periphery| Agent on host (Docker, repos)   | -    |
| ferretdb | MongoDB-compatible DB (SQLite) | -    |

Periphery mounts the host Docker socket and `/proc` so Komodo can manage stacks on the host.

## Volumes

- `ferretdb-data` – database
- `repo-cache` – clone cache
- `repos` – managed repos
- `stacks` – stack definitions

## 504 Gateway Timeout (Traefik on another host)

If Komodo runs on a **different machine** than Traefik (e.g. Komodo on Ubuntu, Traefik on Unraid), Traefik cannot reach the Komodo container via Docker. Use the **file provider** instead:

1. On the **Traefik host**, ensure `traefik/dynamic/komodo.yml` is in Traefik’s dynamic config directory (e.g. copy from this repo or sync).
2. In `komodo.yml`, replace `KOMODO_HOST` with the **IP or hostname** of the machine running Komodo (as seen from the Traefik host), e.g. `192.168.1.100` or `komodo.lan`.
3. Ensure the Komodo host allows **inbound TCP 9120** from the Traefik host (firewall/LAN).
4. Reload Traefik or wait for it to pick up the file.

Then `https://komodo.hjacke.com` will be proxied to `http://KOMODO_HOST:9120`.

## Commands

```bash
docker compose up -d --build   # build and start
docker compose down            # stop
docker compose logs -f core    # follow core logs
```
