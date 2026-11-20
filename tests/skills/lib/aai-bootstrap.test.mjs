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
