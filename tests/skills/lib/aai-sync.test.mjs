// aai-sync.test.mjs - node:test cases of the sync-on-node ride
// (docs/specs/SPEC-DRAFT-spec-sync-on-node.md). Every case name starts with its TEST id; the suite
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
import {
  copyFileSync, existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, readlinkSync, realpathSync, renameSync, statSync,
  symlinkSync, writeFileSync,
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
export function runSync({ argv = [], root, target = null, cwd = root, env = {}, script = MODULE, exe = process.execPath }) {
  const runEnv = prepareEnv(root, { PWD: cwd, ...env });
  assert.equal(runEnv.GIT_CONFIG_NOSYSTEM, '1');
  assert.equal(readFileSync(runEnv.GIT_CONFIG_GLOBAL, 'utf8'), '', 'GIT_CONFIG_GLOBAL is an empty file');
  assertTargetUnderRoot(target, root, cwd, argv);
  assert.ok(script === MODULE || under(script, root), `the script ${script} is neither the module nor under the scratch root`);
  return spawnSync(exe, [script, ...argv], { cwd, env: runEnv, encoding: 'utf8' });
}

// runInProcess({ argv, root, target, cwd, env, scriptPath, spawn }): the one way these tests call the module's run().
// The scrubbed environment goes in as io.env; the child seam records and never starts anything real unless spawn is given.
async function runInProcess({ argv = [], root, target = null, cwd = root, env = {}, scriptPath = MODULE, spawn = null }) {
  const runEnv = prepareEnv(root, { PWD: cwd, ...env });
  assertTargetUnderRoot(target, root, cwd, argv);
  const { run } = await import(MODULE_URL);
  const out = [];
  const err = [];
  const calls = [];
  const seam = spawn ?? ((file, args) => { calls.push([file, args]); return { status: 1, stdout: '', stderr: '' }; });
  const code = await run(argv, { out: (s) => out.push(s), err: (s) => err.push(s), env: runEnv, cwd, spawn: seam, scriptPath });
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
        if (/(aai-sync-(node|docs|fixtures)|aai-sync\.(test|Tests)|sync-reference|resolve-base\.test|git-env-scrub)/.test(name) && !exempt.has(name) && statSync(path.join(dir, name)).isFile()) found.push(path.join(dir, name));
      }
    }
    for (const f of found) assert.ok(NEW_TEST_FILES.includes(f), `${f} is a test file of this ride and must be added to NEW_TEST_FILES`);
    for (const f of NEW_TEST_FILES) assert.ok(found.includes(f), `${f} is listed but not found by name`);
  });

  test('TEST-4000 every sync invocation sets the git environment and asserts the target under the scratch root', () => {
    for (const file of NEW_TEST_FILES) {
      const src = readFileSync(file, 'utf8');
      const problems = file.endsWith('.sh') ? shellInvocationProblems(src) : invocationProblems(src);
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
    prepareEnv(root);
    const before = snapshotTree(root);
    let r = runSync({ argv: [target, '--profile', 'core'], root, target, script: noManifest.script });
    assert.equal(r.status, 1);
    assert.equal(r.stderr, `ERROR: --profile core requires the manifest: ${path.join(noManifest.src, '.aai', 'system', 'PROFILES.yaml')}\n`);
    assert.equal(r.stdout, header(noManifest.src));
    for (const s of [emptyList, noBlock, crlf]) {
      r = runSync({ argv: [target, '--profile', 'core'], root, target, script: s.script });
      assert.equal(r.status, 1, s.src);
      assert.equal(r.stderr, `ERROR: no core entries found in ${path.join(s.src, '.aai', 'system', 'PROFILES.yaml')}\n`);
      assert.equal(r.stdout, header(s.src));
    }
    assert.deepEqual(snapshotTree(root), before, 'nothing changed');
    // the extended profile never reads the manifest: a missing one passes the refusals
    r = runSync({ argv: [target, '--profile', 'extended'], root, target, script: noManifest.script });
    assert.ok(!/requires the manifest|no core entries/.test(r.stderr), r.stderr);
    assert.ok(r.stdout.endsWith('Profile:            extended\n'), r.stdout);
    // a valid core list passes them too
    const ok = makeSource(root, 'S5', { profiles: PROFILES_OK });
    r = runSync({ argv: [target, '--profile', 'core'], root, target, script: ok.script });
    assert.ok(!/requires the manifest|no core entries/.test(r.stderr), r.stderr);
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
    assert.ok(r.stdout.endsWith('Profile:            extended\n'), r.stdout);
    writeFileSync(path.join(target, '.aai', 'system', 'AAI_PIN.md'), '- Profile: bogus\n- Profile: core\n');
    r = runSync({ argv: [target], root, target, script });
    assert.ok(r.stdout.endsWith('Profile:            extended\n'), r.stdout);
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
    assert.deepEqual(parseCoreList('core:\r\n  - a\r\n'), [], 'a CR after core: does not open it');
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
const MANAGED_TOP = new Set(['.aai', '.agents', '.claude', '.claude-plugin', '.codex', '.cursor', '.gemini', '.github', '.gitignore', 'hooks']);

// outsideManaged(dir): the snapshot rows of every path outside the managed set (the advisory directory docs/ai/reports
// is part of it).
const outsideManaged = (dir) => snapshotTree(dir).filter((row) => {
  const rel = row.split('\t')[0];
  return !MANAGED_TOP.has(rel.split('/')[0]) && !rel.startsWith('docs/ai/reports');
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
