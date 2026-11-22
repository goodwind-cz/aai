// sync-upgrade.test.mjs - TEST-4018 of the sync-on-node ride (docs/specs/SPEC-DRAFT-spec-sync-on-node.md, D-UPGRADE):
// the upgrade proof in scratch trees. The suite tests/skills/test-aai-sync-node.sh selects these cases with
// --test-name-pattern TEST-4018.
//
// The OLD side is the real layer at commit 077ee649 (the last commit before this ride), taken with `git archive` into a
// scratch directory: its sync, update, bootstrap and hook installer are the shipped old engines, so an old install made
// from it is a genuine old install. The NEW side is a committed scratch copy of this checkout's tracked and untracked
// files. The only reference to this checkout's git history is the read-only `git archive`; no target, source or cwd
// of a run is this checkout (D-SAFETY: the run's own scratch root with the own prefix and marker, a scrubbed git
// environment, HOME and TMPDIR inside the root, every path asserted under the root, nothing removed that the run did
// not create). U4 and the PowerShell leg of U0 use pwsh and are named skips without it (a failure on CI).

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, readlinkSync, realpathSync, rmSync,
  symlinkSync, writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { after, before, describe, test } from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  OWN_MARKER_FILE, REFERENCE_COMMIT, REFERENCE_SH_SHA256, createOwnScratch, removeOwnScratch, sha256File,
} from './sync-reference.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..', '..');
const UPDATE_REFERENCE = path.join(ROOT, 'tests', 'fixtures', 'aai-update-reference', 'aai-update.sh');
const REFUSAL = 'aai-sync: refused - node not found in PATH or aai-sync.mjs missing; nothing was changed. Install Node.js 22 or later (https://nodejs.org/) and re-run.';
const ENGINE = ['.aai/scripts/aai-sync.sh', '.aai/scripts/aai-sync.ps1', '.aai/scripts/aai-sync.mjs', '.aai/scripts/lib/resolve-base.mjs', '.aai/scripts/lib/gitignore-block.mjs'];
const OLD_LIB = '.aai/scripts/lib/gitignore-block.sh';

const under = (child, parent) => child === parent || child.startsWith(parent.endsWith(path.sep) ? parent : parent + path.sep);
const sha = (file) => createHash('sha256').update(readFileSync(file)).digest('hex');

// The scratch root: the suite's own (AAI_SYNC_UPGRADE_ROOT, a marked directory it removes itself) or one made here.
let ROOT_DIR = '';
let ownsRoot = false;
const pwshExe = () => {
  const r = spawnSync('/bin/sh', ['-c', 'command -v pwsh'], { encoding: 'utf8' });
  return r.status === 0 ? r.stdout.trim() : '';
};
let PWSH = '';
let CHECKOUT_BEFORE = '';

const checkoutState = () => spawnSync('git', ['-C', ROOT, 'status', '--porcelain', '--', '.aai', 'install.sh', 'install.ps1', 'hooks', '.claude', '.agents'],
  { encoding: 'utf8', env: scrubbed(ROOT_DIR || ROOT, {}) }).stdout;

// scrubbed(root, extra): the caller's environment minus every AAI_ and GIT_ variable, no system git config, an empty global
// one inside the root, HOME and TMPDIR inside the root.
function scrubbed(root, extra) {
  const env = {};
  for (const [k, v] of Object.entries(process.env)) if (!k.startsWith('AAI_') && !k.startsWith('GIT_')) env[k] = v;
  const home = path.join(root, 'home');
  const tmp = path.join(root, 'tmp');
  mkdirSync(home, { recursive: true });
  mkdirSync(tmp, { recursive: true });
  const gitconfig = path.join(root, 'gitconfig');
  writeFileSync(gitconfig, '');
  return { ...env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: gitconfig, HOME: home, TMPDIR: tmp, ...extra };
}

// assertInRoot(...paths): every path (existing or its parent) is under the scratch root and not under this checkout.
function assertInRoot(...paths) {
  const real = realpathSync(ROOT_DIR);
  for (const p of paths) {
    assert.ok(typeof p === 'string' && path.isAbsolute(p), `not an absolute path: ${p}`);
    const probe = existsSync(p) ? p : path.dirname(p);
    const r = realpathSync(probe);
    assert.ok(under(r, real), `${p} lies outside the scratch root ${ROOT_DIR}`);
    assert.ok(!under(r, realpathSync(ROOT)), `${p} lies under this checkout`);
  }
}

