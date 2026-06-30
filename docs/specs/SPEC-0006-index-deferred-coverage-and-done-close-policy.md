---
id: SPEC-0006
type: spec
status: done
links:
  requirement: null
  rfc: RFC-0001
  debt: DEBT-0001
  pr: []
  commits: []
---

# SPEC-0006 — INDEX whole-doc `deferred` coverage invariant + `done` close-policy (DEBT-0001)

SPEC-FROZEN: true

## Links
- Tech debt (WHAT/WHY): docs/issues/DEBT-0001-index-deferred-gap-and-done-with-live-decisions.md
- AC-tracking authority: docs/rfc/RFC-0001-ac-tracking-and-multi-dev-state.md
- Docs hygiene / drift authority: docs/rfc/RFC-0002-docs-hygiene-and-drift-audit.md
- Prior art (report-only audit classification, TDD'd): docs/specs/SPEC-0003-docs-audit-closeout-candidate.md
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (this doc)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Problem (WHAT/WHY lives in DEBT-0001)
Two systemic gaps, both confirmed against the live code:

1. **Tooling gap — whole-doc `deferred` silently vanishes from `docs/INDEX.md`.**
   `deferred` is a member of `DOC_STATUS_ENUM`
   (`.aai/scripts/lib/docs-model.mjs` lines 7-10) and passes `docs-audit`, but
   `generate-docs-index.mjs` renders doc-level sections only for
   `implementing|accepted|proposed|frozen` (Active), `done`, `draft`,
   `rejected|superseded`, the canonical `type`, and legacy (no-frontmatter).
   Verified via `byStatus(` call sites at lines 233/253/259/283 — there is **no
   `byStatus('deferred')` doc-level section**. The per-AC "Deferred items"
   section (line 265) is a different thing (it lists deferred *AC rows*, not
   deferred *docs*). A doc with frontmatter `status: deferred` therefore renders
   in **zero** doc-level sections, exits 0, and disappears. Nothing asserts that
   every validatable doc lands in ≥1 section, so the failure mode is invisible
   (fail-open) rather than loud.

2. **Process gap — a doc can close `done` with live decisions buried as
   free-text WARNINGs.** The workflow / `VALIDATION.prompt.md` done-transition
   assertion (RFC-0002, prompt lines 121-126) checks the AC table is terminal
   with evidence, but does NOT forbid transitioning to `done` while unresolved
   decisions sit only as prose WARNINGs in the spec body. WARNINGs are not
   tracked, indexed, or gated, so they rot unowned (instance: CHANGE-128 closed
   `done` with open confirmations RR-1/RR-2 as a body WARNING).

The two specific instances (CHANGE-075, CHANGE-128) are already remediated and
are OUT OF SCOPE. This spec delivers the *systemic* mechanisms so neither class
recurs.

## Design decisions (load-bearing — read before implementing)
1. **Deferred section is additive and distinct.** Add a doc-level
   `## Deferred (whole-doc)` section rendering `byStatus('deferred')` (excluding
   canonical, consistent with the other `byStatus` sections). Keep the existing
   per-AC `## Deferred items (per-AC, across all specs)` section untouched. The
   two must never be conflated or double-list the same row.
2. **Coverage invariant is data-driven, not a hardcoded `deferred` check.** The
   generator must compute, for each non-legacy doc, the set of doc-level
   *placement* sections it actually lands in
   (Active / Canonical layer / Done / Drafts / Deferred (whole-doc) /
   Rejected-Superseded). A doc that lands in zero placement sections is a
   coverage violation. This generalizes: any future `DOC_STATUS_ENUM` value
   added without a section is caught automatically — the deferred bug is just
   today's instance. Per-AC / cross-cutting sections (Overdue, per-AC Deferred,
   per-AC Blocked, Broken references, audit sections) do NOT count as placement.
3. **Failure-mode parity with the existing generator.** Under `--strict` /
   `lint-docs` the coverage violation is fatal (exit 1, offending docs named),
   matching the existing strict schema-violation path (lines 152-157). Under the
   default degrade-and-report mode it must NEVER abort: list the zero-section
   docs (reuse the `Skipped`/companion-report machinery or an analogous coverage
   list) and still write a best-effort `docs/INDEX.md`. Legacy docs (no
   frontmatter → Legacy section) are exempt.
