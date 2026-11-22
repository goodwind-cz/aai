// resolve-base.test.mjs - node:test cases of the shared base resolution
// (docs/specs/SPEC-DRAFT-spec-sync-on-node.md, D-BASE, TEST-4004). Every case name starts with TEST-4004; the suite
// tests/skills/test-aai-sync-node.sh selects them with --test-name-pattern.
//
// The same fixtures run through the lib and through its four users (aai-update.mjs resolveBase, aai-bootstrap.mjs
// resolveRoot, install-pre-commit-hook.mjs resolveBase and the sync module's resolveRoots), so a user that grows an
// identity check of its own and disagrees with the lib is caught. Directories are created and removed only through
// sync-reference.mjs (own prefix, marker, re-verified before removal); nothing here runs a sync or starts a child.
//
// TEST-4004: the `..` after a symbolic link, the stale, relative, absent and empty PWD, the trailing slash and the
// relative-path resolution; four users agreeing with the lib; no PWD comparison of their own in the four modules.

import assert from 'node:assert/strict';
import { mkdirSync, readFileSync, statSync, symlinkSync } from 'node:fs';
import path from 'node:path';
import { after, describe, test } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { createOwnScratch, removeOwnScratchAll } from './sync-reference.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..', '..');
const SCRIPTS = path.join(ROOT, '.aai', 'scripts');
const url = (...p) => pathToFileURL(path.join(SCRIPTS, ...p)).href;

const scratchDirs = [];
const scratch = (label = '') => {
  const dir = createOwnScratch(label);
  scratchDirs.push(dir);
  return dir;
};
after(() => {
  if (scratchDirs.length > 0) removeOwnScratchAll(scratchDirs.splice(0));
});

// fixture(): R/real/sub, R/link -> R/real/sub, R/rlink -> R/real, R/other, R/stale (not created).
function fixture() {
  const R = scratch('rb-');
  const real = path.join(R, 'real');
  mkdirSync(path.join(real, 'sub'), { recursive: true });
  mkdirSync(path.join(R, 'other'));
  symlinkSync(path.join(real, 'sub'), path.join(R, 'link'));
  symlinkSync(real, path.join(R, 'rlink'));
  return { R, real, sub: path.join(real, 'sub'), link: path.join(R, 'link'), rlink: path.join(R, 'rlink'), other: path.join(R, 'other'), stale: path.join(R, 'stale') };
}

// The cases every implementation answers the same way: [label, env, cwd, expected base].
function cases(f) {
  return [
    ['PWD is the working directory', { PWD: f.real }, f.real, f.real],
    ['PWD with a trailing slash', { PWD: `${f.real}/` }, f.real, f.real],
    ['PWD with a double trailing slash', { PWD: `${f.real}//` }, f.real, f.real],
    ['PWD with a dot segment', { PWD: `${f.real}/.` }, f.real, f.real],
    ['PWD through a link to the working directory keeps the logical path', { PWD: f.rlink }, f.real, f.rlink],
    ['PWD through a link with a trailing slash', { PWD: `${f.rlink}/` }, f.real, f.rlink],
    // R/link -> R/real/sub; the OS reads R/link/.. as R/real (the parent of the link target), the lexical reading is R
    ['PWD with .. after a symbolic link (the OS reading is the working directory)', { PWD: `${f.link}/..` }, f.real, f.real],
    ['PWD with .. after a symbolic link and a trailing slash', { PWD: `${f.link}/../` }, f.real, f.real],
    ['PWD with .. after a symbolic link, when the lexical reading is the working directory', { PWD: `${f.link}/..` }, f.R, f.R],
    ['a stale PWD', { PWD: f.stale }, f.real, f.real],
    ['a PWD naming another directory', { PWD: f.other }, f.real, f.real],
    ['a relative PWD', { PWD: 'real' }, f.real, f.real],
    ['an empty PWD', { PWD: '' }, f.real, f.real],
    ['an absent PWD', {}, f.real, f.real],
  ];
}

