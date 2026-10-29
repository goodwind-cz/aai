---
id: docs-audit-content-engine-split
type: change
number: null
status: draft
capability: docs-audit-content-engine-split
user_visible: false
links:
  pr: []
  commits: []
---

# Split always-on document-content checks from docs-audit engine regression in CI

## Summary

RFC-0017 phase 2, owner-decided order item 3 (2026-10-22): finish the
docs-audit `node:test` migration and separate always-on document-content
validation from the docs-audit engine regression suite. Today
`aai-docs-audit` is in the always-on core set of the selected skill suite,
and its globs include `docs/issues/**`, `docs/specs/**` and `docs/rfc/**`, so
every pull request, including a one-line document edit, runs the 9,092-line
engine regression suite (`tests/skills/test-aai-docs-audit.sh`). The content
invariants of the corpus are already checked separately by
`docs-audit.mjs --check --strict` in `.github/workflows/docs-numbering.yml`.

## Motivation / Business Value

- Document-only pull requests wait for an engine regression run that cannot
  fail because of their change; RFC-0017 targets an ordinary document-only CI
  gate of at most 60 s median while keeping the actual content and corpus
  invariants.
- Engine regression is still needed whenever the engine, its library, its
  configuration or its tests change; that coverage must not weaken.

## Scope

- In scope:
  - Planning measures, on the current tree, which `test-aai-docs-audit.sh`
    cases exercise the live corpus (content invariants) and which exercise the
    engine on fixtures (engine regression), and their wall time.
  - Content invariants that must hold for every document change stay always-on
    and cheap (the existing `docs-audit --check --strict` gate or a small
    content-only suite), so a document-only pull request still fails on a
    content violation.
  - Engine regression runs only when the engine, its library, configuration,
    prompts it reads, or its tests change (selection by `suite-map.yaml` globs,
    removing `aai-docs-audit` from the always-on core set only if the content
    split leaves no corpus invariant uncovered).
  - Move remaining docs-audit legacy logic cases to `node:test` where Planning
    measures a benefit; keep CLI and real-corpus cases in Bash.
  - Update the RFC-0017 Rollout Status table: phase 2 row reflects this
    delivery; phase 4 row lists CHANGE-0228 (provider adapter registry slice)
    as delivered. The umbrella RFC stays open (phase 5 remains).
- Out of scope:
  - Phase 5 (evidence reuse, process adapters).
  - Changing what docs-audit checks, its exit codes or its findings.
  - The release-notes gate and `watch-ci` issues found on 2026-10-29.

## Affected Area

`tests/skills/suite-map.yaml` (core set and `aai-docs-audit` globs),
`tests/skills/test-aai-docs-audit.sh`, `tests/skills/lib/docs-audit-*.test.mjs`,
possibly `.github/workflows/skill-suite.yml` or `docs-numbering.yml`, the
select-suites tests, `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`
and a measurement note under `docs/analysis/`.

## Desired Behavior (To-Be)

- A document-only pull request runs the content checks and not the engine
  regression suite; a content violation in that pull request still fails CI.
- A pull request touching the docs-audit engine, library, configuration,
  prompts it reads, or its tests selects the full engine regression suite.
- Every case that exists today still runs somewhere; none is dropped.

## Acceptance Criteria

- AC-001: A measurement note classifies every docs-audit test case as content
  (live corpus) or engine (fixture), with wall time per class, measured on the
  current tree with at least five paired runs (median and worst).
- AC-002: A document-only diff (only `docs/issues/**`, `docs/specs/**` or
  `docs/rfc/**` changed) does not select the engine regression suite; shown by
  `select-suites.mjs` on a fixed fixture diff in a test.
- AC-003: A planted content violation in a document-only diff still fails the
  always-on content gate; shown by a test.
- AC-004: A diff touching `.aai/scripts/docs-audit.mjs`,
  `.aai/scripts/lib/docs-audit-core.mjs`, `docs/ai/docs-audit.yaml` or a
  docs-audit test selects the engine regression suite; shown by a test.
- AC-005: The set of test cases before and after is equal (no case dropped);
  shown by a case inventory diff in the measurement note.
- AC-006: Any case moved to `node:test` keeps its assertion; the note reports
  matched before/after time for the moved cluster.
- AC-007: The RFC-0017 Rollout Status table lists this delivery under phase 2
  and CHANGE-0228 under phase 4; the RFC stays `implementing`.

## Verification

- `node .aai/scripts/select-suites.mjs` on fixture diffs (document-only,
  engine) gives the expected selection.
- The docs-audit suites and the select-suites suite pass.
- One full sweep before close.

## Constraints / Risks

- Under-selection risk: the fail-open triad of `suite-map.yaml` (shared
  library, protected L3 paths, unmatched paths) must stay intact.
- Node stdlib only for new test code (docs/TECHNOLOGY.md).
- The content gate in `docs-numbering.yml` is report-only for the numbering
  guard; Planning confirms the strict content check there actually fails the
  job before relying on it.
- Secrets preflight: no secret referenced.

## Notes

- Owner direction 2026-10-29: "pokračuj v tom rfc 17"; order item 3 of the
  owner decisions recorded in RFC-0017 (2026-10-22).
- Assumptions (autopilot): Planning picks the split by measurement; if moving
  `aai-docs-audit` out of the core set would leave a corpus invariant
  uncovered, the ride keeps it in core, delivers the measurement note and the
  `node:test` moves, and says so.
- Intake metrics: autopilot default, human_time_minutes null.
