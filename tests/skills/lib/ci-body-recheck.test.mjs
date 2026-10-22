import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import {
  bodyEditEligibility, proveBodyRun, GATE_JOB, FULL_LEG_JOB, SELECTED_JOB,
  SELECTED_SHARDED_JOB, SELECT_JOB, SEED_JOB, SMOKE_JOB, TRACKED_JOB, NOTES_JOB,
} from '../../../.aai/scripts/ci-select.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../../..');
const WF = readFileSync(join(ROOT, '.github/workflows/skill-suite.yml'), 'utf8');
const A = 'a'.repeat(40), B = 'b'.repeat(40), C = 'c'.repeat(40);
const options = () => ({ repo: 'o/r', workflowFile: 'skill-suite.yml', checkoutSha: C, workflowSha: C, currentRunId: '200' });
const event = () => ({
  action: 'edited', changes: { body: { from: 'before' } }, repository: { full_name: 'o/r' },
  pull_request: { number: 7, body: 'after', labels: [],
    head: { sha: B, ref: 'feat', repo: { full_name: 'o/r' } },
    base: { sha: A, ref: 'main', repo: { full_name: 'o/r' } } },
});
const identity = (e = event(), o = options()) =>
  `ci-source-identity-v1 head=${e.pull_request.head.sha} base=${e.pull_request.base.sha} checkout=${o.checkoutSha} workflow=${o.workflowSha}`;
const step = (name) => ({ name, status: 'completed', conclusion: 'success' });
const job = (name, conclusion = 'success', source = false, e = event(), o = options()) => ({
  name, status: 'completed', conclusion, run_attempt: 1,
  steps: source ? [step(identity(e, o))] : [],
});
function anchor(mode = 'full', e = event(), o = options()) {
  const run = { id: 100, run_attempt: 1, status: 'completed', conclusion: 'success', event: 'pull_request',
    head_sha: e.pull_request.head.sha, head_branch: e.pull_request.head.ref,
    repository: { full_name: o.repo }, head_repository: { full_name: o.repo },
    path: `.github/workflows/${o.workflowFile}@refs/pull/${e.pull_request.number}/merge`,
    pull_requests: [{ number: e.pull_request.number, base: { ref: e.pull_request.base.ref, sha: e.pull_request.base.sha } }],
    html_url: 'https://github.com/o/r/actions/runs/100' };
  const runners = mode === 'selected' ? '1' : mode === 'sharded' ? '2' : 'none';
  const selected = mode === 'selected' ? '[1]' : mode === 'sharded' ? '[1,2]' : 'none';
  const jobs = [job(SELECT_JOB, 'success', true, e, o), job(GATE_JOB), job(SEED_JOB, 'success', true, e, o),
    job(SMOKE_JOB, 'success', true, e, o), job(TRACKED_JOB), job(NOTES_JOB)];
  jobs[0].steps.push(step(`ci-source-plan-v1 full=[1,2,3,4] selected=${selected} runners=${runners}`));
  if (mode === 'full') {
    jobs.push(...[1, 2, 3, 4].map((n) => job(`${FULL_LEG_JOB} (${n})`, 'success', true, e, o)));
    jobs.push(job(SELECTED_JOB, 'skipped'), job(SELECTED_SHARDED_JOB, 'skipped'));
  } else if (mode === 'selected') {
    jobs.push(job(FULL_LEG_JOB, 'skipped'), job(SELECTED_JOB, 'success', true, e, o), job(SELECTED_SHARDED_JOB, 'skipped'));
  } else {
    jobs.push(job(FULL_LEG_JOB, 'skipped'), job(SELECTED_JOB, 'skipped'),
      ...[1, 2].map((n) => job(`${SELECTED_SHARDED_JOB} (${n})`, 'success', true, e, o)));
  }
  return { run, jobs };
}
const copy = (x) => structuredClone(x);

test('TEST-001 body-only classification is exact and conservative', () => {
  assert.equal(bodyEditEligibility(event(), options()), null);
  const yesNull = event(); yesNull.changes.body.from = null;
  assert.equal(bodyEditEligibility(yesNull, options()), null);
  for (const edit of [
    (e) => { e.action = 'synchronize'; }, (e) => { delete e.changes; },
    (e) => { e.changes.title = { from: 'old' }; }, (e) => { e.changes.unknown = {}; },
    (e) => { e.changes.body.from = 5; }, (e) => { e.pull_request.body = false; },
    (e) => { e.pull_request.body = 'before'; }, (e) => { e.pull_request.labels = [{ name: 'ci-full' }]; },
    (e) => { e.pull_request.labels = { name: 'ci-full' }; },
    (e) => { e.pull_request.head.repo.full_name = 'fork/r'; },
    (e) => { delete e.pull_request.base.sha; }, (e) => { delete e.repository; },
  ]) { const e = event(); edit(e); assert.notEqual(bodyEditEligibility(e, options()), null); }
  assert.notEqual(bodyEditEligibility(event(), { ...options(), checkoutSha: B }), null);
  assert.notEqual(bodyEditEligibility(event(), { ...options(), workflowSha: B }), null);
});