4. **Close-policy rule is mechanism + prose.** Prose: add the rule to
   `.aai/workflow/WORKFLOW.md` (Gates/Stop conditions) and `.aai/VALIDATION.prompt.md`
   (extend the 8b done-transition assertion). Mechanism: add a READ-ONLY
   `docs-audit` classification that flags `status: done` docs whose body carries
   an open-decision marker, so the rule is *gated/indexed*, not discipline-only
   (RFC-0001 philosophy: mechanism over discipline).
5. **The done open-decision guard is report-only with a narrow marker.** Mirror
   SPEC-0003's closeout-candidate precedent exactly: NOT added to `hardFail` or
   `needsTriage`; `--check` / `--check --strict` exit codes are unchanged; it
   renders in its own digest section. The marker must be narrow enough to avoid
   false positives on legitimate informational notes (intake constraint):
   default = a body line (outside fenced code blocks) that asserts an OPEN/
   unresolved decision — e.g. a `WARNING`/`> [!WARNING]` line combined with an
   unresolved-decision token (`unresolved`, `open decision`, `must be
   resolved/confirmed/decided`, `pending confirmation/decision`), or an explicit
   `<!-- OPEN-DECISION -->` marker. Implementation MAY refine the exact regex but
   MUST keep the false-positive negative-control test (Spec-AC-06) green. Escalation
   from report to gate is explicitly deferred until the signal is proven clean.
6. **Reuse, do not re-scan.** The coverage invariant reuses the `docs[]` array
   already built in `generate-docs-index.mjs`; the done-guard reuses the
   `docs[]` index and per-doc content already read in `runAudit`
   (`.aai/scripts/lib/docs-audit-core.mjs`). No second filesystem walk.

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD for the three code surfaces — the index `deferred` section, the
  zero-section coverage invariant, and the `docs-audit` open-decision guard —
  because they touch shared engines consumed by CI, pre-commit, and intake
  gating, carry real regression and false-positive risk, and contain
  self-evaluation-trap negative assertions ("informational note is NOT flagged",
  "a zero-section doc DOES fail `--strict`") that only a real RED state can prove
  non-tautological. Loop for the `WORKFLOW.md` / `VALIDATION.prompt.md`
  close-policy prose, which is documentation glue verified by grep. This refines
  the dispatch suggestion by also TDD-ing the audit guard: it is report-only code
  with the identical false-positive profile to the SPEC-0003 closeout-candidate
  guard, which was TDD'd.
- RED-proof obligation (all AC-gating tests, any strategy): every gating test
  must be observed FAILING without the change. Negative assertions (Spec-AC-02
  zero-section fatal, Spec-AC-06 informational-note-not-flagged) embed a
  positive control in the same fixture so the RED is genuine, per the SPEC-0003
  pattern.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: additive, low-risk changes to existing single modules
  (`generate-docs-index.mjs`, `docs-audit-core.mjs`/`docs-audit.mjs`, one test
  file, two prompt files); degrade-and-report keeps the index always producible;
  the guard is report-only and changes no gate exit code; no schema, migration,
  or protected-workflow rewrite. Same inline posture used for the sibling
  SPEC-0003/0004/0005 index/audit work.
- User decision: inline
- Base ref: main
- Worktree branch/path: n/a (inline on main)
- Inline review scope:
  - `.aai/scripts/generate-docs-index.mjs`
  - `.aai/scripts/lib/docs-audit-core.mjs`
  - `.aai/scripts/docs-audit.mjs`
  - `tests/skills/test-aai-docs-audit.sh`
  - `.aai/workflow/WORKFLOW.md`
  - `.aai/VALIDATION.prompt.md`
  - `docs/specs/SPEC-0006-index-deferred-coverage-and-done-close-policy.md`
  - `docs/issues/DEBT-0001-index-deferred-gap-and-done-with-live-decisions.md` (links)

## Acceptance Criteria Mapping

- Maps to: DEBT-0001 Target State (1) / Plan step 1
  - Spec-AC-01: `generate-docs-index.mjs` renders a doc-level
    `## Deferred (whole-doc)` section listing every non-canonical doc whose
    frontmatter `status` is `deferred` (ID / Type / Path), distinct from the
    existing per-AC "Deferred items" section. A doc with `status: deferred`
    appears in `docs/INDEX.md`.
  - Verification: TEST-001.

