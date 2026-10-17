#!/usr/bin/env node
// Shared release-only state machine. Durable identity lives in Git metadata;
// remote facts are re-read on every resume. No general PR merge authorization.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {isShipped, hasNoNotesReason, hasAddedNotes} from './release-notes-gate.mjs';
import {atomicWrite,loadOrDegrade,claimExclusive} from './lib/runtime-file.mjs';

// Canonical path identity: Git for Windows prints forward slashes while Node
// realpaths use backslashes (and win32 paths are case-insensitive).
export function samePath(a,b,platform=process.platform) {
  const norm=p=>{let n=String(p).replace(/\\/g,'/').replace(/\/+$/,'');if(platform==='win32')n=n.toLowerCase();return n;};
  return norm(a)===norm(b);
}
export function worktreeBlock(porcelain,wt,platform=process.platform) {
  return porcelain.split('\n\n').find(block=>block.split('\n').some(l=>l.startsWith('worktree ')&&samePath(l.slice(9),wt,platform)));
}
// Tag shape the publication workflow (release.yml) accepts: v?[0-9][^\s]*
export function validTagVersion(v) {return /^v?[0-9]\S*$/.test(String(v||''));}
const here=path.dirname(fileURLToPath(import.meta.url));
const argv=process.argv.slice(2);
let version='',root='',auditFile='',auditOnly=false,onlineAudit=false,confirmed=false;
for(let i=0;i<argv.length;i++) {
  if(argv[i]==='--version')version=argv[++i];
  else if(argv[i]==='--root')root=argv[++i];
  else if(argv[i]==='--confirm') confirmed=true;
  else if(argv[i]==='--online') onlineAudit=true;
  else if(argv[i]==='--audit') {auditOnly=true;auditFile=argv[++i];}
  else throw Error(`Unknown release-finish argument ${argv[i]}`);
}
root=root||process.cwd();
let journal,record,claimPath,claimToken;
const maxWait=Number(process.env.AAI_RELEASE_WAIT_SECONDS||3600);
const interval=Number(process.env.AAI_RELEASE_POLL_SECONDS||15);
function refuse(cause,detail) {const e=new Error(detail);e.causeName=cause;throw e;}
// Not a refusal: the release is progressing remotely (exit 8, the gh pending code); resume re-reads it.
function pending(cause,detail) {const e=new Error(detail);e.causeName=cause;e.pending=true;throw e;}
function command(exe,args,cwd=root,allowFailure=false,timeout=60000,env={}) {
 const r=spawnSync(exe,args,{cwd,encoding:'utf8',timeout,maxBuffer:8*1024*1024,env:exe==='git'?{...process.env,GIT_NO_LAZY_FETCH:'1',...env}:{...process.env,...env}});
 if(!allowFailure&&(r.error||r.status!==0))refuse(exe==='gh'?'github-command':'git-command',`${exe} ${args.join(' ')}: ${r.error?.message||r.stderr?.trim()||`exit ${r.status}`}`);
 return r;
}
function git(...args){return command('git',args).stdout.trim();}
function gh(...args){return command('gh',args).stdout.trim();}
function json(...args){const s=gh(...args);try{return JSON.parse(s);}catch{refuse('github-data',`Invalid JSON for gh ${args.join(' ')}`);}}
function sha(value,name){if(!/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(value||''))refuse('empty-sha',`${name} did not return a full SHA`);return value;}
function privateFile(write){const prior=process.umask(0o077);try{return write();}finally{process.umask(prior);}}
function atomicSave(){privateFile(()=>atomicWrite(journal,JSON.stringify(record,null,2)+'\n'));}
function journalShape(value){
 return value!==null&&typeof value==='object'&&!Array.isArray(value)&&
 ['version','repo','origin','base','baseRef','baseHead','branch','notes','content','stage'].every(k=>typeof value[k]==='string'&&value[k].length>0)&&
 /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(value.baseHead)&&
 [value.head,value.merge].every(v=>v===null||/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(v||''))&&
 (value.pr===null||Number.isSafeInteger(value.pr)&&value.pr>0)&&
 ['initialized','worktree','payload','prepared','pushed','pr','merged','workflow','verified','remote-deleted','local-deleted','synced'].includes(value.stage);
}
function claimShape(value){return value!==null&&typeof value==='object'&&Number.isSafeInteger(value.pid)&&value.pid>0&&typeof value.host==='string'&&/^[a-f0-9]{32}$/.test(value.token||'')&&value.version===version;}
function deadOwner(owner){
 if(owner.host!==os.hostname())return false;
 return !processAlive(owner.pid);
}
function removeOwnClaim(file,token){
 const current=loadOrDegrade(file,{isShape:claimShape});
 if(current.status==='ok'&&current.data.token===token)fs.unlinkSync(file);
}
function exclusiveRunClaim(file,depth=0){
 const owner={token:crypto.randomBytes(16).toString('hex'),pid:process.pid,host:os.hostname(),version};
 const claimed=privateFile(()=>claimExclusive(file,JSON.stringify(owner)+'\n'));
 if(claimed.status!=='held')return {...claimed,token:owner.token};
 const old=loadOrDegrade(file,{isShape:claimShape});
 if(old.status!=='ok'||!deadOwner(old.data)||depth>=3)return {status:'held'};
 // One exclusive guard per dead ownership generation serializes reclaim.
 // A crashed reclaimer is recovered through another generation guard, bounded
 // to keep path length finite. Live/foreign/corrupt owners never expire by age.
 const guard=file+'.reclaim.'+old.data.token;const right=exclusiveRunClaim(guard,depth+1);
 if(right.status!=='claimed')return right;
 try{
  const fresh=loadOrDegrade(file,{isShape:claimShape});
  if(fresh.status==='ok'&&fresh.data.token===old.data.token&&deadOwner(fresh.data))fs.unlinkSync(file);
  const next=privateFile(()=>claimExclusive(file,JSON.stringify(owner)+'\n'));
  return {...next,token:owner.token};
 }finally{removeOwnClaim(guard,right.token);}
}
function claimRun(){
 claimPath=journal+'.claim';const held=exclusiveRunClaim(claimPath);
 if(held.status==='held')refuse('release-busy','Another confirmation owns this version, or its owner cannot safely be proven dead; retry when the owner finishes');
 if(held.status!=='claimed')refuse('release-claim',`Cannot exclusively own release: ${held.code||'unknown error'}`);
 claimToken=held.token;
}
function releaseClaim(){if(claimToken)removeOwnClaim(claimPath,claimToken);}
function githubOrigin(origin){
 const scp=/^git@github\.com:([\w.-]+\/[\w.-]+?)(?:\.git)?$/.exec(origin);if(scp)return scp[1];
 let url;try{url=new URL(origin);}catch{return null;}
 if(!['https:','ssh:'].includes(url.protocol)||url.hostname!=='github.com'||url.port||url.search||url.hash)return null;
 const match=/^\/([\w.-]+\/[\w.-]+?)(?:\.git)?$/.exec(url.pathname);return match?.[1]||null;
}
function stage(name){record.stage=name;atomicSave();console.log(`release: ${name}`);if(process.env.AAI_RELEASE_TEST_STOP_AFTER===name)refuse('interrupted',`Test interruption after ${name}`);}
function remoteHead(ref){return git('ls-remote','origin',ref).split(/\s/)[0]||'';}
function trim(s){return s.replace(/\r\n/g,'\n').trim();}
function rollup(source) {
 const newline=source.endsWith('\n');const lines=source.replace(/\r\n/g,'\n').split('\n');if(newline)lines.pop();
 const first=lines.findIndex(l=>/^## \[/.test(l));if(first<0)refuse('empty-notes','No rollable entries');
 const heads=[];for(let i=first;i<lines.length;i++)if(/^## /.test(lines[i]))heads.push(i);heads.push(lines.length);
 const sections=[];for(let k=0;k<heads.length-1;k++){
  const text=lines.slice(heads[k],heads[k+1]);const heading=text[0];
  if(/^## \[unreleased\]/.test(heading)){
   if(/^## \[unreleased\]\s*$/.test(heading)&&text.slice(1).every(l=>!l.trim()))continue;
   if(!/^## \[unreleased\] — \S/.test(heading)||!text.slice(1).some(l=>l.trim()))refuse('malformed-notes','Malformed or empty unreleased entry');
   sections.push({entry:true,text:[heading.replace('[unreleased]',`[${version}]`),...text.slice(1)]});
  }else sections.push({entry:false,text});
 }
 if(!sections.some(s=>s.entry))refuse('empty-notes','No rollable entries');
 const notes=sections.filter(s=>s.entry).flatMap(s=>s.text).join('\n').trim();
 const ordered=[...sections.filter(s=>s.entry),...sections.filter(s=>!s.entry)];
 return {content:[...lines.slice(0,first),'## [unreleased]','',...ordered.flatMap(s=>s.text)].join('\n')+(newline?'\n':''),notes};
}
function historyBoundary(head,online){
 if(git('rev-parse','--is-shallow-repository')!=='false')refuse('notes-history','Complete release history is required; obtain full history before retrying');
 const local=online?null:command('git',['show-ref','--tags','--dereference'],root,true);
 if(local&&(local.error||![0,1].includes(local.status)))refuse('notes-history','Cannot read local release tags');
 const snapshot=online?git('ls-remote','--tags','origin'):local.stdout.trim();
 const tags=new Map(),peeled=new Map();
 for(const line of snapshot.split('\n').filter(Boolean)){
  const match=/^([a-f0-9]{40}|[a-f0-9]{64})\s+(refs\/tags\/.+?)(\^\{\})?$/.exec(line);
  if(!match)refuse('notes-history','Malformed release tag history');
  // Only release tags (release.yml cuts tags named by its 'v?[0-9]' commit-message pattern) bound the audit.
  if(!/^refs\/tags\/v?[0-9]/.test(match[2]))continue;
  (match[3]?peeled:tags).set(match[2],match[1]);
 }
 let previous='',distance=Infinity;
 for(const [ref,object] of tags){
  const commit=peeled.get(ref)||object;
  const kind=command('git',['cat-file','-t',commit],root,true);
  if(kind.status===0&&kind.stdout.trim()!=='commit')continue;
  if(command('git',['cat-file','-e',commit+'^{commit}'],root,true).status!==0)refuse('notes-history',`Release history for ${ref} is unavailable; obtain its objects before retrying`);
  const ancestor=command('git',['merge-base','--is-ancestor',commit,head],root,true);
  if(ancestor.error||![0,1].includes(ancestor.status))refuse('notes-history',`Cannot establish release ancestry for ${ref}`);
  if(ancestor.status===0){const count=Number(git('rev-list','--count',commit+'..'+head));if(!Number.isSafeInteger(count))refuse('notes-history','Invalid release history length');if(count<distance){distance=count;previous=commit;}}
 }
 // A genuine first release still audits all shipped changes in the full graph.
 command('git',['rev-list','--count',head]);
 return {previous,snapshot};
}
// A PR's own diff added rollable unreleased notes (shared classifier) that survive in the rolled notes.
function addedRolledNotes(commit,parents,notes){
 const range=parents.length>1?[parents[1],commit]:['--root',commit];
 const patch=command('git',parents.length>1?['diff','--no-ext-diff','--no-textconv','--no-renames','--ignore-space-at-eol','--unified=0',...range,'--','CHANGELOG.md']:['diff-tree','-p','--root','--no-commit-id','--no-ext-diff','--no-textconv','--no-renames','--ignore-space-at-eol','--unified=0',commit,'--','CHANGELOG.md']).stdout;
 const content=command('git',['show',`${commit}:CHANGELOG.md`],root,true);
 if(content.status!==0||!hasAddedNotes(content.stdout,patch))return false;
 // The PR's own added entry heading, rewritten to this version, must survive as a rolled heading.
 // Preview audits (--audit) run without --version and compare headings regardless of the version bracket.
 const norm=l=>l.trim().replace(/\s+/g,' ');
 const key=l=>version?norm(l):norm(l).replace(/^## \[[^\]]*\]/,'##');
 const rolled=new Set(notes.split('\n').filter(l=>/^## /.test(l)).map(key));
 return patch.split('\n').some(l=>/^\+## \[unreleased\] — \S/.test(l)&&rolled.has(key(l.slice(1).replace('## [unreleased]',`## [${version}]`))));
}
function audit(notes,online,head) {
 const history=historyBoundary(head,online);
 const lines=git('log','--format=%H%x09%s',history.previous?`${history.previous}..${head}`:head).split('\n').filter(Boolean);const missing=[];
 const number=subject=>{const tokens=[...subject.matchAll(/\((?:[\w.-]+\/[\w.-]+)?#(\d+)\)/g)];const last=tokens[tokens.length-1];const merge=subject.match(/^Merge pull request #(\d+)/);return {last,merge};};
 // Commits reachable from M^2 but not M^1 of a numbered merge M belong to that PR; M's own audit (diff vs M^1) covers them.
 const covered=new Set();
 for(const line of lines){const [commit,subject]=line.split('\t');const {last,merge}=number(subject);if(!last&&!merge)continue;
  const parents=git('rev-list','--parents','-n','1',commit).split(' ');
  if(parents.length>2)for(const c of git('rev-list',`${parents[1]}..${parents[2]}`).split('\n').filter(Boolean))covered.add(c);}
 for(const line of lines){const [commit,subject]=line.split('\t');
 if(covered.has(commit))continue;
 const {last,merge}=number(subject);
 let numbered=Boolean(last||merge);
 let n=last?last[1]:merge?merge[1]:'',title=last?subject.slice(0,last.index).trim():subject;
 const parents=git('rev-list','--parents','-n','1',commit).split(' ');
 // An unnumbered merge commit adds nothing of its own; the commits it merged are in this range and audited individually.
 if(!numbered&&parents.length>2)continue;
 const diff=parents.length>1?['diff','--raw','-z','--no-renames','--no-ext-diff',parents[1],commit,'--']:['diff-tree','--root','--no-commit-id','-r','--raw','-z','--no-renames','--no-ext-diff',commit,'--'];
 const raw=command('git',diff).stdout.split('\0');
 const files=[];let shipped=false;
 for(let i=0;i<raw.length&&raw[i];i+=2){
  const modes=/^:(\d+) (\d+) \S+ \S+ \S+$/.exec(raw[i]);
  if(!modes||raw[i+1]===undefined)refuse('notes-history','Malformed Git changed-path modes');
  files.push(raw[i+1]);shipped ||= isShipped(raw[i+1],modes[1])||isShipped(raw[i+1],modes[2]);
 }
 if(!shipped)continue;
 // A preceding release cut has no new shipped behavior; validate its payload.
 if(/^chore\(release\): /.test(subject)&&files.every(f=>['CHANGELOG.md','docs/ai/AAI_VERSION.md'].includes(f)))continue;
 if(!numbered&&online&&parents.length===2){
  // A rebase-merged PR leaves unnumbered commits; GitHub knows which merged PR each belongs to.
  const r=command('gh',['api','repos/{owner}/{repo}/commits/'+commit+'/pulls'],root,true);
  let prs=[];if(!r.error&&r.status===0)try{prs=JSON.parse(r.stdout);}catch{}
  const hit=Array.isArray(prs)?prs.find(p=>p&&Number.isSafeInteger(p.number)&&p.merged_at):null;
  if(hit){numbered=true;n=String(hit.number);title=typeof hit.title==='string'?hit.title:subject;}
 }
 if(!numbered){
  // A direct or rebase-merged commit has no PR number: its own added notes or its message body must cover it.
  if(files.includes('CHANGELOG.md')&&addedRolledNotes(commit,parents,notes))continue;
  if(hasNoNotesReason(git('show','-s','--format=%B',commit)))continue;
  missing.push(`${commit.slice(0,12)} ${subject} (no PR number; add notes or a no-notes: line to the commit message)`);continue;
 }
 if(new RegExp(`(?:#|/)${n}(?![0-9])`).test(notes)||notes.includes(title))continue;
 if(files.includes('CHANGELOG.md')&&addedRolledNotes(commit,parents,notes))continue;
 if(online){const pr=json('pr','view',n,'--json','body,files');if(!Array.isArray(pr.files)||typeof pr.body!=='string')refuse('notes-history',`Unknown changed files/body for PR #${n}`);if(hasNoNotesReason(pr.body))continue;}
 missing.push(`#${n} ${title}`);
 }
 if(online&&git('ls-remote','--tags','origin')!==history.snapshot)refuse('notes-history','Remote release tags moved during audit; retry confirmation');
 return missing;
}
const fields='number,url,title,baseRefName,headRefName,headRefOid,state,mergeCommit,headRepository,isCrossRepository';
function identity(pr){
 if(!pr||pr.baseRefName!==record.base||pr.headRefName!==record.branch||pr.headRefOid!==record.head||pr.title!==`chore(release): ${version}`||pr.isCrossRepository||pr.headRepository?.nameWithOwner!==record.repo||!/^https:\/\/github\.com\//.test(pr.url||''))refuse('identity','Release PR identity does not match repository/version/base/branch/pushed head');
 if(record.pr&&pr.number!==record.pr)refuse('identity','Release PR number changed');
 return pr;
}
function boundedPoll(read,ready,cause){const end=Date.now()+maxWait*1000;for(;;){const v=read();if(ready(v))return v;if(Date.now()>=end)refuse(cause,'Bounded wait expired');Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,interval*1000);}}
// Keep the expected-old base ref locked while updating its checkout. HEAD is not
// locked: the base index.lock (baseIndexClaim) keeps porcelain checkouts out, and
// syncBase re-verifies HEAD and the ref after the update.
async function baseTransaction(cwd,ref,oldHead,newHead){
 const child=spawn('git',['update-ref','--stdin'],{cwd,env:{...process.env,GIT_NO_LAZY_FETCH:'1'},stdio:['pipe','pipe','pipe']});
 let output='',errors='',failure=null;const waiters=new Set();
 const wake=()=>{for(const fn of waiters)fn();};
 child.stdout.on('data',b=>{output+=b;wake();});child.stderr.on('data',b=>{errors+=b;});
 child.on('error',e=>{failure=e.message;wake();});child.stdin.on('error',e=>{failure=e.message;wake();});
 const closed=new Promise(resolve=>child.on('close',code=>{failure ||= `transaction exited ${code}: ${errors.trim()}`;wake();resolve(code);}));
 async function send(text,ack){
  const offset=output.length;
  const ready=new Promise((resolve,reject)=>{
   const check=()=>{if(output.slice(offset).includes(ack+'\n')){cleanup();resolve();}else if(failure){cleanup();reject(new Error(failure));}};
   const timer=setTimeout(()=>{cleanup();child.kill();reject(new Error('Base ref transaction timed out'));},60000);
   const cleanup=()=>{clearTimeout(timer);waiters.delete(check);};waiters.add(check);check();
  });child.stdin.write(text+'\n');await ready;
 }
 try{await send(`start\nupdate ${ref} ${newHead} ${oldHead}\nprepare`,'prepare: ok');}
 catch(e){child.stdin.end();await closed;refuse('base-transaction',e.message);}
 return {async commit(){await send('commit','commit: ok');child.stdin.end();const code=await closed;if(code!==0)refuse('base-transaction',errors||`exit ${code}`);},async abort(){if(!failure){try{await send('abort','abort: ok');}catch{child.kill();}}child.stdin.end();await closed;}};
}
function baseIndexShape(o){return o&&o.kind==='aai-release-base-index'&&Number.isSafeInteger(o.pid)&&o.pid>0&&typeof o.host==='string'&&/^[a-f0-9]{32}$/.test(o.token||'')&&['claimed','updating','updated'].includes(o.phase)&&[o.version,o.repo,o.base].every(v=>typeof v==='string'&&v.length)&&[o.old,o.merge].every(v=>/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(v||''))&&/^[a-f0-9]{64}$/.test(o.indexHash||'')&& (o.worker===null||Number.isSafeInteger(o.worker)&&o.worker>0);}
// An exited-but-unreaped child (zombie) still answers kill(pid,0); containers without a reaping init leave
// orphaned workers in that state, so state Z/X counts as dead.
export function processAlive(pid,platform=process.platform){
 try{process.kill(pid,0);}catch(e){return e.code!=='ESRCH';}
 if(platform==='win32')return true;
 let state='';
 try{state=fs.readFileSync(`/proc/${pid}/stat`,'utf8').replace(/^.*\) /s,'').slice(0,1);}
 catch{const r=spawnSync('ps',['-o','stat=','-p',String(pid)],{encoding:'utf8'});if(r.status===0)state=(r.stdout||'').trim().slice(0,1);else if(r.status===1&&!(r.stdout||'').trim())return false;}
 return !['Z','X'].includes(state);
}
function baseIndexClaim(index,cwd,ref){
 const file=index+'.lock',hash=()=>crypto.createHash('sha256').update(fs.readFileSync(index)).digest('hex');
 let owner={kind:'aai-release-base-index',pid:process.pid,host:os.hostname(),token:crypto.randomBytes(16).toString('hex'),phase:'claimed',worker:null,version,repo:record.repo,base:ref,old:command('git',['rev-parse',ref],cwd).stdout.trim(),merge:record.merge,indexHash:hash()};
 const claimed=claimExclusive(file,JSON.stringify(owner)+'\n');let recovered=false;
 if(claimed.status==='held'){
  const saved=loadOrDegrade(file,{isShape:baseIndexShape});
  if(saved.status!=='ok'||!deadOwner(saved.data)||saved.data.version!==version||saved.data.repo!==record.repo||saved.data.base!==ref||saved.data.merge!==record.merge||saved.data.worker&&saved.data.phase!=='updated'&&processAlive(saved.data.worker))refuse('base-busy','Registered base index lock has an unknown, live or foreign owner; preserve it and retry after its owner finishes');
  owner=saved.data;const privateIndex=index+'.aai-release-'+owner.token;
  if(![owner.indexHash,owner.updatedHash].includes(hash())||owner.phase==='updating'||owner.phase==='updated'&&owner.result!==0)refuse('base-busy','Interrupted base index update cannot be safely recovered; preserve its lock and private index for Git recovery');
  // Native ref transactions release their locks when their parent's pipe closes.
  for(const name of ['HEAD',ref])if(fs.existsSync(path.resolve(cwd,command('git',['rev-parse','--git-path',name],cwd).stdout.trim())+'.lock'))refuse('base-busy','Native Git ref transaction still owns the registered base');
  if(owner.phase==='updated'){if(!fs.existsSync(privateIndex)){if(hash()!==owner.updatedHash||command('git',['rev-parse',ref],cwd).stdout.trim()!==record.merge)refuse('base-busy','Interrupted base private index is unavailable');fs.copyFileSync(index,privateIndex);}recovered=true;}
  owner.pid=process.pid;owner.worker=null;atomicWrite(file,JSON.stringify(owner)+'\n');
 }else if(claimed.status!=='claimed')refuse('base-busy',`Cannot own registered base index: ${claimed.code||claimed.status}`);
 const privateIndex=index+'.aai-release-'+owner.token;
 if(!recovered)fs.copyFileSync(index,privateIndex);
 return {file,privateIndex,owner,recovered};
}
async function updateBaseTree(lock,cwd,oldHead){
 // The worker waits for permission until its PID is durably recorded. If the
 // helper is killed, this PID remains live through the native Git operation;
 // a resume never reclaims the index while that operation can still mutate it.
 const source=`import fs from 'node:fs';import crypto from 'node:crypto';import {spawnSync} from 'node:child_process';import {atomicWrite} from ${JSON.stringify(pathToFileURL(path.join(here,'lib/runtime-file.mjs')).href)};
 const c=JSON.parse(process.env.AAI_RELEASE_BASE_WORKER);let allowed=false;process.stdin.once('data',()=>{allowed=true;const r=spawnSync('git',c.args,{cwd:c.cwd,env:{...process.env,GIT_NO_LAZY_FETCH:'1',GIT_INDEX_FILE:c.index},encoding:'utf8',timeout:60000,maxBuffer:8*1024*1024});const owner=JSON.parse(fs.readFileSync(c.lock));if(owner.token!==c.token)process.exit(21);atomicWrite(c.lock,JSON.stringify({...owner,phase:'updated',result:r.status,updatedHash:r.status===0?crypto.createHash('sha256').update(fs.readFileSync(c.index)).digest('hex'):null,error:r.error?.message||r.stderr||''})+'\\n');process.exitCode=r.status===0?0:20;});process.stdin.on('end',()=>{if(!allowed)process.exitCode=20;});`;
 const child=spawn(process.execPath,['--input-type=module','-e',source],{cwd,stdio:['pipe','ignore','ignore'],env:{...process.env,AAI_RELEASE_BASE_WORKER:JSON.stringify({cwd,args:['read-tree','-u','-m',oldHead,record.merge],index:lock.privateIndex,lock:lock.file,token:lock.owner.token})}});
 child.stdin.on('error',()=>{});
 const closed=new Promise((resolve,reject)=>{child.on('error',reject);child.on('close',resolve);});
 if(!Number.isSafeInteger(child.pid)){try{await closed;}catch(e){refuse('base-update',e.message);}refuse('base-update','Base worker did not start');}
 lock.owner.worker=child.pid;lock.owner.phase='updating';atomicWrite(lock.file,JSON.stringify(lock.owner)+'\n');child.stdin.end('go');
 const code=await closed;const result=loadOrDegrade(lock.file,{isShape:baseIndexShape});
 if(code!==0||result.status!=='ok'||result.data.result!==0)refuse('base-update',result.data?.error||`Native base update failed (${code}); preserve Git recovery evidence`);
 lock.owner=result.data;
}
async function syncBase(){
 const list=git('worktree','list','--porcelain').split('\n\n');let basePath='';
 for(const block of list){if(block.split('\n').includes(`branch refs/heads/${record.base}`)){basePath=block.split('\n').find(l=>l.startsWith('worktree '))?.slice(9)||'';break;}}
 if(!basePath){console.log('- Base: SKIPPED (no registered base checkout)');stage('synced');return;}
 const ref=`refs/heads/${record.base}`;
 const at=(...args)=>command('git',args,basePath).stdout.trim();
 const index=path.resolve(basePath,at('rev-parse','--git-path','index'));
 let lock,transaction;
 try{
  lock=baseIndexClaim(index,basePath,ref);
  if(at('symbolic-ref','--quiet','HEAD')!==ref)refuse('base-checkout-moved','Registered base checkout changed branch');
  const baseHead=sha(at('rev-parse',ref),'registered base');
  if(at('rev-parse','HEAD')!==baseHead||![lock.owner.old,record.merge].includes(baseHead))refuse('base-checkout-moved','Registered base checkout changed head');
  const changed=at('diff','--name-only',lock.owner.old,record.merge).split('\n');
  const overlaps=files=>files.some(f=>changed.some(c=>c===f||c.startsWith(f+'/')||f.startsWith(c+'/')));
  if(lock.recovered){
   const differences=command('git',['diff','--name-only',record.merge,'--'],basePath,false,60000,{GIT_INDEX_FILE:lock.privateIndex}).stdout.trim().split('\n').filter(Boolean);
   if(overlaps(differences))refuse('base-dirty-overlap','Recovered base data changed after the completed native update; preserve it');
  }
  if(baseHead!==record.merge){
   if(command('git',['merge-base','--is-ancestor',baseHead,record.merge],basePath,true).status!==0)refuse('base-diverged','Registered base checkout cannot fast-forward');
   const hidden=command('git',['ls-files','-v','-z'],basePath).stdout.split('\0').filter(Boolean).filter(l=>/^[a-zS] /.test(l)).map(l=>l.slice(2));
   if(overlaps(hidden))refuse('base-hidden-edits','Registered base has hidden index paths overlapping release changes');
   if(!lock.recovered){const dirty=command('git',['status','--porcelain','-z','--untracked-files=all'],basePath).stdout.split('\0').filter(Boolean).map(l=>l.slice(3));if(overlaps(dirty))refuse('base-dirty-overlap','Registered base has dirty files overlapping release changes');}
   transaction=await baseTransaction(basePath,ref,baseHead,record.merge);
   await updateBaseTree(lock,basePath,baseHead);
   await transaction.commit();transaction=null;
  }
  if(at('symbolic-ref','--quiet','HEAD')!==ref||at('rev-parse',ref)!==record.merge)refuse('base-checkout-moved','Registered base changed during synchronization');
  fs.renameSync(lock.privateIndex,index);
  fs.unlinkSync(lock.file);lock=null;
  console.log('- Base: synced');stage('synced');
 }finally{
  if(transaction)await transaction.abort();
  if(lock){const current=loadOrDegrade(lock.file,{isShape:baseIndexShape});if(current.status==='ok'&&current.data.token===lock.owner.token&&(!current.data.worker||!processAlive(current.data.worker))){fs.rmSync(lock.privateIndex,{force:true});fs.unlinkSync(lock.file);}}
 }
}
function releaseBase(){
 let base=command('git',['symbolic-ref','refs/remotes/origin/HEAD'],root,true).stdout.trim().replace(/^refs\/remotes\/origin\//,'');
 if(!base){
  const mainExists=['refs/remotes/origin/main','refs/heads/main'].some(ref=>command('git',['rev-parse','--verify',ref],root,true).status===0);
  base=mainExists?'main':command('git',['symbolic-ref','--quiet','--short','HEAD'],root,true).stdout.trim()||'main';
 }
 const remote=`origin/${base}`;
 const baseRef=command('git',['rev-parse','--verify',`refs/remotes/${remote}`],root,true).status===0?remote:
  command('git',['rev-parse','--verify',`refs/heads/${base}`],root,true).status===0?base:'HEAD';
 return {base,baseRef,baseHead:sha(git('rev-parse',baseRef),'release base')};
}
// Read the authoritative branch without changing tracking refs. Confirm may
// obtain missing objects, but refusal must not move refs or FETCH_HEAD.
function authoritativeBase(base,obtainObjects){
 const ref=`refs/heads/${base}`,head=sha(remoteHead(ref),'remote release base');
 if(command('git',['cat-file','-e',head+'^{commit}'],root,true).status!==0){
  if(!obtainObjects)refuse('base-history','Remote base is not locally available; fetch it before a write-free preview');
  command('git',['fetch','--no-tags','--no-write-fetch-head','origin',head]);
 }
 if(remoteHead(ref)!==head)refuse('base-moved','Remote release base moved while reading its history; retry confirmation');
 return head;
}
function unchangedBase(){
 if(authoritativeBase(record.base,true)!==record.baseHead)refuse('base-moved','Remote release base differs from the audited payload; retain this journal/PR and prepare a newly audited release before merging');
}
// A merge queue only enqueues: an OPEN PR that is in the queue is pending, not refused. An armed auto-merge alone is not a queue; its checks are still evaluated.
function queuedOrRefuse(){
 const r=command('gh',['pr','view',String(record.pr),'--repo',record.repo,'--json','state,isInMergeQueue,autoMergeRequest'],root,true);
 let q=null;if(!r.error&&r.status===0)try{q=JSON.parse(r.stdout);}catch{}
 if(q&&q.state==='OPEN'&&q.isInMergeQueue===true)pending('merge-queue',`Release PR #${record.pr} is queued in the merge queue and has not merged yet`);
}
function requiredChecks(){
 const args=['pr','checks',String(record.pr),'--repo',record.repo,'--required','--json','name,bucket,link'];
 const r=command('gh',args,root,true);
 if(r.error||![0,1,8].includes(r.status))refuse('github-checks',r.error?.message||`gh checks transport exited ${r.status}`);
 let checks;try{checks=JSON.parse(r.stdout);}catch{refuse('github-checks','gh checks returned invalid JSON');}
 if(!Array.isArray(checks)||!checks.length)refuse('required-checks','No required checks reported');
 if(r.status===8&&!checks.some(c=>c.bucket==='pending'))refuse('github-checks','Pending exit status without a pending check');
 if(r.status===1&&!checks.some(c=>['fail','cancel'].includes(c.bucket)))refuse('github-checks','Failure exit status without a failed check');
 return checks;
}
async function main(){
 if(!Number.isFinite(maxWait)||maxWait<0||!Number.isFinite(interval)||interval<0)refuse('arguments','Invalid wait interval');
 root=git('rev-parse','--show-toplevel');
 if(auditOnly){const local=releaseBase();const head=onlineAudit?authoritativeBase(local.base,false):local.baseHead;const missing=audit(fs.readFileSync(auditFile,'utf8'),onlineAudit,head);for(const item of missing)console.log(item);return;}
 if(!confirmed)refuse('confirmation','Explicit --confirm is required for release mutations');
 if(!version||command('git',['check-ref-format',`refs/tags/${version}`],root,true).status!==0)refuse('version','Explicit valid tag version is required');
 if(!validTagVersion(version))refuse('version',`Version ${version} does not match the release.yml tag pattern v?[0-9]...; the release would merge but never publish`);
 gh('auth','status');const repo=json('repo','view','--json','nameWithOwner').nameWithOwner;if(!/^[\w.-]+\/[\w.-]+$/.test(repo||''))refuse('identity','Unknown GitHub repository');
 const origin=git('config','--get','remote.origin.url');if(githubOrigin(origin)!==repo)refuse('identity','Origin and GitHub repository disagree');
 const common=path.resolve(root,git('rev-parse','--git-common-dir'));journal=path.join(common,'aai/releases',crypto.createHash('sha256').update(version).digest('hex')+'.json');
 const branch=`chore/release-${version}`;
 claimRun();
 const loaded=loadOrDegrade(journal,{isShape:journalShape});
 if(loaded.status==='corrupt')refuse('journal-corrupt','Release journal is unreadable, malformed or has invalid durable fields; preserve it for recovery');
 if(loaded.status==='ok'){
  record=loaded.data;
  if(record.repo!==repo||record.origin!==origin||record.version!==version||record.branch!==branch)refuse('identity','Journal repository/version/branch mismatch');
 }else{
  // Preflight before persistent refs, journal, worktree, commit or push.
  const {base,baseRef}=releaseBase();const baseHead=authoritativeBase(base,true);
  if(remoteHead(`refs/heads/${branch}`)||command('git',['rev-parse','--verify',`refs/heads/${branch}`],root,true).status===0)refuse('identity','Release branch exists without durable authorization');
  if(remoteHead(`refs/tags/${version}`)||command('git',['rev-parse','--verify',`refs/tags/${version}`],root,true).status===0)refuse('tag-exists',`Tag ${version} exists without a matching journal`);
  const rolled=rollup(git('show',`${baseHead}:CHANGELOG.md`));const missing=audit(rolled.notes,true,baseHead);if(missing.length)refuse('missing-notes',missing.join('; '));
  if(authoritativeBase(base,true)!==baseHead)refuse('base-moved','Remote release base moved during notes audit; retry confirmation');
  const ambiguous=json('pr','list','--repo',repo,'--head',branch,'--state','all','--json',fields);if(!Array.isArray(ambiguous)||ambiguous.length)refuse('identity','Existing or ambiguous release PR has no matching journal');
  record={version,repo,origin,base,baseRef,baseHead,branch,notes:rolled.notes,content:rolled.content,head:null,pr:null,merge:null,stage:'initialized'};
  fs.mkdirSync(path.dirname(journal),{recursive:true});atomicSave();
 }
 if(!record.pr)unchangedBase();
 if(!record.head){
  const existing=command('git',['rev-parse','--verify',`refs/heads/${branch}`],root,true);
  if(existing.status===0&&existing.stdout.trim()!==record.baseHead){
   // A crash after commit may precede saving its SHA. Recover only the exact
   // payload and parent authorized by the initialized journal.
   const head=sha(existing.stdout.trim(),'prepared');
   if(git('rev-parse',head+'^')!==record.baseHead||git('log','-1','--format=%s',head)!==`chore(release): ${version}`||git('diff-tree','--no-commit-id','--name-only','-r',head)!=='CHANGELOG.md\ndocs/ai/AAI_VERSION.md'||trim(git('show',head+':CHANGELOG.md'))!==trim(record.content))refuse('identity','Unbound prepared release branch');
   record.head=head;atomicSave();
  }else{
   if(existing.status===0&&!record.worktree)refuse('identity','Unbound uncommitted release branch');
   if(!record.worktree){record.worktree=fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(),'aai-release-wt.')));atomicSave();}
   const wt=record.worktree;
   const registered=worktreeBlock(git('worktree','list','--porcelain'),wt);
   if(registered){
    if(!registered.split('\n').includes(`branch refs/heads/${branch}`))refuse('identity','Preparation worktree changed branch');
    const dirty=command('git',['status','--porcelain','--untracked-files=all'],wt).stdout.trimEnd().split('\n').filter(Boolean).map(l=>l.slice(3));
    if(dirty.some(f=>!['CHANGELOG.md','docs/ai/AAI_VERSION.md'].includes(f)))refuse('preparation-dirty','Preparation worktree has unrelated changes');
   }else if(existing.status===0)command('git',['worktree','add','-q',wt,branch]);
   else command('git',['worktree','add','-q','-b',branch,wt,record.baseHead]);
   stage('worktree');
   fs.writeFileSync(path.join(wt,'CHANGELOG.md'),record.content);fs.mkdirSync(path.join(wt,'docs/ai'),{recursive:true});
   fs.writeFileSync(path.join(wt,'docs/ai/AAI_VERSION.md'),`# AAI Version\n\n- Version: ${version}\n\nNotes:\n- Written by the release engines at each cut.\n`);
   stage('payload');
   command('git',['add','--','CHANGELOG.md','docs/ai/AAI_VERSION.md'],wt);command('git',['commit','-q','-m',`chore(release): ${version}`],wt);record.head=sha(command('git',['rev-parse','HEAD'],wt).stdout.trim(),'release');atomicSave();
  }
 }
 if(record.worktree){
  const registered=worktreeBlock(git('worktree','list','--porcelain'),record.worktree);
  if(registered){
   if(!registered.split('\n').includes(`branch refs/heads/${branch}`)||command('git',['status','--porcelain'],record.worktree).stdout.trim())refuse('preparation-dirty','Prepared worktree changed after commit');
   command('git',['worktree','remove',record.worktree]);
  }
  record.worktree=null;atomicSave();
 }
 if(!record.pr)stage('prepared');
 sha(record.head,'journal release');
 let prs=json('pr','list','--repo',repo,'--head',branch,'--state','all','--json',fields);if(!Array.isArray(prs)||prs.length>1)refuse('identity','Ambiguous release PRs');
 let pr=prs.length?identity(prs[0]):null;
 if(record.pr&&!pr)refuse('identity','Journal PR no longer exists');
 if(!pr){
  const head=remoteHead(`refs/heads/${branch}`);if(head&&head!==record.head)refuse('head-moved','Remote release head moved');
  if(!head)command('git',['push','--no-follow-tags',`--force-with-lease=refs/heads/${branch}:`,'origin',`${record.head}:refs/heads/${branch}`]);stage('pushed');
  const body=path.join(path.dirname(journal),'body-'+crypto.randomBytes(6).toString('hex')+'.md');
  try{fs.writeFileSync(body,`Automated release cut for ${version}.\n\nBound release: ${repo} ${branch} ${record.head}.\n\nno-notes: release rollup contains the previously recorded entries.\n`);const url=gh('pr','create','--repo',repo,'--base',record.base,'--head',branch,'--title',`chore(release): ${version}`,'--body-file',body);if(!/^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/pull\/\d+$/.test(url))refuse('empty-pr-url','PR creation did not return a valid URL');}finally{fs.unlinkSync(body);}
  prs=json('pr','list','--repo',repo,'--head',branch,'--state','all','--json',fields);if(prs.length!==1)refuse('identity','Could not bind unique created PR');pr=identity(prs[0]);record.pr=pr.number;stage('pr');
 }else{record.pr=pr.number;atomicSave();}
 if(pr.state!=='MERGED'){
  if(pr.state!=='OPEN')refuse('identity','Bound release PR is closed without merge');
  queuedOrRefuse();
  unchangedBase();
  const required=requiredChecks();if(!Array.isArray(required)||!required.length||required.some(c=>!['pass','pending'].includes(c.bucket))){const bad=Array.isArray(required)?required.filter(c=>!['pass','pending'].includes(c.bucket)).map(c=>`${c.name} (${c.bucket})`):[];refuse('required-checks','Required checks missing, skipped or failed'+(bad.length?': '+bad.join(', '):''));}
  console.log(`release: waiting for required CI on PR #${record.pr}`);
  const watcher=spawnSync(process.execPath,[path.join(here,'watch-ci.mjs'),'--pr',String(record.pr),'--required','--interval-seconds',String(interval),'--max-wait-seconds',String(maxWait)],{cwd:root,encoding:'utf8',timeout:(maxWait+15)*1000,stdio:['ignore','inherit','pipe']});
  if(watcher.error||watcher.status!==0)refuse('ci',watcher.error?.message||trim(watcher.stderr||'CI watcher failed'));
  const settled=requiredChecks();if(!settled.length||settled.some(c=>c.bucket!=='pass'))refuse('required-checks','Required checks did not all pass');
  pr=identity(json('pr','view',String(record.pr),'--repo',repo,'--json',fields));if(remoteHead(`refs/heads/${branch}`)!==record.head)refuse('head-moved','Release head moved before merge');
  unchangedBase();
  gh('pr','merge',String(record.pr),'--repo',repo,'--squash','--match-head-commit',record.head);
  pr=identity(json('pr','view',String(record.pr),'--repo',repo,'--json',fields));if(pr.state!=='MERGED'){queuedOrRefuse();refuse('merge','Release PR did not merge');}
 }
 record.merge=sha(pr.mergeCommit?.oid,'merge');stage('merged');
 command('git',['fetch','--no-tags','origin',record.base]);
 if(command('git',['cat-file','-e',`${record.merge}:.github/workflows/release.yml`],root,true).status!==0){console.log('- Publication: SKIPPED (no release.yml; manual tagging retained)');console.log(`- Version: ${version}\n- PR: ${pr.url}\n- Merge SHA: ${record.merge}`);return;}
 boundedPoll(()=>json('run','list','--repo',repo,'--workflow','release.yml','--commit',record.merge,'--json','databaseId,headSha,status,conclusion'),runs=>{if(!Array.isArray(runs)||runs.length>1)refuse('workflow','Ambiguous workflow runs');if(!runs.length)return false;const r=runs[0];if(r.headSha!==record.merge)refuse('workflow','Workflow SHA mismatch');if(r.status!=='completed')return false;if(r.conclusion!=='success')refuse('workflow','Release workflow failed');return true;},'workflow-timeout');stage('workflow');
 const tags=git('ls-remote','--tags','origin',`refs/tags/${version}`,`refs/tags/${version}^{}`).split('\n').filter(Boolean);const peeled=tags.find(l=>l.endsWith(`refs/tags/${version}^{}`));if(!peeled||peeled.split(/\s/)[0]!==record.merge)refuse('tag-mismatch','Peeled remote tag does not equal merged release SHA');
 const release=json('release','view',version,'--repo',repo,'--json','body,url');if(typeof release.body!=='string'||trim(release.body)!==trim(record.notes))refuse('notes-mismatch','Published release body differs from rolled notes');if(!/^https:\/\/github\.com\//.test(release.url||''))refuse('release-url','Published release URL is missing');record.releaseUrl=release.url;stage('verified');
 const dependents=json('pr','list','--repo',repo,'--base',branch,'--state','open','--json','number');if(!Array.isArray(dependents)||dependents.length)refuse('dependent-pr','Release branch has dependent PRs');
 const head=remoteHead(`refs/heads/${branch}`);if(head&&head!==record.head)refuse('cleanup-head-moved','Release branch moved before deletion');if(head)command('git',['push',`--force-with-lease=refs/heads/${branch}:${record.head}`,'origin',`:refs/heads/${branch}`]);stage('remote-deleted');
 const local=command('git',['rev-parse','--verify',`refs/heads/${branch}`],root,true);if(local.status===0){if(local.stdout.trim()!==record.head)refuse('cleanup-local-head','Local release branch moved');if(git('worktree','list','--porcelain').split('\n').map(l=>l.trimEnd()).includes(`branch refs/heads/${branch}`))refuse('cleanup-worktree','Release branch is checked out');command('git',['update-ref','-d',`refs/heads/${branch}`,record.head]);}stage('local-deleted');
 await syncBase();console.log(`## aai-release — complete\n- Version: ${version}\n- PR: ${pr.url}\n- Merge SHA: ${record.merge}\n- Tag SHA: ${record.merge}\n- Release: ${record.releaseUrl}\n- Branch: deleted`);
}
function shellQuote(value){return "'"+String(value).replaceAll("'",process.platform==='win32'?"''":"'\\''")+"'";}
const realOrResolve=p=>{try{return fs.realpathSync(p);}catch{return path.resolve(p);}};
if(process.argv[1]&&import.meta.url===pathToFileURL(realOrResolve(process.argv[1])).href)try{await main();}catch(e){console.error(`${e.pending?'PENDING':'REFUSED'}: ${e.causeName||'release'} — ${e.message}`);if(record)console.error(`Completed: stage=${record.stage}; release-head=${record.head||'pending'}; PR=${record.pr||'pending'}; merge=${record.merge||'pending'}`);if(version)console.error(`Resume: node ${shellQuote(path.join(here,'release-finish.mjs'))} --root ${shellQuote(root)} --version ${/^[A-Za-z0-9._/+\-]+$/.test(version)?version:shellQuote(version)} --confirm`);process.exitCode=e.pending?8:20;}finally{try{releaseClaim();}catch(e){console.error('Release claim cleanup failed: '+e.message);process.exitCode=20;}}
