import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const head = 'a'.repeat(40);

function run(exe, args, cwd, env = {}) {
  const childEnv = {...process.env, AAI_GIT_WRITE: '1', ...env};
  delete childEnv.NODE_TEST_CONTEXT;
  return spawnSync(exe, args, {
    cwd, encoding: 'utf8', env: childEnv, timeout: 120000, maxBuffer: 8 * 1024 * 1024
  });
}

function git(dir, ...args) {
  const r = run('git', args, dir);
  assert.equal(r.status, 0, r.stderr);
  return r.stdout;
}

function put(dir, file, text) {
  fs.mkdirSync(path.dirname(path.join(dir, file)), {recursive: true});
  fs.writeFileSync(path.join(dir, file), text);
}

function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'aai-current-head-ci-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  git(dir, 'init', '-b', 'main');
  git(dir, 'config', 'user.email', 'fixture@example.invalid');
  git(dir, 'config', 'user.name', 'Fixture');
  put(dir, 'README.md', 'fixture\n');
  git(dir, 'add', '.');
  git(dir, 'commit', '-m', 'fixture');
  return dir;
}

function checkRun(id, conclusion = 'success', sha = head, app = {id: 1, slug: 'github-actions'}) {
  return {
    id,
    name: 'aggregate',
    head_sha: sha,
    status: conclusion === 'pending' ? 'in_progress' : 'completed',
    conclusion: conclusion === 'pending' ? null : conclusion,
    started_at: `2026-10-27T00:00:${String(id).padStart(2, '0')}Z`,
    details_url: `https://github.com/test/repo/actions/runs/${id}/job/${id}`,
    app
  };
}

function transport(t, checks, opts = {}) {
  const dir = fixture(t);
  const bin = path.join(dir, 'bin');
  fs.mkdirSync(bin);
  git(dir, 'remote', 'add', 'origin', 'https://github.com/test/repo.git');
  const data = {head, checks, ...opts};
  put(dir, 'transport.json', JSON.stringify(data));
  put(dir, 'bin/gh', `#!/usr/bin/env node
const fs=require('fs'),p=${JSON.stringify(path.join(dir, 'transport.json'))},d=JSON.parse(fs.readFileSync(p)),a=process.argv.slice(2);fs.appendFileSync(${JSON.stringify(path.join(dir, 'calls.jsonl'))},JSON.stringify(a)+'\\n');const out=x=>console.log(JSON.stringify(x));if(a[0]==='--version'){console.log('fixture gh');process.exit(0);}if(a[0]==='pr'&&a[1]==='view'){d.views=(d.views||0)+1;fs.writeFileSync(p,JSON.stringify(d));out({headRefOid:d.move&&d.views>1?'b'.repeat(40):d.head,url:'https://github.com/test/repo/pull/1',number:d.number??1});}else if(a[0]==='pr'&&a[1]==='checks'){if(d.transportFail){console.error('fixture network error');process.exit(42);}out(d.required||[{name:'aggregate',bucket:'pass',link:'x'}]);}else if(a[0]==='api'&&a.some(x=>x.includes('/check-runs'))){if(d.transportFail){console.error('fixture network error');process.exit(42);}if(d.checkSeq){d.crn=(d.crn||0)+1;fs.writeFileSync(p,JSON.stringify(d));const c=d.checkSeq[Math.min(d.crn,d.checkSeq.length)-1];out([{total_count:c.length,check_runs:c}]);}else out(d.malformed?{}:(d.pages||[{total_count:d.checks.length,check_runs:d.checks}]));}else if(a[0]==='api'&&a.some(x=>x.includes('/actions/runs?head_sha='))){if(!d.runPages&&!d.runList){console.error('unexpected run list');process.exit(91);}out(d.runPages||[{total_count:d.runList.length,workflow_runs:d.runList}]);}else if(a[0]==='api'&&a.some(x=>x.includes('/actions/runs/'))){const id=Number(a.find(x=>x.includes('/actions/runs/')).split('/').pop());out(d.workflows?.[id]||d.workflow||{id,head_sha:d.head,created_at:new Date(Date.UTC(2026,9,27,0,0,id)).toISOString()});}else if(a[0]==='api'&&a.some(x=>x.includes('/statuses'))){out(d.statusPages||[[]]);}else{console.error('unexpected '+a.join(' '));process.exit(90);}`);
  fs.chmodSync(path.join(bin, 'gh'), 0o755);
  return {
    dir,
    env: {PATH: bin + path.delimiter + process.env.PATH},
    data: path.join(dir, 'transport.json')
  };
}

