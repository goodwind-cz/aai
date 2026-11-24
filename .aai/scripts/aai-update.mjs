#!/usr/bin/env node
// aai-update.mjs - the AAI layer updater as one Node module behind thin launchers
// (docs/specs/SPEC-0307-spec-update-on-node.md; RFC-0017 phase 5).
//
// Usage: node .aai/scripts/aai-update.mjs [--repo <slug|url|path>] [--ref <ref>] [--dry-run] [--keep-temp] [--force] [-h]
//
// The module holds the update policy: arguments, the base directory, the canonical-repo guard,
// source resolution, the temp lifecycle, the sync step, the evidence report and the exit code.
// Importing it has no side effect; the main guard runs it only as the entry point. It never reads
// standard input, and all of its output goes through descriptors 1 and 2 so that its lines and the
// lines of the children it starts appear in program order.

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolveFromBase } from './lib/resolve-base.mjs';

const DEFAULT_REPO = 'goodwind-cz/aai';
const DEFAULT_REF = 'main';
const EXIT_USAGE = 1;
const EXIT_REFUSED = 2;
const EXIT_FETCH = 3;
const EXIT_MALFORMED = 4;
const TMP_PREFIX = 'aai-src.';
const SRC_SUBDIR = 'src';
const RUNNER_ENV = 'AAI_UPDATE_SYNC_RUNNER';
const SLUG_CASE_FLAGS = 'i';
const PIN_KEYWORDS = ['source', 'version', 'commit', 'canonical', 'ref'];
const ANON_CLONE = ['-c', 'credential.helper=', '-c', 'http.https://github.com/.extraheader='];
const HELPER_REL = '.aai/scripts/update-doctor-report.mjs';
// The status read is not capped at spawnSync's default 1 MiB, which would read a large tree as no changes.
const STATUS_MAX_BUFFER = 1024 * 1024 * 1024;
const runChild = (file, args, opts) => spawnSync(file, args, opts);
const writeFd = (fd) => (s) => { fs.writeSync(fd, s); };

// The help text (DR-1): the bash reference's comment block, then the PowerShell usage line and the
// Node requirement line.
const HELP_LINES = [
  'AAI layer updater \u2014 one deterministic command for /aai-update.',
  '',
  'Materializes the canonical AAI repo\'s `main`, runs aai-sync into THIS project,',
  'and prints concise post-sync evidence. Replaces the old 7-step agent-narrated',
  'procedure: the agent now runs this once and relays the final report.',
  '',
  'Usage (run from the TARGET project root):',
  '  ./.aai/scripts/aai-update.sh                       # sync from goodwind-cz/aai@main',
  '  ./.aai/scripts/aai-update.sh --dry-run             # print the plan, change nothing',
  '  ./.aai/scripts/aai-update.sh --repo OWNER/NAME     # alternate upstream slug',
  '  ./.aai/scripts/aai-update.sh --repo ../aai         # alternate upstream: local checkout',
  '  ./.aai/scripts/aai-update.sh --repo git@github.com:OWNER/NAME.git',
  '  ./.aai/scripts/aai-update.sh --ref some-branch     # non-default ref',
  '  ./.aai/scripts/aai-update.sh --keep-temp           # keep the temp clone for inspection',
  '  ./.aai/scripts/aai-update.sh --force               # allow running inside the canonical repo',
  '  powershell -NoProfile -File .aai/scripts/aai-update.ps1 [-Repo X] [-Ref Y] [-DryRun] [-KeepTemp] [-Force]   # the long flags work too',
  'Requires Node.js 22 or later; both launchers run .aai/scripts/aai-update.mjs.',
];
export const HELP_TEXT = `${HELP_LINES.join('\n')}\n`;

// The flags that take a value and the switches, by their exact long spelling and by their PowerShell
// name (matched case-insensitively, no abbreviation).
const VALUE_FLAGS = { '--repo': 'repo', '--ref': 'ref', '-repo': 'repo', '-ref': 'ref' };
const SWITCH_FLAGS = { '--dry-run': 'dryRun', '--keep-temp': 'keepTemp', '--force': 'force', '-dryrun': 'dryRun', '-keeptemp': 'keepTemp', '-force': 'force' };

