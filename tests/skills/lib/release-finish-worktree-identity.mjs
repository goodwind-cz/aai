// Real-git probe for release-finish.mjs worktree identity (CR-3). Runs on any
// OS; on windows-latest it is the only place the Git-for-Windows path form
// (forward slashes, possible 8.3 names) meets Node's native realpath.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {pathToFileURL,fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const {worktreeBlock}=await import(pathToFileURL(path.resolve(here,'../../../.aai/scripts/release-finish.mjs')).href);
const git=(cwd,...a)=>{const r=spawnSync('git',a,{cwd,encoding:'utf8'});assert.equal(r.status,0,`git ${a.join(' ')}: ${r.stderr}`);return r.stdout.trim();};
const repo=fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(),'aai-wt-id-repo.')));
const wt=fs.realpathSync.native(fs.mkdtempSync(path.join(os.tmpdir(),'aai-release-wt.')));
try{
  git(repo,'init','-q','-b','main');git(repo,'config','user.name','t');git(repo,'config','user.email','t@test.invalid');
  fs.writeFileSync(path.join(repo,'a'),'a');git(repo,'add','a');git(repo,'commit','-qm','seed');
  git(repo,'worktree','add','-q','-b','chore/release-v1',wt,'HEAD');
  const list=git(repo,'worktree','list','--porcelain');
  const blk=worktreeBlock(list,wt);
  assert.ok(blk,`registered worktree not recognised: native=${wt}\n${list}`);
  assert.ok(blk.split('\n').includes('branch refs/heads/chore/release-v1'));
  git(repo,'worktree','remove',wt);
  assert.equal(worktreeBlock(git(repo,'worktree','list','--porcelain'),wt),undefined,'removed worktree must not be found');
  console.log('PASS: release-finish worktree identity on '+process.platform);
}finally{fs.rmSync(repo,{recursive:true,force:true});fs.rmSync(wt,{recursive:true,force:true});}