function watcher(f, required = false) {
  return run(process.execPath, [
    path.join(root, '.aai/scripts/watch-ci.mjs'),
    '--pr', '1',
    ...(required ? ['--required'] : []),
    '--interval-seconds', '0.01',
    '--max-wait-seconds', '0.03'
  ], f.dir, f.env);
}

function releaseReader(f, expected = head) {
  return run(process.execPath, [
    '--input-type=module',
    '-e',
    `import {readReleaseRequiredChecks} from ${JSON.stringify('file://' + path.join(root, '.aai/scripts/release-finish.mjs'))};try{console.log(JSON.stringify(readReleaseRequiredChecks({pr:1,repo:'test/repo',head:${JSON.stringify(expected)},cwd:${JSON.stringify(f.dir)}})));}catch(e){console.error(e.message);process.exit(20);}`
  ], f.dir, f.env);
}

test('TEST-001 watch and release select newer pending/success over failed cancelled run', t => {
  for (const conclusion of ['success', 'pending']) {
    const f = transport(t, [checkRun(2, conclusion), checkRun(1, 'cancelled')]);
    let r = watcher(f, true);
    assert.equal(r.status, conclusion === 'success' ? 0 : 3, r.stdout + r.stderr);
    if (conclusion === 'pending') assert.match(r.stdout + r.stderr, /pending/);
    r = releaseReader(f);
    assert.equal(r.status, 0, r.stderr);
    const checks = JSON.parse(r.stdout);
    assert.equal(checks.length, 1);
    assert.equal(checks[0].bucket, conclusion === 'success' ? 'pass' : 'pending');
  }
});

test('TEST-001 queued rerun without started_at still supersedes old failure', t => {
  const queued = {...checkRun(3, 'pending'), started_at: null, details_url: 'https://github.com/test/repo/actions/runs/7/job/3'};
  const older = {...checkRun(2, 'failure'), details_url: 'https://github.com/test/repo/actions/runs/7/job/2'};
  const f = transport(t, [older, queued], {workflow: {head_sha: head, created_at: '2026-10-27T00:00:00Z'}});
  const watched = watcher(f, true);
  assert.equal(watched.status, 3, watched.stdout + watched.stderr);
  assert.match(watched.stdout + watched.stderr, /pending/);
  const released = releaseReader(f);
  assert.equal(released.status, 0, released.stderr);
  assert.equal(JSON.parse(released.stdout)[0].bucket, 'pending');
});

