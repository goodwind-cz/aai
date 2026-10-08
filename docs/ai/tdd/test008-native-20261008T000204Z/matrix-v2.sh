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
const scratch = process.env.AAI_PREFLIGHT_SCRATCH || path.join(os.tmpdir(),'aai-pr-preflight-scratch');
if(!process.env.AAI_PREFLIGHT_SCRATCH){assert.equal(scratch,path.join(os.tmpdir(),'aai-pr-preflight-scratch'));console.log('INFO: scratch_override=unset platform='+process.platform+' uid='+(process.getuid?process.getuid():'unavailable'));}
fs.mkdirSync(scratch,{recursive:true});
const tmp = fs.mkdtempSync(path.join(scratch,'fixture-'));
const repo = path.join(tmp,'checkout with spaces 雪'), bin = path.join(tmp,'bin');
fs.mkdirSync(repo); fs.mkdirSync(bin);
function git(...args) { return execFileSync('git',args,{cwd:repo,encoding:'utf8',stdio:['ignore','pipe','pipe'],env:{...process.env,AAI_GIT_WRITE:'1',GIT_CONFIG_NOSYSTEM:'1'}}).trim(); }
git('init','-q'); git('config','user.name','Fixture'); git('config','user.email','fixture@example.invalid');
fs.writeFileSync(path.join(repo,'file'),'base'); git('add','file'); git('commit','-qm','base'); git('branch','-M','change/pr-capability-preflight');
const realGit=execFileSync(process.platform==='win32'?'where':'which',[process.platform==='win32'?'git.exe':'git'],{encoding:'utf8'}).split(/\r?\n/)[0].trim();
const realGitEol=execFileSync(realGit,['--version'],{encoding:'utf8',stdio:['ignore','pipe','pipe']}).endsWith('\r\n')?'\r\n':'\n';
const gitLog=path.join(tmp,'git-calls.jsonl');
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
if(name==='git'){if(process.env.FIX_PUSH_OUTPUT_HEX&&JSON.stringify(args)===JSON.stringify(['-C',process.env.FIX_REPO_ROOT,'remote','get-url','--push','--all','--','origin'])){fs.appendFileSync(process.env.FIX_GIT_LOG,JSON.stringify({blank_fixture:true,args})+'\\n');process.stdout.write(Buffer.from(process.env.FIX_PUSH_OUTPUT_HEX,'hex'));process.exit(0);}if(process.env.FIX_DELAY_MS)Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,Number(process.env.FIX_DELAY_MS));fs.appendFileSync(process.env.FIX_GIT_LOG,JSON.stringify({args,GIT_TERMINAL_PROMPT:process.env.GIT_TERMINAL_PROMPT,GH_PROMPT_DISABLED:process.env.GH_PROMPT_DISABLED})+'\\n');const crlf=process.env.FIX_GIT_CRLF==='1';const r=require('child_process').spawnSync(process.env.FIX_REAL_GIT,args,{stdio:crlf?['ignore','pipe','pipe']:'inherit',encoding:'utf8',env:process.env});if(crlf){process.stdout.write((r.stdout||'').split(process.env.FIX_REAL_GIT_EOL).join('\\r\\n'));process.stderr.write(r.stderr||'');}process.exit(r.status===null?95:r.status);}
const allowed=JSON.parse(process.env.FIX_ALLOWED)[name];
const step=allowed.findIndex(x=>JSON.stringify(x)===JSON.stringify(args));
fs.appendFileSync(process.env.FIX_LOG,JSON.stringify({name,args,env:{AZURE_EXTENSION_USE_DYNAMIC_INSTALL:process.env.AZURE_EXTENSION_USE_DYNAMIC_INSTALL,AZURE_CORE_NO_COLOR:process.env.AZURE_CORE_NO_COLOR,GH_HOST:process.env.GH_HOST,GIT_TERMINAL_PROMPT:process.env.GIT_TERMINAL_PROMPT,GH_PROMPT_DISABLED:process.env.GH_PROMPT_DISABLED,AZ_INSTALLER:process.env.AZ_INSTALLER}})+'\\n');
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
 if(name==='az'){const raw=JSON.stringify({name:mode==='mismatch'?'Other':'Repo Name',project:{name:'Project 雪'},remoteUrl:'https://dev.azure.com/Org/Project%20%E9%9B%AA/_git/Repo%20Name'});if(mode==='split-unicode'){const bytes=Buffer.from(raw),cut=bytes.indexOf(Buffer.from('雪'))+1;fs.appendFileSync(process.env.FIX_LOG,JSON.stringify({split_fixture:true,cut,bytes:bytes.length})+'\\n');process.stdout.write(bytes.subarray(0,cut));setTimeout(()=>process.stdout.write(bytes.subarray(cut)),100);return;}console.log(raw);return;}
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
install('az'); install('gh'); install('git');
let input = {schema_version:1,repo_root:repo,remote_name:'origin',source_branch:'change/pr-capability-preflight',target_branch:'main',organization_url:'https://dev.azure.com/Org',project:'Project 雪',repository:'Repo Name'};
let host='github.com',invocation=0;
// Seven identity Git probes plus three provider probes run sequentially.
const MAX_CLI_PROBES=10,STARTUP_ALLOWANCE_MS=5000;
function azure(url='https://dev.azure.com/Org/Project%20%E9%9B%AA/_git/Repo%20Name') {try{git('remote','remove','origin')}catch{} git('remote','add','origin',url);}
function github(h='github.com') {host=h; azure('https://'+h+'/Org/Repo.git'); input={schema_version:1,repo_root:repo,remote_name:'origin',source_branch:'change/pr-capability-preflight',target_branch:'main',repository:'Org/Repo'}; ghArgs[1][3]=h;}
function calls() {return fs.existsSync(log)?fs.readFileSync(log,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse):[];}
function run(mode='ok',extra=[],override={},entry=cli) {
 fs.writeFileSync(log,''); fs.writeFileSync(gitLog,''); const file=path.join(tmp,'input.json'); fs.writeFileSync(file,JSON.stringify(input));
 const env={...process.env,PATH:bin+path.delimiter+process.env.PATH,FIX_MODE:mode,FIX_REAL_GIT:realGit,FIX_REPO_ROOT:repo,FIX_REAL_GIT_EOL:realGitEol,FIX_GIT_LOG:gitLog,FIX_ALLOWED:JSON.stringify({az:azArgs,gh:ghArgs}),FIX_LOG:log,FIX_PID:pidFile,FIX_HOST:host,AAI_NATIVE_NODE:process.execPath,AAI_NATIVE_STUB:stub,...override};
 const requestedTimeout=extra.includes('--timeout-ms')?Number(extra[extra.indexOf('--timeout-ms')+1]):10000;
 const timeout=mode==='hang'?4000:MAX_CLI_PROBES*(Number.isFinite(requestedTimeout)&&requestedTimeout>=100?requestedTimeout:10000)+STARTUP_ALLOWANCE_MS;
 const sequence=++invocation,start=Date.now(); const r=spawnSync(process.execPath,[entry,'--input',file,'--json',...extra],{env,encoding:'utf8',timeout,maxBuffer:2000000});
 const elapsed=Date.now()-start,diagnostic={test:id,sequence,mode,timeout_ms:timeout,elapsed_ms:elapsed,error_code:r.error?.code||null,signal:r.signal,git_probes:fs.existsSync(gitLog)?fs.readFileSync(gitLog,'utf8').trim().split('\n').filter(Boolean).length:0,provider_steps:calls().filter(c=>c.name).map(c=>c.name+'.'+c.args[0]).slice(-3),stdout_bytes:Buffer.byteLength(r.stdout||'')};
 if(r.error||elapsed>=4000)console.log('INFO: CLI_BOUND '+JSON.stringify(diagnostic));
 assert.equal(r.error,undefined,'CLI must finish within harness bound: '+JSON.stringify(diagnostic));
 let json; try{json=JSON.parse(r.stdout)}catch{assert.fail('one parseable JSON result required: '+String(r.stdout).slice(0,200));}
 return {...r,json,ms:Date.now()-start};
}
function expect(r,status,code) {assert.equal(r.status,status,'exit '+code);assert.equal(r.json.code,code);assert.equal(r.json.create_permission,'unknown');assert.equal(r.json.schema_version,1);if(status){assert.ok(r.json.operation);assert.ok(r.json.remedy);assert.ok(r.stderr.trim());}}
function refusal(change) {const saved={...input};Object.assign(input,change);const r=run();expect(r,2,'IDENTITY_INVALID');assert.equal(calls().length,0,'identity refusal precedes clients');input=saved;}
azure();
try {
 if(id==='001') {
  const linkDir=path.join(tmp,'linked-scripts');fs.symlinkSync(path.dirname(cli),linkDir,process.platform==='win32'?'junction':'dir');const direct=run(),linked=run('ok',[],{},path.join(linkDir,path.basename(cli)));assert.equal(linked.status,direct.status);assert.equal(linked.stdout,direct.stdout);assert.equal(linked.stderr,direct.stderr);console.log('INFO: TEST-001 direct_symlink_exit_output_equal=true');
  const verified=run();expect(verified,0,'READ_VERIFIED'); assert.equal(calls().length,3);console.log('INFO: TEST-001 '+JSON.stringify({result:verified.json,calls:calls()})); assert.match(run().json.head_sha,/^[0-9a-f]{40,64}$/);
  for(const change of [{source_branch:'other'},{target_branch:input.source_branch},{repository:'Other'},{project:'Other'},{organization_url:'https://dev.azure.com/Other'},{remote_name:'missing'},{schema_version:2},{surprise:true},{target_branch:''},{source_branch:'bad..branch'},{repo_root:'relative'}])refusal(change);
  const saved=input.target_branch;delete input.target_branch;expect(run(),2,'IDENTITY_INVALID');assert.equal(calls().length,0);input.target_branch=saved;
  git('checkout','--detach','-q');expect(run(),2,'IDENTITY_INVALID');assert.equal(calls().length,0);git('checkout','-q','change/pr-capability-preflight');
  for(const url of ['git@ssh.dev.azure.com:v3/Org/Project%20%E9%9B%AA/Repo%20Name','https://Org.visualstudio.com/Project%20%E9%9B%AA/_git/Repo%20Name','Org@vs-ssh.visualstudio.com:v3/Org/Project%20%E9%9B%AA/Repo%20Name']){azure(url);expect(run(),0,'READ_VERIFIED');}
  azure('https://dev.azure.com/Org/Project/_git/Repo/extra');expect(run(),2,'IDENTITY_INVALID');assert.equal(calls().length,0);
  github();expect(run(),0,'READ_VERIFIED');
  const ordinary='https://github.com/Org/Repo.git';
  function rawGit(...args){return execFileSync(realGit,args,{cwd:repo,stdio:['ignore','pipe','pipe'],env:{...process.env,AAI_GIT_WRITE:'1',GIT_CONFIG_NOSYSTEM:'1'}});}
  function quotedEndpoint(endpoint,value){
   try{git('config','--unset-all','remote.origin.'+endpoint)}catch{}
   // Literal CR inside Git quotes survives old Git config parsing.
   const encoded=value.replace(/\\/g,'\\\\').replace(/"/g,'\\"').replace(/\n/g,'\\n').replace(/\t/g,'\\t');
   fs.appendFileSync(path.join(repo,'.git','config'),'\n[remote "origin"]\n\t'+endpoint+' = "'+encoded+'"\n');
   assert.deepEqual(rawGit('config','--null','--get-all','remote.origin.'+endpoint),Buffer.from(value+'\0'),'quoted config round-trip retains endpoint bytes');
   const args=['remote','get-url',...(endpoint==='pushurl'?['--push']:[]),'--all','origin'];
   const effective=rawGit(...args);assert.deepEqual(effective,Buffer.from(value+realGitEol),'real Git effective endpoint retains seeded bytes');
   console.log('INFO: TEST001_ENDPOINT '+JSON.stringify({endpoint,supplied_hex:Buffer.from(value).toString('hex'),effective_hex:effective.toString('hex')}));
  }
  for(const endpoint of ['url','pushurl'])for(const malformed of [' '+ordinary,ordinary+' ', '\t'+ordinary,ordinary+'\t','\r'+ordinary,ordinary+'\r',ordinary+'\n', '\n'+ordinary,ordinary+'\n'+ordinary,ordinary+'\r'+ordinary]){
   github();quotedEndpoint(endpoint,malformed);
   const refused=run();expect(refused,2,'IDENTITY_INVALID');assert.equal(calls().length,0,'malformed effective '+endpoint+' refused before providers');assert.equal(refused.json.operation,'git.push-destination');
  }
  // Derive this host's contract from real effective bytes, never from CLI outcome.
  const gitVersion=rawGit('--version').toString().trim();
  for(const destinations of [[ordinary,''],['',ordinary]]){
   github();for(const value of destinations)git('config','--add','remote.origin.pushurl',value);
   const effective=rawGit('remote','get-url','--push','--all','origin'),single=effective.equals(Buffer.from(ordinary+realGitEol));
   if(!single)assert.ok([ordinary+realGitEol+realGitEol,realGitEol+ordinary+realGitEol].some(v=>effective.equals(Buffer.from(v))),'observed effective output is single URL or explicit blank destination');
   const observed=run();expect(observed,single?0:2,single?'READ_VERIFIED':'IDENTITY_INVALID');assert.equal(calls().length,single?3:0);
   console.log('INFO: TEST001_EMPTY '+JSON.stringify({git_version:gitVersion,configured_order:destinations,effective_hex:effective.toString('hex'),expected:single?'READ_VERIFIED':'IDENTITY_INVALID',provider_calls:calls().length}));
  }
  github();
  for(const raw of [realGitEol+ordinary+realGitEol,ordinary+realGitEol+realGitEol,realGitEol]){
   const refused=run('ok',[],{FIX_PUSH_OUTPUT_HEX:Buffer.from(raw).toString('hex')});expect(refused,2,'IDENTITY_INVALID');assert.equal(refused.json.operation,'git.push-destination');assert.equal(calls().length,0,'blank effective destination refuses on every host Git');assert.equal(fs.readFileSync(gitLog,'utf8').split('\n').filter(Boolean).map(JSON.parse).filter(c=>c.blank_fixture).length,1,'blank output fixture reached actual push query');
  }
  console.log('INFO: TEST001_BLANK deterministic_blank_first_last_only_refused=true provider_calls=0');
  github();
  github();expect(run('ok',[],{FIX_GIT_CRLF:'1'}),0,'READ_VERIFIED');assert.equal(calls().length,3,'ordinary CRLF Git process delimiter supported');quotedEndpoint('pushurl',ordinary+'\r');expect(run('ok',[],{FIX_GIT_CRLF:'1'}),2,'IDENTITY_INVALID');assert.equal(calls().length,0,'URL CR retained under CRLF Git process delimiter');github();
  git('config','remote.origin.pushurl','https://github.com/Org/Repo.git');expect(run(),0,'READ_VERIFIED');assert.equal(calls().length,3,'one matching explicit push destination succeeds');
  for(const destinations of [['https://dev.azure.com/Other/Project/_git/Other'],['https://github.com/Other/Repo.git'],['https://github.com/Org/Repo.git','https://github.com/Other/Repo.git'],['https://github.com/Org/Repo.git','https://github.com/Org/Repo.git']]){
   git('config','--unset-all','remote.origin.pushurl');for(const url of destinations)git('config','--add','remote.origin.pushurl',url);
   const refused=run();expect(refused,2,'IDENTITY_INVALID');assert.equal(calls().length,0,'push destination refusal precedes providers');assert.equal(refused.json.operation,'git.push-destination');
  }
  git('config','--unset-all','remote.origin.pushurl');
  const rewriteKey='url.https://dev.azure.com/Other/Project/_git/.pushInsteadOf';git('config',rewriteKey,'https://github.com/Org/');expect(run(),2,'IDENTITY_INVALID');assert.equal(calls().length,0,'effective pushInsteadOf destination checked');git('config','--unset-all',rewriteKey);
  git('config','--add','remote.origin.url','https://github.com/Other/Repo.git');expect(run(),2,'IDENTITY_INVALID');assert.equal(calls().length,0,'multiple fetch destinations refuse');git('config','--unset-all','remote.origin.url');git('config','remote.origin.url','https://github.com/Org/Repo.git');expect(run(),0,'READ_VERIFIED');console.log('INFO: TEST-001 pushurl_divergent_multiple_rewrite_refused=true ordinary_single_positive=true');
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
  expect(run('ok',[],{GIT_TERMINAL_PROMPT:'1',GH_PROMPT_DISABLED:'0'}),0,'READ_VERIFIED');assert.ok(calls().every(c=>c.env.GIT_TERMINAL_PROMPT==='0'&&c.env.GH_PROMPT_DISABLED==='1'));const gitProbes=fs.readFileSync(gitLog,'utf8').trim().split('\n').map(JSON.parse);assert.ok(gitProbes.length>=6,'Git identity probes reached');assert.ok(gitProbes.every(c=>c.GIT_TERMINAL_PROMPT==='0'&&c.GH_PROMPT_DISABLED==='1'));
  if(process.platform==='win32'){const liveWrapper=path.join(bin,'az.cmd'),original=fs.readFileSync(liveWrapper,'utf8');assert.ok(calls().every(c=>c.env.AZ_INSTALLER==='MSI'));fs.writeFileSync(liveWrapper,original.replace('AZ_INSTALLER=MSI','AZ_INSTALLER=ZIP'));expect(run(),0,'READ_VERIFIED');assert.ok(calls().every(c=>c.env.AZ_INSTALLER==='ZIP'));fs.appendFileSync(liveWrapper,'\r\necho unexpected');expect(run(),3,'ACCESS_UNKNOWN');assert.equal(calls().length,0,'unknown cmd never executed');fs.writeFileSync(liveWrapper,original);}
  const split=run('split-unicode');assert.equal(calls().filter(c=>c.split_fixture).length,1,'split provider fixture reached');assert.deepEqual(calls().filter(c=>c.name).map(c=>c.args),azArgs);expect(split,0,'READ_VERIFIED');console.log('INFO: TEST-002 split_utf8_read_verified=true split_fixture_reached=true');
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
  const rawPrompt=fs.readFileSync(path.join(root,'.aai/SKILL_PR.prompt.md'),'utf8');function assertPrompt(raw){const prompt=raw.replace(/\r\n/g,'\n');const invocation=prompt.indexOf('node .aai/scripts/pr-preflight.mjs --input <preflight-input.json> --json');assert.ok(invocation>=0,'actual readiness invocation exists');assert.ok(invocation<prompt.indexOf('PROCESS\n'),'readiness in PRECONDITIONS');assert.match(prompt,/missing STATE.*readiness succeeds/s,'fresh STATE initialization follows readiness');assert.match(prompt,/release --pid/);assert.match(prompt,/Nonzero.*STOP/);assert.match(prompt,/remote_name is `origin` when origin exists, otherwise null/,'readiness uses ceremony origin');assert.match(prompt,/null only when origin is absent/,'none cannot bypass an existing origin');}
  for(const newline of ['\n','\r\n']){const fixture=path.join(tmp,'prompt-fixture.md');fs.writeFileSync(fixture,rawPrompt.replace(/\r?\n/g,newline));assertPrompt(fs.readFileSync(fixture,'utf8'));}
  const originInput={...input};git('remote','add','alternate','https://github.com/Org/Repo.git');
  input={schema_version:1,repo_root:repo,remote_name:'alternate',source_branch:originInput.source_branch,target_branch:'main',repository:'Org/Repo'};expect(run(),0,'READ_VERIFIED');assert.equal(calls().length,3,'alternate GitHub would succeed');
  input={schema_version:1,repo_root:repo,remote_name:null,source_branch:originInput.source_branch,target_branch:'main'};expect(run(),0,'CAPABILITY_NOT_APPLICABLE');assert.equal(calls().length,0,'null would bypass the existing origin');
  input=originInput;expect(run('extension'),3,'EXTENSION_MISSING');assert.equal(calls().length,2,'origin-bound ceremony refuses before writes despite valid alternate');console.log('INFO: TEST-006 alternate_read_verified=true null_bypasses_origin=true ceremony_origin_refused=true');
  fs.mkdirSync(path.join(repo,'docs/ai'),{recursive:true});fs.writeFileSync(path.join(repo,'docs/ai/STATE.yaml'),'sentinel state');git('update-ref','refs/aai/reservations/local',git('rev-parse','HEAD'));git('update-ref','refs/remotes/origin/aai-reservations',git('rev-parse','HEAD'));
  const snapshot=()=>JSON.stringify([fs.existsSync(path.join(repo,'docs/ai/STATE.yaml'))?fs.readFileSync(path.join(repo,'docs/ai/STATE.yaml'),'hex'):null,git('write-tree'),git('rev-parse','HEAD'),git('for-each-ref','--format=%(refname) %(objectname)','refs/aai','refs/remotes')]);const before=snapshot();expect(run('extension'),3,'EXTENSION_MISSING');assert.equal(calls().length,2);assert.equal(snapshot(),before,'refusal preserves state/index/head/reservations');expect(run(),0,'READ_VERIFIED');assert.equal(calls().length,3);
  const stateFile=path.join(repo,'docs/ai/STATE.yaml');fs.unlinkSync(stateFile);const absent=snapshot();
  function freshCeremony(mode){const observed=run(mode);if(observed.status===0){const repair=spawnSync(process.execPath,[path.join(root,'.aai/scripts/check-state.mjs'),'--repair',stateFile],{cwd:repo,encoding:'utf8'});assert.equal(repair.status,0,'successful readiness reaches real STATE repair');assert.match(repair.stdout,/CREATED:/);}return observed;}
  expect(freshCeremony('extension'),3,'EXTENSION_MISSING');assert.equal(fs.existsSync(stateFile),false,'refusal leaves missing STATE absent');assert.equal(snapshot(),absent);expect(freshCeremony('ok'),0,'READ_VERIFIED');assert.equal(fs.existsSync(stateFile),true);assert.equal(calls().length,3,'success path reached provider then STATE initialization');

 } else if(id==='007') {
  github();const delayed=run('ok',[],{FIX_DELAY_MS:'700'});expect(delayed,0,'READ_VERIFIED');assert.ok(delayed.ms>=4200,'real Git fixture crossed old whole-CLI bound');assert.ok(calls().length===3,'delayed success reached all provider probes');console.log('INFO: TEST-007 bounded_identity_delay_ms='+delayed.ms+' read_verified=true');
  github('enterprise.github.com');expect(run('ok',[],{GIT_TERMINAL_PROMPT:'1',GH_PROMPT_DISABLED:'0'}),0,'READ_VERIFIED');assert.ok(calls().every(c=>c.env.GIT_TERMINAL_PROMPT==='0'&&c.env.GH_PROMPT_DISABLED==='1'));assert.deepEqual(calls().map(c=>c.args),ghArgs);assert.ok(calls().every(c=>c.env.GH_HOST===host));expect(run('gh-auth'),3,'AUTH_FAILED');assert.equal(calls().length,2);expect(run('mismatch'),3,'PROVIDER_RESULT_INVALID');
  delete input.repository;azure('https://gitlab.com/Org/Repo.git');const r=run();expect(r,0,'CAPABILITY_NOT_APPLICABLE');assert.equal(calls().length,0);assert.match(r.json.remedy,/GENERIC MODE/);
  for(const suffix of ['?access_token=SYNTHETIC_QUERY_CREDENTIAL','#SYNTHETIC_FRAGMENT_CREDENTIAL']){azure('https://user:SYNTHETIC_USERINFO_CREDENTIAL@gitlab.com/Org/Repo.git'+suffix);const clean=run();expect(clean,0,'CAPABILITY_NOT_APPLICABLE');assert.equal(calls().length,0);assert.equal(clean.json.repository.remote,'https://gitlab.com/Org/Repo.git');assert.doesNotMatch(clean.stdout+clean.stderr,/SYNTHETIC_|access_token|user:/);}
  git('remote','remove','origin');input.remote_name=null;expect(run(),0,'CAPABILITY_NOT_APPLICABLE');assert.equal(calls().length,0);
 } else if(id==='008') {
  const profiles=fs.readFileSync(path.join(root,'.aai/system/PROFILES.yaml'),'utf8');const core=profiles.split(/^core:\s*$/m)[1].split(/^\S/m)[0];assert.match(core,/  - \.aai\/scripts\/pr-preflight\.mjs/,'new script core');
  const changed=path.join(tmp,'changed.txt');fs.writeFileSync(changed,'.aai/scripts/pr-preflight.mjs\n');const selected=spawnSync(process.execPath,[path.join(root,'.aai/scripts/select-suites.mjs'),'--files-from',changed],{cwd:root,encoding:'utf8'});assert.equal(selected.status,0);assert.match(selected.stdout,/aai-pr-preflight/,'suite selected for actual script');
  const ledger=fs.readFileSync(path.join(root,'tests/skills/lib/prompt-diet-ledger.sh'),'utf8');const entry=ledger.match(/JUSTIFIED_ADDITIONS\+=\( "(\d+) pr-capability-preflight /);assert.ok(entry,'measured ledger entry');// Immutable LF blob bdeb425c040ada918dd97e5b878b71e420bad83a:.aai/SKILL_PR.prompt.md measured36430 bytes. No historical object is required.
  const baselineBytes=36430,lf=fs.readFileSync(path.join(root,'.aai/SKILL_PR.prompt.md'),'utf8').replace(/\r\n/g,'\n');const measured=raw=>Buffer.byteLength(raw.replace(/\r\n/g,'\n'),'utf8');assert.equal(measured(lf),measured(lf.replace(/\n/g,'\r\n')),'LF/CRLF canonical accounting parity');assert.equal(Number(entry[1]),measured(lf)-baselineBytes,'actual normalized prompt growth');
  const diet=fs.readFileSync(path.join(root,'tests/skills/test-aai-prompt-diet.sh'),'utf8');assert.match(diet,new RegExp('local want_growth='+String(54252+Number(entry[1]))));
  function cloneGit(args,executable=realGit) {return execFileSync(executable,args,{stdio:['ignore','pipe','pipe'],env:{...process.env,AAI_GIT_WRITE:'1'}});}
  assert.throws(()=>cloneGit(['clone','--quiet',path.join(tmp,'nonexistent-repository'),path.join(tmp,'failed-clone')]),e=>e.status!==0&&e.stderr.length>0,'genuine clone failures remain visible');
  // A portable successful Git boundary emits the same benign note that PS5.1
  // promoted to RemoteException in CI. The inner process still performs a real clone.
  const noteCheckout=path.join(tmp,'note-shallow'),shortCheckout=path.join(scratch,'s-'+path.basename(tmp).slice(-6));
  const noteScript=`const {spawnSync}=require('child_process'),fs=require('fs'),path=require('path');
const git=process.argv[1],source=process.argv[2],deep=process.argv[3],short=process.argv[4],root=process.argv[5];
function run(args,cwd,timeout=5000){return spawnSync(git,args,{cwd,encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout,maxBuffer:65536});}
function result(r){return {status:r.status,signal:r.signal,error:r.error?{code:r.error.code,message:r.error.message}:null,stdout:r.stdout||'',stderr:r.stderr||''};}
const config=run(['config','--show-origin','--get','core.longpaths'],root),head=run(['rev-parse','HEAD'],root);
const tree=spawnSync(git,['ls-tree','-r','--name-only','HEAD'],{cwd:root,encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:5000,maxBuffer:1048576});
const longest=(tree.stdout||'').split(/\\r?\\n/).reduce((a,b)=>b.length>a.length?b:a,'');
function clone(destination){const r=run(['clone','--quiet','--depth','1',source,destination],undefined,30000);return {destination,max_checkout_path_chars:path.join(destination,longest).length,...result(r),head:r.status===0?result(run(['rev-parse','HEAD'],destination)):null,shallow:r.status===0?result(run(['rev-parse','--is-shallow-repository'],destination)):null};}
let first;try{first=clone(deep);const control=clone(short);console.log('INFO: TEST008_CLONE '+JSON.stringify({clone_timeout_ms:30000,output_cap_bytes:65536,source_head:result(head),core_longpaths:result(config),tree_status:tree.status,longest_relative_path:longest,longest_relative_chars:longest.length,deep:first,short:control}));}finally{fs.rmSync(short,{recursive:true,force:true});}
if(first.status!==0){process.stderr.write(first.stderr);process.exit(first.status||1);}process.stderr.write('Note: switching to detached fixture.\\n');`;
  const noteArgs=['-e',noteScript,realGit,require('url').pathToFileURL(root).href,noteCheckout,shortCheckout,root];
  const outer="const {execFileSync}=require('child_process');const realGit="+JSON.stringify(realGit)+';try{const out=('+cloneGit.toString()+')('+JSON.stringify(noteArgs)+','+JSON.stringify(process.execPath)+');process.stdout.write(out);}catch(e){if(e.stdout)process.stdout.write(e.stdout);console.log("INFO: TEST008_CAPTURE "+JSON.stringify({status:e.status,signal:e.signal,error:{code:e.code||null,message:String(e.message).slice(0,65536)},stderr:String(e.stderr||"").slice(0,65536)}));process.exit(e.status||1);}';
  const noteProbe=spawnSync(process.execPath,['-e',outer],{encoding:'utf8',timeout:75000,maxBuffer:262144});
  process.stdout.write(noteProbe.stdout||'');
  assert.equal(noteProbe.status,0,'benign-note clone succeeds: '+noteProbe.stderr);assert.equal(noteProbe.stderr,'','successful clone stderr is captured at boundary');assert.equal(execFileSync(realGit,['rev-parse','--is-shallow-repository'],{cwd:noteCheckout,encoding:'utf8'}).trim(),'true');console.log('INFO: TEST-008 benign_note_captured=true genuine_clone_failure_throws=true note_control_shallow=true');
  if(!process.env.AAI_PREFLIGHT_SHALLOW_PROOF){const shallow=path.join(tmp,'shallow');cloneGit(['clone','--quiet','--depth','1',require('url').pathToFileURL(root).href,shallow]);assert.equal(execFileSync(realGit,['rev-parse','--is-shallow-repository'],{cwd:shallow,encoding:'utf8'}).trim(),'true');assert.notEqual(spawnSync(realGit,['cat-file','-e','bdeb425c040ada918dd97e5b878b71e420bad83a'],{cwd:shallow,stdio:'ignore'}).status,0,'historical baseline unavailable');for(const rel of ['.aai/SKILL_PR.prompt.md','tests/skills/test-aai-pr-preflight.sh','tests/skills/lib/prompt-diet-ledger.sh','tests/skills/test-aai-prompt-diet.sh'])fs.copyFileSync(path.join(root,rel),path.join(shallow,rel));const src=fs.readFileSync(path.join(root,'tests/skills/test-aai-pr-preflight.sh'),'utf8');const matrix=src.match(/AAI_PREFLIGHT_MATRIX'\r?\n([\s\S]*?)\r?\nAAI_PREFLIGHT_MATRIX/)[1],matrixFile=path.join(tmp,'shallow-matrix.cjs');fs.writeFileSync(matrixFile,matrix);const proof=spawnSync(process.execPath,[matrixFile,shallow,'008'],{encoding:'utf8',timeout:10000,env:{...process.env,AAI_PREFLIGHT_SHALLOW_PROOF:'1'}});assert.equal(proof.status,0,'shallow TEST008: '+proof.stdout+proof.stderr);assert.match(proof.stdout,/PASS: TEST-008/);console.log('INFO: TEST-008 shallow=true baseline_object_absent=true LF_CRLF_bytes_equal=true');}
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
