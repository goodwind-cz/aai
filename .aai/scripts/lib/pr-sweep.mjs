// lib/pr-sweep.mjs — the ONE pr_sweep record predicate (Spec-AC-33/34,
// CHANGE-0060 step 5d mechanization / GitHub issue 338).
//
// append-event.mjs (write side) and lane-gate.mjs --sweep-check (read side)
// BOTH import sweepContradictions from here instead of each holding its own
// copy (validation-round1 NB-2: the read side re-checked only one of the
// four contradictions, so a hand-appended record could carry
// threads_unresolved: 7 and outcome: swept past --sweep-check). One
// predicate, called twice.

import { execFileSync } from 'node:child_process';

// Closed set of legal pr_sweep outcomes (Spec-AC-33).
export const PR_SWEEP_OUTCOMES = new Set(['swept', 'skipped_fast_lane', 'internal_substituted']);

// Closed set of legal reviewer_bots values — the SAME tri-state
// pr-platform.mjs classifies and SKILL_PR.prompt.md:468 documents on the
// `append-event.mjs --reviewer-bots <expected|none|unknown>` call
// (code review 20260918T172546Z round 2, R2-NB-1 / Amendment 24): a missing
// key or a value outside this set (a typo, an empty object, ...) is a
// contradiction like any other field, not an open string.
export const REVIEWER_BOTS_VALUES = new Set(['expected', 'none', 'unknown']);

// A pr_sweep count/pr field is well-formed the same way parseSweepCount
// requires at write time: a genuine (already-parsed) JS integer, never a
// string, float, or negative number. A hand-appended EVENTS.jsonl line can
// carry any JSON shape at all in these fields, and `"3" <= 0` / `NaN > 0`
// coerce false the same way an out-of-vocabulary value used to slip past
// the outcome check below -- so this is the SAME class of gap, checked the
// same way (code review 20260918T172546Z, BLOCKING-1).
function isNonNegativeInt(v) {
  return typeof v === 'number' && Number.isInteger(v) && v >= 0;
}

// Spec-AC-33 — the four self-contradictions a pr_sweep record may never
// carry: each is a claim the payload's OWN other fields disprove. Returns a
// list of reasons (empty = consistent).
//
// This is also the WHOLE of the read side's defense against a hand-appended
// EVENTS.jsonl line (lane-gate.mjs --sweep-check re-runs this SAME function
// instead of re-deriving the writer's rules): every field append-event.mjs
// validates before it will write a record must be judged here too, or a
// line that bypasses the writer entirely reads as consistent regardless of
// what it says (code review 20260918T172546Z, BLOCKING-1 — reproduced with
// a hand-appended `"outcome":"totally_fine"` record that read SWEEP-CHECK
// allowed, rc=0, because no per-outcome branch below matched it).
export function sweepContradictions(p) {
  const bad = [];
  if (!PR_SWEEP_OUTCOMES.has(p.outcome)) {
    bad.push(`outcome must be one of ${[...PR_SWEEP_OUTCOMES].join('|')}, got ${JSON.stringify(p.outcome)}`);
  }
  if (p.lane !== 'fast' && p.lane !== 'heavy') {
    bad.push(`lane must be fast|heavy, got ${JSON.stringify(p.lane)}`);
  }
  if (!isNonNegativeInt(p.pr) || p.pr === 0) {
    bad.push(`pr must be a positive integer, got ${JSON.stringify(p.pr)}`);
  }
  if (!isNonNegativeInt(p.threads_seen)) {
    bad.push(`threads_seen must be a non-negative integer, got ${JSON.stringify(p.threads_seen)}`);
  }
  if (!isNonNegativeInt(p.threads_unresolved)) {
    bad.push(`threads_unresolved must be a non-negative integer, got ${JSON.stringify(p.threads_unresolved)}`);
  }
  if (!REVIEWER_BOTS_VALUES.has(p.reviewer_bots)) {
    bad.push(`reviewer_bots must be one of ${[...REVIEWER_BOTS_VALUES].join('|')}, got ${JSON.stringify(p.reviewer_bots)}`);
  }
  if (p.outcome === 'swept' && (p.threads_seen <= 0 || p.reviewer_bots !== 'expected')) {
    bad.push('swept requires threads_seen > 0 and reviewer_bots=expected');
  }
  if (p.outcome === 'skipped_fast_lane' && p.lane !== 'fast') {
    bad.push('skipped_fast_lane is not legal on the heavy lane');
  }
  if (p.outcome === 'internal_substituted' && p.reviewer_bots === 'expected') {
    bad.push('internal_substituted is not legal while reviewer_bots=expected');
  }
  if (p.threads_unresolved > 0) {
    bad.push(`threads_unresolved=${p.threads_unresolved} must be 0 before a merge-readiness claim`);
  }
  return bad;
}

