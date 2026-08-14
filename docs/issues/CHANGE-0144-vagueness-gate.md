---
id: vagueness-gate
number: 144
type: change
status: done
user_visible: false
ceremony_level: 1
capability: aai-intake
links:
  commits:
    - 745bfc3
  pr:
    - 258
---

# Change — mark it, do not assert it: a freeze-time gate on vagueness and unverified claims

## Summary
- Owner ask 2026-08-14 via /aai-ship, sourced from RESEARCH-0001 F2/F12
  (github/spec-kit's `/analyze` and `specify` templates).
- Our own failure, same day: intake CHANGE-0140 asserted as fact that only
  `aai-feedback-status.mjs` existed. All three feedback scripts existed.
  The false claim survived into a committed intake and was caught by
  Planning reading the code — nothing in the toolchain objected. Spec-kit
  reports the identical class from the field: an agent that produced a
  `research.md` from training data rather than research.
- Their rule is the one we lack, stated as a prohibition rather than a
  virtue: mark ambiguity with an explicit marker, and DO NOT GUESS. Ours
  has no marker vocabulary at all, so an unverified claim reads exactly
  like a verified one.

## Acceptance Criteria
- AC-001 (marker vocabulary): a documented marker for an unverified or
  underspecified claim in intake and spec bodies, with one canonical
  spelling that a linter can find; Planning states the claim WITH the
  marker instead of asserting it, and resolving one is a visible edit.
- AC-002 (freeze gate): spec-lint FAILS a spec that reaches freeze while
  any unresolved marker remains in it, naming each occurrence with its
  line; in-flight (pre-freeze) docs are reported, never blocked.
- AC-003 (bounded, or it becomes noise — F12): a hard cap on markers per
  document with the excess prioritized scope > security/privacy > UX >
  technical detail, and an explicit DON'T-ASK default list (retention,
  performance budgets, error handling, auth, integration patterns) that
  the gate never demands a marker for. Planning records both lists.
- AC-004 (vagueness detection, advisory): unquantified comparatives in an
  acceptance-criteria cell (fast, scalable, secure, robust, quickly) are
  reported with their line, but do NOT block a freeze on their own — the
  measured-criterion rule already lives in the AC table's own contract.
- AC-005 (no new ceremony for small scopes): the gate adds no step to the
  ride and no prompt bytes beyond one marker sentence; L0/L1 lanes must
  not get slower — the strongest external evidence against added ceremony
  is recorded in RESEARCH-0001 F14 (a controlled test measured 33 min vs
  8 min with no measured quality gain).
- AC-006: tests RED-first with RED_CLASS stamped at capture, replaying the
  CHANGE-0140 false-claim shape and a marker-at-freeze shape; docs updated
  truthfully; prompt-diet ledger + TEST-012 true-up if any prompt byte
  moves (checkpoint currently -5844).
