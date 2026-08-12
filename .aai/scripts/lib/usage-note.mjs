// usage-note.mjs — canonical usage_total_tokens=<N> note-marker grammar
// (SPEC-0089-spec-token-economics-end-to-end, Spec-AC-01: SINGLE SOURCE).
//
// metrics-flush.mjs (INFO/WARNING classification of undecomposed-note vs
// capture-missing runs), metrics-report.mjs (per-item + per-role token
// columns), and generate-overview.mjs (per-item + grand-total token
// decoration) must never fork on what counts as a valid marker — they all
// import USAGE_NOTE_RE / extractUsageTotal from here. The raw capturing
// regex literal must exist in exactly ONE source file: this one (TEST-003
// grep contract). Node stdlib only (docs/TECHNOLOGY.md).
//
// GRAMMAR: the complete canonical token, delimited on BOTH sides — the exact
// boundary regex originally inlined at metrics-flush.mjs:432 (PR #158
// boundary-hardening), byte-identical, no global flag (single-match callers
// only; a `.match()` on this regex returns the first hit with `[1]` as the
// captured digit string):
//   (?:^|[\s"'(\[])usage_total_tokens=(\d+)(?=$|[\s"'),\].;])
// A malformed value (usage_total_tokens=123oops) or a prefixed key
// (not_usage_total_tokens=456) never matches — on purpose, a malformed note
// is not an honest total.
export const USAGE_NOTE_RE = /(?:^|[\s"'(\[])usage_total_tokens=(\d+)(?=$|[\s"'),\].;])/;

// extractUsageTotal(note) -> integer total from the first canonical marker
// match in `note`, or null when `note` is not a string or carries no valid
// marker. Never throws.
export function extractUsageTotal(note) {
  if (typeof note !== 'string') return null;
  const m = note.match(USAGE_NOTE_RE);
  return m ? Number(m[1]) : null;
}

// --- honest-gap SENTINEL grammar (spec-telemetry-completeness) ---------------
// The close-time usage-capture gate's escape hatch: a missing marker cannot,
// by itself, distinguish "orchestrator forgot to record usage" from "the
// harness genuinely exposed no usage" — both look like a dropped marker. So a
// run that honestly had NO usage to record says so explicitly with this
// sentinel, which counts as captured and passes even under an `enforce` dial
// (enforce must not punish an honest gap — intake Constraints).
//
// GRAMMAR: the complete canonical token `usage_capture=none`, delimited on
// BOTH sides with the SAME boundary discipline as USAGE_NOTE_RE — a prefixed
// key (not_usage_capture=none) or a different value (usage_capture=partial)
// never matches, on purpose (only an explicit "none" is an honest absence).
export const USAGE_SENTINEL_RE = /(?:^|[\s"'(\[])usage_capture=none(?=$|[\s"'),\].;])/;

// hasUsageSentinel(note) -> true when `note` carries the canonical
// usage_capture=none sentinel. Never throws; a non-string is false.
export function hasUsageSentinel(note) {
  return typeof note === 'string' && USAGE_SENTINEL_RE.test(note);
}

// --- requested/actual MODEL marker grammar (validation-cost-calibration
// Spec-AC-04) -----------------------------------------------------------
// `requested_model=<id>` / `actual_model=<id>` make a silently-dropped model
// override (CLI ~0.145.0 history: the subagent model catalog is narrower
// than the top level and explicit overrides have been dropped) VISIBLE in
// METRICS instead of being read as independence that never happened.
//
// GRAMMAR: same both-sides boundary discipline as USAGE_NOTE_RE — left
// `(?:^|[\s"'(\[])`, right `(?=$|[\s"'),\].;])` — around the KEY, so a
// prefixed key (not_requested_model=x) or an empty value
// (requested_model=) never matches, exactly like the existing
// not_usage_total_tokens=456 rejection. The captured <id> is a base id
// `[A-Za-z0-9][A-Za-z0-9._:@/+-]*` plus an OPTIONAL bracketed
// context-window suffix `(?:\[[A-Za-z0-9._-]+\])?` — required because
// `claude-opus-4-8[1m]` is a real recorded model id and the bare
// USAGE_NOTE_RE right-boundary class does not admit `[`.
const MODEL_ID_GROUP = "([A-Za-z0-9][A-Za-z0-9._:@/+-]*(?:\\[[A-Za-z0-9._-]+\\])?)";
export const REQUESTED_MODEL_RE = new RegExp(
  '(?:^|[\\s"\'(\\[])requested_model=' + MODEL_ID_GROUP + '(?=$|[\\s"\'),\\].;])'
);
export const ACTUAL_MODEL_RE = new RegExp(
  '(?:^|[\\s"\'(\\[])actual_model=' + MODEL_ID_GROUP + '(?=$|[\\s"\'),\\].;])'
);

// extractRequestedModel(note) -> the requested_model=<id> value from `note`,
// or null when `note` is not a string or carries no valid marker (prefixed
// key, empty value, malformed id). Never throws.
export function extractRequestedModel(note) {
  if (typeof note !== 'string') return null;
  const m = note.match(REQUESTED_MODEL_RE);
  return m ? m[1] : null;
}

// extractActualModel(note) -> the actual_model=<id> value from `note`, or
// null under the same conditions as extractRequestedModel. Never throws.
export function extractActualModel(note) {
  if (typeof note !== 'string') return null;
  const m = note.match(ACTUAL_MODEL_RE);
  return m ? m[1] : null;
}

// modelOverrideDropped(note) -> true ONLY when `note` carries BOTH markers
// and their values differ (a granted model that is not the requested one —
// the override was silently dropped). false when either marker is absent
// or the two values are equal (an equal pair is the positive evidence the
// override took). Never throws.
export function modelOverrideDropped(note) {
  const requested = extractRequestedModel(note);
  const actual = extractActualModel(note);
  if (requested === null || actual === null) return false;
  return requested !== actual;
}

// --- canonical harness-dispatched role vocabulary (SINGLE SOURCE) ------------
// The six roles the harness dispatches per ride — state.mjs ROLES minus the
// meta-roles Orchestration / Metrics Flush, which may legitimately run with no
// usage marker and are therefore never gated. Both the close-time usage-capture
// gate (close-work-item.mjs) and the factory-report run-coverage KPI + role
// split (generate-factory-report.mjs) import this list + normalizeRole so a new
// role variant is never silently un-gated or mis-bucketed (drift risk, intake
// Constraints). Longest-first so a longest-prefix match assigns recorded
// variants ("Remediation (E1 over-kill)", "Code Review (re-review)",
// "Implementation (loop)") to their canonical bucket; "TDD Implementation"
// starts with "TDD", never with "Implementation", so the two never collide.
export const CANONICAL_ROLES = [
  'TDD Implementation',
  'Code Review',
  'Implementation',
  'Remediation',
  'Validation',
  'Planning',
].sort((a, b) => b.length - a.length);

// The gate's "expected to carry usage telemetry" set is exactly the canonical
// harness-dispatched roles (an alias, for call-site readability).
export const HARNESS_DISPATCHED_ROLES = CANONICAL_ROLES;

// normalizeRole(raw) -> one of CANONICAL_ROLES by longest-prefix match, or null
// when nothing matches (the report records 'Other'; the gate leaves it
// un-gated). Match semantics are byte-identical to the form previously inlined
// in generate-factory-report.mjs (moved here as the single source).
export function normalizeRole(raw) {
  if (typeof raw !== 'string' || raw === '') return null;
  for (const c of CANONICAL_ROLES) {
    if (raw === c || raw.startsWith(`${c} `) || raw.startsWith(`${c}(`)) return c;
  }
  // Fall back to a plain prefix for any spacing the two forms above miss.
  for (const c of CANONICAL_ROLES) {
    if (raw.startsWith(c)) return c;
  }
  return null;
}

// isHarnessDispatchedRole(raw) -> true when `raw` normalizes to a canonical
// harness-dispatched role (the only runs the usage-capture gate ever inspects).
export function isHarnessDispatchedRole(raw) {
  return normalizeRole(raw) !== null;
}
