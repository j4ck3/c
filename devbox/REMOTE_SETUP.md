# code.hjacke.com (devbox-remote)

The **devbox-remote** service exposes the devbox web terminal at **https://code.hjacke.com**. Traefik runs on a **different host** (e.g. Unraid), so the route is defined in **`traefik/dynamic/devbox.yml`** (file provider).

## Prerequisites

- **Traefik** with file provider loading `dynamic/` (e.g. `/mnt/user/documents/compose/traefik/dynamic` on the Traefik host).
- **DNS**: `code.hjacke.com` points to the host where Traefik is reachable (port 443).
- The **Traefik host** can reach the **devbox host** on port **7681** (same LAN or forwarded).

## Setup

### 1. Copy and edit the route on the Traefik host

Ensure **`traefik/dynamic/devbox.yml`** from this repo is present in Traefik’s dynamic config directory on the **Traefik host** (e.g. `/mnt/user/documents/compose/traefik/dynamic/devbox.yml`).

Edit **`devbox.yml`** on the Traefik host:

1. **Backend URL**  
   Replace `DEVBOX_HOST` with the **IP or hostname of the machine running devbox**, as seen from the Traefik host (e.g. `192.168.1.50` or `my-pc.lan`):
   ```yaml
   - url: "http://192.168.1.50:7681"
   ```

2. **BasicAuth**  
   Generate a user and put it in the `users` list:
   ```bash
   docker run --rm httpd:alpine htpasswd -nbB YOUR_USER YOUR_PASSWORD
   ```
   Replace the placeholder in `devbox.yml`:
   ```yaml
   users:
     - "jacke:$apr1$..."
   ```

### 2. Expose port 7681 on the devbox host

On the machine where you run devbox, port **7681** must be reachable from the Traefik host. If devbox is only for local use, you may need to publish the port (e.g. in devbox compose or host firewall). The devbox service already maps `7681:7681` when you use the remote profile.

### 3. Start devbox with the remote profile

```bash
cd devbox
docker compose --profile remote up -d
```

### 4. Reload Traefik

Restart Traefik or rely on its file watcher so it reloads `devbox.yml`.

## Verify

- Open **https://code.hjacke.com** — BasicAuth prompt, then ttyd terminal.
- **404**: Check that `devbox.yml` is in Traefik’s dynamic directory and that the router/service names don’t conflict. Restart Traefik.
- **Connection refused / timeout**: Check that `DEVBOX_HOST` and port 7681 are correct and that the Traefik host can reach the devbox host (firewall, routing).

## Same volumes as local devbox

devbox-remote uses the same **devbox-workspace** and **devbox-home** volumes as the local devbox service.
