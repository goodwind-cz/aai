#!/usr/bin/env node
// watch-ci.mjs — poll a PR's CI checks to settlement (dispatch-state-sweep
// D9 / Spec-AC-09, fu-orchestrator-does-not-watch-ci).
//
// WHY THIS EXISTS. The PR ceremony's own contract ends at the push; nothing
// after that watches whether CI actually passes, so an orchestrator that
// wants to know has to invent its own poll — the same shape as the D8
// incident (a hand-rolled probe that fails closed to a number
// indistinguishable from a measurement). This is that probe, built once,
// named, and exit-coded.
//
// CLI
//   node watch-ci.mjs [--pr <N>] [--interval-seconds <N>] [--max-wait-seconds <N>]
//     --pr <N>               the PR number; omitted, `gh` resolves it from
//                             the current branch (its own documented default).
//     --interval-seconds <N> poll interval, default 15; test-only knob.
//     --max-wait-seconds <N> deadline on total wait, default 3600 (1h); past
//                             it, DEGRADE rather than poll forever (test-only
//                             knob; validation-round1 N1 — a check stuck
//                             `pending` must not block the PR ceremony
//                             indefinitely).
//
// Exit codes, three and only three, the SAME rule D8 states for a liveness
// probe — "alive", "failed" and "I could not tell" must never render as the
// same answer:
//   0  every check settled PASS (a settlement line is printed)
//   5  at least one check settled FAIL (the failing check(s) are named)
//   3  DEGRADED — `gh` is absent, the remote is not GitHub, `gh` itself
//      errored, or the wait deadline passed with checks still unsettled.
//      Reported on stderr, never a silent zero.
//   2  usage error (a bad --interval-seconds/--max-wait-seconds value)
//
// One line is printed per STATE TRANSITION (the set of name:bucket pairs
// changes from the previous poll), so a watching orchestrator has something
// to relay without re-deriving it from raw `gh` output.
//
// Rejected: a background poll started by the PR ceremony itself (D9). The
// ceremony's own contract ends at the push; a detached poller that outlives
// it is state nobody owns. The orchestrator runs this command and waits —
// the same discipline already demanded of a subagent waiting on a long run.

import { spawnSync } from 'node:child_process';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

function usage(msg) {
  process.stderr.write(`watch-ci: ${msg}\n`);
  exit(2);
}

function degrade(reason) {
  process.stderr.write(`watch-ci: degraded — ${reason}\n`);
  exit(3);
}

function parseArgs(argv) {
  const opts = { pr: undefined, intervalSeconds: 15, maxWaitSeconds: 3600 };
  for (let i = 0; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--pr') {
      const v = argv[i + 1];
      if (v === undefined || v.startsWith('--')) usage('--pr requires a value');
      opts.pr = v;
      i += 1;
    } else if (tok === '--interval-seconds') {
      const v = argv[i + 1];
      if (v === undefined || v.startsWith('--')) usage('--interval-seconds requires a value');
      if (!/^\d+(\.\d+)?$/.test(v) || Number(v) <= 0) usage(`--interval-seconds must be a positive number (got "${v}")`);
      opts.intervalSeconds = Number(v);
      i += 1;
    } else if (tok === '--max-wait-seconds') {
      const v = argv[i + 1];
      if (v === undefined || v.startsWith('--')) usage('--max-wait-seconds requires a value');
      if (!/^\d+(\.\d+)?$/.test(v) || Number(v) <= 0) usage(`--max-wait-seconds must be a positive number (got "${v}")`);
      opts.maxWaitSeconds = Number(v);
      i += 1;
    } else if (tok === '-h' || tok === '--help') {
      process.stdout.write('usage: node watch-ci.mjs [--pr <N>] [--interval-seconds <N>] [--max-wait-seconds <N>]\n');
      exit(0);
    } else {
      usage(`unknown argument "${tok}"`);
    }
  }
  return opts;
}