test('TEST-002 failures mixed heads paging required filters and malformed transport fail closed', t => {
  let f = transport(t, [checkRun(2, 'failure'), checkRun(1)]);
  assert.equal(watcher(f).status, 5);
  assert.equal(JSON.parse(releaseReader(f).stdout)[0].bucket, 'fail');
  f = transport(t, [checkRun(1), checkRun(2, 'success', 'b'.repeat(40))]);
  assert.notEqual(watcher(f).status, 0);
  assert.notEqual(releaseReader(f).status, 0);
  f = transport(t, [checkRun(1)], {move: true});
  assert.notEqual(watcher(f).status, 0);
  f = transport(t, [], {
    pages: [
      {total_count: 2, check_runs: [checkRun(1, 'failure')]},
      {total_count: 2, check_runs: [checkRun(2)]}
    ]
  });
  assert.equal(watcher(f).status, 0);
  assert.equal(releaseReader(f).status, 0);
  const calls = fs.readFileSync(path.join(f.dir, 'calls.jsonl'), 'utf8');
  assert.match(calls, /--paginate/);
  assert.match(calls, /--slurp/);
  f = transport(t, [checkRun(1), {...checkRun(2, 'failure'), name: 'optional'}]);
  assert.equal(watcher(f, true).status, 0);
  assert.equal(watcher(f).status, 5);
  for (const opts of [
    {malformed: true},
    {transportFail: true},
    {pages: [{total_count: 2, check_runs: [checkRun(1)]}]},
    {workflow: {head_sha: head, created_at: null}}
  ]) {
    f = transport(t, [checkRun(1)], opts);
    assert.notEqual(watcher(f).status, 0);
    assert.notEqual(releaseReader(f).status, 0);
  }
  f = transport(t, [checkRun(1)]);
  assert.notEqual(releaseReader(f, 'b'.repeat(40)).status, 0);
  f = transport(t, [], {
    required: [{name: 'legacy', bucket: 'pass'}],
    statusPages: [[
      {id: 2, context: 'legacy', state: 'success', sha: head, created_at: '2026-10-27T00:00:02Z', target_url: 'https://example.invalid'}
    ], [
      {id: 1, context: 'legacy', state: 'failure', sha: head, created_at: '2026-10-27T00:00:01Z'}
    ]]
  });
  assert.equal(watcher(f, true).status, 0);
});

test('TEST-002 refuses repeated pagination and inconsistent PR identity', t => {
  for (const options of [
    {pages: [{total_count: 2, check_runs: [checkRun(1)]}, {total_count: 2, check_runs: [checkRun(1)]}]},
    {number: 2},
    {statusPages: [[{id: 1, context: 'legacy', state: 'success', created_at: '2026-10-27T00:00:00Z'}], [{id: 1, context: 'legacy', state: 'success', created_at: '2026-10-27T00:00:00Z'}]]}
  ]) {
    const f = transport(t, [checkRun(1)], options);
    assert.notEqual(watcher(f).status, 0);
    assert.notEqual(releaseReader(f).status, 0);
  }
});

test('TEST-002 one authoritative ordering is invariant across every response permutation', t => {
  const checks = [
    {...checkRun(3, 'pending'), started_at: null, details_url: 'https://github.com/test/repo/actions/runs/1/job/3'},
    {...checkRun(2), started_at: '2026-10-27T10:00:10Z', details_url: 'https://github.com/test/repo/actions/runs/1/job/2'},
    {...checkRun(4, 'failure'), started_at: '2026-10-27T10:00:05Z', details_url: 'https://github.com/test/repo/actions/runs/2/job/4'}
  ];
  const workflows = {
    1: {id: 1, head_sha: head, created_at: '2026-10-27T10:00:01Z'},
    2: {id: 2, head_sha: head, created_at: '2026-10-27T10:00:02Z'}
  };
  for (const order of [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]) {
    const f = transport(t, order.map(i => checks[i]), {workflows});
    const watched = watcher(f, true);
    assert.equal(watched.status, 5, watched.stdout + watched.stderr);
    const released = releaseReader(f);
    assert.equal(released.status, 0, released.stderr);
    const selected = JSON.parse(released.stdout)[0];
    assert.equal(selected.id, 4);
    assert.equal(selected.bucket, 'fail');
  }
  const queued = {...checkRun(200, 'pending'), started_at: null, details_url: 'https://github.com/test/repo/actions/runs/200/job/200'};
  const lateOld = {...checkRun(100, 'failure'), started_at: '2026-10-27T10:05:00Z', details_url: 'https://github.com/test/repo/actions/runs/100/job/100'};
  const created = {
    100: {id: 100, head_sha: head, created_at: '2026-10-27T10:00:00Z'},
    200: {id: 200, head_sha: head, created_at: '2026-10-27T10:04:00Z'}
  };
  for (const rows of [[lateOld, queued], [queued, lateOld]]) {
    const f = transport(t, rows, {workflows: created});
    const watched = watcher(f, true);
    assert.equal(watched.status, 3, watched.stdout + watched.stderr);
    assert.match(watched.stdout + watched.stderr, /pending/);
    const released = releaseReader(f);
    assert.equal(released.status, 0, released.stderr);
    assert.equal(JSON.parse(released.stdout)[0].id, 200);
  }
});

