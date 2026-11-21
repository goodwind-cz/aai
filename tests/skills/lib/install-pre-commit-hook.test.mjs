// install-pre-commit-hook.test.mjs - node:test cases of the hook-installer-on-node ride
// (docs/specs/SPEC-DRAFT-pre-commit-installer-on-node.md). Every case name starts with its TEST id; the suite
// tests/skills/test-aai-hook-installer-node.sh selects them with --test-name-pattern. The file grows run by run.
//
// Safety (D-SAFETY): directories are created and removed only through hook-installer-reference.mjs (own prefix,
// marker, re-verified before removal); no case starts a container tool or kills by pattern; every installer
// invocation goes through runInstaller, which sets GIT_CONFIG_NOSYSTEM=1 and an empty GIT_CONFIG_GLOBAL, runs
// only under the run's own scratch root and asserts that the hooks path git resolves there lies under it.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  existsSync, mkdirSync, readdirSync, readFileSync, statSync, symlinkSync, writeFileSync,
} from 'node:fs';
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

// prepareEnv(root, extra): the environment of an installer run: the caller's minus every AAI_ variable, plus no
// system git config, a global git config that is an empty scratch file (a global core.hooksPath would otherwise
// redirect the writes) and a per-root TMPDIR.
export function prepareEnv(root, extra = {}) {
  const env = {};
  for (const [k, v] of Object.entries(process.env)) if (!k.startsWith('AAI_') && k !== 'GIT_DIR' && k !== 'GIT_WORK_TREE') env[k] = v;
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
export function runInstaller({ args = [], root, cwd = root, env = {}, script = MODULE }) {
  const runEnv = prepareEnv(root, env);
  assert.equal(runEnv.GIT_CONFIG_NOSYSTEM, '1');
  assert.equal(readFileSync(runEnv.GIT_CONFIG_GLOBAL, 'utf8'), '', 'GIT_CONFIG_GLOBAL is an empty file');
  assertHooksUnderRoot(cwd, root, runEnv);
  const file = script.endsWith('.sh') ? 'bash' : process.execPath;
  return spawnSync(file, [script, ...args], { cwd, env: runEnv, encoding: 'utf8' });
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
      const problems = file.endsWith('.sh') ? shellInvocationProblems(src) : invocationProblems(src);
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

// --- TEST-3981 ---------------------------------------------------------------------------------------------

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

// --- TEST-3982 ---------------------------------------------------------------------------------------------

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
