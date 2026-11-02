// suite-reuse.test.mjs - node:test cases of spec-precise-suite-evidence-reuse
// (library rows of Spec-AC-02, -03, -04, -05, -06, -07, -08, -09) and of
// spec-reuse-for-docs-reading-suites (TEST-3261..3269: the access trace and the
// identity built from it).
//
// Every case builds a throwaway git repository holding a suite map, a manifest
// and a few fixture suites, then drives the helper's library entry points with
// an injected environment and runtime (never the host's). Nothing runs in the
// shipping tree. Case names start with their spec TEST id (the wrapper suite
// selects by that prefix so mutation-run.mjs can target one row).

import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..', '..');
const HELPER = process.env.SUITE_REUSE_SCRIPT || path.join(REPO, '.aai', 'scripts', 'suite-reuse.mjs');
const SELECTOR = path.join(REPO, '.aai', 'scripts', 'select-suites.mjs');
const TRACE_MODULE = process.env.CHECKOUT_TRACE_MODULE || path.join(REPO, '.aai', 'scripts', 'lib', 'checkout-trace.mjs');

const roots = [];
after(() => { for (const r of roots) fs.rmSync(r, { recursive: true, force: true }); });

// The helper may not exist yet (RED): the missing module is the test's own
// assertion, not a loader crash.
async function lib() {
  let mod = null;
  try { mod = await import(pathToFileURL(HELPER).href); } catch { /* asserted below */ }
  assert.ok(mod, `helper ${HELPER} exists and loads`);
  return mod;
}

const ENV = { PATH: '/usr/bin:/bin', HOME: '/home/fixture', AAI_FIXTURE_X: '1', AAI_TEST_REF_ID: 'a' };
const RT = { node: 'v24.0.0', platform: 'linux', arch: 'x64', git: 'git version 2.40', bash: 'GNU bash 5.2' };
const BASE = { env: ENV, runtime: RT };
const GIT_ENV = {
  ...process.env, GIT_AUTHOR_NAME: 'F', GIT_AUTHOR_EMAIL: 'f@example.invalid', GIT_COMMITTER_NAME: 'F',
  GIT_COMMITTER_EMAIL: 'f@example.invalid', GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_NOSYSTEM: '1',
};
delete GIT_ENV.AAI_ROLE;

function git(root, ...args) {
  const r = spawnSync('git', ['-C', root, ...args], { env: GIT_ENV, encoding: 'utf8' });
  assert.equal(r.status, 0, `git ${args.join(' ')}: ${r.stderr}`);
  return r.stdout;
}
const suiteRow = (name, globs) => `  ${name}:\n    globs:\n${globs.map((g) => `      - ${g}`).join('\n')}\n`;
const MAP = `core:\n  - fy\nfull_run_triggers:\n  shared_lib_globs:\n    - .aai/scripts/lib/**\nsuites:\n`
  + suiteRow('fx', ['tests/skills/lib/data/*.txt'])
  + suiteRow('fy', ['tests/skills/test-fy.sh'])
  + suiteRow('fz', ['tests/skills/test-fz.sh'])
  + suiteRow('fh', ['tests/skills/test-fh.sh']);
const MANIFEST = {
  version: 1,
  suites: Object.fromEntries(['fx', 'fy', 'fz', 'fh'].map((s) => [s, { inputs: [], live: false, note: 'fixture suite reads only its closure' }])),
};

function mkRepo(overrides = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'suite-reuse-'));
  roots.push(root);
  const files = {
    '.gitignore': 'tests/skills/results/\ndocs/ai/STATE.yaml\n',
    'tests/skills/suite-map.yaml': MAP,
    'tests/skills/suite-reuse.json': JSON.stringify(MANIFEST),
    'tests/skills/test-fx.sh': '#!/usr/bin/env bash\nnode "$ROOT/tests/skills/lib/fx.test.mjs"\nls tests/skills/fixtures/dir/\necho STATE.yaml\n',
    'tests/skills/test-fy.sh': '#!/usr/bin/env bash\necho nothing\n',
    'tests/skills/test-fz.sh': '#!/usr/bin/env bash\necho "$AAI_TEST_REF_ID"\n',
    'tests/skills/test-fh.sh': '#!/usr/bin/env bash\ngit rev-parse HEAD\n',
    'tests/skills/lib/fx.test.mjs': "import { u } from './util.mjs';\nexport default u;\n",
    'tests/skills/lib/util.mjs': 'export const u = 1;\n',
    'tests/skills/lib/data/a.txt': 'a\n',
    'tests/skills/fixtures/dir/one.txt': 'one\n',
    'docs/ai/STATE.yaml': 'state: 1\n',
    ...overrides,
  };
  git(root, 'init', '-q', '-b', 'main');
  for (const [rel, text] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
    fs.writeFileSync(path.join(root, rel), text);
  }
  git(root, 'add', '-A');
  git(root, 'commit', '-q', '-m', 'fixture');
  return root;
}
const PASS = (suite) => ({ skill: suite, status: 'PASS', duration_seconds: 1, exit_code: 0, tripwire_attested: true, tripwire_hasher_degraded: false });
const runDirOf = (root, id = 'run1') => path.join(root, 'tests', 'skills', 'results', id);

