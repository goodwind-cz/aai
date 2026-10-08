const fs=require('fs'),path=require('path'),assert=require('assert/strict'),{spawnSync}=require('child_process');
const root=process.argv[2],base='/private/tmp/aai-pr434-scp-review-scratch/independent';fs.mkdirSync(base,{recursive:true});
const repo=path.join(base,'repo'),bin=path.join(base,'bin');for(const p of [repo,bin])fs.mkdirSync(p,{recursive:true});
const env={...process.env,AAI_ROLE:'subagent',AAI_GIT_WRITE:'1',GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'/dev/null',GIT_TERMINAL_PROMPT:'0'};
function git(args){const r=spawnSync('git',args,{cwd:repo,env,encoding:'utf8',timeout:5000});assert.equal(r.status,0,JSON.stringify({args,status:r.status,stderr:r.stderr}));return r.stdout.trim();}
git(['init','-q','-b','change/probe']);git(['config','user.name','Fixture']);git(['config','user.email','fixture@example.invalid']);fs.writeFileSync(path.join(repo,'f'),'x');git(['add','f']);git(['commit','-qm','fixture']);
const calls=path.join(base,'calls.jsonl');
fs.writeFileSync(path.join(bin,'gh'),`#!${process.execPath}\nconst fs=require('fs'),a=process.argv.slice(2),v=JSON.stringify(a);fs.appendFileSync(${JSON.stringify(calls)},v+'\\n');if(v==='["--version"]')console.log('fixture');else if(v==='["auth","status","--hostname","github.com"]')console.log('ok');else if(v==='["repo","view","Org/Repo","--json","nameWithOwner,url"]')console.log(JSON.stringify({nameWithOwner:process.env.FIX_CANONICAL,url:'https://github.com/'+process.env.FIX_CANONICAL}));else process.exitCode=91;`.replace('\\n','\n'),{mode:0o755});
const rows=[];
for(const [name,remote,repository,canonical] of [['ordinary','https://github.com/Org/Repo.git','Org/Repo','Org/Repo'],['case','https://github.com/Org/Repo.git','Org/Repo','org/repo'],['malformed','https://github.com:bad/Org/Repo.git',undefined,'Org/Repo'],['generic','https://gitlab.com/Org/Repo.git',undefined,'Org/Repo']]){
 if(rows.length)git(['remote','remove','origin']);git(['remote','add','origin',remote]);fs.writeFileSync(calls,'');
 const input={schema_version:1,repo_root:repo,remote_name:'origin',source_branch:'change/probe',target_branch:'main',...(repository?{repository}:{})};const inputPath=path.join(base,'input.json');fs.writeFileSync(inputPath,JSON.stringify(input));
 const r=spawnSync(process.execPath,[path.join(root,'.aai/scripts/pr-preflight.mjs'),'--input',inputPath,'--json'],{cwd:repo,env:{...env,PATH:bin+path.delimiter+env.PATH,FIX_CANONICAL:canonical},encoding:'utf8',timeout:15000});
 let transport=null;if(name==='malformed'){const t=spawnSync('git',['-c','http.proxy=http://127.0.0.1:1','ls-remote','origin'],{cwd:repo,env,encoding:'utf8',timeout:5000});transport={status:t.status,stdout:t.stdout,stderr:t.stderr,error:t.error?.code};}
 const row={name,remote,fetch:git(['remote','get-url','--all','origin']),push:git(['remote','get-url','--push','--all','origin']),status:r.status,stdout:r.stdout,stderr:r.stderr,calls:fs.readFileSync(calls,'utf8'),transport};rows.push(row);console.log(JSON.stringify(row));
}
fs.writeFileSync('/private/tmp/aai-pr434-scp-review-scratch/probe-results.json',JSON.stringify(rows,null,2)+'\n');
assert.equal(rows[0].status,0,'exact identity positive');assert.equal(rows[3].status,0,'lawful generic positive');assert.equal(rows[2].transport.status,128);assert.match(rows[2].transport.stderr,/Port number|port/);
const errors=[];try{assert.equal(rows[2].status,2,'malformed scheme must refuse')}catch(e){errors.push(e.message)}try{assert.equal(rows[1].status,0,'case-equivalent GitHub repository must succeed')}catch(e){errors.push(e.message)}for(const e of errors)console.error('ASSERTION: '+e);assert.equal(errors.length,0,'independent regressions');
