// recheck.test.mjs - node:test cases for the delta re-check mode
// (docs/specs/SPEC-0250-spec-cheap-transitions-slice.md, TEST-2701..2746;
// docs/specs/SPEC-DRAFT-spec-recheck-verdict-binding.md, TEST-2801..2837).
// Every case builds a temporary git repository under the OS temp directory; the
// shipping tree is only read. Each case name starts with its TEST id so
// test-aai-recheck.sh can run one id at a time (node --test --test-name-pattern).
//
// SELF-HOSTING: the delta mode is on by default (spec-recheck-verdict-binding D7) and
// AAI_RECHECK_MODE=full turns it off. The cases SET AAI_RECHECK_MODE=delta explicitly in every
// child process (cleanEnv) and pass an explicit env to recheckMode (DELTA_ENV), so the suite
// gives the same answer when the rider exports AAI_RECHECK_MODE=full. TEST-2738, TEST-2820 and
// the ENVS.default cases scrub the variable to test the default.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
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

// The harness is detected from the environment (lib/harness.mjs). MODEL_ROUTING.yaml
// is Mode B (per-harness), so an undetected harness resolves suggested_model to null by
// design. Locally CLAUDECODE says "claude"; a hosted runner exports nothing, and TEST-2708
// read null there (cheap-transitions-slice remediation round 6). Pin it in the child env.
const HARNESS_ENV = { AAI_HARNESS: 'claude' };

function cleanEnv(extra = {}) {
  const env = { ...process.env };
  delete env.AAI_ROLE;
  return { ...env, ...HARNESS_ENV, ...DELTA_ENV, ...extra };
}

function unsetEnv() {
  const env = { ...process.env };
  delete env.AAI_RECHECK_MODE;
  delete env.AAI_ROLE;
  return { ...env, ...HARNESS_ENV };
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
    wi = 'in_progress', second = false,
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
    status: ${wi}
    phase: ${phase}
    primary_path: docs/issues/CHANGE-0001-fixture.md
    spec_path: ${spec}
${second ? '  - ref_id: r2\n    status: in_progress\n    phase: implementation\n    primary_path: docs/issues/CHANGE-0002-other.md\n' : ''}implementation_strategy:
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
  writeKeep(root, stateYaml(o.state));
  git(root, ['add', '-A']);
  git(root, ['commit', '-q', '-m', 'base']);
  const base = git(root, ['rev-parse', 'HEAD']);
  // The judged round is bound through the real `state.mjs bind-check` (the check_binding
  // block of STATE), never by a hand-written EVENTS stamp: eligibility no longer reads those.
  if (o.verdicts !== false) bindRounds(root, o.verdictRoles ?? ['validation', 'code_review'], o.state);
  if (o.stamps) appendEvents(root, verdictEvents(base, o.verdictRoles));
  made.push(root);
  return { root, base };
}

// ---------------------------------------------------------------- binding helpers
function bindCheck(root, on, role, ref = REF, env = cleanEnv(), extra = []) {
  return spawnSync(process.execPath, [path.join(SCRIPTS, 'state.mjs'), 'bind-check', '--on', on, '--role', role, '--ref', ref,
    ...extra, '--state', stateOf(root)], { cwd: root, encoding: 'utf8', env });
}

function mustBind(root, on, role, ref = REF) {
  const r = bindCheck(root, on, role, ref);
  assert.equal(r.status, 0, `bind-check --on ${on} --role ${role}: ${r.stderr}${r.stdout}`);
  return r;
}

// Rewrites STATE with `text` and carries the check_binding block of the current file over.
function writeKeep(root, text) {
  const p = stateOf(root);
  const cur = fs.existsSync(p) ? fs.readFileSync(p, 'utf8').split('\n') : [];
  const blk = [];
  for (const key of ['check_binding:', 'check_sticky:']) {
    const i = cur.indexOf(key);
    if (i < 0) continue;
    let j = i + 1;
    while (j < cur.length && !/^[A-Za-z_]/.test(cur[j])) j += 1;
    blk.push(...cur.slice(i, j));
  }
  const next = text.split('\n');
  if (blk.length) next.splice(Math.max(0, next.findIndex((l) => /^updated_at_utc:/.test(l))), 0, ...blk);
  fs.writeFileSync(p, next.join('\n'));
}

// The block as plain strings, parsed independently of the library under test.
function blockOf(root) {
  const lines = fs.readFileSync(stateOf(root), 'utf8').split('\n');
  const i = lines.indexOf('check_binding:');
  if (i < 0) return null;
  const out = {};
  let key = null;
  for (let j = i + 1; j < lines.length && !/^[A-Za-z_]/.test(lines[j]); j += 1) {
    let m;
    if ((m = /^ {2}([a-z_]+):\s*(.*)$/.exec(lines[j]))) {
      key = m[1];
      const v = m[2].trim();
      out[key] = v === '' || v === '[]' ? [] : v;
    } else if ((m = /^ {4}- (.*)$/.exec(lines[j]))) out[key].push(m[1].trim());
  }
  return out;
}

function editBlock(root, fn) {
  const p = stateOf(root);
  const lines = fs.readFileSync(p, 'utf8').split('\n');
  const i = lines.indexOf('check_binding:');
  assert.ok(i >= 0, 'the fixture STATE holds no check_binding block');
  let j = i + 1;
  while (j < lines.length && !/^[A-Za-z_]/.test(lines[j])) j += 1;
  const next = fn(lines.slice(i, j));
  lines.splice(i, j - i, ...next);
  fs.writeFileSync(p, lines.join('\n'));
}

function dropBlock(root) { editBlock(root, () => []); }

const sha256Hex = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

// One judged round of one check role through the real CLI: a dispatch bind with no report in
// STATE, the checker's report written, STATE showing a fail verdict naming it, a verdict bind,
// then STATE restored to `finalState` with the block carried over.
function judgeRound(root, token, rel, text, so = {}, finalState = so) {
  const ref = so.ref || REF;
  const cleared = { ...so, evidence: [], reports: [], vstatus: 'not_run', rstatus: 'not_run' };
  writeKeep(root, stateYaml(cleared));
  mustBind(root, 'dispatch', token, ref);
  write(root, rel, text);
  writeKeep(root, token === 'validation'
    ? stateYaml({ ...so, vstatus: 'fail', evidence: [rel], reports: [] })
    : stateYaml({ ...so, vstatus: 'pass', rstatus: 'fail', evidence: [], reports: [rel] }));
  mustBind(root, 'verdict', token, ref);
  writeKeep(root, stateYaml(finalState));
}

// The default judged state of mkRepo: every role bound at the base commit, reports as committed.
function bindRounds(root, roles, so = {}) {
  const ref = (so && so.ref) || REF;
  const full = stateYaml(so);
  for (const token of roles) {
    writeKeep(root, stateYaml({ ...so, evidence: [], reports: [], vstatus: 'not_run', rstatus: 'not_run' }));
    mustBind(root, 'dispatch', token, ref);
    writeKeep(root, token === 'validation'
      ? stateYaml({ ...so, vstatus: 'fail', rstatus: 'not_run' })
      : stateYaml({ ...so, vstatus: 'pass', rstatus: 'fail' }));
    mustBind(root, 'verdict', token, ref);
  }
  writeKeep(root, full);
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
  bindRounds(sib.root, ['validation', 'code_review']);
  git(sib.root, ['checkout', '-q', 'main']);
  git(sib.root, ['cat-file', '-e', sideHead + '^{commit}']);
  assert.equal(blockOf(sib.root).validation_head, sideHead, 'the round is bound on the side branch');
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
  writeKeep(root, stateYaml({ vstatus: 'pass', rstatus: 'not_run' }));
  const b = runDispatch(root);
  assert.equal(b.out.rule, '13', JSON.stringify(b.out));
  assert.equal(b.out.role, 'Code Review');
  assert.equal(rc(b).mode, 'delta', JSON.stringify(b.out.recheck));
  const { fallback: fbB, ...restB } = rc(b);
  assert.deepEqual(restB, L.recheckMode({ root, ref: REF, role: 'Code Review', env: DELTA_ENV }));
  assert.equal(fbB.system_prompt, '.aai/SKILL_CODE_REVIEW.prompt.md');
  assert.equal(b.out.system_prompt, '.aai/RECHECK_DELTA.prompt.md');
  // a Remediation dispatch (rule 10) and a no_action verdict carry null
  writeKeep(root, stateYaml({ vstatus: 'fail' }));
  const c = runDispatch(root);
  assert.equal(c.out.role, 'Remediation');
  assert.ok('recheck' in c.out && c.out.recheck === null, 'Remediation recheck must be null');
  writeKeep(root, stateYaml({ human: true }));
  const d = runDispatch(root);
  assert.equal(d.out.verdict, 'no_action');
  assert.ok('recheck' in d.out && d.out.recheck === null, 'no_action recheck must be null');
  // forced full: the object is present, mode full, the stock prompt stays
  writeKeep(root, stateYaml());
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
  assert.equal(delta.out.harness, 'claude', 'the harness is pinned by the child env, not detected from the host');
  assert.ok(typeof delta.out.suggested_model === 'string' && delta.out.suggested_model !== impl, 'suggested_model must differ from the implementer: ' + delta.out.suggested_model);
});

