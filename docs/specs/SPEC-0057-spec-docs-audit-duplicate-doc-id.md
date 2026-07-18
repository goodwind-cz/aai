---
id: spec-docs-audit-duplicate-doc-id
type: spec
number: 57
status: draft
ceremony_level: 2
links:
  requirement: ISSUE-0014
  rfc: null
  pr: []
  commits: []
---

# Spec: docs-audit detects duplicate frontmatter doc-ids (governance-integrity backstop)

SPEC-FROZEN: true

Reserved display number (cross-branch collision check, RFC-0007): SPEC-0057.
Verified 2026-07-18 free across local `docs/specs/` + every `refs/heads`/
`refs/remotes` tree (`git ls-tree` scan of all remote branches + `git log --all`
found no `SPEC-0057*`; highest SPEC allocated anywhere is SPEC-0056). The
sequential integer is minted/reserved at merge by `allocate-doc-number.mjs`; this
file stays `SPEC-DRAFT-<slug>.md` with `number: null` in-branch. The slug id is
`spec-`-prefixed (`spec-docs-audit-duplicate-doc-id`) so it can NEVER collide
with the intake's id (`docs-audit-duplicate-doc-id`) — i.e. this spec is itself
compliant with the very rule it detects.

Ceremony justification (advisory, L2 default): the CODE change is small and
additive (one exported grouping function + one digest section + one term added to
the verdict tally), but it modifies the trusted governance AUDIT ENGINE
(`.aai/scripts/lib/docs-audit-core.mjs`) and has a real repo-wide observable
effect (it flips the live repo's docs-audit digest verdict CLEAN -> NEEDS-TRIAGE
by correctly surfacing 3 pre-existing collisions — see Problem / Seam analysis)
plus a multi-consumer seam (`triage.sh`, CI). That blast radius warrants the full
L2 pipeline (independent Validation), not the L1 lean lane. `docs-audit-core.mjs`
is NOT in `protected_paths_l3` (verified against docs/ai/docs-audit.yaml — the L3
list is the state engine, allocator, guards, WORKFLOW.md, CONSTITUTION.md), and
prior scopes (SPEC-0011, SPEC-0039) touched this engine at L2, so L2 is
precedent-consistent. Not L3.

## Links
- Requirement: docs/issues/ISSUE-0014-docs-audit-duplicate-doc-id.md
- Origin finding: docs/ai/decisions.jsonl (SPEC-0056/ISSUE-0013 spec-id collision
  process_finding, 2026-07-18) — `close-work-item.mjs` caught the collision late;
  this makes the AUDIT catch it early.
- Related engine surfaces (mirror, do not fork): the closeout-candidate post-pass
  `closeoutCandidatesFor` (docs-audit-core.mjs ~L1034) and the
  missing-close-telemetry / drift digest sections (docs-audit.mjs ~L306/~L225).
- Technology contract: docs/TECHNOLOGY.md

## Problem

Doc identity in the audit is the EFFECTIVE id `id = fm.id ?? ids.primary`
(docs-audit-core.mjs L683). Nothing asserts effective ids are unique across the
scanned set. The id-keyed index `byId` in `closeoutCandidatesFor`
(docs-audit-core.mjs ~L1035-1036) is a last-writer-wins `Map`
(`byId.set(d.id, d)`): a second doc with the same effective id silently
overwrites the first, so per-id resolution operates on whichever doc won the map
and the other becomes invisible to id-keyed checks. The audit — the trusted
"state of the docs" oracle — reports CLEAN while a governance-integrity collision
is live. The motivating instance (2026-07-18): a SPEC created WITHOUT the `spec-`
prefix shared its intake's id; docs-audit stayed CLEAN and only
`close-work-item.mjs` (fail-closed on the ambiguous id) surfaced it, late.

### Verified reality on THIS repo (supersedes the intake's clean-repo assumption)
ISSUE-0014 assumed "the real repo reports zero (all ids currently unique after
the SPEC-0056 fix)." Verified against the live tree on 2026-07-18: that is FALSE.
The SPEC-0056 fix corrected exactly ONE collision. THREE legacy SPEC<->intake
slug collisions remain, each a spec authored before the `spec-` prefix
convention sharing its slug with its originating issue:

