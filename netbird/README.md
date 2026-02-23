# Netbird VPN mesh stack

WireGuard-based mesh VPN: management, signal, relay, and embedded STUN in a combined server, with web dashboard. **Routing for netbird.hjacke.com is in `traefik/dynamic/netbird.yml`** (Traefik file provider). Traefik on `npm_services` does TLS.

## Prerequisites

- Traefik on network `npm_services` with entrypoint `websecure` and cert resolver `letsencrypt`
- A hostname (e.g. `netbird.hjacke.com`) pointing to the host where Traefik is reachable
- **UDP 3478** open on the host for STUN (NAT traversal)

## Quick start

1. **Set your domain**  
   If not using `netbird.hjacke.com`, replace it in:
   - `config.yaml`: `server.exposedAddress`, `server.auth.issuer`, `server.auth.dashboardRedirectURIs`
   - `dashboard.env`: `NETBIRD_MGMT_*`, `AUTH_AUTHORITY`  
   Optionally set `NETBIRD_DOMAIN` in `.env` (copy from `.env.example`) so Traefik labels use the same hostname.

2. **Start the stack**
   ```bash
   cd /mnt/user/documents/compose/netbird
   docker compose up -d
   ```

3. **Open the dashboard**  
   Visit `https://<your-domain>` (e.g. `https://netbird.hjacke.com`). First run will create an admin user (embedded IdP).  
   **Fallback:** If the domain doesn’t load, try `http://<server-ip>:8080` (dashboard is also exposed on port 8080). The app will still call the API at `https://<your-domain>`, so the domain must work for login and data.

4. **Add peers**  
   In the dashboard: **Setup keys** → create a key → use it on clients:
   - **Docker client**: `docker run --rm -d --cap-add=NET_ADMIN --cap-add=SYS_ADMIN --cap-add=SYS_RESOURCE -e NB_SETUP_KEY=<KEY> -e NB_MANAGEMENT_URL=https://<your-domain> -v netbird-client:/var/lib/netbird netbirdio/netbird:latest`
   - **Linux/macOS/Windows**: install Netbird from [docs.netbird.io](https://docs.netbird.io) and run with the same setup key and management URL.

## Files

| File            | Purpose                                      |
|-----------------|----------------------------------------------|
| `docker-compose.yml` | Dashboard + netbird-server (no Traefik labels) |
| `../traefik/dynamic/netbird.yml` | Traefik routes for netbird.hjacke.com |
| `config.yaml`   | Server: listen, STUN, auth, store (SQLite)   |
| `dashboard.env` | Dashboard API and OIDC (embedded IdP)        |

## Troubleshooting: dashboard does not load

- **Use the same IP as your other services (e.g. Gitea)**  
  Your Traefik runs on a dedicated IP (e.g. `10.0.0.25`). Ensure `netbird.hjacke.com` (or your domain) resolves to that IP. If netbird.hjacke.com resolves to 10.0.0.25 but gitea.hjacke.com uses 83.255.200.238, point netbird to 83.255.200.238 and add a proxy for netbird in NPM. If it resolves to the host’s main IP, the request may hit another reverse proxy (e.g. Nginx Proxy Manager) that has no route for Netbird.

- **Test via port 8080**  
  Open `http://<server-ip>:8080`. If the dashboard UI loads there but not via the domain, the domain is not reaching the right proxy (see above).

- **Stuck on loading spinner**  
  Open DevTools → Network (F12). Reload and check for failed requests to `/api/...` or `/oauth2/...`. If those return 404/502, Traefik may be sending them to the wrong service; ensure netbird-server routers have **priority=10** and netbird-dashboard has **priority=1** in `docker-compose.yml`.

## Optional: long-lived connections

If gRPC or WebSocket connections drop behind Traefik, consider increasing read timeouts (Traefik v3: `--entrypoints.websecure.transport.respondingTimeouts.readTimeout=0`). Your current Traefik is v2; if you see disconnects, plan for a Traefik upgrade or timeout tuning.

## Backup

- **Data**: volume `netbird_data` (SQLite, setup keys, IdP data). Back up the volume and `config.yaml` before upgrades.
