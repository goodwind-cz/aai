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
import { spawn, spawnSync } from 'node:child_process';
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

test('TEST-3167 a top-level directory literal without a trailing slash widens the identity to that directory', async () => {
  const forms = {
    'quoted variable': 'D="$ROOT/docs"\ncat "$D/probe.txt"',
    'dot-aai variable': 'D="$ROOT/.aai"\ncat "$D/probe.txt"',
    'plain tests variable': 'D=$ROOT/tests\ncat "$D/probe.txt"',
    'quoted literal': 'cd "tests"',
  };
  for (const [form, body] of Object.entries(forms)) {
    const dir = body.includes('.aai') ? '.aai' : body.includes('tests') ? 'tests' : 'docs';
    const files = { [`${dir}/probe.txt`]: 'one\n' };
    const a = mkSuiteRepo(body, files);
    await pass(a, 'fk');
    assert.equal((await chk(a, 'fk')).status, 'REUSE', form);
    write(a, `${dir}/probe.txt`, 'two\n');
    const edited = await chk(a, 'fk');
    assert.equal(edited.status, 'RUN', `${form}: edit under ${dir}`);
    assert.equal(edited.reason, 'inputs');
    const b = mkSuiteRepo(body, files);
    await pass(b, 'fk');
    write(b, `${dir}/new.txt`, 'added\n');
    assert.equal((await chk(b, 'fk')).status, 'RUN', `${form}: add under ${dir}`);
  }
  const prose = mkSuiteRepo('echo see docs and tests for details', { 'docs/probe.txt': 'one\n' });
  await pass(prose, 'fk');
  write(prose, 'docs/probe.txt', 'two\n');
  assert.equal((await chk(prose, 'fk')).status, 'REUSE', 'plain prose naming docs is not a directory literal');
});

test('TEST-3167 a partly built path widens to its deepest fully literal directory', async () => {
  const forms = {
    'prefix then variable': ['for n in a b; do bash ".aai/scripts/aai-${n}.mjs"; done', '.aai/scripts/aai-zed.mjs'],
    'prefix then bare variable': ['cat tests/skills/fix-$X.json', 'tests/skills/fix-other.json'],
    'prefix then star': ['cat tests/skills/fixtures/part-*.txt', 'tests/skills/fixtures/part-z.txt'],
    'variable as a whole segment': ['cat tests/skills/fixtures/${n}/x.txt', 'tests/skills/fixtures/q/x.txt'],
    'literal ending in a dot then variable': ['ext=md; cat "$ROOT/docs/specs/SPEC-0001.${ext}"', 'docs/specs/SPEC-0001.md'],
    'literal ending in a dot then star': ['cat tests/skills/fixtures/part.*', 'tests/skills/fixtures/part.txt'],
    'brace pair after a dot': ['bash .aai/scripts/install-hook.{sh,ps1}', '.aai/scripts/install-hook.sh'],
  };
  for (const [form, [body, touched]] of Object.entries(forms)) {
    const a = mkSuiteRepo(body, { 'tests/skills/fixtures/keep.txt': 'k\n', '.aai/scripts/keep.mjs': 'x\n' });
    await pass(a, 'fk');
    assert.equal((await chk(a, 'fk')).status, 'REUSE', form);
    write(a, touched, 'new\n');
    const r = await chk(a, 'fk');
    assert.equal(r.status, 'RUN', `${form}: ${touched} added`);
    assert.equal(r.reason, 'inputs');
  }
});

test('TEST-3167 a path literal is normalized: dot segments collapse, a directory without a slash widens, an escape is unresolvable', async () => {
  const files = { 'docs/specs/a.md': 'a\n', 'docs/keep.txt': 'k\n' };
  const widen = {
    'dotdot then variable': ['f=a.md; cat "$ROOT/tests/../docs/specs/${f}"', 'docs/specs/new.md'],
    'dot segment directory then star': ['for f in "$ROOT/docs/./specs/"*.md; do cat "$f"; done', 'docs/specs/new.md'],
    'directory without a slash': ['ls docs/specs', 'docs/specs/new.md'],
    'dotdot directory without a slash': ['ls tests/skills/../../docs', 'docs/new.md'],
    'trailing dotdot widens to the parent': ['ls docs/specs/..', 'docs/new2.md'],
    'trailing dotdot under tests widens to tests': ['ls tests/skills/..', 'tests/other/new.txt'],
    'sentence-ending dot still names the file': ['cat docs/specs/a.md.', 'docs/specs/a.md'],
  };
  for (const [form, [body, touched]] of Object.entries(widen)) {
    const a = mkSuiteRepo(body, files);
    await pass(a, 'fk');
    assert.equal((await chk(a, 'fk')).status, 'REUSE', form);
    write(a, touched, 'n\n');
    const r = await chk(a, 'fk');
    assert.equal(r.status, 'RUN', `${form}: ${touched} added`);
    assert.equal(r.reason, 'inputs', form);
  }
  for (const [form, body] of Object.entries({
    'escapes the repository': 'cat docs/../../outside/x.txt',
    'climbs above the root': 'cat tests/../../outside',
    'collapses to the root': 'cat docs/../',
    'trailing dotdot collapses to the root': 'ls docs/..',
    'trailing dotdot under tests collapses to the root': 'ls tests/..',
  })) {
    const root = mkSuiteRepo(body, files);
    const r = await chk(root, 'fk');
    assert.equal(r.status, 'RUN', form);
    assert.equal(r.reason, 'inputs-unresolvable', form);
  }
});

