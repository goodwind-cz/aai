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

// Hermetic platform CLI: fixtures without a pr-config fall back to platform github, so every
// status/probe call gets a gh stub first on PATH (empty PR list) instead of the real gh.
let defaultGh = null;
const defaultGhEnv = () => {
  if (!defaultGh) { defaultGh = ghStub(); defaultGh.answer('[]'); }
  return defaultGh.env;
};
const status = (w, ...extra) => run('node', [SCRIPT, ...extra, '--state', w.statePath, '--root', w.root], w.root, defaultGhEnv());
const probe = (w, ...extra) => run('node', [SCRIPT, 'probe', ...extra, '--state', w.statePath, '--root', w.root], w.root, defaultGhEnv());
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

// --- TEST-3149 .. TEST-3151 ---------------------------------------------------------

const json = (w) => {
  const r = status(w, '--json');
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
};

test('TEST-3149 blocker kinds and the owner / loop split of the next decision', () => {
  const human = json(world({ human: { required: true, question: 'Which way should the ride go?' } }));
  assert.equal(human.blocker.kind, 'human_input');
  assert.equal(human.blocker.detail, 'Which way should the ride go?');
  assert.equal(human.next_decision.actor, 'owner');
  assert.equal(human.next_decision.command, '/aai-hitl');

  const failing = json(world({ phase: 'validation', status: 'in_progress', validation: { status: 'fail', ref: REF, paths: [] } }));
  assert.equal(failing.blocker.kind, 'failing_gate');
  assert.equal(failing.blocker.detail, 'validation');
  assert.equal(failing.next_decision.actor, 'loop');

  const llm = json(world({
    phase: 'validation', status: 'in_progress', runs: ['Planning', 'TDD Implementation'],
    validation: { status: 'pass', ref: REF, paths: [] }, review: { required: true, status: 'pass', paths: [] },
  }));
  assert.equal(llm.blocker.kind, 'needs_llm');
  assert.ok(llm.blocker.detail.includes('review_staleness_unknown'), llm.blocker.detail);
});

test('TEST-3150 next decision: pull request after flush, loop before it, worktree gate by recommendation', () => {
  const passing = {
    phase: 'validation', status: 'in_progress',
    validation: { status: 'pass', ref: REF, paths: [] }, review: { required: true, status: 'pass', paths: [] },
  };
  const flushed = json(world({ ...passing, metrics: `${JSON.stringify({ ref_id: REF, date_utc: '2026-10-30', title: 'demo' })}\n` }));
  assert.equal(flushed.current_action.rule, '14');
  assert.equal(flushed.next_decision.actor, 'loop');
  assert.equal(flushed.next_decision.command, '/aai-pr');

  const unflushed = json(world(passing));
  assert.equal(unflushed.current_action.role, 'Metrics Flush');
  assert.equal(unflushed.next_decision.actor, 'loop');
  assert.equal(unflushed.next_decision.command, '/aai-loop');

  const required = json(world({ wtRec: 'required', wtDec: 'undecided' }));
  assert.equal(required.current_action.rule, '8');
  assert.equal(required.next_decision.actor, 'owner');
  assert.equal(required.next_decision.command, '/aai-worktree gate');

  const recommended = json(world({ wtRec: 'recommended', wtDec: 'undecided' }));
  assert.equal(recommended.current_action.rule, '8');
  assert.equal(recommended.ceremony_level, 2);
  assert.equal(recommended.next_decision.actor, 'loop');
  assert.equal(recommended.next_decision.command, '/aai-loop');
});

test('TEST-3151 strategy reuse is bound to the focus ref; the worktree part prints ref_binding none', () => {
  const bound = world({ phase: 'planning', status: 'done', strategy: 'tdd', stratRef: REF });
  const b = json(bound);
  assert.equal(b.decisions.strategy.reused, true);
  assert.equal(b.current_action.role, 'TDD Implementation');
  assert.notEqual(b.current_action.rule, '7');
  assert.equal(b.decisions.worktree.ref_binding, 'none');
  assert.match(status(bound).stdout, /ref_binding=none$/m);

  const other = world({ phase: 'planning', status: 'done', strategy: 'tdd', stratRef: 'OTHER-1' });
  const o = json(other);
  assert.equal(o.decisions.strategy.reused, false);
  assert.equal(o.decisions.strategy.ref_id, 'OTHER-1');
  assert.equal(o.current_action.role, 'Planning');
  assert.equal(o.current_action.rule, '7');
  assert.equal(o.decisions.worktree.ref_binding, 'none');
  assert.match(status(other).stdout, /ref_binding=none$/m);
});

// --- TEST-3152 .. TEST-3155 ---------------------------------------------------------

const BRANCH = 'feat/x';

