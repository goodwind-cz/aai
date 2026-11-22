// install-pre-commit-hook.test.mjs - node:test cases of the hook-installer-on-node ride
// (docs/specs/SPEC-0308-spec-pre-commit-installer-on-node.md). Every case name starts with its TEST id; the suite
// tests/skills/test-aai-hook-installer-node.sh selects them with --test-name-pattern. The file grows run by run.
//
// Safety (D-SAFETY): directories are created and removed only through hook-installer-reference.mjs (own prefix,
// marker, re-verified before removal); no case starts a container tool or kills by pattern; every installer
// invocation goes through runInstaller, which sets GIT_CONFIG_NOSYSTEM=1 and an empty GIT_CONFIG_GLOBAL, runs
// only under the run's own scratch root and asserts that the hooks path git resolves there lies under it.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  chmodSync, existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, readlinkSync, renameSync, rmSync, statSync, symlinkSync, utimesSync, writeFileSync,
} from 'node:fs';
import net from 'node:net';
import path from 'node:path';
import { after, describe, test } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import {
  OWN_MARKER_FILE, REFERENCE_COMMIT, REFERENCE_PS1, REFERENCE_PS1_SHA256, REFERENCE_SH, REFERENCE_SH_SHA256,
  createOwnScratch, materializeHookInstallerReference, removeOwnScratch, removeOwnScratchAll, sha256File,
} from './hook-installer-reference.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..', '..');
const MODULE = path.join(ROOT, '.aai', 'scripts', 'install-pre-commit-hook.mjs');
const MODULE_URL = pathToFileURL(MODULE).href;
const TEMPLATE_DIR = path.join(ROOT, '.aai', 'templates', 'git-hooks');
// Every test file of this ride that exists; a file that a later run adds is listed here by that run.
const NEW_TEST_FILES = [
  path.join(ROOT, 'tests', 'skills', 'test-aai-hook-installer-node.sh'),
  path.join(ROOT, 'tests', 'skills', 'test-aai-hook-installer-docs.sh'),
  path.join(HERE, 'install-pre-commit-hook.test.mjs'),
  path.join(HERE, 'hook-installer-reference.mjs'),
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

// --- the installer invocation helpers (D-SAFETY) -------------------------------------------------------------

// prepareEnv(root, extra): the environment of an installer run: the caller's minus every AAI_ and GIT_ variable, plus no
// system git config, a global git config that is an empty scratch file (a global core.hooksPath would otherwise
// redirect the writes) and a per-root TMPDIR.
export function prepareEnv(root, extra = {}) {
  const env = {};
  // every GIT_ variable goes: GIT_CONFIG_COUNT/KEY_n/VALUE_n, GIT_CONFIG_PARAMETERS, GIT_DIR, GIT_COMMON_DIR, ... can each
  // redirect the hooks path or the repository; the two the run needs are set below
  for (const [k, v] of Object.entries(process.env)) if (!k.startsWith('AAI_') && !k.startsWith('GIT_')) env[k] = v;
  const gitconfig = path.join(root, 'gitconfig');
  const tmp = path.join(root, 'tmp');
  mkdirSync(tmp, { recursive: true });
  writeFileSync(gitconfig, '');
  return { ...env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: gitconfig, TMPDIR: tmp, ...extra };
}

// assertHooksUnderRoot(cwd, root, env): the cwd lies under the run's own scratch root, and where it is a
// repository the hooks path git resolves from it lies under the root too.
export function assertHooksUnderRoot(cwd, root, env) {
  assert.ok(path.isAbsolute(root) && path.basename(root).startsWith('aai-hk-'), `scratch root ${root} lacks the own prefix`);
  assert.ok(existsSync(path.join(root, OWN_MARKER_FILE)), `scratch root ${root} lacks the ownership marker`);
  assert.ok(under(cwd, root), `cwd ${cwd} lies outside the scratch root ${root}`);
  const r = spawnSync('git', ['rev-parse', '--git-path', 'hooks/pre-commit'], { cwd, env, encoding: 'utf8' });
  if (r.status !== 0) return;
  const resolved = path.resolve(cwd, r.stdout.trim());
  assert.ok(under(resolved, root), `the hooks path ${resolved} lies outside the scratch root ${root}`);
}

// runInstaller({ args, root, cwd, env, script }): the one way these tests start the installer as a process: the
// module (default), or a frozen reference script materialized under the root.
export function runInstaller({ args = [], root, cwd = root, env = {}, script = MODULE, umask = '', encoding = 'utf8' }) {
  const runEnv = prepareEnv(root, env);
  assert.equal(runEnv.GIT_CONFIG_NOSYSTEM, '1');
  assert.equal(readFileSync(runEnv.GIT_CONFIG_GLOBAL, 'utf8'), '', 'GIT_CONFIG_GLOBAL is an empty file');
  assertHooksUnderRoot(cwd, root, runEnv);
  const file = script.endsWith('.sh') ? 'bash' : script.endsWith('.ps1') ? 'pwsh' : process.execPath;
  if (file === 'pwsh') return spawnSync('pwsh', ['-NoProfile', '-NonInteractive', '-File', script, ...args], { cwd, env: runEnv, encoding });
  if (umask !== '') {
    assert.match(umask, /^[0-7]{3}$/, 'the umask is three octal digits');
    return spawnSync('sh', ['-c', `umask ${umask} && exec "$0" "$@"`, file, script, ...args], { cwd, env: runEnv, encoding });
  }
  return spawnSync(file, [script, ...args], { cwd, env: runEnv, encoding });
}

// --- TEST-3980 ---------------------------------------------------------------------------------------------

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
const INSTALLER_ENTRY = /\b(MODULE|REFERENCE_SH|REFERENCE_PS1)\b|install-pre-commit-hook\.(mjs|sh|ps1)|refs\.(sh|ps1)/;

// invocationProblems(source): the JS rule of D-SAFETY: a process call that names an installer entry point must be
// the one inside runInstaller, and runInstaller must build its environment with prepareEnv, which sets
// GIT_CONFIG_NOSYSTEM to 1 and GIT_CONFIG_GLOBAL, and assert the hooks path through assertHooksUnderRoot. A
// source with no runInstaller has no invocation to check.
export function invocationProblems(source) {
  const problems = [];
  const from = source.indexOf('export function runInstaller(');
  const bodyEnd = from < 0 ? -1 : source.indexOf('\n}\n', from);
  for (const call of spawnCalls(source)) {
    const inside = from >= 0 && call.at > from && call.at < bodyEnd;
    if (!inside && INSTALLER_ENTRY.test(call.text)) problems.push(`an installer entry point is started outside runInstaller: ${call.text.slice(0, 70)}`);
  }
  if (from >= 0) {
    const body = source.slice(from, bodyEnd);
    if (!body.includes('prepareEnv(')) problems.push('runInstaller does not build its environment with prepareEnv');
    if (!body.includes('assertHooksUnderRoot(')) problems.push('runInstaller does not assert the hooks path against the scratch root');
    const prep = source.slice(source.indexOf('export function prepareEnv('), source.indexOf('export function assertHooksUnderRoot('));
    if (!/GIT_CONFIG_NOSYSTEM: '1'/.test(prep)) problems.push('prepareEnv does not set GIT_CONFIG_NOSYSTEM to 1');
    if (!/GIT_CONFIG_GLOBAL: gitconfig/.test(prep) || !/writeFileSync\(gitconfig, ''\)/.test(prep)) problems.push('prepareEnv does not set GIT_CONFIG_GLOBAL to an empty file');
  }
  return problems;
}

// inProcessRunProblems(source): the in-process rule of D-SAFETY: an awaited call of the module's run() must sit inside
// runInProcess (which builds the environment with prepareEnv and asserts the hooks path under the scratch root) or
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
    if (!body.includes('assertHooksUnderRoot(')) problems.push('runInProcess does not assert the hooks path against the scratch root');
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
  const prep = source.slice(source.indexOf('export function prepareEnv('), source.indexOf('export function assertHooksUnderRoot('));
  if (!/startsWith\('GIT_'\)/.test(prep)) problems.push('prepareEnv does not drop every GIT_ variable');
  return problems;
}

