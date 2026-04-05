---
name: home-assistant
description: >
  Control Home Assistant via the REST API (lights, vacuum, climate, scripts, automations, scenes).
  Use when the user mentions Home Assistant, HA, smart home, lights, rooms, vacuum/robot,
  sensors, or automating their house. Trigger words: "home assistant", "turn on/off",
  "vacuum", "room", "light", "scene", "automation", "HA".
metadata: {"clawdis":{"emoji":"🏠","requires":{"bins":["curl"]},"primaryEnv":"HA_URL"}}
---

# Home Assistant — REST API from this gateway

## Credentials (already configured — do not ask the user)

This container receives secrets from Varlock at startup. **You already have access.** Do **not** ask the user for a URL or long-lived token unless a request fails with 401 and you have confirmed the deployment is broken.

Use these environment variables in shell commands (they are set for the gateway process and inherited by `exec`):

| Variable | Purpose |
|----------|---------|
| `HA_URL` | Base URL of Home Assistant (no trailing slash), e.g. `http://10.0.0.23:8123` |
| `HA_TOKEN` | Long-lived access token (Bearer) |
| `HOME_ASSISTANT_URL` | Same as `HA_URL` (alias) |
| `HOME_ASSISTANT_TOKEN` | Same as `HA_TOKEN` (alias) |

**Never print, log, or paste token values.** Use `"Authorization: Bearer ${HA_TOKEN}"` or `"Authorization: Bearer ${HOME_ASSISTANT_TOKEN}"` in `curl` only.

Quick check (should return 200 and JSON):

```bash
curl -sS -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer ${HA_TOKEN}" -H "Content-Type: application/json" "${HA_URL}/api/"
```

## Typical API calls

**List entities (states):**

```bash
curl -sS -H "Authorization: Bearer ${HA_TOKEN}" "${HA_URL}/api/states"
```

**Call a service** (replace `light`, `turn_off`, and entity_id):

```bash
curl -sS -X POST -H "Authorization: Bearer ${HA_TOKEN}" -H "Content-Type: application/json" \
  -d '{"entity_id": "light.gaming_room"}' \
  "${HA_URL}/api/services/light/turn_off"
```

**Vacuum — start cleaning a room** (room depends on their setup; often `vacuum.start` with `command` or `segment` — inspect `vacuum.*` entities first):

```bash
curl -sS -H "Authorization: Bearer ${HA_TOKEN}" "${HA_URL}/api/states" | head -c 8000
# find vacuum entity, then e.g.:
curl -sS -X POST -H "Authorization: Bearer ${HA_TOKEN}" -H "Content-Type: application/json" \
  -d '{"entity_id": "vacuum.roborock"}' \
  "${HA_URL}/api/services/vacuum/start"
```

**Render a template** (optional):

```bash
curl -sS -X POST -H "Authorization: Bearer ${HA_TOKEN}" -H "Content-Type: application/json" \
  -d '{"template": "{{ states(\"light.living_room\") }}"}' \
  "${HA_URL}/api/template"
```

## Workflow

1. Load this skill when the task involves Home Assistant.
2. Prefer **REST + curl** from the shell; use **agent-browser** only if the user needs UI interaction or OAuth login (not needed for API token calls).
3. If you do not know the `entity_id`, list `/api/states` and filter (or ask the user for the **friendly name / room** only — not for secrets).
4. On `401 Unauthorized`, say the token may be invalid or the gateway needs a restart after rotating secrets — still do not ask them to paste a token in chat.

## Security

- Tokens are scoped to this host; treat them like passwords.
- Do not store tokens in workspace files; use env vars only.