// ------------------------------------------------------------------ TEST-2709
test('TEST-2709 the delta prompt_hash equals canon --print-hash --recheck delta', () => {
  const { root } = eligibleCanon('t2709');
  const pair = (stateOpts, role) => {
    writeKeep(root, stateYaml(stateOpts));
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
  fs.rmSync(path.join(root, 'docs/ai/EVENTS.jsonl'), { force: true });
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
  writeKeep(root, stateYaml({ vstatus: 'fail', runAt: '2026-07-02T00:00:00Z' }));
  const t2 = runDispatch(root, ['--confirm']);
  assert.equal(t2.out.role, 'Remediation');
  assert.equal(only('check_verdict').length, 1);
  assert.equal(only('check_verdict')[0].payload.status, 'fail');
  assert.equal(only('check_verdict')[0].payload.head, H);
  runDispatch(root, ['--confirm']);
  assert.equal(only('check_verdict').length, 1, 'a repeat after the stamp appends nothing');
  // a verdict with no check_dispatched is never stamped
  const lone = eligibleCanon('t2711-lone');
  fs.rmSync(path.join(lone.root, 'docs/ai/EVENTS.jsonl'), { force: true });
  writeKeep(lone.root, stateYaml({ vstatus: 'fail', runAt: '2026-07-02T00:00:00Z' }));
  runDispatch(lone.root, ['--confirm']);
  assert.equal(readEvents(lone.root).filter((e) => e.event === 'check_verdict').length, 0, 'no check_dispatched, no stamp');
  // a verdict that is not newer than the dispatched marker is not stamped
  const same = eligibleCanon('t2711-same');
  fs.rmSync(path.join(same.root, 'docs/ai/EVENTS.jsonl'), { force: true });
  runDispatch(same.root, ['--confirm']);
  writeKeep(same.root, stateYaml({ vstatus: 'fail', runAt: '2026-07-01T00:00:00Z' }));
  runDispatch(same.root, ['--confirm']);
  assert.equal(readEvents(same.root).filter((e) => e.event === 'check_verdict').length, 0, 'an unchanged run_at_utc is not a new verdict');
});

test('TEST-2711 code review: one more report plus a pass or fail status stamps a verdict', () => {
  const { root } = eligibleCanon('t2711-cr');
  fs.rmSync(path.join(root, 'docs/ai/EVENTS.jsonl'), { force: true });
  writeKeep(root, stateYaml({ vstatus: 'pass', rstatus: 'not_run' }));
  const t1 = runDispatch(root, ['--confirm']);
  assert.equal(t1.out.rule, '13');
  const d = readEvents(root).filter((e) => e.event === 'check_dispatched' && e.payload.role === 'code_review');
  assert.equal(d.length, 1);
  assert.equal(d[0].payload.seen, 'reports:1');
  writeKeep(root, stateYaml({ vstatus: 'pass', rstatus: 'fail', reports: [REV_REL, 'docs/ai/reviews/rev-2.md'] }));
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
  // the checker's own report exists before the verdict names it, and is committed with the first dispatch head
  const E2E_REPORT = VAL_N('e2e');
  write(root, E2E_REPORT, `# Validation e2e\n\n${MARK_FALSE}`);
  const H1 = commitAll(root, 'the checker report');
  const t1 = runDispatch(root, ['--confirm']);
  assert.equal(t1.out.rule, '11');
  assert.equal(rc(t1).mode, 'full');
  assert.ok(rc(t1).reasons.includes('first_round'));
  const sv = stateCli(root, ['set-validation', '--status', 'fail', '--ref', REF, '--evidence', E2E_REPORT, '--notes', 'round 1']);
  assert.equal(sv.status, 0, sv.stderr + sv.stdout);
  const t2 = runDispatch(root, ['--confirm']);
  assert.equal(t2.out.role, 'Remediation');
  const stamps = readEvents(root).filter((e) => e.event === 'check_verdict');
  assert.equal(stamps.length, 1, JSON.stringify(readEvents(root)));
  assert.equal(stamps[0].payload.head, H1);
  assert.equal(blockOf(root).validation_head, H1, 'the tick bound the verdict to the head of the first dispatch');
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
  const IF_REPORT = VAL_N('inflight');
  write(root, IF_REPORT, `# Validation in flight\n\n${MARK_FALSE}`);
  const sv = stateCli(root, ['set-validation', '--status', 'fail', '--ref', REF, '--evidence', IF_REPORT, '--notes', 'round 1']);
  assert.equal(sv.status, 0, sv.stderr + sv.stdout);
  runDispatch(root, ['--confirm']);
  const stamps = readEvents(root).filter((e) => e.event === 'check_verdict' && e.payload.role === 'validation');
  assert.equal(stamps.length, 1);
  assert.equal(stamps[0].payload.head, H1, 'the base is the head the checker was handed, not the re-tick head');
  assert.equal(blockOf(root).validation_head, H1, 'the binding takes the first pending head too');
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
  writeKeep(amb.root, stateYaml({ vstatus: 'fail', runAt: '2026-07-02T00:00:00Z' }));
  const plan = L.planCheckStamps({ root: amb.root, ref: REF, dispatchRole: null });
  assert.equal(plan.length, 1);
  assert.equal(plan[0].head, L.AMBIGUOUS_HEAD, 'divergent unjudged heads must stamp the ambiguous head');
  // positive control: two dispatches on one line of history stamp the earlier one
  const lin = mkRepo('t2724-linear', { verdicts: false });
  write(lin.root, 'tests/skills/test-aai-more.sh', 'x\n');
  git(lin.root, ['add', '-A']);
  git(lin.root, ['commit', '-q', '-m', 'later']);
  appendEvents(lin.root, [
    { event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: lin.base, seen } },
    { event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: git(lin.root, ['rev-parse', 'HEAD']), seen } },
  ]);
  writeKeep(lin.root, stateYaml({ vstatus: 'fail', runAt: '2026-07-02T00:00:00Z' }));
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
  const judgedFresh = (name, valText) => {
    const fx = mkRepo(name, { verdicts: false });
    const fin = { evidence: [NEW_VAL], reports: [NEW_REV] };
    judgeRound(fx.root, 'validation', NEW_VAL, valText, {}, fin);
    judgeRound(fx.root, 'code_review', NEW_REV, `# Review 2\n\n${MARK_FALSE}`, {}, fin);
    return fx;
  };
  const fresh = judgedFresh('t2729-fresh', `# Validation 2\n\n${MARK_FALSE}`);
  const c = L.recheckMode({ root: fresh.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(c.mode, 'delta', 'control: ' + reasonsOf(c));
  assert.deepEqual([...c.prior_reports].sort(), [NEW_REV, NEW_VAL].sort());
  const bad = judgedFresh('t2729-fresh-true', '# Validation 2\n\nsecurity_relevant: true\n');
  assert.ok(L.recheckMode({ root: bad.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('security_relevant:' + NEW_VAL), 'a new report that says true refuses');
});

// ------------------------------------------------------------------ TEST-2734
// NB-6: the judged round's own report is written after the base, so its marker is read live
// and an edit could flip it. The marker is recorded in the check_binding block when the
// verdict is bound, together with the sha256 of the report, and eligibility compares those.
const Q_VAL = 'docs/ai/reports/VALIDATION-2.md';
const Q_REV = 'docs/ai/reviews/rev-2.md';

// One judged round of one role through bind-check: the checker's report (marker text given)
// is written after the base and STATE shows the verdict that names it.
function judgedRound(name, tokenRole, markerText) {
  const fx = mkRepo(name, { verdicts: false });
  const rel = tokenRole === 'validation' ? Q_VAL : Q_REV;
  judgeRound(fx.root, tokenRole, rel, markerText, {}, tokenRole === 'validation' ? { evidence: [Q_VAL] } : { reports: [REV_REL, Q_REV] });
  return { ...fx, rel };
}

test('TEST-2734 the bound marker decides: a flipped committed review report (Q8) and a flipped gitignored validation report (Q9) stay full', async () => {
  const L = await lib();
  // Q8: a committed Code Review report that said true at verdict time is flipped to false inside the delta.
  const q8 = judgedRound('t2734-q8', 'code_review', '# Review 2\n\nsecurity_relevant: true\n');
  assert.equal(blockOf(q8.root).code_review_security, 'true', 'the block records the marker read at verdict time');
  commitAll(q8.root, 'judged round report');
  write(q8.root, Q_REV, '# Review 2\n\nsecurity_relevant: false\n');
  git(q8.root, ['commit', '-qam', 'flip the marker inside the delta']);
  const r8 = L.recheckMode({ root: q8.root, ref: REF, role: 'Code Review', env: DELTA_ENV });
  assert.equal(r8.mode, 'full', 'Q8: ' + reasonsOf(r8));
  assert.ok(r8.reasons.includes('security_relevant:binding') && r8.reasons.includes('binding_report_changed:' + Q_REV), reasonsOf(r8));
  // Q9: the Validation report is gitignored, so an in-place edit is not even visible in the delta.
  const q9 = judgedRound('t2734-q9', 'validation', '# Validation 2\n\nsecurity_relevant: true\n');
  assert.equal(blockOf(q9.root).validation_security, 'true');
  fs.appendFileSync(path.join(q9.root, '.git/info/exclude'), Q_VAL + '\n');
  write(q9.root, Q_VAL, '# Validation 2\n\nsecurity_relevant: false\n');
  assert.equal(git(q9.root, ['status', '--porcelain', '--', Q_VAL]), '', 'the flip is invisible to git');
  const r9 = L.recheckMode({ root: q9.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(r9.mode, 'full', 'Q9: ' + reasonsOf(r9));
  assert.ok(r9.reasons.includes('security_relevant:binding') && r9.reasons.includes('binding_report_changed:' + Q_VAL), reasonsOf(r9));
  // control: the same flow with a report that says false at verdict time stays delta, marker false
  for (const role of ['validation', 'code_review']) {
    const ok = judgedRound('t2734-ok-' + role, role, '# Round 2\n\nsecurity_relevant: false\n');
    assert.equal(blockOf(ok.root)[role + '_security'], 'false');
    fs.appendFileSync(path.join(ok.root, 'tests/skills/test-aai-base.sh'), 'echo fix\n');
    const o = L.recheckMode({ root: ok.root, ref: REF, role: role === 'validation' ? 'Validation' : 'Code Review', env: DELTA_ENV });
    assert.equal(o.mode, 'delta', 'control ' + role + ': ' + reasonsOf(o));
  }
});

test('TEST-2735 a binding without a marker is absent, and a marker bound true keeps every later round full', async () => {
  const L = await lib();
  // a report with no marker line: the block carries null, so the next round is full
  const none = judgedRound('t2735-none', 'validation', '# Validation 2\n\nno marker here\n');
  assert.equal(blockOf(none.root).validation_security, 'null');
  fs.appendFileSync(path.join(none.root, 'tests/skills/test-aai-base.sh'), 'echo fix\n');
  const a = L.recheckMode({ root: none.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.ok(a.reasons.includes('security_marker_absent:binding:validation'), reasonsOf(a));
  // sticky: an earlier round bound true, then a later round of the same role bound false: still full
  const st = mkRepo('t2735-sticky', { verdicts: false });
  judgeRound(st.root, 'validation', VAL_N('s1'), '# V1\n\nsecurity_relevant: true\n');
  judgeRound(st.root, 'validation', VAL_N('s2'), `# V2\n\n${MARK_FALSE}`, {}, { evidence: [VAL_N('s2')] });
  touchTest(st.root);
  const b = L.recheckMode({ root: st.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(b.mode, 'full');
  assert.ok(b.reasons.includes('security_relevant:binding'), reasonsOf(b));
  // a true marker bound for the OTHER role also keeps this role full
  const oth = mkRepo('t2735-other', { verdicts: false });
  judgeRound(oth.root, 'code_review', 'docs/ai/reviews/rev-o.md', '# C\n\nsecurity_relevant: true\n');
  judgeRound(oth.root, 'validation', VAL_N('o'), `# V\n\n${MARK_FALSE}`, {}, { evidence: [VAL_N('o')] });
  touchTest(oth.root);
  assert.ok(L.recheckMode({ root: oth.root, ref: REF, role: 'Validation', env: DELTA_ENV }).reasons.includes('security_relevant:binding'));
});

test('TEST-2736 the real tick records the marker in the stamp and append-event validates it', () => {
  const { root } = eligibleCanon('t2734-tick');
  fs.rmSync(path.join(root, 'docs/ai/EVENTS.jsonl'), { force: true });
  runDispatch(root, ['--confirm']);
  writeKeep(root, stateYaml({ vstatus: 'fail', runAt: '2026-07-02T00:00:00Z' }));
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
// Owner decision 2026-10-24 ("Zapnout po ověření"): once the verdict is bound to STATE (spec-recheck-verdict-binding)
// delta is the default. AAI_RECHECK_MODE trims and lower-cases: unset, empty, blank and delta enable the mode;
// full and every other value (a misspelling included) keep the round full.
test('TEST-2731 AAI_RECHECK_MODE: unset, empty, blank and delta enable the mode; full and any other value give recheck_disabled', async () => {
  const L = await lib();
  for (const v of ['full', 'FULL', ' Full ', 'full\n', '\tfull', 'off', '0', 'false', 'no', 'deltas', 'ful']) {
    assert.equal(L.deltaEnabled({ AAI_RECHECK_MODE: v }), false, JSON.stringify(v));
  }
  for (const v of ['delta', ' Delta ', 'DELTA', 'delta\n', undefined, '', '   ']) {
    assert.equal(L.deltaEnabled({ AAI_RECHECK_MODE: v }), true, JSON.stringify(v));
  }
  assert.equal(L.deltaEnabled({}), true);
  assert.equal(L.deltaEnabled(null), true);
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
test('TEST-2738 the default is on: an eligible tree with the variable unset gives delta, forced full gives recheck_disabled', async () => {
  const L = await lib();
  const { root } = mkRepo('t2738');
  touchTest(root);
  for (const env of [{}, { AAI_RECHECK_MODE: '' }, { AAI_RECHECK_MODE: '  ' }, DELTA_ENV]) {
    const r = L.recheckMode({ root, ref: REF, role: 'Validation', env });
    assert.equal(r.mode, 'delta', JSON.stringify(env) + ': ' + reasonsOf(r));
  }
  const f = L.recheckMode({ root, ref: REF, role: 'Validation', env: { AAI_RECHECK_MODE: 'full' } });
  assert.equal(f.mode, 'full');
  assert.deepEqual(f.reasons, ['recheck_disabled']);
  // the dispatch and canon read the process env: scrubbed, they answer delta
  const fx = eligibleCanon('t2738-dispatch');
  const d = spawnSync(process.execPath, [path.join(SCRIPTS, 'orchestration-dispatch.mjs'), '--state', stateOf(fx.root), '--root', fx.root],
    { cwd: PROJECT_ROOT, encoding: 'utf8', env: unsetEnv() });
  const out = JSON.parse(d.stdout);
  assert.equal(out.recheck.mode, 'delta', JSON.stringify(out.recheck));
  assert.equal(out.system_prompt, '.aai/RECHECK_DELTA.prompt.md');
  const c = spawnSync(process.execPath, [path.join(SCRIPTS, 'canon.mjs'), 'build', '--role', 'Validation', '--ref', REF, '--recheck', 'delta'],
    { cwd: fx.root, encoding: 'utf8', env: unsetEnv() });
  assert.equal(c.status, 0, c.stderr);
});

// ------------------------------------------------------------------ TEST-2739
// B9/F7: EVENTS.jsonl is a tracked non-production ledger, so a delta may edit it. The ledger
// comparison (ledger_rewritten) stays next to the binding: the ledger is append-only across
// the range or the round is full.
function mkTrackedLedgerRepo(name) {
  const fx = mkRepo(name, { verdicts: false, trackEvents: true });
  appendEvents(fx.root, [{ event: 'check_verdict', ref: REF, payload: { role: 'validation', head: fx.base, status: 'fail', security_relevant: true } }]);
  const stampCommit = commitAll(fx.root, 'stamp true');
  bindRounds(fx.root, ['validation', 'code_review']);
  return { ...fx, stampCommit };
}

function flipTrueStamp(root) {
  const p = path.join(root, 'docs/ai/EVENTS.jsonl');
  fs.writeFileSync(p, fs.readFileSync(p, 'utf8').replace('"security_relevant":true', '"security_relevant":false'));
}

test('TEST-2739 an in-place rewrite of an earlier stamp refuses delta (ledger_rewritten)', async () => {
  const L = await lib();
  // control: an append-only ledger with a clean false history is delta
  const ok = mkRepo('t2739-ctl', { verdicts: false, trackEvents: true });
  appendEvents(ok.root, verdictEvents(ok.base));
  commitAll(ok.root, 'stamps false');
  bindRounds(ok.root, ['validation', 'code_review']);
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
  // committed rewrite of a line that predates the bound base
  const done = mkTrackedLedgerRepo('t2739-committed');
  appendEvents(done.root, [{ event: 'check_verdict', ref: REF, payload: { role: 'code_review', head: done.stampCommit, status: 'fail', security_relevant: false } }]);
  git(done.root, ['commit', '-qam', 'second stamp']);
  flipTrueStamp(done.root);
  git(done.root, ['commit', '-qam', 'rewrite']);
  touchTest(done.root);
  const b = L.recheckMode({ root: done.root, ref: REF, role: 'Code Review', env: DELTA_ENV });
  assert.equal(b.mode, 'full');
  assert.ok(b.reasons.includes('ledger_rewritten'), reasonsOf(b));
  // a line committed after the base and then removed from the live file: the live file still begins
  // with its blob at the base but no longer with its blob at HEAD
  const head = mkTrackedLedgerRepo('t2739-headblob');
  const baseBytes = fs.readFileSync(path.join(head.root, 'docs/ai/EVENTS.jsonl'), 'utf8');
  appendEvents(head.root, [{ event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: head.stampCommit, seen: 'run_at:x' } }]);
  git(head.root, ['commit', '-qam', 'committed append']);
  fs.writeFileSync(path.join(head.root, 'docs/ai/EVENTS.jsonl'), baseBytes);
  touchTest(head.root);
  const h = L.recheckMode({ root: head.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.ok(h.reasons.includes('ledger_rewritten'), 'the live ledger lost a committed line: ' + reasonsOf(h));
  // truncation drops the stamp itself: the live file no longer begins with its blob at the base
  const cut = mkTrackedLedgerRepo('t2739-cut');
  fs.writeFileSync(path.join(cut.root, 'docs/ai/EVENTS.jsonl'), '');
  touchTest(cut.root);
  const t = L.recheckMode({ root: cut.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(t.mode, 'full');
  assert.ok(t.reasons.includes('ledger_rewritten'), reasonsOf(t));
});

// ------------------------------------------------------------------ TEST-2740
test('TEST-2740 a committed rewrite inside the delta range refuses delta even when the ends look appended', async () => {
  const L = await lib();
  const fx = mkRepo('t2740', { verdicts: false, trackEvents: true });
  appendEvents(fx.root, verdictEvents(fx.base));
  const stamped = commitAll(fx.root, 'stamps false');
  bindRounds(fx.root, ['validation', 'code_review']);
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
  commitAll(clean.root, 'stamps false');
  bindRounds(clean.root, ['validation', 'code_review']);
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
// Formerly the KNOWN RESIDUAL of docs/specs/SPEC-0250-spec-cheap-transitions-slice.md
// (fu-recheck-verdict-not-bound-to-check): with the verdict stamps of docs/ai/EVENTS.jsonl as
// the only record, an uncommitted flip of a true stamp and a flip folded in by --amend gave
// delta under the opt-in. spec-recheck-verdict-binding D1 to D5 replaces the stamps with the
// check_binding block of STATE, so both shapes give full; TEST-2807 holds the bound twins.
test('TEST-2742 an uncommitted true stamp flipped before its first commit, and an amended flip, give full', async () => {
  const L = await lib();
  const stamps = (head) => [
    { event: 'check_verdict', ref: REF, payload: { role: 'validation', head, status: 'fail', security_relevant: true } },
    { event: 'check_verdict', ref: REF, payload: { role: 'code_review', head, status: 'pass', security_relevant: false } },
  ];
  // stamps only, no binding: nothing is judged
  const fx = mkRepo('t2742', { verdicts: false, trackEvents: true });
  appendEvents(fx.root, stamps(fx.base));
  touchTest(fx.root);
  flipTrueStamp(fx.root);
  const after = L.recheckMode({ root: fx.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(after.mode, 'full', 'the flipped stamp gives no delta: ' + reasonsOf(after));
  assert.ok(after.reasons.includes('first_round'), reasonsOf(after));
  const dflt = L.recheckMode({ root: fx.root, ref: REF, role: 'Validation', env: {} });
  assert.equal(dflt.mode, 'full', 'the default env stays full');
  assert.ok(dflt.reasons.includes('first_round'));
  // the amend shape: a true stamp committed after the base, then flipped and folded in with --amend
  const am = mkRepo('t2742-amend', { verdicts: false, trackEvents: true });
  appendEvents(am.root, stamps(am.base));
  git(am.root, ['add', '-A']);
  git(am.root, ['commit', '-qm', 'true stamp']);
  touchTest(am.root);
  flipTrueStamp(am.root);
  git(am.root, ['commit', '-qa', '--amend', '--no-edit']);
  const amended = L.recheckMode({ root: am.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(amended.mode, 'full', reasonsOf(amended));
  assert.ok(amended.reasons.includes('first_round'));
  // the same two shapes on a fixture bound through bind-check, round 1 true then round 2 false
  const bound = trackedFx('t2742-bound');
  roundOne(bound);
  roundTwo(bound);
  touchTest(bound.root);
  flipTrueStamp(bound.root);
  assertFullBoth(L, bound.root, 'Validation', ['security_relevant:binding'], 'uncommitted flip, bound');
});

// ------------------------------------------------------------------ TEST-2743
test('TEST-2743 a merge commit in the delta range refuses delta (merge_in_range): merge -s ours drops a committed true stamp', async () => {
  const L = await lib();
  const mk = (name) => {
    const fx = mkRepo(name, { verdicts: false, trackEvents: true });
    appendEvents(fx.root, verdictEvents(fx.base));
    const stamped = commitAll(fx.root, 'stamps false');
    bindRounds(fx.root, ['validation', 'code_review']);
    return { ...fx, stamped };
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

// ------------------------------------------------------------------ TEST-2745
test('TEST-2745 the delta identity covers exactly the layers sent: LEARNED.md moves the full hash, never the delta hash', async () => {
  const { root } = eligibleCanon('t2745');
  const sha = (parts) => {
    const h = crypto.createHash('sha256');
    for (const [name, body] of parts) { h.update(`\n--- ${name} ---\n`); h.update(body); }
    return h.digest('hex');
  };
  const bytes = (rel) => fs.readFileSync(path.join(root, rel));
  const learnedRel = 'docs/knowledge/LEARNED.md';
  const sentHash = () => sha([['RECHECK_DELTA.prompt.md', bytes('.aai/RECHECK_DELTA.prompt.md')], ['SUBAGENT_CONTRACT.md', bytes('.aai/SUBAGENT_CONTRACT.md')]]);
  const measure = () => {
    const d = runDispatch(root);
    assert.equal(rc(d).mode, 'delta');
    const c = canonRun(root, ['build', '--role', 'Validation', '--print-hash', '--recheck', 'delta']);
    assert.equal(c.status, 0, c.stderr);
    const payload = canonRun(root, ['build', '--role', 'Validation', '--ref', REF, '--recheck', 'delta']);
    assert.equal(payload.status, 0, payload.stderr);
    return { d, canon: c.stdout.trim(), payload: payload.stdout };
  };
  const one = measure();
  // the identity is exactly sha256 over the two static layers the payload carries
  assert.equal(one.d.out.prompt_hash, sentHash(), 'dispatch delta prompt_hash must hash only the re-check prompt and the contract');
  assert.equal(one.canon, sentHash(), 'canon --print-hash --recheck delta must hash only the re-check prompt and the contract');
  assert.equal(one.d.out.inherits.learned, null, 'LEARNED was not sent: no provenance version is reported for it');
  assert.match(one.d.out.inherits.contract, /^[0-9a-f]{64}$/);
  assert.ok(!one.payload.includes('learned v1'), 'the delta payload does not carry LEARNED.md');
  // a LEARNED edit moves the FULL identity and leaves the delta identity alone. The edit goes
  // into a copy of the three files (a LEARNED change in the fixture tree itself would make the
  // tree ineligible for delta, which is not what is measured here).
  const PH = await import(pathToFileURL(path.join(SCRIPTS, 'lib', 'prompt-hash.mjs')).href);
  const copyRoot = path.join(tmpTop, 't2745-copy');
  for (const rel of ['.aai/RECHECK_DELTA.prompt.md', '.aai/SUBAGENT_CONTRACT.md', learnedRel]) {
    fs.mkdirSync(path.dirname(path.join(copyRoot, rel)), { recursive: true });
    fs.copyFileSync(path.join(root, rel), path.join(copyRoot, rel));
  }
  const rp = '.aai/RECHECK_DELTA.prompt.md';
  const before = { full: PH.computeEffectivePromptHash(rp, copyRoot), delta: PH.computeEffectivePromptHash(rp, copyRoot, { sendsLearned: false }) };
  assert.equal(before.delta, sentHash());
  fs.writeFileSync(path.join(copyRoot, learnedRel), 'learned v2, a different lesson\n');
  assert.notEqual(PH.computeEffectivePromptHash(rp, copyRoot), before.full, 'positive control: the full hash does cover LEARNED.md');
  assert.equal(PH.computeEffectivePromptHash(rp, copyRoot, { sendsLearned: false }), before.delta, 'a LEARNED change must not change the delta prompt_hash');
  // positive control: a change to a sent layer does move the delta identity
  fs.appendFileSync(path.join(copyRoot, '.aai/SUBAGENT_CONTRACT.md'), '\nnote\n');
  assert.notEqual(PH.computeEffectivePromptHash(rp, copyRoot, { sendsLearned: false }), before.delta);
});

// ------------------------------------------------------------------ TEST-2746
test('TEST-2746 needs_full_recheck is an escalation to the full role, never a human stop', () => {
  // (a) the prose that maps BLOCKED to human_input names the exception
  const orch = readRel('.aai/ORCHESTRATION.prompt.md');
  assert.ok(orch.split('\n').length - (orch.endsWith('\n') ? 1 : 0) <= 45, 'ORCHESTRATION.prompt.md is over 45 lines');
  assert.match(orch, /needs_full_recheck[\s\S]{0,200}no human stop/);
  assert.ok(orch.includes('AAI_RECHECK_MODE=full'));
  const proto = readRel('.aai/SUBAGENT_PROTOCOL.md');
  const blocked = proto.slice(proto.indexOf('- `BLOCKED` if any subagent returned `BLOCKED`'));
  assert.match(blocked.slice(0, 900), /EXCEPT a delta re-check[\s\S]*needs_full_recheck[\s\S]*Set no `human_input`[\s\S]*AAI_RECHECK_MODE=full/);
  const delta = readRel('.aai/RECHECK_DELTA.prompt.md');
  assert.ok(Buffer.byteLength(delta, 'utf8') <= 4096);
  assert.match(delta, /needs_full_recheck[^\n]*never a human stop/);
  // (b) the checker tells the merge step which BLOCKED is an escalation
  const dir = path.join(tmpTop, 't2746');
  fs.mkdirSync(dir, { recursive: true });
  const block = (status, blockers) => [
    '```yaml', 'subagent_result:', '  scope: s', '  role: Code Review', `  status: ${status}`,
    '  started_utc: 2026-10-24T10:00:00Z', '  ended_utc: 2026-10-24T10:00:10Z', '  duration_seconds: 10',
    '  evidence:', '    - command: git diff', '      exit_code: 0', '      output_snippet: x', '  files_changed: []',
    blockers.length ? '  blockers:' : '  blockers: []', ...blockers.map((b) => `    - ${b}`), '```', ''].join('\n');
  const check = (name, text, extra = ['--recheck-mode', 'delta']) => {
    const f = path.join(dir, name + '.md');
    fs.writeFileSync(f, text);
    return spawnSync(process.execPath, [path.join(SCRIPTS, 'check-role-output.mjs'), '--file', f, '--now', '2026-10-24T10:00:20Z', ...extra], { encoding: 'utf8', env: cleanEnv() });
  };
  const esc = check('esc', block('BLOCKED', ['needs_full_recheck']));
  assert.equal(esc.status, 0, esc.stdout);
  assert.match(esc.stdout, /^RECHECK-ESCALATION: needs_full_recheck /m);
  for (const [name, text] of [
    ['other', block('BLOCKED', ['spec is ambiguous'])],
    ['two', block('BLOCKED', ['needs_full_recheck', 'spec is ambiguous'])],
    ['pass', block('PASS', ['needs_full_recheck'])],
    ['none', block('BLOCKED', [])],
  ]) {
    const r = check(name, text);
    assert.equal(r.status, 0, name + ': ' + r.stdout);
    assert.ok(!r.stdout.includes('RECHECK-ESCALATION'), name + ' must stay a plain result: ' + r.stdout);
  }
  // (c) the re-dispatch the prompts name lands on the SAME role and ref in full mode
  const { root } = eligibleCanon('t2746');
  const first = runDispatch(root);
  assert.equal(rc(first).mode, 'delta');
  assert.equal(first.out.system_prompt, '.aai/RECHECK_DELTA.prompt.md');
  const again = runDispatch(root, [], { AAI_RECHECK_MODE: 'full' });
  assert.equal(again.status, 0, again.stderr);
  assert.equal(rc(again).mode, 'full');
  assert.equal(again.out.role, first.out.role);
  assert.equal(again.out.ref_id, first.out.ref_id);
  assert.equal(again.out.system_prompt, '.aai/VALIDATION.prompt.md', 'the full role prompt, not the delta prompt');
  assert.equal(again.out.human_input, undefined);
});

// =====================================================================================
// recheck-verdict-binding (docs/specs/SPEC-DRAFT-spec-recheck-verdict-binding.md, TEST-2801..2832)
// The judged round is bound in STATE by `state.mjs bind-check`; every fixture below builds it
// through that real CLI. Eligibility compares the binding and never reads a check_ stamp.
// =====================================================================================
const ZERO40 = '0'.repeat(40);
const VAL_N = (n) => `docs/ai/reports/VALIDATION-${n}.md`;
const topLevel = (root) => fs.realpathSync(git(root, ['rev-parse', '--show-toplevel']));
const commitAll = (root, msg) => { git(root, ['add', '-A']); git(root, ['commit', '-q', '-m', msg]); return git(root, ['rev-parse', 'HEAD']); };
const stateText = (root) => fs.readFileSync(stateOf(root), 'utf8');
const listOf = (b, k) => (b && b[k] !== undefined ? b[k] : []);
const ENVS = { delta: DELTA_ENV, default: {} };

function assertFullBoth(L, root, role, wants, label) {
  for (const [name, env] of Object.entries(ENVS)) {
    const r = L.recheckMode({ root, ref: REF, role, env });
    assert.equal(r.mode, 'full', `${label} (${name} env): ${reasonsOf(r)}`);
    for (const w of wants) assert.ok(r.reasons.includes(w), `${label} (${name} env) lacks ${w}: ${reasonsOf(r)}`);
  }
}

// A verdict-only step: the dispatch bind already ran; the checker's report is written, STATE
// shows the verdict, the verdict bind runs, STATE goes back to `finalState`.
function verdictOnly(root, token, rel, text, so = {}, finalState = so) {
  const ref = so.ref || REF;
  write(root, rel, text);
  writeKeep(root, token === 'validation'
    ? stateYaml({ ...so, vstatus: 'fail', evidence: [rel], reports: [] })
    : stateYaml({ ...so, vstatus: 'pass', rstatus: 'fail', evidence: [], reports: [rel] }));
  mustBind(root, 'verdict', token, ref);
  writeKeep(root, stateYaml(finalState));
}

// ------------------------------------------------------------------ TEST-2801
test('TEST-2801 bind-check --on dispatch records ref, checkout, the pending head and the report set', () => {
  const { root, base } = mkRepo('t2801', { verdicts: false });
  assert.equal(blockOf(root), null, 'positive control: no block before the first bind');
  mustBind(root, 'dispatch', 'validation');
  const a = blockOf(root);
  assert.equal(a.ref_id, REF);
  assert.equal(a.checkout, topLevel(root));
  assert.deepEqual(a.validation_pending_heads, [base]);
  assert.deepEqual(a.validation_pending_reports, [VAL_REL]);
  // a repeat with the same head and report set writes nothing
  const snap = stateText(root);
  mustBind(root, 'dispatch', 'validation');
  assert.equal(stateText(root), snap, 'a repeat dispatch bind must leave STATE byte-identical');
  // a newer head appends; the first report set is kept although STATE names another path now
  write(root, 'tests/skills/test-aai-more.sh', 'x\n');
  const h2 = commitAll(root, 'more');
  writeKeep(root, stateYaml({ evidence: [VAL_REL, VAL_N(9)] }));
  mustBind(root, 'dispatch', 'validation');
  const b = blockOf(root);
  assert.deepEqual(b.validation_pending_heads, [base, h2]);
  assert.deepEqual(b.validation_pending_reports, [VAL_REL]);
  // the other role keeps its own lists
  mustBind(root, 'dispatch', 'code_review');
  const c = blockOf(root);
  assert.deepEqual(c.code_review_pending_heads, [h2]);
  assert.deepEqual(c.code_review_pending_reports, [REV_REL]);
  assert.deepEqual(c.validation_pending_heads, [base, h2]);
  // a dispatch for another focus ref replaces the whole block
  writeKeep(root, stateYaml({ ref: 'r2' }));
  mustBind(root, 'dispatch', 'validation', 'r2');
  const d = blockOf(root);
  assert.equal(d.ref_id, 'r2');
  assert.deepEqual(d.validation_pending_heads, [h2]);
  assert.deepEqual(listOf(d, 'code_review_pending_heads'), [], 'the old ref lists are gone');
  // a ref that is not current_focus.ref_id exits 2 and writes nothing
  const before = stateText(root);
  const bad = bindCheck(root, 'dispatch', 'validation', 'not-the-focus');
  assert.equal(bad.status, 2, bad.stderr);
  assert.equal(stateText(root), before);
  // no head, report, digest or marker flag exists
  for (const flag of ['--head', '--report', '--digest', '--marker']) {
    const r = bindCheck(root, 'dispatch', 'validation', 'r2', cleanEnv(), [flag, 'x']);
    assert.equal(r.status, 2, flag + ': ' + r.stderr);
    assert.equal(stateText(root), before, flag + ' must write nothing');
  }
});

// ------------------------------------------------------------------ TEST-2803
test('TEST-2803 bind-check --on verdict writes head, status, reports, digests and the marker, and clears the pending fields', () => {
  const { root, base } = mkRepo('t2803', { verdicts: false });
  const R = (n) => VAL_N('v' + n);
  judgeRound(root, 'validation', R(1), `# V1\n\n${MARK_FALSE}`);
  const a = blockOf(root);
  assert.equal(a.validation_head, base);
  assert.equal(a.validation_status, 'fail');
  assert.deepEqual(a.validation_reports, [R(1)]);
  assert.deepEqual(a.validation_digests, [sha256Hex(fs.readFileSync(path.join(root, R(1))))]);
  assert.equal(a.validation_security, 'false');
  assert.equal(a.security_sticky, 'false');
  assert.deepEqual(listOf(a, 'validation_pending_heads'), []);
  assert.deepEqual(listOf(a, 'validation_pending_reports'), []);
  assert.match(a.validation_bound_at_utc, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z$/);
  // a true marker sets the role marker and the sticky flag
  judgeRound(root, 'validation', R(2), '# V2\n\nsecurity_relevant: true\n');
  const b = blockOf(root);
  assert.equal(b.validation_security, 'true');
  assert.equal(b.security_sticky, 'true');
  assert.deepEqual(b.validation_reports, [R(2)]);
  // a later bound round with false keeps the sticky flag
  judgeRound(root, 'validation', R(3), `# V3\n\n${MARK_FALSE}`);
  const c = blockOf(root);
  assert.equal(c.validation_security, 'false');
  assert.equal(c.security_sticky, 'true', 'never lowered while the block names this ref');
  // a report without the marker line gives null
  judgeRound(root, 'validation', R(4), '# V4\n\nno marker\n');
  assert.equal(blockOf(root).validation_security, 'null');
  // the same for code_review with report_paths
  const cr = mkRepo('t2803-cr', { verdicts: false });
  judgeRound(cr.root, 'code_review', 'docs/ai/reviews/c1.md', `# C1\n\n${MARK_FALSE}`);
  const d = blockOf(cr.root);
  assert.equal(d.code_review_head, cr.base);
  assert.equal(d.code_review_status, 'fail');
  assert.deepEqual(d.code_review_reports, ['docs/ai/reviews/c1.md']);
  assert.deepEqual(d.code_review_digests, [sha256Hex(fs.readFileSync(path.join(cr.root, 'docs/ai/reviews/c1.md')))]);
  assert.equal(d.code_review_security, 'false');
  judgeRound(cr.root, 'code_review', 'docs/ai/reviews/c2.md', '# C2\n\nsecurity_relevant: true\n');
  assert.equal(blockOf(cr.root).security_sticky, 'true');
  // a true marker of the other role is sticky for both
  assert.equal(blockOf(cr.root).code_review_security, 'true');
});

// ------------------------------------------------------------------ TEST-2804
test('TEST-2804 bind-check --on verdict refuses without a dispatched check, a verdict, a new report', () => {
  const same = (root, label, fn) => {
    const before = stateText(root);
    fn();
    assert.equal(stateText(root), before, label + ' must write nothing');
  };
  // no pending head
  const np = mkRepo('t2804-nopending', { verdicts: false });
  write(np.root, VAL_N('np'), `# V\n\n${MARK_FALSE}`);
  writeKeep(np.root, stateYaml({ vstatus: 'fail', evidence: [VAL_N('np')] }));
  same(np.root, 'no pending head', () => mustBind(np.root, 'verdict', 'validation'));
  assert.equal(blockOf(np.root), null);
  // a not_run verdict
  const nr = mkRepo('t2804-notrun', { verdicts: false });
  writeKeep(nr.root, stateYaml({ evidence: [], reports: [] }));
  mustBind(nr.root, 'dispatch', 'validation');
  write(nr.root, VAL_N('nr'), `# V\n\n${MARK_FALSE}`);
  writeKeep(nr.root, stateYaml({ vstatus: 'not_run', evidence: [VAL_N('nr')] }));
  same(nr.root, 'a not_run verdict', () => mustBind(nr.root, 'verdict', 'validation'));
  // a verdict of another ref
  writeKeep(nr.root, stateYaml({ vstatus: 'fail', vref: 'other', evidence: [VAL_N('nr')] }));
  same(nr.root, 'a verdict naming another ref', () => mustBind(nr.root, 'verdict', 'validation'));
  assert.equal(blockOf(nr.root).validation_status, undefined);
  // a re-record naming only the report set recorded at dispatch (probe D2)
  const rr = mkRepo('t2804-rerecord', { verdicts: false });
  mustBind(rr.root, 'dispatch', 'validation');
  writeKeep(rr.root, stateYaml({ vstatus: 'fail', runAt: '2026-07-05T00:00:00Z' }));
  same(rr.root, 're-record of the old report', () => mustBind(rr.root, 'verdict', 'validation'));
  assert.equal(blockOf(rr.root).validation_status, undefined);
  assert.deepEqual(blockOf(rr.root).validation_pending_heads, [rr.base], 'the pending head stays');
  // a repeat after the bind
  const rp = mkRepo('t2804-repeat', { verdicts: false });
  judgeRound(rp.root, 'validation', VAL_N('rp'), `# V\n\n${MARK_FALSE}`);
  same(rp.root, 'a repeat after the bind', () => mustBind(rp.root, 'verdict', 'validation'));
  // two pending heads on one line of history bind the first
  const lin = mkRepo('t2804-linear', { verdicts: false });
  writeKeep(lin.root, stateYaml({ evidence: [], reports: [] }));
  mustBind(lin.root, 'dispatch', 'validation');
  write(lin.root, 'tests/skills/test-aai-more.sh', 'x\n');
  commitAll(lin.root, 'later');
  mustBind(lin.root, 'dispatch', 'validation');
  assert.equal(listOf(blockOf(lin.root), 'validation_pending_heads').length, 2);
  verdictOnly(lin.root, 'validation', VAL_N('lin'), `# V\n\n${MARK_FALSE}`);
  assert.equal(blockOf(lin.root).validation_head, lin.base);
  // a pending head on a sibling branch binds forty zeros
  const sib = mkRepo('t2804-sibling', { verdicts: false });
  git(sib.root, ['checkout', '-q', '-b', 'side']);
  write(sib.root, 'tests/skills/side.sh', 'x\n');
  commitAll(sib.root, 'side');
  writeKeep(sib.root, stateYaml({ evidence: [], reports: [] }));
  mustBind(sib.root, 'dispatch', 'validation');
  git(sib.root, ['checkout', '-q', 'main']);
  mustBind(sib.root, 'dispatch', 'validation');
  verdictOnly(sib.root, 'validation', VAL_N('sib'), `# V\n\n${MARK_FALSE}`);
  assert.equal(blockOf(sib.root).validation_head, ZERO40);
});

// ------------------------------------------------------------------ TEST-2805
test('TEST-2805 eligibility reads the binding: each failing comparison gives full with exactly its reason', async () => {
  const L = await lib();
  const fresh = (name, o = {}) => { const f = mkRepo(name, o); touchTest(f.root); return f; };
  const decide = (root, role = 'Validation') => L.recheckMode({ root, ref: REF, role, env: DELTA_ENV });
  const ok = fresh('t2805-ok');
  const c = decide(ok.root);
  assert.equal(c.mode, 'delta', 'positive control: ' + reasonsOf(c));
  assert.equal(c.base, ok.base, 'the base is the bound role head');
  assert.equal(decide(ok.root, 'Code Review').mode, 'delta');
  const one = (name, mutate, want, o = {}) => {
    const f = fresh(name, o);
    mutate(f);
    const r = decide(f.root);
    assert.equal(r.mode, 'full', name + ': ' + reasonsOf(r));
    assert.ok(r.reasons.includes(want), name + ' lacks ' + want + ': ' + reasonsOf(r));
    return r;
  };
  one('t2805-noblock', (f) => dropBlock(f.root), 'first_round');
  one('t2805-otherref', (f) => editBlock(f.root, (b) => b.map((l) => l.replace(/^ {2}ref_id: .*/, '  ref_id: other'))), 'first_round');
  one('t2805-dupkey', (f) => fs.appendFileSync(stateOf(f.root), 'check_binding:\n  ref_id: r1\n'), 'binding_ambiguous');
  one('t2805-digests', (f) => editBlock(f.root, (b) => {
    const i = b.findIndex((l) => /^ {2}validation_digests:/.test(l));
    assert.ok(i >= 0, 'fixture block lacks validation_digests');
    let j = i + 1;
    while (j < b.length && /^ {4}- /.test(b[j])) j += 1;
    return [...b.slice(0, i), '  validation_digests: []', ...b.slice(j)];
  }), 'binding_ambiguous');
  one('t2805-badhead', (f) => editBlock(f.root, (b) => b.map((l) => l.replace(/^ {2}validation_head: .*/, '  validation_head: nothex'))), 'binding_ambiguous');
  // a block written by a second checkout of the repository
  one('t2805-checkout', (f) => {
    const wt = path.join(tmpTop, 't2805-checkout-wt');
    git(f.root, ['worktree', 'add', '-q', '--detach', wt]);
    bindRounds(wt, ['validation', 'code_review']);
    fs.copyFileSync(stateOf(wt), stateOf(f.root));
  }, 'binding_other_checkout');
  // a newer dispatch without a verdict
  one('t2805-pending', (f) => {
    write(f.root, 'tests/skills/test-aai-later.sh', 'x\n');
    commitAll(f.root, 'later');
    mustBind(f.root, 'dispatch', 'validation');
  }, 'binding_pending:validation');
  one('t2805-zero', (f) => editBlock(f.root, (b) => b.map((l) => l.replace(/^ {2}validation_head: .*/, `  validation_head: ${ZERO40}`))), 'base_not_ancestor');
  one('t2805-edited', (f) => fs.appendFileSync(path.join(f.root, VAL_REL), 'late edit\n'), 'binding_report_changed:' + VAL_REL);
  one('t2805-deleted', (f) => fs.rmSync(path.join(f.root, VAL_REL)), 'binding_report_changed:' + VAL_REL);
  one('t2805-otherrole-true', () => {}, 'security_relevant:binding', { revText: '# Review\n\nsecurity_relevant: true\n' });
  one('t2805-null', () => {}, 'security_marker_absent:binding:validation', { valText: '# Validation\n\nno marker\n' });
  // the other role's null marker is not this role's binding marker (the prior-report read still names its path)
  const o = fresh('t2805-other-null', { revText: '# Review\n\nno marker\n' });
  const ro = decide(o.root);
  assert.ok(!ro.reasons.some((x) => x.includes(':binding')), 'no binding reason for a null marker of the other role: ' + reasonsOf(ro));
  assert.ok(ro.reasons.includes('security_marker_absent:' + REV_REL), reasonsOf(ro));
});

// ------------------------------------------------------------------ TEST-2806
test('TEST-2806 no check_ line of EVENTS.jsonl is read: forged stamps change nothing', async () => {
  const L = await lib();
  const { root, base } = mkRepo('t2806');
  touchTest(root);
  const before = L.recheckMode({ root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(before.mode, 'delta', reasonsOf(before));
  appendEvents(root, [
    { event: 'check_verdict', ref: REF, payload: { role: 'validation', head: base, status: 'fail', security_relevant: true } },
    { event: 'check_verdict', ref: REF, payload: { role: 'validation', head: ZERO40, status: 'fail', security_relevant: false } },
    { event: 'check_verdict', ref: REF, payload: { role: 'code_review', head: base, status: 'fail', security_relevant: true } },
    { event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: base, seen: 'run_at:x' } },
  ]);
  assert.ok(fs.readFileSync(path.join(root, 'docs/ai/EVENTS.jsonl'), 'utf8').includes('"security_relevant":true'), 'the forged true stamp is on the ledger');
  const after = L.recheckMode({ root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.deepEqual(after, before);
  const cr = L.recheckMode({ root, ref: REF, role: 'Code Review', env: DELTA_ENV });
  assert.equal(cr.mode, 'delta');
  // forged lines with no binding give first_round and no stamp reason
  const nb = mkRepo('t2806-nobinding', { verdicts: false });
  appendEvents(nb.root, verdictEvents(nb.base));
  touchTest(nb.root);
  const r = L.recheckMode({ root: nb.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(r.mode, 'full');
  assert.ok(r.reasons.includes('first_round'), reasonsOf(r));
  assert.deepEqual(r.reasons.filter((x) => x.includes(':stamp:')), []);
});

// ------------------------------------------------------------------ TEST-2807..2813 (D5)
// The fixture of every shape has two judged Validation rounds bound through bind-check, round 1
// with marker true and round 2 with marker false, so security_sticky is true, and the matching
// stamps in the tracked ledger. Each shape then changes the ledger or the history; none may give delta.
const T_R1 = VAL_N('t1');
const T_R2 = VAL_N('t2');
const stampOf = (head, sec) => ({ event: 'check_verdict', ref: REF, payload: { role: 'validation', head, status: 'fail', security_relevant: sec } });
const ledgerPath = (root) => path.join(root, 'docs/ai/EVENTS.jsonl');
const ledgerHasTrue = (root) => fs.existsSync(ledgerPath(root)) && fs.readFileSync(ledgerPath(root), 'utf8').includes('"security_relevant":true');
function roundOne(fx) {
  judgeRound(fx.root, 'validation', T_R1, '# Round 1\n\nsecurity_relevant: true\n');
  appendEvents(fx.root, [stampOf(git(fx.root, ['rev-parse', 'HEAD']), true)]);
  assert.equal(blockOf(fx.root).security_sticky, 'true');
}
function roundTwo(fx) {
  judgeRound(fx.root, 'validation', T_R2, `# Round 2\n\n${MARK_FALSE}`);
  appendEvents(fx.root, [stampOf(git(fx.root, ['rev-parse', 'HEAD']), false)]);
  const b = blockOf(fx.root);
  assert.equal(b.validation_security, 'false');
  assert.equal(b.security_sticky, 'true');
}
const trackedFx = (name) => mkRepo(name, { verdicts: false, trackEvents: true });

test('TEST-2807 D5 shapes 1 and 2: an uncommitted flip of the true stamp and a flip folded in by --amend give full', async () => {
  const L = await lib();
  const a = trackedFx('t2807-flip');
  roundOne(a);
  roundTwo(a);
  touchTest(a.root);
  assert.ok(ledgerHasTrue(a.root), 'the true stamp is on the ledger before the flip');
  assertFullBoth(L, a.root, 'Validation', ['security_relevant:binding'], 'control before the flip');
  flipTrueStamp(a.root);
  assert.ok(!ledgerHasTrue(a.root), 'the true stamp is gone after the flip');
  assertFullBoth(L, a.root, 'Validation', ['security_relevant:binding'], 'shape 1');
  const b = trackedFx('t2807-amend');
  roundOne(b);
  roundTwo(b);
  touchTest(b.root);
  commitAll(b.root, 'stamps');
  flipTrueStamp(b.root);
  git(b.root, ['commit', '-qa', '--amend', '--no-edit']);
  assert.ok(!ledgerHasTrue(b.root));
  assertFullBoth(L, b.root, 'Validation', ['security_relevant:binding'], 'shape 2');
});

test('TEST-2808 D5 shapes 3 and 4: a rebase and a squash merge resolved to ours that drop the stamp commit give full', async () => {
  const L = await lib();
  const a = trackedFx('t2808-rebase');
  roundOne(a);
  roundTwo(a);
  git(a.root, ['add', 'docs/ai/EVENTS.jsonl']);
  git(a.root, ['commit', '-q', '-m', 'stamps']);
  const stampsCommit = git(a.root, ['rev-parse', 'HEAD']);
  fs.appendFileSync(path.join(a.root, 'tests/skills/test-aai-base.sh'), 'echo fix\n');
  git(a.root, ['commit', '-qam', 'test fix']);
  assert.ok(ledgerHasTrue(a.root));
  git(a.root, ['rebase', '-q', '--onto', a.base, stampsCommit]);
  assert.ok(!ledgerHasTrue(a.root), 'the rebase dropped the stamp commit');
  touchTest(a.root);
  assertFullBoth(L, a.root, 'Validation', ['security_relevant:binding'], 'shape 3');
  const b = trackedFx('t2808-squash');
  roundOne(b);
  roundTwo(b);
  git(b.root, ['checkout', '-q', '-b', 'side']);
  git(b.root, ['add', 'docs/ai/EVENTS.jsonl']);
  git(b.root, ['commit', '-q', '-m', 'side stamps']);
  git(b.root, ['checkout', '-q', 'main']);
  appendEvents(b.root, [{ event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: b.base, seen: 'run_at:x' } }]);
  git(b.root, ['add', 'docs/ai/EVENTS.jsonl']);
  git(b.root, ['commit', '-q', '-m', 'main append']);
  spawnSync('git', ['merge', '--squash', 'side'], { cwd: b.root, encoding: 'utf8' });
  git(b.root, ['checkout', '--ours', 'docs/ai/EVENTS.jsonl']);
  git(b.root, ['add', 'docs/ai/EVENTS.jsonl']);
  git(b.root, ['commit', '-q', '--allow-empty', '-m', 'squash resolved to ours']);
  assert.ok(!ledgerHasTrue(b.root), 'the squash dropped the stamp');
  touchTest(b.root);
  assertFullBoth(L, b.root, 'Validation', ['security_relevant:binding'], 'shape 4');
});

test('TEST-2809 D5 shape 5: a stamp appended true then flipped in commits before the bound base gives full', async () => {
  const L = await lib();
  const fx = trackedFx('t2809');
  roundOne(fx);
  git(fx.root, ['add', 'docs/ai/EVENTS.jsonl']);
  git(fx.root, ['commit', '-q', '-m', 'C1 true stamp']);
  assert.ok(ledgerHasTrue(fx.root));
  flipTrueStamp(fx.root);
  appendEvents(fx.root, [{ event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: fx.base, seen: 'run_at:x' } }]);
  git(fx.root, ['commit', '-qam', 'C2 rewrite and append']);
  assert.ok(!ledgerHasTrue(fx.root));
  roundTwo(fx);
  touchTest(fx.root);
  assert.equal(blockOf(fx.root).validation_head, git(fx.root, ['rev-parse', 'HEAD']), 'the rewrite is before the bound base');
  assertFullBoth(L, fx.root, 'Validation', ['security_relevant:binding'], 'shape 5');
});

test('TEST-2810 D5 shape 6: git replace in every form gives full', async () => {
  const L = await lib();
  const hidden = '.aai/scripts/hidden.mjs';
  const mk = (name, withProd) => {
    const fx = mkRepo(name);
    if (withProd) { write(fx.root, hidden, 'export const hidden = 1;\n'); commitAll(fx.root, 'production change'); }
    touchTest(fx.root);
    return fx;
  };
  const decide = (root, env = DELTA_ENV) => L.recheckMode({ root, ref: REF, role: 'Validation', env });
  // controls: the production change is named without any replace, and the fixture without it is delta
  const ctl = mk('t2810-control', true);
  assert.ok(decide(ctl.root).reasons.includes('production_path:' + hidden), 'control: ' + reasonsOf(decide(ctl.root)));
  assert.equal(decide(mk('t2810-clean', false).root).mode, 'delta', 'the same fixture without the production change');
  // an object replace of the base commit by a commit whose tree already holds the change
  const a = mk('t2810-object', true);
  const tree = git(a.root, ['rev-parse', 'HEAD^{tree}']);
  const fake = git(a.root, ['commit-tree', tree, '-m', 'fake base']);
  git(a.root, ['replace', a.base, fake]);
  assertFullBoth(L, a.root, 'Validation', ['replace_refs_present'], 'object replace');
  // replace --graft
  const g = mk('t2810-graft', true);
  git(g.root, ['replace', '--graft', 'HEAD']);
  assertFullBoth(L, g.root, 'Validation', ['replace_refs_present'], 'replace --graft');
  // the same under a different GIT_REPLACE_REF_BASE
  const o = mk('t2810-refbase', true);
  const tree2 = git(o.root, ['rev-parse', 'HEAD^{tree}']);
  const fake2 = git(o.root, ['commit-tree', tree2, '-m', 'fake base']);
  execFileSync('git', ['replace', o.base, fake2], { cwd: o.root, env: { ...process.env, GIT_REPLACE_REF_BASE: 'refs/other/' } });
  assert.equal(git(o.root, ['for-each-ref', 'refs/other/']).split('\n').filter(Boolean).length, 1, 'the replace ref lives under refs/other/');
  const saved = process.env.GIT_REPLACE_REF_BASE;
  process.env.GIT_REPLACE_REF_BASE = 'refs/other/';
  try {
    assertFullBoth(L, o.root, 'Validation', ['production_path:' + hidden], 'GIT_REPLACE_REF_BASE');
  } finally {
    if (saved === undefined) delete process.env.GIT_REPLACE_REF_BASE; else process.env.GIT_REPLACE_REF_BASE = saved;
  }
  // an info/grafts file
  const f = mk('t2810-grafts', true);
  const gitDir = path.resolve(f.root, git(f.root, ['rev-parse', '--git-common-dir']));
  fs.mkdirSync(path.join(gitDir, 'info'), { recursive: true });
  fs.writeFileSync(path.join(gitDir, 'info', 'grafts'), `${git(f.root, ['rev-parse', 'HEAD'])} ${f.base}\n`);
  assertFullBoth(L, f.root, 'Validation', ['replace_refs_present'], 'info/grafts');
});

test('TEST-2811 D5 shapes 7 and 8: a hand-appended check_verdict gives production_path from the bound head, or first_round', async () => {
  const L = await lib();
  const fx = mkRepo('t2811');
  write(fx.root, '.aai/scripts/forged.mjs', 'export const forged = 1;\n');
  const prodHead = commitAll(fx.root, 'production commit');
  appendEvents(fx.root, [{ event: 'check_verdict', ref: REF, payload: { role: 'validation', head: prodHead, status: 'fail', security_relevant: false } }]);
  touchTest(fx.root);
  assertFullBoth(L, fx.root, 'Validation', ['production_path:.aai/scripts/forged.mjs'], 'shape 7');
  assert.equal(L.recheckMode({ root: fx.root, ref: REF, role: 'Validation', env: DELTA_ENV }).base, fx.base, 'the base stays the bound head');
  const nb = mkRepo('t2811-nobinding', { verdicts: false });
  appendEvents(nb.root, verdictEvents(nb.base));
  touchTest(nb.root);
  assertFullBoth(L, nb.root, 'Validation', ['first_round'], 'shape 8');
});

test('TEST-2812 D5 shapes 9 and 10: merge -s ours dropping a true stamp and a re-recorded old report give full', async () => {
  const L = await lib();
  const fx = trackedFx('t2812-merge');
  appendEvents(fx.root, [stampOf(fx.base, false)]);
  const stamped = commitAll(fx.root, 'stamps false');
  roundOne(fx);
  roundTwo(fx);
  git(fx.root, ['checkout', '-q', '-b', 'side']);
  git(fx.root, ['add', 'docs/ai/EVENTS.jsonl']);
  git(fx.root, ['commit', '-q', '-m', 'side: true stamp']);
  assert.ok(ledgerHasTrue(fx.root));
  git(fx.root, ['checkout', '-q', 'main']);
  appendEvents(fx.root, [{ event: 'check_dispatched', ref: REF, payload: { role: 'validation', head: stamped, seen: 'run_at:x' } }]);
  git(fx.root, ['add', 'docs/ai/EVENTS.jsonl']);
  git(fx.root, ['commit', '-q', '-m', 'main: append']);
  git(fx.root, ['merge', '-q', '-s', 'ours', '-m', 'drop side', 'side']);
  assert.ok(!ledgerHasTrue(fx.root), 'the true stamp is gone from the live ledger');
  touchTest(fx.root);
  assertFullBoth(L, fx.root, 'Validation', ['security_relevant:binding', 'merge_in_range'], 'shape 9');
  // shape 10: a crashed check, then set-validation re-records the old report
  const cr = mkRepo('t2812-crash');
  write(cr.root, 'tests/skills/test-aai-later.sh', 'x\n');
  commitAll(cr.root, 'remediation');
  mustBind(cr.root, 'dispatch', 'validation');
  writeKeep(cr.root, stateYaml({ vstatus: 'fail', runAt: '2026-07-05T00:00:00Z' }));
  mustBind(cr.root, 'verdict', 'validation');
  touchTest(cr.root);
  assert.ok(listOf(blockOf(cr.root), 'validation_pending_heads').length === 1, 'the crashed dispatch stays pending');
  assertFullBoth(L, cr.root, 'Validation', ['binding_pending:validation'], 'shape 10');
});

test('TEST-2813 D5 shape 11: a bound report flipped after the bind, committed or gitignored in place, gives full', async () => {
  const L = await lib();
  const q8 = mkRepo('t2813-q8', { verdicts: false });
  judgeRound(q8.root, 'code_review', 'docs/ai/reviews/rev-q8.md', '# Review q8\n\nsecurity_relevant: true\n', {}, { reports: ['docs/ai/reviews/rev-q8.md'] });
  commitAll(q8.root, 'judged round report');
  write(q8.root, 'docs/ai/reviews/rev-q8.md', '# Review q8\n\nsecurity_relevant: false\n');
  git(q8.root, ['commit', '-qam', 'flip the marker inside the delta']);
  assertFullBoth(L, q8.root, 'Code Review', ['binding_report_changed:docs/ai/reviews/rev-q8.md'], 'Q8');
  const q9 = mkRepo('t2813-q9', { verdicts: false });
  judgeRound(q9.root, 'validation', Q_VAL, '# Validation q9\n\nsecurity_relevant: true\n', {}, { evidence: [Q_VAL] });
  fs.appendFileSync(path.join(q9.root, '.git/info/exclude'), Q_VAL + '\n');
  write(q9.root, Q_VAL, '# Validation q9\n\nsecurity_relevant: false\n');
  assert.equal(git(q9.root, ['status', '--porcelain', '--', Q_VAL]), '', 'the flip is invisible to git');
  assertFullBoth(L, q9.root, 'Validation', ['binding_report_changed:' + Q_VAL], 'Q9');
});

// ------------------------------------------------------------------ TEST-2829 / 2830 (D13)
test('TEST-2829 markerOfText counts a marker line only at column 0 outside every fenced code block', async () => {
  const L = await lib();
  const m = L.markerOfText;
  assert.equal(typeof m, 'function', 'recheck.mjs must export markerOfText');
  const F = 'security_relevant: false\n';
  const T = 'security_relevant: true\n';
  const cases = [
    ['a real false line', `# R\n\n${F}`, false],
    ['a false line only inside a backtick fence', `# R\n\n\`\`\`\n${F}\`\`\`\n`, null],
    ['a false line only inside a tilde fence', `~~~\n${F}~~~\n`, null],
    ['a fence opened with three leading spaces', `   \`\`\`yaml\n${F}   \`\`\`\n`, null],
    ['a false line indented four spaces', `    ${F}`, null],
    ['a true line outside a fence', `\`\`\`\nx\n\`\`\`\n${T}`, true],
    ['an unclosed fence holding the only marker', `\`\`\`\n${F}`, null],
    ['a real marker before an unclosed fence', `${F}\`\`\`\ntext\n`, null],
    ['a fence then one real false line', `\`\`\`\n${F}\`\`\`\n${F}`, false],
    ['a fence then two real marker lines', `\`\`\`\n${F}\`\`\`\n${F}${F}`, null],
    ['a shorter closing line does not close a longer fence', `\`\`\`\`\n\`\`\`\n${F}\`\`\`\`\n`, null],
    ['a true line only inside a fence is not read', `\`\`\`\n${T}\`\`\`\n${F}`, false],
    ['a closing line with trailing text does not close', `\`\`\`\n${F}\`\`\` x\n`, null],
    ['backticks do not close a tilde fence', `~~~\n${F}\`\`\`\n`, null],
    ['CRLF line endings', 'security_relevant: false\r\n', false],
    ['no marker', '# R\n', null],
    ['a true line and a false line outside', `${T}${F}`, true],
  ];
  const bad = [];
  for (const [label, text, want] of cases) if (m(text) !== want) bad.push(`${label}: got ${m(text)}, want ${want}`);
  assert.deepEqual(bad, []);
});

test('TEST-2830 a report whose only false marker is inside a fence gives full through bind-check and recheckMode', async () => {
  const L = await lib();
  const fenced = '# Validation\n\n```\nsecurity_relevant: false\n```\n';
  const a = mkRepo('t2830-fenced', { valText: fenced });
  touchTest(a.root);
  assert.equal(blockOf(a.root).validation_security, 'null');
  const r = L.recheckMode({ root: a.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(r.mode, 'full');
  assert.ok(r.reasons.includes('security_marker_absent:binding:validation'), reasonsOf(r));
  assert.ok(r.reasons.includes('security_marker_absent:' + VAL_REL), 'the prior-report read also treats it as absent: ' + reasonsOf(r));
  const ctl = mkRepo('t2830-real', { valText: fenced + `\n${MARK_FALSE}` });
  touchTest(ctl.root);
  assert.equal(blockOf(ctl.root).validation_security, 'false');
  const c = L.recheckMode({ root: ctl.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(c.mode, 'delta', 'control: one real false line after the fence: ' + reasonsOf(c));
  const open = mkRepo('t2830-unclosed', { valText: `# Validation\n\n${MARK_FALSE}\n\`\`\`\ntext\n` });
  assert.equal(blockOf(open.root).validation_security, 'null');
});

// ------------------------------------------------------------------ TEST-2831 (D13)
test('TEST-2831 re-pointing STATE spec_path at a lower-level spec inside the same block, in the work item or the focus, keeps the recorded ceremony level', async () => {
  const L = await lib();
  const LOW = 'docs/specs/SPEC-0002-low.md';
  const mk = (name, level) => {
    const fx = mkRepo(name, { level, verdicts: false });
    write(fx.root, LOW, specText(2).replace('SPEC-0001', 'SPEC-0002'));
    commitAll(fx.root, 'a lower-level spec');
    bindRounds(fx.root, ['validation', 'code_review']);
    touchTest(fx.root);
    return fx;
  };
  const decide = (root) => L.recheckMode({ root, ref: REF, role: 'Validation', env: DELTA_ENV });
  const editState = (root, fn) => fs.writeFileSync(stateOf(root), fn(stateText(root)));
  const workItem = (t) => t.replace(/^ {4}spec_path: .*$/m, `    spec_path: ${LOW}`);
  const focus = (t) => t.replace(/^ {2}spec_path: .*$/m, `  spec_path: ${LOW}`);
  // control: an unchanged level 2 ride is delta
  const ok = mk('t2831-ok', 2);
  assert.equal(decide(ok.root).mode, 'delta', 'control: ' + reasonsOf(decide(ok.root)));
  assert.equal(blockOf(ok.root).spec_path, SPEC_REL);
  const a = mk('t2831-workitem', 3);
  editState(a.root, workItem);
  const ra = decide(a.root);
  assert.equal(ra.mode, 'full');
  assert.ok(ra.reasons.includes('spec_path_changed:binding'), reasonsOf(ra));
  assert.ok(ra.reasons.includes('ceremony_l3'), 'the recorded spec is level 3: ' + reasonsOf(ra));
  const b = mk('t2831-focus', 3);
  editState(b.root, (t) => focus(workItem(t)));
  const rb = decide(b.root);
  assert.ok(rb.reasons.includes('spec_path_changed:binding') && rb.reasons.includes('ceremony_l3'), reasonsOf(rb));
  const c = mk('t2831-focus-only', 3);
  editState(c.root, focus);
  assert.ok(decide(c.root).reasons.includes('ceremony_l3'), 'a focus-only re-point leaves the work item path and the level: ' + reasonsOf(decide(c.root)));
  // a block that records no spec path
  const d = mk('t2831-unbound', 2);
  editBlock(d.root, (blk) => blk.filter((l) => !/^ {2}spec_path:/.test(l)));
  const rd = decide(d.root);
  assert.equal(rd.mode, 'full');
  assert.ok(rd.reasons.includes('spec_path_unbound:binding'), reasonsOf(rd));
  // the recorded spec lowered inside the delta is still read at the base
  const e = mk('t2831-lowered', 3);
  write(e.root, SPEC_REL, specText(2));
  assert.ok(decide(e.root).reasons.includes('ceremony_l3'), 'the base blob of the recorded spec says 3');
});

// ------------------------------------------------------------------ TEST-2802
function resultBlock(role, status, { blockers = [], commands = [] } = {}) {
  return [
    '```yaml', 'subagent_result:', '  scope: s', `  role: ${role}`, `  status: ${status}`,
    '  started_utc: 2026-10-24T10:00:00Z', '  ended_utc: 2026-10-24T10:00:10Z', '  duration_seconds: 10',
    '  evidence:', '    - command: git diff', '      exit_code: 0', '      output_snippet: x', '  files_changed: []',
    blockers.length ? '  blockers:' : '  blockers: []', ...blockers.map((b) => `    - ${b}`),
    commands.length ? '  state_update_commands:' : '  state_update_commands: []', ...commands.map((c) => `    - ${c}`),
    '```', ''].join('\n');
}

function checkRoleOutput(name, text, extraArgs = []) {
  const dir = path.join(tmpTop, 'role-output');
  fs.mkdirSync(dir, { recursive: true });
  const f = path.join(dir, name + '.md');
  fs.writeFileSync(f, text);
  return spawnSync(process.execPath, [path.join(SCRIPTS, 'check-role-output.mjs'), '--file', f, '--now', '2026-10-24T10:00:20Z', ...extraArgs], { encoding: 'utf8', env: cleanEnv() });
}

test('TEST-2802 bind-check is refused under any AAI_ROLE, a returned bind-check command is refused, and a subagent tick leaves the block alone', () => {
  const { root } = mkRepo('t2802', { verdicts: false });
  const before = stateText(root);
  for (const v of ['subagent', ' ', '\t', 'Validation']) {
    const r = bindCheck(root, 'dispatch', 'validation', REF, { ...cleanEnv(), AAI_ROLE: v });
    assert.equal(r.status, 3, JSON.stringify(v) + ': ' + r.stderr);
    assert.equal(stateText(root), before, JSON.stringify(v) + ' must write nothing');
  }
  assert.equal(bindCheck(root, 'dispatch', 'validation').status, 0, 'positive control: unset writes');
  assert.notEqual(stateText(root), before);
  // a returned state_update_commands entry naming bind-check is outside the allowlist
  const cmd = 'node .aai/scripts/state.mjs bind-check --on verdict --role validation --ref r1';
  const bad = checkRoleOutput('t2802-bad', resultBlock('Validation', 'PASS', { commands: [cmd] }));
  assert.match(bad.stdout, /E-STATE-UPDATE-COMMAND/);
  const none = checkRoleOutput('t2802-none', resultBlock('Validation', 'PASS'));
  assert.ok(!/E-STATE-UPDATE-COMMAND/.test(none.stdout), 'control: no command, no violation: ' + none.stdout);
  // a dispatch tick run with AAI_ROLE set leaves STATE byte-identical and exits as the unguarded tick
  const guarded = eligibleCanon('t2802-guarded');
  const plain = eligibleCanon('t2802-plain');
  const snap = stateText(guarded.root);
  const g = runDispatch(guarded.root, ['--confirm'], { AAI_ROLE: 'subagent' });
  const u = runDispatch(plain.root, ['--confirm']);
  assert.equal(g.status, u.status, 'the exit code is unchanged: ' + g.stderr);
  assert.equal(g.out.rule, u.out.rule);
  assert.equal(stateText(guarded.root), snap, 'no check_binding change under AAI_ROLE');
  assert.notEqual(stateText(plain.root), stateText(guarded.root), 'control: the unguarded tick did record its dispatch');
  assert.deepEqual(listOf(blockOf(plain.root), 'validation_pending_heads'), [plain.base]);
  // the next orchestrator tick still decides from the unchanged block
  const next = runDispatch(guarded.root);
  assert.equal(rc(next).mode, 'delta', JSON.stringify(next.out.recheck));
  assert.equal(rc(next).base, guarded.base);
});

// ------------------------------------------------------------------ TEST-2814
test('TEST-2814 ride-handoff does not carry the binding, a hand-copied STATE names another checkout, an archived copy is never read', async () => {
  const L = await lib();
  const fx = mkRepo('t2814');
  assert.ok(blockOf(fx.root), 'positive control: the origin STATE holds check_binding before the handoff');
  const saved = stateText(fx.root);
  const wt = path.join(tmpTop, 't2814-wt');
  git(fx.root, ['worktree', 'add', '-q', '-b', 'ride-branch', wt]);
  fs.mkdirSync(path.join(wt, 'docs/ai'), { recursive: true });
  fs.copyFileSync(path.join(PROJECT_ROOT, '.aai/templates/STATE_TEMPLATE.yaml'), stateOf(wt));
  const out = spawnSync(process.execPath, [path.join(SCRIPTS, 'ride-handoff.mjs'), 'out', '--ref', REF, '--worktree', wt, '--state', stateOf(fx.root), '--base-ref', 'main'],
    { cwd: fx.root, encoding: 'utf8', env: cleanEnv() });
  assert.equal(out.status, 0, out.stdout + out.stderr);
  assert.ok(!/^check_binding:/m.test(fs.readFileSync(stateOf(wt), 'utf8')), 'the worktree STATE holds no check_binding');
  const r = L.recheckMode({ root: wt, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(r.mode, 'full');
  assert.ok(r.reasons.includes('first_round'), reasonsOf(r));
  // a STATE copied by hand into another worktree of the same repository
  const wt2 = path.join(tmpTop, 't2814-wt2');
  git(fx.root, ['worktree', 'add', '-q', '--detach', wt2]);
  fs.writeFileSync(stateOf(wt2), saved);
  fs.appendFileSync(path.join(wt2, 'tests/skills/test-aai-base.sh'), 'echo more\n');
  const c = L.recheckMode({ root: wt2, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(c.mode, 'full');
  assert.ok(c.reasons.includes('binding_other_checkout'), reasonsOf(c));
  // an archived copy is never read: the live block removed, the archive copy kept
  const arch = mkRepo('t2814-archive');
  write(arch.root, 'docs/ai/archive/merge-cleanup/STATE-r1.yaml', stateText(arch.root));
  dropBlock(arch.root);
  touchTest(arch.root);
  const a = L.recheckMode({ root: arch.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.ok(a.reasons.includes('first_round'), reasonsOf(a));
  assert.equal(a.mode, 'full');
});

// ------------------------------------------------------------------ TEST-2815
const rawBlock = (root) => {
  const lines = stateText(root).split('\n');
  const i = lines.indexOf('check_binding:');
  if (i < 0) return null;
  let j = i + 1;
  while (j < lines.length && !/^[A-Za-z_]/.test(lines[j])) j += 1;
  return lines.slice(i, j).join('\n');
};

function runFlush(root) {
  fs.mkdirSync(path.join(root, 'docs/ai'), { recursive: true });
  if (!fs.existsSync(path.join(root, 'docs/ai/METRICS.jsonl'))) fs.writeFileSync(path.join(root, 'docs/ai/METRICS.jsonl'), '# ledger\n');
  return spawnSync(process.execPath, [path.join(SCRIPTS, 'metrics-flush.mjs'), '--state', stateOf(root), '--metrics', path.join(root, 'docs/ai/METRICS.jsonl'),
    '--ticks', path.join(root, 'docs/ai/LOOP_TICKS.jsonl'), '--pricing', '.aai/system/PRICING.yaml', '--events', path.join(root, 'docs/ai/EVENTS.jsonl'), '--now', '2026-10-24T12:00:00Z'],
  { cwd: PROJECT_ROOT, encoding: 'utf8', env: cleanEnv() });
}

const flushable = (o = {}) => stateYaml({ vstatus: 'pass', rstatus: 'pass', implModel: 'claude-opus-5-5', ...o });

test('TEST-2815 a partial flush clears the verdict and pending fields, a full flush removes the block, reset-block and check-state leave it alone', async () => {
  const L = await lib();
  const part = mkRepo('t2815-partial');
  const b0 = blockOf(part.root);
  assert.ok(b0 && b0.validation_head && b0.code_review_head, 'positive control: both roles are bound before the flush');
  mustBind(part.root, 'dispatch', 'validation');
  writeKeep(part.root, flushable({ second: true }));
  const p = runFlush(part.root);
  assert.equal(p.status, 0, p.stdout + p.stderr);
  const b1 = blockOf(part.root);
  assert.ok(b1, 'a partial reset keeps the block');
  assert.equal(b1.ref_id, b0.ref_id);
  assert.equal(b1.checkout, b0.checkout);
  assert.equal(b1.security_sticky, b0.security_sticky);
  assert.equal(b1.spec_path, b0.spec_path);
  for (const k of Object.keys(b1)) assert.ok(!/^(validation|code_review)_/.test(k), `a verdict or pending field survived the reset: ${k}`);
  const r = L.recheckMode({ root: part.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.ok(r.reasons.includes('first_round'), reasonsOf(r));
  // the full reset removes the block
  const full = mkRepo('t2815-full');
  writeKeep(full.root, flushable({ wi: 'done' }));
  const f = runFlush(full.root);
  assert.equal(f.status, 0, f.stdout + f.stderr);
  assert.equal(blockOf(full.root), null, 'a full reset removes check_binding');
  // reset-block leaves the block byte-identical
  const rb = mkRepo('t2815-reset');
  writeKeep(rb.root, stateYaml({ vstatus: 'fail' }));
  const before = rawBlock(rb.root);
  assert.ok(before);
  const rr = stateCli(rb.root, ['reset-block', 'last_validation']);
  assert.equal(rr.status, 0, rr.stderr + rr.stdout);
  assert.equal(rawBlock(rb.root), before);
  // check-state is happy with the block present
  const ck = spawnSync(process.execPath, [path.join(SCRIPTS, 'check-state.mjs'), stateOf(rb.root)], { cwd: PROJECT_ROOT, encoding: 'utf8', env: cleanEnv() });
  assert.equal(ck.status, 0, ck.stdout + ck.stderr);
});

// ------------------------------------------------------------------ TEST-2832
test('TEST-2832 the spec path is recorded once from STATE and survives a verdict write, a later dispatch and a partial flush', () => {
  const LOW = 'docs/specs/SPEC-0002-low.md';
  const { root } = mkRepo('t2832', { verdicts: false });
  mustBind(root, 'dispatch', 'validation');
  assert.equal(blockOf(root).spec_path, SPEC_REL);
  // STATE is re-pointed; a later dispatch and a verdict write keep the first path
  writeKeep(root, stateYaml({ spec: LOW, evidence: [], reports: [] }));
  write(root, VAL_N('sp'), `# V\n\n${MARK_FALSE}`);
  commitAll(root, 'later');
  mustBind(root, 'dispatch', 'code_review');
  assert.equal(blockOf(root).spec_path, SPEC_REL, 'a later dispatch after the re-point keeps the first path');
  writeKeep(root, stateYaml({ spec: LOW, vstatus: 'fail', evidence: [VAL_N('sp')] }));
  mustBind(root, 'verdict', 'validation');
  const b = blockOf(root);
  assert.equal(b.validation_status, 'fail');
  assert.equal(b.spec_path, SPEC_REL, 'a verdict write keeps it');
  // a dispatch for another ref replaces the block and records that ref's spec path
  writeKeep(root, stateYaml({ ref: 'r2', spec: LOW }));
  mustBind(root, 'dispatch', 'validation', 'r2');
  assert.equal(blockOf(root).ref_id, 'r2');
  assert.equal(blockOf(root).spec_path, LOW);
  // the partial flush keeps it
  const fl = mkRepo('t2832-flush');
  writeKeep(fl.root, flushable({ second: true }));
  const r = runFlush(fl.root);
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.equal(blockOf(fl.root).spec_path, SPEC_REL);
});

// ------------------------------------------------------------------ TEST-2816
// The whole seam with real ticks: dispatch (--confirm) -> bind-check -> the next tick's decision
// -> canon. Both roles go through one fail, a test-only remediation commit and the next dispatch.
function chain(name, productionBeforeCr) {
  const fx = mkRepo(name, { canon: true, verdicts: false });
  const { root } = fx;
  const tick = () => runDispatch(root, ['--confirm']);
  const mustState = (args) => { const r = stateCli(root, args); assert.equal(r.status, 0, args.join(' ') + ': ' + r.stderr + r.stdout); };
  const report = (rel, text) => { write(root, rel, text); return commitAll(root, 'report ' + rel); };
  const testCommit = (msg) => { fs.appendFileSync(path.join(root, 'tests/skills/test-aai-base.sh'), `echo ${msg}\n`); return commitAll(root, msg); };
  const parity = (d) => {
    const full = runDispatch(root, [], { AAI_RECHECK_MODE: 'full' });
    for (const k of ['role', 'rule', 'suggested_tier', 'suggested_model', 'suggested_effort', 'validator_independence', 'lane']) assert.deepEqual(d.out[k], full.out[k], k);
  };
  const bl = () => { const b = blockOf(root); assert.ok(b, 'the tick wrote no check_binding block'); return b; };
  const out = {};
  // validation round 1: fail
  const H1 = report(VAL_N('c1'), `# V1\n\n${MARK_FALSE}`);
  const t1 = tick();
  assert.equal(t1.out.role, 'Validation');
  assert.ok(rc(t1).reasons.includes('first_round'));
  mustState(['set-validation', '--status', 'fail', '--ref', REF, '--evidence', VAL_N('c1')]);
  const t2 = tick();
  assert.equal(t2.out.role, 'Remediation');
  assert.equal(bl().validation_head, H1);
  testCommit('fix1');
  mustState(['reset-block', 'last_validation']);
  // validation round 2: delta from the head of the first dispatch
  const t3 = tick();
  assert.equal(t3.out.role, 'Validation');
  assert.equal(rc(t3).mode, 'delta', JSON.stringify(t3.out.recheck));
  assert.equal(rc(t3).base, H1);
  parity(t3);
  const cv = canonRun(root, ['build', '--role', 'Validation', '--ref', REF, '--recheck', 'delta']);
  assert.equal(cv.status, 0, cv.stderr);
  assert.ok(cv.stdout.includes(H1), 'the canon scope carries the bound base');
  out.v = { dispatch: t3.out.recheck, canon: cv.status };
  // validation passes; the same tick dispatches the Code Review
  const H2 = git(root, ['rev-parse', 'HEAD']);
  report(VAL_N('c2'), `# V2\n\n${MARK_FALSE}`);
  mustState(['set-validation', '--status', 'pass', '--ref', REF, '--evidence', VAL_N('c2')]);
  const t4 = tick();
  assert.equal(t4.out.role, 'Code Review');
  assert.equal(bl().validation_head, H2);
  const H3 = git(root, ['rev-parse', 'HEAD']);
  report('docs/ai/reviews/c1.md', `# C1\n\n${MARK_FALSE}`);
  mustState(['set-code-review', '--status', 'fail', '--report', 'docs/ai/reviews/c1.md']);
  const t5 = tick();
  assert.equal(t5.out.role, 'Remediation');
  assert.equal(bl().code_review_head, H3, 'the Code Review verdict binds the head of its first dispatch');
  testCommit('fix2');
  mustState(['reset-block', 'code_review']);
  // the stale validation pass runs again (delta from its bound head), then passes
  const t6 = tick();
  assert.equal(t6.out.role, 'Validation');
  assert.equal(rc(t6).base, H2);
  if (productionBeforeCr) {
    write(root, '.aai/scripts/fixture.mjs', 'export const y = 2;\n');
    commitAll(root, 'production change judged by the third validation');
  }
  report(VAL_N('c3'), `# V3\n\n${MARK_FALSE}`);
  // run_at_utc has second resolution and the stamp of the first pass has milliseconds: wait one tick of the clock
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 1100);
  mustState(['set-validation', '--status', 'pass', '--ref', REF, '--evidence', VAL_N('c3')]);
  // the pass is older than the tree it judged until a tick re-stamps it (rule 11s, restamp_requires_confirm)
  const t6b = tick();
  assert.equal(t6b.out.role, 'Validation');
  const t7 = tick();
  assert.equal(t7.out.role, 'Code Review');
  out.cr = { t7, H3 };
  out.root = root;
  out.parity = () => parity(t7);
  out.canon = () => canonRun(root, ['build', '--role', 'Code Review', '--ref', REF, '--recheck', 'delta']);
  return out;
}

test('TEST-2816 end to end: real ticks bind a Validation and a Code Review round, and the next dispatch of each is delta from the bound head', () => {
  const a = chain('t2816', false);
  const t7 = a.cr.t7;
  assert.equal(rc(t7).mode, 'delta', JSON.stringify(t7.out.recheck));
  assert.equal(rc(t7).base, a.cr.H3, 'the Code Review base is the head of its first dispatch, read from check_binding');
  a.parity();
  const c = a.canon();
  assert.equal(c.status, 0, c.stderr);
  assert.ok(c.stdout.includes(a.cr.H3));
  const b = chain('t2816-prod', true);
  assert.equal(rc(b.cr.t7).mode, 'full');
  assert.ok(rc(b.cr.t7).reasons.includes('production_path:.aai/scripts/fixture.mjs'), JSON.stringify(b.cr.t7.out.recheck.reasons));
  assert.equal(b.cr.t7.out.system_prompt, '.aai/SKILL_CODE_REVIEW.prompt.md');
  assert.equal(b.canon().status, 11);
});

// ------------------------------------------------------------------ TEST-2817
test('TEST-2817 check-role-output prints RECHECK-ESCALATION only for a delta round, and the prompts say an escalated round merges nothing', () => {
  const blocked = resultBlock('Code Review', 'BLOCKED', { blockers: ['needs_full_recheck'] });
  const d = checkRoleOutput('t2817-delta', blocked, ['--recheck-mode', 'delta']);
  assert.equal(d.status, 0, d.stdout + d.stderr);
  assert.match(d.stdout, /^RECHECK-ESCALATION: needs_full_recheck /m);
  const f = checkRoleOutput('t2817-full', blocked, ['--recheck-mode', 'full']);
  assert.equal(f.status, 0, f.stdout);
  assert.ok(!f.stdout.includes('RECHECK-ESCALATION'), 'with full a needs_full_recheck BLOCKED is ordinary: ' + f.stdout);
  const n = checkRoleOutput('t2817-none', blocked);
  assert.equal(n.status, 0, n.stdout);
  assert.ok(!n.stdout.includes('RECHECK-ESCALATION'), 'without the flag it is ordinary: ' + n.stdout);
  const bad = checkRoleOutput('t2817-bogus', blocked, ['--recheck-mode', 'bogus']);
  assert.equal(bad.status, 2, bad.stdout + bad.stderr);
  const miss = checkRoleOutput('t2817-missing', blocked, ['--recheck-mode']);
  assert.equal(miss.status, 2, miss.stdout + miss.stderr);
  const orch = readRel('.aai/ORCHESTRATION.prompt.md');
  assert.ok(orch.split('\n').length - (orch.endsWith('\n') ? 1 : 0) <= 45, 'ORCHESTRATION.prompt.md is over 45 lines');
  for (const rel of ['.aai/ORCHESTRATION.prompt.md', '.aai/ORCHESTRATION_PARALLEL.prompt.md', '.aai/SUBAGENT_PROTOCOL.md']) {
    const t = readRel(rel);
    assert.ok(t.includes('--recheck-mode'), rel + ' lacks --recheck-mode');
    assert.ok(t.includes('run none of its state_update_commands'), rel + ' lacks the phrase: run none of its state_update_commands');
  }
});

// ------------------------------------------------------------------ TEST-2818 / 2819
const BANNED = ['tamper-proof', 'guarantee', 'closes every', 'cannot be forged'];
const bannedIn = (text) => BANNED.filter((w) => text.toLowerCase().includes(w));

test('TEST-2818 the ledger comment states the comparison it makes, and the code names no guarantee', () => {
  const src = readRel('.aai/scripts/lib/recheck.mjs').split('\n');
  const at = src.findIndex((l) => l.startsWith('export function eventsAppendOnly('));
  assert.ok(at > 0, 'eventsAppendOnly is not in recheck.mjs');
  let from = at;
  while (from > 0 && src[from - 1].startsWith('//')) from -= 1;
  const comment = src.slice(from, at).join('\n');
  assert.ok(comment.includes('compares only'), 'the comment lacks "compares only": ' + comment);
  assert.ok(!comment.includes('fu-recheck-uncommitted-stamp-rewrite'), 'the comment still names the dropped follow-up id');
  assert.ok(!comment.includes('only lines already present in a committed blob are protected'), 'the comment still claims committed lines are protected');
  for (const rel of ['.aai/scripts/lib/recheck.mjs', '.aai/scripts/lib/check-binding.mjs']) {
    assert.deepEqual(bannedIn(readRel(rel)), [], rel + ' names a banned phrase');
  }
});

const protocolSection = () => {
  const t = readRel('.aai/SUBAGENT_PROTOCOL.md');
  const at = t.indexOf('## Delta re-check');
  assert.ok(at >= 0, 'SUBAGENT_PROTOCOL.md has no Delta re-check section');
  const rest = t.slice(at + 3);
  const next = rest.search(/^## /m);
  return t.slice(at, next < 0 ? undefined : at + 3 + next);
};
const workflowLines = () => readRel('.aai/workflow/WORKFLOW.md').split('\n').filter((l) => /delta re-check/i.test(l));
const changelogEntry = () => {
  const t = readRel('CHANGELOG.md');
  const parts = t.split(/^## \[unreleased\] — /m).slice(1);
  const mine = parts.filter((p) => p.includes('recheck-verdict-binding'));
  assert.equal(mine.length, 1, 'exactly one CHANGELOG entry names recheck-verdict-binding, got ' + mine.length);
  return mine[0];
};

test('TEST-2819 the protocol, the workflow line and the changelog entry name the comparison and carry one Residual: line', () => {
  const proto = protocolSection();
  const wf = workflowLines();
  assert.ok(wf.length >= 1, 'WORKFLOW.md has no delta re-check line');
  const log = changelogEntry();
  for (const [name, text] of [['protocol', proto], ['workflow', wf.join('\n')], ['changelog', log]]) {
    assert.ok(text.includes('check_binding'), name + ' does not name check_binding');
    assert.ok(text.includes('bind-check'), name + ' does not name bind-check');
    assert.deepEqual(bannedIn(text), [], name + ' names a banned phrase');
  }
  assert.equal(proto.split('\n').filter((l) => l.startsWith('Residual:')).length, 1, 'the protocol section has exactly one line starting Residual:');
});

// ------------------------------------------------------------------ TEST-2822 / 2823
test('TEST-2822 PROFILES lists check-binding.mjs exactly once, in core', () => {
  const text = readRel('.aai/system/PROFILES.yaml');
  const coreAt = text.search(/^core:\s*$/m);
  const extAt = text.search(/^extended:\s*$/m);
  assert.ok(coreAt >= 0 && extAt > coreAt);
  const p = '.aai/scripts/lib/check-binding.mjs';
  assert.equal(text.split('\n').filter((l) => l.trim() === '- ' + p).length, 1);
  const at = text.indexOf('- ' + p + '\n');
  assert.ok(at > coreAt && at < extAt, p + ' must be in the core list');
});

test('TEST-2823 the suite map selects aai-recheck for the files the scope touches', () => {
  const select = (p) => spawnSync(process.execPath, [path.join(SCRIPTS, 'select-suites.mjs'), '--files-from', '-'], { cwd: PROJECT_ROOT, input: p + '\n', encoding: 'utf8', env: cleanEnv() });
  const lib = select('.aai/scripts/lib/check-binding.mjs');
  assert.match(lib.stdout, /^FULL_RUN reason=shared-lib path=\.aai\/scripts\/lib\/check-binding\.mjs$/m, lib.stdout);
  const map = readRel('tests/skills/suite-map.yaml');
  const row = map.slice(map.search(/^ {2}aai-recheck:\s*$/m));
  const mine = row.split(/\n {2}[a-z0-9][a-z0-9-]*:\s*\n/)[0];
  for (const f of ['check-binding.mjs', 'state.mjs', 'metrics-flush.mjs', 'check-role-output.mjs']) {
    assert.match(mine, new RegExp(`^ {6}- \\.aai/scripts/(lib/)?${f.replace('.', '\\.')}$`, 'm'), 'the aai-recheck row does not list ' + f);
  }
  for (const p of ['.aai/scripts/metrics-flush.mjs', '.aai/scripts/check-role-output.mjs']) {
    assert.match(select(p).stdout, /^SELECTED aai-recheck\b/m, p + ' did not select aai-recheck');
  }
  const st = select('.aai/scripts/state.mjs').stdout;
  assert.ok(/^FULL_RUN /m.test(st) || /^SELECTED aai-recheck\b/m.test(st), 'state.mjs must select aai-recheck or run everything: ' + st);
});

// ------------------------------------------------------------------ TEST-2825
test('TEST-2825 the RFC-0017 phase 4 row links this slice and stays in progress', () => {
  const text = readRel('docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md');
  const fm = /^---\n([\s\S]*?)\n---/.exec(text);
  assert.ok(fm);
  assert.match(fm[1], /^status:\s*implementing\s*$/m);
  assert.match(fm[1], /^umbrella:\s*true\s*$/m);
  const at = text.indexOf('Rollout Status');
  const rows = text.slice(at).split('\n').filter((l) => /^\|\s*[0-9]+\s*\|/.test(l)).map((l) => l.split('|').slice(1, -1).map((c) => c.trim()));
  const byPhase = {};
  for (const c of rows) byPhase[c[0]] = c;
  const cellStatus = (c) => c.find((x) => /^(not started|in progress|done)$/i.test(x));
  assert.equal((cellStatus(byPhase['4']) || '').toLowerCase(), 'in progress');
  const joined = byPhase['4'].join(' | ');
  assert.equal([...joined.matchAll(/\]\([^)]*recheck-verdict-binding\.md\)/g)].length, 1, 'one link target ends recheck-verdict-binding.md');
  assert.match(joined, /\]\([^)]*cheap-transitions-slice\.md\)/);
  for (const [n, want] of [['0', 'in progress'], ['2', 'in progress'], ['1', 'done'], ['3', 'done'], ['5', 'not started']]) {
    assert.equal((cellStatus(byPhase[n]) || '').toLowerCase(), want, 'phase ' + n);
  }
});

// ------------------------------------------------------------------ TEST-2826
test('TEST-2826 the #498 amendments are signed and their trackers are done', () => {
  const run = (script, args) => JSON.parse(execFileSync(process.execPath, [path.join(SCRIPTS, script), ...args], { cwd: PROJECT_ROOT, encoding: 'utf8', env: cleanEnv(), maxBuffer: 64 * 1024 * 1024 }));
  const sa = run('spec-amend.mjs', ['list', '--json']);
  const fu = run('follow-ups.mjs', ['list', '--status', 'all', '--json']);
  const mine = sa.items.filter((i) => i.ref_id === 'cheap-transitions-slice' && String(i.ts) < '2026-10-24T18:30:00Z');
  const other = mine.filter((i) => i.bucket !== 'signed' && i.bucket !== 'measurement');
  assert.deepEqual(other.map((i) => i.record_key + ' is ' + i.bucket), []);
  assert.ok(mine.filter((i) => i.bucket === 'signed').length >= 11, 'fewer than eleven signed records for cheap-transitions-slice');
  for (const [ts, ref] of [['2026-10-24T12:53:10Z', 'roadmap-serves-downstream-projects'], ['2026-10-24T12:53:11Z', 'ride-state-handoff-to-worktree'],
    ['2026-10-24T12:53:11Z', 'canon-is-a-build-artifact'], ['2026-10-24T13:42:28Z', 'node-first-third-slice']]) {
    const recs = sa.items.filter((i) => i.ts === ts && i.ref_id === ref);
    assert.ok(recs.length >= 1 && recs.every((i) => i.bucket === 'signed'), `${ref} at ${ts} is not signed: ${JSON.stringify(recs.map((i) => i.bucket))}`);
  }
  for (const id of ['fu-amend-spec-cheap-transitions-slice', 'fu-amend-roadmap-serves-downstrea-fb0e2b', 'fu-amend-canon-is-a-build-artifac-d789f0', 'fu-amend-node-first-third-slice-2-6a231a']) {
    const f = fu.items.find((i) => i.id === id);
    assert.ok(f, id + ' is not listed');
    assert.equal(f.status, 'done', id);
  }
});

// ------------------------------------------------------------------ TEST-2827
test('TEST-2827 this ride stays full: ceremony_l3 on its own spec, for both roles, with and without the opt-in', async () => {
  const L = await lib();
  const specName = fs.readdirSync(path.join(PROJECT_ROOT, 'docs/specs')).find((f) => /-spec-recheck-verdict-binding\.md$/.test(f));
  assert.ok(specName, 'the recheck-verdict-binding spec is not under docs/specs');
  const specRel = 'docs/specs/' + specName;
  const so = { ref: 'recheck-verdict-binding', spec: specRel };
  const fx = mkRepo('t2827', { verdicts: false, state: so });
  fs.copyFileSync(path.join(PROJECT_ROOT, specRel), path.join(fx.root, specRel));
  commitAll(fx.root, 'the live spec');
  bindRounds(fx.root, ['validation', 'code_review'], so);
  touchTest(fx.root);
  for (const role of ['Validation', 'Code Review']) {
    for (const env of [DELTA_ENV, {}]) {
      const r = L.recheckMode({ root: fx.root, ref: 'recheck-verdict-binding', role, env });
      assert.equal(r.mode, 'full', role);
      assert.ok(r.reasons.includes('ceremony_l3'), `${role}: ${reasonsOf(r)}`);
    }
  }
});

// ------------------------------------------------------------------ TEST-2828
test('TEST-2828 SPEC-0250 points at this spec for the stamp residual and the amendment is recorded', () => {
  const name = fs.readdirSync(path.join(PROJECT_ROOT, 'docs/specs')).find((f) => /-spec-cheap-transitions-slice\.md$/.test(f));
  assert.ok(name);
  const text = readRel('docs/specs/' + name);
  const row = text.split('\n').find((l) => l.startsWith('| TEST-2742 |'));
  assert.ok(row, 'no TEST-2742 row in SPEC-0250');
  assert.ok(row.includes('spec-recheck-verdict-binding'), 'the TEST-2742 row does not name spec-recheck-verdict-binding');
  assert.ok(!row.includes('pins the KNOWN general residual'), 'the TEST-2742 row still pins the residual');
  const d4 = text.slice(text.indexOf('### D4'), text.indexOf('### D5'));
  assert.ok(d4.includes('spec-recheck-verdict-binding'), 'D4 does not name spec-recheck-verdict-binding');
  assert.ok(!d4.includes('pins the KNOWN general residual'));
  const sa = JSON.parse(execFileSync(process.execPath, [path.join(SCRIPTS, 'spec-amend.mjs'), 'list', '--json'], { cwd: PROJECT_ROOT, encoding: 'utf8', env: cleanEnv(), maxBuffer: 64 * 1024 * 1024 }));
  const later = sa.items.filter((i) => i.ref_id === 'cheap-transitions-slice' && String(i.ts) > '2026-10-24T18:30:00Z' && i.tracked_by !== 'fu-amend-spec-cheap-transitions-slice');
  assert.ok(later.length >= 1, 'no later spec_amendment of cheap-transitions-slice with a new tracker');
  const strict = spawnSync(process.execPath, [path.join(SCRIPTS, 'spec-amend.mjs'), 'list', '--strict'], { cwd: PROJECT_ROOT, encoding: 'utf8', env: cleanEnv(), maxBuffer: 64 * 1024 * 1024 });
  assert.equal(strict.status, 0, 'spec-amend list --strict exits ' + strict.status);
});

// ------------------------------------------------------------------ TEST-2820 / 2821 (D7, the separable flip)
test('TEST-2820 default on: deltaEnabled, recheckMode, the dispatch field and canon agree for every value', async () => {
  const L = await lib();
  for (const v of [undefined, '', '   ', 'delta', 'DELTA', ' delta ']) assert.equal(L.deltaEnabled({ AAI_RECHECK_MODE: v }), true, JSON.stringify(v));
  for (const v of ['full', 'FULL', ' full ', 'off', '0', 'false', 'dleta']) assert.equal(L.deltaEnabled({ AAI_RECHECK_MODE: v }), false, JSON.stringify(v));
  const fx = eligibleCanon('t2820');
  const unset = runDispatchEnv(fx.root, unsetEnv());
  assert.equal(rc(unset).mode, 'delta', JSON.stringify(unset.out.recheck));
  assert.equal(unset.out.system_prompt, '.aai/RECHECK_DELTA.prompt.md');
  const cd = spawnSync(process.execPath, [path.join(SCRIPTS, 'canon.mjs'), 'build', '--role', 'Validation', '--ref', REF, '--recheck', 'delta'], { cwd: fx.root, encoding: 'utf8', env: unsetEnv() });
  assert.equal(cd.status, 0, cd.stderr);
  const off = { ...unsetEnv(), AAI_RECHECK_MODE: 'full' };
  const forced = runDispatchEnv(fx.root, off);
  assert.equal(rc(forced).mode, 'full');
  assert.ok(rc(forced).reasons.includes('recheck_disabled'));
  const cf = spawnSync(process.execPath, [path.join(SCRIPTS, 'canon.mjs'), 'build', '--role', 'Validation', '--ref', REF, '--recheck', 'delta'], { cwd: fx.root, encoding: 'utf8', env: off });
  assert.equal(cf.status, 11);
  assert.match(cf.stderr, /recheck_disabled/);
});

function runDispatchEnv(root, env) {
  const r = spawnSync(process.execPath, [path.join(SCRIPTS, 'orchestration-dispatch.mjs'), '--state', stateOf(root), '--root', root], { cwd: PROJECT_ROOT, encoding: 'utf8', env });
  return { status: r.status, out: JSON.parse(r.stdout), stderr: r.stderr };
}

test('TEST-2821 the docs state the default as on with AAI_RECHECK_MODE=full as the opt-out', () => {
  const recheckLines = (t) => t.split('\n').filter((l) => /recheck|delta/i.test(l));
  const docs = {
    protocol: protocolSection(),
    workflow: workflowLines().join('\n'),
    orchestration: readRel('.aai/ORCHESTRATION.prompt.md'),
    parallel: readRel('.aai/ORCHESTRATION_PARALLEL.prompt.md'),
    changelog: changelogEntry(),
  };
  for (const [name, text] of Object.entries(docs)) {
    assert.ok(text.includes('AAI_RECHECK_MODE=full'), name + ' lacks AAI_RECHECK_MODE=full');
    const bad = recheckLines(text).filter((l) => /opt-in|off by default/i.test(l));
    assert.deepEqual(bad, [], name + ' still calls the mode opt-in or off by default');
  }
  const name = fs.readdirSync(path.join(PROJECT_ROOT, 'docs/specs')).find((f) => /-spec-cheap-transitions-slice\.md$/.test(f));
  const row = readRel('docs/specs/' + name).split('\n').find((l) => l.startsWith('| Spec-AC-17 |'));
  assert.ok(row && row.includes('spec-recheck-verdict-binding'), 'SPEC-0250 Spec-AC-17 does not name spec-recheck-verdict-binding');
  // the escalation sentence names the opt-out explicitly, and no place calls an unset variable the full default
  const esc = docs.protocol.split('\n').filter((l) => l.includes('RECHECK-ESCALATION'));
  assert.ok(esc.length > 0 && esc.every((l) => l.includes('AAI_RECHECK_MODE=full') && !/full[^.]*or unset/.test(l)), 'the escalation re-dispatch must name AAI_RECHECK_MODE=full set explicitly');
  const rfc = readRel('docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md').split('\n').filter((l) => l.includes('recheck-verdict-binding'));
  assert.ok(rfc.length > 0 && rfc.every((l) => !/stays opt-in|opt-in until/.test(l)), 'the RFC-0017 row still says the mode stays opt-in');
  const log498 = readRel('CHANGELOG.md').split(/^## \[unreleased\] — /m).find((p) => p.startsWith('feat(recheck): an opt-in slim payload'));
  assert.ok(log498 && /changes the default/.test(log498), 'the #498 CHANGELOG entry does not say that the later entry changes the default');
  const spec250 = readRel('docs/specs/' + name);
  const stale = spec250.split('\n').filter((l) => /delta is OPT-IN|opt-in by proof|Delta is off by default|leave `AAI_RECHECK_MODE` unset \(the default\)|unset \(the default\) keeps/.test(l));
  assert.deepEqual(stale, [], 'SPEC-0250 still states the old default');
});

// =====================================================================================
// recheck-verdict-binding remediation round 1 (TEST-2833..2837): the per-ref check_sticky record.
// It is written only by bind-check, only ever raises the flag and adds spec paths, and is not
// touched by a block replacement, a flush or reset-block. Each case ends in a round that
// STATE would otherwise let run as delta, so each asserts full.
// =====================================================================================
const stickyRaw = (root) => {
  const lines = stateText(root).split('\n');
  const i = lines.indexOf('check_sticky:');
  if (i < 0) return null;
  let j = i + 1;
  while (j < lines.length && !/^[A-Za-z_]/.test(lines[j])) j += 1;
  return lines.slice(i, j).join('\n');
};
// The record of one ref as plain data, parsed here and not by the library under test.
const stickyOf = (root, ref = REF) => {
  const raw = stickyRaw(root);
  if (raw === null) return null;
  for (const l of raw.split('\n').slice(1)) {
    const m = /^ {2}- '(.*)'$/.exec(l);
    if (!m) continue;
    const o = JSON.parse(m[1].replace(/''/g, "'"));
    if (o.ref_id === ref) return o;
  }
  return null;
};
const decideFull = async (root, ref = REF, env = DELTA_ENV) => (await lib()).recheckMode({ root, ref, role: 'Validation', env });
const setFocus = (root, ref, issue, spec = SPEC_REL) => {
  const r = stateCli(root, ['set-focus', '--type', 'intake_change', '--ref', ref, '--path', issue, '--spec_path', spec]);
  assert.equal(r.status, 0, 'set-focus ' + ref + ': ' + r.stderr + r.stdout);
};
const ISSUE_1 = 'docs/issues/CHANGE-0001-fixture.md';
const ISSUE_2 = 'docs/issues/CHANGE-0002-other.md';

test('TEST-2833 a focus switch away and back through state.mjs alone does not lower security_sticky: the next test-only round is full', async () => {
  const R = 'ride-one';
  const so = { ref: R };
  const { root } = mkRepo('t2833', { verdicts: false, state: so });
  judgeRound(root, 'validation', VAL_N('a1'), '# Round 1\n\nsecurity_relevant: true\n', so);
  assert.equal(blockOf(root).security_sticky, 'true', 'control: round 1 bound true');
  setFocus(root, 'hotfix-two', ISSUE_2);
  mustBind(root, 'dispatch', 'validation', 'hotfix-two');
  assert.equal(blockOf(root).ref_id, 'hotfix-two', 'the block was replaced');
  assert.equal(blockOf(root).security_sticky, 'false', 'the replacing block starts without the flag');
  assert.equal(stickyOf(root, R).security, true, 'the per-ref record kept it');
  setFocus(root, R, ISSUE_1);
  mustBind(root, 'dispatch', 'validation', R);
  write(root, VAL_N('a2'), `# Round 2\n\n${MARK_FALSE}`);
  const sv = stateCli(root, ['set-validation', '--ref', R, '--status', 'fail', '--evidence', VAL_N('a2')]);
  assert.equal(sv.status, 0, sv.stderr + sv.stdout);
  mustBind(root, 'verdict', 'validation', R);
  assert.equal(blockOf(root).validation_security, 'false', 'round 2 itself says false');
  touchTest(root);
  const L = await lib();
  for (const env of [DELTA_ENV, {}]) {
    const m = L.recheckMode({ root, ref: R, role: 'Validation', env });
    assert.equal(m.mode, 'full', reasonsOf(m));
    assert.ok(m.reasons.includes('security_relevant:binding') || m.reasons.includes('security_relevant:sticky'), reasonsOf(m));
  }
  // alternation r1 to r2 to r1 once more: the record still holds
  setFocus(root, 'hotfix-two', ISSUE_2);
  mustBind(root, 'dispatch', 'validation', 'hotfix-two');
  setFocus(root, R, ISSUE_1);
  judgeRound(root, 'validation', VAL_N('a3'), `# Round 3\n\n${MARK_FALSE}`, so);
  touchTest(root);
  const m3 = L.recheckMode({ root, ref: R, role: 'Validation', env: DELTA_ENV });
  assert.equal(m3.mode, 'full', reasonsOf(m3));
  assert.ok(m3.reasons.includes('security_relevant:sticky'), 'after the second replacement only the record carries it: ' + reasonsOf(m3));
  // control: a ride that never bound true stays delta after the same alternation
  const ctl = mkRepo('t2833-ctl', { verdicts: false, state: so });
  judgeRound(ctl.root, 'validation', VAL_N('c1'), `# Round 1\n\n${MARK_FALSE}`, so);
  setFocus(ctl.root, 'hotfix-two', ISSUE_2);
  mustBind(ctl.root, 'dispatch', 'validation', 'hotfix-two');
  setFocus(ctl.root, R, ISSUE_1);
  judgeRound(ctl.root, 'validation', VAL_N('c2'), `# Round 2\n\n${MARK_FALSE}`, so);
  touchTest(ctl.root);
  const c = L.recheckMode({ root: ctl.root, ref: R, role: 'Validation', env: DELTA_ENV });
  assert.equal(c.mode, 'delta', 'control: ' + reasonsOf(c));
});

test('TEST-2834 git worktree move replaces the block but not the per-ref record: the next test-only round is full', async () => {
  const fx = mkRepo('t2834', { verdicts: false });
  const wt = path.join(tmpTop, 't2834-linked');
  git(fx.root, ['worktree', 'add', '-q', '-b', 'wm-branch', wt, 'HEAD']);
  const real = fs.realpathSync(wt);
  writeKeep(real, stateYaml());
  judgeRound(real, 'validation', VAL_N('w1'), '# Round 1\n\nsecurity_relevant: true\n');
  judgeRound(real, 'validation', VAL_N('w2'), `# Round 2\n\n${MARK_FALSE}`);
  assert.equal(blockOf(real).security_sticky, 'true', 'control: bound true before the move');
  const moved = path.join(tmpTop, 't2834-moved');
  git(fx.root, ['worktree', 'move', real, moved]);
  const now = fs.realpathSync(moved);
  const L = await lib();
  const before = L.recheckMode({ root: now, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.ok(before.reasons.includes('binding_other_checkout'), reasonsOf(before));
  judgeRound(now, 'validation', VAL_N('w3'), `# Round 3\n\n${MARK_FALSE}`);
  assert.equal(blockOf(now).checkout, topLevel(now), 'the block was replaced for the new checkout');
  assert.equal(blockOf(now).security_sticky, 'true', 'the replacing block is seeded from the record');
  assert.equal(stickyOf(now).security, true);
  touchTest(now);
  for (const env of [DELTA_ENV, {}]) {
    const m = L.recheckMode({ root: now, ref: REF, role: 'Validation', env });
    assert.equal(m.mode, 'full', reasonsOf(m));
    assert.ok(m.reasons.includes('security_relevant:binding') || m.reasons.includes('security_relevant:sticky'), reasonsOf(m));
  }
  // control: the same move on a ride that never bound true gives delta once re-bound
  const c = mkRepo('t2834-ctl', { verdicts: false });
  const cwt = path.join(tmpTop, 't2834-ctl-linked');
  git(c.root, ['worktree', 'add', '-q', '-b', 'wm-ctl', cwt, 'HEAD']);
  const creal = fs.realpathSync(cwt);
  writeKeep(creal, stateYaml());
  judgeRound(creal, 'validation', VAL_N('x1'), `# Round 1\n\n${MARK_FALSE}`);
  const cmoved = path.join(tmpTop, 't2834-ctl-moved');
  git(c.root, ['worktree', 'move', creal, cmoved]);
  const cnow = fs.realpathSync(cmoved);
  judgeRound(cnow, 'validation', VAL_N('x2'), `# Round 2\n\n${MARK_FALSE}`);
  touchTest(cnow);
  const cm = L.recheckMode({ root: cnow, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(cm.mode, 'delta', 'control: ' + reasonsOf(cm));
});

test('TEST-2835 ride-handoff out copies the record of its ref into the worktree STATE, and the worktree rounds stay full', async () => {
  const fx = mkRepo('t2835', { verdicts: false });
  judgeRound(fx.root, 'validation', VAL_N('h1'), '# Round 1\n\nsecurity_relevant: true\n');
  judgeRound(fx.root, 'validation', VAL_N('h2'), `# Round 2\n\n${MARK_FALSE}`);
  const want = stickyOf(fx.root);
  assert.equal(want.security, true);
  const wt = path.join(tmpTop, 't2835-wt');
  git(fx.root, ['worktree', 'add', '-q', '-b', 'ride-branch', wt, 'HEAD']);
  const real = fs.realpathSync(wt);
  const rep = spawnSync(process.execPath, [path.join(SCRIPTS, 'check-state.mjs'), '--repair'], { cwd: real, encoding: 'utf8', env: cleanEnv() });
  assert.equal(rep.status, 0, rep.stdout + rep.stderr);
  const run = (state = stateOf(fx.root)) => spawnSync(process.execPath, [path.join(SCRIPTS, 'ride-handoff.mjs'), 'out', '--ref', REF, '--worktree', real,
    '--state', state, '--base-ref', 'main'], { cwd: fx.root, encoding: 'utf8', env: cleanEnv() });
  const h = run();
  assert.equal(h.status, 0, h.stdout + h.stderr);
  assert.deepEqual(stickyOf(real), want, 'the worktree holds the origin record');
  assert.equal(blockOf(real), null, 'the block itself is not carried: the worktree starts at first_round');
  const L = await lib();
  const first = L.recheckMode({ root: real, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.ok(first.reasons.includes('first_round'), reasonsOf(first));
  judgeRound(real, 'validation', VAL_N('h3'), `# Round 3\n\n${MARK_FALSE}`);
  judgeRound(real, 'validation', VAL_N('h4'), `# Round 4\n\n${MARK_FALSE}`);
  assert.equal(stickyOf(real).security, true, 'the worktree binds never lowered it');
  touchTest(real);
  const m = L.recheckMode({ root: real, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(m.mode, 'full', reasonsOf(m));
  assert.ok(m.reasons.includes('security_relevant:binding') || m.reasons.includes('security_relevant:sticky'), reasonsOf(m));
  // an origin record that does not parse, and a block of the ref with no record, are carried raised
  for (const [label, edit] of [
    ['unparseable record', (t) => t.replace(/^check_sticky:\n( {2}- .*\n)+/m, "check_sticky:\n  - 'not json'\n")],
    ['block with no record', (t) => t.replace(/^check_sticky:\n( {2}- .*\n)+/m, '')],
  ]) {
    const o = mkRepo('t2835-' + label.replace(/\W/g, ''), { verdicts: false });
    judgeRound(o.root, 'validation', VAL_N('u1'), `# Round 1\n\n${MARK_FALSE}`);
    fs.writeFileSync(stateOf(o.root), edit(stateText(o.root)));
    const w2 = path.join(tmpTop, 't2835-wt-' + label.replace(/\W/g, ''));
    git(o.root, ['worktree', 'add', '-q', '-b', 'rb-' + label.replace(/\W/g, ''), w2, 'HEAD']);
    const r2 = fs.realpathSync(w2);
    const rp = spawnSync(process.execPath, [path.join(SCRIPTS, 'check-state.mjs'), '--repair'], { cwd: r2, encoding: 'utf8', env: cleanEnv() });
    assert.equal(rp.status, 0, rp.stdout + rp.stderr);
    const hh = spawnSync(process.execPath, [path.join(SCRIPTS, 'ride-handoff.mjs'), 'out', '--ref', REF, '--worktree', r2, '--state', stateOf(o.root), '--base-ref', 'main'],
      { cwd: o.root, encoding: 'utf8', env: cleanEnv() });
    assert.equal(hh.status, 0, label + ': ' + hh.stdout + hh.stderr);
    assert.equal(stickyOf(r2).security, true, label + ': carried with the flag raised');
  }
});

test('TEST-2836 a spec path re-pointed after a focus switch cannot lower the ceremony level: the record keeps the L3 path', async () => {
  const LOW = 'docs/specs/SPEC-0002-low.md';
  const fx = mkRepo('t2836', { verdicts: false, level: 3 });
  write(fx.root, LOW, specText(2).replace('SPEC-0001', 'SPEC-0002'));
  commitAll(fx.root, 'a lower-level spec');
  judgeRound(fx.root, 'validation', VAL_N('p1'), `# Round 1\n\n${MARK_FALSE}`);
  assert.equal(blockOf(fx.root).spec_path, SPEC_REL);
  setFocus(fx.root, 'hotfix-two', ISSUE_2);
  mustBind(fx.root, 'dispatch', 'validation', 'hotfix-two');
  assert.equal(blockOf(fx.root).ref_id, 'hotfix-two');
  const low = { spec: LOW };
  judgeRound(fx.root, 'validation', VAL_N('p2'), `# Round 2\n\n${MARK_FALSE}`, low);
  assert.equal(blockOf(fx.root).spec_path, LOW, 'the replacing block records the re-pointed path');
  assert.deepEqual(stickyOf(fx.root).spec_paths.sort(), [LOW, SPEC_REL].sort(), 'the record holds both paths');
  touchTest(fx.root);
  const L = await lib();
  for (const env of [DELTA_ENV, {}]) {
    const m = L.recheckMode({ root: fx.root, ref: REF, role: 'Validation', env });
    assert.equal(m.mode, 'full', reasonsOf(m));
    assert.ok(m.reasons.includes('ceremony_l3'), reasonsOf(m));
  }
  // control: both paths level 2 stays delta through the same switch
  const ctl = mkRepo('t2836-ctl', { verdicts: false, level: 2 });
  write(ctl.root, LOW, specText(2).replace('SPEC-0001', 'SPEC-0002'));
  commitAll(ctl.root, 'a lower-level spec');
  judgeRound(ctl.root, 'validation', VAL_N('q1'), `# Round 1\n\n${MARK_FALSE}`);
  setFocus(ctl.root, 'hotfix-two', ISSUE_2);
  mustBind(ctl.root, 'dispatch', 'validation', 'hotfix-two');
  judgeRound(ctl.root, 'validation', VAL_N('q2'), `# Round 2\n\n${MARK_FALSE}`, low);
  touchTest(ctl.root);
  const c = L.recheckMode({ root: ctl.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(c.mode, 'delta', 'control: ' + reasonsOf(c));
});

test('TEST-2837 the record is raise-only: a partial flush, a full flush and reset-block leave it, and an absent or unparseable record gives full', async () => {
  const L = await lib();
  const mk = (name) => {
    const fx = mkRepo(name, { verdicts: false });
    judgeRound(fx.root, 'validation', VAL_N('f1'), '# Round 1\n\nsecurity_relevant: true\n');
    return fx;
  };
  const part = mk('t2837-partial');
  const rec0 = stickyRaw(part.root);
  assert.ok(rec0 && rec0.includes('"security":true'), 'control: the record holds the flag');
  writeKeep(part.root, flushable({ second: true }));
  const p = runFlush(part.root);
  assert.equal(p.status, 0, p.stdout + p.stderr);
  assert.equal(stickyRaw(part.root), rec0, 'a partial flush leaves the record byte-identical');
  const full = mk('t2837-full');
  writeKeep(full.root, flushable({ wi: 'done' }));
  const f = runFlush(full.root);
  assert.equal(f.status, 0, f.stdout + f.stderr);
  assert.equal(blockOf(full.root), null, 'control: the full flush removed the block');
  assert.ok(stickyRaw(full.root) && stickyRaw(full.root).includes('"security":true'), 'a full flush leaves the record');
  const rb = mk('t2837-reset');
  const before = stickyRaw(rb.root);
  for (const blk of ['last_validation', 'code_review']) {
    const r = stateCli(rb.root, ['reset-block', blk, '--force']);
    assert.equal(r.status, 0, r.stderr + r.stdout);
  }
  assert.equal(stickyRaw(rb.root), before, 'reset-block leaves the record');
  // a later bind with false never lowers it
  judgeRound(rb.root, 'validation', VAL_N('f2'), `# Round 2\n\n${MARK_FALSE}`);
  assert.equal(stickyOf(rb.root).security, true);
  // absent record beside a bound block, and an unparseable record, are not delta
  const absent = mkRepo('t2837-absent', { verdicts: false });
  judgeRound(absent.root, 'validation', VAL_N('g1'), `# Round 1\n\n${MARK_FALSE}`);
  touchTest(absent.root);
  assert.equal(L.recheckMode({ root: absent.root, ref: REF, role: 'Validation', env: DELTA_ENV }).mode, 'delta', 'control: a present record of a false ride is delta');
  fs.writeFileSync(stateOf(absent.root), stateText(absent.root).replace(/^check_sticky:\n( {2}- .*\n)+/m, ''));
  const ra = L.recheckMode({ root: absent.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(ra.mode, 'full');
  assert.ok(ra.reasons.includes('sticky_record_absent:binding'), reasonsOf(ra));
  const bad = mkRepo('t2837-bad', { verdicts: false });
  judgeRound(bad.root, 'validation', VAL_N('g2'), `# Round 1\n\n${MARK_FALSE}`);
  touchTest(bad.root);
  fs.writeFileSync(stateOf(bad.root), stateText(bad.root).replace(/^check_sticky:\n( {2}- .*\n)+/m, "check_sticky:\n  - '{broken'\n"));
  const rbad = L.recheckMode({ root: bad.root, ref: REF, role: 'Validation', env: DELTA_ENV });
  assert.equal(rbad.mode, 'full');
  assert.ok(rbad.reasons.includes('sticky_record_ambiguous'), reasonsOf(rbad));
  // a bind over an unparseable record rewrites it with the flag raised
  mustBind(bad.root, 'dispatch', 'validation');
  assert.equal(stickyOf(bad.root).security, true);
});
