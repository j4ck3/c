#!/usr/bin/env node
// Regression: the Web file preview (workspaceFiles RPC -> ctx.fs) must read a
// remote workspace's files over SSH under the production filesystem backend
// (dsh-fs-sandbox), including absolute paths outside the mirror directory.
//
// Usage on Tower:
//   docker exec -i -u node deepseek-harness node --input-type=module - \
//     <workspace-id> < scripts/verify-remote-preview.mjs
import {createRequire} from 'node:module';
import {readFileSync,existsSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const require=createRequire('/usr/local/lib/node_modules/@deepseek-ai/dsh/package.json');
const load=async name=>import(require.resolve(name));
const {Context}=await load('@deepseek-ai/cordis');
const {ToolRuntime}=await load('@deepseek-ai/dsh-tools');
const {LocalSubprocessRuntime}=await load('@deepseek-ai/dsh-subprocess-local');
const {WorkspaceFiles}=await load('@deepseek-ai/dsh-api-workspace-files');
const id=process.argv[2]||'wmvd7ucf6fyco';
const mirror=process.env.DSH_HOME+'/remote-workspaces/'+id;
assert.ok(existsSync(mirror+'/.remote-ssh.json'),'workspace marker missing: '+mirror);
const info=JSON.parse(readFileSync(mirror+'/.remote-ssh.json','utf8'));
const ctx=new Context();
ctx.provide('systemPrompt',{tools(){},section(){},context(){},getSectionOrder(){return 0;},getContextOrder(){return 0;}});
ctx.provide('shellEnv',{collect(){return {};}});
ctx.provide('sessionProjections',{register(){},stateOf:()=>undefined});
ctx.plugin(LocalSubprocessRuntime);
ctx.plugin((await load('@deepseek-ai/dsh-sandbox-policy')).default,{mode:process.env.TEST_MODE||'danger-full-access',workspaceRoot:'/workspace'});
// Production base bundle loads dsh-fs-sandbox, not dsh-fs-local.
ctx.plugin((await load('@deepseek-ai/dsh-fs-sandbox')).default,{cwd:'/workspace',diffBasisMaxBytes:1048576});
ctx.plugin((await load('@deepseek-ai/dsh-working-directory')).default,{defaultDirectory:'/workspace'});
ctx.plugin(ToolRuntime);
ctx.provide('workspaceRegistry',{});
ctx.provide('webServer',{register(){return ()=>{};}});
ctx.provide('settings',{register(){return {get:()=>({profiles:[{...info,id:info.profileId,authMethod:'key',port:info.port||22}],workspaces:[{id,mirrorPath:mirror,...info}]}),update(){}};}});
ctx.provide('agents',{list:()=>[],get:()=>undefined,isOwnedBy:()=>false});
ctx.plugin(await import('/home/t3/.dsh/profiles/web/node_modules/@zhangfengshun/dsh-remote-ssh/lib/index.js'),{});
await new Promise(r=>setTimeout(r,300));
// Same object the Web preview calls; only the RPC transport is skipped.
const files=Object.create(WorkspaceFiles.prototype);
files.ctx=ctx;
files.config={maxBytes:2*1024*1024,maxFileBytes:32*1024*1024,maxLines:5000,maxEntries:2000};
const scope={sessionId:'preview-test-'+randomUUID(),workspaceRoot:mirror};
const agent={ctx,id:scope.sessionId,inject(){},session:{id:scope.sessionId,header:{cwd:mirror},append(){}}};
const tag='PREVIEW_PROBE_'+randomUUID();
const dir='/tmp/.dsh-preview-test-'+randomUUID();
const exec=async command=>{
  const r=await ctx.tools.execute({name:'remote_ssh_exec',arguments:{command},agent,callId:randomUUID(),signal:AbortSignal.timeout(30000)});
  assert.ok(r.value?.ok,'remote_ssh_exec failed: '+JSON.stringify(r.value??r.error));
  return r.value.stdout;
};
let failed=false;
try {
  const host=(await exec('hostname')).trim();
  await exec(`mkdir -p ${dir} && printf '%s\\n' ${tag} > ${dir}/probe.md`);
  assert.equal(existsSync(dir+'/probe.md'),false,'probe must not exist locally');
  for(const [label,path] of [['absolute path outside mirror',dir+'/probe.md']]) {
    try {
      const page=await files.read(scope,path,{},AbortSignal.timeout(30000));
      assert.ok(page.text.includes(tag),'preview returned wrong content');
      const bytes=await files.readBytes(scope,path,{},AbortSignal.timeout(30000));
      assert.ok(Buffer.from(bytes.data).toString().includes(tag),'byte preview returned wrong content');
      console.log(`PASS ${host}: preview reads remote ${label}`);
      if((process.env.TEST_MODE||'danger-full-access')==='workspace-write') {
        // Remote writes outside the workspace root must hit the sandbox fence.
        const target=await ctx.fs.resolve(path,{cwd:mirror});
        await assert.rejects(ctx.fs.writeText(target,'MUST_NOT_WRITE',undefined,undefined),e=>e.code==='FS_SANDBOX_DENIED');
        assert.ok((await exec(`cat ${path}`)).includes(tag),'fenced write must leave the file intact');
        console.log(`PASS ${host}: workspace-write fences remote writes outside the workspace`);
      }
    } catch(e) {
      failed=true;
      console.log(`FAIL ${host}: preview of ${label}: ${e.code||''} ${e.message}`);
    }
  }
} finally {
  await exec(`rm -rf -- ${dir}`).catch(()=>{});
  await ctx.fiber.dispose();
  const {createHash}=await import('node:crypto');
  const {rmSync}=await import('node:fs');
  rmSync(process.env.DSH_HOME+'/remote-ssh/session-bindings/'+createHash('sha256').update(scope.sessionId).digest('hex')+'.json',{force:true});
}
process.exit(failed?1:0);