test('TEST-002 refuses same-name checks from different apps instead of picking the newer foreign provider', t => {
  const requiredApp = checkRun(1, 'failure', head, {id: 10, slug: 'required-app'});
  const foreignNewer = checkRun(2, 'success', head, {id: 20, slug: 'foreign-app'});
  foreignNewer.details_url = 'https://github.com/test/repo/actions/runs/2/job/2';
  const f = transport(t, [requiredApp, foreignNewer], {
    required: [{name: 'aggregate', bucket: 'pass'}]
  });
  assert.notEqual(watcher(f, true).status, 0);
  assert.notEqual(releaseReader(f).status, 0);
  const err = releaseReader(f).stderr + releaseReader(f).stdout;
  assert.match(err, /ambiguous check name across apps/);
});

test('TEST-003 captured historical current-head reruns from PR 504', t => {
  const history = JSON.parse(fs.readFileSync(path.join(root, 'tests/fixtures/release-first-pr504.json')));
  assert.match(history.provenance.url, /pull\/504/);
  assert.equal(history.checks.length, 2);
  const f = transport(t, history.checks, {
    head: history.head,
    required: [{name: history.checks[0].name, bucket: 'pass'}]
  });
  assert.equal(watcher(f, true).status, 0);
  assert.equal(releaseReader(f, history.head).status, 0);
});

test('TEST-004 profile suite ownership product and release notes for current-head reader', () => {
  const profiles = fs.readFileSync(path.join(root, '.aai/system/PROFILES.yaml'), 'utf8');
  const map = fs.readFileSync(path.join(root, 'tests/skills/suite-map.yaml'), 'utf8');
  for (const f of ['.aai/scripts/lib/github-checks.mjs', '.aai/scripts/lib/release-rollup.mjs']) {
    assert.equal(profiles.split(f).length - 1, 1, f);
    assert.ok(map.includes(f), f);
  }
  assert.match(map, /  aai-current-head-ci:/);
  const product = fs.readFileSync(path.join(root, 'docs/product/release-command-finish.md'), 'utf8');
  assert.match(product, /newest/);
  assert.match(fs.readFileSync(path.join(root, 'CHANGELOG.md'), 'utf8'), /current(?: |-)?head|newest run/i);
});

const CANCEL_ID = 10;
const SIBLING_ID = 20;
const WF = 5;

function jobCheck(id, runId, conclusion, name = 'aggregate') {
  return {
    ...checkRun(id, conclusion),
    name,
    started_at: `2026-10-27T00:00:${String(id).padStart(2, '0')}Z`,
    details_url: `https://github.com/test/repo/actions/runs/${runId}/job/${id}`
  };
}

function runObj(id, over = {}) {
  return {
    id,
    head_sha: head,
    workflow_id: WF,
    event: 'pull_request',
    status: 'completed',
    conclusion: 'success',
    created_at: `2026-10-27T00:00:${String(id).padStart(2, '0')}Z`,
    html_url: `https://github.com/test/repo/actions/runs/${id}`,
    ...over
  };
}

function runFixture(t, checks, runs, opts = {}) {
  const workflows = {};
  for (const r of runs) workflows[r.id] = r;
  return transport(t, checks, {workflows, runList: runs, ...opts});
}

function rewrite(f, patch) {
  const d = JSON.parse(fs.readFileSync(f.data, 'utf8'));
  fs.writeFileSync(f.data, JSON.stringify({...d, ...patch}));
}

function callLog(f) {
  const p = path.join(f.dir, 'calls.jsonl');
  return fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : '';
}

function releaseBucket(f) {
  const r = releaseReader(f);
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
}

