import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const root='/private/tmp/aai-pr434-ssh443-research';
const shipping='/private/tmp/aai-pr-capability-preflight';
const scratch=path.join(root,'fixture');
fs.mkdirSync(scratch,{recursive:true});
const env={...process.env,AAI_ROLE:'subagent',GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'/dev/null',GIT_TERMINAL_PROMPT:'0'};
function run(bin,args,extra={}) {const r=spawnSync(bin,args,{env,encoding:'utf8',...extra});return {status:r.status,stdout:r.stdout,stderr:r.stderr};}
function git(args){const r=run('git',['-C',scratch,...args]);if(r.status!==0)throw Error(JSON.stringify(r));return r.stdout;}
git(['init','-b','source']);
git(['config','user.name','Fixture']);git(['config','user.email','fixture@example.invalid']);
git(['-c','core.hooksPath=/dev/null','commit','--allow-empty','-m','fixture']);
const bin=path.join(root,'bin');fs.mkdirSync(bin,{recursive:true});
const log=path.join(root,'provider-calls.jsonl');
fs.writeFileSync(path.join(bin,'gh'),`#!/usr/bin/env node
const fs=require('node:fs');const args=process.argv.slice(2);
fs.appendFileSync(process.env.PROVIDER_LOG,JSON.stringify({args,GH_HOST:process.env.GH_HOST})+'\\n');
if(args.join(' ')==='--version') console.log('gh fixture');
else if(args.join(' ')==='auth status --hostname github.com') console.log('authenticated fixture');
else if(args.join(' ')==='repo view OWNER/REPO --json nameWithOwner,url' && process.env.GH_HOST==='github.com') console.log(JSON.stringify({nameWithOwner:'OWNER/REPO',url:'https://github.com/OWNER/REPO'}));
else {console.error('fixture rejects unexpected host or argv');process.exitCode=9;}
`);fs.chmodSync(path.join(bin,'gh'),0o755);
const cases=[
 ['https','https://github.com/OWNER/REPO.git','OWNER/REPO'],
 ['scp','git@github.com:OWNER/REPO.git','OWNER/REPO'],
 ['ssh-no-port','ssh://git@github.com/OWNER/REPO.git','OWNER/REPO'],
 ['documented-alias','ssh://git@ssh.github.com:443/OWNER/REPO.git','OWNER/REPO'],
 ['documented-alias-mismatch','ssh://git@ssh.github.com:443/OWNER/REPO.git','OWNER/OTHER'],
 ['alias-other-port','ssh://git@ssh.github.com:444/OWNER/REPO.git','OWNER/REPO'],
 ['github-ssh443','ssh://git@github.com:443/OWNER/REPO.git','OWNER/REPO'],
 ['https-default443','https://github.com:443/OWNER/REPO.git','OWNER/REPO'],
 ['https-other-port','https://github.com:444/OWNER/REPO.git','OWNER/REPO'],
 ['alias-no-port','ssh://git@ssh.github.com/OWNER/REPO.git','OWNER/REPO'],
 ['ordinary-mismatch','git@github.com:OWNER/REPO.git','OWNER/OTHER'],
 ['github-lookalike','ssh://git@ssh.github.com.evil.invalid:443/OWNER/REPO.git','OWNER/REPO'],
];
const observations=[];
for(const [name,url,repository] of cases){
 git(['config','remote.origin.url',url]);fs.writeFileSync(log,'');
 const input={schema_version:1,repo_root:scratch,remote_name:'origin',source_branch:'source',target_branch:'main',repository};
 const inputPath=path.join(root,'input.json');fs.writeFileSync(inputPath,JSON.stringify(input));
 const fetch=git(['remote','get-url','--all','--','origin']);const push=git(['remote','get-url','--push','--all','--','origin']);
 const platform=run(process.execPath,[path.join(shipping,'.aai/scripts/pr-platform.mjs'),'--remote-url',url,'--pr-config',path.join(root,'absent.yaml'),'--json']);
 const preflight=run(process.execPath,[path.join(shipping,'.aai/scripts/pr-preflight.mjs'),'--input',inputPath,'--json','--timeout-ms','1000'],{env:{...env,PATH:bin+path.delimiter+env.PATH,PROVIDER_LOG:log}});
 const calls=fs.readFileSync(log,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse);
 observations.push({name,url,repository,effective_fetch:fetch,effective_push:push,platform,preflight,calls});
 console.log(JSON.stringify({name,status:preflight.status,result:JSON.parse(preflight.stdout),calls}));
}
fs.writeFileSync(path.join(root,'observations.json'),JSON.stringify({node:process.version,git:run('git',['--version']).stdout,shipping_head:run('git',['-C',shipping,'rev-parse','HEAD']).stdout.trim(),observations},null,2)+'\n');
// Preserve only text artifacts; remove disposable Git object/index internals.
fs.rmSync(scratch,{recursive:true});
for(const file of ['.aai/scripts/pr-preflight.mjs','.aai/scripts/pr-platform.mjs','docs/specs/SPEC-0210-spec-pr-capability-preflight.md','docs/issues/CHANGE-0204-pr-capability-preflight.md'])console.log('source-sha256 '+createHash('sha256').update(fs.readFileSync(path.join(shipping,file))).digest('hex')+' '+file);
