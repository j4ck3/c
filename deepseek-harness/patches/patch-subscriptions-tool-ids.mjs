#!/usr/bin/env node
/**
 * Local DSH patch: dsh-plugin-subscriptions passes DSH tool-call ids through
 * untranslated into provider wire formats. Anthropic only accepts ids
 * matching ^[a-zA-Z0-9_-]+$ in tool_use/tool_result, so session history that
 * carries ids created under other providers (dots, colons, ...) fails with
 * HTTP 400 "String should match pattern". Map every invalid char to '_'
 * consistently on both sides of a pair so tool_use/tool_result stay matched.
 *
 * Patches lib/index.js (bundled runtime) and lib/translate/anthropic.js.
 * The helper is inserted at MODULE SCOPE (after the top-of-file imports) —
 * never inside a function, or other call sites throw ReferenceError.
 * Idempotent.
 */
import { readFileSync, writeFileSync } from "node:fs";
const home = process.env.DSH_HOME ?? "/home/t3/.dsh";
const base = `${home}/profiles/web/node_modules/dsh-plugin-subscriptions/lib`;
const helper = `
// Local patch: provider APIs only accept ids matching ^[a-zA-Z0-9_-]+$ in
// tool_use/tool_result (Anthropic) and tool call ids (OpenAI). DSH history
// may carry ids from other providers with characters outside that set; map
// every invalid char to '_' consistently so pairs stay matched.
const anthropicSafeId = (id) => {
    const s = String(id).replace(/[^a-zA-Z0-9_-]/g, "_");
    return s.length > 0 ? s : "tool_0";
};
`;
const subs = [
  ["tool_use_id: id,", "tool_use_id: anthropicSafeId(id),"],
  ["id: String(block.id),", "id: anthropicSafeId(block.id),"],
  ["tool_use_id: String(block.toolCallId),", "tool_use_id: anthropicSafeId(block.toolCallId),"],
];
for (const name of ["index.js", "translate/anthropic.js"]) {
  const file = `${base}/${name}`;
  let src;
  try {
    src = readFileSync(file, "utf8");
  } catch {
    console.log(`subscriptions id patch: ${name} missing; skip`);
    continue;
  }
  // strip any previously inserted helper (function comment + arrow fn)
  src = src.replace(
    /\n\/\/ Local patch: [^\n]*\n(\/\/[^\n]*\n)*const anthropicSafeId = \(id\) => \{\n([^}]|\n)*?\};\n/g,
    "\n",
  );
  if (!src.includes("anthropicSafeId(")) {
    let applied = true;
    for (const [from, to] of subs) {
      if (!src.includes(from)) {
        console.log(`subscriptions id patch: pattern missing in ${name} (${from}); upstream changed; skip`);
        applied = false;
        break;
      }
    }
    if (!applied) continue;
    for (const [from, to] of subs) src = src.replaceAll(from, to);
  }
  // insert helper at module scope: after the last top-of-file import statement
  const importRe = /^import[\s\S]*?from\s+["'][^"']+["'];\n/gm;
  let last = null, m;
  while ((m = importRe.exec(src)) !== null) {
    if (m.index < 4000) last = m; else break;
  }
  if (!last) {
    console.log(`subscriptions id patch: no imports found in ${name}; skip`);
    continue;
  }
  const pos = last.index + last[0].length;
  src = src.slice(0, pos) + helper + src.slice(pos);
  writeFileSync(file, src);
  console.log(`patched anthropic tool id sanitization in ${name} (module scope)`);
}
