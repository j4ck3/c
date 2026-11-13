#!/usr/bin/env node
// Recover only explicit, unambiguous mappings saved by the former SSH plugin.
// Never copy local mirror contents to a remote target or infer an unknown host.
import {readFileSync,writeFileSync,renameSync,existsSync} from 'node:fs';
import {join,basename} from 'node:path';
import {createRequire} from 'node:module';
const require=createRequire('/usr/local/lib/node_modules/@deepseek-ai/dsh/package.json');
const yaml=require('yaml');
const home=process.env.DSH_HOME||'/home/t3/.dsh';
const legacyFile=join(home,'settings.yaml.imported');
if(!existsSync(legacyFile))process.exit(0);
const legacy=yaml.parseDocument(readFileSync(legacyFile,'utf8'),{logLevel:'silent'}).toJS()?.['remote-ssh'];
if(!legacy)process.exit(0);
const file=join(home,'profiles/web/cordis.patch.yml');
const source=readFileSync(file,'utf8');
const document=yaml.parseDocument(source,{logLevel:'silent'});
if(document.errors.length)throw new Error('Cannot migrate legacy SSH workspaces: invalid profile YAML');
const entries=document.toJS();
const configs=entries.map(x=>x.config).filter(x=>x&&!Array.isArray(x)&&Array.isArray(x.profiles)&&Array.isArray(x.workspaces));
if(configs.length!==1)throw new Error('Cannot identify the active SSH workspace config unambiguously');
const config=configs[0],additions=[],markers=[];
const base=join(home,'remote-ssh/workspaces');
for(const ws of legacy.workspaces||[]) {
  if(typeof ws.id!=='string'||!/^[a-zA-Z0-9_-]+$/.test(ws.id))continue;
  const root=join(base,ws.id);
  if(!existsSync(root))continue; // Do not resurrect deliberately removed folders.
  const server=(legacy.servers||[]).find(s=>s.id===ws.serverId);
  if(!server || server.sshArgs?.length || !ws.remotePath)continue;
  const matches=config.profiles.filter(p=>p.name===server.sshTarget||p.name===server.label||p.host===server.sshTarget);
  if(matches.length!==1)continue; // Unknown folders remain fail-closed.
  const profile=matches[0];
  const current=config.workspaces.find(w=>w.id===ws.id||w.mirrorPath===root);
  if(current&&(current.profileId!==profile.id||current.remotePath!==ws.remotePath))throw new Error('Conflicting legacy SSH mapping for '+ws.id);
  const row={id:ws.id,profileId:profile.id,title:basename(ws.remotePath)+' ('+profile.name+', legacy)',remotePath:ws.remotePath,mirrorPath:root};
  if(!current)additions.push(row);
  const marker=join(root,'.remote-ssh.json');
  const info={profileId:profile.id,host:profile.host,port:profile.port||22,user:profile.user,keyPath:profile.keyPath||'',proxyJump:profile.proxyJump==='none'?'':profile.proxyJump||'',remotePath:ws.remotePath};
  if(existsSync(marker)) {
    const previous=JSON.parse(readFileSync(marker,'utf8'));
    if(previous.profileId!==info.profileId||previous.remotePath!==info.remotePath||previous.host!==info.host)throw new Error('Conflicting legacy SSH marker for '+ws.id);
  } else markers.push({file:marker,info});
}
let updated=source;
if(additions.length) {
  const anchor='    workspaces:\n';
  if(source.split(anchor).length!==2)throw new Error('SSH workspaces YAML anchor is not unique; refusing to rewrite the profile');
  const rows=additions.map(row=>Object.entries(row).map(([key,value],i)=>(i?'        ':'      - ')+key+': '+JSON.stringify(value)).join('\n')).join('\n');
  updated=source.replace(anchor,anchor+rows+'\n');
  const check=yaml.parseDocument(updated,{logLevel:'silent'});
  if(check.errors.length)throw new Error('Legacy SSH migration produced invalid YAML');
}
if(process.argv.includes('--check')) {
  console.log(`Legacy SSH recovery needed: ${additions.length} workspace registrations, ${markers.length} SSH markers`);
  if(additions.length||markers.length)process.exitCode=1;
} else {
  // Publish metadata first. A partial failure can never enable local fallback.
  for(const {file,info}of markers){const tmp=file+'.migration.tmp';writeFileSync(tmp,JSON.stringify(info,null,2)+'\n',{mode:0o600});renameSync(tmp,file);}
  if(updated!==source){const tmp=file+'.legacy-ssh.tmp';writeFileSync(tmp,updated,{mode:0o600});renameSync(tmp,file);}
  console.log(`Legacy SSH recovery: restored ${additions.length} workspace registrations and ${markers.length} SSH markers; no user files synchronized`);
}