test('TEST-002 full and selected anchors bind every source identity field', () => {
  for (const mode of ['full', 'selected', 'sharded']) {
    const a = anchor(mode); assert.equal(proveBodyRun(a.run, a.jobs, event(), options()), null, mode);
  }
  for (const edit of [
    (a) => { a.run.head_sha = A; }, (a) => { a.run.head_branch = 'other'; },
    (a) => { a.run.repository.full_name = 'other/r'; },
    (a) => { a.run.head_repository.full_name = 'other/r'; },
    (a) => { a.run.pull_requests[0].number = 8; },
    (a) => { a.run.pull_requests[0].base.sha = B; },
    (a) => { a.run.pull_requests[0].base.ref = 'other'; },
    (a) => { a.run.path = '.github/workflows/other.yml'; },
    (a) => { a.jobs[0].steps[0].name = 'legacy-no-identity'; },
    (a) => { a.jobs[0].steps[0].name = a.jobs[0].steps[0].name.replace(`checkout=${C}`, `checkout=${B}`); },
    (a) => { a.jobs[0].steps[0].name = a.jobs[0].steps[0].name.replace(`workflow=${C}`, `workflow=${B}`); },
  ]) { const a = anchor(); edit(a); assert.notEqual(proveBodyRun(a.run, a.jobs, event(), options()), null); }
});

test('TEST-003 exact source plan, complete job set and attempt are required', () => {
  const good = anchor(); assert.equal(proveBodyRun(good.run, good.jobs, event(), options()), null);
  for (const edit of [
    (a) => { a.jobs = a.jobs.filter((j) => j.name !== `${FULL_LEG_JOB} (4)`); },
    (a) => { a.jobs.push(copy(a.jobs[0])); },
    (a) => { a.jobs.find((j) => j.name === `${FULL_LEG_JOB} (2)`).conclusion = 'failure'; },
    (a) => { a.jobs.find((j) => j.name === `${FULL_LEG_JOB} (2)`).conclusion = 'cancelled'; },
    (a) => { a.jobs.find((j) => j.name === `${FULL_LEG_JOB} (2)`).conclusion = 'skipped'; },
    (a) => { a.jobs.find((j) => j.name === `${FULL_LEG_JOB} (2)`).status = 'in_progress'; },
    (a) => { a.jobs[0].steps.pop(); }, (a) => { a.jobs[0].steps.push(copy(a.jobs[0].steps[1])); },
    (a) => { a.jobs[0].steps.push({ ...copy(a.jobs[0].steps[0]), conclusion: 'failure' }); },
    (a) => { a.jobs.find((j) => j.name === SEED_JOB).steps = []; },
    (a) => { a.jobs[0].run_attempt = 2; }, (a) => { a.run.conclusion = 'failure'; },
    (a) => { a.run.id = 200; },
  ]) { const a = anchor(); edit(a); assert.notEqual(proveBodyRun(a.run, a.jobs, event(), options()), null); }
  for (const mode of ['full', 'selected', 'sharded']) {
    const good = anchor(mode);
    assert.equal(proveBodyRun(good.run, good.jobs, event(), options()), null, mode);
    for (const source of good.jobs.filter((j) => j.steps.some((s) => s.name === identity()))) {
      const a = anchor(mode);
      a.jobs.find((j) => j.name === source.name).steps.push(step(identity().replace(`base=${A}`, `base=${B}`)));
      assert.notEqual(proveBodyRun(a.run, a.jobs, event(), options()), null, `${mode}: ${source.name}`);
    }
  }
});

