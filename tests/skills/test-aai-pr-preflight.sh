#!/usr/bin/env bash
# pr-capability-preflight: the real CLI, disposable Git repositories, strict clients.
# The delimited Node matrix is also executed by the native Pester suite.
set -uo pipefail
ROOT="${AAI_PREFLIGHT_ROOT:-$PWD}"
run_case() {
  node - "$ROOT" "$1" <<'AAI_PREFLIGHT_MATRIX'
const fs = require('fs'), path = require('path'), os = require('os');
const {spawnSync, execFileSync} = require('child_process');
const assert = require('assert/strict');
const root = process.argv[2], id = process.argv[3];
const parentDynamicInstall = process.env.AZURE_EXTENSION_USE_DYNAMIC_INSTALL;
const cli = process.env.AAI_PR_PREFLIGHT || path.join(root,'.aai/scripts/pr-preflight.mjs');
const scratch = process.env.AAI_PREFLIGHT_SCRATCH || (process.platform === 'win32' ? os.tmpdir() : '/private/tmp/aai-pr-preflight-scratch');
fs.mkdirSync(scratch,{recursive:true});
const tmp = fs.mkdtempSync(path.join(scratch,'fixture-'));
const repo = path.join(tmp,'checkout with spaces 雪'), bin = path.join(tmp,'bin');
fs.mkdirSync(repo); fs.mkdirSync(bin);
function git(...args) { return execFileSync('git',args,{cwd:repo,encoding:'utf8',stdio:['ignore','pipe','pipe'],env:{...process.env,AAI_GIT_WRITE:'1',GIT_CONFIG_NOSYSTEM:'1'}}).trim(); }
git('init','-q'); git('config','user.name','Fixture'); git('config','user.email','fixture@example.invalid');
fs.writeFileSync(path.join(repo,'file'),'base'); git('add','file'); git('commit','-qm','base'); git('branch','-M','change/pr-capability-preflight');
const log = path.join(tmp,'calls.jsonl'), pidFile = path.join(tmp,'pid');
const azArgs = [
 ['--version'],
 ['extension','show','--name','azure-devops','--output','json','--only-show-errors'],
 ['repos','show','--organization','https://dev.azure.com/Org','--project','Project 雪','--repository','Repo Name','--detect','false','--output','json','--only-show-errors']
];
const ghArgs = [['--version'],['auth','status','--hostname','github.com'],['repo','view','Org/Repo','--json','nameWithOwner,url']];
// A strict stub compares the entire argument vector and environment before answering.
const stub = path.join(tmp,'client.cjs');
fs.writeFileSync(stub,`const fs=require('fs'); const name=process.argv[2],args=process.argv.slice(3),mode=process.env.FIX_MODE;
const allowed=JSON.parse(process.env.FIX_ALLOWED)[name];
const step=allowed.findIndex(x=>JSON.stringify(x)===JSON.stringify(args));
fs.appendFileSync(process.env.FIX_LOG,JSON.stringify({name,args,env:{AZURE_EXTENSION_USE_DYNAMIC_INSTALL:process.env.AZURE_EXTENSION_USE_DYNAMIC_INSTALL,AZURE_CORE_NO_COLOR:process.env.AZURE_CORE_NO_COLOR,GH_HOST:process.env.GH_HOST,AZ_INSTALLER:process.env.AZ_INSTALLER}})+'\\n');
if(step<0) {console.error('DENIED unexpected argv');process.exit(91);}
if(name==='az'&&process.env.AZURE_EXTENSION_USE_DYNAMIC_INSTALL!=='no')process.exit(92);
let gotInput=false; process.stdin.on('data',()=>{gotInput=true}); process.stdin.on('end',()=>{
 if(gotInput)process.exit(93);
 if(mode==='hang'&&step===0){fs.writeFileSync(process.env.FIX_PID,String(process.pid));setInterval(()=>{},1000);return;}
 if(mode==='overflow'&&step===0){process.stdout.write('x'.repeat(1100000));return;}
 if(mode==='secrets'&&step===2){console.error('ghp_SYNTHETIC_SECRET sk_live_SYNTHETIC_SECRET AKIASYNTHETICSECRET');process.exit(1);}
 if(mode==='extension'&&step===1){console.error('extension not installed');process.exit(1);}
 if(mode==='broken-extension'&&step===1){console.log('{}');return;}
 if(step===2&&['auth','network','denied','bad'].includes(mode)){if(mode==='bad'){console.log('{');return;} console.error({auth:'authentication failed login required',network:'connection timed out DNS resolution failed',denied:'denied or not found'}[mode]);process.exit(1);}
 if(name==='gh'&&mode==='gh-auth'&&step===1){console.error('not logged in');process.exit(1);}
 if(step===0){console.log(name+' version fixture');return;}
 if(name==='az'&&step===1){console.log(JSON.stringify({name:'azure-devops',version:'1.0.0'}));return;}
 if(name==='az'){console.log(JSON.stringify({name:mode==='mismatch'?'Other':'Repo Name',project:{name:'Project 雪'},remoteUrl:'https://dev.azure.com/Org/Project%20%E9%9B%AA/_git/Repo%20Name'}));return;}
 if(step===1){console.log('authenticated');return;}
 console.log(JSON.stringify({nameWithOwner:mode==='mismatch'?'Other/Repo':'Org/Repo',url:'https://'+process.env.FIX_HOST+'/Org/Repo'}));
}); process.stdin.resume();`);
function install(name) {
 if(process.platform==='win32') {
   // Native tests supply an executable shim, avoiding shell wrappers entirely.
   const shim = process.env.AAI_PREFLIGHT_NATIVE_SHIM;
   assert.ok(shim,'native executable shim required');
   if(name==='az') {
     fs.copyFileSync(shim,path.join(tmp,'python.exe'));
     fs.writeFileSync(path.join(bin,'az.cmd'),[':: Microsoft Azure CLI - Windows Installer - Author file components script','@IF EXIST "%~dp0\\..\\python.exe" (','SET AZ_INSTALLER=MSI','"%~dp0\\..\\python.exe" -IBm azure.cli %*',') ELSE (','echo Failed to load python executable.','exit /b 1',')'].join('\r\n'));
   } else fs.copyFileSync(shim,path.join(bin,name+'.exe'));
 } else {
   fs.writeFileSync(path.join(bin,name),'#!/bin/sh\nexec "'+process.execPath+'" "'+stub+'" '+name+' "$@"\n',{mode:0o755});
 }
}
install('az'); install('gh');
let input = {schema_version:1,repo_root:repo,remote_name:'origin',source_branch:'change/pr-capability-preflight',target_branch:'main',organization_url:'https://dev.azure.com/Org',project:'Project 雪',repository:'Repo Name'};
let host='github.com';
function azure(url='https://dev.azure.com/Org/Project%20%E9%9B%AA/_git/Repo%20Name') {try{git('remote','remove','origin')}catch{} git('remote','add','origin',url);}
function github(h='github.com') {host=h; azure('https://'+h+'/Org/Repo.git'); input={schema_version:1,repo_root:repo,remote_name:'origin',source_branch:'change/pr-capability-preflight',target_branch:'main',repository:'Org/Repo'}; ghArgs[1][3]=h;}
function calls() {return fs.existsSync(log)?fs.readFileSync(log,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse):[];}
function run(mode='ok',extra=[],override={}) {
 fs.writeFileSync(log,''); const file=path.join(tmp,'input.json'); fs.writeFileSync(file,JSON.stringify(input));
 const env={...process.env,PATH:bin+path.delimiter+process.env.PATH,FIX_MODE:mode,FIX_ALLOWED:JSON.stringify({az:azArgs,gh:ghArgs}),FIX_LOG:log,FIX_PID:pidFile,FIX_HOST:host,AAI_NATIVE_NODE:process.execPath,AAI_NATIVE_STUB:stub,...override};
 const start=Date.now(); const r=spawnSync(process.execPath,[cli,'--input',file,'--json',...extra],{env,encoding:'utf8',timeout:4000,maxBuffer:2000000});
 assert.equal(r.error,undefined,'CLI must finish within harness bound');
 let json; try{json=JSON.parse(r.stdout)}catch{assert.fail('one parseable JSON result required: '+String(r.stdout).slice(0,200));}
 return {...r,json,ms:Date.now()-start};
}
function expect(r,status,code) {assert.equal(r.status,status,'exit '+code);assert.equal(r.json.code,code);assert.equal(r.json.create_permission,'unknown');assert.equal(r.json.schema_version,1);if(status){assert.ok(r.json.operation);assert.ok(r.json.remedy);assert.ok(r.stderr.trim());}}
function refusal(change) {const saved={...input};Object.assign(input,change);const r=run();expect(r,2,'IDENTITY_INVALID');assert.equal(calls().length,0,'identity refusal precedes clients');input=saved;}
azure();
try {
 if(id==='001') {
  const verified=run();expect(verified,0,'READ_VERIFIED'); assert.equal(calls().length,3);console.log('INFO: TEST-001 '+JSON.stringify({result:verified.json,calls:calls()})); assert.match(run().json.head_sha,/^[0-9a-f]{40,64}$/);
  for(const change of [{source_branch:'other'},{target_branch:input.source_branch},{repository:'Other'},{project:'Other'},{organization_url:'https://dev.azure.com/Other'},{remote_name:'missing'},{schema_version:2},{surprise:true},{target_branch:''},{source_branch:'bad..branch'},{repo_root:'relative'}])refusal(change);
  const saved=input.target_branch;delete input.target_branch;expect(run(),2,'IDENTITY_INVALID');assert.equal(calls().length,0);input.target_branch=saved;
  git('checkout','--detach','-q');expect(run(),2,'IDENTITY_INVALID');assert.equal(calls().length,0);git('checkout','-q','change/pr-capability-preflight');
  for(const url of ['git@ssh.dev.azure.com:v3/Org/Project%20%E9%9B%AA/Repo%20Name','https://Org.visualstudio.com/Project%20%E9%9B%AA/_git/Repo%20Name']){azure(url);expect(run(),0,'READ_VERIFIED');}
  azure('https://dev.azure.com/Org/Project/_git/Repo/extra');expect(run(),2,'IDENTITY_INVALID');assert.equal(calls().length,0);
  github();expect(run(),0,'READ_VERIFIED');
  for(const args of [['--json'],['--unknown'],['--timeout-ms','200','--timeout-ms','200']]) {expect(run('ok',args),2,'IDENTITY_INVALID');assert.equal(calls().length,0);}
  const savedInput=input;for(const empty of [{},[],null]){input=empty;expect(run(),2,'IDENTITY_INVALID');assert.equal(calls().length,0);}input=savedInput;
 } else if(id==='002') {
  const launcherDir=path.join(tmp,'launch-bin');fs.mkdirSync(launcherDir);const wrapper=path.join(launcherDir,'az.cmd');if(!fs.existsSync(path.join(tmp,'python.exe')))fs.writeFileSync(path.join(tmp,'python.exe'),'fixture');
  const launchLines=[':: official fixture','@IF EXIST "%~dp0\\..\\python.exe" (','SET AZ_INSTALLER=MSI','"%~dp0\\..\\python.exe" -IBm azure.cli %*',') ELSE (','echo Failed to load python executable.','exit /b 1',')'];
  const importCode='import {azureWindowsLauncher} from '+JSON.stringify(require('url').pathToFileURL(cli).href)+'; try {console.log(JSON.stringify(azureWindowsLauncher(process.argv[1])))} catch {process.exitCode=3}';
  for(const variant of ['MSI','ZIP']){launchLines[2]='SET AZ_INSTALLER='+variant;fs.writeFileSync(wrapper,launchLines.join('\r\n'));const resolved=spawnSync(process.execPath,['--input-type=module','-e',importCode,wrapper],{encoding:'utf8'});assert.equal(resolved.status,0,'known Windows launcher parsed');const record=JSON.parse(resolved.stdout);assert.equal(record.installer,variant);assert.deepEqual(record.prefix,['-IBm','azure.cli']);assert.equal(record.bin,path.join(tmp,'python.exe'));}
  fs.appendFileSync(wrapper,'\r\necho unexpected');assert.equal(spawnSync(process.execPath,['--input-type=module','-e',importCode,wrapper],{encoding:'utf8'}).status,3,'unknown batch text refused');
  const r=run();expect(r,0,'READ_VERIFIED');assert.equal(r.json.outcome,'read_verified');assert.deepEqual(calls().map(c=>c.args),azArgs);console.log('INFO: TEST-002 '+JSON.stringify({result:r.json,calls:calls()}));assert.equal(process.env.AZURE_EXTENSION_USE_DYNAMIC_INSTALL,parentDynamicInstall);
  assert.ok(calls().every(c=>c.env.AZURE_CORE_NO_COLOR==='true'));
  if(process.platform==='win32'){const liveWrapper=path.join(bin,'az.cmd'),original=fs.readFileSync(liveWrapper,'utf8');assert.ok(calls().every(c=>c.env.AZ_INSTALLER==='MSI'));fs.writeFileSync(liveWrapper,original.replace('AZ_INSTALLER=MSI','AZ_INSTALLER=ZIP'));expect(run(),0,'READ_VERIFIED');assert.ok(calls().every(c=>c.env.AZ_INSTALLER==='ZIP'));fs.appendFileSync(liveWrapper,'\r\necho unexpected');expect(run(),3,'ACCESS_UNKNOWN');assert.equal(calls().length,0,'unknown cmd never executed');fs.writeFileSync(liveWrapper,original);}
  expect(run('extension'),3,'EXTENSION_MISSING');assert.equal(calls().length,2,'no repos without extension');
  expect(run('mismatch'),3,'PROVIDER_RESULT_INVALID');assert.equal(calls().length,3);
 } else if(id==='003') {
  const missing=path.join(tmp,'missing-bin');fs.mkdirSync(missing); // git still needed; copy a link to it on POSIX.
  if(process.platform!=='win32')fs.symlinkSync(execFileSync('which',['git'],{encoding:'utf8'}).trim(),path.join(missing,'git'));
  const gitPath=process.platform==='win32'?path.dirname(execFileSync('where',['git.exe'],{encoding:'utf8'}).split(/\r?\n/)[0]):missing;
  expect(run('ok',[],{PATH:gitPath}),3,'CLIENT_MISSING');
  for(const [mode,code,operation] of [['extension','EXTENSION_MISSING','az.extension'],['broken-extension','EXTENSION_MISSING','az.extension'],['auth','AUTH_FAILED','az.repository'],['network','NETWORK_FAILED','az.repository'],['denied','ACCESS_UNKNOWN','az.repository'],['bad','PROVIDER_RESULT_INVALID','az.repository']]) {const r=run(mode);expect(r,3,code);assert.equal(r.json.operation,operation);assert.ok(calls().every(c=>!c.args.some(a=>['install','create','login','set'].includes(a))));}
 } else if(id==='004') {
  for(const n of ['0','99','60001','2.5','NaN']){expect(run('ok',['--timeout-ms',n]),2,'IDENTITY_INVALID');assert.equal(calls().length,0);}
  const r=run('hang',['--timeout-ms','1000']);expect(r,124,'PROBE_TIMEOUT');assert.equal(r.json.operation,'az.version');assert.ok(r.ms<=3000);assert.equal(calls().length,1);const pid=Number(fs.readFileSync(pidFile));let alive=true;try{process.kill(pid,0)}catch{alive=false}assert.equal(alive,false,'timed-out child is gone');console.log('INFO: TEST-004 elapsed_ms='+r.ms+' child_alive='+alive+' later_probes=0');
 } else if(id==='005') {
  azure('https://user:ghp_REMOTE_SYNTHETIC@dev.azure.com/Org/Project%20%E9%9B%AA/_git/Repo%20Name');const r=run('secrets');expect(r,3,'ACCESS_UNKNOWN');assert.equal(calls().length,3,'secret emitter reached');assert.doesNotMatch(r.stdout+r.stderr,/ghp_|sk_live_|AKIA|user:/);assert.ok(r.stderr.includes('ACCESS_UNKNOWN'));
  const large=run('overflow');expect(large,3,'PROVIDER_RESULT_INVALID');assert.equal(calls().length,1);assert.ok(large.stdout.length<10000);
 } else if(id==='006') {
  const prompt=fs.readFileSync(path.join(root,'.aai/SKILL_PR.prompt.md'),'utf8');const invocation=prompt.indexOf('node .aai/scripts/pr-preflight.mjs --input <preflight-input.json> --json');assert.ok(invocation>=0,'actual readiness invocation exists');assert.ok(invocation<prompt.indexOf('PROCESS\n'),'readiness in PRECONDITIONS');assert.match(prompt,/missing STATE.*readiness succeeds/s,'fresh STATE initialization follows readiness');assert.match(prompt,/release --pid/);assert.match(prompt,/Nonzero.*STOP/);
  fs.mkdirSync(path.join(repo,'docs/ai'),{recursive:true});fs.writeFileSync(path.join(repo,'docs/ai/STATE.yaml'),'sentinel state');git('update-ref','refs/aai/reservations/local',git('rev-parse','HEAD'));git('update-ref','refs/remotes/origin/aai-reservations',git('rev-parse','HEAD'));
  const snapshot=()=>JSON.stringify([fs.existsSync(path.join(repo,'docs/ai/STATE.yaml'))?fs.readFileSync(path.join(repo,'docs/ai/STATE.yaml'),'hex'):null,git('write-tree'),git('rev-parse','HEAD'),git('for-each-ref','--format=%(refname) %(objectname)','refs/aai','refs/remotes')]);const before=snapshot();expect(run('extension'),3,'EXTENSION_MISSING');assert.equal(calls().length,2);assert.equal(snapshot(),before,'refusal preserves state/index/head/reservations');expect(run(),0,'READ_VERIFIED');assert.equal(calls().length,3);
  const stateFile=path.join(repo,'docs/ai/STATE.yaml');fs.unlinkSync(stateFile);const absent=snapshot();
  function freshCeremony(mode){const observed=run(mode);if(observed.status===0){const repair=spawnSync(process.execPath,[path.join(root,'.aai/scripts/check-state.mjs'),'--repair',stateFile],{cwd:repo,encoding:'utf8'});assert.equal(repair.status,0,'successful readiness reaches real STATE repair');assert.match(repair.stdout,/CREATED:/);}return observed;}
  expect(freshCeremony('extension'),3,'EXTENSION_MISSING');assert.equal(fs.existsSync(stateFile),false,'refusal leaves missing STATE absent');assert.equal(snapshot(),absent);expect(freshCeremony('ok'),0,'READ_VERIFIED');assert.equal(fs.existsSync(stateFile),true);assert.equal(calls().length,3,'success path reached provider then STATE initialization');

 } else if(id==='007') {
  github('enterprise.github.com');expect(run(),0,'READ_VERIFIED');assert.deepEqual(calls().map(c=>c.args),ghArgs);assert.ok(calls().every(c=>c.env.GH_HOST===host));expect(run('gh-auth'),3,'AUTH_FAILED');assert.equal(calls().length,2);expect(run('mismatch'),3,'PROVIDER_RESULT_INVALID');
  delete input.repository;azure('https://gitlab.com/Org/Repo.git');const r=run();expect(r,0,'CAPABILITY_NOT_APPLICABLE');assert.equal(calls().length,0);assert.match(r.json.remedy,/GENERIC MODE/);
  git('remote','remove','origin');input.remote_name=null;expect(run(),0,'CAPABILITY_NOT_APPLICABLE');assert.equal(calls().length,0);
 } else if(id==='008') {
  const profiles=fs.readFileSync(path.join(root,'.aai/system/PROFILES.yaml'),'utf8');const core=profiles.split(/^core:\s*$/m)[1].split(/^\S/m)[0];assert.match(core,/  - \.aai\/scripts\/pr-preflight\.mjs/,'new script core');
  const changed=path.join(tmp,'changed.txt');fs.writeFileSync(changed,'.aai/scripts/pr-preflight.mjs\n');const selected=spawnSync(process.execPath,[path.join(root,'.aai/scripts/select-suites.mjs'),'--files-from',changed],{cwd:root,encoding:'utf8'});assert.equal(selected.status,0);assert.match(selected.stdout,/aai-pr-preflight/,'suite selected for actual script');
  const ledger=fs.readFileSync(path.join(root,'tests/skills/lib/prompt-diet-ledger.sh'),'utf8');const entry=ledger.match(/JUSTIFIED_ADDITIONS\+=\( "(\d+) pr-capability-preflight /);assert.ok(entry,'measured ledger entry');const base=execFileSync('git',['show','bdeb425c040ada918dd97e5b878b71e420bad83a:.aai/SKILL_PR.prompt.md'],{cwd:root});assert.equal(Number(entry[1]),fs.statSync(path.join(root,'.aai/SKILL_PR.prompt.md')).size-base.length,'actual prompt growth');
  const diet=fs.readFileSync(path.join(root,'tests/skills/test-aai-prompt-diet.sh'),'utf8');assert.match(diet,new RegExp('local want_growth='+String(54252+Number(entry[1]))));
 }
 console.log('PASS: TEST-'+id+' pr-capability-preflight');
} catch(e) {console.error('FAIL: TEST-'+id+' '+e.message);process.exitCode=1;}
finally{if(fs.existsSync(pidFile)){const pid=Number(fs.readFileSync(pidFile));try{if(process.platform==='win32')spawnSync('taskkill',['/PID',String(pid),'/T','/F'],{stdio:'ignore'});else process.kill(-pid,'SIGKILL');}catch{}}fs.rmSync(tmp,{recursive:true,force:true});}
AAI_PREFLIGHT_MATRIX
}
test_001() { run_case 001; }
test_002() { run_case 002; }
test_003() { run_case 003; }
test_004() { run_case 004; }
test_005() { run_case 005; }
test_006() { run_case 006; }
test_007() { run_case 007; }
test_008() { run_case 008; }
if [[ $# -gt 0 ]]; then
  case "$1" in test_00[1-8]) ;; *) echo "Unknown selector: $1" >&2; exit 2;; esac
  declare -F "$1" >/dev/null || exit 2
  "$1"
else
  failed=0
  for test in test_001 test_002 test_003 test_004 test_005 test_006 test_007 test_008; do
    "$test" || failed=1
  done
  exit "$failed"
fi
