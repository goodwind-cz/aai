// migrate-state-to-local.test.mjs - node:test cases for .aai/scripts/migrate-state-to-local.mjs
// (docs/specs/SPEC-DRAFT-spec-retire-legacy-migrations.md, TEST-3380 to TEST-3384).
// Pure functions plus the module CLI against real git in mkdtemp fixtures. Nothing here
// touches the repository checkout: every fixture is a fresh temp directory.
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
// The module may not exist yet (RED on the baseline): every case must fail on its own assertion.
const M = await import('../../../.aai/scripts/migrate-state-to-local.mjs').catch(() => ({}));

const HERE = path.dirname(fileURLToPath(import.meta.url));
// AAI_MIG_MODULE points the CLI cases at a scratch copy (RED proof by revert); unset, the repository module runs.
const MODULE = process.env.AAI_MIG_MODULE || path.resolve(HERE, '../../../.aai/scripts/migrate-state-to-local.mjs');
const CRLF = '\r\n';
const HEADER = '# AAI per-dev runtime state (RFC-0001: never committed)';
const PATTERNS = [
  'docs/ai/STATE.yaml', 'docs/ai/LOOP_TICKS.jsonl', 'docs/ai/tdd/**', 'docs/ai/validation/**',
  '!docs/ai/tdd/', '!docs/ai/tdd/.gitkeep', 'docs/ai/loop/', 'docs/ai/locks/',
  'docs/ai/hitl-channel.json', 'docs/ai/briefs/**', 'docs/ai/reports/**', 'docs/ai/friction/**',
  'docs/ai/archive/**', 'docs/ai/.session-context.md', 'docs/ai/.pre-compact-state-backup.yaml',
  'docs/INDEX.audit.md',
];
const TMP = [];
after(() => { for (const d of TMP) fs.rmSync(d, { recursive: true, force: true }); });

const git = (cwd, ...args) => {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`git ${args.join(' ')} failed: ${r.stderr}`);
  return r.stdout;
};
const scratch = (label) => {
  const d = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), `aai-mig-${label}-`)));
  TMP.push(d);
  return d;
};
const put = (root, rel, text = 'x\n') => {
  fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
  fs.writeFileSync(path.join(root, rel), text);
};
// legacy fixture: clean, committed, one-line CRLF .gitignore, tracked runtime state.
function legacy(label, extra = []) {
  const d = scratch(label);
  git(d, 'init', '-q');
  git(d, 'config', 'user.email', 'fixture@example.invalid');
  git(d, 'config', 'user.name', 'fixture');
  git(d, 'config', 'commit.gpgsign', 'false');
  put(d, '.gitignore', `node_modules${CRLF}`);
  for (const f of ['docs/ai/STATE.yaml', 'docs/ai/LOOP_TICKS.jsonl', 'docs/ai/tdd/.gitkeep',
    'docs/ai/tdd/x/red.log', 'docs/ai/loop/a.txt', ...extra]) put(d, f);
  git(d, 'add', '-A');
  git(d, 'commit', '-q', '-m', 'legacy');
  return d;
}
const cli = (args, opts = {}) => spawnSync(process.execPath, [MODULE, ...args], { encoding: 'utf8', cwd: opts.cwd, env: opts.env || process.env });
const listing = (root) => {
  const out = [];
  const walk = (d) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
      if (e.name === '.git') continue;
      const p = path.join(d, e.name);
      if (e.isDirectory()) walk(p); else out.push(path.relative(root, p) + ':' + fs.readFileSync(p).toString('hex'));
    }
  };
  walk(root);
  return out;
};

// ---------------------------------------------------------------- TEST-3380
test('TEST-3380 IGNORE_PATTERNS is exactly the 16 D1 entries in order', () => {
  assert.deepEqual(M.IGNORE_PATTERNS, PATTERNS);
});

test('TEST-3380 parseArgs maps the D1 arguments', () => {
  assert.equal(M.parseArgs(['--dry-run']).dryRun, true);
  assert.equal(M.parseArgs([]).dryRun, false);
  assert.equal(M.parseArgs(['-h']).help, true);
  assert.equal(M.parseArgs(['--help']).help, true);
  assert.equal(M.parseArgs(['/t/x', '--dry-run']).target, '/t/x');
  const second = M.parseArgs(['/a', '/b']);
  assert.equal(second.code, 2);
  assert.equal(second.error, 'ERROR: unexpected argument: /b');
  const bogus = M.parseArgs(['--bogus']);
  assert.equal(bogus.code, 2);
  assert.equal(bogus.error, 'ERROR: unknown option: --bogus');
});

