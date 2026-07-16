---
id: spec-l1-close-gate
type: spec
number: 36
status: done
ceremony_level: 2
links:
  change: l1-close-gate
  rfc: scale-adaptive-ceremony
  pr:
    - 85
  commits:
    - 7e89f03
---

# SPEC — Level-Aware Close Gate and Done-Drift Check (L0/L1 lean specs can close)

SPEC-FROZEN: true

## Links
- Change: l1-close-gate (docs/issues/CHANGE-0024-l1-close-gate.md)
- Amends behavior introduced by: spec-scale-adaptive-ceremony
  (docs/specs/SPEC-0030-spec-scale-adaptive-ceremony.md, RFC-0009)
- Found by: first live ceremony_level 1 validation
  (validation-truth-20260716T161729Z.md, finding L1-1 BLOCKING)
- Technology contract: docs/TECHNOLOGY.md

## Problem
SPEC-0030 defined L0/L1 lean specs ("lean SPEC (AC table only) + justification"
per the WORKFLOW.md ceremony table) but never reconciled two pre-existing
consumers that unconditionally demand the canonical
`## Acceptance Criteria Status` table (with `Review-By` column):
- `gateContent` (.aai/scripts/lib/docs-audit-core.mjs) fails any doc without
  the canonical table: `missing AC Status table`;
- the done-drift check (same file, `status done && !ac.hasGate && type spec`)
  marks a done lean spec `probable-partial`.
Consequence: no L0/L1 spec can ever transition to done through the standard
playbook (VALIDATION step 8b mandates FAIL on the flip).

## Ceremony level
`ceremony_level: 2` — this change edits the docs-audit close-gate machinery
and a role prompt; it is not a small single-surface fix and it is not on the
`protected_paths_l3` list (checked against docs/ai/docs-audit.yaml: state
engine, allocator, guards, workflow canon only). Full pipeline applies.

## Implementation strategy
- Strategy: tdd
- Rationale: gate/drift behavior changes on a governance surface need
  regression proof both ways; the validator's live reproduction is the RED.
- RED-proof obligation: before any edit, reproduce the validator's finding on
  fixtures (L1 lean spec fails `--gate-file`; done flip goes NEEDS-TRIAGE) and
  run the new suite stanzas failing; save docs/ai/tdd/l1-close-gate-red.log.

## Isolation and review
- Worktree recommendation: recommended (parallel-wave repo hygiene)
- User decision: worktree (executing in /Users/ales/Projects/aai-fix-l1gate,
  branch fix/l1-close-gate, base 0b4ce55)
- Base ref: 0b4ce55
- Inline review scope (explicit paths):
  - .aai/scripts/lib/docs-model.mjs (new lean-AC-table parser)
  - .aai/scripts/lib/docs-audit-core.mjs (gateContent + done-drift check)
  - .aai/VALIDATION.prompt.md (step 8b wording, minimal)
  - tests/skills/test-aai-docs-audit.sh (new stanzas)
  - docs/specs/SPEC-0036-spec-l1-close-gate.md, docs/issues/CHANGE-0024-l1-close-gate.md
  - docs/specs/SPEC-0032-spec-truth-scoring.md (D6 conformance: Status column
    added, two literal-pipe AC cells reworded — first live L1 spec made closeable)
  - docs/INDEX.md (regenerated)

## Design decisions

### D1 — Lean AC-table shape (what L0/L1 must carry to close)
A lean AC table is the first markdown table under a heading line
`## Acceptance Criteria` or `## Acceptance Criteria Status` (case-insensitive;
nothing else on the heading line, so `## Acceptance Criteria Mapping` never
matches) whose header row has a `Spec-AC` column AND a `Status` column.
`Review-By` and `Evidence` columns are OPTIONAL; when present they are checked
with the canonical rules (schema-valid Review-By; done rows need Evidence).
Placeholder rows are skipped exactly as in the canonical parser. Parser lands
as `parseLeanAcTable` in docs-model.mjs beside `parseAcTable` (shared by gate
and drift check — no fork).

