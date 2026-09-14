// iso-time.mjs — the ONE clock (CHANGE-0184 / spec-dispatch-state-sweep D7).
//
// Every producer that stamps an instant into STATE.yaml or EVENTS.jsonl
// SHALL resolve to this single definition of `nowIso()`. Before this file
// existed, `lib/state-engine.mjs` defined its own second-precision `nowIso()`
// (which `state.mjs` self-stamps with) while `append-event.mjs` wrote
// `new Date().toISOString()` directly (millisecond precision) for the `ts`
// field on every EVENTS line — two writers of "now", two precisions,
// disagreeing on their own emitted bytes. Direction is decided by evidence,
// not taste: `validation-waiver.mjs` validates an archive record's instant by
// EXACT STRING EQUALITY against a second-truncated render, so moving STATE up
// to milliseconds would break that round-trip, while moving EVENTS down to
// seconds breaks nothing — every EVENTS consumer parses with `Date.parse` and
// ordering inside a second is already given by append order in an
// append-only ledger. See SPEC-0180-spec-dispatch-state-sweep D7 for the
// full argument and R4 for the five other private truncation copies this
// file deliberately does NOT touch (no defect behind them).
//
// Node stdlib only (Technology contract: zero runtime dependencies).

export function nowIso() {
  return new Date().toISOString().replace(/\.\d+Z$/, 'Z');
}
