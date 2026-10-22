// ride-handoff.test.mjs — TEST-001..TEST-010 of spec-ride-state-handoff-to-worktree.
//
// Every test builds a throwaway git repository (git init -b main, its own
// user.email/user.name), a real `git worktree add`, and a worktree STATE made
// by the real check-state.mjs --repair. Nothing runs in the shipping tree.
// The script under test is overridable through RIDE_HANDOFF_SCRIPT.
// Test names start with their spec TEST id (the suite selects by that prefix).

import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..', '..');
const SCRIPT = process.env.RIDE_HANDOFF_SCRIPT || path.join(REPO, '.aai', 'scripts', 'ride-handoff.mjs');
const CHECK_STATE = path.join(REPO, '.aai', 'scripts', 'check-state.mjs');
const DISPATCH = path.join(REPO, '.aai', 'scripts', 'orchestration-dispatch.mjs');
const FLUSH = path.join(REPO, '.aai', 'scripts', 'metrics-flush.mjs');
const FIXTURES = path.join(REPO, 'tests', 'fixtures', 'ride-handoff');
const TEMPLATE = fs.readFileSync(path.join(REPO, '.aai', 'templates', 'STATE_TEMPLATE.yaml'), 'utf8');

const R = 'ride-demo';
const FOREIGN = ['foreign-alpha', 'foreign-beta'];
const INTAKE_REL = 'docs/issues/CHANGE-DRAFT-ride-demo.md';
const SPEC_REL = 'docs/specs/SPEC-DRAFT-spec-ride-demo.md';
const BRIEF_REL = 'docs/ai/briefs/ride-demo.md';

const fx = (name) => fs.readFileSync(path.join(FIXTURES, name), 'utf8');
const ORIGIN_STATE = fx('STATE.origin.yaml');
const LEDGER_FULL = fx('METRICS.jsonl');

const roots = [];
after(() => { for (const r of roots) fs.rmSync(r, { recursive: true, force: true }); });

function absolute(p) {
  assert.ok(typeof p === 'string' && p !== '' && path.isAbsolute(p), `path must be absolute and non-empty: ${JSON.stringify(p)}`);
  return p;
}

function cleanEnv(extra = {}) {
  const env = { ...process.env };
  delete env.AAI_ROLE;
  delete env.AAI_RIDE_HANDOFF_INJECT_CRASH;
  Object.assign(env, {
    GIT_AUTHOR_NAME: 'AAI Fixture', GIT_AUTHOR_EMAIL: 'fixture@example.invalid',
    GIT_COMMITTER_NAME: 'AAI Fixture', GIT_COMMITTER_EMAIL: 'fixture@example.invalid',
    GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1',
  });
  for (const [k, v] of Object.entries(extra)) { if (v === undefined) delete env[k]; else env[k] = v; }
  return env;
}

function run(cmd, args, cwd, extraEnv = {}) {
  absolute(cwd);
  const r = spawnSync(cmd, args, { cwd, encoding: 'utf8', env: cleanEnv(extraEnv), maxBuffer: 64 * 1024 * 1024 });
  return { status: r.status, signal: r.signal, stdout: r.stdout ?? '', stderr: r.stderr ?? '' };
}

function git(cwd, ...args) {
  const r = run('git', args, cwd);
  assert.equal(r.status, 0, `git ${args.join(' ')} failed: ${r.stderr}`);
  return r.stdout;
}

const sha = (file) => (fs.existsSync(file) ? crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex') : 'absent');
const write = (file, text) => { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, text); };
const lines = (t) => t.replace(/\r\n/g, '\n').split('\n');
const count = (text, needle) => lines(text).filter((l) => l.includes(needle)).length;

// --- independent STATE readers (never the code under test) --------------------

function topBlock(text, key) {
  const L = lines(text);
  const i = L.findIndex((l) => l.startsWith(`${key}:`));
  if (i < 0) return null;
  let j = i + 1;
  while (j < L.length && !/^[A-Za-z_][\w-]*:/.test(L[j])) j += 1;
  while (j > i + 1 && L[j - 1].trim() === '') j -= 1;
  return L.slice(i, j).join('\n');
}

function entryText(text, key) {
  const L = lines(text);
  const i = L.findIndex((l) => l.trimEnd() === `    ${key}:`);
  if (i < 0) return null;
  let j = i + 1;
  while (j < L.length && (L[j].trim() === '' || /^ {6,}/.test(L[j]))) j += 1;
  while (j > i + 1 && L[j - 1].trim() === '') j -= 1;
  return L.slice(i, j).join('\n');
}

function itemText(text, key) {
  const L = lines(text);
  const i = L.findIndex((l) => l === `  - ref_id: ${key}`);
  if (i < 0) return null;
  let j = i + 1;
  while (j < L.length && /^ {4}\S/.test(L[j])) j += 1;
  return L.slice(i, j).join('\n');
}

const runsOf = (text, key) => { const e = entryText(text, key); return e === null ? 0 : (e.match(/^ {8}- role:/gm) ?? []).length; };
const allRuns = (text) => (text.match(/^ {8}- role:/gm) ?? []).length;
const templateBlock = (key) => topBlock(TEMPLATE, key);

// --- world ----------------------------------------------------------------------

function ledgerFor(kind) {
  if (kind === 'full') return LEDGER_FULL;
  if (kind === 'first-only') {
    const j = JSON.parse(LEDGER_FULL.trim());
    j.agent_runs = j.agent_runs.slice(0, 1);
    return `${JSON.stringify(j)}\n`;
  }
  if (kind === 'wrong-started') {
    const j = JSON.parse(LEDGER_FULL.trim());
    j.agent_runs[1].started_utc = '2026-10-22T16:31:13Z';
    return `${JSON.stringify(j)}\n`;
  }
  return '';
}

