---
id: spec-allocator-rewrite-all-trees
type: spec
number: 90
status: draft
ceremony_level: 3
links:
  requirement: docs/issues/CHANGE-0064-allocator-rewrite-all-trees.md
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — allocator-rewrite-all-trees

SPEC-FROZEN: true

## Ceremony level (RFC-0009)

`ceremony_level: 3` — MANDATORY, not discretionary. The sole code target,
`.aai/scripts/allocate-doc-number.mjs`, is listed verbatim in
`protected_paths_l3` (docs/ai/docs-audit.yaml) and in the WORKFLOW.md
"Protected surfaces" list (allocator). A spec whose scope touches a protected
surface MUST declare level 3. L3 consequences carried by this scope:

- Worktree gate (rule 8): REQUIRED semantics — an explicit `user_decision`
  must be RECORDED for the recommendation (see Isolation and review). The
  operator's blanket run-level authorization (2026-07-27) is the recorded
  decision; the orchestrator writes it with rationale. The decision, not the
  isolation mode, is what rule 8 mandates.
- Code review (rule 13): MANDATORY on the most capable tier. No waiver is
  auto-accepted; a waiver would be flagged to the operator (needs_llm).
- PR ceremony: adds an OPERATOR CHECKPOINT before merge — an explicit
  final-diff sign-off. This is the one stop in the otherwise-autonomous run.
- Evidence-before-claims and full independent validation are NOT pruned at any
  level; L3 scales artifact weight and review, never the evidence bar.

## Links
- Requirement / intake: docs/issues/CHANGE-0064-allocator-rewrite-all-trees.md
- Prior allocator specs (context, not modified): docs/specs/SPEC-0015 (RFC-0007
  parallel-safe doc numbering), docs/specs/SPEC-0047 (CHANGE-0035 origin
  reservation)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded

## Problem

`.aai/scripts/allocate-doc-number.mjs` renames `TYPE-DRAFT-<slug>.md` to
`TYPE-000N-<slug>.md` at merge time and rewrites in-repo references from the
old DRAFT basename to the new numbered basename. The rewrite pass
(`rewriteReferences`, lines 556-569) scans ONLY `GOVERNED_DIRS`
(`docs/rfc`, `docs/specs`, `docs/issues`, `docs/requirements`,
`docs/releases`) and only NON-recursively (a flat `readdirSync` per dir).

References that live in other committed-class trees — `docs/product/`,
`docs/ai/reviews/`, `docs/project-sessions/`, `docs/knowledge/`, and repo-root
`README.md` / `CHANGELOG.md` — keep pointing at the deleted DRAFT path.
External review bots flagged this on three consecutive PRs and the orchestrator
now hand-patches with `sed` before every ship ride. This spec extends the
rewrite scan to every committed-class markdown tree behind an explicit
allowlist, with an explicit exclusion list for runtime/archive trees, reusing
the existing substring matcher verbatim.

## Scope

In scope:
- `.aai/scripts/allocate-doc-number.mjs`:
  - Add a single explicit `REWRITE_TREES` constant (exported) enumerating the
    committed-class markdown roots to scan: the existing governed dirs plus
    `docs/product`, `docs/ai/reviews`, `docs/project-sessions`,
    `docs/knowledge`, and the repo-root files `README.md`, `CHANGELOG.md`.
  - Add a single explicit `EXCLUDED_TREES` constant (exported) enumerating
    runtime/archive prefixes that must NEVER be rewritten: `docs/archive`,
    `docs/_archive`, `docs/ai/reports`, `docs/ai/briefs`, `docs/ai/tdd`,
    `docs/ai/friction`, `docs/ai/archive`, `docs/ai/loop`, `docs/ai/locks`,
    `docs/ai/tests`, `.aai/cache`.
  - Replace the `rewriteReferences` tree iteration with a recursive markdown
    walk over `REWRITE_TREES` that skips any path under an `EXCLUDED_TREES`
    prefix. Directory entries are walked recursively for `*.md`; file entries
    (root README/CHANGELOG) are matched directly. Reuse the EXISTING inner
    match/replace verbatim (`content.includes(oldBase)` guard +
    `content.split(oldBase).join(newBase)` + write-only-if-changed).
  - Add a dry-run reporting path: when `--dry-run`, report the planned
    per-tree rewrite set (which files WOULD change per draft) and write
    nothing.
