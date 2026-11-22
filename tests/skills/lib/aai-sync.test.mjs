// aai-sync.test.mjs - node:test cases of the sync-on-node ride
// (docs/specs/SPEC-0310-spec-sync-on-node.md). Every case name starts with its TEST id; the suite
// tests/skills/test-aai-sync-node.sh selects them with --test-name-pattern. The file grows run by run.
//
// Safety (D-SAFETY): directories are created and removed only through sync-reference.mjs (own prefix, marker,
// re-verified before removal); no case starts a container tool or kills by pattern; every sync invocation goes
// through runSync (a child) or runInProcess (an in-process run), which remove every GIT_ variable, set
// GIT_CONFIG_NOSYSTEM=1 and an empty GIT_CONFIG_GLOBAL, run only under the run's own scratch root and assert that
// the target's real path lies under that root and not under this checkout.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import nodeFs from 'node:fs';
import {
  chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, readlinkSync, realpathSync, renameSync,
  rmSync, statSync, symlinkSync, utimesSync, writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { after, describe, test } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import {
  ENGINE_FILES_MODULE, ENGINE_FILES_REFERENCE, OWN_MARKER_FILE, REFERENCE_COMMIT, REFERENCE_LIB, REFERENCE_LIB_SHA256, REFERENCE_PS1,
  REFERENCE_PS1_SHA256, REFERENCE_SH, REFERENCE_SH_SHA256, createOwnScratch, materializeSyncReference, removeOwnScratch,
  removeOwnScratchAll, sha256File,
} from './sync-reference.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..', '..');
const MODULE = path.join(ROOT, '.aai', 'scripts', 'aai-sync.mjs');
const MODULE_URL = pathToFileURL(MODULE).href;
const MODULE_LIBS = ['resolve-base.mjs', 'gitignore-block.mjs', 'merge-hooks-json.mjs'];
// Every test file of this ride that exists; a file that a later run adds is listed here by that run.
const NEW_TEST_FILES = [
  path.join(ROOT, 'tests', 'skills', 'test-aai-sync-node.sh'),
  path.join(HERE, 'aai-sync.test.mjs'),
  path.join(HERE, 'sync-reference.mjs'),
  path.join(HERE, 'resolve-base.test.mjs'),
  path.join(HERE, 'git-env-scrub.sh'),
  path.join(ROOT, 'tests', 'skills', 'aai-sync.Tests.ps1'),
  path.join(ROOT, 'tests', 'skills', 'test-aai-sync-docs.sh'),
  path.join(HERE, 'sync-upgrade.test.mjs'),
];

const scratchDirs = [];
const scratch = (label = '') => {
  const dir = createOwnScratch(label);
  scratchDirs.push(dir);
  return dir;
};
after(() => {
  if (scratchDirs.length > 0) removeOwnScratchAll(scratchDirs.splice(0));
});

const listTree = (dir) => readdirSync(dir, { recursive: true }).map(String).sort();
const under = (child, parent) => child === parent || child.startsWith(parent.endsWith(path.sep) ? parent : parent + path.sep);

// snapshotTree(dir): every path under dir with its type, mode and bytes (a link with its target text), links not
// followed, so two snapshots are equal exactly when nothing under dir changed.
function snapshotTree(dir) {
  const rows = [];
  const walk = (d, rel) => {
    for (const name of readdirSync(d).sort()) {
      const full = path.join(d, name);
      const r = rel === '' ? name : `${rel}/${name}`;
      const st = lstatSync(full);
      if (st.isSymbolicLink()) rows.push(`${r}\tlink\t${readlinkSync(full)}`);
      else if (st.isDirectory()) {
        rows.push(`${r}\tdir\t${(st.mode & 0o777).toString(8)}`);
        walk(full, r);
      } else rows.push(`${r}\tfile\t${(st.mode & 0o777).toString(8)}\t${createHash('sha256').update(readFileSync(full)).digest('hex')}`);
    }
  };
  walk(dir, '');
  return rows;
}

// --- the sync invocation helpers (D-SAFETY) -------------------------------------------------------------------

// prepareEnv(root, extra): the environment of a sync run: the caller's minus every AAI_ and GIT_ variable, plus no
// system git config, a global git config that is an empty scratch file (a global core.hooksPath or other setting
// would otherwise leak in) and a per-root TMPDIR.
export function prepareEnv(root, extra = {}) {
  const env = {};
  // every GIT_ variable goes: GIT_CONFIG_COUNT/KEY_n/VALUE_n, GIT_CONFIG_PARAMETERS, GIT_DIR, GIT_COMMON_DIR, ... can each
  // redirect the repository or its configuration; the two the run needs are set below
  for (const [k, v] of Object.entries(process.env)) if (!k.startsWith('AAI_') && !k.startsWith('GIT_')) env[k] = v;
  const gitconfig = path.join(root, 'gitconfig');
  const tmp = path.join(root, 'tmp');
  mkdirSync(tmp, { recursive: true });
  writeFileSync(gitconfig, '');
  return { ...env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: gitconfig, TMPDIR: tmp, ...extra };
}

// assertTargetUnderRoot(target, root, cwd, argv): the root is an own marked scratch root, the cwd and the target
// (when there is one; null for a run that names none) lie under it and not under this checkout, and no absolute
// argument of the run lies outside the root.
export function assertTargetUnderRoot(target, root, cwd, argv = []) {
  assert.ok(path.isAbsolute(root) && path.basename(root).startsWith('aai-sy-'), `scratch root ${root} lacks the own prefix`);
  assert.ok(existsSync(path.join(root, OWN_MARKER_FILE)), `scratch root ${root} lacks the ownership marker`);
  const realRoot = realpathSync(root);
  const realChecked = realpathSync(ROOT);
  assert.ok(under(realpathSync(cwd), realRoot), `cwd ${cwd} lies outside the scratch root ${root}`);
  if (target !== null) {
    assert.ok(typeof target === 'string' && target !== '', 'the target is a non-empty path');
    const real = realpathSync(target);
    assert.ok(under(real, realRoot), `the target ${target} lies outside the scratch root ${root}`);
    assert.ok(!under(real, realChecked), `the target ${target} lies under this checkout`);
  }
  for (const a of argv) {
    if (typeof a === 'string' && path.isAbsolute(a) && existsSync(a)) assert.ok(under(realpathSync(a), realRoot), `the argument ${a} lies outside the scratch root ${root}`);
  }
}

// runSync({ argv, root, target, cwd, env, script }): the one way these tests start the sync as a process: the module
// (default) or a copy of it under the root; exe is the interpreter (node by default, bash for the frozen bash
// reference). The streams are returned as strings.
export function runSync({ argv = [], root, target = null, cwd = root, env = {}, script = MODULE, exe = process.execPath, exeArgs = [], encoding = 'utf8' }) {
  const runEnv = prepareEnv(root, { PWD: cwd, ...env });
  assert.equal(runEnv.GIT_CONFIG_NOSYSTEM, '1');
  assert.equal(readFileSync(runEnv.GIT_CONFIG_GLOBAL, 'utf8'), '', 'GIT_CONFIG_GLOBAL is an empty file');
  assertTargetUnderRoot(target, root, cwd, argv);
  assert.ok(script === MODULE || under(script, root), `the script ${script} is neither the module nor under the scratch root`);
  return spawnSync(exe, [...exeArgs, script, ...argv], { cwd, env: runEnv, encoding, maxBuffer: 256 * 1024 * 1024 });
}

// runInProcess({ argv, root, target, cwd, env, scriptPath, spawn, ledger, onOut }): the one way these tests call the module's run().
// The scrubbed environment goes in as io.env; the child seam records and never starts anything real unless spawn is given.
// The module is imported from scriptPath (a scratch copy has its own root); ledger collects the conflicts and deletions the
// run records; onOut sees each printed text as it is printed.
async function runInProcess({ argv = [], root, target = null, cwd = root, env = {}, scriptPath = MODULE, spawn = null, ledger = null, onOut = null, now = null, platform = null }) {
  const runEnv = prepareEnv(root, { PWD: cwd, ...env });
  assertTargetUnderRoot(target, root, cwd, argv);
  const { run } = await import(pathToFileURL(scriptPath).href);
  const out = [];
  const err = [];
  const calls = [];
  const seam = spawn ?? ((file, args) => { calls.push([file, args]); return { status: 1, stdout: '', stderr: '' }; });
  const code = await run(argv, {
    out: (s) => { out.push(s); if (onOut) onOut(s); }, err: (s) => err.push(s), env: runEnv, cwd, spawn: seam, scriptPath, ...(ledger ? { ledger } : {}), ...(now ? { now } : {}), ...(platform ? { platform } : {}),
  });
  return { code, stdout: out.join(''), stderr: err.join(''), calls };
}

// --- TEST-4000 ---------------------------------------------------------------------------------------------

// The forbidden words are assembled from parts so that this file itself holds none of them.
const STOP = 'Stop-' + 'Process';
const TASKK = 'task' + 'kill';
const FORBIDDEN = ['dock' + 'er', 'pk' + 'ill', 'kill' + 'all'];