const CLOSED_EVENT = `{"v":1,"ts":"2026-10-22T17:30:00.000Z","actor":"fixture","event":"work_item_closed","ref":"${R}","payload":{"validation":"pass","code_review":"pass"}}\n`;

function world(opts = {}) {
  const o = { state: ORIGIN_STATE, ledger: 'empty', drafts: 'untracked', stateMjs: false, events: '', worktree: true, ...opts };
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'ride-handoff-')));
  roots.push(root);
  const origin = absolute(path.join(root, 'origin'));
  const wt = absolute(path.join(root, 'wt'));
  fs.mkdirSync(origin, { recursive: true });
  git(origin, 'init', '-q', '-b', 'main');
  git(origin, 'config', 'user.email', 'fixture@example.invalid');
  git(origin, 'config', 'user.name', 'AAI Fixture');
  write(path.join(origin, 'README.md'), 'fixture\n');
  write(path.join(origin, '.gitignore'), 'docs/ai/STATE.yaml\ndocs/ai/archive/**\ndocs/ai/briefs/**\n');
  write(path.join(origin, 'docs/ai/EVENTS.jsonl'), o.events);
  write(path.join(origin, 'docs/ai/METRICS.jsonl'), ledgerFor(o.ledger));
  write(path.join(origin, 'docs/TECHNOLOGY.md'), '# Technology\n');
  write(path.join(origin, '.aai/workflow/WORKFLOW.md'), '# Workflow\n');
  write(path.join(origin, '.aai/system/LOCKS.md'), '# Locks\n');
  if (o.stateMjs) write(path.join(origin, '.aai/scripts/state.mjs'), '// fixture marker: an AAI project root\n');
  if (o.drafts === 'tracked-before') {
    write(path.join(origin, INTAKE_REL), fx('INTAKE.md'));
    write(path.join(origin, SPEC_REL), fx('SPEC.md'));
  }
  git(origin, 'add', '-A');
  git(origin, 'commit', '-q', '-m', 'baseline');
  if (o.worktree) git(origin, 'worktree', 'add', '-q', '-b', 'change/ride-demo', wt, 'main');
  if (o.drafts === 'tracked-after') {
    write(path.join(origin, INTAKE_REL), fx('INTAKE.md'));
    write(path.join(origin, SPEC_REL), fx('SPEC.md'));
    git(origin, 'add', INTAKE_REL, SPEC_REL);
    git(origin, 'commit', '-q', '-m', 'track drafts');
  }
  if (o.drafts === 'untracked') {
    write(path.join(origin, INTAKE_REL), fx('INTAKE.md'));
    write(path.join(origin, SPEC_REL), fx('SPEC.md'));
  }
  if (o.drafts !== 'none') write(path.join(origin, BRIEF_REL), fx('BRIEF.md'));
  const oState = path.join(origin, 'docs/ai/STATE.yaml');
  write(oState, o.state);
  const wState = path.join(wt, 'docs/ai/STATE.yaml');
  if (o.worktree) {
    fs.mkdirSync(path.join(wt, 'docs/ai'), { recursive: true });
    const rep = run(process.execPath, [CHECK_STATE, '--repair'], wt);
    assert.equal(rep.status, 0, `check-state --repair failed: ${rep.stdout}${rep.stderr}`);
    assert.ok(fs.existsSync(wState), 'fresh worktree STATE was not created');
  }
  return { root, origin, wt, oState, wState };
}

function handoff(w, args, extraEnv = {}) {
  return run(process.execPath, [SCRIPT, ...args], w.origin, extraEnv);
}
function out(w, extra = [], extraEnv = {}) {
  return handoff(w, ['out', '--ref', R, '--worktree', w.wt, '--state', w.oState, ...extra], extraEnv);
}
function reconcile(w, extra = [], ref = R) {
  return handoff(w, ['reconcile', '--ref', ref, '--state', w.oState, '--metrics', path.join(w.origin, 'docs/ai/METRICS.jsonl'), ...extra]);
}
const handoffDirs = (w) => {
  const d = path.join(w.origin, 'docs/ai/archive/handoffs');
  return fs.existsSync(d) ? fs.readdirSync(d).sort().map((n) => path.join(d, n)) : [];
};
const read = (f) => fs.readFileSync(f, 'utf8');

function okOut(w, extra = [], extraEnv = {}) {
  const r = out(w, extra, extraEnv);
  assert.equal(r.status, 0, `out failed (${r.status}): ${r.stdout}${r.stderr}`);
  return r;
}

// ---------------------------------------------------------------------------------

