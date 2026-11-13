# Codex model discovery

## Root cause

The Codex OAuth plugin discovers models from pi-ai's bundled metadata, not from the subscription's live model list. The image previously pinned metadata to pi-ai 0.87.1 and copied that snapshot into the persistent plugin at every startup. That snapshot did not contain `gpt-6.1-sol`.

## Deployed fix

- The image contains a normalized pi-ai 0.99.1 Codex fallback.
- `patches/refresh-codex-catalog.mjs` fetches the latest published pi-ai metadata at startup, with a 24-hour cache under `$DSH_HOME/model-catalog`.
- Only metadata is updated; the harness and SDK runtimes remain pinned.
- New `chat:<id>` catalog keys are converted to bare IDs required by the older SDK.
- Failed downloads warn and retain cached metadata or the image fallback.
- `patches/check-codex-catalog.mjs` exercises the real adapter's list and resolution methods, including `gpt-6.1-sol` and every cached model ID. It does not make inference requests or verify subscription entitlement.

## Future models

The running provider loads its catalog into memory at startup. This fix does not provide live discovery. Restart the harness after new models are published in pi-ai metadata; no image rebuild is required. A browser refresh alone cannot update server-side metadata.

To force a catalog refresh, then restart:

```sh
docker exec -u 1000 deepseek-harness node /opt/dsh/patches/refresh-codex-catalog.mjs --force
docker restart deepseek-harness
# After startup completes:
docker exec -u 1000 deepseek-harness node /opt/dsh/patches/check-codex-catalog.mjs
```

Run the refresh as UID 1000, not root, to preserve writable ownership of catalog/cache files.

## Rebuild

From `/mnt/user/documents/compose/deepseek-harness`:

```sh
docker build -t deepseek-harness:local .
docker compose up -d --no-build --no-deps deepseek-harness
```

At deployment, `docker compose build` failed because tower's buildx was older than Compose required; direct `docker build` succeeded.

## Verification after resuming

The deployed container was healthy with zero restarts. The real Codex adapter listed and resolved nine models, including `gpt-6.1-sol`. The web endpoint responded with its expected authentication-required HTTP 401. Browser rendering and model inference were not tested.