test('TEST-3167 a file-relative reference outside lib/ is resolved against its directory, else the suite is not reusable', async () => {
  const known = '#!/usr/bin/env bash\nSCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nPROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"\ncat "$SCRIPT_DIR/fixtures/rel/x.txt"\ncat "$(dirname "${BASH_SOURCE[0]}")/fixtures/rel2/y.txt"';
  const a = mkSuiteRepo(known.split('\n').slice(1).join('\n'), { 'tests/skills/fixtures/rel/x.txt': 'x\n', 'tests/skills/fixtures/rel2/y.txt': 'y\n' });
  await pass(a, 'fk');
  assert.equal((await chk(a, 'fk')).status, 'REUSE');
  write(a, 'tests/skills/fixtures/rel/x.txt', 'changed\n');
  assert.equal((await chk(a, 'fk')).status, 'RUN', 'edit of a SCRIPT_DIR-relative read');
  const b = mkSuiteRepo(known.split('\n').slice(1).join('\n'), { 'tests/skills/fixtures/rel/x.txt': 'x\n', 'tests/skills/fixtures/rel2/y.txt': 'y\n' });
  await pass(b, 'fk');
  write(b, 'tests/skills/fixtures/rel2/y.txt', 'changed\n');
  assert.equal((await chk(b, 'fk')).status, 'RUN', 'edit of a dirname-relative read');
  const part = mkSuiteRepo('SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\ncat "$SCRIPT_DIR/fixtures/pre-$X.txt"', { 'tests/skills/fixtures/keep.txt': 'k\n' });
  await pass(part, 'fk');
  write(part, 'tests/skills/fixtures/pre-new.txt', 'n\n');
  assert.equal((await chk(part, 'fk')).status, 'RUN', 'partly built SCRIPT_DIR-relative path widens to its directory');
  const unknown = mkSuiteRepo('SCRIPT_DIR=/somewhere/else\ncat "$SCRIPT_DIR/fixtures/x.txt"');
  const m = await lib();
  const c = m.checkSuites({ root: unknown, suites: ['fk'], runDir: runDirOf(unknown), ...BASE });
  fs.writeFileSync(path.join(runDirOf(unknown), 'fk.log'), 'PASS\n');
  const rec = m.recordSuite({ root: unknown, suite: 'fk', runDir: runDirOf(unknown), metrics: PASS('fk'), ...BASE });
  assert.equal(rec.recorded, false);
  assert.equal(rec.reason, 'inputs-unresolvable');
  const r = await chk(unknown, 'fk');
  assert.equal(r.status, 'RUN');
  assert.equal(r.reason, 'inputs-unresolvable');
  assert.equal(c.results[0].reason, 'inputs-unresolvable');
});