const sha = (text) => createHash('sha256').update(text).digest('hex');
async function treePaths(root) {
  const { listTreeFiles } = await import(pathToFileURL(path.join(REPO, '.aai', 'scripts', 'lib', 'tree-hash.mjs')).href);
  const seeds = ['docs/ai/STATE.yaml', 'docs/ai/LOOP_TICKS.jsonl', 'docs/ai/hitl-channel.json'].filter((x) => fs.existsSync(path.join(root, x)));
  return [...new Set([...listTreeFiles(root), ...seeds])].sort();
}
// A synthetic trace file as collectTrace would write it. over.inputs maps a path to true (hash the working
// tree file now) or to a string (the hash to claim); the suite file is always an input.
async function writeTrace(root, suite, runDir, over = {}) {
  const inputs = { [`tests/skills/test-${suite}.sh`]: true, ...(over.inputs || {}) };
  for (const [p, v] of Object.entries(inputs)) {
    const abs = path.join(root, p);
    inputs[p] = v === true ? sha(fs.readFileSync(abs)) + ((fs.statSync(abs).mode & 0o111) ? ':x' : ':-') : v;
  }
  const trace = {
    suite, run_id: path.basename(runDir), canary: true, git_read: false, index_read: false, paths: await treePaths(root), env_names: [],
    ...over, inputs,
  };
  fs.mkdirSync(runDir, { recursive: true });
  fs.writeFileSync(path.join(runDir, `${suite}.reuse-trace.json`), JSON.stringify(trace));
  return trace;
}
// check then record a passing run with a synthetic trace; returns the check result.
async function pass(root, suite, extra = {}) {
  const m = await lib();
  const runDir = runDirOf(root, extra.run || 'run1');
  const opts = { ...BASE, ...extra.opts };
  const c = m.checkSuites({ root, suites: [suite], runDir, ...opts });
  fs.writeFileSync(path.join(runDir, `${suite}.log`), `PASS ${suite}\n`);
  await writeTrace(root, suite, runDir, extra.trace);
  const r = m.recordSuite({ root, suite, runDir, metrics: PASS(suite), ...opts });
  assert.equal(r.recorded, true, `fixture record for ${suite}: ${JSON.stringify(r)}`);
  return c.results[0];
}
async function chk(root, suite, extra = {}) {
  const m = await lib();
  const out = m.checkSuites({ root, suites: [suite], runDir: runDirOf(root, 'run2'), ...BASE, ...extra });
  return out.off ? { off: out.off } : out.results[0];
}
const write = (root, rel, text) => { fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true }); fs.writeFileSync(path.join(root, rel), text); };

test('TEST-3166 an edit of a traced input gives reason=inputs naming the path; an edit of an untraced file reuses', async () => {
  const root = mkRepo();
  const first = await pass(root, 'fx', { trace: { inputs: { 'tests/skills/lib/data/a.txt': true } } });
  assert.equal(first.status, 'RUN');
  const hit = await chk(root, 'fx');
  assert.equal(hit.status, 'REUSE', 'unchanged identity reuses');
  write(root, 'tests/skills/fixtures/dir/one.txt', 'one changed (never read)\n');
  assert.equal((await chk(root, 'fx')).status, 'REUSE', 'a file the trace does not name');
  write(root, 'tests/skills/lib/data/a.txt', 'a changed\n');
  const edited = await chk(root, 'fx');
  assert.equal(edited.status, 'RUN');
  assert.equal(edited.reason, 'inputs');
  assert.equal(edited.detail, 'changed tests/skills/lib/data/a.txt');
});

// A one-suite repository whose suite `fk` has the given body and extra files.
function mkSuiteRepo(body, files = {}) {
  const map = `${MAP}${suiteRow('fk', ['tests/skills/test-fk.sh'])}`;
  const manifest = { version: 1, suites: { ...MANIFEST.suites, fk: MANIFEST.suites.fx } };
  return mkRepo({
    'tests/skills/suite-map.yaml': map,
    'tests/skills/suite-reuse.json': JSON.stringify(manifest),
    'tests/skills/test-fk.sh': `#!/usr/bin/env bash\n${body}\n`,
    ...files,
  });
}

test('TEST-3168 environment: AAI_ variable, excluded variable and referenced excluded variable', async () => {
  const root = mkRepo();
  await pass(root, 'fx');
  await pass(root, 'fz', { trace: { env_names: ['AAI_TEST_REF_ID'] } });
  const x = await chk(root, 'fx', { env: { ...ENV, AAI_FIXTURE_X: '2' } });
  assert.equal(x.reason, 'env');
  assert.equal((await chk(root, 'fx', { env: { ...ENV, AAI_TEST_REF_ID: 'b' } })).status, 'REUSE', 'heartbeat label is excluded');
  assert.equal((await chk(root, 'fz', { env: { ...ENV, AAI_TEST_REF_ID: 'b' } })).reason, 'env', 'excluded but named by a file the run read');
});

test('TEST-3169 a longer argument vector gives reason=args', async () => {
  const root = mkRepo();
  await pass(root, 'fx');
  const r = await chk(root, 'fx', { args: ['bash', 'tests/skills/test-fx.sh', '--extra'] });
  assert.equal(r.reason, 'args');
});

test('TEST-3170 another Node version or platform gives reason=runtime', async () => {
  const root = mkRepo();
  await pass(root, 'fx');
  assert.equal((await chk(root, 'fx', { runtime: { ...RT, node: 'v22.1.0' } })).reason, 'runtime');
  assert.equal((await chk(root, 'fx', { runtime: { ...RT, platform: 'win32' } })).reason, 'runtime');
});

test('TEST-3171 another seed list and another policy version each give reason=policy', async () => {
  const root = mkRepo();
  await pass(root, 'fx');
  assert.equal((await chk(root, 'fx', { seedPaths: 'docs/ai/STATE.yaml docs/ai/LOOP_TICKS.jsonl docs/ai/hitl-channel.json docs/ai/extra-seed.json' })).reason, 'policy');
  assert.equal((await chk(root, 'fx', { policyVersion: 3 })).reason, 'policy');
});

