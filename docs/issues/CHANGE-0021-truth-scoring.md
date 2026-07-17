---
id: truth-scoring
type: change
number: 21
status: done
links:
  research: RES-0001
  pr:
    - 80
  commits:
    - bbf0ad4
---

# Change — Truth-Scoring on the Metrics Ledger

## Summary
- Record per-work-item reliability facts at flush (claude-flow concept minus
  the theater, RES-0001 P3): validation FAIL count before first PASS, review
  FAIL count, remediation-run count, first-pass-clean flag — derived from
  agent_runs/events already in STATE, never estimated.

## Scope
- In scope: metrics-flush.mjs computes a `reliability` object per flushed
  entry (counts derived from the runs it already reads); metrics-report.mjs
  gains a per-strategy reliability table (first-pass-clean rate, avg
  remediations); dashboard note optional. Backward compatible: old ledger
  lines without the field render as n/a.
- Out of scope: routing decisions based on scores (watch-first); any
  self-reported "truth score" numbers.

## Acceptance Criteria
- AC-001: flush writes reliability{validation_fails, review_fails,
  remediation_runs, first_pass_clean} derived ONLY from recorded runs/events;
  golden test.
- AC-002: report renders the per-strategy table; old lines n/a; byte-
  deterministic golden.
- AC-003: suite + sweep green; audit CLEAN.
