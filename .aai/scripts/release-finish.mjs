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
const graceRaw=String(process.env.AAI_RELEASE_CHECKS_GRACE_SECONDS??60).trim();
// Unset or blank means the default; only a plain decimal is a number (no hex, exponent or Infinity), anything else refuses `arguments`.
const checksGrace=graceRaw===''?60:/^[+-]?(\d+\.?\d*|\.\d+)$/.test(graceRaw)?Number(graceRaw):NaN;
const preflightRaw=String(process.env.AAI_RELEASE_PREFLIGHT_SECONDS??900).trim();
// Same plain-decimal rule as the grace parse; blank means the default 900.
const preflightSeconds=preflightRaw===''?900:/^[+-]?(\d+\.?\d*|\.\d+)$/.test(preflightRaw)?Number(preflightRaw):NaN;
function refuse(cause,detail) {const e=new Error(detail);e.causeName=cause;throw e;}
// Not a refusal: the release is progressing remotely (exit 8, the gh pending code); resume re-reads it.
function pending(cause,detail) {const e=new Error(detail);e.causeName=cause;e.pending=true;throw e;}
function command(exe,args,cwd=root,allowFailure=false,timeout=60000,env={}) {
 const r=spawnSync(exe,args,{cwd,encoding:'utf8',timeout,maxBuffer:8*1024*1024,env:exe==='git'?{...process.env,GIT_NO_LAZY_FETCH:'1',...env}:{...process.env,...env}});
 if(!allowFailure&&(r.error||r.status!==0))refuse(exe==='gh'?'github-command':'git-command',`${exe} ${args.join(' ')}: ${r.error?.message||r.stderr?.trim()||`exit ${r.status}`}`);
 return r;
}
function git(...args){return command('git',args).stdout.trim();}
// Exact bytes (no trim): a release payload must keep the file's own BOM, line endings and EOF state.
function blob(spec){return command('git',['cat-file','blob',spec]).stdout;}
function gh(...args){return command('gh',args).stdout.trim();}
function json(...args){const s=gh(...args);try{return JSON.parse(s);}catch{refuse('github-data',`Invalid JSON for gh ${args.join(' ')}`);}}
function sha(value,name){if(!/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(value||''))refuse('empty-sha',`${name} did not return a full SHA`);return value;}
function privateFile(write){const prior=process.umask(0o077);try{return write();}finally{process.umask(prior);}}
function atomicSave(){privateFile(()=>atomicWrite(journal,JSON.stringify(record,null,2)+'\n'));}
const fullSha=v=>/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(v||'');
const exactKeys=(o,keys)=>o!==null&&typeof o==='object'&&!Array.isArray(o)&&Object.keys(o).sort().join()===[...keys].sort().join();
// Additive journal keys (a journal without them loads unchanged); unknown keys inside either shape make the journal corrupt.
const recutShape=o=>exactKeys(o,['fromBase','fromHead'])&&fullSha(o.fromBase)&&(o.fromHead===null||fullSha(o.fromHead));
const recutsShape=o=>exactKeys(o,['fromBase','toBase','fromHead','toHead','at'])&&[o.fromBase,o.toBase,o.toHead].every(fullSha)&&(o.fromHead===null||fullSha(o.fromHead))&&typeof o.at==='string'&&!Number.isNaN(Date.parse(o.at));
function journalShape(value){
 return value!==null&&typeof value==='object'&&!Array.isArray(value)&&
 ['version','repo','origin','base','baseRef','baseHead','branch','notes','content','stage'].every(k=>typeof value[k]==='string'&&value[k].length>0)&&
 /^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(value.baseHead)&&
 [value.head,value.merge].every(v=>v===null||/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(v||''))&&
 (value.pr===null||Number.isSafeInteger(value.pr)&&value.pr>0)&&
 (value.superseded===undefined||Array.isArray(value.superseded)&&value.superseded.every(fullSha))&&
 (value.recut===undefined||value.recut===null||recutShape(value.recut))&&(value.recuts===undefined||Array.isArray(value.recuts)&&value.recuts.every(recutsShape))&&
 ['initialized','recut','worktree','payload','prepared','pushed','pr','merged','workflow','verified','remote-deleted','local-deleted','synced'].includes(value.stage);
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
 const bom=source.startsWith('\uFEFF')?'\uFEFF':'';if(bom)source=source.slice(1);
 const newline=source.endsWith('\n');const lines=source.split('\n');if(newline)lines.pop();
 const first=lines.findIndex(l=>/^## \[/.test(l));if(first<0)refuse('empty-notes','No rollable entries');
 const cr=lines[first].endsWith('\r')?'\r':'';
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
 const notes=sections.filter(s=>s.entry).flatMap(s=>s.text).map(l=>l.replace(/\r$/,'')).join('\n').trim();
 const ordered=[...sections.filter(s=>s.entry),...sections.filter(s=>!s.entry)];
 return {content:bom+[...lines.slice(0,first),'## [unreleased]'+cr,''+cr,...ordered.flatMap(s=>s.text)].join('\n')+(newline?'\n':''),notes};
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
 const {last,merge}=number(subject);
 // A covered commit with its own PR number is audited as that PR; only unnumbered ones stay attributed to the outer merge.
 if(covered.has(commit)&&!last&&!merge)continue;
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
// The AAI:REF-GUARD hook refuses a refs/heads/main update unless AAI_GIT_WRITE=1. This one transaction (confirmed run, verified merge SHA, fast-forward only) is the narrow exception: the variable is set on this child alone, never on process.env or the frontends.
// Keep the expected-old base ref locked while updating its checkout. HEAD is not
// locked: the base index.lock (baseIndexClaim) keeps porcelain checkouts out, and
// syncBase re-verifies HEAD and the ref after the update.
async function baseTransaction(cwd,ref,oldHead,newHead){
 const child=spawn('git',['update-ref','--stdin'],{cwd,env:{...process.env,GIT_NO_LAZY_FETCH:'1',AAI_GIT_WRITE:'1'},stdio:['pipe','pipe','pipe']});
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
 if(authoritativeBase(record.base,true)!==record.baseHead)refuse('base-moved','Remote release base moved while CI ran; re-run this same --version --confirm to re-cut it on the new base');
}
const closedPr=()=>`Bound release PR #${record.pr} is closed without merge; reopen it and re-run this same --version`;
const fixHint=()=>`; fix the failure on ${record.base} and re-run this same --version`;
// A moved base is not a refusal: the same version is re-cut on it (audit, rollup, preflight, leased push), keeping the PR.
function recutIfMoved(){
 if(record.merge)return;
 const current=authoritativeBase(record.base,true);
 const moved=current!==record.baseHead||record.recut?current:null;
 if(moved&&record.pr){
  const pr=json('pr','view',String(record.pr),'--repo',record.repo,'--json',fields);
  if(pr.state==='MERGED'){if(record.recut)abandonRecut(pr);return;}
  if(pr.state!=='OPEN')refuse('identity',closedPr());
  queuedOrRefuse();
 }
 if(moved)recutRelease(moved);
}
// A merged release PR is never re-cut (D9): the pending re-cut is dropped and the journal returns to the binding the merged head was cut with.
function abandonRecut(pr){
 const cut=record.recut,at=new Date().toISOString();
 if(record.head&&pr.headRefOid===record.head&&record.head!==cut.fromHead){
  // The re-cut head was pushed and then merged: the re-cut is complete, only its journal write was missing.
  record.recuts=[...(record.recuts||[]),{fromBase:cut.fromBase,toBase:record.baseHead,fromHead:cut.fromHead,toHead:record.head,at}];
  record.recut=null;stage('pr');return;
 }
 if(pr.headRefOid!==cut.fromHead)refuse('head-moved',`Merged release PR head ${pr.headRefOid} is neither the journaled head ${cut.fromHead} nor the pending re-cut head ${record.head||'(none)'}`);
 restoreMergedBinding(cut,false);
}
// Returns the journal to the binding a merged head was cut with; the merged head must carry the rollup of that binding's base.
function restoreMergedBinding(cut,dropLastRecut){
 const rolled=rollup(blob(`${cut.fromBase}:CHANGELOG.md`));
 const merged=command('git',['cat-file','blob',`${cut.fromHead}:CHANGELOG.md`],root,true);
 if(merged.status!==0||merged.stdout!==rolled.content)refuse('identity','Merged release head does not carry the rollup of the journaled base; preserve the journal for recovery');
 const ref=`refs/heads/${record.branch}`,local=command('git',['rev-parse','--verify',ref],root,true);
 const localHead=local.status===0?local.stdout.trim():'';
 const ours=!localHead||localHead===cut.fromHead||[record.head,record.baseHead,cut.fromBase].includes(localHead)||(command('git',['rev-parse',localHead+'^'],root,true).stdout.trim()===record.baseHead&&command('git',['log','-1','--format=%s',localHead],root,true).stdout.trim()===`chore(release): ${version}`);
 if(!ours)refuse('head-moved',`Local ${ref} is ${localHead}, not a head of this release`);
 if(record.worktree){
  if(worktreeBlock(git('worktree','list','--porcelain'),record.worktree))command('git',['worktree','remove','--force',record.worktree]);
  fs.rmSync(record.worktree,{recursive:true,force:true});record.worktree=null;
 }
 if(localHead&&localHead!==cut.fromHead)command('git',['update-ref','-d',ref,localHead]);
 if(dropLastRecut){const gone=record.recuts[record.recuts.length-1];record.recuts=record.recuts.slice(0,-1);record.superseded=[...(record.superseded||[]),gone.toHead];}
 Object.assign(record,{baseHead:cut.fromBase,head:cut.fromHead,content:rolled.content,notes:rolled.notes,recut:null});
 stage('pr');
}
// The PR was read OPEN before the preflight; it is read again right before the leased push, and a PR that is no longer OPEN is never pushed to or edited.
function settlePrAfterPreflight(){
 const pr=json('pr','view',String(record.pr),'--repo',record.repo,'--json',fields);
 if(pr.state==='MERGED'){abandonRecut(pr);return;}
 refuse('identity',pr.state==='CLOSED'?closedPr():`Release PR #${record.pr} changed state while the re-cut was prepared; re-run this same --version`);
}
function recutRelease(newBase){
 const ref=`refs/heads/${record.branch}`;
 const live=remoteHead(ref);
 // In memory until the journal write below: a refusing guard leaves the journal byte-identical.
 if(!record.recut)record.recut={fromBase:record.baseHead,fromHead:live===''&&!record.pr?null:record.head};
 const tagSeen=Boolean(remoteHead(`refs/tags/${version}`))||command('git',['rev-parse','--verify',`refs/tags/${version}`],root,true).status===0;
 if(tagSeen)refuse('tag-exists',`Tag ${version} exists; a published version is never re-cut`);
 const descends=command('git',['merge-base','--is-ancestor',record.baseHead,newBase],root,true).status===0;
 if(!descends)refuse('base-rewritten',`Remote ${record.base} no longer contains the audited base ${record.baseHead}`);
 const remote=live||null;
 const allowedHeads=[record.recut.fromHead,...(record.head?[record.head]:[])];
 if(!allowedHeads.includes(remote))refuse('head-moved',`Remote release head ${remote||'(absent)'} is neither the journaled head ${record.recut.fromHead||'(never pushed)'} nor the pending re-cut head ${record.head||'(none)'}`);
 if(newBase===record.baseHead)return;
 if(record.head&&remote===record.head&&record.head!==record.recut.fromHead){
  // A pending re-cut that was pushed before its journal write: fold it in, so the next lease is on the pushed head.
  record.recuts=[...(record.recuts||[]),{fromBase:record.recut.fromBase,toBase:record.baseHead,fromHead:record.recut.fromHead,toHead:record.head,at:new Date().toISOString()}];
  record.recut={fromBase:record.baseHead,fromHead:record.head};
 }
 const local=command('git',['rev-parse','--verify',ref],root,true);
 const localHead=local.status===0?local.stdout.trim():'';
 if(localHead&&![record.head,record.baseHead].includes(localHead))refuse('head-moved',`Local ${ref} is ${localHead}, not the journaled ${record.head||record.baseHead}`);
 const rolled=rollup(blob(`${newBase}:CHANGELOG.md`));
 const missing=audit(rolled.notes,true,newBase);if(missing.length)refuse('missing-notes',missing.join('; '));
 if(authoritativeBase(record.base,true)!==newBase)refuse('base-moved','Remote release base moved during notes audit; retry confirmation');
 if(record.worktree){
  if(worktreeBlock(git('worktree','list','--porcelain'),record.worktree))command('git',['worktree','remove','--force',record.worktree]);
  record.worktree=null;
 }
 // Compare-and-swap from the journaled tip: a local branch that moved meanwhile makes git refuse.
 if(localHead)command('git',['update-ref','-d',ref,localHead]);
 Object.assign(record,{baseHead:newBase,content:rolled.content,notes:rolled.notes,head:null});
 stage('recut');
}
// Release preflight: the tracked node tests that read CHANGELOG run against the rolled tree before any push of a release head.
function preflightRun(commit,file){
 const wt=fs.mkdtempSync(path.join(os.tmpdir(),'aai-release-pf.'));
 try{
  command('git',['worktree','add','-q','--detach',wt,commit]);
  // Own process group: the timeout kills only the runner, so the whole group is killed afterwards (POSIX). Windows has no group; taskkill /T reaches only children the dead runner still parents, a documented limit.
  const r=spawnSync(process.execPath,['--test',file],{cwd:wt,encoding:'utf8',timeout:preflightSeconds*1000,killSignal:'SIGKILL',maxBuffer:8*1024*1024,detached:process.platform!=='win32'});
  const timedOut=Boolean(r.error&&r.error.code==='ETIMEDOUT');
  if(r.pid){if(process.platform==='win32'){if(timedOut)spawnSync('taskkill',['/PID',String(r.pid),'/T','/F'],{windowsHide:true});}else{try{process.kill(-r.pid,'SIGKILL');}catch{}}}
  return {ok:!r.error&&r.status===0,timedOut,tail:`${r.stdout||''}${r.stderr||''}`.trim().split('\n').slice(-20).join('\n')};
 }finally{
  command('git',['worktree','remove','--force',wt],root,true);
  fs.rmSync(wt,{recursive:true,force:true});
 }
}
function releasePreflight(){
 const tracked=git('ls-tree','-r','-z','--name-only',record.head).split('\0').filter(Boolean).filter(p=>p.split('/').includes('tests')&&p.endsWith('.test.mjs'));
 const files=tracked.filter(p=>{const text=blob(`${record.head}:${p}`);return text.includes('CHANGELOG');});
 if(!files.length){console.log('- Release preflight: SKIPPED (no tracked tests/**/*.test.mjs reads CHANGELOG)');return;}
 let passed=0;
 for(const file of files){
  const rolled=preflightRun(record.head,file);
  if(rolled.ok){passed++;continue;}
  const baseFails=!preflightRun(record.baseHead,file).ok;
  if(!baseFails)refuse('release-preflight',`${file} fails only on the rolled payload${rolled.timedOut?` (timed out after ${preflightSeconds}s)`:''}; last 20 output lines:\n${rolled.tail}`);
  console.log(`- Release preflight: ${file} FAILS ON BASE TOO (not caused by the rollup; CI decides)`);
 }
 console.log(`- Release preflight: ${passed} of ${files.length} file(s) passed on the rolled payload`);
}
// The one place a release head is pushed (first cut and re-cut): preflight first, then the leased push.
function pushRelease(){
 releasePreflight();
 if(record.pr&&json('pr','view',String(record.pr),'--repo',record.repo,'--json',fields).state!=='OPEN')return false;
 const branch=record.branch;
 const lease=record.recut&&record.recut.fromHead?`--force-with-lease=refs/heads/${branch}:${record.recut.fromHead}`:`--force-with-lease=refs/heads/${branch}:`;
 command('git',['push','--no-follow-tags',lease,'origin',`${record.head}:refs/heads/${branch}`]);
 return true;
}
// A merge queue only enqueues: an OPEN PR that is in the queue is pending, not refused. An armed auto-merge alone is not a queue; its checks are still evaluated.
function queuedOrRefuse(){
 const r=command('gh',['pr','view',String(record.pr),'--repo',record.repo,'--json','state,isInMergeQueue,autoMergeRequest'],root,true);
 let q=null;if(!r.error&&r.status===0)try{q=JSON.parse(r.stdout);}catch{}
 if(q&&q.state==='OPEN'&&q.isInMergeQueue===true)pending('merge-queue',`Release PR #${record.pr} is queued in the merge queue and has not merged yet`);
}
function requiredChecks(allowEmpty=false){
 const args=['pr','checks',String(record.pr),'--repo',record.repo,'--required','--json','name,bucket,link'];
 const r=command('gh',args,root,true);
 if(r.error||![0,1,8].includes(r.status))refuse('github-checks',r.error?.message||`gh checks transport exited ${r.status}`);
 // gh 2.93 prints nothing on stdout and exits 1 with this stderr while no (required) check is registered yet.
 const notRegistered=r.status===1&&!r.stdout.trim()&&/^no (required )?checks reported on the '[^']*' branch$/.test((r.stderr||'').trim());
 let checks;if(notRegistered)checks=[];else{try{checks=JSON.parse(r.stdout);}catch{refuse('github-checks','gh checks returned invalid JSON');}}
 if(!Array.isArray(checks)||!checks.length){if(allowEmpty&&Array.isArray(checks))return checks;refuse('required-checks','No required checks reported');}
 if(r.status===8&&!checks.some(c=>c.bucket==='pending'))refuse('github-checks','Pending exit status without a pending check');
 if(r.status===1&&!checks.some(c=>['fail','cancel'].includes(c.bucket)))refuse('github-checks','Failure exit status without a failed check');
 return checks;
}
// Required contexts of the base branch, read-access only: classic protection (branch endpoint) plus rulesets. Unreadable = named degrade (D2); malformed = refusal (D3).
// paged: read every page of a list endpoint. `gh api --paginate --slurp` (gh 2.48+) answers one array of page arrays; an older gh rejects --slurp, which lands in the unreadable branch below (named line), never a silent first-page read.
function contextSource(source,endpoint,extract,paged=false) {
 const r=command('gh',paged?['api','--paginate','--slurp',`${endpoint}?per_page=100`]:['api',endpoint],root,true);
 if(r.error||r.status!==0)return {source,unreadable:r.error?.message||(r.stderr||'').split('\n')[0].trim()||`exit ${r.status}`};
 let data;try{data=JSON.parse(r.stdout);}catch{refuse('required-contexts','Invalid JSON from gh api '+endpoint);}
 const shape=why=>refuse('required-contexts',`Unexpected shape from gh api ${endpoint}: ${why}`);
 if(paged){if(!Array.isArray(data)||data.some(p=>!Array.isArray(p)))shape('rules answer is not an array');data=data.flat();}
 const found=extract(data,shape);
 return found===null?{source,unreadable:'protected branch without a readable protection object'}:{source,contexts:found};
}
function classicContexts(data,shape) {
 if(data===null||typeof data!=='object'||Array.isArray(data)||typeof data.protected!=='boolean')shape('branch answer without a boolean protected');
 if(!data.protected)return [];
 if(data.protection===undefined||data.protection===null)return null;
 if(typeof data.protection!=='object'||Array.isArray(data.protection))shape('protection is not an object');
 const rsc=data.protection.required_status_checks;
 if(rsc===undefined||rsc===null)return [];
 if(typeof rsc!=='object'||Array.isArray(rsc))shape('required_status_checks is not an object');
 if(rsc.enforcement_level==='off')return [];
 const names=[];
 if(rsc.contexts!==undefined){if(!Array.isArray(rsc.contexts)||rsc.contexts.some(c=>typeof c!=='string'))shape('contexts is not a list of strings');names.push(...rsc.contexts);}
 if(rsc.checks!==undefined){if(!Array.isArray(rsc.checks)||rsc.checks.some(c=>!c||typeof c.context!=='string'))shape('checks is not a list of context entries');names.push(...rsc.checks.map(c=>c.context));}
 return names;
}
function rulesetContexts(data,shape) {
 if(!Array.isArray(data))shape('rules answer is not an array');
 const names=[];
 for(const rule of data.filter(r=>r&&r.type==='required_status_checks')){
  const list=rule.parameters&&rule.parameters.required_status_checks;
  if(!Array.isArray(list)||list.some(c=>!c||typeof c.context!=='string'))shape('required_status_checks rule without a list of contexts');
  names.push(...list.map(c=>c.context));
 }
 return names;
}
function requiredContexts() {
 const base=`repos/${record.repo}`,branch=encodeURIComponent(record.base);
 const answers=[contextSource('protection',`${base}/branches/${branch}`,classicContexts),contextSource('rulesets',`${base}/rules/branches/${branch}`,rulesetContexts,true)];
 const lost=answers.filter(a=>a.unreadable!==undefined);
 if(lost.length)console.log(`- Required contexts: ${lost.map(a=>`UNREADABLE ${a.source} (${a.unreadable})`).join('; ')}${lost.length===answers.length?'; waiting on reported required checks only':''}`);
 return [...new Set(answers.flatMap(a=>a.contexts||[]))];
}
function registeredChecks(){
 const end=Date.now()+checksGrace*1000;
 for(;;){
  const c=requiredChecks(true);
  if(c.length)return c;
  if(Date.now()>=end)refuse('required-checks',`No required checks registered within ${checksGrace}s`);
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,interval*1000);
 }
}
// After watch-ci: every reported check passes and every required context appears by name with bucket pass, bounded by AAI_RELEASE_WAIT_SECONDS.
function awaitContexts(contexts) {
 const end=Date.now()+maxWait*1000;
 for(;;){
  const settled=requiredChecks();
  const bad=settled.filter(c=>!['pass','pending'].includes(c.bucket));
  if(bad.length)refuse('required-checks',`Required check not passing: ${bad.map(c=>`${c.name} (${c.bucket})`).join(', ')}${fixHint()}`);
  const unsettled=contexts.filter(n=>!settled.some(c=>c.name===n&&c.bucket==='pass'));
  const waiting=settled.filter(c=>c.bucket==='pending').map(c=>c.name);
  if(!unsettled.length&&!waiting.length)return settled;
  if(Date.now()>=end)refuse('required-contexts',`Required contexts not passed within ${maxWait}s: ${[...new Set([...unsettled,...waiting])].join(', ')}`);
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,interval*1000);
 }
}
async function main(){
 if(!Number.isFinite(maxWait)||maxWait<0||!Number.isFinite(interval)||interval<0||!Number.isFinite(checksGrace)||checksGrace<0)refuse('arguments','Invalid wait interval');
 if(!Number.isFinite(preflightSeconds)||preflightSeconds<=0)refuse('arguments','Invalid AAI_RELEASE_PREFLIGHT_SECONDS');
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
  if(!record.pr&&rollup(blob(`${record.baseHead}:CHANGELOG.md`)).content!==record.content)refuse('identity','Journal content differs from the base rollup');
 }else{
  // Preflight before persistent refs, journal, worktree, commit or push.
  const {base,baseRef}=releaseBase();const baseHead=authoritativeBase(base,true);
  if(remoteHead(`refs/heads/${branch}`)||command('git',['rev-parse','--verify',`refs/heads/${branch}`],root,true).status===0)refuse('identity','Release branch exists without durable authorization');
  if(remoteHead(`refs/tags/${version}`)||command('git',['rev-parse','--verify',`refs/tags/${version}`],root,true).status===0)refuse('tag-exists',`Tag ${version} exists without a matching journal`);
  const rolled=rollup(blob(`${baseHead}:CHANGELOG.md`));const missing=audit(rolled.notes,true,baseHead);if(missing.length)refuse('missing-notes',missing.join('; '));
  if(authoritativeBase(base,true)!==baseHead)refuse('base-moved','Remote release base moved during notes audit; retry confirmation');
  const ambiguous=json('pr','list','--repo',repo,'--head',branch,'--state','all','--json',fields);if(Array.isArray(ambiguous)&&ambiguous.length===1&&ambiguous[0].state==='CLOSED')refuse('identity',`Release PR #${ambiguous[0].number} on ${branch} is closed without a matching journal; delete branch ${branch} and re-run this same --version`);if(!Array.isArray(ambiguous)||ambiguous.length)refuse('identity','Existing or ambiguous release PR has no matching journal');
  record={version,repo,origin,base,baseRef,baseHead,branch,notes:rolled.notes,content:rolled.content,head:null,pr:null,merge:null,stage:'initialized'};
  fs.mkdirSync(path.dirname(journal),{recursive:true});atomicSave();
 }
 recutIfMoved();
 if(!record.head){
  const existing=command('git',['rev-parse','--verify',`refs/heads/${branch}`],root,true);
  if(existing.status===0&&existing.stdout.trim()!==record.baseHead){
   // A crash after commit may precede saving its SHA. Recover only the exact
   // payload and parent authorized by the initialized journal.
   const head=sha(existing.stdout.trim(),'prepared');
   if(git('rev-parse',head+'^')!==record.baseHead||git('log','-1','--format=%s',head)!==`chore(release): ${version}`||git('diff-tree','--no-commit-id','--name-only','-r',head)!=='CHANGELOG.md\ndocs/ai/AAI_VERSION.md'||blob(head+':CHANGELOG.md')!==record.content)refuse('identity','Unbound prepared release branch');
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
   command('git',['add','--','CHANGELOG.md','docs/ai/AAI_VERSION.md'],wt);command('git',['commit','-q','-m',`chore(release): ${version}`],wt);
   const made=sha(command('git',['rev-parse','HEAD'],wt).stdout.trim(),'release');
   // .gitattributes (text/eol/filter) can make `git add` rewrite the bytes; fail closed before the head is journaled or pushed.
   if(blob(made+':CHANGELOG.md')!==record.content)refuse('changelog-normalized','Committed CHANGELOG.md differs from the journaled rollup (git attributes such as eol/text/filter rewrote it); release refused so the byte-exact guarantee is not broken silently');
   record.head=made;atomicSave();
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
 if(record.recut){
  if(remoteHead(`refs/heads/${branch}`)!==record.head&&!pushRelease())settlePrAfterPreflight();
  else{
   record.recuts=record.recuts||[];
   record.recuts.push({fromBase:record.recut.fromBase,toBase:record.baseHead,fromHead:record.recut.fromHead,toHead:record.head,at:new Date().toISOString()});
   record.recut=null;stage('pushed');
  }
 }
 if(record.pr&&record.stage==='pushed'&&(record.recuts||[]).length){
  // The PR follows the branch: GitHub updates its head asynchronously, so wait for it before rewriting the body and reading checks.
  const followed=boundedPoll(()=>json('pr','view',String(record.pr),'--repo',repo,'--json',fields),p=>p.state!=='OPEN'||p.headRefOid===record.head,'identity');
  if(followed.state!=='OPEN'){
   // Merged or closed while the push propagated: never edit it; the bound head decides what continues.
   if(followed.headRefOid!==record.head){
    // GitHub completed a merge of the previous head while the re-cut was pushed: return to that binding and publish the merged head.
    const last=record.recuts[record.recuts.length-1];
    if(followed.state==='MERGED'&&last.fromHead&&followed.headRefOid===last.fromHead)restoreMergedBinding({fromBase:last.fromBase,fromHead:last.fromHead},true);
    else refuse('identity',`Release PR #${record.pr} is ${followed.state} on ${followed.headRefOid}, not on the re-cut head ${record.head}; preserve the journal for recovery`);
   }else{record.stage='pr';atomicSave();}
  }else{
  const edited=path.join(path.dirname(journal),'body-'+crypto.randomBytes(6).toString('hex')+'.md');
  try{fs.writeFileSync(edited,`Automated release cut for ${version}.\n\nBound release: ${repo} ${branch} ${record.head}.\n\nno-notes: release rollup contains the previously recorded entries.\n`+record.recuts.map(e=>`\nRe-cut: ${e.fromHead} on ${e.fromBase} -> ${e.toHead} on ${e.toBase}.\n`).join(''));gh('pr','edit',String(record.pr),'--repo',repo,'--body-file',edited);}finally{fs.unlinkSync(edited);}
  record.stage='pr';atomicSave();
  }
 }
 let prs=json('pr','list','--repo',repo,'--head',branch,'--state','all','--json',fields);if(!Array.isArray(prs)||prs.length>1)refuse('identity','Ambiguous release PRs');
 let pr=prs.length?identity(prs[0]):null;
 if(record.pr&&!pr)refuse('identity','Journal PR no longer exists');
 if(!pr){
  const head=remoteHead(`refs/heads/${branch}`);if(head&&head!==record.head)refuse('head-moved','Remote release head moved');
  if(!head)pushRelease();stage('pushed');
  const body=path.join(path.dirname(journal),'body-'+crypto.randomBytes(6).toString('hex')+'.md');
  try{fs.writeFileSync(body,`Automated release cut for ${version}.\n\nBound release: ${repo} ${branch} ${record.head}.\n\nno-notes: release rollup contains the previously recorded entries.\n`);const url=gh('pr','create','--repo',repo,'--base',record.base,'--head',branch,'--title',`chore(release): ${version}`,'--body-file',body);if(!/^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/pull\/\d+$/.test(url))refuse('empty-pr-url','PR creation did not return a valid URL');}finally{fs.unlinkSync(body);}
  prs=json('pr','list','--repo',repo,'--head',branch,'--state','all','--json',fields);if(prs.length!==1)refuse('identity','Could not bind unique created PR');pr=identity(prs[0]);record.pr=pr.number;stage('pr');
 }else{record.pr=pr.number;atomicSave();}
 if(pr.state!=='MERGED'){
  if(pr.state!=='OPEN')refuse('identity',closedPr());
  queuedOrRefuse();
  unchangedBase();
  const contexts=requiredContexts();
  const required=registeredChecks();if(!Array.isArray(required)||!required.length||required.some(c=>!['pass','pending'].includes(c.bucket))){const bad=Array.isArray(required)?required.filter(c=>!['pass','pending'].includes(c.bucket)).map(c=>`${c.name} (${c.bucket})`):[];refuse('required-checks','Required checks missing, skipped or failed'+(bad.length?': '+bad.join(', '):'')+fixHint());}
  console.log(`release: waiting for required CI on PR #${record.pr}`);
  const watcher=spawnSync(process.execPath,[path.join(here,'watch-ci.mjs'),'--pr',String(record.pr),'--required','--interval-seconds',String(interval),'--max-wait-seconds',String(maxWait)],{cwd:root,encoding:'utf8',timeout:(maxWait+15)*1000,stdio:['ignore','inherit','pipe']});
  if(watcher.error||watcher.status!==0)refuse('ci',watcher.error?.message||trim(watcher.stderr||'CI watcher failed'));
  awaitContexts(contexts);
  pr=identity(json('pr','view',String(record.pr),'--repo',repo,'--json',fields));if(remoteHead(`refs/heads/${branch}`)!==record.head)refuse('head-moved','Release head moved before merge');
  unchangedBase();
  const attempt=command('gh',['pr','merge',String(record.pr),'--repo',repo,'--squash','--match-head-commit',record.head],root,true);
  const failed=Boolean(attempt.error)||attempt.status!==0;
  pr=identity(json('pr','view',String(record.pr),'--repo',repo,'--json',fields));
  if(pr.state!=='MERGED'){
   queuedOrRefuse();
   const policyRefusal=/the base branch policy prohibits the merge/;
   if(failed){
    if(policyRefusal.test(attempt.stderr||''))pending('merge-policy',`Release PR #${record.pr} is still open: GitHub's base branch policy has not accepted the merge yet; resume once it is satisfied`);
    refuse('github-command',`gh pr merge ${record.pr}: ${attempt.error?.message||(attempt.stderr||'').trim()||`exit ${attempt.status}`}`);
   }
   refuse('merge','Release PR did not merge');
  }
 }
 record.merge=sha(pr.mergeCommit?.oid,'merge');stage('merged');
 command('git',['fetch','--no-tags','origin',record.base]);
 if(command('git',['cat-file','-e',`${record.merge}:.github/workflows/release.yml`],root,true).status!==0){console.log('- Publication: SKIPPED (no release.yml; manual tagging retained)');console.log(`- Version: ${version}\n- PR: ${pr.url}\n- Merge SHA: ${record.merge}`);return;}
 boundedPoll(()=>json('run','list','--repo',repo,'--workflow','release.yml','--commit',record.merge,'--json','databaseId,headSha,status,conclusion'),runs=>{if(!Array.isArray(runs)||runs.length>1)refuse('workflow','Ambiguous workflow runs');if(!runs.length)return false;const r=runs[0];if(r.headSha!==record.merge)refuse('workflow','Workflow SHA mismatch');if(r.status!=='completed')return false;if(r.conclusion!=='success')refuse('workflow','Release workflow failed');return true;},'workflow-timeout');stage('workflow');
 const tags=git('ls-remote','--tags','origin',`refs/tags/${version}`,`refs/tags/${version}^{}`).split('\n').filter(Boolean);const peeled=tags.find(l=>l.endsWith(`refs/tags/${version}^{}`));if(!peeled||peeled.split(/\s/)[0]!==record.merge)refuse('tag-mismatch','Peeled remote tag does not equal merged release SHA');
 const release=json('release','view',version,'--repo',repo,'--json','body,url');if(typeof release.body!=='string'||trim(release.body)!==trim(record.notes))refuse('notes-mismatch','Published release body differs from rolled notes');if(!/^https:\/\/github\.com\//.test(release.url||''))refuse('release-url','Published release URL is missing');record.releaseUrl=release.url;stage('verified');
 const dependents=json('pr','list','--repo',repo,'--base',branch,'--state','open','--json','number');if(!Array.isArray(dependents)||dependents.length)refuse('dependent-pr','Release branch has dependent PRs');
 const head=remoteHead(`refs/heads/${branch}`);if(head&&head!==record.head&&!(record.superseded||[]).includes(head))refuse('cleanup-head-moved','Release branch moved before deletion');if(head)command('git',['push',`--force-with-lease=refs/heads/${branch}:${head}`,'origin',`:refs/heads/${branch}`]);stage('remote-deleted');
 const local=command('git',['rev-parse','--verify',`refs/heads/${branch}`],root,true);if(local.status===0){if(local.stdout.trim()!==record.head)refuse('cleanup-local-head','Local release branch moved');if(git('worktree','list','--porcelain').split('\n').map(l=>l.trimEnd()).includes(`branch refs/heads/${branch}`))refuse('cleanup-worktree','Release branch is checked out');command('git',['update-ref','-d',`refs/heads/${branch}`,record.head]);}stage('local-deleted');
 await syncBase();console.log(`## aai-release — complete\n- Version: ${version}\n- PR: ${pr.url}\n- Merge SHA: ${record.merge}\n- Tag SHA: ${record.merge}\n- Release: ${record.releaseUrl}\n- Branch: deleted`);
}
function shellQuote(value){return "'"+String(value).replaceAll("'",process.platform==='win32'?"''":"'\\''")+"'";}
const realOrResolve=p=>{try{return fs.realpathSync(p);}catch{return path.resolve(p);}};
if(process.argv[1]&&import.meta.url===pathToFileURL(realOrResolve(process.argv[1])).href)try{await main();}catch(e){console.error(`${e.pending?'PENDING':'REFUSED'}: ${e.causeName||'release'} — ${e.message}`);if(record)console.error(`Completed: stage=${record.stage}; release-head=${record.head||'pending'}; PR=${record.pr||'pending'}; merge=${record.merge||'pending'}`);if(version)console.error(`Resume: node ${shellQuote(path.join(here,'release-finish.mjs'))} --root ${shellQuote(root)} --version ${/^[A-Za-z0-9._/+\-]+$/.test(version)?version:shellQuote(version)} --confirm`);process.exitCode=e.pending?8:20;}finally{try{releaseClaim();}catch(e){console.error('Release claim cleanup failed: '+e.message);process.exitCode=20;}}
