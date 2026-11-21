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
  chmodSync, existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, realpathSync, renameSync, statSync, symlinkSync, unlinkSync, rmdirSync, utimesSync, writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { after, describe, test } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { compareSnapshots, snapshotNormalized } from './install-parity.mjs';
import {
  EM_DASH, U_CASES, buildSource, buildTarget, git,
} from './aai-update-fixtures.mjs';
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
  path.join(HERE, 'aai-update-fixtures.mjs'),
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
export function prepareEnv(root, extra = {}, { gitWrapper = '' } = {}) {
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
    if (gitWrapper) {
      // U23 only: logs every clone, fails it unless the argv holds credential.helper=, else runs the real git.
      const wrap = path.join(bin, 'git');
      writeFileSync(wrap, `#!/bin/sh\nfor a in "$@"; do\n  case "$a" in clone) c=1 ;; credential.helper=) anon=1 ;; esac\ndone\nif [ -n "$c" ]; then\n  printf '%s\\n' "$*" >> "${path.join(root, 'git.log')}"\n  [ -n "$anon" ] || exit 1\nfi\nexec "${gitWrapper}" "$@"\n`);
      chmodSync(wrap, 0o755);
    }
    env.PATH = `${bin}${path.delimiter}${env.PATH ?? ''}`;
  }
  return {
    ...env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: gitconfig, GIT_ALLOW_PROTOCOL: 'file', GH_CONFIG_DIR: ghDir, TMPDIR: tmp, ...extra,
  };
}

