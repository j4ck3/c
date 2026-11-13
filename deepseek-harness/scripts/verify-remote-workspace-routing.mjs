#!/usr/bin/env node
// Real stock tool registry + stock subprocess/bash/fs/search + installed SSH plugin.
// No model prompting or mocked SSH. Writes only unique temporary test files.
import {createRequire} from 'node:module';
import {readFileSync,readdirSync,existsSync,mkdirSync,writeFileSync,rmSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const require=createRequire('/usr/local/lib/node_modules/@deepseek-ai/dsh/package.json');
const load=async name=>import(require.resolve(name));
const {Context}=await load('@deepseek-ai/cordis');
const {ToolRuntime}=await load('@deepseek-ai/dsh-tools');
const {LocalSubprocessRuntime}=await load('@deepseek-ai/dsh-subprocess-local');
const {LocalBashExecutor}=await load('@deepseek-ai/dsh-bash-local');
const root=process.env.DSH_HOME+'/remote-workspaces';
const bases=[root,process.env.DSH_HOME+'/remote-ssh/workspaces'];
const rows=bases.flatMap(base=>readdirSync(base).filter(id=>!id.startsWith('.')&&existsSync(base+'/'+id+'/.remote-ssh.json')).map(id=>({id,mirrorPath:base+'/'+id,...JSON.parse(readFileSync(base+'/'+id+'/.remote-ssh.json','utf8'))})));
const ctx=new Context();
ctx.provide('systemPrompt',{tools(){},section(){},context(){},getSectionOrder(){return 0;},getContextOrder(){return 0;}});
ctx.provide('shellEnv',{collect(){return {};}});
const effective=new Map();
ctx.provide('sessionProjections',{register(){},stateOf:(s,key)=>key==='sandboxMode'?undefined:(effective.get(s.id)||s.header.cwd)});
ctx.plugin(LocalSubprocessRuntime);
ctx.plugin({inject:['subprocess'],apply(c){new LocalBashExecutor(c,Object.fromEntries(Object.entries({cwd:'/workspace',timeoutMs:15000,maxTimeoutMs:60000,maxOutputBytes:64000,maxSpillBytes:1048576,graceMs:1000}).map(([k,v])=>[k,{get:()=>v}])));}});
// Production base bundle mounts dsh-fs-sandbox (exposes sandboxMode), not
// dsh-fs-local. Testing fs-local hid the guard skipping the sandbox backend.
ctx.plugin((await load('@deepseek-ai/dsh-sandbox-policy')).default,{mode:process.env.TEST_MODE||'danger-full-access',workspaceRoot:'/workspace'});
ctx.plugin((await load('@deepseek-ai/dsh-fs-sandbox')).default,{cwd:'/workspace',diffBasisMaxBytes:1048576});
ctx.plugin((await load('@deepseek-ai/dsh-working-directory')).default,{defaultDirectory:'/workspace'});
ctx.plugin(ToolRuntime);
ctx.plugin((await load('@deepseek-ai/dsh-jobs-local')).default,{maxConcurrentJobsPerOwner:10,retainBytes:64000,settledRetainBytes:64000,pumpPollMs:10});
ctx.plugin(await load('@deepseek-ai/dsh-tool-jobs'),{});
ctx.plugin(await load('@deepseek-ai/dsh-tool-bash'),{enableRunInBackground:true,promoteOnTimeout:false});
ctx.plugin(await load('@deepseek-ai/dsh-tool-fs'),{read:true,readImage:false,write:true,edit:true,readLimit:1000,readMaxLineLength:2000,readMaxBytes:64000,readStreamMinSize:1000000});
ctx.plugin(await load('@deepseek-ai/dsh-tool-fs-search'),{sampleOverCapGlobResults:false,globMaxResults:100,grepMaxMatches:100,grepMaxLineBytes:1000,searchMetaMaxBytes:64000,rawOutputMaxBytes:64000,graceMs:1000,stderrMaxBytes:16000,timeoutMs:15000});
ctx.provide('workspaceRegistry',{});
ctx.provide('webServer',{register(){return ()=>{};}});
ctx.provide('settings',{register(){return {get:()=>({profiles:rows.map(r=>({...r,id:r.profileId,authMethod:'key',port:r.port||22})),workspaces:rows}),update(){}};}});
const parents=new Map(),live=[];
ctx.provide('agents',{list:()=>live,get:id=>live.find(a=>a.id===id),isOwnedBy:(id,p)=>parents.get(id)===p});
ctx.plugin(await import('/home/t3/.dsh/profiles/web/node_modules/@zhangfengshun/dsh-remote-ssh/lib/index.js'),{});
if(process.env.WITH_GUARD==='1') {
 const {installRemoteWorkspaceGuard}=await import('/opt/dsh/patches/remote-workspace-guard.mjs');
 ctx.plugin({inject:['tools','subprocess'],apply:installRemoteWorkspaceGuard});
}
await new Promise(r=>setTimeout(r,150));
const freshAgent=cwd=>{const id='routing-test-'+randomUUID();const agent={ctx,id,inject(){},session:{id,header:{cwd},append(type,data){if(type==='working-directory/change')effective.set(id,data.cwd);}}};live.push(agent);return agent;};
async function call(agent,name,args,allowError=false) {
 const result=await ctx.tools.execute({name,arguments:args,agent,callId:randomUUID(),signal:AbortSignal.timeout(45000)});
 if(!allowError)assert.equal(result.isError,false,`${name}: ${JSON.stringify(result.error)}`);
 return result;
}
const bash=(a,command,extra={})=>call(a,'bash',{command,description:'Remote routing regression test',...extra});
const text=r=>r.value?.stdout?.text ?? r.content?.filter(c=>c.type==='text').map(c=>c.text).join('\n') ?? '';
const chosen=process.argv.slice(2);
try {
 for(const row of rows.filter(r=>!chosen.length||chosen.includes(r.id))) {
  const agent=freshAgent(row.mirrorPath);
  assert.ok(ctx.tools.get('remote_ssh_exec',agent),'Installed SSH plugin must be mounted');
  const expected=await call(agent,'remote_ssh_exec',{command:'hostname; pwd'});
  const expectedText=expected.value?.stdout;
  assert.ok(expected.value?.ok,`SSH fixture unreachable: ${row.host}: ${expected.value?.error || JSON.stringify(expected.error)}`);
  const actual=await bash(agent,'hostname; pwd');
  assert.equal(text(actual).trimEnd(),expectedText.trimEnd(),'Ordinary bash is not targeting its SSH workspace');
  console.log(`PASS ${row.host}: stock bash host and workspace match explicit SSH`);
  const bg=await bash(agent,'sleep 0.1; hostname; pwd',{run_in_background:true});
  assert.equal(bg.value.kind,'background');
  const output=await call(agent,'job_output',{job_id:bg.value.jobId,wait:true});
  assert.ok(JSON.stringify(output).includes(expectedText.split('\n')[0]));
  assert.ok(!JSON.stringify(output).includes('deepseek-harness\\n'));
  console.log(`PASS ${row.host}: native background jobs retain the SSH binding`);
  // Immutable session binding must survive a durable/effective cwd change.
  await ctx.workingDirectory.set(agent,'/tmp',AbortSignal.timeout(15000));
  const changed=await bash(agent,'hostname; pwd');
  assert.equal(text(changed).split('\n')[0],expectedText.split('\n')[0]);
  assert.equal(text(changed).split('\n')[1],'/tmp');
  effective.delete(agent.id);
  console.log(`PASS ${row.host}: changed cwd stays on the SSH target`);
  const dir='.dsh-routing-test-'+randomUUID();
  const file=dir+'/probe.txt';
  const local=row.mirrorPath+'/'+file;
  await call(agent,'remote_ssh_exec',{command:`mkdir ${dir}`});
  try {
   await call(agent,'write',{file_path:file,content:'REMOTE_ONE\n'});
   assert.equal(existsSync(local),false,'Native write must not write the container mirror');
   mkdirSync(row.mirrorPath+'/'+dir,{recursive:true});writeFileSync(local,'STALE_LOCAL_DECOY\n');
   const read=await call(agent,'read',{file_path:file});
   assert.ok(JSON.stringify(read).includes('REMOTE_ONE'),'Read must fetch remote contents, not the local decoy');
   assert.ok(!JSON.stringify(read).includes('STALE_LOCAL_DECOY'));
   await call(agent,'edit',{file_path:file,old_string:'REMOTE_ONE',new_string:'REMOTE_TWO'});
   const verify=await call(agent,'remote_ssh_exec',{command:`cat ${file}`});
   assert.equal(verify.value.stdout.trimEnd(),'REMOTE_TWO');
   assert.equal(readFileSync(local,'utf8'),'STALE_LOCAL_DECOY\n','Native edit must not modify the local decoy');
   const target=await ctx.fs.resolve(local);
   const observed=await ctx.fs.stat(target);
   await call(agent,'remote_ssh_exec',{command:`printf 'REMOTE_TWO changed externally\\n' > ${file}`});
   await assert.rejects(ctx.fs.writeText(target,'MUST_NOT_OVERWRITE',{kind:'replaceIfVersion',version:observed.version}),e=>e.code==='FS_STALE_VERSION');
   const grep=await call(agent,'grep',{pattern:'REMOTE_TWO',path:dir});
   assert.ok(JSON.stringify(grep).includes('REMOTE_TWO'));
   const glob=await call(agent,'glob',{pattern:'*.txt',path:dir});
   assert.ok(JSON.stringify(glob).includes('probe.txt'));
   console.log(`PASS ${row.host}: stock read/write/edit/grep/glob use remote data, never the mirror; stale overwrites blocked`);
  } finally {
   await call(agent,'remote_ssh_exec',{command:`rm -rf -- ${dir}`});
   rmSync(row.mirrorPath+'/'+dir,{recursive:true,force:true});
  }
  // An inherited remote child with a non-mirror cwd must stay bound on resume.
  const child=freshAgent('/tmp');parents.set(child.id,agent);
  const childResult=await bash(child,'hostname');
  assert.equal(text(childResult).trim(),expectedText.split('\n')[0]);
  parents.delete(child.id);
  const resumed={ctx,id:child.id,session:{id:child.id,header:{cwd:'/tmp'}}};
  assert.equal(text(await bash(resumed,'hostname')).trim(),expectedText.split('\n')[0]);
  const detachedChild=freshAgent('/tmp');detachedChild.session.header.parentSession=agent.id;
  assert.equal(text(await bash(detachedChild,'hostname')).trim(),expectedText.split('\n')[0]);
  console.log(`PASS ${row.host}: child-agent routing, resumed binding, and persisted parent lineage`);
  const concurrentLocal=freshAgent('/tmp');
  const [remoteRun,localRun]=await Promise.all([bash(agent,'sleep 0.1; hostname'),bash(concurrentLocal,'sleep 0.1; hostname')]);
  assert.equal(text(remoteRun).trim(),expectedText.split('\n')[0]);
  assert.equal(text(localRun).trim(),'deepseek-harness');
  console.log(`PASS ${row.host}: concurrent local and remote calls remain isolated`);
 }
 const local=freshAgent('/tmp');
 assert.equal(text(await bash(local,'hostname')).trim(),'deepseek-harness');
 console.log('PASS ordinary local sessions remain local');
 const unboundLegacy=bases[1]+'/.routing-unbound-'+randomUUID();
 mkdirSync(unboundLegacy,{recursive:true});
 try {
  const a=freshAgent(unboundLegacy);
  const r=await call(a,'bash',{command:'printf MUST_NOT_RUN_LOCALLY',description:'Unbound legacy workspace must fail closed'},true);
  assert.equal(r.isError,true,'Legacy SSH workspace without a marker must never be treated as a local session');
  console.log('PASS unbound legacy-layout workspaces fail closed');
 } finally {rmSync(unboundLegacy,{recursive:true,force:true});}
 const badRoot=root+'/.routing-offline-'+randomUUID();
 mkdirSync(badRoot,{recursive:true});
 writeFileSync(badRoot+'/.remote-ssh.json',JSON.stringify({profileId:'offline-fixture',host:'127.0.0.1',port:1,user:'nobody',remotePath:'~'}));
 try {
  const a=freshAgent(badRoot);
  const failed=await call(a,'bash',{command:'printf MUST_NOT_RUN_LOCALLY',description:'Offline SSH must fail closed'},true);
  assert.ok(failed.isError || failed.value.exitCode!==0);
  assert.ok(!text(failed).includes('MUST_NOT_RUN_LOCALLY'));
  const write=await call(a,'write',{file_path:'must-not-exist',content:'no'},true);
  assert.equal(write.isError,true);assert.equal(existsSync(badRoot+'/must-not-exist'),false);
  rmSync(badRoot+'/.remote-ssh.json');
  const missing=await call(a,'bash',{command:'printf MUST_NOT_RUN_LOCALLY',description:'Missing SSH metadata must block'},true);
  assert.equal(missing.isError,true);
  console.log('PASS offline SSH and missing metadata fail closed without local execution or writes');
 } finally {rmSync(badRoot,{recursive:true,force:true});}
} finally {
 await ctx.fiber.dispose();
 // Test bindings have no credentials and are no longer needed.
 const {createHash}=await import('node:crypto');
 for(const a of live)rmSync(process.env.DSH_HOME+'/remote-ssh/session-bindings/'+createHash('sha256').update(a.id).digest('hex')+'.json',{force:true});
}
