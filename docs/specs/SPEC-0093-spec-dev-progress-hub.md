---
id: spec-dev-progress-hub
type: spec
number: 93
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0067-dev-progress-hub.md
  rfc: null
  pr:
    - 167
  commits:
    - 2cdf408347828780d04d3fd4c914a5c88daca8b0
---

# Implementation Spec — Dev-progress view in the overview: what the factory is doing right now

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0067-dev-progress-hub.md
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Implementation strategy
- Strategy: tdd
- Rationale: the omission/malformed-line arms are exactly the class of
  silent-degradation bug this scope exists to prevent (a fresh clone or a
  half-written ticks file must never crash or render a misleading section) —
  the RED-GREEN discipline proves the negative-control paths, not only the
  happy render path.

Allowed strategy values:
- loop: implementation agent covers all TEST-xxx entries in one focused pass
- tdd: RED-GREEN-REFACTOR is required per TEST-xxx
- hybrid: TDD for risky/core behavior, loop implementation for low-risk glue or docs
- undecided: planning is incomplete and implementation must not start

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single module (generate-overview.mjs) plus its test
  file, a new spec/brief, and a product doc; small, clearly scoped, no
  protected surface, already isolated on its own feature branch
  (feat/dev-progress-hub).
- User decision: inline
- Base ref: main
- Worktree branch/path: feat/dev-progress-hub (existing branch; no nested worktree)
- Inline review scope: .aai/scripts/generate-overview.mjs, tests/skills/test-aai-overview.sh, docs/specs/SPEC-0093-spec-dev-progress-hub.md, docs/issues/CHANGE-0067-dev-progress-hub.md, docs/product/dev-progress-hub.md, docs/INDEX.md

Allowed worktree recommendation values:
- not_needed: small, low-risk, clearly scoped change
- optional: useful but not important for safety
- recommended: larger, experimental, PR-bound, or parallelizable work
- required: protected workflow/state/schema, migration, or high-risk work; user may still explicitly override inline

Allowed user decision values:
- undecided: no implementation may start when recommendation is recommended or required
- worktree: create/use a git worktree before implementation
- inline: continue in the current working tree with a clean explicit review scope
- waived: user explicitly accepts the risk of ambiguous isolation or review scope

## Acceptance Criteria Mapping
For each requirement AC:

- Maps to: CHANGE AC-001 (fixture STATE + ticks render the section)
  - Spec-AC-01: When docs/ai/STATE.yaml exists with a current focus AND
    docs/ai/LOOP_TICKS.jsonl exists with at least one parseable tick row,
    generate-overview.mjs renders an "In flight now" section showing the
    focus ref/type/phase, a strategy chip, a worktree chip (recommendation
    and user decision), a validation-status chip, a review-status chip, and
    the last 5 ticks newest first with role/scope/duration/harness.
  - Verification: bash tests/skills/test-aai-overview.sh
- Maps to: CHANGE AC-002 (absent-file graceful omission)
  - Spec-AC-02: When docs/ai/STATE.yaml is absent, OR
    docs/ai/LOOP_TICKS.jsonl is absent, OR LOOP_TICKS.jsonl contains zero
    parseable tick rows, the In-flight section is omitted entirely from the
    rendered HTML (no empty section, no error) and in_flight is null in
    overview-data.json; the script exits 0 in every case.
  - Verification: bash tests/skills/test-aai-overview.sh
- Maps to: CHANGE AC-003 (malformed line skip)
  - Spec-AC-03: A JSON-parse-invalid line inside LOOP_TICKS.jsonl is skipped
    without raising an error, and it never occupies one of the 5
    rendered-tick slots — the 5 slots are always chosen from the valid rows
    only, never from a fixed window of the last 5 raw lines.
  - Verification: bash tests/skills/test-aai-overview.sh
- Maps to: CHANGE AC-004 (overview-data.json structured block)
  - Spec-AC-04: overview-data.json carries a top-level in_flight object whose
    focus/strategy/worktree/validation_status/review_status/ticks fields
    hold the exact same values the HTML section rendered from (same tick
    count, same order, same field values); in_flight is the literal value
    null when Spec-AC-02's omission condition applies.
  - Verification: bash tests/skills/test-aai-overview.sh
- Maps to: CHANGE AC-005 (no regression)
  - Spec-AC-05: the existing overview suite (token-economics TEST-005..007)
    stays green after this change with no fixture edits; the full
    tests/skills/test-aai-overview.sh run exits 0.
  - Verification: bash tests/skills/test-aai-overview.sh; PR CI full framework

## Constitution deviations

