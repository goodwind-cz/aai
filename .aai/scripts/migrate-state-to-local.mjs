// migrate-state-to-local.mjs - migrate AAI per-dev runtime state to local-only (RFC-0001).
// Untracks docs/ai/STATE.yaml, docs/ai/LOOP_TICKS.jsonl and the runtime evidence under
// docs/ai/tdd and docs/ai/loop, adds the runtime ignore block to .gitignore and creates an
// empty docs/ai/EVENTS.jsonl. Idempotent. Never commits; it prints the next commands.
// Node stdlib only, no side effects on import. Launchers: migrate-state-to-local.sh/.ps1.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const UNTRACK_FILES = ['docs/ai/STATE.yaml', 'docs/ai/LOOP_TICKS.jsonl'];
const EVIDENCE_DIRS = ['docs/ai/tdd', 'docs/ai/loop'];
const EVENTS_FILE = 'docs/ai/EVENTS.jsonl';
const HEADER = '# AAI per-dev runtime state (RFC-0001: never committed)';
const DIRTY_LINE = 'ERROR: working tree has uncommitted changes.';
const CRLF = String.fromCharCode(13, 10);
const GIT_ENV = { ...process.env, GIT_LITERAL_PATHSPECS: '1' };
const RM_ARGS = ['update-index', '--force-remove', '-z', '--stdin'];
const USAGE = 'Usage: node .aai/scripts/migrate-state-to-local.mjs [path-to-target-project] [--dry-run]';

export const IGNORE_PATTERNS = [
  'docs/ai/STATE.yaml',
  'docs/ai/LOOP_TICKS.jsonl',
  'docs/ai/tdd/**',
  'docs/ai/validation/**',
  '!docs/ai/tdd/',
  '!docs/ai/tdd/.gitkeep',
  'docs/ai/loop/',
  'docs/ai/locks/',
  'docs/ai/hitl-channel.json',
  'docs/ai/briefs/**',
  'docs/ai/reports/**',
  'docs/ai/friction/**',
  'docs/ai/archive/**',
  'docs/ai/.session-context.md',
  'docs/ai/.pre-compact-state-backup.yaml',
  'docs/INDEX.audit.md',
];

// parseArgs(argv): { target, dryRun, help } or, for a bad argument, { error, code: 2 }.
export function parseArgs(argv) {
  const opts = { target: null, dryRun: false, help: false };
  for (const a of argv) {
    if (a === '--dry-run') opts.dryRun = true;
    else if (a === '-h' || a === '--help') opts.help = true;
    else if (a.startsWith('-')) return { error: `ERROR: unknown option: ${a}`, code: 2 };
    else if (opts.target === null) opts.target = a;
    else return { error: `ERROR: unexpected argument: ${a}`, code: 2 };
  }
  return opts;
}

// missingPatterns(text, patterns): the patterns that are not a whole line of text (CR tolerated).
export function missingPatterns(text, patterns) {
  const have = new Set(text.split('\n').map((l) => l.replace(/\r$/, '')));
  return patterns.filter((p) => !have.has(p));
}

// gitignoreAppend(text, patterns): the exact string to append to a .gitignore holding text.
export function gitignoreAppend(text, patterns) {
  const useCrlf = text.includes(CRLF);
  const eol = useCrlf ? CRLF : '\n';
  const lead = text !== '' && !text.endsWith('\n') ? eol : '';
  return lead + eol + [HEADER, ...patterns].map((l) => l + eol).join('');
}