### D2 — Level parsing at the gate follows the dispatch fail-closed discipline
`gateContent` derives lean-eligibility ONLY from a validly declared
`ceremony_level` of `0` or `1`. Absent field or YAML null = legacy implicit
L2; a garbage value keeps the existing `schema-invalid ceremony_level` reason
AND full L2 structural requirements (fail-closed: a bad declaration can only
add ceremony, never remove it — same rule as the dispatch, SPEC-0030 D2).
For lean-eligible docs: a doc that volunteers the full canonical table gets
the full canonical row checks; otherwise the lean table is required (missing
=> gate reason naming the lean shape), every row must be terminal, and the
existing `Ceremony justification: ` line requirement stays (gate FAIL naming
it when missing — unchanged check, now load-bearing for close).

### D3 — Done-drift check mirrors the gate exactly
In the `status: done` drift branch, a spec without the canonical gate table is
`probable-partial` UNLESS lean-eligible AND the lean table exists AND the
justification line is present; a lean-eligible done spec whose lean rows are
non-terminal is `probable-false-done` (naming the rows), mirroring the
canonical branch. Aligned lean specs classify `tracked-done`.

### D4 — VALIDATION 8b: minimal wording reconciliation
Step 8b hardcodes the canonical table for every `type: spec`. One line is
adjusted so the assertion names the L0/L1 lean satisfaction path; the
CLOSE-POLICY and CLOSE GATE paragraphs are untouched (the gate command itself
becomes level-aware, so their text stays true).

### D5 — L2/absent byte-identity is a tested invariant
For every doc that is NOT lean-eligible, gate reasons and drift verdicts are
byte-identical to the pre-change engine: proven by re-running the recorded
pre-change fixture outputs (gate logs + strict check reports) and diffing, and
by the existing spec0011/change0012/ceremony-levels suites staying green.

### D6 — Unparseable declared lean rows fail the gate AND the drift check (silent-drop reconciliation)
Surfaced by the FIRST real ceremony_level 1 spec (SPEC-0032): the shared lean
parser splits rows on a naive `|`, so a row whose cell carries a literal pipe
(plain `|` OR an escaped `\|`, which this parser does NOT unescape) gains a
phantom cell, fails the column-count check, and is SILENTLY dropped. Pre-fix,
the gate then validated only the surviving rows and could PASS while a declared
AC went unchecked — the exact SPEC-0012 Spec-AC-08 invisibility class, now on
the close path.

The reconciliation lives at the SINGLE SOURCE OF TRUTH: `parseLeanAcTable`
returns `declaredIds` — every `Spec-AC-NN` id found in the SAME line set it
walks (dropped rows included), using the same `l.trim().startsWith('|')`
whitespace tolerance as its row detection. `unparseableLeanIds(lean)` =
`declaredIds` minus the ids that parsed into `rows`. Both consumers reconcile
on it:
- the close gate (`gateContent`) FAILS naming any unparseable declared id,
  steering the author to reword the cell (escaping does not help this parser);
- the done-drift check mirrors it exactly (D3): a `status: done` lean spec with
  an unparseable declared row is `probable-false-done`, since a dropped row's
  status is invisible and cannot be trusted terminal.

Deriving `declaredIds` from the parser's own line set (not a sibling
line-anchored regex) makes the two views structurally impossible to disagree —
including on indented rows (1–3 leading spaces are valid markdown that the row
detector accepts). Fail-closed and additive — a fully-parseable lean table
reconciles to itself and is unaffected. As a consequence SPEC-0032's own AC
table was brought into the canonical lean shape (a `Status` column added; the
two literal-pipe cells reworded) so the first live L1 spec is gate-closeable.

## Constitution deviations

None.

Honest per-article check (docs/CONSTITUTION.md v1): Art. 1 — the change makes
the evidence gate honest for lean specs, never weaker for L2+ (byte-identity
invariant D5); Art. 2 — one shared parser, no speculative config; Art. 3 —
plain mjs/markdown; Art. 4 — fail-closed garbage handling keeps degrade-and-
report; Art. 5 — additive parser + branch, absent field byte-identical legacy
behavior; Art. 6 — no STATE writes from the audit engine; Art. 7 — merge
stays operator-only.

