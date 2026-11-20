// aai-bootstrap.test.mjs - node:test cases of the bootstrap-on-node ride
// (docs/specs/SPEC-DRAFT-bootstrap-on-node.md). Every case name starts with its TEST id; the suite
// tests/skills/test-aai-bootstrap-node.sh selects them with --test-name-pattern.
//
// Scratch safety (D-SAFETY): directories are created and removed only through bootstrap-reference.mjs
// (own prefix, marker, re-verified before removal); no case starts a container tool or kills by pattern.

import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import {
  existsSync, mkdirSync, readdirSync, readFileSync, statSync, symlinkSync, writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, describe, test } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

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
  path.join(HERE, 'aai-bootstrap.test.mjs'),
  path.join(HERE, 'bootstrap-reference.mjs'),
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
const FORBIDDEN = ['dock' + 'er', 'pk' + 'ill', 'kill' + 'all'];

// forbiddenCalls(source): lines that call a forbidden tool: the word first on a statement, or the
// first string argument of a process-starting call.
export function forbiddenCalls(source) {
  const words = FORBIDDEN.join('|');
  const start = new RegExp(`(^|[;&|(\`]|\\$\\(|\\bexec\\s|\\bsudo\\s)\\s*(${words})(\\s|$)`);
  const spawned = new RegExp(`\\b(spawn|spawnSync|exec|execSync|execFile|execFileSync)\\(\\s*['"\`](${words})\\b`);
  return source.split('\n').map((line, i) => ({ line, n: i + 1 }))
    .filter(({ line }) => !/^\s*(#|\/\/)/.test(line) && (start.test(line) || spawned.test(line)))
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