None.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description                                                              | Status  | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | In-flight section renders focus/phase/strategy/worktree/verdict chips + last 5 ticks newest-first | done | TEST-001/002 green; docs/ai/tdd/red-20260727T084410Z-dev-progress-hub-test_dph01_in_flight_renders_focus_and_chips.log, red-...test_dph02_last_five_ticks_newest_first.log then docs/ai/tdd/green-20260727T084506Z-dev-progress-hub-full-suite.log | -         | -     |
| Spec-AC-02 | Graceful omission on absent STATE / absent or empty ticks, exit 0        | done | TEST-003 green; docs/ai/tdd/red-20260727T084410Z-dev-progress-hub-test_dph03_graceful_omission.log then docs/ai/tdd/green-20260727T084506Z-dev-progress-hub-full-suite.log | -         | -     |
| Spec-AC-03 | Malformed tick line skipped; never consumes a rendered-tick slot         | done | TEST-004 green; docs/ai/tdd/red-20260727T084410Z-dev-progress-hub-test_dph04_malformed_line_no_slot_consumed.log then docs/ai/tdd/green-20260727T084506Z-dev-progress-hub-full-suite.log | -         | -     |
| Spec-AC-04 | overview-data.json in_flight block mirrors the rendered section          | done | TEST-005 green; docs/ai/tdd/red-20260727T084410Z-dev-progress-hub-test_dph05_data_json_mirrors_render.log then docs/ai/tdd/green-20260727T084506Z-dev-progress-hub-full-suite.log | -         | -     |
| Spec-AC-05 | No regression — full overview suite green                                | done | TEST-006 green; docs/ai/tdd/green-20260727T084506Z-dev-progress-hub-full-suite.log (10/10 tests, exit 0) | -         | -     |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan
- Components/modules affected:
  - `.aai/scripts/generate-overview.mjs` — extend the existing minimal
    `readState()` probe (no new YAML dependency) with: the active work item's
    `phase` for the current focus ref (new line-discipline scan of
    `active_work_items`, same house style as `readReleaseMembers`),
    `implementation_strategy.selected`, `worktree.recommendation`,
    `worktree.user_decision`, `last_validation.status`, `code_review.status`.
    Add `readTicks(limit)` reusing the existing generic `readJsonl()` reader
    (which already try/catches per line and skips unparseable JSON) filtered
    to rows shaped like a tick (`role`/`scope` present as strings), then
    `rows.slice(-limit).reverse()` for newest-first. Build an `in_flight`
    model field and an `inFlightSection()` HTML renderer; wire both into
    `buildModel()` / `renderHtml()` alongside the existing sections. Add
    `.chips`/`.chip`/`table.ticks` CSS matching the existing theme-aware
    custom-property style (no new library).
  - `tests/skills/test-aai-overview.sh` — new STATE.yaml and LOOP_TICKS.jsonl
    fixture writers plus TEST-001..006 stanzas (AC-001..004 below).
  - `docs/product/dev-progress-hub.md` — user-facing product doc (user_visible: true).
  - `docs/INDEX.md` — regenerated via `node .aai/scripts/generate-docs-index.mjs`
    (never hand-edited).
- Data flows:
  - docs/ai/STATE.yaml (current_focus, active_work_items[].phase,
    implementation_strategy, worktree, last_validation, code_review) +
    docs/ai/LOOP_TICKS.jsonl (last 5 valid rows) -> `in_flight` model field
    -> both the rendered HTML section and the overview-data.json block (one
    build, two renderers of the SAME model field — no drift possible between
    them by construction).
- Edge cases:
  - STATE.yaml present but `current_focus.ref_id` is null (idle project):
    treated the same as absent STATE for this section (nothing is "in
    flight"); not separately suite-verified (not in the intake AC list) but
    follows the same `in_flight: null` code path as Spec-AC-02.
  - LOOP_TICKS.jsonl has fewer than 5 valid rows: render whatever is
    present (1..4), never pad or error.
  - A JSON-valid but non-tick line (e.g. a stray object missing role/scope):
    dropped by the same shape filter as a truly malformed line — never
    fabricated into a blank row.
  - Never render raw STATE fields beyond the known enum/scalar set above
    (no notes/questions leak beyond the existing `waiting_on_you` question).

## Test Plan
For each Spec-AC, enumerate concrete tests:

| Test ID  | Spec-AC    | Type | File path (expected)              | Description                                                                                   | Status  |
|----------|------------|------|------------------------------------|-------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-overview.sh | Fixture STATE + 6 ticks renders focus ref/type/phase and strategy/worktree/validation/review chips | green |
| TEST-002 | Spec-AC-01 | unit | tests/skills/test-aai-overview.sh | Same fixture: rendered ticks are exactly the last 5, newest first (tick 6..2, tick 1 excluded)  | green |
| TEST-003 | Spec-AC-02 | unit | tests/skills/test-aai-overview.sh | Three sub-cases in one fixture sweep: STATE absent; ticks file absent; ticks file present-but-empty - all omit the section and exit 0 | green |
| TEST-004 | Spec-AC-03 | unit | tests/skills/test-aai-overview.sh | A JSON-parse-invalid line placed second-to-last among 6 valid ticks does not shift or shrink the rendered 5-tick window | green |
| TEST-005 | Spec-AC-04 | unit | tests/skills/test-aai-overview.sh | overview-data.json in_flight block field-for-field matches the TEST-001/002 fixture's rendered values | green |
| TEST-006 | Spec-AC-05 | integration | tests/skills/test-aai-overview.sh | Regression: full suite (existing TEST-005..007 + new TEST-001..005) exits 0                    | green |

Test status values: pending -> red -> green

RED-proof obligation: every AC-gating test above must be observed FAILING
against the unchanged script before its passing counts as evidence. TEST-001
through TEST-005 are the integrity-critical rows and must show a genuine RED
(the section/field does not exist yet). TEST-006 is a regression pin over the
whole file and does not require a separate RED beyond what TEST-001..005
already prove.

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- Test IDs are stable — do not renumber after freeze.
- No table cell above contains a pipe character (AC-table hygiene).

## Seam analysis
- SEAM (one model field feeds two renderers): the same `in_flight` object
  built once in `buildModel()` feeds both the HTML `inFlightSection()` and
  the `overview-data.json` write — there is no second independent
  computation to drift out of sync. Covered end-to-end by TEST-005, which
  reads BOTH the rendered HTML (via the TEST-001/002 fixture) and the JSON
  block from the SAME generator run and asserts field-for-field equality —
  not two isolated unit tests that each mock the other side.
- Residual risk: none identified that lacks an automated test.

## Verification
- Commands to run (derived from Test Plan above):
  - `bash tests/skills/test-aai-overview.sh`
  - `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0093-spec-dev-progress-hub.md`
  - `node .aai/scripts/docs-audit.mjs --check`
  - PR CI: full framework via `.aai/scripts/aai-run-tests.sh`
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: dev-progress-hub
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available
