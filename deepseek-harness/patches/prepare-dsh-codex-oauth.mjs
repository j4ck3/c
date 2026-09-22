#!/usr/bin/env node
/** Approve only the two transitive lifecycle scripts required by pi-ai. */
import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const profile = join(
  process.env.DSH_HOME ?? join(homedir(), ".dsh"),
  "profiles/web",
);
const required = ["@google/genai", "protobufjs"];

function pnpm(...args) {
  const result = spawnSync("pnpm", args, {
    cwd: profile,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error(
      `pnpm ${args.join(" ")} failed: ${(result.stderr || result.stdout).trim()}`,
    );
  }
  return result.stdout.trim();
}

function readJsonConfig(name) {
  const output = pnpm("config", "get", name, "--json");
  if (output === "" || output === "undefined" || output === "null") return undefined;
  return JSON.parse(output);
}

const currentAllow = readJsonConfig("allowBuilds");
let allowBuilds;
if (currentAllow === undefined) {
  allowBuilds = {};
} else if (Array.isArray(currentAllow)) {
  allowBuilds = Object.fromEntries(currentAllow.map((name) => [name, true]));
} else if (typeof currentAllow === "object") {
  allowBuilds = { ...currentAllow };
} else {
  throw new Error("profile allowBuilds must be a map or list");
}

let changed = false;
for (const name of required) {
  if (allowBuilds[name] !== true) changed = true;
  allowBuilds[name] = true;
}
if (changed || Array.isArray(currentAllow)) {
  pnpm(
    "config",
    "set",
    "--location=project",
    "allowBuilds",
    JSON.stringify(allowBuilds),
    "--json",
  );
}

const currentOnly = readJsonConfig("onlyBuiltDependencies");
if (currentOnly !== undefined && !Array.isArray(currentOnly)) {
  throw new Error("profile onlyBuiltDependencies must be a list");
}
const approved = new Set(currentOnly ?? []);
for (const [name, allowed] of Object.entries(allowBuilds)) {
  if (allowed === true) approved.add(name);
}
const onlyBuiltDependencies = [...approved].sort();
if (
  !Array.isArray(currentOnly)
  || currentOnly.length !== onlyBuiltDependencies.length
  || currentOnly.some((name, index) => name !== onlyBuiltDependencies[index])
) {
  pnpm(
    "config",
    "set",
    "--location=project",
    "onlyBuiltDependencies",
    JSON.stringify(onlyBuiltDependencies),
    "--json",
  );
  changed = true;
}

console.log(
  changed
    ? `deepseek-harness: prepared Codex OAuth build approvals in ${profile}`
    : "deepseek-harness: Codex OAuth build approvals already present",
);
