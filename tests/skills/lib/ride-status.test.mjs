// ride-status.test.mjs - node:test cases of spec-ride-status-and-resume.
//
// Every case builds a throwaway git repository (git init -b main, its own
// user.email/user.name) holding a STATE, a frozen spec, an intake and the
// ledgers. Nothing runs in the shipping tree. The script under test is
// overridable through RIDE_STATUS_SCRIPT. Case names start with their spec
// TEST id (the suite selects by that prefix).

import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..', '..');
const SCRIPT = process.env.RIDE_STATUS_SCRIPT || path.join(REPO, '.aai', 'scripts', 'ride-status.mjs');
const DISPATCH = path.join(REPO, '.aai', 'scripts', 'orchestration-dispatch.mjs');
const TREE_HASH = pathToFileURL(path.join(REPO, '.aai', 'scripts', 'lib', 'tree-hash.mjs')).href;

const REF = 'demo';
const SPEC_REL = 'docs/specs/SPEC-9001-demo.md';
const INTAKE_REL = 'docs/issues/CHANGE-9001-demo.md';
const LABELS = ['ride:', 'current action:', 'evidence:', 'blocker:', 'next decision:', 'decisions:'];

const roots = [];
after(() => { for (const r of roots) fs.rmSync(r, { recursive: true, force: true }); });

function cleanEnv(extra = {}) {
  const env = { ...process.env };
  delete env.AAI_ROLE;
  Object.assign(env, {
    GIT_AUTHOR_NAME: 'AAI Fixture', GIT_AUTHOR_EMAIL: 'fixture@example.invalid',
    GIT_COMMITTER_NAME: 'AAI Fixture', GIT_COMMITTER_EMAIL: 'fixture@example.invalid',
    GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1',
  });
  for (const [k, v] of Object.entries(extra)) { if (v === undefined) delete env[k]; else env[k] = v; }
  return env;
}

function run(cmd, args, cwd, extraEnv = {}) {
  assert.ok(path.isAbsolute(cwd), `cwd must be absolute: ${cwd}`);
  const r = spawnSync(cmd, args, { cwd, encoding: 'utf8', env: cleanEnv(extraEnv), maxBuffer: 64 * 1024 * 1024 });
  return { status: r.status, stdout: r.stdout ?? '', stderr: r.stderr ?? '' };
}

function git(cwd, ...args) {
  const r = run('git', args, cwd);
  assert.equal(r.status, 0, `git ${args.join(' ')} failed: ${r.stderr}`);
  return r.stdout;
}

const sha = (file) => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const write = (file, text) => { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, text); };

// --- fixture world ----------------------------------------------------------------

