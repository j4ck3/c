// Deployment-owned routing at capability boundaries, not model instructions.
import {AsyncLocalStorage} from 'node:async_hooks';
import {readFileSync, existsSync, mkdirSync, writeFileSync, renameSync} from 'node:fs';
import {spawn} from 'node:child_process';
import {posix as path} from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
const require = createRequire('/usr/local/lib/node_modules/@deepseek-ai/dsh/package.json');
const {FsError} = await import(require.resolve('@deepseek-ai/dsh-fs'));
const helper = readFileSync(new URL('./remote-workspace-fs.py',import.meta.url),'utf8');
const home=process.env.DSH_HOME || '/home/t3/.dsh';
const mirrorBase=path.join(home,'remote-workspaces');
const legacyMirrorBase=path.join(home,'remote-ssh','workspaces');
const bindingDir=path.join(home,'remote-ssh','session-bindings');
const PREFIX='dsh-ssh-guard:';
const ACTIVE=Symbol.for('dsh.remote-workspace-guard');
const WORLD=Symbol.for('dsh.remote-workspace-world');
const quote = s => "'"+String(s).replaceAll("'","'\\''")+"'";
const inside=(p,root)=>p===root || p.startsWith(root+'/');
const hash = s=>createHash('sha256').update(s).digest('hex');

export function findBinding(cwd) {
  if (!cwd || !path.isAbsolute(cwd)) return null;
  let p=path.normalize(cwd);
  while(p!=='/') {
    const file=path.join(p,'.remote-ssh.json');
    if(existsSync(file)) {
      const info=JSON.parse(readFileSync(file,'utf8'));
      if(!info.host || !info.user || !info.remotePath) throw new Error('Remote workspace has invalid SSH metadata; local fallback is forbidden');
      return {root:p,info};
    }
    p=path.dirname(p);
  }
  if([mirrorBase,legacyMirrorBase].some(root=>inside(path.normalize(cwd),root))) throw new Error('Remote workspace SSH metadata is missing; local fallback is forbidden');
  return null;
}
function remotePath(p,b) {
  const value=String(p || b.root);
  if(inside(path.normalize(value),b.root)) return path.join(b.info.remotePath,path.relative(b.root,path.normalize(value)));
  if(path.isAbsolute(value) || value==='~' || value.startsWith('~/')) return path.normalize(value);
  return path.join(b.info.remotePath,value);
}
function shellPath(p) {
  if(p==='~') return '"$HOME"';
  if(p.startsWith('~/')) return '"$HOME"/'+quote(p.slice(2));
  return quote(p);
}
function sshArgs(b,command) {
  const p=b.info;
  if(!/^[a-zA-Z0-9_.@:-]+$/.test(p.user) || String(p.host).startsWith('-')) throw new Error('Invalid SSH workspace identity');
  const args=['-T','-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ClearAllForwardings=yes','-o','ServerAliveInterval=15','-o','ServerAliveCountMax=3','-p',String(p.port || 22)];
  if(p.keyPath) args.push('-i',p.keyPath);
  if(p.proxyJump) args.push('-J',p.proxyJump);
  args.push('--',p.user+'@'+p.host,command);
  return args;
}
async function sshRpc(b,q,signal) {
  signal?.throwIfAborted();
  const timeout=AbortSignal.timeout(60000);
  const control=signal?AbortSignal.any([signal,timeout]):timeout;
  return new Promise((resolve,reject)=>{
    const child=spawn('/usr/bin/ssh',sshArgs(b,'python3 -c '+quote(helper)),{stdio:['pipe','pipe','pipe'],signal:control});
    const out=[],err=[]; let size=0;
    child.stdout.on('data',chunk=>{size+=chunk.length;if(size>24*1024*1024) child.kill();else out.push(chunk);});
    child.stderr.on('data',chunk=>{if(err.reduce((n,v)=>n+v.length,0)<8192)err.push(chunk);});
    child.on('error',reject);
    child.stdin.on('error',()=>{});
    child.on('close',code=>{
      if(code!==0) return reject(new FsError('Remote SSH filesystem failed (no local fallback): '+Buffer.concat(err).toString().slice(0,1500),'FS_IO_ERROR'));
      try {
        const reply=JSON.parse(Buffer.concat(out).toString());
        if(!reply.ok) reject(new FsError(reply.error.message,reply.error.code));
        else resolve(reply.value);
      } catch(e) {reject(new FsError('Invalid remote filesystem response; no local fallback','FS_IO_ERROR',{cause:e}));}
    });
    child.stdin.end(JSON.stringify(q));
  });
}