test('TEST-3174 invalid manifests give manifest-invalid for every suite', async () => {
  const bad = [
    { version: 2, suites: MANIFEST.suites },
    { version: 1, suites: { fx: { inputs: [], live: 'false', note: 'n' }, fy: MANIFEST.suites.fy } },
    { version: 1, suites: { fx: { inputs: [], live: false, note: '' }, fy: MANIFEST.suites.fy } },
  ];
  for (const manifest of bad) {
    const root = mkRepo({ 'tests/skills/suite-reuse.json': JSON.stringify(manifest) });
    for (const suite of ['fx', 'fy']) {
      const r = await chk(root, suite);
      assert.equal(r.status, 'RUN');
      assert.equal(r.reason, 'manifest-invalid', JSON.stringify(manifest));
    }
  }
});

test('TEST-3176 record refuses on each matching condition and writes no store file', async () => {
  const m = await lib();
  const store = (root) => path.join(root, 'tests', 'skills', 'results', 'reuse', 'fx.json');
  const cases = [
    ['not-pass', { ...PASS('fx'), status: 'FAIL', exit_code: 1 }, {}],
    ['not-attested', { ...PASS('fx'), tripwire_attested: false }, {}],
    ['not-attested', { ...PASS('fx'), tripwire_hasher_degraded: true }, {}],
    ['not-isolated', PASS('fx'), { isolation: 'degraded' }],
    ['not-isolated', PASS('fx'), { seeding: 'partial' }],
  ];
  for (const [reason, metrics, extra] of cases) {
    const root = mkRepo();
    const runDir = runDirOf(root);
    m.checkSuites({ root, suites: ['fx'], runDir, ...BASE });
    fs.writeFileSync(path.join(runDir, 'fx.log'), 'log\n');
    const r = m.recordSuite({ root, suite: 'fx', runDir, metrics, ...BASE, ...extra });
    assert.equal(r.recorded, false);
    assert.equal(r.reason, reason);
    assert.equal(fs.existsSync(store(root)), false, 'no store file');
  }
  const root = mkRepo();
  const runDir = runDirOf(root);
  m.checkSuites({ root, suites: ['fx'], runDir, ...BASE });
  fs.writeFileSync(path.join(runDir, 'fx.log'), 'log\n');
  await writeTrace(root, 'fx', runDir);
  write(root, '.gitignore', 'tests/skills/results/\nedited-mid-run\n');
  const r = m.recordSuite({ root, suite: 'fx', runDir, metrics: PASS('fx'), ...BASE });
  assert.equal(r.reason, 'inputs-changed-during-run');
  assert.equal(fs.existsSync(store(root)), false);
});

test('TEST-3176 concurrent records of one suite leave a whole store file and no temp residue; a stale orphan temp is reaped', async () => {
  const m = await lib();
  const root = mkRepo();
  const runDir = runDirOf(root);
  const env = { ...process.env };
  delete env.AAI_ROLE; delete env.AAI_SUITE_REUSE; delete env.CI; delete env.GITHUB_ACTIONS;
  const pre = spawnSync(process.execPath, [HELPER, 'check', '--root', root, '--run-dir', runDir, '--mode', 'selected', '--isolation', 'on', '--suite', 'fx'], { env, encoding: 'utf8' });
  assert.equal(pre.status, 0, pre.stderr);
  fs.writeFileSync(path.join(runDir, 'fx.log'), 'PASS fx\n');
  await writeTrace(root, 'fx', runDir);
  fs.writeFileSync(path.join(runDir, 'metrics.jsonl'), `${JSON.stringify(PASS('fx'))}\n`);
  const storeDir = path.join(root, 'tests', 'skills', 'results', 'reuse');
  fs.mkdirSync(storeDir, { recursive: true });
  const orphan = path.join(storeDir, 'fx.json.tmp.99999.0');
  fs.writeFileSync(orphan, '{"half":');
  const old = new Date(Date.now() - 3 * 3600 * 1000);
  fs.utimesSync(orphan, old, old);
  const args = [HELPER, 'record', '--root', root, '--run-dir', runDir, '--suite', 'fx', '--isolation', 'isolated', '--seeding', 'seeded'];
  const kids = Array.from({ length: 6 }, () => new Promise((resolve) => {
    const c = spawn(process.execPath, args, { env, stdio: ['ignore', 'pipe', 'pipe'] });
    let out = ''; let err = '';
    c.stdout.on('data', (d) => { out += d; }); c.stderr.on('data', (d) => { err += d; });
    c.on('close', (code) => resolve({ code, out, err }));
  }));
  for (const k of await Promise.all(kids)) {
    assert.equal(k.code, 0, `record exits 0: ${k.err}`);
    assert.match(k.out, /^RECORDED fx/, k.out);
  }
  const rec = JSON.parse(fs.readFileSync(path.join(storeDir, 'fx.json'), 'utf8'));
  assert.equal(rec.suite, 'fx');
  assert.deepEqual(fs.readdirSync(storeDir).filter((n) => n !== 'fx.json'), [], 'no temp residue, stale orphan reaped');
});

test('TEST-3176 a corrupt store file is a visible miss, never read as an empty record', async () => {
  const root = mkRepo();
  await pass(root, 'fx');
  const store = path.join(root, 'tests', 'skills', 'results', 'reuse', 'fx.json');
  fs.writeFileSync(store, '{"half":');
  const r = await chk(root, 'fx');
  assert.equal(r.status, 'RUN');
  assert.equal(r.reason, 'store-corrupt');
});