// A pr_sweep count field (--threads-seen / --threads-unresolved) is a usage
// error, not a silent NaN, when it is anything other than a non-negative
// integer (validation-round1 B3: Number('abc') is NaN, and every
// sweepContradictions comparison against NaN is false, so a garbage value
// used to sail through as a "consistent" record with null counts written).
// Returns the parsed integer; throws an Error carrying `.field` on a bad
// value. `raw === undefined` means the flag was omitted entirely and
// defaults to 0 (unchanged from the pre-fix behaviour); `raw === true`
// means the flag was given with no following value (parseArgs's sentinel
// for a bare boolean flag), which is equally not a count.
export function parseSweepCount(raw, field) {
  if (raw === undefined) return 0;
  if (typeof raw !== 'string' || !/^[0-9]+$/.test(raw)) {
    const err = new Error(`--${field.replace(/_/g, '-')} must be a non-negative integer, got ${JSON.stringify(raw)}`);
    err.field = field;
    throw err;
  }
  return Number(raw);
}

// Amendment 28 — the stale-head exception. head_sha binding (Amendment 27,
// finding 3+4) makes a pr_sweep record impossible to ever land: the SAME
// commit that appends the record to docs/ai/EVENTS.jsonl is the commit that
// moves HEAD past the sha the record names, so an honest "record it, commit
// it" sequence denies its own merge the instant it lands (dogfooded on PR
// #385 itself: record f4e69da4, commit it as d4ca13a4, --sweep-check then
// denied reason=stale-head against its own just-made commit).
//
// The principled fix: a sweep is a statement about REVIEWED CODE. A commit
// that only appends to an append-only telemetry ledger does not change
// reviewed code, so it must not invalidate the record. This is the SAME
// three files SUBAGENT_CONTRACT.md's HAZ-LEDGER hazard already designates
// append-only by established convention (not a new judgment call here):
//   - docs/ai/EVENTS.jsonl        — the ledger the pr_sweep record itself
//     lands in (append-event.mjs); a sweep can never be recorded at all
//     without a commit touching this exact file.
//   - docs/ai/decisions.jsonl     — HITL/owner decision records, appended by
//     the same discipline, never rewritten.
//   - docs/ai/tests/test-runs.jsonl — test-run telemetry, appended by the
//     test harness, never rewritten.
// A path outside this set is deliberately NOT exempted, even another *.jsonl
// ledger (e.g. docs/ai/METRICS.jsonl, docs/ai/tests/golden-flow.jsonl) —
// HAZ-LEDGER does not name them, and this predicate reuses that canon rather
// than growing its own list by guessing which other files are "probably
// fine". Any other differing path — a source file, a test, a doc — still
// denies stale-head, per Spec-AC-34.
export const STALE_HEAD_SAFE_LEDGERS = new Set([
  'docs/ai/EVENTS.jsonl',
  'docs/ai/decisions.jsonl',
  'docs/ai/tests/test-runs.jsonl',
]);

