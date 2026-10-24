// recheck.test.mjs - node:test cases for the delta re-check mode
// (docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md, TEST-2701..2723).
// Every case builds a temporary git repository under the OS temp directory; the
// shipping tree is only read. Each case name starts with its TEST id so
// test-aai-recheck.sh can run one id at a time (node --test --test-name-pattern).
//
// SELF-HOSTING: the cases scrub AAI_RECHECK_MODE from every child process and
// pass an explicit env to recheckMode, so the suite gives the same answer when the
// rider exports AAI_RECHECK_MODE=full.
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

function cleanEnv(extra = {}) {
  const env = { ...process.env };
  delete env.AAI_RECHECK_MODE;
  delete env.AAI_ROLE;
  return { ...env, ...extra };
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
  return roles.map((role) => ({ event: 'check_verdict', ref: REF, payload: { role, head: base, status: 'fail' } }));
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
  write(root, '.gitignore', 'docs/ai/STATE.yaml\ndocs/ai/EVENTS.jsonl\n');
  write(root, 'docs/ai/docs-audit.yaml', o.audit ?? DEFAULT_AUDIT);
  if (o.spec !== false) write(root, SPEC_REL, specText('level' in o ? o.level : 2));
  write(root, REV_REL, o.revText ?? `# Review\n\n${MARK_FALSE}`);
  write(root, VAL_REL, o.valText ?? `# Validation\n\n${MARK_FALSE}`);
  write(root, '.aai/scripts/x.mjs', 'export const x = 1;\n');
  write(root, '.aai/workflow/WORKFLOW.md', '# Workflow fixture\n');
  write(root, 'docs/TECHNOLOGY.md', '# Technology fixture\n');
  write(root, 'docs/knowledge/LEARNED.md', '# Learned fixture\n');
  write(root, 'docs/ai/decisions.jsonl', '{"type":"x"}\n');
  write(root, 'tests/skills/base-test.sh', '#!/usr/bin/env bash\necho base\n');
  write(root, 'tests/skills/guarded.sh', '#!/usr/bin/env bash\necho guarded\n');
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
  fs.appendFileSync(path.join(root, 'tests/skills/base-test.sh'), 'echo more\n');
  write(root, 'docs/specs/new-note.md', '# note\n');
  fs.appendFileSync(path.join(root, 'docs/ai/decisions.jsonl'), '{"type":"y"}\n');
  const head = git(root, ['rev-parse', 'HEAD']);
  for (const role of ['Validation', 'Code Review']) {
    const r = L.recheckMode({ root, ref: REF, role, env: {} });
    assert.deepEqual(r.reasons, [], reasonsOf(r));
    assert.equal(r.mode, 'delta');
    assert.equal(r.base, base);
    assert.equal(r.head, head);
    assert.deepEqual(r.changed_paths, ['docs/ai/decisions.jsonl', 'docs/specs/new-note.md', 'tests/skills/base-test.sh']);
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
    const r = L.recheckMode({ root, ref: REF, role: 'Validation', env: {} });
    assert.equal(r.mode, 'full', name);
    assert.ok(r.reasons.includes('production_path:' + p), name + ': ' + reasonsOf(r));
  }
  const { root } = mkRepo('t2703-mixed');
  fs.appendFileSync(path.join(root, '.aai/scripts/x.mjs'), '// edit\n');
  fs.appendFileSync(path.join(root, 'tests/skills/base-test.sh'), 'echo more\n');
  const r = L.recheckMode({ root, ref: REF, role: 'Code Review', env: {} });
  assert.deepEqual(r.reasons.filter((x) => x.startsWith('production_path:')), ['production_path:.aai/scripts/x.mjs']);
});

