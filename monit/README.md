# Monitoring Stack

Complete monitoring solution with Prometheus, Grafana, Loki, and Promtail for metrics and log aggregation.

## Services

- **Prometheus** (v2.51.0) - Metrics collection and storage
  - Port: 9494 (internal: 9090)
  - Access: http://localhost:9494

- **Grafana** (v11.5.2) - Visualization and dashboards
  - Port: 3020 (internal: 3000)
  - Web: https://monit.hjacke.com
  - Default login: admin/admin (change on first login!)

- **Loki** (v3.0.0) - Log aggregation
  - Port: 3100
  - Access: http://localhost:3100

- **Promtail** (v3.0.0) - Log shipper
  - Collects logs from backup system and Docker containers

- **Node Exporter** (v1.9.0) - System metrics
  - Exposes host metrics to Prometheus

- **cAdvisor** (v0.51.0) - Container metrics
  - Port: 8484
  - Access: http://localhost:8484

## Access

### Grafana Dashboard
- **URL**: https://monit.hjacke.com
- **Default credentials**: admin/admin (change immediately!)
- **Data sources**: Automatically configured (Prometheus & Loki)

### Backup Logs Dashboard

The backup monitoring dashboard should be available in Grafana. If it doesn't appear automatically:

1. Login to Grafana
2. Go to Dashboards → Import
3. The dashboard file is at: `/mnt/user/appdata/grafana/provisioning/dashboards/backup-monitoring.json`
4. Or create a new dashboard and use these queries:

**Backup Logs Panel:**
```
{job="backup"}
```

**Success Count:**
```
count_over_time({job="backup", level="SUCCESS"}[5m])
```

**Error Count:**
```
count_over_time({job="backup", level="ERROR"}[5m])
```

**Recent Errors:**
```
{job="backup", level="ERROR"}
```

## Log Sources

Promtail is configured to collect:
- **Backup logs**: `/mnt/user/backups/logs/*.log`
- **Docker container logs**: All running containers

## Data Retention

- **Loki**: 30 days (720 hours)
- **Prometheus**: 15 days (default)

## Configuration Files

- Loki config: `/mnt/user/appdata/loki/config/loki-config.yaml`
- Promtail config: `/mnt/user/appdata/promtail/config/promtail-config.yaml`
- Grafana datasources: `/mnt/user/appdata/grafana/provisioning/datasources/datasources.yaml`
- Grafana dashboards: `/mnt/user/appdata/grafana/provisioning/dashboards/`

## Commands

```bash
cd /mnt/user/documents/compose/monit

# Start all services
docker compose up -d

# View logs
docker compose logs -f grafana
docker compose logs -f loki
docker compose logs -f promtail

# Restart a service
docker compose restart grafana

# Check status
docker compose ps
```

## Troubleshooting

### Dashboard not showing
- Check Grafana logs: `docker compose logs grafana | grep dashboard`
- Manually import the dashboard JSON from the provisioning directory
- Or create dashboard via Grafana UI using the queries above

### No backup logs in Loki
- Check Promtail is reading logs: `docker compose logs promtail | grep backup`
- Verify log files exist: `ls -la /mnt/user/backups/logs/`
- Check Loki is receiving data: `curl http://localhost:3100/loki/api/v1/labels`

### Grafana not accessible via domain
- Check Traefik labels are applied: `docker inspect grafana | grep traefik`
- Verify Traefik is running and can see the container
- Check DNS points to your server
