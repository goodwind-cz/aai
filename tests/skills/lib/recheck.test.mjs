// recheck.test.mjs - node:test cases for the delta re-check mode
// (docs/specs/SPEC-0250-spec-cheap-transitions-slice.md, TEST-2701..2723).
// Every case builds a temporary git repository under the OS temp directory; the
// shipping tree is only read. Each case name starts with its TEST id so
// test-aai-recheck.sh can run one id at a time (node --test --test-name-pattern).
//
// SELF-HOSTING: delta is opt-in (owner decision 2026-10-24), so the cases SET
// AAI_RECHECK_MODE=delta explicitly in every child process (cleanEnv) and pass an
// explicit env to recheckMode (DELTA_ENV), so the suite gives the same answer when the
// rider exports AAI_RECHECK_MODE=full. TEST-2738 scrubs the variable to test the default.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync, execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(HERE, '..', '..', '..');
const SCRIPTS = path.join(PROJECT_ROOT, '.aai', 'scripts');
const LIB_PATH = path.join(SCRIPTS, 'lib', 'recheck.mjs');
const BASE_CANON_COMMIT = 'ba552b89';
const ROLES_ALL = ['Planning', 'Implementation', 'Validation', 'Remediation', 'TDD Implementation', 'Code Review'];

const made = [];
const tmpTop = fs.mkdtempSync(path.join(os.tmpdir(), 'aai-recheck-test.'));
after(() => { fs.rmSync(tmpTop, { recursive: true, force: true }); });

async function lib() {
  assert.ok(fs.existsSync(LIB_PATH), '.aai/scripts/lib/recheck.mjs does not exist');
  return import(pathToFileURL(LIB_PATH).href);
}

const DELTA_ENV = { AAI_RECHECK_MODE: 'delta' };

function cleanEnv(extra = {}) {
  const env = { ...process.env };
  delete env.AAI_ROLE;
  return { ...env, ...DELTA_ENV, ...extra };
}

function unsetEnv() {
  const env = { ...process.env };
  delete env.AAI_RECHECK_MODE;
  delete env.AAI_ROLE;
  return env;
}

