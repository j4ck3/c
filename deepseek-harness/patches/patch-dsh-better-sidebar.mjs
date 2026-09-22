#!/usr/bin/env node
/**
 * Make dsh-better-sidebar Git operations work in dsh-remote-ssh workspaces.
 *
 * The published sidebar uses node:child_process directly. That evaluates the
 * virtual workspace alias inside the DSH container instead of on the selected
 * SSH host. Injecting DSH's subprocess service lets dsh-remote-ssh route by
 * cwd. Tower's shared repositories have a different owner, so safe.directory
 * is relaxed per command only; no persistent global Git config is changed.
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const file = join(
  process.env.DSH_HOME ?? join(homedir(), ".dsh"),
  "profiles/web/node_modules/dsh-better-sidebar/lib/index.js",
);

if (!existsSync(file)) {
  console.log("dsh-better-sidebar not installed; skip");
  process.exit(0);
}

let src = readFileSync(file, "utf8");

function replaceOnce(from, to, label) {
  if (src.includes(to) && !src.includes(from)) {
    console.log(`already patched ${label} in ${file}`);
    return;
  }
  if (!src.includes(from)) {
    throw new Error(`patch ${label}: pattern not found in ${file}`);
  }
  src = src.replace(from, to);
}

const runGitFrom = `/** Run one git command; resolves with stdout, rejects with GitCommandError. */
function runGit(cwd, args, timeoutMs = 3e4) {
\tconst full = [
\t\t"-C",
\t\tcwd,
\t\t"--no-pager",
\t\t"-c",
\t\t"color.ui=false",
\t\t...args
\t];
\treturn new Promise((resolvePromise, reject) => {
\t\tconst child = spawn("git", full, {
\t\t\tstdio: [
\t\t\t\t"ignore",
\t\t\t\t"pipe",
\t\t\t\t"pipe"
\t\t\t],
\t\t\twindowsHide: true,
\t\t\tenv: {
\t\t\t\t...process.env,
\t\t\t\tGIT_OPTIONAL_LOCKS: "0"
\t\t\t}
\t\t});
\t\tlet stdout = "";
\t\tlet stderr = "";
\t\tconst timer = setTimeout(() => {
\t\t\tchild.kill("SIGKILL");
\t\t\treject(new GitCommandError(\`git \${args[0] ?? ""} timed out after \${timeoutMs}ms\`, "git-error", args.join(" ")));
\t\t}, timeoutMs);
\t\tchild.stdout.on("data", (chunk) => {
\t\t\tstdout += chunk.toString("utf8");
\t\t});
\t\tchild.stderr.on("data", (chunk) => {
\t\t\tstderr += chunk.toString("utf8");
\t\t});
\t\tchild.on("error", (error) => {
\t\t\tclearTimeout(timer);
\t\t\treject(new GitCommandError(\`cannot run git: \${error.message}\`, "git-error", args.join(" ")));
\t\t});
\t\tchild.on("close", (code) => {
\t\t\tclearTimeout(timer);
\t\t\tif (code === 0) resolvePromise(stdout);
\t\t\telse reject(new GitCommandError(stderr.trim() || \`git exited with \${String(code)}\`, "git-error", args.join(" ")));
\t\t});
\t});
}`;

const runGitTo = `/** DSH subprocess service; its cwd router selects local vs Remote SSH. */
let gitSubprocess;
const warnedGitProbeCwds = /* @__PURE__ */ new Set();
/** Run one git command; resolves with stdout, rejects with GitCommandError. */
async function runGit(cwd, args, timeoutMs = 3e4) {
\tif (gitSubprocess === void 0) throw new GitCommandError("Git subprocess service is unavailable", "git-error", args.join(" "));
\tconst controller = new AbortController();
\tconst timer = setTimeout(() => controller.abort(new Error("git timeout")), timeoutMs);
\ttry {
\t\tconst handle = gitSubprocess.spawn({
\t\t\targv: [
\t\t\t\t"git",
\t\t\t\t"-c",
\t\t\t\t"safe.directory=*",
\t\t\t\t"--no-pager",
\t\t\t\t"-c",
\t\t\t\t"color.ui=false",
\t\t\t\t...args
\t\t\t],
\t\t\tcwd,
\t\t\tstdio: {
\t\t\t\tstdin: "ignore",
\t\t\t\tstdout: { maxBytes: 67108864 },
\t\t\t\tstderr: { maxBytes: 67108864 }
\t\t\t},
\t\t\tgraceMs: 1e3,
\t\t\tsignal: controller.signal,
\t\t\tenv: { GIT_OPTIONAL_LOCKS: "0" }
\t\t});
\t\tconst outcome = await handle.done;
\t\tif (controller.signal.aborted) throw new GitCommandError(\`git \${args[0] ?? ""} timed out after \${timeoutMs}ms\`, "git-error", args.join(" "));
\t\tconst stdoutReader = handle.collected.stdout;
\t\tconst stderrReader = handle.collected.stderr;
\t\tif (stdoutReader === void 0 || stderrReader === void 0) throw new Error("subprocess dropped requested Git output");
\t\tconst stdout = stdoutReader.readFrom(0);
\t\tconst stderr = stderrReader.readFrom(0);
\t\tif (stdout.lossy || stderr.lossy) throw new GitCommandError("git output exceeded 64 MiB", "git-error", args.join(" "));
\t\tif (outcome.exitCode === 0) return stdout.text;
\t\tthrow new GitCommandError(stderr.text.trim() || \`git exited with \${String(outcome.exitCode ?? outcome.signal)}\`, "git-error", args.join(" "));
\t} catch (error) {
\t\tif (error instanceof GitCommandError) throw error;
\t\tthrow new GitCommandError(\`cannot run git: \${error instanceof Error ? error.message : String(error)}\`, "git-error", args.join(" "));
\t} finally {
\t\tclearTimeout(timer);
\t}
}`;

// Migrate the first revision of this local patch without depending on a
// package reinstall to restore the upstream block.
const runGitV1 = runGitTo.replace("const warnedGitProbeCwds = /* @__PURE__ */ new Set();\n", "");
if (src.includes(runGitV1) && !src.includes(runGitTo)) src = src.replace(runGitV1, runGitTo);
if (src.includes("gitRemoteManager?.route(void 0, cwd)")) {
  console.log(`already patched cwd-routed Git subprocess in ${file}`);
} else {
  replaceOnce(runGitFrom, runGitTo, "cwd-routed Git subprocess");
}
replaceOnce(
  `let gitSubprocess;\nconst warnedGitProbeCwds`,
  `let gitSubprocess;\nlet gitRemoteManager;\nfunction quoteGitArg(value) {\n\treturn "'" + value.replaceAll("'", "'\\\"'\\\"'") + "'";\n}\nconst warnedGitProbeCwds`,
  "Remote SSH Git shell helpers",
);
if (!src.includes("const remoteCwd = route.mapper.toRemotePath(cwd, route.aliasPath);")) replaceOnce(
  `\ttry {\n\t\tconst handle = gitSubprocess.spawn({`,
  `\ttry {\n\t\tconst route = gitRemoteManager?.route(void 0, cwd);\n\t\tif (route?.kind === "remote") {\n\t\t\tconst shell = await gitRemoteManager.workspaceShell(route, "bash");\n\t\t\tconst argv = ["git", "-c", "safe.directory=*", "--no-pager", "-c", "color.ui=false", ...args];\n\t\t\tconst outcome = await shell.run(shell.resolve({\n\t\t\t\tcommand: argv.map(quoteGitArg).join(" "),\n\t\t\t\tworkdir: cwd,\n\t\t\t\ttimeoutMs,\n\t\t\t\tstdoutMaxBytes: 16777216,\n\t\t\t\tsignal: controller.signal,\n\t\t\t\tenv: { GIT_OPTIONAL_LOCKS: "0" },\n\t\t\t\tsandboxPolicy: { mode: "danger-full-access", workspaceRoot: route.aliasPath }\n\t\t\t}));\n\t\t\tif (outcome.exitCode === 0) return outcome.stdout.text;\n\t\t\tthrow new GitCommandError(outcome.stdout.text.trim() || \`git exited with \${String(outcome.exitCode ?? outcome.signal)}\`, "git-error", args.join(" "));\n\t\t}\n\t\tconst handle = gitSubprocess.spawn({`,
  "direct Remote SSH Git execution",
);
replaceOnce(
  `\t\t\tconst shell = await gitRemoteManager.workspaceShell(route, "bash");\n\t\t\tconst argv = ["git", "-c", "safe.directory=*", "--no-pager", "-c", "color.ui=false", ...args];\n\t\t\tconst outcome = await shell.run(shell.resolve({\n\t\t\t\tcommand: argv.map(quoteGitArg).join(" "),\n\t\t\t\tworkdir: cwd,`,
  `\t\t\tconst shell = await gitRemoteManager.workspaceShell(route, "bash");\n\t\t\tconst remoteCwd = route.mapper.toRemotePath(cwd, route.aliasPath);\n\t\t\tconst argv = ["git", "-c", "safe.directory=*", "--no-pager", "-c", "color.ui=false", ...args];\n\t\t\tconst outcome = await shell.run(shell.resolve({\n\t\t\t\tcommand: \`cd -- \${quoteGitArg(remoteCwd)} && \${argv.map(quoteGitArg).join(" ")}\`,\n\t\t\t\tworkdir: route.aliasPath,`,
  "explicit remote Git cwd",
);
const probeV1 = `\ttry {\n\t\treturn (await runGit(cwd, ["rev-parse", "--is-inside-work-tree"], DISCOVERY_TIMEOUT_MS)).trim() === "true";\n\t} catch (error) {\n\t\tif (!warnedGitProbeCwds.has(cwd)) {\n\t\t\twarnedGitProbeCwds.add(cwd);\n\t\t\tconsole.warn(\`[dsh-better-sidebar] Git repository probe failed for "\${cwd}": \${error instanceof Error ? error.message : String(error)}\`);\n\t\t}\n\t\treturn false;\n\t}`;
const probeV2 = `\ttry {\n\t\tconst probe = (await runGit(cwd, ["rev-parse", "--is-inside-work-tree"], DISCOVERY_TIMEOUT_MS)).trim();\n\t\tif (probe !== "true" && !warnedGitProbeCwds.has(cwd)) {\n\t\t\twarnedGitProbeCwds.add(cwd);\n\t\t\tconsole.warn(\`[dsh-better-sidebar] Git repository probe for "\${cwd}" returned \${JSON.stringify(probe)}\`);\n\t\t}\n\t\treturn probe === "true";\n\t} catch (error) {\n\t\tif (!warnedGitProbeCwds.has(cwd)) {\n\t\t\twarnedGitProbeCwds.add(cwd);\n\t\t\tconsole.warn(\`[dsh-better-sidebar] Git repository probe failed for "\${cwd}": \${error instanceof Error ? error.message : String(error)}\`);\n\t\t}\n\t\treturn false;\n\t}`;
if (src.includes(probeV1) && !src.includes(probeV2)) src = src.replace(probeV1, probeV2);
replaceOnce(
  `\ttry {\n\t\treturn (await runGit(cwd, ["rev-parse", "--is-inside-work-tree"], DISCOVERY_TIMEOUT_MS)).trim() === "true";\n\t} catch {\n\t\treturn false;\n\t}\n}\n/** The repository top level containing \`cwd\``,
  `\ttry {\n\t\tconst probe = (await runGit(cwd, ["rev-parse", "--is-inside-work-tree"], DISCOVERY_TIMEOUT_MS)).trim();\n\t\tif (probe !== "true" && !warnedGitProbeCwds.has(cwd)) {\n\t\t\twarnedGitProbeCwds.add(cwd);\n\t\t\tconsole.warn(\`[dsh-better-sidebar] Git repository probe for \"\${cwd}\" returned \${JSON.stringify(probe)}\`);\n\t\t}\n\t\treturn probe === "true";\n\t} catch (error) {\n\t\tif (!warnedGitProbeCwds.has(cwd)) {\n\t\t\twarnedGitProbeCwds.add(cwd);\n\t\t\tconsole.warn(\`[dsh-better-sidebar] Git repository probe failed for \"\${cwd}\": \${error instanceof Error ? error.message : String(error)}\`);\n\t\t}\n\t\treturn false;\n\t}\n}\n/** The repository top level containing \`cwd\``,
  "Git discovery diagnostics",
);
replaceOnce(
  `\t} catch {\n\t\tconst entries = await readdir(cwd, { withFileTypes: true }).catch(() => []);`,
  `\t} catch (error) {\n\t\tif (!warnedGitProbeCwds.has(cwd)) {\n\t\t\twarnedGitProbeCwds.add(cwd);\n\t\t\tconsole.warn(\`[dsh-better-sidebar] Git discovery failed for \"\${cwd}\": \${error instanceof Error ? error.message : String(error)}\`);\n\t\t}\n\t\tconst entries = await readdir(cwd, { withFileTypes: true }).catch(() => []);`,
  "Git root diagnostics",
);
if (!src.includes(`\t"remoteSshManager"\n];`)) {
  replaceOnce(
    `\t"webRuntime",\n\t"tools"\n];`,
    `\t"webRuntime",\n\t"tools",\n\t"subprocess"\n];`,
    "subprocess injection",
  );
}
replaceOnce(
  `\t"webRuntime",\n\t"tools",\n\t"subprocess"\n];`,
  `\t"webRuntime",\n\t"tools",\n\t"subprocess",\n\t"remoteSshManager"\n];`,
  "Remote SSH manager injection",
);
if (!src.includes("\tgitRemoteManager = ctx.remoteSshManager;")) {
  replaceOnce(
    `function apply(ctx, config) {\n\tensureSpawnHelper();`,
    `function apply(ctx, config) {\n\tgitSubprocess = ctx.subprocess;\n\tensureSpawnHelper();`,
    "subprocess binding",
  );
}
replaceOnce(
  `function apply(ctx, config) {\n\tgitSubprocess = ctx.subprocess;\n\tensureSpawnHelper();`,
  `function apply(ctx, config) {\n\tgitSubprocess = ctx.subprocess;\n\tgitRemoteManager = ctx.remoteSshManager;\n\tensureSpawnHelper();`,
  "Remote SSH manager binding",
);

writeFileSync(file, src);
console.log(`patched ${file}`);
