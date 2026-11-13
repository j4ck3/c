#!/usr/bin/env python3
"""Read-only plugin checks. Never print account data or credentials."""
import json, subprocess, sys, re
from pathlib import Path
baseline = Path(__file__).with_name('upgrade-baseline.json')

logs = subprocess.check_output(['docker','logs','--tail','2000','deepseek-harness'], stderr=subprocess.STDOUT).decode()
tokens = re.findall(r'https?://[^\s]+[?&]token=([A-Za-z0-9_-]+)', logs)
if tokens:
    subprocess.check_call(['docker','exec','deepseek-harness','curl','-sS','-o','/dev/null','-c','/tmp/upgrade-check-cookies','http://127.0.0.1:13080/?token='+tokens[-1]])

def request(path, payload, host='127.0.0.1:13080'):
    raw = subprocess.check_output(['docker','exec','deepseek-harness','curl','-sS','-b','/tmp/upgrade-check-cookies','--max-time','45','-X','POST','-H',f'Host: {host}','-H','x-requested-with: XMLHttpRequest','-H','Content-Type: application/json','-d',json.dumps(payload),f'http://127.0.0.1:13080{path}'])
    return json.loads(raw)

snapshot = {}
saved = {}
for method, key in [('listProfiles','profiles'),('listWorkspaces','workspaces')]:
    for host in ['127.0.0.1:13080','code.netbird.hjacke.com']:
        d = request('/remote-ssh/api/'+method, {}, host)
        assert d.get('ok'), (method,host,d.get('error',{}).get('code'))
        ids = sorted(row['id'] for row in d['value'][key])
        snapshot[key] = ids
        saved[key] = d['value'][key]
        print(f'PASS {host}: {len(ids)} saved {key}')
d = request('/remote-ssh/api/listProfiles', {}, 'untrusted.invalid')
assert not d.get('ok') and d.get('error',{}).get('code') == 'forbidden'
print('PASS SSH untrusted host rejected')
if len(sys.argv)>1:
    if sys.argv[1]=='save':
        with baseline.open('w') as f: json.dump(snapshot,f)
    else:
        with baseline.open() as f: assert snapshot == json.load(f), 'Saved IDs changed'
        print('PASS all saved profile/workspace IDs preserved')
if 'live' in sys.argv:
    reachable = set()
    for profile in saved['profiles']:
        d = request('/remote-ssh/api/testConnection', {'id':profile['id']})
        good = d.get('ok') and d.get('value',{}).get('ok')
        if good: reachable.add(profile['id'])
        print(f"{'PASS' if good else 'UNREACHABLE'} SSH plugin connection: {profile.get('name',profile['id'])}")
    for ws in saved['workspaces']:
        if ws['profileId'] not in reachable:
            print(f"SKIP offline workspace: {ws['id']}")
            continue
        d = request('/remote-ssh/api/listDir', {'profileId':ws['profileId'], 'path':ws['remotePath']})
        assert d.get('ok') and d.get('value',{}).get('ok'), ('listDir', ws['id'])
        d = request('/remote-ssh/api/remoteExec', {'profileId':ws['profileId'], 'command':'printf __UPGRADE_SSH_OK__'})
        assert d.get('ok') and d.get('value',{}).get('ok') and '__UPGRADE_SSH_OK__' in d['value'].get('stdout',''), ('remoteExec',ws['id'])
        print(f"PASS workspace directory listing and remote shell: {ws['id']}")
for provider in ['codex','claude']:
    method = 'subscriptions-auth.status'
    d = request('/api/'+method, {'type':'client-request','rpcId':'upgrade-check','method':method,'payload':{'provider':provider}})
    result = d.get('result',{})
    assert result.get('ok'), (provider, result.get('error',{}).get('code'))
    value = result.get('value',{}).get('providers',{}).get(provider,{})
    assert value.get('accounts'), f'{provider} login missing'
    print(f"PASS {provider} status RPC: accounts={len(value.get('accounts',[]))}, busy={value.get('busy')}, clientVersion={value.get('clientVersion',{}).get('version','n/a')}")