function stateText(o) {
  const noFocus = o.noFocus === true;
  const list = (items, indent) => (items.length === 0 ? ' []' : `\n${items.map((p) => `${indent}- ${p}`).join('\n')}`);
  const out = [];
  out.push('project_status: active');
  if (o.dupKey) out.push('project_status: active');
  out.push('current_focus:');
  if (noFocus) {
    out.push('  type: none', '  ref_id: null', '  primary_path: null', '  spec_path: null');
  } else {
    out.push('  type: intake_change', `  ref_id: ${REF}`, `  primary_path: ${INTAKE_REL}`, `  spec_path: ${SPEC_REL}`);
  }
  if (noFocus) {
    out.push('active_work_items: []');
  } else {
    out.push('active_work_items:', `  - ref_id: ${REF}`, `    status: ${o.status ?? 'done'}`, `    phase: ${o.phase ?? 'planning'}`,
      `    primary_path: ${INTAKE_REL}`, `    spec_path: ${SPEC_REL}`);
  }
  out.push('implementation_strategy:', `  selected: ${o.strategy ?? 'tdd'}`, `  ref_id: ${noFocus ? 'null' : (o.stratRef ?? REF)}`);
  out.push('worktree:', `  recommendation: ${o.wtRec ?? 'not_needed'}`, `  user_decision: ${o.wtDec ?? 'worktree'}`);
  const rv = o.review ?? { required: false, status: 'not_run', paths: [] };
  out.push('code_review:', `  required: ${rv.required}`, `  status: ${rv.status}`, `  report_paths:${list(rv.paths, '    ')}`);
  const va = o.validation ?? { status: 'not_run', ref: null, paths: [] };
  out.push('last_validation:', `  status: ${va.status}`, `  ref_id: ${va.ref ?? 'null'}`, `  evidence_paths:${list(va.paths, '    ')}`);
  if (o.tdd) {
    out.push('tdd_cycle:', `  status: ${o.tdd.status}`, `  test_id: ${o.tdd.testId}`, `  spec_path: ${o.tdd.specPath ?? SPEC_REL}`);
  }
  const hi = o.human ?? { required: false, question: null };
  out.push('human_input:', `  required: ${hi.required}`, `  question: ${hi.question ?? 'null'}`, '  blocking_reason: null');
  if (o.runs) {
    out.push('metrics:', '  work_items:', `    ${REF}:`, '      agent_runs:');
    for (const role of o.runs) out.push(`        - role: ${role}`, '          model_id: claude-sonnet-5-5');
  }
  out.push('updated_at_utc: 2026-10-31T00:00:00Z');
  return `${out.join('\n')}\n`;
}

function specText(o) {
  const pr = (o.specPr ?? []).length === 0 ? '  pr: []' : `  pr:\n${o.specPr.map((n) => `    - ${n}`).join('\n')}`;
  return `---\nid: spec-demo\ntype: spec\nstatus: implementing\nceremony_level: 2\nlinks:\n${pr}\n---\n\n# Demo\n\nSPEC-FROZEN: true\n`;
}

function world(o = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ride-status-'));
  roots.push(root);
  git(root, 'init', '-q', '-b', 'main');
  git(root, 'config', 'user.email', 'fixture@example.invalid');
  git(root, 'config', 'user.name', 'AAI Fixture');
  write(path.join(root, 'docs/TECHNOLOGY.md'), '# Tech\n');
  write(path.join(root, '.aai/workflow/WORKFLOW.md'), '# Workflow\n');
  write(path.join(root, '.aai/system/LOCKS.md'), '# Locks\n');
  write(path.join(root, SPEC_REL), specText(o));
  write(path.join(root, INTAKE_REL), `---\nid: CHANGE-9001\ntype: change\nstatus: implementing\nlinks:\n  pr: []\n---\n\n# Intake\n`);
  for (let i = 1; i <= (o.mutations ?? 0); i += 1) {
    write(path.join(root, `docs/ai/tdd/spec-demo/mutation-TEST-${String(i).padStart(3, '0')}.txt`), 'verdict: RED\n');
  }
  write(path.join(root, 'docs/ai/EVENTS.jsonl'), o.events ?? '');
  write(path.join(root, 'docs/ai/METRICS.jsonl'), o.metrics ?? '');
  const statePath = path.join(root, 'docs/ai/STATE.yaml');
  write(statePath, stateText(o));
  git(root, 'add', '-A');
  git(root, 'commit', '-q', '-m', 'fixture');
  return { root, statePath };
}

const status = (w, ...extra) => run('node', [SCRIPT, ...extra, '--state', w.statePath, '--root', w.root], w.root);
const probe = (w, ...extra) => run('node', [SCRIPT, 'probe', ...extra, '--state', w.statePath, '--root', w.root], w.root);
const dispatcher = (w) => run('node', [DISPATCH, '--state', w.statePath, '--root', w.root], w.root);

