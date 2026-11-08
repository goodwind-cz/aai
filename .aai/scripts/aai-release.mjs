#!/usr/bin/env node
// aai-release.mjs: the whole /aai-release command in one module (RFC-0017 phase 5). aai-release.sh and aai-release.ps1 are
// permanent thin launchers of it. It parses the flags, checks the repository and CHANGELOG.md, resolves the version, hands a
// remote --confirm to release-finish.mjs (run in process), prints the plan (release-cut.mjs plan) or runs the local cut (release-cut.mjs check
// and roll, a release branch in a temporary worktree). Node stdlib only; importing it has no side effect.
//
//   aai-release.mjs [--launcher sh|ps1] [--launcher-path P] [--version V] [--dry-run] [--confirm|--yes] [--no-remote] [-h|--help]
//
// Exit codes: 0 ok | 1 bad argument or version | 10 not a git repository | 11 no CHANGELOG.md | 14 release branch with unmerged
//   commits | 20 refused (a failing git step, an interruption keeps 130 or 143) | the exit codes of release-cut.mjs and
//   release-finish.mjs relayed (12 13 15 20 8). See .aai/SKILL_RELEASE.prompt.md.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { main as cutMain } from './release-cut.mjs';
import { resolvePlatform, createAdapter } from './lib/platform-adapter.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FINISH_SCRIPT = 'release-finish.mjs';
const REPORT_HEADER = '## aai-release — cut complete';
const EXIT = { USAGE: 1, NOT_REPO: 10, NO_CHANGELOG: 11, BRANCH: 14, REFUSED: 20 };
const SIGNALS = { SIGINT: 130, SIGTERM: 143 };

const FLAG_NAMES = {
  sh: { head: 'usage: aai-release.sh [--version <v>] [--dry-run] [--confirm] [--no-remote]', yes: '--yes', nr: '--no-remote' },
  ps1: { head: 'usage: aai-release.ps1 [-Version <v>] [-DryRun] [-Confirm] [-NoRemote]', yes: '-Yes', nr: '-NoRemote' },
};

export function usage(launcher) {
  const f = FLAG_NAMES[launcher] ?? FLAG_NAMES.sh;
  return [
    f.head,
    `  ${f.yes} is the same as the confirm flag (the cut)`,
    '  default version: CalVer vYYYY.MM.DD (UTC); AAI_RELEASE_DATE=YYYY-MM-DD pins the date',
    `  AAI_RELEASE_NO_REMOTE=1 is the same as ${f.nr}`,
    'Exit codes: see .aai/SKILL_RELEASE.prompt.md',
  ];
}

// parseArgs: the launcher pair comes first, the user's flags follow verbatim. Returns the options or { error, code }.
export function parseArgs(argv, env = {}) {
  const o = { launcher: 'sh', launcherPath: '', version: '', dryRun: false, confirm: false, noRemote: env.AAI_RELEASE_NO_REMOTE === '1', help: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--launcher' && (argv[i + 1] === 'sh' || argv[i + 1] === 'ps1')) o.launcher = argv[++i];
    else if (a === '--launcher-path' && i + 1 < argv.length) o.launcherPath = argv[++i];
    else if (a === '--version' || a.startsWith('--version=')) {
      const v = a === '--version' ? argv[i + 1] : a.slice('--version='.length);
      if (!v || v.startsWith('-')) return { error: ['REFUSED: --version needs a value.'], code: EXIT.USAGE };
      o.version = v;
      if (a === '--version') i++;
    } else if (a === '--dry-run') o.dryRun = true;
    else if (a === '--confirm' || a === '--yes') o.confirm = true;
    else if (a === '--no-remote') o.noRemote = true;
    else if (a === '-h' || a === '--help') { o.help = true; return o; }
    else return { error: [`Unknown argument: ${a}`, 'Run with --help for usage.'], code: EXIT.USAGE };
  }
  if (o.dryRun) o.confirm = false;
  if (!o.launcherPath) o.launcherPath = path.join(HERE, o.launcher === 'ps1' ? 'aai-release.ps1' : 'aai-release.sh');
  return o;
}

export function resolveVersion({ version, env, now }) {
  if (version) return version;
  if (env.AAI_RELEASE_DATE) return `v${env.AAI_RELEASE_DATE.replace(/-/g, '.')}`;
  return `v${now.toISOString().slice(0, 10).replace(/-/g, '.')}`;
}

const nrFlag = (launcher) => FLAG_NAMES[launcher === 'ps1' ? 'ps1' : 'sh'].nr;

