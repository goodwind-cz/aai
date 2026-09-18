// lib/pr-sweep.mjs — the ONE pr_sweep record predicate (Spec-AC-33/34,
// CHANGE-0060 step 5d mechanization / GitHub issue 338).
//
// append-event.mjs (write side) and lane-gate.mjs --sweep-check (read side)
// BOTH import sweepContradictions from here instead of each holding its own
// copy (validation-round1 NB-2: the read side re-checked only one of the
// four contradictions, so a hand-appended record could carry
// threads_unresolved: 7 and outcome: swept past --sweep-check). One
// predicate, called twice.

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
