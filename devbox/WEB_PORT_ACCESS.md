# Accessing Web Ports from Devbox Container

When developing in the devbox container, you need to access HTTP/web ports. Here are the best approaches:

## Option 1: Direct Port Mapping (Simplest for Local Development)

Add port mappings to `compose.yml` for common dev ports:

```yaml
ports:
  - "7681:7681"  # Web terminal (ttyd)
  - "2222:22"    # SSH access
  - "3000:3000"  # Common React/Next.js port
  - "8000:8000"  # Common Python/Django port
  - "8080:8080"  # Common alternative port
  - "5173:5173"  # Vite dev server
  - "4000:4000"  # Jekyll/other
```

**Pros:**
- Simple, direct access
- Works immediately
- No configuration needed

**Cons:**
- Need to add ports manually
- Port conflicts if multiple projects use same port
- Not suitable for production

## Option 2: Traefik Routing (Best for Production-like Setup)

Connect devbox to Traefik network and use labels for automatic routing:

```yaml
networks:
  - devbox-network
  - npm_services  # Traefik network

labels:
  - "traefik.enable=true"
  - "traefik.http.routers.devbox-dev.rule=Host(`dev.localhost`) || Host(`dev.hjacke.com`)"
  - "traefik.http.routers.devbox-dev.entrypoints=websecure"
  - "traefik.http.routers.devbox-dev.tls=true"
  - "traefik.http.routers.devbox-dev.tls.certresolver=letsencrypt"
  - "traefik.http.services.devbox-dev.loadbalancer.server.port=3000"
```

**Pros:**
- Automatic HTTPS with Let's Encrypt
- Can use custom domains
- Production-ready
- Works with your existing Traefik setup

**Cons:**
- Requires domain/DNS setup
- More complex configuration
- Need to change labels per project

## Option 3: SSH Port Forwarding (Flexible, On-Demand)

Forward ports through SSH when needed:

```bash
# Forward local port 3000 to container port 3000
ssh -L 3000:localhost:3000 dev@localhost -p 2222

# Or forward to a specific container/service
ssh -L 3000:service-name:3000 dev@localhost -p 2222
```

**Pros:**
- No compose.yml changes needed
- Flexible, can forward any port
- Works for remote access too
- Can forward multiple ports

**Cons:**
- Need to run SSH command each time
- Connection must stay open
- Less convenient for frequent use

## Option 4: Host Network Mode (Simplest but Less Secure)

Run devbox with host networking:

```yaml
network_mode: host
```

**Pros:**
- All ports automatically accessible
- Simplest setup
- No port mapping needed

**Cons:**
- Less secure (shares host network)
- Can conflict with host services
- Not recommended for production

## Option 5: Dynamic Port Mapping Script

Create a helper script to dynamically map ports:

```bash
#!/bin/bash
# devbox-port-forward.sh
PORT=${1:-3000}
echo "Forwarding port $PORT..."
docker compose -f /path/to/devbox/compose.yml port devbox $PORT
```

## Recommended Approach

**For local development:** Use Option 1 (direct port mapping) for common ports

**For production-like testing:** Use Option 2 (Traefik) with dynamic labels

**For ad-hoc access:** Use Option 3 (SSH port forwarding)

## Example: Adding Common Dev Ports

Add to `devbox` service in `compose.yml`:

```yaml
ports:
  - "7681:7681"  # Web terminal
  - "2222:22"    # SSH
  - "3000:3000"  # React/Next.js
  - "8000:8000"  # Python/Django
  - "8080:8080"  # Alternative
  - "5173:5173"  # Vite
```

Then access via `http://localhost:3000` (or whatever port your app uses).
