#!/usr/bin/env node
// Read-only PR rehearsal. Every child reads an independent, committed snapshot.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {spawn,spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {rollup} from './lib/release-rollup.mjs';
// Measured complete release reader: 464.412s alone on the supported baseline.
// Successful PR runs retain a ten-minute target. Failure diagnostics have a
// twenty-minute job ceiling, with an eighteen-minute total executor budget.
export const DEFAULT_READER_TIMEOUT_SECONDS=540;
export const DEFAULT_BUDGET_SECONDS=1080;
export function cleanEnvironment(source=process.env) {
  const env=Object.fromEntries(Object.entries(source).filter(([k])=>!/^GIT_|^GH_|^GITHUB_|TOKEN|PASSWORD|SECRET|CREDENTIAL|ASKPASS|^NODE_TEST_CONTEXT$|^NODE_OPTIONS$/i.test(k)));
  return {
    ...env,GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:os.devNull,GIT_TERMINAL_PROMPT:'0',AAI_GIT_WRITE:'1'
  };
}
function command(exe,args,cwd,env=cleanEnvironment()) {
  const r=spawnSync(exe,args, {
    cwd,env,encoding:'utf8',timeout:120000,maxBuffer:32*1024*1024
  });
  if(r.error||r.status!==0)throw Error(`${exe} ${args.join(' ')}: ${r.error?.message||r.stderr||r.status}`);
  return r.stdout;
}
function tracked(root) {
  return command('git',['ls-files','-z'],root).split('\0').filter(Boolean);
}
// Only resolvable literal edges establish ownership. Node relative modules are
// file-relative; shell/PowerShell literal paths are relative to the invoked root.
// Known script-directory forms are resolved explicitly, never by basename.
function helperReferences(owner,body) {
  const references=[];
  const directory=path.posix.dirname(owner);
  const add=(literal,base)=> {
    if(!literal||/[$`{}*?]/.test(literal)||path.posix.isAbsolute(literal))return;
    const resolved=path.posix.normalize(path.posix.join(base,literal));
    if(resolved.startsWith('tests/'))references.push(resolved);
  };
  if(/\.mjs$/i.test(owner)) {
    const imports=/(?:\bfrom\s*|\bimport\s*(?:\(\s*)?|\brequire\s*\(\s*)["']([^"']+)["']/g;
    for(const match of body.matchAll(imports)) {
      if(match[1].startsWith('.'))add(match[1],directory);
    }
  } else {
    // SCRIPT_DIR is recognized only with the canonical BASH_SOURCE definition.
    const scriptDir=body.includes('SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"');
    const sources=/(?:^|[;\n])\s*(?:source|\.)\s+(?:"([^"\n]+)"|'([^'\n]+)'|([^\s;]+))/g;
    for(const match of body.matchAll(sources)) {
      const raw=match[1]??match[2]??match[3];
      const literal=/\.ps1$/i.test(owner)?raw.replace(/\\/g,'/'):raw;
      const prefix=/^\$(?:PSScriptRoot|\{PSScriptRoot\})\//i.exec(literal);
      const shellPrefix=scriptDir&&/^\$(?:SCRIPT_DIR|\{SCRIPT_DIR\})\//.exec(literal);
      if(/\.ps1$/i.test(owner)&&prefix)add(literal.slice(prefix[0].length),directory);
      else if(/\.sh$/i.test(owner)&&shellPrefix)add(literal.slice(shellPrefix[0].length),directory);
      else add(literal,'.');
    }
  }
  return references;
}
export function discover(root) {
  const sources=tracked(root).filter(f=>/^tests\//.test(f)&&/\.(?:mjs|sh|ps1)$/i.test(f));
  const text=new Map(sources.map(f=>[f,fs.existsSync(path.join(root,f))?fs.readFileSync(path.join(root,f),'utf8'):'']));
  const runnable=f=>/\.(?:test\.mjs|Tests\.ps1)$/i.test(f)||/(?:^|\/)test-[^/]+\.(?:sh|mjs)$/i.test(f);
  const selected=new Set(),owners=[];
  for(const f of sources.filter(f=>/CHANGELOG/i.test(text.get(f)))) {
    if(runnable(f)) {
      selected.add(f);
      continue;
    }
    // A literal helper reference can pass through other helpers. Resolve to all
    // runnable owners conservatively; unknown ownership is a named failure.
    const seen=new Set([f]),pending=[f],found=new Set();
    while(pending.length) {
      const helper=pending.pop();
      for(const [owner,body] of text) {
        if(owner===helper||!helperReferences(owner,body).includes(helper))continue;
        if(runnable(owner))found.add(owner);
        else if(!seen.has(owner)) {
          seen.add(owner);
          pending.push(owner);
        }
      }
    }
    if(!found.size)throw Error(`unowned reader helper: ${f}`);
    for(const owner of found) {
      selected.add(owner);
      owners.push({
        helper:f,owner
      });
    }
  }
  return {
    readers:[...selected].sort(),owners
  };
}
// Existing suite weights guide order only. Missing/new readers conservatively
// receive the maximum known estimate; every discovered file stays in the queue.
export function readerSchedule(root,files) {
  const weights=new Map();
  let warning;
  try {
    const text=fs.readFileSync(path.join(root,'tests/skills/suite-weights.tsv'),'utf8');
    for(const line of text.split(/\r?\n/)) {
      if(!line.trim()||line.startsWith('#'))continue;
      const match=/^(aai-[A-Za-z0-9_-]+)\s+([1-9][0-9]*)$/.exec(line);
      if(!match||!Number.isSafeInteger(Number(match[2]))||weights.has(match[1]))throw Error('malformed or duplicate weight');
      weights.set(match[1],Number(match[2]));
    }
    if(!weights.size)throw Error('no weight rows');
  } catch(e) {
    weights.clear();
    warning=`WEIGHTS_IGNORED ${e.code||e.message}`;
  }
  const fallback=Math.max(1,...weights.values());
  const estimates=Object.fromEntries(files.map(file=> {
    const stem=path.basename(file).replace(/^test-/,'').replace(/\.test\.mjs$/i,'').replace(/\.Tests\.ps1$/i,'').replace(/\.(?:sh|mjs|ps1)$/i,'');
    const suite=stem.startsWith('aai-')?stem:`aai-${stem}`;
    return [file,weights.get(suite)??fallback];
  }));
  const orderedReaders=[...files].sort((a,b)=>estimates[b]-estimates[a]||a.localeCompare(b));
  return {policy:'suite-weight-desc',estimatesOnly:true,orderedReaders,estimatedWeights:estimates,warning};
}
function clone(source,dest) {
  command('git',['clone','--quiet','--no-local','--no-hardlinks',source,dest],path.dirname(dest));
  // A normal clone has only the checked-out local branch. Preserve the base
  // name that existing read-only history assertions resolve, without sharing refs.
  const base=spawnSync('git',['rev-parse','--verify','refs/heads/main'], {
    cwd:source,env:cleanEnvironment(),encoding:'utf8'
  });
  const fallback=base.status===0?base:spawnSync('git',['rev-parse','--verify','refs/remotes/origin/main'], {
    cwd:source,env:cleanEnvironment(),encoding:'utf8'
  });
  if(fallback.status===0)command('git',['update-ref','refs/heads/main',fallback.stdout.trim()],dest);
  // Never leave a source checkout reachable as a push/fetch destination.
  command('git',['remote','set-url','origin','https://github.com/aai-rehearsal/disabled.git'],dest);
  command('git',['remote','set-url','--push','origin','DISABLED'],dest);
  command('git',['config','credential.helper',''],dest);
  command('git',['config','core.hooksPath',os.devNull],dest);
}
function commit(root) {
  command('git',['-c','user.name=Release rehearsal','-c','user.email=rehearsal@example.invalid','add','-A'],root);
  command('git',['-c','user.name=Release rehearsal','-c','user.email=rehearsal@example.invalid','commit','--quiet','--allow-empty','--no-verify','-m','Disposable release rehearsal snapshot'],root);
}
// Walk only owned clone directories. A checkout can contain a symlink where
// the dirty source now contains a regular file or directory; copyFileSync and
// rmSync otherwise follow that cloned ancestor/leaf outside the scratch tree.
function destination(root,relative) {
  const base=path.resolve(root);
  const target=path.resolve(base,relative);
  if(!target.startsWith(base+path.sep))throw Error(`unsafe snapshot path: ${relative}`);
  const parents=path.relative(base,path.dirname(target)).split(path.sep).filter(Boolean);
  let current=base;
  for(const part of parents) {
    current=path.join(current,part);
    let stat;
    try { stat=fs.lstatSync(current); }
    catch(e) { if(e.code!=='ENOENT')throw e; }
    if(stat&&(!stat.isDirectory()||stat.isSymbolicLink()))fs.rmSync(current,{recursive:true,force:true});
    if(!stat||!stat.isDirectory()||stat.isSymbolicLink())fs.mkdirSync(current);
  }
  return target;
}
function snapshot(source,dest) {
  clone(source,dest);
  const files=command('git',['ls-files','--cached','--others','--exclude-standard','-z'],source).split('\0').filter(Boolean);
  for(const f of files) {
    const from=path.join(source,f),to=destination(dest,f);
    if(!fs.existsSync(from)) {
      fs.rmSync(to, {
        force:true
      });
      continue;
    }
    const stat=fs.lstatSync(from);
    fs.mkdirSync(path.dirname(to), {
      recursive:true
    });
    if(stat.isSymbolicLink()) {
      fs.rmSync(to, {
        force:true
      });
      fs.symlinkSync(fs.readlinkSync(from),to);
    }
    else if(stat.isFile()) {
      fs.rmSync(to,{recursive:true,force:true});
      fs.copyFileSync(from,to);
    }
  }
  commit(dest);
}
function invocation(file,cwd,env) {
  if(/\.mjs$/i.test(file))return [process.execPath,['--test','--test-reporter=tap',file]];
  if(/\.ps1$/i.test(file)) {
    const exe=env.AAI_RELEASE_DRY_PWSH||'pwsh';
    return [exe,['-NoProfile','-NonInteractive','-Command',`$ErrorActionPreference='Stop'; Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop; $c=New-PesterConfiguration; $c.Run.Path='${file.replace(/'/g,"''")}'; $c.Run.Exit=$true; Invoke-Pester -Configuration $c`]];
  }
  if(/^tests\/skills\/test-[^/]+\.sh$/.test(file)&&fs.existsSync(path.join(cwd,'tests/skills/test-framework.sh')))return ['bash',['tests/skills/test-framework.sh','--skill',path.basename(file,'.sh').slice(5)]];
  return ['bash',[file]];
}
const children=new Set();
function terminate(child) {
  if(!child.pid)return;
  try {
    if(process.platform!=='win32')process.kill(-child.pid,'SIGKILL');
    else spawnSync('taskkill',['/PID',String(child.pid),'/T','/F'], {
      stdio:'ignore'
    });
  }
  catch {
  }
}
async function execute(file,arm,base,tmp,index,seconds) {
  const cwd=path.join(tmp,`reader-${index}`);
  clone(base,cwd);
  const env= {
    ...cleanEnvironment(),AAI_TEST_PARALLEL:'1'
  };
  const [exe,args]=invocation(file,cwd,env);
  const start=performance.now();
  let output='',timedOut=false,missing=false;
  const exitCode=await new Promise(resolve=> {
    const child=spawn(exe,args, {
      cwd,env,detached:process.platform!=='win32',stdio:['ignore','pipe','pipe']
    });
    children.add(child);
    const timer=setTimeout(()=> {
      timedOut=true;
      terminate(child);
    },seconds*1000);
    for(const pipe of [child.stdout,child.stderr])pipe.on('data',b=> {
      output=(output+b).slice(-256000);
    });
    child.on('error',e=> {
      missing=e.code==='ENOENT';
      output+=e.message;
    });
    child.on('close',code=> {
      clearTimeout(timer);
      terminate(child);
      children.delete(child);
      resolve(timedOut?124:code??125);
    });
  });
  fs.rmSync(cwd, {
    recursive:true,force:true
  });
  return {
    file,arm,exitCode,durationSeconds:(performance.now()-start)/1000,disposition:timedOut?'timeout':missing?'missing-tool':exitCode===0?'PASS':'FAIL',output
  };
}
function sourceProof(root,reportPath) {
  const hash = createHash('sha256');
  const files = command('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], root).split('\0').filter(Boolean).sort();
  for (const file of files) {
    if(reportPath&&path.resolve(root,file)===reportPath)continue;
    hash.update(file + '\0');
    const absolute = path.join(root, file);
    if (!fs.existsSync(absolute)) { hash.update('MISSING'); continue; }
    const stat = fs.lstatSync(absolute);
    hash.update(String(stat.mode));
    hash.update(stat.isSymbolicLink() ? fs.readlinkSync(absolute) : fs.readFileSync(absolute));
  }
  const indexPath = command('git', ['rev-parse', '--git-path', 'index'], root).trim();
  return {
    treeSha256: hash.digest('hex'),
    indexSha256: createHash('sha256').update(fs.readFileSync(path.resolve(root, indexPath))).digest('hex'),
    refs: command('git', ['for-each-ref', '--format=%(refname) %(objectname)'], root),
    head: command('git', ['rev-parse', 'HEAD'], root).trim()
  };
}
function underPath(base,target) {
  const rel=path.relative(path.resolve(base),path.resolve(target));
  return rel===''||(rel!=='..'&&!rel.startsWith('..'+path.sep)&&!path.isAbsolute(rel));
}
function reportDestination(root,output) {
  const absolute=path.resolve(output),base=path.resolve(root);
  // V4-1: refuse Git metadata (git-dir / common-dir / worktree gitfile) before
  // any checkpoint write. Tracked-file checks miss .git/index because it is
  // never returned by git ls-files.
  const gitDir=path.resolve(root,command('git',['rev-parse','--git-dir'],root).trim());
  const commonDir=path.resolve(root,command('git',['rev-parse','--git-common-dir'],root).trim());
  if(underPath(gitDir,absolute)||underPath(commonDir,absolute)) {
    throw Error('report path is inside Git metadata');
  }
  const gitFile=path.join(base,'.git');
  try {
    if(fs.lstatSync(gitFile).isFile()&&path.resolve(absolute)===path.resolve(gitFile)) {
      throw Error('report path is inside Git metadata');
    }
  } catch(e) {
    if(e.code!=='ENOENT')throw e;
  }
  const relative=path.relative(base,absolute);
  const inside=relative!=='..'&&!relative.startsWith('..'+path.sep)&&!path.isAbsolute(relative);
  if(inside) {
    let cursor=base;
    for(const part of relative.split(path.sep).filter(Boolean)) {
      cursor=path.join(cursor,part);
      let stat;
      try { stat=fs.lstatSync(cursor); }
      catch(e) { if(e.code!=='ENOENT')throw e; }
      if(stat?.isSymbolicLink())throw Error('report path has a symlink leaf or directory ancestor');
    }
  }
  let leaf;
  try { leaf=fs.lstatSync(absolute); }
  catch(e) { if(e.code!=='ENOENT')throw e; }
  if(leaf?.isSymbolicLink())throw Error('report path is a symlink');
  // Resolve external directory aliases before comparing tracked identities.
  // System directory aliases such as macOS /tmp remain valid output locations.
  const canonical=path.join(fs.realpathSync(path.dirname(absolute)),path.basename(absolute));
  const canonicalRelative=path.relative(fs.realpathSync(base),canonical);
  if(underPath(gitDir,canonical)||underPath(commonDir,canonical)) {
    throw Error('report path is inside Git metadata');
  }
  if(tracked(root).includes(canonicalRelative.split(path.sep).join('/')))throw Error('report path is a tracked source file');
  const aliasesSource=canonicalRelative!=='..'&&!canonicalRelative.startsWith('..'+path.sep)&&!path.isAbsolute(canonicalRelative);
  if(!inside&&aliasesSource)throw Error('report directory aliases the source tree');
  return absolute;
}
export async function dryRun(opts) {
  const inventory=discover(opts.root);
  if(opts.list) {
    for(const f of inventory.readers)console.log(`READER ${f}`);
    for(const o of inventory.owners)console.log(`OWNER ${o.helper} -> ${o.owner}`);
    return {
      results:[],inventory
    };
  }
  const schedule=readerSchedule(opts.root,inventory.readers);
  if(schedule.warning)console.log(schedule.warning);
  // The explicitly requested generated report is the only source-tree output.
  // Never let that exception hide an existing tracked file or symlink target.
  const reportPath=opts.report&&reportDestination(opts.root,opts.report);
  const sourceBefore=sourceProof(opts.root,reportPath);
  const start=performance.now(),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'aai-release-dry-')),results=[],wallSeconds= {
  },jobs=opts.jobs||4;
  const budgetSeconds=opts.budgetSeconds??DEFAULT_BUDGET_SECONDS;
  let active=0,peakActive=0,index=0,aborted=false,termination,notes='preparing';
  function checkpoint(complete=false) {
    const expected=[...inventory.readers.map(file=>({file,arm:'rolled'}))];
    const diagnostic=opts.both?inventory.readers:results.filter(r=>r.arm==='rolled'&&r.exitCode!==0).map(r=>r.file);
    expected.push(...diagnostic.map(file=>({file,arm:'ordinary'})));
    const unfinished=r=>!r||r.disposition==='budget-exhausted'||r.disposition==='interrupted';
    const pending=expected.filter(wanted=>unfinished(results.find(r=>r.file===wanted.file&&r.arm===wanted.arm)));
    for(const result of results.filter(r=>r.arm==='rolled'&&r.exitCode!==0)) {
      const base=results.find(r=>r.file===result.file&&r.arm==='ordinary');
      if(unfinished(base))result.differential=aborted?'diagnostic-incomplete':'diagnostic-pending';
      else result.differential=base.exitCode===0?'rollup-only':'baseline-failure';
    }
    const report={
      sourceProof:sourceBefore,sourcePreserved:false,
      readerTimeoutSeconds:opts.timeoutSeconds||DEFAULT_READER_TIMEOUT_SECONDS,budgetSeconds,schedule,
      schema:'aai-release-dry-run-v1',inventory,jobs,peakActive,notes,results,wallSeconds,
      totalSeconds:(performance.now()-start)/1000,complete,termination,pending
    };
    if(opts.report)fs.writeFileSync(opts.report,JSON.stringify(report,null,2)+'\n');
    return report;
  }
  const stop=reason=> {
    aborted=true;
    termination=reason;
    for(const child of children)terminate(child);
    checkpoint();
  };
  const signal=()=>stop('interrupted');
  const budgetTimer=setTimeout(()=>stop('budget-exhausted'),budgetSeconds*1000);
  process.once('SIGTERM',signal);
  process.once('SIGINT',signal);
  checkpoint();
  try {
    const ordinary=path.join(tmp,'ordinary');
    snapshot(opts.root,ordinary);
    const rolled=path.join(tmp,'rolled');
    clone(ordinary,rolled);
    notes='rolled';
    try {
      const f=path.join(rolled,'CHANGELOG.md');
      if(fs.lstatSync(f).isSymbolicLink())throw Error('symlink CHANGELOG is not a regular production release payload');
      const result=rollup(fs.readFileSync(f,'utf8'),'v2099.01.01');
      fs.writeFileSync(f,result.content);
    }
    catch(e) {
      if(e.causeName!=='empty-notes')throw e;
      notes='no-rollable-entries';
    }
    commit(rolled);
    console.log(`release-dry-run: ${notes}; ${inventory.readers.length} reader(s); jobs=${jobs}`);
    async function arm(name,files) {
      const began=performance.now(),wanted=new Set(files),queue=schedule.orderedReaders.filter(file=>wanted.has(file));
      async function worker() {
        for(; ; ) {
          const file=queue.shift();
          if(!file||aborted)return;
          active++;
          peakActive=Math.max(peakActive,active);
          try {
            const result=await execute(file,name,name==='rolled'?rolled:ordinary,tmp,index++,opts.timeoutSeconds||DEFAULT_READER_TIMEOUT_SECONDS);
            if(aborted&&result.exitCode!==0)result.disposition=termination;
            results.push(result);
            checkpoint();
            console.log(`${name} ${file} ${result.disposition} ${result.durationSeconds.toFixed(3)}s`);
            if(result.exitCode!==0)console.log(result.output.split('\n').slice(-24).join('\n'));
          }
          finally {
            active--;
          }
        }
      }
      await Promise.all(Array.from({
        length:Math.min(jobs,files.length)
      },worker));
      wallSeconds[name]=(performance.now()-began)/1000;
    }
    if(opts.both)await arm('ordinary',inventory.readers);
    await arm('rolled',inventory.readers);
    if(!opts.both) {
      const failed=results.filter(v=>v.exitCode!==0).map(v=>v.file);
      if(failed.length&&!aborted)await arm('ordinary',failed);
    }
    clearTimeout(budgetTimer);
    checkpoint(!aborted);
    for(const r of results.filter(v=>v.arm==='rolled'&&v.exitCode!==0))console.log(`${r.file} ${r.differential}`);
    if(termination)console.log(`release-dry-run: ${termination}; partial diagnostic evidence retained`);
    const sourceAfter=sourceProof(opts.root,reportPath);
    if(JSON.stringify(sourceBefore)!==JSON.stringify(sourceAfter))throw Error('source files/index/refs changed during rehearsal');
    const report= {
      ...checkpoint(!aborted),sourcePreserved:true,
      sourceHead:command('git',['rev-parse','HEAD'],opts.root).trim(),machine: {
        platform:process.platform,arch:process.arch,release:os.release(),cpus:os.cpus().length
      },interpreters: {
        node:process.version,bash:spawnSync('bash',['--version'], {
          encoding:'utf8'
        }).stdout?.split('\n')[0],powershell:spawnSync(process.env.AAI_RELEASE_DRY_PWSH||'pwsh',['-NoProfile','-Command',"$PSVersionTable.PSVersion.ToString(); (Get-Module Pester -ListAvailable | Select-Object -First 1).Version.ToString()"], {
          encoding:'utf8'
        }).stdout?.trim()
      },hostedTiming:'unverified — local execution only'
    };
    if(opts.report)fs.writeFileSync(opts.report,JSON.stringify(report,null,2)+'\n');
    console.log(`release-dry-run: ${results.filter(r=>r.exitCode!==0).length} failed / ${results.length} executions; ${report.totalSeconds.toFixed(3)}s`);
    return report;
  }
  finally {
    clearTimeout(budgetTimer);
    for(const child of children)terminate(child);
    process.removeListener('SIGTERM',signal);
    process.removeListener('SIGINT',signal);
    fs.rmSync(tmp, {
      recursive:true,force:true
    });
  }
}
async function main() {
  const opts= {
    root:process.cwd(),jobs:4,timeoutSeconds:DEFAULT_READER_TIMEOUT_SECONDS,budgetSeconds:DEFAULT_BUDGET_SECONDS
  };
  const args=process.argv.slice(2);
  for(let i=0; i<args.length; i++) {
    const a=args[i];
    if(a==='--root')opts.root=path.resolve(args[++i]);
    else if(a==='--list')opts.list=true;
    else if(a==='--both')opts.both=true;
    else if(a==='--report')opts.report=path.resolve(args[++i]);
    else if(a==='--jobs')opts.jobs=Number(args[++i]);
    else if(a==='--timeout-seconds')opts.timeoutSeconds=Number(args[++i]);
    else if(a==='--budget-seconds')opts.budgetSeconds=Number(args[++i]);
    else throw Error(`Unknown argument ${a}`);
  }
  if(!Number.isInteger(opts.jobs)||opts.jobs<1||opts.jobs>16||!Number.isFinite(opts.timeoutSeconds)||opts.timeoutSeconds<=0||!Number.isFinite(opts.budgetSeconds)||opts.budgetSeconds<=0)throw Error('Invalid jobs/timeout bound');
  const report=await dryRun(opts);
  if(report.complete===false||report.results.some(r=>r.exitCode!==0))process.exitCode=1;
}
const realOrResolve=p=> {
  try {
    return fs.realpathSync(p);
  }
  catch {
    return path.resolve(p);
  }
};
if(process.argv[1]&&realOrResolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(e=> {
  console.error(`release-dry-run: ${e.message}`);
  process.exitCode=1;
});
