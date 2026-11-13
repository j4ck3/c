#!/usr/bin/env node
/**
 * dsh-codex-oauth 0.1.6 targets the older dsh-llm CallId export. DSH
 * 0.1.2-rc.1 renamed that branded tool-call identifier to ToolCallId.
 */
import { existsSync, lstatSync, readFileSync, readlinkSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const dshHome = process.env.DSH_HOME ?? join(homedir(), ".dsh");
const file = join(dshHome, "profiles/web/node_modules/dsh-codex-oauth/lib/convert.js");

// The plugin bundles an older dsh-llm runtime. Point it at the exact runtime
// installed with this DSH release so Cordis brands and exports stay coherent.
const sourceRoot = "/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai";
const sourceLlm = join(sourceRoot, "dsh-llm");
const pluginRoot = join(
  dshHome,
  "profiles/web/local-plugins/dsh-codex-oauth-image/node_modules/@deepseek-ai",
);
const pluginLlm = join(
  dshHome,
  "profiles/web/local-plugins/dsh-codex-oauth-image/node_modules/@deepseek-ai/dsh-llm",
);
for (const packageName of ["dsh-llm", "dsh-attachment"]) {
  const sourcePackage = join(sourceRoot, packageName);
  const pluginPackage = join(pluginRoot, packageName);
  if (!existsSync(sourcePackage)) continue;
  let current;
  try {
    current = lstatSync(pluginPackage).isSymbolicLink() ? readlinkSync(pluginPackage) : undefined;
  } catch {}
  if (current !== sourcePackage) {
    rmSync(pluginPackage, { force: true, recursive: true });
    symlinkSync(sourcePackage, pluginPackage);
    console.log(`linked Codex OAuth to source-build ${packageName} at ${sourcePackage}`);
  }
}

if (!existsSync(file)) {
  console.log("dsh-codex-oauth not installed; skip");
  process.exit(0);
}

const callIdImportPattern =
  /import\s*\{[^}]*\bCallId\b[^}]*\}\s*from\s*['"]@deepseek-ai\/dsh-llm['"];/;
const toolCallIdImportPattern =
  /import\s*\{[^}]*\bToolCallId\b[^}]*\}\s*from\s*['"]@deepseek-ai\/dsh-llm['"];/;
const imageImport = "import { requestImageDimensions } from '@deepseek-ai/dsh-attachment';";
const imageCallFrom = "await attachments.readImageRequest(block.attachment, policy, options.signal)";
const imageCallTo = `await attachments.readImageRequest(block.attachment, {
            ...requestImageDimensions(block.attachment.width, block.attachment.height, policy.maxPixels),
            maxBytes: policy.maxBytes,
        }, options.signal)`;
let src = readFileSync(file, "utf8");
let changed = false;

if (callIdImportPattern.test(src)) {
  src = src.replaceAll(/\bCallId\b/g, "ToolCallId");
  changed = true;
} else if (!toolCallIdImportPattern.test(src)) {
  throw new Error(`patch dsh-llm ToolCallId compatibility: pattern not found in ${file}`);
}

if (src.includes(imageCallFrom)) {
  if (!src.includes(imageImport)) src = `${imageImport}\n${src}`;
  src = src.replace(imageCallFrom, imageCallTo);
  changed = true;
} else if (src.includes("requestImageDimensions(block.attachment.width")) {
  // Dimensions patch already applied.
} else {
  // Newer dsh-codex-oauth builds refuse image blocks before conversion, so
  // the dimension-clamping pattern is absent. Nothing to patch; tolerate.
  console.log(`dsh-codex-oauth: image-dimension pattern absent; skipping (upstream may have changed)`);
}

if (changed) {
  writeFileSync(file, src);
  console.log(`patched dsh-llm compatibility and image dimensions in ${file}`);
} else {
  console.log(`already patched dsh-llm compatibility and image dimensions in ${file}`);
}
