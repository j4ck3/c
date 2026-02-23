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

Then start the runner:

```bash
docker compose up -d gitlab-runner-3
```

## Ports

| Runner           | Host port |
|------------------|-----------|
| gitlab-runner-1  | 8093      |
| gitlab-runner-2  | 8094      |
| gitlab-runner-3  | 8096      |
