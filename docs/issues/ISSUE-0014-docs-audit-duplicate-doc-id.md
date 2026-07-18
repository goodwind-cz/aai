---
id: docs-audit-duplicate-doc-id
type: issue
number: 14
status: draft
links:
  pr: []
  commits: []
---

# Issue: docs-audit silently overwrites duplicate frontmatter ids instead of flagging them

## Summary
- Two docs sharing a frontmatter `id` are not detected by `docs-audit`. The
  `byId` map (`docs-audit-core.mjs` ~L1035-1036) does `byId.set(d.id, d)`, so a
  second doc with the same id silently overwrites the first, and per-id logic
  (closeout-candidate spec resolution, roll-ups) operates on whichever doc won
  the map — a silent governance-integrity corruption. The audit reports CLEAN
  while the collision is live.

## Root Cause
- Doc identity is `id = fm.id ?? primary` (L683). Nothing asserts ids are
  unique across the scanned set; `byId` is a last-writer-wins Map. Observed
  2026-07-18: a SPEC created without the `spec-` prefix collided with its change
  (both id `secrets-preflight-unterminated-quote-safe-direction`); `docs-audit`
  stayed CLEAN and only `close-work-item.mjs` (fail-closed on the ambiguous id)
  surfaced it — late, at close time.

## Current Cost / Risk
- Governance-integrity: a duplicate id makes the audit's per-id resolution
  (which spec is `done`, which doc a closeout candidate references) silently
  pick one doc; the other becomes invisible to id-keyed checks. The audit is the
  trusted "state of the docs" oracle — a silent id collision undermines it.

## Steps to Reproduce
- Two docs (any types) with identical frontmatter `id`; `node
  .aai/scripts/docs-audit.mjs` → currently CLEAN, no duplicate-id finding.

## Expected vs Actual
- Expected: `docs-audit` emits a deterministic `duplicate-doc-id` finding
  naming the shared id and all doc paths that carry it, and the overall verdict
  is NEEDS-TRIAGE while a collision exists.
- Actual: silent last-writer-wins in `byId`; verdict CLEAN.

## Acceptance Criteria
| AC | Status | Evidence |
|---|---|---|
| AC-001: when ≥2 scanned docs share a frontmatter `id`, docs-audit emits a `duplicate-doc-id` finding naming the id + all carrying paths, and the verdict becomes NEEDS-TRIAGE. | pending | |
| AC-002: no false positives — a unique-id corpus (the real repo) reports zero duplicate-doc-id findings; the fileId/slug distinction is respected (a doc's slug id and its numbered fileId are the same doc, not a duplicate). Existing docs-audit behavior/verdicts otherwise unchanged; suite green. | pending | |

Ceremony justification: additive detection in one governance script
(docs-audit-core.mjs) + regression stanzas; no shared-schema change, no
protected path (L1).

## Verification
- New stanzas in `tests/skills/test-aai-docs-audit.sh`: a two-doc same-id
  fixture (flagged, NEEDS-TRIAGE) + a negative control (unique ids, incl. a
  change+spec pair with the correct `spec-` prefix → clean); real-repo audit
  stays CLEAN (0 duplicate-doc-id); suite green.

## Constraints / Risks
- Deterministic; do not change how `id` is computed (fm.id ?? primary); only
  ADD the uniqueness check. Distinguish a legitimate slug-vs-fileId of the SAME
  doc from two DIFFERENT docs sharing an id.

## Notes
- Source: the SPEC-0056/ISSUE-0013 spec-id collision (decisions.jsonl
  process_finding, 2026-07-18) — close-work-item.mjs caught it late; this makes
  the AUDIT catch it early. A separate follow-up may enforce the `spec-` prefix
  at allocation/Planning; this issue is the detection backstop.