// runUpdate({ entry, args, root, cwd, env }): the one way these tests start an update entry point: the module
// (entry 'module'), or a frozen reference materialized under the root (entry 'sh' or 'ps1', through bash or pwsh).
export function runUpdate({ entry = 'module', args = [], root, cwd = root, env = {}, script = MODULE, stdio = 'pipe', gitWrapper = '' }) {
  const runEnv = prepareEnv(root, env, { gitWrapper });
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
  return spawnSync(file, argv, { cwd, env: runEnv, encoding: 'utf8', stdio, timeout: 240000 });
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

// shellInvocationProblems(source): the same rule for a bash suite. A line that runs an update entry point must sit
// inside the run_update function, which sets the same environment and asserts a repo under the scratch root: a line
// outside it is flagged when it runs the entry point through bash, sh, dash, node or pwsh, or when it names an
// aai-update launcher or module together with an update argument (--repo, -Repo, --dry-run, -DryRun), whatever word
// precedes the path. A line that runs under a PATH without node ("$fakebin") starts no update and is exempt.
export function shellInvocationProblems(source) {
  const problems = [];
  const lines = source.split('\n');
  const entry = /\b(bash|sh|dash|node|pwsh)\s+("?\$\{?(MJS|SH_LAUNCHER|PS1_LAUNCHER|REFERENCE_SH|REFERENCE_PS1)\b|\S*aai-update\.(sh|mjs|ps1))/;
  const named = /aai-update\.(sh|ps1|mjs)\b.*(--repo\b|-Repo\b|--dry-run\b|-DryRun\b)/;
  const open = lines.findIndex((l) => /^run_update\(\) \{/.test(l));
  const close = open < 0 ? -1 : lines.findIndex((l, i) => i > open && l === '}');
  lines.forEach((line, i) => {
    if (/^\s*#/.test(line) || !(entry.test(line) || named.test(line))) return;
    if (line.includes('PATH="$fakebin"')) return;
    if (!(open >= 0 && i > open && i < close)) problems.push(`${i + 1}: an update entry point is run outside run_update: ${line.trim().slice(0, 70)}`);
  });
  if (open < 0) {
    problems.push('the suite has no run_update function');
  } else {
    const body = lines.slice(open, close + 1).join('\n');
    if (!body.includes('GIT_ALLOW_PROTOCOL=file')) problems.push('run_update does not set GIT_ALLOW_PROTOCOL=file');
    if (!body.includes('GH_CONFIG_DIR=')) problems.push('run_update does not set GH_CONFIG_DIR');
    if (!/case "\$src" in "\$work"\/\*\)/.test(body)) problems.push('run_update does not assert the repo under the scratch root');
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
    assert.equal(shellInvocationProblems('bash "$SH_LAUNCHER" --dry-run\n').length, 2);
    assert.equal(shellInvocationProblems('out="$(node "$MJS" -h)"\n').length, 2);
    const okBody = 'run_update() {\n  case "$src" in "$work"/*) ;; *) exit 1 ;; esac\n  GIT_ALLOW_PROTOCOL=file GH_CONFIG_DIR="$d" bash "$SH_LAUNCHER" "$@"\n}\n';
    assert.equal(shellInvocationProblems(`# bash "$MJS" in a comment\n[[ -f "$MJS" ]]\nMJS="$PROJECT_ROOT/x"\n${okBody}`).length, 0);
    assert.equal(shellInvocationProblems(okBody).length, 0);
    assert.equal(shellInvocationProblems('run_update() {\n  bash "$SH_LAUNCHER" "$@"\n}\n').length, 3);
    assert.equal(shellInvocationProblems('# no run_update at all\n').length, 1);
    // the committed bash suite: no problem as committed, and a problem for each property removed from run_update
    const suiteFile = NEW_TEST_FILES.find((f) => f.endsWith('test-aai-update-node.sh'));
    const suite = readFileSync(suiteFile, 'utf8');
    assert.ok(/^run_update\(\) \{/m.test(suite), 'the suite has run_update');
    assert.deepEqual(shellInvocationProblems(suite), []);
    assert.ok(shellInvocationProblems(suite.replace(' GIT_ALLOW_PROTOCOL=file', '')).length >= 1, 'GIT_ALLOW_PROTOCOL removed');
    assert.ok(shellInvocationProblems(suite.replace(' GH_CONFIG_DIR="$work/ghcfg"', '')).length >= 1, 'GH_CONFIG_DIR removed');
    assert.ok(shellInvocationProblems(suite.replace(/^ {2}case "\$src" in "\$work"\/\*\) ;;.*$/m, '')).length >= 1, 'the scratch-root assertion removed');
    // an update run outside run_update is flagged whatever word precedes the path
    assert.ok(shellInvocationProblems(`${suite}\nset -- pwsh -NoProfile -File .aai/scripts/aai-update.ps1 -Repo "$x" -Force\n`).length >= 1);
    assert.ok(shellInvocationProblems(`${suite}\n"$shell" .aai/scripts/aai-update.sh --repo "$x" --force\n`).length >= 1);
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
      assert.equal(await run([flag], c.io), 0);
      assert.equal(c.out, want);
      assert.equal(c.err, '');
      assert.deepEqual(c.spawned, []);
    }
    // help wins over a later problem and exits 0 with nothing on stderr
    const c = cap();
    assert.equal(await run(['--dry-run', '-h', '--bogus'], c.io), 0);
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
      assert.equal(await run(argv, c.io), 1, argv.join(' '));
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
      assert.equal(await run(argv, c.io), 1, argv.join(' '));
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

// --- run 2: the guard, the source and the temp lifecycle (TEST-3963 to TEST-3965) ----------------------------

// fakeSpawn(handler): the injected child seam. Every call is recorded; the handler returns the spawnSync-shaped
// result (status, error, stdout), or nothing for a plain success. The real module starts nothing through it.
function fakeSpawn(handler = () => null) {
  const calls = [];
  const spawn = (file, args, opts) => {
    const call = { file, args, opts };
    calls.push(call);
    return handler(call, calls.length - 1) ?? { status: 0, stdout: '' };
  };
  spawn.calls = calls;
  return spawn;
}

const isGuardRead = (c) => c.file === 'git' && c.args[0] === '-C' && c.args[2] === 'config';
const isSync = (c) => c.file === 'bash' && c.args[0].endsWith(`${path.sep}aai-sync.sh`);
const enoent = () => ({ status: null, error: Object.assign(new Error('spawn ENOENT'), { code: 'ENOENT' }) });
const IGNORE3 = ['ignore', 'ignore', 'ignore'];

// A scratch layout of one run: a target directory (the working directory), a temp directory and a source directory
// holding a stub sync script.
function layout(label) {
  const root = scratch(label);
  const target = path.join(root, 'target');
  const tmpdir = path.join(root, 'tmp');
  const source = path.join(root, 'src');
  mkdirSync(target);
  mkdirSync(tmpdir);
  mkdirSync(path.join(source, '.aai', 'scripts'), { recursive: true });
  writeFileSync(path.join(source, '.aai', 'scripts', 'aai-sync.sh'), '#!/bin/sh\nexit 0\n');
  return { root, target, tmpdir, source };
}

// runFake(mod, { argv, lay, origin, handler, platform }): one run of the module with an injected child seam; the
// guard's git read answers with the origin ('' means no origin), every other child goes to the handler.
async function runFake(mod, { argv, lay, origin = '', handler = () => null, platform = 'linux', env = {} }) {
  const o = { out: '', err: '' };
  const spawn = fakeSpawn((call, i) => {
    if (isGuardRead(call)) return origin === null ? enoent() : { status: origin === '' ? 1 : 0, stdout: origin === '' ? '' : `${origin}\n` };
    return handler(call, i);
  });
  o.spawn = spawn;
  o.code = await mod.run(argv, {
    out: (s) => { o.out += s; }, err: (s) => { o.err += s; }, env: { PWD: lay.target, ...env }, cwd: lay.target, spawn, tmpdir: lay.tmpdir, platform,
  });
  o.others = spawn.calls.filter((c) => !isGuardRead(c));
  o.temps = readdirSync(lay.tmpdir).filter((n) => n.startsWith('aai-src.'));
  return o;
}

// A clone handler: the attempts fail with the given results in order, the one that returns 'ok' plants a source
// holding the sync script at the destination it was given.
function cloneHandler(results, seen = []) {
  let attempt = 0;
  return (call) => {
    const isClone = (call.file === 'gh' && call.args[0] === 'repo') || (call.file === 'git' && call.args.includes('clone'));
    if (!isClone) return null;
    const dest = call.args.includes('--') ? call.args[3] : call.args[call.args.length - 1];
    const tmp = path.dirname(dest);
    seen.push({ call, dest, existed: existsSync(dest), tmpIno: statSync(tmp).ino, tmpEntries: readdirSync(tmp) });
    const r = results[attempt];
    attempt += 1;
    if (r === 'ok') {
      mkdirSync(path.join(dest, '.aai', 'scripts'), { recursive: true });
      writeFileSync(path.join(dest, '.aai', 'scripts', 'aai-sync.sh'), '#!/bin/sh\nexit 0\n');
      return { status: 0 };
    }
    mkdirSync(path.join(dest, 'partial'), { recursive: true });
    writeFileSync(path.join(dest, 'partial', 'pack'), 'x');
    return r;
  };
}

// --- TEST-3963 ---------------------------------------------------------------------------------

const REFUSAL = (origin) => `REFUSED: this project (${origin}) looks like the canonical AAI repo.\n`
  + '  /aai-update syncs AAI INTO a target project; update the canonical repo with normal git.\n'
  + '  Pass --force (or -Force) to override.\n';

describe('TEST-3963 canonical repo guard', () => {
  test('TEST-3963 normSlug reduces a slug, an https or ssh URL, an upper-case host or suffix and a doubled host', async () => {
    const { normSlug } = await import(MODULE_URL);
    const same = 'goodwind-cz/aai';
    for (const v of [
      'goodwind-cz/aai', 'Goodwind-CZ/AAI', 'https://github.com/goodwind-cz/aai', 'https://github.com/goodwind-cz/aai.git',
      'https://github.com/Goodwind-CZ/AAI.git', 'git@github.com:Goodwind-CZ/AAI.git', 'ssh://git@github.com/goodwind-cz/aai.git',
      'https://GITHUB.COM/goodwind-cz/aai.GIT', 'git@GitHub.com:goodwind-cz/aai.Git', 'https://github.com/github.com/goodwind-cz/aai',
      'https://github.com/github.com:goodwind-cz/aai.git', 'GITHUB.COM:Goodwind-CZ/AAI',
    ]) assert.equal(normSlug(v), same, v);
    assert.equal(normSlug('acme/foo.git'), 'acme/foo');
    assert.equal(normSlug('Acme/Foo'), 'acme/foo');
  });

  test('TEST-3963 normSlug is empty for a path, an empty value and anything that is not owner/repo', async () => {
    const { normSlug } = await import(MODULE_URL);
    for (const v of ['', undefined, null, '/tmp/x/src', '/abs/dir', 'a/b/c', 'solo', 'https://example.com/a/b', 'https://github.com/a/b/c', 'https://github.com/', 'github.com/', 'git@github.com:', '.git']) {
      assert.equal(normSlug(v), '', String(v));
    }
  });

  test('TEST-3963 a canonical target is refused with the three lines and exit 2 before any temp or sync', async () => {
    const mod = await import(MODULE_URL);
    const origins = ['https://github.com/goodwind-cz/aai.git', 'git@github.com:Goodwind-CZ/AAI.git', 'https://GITHUB.COM/goodwind-cz/aai.GIT', 'https://github.com/github.com/goodwind-cz/aai'];
    const repos = ['goodwind-cz/aai', 'Goodwind-CZ/AAI', 'https://github.com/goodwind-cz/aai', 'git@github.com:goodwind-cz/aai.git', 'HTTPS://GITHUB.COM/GOODWIND-CZ/AAI.GIT'];
    for (const origin of origins) {
      for (const repo of repos) {
        for (const extra of [[], ['--dry-run']]) {
          const lay = layout('refuse-');
          const o = await runFake(mod, { argv: ['--repo', repo, ...extra], lay, origin });
          const label = `${origin} against ${repo} ${extra.join(' ')}`;
          assert.equal(o.code, 2, label);
          assert.equal(o.err, REFUSAL(origin), label);
          assert.equal(o.out, '', label);
          assert.deepEqual(o.others, [], `${label}: no clone, no sync, no source command`);
          assert.deepEqual(readdirSync(lay.tmpdir), [], `${label}: no temp directory`);
        }
      }
    }
  });

  test('TEST-3963 the default repository is guarded too, and the guard reads the origin the documented way', async () => {
    const mod = await import(MODULE_URL);
    const lay = layout('default-');
    const o = await runFake(mod, { argv: [], lay, origin: 'https://github.com/goodwind-cz/aai.git' });
    assert.equal(o.code, 2);
    const reads = o.spawn.calls.filter(isGuardRead);
    assert.equal(reads.length, 1);
    assert.equal(reads[0].file, 'git');
    assert.deepEqual(reads[0].args, ['-C', lay.target, 'config', '--get', 'remote.origin.url']);
    assert.deepEqual(reads[0].opts.stdio, ['ignore', 'pipe', 'ignore']);
  });

  test('TEST-3963 no refusal with --force, with a local directory, with another repository, without an origin or when the read fails', async () => {
    const mod = await import(MODULE_URL);
    const canonical = 'https://github.com/goodwind-cz/aai.git';
    const refused = (o) => o.code === 2 || o.err.includes('REFUSED');
    for (const flag of ['--force', '-Force', '-force']) {
      const lay = layout('force-');
      const o = await runFake(mod, { argv: ['--repo', 'goodwind-cz/aai', '--dry-run', flag], lay, origin: canonical });
      assert.ok(!refused(o), `${flag}: ${o.err}`);
    }
    // a local directory as the repository value
    const lay1 = layout('local-');
    const o1 = await runFake(mod, { argv: ['--repo', lay1.source, '--dry-run'], lay: lay1, origin: canonical });
    assert.ok(!refused(o1), o1.err);
    // another repository
    const lay2 = layout('other-');
    const o2 = await runFake(mod, { argv: ['--repo', 'acme/foo', '--dry-run'], lay: lay2, origin: canonical });
    assert.ok(!refused(o2), o2.err);
    const o3 = await runFake(mod, { argv: ['--repo', 'goodwind-cz/aai', '--dry-run'], lay: layout('other2-'), origin: 'https://github.com/acme/target.git' });
    assert.ok(!refused(o3), o3.err);
    // no origin (the read fails or prints nothing) and a git that cannot start
    const o4 = await runFake(mod, { argv: ['--repo', 'goodwind-cz/aai', '--dry-run'], lay: layout('noorigin-'), origin: '' });
    assert.ok(!refused(o4), o4.err);
    const o5 = await runFake(mod, { argv: ['--repo', 'goodwind-cz/aai', '--dry-run'], lay: layout('nogit-'), origin: null });
    assert.ok(!refused(o5), o5.err);
    // a repo value that names a path is never a canonical slug, even beside a canonical origin
    const o6 = await runFake(mod, { argv: ['--repo', '/tmp/x/goodwind-cz/aai', '--dry-run'], lay: layout('path-'), origin: canonical });
    assert.ok(!refused(o6), o6.err);
  });

  test('TEST-3963 the refusal is real through the entry point: exit 2, the three lines, target unchanged, nothing left in TMPDIR', () => {
    const root = scratch('guard-real-');
    const target = path.join(root, 'target');
    mkdirSync(target);
    const git = (...a) => spawnSync('git', a, { cwd: target, env: prepareEnv(root), encoding: 'utf8' });
    assert.equal(git('init', '-q').status, 0);
    assert.equal(git('remote', 'add', 'origin', 'https://GITHUB.COM/goodwind-cz/aai.GIT').status, 0);
    const before = listTree(target);
    const r = runUpdate({ args: ['--repo', 'goodwind-cz/aai', '--dry-run'], root, cwd: target });
    assert.equal(r.status, 2, r.stderr);
    assert.equal(r.stderr, REFUSAL('https://GITHUB.COM/goodwind-cz/aai.GIT'));
    assert.equal(r.stdout, '');
    assert.deepEqual(listTree(target), before);
    assert.deepEqual(readdirSync(path.join(root, 'tmp')), []);
    // --force lifts it
    const forced = runUpdate({ args: ['--repo', 'goodwind-cz/aai', '--dry-run', '--force'], root, cwd: target });
    assert.notEqual(forced.status, 2);
  });
});

// --- TEST-3964 ---------------------------------------------------------------------------------

describe('TEST-3964 source resolution and the clone chain', () => {
  test('TEST-3964 a real run on a local checkout runs the three git commands in it, in order, with closed stdio', async () => {
    const mod = await import(MODULE_URL);
    const lay = layout('local-real-');
    const o = await runFake(mod, { argv: ['--repo', lay.source, '--ref', 'dev'], lay });
    assert.equal(o.code, 0, o.err);
    const git = o.others.filter((c) => c.file === 'git' && !isStatus(c));
    assert.deepEqual(git.map((c) => c.args), [
      ['-C', lay.source, 'fetch', '--depth', '1', 'origin', 'dev'],
      ['-C', lay.source, 'checkout', 'dev'],
      ['-C', lay.source, 'pull', '--ff-only', 'origin', 'dev'],
    ]);
    for (const c of git) assert.deepEqual(c.opts.stdio, IGNORE3);
    assert.equal(o.others.filter((c) => c.file === 'gh').length, 0, 'gh is not asked for a local checkout');
    assert.deepEqual(o.temps, [], 'a local checkout needs no temp directory');
    // the sync runs after the three commands
    assert.equal(o.others.findIndex(isSync), 3);
  });

  test('TEST-3964 a local checkout resolves lexically against the base, and failing git commands are ignored', async () => {
    const mod = await import(MODULE_URL);
    const lay = layout('local-rel-');
    const o = await runFake(mod, {
      argv: ['--repo', path.join('..', 'src')], lay,
      handler: (c) => (c.file === 'git' ? { status: 128 } : null),
    });
    assert.equal(o.code, 0, o.err);
    assert.deepEqual(o.others[0].args, ['-C', lay.source, 'fetch', '--depth', '1', 'origin', 'main']);
    assert.ok(isSync(o.others[3]));
    // git missing altogether: the three commands fail to start and the sync still runs, exit 0
    const lay2 = layout('local-nogit-');
    const o2 = await runFake(mod, { argv: ['--repo', lay2.source], lay: lay2, origin: null, handler: (c) => (c.file === 'git' ? enoent() : null) });
    assert.equal(o2.code, 0, o2.err);
    assert.equal(o2.err, '');
    assert.equal(o2.others.filter(isSync).length, 1);
  });

  test('TEST-3964 a dry-run on a local checkout starts no command in it', async () => {
    const mod = await import(MODULE_URL);
    const lay = layout('local-dry-');
    const o = await runFake(mod, { argv: ['--repo', lay.source, '--ref', 'main', '--dry-run'], lay });
    assert.equal(o.code, 0, o.err);
    assert.deepEqual(o.others, [], 'no fetch, checkout, pull or sync');
    assert.deepEqual(o.temps, []);
  });

  test('TEST-3964 cloneUrl keeps a URL and builds the https form for a slug (DR-22)', async () => {
    const { cloneUrl } = await import(MODULE_URL);
    const as = ['https://example.com/a/b.git', 'file:///x/y', 'ssh://git@host/a/b', 'git@github.com:a/b.git', 'user@host:path', '@:', 'x@y:z', 'x@:'];
    for (const v of as) assert.equal(cloneUrl(v), v, v);
    for (const v of ['acme/foo', 'goodwind-cz/aai', 'a:b@c', 'foo@bar', 'a@b', 'host:path']) assert.equal(cloneUrl(v), `https://github.com/${v}.git`, v);
  });

  test('TEST-3964 resolveSource describes a slug as url@ref and starts nothing in a dry-run', async () => {
    const { resolveSource } = await import(MODULE_URL);
    const lay = layout('desc-');
    const spawn = fakeSpawn();
    const state = { keepTemp: false, tmp: '', created: null };
    const r = resolveSource({ repo: 'acme/foo', ref: 'dev', dryRun: true }, { spawn, tmpdir: lay.tmpdir, env: {}, cwd: lay.target, err: () => {} }, state);
    assert.equal(r.desc, 'https://github.com/acme/foo.git@dev');
    assert.equal(r.fail, undefined);
    assert.deepEqual(spawn.calls, []);
    assert.deepEqual(readdirSync(lay.tmpdir), []);
    assert.equal(state.tmp, '');
    const l = resolveSource({ repo: lay.source, ref: 'main', dryRun: true }, { spawn, tmpdir: lay.tmpdir, env: {}, cwd: lay.target, err: () => {} }, state);
    assert.equal(l.desc, `local checkout ${lay.source}`);
    assert.equal(l.src, lay.source);
    assert.deepEqual(spawn.calls, []);
    // a dry-run on a remote URL through run: the description line is Run 3's, but no clone and no temp happen
    const o = await runFake(await import(MODULE_URL), { argv: ['--repo', 'acme/foo', '--ref', 'dev', '--dry-run'], lay });
    assert.equal(o.code, 0, o.err);
    assert.deepEqual(o.others, []);
    assert.deepEqual(o.temps, []);
  });

  test('TEST-3964 three clone attempts run in order into tmp/src, each after the source directory was emptied', async () => {
    const mod = await import(MODULE_URL);
    const lay = layout('clone-');
    const seen = [];
    const o = await runFake(mod, {
      argv: ['--repo', 'acme/foo', '--ref', 'dev'], lay, handler: cloneHandler([{ status: 1 }, { status: 1 }, 'ok'], seen),
    });
    assert.equal(o.code, 0, o.err);
    assert.equal(seen.length, 3);
    const dest = seen[0].dest;
    assert.equal(path.basename(dest), 'src');
    const tmp = path.dirname(dest);
    assert.equal(path.dirname(tmp), lay.tmpdir);
    assert.ok(path.basename(tmp).startsWith('aai-src.'));
    assert.equal(path.basename(tmp).length, 'aai-src.'.length + 6);
    for (const s of seen) assert.equal(s.dest, dest);
    assert.deepEqual(seen[0].call.file, 'gh');
    assert.deepEqual(seen[0].call.args, ['repo', 'clone', 'acme/foo', dest, '--', '--branch', 'dev', '--depth', '1']);
    assert.equal(seen[1].call.file, 'git');
    assert.deepEqual(seen[1].call.args, ['clone', '--branch', 'dev', '--depth', '1', 'https://github.com/acme/foo.git', dest]);
    assert.equal(seen[2].call.file, 'git');
    assert.deepEqual(seen[2].call.args, ['-c', 'credential.helper=', '-c', 'http.https://github.com/.extraheader=', 'clone', '--branch', 'dev', '--depth', '1', 'https://github.com/acme/foo.git', dest]);
    // the partial clone of attempt 1 and 2 is gone before the next attempt; the first attempt starts clean
    assert.deepEqual(seen.map((s) => s.existed), [false, false, false]);
    // the temp directory is never replaced: one inode throughout, and src was the only thing removed
    assert.equal(new Set(seen.map((s) => s.tmpIno)).size, 1);
    // every git and gh child has all three stdio streams closed
    for (const s of seen) assert.deepEqual(s.call.opts.stdio, IGNORE3);
  });

  test('TEST-3964 GIT_TERMINAL_PROMPT=0 is set for the third attempt only', async () => {
    const mod = await import(MODULE_URL);
    const lay = layout('prompt-');
    const seen = [];
    const o = await runFake(mod, { argv: ['--repo', 'acme/foo'], lay, handler: cloneHandler([{ status: 1 }, { status: 1 }, 'ok'], seen) });
    assert.equal(o.code, 0, o.err);
    assert.equal(seen[0].call.opts.env.GIT_TERMINAL_PROMPT, undefined);
    assert.equal(seen[1].call.opts.env.GIT_TERMINAL_PROMPT, undefined);
    assert.equal(seen[2].call.opts.env.GIT_TERMINAL_PROMPT, '0');
    // the sync child does not inherit it
    const sync = o.others.find(isSync);
    assert.ok(sync);
    assert.equal(sync.opts.env.GIT_TERMINAL_PROMPT, undefined);
  });

  test('TEST-3964 the first attempt that succeeds ends the chain', async () => {
    const mod = await import(MODULE_URL);
    for (const [results, count] of [[['ok'], 1], [[{ status: 1 }, 'ok'], 2]]) {
      const lay = layout('chain-');
      const seen = [];
      const o = await runFake(mod, { argv: ['--repo', 'acme/foo'], lay, handler: cloneHandler(results, seen) });
      assert.equal(o.code, 0, o.err);
      assert.equal(seen.length, count);
    }
    // a gh that cannot start is a failed attempt, not an error
    const lay = layout('chain-nogh-');
    const seen = [];
    const o = await runFake(mod, { argv: ['--repo', 'acme/foo'], lay, handler: cloneHandler([enoent(), 'ok'], seen) });
    assert.equal(o.code, 0, o.err);
    assert.equal(seen.length, 2);
  });

  test('TEST-3964 a clone attempt killed by a signal stops the chain and the run exits 128 plus the signal number', async () => {
    const mod = await import(MODULE_URL);
    for (const [signal, code] of [['SIGINT', 130], ['SIGTERM', 143]]) {
      const lay = layout('chain-sig-');
      const seen = [];
      const o = await runFake(mod, { argv: ['--repo', 'acme/foo'], lay, handler: cloneHandler([{ status: null, signal }, 'ok', 'ok'], seen) });
      assert.equal(seen.length, 1, `no second attempt after ${signal}`);
      assert.equal(o.code, code);
      assert.equal(o.others.filter(isSync).length, 0, 'no sync after an interrupted fetch');
      assert.deepEqual(o.temps, [], 'the run temp directory is removed');
    }
    // a signal on the second attempt stops before the third
    const lay2 = layout('chain-sig2-');
    const seen2 = [];
    const o2 = await runFake(mod, { argv: ['--repo', 'acme/foo'], lay: lay2, handler: cloneHandler([{ status: 1 }, { status: null, signal: 'SIGINT' }, 'ok'], seen2) });
    assert.equal(seen2.length, 2);
    assert.equal(o2.code, 130);
    assert.deepEqual(o2.temps, []);
  });

  test('TEST-3964 a local-checkout git command killed by a signal stops the run before the next command and the sync', async () => {
    const mod = await import(MODULE_URL);
    const lay = layout('local-sig-');
    const o = await runFake(mod, { argv: ['--repo', lay.source], lay, handler: (c) => (c.file === 'git' ? { status: null, signal: 'SIGINT' } : null) });
    assert.equal(o.code, 130);
    assert.equal(o.others.filter((c) => c.file === 'git').length, 1);
    assert.equal(o.others.filter(isSync).length, 0);
  });

  test('TEST-3964 all attempts failing exit 3 with the auth line; git that cannot start gives the DR-18 line', async () => {
    const mod = await import(MODULE_URL);
    const lay = layout('fail-');
    const o = await runFake(mod, { argv: ['--repo', 'acme/foo', '--ref', 'dev'], lay, handler: cloneHandler([{ status: 1 }, { status: 128 }, { status: 128 }]) });
    assert.equal(o.code, 3);
    assert.equal(o.err, 'ERROR: could not fetch acme/foo@dev (auth or network?). Treat as an access issue, not a missing repo.\n');
    assert.equal(o.out, '');
    assert.equal(o.others.filter(isSync).length, 0, 'no sync after a failed fetch');
    assert.deepEqual(o.temps, []);
    // a signal-killed attempt is not a failed attempt: it stops the chain (see the signal test above)
    // DR-18: gh and git cannot start
    const lay2 = layout('nogit-');
    const o2 = await runFake(mod, { argv: ['--repo', 'acme/foo', '--ref', 'dev'], lay: lay2, origin: null, handler: cloneHandler([enoent(), enoent(), enoent()]) });
    assert.equal(o2.code, 3);
    assert.equal(o2.err, 'ERROR: could not fetch acme/foo@dev: git was not found on PATH.\n');
    assert.deepEqual(o2.temps, []);
    // gh present, git missing at attempts 2 and 3 is the same line
    const lay3 = layout('nogit2-');
    const o3 = await runFake(mod, { argv: ['--repo', 'acme/foo'], lay: lay3, handler: cloneHandler([{ status: 1 }, enoent(), enoent()]) });
    assert.equal(o3.err, 'ERROR: could not fetch acme/foo@main: git was not found on PATH.\n');
    // only one of the two git attempts failing to start keeps the access line
    const lay4 = layout('nogit3-');
    const o4 = await runFake(mod, { argv: ['--repo', 'acme/foo'], lay: lay4, handler: cloneHandler([{ status: 1 }, enoent(), { status: 128 }]) });
    assert.ok(o4.err.includes('(auth or network?)'));
  });

  test('TEST-3964 the clone reaches a real source through file:// with the real git and a failing gh stub', () => {
    const root = scratch('clone-real-');
    const upstream = path.join(root, 'upstream');
    const target = path.join(root, 'target');
    mkdirSync(path.join(upstream, '.aai', 'scripts'), { recursive: true });
    mkdirSync(target);
    writeFileSync(path.join(upstream, '.aai', 'scripts', 'aai-sync.sh'), '#!/bin/sh\necho "FX-SYNC target=$1"\n');
    const env = prepareEnv(root);
    const git = (cwd, ...a) => spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.com', ...a], { cwd, env, encoding: 'utf8' });
    assert.equal(git(upstream, 'init', '-q', '-b', 'main').status, 0);
    assert.equal(git(upstream, 'add', '.').status, 0);
    assert.equal(git(upstream, 'commit', '-q', '-m', 'x').status, 0);
    const r = runUpdate({ args: ['--repo', `file://${upstream}`, '--ref', 'main'], root, cwd: target });
    assert.equal(r.status, 0, r.stderr);
    assert.ok(r.stdout.includes(`FX-SYNC target=${target}`), r.stdout);
    const ghLog = readFileSync(path.join(root, 'gh.log'), 'utf8');
    assert.match(ghLog, new RegExp(`^repo clone file://${upstream.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')} \\S+/aai-src\\.\\w{6}/src -- --branch main --depth 1\n$`));
    assert.deepEqual(readdirSync(path.join(root, 'tmp')), []);
  });
});

// --- TEST-3965 ---------------------------------------------------------------------------------

describe('TEST-3965 temp lifecycle', () => {
  test('TEST-3965 createOwnTemp makes aai-src.XXXXXX under the temp directory and records its parent', async () => {
    const { createOwnTemp } = await import(MODULE_URL);
    const lay = layout('create-');
    const created = createOwnTemp(lay.tmpdir);
    assert.equal(path.dirname(created.path), lay.tmpdir);
    assert.match(path.basename(created.path), /^aai-src\.[A-Za-z0-9]{6}$/);
    assert.ok(lstatSync(created.path).isDirectory());
    assert.equal(created.parentReal, realpathSync(lay.tmpdir));
    const second = createOwnTemp(lay.tmpdir);
    assert.notEqual(second.path, created.path);
  });

  test('TEST-3965 removeOwnTemp removes the created directory with its content', async () => {
    const { createOwnTemp, removeOwnTemp } = await import(MODULE_URL);
    const lay = layout('remove-');
    let err = '';
    const created = createOwnTemp(lay.tmpdir, (s) => { err += s; });
    mkdirSync(path.join(created.path, 'src', 'deep'), { recursive: true });
    writeFileSync(path.join(created.path, 'src', 'deep', 'f'), 'x');
    removeOwnTemp(created.path, created);
    assert.ok(!existsSync(created.path));
    assert.equal(err, '');
    assert.ok(existsSync(lay.tmpdir), 'the parent stays');
  });

  test('TEST-3965 removeOwnTemp keeps and reports a different path, a foreign prefix, a symbolic link, a moved parent and an unusable value', async () => {
    const { createOwnTemp, removeOwnTemp } = await import(MODULE_URL);
    const lay = layout('keep-');
    const keptLine = (dir) => new RegExp(`^aai-update: kept ${dir.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}: .+\\n$`);
    const attempt = (dir, created) => {
      let err = '';
      const rec = { ...created, err: (s) => { err += s; } };
      removeOwnTemp(dir, rec);
      return err;
    };
    const created = createOwnTemp(lay.tmpdir);
    // a different path that carries the prefix
    const other = path.join(lay.tmpdir, 'aai-src.other1');
    mkdirSync(other);
    writeFileSync(path.join(other, 'keep'), 'x');
    assert.match(attempt(other, created), keptLine(other));
    assert.ok(existsSync(path.join(other, 'keep')));
    // a foreign prefix, even when it is the recorded path
    const foreign = path.join(lay.tmpdir, 'something-else');
    mkdirSync(foreign);
    assert.match(attempt(foreign, { path: foreign, parentReal: realpathSync(lay.tmpdir) }), keptLine(foreign));
    assert.ok(existsSync(foreign));
    // a symbolic link with the prefix, recorded as the path
    const real = path.join(lay.tmpdir, 'real-dir');
    mkdirSync(real);
    writeFileSync(path.join(real, 'keep'), 'x');
    const link = path.join(lay.tmpdir, 'aai-src.link01');
    symlinkSync(real, link);
    assert.match(attempt(link, { path: link, parentReal: realpathSync(lay.tmpdir) }), keptLine(link));
    assert.ok(existsSync(path.join(real, 'keep')));
    assert.ok(lstatSync(link).isSymbolicLink());
    // a parent whose realpath differs from the recorded one
    const elsewhere = path.join(lay.root, 'elsewhere');
    mkdirSync(elsewhere);
    const moved = path.join(elsewhere, 'aai-src.moved1');
    mkdirSync(moved);
    assert.match(attempt(moved, { path: moved, parentReal: realpathSync(lay.tmpdir) }), keptLine(moved));
    assert.ok(existsSync(moved));
    // a path that is a regular file
    const file = path.join(lay.tmpdir, 'aai-src.file01');
    writeFileSync(file, 'x');
    assert.match(attempt(file, { path: file, parentReal: realpathSync(lay.tmpdir) }), keptLine(file));
    assert.ok(existsSync(file));
    // an empty, a relative and a missing record
    for (const bad of ['', 'aai-src.rel001', undefined]) {
      let err = '';
      removeOwnTemp(bad, { path: bad, parentReal: realpathSync(lay.tmpdir), err: (s) => { err += s; } });
      assert.match(err, /^aai-update: kept .*: .+\n$/, String(bad));
    }
    let err = '';
    removeOwnTemp(created.path, { ...created, path: '', err: (s) => { err += s; } });
    assert.match(err, /^aai-update: kept /);
    assert.ok(existsSync(created.path));
    err = '';
    removeOwnTemp(created.path, null);
    assert.ok(existsSync(created.path), 'no record: nothing is removed');
    // the directory itself was never removed by any refusal, and the recorded one still can be
    removeOwnTemp(created.path, created);
    assert.ok(!existsSync(created.path));
  });

  test('TEST-3965 a real run leaves no aai-src. entry after success, exit 3, exit 4, a failing sync and an internal error', async () => {
    const mod = await import(MODULE_URL);
    // success
    const l1 = layout('end-ok-');
    const o1 = await runFake(mod, { argv: ['--repo', 'acme/foo'], lay: l1, handler: cloneHandler(['ok']) });
    assert.equal(o1.code, 0, o1.err);
    assert.equal(o1.others.filter(isSync).length, 1);
    assert.deepEqual(o1.temps, []);
    // exit 3
    const l2 = layout('end-3-');
    const o2 = await runFake(mod, { argv: ['--repo', 'acme/foo'], lay: l2, handler: cloneHandler([{ status: 1 }, { status: 1 }, { status: 1 }]) });
    assert.equal(o2.code, 3);
    assert.deepEqual(o2.temps, []);
    // exit 4: the clone has no sync script
    const l3 = layout('end-4-');
    const o3 = await runFake(mod, {
      argv: ['--repo', 'acme/foo'], lay: l3,
      handler: (c) => { if (c.file === 'git' && c.args.includes('clone') && !c.args.includes('credential.helper=')) { mkdirSync(c.args[c.args.length - 1], { recursive: true }); return { status: 0 }; } return null; },
    });
    assert.equal(o3.code, 4);
    assert.match(o3.err, /^ERROR: sync script missing in source: .+aai-sync\.sh\n$/);
    assert.deepEqual(o3.temps, []);
    // a failing sync: its code is passed through
    const l4 = layout('end-sync-');
    const clone = cloneHandler(['ok']);
    const o4 = await runFake(mod, { argv: ['--repo', 'acme/foo'], lay: l4, handler: (c, i) => (isSync(c) ? { status: 5 } : clone(c, i)) });
    assert.equal(o4.code, 5);
    assert.deepEqual(o4.temps, []);
    // an internal error: the sync child throws
    const l5 = layout('end-throw-');
    const clone5 = cloneHandler(['ok']);
    const o5 = await runFake(mod, { argv: ['--repo', 'acme/foo'], lay: l5, handler: (c, i) => { if (isSync(c)) throw new Error('boom'); return clone5(c, i); } });
    assert.equal(o5.code, 1);
    assert.equal(o5.err, 'aai-update: internal error: boom\n');
    assert.deepEqual(o5.temps, []);
  });

  test('TEST-3965 --keep-temp keeps exactly one directory on every path and prints nothing about it', async () => {
    const mod = await import(MODULE_URL);
    const l1 = layout('keep-ok-');
    const o1 = await runFake(mod, { argv: ['--repo', 'acme/foo', '--keep-temp'], lay: l1, handler: cloneHandler(['ok']) });
    assert.equal(o1.code, 0, o1.err);
    assert.equal(o1.temps.length, 1);
    assert.equal(o1.err, '');
    assert.ok(!o1.out.includes('aai-src'));
    assert.ok(existsSync(path.join(l1.tmpdir, o1.temps[0], 'src', '.aai', 'scripts', 'aai-sync.sh')));
    const l2 = layout('keep-3-');
    const o2 = await runFake(mod, { argv: ['--repo', 'acme/foo', '--keep-temp'], lay: l2, handler: cloneHandler([{ status: 1 }, { status: 1 }, { status: 1 }]) });
    assert.equal(o2.code, 3);
    assert.equal(o2.temps.length, 1);
    assert.ok(!o2.err.includes('aai-src'), 'the kept directory is not named');
  });

  test('TEST-3965 a dry-run, a usage error and a refusal create no temp directory', async () => {
    const mod = await import(MODULE_URL);
    for (const [argv, code, origin] of [
      [['--repo', 'acme/foo', '--dry-run'], 0, ''], [['--dry-run', '--bogus'], 1, ''], [['--repo'], 1, ''], [['-h'], 0, ''],
      [['--repo', 'goodwind-cz/aai'], 2, 'https://github.com/goodwind-cz/aai.git'],
    ]) {
      const lay = layout('none-');
      const o = await runFake(mod, { argv, lay, origin });
      assert.equal(o.code, code, argv.join(' '));
      assert.deepEqual(readdirSync(lay.tmpdir), [], argv.join(' '));
    }
  });

  test('TEST-3965 a cleanup that refuses keeps the directory, reports it, and leaves the exit code unchanged', async () => {
    const mod = await import(MODULE_URL);
    const lay = layout('swap-');
    const clone = cloneHandler(['ok']);
    let swapped = '';
    const o = await runFake(mod, {
      argv: ['--repo', 'acme/foo'], lay,
      handler: (c, i) => {
        if (isSync(c)) {
          // during the sync, the temp directory is replaced by a symbolic link to a directory of the test
          const tmp = path.dirname(path.dirname(path.dirname(path.dirname(c.args[0]))));
          const decoy = path.join(lay.root, 'decoy');
          mkdirSync(decoy);
          writeFileSync(path.join(decoy, 'precious'), 'x');
          renameSync(tmp, path.join(lay.root, 'moved-away'));
          symlinkSync(decoy, tmp);
          swapped = tmp;
          return { status: 0 };
        }
        return clone(c, i);
      },
    });
    assert.equal(o.code, 0, 'the exit code is the sync result, not the cleanup result');
    assert.ok(swapped.length > 0);
    assert.match(o.err, new RegExp(`^aai-update: kept ${swapped.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}: .+\\n$`));
    assert.ok(existsSync(path.join(lay.root, 'decoy', 'precious')), 'the link target was not touched');
  });

  test('TEST-3965 the real entry point removes its temp on success and keeps it with --keep-temp', () => {
    const root = scratch('real-temp-');
    const upstream = path.join(root, 'upstream');
    const target = path.join(root, 'target');
    mkdirSync(path.join(upstream, '.aai', 'scripts'), { recursive: true });
    mkdirSync(target);
    writeFileSync(path.join(upstream, '.aai', 'scripts', 'aai-sync.sh'), '#!/bin/sh\nexit 0\n');
    const env = prepareEnv(root);
    const git = (...a) => spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.com', ...a], { cwd: upstream, env, encoding: 'utf8' });
    assert.equal(git('init', '-q', '-b', 'main').status, 0);
    assert.equal(git('add', '.').status, 0);
    assert.equal(git('commit', '-q', '-m', 'x').status, 0);
    const tmp = path.join(root, 'tmp');
    const ok = runUpdate({ args: ['--repo', `file://${upstream}`], root, cwd: target });
    assert.equal(ok.status, 0, ok.stderr);
    assert.deepEqual(readdirSync(tmp), []);
    const keep = runUpdate({ args: ['--repo', `file://${upstream}`, '--keep-temp'], root, cwd: target });
    assert.equal(keep.status, 0, keep.stderr);
    const kept = readdirSync(tmp);
    assert.equal(kept.length, 1);
    assert.match(kept[0], /^aai-src\./);
    const bad = runUpdate({ args: ['--repo', `file://${path.join(root, 'missing')}`], root, cwd: target });
    assert.equal(bad.status, 3);
    assert.equal(readdirSync(tmp).length, 1, 'the failed run removed its own temp and not the kept one');
  });

  test('TEST-3965 a SIGTERM during the sync child stops the run with 143 after the child returns, with no post-sync output and no temp left', () => {
    const root = scratch('real-sigterm-');
    const upstream = path.join(root, 'upstream');
    const target = path.join(root, 'target');
    mkdirSync(path.join(upstream, '.aai', 'scripts'), { recursive: true });
    mkdirSync(target);
    // the sync child signals its parent (the module) and then lingers, so the signal arrives while spawnSync blocks
    writeFileSync(path.join(upstream, '.aai', 'scripts', 'aai-sync.sh'), '#!/bin/sh\necho SYNC-START\nkill -TERM "$PPID"\nsleep 1\necho SYNC-END\n');
    const env = prepareEnv(root);
    const git = (...a) => spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.com', ...a], { cwd: upstream, env, encoding: 'utf8' });
    assert.equal(git('init', '-q', '-b', 'main').status, 0);
    assert.equal(git('add', '.').status, 0);
    assert.equal(git('commit', '-q', '-m', 'x').status, 0);
    assert.equal(spawnSync('git', ['init', '-q'], { cwd: target, env, encoding: 'utf8' }).status, 0);
    const r = runUpdate({ args: ['--repo', `file://${upstream}`], root, cwd: target });
    assert.equal(r.status, 143, `${r.stdout}${r.stderr}`);
    assert.match(r.stdout, /SYNC-START/);
    assert.doesNotMatch(r.stdout, /Post-sync evidence|Recommended/);
    assert.deepEqual(readdirSync(path.join(root, 'tmp')).filter((n) => n.startsWith('aai-src.')), []);
  });

  // a post-sync window: the sync child ends cleanly, then the named post-sync child signals the module and lingers
  function postSyncSignalRun(label, { doctor, gitStatus }) {
    const root = scratch(`real-sigterm-${label}-`);
    const upstream = path.join(root, 'upstream');
    const target = path.join(root, 'target');
    mkdirSync(path.join(upstream, '.aai', 'scripts'), { recursive: true });
    mkdirSync(path.join(target, '.aai', 'scripts'), { recursive: true });
    writeFileSync(path.join(upstream, '.aai', 'scripts', 'aai-sync.sh'), '#!/bin/sh\necho SYNC-START\necho SYNC-END\n');
    const signalling = 'process.kill(process.ppid, "SIGTERM"); console.log("DOCTOR-START"); setTimeout(() => console.log("DOCTOR-END"), 1000);\n';
    writeFileSync(path.join(target, '.aai', 'scripts', 'update-doctor-report.mjs'), doctor ? signalling : 'console.log("DOCTOR-REPORT");\n');
    const env = prepareEnv(root);
    const git = (...a) => spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.com', ...a], { cwd: upstream, env, encoding: 'utf8' });
    assert.equal(git('init', '-q', '-b', 'main').status, 0);
    assert.equal(git('add', '.').status, 0);
    assert.equal(git('commit', '-q', '-m', 'x').status, 0);
    assert.equal(spawnSync('git', ['init', '-q'], { cwd: target, env, encoding: 'utf8' }).status, 0);
    if (gitStatus) {
      // a git shim that signals the module while it runs the evidence status call, then lingers and runs the real git
      const realGit = env.PATH.split(path.delimiter).slice(1).map((d) => path.join(d, 'git')).find((f) => existsSync(f));
      assert.ok(realGit, 'a real git exists');
      const shim = path.join(root, 'bin', 'git');
      writeFileSync(shim, `#!/bin/sh\nfor a in "$@"; do\n  if [ "$a" = status ]; then kill -TERM "$PPID"; sleep 1; fi\ndone\nexec "${realGit}" "$@"\n`);
      chmodSync(shim, 0o755);
    }
    const r = runUpdate({ args: ['--repo', `file://${upstream}`], root, cwd: target });
    assert.equal(r.status, 143, `${r.stdout}${r.stderr}`);
    assert.match(r.stdout, /SYNC-START/);
    assert.doesNotMatch(r.stdout, /Recommended|## Next|DOCTOR-REPORT/);
    assert.deepEqual(readdirSync(path.join(root, 'tmp')).filter((n) => n.startsWith('aai-src.')), []);
    return r;
  }

  test('TEST-3965 a SIGTERM during the doctor helper stops the run with 143 and prints no Next block', () => {
    postSyncSignalRun('doctor', { doctor: true, gitStatus: false });
  });

  test('TEST-3965 a SIGTERM during the evidence git status stops the run with 143 and prints no doctor report or Next block', () => {
    postSyncSignalRun('status', { doctor: false, gitStatus: true });
  });

  test('TEST-3965 a real run uninstalls its SIGINT and SIGTERM listeners when it returns', async () => {
    const root = scratch('listeners-');
    const upstream = path.join(root, 'upstream');
    const target = path.join(root, 'target');
    mkdirSync(path.join(upstream, '.aai', 'scripts'), { recursive: true });
    mkdirSync(target);
    writeFileSync(path.join(upstream, '.aai', 'scripts', 'aai-sync.sh'), '#!/bin/sh\necho SYNC\n');
    const env = prepareEnv(root);
    const git = (...a) => spawnSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.com', ...a], { cwd: upstream, env, encoding: 'utf8' });
    assert.equal(git('init', '-q', '-b', 'main').status, 0);
    assert.equal(git('add', '.').status, 0);
    assert.equal(git('commit', '-q', '-m', 'x').status, 0);
    assert.equal(spawnSync('git', ['init', '-q'], { cwd: target, env, encoding: 'utf8' }).status, 0);
    assert.equal(spawnSync('git', ['config', 'user.name', 't'], { cwd: target, env }).status, 0);
    const { run } = await import(MODULE_URL);
    const before = { int: process.listenerCount('SIGINT'), term: process.listenerCount('SIGTERM') };
    const sink = { out: () => {}, err: () => {} };
    const errs = [];
    const code = await run(['--repo', `file://${upstream}`], { ...sink, err: (m) => errs.push(m), env, cwd: target, tmpdir: path.join(root, 'tmp') });
    assert.equal(code, 0, errs.join(''));
    assert.equal(process.listenerCount('SIGINT'), before.int);
    assert.equal(process.listenerCount('SIGTERM'), before.term);
    const dry = await run(['--dry-run', '--repo', `file://${upstream}`], { ...sink, env, cwd: target, tmpdir: path.join(root, 'tmp') });
    assert.equal(dry, 0);
    assert.equal(process.listenerCount('SIGTERM'), before.term);
  });
});

// --- run 3: the runner, the rendering and the doctor postamble (TEST-3966 to TEST-3968) ---------------------

const RUNNER_VAR = 'AAI_UPDATE_SYNC_RUNNER';
const isSyncAny = (c) => c.args.some((a) => /aai-sync\.(sh|ps1)$/.test(String(a)));
const isHelper = (c) => c.file === process.execPath;
const isStatus = (c) => c.file === 'git' && c.args[0] === '-C' && c.args[2] === 'status';
const DASH = '\u2014';
const WARN = '\u26a0';
const PWSH = '/opt/microsoft/powershell/7/pwsh';
const HELPER_PATH = ['.aai', 'scripts', 'update-doctor-report.mjs'];

// TEST-3966 -------------------------------------------------------------------------------------------------

describe('TEST-3966 runner and sync step', () => {
  test('TEST-3966 resolveRunner maps bash, absolute bash, pwsh and powershell paths and the platform defaults', async () => {
    const { resolveRunner } = await import(MODULE_URL);
    const r = (value, platform = 'linux') => resolveRunner(value === undefined ? {} : { [RUNNER_VAR]: value }, platform);
    assert.deepEqual(r('bash'), { kind: 'bash', exe: 'bash' });
    assert.deepEqual(r('/usr/bin/bash'), { kind: 'bash', exe: '/usr/bin/bash' });
    assert.deepEqual(r('C:\\Program Files\\Git\\bin\\BASH.EXE', 'win32'), { kind: 'bash', exe: 'C:\\Program Files\\Git\\bin\\BASH.EXE' });
    assert.deepEqual(r(PWSH), { kind: 'powershell', exe: PWSH });
    assert.deepEqual(r('C:\\Program Files\\PowerShell\\7\\pwsh.exe', 'win32'), { kind: 'powershell', exe: 'C:\\Program Files\\PowerShell\\7\\pwsh.exe' });
    assert.deepEqual(r('/usr/bin/powershell'), { kind: 'powershell', exe: '/usr/bin/powershell' });
    assert.deepEqual(r('C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\POWERSHELL.exe', 'win32'), { kind: 'powershell', exe: 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\POWERSHELL.exe' });
    assert.deepEqual(r(undefined), { kind: 'bash', exe: 'bash' });
    assert.deepEqual(r(''), { kind: 'bash', exe: 'bash' });
    assert.deepEqual(r(undefined, 'win32'), { kind: 'powershell', exe: 'powershell.exe' });
    assert.deepEqual(r('', 'win32'), { kind: 'powershell', exe: 'powershell.exe' });
    for (const bad of ['zsh', 'Bash', 'pwsh', 'relative/bash', '/bin/sh', '/usr/bin/bashx', '/usr/bin/pwsh.bak', '  ']) {
      assert.deepEqual(r(bad), {
        error: `aai-update: AAI_UPDATE_SYNC_RUNNER must be bash or a path to bash, pwsh or powershell, got '${bad}'`,
      }, bad);
    }
  });

  test('TEST-3966 syncCommand builds the bash and the PowerShell command with forward slashes and Bypass on win32 only', async () => {
    const { syncCommand } = await import(MODULE_URL);
    const bash = { kind: 'bash', exe: 'bash' };
    const ps = { kind: 'powershell', exe: PWSH };
    assert.deepEqual(syncCommand(bash, '/s', '/t', 'linux'), { file: 'bash', args: ['/s/.aai/scripts/aai-sync.sh', '/t'], path: '/s/.aai/scripts/aai-sync.sh' });
    assert.deepEqual(syncCommand({ kind: 'bash', exe: 'C:\\Git\\bin\\bash.exe' }, 'C:\\Users\\a b\\src', 'C:\\Users\\a b\\target', 'win32'), {
      file: 'C:\\Git\\bin\\bash.exe', args: ['C:/Users/a b/src/.aai/scripts/aai-sync.sh', 'C:/Users/a b/target'], path: 'C:/Users/a b/src/.aai/scripts/aai-sync.sh',
    });
    assert.deepEqual(syncCommand(ps, '/s', '/t', 'linux'), {
      file: PWSH, args: ['-NoProfile', '-NonInteractive', '-File', '/s/.aai/scripts/aai-sync.ps1', '-TargetRoot', '/t'], path: '/s/.aai/scripts/aai-sync.ps1',
    });
    assert.deepEqual(syncCommand(ps, '/s', '/t', 'darwin').args.includes('Bypass'), false);
    assert.deepEqual(syncCommand({ kind: 'powershell', exe: 'powershell.exe' }, 'C:\\s', 'C:\\t', 'win32'), {
      file: 'powershell.exe',
      args: ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', 'C:\\s/.aai/scripts/aai-sync.ps1', '-TargetRoot', 'C:\\t'],
      path: 'C:\\s/.aai/scripts/aai-sync.ps1',
    });
  });

  test('TEST-3966 an invalid runner value exits 1 with the named line before any child starts', async () => {
    const mod = await import(MODULE_URL);
    const lay = layout('badrunner-');
    const o = await runFake(mod, { argv: ['--repo', lay.source], lay, env: { [RUNNER_VAR]: 'zsh' } });
    assert.equal(o.code, 1);
    assert.equal(o.err, "aai-update: AAI_UPDATE_SYNC_RUNNER must be bash or a path to bash, pwsh or powershell, got 'zsh'\n");
    assert.equal(o.out, '');
    assert.equal(o.spawn.calls.length, 0);
    const d = await runFake(mod, { argv: ['--repo', 'acme/foo', '--dry-run'], lay, env: { [RUNNER_VAR]: 'sh' } });
    assert.equal(d.code, 1);
    assert.equal(d.spawn.calls.length, 0);
  });

  test('TEST-3966 a missing sync file of the chosen runner is exit 4 naming that file', async () => {
    const mod = await import(MODULE_URL);
    const lay = layout('nosync-');
    // the source holds only aai-sync.sh: the PowerShell runner misses its own file
    const ps = await runFake(mod, { argv: ['--repo', lay.source], lay, env: { [RUNNER_VAR]: PWSH } });
    assert.equal(ps.code, 4);
    assert.equal(ps.err, `ERROR: sync script missing in source: ${lay.source}/.aai/scripts/aai-sync.ps1\n`);
    assert.equal(ps.others.filter(isSyncAny).length, 0);
    const bashLay = layout('nosync-sh-');
    rmSyncFile(path.join(bashLay.source, '.aai', 'scripts', 'aai-sync.sh'));
    writeFileSync(path.join(bashLay.source, '.aai', 'scripts', 'aai-sync.ps1'), '');
    const b = await runFake(mod, { argv: ['--repo', bashLay.source], lay: bashLay });
    assert.equal(b.code, 4);
    assert.equal(b.err, `ERROR: sync script missing in source: ${bashLay.source}/.aai/scripts/aai-sync.sh\n`);
    // a directory in place of the file is not a regular file
    const dirLay = layout('nosync-dir-');
    rmSyncFile(path.join(dirLay.source, '.aai', 'scripts', 'aai-sync.sh'));
    mkdirSync(path.join(dirLay.source, '.aai', 'scripts', 'aai-sync.sh'));
    assert.equal((await runFake(mod, { argv: ['--repo', dirLay.source], lay: dirLay })).code, 4);
  });

  test('TEST-3966 a nonzero sync exit is passed through with no post-sync output and no helper', async () => {
    const mod = await import(MODULE_URL);
    for (const [result, code] of [[{ status: 5 }, 5], [{ status: null, signal: 'SIGTERM' }, 143], [{ status: null, signal: 'SIGINT' }, 130]]) {
      const lay = layout('syncfail-');
      mkdirSync(path.join(lay.target, '.aai', 'scripts'), { recursive: true });
      writeFileSync(path.join(lay.target, ...HELPER_PATH), '');
      const o = await runFake(mod, { argv: ['--repo', lay.source], lay, handler: (c) => (isSyncAny(c) ? result : null) });
      assert.equal(o.code, code);
      assert.equal(o.out, `## aai-update ${DASH} syncing local checkout ${lay.source} into ${lay.target}\n`);
      assert.equal(o.others.filter(isStatus).length, 0);
      assert.equal(o.others.filter(isHelper).length, 0);
    }
  });

  test('TEST-3966 the runner variable is absent from the sync and helper environments and the sync runs in the target with inherited stdio', async () => {
    const mod = await import(MODULE_URL);
    const lay = layout('env-');
    writeFileSync(path.join(lay.source, '.aai', 'scripts', 'aai-sync.ps1'), '');
    mkdirSync(path.join(lay.target, '.aai', 'scripts'), { recursive: true });
    writeFileSync(path.join(lay.target, ...HELPER_PATH), '');
    for (const runner of [undefined, 'bash', PWSH]) {
      const env = runner === undefined ? { KEEP: '1' } : { [RUNNER_VAR]: runner, KEEP: '1' };
      const o = await runFake(mod, { argv: ['--repo', lay.source], lay, env });
      assert.equal(o.code, 0, o.err);
      const sync = o.others.find(isSyncAny);
      assert.ok(sync, 'the sync child ran');
      assert.equal(sync.file, runner === PWSH ? PWSH : (runner ?? 'bash'));
      assert.equal(sync.opts.cwd, lay.target);
      assert.equal(sync.opts.stdio, 'inherit');
      assert.equal(sync.opts.env.KEEP, '1');
      assert.ok(!(RUNNER_VAR in sync.opts.env), 'the sync environment has no runner variable');
      const helper = o.others.find(isHelper);
      assert.ok(helper, 'the helper ran');
      assert.ok(!(RUNNER_VAR in helper.opts.env), 'the helper environment has no runner variable');
      assert.equal(helper.opts.env.KEEP, '1');
    }
  });

  test('TEST-3966 the dry-run prints the Would run line of the runner and starts only the guard read', async () => {
    const mod = await import(MODULE_URL);
    const lay = layout('dry-');
    const bash = await runFake(mod, { argv: ['--repo', 'acme/foo', '--dry-run'], lay });
    assert.equal(bash.code, 0);
    assert.ok(bash.out.includes(`- Would run: <source>/.aai/scripts/aai-sync.sh "${lay.target}"\n`), bash.out);
    assert.equal(bash.others.length, 0);
    const ps = await runFake(mod, { argv: ['--repo', 'acme/foo', '--dry-run'], lay, env: { [RUNNER_VAR]: PWSH } });
    assert.equal(ps.code, 0);
    assert.ok(ps.out.includes(`- Would run: <source>/.aai/scripts/aai-sync.ps1 -TargetRoot "${lay.target}"\n`), ps.out);
    assert.equal(ps.others.length, 0);
  });
});

// rmSyncFile(file): removes one file this test made inside its own scratch layout.
function rmSyncFile(file) {
  assert.ok(path.basename(file).startsWith('aai-sync.'), file);
  assert.ok(existsSync(file) && lstatSync(file).isFile(), file);
  unlinkSync(file);
}

// TEST-3967 -------------------------------------------------------------------------------------------------

const BASH_RUNNER = { kind: 'bash', exe: 'bash' };
const PS_RUNNER = { kind: 'powershell', exe: PWSH };

describe('TEST-3967 rendering', () => {
  test('TEST-3967 renderDryRun prints the bash reference block for a local and a remote source and both runners', async () => {
    const { renderDryRun } = await import(MODULE_URL);
    const head = `## aai-update (dry-run) ${DASH} no files changed\n`;
    const tail = '- Then check: git status --short, .aai/system/AAI_PIN.md, docs/ai/reports/sync-conflicts-*.md\n'
      + '- Next: /aai-doctor (and /aai-bootstrap if skills changed)\n';
    assert.equal(
      renderDryRun({ target: '/t x', desc: 'local checkout /s', runner: BASH_RUNNER }),
      `${head}- Target:   /t x\n- Upstream: local checkout /s\n- Would run: <source>/.aai/scripts/aai-sync.sh "/t x"\n${tail}`,
    );
    assert.equal(
      renderDryRun({ target: '/t', desc: 'https://github.com/acme/foo.git@dev', runner: PS_RUNNER }),
      `${head}- Target:   /t\n- Upstream: https://github.com/acme/foo.git@dev\n- Would run: <source>/.aai/scripts/aai-sync.ps1 -TargetRoot "/t"\n${tail}`,
    );
  });

  test('TEST-3967 renderSyncHeader prints the em dash header', async () => {
    const { renderSyncHeader } = await import(MODULE_URL);
    assert.equal(renderSyncHeader('local checkout /s', '/t'), `## aai-update ${DASH} syncing local checkout /s into /t\n`);
  });

  test('TEST-3967 changedFiles splits the git status output on LF, drops empty lines, keeps CR and reads a failure as none', async () => {
    const { changedFiles } = await import(MODULE_URL);
    const calls = [];
    const spawn = (file, args, opts) => { calls.push({ file, args, opts }); return { status: 0, stdout: ' M a.txt\n?? b c\r\n\n\nA  d\n' }; };
    assert.deepEqual(changedFiles('/t', spawn, { K: '1' }), [' M a.txt', '?? b c\r', 'A  d']);
    assert.equal(calls.length, 1);
    assert.equal(calls[0].file, 'git');
    assert.deepEqual(calls[0].args, ['-C', '/t', 'status', '--short']);
    assert.equal(calls[0].opts.stdio[0], 'ignore');
    assert.equal(calls[0].opts.stdio[1], 'pipe');
    assert.equal(calls[0].opts.stdio[2], 'ignore');
    assert.deepEqual(changedFiles('/t', () => ({ status: 128, stdout: 'fatal\n' }), {}), []);
    assert.deepEqual(changedFiles('/t', () => enoent(), {}), []);
    assert.deepEqual(changedFiles('/t', () => { throw new Error('x'); }, {}), []);
    assert.deepEqual(changedFiles('/t', () => ({ status: 0, stdout: '' }), {}), []);
  });

  test('TEST-3967 changedFiles lifts the output cap and reads a status larger than 1 MiB in full', async () => {
    const { changedFiles } = await import(MODULE_URL);
    let opts;
    changedFiles('/t', (f, a, o) => { opts = o; return { status: 0, stdout: '' }; }, {});
    assert.ok(opts.maxBuffer >= 1024 * 1024 * 1024, 'maxBuffer is at least 1 GiB');
    const t = scratch('bigstatus-');
    const run = (...a) => spawnSync('git', ['-C', t, ...a], { encoding: 'utf8' });
    assert.equal(spawnSync('git', ['init', '-q', t], { encoding: 'utf8' }).status, 0);
    run('config', 'status.showUntrackedFiles', 'all');
    const deep = path.join(t, 'generated', 'a-reasonably-long-directory-name');
    mkdirSync(deep, { recursive: true });
    for (let i = 0; i < 30000; i += 1) writeFileSync(path.join(deep, `file-${String(i).padStart(6, '0')}.txt`), '');
    assert.ok(changedFiles(t).length >= 30000, 'the full status is read');
  });

  test('TEST-3967 pinLines keeps the keyword lines case-insensitively without a byte order mark or a CR, and reads a non-file as null', async () => {
    const { pinLines } = await import(MODULE_URL);
    const lay = layout('pin-');
    assert.equal(pinLines(lay.target), null, 'no pin file');
    const dir = path.join(lay.target, '.aai', 'system');
    mkdirSync(path.join(dir, 'AAI_PIN.md'), { recursive: true });
    assert.equal(pinLines(lay.target), null, 'a directory is not a pin file');
    rmdirSync(path.join(dir, 'AAI_PIN.md'));
    writeFileSync(path.join(dir, 'AAI_PIN.md'), '\uFEFFSource: x\r\nunrelated\r\nTEMPLATE_VERSION: 1\r\nCanonical: y\r\nPrefix: z\r\nCOMMIT abc\r\nnothing here\r\n');
    assert.deepEqual(pinLines(lay.target), ['Source: x', 'TEMPLATE_VERSION: 1', 'Canonical: y', 'Prefix: z', 'COMMIT abc']);
    writeFileSync(path.join(dir, 'AAI_PIN.md'), 'nothing\n');
    assert.deepEqual(pinLines(lay.target), []);
  });

  test('TEST-3967 latestConflict picks the newest regular sync-conflicts report, a tie to the smallest name, and ignores directories', async () => {
    const { latestConflict } = await import(MODULE_URL);
    const lay = layout('conf-');
    assert.equal(latestConflict(lay.target), '', 'no reports directory');
    const dir = path.join(lay.target, 'docs', 'ai', 'reports');
    mkdirSync(dir, { recursive: true });
    assert.equal(latestConflict(lay.target), '', 'an empty directory');
    const put = (name, secs) => { writeFileSync(path.join(dir, name), 'x'); utimesSync(path.join(dir, name), secs, secs); };
    put('sync-conflicts-a.md', 100);
    put('sync-conflicts-b.md', 200);
    put('other.md', 900);
    put('sync-conflicts-x.txt', 900);
    mkdirSync(path.join(dir, 'sync-conflicts-dir.md'));
    utimesSync(path.join(dir, 'sync-conflicts-dir.md'), 950, 950);
    assert.equal(latestConflict(lay.target), 'docs/ai/reports/sync-conflicts-b.md');
    put('sync-conflicts-z.md', 300);
    put('sync-conflicts-m.md', 300);
    assert.equal(latestConflict(lay.target), 'docs/ai/reports/sync-conflicts-m.md');
  });

  test('TEST-3967 renderEvidence prints the changed list with its count, the pin, the conflict advisory and the none line', async () => {
    const { renderEvidence } = await import(MODULE_URL);
    assert.equal(
      renderEvidence({ changed: [' M a', '?? b'], pin: ['Source: x', 'Ref: main'], conflict: 'docs/ai/reports/sync-conflicts-m.md' }),
      `\n## Post-sync evidence\n- Changed files (2):\n   M a\n  ?? b\n- AAI_PIN:\n  Source: x\n  Ref: main\n- ${WARN} Conflict advisory: docs/ai/reports/sync-conflicts-m.md ${DASH} review before committing.\n`,
    );
    assert.equal(renderEvidence({ changed: [], pin: null, conflict: '' }), '\n## Post-sync evidence\n- Changed files: none (already up to date)\n');
    assert.equal(renderEvidence({ changed: ['A  d'], pin: [], conflict: '' }), '\n## Post-sync evidence\n- Changed files (1):\n  A  d\n- AAI_PIN:\n');
  });

  test('TEST-3967 renderNext prints the Recommended line with the bootstrap clause only when files changed', async () => {
    const { renderNext } = await import(MODULE_URL);
    const base = '\n## Next\n- Review the diff (git diff), then commit manually (this tool never auto-commits).\n';
    assert.equal(renderNext(true), `${base}- Recommended: /aai-doctor ; /aai-bootstrap if skills/indexes changed\n`);
    assert.equal(renderNext(false), `${base}- Recommended: /aai-doctor\n`);
  });

  test('TEST-3967 a real run prints header, evidence, doctor report and next in order', async () => {
    const mod = await import(MODULE_URL);
    const lay = layout('flow-');
    const o = await runFake(mod, { argv: ['--repo', lay.source], lay, handler: (c) => (isStatus(c) ? { status: 0, stdout: ' M f\n' } : null) });
    assert.equal(o.code, 0, o.err);
    assert.equal(
      o.out,
      `## aai-update ${DASH} syncing local checkout ${lay.source} into ${lay.target}\n`
      + '\n## Post-sync evidence\n- Changed files (1):\n   M f\n'
      + '\n## Doctor field report\nDOCTOR-REPORT SKIP helper missing - update unaffected\n'
      + '\n## Next\n- Review the diff (git diff), then commit manually (this tool never auto-commits).\n'
      + '- Recommended: /aai-doctor ; /aai-bootstrap if skills/indexes changed\n',
    );
    const none = await runFake(mod, { argv: ['--repo', lay.source], lay });
    assert.ok(none.out.includes('- Changed files: none (already up to date)\n'));
    assert.ok(none.out.endsWith('- Recommended: /aai-doctor\n'));
  });
});

// TEST-3968 -------------------------------------------------------------------------------------------------

const MISSING_LINE = '\n## Doctor field report\nDOCTOR-REPORT SKIP helper missing - update unaffected\n';
const CRASHED_LINE = '\n## Doctor field report\nDOCTOR-REPORT SKIP helper crashed - update unaffected\n';

describe('TEST-3968 doctor postamble', () => {
  const plantHelper = (target) => {
    mkdirSync(path.join(target, '.aai', 'scripts'), { recursive: true });
    writeFileSync(path.join(target, ...HELPER_PATH), '');
    return path.join(target, ...HELPER_PATH);
  };
  const call = async (target, spawn) => {
    const { doctorReport } = await import(MODULE_URL);
    let out = '';
    const ret = doctorReport(target, { out: (s) => { out += s; }, spawn, env: { K: '1', [RUNNER_VAR]: 'bash' } });
    return { out, ret };
  };

  test('TEST-3968 an absent helper and a directory in its place print the missing line and start nothing', async () => {
    const lay = layout('doc-missing-');
    const spawn = fakeSpawn();
    assert.equal((await call(lay.target, spawn)).out, MISSING_LINE);
    mkdirSync(path.join(lay.target, ...HELPER_PATH), { recursive: true });
    assert.equal((await call(lay.target, spawn)).out, MISSING_LINE);
    assert.equal(spawn.calls.length, 0);
  });

  test('TEST-3968 a present helper runs on process.execPath with --root, the target as cwd and inherited stdio', async () => {
    const lay = layout('doc-run-');
    const helper = plantHelper(lay.target);
    const spawn = fakeSpawn(() => ({ status: 0 }));
    const r = await call(lay.target, spawn);
    assert.equal(r.out, '\n## Doctor field report\n');
    assert.equal(spawn.calls.length, 1);
    const c = spawn.calls[0];
    assert.equal(c.file, process.execPath);
    assert.deepEqual(c.args, [helper, '--root', lay.target]);
    assert.equal(c.opts.cwd, lay.target);
    assert.equal(c.opts.stdio, 'inherit');
    assert.equal(c.opts.env.K, '1');
    assert.ok(!(RUNNER_VAR in c.opts.env));
  });

  test('TEST-3968 a nonzero exit, a signal, a start failure and a throwing seam print the crashed line and never throw', async () => {
    const lay = layout('doc-crash-');
    plantHelper(lay.target);
    for (const result of [{ status: 1 }, { status: 2 }, { status: null, signal: 'SIGKILL' }, enoent()]) {
      assert.equal((await call(lay.target, () => result)).out, CRASHED_LINE);
    }
    assert.equal((await call(lay.target, () => { throw new Error('boom'); })).out, CRASHED_LINE);
  });

  test('TEST-3968 the run keeps exit 0 for every helper outcome and starts no helper in a dry-run or after a failed sync', async () => {
    const mod = await import(MODULE_URL);
    for (const [result, line] of [[{ status: 0 }, ''], [{ status: 1 }, 'crashed'], [{ status: null, signal: 'SIGTERM' }, 'crashed'], [enoent(), 'crashed']]) {
      const lay = layout('doc-run-code-');
      plantHelper(lay.target);
      const o = await runFake(mod, { argv: ['--repo', lay.source], lay, handler: (c) => (isHelper(c) ? result : null) });
      assert.equal(o.code, 0, o.err);
      assert.equal(o.out.includes('DOCTOR-REPORT SKIP helper crashed'), line === 'crashed');
      assert.equal(o.others.filter(isHelper).length, 1);
    }
    const dry = layout('doc-dry-');
    plantHelper(dry.target);
    const d = await runFake(mod, { argv: ['--repo', dry.source, '--dry-run'], lay: dry });
    assert.equal(d.code, 0);
    assert.equal(d.others.filter(isHelper).length, 0);
    assert.ok(!d.out.includes('Doctor field report'));
    const failed = layout('doc-failed-');
    plantHelper(failed.target);
    const f = await runFake(mod, { argv: ['--repo', failed.source], lay: failed, handler: (c) => (isSyncAny(c) ? { status: 7 } : null) });
    assert.equal(f.code, 7);
    assert.equal(f.others.filter(isHelper).length, 0);
    assert.ok(!f.out.includes('Doctor field report'));
  });
});

// --- TEST-3969 and TEST-3970: the differential corpora (D-CORPUS) ------------------------------------

const which = (name) => {
  for (const dir of (process.env.PATH ?? '').split(path.delimiter)) {
    if (!dir) continue;
    const file = path.join(dir, name);
    try {
      if (statSync(file).isFile()) return file;
    } catch {
      // not in this directory
    }
  }
  return '';
};
const BASH_PATH = which('bash');
const PWSH_PATH = which('pwsh');
const GIT_PATH = which('git');
const CORPUS_ROOT_ENTRIES = ['.aai-up-owned', 'bin', 'fx', 'fx.ref-side', 'gh-config', 'gh.log', 'git.log', 'gitconfig', 'ref-ps1', 'ref-sh', 'tmp', 'tmp.ref-side'];
const DR1_TAIL = [
  '  powershell -NoProfile -File .aai/scripts/aai-update.ps1 [-Repo X] [-Ref Y] [-DryRun] [-KeepTemp] [-Force]   # the long flags work too',
  'Requires Node.js 22 or later; both launchers run .aai/scripts/aai-update.mjs.',
];
const DRY_NEXT = '- Then check: git status --short, .aai/system/AAI_PIN.md, docs/ai/reports/sync-conflicts-*.md\n- Next: /aai-doctor (and /aai-bootstrap if skills changed)\n';

// The registered DR rewrites: each is applied to the reference's stream and must change at least one byte.
export const REWRITES = {
  'DR-1': { stream: 'stdout', fn: (s) => `${s}${DR1_TAIL.join('\n')}\n` },
  'DR-6': { stream: 'stderr', fn: (s) => s.replace(/^ {2}Pass (?:--force|-Force) to override\.$/m, () => '  Pass --force (or -Force) to override.') },
  'DR-13': { stream: 'stdout', fn: (s) => s.replace(/^(## aai-update(?: \(dry-run\))?) - /m, (m, head) => `${head} ${EM_DASH} `) },
  'DR-14': { stream: 'stdout', fn: (s) => s.replace(/^- ! Conflict advisory: (.+?) - review before committing\.$/m, (m, name) => `- ⚠ Conflict advisory: docs/ai/reports/${name} ${EM_DASH} review before committing.`) },
  'DR-15': {
    stream: 'stdout',
    fn: (s) => s.replace(/^- Recommended: \/aai-doctor \(and \/aai-bootstrap if skills\/indexes changed\)$/m,
      () => (s.includes('- Changed files: none') ? '- Recommended: /aai-doctor' : '- Recommended: /aai-doctor ; /aai-bootstrap if skills/indexes changed')),
  },
  'DR-16': { stream: 'stdout', fn: (s) => s.replace(/^- Would run: SOURCE\//m, () => '- Would run: <source>/') },
  'DR-17': {
    stream: 'stdout',
    fn: (s) => {
      const mark = '- AAI_PIN:\n';
      const at = s.indexOf(mark);
      if (at < 0) return s;
      const lines = s.slice(at + mark.length).split('\n');
      let n = 0;
      const pin = [];
      for (; n < lines.length && lines[n].startsWith('  '); n += 1) pin.push(lines[n].replace(/^ {2}﻿/, () => '  ').replace(/\r$/, ''));
      return s.slice(0, at + mark.length) + [...pin, ...lines.slice(n)].join('\n');
    },
  },
};

// The rewrites every case gets that are not registered: doctor report names and random temp ids (DR-10: the
// PowerShell temp prefix aai-src- reads as aai-src.).
const normText = (s) => s
  .replace(/doctor-\d{8}T\d{6}Z-[a-z0-9-]+\.md/g, () => 'doctor-<stamp>.md')
  .replace(/aai-src\.[A-Za-z0-9]+(?:\.[a-z0-9]+)?/g, () => 'aai-src.<id>');
const readLines = (file) => {
  try {
    return readFileSync(file, 'utf8').split('\n').filter(Boolean);
  } catch {
    return [];
  }
};

function referenceDryRun(target, src) {
  return `## aai-update (dry-run) ${EM_DASH} no files changed\n- Target:   ${target}\n- Upstream: local checkout ${src}\n- Would run: <source>/.aai/scripts/aai-sync.sh "${target}"\n${DRY_NEXT}`;
}

// The asserted divergences: each returns { skip, rewriteRef } after asserting the expected values on both runs.
const DIVERGE = {
  branch: (k, side, ref, mod) => {
    assert.equal(ref.branch, 'main', 'the reference switches the source to --ref in a dry-run');
    assert.equal(mod.branch, 'dev', 'the module leaves the source branch alone (DR-7)');
    assert.notEqual(ref.head, mod.head);
    return { skip: ['branch', 'head'] };
  },
  'not-refused': (k, side, ref, mod) => {
    assert.equal(ref.code, 0);
    assert.ok(ref.stdout.startsWith(`## aai-update (dry-run) ${EM_DASH} no files changed\n`), 'the bash twin does not refuse an upper-case origin');
    assert.equal(mod.code, 2);
    assert.equal(mod.stdout, '');
    assert.equal(mod.stderr, `REFUSED: this project (${k.origin}) looks like the canonical AAI repo.\n  /aai-update syncs AAI INTO a target project; update the canonical repo with normal git.\n  Pass --force (or -Force) to override.\n`);
    return { skip: ['code', 'stdout', 'stderr'] };
  },
  warn: (k, side, ref, mod) => {
    assert.equal(ref.code, 0);
    assert.equal(ref.stderr, "WARN: ignoring unrecognized argument '--bogus'\n");
    assert.ok(ref.stdout.startsWith('## aai-update (dry-run) - no files changed\n'), 'the PowerShell twin goes on after the warning');
    assert.equal(mod.code, 1);
    assert.equal(mod.stderr, 'Unknown argument: --bogus\n');
    assert.equal(mod.stdout, expectedHelp());
    return { skip: ['code', 'stdout', 'stderr'] };
  },
  'needs-value': (k, side, ref, mod) => {
    assert.equal(mod.code, 1);
    assert.equal(mod.stderr, 'aai-update: --repo needs a value\n');
    assert.equal(mod.stdout, '');
    if (side === 'sh') {
      assert.equal(ref.stdout, '', 'the bash twin does nothing else');
      assert.ok(ref.stderr.includes('--repo needs a value'));
    } else {
      assert.ok(!ref.stdout.includes('## Post-sync evidence'), 'the PowerShell twin does no update either (its own binder stops, exit code not compared)');
    }
    return { skip: ['code', 'stdout', 'stderr'] };
  },
  'evidence-after-failure': (k, side, ref, mod) => {
    assert.ok(ref.stdout.includes('## Post-sync evidence'), 'the PowerShell twin goes on to the evidence after a failed sync');
    assert.ok(!mod.stdout.includes('## Post-sync evidence'));
    assert.equal(mod.code, 5);
    assert.ok(![...mod.snap.keys()].some((p) => p.startsWith('docs/ai/reports/doctor-')), 'the module runs no doctor after a failed sync');
    return { skip: ['code', 'stdout', 'tree'] };
  },
  'long-equals-form': (k, side, ref, mod, c) => {
    assert.equal(ref.code, 1);
    assert.equal(ref.stderr, `Unknown argument: --repo=${c.src}\n`);
    assert.equal(mod.code, 0);
    assert.equal(mod.stderr, '');
    assert.equal(mod.stdout, referenceDryRun(c.target, c.src));
    return { skip: ['code', 'stdout', 'stderr'] };
  },
  'powershell-names': (k, side, ref, mod, c) => {
    assert.equal(ref.code, 1);
    assert.equal(ref.stderr, 'Unknown argument: -Repo\n');
    assert.equal(mod.code, 0);
    assert.equal(mod.stderr, '');
    assert.equal(mod.stdout, referenceDryRun(c.target, c.src));
    return { skip: ['code', 'stdout', 'stderr'] };
  },
  'prompt-setting': (k, side, ref, mod) => {
    assert.ok(ref.stdout.includes('FX-GTP=0\n'), 'the PowerShell twin leaves the prompt setting on for the sync');
    assert.ok(mod.stdout.includes('FX-GTP=unset\n'), 'the module sets it for the anonymous clone only');
    return { skip: [], rewriteRef: (s) => s.replace('FX-GTP=0\n', () => 'FX-GTP=unset\n') };
  },
};

// compareRuns(k, side, ref, mod, c): the problems found comparing the reference run with the module run: the
// registered rewrites (each must change a byte), the asserted divergence, then every compared field.
export function compareRuns(k, side, ref0, mod, c) {
  const problems = [];
  const ref = { ...ref0 };
  for (const id of k.rw[side] ?? []) {
    const rule = REWRITES[id];
    if (!rule) {
      problems.push(`${k.id} ${side}: unknown rewrite ${id}`);
      continue;
    }
    const before = ref[rule.stream];
    ref[rule.stream] = rule.fn(before);
    if (ref[rule.stream] === before) problems.push(`${k.id} ${side}: the registered rewrite ${id} changed nothing`);
  }
  let skip = [];
  const name = k.diverge?.[side];
  if (name) {
    const d = DIVERGE[name](k, side, ref, mod, c);
    skip = d.skip;
    if (d.rewriteRef) ref.stdout = d.rewriteRef(ref.stdout);
  }
  const same = (field, a, b) => {
    if (skip.includes(field)) return;
    if (JSON.stringify(a) !== JSON.stringify(b)) problems.push(`${k.id} ${side}: ${field} differs\n--- reference\n${typeof a === 'string' ? a : JSON.stringify(a)}\n--- module\n${typeof b === 'string' ? b : JSON.stringify(b)}`);
  };
  same('code', ref.code, mod.code);
  same('stdout', ref.stdout, mod.stdout);
  same('stderr', ref.stderr, mod.stderr);
  same('branch', ref.branch, mod.branch);
  same('head', ref.head, mod.head);
  same('tmp', ref.tmp, mod.tmp);
  same('gh', ref.gh, mod.gh);
  same('git', ref.git, mod.git);
  if (!skip.includes('tree')) {
    for (const d of compareSnapshots(ref.snap, mod.snap, 'reference:module')) problems.push(`${k.id} ${side}: tree ${d.kind} at ${d.path}: ${d.detail}`);
  }
  return problems;
}

// One run of one entry (the reference or the module) on a freshly built fixture; returns its observations.
function observe(k, side, role, c, runnerValue) {
  const fxEnv = { ...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: path.join(c.root, 'gitconfig') };
  writeFileSync(path.join(c.root, 'gitconfig'), '');
  buildSource(c.src, { head: k.srcHead ?? 'main', omit: k.omit?.[side] ?? '', helperReal: readFileSync(path.join(ROOT, '.aai', 'scripts', 'update-doctor-report.mjs'), 'utf8'), env: fxEnv });
  buildTarget(c.target, { origin: k.origin ?? undefined, repo: k.targetRepo !== false, env: fxEnv });
  for (const f of ['gh.log', 'git.log']) writeFileSync(path.join(c.root, f), '');
  const env = { PWD: c.target, ...(k.env ?? {}), ...(role === 'module' ? { AAI_UPDATE_SYNC_RUNNER: runnerValue } : {}) };
  const res = runUpdate({ entry: role === 'ref' ? side : 'module', args: k.args(c), root: c.root, cwd: c.target, env, gitWrapper: k.gitWrapper ? GIT_PATH : '' });
  assert.equal(res.error, undefined, `${k.id} ${side} ${role}: ${res.error}`);
  assert.equal(res.signal, null, `${k.id} ${side} ${role} ended on a signal`);
  const norm = (s) => normText(role === 'ref' && side === 'ps1' ? s.replace(/aai-src-/g, () => 'aai-src.') : s);
  const obs = {
    code: res.status,
    stdout: norm(res.stdout),
    stderr: norm(res.stderr),
    snap: snapshotNormalized(c.target),
    branch: git(c.src, ['rev-parse', '--abbrev-ref', 'HEAD'], fxEnv).trim(),
    head: git(c.src, ['rev-parse', 'HEAD'], fxEnv).trim(),
    tmp: readdirSync(path.join(c.root, 'tmp'), { recursive: true }).map(String).sort().map(norm),
    gh: readLines(path.join(c.root, 'gh.log')).map(norm),
    git: readLines(path.join(c.root, 'git.log')).map(norm),
  };
  return obs;
}

// runCorpusCase(k, side, runnerValue): builds the case's scratch root, runs the reference, then the module, each on
// a fresh fixture at the same absolute paths (the reference's tree renamed away first), and returns the problems.
export function runCorpusCase(k, side, runnerValue) {
  const root = scratch(`corpus-${k.id}-`);
  const c = { root, src: path.join(root, 'fx', 'src'), target: path.join(root, 'fx', k.targetName ?? 'target') };
  const problems = [];
  try {
    mkdirSync(path.join(root, 'fx'));
    const ref = observe(k, side, 'ref', c, runnerValue);
    renameSync(path.join(root, 'fx'), path.join(root, 'fx.ref-side'));
    renameSync(path.join(root, 'tmp'), path.join(root, 'tmp.ref-side'));
    mkdirSync(path.join(root, 'fx'));
    const mod = observe(k, side, 'module', c, runnerValue);
    problems.push(...compareRuns(k, side, ref, mod, c));
    for (const [who, o] of [['reference', ref], ['module', mod]]) {
      if (k.tmp === 'empty' && o.tmp.length !== 0) problems.push(`${k.id} ${side}: the ${who} left ${JSON.stringify(o.tmp)} in TMPDIR`);
      if (k.tmp === 'one-kept' && JSON.stringify(o.tmp) !== JSON.stringify(['aai-src.<id>'])) problems.push(`${k.id} ${side}: the ${who} should keep exactly one empty temp directory, TMPDIR holds ${JSON.stringify(o.tmp)}`);
      if (k.gh === 'none' && o.gh.length !== 0) problems.push(`${k.id} ${side}: the ${who} called gh in a dry-run: ${JSON.stringify(o.gh)}`);
      for (const line of o.gh) if (!line.startsWith('repo clone ')) problems.push(`${k.id} ${side}: the ${who} ran a gh command other than repo clone: ${line}`);
      for (const line of [...o.gh, ...o.git]) if (line.split(' ').some((w) => /^[a-z][a-z0-9+-]*:\/\//i.test(w) && !w.startsWith('file://'))) problems.push(`${k.id} ${side}: the ${who} reached a non-file URL: ${line}`);
    }
    const extra = readdirSync(root).filter((n) => !CORPUS_ROOT_ENTRIES.includes(n));
    if (extra.length > 0) problems.push(`${k.id} ${side}: the scratch root holds ${JSON.stringify(extra)} beside its fixtures, stubs, logs and marker`);
  } finally {
    removeOwnScratch(root);
    scratchDirs.splice(scratchDirs.indexOf(root), 1);
  }
  return problems;
}

const CORPUS_SKIP = process.platform === 'win32' ? 'the corpora need bash and run on POSIX hosts' : false;
const ALL_IDS = ['U01', 'U02', 'U03', 'U03k', 'U04', 'U05', 'U06', 'U07', 'U08', 'U09', 'U10', 'U11', 'U12', 'U13', 'U13t', 'U14', 'U15', 'U16', 'U17', 'U18', 'U19', 'U20', 'U21', 'U22', 'U23'];

describe('TEST-3969 bash-side corpus', { skip: CORPUS_SKIP || (BASH_PATH && GIT_PATH ? false : 'bash and git are needed') }, () => {
  const cases = U_CASES.filter((k) => k.sides.includes('sh'));
  test('TEST-3969 the corpus holds the bash-side cases of D-CORPUS and only registered rewrites', () => {
    assert.deepEqual(cases.map((k) => k.id), ALL_IDS.filter((id) => id !== 'U13t'));
    for (const k of cases) for (const id of k.rw.sh ?? []) assert.ok(['DR-1', 'DR-6', 'DR-17'].includes(id), `${k.id}: ${id} is not a bash-side rewrite`);
  });
  test('TEST-3969 a rewrite that changes nothing and a one-byte difference both fail the comparison', () => {
    const snap = new Map();
    const run = { code: 0, stdout: 'a\n', stderr: '', snap, branch: 'main', head: 'x', tmp: [], gh: [], git: [] };
    const k = { id: 'UX', rw: { sh: ['DR-6'] } };
    assert.ok(compareRuns(k, 'sh', run, run, {}).some((p) => /DR-6 changed nothing/.test(p)));
    assert.ok(compareRuns({ id: 'UX', rw: { sh: [] } }, 'sh', run, { ...run, stdout: 'a\n\n' }, {}).some((p) => /stdout differs/.test(p)));
    assert.deepEqual(compareRuns({ id: 'UX', rw: { sh: [] } }, 'sh', run, run, {}), []);
  });
  for (const k of cases) {
    test(`TEST-3969 ${k.id} the module and the bash reference agree`, () => {
      assert.deepEqual(runCorpusCase(k, 'sh', 'bash'), []);
    });
  }
});

describe('TEST-3970 PowerShell-side corpus', { skip: CORPUS_SKIP || (PWSH_PATH && BASH_PATH && GIT_PATH ? false : 'pwsh, bash and git are needed') }, () => {
  const cases = U_CASES.filter((k) => k.sides.includes('ps1'));
  test('TEST-3970 the corpus holds the PowerShell-side cases of D-CORPUS and only registered rewrites', () => {
    assert.deepEqual(cases.map((k) => k.id), ALL_IDS.filter((id) => id !== 'U09'));
    for (const k of cases) for (const id of k.rw.ps1 ?? []) assert.ok(['DR-13', 'DR-14', 'DR-15', 'DR-16', 'DR-6'].includes(id), `${k.id}: ${id} is not a PowerShell-side rewrite`);
  });
  for (const k of cases) {
    test(`TEST-3970 ${k.id} the module on the pwsh runner and the PowerShell reference agree`, () => {
      assert.deepEqual(runCorpusCase(k, 'ps1', PWSH_PATH), []);
    });
  }
});
