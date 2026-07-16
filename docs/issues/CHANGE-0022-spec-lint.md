---
id: spec-lint
type: change
number: 22
status: implementing
links:
  research: RES-0001
  spec: spec-spec-lint
  pr: []
  commits: []
---

# Change — spec-lint.mjs: Deterministic Structural Validation of Spec Documents

## Summary
- Deterministic CLI linting spec artifacts (OpenSpec pattern, RES-0001 P3):
  AC-table shape (ids unique/sequential, statuses in enum, done rows carry
  evidence), Test Plan rows map to Spec-AC ids, SPEC-FROZEN consistency
  (frozen spec must have strategy + AC table), ceremony_level enum. Sits
  beside docs-audit (docs lifecycle) as the spec-STRUCTURE lint; LLM judgment
  stays with Planning/Validation.

## Scope
- In scope: .aai/scripts/spec-lint.mjs (exit 0 clean / 1 findings / 2 usage;
  --json; --path <spec> or all governed specs; report-only posture — wired as
  an advisory line in PLANNING post-freeze and VALIDATION step 1, never a
  hard gate in v1); suite; degrade clause when absent.
- Out of scope: enforcing dial (follow-up after field experience); rewriting
  docs-audit checks (no duplication — spec-lint owns intra-spec structure,
  docs-audit owns lifecycle/drift).

## Acceptance Criteria
- AC-001: catches on fixtures: duplicate/missing Spec-AC id, done-without-
  evidence, TEST row referencing unknown AC, frozen-without-strategy,
  invalid ceremony_level; passes all current repo specs (0 findings —
  else the findings are real and get fixed or whitelisted with reason).
- AC-002: PLANNING/VALIDATION carry <=2-line advisory wiring with degrade.
- AC-003: suite + sweep green; strict audit CLEAN; prompt-diet floor holds.
