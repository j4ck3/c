# Netdata

Real-time system and container monitoring with 1-second granularity. Automatically discovers Docker containers, databases, web servers, and 800+ services.

Based on [Learn Netdata: Install with Docker](https://learn.netdata.cloud/docs/netdata-agent/installation/docker).

## Features

- Per-container CPU, memory, network, and disk metrics
- Host system monitoring (CPU, memory, disks, network)
- Machine learning-powered anomaly detection
- Low overhead (<1% CPU)
- Built-in alerting

## Access

| Method | URL |
|--------|-----|
| Direct (host network) | http://HOST_IP:19999 |
| Via Traefik (HTTPS) | https://netdata.hjacke.com |

Ensure DNS for `netdata.hjacke.com` points to your Traefik host (10.0.0.25). Traefik proxies to `host.docker.internal:19999`.

## Quick start

```bash
cd /mnt/user/documents/compose/netdata
docker compose up -d
```

First run creates `/mnt/user/appdata/netdata` for persistent config.

## Configuration

- **Config**: `/mnt/user/appdata/netdata/` — edit `netdata.conf` for bind address, retention, etc.
- **Hostname**: Set `NETDATA_HOSTNAME` in `.env` or leave default `netdata`.
- **Timezone**: Uses `TZ=Europe/Stockholm` (inherited from compose).

To edit config:
```bash
docker exec -it netdata bash
cd /etc/netdata
./edit-config netdata.conf
# Restart to apply: docker compose restart
```

## Requirements

- Docker Engine 20.10+
- Port 19999 available on host
- 512MB RAM minimum (1GB+ recommended)
- Traefik with `extra_hosts: host.docker.internal:host-gateway` (already in your traefik compose)

## Optional: Netdata Cloud

Connect to [Netdata Cloud](https://app.netdata.cloud) for multi-node dashboards and alerting. Use "Add Nodes" in your Space to get the connection command with the right parameters.