// platformBlock: the reason the plan's publish path is blocked, or '' (DB-15, DB-16 and the two GitHub reasons).
export function platformBlock({ root, noRemote, launcher = 'sh', deps }) {
  if (noRemote) return '';
  const { resolved, adapter } = deps.adapter(root);
  if (resolved.mismatch) {
    return `platform record does not match the remote (recorded=${resolved.recorded}, detected=${resolved.detected}); re-record: node .aai/scripts/platform.mjs record --force`;
  }
  if (resolved.platform !== 'github') {
    return `the remote release finish runs on GitHub only (platform ${resolved.platform}); cut locally with ${nrFlag(launcher)}`;
  }
  const auth = adapter.authStatus();
  if (auth === 'cli_missing') return 'gh CLI not found on PATH';
  if (auth !== 'ok') return 'gh CLI not authenticated (gh auth status failed)';
  return '';
}

export function cutReport({ version, branch, sha, short, launcher }) {
  return [
    REPORT_HEADER,
    `- Version: ${version}`,
    `- Commit:  ${short}`,
    `- Release branch: ${branch} (${sha})`,
    `- Remote:  SKIPPED (${nrFlag(launcher)}/AAI_RELEASE_NO_REMOTE=1) — release branch ${branch} created locally at ${sha}`,
  ];
}

const first = (r) => String(r.stdout ?? '').trim();

