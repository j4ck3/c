# Docker Contexts for Remote Hosts

This document explains how to set up Docker contexts to connect to external Docker hosts from the devbox container.

## Overview

The devbox container uses Docker-in-Docker (DinD) by default for local development. You can also connect to external Docker hosts (e.g., production, staging servers) using Docker contexts.

## Default: Docker-in-Docker

By default, the devbox uses Docker-in-Docker (DinD) running as a sibling container:
- **Endpoint**: `tcp://dind:2375`
- **Purpose**: Local development, building images, running containers
- **Isolation**: Full isolation from host Docker daemon

## Setting Up External Docker Contexts

To connect to external Docker hosts, create Docker contexts inside the devbox container.

### Method 1: SSH Connection (Recommended)

Connect to remote hosts via SSH:

```bash
# Inside devbox container
docker context create host1 --docker "host=ssh://user@host1.example.com"

# With custom SSH key
docker context create host1 --docker "host=ssh://user@host1.example.com" --description "Production server"
```

### Method 2: TCP Connection

Connect to remote hosts via TCP (requires Docker daemon exposed on network):

```bash
# With TLS
docker context create host1 --docker "host=tcp://host1.example.com:2376,tls=true"

# Without TLS (less secure, but simpler for Tailscale/internal networks)
docker context create host1 --docker "host=tcp://host1.example.com:2375"
```

#### Tailscale Example

For Tailscale hosts on your private network:

```bash
# Tower server
docker context create tower --docker "host=tcp://100.109.213.78:2375" --description "Tower server via Tailscale"

# Instance server
docker context create instance-20251201-2024 --docker "host=tcp://100.71.3.26:2375" --description "Instance server via Tailscale"
```

**Note:** Ensure Docker daemon on remote hosts is listening on port 2375 (or 2376 for TLS). You may need to configure Docker daemon on those machines to accept remote connections.

### Method 3: Docker Desktop/Remote

Connect to Docker Desktop or remote Docker instances:

```bash
docker context create desktop --docker "host=tcp://192.168.1.100:2375"
```

## Quick Setup Script

A helper script is provided at `/usr/local/bin/setup-docker-contexts.sh` (when mounted) or run manually:

```bash
# Inside devbox container
bash /path/to/setup-docker-contexts.sh
```

## Using Contexts

### List Available Contexts

```bash
docker context ls
```

You'll see:
- `default` - Default context (not used, DinD is default)
- `Docker-in-Docker (Local)` - Built-in DinD option
- Your custom contexts (tower, instance-20251201-2024, etc.)

### Select Context When Starting Session

When you open a new browser tab/session:
1. Select your project (existing flow)
2. Select Docker connection:
   - **Docker-in-Docker (Local)** - For development
   - **tower** - Your Tailscale tower server
   - **instance-20251201-2024** - Your Tailscale instance server
   - etc.

The selected context will be used for all Docker commands in that session.

### Switch Context in Running Session

If you need to switch contexts within a session:

```bash
# Use Docker context
docker context use tower

# Or set DOCKER_HOST directly
export DOCKER_HOST=tcp://100.109.213.78:2375

# Verify connection
docker ps
```

## Example: Setting Up Tailscale Hosts

For your Tailscale network:

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

# Now when you start a new session, you'll see:
# - Docker-in-Docker (Local)
# - tower
# - instance-20251201-2024
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

**Security Note:** This exposes Docker on port 2375. Since you're using Tailscale (private network), this is acceptable, but ensure only Tailscale hosts can reach these IPs.

For production, use TLS (port 2376) or SSH-based contexts.

## Persisting Contexts

Docker contexts are stored in `/home/dev/.docker/config.json` and persist across container restarts (stored in `devbox-home` volume).

To make contexts available to all containers, they should be set up inside the devbox container, not on the host.

## Security Notes

- **SSH connections**: More secure, uses SSH key authentication
- **TCP connections**: Less secure, expose Docker daemon on network
  - **Tailscale**: Acceptable for private Tailscale network
  - **Public network**: Use TLS (2376) or SSH instead
- **TLS**: Always use TLS when connecting via TCP in production
- **Contexts**: Contexts are stored in `/home/dev/.docker/config.json` - ensure this is secure

## Troubleshooting

### Context not appearing in menu

- Ensure context is created: `docker context ls`
- Check if context has valid endpoint: `docker context inspect <context-name>`

### Cannot connect to remote host

**For Tailscale TCP connections:**
- Verify Tailscale connectivity: `ping 100.109.213.78` from devbox container
- Check Docker daemon is running on remote host: `ssh user@100.109.213.78 'systemctl status docker'`
- Verify Docker is listening on port 2375: `ssh user@100.109.213.78 'netstat -tlnp | grep 2375'`
- Test connection: `docker -H tcp://100.109.213.78:2375 ps`
- Check firewall rules on remote host (should allow port 2375)

**For SSH connections:**
- Verify SSH access: `ssh user@host`
- Check Docker daemon is running on remote host
- Verify network connectivity from devbox container

### DinD not working

- Check DinD service is running: `docker ps | grep dind`
- Verify network connectivity: `ping dind` from devbox container
- Check DOCKER_HOST: `echo $DOCKER_HOST` should be `tcp://dind:2375`

## Reference

- [Docker Context Documentation](https://docs.docker.com/engine/context/working-with-contexts/)
- [Docker-in-Docker](https://github.com/docker-library/docker/blob/master/dind/README.md)
- [Tailscale Documentation](https://tailscale.com/kb/)