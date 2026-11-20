// aai-bootstrap.test.mjs - node:test cases of the bootstrap-on-node ride
// (docs/specs/SPEC-0306-spec-bootstrap-on-node.md). Every case name starts with its TEST id; the suite
// tests/skills/test-aai-bootstrap-node.sh selects them with --test-name-pattern.
//
// Scratch safety (D-SAFETY): directories are created and removed only through bootstrap-reference.mjs
// (own prefix, marker, re-verified before removal); no case starts a container tool or kills by pattern.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  appendFileSync, chmodSync, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, symlinkSync, unlinkSync, writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, describe, test } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { K_CASES, K_CASES_AB, K_CASES_C, GOLDEN_EMPTY, GOLDEN_FULL, HOOKS_TEMPLATE_REL } from './aai-bootstrap-fixtures.mjs';
import * as PARITY from './install-parity.mjs';
import { compareSnapshots, snapshotNormalized } from './install-parity.mjs';
import {
  OWN_MARKER_FILE, REFERENCE_BLOB, REFERENCE_COMMIT, REFERENCE_PATH, REFERENCE_SHA256,
  createOwnScratch, materializeBootstrapReference, removeOwnScratch, removeOwnScratchAll, sha256File,
} from './bootstrap-reference.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..', '..');
const MODULE = path.join(ROOT, '.aai', 'scripts', 'aai-bootstrap.mjs');
const REFERENCE = path.join(ROOT, REFERENCE_PATH);
const NEW_TEST_FILES = [
  path.join(ROOT, 'tests', 'skills', 'test-aai-bootstrap-node.sh'),
  path.join(ROOT, 'tests', 'skills', 'aai-bootstrap.Tests.ps1'),
  path.join(HERE, 'aai-bootstrap.test.mjs'),
  path.join(HERE, 'bootstrap-reference.mjs'),
  path.join(HERE, 'aai-bootstrap-fixtures.mjs'),
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

// --- TEST-3940 ---------------------------------------------------------------------------------

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

describe('TEST-3940 scratch safety', () => {
  test('TEST-3940 removeOwnScratch refuses each unsafe path', () => {
    const base = scratch('refuse-');
    const unmarked = path.join(base, 'aai-bs-unmarked');
    mkdirSync(unmarked);
    const foreign = path.join(base, 'foreign-name');
    mkdirSync(foreign);
    writeFileSync(path.join(foreign, OWN_MARKER_FILE), `${process.pid}\n`);
    const nonNumeric = path.join(base, 'aai-bs-badmarker');
    mkdirSync(nonNumeric);
    writeFileSync(path.join(nonNumeric, OWN_MARKER_FILE), 'not-a-pid\n');
    assert.throws(() => removeOwnScratch(''), /empty path/);
    assert.throws(() => removeOwnScratch(undefined), /empty path/);
    assert.throws(() => removeOwnScratch('aai-bs-relative'), /relative path/);
    assert.throws(() => removeOwnScratch(foreign), /own prefix/);
    assert.throws(() => removeOwnScratch(path.join(base, 'aai-bs-missing')), /does not exist/);
    assert.throws(() => removeOwnScratch(unmarked), /marker/);
    assert.throws(() => removeOwnScratch(nonNumeric), /marker/);
    assert.throws(() => removeOwnScratchAll([]), /empty list/);
    for (const kept of [foreign, unmarked, nonNumeric]) assert.ok(existsSync(kept), `${kept} must survive`);
  });

  test('TEST-3940 removeOwnScratch refuses a path outside the temp directory and a symlink', () => {
    const base = scratch('outside-');
    const marked = path.join(base, 'aai-bs-marked');
    mkdirSync(marked);
    writeFileSync(path.join(marked, OWN_MARKER_FILE), `${process.pid}\n`);
    // a child whose temp directory is a sub-directory: the marked directory then lies outside it
    const childTmp = path.join(base, 'childtmp');
    mkdirSync(childTmp);
    const helperUrl = pathToFileURL(path.join(HERE, 'bootstrap-reference.mjs')).href;
    const code = `import(${JSON.stringify(helperUrl)}).then((m) => { try { m.removeOwnScratch(${JSON.stringify(marked)}); console.log('REMOVED'); } catch (e) { console.log(e.message); } });`;
    const r = spawnSync(process.execPath, ['-e', code], {
      encoding: 'utf8', env: { ...process.env, TMPDIR: childTmp, TMP: childTmp, TEMP: childTmp },
    });
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /outside the temp directory/);
    assert.ok(existsSync(marked), 'the outside directory must survive');
    // a symlink with the prefix is refused and its target survives
    const link = path.join(base, 'aai-bs-link');
    symlinkSync(marked, link);
    assert.throws(() => removeOwnScratch(link), /not a real directory/);
    assert.ok(existsSync(marked));
  });

  test('TEST-3940 removeOwnScratch removes a marked own directory and createOwnScratch marks it', () => {
    const dir = createOwnScratch('own-');
    assert.ok(path.basename(dir).startsWith('aai-bs-own-'));
    assert.match(readFileSync(path.join(dir, OWN_MARKER_FILE), 'utf8'), /^[0-9]+\n$/);
    writeFileSync(path.join(dir, 'file'), 'x');
    removeOwnScratch(dir);
    assert.ok(!existsSync(dir));
  });

  test('TEST-3940 the reference copy hashes to the pinned sha256 and equals the pinned commit blob', () => {
    assert.equal(sha256File(REFERENCE), REFERENCE_SHA256);
    assert.match(REFERENCE_SHA256, /^[0-9a-f]{64}$/);
    assert.equal(statSync(REFERENCE).mode & 0o111, 0o111, 'the reference stays executable');
    const has = spawnSync('git', ['cat-file', '-e', `${REFERENCE_COMMIT}^{commit}`], { cwd: ROOT, encoding: 'utf8' });
    if (has.status !== 0) return; // shallow checkout: the hash pin alone holds
    const shown = spawnSync('git', ['show', `${REFERENCE_COMMIT}:.aai/scripts/aai-bootstrap.sh`], { cwd: ROOT, maxBuffer: 16 * 1024 * 1024 });
    assert.equal(shown.status, 0);
    assert.ok(Buffer.compare(shown.stdout, readFileSync(REFERENCE)) === 0, `the copy equals ${REFERENCE_COMMIT}:.aai/scripts/aai-bootstrap.sh (blob ${REFERENCE_BLOB})`);
  });

  test('TEST-3940 materializeBootstrapReference verifies the hash and writes an executable copy', () => {
    const into = path.join(scratch('mat-'), 'tree');
    const dest = materializeBootstrapReference(ROOT, into);
    assert.equal(dest, path.join(into, '.aai', 'scripts', 'aai-bootstrap.sh'));
    assert.equal(sha256File(dest), REFERENCE_SHA256);
    assert.equal(statSync(dest).mode & 0o777, 0o755);
    assert.ok(existsSync(path.join(into, '.aai', 'scripts', 'platform.mjs')));
    // a from-root whose copy was edited fails by naming the file
    const fakeFrom = path.join(scratch('mat-bad-'), 'from');
    mkdirSync(path.join(fakeFrom, path.dirname(REFERENCE_PATH)), { recursive: true });
    writeFileSync(path.join(fakeFrom, REFERENCE_PATH), '#!/bin/sh\necho edited\n');
    assert.throws(() => materializeBootstrapReference(fakeFrom, path.join(scratch('mat-bad2-'), 'x')), (e) => e.message.includes(path.join(fakeFrom, REFERENCE_PATH)) && /hashes to/.test(e.message));
  });

  test('TEST-3940 the new test files hold no call of a container tool or a kill by pattern', () => {
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
    // PowerShell positive control: the scan bites on .ps1 content
    assert.equal(forbiddenCalls(`${d} ps -aq\n`).length, 1);
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

  test('TEST-3940 the scanned list holds every bootstrap test file of tests/skills', () => {
    // Files named for the bootstrap under tests/skills and its lib, minus the pre-existing suite and the golden data.
    const exempt = new Set(['test-aai-bootstrap.sh', 'aai-bootstrap-golden.json']);
    const found = [];
    for (const dir of [path.join(ROOT, 'tests', 'skills'), HERE]) {
      for (const name of readdirSync(dir)) {
        if (/bootstrap/i.test(name) && !exempt.has(name) && statSync(path.join(dir, name)).isFile()) found.push(path.join(dir, name));
      }
    }
    assert.deepEqual(found.sort(), [...NEW_TEST_FILES].sort(), 'a new bootstrap test file must be added to NEW_TEST_FILES');
  });
});

// --- TEST-3941 ---------------------------------------------------------------------------------

const EXPORTS = [
  'parseArgs', 'resolveRoot', 'detect', 'chooseCommands', 'dockerTag', 'detectAuth', 'planSkills', 'wrapTestCommand',
  'renderSkill', 'renderMarker', 'renderIndex', 'renderSummary', 'isManagedFile', 'preflight', 'writeOutputs',
  'ensureGitignore', 'seedRuntimeGitignore', 'installClaudeHooks', 'recordGitPlatform', 'run', 'main',
];

const ANCHORS = [
  "const GENERATOR = '.aai/scripts/aai-bootstrap.sh';",
  "const SKILL_MARKER = 'AAI-DYNAMIC-SKILL:START';",
  "const FILE_MARKER = 'AAI-DYNAMIC-FILE:START';",
  "const RUNTIME_MARKER_PREFIX = '# AAI runtime sidecars';",
  "const RUNTIME_MARKER = '# AAI runtime sidecars (seeded by aai-bootstrap; per-dev, never commit)';",
  "const CACHE_PATTERNS = ['.claude/skills/.cache', '.codex/skills.local/.cache', '.gemini/skills.local/.cache'];",
  "const LOCKFILES = [['pnpm-lock.yaml', 'pnpm'], ['yarn.lock', 'yarn'], ['bun.lock', 'bun'], ['bun.lockb', 'bun']];",
  "const AUTH_SKIP_DIRS = ['node_modules', '.git', 'dist', 'build'];",
  "const HOOKS_UNCHANGED = '0 hook(s) added, 0 updated';",
  'const PLATFORM_MISMATCH = 6;',
  'const EXIT_HOOKS_REFUSED = 3;',
  'const samePlace = (a, b) => a.dev === b.dev && a.ino === b.ino;',
  'const sameContent = (a, b) => stripTrailingNewlines(a) === stripTrailingNewlines(b);',
  "if (pm === 'npm' && script === 'test') return 'npm test';",
  "const runChild = (script, args, cwd) => spawnSync(process.execPath, [script, ...args], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });",
];

// The messages of the reference's three missing-node branches (DR-3), which the module must not hold.
const DR3_MESSAGES = ['node unavailable', 'cannot merge the hooks overlay', 'platform not recorded'];

// The balanced-parenthesis text of every spawnSync( call in the source, from the call name on.
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
    calls.push(source.slice(m.index, i + 1));
  }
  return calls;
}