// docs/INDEX.md is a SECOND, narrower exception, found by dogfooding this
// very fix against PR #385's own real history: even with the ledger set
// above, --sweep-check still denied at PR #385's actual current head,
// because the `AAI:INDEX-AUTOGEN` pre-commit hook (install-pre-commit-
// hook.sh) regenerates and re-stages docs/INDEX.md on EVERY commit that
// touches any docs/ path — and appending a pr_sweep record always touches
// docs/ai/EVENTS.jsonl, a docs/ path, so the record-carrying commit ALSO
// always carries this mechanical re-stage. Left unhandled, that reproduces
// the identical defect (a record-only commit denies its own merge) under a
// different filename — every future honest sweep would hit it, not just
// this one. docs/INDEX.md is not append-only, so it cannot join
// STALE_HEAD_SAFE_LEDGERS; instead its diff is compared with the ONE line
// that changes on every mechanical regeneration by construction — `Generated:
// <timestamp>` — stripped from both sides first. Any OTHER difference (a
// document added, removed, or its indexed metadata changed) still denies:
// this is strictly narrower than "docs/INDEX.md always safe", not a general
// doc exemption.
const INDEX_MD_PATH = 'docs/INDEX.md';
const INDEX_MD_TIMESTAMP_LINE = /^Generated: .*$/m;
function isIndexMdRegenOnlySafe(before, after) {
  const strip = (s) => s.replace(INDEX_MD_TIMESTAMP_LINE, 'Generated: <stripped>');
  return strip(before) === strip(after);
}

// readGitBlob(repoRoot, ref, path) -> file content at that commit, or null
// when the path does not exist there (a ledger created AFTER recordHead is
// legitimately absent at recordHead — its whole content at currentHead is
// then trivially an "append" onto nothing). Any OTHER git failure (bad ref,
// no git, not a repo) throws, so the caller's catch-all can fail closed
// (deny) rather than silently reading a missing blob as an empty-and-safe
// ledger.
function readGitBlob(repoRoot, ref, path) {
  try {
    return execFileSync('git', ['show', `${ref}:${path}`], {
      cwd: repoRoot, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    });
  } catch (err) {
    // git show exits non-zero both for "path missing at this ref" (fine,
    // treat as empty) and for a genuine failure (bad ref, not a repo --
    // must NOT be swallowed the same way). Distinguish the only way
    // available without parsing stderr text: ask git separately whether the
    // ref itself resolves at all.
    try {
      execFileSync('git', ['cat-file', '-e', `${ref}^{commit}`], {
        cwd: repoRoot, stdio: ['ignore', 'ignore', 'ignore'],
      });
    } catch {
      throw err; // the ref itself is bad -- a real failure, not "path absent"
    }
    return null; // ref resolves, path just isn't there at this ref
  }
}

// isStaleHeadSafeDelta(repoRoot, recordHead, currentHead) -> true only when
// EVERY path that differs between the two commits is EITHER (a) one of
// STALE_HEAD_SAFE_LEDGERS whose content at recordHead is a byte-exact
// PREFIX of its content at currentHead (an append, never a rewrite --
// HAZ-LEDGER's own "the base must stay an exact prefix" discipline, reused
// here rather than re-derived), OR (b) docs/INDEX.md with only its
// regeneration-timestamp line differing (see isIndexMdRegenOnlySafe above).
// A ledger that was REWRITTEN (its recordHead content is not a strict
// prefix -- reordered, truncated, edited in place) still denies, same as a
// non-ledger path. Any git failure denies too (returns false): this
// predicate only ever ADDS an ALLOW on top of the pre-existing stale-head
// deny, never invents a new false ALLOW out of a tool error.
export function isStaleHeadSafeDelta(repoRoot, recordHead, currentHead) {
  let changed;
  try {
    const out = execFileSync('git', ['diff', '--name-only', `${recordHead}..${currentHead}`], {
      cwd: repoRoot, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    });
    changed = out.split('\n').map((s) => s.trim()).filter(Boolean);
  } catch {
    return false;
  }
  if (changed.length === 0) return false; // caller only calls this when the shas differ; an empty diff here is unexpected -- never the reason an ALLOW happens
  for (const path of changed) {
    const isLedger = STALE_HEAD_SAFE_LEDGERS.has(path);
    const isIndex = path === INDEX_MD_PATH;
    if (!isLedger && !isIndex) return false;
    let before;
    let after;
    try {
      before = readGitBlob(repoRoot, recordHead, path) ?? '';
      after = readGitBlob(repoRoot, currentHead, path);
    } catch {
      return false;
    }
    if (after === null) return false; // present at recordHead and gone at currentHead -- a rewrite (deletion), never safe
    if (isIndex) {
      if (!isIndexMdRegenOnlySafe(before, after)) return false;
      continue;
    }
    if (!after.startsWith(before)) return false; // not a strict prefix -- rewritten, not appended
  }
  return true;
}