test('TEST-2701 superseded cancelled run stays pending until the newer run registers the check', t => {
  const cancelled = runObj(CANCEL_ID, {conclusion: 'cancelled'});
  const sibling = runObj(SIBLING_ID, {status: 'in_progress', conclusion: null});
  const f = runFixture(t, [jobCheck(1, CANCEL_ID, 'failure')], [cancelled, sibling]);
  let w = watcher(f, true);
  assert.equal(w.status, 3, w.stdout + w.stderr);
  assert.match(w.stdout + w.stderr, /pending/);
  const rel = releaseBucket(f);
  assert.equal(rel.length, 1);
  assert.equal(rel[0].bucket, 'pending');
  assert.match(callLog(f), /actions\/runs\?head_sha=/);
  rewrite(f, {
    checks: [jobCheck(1, CANCEL_ID, 'failure'), jobCheck(2, SIBLING_ID, 'success')],
    runList: [cancelled, runObj(SIBLING_ID)],
    workflows: {[CANCEL_ID]: cancelled, [SIBLING_ID]: runObj(SIBLING_ID)}
  });
  w = watcher(f, true);
  assert.equal(w.status, 0, w.stdout + w.stderr);
  assert.equal(releaseBucket(f)[0].bucket, 'pass');
});

test('TEST-2702 replay of PR 515 never reports the cancelled run as failed', t => {
  // Only the repository slug is retargeted to the stub repo; run, job and check identities stay as captured.
  const fx = JSON.parse(fs.readFileSync(path.join(root, 'tests/fixtures/watch-ci-pr515.json'), 'utf8').split('goodwind-cz/aai/actions').join('test/repo/actions'));
  assert.match(fx.provenance.url, /pull\/515/);
  assert.equal(fx.phases.length, 2);
  const names = fx.required.map(c => c.name);
  const f = transport(t, fx.phases[0].checks, {
    head: fx.head,
    required: fx.required,
    workflows: fx.phases[0].workflows,
    runList: fx.phases[0].runList
  });
  let w = watcher(f, true);
  assert.equal(w.status, 3, w.stdout + w.stderr);
  assert.match(w.stdout + w.stderr, /pending/);
  let rel = JSON.parse(run(process.execPath, [
    '--input-type=module', '-e',
    `import {readCurrentChecks} from ${JSON.stringify('file://' + path.join(root, '.aai/scripts/lib/github-checks.mjs'))};console.log(JSON.stringify(readCurrentChecks({pr:1,repo:'test/repo',required:true,cwd:${JSON.stringify(f.dir)}}).checks));`
  ], f.dir, f.env).stdout);
  assert.deepEqual(rel.map(c => c.name).sort(), [...names].sort());
  for (const c of rel) assert.equal(c.bucket, /^doc-numbering/.test(c.name) ? 'pass' : 'pending', c.name);
  rewrite(f, {
    checks: fx.phases[1].checks,
    workflows: fx.phases[1].workflows,
    runList: fx.phases[1].runList
  });
  w = watcher(f, true);
  assert.equal(w.status, 0, w.stdout + w.stderr);
});

test('TEST-2703 cancelled run keeps its own bucket without a same-workflow same-event newer sibling', t => {
  const cancelled = runObj(CANCEL_ID, {conclusion: 'cancelled'});
  const arms = [
    ['no sibling', [jobCheck(1, CANCEL_ID, 'failure')], [cancelled]],
    ['newer run of another event', [jobCheck(1, CANCEL_ID, 'failure')], [cancelled, runObj(SIBLING_ID, {event: 'push', status: 'in_progress', conclusion: null})]],
    ['newer run of another workflow', [jobCheck(1, CANCEL_ID, 'failure')], [cancelled, runObj(SIBLING_ID, {workflow_id: 99, status: 'in_progress', conclusion: null})]],
    ['older run failed, in-progress sibling', [jobCheck(1, CANCEL_ID, 'failure')], [runObj(CANCEL_ID, {conclusion: 'failure'}), runObj(SIBLING_ID, {status: 'in_progress', conclusion: null})]]
  ];
  for (const [label, checks, runs] of arms) {
    const f = runFixture(t, checks, runs);
    const w = watcher(f, true);
    assert.equal(w.status, 5, `${label}: ${w.stdout}${w.stderr}`);
    assert.match(w.stdout + w.stderr, /aggregate/, label);
    assert.ok(['fail', 'cancel'].includes(releaseBucket(f)[0].bucket), label);
  }
});

