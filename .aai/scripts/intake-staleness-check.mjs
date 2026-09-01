#!/usr/bin/env node
// intake-staleness-check.mjs — read-only, silent-by-default staleness
// preflight for the shared intake entry point (CHANGE
// intake-staleness-preflight-warning / SPEC
// spec-intake-staleness-preflight-warning). Answers "is this checkout
// behind?" for the current branch versus its configured upstream, and for
// every INITIALIZED submodule versus its own comparison ref, and prints one
// `AAI-STALE: ...` line per stale ref. Nothing behind -> zero bytes of
// output. Anything fails, times out, has no upstream, or git is unavailable
// -> silent no-op. This is a soft warning, never a gate: exit is ALWAYS 0 at
// runtime; exit 2 is reserved for a CLI usage error typed by a human (D6).
//
// Reuse, not reinvention: the `git()` helper below copies the bounded,
// prompt-free spawnSync shape from `.aai/scripts/layer-drift.mjs` (lines
// 122-134: spawnSync + timeout + GIT_TERMINAL_PROMPT: '0' + timedOut
// detection), extended with D5's credential-helper/askpass disabling. Not
// imported from layer-drift.mjs: that file is a CLI with its own argv
// contract used by the SessionStart hook, and a cross-import would put a
// network probe used there on the intake path's dependency chain.
//
// The ONLY git write performed anywhere in this file is `git fetch`, and it
// only ever touches `refs/remotes/*` (Spec-AC-04). No pull, no submodule
// update, no checkout, no merge, no rebase — ever.
//
// Usage:
//   node intake-staleness-check.mjs [--repo <path>] [--timeout-ms <n>]
//     [--budget-ms <n>] [--no-fetch]
//   --repo defaults to the current working directory; lets tests drive a
//     scratch fixture without `cd`.
//   --timeout-ms bounds EACH individual `git fetch` call (default 5000, D4).
//   --budget-ms bounds the WHOLE preflight's wall clock across the
//     superproject fetch and every submodule fetch (default 10000, D4);
//     once spent, remaining submodules are skipped silently.
//   --no-fetch skips the network entirely and compares against whatever
//     remote-tracking refs already exist — makes the compare logic testable
//     with zero network (also used by the D4 timing/degradation fixtures).
//
// Exit codes:
//   0  every runtime outcome, including every degradation (D6).
//   2  CLI usage error (unknown flag / missing value) — a human ran it wrong.

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

const DEFAULT_TIMEOUT_MS = 5_000; // per-`git fetch` bound (D4)
const DEFAULT_BUDGET_MS = 10_000; // total preflight wall-clock budget (D4)

function usage() {
  process.stderr.write(
    'Usage: intake-staleness-check [--repo <path>] [--timeout-ms <n>]\n' +
    '                              [--budget-ms <n>] [--no-fetch]\n' +
    '  Prints AAI-STALE: lines for a behind branch/submodule, read-only.\n' +
    '  Exit: 0 always at runtime (silent-by-default) | 2 usage error.\n',
  );
}

function fail(msg) {
  process.stderr.write(`intake-staleness-check: ${msg}\n`);
  usage();
  exit(2);
}

function parseArgs(argv) {
  const args = {
    repo: process.cwd(),
    timeoutMs: DEFAULT_TIMEOUT_MS,
    budgetMs: DEFAULT_BUDGET_MS,
    noFetch: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const tok = argv[i];
    const need = (name) => {
      const v = argv[++i];
      if (v === undefined || v.startsWith('--')) fail(`${name} needs a value`);
      return v;
    };
    if (tok === '--repo') args.repo = path.resolve(need('--repo'));
    else if (tok === '--timeout-ms') {
      const n = Number.parseInt(need('--timeout-ms'), 10);
      if (!Number.isInteger(n) || n <= 0) fail('--timeout-ms must be a positive integer');
      args.timeoutMs = n;
    } else if (tok === '--budget-ms') {
      const n = Number.parseInt(need('--budget-ms'), 10);
      if (!Number.isInteger(n) || n <= 0) fail('--budget-ms must be a positive integer');
      args.budgetMs = n;
    } else if (tok === '--no-fetch') args.noFetch = true;
    else fail(`unknown flag: ${tok}`);
  }
  return args;
}

