---
id: strategy-scaled-evidence
number: 122
type: change
status: draft
user_visible: true
ceremony_level: 1
links:
  pr: []
  commits: []
---

# Change — evidence requirements scale with the recorded strategy (direct rides stop paying TDD ceremony)

## Summary
- Live cost forensics (downstream InfluxDriver, Codex log 2026-08-04): a
  ONE-LINE pandas fix under the `direct` strategy still produced a spec
  demanding a STORED pre-fix RED artifact and a full test matrix. Review
  refused without the RED artifact -> Remediation reproduced the warning
  against base + Re-review = 2 full agent runs for evidence the chosen
  strategy never promised. That is TDD's contract leaking into non-TDD
  rides.
- Fix: PLANNING prompt + spec template derive the EVIDENCE CONTRACT from
  the recorded implementation strategy (CHANGE-0100): `tdd/hybrid` -> RED
  artifact + full matrix (unchanged); `direct` -> targeted regression tests
  green + scoped diff, NO stored RED artifact, NO matrix beyond declared
  versions; `untested` -> rationale + scoped diff only.
- Deterministic enforcement (prose doesn't fire): spec-lint gains a rule —
  a spec whose STATE-recorded strategy is direct/untested but whose AC/
  verification text requires a RED artifact or TDD-cycle evidence is a
  lint FINDING at write time (Planning fixes it before freeze, not Review
  three agents later).

## Acceptance Criteria
- AC-001: spec-lint flags a direct-strategy spec demanding RED artifacts
  (RED-first fixture) and passes the same text under tdd strategy.
- AC-002: SPEC_TEMPLATE + PLANNING document the per-strategy evidence
  table; prompt bytes ledger-credited.
- AC-003: tdd rides' requirements byte-unchanged (non-regression pins).

## Constraints / Risks
- Ceremony L1. Touches PLANNING prompt (ledger) + spec-lint.mjs + template.
- Boundary honesty: review may still ASK for more evidence as a finding —
  the change removes only the hard REQUIREMENT mismatch.
