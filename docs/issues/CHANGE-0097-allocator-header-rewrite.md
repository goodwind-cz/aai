---
id: allocator-header-rewrite
number: 97
type: change
status: done
user_visible: false
links:
  pr:
    - 200
  commits:
    - ffec0e68ad290684d87b84efea8ca301d4cb40f0
---

# Change — Allocator rewrites DRAFT references in SCRIPT and TEST trees

## Summary
- CHANGE-0064 extended `allocate-doc-number.mjs`'s reference-rewrite pass to
  every committed-class MARKDOWN tree, but SCRIPT and TEST sources were left
  out. When a `TYPE-DRAFT-<slug>` doc is numbered, header comments and fixture
  path constants inside `tests/**/*.{sh,ps1,mjs}` and
  `.aai/scripts/**/*.{mjs,sh,ps1}` still point at the deleted DRAFT basename,
  so every ride does a manual sed sweep (error-prone; stale refs linger). This
  extends the SAME verbatim rewrite pass to those source trees, with an
  explicit exclusion list for the meta-tests that TEACH the DRAFT convention.

## Motivation / Business Value
- Removes the recurring manual "allocator rewrite of script/test headers"
  sweep flagged in the 2026-07-26 audit session — the last dangling-DRAFT-ref
  class after CHANGE-0064 closed the markdown trees.
- Keeps the test/script header docstrings' "Covers TEST-... from
  docs/specs/SPEC-...md" pointers pointing at files that actually exist.

## Scope
- In scope:
  - .aai/scripts/allocate-doc-number.mjs: add REWRITE_CODE_TREES
    (tests, .aai/scripts) + REWRITE_CODE_EXTS (.sh, .ps1, .mjs) +
    EXCLUDED_CODE_PATHS; the rewrite pass now unions markdown files with
    source files, reusing the existing verbatim-substring matcher and
    write-only-if-changed idempotence.
  - One-time backfill of the stale refs already in-tree (already-numbered
    docs), so the pointer invariant starts clean.
  - Tests: fixture DRAFT + source consumers rewritten; excluded meta-test and
    fixtures tree byte-identical; non-source extension untouched; idempotent
    unrelated second allocation; dry-run plans the code-tree rewrites.
- Out of scope: any change to number allocation, collision guards, INDEX
  regeneration, naming; rewriting the historical prompt-diet byte-accounting
  ledger's frozen rationale entries.

## Affected Area
- .aai/scripts/allocate-doc-number.mjs, tests/skills/test-aai-doc-numbering.sh,
  plus one-time backfilled comment refs across tests/skills/** and
  .aai/scripts/**.

## Desired Behavior (To-Be)
- After allocation, no committed source file references a now-numbered doc's
  DRAFT basename; a second unrelated allocation rewrites nothing; the
  convention-teaching meta-tests, the fixtures tree, and non-source files stay
  byte-identical.

## Acceptance Criteria
- AC-001: numbering a draft rewrites its DRAFT basename to the numbered form
  in tests/**/*.{sh,ps1,mjs} and .aai/scripts/**/*.{mjs,sh,ps1}
  (suite-verified).
- AC-002: the convention-teaching meta-test suites, the tests/fixtures tree,
  and the allocator's own source stay byte-identical (exclusion list).
- AC-003: non-source file extensions are never touched (byte-safety).
- AC-004: a second, unrelated allocation does not re-touch an
  already-rewritten source file (idempotence).
- AC-005: dry-run reports the planned code-tree rewrites without writing.
- AC-006: existing allocator, doc-numbering, and reservation suites pass
  unchanged.

## Verification
- bash tests/skills/test-aai-doc-numbering.sh (TEST-019 added)
- bash tests/skills/test-aai-doc-number-reservation.sh
- node .aai/scripts/docs-audit.mjs --check --strict --no-event

## Constraints / Risks
- No secrets referenced (secrets preflight skipped).
- CEREMONY LEVEL 3 (reclassified from the L2 intake): the sole code target
  `.aai/scripts/allocate-doc-number.mjs` is on `protected_paths_l3`
  (docs/ai/docs-audit.yaml), so the scope MUST declare level 3 — same basis as
  the predecessor CHANGE-0064/SPEC-0090. Authorized by the frozen
  `ceremony_level: 3` spec docs/specs/SPEC-0107-spec-allocator-header-rewrite.md.
  Consequences: mandatory code review on the most capable tier + an operator
  PR checkpoint before merge.
- Residual risk: a future draft slug colliding verbatim with a DRAFT-fixture
  string inside a NON-excluded suite would be rewritten — mitigated by
  excluding every DRAFT-fixture-heavy meta-test and by exact-token matching
  (same residual accepted by CHANGE-0064).

## Notes
- Follow-up recorded in the 2026-07-26 audit session ("allocator rewrite of
  script/test headers — manual sweep each ride"), the remaining gap after
  CHANGE-0064.
