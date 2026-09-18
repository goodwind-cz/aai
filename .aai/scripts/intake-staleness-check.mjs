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

function isGitRepo(repo, timeoutMs, deadline) {
  return budgetedGit(repo, ['rev-parse', '--git-dir'], timeoutMs, deadline);
}

// budgetedGit — the ONE call site every git() invocation in this file goes
// through from here down (Spec-AC-25: "clamp every git call, not only
// fetches, to the remaining --budget-ms"). Before this fix only the two
// `git fetch` call sites clamped their own timeout to the remaining budget;
// every OTHER call (symbolic-ref, rev-parse, rev-list, submodule status,
// config lookups) used the flat per-call --timeout-ms regardless of how much
// of the wall-clock budget was already spent, so a slow or hung LOCAL git
// invocation (or simply many of them) could keep running well past
// --budget-ms. Once the deadline has passed, no further git process is even
// spawned — this call degrades to a plain failure silently, exactly like a
// real git failure already does at every call site below.
function budgetedGit(repo, argsArr, timeoutMs, deadline) {
  const remaining = deadline - Date.now();
  if (remaining <= 0) return { ok: false, stdout: '', timedOut: false, enoent: false };
  return git(repo, argsArr, Math.min(timeoutMs, remaining));
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

  const headRef = budgetedGit(repo, ['symbolic-ref', '-q', 'HEAD'], timeoutMs, deadline);
  if (!headRef.ok) return; // detached HEAD -> skip silently
  const branch = headRef.stdout.replace(/^refs\/heads\//, '');
  if (!branch) return;

  const upstreamRef = budgetedGit(
    repo,
    ['rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}'],
    timeoutMs,
    deadline,
  );
  if (!upstreamRef.ok || !upstreamRef.stdout) return; // no configured upstream -> skip silently
  const upstream = upstreamRef.stdout;
  const slash = upstream.indexOf('/');
  if (slash <= 0) return;
  const remoteName = upstream.slice(0, slash);
  const remoteBranch = upstream.slice(slash + 1);
  if (!remoteBranch) return;

  if (!noFetch) {
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
    const fetchRes = budgetedGit(repo, ['fetch', '--quiet', remoteName, fetchRefspec], timeoutMs, deadline);
    if (!fetchRes.ok) return; // unreachable / auth failure / timeout / budget exhausted -> skip silently
  }

  const countRes = budgetedGit(repo, ['rev-list', '--count', `HEAD..${upstream}`], timeoutMs, deadline);
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
function listInitializedSubmodulePaths(repo, timeoutMs, deadline) {
  const res = budgetedGit(repo, ['submodule', 'status'], timeoutMs, deadline);
  if (!res.ok || !res.stdout) return [];
  const paths = [];
  for (const line of res.stdout.split('\n')) {
    if (!line || line.startsWith('-')) continue; // uninitialized -> skip
    // `git submodule status` format: <flag><40-hex-sha1> <path>[ (<describe>)].
    // A naive `trimmed.split(/\s+/)` (the previous approach) truncates any
    // path containing whitespace at its first space, silently mis-resolving
    // the submodule's directory (Spec-AC-26). Parse positionally instead:
    // the flag char plus the fixed-width sha1 anchor where the path begins,
    // and an optional trailing " (<describe>)" is stripped from the end —
    // whatever whitespace remains between them is part of the path itself.
    // The flag char is OPTIONAL in this pattern: `git()` trims the WHOLE
    // multi-line stdout blob, not each line, so a leading-space flag on the
    // very first line is already gone by the time it reaches here.
    const m = line.match(/^[+U ]?([0-9a-f]{40}) (.+?)(?: \([^()]*\))?$/);
    if (m && m[2]) paths.push(m[2]);
  }
  return paths;
}

// The .gitmodules SECTION name for a given submodule path (needed to look up
// `submodule.<name>.branch`); null when .gitmodules is absent or has no
// matching row.
function submoduleNameForPath(repo, subPath, timeoutMs, deadline) {
  if (!fs.existsSync(path.join(repo, '.gitmodules'))) return null;
  const res = budgetedGit(
    repo,
    ['config', '-f', '.gitmodules', '--get-regexp', '^submodule\\..*\\.path$'],
    timeoutMs,
    deadline,
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
//
// Spec-AC-26: git's own `submodule.<name>.branch` convention treats the
// literal value `.` as a SENTINEL ("track whatever branch the superproject
// itself has checked out"), never as a real branch name. Reading it as a
// refspec (the previous behavior) built `origin/.`, which resolves to
// nothing, so the submodule silently read as "up to date" — indistinguishable
// from a submodule with no staleness at all. Treating `.` as equivalent to
// "no branch configured" and falling through to the same origin/HEAD default
// -branch resolution used when `submodule.<name>.branch` is absent gives a
// REAL behind-count instead of a silent skip.
function resolveSubmoduleBranch(repo, subPath, name, timeoutMs, deadline) {
  if (name) {
    const cfg = budgetedGit(repo, ['config', '-f', '.gitmodules', '--get', `submodule.${name}.branch`], timeoutMs, deadline);
    if (cfg.ok && cfg.stdout) {
      const b = cfg.stdout.trim();
      if (b && b !== '.') return b;
    }
  }
  const subDir = path.join(repo, subPath);
  const head = budgetedGit(subDir, ['symbolic-ref', 'refs/remotes/origin/HEAD'], timeoutMs, deadline);
  if (head.ok && head.stdout) return head.stdout.replace(/^refs\/remotes\/origin\//, '');
  return null;
}

function checkSubmodulesArm(args, lines, deadline) {
  const { repo, timeoutMs, noFetch } = args;
  const subPaths = listInitializedSubmodulePaths(repo, timeoutMs, deadline);

  for (const subPath of subPaths) {
    if (Date.now() >= deadline) break; // budget exhausted -> stop silently, keep what was found
    const subDir = path.join(repo, subPath);
    if (!fs.existsSync(subDir)) continue;

    const name = submoduleNameForPath(repo, subPath, timeoutMs, deadline);
    const branch = resolveSubmoduleBranch(repo, subPath, name, timeoutMs, deadline);
    if (!branch) continue; // D7: neither ref resolves -> degrade this submodule alone

    if (!noFetch) {
      // Explicit destination refspec — same reasoning as the branch arm
      // above: never depend on ambient tracking-ref-update behavior.
      const fetchRes = budgetedGit(subDir, ['fetch', '--quiet', 'origin', `+${branch}:refs/remotes/origin/${branch}`], timeoutMs, deadline);
      if (!fetchRes.ok) continue; // this submodule alone degrades (incl. budget exhausted), others still checked
    }

    const ref = `origin/${branch}`;
    const countRes = budgetedGit(subDir, ['rev-list', '--count', `HEAD..${ref}`], timeoutMs, deadline);
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

  const dirCheck = isGitRepo(args.repo, args.timeoutMs, deadline);
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
  // Spec-AC-25: this preflight's OWN contract (see the exit-codes note at the
  // top of this file) is "0 always at runtime" — a usage error (exit 2) is
  // the one case a human typed wrong, thrown deliberately via exit(2) above
  // and caught by runMain's own ExitSignal branch before onError ever runs.
  // An unexpected bug here (a genuine ReferenceError/TypeError, not a usage
  // error) must never surface as a crash with a stack trace on the caller's
  // stderr: the intake router only ever "relays stdout verbatim" and
  // "proceeds regardless of outcome" — a crash is not a degradation this
  // preflight is allowed to hand back. Swallow it silently and exit 0.
  runMain(() => main(), { onError() { process.exitCode = 0; } });
}