test('TEST-3380 missingPatterns matches whole lines and tolerates CRLF', () => {
  const text = `docs/ai/STATE.yaml${CRLF}other${CRLF}`;
  const missing = M.missingPatterns(text, PATTERNS);
  assert.equal(missing.includes('docs/ai/STATE.yaml'), false);
  assert.equal(missing.length, 15);
  assert.deepEqual(M.missingPatterns('xdocs/ai/STATE.yaml\n', ['docs/ai/STATE.yaml']), ['docs/ai/STATE.yaml']);
  assert.deepEqual(M.missingPatterns('', ['a', 'b']), ['a', 'b']);
  assert.deepEqual(M.missingPatterns('a\nb\n', ['a', 'b']), []);
});

test('TEST-3380 gitignoreAppend returns the exact block per end-of-line shape', () => {
  const p = ['a', 'b'];
  assert.equal(M.gitignoreAppend('', p), `\n${HEADER}\na\nb\n`);
  assert.equal(M.gitignoreAppend('x\n', p), `\n${HEADER}\na\nb\n`);
  assert.equal(M.gitignoreAppend(`x${CRLF}`, p), `${CRLF}${HEADER}${CRLF}a${CRLF}b${CRLF}`);
  assert.equal(M.gitignoreAppend('x', p), `\n\n${HEADER}\na\nb\n`);
  assert.equal(M.gitignoreAppend(`x${CRLF}y`, p), `${CRLF}${CRLF}${HEADER}${CRLF}a${CRLF}b${CRLF}`);
});

// ---------------------------------------------------------------- TEST-3381
test('TEST-3381 a clean legacy fixture is migrated and a second run is a no-op', () => {
  const d = legacy('effects');
  const r = cli([d]);
  assert.equal(r.status, 0, r.stderr);
  const tracked = git(d, 'ls-files').split('\n').filter(Boolean).sort();
  assert.deepEqual(tracked, ['.gitignore', 'docs/ai/tdd/.gitkeep']);
  for (const f of ['docs/ai/STATE.yaml', 'docs/ai/LOOP_TICKS.jsonl', 'docs/ai/tdd/x/red.log', 'docs/ai/loop/a.txt']) {
    assert.equal(fs.existsSync(path.join(d, f)), true, f);
  }
  const want = `node_modules${CRLF}${CRLF}${HEADER}${CRLF}${PATTERNS.map((p) => p + CRLF).join('')}`;
  assert.equal(fs.readFileSync(path.join(d, '.gitignore'), 'utf8'), want);
  assert.equal(fs.statSync(path.join(d, 'docs/ai/EVENTS.jsonl')).size, 0);
  for (const line of ['AAI per-dev runtime state migration (RFC-0001)', `Target: ${d}`, '  Files untracked:        4',
    '  .gitignore entries added: 16', '  EVENTS.jsonl created:   1', 'Next steps (run manually):',
    `  git -C "${d}" add .gitignore docs/ai/EVENTS.jsonl`,
    `  git -C "${d}" commit -m "Migrate AAI STATE to per-dev local runtime (RFC-0001)"`,
    'After commit, other developers will see STATE.yaml and LOOP_TICKS.jsonl',
    'vanish from the tree on next pull. Their local copies remain on disk.',
    'UNTRACK docs/ai/STATE.yaml (file remains on disk)',
    'UNTRACK docs/ai/tdd/x/red.log (runtime evidence; file remains on disk)']) {
    assert.ok(r.stdout.split('\n').includes(line), `missing line: ${line}`);
  }
  assert.equal(r.stdout.includes('Nothing to do'), false);
  git(d, 'add', '.gitignore', 'docs/ai/EVENTS.jsonl');
  git(d, 'commit', '-q', '-m', 'migrate');
  assert.equal(git(d, 'status', '--porcelain'), '');
  const before = listing(d);
  const again = cli([d]);
  assert.equal(again.status, 0, again.stderr);
  const lines = again.stdout.split('\n');
  assert.ok(lines.includes('Nothing to do - already migrated.'));
  assert.ok(lines.includes('  Files untracked:        0'));
  assert.ok(lines.includes('  .gitignore entries added: 0'));
  assert.ok(lines.includes('  EVENTS.jsonl created:   0'));
  assert.equal(git(d, 'status', '--porcelain'), '');
  assert.deepEqual(listing(d), before);
});

