# Gitea behind reverse proxy (gitea.hjacke.com)

Gitea is served via **Traefik** at **https://gitea.hjacke.com**. DNS for `gitea.hjacke.com` points to your **public IP**; the router forwards ports 80/443 to Traefik (10.0.0.25).

## 1. Router / firewall

Forward these ports from your public IP to **Traefik** (10.0.0.25):

| External (router) | Forward to        | Purpose                    |
|-------------------|-------------------|----------------------------|
| TCP 22            | 10.0.0.25:22      | **Git over SSH** (clone/push) |
| TCP 80            | 10.0.0.25:80      | HTTP → HTTPS + ACME challenge |
| TCP 443           | 10.0.0.25:443     | HTTPS (Gitea, registry)    |

**Git over SSH (from tower/host):** Gitea’s SSH is on **host port 2222**. On the tower, `/etc/hosts` has `127.0.0.1 gitea.hjacke.com`, so use the URL **with port 2222**:

- Clone: `git clone git@gitea.hjacke.com:2222/j4ck3/mammas-hemsida.git`
- Remote: `git remote set-url origin git@gitea.hjacke.com:2222/j4ck3/mammas-hemsida.git`

Add your SSH public key in Gitea: **Settings → SSH / GPG Keys**. For access from outside the tower, forward router **TCP 2222** to **tower IP:2222**.

**If you get "Internal Server Connection Error" on pull/push:** add keepalives and (if you use LFS) try skipping LFS once to see if LFS is the cause:
- In `~/.ssh/config` for `Host gitea.hjacke.com` add:
  ```
  ServerAliveInterval 30
  ServerAliveCountMax 6
  ```
- Test without LFS: `GIT_LFS_SKIP_SMUDGE=1 git pull origin master`. If that works, the problem is likely LFS (e.g. LFS over HTTPS failing); you can keep using `GIT_LFS_SKIP_SMUDGE=1` for pulls or fix LFS URL/auth.

For the **runner** (on the same host) to reach the registry at `gitea.hjacke.com`, the host will connect to your **public IP**. The router must support **NAT hairpinning** (same-LAN device connecting to public IP and being forwarded back). If your router does not support it, see “Fallback: registry on localhost” below.

## 2. Variables and secrets to set

### Gitea repo secrets (Settings → Secrets and Variables → Actions)

| Secret             | Value              | Notes                                      |
|--------------------|--------------------|--------------------------------------------|
| **REGISTRY**       | `127.0.0.1:3002`   | So the host's Docker daemon reaches Gitea (avoids 404 on /v2/ when using gitea.hjacke.com:80) |
| **REGISTRY_USERNAME** | Your Gitea username | Or a bot/user for automation               |
| **REGISTRY_PASSWORD** | Gitea password or PAT | Use PAT if 2FA is enabled              |

### Workflow: use HTTP for 127.0.0.1:3002

With **REGISTRY=127.0.0.1:3002**, keep the **config-inline** in the “Set up Docker Buildx” step so Docker uses HTTP and accepts the insecure registry:

```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3
  with:
    config-inline: |
      [registry."${{ secrets.REGISTRY }}"]
        http = true
        insecure = true
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

- **GITEA_REGISTRY** = `127.0.0.1:3002` (so jobs can use `${{ env.GITEA_REGISTRY }}`; matches REGISTRY secret).

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