test('TEST-3178 off modes: ci, opt-out, full-sweep, isolation-off; record writes nothing in ci', async () => {
  const m = await lib();
  const root = mkRepo();
  await pass(root, 'fx');
  assert.equal((await chk(root, 'fx', { env: { ...ENV, GITHUB_ACTIONS: 'true' } })).off, 'ci');
  assert.equal((await chk(root, 'fx', { env: { ...ENV, CI: 'true' } })).off, 'ci');
  assert.equal((await chk(root, 'fx', { env: { ...ENV, CI: 'false' } })).status, 'REUSE', 'CI=false is not CI');
  assert.equal((await chk(root, 'fx', { env: { ...ENV, AAI_SUITE_REUSE: '0' } })).off, 'opt-out');
  assert.equal((await chk(root, 'fx', { mode: 'full' })).off, 'full-sweep');
  assert.equal((await chk(root, 'fx', { isolation: 'off' })).off, 'isolation-off');
  const fresh = mkRepo();
  const runDir = runDirOf(fresh);
  m.checkSuites({ root: fresh, suites: ['fx'], runDir, ...BASE });
  fs.writeFileSync(path.join(runDir, 'fx.log'), 'log\n');
  const r = m.recordSuite({ root: fresh, suite: 'fx', runDir, metrics: PASS('fx'), ...BASE, env: { ...ENV, GITHUB_ACTIONS: 'true' } });
  assert.equal(r.recorded, false);
  assert.equal(fs.existsSync(path.join(fresh, 'tests', 'skills', 'results', 'reuse')), false, 'ci writes no store');
});

test('TEST-3181 a deleted or altered cited log gives reason=log-missing', async () => {
  const a = mkRepo();
  await pass(a, 'fx');
  fs.rmSync(path.join(runDirOf(a), 'fx.log'));
  assert.equal((await chk(a, 'fx')).reason, 'log-missing');
  const b = mkRepo();
  await pass(b, 'fx');
  fs.appendFileSync(path.join(runDirOf(b), 'fx.log'), 'x');
  assert.equal((await chk(b, 'fx')).reason, 'log-missing');
});

test('TEST-3173 undeclared and live suites run (library rows of the framework case)', async () => {
  const root = mkRepo();
  await pass(root, 'fx');
  const unlisted = { version: 1, suites: { fy: MANIFEST.suites.fy } };
  write(root, 'tests/skills/suite-reuse.json', JSON.stringify(unlisted));
  assert.equal((await chk(root, 'fx')).reason, 'not-declared');
  write(root, 'tests/skills/suite-reuse.json', JSON.stringify({ version: 1, suites: { fx: { ...MANIFEST.suites.fx, live: true } } }));
  assert.equal((await chk(root, 'fx')).reason, 'live');
  write(root, 'tests/skills/suite-reuse.json', JSON.stringify({ version: 1, suites: MANIFEST.suites, extra: 1 }));
  assert.equal((await chk(root, 'fx')).reason, 'manifest-invalid');
});

test('TEST-3182 lint: live repository is clean with a qualified manifest; a ghost suite is named', async () => {
  const m = await lib();
  assert.equal(m.lintManifest({ root: REPO }).ok, true, 'live lint');
  const man = JSON.parse(fs.readFileSync(path.join(REPO, 'tests/skills/suite-reuse.json'), 'utf8'));
  const names = Object.keys(man.suites);
  assert.ok(names.length >= 5, `at least 5 suites, got ${names.length}`);
  for (const [n, e] of Object.entries(man.suites)) {
    assert.equal(e.live, false, n);
    assert.ok(typeof e.note === 'string' && e.note.trim() !== '', n);
  }
  const root = mkRepo({ 'tests/skills/suite-reuse.json': JSON.stringify({ version: 1, suites: { ...MANIFEST.suites, 'ghost-suite': MANIFEST.suites.fx } }) });
  const cli = spawnSync(process.execPath, [HELPER, 'lint', '--root', root], { encoding: 'utf8' });
  assert.equal(cli.status, 1);
  assert.match(cli.stdout, /ghost-suite not-in-suite-map/);
  const ok = spawnSync(process.execPath, [HELPER, 'lint', '--root', REPO], { encoding: 'utf8' });
  assert.equal(ok.status, 0, ok.stdout);
});

test('TEST-3182 lint: a manifest suite whose file the aai-suite-reuse row globs do not match is named', async () => {
  const map = `${MAP}${suiteRow('aai-suite-reuse', ['tests/skills/test-fy.sh', 'tests/skills/test-fz.sh', 'tests/skills/test-fh.sh'])}`;
  const root = mkRepo({ 'tests/skills/suite-map.yaml': map });
  const cli = spawnSync(process.execPath, [HELPER, 'lint', '--root', root], { encoding: 'utf8' });
  assert.equal(cli.status, 1, cli.stdout);
  assert.match(cli.stdout, /fx not-gate-selected/);
  assert.doesNotMatch(cli.stdout, /f[yzh] not-gate-selected/);
});

test('TEST-3182 lint: a manifest listing suites while the suite map has no aai-suite-reuse row is gate-row-missing', async () => {
  const root = mkRepo({});
  const cli = spawnSync(process.execPath, [HELPER, 'lint', '--root', root], { encoding: 'utf8' });
  assert.equal(cli.status, 1, cli.stdout);
  assert.match(cli.stdout, /gate-row-missing/);
  const withRow = mkRepo({ 'tests/skills/suite-map.yaml': `${MAP}${suiteRow('aai-suite-reuse', ['tests/skills/test-fx.sh'])}` });
  const ok = spawnSync(process.execPath, [HELPER, 'lint', '--root', withRow], { encoding: 'utf8' });
  assert.doesNotMatch(ok.stdout, /gate-row-missing/);
});