// The boolean words a switch accepts after it or after a colon (the PowerShell spellings included).
const BOOL_WORDS = new Map([['true', true], ['false', false], ['$true', true], ['$false', false]]);

// flagKey(arg): the lookup key of a flag word: a long flag exactly, a single-dash name lower-cased.
const flagKey = (arg) => (arg.startsWith('--') ? arg : arg.toLowerCase());

// isOption(word): a word this parser recognizes as a flag (help, a switch or a value flag, the equals form
// included); after a value flag it is a missing value, never the value (--repo --dry-run must not drop the dry-run).
const isOption = (word) => {
  const k = flagKey(word.startsWith('--') && word.indexOf('=') > 0 ? word.slice(0, word.indexOf('=')) : word);
  return word === '-h' || word === '--help' || Object.prototype.hasOwnProperty.call(SWITCH_FLAGS, k) || Object.prototype.hasOwnProperty.call(VALUE_FLAGS, k);
};

// parseArgs(argv): arguments left to right, a later occurrence of a setting wins. outcome is 'run',
// 'help' (-h or --help seen), 'unknown' (arg names the first unrecognized argument) or 'value' (arg
// names the value flag, as given, that came without a value). Parsing stops at the first terminal.
export function parseArgs(argv) {
  const out = { repo: DEFAULT_REPO, ref: DEFAULT_REF, dryRun: false, keepTemp: false, force: false, outcome: 'run', arg: '' };
  const has = (table, key) => Object.prototype.hasOwnProperty.call(table, key);
  for (let i = 0; i < argv.length; i += 1) {
    let arg = argv[i];
    if (arg === '-h' || arg === '--help') {
      out.outcome = 'help';
      return out;
    }
    // The PowerShell colon form, -Flag:value in one token; Windows PowerShell 5.1 under -File may hand it over as
    // -Flag: then the value, which is joined here (the grammar of aai-release.mjs).
    const colon = arg.match(/^-[A-Za-z][A-Za-z0-9-]*:/);
    let colonValue;
    if (colon) {
      colonValue = arg.slice(colon[0].length);
      arg = arg.slice(0, colon[0].length - 1);
      if (colonValue === '' && i + 1 < argv.length && !isOption(argv[i + 1])) colonValue = argv[(i += 1)];
    }
    const eq = arg.startsWith('--') ? arg.indexOf('=') : -1;
    const key = flagKey(eq > 0 ? arg.slice(0, eq) : arg);
    if (has(SWITCH_FLAGS, key) && eq < 0) {
      let word = colonValue;
      if (word === undefined && BOOL_WORDS.has(String(argv[i + 1]).toLowerCase())) word = argv[(i += 1)];
      const value = word === undefined ? true : BOOL_WORDS.get(word.toLowerCase());
      if (value === undefined) {
        out.outcome = 'unknown';
        out.arg = argv[i];
        return out;
      }
      out[SWITCH_FLAGS[key]] = value;
    } else if (has(VALUE_FLAGS, key)) {
      const inline = colonValue !== undefined || eq > 0;
      const value = colonValue !== undefined ? colonValue : eq > 0 ? arg.slice(eq + 1) : argv[i + 1];
      if (value === undefined || value === '' || (!inline && isOption(value))) {
        out.outcome = 'value';
        out.arg = eq > 0 ? arg.slice(0, eq) : arg;
        return out;
      }
      out[VALUE_FLAGS[key]] = value;
      if (!inline) i += 1;
    } else {
      out.outcome = 'unknown';
      out.arg = argv[i];
      return out;
    }
  }
  return out;
}

const statOrNull = (p) => {
  try {
    return fs.statSync(p);
  } catch {
    return null;
  }
};