// A synchronous sleep with no subprocess and no platform-specific binary
// (Atomics.wait blocks the calling thread — the CLI has no other work to do
// while it waits, so blocking is exactly right here).
function sleepMs(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function ghAvailable() {
  const r = spawnSync('gh', ['--version'], { stdio: ['ignore', 'ignore', 'ignore'] });
  return !(r.error);
}

// Best-effort: a repo whose origin is not GitHub degrades rather than
// letting `gh` produce a confusing error of its own. Never throws — an
// unresolvable remote is treated as "cannot tell", not as GitHub.
function originIsGithub() {
  const r = spawnSync('git', ['remote', 'get-url', 'origin'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  if (r.error || r.status !== 0) return false;
  return /(^|[@/.])github\.com([:/]|$)/i.test((r.stdout || '').trim());
}

// One `gh pr checks` poll. Returns { checks } on success or { error } naming
// what went wrong (a non-zero exit with output that is not the checks-array
// shape, a spawn failure, or unparseable JSON) — the caller degrades.
// validation-round1 N1: `r.status` is INSPECTED, not ignored. `gh` itself
// exits non-zero when a check is pending or failing for a POPULATED array —
// that is normal, the bucket values already carry the real signal. An EMPTY
// array paired with a non-zero exit is a different shape: gh failed to
// resolve the PR/checks at all (e.g. no commit found), which must never be
// read as "zero checks, all passed" — the exact D8-forbidden shape this
// probe exists to prevent.
function pollOnce(pr) {
  const args = ['pr', 'checks'];
  if (pr !== undefined) args.push(pr);
  args.push('--json', 'name,bucket,link');
  const r = spawnSync('gh', args, { encoding: 'utf8' });
  if (r.error) return { error: `gh pr checks failed to run (${r.error.code || 'unknown'})` };
  let checks;
  try { checks = JSON.parse(r.stdout); } catch {
    return { error: `gh pr checks returned non-JSON output (exit ${r.status}): ${(r.stderr || r.stdout || '').trim().slice(0, 200)}` };
  }
  if (!Array.isArray(checks)) return { error: 'gh pr checks --json did not return an array' };
  if (checks.length === 0 && r.status !== 0) {
    return { error: `gh pr checks exited ${r.status} with no checks reported: ${(r.stderr || '').trim().slice(0, 200) || '(no stderr)'}` };
  }
  return { checks };
}

function main(argv) {
  const opts = parseArgs(argv);
  if (!ghAvailable()) degrade('gh not found on PATH');
  if (!originIsGithub()) degrade('origin remote is not a github.com URL — gh pr checks is GitHub-only');

  // validation-round1 N1: a real DEADLINE, not an unbounded `for (;;)` — a
  // check stuck `pending` (or a PR that never reports any check) must not
  // block the PR ceremony indefinitely.
  const deadlineMs = Date.now() + opts.maxWaitSeconds * 1000;
  let lastSummary = null;
  for (;;) {
    const res = pollOnce(opts.pr);
    if (res.error) degrade(res.error);
    const { checks } = res;
    // validation-round1 N1: an EMPTY checks array is "no checks reported
    // YET" (e.g. GitHub has not registered a check run against the head
    // commit), never "zero checks, settled, pass" — rendering an empty
    // array as a pass is the same shape D8 exists to forbid. Keep polling
    // (bounded by the deadline below) instead of exiting 0.
    if (checks.length === 0) {
      if (Date.now() >= deadlineMs) {
        degrade(`no checks reported after ${opts.maxWaitSeconds}s — gave up waiting`);
      }
      sleepMs(opts.intervalSeconds * 1000);
      continue;
    }
    // BLOCKING-1 (review-dispatch-state-sweep-20260913T221903Z): `gh`'s own
    // buckets are pass/fail/pending/skipping/cancel, and `skipping` is
    // TERMINAL — a check gh itself already settled as "did not run" (e.g. a
    // path-filtered job) — not a synonym for still-pending. Modeling it as
    // pending meant a PR with any skipped check could never settle and
    // polled to the --max-wait-seconds deadline before degrading. `pending`
    // now means bucket `pending` ONLY; `failed` is unchanged (fail+cancel,
    // both terminal-bad).
    const pending = checks.filter((c) => c.bucket === 'pending');
    const failed = checks.filter((c) => c.bucket === 'fail' || c.bucket === 'cancel');
    const passed = checks.filter((c) => c.bucket === 'pass');
    const skipped = checks.filter((c) => c.bucket === 'skipping');
    const summary = checks.map((c) => `${c.name}:${c.bucket}`).sort().join(',');
    if (summary !== lastSummary) {
      console.log(`watch-ci: ${checks.length} check(s) — ${pending.length} pending, ${failed.length} failed`);
      lastSummary = summary;
    }
    if (pending.length === 0) {
      if (failed.length > 0) {
        console.error(`watch-ci: FAILED — ${failed.map((c) => c.name).join(', ')}`);
        exit(5);
      }
      // Settled-pass requires every remaining check in pass/skipping AND at
      // least one real `pass` — an all-`skipping` PR is "no checks ran",
      // the same D9 empty-checks shape (an array of nothing meaningful must
      // never render as a pass), so it degrades instead of exiting 0.
      if (passed.length === 0) {
        degrade(`all ${checks.length} check(s) settled without a single pass — nothing ran (${skipped.map((c) => c.name).join(', ')})`);
      }
      console.log(`watch-ci: settled — all ${checks.length} check(s) passed (${passed.length} pass, ${skipped.length} skipped)`);
      exit(0);
    }
    if (Date.now() >= deadlineMs) {
      degrade(`checks still pending after ${opts.maxWaitSeconds}s — gave up waiting (${pending.map((c) => c.name).join(', ')})`);
    }
    sleepMs(opts.intervalSeconds * 1000);
  }
}

runMain(() => main(process.argv.slice(2)));