function targetBranch(root, deps) {
  const sym = deps.git(['symbolic-ref', 'refs/remotes/origin/HEAD'], root);
  const fromOrigin = sym.status === 0 ? first(sym).replace(/^refs\/remotes\/origin\//, '') : '';
  if (fromOrigin) return fromOrigin;
  const has = (ref) => deps.git(['rev-parse', '-q', '--verify', ref], root).status === 0;
  if (has('refs/remotes/origin/main') || has('refs/heads/main')) return 'main';
  const head = deps.git(['rev-parse', '--abbrev-ref', 'HEAD'], root);
  const name = head.status === 0 ? first(head) : '';
  return !name || name === 'HEAD' ? 'main' : name;
}

const VERSION_DOC = (version) => [
  '# AAI Version', '', `- Version: ${version}`, '', 'Notes:',
  '- Written by the release engines (aai-release.sh / aai-release.ps1) at each cut;',
  '  consumed by `.aai/scripts/aai-sync.*` to stamp `Template version:` into the',
  "  target project's `.aai/system/AAI_PIN.md`. Do not edit by hand.", '',
].join('\n');

// gitStep: a failing git step of the cut ends the cut with the git-command refusal (DB-07).
class Refusal extends Error {}
function gitStep(deps, args, cwd) {
  const r = deps.git(args, cwd);
  if (r.status !== 0) {
    const detail = String(r.stderr ?? '').split('\n').find((l) => l.trim()) ?? `exit ${r.status}`;
    throw new Refusal(`REFUSED: git-command — git ${args.join(' ')}: ${detail.trim()}`);
  }
  return first(r);
}

// localCut: reuse rule for an existing release branch (14 when it holds unmerged work), then the worktree and the commit.
async function localCut(o, version, root, target, deps) {
  const check = deps.cut(['check', '--root', root, '--version', version, '--launcher', o.launcher, '--launcher-path', o.launcherPath]);
  if (check !== 0) return check;
  const branch = `chore/release-${version}`;
  const has = (ref) => deps.git(['rev-parse', '-q', '--verify', ref], root).status === 0;
  const base = has(`refs/remotes/origin/${target}`) ? `origin/${target}` : has(`refs/heads/${target}`) ? target : 'HEAD';
  if (has(`refs/heads/${branch}`)) {
    const subject = first(deps.git(['log', '-1', '--format=%s', `refs/heads/${branch}`], root));
    if (subject.startsWith(`chore(release): ${version}`) || deps.git(['merge-base', '--is-ancestor', branch, base], root).status === 0) {
      deps.git(['branch', '-D', branch], root);
    } else {
      deps.err(`REFUSED: branch ${branch} already exists with unmerged commits (${subject}).`);
      return EXIT.BRANCH;
    }
  }
  deps.arm?.();
  let wt = '';
  const stop = async () => {
    await deps.tick();
    const sig = deps.interrupted();
    if (!sig) return 0;
    deps.err(`REFUSED: interrupted (${sig}) — the temporary worktree was removed.`);
    return SIGNALS[sig];
  };
  try {
    wt = deps.mkdtemp();
    gitStep(deps, ['worktree', 'add', '-q', '-b', branch, wt, base], root);
    let code = await stop();
    if (code) return code;
    code = deps.cut(['roll', '--file', path.join(wt, 'CHANGELOG.md'), '--version', version]);
    if (code !== 0) return code;
    deps.writeFile(path.join(wt, 'docs/ai/AAI_VERSION.md'), VERSION_DOC(version));
    gitStep(deps, ['add', '--', 'CHANGELOG.md', 'docs/ai/AAI_VERSION.md'], wt);
    gitStep(deps, ['commit', '-q', '-m', `chore(release): ${version}`], wt);
    code = await stop();
    if (code) return code;
    const sha = gitStep(deps, ['rev-parse', 'HEAD'], wt);
    const short = gitStep(deps, ['rev-parse', '--short', sha], root);
    wt = removeWorktree(deps, root, wt);
    cutReport({ version, branch, sha, short, launcher: o.launcher }).forEach(deps.out);
    return 0;
  } catch (e) {
    if (!(e instanceof Refusal)) throw e;
    deps.err(e.message);
    return EXIT.REFUSED;
  } finally {
    removeWorktree(deps, root, wt);
  }
}

function removeWorktree(deps, root, wt) {
  if (wt && deps.git(['worktree', 'remove', '--force', wt], root).status !== 0) deps.rm(wt);
  return '';
}

export async function run(argv, deps) {
  const o = parseArgs(argv, deps.env);
  if (o.error) { o.error.forEach(deps.err); return o.code; }
  if (o.help) { usage(o.launcher).forEach(deps.out); return 0; }
  const top = deps.git(['rev-parse', '--show-toplevel'], deps.cwd());
  if (top.status !== 0 || !first(top)) { deps.err(`REFUSED: not a git repository (cwd=${deps.cwd()}).`); return EXIT.NOT_REPO; }
  const root = first(top);
  if (!deps.exists(path.join(root, 'CHANGELOG.md'))) { deps.err(`REFUSED: no CHANGELOG.md at repo root: ${path.join(root, 'CHANGELOG.md')}`); return EXIT.NO_CHANGELOG; }
  const version = resolveVersion({ version: o.version, env: deps.env, now: deps.now() });
  const bad = deps.git(['check-ref-format', `refs/tags/${version}`], root).status !== 0
    || deps.git(['check-ref-format', '--branch', `chore/release-${version}`], root).status !== 0;
  if (bad) { deps.err(`REFUSED: invalid version '${version}' — not a valid git tag or branch name.`); return EXIT.USAGE; }
  if (o.confirm && !o.noRemote) return deps.finish([path.join(HERE, FINISH_SCRIPT), '--root', root, '--version', version, '--confirm']);
  const target = targetBranch(root, deps);
  if (!o.confirm) {
    const args = ['plan', '--root', root, '--version', version, '--target-branch', target, '--launcher', o.launcher];
    if (o.noRemote) args.push('--no-remote');
    else {
      const block = platformBlock({ root, noRemote: false, launcher: o.launcher, deps });
      if (block) args.push('--gh-block', block);
    }
    return deps.cut(args);
  }
  return localCut(o, version, root, target, deps);
}

function realDeps() {
  const spawn = (cmd, args, cwd) => {
    const r = spawnSync(cmd, args, { cwd, encoding: 'utf8', maxBuffer: 64 << 20 });
    return { status: r.status ?? 1, stdout: r.stdout ?? '', stderr: r.error ? String(r.error.message) : (r.stderr ?? '') };
  };
  const interrupted = { name: '' };
  return {
    git: (args, cwd) => spawn('git', args, cwd),
    // In process: killing the launcher stops the release, as the old exec did.
    finish: async (args) => (await import(pathToFileURL(args[0]).href)).runCli(args.slice(1)),
    cut: (args) => cutMain(args),
    adapter: (root) => {
      const resolved = resolvePlatform({ repoRoot: root });
      return { resolved, adapter: resolved.platform ? createAdapter(resolved.platform, { cwd: root }) : null };
    },
    exists: (p) => fs.existsSync(p),
    writeFile: (p, d) => { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, d); },
    mkdtemp: () => fs.mkdtempSync(path.join(os.tmpdir(), 'aai-release-wt-')),
    rm: (p) => fs.rmSync(p, { recursive: true, force: true }),
    env: process.env, now: () => new Date(), cwd: () => process.cwd(),
    out: (l) => process.stdout.write(`${l}\n`),
    err: (l) => process.stderr.write(`${l}\n`),
    tick: () => new Promise((r) => setImmediate(r)),
    arm: () => { for (const sig of Object.keys(SIGNALS)) process.on(sig, () => { interrupted.name = sig; }); },
    interrupted: () => interrupted.name,
  };
}

const realOrResolve = (p) => { try { return fs.realpathSync(p); } catch { return path.resolve(p); } };
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  // A reader that closes early (`| head -1`) ends the command quietly with the SIGPIPE status, not a stack trace.
  process.stdout.on('error', (e) => { if (e.code === 'EPIPE') process.exit(141); throw e; });
  process.exitCode = await run(process.argv.slice(2), realDeps());
}
