---
id: spec-token-economics-end-to-end
type: spec
number: 89
status: implementing
ceremony_level: 2
links:
  requirement: null
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — Token economics end-to-end: metrics-report reads usage notes; overview v2 shows tokens per feature

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0063-token-economics-end-to-end.md
- Decision records: SPEC-0043 (loop-token-usage-capture), SPEC-0085 (token-capture-canary, PR #158 marker hardening), SPEC-0053 (deterministic close-ceremony)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Implementation strategy
- Strategy: hybrid
- Rationale: the marker-grammar single-source (Spec-AC-01), the cross-consumer
  boundary equivalence (Spec-AC-01/04 seams), and the close-ceremony
  best-effort regen with its negative control (Spec-AC-06) are telemetry-
  integrity behaviors that must be proven RED first (a fabricated or drifting
  token total is exactly the class of bug this scope exists to close); the
  overview HTML rendering and the Delivered grouping layout (Spec-AC-05) are
  lower-risk formatting wiring where loop-style implementation is adequate.

Allowed strategy values:
- loop: implementation agent covers all TEST-xxx entries in one focused pass
- tdd: RED-GREEN-REFACTOR is required per TEST-xxx
- hybrid: TDD for risky/core behavior, loop implementation for low-risk glue or docs
- undecided: planning is incomplete and implementation must not start

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound scope spanning three-plus independent modules
  (metrics-report, generate-overview, close-work-item) plus a new shared lib
  and a byte-behavior-preserving refactor of the heavily-golden-tested
  metrics-flush. Isolation is useful but not safety-critical: the work is
  already isolated on the dedicated feature branch feat/token-economics-end-to-end,
  so the operator may record an inline decision on that branch rather than
  nesting a further worktree.
- User decision: undecided
- Base ref: feat/token-economics-end-to-end
- Worktree branch/path: (operator decides at preparation)
- Inline review scope: .aai/scripts/lib/usage-note.mjs, .aai/scripts/metrics-flush.mjs, .aai/scripts/metrics-report.mjs, .aai/scripts/generate-overview.mjs, .aai/scripts/close-work-item.mjs, .aai/system/PROFILES.yaml, tests/skills/test-aai-metrics.sh, tests/skills/test-aai-overview.sh, tests/skills/test-aai-close-work-item.sh, docs/specs/SPEC-0089-spec-token-economics-end-to-end.md, docs/issues/CHANGE-0063-token-economics-end-to-end.md

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

- Maps to: CHANGE AC-001 (metrics-report marker sum + per-item and per-role columns)
  - Spec-AC-01: One shared marker grammar. A new `.aai/scripts/lib/usage-note.mjs`
    exports the boundary regex `USAGE_NOTE_RE` and `extractUsageTotal(note)`;
    `metrics-flush.mjs` consumes `USAGE_NOTE_RE` in place of its inlined literal
    with byte-identical match semantics; the raw `usage_total_tokens=` capturing
    regex literal exists in exactly one source file (usage-note.mjs).
  - Spec-AC-02: `metrics-report.mjs` Per Work Item table gains a column named
    `agent tokens (undecomposed)` whose value is the sum of valid delimited
    markers across the item's runs; a malformed value and a prefixed key are not
    counted; the cell renders `n/a` when the item has no valid marker.
  - Spec-AC-03: `metrics-report.mjs` renders a per-role token rollup section
    summing valid markers by run role; the section displays tokens only and
    never derives a USD figure from an undecomposed total.
  - Verification: `bash tests/skills/test-aai-metrics.sh`
- Maps to: CHANGE AC-002 (overview per-item tokens + grand total)
  - Spec-AC-04: `generate-overview.mjs` decorates each delivered item with a
    token total equal to the sum of the same valid markers across that item's
    METRICS runs (null when none), and the counts row exposes the grand total of
    recorded tokens across delivered items.
  - Verification: `bash tests/skills/test-aai-overview.sh`
- Maps to: CHANGE AC-004 (Delivered grouping)
  - Spec-AC-05: In the overview Delivered section a delivered item whose ref is
    named in a release doc's frontmatter member list renders under that release
    heading; an item named by no release falls back to a close-month group
    derived from its close date.
  - Verification: `bash tests/skills/test-aai-overview.sh`
- Maps to: CHANGE AC-003 (close-ceremony best-effort regen + negative control)
  - Spec-AC-06: after a successful, self-verified close, `close-work-item.mjs`
    regenerates the overview data best-effort as its last step; a generator
    failure is swallowed, never changes the close exit code, and never triggers
    a close rollback (the closed doc stays done, close events intact).
  - Verification: `bash tests/skills/test-aai-close-work-item.sh`
- Maps to: CHANGE AC-005 (no regression) plus the new-file companion obligation
  - Spec-AC-07: the targeted suites are green and `PROFILES.yaml` classifies the
    new `usage-note.mjs` exactly once so `test-aai-layer-profiles.sh` stays green.
  - Verification: `bash tests/skills/test-aai-layer-profiles.sh` plus the three
    targeted suites; PR CI runs the full framework.

## Constitution deviations

None.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description                                                                 | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Shared marker grammar in usage-note.mjs; flush consumes it; single-source   | done | TEST-003/004 green; docs/ai/tdd/red-20260726T221908Z-token-economics-test_120_shared_lib_grep_contract.log then docs/ai/tdd/green-20260726T221946Z-token-economics-test_120_shared_lib_grep_contract.log; docs/ai/tdd/green-20260726T222649Z-token-economics-final-metrics-wrapped.log | —         | —     |
| Spec-AC-02 | metrics-report per-item undecomposed-token column; malformed markers ignored | done | TEST-001 green; docs/ai/tdd/red-20260726T221908Z-token-economics-test_122_report_per_item_undecomposed_column.log then docs/ai/tdd/green-20260726T221946Z-token-economics-test_122_report_per_item_undecomposed_column.log | —         | —     |
| Spec-AC-03 | metrics-report per-role token rollup; tokens-only, never USD from totals     | done | TEST-002 green; docs/ai/tdd/red-20260726T221908Z-token-economics-test_123_report_per_role_token_rollup.log then docs/ai/tdd/green-20260726T221946Z-token-economics-test_123_report_per_role_token_rollup.log; real-ledger spot-check docs/ai/tdd/report-20260726T222554Z-token-economics-real-ledger-spot-check.md | —         | —     |
| Spec-AC-04 | overview per-item token total equals METRICS sums; counts grand total        | done | TEST-005/006 green; docs/ai/tdd/red-20260726T222239Z-token-economics-test_005_per_item_tokens_and_grand_total.log then docs/ai/tdd/green-20260726T222337Z-token-economics-overview-suite.log | —         | —     |
| Spec-AC-05 | overview Delivered grouped by release membership, close-month fallback       | done | TEST-007 green; docs/ai/tdd/red-20260726T222239Z-token-economics-test_007_release_grouping_and_close_month_fallback.log then docs/ai/tdd/green-20260726T222649Z-token-economics-final-overview-wrapped.log | —         | —     |
| Spec-AC-06 | close-work-item best-effort overview regen; failure never changes exit/close | done | TEST-008/009 green (TEST-009 genuine RED captured pre-try/catch); docs/ai/tdd/red-20260726T222436Z-token-economics-test_015_overview_regen_failure_negative_control.log then docs/ai/tdd/green-20260726T222649Z-token-economics-final-close-work-item-wrapped.log | —         | —     |
| Spec-AC-07 | targeted suites green; PROFILES classifies usage-note.mjs once               | done | TEST-010 green (test-aai-layer-profiles.sh); docs/ai/tdd/green-20260726T222048Z-token-economics-test010-layer-profiles.log; all 4 targeted suites green via docs/ai/tdd/green-20260726T222649Z-token-economics-final-*-wrapped.log | —         | —     |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan
- Components/modules affected:
  - NEW `.aai/scripts/lib/usage-note.mjs` — the single-source marker grammar.
    Exports `USAGE_NOTE_RE` (the exact boundary regex currently inlined at
    metrics-flush.mjs line 432, no global flag) and `extractUsageTotal(note)`
    returning the integer total of the first match or null. Node stdlib only.
  - `.aai/scripts/metrics-flush.mjs` — replace the inlined regex literal in
    buildEntry with `USAGE_NOTE_RE` imported from the new lib. Match semantics
    unchanged (still `note.match(USAGE_NOTE_RE)`, first capture group), so the
    undecomposed-note INFO vs capture-missing WARNING classification and every
    existing golden stay byte-identical.
  - `.aai/scripts/metrics-report.mjs` — add the Per Work Item `agent tokens
    (undecomposed)` column and a new per-role token rollup section, both fed by
    `extractUsageTotal` summed over runs. No USD is ever computed from these
    totals (pricing needs an in/out split the markers do not carry).
  - `.aai/scripts/generate-overview.mjs` — decorate each item with a summed
    token total via the shared lib; add the grand total to counts; group the
    Delivered section by release membership with a close-month fallback.
  - `.aai/scripts/close-work-item.mjs` — add a best-effort overview-data regen
    as the final step of a successful close (after self-verify and brief prune),
    wrapped so any generator failure is caught, logged, and swallowed.
  - `.aai/system/PROFILES.yaml` — classify usage-note.mjs once under `core`
    (companion obligation for the new `.aai/**` file; mirrors lib/pricing.mjs).
- Data flows:
  - agent run note text -> USAGE_NOTE_RE -> integer total; summed per item and
    per role (report) and per delivered item plus grand total (overview).
  - release doc frontmatter member list -> item ref membership -> Delivered
    grouping; unmatched items -> close-month bucket from EVENTS close date.
  - successful close -> spawn generate-overview (best-effort) -> overview-data.json.
- Release membership convention (additive, backward compatible): a release doc
  may carry an additive frontmatter member list of work-item refs (slug id or
  display id) under its links block. REL-0001 carries none today, so all its
  members deterministically take the close-month fallback path (proves AC-004's
  fallback arm).
- Edge cases:
  - A run whose tokens_in and tokens_out are both present AND also carries a
    marker: the report/overview token columns count the marker sum consistently
    with flush's INFO/WARNING classification (seam test pins agreement).
  - Malformed marker (usage_total_tokens=1x) and prefixed key
    (not_usage_total_tokens=1) are never counted anywhere.
  - Item with no marker in any run: report cell n/a, overview total null.
  - Item with a null close date: falls into a deterministic undated bucket.
  - Generator failure at close: swallowed; close exit code and durable close
    outcome unchanged.

## Test Plan
For each Spec-AC, enumerate concrete tests:

| Test ID  | Spec-AC    | Type        | File path (expected)                       | Description                                                                                             | Status  |
|----------|------------|-------------|--------------------------------------------|--------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-02 | unit        | tests/skills/test-aai-metrics.sh           | Per Work Item undecomposed-token column sums valid markers; malformed and prefixed markers ignored; n/a when none | green |
| TEST-002 | Spec-AC-03 | unit        | tests/skills/test-aai-metrics.sh           | Per-role token rollup section sums valid markers by role; no USD derived from totals                    | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-metrics.sh           | Single-source grep contract: flush and report import USAGE_NOTE_RE from usage-note.mjs; raw regex literal only in the lib; flush goldens stay green | green |
| TEST-004 | Spec-AC-01 | integration | tests/skills/test-aai-metrics.sh           | Seam: a note flush classifies undecomposed-INFO is counted by report; a malformed note flush drops is ignored by report (all consumers agree) | green |
| TEST-005 | Spec-AC-04 | unit        | tests/skills/test-aai-overview.sh          | overview-data.json per-item token total equals METRICS marker sums; counts grand total equals the sum across delivered items | green |
| TEST-006 | Spec-AC-04 | integration | tests/skills/test-aai-overview.sh          | Seam: overview per-item token sum equals metrics-report per-item sum on the same METRICS fixture        | green |
| TEST-007 | Spec-AC-05 | unit        | tests/skills/test-aai-overview.sh          | Delivered grouping: item named by a release member list renders under that release; unnamed item takes close-month fallback | green |
| TEST-008 | Spec-AC-06 | integration | tests/skills/test-aai-close-work-item.sh   | Seam: close on a fixture root regenerates overview-data.json best-effort and exits 0                    | green |
| TEST-009 | Spec-AC-06 | integration | tests/skills/test-aai-close-work-item.sh   | Negative control: a rigged generator failure leaves close exit 0, the doc still done, and close events intact (no rollback) | green |
| TEST-010 | Spec-AC-07 | unit        | tests/skills/test-aai-layer-profiles.sh    | PROFILES classifies usage-note.mjs exactly once; layer-profiles suite green                             | green |
| TEST-011 | Spec-AC-07 | integration | tests/skills/test-aai-metrics.sh           | Regression: existing flush and report goldens stay green after the shared-lib refactor                  | green |

Test status values: pending -> red -> green

RED-proof obligation: every AC-gating test above must be observed FAILING
against the unchanged scripts before its passing counts as evidence. TEST-003,
TEST-004, TEST-008, and TEST-009 are the integrity-critical rows and must show a
genuine RED. TEST-011 is a regression pin (already green pre-change) and does not
require a RED.

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- Test IDs are stable — do not renumber after freeze.
- No table cell above contains a pipe character (AC-table hygiene).

## Seam analysis
- SEAM 1 (marker grammar shared by three writers/readers): metrics-flush
  produces the INFO/WARNING classification; metrics-report and generate-overview
  read the same grammar to sum. Covered end-to-end by TEST-004 (one fixture note
  run through flush AND report, asserting agreement) plus the single-source
  contract TEST-003. Not two mocked unit tests — the same note text crosses the
  boundary.
- SEAM 2 (METRICS ledger consumed by two reporters): the overview per-item token
  sum and the report per-item sum must agree for the same ledger. Covered by
  TEST-006 (both run on one fixture, totals asserted equal).
- SEAM 3 (close-ceremony invokes the overview generator): the close writes the
  durable close, then regenerates the overview data. Covered by TEST-008
  (regen happens, close succeeds) and TEST-009 (generator failure cannot harm
  the close). Ordering constraint: regen is strictly the last step, after
  self-verify passes, so a regen failure can never reach the rollback path.
- Residual risk: none identified that lacks an automated test.

## Verification
- Commands to run (derived from Test Plan above):
  - `bash tests/skills/test-aai-metrics.sh`
  - `bash tests/skills/test-aai-overview.sh`
  - `bash tests/skills/test-aai-close-work-item.sh`
  - `bash tests/skills/test-aai-layer-profiles.sh`
  - `node .aai/scripts/metrics-report.mjs` (spot-check on the real ledger)
  - PR CI: full framework via `.aai/scripts/aai-run-tests.sh`
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: token-economics-end-to-end
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available