const focusOpts = () => ({
  phase: 'implementation', status: 'in_progress', strategy: 'tdd',
  validation: { status: 'pass', ref: REF, paths: ['docs/ai/validation/VALIDATION-demo.md'] },
  review: { required: true, status: 'pass', paths: ['docs/ai/reports/REVIEW-demo.md'] },
  tdd: { status: 'GREEN', testId: 'TEST-9001' },
  mutations: 2,
  specPr: [77],
});

function labelLines(out) {
  const ls = out.trimEnd().split('\n');
  assert.equal(ls.length, 6, `status must print exactly six lines, got:\n${out}`);
  LABELS.forEach((l, i) => assert.ok(ls[i].startsWith(l), `line ${i + 1} must start with "${l}": ${ls[i]}`));
  return ls;
}

// --- TEST-3144 .. TEST-3148 ---------------------------------------------------------

test('TEST-3144 text mode prints the six D2 lines in order with the fixture values', () => {
  const w = world(focusOpts());
  const r = status(w);
  assert.equal(r.status, 0, r.stderr);
  const ls = labelLines(r.stdout);
  assert.equal(ls[0], `ride: ${REF} (intake_change) spec=${SPEC_REL} ceremony=2`);
  assert.match(ls[1], /^current action: phase=implementation status=in_progress; dispatcher: dispatch rule 14 -> Metrics Flush/);
  assert.ok(ls[2].includes(`validation=pass for ${REF} docs/ai/validation/VALIDATION-demo.md`), ls[2]);
  assert.ok(ls[2].includes('review=pass required=true docs/ai/reports/REVIEW-demo.md'), ls[2]);
  assert.ok(ls[2].includes('tdd=GREEN mutation_records=2'), ls[2]);
  assert.ok(ls[2].endsWith('pr=77'), ls[2]);
  assert.equal(ls[3], 'blocker: none');
  assert.match(ls[4], /^next decision: loop: \/aai-loop - /);
  assert.match(ls[5], new RegExp(`^decisions: strategy=tdd ref=${REF} reused=true; worktree=not_needed/worktree ref_binding=none$`));
});

test('TEST-3145 --json carries the same values under the D2 keys', () => {
  const w = world(focusOpts());
  const r = status(w, '--json');
  assert.equal(r.status, 0, r.stderr);
  const j = JSON.parse(r.stdout);
  assert.equal(j.ref_id, REF);
  assert.equal(j.focus_type, 'intake_change');
  assert.equal(j.spec_path, SPEC_REL);
  assert.equal(j.ceremony_level, 2);
  assert.deepEqual({ phase: j.current_action.phase, status: j.current_action.status, verdict: j.current_action.verdict, rule: j.current_action.rule, role: j.current_action.role },
    { phase: 'implementation', status: 'in_progress', verdict: 'dispatch', rule: '14', role: 'Metrics Flush' });
  assert.deepEqual(j.evidence.validation, { status: 'pass', ref_id: REF, for_focus: true, evidence_paths: ['docs/ai/validation/VALIDATION-demo.md'] });
  assert.deepEqual(j.evidence.code_review, { required: true, status: 'pass', report_paths: ['docs/ai/reports/REVIEW-demo.md'] });
  assert.deepEqual(j.evidence.tdd, { status: 'GREEN', test_id: 'TEST-9001', mutation_records: 2 });
  assert.deepEqual(j.evidence.pr, ['77']);
  assert.equal(j.blocker.kind, 'none');
  assert.equal(typeof j.next_decision.actor, 'string');
  assert.equal(typeof j.next_decision.command, 'string');
  assert.equal(typeof j.next_decision.why, 'string');
  assert.deepEqual(j.decisions.strategy, { selected: 'tdd', ref_id: REF, reused: true });
  assert.deepEqual(j.decisions.worktree, { recommendation: 'not_needed', user_decision: 'worktree', ref_binding: 'none' });
});

