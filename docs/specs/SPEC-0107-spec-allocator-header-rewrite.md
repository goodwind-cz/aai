---
id: spec-allocator-header-rewrite
type: spec
number: 107
status: done
ceremony_level: 3
links:
  requirement: docs/issues/CHANGE-0097-allocator-header-rewrite.md
  rfc: null
  pr:
    - 200
  commits:
    - ffec0e68ad290684d87b84efea8ca301d4cb40f0
---

# Implementation Spec — allocator-header-rewrite

SPEC-FROZEN: true

## Ceremony level (RFC-0009)

`ceremony_level: 3` — MANDATORY, not discretionary. The sole code target,
`.aai/scripts/allocate-doc-number.mjs`, is listed verbatim in
`protected_paths_l3` (docs/ai/docs-audit.yaml) and in the WORKFLOW.md
"Protected surfaces" list (allocator). A scope that touches a protected
surface MUST declare level 3 — the same basis as the predecessor SPEC-0090
(CHANGE-0064). The intake was drafted as an L2 change; this spec RECLASSIFIES
it to L3 because the target file is protected. L3 consequences carried:

- Worktree gate (rule 8): REQUIRED semantics — work is on the dedicated
  isolated worktree branch off main; the operator's blanket run-level
  authorization (2026-07-27) is the recorded decision.
- Code review (rule 13): MANDATORY on the most capable tier. No auto-waiver.
- PR ceremony: adds an OPERATOR CHECKPOINT before merge (explicit final-diff
  sign-off).
- Evidence-before-claims and full independent validation are NOT pruned; L3
  scales artifact weight and review, never the evidence bar.

## Links
- Requirement / intake: docs/issues/CHANGE-0097-allocator-header-rewrite.md
- Prior allocator specs (context, not modified): docs/specs/SPEC-0015 (RFC-0007
  parallel-safe doc numbering), docs/specs/SPEC-0047 (CHANGE-0035 origin
  reservation), docs/specs/SPEC-0090 (CHANGE-0064 rewrite-all-markdown-trees —
  the direct predecessor this extends to code trees)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded

## Problem