// run(label, exe, args, { cwd, env }): one child under the scrubbed environment; cwd and every absolute argument are asserted under the root.
function run(exe, args, { cwd, env = {}, input } = {}) {
  assertInRoot(cwd);
  for (const a of args) if (typeof a === 'string' && path.isAbsolute(a) && !a.startsWith(ROOT + path.sep) && !a.startsWith('/bin/') && !a.startsWith('/usr/')) assertInRoot(a);
  const r = spawnSync(exe, args, { cwd, env: scrubbed(ROOT_DIR, { PWD: cwd, ...env }), encoding: 'utf8', maxBuffer: 256 * 1024 * 1024, timeout: 540000, input });
  return { code: r.status, out: r.stdout ?? '', err: r.stderr ?? '', all: `${r.stdout ?? ''}${r.stderr ?? ''}` };
}
const ok = (r, what) => assert.equal(r.code, 0, `${what} exited ${r.code}: ${r.all.slice(-1500)}`);

const git = (dir, ...args) => ok(run('git', ['-c', 'user.email=upgrade@example.invalid', '-c', 'user.name=upgrade', '-c', 'commit.gpgsign=false', '-c', 'gc.auto=0', '-c', 'core.hooksPath=/dev/null', ...args], { cwd: dir }), `git ${args[0]}`);

function commitScratch(dir) {
  git(dir, 'init', '-q', '-b', 'main', '.');
  git(dir, 'add', '-A', '-f');
  git(dir, 'commit', '-q', '--no-verify', '-m', 'scratch source');
}

// A scratch source keeps what the sync reads: every path except tests/** and docs/** (docs/knowledge/** and docs/ai/AAI_VERSION.md kept).
const keepPath = (rel) => !rel.startsWith('tests/') && !(rel.startsWith('docs/') && !rel.startsWith('docs/knowledge/') && rel !== 'docs/ai/AAI_VERSION.md');

function buildNew() {
  const dir = path.join(ROOT_DIR, 'src-new');
  assertInRoot(dir);
  const ls = spawnSync('git', ['-C', ROOT, 'ls-files', '-z', '--cached', '--others', '--exclude-standard'], { encoding: 'utf8', env: scrubbed(ROOT_DIR, {}), maxBuffer: 256 * 1024 * 1024 });
  assert.equal(ls.status, 0, 'git ls-files');
  for (const rel of ls.stdout.split('\0').filter(Boolean)) {
    if (!keepPath(rel)) continue;
    const from = path.join(ROOT, rel);
    let st;
    try { st = lstatSync(from); } catch { continue; }
    if (st.isDirectory()) continue;
    const to = path.join(dir, rel);
    mkdirSync(path.dirname(to), { recursive: true });
    if (st.isSymbolicLink()) symlinkSync(readlinkSync(from), to);
    else { copyFileSync(from, to); chmodSync(to, st.mode & 0o777); }
  }
  commitScratch(dir);
  return dir;
}

function buildOld() {
  const dir = path.join(ROOT_DIR, 'src-old');
  const tar = path.join(ROOT_DIR, 'old.tar');
  assertInRoot(dir, tar);
  assert.equal(spawnSync('git', ['-C', ROOT, 'cat-file', '-e', `${REFERENCE_COMMIT}^{commit}`], { env: scrubbed(ROOT_DIR, {}) }).status, 0, `commit ${REFERENCE_COMMIT} is not in this clone (a shallow clone cannot run the upgrade proof)`);
  // the one read of this checkout's history: git archive writes only the tar named under the scratch root
  const ar = spawnSync('git', ['-C', ROOT, 'archive', '--format=tar', '-o', tar, REFERENCE_COMMIT], { env: scrubbed(ROOT_DIR, {}), encoding: 'utf8' });
  assert.equal(ar.status, 0, `git archive: ${ar.stderr}`);
  mkdirSync(dir, { recursive: true });
  ok(run('tar', ['-xf', tar, '-C', dir], { cwd: ROOT_DIR }), 'tar extract');
  rmSync(tar);
  rmSync(path.join(dir, 'tests'), { recursive: true, force: true });
  const docs = path.join(dir, 'docs');
  for (const name of readdirSync(docs)) if (name !== 'knowledge' && name !== 'ai') rmSync(path.join(docs, name), { recursive: true, force: true });
  for (const name of readdirSync(path.join(docs, 'ai'))) if (name !== 'AAI_VERSION.md') rmSync(path.join(docs, 'ai', name), { recursive: true, force: true });
  assert.equal(sha256File(path.join(dir, '.aai/scripts/aai-sync.sh')), REFERENCE_SH_SHA256, 'the archived old sync is the frozen bash twin');
  assert.ok(!existsSync(path.join(dir, '.aai/scripts/aai-sync.mjs')), 'the old layer has no sync module');
  commitScratch(dir);
  return dir;
}

