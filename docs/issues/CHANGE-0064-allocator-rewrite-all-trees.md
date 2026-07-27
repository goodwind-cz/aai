---
id: allocator-rewrite-all-trees
number: 64
type: change
status: done
links:
  pr:
    - 164
  commits:
    - 987f33acdf2fc5c2a1e2c241e3aced84f780a1cb
---

# Change — Allocator rewrites DRAFT references in all committed-class trees

## Summary
- `allocate-doc-number.mjs` renames `TYPE-DRAFT-<slug>.md` to
  `TYPE-000N-<slug>.md` and rewrites references — but only in the trees it
  currently scans. References in `docs/product/`, `docs/ai/reviews/`, and
  other committed-class docs keep pointing at the deleted DRAFT path, which
  external review bots flagged on three consecutive PRs (#158 x3, #161 x3,
  #163 candidates) and the orchestrator now patches by hand with sed before
  every PR. Extend the allocator's reference-rewrite pass to every
  committed-class tree, with an explicit exclusion list for runtime/archive
  trees.

## Motivation / Business Value
- Removes a whole recurring class of bot findings and a manual sed step from
  every ship ride (observed 10+ hand-fixes across 4 PRs on 2026-07-26).
- Broken links from product docs and review reports to specs undermine the
  stakeholder-facing artifact chain the factory now produces.

## Scope
- In scope:
  - .aai/scripts/allocate-doc-number.mjs: extend the rewrite scan set to
    committed-class markdown trees (at minimum: docs/product/,
    docs/ai/reviews/, docs/project-sessions/, docs/knowledge/, README/
    CHANGELOG at repo root) behind a single explicit list constant;
    exclusions stay excluded (docs/_archive/, docs/archive/, docs/ai/
    runtime JSONL/reports spool, .aai/cache/).
  - Idempotence and byte-safety: rewrite only exact path/id token matches
    (existing matching semantics reused), no partial-token rewrites;
    dry-run flag reports planned rewrites per tree.
  - Tests: fixture tree with references in each newly-scanned location
    (rewritten) and in each excluded location (untouched); idempotent
    second run; collision/guard behavior unchanged.
- Out of scope: any change to number allocation, collision guards, INDEX
  regeneration, or naming conventions.

## Affected Area
- .aai/scripts/allocate-doc-number.mjs (PROTECTED SURFACE — L3),
  tests/skills/test-aai-doc-number-reservation.sh (or sibling suite),
  docs.

## Desired Behavior (To-Be)
- After allocation, no committed-class file references the DRAFT path; a
  second run rewrites nothing; excluded trees byte-identical.

## Acceptance Criteria
- AC-001: fixture references in each newly-scanned tree are rewritten to the
  numbered path; excluded trees stay byte-identical (suite-verified).
- AC-002: second allocator run is a no-op on the fixture (idempotence).
- AC-003: existing allocation/collision/guard suites pass unchanged.
- AC-004: dry-run reports the planned rewrite set without writing.
- AC-005: no regression — targeted suites green locally; full run on PR CI.

## Verification
- bash tests/skills/test-aai-doc-number-reservation.sh (+ new stanzas)
- PR CI full framework.

## Constraints / Risks
- No secrets referenced (secrets preflight skipped).
- CEREMONY LEVEL 3: allocate-doc-number.mjs is on protected_paths_l3.
  Consequences honored: worktree gate needs a RECORDED decision (operator
  blanket run-level authorization 2026-07-27 recorded as the decision, with
  inline rationale), code review MANDATORY on the most capable tier, and the
  PR ceremony adds an OPERATOR CHECKPOINT before merge (explicit final-diff
  sign-off — the one stop in the autonomous run).
- Risk: over-eager rewrite corrupting prose — mitigated by exact-token
  matching reuse + byte-identity assertions on excluded trees.

## Notes
- Evidence of the recurring class: PR #158/#161 bot threads (DRAFT refs in
  product doc + review reports), orchestrator sed patches before #159/#161/
  #163. Autopilot intake: metrics question skipped, human_time_minutes null.