`.aai/scripts/allocate-doc-number.mjs` renames `TYPE-DRAFT-<slug>.md` to
`TYPE-000N-<slug>.md` at merge time and rewrites in-repo references from the
old DRAFT basename to the new numbered basename. SPEC-0090 (CHANGE-0064)
extended that rewrite pass to every committed-class MARKDOWN tree, but SCRIPT
and TEST sources were left out. Header comments and fixture path constants in
`tests/**/*.{sh,ps1,mjs}` and `.aai/scripts/**/*.{mjs,sh,ps1}` keep pointing at
the deleted DRAFT basename after numbering, so each ride does a manual `sed`
sweep (error-prone; stale refs linger — the "allocator rewrite of script/test
headers" follow-up recorded in the 2026-07-26 audit session).

## Scope

In scope:
- `.aai/scripts/allocate-doc-number.mjs`:
  - Add three exported constants: `REWRITE_CODE_TREES` (`tests`, `.aai/scripts`),
    `REWRITE_CODE_EXTS` (`.sh`, `.ps1`, `.mjs`), and `EXCLUDED_CODE_PATHS`
    (the code-pass mirror of `EXCLUDED_TREES`).
  - Add a recursive source-file walker `collectRewriteCodeFiles(root)` (with an
    `isExcludedCodePath` prefix guard and symlink rejection, mirroring the
    markdown `collectRewriteFiles`/`walkMarkdown` pair).
  - The rewrite pass `rewriteReferences` now iterates the UNION of markdown
    files and source files, reusing the EXISTING verbatim substring matcher
    (`content.includes(oldBase)` guard + `content.split(oldBase).join(newBase)`
    + write-only-if-changed). `ownerTreeFor` groups by markdown OR code tree so
    the dry-run report covers both.
  - No change to number allocation, collision guards, reservation, or INDEX.
- One-time backfill of the stale refs already in-tree (already-numbered docs),
  so the pointer invariant starts clean.
- Tests: extend `tests/skills/test-aai-doc-numbering.sh` (TEST-019).

Out of scope:
- Any change to number allocation, collision guards, the reservation protocol,
  INDEX regeneration, or naming conventions.
- Introducing a new or boundary-aware matcher (L3 conservative-design
  directive); the existing substring matcher is reused verbatim, its
  substring-prefix property recorded as a residual risk (RR-1, inherited).
- Rewriting the historical prompt-diet byte-accounting ledger's frozen
  rationale entries (excluded); rewriting non-source file extensions.

## Design

### Constants (single source, exported for test assertion)
- `REWRITE_CODE_TREES`: repo-relative roots walked recursively for source
  files — `tests`, `.aai/scripts`.
- `REWRITE_CODE_EXTS`: source extensions the pass touches — `.sh`, `.ps1`,
  `.mjs`. Data files and other extensions are never read or written
  (byte-safety).
- `EXCLUDED_CODE_PATHS`: files/dirs that MUST stay byte-identical because they
  TEACH the DRAFT convention or assert on DRAFT literals as test data — the
  allocator's own source, its two suites (doc-numbering, reservation), the
  spec-lint / docs-audit / state suites, the shared `tests/fixtures` tree, and
  the frozen prompt-diet byte-accounting ledger. Prefix match (exact file or a
  path-segment boundary), identical semantics to `isExcludedTree`.

### Walker
`collectRewriteCodeFiles(root)` returns a deduplicated list of repo-relative
source paths across `REWRITE_CODE_TREES`, skipping missing roots
(`fs.existsSync` guard), any path under an `EXCLUDED_CODE_PATHS` prefix, and
symlinked roots (rejected with a WARNING, never followed). Dirents reflect
lstat, so a symlinked entry is neither file nor dir and is skipped.

### Rewrite pass
`rewriteReferences` iterates `[...collectRewriteFiles(root),
...collectRewriteCodeFiles(root)]`; the inner match/replace body is the
UNCHANGED substring matcher. Ordering in `runAllocate` is unchanged
(`stampNumber` -> `moveFile` -> `rewriteReferences`). Dry-run invokes the same
pass with `{ dryRun: true }` and prints the per-tree planned set.

### Idempotence and byte-safety
After a real run the DRAFT basename no longer exists, so a subsequent
unrelated allocation finds no matching token in an already-rewritten file and
writes nothing (the `content.includes` guard). Only `REWRITE_CODE_EXTS`
extensions are ever touched; excluded paths and non-source files stay
byte-identical.

## Companion obligations (PLANNING step 3a)
Neither companion obligation applies:
- No bytes added to the prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`):
  only `.aai/scripts/allocate-doc-number.mjs`, tests, and docs change. No
  prompt-diet ledger true-up required.
- No NEW `.aai/**` file: `allocate-doc-number.mjs` is MODIFIED, not added. No
  `.aai/system/PROFILES.yaml` classification entry required.

## Implementation strategy
- Strategy: tdd
- Rationale: touches a PROTECTED core script (L3) where the failure mode is
  silent data corruption (over-eager rewrite mangling a source file or an
  excluded meta-test mutated). The AC-gating test is observed RED before GREEN
  so the rewrite/exclusion/byte-safety guarantees are proven; the codebase
  precedent (SPEC-0015 / SPEC-0047 / SPEC-0090 on the same allocator) is TDD.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: L3 protected surface (allocator). Rule-8 REQUIRED
  semantics mandate a RECORDED user_decision; the change edits a shared
  transactional script every ride depends on.
- User decision: recorded from the operator's blanket run-level authorization
  (2026-07-27). Work is on the dedicated isolated worktree branch off main.
- Base ref: main
- Inline review scope (if inline is recorded):
  .aai/scripts/allocate-doc-number.mjs,
  tests/skills/test-aai-doc-numbering.sh,
  docs/specs/SPEC-0107-spec-allocator-header-rewrite.md,
  docs/issues/CHANGE-0097-allocator-header-rewrite.md

## Acceptance Criteria Mapping
- Maps to: intake AC-001
  - Spec-AC-01: numbering a draft rewrites its DRAFT basename to the numbered
    form in tests/**/*.{sh,ps1,mjs} and .aai/scripts/**/*.{mjs,sh,ps1}.
  - Verification: bash tests/skills/test-aai-doc-numbering.sh (TEST-019). Exit 0.
- Maps to: intake AC-002
  - Spec-AC-02: the convention-teaching meta-tests, the tests/fixtures tree,
    and the allocator's own source stay byte-identical (exclusion list).
  - Verification: TEST-019 asserts the excluded fixtures unchanged. Exit 0.
- Maps to: intake AC-003
  - Spec-AC-03: non-source file extensions are never touched (byte-safety).
  - Verification: TEST-019 asserts a .txt fixture unchanged. Exit 0.
- Maps to: intake AC-004
  - Spec-AC-04: a second, unrelated allocation does not re-touch an
    already-rewritten source file (idempotence).
  - Verification: TEST-019 sha-compares the consumer across a second
    allocation. Exit 0.
- Maps to: intake AC-005
  - Spec-AC-05: dry-run reports the planned code-tree rewrites and writes
    nothing.
  - Verification: TEST-019 asserts the dry-run log names the consumer files and
    the file is unchanged. Exit 0.
- Maps to: intake AC-006
  - Spec-AC-06: existing allocator, doc-numbering, and reservation suites pass
    unchanged.
  - Verification: bash tests/skills/test-aai-doc-numbering.sh and bash
    tests/skills/test-aai-doc-number-reservation.sh both exit 0.

## Constitution deviations
None.

## Seam analysis
- Seam S1 (allocator rewrite pass -> source files consumed by test/CI tooling):
  the rewrite PRODUCES corrected DRAFT->numbered references that test runners
  and readers consume across tests/ and .aai/scripts/. Covered end-to-end by
  TEST-019: number a draft via the FULL allocator CLI, then assert on the
  consuming source file (rewritten) AND an excluded meta-test (byte-identical)
  — one fixture crossing the boundary, not mocked units.
- Seam S2 (code tree overlapping the allocator's own source): `.aai/scripts`
  is a rewrite root AND contains the allocator itself plus its libs; the
  EXCLUDED_CODE_PATHS entry keeps the allocator source byte-identical while the
  rest of the tree is rewritten. Covered by the exclusion assertion in TEST-019.

Residual risks (accepted):
- RR-1 (substring-prefix over-rewrite): inherited verbatim from the reused
  matcher (SPEC-0090 RR-1). A future draft slug that is a strict prefix of a
  fixture slug in a NON-excluded suite could over-rewrite; mitigated by
  excluding every DRAFT-fixture-heavy meta-test. Recorded, not fixed (L3
  conservative directive).
- RR-2 (rescan cost): the code-tree walk runs once per draft in a batch —
  O(N x files) over tests/ and .aai/scripts/. Acceptable at repo scale; not
  optimized to keep the change minimal on a protected surface.

## Acceptance Criteria Status

| Spec-AC    | Description                                                          | Status | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | DRAFT basename rewritten to numbered form in script and test trees  | done | TEST-019 green; docs/ai/tdd/allocator-header-rewrite-RED.log, docs/ai/tdd/allocator-header-rewrite-GREEN.log | — | — |
| Spec-AC-02 | Meta-tests, tests/fixtures, and allocator source stay byte-identical | done | TEST-019 exclusion assertions green; docs/ai/tdd/allocator-header-rewrite-GREEN.log | — | — |
| Spec-AC-03 | Non-source file extensions never touched (byte-safety)              | done | TEST-019 txt byte-safety assertion green; docs/ai/tdd/allocator-header-rewrite-GREEN.log | — | — |
| Spec-AC-04 | Second unrelated allocation does not re-touch a rewritten file      | done | TEST-019 sha-compare green; docs/ai/tdd/allocator-header-rewrite-GREEN.log | — | — |
| Spec-AC-05 | Dry-run reports planned code-tree rewrites and writes nothing       | done | TEST-019 dry-run assertion green; docs/ai/tdd/allocator-header-rewrite-GREEN.log | — | — |
| Spec-AC-06 | Existing allocator/doc-numbering/reservation suites pass unchanged  | done | doc-numbering + reservation suites exit 0; docs/ai/tdd/allocator-header-rewrite-GREEN.log | — | — |

## Implementation plan
- Components/modules affected: `.aai/scripts/allocate-doc-number.mjs` only
  (three exported constants, `isExcludedCodePath`, `walkCode`,
  `collectRewriteCodeFiles`, union in `rewriteReferences`, code-tree awareness
  in `ownerTreeFor`).
- Data flows: DRAFT rename plan (existing) -> per-plan `rewriteReferences` over
  markdown UNION source trees -> per-tree report (printed in dry-run). No STATE
  writes, no new JSONL.
- Edge cases: missing roots (existsSync skip); symlinked root/entry (rejected /
  skipped); excluded meta-test under a scanned root; non-source extension
  (skipped); file with no DRAFT token (unchanged guard); idempotent second run.

## Test Plan

Test ID / Spec-AC / Type / File / Description / Status:

- TEST-019 / Spec-AC-01..05 / integration / tests/skills/test-aai-doc-numbering.sh / Full-CLI allocation rewrites the DRAFT basename in .sh/.mjs/.ps1 consumers; excluded meta-test + tests/fixtures + allocator source + non-source .txt stay byte-identical; dry-run plans without writing; a second unrelated allocation is idempotent / green
- TEST-004..018 / Spec-AC-06 / integration / tests/skills/test-aai-doc-numbering.sh + test-aai-doc-number-reservation.sh / Existing allocator/doc-numbering/reservation behavior unchanged (regression) / green

RED-proof obligation: TEST-019 was observed FAILING against the unmodified
allocator (docs/ai/tdd/allocator-header-rewrite-RED.log — the dry-run planned
set omits the code-tree consumers) before GREEN
(docs/ai/tdd/allocator-header-rewrite-GREEN.log). The regression stanzas
(TEST-004..018) prove no new behavior and are RED-proof-exempt.

## Verification
- Commands:
  - bash tests/skills/test-aai-doc-numbering.sh
  - bash tests/skills/test-aai-doc-number-reservation.sh
  - node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0107-spec-allocator-header-rewrite.md
  - node .aai/scripts/docs-audit.mjs --check --strict --no-event
- Evidence artifacts: suite stdout (exit 0), RED/GREEN logs for TEST-019.
- PASS criteria: all TEST green AND all Spec-AC terminal AND PR CI full
  framework green.

## Evidence contract
Per artifact record: ref_id (allocator-header-rewrite); Spec-AC and TEST links;
command or review scope; exit code or review verdict; evidence path; commit SHA
or diff range when available.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