// moduleShapeProblems(source): the static D-MODULE rules, as a list of problems (empty when clean).
export function moduleShapeProblems(source) {
  const problems = [];
  const specs = [];
  for (const m of source.matchAll(/^\s*import\s[^;]*?\sfrom\s+['"]([^'"]+)['"]/gm)) specs.push(m[1]);
  for (const m of source.matchAll(/^\s*import\s+['"]([^'"]+)['"]/gm)) specs.push(m[1]);
  for (const m of source.matchAll(/\b(?:import|require)\(\s*['"]([^'"]+)['"]/g)) specs.push(m[1]);
  for (const spec of specs) if (!spec.startsWith('node:')) problems.push(`import of ${spec} is not a node: specifier`);
  if (/[^\x00-\x7f]/.test(source)) problems.push('non-ASCII character');
  for (const anchor of ANCHORS) {
    const n = source.split(anchor).length - 1;
    if (n !== 1) problems.push(`anchor appears ${n} times: ${anchor}`);
  }
  for (const call of spawnCalls(source)) {
    if (!call.startsWith('spawnSync(process.execPath')) problems.push(`spawn call does not start with process.execPath: ${call.slice(0, 60)}`);
    for (const word of ['rg', 'grep', 'bash', 'docker', 'gh auth', 'az account']) {
      if (new RegExp(`(^|[^A-Za-z0-9_])${word}([^A-Za-z0-9_]|$)`).test(call)) problems.push(`spawn call holds ${word}`);
    }
  }
  if (/\b(exec|execSync|execFile|execFileSync|spawn|fork)\s*\(/.test(source)) problems.push('a process is started other than through spawnSync');
  if (/shell\s*:\s*true/.test(source)) problems.push('a spawn asks for a shell');
  if (/process\.stdin|readFileSync\(\s*0\b/.test(source)) problems.push('reads standard input');
  for (const msg of DR3_MESSAGES) if (source.includes(msg)) problems.push(`holds the DR-3 message ${msg}`);
  return problems;
}

describe('TEST-3941 module shape', () => {
  test('TEST-3941 importing the module creates nothing and prints nothing', () => {
    const cwd = scratch('import-');
    const before = listTree(cwd);
    const r = spawnSync(process.execPath, ['--input-type=module', '-e', `await import(${JSON.stringify(pathToFileURL(MODULE).href)});`], {
      cwd, encoding: 'utf8',
    });
    assert.equal(r.status, 0, r.stderr);
    assert.equal(r.stdout, '');
    assert.equal(r.stderr, '');
    assert.deepEqual(listTree(cwd), before);
  });

  test('TEST-3941 the module exports the D-MODULE names', async () => {
    const mod = await import(pathToFileURL(MODULE).href);
    for (const name of EXPORTS) assert.equal(typeof mod[name], 'function', `export ${name}`);
  });

  test('TEST-3941 the module imports only node: specifiers and holds each anchor once', () => {
    const source = readFileSync(MODULE, 'utf8');
    assert.deepEqual(moduleShapeProblems(source), []);
    assert.ok(spawnCalls(source).length >= 1, 'the module has a spawn call to check');
  });

  test('TEST-3941 the shape checks report each violation they exist for', () => {
    const good = readFileSync(MODULE, 'utf8');
    const swapped = good.replace('spawnSync(process.execPath, [script', "spawnSync('node', [script");
    assert.ok(moduleShapeProblems(swapped).some((p) => /process\.execPath/.test(p)));
    assert.ok(moduleShapeProblems(`${good}\nimport fs from 'fs';\n`).some((p) => /not a node: specifier/.test(p)));
    assert.ok(moduleShapeProblems(`${good}\nconst GENERATOR = '.aai/scripts/aai-bootstrap.sh';\n`).some((p) => /anchor appears 2 times/.test(p)));
    assert.ok(moduleShapeProblems(good.replace("const FILE_MARKER = 'AAI-DYNAMIC-FILE:START';\n", '')).some((p) => /anchor appears 0 times/.test(p)));
    assert.ok(moduleShapeProblems(good.replace('{ cwd, encoding', "{ cwd, shell: 'grep', encoding")).some((p) => /spawn call holds grep/.test(p)));
    assert.ok(moduleShapeProblems(`${good}\n// ${DR3_MESSAGES[0]}\n`).some((p) => /DR-3/.test(p)));
    assert.ok(moduleShapeProblems(`${good}\nexecSync('ls');\n`).some((p) => /other than through spawnSync/.test(p)));
    assert.ok(moduleShapeProblems(`${good}\n// café\n`).some((p) => /non-ASCII/.test(p)));
    assert.deepEqual(moduleShapeProblems(good), []);
  });
});

// --- TEST-3942 ---------------------------------------------------------------------------------

// The reference's help output, run from the frozen copy: it exits before it reads or writes anything.
function referenceHelp() {
  const r = spawnSync('bash', [REFERENCE, '-h'], { encoding: 'utf8', });
  assert.equal(r.status, 0, r.stderr);
  return r.stdout;
}

// expectedHelp(): DR-1 - the reference help without its first two lines, with the PowerShell usage line
// added right after the usage line.
function expectedHelp() {
  const lines = referenceHelp().split('\n');
  assert.equal(lines[0], 'set -euo pipefail');
  assert.equal(lines[1], '');
  const rest = lines.slice(2);
  const at = rest.findIndex((l) => l.startsWith('  ./.aai/scripts/aai-bootstrap.sh '));
  assert.ok(at >= 0, 'the reference help holds the usage line');
  rest.splice(at + 1, 0, '  powershell -NoProfile -File .aai/scripts/aai-bootstrap.ps1 [target-root] [--dry-run] [--force] [--with-claude-hooks]');
  return rest.join('\n');
}

const cap = () => {
  const o = { out: '', err: '' };
  o.io = { out: (s) => { o.out += s; }, err: (s) => { o.err += s; } };
  return o;
};

describe('TEST-3942 arguments and root', () => {
  test('TEST-3942 modes are read in any position', async () => {
    const { parseArgs } = await import(pathToFileURL(MODULE).href);
    const orders = [
      ['--dry-run', '--force', '--with-claude-hooks', 'tgt'],
      ['tgt', '--with-claude-hooks', '--force', '--dry-run'],
      ['--force', 'tgt', '--dry-run', '--with-claude-hooks'],
    ];
    for (const argv of orders) {
      assert.deepEqual(parseArgs(argv), { dryRun: true, force: true, withClaudeHooks: true, target: 'tgt', outcome: 'run', extra: '' }, argv.join(' '));
    }
    // negative control: a mode that is absent stays off
    assert.deepEqual(parseArgs(['tgt', '--force']), { dryRun: false, force: true, withClaudeHooks: false, target: 'tgt', outcome: 'run', extra: '' });
    assert.deepEqual(parseArgs([]), { dryRun: false, force: false, withClaudeHooks: false, target: '', outcome: 'run', extra: '' });
    // an unknown flag is a target, kept for parity; an empty argument leaves the target unset
    assert.equal(parseArgs(['--bogus']).target, '--bogus');
    const empty = parseArgs(['', 'tgt']);
    assert.equal(empty.target, 'tgt');
    assert.equal(empty.outcome, 'run');
  });

  test('TEST-3942 help and a second positional are decided at their position', async () => {
    const { parseArgs } = await import(pathToFileURL(MODULE).href);
    assert.equal(parseArgs(['-h']).outcome, 'help');
    assert.equal(parseArgs(['--help']).outcome, 'help');
    assert.equal(parseArgs(['a', '-h', 'b']).outcome, 'help');
    assert.equal(parseArgs(['--dry-run', '--help', '--force']).dryRun, true);
    const usage = parseArgs(['a', 'b', '-h']);
    assert.equal(usage.outcome, 'usage');
    assert.equal(usage.extra, 'b');
    assert.equal(parseArgs(['a', 'b', 'c']).extra, 'b');
  });

  test('TEST-3942 help text is the reference help without two lines plus the PowerShell line (DR-1)', async () => {
    const { run, HELP_TEXT } = await import(pathToFileURL(MODULE).href);
    const want = expectedHelp();
    assert.equal(HELP_TEXT, want);
    for (const flag of ['-h', '--help']) {
      const c = cap();
      assert.equal(run([flag], c.io), 0);
      assert.equal(c.out, want);
      assert.equal(c.err, '');
    }
    // help wins over a later problem and exits 0 with nothing on stderr
    const c = cap();
    assert.equal(run(['a', '-h', 'b'], c.io), 0);
    assert.equal(c.out, want);
    assert.equal(c.err, '');
    // the reference prints one more usage line less than the module: exactly the two DR-1 differences
    const refLines = referenceHelp().split('\n');
    assert.equal(want.split('\n').length, refLines.length - 2 + 1);
  });

  test('TEST-3942 a second positional exits 2 with the ERROR line and help on stderr', async () => {
    const { run } = await import(pathToFileURL(MODULE).href);
    const c = cap();
    assert.equal(run(['one', 'two'], c.io), 2);
    assert.equal(c.out, '');
    assert.equal(c.err, `ERROR: unexpected argument: two\n${expectedHelp()}`);
    // the reference exits 2 too, with its ERROR line first on stderr
    const ref = spawnSync('bash', [REFERENCE, 'one', 'two'], { encoding: 'utf8', cwd: scratch('ref2-') });
    assert.equal(ref.status, 2);
    assert.equal(ref.stdout, '');
    assert.ok(ref.stderr.startsWith('ERROR: unexpected argument: two\n'));
    // through the real entry point
    const r = spawnSync(process.execPath, [MODULE, 'one', 'two'], { encoding: 'utf8', cwd: scratch('cli2-') });
    assert.equal(r.status, 2);
    assert.equal(r.stderr, c.err);
  });

  test('TEST-3942 a target that names no directory exits 1 with the DR-2 line and writes nothing', () => {
    const cwd = scratch('baddir-');
    writeFileSync(path.join(cwd, 'afile'), 'x');
    const before = listTree(cwd);
    for (const target of ['no-such-dir', 'afile', '--bogus', path.join(cwd, 'missing', 'deeper')]) {
      const r = spawnSync(process.execPath, [MODULE, target], { encoding: 'utf8', cwd });
      assert.equal(r.status, 1, `${target}: ${r.stderr}`);
      assert.equal(r.stdout, '');
      assert.equal(r.stderr, `aai-bootstrap: target not found: ${target}\n`);
      assert.deepEqual(listTree(cwd), before, `${target} wrote something`);
      // the reference ends with the same exit code and writes nothing either
      const ref = spawnSync('bash', [REFERENCE, target], { encoding: 'utf8', cwd });
      assert.equal(ref.status, 1, `reference on ${target}`);
      assert.equal(ref.stdout, '');
      assert.deepEqual(listTree(cwd), before, `reference on ${target} wrote something`);
    }
    // negative control: an existing directory is not reported as missing
    mkdirSync(path.join(cwd, 'real'));
    const ok = spawnSync(process.execPath, [MODULE, 'real'], { encoding: 'utf8', cwd });
    assert.ok(!ok.stderr.includes('target not found'));
  });

  test('TEST-3942 the targets -- -P -L are refused by the module and bootstrap HOME in the reference (DR-11)', () => {
    const refTree = scratch('cdopt-ref-');
    const ref0 = materializeBootstrapReference(ROOT, refTree);
    for (const target of ['--', '-P', '-L']) {
      const cwd = scratch('cdopt-cwd-');
      const home = scratch('cdopt-home-');
      const env = { ...process.env, HOME: home };
      const beforeCwd = listTree(cwd);
      const beforeHome = listTree(home);
      const r = spawnSync(process.execPath, [MODULE, target], { encoding: 'utf8', cwd, env });
      assert.equal(r.status, 1, `${target}: ${r.stderr}`);
      assert.equal(r.stdout, '');
      assert.equal(r.stderr, `aai-bootstrap: target not found: ${target}\n`);
      assert.deepEqual(listTree(home), beforeHome, `${target} wrote into HOME`);
      assert.deepEqual(listTree(cwd), beforeCwd, `${target} wrote into the working directory`);
      // the reference reads the target as a cd option and lands in the (scratch) HOME
      const ref = spawnSync('bash', [ref0, target], { encoding: 'utf8', cwd, env });
      assert.equal(ref.status, 0, `reference on ${target}: ${ref.stderr}`);
      assert.ok(listTree(home).length > beforeHome.length, `reference on ${target} bootstrapped nothing in HOME`);
      assert.deepEqual(listTree(cwd), beforeCwd, `reference on ${target} wrote into the working directory`);
    }
  });

  test('TEST-3942 resolveRoot keeps the logical path when PWD names the working directory', async () => {
    const { resolveRoot } = await import(pathToFileURL(MODULE).href);
    const base = scratch('root-');
    const real = path.join(base, 'real');
    const link = path.join(base, 'link');
    mkdirSync(real);
    symlinkSync(real, link);
    assert.equal(resolveRoot('', { PWD: link }, real), link);
    assert.equal(resolveRoot('sub', { PWD: link }, real), path.join(link, 'sub'));
    // a target is resolved lexically: dot-dot goes up the logical path
    assert.equal(resolveRoot(path.join('a', '..', 'b'), { PWD: link }, real), path.join(link, 'b'));
    assert.equal(resolveRoot('..', { PWD: link }, real), base);
    // an absolute target ignores the base
    assert.equal(resolveRoot(base, { PWD: link }, real), base);
  });

  test('TEST-3942 a non-canonical PWD records the same target as the reference (D-ROOT)', () => {
    const base = scratch('pwdnc-');
    const refTree = path.join(base, 'ref');
    const refScript = materializeBootstrapReference(ROOT, refTree);
    const dir = path.join(base, 'd');
    mkdirSync(path.join(dir, 'sub'), { recursive: true });
    const real = path.join(base, 'real');
    mkdirSync(real);
    const link = path.join(base, 'link');
    symlinkSync(real, link);
    const targetLine = (out) => out.split('\n').find((l) => l.startsWith('Target: '));
    const cases = [[dir, `${dir}/`], [dir, `${dir}/sub/..`], [dir, `${dir}/./`], [dir, `${dir}//`], [real, link], [real, `${link}/`]];
    for (const [cwd, pwd] of cases) {
      const env = { ...process.env, PWD: pwd };
      const ref = spawnSync('bash', [refScript, '--dry-run'], { encoding: 'utf8', cwd, env });
      const mod = spawnSync(process.execPath, [MODULE, '--dry-run'], { encoding: 'utf8', cwd, env });
      assert.equal(ref.status, 0, ref.stderr);
      assert.equal(mod.status, 0, mod.stderr);
      assert.ok(targetLine(ref.stdout), `reference prints a Target line for PWD ${pwd}`);
      assert.equal(targetLine(mod.stdout), targetLine(ref.stdout), `Target line for PWD ${pwd}`);
    }
  });

  test('TEST-3942 resolveRoot uses the working directory for a stale, relative or absent PWD', async () => {
    const { resolveRoot } = await import(pathToFileURL(MODULE).href);
    const base = scratch('stale-');
    const here = path.join(base, 'here');
    const other = path.join(base, 'other');
    mkdirSync(here);
    mkdirSync(other);
    assert.equal(resolveRoot('', { PWD: other }, here), here);
    assert.equal(resolveRoot('t', { PWD: other }, here), path.join(here, 't'));
    assert.equal(resolveRoot('', { PWD: path.join(base, 'missing') }, here), here);
    assert.equal(resolveRoot('', { PWD: 'here' }, here), here);
    assert.equal(resolveRoot('', {}, here), here);
    assert.equal(resolveRoot('', { PWD: '' }, here), here);
  });

  test('TEST-3942 resolveRoot ignores CDPATH', async () => {
    const { resolveRoot } = await import(pathToFileURL(MODULE).href);
    const base = scratch('cdpath-');
    const here = path.join(base, 'here');
    const elsewhere = path.join(base, 'elsewhere');
    mkdirSync(here);
    mkdirSync(path.join(elsewhere, 'proj'), { recursive: true });
    const env = { PWD: here, CDPATH: elsewhere };
    assert.equal(resolveRoot('proj', env, here), path.join(here, 'proj'));
    assert.equal(resolveRoot('', env, here), here);
    // through the real entry point: the relative name is a missing directory, not the CDPATH one
    const r = spawnSync(process.execPath, [MODULE, 'proj'], { encoding: 'utf8', cwd: here, env: { ...process.env, CDPATH: elsewhere, PWD: here } });
    assert.equal(r.status, 1);
    assert.equal(r.stderr, 'aai-bootstrap: target not found: proj\n');
  });
});

// --- fixtures shared by TEST-3943 to TEST-3945 ---------------------------------------------------

const modP = () => import(pathToFileURL(MODULE).href);

let fxBase = '';
let fxCount = 0;
// fx(files, name): a project directory under one own scratch root. A key ending in / is a directory;
// any other key is a file with the given text (parents are created).
function fx(files = {}, name = 'proj') {
  if (!fxBase) fxBase = scratch('fx-');
  fxCount += 1;
  const root = path.join(fxBase, `case-${fxCount}`, name);
  mkdirSync(root, { recursive: true });
  for (const [rel, body] of Object.entries(files)) {
    const p = path.join(root, rel);
    if (rel.endsWith('/')) mkdirSync(p, { recursive: true });
    else {
      mkdirSync(path.dirname(p), { recursive: true });
      writeFileSync(p, body);
    }
  }
  return root;
}
const pkg = (obj) => JSON.stringify(obj);

// --- TEST-3943 detection -----------------------------------------------------------------------

// [rule, list, entry, positive files, negative files]
const DETECT_RULES = [
  ['package.json file', 'languages', 'JavaScript/TypeScript', { 'package.json': '{}' }, { 'package.json/': '' }],
  ['workspaces key', 'buildTools', 'package.json workspaces', { 'package.json': pkg({ workspaces: ['a'] }) }, { 'package.json': pkg({ name: 'x' }) }],
  ['python pyproject', 'languages', 'Python', { 'pyproject.toml': '' }, { 'README.md': '' }],
  ['python requirements', 'languages', 'Python', { 'requirements.txt': '' }, { 'requirements.txt/': '' }],
  ['python poetry.lock', 'languages', 'Python', { 'poetry.lock': '' }, {}],
  ['python uv.lock', 'languages', 'Python', { 'uv.lock': '' }, {}],
  ['python setup.cfg', 'languages', 'Python', { 'setup.cfg': '' }, {}],
  ['python setup.py', 'languages', 'Python', { 'setup.py': '' }, {}],
  ['poetry manager', 'packageManagers', 'poetry (poetry.lock)', { 'poetry.lock': '' }, { 'uv.lock': '' }],
  ['uv manager', 'packageManagers', 'uv (uv.lock)', { 'uv.lock': '' }, { 'poetry.lock': '', 'uv.lock/': '' }],
  ['pip manager', 'packageManagers', 'pip/python (python manifest)', { 'requirements.txt': '' }, { 'poetry.lock': '' }],
  ['go language', 'languages', 'Go', { 'go.mod': '' }, {}],
  ['go modules', 'packageManagers', 'go modules (go.mod)', { 'go.mod': '' }, {}],
  ['rust language', 'languages', 'Rust', { 'Cargo.toml': '' }, {}],
  ['cargo', 'packageManagers', 'cargo (Cargo.toml)', { 'Cargo.toml': '' }, {}],
  ['java language', 'languages', 'Java', { 'pom.xml': '' }, {}],
  ['maven', 'packageManagers', 'maven (pom.xml)', { 'pom.xml': '' }, {}],
  ['gradle build.gradle', 'languages', 'Java/Kotlin', { 'build.gradle': '' }, {}],
  ['gradle kts', 'languages', 'Java/Kotlin', { 'build.gradle.kts': '' }, {}],
  ['gradle wrapper', 'packageManagers', 'gradle', { gradlew: '' }, {}],
  ['playwright config', 'testTools', 'Playwright', { 'playwright.config.ts': '' }, { 'playwright.cfg.ts': '', 'Playwright.config.ts': '' }],
  ['playwright config as a directory', 'testTools', 'Playwright', { 'playwright.config.d/': '' }, {}],
  ['cypress config', 'testTools', 'Cypress', { 'cypress.config.js': '' }, { 'cypress.json': '' }],
  ['jest config', 'testTools', 'Jest', { 'jest.config.js': '' }, { 'jest.js': '' }],
  ['vitest config', 'testTools', 'Vitest', { 'vitest.config.ts': '' }, {}],
  ['vitest dependency', 'testTools', 'Vitest', { 'package.json': pkg({ devDependencies: { vitest: '1' } }) }, { 'package.json': pkg({ scripts: { vitest: 'x' } }) }],
  ['vitest peer dependency', 'testTools', 'Vitest', { 'package.json': pkg({ peerDependencies: { vitest: '1' } }) }, { 'package.json': '{not json' }],
  ['pytest.ini', 'testTools', 'pytest', { 'pytest.ini': '' }, {}],
  ['tox.ini', 'testTools', 'pytest', { 'tox.ini': '' }, { 'setup.cfg': '' }],
  ['tests directory', 'testTools', 'test directory', { 'tests/': '' }, { tests: 'a file' }],
  ['test directory', 'testTools', 'test directory', { 'test/': '' }, {}],
  ['vite config', 'buildTools', 'Vite', { 'vite.config.js': '' }, {}],
  ['webpack config', 'buildTools', 'Webpack', { 'webpack.config.js': '' }, {}],
  ['tsconfig', 'buildTools', 'TypeScript (tsconfig.json)', { 'tsconfig.json': '' }, { 'tsconfig.base.json': '' }],
  ['Dockerfile', 'buildTools', 'Dockerfile', { Dockerfile: '' }, {}],
  ['compose.yml', 'buildTools', 'Docker Compose', { 'compose.yml': '' }, { 'compose.yaml': '' }],
  ['docker-compose.yml', 'buildTools', 'Docker Compose', { 'docker-compose.yml': '' }, {}],
  ['Makefile', 'buildTools', 'Makefile', { Makefile: '' }, {}],
  ['makefile', 'buildTools', 'Makefile', { makefile: '' }, {}],
  ['justfile', 'buildTools', 'justfile', { justfile: '' }, {}],
  ['Justfile', 'buildTools', 'justfile', { Justfile: '' }, {}],
  ['eslintrc glob', 'lintTools', 'ESLint config', { '.eslintrc.json': '' }, {}],
  ['eslint.config.js', 'lintTools', 'ESLint config', { 'eslint.config.js': '' }, { 'eslint.config.ts': '' }],
  ['eslint.config.mjs', 'lintTools', 'ESLint config', { 'eslint.config.mjs': '' }, {}],
  ['eslint.config.cjs', 'lintTools', 'ESLint config', { 'eslint.config.cjs': '' }, {}],
  ['biome.json', 'lintTools', 'Biome', { 'biome.json': '' }, {}],
  ['biome.jsonc', 'lintTools', 'Biome', { 'biome.jsonc': '' }, {}],
  ['ruff.toml', 'lintTools', 'Ruff', { 'ruff.toml': '' }, {}],
  ['ruff in pyproject', 'lintTools', 'Python lint config (pyproject.toml)', { 'pyproject.toml': '[tool.ruff]\n' }, { 'pyproject.toml': '[tool.poetry]\n' }],
  ['flake8 in pyproject', 'lintTools', 'Python lint config (pyproject.toml)', { 'pyproject.toml': 'x\n[tool.flake8]\n' }, { 'setup.cfg': '[tool.ruff]\n' }],
  ['black in pyproject', 'lintTools', 'Python lint config (pyproject.toml)', { 'pyproject.toml': '[tool.black]\n' }, {}],
  ['github workflows', 'ci', '.github/workflows', { '.github/workflows/': '' }, { '.github/workflows': 'a file' }],
  ['wrangler', 'deploy', 'Cloudflare Wrangler', { 'wrangler.toml': '' }, {}],
  ['vercel', 'deploy', 'Vercel', { 'vercel.json': '' }, {}],
  ['netlify', 'deploy', 'Netlify', { 'netlify.toml': '' }, {}],
];

describe('TEST-3943 detection', () => {
  test('TEST-3943 every rule answers its positive and negative fixture', async () => {
    const { detect } = await modP();
    for (const [rule, list, entry, pos, neg] of DETECT_RULES) {
      assert.ok(detect(fx(pos))[list].includes(entry), `${rule}: positive`);
      assert.ok(!detect(fx(neg))[list].includes(entry), `${rule}: negative`);
    }
  });

  test('TEST-3943 an empty project detects nothing', async () => {
    const { detect } = await modP();
    assert.deepEqual(detect(fx({})), {
      languages: [], packageManagers: [], testTools: [], buildTools: [], lintTools: [], ci: [], deploy: [], vitest: false,
    });
  });

  test('TEST-3943 lockfile precedence is pnpm before yarn before bun before npm', async () => {
    const { detect } = await modP();
    const pm = (files) => detect(fx({ 'package.json': '{}', ...files })).packageManagers;
    assert.deepEqual(pm({ 'pnpm-lock.yaml': '', 'yarn.lock': '', 'bun.lock': '' }), ['pnpm (package.json)']);
    assert.deepEqual(pm({ 'yarn.lock': '', 'bun.lock': '' }), ['yarn (package.json)']);
    assert.deepEqual(pm({ 'bun.lock': '' }), ['bun (package.json)']);
    assert.deepEqual(pm({ 'bun.lockb': '' }), ['bun (package.json)']);
    assert.deepEqual(pm({}), ['npm (package.json)']);
    // negative control: lockfiles without a package.json name no manager
    assert.deepEqual(detect(fx({ 'pnpm-lock.yaml': '' })).packageManagers, []);
  });

  test('TEST-3943 lists keep first-seen order without duplicates', async () => {
    const { detect } = await modP();
    const d = detect(fx({
      '.eslintrc.json': '', 'eslint.config.js': '', 'eslint.config.mjs': '', 'biome.json': '', 'biome.jsonc': '',
      'package.json': pkg({ workspaces: [], devDependencies: { vitest: '1' } }), 'vitest.config.ts': '',
      'go.mod': '', 'Cargo.toml': '', 'pom.xml': '', 'build.gradle': '', 'gradlew': '', 'pyproject.toml': '[tool.ruff]', 'poetry.lock': '', 'uv.lock': '',
      'Makefile': '', 'justfile': '', 'Dockerfile': '', 'tsconfig.json': '', 'vite.config.js': '',
      'wrangler.toml': '', 'vercel.json': '', 'netlify.toml': '', '.github/workflows/': '', 'tests/': '', 'jest.config.js': '', 'playwright.config.ts': '',
    }));
    assert.deepEqual(d.lintTools, ['ESLint config', 'Biome', 'Python lint config (pyproject.toml)']);
    assert.deepEqual(d.languages, ['JavaScript/TypeScript', 'Python', 'Go', 'Rust', 'Java', 'Java/Kotlin']);
    assert.deepEqual(d.packageManagers, ['npm (package.json)', 'poetry (poetry.lock)', 'go modules (go.mod)', 'cargo (Cargo.toml)', 'maven (pom.xml)', 'gradle']);
    assert.deepEqual(d.testTools, ['Playwright', 'Jest', 'Vitest', 'test directory']);
    assert.deepEqual(d.buildTools, ['package.json workspaces', 'Vite', 'TypeScript (tsconfig.json)', 'Dockerfile', 'Makefile', 'justfile']);
    assert.deepEqual(d.deploy, ['Cloudflare Wrangler', 'Vercel', 'Netlify']);
    assert.equal(d.vitest, true);
  });

  test('TEST-3943 package.json queries answer false for invalid JSON, null and non-objects', async () => {
    const { detect, chooseCommands } = await modP();
    for (const body of ['{not json', 'null', '[]', '"workspaces"', '42', '']) {
      const root = fx({ 'package.json': body });
      const d = detect(root);
      assert.ok(!d.buildTools.includes('package.json workspaces'), `workspaces on ${JSON.stringify(body)}`);
      assert.equal(d.vitest, false, `vitest on ${JSON.stringify(body)}`);
      assert.equal(chooseCommands(root).unit, null, `unit on ${JSON.stringify(body)}`);
      assert.ok(d.languages.includes('JavaScript/TypeScript'), 'package.json is still a file');
    }
    // valid JSON answers true
    assert.equal(chooseCommands(fx({ 'package.json': pkg({ scripts: { test: 'x' } }) })).unit, 'npm test');
    // a script name is an own property only
    assert.equal(chooseCommands(fx({ 'package.json': pkg({ scripts: { constructor: 'x' } }) })).unit, null);
  });
});

// --- TEST-3944 commands ------------------------------------------------------------------------

const P = (o) => ({ 'package.json': pkg(o) });
const RUN = (t) => ({ [t]: 'x' });

// [label, files, chain, expected]
const COMMAND_CASES = [
  // unit: task runner, scripts, tools, languages
  ['unit justfile test-unit', { justfile: 'test-unit:\n  x\n' }, 'unit', 'just test-unit'],
  ['unit Justfile', { Justfile: 'unit:\n  x\n' }, 'unit', 'just unit'],
  ['unit justfile with args', { justfile: 'test arg:\n  x\n' }, 'unit', 'just test'],
  ['unit justfile indented', { justfile: '  test:\n  x\n' }, 'unit', 'just test'],
  ['unit Makefile', { Makefile: 'unit:\n\tx\n' }, 'unit', 'make unit'],
  ['unit makefile space before colon', { makefile: 'test : \n\tx\n' }, 'unit', 'make test'],
  ['unit makefile target with args is no target', { Makefile: 'test arg:\n\tx\n' }, 'unit', null],
  ['unit justfile before Makefile', { justfile: 'test:\n x\n', Makefile: 'test:\n\tx\n' }, 'unit', 'just test'],
  ['unit target order beats file order', { justfile: 'unit:\n x\n', Makefile: 'test-unit:\n\tx\n' }, 'unit', 'make test-unit'],
  ['unit target prefix is no target', { justfile: 'test-units:\n x\n' }, 'unit', null],
  ['unit script test:unit', P({ scripts: { 'test:unit': 'x', test: 'y' } }), 'unit', 'npm run test:unit'],
  ['unit script unit', P({ scripts: { unit: 'x', test: 'y' } }), 'unit', 'npm run unit'],
  ['unit npm test special case', P({ scripts: { test: 'x' } }), 'unit', 'npm test'],
  ['unit pnpm run', { ...P({ scripts: { test: 'x' } }), 'pnpm-lock.yaml': '' }, 'unit', 'pnpm run test'],
  ['unit yarn run', { ...P({ scripts: { test: 'x' } }), 'yarn.lock': '' }, 'unit', 'yarn run test'],
  ['unit bun run', { ...P({ scripts: { test: 'x' } }), 'bun.lockb': '' }, 'unit', 'bun run test'],
  ['unit runner beats scripts', { ...P({ scripts: { test: 'x' } }), Makefile: 'test:\n\tx\n' }, 'unit', 'make test'],
  ['unit vitest config', { 'vitest.config.ts': '' }, 'unit', 'npx vitest run'],
  ['unit vitest dep pnpm', { ...P({ devDependencies: { vitest: '1' } }), 'pnpm-lock.yaml': '' }, 'unit', 'pnpm exec vitest run'],
  ['unit vitest dep yarn', { ...P({ dependencies: { vitest: '1' } }), 'yarn.lock': '' }, 'unit', 'yarn exec vitest run'],
  ['unit vitest dep bun', { ...P({ devDependencies: { vitest: '1' } }), 'bun.lock': '' }, 'unit', 'bunx vitest run'],
  ['unit jest config', { 'jest.config.js': '' }, 'unit', 'npx jest'],
  ['unit jest dep', P({ optionalDependencies: { jest: '1' } }), 'unit', 'npx jest'],
  ['unit vitest before jest', { 'vitest.config.ts': '', 'jest.config.js': '' }, 'unit', 'npx vitest run'],
  ['unit pytest.ini', { 'pytest.ini': '' }, 'unit', 'pytest'],
  ['unit pytest in pyproject', { 'pyproject.toml': 'dependencies = ["pytest"]\n' }, 'unit', 'pytest'],
  ['unit pytest in requirements', { 'requirements.txt': 'pytest\n' }, 'unit', 'pytest'],
  ['unit pytest in setup.cfg', { 'setup.cfg': '[tool:pytest]\n' }, 'unit', 'pytest'],
  ['unit pytest in tox.ini', { 'tox.ini': 'commands = pytest\n' }, 'unit', 'pytest'],
  ['unit pytest below a directory', { 'requirements.txt/base.txt': 'pytest\n' }, 'unit', 'pytest'],
  ['unit no pytest evidence', { 'pyproject.toml': '[tool.poetry]\n' }, 'unit', null],
  ['unit go', { 'go.mod': '' }, 'unit', 'go test ./...'],
  ['unit cargo', { 'Cargo.toml': '' }, 'unit', 'cargo test'],
  ['unit maven', { 'pom.xml': '' }, 'unit', 'mvn test'],
  ['unit gradlew', { gradlew: '', 'build.gradle': '' }, 'unit', './gradlew test'],
  ['unit gradle', { 'build.gradle.kts': '' }, 'unit', 'gradle test'],
  ['unit nothing', {}, 'unit', null],
  // e2e: gate first
  ['e2e gate closed without config or script', { justfile: 'test-e2e:\n x\n' }, 'e2e', null],
  ['e2e playwright config', { 'playwright.config.ts': '' }, 'e2e', 'npx playwright test'],
  ['e2e cypress config', { 'cypress.config.js': '' }, 'e2e', 'npx cypress run'],
  ['e2e playwright before cypress', { 'playwright.config.ts': '', 'cypress.config.js': '' }, 'e2e', 'npx playwright test'],
  ['e2e runner test-e2e', { 'playwright.config.ts': '', justfile: 'test-e2e:\n x\n' }, 'e2e', 'just test-e2e'],
  ['e2e runner test_e2e', { 'cypress.config.js': '', Makefile: 'test_e2e:\n\tx\n' }, 'e2e', 'make test_e2e'],
  ['e2e script test:e2e opens the gate', P({ scripts: { 'test:e2e': 'x' } }), 'e2e', 'npm run test:e2e'],
  ['e2e script e2e opens the gate', P({ scripts: { e2e: 'x' } }), 'e2e', 'npm run e2e'],
  ['e2e script playwright', { 'playwright.config.ts': '', ...P({ scripts: { playwright: 'x' } }) }, 'e2e', 'npm run playwright'],
  ['e2e script cypress:run', { 'cypress.config.js': '', ...P({ scripts: { 'cypress:run': 'x' } }) }, 'e2e', 'npm run cypress:run'],
  ['e2e script cy:run', { 'cypress.config.js': '', ...P({ scripts: { 'cy:run': 'x' } }) }, 'e2e', 'npm run cy:run'],
  ['e2e pnpm exec playwright', { 'playwright.config.ts': '', 'pnpm-lock.yaml': '', ...P({}) }, 'e2e', 'pnpm exec playwright test'],
  ['e2e playwright dependency under a cypress config', { 'cypress.config.js': '', ...P({ devDependencies: { playwright: '1' } }) }, 'e2e', 'npx playwright test'],
  ['e2e @playwright/test dependency under a cypress config', { 'cypress.config.js': '', ...P({ devDependencies: { '@playwright/test': '1' } }) }, 'e2e', 'npx playwright test'],
  ['e2e cypress dependency', { 'cypress.config.js': '', ...P({ devDependencies: { cypress: '1' } }) }, 'e2e', 'npx cypress run'],
  // build
  ['build runner build', { justfile: 'build:\n x\n' }, 'build', 'just build'],
  ['build runner compile', { Makefile: 'compile:\n\tx\n' }, 'build', 'make compile'],
  ['build script build', P({ scripts: { build: 'x' } }), 'build', 'npm run build'],
  ['build script compile', P({ scripts: { compile: 'x' } }), 'build', 'npm run compile'],
  ['build vite config', { 'vite.config.js': '' }, 'build', 'npx vite build'],
  ['build vite dep', P({ devDependencies: { vite: '1' } }), 'build', 'npx vite build'],
  ['build webpack config', { 'webpack.config.js': '' }, 'build', 'npx webpack'],
  ['build webpack dep bun', { ...P({ dependencies: { webpack: '1' } }), 'bun.lock': '' }, 'build', 'bunx webpack'],
  ['build tsc needs the dependency', { 'tsconfig.json': '', ...P({ devDependencies: { typescript: '5' } }) }, 'build', 'npx tsc --noEmit'],
  ['build tsc without the dependency', { 'tsconfig.json': '', ...P({}) }, 'build', null],
  ['build go', { 'go.mod': '' }, 'build', 'go build ./...'],
  ['build cargo', { 'Cargo.toml': '' }, 'build', 'cargo build'],
  ['build maven', { 'pom.xml': '' }, 'build', 'mvn package'],
  ['build gradlew', { gradlew: '' }, 'build', './gradlew build'],
  ['build gradle', { 'build.gradle': '' }, 'build', 'gradle build'],
  ['build Dockerfile', { Dockerfile: '' }, 'build', 'docker build -t proj- .'],
  ['build Dockerfile is the last step', { Dockerfile: '', 'go.mod': '' }, 'build', 'go build ./...'],
  ['build nothing', {}, 'build', null],
  // lint
  ['lint runner lint', { justfile: 'lint:\n x\n' }, 'lint', 'just lint'],
  ['lint runner check', { Makefile: 'check:\n\tx\n' }, 'lint', 'make check'],
  ['lint runner lint-check', { Makefile: 'lint-check:\n\tx\n' }, 'lint', 'make lint-check'],
  ['lint script typecheck', P({ scripts: { typecheck: 'x' } }), 'lint', 'npm run typecheck'],
  ['lint script check', P({ scripts: { check: 'x' } }), 'lint', 'npm run check'],
  ['lint eslint flat config', { 'eslint.config.mjs': '' }, 'lint', 'npx eslint .'],
  ['lint eslintrc', { '.eslintrc.json': '' }, 'lint', 'npx eslint .'],
  ['lint eslint dep', P({ devDependencies: { eslint: '9' } }), 'lint', 'npx eslint .'],
  ['lint biome config', { 'biome.jsonc': '' }, 'lint', 'npx biome check .'],
  ['lint biome dep', P({ devDependencies: { '@biomejs/biome': '1' } }), 'lint', 'npx biome check .'],
  ['lint eslint before biome', { 'eslint.config.js': '', 'biome.json': '' }, 'lint', 'npx eslint .'],
  ['lint ruff.toml', { 'ruff.toml': '' }, 'lint', 'ruff check .'],
  ['lint ruff in pyproject', { 'pyproject.toml': '[tool.ruff]\n' }, 'lint', 'ruff check .'],
  ['lint ruff in requirements', { 'requirements.txt': 'ruff\n' }, 'lint', 'ruff check .'],
  ['lint ruff in setup.cfg is not read', { 'setup.cfg': 'ruff\n' }, 'lint', null],
  ['lint flake8 in setup.cfg', { 'setup.cfg': '[flake8]\n' }, 'lint', 'flake8'],
  ['lint flake8 in tox.ini', { 'tox.ini': '[flake8]\n' }, 'lint', 'flake8'],
  ['lint go', { 'go.mod': '' }, 'lint', 'go vet ./...'],
  ['lint cargo', { 'Cargo.toml': '' }, 'lint', 'cargo clippy --all-targets --all-features'],
  ['lint nothing', {}, 'lint', null],
  // monty
  ['monty pyproject', { 'pyproject.toml': '' }, 'monty', `python -c "import pydantic_monty; print('pydantic-monty available')"`],
  ['monty setup.py', { 'setup.py': '' }, 'monty', `python -c "import pydantic_monty; print('pydantic-monty available')"`],
  ['monty not python', { 'go.mod': '' }, 'monty', null],
  // deploy
  ['deploy runner', { justfile: 'deploy:\n x\n' }, 'deploy', 'just deploy'],
  ['deploy runner publish', { Makefile: 'publish:\n\tx\n' }, 'deploy', 'make publish'],
  ['deploy script release', P({ scripts: { release: 'x' } }), 'deploy', 'npm run release'],
  ['deploy wrangler', { 'wrangler.toml': '' }, 'deploy', 'wrangler deploy'],
  ['deploy vercel', { 'vercel.json': '' }, 'deploy', 'vercel deploy'],
  ['deploy netlify', { 'netlify.toml': '' }, 'deploy', 'netlify deploy'],
  ['deploy nothing', {}, 'deploy', null],
];

describe('TEST-3944 commands', () => {
  test('TEST-3944 each chain step answers its fixture', async () => {
    const { chooseCommands } = await modP();
    for (const [label, files, chain, want] of COMMAND_CASES) {
      assert.equal(chooseCommands(fx(files))[chain], want, label);
    }
  });

  test('TEST-3944 chooseCommands names every chain', async () => {
    const { chooseCommands } = await modP();
    assert.deepEqual(Object.keys(chooseCommands(fx({}))).sort(), ['build', 'deploy', 'e2e', 'lint', 'monty', 'unit']);
  });

  test('TEST-3944 dockerTag lowers, replaces and folds, keeping the trailing dash for parity', async () => {
    const { dockerTag } = await modP();
    assert.equal(dockerTag('/x/My Proj--X'), 'my-proj-x-');
    assert.equal(dockerTag('/x/plain'), 'plain-');
    assert.equal(dockerTag('/x/a_b.c-d'), 'a_b.c-d-');
    assert.equal(dockerTag('/x/Caf\u00e9 \u00dc'), 'caf-');
    assert.equal(dockerTag('/x/trailing/'), 'trailing-');
    assert.equal(dockerTag('/x/A--B---C'), 'a-b-c-');
  });

  test('TEST-3944 wrapTestCommand emits the two-line Windows and POSIX form', async () => {
    const { wrapTestCommand } = await modP();
    assert.equal(wrapTestCommand('npm test'), 'Windows: powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1 npm test\nPOSIX: bash .aai/scripts/aai-run-tests.sh npm test');
  });
});

// --- TEST-3945 auth and plan -------------------------------------------------------------------

const PW = { 'playwright.config.ts': 'export default {};\n' };
const SESSION_NONE = 'No reusable auth session detected; create globalSetup/storageState before scaling E2E coverage.';
const SESSION_FOUND = 'Existing globalSetup/storageState signal detected.';

describe('TEST-3945 auth and plan', () => {
  test('TEST-3945 no auth is detected without an e2e command', async () => {
    const { detectAuth } = await modP();
    const root = fx({ 'src/login.ts': 'login\n' });
    assert.deepEqual(detectAuth(root), { detected: false, credentialsRef: '', sessionRef: '' });
    // negative control: the same tree with an e2e gate detects it
    assert.equal(detectAuth(fx({ ...PW, 'src/login.ts': 'login\n' })).detected, true);
  });

  test('TEST-3945 a signal only under a skipped directory is not found, one in a hidden file is', async () => {
    const { detectAuth } = await modP();
    for (const skipped of ['node_modules', 'dist', 'build', '.git']) {
      assert.equal(detectAuth(fx({ ...PW, [`src/${skipped}/x.js`]: 'jwt\n', 'src/ok.js': 'nothing\n' })).detected, false, `under ${skipped}`);
    }
    // skipped at any depth, and the top-level candidate walk skips it too
    assert.equal(detectAuth(fx({ ...PW, 'tests/a/b/node_modules/x.js': 'auth\n' })).detected, false);
    assert.equal(detectAuth(fx({ ...PW, 'src/.hidden.ts': 'clerk\n' })).detected, true);
    assert.equal(detectAuth(fx({ ...PW, 'src/.cfg/deep/x.ts': 'passport\n' })).detected, true);
    // a file that merely has a skipped name is read
    assert.equal(detectAuth(fx({ ...PW, 'src/dist': 'session\n' })).detected, true);
  });

  test('TEST-3945 candidate paths and the alternation, case-insensitively', async () => {
    const { detectAuth } = await modP();
    const words = ['login', 'sign-in', 'auth', 'session', 'jwt', 'passport', 'next-auth', 'clerk', 'requireAuth', 'withAuth', 'storageState', 'globalSetup'];
    for (const w of words) {
      assert.equal(detectAuth(fx({ ...PW, 'src/a.ts': `x ${w.toUpperCase()} y\n` })).detected, true, w);
    }
    for (const dir of ['app', 'src', 'pages', 'components', 'routes', 'tests', 'e2e', 'cypress']) {
      assert.equal(detectAuth(fx({ ...PW, [`${dir}/a.ts`]: 'login\n' })).detected, true, dir);
    }
    assert.equal(detectAuth(fx({ ...PW, 'package.json': '{"name":"auth-demo"}' })).detected, true, 'package.json');
    assert.equal(detectAuth(fx({ ...PW, 'middleware.ts': 'auth\n' })).detected, true, 'middleware.ts');
    assert.equal(detectAuth(fx({ ...PW, 'middleware.js': 'auth\n' })).detected, true, 'middleware.js');
    assert.equal(detectAuth(fx({ 'cypress.config.js': 'module.exports = { auth: 1 };\n' })).detected, true, 'cypress config');
    assert.equal(detectAuth(fx({ 'playwright.config.ts': 'storageState\n' })).detected, true, 'playwright config');
    // negative controls: not a candidate path, and a clean candidate
    assert.equal(detectAuth(fx({ ...PW, 'lib/a.ts': 'login\n' })).detected, false);
    assert.equal(detectAuth(fx({ ...PW, 'src/a.ts': 'nothing to see\n' })).detected, false);
  });

  test('TEST-3945 the walk follows directory symlinks once and ends on a cycle', async () => {
    const { detectAuth } = await modP();
    const root = fx({ ...PW, 'src/a.ts': 'nothing\n' });
    symlinkSync(path.join(root, 'src'), path.join(root, 'src', 'loop'));
    assert.equal(detectAuth(root).detected, false);
    const other = fx({ 'target/x.ts': 'login\n' });
    const root2 = fx({ ...PW, 'src/': '' });
    symlinkSync(path.join(other, 'target'), path.join(root2, 'src', 'link'));
    assert.equal(detectAuth(root2).detected, true);
  });

  test('TEST-3945 the credential reference prefers FACTS.md, then the first env file with names', async () => {
    const { detectAuth } = await modP();
    const base = { ...PW, 'src/a.ts': 'login\n' };
    const FACTS = 'docs/knowledge/FACTS.md, section "Test Credentials"';
    assert.equal(detectAuth(fx({ ...base, 'docs/knowledge/FACTS.md': '# Facts\n\n## Test Credentials\n- x\n', '.env.e2e': 'TEST_USER=a\n' })).credentialsRef, FACTS);
    assert.equal(detectAuth(fx({ ...base, 'docs/knowledge/FACTS.md': '# Facts\n## Other\n', '.env.e2e': 'TEST_USER=a\nE2E_PASSWORD=b\nOTHER_USER=c\nAUTH_TOKEN=t\nLOGIN_EMAIL=e\nCYPRESS_PASS=p\nPLAYWRIGHT_USER=u\nTESTING=1\n' })).credentialsRef,
      '.env.e2e variable names: TEST_USER, E2E_PASSWORD, AUTH_TOKEN, LOGIN_EMAIL, CYPRESS_PASS, PLAYWRIGHT_USER');
    // an env file without names is skipped for the next one; .env.e2e wins over .env.test
    assert.equal(detectAuth(fx({ ...base, '.env.test': 'FOO=1\n', '.env.testing': 'E2E_USER=z\n' })).credentialsRef, '.env.testing variable names: E2E_USER');
    assert.equal(detectAuth(fx({ ...base, '.env.e2e': 'TEST_USER=a\n', '.env.test': 'TEST_USER=b\n' })).credentialsRef, '.env.e2e variable names: TEST_USER');
    // CRLF lines, a value holding another name, a header that is not the section
    assert.equal(detectAuth(fx({ ...base, '.env.e2e': 'TEST_USER=a\r\nTEST_X=1_PASS=2\r\n' })).credentialsRef, '.env.e2e variable names: TEST_USER, TEST_X');
    assert.equal(detectAuth(fx({ ...base, 'docs/knowledge/FACTS.md': '  ## Test Credentials\n' })).credentialsRef, '');
    // none at all
    assert.equal(detectAuth(fx(base)).credentialsRef, '');
  });

  test('TEST-3945 the session line says whether a globalSetup or storageState signal exists', async () => {
    const { detectAuth } = await modP();
    assert.equal(detectAuth(fx({ ...PW, 'src/a.ts': 'login\n' })).sessionRef, SESSION_NONE);
    assert.equal(detectAuth(fx({ ...PW, 'src/a.ts': 'login\n', 'tests/b.ts': 'use(storageState)\n' })).sessionRef, SESSION_FOUND);
    assert.equal(detectAuth(fx({ ...PW, 'src/a.ts': 'login\n', 'tests/b.ts': 'GLOBALSETUP\n' })).sessionRef, SESSION_FOUND);
    // the signal under a skipped directory does not count
    assert.equal(detectAuth(fx({ ...PW, 'src/a.ts': 'login\n', 'tests/node_modules/b.ts': 'storageState\n' })).sessionRef, SESSION_NONE);
  });

  test('TEST-3945 the plan of an empty project skips every skill with the reference message', async () => {
    const { planSkills } = await modP();
    assert.deepEqual(planSkills(fx({})), {
      skills: [],
      skipped: [
        'aai-test-unit: no unit test command detected',
        'aai-test-e2e: no E2E command detected',
        'aai-build: no build command detected',
        'aai-lint: no lint command detected',
        'aai-python-monty: Python project not detected',
      ],
    });
  });

  test('TEST-3945 the plan keeps the skill order and wraps the unit and e2e commands', async () => {
    const { planSkills, wrapTestCommand } = await modP();
    const root = fx({
      ...P({ scripts: { test: 'x', build: 'x', lint: 'x', deploy: 'x' } }), 'playwright.config.ts': '', 'pyproject.toml': '',
    });
    const plan = planSkills(root);
    assert.deepEqual(plan.skills.map((s) => s.name), ['aai-test-unit', 'aai-test-e2e', 'aai-build', 'aai-lint', 'aai-python-monty', 'aai-deploy']);
    assert.deepEqual(plan.skipped, []);
    const [unit, e2e, build, lint, monty, deploy] = plan.skills;
    assert.equal(unit.command, wrapTestCommand('npm test'));
    assert.equal(unit.description, 'Run project unit tests with the detected project command (routed through the leak-safe wrapper).');
    assert.equal(e2e.command, wrapTestCommand('npx playwright test'));
    assert.equal(e2e.description, 'Run project E2E tests with the detected project command (routed through the leak-safe wrapper).');
    assert.equal(build.command, 'npm run build');
    assert.equal(build.description, 'Build or type-check the project with the detected project command.');
    assert.equal(lint.command, 'npm run lint');
    assert.equal(lint.description, 'Run project lint or static checks with the detected project command.');
    assert.equal(monty.description, 'Use pydantic-monty as a safe scratchpad for small isolated Python logic before normal project validation.');
    assert.equal(deploy.command, 'npm run deploy');
    assert.equal(deploy.description, 'Deploy or publish the project with the detected project command.');
    // a skill without a command is skipped, deploy never is
    const partial = planSkills(fx({ 'go.mod': '' }));
    assert.deepEqual(partial.skills.map((s) => s.name), ['aai-test-unit', 'aai-build', 'aai-lint']);
    assert.deepEqual(partial.skipped, ['aai-test-e2e: no E2E command detected', 'aai-python-monty: Python project not detected']);
  });

  test('TEST-3945 the e2e prerequisites block follows the auth result', async () => {
    const { planSkills } = await modP();
    const e2eOf = (files) => planSkills(fx(files)).skills.find((s) => s.name === 'aai-test-e2e');
    assert.equal(e2eOf(PW).extra, '');
    assert.equal(e2eOf({ ...PW, 'src/a.ts': 'login\n' }).extra,
      `## Prerequisites\n- Authentication detected. Add non-secret test credential references to docs/knowledge/FACTS.md; keep actual values in ignored env files or a secret manager.\n- ${SESSION_NONE}\n`);
    assert.equal(e2eOf({ ...PW, 'src/a.ts': 'login globalSetup\n', '.env.test': 'TEST_USER=a\n' }).extra,
      `## Prerequisites\n- Authentication detected. Test credential reference: .env.test variable names: TEST_USER\n- ${SESSION_FOUND}\n`);
  });

  test('TEST-3945 the vitest and monty blocks appear only for their projects', async () => {
    const { planSkills } = await modP();
    const unit = planSkills(fx({ 'vitest.config.ts': '' })).skills[0];
    assert.ok(unit.extra.startsWith('## Leak-safe Vitest configuration (bounds fork memory)\n'));
    assert.ok(unit.extra.endsWith('so no fork worker can outlive the step.\n'));
    assert.equal(planSkills(fx({ 'jest.config.js': '' })).skills[0].extra, '');
    const monty = planSkills(fx({ 'pyproject.toml': '' })).skills.find((s) => s.name === 'aai-python-monty');
    assert.ok(monty.extra.startsWith('## Monty Scratchpad Workflow\n- Use Monty only before implementation'));
    assert.ok(monty.extra.endsWith("print(m.run(inputs={\"value\": \"  Example  \"}))\nPY\n```\n"));
    assert.equal(planSkills(fx({ 'go.mod': '' })).skills.find((s) => s.name === 'aai-python-monty'), undefined);
  });

  test('TEST-3945 detection, commands and plan equal the reference on shared fixtures', async () => {
    const { detect, planSkills } = await modP();
    const tree = path.join(scratch('refplan-'), 'tree');
    materializeBootstrapReference(ROOT, tree);
    const refScript = path.join(tree, '.aai', 'scripts', 'aai-bootstrap.sh');
    const CASES = [
      ['empty', {}],
      ['node full', {
        ...P({ scripts: { test: 'x', build: 'x', lint: 'x', deploy: 'x' }, devDependencies: { vitest: '1', eslint: '9' }, workspaces: ['a'] }),
        'playwright.config.ts': 'export default {};\n', 'src/login.ts': 'login\n', 'docs/knowledge/FACTS.md': '## Test Credentials\n', 'tests/': '', '.github/workflows/': '', 'pnpm-lock.yaml': '',
      }],
      ['node npm jest tsc', { ...P({ devDependencies: { jest: '1', typescript: '5' } }), 'jest.config.js': '', 'tsconfig.json': '{}', 'eslint.config.js': '' }],
      ['cypress env creds', { ...P({ scripts: { 'cy:run': 'x' } }), 'cypress.config.js': 'module.exports = {};\n', 'e2e/a.cy.js': 'cy.login()\n', '.env.e2e': 'E2E_USER=a\nE2E_PASSWORD=b\n', 'yarn.lock': '' }],
      ['python', { 'pyproject.toml': '[tool.ruff]\ndependencies = ["pytest"]\n', 'requirements.txt': 'pytest\n', 'uv.lock': '', 'tests/': '' }],
      ['python poetry flake8', { 'poetry.lock': '', 'setup.cfg': '[flake8]\n', 'tox.ini': '' }],
      ['go', { 'go.mod': '', 'Dockerfile': '' }],
      ['rust', { 'Cargo.toml': '', 'wrangler.toml': '' }],
      ['maven', { 'pom.xml': '', 'vercel.json': '' }],
      ['gradle wrapper', { gradlew: '', 'build.gradle': '', 'netlify.toml': '' }],
      ['gradle kts', { 'build.gradle.kts': '' }],
      ['justfile and Makefile', { justfile: 'test-unit:\n x\n  lint:\n x\n', Makefile: 'build:\n\tx\ncheck:\n\tx\ndeploy:\n\tx\n' }],
      ['docker only', { Dockerfile: '', 'compose.yml': '' }, 'My Proj--X'],
      ['bun vite webpack', { ...P({ dependencies: { vite: '1', webpack: '1', 'cypress': '1' } }), 'bun.lockb': '', 'vite.config.js': '', 'webpack.config.js': '', 'cypress.config.ts': '', 'biome.json': '' }],
      ['vitest peer and e2e script', P({ peerDependencies: { vitest: '1' }, scripts: { 'test:e2e': 'x', typecheck: 'x', publish: 'x' } })],
      ['invalid package.json', { 'package.json': '{oops', 'playwright.config.ts': '' }],
    ];
    for (const [label, files, name] of CASES) {
      const root = fx(files, name ?? 'proj');
      const d = detect(root);
      const plan = planSkills(root);
      const r = spawnSync('bash', [refScript, root], { encoding: 'utf8', cwd: path.dirname(root), env: { ...process.env, AAI_ROLE: '' } });
      assert.equal(r.status, 0, `${label}: reference exited ${r.status}: ${r.stderr}`);
      const marker = readFileSync(path.join(root, '.claude', 'skills', 'AAI_DYNAMIC_SKILLS.md'), 'utf8');
      const section = (title) => {
        const m = marker.match(new RegExp(`### ${title}\\n([\\s\\S]*?)\\n\\n(?:###|##) `));
        assert.ok(m, `${label}: marker section ${title}`);
        return m[1].split('\n').map((l) => l.replace(/^- /, '')).filter((l) => !/^(Not detected)$/.test(l));
      };
      assert.deepEqual(d.languages, section('Languages'), `${label}: languages`);
      assert.deepEqual(d.packageManagers, section('Package/Dependency Managers'), `${label}: package managers`);
      assert.deepEqual(d.testTools, section('Test Tooling'), `${label}: test tooling`);
      assert.deepEqual(d.buildTools, section('Build Tooling'), `${label}: build tooling`);
      assert.deepEqual(d.lintTools, section('Lint Tooling'), `${label}: lint tooling`);
      assert.deepEqual([...d.ci, ...d.deploy], section('CI/CD Signals'), `${label}: CI/CD`);
      const skipped = marker.match(/## Skipped Skills\n([\s\S]*?)\nThese files are generated/)[1].split('\n').map((l) => l.replace(/^- /, '')).filter((l) => l && l !== 'None');
      assert.deepEqual(plan.skipped, skipped, `${label}: skipped`);
      const refSkills = [];
      for (const s of plan.skills) {
        const text = readFileSync(path.join(root, '.claude', 'skills', s.name, 'SKILL.md'), 'utf8');
        const m = text.match(/^---\nname: (.*)\ndescription: (.*)\n---\n[\s\S]*?\n```(?:bash)?\n([\s\S]*?)\n```\n\n([\s\S]*?)\n## Notes\n- Generated from/);
        assert.ok(m, `${label}: ${s.name} parses`);
        refSkills.push({ name: m[1], description: m[2], command: m[3], extra: m[4] });
      }
      assert.deepEqual(plan.skills, refSkills, `${label}: skills`);
      const refDirs = readdirSync(path.join(root, '.claude', 'skills')).filter((n) => n.startsWith('aai-') && statSync(path.join(root, '.claude', 'skills', n)).isDirectory()).sort();
      assert.deepEqual(plan.skills.map((s) => s.name).sort(), refDirs, `${label}: the reference wrote no other skill`);
    }
  });
});

// --- slice b: rendering, writes, .gitignore and the masked corpus ---------------------------------

const GOLDEN = JSON.parse(readFileSync(path.join(HERE, 'aai-bootstrap-golden.json'), 'utf8'));
const NOW = '2026-01-02T03:04:05Z';
const fill = (text, root, now = NOW) => text.split('@ROOT@').join(root).split('@NOW@').join(now);
const strip = (text) => text.replace(/\n+$/, '');
const RUNTIME_LIST = path.join(ROOT, '.aai', 'system', 'RUNTIME_IGNORE.list');
const runtimePatterns = () => readFileSync(RUNTIME_LIST, 'utf8').split('\n').filter((l) => l !== '' && !l.startsWith('#'));
const SEED_MARKER = '# AAI runtime sidecars (seeded by aai-bootstrap; per-dev, never commit)';
const CACHE = ['.claude/skills/.cache', '.codex/skills.local/.cache', '.gemini/skills.local/.cache'];

// parseSummary(text): the lists the summary holds, read back from the reference's stdout.
function summaryLists(text) {
  const block = (title) => {
    const m = text.match(new RegExp(`\\n${title}:\\n([\\s\\S]*?)(?:\\n\\n|\\n$)`));
    return m ? m[1].split('\n').map((l) => l.replace(/^- /, '')) : [];
  };
  return { written: block('Generated/updated files').filter((l) => l !== 'No file changes'), unchanged: block('Unchanged files'), platform: block('Git platform') };
}

// --- TEST-3946 ---------------------------------------------------------------------------------

describe('TEST-3946 rendering', () => {
  test('TEST-3946 renderSkill returns the reference bytes for every skill of a full plan', async () => {
    const { renderSkill, planSkills } = await modP();
    const root = fx(GOLDEN_FULL);
    const plan = planSkills(root);
    assert.deepEqual(plan.skills.map((s) => s.name).sort(), Object.keys(GOLDEN.skills).sort());
    for (const skill of plan.skills) {
      assert.equal(renderSkill(skill), strip(fill(GOLDEN.skills[skill.name], root)), skill.name);
    }
  });

  test('TEST-3946 the fence rule and the empty extra block', async () => {
    const { renderSkill } = await modP();
    const base = { name: 'aai-x', description: 'd', extra: '' };
    const wrapped = renderSkill({ ...base, command: 'Windows: a\nPOSIX: b' });
    assert.ok(wrapped.includes('Run from the repository root:\n\n```\nWindows: a\nPOSIX: b\n```\n'), 'a newline gives an empty fence');
    const oneLine = renderSkill({ ...base, command: 'powershell -File .aai/scripts/aai-run-tests.ps1 npm test' });
    assert.ok(oneLine.includes('\n```\npowershell -File .aai/scripts/aai-run-tests.ps1 npm test\n```\n'), 'a one-line ps1 command gives an empty fence');
    const plain = renderSkill({ ...base, command: 'npm run build' });
    assert.ok(plain.includes('\n```bash\nnpm run build\n```\n'), 'a plain command gives a bash fence');
    assert.ok(plain.includes('```\n\n\n## Notes\n'), 'an empty extra block leaves two empty lines');
    assert.ok(renderSkill({ ...base, command: 'x', extra: 'EXTRA\n' }).includes('```\n\nEXTRA\n\n## Notes\n'));
    assert.ok(plain.endsWith('<!-- AAI-DYNAMIC-SKILL:END -->'), 'trailing newlines are removed');
  });

  test('TEST-3946 renderMarker and renderIndex return the reference bytes with and without skills', async () => {
    const { renderMarker, renderIndex, planSkills, detect } = await modP();
    const root = fx(GOLDEN_FULL);
    const plan = planSkills(root);
    const det = detect(root);
    assert.equal(renderMarker(plan, det, { now: NOW, root }), strip(fill(GOLDEN.marker, root)));
    assert.equal(renderIndex('Codex', plan, NOW), strip(fill(GOLDEN.codex, root)));
    assert.equal(renderIndex('Gemini', plan, NOW), strip(fill(GOLDEN.gemini, root)));
    const eroot = fx(GOLDEN_EMPTY);
    const eplan = planSkills(eroot);
    const edet = detect(eroot);
    assert.equal(renderMarker(eplan, edet, { now: NOW, root: eroot }), strip(fill(GOLDEN.markerEmpty, eroot)));
    assert.equal(renderIndex('Codex', eplan, NOW), strip(fill(GOLDEN.codexEmpty, eroot)));
    assert.equal(renderIndex('Gemini', eplan, NOW), strip(fill(GOLDEN.geminiEmpty, eroot)));
    for (const text of [GOLDEN.markerEmpty, GOLDEN.codexEmpty]) assert.ok(/- None( generated)?\n/.test(text), 'a fallback line exists in the golden');
  });

  test('TEST-3946 the CI and deploy signals are one joined list', async () => {
    const { renderMarker, planSkills, detect } = await modP();
    const root = fx({ '.github/workflows/': '', 'wrangler.toml': '', 'vercel.json': '' });
    const text = renderMarker(planSkills(root), detect(root), { now: NOW, root });
    assert.ok(text.includes('### CI/CD Signals\n- .github/workflows\n- Cloudflare Wrangler\n- Vercel\n\n## Generated Skills\n'));
    const none = fx({});
    assert.ok(renderMarker(planSkills(none), detect(none), { now: NOW, root: none }).includes('### CI/CD Signals\n- Not detected\n'));
  });

  test('TEST-3946 renderSummary returns the reference stdout for each summary shape', async () => {
    const { renderSummary, planSkills, detect, detectAuth } = await modP();
    const shapes = [
      ['first', GOLDEN_FULL, { dryRun: false, force: false }],
      ['rerun', GOLDEN_FULL, { dryRun: false, force: false }],
      ['dry', GOLDEN_FULL, { dryRun: true, force: true }],
      ['empty', GOLDEN_EMPTY, { dryRun: false, force: false }],
    ];
    for (const [key, files, mode] of shapes) {
      const root = fx(files);
      const text = fill(GOLDEN.summaries[key], root);
      const lists = summaryLists(text);
      const plan = planSkills(root);
      const got = renderSummary({
        root, ...mode, det: detect(root), auth: detectAuth(root), plan, written: lists.written, unchanged: lists.unchanged, platformLines: lists.platform.join('\n'),
      });
      assert.equal(got, text, key);
    }
    // sections that depend on the inputs: no auth, no platform, no unchanged, empty written
    const root = fx({});
    const bare = renderSummary({ root, dryRun: false, force: false, det: detect(root), auth: detectAuth(root), plan: planSkills(root), written: [], unchanged: [], platformLines: '' });
    assert.ok(!bare.includes('Auth notes:') && !bare.includes('Git platform:') && !bare.includes('Unchanged files:'));
    assert.ok(bare.includes('Ready-to-use commands:\n- None generated\n'));
    assert.ok(bare.includes('Generated/updated files:\n- No file changes\n'));
    assert.ok(bare.includes('Skipped:\n- aai-test-unit: no unit test command detected\n'));
  });
});

// --- TEST-3947 ---------------------------------------------------------------------------------

describe('TEST-3947 writes and conflicts', () => {
  const ctxFor = async (root, extra = {}) => {
    const m = await modP();
    return { m, ctx: { plan: m.planSkills(root), det: m.detect(root), now: NOW, dryRun: false, runtimeList: RUNTIME_LIST, ...extra } };
  };
  const SKILL = '.claude/skills/aai-build/SKILL.md';

  test('TEST-3947 isManagedFile accepts a missing path and each managed mark, and refuses the rest', async () => {
    const { isManagedFile } = await modP();
    const dir = fx({});
    const at = (body) => {
      const f = path.join(dir, `f${fxCount += 1}.md`);
      writeFileSync(f, body);
      return f;
    };
    assert.equal(isManagedFile(path.join(dir, 'missing.md')), true);
    assert.equal(isManagedFile(dir), true, 'not a regular file counts as managed');
    for (const mark of ['AAI-DYNAMIC-SKILL:START', 'AAI-DYNAMIC-FILE:START', 'Generated by: .aai/scripts/aai-bootstrap.sh', 'generated by aai-bootstrap', 'AAI Dynamic Skills']) {
      assert.equal(isManagedFile(at(`x\n${mark}\ny\n`)), true, mark);
    }
    // the GENERATOR dots match any character
    assert.equal(isManagedFile(at('Generated by: Xaai/scripts/aai-bootstrapYsh\n')), true);
    assert.equal(isManagedFile(at('Generated by: .aai/scripts/aai-bootstrap.s\n')), false);
    assert.equal(isManagedFile(at('my own skill\n')), false);
    assert.equal(isManagedFile(at('')), false);
    assert.equal(isManagedFile(at('generated BY aai-bootstrap\n')), false, 'marks are case-sensitive');
  });

  test('TEST-3947 preflight lists the conflict of each unmarked file in write order and force clears them', async () => {
    const root = fx({ ...K01_PLAN_FILES, '.claude/skills/aai-build/SKILL.md': 'mine\n', '.claude/skills/aai-lint/SKILL.md': 'AAI-DYNAMIC-SKILL:START\n', '.claude/skills/AAI_DYNAMIC_SKILLS.md': 'mine\n', '.codex/skills.local/README.md': 'mine\n', '.gemini/skills.local/README.md': 'AAI Dynamic Skills\n' });
    const { m, ctx } = await ctxFor(root);
    const why = (p) => `${p} exists and is not marked as AAI-generated; rerun with --force to replace it`;
    assert.deepEqual(m.preflight(root, ctx.plan, false), [why(SKILL), why('.claude/skills/AAI_DYNAMIC_SKILLS.md'), why('.codex/skills.local/README.md')]);
    assert.deepEqual(m.preflight(root, ctx.plan, true), []);
    // a missing file and a directory in the way are no conflict
    const clean = fx(K01_PLAN_FILES);
    assert.deepEqual(m.preflight(clean, (await ctxFor(clean)).ctx.plan, false), []);
    const dirRoot = fx({ ...K01_PLAN_FILES, '.claude/skills/aai-build/SKILL.md/': '' });
    assert.deepEqual(m.preflight(dirRoot, (await ctxFor(dirRoot)).ctx.plan, false), []);
  });

  test('TEST-3947 run refuses unmarked files with the three stderr lines and exit 1 before any write', async () => {
    const { run } = await modP();
    const root = fx({ ...K01_PLAN_FILES, [SKILL]: 'mine\n' });
    const before = listTree(root);
    const c = cap();
    assert.equal(run([], { ...c.io, env: { PWD: root }, cwd: root, now: () => new Date('2026-01-02T03:04:05Z') }), 1);
    assert.equal(c.out, '');
    assert.equal(c.err, `ERROR: bootstrap would overwrite unmarked files.\n- ${SKILL} exists and is not marked as AAI-generated; rerun with --force to replace it\nRerun with --force only if replacing these files is intentional.\n`);
    assert.deepEqual(listTree(root), before);
    assert.equal(readFileSync(path.join(root, SKILL), 'utf8'), 'mine\n');
    // with --force the file is replaced and the run ends 0
    const f = cap();
    assert.equal(run(['--force'], { ...f.io, env: { PWD: root }, cwd: root, now: () => new Date('2026-01-02T03:04:05Z') }), 0);
    assert.ok(readFileSync(path.join(root, SKILL), 'utf8').includes('AAI-DYNAMIC-SKILL:START'));
    assert.ok(f.out.startsWith(`\nAAI bootstrap summary\nTarget: ${root}\nForce: true\n`));
  });

  test('TEST-3947 writeOutputs writes content plus one newline in the fixed order', async () => {
    const root = fx(K01_PLAN_FILES);
    const { m, ctx } = await ctxFor(root);
    const r = m.writeOutputs(root, ctx);
    const names = ctx.plan.skills.map((s) => `.claude/skills/${s.name}/SKILL.md`);
    assert.deepEqual(r.written.slice(0, names.length + 3), [...names, '.claude/skills/AAI_DYNAMIC_SKILLS.md', '.codex/skills.local/README.md', '.gemini/skills.local/README.md']);
    assert.ok(r.written[names.length + 3].startsWith('.gitignore'), 'the gitignore entries come last');
    assert.deepEqual(r.unchanged, []);
    for (const n of names) {
      const text = readFileSync(path.join(root, n), 'utf8');
      assert.ok(text.endsWith('<!-- AAI-DYNAMIC-SKILL:END -->\n') && !text.endsWith('\n\n'));
    }
  });

  test('TEST-3947 a file equal after trailing newlines is unchanged, a different one is rewritten', async () => {
    const root = fx(K01_PLAN_FILES);
    const { m, ctx } = await ctxFor(root);
    m.writeOutputs(root, ctx);
    const file = path.join(root, SKILL);
    appendFileSync(file, '\n\n\n');
    const again = m.writeOutputs(root, ctx);
    assert.ok(again.unchanged.includes(SKILL), 'extra trailing newlines still count as unchanged');
    assert.ok(!again.written.includes(SKILL));
    assert.ok(readFileSync(file, 'utf8').endsWith('\n\n\n\n'), 'an unchanged file is not touched');
    writeFileSync(file, `${readFileSync(file, 'utf8').replace('npm run build', 'npm run other')}`);
    const third = m.writeOutputs(root, ctx);
    assert.ok(third.written.includes(SKILL));
    assert.ok(readFileSync(file, 'utf8').includes('npm run build'));
  });

  test('TEST-3947 dry-run lists the paths and writes nothing, even the unchanged check holds', async () => {
    const root = fx(K01_PLAN_FILES);
    const { m, ctx } = await ctxFor(root, { dryRun: true });
    const before = listTree(root);
    const r = m.writeOutputs(root, ctx);
    assert.ok(r.written.includes(`[dry-run] ${SKILL}`));
    assert.ok(r.written.includes('[dry-run] .claude/skills/AAI_DYNAMIC_SKILLS.md'));
    assert.deepEqual(listTree(root), before);
    // an existing equal file is listed unchanged even in dry-run
    const real = await ctxFor(root);
    real.m.writeOutputs(root, real.ctx);
    const dry = m.writeOutputs(root, ctx);
    assert.ok(dry.unchanged.includes(SKILL));
    assert.ok(!dry.written.includes(`[dry-run] ${SKILL}`));
  });

  test('TEST-3947 a file holding a NUL byte is rewritten (DR-7)', async () => {
    const root = fx(K01_PLAN_FILES);
    const { m, ctx } = await ctxFor(root);
    m.writeOutputs(root, ctx);
    const file = path.join(root, SKILL);
    writeFileSync(file, `${readFileSync(file, 'utf8')}\0`);
    const again = m.writeOutputs(root, ctx);
    assert.ok(again.written.includes(SKILL), 'a NUL-holding file differs from the new content');
    assert.ok(!readFileSync(file, 'utf8').includes('\0'));
  });
});

// The files of GOLDEN_FULL that decide a plan with build and lint skills.
const K01_PLAN_FILES = { 'package.json': pkg({ scripts: { build: 'x', lint: 'x' } }) };

// --- TEST-3948 ---------------------------------------------------------------------------------

describe('TEST-3948 gitignore', () => {
  const run = async (root, opts = {}) => (await modP()).ensureGitignore(root, { dryRun: false, runtimeList: RUNTIME_LIST, ...opts });
  const text = (root) => readFileSync(path.join(root, '.gitignore'), 'utf8');
  const N = () => runtimePatterns().length;

  test('TEST-3948 a missing .gitignore is only listed in dry-run and created otherwise', async () => {
    const dry = fx({});
    assert.deepEqual(await run(dry, { dryRun: true }), ['[dry-run] .gitignore']);
    assert.ok(!existsSync(path.join(dry, '.gitignore')));
    const root = fx({});
    const lines = await run(root);
    assert.deepEqual(lines, [...CACHE.map((p) => `.gitignore add ${p}`), `.gitignore add ${N()} AAI runtime sidecar pattern(s)`]);
    assert.equal(text(root), `${CACHE.map((p) => `\n${p}\n`).join('')}\n${SEED_MARKER}\n${runtimePatterns().join('\n')}\n`);
    assert.equal(N(), 30);
  });

  test('TEST-3948 cache patterns go after a blank line and a CR-suffixed line is not counted', async () => {
    const root = fx({ '.gitignore': 'node_modules/' });
    await run(root);
    assert.ok(text(root).startsWith(`node_modules/\n${CACHE[0]}\n\n${CACHE[1]}\n\n${CACHE[2]}\n\n${SEED_MARKER}\n`), 'a missing final newline is completed by the blank-line echo');
    const crlf = fx({ '.gitignore': `${CACHE[0]}\r\n` });
    const lines = await run(crlf);
    assert.ok(lines.includes(`.gitignore add ${CACHE[0]}`), 'a CR-suffixed cache line does not count as present');
    assert.ok(!lines.includes(`.gitignore add ${CACHE[1]}x`));
    // exact lines count as present
    const present = fx({ '.gitignore': `${CACHE.join('\n')}\n` });
    assert.deepEqual((await run(present)).filter((l) => l.includes('.cache')), []);
  });

  test('TEST-3948 runtime patterns are compared against a CR-stripped target', async () => {
    const all = runtimePatterns();
    const root = fx({ '.gitignore': `${CACHE.join('\r\n')}\r\n${all.join('\r\n')}\r\n` });
    const lines = await run(root);
    assert.deepEqual(lines.filter((l) => l.includes('sidecar')), [], 'every pattern is present behind its carriage return');
    const partial = fx({ '.gitignore': `${all.slice(0, 5).join('\r\n')}\r\n` });
    assert.ok((await run(partial)).includes(`.gitignore add ${all.length - 5} AAI runtime sidecar pattern(s)`));
  });

  test('TEST-3948 the marker is written once and never when a line starts with the prefix', async () => {
    const root = fx({});
    await run(root);
    assert.equal(text(root).split('\n').filter((l) => l.startsWith('# AAI runtime sidecars')).length, 1);
    assert.deepEqual(await run(root), [], 'a second run adds nothing');
    const legacy = fx({ '.gitignore': '# AAI runtime sidecars (seeded from sync)\n' });
    await run(legacy);
    assert.equal(text(legacy).split('\n').filter((l) => l.startsWith('# AAI runtime sidecars')).length, 1, 'the legacy marker suppresses a second one');
    assert.ok(!text(legacy).includes(SEED_MARKER));
    assert.ok(text(legacy).includes(runtimePatterns()[0]));
  });

  test('TEST-3948 dry-run prints the count line and writes nothing', async () => {
    const root = fx({ '.gitignore': 'node_modules/\n' });
    const lines = await run(root, { dryRun: true });
    assert.deepEqual(lines, [...CACHE.map((p) => `[dry-run] .gitignore add ${p}`), `[dry-run] .gitignore add ${N()} AAI runtime sidecar pattern(s)`]);
    assert.equal(text(root), 'node_modules/\n');
  });

  test('TEST-3948 a missing list prints the named skip line with the full path and writes nothing', async () => {
    const { seedRuntimeGitignore } = await modP();
    const root = fx({ '.gitignore': 'x\n' });
    const missing = path.join(fx({}), 'system', 'RUNTIME_IGNORE.list');
    assert.equal(seedRuntimeGitignore(path.join(root, '.gitignore'), missing, SEED_MARKER, false, '.gitignore'), `skipped runtime-sidecar gitignore seed: ${missing} missing`);
    assert.equal(text(root), 'x\n');
    const lines = await run(root, { runtimeList: missing });
    assert.equal(lines[lines.length - 1], `skipped runtime-sidecar gitignore seed: ${missing} missing`);
  });

  test('TEST-3948 list lines keep a carriage return, blank and comment lines are skipped', async () => {
    const list = path.join(fx({ 'list.txt': 'a\r\n\n# note\nb\nc' }), 'list.txt');
    const root = fx({ '.gitignore': `${CACHE.join('\n')}\n` });
    const { seedRuntimeGitignore } = await modP();
    const note = seedRuntimeGitignore(path.join(root, '.gitignore'), list, SEED_MARKER, false, '.gitignore');
    assert.equal(note, '.gitignore add 3 AAI runtime sidecar pattern(s)');
    assert.ok(text(root).endsWith(`\n\n${SEED_MARKER}\na\r\nb\nc\n`));
    assert.equal(seedRuntimeGitignore(path.join(root, '.gitignore'), list, SEED_MARKER, false, '.gitignore'), '.gitignore add 1 AAI runtime sidecar pattern(s)', 'the CR line never matches its stripped copy');
  });

  test('TEST-3948 a tree copy without lib/gitignore-block.sh still seeds the 30 patterns (DR-4)', () => {
    const base = scratch('dr4-');
    const tree = path.join(base, 'tree');
    materializeBootstrapReference(ROOT, tree);
    const lib = path.join(tree, '.aai', 'scripts', 'lib', 'gitignore-block.sh');
    assert.ok(lib.startsWith(base) && existsSync(lib));
    unlinkSync(lib);
    const root = fx(K01_PLAN_FILES);
    const r = spawnSync(process.execPath, [path.join(tree, '.aai', 'scripts', 'aai-bootstrap.mjs'), root], { encoding: 'utf8', cwd: root, env: { ...process.env, PWD: root } });
    assert.equal(r.status, 0, r.stderr);
    const got = readFileSync(path.join(root, '.gitignore'), 'utf8').split('\n');
    for (const p of runtimePatterns()) assert.ok(got.includes(p), p);
    assert.ok(r.stdout.includes(`- .gitignore add ${runtimePatterns().length} AAI runtime sidecar pattern(s)`));
    assert.ok(!r.stdout.includes('skipped runtime-sidecar'));
  });
});

// --- the differential corpus -------------------------------------------------------------------

const waitNextSecond = () => {
  const ms = 1000 - (Date.now() % 1000) + 30;
  spawnSync(process.execPath, ['-e', `setTimeout(() => {}, ${ms})`]);
};

// The stubs a corpus run puts first on PATH: each appends its argv to the log and exits 0.
function makeStubs(base) {
  const bin = path.join(base, 'stub-bin');
  const log = path.join(base, 'stub.log');
  mkdirSync(bin);
  writeFileSync(log, '');
  for (const name of [FORBIDDEN[0], 'gh', 'az']) {
    const f = path.join(bin, name);
    writeFileSync(f, `#!/bin/sh\necho "${name} $*" >> "${log}"\nexit 0\n`);
    chmodSync(f, 0o755);
  }
  const gitconfig = path.join(base, 'gitconfig');
  writeFileSync(gitconfig, '');
  return { bin, log, gitconfig };
}

function layout(root, files) {
  mkdirSync(root, { recursive: true });
  for (const [rel, body] of Object.entries(files)) {
    const p = path.join(root, rel);
    if (rel.endsWith('/')) mkdirSync(p, { recursive: true });
    else {
      mkdirSync(path.dirname(p), { recursive: true });
      writeFileSync(p, body);
    }
  }
}

function gitInit(root) {
  for (const args of [['init', '-q'], ['config', 'user.email', 'fixture@example.invalid'], ['config', 'user.name', 'fixture'], ['config', 'commit.gpgsign', 'false']]) {
    const r = spawnSync('git', args, { cwd: root, encoding: 'utf8', env: { ...process.env, GIT_CONFIG_NOSYSTEM: '1' } });
    assert.equal(r.status, 0, `git ${args.join(' ')}: ${r.stderr}`);
  }
}

// maskSnapshot(snap, masked): the stamp lines are normalized by snapshotNormalized (N5); in masked mode this also cuts
// docs/ai/pr-config.yaml and the directories that only it created.
function maskSnapshot(snap, masked) {
  const out = new Map();
  for (const [p, e] of snap) {
    if (masked && p === 'docs/ai/pr-config.yaml') continue;
    out.set(p, e);
  }
  if (masked) {
    for (const dir of ['docs/ai', 'docs']) {
      if (out.get(dir)?.kind === 'dir' && ![...out.keys()].some((k) => k.startsWith(`${dir}/`))) out.delete(dir);
    }
  }
  return out;
}

const maskStdout = (text, masked) => (masked ? text.replace(/\nGit platform:\n[\s\S]*?\n\n(?=Generated\/updated files:)/, '\n') : text);

function runCorpus(cases, { masked }) {
  const base = scratch('corpus-');
  const tree = path.join(base, 'tree');
  materializeBootstrapReference(ROOT, tree);
  const { bin, log, gitconfig } = makeStubs(base);
  const env = {};
  for (const [k, v] of Object.entries(process.env)) if (!k.startsWith('AAI_')) env[k] = v;
  Object.assign(env, { PATH: `${bin}${path.delimiter}${process.env.PATH}`, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: gitconfig });
  let bareTree = '';
  const scriptsFor = (k) => {
    let t = tree;
    if (k.noMergeLib) {
      if (!bareTree) {
        bareTree = path.join(base, 'tree-nolib');
        materializeBootstrapReference(ROOT, bareTree);
        const lib = path.join(bareTree, '.aai', 'scripts', 'lib', 'merge-hooks-json.mjs');
        assert.ok(lib.startsWith(`${base}${path.sep}`) && existsSync(lib), 'the library removed from the copy is inside the own scratch root');
        unlinkSync(lib);
      }
      t = bareTree;
    }
    return { sh: ['bash', path.join(t, '.aai', 'scripts', 'aai-bootstrap.sh')], node: [process.execPath, path.join(t, '.aai', 'scripts', 'aai-bootstrap.mjs')] };
  };
  const problems = [];
  const stubBySide = {};
  const logLines = () => readFileSync(log, 'utf8').split('\n').filter(Boolean);
  for (const k of cases) {
    const caseDir = path.join(base, 'cases', k.id);
    const target = path.join(caseDir, k.name);
    const scripts = scriptsFor(k);
    const sides = {};
    for (const side of ['sh', 'node']) {
      layout(target, k.files);
      if (k.repo) gitInit(target);
      if (k.remote) {
        const r = spawnSync('git', ['remote', 'add', 'origin', k.remote], { cwd: target, encoding: 'utf8', env: { ...process.env, GIT_CONFIG_NOSYSTEM: '1' } });
        assert.equal(r.status, 0, r.stderr);
      }
      const [cmd, script] = scripts[side];
      const results = [];
      const logBefore = logLines().length;
      k.steps.forEach((step, i) => {
        if (i > 0) waitNextSecond();
        if (step.before) step.before(target);
        const argv = [script, ...(k.target ? [target] : []), ...step.args];
        const r = spawnSync(cmd, argv, { cwd: target, env: { ...env, PWD: target }, encoding: 'utf8', timeout: 60000 });
        results.push({ code: r.status, stdout: maskStdout(r.stdout, masked), stderr: r.stderr });
      });
      stubBySide[`${k.id}:${side}`] = logLines().slice(logBefore);
      sides[side] = { results, snap: maskSnapshot(snapshotNormalized(target), masked) };
      if (side === 'sh') renameSync(target, `${target}.ref-side`);
    }
    const two = [k.name, `${k.name}.ref-side`].sort();
    if (k.knownDivergence) {
      const [a, b] = [sides.sh.results[0], sides.node.results[0]];
      const want = k.knownDivergence;
      if (a.code !== want.sh.code || a.stdout !== want.sh.stdout || a.stderr !== want.sh.stderr) problems.push(`${k.id}: the reference no longer ends as recorded (exit ${a.code}, stdout ${JSON.stringify(a.stdout)})`);
      if (b.code !== want.node.code) problems.push(`${k.id}: the module ends with exit ${b.code}, recorded ${want.node.code}`);
      if (sides.sh.snap.has('.claude')) problems.push(`${k.id}: the reference wrote output after all`);
      assert.deepEqual(readdirSync(caseDir).sort(), two);
      continue;
    }
    for (let i = 0; i < k.steps.length; i += 1) {
      const a = sides.sh.results[i];
      const b = sides.node.results[i];
      if (a.code !== b.code) problems.push(`${k.id} step ${i + 1}: exit ${a.code} (sh) vs ${b.code} (node)`);
      if (a.stdout !== b.stdout) problems.push(`${k.id} step ${i + 1}: stdout differs\n--- sh\n${a.stdout}\n--- node\n${b.stdout}`);
      if (a.stderr !== b.stderr) problems.push(`${k.id} step ${i + 1}: stderr differs\n--- sh\n${a.stderr}\n--- node\n${b.stderr}`);
    }
    for (const d of compareSnapshots(sides.sh.snap, sides.node.snap, 'sh:node')) problems.push(`${k.id}: tree ${d.kind} at ${d.path}: ${d.detail}`);
    if (stubBySide[`${k.id}:sh`].join('\n') !== stubBySide[`${k.id}:node`].join('\n')) problems.push(`${k.id}: the stub calls differ (sh ${JSON.stringify(stubBySide[`${k.id}:sh`])} vs node ${JSON.stringify(stubBySide[`${k.id}:node`])})`);
    assert.deepEqual(readdirSync(caseDir).sort(), two, `${k.id}: the case directory holds only its two sides`);
  }
  const parts = ['cases', 'gitconfig', 'stub-bin', 'stub.log', 'tree', OWN_MARKER_FILE, ...(bareTree ? ['tree-nolib'] : [])];
  assert.deepEqual(readdirSync(base).sort(), parts.sort(), 'the scratch root holds only its own parts');
  return { problems, stub: logLines(), stubBySide };
}

const CORPUS_SKIP = process.platform === 'win32' ? 'the corpus needs bash and runs on POSIX hosts' : false;

describe('TEST-3949 masked corpus', { skip: CORPUS_SKIP }, () => {
  test('TEST-3949 K01 to K27 and K38 agree in exit, stdout, stderr and tree, and no stub logs a container call', () => {
    const { problems, stub } = runCorpus(K_CASES_AB, { masked: true });
    assert.deepEqual(problems, []);
    assert.deepEqual(stub.filter((l) => l.startsWith(`${FORBIDDEN[0]} `) || l === FORBIDDEN[0]), []);
    assert.deepEqual(K_CASES_AB.map((k) => k.id).filter((id) => !/^K(0[1-9]|1\d|19b|2[0-7]|38)$/.test(id)), [], 'the masked set holds only K01 to K27 and K38');
  });
});

// --- slice c: hooks overlay, platform record, the full corpus --------------------------------------

const TPL_REL = HOOKS_TEMPLATE_REL;
const EM = '—';
const PLATFORM_OK = 'RECORDED platform=none (new file)\nAUTH none skipped\n';
const realSpawn = (script, args, cwd) => spawnSync(process.execPath, [script, ...args], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
// A spawn that runs the merge library for real and answers the platform record with a fixed result.
const spawnWith = (platform, calls = []) => (script, args, cwd) => {
  calls.push({ script: path.basename(script), args, cwd });
  return path.basename(script) === 'platform.mjs' ? platform : realSpawn(script, args, cwd);
};
const platformOk = { status: 0, stdout: PLATFORM_OK, stderr: '' };
const hooksIo = (root, extra = {}) => {
  const c = cap();
  return { c, io: { ...c.io, env: { PWD: root }, cwd: root, now: () => new Date('2026-01-02T03:04:05Z'), spawn: spawnWith(platformOk), ...extra } };
};
const tplText = readFileSync(path.join(ROOT, TPL_REL), 'utf8');
const hooksRoot = (files = {}) => fx({ [TPL_REL]: tplText, ...K01_PLAN_FILES, ...files });
const SETTINGS = '.claude/settings.json';

describe('TEST-3950 hooks overlay', () => {
  test('TEST-3950 a run without the flag creates no settings.json and prints no overlay line', async () => {
    const { run } = await modP();
    const root = hooksRoot();
    const { c, io } = hooksIo(root);
    assert.equal(run([], io), 0);
    assert.ok(!existsSync(path.join(root, SETTINGS)));
    assert.ok(!c.out.includes('hooks overlay'));
  });

  test('TEST-3950 a missing template warns, continues and exits 0', async () => {
    const { run } = await modP();
    const root = fx(K01_PLAN_FILES);
    const { c, io } = hooksIo(root);
    assert.equal(run(['--with-claude-hooks'], io), 0);
    assert.ok(c.out.startsWith(`WARN: Claude hooks template not found (${TPL_REL}) ${EM} skipping hooks install. Vendor it via .aai/scripts/aai-sync.sh, then rerun with --with-claude-hooks.\n\nAAI bootstrap summary\n`));
    assert.equal(c.err, '');
    assert.ok(!existsSync(path.join(root, SETTINGS)));
  });

  test('TEST-3950 dry-run lists the merge and writes no settings.json', async () => {
    const { run } = await modP();
    const root = hooksRoot();
    const { c, io } = hooksIo(root);
    assert.equal(run(['--dry-run', '--with-claude-hooks'], io), 0);
    assert.ok(c.out.includes(`- [dry-run] ${SETTINGS} (merge AAI hooks overlay from ${TPL_REL})\n`));
    assert.ok(!existsSync(path.join(root, SETTINGS)));
    assert.ok(!c.out.includes('  hooks overlay: '));
  });

  test('TEST-3950 the overlay is merged, then reported unchanged on a re-run, keeping foreign keys', async () => {
    const { run } = await modP();
    const root = hooksRoot({ [SETTINGS]: JSON.stringify({ permissions: { allow: ['Bash(ls:*)'] }, hooks: { SessionStart: [{ hooks: [{ type: 'command', command: 'echo foreign-start' }] }] } }) });
    const first = hooksIo(root);
    assert.equal(run(['--with-claude-hooks'], first.io), 0);
    assert.match(first.c.out, /^  hooks overlay: /m);
    assert.ok(first.c.out.includes(`- ${SETTINGS} (AAI hooks overlay merged)\n`));
    const merged = JSON.parse(readFileSync(path.join(root, SETTINGS), 'utf8'));
    assert.deepEqual(merged.permissions, { allow: ['Bash(ls:*)'] });
    assert.ok(JSON.stringify(merged.hooks.SessionStart).includes('echo foreign-start'), 'the foreign hook stays');
    assert.ok(Object.keys(merged.hooks).length >= 1);
    const bytes = readFileSync(path.join(root, SETTINGS), 'utf8');
    const second = hooksIo(root);
    assert.equal(run(['--with-claude-hooks'], second.io), 0);
    assert.ok(second.c.out.includes('0 hook(s) added, 0 updated'));
    assert.ok(second.c.out.includes('\nUnchanged files:\n') && second.c.out.includes(`- ${SETTINGS} (AAI hooks overlay already present)\n`));
    assert.equal(readFileSync(path.join(root, SETTINGS), 'utf8'), bytes);
  });

  test('TEST-3950 invalid JSON and a non-object hooks key are refused with the file untouched and exit 3', async () => {
    const { run } = await modP();
    for (const body of ['NOT JSON {', '{"hooks": []}']) {
      const root = hooksRoot({ [SETTINGS]: body });
      const { c, io } = hooksIo(root);
      assert.equal(run(['--with-claude-hooks'], io), 3, body);
      assert.equal(readFileSync(path.join(root, SETTINGS), 'utf8'), body, 'the file is byte-identical');
      const lines = c.err.split('\n');
      assert.ok(lines[0].startsWith(`ERROR: hooks overlay merge refused ${EM} `), lines[0]);
      assert.equal(lines[lines.length - 2], `ERROR: ${SETTINGS} left untouched. Merge the "hooks" key from ${TPL_REL} manually.`);
      assert.ok(c.out.startsWith('\nAAI bootstrap summary\n'), 'the summary is printed before the exit');
      assert.ok(!c.out.includes('hooks overlay:'));
    }
  });

  test('TEST-3950 a merge library missing next to the module ends with exit 3 after the summary', () => {
    const base = scratch('nolib-');
    const tree = path.join(base, 'tree');
    materializeBootstrapReference(ROOT, tree);
    const lib = path.join(tree, '.aai', 'scripts', 'lib', 'merge-hooks-json.mjs');
    assert.ok(lib.startsWith(`${base}${path.sep}`) && existsSync(lib));
    unlinkSync(lib);
    const root = hooksRoot();
    const r = spawnSync(process.execPath, [path.join(tree, '.aai', 'scripts', 'aai-bootstrap.mjs'), root, '--with-claude-hooks'], { encoding: 'utf8', cwd: root, env: { ...process.env, PWD: root } });
    assert.equal(r.status, 3, r.stderr);
    assert.equal(r.stderr, `ERROR: hooks merge library not found (${lib}) ${EM} the hooks overlay was NOT installed. Re-sync (.aai/scripts/aai-sync.sh) to vendor it, then rerun with --with-claude-hooks.\n`);
    assert.ok(r.stdout.startsWith('\nAAI bootstrap summary\n'));
    assert.ok(!existsSync(path.join(root, SETTINGS)));
    // the template check comes first: without a template the run only warns
    const bare = fx(K01_PLAN_FILES);
    const w = spawnSync(process.execPath, [path.join(tree, '.aai', 'scripts', 'aai-bootstrap.mjs'), bare, '--with-claude-hooks'], { encoding: 'utf8', cwd: bare, env: { ...process.env, PWD: bare } });
    assert.equal(w.status, 0, w.stderr);
    assert.ok(w.stdout.startsWith('WARN: Claude hooks template not found'));
  });

  test('TEST-3950 the child runs in the root with the relative template and destination', async () => {
    const { run } = await modP();
    const root = hooksRoot();
    const calls = [];
    const { io } = hooksIo(root, { spawn: spawnWith(platformOk, calls) });
    assert.equal(run(['--with-claude-hooks'], io), 0);
    const merge = calls.find((x) => x.script === 'merge-hooks-json.mjs');
    assert.deepEqual(merge.args, [TPL_REL, SETTINGS]);
    assert.equal(merge.cwd, root);
  });
});

// --- TEST-3951 ---------------------------------------------------------------------------------

describe('TEST-3951 platform record', () => {
  const record = async (result, { dryRun = false } = {}) => {
    const { recordGitPlatform } = await modP();
    const calls = [];
    const root = fx({});
    const text = recordGitPlatform(root, { dryRun, spawn: (script, args, cwd) => { calls.push({ script: path.basename(script), args, cwd }); return result; } });
    return { text, calls, root };
  };

  test('TEST-3951 exit 0 and exit 6 relay the child text as is', async () => {
    const ok = await record({ status: 0, stdout: 'RECORDED platform=azure\nAUTH azure ok\n', stderr: '' });
    assert.equal(ok.text, 'RECORDED platform=azure\nAUTH azure ok');
    const mismatch = await record({ status: 6, stdout: 'MISMATCH recorded=azure origin=github\n', stderr: 'note\n' });
    assert.equal(mismatch.text, 'MISMATCH recorded=azure origin=github\nnote');
  });

  test('TEST-3951 any other exit relays platform record failed with the exit and the text', async () => {
    for (const code of [1, 4, 2, 3]) {
      const r = await record({ status: code, stdout: '', stderr: 'boom\n\n' });
      assert.equal(r.text, `platform record failed (exit ${code}): boom`);
    }
    assert.equal((await record({ status: null, stdout: '', stderr: 'killed\n' })).text, 'platform record failed (exit 1): killed');
  });

  test('TEST-3951 the dry-run flag reaches the argument list and the child runs in the root', async () => {
    const real = await record(platformOk);
    assert.deepEqual(real.calls, [{ script: 'platform.mjs', args: ['record', '--repo-root', real.root], cwd: real.root }]);
    const dry = await record(platformOk, { dryRun: true });
    assert.deepEqual(dry.calls[0].args, ['record', '--repo-root', dry.root, '--dry-run']);
  });

  test('TEST-3951 the run prints the relayed text and keeps its own exit code', async () => {
    const { run } = await modP();
    for (const [result, want] of [[{ status: 6, stdout: 'MISMATCH x\n', stderr: '' }, 'MISMATCH x'], [{ status: 4, stdout: '', stderr: 'bad\n' }, 'platform record failed (exit 4): bad']]) {
      const root = fx(K01_PLAN_FILES);
      const { c, io } = hooksIo(root, { spawn: spawnWith(result) });
      assert.equal(run([], io), 0);
      assert.ok(c.out.includes(`\nGit platform:\n${want}\n\nGenerated/updated files:\n`), c.out);
    }
    // a refused hooks overlay still ends 3 whatever the platform record says
    const root = hooksRoot({ [SETTINGS]: 'NOT JSON {' });
    const { io } = hooksIo(root, { spawn: spawnWith({ status: 6, stdout: 'MISMATCH x\n', stderr: '' }) });
    assert.equal(run(['--with-claude-hooks'], io), 3);
  });
});

// --- TEST-3952 ---------------------------------------------------------------------------------

describe('TEST-3952 full corpus', { skip: CORPUS_SKIP }, () => {
  test('TEST-3952 K01 to K38 agree in exit, stdout, stderr and tree, with platform stub lines only for K35 to K37', () => {
    const ids = K_CASES.map((k) => k.id);
    for (let n = 1; n <= 38; n += 1) assert.ok(ids.includes(`K${String(n).padStart(2, '0')}`), `K${n} is in the corpus`);
    const { problems, stub, stubBySide } = runCorpus(K_CASES, { masked: false });
    assert.deepEqual(problems, []);
    assert.deepEqual(stub.filter((l) => l.startsWith(`${FORBIDDEN[0]} `) || l === FORBIDDEN[0]), []);
    const platformCases = new Set(['K35', 'K36', 'K37']);
    for (const [key, lines] of Object.entries(stubBySide)) {
      if (!platformCases.has(key.split(':')[0])) assert.deepEqual(lines, [], `${key} must not start gh or az`);
    }
    assert.ok(K_CASES_C.length === 10);
  });
});

// --- TEST-3956 ---------------------------------------------------------------------------------

const BS_STAMPED = ['.claude/skills/AAI_DYNAMIC_SKILLS.md', '.codex/skills.local/README.md', '.gemini/skills.local/README.md'];

describe('TEST-3956 parity harness bootstrap pieces', () => {
  const snapOf = (files) => {
    const d = scratch('n5-');
    for (const [k, v] of Object.entries(files)) {
      mkdirSync(path.dirname(path.join(d, k)), { recursive: true });
      writeFileSync(path.join(d, k), v);
    }
    return PARITY.snapshotNormalized(d);
  };
  const text = (snap, p) => snap.get(p).data.toString('utf8');

  test('TEST-3956 N5 is in NORMALIZATIONS with its reason', () => {
    const n5 = PARITY.NORMALIZATIONS.find((n) => n.id === 'N5');
    assert.ok(n5, 'N5 exists');
    assert.equal(n5.reason, 'wall clock: the bootstrap run timestamp NOW_UTC');
    assert.deepEqual(PARITY.NORMALIZATIONS.map((n) => n.id), ['N1', 'N2', 'N3', 'N4', 'N5', 'E1', 'E2']);
  });

  test('TEST-3956 N5 rewrites the second-precision stamp line of exactly the three paths', () => {
    const stamp = '2026-11-10T18:54:19Z';
    const s = snapOf({
      [BS_STAMPED[0]]: `# AAI Dynamic Skills\n\n- Generated at (UTC): ${stamp}\n- Target root: /x\n`,
      [BS_STAMPED[1]]: `# AAI Dynamic Skills (Codex)\n\nGenerated at (UTC): ${stamp}\n\nmore\n`,
      [BS_STAMPED[2]]: `Generated at (UTC): ${stamp}\r\n`,
      'docs/other.md': `- Generated at (UTC): ${stamp}\n`,
    });
    assert.equal(text(s, BS_STAMPED[0]), '# AAI Dynamic Skills\n\n- Generated at (UTC): <stamp>\n- Target root: /x\n');
    assert.equal(text(s, BS_STAMPED[1]), '# AAI Dynamic Skills (Codex)\n\nGenerated at (UTC): <stamp>\n\nmore\n');
    assert.equal(text(s, BS_STAMPED[2]), 'Generated at (UTC): <stamp>\r\n');
    assert.equal(text(s, 'docs/other.md'), `- Generated at (UTC): ${stamp}\n`, 'a path outside the list is unchanged');
    // fraction digits and another line are not second precision: unchanged
    const f = snapOf({ [BS_STAMPED[0]]: '- Generated at (UTC): 2026-11-10T18:54:19.123Z\n- Other (UTC): 2026-11-10T18:54:19Z\n' });
    assert.equal(text(f, BS_STAMPED[0]), '- Generated at (UTC): 2026-11-10T18:54:19.123Z\n- Other (UTC): 2026-11-10T18:54:19Z\n');
  });

  test('TEST-3956 the DR-9 allowlist row parses with the documented fields', () => {
    const rows = PARITY.parseAllowlist(readFileSync(PARITY.DEFAULT_ALLOWLIST, 'utf8'), { twins: ['sh', 'ps1', 'node'] });
    const row = rows.find((r) => r.id === 'win-bootstrap-target-root');
    assert.ok(row, 'the row exists');
    assert.equal(row.pairs, 'sh:ps1,sh:node');
    assert.equal(row.scenario, 'BS-01,BS-03,BS-04,BS-06,BS-07,BS-08,BS-09');
    assert.equal(row.path, '.claude/skills/AAI_DYNAMIC_SKILLS.md');
    assert.equal(row.kind, 'lines');
    assert.equal(row.host, 'win32');
    assert.equal(row.tracker, 'accepted');
    assert.equal(row.match, '^- Target root: ');
    assert.equal(rows.filter((r) => /bootstrap/.test(r.id)).length, 1, 'exactly one new row');
  });

  test('TEST-3956 the bootstrap scenarios, tier sizes and setups follow the table', () => {
    assert.deepEqual(PARITY.listMatrix('smoke').filter((id) => id.startsWith('BS-')), ['BS-01', 'BS-02']);
    assert.deepEqual(PARITY.listMatrix('default').filter((id) => id.startsWith('BS-')), ['BS-01', 'BS-02', 'BS-03', 'BS-04', 'BS-05', 'BS-06']);
    assert.deepEqual(PARITY.listMatrix('full').filter((id) => id.startsWith('BS-')), ['BS-01', 'BS-02', 'BS-03', 'BS-04', 'BS-05', 'BS-06', 'BS-07', 'BS-08', 'BS-09']);
    assert.deepEqual([PARITY.listMatrix('smoke').length, PARITY.listMatrix('default').length, PARITY.listMatrix('full').length], [9, 21, 29]);
    const by = Object.fromEntries(PARITY.SCENARIOS.filter((x) => x.id.startsWith('BS-')).map((x) => [x.id, x]));
    assert.equal(by['BS-01'].target, 'target with space');
    assert.equal(by['BS-03'].steps.length, 2);
    assert.deepEqual(by['BS-04'].steps[0].flags, ['force']);
    assert.deepEqual(by['BS-05'].steps[0].flags, ['dry-run']);
    assert.deepEqual(by['BS-06'].steps[0].flags, ['with-claude-hooks']);
    assert.equal(by['BS-02'].steps[0].expect, 'nonzero');
    assert.equal(by['BS-07'].steps[0].expect, 'nonzero');
    assert.deepEqual(by['BS-01'].probes, ['.claude/skills/AAI_DYNAMIC_SKILLS.md', '.claude/skills/aai-test-e2e/SKILL.md', 'docs/ai/pr-config.yaml']);
    assert.ok(PARITY.SCENARIOS.filter((x) => x.op === 'bootstrap').every((x) => x.id.startsWith('BS-')));
  });

  test('TEST-3956 the twin registry holds the node twin restricted to bootstrap and the argv lines follow D-PARITY', () => {
    assert.deepEqual(Object.keys(PARITY.TWINS), ['sh', 'ps1', 'node']);
    assert.deepEqual(PARITY.TWINS.node.ops, ['bootstrap']);
    assert.equal(PARITY.TWINS.sh.ops, undefined);
    const ctx = { src: '/s', target: '/t', bash: 'bash', ps: 'pwsh', bsref: '/r' };
    const step = { op: 'bootstrap', profile: null, flags: ['force', 'dry-run', 'with-claude-hooks'] };
    const flags = ['--force', '--dry-run', '--with-claude-hooks'];
    const sh = PARITY.TWINS.sh.argv(step, ctx);
    assert.deepEqual([sh.file, ...sh.args], ['bash', '/r/.aai/scripts/aai-bootstrap.sh', '/t', ...flags]);
    assert.equal(sh.cwd, '/t');
    const ps = PARITY.TWINS.ps1.argv(step, ctx);
    assert.equal(ps.file, 'pwsh');
    assert.deepEqual(ps.args.slice(ps.args.indexOf('-File')), ['-File', '/r/.aai/scripts/aai-bootstrap.ps1', '/t', ...flags]);
    const nd = PARITY.TWINS.node.argv(step, ctx);
    assert.equal(nd.file, process.execPath);
    assert.deepEqual(nd.args, [path.join('/r', '.aai', 'scripts', 'aai-bootstrap.mjs'), '/t', ...flags]);
    assert.equal(nd.cwd, '/t');
    // a module twin without ops still runs everywhere: its argv is used as given
    assert.equal(PARITY.TWINS.sh.ops, undefined);
  });

  test('TEST-3956 the runner gives a twin with ops only the scenarios of its operation', () => {
    assert.equal(typeof PARITY.twinsFor, 'function');
    const all = [PARITY.TWINS.sh, PARITY.TWINS.ps1, PARITY.TWINS.node];
    const sync = PARITY.SCENARIOS.find((x) => x.id === 'SY-01');
    const bs = PARITY.SCENARIOS.find((x) => x.id === 'BS-01');
    assert.deepEqual(PARITY.twinsFor(all, sync).map((t) => t.name), ['sh', 'ps1']);
    assert.deepEqual(PARITY.twinsFor(all, bs).map((t) => t.name), ['sh', 'ps1', 'node']);
    const plain = { name: 'plain', argv: () => ({}) };
    assert.deepEqual(PARITY.twinsFor([plain, PARITY.TWINS.node], sync).map((t) => t.name), ['plain']);
  });
});
