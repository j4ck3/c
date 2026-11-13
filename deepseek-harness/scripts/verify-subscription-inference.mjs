#!/usr/bin/env node
// Real, minimal inference through the installed plugin's adapters and token store.
// Temporary export shim is removed even when a provider fails. Never log tokens.
import {readFile, writeFile, unlink} from 'node:fs/promises';
const base = `${process.env.DSH_HOME}/profiles/web/node_modules/dsh-plugin-subscriptions/lib`;
const shim = `${base}/.upgrade-smoke-${process.pid}.mjs`;
try {
  const source = await readFile(`${base}/index.js`, 'utf8');
  await writeFile(shim, source + '\nexport {AccountTokenManager, CodexAdapter, ClaudeAdapter, refreshCodex, refreshClaude, isCodexPermanentRefreshError, isClaudePermanentRefreshError, ClaudeCliVersionCache, DEFAULT_MODELS};\n', {mode:0o600});
  const p = await import(shim);
  const claudeVersions = new p.ClaudeCliVersionCache();
  let failed = false;
  for (const provider of ['codex','claude']) {
    try {
      const tokens = new p.AccountTokenManager({provider,displayName:provider,makeOptions:()=>({preemptMs:300000, refresh:provider==='codex'?p.refreshCodex:p.refreshClaude,isPermanent:provider==='codex'?p.isCodexPermanentRefreshError:p.isClaudePermanentRefreshError})});
      const Adapter = provider==='codex'?p.CodexAdapter:p.ClaudeAdapter;
      const adapter = new Adapter({tokens,models:p.DEFAULT_MODELS[provider],discovery:true,streamIdleTimeoutMs:45000,resolveCliVersion:async()=>(await claudeVersions.resolve()).version});
      const models = await adapter.listModels(provider);
      if (!models.length) throw new Error('No available models');
      const model = models.find(m=>/mini|haiku/i.test(m.id)) ?? models.find(m=>/sonnet/i.test(m.id)) ?? models[0];
      let events=0, text=false;
      for await (const event of adapter.stream({provider,model:model.id,messages:[{role:'user',content:[{type:'text',text:'Reply with exactly OK.'}]}],maxTokens:64,signal:AbortSignal.timeout(90000)})) {
        events++;
        if (JSON.stringify(event).includes('OK')) text=true;
      }
      if (!events || !text) throw new Error('No expected text in inference stream');
      console.log(`PASS ${provider}: ${models.length} models, real inference OK (${model.id}, ${events} events)`);
    } catch (e) {
      failed=true;
      // Error codes/status only: provider response bodies may include identifiers.
      console.log(`FAIL ${provider}: ${e.name}, code=${e.code ?? 'none'}, status=${e.status ?? e.statusCode ?? 'none'}`);
    }
  }
  if (failed) process.exitCode=1;
} finally {
  await unlink(shim).catch(()=>{});
}