test('TEST-3183 select-suites.mjs imports silently and exports the map parser', async () => {
  const child = spawnSync(process.execPath, ['--input-type=module', '-e',
    `import * as s from ${JSON.stringify(pathToFileURL(SELECTOR).href)};`
    + 'if (typeof s.parseSuiteMap !== "function" || typeof s.matchesGlob !== "function") { process.stderr.write("exports missing"); process.exitCode = 3; }'],
  { encoding: 'utf8' });
  assert.equal(child.stdout, '');
  assert.equal(child.stderr, '');
  assert.equal(child.status, 0);
  const sel = await import(pathToFileURL(SELECTOR).href);
  assert.ok(sel.parseSuiteMap(fs.readFileSync(path.join(REPO, 'tests/skills/suite-map.yaml'), 'utf8')).suites['aai-ride-status'].globs.length > 0);
});

const HAZARDS = { BASH_ENV: '/nonexistent/hook.sh', ENV: '/nonexistent/hook.sh', 'BASH_FUNC_x%%': '() { echo hi; }', SHELLOPTS: 'xtrace', BASHOPTS: 'extglob' };

test('TEST-3195 a bash startup hook at check time gives RUN reason=bash-startup-hook; at record time nothing is stored and a stale record is forgotten', async () => {
  const m = await lib();
  for (const [name, val] of Object.entries(HAZARDS)) {
    const root = mkRepo();
    await pass(root, 'fx');
    const r = await chk(root, 'fx', { env: { ...ENV, [name]: val } });
    assert.equal(r.status, 'RUN', name);
    assert.equal(r.reason, 'bash-startup-hook', name);
    assert.equal((await chk(root, 'fx', { env: { ...ENV, [name]: '' } })).status, 'REUSE', `${name}: an empty value is no hook`);
    // record time: a pass made under the hook is never stored, and drops the clean record
    const runDir = runDirOf(root, 'run3');
    const opts = { ...BASE, env: { ...ENV, [name]: val } };
    m.checkSuites({ root, suites: ['fx'], runDir, ...BASE });
    fs.writeFileSync(path.join(runDir, 'fx.log'), 'PASS fx\n');
    const rec = m.recordSuite({ root, suite: 'fx', runDir, metrics: PASS('fx'), ...opts });
    assert.equal(rec.recorded, false, name);
    assert.equal(rec.reason, 'bash-startup-hook', name);
    const after = await chk(root, 'fx');
    assert.equal(after.status, 'RUN', `${name}: stale record must not survive`);
    assert.equal(after.reason, 'no-record', name);
  }
  // a fresh record made with the hook set, then checked with it unset, is not reused
  const root = mkRepo();
  const runDir = runDirOf(root);
  m.checkSuites({ root, suites: ['fx'], runDir, ...BASE });
  fs.writeFileSync(path.join(runDir, 'fx.log'), 'PASS fx\n');
  m.recordSuite({ root, suite: 'fx', runDir, metrics: PASS('fx'), ...BASE, env: { ...ENV, BASH_ENV: '/nonexistent/hook.sh' } });
  const r = await chk(root, 'fx');
  assert.equal(r.status, 'RUN');
  assert.equal(r.reason, 'no-record');
});

test('TEST-3196 record with a missing or unreadable identity file is a clean no-record, never a throw', async () => {
  const m = await lib();
  for (const body of [null, 'not json', 'null', '{}', '{"args":"x"}']) {
    const root = mkRepo();
    const runDir = runDirOf(root);
    fs.mkdirSync(runDir, { recursive: true });
    fs.writeFileSync(path.join(runDir, 'fx.log'), 'log\n');
    if (body !== null) fs.writeFileSync(path.join(runDir, 'fx.reuse-identity.json'), body);
    const r = m.recordSuite({ root, suite: 'fx', runDir, metrics: PASS('fx'), ...BASE });
    assert.equal(r.recorded, false);
    assert.equal(r.reason, 'no-identity');
  }
});

// ---- spec-reuse-for-docs-reading-suites ----

async function traceLib() {
  let mod = null;
  try { mod = await import(pathToFileURL(TRACE_MODULE).href); } catch { /* asserted below */ }
  assert.ok(mod, `module ${TRACE_MODULE} exists and loads`);
  return mod;
}
function scratchCheckout(files) {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'checkout-trace-'));
  roots.push(base);
  const dir = path.join(base, 'wt');
  fs.mkdirSync(dir);
  git(dir, 'init', '-q', '-b', 'main');
  for (const [rel, text] of Object.entries(files)) write(dir, rel, text);
  git(dir, 'add', '-A');
  git(dir, 'commit', '-q', '-m', 'fixture');
  return { base, dir, runDir: path.join(base, 'run') };
}