test('TEST-001 out splices ride R into the fresh worktree STATE and nothing foreign', () => {
  const w = world();
  const before = read(w.oState);
  const fresh = read(w.wState);
  assert.equal(count(fresh, R), 0, 'control: the fresh worktree STATE names no ride');
  assert.ok(FOREIGN.every((f) => count(before, f) > 0), 'control: the origin names both foreign refs');
  const r = okOut(w);
  assert.match(r.stdout, /^HANDOFF /m);
  const after = read(w.wState);
  for (const key of ['current_focus', 'implementation_strategy', 'code_review', 'last_validation']) {
    assert.equal(topBlock(after, key), topBlock(before, key), `${key} block is verbatim the origin's`);
  }
  assert.equal(itemText(after, R), itemText(before, R));
  assert.notEqual(itemText(after, R), null);
  assert.equal(entryText(after, R), entryText(before, R));
  assert.notEqual(entryText(after, R), null);
  assert.match(topBlock(after, 'code_review'), /scope_ref_id: ride-demo/);
  for (const f of FOREIGN) assert.equal(count(after, f), 0, `zero lines naming ${f} in the worktree STATE`);
  assert.equal(topBlock(after, 'tdd_cycle'), null, 'a foreign tdd_cycle is not carried');
  assert.equal(topBlock(after, 'worktree').includes('foreign'), false);
  assert.match(topBlock(after, 'worktree'), /user_decision: worktree/);
  assert.match(topBlock(after, 'worktree'), /branch: change\/ride-demo/);
  assert.match(topBlock(after, 'worktree'), /recommendation: recommended/);
  assert.match(topBlock(after, 'worktree'), /Demo ride is PR-bound/);
});

test('TEST-001 an R-owned tdd_cycle moves too; a foreign one stays', () => {
  const state = ORIGIN_STATE.replace('spec_path: docs/specs/SPEC-0900-foreign-alpha.md\n  test_path', `spec_path: ${SPEC_REL}\n  test_path`);
  assert.notEqual(state, ORIGIN_STATE);
  const w = world({ state });
  okOut(w);
  assert.equal(topBlock(read(w.wState), 'tdd_cycle'), topBlock(state, 'tdd_cycle'));
  assert.equal(topBlock(read(w.oState), 'tdd_cycle'), 'tdd_cycle:\n  status: IDLE\n  test_id: null\n  spec_path: null\n  test_path: null\n  evidence:\n    red: null\n    green: null\n    refactor: null');
});

test('TEST-002 origin keeps every foreign byte, loses R, and the archive holds the pre-file', () => {
  const w = world();
  const before = read(w.oState);
  const preSha = sha(w.oState);
  const dry = out(w, ['--dry-run']);
  assert.equal(dry.status, 0, `dry-run: ${dry.stdout}${dry.stderr}`);
  assert.match(dry.stdout, /^HANDOFF /m);
  assert.equal(sha(w.oState), preSha, 'dry-run writes nothing to the origin');
  assert.equal(handoffDirs(w).length, 0, 'dry-run creates no archive');
  assert.equal(topBlock(read(w.wState), 'current_focus'), templateBlock('current_focus'), 'dry-run writes nothing to the worktree');
  okOut(w);
  const after = read(w.oState);
  assert.notEqual(sha(w.oState), preSha, 'control: the origin STATE did change');
  for (const f of FOREIGN) {
    assert.equal(entryText(after, f), entryText(before, f), `${f} metrics entry byte-identical`);
    assert.equal(itemText(after, f), itemText(before, f), `${f} active item byte-identical`);
  }
  assert.equal(entryText(after, R), null);
  assert.equal(itemText(after, R), null);
  assert.equal(count(after, `ref_id: ${R}`), 0);
  assert.equal(topBlock(after, 'current_focus'), 'current_focus:\n  type: none\n  ref_id: null\n  primary_path: null\n  spec_path: null');
  for (const key of ['implementation_strategy', 'code_review', 'last_validation']) {
    assert.equal(topBlock(after, key), templateBlock(key), `${key} reset to template values`);
  }
  assert.equal(topBlock(after, 'worktree'), topBlock(before, 'worktree'), 'a worktree block naming another ride is kept');
  assert.equal(topBlock(after, 'tdd_cycle'), topBlock(before, 'tdd_cycle'), 'a foreign tdd_cycle is kept');
  const dirs = handoffDirs(w);
  assert.equal(dirs.length, 1);
  assert.match(path.basename(dirs[0]), /^ride-demo-\d{8}T\d{6}Z/);
  const archived = fs.readdirSync(dirs[0]).filter((n) => n.endsWith('.yaml'));
  assert.equal(archived.length, 1);
  assert.equal(sha(path.join(dirs[0], archived[0])), preSha, 'archive is a byte copy of the pre-handoff origin STATE');
  const rec = JSON.parse(read(path.join(dirs[0], 'record.json')));
  assert.equal(rec.status, 'done');
  assert.equal(rec.ref, R);
  assert.equal(rec.runs_moved, 2);
  assert.equal(rec.branch, 'change/ride-demo');
  assert.equal(rec.base_ref, 'main');
  assert.equal(fs.realpathSync(rec.worktree), w.wt);
});

test('TEST-002 an origin worktree block that names this worktree is reset', () => {
  const state = ORIGIN_STATE.replace('branch: change/foreign-beta', 'branch: change/ride-demo').replace('/var/empty/foreign-beta-worktree', 'PLACEHOLDER');
  const w = world({ state });
  const patched = state.replace('PLACEHOLDER', w.wt);
  write(w.oState, patched);
  okOut(w);
  assert.equal(topBlock(read(w.oState), 'worktree'), templateBlock('worktree'));
});

test('TEST-003 the run count is conserved: moved, not copied', () => {
  const w = world();
  const before = read(w.oState);
  const rBefore = runsOf(before, R);
  const foreignBefore = FOREIGN.reduce((n, f) => n + runsOf(before, f), 0);
  assert.equal(rBefore, 2);
  assert.equal(foreignBefore, 3);
  okOut(w);
  const o = read(w.oState);
  const t = read(w.wState);
  assert.equal(runsOf(t, R), rBefore);
  assert.equal(runsOf(o, R), 0);
  assert.equal(allRuns(t), rBefore, 'the worktree holds only R runs');
  assert.equal(FOREIGN.reduce((n, f) => n + runsOf(o, f), 0), foreignBefore);
  assert.equal(allRuns(o), foreignBefore);
  assert.equal(allRuns(o) + allRuns(t), allRuns(before));
});

