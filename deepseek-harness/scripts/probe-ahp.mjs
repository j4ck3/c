import { spawn } from 'node:child_process'
import { AhpClient } from '@microsoft/agent-host-protocol/client'
import { WebSocketTransport } from '@microsoft/agent-host-protocol/ws'
import { SUPPORTED_PROTOCOL_VERSIONS } from '@microsoft/agent-host-protocol'

const host = process.argv[2] || 'htpc'
const offered = [...new Set(['0.9.0', '0.8.0', ...SUPPORTED_PROTOCOL_VERSIONS])]
console.log('offered', offered, 'host', host)

const cmd = [
  "dsh_code='code'",
  'if [ "$dsh_code" = code ] && ! command -v "$dsh_code" >/dev/null 2>&1 && [ -x "$HOME/.dsh-remote-ssh/cli/bin/code" ]; then dsh_code="$HOME/.dsh-remote-ssh/cli/bin/code"; fi',
  'exec "$dsh_code" agent host --host 127.0.0.1 --port 0 --idle-timeout 60 --server-data-dir "$HOME/.dsh-remote-ssh/server" --cli-data-dir "$HOME/.dsh-remote-ssh/cli" --verbose --new-instance',
].join('\n')

const child = spawn('ssh', ['-o', 'BatchMode=yes', '-T', host, cmd], { stdio: ['ignore', 'pipe', 'pipe'] })
let buf = ''
const endpoint = await new Promise((resolve, reject) => {
  const onData = (chunk) => {
    buf += chunk.toString()
    const m = /ws:\/\/(?:localhost|127\.0\.0\.1):(\d+)\?tkn=([A-Za-z0-9_-]+)/.exec(buf)
    if (m) resolve({ port: Number(m[1]), token: m[2] })
  }
  child.stdout.on('data', onData)
  child.stderr.on('data', onData)
  child.on('exit', (code) => reject(new Error(`ssh exited ${code}\n${buf.slice(-800)}`)))
  setTimeout(() => reject(new Error(`timeout\n${buf.slice(-800)}`)), 90_000)
})
console.log('endpoint', endpoint)

const localPort = 18_700 + Math.floor(Math.random() * 200)
const tunnel = spawn(
  'ssh',
  [
    '-o', 'BatchMode=yes',
    '-o', 'ExitOnForwardFailure=yes',
    '-T', '-N',
    '-L', `127.0.0.1:${localPort}:127.0.0.1:${endpoint.port}`,
    host,
  ],
  { stdio: 'ignore' },
)
await new Promise((r) => setTimeout(r, 1200))

try {
  const url = `ws://127.0.0.1:${localPort}?tkn=${encodeURIComponent(endpoint.token)}`
  const transport = await WebSocketTransport.connect(url)
  const client = new AhpClient(transport, { requestTimeoutMs: 30_000 })
  const init = await client.initialize({
    clientId: 'dsh-probe',
    protocolVersions: offered,
    initialSubscriptions: ['ahp-root://'],
  })
  console.log('SUCCESS protocol', init.protocolVersion)
  await client.shutdown().catch(() => {})
} catch (e) {
  console.error('FAIL', e?.message || e)
  if (e?.data) console.error('data', JSON.stringify(e.data))
  process.exitCode = 1
} finally {
  tunnel.kill()
  child.kill()
}