// resolveBase(rel, env, cwd): the shared base resolution of lib/resolve-base.mjs (D-BASE): PWD when it names the
// working directory, else the working directory; a relative path resolves lexically against it.
export const resolveBase = (rel = '', env = process.env, cwd = process.cwd()) => resolveFromBase(rel, env, cwd);

// normSlug(s): "owner/repo" lower-cased from a slug, an https or ssh URL (a trailing .git and everything up to
// the LAST github.com: or github.com/ dropped, both case per SLUG_CASE_FLAGS); empty for anything else.
export function normSlug(s) {
  if (!s) return '';
  const v = String(s)
    .replace(new RegExp('\\.git$', SLUG_CASE_FLAGS), '')
    .replace(new RegExp('^[\\s\\S]*github\\.com[:/]', SLUG_CASE_FLAGS), '');
  return /^[^/]+\/[^/]+$/.test(v) ? v.toLowerCase() : '';
}

const REFUSAL_LINES = (origin) => [
  `REFUSED: this project (${origin}) looks like the canonical AAI repo.`,
  '  /aai-update syncs AAI INTO a target project; update the canonical repo with normal git.',
  '  Pass --force (or -Force) to override.',
];

// canonicalGuard({ repo, target, force, spawn, env }): { refused, origin, lines }. The target's origin is read
// with git (stdout only, any failure reads as empty); the guard refuses unless force when the repo value and the
// origin name the same owner and repository. No git is started when the repo value names no slug or force is on.
export function canonicalGuard({ repo, target, force = false, spawn: child = runChild, env = process.env }) {
  const want = normSlug(repo);
  if (want === '' || force) return { refused: false, origin: '', lines: [] };
  let origin = '';
  try {
    const r = child('git', ['-C', target, 'config', '--get', 'remote.origin.url'], { stdio: ['ignore', 'pipe', 'ignore'], encoding: 'utf8', env });
    if (r && !r.error && r.status === 0 && typeof r.stdout === 'string') origin = r.stdout.replace(/\n+$/, '');
  } catch {
    origin = '';
  }
  if (normSlug(origin) !== want) return { refused: false, origin, lines: [] };
  return { refused: true, origin, lines: REFUSAL_LINES(origin) };
}

// cloneUrl(repo): the value as given when it holds :// or an @ followed later by a colon, else the https form.
export function cloneUrl(repo) {
  return repo.includes('://') || /@[\s\S]*:/.test(repo) ? repo : `https://github.com/${repo}.git`;
}

const isDir = (p) => {
  const st = statOrNull(p);
  return st !== null && st.isDirectory();
};

const NO_STDIO = ['ignore', 'ignore', 'ignore'];

