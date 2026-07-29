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