// A fixture clone of a real bare origin, on BRANCH. Returns the world plus the origin path.
function clonedWorld(o = {}, { push = true } = {}) {
  const w = world(o);
  const origin = fs.mkdtempSync(path.join(os.tmpdir(), 'ride-status-origin-'));
  roots.push(origin);
  git(origin, 'init', '-q', '--bare', '-b', 'main');
  git(origin, 'symbolic-ref', 'HEAD', 'refs/heads/main');
  git(w.root, 'remote', 'add', 'origin', origin);
  git(w.root, 'checkout', '-q', '-b', BRANCH);
  if (push) git(w.root, 'push', '-q', '-u', 'origin', BRANCH);
  return { ...w, origin };
}

const pushedOf = (w) => JSON.parse(probe(w, '--json', '--branch', BRANCH).stdout).effects.pushed;

test('TEST-3152 pushed: done at head, not_done naming both shas when ahead, not_done when absent, unknown without origin', () => {
  const w = clonedWorld(focusOpts());
  const head = git(w.root, 'rev-parse', BRANCH).trim();
  const done = pushedOf(w);
  assert.equal(done.state, 'done');
  assert.ok(done.detail.includes(head), done.detail);

  write(path.join(w.root, 'extra.txt'), 'one more\n');
  git(w.root, 'add', '-A');
  git(w.root, 'commit', '-q', '-m', 'ahead');
  const newHead = git(w.root, 'rev-parse', BRANCH).trim();
  const ahead = pushedOf(w);
  assert.equal(ahead.state, 'not_done');
  assert.ok(ahead.detail.includes(head) && ahead.detail.includes(newHead), ahead.detail);

  const never = clonedWorld(focusOpts(), { push: false });
  const absent = pushedOf(never);
  assert.equal(absent.state, 'not_done');
  assert.ok(absent.detail.includes('absent'), absent.detail);

  git(w.root, 'remote', 'remove', 'origin');
  const gone = pushedOf(w);
  assert.equal(gone.state, 'unknown');
  assert.ok(gone.detail.includes('no origin'), gone.detail);
});

// gh stub first on PATH: logs argv (one line per call), answers from files, writes nothing else.
function ghStub() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ride-status-gh-'));
  roots.push(dir);
  const bin = path.join(dir, 'bin');
  fs.mkdirSync(bin);
  const script = '#!/bin/sh\nprintf \'%s\\n\' "$*" >> "$GH_STUB_DIR/argv.log"\n'
    + 'if [ -f "$GH_STUB_DIR/rc" ]; then exit "$(cat "$GH_STUB_DIR/rc")"; fi\n'
    + 'cat "$GH_STUB_DIR/answer.json"\n';
  fs.writeFileSync(path.join(bin, 'gh'), script, { mode: 0o755 });
  return {
    dir,
    answer(text) { fs.rmSync(path.join(dir, 'rc'), { force: true }); fs.writeFileSync(path.join(dir, 'answer.json'), text); },
    fail(rc) { fs.writeFileSync(path.join(dir, 'rc'), String(rc)); },
    calls() { try { return fs.readFileSync(path.join(dir, 'argv.log'), 'utf8').split('\n').filter(Boolean); } catch { return []; } },
    env: { PATH: `${bin}${path.delimiter}${process.env.PATH}`, GH_STUB_DIR: dir },
  };
}

const prProbe = (w, stub) => {
  const r = run('node', [SCRIPT, 'probe', '--json', '--branch', BRANCH, '--state', w.statePath, '--root', w.root], w.root, stub.env);
  assert.equal(r.status, 0, r.stderr);
  return JSON.parse(r.stdout).effects.pr_open;
};

test('TEST-3153 pr_open: done with the listed number, not_done on an empty list, unknown on stub failure, skipped on platform none', () => {
  const w = clonedWorld(focusOpts());
  write(path.join(w.root, 'docs/ai/pr-config.yaml'), 'platform: github\n');
  const stub = ghStub();

  stub.answer('[{"number":41}]');
  const one = prProbe(w, stub);
  assert.equal(one.state, 'done');
  assert.deepEqual(one.prs, [41]);
  assert.ok(stub.calls().every((c) => c.includes(`--head ${BRANCH}`)), `head-branch list expected: ${stub.calls()}`);
  assert.ok(one.detail.includes('41'), one.detail);

  stub.answer('[]');
  assert.equal(prProbe(w, stub).state, 'not_done');

  stub.fail(1);
  assert.equal(prProbe(w, stub).state, 'unknown');

  const none = clonedWorld(focusOpts());
  write(path.join(none.root, 'docs/ai/pr-config.yaml'), 'platform: none\n');
  const quiet = ghStub();
  quiet.answer('[{"number":41}]');
  assert.equal(prProbe(none, quiet).state, 'skipped');
  assert.equal(quiet.calls().length, 0, 'platform none must not call the stub');
});

