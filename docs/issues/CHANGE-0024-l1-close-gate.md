---
id: l1-close-gate
type: change
number: 24
status: draft
links:
  spec: spec-l1-close-gate
  amends: spec-scale-adaptive-ceremony
  pr: []
  commits: []
---

# Change — Reconcile the Close Gate and Drift Check With L0/L1 Lean Specs

## Summary
- SPEC-0030 shipped ceremony levels, but docs-audit's gateContent
  unconditionally requires the canonical Acceptance Criteria Status table
  (Review-By columns), and the drift check marks a done spec without that
  table probable-partial. A ceremony_level 0/1 lean spec therefore can NEVER
  close: gate FAIL + NEEDS-TRIAGE + VALIDATION 8b mandates FAIL on the done
  flip. Found by the first live L1 validation (truth-scoring, 2026-07-16).

## Steps to Reproduce
1. Freeze an L1 spec per WORKFLOW.md (lean AC table + Ceremony justification
   line). 2. node docs-audit.mjs --gate-file <spec> -> GATE FAIL missing AC
   Status table. 3. Flip status: done on a scratch copy -> --check --strict
   flips CLEAN -> NEEDS-TRIAGE (probable-partial).

## Expected
- gateContent and the done-drift check are level-aware: ceremony_level <= 1
  accepts the lean AC-table shape (ids + status, no Review-By columns) and
  REQUIRES the Ceremony justification line (SPEC-0030 D-rule); level >= 2 (or
  absent = 2) unchanged.

## Acceptance Criteria
- AC-001: L1 fixture spec passes --gate-file and, when done, stays CLEAN in
  --check --strict; missing justification line fails the gate naming it.
- AC-002: L2/absent behavior byte-identical (regression fixtures both ways);
  spec-lint's frozen-without-ac-table L0 exemption stays consistent.
- AC-003: suites green (docs-audit, ceremony-levels, spec-lint if present on
  branch base); strict audit CLEAN; VALIDATION 8b wording verified consistent
  (adjust <=2 lines if it hardcodes the canonical table).
