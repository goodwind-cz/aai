---
id: false-open-drift-heuristic
type: change
number: 27
status: draft
links:
  pr: []
  commits: []
---

# Change — Docs-audit false-open drift heuristic (delivered but still draft/implementing)

## Summary
- Add a `probable-false-open` drift verdict to the docs-audit engine: a doc in
  an open status (`draft`/`implementing`/`accepted`) whose delivery is already
  evidenced in git should be flagged, mirroring the existing
  `probable-false-done` check in the opposite direction.

## Motivation / Business Value
- On 2026-07-17 the audit reported CLEAN while 49 delivered work items
  (CHANGE-0009..0026, ISSUE-0007/0008, SPEC-0015..0038, RFC-0007..0011) still
  sat in `draft`/`implementing`/`accepted` — the close ceremony (status flip,
  links.pr/commits, doc_lifecycle + work_item_closed events) was skipped and
  nothing caught it. The only false-open detector today is
  `probable-stale-open`, which never fires for recently touched docs.
- Without this, INDEX.md misrepresents project state and close telemetry
  silently rots.

## Scope
- In scope: `.aai/scripts/lib/docs-audit-core.mjs` drift heuristics; digest
  section + suggested next step; tests.
- Out of scope: auto-remediation (report-only, operator decides), changes to
  the close gate itself.

## Affected Area
- docs-audit engine (`docs-audit.mjs`, `lib/docs-audit-core.mjs`), audit digest
  output consumed by /aai-docs-audit.

## Desired Behavior (To-Be)
- For every doc in an open status, the audit checks delivery evidence:
  the doc id (or its numbered file prefix, e.g. `CHANGE-0009`) mentioned in a
  merged commit subject in a delivery context (feat/fix/chore that is not the
  intake commit itself), or an `ac_evidence` event, or a fully terminal AC
  Status table with evidence.
- On a hit, verdict `probable-false-open` with the evidencing commit(s) in the
  reasons, suggested step "confirm delivery, then run close ceremony
  (status flip + links + doc_lifecycle/work_item_closed events)".
- Intake commits (the commit that created the doc) must not count as delivery
  evidence — otherwise every doc would flag immediately after intake.

## Acceptance Criteria
- AC-001: An open-status doc whose ID appears in a later delivering commit
  subject is reported as `probable-false-open` with the commit hash cited.
- AC-002: A freshly intaken doc (only its intake commit references it) is NOT
  flagged.
- AC-003: The digest gains a false-open section (or rows in the drift report)
  and the overall verdict becomes NEEDS-TRIAGE when any exist.
- AC-004: Existing verdicts (false-done, stale-open, partial) are unchanged;
  full test suite passes.

## Verification
- `node .aai/scripts/docs-audit.mjs` on a fixture repo with a delivered-but-
  draft doc reports `probable-false-open`; project test suite green.

## Constraints / Risks
- Heuristic precision: commit-message matching must respect the existing
  sibling-ID boundary rules (CHANGE-0002 D11) to avoid cross-matches.
- Keep it report-only; the operator decides closure (RFC-0002 principle).

## Notes
- Motivating incident: remediation batch of 2026-07-17 (49 docs closed
  retroactively); see docs_audit events around that date in
  docs/ai/EVENTS.jsonl.
