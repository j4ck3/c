# GitLab Runners

Three GitLab runners for GitLab.com, using the Docker executor.

## Runner 3 registration

After starting the stack, register runner 3 (one-time):

```bash
cd gitlab-runner
docker compose run --rm gitlab-runner-3 gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.com" \
  --token "${GITLAB_RUNNER_3_TOKEN}" \
  --executor "docker" \
  --docker-image alpine:latest \
  --description "gitlab-runner-3"
```

Or with the token inline:

```bash
docker compose run --rm gitlab-runner-3 gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.com" \
  --token "glrt-yERrDoAinureazPltS9XSG86MQpwOjFiZ3gzdwp0OjMKdTpqZXE0bxg.01.1j0mmh170" \
  --executor "docker" \
  --docker-image alpine:latest \
  --description "gitlab-runner-3"
```

Start the runner:

```bash
docker compose up -d gitlab-runner-3
```

## ARM runner (this machine only)

On this ARM machine, run **only** the ARM runner (not the full stack):

```bash
cd gitlab-runner
docker compose -f compose.arm.yml up -d
```

Start the runner:

```bash
docker compose -f compose.arm.yml up -d gitlab-runner-arm
```

**CI jobs using host Docker (no dind):** The ARM runner config in `config-arm/config.toml` mounts the Docker socket and hemsida-mammas at `/deploy`:

```toml
[runners.docker]
  volumes = ["/var/run/docker.sock:/var/run/docker.sock", "/home/ubuntu/c/hemsida-mammas:/deploy"]
```

Edit `config-arm/config.toml` to change volumes or the token.

### Docker Buildx layer cache (registry)

The runner uses the host Docker socket, so builds run on the host daemon. For registry-based layer cache (`--cache-from` / `--cache-to` to `$CI_REGISTRY_IMAGE:buildcache`):

1. **Runner config** – Already correct: Docker socket is mounted, and `docker login` in the job authenticates the host daemon over the socket so buildx can push/pull cache.

2. **`.gitlab-ci.yml`** – Ensure this order in the build job:

```yaml
build:
  image: docker:26-cli
  # No dind service – jobs use the host Docker via the mounted socket
  variables:
    DOCKER_HOST: unix:///var/run/docker.sock
  before_script:
    - docker login -u "$CI_REGISTRY_USER" -p "$CI_REGISTRY_PASSWORD" "$CI_REGISTRY"
  script:
    - docker buildx build
        --cache-from type=registry,ref=$CI_REGISTRY_IMAGE:buildcache
        --cache-to type=registry,ref=$CI_REGISTRY_IMAGE:buildcache,mode=max
        --load -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHA .
```

3. **Cache persistence** – Cache is stored in the registry image `...:buildcache`, so it survives across jobs and pipelines. No extra runner volumes are needed.

4. **`pull_policy`** – Set to `if-not-present` so job images (e.g. `docker:26-cli`) are reused across runs.

## Ports

| Runner           | Host port |
|------------------|-----------|
| gitlab-runner-1  | 8093      |
| gitlab-runner-2  | 8094      |
| gitlab-runner-3  | 8096      |
| gitlab-runner-arm| 8097      |
