import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

export function auditWeights(text, names) {
  const rows = new Map();
  for (const line of text.split('\n')) {
    if (!line.trim() || line.startsWith('#')) continue;
    const m = line.match(/^(aai-[A-Za-z0-9_-]+)\s+([1-9][0-9]*)$/);
    assert(m, 'malformed/nonpositive weight row');
    assert(!rows.has(m[1]), 'duplicate weight'); rows.set(m[1], Number(m[2]));
  }
  assert.deepEqual([...rows.keys()].sort(), [...names].sort(), 'stale/missing suite weights');
  const sources = new Map([...text.matchAll(/^# source run ([0-9]+) head SHA ([0-9a-f]{40}) /gm)]
    .map((m) => [m[1], m[2]]));
  assert(sources.size > 0, 'source run SHAs missing');
  for (const name of names) {
    const sample = text.split('\n').find((line) => line.startsWith('# sample ' + name + ' '));
    assert(sample, 'sample classification missing: ' + name);
    if (sample.includes(' fallback unsampled ')) continue;
    const measured = sample.match(/ measured count=([1-9][0-9]*) runs=([0-9,]+) seconds=([0-9.,]+)$/);
    assert(measured, 'invalid measured provenance: ' + name);
    const count = Number(measured[1]);
    const runs = measured[2].split(',');
    const seconds = measured[3].split(',').map(Number).sort((a, b) => a - b);
    assert.equal(runs.length, count); assert.equal(new Set(runs).size, count);
    assert.equal(seconds.length, count);
    for (const run of runs) assert(sources.has(run), 'sample run has no SHA: ' + run);
    assert(seconds.every((n) => Number.isFinite(n) && n >= 0));
    const middle = (seconds[Math.floor((count - 1) / 2)] + seconds[Math.ceil((count - 1) / 2)]) / 2;
    assert.equal(rows.get(name), Math.max(1, Math.round(middle)), 'weight differs from sample median: ' + name);
  }
  const max = Math.max(...[...rows].filter(([n]) => text.includes('# sample '+n+' measured ')).map(([,w])=>w));
  for(const [n,w] of rows) if(text.includes('# sample '+n+' fallback ')) assert.equal(w,max,'fallback must use maximum measured');
  return { suites: rows.size, maximum: max };
}
const median = a => { const b=[...a].sort((x,y)=>x-y); return (b[Math.floor((b.length-1)/2)]+b[Math.ceil((b.length-1)/2)])/2; };
export function checkBenchmark(data) {
  const sharded = data.variant === 'selected-conditional-sharding-v1';
  assert(!data.variant || sharded, 'unknown benchmark variant');
  assert.equal(data.pairs.length,5,'exactly five pairs required');
  assert(data.hardware && data.runtime && data.base_sha && data.candidate_base_sha,'environment identity required');
  assert(data.membership.length>0); assert.equal(new Set(data.membership).size,data.membership.length);
  const sides={baseline:[],after:[]};
  for(let i=0;i<5;i++) for(const side of Object.keys(sides)) {
    if (sharded) assert.equal(data.pairs[i].pair,i+1,'distinct ordered pair IDs required');
    const row=data.pairs[i][side]; assert(row, 'paired record missing');
    assert.equal(row.hardware,data.hardware); assert.equal(row.runtime,data.runtime);
    assert.deepEqual([...row.membership].sort(),[...data.membership].sort());
    assert.deepEqual([...row.order].sort(),[...data.membership].sort());
    assert.equal(row.runners,sharded && side==='after' ? 2 : 1); assert.equal(row.workers,4); assert.equal(row.exit_code,0);
    if (sharded) {
      assert.equal(row.legs.length,row.runners,'one actual record per runner');
      assert.deepEqual(row.legs.map(l=>l.id),Array.from({length:row.runners},(_,i)=>i+1));
      assert.deepEqual(row.legs.flatMap(l=>l.membership).sort(),[...data.membership].sort(),'leg membership differs');
      let seconds=0;
      for (const leg of row.legs) {
        assert(leg.membership.length>0); assert.equal(leg.exit_code,0); assert.equal(leg.workers,4,'four workers per runner');
        assert(Number.isFinite(leg.wall_seconds)&&leg.wall_seconds>0);
        assert(typeof leg.log==='string' && leg.log.length>0,'raw leg log required');
        seconds+=leg.wall_seconds;
      }
      assert(Math.abs(row.runner_seconds-seconds)<1e-6,'bad runner-second arithmetic');
      assert(row.wall_seconds+0.001>=Math.max(...row.legs.map(l=>l.wall_seconds)),'wall shorter than a runner');
      assert.equal(row.skip_count,row.outcomes.filter(x=>x.verdict==='SKIP').length,'hidden skips');
      for(const outcome of row.outcomes) assert.equal(outcome.exit_code,outcome.verdict==='SKIP'?42:0,'outcome exit differs');
    }
    assert(Number.isFinite(row.wall_seconds)&&row.wall_seconds>0);
    assert.equal(row.outcomes.length,data.membership.length);
    assert.deepEqual(row.outcomes.map(x=>x.suite).sort(),[...data.membership].sort());
    for(const x of row.outcomes) {assert(['PASS','SKIP'].includes(x.verdict));if(x.verdict==='SKIP') assert(x.skip_reason);}
    for(const c of ['fixture','startup','execution','cleanup']) assert(row.components[c]==='unavailable'||(Number.isFinite(row.components[c])&&row.components[c]>=0));
    sides[side].push(row.wall_seconds);
  }
  const result={sample_count:5};
  for(const [side,values] of Object.entries(sides)) result[side]={median:median(values),worst:Math.max(...values),runner_seconds:sharded ? data.pairs.reduce((sum,pair)=>sum+pair[side].runner_seconds,0) : values.reduce((a,b)=>a+b,0)};
  result.speedup_percent=100*(result.baseline.median-result.after.median)/result.baseline.median;
  if (sharded) {
    assert(/^[a-f0-9]{40}$/.test(data.base_sha) && data.candidate_base_sha===data.base_sha,'fixed benchmark checkout required');
    assert(data.membership.length>=8,'eligible workload requires at least eight suites');
    assert(data.policy && data.policy.runners===2 && data.policy.w1>=120 && data.policy.w1-data.policy.w2>=30 &&
      data.policy.w2<=0.8*data.policy.w1 && data.policy.r2<=1.25*data.policy.r1,'modeled eligible policy required');
    result.runner_cost_change_percent=100*(result.after.runner_seconds-result.baseline.runner_seconds)/result.baseline.runner_seconds;
    result.runner_budget_overrun=result.after.runner_seconds>1.25*result.baseline.runner_seconds;
    result.slowed_pairs=data.pairs.map((p,i)=>p.after.wall_seconds>p.baseline.wall_seconds?i+1:null).filter(Boolean);
    if(data.summary) assert.deepEqual(data.summary,result,'bad summary arithmetic');
  }
  return result;
}
if(process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    if(process.argv[2]==='--weights-audit') {
      const root=resolve(process.argv[3]||'.');
      const names=readdirSync(root+'/tests/skills',{withFileTypes:true}).filter(e=>e.isFile()&&/^test-aai-.*\.sh$/.test(e.name)).map(e=>e.name.slice(5,-3));
      console.log(JSON.stringify(auditWeights(readFileSync(root+'/tests/skills/suite-weights.tsv','utf8'),names)));
    } else console.log(JSON.stringify(checkBenchmark(JSON.parse(readFileSync(process.argv[2],'utf8'))),null,2));
  } catch(e) { console.error(e.message); process.exitCode=1; }
}
