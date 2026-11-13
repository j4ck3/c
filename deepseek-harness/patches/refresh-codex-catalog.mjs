import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync, renameSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// Update metadata only: do not replace the harness's pinned pi-ai runtime.
export function normalizeCatalog(raw) {
  const models = Object.values(raw['openai-codex-responses'] ?? {});
  if (!models.length) throw new Error('Empty Codex model catalog');
  const normalized = {};
  for (const model of models) {
    if (model.type && model.type !== 'chat') continue;
    if (typeof model.id !== 'string' || !model.id || model.provider !== 'openai-codex'
        || model.api !== 'openai-codex-responses' || typeof model.name !== 'string'
        || !Array.isArray(model.input) || !(model.contextWindow > 0) || !(model.maxTokens > 0)) {
      throw new Error('Unsupported Codex model metadata');
    }
    // New catalogs key by "chat:id"; the pinned SDK resolves by bare ID.
    normalized[model.id] = model;
  }
  if (!Object.keys(normalized).length) throw new Error('No chat models in Codex catalog');
  return { 'openai-codex-responses': normalized };
}

function atomicWrite(path, data) {
  writeFileSync(`${path}.tmp`, data);
  renameSync(`${path}.tmp`, path);
}

export function refresh() {
  const home = process.env.DSH_HOME ?? '/home/t3/.dsh';
  const cacheDir = join(home, 'model-catalog');
  mkdirSync(cacheDir, { recursive: true });
  const cache = join(cacheDir, 'openai-codex.json');
  const stamp = join(cacheDir, 'openai-codex-refresh.json');
  let last = {};
  try { last = JSON.parse(readFileSync(stamp, 'utf8')); } catch {}
  let catalog;
  try { catalog = normalizeCatalog(JSON.parse(readFileSync(cache, 'utf8'))); } catch {}
  if (!catalog || process.argv.includes('--force') || Date.now() - (last.checkedAt ?? 0) > 86400000) {
    const dir = mkdtempSync(join(tmpdir(), 'dsh-codex-catalog-'));
    try {
      const output = execFileSync('npm', ['pack', '@earendil-works/pi-ai@latest', '--json', '--pack-destination', dir],
        { encoding: 'utf8', timeout: 60000, stdio: ['ignore', 'pipe', 'pipe'] });
      const [pack] = JSON.parse(output);
      execFileSync('tar', ['-xzf', join(dir, pack.filename), '-C', dir,
        'package/dist/providers/data/openai-codex.json'], { timeout: 10000 });
      catalog = normalizeCatalog(JSON.parse(readFileSync(join(dir, 'package/dist/providers/data/openai-codex.json'), 'utf8')));
      atomicWrite(cache, JSON.stringify(catalog));
      atomicWrite(stamp, JSON.stringify({ version: pack.version, checkedAt: Date.now() }));
      console.log(`deepseek-harness: refreshed Codex catalog from pi-ai ${pack.version}`);
    } catch {
      // Never log subprocess output: registry configuration can contain credentials.
      console.warn('deepseek-harness: WARNING: Codex catalog refresh failed; using last-known-good metadata');
    } finally { rmSync(dir, { recursive: true, force: true }); }
  }
  catalog ??= normalizeCatalog(JSON.parse(readFileSync('/opt/dsh/model-catalog/openai-codex.json', 'utf8')));
  const targets = [
    join(home, 'profiles/web/node_modules/dsh-codex-oauth/node_modules/@earendil-works/pi-ai/dist/providers/data/openai-codex.json'),
  ];
  for (const target of targets) {
    if (existsSync(target)) atomicWrite(target, JSON.stringify(catalog));
  }
  console.log(`deepseek-harness: Codex catalog ready (${Object.keys(catalog['openai-codex-responses']).length} models)`);
}

if (process.argv[1] === new URL(import.meta.url).pathname) refresh();