## Acceptance Criteria Mapping
- Maps to CHANGE AC-001 (L1 lean spec can pass the gate and close CLEAN)
  - Spec-AC-01: an L1 spec with a lean AC table (Spec-AC + Status, terminal
    rows) and a `Ceremony justification: ` line passes `--gate-file`/`--gate`
    (exit 0); with `status: done` it classifies aligned/tracked-done and
    `--check --strict` stays CLEAN; missing justification line fails the gate
    naming it (and drifts probable-partial when done); a non-terminal lean row
    fails the gate naming the row.
  - Verification: TEST-001, TEST-002, TEST-003.
- Maps to CHANGE AC-002 (L2/absent byte-identical; L0 semantics compatible)
  - Spec-AC-02: explicit `ceremony_level: 2` and absent-level specs keep
    byte-identical gate reasons and drift verdicts (lean table alone still
    fails: `missing AC Status table` / probable-partial); garbage level values
    fail closed to full requirements while still reporting `schema-invalid
    ceremony_level`; `ceremony_level: 0` gets the same lean acceptance as 1
    (spec-lint L0 exemption semantics stay compatible; that suite is not on
    this branch base).
  - Verification: TEST-004, TEST-005, byte-identity probe (D5).
- Maps to CHANGE AC-003 (hygiene + 8b consistency)
  - Spec-AC-03: docs-audit and ceremony-levels suites green; full
    tests/skills sweep no new failures; repo-wide `--check --strict` CLEAN;
    audit re-run and index regeneration idempotent; check-state OK;
    VALIDATION 8b adjusted at most 2 lines and consistent with the
    level-aware gate.
  - Verification: TEST-006 + suite/sweep/audit/check-state runs recorded in
    the Evidence contract.