- Tests: extend `tests/skills/test-aai-doc-number-reservation.sh` (or a
  sibling suite stanza) with a fixture tree carrying references in each
  newly-scanned location (asserted rewritten) and in each excluded location
  (asserted byte-identical), an idempotent second run, and a dry-run
  no-write assertion.

Out of scope:
- Any change to number allocation, collision guards, the reservation protocol,
  INDEX regeneration, or naming conventions.
- Introducing a new or boundary-aware matcher. The existing substring matcher
  is reused verbatim (L3 conservative-design directive); its pre-existing
  substring-prefix property is recorded as a residual risk, not fixed here.
- Rewriting non-markdown files or trees not in the explicit allowlist.

## Design

### Constants (single source, exported for test assertion)

- `REWRITE_TREES`: array of repo-relative roots. Each entry is either a
  directory (walked recursively for `*.md`) or a specific file. Includes the
  five `GOVERNED_DIRS` roots (so existing behavior is preserved), plus
  `docs/product`, `docs/ai/reviews`, `docs/project-sessions`,
  `docs/knowledge`, `README.md`, `CHANGELOG.md`.
- `EXCLUDED_TREES`: array of repo-relative prefixes. A candidate file whose
  repo-relative path starts with any excluded prefix is skipped. This is
  defense-in-depth: the allowlist already excludes runtime trees by
  construction, but the explicit exclusion (a) documents the guarantee, (b)
  is the anchor for byte-identity tests, and (c) protects the one nesting
  case — `docs/ai/reviews` (scanned) sits under `docs/ai`, whose sibling
  runtime spools (`docs/ai/reports`, `docs/ai/briefs`, ...) must never be
  touched.

### Walker

A recursive markdown collector `collectRewriteFiles(root)` returns a
deduplicated list of repo-relative `*.md` paths across `REWRITE_TREES`,
skipping missing roots (degrade-and-report: `fs.existsSync` guard, matching
the existing pattern) and any path under an `EXCLUDED_TREES` prefix. File
entries that are themselves `*.md` are included directly.

### Rewrite pass

`rewriteReferences(root, oldBase, newBase, { dryRun } = {})`:
- iterate `collectRewriteFiles(root)`;
- for each file, read content; if `!content.includes(oldBase)` skip (unchanged
  guard);
- compute `updated = content.split(oldBase).join(newBase)` (VERBATIM existing
  matcher — no boundary logic added);
- if `updated !== content`: when not dryRun, `fs.writeFileSync`; always record
  the file under its owning tree for the return report;
- return a per-tree report structure so the dry-run path can print planned
  rewrites grouped by tree.

Ordering in `runAllocate` is unchanged: per draft, `stampNumber` ->
`moveFile` -> `rewriteReferences`. The just-renamed numbered file is in a
scanned tree, so a self-reference in the draft body is still rewritten
(behavior preserved).

### Dry-run

The existing `--dry-run` branch (currently prints only the rename plan and
returns before writing) additionally invokes `rewriteReferences` with
`{ dryRun: true }` for each planned rename and prints the per-tree planned
rewrite set. No file is written; every file stays byte-identical to its
pre-run state.

### Idempotence

After a real run, DRAFT basenames no longer exist on disk and no reference
contains the old DRAFT token, so a second `--all` run finds no drafts and is a
clean no-op (exit 0, "nothing to do"). The rewrite itself is idempotent: once
references point at the numbered basename, the DRAFT `oldBase` no longer
matches.

## Companion obligations (PLANNING step 3a)

