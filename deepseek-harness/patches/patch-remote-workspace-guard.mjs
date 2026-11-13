#!/usr/bin/env node
// Pin this patch to the reviewed upstream source. Never boot silently unguarded.
import {readFileSync,writeFileSync,renameSync} from 'node:fs';
const root=(process.env.DSH_HOME||'/home/t3/.dsh')+'/profiles/web/node_modules/@zhangfengshun/dsh-remote-ssh';
const version=JSON.parse(readFileSync(root+'/package.json','utf8')).version;
if(version!=='2.4.36')throw new Error('Remote workspace routing patch requires review for SSH plugin '+version);
const file=root+'/lib/index.js';
let source=readFileSync(file,'utf8');
const marker='// DSH_REMOTE_WORKSPACE_ROUTING_GUARD';
if(source.includes(marker)) {
  console.log('Remote workspace routing guard: already installed');
} else {
  const anchor='  // ---- 清理 ----';
  if(source.split(anchor).length!==2)throw new Error('Remote workspace guard patch anchor changed');
  source='import {installRemoteWorkspaceGuard} from "/opt/dsh/patches/remote-workspace-guard.mjs";\n'+source;
  source=source.replace(anchor,marker+'\n  installRemoteWorkspaceGuard(ctx);\n\n'+anchor);
  const temp=file+'.routing-guard.tmp';
  writeFileSync(temp,source,{mode:0o644});renameSync(temp,file);
  console.log('Remote workspace routing guard: installed');
}