// ------------------------------------------------------------------ TEST-2704
test('TEST-2704 a protected path refuses delta; the same change without the entry gives delta', async () => {
  const L = await lib();
  const guardedAudit = 'protected_paths_l3:\n  - tests/skills/guarded.sh\n';
  const change = (root) => fs.appendFileSync(path.join(root, 'tests/skills/guarded.sh'), 'echo more\n');
  const control = mkRepo('t2704-control');
  change(control.root);
  const c = L.recheckMode({ root: control.root, ref: REF, role: 'Validation', env: {} });
  assert.equal(c.mode, 'delta', 'positive control: ' + reasonsOf(c));
  const prot = mkRepo('t2704-protected', { audit: guardedAudit });
  change(prot.root);
  const p = L.recheckMode({ root: prot.root, ref: REF, role: 'Validation', env: {} });
  assert.equal(p.mode, 'full');
  assert.ok(p.reasons.includes('protected_path:tests/skills/guarded.sh'), reasonsOf(p));
  const bad = mkRepo('t2704-unreadable');
  fs.rmSync(path.join(bad.root, 'docs/ai/docs-audit.yaml'));
  fs.mkdirSync(path.join(bad.root, 'docs/ai/docs-audit.yaml'));
  const u = L.recheckMode({ root: bad.root, ref: REF, role: 'Validation', env: {} });
  assert.equal(u.mode, 'full');
  assert.ok(u.reasons.includes('protected_config_unreadable'), reasonsOf(u));
  const absent = mkRepo('t2704-absent');
  fs.rmSync(path.join(absent.root, 'docs/ai/docs-audit.yaml'));
  const a = L.recheckMode({ root: absent.root, ref: REF, role: 'Validation', env: {} });
  assert.ok(a.reasons.includes('protected_config_unreadable'), 'absent config: ' + reasonsOf(a));
});

// ------------------------------------------------------------------ TEST-2705
test('TEST-2705 security marker refusals', async () => {
  const L = await lib();
  const touch = (root) => fs.appendFileSync(path.join(root, 'tests/skills/base-test.sh'), 'echo more\n');
  const ok = mkRepo('t2705-ok');
  touch(ok.root);
  assert.equal(L.recheckMode({ root: ok.root, ref: REF, role: 'Validation', env: {} }).mode, 'delta', 'positive control');

  const t = mkRepo('t2705-true', { revText: '# Review\n\nsecurity_relevant: true\n' });
  touch(t.root);
  const rt = L.recheckMode({ root: t.root, ref: REF, role: 'Validation', env: {} });
  assert.equal(rt.mode, 'full');
  assert.ok(rt.reasons.includes('security_relevant:' + REV_REL), reasonsOf(rt));

  const none = mkRepo('t2705-none', { valText: '# Validation\n\nno marker here\n' });
  touch(none.root);
  assert.ok(L.recheckMode({ root: none.root, ref: REF, role: 'Validation', env: {} }).reasons.includes('security_marker_absent:' + VAL_REL));

  const twice = mkRepo('t2705-twice', { valText: `# Validation\n\n${MARK_FALSE}${MARK_FALSE}` });
  touch(twice.root);
  assert.ok(L.recheckMode({ root: twice.root, ref: REF, role: 'Validation', env: {} }).reasons.includes('security_marker_absent:' + VAL_REL));

  const missing = mkRepo('t2705-missing');
  fs.rmSync(path.join(missing.root, VAL_REL));
  const rm = L.recheckMode({ root: missing.root, ref: REF, role: 'Validation', env: {} });
  assert.ok(rm.reasons.includes('prior_report_unreadable:' + VAL_REL), reasonsOf(rm));

  const noReport = mkRepo('t2705-noreport', { state: { evidence: [] } });
  touch(noReport.root);
  const rn = L.recheckMode({ root: noReport.root, ref: REF, role: 'Validation', env: {} });
  assert.ok(rn.reasons.includes('security_marker_absent:validation'), reasonsOf(rn));
});

