---
id: delta-stage-3
type: change
number: 26
status: draft
links:
  spec: spec-delta-stage-3
  rfc: delta-spec-lifecycle
  pr: []
  commits: []
---

# Change — Delta-Spec Lifecycle, Stage 3: Close-Time Delta Merge + Provenance Drift

## Summary
- Final stage of the RFC-0011 delta-spec lifecycle. Stage 1 (SPEC-0034) defined
  the canonical Requirements contract; stage 2 (SPEC-0037) let a SPEC declare a
  `## Deltas` section and validated its shape. Stage 3 is the CONSUMER: a new
  `delta-merge.mjs` applies a merging spec's deltas into `docs/canonical/` at PR
  ceremony (the approved merge trigger) — line-surgical, deterministic,
  idempotent, no LLM in the write path — and docs-audit gains a provenance drift
  check so every canonical requirement traces to a merging spec.
- Because `docs/canonical/` is EMPTY in this repo, the merge and the drift check
  are no-ops on the live tree; the engine ships fixture-tested and ready for the
  first project that carries canonical docs.

## Motivation
The canonical layer only stays current if the deltas a spec declares are applied
mechanically at merge. Stage 3 closes the loop: declared intent (stage 2)
becomes canonical fact (stage 3) with a deterministic writer and a drift check
that fails loud on any untraced or orphaned requirement.

## Acceptance criteria
- AC-001: `delta-merge.mjs --spec <path>` reads the spec's `## Deltas` via the
  stage-2 `parseDeltasSection`, is FAIL-CLOSED on any violation (no writes), and
  applies ADDED (next unused per-domain NNN + `Provenance`), MODIFIED (replace
  body + set `Provenance`), REMOVED (retire the block) into
  `docs/canonical/<slug>.md`; re-running for the same spec is byte-idempotent.
- AC-002: docs-audit `--check` reports a provenance drift finding for any
  canonical requirement whose `Provenance` is empty or names a non-existent
  spec; CLEAN when every requirement traces; a no-op (no false positives) when
  `docs/canonical/` is empty or absent.
- AC-003: the PR ceremony (SKILL_PR) documents the delta-merge step (after
  number allocation, so the canonical diff is in the PR and reviewable);
  existing flow intact (delta-stage1/2, spec-lint, docs-audit, ceremony suites
  green; strict audit CLEAN; index idempotent; check-state OK); the NB-1
  resync-re-render obligation SPEC-0034 promoted is resolved or explicitly
  re-tracked with rationale.

## Links
- RFC: delta-spec-lifecycle (docs/rfc/RFC-0011-delta-spec-lifecycle.md)
- Spec: spec-delta-stage-3 (docs/specs/SPEC-0038-spec-delta-stage-3.md)
- Builds on: spec-delta-stage-1 (SPEC-0034), spec-delta-stage-2 (SPEC-0037)
