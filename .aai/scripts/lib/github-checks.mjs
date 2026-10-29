// Current-head observations shared by watch-ci and release required-check reads.
// Use complete API pages and creation/start identity, never response order or
// conclusion preference. The PR head is read on both sides of the observation.
// Same-name checks from different apps stay distinct; required names that map
// to more than one app refuse closed instead of picking the wrong provider.
// A run whose run-level conclusion is cancelled is superseded by a newer run of
// the same workflow and event on the head (concurrency cancel-in-progress): its
// checks are pending while the sibling runs, dropped once it completed.
import {spawnSync} from 'node:child_process';
const sha=s=>/^(?:[a-f0-9]{40}|[a-f0-9]{64})$/.test(s||'');
function fail(message) {
  throw Error(`github-checks: ${message}`);
}
function bucket(status,conclusion) {
  if(status!=='completed') {
    if(['queued','in_progress','waiting','requested','pending'].includes(status))return 'pending';
    fail(`unknown check status ${status}`);
  }
  const map= {
    success:'pass',neutral:'skipping',skipped:'skipping',failure:'fail',timed_out:'fail',action_required:'fail',startup_failure:'fail',cancelled:'cancel',stale:'fail'
  };
  if(!(conclusion in map))fail(`unknown check conclusion ${conclusion}`);
  return map[conclusion];
}
function newer(a,b) {
  for(let i=0;i<a.order.length;i++) {
    if(a.order[i]!==b.order[i])return a.order[i] > b.order[i];
  }
  return false;
}
function providerKey(c,kind) {
  if(kind==='status')return 'legacy-status';
  const app=c?.app;
  if(app&&typeof app==='object') {
    if(Number.isSafeInteger(app.id)&&app.id>0)return `app:${app.id}`;
    if(typeof app.slug==='string'&&app.slug)return `app:${app.slug}`;
    if(typeof app.name==='string'&&app.name)return `app:${app.name}`;
  }
  return 'app:none';
}
export function readCurrentChecks({
  pr,repo,expectedHead,required=false,cwd=process.cwd(),run
}
= {
}) {
  const invoke=run||((args)=>spawnSync('gh',args, {
    cwd,encoding:'utf8',timeout:60000,maxBuffer:32*1024*1024
  }));
  function raw(args,allowed=[0]) {
    const r=invoke(args);
    if(r.error||!allowed.includes(r.status))fail(`transport ${args.join(' ')}: ${r.error?.message||r.stderr||`exit ${r.status}`}`);
    return r;
  }
  function json(args) {
    const r=raw(args);
    try {
      return JSON.parse(r.stdout);
    }
    catch {
      fail(`invalid JSON: ${args.join(' ')}`);
    }
  }
  const view=['pr','view',...(pr===undefined?[]:[String(pr)]),...(repo?['--repo',repo]:[]),'--json','headRefOid,url,number'];
  const before=json(view);
  if(!sha(before?.headRefOid))fail('missing PR head identity');
  const head=before.headRefOid;
  if(expectedHead&&head!==expectedHead)fail('head-SHA mismatch with release journal');
  const match=/^https:\/\/github\.com\/([\w.-]+\/[\w.-]+)\/pull\/(\d+)$/.exec(before.url||'');
  if(!match || repo&&repo!==match[1] || !Number.isSafeInteger(before.number) || before.number<1 || String(before.number)!==match[2] || /^\d+$/.test(String(pr))&&Number(pr)!==before.number)fail('missing or inconsistent repository/PR identity');
  repo=match[1];
  let names=null;
  if(required) {
    const args=['pr','checks',String(before.number||pr),'--repo',repo,'--required','--json','name,bucket,link'];
    const r=raw(args,[0,1,8]);
    let list;
    if(r.status===1&&!r.stdout.trim()&&/^no (required )?checks reported on the '[^']*' branch$/.test((r.stderr||'').trim()))list=[];
    else try {
      list=JSON.parse(r.stdout);
    }
    catch {
      fail('invalid JSON from required-check reader');
    }
    if(!Array.isArray(list)||list.some(c=>!c||typeof c.name!=='string'||!c.name||!['pass','fail','cancel','pending','skipping'].includes(c.bucket)))fail('malformed required checks');
    if(r.status===8&&!list.some(c=>c.bucket==='pending')||r.status===1&&list.length&&!list.some(c=>['fail','cancel'].includes(c.bucket)))fail('inconsistent required-check exit status');
    names=new Set(list.map(c=>c.name));
  }
  const workflows=new Map();
  let observations=[];
  const readCheckRuns=()=>{
    const pages=json(['api','--paginate','--slurp',`repos/${repo}/commits/${head}/check-runs?filter=all&per_page=100`]);
    if(!Array.isArray(pages)||!pages.length||pages.some(p=>!p||!Number.isSafeInteger(p.total_count)||!Array.isArray(p.check_runs)))fail('malformed check-run pages');
    const runs=pages.flatMap(p=>p.check_runs),total=pages[0].total_count;
    if(pages.some(p=>p.total_count!==total)||runs.length!==total)fail('incomplete or moving check-run pagination');
    observations=[];
    const seenRunIds=new Set();
    for(const c of runs) {
      if(seenRunIds.has(c.id))fail('duplicate check-run identity across pages');
      seenRunIds.add(c.id);
      if(c.head_sha!==head)fail(`head-SHA mismatch: ${c.name||'(unnamed)'}`);
      if(typeof c.name!=='string'||!c.name||!Number.isSafeInteger(c.id)||c.id<=0)fail('malformed check-run identity');
      // Every Actions job uses the SAME immutable workflow creation identity.
      // Job start time can be later in an older workflow, and queued jobs lack
      // a start time. Mixing those clocks makes pairwise ordering nontransitive.
      const runMatch=new RegExp(`^https://github\\.com/${repo}/actions/runs/(\\d+)(?:/|$)`).exec(c.details_url||c.html_url||'');
      let time,runId=0,orderKind='check';
      if(runMatch) {
        runId=Number(runMatch[1]);
        if(!Number.isSafeInteger(runId)||runId<1)fail(`malformed workflow identity: ${c.name}`);
        if(!workflows.has(runId)) {
          const workflow=json(['api',`repos/${repo}/actions/runs/${runId}`]);
          if(workflow?.head_sha!==head || workflow.id!==undefined&&workflow.id!==runId)fail(`workflow identity/head-SHA mismatch: ${c.name}`);
          const created=Date.parse(workflow.created_at||'');
          if(!Number.isFinite(created))fail(`missing workflow creation identity: ${c.name}`);
          workflows.set(runId, {
            created,workflowId:workflow.workflow_id,event:workflow.event,status:workflow.status,conclusion:workflow.conclusion
          });
        }
        time=workflows.get(runId).created;
        orderKind='workflow';
      } else time=Date.parse(c.started_at||c.created_at||'');
      if(!Number.isFinite(time))fail(`missing check-run ordering identity: ${c.name}`);
      const provider=providerKey(c,'check');
      observations.push({
        name:c.name,provider,bucket:(()=> {
          try {
            return bucket(c.status,c.conclusion);
          }
          catch(e) {
            fail(`${c.name}: ${e.message}`);
          }
        })(),link:c.details_url||c.html_url||'',id:c.id,order:[time,runId,c.id],orderKind,kind:'check'
      });
    }
  };
  readCheckRuns();
  const cancelledRuns=[...workflows].filter(([,w])=>w.conclusion==='cancelled');
  if(cancelledRuns.length) {
    for(const [,w] of cancelledRuns) {
      if(!Number.isSafeInteger(w.workflowId)||w.workflowId<1||typeof w.event!=='string'||!w.event)fail('malformed cancelled workflow identity');
    }
    const runPages=json(['api','--paginate','--slurp',`repos/${repo}/actions/runs?head_sha=${head}&per_page=100`]);
    if(!Array.isArray(runPages)||!runPages.length||runPages.some(p=>!p||!Number.isSafeInteger(p.total_count)||!Array.isArray(p.workflow_runs)))fail('malformed workflow-run pages');
    const listed=runPages.flatMap(p=>p.workflow_runs),listedTotal=runPages[0].total_count;
    if(runPages.some(p=>p.total_count!==listedTotal)||listed.length!==listedTotal)fail('incomplete or moving workflow-run pagination');
    const listedIds=new Set();
    for(const w of listed) {
      if(!w||!Number.isSafeInteger(w.id)||w.id<1)fail('malformed workflow-run identity');
      if(listedIds.has(w.id))fail('duplicate workflow-run identity across pages');
      listedIds.add(w.id);
      if(w.head_sha!==head)fail(`workflow-run head-SHA mismatch: ${w.id}`);
      if(!Number.isFinite(Date.parse(w.created_at||''))||!Number.isSafeInteger(w.workflow_id)||w.workflow_id<1||typeof w.event!=='string'||!w.event||typeof w.status!=='string')fail(`malformed workflow-run identity: ${w.id}`);
    }
    const after=(a,b)=>{
      const ta=Date.parse(a.created_at),tb=Date.parse(b.created_at);
      return ta!==tb?ta>tb:a.id>b.id;
    };
    // Snapshot skew: a sibling that completed after the first check-run read
    // may have registered (and failed) its checks since. Re-read the check
    // runs AFTER the run list so a completed sibling's checks are always
    // visible before supersession decides anything.
    readCheckRuns();
    for(const [id,w] of workflows)if(w.conclusion==='cancelled'&&!cancelledRuns.some(([r])=>r===id))fail('workflow state moved during observation');
    const drop=new Set();
    for(const [runId,w] of cancelledRuns) {
      const self= {
        id:runId,created_at:new Date(w.created).toISOString()
      };
      let newest=null;
      for(const sibling of listed) {
        const same=sibling.workflow_id===w.workflowId&&w.event===sibling.event;
        if(sibling.id===runId||!same||!after(sibling,self))continue;
        if(!newest||after(sibling,newest))newest=sibling;
      }
      if(!newest)continue;
      const sibling=newest;
      const siblingTime=Date.parse(sibling.created_at);
      for(let i=0;i<observations.length;i++) {
        const o=observations[i];
        if(o.kind!=='check'||o.order[1]!==runId)continue;
        if(observations.some(x=>x.kind==='check'&&x.order[1]===sibling.id&&x.name===o.name&&x.provider===o.provider))continue;
        if(sibling.status!=='completed')observations[i]= {
          ...o,bucket:'pending',link:sibling.html_url||o.link,order:[siblingTime,sibling.id,0]
        };
        else drop.add(o);
      }
    }
    if(drop.size)observations.splice(0,observations.length,...observations.filter(o=>!drop.has(o)));
  }
  const statusPages=json(['api','--paginate','--slurp',`repos/${repo}/commits/${head}/statuses?per_page=100`]);
  if(!Array.isArray(statusPages)||!statusPages.length||statusPages.some(p=>!Array.isArray(p)))fail('malformed status pages');
  const seenStatusIds=new Set();
  for(const c of statusPages.flat()) {
    if(seenStatusIds.has(c.id))fail('duplicate legacy status identity across pages');
    seenStatusIds.add(c.id);
    if(c.sha!==undefined&&c.sha!==head)fail(`head-SHA mismatch: ${c.context}`);
    const time=Date.parse(c.created_at||'');
    if(!c.context||!Number.isSafeInteger(c.id)||c.id<1||!Number.isFinite(time)||!['success','failure','error','pending'].includes(c.state))fail('malformed legacy status identity');
    observations.push({
      name:c.context,provider:providerKey(c,'status'),bucket: {
        success:'pass',failure:'fail',error:'fail',pending:'pending'
      }
      [c.state],link:c.target_url||'',id:c.id,order:[time,0,c.id],orderKind:'status',kind:'status'
    });
  }
  const latest=new Map();
  for(const c of observations) {
    const key=`${c.name}\0${c.provider}`;
    const old=latest.get(key);
    if(old&&old.kind!==c.kind)fail(`ambiguous check and status context: ${c.name}`);
    if(old&&c.id===old.id&&JSON.stringify(c)!==JSON.stringify(old))fail(`ambiguous duplicate check identity: ${c.name}`);
    if(old&&old.orderKind!==c.orderKind)fail(`ambiguous ordering identities: ${c.name}`);
    if(!old||newer(c,old))latest.set(key,c);
  }
  const after=json(view);
  if(after?.headRefOid!==head||after?.url!==before.url||after?.number!==before.number)fail('PR head changed during observation');
  const byName=new Map();
  for(const c of latest.values()) {
    const group=byName.get(c.name)||[];
    group.push(c);
    byName.set(c.name,group);
  }
  const selected=[];
  const wanted=names?names:new Set(byName.keys());
  for(const name of wanted) {
    const group=byName.get(name)||[];
    if(!group.length)fail(`required context missing from current head: ${name}`);
    const providers=new Set(group.map(c=>c.provider));
    if(providers.size>1)fail(`ambiguous check name across apps: ${name}`);
    selected.push(group[0]);
  }
  const checks=selected.map(({
    name,bucket,link,id,provider
  })=>({
    name,bucket,link,id,head,provider
  }));
  return {
    head,checks
  };
}