// started(r): whether a child result means the program ran (a result with an error never started it).
const started = (r) => !(r && r.error);
// A child killed by a signal is a failed attempt, exactly as in both twins (a local-checkout git command is best
// effort and ignored, a clone attempt moves on to the next one). The chain stops only when the updater itself was
// signalled: the bash reference stops only when the shell itself receives the signal (a terminal Ctrl-C reaches the
// whole process group), a signal that only the child got does not stop it. spawnSync blocks the event loop, so the
// module's own handler is dispatched only when the loop turns; after each child the code yields once (signalled)
// and then reads state.signal; the run exits with it (130 or 143) through its existing path.
// resolveSource({ repo, ref, dryRun }, io, state): { src, desc } or { fail: { code, line } } (async). A local checkout gets
// the three best-effort git commands in a real run; anything else is cloned into <temp>/src in three attempts
// (gh, git, anonymous git), the temp directory being recorded in state before the first attempt so that the
// caller's cleanup owns it on every path. A dry-run starts nothing and creates nothing.
export async function resolveSource(args, io, state) {
  const { repo, ref, dryRun } = args;
  const child = io.spawn ?? runChild;
  const env = io.env ?? process.env;
  const local = resolveBase(repo, env, io.cwd ?? process.cwd());
  if (isDir(local)) {
    if (!dryRun) {
      for (const sub of [['fetch', '--depth', '1', 'origin', ref], ['checkout', ref], ['pull', '--ff-only', 'origin', ref]]) {
        try {
          child('git', ['-C', local, ...sub], { stdio: NO_STDIO, env });
        } catch {
          // best effort: a source without git or without a remote is still synced
        }
        if (await signalled(state)) return { fail: { code: state.signal, line: '' } };
      }
    }
    return { src: local, desc: `local checkout ${local}` };
  }
  const url = cloneUrl(repo);
  const desc = `${url}@${ref}`;
  if (dryRun) return { src: '', desc };
  state.created = createOwnTemp(io.tmpdir ?? os.tmpdir(), io.err);
  state.tmp = state.created.path;
  const srcDir = path.join(state.tmp, SRC_SUBDIR);
  const wipe = () => fs.rmSync(srcDir, { recursive: true, force: true });
  const attempts = [
    ['gh', ['repo', 'clone', repo, srcDir, '--', '--branch', ref, '--depth', '1'], env],
    ['git', ['clone', '--branch', ref, '--depth', '1', url, srcDir], env],
    ['git', [...ANON_CLONE, 'clone', '--branch', ref, '--depth', '1', url, srcDir], { ...env, GIT_TERMINAL_PROMPT: '0' }],
  ];
  const ran = [];
  for (const [file, argv, childEnv] of attempts) {
    wipe();
    const r = child(file, argv, { stdio: NO_STDIO, env: childEnv });
    if (await signalled(state)) return { fail: { code: state.signal, line: '' } };
    ran.push(started(r));
    if (r && !r.error && r.status === 0) return { src: srcDir, desc };
  }
  const line = !ran[1] && !ran[2]
    ? `ERROR: could not fetch ${repo}@${ref}: git was not found on PATH.`
    : `ERROR: could not fetch ${repo}@${ref} (auth or network?). Treat as an access issue, not a missing repo.`;
  return { fail: { code: EXIT_FETCH, line } };
}

// pathBase(p): the last segment of a path written with either separator.
const pathBase = (p) => p.slice(Math.max(p.lastIndexOf('/'), p.lastIndexOf('\\')) + 1);
const isAbs = (p) => path.posix.isAbsolute(p) || path.win32.isAbsolute(p);

// resolveRunner(env, platform): which sync twin of the source runs, as { kind, exe } or { error } (D-RUNNER). The
// value bash, or an absolute path to bash, selects the bash twin; an absolute path to pwsh or powershell selects the
// PowerShell twin; unset or empty takes bash on POSIX and powershell.exe on win32.
export function resolveRunner(env = process.env, platform = process.platform) {
  const value = env[RUNNER_ENV];
  if (value === undefined || value === '') return platform === 'win32' ? { kind: 'powershell', exe: 'powershell.exe' } : { kind: 'bash', exe: 'bash' };
  if (value === 'bash') return { kind: 'bash', exe: 'bash' };
  if (isAbs(value)) {
    const base = pathBase(value).toLowerCase();
    if (base === 'bash' || base === 'bash.exe') return { kind: 'bash', exe: value };
    if (['pwsh', 'pwsh.exe', 'powershell', 'powershell.exe'].includes(base)) return { kind: 'powershell', exe: value };
  }
  return { error: `aai-update: ${RUNNER_ENV} must be bash or a path to bash, pwsh or powershell, got '${value}'` };
}

// syncCommand(runner, src, target, platform): { file, args, path } of the sync child; path is the sync file the
// command runs. The bash twin gets forward slashes on win32 (Git Bash reads C:/...).
export function syncCommand(runner, src, target, platform = process.platform) {
  if (runner.kind === 'bash') {
    const fwd = (p) => (platform === 'win32' ? p.replace(/\\/g, '/') : p);
    const file = `${fwd(src)}/.aai/scripts/aai-sync.sh`;
    return { file: runner.exe, args: [file, fwd(target)], path: file };
  }
  const file = `${src}/.aai/scripts/aai-sync.ps1`;
  const policy = platform === 'win32' ? ['-ExecutionPolicy', 'Bypass'] : [];
  return { file: runner.exe, args: ['-NoProfile', '-NonInteractive', ...policy, '-File', file, '-TargetRoot', target], path: file };
}