function run(cmd, args, cwd, env = {}) {
  return spawnSync(cmd, args, { cwd, encoding: 'utf8', env: { ...process.env, ...env }, timeout: 15000 });
}
function git(cwd, ...args) {
  const r = run('git', args, cwd, { GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_SYSTEM: '/dev/null', GIT_CONFIG_NOSYSTEM: '1' });
  assert.equal(r.status, 0, `${args.join(' ')}: ${r.stderr}`);
  return r.stdout.trim();
}
function fixture() {
  const scratch = process.env.AAI_CI_BODY_SCRATCH || join(tmpdir(), 'aai-ci-body-implementation-scratch');
  mkdirSync(scratch, { recursive: true });
  const dir = mkdtempSync(join(scratch, 'fixture-'));
  git(dir, 'init', '-q', '-b', 'main'); git(dir, 'config', 'user.email', 'fixture@example.invalid');
  git(dir, 'config', 'user.name', 'Fixture');
  mkdirSync(join(dir, 'tests/skills'), { recursive: true });
  writeFileSync(join(dir, 'tests/skills/suite-map.yaml'), 'core:\n  - aai-core\nsuites:\n  aai-core:\n    globs:\n      - feature/**\n');
  writeFileSync(join(dir, 'start.txt'), 'base\n'); git(dir, 'add', '.'); git(dir, 'commit', '-qm', 'base');
  const base = git(dir, 'rev-parse', 'HEAD');
  git(dir, 'checkout', '-qb', 'feat'); mkdirSync(join(dir, 'feature'));
  writeFileSync(join(dir, 'feature/a.txt'), 'change\n'); git(dir, 'add', '.'); git(dir, 'commit', '-qm', 'feature');
  const head = git(dir, 'rev-parse', 'HEAD');
  git(dir, 'checkout', '-qb', 'merge', 'main'); git(dir, 'merge', '--no-ff', '-qm', 'merge', 'feat');
  const checkout = git(dir, 'rev-parse', 'HEAD');
  const e = event(); e.pull_request.base.sha = base; e.pull_request.head.sha = head;
  const o = { ...options(), checkoutSha: checkout, workflowSha: checkout };
  const a = anchor('selected', e, o);
  const runs = `/repos/o/r/actions/workflows/skill-suite.yml/runs?event=pull_request&status=completed&head_sha=${head}&per_page=20`;
  const detail = '/repos/o/r/actions/runs/100';
  const jobs = '/repos/o/r/actions/runs/100/attempts/1/jobs?per_page=100';
  const responses = {
    [runs]: { status: 200, body: { total_count: 1, workflow_runs: [a.run] } },
    [detail]: { status: 200, body: a.run },
    [jobs]: { status: 200, body: { total_count: a.jobs.length, jobs: a.jobs } },
  };
  const ev = join(dir, 'event.json'), api = join(dir, 'api.json'), log = join(dir, 'requests.log');
  writeFileSync(ev, JSON.stringify(e)); writeFileSync(api, JSON.stringify(responses));
  return { dir, base, head, checkout, e, o, responses, runs, detail, jobs, ev, api, log,
    close: () => rmSync(dir, { recursive: true, force: true }) };
}
function cli(f, env = {}) {
  writeFileSync(f.api, JSON.stringify(f.responses));
  return run('node', [join(ROOT, '.aai/scripts/ci-select.mjs'), '--base-ref', 'main', '--event', f.ev,
    '--repo', 'o/r', '--workflow-file', 'skill-suite.yml', '--repo-root', f.dir,
    '--checkout-sha', f.checkout, '--workflow-sha', f.checkout, '--current-run-id', '200',
    '--api-fixture', f.api, '--request-log', f.log], ROOT, { GITHUB_TOKEN: 'fixture-token', ...env });
}

test('TEST-004 CLI accepts proven attempt and falls back on bounded API failures', () => {
  const f = fixture();
  try {
    const yes = cli(f); assert.equal(yes.status, 0, yes.stderr);
    assert.match(yes.stdout, /^BODY_REUSE run=100 attempt=1 /m);
    assert.deepEqual(readFileSync(f.log, 'utf8').trim().split('\n'),
      [`GET ${f.runs}`, `GET ${f.detail}`, `GET ${f.jobs}`, `GET ${f.detail}`]);
    const ordinary = run('node', [join(ROOT, '.aai/scripts/select-suites.mjs'), '--base-ref', 'main', '--repo-root', f.dir], ROOT);
    for (const response of [
      { status: 403, body: {} }, { status: 429, body: {} }, { status: 200, raw: '{bad' },
      { status: 200, body: { total_count: 2, workflow_runs: [f.responses[f.runs].body.workflow_runs[0]] } },
    ]) {
      f.responses[f.runs] = response; const no = cli(f); assert.equal(no.status, 0);
      assert.ok(no.stdout.startsWith(ordinary.stdout)); assert.match(no.stdout, /CARRY_FORWARD none reason=body-reuse:/);
    }
    f.responses[f.runs] = { status: 200, body: { total_count: 1, workflow_runs: [anchor('selected', f.e, f.o).run] } };
    delete f.responses[f.jobs]; assert.match(cli(f).stdout, /body-reuse:api-404/);
    assert.match(cli(f, { GITHUB_TOKEN: '' }).stdout, /body-reuse:no-token/);
  } finally { f.close(); }
});