test('TEST-3261 armTrace then collectTrace: a renamed-in file is an input, a listing is not, rev-parse reads git without the index, status reads both', async () => {
  const t = await traceLib();
  const { dir, runDir } = scratchCheckout({ 'a.txt': 'a\n', 'b.txt': 'b\n', 'sub/c.txt': 'c\n', 'u.txt': 'u\n' });
  const arm = t.armTrace({ dir, runDir, suite: 'fx' });
  assert.equal(arm.canary, true);
  fs.writeFileSync(path.join(dir, 'new.tmp'), 'replacement\n');
  fs.renameSync(path.join(dir, 'new.tmp'), path.join(dir, 'b.txt'));
  fs.utimesSync(path.join(dir, 'b.txt'), t.ATIME_FLOOR, fs.statSync(path.join(dir, 'b.txt')).mtime); // a replacement nobody read: only the new inode gives it away
  fs.readdirSync(path.join(dir, 'sub'));
  fs.readFileSync(path.join(dir, 'a.txt'));
  const tr = t.collectTrace({ dir, runDir, suite: 'fx' });
  assert.deepEqual(Object.keys(tr.inputs).filter((p) => !p.startsWith('.git/')).sort(), ['a.txt', 'b.txt'], 'read and replaced files only');
  assert.equal(tr.git_read, false);
  assert.equal(tr.index_read, false);
  assert.equal(JSON.parse(fs.readFileSync(path.join(runDir, 'fx.reuse-trace.json'), 'utf8')).suite, 'fx');

  const g = scratchCheckout({ 'a.txt': 'a\n' });
  t.armTrace({ dir: g.dir, runDir: g.runDir, suite: 'fx' });
  git(g.dir, 'rev-parse', 'HEAD');
  const rp = t.collectTrace({ dir: g.dir, runDir: g.runDir, suite: 'fx' });
  assert.equal(rp.git_read, true, 'rev-parse reads the git directory');
  assert.equal(rp.index_read, false, 'rev-parse does not read the index');

  const h = scratchCheckout({ 'a.txt': 'a\n' });
  t.armTrace({ dir: h.dir, runDir: h.runDir, suite: 'fx' });
  git(h.dir, 'status', '--porcelain');
  const st = t.collectTrace({ dir: h.dir, runDir: h.runDir, suite: 'fx' });
  assert.equal(st.git_read, true);
  assert.equal(st.index_read, true, 'status reads the index');
});

test('TEST-3262 a traced input edit gives RUN reason=inputs naming it; an edit of a file in the path list the trace does not name reuses', async () => {
  const mk = () => mkRepo({ 'docs/x.md': 'x\n', 'docs/y.md': 'y\n' });
  const a = mk();
  await pass(a, 'fx', { trace: { inputs: { 'docs/x.md': true } } });
  assert.equal((await chk(a, 'fx')).status, 'REUSE');
  write(a, 'docs/x.md', 'x edited\n');
  const r = await chk(a, 'fx');
  assert.equal(r.reason, 'inputs');
  assert.equal(r.detail, 'changed docs/x.md');
  const b = mk();
  await pass(b, 'fx', { trace: { inputs: { 'docs/x.md': true } } });
  write(b, 'docs/y.md', 'y edited\n');
  assert.equal((await chk(b, 'fx')).status, 'REUSE');
  // the executable bit is part of an input's identity: chmod -x on a traced input is a change, on an untraced file it is not
  if (process.platform !== 'win32') {
    const c = mk();
    write(c, 'docs/x.md', 'x\n');
    fs.chmodSync(path.join(c, 'docs/x.md'), 0o755);
    await pass(c, 'fx', { trace: { inputs: { 'docs/x.md': true } } });
    assert.equal((await chk(c, 'fx')).status, 'REUSE');
    fs.chmodSync(path.join(c, 'docs/x.md'), 0o644);
    const m = await chk(c, 'fx');
    assert.equal(m.reason, 'inputs');
    assert.equal(m.detail, 'changed docs/x.md');
    fs.chmodSync(path.join(c, 'docs/y.md'), 0o755);
    assert.equal((await chk(c, 'fx')).reason, 'inputs', 'still the x.md change');
  }
});

test('TEST-3263 an untracked file no trace names gives reason=paths added it; a removed untraced tracked file gives reason=paths removed', async () => {
  const a = mkRepo({ 'docs/y.md': 'y\n' });
  await pass(a, 'fx');
  write(a, 'docs/new-untracked.md', 'n\n');
  const added = await chk(a, 'fx');
  assert.equal(added.reason, 'paths');
  assert.equal(added.detail, 'added docs/new-untracked.md');
  const b = mkRepo({ 'docs/y.md': 'y\n' });
  await pass(b, 'fx');
  git(b, 'rm', '-q', 'docs/y.md');
  const gone = await chk(b, 'fx');
  assert.equal(gone.reason, 'paths');
  assert.equal(gone.detail, 'removed docs/y.md');
});

test('TEST-3264 a moved HEAD gives reason=history only when the trace read the git directory', async () => {
  const root = mkRepo();
  // fh's source mentions git rev-parse and fy's does not: only the trace decides.
  await pass(root, 'fy', { trace: { git_read: true } });
  await pass(root, 'fh', { trace: { git_read: false } });
  assert.equal((await chk(root, 'fy')).status, 'REUSE', 'unchanged history reuses');
  git(root, 'commit', '-q', '--allow-empty', '-m', 'move head');
  assert.equal((await chk(root, 'fy')).reason, 'history');
  assert.equal((await chk(root, 'fh')).status, 'REUSE');
});

test('TEST-3265 with index_read every tracked file is an input; without it an unnamed tracked file is not', async () => {
  const mk = () => mkRepo({ 'docs/y.md': 'y\n' });
  const a = mk();
  await pass(a, 'fx', { trace: { index_read: true, git_read: true } });
  write(a, 'docs/y.md', 'y edited\n');
  const r = await chk(a, 'fx');
  assert.equal(r.reason, 'inputs');
  assert.equal(r.detail, 'changed docs/y.md');
  const b = mk();
  await pass(b, 'fx', { trace: { index_read: false } });
  write(b, 'docs/y.md', 'y edited\n');
  assert.equal((await chk(b, 'fx')).status, 'REUSE');
});

