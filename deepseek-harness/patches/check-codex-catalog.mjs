import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { readFileSync } from 'node:fs';
import { normalizeCatalog } from './refresh-codex-catalog.mjs';
const root = `${process.env.DSH_HOME ?? '/home/t3/.dsh'}/profiles/web/node_modules/dsh-codex-oauth`;
const { createModels } = await import(pathToFileURL(`${root}/node_modules/@earendil-works/pi-ai/dist/index.js`));
const { openaiCodexProvider } = await import(pathToFileURL(`${root}/node_modules/@earendil-works/pi-ai/dist/providers/openai-codex.js`));
const { CodexAdapter } = await import(pathToFileURL(`${root}/lib/adapter.js`));
const models = createModels();
models.setProvider(openaiCodexProvider());
const adapter = new CodexAdapter(models, 'codex', {});
const listed = await adapter.listModels('codex');
assert(listed.some(model => model.id === 'gpt-6.1-sol'), 'gpt-6.1-sol missing from real Codex adapter');
const cached = normalizeCatalog(JSON.parse(readFileSync(`${process.env.DSH_HOME ?? '/home/t3/.dsh'}/model-catalog/openai-codex.json`, 'utf8')));
for (const id of Object.keys(cached['openai-codex-responses'])) {
  assert(listed.some(model => model.id === id), `${id} absent from adapter`);
  assert.equal((await adapter.resolveModel('codex', id)).id, id);
}
assert.deepEqual(Object.keys(normalizeCatalog({ 'openai-codex-responses': {
  'chat:example': { id: 'example', name: 'Example', type: 'chat', provider: 'openai-codex', api: 'openai-codex-responses', input: ['text'], contextWindow: 100, maxTokens: 10 },
} })['openai-codex-responses']), ['example']);
assert.throws(() => normalizeCatalog({}), /Empty/);
console.log(`PASS: ${listed.length} Codex models list and resolve, including gpt-6.1-sol; new catalog keys normalized`);