// renderDryRun({ target, desc, runner }): the dry-run block, nothing else.
export function renderDryRun({ target, desc, runner }) {
  const would = runner.kind === 'bash'
    ? `<source>/.aai/scripts/aai-sync.sh "${target}"`
    : `<source>/.aai/scripts/aai-sync.ps1 -TargetRoot "${target}"`;
  return [
    '## aai-update (dry-run) \u2014 no files changed',
    `- Target:   ${target}`,
    `- Upstream: ${desc}`,
    `- Would run: ${would}`,
    '- Then check: git status --short, .aai/system/AAI_PIN.md, docs/ai/reports/sync-conflicts-*.md',
    '- Next: /aai-doctor (and /aai-bootstrap if skills changed)',
    '',
  ].join('\n');
}

// renderSyncHeader(desc, target): the line printed before the sync's own output.
export function renderSyncHeader(desc, target) {
  return `## aai-update \u2014 syncing ${desc} into ${target}\n`;
}

// changedFiles(target, spawn, env): the lines of `git status --short` (empty lines dropped, no CR stripping); any
// failure reads as none.
export function changedFiles(target, child = runChild, env = process.env) {
  try {
    const r = child('git', ['-C', target, 'status', '--short'], { stdio: ['ignore', 'pipe', 'ignore'], encoding: 'utf8', maxBuffer: STATUS_MAX_BUFFER, env });
    if (!r || r.error || r.status !== 0 || typeof r.stdout !== 'string') return [];
    return r.stdout.split('\n').filter((l) => l !== '');
  } catch {
    return [];
  }
}

const isFile = (p) => {
  const st = statOrNull(p);
  return st !== null && st.isFile();
};

// pinLines(target): the AAI_PIN lines that name a PIN_KEYWORDS word (case-insensitive) without a leading byte order
// mark or trailing CR; null when the pin is not a regular file.
export function pinLines(target) {
  const file = path.join(target, '.aai', 'system', 'AAI_PIN.md');
  if (!isFile(file)) return null;
  const words = new RegExp(PIN_KEYWORDS.join('|'), 'i');
  return fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '').split('\n').map((l) => l.replace(/\r$/, '')).filter((l) => words.test(l));
}

// latestConflict(target): the target-relative forward-slash path of the newest sync-conflicts report (mtime in
// nanoseconds, a tie to the smallest name), or an empty string.
export function latestConflict(target) {
  const dir = path.join(target, 'docs', 'ai', 'reports');
  let names = [];
  try {
    names = fs.readdirSync(dir).filter((n) => /^sync-conflicts-.*\.md$/.test(n)).sort();
  } catch {
    return '';
  }
  let best = '';
  let bestNs = -1n;
  for (const name of names) {
    let st = null;
    try {
      st = fs.statSync(path.join(dir, name), { bigint: true });
    } catch {
      st = null;
    }
    if (st && st.isFile() && st.mtimeNs > bestNs) {
      best = name;
      bestNs = st.mtimeNs;
    }
  }
  return best === '' ? '' : `docs/ai/reports/${best}`;
}

// renderEvidence({ changed, pin, conflict }): the post-sync evidence block (starts with an empty line).
export function renderEvidence({ changed, pin, conflict }) {
  const lines = ['', '## Post-sync evidence'];
  if (changed.length > 0) lines.push(`- Changed files (${changed.length}):`, ...changed.map((l) => `  ${l}`));
  else lines.push('- Changed files: none (already up to date)');
  if (pin !== null) lines.push('- AAI_PIN:', ...pin.map((l) => `  ${l}`));
  if (conflict !== '') lines.push(`- \u26a0 Conflict advisory: ${conflict} \u2014 review before committing.`);
  return `${lines.join('\n')}\n`;
}

// withoutRunner(env): the caller's environment minus the runner hint, the one the sync and the helper get.
const withoutRunner = (env) => {
  const copy = { ...env };
  delete copy[RUNNER_ENV];
  return copy;
};