test('TEST-3381 an LF .gitignore without a final newline and no .gitignore at all', () => {
  const d = legacy('lf');
  fs.writeFileSync(path.join(d, '.gitignore'), 'node_modules');
  git(d, 'commit', '-q', '-am', 'no final newline');
  assert.equal(cli([d]).status, 0);
  assert.equal(fs.readFileSync(path.join(d, '.gitignore'), 'utf8'),
    `node_modules\n\n${HEADER}\n${PATTERNS.map((p) => p + '\n').join('')}`);
  const e = legacy('nogi');
  git(e, 'rm', '-q', '-f', '.gitignore');
  git(e, 'commit', '-q', '-m', 'drop gitignore');
  assert.equal(cli([e]).status, 0);
  assert.equal(fs.readFileSync(path.join(e, '.gitignore'), 'utf8'), `\n${HEADER}\n${PATTERNS.map((p) => p + '\n').join('')}`);
});

test('TEST-3381 an existing EVENTS.jsonl and present patterns are kept', () => {
  const d = legacy('present', ['docs/ai/EVENTS.jsonl']);
  fs.writeFileSync(path.join(d, '.gitignore'), `docs/ai/STATE.yaml${CRLF}`);
  git(d, 'commit', '-q', '-am', 'one pattern present');
  const r = cli([d]);
  assert.equal(r.status, 0, r.stderr);
  const lines = r.stdout.split('\n');
  assert.ok(lines.includes('SKIP    .gitignore already contains docs/ai/STATE.yaml'));
  assert.ok(lines.includes('SKIP    docs/ai/EVENTS.jsonl already exists'));
  assert.ok(lines.includes('  .gitignore entries added: 15'));
  assert.ok(lines.includes('  EVENTS.jsonl created:   0'));
  assert.equal(fs.readFileSync(path.join(d, 'docs/ai/EVENTS.jsonl'), 'utf8'), 'x\n');
});

// ---------------------------------------------------------------- TEST-3382
test('TEST-3382 argument and target refusals carry their exit codes', () => {
  const d = legacy('refuse');
  let r = cli(['--bogus']);
  assert.equal(r.status, 2);
  assert.equal(r.stderr.trim(), 'ERROR: unknown option: --bogus');
  r = cli([d, '/second']);
  assert.equal(r.status, 2);
  assert.equal(r.stderr.trim(), 'ERROR: unexpected argument: /second');
  const gone = path.join(d, 'no-such-dir');
  r = cli([gone]);
  assert.equal(r.status, 1);
  assert.equal(r.stderr.trim(), `ERROR: target directory not found: ${gone}`);
  assert.equal(r.stdout, '');
});

test('TEST-3382 a repo without docs/ai and a docs/ai folder outside git are refused', () => {
  const a = scratch('nodocs');
  git(a, 'init', '-q');
  let r = cli([a]);
  assert.equal(r.status, 1);
  assert.equal(r.stderr.trim(), `ERROR: ${path.join(a, 'docs/ai')} not found. Is this an AAI project?`);
  const b = scratch('nogit');
  put(b, 'docs/ai/STATE.yaml');
  r = cli([b], { env: { ...process.env, GIT_CEILING_DIRECTORIES: path.dirname(b) } });
  assert.equal(r.status, 1);
  assert.equal(r.stderr.trim(), `ERROR: ${b} is not inside a git repository.`);
});

test('TEST-3382 a PATH without git, a dirty tree and help', () => {
  const d = legacy('dirty');
  const empty = scratch('emptybin');
  let r = cli([d], { env: { ...process.env, PATH: empty } });
  assert.equal(r.status, 1);
  assert.equal(r.stderr.trim(), 'ERROR: git not found in PATH.');
  put(d, 'extra.txt');
  r = cli([d]);
  assert.equal(r.status, 1);
  assert.equal(r.stderr, 'ERROR: working tree has uncommitted changes.\n       Commit or stash them first, then re-run this script.\n');
  assert.equal(r.stdout, '');
  for (const flag of ['--help', '-h']) {
    r = cli([flag]);
    assert.equal(r.status, 0);
    assert.ok(r.stdout.includes('Usage: node .aai/scripts/migrate-state-to-local.mjs [path-to-target-project] [--dry-run]'));
  }
});

