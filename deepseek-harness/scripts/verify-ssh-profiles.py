#!/usr/bin/env python3
import json, subprocess

def request(host, method):
    result = subprocess.check_output(['docker','exec','deepseek-harness','curl','-sS','--max-time','10','-X','POST','-H',f'Host: {host}','-H','x-requested-with: XMLHttpRequest','-H','Content-Type: application/json','-d','{}',f'http://127.0.0.1:13080/remote-ssh/api/{method}'])
    return json.loads(result)

for host in ['127.0.0.1:13080', 'code.netbird.hjacke.com']:
    d = request(host, 'listProfiles')
    assert d.get('ok'), f'{host}: {d.get("error", {}).get("code")}'
    profiles = d['value']['profiles']
    assert {p['id'] for p in profiles} == {'pmuo1fumjhw5h','pmuo1fvsjmxj8','pmuo1fx1k3o0b','pmuo1fy5t12zi'}, 'Saved profile IDs changed'
    d = request(host, 'listWorkspaces')
    assert d.get('ok')
    workspaces = d['value']['workspaces']
    assert {w['id'] for w in workspaces} == {'wmuo2hn5j1gvx','wmuo2hzcjydy0','wmuo2ied2vdxb'}, 'Saved workspace IDs changed'
    print(f'PASS {host}: 4 original profiles, 3 original workspaces')
d = request('untrusted.invalid', 'listProfiles')
assert not d.get('ok') and d.get('error', {}).get('code') == 'forbidden'
print('PASS untrusted host rejected')