test('TEST-003 edge shapes: zero runs, focus only, item only', () => {
  // an R entry that carries no runs moves as is, runs_moved 0
  const zero = ORIGIN_STATE.replace(/ {6}agent_runs:\n(?: {8}.*\n| {10}.*\n)+(?= {4}foreign-beta:)/, '      agent_runs: []\n');
  assert.equal(runsOf(zero, R), 0);
  assert.ok(zero.includes('      agent_runs: []'));
  const wz = world({ state: zero });
  okOut(wz);
  assert.equal(JSON.parse(read(path.join(handoffDirs(wz)[0], 'record.json'))).runs_moved, 0);
  assert.equal(entryText(read(wz.wState), R), entryText(zero, R));
  assert.equal(entryText(read(wz.oState), R), null);
  // focus is R, no active item and no metrics entry: only the focus moves
  const focusOnly = ORIGIN_STATE
    .replace(/ {2}- ref_id: ride-demo\n(?: {4}.*\n)+/, '')
    .replace(/ {4}ride-demo:\n(?: {6}.*\n| {8}.*\n| {10}.*\n)+(?= {4}foreign-beta:)/, '');
  assert.equal(itemText(focusOnly, R), null);
  assert.equal(entryText(focusOnly, R), null);
  const wf = world({ state: focusOnly });
  okOut(wf);
  assert.match(topBlock(read(wf.wState), 'current_focus'), /ref_id: ride-demo/);
  assert.equal(allRuns(read(wf.wState)), 0);
  assert.equal(JSON.parse(read(path.join(handoffDirs(wf)[0], 'record.json'))).runs_moved, 0);
  assert.equal(topBlock(read(wf.oState), 'current_focus').includes('none'), true);
  // item and entry for R while the focus is another ref: item and entry move, focus stays
  const otherFocus = ORIGIN_STATE.replace(/current_focus:\n(?: {2}.*\n)+/, 'current_focus:\n  type: intake_change\n  ref_id: foreign-alpha\n  primary_path: null\n  spec_path: null\n');
  const wo = world({ state: otherFocus });
  okOut(wo);
  assert.equal(itemText(read(wo.wState), R), itemText(otherFocus, R));
  assert.equal(topBlock(read(wo.wState), 'current_focus'), templateBlock('current_focus'));
  assert.equal(topBlock(read(wo.oState), 'current_focus'), topBlock(otherFocus, 'current_focus'));
  assert.equal(runsOf(read(wo.wState), R), 2);
  assert.equal(runsOf(read(wo.oState), R), 0);
});

function dispatchOf(root, statePath) {
  const r = run(process.execPath, [DISPATCH, '--state', statePath, '--root', root], root);
  let j;
  try { j = JSON.parse(r.stdout); } catch { assert.fail(`dispatcher printed no JSON: ${r.stdout}${r.stderr}`); }
  return { rule: j.rule, role: j.role ?? null, verdict: j.verdict, reasons: j.reasons ?? [] };
}

