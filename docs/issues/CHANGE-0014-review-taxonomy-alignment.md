---
id: review-taxonomy-alignment
type: change
number: 14
status: draft
links:
  spec: spec-single-dual-verdict-review
  pr: []
  commits: []
---

# Change — Align Orchestration-Facing Surfaces With the Dual-Verdict Review Taxonomy

## Summary
- The dual-verdict review (SPEC single-dual-verdict-review) replaced the
  Stage-1/Stage-2 + ERROR/WARNING taxonomy, but orchestration-facing surfaces
  still speak the old one (review dogfood finding NB-1): REMEDIATION.prompt.md
  (Stage-1/Stage-2 ERROR findings), SKILL_TDD.prompt.md:325, WORKFLOW.md:63,
  ORCHESTRATION_HITL.prompt.md:22, orchestration-dispatch.mjs:166,
  system/AUTONOMOUS_LOOP.md, system/SUPERPOWERS_INTEGRATION.md.

## Motivation / Business Value
- A review FAIL dispatches Remediation with a failure taxonomy that can never
  match a new-format report -> mis-bucketing or spurious HITL escalation.
  Routing itself survives (keys on code_review.status), so this is alignment,
  not breakage — but it is the same drift class as F1 and will confuse agents.

## Scope
- In scope: reword the listed surfaces to spec_compliance/code_quality +
  BLOCKING/NON-BLOCKING; grep-wired test extending test_042's negative
  markers to these files.
- Out of scope: any behavior change; the review prompt itself.

## Acceptance Criteria
- AC-001: repo-wide grep for the old taxonomy in orchestration-facing prompts
  and scripts returns only historical docs (specs/RFCs/reports/CHANGELOG).
- AC-002: REMEDIATION prompt's finding-intake wording matches the dual-verdict
  report schema field names.
- AC-003: existing suites green; hygiene stanza extended.