test('TEST-3167 fail closed: an expansion is accepted only after a known base and a literal directory, anything else is unresolvable', async () => {
  const SD = 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\n';
  const forms = {
    'SCRIPT_DIR then variable name': `${SD}bash "$SCRIPT_DIR/$s.sh"`,
    'braced SCRIPT_DIR then braced name': `${SD}cat "\${SCRIPT_DIR}/\${name}"`,
    'dirname then variable': 'cat "$(dirname "$0")/$f"',
    'SCRIPT_DIR then dots then variable': `${SD}cat "$SCRIPT_DIR/../$f"`,
    'custom own-directory variable': 'HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\ncat "$HERE/foo.txt"',
    'custom own-directory variable from dirname $0': 'DIR=$(dirname "$0")\ncat "$DIR/foo.txt"',
    'cd to the own directory then a bare word': 'cd "$(dirname "$0")"\nsource sub/x.sh',
    'literal closed by a quote before an expansion': 'cat "$ROOT/docs/pro"$S',
    'literal closed by a quote before a quoted expansion': 'cat "$ROOT/docs/pro""$S"',
    'repo root variable then variable name': 'cat "$ROOT/$x"',
    'bare directory then expansion': 'cat "$ROOT/docs$x"',
    'concatenated segments': 'cat docs"/"probe.txt',
    'bare dots that compute no root variable': `${SD}cd "$SCRIPT_DIR/.."`,
  };
  for (const [form, body] of Object.entries(forms)) {
    const root = mkSuiteRepo(body, { 'docs/probe.txt': 'one\n', 'tests/skills/helper.sh': 'h\n' });
    const r = await chk(root, 'fk');
    assert.equal(r.status, 'RUN', form);
    assert.equal(r.reason, 'inputs-unresolvable', form);
    const m = await lib();
    m.checkSuites({ root, suites: ['fk'], runDir: runDirOf(root), ...BASE });
    fs.writeFileSync(path.join(runDirOf(root), 'fk.log'), 'PASS\n');
    const rec = m.recordSuite({ root, suite: 'fk', runDir: runDirOf(root), metrics: PASS('fk'), ...BASE });
    assert.equal(rec.recorded, false, `${form}: record refuses`);
    assert.equal(rec.reason, 'inputs-unresolvable', form);
  }
  // Controls: a known base with a literal directory or file keeps resolving.
  const controls = {
    'SCRIPT_DIR file': [`${SD}cat "$SCRIPT_DIR/helper.sh"`, 'tests/skills/helper.sh'],
    'dirname literal directory then variable': ['cat "$(dirname "$0")/sub/$f"', 'tests/skills/sub/x.sh'],
    'bare dots computing a root variable': [`${SD}ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"\ncat "$SCRIPT_DIR/helper.sh"`, 'tests/skills/helper.sh'],
  };
  for (const [form, [body, touched]] of Object.entries(controls)) {
    const a = mkSuiteRepo(body, { 'tests/skills/helper.sh': 'h\n', 'tests/skills/sub/x.sh': 'x\n' });
    await pass(a, 'fk');
    assert.equal((await chk(a, 'fk')).status, 'REUSE', form);
    write(a, touched, 'changed\n');
    const r = await chk(a, 'fk');
    assert.equal(r.status, 'RUN', `${form}: ${touched} edited`);
    assert.equal(r.reason, 'inputs', form);
  }
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

test('TEST-3176 concurrent records of one suite leave a whole store file and no temp residue; a stale orphan temp is reaped', async () => {
  const m = await lib();
  const root = mkRepo();
  const runDir = runDirOf(root);
  const env = { ...process.env };
  delete env.AAI_ROLE; delete env.AAI_SUITE_REUSE; delete env.CI; delete env.GITHUB_ACTIONS;
  const pre = spawnSync(process.execPath, [HELPER, 'check', '--root', root, '--run-dir', runDir, '--mode', 'selected', '--isolation', 'on', '--suite', 'fx'], { env, encoding: 'utf8' });
  assert.equal(pre.status, 0, pre.stderr);
  fs.writeFileSync(path.join(runDir, 'fx.log'), 'PASS fx\n');
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

test('TEST-3193 no Node fs read traced by read-trace.cjs in a live manifest suite falls outside its identity', async () => {
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

// TEST-3194: the admission gate (residual R1). The tokenizer is advisory; a suite may
// stay in the manifest only if it passes fresh through the framework in a copy of the
// repository holding just its identity files.
function admit(manifestPath, suites) {
  const args = [HELPER, 'lint', '--root', REPO, '--minimal-tree', ...suites.flatMap((s) => ['--suite', s])];
  if (manifestPath) args.push('--manifest', manifestPath);
  const env = { ...process.env };
  delete env.AAI_ROLE; delete env.CI; delete env.GITHUB_ACTIONS;
  return spawnSync(process.execPath, args, { cwd: REPO, env, encoding: 'utf8', timeout: 900000 });
}

test('TEST-3194 every suite of the live manifest passes fresh in its minimal tree', () => {
  const man = JSON.parse(fs.readFileSync(path.join(REPO, 'tests/skills/suite-reuse.json'), 'utf8'));
  const r = admit(null, []);
  assert.equal(r.status, 0, `minimal-tree admission: ${r.stdout}${r.stderr}`);
  for (const suite of Object.keys(man.suites)) assert.match(r.stdout, new RegExp(`MINIMAL-TREE-PASS ${suite} `), `${suite} admitted`);
});

test('TEST-3194 a manifest naming aai-check-state is refused: it reads outside its identity', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'suite-reuse-admit-'));
  roots.push(dir);
  const man = JSON.parse(fs.readFileSync(path.join(REPO, 'tests/skills/suite-reuse.json'), 'utf8'));
  man.suites['aai-check-state'] = { inputs: [], live: false, note: 'fixture: reads docs/TECHNOLOGY.md outside its identity' };
  const file = path.join(dir, 'manifest.json');
  fs.writeFileSync(file, JSON.stringify(man));
  const r = admit(file, ['aai-check-state']);
  assert.equal(r.status, 1, `must refuse: ${r.stdout}${r.stderr}`);
  assert.match(r.stdout, /MINIMAL-TREE-FAIL aai-check-state /);
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
