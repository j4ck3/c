# Gitea behind reverse proxy (gitea.hjacke.com)

Gitea is served via **Traefik** at **https://gitea.hjacke.com**. DNS for `gitea.hjacke.com` points to your **public IP**; the router forwards ports 80/443 to Traefik (10.0.0.25).

## 1. Router / firewall

Forward these ports from your public IP to **Traefik** (10.0.0.25):

| External (router) | Forward to        | Purpose                    |
|-------------------|-------------------|----------------------------|
| TCP 443           | 10.0.0.25:443     | HTTPS (Gitea, registry)    |
| TCP 80            | 10.0.0.25:80      | HTTP → HTTPS + ACME challenge |
| TCP 22 (optional) | 10.0.0.25:22      | Git over SSH               |

For the **runner** (on the same host) to reach the registry at `gitea.hjacke.com`, the host will connect to your **public IP**. The router must support **NAT hairpinning** (same-LAN device connecting to public IP and being forwarded back). If your router does not support it, see “Fallback: registry on localhost” below.

## 2. Variables and secrets to set

### Gitea repo secrets (Settings → Secrets and Variables → Actions)

| Secret             | Value              | Notes                                      |
|--------------------|--------------------|--------------------------------------------|
| **REGISTRY**       | `gitea.hjacke.com` | No `https://`, no port, no trailing slash  |
| **REGISTRY_USERNAME** | Your Gitea username | Or a bot/user for automation               |
| **REGISTRY_PASSWORD** | Gitea password or PAT | Use PAT if 2FA is enabled              |

### Workflow: use HTTPS (no insecure registry)

With the registry at `gitea.hjacke.com` over HTTPS, **remove** the `config-inline` block from the “Set up Docker Buildx” step so Docker uses HTTPS:

```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3
  # For HTTPS registry (gitea.hjacke.com), do NOT use config-inline with http = true
```

Keep the login step using the secret:

```yaml
- name: Login to Gitea Container Registry
  uses: docker/login-action@v3
  with:
    registry: ${{ secrets.REGISTRY }}
    username: ${{ secrets.REGISTRY_USERNAME }}
    password: ${{ secrets.REGISTRY_PASSWORD }}
```

### Runner env (already in `runner-config.yaml`)

- **GITEA_REGISTRY** = `gitea.hjacke.com` (so jobs can use `${{ env.GITEA_REGISTRY }}` if you prefer that over the secret).

## 3. Gitea / Traefik config (already set)

- **ROOT_URL** = `https://gitea.hjacke.com/` (Gitea env `GITEA__server__ROOT_URL`)
- **DOMAIN** = `gitea.hjacke.com` (Gitea env `GITEA__server__DOMAIN`)
- Traefik routes `Host(`gitea.hjacke.com`)` to the Gitea container (Docker labels on `server`), TLS via Let’s Encrypt.

No `LOCAL_ROOT_URL` is set in compose; the registry token URL is `https://gitea.hjacke.com/v2/token`. If you previously had `LOCAL_ROOT_URL` in Gitea’s config (e.g. in Admin → Configuration or `custom/conf/app.ini` in the data volume), remove it so the registry uses the public URL.

## 4. After changing config

1. Restart Gitea: `docker compose -f gitea/docker-compose.yml up -d server`
2. Restart runner: `docker compose -f gitea/docker-compose.yml restart runner`
3. In the repo, set **REGISTRY** secret to `gitea.hjacke.com` and remove the Buildx `config-inline` (HTTP/insecure) block from the workflow, then re-run the job.

## 5. Fallback: registry on localhost (no NAT hairpin)

If the runner host **cannot** reach `gitea.hjacke.com` (e.g. router does not support NAT hairpin):

1. In **runner-config.yaml** set `GITEA_REGISTRY: 127.0.0.1:3002`.
2. In Gitea **docker-compose.yml** add back:  
   `GITEA__server__LOCAL_ROOT_URL=http://127.0.0.1:3002/`
3. On the **host** Docker daemon, add `"insecure-registries": ["127.0.0.1:3002"]` and restart Docker.
4. In the repo, set **REGISTRY** secret to `127.0.0.1:3002` and keep the Buildx `config-inline` with `http = true` for that registry.
