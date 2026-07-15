---
id: doctor-vendored-layer-drift
type: change
number: 13
status: draft
links:
  research: RES-0001
  pr: []
  commits: []
---

# Change — aai-doctor Reports Vendored-Layer Drift vs Canonical Main

## Summary
- A target project's vendored .aai/ layer silently ages: fixes land in the
  canonical template repo and nobody is told. Operator hit this twice today
  (ISSUE-0006/0008 fixed in canon; the affected project still mints wrong
  numbers until someone remembers /aai-update). aai-doctor should surface
  "layer is N commits behind canonical" with the remedy.

## Motivation / Business Value
- Converts a silent, recurring class of confusion (fixed-in-canon bugs
  reappearing in projects) into a visible, actionable health report line.

## Scope
- In scope: SKILL_DOCTOR check using the existing .aai/system/AAI_PIN.md
  mechanism (pin_commit vs canonical main HEAD via git ls-remote of the
  canonical repo URL recorded in the pin; offline-tolerant: degrade to
  "cannot verify (offline)" info line, never a failure); report line with
  commit distance when computable and the /aai-update remedy; a doctor
  test-suite stanza.
- In scope (added at planning, spec D1): extending the AAI_PIN contract with a
  "Canonical repo" field and making aai-sync.sh/aai-sync.ps1 stamp it going
  forward (backward-tolerant: pins without the field fall back to Source path
  or degrade to "unverifiable"); the pin field is where the check learns the
  canonical URL, so the pin-writer block is part of this change.
- Out of scope: auto-updating; changing aai-sync/aai-update BEHAVIOR beyond
  the pin stamp and evidence lines; notifications outside doctor runs.

## Affected Area
- .aai/SKILL_DOCTOR.prompt.md (or its script if one exists), .aai/system/AAI_PIN.md
  contract wording, tests.

## Desired Behavior (To-Be)
- `/aai-doctor` in a vendored project prints one of:
  "layer up-to-date (pin <sha> == canonical)", "layer BEHIND canonical by N
  commit(s) — run /aai-update", or "layer drift unverifiable (offline / no
  pin)" — never hard-fails on network absence.

## Acceptance Criteria
- AC-001: pin == remote HEAD -> up-to-date line, exit unchanged.
- AC-002: pin behind -> BEHIND line naming N (or "unknown distance" when only
  inequality is provable) + /aai-update remedy.
- AC-003: no network / no pin file -> info line, doctor still completes.
- AC-004: doctor suite covers all three paths with fixtures (no real network
  in tests).
