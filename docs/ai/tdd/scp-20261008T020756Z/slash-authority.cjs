const fs=require('fs'),path=require('path'),assert=require('assert/strict'),{spawnSync}=require('child_process');
const root=process.argv[2],base=fs.mkdtempSync('/private/tmp/aai-pr434-remediation-scratch/password-');fs.mkdirSync(base,{recursive:true});
const repo=path.join(base,'checkout'),bin=path.join(base,'bin'),server=path.join(base,'server');for(const p of [repo,bin,server])fs.mkdirSync(p,{recursive:true});
const env={...process.env,AAI_ROLE:'subagent',GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'/dev/null',AAI_GIT_WRITE:'1'};
function git(args,cwd=repo){const r=spawnSync('git',args,{cwd,env,encoding:'utf8',timeout:5000});assert.equal(r.status,0,JSON.stringify({args,...r}));return r.stdout.trim();}
git(['init','-q','-b','change/pr-capability-preflight']);git(['config','user.name','Fixture']);git(['config','user.email','fixture@example.invalid']);fs.writeFileSync(path.join(repo,'f'),'x');git(['add','f']);git(['commit','-qm','fixture']);
fs.mkdirSync(path.join(server,'Org'),{recursive:true});git(['clone','--bare','--quiet',repo,path.join(server,'Org','Repo.git')]);
const calls=path.join(base,'calls.jsonl'),sshlog=path.join(base,'ssh.jsonl');
fs.writeFileSync(path.join(bin,'gh'),`#!${process.execPath}\nconst fs=require('fs'),a=process.argv.slice(2),v=JSON.stringify(a);fs.appendFileSync(${JSON.stringify(calls)},v+'\\n');if(v==='["--version"]')console.log('gh fixture');else if(v==='["auth","status","--hostname","github.com"]')console.log('ok');else if(v==='["repo","view","Org/Repo","--json","nameWithOwner,url"]')console.log(JSON.stringify({nameWithOwner:'Org/Repo',url:'https://github.com/Org/Repo'}));else process.exitCode=91;`,{mode:0o755});
fs.writeFileSync(path.join(bin,'ssh'),`#!${process.execPath}\nconst fs=require('fs'),path=require('path'),{spawnSync}=require('child_process');const a=process.argv.slice(2);fs.appendFileSync(${JSON.stringify(sshlog)},JSON.stringify(a)+'\\n');const m=a[a.length-1].match(/^git-upload-pack '(.*)'$/);if(!m)process.exit(92);const p=path.join(${JSON.stringify(server)},m[1].replace(/^\\//,''));const r=spawnSync('git',['upload-pack',p],{stdio:'inherit',env:process.env});process.exitCode=r.status===null?93:r.status;`,{mode:0o755});
const results=[];
for(const remote of ['ssh://%67it@ssh.github.com:443/Org/Repo.git','ssh://git%2Fuser@ssh.github.com:443/Org/Repo.git']){
 try{git(['remote','remove','origin']);}catch{}git(['remote','add','origin',remote]);
 fs.writeFileSync(calls,'');fs.writeFileSync(sshlog,'');
 const input={schema_version:1,repo_root:repo,remote_name:'origin',source_branch:'change/pr-capability-preflight',target_branch:'main',repository:'Org/Repo'};
 const inputPath=path.join(base,'input.json');fs.writeFileSync(inputPath,JSON.stringify(input));
 const r=spawnSync(process.execPath,[path.join(root,'.aai/scripts/pr-preflight.mjs'),'--input',inputPath,'--json'],{cwd:repo,env:{...env,PATH:bin+path.delimiter+process.env.PATH},encoding:'utf8',timeout:10000});
 const transport=spawnSync('git',['ls-remote','origin'],{cwd:repo,env:{...env,GIT_SSH:path.join(bin,'ssh'),GIT_SSH_VARIANT:'ssh',GIT_TERMINAL_PROMPT:'0'},encoding:'utf8',timeout:5000});
 const row={remote,effective_fetch:git(['remote','get-url','--all','origin']),effective_push:git(['remote','get-url','--push','--all','origin']),preflight_status:r.status,preflight:JSON.parse(r.stdout),provider_calls:fs.readFileSync(calls,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse),transport_status:transport.status,transport_stdout:transport.stdout,transport_stderr:transport.stderr,ssh_argv:fs.readFileSync(sshlog,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse)};results.push(row);console.log(JSON.stringify(row));
}
fs.writeFileSync('/private/tmp/aai-pr434-remediation-scratch/password-results.json',JSON.stringify(results,null,2)+'\n');
assert.equal(results[0].preflight_status,0);assert.equal(results[0].provider_calls.length,3);assert.ok(results[0].ssh_argv[0].includes('-p'));assert.ok(results[0].ssh_argv[0].includes('git@ssh.github.com'));
assert.notEqual(results[1].transport_status,0,'encoded slash moves actual Git authority/path split');
assert.equal(results[1].preflight_status,2,'encoded userinfo slash must refuse mismatched transport identity');assert.equal(results[1].provider_calls.length,0);