// forbiddenCalls(source): lines that call a forbidden tool: the word first on a statement (a Windows executable
// suffix or a PowerShell call operator or Start-Process in front included), the first string argument of a
// process-starting call, or a PowerShell kill by name.
export function forbiddenCalls(source) {
  const words = FORBIDDEN.join('|');
  const start = new RegExp(`(^|[;&|(\`]|\\$\\(|\\bexec\\s|\\bsudo\\s|\\bStart-Process\\s+(-FilePath\\s+)?['"]?)\\s*(${words})(\\.exe)?(\\s|$|['"])`, 'i');
  const spawned = new RegExp(`\\b(spawn|spawnSync|exec|execSync|execFile|execFileSync)\\(\\s*['"\`](${words})\\b`);
  const psKill = new RegExp(`\\b${STOP}\\b[^\\n#]*-Name\\b|\\b${TASKK}(\\.exe)?\\s+[^\\n#]*\\/IM\\b|\\bGet-Process\\b[^\\n#]*\\|\\s*${STOP}\\b`, 'i');
  return source.split('\n').map((line, i) => ({ line, n: i + 1 }))
    .filter(({ line }) => !/^\s*(#|\/\/)/.test(line) && (start.test(line) || spawned.test(line) || psKill.test(line)))
    .map(({ line, n }) => `${n}: ${line.trim()}`);
}

// The balanced-parenthesis text of every call of the process-starting function, from the call name on.
function spawnCalls(source) {
  const calls = [];
  const re = /\bspawnSync\(/g;
  let m;
  while ((m = re.exec(source)) !== null) {
    let depth = 0;
    let i = m.index + m[0].length - 1;
    let quote = '';
    for (; i < source.length; i += 1) {
      const c = source[i];
      if (quote) {
        if (c === '\\') i += 1;
        else if (c === quote) quote = '';
      } else if (c === "'" || c === '"' || c === '`') quote = c;
      else if (c === '(') depth += 1;
      else if (c === ')') {
        depth -= 1;
        if (depth === 0) break;
      }
    }
    calls.push({ at: m.index, text: source.slice(m.index, i + 1) });
  }
  return calls;
}

const AWAIT_RUN = 'await ' + 'run(';
// The call name is assembled so that this file holds no literal call text inside its own control strings.
const SPAWN = 'spawn' + 'Sync';
const SYNC_ENTRY = /\b(MODULE|REFERENCE_SH|REFERENCE_PS1)\b|aai-sync\.(mjs|sh|ps1)|refs\.(sh|ps1)/;

// invocationProblems(source): the JS rule of D-SAFETY: a process call that names a sync entry point must be the one
// inside runSync, and runSync must build its environment with prepareEnv, which sets GIT_CONFIG_NOSYSTEM to 1 and
// GIT_CONFIG_GLOBAL, and assert the target through assertTargetUnderRoot. A source with no runSync has no
// invocation to check.
export function invocationProblems(source) {
  const problems = [];
  const from = source.indexOf('export function runSync(');
  const bodyEnd = from < 0 ? -1 : source.indexOf('\n}\n', from);
  for (const call of spawnCalls(source)) {
    const inside = from >= 0 && call.at > from && call.at < bodyEnd;
    if (!inside && SYNC_ENTRY.test(call.text)) problems.push(`a sync entry point is started outside runSync: ${call.text.slice(0, 70)}`);
  }
  if (from >= 0) {
    const body = source.slice(from, bodyEnd);
    if (!body.includes('prepareEnv(')) problems.push('runSync does not build its environment with prepareEnv');
    if (!body.includes('assertTargetUnderRoot(')) problems.push('runSync does not assert the target against the scratch root');
    const prep = source.slice(source.indexOf('export function prepareEnv('), source.indexOf('export function assertTargetUnderRoot('));
    if (!/GIT_CONFIG_NOSYSTEM: '1'/.test(prep)) problems.push('prepareEnv does not set GIT_CONFIG_NOSYSTEM to 1');
    if (!/GIT_CONFIG_GLOBAL: gitconfig/.test(prep) || !/writeFileSync\(gitconfig, ''\)/.test(prep)) problems.push('prepareEnv does not set GIT_CONFIG_GLOBAL to an empty file');
  }
  return problems;
}

// inProcessRunProblems(source): the in-process rule of D-SAFETY: an awaited call of the module's run() must sit inside
// runInProcess (which builds the environment with prepareEnv and asserts the target under the scratch root) or
// carry the recording child seam in its options (nothing real is started then). prepareEnv must scrub every GIT_
// variable. It checks the calls of a function named run( that is awaited, nothing else.
export function inProcessRunProblems(source) {
  const problems = [];
  const from = source.indexOf('\nasync function runInProcess(');
  const bodyEnd = from < 0 ? -1 : source.indexOf('\n}\n', from);
  if (from < 0) problems.push('there is no runInProcess helper');
  else {
    const body = source.slice(from, bodyEnd);
    if (!body.includes('prepareEnv(')) problems.push('runInProcess does not build its environment with prepareEnv');
    if (!body.includes('assertTargetUnderRoot(')) problems.push('runInProcess does not assert the target against the scratch root');
    if (!/env: runEnv/.test(body)) problems.push('runInProcess does not pass the scrubbed environment as io.env');
  }
  const re = /\bawait run\(/g;
  let m;
  while ((m = re.exec(source)) !== null) {
    let depth = 0;
    let i = m.index + m[0].length - 1;
    for (; i < source.length; i += 1) {
      if (source[i] === '(') depth += 1;
      else if (source[i] === ')' && --depth === 0) break;
    }
    const text = source.slice(m.index, i + 1);
    const inside = from >= 0 && m.index > from && m.index < bodyEnd;
    if (!inside && !/\bspawn\b/.test(text)) problems.push(`an in-process run( call is made outside runInProcess: ${text.slice(0, 70)}`);
  }
  const prep = source.slice(source.indexOf('export function prepareEnv('), source.indexOf('export function assertTargetUnderRoot('));
  if (!/startsWith\('GIT_'\)/.test(prep)) problems.push('prepareEnv does not drop every GIT_ variable');
  return problems;
}

// shellInvocationProblems(source): the same rule for a bash suite. A line that runs a sync entry point must sit
// inside the run_sync_scratch function, which sets GIT_CONFIG_NOSYSTEM=1 and an empty GIT_CONFIG_GLOBAL, removes
// every other GIT_ variable and asserts the target under the scratch root: a line outside it is flagged when it runs
// the entry point through bash, sh, dash, node or pwsh, or names a sync launcher or module with a sync argument.
export function shellInvocationProblems(source) {
  const problems = [];
  const lines = source.split('\n');
  const entry = /\b(bash|sh|dash|node|pwsh)\s+("?\$\{?(MJS|SH_LAUNCHER|PS1_LAUNCHER|REFERENCE_SH|REFERENCE_PS1)\b|\S*aai-sync\.(sh|mjs|ps1))/;
  const named = /aai-sync\.(sh|ps1|mjs)\b.*(--profile\b|-Profile\b|-TargetRoot\b|-h\b)/;
  const open = lines.findIndex((l) => /^run_sync_scratch\(\) \{/.test(l));
  const close = open < 0 ? -1 : lines.findIndex((l, i) => i > open && l === '}');
  lines.forEach((line, i) => {
    if (/^\s*#/.test(line) || !(entry.test(line) || named.test(line))) return;
    if (!(open >= 0 && i > open && i < close)) problems.push(`${i + 1}: a sync entry point is run outside run_sync_scratch: ${line.trim().slice(0, 70)}`);
  });
  if (open < 0) {
    problems.push('the suite has no run_sync_scratch function');
  } else {
    const body = lines.slice(open, close + 1).join('\n');
    if (!body.includes('GIT_CONFIG_NOSYSTEM=1')) problems.push('run_sync_scratch does not set GIT_CONFIG_NOSYSTEM=1');
    if (!/GIT_CONFIG_GLOBAL="\$/.test(body)) problems.push('run_sync_scratch does not set GIT_CONFIG_GLOBAL to a scratch file');
    if (!/unset "\$_gv"/.test(body) && !body.includes('scratch_env_run')) problems.push('run_sync_scratch does not remove the GIT_ variables');
    if (!/case "\$real_target" in "\$real_work"\/\*\)/.test(body)) problems.push('run_sync_scratch does not assert the target under the scratch root');
  }
  return problems;
}

describe('TEST-4000 scratch safety and the frozen references', () => {
  test('TEST-4000 removeOwnScratch removes the children first and the ownership marker last', (t) => {
    if (process.platform === 'win32' || (typeof process.getuid === 'function' && process.getuid() === 0)) {
      t.skip('a directory cannot be made undeletable here (win32 or root)');
      return;
    }
    const dir = scratch('order-');
    const locked = path.join(dir, 'locked');
    mkdirSync(locked);
    writeFileSync(path.join(locked, 'f'), 'x\n');
    writeFileSync(path.join(dir, 'plain'), 'y\n');
    chmodSync(locked, 0o500);
    try {
      assert.throws(() => removeOwnScratch(dir), /EACCES|EPERM/);
      assert.ok(existsSync(path.join(dir, OWN_MARKER_FILE)), 'an interrupted removal still leaves the marker, so a rerun may finish it');
    } finally {
      chmodSync(locked, 0o700);
    }
  });

  test('TEST-4000 removeOwnScratch refuses each unsafe path', () => {
    const base = scratch('refuse-');
    const unmarked = path.join(base, 'aai-sy-unmarked');
    mkdirSync(unmarked);
    const foreign = path.join(base, 'foreign-name');
    mkdirSync(foreign);
    writeFileSync(path.join(foreign, OWN_MARKER_FILE), `${process.pid}\n`);
    const nonNumeric = path.join(base, 'aai-sy-badmarker');
    mkdirSync(nonNumeric);
    writeFileSync(path.join(nonNumeric, OWN_MARKER_FILE), 'not-a-pid\n');
    assert.throws(() => removeOwnScratch(''), /empty path/);
    assert.throws(() => removeOwnScratch(undefined), /empty path/);
    assert.throws(() => removeOwnScratch('aai-sy-relative'), /relative path/);
    assert.throws(() => removeOwnScratch(foreign), /own prefix/);
    assert.throws(() => removeOwnScratch(path.join(base, 'aai-sy-missing')), /does not exist/);
    assert.throws(() => removeOwnScratch(unmarked), /marker/);
    assert.throws(() => removeOwnScratch(nonNumeric), /marker/);
    assert.throws(() => removeOwnScratchAll([]), /empty list/);
    for (const kept of [foreign, unmarked, nonNumeric]) assert.ok(existsSync(kept), `${kept} must survive`);
  });

  test('TEST-4000 removeOwnScratch refuses a path outside the temp directory and a symlink', () => {
    const base = scratch('outside-');
    const marked = path.join(base, 'aai-sy-marked');
    mkdirSync(marked);
    writeFileSync(path.join(marked, OWN_MARKER_FILE), `${process.pid}\n`);
    // a child whose temp directory is a sub-directory: the marked directory then lies outside it
    const childTmp = path.join(base, 'childtmp');
    mkdirSync(childTmp);
    const helperUrl = pathToFileURL(path.join(HERE, 'sync-reference.mjs')).href;
    const code = `import(${JSON.stringify(helperUrl)}).then((m) => { try { m.removeOwnScratch(${JSON.stringify(marked)}); console.log('REMOVED'); } catch (e) { console.log(e.message); } });`;
    const r = spawnSync(process.execPath, ['-e', code], {
      encoding: 'utf8', env: { ...prepareEnv(base), TMPDIR: childTmp, TMP: childTmp, TEMP: childTmp },
    });
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /outside the temp directory/);
    assert.ok(existsSync(marked), 'the outside directory must survive');
    // a symlink with the prefix is refused and its target survives
    const link = path.join(base, 'aai-sy-link');
    symlinkSync(marked, link);
    assert.throws(() => removeOwnScratch(link), /not a real directory/);
    assert.ok(existsSync(marked));
  });

  test('TEST-4000 removeOwnScratch removes a marked own directory and createOwnScratch marks it', () => {
    const dir = createOwnScratch('own-');
    assert.ok(path.basename(dir).startsWith('aai-sy-own-'));
    assert.match(readFileSync(path.join(dir, OWN_MARKER_FILE), 'utf8'), /^[0-9]+\n$/);
    writeFileSync(path.join(dir, 'file'), 'x');
    removeOwnScratch(dir);
    assert.ok(!existsSync(dir));
  });

  test('TEST-4000 the three reference copies hash to their pins and equal the pinned commit', () => {
    for (const [sha, head] of [[REFERENCE_SH_SHA256, '00aac687'], [REFERENCE_PS1_SHA256, '038a640a'], [REFERENCE_LIB_SHA256, '5544c839']]) {
      assert.match(sha, /^[0-9a-f]{64}$/);
      assert.ok(sha.startsWith(head), `the D-REF pin ${head}`);
    }
    assert.equal(REFERENCE_COMMIT, '077ee649');
    const names = [[REFERENCE_SH, REFERENCE_SH_SHA256, '.aai/scripts/aai-sync.sh'], [REFERENCE_PS1, REFERENCE_PS1_SHA256, '.aai/scripts/aai-sync.ps1'],
      [REFERENCE_LIB, REFERENCE_LIB_SHA256, '.aai/scripts/lib/gitignore-block.sh']];
    for (const [rel, want, original] of names) {
      const file = path.join(ROOT, rel);
      assert.equal(sha256File(file), want, `${rel} hashes to its pin`);
      const has = spawnSync('git', ['cat-file', '-e', `${REFERENCE_COMMIT}^{commit}`], { cwd: ROOT, encoding: 'utf8' });
      if (has.status !== 0) continue; // shallow checkout: the hash pin alone holds
      const shown = spawnSync('git', ['show', `${REFERENCE_COMMIT}:${original}`], { cwd: ROOT, maxBuffer: 16 * 1024 * 1024 });
      assert.equal(shown.status, 0);
      assert.ok(Buffer.compare(shown.stdout, readFileSync(file)) === 0, `${rel} equals ${REFERENCE_COMMIT}:${original}`);
    }
    assert.equal(statSync(path.join(ROOT, REFERENCE_SH)).mode & 0o111, 0o111, 'the bash reference stays executable');
    assert.deepEqual(ENGINE_FILES_REFERENCE, ['.aai/scripts/aai-sync.sh', '.aai/scripts/aai-sync.ps1', '.aai/scripts/lib/gitignore-block.sh']);
    assert.deepEqual(ENGINE_FILES_MODULE, ['.aai/scripts/aai-sync.sh', '.aai/scripts/aai-sync.ps1', '.aai/scripts/aai-sync.mjs',
      '.aai/scripts/lib/resolve-base.mjs', '.aai/scripts/lib/gitignore-block.mjs']);
  });

  test('TEST-4000 materializeSyncReference verifies the hashes, writes the twins and the library and removes the module side', () => {
    const into = path.join(scratch('mat-'), 'tree');
    mkdirSync(path.join(into, '.aai', 'scripts', 'lib'), { recursive: true });
    for (const rel of ENGINE_FILES_MODULE) writeFileSync(path.join(into, rel), `module side ${rel}\n`);
    writeFileSync(path.join(into, '.aai', 'scripts', 'keep.sh'), 'keep\n');
    const dests = materializeSyncReference(into);
    assert.equal(dests.sh, path.join(into, '.aai', 'scripts', 'aai-sync.sh'));
    assert.equal(dests.ps1, path.join(into, '.aai', 'scripts', 'aai-sync.ps1'));
    assert.equal(dests.lib, path.join(into, '.aai', 'scripts', 'lib', 'gitignore-block.sh'));
    assert.equal(sha256File(dests.sh), REFERENCE_SH_SHA256);
    assert.equal(sha256File(dests.ps1), REFERENCE_PS1_SHA256);
    assert.equal(sha256File(dests.lib), REFERENCE_LIB_SHA256);
    assert.equal(statSync(dests.sh).mode & 0o777, 0o755);
    assert.equal(statSync(dests.ps1).mode & 0o777, 0o644);
    assert.deepEqual(readdirSync(path.join(into, '.aai', 'scripts')).sort(), ['aai-sync.ps1', 'aai-sync.sh', 'keep.sh', 'lib']);
    assert.deepEqual(readdirSync(path.join(into, '.aai', 'scripts', 'lib')), ['gitignore-block.sh']);
    // a source root that is this checkout, a relative path or an edited reference is refused
    assert.throws(() => materializeSyncReference(ROOT), /this checkout/);
    assert.throws(() => materializeSyncReference('relative/path'), /not an absolute path/);
    assert.ok(existsSync(MODULE), 'the refused checkout kept its module');
  });

  test('TEST-4000 an edited reference fails materialization by naming the file', () => {
    // a child whose helper sees an edited copy: a scratch tree that holds the helper and the three references, one edited
    const tree = path.join(scratch('mat-bad-'), 'repo');
    mkdirSync(path.join(tree, 'tests', 'skills', 'lib'), { recursive: true });
    copyFileSync(path.join(HERE, 'sync-reference.mjs'), path.join(tree, 'tests', 'skills', 'lib', 'sync-reference.mjs'));
    for (const rel of [REFERENCE_SH, REFERENCE_PS1, REFERENCE_LIB]) {
      mkdirSync(path.dirname(path.join(tree, rel)), { recursive: true });
      copyFileSync(path.join(ROOT, rel), path.join(tree, rel));
    }
    writeFileSync(path.join(tree, REFERENCE_PS1), 'edited\n');
    const into = path.join(scratch('mat-bad-into-'), 'x');
    mkdirSync(into);
    const helperUrl = pathToFileURL(path.join(tree, 'tests', 'skills', 'lib', 'sync-reference.mjs')).href;
    const code = `import(${JSON.stringify(helperUrl)}).then((m) => { try { m.materializeSyncReference(${JSON.stringify(into)}); console.log('WRITTEN'); } catch (e) { console.log(e.message); } });`;
    const r = spawnSync(process.execPath, ['-e', code], { encoding: 'utf8', env: prepareEnv(path.dirname(into)) });
    assert.equal(r.status, 0, r.stderr);
    assert.ok(r.stdout.includes(path.join(tree, REFERENCE_PS1)) && /hashes to/.test(r.stdout), r.stdout);
    assert.deepEqual(listTree(into), [], 'nothing was written for an edited reference');
  });

  test('TEST-4000 the new test files hold no call of a container tool or a kill by pattern', () => {
    for (const file of NEW_TEST_FILES) {
      assert.ok(existsSync(file), `${file} exists`);
      assert.deepEqual(forbiddenCalls(readFileSync(file, 'utf8')), [], `${path.basename(file)} calls a forbidden tool`);
    }
    // positive control: the scanner reports each shape, and passes clean text
    const [d, p, k] = FORBIDDEN;
    assert.equal(forbiddenCalls(`${d} ps -aq\n`).length, 1);
    assert.equal(forbiddenCalls(`  ${p} -f node\n`).length, 1);
    assert.equal(forbiddenCalls(`x && ${k} node\n`).length, 1);
    assert.equal(forbiddenCalls(`out=$(${d} ps)\n`).length, 1);
    assert.equal(forbiddenCalls(`${SPAWN}('${d}', ['ps'])\n`).length, 1);
    assert.equal(forbiddenCalls(`# the stub log holds no ${d} line\n`).length, 0);
    assert.equal(forbiddenCalls('echo hello\n').length, 0);
    assert.equal(forbiddenCalls(`& ${d} ps\n`).length, 1);
    assert.equal(forbiddenCalls(`${d}.exe ps\n`).length, 1);
    assert.equal(forbiddenCalls(`Start-Process ${d} -ArgumentList ps\n`).length, 1);
    assert.equal(forbiddenCalls(`${STOP} -Name node -Force\n`).length, 1);
    assert.equal(forbiddenCalls(`Get-Process node | ${STOP}\n`).length, 1);
    assert.equal(forbiddenCalls(`${TASKK} /F /IM node.exe\n`).length, 1);
    assert.equal(forbiddenCalls(`${STOP} -Id $pid\n`).length, 0);
    assert.equal(forbiddenCalls(`# never ${d} or ${STOP} -Name here\n`).length, 0);
    assert.equal(forbiddenCalls(`$x = 'no ${d} here'\n`).length, 0);
  });

  test('TEST-4000 the scanned list holds every sync-on-node test file that exists', () => {
    // Files of this ride's naming under tests/skills and its lib; pre-existing sync files are not new.
    const exempt = new Set(['test-aai-sync-seed.sh', 'aai-sync-seed.sh']);
    const found = [];
    for (const dir of [path.join(ROOT, 'tests', 'skills'), HERE]) {
      for (const name of readdirSync(dir)) {
        if (/(aai-sync-(node|docs|fixtures)|aai-sync\.(test|Tests)|sync-reference|sync-upgrade\.test|resolve-base\.test|git-env-scrub)/.test(name) && !exempt.has(name) && statSync(path.join(dir, name)).isFile()) found.push(path.join(dir, name));
      }
    }
    for (const f of found) assert.ok(NEW_TEST_FILES.includes(f), `${f} is a test file of this ride and must be added to NEW_TEST_FILES`);
    for (const f of NEW_TEST_FILES) assert.ok(found.includes(f), `${f} is listed but not found by name`);
  });

  test('TEST-4000 every sync invocation sets the git environment and asserts the target under the scratch root', () => {
    for (const file of NEW_TEST_FILES) {
      const src = readFileSync(file, 'utf8');
      // git-env-scrub.sh and test-aai-sync-docs.sh run no sync entry point (only the suite test-aai-sync-node.sh and the upgrade cases do) and the Pester file runs only the launcher with its own scrubbed environment: the forbidden-call scan covers both
      const problems = file.endsWith('git-env-scrub.sh') || file.endsWith('test-aai-sync-docs.sh') || file.endsWith('.ps1') ? [] : file.endsWith('.sh') ? shellInvocationProblems(src) : invocationProblems(src);
      assert.deepEqual(problems, [], path.basename(file));
    }
    const mine = readFileSync(path.join(HERE, 'aai-sync.test.mjs'), 'utf8');
    assert.ok(mine.includes('export function runSync('), 'the invocation helper exists');
    // positive controls for both scanners
    assert.equal(invocationProblems(`${SPAWN}(process.execPath, [MODULE, '-h'], {});\n`).length, 1);
    assert.equal(invocationProblems(`${SPAWN}('bash', [path.join(root, 'aai-sync.sh')], {});\n`).length, 1);
    assert.equal(invocationProblems(`${SPAWN}('git', ['status'], {});\n`).length, 0);
    assert.equal(invocationProblems(mine.replace("GIT_CONFIG_NOSYSTEM: '1'", "GIT_CONFIG_NOSYSTEM: '0'")).length, 1);
    assert.equal(invocationProblems(mine.replace('GIT_CONFIG_GLOBAL: gitconfig', 'GIT_X: gitconfig')).length, 1);
    assert.equal(invocationProblems(mine.replace("writeFileSync(gitconfig, '');", '')).length, 1);
    assert.equal(invocationProblems(mine.replace('  assertTargetUnderRoot(target, root, cwd, argv);\n  assert.ok(script', '  assert.ok(script')).length, 1);
    assert.equal(shellInvocationProblems('bash "$SH_LAUNCHER" --profile core\n').length, 2);
    assert.equal(shellInvocationProblems('out="$(node "$MJS" -h)"\n').length, 2);
    const okBody = 'run_sync_scratch() {\n  case "$real_target" in "$real_work"/*) ;; *) exit 1 ;; esac\n  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$g" scratch_env_run node "$MJS" "$@"\n}\n';
    assert.equal(shellInvocationProblems(`# bash "$MJS" in a comment\n[[ -f "$MJS" ]]\nMJS="$PROJECT_ROOT/x"\n${okBody}`).length, 0);
    assert.equal(shellInvocationProblems('run_sync_scratch() {\n  node "$MJS" "$@"\n}\n').length, 4);
    assert.equal(shellInvocationProblems('# no run_sync_scratch at all\n').length, 1);
    // the committed bash suite: no problem as committed, and a problem for each property removed from run_sync_scratch
    const suite = readFileSync(NEW_TEST_FILES.find((f) => f.endsWith('test-aai-sync-node.sh')), 'utf8');
    assert.ok(/^run_sync_scratch\(\) \{/m.test(suite), 'the suite has run_sync_scratch');
    assert.deepEqual(shellInvocationProblems(suite), []);
    assert.ok(shellInvocationProblems(suite.replace('local -x GIT_CONFIG_NOSYSTEM=1', 'local -x GIT_CONFIG_NOSYSTEM=0')).length >= 1, 'GIT_CONFIG_NOSYSTEM removed');
    assert.ok(shellInvocationProblems(suite.replace(/^ {2}case "\$real_target" in "\$real_work"\/\*\) ;;.*$/m, '')).length >= 1, 'the scratch-root assertion removed');
    assert.ok(shellInvocationProblems(`${suite}\nbash .aai/scripts/aai-sync.sh t --profile core\n`).length >= 1, 'a run outside run_sync_scratch');
  });

  test('TEST-4000 an awaited in-process run( call goes through runInProcess or carries the recording seam, and prepareEnv drops every GIT_ variable', () => {
    const mine = readFileSync(path.join(HERE, 'aai-sync.test.mjs'), 'utf8');
    assert.deepEqual(inProcessRunProblems(mine), []);
    // positive controls
    assert.equal(inProcessRunProblems(mine.replace('  assertTargetUnderRoot(target, root, cwd, argv);\n  const { run }', '  const { run }')).length, 1);
    assert.equal(inProcessRunProblems(mine.replace("!k.startsWith('GIT_')", "k !== 'GIT_DIR'")).length, 1);
    assert.equal(inProcessRunProblems(mine.replace('env: runEnv, cwd, spawn: seam', 'cwd, spawn: seam')).length, 1);
    assert.equal(inProcessRunProblems(`${mine}\nconst c = ${AWAIT_RUN}[], { cwd: repo, env: prepareEnv(root) });\n`).length, 1);
    assert.equal(inProcessRunProblems(`${mine}\nconst c = ${AWAIT_RUN}[], { spawn, cwd: repo });\n`).length, 0);
  });

  test('TEST-4000 prepareEnv builds the isolated git environment and the helpers refuse a target outside the root', async () => {
    const root = scratch('env-');
    const saved = { role: process.env.AAI_ROLE, dir: process.env.GIT_DIR, count: process.env.GIT_CONFIG_COUNT, params: process.env.GIT_CONFIG_PARAMETERS };
    process.env.AAI_ROLE = 'x';
    process.env.GIT_DIR = '/nonexistent/git';
    process.env.GIT_CONFIG_COUNT = '1';
    process.env.GIT_CONFIG_PARAMETERS = "'core.hooksPath=/x'";
    let env;
    try {
      env = prepareEnv(root, { EXTRA: '1' });
    } finally {
      for (const [name, v] of [['AAI_ROLE', saved.role], ['GIT_DIR', saved.dir], ['GIT_CONFIG_COUNT', saved.count], ['GIT_CONFIG_PARAMETERS', saved.params]]) {
        if (v === undefined) delete process.env[name]; else process.env[name] = v;
      }
    }
    assert.ok(!('AAI_ROLE' in env));
    assert.deepEqual(Object.keys(env).filter((k) => k.startsWith('GIT_')).sort(), ['GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM']);
    assert.equal(env.GIT_CONFIG_NOSYSTEM, '1');
    assert.equal(env.EXTRA, '1');
    assert.equal(readFileSync(env.GIT_CONFIG_GLOBAL, 'utf8'), '');
    assert.ok(under(env.GIT_CONFIG_GLOBAL, root) && under(env.TMPDIR, root));
    // the helpers refuse a cwd or a target that lies outside the root, under this checkout, or a root without the prefix
    assert.throws(() => runSync({ argv: ['-h'], root, cwd: ROOT }), /outside the scratch root/);
    assert.throws(() => runSync({ argv: [ROOT], root, target: ROOT }), /outside the scratch root/);
    assert.throws(() => assertTargetUnderRoot(null, ROOT, root), /own prefix/);
    const bare = path.join(root, 'no-marker');
    mkdirSync(bare);
    assert.throws(() => assertTargetUnderRoot(null, bare, bare), /own prefix|ownership marker/);
    const inside = path.join(root, 'inside');
    mkdirSync(inside);
    assertTargetUnderRoot(inside, root, root, [inside]);
    assert.throws(() => assertTargetUnderRoot(inside, root, root, [ROOT]), /outside the scratch root/);
    await assert.rejects(runInProcess({ argv: [ROOT], root, target: ROOT }), /outside the scratch root/);
    // a link under the root that points at this checkout is a target under the checkout
    const link = path.join(root, 'link-to-checkout');
    symlinkSync(ROOT, link);
    assert.throws(() => assertTargetUnderRoot(link, root, root), /outside the scratch root|under this checkout/);
  });
});

// --- TEST-4001: module shape -------------------------------------------------------------------------------

const EXPORTS = [
  'parseArgs', 'resolveRoots', 'readStickyProfile', 'parseCoreList', 'planCore', 'planPrune', 'copyReplace', 'underRoot',
  'isRetiredSkillWrapper', 'copilotShimIsShipped', 'extractCopilotOverrides', 'renderAdvisory', 'renderPin', 'run', 'main',
];

// The anchor lines of D-MODULE: each occurs exactly once in the module.
const ANCHORS = [
  "import { resolveFromBase } from './lib/resolve-base.mjs';",
  "import { reconcileGitignore } from './lib/gitignore-block.mjs';",
  "import { mergeHooksJson, formatSummary, formatConflicts, formatSnapshotError } from './lib/merge-hooks-json.mjs';",
  'const EXIT_FAIL = 1;',
  'const EXIT_USAGE = 2;',
  "const PROFILE_NAMES = ['core', 'extended'];",
  "const PS_NAMES = { '-targetroot': 'target', '-profile': '--profile' };",
  "const ROOT_SHIMS = ['AGENTS.md', 'CLAUDE.md', 'CODEX.md', 'GEMINI.md', 'SKILLS.md'];",
  "const SKILL_TREES = ['.claude/skills', '.agents/skills'];",
  'const isCoreListed = (coreSet, rel) => coreSet.has(rel);',
  'const overlapsSource = (roots) => isUnderOrSame(roots.targetReal, roots.srcReal);',
  "const PIN_VERSION_PREFIX = '- Template version: ';",
  'const runChild = (file, args, opts) => spawnSync(file, args, opts);',
  'const writeFd = (fd) => (s) => { fs.writeSync(fd, s); };',
  '  const roots = resolveRoots(args, io);',
  '  if (!underRoot(roots, abs)) return refuseOutside(roots, abs);',
];
const ALLOWED_LIBS = ['./lib/resolve-base.mjs', './lib/gitignore-block.mjs', './lib/merge-hooks-json.mjs'];
const NETWORK_MODULES = ['http', 'https', 'net', 'tls', 'dgram'];

// moduleShapeProblems(source): the static D-MODULE rules, as a list of problems (empty when clean).
export function moduleShapeProblems(source) {
  const problems = [];
  const specs = [];
  for (const m of source.matchAll(/^\s*import\s[^;]*?\sfrom\s+['"]([^'"]+)['"]/gm)) specs.push(m[1]);
  for (const m of source.matchAll(/^\s*import\s+['"]([^'"]+)['"]/gm)) specs.push(m[1]);
  for (const m of source.matchAll(/\b(?:import|require)\(\s*['"]([^'"]+)['"]/g)) specs.push(m[1]);
  for (const spec of specs) {
    if (!spec.startsWith('node:') && !ALLOWED_LIBS.includes(spec)) problems.push(`import of ${spec} is not a node: specifier or one of the three libraries`);
    if (NETWORK_MODULES.includes(spec.replace(/^node:/, ''))) problems.push(`import of the network module ${spec}`);
  }
  if (/[^\x00-\x7f]/.test(source)) problems.push('non-ASCII character');
  for (const anchor of ANCHORS) {
    const n = source.split(anchor).length - 1;
    if (n !== 1) problems.push(`anchor appears ${n} times: ${anchor}`);
  }
  const calls = spawnCalls(source);
  if (calls.length !== 1) problems.push(`spawnSync is called ${calls.length} times, want 1`);
  else if (!source.split('\n').some((l) => l === 'const runChild = (file, args, opts) => spawnSync(file, args, opts);')) problems.push('the one spawnSync call is not inside runChild');
  if (/process\.(stdout|stderr)/.test(source)) problems.push('references process.stdout or process.stderr');
  if (/process\.stdin|readFileSync\(\s*0\b/.test(source)) problems.push('reads standard input');
  if (/\b(exec|execSync|execFile|execFileSync|spawn|fork)\s*\(/.test(source.replace(/\bio\.spawn\b/g, ''))) problems.push('a process is started other than through spawnSync');
  if (/shell\s*:\s*true/.test(source)) problems.push('a spawn asks for a shell');
  return problems;
}

describe('TEST-4001 module shape', () => {
  test('TEST-4001 importing the module creates nothing and prints nothing', () => {
    const root = scratch('import-');
    const cwd = path.join(root, 'cwd');
    mkdirSync(cwd);
    const before = listTree(cwd);
    const r = spawnSync(process.execPath, ['--input-type=module', '-e', `await import(${JSON.stringify(MODULE_URL)});`], {
      cwd, encoding: 'utf8', env: prepareEnv(root),
    });
    assert.equal(r.status, 0, r.stderr);
    assert.equal(r.stdout, '');
    assert.equal(r.stderr, '');
    assert.deepEqual(listTree(cwd), before);
    assert.deepEqual(listTree(root).filter((n) => n !== 'cwd' && n !== 'gitconfig' && n !== 'tmp' && n !== OWN_MARKER_FILE), []);
  });

  test('TEST-4001 the module exports the D-MODULE names', async () => {
    const mod = await import(MODULE_URL);
    for (const name of EXPORTS) assert.equal(typeof mod[name], 'function', `export ${name}`);
  });

  test('TEST-4001 the module holds the static shape of D-MODULE', () => {
    const source = readFileSync(MODULE, 'utf8');
    assert.deepEqual(moduleShapeProblems(source), []);
    assert.ok(source.startsWith('#!/usr/bin/env node\n'));
    assert.ok(statSync(MODULE).mode & 0o111, 'the module is executable');
    for (const lib of MODULE_LIBS) assert.ok(existsSync(path.join(ROOT, '.aai', 'scripts', 'lib', lib)), `lib/${lib} exists`);
  });

  test('TEST-4001 the three libraries are dependency-free and ASCII', () => {
    for (const lib of ['resolve-base.mjs', 'gitignore-block.mjs']) {
      const text = readFileSync(path.join(ROOT, '.aai', 'scripts', 'lib', lib), 'utf8');
      assert.ok(!/[^\x00-\x7f]/.test(text), `${lib} is ASCII`);
      for (const m of text.matchAll(/^\s*import\s[^;]*?\sfrom\s+['"]([^'"]+)['"]/gm)) assert.ok(m[1].startsWith('node:'), `${lib} imports ${m[1]}`);
    }
  });

  test('TEST-4001 the shape check reports each violation it is meant to catch', () => {
    const good = readFileSync(MODULE, 'utf8');
    const bad = (mutated, re) => {
      const problems = moduleShapeProblems(mutated);
      assert.ok(problems.some((p) => re.test(p)), `${re} not reported: ${problems.join(' | ')}`);
    };
    bad(good.replace('{ fs.writeSync(fd, s); }', '{ process.stdout.write(s); }'), /process\.stdout|anchor appears 0/);
    bad(good.replace('{ fs.writeSync(fd, s); }', '{ process.stderr.write(s); }'), /process\.stderr|anchor appears 0/);
    bad(`${good}\n${SPAWN}('git', []);\n`, /spawnSync is called 2 times/);
    bad(`import http from 'node:http';\n${good}`, /network module/);
    bad(`import x from 'some-package';\n${good}`, /is not a node: specifier/);
    bad(`import y from './lib/other.mjs';\n${good}`, /is not a node: specifier/);
    bad(`${good}\nconst x = '\u00e9';\n`, /non-ASCII/);
    bad(`${good}\nconst EXIT_FAIL = 1;\n`, /anchor appears 2 times: const EXIT_FAIL/);
    bad(good.replace('const EXIT_USAGE = 2;', 'const EXIT_USAGE = 0;'), /anchor appears 0 times: const EXIT_USAGE/);
    bad(good.replace("import { resolveFromBase } from './lib/resolve-base.mjs';\n", ''), /anchor appears 0 times: import \{ resolveFromBase/);
    bad(good.replace('const runChild = (file, args, opts) => spawnSync(file, args, opts);', 'const runChild = (file, args, opts) => spawnSync(file, args, { ...opts });'), /anchor appears 0 times: const runChild|not inside runChild/);
    bad(`${good}\nexecSync('git');\n`, /started other than through spawnSync/);
    bad(`${good}\nprocess.stdin.read();\n`, /standard input/);
    bad(`${good}\nconst a = { shell: true };\n`, /asks for a shell/);
    // the module without its main-guard export is caught by the export list test; a source that is clean passes
    assert.deepEqual(moduleShapeProblems(good), []);
  });
});

// --- TEST-4002: arguments, help and usage ------------------------------------------------------------------

// expectedHelp(): lines 4 to 20 of the frozen bash reference after s/^# \{0,1\}//, then the two DR-1 lines.
function expectedHelp() {
  const lines = readFileSync(path.join(ROOT, REFERENCE_SH), 'utf8').split('\n').slice(3, 20).map((l) => l.replace(/^# {0,1}/, ''));
  assert.equal(lines.length, 17);
  lines.push('  powershell -NoProfile -File .aai/scripts/aai-sync.ps1 -TargetRoot <path> [-Profile core|extended]   # the bash form works too');
  lines.push('Requires Node.js 22 or later; both launchers run .aai/scripts/aai-sync.mjs.');
  return `${lines.join('\n')}\n`;
}

const USAGE = 'Usage: .aai/scripts/aai-sync.sh <path-to-target-project> [--profile core|extended]\n';
const parse = async (argv) => (await import(MODULE_URL)).parseArgs(argv);

describe('TEST-4002 arguments, help and usage', () => {
  test('TEST-4002 every accepted form resolves in any order and case', async () => {
    const want = (target, profile) => ({ target, profile, outcome: 'run', arg: '' });
    assert.deepEqual(await parse(['t']), want('t', ''));
    assert.deepEqual(await parse(['t', '--profile', 'core']), want('t', 'core'));
    assert.deepEqual(await parse(['--profile', 'core', 't']), want('t', 'core'));
    assert.deepEqual(await parse(['--profile=extended', 't']), want('t', 'extended'));
    assert.deepEqual(await parse(['t', '--profile=core', '--profile', 'extended']), want('t', 'extended'), 'the last --profile wins');
    assert.deepEqual(await parse(['-TargetRoot', 't', '-Profile', 'core']), want('t', 'core'));
    assert.deepEqual(await parse(['-profile', 'core', '-targetroot', 't']), want('t', 'core'));
    assert.deepEqual(await parse(['-TARGETROOT', 't', '-PROFILE', 'extended']), want('t', 'extended'));
    assert.deepEqual(await parse(['-TargetRoot', 'a b [c]']), want('a b [c]', ''));
    assert.deepEqual(await parse(['--', '-weird']), want('-weird', ''), '-- makes the next argument a target');
    assert.deepEqual(await parse(['--profile', 'core', '--', '--profile']), want('--profile', 'core'));
    assert.deepEqual(await parse(['--', '-h']), want('-h', ''), 'help is not special after --');
    assert.deepEqual(await parse(['-']), want('-', ''), 'a lone dash is a target');
    assert.deepEqual(await parse([]), want('', ''));
    assert.deepEqual(await parse(['']), want('', ''));
  });

  test('TEST-4002 help is a terminal outcome at its position', async () => {
    assert.equal((await parse(['-h'])).outcome, 'help');
    assert.equal((await parse(['--help'])).outcome, 'help');
    assert.equal((await parse(['t', '--profile', 'core', '-h'])).outcome, 'help');
    assert.equal((await parse(['-h', 'a', 'b'])).outcome, 'help', 'help ends parsing before a later error');
    const early = await parse(['a', 'b', '-h']);
    assert.equal(early.outcome, 'unexpected', 'an error before -h comes first');
    assert.equal(early.arg, 'b');
  });

  test('TEST-4002 help is lines 4 to 20 of the reference plus the two DR-1 lines, on stdout, exit 0', async () => {
    const root = scratch('help-');
    const help = expectedHelp();
    assert.ok(help.includes('\u2014'), 'the reference help holds the em dash');
    for (const argv of [['-h'], ['--help'], ['t', '-h']]) {
      const r = await runInProcess({ argv, root });
      assert.equal(r.code, 0, argv.join(' '));
      assert.equal(r.stdout, help);
      assert.equal(r.stderr, '');
      assert.equal(r.calls.length, 0);
    }
    const { HELP_TEXT } = await import(MODULE_URL);
    assert.equal(HELP_TEXT, help);
    assert.ok(!/[^\x00-\x7f]/.test(readFileSync(MODULE, 'utf8')), 'the module holds the em dash as an escape');
  });

  test('TEST-4002 each DR-2 usage case exits 2 with its stderr line, the usage line, no stdout and no child', async () => {
    const root = scratch('usage-');
    const cases = [
      [[], USAGE],
      [[''], USAGE],
      [['-TargetRoot'], USAGE],
      [['--profile=core'], USAGE],
      [['--profile=bogus'], USAGE],
      [['a', 'b'], `ERROR: unexpected argument: b\n${USAGE}`],
      [['a', 'b', 'c'], `ERROR: unexpected argument: b\n${USAGE}`],
      [['--bogus', 'a'], `ERROR: unexpected argument: --bogus\n${USAGE}`],
      [['a', '--bogus'], `ERROR: unexpected argument: --bogus\n${USAGE}`],
      [['-T', 'a'], `ERROR: unexpected argument: -T\n${USAGE}`],
      [['-Verbose', 'a'], `ERROR: unexpected argument: -Verbose\n${USAGE}`],
      [['a', '-targetroot', 'b'], `ERROR: unexpected argument: -targetroot\n${USAGE}`],
      [['-TargetRoot', 'a', 'b'], `ERROR: unexpected argument: b\n${USAGE}`],
      [['--profile'], `ERROR: --profile needs a value (core|extended)\n${USAGE}`],
      [['a', '--profile'], `ERROR: --profile needs a value (core|extended)\n${USAGE}`],
      [['a', '-Profile'], `ERROR: --profile needs a value (core|extended)\n${USAGE}`],
      [['a', '--profile='], `ERROR: --profile needs a value (core|extended)\n${USAGE}`],
      [['a', '--profile', ''], `ERROR: --profile needs a value (core|extended)\n${USAGE}`],
      [['a', '--profile', '--help'], `ERROR: --profile needs a value (core|extended)\n${USAGE}`],
      [['a', '--profile', 'bogus'], `ERROR: invalid --profile value: bogus (allowed: core|extended)\n${USAGE}`],
      [['a', '--profile=Core'], `ERROR: invalid --profile value: Core (allowed: core|extended)\n${USAGE}`],
      [['a', '-Profile', 'bogus'], `ERROR: invalid --profile value: bogus (allowed: core|extended)\n${USAGE}`],
    ];
    for (const [argv, stderr] of cases) {
      const r = await runInProcess({ argv, root });
      assert.equal(r.code, 2, JSON.stringify(argv));
      assert.equal(r.stderr, stderr, JSON.stringify(argv));
      assert.equal(r.stdout, '', JSON.stringify(argv));
      assert.equal(r.calls.length, 0, JSON.stringify(argv));
    }
    assert.deepEqual(listTree(root).filter((n) => n !== 'gitconfig' && n !== 'tmp' && n !== OWN_MARKER_FILE), [], 'a usage error wrote nothing');
  });

  test('TEST-4002 a missing target directory prints the bash line and exits 1; a file is no directory', async () => {
    const root = scratch('missing-');
    const missing = path.join(root, 'no-such-dir');
    const r = await runInProcess({ argv: [missing], root, target: null });
    assert.equal(r.code, 1);
    assert.equal(r.stderr, `ERROR: Target directory does not exist: ${missing}\n`);
    assert.equal(r.stdout, '');
    // a relative target resolves against the logical base and is reported as given
    const rel = await runInProcess({ argv: ['rel-missing'], root, cwd: root });
    assert.equal(rel.code, 1);
    assert.equal(rel.stderr, 'ERROR: Target directory does not exist: rel-missing\n');
    const file = path.join(root, 'a-file');
    writeFileSync(file, 'x');
    const f = await runInProcess({ argv: [file], root, target: null });
    assert.equal(f.code, 1);
    assert.equal(f.stderr, `ERROR: Target directory does not exist: ${file}\n`);
    assert.equal(r.calls.length + rel.calls.length + f.calls.length, 0);
  });

  test('TEST-4002 a real process exits 2 for a usage error and 0 for help, with nothing on the other stream', () => {
    const root = scratch('proc-');
    const target = path.join(root, 'target');
    mkdirSync(target);
    const help = runSync({ argv: [target, '-h'], root, target });
    assert.equal(help.status, 0, help.stderr);
    assert.equal(help.stdout, expectedHelp());
    assert.equal(help.stderr, '');
    const bad = runSync({ argv: [target, '--bogus'], root, target });
    assert.equal(bad.status, 2);
    assert.equal(bad.stderr, `ERROR: unexpected argument: --bogus\n${USAGE}`);
    assert.equal(bad.stdout, '');
    assert.deepEqual(listTree(target), [], 'the target is untouched');
  });
});

// --- TEST-4003: roots and the refusals before any write ------------------------------------------------------

// makeSource(root, name, { profiles, noAai, subdir }): a scratch source tree: a copy of the module and its libs under
// <name>/<aai>/scripts (so the module's own location names the root), a minimal .aai/system and the given PROFILES text.
function makeSource(root, name, { profiles = null, aai = '.aai' } = {}) {
  const src = path.join(root, name);
  const scripts = path.join(src, aai, 'scripts');
  mkdirSync(path.join(scripts, 'lib'), { recursive: true });
  copyFileSync(MODULE, path.join(scripts, 'aai-sync.mjs'));
  for (const lib of MODULE_LIBS) copyFileSync(path.join(ROOT, '.aai', 'scripts', 'lib', lib), path.join(scripts, 'lib', lib));
  if (profiles !== null) {
    mkdirSync(path.join(src, aai, 'system'), { recursive: true });
    writeFileSync(path.join(src, aai, 'system', 'PROFILES.yaml'), profiles);
  }
  return { src, script: path.join(scripts, 'aai-sync.mjs') };
}

const PROFILES_OK = 'core:\n  - .aai/AGENTS.md\nextended:\n  - .aai/x.md\n';

describe('TEST-4003 roots and the refusals before any write', () => {
  const refusalLine = (target, src) => `ERROR: target ${target} is the source ${src} or lies inside it; nothing was written.\n`;

  test('TEST-4003 a target equal to the source, inside it or at a link to it is refused before any write', () => {
    const root = scratch('self-');
    const { src, script } = makeSource(root, 'S', { profiles: PROFILES_OK });
    mkdirSync(path.join(src, 'sub', 'deeper'), { recursive: true });
    symlinkSync(src, path.join(root, 'link-to-S'));
    symlinkSync(path.join(src, 'sub'), path.join(root, 'link-to-sub'));
    prepareEnv(root);
    const before = snapshotTree(root);
    const cases = [
      [src, src],
      [path.join(src, 'sub'), path.join(src, 'sub')],
      [path.join(src, 'sub', 'deeper'), path.join(src, 'sub', 'deeper')],
      [path.join(root, 'link-to-S'), src],
      [path.join(root, 'link-to-sub'), path.join(src, 'sub')],
      [path.join(src, '.aai'), path.join(src, '.aai')],
    ];
    for (const [target, real] of cases) {
      for (const extra of [[], ['--profile', 'core']]) {
        const r = runSync({ argv: [target, ...extra], root, target, script });
        assert.equal(r.status, 1, `${target} ${extra.join(' ')}`);
        assert.equal(r.stderr, refusalLine(real, src));
        assert.equal(r.stdout, '', 'a refusal before the header prints nothing on stdout');
      }
    }
    assert.deepEqual(snapshotTree(root), before, 'the target and the source are byte-identical afterwards');
  });

  test('TEST-4003 DR-32 a target that names the source with other letter case is refused by identity, on a case-insensitive file system', (t) => {
    const root = scratch('case-');
    const { src, script } = makeSource(root, 'Src', { profiles: PROFILES_OK });
    mkdirSync(path.join(src, 'Sub'));
    const upper = path.join(root, 'SRC');
    if (!existsSync(upper)) {
      t.skip('the scratch file system is case-sensitive, a case variant names no directory');
      return;
    }
    prepareEnv(root);
    const before = snapshotTree(root);
    for (const target of [upper, path.join(root, 'SRC', 'sUB')]) {
      const r = runSync({ argv: [target], root, target, script });
      assert.equal(r.status, 1, `${target}: ${r.stderr}`);
      assert.match(r.stderr, /^ERROR: target .* is the source .* or lies inside it; nothing was written\.\n$/, r.stderr);
      assert.equal(r.stdout, '');
    }
    assert.deepEqual(snapshotTree(root), before, 'the source is byte-identical afterwards');
  });

  test('TEST-4003 DR-33 a source inside a managed entry of the target is refused before any write', () => {
    const root = scratch('nested-');
    const target = path.join(root, 'project');
    mkdirSync(path.join(target, '.aai'), { recursive: true });
    const { src, script } = makeSource(path.join(target, '.aai'), 'upstream', { profiles: PROFILES_OK });
    prepareEnv(root);
    const before = snapshotTree(root);
    for (const extra of [[], ['--profile', 'core']]) {
      const r = runSync({ argv: [target, ...extra], root, target, script });
      assert.equal(r.status, 1, r.stderr);
      assert.equal(r.stderr, `ERROR: the source ${realpathSync(src)} lies inside .aai of the target ${target}, which the sync replaces; nothing was written.\n`);
      assert.equal(r.stdout, '');
    }
    assert.deepEqual(snapshotTree(root), before, 'the source and the target are byte-identical afterwards');
  });

  // DR-35: a file system may report no inode (0) or one above 2**53 (Windows file ids), which a Number comparison reads as equal.
  test('TEST-4003 DR-35 a file system that reports no inode does not make every directory the source, and a target stays under the root by spelling', async () => {
    const { resolveRoots, underRoot } = await import(MODULE_URL);
    const root = scratch('zero-ino-');
    const target = path.join(root, 'target');
    mkdirSync(target);
    const env = prepareEnv(root);
    const realStat = nodeFs.statSync;
    // every stat of the module reads inode 0, as a file system without inodes does (the test code itself holds the named import)
    nodeFs.statSync = (p, o) => {
      const st = realStat(p, o);
      return Object.assign(Object.create(Object.getPrototypeOf(st)), st, { ino: typeof st.ino === 'bigint' ? 0n : 0 });
    };
    try {
      const roots = resolveRoots({ target }, { env, cwd: root });
      assert.equal(roots.refusal, undefined, `a target outside the source is not refused: ${roots.refusal?.refusal?.line ?? JSON.stringify(roots.refusal)}`);
      assert.equal(typeof roots.targetIno, 'bigint', 'the identity is read as bigint');
      assert.equal(typeof roots.targetDev, 'bigint');
      assert.equal(underRoot(roots, path.join(target, '.aai', 'x')), true, 'a path under the target is allowed');
      assert.equal(underRoot(roots, path.join(root, 'elsewhere', 'x')), false, 'a path outside the target is refused');
      const self = resolveRoots({ target: ROOT }, { env, cwd: root });
      assert.ok(self.refusal, 'the source itself is still refused, by spelling');
    } finally {
      nodeFs.statSync = realStat;
    }
  });

  test('TEST-4003 DR-35 a real path that realpathSync.native cannot read is read with realpathSync, and the roots are still captured', async () => {
    const { resolveRoots } = await import(MODULE_URL);
    const root = scratch('no-native-');
    const target = path.join(root, 'target');
    mkdirSync(target);
    const env = prepareEnv(root);
    const native = nodeFs.realpathSync.native;
    nodeFs.realpathSync.native = () => { throw new Error('no native real path here'); };
    try {
      const roots = resolveRoots({ target }, { env, cwd: root });
      assert.equal(roots.refusal, undefined, JSON.stringify(roots.refusal));
      assert.equal(roots.targetReal, realpathSync(target));
      assert.equal(roots.srcReal, realpathSync(ROOT));
    } finally {
      nodeFs.realpathSync.native = native;
    }
  });

  test('TEST-4003 a target holding the source is allowed past the refusals', () => {
    const root = scratch('vendored-');
    const target = path.join(root, 'project');
    mkdirSync(target);
    const { src, script } = makeSource(target, 'vendor-aai', { profiles: PROFILES_OK });
    const r = runSync({ argv: [target], root, target, script });
    assert.ok(!/is the source|root of its file system|Source missing|requires the manifest/.test(r.stderr), r.stderr);
    assert.ok(r.stdout.startsWith(`Syncing AAI from: ${src}\nTarget project:     ${target}\nProfile:            extended\n`), r.stdout);
  });

  test('TEST-4003 a file system root is refused; a source without .aai is refused', async () => {
    const root = scratch('rootsrc-');
    const { resolveRoots } = await import(MODULE_URL);
    // resolveRoots only reads: it returns the refusal for the root of the file system and never writes
    const fsRoot = path.parse(realpathSync(root)).root;
    const refused = resolveRoots({ target: fsRoot, profile: '', outcome: 'run', arg: '' }, { env: prepareEnv(root), cwd: root, scriptPath: MODULE });
    assert.equal(refused.refusal.code, 1);
    assert.equal(refused.refusal.line, `ERROR: target ${fsRoot} is the root of its file system (source ${realpathSync(ROOT)}); nothing was written.`);
    assert.equal(refused.refusal.line.includes('nothing was written'), true);
    // a module copy whose root holds no .aai: the module's own location names the root
    const copyRoot = path.join(root, 'm');
    const scripts = path.join(copyRoot, 'x', 'scripts');
    mkdirSync(path.join(scripts, 'lib'), { recursive: true });
    copyFileSync(MODULE, path.join(scripts, 'aai-sync.mjs'));
    for (const lib of MODULE_LIBS) copyFileSync(path.join(ROOT, '.aai', 'scripts', 'lib', lib), path.join(scripts, 'lib', lib));
    const target = path.join(root, 'target');
    mkdirSync(target);
    prepareEnv(root);
    const before = snapshotTree(root);
    const r = runSync({ argv: [target], root, target, script: path.join(scripts, 'aai-sync.mjs') });
    assert.equal(r.status, 1);
    assert.equal(r.stderr, `ERROR: Source missing .aai/ directory: ${copyRoot}\n`);
    assert.equal(r.stdout, '');
    assert.deepEqual(snapshotTree(root), before);
  });

  test('TEST-4003 a missing manifest and an empty core list are refused for the core profile only', () => {
    const root = scratch('manifest-');
    const target = path.join(root, 'target');
    mkdirSync(target);
    const header = (src) => `Syncing AAI from: ${src}\nTarget project:     ${target}\nProfile:            core\n`;
    const noManifest = makeSource(root, 'S1');
    mkdirSync(path.join(noManifest.src, '.aai', 'system'), { recursive: true });
    const emptyList = makeSource(root, 'S2', { profiles: 'core:\nextended:\n  - .aai/x.md\n' });
    const noBlock = makeSource(root, 'S3', { profiles: 'extended:\n  - .aai/x.md\n' });
    const crlf = makeSource(root, 'S4', { profiles: 'core:\r\n  - .aai/AGENTS.md\r\n' });
    const crlfEmpty = makeSource(root, 'S4b', { profiles: 'core:\r\nextended:\r\n  - .aai/x.md\r\n' });
    prepareEnv(root);
    const before = snapshotTree(root);
    let r = runSync({ argv: [target, '--profile', 'core'], root, target, script: noManifest.script });
    assert.equal(r.status, 1);
    assert.equal(r.stderr, `ERROR: --profile core requires the manifest: ${path.join(noManifest.src, '.aai', 'system', 'PROFILES.yaml')}\n`);
    assert.equal(r.stdout, header(noManifest.src));
    for (const s of [emptyList, noBlock, crlfEmpty]) {
      r = runSync({ argv: [target, '--profile', 'core'], root, target, script: s.script });
      assert.equal(r.status, 1, s.src);
      assert.equal(r.stderr, `ERROR: no core entries found in ${path.join(s.src, '.aai', 'system', 'PROFILES.yaml')}\n`);
      assert.equal(r.stdout, header(s.src));
    }
    assert.deepEqual(snapshotTree(root), before, 'nothing changed');
    // the extended profile never reads the manifest: a missing one passes the refusals
    r = runSync({ argv: [target, '--profile', 'extended'], root, target, script: noManifest.script });
    assert.ok(!/requires the manifest|no core entries/.test(r.stderr), r.stderr);
    assert.match(r.stdout, /^Profile: {12}extended$/m);
    // a valid core list passes them too
    const ok = makeSource(root, 'S5', { profiles: PROFILES_OK });
    r = runSync({ argv: [target, '--profile', 'core'], root, target, script: ok.script });
    assert.ok(!/requires the manifest|no core entries/.test(r.stderr), r.stderr);
    // DR-34: the same list with CRLF line ends (a Windows checkout) passes them as well; an empty CRLF core block still does not
    r = runSync({ argv: [target, '--profile', 'core'], root, target, script: crlf.script });
    assert.ok(!/requires the manifest|no core entries/.test(r.stderr), r.stderr);
    assert.equal(r.status, 0, r.stderr);
  });

  test('TEST-4003 the sticky profile is read from the pin before the refusals of the core profile', () => {
    const root = scratch('sticky-');
    const target = path.join(root, 'target');
    mkdirSync(path.join(target, '.aai', 'system'), { recursive: true });
    const { src, script } = makeSource(root, 'S', { profiles: 'extended:\n  - .aai/x.md\n' });
    writeFileSync(path.join(target, '.aai', 'system', 'AAI_PIN.md'), '- Profile: core  \r\n- Profile: extended\r\n');
    let r = runSync({ argv: [target], root, target, script });
    assert.equal(r.status, 1);
    assert.equal(r.stderr, `ERROR: no core entries found in ${path.join(src, '.aai', 'system', 'PROFILES.yaml')}\n`);
    // the flag wins over the pin; an invalid pin value falls back to extended
    r = runSync({ argv: [target, '--profile', 'extended'], root, target, script });
    assert.match(r.stdout, /^Profile: {12}extended$/m);
    writeFileSync(path.join(target, '.aai', 'system', 'AAI_PIN.md'), '- Profile: bogus\n- Profile: core\n');
    r = runSync({ argv: [target], root, target, script });
    assert.match(r.stdout, /^Profile: {12}extended$/m);
  });

  test('TEST-4003 readStickyProfile and parseCoreList read the pin and the manifest as the bash twin did', async () => {
    const { readStickyProfile, parseCoreList } = await import(MODULE_URL);
    const root = scratch('readers-');
    const pinDir = path.join(root, '.aai', 'system');
    mkdirSync(pinDir, { recursive: true });
    const pin = (text) => writeFileSync(path.join(pinDir, 'AAI_PIN.md'), text);
    assert.equal(readStickyProfile(root), '', 'no pin');
    pin('- Profile: core\n');
    assert.equal(readStickyProfile(root), 'core');
    pin('x\r\n- Profile: extended \t\r\n');
    assert.equal(readStickyProfile(root), 'extended');
    pin('- Profile: bogus\n- Profile: core\n');
    assert.equal(readStickyProfile(root), '', 'the first line decides, then it is validated');
    pin(' - Profile: core\n- profile: core\n');
    assert.equal(readStickyProfile(root), '');
    assert.deepEqual(parseCoreList(''), []);
    assert.deepEqual(parseCoreList('extended:\n  - a\n'), []);
    assert.deepEqual(parseCoreList('core:\n  - a\n  - b  \t\n# c\n  - skipped\n'), ['a', 'b'], 'a line starting with a non-space closes the block');
    assert.deepEqual(parseCoreList('core:\n  - a\n\n  - b\n'), ['a', 'b'], 'a blank line does not close the block');
    assert.deepEqual(parseCoreList('core:\n  - a\n\t- b\n  - c\n'), ['a'], 'a tab-indented line closes the block');
    assert.deepEqual(parseCoreList('core:  \n  - a\n'), [], 'core: followed by spaces does not open it');
    // DR-34: a checkout with CRLF line ends (core.autocrlf on Windows) reads as the LF text does; the CR is no part of a line
    assert.deepEqual(parseCoreList('core:\r\n  - a\r\n'), ['a'], 'a CR after core: is the end of the line, not a character of it');
    assert.deepEqual(parseCoreList('core:\r\n  - a\r\n\r\n  - b \t\r\nextended:\r\n  - z\r\n'), ['a', 'b'], 'a CRLF manifest: blank lines stay inside, the next key closes the block');
    assert.deepEqual(parseCoreList('core:\r\n  - a\r\n\tx\r\n  - c\r\n'), ['a'], 'a CRLF tab-indented line still closes the block');
    assert.deepEqual(parseCoreList('core: \r\n  - a\r\n'), [], 'core: with a trailing space does not open the block under CRLF either');
    assert.deepEqual(parseCoreList('core:\n  - a\r\nextended:\n  - z\ncore:\n  - c\n'), ['a', 'c']);
    assert.deepEqual(parseCoreList('core:\n  - \n  -   \n  - d\n'), ['d'], 'empty entries are dropped');
  });

  test('TEST-4003 underRoot allows only the target and refuses the source, outside paths, links out and a changed target', async () => {
    const { underRoot, resolveRoots, guardMutation } = await import(MODULE_URL);
    const root = scratch('under-');
    const target = path.join(root, 'target');
    const outside = path.join(root, 'outside');
    mkdirSync(target);
    mkdirSync(outside);
    const env = prepareEnv(root);
    const roots = resolveRoots({ target, profile: '', outcome: 'run', arg: '' }, { env, cwd: root, scriptPath: MODULE });
    assert.equal(roots.targetReal, realpathSync(target));
    assert.equal(underRoot(roots, path.join(target, '.aai', 'x.md')), true, 'a path about to be created under the target');
    assert.equal(underRoot(roots, path.join(target, 'a', 'b', 'c', 'd')), true, 'the nearest existing ancestor decides');
    assert.equal(underRoot(roots, path.join(outside, 'x')), false);
    assert.equal(underRoot(roots, target), false, 'the target itself has its parent outside');
    assert.equal(underRoot(roots, path.join(ROOT, 'x')), false, 'the source is never a destination');
    symlinkSync(outside, path.join(target, 'out-link'));
    assert.equal(underRoot(roots, path.join(target, 'out-link', 'x')), false, 'a link leaving the target');
    assert.equal(guardMutation(roots, path.join(target, 'ok')), null);
    const refused = guardMutation(roots, path.join(outside, 'x'));
    assert.equal(refused.refusal.code, 1);
    assert.equal(refused.refusal.line, `ERROR: ${path.relative(roots.target, path.join(outside, 'x'))} resolves outside the target ${roots.target}; refusing to write or delete there.`);
    // the target replaced by another directory of the same name changes its identity
    const moved = path.join(root, 'moved');
    renameSync(target, moved);
    mkdirSync(target);
    assert.equal(underRoot(roots, path.join(target, 'x')), false, 'the identity of the target changed');
  });
});

// --- TEST-4005 and TEST-4006 (run 2): the .gitignore reconcile and the dropped legacy moves --------------------------

const GITIGNORE_LIB_URL = pathToFileURL(path.join(ROOT, '.aai', 'scripts', 'lib', 'gitignore-block.mjs')).href;
const REAL_LIST = path.join(ROOT, '.aai', 'system', 'RUNTIME_IGNORE.list');
const PS1_MARKER = '# AAI runtime sidecars (seeded by aai-sync.ps1; per-dev, never commit)';
const BOOTSTRAP_MARKER = '# AAI runtime sidecars (seeded by aai-bootstrap; per-dev, never commit)';
const POINTER_1 = '  NOTE: If docs/ai/STATE.yaml or docs/ai/LOOP_TICKS.jsonl is still tracked,\n';
const POINTER_2 = '        run bash .aai/scripts/migrate-state-to-local.sh (or powershell -NoProfile -File .aai/scripts/migrate-state-to-local.ps1) in the target project.\n';

// refSource(root, { list }): a scratch source tree holding the frozen bash twin and its library (the module-side engine
// files are removed) and, when list is true, the real RUNTIME_IGNORE.list. Returns the root of the source.
function refSource(root, { list = true } = {}) {
  const src = path.join(root, 'refsrc');
  mkdirSync(path.join(src, '.aai', 'system'), { recursive: true });
  materializeSyncReference(src);
  if (list) copyFileSync(REAL_LIST, path.join(src, '.aai', 'system', 'RUNTIME_IGNORE.list'));
  return src;
}

// refSync(root, src, target): runs the frozen bash twin from the scratch source into the target through runSync.
function refSync(root, src, target) {
  const r = runSync({ argv: [target], root, target, script: path.join(src, '.aai', 'scripts', 'aai-sync.sh'), exe: 'bash' });
  assert.equal(r.status, 0, `the bash reference failed: ${r.stderr}`);
  return r;
}

// gitignoreLines(stdout, target): the lines of a run that concern the .gitignore, the target path replaced by <T>, the
// second line of the pointer (its text differs by design, DR-14) left out.
function gitignoreLines(stdout, target) {
  return stdout.split('\n')
    .filter((l) => /\.gitignore|^  NOTE: If docs\/ai\/STATE|skipped runtime-sidecar/.test(l))
    .map((l) => l.split(target).join('<T>'));
}

const readIf = (file) => (existsSync(file) ? readFileSync(file) : null);

// The K09 inputs: [label, initial .gitignore text or null, source list present, target list text or null]. A block built
// from a first bash run on an empty target is the managed text.
function k09Cases(managed) {
  const crlf = (t) => t.replace(/\n/g, '\r\n');
  return [
    ['K09a no .gitignore', null, true, null],
    ['K09a2 an LF .gitignore without the managed lines', 'node_modules/\ndist/\n', true, null],
    ['K09a3 an LF .gitignore without a final newline', 'node_modules/\ndist', true, null],
    ['K09b a CRLF .gitignore', crlf('node_modules/\n.agents/skills/\n.claude/skills/\ndocs/ai/STATE.yaml\n'), true, null],
    ['K09c every managed block twice', `${managed}\n${managed}`, true, null],
    ['K09c2 every managed block twice with blank runs and a project line between', `build/\n\n\n${managed}\n\nmine.log\n${managed}\n\n\n`, true, null],
    ['K09c3 every managed block twice, CRLF', crlf(`${managed}${managed}`), true, null],
    ['K09d only .aai/cache/ present (prefix reading)', 'src/\n.aai/cache/\n', true, null],
    ['K09d2 a line starting with .aai/ is enough for the .aai/ block', '.aai/anything\n', true, null],
    ['K09e a 200 KB .gitignore with the managed lines at the top', `${managed}${'padding/line/of/a/large/ignore/file\n'.repeat(5800)}`, true, null],
    ['K09f the .ps1 marker text already present', `${PS1_MARKER}\nlogs/\n`, true, null],
    ['K09f2 the bootstrap marker text already present', `${BOOTSTRAP_MARKER}\ndocs/ai/STATE.yaml\n`, true, null],
    ['K09g no list in the source, the target list used', 'x/\n', false, 'custom/pattern-one\ncustom/pattern-two\n# comment\n\ncustom/pattern-one\n'],
    ['K09h no list anywhere (the note)', 'x/\n', false, null],
    ['K09i prefix-only: the marker prefix alone', '# AAI runtime sidecars\n', true, null],
    ['K09j managed lines with trailing whitespace are not managed lines (DR-12: matched exactly, never after TrimEnd)', 'build/\n.aai/ \n.aai/\n.aai/cache/\t\n.aai/cache/\n.aai/\n', true, null],
  ];
}

describe('TEST-4005 the .gitignore reconcile', () => {
  test('TEST-4005 reconcileGitignore leaves the bytes of the frozen bash reference for the K09 inputs, a second run changes nothing', async () => {
    const { reconcileGitignore } = await import(GITIGNORE_LIB_URL);
    const root = scratch('gi-');
    const withList = refSource(root);
    const noList = path.join(root, 'refsrc-nolist');
    mkdirSync(path.join(noList, '.aai', 'system'), { recursive: true });
    materializeSyncReference(noList);
    // the managed text: what the bash twin writes into an empty target
    const first = path.join(root, 'managed-target');
    mkdirSync(first);
    refSync(root, withList, first);
    const managed = readFileSync(path.join(first, '.gitignore'), 'utf8');
    assert.ok(managed.includes('# AAI runtime sidecars (seeded from .aai/system/RUNTIME_IGNORE.list; per-dev, never commit)'));
    assert.ok(managed.includes('docs/ai/STATE.yaml') && managed.includes('.agents/skills/') && managed.includes('.wrangler/'));
    let n = 0;
    for (const [label, initial, sourceList, targetList] of k09Cases(managed)) {
      n += 1;
      const tb = path.join(root, `bash-${n}`);
      const tn = path.join(root, `node-${n}`);
      for (const t of [tb, tn]) {
        mkdirSync(path.join(t, '.aai', 'system'), { recursive: true });
        if (initial !== null) writeFileSync(path.join(t, '.gitignore'), initial, 'latin1');
        if (targetList !== null) writeFileSync(path.join(t, '.aai', 'system', 'RUNTIME_IGNORE.list'), targetList);
      }
      // The bash twin replaces the target's .aai/system before it reconciles, so a list that only the target holds is gone
      // by then (the copy step, not the reconcile). The twin therefore runs with that same list in its source: the list in
      // effect is the one under test, and the module reads it from the target.
      let refSrc = sourceList ? withList : noList;
      if (!sourceList && targetList !== null) {
        refSrc = path.join(root, `refsrc-custom-${n}`);
        mkdirSync(path.join(refSrc, '.aai', 'system'), { recursive: true });
        materializeSyncReference(refSrc);
        writeFileSync(path.join(refSrc, '.aai', 'system', 'RUNTIME_IGNORE.list'), targetList);
      }
      const ref = refSync(root, refSrc, tb);
      const out = [];
      const srcList = sourceList ? path.join(withList, '.aai', 'system', 'RUNTIME_IGNORE.list') : path.join(noList, '.aai', 'system', 'RUNTIME_IGNORE.list');
      reconcileGitignore(tn, { srcList, targetList: path.join(tn, '.aai', 'system', 'RUNTIME_IGNORE.list'), out: (t) => out.push(t) });
      const want = readIf(path.join(tb, '.gitignore'));
      const got = readIf(path.join(tn, '.gitignore'));
      assert.ok(want !== null && got !== null, `${label}: both targets hold a .gitignore`);
      assert.equal(got.toString('latin1'), want.toString('latin1'), `${label}: the bytes of the bash reference`);
      const wantLines = gitignoreLines(ref.stdout, tb);
      const gotLines = gitignoreLines(out.join(''), tn).filter((l) => !l.startsWith('        run bash'));
      assert.deepEqual(gotLines, wantLines.map((l) => l.replace(/^ {8}run bash.*$/, '')).filter(Boolean), `${label}: the printed lines`);
      // a second run: byte-identical, nothing printed
      const again = [];
      reconcileGitignore(tn, { srcList, targetList: path.join(tn, '.aai', 'system', 'RUNTIME_IGNORE.list'), out: (t) => again.push(t) });
      assert.equal(readFileSync(path.join(tn, '.gitignore'), 'latin1'), got.toString('latin1'), `${label}: a second run is byte-identical`);
      // the missing-list note is printed on every run (the bash twin does the same); nothing else is
      assert.deepEqual(again.filter((l) => !l.startsWith('  skipped runtime-sidecar gitignore seed: ')), [], `${label}: a second run prints nothing`);
      assert.deepEqual(listTree(tn).filter((f) => f.includes('aai-dedup')), [], `${label}: no temporary sibling is left`);
    }
    assert.ok(n >= 12, 'the K09 inputs ran');
  });

  test('TEST-4005 a 200 KB .gitignore with the managed lines at the top is not re-appended, whatever the pipe buffer holds', async () => {
    const { reconcileGitignore } = await import(GITIGNORE_LIB_URL);
    const root = scratch('gi-big-');
    const src = refSource(root);
    const seed = path.join(root, 'seed');
    mkdirSync(seed);
    refSync(root, src, seed);
    const big = `${readFileSync(path.join(seed, '.gitignore'), 'utf8')}${'a/line/that/pads/the/ignore/file\n'.repeat(7000)}`;
    assert.ok(big.length > 200 * 1024, 'the file is larger than 200 KB');
    const t = path.join(root, 't');
    mkdirSync(t);
    writeFileSync(path.join(t, '.gitignore'), big);
    const out = [];
    reconcileGitignore(t, { srcList: path.join(src, '.aai', 'system', 'RUNTIME_IGNORE.list'), targetList: path.join(t, 'none.list'), out: (x) => out.push(x) });
    reconcileGitignore(t, { srcList: path.join(src, '.aai', 'system', 'RUNTIME_IGNORE.list'), targetList: path.join(t, 'none.list'), out: (x) => out.push(x) });
    assert.equal(readFileSync(path.join(t, '.gitignore'), 'utf8'), big, 'two runs left the file unchanged');
    assert.deepEqual(out, [], 'nothing printed');
  });

  test('TEST-4005 the runtime-state block prints the DR-14 pointer naming both launchers, and a missing list prints the note', async () => {
    const { reconcileGitignore } = await import(GITIGNORE_LIB_URL);
    const root = scratch('gi-ptr-');
    const t = path.join(root, 't');
    mkdirSync(t);
    const out = [];
    const list = path.join(t, '.aai', 'system', 'RUNTIME_IGNORE.list');
    reconcileGitignore(t, { srcList: path.join(root, 'no-src.list'), targetList: list, out: (x) => out.push(x) });
    const gi = path.join(t, '.gitignore');
    assert.deepEqual(out, [
      `  Added .aai/ to ${gi}\n`,
      `  skipped runtime-sidecar gitignore seed: ${list} missing\n`,
      `  Added .cloudflare-publish* to ${gi}\n`,
      `  Added .wrangler/ to ${gi}\n`,
      `  Added .aai/cache/ to ${gi}\n`,
      `  Added docs/ai/reports runtime ignore rules to ${gi}\n`,
      `  Added agent skill sync patterns to ${gi}\n`,
      `  Added AAI per-dev runtime state patterns to ${gi}\n`,
      POINTER_1,
      POINTER_2,
    ]);
    // no pointer when the state patterns are already present, and none when the file is already complete
    const second = [];
    reconcileGitignore(t, { srcList: '', targetList: list, out: (x) => second.push(x) });
    assert.deepEqual(second.filter((l) => !l.startsWith('  skipped runtime-sidecar')), []);
    assert.equal(POINTER_2.includes('migrate-state-to-local.sh') && POINTER_2.includes('migrate-state-to-local.ps1'), true);
  });

  test('TEST-4005 seedRuntimeGitignore matches exact lines on a CR-free read, writes the marker once and by prefix, and reports the count', async () => {
    const { seedRuntimeGitignore, AAI_GITIGNORE_MARKER_PREFIX } = await import(GITIGNORE_LIB_URL);
    assert.equal(AAI_GITIGNORE_MARKER_PREFIX, '# AAI runtime sidecars');
    const root = scratch('gi-seed-');
    const list = path.join(root, 'list');
    const file = path.join(root, '.gitignore');
    writeFileSync(list, '# comment\n\na/one\r\nb/two\na/one\n');
    // CRLF list lines match as LF lines; a duplicate list entry is written once per occurrence (the bash contract)
    writeFileSync(file, 'x\r\nb/two\r\n');
    assert.equal(seedRuntimeGitignore(file, list, '# AAI runtime sidecars (marker)'), `${file} add 2 AAI runtime sidecar pattern(s)`);
    assert.equal(readFileSync(file, 'latin1'), 'x\r\nb/two\r\n\n# AAI runtime sidecars (marker)\na/one\na/one\n');
    assert.equal(seedRuntimeGitignore(file, list, '# AAI runtime sidecars (marker)'), '', 'nothing to add: no note');
    // a legacy marker (any text with the prefix) suppresses the new marker
    writeFileSync(file, '# AAI runtime sidecars (seeded by something else)\n');
    seedRuntimeGitignore(file, list, '# AAI runtime sidecars (marker)');
    assert.equal(readFileSync(file, 'utf8'), '# AAI runtime sidecars (seeded by something else)\n\na/one\nb/two\na/one\n');
    // a missing list writes nothing
    const before = readFileSync(file);
    assert.equal(seedRuntimeGitignore(file, path.join(root, 'absent'), 'm'), `skipped runtime-sidecar gitignore seed: ${path.join(root, 'absent')} missing`);
    assert.deepEqual(readFileSync(file), before);
    // an empty list is not a note and writes nothing
    writeFileSync(list, '# only a comment\n\n');
    assert.equal(seedRuntimeGitignore(file, list, 'm'), '');
    assert.deepEqual(readFileSync(file), before);
  });

  test('TEST-4005 the self-heal keeps the first managed line, leaves project lines alone, keeps CRLF and rewrites only for a managed duplicate', async () => {
    const { reconcileGitignore } = await import(GITIGNORE_LIB_URL);
    const root = scratch('gi-heal-');
    const src = refSource(root);
    const list = path.join(src, '.aai', 'system', 'RUNTIME_IGNORE.list');
    const seed = path.join(root, 'seed');
    mkdirSync(seed);
    refSync(root, src, seed);
    const managed = readFileSync(path.join(seed, '.gitignore'), 'utf8');
    const run = (initial) => {
      const t = path.join(root, `h-${Math.random().toString(36).slice(2, 8)}`);
      mkdirSync(t);
      writeFileSync(path.join(t, '.gitignore'), initial);
      const out = [];
      reconcileGitignore(t, { srcList: list, targetList: path.join(t, 'none'), out: (x) => out.push(x) });
      return { text: readFileSync(path.join(t, '.gitignore'), 'utf8'), out: out.join('').split(t).join('<T>'), dir: t };
    };
    // a project duplicate is never touched; a managed duplicate is removed once and the blank runs collapse
    const a = run(`dup\ndup\n\n\n\n${managed}.wrangler/\n`);
    assert.ok(a.text.startsWith('dup\ndup\n\n'), 'project duplicates stay');
    assert.equal(a.text.split('\n').filter((l) => l === '.wrangler/').length, 1);
    assert.ok(!/\n\n\n/.test(a.text), 'runs of blank lines collapsed');
    assert.ok(a.out.includes('  De-duplicated 1 stale AAI-managed line(s) in <T>/.gitignore\n'), a.out);
    // blank runs alone, without a managed duplicate, leave the file as it is
    const b = run('x\n\n\n\ny\n');
    assert.ok(b.text.startsWith('x\n\n\n\ny\n'), 'no managed duplicate: the file is not rewritten');
    // CRLF is kept when any CR exists
    const c = run(managed.replace(/\n/g, '\r\n') + '.wrangler/\r\n');
    assert.ok(c.text.includes('\r\n') && !/[^\r]\n/.test(c.text), 'every line ends with CRLF');
    // a leftover temporary sibling this run did not create is never overwritten
    const d = path.join(root, 'h-exists');
    mkdirSync(d);
    writeFileSync(path.join(d, '.gitignore'), `${managed}.wrangler/\n`);
    const tmp = path.join(d, `.gitignore.aai-dedup.${process.pid}`);
    writeFileSync(tmp, 'foreign');
    const before = readFileSync(path.join(d, '.gitignore'), 'utf8');
    assert.throws(() => reconcileGitignore(d, { srcList: list, targetList: path.join(d, 'none'), out: () => {} }), /EEXIST/);
    assert.equal(readFileSync(tmp, 'utf8'), 'foreign', 'the foreign temporary is left in place');
    assert.equal(readFileSync(path.join(d, '.gitignore'), 'utf8'), before, 'the file is unchanged');
  });

  test('TEST-4005 the lib starts no child process and holds no shell', () => {
    const text = readFileSync(path.join(ROOT, '.aai', 'scripts', 'lib', 'gitignore-block.mjs'), 'utf8');
    const code = text.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');
    assert.ok(!/child_process|spawn|exec\w*\(|\bshell\b|\|\s*grep|process\.stdout|process\.stderr/.test(code), 'no child process, shell or pipe');
    assert.equal(text.split("export const AAI_GITIGNORE_MARKER_PREFIX = '# AAI runtime sidecars';").length - 1, 1, 'the prefix constant, once');
    assert.ok(!/[^\x00-\x7f]/.test(text), 'ASCII only');
  });
});

// --- TEST-4006 -----------------------------------------------------------------------------------------------------

// The dropped moves of D-LEGACY, as the paths a pre-.aai layout holds. Assembled from parts so that this file names
// each path as data and the module source can be scanned for the same tokens.
const LEGACY_FILES = {
  'ai/notes.md': 'legacy ai dir\n',
  'scripts/tool.sh': '#!/bin/sh\necho mine\n',
  'scripts/triage.sh': '#!/bin/sh\necho project-owned triage\n',
  'scripts/ai-os-old.sh': '#!/bin/sh\necho old name\n',
  'PLAYBOOK.md': 'project-owned playbook\n',
  'docs/workflow/flow.md': 'workflow\n',
  'docs/roles/role.md': 'role\n',
  'docs/templates/t.md': 'template\n',
  'docs/ai/AUTONOMOUS_LOOP.md': 'loop\n',
  'docs/ai/SUPERPOWERS_INTEGRATION.md': 'sp\n',
  'docs/ai/DYNAMIC_SKILLS.md': 'ds\n',
  'docs/ai/PRICING.yaml': 'pricing\n',
  'docs/ai/AAI_PIN.md': 'pin\n',
  'docs/ai/LOCKS.md': 'locks\n',
  'docs/knowledge/PATTERNS_UNIVERSAL.md': 'patterns\n',
  'docs/specs/SPEC-1.md': 'project spec\n',
  'README.md': 'project readme\n',
};
// Tokens of the dropped moves; the module and the two libs hold none of them (the pointer to the state-migration
// script is kept and is not one of them).
const DROPPED_TOKENS = [
  'MIGRATE', 'Legacy', 'PLAYBOOK', 'AUTONOMOUS_LOOP', 'SUPERPOWERS_INTEGRATION', 'DYNAMIC_SKILLS', 'PATTERNS_UNIVERSAL',
  'ai-os-', 'docs/workflow', 'docs/roles', 'docs/templates', 'docs/ai/PRICING', 'docs/ai/AAI_PIN', 'docs/ai/LOCKS',
];
// outsideManaged(dir): the snapshot rows of the legacy layout and of the project-owned paths around it. The module now
// writes the managed set (the layer, the shims, the seeds), so only the paths the dropped moves reached are compared.
const LEGACY_ROOTS = ['ai', 'scripts', 'PLAYBOOK.md', 'README.md', 'docs/workflow', 'docs/roles', 'docs/templates', 'docs/specs',
  'docs/ai/AUTONOMOUS_LOOP.md', 'docs/ai/SUPERPOWERS_INTEGRATION.md', 'docs/ai/DYNAMIC_SKILLS.md', 'docs/ai/PRICING.yaml',
  'docs/ai/AAI_PIN.md', 'docs/ai/LOCKS.md', 'docs/knowledge/PATTERNS_UNIVERSAL.md'];
const outsideManaged = (dir) => snapshotTree(dir).filter((row) => {
  const rel = row.split('\t')[0];
  return LEGACY_ROOTS.some((r) => rel === r || rel.startsWith(`${r}/`));
});

function writeLegacy(target) {
  for (const [rel, body] of Object.entries(LEGACY_FILES)) {
    mkdirSync(path.dirname(path.join(target, rel)), { recursive: true });
    writeFileSync(path.join(target, rel), body);
  }
}

describe('TEST-4006 the legacy-layout moves are dropped', () => {
  test('TEST-4006 the frozen bash twin removes the legacy layout (the fixture reaches the dropped moves)', () => {
    const root = scratch('lg-ref-');
    const src = refSource(root);
    const t = path.join(root, 't');
    mkdirSync(t);
    writeLegacy(t);
    const r = refSync(root, src, t);
    assert.match(r.stdout, /MIGRATE removed legacy/);
    assert.equal(existsSync(path.join(t, 'PLAYBOOK.md')), false, 'the twin deleted a project-owned playbook');
    assert.equal(existsSync(path.join(t, 'ai')), false);
    assert.equal(existsSync(path.join(t, 'docs', 'workflow', 'flow.md')), false);
  });

  test('TEST-4006 the module and the reconcile keep every legacy path byte-identical and print no MIGRATE or Legacy line', async () => {
    const { reconcileGitignore } = await import(GITIGNORE_LIB_URL);
    const root = scratch('lg-');
    const t = path.join(root, 't');
    mkdirSync(t);
    writeLegacy(t);
    const before = outsideManaged(t);
    assert.ok(before.length >= Object.keys(LEGACY_FILES).length, 'the fixture holds the legacy layout');
    const r = runSync({ argv: [t], root, target: t });
    assert.doesNotMatch(r.stdout + r.stderr, /MIGRATE|Legacy/, 'no legacy line');
    assert.deepEqual(outsideManaged(t), before, 'the module run left every path outside the managed set byte-identical');
    const out = [];
    reconcileGitignore(t, { srcList: REAL_LIST, targetList: path.join(t, 'none'), out: (x) => out.push(x) });
    assert.doesNotMatch(out.join(''), /MIGRATE|Legacy/);
    assert.deepEqual(outsideManaged(t), before, 'the reconcile touched only .gitignore');
    assert.ok(existsSync(path.join(t, '.gitignore')));
    for (const [rel, body] of Object.entries(LEGACY_FILES)) assert.equal(readFileSync(path.join(t, rel), 'utf8'), body, rel);
  });

  test('TEST-4006 the module source and the two libs hold none of the dropped paths and lines', () => {
    for (const file of [MODULE, path.join(ROOT, '.aai', 'scripts', 'lib', 'gitignore-block.mjs'), path.join(ROOT, '.aai', 'scripts', 'lib', 'resolve-base.mjs')]) {
      const text = readFileSync(file, 'utf8');
      for (const token of DROPPED_TOKENS) assert.ok(!text.includes(token), `${path.basename(file)} holds ${token}`);
    }
    // the kept pointer to the state migration is in the reconcile
    assert.ok(readFileSync(path.join(ROOT, '.aai', 'scripts', 'lib', 'gitignore-block.mjs'), 'utf8').includes('migrate-state-to-local.sh'));
    // negative control: the scan is not vacuous
    assert.ok(DROPPED_TOKENS.some((tok) => readFileSync(path.join(ROOT, 'tests', 'fixtures', 'sync-reference', 'aai-sync.sh'), 'utf8').includes(tok)), 'the bash twin holds the tokens');
  });
});

// --- run 3: the profile, the core copy and prune, the extended copy, the path guard, the skill trees, the indexes,
// --- the knowledge files, the seeds and the root shims (TEST-4007 to TEST-4009) ---------------------------------------

// writeTree(dir, files): files maps a relative path to a string, { text, mode } or { link }.
function writeTree(dir, files) {
  for (const [rel, spec] of Object.entries(files)) {
    const full = path.join(dir, rel);
    mkdirSync(path.dirname(full), { recursive: true });
    if (typeof spec === 'string') writeFileSync(full, spec);
    else if (spec.link !== undefined) symlinkSync(spec.link, full);
    else {
      writeFileSync(full, spec.text);
      chmodSync(full, spec.mode);
    }
  }
}

const lstatOrNull = (p) => {
  try {
    return lstatSync(p);
  } catch {
    return null;
  }
};

const EM_DASH = '\u2014';
// wrapperText(name, prompt, opts): the text of a template skill wrapper as the layer ships it.
function wrapperText(name, prompt, { eol = '\n', stop = false, descr = 'Delegating wrapper.' } = {}) {
  const lines = ['---', `name: ${name}`, `description: ${descr}`, '---', ''];
  if (stop) lines.push('<SUBAGENT-STOP>', 'You are a subagent.', '</SUBAGENT-STOP>', '');
  lines.push(
    `Read the file \`.aai/SKILL_${prompt}.prompt.md\` from the current project root and follow its instructions exactly. Invoke this as \`/${name}\`.`,
    '',
    `If \`.aai/SKILL_${prompt}.prompt.md\` does not exist, say: "SKILL_${prompt} not found ${EM_DASH} are you in an AAI project? Expected: .aai/SKILL_${prompt}.prompt.md"`,
    '',
  );
  return lines.join(eol);
}

const CORE_REAL = [
  '.aai/AGENTS.md', '.aai/workflow/WORKFLOW.md', '.aai/SKILL_ALIVE.prompt.md', '.aai/scripts/tool.sh', '.aai/scripts/lib/merge-hooks-json.mjs',
  '.aai/system/PROFILES.yaml', '.aai/system/RUNTIME_IGNORE.list', '.aai/templates/TECHNOLOGY_TEMPLATE.md',
];
const profilesText = (core) => `core:\n${core.map((c) => `  - ${c}`).join('\n')}\nextended:\n  - .aai/x.md\n`;

// layerFiles({ core }): the files of a small layer source. The engine files are added by makeLayer.
function layerFiles({ core = [...CORE_REAL, '.aai/MISSING.md'] } = {}) {
  return {
    '.aai/AGENTS.md': 'agents\n',
    '.aai/workflow/WORKFLOW.md': 'workflow\n',
    '.aai/workflow/OTHER.md': 'other workflow\n',
    '.aai/roles/ROLE.md': 'role\n',
    '.aai/knowledge/K.md': 'knowledge\n',
    '.aai/SKILL_ALIVE.prompt.md': 'alive prompt\n',
    '.aai/templates/TECHNOLOGY_TEMPLATE.md': '# tech\n',
    '.aai/templates/update-config.template.yaml': 'auto: false\n',
    '.aai/templates/docs-audit.template.yaml': 'dials: report-only\n',
    '.aai/system/PROFILES.yaml': profilesText(core),
    '.aai/system/RUNTIME_IGNORE.list': readFileSync(REAL_LIST, 'utf8'),
    '.aai/scripts/tool.sh': { text: '#!/bin/sh\necho tool\n', mode: 0o755 },
    '.aai/scripts/other.sh': '#!/bin/sh\necho other\n',
    '.claude/skills/aai-alive/SKILL.md': wrapperText('aai-alive', 'ALIVE'),
    '.claude/skills/aai-two/SKILL.md': 'two\n',
    '.claude/skills/aai-two/aux/extra.md': 'extra\n',
    '.agents/skills/aai-alive/SKILL.md': wrapperText('aai-alive', 'ALIVE'),
    '.codex/skills/README.md': 'codex index\n',
    '.gemini/skills/README.md': 'gemini index\n',
    '.claude-plugin/plugin.json': '{"name":"aai"}\n',
    '.cursor/rules/aai.mdc': 'cursor rules\n',
    'docs/knowledge/FACTS.md': 'AAI-TEMPLATE facts\n',
    'docs/knowledge/PATTERNS.md': 'AAI-TEMPLATE patterns\n',
    'docs/knowledge/NEW.md': 'AAI-TEMPLATE new\n',
    'AGENTS.md': 'root agents\n',
    'CLAUDE.md': 'root claude\n',
    'CODEX.md': 'root codex\n',
    'GEMINI.md': 'root gemini\n',
    'SKILLS.md': 'root skills\n',
    'README.md': 'readme\n',
  };
}

// makeLayer(root, name, { engine, core, files }): a scratch layer source. engine 'module' vendors the module and its three
// libs, 'reference' the two frozen twins and the bash library (plus the merge library, so the trees match).
function makeLayer(root, name, { engine = 'module', core, files = {} } = {}) {
  const src = path.join(root, name);
  writeTree(src, { ...layerFiles(core === undefined ? {} : { core }), ...files });
  const scripts = path.join(src, '.aai', 'scripts');
  mkdirSync(path.join(scripts, 'lib'), { recursive: true });
  if (engine === 'module') {
    copyFileSync(MODULE, path.join(scripts, 'aai-sync.mjs'));
    for (const lib of MODULE_LIBS) copyFileSync(path.join(ROOT, '.aai', 'scripts', 'lib', lib), path.join(scripts, 'lib', lib));
    return { src, script: path.join(scripts, 'aai-sync.mjs') };
  }
  materializeSyncReference(src);
  copyFileSync(path.join(ROOT, '.aai', 'scripts', 'lib', 'merge-hooks-json.mjs'), path.join(scripts, 'lib', 'merge-hooks-json.mjs'));
  return { src, script: path.join(scripts, 'aai-sync.sh') };
}

const ENGINE_NAME = /^(aai-sync\.|gitignore-block\.|resolve-base\.mjs)/;
// comparableRows(target): the snapshot rows both engines write in run 3: not the engine files, the pin, the advisory,
// the .gitignore and the sync-written Copilot/hooks surfaces (later runs).
const comparableRows = (target) => snapshotTree(target).filter((row) => {
  const rel = row.split('\t')[0];
  return !ENGINE_NAME.test(path.basename(rel)) && rel !== '.gitignore' && !rel.startsWith('docs/ai/reports') && rel !== '.aai/system/AAI_PIN.md';
});

const RUN3_LINE = /^ {2}(PROFILE core|WARN core-listed|WARN could not remove|PRESERVE|CLEAN|SEED|SKIP|SYNC \.claude-plugin|SYNC \.cursor|SYNC \.github|SYNC hooks|MERGE|WARN hooks)/;
// run3Lines(stdout, ...pairs): the narrative lines of the steps of run 3, each path replaced by its placeholder.
function run3Lines(stdout, pairs) {
  const engine = (l) => ENGINE_NAME.test(path.basename(l.trim().split(' ').pop()));
  return stdout.split('\n').filter((l) => RUN3_LINE.test(l) && !l.includes('AAI_PIN.md') && !engine(l)).map((l) => {
    let line = l;
    for (const [from, to] of pairs) line = line.split(from).join(to);
    return line;
  });
}

// advisoryRows(target): the conflicts and deletions the bash twin wrote into its advisory report.
function advisoryRows(target) {
  const dir = path.join(target, 'docs', 'ai', 'reports');
  if (!existsSync(dir)) return { conflicts: [], deletions: [] };
  const name = readdirSync(dir).filter((n) => n.startsWith('sync-conflicts-')).sort().pop();
  if (name === undefined) return { conflicts: [], deletions: [] };
  const text = readFileSync(path.join(dir, name), 'utf8');
  const [over, del = ''] = text.split('\n## Deleted items\n');
  return {
    conflicts: [...over.matchAll(/^- Path: (.*)\n- Recommendation: (.*)$/gm)].map((m) => ({ path: m[1], text: m[2] })),
    deletions: [...del.matchAll(/^- Path: (.*)$/gm)].map((m) => m[1]),
  };
}

// diffRun(root, label, { layer, prepare, steps }): the frozen bash twin and the module sync one layer into two targets; each
// step is an argument list (run in turn, both sides). Returns what the comparison needs.
async function diffRun(root, label, { layer = {}, prepare = () => {}, steps = [[]] } = {}) {
  const b = makeLayer(root, `${label}-Sb`, { engine: 'reference', ...layer });
  const m = makeLayer(root, `${label}-Sm`, { engine: 'module', ...layer });
  const tb = path.join(root, `${label}-Tb`);
  const tm = path.join(root, `${label}-Tm`);
  for (const t of [tb, tm]) {
    mkdirSync(t);
    prepare(t);
  }
  let ref = null;
  let mod = null;
  const ledger = { conflicts: [], deletions: [] };
  for (const argv of steps) {
    // the advisory of an earlier step is not this step's (scratch only)
    rmSync(path.join(tb, 'docs', 'ai', 'reports'), { recursive: true, force: true });
    ledger.conflicts.length = 0;
    ledger.deletions.length = 0;
    ref = runSync({ argv: [tb, ...argv], root, target: tb, script: b.script, exe: 'bash' });
    assert.equal(ref.status, 0, `the bash reference failed: ${ref.stderr}`);
    mod = await runInProcess({ argv: [tm, ...argv], root, target: tm, scriptPath: m.script, ledger });
  }
  return { ref, mod, tb, tm, sb: b.src, sm: m.src, ledger, advisory: advisoryRows(tb) };
}

// assertSameRun(d): the run-3 lines, the comparable tree and the recorded conflicts and deletions equal the twin's.
function assertSameRun(d, label, { sortLines = false } = {}) {
  const norm = (x) => (sortLines ? [...x].sort() : x);
  const refLines = run3Lines(d.ref.stdout, [[d.tb, '<T>'], [d.sb, '<S>']]);
  const modLines = run3Lines(d.mod.stdout, [[d.tm, '<T>'], [d.sm, '<S>']]);
  assert.deepEqual(norm(modLines), norm(refLines), `${label}: the narrative lines`);
  const strip = (rows, base) => rows.map((r) => r.split(base).join('<T>'));
  assert.deepEqual(strip(comparableRows(d.tm), d.tm), strip(comparableRows(d.tb), d.tb), `${label}: the target tree`);
  assert.deepEqual(d.ledger.conflicts, d.advisory.conflicts, `${label}: the recorded conflicts`);
  const notEngine = (x) => x !== '.aai/system/AAI_PIN.md' && !ENGINE_NAME.test(path.basename(x));
  assert.deepEqual([...d.ledger.deletions].filter(notEngine).sort(), [...d.advisory.deletions].filter(notEngine).sort(), `${label}: the recorded deletions`);
}

// changedPaths(before, after): the paths whose rows differ between two snapshots of one root.
function changedPaths(before, after) {
  const mb = new Map(before.map((r) => [r.split('\t')[0], r]));
  const ma = new Map(after.map((r) => [r.split('\t')[0], r]));
  const changed = [];
  for (const [p, r] of mb) if (ma.get(p) !== r) changed.push(p);
  for (const p of ma.keys()) if (!mb.has(p)) changed.push(p);
  return changed;
}
// assertChangesUnder(before, after, prefix): every path the run wrote or deleted lies under the target (D-SAFETY): the
// source, the scratch infrastructure and every sibling are byte-identical.
function assertChangesUnder(before, after, prefix) {
  const stray = changedPaths(before, after).filter((p) => !(p === prefix || p.startsWith(`${prefix}/`)));
  assert.deepEqual(stray, [], 'a path outside the target changed');
}

const LAYER_DIRS = ['.aai/workflow', '.aai/roles', '.aai/templates', '.aai/scripts', '.aai/system', '.aai/knowledge', '.agents/skills',
  '.claude/skills', '.claude-plugin', '.codex/skills', '.codex/skills.local', '.cursor/rules', '.gemini/skills', '.gemini/skills.local',
  '.github', 'docs/knowledge', 'docs/ai', 'hooks'];

// --- TEST-4007 ---------------------------------------------------------------------------------------------------------

describe('TEST-4007 the core profile: resolution, copy and prune', () => {
  test('TEST-4007 DR-9 and DR-10: the sticky profile and the core block are read the bash way', async () => {
    const { readStickyProfile, parseCoreList } = await import(MODULE_URL);
    const root = scratch('p9-');
    const pinDir = path.join(root, '.aai', 'system');
    mkdirSync(pinDir, { recursive: true });
    const pin = (t) => writeFileSync(path.join(pinDir, 'AAI_PIN.md'), t);
    // DR-9: the FIRST line starting "- Profile: " decides; a value that is not a profile reads as none (never the next line)
    pin('# AAI Pin\n- Profile: bogus\n- Profile: core\n');
    assert.equal(readStickyProfile(root), '', 'the first line is read, then validated');
    pin('- Profile: core \t\r\n- Profile: extended\r\n');
    assert.equal(readStickyProfile(root), 'core', 'a CRLF pin, trailing blanks removed');
    pin('  - Profile: core\n- Profile: extended\n');
    assert.equal(readStickyProfile(root), 'extended', 'an indented line is not the line');
    pin('- Profile:core\n');
    assert.equal(readStickyProfile(root), '');
    // DR-10: the block opens at the line "core:" exactly and closes at the first line that is not indented
    assert.deepEqual(parseCoreList('core:\n  - a\n  - b  \r\n\textra\n  - c\n'), ['a', 'b'], 'a tab-indented line is not indented: it closes the block');
    assert.deepEqual(parseCoreList('core: \n  - a\n'), [], 'core: with a trailing space does not open the block');
    assert.deepEqual(parseCoreList('core:\n  - a\next:\n  - b\n'), ['a'], 'the next top-level key closes it');
    assert.deepEqual(parseCoreList('core:\n  - a\n\n  - b\n'), ['a', 'b'], 'a blank line stays inside the block');
    assert.deepEqual(parseCoreList('core:\n  -  spaced\n  - \n  - last\t\n'), [' spaced', 'last'], 'an empty entry is dropped, nothing else is trimmed at the front');
    assert.deepEqual(parseCoreList('# core:\n  - a\n'), []);
    assert.deepEqual(parseCoreList(''), []);
  });

  test('TEST-4007 planCore warns for a listed file missing in the source; planPrune is pure and never nominates a directory or the cache', async () => {
    const { planCore, planPrune } = await import(MODULE_URL);
    const root = scratch('plan-');
    writeTree(root, { 'a/x.md': 'x', 'a/dir/y.md': 'y' });
    assert.deepEqual(planCore(['a/x.md', 'a/gone.md', 'a/dir', 'a/dir/y.md'], root).map((e) => [e.rel, e.present]),
      [['a/x.md', true], ['a/gone.md', false], ['a/dir', false], ['a/dir/y.md', true]], 'a directory is not a regular file');
    const files = ['.aai/AGENTS.md', '.aai/extra.md', '.aai/cache/keep', '.aai/cache/deep/x', '.aai/scripts/own.sh', '.aai/scripts/tool.sh', '.aai/scripts/lib/old.sh', '.aai/system/AAI_PIN.md'];
    const core = new Set(['.aai/AGENTS.md', '.aai/scripts/tool.sh']);
    const srcHas = (rel) => rel === '.aai/scripts/tool.sh' || rel === '.aai/scripts/lib/old.sh';
    const frozen = JSON.stringify(files);
    const plan = planPrune(files, core, srcHas);
    assert.equal(JSON.stringify(files), frozen, 'the input is untouched');
    assert.deepEqual(plan, [
      { rel: '.aai/extra.md', action: 'prune' },
      { rel: '.aai/scripts/own.sh', action: 'preserve' },
      { rel: '.aai/scripts/lib/old.sh', action: 'prune' },
      { rel: '.aai/system/AAI_PIN.md', action: 'prune' },
    ], 'core files and the cache are never candidates; a script the source lacks is preserved');
    assert.throws(() => planPrune(files, new Set(), srcHas), /empty core/, 'an empty core set is a hard failure, never delete everything');
    assert.throws(() => planPrune(files, [], srcHas), /empty core|core set/);
  });

  test('TEST-4007 K03: a fresh core sync copies the listed files with their modes and warns for the missing one', async () => {
    const root = scratch('k03-');
    const d = await diffRun(root, 'k03', { steps: [['--profile', 'core']] });
    assertSameRun(d, 'K03');
    const t = d.tm;
    for (const rel of CORE_REAL) assert.ok(existsSync(path.join(t, rel)), `${rel} copied`);
    assert.equal(statSync(path.join(t, '.aai/scripts/tool.sh')).mode & 0o777, 0o755, 'the mode of a core file is kept');
    assert.equal(existsSync(path.join(t, '.aai/workflow/OTHER.md')), false, 'a file that is not core is not copied');
    assert.match(d.mod.stdout, /^ {2}PROFILE core: filtered \.aai copy per \.aai\/system\/PROFILES\.yaml$/m);
    assert.match(d.mod.stdout, /^ {2}WARN core-listed file missing in source \(skipped\): \.aai\/MISSING\.md$/m);
    // the eighteen directories the twins create up front exist in a core sync too
    for (const dir of LAYER_DIRS.filter((x) => !['.aai/roles', '.aai/knowledge'].includes(x))) assert.ok(statSync(path.join(t, dir)).isDirectory(), `${dir} created up front`);
    assert.equal(existsSync(path.join(t, '.aai/roles')), false, 'an up-front directory the core copy left empty is removed again');
  });

  test('TEST-4007 K04: extended then core prunes the extended-only files, keeps the cache and target-only scripts, removes emptied directories', async () => {
    const root = scratch('k04-');
    const prepare = (t) => {
      // a target-only script, runtime cache and an empty directory under the cache are in place before the first sync
      writeTree(t, { '.aai/scripts/own.sh': 'own\n', '.aai/cache/keep': 'cache\n', '.aai/cache/sub/also': 'cache2\n' });
      mkdirSync(path.join(t, '.aai/cache/emptydir'), { recursive: true });
    };
    const d = await diffRun(root, 'k04', { prepare, steps: [['--profile', 'extended'], ['--profile', 'core']] });
    assertSameRun(d, 'K04', { sortLines: true });
    const t = d.tm;
    assert.equal(existsSync(path.join(t, '.aai/workflow/OTHER.md')), false, 'the extended-only file is pruned');
    assert.equal(existsSync(path.join(t, '.aai/roles')), false, 'the directory the prune emptied is removed');
    assert.equal(existsSync(path.join(t, '.aai/knowledge')), false, 'another emptied directory is removed');
    assert.equal(readFileSync(path.join(t, '.aai/scripts/own.sh'), 'utf8'), 'own\n', 'a target-only script is preserved');
    assert.equal(readFileSync(path.join(t, '.aai/cache/keep'), 'utf8'), 'cache\n');
    assert.ok(statSync(path.join(t, '.aai/cache')).isDirectory(), 'the cache directory itself is never removed');
    assert.equal(existsSync(path.join(t, '.aai/cache/emptydir')), false, 'parity: an empty directory inside the cache goes with the emptied ones');
    assert.equal(readFileSync(path.join(t, '.aai/cache/sub/also'), 'utf8'), 'cache2\n');
    assert.ok(statSync(path.join(t, '.aai')).isDirectory());
    assert.match(d.mod.stdout, /^ {2}PRESERVE target-only script: \.aai\/scripts\/own\.sh$/m);
    assert.match(d.mod.stdout, /^ {2}PROFILE prune \(not in core\): \.aai\/workflow\/OTHER\.md$/m);
    // every prune is recorded as a deletion (the advisory of run 4 lists them): the ledger equals the twin's
    assert.ok(d.ledger.deletions.includes('.aai/workflow/OTHER.md') && d.ledger.deletions.includes('.aai/roles/ROLE.md'));
    assert.ok(!d.ledger.deletions.some((p) => p.startsWith('.aai/cache')), 'the cache is not a deletion');
    // the prune lines come in ascending order
    const pruned = d.mod.stdout.split('\n').filter((l) => l.startsWith('  PROFILE prune'));
    assert.deepEqual(pruned, [...pruned].sort());
  });

  test('TEST-4007 K05: the sticky core profile applies without a flag, and an explicit flag wins over the pin', async () => {
    const root = scratch('k05-');
    const { src, script } = makeLayer(root, 'S', { engine: 'module' });
    const t = path.join(root, 't');
    writeTree(t, { '.aai/system/AAI_PIN.md': '# AAI Pin\n\n- Profile: core\n', '.aai/workflow/OTHER.md': 'x\n' });
    prepareEnv(root);
    let r = await runInProcess({ argv: [t], root, target: t, scriptPath: script });
    assert.match(r.stdout, /^Profile: {12}core$/m);
    assert.equal(existsSync(path.join(t, '.aai/workflow/OTHER.md')), false, 'sticky core pruned the extended-only file');
    assert.equal(existsSync(path.join(t, '.aai/AGENTS.md')), true);
    r = await runInProcess({ argv: [t, '--profile', 'extended'], root, target: t, scriptPath: script });
    assert.match(r.stdout, /^Profile: {12}extended$/m);
    assert.equal(readFileSync(path.join(t, '.aai/workflow/OTHER.md'), 'utf8'), 'other workflow\n', 'the flag overrides the pin: the full layer is copied');
    assert.ok(src.length > 0);
  });

  test('TEST-4007 K07: a core list padded with 20,000 entries prunes no core-listed file on either of two runs', async () => {
    const root = scratch('k07-');
    const fake = Array.from({ length: 20000 }, (_, i) => `.aai/fake/entry-${i}.md`);
    const { script } = makeLayer(root, 'S', { engine: 'module', core: [...CORE_REAL, ...fake] });
    const t = path.join(root, 't');
    mkdirSync(t);
    prepareEnv(root);
    for (const round of [1, 2]) {
      if (round === 2) writeTree(t, { '.aai/extra-after-first.md': 'gone\n', '.aai/workflow/OTHER.md': 'gone\n' });
      const before = snapshotTree(root);
      const r = await runInProcess({ argv: [t, '--profile', 'core'], root, target: t, scriptPath: script });
      const warns = r.stdout.split('\n').filter((l) => l.startsWith('  WARN core-listed file missing in source')).length;
      assert.equal(warns, 20000, `round ${round}: one warning per missing listed entry`);
      for (const rel of CORE_REAL) assert.ok(existsSync(path.join(t, rel)), `round ${round}: ${rel} survives the prune`);
      assert.ok(!r.stdout.split('\n').some((l) => l.startsWith('  PROFILE prune') && CORE_REAL.some((c) => l.endsWith(c))), `round ${round}: no core-listed file is pruned`);
      if (round === 2) {
        assert.equal(existsSync(path.join(t, '.aai/extra-after-first.md')), false, 'a non-core file is still pruned');
        assert.equal(existsSync(path.join(t, '.aai/workflow/OTHER.md')), false);
      }
      assertChangesUnder(before, snapshotTree(root), 't');
    }
  });

  test('TEST-4007 a prune never follows a link, a link is pruned as a link, and every deleted path lies under the target', async () => {
    const root = scratch('prunelink-');
    const { script } = makeLayer(root, 'S', { engine: 'module' });
    const t = path.join(root, 't');
    const outside = path.join(root, 'outside');
    writeTree(outside, { 'precious.txt': 'keep me\n', 'deep/precious2.txt': 'keep me too\n' });
    writeTree(t, { '.aai/OLD.md': 'stale\n' });
    symlinkSync(outside, path.join(t, '.aai', 'linked-dir'));
    symlinkSync(path.join(outside, 'precious.txt'), path.join(t, '.aai', 'linked-file'));
    symlinkSync(path.join(root, 'nowhere'), path.join(t, '.aai', 'dangling'));
    prepareEnv(root);
    const before = snapshotTree(root);
    const r = await runInProcess({ argv: [t, '--profile', 'core'], root, target: t, scriptPath: script });
    for (const name of ['linked-dir', 'linked-file', 'dangling']) {
      assert.equal(lstatOrNull(path.join(t, '.aai', name)), null, `${name} is pruned as a link`);
      assert.match(r.stdout, new RegExp(`^ {2}PROFILE prune \\(not in core\\): \\.aai/${name}$`, 'm'));
    }
    assert.equal(readFileSync(path.join(outside, 'precious.txt'), 'utf8'), 'keep me\n');
    assert.equal(readFileSync(path.join(outside, 'deep/precious2.txt'), 'utf8'), 'keep me too\n');
    assertChangesUnder(before, snapshotTree(root), 't');
  });

  test('TEST-4007 the prune lookup reads no pipe and no child, and a listed-file refusal leaves the target untouched', () => {
    const text = readFileSync(MODULE, 'utf8');
    const code = text.split('\n').filter((l) => !/^\s*\/\//.test(l)).join('\n');
    assert.ok(!/shell\s*:\s*true|execSync|exec\(|\|\s*grep/.test(code), 'no shell, no pipe in the module');
    assert.equal(text.split('const isCoreListed = (coreSet, rel) => coreSet.has(rel);').length - 1, 1);
    assert.ok(/isCoreListed\(/.test(code.replace('const isCoreListed', '')), 'the prune asks isCoreListed');
    // a core list holding a path that leaves the target is refused by the guard before the file is written
    const root = scratch('escape-');
    const { script } = makeLayer(root, 'S', { engine: 'module', core: [...CORE_REAL, '../escape.md'] });
    writeFileSync(path.join(root, 'escape.md'), 'source of the escape\n');
    const t = path.join(root, 't');
    mkdirSync(t);
    prepareEnv(root);
    const before = snapshotTree(root);
    const r = runSync({ argv: [t, '--profile', 'core'], root, target: t, script });
    assert.equal(r.status, 1);
    assert.match(r.stderr, /^ERROR: \.\.\/escape\.md resolves outside the target .*; refusing to write or delete there\.\n$/);
    assert.equal(readFileSync(path.join(root, 'escape.md'), 'utf8'), 'source of the escape\n', 'nothing was written outside the target');
    assertChangesUnder(before, snapshotTree(root), 't');
  });
});

// --- TEST-4008 ---------------------------------------------------------------------------------------------------------

const MANAGED_TOP_PATHS = ['.aai', '.agents', '.agents/skills', '.claude', '.claude/skills', '.claude-plugin', '.codex', '.codex/skills',
  '.cursor', '.gemini', '.gemini/skills', '.github', 'docs', 'docs/ai', 'docs/knowledge', 'hooks'];

describe('TEST-4008 copy semantics, the extended flow and the path guard', () => {
  test('TEST-4008 copyReplace keeps modes, timestamps and links, copies a dangling link as a link and replaces any destination', async () => {
    const { copyReplace, resolveRoots } = await import(MODULE_URL);
    const root = scratch('copy-');
    const target = path.join(root, 'target');
    mkdirSync(target);
    const env = prepareEnv(root);
    const roots = resolveRoots({ target, profile: '', outcome: 'run', arg: '' }, { env, cwd: root, scriptPath: MODULE });
    writeTree(path.join(root, 'in'), {
      'run.sh': { text: '#!/bin/sh\n', mode: 0o755 },
      'ro.txt': { text: 'read only\n', mode: 0o444 },
      'tree/a.txt': 'a\n',
      'tree/sub/b.txt': { text: 'b\n', mode: 0o700 },
      'tree/dangling': { link: path.join(root, 'nowhere') },
      'tree/rel': { link: 'a.txt' },
    });
    symlinkSync(path.join(root, 'nowhere-either'), path.join(root, 'in', 'top-dangling'));
    const old = new Date('2020-01-02T03:04:05Z');
    utimesSync(path.join(root, 'in', 'run.sh'), old, old);
    chmodSync(path.join(root, 'in', 'tree', 'sub'), 0o750);
    copyReplace(path.join(root, 'in', 'run.sh'), path.join(target, 'run.sh'), roots);
    assert.equal(statSync(path.join(target, 'run.sh')).mode & 0o777, 0o755);
    assert.equal(statSync(path.join(target, 'run.sh')).mtimeMs, old.getTime(), 'the timestamp is kept');
    copyReplace(path.join(root, 'in', 'ro.txt'), path.join(target, 'ro.txt'), roots);
    assert.equal(statSync(path.join(target, 'ro.txt')).mode & 0o777, 0o444);
    copyReplace(path.join(root, 'in', 'tree'), path.join(target, 'tree'), roots);
    assert.equal(statSync(path.join(target, 'tree/sub/b.txt')).mode & 0o777, 0o700);
    assert.equal(statSync(path.join(target, 'tree/sub')).mode & 0o777, 0o750, 'a directory mode is kept');
    assert.equal(readlinkSync(path.join(target, 'tree/dangling')), path.join(root, 'nowhere'), 'a dangling link inside a tree stays a link');
    assert.equal(readlinkSync(path.join(target, 'tree/rel')), 'a.txt', 'a relative link keeps its text');
    copyReplace(path.join(root, 'in', 'top-dangling'), path.join(target, 'top-dangling'), roots);
    assert.equal(readlinkSync(path.join(target, 'top-dangling')), path.join(root, 'nowhere-either'), 'DR-15: a dangling source link is copied as a link');
    // a destination of another type is replaced; a copied directory loses what the target added inside it (parity)
    writeTree(target, { 'tree/target-added.txt': 'mine\n' });
    copyReplace(path.join(root, 'in', 'tree'), path.join(target, 'tree'), roots);
    assert.equal(existsSync(path.join(target, 'tree/target-added.txt')), false, 'parity: a copy-replaced directory loses files the target added');
    mkdirSync(path.join(target, 'was-dir', 'inner'), { recursive: true });
    copyReplace(path.join(root, 'in', 'run.sh'), path.join(target, 'was-dir'), roots);
    assert.equal(lstatSync(path.join(target, 'was-dir')).isFile(), true);
    // a destination link is replaced, never followed
    const outside = path.join(root, 'outside');
    writeTree(outside, { 'keep.txt': 'keep\n' });
    symlinkSync(outside, path.join(target, 'was-link'));
    copyReplace(path.join(root, 'in', 'tree'), path.join(target, 'was-link'), roots);
    assert.equal(lstatSync(path.join(target, 'was-link')).isDirectory(), true);
    assert.deepEqual(readdirSync(outside), ['keep.txt'], 'nothing was written through the link');
  });

  test('TEST-4008 copyReplace refuses a destination outside the target, in the source or behind a link, and writes nothing', async () => {
    const root = scratch('guard-');
    // the module is the scratch copy, so that its source root is a scratch tree and never this checkout
    const { src, script } = makeLayer(root, 'S', { engine: 'module' });
    const { copyReplace, resolveRoots, guardMutation } = await import(pathToFileURL(script).href);
    const target = path.join(root, 'target');
    const outside = path.join(root, 'outside');
    mkdirSync(target);
    writeTree(outside, { 'victim.txt': 'victim\n' });
    symlinkSync(outside, path.join(target, 'out-link'));
    writeFileSync(path.join(root, 'payload.txt'), 'payload\n');
    const env = prepareEnv(root);
    const roots = resolveRoots({ target, profile: '', outcome: 'run', arg: '' }, { env, cwd: root, scriptPath: script });
    assert.equal(roots.srcReal, realpathSync(src), 'the source is the scratch layer');
    const before = snapshotTree(root);
    for (const dst of [path.join(outside, 'victim.txt'), path.join(outside, 'new.txt'), path.join(target, 'out-link', 'victim.txt'), path.join(src, 'never-written.txt'), path.join(src, '.aai', 'AGENTS.md'), path.join(root, 'sibling.txt')]) {
      assert.throws(() => copyReplace(path.join(root, 'payload.txt'), dst, roots), (e) => e.code === 1 && /resolves outside the target .*; refusing to write or delete there\.$/.test(e.message), dst);
      assert.notEqual(guardMutation(roots, dst), null, `${dst} is not a mutation path`);
    }
    assert.deepEqual(snapshotTree(root), before, 'nothing was written or deleted');
  });

  test('TEST-4008 K08: the extended sync copies, cleans stale top-level entries and preserves target-only scripts', async () => {
    const root = scratch('k08-');
    const prepare = (t) => writeTree(t, {
      '.aai/OLD.md': 'stale\n', '.aai/oldtree/inner.md': 'stale tree\n', '.aai/scripts/own.sh': 'own\n', '.aai/scripts/lib/target-only.mjs': 'x\n',
      '.aai/cache/keep': 'cache\n', '.aai/workflow/extra.md': 'added by the project\n',
    });
    const d = await diffRun(root, 'k08', { prepare });
    assertSameRun(d, 'K08');
    const t = d.tm;
    assert.equal(existsSync(path.join(t, '.aai/OLD.md')), false);
    assert.equal(existsSync(path.join(t, '.aai/oldtree')), false);
    assert.equal(readFileSync(path.join(t, '.aai/cache/keep'), 'utf8'), 'cache\n', 'the cache survives');
    assert.equal(existsSync(path.join(t, '.aai/workflow/extra.md')), false, 'parity: a copy-replaced directory loses the target-added file');
    assert.equal(readFileSync(path.join(t, '.aai/scripts/own.sh'), 'utf8'), 'own\n');
    assert.equal(existsSync(path.join(t, '.aai/scripts/lib/target-only.mjs')), false, 'parity: scripts/lib is copy-replaced as a whole');
    assert.equal(statSync(path.join(t, '.aai/scripts/tool.sh')).mode & 0o777, 0o755);
    assert.match(d.mod.stdout, /^ {2}CLEAN removed stale: \.aai\/OLD\.md$/m);
    assert.match(d.mod.stdout, /^ {2}CLEAN removed stale: \.aai\/oldtree$/m);
    assert.match(d.mod.stdout, /^ {2}PRESERVE target-only script: \.aai\/scripts\/own\.sh$/m);
    assert.deepEqual([...d.ledger.deletions].sort(), ['.aai/OLD.md', '.aai/oldtree']);
    for (const dir of LAYER_DIRS) assert.ok(statSync(path.join(t, dir)).isDirectory(), `${dir} created up front`);
  });

  test('TEST-4008 DR-7: a managed top-level path that is a link leaving the target (or entering the source) refuses the whole run before any write', async () => {
    const root = scratch('dr7-');
    const { src, script } = makeLayer(root, 'S', { engine: 'module' });
    const outside = path.join(root, 'outside');
    writeTree(outside, { 'keep.txt': 'keep\n' });
    prepareEnv(root);
    let n = 0;
    for (const managed of MANAGED_TOP_PATHS) {
      for (const kind of ['outside', 'source', 'dangling']) {
        n += 1;
        const t = path.join(root, `t${n}`);
        mkdirSync(path.dirname(path.join(t, managed)), { recursive: true });
        const to = kind === 'outside' ? outside : kind === 'source' ? path.join(src, '.aai') : path.join(root, `nowhere-${n}`);
        symlinkSync(to, path.join(t, managed));
        const before = snapshotTree(root);
        const r = await runInProcess({ argv: [t], root, target: t, scriptPath: script });
        assert.equal(r.code, 1, `${managed} -> ${kind}`);
        assert.equal(r.stdout, '', 'nothing is printed before the refusal');
        assert.match(r.stderr, /^ERROR: [^\n]* nothing was written\.\n$/, `${managed} -> ${kind}`);
        assert.ok(r.stderr.includes(managed) && r.stderr.includes(path.basename(to)), 'the line names the path and where it leads');
        assert.deepEqual(snapshotTree(root), before, `${managed} -> ${kind}: nothing changed`);
        assert.deepEqual(readdirSync(outside), ['keep.txt']);
      }
    }
    assert.equal(n, MANAGED_TOP_PATHS.length * 3);
    // a link that stays inside the target is not refused, and the layer lands behind it
    const t = path.join(root, 'inside');
    mkdirSync(path.join(t, 'real-skills'), { recursive: true });
    mkdirSync(path.join(t, '.claude'));
    symlinkSync(path.join(t, 'real-skills'), path.join(t, '.claude', 'skills'));
    const r = await runInProcess({ argv: [t], root, target: t, scriptPath: script });
    assert.ok(!/nothing was written/.test(r.stderr), r.stderr);
    assert.equal(readFileSync(path.join(t, 'real-skills', 'aai-two', 'SKILL.md'), 'utf8'), 'two\n');
    // the same link through the child process (the real entry point)
    const t2 = path.join(root, 'real-run');
    mkdirSync(path.join(t2, '.codex'), { recursive: true });
    symlinkSync(outside, path.join(t2, '.codex', 'skills'));
    const child = runSync({ argv: [t2], root, target: t2, script });
    assert.equal(child.status, 1);
    assert.match(child.stderr, /nothing was written/);
    assert.deepEqual(readdirSync(outside), ['keep.txt']);
  });

  test('TEST-4008 DR-8: the target identity is re-read before the prune, and a target swapped mid-run exits 1 with the same line', async () => {
    const { reverifyTarget, resolveRoots } = await import(MODULE_URL);
    const root = scratch('dr8-');
    const { script } = makeLayer(root, 'S', { engine: 'module' });
    const t = path.join(root, 't');
    writeTree(t, { '.aai/EXTRA.md': 'extra\n', '.aai/system/KEEPME.md': 'would be pruned\n' });
    prepareEnv(root);
    const moved = path.join(root, 'moved');
    let swapped = false;
    const r = await runInProcess({
      argv: [t, '--profile', 'core'], root, target: t, scriptPath: script,
      onOut: (s) => {
        // the last listed core file is missing in the source: its warning is the last write-free line before the prune
        if (!swapped && s.includes('core-listed file missing in source (skipped): .aai/MISSING.md')) {
          swapped = true;
          renameSync(t, moved);
          mkdirSync(t);
        }
      },
    });
    assert.ok(swapped, 'the swap point was reached');
    assert.equal(r.code, 1);
    assert.equal(r.stderr, `ERROR: .aai resolves outside the target ${t}; refusing to write or delete there.\n`);
    assert.equal(readFileSync(path.join(moved, '.aai/EXTRA.md'), 'utf8'), 'extra\n', 'nothing was pruned in the swapped-away directory');
    assert.deepEqual(readdirSync(t), [], 'nothing was written into the directory that replaced the target');
    // the helper itself: an unchanged target passes, a replaced one is refused
    const env = prepareEnv(root);
    const t3 = path.join(root, 't3');
    mkdirSync(t3);
    const roots = resolveRoots({ target: t3, profile: '', outcome: 'run', arg: '' }, { env, cwd: root, scriptPath: MODULE });
    assert.equal(reverifyTarget(roots), null);
    renameSync(t3, path.join(root, 't3-moved'));
    mkdirSync(t3);
    assert.equal(reverifyTarget(roots).refusal.code, 1);
    // the three delete phases (the core prune, the extended stale clean, the retired-wrapper removal) each re-read it
    const source = readFileSync(MODULE, 'utf8');
    assert.ok(source.split('mustReverify(').length - 1 >= 4, 'one definition and three call sites');
  });

  test('TEST-4008 a temp file the run did not create is left in place when the self-heal meets it (EEXIST)', async () => {
    const root = scratch('eexist-');
    const { script } = makeLayer(root, 'S', { engine: 'module' });
    const t = path.join(root, 't');
    mkdirSync(t);
    writeFileSync(path.join(t, '.gitignore'), '.aai/\n.aai/\nproject/\n');
    const foreign = `${path.join(t, '.gitignore')}.aai-dedup.${process.pid}`;
    writeFileSync(foreign, 'not made by this run\n');
    prepareEnv(root);
    const r = await runInProcess({ argv: [t], root, target: t, scriptPath: script });
    assert.equal(r.code, 1);
    assert.match(r.stderr, /aai-sync: internal error: .*EEXIST/);
    assert.equal(readFileSync(foreign, 'utf8'), 'not made by this run\n', 'the foreign temp file is never deleted');
  });

  test('TEST-4008 DR-31: a link in the shipped snapshot directory or at a merge temp name is replaced, never written through', async () => {
    for (const [label, where] of [['snapshot', ['.aai', 'cache', 'hooks-shipped', 'hooks.json']], ['merge temp', ['hooks', `.hooks.json.${process.pid}.tmp`]]]) {
      const root = scratch('dr31-');
      const { src, script } = makeLayer(root, 'S', { engine: 'module', ...hooksLayer });
      const outside = path.join(root, 'outside');
      writeTree(outside, { 'victim.json': 'VICTIM\n' });
      const t = path.join(root, 't');
      mkdirSync(path.dirname(path.join(t, ...where)), { recursive: true });
      symlinkSync(path.join(outside, 'victim.json'), path.join(t, ...where));
      prepareEnv(root);
      const r = await runInProcess({ argv: [t], root, target: t, scriptPath: script });
      assert.equal(r.code, 0, `${label}: ${r.stderr}`);
      assert.equal(readFileSync(path.join(outside, 'victim.json'), 'utf8'), 'VICTIM\n', `${label}: the file outside the target is untouched`);
      assert.deepEqual(readdirSync(outside), ['victim.json']);
      if (label === 'snapshot') {
        const snap = path.join(t, '.aai', 'cache', 'hooks-shipped', 'hooks.json');
        assert.ok(!lstatSync(snap).isSymbolicLink(), 'the link is replaced by a regular file');
        assert.equal(readFileSync(snap, 'utf8'), readFileSync(path.join(src, 'hooks', 'hooks.json'), 'utf8'));
      }
    }
  });

  test('TEST-4008 a dangling link nested in a source skill is copied as a link (DR-15); a dangling top-level entry of the skill tree is skipped as bash skips it (DR-27)', async () => {
    const root = scratch('dangle-');
    const { script } = makeLayer(root, 'S', { engine: 'module', files: { '.claude/skills/aai-two/dangling': { link: path.join(root, 'nowhere') }, '.claude/skills/aai-dangling': { link: path.join(root, 'nowhere') } } });
    const t = path.join(root, 't');
    mkdirSync(t);
    prepareEnv(root);
    const r = await runInProcess({ argv: [t], root, target: t, scriptPath: script });
    assert.ok(!/internal error: .*(ENOENT|dangling)/.test(r.stderr), r.stderr);
    assert.equal(r.code, 0, r.stderr);
    assert.equal(readlinkSync(path.join(t, '.claude/skills/aai-two/dangling')), path.join(root, 'nowhere'));
    assert.equal(lstatOrNull(path.join(t, '.claude/skills/aai-dangling')), null, 'the top-level dangling link is not copied');
  });
});

// --- TEST-4009 ---------------------------------------------------------------------------------------------------------

// retiredCase(root, name, files, opts): a skill tree entry <root>/skills/<name> holding the given files; returns the path.
function retiredEntry(root, name, files) {
  const entry = path.join(root, 'skills', name);
  mkdirSync(entry, { recursive: true });
  writeTree(entry, files);
  return entry;
}

describe('TEST-4009 skill trees, indexes, knowledge, seeds and root shims', () => {
  test('TEST-4009 K10 to K14: the surfaces of a differing target equal the frozen bash twin (lines, tree and recorded conflicts)', async () => {
    const root = scratch('k10-');
    const prepare = (t) => writeTree(t, {
      '.claude/skills/aai-alive/SKILL.md': 'local edit of a template skill\n',
      '.claude/skills/aai-two/SKILL.md': 'two\n',
      '.claude/skills/aai-two/aux/extra.md': 'a different extra\n',
      '.claude/skills/aai-project-x/SKILL.md': wrapperText('aai-project-x', 'GONE'),
      '.claude/skills/aai-gone/SKILL.md': wrapperText('aai-gone', 'GONE'),
      '.claude/skills/aai-near/SKILL.md': wrapperText('aai-near', 'GONE').replace('instructions exactly', 'instruction exactly'),
      '.claude/skills/aai-link': { link: '../../elsewhere' },
      '.claude/skills/own-skill/SKILL.md': 'project owned\n',
      '.agents/skills/aai-gone2/SKILL.md': wrapperText('aai-gone2', 'GONE2', { stop: true }),
      '.agents/skills/aai-alive/SKILL.md': wrapperText('aai-alive', 'ALIVE'),
      '.codex/skills/README.md': 'a different codex index\n',
      '.codex/skills.local/mine.md': 'local index\n',
      '.gemini/skills/README.md': 'gemini index\n',
      '.gemini/skills.local/mine.md': 'local index\n',
      'docs/knowledge/FACTS.md': 'project facts, sentinel removed\n',
      'docs/knowledge/PATTERNS.md': 'lower case aai-template is no sentinel\n',
      'docs/knowledge/NEW.md': 'AAI-TEMPLATE still a template\n',
      'docs/ai/update-config.yaml': 'auto: true\n',
      'AGENTS.md': 'local agents\n',
      'CLAUDE.md': 'root claude\n',
      'README_AAI.md': 'local readme\n',
    });
    const d = await diffRun(root, 'k10', { prepare });
    assertSameRun(d, 'K10 to K14');
    const t = d.tm;
    assert.equal(existsSync(path.join(t, '.claude/skills/aai-gone')), false, 'the retired wrapper is removed');
    assert.equal(existsSync(path.join(t, '.agents/skills/aai-gone2')), false, 'a wrapper with a SUBAGENT-STOP block is removed');
    for (const kept of ['aai-project-x', 'aai-near', 'own-skill', 'aai-link']) assert.ok(lstatOrNull(path.join(t, '.claude/skills', kept)) !== null, `${kept} kept`);
    assert.equal(readFileSync(path.join(t, 'docs/knowledge/NEW.md'), 'utf8'), 'AAI-TEMPLATE new\n', 'a file that still holds the sentinel is replaced');
    assert.equal(readFileSync(path.join(t, 'docs/knowledge/PATTERNS.md'), 'utf8'), 'lower case aai-template is no sentinel\n', 'DR-16: the sentinel is case-sensitive');
    assert.equal(readFileSync(path.join(t, 'docs/ai/update-config.yaml'), 'utf8'), 'auto: true\n', 'a seed is never overwritten');
    assert.equal(readFileSync(path.join(t, 'docs/TECHNOLOGY.md'), 'utf8'), '# tech\n');
    assert.equal(readFileSync(path.join(t, 'docs/ai/docs-audit.yaml'), 'utf8'), 'dials: report-only\n');
    assert.equal(readFileSync(path.join(t, 'README_AAI.md'), 'utf8'), 'readme\n');
    assert.equal(readFileSync(path.join(t, 'SKILLS.md'), 'utf8'), 'root skills\n');
    const texts = d.ledger.conflicts.map((c) => c.path);
    for (const p of ['.claude/skills/aai-alive/SKILL.md', '.claude/skills/aai-two', 'AGENTS.md', 'README_AAI.md', '.codex/skills/']) assert.ok(texts.includes(p), `a conflict for ${p}`);
    assert.ok(!texts.includes('CLAUDE.md') && !texts.includes('.gemini/skills/'), 'an identical file or directory is no conflict');
    assert.ok(!texts.includes('.agents/skills/aai-alive/SKILL.md'));
    assert.deepEqual([...d.ledger.deletions].sort(), ['.agents/skills/aai-gone2', '.claude/skills/aai-gone']);
  });

  test('TEST-4009 K10 to K14 on an empty target: every surface is created, nothing is recorded', async () => {
    const root = scratch('k10b-');
    const d = await diffRun(root, 'k10b', { steps: [[], []] });
    assertSameRun(d, 'fresh target, twice');
    assert.deepEqual(d.ledger.conflicts, []);
    assert.deepEqual(d.ledger.deletions, []);
    assert.ok(existsSync(path.join(d.tm, 'docs/TECHNOLOGY.md')));
  });

  test('TEST-4009 the seed lines, the sentinel lines and the shim and index lines are the bash lines', async () => {
    const root = scratch('lines-');
    const { script } = makeLayer(root, 'S', { engine: 'module' });
    const t = path.join(root, 't');
    writeTree(t, { 'docs/knowledge/FACTS.md': 'mine\n' });
    prepareEnv(root);
    const r = await runInProcess({ argv: [t], root, target: t, scriptPath: script });
    const has = (line) => assert.ok(r.stdout.split('\n').includes(line), `missing line: ${line}`);
    has('  SEED docs/TECHNOLOGY.md from .aai/templates/TECHNOLOGY_TEMPLATE.md');
    has('  SEED docs/ai/update-config.yaml from .aai/templates/update-config.template.yaml');
    has('  SEED docs/ai/docs-audit.yaml from .aai/templates/docs-audit.template.yaml (dials report-only; docs-audit --check now runs enforced)');
    has(`  SKIP (project-owned, sentinel removed): ${path.join(t, 'docs/knowledge/FACTS.md')}`);
    has(`  PRESERVE target-only skills under: ${path.join(t, '.claude/skills')}`);
    has(`  PRESERVE target-only skills under: ${path.join(t, '.agents/skills')}`);
    has(`  PRESERVE local Codex dynamic index: ${path.join(t, '.codex/skills.local')}`);
    has(`  PRESERVE local Gemini dynamic index: ${path.join(t, '.gemini/skills.local')}`);
    has('  PRESERVE docs/ai/ runtime data (STATE.yaml, LOOP_TICKS.jsonl, METRICS.jsonl, EVENTS.jsonl, decisions.jsonl, reports/)');
    has('  SYNC .claude-plugin/plugin.json');
    has('  SYNC .cursor/rules/aai.mdc');
    // the step order of the twin: the .aai copy, the skill trees, the knowledge, the seeds, the indexes, the plugin, the cursor rules
    const order = ['  PRESERVE target-only script: .aai/scripts', 'PRESERVE target-only skills under: ', '  SKIP (project-owned', '  SEED docs/TECHNOLOGY.md', '  PRESERVE docs/ai/ runtime data',
      '  PRESERVE local Codex', '  PRESERVE local Gemini', '  SYNC .claude-plugin', '  SYNC .cursor'];
    let at = -1;
    for (const needle of order) {
      const i = r.stdout.indexOf(needle, at + 1);
      if (needle.startsWith('  PRESERVE target-only script')) continue; // present only when the target holds a script of its own
      assert.ok(i > at, `${needle} comes after the previous step`);
      at = i;
    }
    // the .gitignore reconcile runs in its place in the step order (after the cursor rules)
    const gi = r.stdout.indexOf('Added .aai/ to ');
    assert.ok(gi > r.stdout.indexOf('  SYNC .cursor/rules/aai.mdc'), 'the reconcile follows the cursor rules');
    assert.ok(existsSync(path.join(t, '.gitignore')));
    assert.match(readFileSync(path.join(t, '.gitignore'), 'utf8'), /^\.aai\/$/m);
  });

  test('TEST-4009 isRetiredSkillWrapper accepts exactly the shipped wrapper shape', async () => {
    const { isRetiredSkillWrapper } = await import(MODULE_URL);
    const root = scratch('retired-');
    const srcRoot = path.join(root, 'src');
    writeTree(srcRoot, { '.aai/SKILL_ALIVE.prompt.md': 'alive\n' });
    const ok = (name, files, want = true, label = name) => {
      const entry = retiredEntry(root, `${name}-${Math.random().toString(36).slice(2, 8)}`, files);
      assert.equal(isRetiredSkillWrapper(entry, name, srcRoot), want, label);
    };
    const W = (name, prompt = 'GONE', o = {}) => wrapperText(name, prompt, o);
    // accepted shapes
    ok('aai-gone', { 'SKILL.md': W('aai-gone') });
    ok('aai-gone', { 'SKILL.md': W('aai-gone', 'GONE', { stop: true }) }, true, 'with a SUBAGENT-STOP block');
    ok('aai-gone', { 'SKILL.md': W('aai-gone', 'GONE', { eol: '\r\n' }) }, true, 'CRLF');
    ok('aai-gone', { 'SKILL.md': `${W('aai-gone')}\n\n  \n` }, true, 'trailing blank lines');
    ok('aai-gone', { 'SKILL.md': W('aai-gone', 'GONE', { descr: 'caf\u0065\u0301 NFD in the description is not compared' }) }, true, 'NFD in the free description');
    ok('aai-gone-2', { 'SKILL.md': W('aai-gone-2', 'GONE_2') }, true, 'digits and underscore in the prompt name');
    const pad = W('aai-gone', 'GONE', { descr: 'x' });
    const exact = pad.replace('description: x', `description: ${'d'.repeat(65536 - Buffer.byteLength(pad) + 1)}`);
    assert.equal(Buffer.byteLength(exact), 65536);
    ok('aai-gone', { 'SKILL.md': exact }, true, '65536 bytes');
    // near misses: each one is kept
    ok('aai-alive', { 'SKILL.md': W('aai-alive', 'ALIVE') }, false, 'the source still ships the prompt');
    ok('aai-gone', { 'SKILL.md': W('aai-gone').replace('instructions exactly', 'instruction exactly') }, false, 'one changed byte');
    ok('aai-gone', { 'SKILL.md': `\uFEFF${W('aai-gone')}` }, false, 'a BOM');
    ok('aai-gone', { 'SKILL.md': W('aai-gone').replace('not found', 'not\u200B found') }, false, 'U+200B in the expected line');
    ok('aai-gone', { 'SKILL.md': W('aai-gone').replace(EM_DASH, `${EM_DASH}\u0301`) }, false, 'a combining mark after the dash (NFD-style)');
    ok('aai-gone', { 'SKILL.md': W('aai-gone').replace(EM_DASH, '-') }, false, 'an ASCII hyphen for the dash');
    ok('aai-gone', { 'SKILL.md': W('aai-gone').replace('name: aai-gone', 'name: aai-other') }, false, 'another name in the frontmatter');
    ok('aai-gone', { 'SKILL.md': W('aai-gone').replace('name: aai-gone\n', '') }, false, 'no name line');
    ok('aai-gone', { 'SKILL.md': W('aai-gone').replace('---\n\nRead', '\nRead') }, false, 'no closing frontmatter line');
    ok('aai-gone', { 'SKILL.md': `${W('aai-gone')}Extra trailing line.\n` }, false, 'an extra body line');
    ok('aai-gone', { 'SKILL.md': W('aai-gone').replace('Invoke this as', 'Run it as') }, false, 'no Invoke this as');
    ok('aai-gone', { 'SKILL.md': W('aai-gone').replace('/aai-gone`.', '/aai-gone` in .aai/ please.') }, false, 'a .aai/ path after the prompt');
    ok('aai-gone', { 'SKILL.md': W('aai-gone').replace('`/aai-gone`.', '`/aai-gone`') }, false, 'no final dot');
    ok('aai-gone', { 'SKILL.md': W('aai-gone', 'gone') }, false, 'a lower-case prompt name');
    ok('aai-gone', { 'SKILL.md': W('aai-gone', 'GONE', { stop: true }).replace('You are a subagent.\n', '') }, false, 'an empty SUBAGENT-STOP block');
    ok('aai-gone', { 'SKILL.md': W('aai-gone').replace('---\n\nRead', '---\n\nNote.\n\nRead') }, false, 'a third body line');
    ok('aai-gone', { 'SKILL.md': '' }, false, 'empty file');
    ok('aai-gone', { 'SKILL.md': `${W('aai-gone')}\0` }, false, 'a NUL byte');
    ok('aai-gone', { 'SKILL.md': W('aai-gone').replace('description: Delegating wrapper.', `description: ${'d'.repeat(70000)}`) }, false, '65537 bytes and more');
    ok('aai-gone', { 'SKILL.md': exact.replace('d'.repeat(10), 'd'.repeat(11)) }, false, 'exactly 65537 bytes');
    ok('aai-gone', { 'SKILL.md': W('aai-gone'), 'other.md': 'a second file\n' }, false, 'a second file');
    ok('aai-gone', { 'skill.md': W('aai-gone') }, false, 'a lower-case file name');
    ok('aai-gone', { 'SKILL.md/inner': 'a directory named SKILL.md\n' }, false, 'SKILL.md is a directory');
    ok('aai-gone', { 'SKILL.md': { link: path.join(root, 'elsewhere.md') } }, false, 'SKILL.md is a link');
    ok('aai-gone', {}, false, 'an empty directory');
    ok('aai-project-x', { 'SKILL.md': W('aai-project-x') }, false, 'a project-owned name');
    for (const bad of ['aai-Gone', 'aai-g\u00e9', 'aai_gone', 'aai-', 'x-aai-gone', 'aai-go ne', 'aai-gone*']) ok(bad, { 'SKILL.md': W(bad) }, false, `name ${bad}`);
    // the entry itself: a link to a wrapper directory, a file, a missing path
    const real = retiredEntry(root, 'real-target', { 'SKILL.md': W('aai-gone') });
    symlinkSync(real, path.join(root, 'skills', 'aai-linked'));
    assert.equal(isRetiredSkillWrapper(path.join(root, 'skills', 'aai-linked'), 'aai-linked', srcRoot), false, 'a link to a wrapper directory');
    assert.equal(isRetiredSkillWrapper(path.join(root, 'skills', 'aai-missing'), 'aai-missing', srcRoot), false, 'a missing entry');
    writeFileSync(path.join(root, 'skills', 'aai-file'), W('aai-file'));
    assert.equal(isRetiredSkillWrapper(path.join(root, 'skills', 'aai-file'), 'aai-file', srcRoot), false, 'a file');
  });

  test('TEST-4009 the removal of retired wrappers removes only provable wrappers, records them, and keeps links, near misses and shipped names', async () => {
    const root = scratch('wrappers-');
    const { script } = makeLayer(root, 'S', { engine: 'module' });
    const t = path.join(root, 't');
    const outside = path.join(root, 'outside');
    writeTree(outside, { 'SKILL.md': wrapperText('aai-linked', 'GONE') });
    writeTree(t, {
      '.claude/skills/aai-gone/SKILL.md': wrapperText('aai-gone', 'GONE'),
      '.claude/skills/aai-two/SKILL.md': wrapperText('aai-two', 'GONE'),
      '.claude/skills/aai-alive/SKILL.md': wrapperText('aai-alive', 'ALIVE'),
      '.claude/skills/aai-linked': { link: outside },
      '.claude/skills/aai-project-keep/SKILL.md': wrapperText('aai-project-keep', 'GONE'),
      '.claude/skills/aai-exec/SKILL.md': wrapperText('aai-exec', 'GONE').replace('Invoke this as', 'Run as'),
    });
    prepareEnv(root);
    const ledger = { conflicts: [], deletions: [] };
    const before = snapshotTree(root);
    const r = await runInProcess({ argv: [t], root, target: t, scriptPath: script, ledger });
    assert.match(r.stdout, /^ {2}CLEAN removed retired skill wrapper: \.claude\/skills\/aai-gone$/m);
    assert.equal(existsSync(path.join(t, '.claude/skills/aai-gone')), false);
    // a shipped name is copy-replaced from the source, never removed as a wrapper
    assert.equal(readFileSync(path.join(t, '.claude/skills/aai-two/SKILL.md'), 'utf8'), 'two\n');
    assert.deepEqual(ledger.deletions, ['.claude/skills/aai-gone']);
    for (const kept of ['aai-project-keep', 'aai-exec', 'aai-linked']) assert.ok(lstatOrNull(path.join(t, '.claude/skills', kept)) !== null, `${kept} kept`);
    assert.equal(readFileSync(path.join(outside, 'SKILL.md'), 'utf8'), wrapperText('aai-linked', 'GONE'), 'a link is never followed');
    assertChangesUnder(before, snapshotTree(root), 't');
  });

  test('TEST-4009 a root shim, README_AAI.md, a knowledge file and a seed are written only inside the target', async () => {
    const root = scratch('shims-');
    const { script } = makeLayer(root, 'S', { engine: 'module' });
    const t = path.join(root, 't');
    mkdirSync(t);
    const outside = path.join(root, 'outside.md');
    writeFileSync(outside, 'outside\n');
    symlinkSync(outside, path.join(t, 'AGENTS.md'));
    prepareEnv(root);
    const before = snapshotTree(root);
    const r = await runInProcess({ argv: [t], root, target: t, scriptPath: script });
    assert.equal(readFileSync(outside, 'utf8'), 'outside\n', 'a destination link is replaced, never written through');
    assert.equal(lstatSync(path.join(t, 'AGENTS.md')).isFile(), true);
    assert.equal(readFileSync(path.join(t, 'AGENTS.md'), 'utf8'), 'root agents\n');
    assert.ok(r.stdout.includes('Syncing AAI from:'));
    assertChangesUnder(before, snapshotTree(root), 't');
  });
});

// --- TEST-4010 and TEST-4011 (run 4): the Copilot shim, the hooks merge, the advisory and the pin ------------------------

const sha256Hex = (text) => createHash('sha256').update(text, 'utf8').digest('hex');
// the normalized hash the list holds: every CR removed, trailing LFs dropped
const shimHash = (text) => sha256Hex(text.replace(/\r/g, '').replace(/\n+$/, ''));
const SHIM_NEW = 'Copilot shim v2\nsecond line\n';
const SHIM_OLD = 'Copilot shim v1\nold line\n';
const OV_START = '<!-- AAI-PROJECT-OVERRIDES:START -->';
const OV_END = '<!-- AAI-PROJECT-OVERRIDES:END -->';
const OV_FILE = 'docs/ai/project-overrides/copilot-instructions.project.md';
const shimLayer = { files: { '.github/copilot-instructions.md': SHIM_NEW, '.aai/system/COPILOT_SHIM_SHIPPED.list': `# shipped\n${shimHash(SHIM_OLD)}\r\n` } };
const mergedShim = (rules, eol = '\n') => `${SHIM_NEW}\n---\n## Project Overrides (auto-merged)\n\n${OV_START}${eol}${rules}${eol}${OV_END}${eol}`;

const hooksJson = (cmd, extra = {}) => `${JSON.stringify({ hooks: { SessionStart: [{ matcher: 'startup', hooks: [{ type: 'command', command: cmd, async: false, ...extra }] }] } }, null, 2)}\n`;
const hookCmd = (flag) => `"\${CLAUDE_PLUGIN_ROOT}/hooks/session-start.sh" ${flag}`;
const hooksLayer = {
  files: {
    'hooks/session-start.sh': { text: '#!/bin/sh\necho hi\n', mode: 0o644 },
    'hooks/session-start.ps1': 'ps1\n',
    'hooks/.hidden-hook.sh': 'hidden\n',
    'hooks/hooks.json': hooksJson(hookCmd('--v2')),
    'hooks/hooks.windows.json': hooksJson('pwsh "${CLAUDE_PLUGIN_ROOT}/hooks/session-start.ps1" --v2'),
  },
};

describe('TEST-4010 the Copilot shim and the session hooks', () => {
  test('TEST-4010 K15: every Copilot shim flow equals the frozen bash twin (lines, tree, recorded conflicts) and is not vacuous', async () => {
    const root = scratch('k15-');
    const cases = [
      ['absent', {}, null],
      ['identical', { '.github/copilot-instructions.md': SHIM_NEW }, null],
      ['older shipped shim (listed hash)', { '.github/copilot-instructions.md': SHIM_OLD }, 'SYNC .github/copilot-instructions.md (unmodified shipped shim replaced, no project overrides)'],
      ['older shipped shim with CRLF', { '.github/copilot-instructions.md': SHIM_OLD.replace(/\n/g, '\r\n') }, 'SYNC .github/copilot-instructions.md (unmodified shipped shim replaced, no project overrides)'],
      ['project overrides block', { '.github/copilot-instructions.md': mergedShim('my rule\nsecond rule') }, 'MERGE preserved project overrides in:'],
      ['CRLF block without a final newline', { '.github/copilot-instructions.md': `${SHIM_NEW}\r\n${OV_START}\r\nmy rule\r\n${OV_END}` }, 'MERGE preserved project overrides in:'],
      ['no markers, the whole file is the overrides', { '.github/copilot-instructions.md': 'my own copilot file\n' }, 'MERGE preserved project overrides in:'],
      ['end marker before start marker', { '.github/copilot-instructions.md': `${OV_END}\n${OV_START}\nmy rule\n` }, 'SYNC .github/copilot-instructions.md (unmodified shipped shim replaced, no project overrides)'],
      ['empty block, override file fallback', { '.github/copilot-instructions.md': `${OV_START}\n${OV_END}\n`, [OV_FILE]: 'file rule\n' }, 'MERGE preserved project overrides in:'],
      ['whitespace only, no override file', { '.github/copilot-instructions.md': '  \n\n' }, 'SYNC .github/copilot-instructions.md (unmodified shipped shim replaced, no project overrides)'],
    ];
    for (const [label, prepared, line] of cases) {
      const d = await diffRun(root, `k15-${cases.findIndex((c) => c[0] === label)}`, { layer: shimLayer, prepare: (t) => writeTree(t, prepared) });
      assertSameRun(d, `K15 ${label}`);
      const stdout = d.mod.stdout;
      if (line === null) assert.ok(!stdout.includes('copilot-instructions'), `${label}: no shim line`);
      else assert.ok(stdout.split('\n').some((l) => l.includes(line)), `${label}: the line ${line}`);
      const shim = readFileSync(path.join(d.tm, '.github/copilot-instructions.md'), 'utf8');
      if (line !== null && line.startsWith('SYNC')) assert.equal(shim, SHIM_NEW, `${label}: replaced by the shim`);
      if (line !== null && line.startsWith('MERGE')) {
        assert.ok(shim.startsWith(`${SHIM_NEW}\n---\n## Project Overrides (auto-merged)\n\n${OV_START}\n`), `${label}: the merged bytes`);
        assert.ok(existsSync(path.join(d.tm, OV_FILE)), `${label}: the override file is written`);
        assert.deepEqual(d.ledger.conflicts.filter((c) => c.path.includes('copilot')), [], `${label}: a merge records no conflict`);
      }
    }
  });

  test('TEST-4010 DR-17 the merged shim and the override file are the bash bytes (no trim, a final newline)', async () => {
    const root = scratch('dr17-');
    const { script } = makeLayer(root, 'S', { engine: 'module', ...shimLayer });
    const t = path.join(root, 't');
    writeTree(t, { '.github/copilot-instructions.md': `${SHIM_NEW}\n${OV_START}\n  indented rule  \n\n${OV_END}\n` });
    await runInProcess({ argv: [t], root, target: t, scriptPath: script });
    assert.equal(readFileSync(path.join(t, OV_FILE), 'utf8'), '  indented rule  \n', 'the override file: the text, one newline');
    assert.equal(readFileSync(path.join(t, '.github/copilot-instructions.md'), 'utf8'), mergedShim('  indented rule  '));
    assert.ok(!readFileSync(path.join(t, '.github/copilot-instructions.md')).subarray(0, 3).equals(Buffer.from([0xef, 0xbb, 0xbf])), 'no BOM');
  });

  test('TEST-4010 copilotShimIsShipped answers for listed, unlisted, empty and CRLF texts and never reads "not shipped" for a missing hash tool (DR-19)', async () => {
    const { copilotShimIsShipped, extractCopilotOverrides } = await import(MODULE_URL);
    const root = scratch('shipped-');
    const list = path.join(root, 'shipped.list');
    writeFileSync(list, `# comment\n${shimHash(SHIM_OLD)}\r\n${'0'.repeat(64)}\n`);
    assert.equal(copilotShimIsShipped(SHIM_OLD.replace(/\n+$/, ''), list), true, 'listed');
    assert.equal(copilotShimIsShipped(SHIM_OLD, list), true, 'trailing LFs do not count');
    assert.equal(copilotShimIsShipped(SHIM_OLD.replace(/\n/g, '\r\n'), list), true, 'CRLF');
    assert.equal(copilotShimIsShipped('my own rule', list), false, 'unlisted');
    assert.equal(copilotShimIsShipped('', list), true, 'empty');
    assert.equal(copilotShimIsShipped(' \t\n \n', list), true, 'whitespace only');
    assert.equal(copilotShimIsShipped('my own rule', path.join(root, 'missing.list')), false, 'no list: not shipped');
    assert.equal(copilotShimIsShipped('', path.join(root, 'missing.list')), true, 'empty needs no list');
    writeFileSync(list, `${shimHash('café')}\n`);
    assert.equal(copilotShimIsShipped('café', list), true, 'the hash is over the UTF-8 bytes');
    assert.equal(extractCopilotOverrides(`a\n${OV_START}\nx\r\ny\n${OV_END}\nz\n`), 'x\ny', 'the block, CR removed');
    assert.equal(extractCopilotOverrides('no markers\r\nhere\n'), 'no markers\r\nhere', 'no markers: the whole text');
    assert.equal(extractCopilotOverrides(`${OV_START}\nonly start\n`), `${OV_START}\nonly start`, 'a start without an end: the whole text');
    assert.equal(extractCopilotOverrides(`${OV_END}\n${OV_START}\nx\n`), '', 'an end before a start: nothing');
  });

  test('TEST-4010 K16: every hooks flow equals the frozen bash twin (lines, tree, recorded conflicts) and is not vacuous', async () => {
    const root = scratch('k16-');
    const cases = {
      'a target-only hook': { prepared: { 'hooks/merge-guard.sh': 'mine\n' }, expect: ['  PRESERVE target-only hook: hooks/merge-guard.sh', '  SYNC hooks/'], conflicts: 0 },
      'b hooks.json absent': { prepared: {}, expect: ['  MERGE hooks/hooks.json: 1 hook(s) added, 0 updated, 0 already present, 0 left as-is -> hooks/hooks.json'], conflicts: 0 },
      'c malformed hooks.json': { prepared: { 'hooks/hooks.json': '{not json\n' }, expect: ['  WARN hooks/hooks.json registration merge refused (target left untouched): existing hooks/hooks.json is not valid JSON'], conflicts: 1 },
      'd user-modified entry': {
        prepared: { 'hooks/hooks.json': hooksJson(hookCmd('--old'), { timeout: 5 }), '.aai/cache/hooks-shipped/hooks.json': hooksJson(hookCmd('--old')) },
        expect: ['0 hook(s) added, 0 updated, 0 already present, 1 left as-is'], conflicts: 1,
      },
      'e updated in place': {
        prepared: { 'hooks/hooks.json': hooksJson(hookCmd('--old')), '.aai/cache/hooks-shipped/hooks.json': hooksJson(hookCmd('--old')) },
        expect: ['0 hook(s) added, 1 updated, 0 already present, 0 left as-is'], conflicts: 0,
      },
      'f snapshot not recordable': {
        prepared: { '.aai/cache/hooks-shipped': 'a file where the snapshot directory belongs\n' },
        expect: ['  WARN hooks/hooks.json merged, but the shipped snapshot could not be recorded: ', '  WARN hooks/hooks.windows.json merged, but the shipped snapshot could not be recorded: '], conflicts: 2,
      },
    };
    let n = 0;
    for (const [label, c] of Object.entries(cases)) {
      n += 1;
      const d = await diffRun(root, `k16-${n}`, { layer: hooksLayer, prepare: (t) => writeTree(t, c.prepared) });
      assertSameRun(d, `K16 ${label}`);
      for (const piece of c.expect) assert.ok(d.mod.stdout.includes(piece) || d.mod.stdout.split(d.tm).join('').includes(piece), `${label}: ${piece}`);
      assert.equal(d.ledger.conflicts.filter((x) => x.path.startsWith('hooks/')).length, c.conflicts, `${label}: the recorded hooks conflicts`);
      // the dotfile hook is copied (K16e) and session-start.sh is executable afterwards (K16f)
      assert.equal(readFileSync(path.join(d.tm, 'hooks/.hidden-hook.sh'), 'utf8'), 'hidden\n', `${label}: the dotfile hook`);
      assert.equal(statSync(path.join(d.tm, 'hooks/session-start.sh')).mode & 0o111, 0o111, `${label}: session-start.sh executable`);
      assert.equal(d.mod.code, 0, `${label}: exit 0`);
    }
  });

  test('TEST-4010 a malformed registration is left untouched byte for byte, and the in-process merge lines equal the library CLI', async () => {
    const root = scratch('merge-lines-');
    const { src, script } = makeLayer(root, 'S', { engine: 'module', ...hooksLayer });
    const files = {
      'hooks/hooks.json': hooksJson(hookCmd('--old'), { timeout: 5 }),
      '.aai/cache/hooks-shipped/hooks.json': hooksJson(hookCmd('--old')),
      'hooks/hooks.windows.json': '[1, 2\n',
    };
    const t = path.join(root, 't');
    const c = path.join(root, 'c');
    for (const dir of [t, c]) writeTree(dir, files);
    const r = await runInProcess({ argv: [t], root, target: t, scriptPath: script });
    assert.equal(readFileSync(path.join(t, 'hooks/hooks.windows.json'), 'utf8'), '[1, 2\n', 'the malformed registration is untouched');
    const lib = path.join(ROOT, '.aai', 'scripts', 'lib', 'merge-hooks-json.mjs');
    const scrub = (s) => s.split(`${c}${path.sep}`).join('').split(`${src}${path.sep}`).join('<source>/');
    const cli = spawnSync(process.execPath, [lib, path.join(src, 'hooks/hooks.json'), path.join(c, 'hooks/hooks.json'), '--shipped', path.join(c, '.aai/cache/hooks-shipped/hooks.json')], { encoding: 'utf8' });
    assert.equal(cli.status, 0);
    const want = `  MERGE hooks/hooks.json: ${scrub(cli.stdout.replace(/\n+$/, ''))}\n`;
    assert.ok(r.stdout.split(t + path.sep).join('').includes(want), `the MERGE line equals the library CLI output: ${want}`);
    assert.equal(readFileSync(path.join(t, 'hooks/hooks.json'), 'utf8'), readFileSync(path.join(c, 'hooks/hooks.json'), 'utf8'), 'the merged bytes equal the CLI merged bytes');
    assert.ok(r.calls.every(([file]) => file === 'git'), 'the merge is in process: the only children are the pin\'s git calls');
  });

  test('TEST-4010 session-start.sh gets its execute bits when it is a regular file, never through a link; every write lies under the target', async () => {
    const root = scratch('exec-');
    const { script } = makeLayer(root, 'S', { engine: 'module', ...hooksLayer });
    const t = path.join(root, 't');
    mkdirSync(t);
    prepareEnv(root);
    const before = snapshotTree(root);
    await runInProcess({ argv: [t], root, target: t, scriptPath: script });
    assert.equal(statSync(path.join(t, 'hooks/session-start.sh')).mode & 0o777, 0o755);
    assertChangesUnder(before, snapshotTree(root), 't');
    // a source without a session-start.sh in hooks/ chmods nothing and does not fail
    const bare = makeLayer(root, 'S2', { engine: 'module', files: { 'hooks/other.sh': 'x\n' } });
    const t2 = path.join(root, 't2');
    mkdirSync(t2);
    const r2 = await runInProcess({ argv: [t2], root, target: t2, scriptPath: bare.script });
    assert.equal(r2.code, 0);
    assert.equal(existsSync(path.join(t2, 'hooks/session-start.sh')), false);
  });

  test('TEST-4010 a hooks.json that is a link is refused (never written through) and recorded; the target of the link is unchanged', async () => {
    const root = scratch('hooks-link-');
    const { script } = makeLayer(root, 'S', { engine: 'module', ...hooksLayer });
    const t = path.join(root, 't');
    const outside = path.join(root, 'outside.json');
    writeFileSync(outside, hooksJson(hookCmd('--x')));
    mkdirSync(path.join(t, 'hooks'), { recursive: true });
    symlinkSync(outside, path.join(t, 'hooks/hooks.json'));
    const ledger = { conflicts: [], deletions: [] };
    const r = await runInProcess({ argv: [t], root, target: t, scriptPath: script, ledger });
    assert.equal(readFileSync(outside, 'utf8'), hooksJson(hookCmd('--x')), 'the link target is unchanged');
    assert.equal(r.code, 0);
    assert.ok(ledger.conflicts.some((x) => x.path === 'hooks/hooks.json' && x.text.startsWith('Hook-registration merge was refused and the target was left untouched: ')));
  });
});

// advisoryText(generated, src, items): the bash advisory text written out literally.
const advisoryText = (generated, src, { conflicts = [], deletions = [] } = {}) => [
  '# Sync Conflict Advisory',
  '',
  `- Generated at (UTC): ${generated}`,
  `- Source: ${src}`,
  '',
  'The following target files/directories had local content that differed from sync source and were overwritten.',
  'Use an AI agent to decide merge strategy per item.',
  '',
  '## Recommended AI workflow',
  '1. Inspect each item with `git diff -- <path>` in the target project.',
  '2. Ask AI to extract project-specific guidance and place it into project-owned docs (for example `docs/ai/project-overrides/`).',
  '3. Keep sync-managed files as baseline templates to reduce future conflicts.',
  '',
  '## Overwritten items',
  ...conflicts.flatMap((c) => ['', `- Path: ${c.path}`, `- Recommendation: ${c.text}`]),
  ...(deletions.length > 0 ? ['', '## Deleted items', ...deletions.flatMap((p) => ['', `- Path: ${p}`])] : []),
  '',
].join('\n');

const fakeGit = (answers) => (file, args, opts) => {
  fakeGit.calls.push({ file, args, opts });
  const sub = args[0] === '-C' ? args.slice(2) : args;
  const key = sub.join(' ');
  const answer = answers[key];
  return answer === undefined ? { status: 128, stdout: '', stderr: 'fatal' } : { status: 0, stdout: answer, stderr: '' };
};
fakeGit.calls = [];

describe('TEST-4011 the advisory report, the pin and the closing lines', () => {
  test('TEST-4011 renderAdvisory: the name and the stamp come from one clock read, the bash text, LF, no BOM; none for a quiet run', async () => {
    const { renderAdvisory } = await import(MODULE_URL);
    const now = new Date('2026-03-04T05:06:07.891Z');
    const items = { conflicts: [{ path: 'AGENTS.md', text: 'Target file contains local changes.' }, { path: 'hooks/hooks.json', text: 'left as-is' }], deletions: ['.aai/old.md', '.claude/skills/aai-gone'] };
    const adv = renderAdvisory({ ...items, src: '/the/source', now });
    assert.equal(adv.name, 'sync-conflicts-20260304-050607.md');
    assert.equal(adv.text, advisoryText('2026-03-04T05:06:07Z', '/the/source', items));
    assert.ok(!adv.text.includes('\r') && !adv.text.startsWith('﻿'), 'LF, no BOM');
    assert.equal(renderAdvisory({ conflicts: [], deletions: [], src: '/s', now }), null, 'a quiet run writes none');
    const only = renderAdvisory({ conflicts: [], deletions: ['.aai/x'], src: '/s', now });
    assert.equal(only.text, advisoryText('2026-03-04T05:06:07Z', '/s', { deletions: ['.aai/x'] }), 'a deletion alone is enough');
    const midnight = renderAdvisory({ conflicts: [{ path: 'a', text: 'b' }], deletions: [], src: '/s', now: new Date('2026-12-31T23:59:59.999Z') });
    assert.equal(midnight.name, 'sync-conflicts-20261231-235959.md');
    assert.match(midnight.text, /- Generated at \(UTC\): 2026-12-31T23:59:59Z\n/);
  });

  test('TEST-4011 renderPin: the bash text, one space after Template version, the tag fallback, UNKNOWN, one clock read, the DR-22 environment', async () => {
    const { renderPin } = await import(MODULE_URL);
    const root = scratch('pin-');
    const src = path.join(root, 'S');
    mkdirSync(path.join(src, 'docs/ai'), { recursive: true });
    const now = new Date('2026-03-04T05:06:07.891Z');
    const env = { PATH: process.env.PATH, GIT_DIR: '/x', GIT_WORK_TREE: '/x', GIT_INDEX_FILE: '/x', GIT_COMMON_DIR: '/x', GIT_OBJECT_DIRECTORY: '/x', GIT_ALTERNATE_OBJECT_DIRECTORIES: '/x', GIT_NAMESPACE: 'x', KEEP: '1' };
    const answers = { 'rev-parse HEAD': 'abc123\n', 'config --get remote.origin.url': 'https://example.invalid/aai.git\n', 'describe --tags --abbrev=0': 'v1.2.3\n' };
    const pin = (version, extra = {}) => `# AAI Pin\n\n- Source path: ${src}\n- Template version: ${version}\n- Template commit: ${extra.commit ?? 'abc123'}\n- Canonical repo: ${extra.url ?? 'https://example.invalid/aai.git'}\n- Profile: ${extra.profile ?? 'core'}\n- Synced at (UTC): 2026-03-04T05:06:07Z\n\nNotes:\n- This project intentionally vendors the AAI files (self-contained).\n- Project-specific docs (requirements/specs/decisions/releases/issues/project-sessions) are not synced by this script.\n- docs/TECHNOLOGY.md is seeded from template only when missing and becomes project-owned after generation.\n`;
    // a version file: the value after the last "Version:" with spaces, tabs and a CR trimmed
    writeFileSync(path.join(src, 'docs/ai/AAI_VERSION.md'), '# AAI\n- Version:  \t4.5.6 \t\r\nVersion: 9.9.9\n');
    fakeGit.calls = [];
    const text = renderPin({ src, profile: 'core', now, spawn: fakeGit(answers), env });
    assert.equal(text, pin('4.5.6'));
    assert.ok(text.includes('- Template version: 4.5.6\n') && !text.includes('version:  '), 'one space');
    for (const call of fakeGit.calls) {
      assert.equal(call.file, 'git');
      assert.deepEqual(call.args.slice(0, 2), ['-C', src], 'git -C <source>');
      for (const v of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_NAMESPACE']) assert.ok(!(v in call.opts.env), `${v} is removed for the child`);
      assert.equal(call.opts.env.KEEP, '1', 'the rest of the environment stays');
      assert.equal(call.opts.stdio[0], 'ignore', 'stdin ignored');
      assert.equal(call.opts.stdio[1], 'pipe', 'stdout piped');
    }
    assert.deepEqual(env.GIT_DIR, '/x', 'the caller environment object is not changed');
    // no version file: the tag fallback
    rmSync(path.join(src, 'docs/ai/AAI_VERSION.md'));
    assert.equal(renderPin({ src, profile: 'extended', now, spawn: fakeGit(answers), env }), pin('v1.2.3 (tag)', { profile: 'extended' }));
    // a version file without a Version line also falls back to the tag
    writeFileSync(path.join(src, 'docs/ai/AAI_VERSION.md'), '# no version here\n\tVersion: tab led is not a version line\nx Version: neither is this\n');
    assert.equal(renderPin({ src, profile: 'core', now, spawn: fakeGit(answers), env }), pin('v1.2.3 (tag)'));
    rmSync(path.join(src, 'docs/ai/AAI_VERSION.md'));
    // no git at all: every git-derived value is UNKNOWN
    const none = renderPin({ src, profile: 'core', now, spawn: () => ({ status: null, error: new Error('ENOENT'), stdout: '' }), env });
    assert.equal(none, pin('UNKNOWN', { commit: 'UNKNOWN', url: 'UNKNOWN' }));
    // an empty remote url is UNKNOWN too
    const emptyUrl = renderPin({ src, profile: 'core', now, spawn: fakeGit({ ...answers, 'config --get remote.origin.url': '\n' }), env });
    assert.equal(emptyUrl, pin('v1.2.3 (tag)', { url: 'UNKNOWN' }));
    assert.ok(!none.includes('\r') && !none.startsWith('﻿'), 'LF, no BOM');
  });

  test('TEST-4011 a run with GIT_DIR exported stamps the commit of the source, not of the repository the variable names (DR-22)', async () => {
    const root = scratch('gitdir-');
    const { src, script } = makeLayer(root, 'S', { engine: 'module', files: { 'docs/ai/AAI_VERSION.md': '- Version: 7.8.9\n' } });
    const other = path.join(root, 'other');
    mkdirSync(other);
    writeFileSync(path.join(other, 'f.txt'), 'other\n');
    const git = (cwd, args) => {
      const r = spawnSync('git', ['-c', 'user.email=t@example.invalid', '-c', 'user.name=T', '-c', 'commit.gpgsign=false', ...args], { cwd, env: prepareEnv(root), encoding: 'utf8' });
      assert.equal(r.status, 0, `git ${args.join(' ')}: ${r.stderr}`);
      return r.stdout.trim();
    };
    git(other, ['init', '-q', '-b', 'main']);
    git(other, ['add', '-A']);
    git(other, ['commit', '-q', '-m', 'other']);
    git(src, ['init', '-q', '-b', 'main']);
    git(src, ['add', '-A']);
    git(src, ['commit', '-q', '-m', 'source']);
    const srcSha = git(src, ['rev-parse', 'HEAD']);
    const otherSha = git(other, ['rev-parse', 'HEAD']);
    assert.notEqual(srcSha, otherSha);
    // the control: with the variable set, a plain git call names the other repository
    const control = spawnSync('git', ['-C', src, 'rev-parse', 'HEAD'], { env: { ...prepareEnv(root), GIT_DIR: path.join(other, '.git') }, encoding: 'utf8' });
    assert.equal(control.stdout.trim(), otherSha, 'the variable really redirects git here');
    const t = path.join(root, 't');
    mkdirSync(t);
    const r = await runInProcess({ argv: [t], root, target: t, scriptPath: script, env: { GIT_DIR: path.join(other, '.git') }, spawn: (f, a, o) => spawnSync(f, a, o) });
    assert.equal(r.code, 0, r.stderr);
    const pin = readFileSync(path.join(t, '.aai/system/AAI_PIN.md'), 'utf8');
    assert.ok(pin.includes(`- Template commit: ${srcSha}\n`), 'the pin names the commit of the source');
    assert.ok(pin.includes('- Template version: 7.8.9\n'));
  });

  test('TEST-4011 K30: no AAI_VERSION.md gives the tag fallback, a source without git gives UNKNOWN', async () => {
    const root = scratch('k30-');
    const tagged = makeLayer(root, 'Stag', { engine: 'module' });
    const git = (args) => {
      const r = spawnSync('git', ['-c', 'user.email=t@example.invalid', '-c', 'user.name=T', '-c', 'commit.gpgsign=false', ...args], { cwd: tagged.src, env: prepareEnv(root), encoding: 'utf8' });
      assert.equal(r.status, 0, r.stderr);
    };
    git(['init', '-q', '-b', 'main']);
    git(['add', '-A']);
    git(['commit', '-q', '-m', 'x']);
    git(['tag', 'v9.9.9']);
    const t1 = path.join(root, 't1');
    mkdirSync(t1);
    const r1 = await runInProcess({ argv: [t1], root, target: t1, scriptPath: tagged.script, spawn: (f, a, o) => spawnSync(f, a, o) });
    assert.equal(r1.code, 0, r1.stderr);
    assert.ok(readFileSync(path.join(t1, '.aai/system/AAI_PIN.md'), 'utf8').includes('- Template version: v9.9.9 (tag)\n'));
    const plain = makeLayer(root, 'Splain', { engine: 'module' });
    const t2 = path.join(root, 't2');
    mkdirSync(t2);
    const r2 = await runInProcess({ argv: [t2], root, target: t2, scriptPath: plain.script, spawn: (f, a, o) => spawnSync(f, a, o) });
    assert.equal(r2.code, 0, r2.stderr);
    const pin = readFileSync(path.join(t2, '.aai/system/AAI_PIN.md'), 'utf8');
    for (const line of ['- Template version: UNKNOWN', '- Template commit: UNKNOWN', '- Canonical repo: UNKNOWN', '- Profile: extended']) assert.ok(pin.split('\n').includes(line), line);
  });

  test('TEST-4011 a sync that records a conflict and a deletion writes the bash advisory and pin; the closing lines end the run', async () => {
    const root = scratch('report-');
    const prepare = (t) => writeTree(t, { 'AGENTS.md': 'local agents\n', '.aai/knowledge/K.md': 'extended only\n' });
    const d = await diffRun(root, 'rep', { prepare, steps: [['--profile', 'core']] });
    const reportOf = (stdout) => {
      const m = /^ {2}Advisory report: (.*)$/m.exec(stdout);
      assert.ok(m, 'an Advisory report line is printed');
      return m[1];
    };
    const mask = (text, srcDir) => text.split(srcDir).join('<S>').replace(/- Generated at \(UTC\): .*/, '- Generated at (UTC): <T>');
    const refText = mask(readFileSync(reportOf(d.ref.stdout), 'utf8'), d.sb);
    const modPath = reportOf(d.mod.stdout);
    assert.ok(modPath.startsWith(path.join(d.tm, 'docs/ai/reports', 'sync-conflicts-')), 'the report lies in the target');
    assert.match(path.basename(modPath), /^sync-conflicts-\d{8}-\d{6}\.md$/);
    const modText = readFileSync(modPath, 'utf8');
    assert.equal(mask(modText, d.sm), refText, 'the advisory equals the bash advisory');
    assert.ok(modText.includes('## Deleted items') && modText.includes('- Path: .aai/knowledge/K.md'), 'the deletion is listed');
    assert.ok(modText.includes('- Path: AGENTS.md'), 'the conflict is listed');
    // the pin: the bash lines except the version spacing (DR-21), the stamp and the path
    const pinLines = (p) => readFileSync(p, 'utf8').split('\n').filter((l) => !/^- (Synced at|Template version|Source path)/.test(l));
    assert.deepEqual(pinLines(path.join(d.tm, '.aai/system/AAI_PIN.md')), pinLines(path.join(d.tb, '.aai/system/AAI_PIN.md')), 'the pin equals the bash pin');
    assert.ok(readFileSync(path.join(d.tm, '.aai/system/AAI_PIN.md'), 'utf8').includes(`- Source path: ${d.sm}\n`));
    // the closing lines are the bash lines
    assert.ok(d.mod.stdout.endsWith(`Sync complete. Review changes in ${d.tm}:\n  cd ${d.tm} && git status && git diff\n`), 'the closing lines');
    assert.ok(d.ref.stdout.endsWith(`Sync complete. Review changes in ${d.tb}:\n  cd ${d.tb} && git status && git diff\n`));
    assert.equal(d.mod.code, 0);
  });

  test('TEST-4011 a quiet run writes no advisory and prints no Advisory report line; the injected clock stamps the report and the pin from one read', async () => {
    const root = scratch('quiet-');
    const { script } = makeLayer(root, 'S', { engine: 'module' });
    const t = path.join(root, 't');
    mkdirSync(t);
    // a fresh target records the two index directories the up-front mkdir made (as the bash twin does); the second run is quiet
    const first = await runInProcess({ argv: [t], root, target: t, scriptPath: script });
    assert.equal(first.code, 0);
    assert.ok(first.stdout.includes('Advisory report:'), 'the fresh run recorded the index conflicts');
    rmSync(path.join(t, 'docs/ai/reports'), { recursive: true });
    const quiet = await runInProcess({ argv: [t], root, target: t, scriptPath: script });
    assert.equal(quiet.code, 0);
    assert.ok(!quiet.stdout.includes('Advisory report:'), 'a quiet run prints no advisory line');
    assert.equal(existsSync(path.join(t, 'docs/ai/reports')), false, 'a quiet run writes no advisory (the reports directory is not even created)');
    writeFileSync(path.join(t, 'AGENTS.md'), 'now a local change\n');
    let reads = 0;
    const now = () => { reads += 1; return new Date('2026-05-06T07:08:09.999Z'); };
    const loud = await runInProcess({ argv: [t], root, target: t, scriptPath: script, now });
    assert.equal(reads, 1, 'the clock is read once per run');
    assert.ok(loud.stdout.includes(`  Advisory report: ${path.join(t, 'docs/ai/reports/sync-conflicts-20260506-070809.md')}\n`));
    assert.ok(readFileSync(path.join(t, 'docs/ai/reports/sync-conflicts-20260506-070809.md'), 'utf8').includes('- Generated at (UTC): 2026-05-06T07:08:09Z\n'));
    assert.ok(readFileSync(path.join(t, '.aai/system/AAI_PIN.md'), 'utf8').includes('- Synced at (UTC): 2026-05-06T07:08:09Z\n'));
  });

  test('TEST-4011 native paths: the source path in the pin and the closing lines is the path the host gives it, never rewritten to a /c/ style (Windows form is hosted evidence H2)', async () => {
    const root = scratch('win-');
    const { src, script } = makeLayer(root, 'S', { engine: 'module' });
    const t = path.join(root, 't');
    mkdirSync(t);
    const r = await runInProcess({ argv: [t], root, target: t, scriptPath: script });
    assert.equal(r.code, 0, r.stderr);
    assert.ok(readFileSync(path.join(t, '.aai/system/AAI_PIN.md'), 'utf8').includes(`- Source path: ${src}\n`));
    assert.ok(r.stdout.includes(`Syncing AAI from: ${src}\n`));
    assert.ok(!/^\/[a-z]\//m.test(readFileSync(path.join(t, '.aai/system/AAI_PIN.md'), 'utf8')), 'no /c/ style path');
  });

  test('TEST-4011 every write and delete of the report and the pin lies under the target', async () => {
    const root = scratch('under-');
    const { script } = makeLayer(root, 'S', { engine: 'module' });
    const t = path.join(root, 't');
    writeTree(t, { 'AGENTS.md': 'local\n' });
    prepareEnv(root);
    const before = snapshotTree(root);
    const r = await runInProcess({ argv: [t], root, target: t, scriptPath: script });
    assert.equal(r.code, 0);
    assertChangesUnder(before, snapshotTree(root), 't');
  });
});

// --- TEST-4013 and TEST-4014 (run 5): the differential corpora of D-CORPUS ------------------------------------------------
//
// A case is { id, title, steps, src, tgt, tname, noGit, noTag, noCommit, cwdLink, kit, rw, asserted, engine }:
//   steps     one argument list per run (tokens <T> <S> <C> stand for the target, the source and the case directory)
//   src(h)    changes the source before it is committed;  tgt(h)  prepares the target
//   rw        the registered rewrites of the case: names of CORPUS_REWRITES, each of which must change at least one byte
//             (an order rewrite may change nothing: its DR says the bash order is undefined)
//   asserted  (ref, mod, c) replaces the byte comparison with the asserted divergence of the DR it names
// Both sides are built at the same absolute path (root/case) one after the other, the first side's tree renamed away.

const CORPUS_ENV = { LC_ALL: 'C' };
const CORPUS_GIT_ID = {
  GIT_AUTHOR_NAME: 'corpus', GIT_AUTHOR_EMAIL: 'corpus@example.invalid', GIT_COMMITTER_NAME: 'corpus', GIT_COMMITTER_EMAIL: 'corpus@example.invalid',
  GIT_AUTHOR_DATE: '2026-01-02T03:04:05Z', GIT_COMMITTER_DATE: '2026-01-02T03:04:05Z',
};
const pwshAvailable = spawnSync('pwsh', ['-NoProfile', '-Command', 'exit 0']).status === 0;
const bashAvailable = spawnSync('bash', ['-c', 'exit 0']).status === 0;
const gitAvailable = spawnSync('git', ['--version']).status === 0;
// BSD sed has no \s: the bash twin's Template version line keeps two spaces there (DR-21)
const bsdSed = spawnSync('sed', ['-E', 's/a\\s*b/X/'], { input: 'a  b', encoding: 'utf8' }).stdout.trim() !== 'X';

function corpusGit(cwd, root, args) {
  assert.ok(under(realpathSync(cwd), realpathSync(root)), `the git working directory ${cwd} lies outside the scratch root`);
  const r = spawnSync('git', ['-c', 'gc.auto=0', '-c', 'maintenance.auto=false', ...args], { cwd, env: prepareEnv(root, CORPUS_GIT_ID), encoding: 'utf8' });
  assert.equal(r.status, 0, `git ${args.join(' ')}: ${r.stderr}`);
  return r.stdout;
}

const CORPUS_CORE = [...CORE_REAL, '.aai/roles/ROLE.md', '.aai/knowledge/K.md', '.aai/templates/update-config.template.yaml', '.aai/templates/docs-audit.template.yaml'];
// corpusFiles(): the synthetic source S (D-CORPUS): a small .aai with a 12-entry PROFILES core list, the real list files and merge library,
// one skill in each skill tree, the indexes, the plugin manifest, the cursor rule, the Copilot shim, the hooks, a sentinel knowledge file,
// the version file, the five root shims and README.md.
function corpusFiles() {
  return {
    ...layerFiles({ core: CORPUS_CORE }),
    ...shimLayer.files,
    ...hooksLayer.files,
    '.aai/extra/only.md': 'extended only\n',
    '.aai/scripts/lib/merge-hooks-json.mjs': { text: readFileSync(path.join(ROOT, '.aai', 'scripts', 'lib', 'merge-hooks-json.mjs')), mode: 0o644 },
    'docs/ai/AAI_VERSION.md': '# AAI\n- Version: v9.9.9\n',
  };
}

// copyCheckout(dir): the tracked files of this checkout (working tree bytes, modes and links) copied into dir.
function copyCheckout(dir) {
  const r = spawnSync('git', ['-C', ROOT, 'ls-files', '-z'], { env: prepareEnv(dir.replace(/\/[^/]*$/, '')), encoding: 'buffer', maxBuffer: 64 * 1024 * 1024 });
  assert.equal(r.status, 0, 'git ls-files failed');
  for (const rel of r.stdout.toString('utf8').split('\0').filter(Boolean)) {
    const from = path.join(ROOT, rel);
    const st = lstatOrNull(from);
    if (st === null) continue;
    const to = path.join(dir, rel);
    mkdirSync(path.dirname(to), { recursive: true });
    if (st.isSymbolicLink()) symlinkSync(readlinkSync(from), to);
    else if (st.isFile()) {
      copyFileSync(from, to);
      chmodSync(to, st.mode & 0o777);
    }
  }
}

const ENGINE_ANY = new Set([...ENGINE_FILES_REFERENCE, ...ENGINE_FILES_MODULE]);

// buildCorpusSide(c, side, root): the case directory root/case holding S and T for one side; returns the handle h.
function buildCorpusSide(c, side, root) {
  const C = path.join(root, 'case');
  mkdirSync(C);
  const S = path.join(C, 'S');
  const T = path.join(C, c.tname ?? 'T');
  const base = { S, T, C };
  const h = {
    ...base,
    w(which, rel, content, mode) {
      const p = path.join(base[which], rel);
      mkdirSync(path.dirname(p), { recursive: true });
      rmSync(p, { recursive: true, force: true });
      writeFileSync(p, content);
      if (mode !== undefined) chmodSync(p, mode);
      return p;
    },
    link(which, rel, text) {
      const p = path.join(base[which], rel);
      mkdirSync(path.dirname(p), { recursive: true });
      rmSync(p, { recursive: true, force: true });
      symlinkSync(text, p);
      return p;
    },
    mkdir(which, rel) { mkdirSync(path.join(base[which], rel), { recursive: true }); },
    rm(which, rel) { rmSync(path.join(base[which], rel), { recursive: true, force: true }); },
  };
  mkdirSync(S);
  if (c.kit === 'checkout') copyCheckout(S);
  else writeTree(S, corpusFiles());
  if (c.src) c.src(h);
  if (!c.noGit) {
    corpusGit(S, root, ['init', '-q', '-b', 'main']);
    if (!c.noCommit) {
      corpusGit(S, root, ['add', '--all']);
      corpusGit(S, root, ['commit', '-q', '-m', 'corpus source']);
      if (!c.noTag) corpusGit(S, root, ['tag', 'v1.0.0']);
    }
  }
  const scripts = path.join(S, '.aai', 'scripts');
  if (side === 'mod') {
    mkdirSync(path.join(scripts, 'lib'), { recursive: true });
    copyFileSync(MODULE, path.join(scripts, 'aai-sync.mjs'));
    for (const lib of MODULE_LIBS) copyFileSync(path.join(ROOT, '.aai', 'scripts', 'lib', lib), path.join(scripts, 'lib', lib));
    for (const name of ['aai-sync.sh', 'aai-sync.ps1']) {
      copyFileSync(path.join(ROOT, '.aai', 'scripts', name), path.join(scripts, name));
      chmodSync(path.join(scripts, name), lstatSync(path.join(ROOT, '.aai', 'scripts', name)).mode & 0o777);
    }
  } else {
    materializeSyncReference(S);
    mkdirSync(path.join(scripts, 'lib'), { recursive: true });
    copyFileSync(path.join(ROOT, '.aai', 'scripts', 'lib', 'merge-hooks-json.mjs'), path.join(scripts, 'lib', 'merge-hooks-json.mjs'));
  }
  if (!c.noTgt) {
    mkdirSync(T);
    if (!c.noTgtGit) corpusGit(T, root, ['init', '-q', '-b', 'main']);
  }
  if (c.tgt) c.tgt(h);
  return h;
}

// corpusSnapshot(dir): path -> "type:mode:bytes" for every path under dir (links by their text, never followed) except a top-level
// .git directory; the engine files of either side are returned apart.
function corpusSnapshot(dir) {
  const rows = {};
  const engine = [];
  const walk = (d, rel) => {
    for (const name of readdirSync(d).sort()) {
      const key = rel === '' ? name : `${rel}/${name}`;
      if (rel === '' && name === '.git') continue;
      const p = path.join(d, name);
      const st = lstatSync(p);
      if (ENGINE_ANY.has(key)) {
        engine.push(key);
        continue;
      }
      if (st.isSymbolicLink()) rows[key] = `link:${readlinkSync(p)}`;
      else if (st.isDirectory()) {
        rows[key] = `dir:${(st.mode & 0o777).toString(8)}`;
        walk(p, key);
      } else if (st.isFile()) rows[key] = `file:${(st.mode & 0o777).toString(8)}:${readFileSync(p).toString('latin1')}`;
      else rows[key] = `other:${st.mode}`;
    }
  };
  if (lstatOrNull(dir)?.isDirectory()) walk(dir, '');
  else rows['<absent>'] = 'absent';
  return { rows, engine };
}

// The registered normalization (not a divergence): the stamps of the report name, the report's Generated at and the pin's Synced at.
// and the lines that name the engine files of either side (each side's own files differ by construction, asserted per side)
const ENGINE_PATH = String.raw`\.aai/scripts/(?:aai-sync\.(?:sh|ps1|mjs)|lib/(?:gitignore-block\.(?:sh|mjs)|resolve-base\.mjs))`;
const ENGINE_LINE = new RegExp(`^ {2}(?:PROFILE prune \\(not in core\\)|PRESERVE target-only script|WARN core-listed file missing in source \\(skipped\\)): ${ENGINE_PATH}\\n`, 'gm');
const ENGINE_ITEM = new RegExp(`\\n\\n- Path: ${ENGINE_PATH}(?=\\n|$)`, 'g');
const normStamp = (s) => s.replace(/sync-conflicts-\d{8}-\d{6}\.md/g, 'sync-conflicts-<STAMP>.md').replace(/^(- (?:Synced|Generated) at \(UTC\):).*$/gm, '$1 <STAMP>')
  .replace(ENGINE_LINE, '').replace(ENGINE_ITEM, '');
const normRows = (rows) => Object.fromEntries(Object.entries(rows).map(([k, v]) => [normStamp(k), normStamp(v)]));

const BASH_POINTER_2 = '        run bash .aai/scripts/migrate-state-to-local.sh in the target project.\n';
const sortBlock = (text, re, keyOf) => {
  const lines = text.split('\n');
  const out = [];
  for (let i = 0; i < lines.length;) {
    if (!re.test(lines[i])) {
      out.push(lines[i]);
      i += 1;
      continue;
    }
    const block = [];
    while (i < lines.length && re.test(lines[i])) block.push(lines[i++]);
    out.push(...block.sort((a, b) => (keyOf(a) < keyOf(b) ? -1 : keyOf(a) > keyOf(b) ? 1 : 0)));
  }
  return out.join('\n');
};
const PRUNE_LINE = /^ {2}(PROFILE prune \(not in core\)|PRESERVE target-only script): /;
// the registered rewrites of D-CORPUS, each named by the DR it carries; text works on every stream of every step, snap on the target snapshot
const CORPUS_REWRITES = {
  // DR-14: the pointer under the runtime-state block names both launchers (module) where the bash text named one
  'DR-14': { side: 'mod', text: (s) => s.replace(POINTER_2, BASH_POINTER_2) },
  // DR-21: BSD sed leaves two spaces after "Template version:" (the bash side on a host with BSD sed only)
  'DR-21': bsdSed ? { side: 'ref', snap: (rows) => Object.fromEntries(Object.entries(rows).map(([k, v]) => [k, v.replace(/^- Template version:  /m, '- Template version: ')])) } : null,
  // DR-4: an ERROR line the bash twin prints on stdout is on stderr in the module
  'DR-4': { side: 'mod', text: null, steps: (st) => ({ ...st, stdout: st.stdout + st.stderr, stderr: '' }) },
  // DR-26: find order is undefined; the module prunes in byte order, so the bash prune lines and the advisory's deleted items are sorted
  'DR-26': {
    side: 'ref', mayNoop: true,
    text: (s) => sortBlock(s, PRUNE_LINE, (l) => l.slice(l.indexOf(': ') + 2)),
    snap: (rows) => Object.fromEntries(Object.entries(rows).map(([k, v]) => [k, /sync-conflicts-/.test(k) ? sortDeleted(v) : v])),
  },
  // DR-28: a source repository without a commit: bash printed the word HEAD before UNKNOWN as the commit
  'DR-28': { side: 'ref', snap: (rows) => Object.fromEntries(Object.entries(rows).map(([k, v]) => [k, v.replace('- Template commit: HEAD\nUNKNOWN\n', '- Template commit: UNKNOWN\n')])) },
};
function sortDeleted(text) {
  const at = text.indexOf('\n## Deleted items\n');
  if (at < 0) return text;
  const head = text.slice(0, at + '\n## Deleted items\n'.length);
  const items = text.slice(head.length).split('\n\n').map((x) => x.trim()).filter(Boolean);
  items.sort();
  return `${head}\n${items.join('\n\n')}\n`;
}

// runCorpusSide(c, side, root, kind): builds the case for one side, runs every step, snapshots, renames the tree away.
function runCorpusSide(c, side, root, kind) {
  const h = buildCorpusSide(c, side, root);
  const tmp = path.join(root, `tmp-${side}`);
  mkdirSync(tmp);
  const outside = () => snapshotTree(root).filter((r) => !/^(case|tmp-|tree-)/.test(r));
  const outsideBefore = outside();
  let cwd = h.C;
  if (c.cwdLink) {
    mkdirSync(path.join(h.C, 'real', 'deep'), { recursive: true });
    symlinkSync(path.join('real', 'deep'), path.join(h.C, 'lnk'));
    cwd = path.join(h.C, 'lnk');
  }
  const entry = side === 'mod' ? path.join(h.S, '.aai', 'scripts', 'aai-sync.mjs') : path.join(h.S, '.aai', 'scripts', kind === 'bash' ? 'aai-sync.sh' : 'aai-sync.ps1');
  const exe = side === 'mod' ? process.execPath : (kind === 'bash' ? 'bash' : 'pwsh');
  const exeArgs = side === 'ref' && kind === 'ps1' ? ['-NoProfile', '-NonInteractive', '-File'] : [];
  const srcBefore = corpusSnapshot(h.S);
  const watchDir = c.watch ? path.join(h.C, c.watch) : null;
  const watchBefore = watchDir ? corpusSnapshot(watchDir).rows : null;
  const steps = [];
  for (const raw of c.steps) {
    const argv = raw.map((a) => a.split('<T>').join(h.T).split('<S>').join(h.S).split('<C>').join(h.C));
    const targetArg = lstatOrNull(h.T)?.isDirectory() ? h.T : null;
    const r = runSync({ argv, root, target: targetArg, cwd, env: { ...CORPUS_ENV, TMPDIR: tmp }, script: entry, exe, exeArgs, encoding: 'buffer' });
    assert.ok(r.error === undefined, `${c.id} ${side}: ${r.error}`);
    steps.push({ code: r.status, stdout: r.stdout.toString('latin1'), stderr: r.stderr.toString('latin1') });
  }
  const tgt = corpusSnapshot(h.T);
  const srcAfter = corpusSnapshot(h.S);
  const result = { steps, tgt: tgt.rows, tgtEngine: tgt.engine, srcBefore: srcBefore.rows, src: srcAfter.rows, tmp: readdirSync(tmp).sort(), h, watchBefore, watch: watchDir ? corpusSnapshot(watchDir).rows : null };
  assert.deepEqual(outside(), outsideBefore, `${c.id} ${side}: a path outside the case directory changed`);
  renameSync(h.C, path.join(root, `tree-${side}`));
  return result;
}

// applyCorpusRewrites(c, side, result): the registered rewrites of this side; returns the names of those that changed nothing.
function applyCorpusRewrites(c, side, result) {
  const idle = [];
  for (const name of c.rw ?? []) {
    const rw = CORPUS_REWRITES[name];
    if (rw === null || rw === undefined || rw.side !== side) continue;
    let changed = false;
    if (rw.snap) {
      const next = rw.snap(result.tgt);
      changed = JSON.stringify(next) !== JSON.stringify(result.tgt);
      result.tgt = next;
    }
    if (rw.text || rw.steps) {
      for (const st of result.steps) {
        const before = JSON.stringify(st);
        const next = rw.steps ? rw.steps(st) : { ...st, stdout: rw.text(st.stdout), stderr: rw.text(st.stderr) };
        Object.assign(st, next);
        if (JSON.stringify(st) !== before) changed = true;
      }
      if (rw.text) {
        for (const k of Object.keys(result.tgt)) {
          const next = rw.text(result.tgt[k]);
          if (next !== result.tgt[k]) changed = true;
          result.tgt[k] = next;
        }
      }
    }
    if (!changed && !rw.mayNoop) idle.push(name);
  }
  return idle;
}

function corpusStreams(res, keys) {
  return {
    steps: res.steps.map((s) => Object.fromEntries(keys.map((k) => [k, typeof s[k] === 'string' ? normStamp(s[k]) : s[k]]))),
    tgt: normRows(res.tgt),
    ...(keys.includes('stdout') ? { src: normRows(res.src), tmp: res.tmp } : {}),
  };
}

// runCorpusCase(c, kind): the whole differential run of one case; returns both results (after rewrites and normalization).
function runCorpusCase(c, kind, keys, project = (x) => x) {
  const root = scratch(`corpus-${c.id.toLowerCase()}-`);
  try {
    const ref = runCorpusSide(c, 'ref', root, kind);
    const mod = runCorpusSide(c, 'mod', root, kind);
    assert.deepEqual([...applyCorpusRewrites(c, 'ref', ref), ...applyCorpusRewrites(c, 'mod', mod)], [], `${c.id}: a registered rewrite changed nothing`);
    for (const [side, res, list] of [['reference', ref, ENGINE_FILES_REFERENCE], ['module', mod, ENGINE_FILES_MODULE]]) {
      if (c.kit !== 'checkout') assert.ok(res.tgtEngine.every((f) => list.includes(f)), `${c.id}: the ${side} target holds an engine file of the other side: ${res.tgtEngine}`);
      if (c.engine === 'all') assert.deepEqual([...res.tgtEngine].sort(), [...list].sort(), `${c.id}: the ${side} target holds exactly the engine files of its side`);
      if (!c.mutatesSource) assert.deepEqual(res.src, res.srcBefore, `${c.id}: the ${side} run changed the source`);
    }
    if (c.asserted) c.asserted(ref, mod, c);
    else assert.deepEqual(project(corpusStreams(mod, keys)), project(corpusStreams(ref, keys)), `${c.id}: the module differs from the frozen ${kind === 'bash' ? 'bash' : 'PowerShell'} twin`);
    if (c.also) c.also(ref, mod);
    // after every case the scratch root holds no entry besides the marker, the global git config, the per-side TMPDIRs and the two trees
    const allowed = new Set([OWN_MARKER_FILE, 'gitconfig', 'tmp', 'tmp-ref', 'tmp-mod', 'tree-ref', 'tree-mod']);
    for (const name of readdirSync(root)) assert.ok(allowed.has(name), `${c.id}: unexpected entry ${name} in the case scratch root`);
    return { ref, mod };
  } finally {
    const at = scratchDirs.indexOf(root);
    if (at >= 0) scratchDirs.splice(at, 1);
    removeOwnScratch(root);
  }
}

// managedGitignore(): the .gitignore the frozen bash twin writes into an empty target, computed once.
let managedCache = null;
function managedGitignore() {
  if (managedCache !== null) return managedCache;
  const root = scratch('managed-');
  const src = refSource(root);
  const t = path.join(root, 't');
  mkdirSync(t);
  refSync(root, src, t);
  managedCache = readFileSync(path.join(t, '.gitignore'), 'utf8');
  const at = scratchDirs.indexOf(root);
  if (at >= 0) scratchDirs.splice(at, 1);
  removeOwnScratch(root);
  return managedCache;
}

const CORPUS_LEGACY = { 'ai/x': 'legacy\n', 'scripts/tool.sh': 'old tool\n', 'scripts/ai-os-old.sh': 'old\n', 'PLAYBOOK.md': 'play\n', 'docs/workflow/x.txt': 'wf\n', 'docs/ai/LOCKS.md': 'locks\n', 'docs/knowledge/PATTERNS_UNIVERSAL.md': 'pu\n' };
const writeAll = (h, which, files) => { for (const [rel, text] of Object.entries(files)) h.w(which, rel, text); };

// bashCases(): K01 to K32 (and KR1, KR2); each case is a function of nothing, built lazily so the managed text is computed on use.
function bashCases(managed) {
  const m = managed;
  const T = '<T>';
  const k = (id, title, steps, extra = {}) => ({ id, title, steps, rw: ['DR-21'], ...extra });
  const gi = (text) => ({ tgt: (h) => h.w('T', '.gitignore', Buffer.from(text, 'latin1')) });
  const crlf = (t) => t.replace(/\n/g, '\r\n');
  const cases = [
    k('K01', 'a fresh empty git init target, default profile', [[T]], { engine: 'all' }),
    k('K02', 'K01 twice: the second run writes no advisory and nothing changes', [[T], [T]], { engine: 'all' }),
    k('K03', '--profile core, fresh', [[T, '--profile', 'core']]),
    k('K04', 'extended then core: extended-only files pruned, a target-only script and the cache kept', [[T], [T, '--profile', 'core']], {
      rw: ['DR-21', 'DR-26'],
      src: (h) => { for (const f of ['b.md', 'a.md', 'a.b.md', 'a/c.md', 'a-d.md']) h.w('S', `.aai/extra/${f}`, `${f}\n`); h.w('S', '.aai/workflow/Z.md', 'z\n'); },
      tgt: (h) => { h.w('T', '.aai/scripts/x.sh', '#!/bin/sh\n', 0o755); h.w('T', '.aai/cache/keep', 'cache\n'); },
      also: (ref, mod) => {
        // DR-26: the module's prune lines are in byte order of the whole relative path, so the order is the same on every host
        const lines = stepOf(mod, 1).stdout.split('\n').filter((l) => /^ {2}PROFILE prune /.test(l)).map((l) => l.slice(l.indexOf(': ') + 2));
        assert.ok(lines.includes('.aai/extra/a/c.md') && lines.length >= 8, 'the prune lines are there');
        assert.deepEqual(lines, [...lines].sort(), 'prune lines are in byte order');
        assert.ok(lines.indexOf('.aai/extra/a.md') < lines.indexOf('.aai/extra/a/c.md') && lines.indexOf('.aai/extra/a-d.md') < lines.indexOf('.aai/extra/a.b.md'), 'the whole path is sorted, not each directory');
        assert.ok(mod.tgt['.aai/cache/keep'] !== undefined && mod.tgt['.aai/scripts/x.sh'] !== undefined && mod.tgt['.aai/extra'] === undefined, 'the cache and the target-only script stay, the emptied directory goes');
      },
    }),
    k('K05', 'core then no flag (sticky core)', [[T, '--profile', 'core'], [T]]),
    k('K05b', 'core, no flag, then --profile extended', [[T, '--profile', 'core'], [T], [T, '--profile', 'extended']]),
    k('K06a', 'a pin whose first Profile line reads bogus', [[T]], { tgt: (h) => h.w('T', '.aai/system/AAI_PIN.md', '# AAI Pin\n- Profile: bogus\n- Profile: core\n') }),
    k('K06b', 'a CRLF pin recording core', [[T]], { tgt: (h) => h.w('T', '.aai/system/AAI_PIN.md', '# AAI Pin\r\n- Profile: core\r\n') }),
    k('K07', 'the core list padded with 20,000 fake entries', [[T, '--profile', 'core'], [T, '--profile', 'core']], {
      src: (h) => h.w('S', '.aai/system/PROFILES.yaml', profilesText([...CORPUS_CORE, ...Array.from({ length: 20000 }, (_, i) => `.aai/fake/f${String(i).padStart(5, '0')}.md`)])),
    }),
    k('K08', 'extended with a stale .aai/OLD.md and a target-only script', [[T]], { tgt: (h) => { h.w('T', '.aai/OLD.md', 'old\n'); h.w('T', '.aai/scripts/own.sh', '#!/bin/sh\n', 0o755); } }),
  ];
  const g = (id, title, text, extra = {}) => cases.push(k(id, title, [[T]], { ...gi(text), ...extra }));
  g('K09a', 'an LF .gitignore without the managed lines', 'node_modules/\ndist/\n');
  g('K09a2', 'no final newline', 'node_modules/\ndist');
  g('K09b', 'a CRLF .gitignore', crlf('node_modules/\n.agents/skills/\n.claude/skills/\ndocs/ai/STATE.yaml\n'));
  g('K09c', 'every managed block twice (self-heal)', `${m}\n${m}`, { rw: ['DR-21'] });
  g('K09c2', 'every managed block twice with blank runs and a project line', `build/\n\n\n${m}\n\nmine.log\n${m}\n\n\n`, { rw: ['DR-21'] });
  g('K09c3', 'every managed block twice, CRLF', crlf(`${m}${m}`), { rw: ['DR-21'] });
  g('K09d', 'only .aai/cache/ present (the prefix reading)', 'src/\n.aai/cache/\n');
  g('K09e', 'a 200 KB .gitignore with the managed lines at the top', `${m}${'padding/line/of/a/large/ignore/file\n'.repeat(5800)}`, { rw: ['DR-21'] });
  g('K09f', 'the .ps1 marker text already present', `${PS1_MARKER}\nlogs/\n`);
  g('K09g', 'no list in the source', 'x/\n', { rw: ['DR-14', 'DR-21'], src: (h) => h.rm('S', '.aai/system/RUNTIME_IGNORE.list'), tgt: (h) => { h.w('T', '.gitignore', 'x/\n'); h.w('T', '.aai/system/RUNTIME_IGNORE.list', 'custom/one\n'); } });
  g('K09h', 'no list anywhere (the note)', 'x/\n', { rw: ['DR-14', 'DR-21'], src: (h) => h.rm('S', '.aai/system/RUNTIME_IGNORE.list') });
  g('K09j', 'managed lines with trailing whitespace are kept, only the exact duplicate goes (DR-12)', 'build/\n.aai/ \n.aai/\n.aai/cache/\t\n.aai/cache/\n.aai/\n');
  cases.push(
    k('K09i', 'no .gitignore at all', [[T]], {}),
    k('K10', 'skill trees: a differing template skill, a project skill, a retired wrapper, a near miss, a link entry', [[T]], {
      tgt: (h) => {
        for (const tree of ['.claude/skills', '.agents/skills']) {
          h.w('T', `${tree}/aai-alive/SKILL.md`, 'local\n');
          h.w('T', `${tree}/aai-project-x/SKILL.md`, 'mine\n');
          h.w('T', `${tree}/aai-gone/SKILL.md`, wrapperText('aai-gone', 'GONE'));
          h.w('T', `${tree}/aai-near/SKILL.md`, wrapperText('aai-near', 'GONE').replace('follow', 'folloW'));
          h.link('T', `${tree}/aai-link`, '../elsewhere');
        }
        h.w('T', '.claude/skills/aai-two/aux/extra.md', 'changed\n');
      },
    }),
    k('K11', 'differing .codex/skills and .gemini/skills, skills.local kept', [[T]], {
      tgt: (h) => { h.w('T', '.codex/skills/README.md', 'local codex\n'); h.w('T', '.gemini/skills/README.md', 'local gemini\n'); h.w('T', '.codex/skills.local/keep.md', 'k\n'); },
    }),
    k('K12', 'knowledge: a sentinel file replaced, one without it skipped', [[T]], { tgt: (h) => { h.w('T', 'docs/knowledge/FACTS.md', 'AAI-TEMPLATE old\n'); h.w('T', 'docs/knowledge/PATTERNS.md', 'mine\n'); } }),
    k('K13a', 'the three seeds absent (seeded)', [[T]], {}),
    k('K13b', 'the three seeds present (kept)', [[T]], { tgt: (h) => { h.w('T', 'docs/TECHNOLOGY.md', 'mine\n'); h.w('T', 'docs/ai/update-config.yaml', 'mine\n'); h.w('T', 'docs/ai/docs-audit.yaml', 'mine\n'); } }),
    k('K14', 'differing root shims and README_AAI.md (conflicts)', [[T]], { tgt: (h) => { for (const f of ['AGENTS.md', 'CLAUDE.md', 'CODEX.md', 'GEMINI.md', 'SKILLS.md', 'README_AAI.md']) h.w('T', f, `local ${f}\n`); } }),
    k('K15a', 'the Copilot shim absent', [[T]], {}),
    k('K15b', 'the Copilot shim identical', [[T]], { tgt: (h) => h.w('T', '.github/copilot-instructions.md', SHIM_NEW) }),
    k('K15c', 'an older shipped shim (hash listed)', [[T]], { tgt: (h) => h.w('T', '.github/copilot-instructions.md', SHIM_OLD) }),
    k('K15d', 'a project-overrides block (merged)', [[T]], { tgt: (h) => h.w('T', '.github/copilot-instructions.md', mergedShim('my rule\nsecond rule')) }),
    k('K15e', 'an empty block with the override file fallback', [[T]], { tgt: (h) => { h.w('T', '.github/copilot-instructions.md', `${OV_START}\n${OV_END}\n`); h.w('T', OV_FILE, 'file rule\n'); } }),
    k('K16a', 'a target-only hook kept', [[T]], { tgt: (h) => h.w('T', 'hooks/merge-guard.sh', '#!/bin/sh\n', 0o755) }),
    k('K16b', 'hooks.json absent', [[T]], {}),
    k('K16c', 'a malformed hooks.json (refused, untouched)', [[T]], { tgt: (h) => h.w('T', 'hooks/hooks.json', '{bad') }),
    k('K16d', 'a user-modified hook entry (left as-is)', [[T]], { tgt: (h) => h.w('T', 'hooks/hooks.json', hooksJson(hookCmd('--old'))) }),
    k('K16e', 'the dotfile hook replaced', [[T]], { tgt: (h) => h.w('T', 'hooks/.hidden-hook.sh', 'old\n') }),
    k('K16f', 'session-start.sh executable afterwards', [[T]], { tgt: (h) => h.w('T', 'hooks/session-start.sh', 'old\n', 0o600) }),
    k('K17', 'a legacy-layout target (the moves are dropped, DR-13)', [[T]], { tgt: (h) => writeAll(h, 'T', CORPUS_LEGACY) }),
    k('K18', '-h', [['-h']], { rw: [] }),
    k('K19', '--bogus with a target', [['--bogus', T]], { rw: [] }),
    k('K20', 'no argument', [[]], { rw: [] }),
    k('K21', 'two positionals', [[T, '<C>/second']], { rw: [] }),
    k('K22', 'a bare --profile', [[T, '--profile']], { rw: [] }),
    k('K23', '--profile=bogus then the target', [['--profile=bogus', T]], { rw: [] }),
    k('K24', 'a missing target directory', [['<C>/missing']], { rw: ['DR-4'] }),
    k('K25', 'the target is the source itself (DR-5)', [['<S>']], { rw: [], mutatesSource: true, noTgt: true }),
    k('K26', 'the target lies inside the source (DR-5)', [['<S>/sub']], { rw: [], mutatesSource: true, noTgt: true, src: (h) => h.w('S', 'sub/.keep', '') }),
    k('K27', 'a target whose .claude/skills is a link out of the target (DR-7)', [[T]], { rw: [], watch: 'outside', asserted: 'K27', tgt: (h) => { h.mkdir('C', 'outside'); h.link('T', '.claude/skills', '../../outside'); } }),
    k('K28', 'a target path holding a space and brackets', [[T]], { tname: 't [x] y' }),
    k('K29', 'a relative ../t from a symbolic-link working directory, the target present on both readings', [['../t']], { tname: 't', cwdLink: true, tgt: (h) => h.mkdir('C', 'real/t') }),
    k('K29b', 'a relative ../t that exists only on the logical reading (DR-30)', [['../t']], { tname: 't', cwdLink: true, rw: [], asserted: 'K29b' }),
    k('K30a', 'no AAI_VERSION.md (the tag fallback)', [[T]], { rw: [], src: (h) => h.rm('S', 'docs/ai/AAI_VERSION.md') }),
    k('K30b', 'a source repository without a commit (DR-28)', [[T]], { noCommit: true, rw: ['DR-21', 'DR-28'] }),
    k('K30c', 'a source without git (UNKNOWN)', [[T]], { noGit: true }),
    k('K30d', 'no tag and no version file', [[T]], { rw: [], noTag: true, src: (h) => h.rm('S', 'docs/ai/AAI_VERSION.md') }),
    k('K31a', 'dangling links: top-level entries of the source and the target, and a nested one (DR-27, DR-15)', [[T]], {
      src: (h) => { for (const rel of ['.aai/dangle.md', '.aai/scripts/dangle.sh', '.claude/skills/aai-dangling', '.agents/skills/aai-dangling2', 'hooks/dangle.sh', '.aai/workflow/nested']) h.link('S', rel, 'nowhere'); },
      tgt: (h) => { h.link('T', '.aai/stale-dangle.md', 'nowhere'); h.link('T', '.aai/scripts/t-dangle.sh', 'nowhere'); h.link('T', '.claude/skills/aai-tdangle', 'nowhere'); },
      also: (ref, mod) => {
        // DR-27: a dangling link that is a top-level entry of a globbed directory is skipped, in the source and the target
        for (const rel of ['.aai/dangle.md', '.aai/scripts/dangle.sh', '.claude/skills/aai-dangling', '.agents/skills/aai-dangling2', 'hooks/dangle.sh']) assert.equal(mod.tgt[rel], undefined, `${rel} was not copied`);
        for (const rel of ['.aai/stale-dangle.md', '.aai/scripts/t-dangle.sh', '.claude/skills/aai-tdangle']) assert.equal(mod.tgt[rel], 'link:nowhere', `${rel} was left alone`);
        // DR-15: a dangling link nested in a copied directory is copied as a link
        assert.equal(mod.tgt['.aai/workflow/nested'], 'link:nowhere');
      },
    }),
    k('K31b', 'extended then core with a dangling link in the target .aai', [[T], [T, '--profile', 'core']], {
      rw: ['DR-21', 'DR-26'],
      tgt: (h) => { h.link('T', '.aai/extra/lnk', 'only.md'); h.link('T', '.aai/extra/dang', 'nowhere'); h.link('T', '.aai/workflow/lnk2', 'WORKFLOW.md'); },
    }),
    k('K32a', 'a .gitignore that is a link leaving the target (DR-29)', [[T]], { rw: [], watch: 'outside', asserted: 'K32a', tgt: (h) => { h.mkdir('C', 'outside'); h.w('C', 'outside/ig', 'outside\n'); h.link('T', '.gitignore', '../outside/ig'); } }),
    k('K32b', 'a .gitignore that is a link inside the target', [[T]], { tgt: (h) => { h.w('T', 'real.ign', 'inside\n'); h.link('T', '.gitignore', 'real.ign'); } }),
    k('KR1', 'the checkout as the source, extended', [[T]], { kit: 'checkout' }),
    k('KR2', 'the checkout as the source, core', [[T, '--profile', 'core']], { kit: 'checkout' }),
  );
  return cases;
}

const BASH_KEYS = ['code', 'stdout', 'stderr'];
const PS_KEYS = ['code'];

const utf8 = (latin1) => Buffer.from(latin1, 'latin1').toString('utf8');
const USAGE_LINE = 'Usage: .aai/scripts/aai-sync.sh <path-to-target-project> [--profile core|extended]\n';
const hasNone = (rows, prefixes) => Object.keys(rows).filter((k) => prefixes.some((p) => k === p || k.startsWith(`${p}/`)));
const same = (a, b, why) => assert.deepEqual(a, b, why);
// stepOf(res, n): the n-th step of a side
const stepOf = (res, n = 0) => res.steps[n];
// moduleRefused(mod, text): the module's whole refusal: exit 1, nothing on stdout but the banner, the named text on stderr, the target and source untouched
function moduleRefused(mod, id, text) {
  const st = stepOf(mod);
  assert.equal(st.code, 1, `${id}: exit 1`);
  assert.ok(st.stderr.startsWith('ERROR: '), `${id}: an ERROR line on stderr: ${st.stderr}`);
  assert.ok(st.stderr.includes(text), `${id}: stderr names ${text}: ${st.stderr}`);
  assert.ok(st.stderr.includes('nothing was written'), `${id}: stderr says nothing was written`);
  assert.deepEqual(mod.src, mod.srcBefore, `${id}: the source is unchanged`);
}

// The asserted divergences of the bash side: each compares both sides to the expected values of the DR it names.
const BASH_ASSERTED = {
  K17(ref, mod) {
    const gone = ['ai', 'scripts', 'docs/workflow', 'PLAYBOOK.md', 'docs/ai/LOCKS.md', 'docs/knowledge/PATTERNS_UNIVERSAL.md'];
    assert.ok(stepOf(ref).stdout.includes('  MIGRATE removed legacy: ai/\n') && stepOf(ref).stdout.includes('  Legacy paths migrated to .aai/ structure.\n'), 'the bash twin migrates');
    assert.deepEqual(hasNone(ref.tgt, ['ai', 'scripts', 'PLAYBOOK.md', 'docs/ai/LOCKS.md', 'docs/knowledge/PATTERNS_UNIVERSAL.md']), [], 'the bash twin deleted the legacy paths');
    assert.ok(!/MIGRATE|Legacy paths/.test(stepOf(mod).stdout), 'the module prints no MIGRATE or Legacy line');
    for (const [rel, text] of Object.entries(CORPUS_LEGACY)) assert.equal(mod.tgt[rel], `file:644:${text}`, `the module keeps ${rel} byte for byte`);
    const strip = (res, drop) => {
      const rows = Object.fromEntries(Object.entries(res.tgt).filter(([k]) => !hasNone({ [k]: 1 }, gone).length));
      const lines = stepOf(res).stdout.split('\n').filter((l) => !(drop && /^ {2}(MIGRATE|Legacy paths)/.test(l))).join('\n');
      return { rows: normRows(rows), lines: normStamp(lines), code: stepOf(res).code, stderr: stepOf(res).stderr };
    };
    same(strip(mod, false), strip(ref, true), 'everything else is equal');
  },
  K18(ref, mod) {
    assert.equal(stepOf(ref).code, 1, 'the bash twin takes -h as a target');
    assert.equal(stepOf(ref).stdout, 'ERROR: Target directory does not exist: -h\n');
    assert.deepEqual({ ...stepOf(mod), stdout: utf8(stepOf(mod).stdout) }, { code: 0, stdout: expectedHelp(), stderr: '' }, 'the module prints the help on stdout, exit 0');
    same(mod.tgt, ref.tgt);
  },
  K19(ref, mod, c) {
    assert.equal(stepOf(ref).code, 1);
    assert.ok(stepOf(ref).stdout.startsWith('ERROR: unexpected argument: '), 'the bash twin took --bogus as the target');
    assert.deepEqual(stepOf(mod), { code: 2, stdout: '', stderr: `ERROR: unexpected argument: --bogus\n${USAGE_LINE}` });
    same(mod.tgt, ref.tgt);
  },
  K20(ref, mod) {
    assert.equal(stepOf(ref).code, 1);
    assert.equal(stepOf(ref).stdout, `Usage: ${ref.h.S}/.aai/scripts/aai-sync.sh <path-to-target-project> [--profile core|extended]\n`);
    assert.deepEqual(stepOf(mod), { code: 2, stdout: '', stderr: USAGE_LINE });
    same(mod.tgt, ref.tgt);
  },
  K21(ref, mod) {
    assert.equal(stepOf(ref).code, 1);
    assert.ok(stepOf(ref).stdout.startsWith(`ERROR: unexpected argument: ${ref.h.C}/second\n`));
    assert.deepEqual(stepOf(mod), { code: 2, stdout: '', stderr: `ERROR: unexpected argument: ${mod.h.C}/second\n${USAGE_LINE}` });
    same(mod.tgt, ref.tgt);
  },
  K22(ref, mod) {
    assert.deepEqual([stepOf(ref).code, stepOf(ref).stdout], [1, 'ERROR: --profile needs a value (core|extended)\n']);
    assert.deepEqual(stepOf(mod), { code: 2, stdout: '', stderr: `ERROR: --profile needs a value (core|extended)\n${USAGE_LINE}` });
    same(mod.tgt, ref.tgt);
  },
  K23(ref, mod) {
    assert.deepEqual([stepOf(ref).code, stepOf(ref).stdout], [1, 'ERROR: invalid --profile value: bogus (allowed: core|extended)\n']);
    assert.deepEqual(stepOf(mod), { code: 2, stdout: '', stderr: `ERROR: invalid --profile value: bogus (allowed: core|extended)\n${USAGE_LINE}` });
    same(mod.tgt, ref.tgt);
  },
  K25(ref, mod) {
    assert.equal(stepOf(ref).code, 1, 'the bash twin fails after copying over itself');
    assert.notDeepEqual(ref.src, ref.srcBefore, 'the bash twin damaged its source');
    assert.equal(ref.src['.aai/AGENTS.md'], undefined, 'the bash twin lost a source file');
    moduleRefused(mod, 'K25', mod.h.S);
    assert.equal(stepOf(mod).stdout, '');
  },
  K26(ref, mod) {
    assert.equal(stepOf(ref).code, 0, 'the bash twin syncs into a directory inside its source');
    assert.ok(ref.src['sub/.aai/AGENTS.md'] !== undefined, 'the bash twin wrote a layer into the source tree');
    moduleRefused(mod, 'K26', `${mod.h.S}/sub`);
    assert.equal(stepOf(mod).stdout, '');
  },
  K27(ref, mod) {
    assert.ok(Object.keys(ref.watch).some((k) => k.startsWith('.claude') === false && k !== ''), 'the bash twin wrote through the link');
    assert.notDeepEqual(ref.watch, ref.watchBefore);
    moduleRefused(mod, 'K27', '.claude/skills');
    assert.deepEqual(mod.watch, mod.watchBefore, 'nothing was written through the link');
    assert.equal(stepOf(mod).stdout, '', 'nothing printed before the refusal');
    assert.deepEqual(Object.keys(mod.tgt).sort(), ['.claude', '.claude/skills'], 'the target holds only what the case put there');
  },
  K29b(ref, mod) {
    assert.equal(stepOf(ref).code, 1, 'the bash twin tests -d on the physical path');
    assert.equal(stepOf(ref).stdout, 'ERROR: Target directory does not exist: ../t\n');
    assert.equal(stepOf(mod).code, 0, 'the module resolves ../t from the logical working directory, as cd does');
    assert.ok(stepOf(mod).stdout.includes(`Target project:     ${mod.h.C}/t\n`));
  },
  K32a(ref, mod) {
    assert.equal(stepOf(ref).code, 0, 'the bash twin appended through the link');
    assert.notDeepEqual(ref.watch, ref.watchBefore, 'the file outside the target changed');
    moduleRefused(mod, 'K32a', '.gitignore');
    assert.deepEqual(mod.watch, mod.watchBefore, 'the file outside the target is unchanged');
    assert.equal(stepOf(mod).stdout, '', 'nothing printed before the refusal');
    assert.deepEqual(Object.keys(mod.tgt), ['.gitignore'], 'the target holds only the link');
  },
};

const bashSkip = process.platform === 'win32' ? 'the bash-side corpus runs on POSIX hosts' : !bashAvailable ? 'bash is not installed here' : !gitAvailable ? 'git is not installed here' : false;
const pwshSkip = process.platform === 'win32' ? 'the PowerShell-side corpus runs on POSIX hosts' : !pwshAvailable ? 'pwsh is not installed on this host; the Windows CI job (ps1-quality) runs the PowerShell-side corpus' : !gitAvailable ? 'git is not installed here' : false;

describe('TEST-4013 the bash-side corpus K01 to K32, KR1 and KR2 against the frozen bash reference', { skip: bashSkip }, () => {
  const cases = bashCases(managedGitignore());
  for (const c of cases) if (BASH_ASSERTED[c.id]) c.asserted = BASH_ASSERTED[c.id]; else delete c.asserted;
  test('TEST-4013 the corpus holds every K case with its lettered variants and KR1 and KR2, each registered rewrite names a DR, and no case is filtered away', () => {
    const ids = cases.map((c) => c.id);
    assert.equal(new Set(ids).size, ids.length);
    const want = ['K01', 'K02', 'K03', 'K04', 'K05', 'K05b', 'K06a', 'K06b', 'K07', 'K08', 'K09a', 'K09a2', 'K09b', 'K09c', 'K09c2', 'K09c3', 'K09d', 'K09e', 'K09f', 'K09g', 'K09h', 'K09j', 'K09i',
      'K10', 'K11', 'K12', 'K13a', 'K13b', 'K14', 'K15a', 'K15b', 'K15c', 'K15d', 'K15e', 'K16a', 'K16b', 'K16c', 'K16d', 'K16e', 'K16f', 'K17', 'K18', 'K19', 'K20', 'K21', 'K22', 'K23', 'K24',
      'K25', 'K26', 'K27', 'K28', 'K29', 'K29b', 'K30a', 'K30b', 'K30c', 'K30d', 'K31a', 'K31b', 'K32a', 'K32b', 'KR1', 'KR2'];
    assert.deepEqual(ids, want);
    for (const c of cases) for (const name of c.rw ?? []) assert.ok(name in CORPUS_REWRITES, `${c.id}: the rewrite ${name} is not registered`);
    for (const id of ['K17', 'K18', 'K19', 'K20', 'K21', 'K22', 'K23', 'K25', 'K26', 'K27', 'K29b', 'K32a']) assert.equal(typeof cases.find((c) => c.id === id).asserted, 'function', `${id} is an asserted divergence`);
  });
  test('TEST-4013 a registered rewrite that changes nothing fails the case', () => {
    const k01 = cases.find((c) => c.id === 'K01');
    assert.throws(() => runCorpusCase({ ...k01, rw: ['DR-14'] }, 'bash', BASH_KEYS), /a registered rewrite changed nothing/);
  });
  for (const c of cases) {
    test(`TEST-4013 ${c.id} ${c.title}`, () => {
      runCorpusCase(c, 'bash', BASH_KEYS);
    });
  }
});

// psCases(): P01 to P16, PowerShell-form arguments; compared on exit code and the target snapshot (DR-11, DR-20 and DR-21 projected away).
function psCases() {
  const TR = (...more) => ['-TargetRoot', '<T>', ...more];
  const p = (id, title, steps, extra = {}) => ({ id, title, steps, rw: [], ...extra });
  return [
    p('P01', 'a fresh -TargetRoot', [TR()]),
    p('P02', 'twice', [TR(), TR()]),
    p('P03', '-Profile core', [TR('-Profile', 'core')]),
    p('P04', 'extended then core', [TR(), TR('-Profile', 'core')]),
    p('P05', 'core then sticky', [TR('-Profile', 'core'), TR()]),
    p('P06', 'a CRLF .gitignore with duplicates (DR-11)', [TR()], { tgt: (h) => h.w('T', '.gitignore', `node_modules/\r\ndocs/ai/STATE.yaml\r\ndocs/ai/STATE.yaml\r\n.wrangler/\r\n.wrangler/\r\n`) }),
    p('P07', 'a Copilot overrides block (DR-17)', [TR()], { tgt: (h) => h.w('T', '.github/copilot-instructions.md', mergedShim('  my rule  \n')) }),
    p('P08', 'a hooks.json merge and session-start.sh (DR-18)', [TR()], { tgt: (h) => h.w('T', 'hooks/hooks.json', hooksJson(hookCmd('--old'))) }),
    p('P09', 'skill conflicts and a retired wrapper', [TR()], {
      tgt: (h) => { h.w('T', '.claude/skills/aai-alive/SKILL.md', 'local\n'); h.w('T', '.claude/skills/aai-gone/SKILL.md', wrapperText('aai-gone', 'GONE')); h.w('T', '.agents/skills/aai-project-x/SKILL.md', 'mine\n'); },
    }),
    p('P10', 'a knowledge file holding aai-template in lower case (DR-16)', [TR()], { tgt: (h) => { h.w('T', 'docs/knowledge/FACTS.md', 'aai-template lower case\n'); h.w('T', 'docs/knowledge/PATTERNS.md', 'mine\n'); } }),
    p('P11', '-h (DR-1)', [['-h']]),
    p('P12', 'no -TargetRoot, under -NonInteractive (DR-25)', [[]]),
    p('P13', '-Profile bogus (DR-2)', [TR('-Profile', 'bogus')]),
    p('P14', 'a missing target', [['-TargetRoot', '<C>/missing']]),
    p('P15', 'the K17 legacy layout (DR-13)', [TR()], { tgt: (h) => writeAll(h, 'T', CORPUS_LEGACY) }),
    p('P16', 'a dangling link nested in a source skill (DR-15)', [TR()], { src: (h) => h.link('S', '.claude/skills/aai-alive/dangling', 'nowhere') }),
    p('P17', 'a dangling link as a top-level entry of the source .claude/skills (DR-27)', [TR()], { src: (h) => h.link('S', '.claude/skills/aai-dangling', 'nowhere') }),
  ];
}

// The projections of the PowerShell side (DR-11, DR-18, DR-20, DR-21): what the module took from the bash side and the .ps1 wrote
// differently is reduced to what both write (the order of the deleted items is DR-26 on this side too): the .gitignore to its set of pattern lines (order, blank lines, comment headers and
// the marker text are DR-11), the report without its backticks (DR-20), the pin without the Template version spacing (DR-21), and the hook
// files without their execute bits (DR-18).
const PS_PROJECTIONS = {
  'DR-11': (rows) => Object.fromEntries(Object.entries(rows).map(([k, v]) => [k, k === '.gitignore'
    ? `gitignore:${[...new Set(v.replace(/^file:\d+:/, '').split(/\r?\n/).filter((l) => l !== '' && !l.startsWith('#')))].sort().join('\n')}`
    : v])),
  'DR-20': (rows) => Object.fromEntries(Object.entries(rows).map(([k, v]) => [k, /^docs\/ai\/reports\/sync-conflicts-/.test(k) ? v.replace(/`/g, '') : v])),
  'DR-21': (rows) => Object.fromEntries(Object.entries(rows).map(([k, v]) => [k, k === '.aai/system/AAI_PIN.md' ? v.replace(/^- Template version: +/m, '- Template version: ') : v])),
  'DR-26': (rows) => Object.fromEntries(Object.entries(rows).map(([k, v]) => [k, /^docs\/ai\/reports\/sync-conflicts-/.test(k) ? sortDeleted(v) : v])),
  'DR-18': (rows) => Object.fromEntries(Object.entries(rows).map(([k, v]) => [k, /^hooks\/[^/]+\.sh$/.test(k) ? v.replace(/^file:\d+:/, 'file:<MODE>:') : v])),
};
const psProject = (streams) => ({ ...streams, tgt: Object.values(PS_PROJECTIONS).reduce((rows, f) => f(rows), streams.tgt) });

const psDrop = (streams, prefixes) => ({ ...streams, tgt: Object.fromEntries(Object.entries(streams.tgt).filter(([k]) => !prefixes.some((p) => k === p || k.startsWith(`${p}/`)))) });
// psRest(ref, mod, drop): everything but the dropped rows is equal after the projections
const psRest = (ref, mod, drop = []) => same(psProject(psDrop(corpusStreams(mod, PS_KEYS), drop)), psProject(psDrop(corpusStreams(ref, PS_KEYS), drop)), 'the rest of the run is equal');
const rowOf = (res, rel) => res.tgt[rel];

// The asserted divergences of the PowerShell side: the exit code and the target of each DR it names, the rest equal.
const PS_ASSERTED = {
  P06(ref, mod) {
    assert.ok(rowOf(ref, '.gitignore').includes(PS1_MARKER), 'the .ps1 writes its own marker text');
    assert.ok(rowOf(mod, '.gitignore').includes('# AAI runtime sidecars (seeded from .aai/system/RUNTIME_IGNORE.list; per-dev, never commit)') && !rowOf(mod, '.gitignore').includes(PS1_MARKER), 'the module writes the bash marker text');
    assert.notEqual(rowOf(mod, '.gitignore'), rowOf(ref, '.gitignore'), 'the bytes differ');
    assert.ok(rowOf(mod, '.gitignore').includes('\r\n'), 'a CRLF file stays CRLF');
    psRest(ref, mod);
  },
  P07(ref, mod) {
    assert.equal(rowOf(ref, OV_FILE), 'file:644:my rule\n', 'the .ps1 trims the overrides');
    assert.equal(rowOf(mod, OV_FILE), 'file:644:  my rule  \n', 'the module keeps the bash bytes');
    assert.notEqual(rowOf(mod, '.github/copilot-instructions.md'), rowOf(ref, '.github/copilot-instructions.md'));
    assert.ok(rowOf(mod, '.github/copilot-instructions.md').endsWith('<!-- AAI-PROJECT-OVERRIDES:END -->\n'), 'the merged shim ends with a final newline');
    psRest(ref, mod, [OV_FILE, '.github/copilot-instructions.md']);
  },
  P08(ref, mod) {
    assert.ok(rowOf(ref, 'hooks/session-start.sh').startsWith('file:644:'), 'the .ps1 leaves session-start.sh non-executable');
    assert.ok(rowOf(mod, 'hooks/session-start.sh').startsWith('file:755:'), 'the module makes it executable');
    psRest(ref, mod);
  },
  P10(ref, mod) {
    assert.equal(rowOf(ref, 'docs/knowledge/FACTS.md'), 'file:644:AAI-TEMPLATE facts\n', 'the .ps1 matches the sentinel in any case and replaces the file');
    assert.equal(rowOf(mod, 'docs/knowledge/FACTS.md'), 'file:644:aai-template lower case\n', 'the module is case-sensitive and keeps it');
    psRest(ref, mod, ['docs/knowledge/FACTS.md']);
  },
  P11(ref, mod) {
    assert.equal(stepOf(ref).code, 1, 'a binding error');
    assert.deepEqual({ ...stepOf(mod), stdout: utf8(stepOf(mod).stdout) }, { code: 0, stdout: expectedHelp(), stderr: '' });
    same(mod.tgt, ref.tgt);
  },
  P12(ref, mod) {
    assert.equal(stepOf(ref).code, 1, 'the .ps1 fails under -NonInteractive');
    assert.deepEqual(stepOf(mod), { code: 2, stdout: '', stderr: USAGE_LINE });
    same(mod.tgt, ref.tgt);
  },
  P13(ref, mod) {
    assert.equal(stepOf(ref).code, 1, 'the .ps1 throws');
    assert.deepEqual(stepOf(mod), { code: 2, stdout: '', stderr: `ERROR: invalid --profile value: bogus (allowed: core|extended)\n${USAGE_LINE}` });
    same(mod.tgt, ref.tgt);
  },
  P15(ref, mod) {
    for (const rel of ['ai/x', 'scripts/tool.sh', 'PLAYBOOK.md', 'docs/ai/LOCKS.md', 'docs/knowledge/PATTERNS_UNIVERSAL.md']) {
      assert.equal(rowOf(ref, rel), undefined, `the .ps1 deleted ${rel}`);
      assert.equal(rowOf(mod, rel), `file:644:${CORPUS_LEGACY[rel]}`, `the module kept ${rel}`);
    }
    psRest(ref, mod, ['ai', 'scripts', 'PLAYBOOK.md', 'docs/ai/LOCKS.md', 'docs/knowledge/PATTERNS_UNIVERSAL.md', 'docs/workflow']);
  },
  P16(ref, mod) {
    assert.equal(stepOf(ref).code, 1, 'Copy-Item crashes on the dangling link');
    assert.equal(stepOf(mod).code, 0);
    assert.equal(rowOf(mod, '.claude/skills/aai-alive/dangling'), 'link:nowhere', 'the module copies it as a link');
  },
  P17(ref, mod) {
    assert.equal(stepOf(ref).code, 1, 'Copy-Item crashes on the dangling link');
    assert.equal(stepOf(mod).code, 0);
    assert.equal(rowOf(mod, '.claude/skills/aai-dangling'), undefined, 'the module skips a dangling top-level entry, as bash does');
  },
};

describe('TEST-4014 the PowerShell-side corpus P01 to P17 against the frozen PowerShell reference', { skip: pwshSkip }, () => {
  const cases = psCases();
  for (const c of cases) if (PS_ASSERTED[c.id]) c.asserted = PS_ASSERTED[c.id];
  test('TEST-4014 the corpus holds P01 to P17 and no case is filtered away', () => {
    assert.deepEqual(cases.map((c) => c.id), Array.from({ length: 17 }, (_, i) => `P${String(i + 1).padStart(2, '0')}`));
    for (const id of ['P06', 'P07', 'P08', 'P10', 'P11', 'P12', 'P13', 'P15', 'P16', 'P17']) assert.equal(typeof cases.find((c) => c.id === id).asserted, 'function', `${id} is an asserted divergence`);
  });
  for (const c of cases) {
    test(`TEST-4014 ${c.id} ${c.title}`, () => {
      runCorpusCase(c, 'ps1', PS_KEYS, psProject);
    });
  }
});
