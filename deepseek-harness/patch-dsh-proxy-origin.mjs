#!/usr/bin/env node
/**
 * DSH 0.1.2-rc.1 needs two compatibility adjustments for an authenticated,
 * trusted reverse-proxy deployment:
 *
 * 1. It parses the forwarded Host header under HTTP, then compares it
 *    literally with the browser's HTTPS Origin. Reverse proxies that forward
 *    Host:443 therefore make browser RPC return 403 even when the host is
 *    explicitly trusted. Compare normalized hostname and effective port.
 * 2. Its settings UI forces all non-loopback browsers into an in-memory mode
 *    that never calls settings.describe. This deployment already has the
 *    release's browser-session auth and trusted-host fence, so retain the Host
 *    settings mirror through the public HTTPS authority.
 */
import { readFileSync, writeFileSync } from "node:fs";

const connectionFile =
  "/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-client-connection/lib/index.js";

const from = `\ttry {
\t\treturn new URL(origin).host === hostUrl.host;
\t} catch {
\t\treturn false;
\t}`;

const to = `\ttry {
\t\tconst originUrl = new URL(origin);
\t\tconst originPort = originUrl.port || (originUrl.protocol === "https:" ? "443" : "80");
\t\tconst hostPort = hostUrl.port || (originUrl.protocol === "https:" ? "443" : "80");
\t\treturn originUrl.hostname === hostUrl.hostname && originPort === hostPort;
\t} catch {
\t\treturn false;
\t}`;

const source = readFileSync(connectionFile, "utf8");
if (source.includes(to) && !source.includes(from)) {
  console.log(`already patched proxy HTTPS origin in ${connectionFile}`);
} else if (!source.includes(from)) {
  throw new Error(`proxy HTTPS origin patch pattern not found in ${connectionFile}`);
} else {
  writeFileSync(connectionFile, source.replace(from, to));
  console.log(`patched proxy HTTPS origin in ${connectionFile}`);
}

const settingsClientFile =
  "/usr/local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-client-ui-settings/lib/client.js";
const settingsFrom =
  `\t\t\tconst persistence = ctx.remote.$host.isLoopback ? "host" : "memory";`;
const settingsTo = `\t\t\tconst persistence = "host";`;
const settingsSource = readFileSync(settingsClientFile, "utf8");
if (settingsSource.includes(settingsTo) && !settingsSource.includes(settingsFrom)) {
  console.log(`already enabled trusted remote settings in ${settingsClientFile}`);
} else if (!settingsSource.includes(settingsFrom)) {
  throw new Error(`trusted remote settings patch pattern not found in ${settingsClientFile}`);
} else {
  writeFileSync(
    settingsClientFile,
    settingsSource.replace(settingsFrom, settingsTo),
  );
  console.log(`enabled trusted remote settings in ${settingsClientFile}`);
}