test('TEST-3382 a dry run prints the dry-run lines and changes nothing', () => {
  const d = legacy('dry');
  const index = git(d, 'ls-files', '-s');
  const gi = fs.readFileSync(path.join(d, '.gitignore'));
  const before = listing(d);
  const r = cli([d, '--dry-run']);
  assert.equal(r.status, 0, r.stderr);
  const lines = r.stdout.split('\n');
  assert.ok(lines.includes('Mode:   dry-run (no changes will be written)'));
  assert.ok(lines.includes('UNTRACK docs/ai/STATE.yaml (file remains on disk)'));
  assert.ok(lines.includes('  [dry-run] git rm --cached docs/ai/STATE.yaml'));
  assert.ok(lines.includes('  [dry-run] git rm --cached docs/ai/tdd/x/red.log'));
  assert.ok(lines.includes('Dry-run only. Re-run without the dry-run flag to apply.'));
  assert.ok(lines.includes('  Files untracked:        4'));
  assert.equal(r.stdout.includes('Next steps'), false);
  assert.equal(git(d, 'ls-files', '-s'), index);
  assert.ok(fs.readFileSync(path.join(d, '.gitignore')).equals(gi));
  assert.equal(fs.existsSync(path.join(d, 'docs/ai/EVENTS.jsonl')), false);
  assert.deepEqual(listing(d), before);
});

// ---------------------------------------------------------------- TEST-3383
test('TEST-3383 hostile tracked names are untracked literally and run no command', () => {
  const d = scratch('hostile');
  git(d, 'init', '-q');
  git(d, 'config', 'user.email', 'fixture@example.invalid');
  git(d, 'config', 'user.name', 'fixture');
  git(d, 'config', 'commit.gpgsign', 'false');
  const names = ['docs/ai/tdd/x/$(touch PWNED).log', 'docs/ai/tdd/x/say "hi".log', 'docs/ai/tdd/x/back`tick`.log',
    'docs/ai/tdd/x/caf\u00e9.log', 'docs/ai/tdd/*'];
  for (const f of ['docs/ai/STATE.yaml', 'docs/ai/tdd/.gitkeep', ...names]) put(d, f);
  git(d, 'add', '-A');
  git(d, 'commit', '-q', '-m', 'hostile');
  const r = cli([d], { cwd: d });
  assert.equal(r.status, 0, r.stderr);
  const tracked = git(d, '-c', 'core.quotepath=off', 'ls-files').split('\n').filter(Boolean);
  assert.deepEqual(tracked.filter((f) => f !== '.gitignore'), ['docs/ai/tdd/.gitkeep']);
  for (const f of names) assert.equal(fs.existsSync(path.join(d, f)), true, f);
  const found = [];
  const walk = (x) => { for (const e of fs.readdirSync(x, { withFileTypes: true })) { if (e.name === '.git') continue; if (e.name === 'PWNED') found.push(e.name); if (e.isDirectory()) walk(path.join(x, e.name)); } };
  walk(d);
  assert.deepEqual(found, []);
  assert.ok(r.stdout.split('\n').includes(`  Files untracked:        ${names.length + 1}`), r.stdout);
});

// ---------------------------------------------------------------- TEST-3384
test('TEST-3384 a failing git rm stops before any other write', () => {
  const d = legacy('rmfail');
  const index = git(d, 'ls-files', '-s');
  const gi = fs.readFileSync(path.join(d, '.gitignore'));
  fs.writeFileSync(path.join(d, '.git', 'index.lock'), '');
  const r = cli([d]);
  assert.equal(r.status, 1);
  assert.ok(r.stderr.startsWith('ERROR: git rm --cached failed (exit '), r.stderr);
  assert.ok(fs.readFileSync(path.join(d, '.gitignore')).equals(gi));
  assert.equal(fs.existsSync(path.join(d, 'docs/ai/EVENTS.jsonl')), false);
  fs.rmSync(path.join(d, '.git', 'index.lock'));
  assert.equal(git(d, 'ls-files', '-s'), index);
});