function jobBlock(name, next) { return WF.split(`  ${name}:\n`)[1].split(`\n  ${next}:`)[0]; }
function publishedPlan(mode) {
  const block = jobBlock('select', 'skills-selected');
  const marker = block.match(/^      - name: (ci-source-plan-v1 .*)$/m);
  const producer = block.indexOf('      - id: selected-plan\n');
  assert.ok(marker && producer >= 0, 'selection plan marker and producer exist');
  assert.ok(producer < marker.index, 'selected plan must exist before its proof is published');
  const outputs = {
    'steps.shard.outputs.shard_ids': '[1,2,3,4]',
    'steps.selected-plan.outputs.shard_ids': mode === 'selected' ? '[1]' : mode === 'sharded' ? '[1,2]' : '',
    'steps.selected-plan.outputs.runners': mode === 'selected' ? '1' : mode === 'sharded' ? '2' : '',
  };
  return marker[1].replace(/\$\{\{ ([^}]+) \}\}/g, (_, expression) => {
    const [key, fallback] = expression.trim().split(' || ');
    return outputs[key] || fallback?.replaceAll("'", '') || '';
  });
}
function gateScript() {
  const block = jobBlock('gate', 'self-hosting-smoke');
  return block.split('        run: |\n')[1].split('\n').map((l) => l.startsWith('          ') ? l.slice(10) : l).join('\n');
}
function gate(data) {
  const script = gateScript().replace(/\$\{\{ (needs\.[^} ]+|github\.event_name) \}\}/g, (_, key) => data[key] ?? '');
  return run('bash', ['-c', script], ROOT, { BODY_PROOF: data['needs.select.outputs.body_proof'] || '' });
}
const goodGate = () => ({ 'github.event_name': 'pull_request', 'needs.select.result': 'success',
  'needs.select.outputs.mode': 'body-reuse', 'needs.select.outputs.body_proof': 'BODY_REUSE run=100',
  'needs.release-notes.result': 'success', 'needs.tracked-ignored.result': 'success',
  'needs.skills-selected.result': 'skipped', 'needs.skills-selected-sharded.result': 'skipped',
  'needs.skills-full.result': 'skipped', 'needs.native-worktree-seed.result': 'skipped',
  'needs.self-hosting-smoke.result': 'skipped', 'needs.select.outputs.selected_runners': '' });