// shellInvocationProblems(source): the same rule for a bash suite. A line that runs an installer entry point must
// sit inside the run_installer function, which sets GIT_CONFIG_NOSYSTEM=1 and an empty GIT_CONFIG_GLOBAL and
// asserts the hooks path under the scratch root: a line outside it is flagged when it runs the entry point
// through bash, sh, dash, node or pwsh, or names an installer launcher or module with an installer argument.
export function shellInvocationProblems(source) {
  const problems = [];
  const lines = source.split('\n');
  const entry = /\b(bash|sh|dash|node|pwsh)\s+("?\$\{?(MJS|SH_LAUNCHER|PS1_LAUNCHER|REFERENCE_SH|REFERENCE_PS1)\b|\S*install-pre-commit-hook\.(sh|mjs|ps1))/;
  const named = /install-pre-commit-hook\.(sh|ps1|mjs)\b.*(--uninstall\b|--print\b|--force\b|--hooks\b|-Uninstall\b|-Hooks\b)/;
  const open = lines.findIndex((l) => /^run_installer\(\) \{/.test(l));
  const close = open < 0 ? -1 : lines.findIndex((l, i) => i > open && l === '}');
  lines.forEach((line, i) => {
    if (/^\s*#/.test(line) || !(entry.test(line) || named.test(line))) return;
    if (!(open >= 0 && i > open && i < close)) problems.push(`${i + 1}: an installer entry point is run outside run_installer: ${line.trim().slice(0, 70)}`);
  });
  if (open < 0) {
    problems.push('the suite has no run_installer function');
  } else {
    const body = lines.slice(open, close + 1).join('\n');
    if (!body.includes('GIT_CONFIG_NOSYSTEM=1')) problems.push('run_installer does not set GIT_CONFIG_NOSYSTEM=1');
    if (!/GIT_CONFIG_GLOBAL="\$/.test(body)) problems.push('run_installer does not set GIT_CONFIG_GLOBAL to a scratch file');
    if (!/case "\$resolved" in "\$work"\/\*\)/.test(body)) problems.push('run_installer does not assert the hooks path under the scratch root');
  }
  return problems;
}

describe('TEST-3980 scratch safety and the frozen references', () => {
  test('TEST-3980 removeOwnScratch refuses each unsafe path', () => {
    const base = scratch('refuse-');
    const unmarked = path.join(base, 'aai-hk-unmarked');
    mkdirSync(unmarked);
    const foreign = path.join(base, 'foreign-name');
    mkdirSync(foreign);
    writeFileSync(path.join(foreign, OWN_MARKER_FILE), `${process.pid}\n`);
    const nonNumeric = path.join(base, 'aai-hk-badmarker');
    mkdirSync(nonNumeric);
    writeFileSync(path.join(nonNumeric, OWN_MARKER_FILE), 'not-a-pid\n');
    assert.throws(() => removeOwnScratch(''), /empty path/);
    assert.throws(() => removeOwnScratch(undefined), /empty path/);
    assert.throws(() => removeOwnScratch('aai-hk-relative'), /relative path/);
    assert.throws(() => removeOwnScratch(foreign), /own prefix/);
    assert.throws(() => removeOwnScratch(path.join(base, 'aai-hk-missing')), /does not exist/);
    assert.throws(() => removeOwnScratch(unmarked), /marker/);
    assert.throws(() => removeOwnScratch(nonNumeric), /marker/);
    assert.throws(() => removeOwnScratchAll([]), /empty list/);
    for (const kept of [foreign, unmarked, nonNumeric]) assert.ok(existsSync(kept), `${kept} must survive`);
  });

  test('TEST-3980 removeOwnScratch refuses a path outside the temp directory and a symlink', () => {
    const base = scratch('outside-');
    const marked = path.join(base, 'aai-hk-marked');
    mkdirSync(marked);
    writeFileSync(path.join(marked, OWN_MARKER_FILE), `${process.pid}\n`);
    // a child whose temp directory is a sub-directory: the marked directory then lies outside it
    const childTmp = path.join(base, 'childtmp');
    mkdirSync(childTmp);
    const helperUrl = pathToFileURL(path.join(HERE, 'hook-installer-reference.mjs')).href;
    const code = `import(${JSON.stringify(helperUrl)}).then((m) => { try { m.removeOwnScratch(${JSON.stringify(marked)}); console.log('REMOVED'); } catch (e) { console.log(e.message); } });`;
    const r = spawnSync(process.execPath, ['-e', code], {
      encoding: 'utf8', env: { ...process.env, TMPDIR: childTmp, TMP: childTmp, TEMP: childTmp },
    });
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /outside the temp directory/);
    assert.ok(existsSync(marked), 'the outside directory must survive');
    // a symlink with the prefix is refused and its target survives
    const link = path.join(base, 'aai-hk-link');
    symlinkSync(marked, link);
    assert.throws(() => removeOwnScratch(link), /not a real directory/);
    assert.ok(existsSync(marked));
  });

  test('TEST-3980 removeOwnScratch removes a marked own directory and createOwnScratch marks it', () => {
    const dir = createOwnScratch('own-');
    assert.ok(path.basename(dir).startsWith('aai-hk-own-'));
    assert.match(readFileSync(path.join(dir, OWN_MARKER_FILE), 'utf8'), /^[0-9]+\n$/);
    writeFileSync(path.join(dir, 'file'), 'x');
    removeOwnScratch(dir);
    assert.ok(!existsSync(dir));
  });

  test('TEST-3980 both reference copies hash to their pins and equal the pinned commit', () => {
    assert.match(REFERENCE_SH_SHA256, /^[0-9a-f]{64}$/);
    assert.match(REFERENCE_PS1_SHA256, /^[0-9a-f]{64}$/);
    assert.ok(REFERENCE_SH_SHA256.startsWith('140b17eb') && REFERENCE_PS1_SHA256.startsWith('b8c8697a'), 'the D-REF pins');
    assert.equal(REFERENCE_COMMIT, 'bf0148d6');
    for (const [rel, want, name] of [[REFERENCE_SH, REFERENCE_SH_SHA256, 'install-pre-commit-hook.sh'], [REFERENCE_PS1, REFERENCE_PS1_SHA256, 'install-pre-commit-hook.ps1']]) {
      const file = path.join(ROOT, rel);
      assert.equal(sha256File(file), want, `${rel} hashes to its pin`);
      const has = spawnSync('git', ['cat-file', '-e', `${REFERENCE_COMMIT}^{commit}`], { cwd: ROOT, encoding: 'utf8' });
      if (has.status !== 0) continue; // shallow checkout: the hash pin alone holds
      const shown = spawnSync('git', ['show', `${REFERENCE_COMMIT}:.aai/scripts/${name}`], { cwd: ROOT, maxBuffer: 16 * 1024 * 1024 });
      assert.equal(shown.status, 0);
      assert.ok(Buffer.compare(shown.stdout, readFileSync(file)) === 0, `${rel} equals ${REFERENCE_COMMIT}:.aai/scripts/${name}`);
    }
    assert.equal(statSync(path.join(ROOT, REFERENCE_SH)).mode & 0o111, 0o111, 'the bash reference stays executable');
  });

  test('TEST-3980 materializeHookInstallerReference verifies both hashes and writes the twins and the templates', () => {
    const into = path.join(scratch('mat-'), 'tree');
    const dests = materializeHookInstallerReference(ROOT, into);
    assert.equal(dests.sh, path.join(into, '.aai', 'scripts', 'install-pre-commit-hook.sh'));
    assert.equal(dests.ps1, path.join(into, '.aai', 'scripts', 'install-pre-commit-hook.ps1'));
    assert.equal(sha256File(dests.sh), REFERENCE_SH_SHA256);
    assert.equal(sha256File(dests.ps1), REFERENCE_PS1_SHA256);
    assert.equal(statSync(dests.sh).mode & 0o777, 0o755);
    assert.equal(statSync(dests.ps1).mode & 0o777, 0o644);
    const templates = ['pre-commit-guard-checks.sh', 'pre-commit-index.sh', 'pre-push.sh', 'reference-transaction.sh'];
    assert.deepEqual(readdirSync(path.join(into, '.aai', 'templates', 'git-hooks')).sort(), templates, 'the four current templates');
    for (const t of templates) {
      assert.ok(Buffer.compare(readFileSync(path.join(into, '.aai', 'templates', 'git-hooks', t)), readFileSync(path.join(TEMPLATE_DIR, t))) === 0, `${t} copied byte for byte`);
    }
    assert.deepEqual(readdirSync(path.join(into, '.aai')).sort(), ['scripts', 'templates'], 'nothing else is copied');
    assert.deepEqual(readdirSync(path.join(into, '.aai', 'scripts')).sort(), ['install-pre-commit-hook.ps1', 'install-pre-commit-hook.sh']);
    // an edited copy of either twin fails by naming the file
    for (const rel of [REFERENCE_SH, REFERENCE_PS1]) {
      const fakeFrom = path.join(scratch('mat-bad-'), 'from');
      for (const r of [REFERENCE_SH, REFERENCE_PS1]) {
        mkdirSync(path.dirname(path.join(fakeFrom, r)), { recursive: true });
        writeFileSync(path.join(fakeFrom, r), readFileSync(path.join(ROOT, r)));
      }
      writeFileSync(path.join(fakeFrom, rel), 'edited\n');
      assert.throws(() => materializeHookInstallerReference(fakeFrom, path.join(scratch('mat-bad2-'), 'x')), (e) => e.message.includes(path.join(fakeFrom, rel)) && /hashes to/.test(e.message));
    }
  });

  test('TEST-3980 the new test files hold no call of a container tool or a kill by pattern', () => {
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

  test('TEST-3980 the scanned list holds every hook-installer-on-node test file that exists', () => {
    // Files of this ride's naming under tests/skills and its lib; the pre-existing installer files are not new.
    const exempt = new Set(['install-pre-commit-hook.Tests.ps1', 'vendor-hook-installer.sh']);
    const found = [];
    for (const dir of [path.join(ROOT, 'tests', 'skills'), HERE]) {
      for (const name of readdirSync(dir)) {
        if (/(hook-installer-(node|reference|docs)|install-pre-commit-hook\.test)/.test(name) && !exempt.has(name) && statSync(path.join(dir, name)).isFile()) found.push(path.join(dir, name));
      }
    }
    for (const f of found) assert.ok(NEW_TEST_FILES.includes(f), `${f} is a test file of this ride and must be added to NEW_TEST_FILES`);
    for (const f of NEW_TEST_FILES) assert.ok(found.includes(f), `${f} is listed but not found by name`);
  });

  test('TEST-3980 every installer invocation sets the git environment and asserts the hooks path under the scratch root', () => {
    for (const file of NEW_TEST_FILES) {
      const src = readFileSync(file, 'utf8');
      let problems = file.endsWith('.sh') ? shellInvocationProblems(src) : invocationProblems(src);
      // the docs suite starts no installer at all: it needs no run_installer, and any entry point it ran would still be flagged
      if (file.endsWith('test-aai-hook-installer-docs.sh')) problems = problems.filter((p) => p !== 'the suite has no run_installer function');
      assert.deepEqual(problems, [], path.basename(file));
    }
    const mine = readFileSync(path.join(HERE, 'install-pre-commit-hook.test.mjs'), 'utf8');
    assert.ok(mine.includes('export function runInstaller('), 'the invocation helper exists');
    // positive controls for both scanners
    assert.equal(invocationProblems(`${SPAWN}(process.execPath, [MODULE, '-h'], {});\n`).length, 1);
    assert.equal(invocationProblems(`${SPAWN}('bash', [path.join(root, 'install-pre-commit-hook.sh')], {});\n`).length, 1);
    assert.equal(invocationProblems(`${SPAWN}('git', ['status'], {});\n`).length, 0);
    assert.equal(invocationProblems(mine.replace("GIT_CONFIG_NOSYSTEM: '1'", "GIT_CONFIG_NOSYSTEM: '0'")).length, 1);
    assert.equal(invocationProblems(mine.replace('GIT_CONFIG_GLOBAL: gitconfig', 'GIT_X: gitconfig')).length, 1);
    assert.equal(invocationProblems(mine.replace("writeFileSync(gitconfig, '');", '')).length, 1);
    assert.equal(invocationProblems(mine.replace('  assertHooksUnderRoot(cwd, root, runEnv);\n  const file', '  const file')).length, 1);
    assert.equal(shellInvocationProblems('bash "$SH_LAUNCHER" --uninstall\n').length, 2);
    assert.equal(shellInvocationProblems('out="$(node "$MJS" -h)"\n').length, 2);
    const okBody = 'run_installer() {\n  case "$resolved" in "$work"/*) ;; *) exit 1 ;; esac\n  GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$g" node "$MJS" "$@"\n}\n';
    assert.equal(shellInvocationProblems(`# bash "$MJS" in a comment\n[[ -f "$MJS" ]]\nMJS="$PROJECT_ROOT/x"\n${okBody}`).length, 0);
    assert.equal(shellInvocationProblems('run_installer() {\n  node "$MJS" "$@"\n}\n').length, 3);
    assert.equal(shellInvocationProblems('# no run_installer at all\n').length, 1);
    // the committed bash suite: no problem as committed, and a problem for each property removed from run_installer
    const suite = readFileSync(NEW_TEST_FILES.find((f) => f.endsWith('test-aai-hook-installer-node.sh')), 'utf8');
    assert.ok(/^run_installer\(\) \{/m.test(suite), 'the suite has run_installer');
    assert.deepEqual(shellInvocationProblems(suite), []);
    assert.ok(shellInvocationProblems(suite.replace('local -x GIT_CONFIG_NOSYSTEM=1', 'local -x')).length >= 1, 'GIT_CONFIG_NOSYSTEM removed');
    assert.ok(shellInvocationProblems(suite.replace(' GIT_CONFIG_GLOBAL="$work/gitconfig"', '')).length >= 1, 'GIT_CONFIG_GLOBAL removed');
    assert.ok(shellInvocationProblems(suite.replace(/^ {2}case "\$resolved" in "\$work"\/\*\) ;;.*$/m, '')).length >= 1, 'the scratch-root assertion removed');
    assert.ok(shellInvocationProblems(`${suite}\nbash .aai/scripts/install-pre-commit-hook.sh --uninstall\n`).length >= 1, 'a run outside run_installer');
  });

  test('TEST-3980 an awaited in-process run( call goes through runInProcess or carries the recording seam, and prepareEnv drops every GIT_ variable', () => {
    const mine = readFileSync(path.join(HERE, 'install-pre-commit-hook.test.mjs'), 'utf8');
    assert.deepEqual(inProcessRunProblems(mine), []);
    // positive controls
    assert.equal(inProcessRunProblems(mine.replace('  assertHooksUnderRoot(cwd, root, env);\n  const code', '  const code')).length, 1);
    assert.equal(inProcessRunProblems(mine.replace("!k.startsWith('GIT_')", "k !== 'GIT_DIR'")).length, 1);
    assert.equal(inProcessRunProblems(`${mine}\nconst c = ${AWAIT_RUN}[], { cwd: repo, env: prepareEnv(root) });\n`).length, 1);
    assert.equal(inProcessRunProblems(`${mine}\nconst c = ${AWAIT_RUN}[], { spawn, cwd: repo });\n`).length, 0);
  });

  test('TEST-3980 prepareEnv builds the isolated git environment and runInstaller refuses a cwd outside the root', () => {
    const root = scratch('env-');
    const saved = process.env.AAI_ROLE;
    process.env.AAI_ROLE = 'x';
    let env;
    try {
      env = prepareEnv(root, { EXTRA: '1' });
    } finally {
      if (saved === undefined) delete process.env.AAI_ROLE; else process.env.AAI_ROLE = saved;
    }
    assert.ok(!('AAI_ROLE' in env));
    assert.equal(env.GIT_CONFIG_NOSYSTEM, '1');
    assert.equal(env.EXTRA, '1');
    assert.equal(readFileSync(env.GIT_CONFIG_GLOBAL, 'utf8'), '');
    assert.ok(under(env.GIT_CONFIG_GLOBAL, root) && under(env.TMPDIR, root));
    assert.throws(() => runInstaller({ args: ['-h'], root, cwd: ROOT }), /outside the scratch root/);
    // a scratch repository: the hooks path resolves under the root; a core.hooksPath pointing out of it is caught
    const repo = path.join(root, 'repo');
    mkdirSync(repo);
    assert.equal(spawnSync('git', ['init', '-q'], { cwd: repo, env, encoding: 'utf8' }).status, 0);
    assertHooksUnderRoot(repo, root, env);
    assert.equal(spawnSync('git', ['config', 'core.hooksPath', path.join(ROOT, '.git', 'hooks')], { cwd: repo, env, encoding: 'utf8' }).status, 0);
    assert.throws(() => assertHooksUnderRoot(repo, root, env), /outside the scratch root/);
    assert.throws(() => assertHooksUnderRoot(root, ROOT, env), /own prefix/);
  });
});

// --- TEST-3981: ---------------------------------------------------------------------------------------------

const EXPORTS = [
  'parseArgs', 'resolveMode', 'resolveBase', 'loadTemplates', 'composePreCommit', 'hasMarkerLine', 'resolveSlots',
  'classifySlot', 'planUpgrade', 'writeSlot', 'run', 'main',
];

// The anchor lines of D-MODULE: each occurs exactly once in the module.
const ANCHORS = [
  "import { readRefGuardPolicy, writeRefGuardPolicy } from './lib/guard-config.mjs';",
  'const EXIT_FAIL = 1;',
  'const EXIT_USAGE = 2;',
  "const GUARD_BEGIN = '# AAI:GUARD-CHECKS BEGIN';",
  "const GUARD_END = '# AAI:GUARD-CHECKS END';",
  "const HOOK_TOKENS = ['index', 'ref-guard', 'close-gate'];",
  "const PRINT_KINDS = ['index', 'ref-guard', 'guard-checks', 'pre-push'];",
  "const MODE_FLAGS = ['--uninstall', '--print', '--decline-ref-guard', '--arm-ref-guard'];",
  "const PS_NAMES = { '-force': '--force', '-uninstall': '--uninstall', '-hooks': '--hooks', '-declinerefguard': '--decline-ref-guard', '-armrefguard': '--arm-ref-guard' };",
  "const GIT_PATH_ARGS = (name) => ['rev-parse', '--git-path', `hooks/${name}`];",
  "const SKIP_DECLINED = (mode, policy) => !mode.force && policy === 'declined';",
  "const ensureFinalLf = (b) => (b.length && b[b.length - 1] !== 10 ? Buffer.concat([b, Buffer.from('\\n')]) : b);",
  'const runChild = (file, args, opts) => spawnSync(file, args, opts);',
  'const writeFd = (fd) => (s) => { fs.writeSync(fd, s); };',
  '  if (refusals.length) return refuseWholeRun(refusals);',
  '    if (!landed(slot, bytes)) return landingFailure(slot);',
];
// The D4 arm rationale comment (D-WRITE) is identified by this phrase and occurs once.
const ARM_RATIONALE = 'D4 makes CAT-17';

const NETWORK_MODULES = ['http', 'https', 'net', 'tls', 'dgram'];

// templateLines(): every trimmed line of 40 or more characters of the four hook templates, CRs removed.
function templateLines() {
  const lines = new Set();
  for (const name of readdirSync(TEMPLATE_DIR)) {
    for (const l of readFileSync(path.join(TEMPLATE_DIR, name), 'utf8').replace(/\r/g, '').split('\n')) if (l.trim().length >= 40) lines.add(l.trim());
  }
  return [...lines];
}

// moduleShapeProblems(source): the static D-MODULE rules, as a list of problems (empty when clean).
export function moduleShapeProblems(source, tplLines = templateLines()) {
  const problems = [];
  const specs = [];
  for (const m of source.matchAll(/^\s*import\s[^;]*?\sfrom\s+['"]([^'"]+)['"]/gm)) specs.push(m[1]);
  for (const m of source.matchAll(/^\s*import\s+['"]([^'"]+)['"]/gm)) specs.push(m[1]);
  for (const m of source.matchAll(/\b(?:import|require)\(\s*['"]([^'"]+)['"]/g)) specs.push(m[1]);
  for (const spec of specs) {
    if (!spec.startsWith('node:') && spec !== './lib/guard-config.mjs') problems.push(`import of ${spec} is not a node: specifier or the guard-config library`);
    if (NETWORK_MODULES.includes(spec.replace(/^node:/, ''))) problems.push(`import of the network module ${spec}`);
  }
  if (/[^\x00-\x7f]/.test(source)) problems.push('non-ASCII character');
  for (const anchor of ANCHORS) {
    const n = source.split(anchor).length - 1;
    if (n !== 1) problems.push(`anchor appears ${n} times: ${anchor}`);
  }
  const rationale = source.split(ARM_RATIONALE).length - 1;
  if (rationale !== 1) problems.push(`the arm rationale comment appears ${rationale} times, want 1`);
  const calls = spawnCalls(source);
  if (calls.length !== 1) problems.push(`spawnSync is called ${calls.length} times, want 1`);
  else if (!source.split('\n').some((l) => l === 'const runChild = (file, args, opts) => spawnSync(file, args, opts);')) problems.push('the one spawnSync call is not inside runChild');
  if (/process\.(stdout|stderr)/.test(source)) problems.push('references process.stdout or process.stderr');
  if (/process\.stdin|readFileSync\(\s*0\b/.test(source)) problems.push('reads standard input');
  if (/\b(exec|execSync|execFile|execFileSync|spawn|fork)\s*\(/.test(source)) problems.push('a process is started other than through spawnSync');
  if (/shell\s*:\s*true/.test(source)) problems.push('a spawn asks for a shell');
  for (const line of tplLines) if (source.includes(line)) problems.push(`holds a hook template line: ${line.slice(0, 60)}`);
  return problems;
}

describe('TEST-3981 module shape', () => {
  test('TEST-3981 importing the module creates nothing and prints nothing', () => {
    const cwd = scratch('import-');
    const before = listTree(cwd);
    const r = spawnSync(process.execPath, ['--input-type=module', '-e', `await import(${JSON.stringify(MODULE_URL)});`], {
      cwd, encoding: 'utf8',
    });
    assert.equal(r.status, 0, r.stderr);
    assert.equal(r.stdout, '');
    assert.equal(r.stderr, '');
    assert.deepEqual(listTree(cwd), before);
  });

  test('TEST-3981 the module exports the D-MODULE names', async () => {
    const mod = await import(MODULE_URL);
    for (const name of EXPORTS) assert.equal(typeof mod[name], 'function', `export ${name}`);
  });

  test('TEST-3981 the module holds the static shape of D-MODULE', () => {
    const source = readFileSync(MODULE, 'utf8');
    assert.deepEqual(moduleShapeProblems(source), []);
    assert.ok(source.startsWith('#!/usr/bin/env node\n'));
    assert.ok(statSync(MODULE).mode & 0o111, 'the module is executable');
  });

  test('TEST-3981 no hook template line of 40 or more characters occurs in the module', () => {
    const lines = templateLines();
    assert.ok(lines.length > 20, `the templates hold long lines (${lines.length})`);
    const source = readFileSync(MODULE, 'utf8');
    for (const line of lines) assert.ok(!source.includes(line), `template line in the module: ${line.slice(0, 60)}`);
  });

  test('TEST-3981 the shape check reports each violation it is meant to catch', () => {
    const good = readFileSync(MODULE, 'utf8');
    const bad = (mutated, re) => {
      const problems = moduleShapeProblems(mutated);
      assert.ok(problems.some((p) => re.test(p)), `${re} not reported: ${problems.join(' | ')}`);
    };
    bad(good.replace('{ fs.writeSync(fd, s); }', '{ process.stdout.write(s); }'), /process\.stdout|anchor appears 0/);
    bad(good.replace('{ fs.writeSync(fd, s); }', '{ process.stderr.write(s); }'), /process\.stderr|anchor appears 0/);
    bad(`${good}\nspawnSync('git', []);\n`, /spawnSync is called 2 times/);
    bad(`import http from 'node:http';\n${good}`, /network module/);
    bad(`import x from 'some-package';\n${good}`, /is not a node: specifier/);
    bad(`${good}\nconst x = 'é';\n`, /non-ASCII/);
    bad(`${good}\nconst EXIT_FAIL = 1;\n`, /anchor appears 2 times: const EXIT_FAIL/);
    bad(good.replace('const EXIT_USAGE = 2;', 'const EXIT_USAGE = 0;'), /anchor appears 0 times: const EXIT_USAGE/);
    bad(`${good}\n// ${ARM_RATIONALE} again\n`, /arm rationale comment appears 2 times/);
    bad(good.split(ARM_RATIONALE).join('D4 trusts'), /arm rationale comment appears 0 times/);
    bad(`${good}\nconst t = '${templateLines()[0].replace(/'/g, '')}';\n`, /hook template line/);
    bad(`${good}\nexecSync('git');\n`, /started other than through spawnSync/);
    bad(`${good}\nprocess.stdin.read();\n`, /standard input/);
    bad(`${good}\nconst a = { shell: true };\n`, /asks for a shell/);
    bad(good.replace('const runChild = (file, args, opts) => spawnSync(file, args, opts);', 'const runChild = (file, args, opts) => spawnSync(file, args, { ...opts });'), /anchor appears 0 times: const runChild|not inside runChild/);
  });
});

// --- TEST-3982: ---------------------------------------------------------------------------------------------

// runModule(argv, extra): run() with captured output and a recording child seam; nothing real is started.
async function runModule(argv, extra = {}) {
  const { run } = await import(MODULE_URL);
  const out = [];
  const err = [];
  const calls = [];
  const spawn = (file, args) => { calls.push([file, args]); return { status: 1, stdout: '', stderr: '' }; };
  const code = await run(argv, { out: (s) => out.push(s), err: (s) => err.push(s), spawn, ...extra });
  return { code, stdout: out.join(''), stderr: err.join(''), calls };
}

// expectedHelp(): lines 4 to 78 of the frozen bash reference after s/^# \{0,1\}//, then the two DR-1 lines.
function expectedHelp() {
  const lines = readFileSync(path.join(ROOT, REFERENCE_SH), 'utf8').split('\n').slice(3, 78).map((l) => l.replace(/^# {0,1}/, ''));
  assert.equal(lines.length, 75);
  lines.push('  powershell -NoProfile -File .aai/scripts/install-pre-commit-hook.ps1 [-Force] [-Uninstall] [-Hooks <csv>] [-DeclineRefGuard] [-ArmRefGuard]   # the long flags work too');
  lines.push('Requires Node.js 22 or later; both launchers run .aai/scripts/install-pre-commit-hook.mjs.');
  return `${lines.join('\n')}\n`;
}

const HOOKS_SET = '(closed set: index, ref-guard, close-gate, all)';
const ALL_HOOKS = ['index', 'ref-guard', 'close-gate'];

describe('TEST-3982 arguments and the one resolved mode', () => {
  test('TEST-3982 every accepted form resolves to one mode in any order and case', async () => {
    const { parseArgs, resolveMode } = await import(MODULE_URL);
    const mode = (argv) => resolveMode(parseArgs(argv));
    assert.deepEqual(mode([]), { mode: 'install', force: false, selected: ALL_HOOKS, printKind: '' });
    assert.deepEqual(mode(['--force']), { mode: 'install', force: true, selected: ALL_HOOKS, printKind: '' });
    assert.deepEqual(mode(['--uninstall']), { mode: 'uninstall', force: false, selected: ALL_HOOKS, printKind: '' });
    assert.deepEqual(mode(['--decline-ref-guard']), { mode: 'decline', force: false, selected: ALL_HOOKS, printKind: '' });
    assert.deepEqual(mode(['--arm-ref-guard', '--force']), { mode: 'arm', force: true, selected: ALL_HOOKS, printKind: '' });
    assert.deepEqual(mode(['--print']), { mode: 'print', force: false, selected: ALL_HOOKS, printKind: 'index' });
    for (const kind of ['index', 'ref-guard', 'guard-checks', 'pre-push']) assert.equal(mode(['--print', kind]).printKind, kind);
    // the five PowerShell names, matched in any case, in any position
    const forms = [
      [['-Force', '-Hooks', 'index'], { mode: 'install', force: true, selected: ['index'] }],
      [['-hooks', 'ref-guard', '-FORCE'], { mode: 'install', force: true, selected: ['ref-guard'] }],
      [['-UNINSTALL', '-force'], { error: 'ERROR: --force has no effect with --uninstall.' }],
      [['-DeclineRefGuard'], { mode: 'decline', force: false }],
      [['-declinerefguard'], { mode: 'decline', force: false }],
      [['-ArmRefGuard', '-Force'], { mode: 'arm', force: true }],
      [['-aRmReFgUaRd'], { mode: 'arm', force: false }],
      [['-Uninstall', '-Hooks', 'close-gate,index'], { mode: 'uninstall', force: false, selected: ['index', 'close-gate'] }],
      [['--hooks', 'close-gate', '--force', '--uninstall', '--uninstall'], { error: 'ERROR: --force has no effect with --uninstall.' }],
    ];
    for (const [argv, want] of forms) {
      const got = mode(argv);
      for (const [k, v] of Object.entries(want)) assert.deepEqual(got[k], v, `${argv.join(' ')}: ${k}`);
    }
    // a repeated flag is one flag
    assert.equal(mode(['--uninstall', '--uninstall', '-Uninstall']).mode, 'uninstall');
    assert.equal(mode(['--force', '--force']).force, true);
    // every selection spelling keeps the canonical slot order
    assert.deepEqual(mode(['--hooks', 'close-gate,ref-guard,index']).selected, ALL_HOOKS);
    assert.deepEqual(mode(['--hooks', 'all']).selected, ALL_HOOKS);
    assert.deepEqual(mode(['--hooks', 'index,all']).selected, ALL_HOOKS);
  });

  test('TEST-3982 the last --hooks and the last --print kind win', async () => {
    const { parseArgs, resolveMode } = await import(MODULE_URL);
    const mode = (argv) => resolveMode(parseArgs(argv));
    assert.deepEqual(mode(['--hooks', 'index', '--hooks', 'ref-guard']).selected, ['ref-guard']);
    assert.deepEqual(mode(['-Hooks', 'index', '--hooks', 'close-gate', '-HOOKS', 'ref-guard']).selected, ['ref-guard']);
    assert.equal(mode(['--print', 'index', '--print', 'pre-push']).printKind, 'pre-push');
    assert.equal(mode(['--print', 'pre-push', '--print']).printKind, 'pre-push');
    // a word after --print that is not a kind is its own argument
    assert.equal(parseArgs(['--print', 'bogus']).outcome, 'unknown');
    assert.equal(parseArgs(['--print', 'bogus']).arg, 'bogus');
    assert.deepEqual(parseArgs(['--print', '--uninstall']).flags, ['--uninstall', '--print'], 'flags keep the canonical order');
  });

  test('TEST-3982 help is the reference comment block plus the two DR-1 lines, on stdout, exit 0, at its position', async () => {
    const want = expectedHelp();
    for (const form of ['-h', '--help']) {
      const r = await runModule([form]);
      assert.equal(r.code, 0);
      assert.equal(r.stdout, want);
      assert.equal(r.stderr, '');
      assert.deepEqual(r.calls, []);
    }
    for (const token of ['token close-gate', 'closed set', '--print guard-checks', '--print pre-push', 'ref_guard: declined', 'AAI:CLOSE-GATE']) {
      assert.ok(want.includes(token), `the help keeps the hygiene token ${token}`);
    }
    assert.ok(want.includes('Requires Node.js 22 or later'));
    // help stops the parse: earlier valid flags are ignored, a later unknown word is never read, an earlier one wins
    assert.equal((await runModule(['--force', '--uninstall', '-h'])).stdout, want);
    assert.equal((await runModule(['--hooks', 'bogus', '--help'])).stdout, want);
    const later = await runModule(['-h', 'bogus']);
    assert.equal(later.code, 0);
    assert.equal(later.stderr, '');
    const earlier = await runModule(['bogus', '-h']);
    assert.equal(earlier.code, 2);
    assert.equal(earlier.stdout, '');
    // -H and --HELP are not help
    assert.equal((await runModule(['-H'])).code, 2);
    assert.equal((await runModule(['--HELP'])).code, 2);
  });

  test('TEST-3982 an unknown argument, an abbreviation, a common parameter and an equals form exit 2 with one line', async () => {
    for (const arg of ['bogus', '-F', '-Verbose', '--hooks=index', '--force=1', '-Hook', '-Dec', '-Debug', '-ErrorAction', '--FORCE', '--Uninstall', '--Hooks', '-', '--', '-force=true', '-hooks=index', '--decline', '']) {
      const r = await runModule([arg]);
      assert.equal(r.code, 2, `exit for ${JSON.stringify(arg)}`);
      assert.equal(r.stdout, '');
      assert.equal(r.stderr, `ERROR: unexpected argument: ${arg}\n`);
      assert.deepEqual(r.calls, [], `no child for ${JSON.stringify(arg)}`);
    }
    // the first unknown word names the error, at its position
    const r = await runModule(['--force', '-Verbose', 'later']);
    assert.equal(r.stderr, 'ERROR: unexpected argument: -Verbose\n');
  });

  test('TEST-3982 --hooks without a value exits 2 with the bash line', async () => {
    for (const argv of [['--hooks'], ['-Hooks'], ['-hooks'], ['--force', '--hooks'], ['--uninstall', '-HOOKS']]) {
      const r = await runModule(argv);
      assert.equal(r.code, 2, argv.join(' '));
      assert.equal(r.stdout, '');
      assert.equal(r.stderr, `ERROR: --hooks requires a value ${HOOKS_SET}\n`);
      assert.deepEqual(r.calls, []);
    }
    // a value that looks like a flag is still the value
    assert.equal((await runModule(['--hooks', '--force'])).stderr, `ERROR: unknown --hooks value: '--force' ${HOOKS_SET}\n`);
  });

  test('TEST-3982 two different mode flags are contradictory, in every pair and order', async () => {
    const names = { '--uninstall': ['--uninstall', '-Uninstall'], '--print': ['--print'], '--decline-ref-guard': ['--decline-ref-guard', '-DeclineRefGuard'], '--arm-ref-guard': ['--arm-ref-guard', '-ArmRefGuard'] };
    const order = Object.keys(names);
    for (let i = 0; i < order.length; i += 1) {
      for (let j = i + 1; j < order.length; j += 1) {
        for (const first of names[order[i]]) {
          for (const second of names[order[j]]) {
            for (const argv of [[first, second], [second, first]]) {
              const r = await runModule(argv);
              assert.equal(r.code, 2, argv.join(' '));
              assert.equal(r.stdout, '');
              assert.equal(r.stderr, `ERROR: ${order[i]} and ${order[j]} are contradictory.\n`, argv.join(' '));
              assert.deepEqual(r.calls, []);
            }
          }
        }
      }
    }
    // for decline plus arm this is the bash line byte for byte
    assert.equal((await runModule(['--arm-ref-guard', '--decline-ref-guard'])).stderr, 'ERROR: --decline-ref-guard and --arm-ref-guard are contradictory.\n');
    // the contradiction is reported before a bad --hooks value
    assert.equal((await runModule(['--uninstall', '--print', '--hooks', 'bogus'])).stderr, 'ERROR: --uninstall and --print are contradictory.\n');
  });

  test('TEST-3982 a modifier that does nothing is a usage error', async () => {
    const forceCases = [['--print', '--print'], ['--uninstall', '--uninstall'], ['--decline-ref-guard', '--decline-ref-guard']];
    for (const [flag, name] of forceCases) {
      for (const argv of [['--force', flag], [flag, '--force'], ['-Force', flag]]) {
        const r = await runModule(argv);
        assert.equal(r.code, 2, argv.join(' '));
        assert.equal(r.stdout, '');
        assert.equal(r.stderr, `ERROR: --force has no effect with ${name}.\n`, argv.join(' '));
        assert.deepEqual(r.calls, []);
      }
    }
    assert.equal((await runModule(['--force', '--print', 'pre-push'])).stderr, 'ERROR: --force has no effect with --print.\n');
    assert.equal((await runModule(['-Uninstall', '-Force'])).stderr, 'ERROR: --force has no effect with --uninstall.\n');
    // --hooks with --print, --decline-ref-guard and --arm-ref-guard
    for (const argv of [['--print', '--hooks', 'index'], ['--hooks', 'index', '--print', 'ref-guard']]) {
      const r = await runModule(argv);
      assert.equal(r.code, 2);
      assert.equal(r.stderr, 'ERROR: --hooks has no effect with --print (name the body instead: --print index, ref-guard, guard-checks or pre-push).\n');
      assert.deepEqual(r.calls, []);
    }
    for (const flag of ['--decline-ref-guard', '--arm-ref-guard', '-DeclineRefGuard', '-ArmRefGuard']) {
      for (const argv of [[flag, '--hooks', 'index'], ['-Hooks', 'ref-guard', flag]]) {
        const r = await runModule(argv);
        assert.equal(r.code, 2, argv.join(' '));
        assert.equal(r.stderr, 'ERROR: --hooks is contradictory with --decline-ref-guard/--arm-ref-guard (these act on the reference-transaction hook alone).\n');
        assert.deepEqual(r.calls, []);
      }
    }
    // the rule order: --hooks with print comes before --force with print, and both before the --hooks value
    assert.match((await runModule(['--print', '--hooks', 'bogus', '--force'])).stderr, /^ERROR: --hooks has no effect with --print/);
    assert.equal((await runModule(['--uninstall', '--force', '--hooks', 'bogus'])).stderr, 'ERROR: --force has no effect with --uninstall.\n');
    // modifiers that do mean something are accepted by the resolver
    const { parseArgs, resolveMode } = await import(MODULE_URL);
    for (const argv of [['--arm-ref-guard', '--force'], ['--uninstall', '--hooks', 'index'], ['--force', '--hooks', 'ref-guard']]) {
      assert.equal(resolveMode(parseArgs(argv)).error, undefined, argv.join(' '));
    }
  });

  test('TEST-3982 the --hooks value is split, trimmed and matched against the closed set', async () => {
    const refused = [['index,', ''], [',index', ''], ['index,,ref-guard', ''], ['', ''], [' ', ''], ['Index', 'Index'], ['INDEX', 'INDEX'], ['in dex', 'in dex'], ['index,bogus', 'bogus'], [' bogus ', 'bogus'], ['All', 'All'], ['ref_guard', 'ref_guard'], ['close_gate', 'close_gate']];
    for (const [value, token] of refused) {
      for (const flag of ['--hooks', '-Hooks']) {
        const r = await runModule([flag, value]);
        assert.equal(r.code, 2, `${flag} ${JSON.stringify(value)}`);
        assert.equal(r.stdout, '');
        assert.equal(r.stderr, `ERROR: unknown --hooks value: '${token}' ${HOOKS_SET}\n`, JSON.stringify(value));
        assert.deepEqual(r.calls, []);
      }
    }
    const { parseArgs, resolveMode } = await import(MODULE_URL);
    const selected = (value) => resolveMode(parseArgs(['--hooks', value])).selected;
    assert.deepEqual(selected(' index'), ['index']);
    assert.deepEqual(selected('index '), ['index']);
    assert.deepEqual(selected('\tindex\t'), ['index']);
    assert.deepEqual(selected('index, ref-guard'), ['index', 'ref-guard']);
    assert.deepEqual(selected(' all '), ALL_HOOKS);
    assert.deepEqual(selected('close-gate'), ['close-gate']);
  });

  test('TEST-3982 resolveBase uses PWD only when it names the working directory', async () => {
    const { resolveBase } = await import(MODULE_URL);
    const base = scratch('base-');
    const real = path.join(base, 'real');
    const link = path.join(base, 'link');
    const other = path.join(base, 'other');
    mkdirSync(path.join(real, 'sub'), { recursive: true });
    mkdirSync(other);
    symlinkSync(real, link);
    // a matching PWD (a symlinked working directory) keeps the logical path
    assert.equal(resolveBase({ PWD: link }, real), link);
    assert.equal(resolveBase({ PWD: `${link}/` }, real), link);
    assert.equal(resolveBase({ PWD: `${link}/sub/..` }, real), link);
    assert.equal(resolveBase({ PWD: real }, real), real);
    assert.equal(resolveBase({ PWD: `${link}/.` }, real), link);
    assert.equal(resolveBase({ PWD: `${link}//` }, real), link);
    // R2-B1: a '..' after a symlink is followed by the OS from the link's target, not lexically; the returned path
    // must be the one that was checked, so PWD=<other>/lnk/.. with lnk -> <real>/sub names <real>, never <other>
    symlinkSync(path.join(real, 'sub'), path.join(other, 'lnk'));
    assert.equal(statSync(`${other}/lnk/..`).ino, statSync(real).ino, 'the OS resolves the link first');
    assert.equal(resolveBase({ PWD: `${other}/lnk/..` }, real), real);
    assert.equal(resolveBase({ PWD: `${other}/lnk/../` }, real), real);
    // a stale, relative, missing, empty or absent PWD is ignored
    assert.equal(resolveBase({ PWD: other }, real), real);
    assert.equal(resolveBase({ PWD: path.join(base, 'missing') }, real), real);
    assert.equal(resolveBase({ PWD: 'real' }, real), real);
    assert.equal(resolveBase({ PWD: '' }, real), real);
    assert.equal(resolveBase({}, real), real);
    // the defaults are the process environment and working directory
    assert.equal(resolveBase(), resolveBase(process.env, process.cwd()));
  });

  test('TEST-3982 a real process exits 2 for a usage error and 0 for help, with nothing on the other stream', () => {
    const root = scratch('proc-');
    const bad = runInstaller({ args: ['--uninstall', '--print'], root });
    assert.equal(bad.status, 2);
    assert.equal(bad.stdout, '');
    assert.equal(bad.stderr, 'ERROR: --uninstall and --print are contradictory.\n');
    const help = runInstaller({ args: ['-Force', '--help'], root });
    assert.equal(help.status, 0);
    assert.equal(help.stderr, '');
    assert.equal(help.stdout, expectedHelp());
    assert.deepEqual(listTree(root).filter((f) => f !== OWN_MARKER_FILE && f !== 'gitconfig' && f !== 'tmp'), [], 'the runs created nothing');
  });
});

// --- TEST-3983: ---------------------------------------------------------------------------------------------

const GUARD_CONFIG_URL = pathToFileURL(path.join(ROOT, '.aai', 'scripts', 'lib', 'guard-config.mjs')).href;
const DOCTOR = path.join(ROOT, '.aai', 'scripts', 'aai-doctor.mjs');
const CFG = 'docs-audit.yaml';
const BOM = '﻿';

// cfgDir(label, bytes): a fresh own scratch directory standing for docs/ai, with the config written when given.
function cfgDir(label, bytes) {
  const dir = path.join(scratch(label), 'ai');
  mkdirSync(dir);
  if (bytes !== undefined) writeFileSync(path.join(dir, CFG), bytes);
  return dir;
}
const cfgBytes = (dir) => readFileSync(path.join(dir, CFG));
const cfgText = (dir) => cfgBytes(dir).toString('latin1');
const noTemp = (dir) => assert.deepEqual(readdirSync(dir).filter((f) => f.includes('.aai-tmp.')), [], 'no temp sibling is left');

// gitScratch(root, name): a scratch repository (no commit needed) with isolated git configuration.
function gitScratch(root, name = 'repo') {
  const repo = path.join(root, name);
  mkdirSync(repo, { recursive: true });
  const env = prepareEnv(root);
  assert.equal(spawnSync('git', ['init', '-q'], { cwd: repo, env, encoding: 'utf8' }).status, 0);
  return repo;
}

describe('TEST-3983 the ref_guard policy writer and the reader', () => {
  test('TEST-3983 seeds an absent file from seedFrom or from nothing and creates the directory', async () => {
    const { writeRefGuardPolicy, readRefGuardPolicy } = await import(GUARD_CONFIG_URL);
    const root = scratch('seed-');
    const tpl = path.join(root, 'tpl.yaml');
    writeFileSync(tpl, '# seed\r\nstale_after_days: 90\r\n');
    const dir = path.join(root, 'new', 'ai');
    const r = writeRefGuardPolicy(dir, 'declined', { seedFrom: tpl });
    assert.deepEqual({ ...r, path: path.basename(r.path) }, { path: CFG, seeded: 'template', changed: true, removed: [] });
    assert.equal(cfgText(dir), '# seed\r\nstale_after_days: 90\r\nref_guard: declined\r\n', 'the template bytes, then the key with the file terminator');
    assert.equal(readRefGuardPolicy(dir), 'declined');
    const dir2 = path.join(root, 'other', 'ai');
    const r2 = writeRefGuardPolicy(dir2, 'armed', { seedFrom: path.join(root, 'missing.yaml') });
    assert.equal(r2.seeded, 'empty');
    assert.equal(cfgText(dir2), 'ref_guard: armed\n');
    const dir3 = path.join(root, 'third', 'ai');
    assert.equal(writeRefGuardPolicy(dir3, 'armed', { seedFrom: root }).seeded, 'empty', 'a directory is not a seed');
    const dir4 = cfgDir('seed-existing-', 'a: 1\n');
    assert.equal(writeRefGuardPolicy(dir4, 'armed', { seedFrom: tpl }).seeded, null, 'an existing file is never seeded');
    assert.equal(cfgText(dir4), 'a: 1\nref_guard: armed\n');
    assert.throws(() => writeRefGuardPolicy(dir4, 'maybe'), /armed or declined/);
    assert.throws(() => writeRefGuardPolicy(dir4, undefined), /armed or declined/);
    assert.equal(cfgText(dir4), 'a: 1\nref_guard: armed\n', 'a refused value writes nothing');
  });

  test('TEST-3983 a symbolic link is written through and kept, a dangling or non-file link is refused', async () => {
    const { writeRefGuardPolicy } = await import(GUARD_CONFIG_URL);
    const root = scratch('link-');
    const real = path.join(root, 'real.yaml');
    writeFileSync(real, 'x: 1\nref_guard: armed\n');
    const dir = path.join(root, 'ai');
    mkdirSync(dir);
    symlinkSync(real, path.join(dir, CFG));
    const r = writeRefGuardPolicy(dir, 'declined');
    assert.equal(r.changed, true);
    assert.ok(lstatSync(path.join(dir, CFG)).isSymbolicLink(), 'the link is kept');
    assert.equal(readlinkSync(path.join(dir, CFG)), real);
    assert.equal(readFileSync(real, 'utf8'), 'x: 1\nref_guard: declined\n', 'the target is written');
    noTemp(root);
    const dir2 = path.join(root, 'ai2');
    mkdirSync(dir2);
    const ghost = path.join(root, 'ghost.yaml');
    symlinkSync(ghost, path.join(dir2, CFG));
    assert.throws(() => writeRefGuardPolicy(dir2, 'armed'), (e) => e.message === `${path.join(dir2, CFG)} is a symbolic link to ${ghost}; nothing was written`);
    assert.ok(!existsSync(ghost), 'the dangling target was not created');
    assert.ok(lstatSync(path.join(dir2, CFG)).isSymbolicLink());
    const dir3 = path.join(root, 'ai3');
    mkdirSync(dir3);
    symlinkSync(root, path.join(dir3, CFG));
    assert.throws(() => writeRefGuardPolicy(dir3, 'armed'), /is a symbolic link to .*; nothing was written/);
    assert.deepEqual(readdirSync(dir3), [CFG]);
  });

  test('TEST-3983 the permission bits of the file are kept (0644 and 0600) and a new file gets 0666 minus umask', async () => {
    const { writeRefGuardPolicy } = await import(GUARD_CONFIG_URL);
    for (const mode of [0o644, 0o600, 0o664]) {
      const dir = cfgDir('mode-', 'ref_guard: armed\n');
      chmodSync(path.join(dir, CFG), mode);
      writeRefGuardPolicy(dir, 'declined');
      assert.equal(statSync(path.join(dir, CFG)).mode & 0o777, mode, `mode ${mode.toString(8)} kept`);
      assert.equal(cfgText(dir), 'ref_guard: declined\n');
    }
    const fresh = path.join(scratch('mode-new-'), 'ai');
    writeRefGuardPolicy(fresh, 'armed');
    const old = process.umask(0o022);
    process.umask(old);
    assert.equal(statSync(path.join(fresh, CFG)).mode & 0o777, 0o666 & ~old);
  });

  test('TEST-3983 each line keeps its own terminator and a leading BOM is kept byte for byte', async () => {
    const { writeRefGuardPolicy, readRefGuardPolicy } = await import(GUARD_CONFIG_URL);
    const dir = cfgDir('eol-', 'a: 1\r\nref_guard: armed\nb: 2\r\nc: 3\n');
    writeRefGuardPolicy(dir, 'declined');
    assert.equal(cfgText(dir), 'a: 1\r\nref_guard: declined\nb: 2\r\nc: 3\n', 'the replaced LF line stays LF, the CRLF lines stay CRLF');
    const crlf = cfgDir('eol-crlf-', 'ref_guard: armed\r\nb: 2\r\n');
    writeRefGuardPolicy(crlf, 'declined');
    assert.equal(cfgText(crlf), 'ref_guard: declined\r\nb: 2\r\n', 'a replaced CRLF line keeps its CR');
    const last = cfgDir('eol-last-', 'a: 1\nref_guard: armed');
    writeRefGuardPolicy(last, 'declined');
    assert.equal(cfgText(last), 'a: 1\nref_guard: declined', 'a last line without a terminator gets none');
    const bom = cfgDir('eol-bom-', Buffer.concat([Buffer.from(BOM, 'utf8'), Buffer.from('ref_guard: armed\r\nb: 2\r\n')]));
    const r = writeRefGuardPolicy(bom, 'declined');
    assert.equal(r.changed, true);
    assert.deepEqual([...cfgBytes(bom).subarray(0, 3)], [0xef, 0xbb, 0xbf], 'the BOM bytes are kept');
    assert.equal(cfgBytes(bom).subarray(3).toString('latin1'), 'ref_guard: declined\r\nb: 2\r\n', 'line 1 matched without the BOM');
    assert.equal(readRefGuardPolicy(bom), 'declined');
    const raw = Buffer.concat([Buffer.from([0xff, 0xfe, 0x80, 0x0a]), Buffer.from('ref_guard: armed\n')]);
    const bin = cfgDir('eol-bin-', raw);
    writeRefGuardPolicy(bin, 'declined');
    assert.deepEqual([...cfgBytes(bin).subarray(0, 4)], [0xff, 0xfe, 0x80, 0x0a], 'bytes that are not UTF-8 survive a rewrite');
  });

  test('TEST-3983 the first key line is replaced (valued or not), every later one removed with its line number', async () => {
    const { writeRefGuardPolicy } = await import(GUARD_CONFIG_URL);
    const dir = cfgDir('dup-', 'a: 1\nref_guard: armed\nb: 2\nref_guard: declined\n  ref_guard: armed\nref_guard:\nz: 1\n');
    const r = writeRefGuardPolicy(dir, 'declined');
    assert.deepEqual(r.removed, [4, 6]);
    assert.equal(r.changed, true);
    assert.equal(cfgText(dir), 'a: 1\nref_guard: declined\nb: 2\n  ref_guard: armed\nz: 1\n', 'an indented line is not a key line');
    const bare = cfgDir('dup-bare-', 'ref_guard:\nref_guard: armed\n');
    const r2 = writeRefGuardPolicy(bare, 'armed');
    assert.deepEqual(r2.removed, [2]);
    assert.equal(cfgText(bare), 'ref_guard: armed\n', 'a value-less key line is the key');
    const typo = cfgDir('dup-typo-', 'ref_guard: arme\nb: 1\n');
    assert.equal(writeRefGuardPolicy(typo, 'armed').changed, true);
    assert.equal(cfgText(typo), 'ref_guard: armed\nb: 1\n');
    const crlfDup = cfgDir('dup-crlf-', 'ref_guard: armed\r\nref_guard: declined\r\nb: 1\r\n');
    assert.deepEqual(writeRefGuardPolicy(crlfDup, 'declined').removed, [2]);
    assert.equal(cfgText(crlfDup), 'ref_guard: declined\r\nb: 1\r\n');
    const probe = cfgDir('dup-dry-', 'ref_guard: armed\nb: 1\nref_guard: declined\n');
    const before = cfgBytes(probe);
    const d = writeRefGuardPolicy(probe, 'armed', { dryRun: true });
    assert.deepEqual({ changed: d.changed, removed: d.removed, keyLines: d.keyLines }, { changed: false, removed: [3], keyLines: [1, 3] });
    assert.ok(Buffer.compare(before, cfgBytes(probe)) === 0);
    const none = path.join(scratch('dup-dry-none-'), 'ai');
    assert.deepEqual(writeRefGuardPolicy(none, 'armed', { dryRun: true }).keyLines, []);
    assert.ok(!existsSync(none), 'a dry run creates nothing');
  });

  test('TEST-3983 a missing key is appended with the file terminator, LF when it has none', async () => {
    const { writeRefGuardPolicy } = await import(GUARD_CONFIG_URL);
    const cases = [
      ['a: 1\r\nb: 2\r\n', 'a: 1\r\nb: 2\r\nref_guard: armed\r\n'],
      ['a: 1\r\nb: 2', 'a: 1\r\nb: 2\r\nref_guard: armed\r\n'],
      ['a: 1\nb: 2', 'a: 1\nb: 2\nref_guard: armed\n'],
      ['a: 1\nb: 2\n', 'a: 1\nb: 2\nref_guard: armed\n'],
      ['a: 1\nb: 2\r\n', 'a: 1\nb: 2\r\nref_guard: armed\n'],
      ['a: 1', 'a: 1\nref_guard: armed\n'],
      ['', 'ref_guard: armed\n'],
      ['# ref_guard: declined\n  ref_guard: declined\n', '# ref_guard: declined\n  ref_guard: declined\nref_guard: armed\n'],
    ];
    for (const [before, after] of cases) {
      const dir = cfgDir('append-', before);
      const r = writeRefGuardPolicy(dir, 'armed');
      assert.equal(r.changed, true, JSON.stringify(before));
      assert.equal(cfgText(dir), after, JSON.stringify(before));
      assert.deepEqual(r.removed, []);
    }
  });

  test('TEST-3983 nothing is written when the result equals the current bytes', async () => {
    const { writeRefGuardPolicy } = await import(GUARD_CONFIG_URL);
    const dir = cfgDir('noop-', 'a: 1\nref_guard: declined\n');
    const file = path.join(dir, CFG);
    utimesSync(file, new Date(1_000_000), new Date(1_000_000));
    const before = statSync(file);
    const r = writeRefGuardPolicy(dir, 'declined');
    assert.equal(r.changed, false);
    assert.equal(r.seeded, null);
    const after = statSync(file);
    assert.equal(after.mtimeMs, before.mtimeMs);
    assert.equal(after.ino, before.ino);
    noTemp(dir);
    chmodSync(file, 0o444);
    assert.equal(writeRefGuardPolicy(dir, 'declined').changed, false, 'a read-only file whose bytes already match is a no-op, not a refusal');
  });

  test('TEST-3983 a target the process cannot write is refused with nothing written', async (t) => {
    if (process.platform === 'win32' || (process.getuid && process.getuid() === 0)) return t.skip('permission bits are not enforced here');
    const { writeRefGuardPolicy } = await import(GUARD_CONFIG_URL);
    const dir = cfgDir('ro-', 'a: 1\nref_guard: armed\n');
    const file = path.join(dir, CFG);
    chmodSync(file, 0o444);
    utimesSync(file, new Date(2_000_000), new Date(2_000_000));
    const before = statSync(file);
    assert.throws(() => writeRefGuardPolicy(dir, 'declined'), (e) => e.message === `${file} is not writable; nothing was written`);
    assert.equal(cfgText(dir), 'a: 1\nref_guard: armed\n');
    assert.equal(statSync(file).mtimeMs, before.mtimeMs);
    assert.equal(statSync(file).mode & 0o777, 0o444);
    noTemp(dir);
    const dir2 = cfgDir('ro-dir-', 'ref_guard: armed\n');
    chmodSync(dir2, 0o555);
    try {
      assert.throws(() => writeRefGuardPolicy(dir2, 'declined'), /nothing was written/);
      assert.equal(cfgText(dir2), 'ref_guard: armed\n');
    } finally {
      chmodSync(dir2, 0o755);
    }
    noTemp(dir2);
  });

  test('TEST-3983 a temp-named file this run did not create survives the policy write and the slot write', async () => {
    const { writeRefGuardPolicy } = await import(GUARD_CONFIG_URL);
    const dir = cfgDir('foreign-tmp-', 'a: 1\nref_guard: armed\n');
    const foreign = path.join(dir, `${CFG}.aai-tmp.${process.pid}`);
    writeFileSync(foreign, 'not ours\n');
    writeRefGuardPolicy(dir, 'declined');
    assert.equal(readFileSync(foreign, 'utf8'), 'not ours\n', 'the foreign temp file is untouched');
    assert.equal(cfgText(dir), 'a: 1\nref_guard: declined\n');
    assert.deepEqual(readdirSync(dir).filter((f) => f.includes('.aai-tmp.')), [path.basename(foreign)], 'only the foreign file remains');
    const { writeSlot } = await import(MODULE_URL);
    const root = scratch('foreign-slot-tmp-');
    const slotPath = path.join(root, 'pre-push');
    const slotForeign = `${slotPath}.aai-tmp.${process.pid}`;
    writeFileSync(slotForeign, 'not ours\n');
    const slot = { path: slotPath, rename: (a, b) => renameSync(a, b) };
    writeSlot(slot, Buffer.from('hook\n'));
    assert.equal(readFileSync(slotForeign, 'utf8'), 'not ours\n', 'the foreign slot temp file is untouched');
    assert.equal(readFileSync(slotPath, 'utf8'), 'hook\n');
    assert.notEqual(slot.tmp, slotForeign, 'the run used another name');
  });

  test('TEST-3983 a failed rename leaves no temp file and the original bytes; a read-back mismatch throws', async () => {
    const { writeRefGuardPolicy } = await import(GUARD_CONFIG_URL);
    const dir = cfgDir('fail-', 'a: 1\nref_guard: armed\n');
    const seen = [];
    const rename = (from) => { seen.push(from); assert.ok(existsSync(from), 'the temp exists before the rename'); throw new Error('rename refused'); };
    assert.throws(() => writeRefGuardPolicy(dir, 'declined', { rename }), /rename refused/);
    assert.equal(seen.length, 1);
    assert.match(path.basename(seen[0]), /^docs-audit\.yaml\.aai-tmp\.[0-9]+$/);
    assert.equal(cfgText(dir), 'a: 1\nref_guard: armed\n');
    noTemp(dir);
    const dir2 = cfgDir('readback-', 'a: 1\n');
    assert.throws(() => writeRefGuardPolicy(dir2, 'declined', { readBack: () => 'armed' }), (e) => e.message === `wrote ref_guard: declined to ${path.join(dir2, CFG)} but reading it back gives armed`);
  });

  test('TEST-3983 the reader reads a BOM-prefixed first line and keeps every other verdict', async () => {
    const { readRefGuardPolicy } = await import(GUARD_CONFIG_URL);
    const verdicts = [
      [undefined, 'armed', false],
      ['a: 1\n', 'armed', false],
      ['ref_guard: declined\n', 'declined', false],
      ['ref_guard:declined\n', 'declined', false],
      ['ref_guard:\tdeclined\r\n', 'declined', false],
      ['ref_guard: declined # why\n', 'declined', false],
      ['ref_guard: armed\nref_guard: declined\n', 'armed', false],
      ['  ref_guard: declined\n', 'armed', false],
      ['# ref_guard: declined\n', 'armed', false],
      ['ref_guard: Declined\n', 'armed', true],
      ['ref_guard: declined#x\n', 'armed', true],
      [`${BOM}ref_guard: declined\n`, 'declined', false],
      [`${BOM}ref_guard: declined\r\nb: 1\r\n`, 'declined', false],
      [`${BOM}a: 1\nref_guard: declined\n`, 'declined', false],
      [`${BOM}${BOM}ref_guard: declined\n`, 'armed', false],
      [`a: 1\n${BOM}ref_guard: declined\n`, 'armed', false],
      [`${BOM}  ref_guard: declined\n`, 'armed', false],
      [`${BOM}ref_guard: armed\n`, 'armed', false],
    ];
    for (const [text, want, warns] of verdicts) {
      const dir = cfgDir('reader-', text);
      const seen = [];
      assert.equal(readRefGuardPolicy(dir, { warn: (m) => seen.push(m) }), want, JSON.stringify(text));
      assert.equal(seen.length > 0, warns, `${JSON.stringify(text)} warning`);
    }
  });

  test('TEST-3983 aai-doctor CAT-17 reports DECLINED for a BOM-prefixed declined file and no hook', () => {
    const root = scratch('doctor-');
    const repo = gitScratch(root);
    mkdirSync(path.join(repo, 'docs', 'ai'), { recursive: true });
    writeFileSync(path.join(repo, 'docs', 'ai', CFG), Buffer.concat([Buffer.from(BOM, 'utf8'), Buffer.from('ref_guard: declined\n')]));
    const env = prepareEnv(root);
    const r = spawnSync(process.execPath, [DOCTOR, '--root', repo, '--json'], { cwd: root, env, encoding: 'utf8' });
    const cat17 = JSON.parse(r.stdout).categories.find((c) => c.id === 'CAT-17');
    assert.equal(cat17.status, 'DECLINED', r.stdout);
    writeFileSync(path.join(repo, 'docs', 'ai', CFG), 'ref_guard: armed\n');
    const r2 = spawnSync(process.execPath, [DOCTOR, '--root', repo, '--json'], { cwd: root, env, encoding: 'utf8' });
    assert.notEqual(JSON.parse(r2.stdout).categories.find((c) => c.id === 'CAT-17').status, 'DECLINED', 'the control: armed is not DECLINED');
  });
});

// --- TEST-3984: ---------------------------------------------------------------------------------------------

const hookOf = (repo, name) => path.join(repo, '.git', 'hooks', name);
const CFG_REL = path.join('docs', 'ai', CFG);
const BASH_INSTALLER = (repo) => `bash ${repo}/.aai/scripts/install-pre-commit-hook.sh`;

// policyRepo(label, cfg, extra): a scratch repository whose docs/ai/docs-audit.yaml holds cfg (absent when undefined).
function policyRepo(label, cfg) {
  const root = scratch(label);
  const repo = gitScratch(root);
  if (cfg !== undefined) {
    mkdirSync(path.join(repo, 'docs', 'ai'), { recursive: true });
    writeFileSync(path.join(repo, CFG_REL), cfg);
  }
  return { root, repo, cfgPath: path.join(repo, CFG_REL), run: (...args) => runInstaller({ args, root, cwd: repo }) };
}
const skippedLines = (repo) => [
  `Skipped AAI reference-transaction hook (AAI:REF-GUARD): ${path.join(repo, CFG_REL)} declares ref_guard: declined.\n`,
  `Re-arm with: ${BASH_INSTALLER(repo)} --arm-ref-guard (--force installs the hook for this run only; ref_guard: declined stays recorded).\n`,
];

describe('TEST-3984 the policy flows', () => {
  test('TEST-3984 a plain install skips the ref-guard for every reader verdict of declined and installs it otherwise', () => {
    const declined = ['ref_guard: declined\n', `${BOM}ref_guard: declined\n`, 'ref_guard:declined\r\nx: 1\r\n', 'a: 1\nref_guard: declined # why\n'];
    for (const cfg of declined) {
      const { repo, run } = policyRepo('skip-', cfg);
      const r = run();
      assert.equal(r.status, 0, `${JSON.stringify(cfg)}: ${r.stderr}`);
      for (const line of skippedLines(repo)) assert.ok(r.stdout.includes(line), `${JSON.stringify(cfg)} says: ${line}`);
      assert.ok(!existsSync(hookOf(repo, 'reference-transaction')), `${JSON.stringify(cfg)}: no ref-guard`);
      assert.ok(existsSync(hookOf(repo, 'pre-commit')) && existsSync(hookOf(repo, 'pre-push')), 'the other two hooks are installed');
      assert.ok(r.stdout.trimEnd().endsWith('Uninstall with: bash .aai/scripts/install-pre-commit-hook.sh --uninstall'));
    }
    for (const cfg of [undefined, 'ref_guard: armed\n', 'ref_guard: Declined\n', 'a: 1\n  ref_guard: declined\n']) {
      const { repo, run } = policyRepo('arm-plain-', cfg);
      const r = run();
      assert.equal(r.status, 0, `${JSON.stringify(cfg)}: ${r.stderr}`);
      assert.ok(existsSync(hookOf(repo, 'reference-transaction')), `${JSON.stringify(cfg)}: the ref-guard is installed`);
      assert.ok(!r.stdout.includes('Skipped AAI reference-transaction'));
      assert.ok(r.stdout.includes(`Installed AAI reference-transaction hook (AAI:REF-GUARD) at ${hookOf(repo, 'reference-transaction')}\n`));
      assert.ok(r.stdout.includes(`Decline: ${BASH_INSTALLER(repo)} --decline-ref-guard\n`), 'the install disclosure names the decline command');
    }
    const invalid = policyRepo('invalid-', 'ref_guard: maybe\n');
    const ri = invalid.run();
    assert.equal(ri.status, 0);
    assert.match(ri.stderr, /^install-pre-commit-hook: WARNING ref_guard value "maybe" in .* treating as armed/m, 'the reader warning goes to stderr under the module prefix');
    assert.ok(existsSync(hookOf(invalid.repo, 'reference-transaction')));
  });

  test('TEST-3984 --force passes a decline for this run and leaves declined recorded; a selected skip is not attested', () => {
    const { repo, run, cfgPath } = policyRepo('force-', 'ref_guard: declined\n');
    const r = run('--force');
    assert.equal(r.status, 0, r.stderr);
    assert.ok(existsSync(hookOf(repo, 'reference-transaction')));
    assert.equal(readFileSync(cfgPath, 'utf8'), 'ref_guard: declined\n');
    const only = policyRepo('skip-only-', 'ref_guard: declined\n');
    const r2 = only.run('--hooks', 'ref-guard');
    assert.equal(r2.status, 0, r2.stderr);
    assert.ok(!existsSync(hookOf(only.repo, 'reference-transaction')));
    assert.deepEqual(readdirSync(path.join(only.repo, '.git', 'hooks')).filter((f) => !f.endsWith('.sample')), [], 'a declined-only run writes no hook');
  });

  test('TEST-3984 decline refuses a foreign hook unmodified and writes the declaration before removing an AAI hook', () => {
    const foreign = policyRepo('decline-foreign-');
    mkdirSync(path.join(foreign.repo, '.git', 'hooks'), { recursive: true });
    writeFileSync(hookOf(foreign.repo, 'reference-transaction'), '#!/bin/sh\necho mine\n');
    const r = foreign.run('--decline-ref-guard');
    assert.equal(r.status, 1);
    assert.equal(r.stderr, `ERROR: ${hookOf(foreign.repo, 'reference-transaction')} already exists and is not AAI-managed.\n       Refusing to remove a foreign hook -- --decline-ref-guard only removes an AAI-managed guard.\n`);
    assert.equal(readFileSync(hookOf(foreign.repo, 'reference-transaction'), 'utf8'), '#!/bin/sh\necho mine\n');
    assert.ok(!existsSync(foreign.cfgPath), 'a refusal writes no declaration');

    const { repo, run, cfgPath } = policyRepo('decline-aai-', 'a: 1\nref_guard: armed\n');
    assert.equal(run('--hooks', 'ref-guard').status, 0);
    assert.ok(existsSync(hookOf(repo, 'reference-transaction')));
    const d = run('--decline-ref-guard');
    assert.equal(d.status, 0, d.stderr);
    assert.equal(readFileSync(cfgPath, 'utf8'), 'a: 1\nref_guard: declined\n');
    assert.ok(!existsSync(hookOf(repo, 'reference-transaction')));
    assert.equal(d.stdout, [
      `Uninstalled AAI reference-transaction hook (AAI:REF-GUARD) from ${hookOf(repo, 'reference-transaction')}`,
      `Declined the AAI reference-transaction guard. Recorded ref_guard: declined in ${cfgPath}`,
      `Re-arm with: bash ${repo}/.aai/scripts/install-pre-commit-hook.sh --arm-ref-guard`,
      '',
    ].join('\n'));
    // declining again is idempotent and says nothing about a removal
    const again = run('--decline-ref-guard');
    assert.equal(again.status, 0);
    assert.ok(!again.stdout.includes('Uninstalled'));
    assert.equal(readFileSync(cfgPath, 'utf8'), 'a: 1\nref_guard: declined\n');
  });

  test('TEST-3984 decline refuses a symlinked foreign hook like a regular one, and a directory slot as a bad type (DR-23)', () => {
    const lnk = policyRepo('decline-link-foreign-');
    mkdirSync(path.join(lnk.repo, '.git', 'hooks'), { recursive: true });
    const target = path.join(lnk.root, 'elsewhere-foreign');
    writeFileSync(target, '#!/bin/sh\necho mine\n', { mode: 0o755 });
    symlinkSync(target, hookOf(lnk.repo, 'reference-transaction'));
    const r = lnk.run('--decline-ref-guard');
    assert.equal(r.status, 1, r.stdout);
    assert.equal(r.stderr, `ERROR: ${hookOf(lnk.repo, 'reference-transaction')} already exists and is not AAI-managed.\n       Refusing to remove a foreign hook -- --decline-ref-guard only removes an AAI-managed guard.\n`);
    assert.equal(readFileSync(target, 'utf8'), '#!/bin/sh\necho mine\n');
    assert.ok(lstatSync(hookOf(lnk.repo, 'reference-transaction')).isSymbolicLink(), 'the link is untouched');
    assert.ok(!existsSync(lnk.cfgPath), 'a refusal writes no declaration');

    const dir = policyRepo('decline-dir-slot-');
    mkdirSync(hookOf(dir.repo, 'reference-transaction'), { recursive: true });
    const d = dir.run('--decline-ref-guard');
    assert.equal(d.status, 1, d.stdout);
    assert.match(d.stderr, /is a directory, not a regular file\. Nothing was written/);
    assert.ok(lstatSync(hookOf(dir.repo, 'reference-transaction')).isDirectory());
    assert.ok(!existsSync(dir.cfgPath), 'a refusal writes no declaration');

    // R2-N1 (DR-23): a dangling link and a link to a directory are refused as bad-type slots too, nothing written
    const dang = policyRepo('decline-dangling-');
    mkdirSync(path.join(dang.repo, '.git', 'hooks'), { recursive: true });
    symlinkSync(path.join(dang.root, 'nowhere'), hookOf(dang.repo, 'reference-transaction'));
    const g = dang.run('--decline-ref-guard');
    assert.equal(g.status, 1, g.stdout);
    assert.match(g.stderr, /is a dangling symbolic link\. Nothing was written/);
    assert.ok(lstatSync(hookOf(dang.repo, 'reference-transaction')).isSymbolicLink());
    assert.ok(!existsSync(dang.cfgPath), 'a refusal writes no declaration');

    const ldir = policyRepo('decline-link-dir-');
    mkdirSync(path.join(ldir.repo, '.git', 'hooks'), { recursive: true });
    mkdirSync(path.join(ldir.root, 'some-dir'));
    symlinkSync(path.join(ldir.root, 'some-dir'), hookOf(ldir.repo, 'reference-transaction'));
    const l = ldir.run('--decline-ref-guard');
    assert.equal(l.status, 1, l.stdout);
    assert.match(l.stderr, /is a symbolic link to a directory\. Nothing was written/);
    assert.ok(lstatSync(hookOf(ldir.repo, 'reference-transaction')).isSymbolicLink());
    assert.ok(!existsSync(ldir.cfgPath), 'a refusal writes no declaration');
  });

  test('TEST-3984 decline discloses the creation of the config: SEED from the template, NOTE without one', () => {
    const noTpl = policyRepo('decline-note-');
    const r = noTpl.run('--decline-ref-guard');
    assert.equal(r.status, 0, r.stderr);
    assert.ok(r.stdout.startsWith('NOTE: creating docs/ai/docs-audit.yaml -- this switches docs-audit from report-only to enforced mode'), r.stdout);
    assert.equal(readFileSync(noTpl.cfgPath, 'utf8'), 'ref_guard: declined\n');
    const withTpl = policyRepo('decline-seed-');
    mkdirSync(path.join(withTpl.repo, '.aai', 'templates'), { recursive: true });
    const tpl = readFileSync(path.join(ROOT, '.aai', 'templates', 'docs-audit.template.yaml'));
    writeFileSync(path.join(withTpl.repo, '.aai', 'templates', 'docs-audit.template.yaml'), tpl);
    const r2 = withTpl.run('--decline-ref-guard');
    assert.equal(r2.status, 0, r2.stderr);
    assert.ok(r2.stdout.startsWith('SEED docs/ai/docs-audit.yaml from .aai/templates/docs-audit.template.yaml (dials report-only; docs-audit --check now runs enforced)\n'), r2.stdout);
    assert.ok(readFileSync(withTpl.cfgPath).subarray(0, tpl.length).equals(tpl), 'the template bytes come first');
    assert.match(readFileSync(withTpl.cfgPath, 'utf8'), /\nref_guard: declined\n$/);
  });

  test('TEST-3984 decline keeps the hook and exits 1 when the config cannot be written', (t) => {
    if (process.platform === 'win32' || (process.getuid && process.getuid() === 0)) return t.skip('permission bits are not enforced here');
    const ro = policyRepo('decline-ro-', 'ref_guard: armed\n');
    assert.equal(ro.run('--hooks', 'ref-guard').status, 0);
    chmodSync(ro.cfgPath, 0o444);
    const r = ro.run('--decline-ref-guard');
    assert.equal(r.status, 1);
    assert.match(r.stderr, /docs-audit\.yaml is not writable; nothing was written/);
    assert.ok(existsSync(hookOf(ro.repo, 'reference-transaction')), 'the hook stays');
    assert.equal(readFileSync(ro.cfgPath, 'utf8'), 'ref_guard: armed\n');
    assert.ok(!r.stdout.includes('Uninstalled'));
    const dir = policyRepo('decline-rodir-', 'ref_guard: armed\n');
    assert.equal(dir.run('--hooks', 'ref-guard').status, 0);
    chmodSync(path.join(dir.repo, 'docs', 'ai'), 0o555);
    try {
      const r2 = dir.run('--decline-ref-guard');
      assert.equal(r2.status, 1);
      assert.ok(existsSync(hookOf(dir.repo, 'reference-transaction')), 'the hook stays');
      assert.equal(readFileSync(dir.cfgPath, 'utf8'), 'ref_guard: armed\n');
    } finally {
      chmodSync(path.join(dir.repo, 'docs', 'ai'), 0o755);
    }
  });

  test('TEST-3984 arm records armed after the attested hook; the round trip leaves one key line and a plain run stays quiet', () => {
    const { repo, run, cfgPath } = policyRepo('arm-', 'ref_guard: declined\n');
    const a = run('--arm-ref-guard');
    assert.equal(a.status, 0, a.stderr);
    assert.equal(a.stdout, [
      `Installed AAI reference-transaction hook (AAI:REF-GUARD) at ${hookOf(repo, 'reference-transaction')}`,
      `Effect: a refs/heads/main update is refused unless AAI_GIT_WRITE=1 is set on that command. Decline: ${BASH_INSTALLER(repo)} --decline-ref-guard`,
      `Recorded ref_guard: armed in ${cfgPath}`,
      '',
    ].join('\n'));
    assert.equal(readFileSync(cfgPath, 'utf8'), 'ref_guard: armed\n');
    assert.ok(statSync(hookOf(repo, 'reference-transaction')).mode & 0o100, 'the hook is executable');
    // arming again: current hook, no write, the declaration is still recorded
    const b = run('--arm-ref-guard');
    assert.equal(b.status, 0, b.stderr);
    assert.ok(b.stdout.startsWith(`AAI reference-transaction hook already installed at ${hookOf(repo, 'reference-transaction')}. No action taken.\n`));
    assert.ok(b.stdout.endsWith(`Recorded ref_guard: armed in ${cfgPath}\n`));
    // decline then a plain install on what decline wrote (the seam): quiet skip, exit 0
    assert.equal(run('--decline-ref-guard').status, 0);
    const p = run();
    assert.equal(p.status, 0, p.stderr);
    for (const line of skippedLines(repo)) assert.ok(p.stdout.includes(line));
    assert.equal(readFileSync(cfgPath, 'utf8'), 'ref_guard: declined\n');
  });

  test('TEST-3984 arm refuses a foreign hook unless forced, naming --print ref-guard, and notes a marked hook that differs', () => {
    const { repo, run, cfgPath } = policyRepo('arm-foreign-');
    mkdirSync(path.join(repo, '.git', 'hooks'), { recursive: true });
    writeFileSync(hookOf(repo, 'reference-transaction'), '#!/bin/sh\necho mine\n');
    const r = run('--arm-ref-guard');
    assert.equal(r.status, 1);
    assert.equal(r.stderr, `ERROR: ${hookOf(repo, 'reference-transaction')} already exists and is not AAI-managed.\n       Pass --force to overwrite, or merge the AAI:REF-GUARD body with: ${repo}/.aai/scripts/install-pre-commit-hook.sh --print ref-guard\n`);
    assert.equal(readFileSync(hookOf(repo, 'reference-transaction'), 'utf8'), '#!/bin/sh\necho mine\n');
    assert.ok(!existsSync(cfgPath), 'a refusal records nothing');
    const plain = run();
    assert.equal(plain.status, 1);
    assert.ok(plain.stderr.includes('--print ref-guard'), 'the plain install names the same command');
    assert.ok(!existsSync(hookOf(repo, 'pre-commit')), 'a foreign slot refuses the whole run before any write');
    const forced = run('--arm-ref-guard', '--force');
    assert.equal(forced.status, 0, forced.stderr);
    assert.match(readFileSync(hookOf(repo, 'reference-transaction'), 'utf8'), /^#!.*\n[\s\S]*AAI:REF-GUARD/);
    // a marked hook whose bytes differ: not rewritten, one more line (DR-14)
    const marked = `${readFileSync(hookOf(repo, 'reference-transaction'), 'utf8')}# local edit\n`;
    writeFileSync(hookOf(repo, 'reference-transaction'), marked);
    const note = run('--arm-ref-guard');
    assert.equal(note.status, 0, note.stderr);
    assert.equal(readFileSync(hookOf(repo, 'reference-transaction'), 'utf8'), marked);
    assert.ok(note.stdout.includes(`No action taken.\nNOTE: ${hookOf(repo, 'reference-transaction')} carries # AAI:REF-GUARD but its bytes differ from the shipped body; pass --force to replace it.\n`), note.stdout);
  });

  test('TEST-3984 uninstalling the ref-guard says what an armed declaration will do, and nothing when declined', () => {
    const note = {
      present: 'NOTE: docs/ai/docs-audit.yaml still reads ref_guard: armed, so the next plain install (for example /aai-update) installs the guard again.\n',
      absent: 'NOTE: docs/ai/docs-audit.yaml does not exist, so ref_guard reads as armed by default and the next plain install (for example /aai-update) installs the guard again.\n',
    };
    for (const cfg of [undefined, 'ref_guard: armed\n']) {
      const { repo, run } = policyRepo('uninstall-armed-', cfg);
      assert.equal(run().status, 0);
      const u = run('--uninstall');
      assert.equal(u.status, 0, u.stderr);
      assert.ok(!existsSync(hookOf(repo, 'reference-transaction')));
      const want = `Uninstalled AAI reference-transaction hook (AAI:REF-GUARD) from ${hookOf(repo, 'reference-transaction')}\n${cfg === undefined ? note.absent : note.present}To keep it off, run: ${BASH_INSTALLER(repo)} --decline-ref-guard\n`;
      assert.ok(u.stdout.includes(want), u.stdout);
    }
    const dec = policyRepo('uninstall-declined-', 'ref_guard: declined\n');
    assert.equal(dec.run('--force').status, 0);
    const u2 = dec.run('--uninstall');
    assert.equal(u2.status, 0, u2.stderr);
    assert.ok(!u2.stdout.includes('NOTE:') && !u2.stdout.includes('To keep it off'));
    // no hook to remove: no disclosure either
    const none = policyRepo('uninstall-none-');
    const u3 = none.run('--uninstall');
    assert.equal(u3.status, 0);
    assert.ok(u3.stdout.includes('No AAI reference-transaction hook found (or hook is not AAI-managed). No action taken.\n'));
    assert.ok(!u3.stdout.includes('To keep it off'));
    // a selection without the ref-guard reads no policy
    const sel = policyRepo('uninstall-sel-', 'ref_guard: maybe\n');
    assert.equal(sel.run().status, 0);
    const u4 = sel.run('--uninstall', '--hooks', 'index');
    assert.equal(u4.status, 0);
    assert.equal(u4.stderr, '', 'no policy read, no reader warning');
  });

  test('TEST-3984 a doubled key warns on a plain run without writing; arm and decline repair it and say so', () => {
    const cfg = 'ref_guard: armed\nb: 1\nref_guard: declined\n';
    const { repo, run, cfgPath } = policyRepo('doubled-', cfg);
    utimesSync(cfgPath, new Date(3_000_000), new Date(3_000_000));
    const before = statSync(cfgPath);
    const p = run();
    assert.equal(p.status, 0, p.stderr);
    assert.equal(p.stderr, `WARNING: ${cfgPath} carries 2 ref_guard: lines (lines 1, 3); the first one wins. Repair: ${BASH_INSTALLER(repo)} --arm-ref-guard (or --decline-ref-guard).\n`);
    assert.equal(readFileSync(cfgPath, 'utf8'), cfg);
    assert.equal(statSync(cfgPath).mtimeMs, before.mtimeMs);
    assert.ok(existsSync(hookOf(repo, 'reference-transaction')), 'the first line (armed) wins');
    const d = run('--decline-ref-guard');
    assert.equal(d.status, 0, d.stderr);
    assert.ok(d.stdout.includes(`Removed 1 duplicate ref_guard: line(s) from ${cfgPath} (lines 3).\n`), d.stdout);
    assert.equal(readFileSync(cfgPath, 'utf8'), 'ref_guard: declined\nb: 1\n');
    const triple = policyRepo('tripled-', 'ref_guard:\nref_guard: armed\nx: 1\nref_guard: declined\n');
    const a = triple.run('--arm-ref-guard');
    assert.equal(a.status, 0, a.stderr);
    assert.ok(a.stdout.includes(`Removed 2 duplicate ref_guard: line(s) from ${triple.cfgPath} (lines 2, 4).\n`), a.stdout);
    assert.equal(readFileSync(triple.cfgPath, 'utf8'), 'ref_guard: armed\nx: 1\n');
    // a single key line: no warning
    const single = policyRepo('single-', 'ref_guard: armed\n');
    assert.equal(single.run().stderr, '');
  });

  test('TEST-3984 the module holds no ref_guard pattern and reads the policy only through the reader', () => {
    const source = readFileSync(MODULE, 'utf8');
    const offending = source.split('\n').filter((l) => l.includes('ref_guard') && /(\.test\(|\.match\(|\.exec\(|RegExp|=~|\^ref_guard|grep )/.test(l) && !/^\s*\/\//.test(l));
    assert.deepEqual(offending, []);
    assert.ok(/readRefGuardPolicy\(path\.join\(/.test(source) || /readRefGuardPolicy\(/.test(source.replace(/import[^\n]*\n/, '')), 'the reader is called');
    assert.ok(/writeRefGuardPolicy\(/.test(source.replace(/import[^\n]*\n/, '')), 'the writer is called');
    assert.ok(!/readFileSync\([^)]*docs-audit/.test(source), 'the config file is not read directly');
  });
});

// --- TEST-3985: ---------------------------------------------------------------------------------------------

const TEMPLATE_FILES = { index: 'pre-commit-index.sh', 'guard-checks': 'pre-commit-guard-checks.sh', 'ref-guard': 'reference-transaction.sh', 'pre-push': 'pre-push.sh' };
const stripCr = (buf) => Buffer.from(buf.filter((b) => b !== 13));

// templateTree(label, mutate): <root>/.aai/{scripts,templates/git-hooks} with the four shipped templates written
// with CRLF line endings; mutate(files) may change the { kind: text } map (a kind set to null is not written).
function templateTree(label, mutate = () => {}) {
  const root = scratch(label);
  const dir = path.join(root, '.aai', 'templates', 'git-hooks');
  mkdirSync(dir, { recursive: true });
  mkdirSync(path.join(root, '.aai', 'scripts'));
  const files = {};
  for (const [kind, name] of Object.entries(TEMPLATE_FILES)) files[kind] = readFileSync(path.join(TEMPLATE_DIR, name), 'utf8');
  mutate(files);
  for (const [kind, text] of Object.entries(files)) if (text !== null) writeFileSync(path.join(dir, TEMPLATE_FILES[kind]), text.replace(/\n/g, '\r\n'));
  return { root, scriptDir: path.join(root, '.aai', 'scripts'), dir, files };
}

// runIn(argv, extra): the module's run() with captured output and a counting child seam; no git child runs
// unless extra.spawn is given.
async function runIn(argv, extra = {}) {
  const { run } = await import(MODULE_URL);
  const out = [];
  const err = [];
  const calls = [];
  const spawn = extra.spawn ?? ((file, args) => { calls.push([file, args]); return { status: 1, stdout: '', stderr: '' }; });
  const code = await run(argv, { out: (s) => out.push(Buffer.from(s)), err: (s) => err.push(s), spawn, ...extra });
  return { code, stdout: Buffer.concat(out), stderr: err.join(''), calls };
}

describe('TEST-3985 templates, --print and composition', () => {
  test('TEST-3985 templates are read from the injected script directory with every CR removed', async () => {
    const tree = templateTree('tpl-crlf-');
    for (const [kind, name] of Object.entries(TEMPLATE_FILES)) {
      assert.ok(readFileSync(path.join(tree.dir, name)).includes(13), `${name} was written with CRLF`);
      const r = await runIn(['--print', kind], { scriptDir: tree.scriptDir });
      assert.equal(r.code, 0, `${kind}: ${r.stderr}`);
      assert.ok(r.stdout.equals(stripCr(readFileSync(path.join(TEMPLATE_DIR, name)))), `${kind} is the CR-stripped template bytes`);
      assert.equal(r.stderr, '');
      assert.deepEqual(r.calls, [], 'no git child for --print');
    }
    const bare = await runIn(['--print'], { scriptDir: tree.scriptDir });
    assert.ok(bare.stdout.equals(stripCr(readFileSync(path.join(TEMPLATE_DIR, TEMPLATE_FILES.index)))), 'bare --print is the index body');
    const { loadTemplates } = await import(MODULE_URL);
    const loaded = loadTemplates(tree.scriptDir, ['index', 'guard-checks']);
    assert.deepEqual(loaded.errors, []);
    assert.deepEqual(Object.keys(loaded.templates).sort(), ['guard-checks', 'index']);
    assert.ok(!loaded.templates.index.includes(13));
    // the default script directory is the module's own, never the working directory
    const own = loadTemplates(undefined, ['pre-push']);
    assert.ok(own.templates['pre-push'].equals(stripCr(readFileSync(path.join(TEMPLATE_DIR, 'pre-push.sh')))));
  });

  test('TEST-3985 every missing template is named with exit 1 and no hook is written', async () => {
    const tree = templateTree('tpl-missing-', (f) => { f['guard-checks'] = null; f['pre-push'] = null; f['ref-guard'] = null; });
    const p = await runIn(['--print', 'pre-push'], { scriptDir: tree.scriptDir });
    assert.equal(p.code, 1);
    assert.equal(p.stderr, `ERROR: AAI hook template missing: ${path.join(tree.dir, 'pre-push.sh')}\n`);
    assert.equal(p.stdout.length, 0);
    // an install in a scratch repository names each template the run needs, in order, before any write
    const root = scratch('tpl-missing-run-');
    const repo = gitScratch(root);
    const before = listTree(path.join(repo, '.git', 'hooks'));
    const first = await runInProcess(root, repo, [], { scriptDir: tree.scriptDir });
    assert.equal(first.code, 1);
    assert.equal(first.stderr, [
      `ERROR: AAI hook template missing: ${path.join(tree.dir, 'pre-commit-guard-checks.sh')}`,
      `ERROR: AAI hook template missing: ${path.join(tree.dir, 'reference-transaction.sh')}`,
      `ERROR: AAI hook template missing: ${path.join(tree.dir, 'pre-push.sh')}`,
      '',
    ].join('\n'));
    assert.deepEqual(listTree(path.join(repo, '.git', 'hooks')), before, 'nothing was written');
    // a template the run does not need is not required: uninstall and decline need none
    const bare = templateTree('tpl-none-', (f) => { for (const k of Object.keys(f)) f[k] = null; });
    const r2 = await runInProcess(root, repo, ['--uninstall'], { scriptDir: bare.scriptDir });
    assert.equal(r2.code, 0, r2.stderr);
    const r3 = await runInProcess(root, repo, ['--decline-ref-guard'], { scriptDir: bare.scriptDir });
    assert.equal(r3.code, 0, r3.stderr);
    // a decline needs no template, an arm needs the ref-guard one
    const r4 = await runInProcess(root, repo, ['--arm-ref-guard'], { scriptDir: bare.scriptDir });
    assert.equal(r4.code, 1);
    assert.ok(r4.stderr.includes(`ERROR: AAI hook template missing: ${path.join(bare.dir, 'reference-transaction.sh')}`));
  });

  test('TEST-3985 a malformed index or guard-checks template is refused per D-TEMPLATE', async () => {
    const indexMsg = (dir) => `ERROR: AAI hook template malformed (needs a first line and a second line): ${path.join(dir, 'pre-commit-index.sh')}\n`;
    const guardMsg = (dir) => `ERROR: AAI hook template malformed (needs one GUARD-CHECKS BEGIN line, then one END line, and a final newline): ${path.join(dir, 'pre-commit-guard-checks.sh')}\n`;
    const { loadTemplates } = await import(MODULE_URL);
    const index1 = templateTree('tpl-index1-', (f) => { f.index = '#!/bin/sh\n'; });
    assert.deepEqual(loadTemplates(index1.scriptDir, ['index']).errors, [indexMsg(index1.dir).trimEnd()]);
    const indexEmpty = templateTree('tpl-index0-', (f) => { f.index = ''; });
    assert.deepEqual(loadTemplates(indexEmpty.scriptDir, ['index']).errors, [indexMsg(indexEmpty.dir).trimEnd()]);
    const indexTwo = templateTree('tpl-index2-', (f) => { f.index = '#!/bin/sh\necho second'; });
    assert.deepEqual(loadTemplates(indexTwo.scriptDir, ['index']).errors, [], 'two lines, the last without a newline, are enough');
    const BEGIN = '# AAI:GUARD-CHECKS BEGIN';
    const END = '# AAI:GUARD-CHECKS END';
    const shapes = {
      'no END': `${BEGIN}\necho x\n`,
      'no BEGIN': `echo x\n${END}\n`,
      'END above BEGIN': `${END}\necho x\n${BEGIN}\n`,
      'no final newline': `${BEGIN}\necho x\n${END}`,
      'two BEGIN': `${BEGIN}\n${BEGIN}\necho x\n${END}\n`,
      'two END': `${BEGIN}\necho x\n${END}\n${END}\n`,
      empty: '',
    };
    for (const [name, text] of Object.entries(shapes)) {
      const tree = templateTree('tpl-guard-', (f) => { f['guard-checks'] = text; });
      // templateTree wrote CRLF text; the missing-final-newline shape has no newline at all after END
      const r = await runIn(['--print', 'guard-checks'], { scriptDir: tree.scriptDir });
      assert.equal(r.code, 1, name);
      assert.equal(r.stderr, guardMsg(tree.dir), name);
      assert.equal(r.stdout.length, 0, name);
    }
    const ok = templateTree('tpl-guard-ok-', (f) => { f['guard-checks'] = `${BEGIN}\necho x\n${END}\n`; });
    assert.equal((await runIn(['--print', 'guard-checks'], { scriptDir: ok.scriptDir })).code, 0);
    // the index run checks both; the other kinds are not checked for markers
    const noMarkers = templateTree('tpl-pp-', (f) => { f['pre-push'] = 'x'; f['ref-guard'] = 'y'; });
    assert.equal((await runIn(['--print', 'pre-push'], { scriptDir: noMarkers.scriptDir })).stdout.toString(), 'x');
    assert.equal((await runIn(['--print', 'ref-guard'], { scriptDir: noMarkers.scriptDir })).stdout.toString(), 'y');
  });

  test('TEST-3985 --print and every kind work outside a repository and equal the CR-stripped template bytes', () => {
    const root = scratch('tpl-print-');
    const empty = path.join(root, 'notrepo');
    mkdirSync(empty);
    for (const [kind, name] of Object.entries(TEMPLATE_FILES)) {
      const r = runInstaller({ args: ['--print', kind], root, cwd: empty });
      assert.equal(r.status, 0, r.stderr);
      assert.equal(r.stdout, stripCr(readFileSync(path.join(TEMPLATE_DIR, name))).toString('utf8'), `${kind} bytes`);
      assert.equal(r.stderr, '');
    }
    const bare = runInstaller({ args: ['--print'], root, cwd: empty });
    assert.equal(bare.status, 0);
    assert.equal(bare.stdout, stripCr(readFileSync(path.join(TEMPLATE_DIR, TEMPLATE_FILES.index))).toString());
  });

  test('TEST-3985 composePreCommit is the index first line, the guard block, the index rest and one final LF', async () => {
    const { composePreCommit } = await import(MODULE_URL);
    const b = (s) => Buffer.from(s);
    assert.equal(composePreCommit(b('#!/bin/sh\necho a\necho b\n'), b('# G BEGIN\nx\n# G END\n')).toString(), '#!/bin/sh\n# G BEGIN\nx\n# G END\necho a\necho b\n');
    assert.equal(composePreCommit(b('#!/bin/sh\necho a'), b('# G BEGIN\n# G END\n')).toString(), '#!/bin/sh\n# G BEGIN\n# G END\necho a\n', 'an index template without a final LF gets one');
    assert.equal(composePreCommit(b('#!/bin/sh\n\n'), b('G\n')).toString(), '#!/bin/sh\nG\n\n');
    const idx = readFileSync(path.join(TEMPLATE_DIR, TEMPLATE_FILES.index));
    const guard = readFileSync(path.join(TEMPLATE_DIR, TEMPLATE_FILES['guard-checks']));
    const composed = composePreCommit(stripCr(idx), stripCr(guard));
    const first = idx.indexOf(10) + 1;
    assert.ok(composed.subarray(0, first).equals(idx.subarray(0, first)));
    assert.ok(composed.subarray(first, first + guard.length).equals(guard));
    assert.equal(composed[composed.length - 1], 10);
  });

  test('TEST-3985 the composed hooks are byte-equal to what the frozen bash reference writes for the shipped templates and for an index without a final LF', async () => {
    const { composePreCommit, loadTemplates } = await import(MODULE_URL);
    for (const variant of ['shipped', 'no-final-lf']) {
      const root = scratch('tpl-bash-');
      const dests = materializeHookInstallerReference(ROOT, path.join(root, 'ref'));
      const tplDir = path.join(root, 'ref', '.aai', 'templates', 'git-hooks');
      if (variant === 'no-final-lf') {
        const f = path.join(tplDir, TEMPLATE_FILES.index);
        writeFileSync(f, readFileSync(f, 'utf8').replace(/\n+$/, ''));
      }
      const repo = gitScratch(root);
      const r = runInstaller({ args: [], root, cwd: repo, script: dests.sh });
      assert.equal(r.status, 0, r.stderr);
      const loaded = loadTemplates(path.join(root, 'ref', '.aai', 'scripts'), ['index', 'guard-checks', 'ref-guard', 'pre-push']);
      assert.deepEqual(loaded.errors, []);
      const want = composePreCommit(loaded.templates.index, loaded.templates['guard-checks']);
      assert.ok(readFileSync(hookOf(repo, 'pre-commit')).equals(want), `${variant}: pre-commit bytes`);
      assert.equal(want[want.length - 1], 10);
      assert.ok(readFileSync(hookOf(repo, 'reference-transaction')).equals(loaded.templates['ref-guard']), `${variant}: reference-transaction bytes`);
      assert.ok(readFileSync(hookOf(repo, 'pre-push')).equals(loaded.templates['pre-push']), `${variant}: pre-push bytes`);
      // and the module itself writes the same bytes from the same templates
      const repo2 = gitScratch(root, 'repo2');
      const m = await runInProcess(root, repo2, [], { scriptDir: path.join(root, 'ref', '.aai', 'scripts') });
      assert.equal(m.code, 0, m.stderr);
      for (const name of ['pre-commit', 'reference-transaction', 'pre-push']) {
        assert.ok(readFileSync(hookOf(repo2, name)).equals(readFileSync(hookOf(repo, name))), `${variant}: the module writes the bash bytes of ${name}`);
      }
    }
  });
});

// --- run 3 helpers: scratch repositories, snapshots and the in-process runner --------------------------------

const S3_NAMES = { index: 'pre-commit', 'ref-guard': 'reference-transaction', 'close-gate': 'pre-push' };
const S3_SLOTS = ['pre-commit', 'reference-transaction', 'pre-push'];
const S3_MARKER = { 'pre-commit': '# AAI:INDEX-AUTOGEN', 'reference-transaction': '# AAI:REF-GUARD', 'pre-push': '# AAI:CLOSE-GATE' };
const S3_BEGIN = '# AAI:GUARD-CHECKS BEGIN';
const S3_END = '# AAI:GUARD-CHECKS END';
const WHOLE_RUN = 'ERROR: refusing the whole run — nothing was written. Fix the slot(s) named above and re-run.\n';

const gitOut = (cwd, root, ...args) => {
  const r = spawnSync('git', args, { cwd, env: prepareEnv(root), encoding: 'utf8' });
  assert.equal(r.status, 0, `git ${args.join(' ')}: ${r.stderr}`);
  return r.stdout.replace(/\n+$/, '');
};
const gitSet = (repo, root, key, value) => gitOut(repo, root, 'config', key, value);
const gitCommit = (repo, root) => gitOut(repo, root, '-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-q', '--allow-empty', '-m', 'init');

// snapshot(dir): every path under dir with its type, mode and bytes (links by target), to prove a run changed nothing.
function snapshot(dir) {
  const out = {};
  for (const rel of readdirSync(dir, { recursive: true }).map(String).sort()) {
    const p = path.join(dir, rel);
    const l = lstatSync(p);
    if (l.isSymbolicLink()) out[rel] = `link:${readlinkSync(p)}`;
    else if (l.isDirectory()) out[rel] = 'dir';
    else if (l.isFile()) out[rel] = `file:${(l.mode & 0o777).toString(8)}:${readFileSync(p).toString('base64')}`;
    else out[rel] = `other:${l.mode}`;
  }
  return out;
}

const hooksDirOf = (repo) => path.join(repo, '.git', 'hooks');
const slotAt = (repo, name) => path.join(hooksDirOf(repo), name);
const shippedGuard = () => Buffer.from(readFileSync(path.join(TEMPLATE_DIR, 'pre-commit-guard-checks.sh')).filter((b) => b !== 13));
const shippedTemplate = (kind) => Buffer.from(readFileSync(path.join(TEMPLATE_DIR, TEMPLATE_FILES[kind])).filter((b) => b !== 13));
async function shippedPreCommit() {
  const { composePreCommit } = await import(MODULE_URL);
  return composePreCommit(shippedTemplate('index'), shippedTemplate('guard-checks'));
}

// runInProcess(root, cwd, argv, extra): the one way these tests run the module's run() in this process against a real
// repository: the isolated git environment, the cwd and the hooks path git resolves asserted under the scratch root
// BEFORE the run, and every hook that exists after it asserted under the root too. stdout and stderr are collected.
async function runInProcess(root, cwd, argv, extra = {}) {
  const { run } = await import(MODULE_URL);
  const out = [];
  const err = [];
  const env = prepareEnv(root);
  assertHooksUnderRoot(cwd, root, env);
  const code = await run(argv, { out: (x) => out.push(x), err: (x) => err.push(x), cwd, env, ...extra });
  const hooks = spawnSync('git', ['rev-parse', '--git-path', 'hooks'], { cwd, env, encoding: 'utf8' });
  if (hooks.status === 0) assert.ok(under(path.resolve(cwd, hooks.stdout.trim()), root), 'the hooks directory lies under the scratch root after the run');
  return { code, stdout: out.join(''), stderr: err.join('') };
}
const runMod = runInProcess;

// --- TEST-3986: ---------------------------------------------------------------------------------------------

const lstatOrNull = (p) => lstatSync(p, { throwIfNoEntry: false }) ?? null;
const gitHookPath = (cwd, root, name) => path.resolve(cwd, gitOut(cwd, root, 'rev-parse', '--git-path', `hooks/${name}`));

function expectHooksAt(cwd, root, label) {
  const r = runInstaller({ root, cwd });
  assert.equal(r.status, 0, `${label}: ${r.stderr}`);
  for (const name of S3_SLOTS) {
    const p = gitHookPath(cwd, root, name);
    assert.ok(under(p, root), `${label}: ${name} resolves under the scratch root`);
    assert.ok(lstatSync(p).isFile(), `${label}: ${name} landed where git resolves it (${p})`);
    assert.ok(readFileSync(p, 'latin1').includes(S3_MARKER[name]), `${label}: ${name} carries its marker`);
    assert.ok((statSync(p).mode & 0o100) !== 0, `${label}: ${name} is executable`);
    // the message path is the base directory joined to git's answer without normalising (DR-20, the bash $PWD/$p)
    const raw = gitOut(cwd, root, 'rev-parse', '--git-path', `hooks/${name}`);
    const shown = path.isAbsolute(raw) ? raw : `${cwd}/${raw}`;
    assert.ok(r.stdout.includes(` at ${shown}\n`), `${label}: the Installed line names ${shown}`);
  }
  return r;
}

describe('TEST-3986 slot paths come from git itself', () => {
  test('TEST-3986 an environment-injected core.hooksPath neither reaches the module nor lands a hook outside the scratch root', async () => {
    const root = scratch('paths-envinject-');
    const victim = path.join(root, 'victim');
    mkdirSync(victim);
    const saved = {};
    const inject = { GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'core.hooksPath', GIT_CONFIG_VALUE_0: victim, GIT_CONFIG_PARAMETERS: `'core.hooksPath=${victim}'`, GIT_COMMON_DIR: victim };
    for (const k of Object.keys(inject)) saved[k] = process.env[k];
    Object.assign(process.env, inject);
    try {
      const env = prepareEnv(root);
      for (const k of Object.keys(inject)) assert.ok(!(k in env), `${k} is scrubbed`);
      const repo = gitScratch(root);
      const r = await runInProcess(root, repo, []);
      assert.equal(r.code, 0, r.stderr);
      assert.deepEqual(listTree(victim), [], 'nothing landed in the injected hooks path');
      assert.ok(lstatSync(path.join(repo, '.git', 'hooks', 'pre-commit')).isFile(), 'the hook landed in the repository');
    } finally {
      for (const k of Object.keys(inject)) { if (saved[k] === undefined) delete process.env[k]; else process.env[k] = saved[k]; }
    }
  });

  test('TEST-3986 hooksPath unset, relative and not yet existing, absolute: the hooks land where git resolves them', () => {
    const unset = scratch('paths-unset-');
    expectHooksAt(gitScratch(unset), unset, 'unset');
    const rel = scratch('paths-rel-');
    const relRepo = gitScratch(rel);
    gitSet(relRepo, rel, 'core.hooksPath', '.custom-hooks');
    assert.ok(!existsSync(path.join(relRepo, '.custom-hooks')), 'the relative hooks directory does not exist yet');
    expectHooksAt(relRepo, rel, 'relative and missing');
    assert.ok(lstatSync(path.join(relRepo, '.custom-hooks', 'pre-commit')).isFile());
    assert.ok(!existsSync(path.join(relRepo, '.git', 'hooks', 'pre-commit')), 'nothing was written to the default directory');
    const abs = scratch('paths-abs-');
    const absRepo = gitScratch(abs);
    gitSet(absRepo, abs, 'core.hooksPath', path.join(abs, 'elsewhere', 'hooks'));
    expectHooksAt(absRepo, abs, 'absolute and missing');
    assert.ok(lstatSync(path.join(abs, 'elsewhere', 'hooks', 'reference-transaction')).isFile());
  });

  test('TEST-3986 a subdirectory cwd resolves a relative answer against the base directory', () => {
    const root = scratch('paths-sub-');
    const repo = gitScratch(root);
    gitSet(repo, root, 'core.hooksPath', '.custom-hooks');
    const sub = path.join(repo, 'a', 'b');
    mkdirSync(sub, { recursive: true });
    expectHooksAt(sub, root, 'subdirectory with relative hooksPath');
    assert.ok(lstatSync(path.join(repo, '.custom-hooks', 'pre-push')).isFile(), 'the hooks sit at the root of the repository');
    assert.ok(!existsSync(path.join(sub, '.custom-hooks')), 'nothing was written below the subdirectory');
    const root2 = scratch('paths-sub2-');
    const repo2 = gitScratch(root2);
    const sub2 = path.join(repo2, 'x');
    mkdirSync(sub2);
    expectHooksAt(sub2, root2, 'subdirectory with the default path');
  });

  test('TEST-3986 a linked worktree installs into the shared git directory, or a per-worktree hooksPath', () => {
    const root = scratch('paths-wt-');
    const repo = gitScratch(root);
    gitCommit(repo, root);
    const wt = path.join(root, 'wt');
    gitOut(repo, root, 'worktree', 'add', '-q', wt, '-b', 'other');
    assert.ok(lstatSync(path.join(wt, '.git')).isFile(), 'a linked worktree has a .git file');
    expectHooksAt(wt, root, 'linked worktree');
    assert.ok(lstatSync(path.join(repo, '.git', 'hooks', 'pre-commit')).isFile(), 'the hooks sit in the common git directory');
    const root2 = scratch('paths-wt2-');
    const repo2 = gitScratch(root2);
    gitCommit(repo2, root2);
    gitSet(repo2, root2, 'core.hooksPath', '.c');
    const wt2 = path.join(root2, 'wt');
    gitOut(repo2, root2, 'worktree', 'add', '-q', wt2, '-b', 'other');
    expectHooksAt(wt2, root2, 'linked worktree with a relative hooksPath');
  });

  test('TEST-3986 outside a repository the bash line and exit 1; with git unable to start the DR-8 line and exit 1', async () => {
    const root = scratch('paths-none-');
    const plain = path.join(root, 'plain');
    mkdirSync(plain);
    const before = snapshot(root);
    const r = runInstaller({ root, cwd: plain });
    assert.equal(r.status, 1);
    assert.equal(r.stderr, 'ERROR: not inside a git repository.\n');
    assert.equal(r.stdout, '');
    const noGit = runInstaller({ root, cwd: plain, env: { PATH: path.join(root, 'no-such-bin') } });
    assert.equal(noGit.status, 1);
    assert.equal(noGit.stderr, 'ERROR: git was not found on PATH.\n');
    const repo = gitScratch(root);
    const calls = [];
    const injected = await runMod(root, repo, [], { spawn: (file, args) => { calls.push([file, args]); return { error: new Error('spawn git ENOENT'), status: null, stdout: '', stderr: '' }; } });
    assert.equal(injected.code, 1);
    assert.equal(injected.stderr, 'ERROR: git was not found on PATH.\n');
    assert.deepEqual(calls.map((c) => c[0]), ['git'], 'git is asked once');
    assert.ok(!existsSync(path.join(repo, '.git', 'hooks', 'pre-commit')));
    // the files of the plain directory and the injected run are unchanged
    assert.deepEqual(Object.keys(before).filter((k) => k.startsWith('plain')), ['plain']);
  });

  test('TEST-3986 a failing git-path answer for a slot refuses with the bash three lines and writes nothing', async () => {
    const root = scratch('paths-fail-');
    const repo = gitScratch(root);
    const before = snapshot(repo);
    const wants = {
      'pre-commit': ['ERROR: could not resolve the effective git hooks path for pre-commit', '       (git rev-parse --git-path failed). Refusing to install: a hook', '       written to a guessed path would report success while git never runs it.'],
      'reference-transaction': ['ERROR: could not resolve the effective git hooks path for reference-transaction', '       (git rev-parse --git-path failed). Refusing to install: a guard', '       written to a guessed path would report success while git never runs it.'],
      'pre-push': ['ERROR: could not resolve the effective git hooks path for pre-push', '       (git rev-parse --git-path failed). Refusing to install: a guard', '       written to a guessed path would report success while git never runs it.'],
    };
    for (const name of S3_SLOTS) {
      const spawn = (file, args, opts) => (args.includes('--git-path') && args.includes(`hooks/${name}`) ? { status: 128, stdout: '', stderr: 'fatal' } : spawnSync(file, args, opts));
      const r = await runMod(root, repo, [], { spawn });
      assert.equal(r.code, 1, name);
      assert.equal(r.stderr, `${wants[name].join('\n')}\n`, name);
      assert.equal(r.stdout, '');
      assert.deepEqual(snapshot(repo), before, `${name}: nothing was written`);
    }
    const empty = (file, args, opts) => (args.includes('--git-path') ? { status: 0, stdout: '\n', stderr: '' } : spawnSync(file, args, opts));
    const e = await runMod(root, repo, [], { spawn: empty });
    assert.equal(e.code, 1);
    assert.ok(e.stderr.startsWith(wants['pre-commit'][0]), 'an empty answer is a failure too');
  });

  test('TEST-3986 message paths are built from PWD when it names the working directory', () => {
    const root = scratch('paths-pwd-');
    const repo = gitScratch(root);
    const link = path.join(root, 'link');
    symlinkSync(repo, link);
    const r = runInstaller({ root, cwd: link, env: { PWD: link } });
    assert.equal(r.status, 0, r.stderr);
    assert.ok(r.stdout.includes(`Installed AAI pre-commit hook at ${link}/.git/hooks/pre-commit\n`), r.stdout);
    assert.ok(readFileSync(path.join(repo, '.git', 'hooks', 'pre-commit')).length > 0, 'the hook is in the real repository');
    const other = scratch('paths-pwd2-');
    const repo2 = gitScratch(other);
    const r2 = runInstaller({ root: other, cwd: repo2, env: { PWD: root } });
    assert.equal(r2.status, 0, r2.stderr);
    assert.ok(r2.stdout.includes(`Installed AAI pre-commit hook at ${repo2}/.git/hooks/pre-commit\n`), 'a PWD that is not the cwd is ignored');
  });
});

// --- TEST-3987: ---------------------------------------------------------------------------------------------

function s3File(root, name, content) {
  const p = path.join(root, name);
  writeFileSync(p, content);
  return p;
}

describe('TEST-3987 slot states and the whole-run refusal', () => {
  test('TEST-3987 the marker rule works on bytes: a column-0 marker followed by a space, LF, the end or a CR before LF or the end', async () => {
    const { hasMarkerLine } = await import(MODULE_URL);
    const M = '# AAI:REF-GUARD';
    const yes = [`${M}\n`, `${M} — x\n`, `x\n${M}`, `${M}\r\n`, `${M}\r`, `#!/bin/sh\n${M}\nrest\n`];
    const no = [`echo "${M}"\n`, `  ${M}\n`, `# see ${M}\n`, `${M}x\n`, `${M}\r x\n`, `${M}\rx\n`, `${M.toLowerCase()}\n`, `${M.slice(0, -1)}\n`];
    for (const t of yes) assert.equal(hasMarkerLine(Buffer.from(t), M), true, JSON.stringify(t));
    for (const t of no) assert.equal(hasMarkerLine(Buffer.from(t), M), false, JSON.stringify(t));
  });

  test('TEST-3987 classifySlot gives every D-SLOT state for crafted slots', async (t) => {
    const { classifySlot } = await import(MODULE_URL);
    const root = scratch('classify-');
    const guard = shippedGuard();
    const refTpl = shippedTemplate('ref-guard');
    const at = (n) => path.join(root, n);
    const IDX = S3_MARKER['pre-commit'];
    const preCommit = (extra) => Buffer.from(`#!/bin/sh\n${IDX} — x\n${extra}`, 'utf8');
    assert.deepEqual(classifySlot(at('missing'), IDX, guard), { state: 'absent' });
    // foreign: no marker line, a marker only in a comment, a marker followed by CR and a space
    assert.equal(classifySlot(s3File(root, 'f1', '#!/bin/sh\necho hi\n'), IDX, guard).state, 'foreign');
    assert.equal(classifySlot(s3File(root, 'f2', `#!/bin/sh\n# note: ${IDX}\n`), IDX, guard).state, 'foreign');
    assert.equal(classifySlot(s3File(root, 'f3', `${S3_MARKER['reference-transaction']}\r x\n`), S3_MARKER['reference-transaction'], refTpl).state, 'foreign');
    // reference-transaction and pre-push: current or marked-differs
    assert.equal(classifySlot(s3File(root, 'r1', refTpl), S3_MARKER['reference-transaction'], refTpl).state, 'current');
    assert.equal(classifySlot(s3File(root, 'r2', Buffer.concat([refTpl, Buffer.from('# local\n')])), S3_MARKER['reference-transaction'], refTpl).state, 'marked-differs');
    assert.equal(classifySlot(s3File(root, 'r3', `${S3_MARKER['pre-push']} — hand merged\n`), S3_MARKER['pre-push'], shippedTemplate('pre-push')).state, 'marked-differs');
    // pre-commit: current, older (insert and refresh), unprovable
    assert.equal(classifySlot(s3File(root, 'p1', await shippedPreCommit()), IDX, guard).state, 'current');
    assert.equal(classifySlot(s3File(root, 'p2', preCommit('echo old\n')), IDX, guard).state, 'older');
    const stale = Buffer.from(`#!/bin/sh\n${S3_BEGIN}\nold interior\n${S3_END}\n${IDX}\n`);
    assert.equal(classifySlot(s3File(root, 'p3', stale), IDX, guard).state, 'older');
    const unprovable = {
      bom: Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), preCommit('x\n')]),
      'no-newline': Buffer.from(IDX),
      'cr-first': Buffer.from(`#!/bin/sh\r\n${IDX}\n`),
      'stray-end': preCommit(`${S3_END}\n`),
      count: Buffer.from(`#!/bin/sh\n${IDX}\n${S3_BEGIN}\na\n${S3_END}\n${S3_BEGIN}\nb\n${S3_END}\n`),
      inverted: Buffer.from(`#!/bin/sh\n${IDX}\n${S3_END}\n${S3_BEGIN}\n`),
    };
    for (const [why, bytes] of Object.entries(unprovable)) {
      const c = classifySlot(s3File(root, `u-${why}`, bytes), IDX, guard);
      assert.equal(c.state, 'unprovable', why);
      assert.equal(c.plan.refuse, why, why);
    }
    // link-file: classified by the target, never written through
    symlinkSync(at('r1'), at('l1'));
    const l1 = classifySlot(at('l1'), S3_MARKER['reference-transaction'], refTpl);
    assert.equal(l1.state, 'link-file');
    assert.equal(l1.inner.state, 'current');
    symlinkSync(at('p2'), at('l2'));
    assert.equal(classifySlot(at('l2'), IDX, guard).inner.state, 'older');
    symlinkSync(at('f1'), at('l3'));
    assert.equal(classifySlot(at('l3'), IDX, guard).inner.state, 'foreign');
    // bad-type: a directory, a dangling link, a link to a directory, a pipe, a socket
    mkdirSync(at('d1'));
    assert.deepEqual(classifySlot(at('d1'), IDX, guard), { state: 'bad-type', kind: 'a directory' });
    symlinkSync(at('nowhere'), at('l4'));
    assert.deepEqual(classifySlot(at('l4'), IDX, guard), { state: 'bad-type', kind: 'dangling' });
    symlinkSync(at('d1'), at('l5'));
    assert.deepEqual(classifySlot(at('l5'), IDX, guard), { state: 'bad-type', kind: 'link-dir' });
    if (process.platform !== 'win32') {
      assert.equal(spawnSync('mkfifo', [at('q1')]).status, 0);
      assert.deepEqual(classifySlot(at('q1'), IDX, guard), { state: 'bad-type', kind: 'a named pipe' });
      const sock = path.join(root, 's');
      const server = net.createServer();
      try {
        await new Promise((resolve, reject) => { server.once('error', reject); server.listen(sock, resolve); });
        assert.deepEqual(classifySlot(sock, IDX, guard), { state: 'bad-type', kind: 'a socket' });
      } catch (e) {
        if (e.code !== 'ENAMETOOLONG' && e.code !== 'EINVAL') throw e;
        t.diagnostic(`socket case skipped: ${e.code}`);
      } finally {
        server.close();
      }
    }
  });

  test('TEST-3987 a declined unforced reference-transaction slot is neither classified nor written; the other slots install', () => {
    const kinds = ['foreign', 'dir', 'dangling'];
    for (const kind of kinds) {
      const root = scratch(`declined-${kind}-`);
      const repo = gitScratch(root);
      mkdirSync(path.join(repo, 'docs', 'ai'), { recursive: true });
      writeFileSync(path.join(repo, 'docs', 'ai', 'docs-audit.yaml'), 'ref_guard: declined\n');
      mkdirSync(hooksDirOf(repo), { recursive: true });
      const slot = slotAt(repo, 'reference-transaction');
      if (kind === 'foreign') writeFileSync(slot, '#!/bin/sh\necho mine\n');
      else if (kind === 'dir') mkdirSync(slot);
      else symlinkSync(path.join(root, 'nowhere'), slot);
      const before = snapshot(slot === '' ? repo : path.dirname(slot));
      const r = runInstaller({ root, cwd: repo });
      assert.equal(r.status, 0, `${kind}: ${r.stderr}`);
      assert.ok(r.stdout.includes('Skipped AAI reference-transaction hook (AAI:REF-GUARD)'), kind);
      assert.ok(lstatSync(slotAt(repo, 'pre-commit')).isFile() && lstatSync(slotAt(repo, 'pre-push')).isFile(), `${kind}: the other two slots install`);
      const after = snapshot(path.dirname(slot));
      for (const [k, v] of Object.entries(before)) assert.equal(after[k], v, `${kind}: ${k} is unchanged`);
    }
  });

  // The expected refusal lines of one slot, written out from the bash reference.
  const foreignLines = (name, p, repo) => {
    if (name === 'pre-commit') {
      return [`ERROR: ${p} already exists and is not AAI-managed.`, '       Pass --force to overwrite, or merge the snippets manually:',
        `       ${repo}/.aai/scripts/install-pre-commit-hook.sh --print               # the AAI:INDEX-AUTOGEN body`,
        `       ${repo}/.aai/scripts/install-pre-commit-hook.sh --print guard-checks  # the AAI:GUARD-CHECKS block (put it first)`];
    }
    const [marker, kind] = name === 'reference-transaction' ? ['AAI:REF-GUARD', 'ref-guard'] : ['AAI:CLOSE-GATE', 'pre-push'];
    return [`ERROR: ${p} already exists and is not AAI-managed.`, `       Pass --force to overwrite, or merge the ${marker} body with: ${repo}/.aai/scripts/install-pre-commit-hook.sh --print ${kind}`];
  };
  const badLines = (name, p, kind) => {
    if (kind === 'linkdir') return [`ERROR: ${name} slot ${p} is a symbolic link to a directory. Nothing was written: following it would drop the hook body inside that directory, possibly outside this repository. Replace the link with a regular file, or remove it, then re-run.`];
    if (kind === 'dangling') return [`ERROR: ${name} slot ${p} is a dangling symbolic link. Nothing was written: following it would create a file at a target this repository does not own. Remove the link, then re-run.`];
    const what = { dir: 'a directory', fifo: 'a named pipe' }[kind];
    return [`ERROR: ${name} slot ${p} is ${what}, not a regular file. Nothing was written and the slot is untouched. Remove or rename it, then re-run.`];
  };
  const IDXM = S3_MARKER['pre-commit'];
  const unprovableCases = {
    bom: [Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(`#!/bin/sh\n${IDXM}\n`)]), (p) => `ERROR: ${p} starts with a UTF-8 byte-order mark (EF BB BF); sh cannot start a hook whose first bytes are not '#!', so the AAI:GUARD-CHECKS block is not inserted into it. File left as it was. Strip the BOM, or pass --force to rewrite the whole slot.`],
    'no-newline': [Buffer.from(IDXM), (p) => `ERROR: ${p} has no newline-terminated line; refusing to insert the AAI:GUARD-CHECKS block into it. Pass --force to rewrite the whole slot.`],
    'cr-first': [Buffer.from(`#!/bin/sh\r\n${IDXM}\n`), (p) => `ERROR: ${p} has a CR-terminated first line (CRLF hook). Refusing to insert an LF block under it — sh could not start the result. Convert the hook to LF, or pass --force to rewrite the whole slot.`],
    'stray-end': [Buffer.from(`#!/bin/sh\n${IDXM}\n${S3_END}\n`), (p) => `ERROR: ${p} carries 1 '${S3_END}' line(s) and no '${S3_BEGIN}'; refusing to insert a block above a stray END marker. File left as it was. Remove the END line by hand, or pass --force to rewrite the whole slot.`],
    count: [Buffer.from(`#!/bin/sh\n${IDXM}\n${S3_BEGIN}\n${S3_BEGIN}\n${S3_END}\n`), (p) => `ERROR: ${p} carries 2 '${S3_BEGIN}' and 1 '${S3_END}' line(s); refusing to guess which block is the installer's. File left as it was. Remove the extra markers by hand, or pass --force to rewrite the whole slot.`],
    inverted: [Buffer.from(`#!/bin/sh\n${IDXM}\n${S3_END}\n${S3_BEGIN}\n`), (p) => `ERROR: ${p} carries '${S3_END}' (line 3) BEFORE '${S3_BEGIN}' (line 4): the markers are inverted, so no interior can be located and a refresh would drop every line after the BEGIN. File left as it was. Move the BEGIN line above the END line by hand, or pass --force to rewrite the whole slot.`],
  };

  // place(repo, root, name, kind): the crafted slot; returns false when the kind cannot be made here.
  function place(repo, root, name, kind) {
    mkdirSync(hooksDirOf(repo), { recursive: true });
    const p = slotAt(repo, name);
    if (kind === 'foreign') writeFileSync(p, '#!/bin/sh\necho mine\n');
    else if (kind === 'dir') mkdirSync(p);
    else if (kind === 'dangling') symlinkSync(path.join(root, 'nowhere'), p);
    else if (kind === 'linkdir') { mkdirSync(path.join(root, 'tgt')); symlinkSync(path.join(root, 'tgt'), p); }
    else if (kind === 'fifo') { if (process.platform === 'win32' || spawnSync('mkfifo', [p]).status !== 0) return false; }
    else if (kind === 'link-older') { const t = path.join(root, 'older-target'); writeFileSync(t, `#!/bin/sh\n${IDXM}\n`); symlinkSync(t, p); }
    else writeFileSync(p, unprovableCases[kind][0]);
    return true;
  }
  const expectedFor = (name, kind, p, repo) => {
    if (kind === 'foreign') return { lines: foreignLines(name, p, repo), foreign: true };
    if (kind === 'link-older') return { lines: [`ERROR: ${p} is a symlink. Refusing to rewrite through a symlink (the target may be outside this repository); replace the link with a regular file, or pass --force.`], foreign: false };
    if (unprovableCases[kind]) return { lines: [unprovableCases[kind][1](p)], foreign: false };
    return { lines: badLines(name, p, kind), foreign: false };
  };

  test('TEST-3987 each refusal kind in each slot prints its bash lines, exits 1 and leaves the tree byte-identical', () => {
    const all = ['foreign', 'dir', 'dangling', 'linkdir', 'fifo'];
    for (const name of S3_SLOTS) {
      const kinds = name === 'pre-commit' ? [...all, ...Object.keys(unprovableCases), 'link-older'] : all;
      for (const kind of kinds) {
        const root = scratch(`refuse-${kind}-`);
        const repo = gitScratch(root);
        if (!place(repo, root, name, kind)) continue;
        const before = snapshot(root);
        const r = runInstaller({ root, cwd: repo });
        const want = expectedFor(name, kind, slotAt(repo, name), repo);
        assert.equal(r.status, 1, `${name} ${kind}`);
        assert.equal(r.stdout, '', `${name} ${kind}: nothing on stdout`);
        assert.equal(r.stderr, `${want.lines.join('\n')}\n${want.foreign ? '' : WHOLE_RUN}`, `${name} ${kind}`);
        assert.deepEqual(snapshot(root), before, `${name} ${kind}: the tree is byte-identical`);
        assert.ok(!existsSync(path.join(repo, 'docs')), `${name} ${kind}: no policy line or config created`);
      }
    }
  });

  test('TEST-3987 two and three refusals at once print in slot order pre-commit, reference-transaction, pre-push', () => {
    const root = scratch('refuse-many-');
    const repo = gitScratch(root);
    place(repo, root, 'pre-commit', 'foreign');
    place(repo, root, 'pre-push', 'dir');
    const before = snapshot(root);
    const r = runInstaller({ root, cwd: repo });
    assert.equal(r.status, 1);
    const want = [...foreignLines('pre-commit', slotAt(repo, 'pre-commit'), repo), ...badLines('pre-push', slotAt(repo, 'pre-push'), 'dir')];
    assert.equal(r.stderr, `${want.join('\n')}\n${WHOLE_RUN}`);
    assert.deepEqual(snapshot(root), before);
    const root3 = scratch('refuse-three-');
    const repo3 = gitScratch(root3);
    place(repo3, root3, 'pre-commit', 'bom');
    place(repo3, root3, 'reference-transaction', 'foreign');
    place(repo3, root3, 'pre-push', 'dangling');
    const before3 = snapshot(root3);
    const r3 = runInstaller({ root: root3, cwd: repo3 });
    const want3 = [unprovableCases.bom[1](slotAt(repo3, 'pre-commit')), ...foreignLines('reference-transaction', slotAt(repo3, 'reference-transaction'), repo3), ...badLines('pre-push', slotAt(repo3, 'pre-push'), 'dangling')];
    assert.equal(r3.status, 1);
    assert.equal(r3.stderr, `${want3.join('\n')}\n${WHOLE_RUN}`);
    assert.deepEqual(snapshot(root3), before3);
    // all foreign: every refusal, and no whole-run line
    const root4 = scratch('refuse-foreign-');
    const repo4 = gitScratch(root4);
    for (const name of S3_SLOTS) place(repo4, root4, name, 'foreign');
    const r4 = runInstaller({ root: root4, cwd: repo4 });
    assert.equal(r4.status, 1);
    assert.equal(r4.stderr, `${S3_SLOTS.flatMap((n) => foreignLines(n, slotAt(repo4, n), repo4)).join('\n')}\n`);
  });

  test('TEST-3987 --force replaces a foreign hook and a link, but never a directory, a dangling link or a pipe', () => {
    const root = scratch('refuse-force-');
    const repo = gitScratch(root);
    place(repo, root, 'pre-commit', 'foreign');
    place(repo, root, 'pre-push', 'link-older');
    const target = path.join(root, 'older-target');
    const targetBefore = readFileSync(target);
    const r = runInstaller({ root, cwd: repo, args: ['--force'] });
    assert.equal(r.status, 0, r.stderr);
    assert.ok(lstatSync(slotAt(repo, 'pre-push')).isFile(), 'the link itself was replaced by a regular file');
    assert.ok(readFileSync(target).equals(targetBefore), 'the link target was not written through');
    for (const kind of ['dir', 'dangling', 'fifo']) {
      const root2 = scratch(`refuse-force-${kind}-`);
      const repo2 = gitScratch(root2);
      if (!place(repo2, root2, 'reference-transaction', kind)) continue;
      const before = snapshot(root2);
      const r2 = runInstaller({ root: root2, cwd: repo2, args: ['--force'] });
      assert.equal(r2.status, 1, kind);
      assert.ok(r2.stderr.endsWith(WHOLE_RUN), kind);
      assert.deepEqual(snapshot(root2), before, `${kind}: untouched even with --force`);
    }
  });

  test('TEST-3987 a link to an installed hook that needs no write stays a link', async () => {
    const root = scratch('refuse-linkok-');
    const repo = gitScratch(root);
    mkdirSync(hooksDirOf(repo), { recursive: true });
    const real = path.join(root, 'shared-pre-commit');
    writeFileSync(real, await shippedPreCommit());
    chmodSync(real, 0o755);
    symlinkSync(real, slotAt(repo, 'pre-commit'));
    const r = runInstaller({ root, cwd: repo });
    assert.equal(r.status, 0, r.stderr);
    assert.ok(lstatSync(slotAt(repo, 'pre-commit')).isSymbolicLink(), 'the link is kept');
    assert.ok(r.stdout.includes(`AAI pre-commit hook already installed at ${slotAt(repo, 'pre-commit')}. No action taken.\n`));
  });
});

// --- TEST-3988 ---------------------------------------------------------------------------------------------

const landingLine = (name, p) => `ERROR: the ${name} hook was composed but did not land at ${p} — the bytes there are not the ones written (the slot may be a link or a directory). No hook was installed; any stray temporary file has been removed.\n`;
const strays = (dir) => readdirSync(dir, { recursive: true }).map(String).filter((f) => f.includes('.aai-tmp.'));

describe('TEST-3988 writes, upgrade, modes and attestation', () => {
  test('TEST-3988 a rename that lands the temp inside a directory, writes other bytes or leaves a link fails with the landing line and no temp or stray', async () => {
    const renames = {
      directory: (from, to) => { mkdirSync(to); renameSync(from, path.join(to, path.basename(from))); },
      'other bytes': (from, to) => { writeFileSync(to, 'something else\n'); rmSync(from); },
      link: (from, to) => { symlinkSync(from, to); },
    };
    for (const [label, rename] of Object.entries(renames)) {
      for (const failing of ['pre-commit', 'pre-push']) {
        const root = scratch('landing-');
        const repo = gitScratch(root);
        const calls = [];
        const r = await runMod(root, repo, [], { rename: (from, to) => { calls.push(to); return path.basename(to) === failing ? rename(from, to) : renameSync(from, to); } });
        const p = slotAt(repo, failing);
        assert.equal(r.code, 1, `${label} ${failing}`);
        assert.ok(r.stderr.includes(landingLine(failing, p)), `${label} ${failing}: ${r.stderr}`);
        assert.ok(calls.some((c) => c === p), 'the write went through io.rename');
        assert.deepEqual(strays(hooksDirOf(repo)), [], `${label} ${failing}: no temp or stray is left`);
        if (label === 'directory') assert.deepEqual(readdirSync(p), [], 'the directory holds no stray');
        assert.ok(!r.stdout.includes(`Installed AAI ${failing}`) && !r.stdout.includes('Uninstall with:'), `${label} ${failing}: no success line`);
      }
    }
  });

  test('TEST-3988 planUpgrade inserts after a shebang or at the top, refreshes only the interior and leaves a current hook', async () => {
    const { planUpgrade } = await import(MODULE_URL);
    const guard = shippedGuard();
    const IDX = `${S3_MARKER['pre-commit']} — x\n`;
    const sheb = Buffer.from(`#!/bin/sh\n${IDX}echo old\nno final lf`);
    const a = planUpgrade(sheb, guard);
    assert.equal(a.action, 'insert');
    assert.ok(a.bytes.equals(Buffer.concat([Buffer.from('#!/bin/sh\n'), guard, Buffer.from(`${IDX}echo old\nno final lf`)])));
    const bare = Buffer.from(`${IDX}echo old\n`);
    const b = planUpgrade(bare, guard);
    assert.equal(b.action, 'insert');
    assert.ok(b.bytes.equals(Buffer.concat([guard, bare])));
    const stale = Buffer.from(`#!/bin/sh\nlead\r\n${S3_BEGIN}\nold\n\n${S3_END}\n${IDX}tail without lf`);
    const c = planUpgrade(stale, guard);
    assert.equal(c.action, 'refresh');
    const interior = guard.toString('latin1').split('\n').slice(1, -2).join('\n') + '\n';
    assert.ok(c.bytes.equals(Buffer.from(`#!/bin/sh\nlead\r\n${S3_BEGIN}\n${interior}${S3_END}\n${IDX}tail without lf`)), 'only the interior changed');
    assert.deepEqual(planUpgrade(c.bytes, guard), { action: 'none' });
    assert.equal(planUpgrade(Buffer.from('#!/bin/sh\nx'), guard).refuse, undefined, 'a file with one newline is provable');
    assert.equal(planUpgrade(Buffer.from('x'), guard).refuse, 'no-newline');
    assert.equal(planUpgrade(Buffer.from(`${S3_BEGIN} extra\n`), guard).refuse, 'count', 'a BEGIN substring without an exact line counts as no block line');
  });

  test('TEST-3988 an upgrade of an older pre-commit hook equals the bash reference byte for byte and line for line', async () => {
    const guardBytes = shippedGuard().toString('latin1');
    const IDX = `${S3_MARKER['pre-commit']} — x\n`;
    const interior = guardBytes.split('\n').slice(1, -2).join('\n') + '\n';
    const cases = {
      'insert after shebang': `#!/bin/sh\n${IDX}echo old\n`,
      'insert at the top': `${IDX}echo old\n`,
      refresh: `#!/bin/sh\n${S3_BEGIN}\nstale\n${S3_END}\n${IDX}echo tail`,
      current: `#!/bin/sh\n${S3_BEGIN}\n${interior}${S3_END}\n${IDX}`,
      'current without final lf': `#!/bin/sh\n${S3_BEGIN}\n${interior}${S3_END}\n${IDX}echo x`,
      'stray end': `#!/bin/sh\n${IDX}${S3_END}\n`,
      inverted: `#!/bin/sh\n${IDX}${S3_END}\n${S3_BEGIN}\n`,
    };
    for (const [label, content] of Object.entries(cases)) {
      const root = scratch('upgrade-ref-');
      const dests = materializeHookInstallerReference(ROOT, path.join(root, 'ref'));
      const ours = gitScratch(root, 'ours');
      const theirs = gitScratch(root, 'theirs');
      for (const repo of [ours, theirs]) {
        mkdirSync(hooksDirOf(repo), { recursive: true });
        writeFileSync(slotAt(repo, 'pre-commit'), content);
        chmodSync(slotAt(repo, 'pre-commit'), 0o755);
      }
      const mine = runInstaller({ root, cwd: ours, args: ['--hooks', 'index'] });
      const bash = runInstaller({ root, cwd: theirs, script: dests.sh, args: ['--hooks', 'index'] });
      const norm = (txt, repo) => txt.split(repo).join('<R>');
      assert.equal(mine.status, bash.status, `${label}: exit code`);
      assert.equal(norm(mine.stdout, ours), norm(bash.stdout, theirs), `${label}: stdout`);
      // the module adds the whole-run line to a refusal that is not a foreign one (D-SLOT)
      assert.equal(norm(mine.stderr, ours).replace(WHOLE_RUN, ''), norm(bash.stderr, theirs), `${label}: stderr`);
      assert.ok(readFileSync(slotAt(ours, 'pre-commit')).equals(readFileSync(slotAt(theirs, 'pre-commit'))), `${label}: the hook bytes`);
    }
  });

  test('TEST-3988 a marked hook that differs is left unwritten with the NOTE line and replaced under --force', () => {
    for (const name of ['reference-transaction', 'pre-push']) {
      const root = scratch('differs-');
      const repo = gitScratch(root);
      const r0 = runInstaller({ root, cwd: repo });
      assert.equal(r0.status, 0, r0.stderr);
      const p = slotAt(repo, name);
      const shipped = readFileSync(p);
      const edited = Buffer.concat([shipped, Buffer.from('# hand merged\n')]);
      writeFileSync(p, edited);
      const r1 = runInstaller({ root, cwd: repo });
      assert.equal(r1.status, 0, r1.stderr);
      assert.ok(readFileSync(p).equals(edited), `${name}: not written`);
      const marker = S3_MARKER[name];
      const lines = r1.stdout.split('\n');
      const at = lines.indexOf(`AAI ${name} hook already installed at ${p}. No action taken.`);
      assert.ok(at >= 0, `${name}: the already installed line`);
      assert.equal(lines[at + 1], `NOTE: ${p} carries ${marker} but its bytes differ from the shipped body; pass --force to replace it.`);
      assert.ok(!r1.stdout.includes(`AAI pre-commit hook already installed at ${slotAt(repo, 'pre-commit')}. No action taken.\nNOTE`), 'a current hook gets no NOTE');
      const r2 = runInstaller({ root, cwd: repo, args: ['--force'] });
      assert.equal(r2.status, 0, r2.stderr);
      assert.ok(readFileSync(p).equals(shipped), `${name}: replaced under --force`);
    }
  });

  test('TEST-3988 new hooks get mode 0777 minus umask under umask 022 and 077', { skip: process.platform === 'win32' }, () => {
    for (const [umask, want] of [['022', 0o755], ['077', 0o700]]) {
      const root = scratch('mode-');
      const repo = gitScratch(root);
      const r = runInstaller({ root, cwd: repo, umask });
      assert.equal(r.status, 0, r.stderr);
      for (const name of S3_SLOTS) assert.equal(statSync(slotAt(repo, name)).mode & 0o777, want, `${name} under umask ${umask}`);
      assert.deepEqual(strays(repo), []);
    }
  });

  test('TEST-3988 a hook made non-executable after the write fails the post-run attestation on posix and passes with platform win32', async () => {
    const strip = (from, to) => { renameSync(from, to); chmodSync(to, 0o644); };
    const root = scratch('attest-');
    const repo = gitScratch(root);
    const posix = await runMod(root, repo, [], { rename: strip, platform: 'linux' });
    assert.equal(posix.code, 1);
    for (const name of S3_SLOTS) assert.ok(posix.stderr.includes(`ERROR: the ${name} hook git would run (${slotAt(repo, name)}) is not executable — git skips it silently.\n`), name);
    assert.ok(posix.stderr.endsWith("ERROR: installation did NOT leave an active hook at the path git resolves.\n       Check 'git config core.hooksPath' and 'git rev-parse --git-path hooks/reference-transaction'.\n"));
    assert.ok(!posix.stdout.includes('Uninstall with:'));
    const root2 = scratch('attest-win-');
    const repo2 = gitScratch(root2);
    const win = await runMod(root2, repo2, [], { rename: strip, platform: 'win32' });
    assert.equal(win.code, 0, win.stderr);
    assert.ok(win.stdout.endsWith('Uninstall with: bash .aai/scripts/install-pre-commit-hook.sh --uninstall\n'));
  });

  test('TEST-3988 the attestation re-asks git and names a hook it can no longer resolve', async () => {
    const root = scratch('attest-resolve-');
    const repo = gitScratch(root);
    let gitPaths = 0;
    const spawn = (file, args, opts) => {
      if (args.includes('--git-path')) {
        gitPaths += 1;
        if (gitPaths > 3) return { status: 1, stdout: '', stderr: '' };
      }
      return spawnSync(file, args, opts);
    };
    const r = await runMod(root, repo, ['--hooks', 'index'], { spawn });
    assert.equal(gitPaths > 1, true);
    assert.equal(r.code, 1);
    assert.ok(r.stderr.includes('ERROR: installed pre-commit but can no longer resolve the effective hooks path.\n'), r.stderr);
    assert.ok(r.stderr.includes('ERROR: installation did NOT leave an active hook at the path git resolves.\n'));
  });

  test('TEST-3988 the module has no placeholder for the upgrade left', () => {
    const src = readFileSync(MODULE, 'utf8');
    assert.ok(!/not implemented yet/.test(src));
    assert.ok(!/throw notYet/.test(src));
  });
});

// --- TEST-3989 and TEST-3990: the differential corpora (D-CORPUS) -----------------------------------------------

// One case runs once per side at the same absolute path under one own scratch root, the previous side's tree
// renamed away first, so a path in a message is byte-equal on both sides. The sides: 'ref' (a frozen twin) and 'mod'
// (the module). A case is { id, title, steps, setup, norepo, cwd, spaced, rewrites, asserted, ps }:
//   steps      one argument list per run, in order (the PowerShell side uses the PowerShell form)
//   setup(h)   builds the case over the base repository: h.dir, h.hooks, h.write, h.git, h.F
//   rewrites   [{ dr, side, text(s) }] registered per case: each must change at least one byte, or the case fails
//   asserted   (ref, mod, h) replaces the byte comparison with the asserted divergence of the DR it names
const CORPUS_ENV = { LC_ALL: 'C' };
const sideLabel = { ref: 'reference', mod: 'module' };

function corpusFixtures() {
  const guard = shippedGuard().toString('latin1');
  const index = shippedTemplate('index').toString('latin1');
  const lines = guard.split('\n');
  const stale = [lines[0], 'stale interior line', ...lines.slice(2)].join('\n');
  return {
    index: index.endsWith('\n') ? index : `${index}\n`,
    guard,
    stale,
    refTpl: shippedTemplate('ref-guard').toString('latin1'),
    pushTpl: shippedTemplate('pre-push').toString('latin1'),
  };
}

// buildCaseDir(root, c, side, F, refs): the case directory at its fixed path, built for one side.
function buildCaseDir(root, c, side, F, refs) {
  const dir = path.join(root, c.spaced ? 'case dir' : 'case');
  mkdirSync(dir, { recursive: true });
  const env = prepareEnv(root);
  const git = (...a) => {
    const r = spawnSync('git', a, { cwd: dir, env, encoding: 'utf8' });
    assert.equal(r.status, 0, `git ${a.join(' ')}: ${r.stderr}`);
    return r.stdout.replace(/\n+$/, '');
  };
  if (!c.norepo) {
    git('init', '-q', '-b', 'main');
    writeFileSync(path.join(dir, 'README.md'), 'case\n');
    git('add', 'README.md');
    git('-c', 'user.name=corpus', '-c', 'user.email=corpus@example.invalid', 'commit', '-q', '-m', 'init');
  }
  const scripts = path.join(dir, '.aai', 'scripts');
  if (side === 'mod') {
    mkdirSync(path.join(scripts, 'lib'), { recursive: true });
    writeFileSync(path.join(scripts, 'install-pre-commit-hook.mjs'), readFileSync(MODULE));
    writeFileSync(path.join(scripts, 'lib', 'guard-config.mjs'), readFileSync(path.join(ROOT, '.aai', 'scripts', 'lib', 'guard-config.mjs')));
    mkdirSync(path.join(dir, '.aai', 'templates', 'git-hooks'), { recursive: true });
    for (const name of readdirSync(TEMPLATE_DIR)) writeFileSync(path.join(dir, '.aai', 'templates', 'git-hooks', name), readFileSync(path.join(TEMPLATE_DIR, name)));
  } else {
    refs.entries = materializeHookInstallerReference(ROOT, dir);
  }
  writeFileSync(path.join(dir, '.aai', 'templates', 'docs-audit.template.yaml'), readFileSync(path.join(ROOT, '.aai', 'templates', 'docs-audit.template.yaml')));
  const hooks = path.join(dir, '.git', 'hooks');
  const h = {
    dir, hooks, F, git,
    write(rel, content, mode = 0o644) {
      const p = path.join(dir, rel);
      mkdirSync(path.dirname(p), { recursive: true });
      writeFileSync(p, content);
      chmodSync(p, mode);
      return p;
    },
    hook(name, content, mode = 0o755) { return h.write(path.join('.git', 'hooks', name), content, mode); },
    cfg(content, mode = 0o644) { return h.write(path.join('docs', 'ai', CFG), content, mode); },
  };
  if (c.setup) c.setup(h);
  return h;
}

// caseSnapshot(dir): every path under the case directory except .git internals and .aai, each with its type and mode
// and bytes (a link by its target text); plus the regular non-sample entries of every hooks directory under .git.
function caseSnapshot(dir, root, env, cwd) {
  const out = {};
  const walk = (base, prefix, skipTop, skipSample) => {
    for (const name of readdirSync(base).sort()) {
      if (skipTop && (name === '.git' && lstatSync(path.join(base, name)).isDirectory() || name === '.aai')) continue;
      if (skipSample && name.endsWith('.sample')) continue;
      const p = path.join(base, name);
      const key = `${prefix}${name}`;
      const l = lstatSync(p);
      if (l.isSymbolicLink()) out[key] = `link:${readlinkSync(p)}`;
      else if (l.isDirectory()) {
        out[key] = `dir:${(l.mode & 0o777).toString(8)}`;
        walk(p, `${key}/`, false, skipSample);
      } else if (l.isFile()) out[key] = `file:${(l.mode & 0o777).toString(8)}:${JSON.stringify(readFileSync(p).toString('latin1'))}`;
      else out[key] = `other:${l.mode}`;
    }
  };
  walk(dir, '', true, false);
  const dirs = new Set([path.join(dir, '.git', 'hooks')]);
  const r = spawnSync('git', ['rev-parse', '--git-path', 'hooks'], { cwd, env, encoding: 'utf8' });
  if (r.status === 0) dirs.add(path.resolve(cwd, r.stdout.trim()));
  for (const d of dirs) {
    if (!under(d, path.join(dir, '.git'))) continue;
    const key = `.git-hooks:${path.relative(dir, d)}`;
    if (lstatSync(d, { throwIfNoEntry: false }) === undefined) out[key] = 'absent';
    else {
      out[key] = 'dir';
      walk(d, `${key}/`, false, true);
    }
  }
  return out;
}

const textOf = (b) => (Buffer.isBuffer(b) ? b.toString('latin1') : String(b ?? ''));

// runCaseSide(c, side, root, F, refs): builds the case for one side, runs every step, snapshots, renames the tree away.
function runCaseSide(c, side, root, F, refs, script) {
  const h = buildCaseDir(root, c, side, F, refs);
  const cwd = c.cwd ? path.join(h.dir, c.cwd) : h.dir;
  const tmp = path.join(root, `tmp-${side}`);
  mkdirSync(tmp);
  const entry = script(h.dir, side);
  const steps = [];
  const env = prepareEnv(root);
  for (const args of c.steps) {
    // the resolved hooks path lies under the case directory before the run (checked with git itself)
    const pre = spawnSync('git', ['rev-parse', '--git-path', 'hooks/pre-commit'], { cwd, env, encoding: 'utf8' });
    if (pre.status === 0) assert.ok(under(path.resolve(cwd, pre.stdout.trim()), h.dir), `${c.id}: the hooks path of the run lies outside the case directory`);
    const r = runInstaller({ args, root, cwd, script: entry, env: { ...CORPUS_ENV, PWD: cwd, TMPDIR: tmp }, encoding: 'buffer' });
    assert.ok(r.error === undefined, `${c.id} ${side}: ${r.error}`);
    steps.push({ code: r.status, stdout: textOf(r.stdout), stderr: textOf(r.stderr) });
  }
  const result = { steps, snap: caseSnapshot(h.dir, root, env, cwd), tmp: readdirSync(tmp).sort(), h };
  renameSync(h.dir, path.join(root, `tree-${side}`));
  return result;
}

// applyRewrites(c, side, result): applies the registered rewrites of this side; returns the rewrites that changed nothing.
function applyRewrites(c, side, result) {
  const idle = [];
  for (const rw of (c.rewrites ?? []).filter((x) => x.side === side)) {
    let changed = false;
    if (rw.snap) {
      const next = rw.snap(result.snap);
      changed = JSON.stringify(next) !== JSON.stringify(result.snap);
      result.snap = next;
    }
    for (const st of rw.text ? result.steps : []) {
      for (const stream of ['stdout', 'stderr']) {
        const next = rw.text(st[stream]);
        if (next !== st[stream]) changed = true;
        st[stream] = next;
      }
    }
    if (!changed) idle.push(rw.dr);
  }
  return idle;
}

const strip = (res, keys) => ({ steps: res.steps.map((s) => Object.fromEntries(keys.map((k) => [k, s[k]]))), snap: res.snap, ...(keys.includes('stdout') ? { tmp: res.tmp } : {}) });

// scratchRootIsClean(root): after a case the root holds only the marker, the global config, the logs, the per-side
// scratch TMPDIRs and the two renamed-away trees.
function assertRootClean(root, id) {
  const allowed = new Set([OWN_MARKER_FILE, 'gitconfig', 'tmp', 'tmp-ref', 'tmp-mod', 'tree-ref', 'tree-mod', 'ref']);
  for (const name of readdirSync(root)) assert.ok(allowed.has(name), `${id}: unexpected entry ${name} in the case scratch root`);
}

// runCorpusCase(c, refSide, label, keys): the whole differential run of one case.
function runCorpusCase(c, refSide, keys, F, script) {
  const root = scratch(`corpus-${c.id.toLowerCase()}-`);
  const refs = {};
  const ref = runCaseSide(c, refSide, root, F, refs, script);
  const mod = runCaseSide(c, 'mod', root, F, refs, script);
  const idle = [...applyRewrites(c, 'ref', ref), ...applyRewrites(c, 'mod', mod)];
  assert.deepEqual(idle, [], `${c.id}: a registered rewrite changed nothing`);
  if (c.asserted) c.asserted(ref, mod, ref.h);
  else assert.deepEqual(strip(mod, keys), strip(ref, keys), `${c.id}: the module differs from the frozen ${sideLabel[refSide]} twin`);
  assertRootClean(root, c.id);
  return { ref, mod };
}

const scriptFor = (refKind) => (dir, side) => path.join(dir, '.aai', 'scripts', side === 'mod' ? 'install-pre-commit-hook.mjs' : `install-pre-commit-hook.${refKind}`);


// The bash-side cases (K): bashCases(F) builds them over the fixture texts of corpusFixtures().
function bashCases(F) {
  const IDX = S3_MARKER['pre-commit'];
  const preCommit = (extra) => `#!/bin/sh\n${IDX} - x\n${extra}`;
  const decl = 'ref_guard: declined\n';
  const k = (id, title, steps, extra = {}) => ({ id, title, steps, ...extra });
  const cases = [
    k('K01', 'plain install in an empty repository', [[]]),
    k('K02', 'the same twice', [[], []]),
    k('K03', 'a foreign pre-commit', [[]], { setup: (h) => h.hook('pre-commit', '#!/bin/sh\necho foreign\n') }),
    k('K04', 'a foreign pre-commit with --force', [['--force']], { setup: (h) => h.hook('pre-commit', '#!/bin/sh\necho foreign\n') }),
    k('K05', 'a pre-guard AAI pre-commit is upgraded by insertion', [[]], { setup: (h) => h.hook('pre-commit', F.index) }),
    k('K06', 'a stale guard interior is refreshed', [[]], { setup: (h) => h.hook('pre-commit', F.stale + F.index) }),
  ];
  const unprovable = {
    a: Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(preCommit('x\n'), 'latin1')]),
    b: Buffer.from(IDX),
    c: Buffer.from(`#!/bin/sh\r\n${IDX}\n`),
    d: Buffer.from(preCommit(`${S3_END}\n`)),
    e: Buffer.from(`#!/bin/sh\n${IDX}\n${S3_BEGIN}\na\n${S3_END}\n${S3_BEGIN}\nb\n${S3_END}\n`),
    f: Buffer.from(`#!/bin/sh\n${IDX}\n${S3_END}\n${S3_BEGIN}\n`),
  };
  for (const [l, bytes] of Object.entries(unprovable)) cases.push(k(`K07${l}`, `an unprovable pre-commit (${l})`, [[]], { setup: (h) => h.hook('pre-commit', bytes) }));
  cases.push(
    k('K08', 'a symlinked pre-commit slot whose target is the K05 body', [[]], {
      setup: (h) => { h.write('target-hook', F.index, 0o755); symlinkSync(path.join(h.dir, 'target-hook'), path.join(h.hooks, 'pre-commit')); rmSync(path.join(h.hooks, 'pre-commit'), { force: true }); symlinkSync(path.join(h.dir, 'target-hook'), path.join(h.hooks, 'pre-commit')); },
    }),
    k('K09a', 'core.hooksPath=.githooks, not yet existing', [[]], { setup: (h) => h.git('config', 'core.hooksPath', '.githooks') }),
    k('K09b', 'an absolute core.hooksPath under the case', [[]], { setup: (h) => h.git('config', 'core.hooksPath', path.join(h.dir, 'abs-hooks')) }),
    k('K09c', 'a run from a subdirectory with K09a', [[]], { cwd: 'sub', setup: (h) => { h.git('config', 'core.hooksPath', '.githooks'); mkdirSync(path.join(h.dir, 'sub')); } }),
    k('K10', 'a linked worktree', [[]], { cwd: 'wt', setup: (h) => h.git('worktree', 'add', '-q', '-b', 'wtbranch', 'wt') }),
    k('K11a', '--hooks index', [['--hooks', 'index']]),
    k('K11b', '--hooks ref-guard', [['--hooks', 'ref-guard']]),
    k('K11c', '--hooks close-gate', [['--hooks', 'close-gate']]),
    k('K11d', '--hooks index,close-gate', [['--hooks', 'index,close-gate']]),
    k('K12a', '--hooks bogus', [['--hooks', 'bogus']]),
    k('K12b', "--hooks ''", [['--hooks', '']]),
    k('K12c', '--hooks at the end', [['--hooks']]),
    k('K13a', '--uninstall after K01', [[], ['--uninstall']]),
    k('K13b', '--uninstall --hooks ref-guard after K01', [[], ['--uninstall', '--hooks', 'ref-guard']]),
    k('K14a', '--decline-ref-guard with no config', [['--decline-ref-guard']]),
    k('K14b', '--decline-ref-guard with an existing config', [['--decline-ref-guard']], { setup: (h) => h.cfg('close_gate: report\nref_guard: armed\n') }),
    k('K14c', '--decline-ref-guard with a foreign reference-transaction hook', [['--decline-ref-guard']], { setup: (h) => h.hook('reference-transaction', '#!/bin/sh\necho foreign\n') }),
    k('K14d', '--decline-ref-guard with a symlinked foreign reference-transaction hook', [['--decline-ref-guard']], {
      setup: (h) => { h.write('elsewhere-foreign', '#!/bin/sh\necho foreign\n', 0o755); symlinkSync(path.join(h.dir, 'elsewhere-foreign'), path.join(h.hooks, 'reference-transaction')); },
    }),
    k('K15', '--arm-ref-guard after K14a', [['--decline-ref-guard'], ['--arm-ref-guard']]),
    k('K16', 'a declined config and a plain run', [[]], { setup: (h) => h.cfg(decl) }),
    k('K16f', 'a declined config and a plain run with --force', [['--force']], { setup: (h) => h.cfg(decl) }),
  );
  for (const [l, kind] of [['a', 'index'], ['b', 'guard-checks'], ['c', 'ref-guard'], ['d', 'pre-push']]) cases.push(k(`K17${l}`, `--print ${kind} outside a repository`, [['--print', kind]], { norepo: true }));
  cases.push(
    k('K18', '-h', [['-h']]),
    k('K19', '--bogus', [['--bogus']]),
    k('K20', '--uninstall --decline-ref-guard', [['--uninstall', '--decline-ref-guard']]),
    k('K21', '--print --force', [['--print', '--force']]),
    k('K22', '--hooks index,', [['--hooks', 'index,']]),
    k('K23', 'a declined config and a foreign reference-transaction hook, plain run', [[]], { setup: (h) => { h.cfg(decl); h.hook('reference-transaction', '#!/bin/sh\necho foreign\n'); } }),
    k('K24', 'a directory at the reference-transaction slot, plain run', [[]], { setup: (h) => mkdirSync(path.join(h.hooks, 'reference-transaction')) }),
    k('K25', '--decline-ref-guard on a symlinked config', [['--decline-ref-guard']], {
      setup: (h) => { h.write('real-config.yaml', 'close_gate: report\nref_guard: armed\n'); mkdirSync(path.join(h.dir, 'docs', 'ai'), { recursive: true }); symlinkSync(path.join(h.dir, 'real-config.yaml'), path.join(h.dir, 'docs', 'ai', CFG)); },
    }),
    k('K26', '--arm-ref-guard on a CRLF config, mode 0644, with a declined line', [['--arm-ref-guard']], { setup: (h) => h.cfg('close_gate: report\r\nref_guard: declined\r\n', 0o644) }),
    k('K27a', 'a doubled key under --arm-ref-guard', [['--arm-ref-guard']], { setup: (h) => h.cfg('ref_guard: armed\nref_guard: declined\n') }),
    k('K27b', 'a doubled key under --decline-ref-guard', [['--decline-ref-guard']], { setup: (h) => h.cfg('ref_guard: armed\nref_guard: declined\n') }),
    k('K27c', 'a doubled key, plain run', [[]], { setup: (h) => h.cfg('ref_guard: armed\nref_guard: declined\n') }),
    k('K27d', 'ref_guard with a no-break space before declined, plain run', [[]], { setup: (h) => h.cfg('ref_guard:\u00a0declined\n') }),
    k('K28', 'not a repository', [[]], { norepo: true }),
  );
  for (const [l, name] of [['a', 'pre-commit-index.sh'], ['b', 'pre-commit-guard-checks.sh'], ['c', 'reference-transaction.sh'], ['d', 'pre-push.sh']]) {
    cases.push(k(`K29${l}`, `the template ${name} is missing`, [[]], { setup: (h) => rmSync(path.join(h.dir, '.aai', 'templates', 'git-hooks', name)) }));
  }
  cases.push(
    k('K30', 'a reference-transaction hook carrying the marker with other bytes', [[]], { setup: (h) => h.hook('reference-transaction', `${F.refTpl}# local\n`) }),
    k('K31', 'the case directory path holds a space', [[]], { spaced: true }),
  );
  return cases;
}

const BASH_KEYS = ['code', 'stdout', 'stderr'];

const latin1Of = (text) => Buffer.from(text, 'utf8').toString('latin1');
const BASE_SNAP = { '.git-hooks:.git/hooks': 'dir', 'README.md': `file:644:${JSON.stringify('case\n')}` };
const CFG_KEY = 'docs/ai/docs-audit.yaml';
const cfgOf = (snap) => {
  const m = /^file:([0-7]+):(.*)$/s.exec(snap[CFG_KEY] ?? '');
  return m ? { mode: m[1], text: JSON.parse(m[2]) } : null;
};
const hookKeys = (snap) => Object.keys(snap).filter((k) => k.startsWith('.git-hooks:.git/hooks/')).sort();

// The registered rewrites (D-CORPUS): each names the DR whose text it removes and the side it is applied on.
const rwWholeRun = { dr: 'DR-12', side: 'mod', text: (t) => t.split(latin1Of('ERROR: refusing the whole run \u2014 nothing was written. Fix the slot(s) named above and re-run.\n')).join('') };
const rwRearm = { dr: 'DR-10', side: 'mod', text: (t) => t.replace(' (--force installs the hook for this run only; ref_guard: declined stays recorded).', ' (or pass --force).') };
const rwNote = { dr: 'DR-14', side: 'mod', text: (t) => t.replace(/^NOTE: .* carries # AAI:REF-GUARD but its bytes differ from the shipped body; pass --force to replace it\.\n/m, '') };
const rwUninstall = { dr: 'DR-18', side: 'mod', text: (t) => t.replace(/^NOTE: docs\/ai\/docs-audit\.yaml (?:still reads ref_guard: armed|does not exist, so ref_guard reads as armed by default).*\n/m, '').replace(/^To keep it off, run: .*\n/m, '') };
const rwMode = { dr: 'DR-15', side: 'ref', snap: (snap) => (snap[CFG_KEY]?.startsWith('file:600:') ? { ...snap, [CFG_KEY]: snap[CFG_KEY].replace('file:600:', 'file:644:') } : snap) };

// The asserted divergences of the bash side, each compared to an expected value instead of byte equality.
const BASH_ASSERTED = {
  K18(ref, mod) {
    const [r, m] = [ref.steps[0], mod.steps[0]];
    assert.deepEqual([r.code, m.code, r.stderr, m.stderr], [0, 0, '', '']);
    const rl = r.stdout.split('\n');
    const ml = m.stdout.split('\n');
    assert.equal(rl.length - 1, 377, 'the bash -h prints all 377 comment lines');
    const block = readFileSync(path.join(ROOT, REFERENCE_SH), 'latin1').split('\n').slice(3, 78).map((l) => l.replace(/^# {0,1}/, ''));
    assert.deepEqual(ml.slice(0, 75), block, 'the module help is the reference lines 4 to 78');
    const commentOnly = readFileSync(path.join(ROOT, REFERENCE_SH), 'latin1').split('\n').slice(3, 78).filter((l) => l.startsWith('#')).map((l) => l.replace(/^# {0,1}/, ''));
    assert.deepEqual(rl.slice(1, 1 + commentOnly.length), commentOnly, 'and those lines open the bash help');
    assert.equal(ml.length - 1, 77, 'plus two lines');
    assert.ok(ml[75].startsWith('  powershell -NoProfile -File .aai/scripts/install-pre-commit-hook.ps1 ') && ml[76].startsWith('Requires Node.js 22 or later'));
    assert.deepEqual(mod.snap, ref.snap);
  },
  K20(ref, mod) {
    assert.equal(ref.steps[0].code, 0, 'bash: the first dispatched mode wins');
    assert.ok(ref.steps[0].stdout.includes('Declined the AAI reference-transaction guard.'));
    assert.ok(cfgOf(ref.snap)?.text.includes('ref_guard: declined'));
    assert.deepEqual(mod.steps[0], { code: 2, stdout: '', stderr: 'ERROR: --uninstall and --decline-ref-guard are contradictory.\n' });
    assert.deepEqual(mod.snap, BASE_SNAP, 'the module did nothing');
  },
  K21(ref, mod) {
    assert.deepEqual([ref.steps[0].code, ref.steps[0].stderr, ref.steps[0].stdout], [0, '', F_INDEX_PRINT(ref)], 'bash ignores --force and prints the template');
    assert.deepEqual(mod.steps[0], { code: 2, stdout: '', stderr: 'ERROR: --force has no effect with --print.\n' });
    assert.deepEqual(mod.snap, BASE_SNAP);
  },
  K22(ref, mod) {
    assert.equal(ref.steps[0].code, 0, 'bash accepts a trailing comma');
    assert.deepEqual(hookKeys(ref.snap), ['.git-hooks:.git/hooks/pre-commit']);
    assert.deepEqual(mod.steps[0], { code: 2, stdout: '', stderr: "ERROR: unknown --hooks value: '' (closed set: index, ref-guard, close-gate, all)\n" });
    assert.deepEqual(mod.snap, BASE_SNAP);
  },
  K23(ref, mod, h) {
    assert.equal(ref.steps[0].code, 1, 'bash refuses the whole run over a foreign hook in a declined slot');
    assert.deepEqual(hookKeys(ref.snap), ['.git-hooks:.git/hooks/reference-transaction']);
    assert.equal(mod.steps[0].code, 0);
    assert.equal(mod.steps[0].stderr, '');
    assert.ok(mod.steps[0].stdout.includes(`Skipped AAI reference-transaction hook (AAI:REF-GUARD): ${h.dir}/docs/ai/docs-audit.yaml declares ref_guard: declined.\n`));
    assert.deepEqual(hookKeys(mod.snap), ['.git-hooks:.git/hooks/pre-commit', '.git-hooks:.git/hooks/pre-push', '.git-hooks:.git/hooks/reference-transaction']);
    assert.equal(mod.snap['.git-hooks:.git/hooks/reference-transaction'], ref.snap['.git-hooks:.git/hooks/reference-transaction'], 'the foreign hook is untouched');
    assert.equal(mod.snap[CFG_KEY], ref.snap[CFG_KEY]);
  },
  K24(ref, mod) {
    assert.equal(ref.steps[0].code, 1);
    assert.ok(hookKeys(ref.snap).includes('.git-hooks:.git/hooks/pre-commit'), 'bash installed the other hooks before failing');
    assert.ok(hookKeys(ref.snap).some((k) => /reference-transaction\/reference-transaction\.aai-tmp\./.test(k)), 'bash left a stray temp inside the directory slot');
    assert.equal(mod.steps[0].code, 1);
    assert.equal(mod.steps[0].stdout, '');
    assert.match(mod.steps[0].stderr, /^ERROR: reference-transaction slot .* is a directory, not a regular file\. Nothing was written and the slot is untouched\./);
    assert.deepEqual(mod.snap, { ...BASE_SNAP, '.git-hooks:.git/hooks/reference-transaction': 'dir:755' }, 'the module wrote nothing');
  },
  K25(ref, mod, h) {
    assert.deepEqual([mod.steps[0].code, mod.steps[0].stdout, mod.steps[0].stderr], [ref.steps[0].code, ref.steps[0].stdout, ref.steps[0].stderr]);
    assert.ok(ref.snap[CFG_KEY].startsWith('file:600:'), 'bash replaced the link by a 0600 file');
    assert.equal(ref.snap['real-config.yaml'].includes('armed'), true, 'the link target stayed armed');
    assert.equal(mod.snap[CFG_KEY], `link:${h.dir}/real-config.yaml`, 'the module kept the link');
    assert.equal(mod.snap['real-config.yaml'], 'file:644:' + JSON.stringify('close_gate: report\nref_guard: declined\n'));
  },
  K26(ref, mod) {
    assert.deepEqual([mod.steps[0].code, mod.steps[0].stdout, mod.steps[0].stderr], [ref.steps[0].code, ref.steps[0].stdout, ref.steps[0].stderr]);
    assert.deepEqual(cfgOf(ref.snap), { mode: '600', text: 'close_gate: report\r\nref_guard: armed\n' });
    assert.deepEqual(cfgOf(mod.snap), { mode: '644', text: 'close_gate: report\r\nref_guard: armed\r\n' });
    assert.deepEqual(hookKeys(mod.snap), hookKeys(ref.snap));
  },
  K27a(ref, mod, h) {
    assert.equal(ref.steps[0].code, 1);
    assert.match(ref.steps[0].stderr, /but reading it back gives declined\.\n$/);
    assert.equal(cfgOf(ref.snap).text, 'ref_guard: armed\nref_guard: declined\n');
    assert.equal(mod.steps[0].code, 0);
    assert.equal(mod.steps[0].stderr, '');
    assert.ok(mod.steps[0].stdout.includes(`Removed 1 duplicate ref_guard: line(s) from ${h.dir}/docs/ai/docs-audit.yaml (lines 2).\n`));
    assert.deepEqual(cfgOf(mod.snap), { mode: '644', text: 'ref_guard: armed\n' });
  },
  K27b(ref, mod, h) {
    assert.equal(ref.steps[0].code, 0);
    assert.equal(cfgOf(ref.snap).text, 'ref_guard: declined\nref_guard: declined\n', 'bash leaves both lines');
    assert.equal(mod.steps[0].code, 0);
    assert.ok(mod.steps[0].stdout.startsWith(`Removed 1 duplicate ref_guard: line(s) from ${h.dir}/docs/ai/docs-audit.yaml (lines 2).\n`));
    assert.deepEqual(cfgOf(mod.snap), { mode: '644', text: 'ref_guard: declined\n' });
  },
  K27c(ref, mod, h) {
    assert.equal(ref.steps[0].code, 0);
    assert.ok(ref.steps[0].stdout.includes('Skipped AAI reference-transaction hook'), 'the bash grep reads the later declined line');
    assert.ok(!hookKeys(ref.snap).includes('.git-hooks:.git/hooks/reference-transaction'));
    assert.equal(mod.steps[0].code, 0);
    assert.ok(mod.steps[0].stdout.includes(`Installed AAI reference-transaction hook (AAI:REF-GUARD) at ${h.dir}/.git/hooks/reference-transaction\n`), 'the first key wins');
    assert.equal(mod.steps[0].stderr, `WARNING: ${h.dir}/docs/ai/docs-audit.yaml carries 2 ref_guard: lines (lines 1, 2); the first one wins. Repair: bash ${h.dir}/.aai/scripts/install-pre-commit-hook.sh --arm-ref-guard (or --decline-ref-guard).\n`);
    assert.equal(mod.snap[CFG_KEY], ref.snap[CFG_KEY], 'a plain run does not touch the file');
  },
  K27d(ref, mod) {
    assert.equal(ref.steps[0].code, 0);
    assert.ok(hookKeys(ref.snap).includes('.git-hooks:.git/hooks/reference-transaction'), 'bash under LC_ALL=C read armed');
    assert.equal(mod.steps[0].code, 0);
    assert.ok(mod.steps[0].stdout.includes('Skipped AAI reference-transaction hook'), 'the reader reads declined');
    assert.ok(!hookKeys(mod.snap).includes('.git-hooks:.git/hooks/reference-transaction'));
    assert.equal(mod.snap[CFG_KEY], ref.snap[CFG_KEY]);
  },
};
const F_INDEX_PRINT = () => corpusFixtures().index;

// Per-case wiring of the rewrites and asserted divergences onto the cases built by bashCases.
function wireBashCases(cases) {
  const by = Object.fromEntries(cases.map((c) => [c.id, c]));
  for (const l of 'abcdef') by[`K07${l}`].rewrites = [rwWholeRun];
  by.K08.rewrites = [rwWholeRun];
  by.K13a.rewrites = [rwUninstall];
  by.K13b.rewrites = [rwUninstall];
  by.K14b.rewrites = [rwMode];
  by.K15.rewrites = [rwMode];
  by.K16.rewrites = [rwRearm];
  by.K30.rewrites = [rwNote];
  for (const [id, fn] of Object.entries(BASH_ASSERTED)) by[id].asserted = fn;
  return cases;
}

describe('TEST-3989 the bash-side corpus K01 to K31 against the frozen bash reference', { skip: process.platform === 'win32' }, () => {
  const F = corpusFixtures();
  const cases = wireBashCases(bashCases(F));
  test('TEST-3989 the corpus holds K01 to K31 with every lettered case, and no case is filtered away', () => {
    const ids = cases.map((c) => c.id);
    assert.equal(new Set(ids).size, ids.length);
    const want = ['K01', 'K02', 'K03', 'K04', 'K05', 'K06', ...'abcdef'.split('').map((l) => `K07${l}`), 'K08', 'K09a', 'K09b', 'K09c', 'K10',
      'K11a', 'K11b', 'K11c', 'K11d', 'K12a', 'K12b', 'K12c', 'K13a', 'K13b', 'K14a', 'K14b', 'K14c', 'K14d', 'K15', 'K16', 'K16f',
      'K17a', 'K17b', 'K17c', 'K17d', 'K18', 'K19', 'K20', 'K21', 'K22', 'K23', 'K24', 'K25', 'K26', 'K27a', 'K27b', 'K27c', 'K27d',
      'K28', 'K29a', 'K29b', 'K29c', 'K29d', 'K30', 'K31'];
    assert.deepEqual(ids, want);
  });
  for (const c of cases) {
    test(`TEST-3989 ${c.id} ${c.title}`, () => {
      runCorpusCase(c, 'ref', BASH_KEYS, F, scriptFor('sh'));
    });
  }
});

// The PowerShell-side cases (P), PowerShell-form arguments; compared on exit code and case snapshot only.
function psCases(F) {
  const IDX = S3_MARKER['pre-commit'];
  const foreign = '#!/bin/sh\necho foreign\n';
  const p = (id, title, steps, extra = {}) => ({ id, title, steps, ...extra });
  return [
    p('P01', 'plain', [[]]),
    p('P02', 'twice', [[], []]),
    p('P03', 'a foreign pre-commit and a foreign pre-push', [[]], { setup: (h) => { h.hook('pre-commit', foreign); h.hook('pre-push', foreign); } }),
    p('P04', '-Force on P03', [['-Force']], { setup: (h) => { h.hook('pre-commit', foreign); h.hook('pre-push', foreign); } }),
    p('P05', 'a pre-guard AAI pre-commit is upgraded', [[]], { setup: (h) => h.hook('pre-commit', F.index) }),
    p('P06', 'a stale guard interior is refreshed', [[]], { setup: (h) => h.hook('pre-commit', F.stale + F.index) }),
    p('P07', 'a BOM pre-commit is unprovable', [[]], { setup: (h) => h.hook('pre-commit', Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(`#!/bin/sh\n${IDX} - x\nx\n`, 'latin1')])) }),
    p('P08', 'core.hooksPath', [[]], { setup: (h) => h.git('config', 'core.hooksPath', '.githooks') }),
    p('P09', '-Hooks index', [['-Hooks', 'index']]),
    p('P10', '-Uninstall after P01', [[], ['-Uninstall']]),
    p('P11', '-Hooks Index', [['-Hooks', 'Index']]),
    p('P12', '-Hooks at the end', [['-Hooks']]),
    p('P13', '-DeclineRefGuard then a plain run', [['-DeclineRefGuard'], []]),
    p('P14', 'declined plus a foreign reference-transaction hook', [[]], { setup: (h) => { h.cfg('ref_guard: declined\n'); h.hook('reference-transaction', foreign); } }),
    p('P15', 'a directory at the pre-push slot', [[]], { setup: (h) => mkdirSync(path.join(h.hooks, 'pre-push')) }),
    p('P16', '-ArmRefGuard on a CRLF config with a doubled key', [['-ArmRefGuard']], { setup: (h) => h.cfg('close_gate: report\r\nref_guard: declined\r\nref_guard: declined\r\n') }),
    p('P17', 'not a repository', [[]], { norepo: true }),
    p('P18', '-h', [['-h']]),
    p('P19', '--bogus', [['--bogus']]),
    p('P20', '-Uninstall -DeclineRefGuard', [['-Uninstall', '-DeclineRefGuard']]),
  ];
}

const PS_KEYS = ['code'];

const sameExitAndTree = (ref, mod) => assert.deepEqual(strip(mod, PS_KEYS), strip(ref, PS_KEYS));
// The asserted divergences of the PowerShell side; the .ps1 messages are not compared (every one is a DR-10 text).
const PS_ASSERTED = {
  P03(ref, mod, h) {
    sameExitAndTree(ref, mod);
    assert.equal(mod.steps[0].code, 1);
    for (const slot of ['pre-commit', 'pre-push']) assert.ok(mod.steps[0].stderr.includes(`ERROR: ${h.dir}/.git/hooks/${slot} already exists and is not AAI-managed.`), `the module names the foreign ${slot}`);
  },
  P11(ref, mod) {
    assert.equal(ref.steps[0].code, 0, 'the .ps1 matches Index case-insensitively and installs');
    assert.ok(hookKeys(ref.snap).includes('.git-hooks:.git/hooks/pre-commit'));
    assert.deepEqual(mod.steps[0], { code: 2, stdout: '', stderr: "ERROR: unknown --hooks value: 'Index' (closed set: index, ref-guard, close-gate, all)\n" });
    assert.deepEqual(mod.snap, BASE_SNAP);
  },
  P12(ref, mod) {
    assert.equal(ref.steps[0].code, 1, 'a binding error');
    assert.deepEqual(ref.snap, BASE_SNAP);
    assert.deepEqual(mod.steps[0], { code: 2, stdout: '', stderr: 'ERROR: --hooks requires a value (closed set: index, ref-guard, close-gate, all)\n' });
    assert.deepEqual(mod.snap, BASE_SNAP);
  },
  P14(ref, mod, h) {
    assert.equal(ref.steps[0].code, 1, 'the .ps1 refuses the whole run over a foreign hook in a declined slot');
    assert.deepEqual(hookKeys(ref.snap), ['.git-hooks:.git/hooks/reference-transaction']);
    assert.equal(mod.steps[0].code, 0);
    assert.ok(mod.steps[0].stdout.includes(`Skipped AAI reference-transaction hook (AAI:REF-GUARD): ${h.dir}/docs/ai/docs-audit.yaml declares ref_guard: declined.\n`));
    assert.deepEqual(hookKeys(mod.snap), ['.git-hooks:.git/hooks/pre-commit', '.git-hooks:.git/hooks/pre-push', '.git-hooks:.git/hooks/reference-transaction']);
    assert.equal(mod.snap['.git-hooks:.git/hooks/reference-transaction'], ref.snap['.git-hooks:.git/hooks/reference-transaction']);
  },
  P16(ref, mod) {
    assert.equal(ref.steps[0].code, 1, 'the .ps1 fails its read-back over the doubled key');
    assert.deepEqual(cfgOf(ref.snap), { mode: '644', text: 'close_gate: report\nref_guard: armed\nref_guard: declined\n' }, 'every line ending is rewritten');
    assert.equal(mod.steps[0].code, 0);
    assert.deepEqual(cfgOf(mod.snap), { mode: '644', text: 'close_gate: report\r\nref_guard: armed\r\n' });
  },
  P17(ref, mod) {
    assert.equal(ref.steps[0].code, 1);
    assert.deepEqual(mod.steps[0], { code: 1, stdout: '', stderr: 'ERROR: not inside a git repository.\n' });
    assert.deepEqual(mod.snap, ref.snap);
  },
  P18(ref, mod) {
    assert.equal(ref.steps[0].code, 1, 'the .ps1 binds -h to -Hooks and fails');
    assert.equal(mod.steps[0].code, 0);
    assert.ok(mod.steps[0].stdout.startsWith('Install the AAI git hook SET into the EFFECTIVE hooks directory'));
    assert.deepEqual(mod.snap, ref.snap);
  },
  P19(ref, mod) {
    assert.equal(ref.steps[0].code, 1, 'a binding error');
    assert.deepEqual(mod.steps[0], { code: 2, stdout: '', stderr: 'ERROR: unexpected argument: --bogus\n' });
    assert.deepEqual([mod.snap, ref.snap], [BASE_SNAP, BASE_SNAP]);
  },
  P20(ref, mod) {
    assert.equal(ref.steps[0].code, 0, 'the first dispatched mode wins');
    assert.ok(cfgOf(ref.snap)?.text.includes('ref_guard: declined'));
    assert.deepEqual(mod.steps[0], { code: 2, stdout: '', stderr: 'ERROR: --uninstall and --decline-ref-guard are contradictory.\n' });
    assert.deepEqual(mod.snap, BASE_SNAP);
  },
};

describe('TEST-3990 the PowerShell-side corpus P01 to P20 against the frozen PowerShell reference', { skip: process.platform === 'win32' || spawnSync('pwsh', ['-NoProfile', '-Command', 'exit 0']).status !== 0 }, () => {
  const F = corpusFixtures();
  const cases = psCases(F);
  for (const c of cases) if (PS_ASSERTED[c.id]) c.asserted = PS_ASSERTED[c.id];
  test('TEST-3990 the corpus holds P01 to P20 and no case is filtered away', () => {
    assert.deepEqual(cases.map((c) => c.id), Array.from({ length: 20 }, (_, i) => `P${String(i + 1).padStart(2, '0')}`));
  });
  for (const c of cases) {
    test(`TEST-3990 ${c.id} ${c.title}`, () => {
      runCorpusCase(c, 'ref', PS_KEYS, F, scriptFor('ps1'));
    });
  }
});