// --- git plumbing (bounded, prompt-free, credential-silent) -----------------
//
// D5: GIT_TERMINAL_PROMPT=0 (layer-drift.mjs pattern) PLUS the credential
// helper cleared and askpass disabled FOR THIS INVOCATION ONLY (-c flags,
// never touching the user's real git config), so a private remote in a
// keychain environment degrades exactly like an unreachable one instead of
// raising a dialog. `stdio` closes the child's stdin entirely so nothing can
// block waiting to read a response that will never come.
function git(repo, argsArr, timeoutMs) {
  const res = spawnSync(
    'git',
    ['-C', repo, '-c', 'credential.helper=', '-c', 'core.askPass=true', ...argsArr],
    {
      encoding: 'utf8',
      timeout: timeoutMs,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env, GIT_TERMINAL_PROMPT: '0', GIT_ASKPASS: 'true' },
    },
  );
  return {
    ok: res.status === 0 && !res.error,
    stdout: (res.stdout || '').trim(),
    timedOut: res.error?.code === 'ETIMEDOUT',
    enoent: res.error?.code === 'ENOENT',
  };
}

function isGitRepo(repo, timeoutMs) {
  return git(repo, ['rev-parse', '--git-dir'], timeoutMs);
}

// --- Superproject branch arm (Spec-AC-01, Spec-AC-02, Spec-AC-06) ----------
//
// Detached HEAD or no configured upstream both degrade this arm alone,
// silently, and never short-circuit the submodule arm below (Spec-AC-06).
// A fetch failure (including an upstream whose remote no longer exists) also
// degrades silently — it must never fall through to comparing against a
// stale local remote-tracking ref (edge case in the spec's Implementation
// plan).
function checkBranchArm(args, lines, deadline) {
  const { repo, timeoutMs, noFetch } = args;

  const headRef = git(repo, ['symbolic-ref', '-q', 'HEAD'], timeoutMs);
  if (!headRef.ok) return; // detached HEAD -> skip silently
  const branch = headRef.stdout.replace(/^refs\/heads\//, '');
  if (!branch) return;

  const upstreamRef = git(
    repo,
    ['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}'],
    timeoutMs,
  );
  if (!upstreamRef.ok || !upstreamRef.stdout) return; // no configured upstream -> skip silently
  const upstream = upstreamRef.stdout;
  const slash = upstream.indexOf('/');
  if (slash <= 0) return;
  const remoteName = upstream.slice(0, slash);
  const remoteBranch = upstream.slice(slash + 1);
  if (!remoteBranch) return;

  if (!noFetch) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) return; // budget already spent -> skip silently
    const fetchTimeout = Math.min(timeoutMs, remaining);
    // EXPLICIT destination refspec (never a bare `<remote> <branch>` pair):
    // a plain `git fetch origin main` only updates `refs/remotes/origin/main`
    // as an AMBIENT side effect of the remote's already-configured fetch
    // refspec matching that ref — behavior this script must not depend on,
    // since `--repo` can point at a checkout whose remote config diverges
    // from a fresh clone's default. Forcing an explicit `+<branch>:refs/remotes/<remote>/<branch>`
    // writes exactly the ref the next command reads, deterministically,
    // regardless of ambient refspec config (found: CI-only TEST-020 failure
    // with 0 AAI-STALE lines where the local reproduction was clean).
    const fetchRefspec = `+${remoteBranch}:refs/remotes/${remoteName}/${remoteBranch}`;
    const fetchRes = git(repo, ['fetch', '--quiet', remoteName, fetchRefspec], fetchTimeout);
    if (!fetchRes.ok) return; // unreachable / auth failure / timeout / stale remote -> skip silently
  }

  const countRes = git(repo, ['rev-list', '--count', `HEAD..${upstream}`], timeoutMs);
  if (!countRes.ok) return;
  const n = Number.parseInt(countRes.stdout, 10);
  if (!Number.isInteger(n) || n <= 0) return;
  lines.push(`AAI-STALE: branch ${branch} is ${n} commit(s) behind ${upstream}`);
}

