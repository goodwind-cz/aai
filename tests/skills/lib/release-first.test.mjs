import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../..');
const cli=path.join(root,'.aai/scripts/release-dry-run.mjs');
const changelog='CHANGE'+'LOG.md';
const note='# Changes\n\n## [unreleased] — Fixture\n\nA real note.\n\n## [1.0] — History\n\nOld note.\n';
function run(exe,args,cwd,env= {
}) {
  const childEnv= {
    ...process.env,AAI_GIT_WRITE:'1',...env
  };
  delete childEnv.NODE_TEST_CONTEXT;
  return spawnSync(exe,args, {
    cwd,encoding:'utf8',env:childEnv,timeout:120000,maxBuffer:8*1024*1024
  });
}
function git(dir,...args) {
  const r=run('git',args,dir);
  assert.equal(r.status,0,r.stderr);
  return r.stdout;
}
function put(dir,file,text) {
  fs.mkdirSync(path.dirname(path.join(dir,file)), {
    recursive:true
  });
  fs.writeFileSync(path.join(dir,file),text);
}
function fixture(t,files= {
}) {
  const dir=fs.mkdtempSync(path.join(os.tmpdir(),'aai-release-first-'));
  t.after(()=>fs.rmSync(dir, {
    recursive:true,force:true
  }));
  git(dir,'init','-b','main');
  git(dir,'config','user.email','fixture@example.invalid');
  git(dir,'config','user.name','Fixture');
  put(dir,changelog,note);
  // Use the real isolation runner, including its mandatory libraries.
  for(const f of ['tests/skills/test-framework.sh','.aai/scripts/lib/repo-tripwire.sh','.aai/scripts/lib/append-lock.sh']) {
    put(dir,f,fs.readFileSync(path.join(root,f),'utf8'));
  }
  for(const [f,s] of Object.entries(files))put(dir,f,s); git(dir,'add','.'); git(dir,'commit','-m','fixture');
  return dir;
}
function dry(dir,args=[],env= {
}) {
  const before=fingerprint(dir);
  const r=run(process.execPath,[cli,'--root',dir,...args],root,env);
  assert.equal(fingerprint(dir),before,'dry-run preserves source files, index and refs');
  return {
    ...r,text:r.stdout+'\n'+r.stderr
  };
}
const nodeReader=(dual=false)=>`import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';test('first',()=>assert.ok(fs.readFileSync('${changelog}','utf8').includes('## [${dual?'v2099.01.01':'unreleased'}] — Fixture')));test('last',()=>assert.ok(true));`;
function fingerprint(dir) {
  return JSON.stringify({
    files:git(dir,'ls-files','-z').split('\0').filter(Boolean).map(f=>[f,fs.readFileSync(path.join(dir,f)).toString('base64')]),index:fs.readFileSync(path.join(dir,'.git/index')).toString('base64'),refs:git(dir,'show-ref'),head:git(dir,'rev-parse','HEAD')
  });
}
test('TEST-001 discovers complete Node shell and Pester files, owns helpers or refuses',t=> {
  const dir=fixture(t, {
    'tests/new.test.mjs':nodeReader(),'tests/new.Tests.ps1':`Describe 'new' { It 'reads' { Get-Content '${changelog}' | Should -Not -BeNullOrEmpty } }`,'tests/test-new.sh':`#!/bin/bash\n# ${changelog}\n. tests/lib/helper.sh\n`,'tests/lib/helper.sh':`# ${changelog}\ntrue\n`
  });
  let r=dry(dir,['--list']);
  assert.equal(r.status,0,r.text);
  for(const f of ['tests/new.test.mjs','tests/new.Tests.ps1','tests/test-new.sh'])assert.ok(r.text.includes(f),r.text); assert.ok(r.text.includes('tests/lib/helper.sh'),r.text); put(dir,'tests/lib/orphan.mjs',`// ${changelog}\n`);
  git(dir,'add','.');
  r=dry(dir,['--list']);
  assert.notEqual(r.status,0,r.text);
  assert.match(r.text,/unowned.*orphan.mjs/i);
});
test('TEST-001 literal helper identities reject same-basename collisions',t=> {
  const cases=[
    {helper:'helper.mjs',owner:'owner.test.mjs',edge:"import {x} from './helper.mjs';",payload:`export const x='${changelog}';console.log('HELPER_EXECUTED');`},
    {helper:'helper.sh',owner:'test-owner.sh',edge:'source tests/used/helper.sh',payload:`# ${changelog}\ntrue`},
    {helper:'helper.ps1',owner:'owner.Tests.ps1',edge:'. "$PSScriptRoot/helper.ps1"',payload:`# ${changelog}\n$x=1`}
  ];
  for(const c of cases) {
    const dir=fixture(t,{
      ['tests/orphan/'+c.helper]:c.payload,
      ['tests/used/'+c.helper]:'',
      ['tests/used/'+c.owner]:c.edge+'\n'
    });
    const collision=dry(dir,['--list']);
    assert.notEqual(collision.status,0,'unrelated same-basename import must not own '+c.helper+'\n'+collision.text);
    assert.match(collision.text,/unowned reader helper: tests\/orphan\//);
    put(dir,'tests/used/'+c.helper,c.payload);
    git(dir,'rm','tests/orphan/'+c.helper);
    const owned=dry(dir,['--list']);
    assert.equal(owned.status,0,owned.text);
    assert.ok(owned.text.includes('OWNER tests/used/'+c.helper+' -> tests/used/'+c.owner),owned.text);
    if(c.helper==='helper.mjs') {
      const report=path.join(dir,'ownership-report.json');
      const executed=dry(dir,['--report',report]);
      assert.equal(executed.status,0,executed.text);
      const data=JSON.parse(fs.readFileSync(report));
      assert.ok(data.results[0].output.includes('HELPER_EXECUTED'),'positive control executes the owned helper');
    }
  }
});
test('TEST-002 executes complete Node reader and production rolled/ordinary differential',t=> {
  const dir=fixture(t, {
    'tests/new.test.mjs':nodeReader()
  });
  const r=dry(dir);
  assert.notEqual(r.status,0,r.text);
  assert.match(r.text,/tests\/new.test.mjs.*rollup-only/);
  assert.match(r.text,/ordinary.*PASS/);
  assert.match(r.text,/rolled.*FAIL/);
  put(dir,'tests/new.test.mjs',nodeReader(true).replace("includes('## [v2099.01.01] — Fixture')","match(/## \\[(?:unreleased|v2099.01.01)\\] — Fixture/ )"));
  const good=dry(dir);
  assert.equal(good.status,0,good.text);
});
test('TEST-003 shell nested isolation observes rolled committed snapshot',t=> {
  const dir=fixture(t, {
    'tests/skills/test-aai-planted.sh':`#!/bin/bash\n# ${changelog}\ngrep -q '^## \\[unreleased\\] — Fixture' ${changelog}\n`
  });
  const r=dry(dir);
  assert.notEqual(r.status,0,r.text);
  assert.match(r.text,/test-aai-planted.sh.*rollup-only/);
});
test('TEST-004 executes actual Pester and propagates failure',t=> {
  const dir=fixture(t, {
    'tests/new.Tests.ps1':`Describe 'rollup' { It 'reads actual content' { (Get-Content '${changelog}' -Raw).Contains('## [unreleased] — Fixture') | Should -BeTrue } }`
  });
  const r=dry(dir);
  assert.notEqual(r.status,0,r.text);
  assert.match(r.text,/new.Tests.ps1.*rollup-only/);
  assert.match(r.text,/ordinary.*PASS/);
});
test('TEST-005 source preservation failure timeout missing tooling baseline and empty entries',t=> {
  const dir=fixture(t, {
    'tests/new.test.mjs':nodeReader()
  });
  put(dir,changelog,note+'\nDirty source bytes\n');
  git(dir,'add',changelog);
  const before=fingerprint(dir);
  let r=dry(dir);
  assert.notEqual(r.status,0,r.text);
  assert.equal(fingerprint(dir),before);
  put(dir,'tests/new.test.mjs',`// ${changelog}\nsetTimeout(()=>{},10000);`);
  r=dry(dir,['--timeout-seconds','0.1']);
  assert.notEqual(r.status,0,r.text);
  assert.match(r.text,/timeout/);
  put(dir,'tests/new.test.mjs',`// ${changelog}\nthrow Error('baseline fixture');`);
  r=dry(dir);
  assert.notEqual(r.status,0,r.text);
  assert.match(r.text,/baseline-failure/);
  put(dir,'tests/new.test.mjs',`// ${changelog}\n`);
  put(dir,'tests/new.Tests.ps1',`# ${changelog}\n`);
  git(dir,'add','.');
  r=dry(dir,[], {
    AAI_RELEASE_DRY_PWSH:'/nonexistent/pwsh'
  });
  assert.notEqual(r.status,0,r.text);
  assert.match(r.text,/missing-tool/);
  fs.unlinkSync(path.join(dir,'tests/new.Tests.ps1'));
  git(dir,'rm','--cached','tests/new.Tests.ps1');
  put(dir,changelog,'# Empty\n\n## [unreleased]\n');
  r=dry(dir,['--both']);
  assert.equal(r.status,0,r.text);
  assert.match(r.text,/no-rollable-entries/);
});
test('TEST-005 snapshot never writes through cloned leaf or ancestor symlinks',t=> {
  for(const ancestor of [false,true]) {
    const dir=fixture(t);
    const external=fs.mkdtempSync(path.join(os.tmpdir(),'aai-release-victim-'));
    t.after(()=>fs.rmSync(external,{recursive:true,force:true}));
    const victim=path.join(external,'victim.txt');
    fs.writeFileSync(victim,'EXTERNAL ORIGINAL\n');
    const link=path.join(dir,ancestor?'nested':'link');
    fs.symlinkSync(ancestor?external:victim,link);
    git(dir,'add','.');git(dir,'commit','-m','tracked link');
    fs.unlinkSync(link);
    if(ancestor) {
      fs.mkdirSync(link);
      put(dir,'nested/victim.txt','LOCAL REPLACEMENT\n');
      git(dir,'rm','--cached','nested');git(dir,'add','-N','nested/victim.txt');
    } else fs.writeFileSync(link,'LOCAL REPLACEMENT\n');
    const observed=dry(dir,['--both']);
    assert.equal(observed.status,0,observed.text);
    assert.equal(fs.readFileSync(victim,'utf8'),'EXTERNAL ORIGINAL\n','outside target must remain byte-identical');
  }
  const dir=fixture(t),external=path.join(os.tmpdir(),path.basename(dir)+'-notes');
  t.after(()=>fs.rmSync(external,{force:true}));
  fs.writeFileSync(external,note);fs.unlinkSync(path.join(dir,changelog));
  fs.symlinkSync(external,path.join(dir,changelog));
  git(dir,'add','.');git(dir,'commit','-m','linked notes');
  const observed=dry(dir);
  assert.notEqual(observed.status,0,observed.text);
  assert.match(observed.text,/symlink/i);
  assert.equal(fs.readFileSync(external,'utf8'),note);
});
test('TEST-005 checkpoint output cannot replace tracked files or symlinks',t=> {
  const dir=fixture(t);
  const original=fs.readFileSync(path.join(dir,changelog),'utf8');
  let r=dry(dir,['--report',path.join(dir,changelog)]);
  assert.notEqual(r.status,0,r.text);
  assert.match(r.text,/report path is a tracked source file/);
  const output=path.join(dir,'linked-report.json');
  fs.symlinkSync(path.join(dir,changelog),output);
  r=dry(dir,['--report',output]);
  assert.notEqual(r.status,0,r.text);
  assert.match(r.text,/report path.*symlink/);
  assert.equal(fs.readFileSync(path.join(dir,changelog),'utf8'),original);
});
test('TEST-005 checkpoint output refuses source directory symlinks and broken leaves',t=> {
  const dir=fixture(t);
  const outside=fs.mkdtempSync(path.join(os.tmpdir(),'aai-report-outside-'));
  t.after(()=>fs.rmSync(outside,{recursive:true,force:true}));
  fs.symlinkSync(outside,path.join(dir,'report-directory'));
  let r=dry(dir,['--report',path.join(dir,'report-directory/result.json')]);
  assert.notEqual(r.status,0,'directory symlink must refuse before checkpoint writes: '+r.text);
  assert.equal(fs.existsSync(path.join(outside,'result.json')),false);
  fs.symlinkSync(path.join(outside,'missing.json'),path.join(dir,'broken-report.json'));
  r=dry(dir,['--report',path.join(dir,'broken-report.json')]);
  assert.notEqual(r.status,0,r.text);
  assert.equal(fs.existsSync(path.join(outside,'missing.json')),false);
});
test('TEST-005 checkpoint output refuses Git metadata including .git/index (V4-1)',t=> {
  const dir=fixture(t);
  const index=path.join(dir,'.git','index');
  const before=fs.readFileSync(index);
  const gitDir=spawnSync('git',['rev-parse','--git-dir'],{cwd:dir,encoding:'utf8'}).stdout.trim();
  const commonDir=spawnSync('git',['rev-parse','--git-common-dir'],{cwd:dir,encoding:'utf8'}).stdout.trim();
  const targets=[
    index,
    path.join(dir,'.git','objects','info','packs'),
    path.resolve(dir,gitDir,'HEAD'),
    path.resolve(dir,commonDir,'config')
  ];
  for(const target of targets) {
    fs.mkdirSync(path.dirname(target),{recursive:true});
    const prior=fs.existsSync(target)?fs.readFileSync(target):null;
    const r=dry(dir,['--report',target]);
    assert.notEqual(r.status,0,'Git metadata report must refuse: '+target+'\n'+r.text);
    assert.match(r.text,/report path is inside Git metadata/);
    if(prior===null)assert.equal(fs.existsSync(target),false,target);
    else assert.deepEqual(fs.readFileSync(target),prior,target);
  }
  assert.deepEqual(fs.readFileSync(index),before);
});
test('TEST-006 PR workflow aggregate executes every mode and all three languages', t => {
  const workflow = fs.readFileSync(path.join(root,'.github/workflows/skill-suite.yml'),'utf8');
  assert.match(workflow,/  release-dry-run:\n/);
  assert.match(workflow,/needs: \[[^\n]*release-dry-run/);
  const job=workflow.split('  release-dry-run:\n')[1].split(/\n  [a-z][\w-]*:\n/)[0];
  assert.match(job,/github.event_name == 'pull_request'/);
  assert.doesNotMatch(job,/body-reuse|outputs.mode/);
  assert.match(job,/release-dry-run.mjs/);
  const gate=workflow.split('      - name: Require the mode-relevant skills job to have succeeded\n')[1].split('        run: |\n')[1].split('\n  self-hosting-smoke:')[0].split('\n').map(l=>l.startsWith('          ')?l.slice(10):l).join('\n');
  for(const mode of ['full','selected','body-reuse']) {
    for(const result of ['success','failure']) {
      const values={
        'github.event_name':'pull_request',
        'needs.select.result':'success',
        'needs.select.outputs.mode':mode,
        'needs.select.outputs.selected_runners':'1',
        'needs.release-notes.result':'success',
        'needs.release-dry-run.result':result,
        'needs.tracked-ignored.result':'success',
        'needs.native-worktree-seed.result':mode==='body-reuse'?'skipped':'success',
        'needs.self-hosting-smoke.result':mode==='body-reuse'?'skipped':'success',
        'needs.skills-selected.result':mode==='selected'?'success':'skipped',
        'needs.skills-selected-sharded.result':'skipped',
        'needs.skills-full.result':mode==='full'?'success':'skipped'
      };
      const script=gate.replace(/\$\{\{\s*(.*?)\s*\}\}/g,(_all,key)=>{
        assert.ok(key in values,key);
        return values[key];
      });
      const execution=run('bash',['-c',script],root,{BODY_PROOF:'current body proof'});
      assert.equal(execution.status,result==='success'?0:1,mode+' '+execution.stdout+execution.stderr);
    }
  }
  const dir=fixture(t,{
    'tests/all.test.mjs':`// ${changelog}\nimport test from 'node:test';test('first',()=>console.log('NODE_FIRST'));test('last',()=>console.log('NODE_LAST'));`,
    'tests/test-all.sh':`#!/bin/bash\n# ${changelog}\necho SHELL_EXECUTED\n`,
    'tests/all.Tests.ps1':`# ${changelog}\nDescribe 'all' { It 'executed' { Write-Host PESTER_EXECUTED; 1 | Should -Be 1 } }`
  });
  const report=path.join(dir,'all-results.json');
  const execution=dry(dir,['--report',report]);
  assert.equal(execution.status,0,execution.text);
  const results=JSON.parse(fs.readFileSync(report)).results;
  assert.equal(results.length,3);
  for(const marker of ['NODE_FIRST','NODE_LAST','SHELL_EXECUTED','PESTER_EXECUTED'])assert.ok(results.some(r=>r.output.includes(marker)),marker);
});
test('TEST-006 failure diagnostic budget fits the actual workflow deadline',()=> {
  const workflow=fs.readFileSync(path.join(root,'.github/workflows/skill-suite.yml'),'utf8');
  const job=workflow.split('  release-dry-run:\n')[1].split(/\n  [a-z][\w-]*:\n/)[0];
  const deadline=Number(/timeout-minutes: (\d+)/.exec(job)[1])*60;
  assert.equal(deadline,1200,'slow rolled failure plus ordinary diagnostic needs the amended job deadline');
  const budget=Number(/--budget-seconds (\d+)/.exec(job)?.[1]);
  assert.equal(budget,1080);
  assert.ok(budget>=2*540,'two complete540-second reader arms fit the executor allowance');
  assert.ok(deadline>=budget+120,'reserve setup/report/upload time outside executor budget');
  assert.match(job,/if: always\(\)/);
});
test('TEST-007 slow failure classifies both complete arms; exhaustion preserves partial evidence',t=> {
  const dir=fixture(t);
  const report=path.join(dir,'slow-report.json');
  put(dir,'tests/slow.test.mjs',`
    import test from 'node:test';
    import fs from 'node:fs';
    import assert from 'node:assert/strict';
    test('slow',async()=> {
      const ordinary=fs.readFileSync('${changelog}','utf8').includes('## [unreleased] — Fixture');
      if(ordinary) {
        const checkpoint=JSON.parse(fs.readFileSync(${JSON.stringify(report)}));
        assert.equal(checkpoint.complete,false);
        assert.equal(checkpoint.results[0].differential,'diagnostic-pending');
        assert.ok(checkpoint.pending.some(x=>x.arm==='ordinary'));
      }
      await new Promise(r=>setTimeout(r,400));
      assert.ok(ordinary);
    });
  `);
  git(dir,'add','.');
  let r=dry(dir,['--budget-seconds','5','--timeout-seconds','2','--report',report]);
  assert.equal(r.status,1,r.text);
  let data=JSON.parse(fs.readFileSync(report));
  assert.equal(data.complete,true);
  assert.equal(data.results.length,2);
  assert.equal(data.results.find(x=>x.arm==='rolled').differential,'rollup-only');
  assert.equal(data.results.find(x=>x.arm==='ordinary').exitCode,0);
  put(dir,'tests/slow.test.mjs',`// ${changelog}\nawait new Promise(r=>setTimeout(r,10000));`);
  const began=performance.now();
  r=dry(dir,['--budget-seconds','1','--timeout-seconds','2','--report',report]);
  assert.ok(performance.now()-began<5000,'scaled outer deadline retains final report after budget exhaustion');
  assert.equal(r.status,1,r.text);
  data=JSON.parse(fs.readFileSync(report));
  assert.equal(data.complete,false);
  assert.equal(data.termination,'budget-exhausted');
  assert.equal(data.sourcePreserved,true);
  assert.ok(data.pending.some(x=>x.arm==='ordinary'&&x.file==='tests/slow.test.mjs'));
  assert.equal(data.results.find(x=>x.arm==='rolled').differential,'diagnostic-incomplete');
  assert.ok(data.results.some(x=>x.disposition==='budget-exhausted'));
});
test('TEST-007 ordinary diagnostic interruption stays incomplete rather than baseline failure',t=> {
  const dir=fixture(t,{'tests/slow.test.mjs':`
    import fs from 'node:fs';
    const ordinary=fs.readFileSync('${changelog}','utf8').includes('## [unreleased] — Fixture');
    if(ordinary)await new Promise(r=>setTimeout(r,10000));
    else throw Error('rolled assertion failure');
  `});
  const report=path.join(dir,'diagnostic-report.json');
  const r=dry(dir,['--budget-seconds','2','--timeout-seconds','4','--report',report]);
  assert.equal(r.status,1,r.text);
  const data=JSON.parse(fs.readFileSync(report));
  assert.equal(data.termination,'budget-exhausted');
  assert.ok(data.results.some(x=>x.arm==='ordinary'&&x.disposition==='budget-exhausted'));
  assert.equal(data.results.find(x=>x.arm==='rolled').differential,'diagnostic-incomplete');
  assert.ok(data.pending.some(x=>x.arm==='ordinary'),'unfinished ordinary execution remains pending');
});
test('TEST-007 both corpus arms report each reader duration and concurrency bound',t=> {
  const dir=fixture(t, {
    'tests/new.test.mjs':`// ${changelog}\nimport test from 'node:test';test('pass',()=>{});`,'tests/second.test.mjs':`// ${changelog}\nimport test from 'node:test';test('pass',()=>{});`
  });
  const r=dry(dir,['--both','--jobs','2','--report',path.join(dir,'result.json')]);
  assert.equal(r.status,0,r.text);
  const j=JSON.parse(fs.readFileSync(path.join(dir,'result.json')));
  assert.equal(j.jobs,2);
  assert.equal(j.budgetSeconds,1080);
  assert.ok(j.peakActive<=2&&j.peakActive>0);
  assert.match(j.hostedTiming,/unverified/i);
  for(const arm of ['ordinary','rolled']) {
    assert.equal(j.results.filter(v=>v.arm===arm).length,2);
    assert.ok(j.wallSeconds[arm]>=0);
    for(const v of j.results.filter(v=>v.arm===arm))assert.ok(v.durationSeconds>=0&&v.exitCode===0);
  }
  assert.ok(j.machine&&j.interpreters.node);assert.equal(j.sourcePreserved,true);assert.match(j.sourceProof.treeSha256,/^[a-f0-9]{64}$/);for(const row of j.results)assert.match(row.output,/# pass 1/); }); test('TEST-007 production default budget and weighted dispatch keep all readers',t=> {
  const dir=fixture(t,{
    'tests/alpha.test.mjs':`// ${changelog}\nimport test from 'node:test';test('alpha',()=>{});`,
    'tests/bravo.test.mjs':`// ${changelog}\nimport test from 'node:test';test('bravo',()=>{});`,
    'tests/skills/suite-weights.tsv':'aai-alpha\t1\naai-bravo\t20\n'
  });
  const report=path.join(dir,'schedule-report.json');
  const result=dry(dir,['--jobs','1','--report',report]);
  assert.equal(result.status,0,result.text);
  const data=JSON.parse(fs.readFileSync(report));
  assert.equal(data.readerTimeoutSeconds,540,'production default must cover the measured464s release reader');
  assert.equal(data.schedule.policy,'suite-weight-desc');
  assert.deepEqual(data.results.map(r=>r.file),['tests/bravo.test.mjs','tests/alpha.test.mjs']);
  assert.deepEqual([...data.results.map(r=>r.file)].sort(),[...data.inventory.readers].sort());
  assert.ok(data.results.every(r=>r.exitCode===0));
  fs.writeFileSync(path.join(dir,'tests/skills/suite-weights.tsv'),'malformed weight\n');
  const fallback=dry(dir,['--jobs','1','--report',report]);
  assert.equal(fallback.status,0,fallback.text);
  const degraded=JSON.parse(fs.readFileSync(report));
  assert.match(fallback.text,/WEIGHTS_IGNORED/);
  assert.deepEqual(degraded.results.map(r=>r.file),[...degraded.inventory.readers].sort());
});
const head='a'.repeat(40);
function checkRun(id,conclusion='success',sha=head) {
  return {
    id,name:'aggregate',head_sha:sha,status:conclusion==='pending'?'in_progress':'completed',conclusion:conclusion==='pending'?null:conclusion,started_at:`2026-10-27T00:00:${String(id).padStart(2,'0')}Z`,details_url:`https://github.com/test/repo/actions/runs/${id}/job/${id}`
  };
}
function transport(t,checks,opts= {
}) {
  const dir=fixture(t),bin=path.join(dir,'bin');
  fs.mkdirSync(bin);
  git(dir,'remote','add','origin','https://github.com/test/repo.git');
  const data= {
    head,checks,...opts
  };
  put(dir,'transport.json',JSON.stringify(data));
  put(dir,'bin/gh',`#!/usr/bin/env node
const fs=require('fs'),p=${JSON.stringify(path.join(dir,'transport.json'))},d=JSON.parse(fs.readFileSync(p)),a=process.argv.slice(2);fs.appendFileSync(${JSON.stringify(path.join(dir,'calls.jsonl'))},JSON.stringify(a)+'\\n');const out=x=>console.log(JSON.stringify(x));if(a[0]==='--version'){console.log('fixture gh');process.exit(0);}if(a[0]==='pr'&&a[1]==='view'){d.views=(d.views||0)+1;fs.writeFileSync(p,JSON.stringify(d));out({headRefOid:d.move&&d.views>1?'b'.repeat(40):d.head,url:'https://github.com/test/repo/pull/1',number:d.number??1});}else if(a[0]==='pr'&&a[1]==='checks'){if(d.transportFail){console.error('fixture network error');process.exit(42);}out(d.required||[{name:'aggregate',bucket:'pass',link:'x'}]);}else if(a[0]==='api'&&a.some(x=>x.includes('/check-runs'))){if(d.transportFail){console.error('fixture network error');process.exit(42);}out(d.malformed?{}:(d.pages||[{total_count:d.checks.length,check_runs:d.checks}]));}else if(a[0]==='api'&&a.some(x=>x.includes('/actions/runs/'))){const id=Number(a.find(x=>x.includes('/actions/runs/')).split('/').pop());out(d.workflows?.[id]||d.workflow||{id,head_sha:d.head,created_at:new Date(Date.UTC(2026,9,27,0,0,id)).toISOString()});}else if(a[0]==='api'&&a.some(x=>x.includes('/statuses'))){out(d.statusPages||[[]]);}else{console.error('unexpected '+a.join(' '));process.exit(90);}`);
  fs.chmodSync(path.join(bin,'gh'),0o755);
  return {
    dir,env: {
      PATH:bin+path.delimiter+process.env.PATH
    },data:path.join(dir,'transport.json')
  };
}
function watcher(f,required=false) {
  return run(process.execPath,[path.join(root,'.aai/scripts/watch-ci.mjs'),'--pr','1',...(required?['--required']:[]),'--interval-seconds','0.01','--max-wait-seconds','0.03'],f.dir,f.env);
}
function releaseReader(f,expected=head) {
  return run(process.execPath,['--input-type=module','-e',`import {readReleaseRequiredChecks} from ${JSON.stringify('file://'+path.join(root,'.aai/scripts/release-finish.mjs'))};try{console.log(JSON.stringify(readReleaseRequiredChecks({pr:1,repo:'test/repo',head:${JSON.stringify(expected)},cwd:${JSON.stringify(f.dir)}})));}catch(e){console.error(e.message);process.exit(20);}`],f.dir,f.env);
}
test('TEST-008 watch and release select newer pending/success over failed cancelled run',t=> {
  for(const conclusion of ['success','pending']) {
    const f=transport(t,[checkRun(2,conclusion),checkRun(1,'cancelled')]);
    let r=watcher(f,true);
    assert.equal(r.status,conclusion==='success'?0:3,r.stdout+r.stderr);
    if(conclusion==='pending')assert.match(r.stdout+r.stderr,/pending/);
    r=releaseReader(f);
    assert.equal(r.status,0,r.stderr);
    const checks=JSON.parse(r.stdout);
    assert.equal(checks.length,1);
    assert.equal(checks[0].bucket,conclusion==='success'?'pass':'pending');
  }
});
test('TEST-008 queued rerun without started_at still supersedes old failure', t => {
  const queued = {...checkRun(3, 'pending'), started_at:null, details_url:'https://github.com/test/repo/actions/runs/7/job/3'};
  const older = {...checkRun(2, 'failure'), details_url:'https://github.com/test/repo/actions/runs/7/job/2'};
  const f = transport(t, [older, queued], {workflow:{head_sha:head, created_at:'2026-10-27T00:00:00Z'}});
  const watched = watcher(f, true);
  assert.equal(watched.status, 3, watched.stdout + watched.stderr);
  assert.match(watched.stdout + watched.stderr, /pending/);
  const released = releaseReader(f);
  assert.equal(released.status, 0, released.stderr);
  assert.equal(JSON.parse(released.stdout)[0].bucket, 'pending');
});
test('TEST-009 failures mixed heads paging required filters and malformed transport fail closed',t=> {
  let f=transport(t,[checkRun(2,'failure'),checkRun(1)]);
  assert.equal(watcher(f).status,5);
  assert.equal(JSON.parse(releaseReader(f).stdout)[0].bucket,'fail');
  f=transport(t,[checkRun(1),checkRun(2,'success','b'.repeat(40))]);
  assert.notEqual(watcher(f).status,0);
  assert.notEqual(releaseReader(f).status,0);
  f=transport(t,[checkRun(1)], {
    move:true
  });
  assert.notEqual(watcher(f).status,0);
  f=transport(t,[], {
    pages:[{
      total_count:2,check_runs:[checkRun(1,'failure')]
    }, {
      total_count:2,check_runs:[checkRun(2)]
    }]
  });
  assert.equal(watcher(f).status,0);
  assert.equal(releaseReader(f).status,0);
  const calls=fs.readFileSync(path.join(f.dir,'calls.jsonl'),'utf8');
  assert.match(calls,/--paginate/);
  assert.match(calls,/--slurp/);
  f=transport(t,[checkRun(1), {
    ...checkRun(2,'failure'),name:'optional'
  }]);
  assert.equal(watcher(f,true).status,0);
  assert.equal(watcher(f).status,5);
  for(const opts of [{
    malformed:true
  }, {
    transportFail:true
  }, {
    pages:[{
      total_count:2,check_runs:[checkRun(1)]
    }]
  }, {
    workflow:{head_sha:head,created_at:null}
  }]) {
    f=transport(t,[checkRun(1)],opts);
    assert.notEqual(watcher(f).status,0);
    assert.notEqual(releaseReader(f).status,0);
  }
  f=transport(t,[checkRun(1)]);
  assert.notEqual(releaseReader(f,'b'.repeat(40)).status,0);
  f=transport(t,[], {
    required:[{
      name:'legacy',bucket:'pass'
    }],statusPages:[[{
      id:2,context:'legacy',state:'success',sha:head,created_at:'2026-10-27T00:00:02Z',target_url:'https://example.invalid'
    }],[{
      id:1,context:'legacy',state:'failure',sha:head,created_at:'2026-10-27T00:00:01Z'
    }]]
  });
  assert.equal(watcher(f,true).status,0);
});
test('TEST-009 refuses repeated pagination and inconsistent PR identity',t=> {
  for (const options of [
    {pages:[{total_count:2,check_runs:[checkRun(1)]},{total_count:2,check_runs:[checkRun(1)]}]},
    {number:2},
    {statusPages:[[{id:1,context:'legacy',state:'success',created_at:'2026-10-27T00:00:00Z'}],[{id:1,context:'legacy',state:'success',created_at:'2026-10-27T00:00:00Z'}]]}
  ]) {
    const f=transport(t,[checkRun(1)],options);
    assert.notEqual(watcher(f).status,0);
    assert.notEqual(releaseReader(f).status,0);
  }
});
test('TEST-009 one authoritative ordering is invariant across every response permutation',t=> {
  const checks=[
    {...checkRun(3,'pending'),started_at:null,details_url:'https://github.com/test/repo/actions/runs/1/job/3'},
    {...checkRun(2),started_at:'2026-10-27T10:00:10Z',details_url:'https://github.com/test/repo/actions/runs/1/job/2'},
    {...checkRun(4,'failure'),started_at:'2026-10-27T10:00:05Z',details_url:'https://github.com/test/repo/actions/runs/2/job/4'}
  ];
  const workflows={1:{id:1,head_sha:head,created_at:'2026-10-27T10:00:01Z'},2:{id:2,head_sha:head,created_at:'2026-10-27T10:00:02Z'}};
  for(const order of [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]]) {
    const f=transport(t,order.map(i=>checks[i]),{workflows});
    const watched=watcher(f,true);assert.equal(watched.status,5,watched.stdout+watched.stderr);
    const released=releaseReader(f);assert.equal(released.status,0,released.stderr);
    const selected=JSON.parse(released.stdout)[0];assert.equal(selected.id,4);assert.equal(selected.bucket,'fail');
  }
  const queued={...checkRun(200,'pending'),started_at:null,details_url:'https://github.com/test/repo/actions/runs/200/job/200'};
  const lateOld={...checkRun(100,'failure'),started_at:'2026-10-27T10:05:00Z',details_url:'https://github.com/test/repo/actions/runs/100/job/100'};
  const created={100:{id:100,head_sha:head,created_at:'2026-10-27T10:00:00Z'},200:{id:200,head_sha:head,created_at:'2026-10-27T10:04:00Z'}};
  for(const rows of [[lateOld,queued],[queued,lateOld]]) {
    const f=transport(t,rows,{workflows:created});
    const watched=watcher(f,true);assert.equal(watched.status,3,watched.stdout+watched.stderr);assert.match(watched.stdout+watched.stderr,/pending/);
    const released=releaseReader(f);assert.equal(released.status,0,released.stderr);assert.equal(JSON.parse(released.stdout)[0].id,200);
  }
});
test('TEST-010 captured historical reruns and actual pre/post fix Git objects',t=> {
  const history=JSON.parse(fs.readFileSync(path.join(root,'tests/fixtures/release-first-pr504.json')));
  assert.match(history.provenance.url,/pull\/504/);
  assert.equal(history.checks.length,2);
  const f=transport(t,history.checks, {
    head:history.head,required:[{
      name:history.checks[0].name,bucket:'pass'
    }]
  });
  assert.equal(watcher(f,true).status,0);
  assert.equal(releaseReader(f,history.head).status,0);
  // Resolve the actual repository history; offline installed copies cannot invent it.
  const shas=['734339e0','20ee3591'];
  for(const ref of shas) {
    const resolved=run('git',['rev-parse','--verify',ref+'^{commit}'],root);
    assert.equal(resolved.status,0,resolved.stderr);
    const dir=fs.mkdtempSync(path.join(os.tmpdir(),'aai-release-history-'));
    t.after(()=>fs.rmSync(dir, {
      recursive:true,force:true
    }));
    git(dir,'clone','--quiet','--no-local','--no-hardlinks',root,path.join(dir,'repo'));
    const repo=path.join(dir,'repo');
    git(repo,'checkout','--quiet','--detach',resolved.stdout.trim());
    const module=path.join(root,'.aai/scripts/lib/release-rollup.mjs');
    const source=git(repo,'show','HEAD:'+changelog);
    const rolled=run(process.execPath,['--input-type=module','-e',`import fs from 'node:fs';import {rollup} from ${JSON.stringify('file://'+module)};fs.writeFileSync(${JSON.stringify(path.join(repo,changelog))},rollup(fs.readFileSync(${JSON.stringify(path.join(repo,changelog))},'utf8'),'v2099.01.01').content);`],repo);
    assert.equal(rolled.status,0,rolled.stderr);
    const text=fs.readFileSync(path.join(repo,'tests/skills/lib/recheck.test.mjs'),'utf8');
    assert.match(text,/TEST-2819/);
    assert.match(text,/TEST-2821/);
    const env= {
      NODE_TEST_CONTEXT:'',NODE_OPTIONS:''
    };
    put(repo,changelog,source);
    const ordinary=run(process.execPath,['--test','--test-name-pattern','TEST-2819|TEST-2821','tests/skills/lib/recheck.test.mjs'],repo,env);
    assert.equal(ordinary.status,0,ordinary.stdout+ordinary.stderr);
    const roll=run(process.execPath,['--input-type=module','-e',`import fs from 'node:fs';import {rollup} from ${JSON.stringify('file://'+module)};fs.writeFileSync(${JSON.stringify(path.join(repo,changelog))},rollup(fs.readFileSync(${JSON.stringify(path.join(repo,changelog))},'utf8'),'v2099.01.01').content);`],repo);
    assert.equal(roll.status,0,roll.stderr);
    const after=run(process.execPath,['--test','--test-name-pattern','TEST-2819|TEST-2821','tests/skills/lib/recheck.test.mjs'],repo,env);
    assert.equal(after.status,ref==='734339e0'?1:0,after.stdout+after.stderr);
    console.log(`history ${resolved.stdout.trim()} ordinary=${ordinary.status} rolled=${after.status} TEST-2819 TEST-2821 tests/skills/lib/recheck.test.mjs`);
  }
});
test('TEST-011 profile inventory suite ownership product and release notes',()=> {
  const profiles=fs.readFileSync(path.join(root,'.aai/system/PROFILES.yaml'),'utf8'),map=fs.readFileSync(path.join(root,'tests/skills/suite-map.yaml'),'utf8');
  for(const f of ['.aai/scripts/release-dry-run.mjs','.aai/scripts/lib/release-rollup.mjs','.aai/scripts/lib/github-checks.mjs']) {
    assert.equal(profiles.split(f).length-1,1,f);
    assert.ok(map.includes(f),f);
  }
  assert.match(map,/  aai-release-first:/);
  const product=fs.readFileSync(path.join(root,'docs/product/release-command-finish.md'),'utf8');
  assert.match(product,/dry-run/);
  assert.match(product,/newest/);
  assert.match(product,/missing.*tool/i);
  assert.match(fs.readFileSync(path.join(root,changelog),'utf8'),/release.*dry-run/i);
});