// ------------------------------------------------------------------ TEST-2706
test('TEST-2706 first round, ceremony, ancestry, empty delta, forced and git refusals', async () => {
  const L = await lib();
  const touch = (root) => fs.appendFileSync(path.join(root, 'tests/skills/base-test.sh'), 'echo more\n');

  const first = mkRepo('t2706-first', { verdicts: false });
  touch(first.root);
  const f = L.recheckMode({ root: first.root, ref: REF, role: 'Validation', env: {} });
  assert.equal(f.mode, 'full');
  assert.ok(f.reasons.includes('first_round'), reasonsOf(f));

  const only = mkRepo('t2706-onerole', { verdictRoles: ['validation'] });
  touch(only.root);
  assert.equal(L.recheckMode({ root: only.root, ref: REF, role: 'Validation', env: {} }).mode, 'delta', 'a verdict for the other role must not matter');
  assert.ok(L.recheckMode({ root: only.root, ref: REF, role: 'Code Review', env: {} }).reasons.includes('first_round'));

  const l3 = mkRepo('t2706-l3', { level: 3 });
  touch(l3.root);
  assert.ok(L.recheckMode({ root: l3.root, ref: REF, role: 'Validation', env: {} }).reasons.includes('ceremony_l3'));

  const nolevel = mkRepo('t2706-nolevel', { level: undefined });
  touch(nolevel.root);
  assert.ok(L.recheckMode({ root: nolevel.root, ref: REF, role: 'Validation', env: {} }).reasons.includes('ceremony_unknown'));

  const nospec = mkRepo('t2706-nospec', { spec: false });
  touch(nospec.root);
  assert.ok(L.recheckMode({ root: nospec.root, ref: REF, role: 'Validation', env: {} }).reasons.includes('ceremony_unknown'));

  for (const lvl of [0, 1]) {
    const ok = mkRepo('t2706-lvl' + lvl, { level: lvl });
    touch(ok.root);
    assert.equal(L.recheckMode({ root: ok.root, ref: REF, role: 'Validation', env: {} }).mode, 'delta', 'level ' + lvl);
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
  assert.ok(L.recheckMode({ root: sib.root, ref: REF, role: 'Validation', env: {} }).reasons.includes('base_not_ancestor'));

  const empty = mkRepo('t2706-empty');
  const e = L.recheckMode({ root: empty.root, ref: REF, role: 'Validation', env: {} });
  assert.equal(e.mode, 'full');
  assert.ok(e.reasons.includes('no_delta'), reasonsOf(e));

  const forced = mkRepo('t2706-forced');
  touch(forced.root);
  const fr = L.recheckMode({ root: forced.root, ref: REF, role: 'Validation', env: { AAI_RECHECK_MODE: 'full' } });
  assert.equal(fr.mode, 'full');
  assert.ok(fr.reasons.includes('forced_full'));
  assert.equal(L.recheckMode({ root: forced.root, ref: REF, role: 'Validation', env: { AAI_RECHECK_MODE: 'delta' } }).mode, 'delta');

  const notGit = path.join(tmpTop, 't2706-nogit');
  fs.mkdirSync(notGit, { recursive: true });
  const g = L.recheckMode({ root: notGit, ref: REF, role: 'Validation', env: {} });
  assert.equal(g.mode, 'full');
  assert.ok(g.reasons.includes('git_error'), reasonsOf(g));

  const both = mkRepo('t2706-both', { verdicts: false });
  fs.appendFileSync(path.join(both.root, '.aai/scripts/x.mjs'), '// edit\n');
  const b = L.recheckMode({ root: both.root, ref: REF, role: 'Validation', env: {} });
  assert.ok(b.reasons.includes('first_round') && b.reasons.includes('production_path:.aai/scripts/x.mjs'), reasonsOf(b));

  const rem = mkRepo('t2706-role');
  touch(rem.root);
  assert.ok(L.recheckMode({ root: rem.root, ref: REF, role: 'Remediation', env: {} }).reasons.includes('role_not_rechecked'));
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
  fs.appendFileSync(path.join(fx.root, 'tests/skills/base-test.sh'), 'echo more\n');
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
  assert.deepEqual(rc(a), L.recheckMode({ root, ref: REF, role: 'Validation', env: {} }));
  assert.equal(a.out.system_prompt, '.aai/RECHECK_DELTA.prompt.md');
  // rule 13: validation passed, review required and missing
  write(root, 'docs/ai/STATE.yaml', stateYaml({ vstatus: 'pass', rstatus: 'not_run' }));
  const b = runDispatch(root);
  assert.equal(b.out.rule, '13', JSON.stringify(b.out));
  assert.equal(b.out.role, 'Code Review');
  assert.equal(rc(b).mode, 'delta', JSON.stringify(b.out.recheck));
  assert.deepEqual(rc(b), L.recheckMode({ root, ref: REF, role: 'Code Review', env: {} }));
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
  assert.ok(rc(e).reasons.includes('forced_full'));
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
  fs.appendFileSync(path.join(root, 'tests/skills/base-test.sh'), 'echo fixed\n');
  git(root, ['commit', '-q', '-am', 'test-only fix']);
  const rb = stateCli(root, ['reset-block', 'last_validation']);
  assert.equal(rb.status, 0, rb.stderr + rb.stdout);
  const t3 = runDispatch(root, ['--confirm']);
  assert.equal(t3.out.rule, '11');
  assert.equal(rc(t3).mode, 'delta', JSON.stringify(t3.out.recheck));
  assert.equal(rc(t3).base, H1);
  assert.deepEqual(rc(t3).changed_paths, ['tests/skills/base-test.sh']);
  const c = canonRun(root, ['build', '--role', 'Validation', '--ref', REF, '--recheck', 'delta']);
  assert.equal(c.status, 0, c.stderr);
  assert.ok(c.stdout.includes('tests/skills/base-test.sh'), 'canon scope must list the same path');
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
  for (const needle of ['Code Review', REF, base, head, 'tests/skills/base-test.sh', 'tests/skills/lib/extra.test.mjs', REV_REL, VAL_REL]) {
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
  fs.appendFileSync(path.join(first.root, 'tests/skills/base-test.sh'), 'echo more\n');
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
  assert.match(c.stderr, /forced_full/);
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
    { event: 'check_verdict', ref: 'cheap-transitions-slice', payload: { role: 'validation', head: fx.base, status: 'fail' } },
    { event: 'check_verdict', ref: 'cheap-transitions-slice', payload: { role: 'code_review', head: fx.base, status: 'fail' } },
  ]);
  fs.appendFileSync(path.join(fx.root, 'tests/skills/base-test.sh'), 'echo more\n');
  for (const role of ['Validation', 'Code Review']) {
    const r = L.recheckMode({ root: fx.root, ref: 'cheap-transitions-slice', role, env: {} });
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
  const par = readRel('.aai/ORCHESTRATION_PARALLEL.prompt.md');
  assert.ok(par.includes('canon.mjs build'), 'ORCHESTRATION_PARALLEL.prompt.md lacks canon.mjs build');
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
  // A path under .aai/scripts/lib/ is a shared-library change: the selector escalates it
  // to a full run by design (suite-map.yaml full_run_triggers.shared_lib_globs), so the
  // map row must LIST the library even though the selector answers FULL_RUN for it.
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
  const mine = sa.items.filter((i) => i.ref_id === 'node-first-third-slice');
  const signed = mine.filter((i) => i.bucket === 'signed');
  assert.ok(signed.length >= 6, 'only ' + signed.length + ' signed record(s) for node-first-third-slice, want at least 6');
  const other = mine.filter((i) => i.bucket !== 'signed' && i.bucket !== 'measurement');
  assert.deepEqual(other.map((i) => i.record_key + ' is ' + i.bucket), []);
  const f = fu.items.find((i) => i.id === 'fu-amend-spec-node-first-third-slice');
  assert.ok(f, 'fu-amend-spec-node-first-third-slice is not listed');
  assert.equal(f.status, 'done');
});