test('TEST-004 check-state is clean on both files and the real dispatcher agrees on both sides', () => {
  const shapes = [
    ['planned focus', fx('SPEC.md')],
    ['frozen spec', fx('SPEC.md').replace('# Demo ride spec', '# Demo ride spec\n\nSPEC-FROZEN: true')],
  ];
  const seen = new Set();
  for (const [label, specText] of shapes) {
    const w = world();
    write(path.join(w.origin, SPEC_REL), specText);
    const beforeD = dispatchOf(w.origin, w.oState);
    // the worktree is named through a symlink: the registered (real) path must still be recognised
    const link = absolute(path.join(w.root, 'wt-link'));
    fs.symlinkSync(w.wt, link);
    const r = handoff(w, ['out', '--ref', R, '--worktree', link, '--state', w.oState]);
    assert.equal(r.status, 0, `${label}: out through a symlinked worktree path: ${r.stdout}${r.stderr}`);
    assert.match(read(w.wState), new RegExp(`^  path: ${w.wt.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'm'), `${label}: the recorded worktree path is the real one`);
    for (const f of [w.oState, w.wState]) {
      const c = run(process.execPath, [CHECK_STATE, f], w.origin);
      assert.equal(c.status, 0, `${label}: check-state on ${f}: ${c.stdout}${c.stderr}`);
    }
    const afterD = dispatchOf(w.wt, w.wState);
    assert.equal(afterD.rule, beforeD.rule, `${label}: same rule`);
    assert.equal(afterD.role, beforeD.role, `${label}: same role`);
    assert.notEqual(beforeD.role, null, `${label}: control, the origin dispatcher named a role`);
    seen.add(`${beforeD.rule}/${beforeD.role}`);
  }
  assert.equal(seen.size, 2, 'the two fixtures exercise different dispatcher outcomes');
});

function flushPlan(root, statePath, extra = []) {
  const d = path.join(root, 'docs', 'ai');
  const r = run(process.execPath, [FLUSH, '--dry-run', '--state', statePath, '--metrics', path.join(d, 'METRICS.jsonl'),
    '--events', path.join(d, 'EVENTS.jsonl'), '--ticks', path.join(d, 'LOOP_TICKS.jsonl'), ...extra], root);
  assert.equal(r.status, 0, `metrics-flush --dry-run ${extra.join(' ')}: ${r.stdout}${r.stderr}`);
  const plan = JSON.parse(r.stdout);
  return new Set([...plan.flush, ...plan.swept, ...plan.resume, ...Object.keys(plan.skipped)]);
}

test('TEST-005 an unrestricted flush or sweep in the worktree can only name R', () => {
  const w = world({ events: CLOSED_EVENT });
  // negative control first (it holds on the baseline too): the whole-file copy of the same origin STATE names foreign refs
  const copy = world({ events: CLOSED_EVENT });
  for (const extra of [[], ['--sweep']]) {
    const whole = flushPlan(copy.origin, copy.oState, extra);
    assert.ok(FOREIGN.some((f) => whole.has(f)), `control: a whole-STATE copy names a foreign ref ${extra.join(' ')}`);
  }
  okOut(w);
  for (const extra of [[], ['--sweep']]) {
    const mine = flushPlan(w.wt, w.wState, extra);
    assert.deepEqual([...mine], [R], `worktree plan ${extra.join(' ')} names exactly R`);
  }
});

test('TEST-006 drafts are carried, archived, never moved when tracked, conflicts refused', () => {
  const w = world();
  const intake = sha(path.join(w.origin, INTAKE_REL));
  const spec = sha(path.join(w.origin, SPEC_REL));
  const brief = sha(path.join(w.origin, BRIEF_REL));
  okOut(w);
  assert.equal(sha(path.join(w.wt, INTAKE_REL)), intake);
  assert.equal(sha(path.join(w.wt, SPEC_REL)), spec);
  assert.equal(sha(path.join(w.wt, BRIEF_REL)), brief);
  for (const rel of [INTAKE_REL, SPEC_REL, BRIEF_REL]) {
    assert.equal(fs.existsSync(path.join(w.origin, rel)), false, `${rel} left the origin`);
    assert.ok(fs.existsSync(path.join(handoffDirs(w)[0], 'drafts', rel)), `${rel} sits in the archive`);
  }
  assert.equal(sha(path.join(handoffDirs(w)[0], 'drafts', SPEC_REL)), spec);
  assert.equal(JSON.parse(read(path.join(handoffDirs(w)[0], 'record.json'))).drafts_moved, 3);

  // tracked in the origin and already in the worktree branch: never moved
  const tb = world({ drafts: 'tracked-before' });
  okOut(tb);
  assert.ok(fs.existsSync(path.join(tb.origin, INTAKE_REL)));
  assert.ok(fs.existsSync(path.join(tb.origin, SPEC_REL)));
  assert.equal(fs.existsSync(path.join(tb.origin, BRIEF_REL)), false, 'the untracked brief still moves');
  assert.equal(fs.existsSync(path.join(handoffDirs(tb)[0], 'drafts', INTAKE_REL)), false);

  // tracked in the origin only: copied into the worktree, origin copy stays
  const ta = world({ drafts: 'tracked-after' });
  assert.equal(fs.existsSync(path.join(ta.wt, SPEC_REL)), false, 'control: the worktree lacks the tracked file');
  okOut(ta);
  assert.equal(sha(path.join(ta.wt, SPEC_REL)), spec);
  assert.ok(fs.existsSync(path.join(ta.origin, SPEC_REL)));

  // a byte-identical copy already in the worktree is accepted
  const same = world();
  write(path.join(same.wt, SPEC_REL), fx('SPEC.md'));
  okOut(same);

  // a differing copy in the worktree is a conflict: refusal, nothing changed
  const c = world();
  write(path.join(c.wt, SPEC_REL), 'a different spec\n');
  const o0 = sha(c.oState);
  const w0 = sha(c.wState);
  const r = out(c);
  assert.equal(r.status, 1);
  assert.match(r.stdout, /^REFUSE draft_conflict /m);
  assert.equal(sha(c.oState), o0);
  assert.equal(sha(c.wState), w0);
  assert.equal(handoffDirs(c).length, 0);
  assert.ok(fs.existsSync(path.join(c.origin, SPEC_REL)), 'the origin draft stays');
  assert.equal(read(path.join(c.wt, SPEC_REL)), 'a different spec\n');
});

test('TEST-007 every refusal exits 1 with its reason and writes nothing; a subagent is refused on a shipping STATE', () => {
  const cases = [];
  const base = () => world();
  {
    const w = base();
    cases.push(['ref_not_in_origin', w, ['out', '--ref', 'no-such-ride', '--worktree', w.wt, '--state', w.oState]]);
  }
  {
    const w = base();
    const plain = absolute(path.join(w.root, 'plain'));
    write(path.join(plain, 'docs/ai/STATE.yaml'), TEMPLATE);
    cases.push(['worktree_not_registered', w, ['out', '--ref', R, '--worktree', plain, '--state', w.oState]]);
  }
  {
    const w = base();
    write(w.wState, ORIGIN_STATE);
    cases.push(['worktree_state_not_fresh', w, null]);
  }
  {
    const w = base();
    fs.rmSync(w.wState);
    cases.push(['worktree_state_not_fresh', w, null]);
  }
  {
    const w = world({ state: ORIGIN_STATE.replace('\nupdated_at_utc:', '\nhuman_input:\n  required: true\n  question: pick\nupdated_at_utc:') });
    cases.push(['hitl_pending', w, null]);
  }
  {
    const w = base();
    write(path.join(w.wt, SPEC_REL), 'a different spec\n');
    cases.push(['draft_conflict', w, null]);
  }
  for (const [reason, w, args] of cases) {
    const o0 = sha(w.oState);
    const w0 = sha(w.wState);
    const r = args ? handoff(w, args) : out(w);
    assert.equal(r.status, 1, `${reason}: exit ${r.status} ${r.stdout}${r.stderr}`);
    assert.match(r.stdout, new RegExp(`^REFUSE ${reason}\\b`, 'm'));
    assert.equal(sha(w.oState), o0, `${reason}: origin STATE unchanged`);
    assert.equal(sha(w.wState), w0, `${reason}: worktree STATE unchanged`);
    assert.equal(handoffDirs(w).length, 0, `${reason}: no archive`);
  }
  // single-writer guard: AAI_ROLE=subagent against a tree that has .aai/scripts/state.mjs
  const g = world({ stateMjs: true });
  const go = sha(g.oState);
  const gw = sha(g.wState);
  const refused = out(g, [], { AAI_ROLE: 'subagent' });
  assert.equal(refused.status, 3, `${refused.stdout}${refused.stderr}`);
  assert.equal(sha(g.oState), go);
  assert.equal(sha(g.wState), gw);
  assert.equal(handoffDirs(g).length, 0);
  // control: the same marker against a plain scratch STATE is unaffected
  const plain = world();
  const allowed = out(plain, [], { AAI_ROLE: 'subagent' });
  assert.equal(allowed.status, 0, `${allowed.stdout}${allowed.stderr}`);
  assert.match(allowed.stdout, /^HANDOFF /m);
  // control: without the marker the guarded fixture proceeds
  assert.equal(out(g).status, 0);
});

test('TEST-008 an interrupted out resumes: RESUMED, runs conserved, record done', () => {
  const w = world();
  const before = read(w.oState);
  const crashed = out(w, [], { AAI_RIDE_HANDOFF_INJECT_CRASH: 'after-worktree-write' });
  assert.notEqual(crashed.status, 0, 'the injected crash exits non-zero');
  assert.equal(runsOf(read(w.wState), R), 2, 'control: R runs are in the worktree');
  assert.equal(runsOf(read(w.oState), R), 2, 'control: R runs are still in the origin');
  assert.equal(JSON.parse(read(path.join(handoffDirs(w)[0], 'record.json'))).status, 'started');
  assert.ok(fs.existsSync(path.join(w.origin, SPEC_REL)), 'control: the origin draft has not moved yet');
  const r = okOut(w);
  assert.match(r.stdout, /^RESUMED /m);
  assert.equal(runsOf(read(w.wState), R), 2);
  assert.equal(runsOf(read(w.oState), R), 0);
  assert.equal(allRuns(read(w.oState)) + allRuns(read(w.wState)), allRuns(before));
  assert.equal(handoffDirs(w).length, 1, 'the resume reuses the archive directory');
  assert.equal(JSON.parse(read(path.join(handoffDirs(w)[0], 'record.json'))).status, 'done');
  assert.equal(fs.existsSync(path.join(w.origin, SPEC_REL)), false);
  assert.equal(sha(path.join(w.wt, SPEC_REL)), sha(path.join(handoffDirs(w)[0], 'drafts', SPEC_REL)));
  // a clean run never prints RESUMED
  const clean = world();
  assert.doesNotMatch(okOut(clean).stdout, /RESUMED/);
});

// --- reconcile --------------------------------------------------------------------

test('TEST-009 reconcile heals the M1-shaped origin; flush and dispatcher then behave', () => {
  const w = world({ ledger: 'full', events: CLOSED_EVENT, drafts: 'none', worktree: false });
  const before = read(w.oState);
  const d0 = dispatchOf(w.origin, w.oState);
  assert.ok(d0.reasons.includes('closed_focus_stale_state'), `control: the stale origin is detected ${JSON.stringify(d0)}`);
  const r = reconcile(w);
  assert.equal(r.status, 0, `${r.stdout}${r.stderr}`);
  assert.match(r.stdout, /^RECONCILED /m);
  const after = read(w.oState);
  assert.equal(entryText(after, R), null);
  assert.equal(itemText(after, R), null);
  assert.equal(count(after, `ref_id: ${R}`), 0);
  assert.equal(topBlock(after, 'current_focus').includes('type: none'), true);
  for (const f of FOREIGN) {
    assert.equal(entryText(after, f), entryText(before, f));
    assert.equal(itemText(after, f), itemText(before, f));
  }
  assert.equal(topBlock(after, 'worktree'), topBlock(before, 'worktree'), 'no --branch: the worktree block is kept');
  assert.equal(handoffDirs(w).length, 1);
  assert.match(path.basename(handoffDirs(w)[0]), /^ride-demo-reconcile-\d{8}T\d{6}Z/);
  const ledger = path.join(w.origin, 'docs/ai/METRICS.jsonl');
  assert.equal(count(read(ledger), `"ref_id":"${R}"`), 1);
  const d = path.join(w.origin, 'docs', 'ai');
  for (const extra of [[], ['--sweep']]) {
    const f = run(process.execPath, [FLUSH, '--state', w.oState, '--metrics', ledger, '--events', path.join(d, 'EVENTS.jsonl'),
      '--ticks', path.join(d, 'LOOP_TICKS.jsonl'), ...extra], w.origin);
    assert.equal(f.status, 0, `metrics-flush ${extra.join(' ')}: ${f.stdout}${f.stderr}`);
    assert.equal(count(read(ledger), `"ref_id":"${R}"`), 1, `flush ${extra.join(' ')} adds no second METRICS line`);
  }
  const d1 = dispatchOf(w.origin, w.oState);
  assert.equal(d1.reasons.includes('closed_focus_stale_state'), false);
  // --branch resets the worktree block that names the ride branch
  const b = world({ ledger: 'full', events: CLOSED_EVENT, drafts: 'none', worktree: false, state: ORIGIN_STATE.replace('branch: change/foreign-beta', 'branch: change/ride-demo') });
  const rb = reconcile(b, ['--branch', 'change/ride-demo']);
  assert.equal(rb.status, 0, `${rb.stdout}${rb.stderr}`);
  assert.equal(topBlock(read(b.oState), 'worktree'), templateBlock('worktree'));
  // a trace with no runs reconciles without any ledger entry
  const focusOnly = world({ ledger: 'empty', drafts: 'none', worktree: false, state: ORIGIN_STATE.replace(/ {6}agent_runs:\n(?: {8}.*\n| {10}.*\n)+(?= {4}foreign-beta:)/, '      agent_runs: []\n') });
  const rf = reconcile(focusOnly);
  assert.equal(rf.status, 0, `${rf.stdout}${rf.stderr}`);
  assert.match(rf.stdout, /^RECONCILED /m);
});

test('TEST-010 reconcile refuses unledgered runs and no-ops without a trace', () => {
  for (const ledger of ['first-only', 'empty', 'wrong-started']) {
    const w = world({ ledger, drafts: 'none', worktree: false });
    const s0 = sha(w.oState);
    const r = reconcile(w);
    assert.equal(r.status, 1, `${ledger}: ${r.stdout}${r.stderr}`);
    assert.match(r.stdout, /^REFUSE origin_runs_not_in_ledger\b/m);
    assert.equal(sha(w.oState), s0, `${ledger}: origin STATE unchanged`);
    assert.equal(handoffDirs(w).length, 0, `${ledger}: no archive`);
  }
  const w = world({ ledger: 'full', drafts: 'none', worktree: false });
  const s0 = sha(w.oState);
  const none = reconcile(w, [], 'ghost-ride');
  assert.equal(none.status, 0, `${none.stdout}${none.stderr}`);
  assert.match(none.stdout, /^NOOP no_trace ghost-ride/m);
  assert.equal(sha(w.oState), s0);
  assert.equal(handoffDirs(w).length, 0, 'no archive directory is created');
  // positive control: the same fixture is read and a ref with a trace is acted on
  const real = reconcile(w);
  assert.match(real.stdout, /^RECONCILED ride-demo\b/m);
  assert.notEqual(sha(w.oState), s0);
  // a second reconcile finds no trace left
  const again = reconcile(w);
  assert.match(again.stdout, /^NOOP no_trace ride-demo/m);
});

// --- remediation regressions (code review NB-1..NB-3) -------------------------------

test('TEST-010 reconcile fails closed on a run item whose first key is not role', () => {
  const swapped = ORIGIN_STATE
    .replace('        - role: Planning\n          model_id: claude-opus-5-5\n          started_utc: 2026-10-22T16:18:38Z\n',
      '        - started_utc: 2026-10-22T16:18:38Z\n          role: Planning\n          model_id: claude-opus-5-5\n')
    .replace('        - role: TDD Implementation\n          model_id: claude-sonnet-5-5\n          started_utc: 2026-10-22T16:30:13Z\n',
      '        - model_id: claude-sonnet-5-5\n          started_utc: 2026-10-22T16:30:13Z\n          role: TDD Implementation\n');
  assert.notEqual(swapped, ORIGIN_STATE, 'control: the fixture was rewritten');
  assert.equal(runsOf(swapped, R), 0, 'control: no item starts with role');
  const w = world({ state: swapped, ledger: 'empty', drafts: 'none', worktree: false });
  const s0 = sha(w.oState);
  const r = reconcile(w);
  assert.equal(r.status, 1, `${r.stdout}${r.stderr}`);
  assert.match(r.stdout, /^REFUSE origin_runs_not_in_ledger\b/m);
  assert.equal(sha(w.oState), s0, 'origin STATE unchanged');
  assert.equal(handoffDirs(w).length, 0, 'no archive');
  // an item with no role at all is unparseable and refused as well
  const norole = ORIGIN_STATE.replace('        - role: Planning\n          model_id: claude-opus-5-5\n          started_utc: 2026-10-22T16:18:38Z\n',
    '        - model_id: claude-opus-5-5\n          started_utc: 2026-10-22T16:18:38Z\n');
  const n = world({ state: norole, ledger: 'full', drafts: 'none', worktree: false });
  const n0 = sha(n.oState);
  const rn = reconcile(n);
  assert.equal(rn.status, 1, `${rn.stdout}${rn.stderr}`);
  assert.match(rn.stdout, /^REFUSE origin_runs_not_in_ledger\b/m);
  assert.equal(sha(n.oState), n0);
  // positive control: the swapped shape with the full ledger is held and reconciles
  const ok = world({ state: swapped, ledger: 'full', drafts: 'none', worktree: false });
  const rok = reconcile(ok);
  assert.equal(rok.status, 0, `${rok.stdout}${rok.stderr}`);
  assert.match(rok.stdout, /^RECONCILED ride-demo cleared=2\b/m);
});

test('TEST-007 an engine-unwritable worktree STATE refuses cleanly and leaves nothing behind', () => {
  const w = world();
  const bare = read(w.wState).replace(/^metrics:\n(?: {2}.*\n|\n)*?(?=updated_at_utc:)/m, 'metrics: {}\n');
  assert.match(bare, /^metrics: \{\}$/m, 'control: the worktree metrics header is inline');
  write(w.wState, bare);
  const o0 = sha(w.oState);
  const w0 = sha(w.wState);
  const r = out(w);
  const verdict = r.status === 0 ? 'ok' : `${r.status}`;
  if (verdict === 'ok') {
    assert.equal(run(process.execPath, [CHECK_STATE, w.wState], w.wt).status, 0);
    assert.equal(JSON.parse(read(path.join(handoffDirs(w)[0], 'record.json'))).status, 'done');
  } else {
    assert.equal(r.status, 1, `${r.stdout}${r.stderr}`);
    assert.match(r.stdout, /^REFUSE worktree_state_not_fresh\b/m);
    assert.equal(sha(w.oState), o0);
    assert.equal(sha(w.wState), w0);
    assert.equal(handoffDirs(w).length, 0, 'no started record, no archive');
    assert.equal(fs.existsSync(path.join(w.wt, SPEC_REL)), false, 'no copied draft');
    assert.ok(fs.existsSync(path.join(w.origin, SPEC_REL)), 'the origin draft stays');
  }
});

test('TEST-001 a worktree STATE with work_items: [] receives the entry as valid block form', () => {
  const w = world();
  const L = read(w.wState);
  assert.match(L, /^ {2}work_items:$/m, 'control: the repaired worktree STATE has a bare work_items header');
  write(w.wState, L.replace(/^ {2}work_items:$/m, '  work_items: []'));
  okOut(w);
  const after = read(w.wState);
  assert.doesNotMatch(after, /work_items: \[\]/, 'the inline list is converted to block form');
  assert.equal(runsOf(after, R), 2);
  const chk = run(process.execPath, [CHECK_STATE, w.wState], w.wt);
  assert.equal(chk.status, 0, `check-state: ${chk.stdout}${chk.stderr}`);
  const py = spawnSync('python3', ['-c', 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))', w.wState], { encoding: 'utf8' });
  if (py.status !== 0 && !/No module named/.test(py.stderr)) assert.fail(`worktree STATE does not parse: ${py.stderr}`);
});

// --- PR #492 review findings -------------------------------------------------------

test('TEST-007 an unsafe draft path in the accepted STATE refuses before any write', () => {
  const variants = [
    ['primary_path', `  primary_path: ${INTAKE_REL}`, '  primary_path: /etc/hosts'],
    ['primary_path ..', `  primary_path: ${INTAKE_REL}`, `  primary_path: docs/../../${path.basename(INTAKE_REL)}`],
    ['spec_path', `  spec_path: ${SPEC_REL}`, '  spec_path: /etc/hosts'],
    ['spec_path ..', `  spec_path: ${SPEC_REL}`, '  spec_path: ../outside/SPEC.md'],
  ];
  for (const [label, from, to] of variants) {
    assert.ok(ORIGIN_STATE.includes(from), `control: fixture holds ${from}`);
    const w = world({ state: ORIGIN_STATE.replace(from, to) });
    const o0 = sha(w.oState);
    const w0 = sha(w.wState);
    const r = out(w);
    assert.equal(r.status, 1, `${label}: exit ${r.status} ${r.stdout}${r.stderr}`);
    assert.match(r.stdout, /^REFUSE unsafe_draft_path\b/m, label);
    assert.equal(sha(w.oState), o0, `${label}: origin STATE unchanged`);
    assert.equal(sha(w.wState), w0, `${label}: worktree STATE unchanged`);
    assert.equal(handoffDirs(w).length, 0, `${label}: no archive`);
    assert.equal(fs.existsSync(path.join(w.wt, SPEC_REL)), false, `${label}: no draft carried`);
  }
});

test('TEST-007 a foreign metrics entry or item in the worktree STATE is not fresh, even with zero runs', () => {
  const withEntry = (txt, body) => txt.replace(/^ {2}work_items:.*$/m, `  work_items:\n${body}`);
  const foreignZero = [
    ['zero-run entry', (t) => withEntry(t, '    foreign-zero:\n      agent_runs: []')],
    ['entry without runs key', (t) => withEntry(t, '    foreign-bare:\n      note: x')],
  ];
  for (const [label, edit] of foreignZero) {
    const w = world();
    write(w.wState, edit(read(w.wState)));
    const o0 = sha(w.oState);
    const w0 = sha(w.wState);
    const r = out(w);
    assert.equal(r.status, 1, `${label}: exit ${r.status} ${r.stdout}${r.stderr}`);
    assert.match(r.stdout, /^REFUSE worktree_state_not_fresh\b/m, label);
    assert.equal(sha(w.oState), o0, `${label}: origin STATE unchanged`);
    assert.equal(sha(w.wState), w0, `${label}: worktree STATE unchanged`);
    assert.equal(handoffDirs(w).length, 0, `${label}: no archive`);
  }
  // control: legitimate fresh shapes are still accepted
  for (const shape of ['  work_items: null', '  work_items: {}', '  work_items: []']) {
    const w = world();
    const L = read(w.wState);
    assert.match(L, /^ {2}work_items:$/m, 'control: repaired STATE has a bare work_items header');
    write(w.wState, L.replace(/^ {2}work_items:$/m, shape));
    okOut(w);
    assert.equal(runsOf(read(w.wState), R), 2, shape);
    assert.equal(count(read(w.wState), 'foreign'), 0, `${shape}: no foreign line survives`);
  }
  okOut(world());
});