describe('TEST-4004 the shared base lib', () => {
  test('TEST-4004 the lib exports exactly resolveBase and resolveFromBase and has no side effect on import', async () => {
    const lib = await import(url('lib', 'resolve-base.mjs'));
    assert.deepEqual(Object.keys(lib).sort(), ['resolveBase', 'resolveFromBase']);
  });

  test('TEST-4004 resolveBase answers every PWD shape, the identity check applying to the path that is returned', async () => {
    const { resolveBase } = await import(url('lib', 'resolve-base.mjs'));
    const f = fixture();
    // the premise of the dot-dot case: the OS follows the link before the dot-dot, path.resolve folds it lexically
    assert.equal(statSync(`${f.link}/..`).ino, statSync(f.real).ino, 'the OS resolves the link first');
    assert.notEqual(path.resolve(`${f.link}/..`), f.real, 'the lexical reading is another directory');
    for (const [label, env, cwd, want] of cases(f)) assert.equal(resolveBase(env, cwd), want, label);
    // the defaults are the process environment and working directory
    assert.equal(resolveBase(), resolveBase(process.env, process.cwd()));
  });

  test('TEST-4004 resolveFromBase is the base for an empty path and the lexical resolution against it otherwise', async () => {
    const { resolveBase, resolveFromBase } = await import(url('lib', 'resolve-base.mjs'));
    const f = fixture();
    for (const [label, env, cwd] of cases(f)) {
      const base = resolveBase(env, cwd);
      assert.equal(resolveFromBase('', env, cwd), base, `${label}: empty`);
      assert.equal(resolveFromBase(undefined, env, cwd), base, `${label}: default`);
      assert.equal(resolveFromBase('t', env, cwd), path.join(base, 't'), `${label}: child`);
      assert.equal(resolveFromBase('..', env, cwd), path.dirname(base), `${label}: dot-dot goes up the logical path`);
      assert.equal(resolveFromBase(f.other, env, cwd), f.other, `${label}: an absolute path ignores the base`);
    }
    // dot-dot from a logical link path goes up the link's parent, not the target's parent
    assert.equal(resolveFromBase('..', { PWD: f.link }, f.sub), f.R);
    assert.equal(resolveFromBase(path.join('a', '..', 'b'), { PWD: f.link }, f.sub), path.join(f.link, 'b'));
    assert.equal(resolveFromBase('', undefined, f.real), resolveBase(undefined, f.real));
  });

  test('TEST-4004 the four users give the lib answers for every fixture', async () => {
    const lib = await import(url('lib', 'resolve-base.mjs'));
    const update = await import(url('aai-update.mjs'));
    const bootstrap = await import(url('aai-bootstrap.mjs'));
    const hook = await import(url('install-pre-commit-hook.mjs'));
    const sync = await import(url('aai-sync.mjs'));
    const f = fixture();
    for (const [label, env, cwd, want] of cases(f)) {
      assert.equal(lib.resolveBase(env, cwd), want, `lib: ${label}`);
      assert.equal(update.resolveBase('', env, cwd), want, `aai-update.mjs resolveBase: ${label}`);
      assert.equal(update.resolveBase('x', env, cwd), path.join(want, 'x'), `aai-update.mjs resolveBase with a path: ${label}`);
      assert.equal(bootstrap.resolveRoot('', env, cwd), want, `aai-bootstrap.mjs resolveRoot: ${label}`);
      assert.equal(bootstrap.resolveRoot('x', env, cwd), path.join(want, 'x'), `aai-bootstrap.mjs resolveRoot with a target: ${label}`);
      assert.equal(hook.resolveBase(env, cwd), want, `install-pre-commit-hook.mjs resolveBase: ${label}`);
    }
    // the sync module resolves its target through the lib: a relative target against the trusted base. Only the
    // roots are read here (no run, no write); the target is a directory of this test's own scratch tree.
    for (const [label, env, cwd, want] of cases(f)) {
      const roots = sync.resolveRoots({ target: '.', profile: '', outcome: 'run', arg: '' }, { env, cwd, scriptPath: path.join(SCRIPTS, 'aai-sync.mjs') });
      assert.equal(roots.target, want, `aai-sync.mjs resolveRoots: ${label}`);
    }
  });
});

// --- the scan of the four modules (no identity check of their own) ---------------------------------------------

const MODULES = ['aai-update.mjs', 'aai-bootstrap.mjs', 'install-pre-commit-hook.mjs', 'aai-sync.mjs'];

// ownPwdCheckProblems(source): a module reading PWD or comparing device and inode of a PWD stat itself. Comment lines
// are ignored. The lib is the only reader; the sync module compares device and inode of its roots (sameFile) but never
// reads PWD, and an inode comparison is a problem only on a line that also names the PWD.
export function ownPwdCheckProblems(source) {
  const problems = [];
  source.split('\n').forEach((line, i) => {
    if (/^\s*\/\//.test(line)) return;
    if (/\bPWD\b/.test(line)) problems.push(`${i + 1}: reads PWD: ${line.trim().slice(0, 60)}`);
    if (/\bsamePlace\(/.test(line)) problems.push(`${i + 1}: calls samePlace: ${line.trim().slice(0, 60)}`);
  });
  return problems;
}

describe('TEST-4004 no module keeps an identity check of its own', () => {
  test('TEST-4004 the four modules hold no PWD read and no samePlace call, and import the lib', () => {
    for (const name of MODULES) {
      const source = readFileSync(path.join(SCRIPTS, name), 'utf8');
      assert.deepEqual(ownPwdCheckProblems(source), [], `${name} holds an identity check of its own`);
      assert.ok(source.split('\n').some((l) => /^import \{[^}]*\} from '\.\/lib\/resolve-base\.mjs';$/.test(l)), `${name} imports ./lib/resolve-base.mjs`);
    }
  });

  test('TEST-4004 the scan reports each shape of the old identity check', () => {
    const old = [
      "const samePlace = (a, b) => a.dev === b.dev && a.ino === b.ino;",
      'export function resolveBase(rel, env, cwd) {',
      '  const pwd = env.PWD;',
      '  if (a && b && samePlace(a, b)) base = path.resolve(pwd);',
    ].join('\n');
    assert.equal(ownPwdCheckProblems(old).length, 2, 'the PWD read and the samePlace call');
    assert.deepEqual(ownPwdCheckProblems('// PWD is read by the lib\nconst x = 1;\n'), [], 'a comment is not a check');
    assert.deepEqual(ownPwdCheckProblems('const sameFile = (a, b) => a.dev === b.dev && a.ino === b.ino;\n'), [], 'a root comparison without PWD');
  });
});