function git(cwd, args) {
  return execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

function write(root, rel, text) {
  const abs = path.join(root, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, text);
}

function copyLive(root, rel) {
  const src = path.join(PROJECT_ROOT, rel);
  if (!fs.existsSync(src)) return false;
  const dst = path.join(root, rel);
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.copyFileSync(src, dst);
  return true;
}

const REF = 'r1';
const SPEC_REL = 'docs/specs/SPEC-0001-fx.md';
const REV_REL = 'docs/ai/reviews/rev-1.md';
const VAL_REL = 'docs/ai/reports/VALIDATION-1.md';
const MARK_FALSE = 'security_relevant: false\n';

function specText(level) {
  const lvl = level === undefined ? '' : `ceremony_level: ${level}\n`;
  return `---\nid: SPEC-0001\ntype: spec\nnumber: 1\nstatus: draft\n${lvl}links:\n  pr: []\n---\n\n# Fixture spec\n\nSPEC-FROZEN: true\n\n## Test Plan\n`;
}

function stateYaml(o = {}) {
  const {
    ref = REF, spec = SPEC_REL, vstatus = 'not_run', rstatus = 'not_run', runAt = '2026-07-01T00:00:00Z',
    evidence = [VAL_REL], reports = [REV_REL], phase = 'implementation', implModel = null, vref = ref, human = false,
  } = o;
  const list = (name, arr) => (arr.length ? `  ${name}:\n${arr.map((x) => `    - ${x}`).join('\n')}\n` : `  ${name}: []\n`);
  const metrics = implModel
    ? `metrics:\n  work_items:\n    ${ref}:\n      human_time_minutes:\n        intake: null\n        reviews: null\n      agent_runs:\n        - role: Implementation\n          model_id: ${implModel}\n`
    : '';
  return `project_status: ${human ? 'paused' : 'active'}
current_focus:
  type: intake_change
  ref_id: ${ref}
  primary_path: docs/issues/CHANGE-0001-fixture.md
  spec_path: ${spec}
active_work_items:
  - ref_id: ${ref}
    status: in_progress
    phase: ${phase}
    primary_path: docs/issues/CHANGE-0001-fixture.md
    spec_path: ${spec}
implementation_strategy:
  selected: tdd
  source: ${spec}
  rationale: null
worktree:
  recommendation: optional
  user_decision: inline
  base_ref: main
  branch: null
  path: null
  inline_review_scope: null
  rationale: null
code_review:
  required: true
  status: ${rstatus}
  scope: null
  base_ref: main
  head_ref: null
  pr: null
${list('report_paths', reports)}  notes: null
last_validation:
  status: ${vstatus}
  run_at_utc: ${runAt}
  ref_id: ${vref}
${list('evidence_paths', evidence)}  notes: null
human_input:
  required: false
  question: null
locks:
  implementation: true
tdd_cycle:
  status: IDLE
  test_id: null
${metrics}updated_at_utc: 2026-07-01T00:00:00Z
`;
}

function eventLine(ev) {
  return JSON.stringify({ v: 1, ts: '2026-07-01T00:00:00.000Z', actor: 'test', ...ev });
}

function appendEvents(root, evs) {
  const p = path.join(root, 'docs/ai/EVENTS.jsonl');
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.appendFileSync(p, evs.map((e) => eventLine(e) + '\n').join(''));
}

function readEvents(root) {
  const p = path.join(root, 'docs/ai/EVENTS.jsonl');
  if (!fs.existsSync(p)) return [];
  return fs.readFileSync(p, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
}

function verdictEvents(base, roles = ['validation', 'code_review']) {
  return roles.map((role) => ({ event: 'check_verdict', ref: REF, payload: { role, head: base, status: 'fail', security_relevant: false } }));
}

const DEFAULT_AUDIT = 'protected_paths_l3:\n  - .aai/workflow/WORKFLOW.md\n  - docs/CONSTITUTION.md\n';

// mkRepo(name, opts) builds a committed fixture repository holding a spec, the two
// prior reports, one production file, one test file, the ledgers and the live canon
// inputs. opts.level undefined means the spec carries no ceremony_level. Returns
// { root, base } where base is the commit the check_verdict events point at.
function mkRepo(name, o = {}) {
  const root = path.join(tmpTop, name);
  fs.mkdirSync(root, { recursive: true });
  git(root, ['init', '-q', '-b', 'main']);
  git(root, ['config', 'user.email', 'test@example.invalid']);
  git(root, ['config', 'user.name', 'AAI Test']);
  write(root, '.gitignore', o.trackEvents ? 'docs/ai/STATE.yaml\n' : 'docs/ai/STATE.yaml\ndocs/ai/EVENTS.jsonl\n');
  write(root, 'docs/ai/docs-audit.yaml', o.audit ?? DEFAULT_AUDIT);
  if (o.spec !== false) write(root, SPEC_REL, specText('level' in o ? o.level : 2));
  write(root, REV_REL, o.revText ?? `# Review\n\n${MARK_FALSE}`);
  write(root, VAL_REL, o.valText ?? `# Validation\n\n${MARK_FALSE}`);
  write(root, '.aai/scripts/x.mjs', 'export const x = 1;\n');
  write(root, '.aai/workflow/WORKFLOW.md', '# Workflow fixture\n');
  write(root, 'docs/TECHNOLOGY.md', '# Technology fixture\n');
  write(root, 'docs/knowledge/LEARNED.md', '# Learned fixture\n');
  write(root, 'docs/ai/decisions.jsonl', '{"type":"x"}\n');
  write(root, 'tests/skills/test-aai-base.sh', '#!/usr/bin/env bash\necho base\n');
  write(root, 'tests/skills/test-aai-guarded.sh', '#!/usr/bin/env bash\necho guarded\n');
  if (o.canon) {
    for (const rel of ['.aai/SUBAGENT_CONTRACT.md', '.aai/RECHECK_DELTA.prompt.md', '.aai/system/CANON.yaml',
      '.aai/system/MODEL_ROUTING.yaml', 'docs/knowledge/LEARNED.md',
      '.aai/PLANNING.prompt.md', '.aai/IMPLEMENTATION.prompt.md', '.aai/VALIDATION.prompt.md',
      '.aai/REMEDIATION.prompt.md', '.aai/SKILL_TDD.prompt.md', '.aai/SKILL_CODE_REVIEW.prompt.md']) copyLive(root, rel);
  }
  write(root, 'docs/ai/STATE.yaml', stateYaml(o.state));
  git(root, ['add', '-A']);
  git(root, ['commit', '-q', '-m', 'base']);
  const base = git(root, ['rev-parse', 'HEAD']);
  if (o.verdicts !== false) appendEvents(root, verdictEvents(base, o.verdictRoles));
  made.push(root);
  return { root, base };
}

function stateOf(root) { return path.join(root, 'docs/ai/STATE.yaml'); }

function reasonsOf(r) { return r.reasons.join(' '); }

// ------------------------------------------------------------------ TEST-2701
test('TEST-2701 the Measured baseline table equals the values recomputed from METRICS.jsonl', () => {
  const spec = fs.readdirSync(path.join(PROJECT_ROOT, 'docs/specs')).find((f) => /-spec-cheap-transitions-slice\.md$/.test(f));
  assert.ok(spec, 'the cheap-transitions-slice spec is not under docs/specs');
  const text = fs.readFileSync(path.join(PROJECT_ROOT, 'docs/specs', spec), 'utf8');
  const at = text.indexOf('## Measured baseline');
  assert.ok(at >= 0, 'no Measured baseline section');
  const rows = [];
  for (const line of text.slice(at).split('\n')) {
    if (rows.length && !line.startsWith('|')) break;
    if (line.startsWith('|')) rows.push(line.split('|').slice(1, -1).map((c) => c.trim()));
  }
  assert.ok(rows.length >= 5, 'baseline table too short');
  const head = rows[0];
  const col = (name) => { const i = head.indexOf(name); assert.ok(i >= 0, 'no column ' + name); return i; };
  const metrics = fs.readFileSync(path.join(PROJECT_ROOT, 'docs/ai/METRICS.jsonl'), 'utf8')
    .split('\n').filter((l) => l.trim() && !l.startsWith('#')).map((l) => JSON.parse(l));
  let checked = 0;
  const bad = [];
  for (const cells of rows.slice(2)) {
    const ref = cells[col('Ride')];
    const mine = metrics.filter((m) => m.ref_id === ref);
    assert.ok(mine.length > 0, 'no METRICS row for ' + ref);
    const runs = mine[mine.length - 1].agent_runs;
    const tok = (r) => (Number.isFinite(r.tokens_total) ? r.tokens_total : 0);
    const seen = new Set();
    let rounds = 0;
    let roundTokens = 0;
    for (const r of runs) {
      if (r.role !== 'Validation' && r.role !== 'Code Review') continue;
      if (seen.has(r.role)) { rounds += 1; roundTokens += tok(r); }
      seen.add(r.role);
    }
    const want = {
      Runs: runs.length,
      'CR runs': runs.filter((r) => r.role === 'Code Review').length,
      'V runs': runs.filter((r) => r.role === 'Validation').length,
      'Rem runs': runs.filter((r) => r.role === 'Remediation').length,
      'Ride tokens': runs.reduce((a, r) => a + tok(r), 0),
      'Re-check rounds': rounds,
      'Re-check tokens': roundTokens,
    };
    for (const [k, v] of Object.entries(want)) {
      if (Number(cells[col(k)]) !== v) bad.push(`${ref} ${k}: table ${cells[col(k)]} != METRICS ${v}`);
    }
    checked += 1;
  }
  assert.ok(checked >= 3, 'fewer than three rides checked');
  assert.deepEqual(bad, []);
});

// ------------------------------------------------------------------ TEST-2702
test('TEST-2702 delta applies on an eligible fixture and every TREE_HASH_EXCLUDE_PATHS member is non-production', async () => {
  const L = await lib();
  const { root, base } = mkRepo('t2702');
  fs.appendFileSync(path.join(root, 'tests/skills/test-aai-base.sh'), 'echo more\n');
  write(root, 'docs/specs/new-note.md', '# note\n');
  fs.appendFileSync(path.join(root, 'docs/ai/decisions.jsonl'), '{"type":"y"}\n');
  const head = git(root, ['rev-parse', 'HEAD']);
  for (const role of ['Validation', 'Code Review']) {
    const r = L.recheckMode({ root, ref: REF, role, env: DELTA_ENV });
    assert.deepEqual(r.reasons, [], reasonsOf(r));
    assert.equal(r.mode, 'delta');
    assert.equal(r.base, base);
    assert.equal(r.head, head);
    assert.deepEqual(r.changed_paths, ['docs/ai/decisions.jsonl', 'docs/specs/new-note.md', 'tests/skills/test-aai-base.sh']);
    assert.ok(r.prior_reports.includes(REV_REL) && r.prior_reports.includes(VAL_REL), JSON.stringify(r.prior_reports));
  }
  const dispatch = await import(pathToFileURL(path.join(SCRIPTS, 'orchestration-dispatch.mjs')).href);
  assert.ok(dispatch.TREE_HASH_EXCLUDE_PATHS instanceof Set && dispatch.TREE_HASH_EXCLUDE_PATHS.size >= 6, 'dispatch must export TREE_HASH_EXCLUDE_PATHS');
  for (const p of dispatch.TREE_HASH_EXCLUDE_PATHS) assert.equal(L.isNonProduction(p), true, p + ' must be non-production');
  for (const p of ['.aai/scripts/x.mjs', 'docs/knowledge/LEARNED.md', 'docs/ai/docs-audit.yaml', 'package.json', 'docs/TECHNOLOGY.md']) {
    assert.equal(L.isNonProduction(p), false, p + ' must be production');
  }
});

// ------------------------------------------------------------------ TEST-2703
test('TEST-2703 production paths refuse delta and name the path', async () => {
  const L = await lib();
  const cases = [
    ['tracked', '.aai/scripts/x.mjs', (root) => fs.appendFileSync(path.join(root, '.aai/scripts/x.mjs'), '// edit\n')],
    ['untracked', '.aai/new.mjs', (root) => write(root, '.aai/new.mjs', 'x\n')],
    ['learned', 'docs/knowledge/LEARNED.md', (root) => fs.appendFileSync(path.join(root, 'docs/knowledge/LEARNED.md'), 'more\n')],
    ['audit', 'docs/ai/docs-audit.yaml', (root) => fs.appendFileSync(path.join(root, 'docs/ai/docs-audit.yaml'), '# edit\n')],
  ];
  for (const [name, p, mutate] of cases) {
    const { root } = mkRepo('t2703-' + name);
    mutate(root);
    const r = L.recheckMode({ root, ref: REF, role: 'Validation', env: DELTA_ENV });
    assert.equal(r.mode, 'full', name);
    assert.ok(r.reasons.includes('production_path:' + p), name + ': ' + reasonsOf(r));
  }
  const { root } = mkRepo('t2703-mixed');
  fs.appendFileSync(path.join(root, '.aai/scripts/x.mjs'), '// edit\n');
  fs.appendFileSync(path.join(root, 'tests/skills/test-aai-base.sh'), 'echo more\n');
  const r = L.recheckMode({ root, ref: REF, role: 'Code Review', env: DELTA_ENV });
  assert.deepEqual(r.reasons.filter((x) => x.startsWith('production_path:')), ['production_path:.aai/scripts/x.mjs']);
});

// ------------------------------------------------------------------ TEST-2704
test('TEST-2704 a protected path refuses delta; the same change without the entry gives delta', async () => {
  const L = await lib();
  const guardedAudit = 'protected_paths_l3:\n  - tests/skills/test-aai-guarded.sh\n';
  const change = (root) => fs.appendFileSync(path.join(root, 'tests/skills/test-aai-guarded.sh'), 'echo more\n');
  const control = mkRepo('t2704-control');
  change(control.root);
  const c = L.recheckMode({ root: control.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(c.mode, 'delta', 'positive control: ' + reasonsOf(c));
  const prot = mkRepo('t2704-protected', { audit: guardedAudit });
  change(prot.root);
  const p = L.recheckMode({ root: prot.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(p.mode, 'full');
  assert.ok(p.reasons.includes('protected_path:tests/skills/test-aai-guarded.sh'), reasonsOf(p));
  const bad = mkRepo('t2704-unreadable');
  fs.rmSync(path.join(bad.root, 'docs/ai/docs-audit.yaml'));
  fs.mkdirSync(path.join(bad.root, 'docs/ai/docs-audit.yaml'));
  const u = L.recheckMode({ root: bad.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(u.mode, 'full');
  assert.ok(u.reasons.includes('protected_config_unreadable'), reasonsOf(u));
  const absent = mkRepo('t2704-absent');
  fs.rmSync(path.join(absent.root, 'docs/ai/docs-audit.yaml'));
  const a = L.recheckMode({ root: absent.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.ok(a.reasons.includes('protected_config_unreadable'), 'absent config: ' + reasonsOf(a));
});

// ------------------------------------------------------------------ TEST-2705
test('TEST-2705 security marker refusals', async () => {
  const L = await lib();
  const touch = (root) => fs.appendFileSync(path.join(root, 'tests/skills/test-aai-base.sh'), 'echo more\n');
  const ok = mkRepo('t2705-ok');
  touch(ok.root);
  assert.equal(L.recheckMode({ root: ok.root, ref: REF, role: 'Validation', env: DELTA_ENV }).mode, 'delta', 'positive control');

  const t = mkRepo('t2705-true', { revText: '# Review\n\nsecurity_relevant: true\n' });
  touch(t.root);
  const rt = L.recheckMode({ root: t.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(rt.mode, 'full');
  assert.ok(rt.reasons.includes('security_relevant:' + REV_REL), reasonsOf(rt));

  const none = mkRepo('t2705-none', { valText: '# Validation\n\nno marker here\n' });
  touch(none.root);
  assert.ok(L.recheckMode({ root: none.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('security_marker_absent:' + VAL_REL));

  const twice = mkRepo('t2705-twice', { valText: `# Validation\n\n${MARK_FALSE}${MARK_FALSE}` });
  touch(twice.root);
  assert.ok(L.recheckMode({ root: twice.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('security_marker_absent:' + VAL_REL));

  const NOPE = 'docs/ai/reports/VALIDATION-never-written.md';
  const missing = mkRepo('t2705-missing', { state: { evidence: [NOPE] } });
  touch(missing.root);
  const rm = L.recheckMode({ root: missing.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.ok(rm.reasons.includes('prior_report_unreadable:' + NOPE), reasonsOf(rm));
  // a report that existed at the base and is deleted inside the delta is a changed report (TEST-2729)
  const gone = mkRepo('t2705-gone');
  fs.rmSync(path.join(gone.root, VAL_REL));
  assert.ok(L.recheckMode({ root: gone.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('prior_report_changed:' + VAL_REL));

  const noReport = mkRepo('t2705-noreport', { state: { evidence: [] } });
  touch(noReport.root);
  const rn = L.recheckMode({ root: noReport.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.ok(rn.reasons.includes('security_marker_absent:validation'), reasonsOf(rn));
});

// ------------------------------------------------------------------ TEST-2706
test('TEST-2706 first round, ceremony, ancestry, empty delta, forced and git refusals', async () => {
  const L = await lib();
  const touch = (root) => fs.appendFileSync(path.join(root, 'tests/skills/test-aai-base.sh'), 'echo more\n');

  const first = mkRepo('t2706-first', { verdicts: false });
  touch(first.root);
  const f = L.recheckMode({ root: first.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(f.mode, 'full');
  assert.ok(f.reasons.includes('first_round'), reasonsOf(f));

  const only = mkRepo('t2706-onerole', { verdictRoles: ['validation'] });
  touch(only.root);
  assert.equal(L.recheckMode({ root: only.root, ref: REF, role: 'Validation', env: DELTA_ENV }).mode, 'delta', 'a verdict for the other role must not matter');
  assert.ok(L.recheckMode({ root: only.root, ref: REF, role: 'Code Review', env: DELTA_ENV }).reasons.includes('first_round'));

  const l3 = mkRepo('t2706-l3', { level: 3 });
  touch(l3.root);
  assert.ok(L.recheckMode({ root: l3.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('ceremony_l3'));

  const nolevel = mkRepo('t2706-nolevel', { level: undefined });
  touch(nolevel.root);
  assert.ok(L.recheckMode({ root: nolevel.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('ceremony_unknown'));

  const nospec = mkRepo('t2706-nospec', { spec: false });
  touch(nospec.root);
  assert.ok(L.recheckMode({ root: nospec.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('ceremony_unknown'));

  for (const lvl of [0, 1]) {
    const ok = mkRepo('t2706-lvl' + lvl, { level: lvl });
    touch(ok.root);
    assert.equal(L.recheckMode({ root: ok.root, ref: REF, role: 'Validation', env: DELTA_ENV }).mode, 'delta', 'level ' + lvl);
  }

  const sib = mkRepo('t2706-sibling', { verdicts: false });
  git(sib.root, ['checkout', '-q', '-b', 'side']);
  write(sib.root, 'tests/skills/side.sh', 'x\n');
  git(sib.root, ['add', '-A']);
  git(sib.root, ['commit', '-q', '-m', 'side']);
  const sideHead = git(sib.root, ['rev-parse', 'HEAD']);
  git(sib.root, ['checkout', '-q', 'main']);
  git(sib.root, ['cat-file', '-e', sideHead + '^{commit}']);
  appendEvents(sib.root, verdictEvents(sideHead));
  touch(sib.root);
  assert.ok(L.recheckMode({ root: sib.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('base_not_ancestor'));

  const empty = mkRepo('t2706-empty');
  const e = L.recheckMode({ root: empty.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(e.mode, 'full');
  assert.ok(e.reasons.includes('no_delta'), reasonsOf(e));

  const forced = mkRepo('t2706-forced');
  touch(forced.root);
  const fr = L.recheckMode({ root: forced.root, ref: REF, role: 'Validation', env: { AAI_RECHECK_MODE: 'full' } });
  assert.equal(fr.mode, 'full');
  assert.ok(fr.reasons.includes('recheck_disabled'));
  assert.equal(L.recheckMode({ root: forced.root, ref: REF, role: 'Validation', env: { AAI_RECHECK_MODE: 'delta' } }).mode, 'delta');

  const notGit = path.join(tmpTop, 't2706-nogit');
  fs.mkdirSync(notGit, { recursive: true });
  const g = L.recheckMode({ root: notGit, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(g.mode, 'full');
  assert.ok(g.reasons.includes('git_error'), reasonsOf(g));

  const both = mkRepo('t2706-both', { verdicts: false });
  fs.appendFileSync(path.join(both.root, '.aai/scripts/x.mjs'), '// edit\n');
  const b = L.recheckMode({ root: both.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.ok(b.reasons.includes('first_round') && b.reasons.includes('production_path:.aai/scripts/x.mjs'), reasonsOf(b));

  const rem = mkRepo('t2706-role');
  touch(rem.root);
  assert.ok(L.recheckMode({ root: rem.root, ref: REF, role: 'Remediation', env: DELTA_ENV }).reasons.includes('role_not_rechecked'));
});

// ---------------------------------------------------------------- dispatch helpers
function runDispatch(root, args = [], envExtra = {}) {
  const r = spawnSync(process.execPath, [path.join(SCRIPTS, 'orchestration-dispatch.mjs'),
    '--state', stateOf(root), '--root', root, ...args], { cwd: PROJECT_ROOT, encoding: 'utf8', env: cleanEnv(envExtra) });
  let out = null;
  try { out = JSON.parse(r.stdout); } catch { out = null; }
  return { status: r.status, out, stdout: r.stdout, stderr: r.stderr };
}

// rc(d): the recheck object of a dispatch result, with a named failure when absent.
function rc(d) {
  assert.ok(d.out && d.out.recheck && typeof d.out.recheck === 'object', 'the dispatch JSON has no recheck object: ' + String(d.stdout).slice(0, 200));
  return d.out.recheck;
}

function canonRun(root, args, envExtra = {}) {
  return spawnSync(process.execPath, [path.join(SCRIPTS, 'canon.mjs'), ...args], { cwd: root, encoding: 'utf8', env: cleanEnv(envExtra) });
}

function eligibleCanon(name, o = {}) {
  const fx = mkRepo(name, { canon: true, ...o });
  fs.appendFileSync(path.join(fx.root, 'tests/skills/test-aai-base.sh'), 'echo more\n');
  return fx;
}

// ------------------------------------------------------------------ TEST-2707
test('TEST-2707 the dispatch carries a recheck object equal to recheckMode; other verdicts carry null', async () => {
  const L = await lib();
  const { root } = eligibleCanon('t2707');
  // rule 11: validation not run
  const a = runDispatch(root);
  assert.equal(a.status, 0, a.stderr);
  assert.equal(a.out.rule, '11');
  assert.equal(a.out.role, 'Validation');
  assert.equal(rc(a).mode, 'delta', JSON.stringify(a.out.recheck));
  const { fallback: fbA, ...restA } = rc(a);
  assert.deepEqual(restA, L.recheckMode({ root, ref: REF, role: 'Validation', env: DELTA_ENV }));
  assert.equal(a.out.system_prompt, '.aai/RECHECK_DELTA.prompt.md');
  assert.equal(fbA.system_prompt, '.aai/VALIDATION.prompt.md', 'a delta dispatch carries the full identity as recheck.fallback');
  // rule 13: validation passed, review required and missing
  write(root, 'docs/ai/STATE.yaml', stateYaml({ vstatus: 'pass', rstatus: 'not_run' }));
  const b = runDispatch(root);
  assert.equal(b.out.rule, '13', JSON.stringify(b.out));
  assert.equal(b.out.role, 'Code Review');
  assert.equal(rc(b).mode, 'delta', JSON.stringify(b.out.recheck));
  const { fallback: fbB, ...restB } = rc(b);
  assert.deepEqual(restB, L.recheckMode({ root, ref: REF, role: 'Code Review', env: DELTA_ENV }));
  assert.equal(fbB.system_prompt, '.aai/SKILL_CODE_REVIEW.prompt.md');
  assert.equal(b.out.system_prompt, '.aai/RECHECK_DELTA.prompt.md');
  // a Remediation dispatch (rule 10) and a no_action verdict carry null
  write(root, 'docs/ai/STATE.yaml', stateYaml({ vstatus: 'fail' }));
  const c = runDispatch(root);
  assert.equal(c.out.role, 'Remediation');
  assert.ok('recheck' in c.out && c.out.recheck === null, 'Remediation recheck must be null');
  write(root, 'docs/ai/STATE.yaml', stateYaml({ human: true }));
  const d = runDispatch(root);
  assert.equal(d.out.verdict, 'no_action');
  assert.ok('recheck' in d.out && d.out.recheck === null, 'no_action recheck must be null');
  // forced full: the object is present, mode full, the stock prompt stays
  write(root, 'docs/ai/STATE.yaml', stateYaml());
  const e = runDispatch(root, [], { AAI_RECHECK_MODE: 'full' });
  assert.equal(rc(e).mode, 'full');
  assert.ok(rc(e).reasons.includes('recheck_disabled'));
  assert.equal(rc(e).fallback, null, 'a full dispatch has no fallback');
  assert.equal(e.out.system_prompt, '.aai/VALIDATION.prompt.md');
});

// ------------------------------------------------------------------ TEST-2708
test('TEST-2708 role, rule, tier, model, effort, independence and lane are the same in delta and full mode', () => {
  const impl = 'claude-opus-5-5';
  const { root } = eligibleCanon('t2708', { state: { implModel: impl } });
  const delta = runDispatch(root);
  const full = runDispatch(root, [], { AAI_RECHECK_MODE: 'full' });
  assert.equal(rc(delta).mode, 'delta');
  assert.equal(rc(full).mode, 'full');
  for (const k of ['role', 'rule', 'suggested_tier', 'suggested_model', 'suggested_effort', 'validator_independence', 'lane']) {
    assert.deepEqual(delta.out[k], full.out[k], k);
  }
  assert.equal(delta.out.validator_independence.must_differ, true);
  assert.equal(delta.out.validator_independence.implementer_model, impl);
  assert.ok(typeof delta.out.suggested_model === 'string' && delta.out.suggested_model !== impl, 'suggested_model must differ from the implementer: ' + delta.out.suggested_model);
});

// ------------------------------------------------------------------ TEST-2709
test('TEST-2709 the delta prompt_hash equals canon --print-hash --recheck delta', () => {
  const { root } = eligibleCanon('t2709');
  const pair = (stateOpts, role) => {
    write(root, 'docs/ai/STATE.yaml', stateYaml(stateOpts));
    const d = runDispatch(root);
    assert.equal(d.out.role, role);
    assert.equal(rc(d).mode, 'delta');
    const h = canonRun(root, ['build', '--role', role, '--print-hash', '--recheck', 'delta']);
    assert.equal(h.status, 0, h.stderr);
    assert.equal(d.out.prompt_hash, h.stdout.trim());
    const full = canonRun(root, ['build', '--role', role, '--print-hash']);
    assert.equal(full.status, 0, full.stderr);
    assert.notEqual(d.out.prompt_hash, full.stdout.trim());
    const f = runDispatch(root, [], { AAI_RECHECK_MODE: 'full' });
    assert.equal(f.out.prompt_hash, full.stdout.trim());
  };
  pair({}, 'Validation');
  pair({ vstatus: 'pass', rstatus: 'not_run' }, 'Code Review');
});

// ------------------------------------------------------------------ TEST-2710
test('TEST-2710 append-event accepts check_dispatched and check_verdict and refuses malformed input', () => {
  const root = path.join(tmpTop, 't2710');
  fs.mkdirSync(path.join(root, 'docs/ai'), { recursive: true });
  git(root, ['init', '-q', '-b', 'main']);
  const append = (args) => spawnSync(process.execPath, [path.join(SCRIPTS, 'append-event.mjs'), ...args], { cwd: root, encoding: 'utf8', env: cleanEnv() });
  const H = 'a'.repeat(40);
  const a = append(['--event', 'check_dispatched', '--ref', REF, '--role', 'validation', '--head', H, '--seen', 'run_at:2026-07-01T00:00:00Z']);
  assert.equal(a.status, 0, a.stderr);
  const b = append(['--event', 'check_verdict', '--ref', REF, '--role', 'code_review', '--head', H, '--status', 'pass']);
  assert.equal(b.status, 0, b.stderr);
  const evs = readEvents(root);
  assert.equal(evs.length, 2);
  assert.deepEqual(evs[0].payload, { role: 'validation', head: H, seen: 'run_at:2026-07-01T00:00:00Z' });
  assert.deepEqual(evs[1].payload, { role: 'code_review', head: H, status: 'pass' });
  const bad = [
    ['missing role', ['--event', 'check_dispatched', '--ref', REF, '--head', H, '--seen', 's']],
    ['unknown role', ['--event', 'check_dispatched', '--ref', REF, '--role', 'reviewer', '--head', H, '--seen', 's']],
    ['39-char head', ['--event', 'check_dispatched', '--ref', REF, '--role', 'validation', '--head', 'a'.repeat(39), '--seen', 's']],
    ['upper-case head', ['--event', 'check_verdict', '--ref', REF, '--role', 'validation', '--head', 'A'.repeat(40), '--status', 'pass']],
    ['verdict without status', ['--event', 'check_verdict', '--ref', REF, '--role', 'validation', '--head', H]],
    ['verdict status other than pass or fail', ['--event', 'check_verdict', '--ref', REF, '--role', 'validation', '--head', H, '--status', 'maybe']],
    ['dispatched without seen', ['--event', 'check_dispatched', '--ref', REF, '--role', 'validation', '--head', H]],
  ];
  for (const [name, args] of bad) {
    const r = append(args);
    assert.notEqual(r.status, 0, name + ' must exit non-zero');
    assert.equal(readEvents(root).length, 2, name + ' must append nothing');
  }
});

// ------------------------------------------------------------------ TEST-2711
test('TEST-2711 --confirm ticks stamp check_dispatched once and check_verdict once', () => {
  const { root } = eligibleCanon('t2711');
  const H = git(root, ['rev-parse', 'HEAD']);
  const only = (name) => readEvents(root).filter((e) => e.event === name && e.ref === REF && e.payload.role === 'validation');
  fs.rmSync(path.join(root, 'docs/ai/EVENTS.jsonl'));
  // a tick without --confirm appends nothing
  const dry = runDispatch(root);
  assert.equal(dry.out.rule, '11');
  assert.equal(readEvents(root).length, 0, 'no --confirm, no write');
  // a --confirm rule 11 tick appends one check_dispatched with the HEAD and the seen marker
  const t1 = runDispatch(root, ['--confirm']);
  assert.equal(t1.out.rule, '11');
  assert.equal(only('check_dispatched').length, 1);
  assert.equal(only('check_dispatched')[0].payload.head, H);
  assert.equal(only('check_dispatched')[0].payload.seen, 'run_at:2026-07-01T00:00:00Z');
  // the same tick again appends nothing
  runDispatch(root, ['--confirm']);
  assert.equal(only('check_dispatched').length, 1, 'no second check_dispatched');
  assert.equal(only('check_verdict').length, 0);
  // a verdict with a newer run_at_utc stamps once, with the dispatched head
  write(root, 'docs/ai/STATE.yaml', stateYaml({ vstatus: 'fail', runAt: '2026-07-02T00:00:00Z' }));
  const t2 = runDispatch(root, ['--confirm']);
  assert.equal(t2.out.role, 'Remediation');
  assert.equal(only('check_verdict').length, 1);
  assert.equal(only('check_verdict')[0].payload.status, 'fail');
  assert.equal(only('check_verdict')[0].payload.head, H);
  runDispatch(root, ['--confirm']);
  assert.equal(only('check_verdict').length, 1, 'a repeat after the stamp appends nothing');
  // a verdict with no check_dispatched is never stamped
  const lone = eligibleCanon('t2711-lone');
  fs.rmSync(path.join(lone.root, 'docs/ai/EVENTS.jsonl'));
  write(lone.root, 'docs/ai/STATE.yaml', stateYaml({ vstatus: 'fail', runAt: '2026-07-02T00:00:00Z' }));
  runDispatch(lone.root, ['--confirm']);
  assert.equal(readEvents(lone.root).filter((e) => e.event === 'check_verdict').length, 0, 'no check_dispatched, no stamp');
  // a verdict that is not newer than the dispatched marker is not stamped
  const same = eligibleCanon('t2711-same');
  fs.rmSync(path.join(same.root, 'docs/ai/EVENTS.jsonl'));
  runDispatch(same.root, ['--confirm']);
  write(same.root, 'docs/ai/STATE.yaml', stateYaml({ vstatus: 'fail', runAt: '2026-07-01T00:00:00Z' }));
  runDispatch(same.root, ['--confirm']);
  assert.equal(readEvents(same.root).filter((e) => e.event === 'check_verdict').length, 0, 'an unchanged run_at_utc is not a new verdict');
});

test('TEST-2711 code review: one more report plus a pass or fail status stamps a verdict', () => {
  const { root } = eligibleCanon('t2711-cr');
  fs.rmSync(path.join(root, 'docs/ai/EVENTS.jsonl'));
  write(root, 'docs/ai/STATE.yaml', stateYaml({ vstatus: 'pass', rstatus: 'not_run' }));
  const t1 = runDispatch(root, ['--confirm']);
  assert.equal(t1.out.rule, '13');
  const d = readEvents(root).filter((e) => e.event === 'check_dispatched' && e.payload.role === 'code_review');
  assert.equal(d.length, 1);
  assert.equal(d[0].payload.seen, 'reports:1');
  write(root, 'docs/ai/STATE.yaml', stateYaml({ vstatus: 'pass', rstatus: 'fail', reports: [REV_REL, 'docs/ai/reviews/rev-2.md'] }));
  runDispatch(root, ['--confirm']);
  const v = readEvents(root).filter((e) => e.event === 'check_verdict' && e.payload.role === 'code_review');
  assert.equal(v.length, 1);
  assert.equal(v[0].payload.status, 'fail');
  assert.equal(v[0].payload.head, d[0].payload.head);
});

// ------------------------------------------------------------------ TEST-2714
function stateCli(root, args) {
  return spawnSync(process.execPath, [path.join(SCRIPTS, 'state.mjs'), ...args, '--state', stateOf(root)], { cwd: root, encoding: 'utf8', env: cleanEnv() });
}

test('TEST-2714 end to end: real ticks, state.mjs writes and canon agree', () => {
  const { root } = mkRepo('t2714', { canon: true, verdicts: false });
  const H1 = git(root, ['rev-parse', 'HEAD']);
  const t1 = runDispatch(root, ['--confirm']);
  assert.equal(t1.out.rule, '11');
  assert.equal(rc(t1).mode, 'full');
  assert.ok(rc(t1).reasons.includes('first_round'));
  const sv = stateCli(root, ['set-validation', '--status', 'fail', '--ref', REF, '--evidence', VAL_REL, '--notes', 'round 1']);
  assert.equal(sv.status, 0, sv.stderr + sv.stdout);
  const t2 = runDispatch(root, ['--confirm']);
  assert.equal(t2.out.role, 'Remediation');
  const stamps = readEvents(root).filter((e) => e.event === 'check_verdict');
  assert.equal(stamps.length, 1, JSON.stringify(readEvents(root)));
  assert.equal(stamps[0].payload.head, H1);
  // remediation: a test-only commit, then the reset the remediation role runs
  fs.appendFileSync(path.join(root, 'tests/skills/test-aai-base.sh'), 'echo fixed\n');
  git(root, ['commit', '-q', '-am', 'test-only fix']);
  const rb = stateCli(root, ['reset-block', 'last_validation']);
  assert.equal(rb.status, 0, rb.stderr + rb.stdout);
  const t3 = runDispatch(root, ['--confirm']);
  assert.equal(t3.out.rule, '11');
  assert.equal(rc(t3).mode, 'delta', JSON.stringify(t3.out.recheck));
  assert.equal(rc(t3).base, H1);
  assert.deepEqual(rc(t3).changed_paths, ['tests/skills/test-aai-base.sh']);
  const c = canonRun(root, ['build', '--role', 'Validation', '--ref', REF, '--recheck', 'delta']);
  assert.equal(c.status, 0, c.stderr);
  assert.ok(c.stdout.includes('tests/skills/test-aai-base.sh'), 'canon scope must list the same path');
  assert.ok(c.stdout.includes(H1), 'canon scope must carry the base');
  // a production commit turns the next dispatch and canon to full and exit 11
  write(root, '.aai/scripts/fixture.mjs', 'export const y = 2;\n');
  git(root, ['add', '-A']);
  git(root, ['commit', '-q', '-m', 'production change']);
  const t4 = runDispatch(root, ['--confirm']);
  assert.equal(rc(t4).mode, 'full');
  assert.ok(rc(t4).reasons.includes('production_path:.aai/scripts/fixture.mjs'), JSON.stringify(t4.out.recheck.reasons));
  assert.equal(t4.out.system_prompt, '.aai/VALIDATION.prompt.md');
  const c2 = canonRun(root, ['build', '--role', 'Validation', '--ref', REF, '--recheck', 'delta']);
  assert.equal(c2.status, 11, c2.stderr);
  assert.equal(c2.stdout, '');
});

// ------------------------------------------------------------------ TEST-2712
function sectionIds(text) {
  return text.split('\n').filter((l) => l.startsWith('<<<AAI-CANON-SECTION ')).map((l) => l.slice('<<<AAI-CANON-SECTION '.length));
}

test('TEST-2712 canon --recheck delta assembles contract, recheck, scope only', () => {
  const { root, base } = eligibleCanon('t2712');
  write(root, 'tests/skills/lib/extra.test.mjs', 'x\n');
  const head = git(root, ['rev-parse', 'HEAD']);
  const r = canonRun(root, ['build', '--role', 'Code Review', '--ref', REF, '--recheck', 'delta']);
  assert.equal(r.status, 0, r.stderr);
  assert.deepEqual(sectionIds(r.stdout), ['contract', 'recheck', 'scope']);
  assert.equal(r.stdout.split('\n').filter((l) => l.startsWith('- HAZ-')).length, 5);
  const scope = r.stdout.slice(r.stdout.indexOf('<<<AAI-CANON-SECTION scope'));
  for (const needle of ['Code Review', REF, base, head, 'tests/skills/test-aai-base.sh', 'tests/skills/lib/extra.test.mjs', REV_REL, VAL_REL]) {
    assert.ok(scope.includes(needle), 'scope section lacks ' + needle);
  }
  const full = canonRun(root, ['build', '--role', 'Code Review', '--ref', REF]);
  assert.equal(full.status, 0, full.stderr);
  const have = new Set(r.stdout.split('\n'));
  const uniqueTo = (rel, others) => {
    const o = new Set(others.flatMap((p) => fs.readFileSync(path.join(root, p), 'utf8').split('\n')));
    return fs.readFileSync(path.join(root, rel), 'utf8').split('\n').find((l) => l.trim().length > 40 && !o.has(l) && !have.has(l));
  };
  const learned = uniqueTo('docs/knowledge/LEARNED.md', ['.aai/SUBAGENT_CONTRACT.md', '.aai/RECHECK_DELTA.prompt.md']);
  const roleOnly = uniqueTo('.aai/SKILL_CODE_REVIEW.prompt.md', ['.aai/SUBAGENT_CONTRACT.md', '.aai/RECHECK_DELTA.prompt.md']);
  assert.ok(learned && full.stdout.includes(learned), 'control: a LEARNED-only line must be in the full build');
  assert.ok(roleOnly && full.stdout.includes(roleOnly), 'control: a role-prompt-only line must be in the full build');
  assert.ok(!r.stdout.includes(learned), 'a line unique to LEARNED.md leaked into the delta payload');
  assert.ok(!r.stdout.includes(roleOnly), 'a line unique to the full role prompt leaked into the delta payload');
});

// ------------------------------------------------------------------ TEST-2713
test('TEST-2713 canon refuses an ineligible tree with exit 11 and an empty stdout', () => {
  const first = mkRepo('t2713-first', { canon: true, verdicts: false });
  fs.appendFileSync(path.join(first.root, 'tests/skills/test-aai-base.sh'), 'echo more\n');
  const a = canonRun(first.root, ['build', '--role', 'Validation', '--ref', REF, '--recheck', 'delta']);
  assert.equal(a.status, 11, a.stderr);
  assert.equal(a.stdout, '');
  assert.match(a.stderr, /canon-recheck-refused:.*first_round/);
  const prod = mkRepo('t2713-prod', { canon: true });
  fs.appendFileSync(path.join(prod.root, '.aai/scripts/x.mjs'), '// edit\n');
  const b = canonRun(prod.root, ['build', '--role', 'Validation', '--ref', REF, '--recheck', 'delta']);
  assert.equal(b.status, 11, b.stderr);
  assert.equal(b.stdout, '');
  assert.match(b.stderr, /canon-recheck-refused:.*production_path:\.aai\/scripts\/x\.mjs/);
  const forced = eligibleCanon('t2713-forced');
  const c = canonRun(forced.root, ['build', '--role', 'Validation', '--ref', REF, '--recheck', 'delta'], { AAI_RECHECK_MODE: 'full' });
  assert.equal(c.status, 11);
  assert.match(c.stderr, /recheck_disabled/);
});

test('TEST-2713 --recheck full and no flag are byte-identical to the base commit canon.mjs', () => {
  const { root } = eligibleCanon('t2713-identity');
  let oldCanon = null;
  let oldGuard = null;
  try {
    oldCanon = execFileSync('git', ['show', `${BASE_CANON_COMMIT}:.aai/scripts/canon.mjs`], { cwd: PROJECT_ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    oldGuard = execFileSync('git', ['show', `${BASE_CANON_COMMIT}:.aai/scripts/lib/cli-pipe-guard.mjs`], { cwd: PROJECT_ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  } catch {
    process.stderr.write(`SKIP-CASE: TEST-2713 identity arm needs ${BASE_CANON_COMMIT}, which is not in this clone\n`);
  }
  const scratch = path.join(tmpTop, 't2713-oldcanon');
  if (oldCanon) {
    write(scratch, '.aai/scripts/canon.mjs', oldCanon);
    write(scratch, '.aai/scripts/lib/cli-pipe-guard.mjs', oldGuard);
  }
  let compared = 0;
  for (const role of ROLES_ALL) {
    const plain = canonRun(root, ['build', '--role', role, '--ref', 'x']);
    assert.equal(plain.status, 0, role + ': ' + plain.stderr);
    const full = canonRun(root, ['build', '--role', role, '--ref', 'x', '--recheck', 'full']);
    assert.equal(full.status, 0, role + ': ' + full.stderr);
    assert.equal(full.stdout, plain.stdout, role + ': --recheck full differs from no flag');
    if (oldCanon) {
      const old = spawnSync(process.execPath, [path.join(scratch, '.aai/scripts/canon.mjs'), 'build', '--role', role, '--ref', 'x'], { cwd: root, encoding: 'utf8', env: cleanEnv() });
      assert.equal(old.status, 0, role + ' (base): ' + old.stderr);
      assert.equal(plain.stdout, old.stdout, role + ': differs from the ' + BASE_CANON_COMMIT + ' canon.mjs');
      compared += 1;
    }
  }
  if (oldCanon) assert.equal(compared, 6);
});

// ------------------------------------------------------------------ TEST-2715
test('TEST-2715 recheck-measure prints a ratio at most 0.40 for both roles and leaves the repository alone', () => {
  const script = path.join(HERE, 'recheck-measure.mjs');
  assert.ok(fs.existsSync(script), 'tests/skills/lib/recheck-measure.mjs does not exist');
  const before = git(PROJECT_ROOT, ['status', '--porcelain']);
  const r = spawnSync(process.execPath, [script], { cwd: PROJECT_ROOT, encoding: 'utf8', env: cleanEnv() });
  assert.equal(r.status, 0, r.stderr);
  const after = git(PROJECT_ROOT, ['status', '--porcelain']);
  assert.equal(after, before, 'git status changed while measuring');
  const lines = r.stdout.split('\n').filter(Boolean).map((l) => JSON.parse(l));
  assert.deepEqual(lines.map((l) => l.role).sort(), ['Code Review', 'Validation']);
  for (const l of lines) {
    assert.ok(Number.isInteger(l.full_bytes) && Number.isInteger(l.delta_bytes), JSON.stringify(l));
    assert.ok(l.delta_bytes <= 0.4 * l.full_bytes, `${l.role}: ${l.delta_bytes} > 0.40 x ${l.full_bytes}`);
    const live = spawnSync(process.execPath, [path.join(SCRIPTS, 'canon.mjs'), 'build', '--role', l.role, '--ref', 'x'], { cwd: PROJECT_ROOT, encoding: 'utf8', env: cleanEnv() });
    assert.equal(live.status, 0, live.stderr);
    assert.equal(l.full_bytes, Buffer.byteLength(live.stdout, 'utf8'), l.role + ': the fixture full build must equal the live full build');
  }
});

// ------------------------------------------------------------------ TEST-2716
test('TEST-2716 the RFC-0017 phase 4 row records the byte pairs', () => {
  const text = fs.readFileSync(path.join(PROJECT_ROOT, 'docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md'), 'utf8');
  const fm = /^---\n([\s\S]*?)\n---/.exec(text);
  assert.ok(fm, 'no frontmatter');
  assert.match(fm[1], /^status:\s*implementing\s*$/m);
  assert.match(fm[1], /^umbrella:\s*true\s*$/m);
  const at = text.indexOf('Rollout Status');
  assert.ok(at >= 0, 'no Rollout Status');
  const rows = text.slice(at).split('\n').filter((l) => /^\|\s*[0-9]+\s*\|/.test(l)).map((l) => l.split('|').slice(1, -1).map((c) => c.trim()));
  const byPhase = {};
  for (const c of rows) byPhase[c[0]] = c;
  const statusOf = (n) => { assert.ok(byPhase[n], 'no phase ' + n + ' row'); return byPhase[n].join(' | '); };
  const four = byPhase['4'];
  assert.ok(four, 'no phase 4 row');
  const cellStatus = (c) => c.find((x) => /^(not started|in progress|done)$/i.test(x));
  assert.equal((cellStatus(four) || '').toLowerCase(), 'in progress');
  const joined = four.join(' | ');
  assert.match(joined, /\]\([^)]*cheap-transitions-slice\.md\)/, 'phase 4 row must link cheap-transitions-slice.md');
  const pairs = [...joined.matchAll(/([0-9]+) to ([0-9]+) bytes/g)].map((m) => [Number(m[1]), Number(m[2])]);
  assert.ok(pairs.length >= 2, 'want at least two N to M bytes pairs, got ' + pairs.length);
  for (const [n, m] of pairs) assert.ok(m <= 0.4 * n, `${n} to ${m} bytes is not at most 0.40`);
  for (const [n, want] of [['0', 'in progress'], ['2', 'in progress'], ['1', 'done'], ['3', 'done'], ['5', 'not started']]) {
    assert.equal((cellStatus(byPhase[n]) || '').toLowerCase(), want, 'phase ' + n + ' row: ' + statusOf(n).slice(0, 80));
  }
});

// ------------------------------------------------------------------ TEST-2717
test('TEST-2717 this ride stays full: ceremony_l3 on its own spec', async () => {
  const L = await lib();
  const specName = fs.readdirSync(path.join(PROJECT_ROOT, 'docs/specs')).find((f) => /-spec-cheap-transitions-slice\.md$/.test(f));
  assert.ok(specName, 'the cheap-transitions-slice spec is not under docs/specs');
  const specRel = 'docs/specs/' + specName;
  const fx = mkRepo('t2717', { verdicts: true, state: { ref: 'cheap-transitions-slice', spec: specRel } });
  fs.copyFileSync(path.join(PROJECT_ROOT, specRel), path.join(fx.root, specRel));
  appendEvents(fx.root, [
    { event: 'check_verdict', ref: 'cheap-transitions-slice', payload: { role: 'validation', head: fx.base, status: 'fail', security_relevant: false } },
    { event: 'check_verdict', ref: 'cheap-transitions-slice', payload: { role: 'code_review', head: fx.base, status: 'fail', security_relevant: false } },
  ]);
  fs.appendFileSync(path.join(fx.root, 'tests/skills/test-aai-base.sh'), 'echo more\n');
  for (const role of ['Validation', 'Code Review']) {
    const r = L.recheckMode({ root: fx.root, ref: 'cheap-transitions-slice', role, env: DELTA_ENV });
    assert.equal(r.mode, 'full', role);
    assert.ok(r.reasons.includes('ceremony_l3'), role + ': ' + reasonsOf(r));
  }
});

// ------------------------------------------------------------------ TEST-2718 / 2719
function readRel(rel) { return fs.readFileSync(path.join(PROJECT_ROOT, rel), 'utf8'); }

test('TEST-2718 the delta prompt and the wired prompts carry the required literals', () => {
  const delta = path.join(PROJECT_ROOT, '.aai/RECHECK_DELTA.prompt.md');
  assert.ok(fs.existsSync(delta), '.aai/RECHECK_DELTA.prompt.md does not exist');
  assert.ok(fs.statSync(delta).size <= 4096, 'RECHECK_DELTA.prompt.md is over 4096 bytes');
  const d = fs.readFileSync(delta, 'utf8');
  for (const lit of ['aai-outcome-v1', 'validation-outcome-check', 'security_relevant', 'needs_full_recheck', 'independent']) {
    assert.ok(d.includes(lit), 'RECHECK_DELTA.prompt.md lacks ' + lit);
  }
  const orch = readRel('.aai/ORCHESTRATION.prompt.md');
  assert.ok(orch.includes('--recheck delta'), 'ORCHESTRATION.prompt.md lacks --recheck delta');
  assert.ok(orch.split('\n').length - (orch.endsWith('\n') ? 1 : 0) <= 45, 'ORCHESTRATION.prompt.md is over 45 lines');
  // B-1: canon keys the stamps on the ref, so the documented command must pass the dispatch
  // JSON's ref_id, never HEAD. The wiring is pinned on the ref argument, not on a literal.
  const orchBuild = /canon\.mjs build --role (<[^>]+>|\S+) --ref ([^\s`]+)/.exec(orch);
  assert.ok(orchBuild, 'ORCHESTRATION.prompt.md has no canon.mjs build --role --ref command');
  assert.equal(orchBuild[2], '<ref_id>', 'ORCHESTRATION.prompt.md must build with --ref <ref_id>, got ' + orchBuild[2]);
  assert.ok(!/--ref HEAD\b/.test(orch), 'ORCHESTRATION.prompt.md still builds with --ref HEAD');
  assert.ok(orch.includes('recheck.fallback'), 'ORCHESTRATION.prompt.md does not say where the full identity comes from after a canon refusal');
  const par = readRel('.aai/ORCHESTRATION_PARALLEL.prompt.md');
  assert.ok(par.includes('canon.mjs build'), 'ORCHESTRATION_PARALLEL.prompt.md lacks canon.mjs build');
  assert.ok(/canon\.mjs build --role <R> --ref <r>`\s+\(<r> = the dispatch JSON's ref_id, never HEAD/.test(par) && !/--ref HEAD\b/.test(par), 'ORCHESTRATION_PARALLEL.prompt.md must define <r> as the dispatch ref_id');
  assert.ok(!par.includes('a copy of .aai/SUBAGENT_CONTRACT.md'), 'ORCHESTRATION_PARALLEL.prompt.md still pastes a copy of the contract');
  assert.ok(readRel('.aai/SKILL_CODE_REVIEW.prompt.md').includes('security_relevant'), 'SKILL_CODE_REVIEW.prompt.md lacks security_relevant');
  assert.ok(readRel('.aai/VALIDATION.prompt.md').includes('security_relevant'), 'VALIDATION.prompt.md lacks security_relevant');
});

test('TEST-2719 the protocol and the workflow describe the delta re-check', () => {
  const proto = readRel('.aai/SUBAGENT_PROTOCOL.md');
  const inputRow = proto.split('\n').find((l) => /^\|\s*`?INPUT`?\s*\|/.test(l));
  assert.ok(inputRow, 'no INPUT row in SUBAGENT_PROTOCOL.md');
  assert.ok(inputRow.includes('canon.mjs'), 'the INPUT row does not name canon.mjs');
  for (const lit of ['recheck=delta', 'AAI_RECHECK_MODE', 'needs_full_recheck']) assert.ok(proto.includes(lit), 'SUBAGENT_PROTOCOL.md lacks ' + lit);
  const wf = readRel('.aai/workflow/WORKFLOW.md').split('\n');
  assert.ok(wf.some((l) => /delta re-check/i.test(l) && l.includes('L3')), 'WORKFLOW.md has no line with delta re-check and L3');
});

// ------------------------------------------------------------------ TEST-2720 / 2721
test('TEST-2720 PROFILES lists the new files exactly once each, in core', () => {
  const text = readRel('.aai/system/PROFILES.yaml');
  const coreAt = text.search(/^core:\s*$/m);
  const extAt = text.search(/^extended:\s*$/m);
  assert.ok(coreAt >= 0 && extAt > coreAt, 'core/extended layout changed');
  for (const p of ['.aai/scripts/lib/recheck.mjs', '.aai/RECHECK_DELTA.prompt.md']) {
    const lines = text.split('\n').filter((l) => l.trim() === '- ' + p);
    assert.equal(lines.length, 1, p + ' must appear exactly once');
    const at = text.indexOf('- ' + p + '\n');
    assert.ok(at > coreAt && at < extAt, p + ' must be in the core list');
  }
});

test('TEST-2721 the suite map selects aai-recheck for each new file', () => {
  const select = (p) => spawnSync(process.execPath, [path.join(SCRIPTS, 'select-suites.mjs'), '--files-from', '-'], { cwd: PROJECT_ROOT, input: p + '\n', encoding: 'utf8', env: cleanEnv() });
  for (const p of ['.aai/RECHECK_DELTA.prompt.md', 'tests/skills/lib/recheck-measure.mjs', 'tests/skills/lib/recheck.test.mjs', '.aai/scripts/canon.mjs', '.aai/scripts/append-event.mjs']) {
    const r = select(p);
    assert.equal(r.status, 0, p + ': ' + r.stderr);
    assert.match(r.stdout, /^SELECTED aai-recheck\b/m, p + ' did not select aai-recheck: ' + r.stdout);
    assert.doesNotMatch(r.stdout, /FULL_RUN/, p + ' forced a full run');
  }
  // Spec-AC-12 (amended): a path under .aai/scripts/lib/ is a shared-library change, which
  // the selector escalates to a full run by design (suite-map.yaml
  // full_run_triggers.shared_lib_globs); a full run includes aai-recheck. The map row must
  // LIST the library even though the selector answers FULL_RUN, not SELECTED, for it.
  const map = readRel('tests/skills/suite-map.yaml');
  const row = map.slice(map.search(/^ {2}aai-recheck:\s*$/m));
  assert.ok(row.length < map.length, 'suite-map.yaml has no aai-recheck row');
  assert.match(row.split(/\n {2}[a-z0-9][a-z0-9-]*:\s*\n/)[0], /^ {6}- \.aai\/scripts\/lib\/recheck\.mjs$/m, 'the aai-recheck row does not list lib/recheck.mjs');
  const lib = select('.aai/scripts/lib/recheck.mjs');
  assert.match(lib.stdout, /^FULL_RUN reason=shared-lib path=\.aai\/scripts\/lib\/recheck\.mjs$/m, lib.stdout);
});

// ------------------------------------------------------------------ TEST-2723
test('TEST-2723 the six #497 amendments are signed and their follow-up is done', () => {
  const run = (script, args) => JSON.parse(execFileSync(process.execPath, [path.join(SCRIPTS, script), ...args], { cwd: PROJECT_ROOT, encoding: 'utf8', env: cleanEnv(), maxBuffer: 64 * 1024 * 1024 }));
  const sa = run('spec-amend.mjs', ['list', '--json']);
  const fu = run('follow-ups.mjs', ['list', '--status', 'all', '--json']);
  // Only the records that existed before this ride's remediation round 2: a later amendment of that ref
  // (remediation round 2, TEST-2623 row-4 scope) is an owner obligation of its own tracker.
  const mine = sa.items.filter((i) => i.ref_id === 'node-first-third-slice' && String(i.ts) < '2026-10-24T13:00:00Z');
  const signed = mine.filter((i) => i.bucket === 'signed');
  assert.ok(signed.length >= 6, 'only ' + signed.length + ' signed record(s) for node-first-third-slice, want at least 6');
  const other = mine.filter((i) => i.bucket !== 'signed' && i.bucket !== 'measurement');
  assert.deepEqual(other.map((i) => i.record_key + ' is ' + i.bucket), []);
  const f = fu.items.find((i) => i.id === 'fu-amend-spec-node-first-third-slice');
  assert.ok(f, 'fu-amend-spec-node-first-third-slice is not listed');
  assert.equal(f.status, 'done');
});

// ================================================== remediation round 1 (TEST-2724..2733)
const touchTest = (root) => fs.appendFileSync(path.join(root, 'tests/skills/test-aai-base.sh'), 'echo more\n');

// ------------------------------------------------------------------ TEST-2724
test('TEST-2724 the verdict base is the earliest unjudged dispatch head, never a re-tick head', async () => {
  const L = await lib();
  const { root } = mkRepo('t2724', { canon: true, verdicts: false });
  const H1 = git(root, ['rev-parse', 'HEAD']);
  const t1 = runDispatch(root, ['--confirm']);
  assert.equal(t1.out.role, 'Validation');
  // a production commit lands while the validator is still working, then the orchestrator re-ticks
  write(root, '.aai/scripts/inflight.mjs', 'export const inflight = 1;\n');
  git(root, ['add', '-A']);
  git(root, ['commit', '-q', '-m', 'production commit during the check']);
  const H2 = git(root, ['rev-parse', 'HEAD']);
  assert.notEqual(H1, H2);
  runDispatch(root, ['--confirm']);
  const dispatched = readEvents(root).filter((e) => e.event === 'check_dispatched' && e.payload.role === 'validation');
  assert.deepEqual(dispatched.map((e) => e.payload.head), [H1, H2], 'the re-tick at a new head appends a second dispatch');
  // the H1 validator returns fail; the next tick stamps the verdict
  const sv = stateCli(root, ['set-validation', '--status', 'fail', '--ref', REF, '--evidence', VAL_REL, '--notes', 'round 1']);
  assert.equal(sv.status, 0, sv.stderr + sv.stdout);
  runDispatch(root, ['--confirm']);
  const stamps = readEvents(root).filter((e) => e.event === 'check_verdict' && e.payload.role === 'validation');
  assert.equal(stamps.length, 1);
  assert.equal(stamps[0].payload.head, H1, 'the base is the head the checker was handed, not the re-tick head');
  // a test-only fix and the reset: the delta must still contain the unjudged production commit
  fs.appendFileSync(path.join(root, 'tests/skills/test-aai-base.sh'), 'echo fixed\n');
  git(root, ['commit', '-q', '-am', 'test-only fix']);
  const rb = stateCli(root, ['reset-block', 'last_validation']);
  assert.equal(rb.status, 0, rb.stderr + rb.stdout);
  const t3 = runDispatch(root, ['--confirm']);
  assert.equal(t3.out.role, 'Validation');
  assert.equal(rc(t3).mode, 'full', JSON.stringify(t3.out.recheck));
  assert.equal(rc(t3).base, H1);
  assert.ok(rc(t3).reasons.includes('production_path:.aai/scripts/inflight.mjs'), JSON.stringify(rc(t3).reasons));
  // fail closed: heads that are not on one line of history stamp an ambiguous base
  const amb = mkRepo('t2724-ambiguous', { verdicts: false });
  git(amb.root, ['checkout', '-q', '-b', 'side']);
  write(amb.root, 'tests/skills/side.sh', 'x\n');
  git(amb.root, ['add', '-A']);
  git(amb.root, ['commit', '-q', '-m', 'side']);
  const side = git(amb.root, ['rev-parse', 'HEAD']);
  git(amb.root, ['checkout', '-q', 'main']);
  const seen = 'run_at:2026-07-01T00:00:00Z';
  appendEvents(amb.root, [
    { event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: side, seen } },
    { event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: amb.base, seen } },
  ]);
  write(amb.root, 'docs/ai/STATE.yaml', stateYaml({ vstatus: 'fail', runAt: '2026-07-02T00:00:00Z' }));
  const plan = L.planCheckStamps({ root: amb.root, ref: REF, dispatchRole: null });
  assert.equal(plan.length, 1);
  assert.equal(plan[0].head, L.AMBIGUOUS_HEAD, 'divergent unjudged heads must stamp the ambiguous head');
  appendEvents(amb.root, [{ event: 'check_verdict', ref: REF, payload: { role: 'validation', head: plan[0].head, status: 'fail' } }]);
  touchTest(amb.root);
  const r = L.recheckMode({ root: amb.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(r.mode, 'full');
  assert.ok(r.reasons.includes('base_not_ancestor'), reasonsOf(r));
  // positive control: two dispatches on one line of history stamp the earlier one
  const lin = mkRepo('t2724-linear', { verdicts: false });
  write(lin.root, 'tests/skills/test-aai-more.sh', 'x\n');
  git(lin.root, ['add', '-A']);
  git(lin.root, ['commit', '-q', '-m', 'later']);
  appendEvents(lin.root, [
    { event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: lin.base, seen } },
    { event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: git(lin.root, ['rev-parse', 'HEAD']), seen } },
  ]);
  write(lin.root, 'docs/ai/STATE.yaml', stateYaml({ vstatus: 'fail', runAt: '2026-07-02T00:00:00Z' }));
  assert.equal(L.planCheckStamps({ root: lin.root, ref: REF, dispatchRole: null })[0].head, lin.base);
});

// ------------------------------------------------------------------ TEST-2725
test('TEST-2725 the documented canon command engages delta with the dispatch ref_id and a refusal keeps the full identity', () => {
  const orch = readRel('.aai/ORCHESTRATION.prompt.md');
  const m = /canon\.mjs build --role (<[^>]+>|\S+) --ref ([^\s`]+)/.exec(orch);
  assert.ok(m, 'ORCHESTRATION.prompt.md has no canon.mjs build command');
  const argv = (role, ref, extra) => ['build', '--role', role, '--ref', ref, ...extra];
  const { root } = eligibleCanon('t2725');
  const d = runDispatch(root);
  assert.equal(d.out.role, 'Validation');
  assert.equal(rc(d).mode, 'delta');
  // run the documented command literally: the template's ref argument filled from the dispatch JSON
  const refArg = m[2] === '<ref_id>' ? d.out.ref_id : m[2];
  const ok = canonRun(root, argv(d.out.role, refArg, ['--recheck', 'delta']));
  assert.equal(ok.status, 0, 'the documented command (--ref ' + m[2] + ') must engage delta: ' + ok.stderr);
  assert.ok(ok.stdout.includes('<<<AAI-CANON-SECTION recheck'), 'the delta payload was not assembled');
  // control: HEAD as the ref is the old wiring and canon refuses it
  const head = canonRun(root, argv(d.out.role, 'HEAD', ['--recheck', 'delta']));
  assert.equal(head.status, 11, '--ref HEAD must be refused: that is why the prompt passes ref_id');
  // the tree moves after the dispatch: canon refuses, and the dispatch already carries the full identity
  write(root, '.aai/scripts/late.mjs', 'export const late = 1;\n');
  git(root, ['add', '-A']);
  git(root, ['commit', '-q', '-m', 'production change after the dispatch']);
  const refused = canonRun(root, argv(d.out.role, d.out.ref_id, ['--recheck', 'delta']));
  assert.equal(refused.status, 11, refused.stderr);
  const fb = rc(d).fallback;
  assert.ok(fb && typeof fb.prompt_hash === 'string', 'a delta dispatch must carry recheck.fallback');
  assert.equal(fb.system_prompt, '.aai/VALIDATION.prompt.md');
  const fullHash = canonRun(root, ['build', '--role', 'Validation', '--ref', d.out.ref_id, '--print-hash']);
  assert.equal(fb.prompt_hash, fullHash.stdout.trim(), 'fallback.prompt_hash must be the full prompt hash canon computes');
  assert.notEqual(fb.prompt_hash, d.out.prompt_hash, 'the delta identity and the full identity must differ');
  const forced = runDispatch(root, [], { AAI_RECHECK_MODE: 'full' });
  assert.equal(forced.out.prompt_hash, fb.prompt_hash, 'the full dispatch records exactly the identity the fallback names');
  assert.equal(forced.out.system_prompt, fb.system_prompt);
  const proto = readRel('.aai/SUBAGENT_PROTOCOL.md');
  assert.ok(/recheck\.fallback/.test(proto) && /delta payload was actually sent/.test(proto), 'the protocol must say the delta note and hash are recorded only for a sent delta payload');
});

// ------------------------------------------------------------------ TEST-2726 / 2727
test('TEST-2726 a rename out of a production path refuses delta', async () => {
  const L = await lib();
  const { root } = mkRepo('t2726');
  git(root, ['mv', '.aai/scripts/x.mjs', 'tests/skills/test-aai-moved.sh']);
  const r = L.recheckMode({ root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(r.mode, 'full', 'a staged rename from .aai/scripts into tests must not be delta: ' + JSON.stringify(r.changed_paths));
  assert.ok(r.reasons.includes('production_path:.aai/scripts/x.mjs'), reasonsOf(r));
  assert.ok(r.changed_paths.includes('.aai/scripts/x.mjs') && r.changed_paths.includes('tests/skills/test-aai-moved.sh'), 'both ends of the rename are listed: ' + JSON.stringify(r.changed_paths));
  const ctl = mkRepo('t2726-control');
  git(ctl.root, ['mv', 'tests/skills/test-aai-base.sh', 'tests/skills/test-aai-renamed.sh']);
  const c = L.recheckMode({ root: ctl.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(c.mode, 'delta', 'control, a rename inside tests: ' + reasonsOf(c));
  assert.deepEqual(c.changed_paths, ['tests/skills/test-aai-base.sh', 'tests/skills/test-aai-renamed.sh']);
});

test('TEST-2727 a deleted production file refuses delta', async () => {
  const L = await lib();
  const staged = mkRepo('t2727-staged');
  git(staged.root, ['rm', '-q', '.aai/scripts/x.mjs']);
  touchTest(staged.root);
  const a = L.recheckMode({ root: staged.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(a.mode, 'full');
  assert.ok(a.reasons.includes('production_path:.aai/scripts/x.mjs'), reasonsOf(a));
  const loose = mkRepo('t2727-loose');
  fs.rmSync(path.join(loose.root, 'docs/knowledge/LEARNED.md'));
  touchTest(loose.root);
  const b = L.recheckMode({ root: loose.root, ref: REF, role: 'Code Review', env: DELTA_ENV });
  assert.ok(b.reasons.includes('production_path:docs/knowledge/LEARNED.md'), reasonsOf(b));
  const ctl = mkRepo('t2727-control');
  fs.rmSync(path.join(ctl.root, 'tests/skills/test-aai-guarded.sh'));
  touchTest(ctl.root);
  const c = L.recheckMode({ root: ctl.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(c.mode, 'delta', 'control, a deleted test file: ' + reasonsOf(c));
  assert.deepEqual(c.changed_paths, ['tests/skills/test-aai-base.sh', 'tests/skills/test-aai-guarded.sh']);
});

// ------------------------------------------------------------------ TEST-2728
test('TEST-2728 the delta cannot lower the ceremony level that decides its own eligibility', async () => {
  const L = await lib();
  const lowered = mkRepo('t2728-lowered', { level: 3 });
  write(lowered.root, SPEC_REL, specText(2));
  const a = L.recheckMode({ root: lowered.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(a.mode, 'full');
  assert.ok(a.reasons.includes('ceremony_l3'), 'an L3 spec rewritten to 2 inside the delta is still L3: ' + reasonsOf(a));
  const raised = mkRepo('t2728-raised', { level: 2 });
  write(raised.root, SPEC_REL, specText(3));
  assert.ok(L.recheckMode({ root: raised.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('ceremony_l3'), 'a level raised inside the delta counts');
  const gone = mkRepo('t2728-deleted', { level: 2 });
  fs.rmSync(path.join(gone.root, SPEC_REL));
  assert.ok(L.recheckMode({ root: gone.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('ceremony_unknown'), 'a spec deleted in the delta is unknown');
  const added = mkRepo('t2728-added', { spec: false });
  write(added.root, SPEC_REL, specText(2));
  const ad = L.recheckMode({ root: added.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.ok(ad.reasons.includes('ceremony_unknown'), 'a spec that did not exist at the base is unknown: ' + reasonsOf(ad));
  const stripped = mkRepo('t2728-stripped', { level: 2 });
  write(stripped.root, SPEC_REL, specText(undefined));
  assert.ok(L.recheckMode({ root: stripped.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('ceremony_unknown'), 'a level removed in the delta is unknown');
  // control: a body edit that leaves the level alone stays delta
  const ok = mkRepo('t2728-body', { level: 2 });
  fs.appendFileSync(path.join(ok.root, SPEC_REL), '\nAmended.\n');
  const o = L.recheckMode({ root: ok.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(o.mode, 'delta', 'control: ' + reasonsOf(o));
  assert.equal(o.spec_path, SPEC_REL);
});

// ------------------------------------------------------------------ TEST-2729
test('TEST-2729 prior-report markers come from the base commit and a changed prior report refuses', async () => {
  const L = await lib();
  const flipped = mkRepo('t2729-flipped', { revText: '# Review\n\nsecurity_relevant: true\n' });
  write(flipped.root, REV_REL, '# Review\n\nsecurity_relevant: false\n');
  const a = L.recheckMode({ root: flipped.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(a.mode, 'full');
  assert.ok(a.reasons.includes('prior_report_changed:' + REV_REL), reasonsOf(a));
  assert.ok(a.reasons.includes('security_relevant:' + REV_REL), 'the base blob still says true: ' + reasonsOf(a));
  const dropped = mkRepo('t2729-deleted');
  fs.rmSync(path.join(dropped.root, VAL_REL));
  const b = L.recheckMode({ root: dropped.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.ok(b.reasons.includes('prior_report_changed:' + VAL_REL), reasonsOf(b));
  const edited = mkRepo('t2729-edited');
  fs.appendFileSync(path.join(edited.root, REV_REL), '\nA late edit.\n');
  assert.ok(L.recheckMode({ root: edited.root, ref: REF, role: 'Code Review', env: DELTA_ENV }).reasons.includes('prior_report_changed:' + REV_REL), 'any edit of a prior report that existed at the base refuses');
  // control: the judged round's own report is written after the base and is read live
  const NEW_VAL = 'docs/ai/reports/VALIDATION-2.md';
  const NEW_REV = 'docs/ai/reviews/rev-2.md';
  const fresh = mkRepo('t2729-fresh', { state: { evidence: [NEW_VAL], reports: [NEW_REV] } });
  write(fresh.root, NEW_VAL, `# Validation 2\n\n${MARK_FALSE}`);
  write(fresh.root, NEW_REV, `# Review 2\n\n${MARK_FALSE}`);
  const c = L.recheckMode({ root: fresh.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(c.mode, 'delta', 'control: ' + reasonsOf(c));
  assert.deepEqual([...c.prior_reports].sort(), [NEW_REV, NEW_VAL].sort());
  const bad = mkRepo('t2729-fresh-true', { state: { evidence: [NEW_VAL], reports: [NEW_REV] } });
  write(bad.root, NEW_VAL, '# Validation 2\n\nsecurity_relevant: true\n');
  write(bad.root, NEW_REV, `# Review 2\n\n${MARK_FALSE}`);
  assert.ok(L.recheckMode({ root: bad.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('security_relevant:' + NEW_VAL), 'a new report that says true refuses');
});

// ------------------------------------------------------------------ TEST-2734
// NB-6: the judged round's own report is written after the base, so its marker is read live
// and an edit could flip it. The marker is recorded in the check_verdict stamp when the
// verdict is first seen, and eligibility trusts only the stamp.
const Q_VAL = 'docs/ai/reports/VALIDATION-2.md';
const Q_REV = 'docs/ai/reviews/rev-2.md';

// Builds the fixture of one judged round: the dispatch stamp at the base, the checker's own
// report (marker text given) written after the base, STATE showing the verdict, and the
// verdict stamp planned by planCheckStamps and appended as the dispatch would.
function judgedRound(L, name, tokenRole, markerText) {
  const fx = mkRepo(name, { verdicts: false, state: { vstatus: 'not_run', rstatus: 'not_run' } });
  const seen = tokenRole === 'validation' ? 'run_at:2026-07-01T00:00:00Z' : 'reports:1';
  appendEvents(fx.root, [{ event: 'check_dispatched', ref: REF, payload: { role: tokenRole, head: fx.base, seen } }]);
  const rel = tokenRole === 'validation' ? Q_VAL : Q_REV;
  write(fx.root, rel, markerText);
  write(fx.root, 'docs/ai/STATE.yaml', tokenRole === 'validation'
    ? stateYaml({ vstatus: 'fail', runAt: '2026-07-02T00:00:00Z', evidence: [Q_VAL] })
    : stateYaml({ vstatus: 'pass', rstatus: 'fail', reports: [REV_REL, Q_REV] }));
  const plan = L.planCheckStamps({ root: fx.root, ref: REF, dispatchRole: null });
  const stamp = plan.find((x) => x.event === 'check_verdict' && x.role === tokenRole);
  assert.ok(stamp, 'a verdict stamp is planned: ' + JSON.stringify(plan));
  appendEvents(fx.root, [{ event: 'check_verdict', ref: REF, payload: { role: tokenRole, head: stamp.head, status: stamp.status,
    ...(stamp.security_relevant === undefined ? {} : { security_relevant: stamp.security_relevant }) } }]);
  return { ...fx, stamp, rel };
}

test('TEST-2734 the stamped security marker decides: a flipped committed review report (Q8) and a flipped gitignored validation report (Q9) stay full', async () => {
  const L = await lib();
  // Q8: a committed Code Review report that said true at verdict time is flipped to false inside the delta.
  const q8 = judgedRound(L, 't2734-q8', 'code_review', '# Review 2\n\nsecurity_relevant: true\n');
  assert.equal(q8.stamp.security_relevant, true, 'the stamp records the marker read at verdict time');
  git(q8.root, ['add', '-A']);
  git(q8.root, ['commit', '-q', '-m', 'judged round report']);
  write(q8.root, Q_REV, '# Review 2\n\nsecurity_relevant: false\n');
  git(q8.root, ['commit', '-q', '-am', 'flip the marker inside the delta']);
  const r8 = L.recheckMode({ root: q8.root, ref: REF, role: 'Code Review', env: DELTA_ENV });
  assert.equal(r8.mode, 'full', 'Q8: ' + reasonsOf(r8));
  assert.ok(r8.reasons.includes('security_relevant:stamp:code_review'), reasonsOf(r8));
  // Q9: the Validation report is gitignored, so an in-place edit is not even visible in the delta.
  const q9 = judgedRound(L, 't2734-q9', 'validation', '# Validation 2\n\nsecurity_relevant: true\n');
  assert.equal(q9.stamp.security_relevant, true);
  fs.appendFileSync(path.join(q9.root, '.git/info/exclude'), Q_VAL + '\n');
  write(q9.root, Q_VAL, '# Validation 2\n\nsecurity_relevant: false\n');
  assert.equal(git(q9.root, ['status', '--porcelain', '--', Q_VAL]), '', 'the flip is invisible to git');
  const r9 = L.recheckMode({ root: q9.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(r9.mode, 'full', 'Q9: ' + reasonsOf(r9));
  assert.ok(r9.reasons.includes('security_relevant:stamp:validation'), reasonsOf(r9));
  // control: the same flow with a report that says false at verdict time stays delta, stamp false
  for (const role of ['validation', 'code_review']) {
    const ok = judgedRound(L, 't2734-ok-' + role, role, '# Round 2\n\nsecurity_relevant: false\n');
    assert.equal(ok.stamp.security_relevant, false);
    fs.appendFileSync(path.join(ok.root, 'tests/skills/test-aai-base.sh'), 'echo fix\n');
    const o = L.recheckMode({ root: ok.root, ref: REF, role: role === 'validation' ? 'Validation' : 'Code Review', env: DELTA_ENV });
    assert.equal(o.mode, 'delta', 'control ' + role + ': ' + reasonsOf(o));
  }
});

test('TEST-2735 a stamp without a marker is absent, and one stamped true keeps the role full for every later round', async () => {
  const L = await lib();
  // a report with no marker line: the stamp carries no marker, so the next round is full
  const none = judgedRound(L, 't2734-none', 'validation', '# Validation 2\n\nno marker here\n');
  assert.equal(none.stamp.security_relevant, undefined);
  fs.appendFileSync(path.join(none.root, 'tests/skills/test-aai-base.sh'), 'echo fix\n');
  const a = L.recheckMode({ root: none.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.ok(a.reasons.includes('security_marker_absent:stamp:validation'), reasonsOf(a));
  // a hand-written verdict stamp from before this field (no marker) is absent too
  const old = mkRepo('t2734-old', { verdicts: false });
  appendEvents(old.root, [{ event: 'check_verdict', ref: REF, payload: { role: 'validation', head: old.base, status: 'fail' } }]);
  fs.appendFileSync(path.join(old.root, 'tests/skills/test-aai-base.sh'), 'echo fix\n');
  assert.ok(L.recheckMode({ root: old.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('security_marker_absent:stamp:validation'));
  // sticky: an earlier stamp true, then a later stamp false for the same role: still full
  const st = mkRepo('t2734-sticky', { verdicts: false });
  appendEvents(st.root, [
    { event: 'check_verdict', ref: REF, payload: { role: 'validation', head: st.base, status: 'fail', security_relevant: true } },
    { event: 'check_verdict', ref: REF, payload: { role: 'validation', head: st.base, status: 'fail', security_relevant: false } },
  ]);
  fs.appendFileSync(path.join(st.root, 'tests/skills/test-aai-base.sh'), 'echo fix\n');
  const b = L.recheckMode({ root: st.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(b.mode, 'full');
  assert.ok(b.reasons.includes('security_relevant:stamp:validation'), reasonsOf(b));
  // a true stamp of the OTHER role also keeps this role full
  const oth = mkRepo('t2734-other', { verdicts: false });
  appendEvents(oth.root, [
    { event: 'check_verdict', ref: REF, payload: { role: 'code_review', head: oth.base, status: 'fail', security_relevant: true } },
    { event: 'check_verdict', ref: REF, payload: { role: 'validation', head: oth.base, status: 'fail', security_relevant: false } },
  ]);
  fs.appendFileSync(path.join(oth.root, 'tests/skills/test-aai-base.sh'), 'echo fix\n');
  assert.ok(L.recheckMode({ root: oth.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('security_relevant:stamp:code_review'));
});

test('TEST-2736 the real tick records the marker in the stamp and append-event validates it', () => {
  const { root } = eligibleCanon('t2734-tick');
  fs.rmSync(path.join(root, 'docs/ai/EVENTS.jsonl'));
  runDispatch(root, ['--confirm']);
  write(root, 'docs/ai/STATE.yaml', stateYaml({ vstatus: 'fail', runAt: '2026-07-02T00:00:00Z' }));
  runDispatch(root, ['--confirm']);
  const v = readEvents(root).filter((e) => e.event === 'check_verdict' && e.payload.role === 'validation');
  assert.equal(v.length, 1);
  assert.equal(v[0].payload.security_relevant, false, JSON.stringify(v[0]));
  const append = (args) => spawnSync(process.execPath, [path.join(SCRIPTS, 'append-event.mjs'), ...args], { cwd: root, encoding: 'utf8', env: cleanEnv() });
  const H = 'b'.repeat(40);
  const ok = append(['--event', 'check_verdict', '--ref', REF, '--role', 'validation', '--head', H, '--status', 'pass', '--security-relevant', 'true']);
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(readEvents(root).pop().payload.security_relevant, true);
  const n = readEvents(root).length;
  const bad = append(['--event', 'check_verdict', '--ref', REF, '--role', 'validation', '--head', H, '--status', 'pass', '--security-relevant', 'maybe']);
  assert.notEqual(bad.status, 0);
  assert.equal(readEvents(root).length, n, 'a malformed marker appends nothing');
});

// ------------------------------------------------------------------ TEST-2737
test('TEST-2737 every append-run capture site names the recheck.fallback clause', () => {
  for (const rel of ['.aai/SUBAGENT_PROTOCOL.md', '.aai/SKILL_LOOP.prompt.md']) {
    const text = readRel(rel);
    const sites = text.split('\n').filter((l) => /prompt[_ -]hash/i.test(l) && /--prompt-hash|append-run|JSON `prompt_hash`|JSON field/.test(l));
    assert.ok(sites.length >= 1, rel + ' has no prompt-hash capture site');
  }
  const proto = readRel('.aai/SUBAGENT_PROTOCOL.md');
  const loop = readRel('.aai/SKILL_LOOP.prompt.md');
  const count = (t) => (t.match(/recheck\.fallback/g) || []).length;
  assert.ok(count(proto) >= 3, 'SUBAGENT_PROTOCOL.md: the delta section and both capture sites name recheck.fallback, got ' + count(proto));
  assert.ok(count(loop) >= 1, 'SKILL_LOOP.prompt.md: the append-run capture step names recheck.fallback');
  // the three sites the review found, each on or next to its prompt_hash instruction
  const near = (t, anchor) => {
    const i = t.indexOf(anchor);
    assert.ok(i >= 0, 'anchor missing: ' + anchor);
    return t.slice(Math.max(0, i - 400), i + 700).includes('recheck.fallback');
  };
  assert.ok(near(proto, 'Prompt hash (SPEC-0098 consumer wiring)'), 'capture site 1 (SUBAGENT_PROTOCOL Harness-reported usage capture)');
  assert.ok(near(proto, 'whenever the dispatch JSON carried'), 'capture site 2 (SUBAGENT_PROTOCOL merge append)');
  assert.ok(near(loop, 'Dispatch printed `Prompt hash: <hex>`'), 'capture site 3 (SKILL_LOOP)');
});

// ------------------------------------------------------------------ TEST-2730
test('TEST-2730 gate inputs under tests/ are production; only test code is not', async () => {
  const L = await lib();
  for (const p of ['tests/skills/test-aai-x.sh', 'tests/skills/aai-y.Tests.ps1', 'tests/skills/lib/z.test.mjs']) assert.equal(L.isNonProduction(p), true, p);
  const gateInputs = [
    'tests/skills/suite-map.yaml', 'tests/skills/suite-weights.tsv', 'tests/skills/lib/base-ref-pin-baseline.tsv',
    'tests/skills/lib/cd-subshell-leak-baseline.tsv', 'tests/skills/lib/prompt-diet-ledger.sh', 'tests/skills/lib/pipe-grep-q-ratchet.sh',
    'tests/skills/test-framework.sh', 'tests/new-top-level/anything.yaml',
  ];
  for (const p of gateInputs) assert.equal(L.isNonProduction(p), false, p + ' is read by a production script and must be production');
  // the shared list: every tests/ path merge-policy guards is production here too
  const mp = await import(pathToFileURL(path.join(SCRIPTS, 'merge-policy.mjs')).href);
  const guarded = mp.GUARD_PATHS.filter((p) => p.startsWith('tests/'));
  assert.ok(guarded.length >= 1, 'merge-policy GUARD_PATHS names no tests/ file any more');
  for (const p of guarded) assert.equal(L.isNonProduction(p), false, 'merge-policy guards ' + p);
  // the derivation: every file under tests/ that a production script names by literal path
  const named = new Set();
  const scan = (dir) => {
    for (const f of fs.readdirSync(dir, { withFileTypes: true })) {
      const abs = path.join(dir, f.name);
      if (f.isDirectory()) { scan(abs); continue; }
      if (!/\.(mjs|sh)$/.test(f.name)) continue;
      for (const m of fs.readFileSync(abs, 'utf8').matchAll(/\btests\/[A-Za-z0-9_./-]+\.(?:yaml|yml|tsv|jsonl|json|sh|mjs|ps1)\b/g)) {
        if (fs.existsSync(path.join(PROJECT_ROOT, m[0])) && fs.statSync(path.join(PROJECT_ROOT, m[0])).isFile()) named.add(m[0]);
      }
    }
  };
  scan(SCRIPTS);
  assert.ok(named.size >= 8, 'the scan found only ' + named.size + ' named tests/ files; the derivation is broken');
  for (const p of ['tests/skills/suite-map.yaml', 'tests/skills/suite-weights.tsv', 'tests/skills/lib/base-ref-pin-baseline.tsv']) assert.ok(named.has(p), 'derivation must find ' + p);
  const isSuite = (p) => /^tests\/skills\/test-aai-[^/]+\.sh$/.test(p) || /^tests\/skills\/[^/]+\.Tests\.ps1$/.test(p) || /^tests\/skills\/lib\/[^/]+\.test\.mjs$/.test(p);
  for (const p of named) {
    assert.equal(L.isNonProduction(p), isSuite(p), p + (isSuite(p) ? ' is test code and must stay non-production' : ' is named by a production script and must be production'));
  }
  // end to end: a remediation that only raises a baseline or drops a suite-map row is not a delta
  const fx = mkRepo('t2730');
  write(fx.root, 'tests/skills/suite-map.yaml', 'suites: {}\n');
  git(fx.root, ['add', '-A']);
  git(fx.root, ['commit', '-q', '-m', 'map']);
  appendEvents(fx.root, verdictEvents(git(fx.root, ['rev-parse', 'HEAD'])));
  fs.appendFileSync(path.join(fx.root, 'tests/skills/suite-map.yaml'), '# dropped a row\n');
  const r = L.recheckMode({ root: fx.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(r.mode, 'full');
  assert.ok(r.reasons.includes('production_path:tests/skills/suite-map.yaml'), reasonsOf(r));
});

// ------------------------------------------------------------------ TEST-2731
test('TEST-2731 AAI_RECHECK_MODE is opt-in: only a value that normalises to delta enables the mode', async () => {
  const L = await lib();
  for (const v of ['full', 'FULL', ' Full ', 'full\n', '\tfull', 'off', '0', 'false', 'no', 'deltas', 'ful', undefined, '', '   ']) {
    assert.equal(L.deltaEnabled({ AAI_RECHECK_MODE: v }), false, JSON.stringify(v));
  }
  for (const v of ['delta', ' Delta ', 'DELTA', 'delta\n']) {
    assert.equal(L.deltaEnabled({ AAI_RECHECK_MODE: v }), true, JSON.stringify(v));
  }
  assert.equal(L.deltaEnabled({}), false);
  assert.equal(L.deltaEnabled(null), false);
  const { root } = mkRepo('t2731');
  touchTest(root);
  for (const v of [' FULL ', 'Full', 'nonsense']) {
    const r = L.recheckMode({ root, ref: REF, role: 'Validation', env: { AAI_RECHECK_MODE: v } });
    assert.equal(r.mode, 'full', JSON.stringify(v));
    assert.ok(r.reasons.includes('recheck_disabled'), JSON.stringify(v));
  }
  assert.equal(L.recheckMode({ root, ref: REF, role: 'Validation', env: { AAI_RECHECK_MODE: ' Delta ' } }).mode, 'delta');
  // the same through the dispatch (the env the orchestrator exports)
  const fx = eligibleCanon('t2731-dispatch');
  const d = runDispatch(fx.root, [], { AAI_RECHECK_MODE: ' FULL ' });
  assert.equal(rc(d).mode, 'full');
  assert.equal(d.out.system_prompt, '.aai/VALIDATION.prompt.md');
});

// ------------------------------------------------------------------ TEST-2738
test('TEST-2738 the default is full: an otherwise eligible tree with the variable unset gives recheck_disabled', async () => {
  const L = await lib();
  const { root } = mkRepo('t2738');
  touchTest(root);
  assert.equal(L.recheckMode({ root, ref: REF, role: 'Validation', env: DELTA_ENV }).mode, 'delta', 'positive control: the tree is eligible when opted in');
  for (const env of [{}, { AAI_RECHECK_MODE: '' }, { AAI_RECHECK_MODE: '  ' }, { AAI_RECHECK_MODE: 'full' }]) {
    const r = L.recheckMode({ root, ref: REF, role: 'Validation', env });
    assert.equal(r.mode, 'full', JSON.stringify(env));
    assert.deepEqual(r.reasons, ['recheck_disabled'], JSON.stringify(env));
  }
  // the dispatch and canon read the process env: scrubbed, they answer full
  const fx = eligibleCanon('t2738-dispatch');
  const optedIn = runDispatch(fx.root, []);
  assert.equal(rc(optedIn).mode, 'delta', 'dispatch positive control');
  const d = spawnSync(process.execPath, [path.join(SCRIPTS, 'orchestration-dispatch.mjs'), '--state', stateOf(fx.root), '--root', fx.root],
    { cwd: PROJECT_ROOT, encoding: 'utf8', env: unsetEnv() });
  const out = JSON.parse(d.stdout);
  assert.equal(out.recheck.mode, 'full');
  assert.ok(out.recheck.reasons.includes('recheck_disabled'));
  assert.equal(out.system_prompt, '.aai/VALIDATION.prompt.md');
  const c = spawnSync(process.execPath, [path.join(SCRIPTS, 'canon.mjs'), 'build', '--role', 'Validation', '--ref', REF, '--recheck', 'delta'],
    { cwd: fx.root, encoding: 'utf8', env: unsetEnv() });
  assert.equal(c.status, 11);
  assert.match(c.stderr, /recheck_disabled/);
});

// ------------------------------------------------------------------ TEST-2739
// B9/F7: EVENTS.jsonl is a tracked non-production ledger, so a delta may edit it. The
// sticky security stamp only holds if it is append-only across the range.
function mkTrackedLedgerRepo(name) {
  const fx = mkRepo(name, { verdicts: false, trackEvents: true });
  const ev = [{ event: 'check_verdict', ref: REF, payload: { role: 'validation', head: fx.base, status: 'fail', security_relevant: true } }];
  appendEvents(fx.root, ev);
  git(fx.root, ['add', '-A']);
  git(fx.root, ['commit', '-q', '-m', 'stamp true']);
  const stampCommit = git(fx.root, ['rev-parse', 'HEAD']);
  return { ...fx, stampCommit };
}

function flipTrueStamp(root) {
  const p = path.join(root, 'docs/ai/EVENTS.jsonl');
  fs.writeFileSync(p, fs.readFileSync(p, 'utf8').replace('"security_relevant":true', '"security_relevant":false'));
}

test('TEST-2739 an in-place rewrite of an earlier stamp refuses delta (ledger_rewritten)', async () => {
  const L = await lib();
  // control: a pure append of a later false stamp is still sticky-true full, and an append-only
  // ledger with a clean false history is delta
  const ok = mkRepo('t2739-ctl', { verdicts: false, trackEvents: true });
  appendEvents(ok.root, verdictEvents(ok.base));
  git(ok.root, ['add', '-A']);
  git(ok.root, ['commit', '-q', '-m', 'stamps false']);
  appendEvents(ok.root, [{ event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: ok.base, seen: 'run_at:x' } }]);
  touchTest(ok.root);
  const c = L.recheckMode({ root: ok.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(c.mode, 'delta', 'append-only control: ' + reasonsOf(c));
  // uncommitted rewrite
  const live = mkTrackedLedgerRepo('t2739-live');
  flipTrueStamp(live.root);
  touchTest(live.root);
  const a = L.recheckMode({ root: live.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(a.mode, 'full');
  assert.ok(a.reasons.includes('ledger_rewritten'), reasonsOf(a));
  // committed rewrite of a line that predates the base
  const done = mkTrackedLedgerRepo('t2739-committed');
  const stampHead = done.stampCommit;
  appendEvents(done.root, [{ event: 'check_verdict', ref: REF, payload: { role: 'code_review', head: stampHead, status: 'fail', security_relevant: false } }]);
  git(done.root, ['commit', '-qam', 'second stamp']);
  flipTrueStamp(done.root);
  git(done.root, ['commit', '-qam', 'rewrite']);
  touchTest(done.root);
  const b = L.recheckMode({ root: done.root, ref: REF, role: 'Code Review', env: DELTA_ENV });
  assert.equal(b.mode, 'full');
  assert.ok(b.reasons.includes('ledger_rewritten'), reasonsOf(b));
  // truncation drops the stamp itself, so the round is first_round and full
  const cut = mkTrackedLedgerRepo('t2739-cut');
  fs.writeFileSync(path.join(cut.root, 'docs/ai/EVENTS.jsonl'), '');
  touchTest(cut.root);
  const t = L.recheckMode({ root: cut.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(t.mode, 'full');
  assert.ok(t.reasons.includes('first_round'), reasonsOf(t));
});

// ------------------------------------------------------------------ TEST-2740
test('TEST-2740 a committed rewrite inside the delta range refuses delta even when the ends look appended', async () => {
  const L = await lib();
  const fx = mkRepo('t2740', { verdicts: false, trackEvents: true });
  appendEvents(fx.root, verdictEvents(fx.base));
  git(fx.root, ['add', '-A']);
  git(fx.root, ['commit', '-q', '-m', 'stamps false']);
  const stamped = git(fx.root, ['rev-parse', 'HEAD']);
  // inside the range: C1 appends a true stamp, C2 rewrites it to false and appends more
  appendEvents(fx.root, [{ event: 'check_verdict', ref: REF, payload: { role: 'validation', head: stamped, status: 'fail', security_relevant: true } }]);
  git(fx.root, ['commit', '-qam', 'C1 true stamp']);
  flipTrueStamp(fx.root);
  appendEvents(fx.root, [{ event: 'check_verdict', ref: REF, payload: { role: 'validation', head: stamped, status: 'fail', security_relevant: false } }]);
  git(fx.root, ['commit', '-qam', 'C2 rewrite and append']);
  touchTest(fx.root);
  const r = L.recheckMode({ root: fx.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(r.mode, 'full');
  assert.ok(r.reasons.includes('ledger_rewritten'), reasonsOf(r));
  // the same range with C2 a pure append stays eligible by this rule
  const clean = mkRepo('t2740-ctl', { verdicts: false, trackEvents: true });
  appendEvents(clean.root, verdictEvents(clean.base));
  git(clean.root, ['add', '-A']);
  git(clean.root, ['commit', '-q', '-m', 'stamps false']);
  appendEvents(clean.root, [{ event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: clean.base, seen: 'run_at:x' } }]);
  git(clean.root, ['commit', '-qam', 'append only']);
  touchTest(clean.root);
  const k = L.recheckMode({ root: clean.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.ok(!k.reasons.includes('ledger_rewritten'), reasonsOf(k));
});

// ------------------------------------------------------------------ TEST-2741
test('TEST-2741 append-event refuses check_dispatched and check_verdict when AAI_ROLE is set', () => {
  const { root } = mkRepo('t2741', { verdicts: false });
  const H = 'c'.repeat(40);
  const run = (args, env) => spawnSync(process.execPath, [path.join(SCRIPTS, 'append-event.mjs'), ...args], { cwd: root, encoding: 'utf8', env });
  const verdict = ['--event', 'check_verdict', '--ref', REF, '--role', 'validation', '--head', H, '--status', 'pass', '--security-relevant', 'false'];
  const dispatched = ['--event', 'check_dispatched', '--ref', REF, '--role', 'validation', '--head', H, '--seen', 'run_at:x'];
  let appended = 0;
  for (const args of [verdict, dispatched]) {
    const refused = run(args, { ...cleanEnv(), AAI_ROLE: 'subagent' });
    assert.notEqual(refused.status, 0, args[1]);
    assert.match(refused.stderr, /single-writer/, args[1]);
    assert.equal(readEvents(root).length, appended, 'a refused stamp appends nothing');
    const ok = run(args, cleanEnv());
    assert.equal(ok.status, 0, ok.stderr);
    appended += 1;
  }
  assert.equal(readEvents(root).length, 2);
  // other event types are untouched by the guard
  const other = run(['--event', 'phase_confirmed', '--ref', REF, '--phase', 'validation'], { ...cleanEnv(), AAI_ROLE: 'subagent' });
  assert.ok(!/single-writer/.test(other.stderr), other.stderr);
});

// ------------------------------------------------------------------ TEST-2742
// KNOWN RESIDUAL, pinned on purpose (fu-recheck-verdict-not-bound-to-check, which also covers the
// former fu-recheck-uncommitted-stamp-rewrite): with delta opted in, the check_* stamps in
// docs/ai/EVENTS.jsonl are not tamper-proof. ledger_rewritten compares only the base and HEAD
// blobs, the live file and the commits of base..HEAD; merge_in_range sees only merges in
// base..HEAD. Any stamp rewrite ledger_rewritten does not see (an uncommitted flip, a rewrite
// committed before the base, commit --amend, a rebase that drops it, a squash resolved to ours,
// git replace in any form, any other history rewrite) and any hand-appended forged stamp can yield
// delta. Only the verdict-to-STATE binding closes it; delta must not become default-on before.
// When that lands, the delta assertions below flip to full and this test is rewritten.
test('TEST-2742 KNOWN RESIDUAL: an uncommitted true stamp flipped before its first commit gives delta under the opt-in, full by default', async () => {
  const L = await lib();
  const fx = mkRepo('t2742', { verdicts: false, trackEvents: true });
  appendEvents(fx.root, [
    { event: 'check_verdict', ref: REF, payload: { role: 'validation', head: fx.base, status: 'fail', security_relevant: true } },
    { event: 'check_verdict', ref: REF, payload: { role: 'code_review', head: fx.base, status: 'pass', security_relevant: false } },
  ]);
  touchTest(fx.root);
  const before = L.recheckMode({ root: fx.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(before.mode, 'full', 'positive control: the unflipped true stamp is sticky');
  assert.ok(before.reasons.includes('security_relevant:stamp:validation'), reasonsOf(before));
  flipTrueStamp(fx.root);
  const after = L.recheckMode({ root: fx.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(after.mode, 'delta', 'today the uncommitted flip is NOT caught (residual): ' + reasonsOf(after));
  assert.ok(!after.reasons.includes('ledger_rewritten'));
  const dflt = L.recheckMode({ root: fx.root, ref: REF, role: 'Validation', env: {} });
  assert.equal(dflt.mode, 'full', 'the default env stays full');
  assert.deepEqual(dflt.reasons, ['recheck_disabled']);

  // The amend shape of the same residual: a true stamp is committed after the base, then flipped
  // and folded into that commit with --amend, so the rewritten commit is the only one reachable.
  const am = mkRepo('t2742-amend', { verdicts: false, trackEvents: true });
  appendEvents(am.root, [
    { event: 'check_verdict', ref: REF, payload: { role: 'validation', head: am.base, status: 'fail', security_relevant: true } },
    { event: 'check_verdict', ref: REF, payload: { role: 'code_review', head: am.base, status: 'pass', security_relevant: false } },
  ]);
  git(am.root, ['add', '-A']);
  git(am.root, ['commit', '-qm', 'true stamp']);
  touchTest(am.root);
  const sticky = L.recheckMode({ root: am.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(sticky.mode, 'full', 'positive control: the committed true stamp is sticky');
  flipTrueStamp(am.root);
  git(am.root, ['commit', '-qa', '--amend', '--no-edit']);
  const amended = L.recheckMode({ root: am.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(amended.mode, 'delta', 'today the amended flip is NOT caught (residual): ' + reasonsOf(amended));
  assert.ok(!amended.reasons.includes('ledger_rewritten'));
  const amendedDefault = L.recheckMode({ root: am.root, ref: REF, role: 'Validation', env: {} });
  assert.equal(amendedDefault.mode, 'full', 'the default env stays full');
  assert.deepEqual(amendedDefault.reasons, ['recheck_disabled']);
});

// ------------------------------------------------------------------ TEST-2743
test('TEST-2743 a merge commit in the delta range refuses delta (merge_in_range): merge -s ours drops a committed true stamp', async () => {
  const L = await lib();
  const mk = (name) => {
    const fx = mkRepo(name, { verdicts: false, trackEvents: true });
    appendEvents(fx.root, verdictEvents(fx.base));
    git(fx.root, ['add', '-A']);
    git(fx.root, ['commit', '-q', '-m', 'stamps false']);
    return { ...fx, stamped: git(fx.root, ['rev-parse', 'HEAD']) };
  };
  const fx = mk('t2743');
  git(fx.root, ['checkout', '-q', '-b', 'side']);
  appendEvents(fx.root, [{ event: 'check_verdict', ref: REF, payload: { role: 'validation', head: fx.stamped, status: 'fail', security_relevant: true } }]);
  git(fx.root, ['commit', '-qam', 'side: true stamp']);
  git(fx.root, ['checkout', '-q', 'main']);
  appendEvents(fx.root, [{ event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: fx.stamped, seen: 'run_at:x' } }]);
  git(fx.root, ['commit', '-qam', 'main: append']);
  git(fx.root, ['merge', '-q', '-s', 'ours', '-m', 'drop side', 'side']);
  assert.ok(!fs.readFileSync(path.join(fx.root, 'docs/ai/EVENTS.jsonl'), 'utf8').includes('"security_relevant":true'), 'positive control: the true stamp is gone from the live ledger');
  touchTest(fx.root);
  const r = L.recheckMode({ root: fx.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(r.mode, 'full');
  assert.ok(r.reasons.includes('merge_in_range'), reasonsOf(r));
  // control: a linear range of the same shape has no merge and stays delta
  const lin = mk('t2743-ctl');
  appendEvents(lin.root, [{ event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: lin.stamped, seen: 'run_at:x' } }]);
  git(lin.root, ['commit', '-qam', 'append']);
  touchTest(lin.root);
  const k = L.recheckMode({ root: lin.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(k.mode, 'delta', reasonsOf(k));
});

// ------------------------------------------------------------------ TEST-2744
test('TEST-2744 a whitespace-only AAI_ROLE counts as set: append-event refuses the check stamps', () => {
  const { root } = mkRepo('t2744', { verdicts: false });
  const H = 'c'.repeat(40);
  const run = (env) => spawnSync(process.execPath, [path.join(SCRIPTS, 'append-event.mjs'), '--event', 'check_verdict', '--ref', REF, '--role', 'validation', '--head', H, '--status', 'pass', '--security-relevant', 'false'], { cwd: root, encoding: 'utf8', env });
  for (const v of [' ', '  ', '\t']) {
    const refused = run({ ...cleanEnv(), AAI_ROLE: v });
    assert.notEqual(refused.status, 0, JSON.stringify(v));
    assert.match(refused.stderr, /single-writer/, JSON.stringify(v));
  }
  assert.equal(readEvents(root).length, 0);
  assert.equal(run(cleanEnv()).status, 0, 'positive control: unset appends');
});

// ------------------------------------------------------------------ TEST-2732
test('TEST-2732 an inherited property name is an unknown role, not a crash', async () => {
  const L = await lib();
  const { root } = mkRepo('t2732');
  touchTest(root);
  for (const role of ['__proto__', 'constructor', 'toString', 'hasOwnProperty', 'valueOf']) {
    let r;
    assert.doesNotThrow(() => { r = L.recheckMode({ root, ref: REF, role, env: DELTA_ENV }); }, role);
    assert.equal(r.mode, 'full', role);
    assert.ok(r.reasons.includes('role_not_rechecked'), role + ': ' + reasonsOf(r));
    assert.doesNotThrow(() => L.planCheckStamps({ root, ref: REF, dispatchRole: role }), role);
  }
  assert.equal(L.tokenOfRole('Validation'), 'validation');
  assert.equal(L.tokenOfRole('Code Review'), 'code_review');
  assert.equal(L.tokenOfRole('__proto__'), null);
  const c = canonRun(root, ['build', '--role', '__proto__', '--ref', REF, '--recheck', 'delta']);
  assert.ok(!/at .*recheck\.mjs/.test(c.stderr), 'canon must refuse an inherited role name without a stack trace: ' + c.stderr.slice(0, 300));
  assert.notEqual(c.status, 0);
});

// ------------------------------------------------------------------ TEST-2733
test('TEST-2733 the delta payload carries the output contracts and the scope names the spec', () => {
  const prompt = readRel('.aai/RECHECK_DELTA.prompt.md');
  assert.ok(Buffer.byteLength(prompt, 'utf8') <= 4096, 'RECHECK_DELTA.prompt.md is over 4096 bytes');
  for (const lit of ['docs/ai/reviews/review-', 'docs/validation', 'H6', 'accepted residual', 'set-code-review', 'set-validation',
    'aai-outcome-v1', 'validation-outcome-check.mjs', 'Before any PASS', 'outcome_report', 'state_update_commands', 'security_relevant']) {
    assert.ok(prompt.includes(lit), 'RECHECK_DELTA.prompt.md lacks ' + lit);
  }
  // each contract section the prompt points at exists in the full prompt it names
  assert.match(readRel('.aai/SKILL_CODE_REVIEW.prompt.md'), /^## REPORT$/m);
  assert.match(readRel('.aai/SKILL_CODE_REVIEW.prompt.md'), /^## WARNINGS POLICY WITH TEETH/m);
  assert.match(readRel('.aai/VALIDATION.prompt.md'), /^6\) Build the coverage table/m);
  const { root } = eligibleCanon('t2733');
  for (const role of ['Validation', 'Code Review']) {
    const r = canonRun(root, ['build', '--role', role, '--ref', REF, '--recheck', 'delta']);
    assert.equal(r.status, 0, r.stderr);
    const scope = r.stdout.slice(r.stdout.indexOf('<<<AAI-CANON-SECTION scope'));
    assert.ok(scope.split('\n').includes('spec: ' + SPEC_REL), role + ': the scope must name the spec path: ' + scope.slice(0, 300));
  }
});