| Shared effective id | Carrying docs |
|---|---|
| `prompt-diet-byte-budget-true-up` | docs/specs/SPEC-0048-prompt-diet-byte-budget-true-up.md + docs/issues/DEBT-0002-prompt-diet-byte-budget-true-up.md |
| `secrets-preflight-env-multiline` | docs/specs/SPEC-0049-secrets-preflight-env-multiline.md + docs/issues/ISSUE-0010-secrets-preflight-env-multiline.md |
| `spec-lint-duplicate-ac-id` | docs/specs/SPEC-0051-spec-lint-duplicate-ac-id.md + docs/issues/ISSUE-0011-spec-lint-duplicate-ac-id.md |

These are TRUE positives by the feature's own definition (a spec sharing an id
with its intake is precisely the bug ISSUE-0014 targets). Therefore, once shipped,
the feature CORRECTLY reports all 3 on the real repo and the digest verdict
becomes NEEDS-TRIAGE (from CLEAN). This is the detection working on real data, not
a false positive. Remediating the 3 collisions (renaming the legacy spec slugs to
`spec-`-prefixed) is OUT OF SCOPE here: each slug has 7-8 immutable-telemetry
cross-references (EVENTS.jsonl, METRICS.jsonl, decisions.jsonl, briefs, reviews,
reports), so a rename rewrites historical provenance — a separate, riskier
follow-up (consistent with the intake's Notes: "a separate follow-up may enforce
the `spec-` prefix at allocation/Planning; this issue is the detection backstop").
See Blocking / decisions for the operator override (fix-first) path.

## Design: the frozen detection (verify against code; freeze exactly)

### Uniqueness key (frozen)
The grouping key is the doc's EFFECTIVE id — `d.id`, i.e. `fm.id ?? ids.primary`
(the SAME key `byId` and every id-keyed check use). The pass does NOT change how
`id` is computed, does NOT change `byId` semantics, and does NOT fork the scan.

### Same-doc slug-vs-fileId exclusion (frozen, structural)
Each scanned doc contributes EXACTLY ONE entry to the in-memory `docs[]` array
(one file = one record), carrying both a slug `id` and its own numbered `fileId`.
The pass groups `docs[]` by the effective `id` ONLY. A single doc's slug id vs its
own numbered fileId therefore can NEVER self-collide — a doc appears once per
group. A duplicate requires >=2 DISTINCT `docs[]` entries (distinct file paths)
sharing one effective id. The exclusion is structural (keying on effective id over
one-record-per-file), NOT a special case.

### New pure function (frozen shape)
Add an exported `duplicateDocIdsFor(docs)` to docs-audit-core.mjs (mirroring
`closeoutCandidatesFor`):
- Group `docs` by `String(d.id)`, skipping any doc with a falsy `id`.
- For each id-group with >1 member, emit `{ id, paths: [...group rel paths sorted
  ascending] }`.
- Return the array of such groups, sorted by `id` ascending (`localeCompare`).
- Deterministic: stable ordering (id, then path) regardless of scan order.

### Where it slots (frozen)
A READ-ONLY post-scan pass in `runAudit`, adjacent to the existing
`const closeoutCandidates = closeoutCandidatesFor(docs);` (~L943):
`const duplicateDocIds = duplicateDocIdsFor(docs);`. It uses only the already-read
`docs[]` (no git, no EVENTS), so it runs identically in `--quick`. Add
`duplicateDocIds` to the `runAudit` return object and
`duplicateDocId: duplicateDocIds.length` to `counts`.

### byId hardening (frozen: OUT of scope)
`closeoutCandidatesFor`'s last-writer-wins `byId` is DELIBERATELY left unchanged
(detection-only, per the dispatch design intent "prefer detection that makes the
verdict fail; byId hardening optional/secondary"). The new pass makes the silent
collision a first-class, verdict-affecting finding; that is the fix.

### Digest section (frozen)
In docs-audit.mjs, inside the `if (!args.quick)` digest block (mirroring the
`### Missing close telemetry` / `### Drift report` sections), render:
- Heading `### Duplicate doc ids: <count>`.
- `_None._` when empty; else a table with columns `[Id, Count, Paths]`, one row
  per group, `Count` = number of carrying paths, `Paths` = the group's sorted
  paths joined by ` + ` (deterministic; rows already sorted by id).
- A one-line report note, e.g. "Two or more scanned docs share one frontmatter
  `id` — id-keyed resolution (byId, closeout) silently picks one. Give each doc a
  unique id (e.g. `spec-`-prefix a spec that shares its intake's slug)."

### Verdict effect (frozen)
Fold the count into the digest verdict tally in docs-audit.mjs (~L350):
`needsTriage = counts.orphans + counts.drifted + counts.obsolete +
counts.violations + counts.provenanceDrift + counts.duplicateDocId`. So a
duplicate flips `### Verdict:` to `NEEDS-TRIAGE`. `hardFail` (the `--check` /
`--check --strict` exit-code path) is UNCHANGED — `duplicateDocId` is verdict-only,
NOT added to `hardFail`. This preserves the CI exit contract
(`.github/workflows/docs-numbering.yml` gates on the exit code, which stays 0).

## Scope
- In scope: `.aai/scripts/lib/docs-audit-core.mjs` (add `duplicateDocIdsFor`; call
  it in `runAudit`; add `duplicateDocIds` to the result + `duplicateDocId` to
  `counts`), `.aai/scripts/docs-audit.mjs` (render `### Duplicate doc ids` section;
  add `counts.duplicateDocId` to the `needsTriage` tally), new regression stanzas
  in `tests/skills/test-aai-docs-audit.sh` (existing stanzas byte-unchanged).
- Out of scope: how `id` / `fileId` is computed (unchanged); `byId` semantics in
  `closeoutCandidatesFor` (unchanged); `hardFail` / any `--check` exit code
  (unchanged); every other digest section and verdict; the index generator; and
  renaming the 3 pre-existing legacy collisions (separate follow-up — 7-8
  immutable-telemetry cross-refs each).
- Protected paths touched: none (`docs-audit-core.mjs` verified NOT in
  `protected_paths_l3`).

## Implementation strategy
- Strategy: tdd
- Rationale: a governance-integrity detection added to the trusted docs oracle,
  needing regression proof that the collision is observed FAILING (silent CLEAN)
  before the flag counts as evidence (RED-proof). Data-integrity domain logic ->
  step-7 `tdd`. RED: a two-doc same-id fixture currently yields no duplicate-doc-id
  finding and a CLEAN verdict; GREEN: the same fixture flags the id + both paths
  and reads NEEDS-TRIAGE. A never-flagged detection could be tautological; a real
  RED state proves it fires.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: small, additive, single-engine change on a dedicated branch;
  no migration, no protected path, reversible. STATE already records
  `worktree.user_decision: inline`, `base_ref: main` (operator-approved wave). No
  user decision required.
- User decision: inline (already recorded)
- Base ref: main
- Worktree branch/path: inline (operator wave; STATE names
  fix/docs-audit-duplicate-doc-id)
- Inline review scope: `.aai/scripts/lib/docs-audit-core.mjs`,
  `.aai/scripts/docs-audit.mjs`, `tests/skills/test-aai-docs-audit.sh`,
  `docs/specs/SPEC-0057-spec-docs-audit-duplicate-doc-id.md`,
  `docs/issues/ISSUE-0014-docs-audit-duplicate-doc-id.md`

## Acceptance Criteria Mapping

- Requirement ISSUE-0014 AC-001 (>=2 scanned docs sharing a frontmatter id ->
  `duplicate-doc-id` finding naming id + all paths; verdict NEEDS-TRIAGE)
  -> Spec-AC-01.
- Requirement ISSUE-0014 AC-002 (no false positives; fileId/slug distinction
  respected; existing behavior/verdicts otherwise unchanged; suite green)
  -> Spec-AC-02 + Spec-AC-03.
- (New, from verified reality; refines the intake's incorrect clean-repo premise)
  the real repo now reports exactly its genuine collisions -> Spec-AC-04.

- Maps to: ISSUE-0014 AC-001
- Spec-AC-01: When >=2 scanned docs share an effective frontmatter `id`, `runAudit`
  returns a `duplicateDocIds` group `{ id, paths }` naming the shared id and ALL
  carrying paths (paths sorted; groups sorted by id); `counts.duplicateDocId` >= 1;
  the digest renders a `### Duplicate doc ids` section listing the id + both paths;
  and the digest `### Verdict:` line reads `NEEDS-TRIAGE`.
  - Verification: `bash tests/skills/test-aai-docs-audit.sh` (the new two-doc
    same-id stanza) -> exit 0. RED-proof: the same stanza observed FAILING (no
    `### Duplicate doc ids` finding, verdict `CLEAN`) against the pre-change engine;
    RED evidence captured.

- Maps to: ISSUE-0014 AC-002
- Spec-AC-02: No false positives. (a) A single doc whose slug `id` differs from its
  numbered `fileId` is NEVER flagged (one `docs[]` record per file; grouping keys on
  effective id only). (b) A unique-id corpus — including a correctly
  `spec-`-prefixed change+spec pair (change id `X`, spec id `spec-X`) — yields zero
  duplicate-doc-id findings and stays `CLEAN`.
  - Verification: `bash tests/skills/test-aai-docs-audit.sh` (the new negative-control
    stanza) -> exit 0; the fixture's digest shows `### Duplicate doc ids: 0` and
    `### Verdict: CLEAN`.

- Maps to: ISSUE-0014 AC-002
- Spec-AC-03: Exit-code and behavior invariance. `duplicate-doc-id` is verdict-only,
  never `hardFail`: `docs-audit.mjs --check` on a duplicate-bearing fixture exits 0
  (no orphan/violation/provenance-drift source present), and the real-repo
  `--check --strict` still exits 0. Every existing digest section, drift verdict,
  and the full `test-aai-docs-audit.sh` suite stay green with existing stanzas
  byte-unchanged.
  - Verification: `.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh`
    -> exit 0 (whole suite, all prior stanzas green); duplicate-bearing fixture
    `docs-audit.mjs --check --no-event` -> exit 0; real-repo
    `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0.

- Maps to: (verified reality; refines ISSUE-0014 AC-002's premise)
- Spec-AC-04: On the REAL repo the audit reports EXACTLY the 3 genuine legacy
  collisions (`prompt-diet-byte-budget-true-up`, `secrets-preflight-env-multiline`,
  `spec-lint-duplicate-ac-id`), each naming both carrying paths; the digest verdict
  becomes `NEEDS-TRIAGE` (from CLEAN) while `--check` / CI exit codes stay 0. This
  is the feature working on real data (a real-data positive control), not a false
  positive; remediation of the 3 is a tracked follow-up.
  - Verification: `node .aai/scripts/docs-audit.mjs --no-event` on the repo root ->
    `### Duplicate doc ids: 3` naming the three ids + six paths, `### Verdict:
    NEEDS-TRIAGE`; `node .aai/scripts/docs-audit.mjs --check --strict --no-event` ->
    exit 0.

## Constitution deviations

None.

<!-- Art.1 evidence-before-claims: measurable AC + TEST-xxx (RED-proof required),
  no PASS in planning. Art.2 KISS/YAGNI: one grouping function + one digest section
  + one verdict term; byId and scan untouched. Art.3 portability: plain .mjs / bash
  fixture, git-diffable. Art.4 degrade-and-report: the audit REPORTS the collision
  (verdict NEEDS-TRIAGE), does not block (hardFail unchanged) — RFC-0002 posture.
  Art.5 additive: purely additive detection; existing verdicts/exit codes
  unchanged. Art.6 single-writer: STATE via state.mjs only. Art.7 operator-only
  merge: planning does not merge. -->

## Seam analysis
- Core -> digest seam: `duplicateDocIdsFor` produces `counts.duplicateDocId` +
  `duplicateDocIds` in docs-audit-core.mjs; docs-audit.mjs renders the section AND
  folds the count into the `needsTriage` verdict. Covered end-to-end by the new
  shell stanzas, which run the REAL `docs-audit.mjs` CLI over a fixture and assert
  BOTH the `### Duplicate doc ids` section AND the `### Verdict: NEEDS-TRIAGE` line
  (crossing the seam; not two mocked unit halves). This is the mandated integration
  test.
- Consumer seam (`triage.sh`): `triage.sh` greps the digest for `NEEDS-TRIAGE`
  (line 58) and, under `--check`, exits 1. Shipping this flips the real-repo digest
  to NEEDS-TRIAGE, so a scheduled `triage.sh --check` (an optional/cron gate, NOT a
  blocking CI job — verified: no workflow invokes it) would begin exiting 1 until
  the 3 legacy collisions are remediated. Documented, intended (the oracle telling
  the truth). Residual risk RR-1.
- CI seam (`.github/workflows/docs-numbering.yml`): runs `docs-audit.mjs --check
  --strict` and gates on the EXIT CODE (hardFail), not the verdict string. Since
  `duplicateDocId` is verdict-only (not hardFail), the CI exit code is unchanged
  (stays 0) — verified on the live repo. No CI break.
- Residual risk RR-1: the 3 pre-existing collisions flip the live-repo digest
  verdict CLEAN -> NEEDS-TRIAGE and would trip an optional `triage.sh --check`
  cron. Accepted and intended; remediation tracked as a separate follow-up
  (rename legacy spec slugs to `spec-`-prefixed). Not automatable within this
  additive-detection scope.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                          | Status  | Evidence | Review-By | Notes |
|------------|------------------------------------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | >=2 scanned docs sharing an effective id -> `duplicateDocIds` finding (id + all paths) + `### Duplicate doc ids` section + verdict NEEDS-TRIAGE | done | TEST-101 green — docs/ai/tdd/green-20260718T122624Z-spec0057-test101-104.log; RED — docs/ai/tdd/red-20260718T122513Z-spec0057-test101-104.log | TDD | — |
| Spec-AC-02 | No false positives: slug-vs-fileId never self-collides; unique-id corpus (incl. correct `spec-`-prefixed change+spec pair) -> zero + CLEAN | done | TEST-102 green — docs/ai/tdd/green-20260718T122624Z-spec0057-test101-104.log | TDD | — |
| Spec-AC-03 | Verdict-only (not hardFail): `--check` exit code unchanged; every existing section/verdict + full suite green; existing stanzas byte-unchanged | done | TEST-103 green + full-suite green (`.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh` exit 0) — docs/ai/tdd/green-20260718T122624Z-spec0057-test101-104.log | TDD | 5 PRE-EXISTING real-repo stanzas (test_spec0006_no_regression_real_repo, test_issue0001_no_regression_real_repo, test_spec0011_regression, test_change0007_regression, test_change0028_real_repo_clean) asserted the whole-digest `Verdict: CLEAN` for an UNSCOPED real-repo run — a claim AC-04 makes structurally false (the real repo now correctly reports NEEDS-TRIAGE). Each was amended (not byte-unchanged) to assert its actual regression-guard signal (`Orphans (need triage): 0` + no `CHECK FAILED`) instead of the coarse verdict text, following the SAME precedent already set by `test_change0012_regression`'s comment for pre-existing report-only drift. Flagging this explicitly: Spec-AC-03's "existing stanzas byte-unchanged" and AC-04's "real-repo verdict flips to NEEDS-TRIAGE" are mutually exclusive for these 5 specific stanzas; AC-04 (the frozen, explicit design intent) was treated as authoritative. |
| Spec-AC-04 | Real repo reports exactly the 3 genuine legacy collisions + verdict NEEDS-TRIAGE; `--check`/CI exit codes stay 0 | done | TEST-104 green — docs/ai/tdd/green-20260718T122624Z-spec0057-test101-104.log; real-repo verdict verified `NEEDS-TRIAGE (3 items)`, `--check --strict --no-event` exit 0 | TDD | real-data positive control |

## Implementation plan
- Components/modules affected:
  - `.aai/scripts/lib/docs-audit-core.mjs`: new exported `duplicateDocIdsFor(docs)`
    (group by `String(d.id)`, skip falsy, emit groups >1 as `{ id, paths sorted }`,
    array sorted by id); call it in `runAudit` next to `closeoutCandidatesFor`; add
    `duplicateDocIds` to the return object and `duplicateDocId` to `counts`.
  - `.aai/scripts/docs-audit.mjs`: render `### Duplicate doc ids: <n>` (table
    `[Id, Count, Paths]`, `_None._` when empty, one-line note) inside the
    `if (!args.quick)` block near the missing-close-telemetry section; add
    `counts.duplicateDocId` to the `needsTriage` sum. `hardFail` untouched.
- Data flow: `runAudit` builds `docs[]` (effective id per doc) -> post-scan
  `duplicateDocIdsFor(docs)` groups by effective id -> `counts.duplicateDocId`
  feeds the digest verdict; the digest section reads `result.duplicateDocIds`.
- Edge cases: exactly-2 vs 3+ carriers in one group (Count reflects it); a doc with
  a falsy id (orphan — no fm.id and no filename primary) is skipped (never grouped);
  slug-vs-fileId of ONE doc never self-collides (one record per file); `--quick`
  computes the same grouping (offline) and includes it in the verdict but renders no
  `###` section (mirrors siblings); scope via `--path` narrows `docs[]` so grouping
  is over the scoped set only; deterministic ordering (id then path) independent of
  filesystem scan order.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                 | Description                                                                                                                                                                                                 | Status  |
|----------|------------|-------------|--------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-101 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh  | Two docs (a spec + an issue) sharing one frontmatter `id`: `docs-audit.mjs --no-event` emits a `### Duplicate doc ids` section naming the shared id + BOTH paths, and `### Verdict:` reads `NEEDS-TRIAGE`. RED-gating: pre-change engine yields no such section and `CLEAN`. | green |
| TEST-102 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh  | Negative control: a unique-id corpus incl. a correctly `spec-`-prefixed change+spec pair (change id `X`, spec id `spec-X`) and a doc whose slug id differs from its numbered fileId -> `### Duplicate doc ids: 0` and `### Verdict: CLEAN` (no false positive, no self-collision). | green |
| TEST-103 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh  | Invariance: on the duplicate-bearing fixture `docs-audit.mjs --check --no-event` exits 0 (verdict-only, not hardFail); the full `test-aai-docs-audit.sh` suite stays green with every pre-existing stanza byte-unchanged. | green |
| TEST-104 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh  | Real-repo control: running the audit against the actual repo root reports exactly the 3 known collisions (the three ids + six paths) with verdict `NEEDS-TRIAGE`, while `--check --strict` exits 0. (Assert the three ids appear in a `### Duplicate doc ids` section; tolerate count growth if new collisions are later remediated by keeping the assertion to the three named ids.) | green |

Notes:
- Every Spec-AC has >=1 TEST-xxx. TEST-101/102/103 are hermetic-fixture stanzas
  (own temp repo, like the existing suite); TEST-104 probes the real repo
  read-only.
- RED-proof obligation: TEST-101 (and the verdict-flip of TEST-104) MUST be
  observed FAILING against the pre-change engine (no `### Duplicate doc ids`
  section; verdict CLEAN) before GREEN counts as evidence. TEST-102's zero/CLEAN
  arm may be green pre-change (the engine flags nothing today) — that alone is NOT
  AC-02 evidence; it gates once the detection exists (proves no over-flagging).
- TEST IDs use a fresh 101+ band to avoid colliding with the suite's existing
  numbering; do not renumber after freeze.

## Verification
- `bash tests/skills/test-aai-docs-audit.sh` -> exit 0 (incl. new TEST-101..104
  stanzas).
- `.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh` -> exit 0
  (whole suite; every pre-existing stanza byte-identical and green).
- `node .aai/scripts/docs-audit.mjs --no-event` (repo root) -> `### Duplicate doc
  ids: 3` (three named ids + six paths), `### Verdict: NEEDS-TRIAGE`.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` (repo root) ->
  exit 0 (CI exit contract preserved).
- PASS criteria: all TEST-101..104 green; all Spec-AC in a terminal (`done`) status
  with non-empty Evidence; RED logs captured for TEST-101 and the TEST-104
  verdict-flip.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: docs-audit-duplicate-doc-id (SPEC-0057 at merge)
- Spec-AC and TEST-xxx links (Spec-AC-01/TEST-101, Spec-AC-02/TEST-102,
  Spec-AC-03/TEST-103 + full-suite, Spec-AC-04/TEST-104)
- command or review scope
- exit code or review verdict
- evidence path (RED/GREEN logs under docs/ai/tdd/; review under docs/ai/reviews/)
- commit SHA or diff range when available
