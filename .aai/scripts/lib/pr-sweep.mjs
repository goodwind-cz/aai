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

// Spec-AC-33 — the four self-contradictions a pr_sweep record may never
// carry: each is a claim the payload's OWN other fields disprove. Returns a
// list of reasons (empty = consistent).
export function sweepContradictions(p) {
  const bad = [];
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