// run(opts, deps): opts { target, dryRun }; deps { git(args, input), fs, out(line), err(line) }.
// Returns the exit code.
export function run(opts, deps) {
  const { git, out, err } = deps;
  const dfs = deps.fs;
  const rawTarget = opts.target;
  const target = path.resolve(rawTarget ?? process.cwd());
  const dry = Boolean(opts.dryRun);
  const isDir = (p) => { try { return dfs.statSync(p).isDirectory(); } catch { return false; } };
  if (!isDir(target)) { err(`ERROR: target directory not found: ${rawTarget}`); return 1; }
  if (!isDir(path.join(target, 'docs/ai'))) {
    err(`ERROR: ${path.join(target, 'docs/ai')} not found. Is this an AAI project?`);
    return 1;
  }
  const g = (args, input) => git(['-C', target, ...args], input);
  const failed = (r, what) => { if (r.status === 0) return false; err(`ERROR: git ${what} failed (exit ${r.status}): ${String(r.stderr).trim()}`); return true; };
  if (git(['--version']).status !== 0) { err('ERROR: git not found in PATH.'); return 1; }
  if (g(['rev-parse', '--git-dir']).status !== 0) {
    err(`ERROR: ${target} is not inside a git repository.`);
    return 1;
  }
  const st = g(['status', '--porcelain']); if (failed(st, 'status')) return 1;
  if (st.stdout.trim() !== '') {
    err(DIRTY_LINE);
    err('       Commit or stash them first, then re-run this script.');
    return 1;
  }
  out('AAI per-dev runtime state migration (RFC-0001)');
  out(`Target: ${target}`);
  if (dry) out('Mode:   dry-run (no changes will be written)');
  out('');

  const ls = g(['ls-files', '-z', '--', ...UNTRACK_FILES, ...EVIDENCE_DIRS]); if (failed(ls, 'ls-files')) return 1;
  const listed = ls.stdout.split('\0').filter(Boolean); const tracked = new Set(listed); const toRemove = [];
  const untrack = (f, why) => {
    toRemove.push(f);
    out(`UNTRACK ${f} (${why})`);
    if (dry) out(`  [dry-run] git rm --cached ${f}`);
  };
  for (const f of UNTRACK_FILES) {
    if (tracked.has(f)) untrack(f, 'file remains on disk');
    else out(`SKIP    ${f} (already untracked or absent)`);
  }
  for (const f of listed) {
    const inEvidence = EVIDENCE_DIRS.some((d) => f.startsWith(`${d}/`));
    if (inEvidence && !f.endsWith('/.gitkeep')) untrack(f, 'runtime evidence; file remains on disk');
  }
  if (!dry && toRemove.length > 0) {
    const ix = path.resolve(target, g(['rev-parse', '--git-path', 'index']).stdout.trim()); const saved = dfs.readFileSync(ix); const rm = g(RM_ARGS, toRemove.join('\0'));
    if (rm.status !== 0) {
      const first = String(rm.stderr || '').split('\n').find((l) => l.trim() !== '') || '';
      err(`ERROR: git rm --cached failed (exit ${rm.status}): ${first}`);
      return 1;
    }
    const left = g(['ls-files', '-z', '--', ...UNTRACK_FILES, ...EVIDENCE_DIRS]).stdout.split('\0').filter((f) => toRemove.includes(f));
    if (left.length > 0) { try { dfs.writeFileSync(ix, saved); err(`ERROR: git could not untrack ${left.length} path(s) it refuses to remove (for example a git~1 or non-UTF-8 name); the index is unchanged.`); } catch (e) { err(`ERROR: git could not untrack ${left.length} path(s) and could not restore the git index (${e.code || e.message}); run: git -C "${target}" reset`); } return 1; }
  }

  const giPath = path.join(target, '.gitignore');
  const text = dfs.existsSync(giPath) ? dfs.readFileSync(giPath, 'utf8') : '';
  const missing = missingPatterns(text, IGNORE_PATTERNS); let headerShown = false;
  for (const p of IGNORE_PATTERNS) {
    if (!missing.includes(p)) { out(`SKIP    .gitignore already contains ${p}`); continue; }
    if (!headerShown) { out(`GITIGNORE add header + entries to ${giPath}`); headerShown = true; }
    out(`GITIGNORE add: ${p}`);
  }
  if (!dry && missing.length > 0) dfs.appendFileSync(giPath, gitignoreAppend(text, missing));

  const eventsPath = path.join(target, EVENTS_FILE); const createEvents = !dfs.existsSync(eventsPath);
  if (createEvents) {
    out('CREATE  docs/ai/EVENTS.jsonl (empty, append-only audit log)');
    if (!dry) dfs.writeFileSync(eventsPath, '');
  } else {
    out('SKIP    docs/ai/EVENTS.jsonl already exists');
  }

  out('');
  out('Summary:');
  out(`  Files untracked:        ${toRemove.length}`);
  out(`  .gitignore entries added: ${missing.length}`);
  out(`  EVENTS.jsonl created:   ${createEvents ? 1 : 0}`);
  out('');
  if (dry) {
    out('Dry-run only. Re-run without the dry-run flag to apply.');
  } else if (toRemove.length > 0 || missing.length > 0 || createEvents) {
    out('Next steps (run manually):');
    out(`  git -C "${target}" add .gitignore docs/ai/EVENTS.jsonl`);
    out(`  git -C "${target}" commit -m "Migrate AAI STATE to per-dev local runtime (RFC-0001)"`);
    out('');
    out('After commit, other developers will see STATE.yaml and LOOP_TICKS.jsonl');
    out('vanish from the tree on next pull. Their local copies remain on disk.');
  } else {
    out('Nothing to do - already migrated.');
  }
  return 0;
}

const realGit = (args, input) => {
  const r = spawnSync('git', args, { encoding: 'utf8', env: GIT_ENV, input });
  return { status: r.error ? null : r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
};

export function main(argv = process.argv.slice(2)) {
  const opts = parseArgs(argv);
  if (opts.error) { process.stderr.write(`${opts.error}\n`); return opts.code; }
  if (opts.help) { process.stdout.write(`${USAGE}\n`); return 0; }
  return run(opts, {
    git: realGit,
    fs,
    out: (l) => process.stdout.write(`${l}\n`),
    err: (l) => process.stderr.write(`${l}\n`),
  });
}

const realOrResolve = (p) => { try { return fs.realpathSync(p); } catch { return path.resolve(p); } };
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) process.exitCode = main();
