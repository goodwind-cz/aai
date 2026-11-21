// aai-update.test.mjs - node:test cases of the update-on-node ride
// (docs/specs/SPEC-DRAFT-update-on-node.md). Every case name starts with its TEST id; the suite
// tests/skills/test-aai-update-node.sh selects them with --test-name-pattern.
//
// Safety (D-SAFETY): directories are created and removed only through update-reference.mjs (own prefix,
// marker, re-verified before removal); no case starts a container tool or kills by pattern; every update
// invocation goes through runUpdate, which sets the network-free environment and refuses a repo argument
// outside the run's own scratch root.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  chmodSync, existsSync, mkdirSync, readdirSync, readFileSync, statSync, symlinkSync, writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { after, describe, test } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import {
  OWN_MARKER_FILE, REFERENCE_COMMIT, REFERENCE_PS1, REFERENCE_PS1_SHA256, REFERENCE_SH, REFERENCE_SH_SHA256,
  createOwnScratch, materializeUpdateReference, removeOwnScratch, removeOwnScratchAll, sha256File,
} from './update-reference.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..', '..');
const MODULE = path.join(ROOT, '.aai', 'scripts', 'aai-update.mjs');
const MODULE_URL = pathToFileURL(MODULE).href;
// Every test file of this ride that exists; a file that a later run adds is listed here by that run.
const NEW_TEST_FILES = [
  path.join(ROOT, 'tests', 'skills', 'test-aai-update-node.sh'),
  path.join(HERE, 'aai-update.test.mjs'),
  path.join(HERE, 'update-reference.mjs'),
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

// --- the update invocation helpers (D-SAFETY) --------------------------------------------------------------

const TOKENS = ['GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN'];
const under = (child, parent) => child === parent || child.startsWith(parent.endsWith(path.sep) ? parent : parent + path.sep);

// assertRepoUnderRoot(args, root, cwd): every --repo or -Repo value of an update invocation must name a
// path under the run's own scratch root, or a file:// URL under it; a bare slug is allowed only when the
// invocation is a dry-run (it starts no clone). A value flag without a value is not a repo argument.
export function assertRepoUnderRoot(args, root, cwd = root) {
  assert.ok(path.isAbsolute(root) && path.basename(root).startsWith('aai-up-'), `scratch root ${root} lacks the own prefix`);
  assert.ok(existsSync(path.join(root, OWN_MARKER_FILE)), `scratch root ${root} lacks the ownership marker`);
  const dry = args.some((a) => a === '--dry-run' || a.toLowerCase() === '-dryrun');
  for (let i = 0; i < args.length; i += 1) {
    const a = args[i];
    let value = null;
    if (a === '--repo' || a.toLowerCase() === '-repo') value = args[i + 1];
    else if (a.startsWith('--repo=')) value = a.slice('--repo='.length);
    if (value === null || value === undefined || value === '') continue;
    if (value.includes('://')) {
      assert.ok(value.startsWith('file://') && under(value.slice('file://'.length), root), `repo URL ${value} is not a file:// URL under ${root}`);
    } else {
      const resolved = path.resolve(cwd, value);
      // a slug-shaped value that is not an existing directory is a slug, and a slug is only safe in a dry-run
      if (/^[^/]+\/[^/]+$/.test(value) && !existsSync(resolved)) assert.ok(dry, `repo slug ${value} outside a dry-run would start a clone`);
      else assert.ok(under(resolved, root), `repo argument ${value} lies outside the scratch root ${root}`);
    }
  }
}

// prepareEnv(root, extra): the network-free environment of an update run (D-CORPUS): the caller's minus every
// AAI_ variable and the GitHub tokens, plus a global git config that is an empty file, GIT_ALLOW_PROTOCOL=file,
// an empty GH_CONFIG_DIR, a per-root TMPDIR and, on POSIX, a gh stub that fails first on PATH.
export function prepareEnv(root, extra = {}) {
  const env = {};
  for (const [k, v] of Object.entries(process.env)) if (!k.startsWith('AAI_') && !TOKENS.includes(k)) env[k] = v;
  const gitconfig = path.join(root, 'gitconfig');
  const ghDir = path.join(root, 'gh-config');
  const tmp = path.join(root, 'tmp');
  const bin = path.join(root, 'bin');
  for (const d of [ghDir, tmp, bin]) mkdirSync(d, { recursive: true });
  writeFileSync(gitconfig, '');
  if (process.platform !== 'win32') {
    const stub = path.join(bin, 'gh');
    writeFileSync(stub, `#!/bin/sh\nprintf '%s\\n' "$*" >> "${path.join(root, 'gh.log')}"\nexit 1\n`);
    chmodSync(stub, 0o755);
    env.PATH = `${bin}${path.delimiter}${env.PATH ?? ''}`;
  }
  return {
    ...env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: gitconfig, GIT_ALLOW_PROTOCOL: 'file', GH_CONFIG_DIR: ghDir, TMPDIR: tmp, ...extra,
  };
}

// runUpdate({ entry, args, root, cwd, env }): the one way these tests start an update entry point: the module
// (entry 'module'), or a frozen reference materialized under the root (entry 'sh' or 'ps1', through bash or pwsh).
export function runUpdate({ entry = 'module', args = [], root, cwd = root, env = {}, script = MODULE, stdio = 'pipe' }) {
  const runEnv = prepareEnv(root, env);
  assert.equal(runEnv.GIT_ALLOW_PROTOCOL, 'file');
  assert.ok(path.isAbsolute(runEnv.GH_CONFIG_DIR) && readdirSync(runEnv.GH_CONFIG_DIR).length === 0, 'GH_CONFIG_DIR is an empty scratch directory');
  assertRepoUnderRoot(args, root, cwd);
  let file = process.execPath;
  let argv = [script, ...args];
  if (entry === 'sh' || entry === 'ps1') {
    const refs = materializeUpdateReference(ROOT, path.join(root, `ref-${entry}`));
    file = entry === 'sh' ? 'bash' : 'pwsh';
    argv = entry === 'sh' ? [refs.sh, ...args] : ['-NoProfile', '-NonInteractive', '-File', refs.ps1, ...args];
  }
  return spawnSync(file, argv, { cwd, env: runEnv, encoding: 'utf8', stdio });
}

// --- TEST-3960 ---------------------------------------------------------------------------------

// The forbidden words are assembled from parts so that this file itself holds none of them.
const STOP = 'Stop-' + 'Process';
const TASKK = 'task' + 'kill';
const FORBIDDEN = ['dock' + 'er', 'pk' + 'ill', 'kill' + 'all'];

// forbiddenCalls(source): lines that call a forbidden tool: the word first on a statement (a Windows
// executable suffix or a PowerShell call operator or Start-Process in front included), the first string
// argument of a process-starting call, or a PowerShell kill by name (Stop-Process -Name, taskkill /IM).
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
const UPDATE_ENTRY = /\b(MODULE|REFERENCE_SH|REFERENCE_PS1)\b|aai-update\.(mjs|sh|ps1)|refs\.(sh|ps1)/;

// invocationProblems(source): the JS rule of D-SAFETY: a spawnSync call that names an update entry point must be
// the one inside runUpdate, and runUpdate must set GIT_ALLOW_PROTOCOL to file, set GH_CONFIG_DIR and check the
// repo argument. A source with no runUpdate has no invocation to check.
export function invocationProblems(source) {
  const problems = [];
  const from = source.indexOf('export function runUpdate(');
  const bodyEnd = from < 0 ? -1 : source.indexOf('\n}\n', from);
  for (const call of spawnCalls(source)) {
    const inside = from >= 0 && call.at > from && call.at < bodyEnd;
    if (!inside && UPDATE_ENTRY.test(call.text)) problems.push(`an update entry point is started outside runUpdate: ${call.text.slice(0, 70)}`);
  }
  if (from >= 0) {
    const body = source.slice(from, bodyEnd);
    if (!body.includes('prepareEnv(')) problems.push('runUpdate does not build its environment with prepareEnv');
    if (!body.includes('assertRepoUnderRoot(')) problems.push('runUpdate does not check the repo argument against the scratch root');
    const prep = source.slice(source.indexOf('export function prepareEnv('), from);
    if (!/GIT_ALLOW_PROTOCOL: 'file'/.test(prep)) problems.push('prepareEnv does not set GIT_ALLOW_PROTOCOL to file');
    if (!/GH_CONFIG_DIR: ghDir/.test(prep)) problems.push('prepareEnv does not set GH_CONFIG_DIR');
  }
  return problems;
}

// shellInvocationProblems(source): the same rule for a bash suite: a line that runs an update entry point through
// bash, sh, dash, node or pwsh must sit inside the run_update function, which sets the same environment.
export function shellInvocationProblems(source) {
  const problems = [];
  const lines = source.split('\n');
  const entry = /\b(bash|sh|dash|node|pwsh)\s+("?\$\{?(MJS|SH_LAUNCHER|PS1_LAUNCHER|REFERENCE_SH|REFERENCE_PS1)\b|\S*aai-update\.(sh|mjs|ps1))/;
  const open = lines.findIndex((l) => /^run_update\(\) \{/.test(l));
  const close = open < 0 ? -1 : lines.findIndex((l, i) => i > open && l === '}');
  lines.forEach((line, i) => {
    if (/^\s*#/.test(line) || !entry.test(line)) return;
    if (!(open >= 0 && i > open && i < close)) problems.push(`${i + 1}: an update entry point is run outside run_update: ${line.trim().slice(0, 70)}`);
  });
  if (open >= 0) {
    const body = lines.slice(open, close + 1).join('\n');
    if (!body.includes('GIT_ALLOW_PROTOCOL=file')) problems.push('run_update does not set GIT_ALLOW_PROTOCOL=file');
    if (!body.includes('GH_CONFIG_DIR=')) problems.push('run_update does not set GH_CONFIG_DIR');
  }
  return problems;
}

describe('TEST-3960 scratch safety and the frozen references', () => {
  test('TEST-3960 removeOwnScratch refuses each unsafe path', () => {
    const base = scratch('refuse-');
    const unmarked = path.join(base, 'aai-up-unmarked');
    mkdirSync(unmarked);
    const foreign = path.join(base, 'foreign-name');
    mkdirSync(foreign);
    writeFileSync(path.join(foreign, OWN_MARKER_FILE), `${process.pid}\n`);
    const nonNumeric = path.join(base, 'aai-up-badmarker');
    mkdirSync(nonNumeric);
    writeFileSync(path.join(nonNumeric, OWN_MARKER_FILE), 'not-a-pid\n');
    assert.throws(() => removeOwnScratch(''), /empty path/);
    assert.throws(() => removeOwnScratch(undefined), /empty path/);
    assert.throws(() => removeOwnScratch('aai-up-relative'), /relative path/);
    assert.throws(() => removeOwnScratch(foreign), /own prefix/);
    assert.throws(() => removeOwnScratch(path.join(base, 'aai-up-missing')), /does not exist/);
    assert.throws(() => removeOwnScratch(unmarked), /marker/);
    assert.throws(() => removeOwnScratch(nonNumeric), /marker/);
    assert.throws(() => removeOwnScratchAll([]), /empty list/);
    for (const kept of [foreign, unmarked, nonNumeric]) assert.ok(existsSync(kept), `${kept} must survive`);
  });

  test('TEST-3960 removeOwnScratch refuses a path outside the temp directory and a symlink', () => {
    const base = scratch('outside-');
    const marked = path.join(base, 'aai-up-marked');
    mkdirSync(marked);
    writeFileSync(path.join(marked, OWN_MARKER_FILE), `${process.pid}\n`);
    // a child whose temp directory is a sub-directory: the marked directory then lies outside it
    const childTmp = path.join(base, 'childtmp');
    mkdirSync(childTmp);
    const helperUrl = pathToFileURL(path.join(HERE, 'update-reference.mjs')).href;
    const code = `import(${JSON.stringify(helperUrl)}).then((m) => { try { m.removeOwnScratch(${JSON.stringify(marked)}); console.log('REMOVED'); } catch (e) { console.log(e.message); } });`;
    const r = spawnSync(process.execPath, ['-e', code], {
      encoding: 'utf8', env: { ...process.env, TMPDIR: childTmp, TMP: childTmp, TEMP: childTmp },
    });
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /outside the temp directory/);
    assert.ok(existsSync(marked), 'the outside directory must survive');
    // a symlink with the prefix is refused and its target survives
    const link = path.join(base, 'aai-up-link');
    symlinkSync(marked, link);
    assert.throws(() => removeOwnScratch(link), /not a real directory/);
    assert.ok(existsSync(marked));
  });

  test('TEST-3960 removeOwnScratch removes a marked own directory and createOwnScratch marks it', () => {
    const dir = createOwnScratch('own-');
    assert.ok(path.basename(dir).startsWith('aai-up-own-'));
    assert.match(readFileSync(path.join(dir, OWN_MARKER_FILE), 'utf8'), /^[0-9]+\n$/);
    writeFileSync(path.join(dir, 'file'), 'x');
    removeOwnScratch(dir);
    assert.ok(!existsSync(dir));
  });

  test('TEST-3960 both reference copies hash to their pins and equal the pinned commit', () => {
    assert.match(REFERENCE_SH_SHA256, /^[0-9a-f]{64}$/);
    assert.match(REFERENCE_PS1_SHA256, /^[0-9a-f]{64}$/);
    for (const [rel, want, name] of [[REFERENCE_SH, REFERENCE_SH_SHA256, 'aai-update.sh'], [REFERENCE_PS1, REFERENCE_PS1_SHA256, 'aai-update.ps1']]) {
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

  test('TEST-3960 materializeUpdateReference verifies both hashes and writes the two twins with their modes', () => {
    const into = path.join(scratch('mat-'), 'tree');
    const dests = materializeUpdateReference(ROOT, into);
    assert.equal(dests.sh, path.join(into, '.aai', 'scripts', 'aai-update.sh'));
    assert.equal(dests.ps1, path.join(into, '.aai', 'scripts', 'aai-update.ps1'));
    assert.equal(sha256File(dests.sh), REFERENCE_SH_SHA256);
    assert.equal(sha256File(dests.ps1), REFERENCE_PS1_SHA256);
    assert.equal(statSync(dests.sh).mode & 0o777, 0o755);
    assert.equal(statSync(dests.ps1).mode & 0o777, 0o644);
    assert.deepEqual(listTree(path.join(into, '.aai')).sort(), ['scripts', 'scripts/aai-update.ps1', 'scripts/aai-update.sh'], 'no sibling is copied');
    // an edited copy of either twin fails by naming the file
    for (const rel of [REFERENCE_SH, REFERENCE_PS1]) {
      const fakeFrom = path.join(scratch('mat-bad-'), 'from');
      for (const r of [REFERENCE_SH, REFERENCE_PS1]) {
        mkdirSync(path.dirname(path.join(fakeFrom, r)), { recursive: true });
        writeFileSync(path.join(fakeFrom, r), readFileSync(path.join(ROOT, r)));
      }
      writeFileSync(path.join(fakeFrom, rel), 'edited\n');
      assert.throws(() => materializeUpdateReference(fakeFrom, path.join(scratch('mat-bad2-'), 'x')), (e) => e.message.includes(path.join(fakeFrom, rel)) && /hashes to/.test(e.message));
    }
  });

  test('TEST-3960 the new test files hold no call of a container tool or a kill by pattern', () => {
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
    assert.equal(forbiddenCalls(`spawnSync('${d}', ['ps'])\n`).length, 1);
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

  test('TEST-3960 the scanned list holds every update-on-node test file that exists', () => {
    // Files of this ride's naming under tests/skills and its lib; the pre-existing update suites and Pester file are not new.
    const exempt = new Set(['test-aai-update.sh', 'test-aai-update-check.sh', 'aai-update.Tests.ps1']);
    const found = [];
    for (const dir of [path.join(ROOT, 'tests', 'skills'), HERE]) {
      for (const name of readdirSync(dir)) {
        if (/(^|[^a-z])(aai-)?update(-node|-reference|-fixtures|\.test)/.test(name) && !exempt.has(name) && statSync(path.join(dir, name)).isFile()) found.push(path.join(dir, name));
      }
    }
    for (const f of found) assert.ok(NEW_TEST_FILES.includes(f), `${f} is a test file of this ride and must be added to NEW_TEST_FILES`);
    for (const f of NEW_TEST_FILES) assert.ok(found.includes(f), `${f} is listed but not found by name`);
  });

  test('TEST-3960 every update invocation sets the network-free environment and a repo under the scratch root', () => {
    for (const file of NEW_TEST_FILES) {
      const src = readFileSync(file, 'utf8');
      const problems = file.endsWith('.sh') ? shellInvocationProblems(src) : invocationProblems(src);
      assert.deepEqual(problems, [], path.basename(file));
    }
    // the JS helper has all three properties
    const mine = readFileSync(path.join(HERE, 'aai-update.test.mjs'), 'utf8');
    assert.ok(mine.includes('export function runUpdate('), 'the invocation helper exists');
    assert.ok(mine.includes("GIT_ALLOW_PROTOCOL: 'file'") && mine.includes('GH_CONFIG_DIR: ghDir'));
    // positive controls for both scanners
    assert.equal(invocationProblems(`${SPAWN}(process.execPath, [MODULE, '-h'], {});\n`).length, 1);
    assert.equal(invocationProblems(`${SPAWN}('bash', [path.join(root, 'aai-update.sh')], {});\n`).length, 1);
    assert.equal(invocationProblems(`${SPAWN}('git', ['status'], {});\n`).length, 0);
    assert.equal(invocationProblems(`${mine.replace("GIT_ALLOW_PROTOCOL: 'file'", "GIT_ALLOW_PROTOCOL: 'all'")}`).length, 1);
    assert.equal(invocationProblems(`${mine.replace('GH_CONFIG_DIR: ghDir', 'GH_X: ghDir')}`).length, 1);
    assert.equal(invocationProblems(mine.replace('  assertRepoUnderRoot(args, root, cwd);\n  let file', '  let file')).length, 1);
    assert.equal(shellInvocationProblems('bash "$SH_LAUNCHER" --dry-run\n').length, 1);
    assert.equal(shellInvocationProblems('out="$(node "$MJS" -h)"\n').length, 1);
    assert.equal(shellInvocationProblems('# bash "$MJS" in a comment\n[[ -f "$MJS" ]]\nMJS="$PROJECT_ROOT/x"\n').length, 0);
    assert.equal(shellInvocationProblems('run_update() {\n  GIT_ALLOW_PROTOCOL=file GH_CONFIG_DIR="$d" bash "$SH_LAUNCHER" "$@"\n}\n').length, 0);
    assert.equal(shellInvocationProblems('run_update() {\n  bash "$SH_LAUNCHER" "$@"\n}\n').length, 2);
  });

  test('TEST-3960 assertRepoUnderRoot accepts a repo under the root and refuses every other one', () => {
    const root = scratch('guard-');
    const target = path.join(root, 'target');
    mkdirSync(target);
    mkdirSync(path.join(root, 'src'));
    const ok = [
      ['--repo', path.join(root, 'src')], [`--repo=${path.join(root, 'src')}`], ['-Repo', '../src'], ['-repo', path.join(root, 'src')],
      ['--repo', `file://${path.join(root, 'src')}`], ['--dry-run', '--repo', 'acme/foo'], ['-DryRun', '--repo=acme/foo'], ['--dry-run', '--repo'], ['--ref', 'dev'], [],
    ];
    for (const args of ok) assertRepoUnderRoot(args, root, target);
    const bad = [
      ['--repo', ROOT], ['--repo', '/'], ['--repo', '../..'], ['--repo', 'acme/foo'], ['--repo', 'https://github.com/acme/foo.git'],
      ['--repo', `file://${ROOT}`], [`--repo=${ROOT}`], ['-Repo', path.dirname(root)], ['--repo', path.join(root, '..', 'elsewhere')],
    ];
    for (const args of bad) assert.throws(() => assertRepoUnderRoot(args, root, target), `${args.join(' ')} must be refused`);
    // the root itself must be an own marked scratch directory
    assert.throws(() => assertRepoUnderRoot([], ROOT), /own prefix/);
    const unmarked = path.join(root, 'aai-up-unmarked');
    mkdirSync(unmarked);
    assert.throws(() => assertRepoUnderRoot([], unmarked), /marker/);
  });

  test('TEST-3960 prepareEnv builds the network-free environment', () => {
    const root = scratch('env-');
    const leaky = { AAI_ROLE: 'x', AAI_GIT_WRITE: '1', GH_TOKEN: 't', GITHUB_TOKEN: 't', GH_ENTERPRISE_TOKEN: 't', GITHUB_ENTERPRISE_TOKEN: 't' };
    const saved = {};
    for (const [k, v] of Object.entries(leaky)) { saved[k] = process.env[k]; process.env[k] = v; }
    let env;
    try {
      env = prepareEnv(root, { EXTRA: '1' });
    } finally {
      for (const [k, v] of Object.entries(saved)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; }
    }
    for (const k of Object.keys(leaky)) assert.ok(!(k in env), `${k} is removed`);
    assert.equal(env.GIT_ALLOW_PROTOCOL, 'file');
    assert.equal(env.GIT_CONFIG_NOSYSTEM, '1');
    assert.equal(env.EXTRA, '1');
    assert.deepEqual(readdirSync(env.GH_CONFIG_DIR), []);
    assert.equal(readFileSync(env.GIT_CONFIG_GLOBAL, 'utf8'), '');
    assert.ok(under(env.TMPDIR, root) && under(env.GH_CONFIG_DIR, root));
    if (process.platform !== 'win32') {
      assert.ok(env.PATH.startsWith(path.join(root, 'bin')), 'the gh stub directory is first on PATH');
      const r = spawnSync('gh', ['repo', 'clone', 'a/b'], { env, encoding: 'utf8' });
      assert.equal(r.status, 1);
      assert.equal(readFileSync(path.join(root, 'gh.log'), 'utf8'), 'repo clone a/b\n');
    }
  });
});

// --- TEST-3961 ---------------------------------------------------------------------------------

const EXPORTS = [
  'parseArgs', 'resolveBase', 'normSlug', 'canonicalGuard', 'cloneUrl', 'resolveSource', 'resolveRunner',
  'syncCommand', 'renderDryRun', 'changedFiles', 'pinLines', 'latestConflict', 'renderEvidence', 'doctorReport',
  'renderNext', 'createOwnTemp', 'removeOwnTemp', 'run', 'main',
];

const ANCHORS = [
  "const DEFAULT_REPO = 'goodwind-cz/aai';",
  "const DEFAULT_REF = 'main';",
  'const EXIT_USAGE = 1;',
  'const EXIT_REFUSED = 2;',
  'const EXIT_FETCH = 3;',
  'const EXIT_MALFORMED = 4;',
  "const TMP_PREFIX = 'aai-src.';",
  "const SRC_SUBDIR = 'src';",
  "const RUNNER_ENV = 'AAI_UPDATE_SYNC_RUNNER';",
  "const SLUG_CASE_FLAGS = 'i';",
  "const PIN_KEYWORDS = ['source', 'version', 'commit', 'canonical', 'ref'];",
  "const ANON_CLONE = ['-c', 'credential.helper=', '-c', 'http.https://github.com/.extraheader='];",
  "const HELPER_REL = '.aai/scripts/update-doctor-report.mjs';",
  'const runChild = (file, args, opts) => spawnSync(file, args, opts);',
  'const writeFd = (fd) => (s) => { fs.writeSync(fd, s); };',
  '  if (!state.keepTemp && state.tmp) removeOwnTemp(state.tmp, state.created);',
  'export function doctorReport(',
];

const NETWORK_MODULES = ['http', 'https', 'net', 'tls', 'dgram'];

// moduleShapeProblems(source): the static D-MODULE rules, as a list of problems (empty when clean).
export function moduleShapeProblems(source) {
  const problems = [];
  const specs = [];
  for (const m of source.matchAll(/^\s*import\s[^;]*?\sfrom\s+['"]([^'"]+)['"]/gm)) specs.push(m[1]);
  for (const m of source.matchAll(/^\s*import\s+['"]([^'"]+)['"]/gm)) specs.push(m[1]);
  for (const m of source.matchAll(/\b(?:import|require)\(\s*['"]([^'"]+)['"]/g)) specs.push(m[1]);
  for (const spec of specs) {
    if (!spec.startsWith('node:')) problems.push(`import of ${spec} is not a node: specifier`);
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
  if (/\b(exec|execSync|execFile|execFileSync|spawn|fork)\s*\(/.test(source)) problems.push('a process is started other than through spawnSync');
  if (/shell\s*:\s*true/.test(source)) problems.push('a spawn asks for a shell');
  for (const word of ['AAI_UPDATE_RELOCATED', 'copyFileSync', 'cpSync', 'node missing', 'aai-update.XXXXXX']) {
    if (source.includes(word)) problems.push(`holds relocation or twin text: ${word}`);
  }
  return problems;
}

describe('TEST-3961 module shape', () => {
  test('TEST-3961 importing the module creates nothing and prints nothing', () => {
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

  test('TEST-3961 the module exports the D-MODULE names', async () => {
    const mod = await import(MODULE_URL);
    for (const name of EXPORTS) assert.equal(typeof mod[name], 'function', `export ${name}`);
  });

  test('TEST-3961 the module imports only node: specifiers and holds each anchor once', () => {
    const source = readFileSync(MODULE, 'utf8');
    assert.deepEqual(moduleShapeProblems(source), []);
    assert.equal(spawnCalls(source).length, 1, 'the module has its one spawn call');
  });

  test('TEST-3961 the shape checks report each violation they exist for', () => {
    const good = readFileSync(MODULE, 'utf8');
    const has = (src, re) => moduleShapeProblems(src).some((p) => re.test(p));
    assert.ok(has(`${good}\nimport fs2 from 'fs';\n`, /not a node: specifier/));
    for (const m of NETWORK_MODULES) assert.ok(has(`${good}\nimport x from 'node:${m}';\n`, /network module/), m);
    assert.ok(has(`${good}\nconst DEFAULT_REF = 'main';\n`, /anchor appears 2 times/));
    assert.ok(has(good.replace("const SRC_SUBDIR = 'src';\n", ''), /anchor appears 0 times/));
    assert.ok(has(`${good}\nspawnSync('git', []);\n`, /spawnSync is called 2 times/));
    assert.ok(has(good.replace('=> spawnSync(file, args, opts)', '=> opts'), /spawnSync is called 0 times|anchor appears 0 times/));
    assert.ok(has(`${good}\nprocess.stdout.write('x');\n`, /process\.stdout/));
    assert.ok(has(`${good}\n// process.stderr\n`, /process\.stdout or process\.stderr/));
    assert.ok(has(`${good}\nprocess.stdin.on('data', () => {});\n`, /standard input/));
    assert.ok(has(`${good}\nexecSync('ls');\n`, /other than through spawnSync/));
    assert.ok(has(`${good}\n// node missing\n`, /relocation or twin text/));
    assert.ok(has(`${good}\n// aai-update.XXXXXX\n`, /relocation or twin text/));
    assert.ok(has(`${good}\nfs.copyFileSync(a, b);\n`, /relocation or twin text/));
    assert.ok(has(`${good}\n// café\n`, /non-ASCII/));
    assert.deepEqual(moduleShapeProblems(good), []);
  });

  test('TEST-3961 the main guard runs the module through a symbolic link and never on import', () => {
    const cwd = scratch('guard-');
    const link = path.join(cwd, 'aai-update-link.mjs');
    symlinkSync(MODULE, link);
    const r = runUpdate({ script: link, args: ['-h'], root: cwd });
    assert.equal(r.status, 0, r.stderr);
    assert.ok(r.stdout.startsWith('AAI layer updater'), 'main ran through the link');
    // a plain import through a different entry script runs nothing
    const r2 = spawnSync(process.execPath, ['--input-type=module', '-e', `import(${JSON.stringify(MODULE_URL)}).then(() => process.exit(0));`], { cwd, encoding: 'utf8' });
    assert.equal(r2.stdout, '');
  });

  test('TEST-3961 output goes through descriptors 1 and 2 and the real entry point never reads standard input', () => {
    const cwd = scratch('fds-');
    // stdin closed: the run still completes (no standard input read)
    const r = runUpdate({ args: ['--bogus'], root: cwd, stdio: ['ignore', 'pipe', 'pipe'] });
    assert.equal(r.status, 1);
    assert.equal(r.stderr, 'Unknown argument: --bogus\n');
    assert.ok(r.stdout.length > 0);
  });
});

// --- TEST-3962 ---------------------------------------------------------------------------------

const cap = () => {
  const o = { out: '', err: '', spawned: [] };
  o.io = { out: (s) => { o.out += s; }, err: (s) => { o.err += s; }, spawn: (...a) => { o.spawned.push(a); return { status: 0 }; } };
  return o;
};

const DR1_LINES = [
  '  powershell -NoProfile -File .aai/scripts/aai-update.ps1 [-Repo X] [-Ref Y] [-DryRun] [-KeepTemp] [-Force]   # the long flags work too',
  'Requires Node.js 22 or later; both launchers run .aai/scripts/aai-update.mjs.',
];

// referenceHelp(): the lines 2 to 16 of the frozen bash twin, the way its usage function prints them
// (the comment block with the leading `# ` removed).
function referenceHelp() {
  const lines = readFileSync(path.join(ROOT, REFERENCE_SH), 'utf8').split('\n');
  const out = [];
  for (const line of lines.slice(1)) {
    if (!line.startsWith('#')) break;
    out.push(line.replace(/^# ?/, ''));
  }
  return out.join('\n') + '\n';
}

const expectedHelp = () => referenceHelp() + DR1_LINES.join('\n') + '\n';

describe('TEST-3962 arguments, help and base directory', () => {
  test('TEST-3962 every accepted form is read, in any order, and the last occurrence wins', async () => {
    const { parseArgs } = await import(MODULE_URL);
    const D = { repo: 'goodwind-cz/aai', ref: 'main', dryRun: false, keepTemp: false, force: false, outcome: 'run', arg: '' };
    assert.deepEqual(parseArgs([]), D, 'defaults');
    assert.deepEqual(parseArgs(['--repo', 'a/b']), { ...D, repo: 'a/b' });
    assert.deepEqual(parseArgs(['--ref', 'dev']), { ...D, ref: 'dev' });
    assert.deepEqual(parseArgs(['--repo=a/b', '--ref=dev']), { ...D, repo: 'a/b', ref: 'dev' });
    assert.deepEqual(parseArgs(['--dry-run', '--keep-temp', '--force']), { ...D, dryRun: true, keepTemp: true, force: true });
    assert.deepEqual(parseArgs(['-Repo', 'a/b', '-Ref', 'dev', '-DryRun', '-KeepTemp', '-Force']), { ...D, repo: 'a/b', ref: 'dev', dryRun: true, keepTemp: true, force: true });
    // mixed order: long, equals and PowerShell forms together
    const all = { ...D, repo: 'x/y', ref: 'dev', dryRun: true, keepTemp: true, force: true };
    const orders = [
      ['--force', '-Repo', 'x/y', '--ref=dev', '-DryRun', '--keep-temp'],
      ['-KeepTemp', '--dry-run', '--repo=x/y', '-Force', '-Ref', 'dev'],
      ['--ref', 'dev', '-Force', '--keep-temp', '--repo', 'x/y', '--dry-run'],
    ];
    for (const argv of orders) assert.deepEqual(parseArgs(argv), all, argv.join(' '));
    // the last occurrence of a setting wins, whatever the spelling (DR-4: left to right)
    assert.equal(parseArgs(['--repo', 'a/a', '-Repo', 'b/b', '--repo=c/c']).repo, 'c/c');
    assert.equal(parseArgs(['--repo=c/c', '-Repo', 'b/b']).repo, 'b/b');
    assert.equal(parseArgs(['-Repo', 'b/b', '--repo', 'a/a']).repo, 'a/a');
    assert.equal(parseArgs(['--ref=one', '--ref', 'two', '-Ref', 'three']).ref, 'three');
    // a switch repeated is still on; a value may start with a dash and is taken as the value
    assert.equal(parseArgs(['--force', '--force']).force, true);
    assert.equal(parseArgs(['--repo', '--dry-run']).repo, '--dry-run');
    assert.equal(parseArgs(['--repo', '--dry-run']).dryRun, false);
    // a value with an equals sign inside it keeps the rest
    assert.equal(parseArgs(['--repo=a=b/c']).repo, 'a=b/c');
    // negative controls: nothing is set by a flag that was not given
    assert.equal(parseArgs(['--dry-run']).force, false);
    assert.equal(parseArgs(['--force']).dryRun, false);
  });

  test('TEST-3962 the PowerShell names match case-insensitively and exactly; abbreviations and other spellings are unknown', async () => {
    const { parseArgs } = await import(MODULE_URL);
    for (const flag of ['-repo', '-REPO', '-rEpO']) assert.equal(parseArgs([flag, 'a/b']).repo, 'a/b', flag);
    for (const flag of ['-ref', '-REF']) assert.equal(parseArgs([flag, 'dev']).ref, 'dev', flag);
    for (const [flag, key] of [['-dryrun', 'dryRun'], ['-DRYRUN', 'dryRun'], ['-keeptemp', 'keepTemp'], ['-KEEPTEMP', 'keepTemp'], ['-force', 'force'], ['-FORCE', 'force']]) {
      assert.equal(parseArgs([flag])[key], true, flag);
    }
    // not accepted: abbreviations, the other parameter names, long flags in another case, the colon and equals forms of the native names
    for (const bad of ['-Rep', '-R', '-Dry', '-Keep', '-F', '-Verbose', '-Help', '-H', '--REPO', '--Dry-Run', '--FORCE', '--repos', '--dryrun', '-Repo=x', '-Ref=x', '-DryRun=1', '--force=1', '--dry-run=1', 'extra', '-']) {
      const r = parseArgs([bad]);
      assert.equal(r.outcome, 'unknown', bad);
      assert.equal(r.arg, bad);
    }
  });

  test('TEST-3962 help is decided at its position and wins over a later problem', async () => {
    const { parseArgs } = await import(MODULE_URL);
    assert.equal(parseArgs(['-h']).outcome, 'help');
    assert.equal(parseArgs(['--help']).outcome, 'help');
    assert.equal(parseArgs(['--dry-run', '-h', '--bogus']).outcome, 'help');
    assert.equal(parseArgs(['--repo', 'a/b', '--help', '--repo']).outcome, 'help');
    assert.equal(parseArgs(['--bogus', '-h']).outcome, 'unknown');
    assert.equal(parseArgs(['--repo', '-h']).outcome, 'run', 'a value that looks like help is a value');
    assert.equal(parseArgs(['--repo']).outcome, 'value');
    assert.equal(parseArgs(['--repo', '-h']).repo, '-h');
  });

  test('TEST-3962 help text is the bash reference help plus the two DR-1 lines, on stdout, exit 0', async () => {
    const { run, HELP_TEXT } = await import(MODULE_URL);
    const want = expectedHelp();
    assert.equal(HELP_TEXT, want);
    assert.equal(want.split('\n').length, 15 + 2 + 1, '15 reference lines, 2 added, one trailing empty piece');
    for (const flag of ['-h', '--help']) {
      const c = cap();
      assert.equal(run([flag], c.io), 0);
      assert.equal(c.out, want);
      assert.equal(c.err, '');
      assert.deepEqual(c.spawned, []);
    }
    // help wins over a later problem and exits 0 with nothing on stderr
    const c = cap();
    assert.equal(run(['--dry-run', '-h', '--bogus'], c.io), 0);
    assert.equal(c.out, want);
    assert.equal(c.err, '');
    // against the real reference: its own help, byte for byte, then the two lines (run in its own scratch)
    const root = scratch('refhelp-');
    const ref = runUpdate({ entry: 'sh', args: ['-h'], root });
    assert.equal(ref.status, 0, ref.stderr);
    assert.equal(ref.stdout + DR1_LINES.join('\n') + '\n', want);
    assert.deepEqual(readdirSync(path.join(root, 'tmp')), [], 'the reference left nothing in TMPDIR');
    // through the real entry point
    const r = runUpdate({ args: ['--help'], root });
    assert.equal(r.status, 0, r.stderr);
    assert.equal(r.stdout, want);
    assert.equal(r.stderr, '');
  });

  test('TEST-3962 an unknown argument exits 1 with the error on stderr, the help on stdout and no child started', async () => {
    const { run } = await import(MODULE_URL);
    const want = expectedHelp();
    for (const [argv, bad] of [[['--bogus'], '--bogus'], [['--dry-runn'], '--dry-runn'], [['--dry-run', '--bogus', '--force'], '--bogus'], [['--repo', 'a/b', 'stray'], 'stray'], [['-Rep', 'x'], '-Rep']]) {
      const c = cap();
      assert.equal(run(argv, c.io), 1, argv.join(' '));
      assert.equal(c.err, `Unknown argument: ${bad}\n`);
      assert.equal(c.out, want);
      assert.deepEqual(c.spawned, [], 'nothing is started');
    }
    // the reference prints the same streams for an unknown argument: error line on stderr, its usage on stdout, exit 1
    const root = scratch('refunknown-');
    const ref = runUpdate({ entry: 'sh', args: ['--bogus'], root });
    const mod = runUpdate({ args: ['--bogus'], root });
    assert.equal(ref.status, 1);
    assert.equal(mod.status, 1);
    assert.equal(mod.stderr, ref.stderr);
    assert.equal(mod.stdout, ref.stdout + DR1_LINES.join('\n') + '\n');
    assert.equal(mod.stderr, 'Unknown argument: --bogus\n');
    // negative control: a valid dry-run argument list is not an unknown argument
    const ok = runUpdate({ args: ['--dry-run', '--force', '--keep-temp'], root });
    assert.ok(!ok.stderr.includes('Unknown argument'));
    assert.deepEqual(listTree(path.join(root, 'tmp')), [], 'a usage error leaves nothing in TMPDIR');
  });

  test('TEST-3962 a value flag at the end or with an empty value exits 1 with the DR-3 line and starts nothing', async () => {
    const { run } = await import(MODULE_URL);
    const cases = [
      [['--repo'], '--repo'], [['--ref'], '--ref'], [['--ref', ''], '--ref'], [['--repo', ''], '--repo'], [['--repo='], '--repo'], [['--ref='], '--ref'],
      [['-Repo'], '-Repo'], [['-ref', ''], '-ref'], [['--dry-run', '--repo'], '--repo'], [['--repo', 'a/b', '--ref'], '--ref'], [['-REPO'], '-REPO'],
    ];
    for (const [argv, flag] of cases) {
      const c = cap();
      assert.equal(run(argv, c.io), 1, argv.join(' '));
      assert.equal(c.err, `aai-update: ${flag} needs a value\n`);
      assert.equal(c.out, '');
      assert.deepEqual(c.spawned, []);
    }
    // through the real entry point, with the exit code and streams of a process
    const root = scratch('novalue-');
    const r = runUpdate({ args: ['--dry-run', '--repo'], root });
    assert.equal(r.status, 1);
    assert.equal(r.stdout, '');
    assert.equal(r.stderr, 'aai-update: --repo needs a value\n');
    assert.deepEqual(listTree(path.join(root, 'tmp')), []);
    // a flag that has its value is fine
    assert.ok(!runUpdate({ args: ['--ref', 'dev', '--dry-run'], root }).stderr.includes('needs a value'));
  });

  test('TEST-3962 resolveBase keeps the logical path when PWD names the working directory', async () => {
    const { resolveBase } = await import(MODULE_URL);
    const base = scratch('base-');
    const real = path.join(base, 'real');
    const link = path.join(base, 'link');
    mkdirSync(path.join(real, 'sub'), { recursive: true });
    symlinkSync(real, link);
    assert.equal(resolveBase('', { PWD: link }, real), link);
    assert.equal(resolveBase('sub', { PWD: link }, real), path.join(link, 'sub'));
    // a relative path is resolved lexically: dot-dot goes up the logical path
    assert.equal(resolveBase(path.join('..', 'src'), { PWD: link }, real), path.join(base, 'src'));
    assert.equal(resolveBase(path.join('a', '..', 'b'), { PWD: link }, real), path.join(link, 'b'));
    assert.equal(resolveBase('..', { PWD: link }, real), base);
    // an absolute path ignores the base
    assert.equal(resolveBase(base, { PWD: link }, real), base);
    // a PWD with a trailing slash or dot segments is cleaned
    assert.equal(resolveBase('', { PWD: `${link}/` }, real), link);
    assert.equal(resolveBase('', { PWD: `${link}/sub/..` }, real), link);
  });

  test('TEST-3962 resolveBase uses the working directory for a stale, relative or absent PWD', async () => {
    const { resolveBase } = await import(MODULE_URL);
    const base = scratch('stale-');
    const here = path.join(base, 'here');
    const other = path.join(base, 'other');
    mkdirSync(here);
    mkdirSync(other);
    assert.equal(resolveBase('', { PWD: other }, here), here);
    assert.equal(resolveBase('t', { PWD: other }, here), path.join(here, 't'));
    assert.equal(resolveBase(path.join('..', 'other'), { PWD: other }, here), other);
    assert.equal(resolveBase('', { PWD: path.join(base, 'missing') }, here), here);
    assert.equal(resolveBase('', { PWD: 'here' }, here), here);
    assert.equal(resolveBase('', {}, here), here);
    assert.equal(resolveBase('', { PWD: '' }, here), here);
    // the default arguments are the process environment and working directory
    assert.equal(resolveBase(), resolveBase('', process.env, process.cwd()));
  });

  test('TEST-3962 resolveBase ignores CDPATH', async () => {
    const { resolveBase } = await import(MODULE_URL);
    const base = scratch('cdpath-');
    const here = path.join(base, 'here');
    const elsewhere = path.join(base, 'elsewhere');
    mkdirSync(here);
    mkdirSync(path.join(elsewhere, 'proj'), { recursive: true });
    const env = { PWD: here, CDPATH: elsewhere };
    assert.equal(resolveBase('proj', env, here), path.join(here, 'proj'));
    assert.equal(resolveBase('', env, here), here);
    assert.ok(!existsSync(path.join(here, 'proj')), 'the CDPATH directory was not entered or created');
  });
});