// doctorReport(target, { out, spawn, env }): the doctor field report postamble. It prints its header, then runs the
// target's helper on this Node, or prints a named SKIP line; it never throws and has no result.
export function doctorReport(target, { out, spawn: child = runChild, env = process.env }) {
  out('\n## Doctor field report\n');
  let crashed = false;
  try {
    const helper = path.join(target, HELPER_REL);
    if (!isFile(helper)) {
      out('DOCTOR-REPORT SKIP helper missing - update unaffected\n');
      return;
    }
    const r = child(process.execPath, [helper, '--root', target], { cwd: target, stdio: 'inherit', env: withoutRunner(env) });
    crashed = !r || Boolean(r.error) || r.status !== 0;
  } catch {
    crashed = true;
  }
  if (crashed) out('DOCTOR-REPORT SKIP helper crashed - update unaffected\n');
}

// renderNext(anyChanged): the closing block; the bootstrap clause only when files changed.
export function renderNext(anyChanged) {
  return [
    '',
    '## Next',
    '- Review the diff (git diff), then commit manually (this tool never auto-commits).',
    `- Recommended: /aai-doctor${anyChanged ? ' ; /aai-bootstrap if skills/indexes changed' : ''}`,
    '',
  ].join('\n');
}

// createOwnTemp(tmpdir, err): a fresh aai-src.XXXXXX directory under tmpdir. The record it returns (the path, the
// realpath of the parent and the stderr sink the kept line goes to) is what removeOwnTemp checks against.
export function createOwnTemp(tmpdir, err = writeFd(2)) {
  const dir = fs.mkdtempSync(path.join(tmpdir, TMP_PREFIX));
  return { path: dir, parentReal: fs.realpathSync(tmpdir), err };
}

// removeOwnTemp(dir, created): removes dir recursively only when it is the recorded path, carries the prefix, is a
// real directory (not a link) and its parent still resolves to the recorded parent; each check is made right
// before the removal. Otherwise nothing is removed and one kept line goes to stderr; it never throws.
export function removeOwnTemp(dir, created) {
  const say = (created && created.err) || writeFd(2);
  const keep = (reason) => { try { say(`aai-update: kept ${dir}: ${reason}\n`); } catch { /* nothing left to report to */ } };
  try {
    if (typeof dir !== 'string' || dir === '' || !path.isAbsolute(dir)) return keep('not an absolute path');
    if (!created || dir !== created.path) return keep('not the directory this run created');
    if (!path.basename(dir).startsWith(TMP_PREFIX)) return keep('name lacks the temp prefix');
    const st = fs.lstatSync(dir);
    if (st.isSymbolicLink() || !st.isDirectory()) return keep('not a real directory');
    if (fs.realpathSync(path.dirname(dir)) !== created.parentReal) return keep('its parent is not the one it was created in');
    fs.rmSync(dir, { recursive: true, force: true });
    return undefined;
  } catch (e) {
    return keep(e.message);
  }
}

