---
id: role-token-trend
number: 130
type: change
status: draft
user_visible: true
ceremony_level: 1
---

# Change — Factory report: per-role token trend (layer-2 measurement)

## Summary
- Owner directive 2026-08-11 after the 5-layer-map audit
  (docs/analysis follow-up of the starmex article): the factory measures
  prompt bytes (diet ledger) and per-ride totals, but nothing shows WHERE
  tokens go per ROLE over time — the one unmeasured layer (context, L2).
- Since 2026-08-02 usage capture is 100% (26/26 runs marked) and
  usage_capture_gate is enforce (PR #242), so the data is now trustworthy
  enough to trend.
- Extend the EXISTING generate-factory-report.mjs (deterministic,
  zero-network, node stdlib, never imputes) with a per-role consumption
  view. No new generator, no LLM, no network.

## Acceptance Criteria
- AC-001: factory-report gains a "Role consumption" section: per role
  (Planning, Implementation, TDD Implementation, Validation, Code Review,
  Remediation) the run count, median and total usage_total_tokens per run,
  and share of ride total — computed ONLY from runs carrying the marker;
  unmarked runs counted separately as n/a (never imputed, honesty rules of
  the existing report), usage_capture=none sentinel runs shown as their own
  honest bucket.
- AC-002: a weekly trend (existing week-bucketing of the report) of
  per-role median tokens/run so context growth is visible as a curve;
  weeks with no marked runs render n/a.
- AC-003: both the HTML section and factory-report-data.json carry the new
  data; existing sections/fields byte-stable when the new inputs are absent
  (back-compat with sparse ledgers); suite test rows extend the existing
  factory-report test coverage RED-first.
- AC-004: docs/product/factory-performance-report (or the report's product
  doc, wherever it lives) updated with the new section's meaning and its
  honesty semantics.