export function installRemoteWorkspaceGuard(ctx) {
  if(ctx.subprocess[ACTIVE])return;
  ctx.subprocess[ACTIVE]=true;
  ctx.effect(()=>()=>{delete ctx.subprocess[ACTIVE];});
  const scope=new AsyncLocalStorage();
  const lifecycle=new AbortController();
  const rpc=(b,q,signal)=>sshRpc(b,q,signal?AbortSignal.any([signal,lifecycle.signal]):lifecycle.signal);
  ctx.effect(()=>()=>{lifecycle.abort(new Error('Remote workspace guard disposed'));});
  const savedBindings=new WeakMap();
  const targets=new Map();
  let agents;
  ctx.inject(['agents'],c=>{agents=c.agents;});
  function bindingFor(agent,seen=new Set()) {
    if(!agent || seen.has(agent)) return null;
    seen.add(agent);
    let root=savedBindings.get(agent.session);
    if(!root && agent.session?.id) {
      const file=path.join(bindingDir,hash(String(agent.session.id))+'.json');
      if(existsSync(file)) root=JSON.parse(readFileSync(file,'utf8')).root;
    }
    let b=root?findBinding(root):findBinding(agent.session?.header?.cwd);
    if(root&&!b)throw new Error('Saved remote session binding is unavailable; local fallback is forbidden');
    if(!b && agent.session?.header?.parentSession) {
      const file=path.join(bindingDir,hash(String(agent.session.header.parentSession))+'.json');
      if(existsSync(file)) {
        const inherited=JSON.parse(readFileSync(file,'utf8')).root;
        b=findBinding(inherited);
        if(!b)throw new Error('Inherited remote binding unavailable; local fallback is forbidden');
      }
    }
    if(!b && agents) {
      const parent=agents.list().find(p=>agents.isOwnedBy(agent.id,p));
      if(parent) b=bindingFor(parent,seen);
    }
    if(b && agent.session && !savedBindings.has(agent.session)) {
      savedBindings.set(agent.session,b.root);
      if(agent.session.id) {
        mkdirSync(bindingDir,{recursive:true,mode:0o700});
        const file=path.join(bindingDir,hash(String(agent.session.id))+'.json');
        const tmp=file+'.'+process.pid+'.tmp';
        writeFileSync(tmp,JSON.stringify({root:b.root}),{mode:0o600});renameSync(tmp,file);
      }
    }
    return b;
  }
  ctx.on('agent/created',({agent})=>{bindingFor(agent);});
  ctx.on('tools/execute',async(exec,next)=>{
    const binding=bindingFor(exec.agent);
    if(!binding) return next();
    // PTC orchestration stays in the harness; its nested tool calls get their
    // own scope. Existing explicit SSH tools must not be double-wrapped.
    const subprocess=['bash','glob','grep'].includes(exec.name);
    return scope.run({binding,subprocess},next);
  },{prepend:true});
  const subprocess=ctx.subprocess;
  const originalSpawn=subprocess.spawn;
  const spawnWrapped=function(spec) {
    const current=scope.getStore();
    if(!current?.subprocess) return originalSpawn.call(this,spec);
    const b=current.binding;
    const cwd=remotePath(spec.cwd || b.root,b);
    const argv=spec.argv.map((arg,i)=>i===0&&path.basename(arg)==='rg'?'rg':inside(String(arg),b.root)?remotePath(arg,b):arg);
    const args=argv.map((arg,i)=>i>0&&(arg==='~'||arg.startsWith('~/'))?shellPath(arg):quote(arg)).join(' ');
    const fallback=process.env.DSH_REMOTE_RG_FALLBACK || '/mnt/user/appdata/deepseek-tools/bin/rg';
    const exec=argv[0]==='rg'?'if command -v rg >/dev/null 2>&1; then exec '+args+'; else exec '+quote(fallback)+' '+argv.slice(1).map(arg=>arg==='~'||arg.startsWith('~/')?shellPath(arg):quote(arg)).join(' ')+'; fi':'exec '+args;
    const command='PATH="$HOME/.local/bin:$PATH"; export PATH; cd '+shellPath(cwd)+' && '+exec;
    return originalSpawn.call(this,{...spec,cwd:b.root,argv:['/usr/bin/ssh',...sshArgs(b,command)]});
  };
  subprocess.spawn=spawnWrapped;
  ctx.effect(()=>()=>{if(subprocess.spawn===spawnWrapped)subprocess.spawn=originalSpawn;});
  // Background-job callbacks may be scheduled outside the dispatch async
  // context. Carry the binding on resolved shell specs (including spreads).
  ctx.inject(['shell'],c=>{
    const shell=c.shell, resolve=shell.resolve, execute=shell.execute;
    const resolved=function(...args){
      const spec=resolve.apply(this,args), current=scope.getStore();
      return current?.subprocess?{...spec,[WORLD]:current.binding.root}:spec;
    };
    const executed=function(spec,...args){
      if(!spec[WORLD])return execute.call(this,spec,...args);
      const binding=findBinding(spec[WORLD]);
      if(!binding)throw new Error('Background remote binding missing; local fallback forbidden');
      return scope.run({binding,subprocess:true},()=>execute.call(this,spec,...args));
    };
    shell.resolve=resolved;shell.execute=executed;
    c.effect(()=>()=>{if(shell.resolve===resolved)shell.resolve=resolve;if(shell.execute===executed)shell.execute=execute;});
  });
  ctx.inject(['fs','workingDirectory','systemPrompt'],c=>{
    const fs=c.fs;
    // Production loads dsh-fs-sandbox, which exposes sandboxMode. Its fence only
    // covers local targets, so remote mutations apply the same per-call policy
    // here (see remotePolicyCheck) instead of skipping the guard entirely.
    // Skipping it previously left the Web preview and native read/write on the
    // container mirror.
    const sandboxed=fs.sandboxMode!==undefined;
    const restores=[];
    async function remotePolicyCheck(r,sandboxPolicy,signal) {
      if(!sandboxed)return;
      let service;
      try {service=c.get?.('sandboxPolicy');} catch {}
      const policy=sandboxPolicy ?? service?.resolve?.();
      const mode=policy?.mode ?? fs.sandboxMode;
      if(mode==='danger-full-access')return;
      if(mode==='read-only')throw new FsError(`cannot write "${r.path}": file access denied under read-only mode`,'FS_SANDBOX_DENIED');
      if(mode!=='workspace-write')throw new FsError(`cannot write "${r.path}": unknown sandbox mode ${mode}`,'FS_SANDBOX_DENIED');
      const root=await rpc(r.binding,{op:'resolve',path:remotePath(r.binding.root,r.binding)},signal);
      if(!inside(r.path,root))throw new FsError(`cannot write "${r.path}": file access denied under workspace-write mode`,'FS_SANDBOX_DENIED');
    }
    function wrap(name,fn) {
      const original=fs[name];
      const replacement=function(...args){return fn.call(this,original.bind(this),...args);};
      fs[name]=replacement;
      restores.push(()=>{if(fs[name]===replacement)fs[name]=original;});
    }
    function targetFor(b,p) {
      const identity=hash(JSON.stringify([b.info.profileId,b.info.host,b.info.user,b.info.port||22]));
      const key=PREFIX+identity+':'+encodeURIComponent(p);
      targets.set(key,{binding:b,path:p});
      return {targetKey:key,displayPath:p};
    }
    function lookup(target) {
      const key=String(target?.targetKey || '');
      if(!key.startsWith(PREFIX)) return null;
      const hit=targets.get(key);
      if(!hit) throw new FsError('Remote target expired; resolve it again. Local fallback forbidden.','FS_IO_ERROR');
      // Revalidate metadata even for previously resolved targets.
      const b=findBinding(hit.binding.root);
      if(!b) throw new FsError('Remote workspace binding disappeared','FS_IO_ERROR');
      return {...hit,binding:b};
    }
    wrap('resolve',async(original,p,opts={})=>{
      const b=scope.getStore()?.binding || findBinding(opts.cwd) || findBinding(p);
      if(!b) return original(p,opts);
      const cwd=remotePath(opts.cwd || c.workingDirectory.defaultDirectory || b.root,b);
      const candidate=path.isAbsolute(p) || p==='~' || p.startsWith('~/')?remotePath(p,b):path.join(cwd,p);
      const resolved=await rpc(b,{op:'resolve',path:candidate},opts.signal);
      return targetFor(b,resolved);
    });
    wrap('processPath',(original,t)=>lookup(t)?.path ?? original(t));
    wrap('processPathFromHostPath',(original,p)=>scope.getStore()?.binding?undefined:original(p));
    wrap('fileUrl',(original,t)=>{const r=lookup(t);return r?'ssh://'+r.binding.info.host+r.path:original(t);});
    wrap('contains',(original,parent,child)=>{
      const a=lookup(parent),b=lookup(child);
      if(a||b) return !!(a&&b&&a.binding.info.profileId===b.binding.info.profileId&&inside(b.path,a.path));
      return original(parent,child);
    });
    for(const op of ['stat','readText','listDir']) wrap(op,async(original,t,signal)=>{
      const r=lookup(t);if(!r)return original(t,signal);
      const value=await rpc(r.binding,{op,path:r.path},signal);
      if(op==='stat')return value ?? undefined;
      if(op==='listDir')return value.map(({path:p,...entry})=>({...entry,target:targetFor(r.binding,p)}));
      return value;
    });
    wrap('lstat',async(original,p,opts={},signal)=>{
      const b=scope.getStore()?.binding || findBinding(opts.cwd) || findBinding(p);
      if(!b)return original(p,opts,signal);
      const cwd=remotePath(opts.cwd||b.root,b);
      return (await rpc(b,{op:'lstat',path:path.isAbsolute(p)||p.startsWith('~')?remotePath(p,b):path.join(cwd,p)},signal)) ?? undefined;
    });
    wrap('streamText',async(original,t,signal)=>{
      const r=lookup(t);if(!r)return original(t,signal);
      const text=await rpc(r.binding,{op:'readText',path:r.path},signal);
      return (async function*(){yield text;})();
    });
    wrap('readBytes',async(original,t,signal,maxBytes)=>{
      const r=lookup(t);if(!r)return original(t,signal,maxBytes);
      return Buffer.from(await rpc(r.binding,{op:'readBytes',path:r.path,limit:Math.min(maxBytes??16777216,16777216)},signal),'base64');
    });
    wrap('readByteRange',async(original,t,range,signal)=>{
      const r=lookup(t);if(!r)return original(t,range,signal);
      const v=await rpc(r.binding,{op:'readByteRange',path:r.path,range},signal);return Buffer.from(v.data,'base64');
    });
    for(const op of ['writeText','editText']) wrap(op,async(original,t,value,expected,signal,...rest)=>{
      const r=lookup(t);if(!r)return original(t,value,expected,signal,...rest);
      await remotePolicyCheck(r,rest[0],signal);
      return rpc(r.binding,{op,path:r.path,[op==='writeText'?'content':'edit']:value,expected},signal);
    });
    wrap('watch',async(original,t,...args)=>{
      if(lookup(t))throw new FsError('Remote file watching is unavailable; refresh explicitly','FS_IO_ERROR');
      return original(t,...args);
    });
    // Directory changes must also execute in the bound world during prompt
    // assembly, not just inside a tool-dispatch async context.
    for(const name of ['ensure','set']) {
      const original=c.workingDirectory[name];
      const replacement=function(agent,...args){
        const binding=bindingFor(agent);
        return binding?scope.run({binding,subprocess:false},()=>original.call(this,agent,...args)):original.call(this,agent,...args);
      };
      c.workingDirectory[name]=replacement;
      restores.push(()=>{if(c.workingDirectory[name]===replacement)c.workingDirectory[name]=original;});
    }
    const originalContextText=c.workingDirectory.contextText;
    if(originalContextText) {
      const replacement=function(session){
        const b=findBinding(session.header?.cwd);
        return b?`Current remote working directory: ${JSON.stringify(remotePath(this.get(session),b))} on ${b.info.user}@${b.info.host}.`:originalContextText.call(this,session);
      };
      c.workingDirectory.contextText=replacement;
      restores.push(()=>{if(c.workingDirectory.contextText===replacement)c.workingDirectory.contextText=originalContextText;});
    }
    c.systemPrompt.context({name:'remote-workspace:binding',order:0,required:true,interpolate:false,text:context=>{
      const b=bindingFor(context.agent);
      return b?`REMOTE WORKSPACE: ${b.info.user}@${b.info.host}, root ${b.info.remotePath}. Ordinary bash, grep, glob, read, write and edit are routed automatically to this SSH target, including absolute paths. Do not add ssh yourself. The local mirror is not the execution host. SSH failure is an error; never retry the operation locally.`:'';
    }});
    c.effect(()=>()=>{for(const restore of restores.reverse())restore();});
  });
}
