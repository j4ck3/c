# cachyos-jacke — Netdata (Netbird only)

Host monitoring for the gaming desktop. **Not** exposed on the public web.

## Run

```bash
docker compose up -d
```

## Private URL (Netbird)

**http://cachyos-jacke.netbird.hjacke.com:19999**

Requires `netbird status` → Management: Connected, with DNS enabled.

## Verify

```bash
docker compose ps
curl -s http://127.0.0.1:19999/api/v1/info | head
netbird status
```