test('TEST-3266 a variable named only in a file the run read moves the env component; an unreferenced one does not', async () => {
  const env = { ...ENV, FIXTURE_Q: '1', FIXTURE_Z: '1' };
  const root = mkRepo({ 'tests/skills/lib/q.mjs': 'export const q = process.env.FIXTURE_Q;\n' });
  await pass(root, 'fx', { opts: { env }, trace: { inputs: { 'tests/skills/lib/q.mjs': true } } });
  assert.equal((await chk(root, 'fx', { env })).status, 'REUSE');
  assert.equal((await chk(root, 'fx', { env: { ...env, FIXTURE_Z: '2' } })).status, 'REUSE', 'FIXTURE_Z is named nowhere');
  assert.equal((await chk(root, 'fx', { env: { ...env, FIXTURE_Q: '2' } })).reason, 'env');
  const t = await traceLib();
  assert.deepEqual(t.referencedNames(['$env:PS_A ${env:PS_B} $SH_C ${SH_D} process.env.JS_E $Env:PS_F $ENV:PS_G ${Env:PS_H}']), ['JS_E', 'PS_A', 'PS_B', 'PS_F', 'PS_G', 'PS_H', 'SH_C', 'SH_D'], 'PowerShell env references are read by the variable name');
});

test('TEST-3268 record refuses without a usable trace and when the run moved the identity, never throws, writes nothing', async () => {
  const m = await lib();
  const store = (root) => path.join(root, 'tests', 'skills', 'results', 'reuse', 'fx.json');
  const attempt = async (prep) => {
    const root = mkRepo();
    const runDir = runDirOf(root);
    m.checkSuites({ root, suite: 'fx', suites: ['fx'], runDir, ...BASE });
    fs.writeFileSync(path.join(runDir, 'fx.log'), 'log\n');
    await prep(root, runDir);
    const r = m.recordSuite({ root, suite: 'fx', runDir, metrics: PASS('fx'), ...BASE });
    assert.equal(r.recorded, false);
    assert.equal(fs.existsSync(store(root)), false, 'no store file');
    return r.reason;
  };
  assert.equal(await attempt(() => {}), 'no-trace', 'missing trace');
  assert.equal(await attempt((root, runDir) => fs.writeFileSync(path.join(runDir, 'fx.reuse-trace.json'), '{"half":')), 'no-trace', 'unparseable');
  assert.equal(await attempt((root, runDir) => writeTrace(root, 'fx', runDir, { suite: 'fy' })), 'no-trace', 'another suite');
  assert.equal(await attempt((root, runDir) => writeTrace(root, 'fx', runDir, { canary: false })), 'trace-unavailable');
  assert.equal(await attempt(async (root, runDir) => { await writeTrace(root, 'fx', runDir); git(root, 'commit', '-q', '--allow-empty', '-m', 'moved during the run'); }), 'inputs-changed-during-run');
});

test('TEST-3269 armTrace with an access-time probe that reports no advance gives canary false; the CLI arm on a normal checkout gives canary true', async () => {
  const t = await traceLib();
  const a = scratchCheckout({ 'a.txt': 'a\n' });
  assert.equal(t.armTrace({ dir: a.dir, runDir: a.runDir, suite: 'fx', atimeProbe: () => false }).canary, false);
  const b = scratchCheckout({ 'a.txt': 'a\n' });
  const cli = spawnSync(process.execPath, [HELPER, 'arm', '--root', REPO, '--dir', b.dir, '--run-dir', b.runDir, '--suite', 'fx'], { encoding: 'utf8' });
  assert.equal(cli.status, 0, cli.stderr);
  assert.match(cli.stdout, /ARMED fx canary=true/);
  const armed = JSON.parse(fs.readFileSync(path.join(b.runDir, 'fx.reuse-arm.json'), 'utf8'));
  assert.equal(armed.canary, true);
  const refuse = spawnSync(process.execPath, [HELPER, 'arm', '--root', REPO, '--dir', REPO, '--run-dir', b.runDir, '--suite', 'fx'], { encoding: 'utf8' });
  assert.equal(refuse.status, 2, 'arm refuses to touch the root checkout');
  // containment either way is refused, a sibling is not; a refused call leaves a real-tree sentinel's times alone
  const sentinel = path.join(REPO, 'package.json');
  const sentinelPath = fs.existsSync(sentinel) ? sentinel : path.join(REPO, 'CLAUDE.md');
  const before = fs.lstatSync(sentinelPath);
  const armAt = (cmd, dir) => spawnSync(process.execPath, [HELPER, cmd, '--root', REPO, '--dir', dir, '--run-dir', b.runDir, '--suite', 'fx'], { encoding: 'utf8', cwd: REPO });
  for (const cmd of ['arm', 'collect']) {
    assert.equal(armAt(cmd, path.dirname(REPO)).status, 2, `${cmd} refuses a parent of the root`);
    assert.equal(armAt(cmd, path.join(REPO, 'tests')).status, 2, `${cmd} refuses a child of the root`);
  }
  const after = fs.lstatSync(sentinelPath);
  assert.equal(after.atimeMs, before.atimeMs, 'refused calls left the sentinel access time');
  assert.equal(after.mtimeMs, before.mtimeMs, 'refused calls left the sentinel mtime');
  const sib = scratchCheckout({ 'a.txt': 'a\n' });
  assert.equal(armAt('arm', sib.dir).status, 0, 'a sibling temp dir is still armed');
  // a case variant of the root names the same directory on a case-insensitive volume; the guard must still refuse it
  const tmp = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'reuse-case-')));
  roots.push(tmp);
  const cRoot = path.join(tmp, 'repo');
  fs.mkdirSync(cRoot);
  git(cRoot, 'init', '-q');
  const cSentinel = path.join(cRoot, 'sentinel.txt');
  fs.writeFileSync(cSentinel, 's\n');
  if (!fs.existsSync(path.join(tmp, 'REPO'))) {
    console.log('TEST-3269 case-variant assertion skipped: the temp volume is case-sensitive');
  } else {
    const cBefore = fs.lstatSync(cSentinel);
    for (const cmd of ['arm', 'collect']) {
      const r = spawnSync(process.execPath, [HELPER, cmd, '--root', cRoot, '--dir', path.join(tmp, 'REPO'), '--run-dir', b.runDir, '--suite', 'fx'], { encoding: 'utf8', cwd: tmp });
      assert.equal(r.status, 2, `${cmd} refuses a case variant of the root`);
    }
    const cAfter = fs.lstatSync(cSentinel);
    assert.equal(cAfter.atimeMs, cBefore.atimeMs, 'case-variant refusal left the sentinel access time');
    assert.equal(cAfter.mtimeMs, cBefore.mtimeMs, 'case-variant refusal left the sentinel mtime');
  }
});