- Maps to CHANGE AC-001 (close-gate honesty — silent-drop hardening, D6)
  - Spec-AC-04: a declared lean AC row that the shared parser drops on a
    cell-count mismatch (a literal or escaped `|` in a cell, flush OR indented)
    FAILS the gate naming the row and explaining it did not parse, instead of
    passing on the surviving rows; the done-drift check mirrors this (a done
    spec with such a row is probable-false-done naming it, not CLEAN); a
    fully-parseable lean table is unaffected. SPEC-0032, the first live L1 spec,
    is brought to the canonical lean shape so it closes.
  - Verification: TEST-007 (gate: flush + escaped + indented), TEST-008 (drift).

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | L1 lean spec passes gate, closes CLEAN; missing justification fails naming it | done | docs/ai/tdd/l1-close-gate-red.log + docs/ai/tdd/l1-close-gate-green.log (TEST-001..003 RED->GREEN; validator repro re-run GATE PASS + CLEAN) | TDD | —     |
| Spec-AC-02 | L2/absent byte-identical; garbage level fail-closed; L0 lean parity | done | docs/ai/tdd/l1-close-gate-green.log (TEST-004/005 + 26-output byte-identity probe pre/post diff empty) | TDD | —     |
| Spec-AC-03 | Suites green, sweep, strict audit CLEAN, idempotence, check-state, 8b wording | done | docs-audit + ceremony-levels + prompt-diet suites exit 0; sweep 25/26 (only known pre-existing aai-worktree env failure, LEARNED 2026-07-15); strict audit CLEAN exit 0 twice byte-identical; INDEX regen idempotent; check-state OK; 8b diff 1 line -> 2 | TDD | validation-owned done-flip pending |
| Spec-AC-04 | Unparseable declared lean row (literal/escaped/indented pipe) fails the gate AND drift-check naming it; parseable table unaffected; SPEC-0032 conformed | done | TEST-007 (plain + escaped + indented gate variants exit 1 naming Spec-AC-02 "did not parse"); TEST-008 (done spec with pipe-dropped non-terminal row -> probable-false-done, reworked -> CLEAN); SPEC-0032 gate PASS post-conformance (Status column added, 2 literal-pipe cells reworded; parseLeanAcTable 3/3 rows); full docs-audit + spec-lint + ceremony-levels suites green; strict audit CLEAN | TDD | —     |

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                   | Description                                                                 | Status  |
|----------|------------|-------------|-----------------------------------------|-------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh    | L1 lean spec + justification: `--gate-file` and `--gate` exit 0; non-terminal lean row flips gate to exit 1 naming the row | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh    | L1 lean spec WITHOUT justification: gate exit 1 naming the Ceremony justification line, with NO missing-table reason | green |
| TEST-003 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh    | done L1 lean spec: `--check --strict` CLEAN / tracked-done; mutation control: dropping the justification flips to NEEDS-TRIAGE probable-partial | green |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh    | L2-explicit and absent-level specs with only a lean table: gate exit 1 `missing AC Status table`; done drifts probable-partial; canonical L2 done still passes | green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh    | garbage `ceremony_level` (banana) with lean table + justification: gate exit 1 with BOTH schema-invalid reason AND missing AC Status table (fail-closed) | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh + tests/skills/test-aai-ceremony-levels.sh | full suites re-run green post-change (regression seam) + strict audit CLEAN over the real repo | green |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh    | lean spec with a literal-pipe-broken declared row: gate exit 1 naming Spec-AC-02 "did not parse"; escaped-pipe AND indented (1-3 space) variants STILL exit 1 (parser does not unescape; reconciler shares the row detector's whitespace tolerance); parseable table unaffected | green |
| TEST-008 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh    | done L1 lean spec with a pipe-dropped NON-TERMINAL declared row: `--check` reports NEEDS-TRIAGE probable-false-done naming Spec-AC-02 as unparseable (drift mirrors gate, D3); rewording the pipe out -> `--check --strict` CLEAN | green |

Seam analysis:
- Seam S1 — gateContent is shared by gateDoc (worktree file), gateFile (staged
  blob via the pre-commit hook) and the closeout skills. Crossing tests:
  TEST-001/002/004/005 drive the real CLI `--gate-file`/`--gate` end-to-end.
- Seam S2 — the drift engine feeds --check verdicts, the digest and the index
  generator. Crossing test: TEST-003 runs the real `--check --strict` on a
  fixture repo; TEST-006 re-runs the repo-wide strict audit + index regen.
- Seam S3 — parseLeanAcTable lives beside parseAcTable/detectNearMissAcTable;
  lean tables must not trip near-miss warnings (they carry neither Review-By
  nor Evidence columns by default). Covered by TEST-003 CLEAN assertion.
- Residual risk (recorded): spec-lint's L0/L1 exemptions live on an unmerged
  sibling stream; this change keeps semantics compatible per CHANGE AC-002
  wording but cannot execute that suite here.
- Residual risk (recorded, review F3): the silent-drop reconciliation covers
  the LEAN table only. A lean-eligible doc that instead volunteers the full
  canonical `## Acceptance Criteria Status` table takes the canonical
  `checkRows(ac.rows, true)` path, and `gateContent` does NOT reconcile
  `parseAcTable` drops there — a pre-existing L2 gap (`gateContent` has never
  reconciled canonical drops; only spec-lint's `ac-row-unparseable` catches
  them, and it runs at FREEZE before a doc can be committed frozen). Newly
  reachable on the close path for a lean-eligible doc, but bounded by that same
  freeze-time spec-lint net. Closing the canonical-path gate reconciliation is
  deferred as its own change (it would alter the L2 `parseAcTable` contract
  repo-wide) rather than folded here.

## Verification
- `bash tests/skills/test-aai-docs-audit.sh` -> exit 0 (all stanzas incl. new).
- `bash tests/skills/test-aai-ceremony-levels.sh` -> exit 0 (TEST-006 of SPEC-0030 unchanged).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0 CLEAN.
- Byte-identity probe: pre-change vs post-change gate logs + strict reports on
  L2/absent fixtures diff empty (D5).
- `node .aai/scripts/generate-docs-index.mjs` twice -> second run idempotent.
- `node .aai/scripts/check-state.mjs docs/ai/STATE.yaml` -> OK.

## Evidence contract
For each artifact, record: ref_id l1-close-gate, Spec-AC and TEST-xxx links,
command, exit code, evidence path (docs/ai/tdd/l1-close-gate-red.log,
docs/ai/tdd/l1-close-gate-green.log), diff range when available.