test('TEST-005 real workflow conditions and aggregate enforce body-reuse proof', () => {
  for (const mode of ['full', 'selected', 'sharded']) {
    const a = anchor(mode);
    a.jobs[0].steps[1].name = publishedPlan(mode);
    assert.equal(proveBodyRun(a.run, a.jobs, event(), options()), null, mode);
  }
  const deriveBlock = jobBlock('select', 'skills-selected').match(/^          if echo "\$OUT"[\s\S]*?^          fi$/m)?.[0];
  assert.ok(deriveBlock);
  const scratch = process.env.AAI_CI_BODY_SCRATCH || join(tmpdir(), 'aai-ci-body-implementation-scratch');
  mkdirSync(scratch, { recursive: true });
  const deriveDir = mkdtempSync(join(scratch, 'derive-'));
  try {
    const output = join(deriveDir, 'output');
    const derive = (out) => {
      writeFileSync(output, '');
      const r = run('bash', ['-c', `set -e\n${deriveBlock.split('\n').map((l) => l.slice(10)).join('\n')}`], ROOT,
        { OUT: out, GITHUB_OUTPUT: output });
      assert.equal(r.status, 0, r.stderr); return readFileSync(output, 'utf8');
    };
    assert.match(derive('BODY_REUSE run=100 attempt=1 url=https://github.com/o/r/actions/runs/100'), /mode=body-reuse/);
    assert.match(derive('FULL_RUN reason=unmapped path=x'), /mode=full/);
    assert.match(derive('CORE aai-core reason=core\nSELECTED aai-feature reason=feature\/x'), /mode=selected/);
  } finally { rmSync(deriveDir, { recursive: true, force: true }); }
  assert.match(WF, /needs: \[select, skills-selected, skills-selected-sharded, skills-full, native-worktree-seed, self-hosting-smoke, tracked-ignored, release-notes\]/);
  for (const name of ['skills-selected', 'skills-selected-sharded', 'skills-full', 'native-worktree-seed', 'self-hosting-smoke']) {
    const next = name === 'skills-selected' ? 'skills-selected-sharded' : name === 'skills-selected-sharded' ? 'skills-full'
      : name === 'skills-full' ? 'tracked-ignored' : name === 'native-worktree-seed' ? 'gate' : null;
    const block = next ? jobBlock(name, next) : WF.split('  self-hosting-smoke:\n')[1];
    assert.match(block, /needs: select/);
    assert.match(block, /mode (?:!= 'body-reuse'|== '(?:selected|full)')/);
    assert.match(block, /ref: \$\{\{ needs\.select\.outputs\.checkout_sha \}\}/);
    assert.match(block, /source_identity/);
  }
  assert.equal(gate(goodGate()).status, 0);
  const selected = { ...goodGate(), 'needs.select.outputs.mode': 'selected', 'needs.select.outputs.selected_runners': '1',
    'needs.skills-selected.result': 'success', 'needs.native-worktree-seed.result': 'success',
    'needs.self-hosting-smoke.result': 'success' };
  assert.equal(gate(selected).status, 0);
  const full = { ...selected, 'needs.select.outputs.mode': 'full', 'needs.skills-selected.result': 'skipped',
    'needs.skills-full.result': 'success' };
  assert.equal(gate(full).status, 0);
  for (const key of ['needs.select.result', 'needs.release-notes.result', 'needs.tracked-ignored.result',
    'needs.select.outputs.body_proof', 'needs.skills-full.result', 'needs.native-worktree-seed.result',
    'needs.self-hosting-smoke.result']) {
    const bad = goodGate(); bad[key] = key.endsWith('body_proof') ? '' : 'failure';
    assert.notEqual(gate(bad).status, 0, key);
  }
  for (const mode of ['', 'bogus']) assert.notEqual(gate({ ...goodGate(), 'needs.select.outputs.mode': mode }).status, 0);
});

test('TEST-006 actual release-notes CLI rejects the current body and aggregate follows', () => {
  const f = fixture();
  try {
    mkdirSync(join(f.dir, '.aai/scripts'), { recursive: true });
    writeFileSync(join(f.dir, '.aai/scripts/a.sh'), 'echo shipped\n'); git(f.dir, 'add', '.'); git(f.dir, 'commit', '-qm', 'shipped');
    const head = git(f.dir, 'rev-parse', 'HEAD');
    const body = join(f.dir, 'body.txt');
    const check = (text) => { writeFileSync(body, text); return run('node', [join(ROOT, '.aai/scripts/release-notes-gate.mjs'),
      '--base', f.base, '--head', head, '--body-file', body], f.dir); };
    assert.equal(check('no-notes: test-only body edit').status, 0);
    assert.notEqual(check('ordinary body').status, 0);
    assert.notEqual(check('$(echo shell-looking body)').status, 0);
    assert.notEqual(gate({ ...goodGate(), 'needs.release-notes.result': 'failure' }).status, 0);
  } finally { f.close(); }
});

test('TEST-008 report states pending hosted protocol with complete evidence fields', () => {
  const report = readFileSync(join(ROOT, 'docs/analysis/ci-body-only-rechecks.md'), 'utf8');
  for (const token of ['H1', 'H2', 'PENDING', 'pre-merge', 'run ID', 'attempt', 'source SHA', 'base SHA',
    'checkout SHA', 'workflow SHA', 'job conclusions', 'executed source-job count', 'job durations', 'wall time']) {
    assert.ok(report.includes(token), token);
  }
  const impact = readFileSync(join(ROOT, 'docs/product/ci-test-impact-selection.md'), 'utf8');
  const notes = readFileSync(join(ROOT, 'docs/product/release-notes-gate.md'), 'utf8');
  for (const term of ['body-reuse', 'same head', 'base', 'checkout', 'workflow', 'fallback', 'release notes']) {
    assert.ok(impact.toLowerCase().includes(term), `product CI text: ${term}`);
  }
  assert.match(notes, /body-only edit/);
  assert.match(notes, /removing an exemption can fail/);
  assert.doesNotMatch(report, /H[12]\s*—\s*(?:DONE|PASS)/);
  assert.match(readFileSync(join(ROOT, 'docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md'), 'utf8'), /status: (?:draft|implementing|active|in_progress|accepted)/);
});