// listAai(target): every regular file and link under target/.aai as a sorted list of forward-slash paths relative to target.
function listAai(target) {
  const out = [];
  const walk = (d, rel) => {
    for (const name of readdirSync(d)) {
      const full = path.join(d, name);
      const r = `${rel}/${name}`;
      if (lstatSync(full).isDirectory()) walk(full, r); else out.push(r);
    }
  };
  walk(path.join(target, '.aai'), '.aai');
  return out.sort();
}

// coreList(srcRoot): the entries of the core: list of the source's PROFILES.yaml.
function coreList(srcRoot) {
  const lines = readFileSync(path.join(srcRoot, '.aai/system/PROFILES.yaml'), 'utf8').split('\n');
  const start = lines.findIndex((l) => /^core:\s*$/.test(l));
  assert.ok(start >= 0, 'PROFILES core');
  const out = [];
  for (let i = start + 1; i < lines.length && /^(\s*-|\s*#|\s*$)/.test(lines[i]); i += 1) {
    const m = /^\s+-\s+(\S+)\s*$/.exec(lines[i]);
    if (m) out.push(m[1]);
  }
  assert.ok(out.length > 100, 'the core list is read');
  return out;
}

// expectedPrune(before, newSrc, core): the .aai files of the old install the new core list lacks: not under .aai/cache/, not listed, and
// not a script the source does not have (a target-only script is preserved), sorted.
function expectedPrune(before, newSrc, core) {
  const set = new Set(core);
  return before.filter((rel) => !rel.startsWith('.aai/cache/') && !set.has(rel)
    && !(rel.startsWith('.aai/scripts/') && !existsSync(path.join(newSrc, rel)))).sort();
}

function deletedItems(target, sinceNames) {
  const dir = path.join(target, 'docs/ai/reports');
  const names = readdirSync(dir).filter((n) => /^sync-conflicts-.*\.md$/.test(n) && !sinceNames.has(n)).sort();
  const files = names.length > 0 ? names : readdirSync(dir).filter((n) => /^sync-conflicts-.*\.md$/.test(n)).sort();
  const text = readFileSync(path.join(dir, files[files.length - 1]), 'utf8');
  const at = text.indexOf('## Deleted items');
  if (at < 0) return [];
  return [...text.slice(at).matchAll(/^- Path: (.+)$/gm)].map((m) => m[1]).sort();
}
const reportNames = (target) => new Set(readdirSync(path.join(target, 'docs/ai/reports')).filter((n) => /^sync-conflicts-/.test(n)));

const pinProfile = (target) => /^- Profile: (\S+)$/m.exec(readFileSync(path.join(target, '.aai/system/AAI_PIN.md'), 'utf8'))?.[1];

// the stamps and the engine-independent lines a tree compare ignores
function normalizedTree(dir) {
  const rows = {};
  const walk = (d, rel) => {
    for (const name of readdirSync(d).sort()) {
      const full = path.join(d, name);
      const r = (rel === '' ? name : `${rel}/${name}`).replace(/sync-conflicts-\d{8}-\d{6}\.md/, 'sync-conflicts-<STAMP>.md');
      const st = lstatSync(full);
      if (st.isSymbolicLink()) rows[r] = `link:${readlinkSync(full)}`;
      else if (st.isDirectory()) walk(full, r);
      else {
        const text = readFileSync(full).toString('latin1').replace(/^(- (?:Synced|Generated) at \(UTC\):).*$/gm, '$1 <STAMP>').replace(/sync-conflicts-\d{8}-\d{6}\.md/g, 'sync-conflicts-<STAMP>.md');
        rows[r] = `${(st.mode & 0o777).toString(8)}:${createHash('sha256').update(text).digest('hex')}`;
      }
    }
  };
  walk(dir, '');
  return rows;
}
function treeDiff(a, b) {
  const keys = [...new Set([...Object.keys(a), ...Object.keys(b)])].sort();
  return keys.filter((k) => a[k] !== b[k]).slice(0, 10).map((k) => `${k}: ${a[k] ?? '<absent>'} vs ${b[k] ?? '<absent>'}`);
}
function snapshot(dir) {
  const rows = [];
  const walk = (d, rel) => {
    for (const name of readdirSync(d).sort()) {
      const full = path.join(d, name);
      const r = rel === '' ? name : `${rel}/${name}`;
      const st = lstatSync(full);
      if (st.isSymbolicLink()) rows.push(`${r}\tlink\t${readlinkSync(full)}`);
      else if (st.isDirectory()) { rows.push(`${r}\tdir`); walk(full, r); } else rows.push(`${r}\tfile\t${(st.mode & 0o777).toString(8)}\t${sha(full)}`);
    }
  };
  walk(dir, '');
  return rows;
}

const state = { newSrc: '', oldSrc: '' };
const bashSync = (src, target, ...flags) => run('bash', [path.join(src, '.aai/scripts/aai-sync.sh'), target, ...flags], { cwd: ROOT_DIR });
const fresh = (name) => { const d = path.join(ROOT_DIR, name); mkdirSync(d, { recursive: true }); return d; };
const mkexec = (file) => chmodSync(file, 0o755);

// the end state every updated target holds (U1, U3, U4, and U2's follow-up update)
function assertEndState(target, profile, { before, label }) {
  const newSrc = state.newSrc;
  for (const rel of ENGINE) {
    assert.ok(existsSync(path.join(target, rel)), `${label}: ${rel} is vendored`);
    assert.equal(sha(path.join(target, rel)), sha(path.join(newSrc, rel)), `${label}: ${rel} equals the new source`);
  }
  for (const rel of ['.aai/scripts/aai-sync.sh']) assert.ok((lstatSync(path.join(target, rel)).mode & 0o111) !== 0, `${label}: ${rel} is executable`);
  if (profile === 'extended') assert.ok(!existsSync(path.join(target, OLD_LIB)), `${label}: no lib/gitignore-block.sh in an extended target`);
  if (profile === 'core') {
    assert.equal(pinProfile(target), 'core', `${label}: the pin still reads core`);
    for (const rel of coreList(newSrc)) if (existsSync(path.join(newSrc, rel))) assert.ok(existsSync(path.join(target, rel)), `${label}: core file ${rel} missing`);
    const after = new Set(listAai(target));
    for (const rel of expectedPrune(before, newSrc, coreList(newSrc))) assert.ok(!after.has(rel), `${label}: ${rel} should have been pruned`);
  }
}

// the target's own launchers run (the import closure of the switched modules arrived)
function assertLaunchers(target, label) {
  const t = (rel) => path.join(target, rel);
  const f = fresh(`${label}-fresh`);
  ok(run('bash', [t('.aai/scripts/aai-sync.sh'), f], { cwd: target }), `${label}: the target's aai-sync.sh`);
  assert.ok(existsSync(path.join(f, '.aai/scripts/aai-sync.mjs')), `${label}: the fresh target holds the module`);
  ok(run('bash', [t('.aai/scripts/aai-update.sh'), '--dry-run', '--repo', state.newSrc, '--force'], { cwd: target }), `${label}: aai-update.sh --dry-run`);
  ok(run('bash', [t('.aai/scripts/install-pre-commit-hook.sh'), '--print', 'index'], { cwd: target }), `${label}: install-pre-commit-hook.sh --print index`);
  ok(run('bash', [t('.aai/scripts/aai-bootstrap.sh'), '--help'], { cwd: target }), `${label}: aai-bootstrap.sh --help`);
}

// the strays an old core install gets before the update: a non-core file (pruned), a cache file and a target-only script (kept)
function plantStrays(target) {
  mkdirSync(path.join(target, '.aai/cache'), { recursive: true });
  writeFileSync(path.join(target, '.aai/cache/keep.txt'), 'cache\n');
  writeFileSync(path.join(target, '.aai/system/stray-old-file.md'), 'stray\n');
  writeFileSync(path.join(target, '.aai/scripts/target-only-tool.sh'), '#!/bin/sh\n');
}
function assertStrays(target, label) {
  assert.ok(!existsSync(path.join(target, '.aai/system/stray-old-file.md')), `${label}: the non-core file is pruned`);
  assert.ok(existsSync(path.join(target, '.aai/cache/keep.txt')), `${label}: .aai/cache is kept`);
  assert.ok(existsSync(path.join(target, '.aai/scripts/target-only-tool.sh')), `${label}: a target-only script is kept`);
}

// installOld(profile, name): an old install made by the frozen old twin of the old layer; returns the target and its .aai list.
function installOld(profile, name) {
  const t = fresh(name);
  ok(bashSync(state.oldSrc, t, '--profile', profile), `old install (${profile})`);
  assert.ok(existsSync(path.join(t, OLD_LIB)) === (profile === 'extended' || coreList(state.oldSrc).includes(OLD_LIB)), `${name}: the old library is present as the old profile says`);
  assert.ok(!existsSync(path.join(t, '.aai/scripts/aai-sync.mjs')), `${name}: an old install holds no module`);
  return t;
}

const updateFromNew = (target, runner) => run(runner ?? 'bash', runner ? [path.join(target, '.aai/scripts/aai-update.mjs'), '--repo', state.newSrc, '--force'] : [path.join(target, '.aai/scripts/aai-update.sh'), '--repo', state.newSrc, '--force'], { cwd: target });

before(() => {
  CHECKOUT_BEFORE = '';
  if (process.env.AAI_SYNC_UPGRADE_ROOT) {
    ROOT_DIR = realpathSync(process.env.AAI_SYNC_UPGRADE_ROOT);
    assert.ok(path.basename(ROOT_DIR).startsWith('aai-sync-node.') || path.basename(ROOT_DIR).startsWith('aai-sy-'), 'the root carries an own prefix');
    assert.ok(existsSync(path.join(ROOT_DIR, '.aai-sn-owned')) || existsSync(path.join(ROOT_DIR, OWN_MARKER_FILE)), 'the root carries an ownership marker');
    ROOT_DIR = path.join(ROOT_DIR, 'upgrade');
    mkdirSync(ROOT_DIR, { recursive: true });
    writeFileSync(path.join(ROOT_DIR, OWN_MARKER_FILE), `${process.pid}\n`);
  } else {
    ROOT_DIR = createOwnScratch('upgrade');
    ownsRoot = true;
  }
  PWSH = pwshExe();
  CHECKOUT_BEFORE = checkoutState();
  state.newSrc = buildNew();
  state.oldSrc = buildOld();
});
after(() => {
  if (ownsRoot && ROOT_DIR) removeOwnScratch(ROOT_DIR);
});

const needPwsh = (t) => {
  if (PWSH) return true;
  assert.ok(!process.env.CI, 'pwsh is required on CI but is not on PATH');
  t.skip('SKIP-CASE: this case needs pwsh, which is not installed here');
  return false;
};

describe('TEST-4018 the upgrade proof U0 to U4 in scratch trees', () => {
  test('TEST-4018 U0 a fresh install vendors the module and both libs and the vendored launchers sync again', (t) => {
    const t0 = fresh('u0-t');
    ok(bashSync(ROOT, t0, '--profile', 'core'), 'U0 install of the core profile');
    for (const rel of ENGINE) assert.ok(existsSync(path.join(t0, rel)), `U0: ${rel} is vendored`);
    assert.ok(!existsSync(path.join(t0, OLD_LIB)), 'U0: no lib/gitignore-block.sh');
    assert.equal(pinProfile(t0), 'core');
    // the vendored launchers sync t0 (as a source) into fresh targets with equal trees
    const a = fresh('u0-a');
    const b = fresh('u0-b');
    ok(run('bash', [path.join(t0, '.aai/scripts/aai-sync.sh'), a], { cwd: ROOT_DIR }), 'U0 bash launcher');
    ok(run('/bin/sh', [path.join(t0, '.aai/scripts/aai-sync.sh'), b], { cwd: ROOT_DIR }), 'U0 sh launcher');
    const na = normalizedTree(a);
    assert.deepEqual(treeDiff(na, normalizedTree(b)), [], 'U0: the bash and sh targets are equal');
    if (needPwsh(t)) {
      const c = fresh('u0-c');
      ok(run(PWSH, ['-NoProfile', '-NonInteractive', '-File', path.join(t0, '.aai/scripts/aai-sync.ps1'), '-TargetRoot', c], { cwd: ROOT_DIR }), 'U0 ps1 launcher');
      assert.deepEqual(treeDiff(na, normalizedTree(c)), [], 'U0: the bash and pwsh targets are equal');
    }
    // sh with a PATH of dirname only: the D-LAUNCH line, exit 1, the fresh target stays empty
    const bin = fresh('u0-bin');
    symlinkSync('/usr/bin/dirname', path.join(bin, 'dirname'));
    const empty = fresh('u0-empty');
    const r = run('/bin/sh', [path.join(t0, '.aai/scripts/aai-sync.sh'), empty], { cwd: ROOT_DIR, env: { PATH: bin } });
    assert.equal(r.code, 1, `U0: no node exits 1: ${r.all}`);
    assert.equal(r.err, `${REFUSAL}\n`, 'U0: the D-LAUNCH line');
    assert.deepEqual(readdirSync(empty), [], 'U0: the fresh target stays empty');
    // install.sh from a committed scratch copy
    const inst = fresh('u0-install');
    ok(run('bash', [path.join(state.newSrc, 'install.sh'), '--source-root', state.newSrc, '--target-root', inst], { cwd: ROOT_DIR }), 'U0 install.sh');
    assert.ok(existsSync(path.join(inst, '.aai/scripts/aai-sync.mjs')), 'U0: install.sh vendored the module');
  });

  for (const profile of ['core', 'extended']) {
    test(`TEST-4018 U1 an old ${profile} install updated by the new updater`, () => {
      const t = installOld(profile, `u1-${profile}`);
      if (profile === 'core') plantStrays(t);
      const before = listAai(t);
      const names = reportNames(t);
      const r = updateFromNew(t);
      ok(r, `U1 ${profile} update`);
      assertEndState(t, profile, { before, label: `U1 ${profile}` });
      if (profile === 'core') {
        assertStrays(t, 'U1 core');
        const want = expectedPrune(before, state.newSrc, coreList(state.newSrc));
        assert.ok(want.includes('.aai/system/stray-old-file.md'), 'U1: the planted stray is in the expected prune set');
        assert.deepEqual(deletedItems(t, names), want, 'U1: the advisory Deleted items are exactly the old core files the new list lacks');
        // the old library is a target-only script of a core target: preserved, never listed as deleted
        assert.ok(r.all.includes(`PRESERVE target-only script: ${OLD_LIB}`), 'U1: the old library is preserved as a target-only script');
      }
      assertLaunchers(t, `u1-${profile}`);
      if (profile === 'extended') {
        // no node: the vendored launcher refuses and the populated target is unchanged
        const bin = fresh('u1-bin');
        symlinkSync('/usr/bin/dirname', path.join(bin, 'dirname'));
        const snap = snapshot(t);
        const nn = run('/bin/sh', [path.join(t, '.aai/scripts/aai-sync.sh'), t], { cwd: ROOT_DIR, env: { PATH: bin } });
        assert.equal(nn.code, 1, `U1: no node exits 1: ${nn.all}`);
        assert.equal(nn.err, `${REFUSAL}\n`);
        assert.deepEqual(snapshot(t), snap, 'U1: the target is unchanged by the refusal');
      }
    });
  }

  for (const profile of ['core', 'extended']) {
    test(`TEST-4018 U2 the frozen old engine over a new tree (${profile}) vendors the module and keeps the frozen twin until the next update`, () => {
      // a copy of the new source whose aai-sync.sh is the frozen bash twin (its library beside it)
      const s2 = path.join(ROOT_DIR, `u2-src-${profile}`);
      assertInRoot(s2);
      ok(run('cp', ['-R', state.newSrc, s2], { cwd: ROOT_DIR }), 'copy of the new source');
      copyFileSync(path.join(ROOT, 'tests/fixtures/sync-reference/aai-sync.sh'), path.join(s2, '.aai/scripts/aai-sync.sh'));
      mkexec(path.join(s2, '.aai/scripts/aai-sync.sh'));
      copyFileSync(path.join(ROOT, 'tests/fixtures/sync-reference/gitignore-block.sh'), path.join(s2, OLD_LIB));
      git(s2, 'add', '-A', '-f');
      git(s2, 'commit', '-q', '--no-verify', '-m', 'frozen twin in a new tree');
      const t = fresh(`u2-${profile}`);
      ok(bashSync(s2, t, '--profile', profile), `U2 ${profile} sync by the frozen engine`);
      for (const rel of ['.aai/scripts/aai-sync.mjs', '.aai/scripts/lib/resolve-base.mjs', '.aai/scripts/lib/gitignore-block.mjs']) assert.ok(existsSync(path.join(t, rel)), `U2: ${rel} is vendored`);
      assert.equal(sha256File(path.join(t, '.aai/scripts/aai-sync.sh')), REFERENCE_SH_SHA256, 'U2: the target keeps the frozen twin as aai-sync.sh');
      assert.equal(sha(path.join(t, '.aai/scripts/aai-sync.sh')), sha(path.join(ROOT, 'tests/fixtures/sync-reference/aai-sync.sh')));
      const before = listAai(t);
      ok(updateFromNew(t), `U2 ${profile} next update`);
      assert.equal(sha(path.join(t, '.aai/scripts/aai-sync.sh')), sha(path.join(state.newSrc, '.aai/scripts/aai-sync.sh')), 'U2: the next update leaves the launcher');
      assertEndState(t, profile, { before, label: `U2 ${profile}` });
    });
  }

  test('TEST-4018 U3 the pre-ride-10 updater of an old core target performs the first update', () => {
    const t = installOld('core', 'u3-core');
    plantStrays(t);
    copyFileSync(UPDATE_REFERENCE, path.join(t, '.aai/scripts/aai-update.sh'));
    mkexec(path.join(t, '.aai/scripts/aai-update.sh'));
    assert.equal(sha(path.join(t, '.aai/scripts/aai-update.sh')), sha(UPDATE_REFERENCE));
    const before = listAai(t);
    const names = reportNames(t);
    const r = updateFromNew(t);
    ok(r, 'U3 update by the frozen bash updater');
    assertEndState(t, 'core', { before, label: 'U3' });
    assertStrays(t, 'U3');
    assert.deepEqual(deletedItems(t, names), expectedPrune(before, state.newSrc, coreList(state.newSrc)), 'U3: the Deleted items equal the expected prune set');
    assertLaunchers(t, 'u3');
  });

  test('TEST-4018 U4 the PowerShell runner updates an old core target', (t) => {
    if (!needPwsh(t)) return;
    const target = installOld('core', 'u4-core');
    plantStrays(target);
    const before = listAai(target);
    const names = reportNames(target);
    const r = run(process.execPath, [path.join(target, '.aai/scripts/aai-update.mjs'), '--repo', state.newSrc, '--force'], { cwd: target, env: { AAI_UPDATE_SYNC_RUNNER: PWSH } });
    ok(r, 'U4 update with the pwsh runner');
    assertEndState(target, 'core', { before, label: 'U4' });
    assertStrays(target, 'U4');
    assert.deepEqual(deletedItems(target, names), expectedPrune(before, state.newSrc, coreList(state.newSrc)), 'U4: the Deleted items equal the expected prune set');
    assertLaunchers(target, 'u4');
  });

  test('TEST-4018 nothing outside the scratch root changed', () => {
    assert.equal(checkoutState(), CHECKOUT_BEFORE, 'this checkout holds no change made by a case');
  });
});
