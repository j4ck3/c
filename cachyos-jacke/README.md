# cachyos-jacke

Live metrics for the **CachyOS workstation** (i9-14900KS, RX 7900 XTX Merc, rootless Docker) via [Glances](https://github.com/nicolargo/glances).

## Run on the desktop

```bash
cd cachyos-jacke
docker compose up -d
```

## Private URL (Netbird)

After this machine is enrolled in Netbird with hostname `cachyos-jacke`:

- **http://cachyos-jacke.netbird.hjacke.com:61208** (same pattern as `tower.netbird.hjacke.com`)

Access is limited to your Netbird mesh (no Glances login — use Traefik basic auth if you expose `cachyos.hjacke.com`).

Enroll (one-time):

```bash
sudo netbird up \
  --management-url https://netbird.hjacke.com/ \
  --setup-key '<from Netbird dashboard or tower netbird .env>' \
  --hostname cachyos-jacke
netbird status   # confirm FQDN
```

## Optional HTTPS (Traefik on tower)

`traefik/dynamic/cachyos-jacke.yml` exposes **https://cachyos.hjacke.com** → this host’s Glances port (LAN or via Netbird IP). Add DNS `cachyos.hjacke.com` → Traefik (10.0.0.25) if you use it.

## Dockhand

Point Dockhand at this host’s Docker API (`dotfiles/docker/README.md`) using the machine’s **Netbird IP** and port **2375** when TCP listener is enabled.