// --- Submodules arm (Spec-AC-03, Spec-AC-06, D7) ---------------------------
//
// Enumerates INITIALIZED submodules only (a `git submodule status` line
// prefixed `-` is uninitialized — skipped, never fetched, never reported).
// Each submodule's failure degrades that submodule alone; it never aborts
// the loop or the run.
function listInitializedSubmodulePaths(repo, timeoutMs) {
  const res = git(repo, ['submodule', 'status'], timeoutMs);
  if (!res.ok || !res.stdout) return [];
  const paths = [];
  for (const line of res.stdout.split('\n')) {
    if (!line || line.startsWith('-')) continue; // uninitialized -> skip
    const trimmed = line.replace(/^[+U ]/, '').trim();
    const parts = trimmed.split(/\s+/);
    if (parts[1]) paths.push(parts[1]);
  }
  return paths;
}

// The .gitmodules SECTION name for a given submodule path (needed to look up
// `submodule.<name>.branch`); null when .gitmodules is absent or has no
// matching row.
function submoduleNameForPath(repo, subPath, timeoutMs) {
  if (!fs.existsSync(path.join(repo, '.gitmodules'))) return null;
  const res = git(
    repo,
    ['config', '-f', '.gitmodules', '--get-regexp', '^submodule\\..*\\.path$'],
    timeoutMs,
  );
  if (!res.ok || !res.stdout) return null;
  for (const line of res.stdout.split('\n')) {
    const m = line.match(/^submodule\.(.+)\.path (.+)$/);
    if (m && m[2] === subPath) return m[1];
  }
  return null;
}

// D7 — comparison branch: `submodule.<name>.branch` from .gitmodules when
// configured, else the submodule remote's default branch resolved from
// `refs/remotes/origin/HEAD`. Neither resolves -> null (caller degrades that
// submodule silently).
function resolveSubmoduleBranch(repo, subPath, name, timeoutMs) {
  if (name) {
    const cfg = git(repo, ['config', '-f', '.gitmodules', '--get', `submodule.${name}.branch`], timeoutMs);
    if (cfg.ok && cfg.stdout) return cfg.stdout.trim();
  }
  const subDir = path.join(repo, subPath);
  const head = git(subDir, ['symbolic-ref', 'refs/remotes/origin/HEAD'], timeoutMs);
  if (head.ok && head.stdout) return head.stdout.replace(/^refs\/remotes\/origin\//, '');
  return null;
}

function checkSubmodulesArm(args, lines, deadline) {
  const { repo, timeoutMs, noFetch } = args;
  const subPaths = listInitializedSubmodulePaths(repo, timeoutMs);

  for (const subPath of subPaths) {
    if (Date.now() >= deadline) break; // budget exhausted -> stop silently, keep what was found
    const subDir = path.join(repo, subPath);
    if (!fs.existsSync(subDir)) continue;

    const name = submoduleNameForPath(repo, subPath, timeoutMs);
    const branch = resolveSubmoduleBranch(repo, subPath, name, timeoutMs);
    if (!branch) continue; // D7: neither ref resolves -> degrade this submodule alone

    if (!noFetch) {
      const remaining = deadline - Date.now();
      if (remaining <= 0) break; // budget spent mid-list -> stop silently
      const fetchTimeout = Math.min(timeoutMs, remaining);
      const fetchRes = git(subDir, ['fetch', '--quiet', 'origin', branch], fetchTimeout);
      if (!fetchRes.ok) continue; // this submodule alone degrades, others still checked
    }

    const ref = `origin/${branch}`;
    const countRes = git(subDir, ['rev-list', '--count', `HEAD..${ref}`], timeoutMs);
    if (!countRes.ok) continue;
    const n = Number.parseInt(countRes.stdout, 10);
    if (!Number.isInteger(n) || n <= 0) continue;
    lines.push(`AAI-STALE: submodule ${subPath} is ${n} commit(s) behind ${ref}`);
  }
}

// --- CLI --------------------------------------------------------------------

function main() {
  const args = parseArgs(process.argv.slice(2));
  const deadline = Date.now() + args.budgetMs;

  const dirCheck = isGitRepo(args.repo, args.timeoutMs);
  if (dirCheck.enoent) { exit(0); return; } // git not on PATH -> silent no-op
  if (!dirCheck.ok) { exit(0); return; } // not a git work tree -> silent no-op

  const lines = [];
  checkBranchArm(args, lines, deadline);
  checkSubmodulesArm(args, lines, deadline);

  if (lines.length > 0) process.stdout.write(lines.join('\n') + '\n');
  exit(0);
}

// Allow `import { ... }` from tests without running the CLI (layer-drift.mjs
// pattern) — path comparison decoded and symlink-resolved on both sides.
function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  runMain(() => main());
}
