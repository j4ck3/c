#!/usr/bin/env node
/**
 * A DSH bash tool runs inside the process whose session it serves. Letting an
 * agent signal that process interrupts the tool before its result is journaled.
 * Reject only commands that target DSH/container supervision; ordinary process
 * management remains available to coding agents.
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";

const CANDIDATES = [
  "/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-tool-bash/lib/index.js",
  "/usr/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-tool-bash/lib/index.js",
];
const file = CANDIDATES.find((candidate) => existsSync(candidate));
if (!file) {
  throw new Error(`dsh-tool-bash not found in:\n${CANDIDATES.join("\n")}`);
}

let source = readFileSync(file, "utf8");
const marker = "DSH_SELF_TERMINATION_GUARD";
if (source.includes(marker)) {
  console.log(`already patched ${marker} in ${file}`);
  process.exit(0);
}

const functionAnchor = "function validateBashArgs(args) {";
const executeAnchor = "\t\tasync execute(args, exec) {\n\t\t\tvalidateBashArgs(args);";
if (!source.includes(functionAnchor) || !source.includes(executeAnchor)) {
  throw new Error(`patch ${marker}: pattern not found in ${file}`);
}

const guard = `const DSH_SELF_TERMINATION_GUARD = "DSH_SELF_TERMINATION_GUARD";
function rejectHarnessTermination(command) {
\tconst protectedPids = [process.pid, process.ppid, 1].map(String).join("|");
\tconst directSignal = new RegExp("\\\\bkill\\\\b(?:\\\\s+-[A-Za-z0-9]+|\\\\s+--[A-Za-z-]+(?:=\\\\S+)?)?\\\\s+(?:" + protectedPids + ")(?:\\\\s|;|&|$)");
\tconst namedSignal = /\\b(?:kill|pkill|killall)\\b[^\\n]*(?:pgrep|pidof|dsh|deepseek-harness)/i;
\tconst supervisorStop = /\\b(?:docker(?:\\s+compose)?|systemctl|service)\\b[^\\n]*(?:kill|stop|restart|down|rm)[^\\n]*(?:dsh|deepseek-harness)/i;
\tif (directSignal.test(command) || namedSignal.test(command) || supervisorStop.test(command)) {
\t\tthrow new Error("blocked: a DSH session cannot stop or restart its own harness; use the external container supervisor");
\t}
}
`;

source = source.replace(functionAnchor, `${guard}\n${functionAnchor}`);
source = source.replace(
  executeAnchor,
  `${executeAnchor}\n\t\t\trejectHarnessTermination(args.command);`,
);
writeFileSync(file, source);
console.log(`patched ${marker} in ${file}`);
