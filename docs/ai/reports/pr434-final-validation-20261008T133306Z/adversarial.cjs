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
 console.log(JSON.stringify({nameWithOwner:process.env.FIX_NAME|| (mode==='mismatch'?'Other/Repo':'Org/Repo'),url:process.env.FIX_URL||'https://'+process.env.FIX_HOST+'/Org/Repo'}));
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
 let json; try{json=JSON.parse(r.stdout)}catch{assert.fail('one parseable JSON result required: '+JSON.stringify({status:r.status,signal:r.signal,stderr:r.stderr,stdout:String(r.stdout).slice(0,200),error:r.error?.message}));}
 return {...r,json,ms:Date.now()-start};
}
function expect(r,status,code) {assert.equal(r.status,status,'exit '+code);assert.equal(r.json.code,code);assert.equal(r.json.create_permission,'unknown');assert.equal(r.json.schema_version,1);if(status){assert.ok(r.json.operation);assert.ok(r.json.remedy);assert.ok(r.stderr.trim());}}
function refusal(change) {const saved={...input};Object.assign(input,change);const r=run();expect(r,2,'IDENTITY_INVALID');assert.equal(calls().length,0,'identity refusal precedes clients');input=saved;}

try {
 const results=[];
 for(const endpoint of ['https://gitlab.com:bad/a/b','https://gitlab.com:65536/a/b','ssh://git@github.com/Org/%2E%2E/Repo.git','ssh://git%3Apass@github.com/Org/Repo.git']) {
  github();azure(endpoint);if(endpoint.includes('gitlab'))delete input.repository;
  const r=run();expect(r,2,'IDENTITY_INVALID');assert.equal(calls().length,0);results.push({endpoint,status:r.status,calls:0});
 }
 for(const h of ['github.com','enterprise.github.com']) {
  github(h);input.repository='oRG/rEPO';const r=run('ok',[],{FIX_NAME:'org/REPO',FIX_URL:'https://'+h+'/ORG/repo'});expect(r,0,'READ_VERIFIED');assert.equal(calls().length,3);assert.ok(calls().every(c=>c.env.GH_HOST===h));results.push({host:h,combined_ascii:true,calls:3});
 }
 github();input.repository='Org/RepK';expect(run(),2,'IDENTITY_INVALID');assert.equal(calls().length,0);results.push({unicode_distinct:true});
 github();input.repository='org/repo';git('config','remote.origin.pushurl','https://github.com/org/repo.git');const mismatch=run();expect(mismatch,2,'IDENTITY_INVALID');assert.equal(mismatch.json.operation,'git.push-destination');assert.equal(calls().length,0);results.push({literal_endpoint_refusal:true});
 github();delete input.repository;azure('https://u:SYNTHETIC@gitlab.com:8443/a/b?token=SYNTHETIC#SYNTHETIC');const generic=run();expect(generic,0,'CAPABILITY_NOT_APPLICABLE');assert.equal(generic.json.repository.remote,'https://gitlab.com:8443/a/b');assert.equal(calls().length,0);results.push({generic_numeric_port_redacted:true});
 input.remote_name=null;expect(run(),0,'CAPABILITY_NOT_APPLICABLE');assert.equal(calls().length,0);results.push({explicit_null:true});
 input={schema_version:1,repo_root:repo,remote_name:'origin',source_branch:'change/pr-capability-preflight',target_branch:'main',organization_url:'https://dev.azure.com/Org',project:'Project 雪',repository:'Repo Name'};azure();expect(run(),0,'READ_VERIFIED');assert.equal(calls().length,3);results.push({azure_unchanged:true,calls:3});
 console.log(JSON.stringify(results,null,2));
} finally {fs.rmSync(tmp,{recursive:true,force:true});}
