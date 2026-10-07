const fs=require('fs'),path=require('path'),assert=require('assert/strict');
const {execFileSync,spawnSync}=require('child_process');
const base='/private/tmp/aai-pr434-validation-pushurl-scratch/edge-fixtures';
fs.mkdirSync(base,{recursive:true});const dir=fs.mkdtempSync(path.join(base,'repo-')),bin=path.join(dir,'bin');fs.mkdirSync(bin);
const gitRaw=(...args)=>execFileSync('git',args,{cwd:dir,encoding:'utf8',stdio:['ignore','pipe','pipe'],env:{...process.env,AAI_GIT_WRITE:'1'}});
const git=(...args)=>gitRaw(...args).trim();
git('init','-q');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid');fs.writeFileSync(path.join(dir,'file'),'base');git('add','file');git('commit','-qm','base');git('branch','-M','change/pr-capability-preflight');
const url='https://github.com/Org/Repo.git';git('remote','add','origin',url);
const log=path.join(dir,'calls'),stub=path.join(dir,'gh.cjs');
fs.writeFileSync(stub,`const fs=require('fs');const args=process.argv.slice(2);fs.appendFileSync(${JSON.stringify(log)},JSON.stringify(args)+'\\n');if(JSON.stringify(args)===JSON.stringify(['--version']))console.log('gh fixture');else if(JSON.stringify(args)===JSON.stringify(['auth','status','--hostname','github.com']))console.log('authenticated');else if(JSON.stringify(args)===JSON.stringify(['repo','view','Org/Repo','--json','nameWithOwner,url']))console.log(JSON.stringify({nameWithOwner:'Org/Repo',url:'https://github.com/Org/Repo'}));else process.exit(91);`);
fs.writeFileSync(path.join(bin,'gh'),'#!/bin/sh\nexec "'+process.execPath+'" "'+stub+'" "$@"\n',{mode:0o755});
const input={schema_version:1,repo_root:dir,remote_name:'origin',source_branch:'change/pr-capability-preflight',target_branch:'main',repository:'Org/Repo'},file=path.join(dir,'input.json');fs.writeFileSync(file,JSON.stringify(input));
const cli='/private/tmp/aai-pr-capability-preflight/.aai/scripts/pr-preflight.mjs';let escapes=0;
for(const [name,destinations,expected] of [['ordinary',[url],0],['divergent',['https://github.com/Other/Repo.git'],2],['duplicate',[url,url],2],['leading-space',[' '+url],2],['trailing-space',[url+' '],2],['empty-last',[url,''],0],['empty-first',['',url],0]]){
 try{git('config','--unset-all','remote.origin.pushurl')}catch{}
 for(const value of destinations)git('config','--add','remote.origin.pushurl',value);
 fs.writeFileSync(log,'');const result=spawnSync(process.execPath,[cli,'--input',file,'--json'],{encoding:'utf8',env:{...process.env,PATH:bin+path.delimiter+process.env.PATH},timeout:15000});assert.equal(result.error,undefined);const json=JSON.parse(result.stdout);const rawFetch=gitRaw('remote','get-url','--all','--','origin'),rawPush=gitRaw('remote','get-url','--push','--all','--','origin');
 console.log(JSON.stringify({observed_at_utc:new Date().toISOString(),scenario:name,configured_push:destinations,raw_fetch:rawFetch,raw_push:rawPush,expected_exit:expected,observed_exit:result.status,result:json,provider_calls:fs.readFileSync(log,'utf8'),no_push_executed:true}));
 if(result.status!==expected)escapes++;
}
fs.rmSync(dir,{recursive:true,force:true});console.log('DESTINATION_EDGE_ESCAPES='+escapes);process.exitCode=escapes?1:0;