// ---- spec-reuse-local-ledger-append (TEST-3301, TEST-3302) ----
const LEDGER = 'docs/ai/tests/test-runs.jsonl';
const ledgerRepo = () => mkRepo({ [LEDGER]: '{"a":1}\n{"b":2}\n', 'docs/ai/EVENTS.jsonl': '{"e":1}\n', 'docs/x.md': 'x\n' });
const copyRepo = (src) => {
  const dst = fs.mkdtempSync(path.join(os.tmpdir(), 'suite-reuse-copy-'));
  roots.push(dst);
  fs.cpSync(src, dst, { recursive: true });
  return dst;
};

test('TEST-3301 an index-reading record tolerates a ledger append alone and misses on every other change', async () => {
  const base = ledgerRepo();
  await pass(base, 'fx', { trace: { index_read: true, git_read: true } });
  const cases = [
    ['append alone', (r) => fs.appendFileSync(path.join(r, LEDGER), '{"c":3}\n'), 'REUSE', null],
    ['append twice', (r) => { fs.appendFileSync(path.join(r, LEDGER), '{"c":3}\n'); fs.appendFileSync(path.join(r, LEDGER), '{"d":4}\n'); }, 'REUSE', null],
    ['equal-length edit', (r) => write(r, LEDGER, '{"a":9}\n{"b":2}\n'), 'RUN', `changed ${LEDGER}`],
    ['truncation', (r) => write(r, LEDGER, '{"a":1}\n'), 'RUN', `changed ${LEDGER}`],
    ['executable bit', (r) => fs.chmodSync(path.join(r, LEDGER), 0o755), 'RUN', `changed ${LEDGER}`],
    ['EVENTS append', (r) => fs.appendFileSync(path.join(r, 'docs/ai/EVENTS.jsonl'), '{"e":2}\n'), 'RUN', 'changed docs/ai/EVENTS.jsonl'],
    ['append plus other edit', (r) => { fs.appendFileSync(path.join(r, LEDGER), '{"c":3}\n'); write(r, 'docs/x.md', 'x edited\n'); }, 'RUN', 'changed docs/x.md'],
  ];
  for (const [name, mutate, status, detail] of cases) {
    const r = copyRepo(base);
    mutate(r);
    const got = await chk(r, 'fx');
    assert.equal(got.status, status, `${name}: ${JSON.stringify(got)}`);
    if (detail) { assert.equal(got.reason, 'inputs', name); assert.equal(got.detail, detail, name); }
  }
});

test('TEST-3302 the tolerance needs an index-reading record that carries append_prefix', async () => {
  const appendThenCheck = async (root) => { fs.appendFileSync(path.join(root, LEDGER), '{"c":3}\n'); return chk(root, 'fx'); };
  const storeOf = (root) => path.join(root, 'tests', 'skills', 'results', 'reuse', 'fx.json');
  // no index read: the ledger is a named input and the hand-written prefix is ignored
  const a = ledgerRepo();
  await pass(a, 'fx', { trace: { index_read: false, inputs: { [LEDGER]: true } } });
  const rec = JSON.parse(fs.readFileSync(storeOf(a), 'utf8'));
  rec.append_prefix = { [LEDGER]: { bytes: fs.statSync(path.join(a, LEDGER)).size, sha256: rec.inputs_map[LEDGER] } };
  fs.writeFileSync(storeOf(a), JSON.stringify(rec));
  const ra = await appendThenCheck(a);
  assert.equal(ra.status, 'RUN');
  assert.equal(ra.reason, 'inputs');
  assert.equal(ra.detail, `changed ${LEDGER}`);
  // index read but the record has no append_prefix
  const b = ledgerRepo();
  await pass(b, 'fx', { trace: { index_read: true, git_read: true } });
  const recB = JSON.parse(fs.readFileSync(storeOf(b), 'utf8'));
  delete recB.append_prefix;
  fs.writeFileSync(storeOf(b), JSON.stringify(recB));
  const rb = await appendThenCheck(b);
  assert.equal(rb.status, 'RUN');
  assert.equal(rb.detail, `changed ${LEDGER}`);
});