test('TEST-3154 the probe only reads: stub argv holds pr list --head calls and the bare origin refs do not change', () => {
  const w = clonedWorld(focusOpts());
  write(path.join(w.root, 'docs/ai/pr-config.yaml'), 'platform: github\n');
  const stub = ghStub();
  const refsBefore = git(w.origin, 'for-each-ref');
  const lsBefore = git(w.root, 'ls-remote', 'origin');
  for (const answer of ['[{"number":41}]', '[]']) { stub.answer(answer); prProbe(w, stub); }
  stub.fail(1); prProbe(w, stub);
  const calls = stub.calls();
  assert.equal(calls.length, 3);
  for (const c of calls) {
    assert.ok(c.startsWith('pr list '), c);
    assert.ok(c.includes(`--head ${BRANCH}`), c);
    assert.ok(!/\b(create|edit|merge|close|comment)\b/.test(c), c);
  }
  assert.equal(git(w.origin, 'for-each-ref'), refsBefore);
  assert.equal(git(w.root, 'ls-remote', 'origin'), lsBefore);
});

test('TEST-3155 closed and flushed come from the real ledgers; no focus gives not_applicable', () => {
  const ev = (o) => `${JSON.stringify({ ts: '2026-10-30T00:00:00Z', ...o })}\n`;
  const closeLine = ev({ event: 'work_item_closed', ref: REF, payload: {} });
  const reopenLine = ev({ event: 'doc_lifecycle', ref: REF, payload: { from: 'done', to: 'implementing' } });
  const effects = (w) => JSON.parse(probe(w, '--json', '--branch', BRANCH).stdout).effects;

  assert.equal(effects(world({ ...focusOpts(), events: closeLine })).closed.state, 'done');
  assert.equal(effects(world({ ...focusOpts(), events: closeLine + reopenLine })).closed.state, 'not_done');
  assert.equal(effects(world({ ...focusOpts(), events: reopenLine + closeLine })).closed.state, 'done');
  assert.equal(effects(world(focusOpts())).closed.state, 'not_done');

  const flushRecord = `${JSON.stringify({ ref_id: REF, date_utc: '2026-10-30', title: 'demo' })}\n`;
  assert.equal(effects(world({ ...focusOpts(), metrics: flushRecord })).flushed.state, 'done');
  assert.equal(effects(world(focusOpts())).flushed.state, 'not_done');

  const none = effects(world({ noFocus: true }));
  assert.equal(none.closed.state, 'not_applicable');
  assert.equal(none.flushed.state, 'not_applicable');
});

const shipInput = () => {
  const t = fs.readFileSync(path.join(REPO, '.aai', 'SKILL_SHIP.prompt.md'), 'utf8');
  return t.slice(t.indexOf('\nINPUT'), t.indexOf('ride-select.mjs show'));
};

test('TEST-3159 an invalid STATE reports ref_id null with blocker state_invalid, and SHIP INPUT stops on it before ride-select', () => {
  const bad = json(world({ ...focusOpts(), dupKey: true }));
  assert.equal(bad.ref_id, null);
  assert.equal(bad.blocker.kind, 'state_invalid');
  const none = json(world({ noFocus: true }));
  assert.equal(none.ref_id, null);
  assert.notEqual(none.blocker.kind, 'state_invalid');

  const input = shipInput();
  assert.ok(input.includes('state_invalid'), 'SKILL_SHIP INPUT must name blocker kind state_invalid');
  assert.ok(/STOP/.test(input.slice(input.indexOf('state_invalid'))), 'SKILL_SHIP INPUT must STOP on state_invalid');
});

test('TEST-3160 a ride whose probe reports closed done is not resumed: SHIP INPUT stops and points to /aai-merge', () => {
  const closeLine = `${JSON.stringify({ ts: '2026-10-30T00:00:00Z', event: 'work_item_closed', ref: REF, payload: {} })}\n`;
  const fx = world({ ...focusOpts(), events: closeLine });
  const effects = JSON.parse(probe(fx, '--json', '--branch', BRANCH).stdout).effects;
  assert.equal(effects.closed.state, 'done');

  const input = shipInput();
  assert.ok(input.includes('closed: done'), 'SKILL_SHIP INPUT must name the probe closed: done fact');
  assert.ok(input.includes('/aai-merge'), 'SKILL_SHIP INPUT must point to /aai-merge cleanup');
  assert.ok(input.indexOf('closed: done') < input.indexOf('RUN step 2') + 200, 'closed check sits with the resume rule');
});
