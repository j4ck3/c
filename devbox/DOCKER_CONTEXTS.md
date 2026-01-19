```bash
# Inside devbox container

# Tower (100.109.213.78)
docker context create tower --docker "host=tcp://100.109.213.78:2375" --description "Tower server via Tailscale"

# Instance (100.71.3.26)
docker context create instance-20251201-2024 --docker "host=tcp://100.71.3.26:2375" --description "Instance server via Tailscale"

# Test instance
docker -H tcp://100.71.3.26:2375 ps

# Test tower (once configured)
docker -H tcp://100.109.213.78:2375 ps

# List contexts
docker context ls
```

## Configuring Docker Daemon on Remote Hosts (Tailscale)

To allow Docker connections from Tailscale, configure Docker daemon on your remote hosts:

**On tower and instance-20251201-2024:**

1. Edit Docker daemon configuration:
   ```bash
   sudo nano /etc/docker/daemon.json
   ```

2. Add or update to include:
   ```json
   {
     "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"]
   }
   ```

3. Restart Docker:
   ```bash
   sudo systemctl restart docker
   ```

4. Verify Docker is listening:
   ```bash
   sudo netstat -tlnp | grep 2375
   # Should show: tcp 0.0.0.0:2375 LISTEN
   ```
