#!/usr/bin/env node
/**
 * dsh-remote-ssh@0.2.4 targets DSH 0.1.0-rc.6. Compatibility patches:
 *
 * 1. DSH 0.1.2 removed the settingsNamespace runtime helper. Namespace
 *    registration now accepts the same validated string directly.
 * 2. settings.plugin.item is now a keyed slot. Registering it with id/order
 *    throws and aborts plugin boot; the Remote SSH client never mounts, while
 *    its host patch has already disabled the official directory picker.
 * 3. Its /plugins/dsh-remote-ssh/* fence compares Origin.host === Host.host
 *    with no port canonicalization, so HTTPS Origin (no port) vs Host:443
 *    (or Origin: null) returns JSON { error: "forbidden" }. The client
 *    throws that string, which is exactly the dialog copy.
 * 4. OpenSSH entries whose effective user is `git` are source-control
 *    transports, not interactive Remote SSH workspaces. Keep their SSH
 *    configuration intact but omit them from the plugin's host directory.
 */
import { existsSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const ROOT = join(
  process.env.DSH_HOME ?? join(homedir(), ".dsh"),
  "profiles/web/node_modules/dsh-remote-ssh",
);

function patchFile(file, replacements) {
  if (!existsSync(file)) {
    throw new Error(`dsh-remote-ssh file not found: ${file}`);
  }
  let src = readFileSync(file, "utf8");
  for (const { from, to, label } of replacements) {
    if (src.includes(to) && !src.includes(from)) {
      console.log(`already patched ${label} in ${file}`);
      continue;
    }
    if (!src.includes(from)) {
      throw new Error(`patch ${label}: pattern not found in ${file}`);
    }
    src = src.replace(from, to);
  }
  writeFileSync(file, src);
  console.log(`patched ${file}`);
}

const clientFrom = `			ctx.slots.inject("settings.plugin.item", () => ctx.slots.register({
				name: "settings.plugin.item",
				id: "remote-ssh",
				order: 30,
				inject: () => ({ t })
			}, RemoteSshPluginCard));`;

const clientTo = `			ctx.slots.inject("settings.plugin.item", () => ctx.slots.register({
				name: "settings.plugin.item",
				key: "remote-ssh",
				inject: () => ({ t })
			}, RemoteSshPluginCard));`;

const trustFrom = `function trustedRequest(req) {
	if (req.headers["sec-fetch-site"] === "cross-site") return false;
	const host = req.headers.host;
	const origin = req.headers.origin;
	if (host === void 0 || origin === void 0) return origin === void 0;
	try {
		return new URL(origin).host === new URL(\`http://\${host}\`).host;
	} catch {
		return false;
	}
}`;

const trustTo = `function defaultPort(protocol) {
	return protocol === "https:" ? "443" : "80";
}
function originPort(url) {
	return url.port === "" ? defaultPort(url.protocol) : url.port;
}
function hostHeaderPort(hostUrl, originIsHttps) {
	if (hostUrl.port !== "") return hostUrl.port;
	return originIsHttps ? "443" : "80";
}
function trustedRequest(req) {
	if (req.headers["sec-fetch-site"] === "cross-site") return false;
	const host = req.headers.host;
	const origin = req.headers.origin;
	if (host === void 0) return false;
	if (origin === void 0 || origin === "" || origin === "null") return true;
	try {
		const originUrl = new URL(origin);
		const hostUrl = new URL("http://" + host);
		if (originUrl.hostname !== hostUrl.hostname) return false;
		return originPort(originUrl) === hostHeaderPort(hostUrl, originUrl.protocol === "https:");
	} catch {
		return false;
	}
}`;

if (!existsSync(ROOT)) {
  console.log("dsh-remote-ssh not installed; skip");
  process.exit(0);
}

patchFile(join(ROOT, "lib/manager.js"), [
  {
    from: `import { settingsNamespace } from "@deepseek-ai/dsh-settings";`,
    to: ``,
    label: "removed settingsNamespace import",
  },
]);

patchFile(join(ROOT, "lib/client.js"), [
  { from: clientFrom, to: clientTo, label: "settings.plugin.item key" },
]);
patchFile(join(ROOT, "lib/web.js"), [
  { from: trustFrom, to: trustTo, label: "trustedRequest port/null origin" },
]);

const sshConfigBundle = readdirSync(join(ROOT, "lib")).find((name) =>
  /^ssh-config-.*\.js$/.test(name),
);
if (sshConfigBundle === undefined) {
  throw new Error(`dsh-remote-ssh SSH config bundle not found in ${ROOT}/lib`);
}
patchFile(join(ROOT, "lib", sshConfigBundle), [
  {
    from: `hosts: [...hosts.values()].sort((left, right) => left.label.localeCompare(right.label)),`,
    to: `hosts: [...hosts.values()].filter((host) => host.user?.toLowerCase() !== "git").sort((left, right) => left.label.localeCompare(right.label)),`,
    label: "hide Git transport hosts",
  },
]);

// Stable VS Code Agent Host now speaks AHP ^0.9.0. Offer it before 0.8 so
// initialize succeeds against current code CLI downloads.
const ahpLib = join(ROOT, "lib/src-D6lNt3RG.js");
if (existsSync(ahpLib)) {
  let ahpSrc = readFileSync(ahpLib, "utf8");
  const ahpWant =
    `[.../* @__PURE__ */ new Set([...["0.9.0", "0.8.0"], ...SUPPORTED_PROTOCOL_VERSIONS])]`;
  const ahpOld =
    `[.../* @__PURE__ */ new Set([...["0.8.0"], ...SUPPORTED_PROTOCOL_VERSIONS])]`;
  if (ahpSrc.includes(ahpWant)) {
    console.log(`already patched AHP offer 0.9.0 in ${ahpLib}`);
  } else if (ahpSrc.includes(ahpOld)) {
    writeFileSync(ahpLib, ahpSrc.replace(ahpOld, ahpWant));
    console.log(`patched ${ahpLib}`);
  } else {
    throw new Error(`patch AHP offer 0.9.0: pattern not found in ${ahpLib}`);
  }
}

// The distro OSS `code` wrapper can be present on PATH but unable to spawn its
// Electron tunnel binary after a package change. Prefer the official private
// CLI provisioned on each SSH host; PATH remains a fallback if it is absent.
const bootstrapLib = ahpLib;
const bootstrapFrom = '"if [ \\"$dsh_code\\" = code ] && ! command -v \\"$dsh_code\\" >/dev/null 2>&1 && [ -x \\"$HOME/.dsh-remote-ssh/cli/bin/code\\" ]; then dsh_code=\\"$HOME/.dsh-remote-ssh/cli/bin/code\\"; fi"';
const bootstrapTo = '"if [ \\"$dsh_code\\" = code ] && [ -x \\"$HOME/.dsh-remote-ssh/cli/bin/code\\" ]; then dsh_code=\\"$HOME/.dsh-remote-ssh/cli/bin/code\\"; fi"';
patchFile(bootstrapLib, [{ from: bootstrapFrom, to: bootstrapTo, label: "prefer private official CLI" }]);

// Reconnect after Agent Host closure OR failed SSH startup. Defer failed
// startup retries until the next request so a transient outage is not cached.
const reconnectFrom = `\tasync getConnection() {
\t\tif (this.disposed) throw new Error("Remote SSH service is disposing");
\t\tconst connection = await this.ready;
\t\tif (this.disposed) throw new Error("Remote SSH service is disposing");
\t\treturn connection;
\t}`;
const reconnectPrevious = `\tasync getConnection() {
\t\tif (this.disposed) throw new Error("Remote SSH service is disposing");
\t\tconst observed = this.ready;
\t\tlet connection = await observed;
\t\tif (this.disposed) throw new Error("Remote SSH service is disposing");
\t\tif (connection.client.connectionState.status !== "connected") {
\t\t\tif (this.ready === observed) {
\t\t\t\tthis.resetSshAttempt();
\t\t\t\tthis.ready = this.open();
\t\t\t\tthis.ready.catch(() => {});
\t\t\t}
\t\t\tconnection = await this.ready;
\t\t\tif (this.disposed) throw new Error("Remote SSH service is disposing");
\t\t}
\t\treturn connection;
\t}`;
const reconnectTo = `\tasync getConnection() {
\t\tif (this.disposed) throw new Error("Remote SSH service is disposing");
\t\tif (this.readyFailed) {
\t\t\tthis.readyFailed = false;
\t\t\tthis.resetSshAttempt();
\t\t\tthis.ready = this.open();
\t\t\tthis.ready.catch(() => {});
\t\t}
\t\tconst observed = this.ready;
\t\tlet connection;
\t\ttry {
\t\t\tconnection = await observed;
\t\t} catch (error) {
\t\t\tif (this.ready === observed) this.readyFailed = true;
\t\t\tthrow error;
\t\t}
\t\tif (this.disposed) throw new Error("Remote SSH service is disposing");
\t\tif (connection.client.connectionState.status !== "connected") {
\t\t\tif (this.ready === observed) {
\t\t\t\tthis.resetSshAttempt();
\t\t\t\tthis.ready = this.open();
\t\t\t\tthis.ready.catch(() => {});
\t\t\t}
\t\t\tconnection = await this.ready;
\t\t\tif (this.disposed) throw new Error("Remote SSH service is disposing");
\t\t}
\t\treturn connection;
\t}`;
let reconnectSrc = readFileSync(ahpLib, "utf8");
if (reconnectSrc.includes(reconnectTo)) {
  console.log(`already patched closed-client reconnect in ${ahpLib}`);
} else if (reconnectSrc.includes(reconnectPrevious) || reconnectSrc.includes(reconnectFrom)) {
  reconnectSrc = reconnectSrc.replace(reconnectSrc.includes(reconnectPrevious) ? reconnectPrevious : reconnectFrom, reconnectTo);
  writeFileSync(ahpLib, reconnectSrc);
  console.log(`patched closed-client reconnect in ${ahpLib}`);
} else {
  throw new Error(`patch closed-client reconnect: pattern not found in ${ahpLib}`);
}

// Remote glob/grep spawn the harness-bundled @vscode/ripgrep path. On POSIX
// remotes that file does not exist; use PATH `rg` instead (INSTALL.md prereq).
const routerSubprocess = join(ROOT, "lib/router-subprocess.js");
if (existsSync(routerSubprocess)) {
  let routerSrc = readFileSync(routerSubprocess, "utf8");
  const rgMarker = 'executable.endsWith("-rg")) return "rg";';
  if (routerSrc.includes(rgMarker)) {
    console.log(`already patched remote ripgrep uses PATH rg in ${routerSubprocess}`);
  } else {
    const rgFrom =
      'function remoteExecutable(executable) {\n\tif (!/^(?:[A-Za-z]:[\\\\/]|\\\\\\\\)/.test(executable)) return executable;\n\treturn win32.basename(executable).replace(/\\.exe$/i, "");\n}';
    const rgTo =
      'function remoteExecutable(executable) {\n\tif (/^(?:[A-Za-z]:[\\\\/]|\\\\\\\\)/.test(executable)) return win32.basename(executable).replace(/\\.exe$/i, "");\n\tif (executable.includes("@vscode/ripgrep") || executable.includes("ripgrep-linux") || executable.endsWith("-rg")) return "rg";\n\treturn executable;\n}';
    if (!routerSrc.includes(rgFrom)) {
      throw new Error(`patch remote ripgrep uses PATH rg: pattern not found in ${routerSubprocess}`);
    }
    writeFileSync(routerSubprocess, routerSrc.replace(rgFrom, rgTo));
    console.log(`patched ${routerSubprocess}`);
  }
}

// Keep the plugin on the AHP client that can negotiate 0.9 with current Agent Host.
const ahpPkg = join(ROOT, "node_modules/@microsoft/agent-host-protocol/package.json");
for (const pkgPath of [ahpPkg]) {
  if (!existsSync(pkgPath)) continue;
  const version = JSON.parse(readFileSync(pkgPath, "utf8")).version;
  if (version === "0.9.0" || version.startsWith("0.9.")) {
    console.log(`AHP client ${version} ok at ${pkgPath}`);
  } else {
    console.log(`AHP client ${version} at ${pkgPath} — need 0.9.x (entrypoint should reinstall)`);
  }
}
