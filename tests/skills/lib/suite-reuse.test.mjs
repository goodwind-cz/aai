// suite-reuse.test.mjs - node:test cases of spec-precise-suite-evidence-reuse
// (library rows of Spec-AC-02, -03, -04, -05, -06, -07, -08, -09).
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
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..', '..');
const HELPER = process.env.SUITE_REUSE_SCRIPT || path.join(REPO, '.aai', 'scripts', 'suite-reuse.mjs');
const SELECTOR = path.join(REPO, '.aai', 'scripts', 'select-suites.mjs');

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

// check then record a passing run; returns the check result.
async function pass(root, suite, extra = {}) {
  const m = await lib();
  const runDir = runDirOf(root, extra.run || 'run1');
  const opts = { ...BASE, ...extra.opts };
  const c = m.checkSuites({ root, suites: [suite], runDir, ...opts });
  fs.writeFileSync(path.join(runDir, `${suite}.log`), `PASS ${suite}\n`);
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

test('TEST-3166 tracked edit and untracked declared file each give reason=inputs', async () => {
  const root = mkRepo();
  const first = await pass(root, 'fx');
  assert.equal(first.status, 'RUN');
  const hit = await chk(root, 'fx');
  assert.equal(hit.status, 'REUSE', 'unchanged identity reuses');
  write(root, 'tests/skills/lib/data/a.txt', 'a changed\n');
  const edited = await chk(root, 'fx');
  assert.equal(edited.status, 'RUN');
  assert.equal(edited.reason, 'inputs');
  assert.equal(edited.detail, 'changed tests/skills/lib/data/a.txt');
  const root2 = mkRepo();
  await pass(root2, 'fx');
  write(root2, 'tests/skills/lib/data/b.txt', 'new untracked\n');
  const added = await chk(root2, 'fx');
  assert.equal(added.reason, 'inputs');
  assert.equal(added.detail, 'added tests/skills/lib/data/b.txt');
});

test('TEST-3167 closure-only module, directory literal and seed file change the identity only where the closure covers them', async () => {
  const a = mkRepo();
  await pass(a, 'fx');
  write(a, 'tests/skills/lib/util.mjs', 'export const u = 2;\n');
  const imported = await chk(a, 'fx');
  assert.equal(imported.reason, 'inputs');
  assert.equal(imported.detail, 'changed tests/skills/lib/util.mjs', 'a module reached only by an import matches no glob');
  const b = mkRepo();
  await pass(b, 'fx');
  write(b, 'tests/skills/fixtures/dir/two.txt', 'two\n');
  const dir = await chk(b, 'fx');
  assert.equal(dir.reason, 'inputs');
  assert.equal(dir.detail, 'added tests/skills/fixtures/dir/two.txt', 'a file appearing under a literal directory');
  const c = mkRepo();
  await pass(c, 'fx');
  await pass(c, 'fy');
  write(c, 'docs/ai/STATE.yaml', 'state: 2\n');
  const seeded = await chk(c, 'fx');
  assert.equal(seeded.reason, 'inputs');
  assert.equal(seeded.detail, 'changed docs/ai/STATE.yaml', 'seed file named by the closure');
  assert.equal((await chk(c, 'fy')).status, 'REUSE', 'seed file the closure does not name');
});

test('TEST-3168 environment: AAI_ variable, excluded variable and referenced excluded variable', async () => {
  const root = mkRepo();
  await pass(root, 'fx');
  await pass(root, 'fz');
  const x = await chk(root, 'fx', { env: { ...ENV, AAI_FIXTURE_X: '2' } });
  assert.equal(x.reason, 'env');
  assert.equal((await chk(root, 'fx', { env: { ...ENV, AAI_TEST_REF_ID: 'b' } })).status, 'REUSE', 'heartbeat label is excluded');
  assert.equal((await chk(root, 'fz', { env: { ...ENV, AAI_TEST_REF_ID: 'b' } })).reason, 'env', 'excluded but referenced by the closure');
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
  assert.equal((await chk(root, 'fx', { policyVersion: 2 })).reason, 'policy');
});

test('TEST-3172 a moved HEAD gives reason=history only for a suite with a history marker', async () => {
  const root = mkRepo();
  await pass(root, 'fh');
  await pass(root, 'fy');
  git(root, 'commit', '-q', '--allow-empty', '-m', 'move head');
  assert.equal((await chk(root, 'fh')).reason, 'history');
  assert.equal((await chk(root, 'fy')).status, 'REUSE');
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
  write(root, 'tests/skills/lib/data/a.txt', 'edited mid-run\n');
  const r = m.recordSuite({ root, suite: 'fx', runDir, metrics: PASS('fx'), ...BASE });
  assert.equal(r.reason, 'inputs-changed-during-run');
  assert.equal(fs.existsSync(store(root)), false);
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

test('TEST-3193 every live manifest suite reads nothing inside the checkout outside its identity', async () => {
  const m = await lib();
  const man = JSON.parse(fs.readFileSync(path.join(REPO, 'tests/skills/suite-reuse.json'), 'utf8'));
  const tracer = path.join(HERE, 'read-trace.cjs');
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'suite-reuse-trace-'));
  roots.push(scratch);
  const env = { ...process.env, NODE_OPTIONS: `--require ${tracer}` };
  delete env.AAI_ROLE;
  delete env.AAI_SUITE_REUSE;
  for (const suite of Object.keys(man.suites)) {
    const out = path.join(scratch, `${suite}.trace`);
    fs.writeFileSync(out, '');
    const run = spawnSync('bash', [path.join(REPO, 'tests', 'skills', `test-${suite}.sh`)], { cwd: REPO, env: { ...env, AAI_TRACE_OUT: out }, encoding: 'utf8' });
    assert.equal(run.status, 0, `${suite} must pass under the tracer: ${(run.stdout || '').slice(-400)}${run.stderr || ''}`);
    const inputs = new Set(Object.keys(m.explainSuite({ root: REPO, suite }).id.inputs_map));
    const outside = new Set();
    for (const line of fs.readFileSync(out, 'utf8').split('\n').filter(Boolean)) {
      const [kind, p] = line.split('\t');
      if (kind !== 'R' || !p) continue;
      const abs = path.resolve(REPO, p);
      if (!abs.startsWith(REPO + path.sep)) continue;
      const rel = abs.slice(REPO.length + 1).split(path.sep).join('/');
      if (rel.startsWith('tests/skills/results/') || rel.startsWith('node_modules/') || inputs.has(rel)) continue;
      outside.add(rel);
    }
    assert.deepEqual([...outside].sort().slice(0, 20), [], `${suite} reads files its identity does not cover`);
  }
});

test('TEST-3183 select-suites.mjs imports silently and its map parser feeds the helper', async () => {
  const child = spawnSync(process.execPath, ['--input-type=module', '-e',
    `import * as s from ${JSON.stringify(pathToFileURL(SELECTOR).href)};`
    + 'if (typeof s.parseSuiteMap !== "function" || typeof s.matchesGlob !== "function") { process.stderr.write("exports missing"); process.exitCode = 3; }'],
  { encoding: 'utf8' });
  assert.equal(child.stdout, '');
  assert.equal(child.stderr, '');
  assert.equal(child.status, 0);
  const m = await lib();
  const sel = await import(pathToFileURL(SELECTOR).href);
  const want = sel.parseSuiteMap(fs.readFileSync(path.join(REPO, 'tests/skills/suite-map.yaml'), 'utf8')).suites['aai-ride-status'].globs;
  assert.deepEqual(m.declaredGlobs({ root: REPO, suite: 'aai-ride-status' }), want);
});
