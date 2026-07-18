---
id: spec-spec-lint-duplicate-ac-id
type: spec
number: 51
status: done
ceremony_level: 1
links:
  requirement: ISSUE-0011
  rfc: null
  pr:
    - 103
  commits:
    - ef43dab
---

# Spec: spec-lint — surface a duplicate Spec-AC-id that silently drops a row

SPEC-FROZEN: true

Ceremony justification: single-surface additive lint check in one report-only
script (`.aai/scripts/spec-lint.mjs`) plus its bash test suite and this spec.
No engine/shared-parser change (`parseAcTable` untouched), no schema change, and
`.aai/scripts/spec-lint.mjs` is NOT in `protected_paths_l3` (docs/ai/docs-audit.yaml
lists state.mjs, state-engine, state-core, allocate-doc-number, pre-commit-checks,
WORKFLOW.md, CONSTITUTION.md — spec-lint.mjs is absent). Report-only, never a hard
gate. L1.

## Links
- Requirement: docs/issues/ISSUE-0011-spec-lint-duplicate-ac-id.md
- Decision records: decisions.jsonl (ref `spec-lint`, F2 dup-id dropped-row)
- Technology contract: docs/TECHNOLOGY.md

## Problem (verified RED)

`parseAcTable` (lib/docs-model.mjs) returns AC rows as an ARRAY, so two rows that
BOTH parse with the same `Spec-AC-NN` id are already caught by the existing
`ac-id-duplicate` check (spec-lint.mjs ~line 237; TEST-001 in the existing suite).
The unhandled case is a DUPLICATE id where one copy is DROPPED by the shared
parser (a cell-count break — e.g. a markdown-escaped pipe `\|` in a later cell):

- the surviving copy seeds the id into `knownIds`, so the existing
  `ac-row-unparseable` check (which fires only when a raw `| Spec-AC-NN` row's id
  is NOT in `knownIds`) stays silent;
- only one row survives into `ac.rows`, so `ac-id-duplicate` also stays silent;
- the dropped row (its status/evidence) is invisible to docs-audit, the index,
  and the close gate.

RED proof (2026-07-17, current tree): a spec whose AC table carries
`| Spec-AC-02 | ... |` twice, the second with an escaped pipe in a cell, lints
`Findings: 0 / LINT PASS / exit 0`. The hidden row escapes the lint entirely.

## Design — reconciliation rule (frozen)

Add ONE additive, report-only finding rule `duplicate-ac-id` to
`lintContent()` in `.aai/scripts/spec-lint.mjs`, scoped to the canonical
Acceptance Criteria Status **gate** table (`if (ac.hasGate)` branch), reusing the
section-scan loop that already emits `ac-row-unparseable` (no second regex, no
second pass — DRY).

RAW-vs-PARSED reconciliation:
1. `rawCount[id]` — while walking the `## Acceptance Criteria Status` section's
   data-row lines, tally each line whose FIRST cell is exactly `Spec-AC-NN`
   (two digits, matched by `AC_ID_RE`). The existing `raw = line.match(
   /^\|\s*(Spec-AC-\d+)(?=\s|\|)/)` capture already extracts the first-cell id
   from padded, compact (`|Spec-AC-01|`), AND escaped-pipe-broken rows (the first
   cell never contains an escaped pipe), and its `(?=\s|\|)` lookahead FAILS on a
   `Spec-AC-NN..MM` range row (the char after the digits is `.`) — so range rows
   contribute NOTHING to `rawCount`. Filter the capture through `AC_ID_RE.test`
   so 1-digit / malformed ids are excluded (they are owned by `ac-id-malformed`).