test('TEST-3146 a null focus prints ride: none, the five other labels, exit 0, and json ref_id null', () => {
  const w = world({ noFocus: true });
  const r = status(w);
  assert.equal(r.status, 0, r.stderr);
  const ls = labelLines(r.stdout);
  assert.equal(ls[0], 'ride: none (no current focus)');
  assert.match(ls[1], /^current action: phase=none status=none; dispatcher: /);
  assert.ok(ls[2].includes('validation=none'), ls[2]);
  assert.ok(ls[2].endsWith('pr=none'), ls[2]);
  const j = JSON.parse(status(w, '--json').stdout);
  assert.equal(j.ref_id, null);
  assert.equal(j.current_action.phase, null);
  assert.equal(status(w, '--json').status, 0);
});

test('TEST-3147 status and probe write nothing: tree hash and STATE bytes are identical', async () => {
  const { computeTreeHash } = await import(TREE_HASH);
  const fixtures = [world(focusOpts()), world({ noFocus: true }), world({ dupKey: true })];
  for (const w of fixtures) {
    for (const call of [() => status(w), () => status(w, '--json'), () => probe(w, '--json')]) {
      const hashBefore = computeTreeHash(w.root);
      const stateBefore = sha(w.statePath);
      const porcelainBefore = git(w.root, 'status', '--porcelain');
      const r = call();
      assert.equal(r.status, 0, `exit ${r.status}: ${r.stderr}`);
      assert.ok(r.stdout.length > 0, 'a report must be printed');
      assert.equal(computeTreeHash(w.root), hashBefore, 'tree hash changed');
      assert.equal(sha(w.statePath), stateBefore, 'STATE bytes changed');
      assert.equal(git(w.root, 'status', '--porcelain'), porcelainBefore, 'git status changed');
    }
  }
});

test('TEST-3148 current action equals the real dispatcher on five fixtures', () => {
  const fixtures = [
    ['tdd dispatch 9a', world({}), { verdict: 'dispatch', rule: '9a' }],
    ['human input rule 2', world({ human: { required: true, question: 'Which way?' } }), { verdict: 'no_action', rule: '2' }],
    ['flushed pass rule 14', world({
      phase: 'validation', status: 'in_progress',
      validation: { status: 'pass', ref: REF, paths: [] }, review: { required: true, status: 'pass', paths: [] },
      metrics: `${JSON.stringify({ ref_id: REF, date_utc: '2026-10-30', title: 'demo' })}\n`,
    }), { verdict: 'no_action', rule: '14' }],
    ['needs_llm review_staleness_unknown', world({
      phase: 'validation', status: 'in_progress', runs: ['Planning', 'TDD Implementation'],
      validation: { status: 'pass', ref: REF, paths: [] }, review: { required: true, status: 'pass', paths: [] },
    }), { verdict: 'needs_llm', reason: 'review_staleness_unknown' }],
    ['duplicate top-level key', world({ dupKey: true }), { verdict: 'needs_llm', reason: 'duplicate_top_level_key:project_status' }],
  ];
  for (const [name, w, want] of fixtures) {
    const d = JSON.parse(dispatcher(w).stdout);
    const sr = status(w, '--json');
    assert.equal(sr.status, 0, `${name}: ride-status exits 0 whatever the verdict: ${sr.stderr}`);
    const s = JSON.parse(sr.stdout).current_action;
    assert.equal(d.verdict, want.verdict, `${name}: fixture must produce the intended dispatcher verdict, got ${d.verdict}/${d.rule}`);
    if (want.rule) assert.equal(d.rule, want.rule, `${name}: dispatcher rule`);
    if (want.reason) assert.ok(d.reasons.includes(want.reason), `${name}: dispatcher reasons ${JSON.stringify(d.reasons)}`);
    assert.equal(s.verdict, d.verdict, `${name}: verdict`);
    assert.equal(s.rule, d.rule, `${name}: rule`);
    assert.equal(s.role, d.role, `${name}: role`);
    assert.deepEqual(s.reasons, d.reasons, `${name}: reasons`);
  }
});