- Maps to: DEBT-0001 Target State (1) / Plan step 2 / Verification line 2
  - Spec-AC-02: A zero-section coverage invariant computes, per non-legacy doc,
    the doc-level placement sections it lands in; if any non-legacy doc lands in
    zero placement sections, `generate-docs-index.mjs --strict` (and `lint-docs`)
    exits non-zero naming the offending doc(s). The check is data-driven over
    actual section membership (not a hardcoded `deferred` test).
  - Verification: TEST-002.

- Maps to: DEBT-0001 Constraints/Risks ("one malformed doc must never block the index")
  - Spec-AC-03: Under the default (non-strict) mode, a zero-section / edge doc
    never aborts the run: a best-effort `docs/INDEX.md` is always written and the
    offending doc is surfaced (coverage/skipped list + stderr warning), exit 0.
  - Verification: TEST-003.

- Maps to: DEBT-0001 Constraints/Risks ("keep per-AC vs whole-doc deferred distinct; avoid double-listing")
  - Spec-AC-04: No double-listing or regression: a whole-doc `deferred` doc is
    listed once at doc level; a `deferred` AC *row* inside a non-deferred spec
    still renders only in the per-AC "Deferred items" section; the index remains
    idempotent (two runs byte-identical modulo the `Generated:` line).
  - Verification: TEST-004.

- Maps to: DEBT-0001 Target State (2) / Plan step 3
  - Spec-AC-05: `.aai/workflow/WORKFLOW.md` and `.aai/VALIDATION.prompt.md`
    codify the close-policy rule: a doc MUST NOT transition to `status: done`
    while carrying unresolved/open decisions as free-text WARNINGs; such
    decisions MUST be either (a) resolved before close, or (b) promoted to a
    first-class tracked item (a per-AC `blocked`/`deferred` row with `Review-By`,
    or a follow-up tracked doc).
  - Verification: TEST-005.

- Maps to: DEBT-0001 Target State (2) / Plan step 4
  - Spec-AC-06: `docs-audit` gains a READ-ONLY classification that flags a
    `status: done` doc whose body contains an open-decision marker (outside
    fenced code), surfaced in its own digest section. It is report-only: NOT part
    of `hardFail`/`needsTriage`, and does not alter `--check` / `--check
    --strict` exit codes. A `done` doc with an ordinary informational note (no
    open-decision marker) is NOT flagged.
  - Verification: TEST-006.