2. `parsedCount[id]` — tally ids in `ac.rows` (the parser's surviving rows) that
   match `AC_ID_RE`.
3. Emit `duplicate-ac-id` for each id where `rawCount[id] > parsedCount[id]`
   **AND** `parsedCount[id] >= 1`. Detail names the id and the raw-vs-parsed
   delta, e.g.: `Spec-AC-02 appears in 2 raw AC-table rows but only 1 survived the
   shared parser — a duplicate id dropped 1 row (invisible to docs-audit, the
   index, and the close gate)`.

This produces a clean, NON-overlapping 3-way partition with the existing checks —
each dropped/duplicate shape reported by exactly one rule:

| Shape | rawCount vs parsedCount | Rule that fires |
|-------|-------------------------|-----------------|
| Duplicate id, both copies parse | rc == pc (== 2) | `ac-id-duplicate` (existing) |
| Duplicate id, one copy dropped (id survives once) | rc > pc, pc >= 1 | `duplicate-ac-id` (NEW) |
| Single row dropped, id fully vanishes | rc >= 1, pc == 0 | `ac-row-unparseable` (existing) |

The `pc >= 1` guard is what keeps `duplicate-ac-id` from double-reporting the
`ac-row-unparseable` (fully-vanished) case. Iteration over `rawCount` (a Map)
preserves document order, so output is deterministic and stable.

Range / lean / compact false-positive avoidance (AC-002):
- Range rows (`Spec-AC-NN..MM`) never enter `rawCount` (lookahead exclusion) and
  are already reported as `ac-id-malformed` by the existing gate-table loop when
  they appear in a gate table — untouched by this rule.
- Compact rows (`|Spec-AC-01|...|`) parse fine → `rawCount == parsedCount` → no
  finding.
- Lean L0/L1 tables (`!ac.hasGate`) do not enter the `if (ac.hasGate)` branch, so
  the new rule never runs on them → zero `duplicate-ac-id` findings by
  construction.

## Out of scope / residual risk

- Lean-table dropped-duplicate detection is DEFERRED (residual risk, low). A
  dropped duplicate in an L0/L1 lean AC table is not detected here. `parseLeanAcTable`
  already exposes `declaredIds` for a future lean reconciliation, but its `\b`
  boundary captures the leading `NN` of a range row (`Spec-AC-NN..MM`), which would
  need dedicated range-exclusion + a test to avoid a false positive — expanding the
  L1 surface. Deferred to keep this fix single-surface; lean specs seed the same
  raw ids into `knownIds` today, and the motivating governance gap (the close gate)
  is a gate-table (L2+) surface.
- The shared `parseAcTable` is NOT modified (other consumers — generate-docs-index,
  docs-audit — depend on it). This rule reconciles against the RAW table only.
- The bundled `state-engine append-run flow-style work_items: {}` tolerance
  (ISSUE-0011 Notes) is a separate surface and stays its own follow-up.

## Implementation strategy
- Strategy: tdd
- Rationale: governance-tooling correctness bug fix that needs regression proof.
  The RED state is real and reproduced (dropped duplicate → 0 findings today);
  the AC-gating positive test MUST be observed failing without the change before
  its pass counts. The partition (no double-report, no false positives on
  range/compact/lean) is exactly the kind of boundary logic where RED-GREEN pins
  intent. Small surface, but the risk profile (silent under-report the lint
  exists to prevent) justifies TDD over loop.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: one script + its bash suite + this spec; report-only, no
  shared-parser or schema change; single scope, low blast radius.
- User decision: inline (operator-approved wave, STATE worktree.user_decision:
  inline on branch fix/spec-lint-duplicate-ac-id).
- Base ref: main
- Worktree branch/path: fix/spec-lint-duplicate-ac-id (current working tree)
- Inline review scope: .aai/scripts/spec-lint.mjs, tests/skills/test-aai-spec-lint.sh,
  docs/specs/SPEC-0051-spec-lint-duplicate-ac-id.md

## Acceptance Criteria Mapping

Requirement AC-001 (ISSUE-0011) → Spec-AC-01, Spec-AC-02.
Requirement AC-002 (ISSUE-0011) → Spec-AC-03, Spec-AC-04, Spec-AC-05.

- Maps to: ISSUE-0011 AC-001
- Spec-AC-01: A gate AC table with a duplicate `Spec-AC-NN` whose second copy is
  dropped by an escaped-pipe cell-count break emits a `duplicate-ac-id` finding
  naming the repeated id; the file lints exit 1 (not clean).
  - Verification: `node .aai/scripts/spec-lint.mjs --path <dup-drop fixture>` →
    exit 1, output contains `duplicate-ac-id` and `Spec-AC-NN`.
- Spec-AC-02: The `duplicate-ac-id` detail reports the raw-vs-parsed delta
  (raw row count and surviving/parsed count) for the repeated id.
  - Verification: fixture output line for the id names both the raw count and the
    parsed/surviving count (delta ≥ 1).
- Maps to: ISSUE-0011 AC-002
- Spec-AC-03: The rule does not double-report. A duplicate id whose BOTH copies
  parse emits `ac-id-duplicate` (existing) and does NOT additionally emit
  `duplicate-ac-id`; a fully-vanished single row emits `ac-row-unparseable`
  (existing) and NOT `duplicate-ac-id`.
  - Verification: both-parse fixture output has `ac-id-duplicate` and no
    `duplicate-ac-id`; vanished-row fixture has `ac-row-unparseable` and no
    `duplicate-ac-id`.
- Spec-AC-04: No false positives on legitimate shapes — a clean gate table with a
  compact row, a Test-Plan `Spec-AC-NN..MM` range, and a lean L1 AC table each
  emit zero `duplicate-ac-id` findings and lint exit 0.
  - Verification: clean/compact/range/lean fixtures → exit 0, no `duplicate-ac-id`.
- Spec-AC-05: The real repository corpus lints with zero `duplicate-ac-id`
  findings (exit 0), and the existing spec-lint suite stays green with zero edits
  to its existing assertions.
  - Verification: `node .aai/scripts/spec-lint.mjs` over the repo → exit 0, no
    `duplicate-ac-id`; `bash tests/skills/test-aai-spec-lint.sh` → exit 0.

## Constitution deviations

None.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description                                                                 | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Dropped-duplicate gate row emits `duplicate-ac-id` naming the id; exit 1     | done | docs/ai/tdd/green-20260717T211900Z-spec-lint-duplicate-ac-id-test001-005.log (TEST-001(dupac)) | —         | —     |
| Spec-AC-02 | Finding detail reports the raw-vs-parsed delta for the repeated id           | done | docs/ai/tdd/green-20260717T211900Z-spec-lint-duplicate-ac-id-test001-005.log (TEST-001(dupac)) | —         | —     |
| Spec-AC-03 | No double-report vs `ac-id-duplicate` (both-parse) and `ac-row-unparseable`  | done | docs/ai/tdd/green-20260717T211900Z-spec-lint-duplicate-ac-id-test001-005.log (TEST-002/003(dupac)) | —         | —     |
| Spec-AC-04 | Zero false positives on compact / range / lean shapes; exit 0                | done | docs/ai/tdd/green-20260717T211900Z-spec-lint-duplicate-ac-id-test001-005.log (TEST-004(dupac)) | —         | —     |
| Spec-AC-05 | Real corpus zero `duplicate-ac-id`; existing suite green, no assertion edits | done | docs/ai/tdd/green-20260717T211900Z-spec-lint-duplicate-ac-id-test001-005.log (TEST-005(dupac) + full suite 18/18) | —         | —     |

## Implementation plan
- Components/modules affected: `.aai/scripts/spec-lint.mjs` (`lintContent`, the
  `if (ac.hasGate)` AC-status section-scan block) ONLY.
- Data flows: reuse the already-computed `section` match + the `raw` first-cell
  capture in the existing `ac-row-unparseable` loop; add a `rawCount` Map tally in
  that loop; after it, build `parsedCount` from `ac.rows`; emit `duplicate-ac-id`
  per the reconciliation rule. No change to `parseAcTable` or any shared parser.
- Edge cases: compact rows (no false positive), range rows (excluded from count),
  1-digit/malformed ids (excluded via `AC_ID_RE.test`, owned by `ac-id-malformed`),
  fully-vanished single row (owned by `ac-row-unparseable`), placeholder rows
  (`Spec-AC-xx`, `<...>` — never match `AC_ID_RE`).

## Test Plan
For each Spec-AC, enumerate concrete tests. All tests live in the existing bash
suite `tests/skills/test-aai-spec-lint.sh` (bash-3.2 compatible), added as new
arms — no existing assertion is edited. At L1 the Test Plan IS the declared
validation scope; each row names a directly executable command.

| Test ID  | Spec-AC              | Type | File path (expected)                | Description                                                                                     | Status  |
|----------|----------------------|------|-------------------------------------|-------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01, Spec-AC-02 | unit | tests/skills/test-aai-spec-lint.sh | Gate table, duplicate `Spec-AC-02`, 2nd copy dropped by escaped pipe → `duplicate-ac-id` names id + delta, exit 1 | green |
| TEST-002 | Spec-AC-03           | unit | tests/skills/test-aai-spec-lint.sh | Duplicate id, BOTH copies parse → `ac-id-duplicate` fires AND `duplicate-ac-id` absent            | green |
| TEST-003 | Spec-AC-03           | unit | tests/skills/test-aai-spec-lint.sh | Single row fully dropped (no surviving copy) → `ac-row-unparseable` fires AND `duplicate-ac-id` absent | green |
| TEST-004 | Spec-AC-04           | unit | tests/skills/test-aai-spec-lint.sh | Clean gate table with a compact row + Test-Plan range + a lean L1 table → zero `duplicate-ac-id`, exit 0 | green |
| TEST-005 | Spec-AC-05           | unit | tests/skills/test-aai-spec-lint.sh | Real corpus `node spec-lint.mjs` → exit 0, no `duplicate-ac-id`; full suite `bash ...` exit 0    | green |

RED-proof obligation: TEST-001 MUST be observed FAILING on the current tree
(dropped duplicate → 0 findings / exit 0 today, reproduced 2026-07-17) before its
passing counts as evidence.

Seam analysis:
- SEAM: spec-lint's finding stream + exit-code contract (0 clean / 1 findings) is
  consumed by the PLANNING post-freeze advisory (step 10) and the VALIDATION
  step-1 advisory, and shaped by `--json`. Adding a finding flips exit to 1 when a
  dropped duplicate exists. Crossed end-to-end by TEST-005 (real corpus run +
  existing TEST-008 `--json` shape + TEST-009 corpus-clean arm) — produce the new
  rule on one side, assert the real exit/output on the other.
- No DB/state/close-gate seam: spec-lint is report-only and does not feed any gate
  mechanically (docs/ai/docs-audit.yaml close_gate governs the docs-audit engine,
  not spec-lint).

## Verification
- `node .aai/scripts/spec-lint.mjs --path <dup-drop fixture>` → exit 1, output
  contains `duplicate-ac-id` + `Spec-AC-NN` + the raw-vs-parsed delta (Spec-AC-01/02).
- Both-parse fixture → `ac-id-duplicate` present, `duplicate-ac-id` absent;
  vanished-row fixture → `ac-row-unparseable` present, `duplicate-ac-id` absent
  (Spec-AC-03).
- Clean/compact/range/lean fixtures → exit 0, no `duplicate-ac-id` (Spec-AC-04).
- `node .aai/scripts/spec-lint.mjs` (repo) → exit 0, no `duplicate-ac-id`;
  `bash tests/skills/test-aai-spec-lint.sh` → exit 0 (Spec-AC-05).
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: spec-lint-duplicate-ac-id
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
