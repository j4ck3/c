# Music Assistant

Self-hosted music library manager. Streams to players (Chromecast, AirPlay, etc.) and can merge local files with Plex, Spotify, and other providers.

- **Web UI:** `http://<host-ip>:8095` (stream port 8097)
- **Music directory (host):** `/mnt/user/music` → **in container:** `/music`
- **Podcasts directory (host):** `/mnt/user/podcasts` → **in container:** `/podcasts`

## First run

1. Create data dir (optional; Docker will create it):  
   `mkdir -p /mnt/user/appdata/music-assistant/data`
2. Start:  
   `docker compose -f /mnt/user/documents/compose/music-assistant/compose.yml up -d`
3. Open `http://<your-server-ip>:8095`.

## Connect your library

In the Music Assistant UI go to **Settings → Music providers** and add:

1. **Local files** – add two providers (or one per path):
   - Path: `/music` (your main music library)
   - Path: `/podcasts` (your podcasts)
2. **Plex** (optional) – if you use Plex for music, add the Plex provider with your Plex URL and token so MA can use the same library.
3. **Spotify / others** (optional) – add any other providers you use.

Same paths are used by:

- **Plex** – `/mnt/user/music`, `/mnt/user/podcasts`
- **music-helpers** – Picard, Soulify, Your Spotify use the same dirs

## Reverse proxy (Traefik)

Music Assistant uses **host network** and listens on port **8095**. To put it behind Traefik you need a route that targets the host (e.g. `host.docker.internal:8095`). If your Traefik runs on the same host, add `extra_hosts: - "host.docker.internal:host-gateway"` to the Traefik service and define an HTTP router/service in `traefik/dynamic/` that forwards to `http://host.docker.internal:8095`.

## Notes

- Host network is required for player discovery (mDNS/uPnP) and streaming.
- First sync of a large library can take a while; the UI shows progress.
- [Official installation docs](https://www.music-assistant.io/installation/)
