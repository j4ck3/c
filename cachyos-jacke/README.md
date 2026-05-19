# cachyos-jacke — Netdata (Netbird only)

Host monitoring for the gaming desktop (i9-14900KS, RX 7900 XTX). **Not** exposed on the public web.

## Run

```bash
cd cachyos-jacke
docker compose up -d
```

Optional — restrict port **19999** to the Netbird mesh (recommended):

```bash
sudo bash install-netbird-firewall.sh
```

## Private URL (Netbird)

Peer must be enrolled with DNS enabled (`netbird status` shows an FQDN):

**http://cachyos-jacke.netbird.hjacke.com:19999**

Only devices on your Netbird mesh can resolve that name and reach the agent (plus apply the firewall script to block LAN).

## Verify

```bash
docker compose ps
curl -s http://127.0.0.1:19999/api/v1/info | head
netbird status
```

## Remove Glances

The old Glances stack in this folder was removed; use Netdata only.
