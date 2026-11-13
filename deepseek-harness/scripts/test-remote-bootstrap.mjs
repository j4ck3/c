import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, chmodSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
const file = process.argv[2] ?? join(process.env.DSH_HOME ?? join(process.env.HOME, '.dsh'), 'profiles/web/node_modules/dsh-remote-ssh/lib/src-D6lNt3RG.js');
const source = readFileSync(file, 'utf8');
const lines = source.match(/function buildRemoteAgentHostCommand\(remoteCodeCommand\) \{[\s\S]*?\n\}/)?.[0];
if (!lines) throw Error('bootstrap function missing');
const script = lines.match(/return \[([\s\S]*?)\]\.join\("\\n"\)/)?.[1];
if (!script) throw Error('bootstrap script missing');
const js = `[${script}]`;
// Evaluate only the shipped bootstrap's static array with the quoted argument.
const quotePosix = x => `'${x.replaceAll("'", "'\"'\"'")}'`;
const remoteCodeCommand = 'code';
const shell = Function('quotePosix', 'remoteCodeCommand', `return ${js}.join('\\n')`)(quotePosix, remoteCodeCommand);
const dir = mkdtempSync(join(tmpdir(), 'dsh-bootstrap-'));
try {
  mkdirSync(join(dir,'bin'), { recursive: true });
  mkdirSync(join(dir,'.dsh-remote-ssh/cli/bin'), { recursive: true });
  const broken = join(dir,'bin/code');
  writeFileSync(broken, '#!/bin/sh\necho "spawn /usr/lib/electron42/bin/code-tunnel-oss ENOENT" >&2\nexit 1\n');
  chmodSync(broken, 0o755);
  const good = join(dir,'.dsh-remote-ssh/cli/bin/code');
  writeFileSync(good, '#!/bin/sh\necho PRIVATE_CLI_SELECTED\n');
  chmodSync(good, 0o755);
  const result = spawnSync('/bin/sh', ['-c', shell], { env: { ...process.env, HOME: dir, PATH: `${join(dir,'bin')}:${process.env.PATH}` }, encoding: 'utf8', timeout: 5000 });
  const pass = result.status === 0 && result.stdout.includes('PRIVATE_CLI_SELECTED') && !result.stderr.includes('ENOENT');
  console.log(pass ? 'PASS private CLI selected over broken PATH code' : `FAIL exact symptom: ${result.stderr.trim()} (exit ${result.status})`);
  process.exitCode = pass ? 0 : 1;
} finally { rmSync(dir, {recursive: true, force: true}); }