test('TEST-2704 malformed or contradictory workflow-run list refuses closed', t => {
  const cancelled = runObj(CANCEL_ID, {conclusion: 'cancelled'});
  const sibling = runObj(SIBLING_ID, {status: 'in_progress', conclusion: null});
  const checks = [jobCheck(1, CANCEL_ID, 'failure')];
  const arms = {
    malformed: {runPages: {}},
    'short pagination': {runPages: [{total_count: 3, workflow_runs: [cancelled, sibling]}]},
    'repeated run id': {runPages: [{total_count: 3, workflow_runs: [cancelled, sibling]}, {total_count: 3, workflow_runs: [sibling]}]},
    'run for another head': {runPages: [{total_count: 2, workflow_runs: [cancelled, {...sibling, head_sha: 'b'.repeat(40)}]}]},
    'bad workflow_id': {runPages: [{total_count: 2, workflow_runs: [cancelled, {...sibling, workflow_id: 0}]}]},
    'bad created_at': {runPages: [{total_count: 2, workflow_runs: [cancelled, {...sibling, created_at: 'nope'}]}]},
    'completed sibling without the required check': {runList: [cancelled, runObj(SIBLING_ID)]}
  };
  for (const [label, opts] of Object.entries(arms)) {
    const f = runFixture(t, checks, [cancelled, sibling], opts);
    const w = watcher(f, true);
    assert.equal(w.status, 3, `${label}: ${w.stdout}${w.stderr}`);
    assert.match(w.stdout + w.stderr, /degraded/i, label);
    const r = releaseReader(f);
    assert.equal(r.status, 20, `${label}: ${r.stdout}${r.stderr}`);
  }
});

test('TEST-2705 the workflow-run list request lives in one file and is read lazily', t => {
  const hits = [];
  const walk = dir => {
    for (const e of fs.readdirSync(dir, {withFileTypes: true})) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (fs.readFileSync(p, 'utf8').includes('actions/runs?head_sha')) hits.push(path.relative(root, p).split(path.sep).join('/'));
    }
  };
  walk(path.join(root, '.aai/scripts'));
  assert.deepEqual(hits, ['.aai/scripts/lib/github-checks.mjs']);
  for (const f of ['watch-ci.mjs', 'release-finish.mjs']) {
    const text = fs.readFileSync(path.join(root, '.aai/scripts', f), 'utf8');
    assert.match(text, /readCurrentChecks/, f);
    assert.ok(!text.includes('actions/runs'), f);
  }
  const f = transport(t, [checkRun(2), checkRun(1, 'failure')]);
  assert.equal(watcher(f, true).status, 0);
  assert.equal(releaseReader(f).status, 0);
  assert.ok(!/actions\/runs\?head_sha/.test(callLog(f)));
});

test('TEST-2711 a check the newer run registers between the check snapshot and the run list is never dropped', t => {
  // Snapshot skew: the first check-run read predates the sibling's check; the run list already shows the sibling completed.
  const cancelled = runObj(CANCEL_ID, {conclusion: 'cancelled'});
  const sibling = runObj(SIBLING_ID);
  const before = [jobCheck(1, CANCEL_ID, 'failure')];
  const after = [jobCheck(1, CANCEL_ID, 'failure'), jobCheck(2, SIBLING_ID, 'failure')];
  const f = runFixture(t, before, [cancelled, sibling], {
    checkSeq: [before, after],
    statusPages: [[{id: 1, context: 'lint', state: 'success', created_at: '2026-10-27T00:00:01Z', target_url: ''}]]
  });
  const w = watcher(f);
  assert.equal(w.status, 5, w.stdout + w.stderr);
  assert.match(w.stdout + w.stderr, /aggregate/);
  rewrite(f, {crn: 0});
  const rel = releaseBucket(f);
  assert.equal(rel.length, 1);
  assert.equal(rel[0].bucket, 'fail');
  assert.equal(rel[0].id, 2);
});