Neither companion obligation applies:
- No bytes added to the prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`):
  only `.aai/scripts/allocate-doc-number.mjs` and test/doc files change. No
  prompt-diet ledger true-up required.
- No NEW `.aai/**` file: `allocate-doc-number.mjs` is MODIFIED, not added. No
  `.aai/system/PROFILES.yaml` classification entry required.

## Implementation strategy
- Strategy: tdd
- Rationale: this touches a PROTECTED core script (L3) where the failure mode
  is silent data corruption (over-eager rewrite mangling prose or an excluded
  runtime file mutated). Every AC-gating test must be observed RED before
  GREEN so the byte-identity and rewrite guarantees are proven, not
  rubber-stamped. Data-integrity + protected-surface is exactly the shape the
  playbook names for TDD; the codebase precedent (SPEC-0015 / SPEC-0047 on the
  same allocator) is TDD.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: L3 protected surface (allocator). Rule-8 REQUIRED
  semantics mandate a RECORDED user_decision for the recommendation; the
  change edits a shared transactional script whose behavior every ship ride
  depends on. Isolation is the conservative default for a protected-path edit.
- User decision: recorded by the orchestrator from the operator's blanket
  run-level authorization (2026-07-27). Work is already on the dedicated
  branch `feat/allocator-rewrite-all-trees` off `main`; the operator may
  record an inline override with that branch as the isolation, satisfying the
  rule-8 recorded-decision requirement either way.
- Base ref: main
- Inline review scope (if inline is recorded):
  .aai/scripts/allocate-doc-number.mjs,
  tests/skills/test-aai-doc-number-reservation.sh,
  docs/specs/SPEC-0090-spec-allocator-rewrite-all-trees.md,
  docs/issues/CHANGE-0064-allocator-rewrite-all-trees.md

## Acceptance Criteria Mapping

- Maps to: intake AC-001
  - Spec-AC-01: After a full-CLI allocation, every file under a `REWRITE_TREES`
    location that contained the exact old DRAFT basename token has it rewritten
    to the new numbered basename — verified for docs/product, docs/ai/reviews,
    docs/project-sessions, docs/knowledge, and repo-root README/CHANGELOG.
  - Verification: bash tests/skills/test-aai-doc-number-reservation.sh (new
    stanza); the numbered basename present and the DRAFT basename absent in
    each fixture file. Exit 0.
- Maps to: intake AC-001 (exclusion half)
  - Spec-AC-02: After the same allocation, every file under an `EXCLUDED_TREES`
    location is byte-identical to its pre-run content — including an excluded
    spool nested under a scanned root (docs/ai/reports beside docs/ai/reviews)
    and an archive tree (docs/archive).
  - Verification: byte/sha compare of each excluded fixture file before and
    after. Exit 0.
- Maps to: intake AC-002
  - Spec-AC-03: A second allocation run on the fixture is a no-op — no DRAFT
    remains and every rewrite-tree file is byte-identical between the
    first-run-after and second-run-after states.
  - Verification: second run exits 0 reporting nothing to do; sha compare of
    the tree unchanged.
- Maps to: intake AC-004
  - Spec-AC-04: `--dry-run` reports the planned per-tree rewrite set and writes
    nothing; every file (drafts and references, scanned and excluded) is
    byte-identical to the pre-run state.
  - Verification: dry-run output names the trees with planned rewrites; sha
    compare of the whole fixture unchanged; DRAFT files still present. Exit 0.
- Maps to: intake AC-001 (structural teeth)
  - Spec-AC-05: The rewrite scan is driven by a single exported `REWRITE_TREES`
    constant and a single exported `EXCLUDED_TREES` constant; the inner
    match/replace is the unchanged substring matcher (no new matcher).
  - Verification: a probe imports both constants and asserts membership
    (docs/product in REWRITE_TREES; docs/archive and docs/ai/reports in
    EXCLUDED_TREES); code review confirms the matcher body is unchanged.
- Maps to: intake AC-003
  - Spec-AC-06: The existing allocation/collision/guard suites pass unchanged.
  - Verification: bash tests/skills/test-aai-doc-numbering.sh and bash
    tests/skills/test-aai-doc-number-reservation.sh both exit 0.
- Maps to: intake AC-005
  - Spec-AC-07: No regression — the targeted suites are green locally and the
    full framework runs on PR CI.
  - Verification: targeted suites exit 0 locally; PR CI full run is the
    authoritative gate.

## Constitution deviations

None.

## Seam analysis

- Seam S1 (allocator rewrite pass -> committed-class docs consumed elsewhere):
  the rewrite PRODUCES corrected references that other tooling (link checkers,
  docs-audit orphan detection) and humans READ across product docs, review
  reports, session notes, knowledge docs, and root README/CHANGELOG. Covered
  end-to-end by the Spec-AC-01/Spec-AC-02 integration test: produce via the
  FULL allocator CLI, then assert on the consuming doc (rewritten) AND an
  excluded doc (byte-identical) — one fixture crossing the boundary, not two
  mocked units.
- Seam S2 (rename tree vs rewrite tree overlap): the just-renamed numbered
  file lives in a scanned governed dir, so a self-reference in the draft body
  must be rewritten after the rename. Covered by a fixture whose DRAFT body
  self-references its own basename, asserted rewritten after full-CLI
  allocation.

Residual risks (no automated coverage / accepted):
- RR-1 (substring-prefix over-rewrite): reusing the verbatim substring matcher
  means a DRAFT slug that is a strict prefix of another same-type DRAFT slug
  in the SAME batch (e.g. `RFC-DRAFT-foo` vs `RFC-DRAFT-foo-bar`) could
  over-rewrite. Pre-existing property of the allocator; fixing it needs a new
  boundary-aware matcher, explicitly out of scope per the L3 conservative
  directive. Realistic exposure is low (two same-prefix drafts merged in one
  batch); recorded, not fixed.
- RR-2 (rescan cost): the rewrite scan runs once per draft, so a batch of N
  drafts walks the tree N times — O(N x files). Acceptable at docs-repo scale;
  not optimized to keep the change minimal on a protected surface.

## Acceptance Criteria Status

| Spec-AC    | Description                                                              | Status  | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | References in each newly-scanned tree rewritten to the numbered path     | done | TEST-101/TEST-102 green; docs/ai/tdd/green-20260726T232940Z-TEST-101.log, docs/ai/tdd/green-20260726T232940Z-TEST-102.log | — | — |
| Spec-AC-02 | Excluded trees byte-identical after allocation                          | done | TEST-103 green; docs/ai/tdd/green-20260726T232940Z-TEST-103.log | — | — |
| Spec-AC-03 | Second run is a no-op (idempotence); tree byte-identical                | done | TEST-104 green; docs/ai/tdd/green-20260726T232940Z-TEST-104.log | — | — |
| Spec-AC-04 | Dry-run reports planned per-tree rewrites and writes nothing            | done | TEST-105 green; docs/ai/tdd/green-20260726T232940Z-TEST-105.log | — | — |
| Spec-AC-05 | Single exported REWRITE_TREES plus EXCLUDED_TREES; verbatim matcher     | done | TEST-106 green; docs/ai/tdd/green-20260726T232940Z-TEST-106.log | — | — |
| Spec-AC-06 | Existing allocation/collision/guard suites pass unchanged              | done | TEST-107 green; docs/ai/tdd/green-20260726T233122Z-doc-numbering-regression.log, docs/ai/tdd/green-20260726T233122Z-reservation-reaped.log | — | — |
| Spec-AC-07 | No regression — targeted suites green locally; PR CI full run           | deferred | TEST-108 green locally; docs/ai/tdd/green-20260726T233122Z-reservation-fullsuite.log | 2026-08-10 | Local half (targeted suites) is green; PR CI full framework is the authoritative gate and has not run yet (not yet pushed/PR'd) — defer to done once CI is green on the PR. |

## Implementation plan

- Components/modules affected: `.aai/scripts/allocate-doc-number.mjs` only
  (exported constants, new recursive walker, reworked `rewriteReferences` with
  a dry-run mode, dry-run branch wiring in `runAllocate`).
- Data flows: DRAFT rename plan (existing) -> per-plan `rewriteReferences` over
  the widened tree set -> per-tree report (new; printed in dry-run, discarded
  in the write path). No STATE writes, no new JSONL, no INDEX changes.
- Edge cases: missing roots (skip via existsSync); excluded subtree nested
  under a scanned root (docs/ai/reports under docs/ai); file entries in
  REWRITE_TREES (README/CHANGELOG) matched directly; a file with no DRAFT
  reference (unchanged guard, not written); idempotent second run (no DRAFT
  left); self-reference in the renamed doc.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                                | Description                                                                                          | Status  |
|----------|------------|-------------|-----------------------------------------------------|------------------------------------------------------------------------------------------------------|---------|
| TEST-101 | Spec-AC-01 | integration | tests/skills/test-aai-doc-number-reservation.sh     | Full-CLI allocation rewrites the DRAFT ref to the numbered basename in product, reviews, sessions, knowledge, root README and CHANGELOG | green |
| TEST-102 | Spec-AC-01 | integration | tests/skills/test-aai-doc-number-reservation.sh     | Self-reference in the renamed draft body is rewritten (seam S2)                                       | green |
| TEST-103 | Spec-AC-02 | integration | tests/skills/test-aai-doc-number-reservation.sh     | Excluded fixture files (docs/archive, docs/ai/reports beside docs/ai/reviews) are byte-identical after allocation | green |
| TEST-104 | Spec-AC-03 | integration | tests/skills/test-aai-doc-number-reservation.sh     | Second allocation run is a no-op; rewrite-tree files sha-unchanged between run1-after and run2-after   | green |
| TEST-105 | Spec-AC-04 | integration | tests/skills/test-aai-doc-number-reservation.sh     | Dry-run reports planned per-tree rewrites and leaves every fixture file byte-identical; DRAFT still present | green |
| TEST-106 | Spec-AC-05 | unit        | tests/skills/test-aai-doc-number-reservation.sh     | Probe imports REWRITE_TREES and EXCLUDED_TREES and asserts membership (product in rewrite; archive and ai/reports in excluded) | green |
| TEST-107 | Spec-AC-06 | integration | tests/skills/test-aai-doc-numbering.sh (unchanged run) | Existing doc-numbering + reservation suites pass unchanged (regression)                            | green |
| TEST-108 | Spec-AC-07 | integration | tests/skills/test-aai-doc-number-reservation.sh     | Targeted allocator suites green locally; PR CI full framework is the authoritative gate               | green |

RED-proof obligation: TEST-101 through TEST-106 must each be observed FAILING
against the unmodified allocator before GREEN counts. TEST-107 is a regression
guard (passes today; its value is staying green) — it cannot be observed RED by
design and is exempt from the RED-proof requirement (it proves no new behavior).

RED-proof outcome (implementation note): TEST-101, TEST-105, and TEST-106 were
each observed FAILING against the unmodified allocator (product_red evidence:
docs/ai/tdd/red-20260726T232844Z-TEST-101.log,
docs/ai/tdd/red-20260726T232844Z-TEST-105.log,
docs/ai/tdd/red-20260726T232844Z-TEST-106.log — each accepted by
`tdd-evidence-check.mjs`). TEST-102, TEST-103, and TEST-104 were each observed
PASSING against the unmodified allocator: their fixtures assert a
NEGATIVE/preservation invariant (a self-reference inside a governed dir
already worked, because governed dirs were already flat-scanned; docs/archive
and docs/ai/reports were never scanned by the old allocator at all, so
byte-identity and idempotence on those trees already held BY OMISSION). By
the same rationale as the TEST-107 exemption (proving no regression, not new
behavior), TEST-102, TEST-103, and TEST-104 are treated as RED-proof-exempt;
the baseline-pass observation is recorded at
docs/ai/tdd/baseline-pass-20260726T232844Z-TEST-102.log,
docs/ai/tdd/baseline-pass-20260726T232844Z-TEST-103.log, and
docs/ai/tdd/baseline-pass-20260726T232844Z-TEST-104.log. All eight tests are
GREEN post-implementation: docs/ai/tdd/green-20260726T232940Z-TEST-10{1..6}.log,
docs/ai/tdd/green-20260726T233122Z-reservation-fullsuite.log,
docs/ai/tdd/green-20260726T233122Z-doc-numbering-regression.log,
docs/ai/tdd/green-20260726T233122Z-reservation-reaped.log.

## Verification
- Commands:
  - bash tests/skills/test-aai-doc-number-reservation.sh
  - bash tests/skills/test-aai-doc-numbering.sh
  - node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0090-spec-allocator-rewrite-all-trees.md
  - node .aai/scripts/docs-audit.mjs --check
- Evidence artifacts: suite stdout (exit 0), RED/GREEN logs per TEST-101..106.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status AND
  PR CI full framework green.

## Evidence contract
Per artifact record: ref_id (allocator-rewrite-all-trees); Spec-AC and
TEST-xxx links; command or review scope; exit code or review verdict; evidence
path; commit SHA or diff range when available.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
