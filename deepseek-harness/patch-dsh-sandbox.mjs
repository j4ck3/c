#!/usr/bin/env node
/**
 * Unraid/Docker cannot confine DSH: Landlock is not enabled on the host
 * kernel, and bubblewrap cannot create user namespaces inside this container.
 * Two follow-on bugs then bite every bash/fs call:
 *
 * 1. workspace-write fail-closed → models escalate to danger-full-access and
 *    sit on "Allow once" forever.
 * 2. Once at full access, models still send sandbox_permissions; rc.2 treats
 *    non-widening requests as hard errors (GitHub discussions #2914, #4383).
 *
 * This patch makes non-widening sandbox_permissions a no-op so the standing
 * mode actually executes. Genuine widening still goes through approval.
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";

const SANDBOX_CANDIDATES = [
  "/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-sandbox/lib/index.js",
  "/usr/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-sandbox/lib/index.js",
];

function patchFile(replacements) {
  const file = SANDBOX_CANDIDATES.find((p) => existsSync(p));
  if (!file) {
    throw new Error(`dsh-sandbox not found in:\n${SANDBOX_CANDIDATES.join("\n")}`);
  }
  let src = readFileSync(file, "utf8");
  for (const { from, to, label } of replacements) {
    if (!src.includes(from)) {
      throw new Error(`patch ${label}: pattern not found in ${file}`);
    }
    src = src.replace(from, to);
  }
  writeFileSync(file, src);
  console.log(`patched ${file}`);
}

const validateFrom = `function validateEscalationArgs(sandboxPermissions, justification) {
	if (sandboxPermissions !== void 0 && justification === void 0) throw new Error("invalid escalation: sandbox_permissions requires a justification");
	if (justification !== void 0 && sandboxPermissions === void 0) throw new Error("invalid escalation: justification is only valid together with sandbox_permissions");
	if (justification !== void 0 && justification.trim().length === 0) throw new Error("invalid justification: expected a non-empty sentence");
}`;

const validateTo = `function validateEscalationArgs(sandboxPermissions, justification) {
	if (justification !== void 0 && sandboxPermissions === void 0) throw new Error("invalid escalation: justification is only valid together with sandbox_permissions");
	if (justification !== void 0 && justification.trim().length === 0) throw new Error("invalid justification: expected a non-empty sentence");
}`;

const approveFrom = `	if (!(WIDER_MODES[effectiveMode] ?? []).includes(mode)) throw new Error(\`sandbox escalation to "\${mode}" is not strictly wider than this call's current "\${effectiveMode}" mode\`);`;

const approveTo = `	if (!(WIDER_MODES[effectiveMode] ?? []).includes(mode)) return effectiveMode;`;

patchFile([
  { from: validateFrom, to: validateTo, label: "validateEscalationArgs" },
  { from: approveFrom, to: approveTo, label: "approveEscalation no-op" },
]);