- Maps to: DEBT-0001 Verification line 3 + Constraints (no regression)
  - Spec-AC-07: No regression — `bash tests/skills/test-aai-docs-audit.sh` passes
    except the known pre-existing `test_index_continue_on_error`; on the real
    repo `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exits 0
    CLEAN and `node .aai/scripts/generate-docs-index.mjs` is idempotent.
  - Verification: TEST-007.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | Doc-level "Deferred (whole-doc)" section; deferred doc appears in INDEX; distinct from per-AC section | done | docs/ai/tdd/red-spec0006-deferred_whole_doc_section.log; docs/ai/tdd/green-spec0006-deferred_whole_doc_section.log; val:2026-06-30T10:20Z | — | TDD RED→GREEN; TEST-001 independently verified by sonnet-4-6 |
| Spec-AC-02 | Data-driven zero-section coverage invariant; --strict/lint-docs exits non-zero naming offending doc | done | docs/ai/tdd/red-spec0006-zero_section_strict_fatal.log; docs/ai/tdd/green-spec0006-zero_section_strict_fatal.log; val:2026-06-30T10:20Z | — | TDD RED→GREEN; RED-proof independently reproduced (strict exited 0 pre-fix) |
| Spec-AC-03 | Default mode degrade-and-report: best-effort INDEX always written, exit 0, gap surfaced | done | docs/ai/tdd/red-spec0006-zero_section_degrade_report.log; docs/ai/tdd/green-spec0006-zero_section_degrade_report.log; val:2026-06-30T10:20Z | — | TDD RED→GREEN; TEST-003 independently verified |
| Spec-AC-04 | No double-listing (whole-doc vs per-AC deferred); index idempotent | done | docs/ai/tdd/red-spec0006-no_double_listing_idempotent.log; docs/ai/tdd/green-spec0006-no_double_listing_idempotent.log; val:2026-06-30T10:20Z | — | TDD RED→GREEN; TEST-004 independently verified |
| Spec-AC-05 | Close-policy rule codified in WORKFLOW.md + VALIDATION.prompt.md | done | docs/ai/tdd/red-spec0006-close_policy_prose.log; docs/ai/tdd/green-spec0006-close_policy_prose.log; val:2026-06-30T10:20Z | — | grep-verified in both files independently; TEST-005 pass |
| Spec-AC-06 | docs-audit report-only open-decision guard for done docs; false-positive negative control | done | docs/ai/tdd/red-spec0006-open_decision_guard.log; docs/ai/tdd/green-spec0006-open_decision_guard.log; val:2026-06-30T10:20Z | — | TDD RED→GREEN; negative control (SPEC-9101 not flagged) confirmed; gate exit 0 |
| Spec-AC-07 | No regression: suite green (except known pre-existing); repo docs-audit CLEAN; index idempotent | done | docs/ai/tdd/green-spec0006-no_regression_real_repo.log; val:2026-06-30T10:20Z | — | Real-repo audit exit 0 CLEAN; index idempotent (2 runs byte-identical); suite exit per test_index_continue_on_error as expected |

Status values: planned | implementing | done | deferred | blocked | rejected.
Gate (per .aai/VALIDATION.prompt.md): any planned/implementing row blocks PASS;
any done row needs non-empty Evidence; deferred/blocked need a future Review-By.

## Implementation plan
- Components/modules affected:
  - `.aai/scripts/generate-docs-index.mjs`:
    - Add `section('Deferred (whole-doc)', byStatus('deferred'), ...)` rendering
      `| ID | Type | Path |` rows (mirror the Done/Drafts renderers), placed with
      the other doc-level status sections.
    - Build a placement-membership map: for each non-legacy doc, record which
      placement section(s) it appears in (derive from the same `byStatus` /
      `isCanonical` predicates used to render). Compute `zeroSection = docs that
      are non-legacy AND in no placement section`. Under `strict`, append to the
      fatal path (exit 1, list docs); otherwise add them to `skipped`/a coverage
      list and keep writing the index.
  - `.aai/scripts/lib/docs-audit-core.mjs`:
    - Add a READ-ONLY post-classification pass (like `closeoutCandidatesFor`)
      that scans each `status: done` doc's body for the open-decision marker
      (outside fenced code) and returns `openDecisionDoneDocs`
      (`[{ id, rel, marker, line }]`) plus a `counts.openDecisionDone` integer.
      Do NOT touch `hardFail`/`needsTriage`.
  - `.aai/scripts/docs-audit.mjs`:
    - Render an "Open decisions on done docs" digest section inside the
      `if (!args.quick)` block; never feed it into the exit-code path.
  - `.aai/workflow/WORKFLOW.md`: add the close-policy Gate + Stop condition.
  - `.aai/VALIDATION.prompt.md`: extend the 8b done-transition assertion with the
    resolve-or-promote rule.
  - `tests/skills/test-aai-docs-audit.sh`: add TEST-001..007 as `test_*`
    functions, registered in `main()` BEFORE `test_index_continue_on_error`
    (the suite is `set -e` and stops at the first failing test, and
    `test_index_continue_on_error` is the known pre-existing failure that must
    stay last).
- Data flows: frontmatter `status`/`type` and doc body already read by both
  scripts; no new git probes; passes stay quick-safe / read-only.
- Edge cases:
  - A doc that is BOTH whole-doc `deferred` AND contains deferred AC rows →
    appears once in "Deferred (whole-doc)" and its AC rows appear in per-AC
    "Deferred items"; no double-count of the same entity.
  - Canonical docs land in "Canonical layer", not a `byStatus` section — the
    coverage invariant must treat "Canonical layer" as a valid placement.
  - Marker inside a fenced code block / inline example must NOT trip the
    done-guard (false-positive guard).

## Seam analysis
- SEAM-1 (index generator → CI / pre-commit gate): the coverage invariant +
  deferred section run in the shared generator that CI and pre-commit invoke with
  `--strict` / `lint-docs`. Risk: the invariant flags an existing real-repo doc
  and breaks CI, or changes exit codes. TEST-007 crosses it end-to-end: run the
  real generator over the real repo and assert exit 0 + idempotence, and run the
  real `docs-audit --check --strict` and assert exit 0 CLEAN.
- SEAM-2 (docs-audit engine → shared exit-code gate): the open-decision guard is
  produced by the engine backing intake gating (`--strict --path`), loop ticks
  (`--quick`), and CI (`--check`). Risk: surfacing it changes a gate exit code.
  TEST-006 crosses it: produce a flagged `done` doc on one side and assert the
  actual `--check --strict` exit code is unchanged AND the section is present —
  not two mocked unit checks. Mirrors SPEC-0003 SEAM-1.
- SEAM-3 (whole-doc deferred section ↔ per-AC deferred items): both consume the
  same `docs[]`/AC model; risk of double-listing or conflating doc-level and
  AC-level deferral. TEST-004 crosses it (a whole-doc deferred doc AND a deferred
  AC row in a non-deferred spec in the same fixture; assert each appears in
  exactly its own section).
- Residual risk (recorded): open-decision marker false positives on legitimate
  informational notes. Mitigated by report-only + narrow marker + the
  TEST-006 negative control; escalation to a gate is deferred until the signal is
  proven clean (per DEBT-0001 constraint).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                | Description | Status |
|----------|------------|-------------|-------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | Fixture doc `status: deferred` → INDEX contains "## Deferred (whole-doc)" listing its id; per-AC "Deferred items" section still present and separate. RED: section absent pre-fix. | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh | A non-legacy doc landing in zero placement sections makes `generate-docs-index.mjs --strict` exit ≠0 naming the doc. RED-proof: pre-fix a `deferred` doc passes `--strict` (exit 0) yet is absent from INDEX (the silent-drop bug); post-fix the invariant fires on a zero-section control. Non-tautological via membership computation. | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh | Default (non-strict) run with a zero-section/edge doc present still writes a best-effort `docs/INDEX.md`, exits 0, and lists the doc in the coverage/skipped report. | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh | Seam: fixture with one whole-doc `deferred` doc AND one non-deferred spec carrying a `deferred` AC row → each appears once in its own section (no double-listing); two generator runs byte-identical modulo `Generated:`. | green |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-docs-audit.sh | grep asserts the close-policy rule text (no `done` with live WARNING decisions; resolve-or-promote to tracked item) is present in both `.aai/workflow/WORKFLOW.md` and `.aai/VALIDATION.prompt.md`. | green |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-docs-audit.sh | A `done` doc with an open-decision marker is flagged in docs-audit's "Open decisions on done docs" section; a `done` doc with an ordinary informational note (positive control) is NOT flagged; `--check --strict --no-event` over the fixture exits 0 (gate unchanged) AND the section is present. RED-proof via the control. | green |
| TEST-007 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh | Regression: full suite green except known `test_index_continue_on_error`; real-repo `docs-audit --check --strict --no-event` exit 0 CLEAN; `generate-docs-index.mjs` idempotent on the real repo. | green |

Test status values: pending → red → green. Every Spec-AC has ≥1 TEST-xxx. Test
IDs are stable; do not renumber after freeze.

## Verification
- `bash tests/skills/test-aai-docs-audit.sh` — TEST-001..007 green; pre-existing
  pass set preserved (only `test_index_continue_on_error` known-fails, as on
  clean main).
- `node .aai/scripts/generate-docs-index.mjs` over a fixture with a
  `status: deferred` doc prints a "Deferred (whole-doc)" section naming it.
- `node .aai/scripts/generate-docs-index.mjs --strict` over a zero-section
  fixture exits ≠0; without `--strict` it exits 0 and writes a best-effort index.
- `node .aai/scripts/docs-audit.mjs --no-event` over a `done`+open-decision
  fixture prints the "Open decisions on done docs" section; `--check --strict`
  over it exits 0 (report-only).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` on the real
  repo exits 0 CLEAN.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id (DEBT-0001 / SPEC-0006)
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY (DEBT-0001 owns WHAT/WHY).
This document does not define workflow.
Use plain Markdown headings and body text. Do not add emoji or decorative icons
unless there is a strong domain-specific reason.
