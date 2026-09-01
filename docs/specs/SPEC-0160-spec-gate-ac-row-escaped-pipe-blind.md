---
id: spec-gate-ac-row-escaped-pipe-blind
type: spec
number: 160
status: done
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0077-gate-ac-row-escaped-pipe-blind.md
  rfc: null
  pr:
    - 331
  commits:
    - abea135
---

# SPEC — Canonical AC Status Table Gains the Silent-Drop Reconciliation (docs-audit --gate / --check)

SPEC-FROZEN: true

## Links
- Issue: gate-ac-row-escaped-pipe-blind
  (docs/issues/ISSUE-0077-gate-ac-row-escaped-pipe-blind.md, GitHub #330)
- Prior art (same defect class, lean table only):
  docs/specs/SPEC-0036-spec-l1-close-gate.md D6, whose own "Seam analysis"
  section explicitly deferred this exact canonical-table gap ("Closing the
  canonical-path gate reconciliation is deferred as its own change") — this
  spec is that deferred change.
- Technology contract: docs/TECHNOLOGY.md

## Problem
`.aai/scripts/lib/docs-model.mjs`'s `parseAcTable` splits each AC Status
table row on a naive `|` and drops any row whose resulting cell count does
not match the header — including a row whose cell carries a literal or
markdown-escaped pipe (`\|`, which this parser does not unescape). Two
consumers read `parseAcTable`'s output and both trust `ac.rows` as the
COMPLETE table with no reconciliation against what was actually declared:
- `gateContent` (`.aai/scripts/lib/docs-audit-core.mjs`), reached by
  `docs-audit.mjs --gate` / `--gate-file` and therefore by
  `close-work-item.mjs`'s close ceremony, asserts "AC Status table complete"
  over only the surviving rows.
- the done-drift check in the same file (`status: done` branch) classifies a
  spec `tracked-done`/aligned over the same survivors.

`spec-lint.mjs` already detects this exact shape (`ac-row-unparseable`) by
independently re-walking the raw section text and comparing declared ids
against parsed ids — but that detection is freeze-time-only and lives nowhere
the close gate reads. A spec whose AC Status table drops a non-terminal row
this way can therefore close through the standard playbook with a false
`GATE PASS`, and — if flipped to `done` while the dropped row's real status is
non-terminal — through `--check --strict` as CLEAN.

This is the canonical-table twin of SPEC-0036 D6, which fixed the identical
defect for the LEAN (`ceremony_level` 0/1) AC table via `parseLeanAcTable`'s
`declaredIds` + `unparseableLeanIds`. SPEC-0036 explicitly scoped that fix to
the lean table only and recorded the canonical gap as a residual risk
("Closing the canonical-path gate reconciliation is deferred as its own
change (it would alter the L2 `parseAcTable` contract repo-wide) rather than
folded here"). This spec closes that gap.

## Ceremony level
`ceremony_level: 2` — this edits the docs-audit close-gate machinery shared
by every `type: spec` doc and by `close-work-item.mjs`'s close ceremony; it is
not a small single-surface fix (two call sites in docs-audit-core.mjs plus the
shared parser in docs-model.mjs) and it is not on the `protected_paths_l3`
list (checked against docs/ai/docs-audit.yaml: state engine, allocator,
guards, workflow canon only — none of the touched files match). Full pipeline
applies, matching the identical precedent in docs/specs/SPEC-0036-spec-l1-close-gate.md.

## Implementation strategy
- Strategy: tdd
- Rationale: this is a governance-gate behavior change (false PASS -> FAIL)
  on the path `close-work-item.mjs` depends on every ride; both directions
  (the defect reproduced, and the fix proven not to regress a clean table)
  need executable RED->GREEN proof, mirroring SPEC-0036's own strategy for
  the identical defect class.
- RED-proof obligation: before any edit, reproduce the GitHub #330 repro
  verbatim on a fixture (a canonical AC Status table with one non-terminal
  row whose Notes/Evidence cell contains `\|`) — `spec-lint.mjs` reports
  `ac-row-unparseable`, `docs-audit.mjs --gate` PASSes (exit 0) — and add the
  new test stanzas failing against the pre-change engine. Save
  docs/ai/tdd/gate-ac-row-escaped-pipe-blind-red.log.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the shipping working tree (`main`) currently carries
  unrelated uncommitted intake docs from the same `/aai-issues` triage batch
  (other ISSUE-DRAFT/CHANGE-DRAFT files, a regenerated docs/INDEX.md, and one
  ledger event) that do not belong to this scope's diff. A fresh worktree
  branched from a clean commit (`main` @ 7eaeecb) isolates this scope's
  changes from that pre-existing dirty state without requiring anyone to
  triage or discard it first; the fix itself has no parallel-wave conflict
  driver.
- User decision: undecided
- Base ref: main (7eaeecb6c308a4c2ff39a185a6b5822a416bf041)
- Worktree branch/path: <assigned by Implementation Preparation>
- Inline review scope: not applicable while worktree is undecided; if the
  user waives the worktree, the inline diff scope is exactly the explicit
  paths listed below.

Explicit review scope (code_review):
- .aai/scripts/lib/docs-model.mjs (`parseAcTable` gains `declaredIds`)
- .aai/scripts/lib/docs-audit-core.mjs (`unparseableLeanIds` generalized to
  `unparseableAcIds`; wired into `gateContent`'s canonical branches and the
  `status: done` drift check's canonical branch)
- tests/skills/test-aai-docs-audit.sh (new stanzas)
- docs/specs/SPEC-0160-spec-gate-ac-row-escaped-pipe-blind.md,
  docs/issues/ISSUE-0077-gate-ac-row-escaped-pipe-blind.md
- docs/INDEX.md (regenerated, mechanical)

## Design decisions

### D1 — `parseAcTable` gains `declaredIds`, mirroring `parseLeanAcTable` exactly
`declaredIds` is populated from the SAME line set the existing row loop
walks (`lines.slice(sepIdx + 1)`, already `.trim().startsWith('|')`-filtered
by the surrounding `lines` computation — so an indented row is included on
the same terms as a flush one), using the identical extraction regex
`^\s*\|\s*(Spec-AC-\d+)\b` already proven by `parseLeanAcTable`. A row is
pushed to `declaredIds` regardless of whether it later survives the
cell-count check into `rows`. Every existing return branch of `parseAcTable`
(`hasGate: false`, `hasGate: true` with no rows) gains the field too, always
as an array, so no caller needs an `?? []` guard for the new key specifically
(existing callers use `.hasGate`/`.rows` only and are unaffected — additive,
Constitution Art. 5).

### D2 — one reconciliation function serves both table shapes
`unparseableLeanIds(lean)` is renamed `unparseableAcIds(table)`; its body is
unchanged (it already only reads `table.rows` and `table.declaredIds ?? []`,
which both `parseLeanAcTable` and `parseAcTable` now expose identically).
Both existing lean call sites (`gateContent`'s lean branch, the lean done-
drift branch) switch to the new name with no behavior change — a pure
rename, proven by TEST-005's full-suite regression. This is the "reuse
spec-lint's detection... rather than inventing a second heuristic" the intake
asked for, scoped correctly: NOT a fork of spec-lint's own (more complex,
duplicate-aware) reconciliation, which stays as-is with its own test
coverage — see Residual risk below — but a single shared mechanism between
the two GATE-LEVEL consumers (gate + drift check) for BOTH table kinds, so
those two can never diverge from each other.

### D3 — `gateContent`'s canonical branches reconcile before `checkRows`
Both places `gateContent` runs the full canonical `checkRows(ac.rows, true)`
today gain a preceding reconciliation loop:
- the legacy/L2/L3 branch (`!isLeanCeremonyLevel(clRaw)`, when
  `ac.hasGate && ac.rows.length > 0`);
- the lean-eligible-but-volunteering-the-full-table branch
  (`isLeanCeremonyLevel(clRaw) && ac.hasGate && ac.rows.length > 0`) — this
  is the SAME gap SPEC-0036 review F3 flagged and explicitly left open.

Each unparseable declared id becomes its own gate-failure reason: `"<id> is
declared in the AC Status table but its row did not parse (a literal \"|\"
inside a cell breaks the row — reword to remove pipes)"`, mirroring the lean
message's wording and steering (escaping does not help this parser). A fully
parseable canonical table reconciles to itself (`declaredIds` and the parsed
ids match one-to-one) and produces zero new reasons — byte-identical gate
verdicts for the byte-identical case, proven by TEST-001's negative control
and TEST-005's full-suite regression.

### D4 — the `status: done` drift check mirrors the gate, canonical case
The `ac.hasGate && (nonTerminal.length || doneNoEvidence.length)` condition
gains a third disjunct: `unparseableAcIds(ac).length`, computed alongside the
existing `nonTerminal`/`doneNoEvidence` filters over the same `ac.rows`. When
it fires, the verdict is `probable-false-done` and the reason names the
count and the ids: `"<n> AC row(s) unparseable (<ids> — a literal \"|\" in a
cell hides the row's status)"`, matching the lean D3 message shape exactly
minus the word "lean". A done spec whose only non-terminal row was invisible
to the survivor-only check can no longer read as `tracked-done`/aligned.

### D5 — scope boundary: spec-lint.mjs and spec-freeze.mjs are unchanged
`spec-lint.mjs`'s own `ac-row-unparseable` detection (its raw-line rescan
with SPEC-0051's duplicate-id nuance: a row whose SECOND declared copy is
dropped is distinguished from a fully-vanished row) is NOT refactored to
consume the new shared `declaredIds`/`unparseableAcIds` — that nuance has no
equivalent in the simpler presence-only reconciliation this spec adds, and
forcing spec-lint onto it would regress its existing `TEST-003(dupac)`
coverage for no behavior gain (spec-lint already catches this shape
correctly at freeze time; the defect this spec fixes is that the CLOSE PATH
did not). `spec-freeze.mjs` also calls `parseAcTable` directly (to refuse an
untested/unterminated AC at freeze) and inherits NO new check from this
spec — freezing a spec with a to-be-dropped canonical row was already caught
by the mandatory post-freeze `spec-lint.mjs` advisory run
(.aai/PLANNING.prompt.md step 10) before this spec, and stays exactly that
well (or badly) covered after it. Widening either is a larger, separate
scope (see Residual risk).

## Constitution deviations

None.

Honest per-article check (docs/CONSTITUTION.md v1): Art. 1 — makes the close
gate's "complete" claim honest instead of a false positive, strictly
tightening evidence, never weakening it for a clean table (D3 byte-identity);
Art. 2 — one shared parser field + one renamed, unforked function, no new
config surface; Art. 3 — plain `.mjs`/Markdown, no binary/service store;
Art. 4 — a dropped row now degrades to an explicit, named gate FAIL instead
of a silent PASS; Art. 5 — additive field on `parseAcTable`'s return shape,
byte-identical behavior for every doc whose table fully parses; Art. 6 — no
`docs/ai/STATE.yaml` writes from the audit engine; Art. 7 — merge stays
operator-only (this scope ends at `gh pr create`).

## Acceptance Criteria Mapping
- Maps to ISSUE AC (gate must not assert completeness over a partially-parsed
  table)
  - Spec-AC-01: a canonical AC Status table (any `ceremony_level`, including
    absent/2/3, and a lean-eligible doc that volunteers the full table) whose
    parser drops a declared row on a cell-count mismatch (plain `|`, escaped
    `\|`, or an indented broken row) makes `docs-audit.mjs --gate` /
    `--gate-file` FAIL (non-zero exit) naming the dropped Spec-AC id and
    explaining it did not parse — never PASS on the surviving rows. A fully
    parseable canonical table's gate verdict is unchanged (same exit code,
    same reasons) from before this change.
  - Verification: TEST-001, TEST-002.
- Maps to ISSUE Verification bullet (done-drift must not read CLEAN over an
  invisible row)
  - Spec-AC-02: a `status: done` spec whose canonical AC Status table drops
    its only non-terminal declared row to the same parser defect classifies
    `probable-false-done` (via `docs-audit.mjs --check`) naming the row as
    unparseable, not `tracked-done`/CLEAN; rewording the pipe out of the cell
    (with the row's real status intact) restores CLEAN under
    `--check --strict`.
  - Verification: TEST-003.
- Maps to ISSUE Constraints bullet (reuse spec-lint's detection instead of a
  second, diverging heuristic; the two callers must never again disagree)
  - Spec-AC-03: the reconciliation is ONE function (`unparseableAcIds`) fed
    by ONE shared parser field (`declaredIds`, on both `parseAcTable` and
    `parseLeanAcTable`) consumed identically by the gate and the drift check;
    run against the GitHub #330 minimal-spec repro, `spec-lint.mjs --path`
    and `docs-audit.mjs --gate` report the SAME row as the problem (one via
    `ac-row-unparseable`, the other via the gate FAIL reason) instead of
    disagreeing.
  - Verification: TEST-004.
- Maps to ISSUE Constraints bullet (verify against the existing docs-audit /
  close-work-item suites, not just a new isolated fixture; no false negative
  on a clean table)
  - Spec-AC-04: `tests/skills/test-aai-docs-audit.sh`,
    `tests/skills/test-aai-ceremony-levels.sh`,
    `tests/skills/test-aai-spec-lint.sh` and
    `tests/skills/test-aai-close-work-item.sh` stay green; a repo-wide
    `node .aai/scripts/docs-audit.mjs --check --strict --no-event` stays
    CLEAN (exit 0); `generate-docs-index.mjs` stays idempotent; `check-state`
    stays OK.
  - Verification: TEST-005.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Gate FAILs naming a canonical row dropped by the shared parser (plain/escaped/indented); clean table unaffected | done | TEST-001/002, tests/skills/test-aai-docs-audit.sh; commit 2f2f02f; independently RED/GREEN-reproduced in validation round 2 | tdd:2026-09-01 | — |
| Spec-AC-02 | Done-drift check mirrors the gate for the canonical table (probable-false-done, not CLEAN) | done | TEST-003, tests/skills/test-aai-docs-audit.sh; commit 2f2f02f | tdd:2026-09-01 | — |
| Spec-AC-03 | One shared declaredIds field + one shared reconciliation function; spec-lint and --gate never disagree on the #330 repro | done | TEST-004, tests/skills/test-aai-docs-audit.sh; commit 2f2f02f; corpus check over 159 opted-in specs byte-identical pre/post-fix (validation round 2) | tdd:2026-09-01 | duplicate-id one-copy-dropped edge case filed as fu-gate-ac-duplicate-id-pipe-drop (P2), not fixed here |
| Spec-AC-04 | Existing docs-audit/ceremony-levels/spec-lint/close-work-item suites + repo-wide strict audit stay green/CLEAN | done | TEST-005; full framework sweep 84/84 on committed tree, commit 0fae71a; docs-audit --check --strict CLEAN | tdd:2026-09-01 | — |

## Implementation plan
- Components/modules affected: `.aai/scripts/lib/docs-model.mjs`
  (`parseAcTable`), `.aai/scripts/lib/docs-audit-core.mjs` (`gateContent`,
  the `status: done` drift branch, the renamed reconciliation helper).
- Data flows: `parseAcTable(content)` -> `{ hasGate, rows, declaredIds }` ->
  `unparseableAcIds({ rows, declaredIds })` -> gate reasons / drift reasons.
  No new file, no new CLI flag, no schema/frontmatter change.
- Edge cases: a duplicate declared id where only one copy is dropped (the
  SPEC-0051 nuance) is presence-only-reconciled here — it will NOT double-
  report the way `spec-lint.mjs` does, but it also will not silently pass:
  as long as at least one surviving copy carries a matching status, the
  duplicate-id case is unaffected by this change (pre-existing `ac-id-
  duplicate` territory, out of scope); a genuinely fully-vanished id (zero
  surviving copies) is caught exactly as any other unparseable id. An empty
  or heading-absent AC Status table is unaffected (existing `missing AC
  Status table` / `probable-partial` paths, unchanged, no declaredIds to
  reconcile).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                | Description                                                                 | Status  |
|----------|------------|-------------|--------------------------------------|-------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | Canonical (absent/L2/L3) spec with a declared non-terminal row broken by a literal pipe: `--gate` exit 1 naming the row + "did not parse"; escaped-pipe and indented variants also exit 1; negative control (pipe reworded out, all rows terminal) exits 0, byte-identical reasons to pre-change | pending |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | A lean-eligible (ceremony_level 0/1) doc that VOLUNTEERS the full canonical table with a pipe-dropped declared row: `--gate` still exits 1 naming it (closes the SPEC-0036 review-F3 gap) | pending |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh | `status: done` canonical spec whose only non-terminal row is pipe-dropped: `--check` reports NEEDS-TRIAGE probable-false-done naming the row unparseable; reworded -> `--check --strict` CLEAN | pending |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh | GitHub #330 minimal-spec repro run through BOTH `spec-lint.mjs --path` (expect `ac-row-unparseable` for the row) and `docs-audit.mjs --gate` (expect FAIL naming the SAME row) — cross-check assertion, no disagreement | pending |
| TEST-005 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh + test-aai-ceremony-levels.sh + test-aai-spec-lint.sh + test-aai-close-work-item.sh | Full named-suite re-run green post-change; repo-wide `docs-audit.mjs --check --strict --no-event` CLEAN; `generate-docs-index.mjs` idempotent twice; `check-state.mjs` OK | pending |

Seam analysis:
- Seam S1 — `gateContent` is shared by `gateDoc` (worktree file, `--gate`),
  `gateFile` (staged blob via the pre-commit hook, `--gate-file`) and every
  closeout skill that calls them. TEST-001/002/004 drive the real CLI
  end-to-end so the fix lands on the actual close-time path, not a
  reimplementation of it.
- Seam S2 — the done-drift engine feeds `--check` verdicts, the digest, and
  (independently, via its own `parseAcTable` call) `generate-docs-index.mjs`.
  TEST-003 exercises the real `--check`/`--check --strict` CLI on a fixture
  repo; TEST-005 re-runs the repo-wide strict audit and an index regen for
  idempotence, but does NOT extend the reconciliation into the index
  generator itself (see Residual risk).
- Seam S3 — `parseAcTable`'s new `declaredIds` field is a producer two other
  consumers (`spec-freeze.mjs`, `evidence-paths.mjs`, `generate-docs-index.mjs`)
  read the SAME function for, without reading the new field. TEST-005's full
  suite re-run (which exercises all three transitively) is the crossing test
  proving the additive field introduces no regression there.
- Residual risk (recorded, scope boundary D5): `generate-docs-index.mjs` calls
  `parseAcTable` directly and does not reconcile `declaredIds` against
  `rows` — an unparseable canonical row stays invisible to the generated
  index's own summary. Bounded by the fact that the index makes a report,
  not a PASS/FAIL claim the way the close gate does, and by the post-freeze
  `spec-lint.mjs` advisory run (which already catches this shape). Widening
  the index generator is a separate, larger change and is deliberately not
  folded into this fix. `spec-freeze.mjs` is NOT part of this residual risk:
  it carries its own independent `ac-row-unparsed` refusal (raw-line count
  vs. parsed-row count) that already fails freeze on exactly this shape —
  confirmed live during code review, not merely assumed.
- Residual risk (recorded, D5 edge case): a duplicate declared id where one
  copy is dropped is reconciled presence-only here (unlike spec-lint's
  count-aware SPEC-0051 nuance) — bounded because `duplicate-ac-id` already
  flags the duplicate itself at lint time (the sibling rule `ac-id-duplicate`
  requires two surviving, parseable rows and cannot fire for this one-copy-
  dropped shape), and a fully-vanished id (the actually dangerous case) is
  still caught. Filed as `fu-gate-ac-duplicate-id-pipe-drop` (P2) rather than
  folded into this fix, since closing it needs count-aware (multiset)
  reconciliation in the shared function, a small but separate change.
- Registry items closed by this scope: none (`node .aai/scripts/follow-ups.mjs
  list` carries no filed item on this subject; this scope instead resolves
  the informally-recorded residual risk in
  docs/specs/SPEC-0036-spec-l1-close-gate.md's Seam-analysis / review-F3 note).

## Verification
- `bash tests/skills/test-aai-docs-audit.sh` -> exit 0 (all stanzas incl. new
  TEST-001..004).
- `bash tests/skills/test-aai-ceremony-levels.sh` -> exit 0 (unchanged).
- `bash tests/skills/test-aai-spec-lint.sh` -> exit 0 (unchanged — D5
  boundary).
- `bash tests/skills/test-aai-close-work-item.sh` -> exit 0 (unchanged).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0
  CLEAN, run over the real repo.
- `node .aai/scripts/generate-docs-index.mjs` twice -> second run idempotent.
- `node .aai/scripts/check-state.mjs docs/ai/STATE.yaml` -> OK.
- GitHub #330 repro re-run post-fix: `spec-lint.mjs --path` reports
  `ac-row-unparseable`; `docs-audit.mjs --gate` on the SAME fixture now exits
  1 naming the same row (TEST-004).
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal
  status.

## Evidence contract
For each artifact, record: ref_id gate-ac-row-escaped-pipe-blind, Spec-AC and
TEST-xxx links, command, exit code, evidence path
(docs/ai/tdd/gate-ac-row-escaped-pipe-blind-red.log,
docs/ai/tdd/gate-ac-row-escaped-pipe-blind-green.log), diff range when
available.

### Evidence by strategy
Strategy recorded above is `tdd`: stored RED artifact per AC-gating test
(docs/ai/tdd/) plus the full verification matrix, per
`.aai/templates/SPEC_TEMPLATE.md` "Evidence by strategy".
