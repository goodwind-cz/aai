---
id: lane-intake-ceremony
number: null
type: change
status: draft
user_visible: true
ceremony_level: 1
links:
  pr: []
  commits: []
---

# Change — fast lane opens to spec-less rides: intake frontmatter as the ceremony source

## Summary
- Measured on 2026-08-02 (8 rides, 0 fast): the two rides that WERE the
  lane's exact target class — 4-5 files, test+docs only (#212 phantom pin,
  #215 scaffold guard) — could never qualify, because predicate 1 reads
  ceremony_level exclusively from SPEC frontmatter and small L0/L1 rides
  ship on an intake CHANGE doc with no spec. The gate's fail-closed default
  turned "no spec" into "never fast", structurally.
- Fix: `lane-gate.mjs --intake <CHANGE doc>` — when NO spec exists, the
  SAME fail-closed parser reads `ceremony_level:` from the intake doc's
  frontmatter; the predicate line labels the source (`source=intake`).
  A present spec ALWAYS wins — an intake can never downgrade a spec'd ride
  (anti-shopping, TEST-024). Both-absent stays heavy (unchanged default).
- Trust model unchanged: an L0/L1 level in a spec is equally self-declared
  (freezing is an L3 concern); the intake sits in the same reviewed diff;
  every degenerate input (garbage token, missing file) still fails closed.
- SKILL_PR LANE step documents passing --intake for spec-less rides
  (+189 B, ledger-credited); product doc updated.

## Acceptance Criteria
- AC-001: spec-less ride + intake `ceremony_level: 1` + remaining predicates
  -> LANE fast with `source=intake` (TEST-023).
- AC-002: garbage intake level or both-sources-absent -> heavy,
  reason=ceremony_level (TEST-023).
- AC-003: spec L2 + intake L1 -> heavy with `source=spec` (TEST-024).

## Verification
- tests/skills/test-aai-lightweight-lane.sh 24/24; prompt-diet green
  (headroom 1530 after +189 credit); docs-audit strict CLEAN.

## Constraints / Risks
- Ceremony L1, strategy direct. lane-gate.mjs is PROFILES-core — this ride
  itself takes the heavy lane (recurring honest irony, 6th time).
- The strategy predicate still requires a STATE record — deliberate
  (CHANGE-0100 anti-gaming); the orchestrator's job is to `set-strategy`
  even on inline rides.
