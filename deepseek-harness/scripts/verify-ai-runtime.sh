#!/usr/bin/env bash
set -euo pipefail

container="${DSH_CONTAINER:-deepseek-harness}"
docker exec -i "${container}" node - <<'NODE'
const fs = require('node:fs');
const assert = require('node:assert/strict');
const root = '/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@earendil-works/pi-ai/dist/providers/data';
const openrouter = JSON.parse(fs.readFileSync(`${root}/openrouter.json`, 'utf8'));
const codexPath = `${process.env.DSH_HOME}/profiles/web/node_modules/dsh-codex-oauth/node_modules/@earendil-works/pi-ai/dist/providers/data/openai-codex.json`;
const codex = JSON.parse(fs.readFileSync(codexPath, 'utf8'));
function modelIn(catalog, id) {
  if (catalog && typeof catalog === 'object') {
    if (catalog.id === id) return catalog;
    for (const value of Object.values(catalog)) {
      const found = modelIn(value, id);
      if (found) return found;
    }
  }
}
for (const id of ['xiaomi/mimo-v2.5', 'xiaomi/mimo-v2.6-flash', 'xiaomi/mimo-v2.6-pro']) {
  const model = modelIn(openrouter, id);
  assert.ok(model, `OpenRouter catalog is missing ${id}`);
  assert.ok(model.input?.includes('image'), `${id} should advertise image input`);
}
for (const id of ['gpt-6-astra', 'gpt-6-luna', 'gpt-6-sol']) {
  assert.ok(modelIn(codex, id), `Codex OAuth catalog is missing ${id}`);
}
console.log('OpenRouter multimodal and Codex GPT-6 catalogs: OK');
NODE

docker exec "${container}" curl -fsS --max-time 2 http://127.0.0.1:8788/readyz >/dev/null
echo 'Headroom provider proxy: ready'