// run(argv, io): returns the exit code. io holds out, err (string sinks), env, cwd, spawn, tmpdir and
// platform; each defaults to the real thing.
export async function run(argv, io = {}) {
  const out = io.out ?? writeFd(1);
  const err = io.err ?? writeFd(2);
  const env = io.env ?? process.env;
  const cwd = io.cwd ?? process.cwd();
  const args = parseArgs(argv);
  if (args.outcome === 'help') {
    out(HELP_TEXT);
    return 0;
  }
  if (args.outcome === 'unknown') {
    err(`Unknown argument: ${args.arg}\n`);
    out(HELP_TEXT);
    return EXIT_USAGE;
  }
  if (args.outcome === 'value') {
    err(`aai-update: ${args.arg} needs a value\n`);
    return EXIT_USAGE;
  }
  const platform = io.platform ?? process.platform;
  const runner = resolveRunner(env, platform);
  if (runner.error) {
    err(`${runner.error}\n`);
    return EXIT_USAGE;
  }
  const child = io.spawn ?? runChild;
  const state = { keepTemp: args.keepTemp, tmp: '', created: null, signal: 0 };
  const unwatch = io.spawn === undefined ? watchSignals(state) : () => {};
  try {
    const target = resolveBase('', env, cwd);
    const guard = canonicalGuard({ repo: args.repo, target, force: args.force, spawn: child, env });
    if (guard.refused) {
      for (const line of guard.lines) err(`${line}\n`);
      return EXIT_REFUSED;
    }
    if (await signalled(state)) return state.signal;
    const source = await resolveSource(args, { spawn: child, env, cwd, tmpdir: io.tmpdir, err }, state);
    if (await signalled(state)) return state.signal;
    if (source.fail) {
      err(`${source.fail.line}\n`);
      return source.fail.code;
    }
    if (args.dryRun) {
      out(renderDryRun({ target, desc: source.desc, runner }));
      return 0;
    }
    return await syncStep(source, target, { child, env, err, out, runner, platform, state });
  } catch (e) {
    err(`aai-update: internal error: ${e.message}\n`);
    return EXIT_USAGE;
  } finally {
    unwatch();
    if (!state.keepTemp && state.tmp) removeOwnTemp(state.tmp, state.created);
  }
}

// syncStep: the real run after the source is resolved: the sync file of the chosen runner must exist (exit 4), the
// header, the sync child with inherited stdio (a nonzero exit or a signal ends the run before any post-sync output),
// then the evidence, the doctor report and the next steps.
async function syncStep(source, target, { child, env, err, out, runner, platform, state }) {
  const cmd = syncCommand(runner, source.src, target, platform);
  if (!isFile(cmd.path)) {
    err(`ERROR: sync script missing in source: ${cmd.path}\n`);
    return EXIT_MALFORMED;
  }
  out(renderSyncHeader(source.desc, target));
  const r = child(cmd.file, cmd.args, { cwd: target, stdio: 'inherit', env: withoutRunner(env) });
  if (r.error) throw r.error;
  if (await signalled(state)) return state.signal;
  if (r.status === null) return 128 + (os.constants.signals[r.signal] ?? 1);
  if (r.status !== 0) return r.status;
  const changed = changedFiles(target, child, env);
  if (await signalled(state)) return state.signal;
  out(renderEvidence({ changed, pin: pinLines(target), conflict: latestConflict(target) }));
  doctorReport(target, { out, spawn: child, env });
  if (await signalled(state)) return state.signal;
  out(renderNext(changed.length > 0));
  return 0;
}

// signalled(state): spawnSync blocks the event loop, so a SIGINT or SIGTERM that arrives during a child is only
// dispatched once the loop turns; one setImmediate after each blocking stage lets the handler record it, and the
// run then stops with 128+signal through its finally (which removes the run's own temp directory).
async function signalled(state) {
  await new Promise((resolve) => setImmediate(resolve));
  return state.signal !== 0;
}

// watchSignals(state): a real run keeps SIGINT and SIGTERM from ending the process in the middle of a blocking
// child; the handler removes the run's own temp directory, records 130 or 143, and the run stops at its next stage boundary (see signalled).
// It returns the function that removes the two listeners again; run calls it in its finally, so after a run default signal behaviour is back.
function watchSignals(state) {
  const handlers = [['SIGINT', 130], ['SIGTERM', 143]].map(([name, code]) => [name, () => {
    if (state.tmp && !state.keepTemp) removeOwnTemp(state.tmp, state.created);
    state.tmp = '';
    state.signal = code;
  }]);
  for (const [name, handler] of handlers) process.on(name, handler);
  return () => { for (const [name, handler] of handlers) process.removeListener(name, handler); };
}

export async function main(argv = process.argv.slice(2)) {
  process.exitCode = await run(argv);
}

// The main guard resolves both sides through realpath (a symlinked checkout still runs main), falling back to a plain resolve.
const realOrResolve = (p) => {
  try {
    return fs.realpathSync(p);
  } catch {
    return path.resolve(p);
  }
};

if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) main();
