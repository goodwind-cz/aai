---
id: spec-ci-test-impact-selection
type: spec
number: 97
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0071-ci-test-impact-selection.md
  rfc: null
  pr:
    - 171
  commits:
    - 7df1d74d75eba3aededa71336accca78714a4996
---

# Implementation Spec — CI test impact selection: PR pushes run affected suites, full framework moves to merge + nightly

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0071-ci-test-impact-selection.md
- Decision records: operator direction 2026-07-27 ("efektivneji v CI vybrano aby nebezelo vzdy vse")
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: the selector's own correctness IS the safety property (a bug
  that under-selects silently drops CI coverage on real PRs) — the exact
  regression class RED-first testing exists to prove is actually held. The
  fail-open triad (unmapped / shared-lib / protected-l3) and the always-
  exit-0 / never-fail-the-build contract are integrity properties that would
  be invisible to a loop-style implement-then-check pass; each needs a test
  that was observed failing against the pre-implementation state. The
  workflow YAML wiring and suite-map authoring are lower-risk glue but stay
  inside the same disciplined pass rather than splitting strategy, since the
  workflow grep-contract test (TEST-013) and the selector tests share one
  suite file and one RED/GREEN cycle.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: CI-wide blast radius (a selector bug affects every
  future PR's test coverage) and a multi-file scope (new script, new data
  file, workflow YAML, two test suites, PROFILES.yaml, product doc) place
  this above `not_needed`/`optional`. Not `required`: no protected L3
  surface is touched (verified against `protected_paths_l3` below) and
  nothing here is an irreversible migration.
- User decision: inline
- Base ref: main
- Worktree branch/path: feat/ci-test-impact-selection (current branch)
- Inline review scope: tests/skills/suite-map.yaml, .aai/scripts/select-suites.mjs, .github/workflows/skill-suite.yml, tests/skills/test-aai-suite-select.sh, tests/skills/test-aai-hygiene-pack.sh, .aai/system/PROFILES.yaml, docs/product/ci-test-impact-selection.md, docs/specs/SPEC-0097-spec-ci-test-impact-selection.md, docs/issues/CHANGE-0071-ci-test-impact-selection.md

## Acceptance Criteria Mapping
For each requirement AC:

- Maps to: AC-001 (intake)
- Spec-AC-01: `tests/skills/suite-map.yaml` carries one row per existing `tests/skills/test-aai-*.sh` suite (watched-path globs, generous by design); `.aai/scripts/select-suites.mjs`, given a changed-path diff and the map, prints exactly the suites whose globs match at least one changed path (`SELECTED <suite> reason=<path>`), plus the three always-on core suites (`CORE <suite> reason=core`: aai-check-state, aai-docs-audit, aai-spec-lint) unconditionally, regardless of the diff.
- Verification: `bash tests/skills/test-aai-suite-select.sh` (TEST-001, TEST-002, TEST-003, TEST-004, TEST-012) exit 0.

- Maps to: AC-002 (intake)
- Spec-AC-02: the selector fails OPEN to `FULL_RUN reason=<trigger> path=<path>` (never a narrowed suite list) on any of three triggers, checked in this priority order: (1) `protected-l3` — a changed path exactly matches an entry in `docs/ai/docs-audit.yaml` `protected_paths_l3` (read live, never duplicated); (2) `shared-lib` — a changed path matches `.aai/scripts/lib/**`; (3) `unmapped` — a changed path matches no suite's glob list at all. The whole diff is scanned before any `SELECTED`/`CORE` line is emitted, so a fail-open trigger anywhere in the diff never leaks partial selection output.
- Verification: `bash tests/skills/test-aai-suite-select.sh` (TEST-005, TEST-006, TEST-007, TEST-008, TEST-009) exit 0.

- Maps to: AC-003 (intake)
- Spec-AC-03: every `tests/skills/test-aai-*.sh` file on disk has a corresponding row in `tests/skills/suite-map.yaml` (`<name>` = filename with `test-` stripped and `.sh` stripped); a new suite added without a row fails a pinned check in `tests/skills/test-aai-hygiene-pack.sh`.
- Verification: `bash tests/skills/test-aai-hygiene-pack.sh` (TEST-014 / `test_090_suite_map_pin`) exit 0; RED-proofed against a fixture missing one row.

- Maps to: AC-004 (intake)
- Spec-AC-04: `.github/workflows/skill-suite.yml` gains a `select` job that (a) on `pull_request` events without the `ci-full` label runs `select-suites.mjs` against the PR's base ref and emits `mode=selected` + the suite list, or `mode=full` on a `FULL_RUN` verdict; (b) on every other trigger (`push` to main, `schedule`, `workflow_dispatch`) and on any `ci-full`-labeled PR, emits `mode=full` unconditionally. `skills-selected` runs each selected suite via `bash tests/skills/test-framework.sh --skill <name>` (reusing the existing exit-42-is-SKIP contract, never a hand-rolled runner); `skills-full` runs the unchanged full `test-framework.sh`. The pre-existing `self-hosting-smoke` job's own trigger/step semantics are preserved unconditioned by selection.
- Verification: grep contracts in `tests/skills/test-aai-suite-select.sh` (TEST-013) exit 0; live: this PR's own CI run on GitHub Actions shows the `select` job choosing a mode and the corresponding job running (evidence recorded at PR time, outside this local TDD cycle).

- Maps to: AC-005 (intake)
- Spec-AC-05: selection output is fully auditable — every `SELECTED` line carries `reason=<matched path>`; exactly one `DROPPED <n>` line is printed, `n` being the exact count of non-core suites that matched no changed path (no silent truncation, no missing count); the CLI's own usage/internal errors (missing `--base-ref`/`--files-from`, unreadable map, bad base-ref) always degrade to a `FULL_RUN reason=internal-error` line and exit 0 — the selector's own failure never fails the build.
- Verification: `bash tests/skills/test-aai-suite-select.sh` (TEST-010, TEST-011) exit 0.

- Maps to: AC-006 (intake)
- Spec-AC-06: no regression — `test-aai-suite-select.sh`, the `test-aai-hygiene-pack.sh` pin stanza, and `test-aai-layer-profiles.sh` (Spec-AC-07) are green locally; this PR's own CI run demonstrates the selected-suites path end-to-end (live evidence, PR-time).
- Verification: wrapper run of the three targeted suites exit 0 (TEST-016); PR CI green (recorded at PR time).

- Maps to: Companion obligation (Planning step 3a — new `.aai/**` file)
- Spec-AC-07: the new `.aai/scripts/select-suites.mjs` is classified in `.aai/system/PROFILES.yaml` under `core:` (it gates every PR's CI run — workflow-engine class, alongside `docs-audit.mjs`/`spec-lint.mjs`), keeping the layer-profiles 100%-classified invariant intact.
- Verification: `bash tests/skills/test-aai-layer-profiles.sh` (TEST-001) exit 0.

## Constitution deviations

None.

## Companion obligations (Planning step 3a)
- Prompt-corpus diet ledger: NOT triggered. This change adds no bytes to
  `.aai/*.prompt.md` or `.aai/AGENTS.md` — the new files are a `.mjs`
  script, a `.yaml` data file, a workflow YAML, and test/doc files.
- New `.aai/**` file classification: TRIGGERED. `.aai/scripts/select-suites.mjs`
  is a new file under `.aai/`. It has been added to `.aai/system/PROFILES.yaml`
  `core:` (Spec-AC-07 / TEST-015) so `test-aai-layer-profiles.sh` TEST-001
  (100%-classified invariant) stays green.

## Implementation plan
- Components/modules affected:
  - NEW `tests/skills/suite-map.yaml` — hand-authored, hand-rolled-parser-
    friendly YAML (not general YAML — a fixed 3-level schema documented in
    its own header comment): `core:` (the 3 always-on suites),
    `full_run_triggers.shared_lib_globs` (`.aai/scripts/lib/**`), and
    `suites.<name>.globs` — one row per existing `test-aai-*.sh` suite,
    built from each suite's own header comment / grepped source references,
    deliberately generous (over-selection is safe).
  - NEW `.aai/scripts/select-suites.mjs` — zero-dep Node stdlib CLI.
    `--base-ref <ref>` drives `git diff --name-only <ref>...HEAD`;
    `--files-from <path|->` injects a newline-separated path list instead
    (the deterministic test hook). Hand-rolled glob matcher (`*`/`**` only —
    no npm minimatch, per the zero-dependency constraint). Hand-rolled
    suite-map parser and a `protected_paths_l3` reader for
    `docs/ai/docs-audit.yaml` (read live — never duplicated into
    suite-map.yaml, avoiding a second source of truth). Exit code is ALWAYS
    0; every internal error path (bad args, unreadable files, git failure)
    prints `FULL_RUN reason=internal-error path=<message>` instead of a
    non-zero exit — selection must never fail the build itself.
  - `.github/workflows/skill-suite.yml` — new `select` job (always runs,
    resolves `mode=full|selected` + the suite list as job outputs on every
    trigger type, so downstream jobs never depend on a conditionally-
    skipped job's outputs); `skills-selected` (PR, mode=selected) loops
    `test-framework.sh --skill <name>`; `skills-full` (mode=full, i.e. push-
    to-main / schedule / workflow_dispatch / ci-full-labeled PR / selector
    FULL_RUN) runs the unchanged full suite; `self-hosting-smoke` untouched
    in trigger/step semantics (new nightly `schedule` trigger on the whole
    workflow now also fires it, a deliberate widening documented in the
    workflow's own header comment).
  - `tests/skills/test-aai-hygiene-pack.sh` — new `test_090_suite_map_pin`
    stanza (every `test-aai-*.sh` has a suite-map row).
  - `.aai/system/PROFILES.yaml` — classify the new script under `core:`.
  - NEW `docs/product/ci-test-impact-selection.md` — user-visible feature
    doc (`user_visible: true` on the primary CHANGE doc).
- Data flows:
  - Producer -> selector: `git diff --name-only` (or `--files-from` in
    tests) yields the changed-path list.
  - suite-map.yaml + docs-audit.yaml (protected_paths_l3) -> selector: read
    at invocation time, never cached, never duplicated.
  - selector stdout -> workflow `select` job: parsed via `grep`/`awk` into
    `GITHUB_OUTPUT` `mode` + `suites`.
  - `select` job outputs -> `skills-selected`/`skills-full` job `if:`
    conditions and the per-suite loop.
- Edge cases:
  - Empty diff (no changed files): CORE lines only, `DROPPED` = every non-
    core suite, exit 0 (TEST-004).
  - A single changed path matching multiple suites: every matching suite
    gets its own `SELECTED` line (TEST-002).
  - A diff where every suite's surface is touched: `DROPPED 0` (TEST-003).
  - An unmapped path anywhere in a large diff: FULL_RUN fires with the
    FIRST unmapped path found; no partial `SELECTED`/`CORE` output leaks
    first (TEST-009).
  - A near-miss path (e.g. `.aai/scripts/state.mjs.bak`, not an exact
    protected-l3 match, not under `.aai/scripts/lib/`) must NOT misfire a
    fail-open trigger — it falls through to ordinary unmapped/mapped
    handling (TEST-008, negative control).
  - Selector internal errors (missing args, unreadable map, bad git ref):
    always `FULL_RUN reason=internal-error`, exit 0 (TEST-011).
- Honest limitation (intake Constraints, Risk): the suite-map is hand-
  authored and can drift from actual suite coverage over time; the hygiene
  pin only proves every suite HAS a row, not that the row's globs are
  complete. The post-merge full gate (push-to-main) and the nightly full
  run are the backstop for a coupling the map misses — documented in the
  workflow's own header comment, not hidden.

## Design decisions
- D1 — `protected_paths_l3` is read live from `docs/ai/docs-audit.yaml` at
  every invocation rather than copied into `suite-map.yaml`: a second copy
  would silently drift the moment either the L3 policy or the map changed
  without the other. Cost: one extra file read per invocation, paid
  gladly for a single source of truth (Constitution Article 2, simplicity).
- D2 — the suite-map parser and the glob matcher are hand-rolled rather than
  pulling a YAML/minimatch dependency: `docs/TECHNOLOGY.md` forbids adding
  any package manifest/lockfile, and every other structural reader in this
  repo (`guard-config.mjs`, the `PROFILES.yaml` parser, `state.mjs`) already
  hand-rolls its exact schema instead of a general parser. `suite-map.yaml`
  documents in its own header that it is NOT general YAML.
- D3 — matching runs over EVERY suite (core included) per changed path
  before deciding "unmapped", not just the non-core suites: a path that only
  touches a core suite's own source (e.g. `.aai/scripts/check-state.mjs`)
  must count as mapped (core always runs already) rather than incorrectly
  escalating to FULL_RUN. Only non-core matches produce a `SELECTED` line.
  TEST-001's DROPPED-count assertion pins this arithmetic.
- D4 — exit code is unconditionally 0: this is a CI-*selection* helper, not
  a gate. A bug in the selector must degrade to the safe default (full
  coverage) rather than failing the workflow outright and blocking every PR
  on a selector regression. TEST-011 pins this across every error path.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description                                                        | Status | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | selector selects exact mapped suites + core always present         | done   | tests/skills/test-aai-suite-select.sh TEST-001/002/003/004/012; docs/ai/tdd/green-20260727T164524Z-TEST-001-013.log | — | — |
| Spec-AC-02 | fail-open triad (unmapped/shared-lib/protected-l3), no partial leak | done   | tests/skills/test-aai-suite-select.sh TEST-005/006/007/008/009; same green log | — | — |
| Spec-AC-03 | suite-map hygiene pin — every suite mapped                         | done   | tests/skills/test-aai-hygiene-pack.sh test_090; docs/ai/tdd/red-20260727T164549Z-TEST-014-pin.log, green-20260727T164553Z-hygiene-pack-full.log | — | — |
| Spec-AC-04 | workflow wires selector on PR; full on push/schedule/ci-full       | done | tests/skills/test-aai-suite-select.sh TEST-013; LIVE: PR #171 run https://github.com/goodwind-cz/aai/actions/runs/30289358425 — select job pass (mode=full, honest fail-open on unmapped docs), skills-selected skipped, skills-full pass, gate job green under the pre-split required-check name | — | first CI run also proved the fail path live (TEST-012 fixture default-branch bug -> gate correctly reported fail) |
| Spec-AC-05 | auditable output (reason=, single accurate DROPPED line), exit 0 always | done | tests/skills/test-aai-suite-select.sh TEST-010/011; same green log | — | — |
| Spec-AC-06 | no regression — targeted suites green; PR CI green end-to-end       | done | wrapper run of 3 targeted suites green locally; LIVE: full framework 55/55 pass on PR #171 run https://github.com/goodwind-cz/aai/actions/runs/30289358425 | — | — |
| Spec-AC-07 | new script classified in PROFILES core, layer-profiles invariant OK | done   | tests/skills/test-aai-layer-profiles.sh TEST-001 green (manifest conformance: core=131 total=187, 100%) | — | — |

Status values: planned | implementing | done | deferred | blocked | rejected

## Seam analysis
- SEAM-1 (suite-map.yaml -> select-suites.mjs -> workflow `select` job): the
  map is authored once and consumed by both the selector's own tests AND the
  real workflow. Covered end-to-end by TEST-012 (real git fixture repo,
  actual `git diff --name-only` through the real selector — not two mocked
  halves) and by TEST-013 (grep contract proving the workflow actually
  invokes `select-suites.mjs`, not a hypothetical wiring).
- SEAM-2 (docs-audit.yaml `protected_paths_l3` -> select-suites.mjs): the L3
  policy is OWNED by docs-audit.yaml (consulted elsewhere by the ceremony
  gate) and READ by the selector. TEST-007 crosses this seam for real: a
  fixture `docs-audit.yaml` is read by the actual parser, not a mocked list.
- SEAM-3 (test-aai-*.sh inventory -> suite-map.yaml -> hygiene pin): the pin
  (test_090) reads the REAL `tests/skills/` directory listing and the REAL
  `suite-map.yaml`, RED-proofed against a fixture with one row renamed away
  (docs/ai/tdd/red-20260727T164549Z-TEST-014-pin.log) so the check
  genuinely discriminates rather than trivially passing.
- Residual risk: the workflow's LIVE behavior on GitHub Actions (job
  skip/run semantics, `needs.select.outputs` propagation across the actual
  Actions runtime) cannot be exercised by a local bash/node test — only
  local YAML structure and grep contracts are proven here. Spec-AC-04 and
  Spec-AC-06 are `deferred` with a Review-By date rather than
  fabricated `done`, pending this PR's real CI run (evidence contract below
  names exactly what to attach when it lands).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                          | Description                                                                                   | Status  |
|----------|------------|-------------|------------------------------------------------|-------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-suite-select.sh           | mapped diff selects exactly the matched suites + core always present; DROPPED arithmetic pinned | green   |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-suite-select.sh           | fixture diversity: one changed path matching multiple suites selects ALL of them (multi-writer) | green   |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-suite-select.sh           | fixture diversity: every suite's surface touched -> DROPPED 0 (zero-remainder)                  | green   |
| TEST-004 | Spec-AC-01 | unit        | tests/skills/test-aai-suite-select.sh           | fixture diversity: empty diff -> core only, exit 0 (degenerate/empty)                           | green   |
| TEST-005 | Spec-AC-02 | unit        | tests/skills/test-aai-suite-select.sh           | unmapped path forces FULL_RUN naming the triggering path                                        | green   |
| TEST-006 | Spec-AC-02 | unit        | tests/skills/test-aai-suite-select.sh           | .aai/scripts/lib/** change forces FULL_RUN reason=shared-lib                                    | green   |
| TEST-007 | Spec-AC-02 | integration | tests/skills/test-aai-suite-select.sh           | SEAM-2: a real docs-audit.yaml protected_paths_l3 path forces FULL_RUN reason=protected-l3      | green   |
| TEST-008 | Spec-AC-02 | unit        | tests/skills/test-aai-suite-select.sh           | fixture diversity: negative control — near-miss path does not misfire L3/shared-lib             | green   |
| TEST-009 | Spec-AC-02 | unit        | tests/skills/test-aai-suite-select.sh           | fixture diversity: mid-operation — an unmapped path anywhere suppresses ALL partial output       | green   |
| TEST-010 | Spec-AC-05 | unit        | tests/skills/test-aai-suite-select.sh           | every SELECTED line carries reason=; exactly one DROPPED line; count is exact                    | green   |
| TEST-011 | Spec-AC-05 | unit        | tests/skills/test-aai-suite-select.sh           | missing args / unreadable map / bad base-ref all degrade to FULL_RUN, exit 0 always              | green   |
| TEST-012 | Spec-AC-01 | integration | tests/skills/test-aai-suite-select.sh           | SEAM-1: real git fixture repo, --base-ref drives an actual git diff --name-only end-to-end       | green   |
| TEST-013 | Spec-AC-04 | integration | tests/skills/test-aai-suite-select.sh           | SEAM-1: skill-suite.yml grep contracts — selector wiring + full-run triggers present              | green   |
| TEST-014 | Spec-AC-03 | integration | tests/skills/test-aai-hygiene-pack.sh           | SEAM-3: every real test-aai-*.sh has a real suite-map.yaml row; RED-proofed against a missing row | green   |
| TEST-015 | Spec-AC-07 | integration | tests/skills/test-aai-layer-profiles.sh         | new script classified under PROFILES core; 100%-classified invariant holds                       | green   |
| TEST-016 | Spec-AC-06 | integration | (wrapper: the 3 targeted suites above)          | no regression — targeted suites green locally; PR CI full-run evidence attached at PR time       | green   |

Test status values: pending -> red -> green

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- RED-proof obligation (all AC-gating tests, regardless of strategy): the
  whole `test-aai-suite-select.sh` suite (TEST-001..013) was observed
  FAILING against the pre-implementation tree (script absent) —
  docs/ai/tdd/red-20260727T164423Z-TEST-001-012.log. TEST-014's pin stanza
  was independently RED-proofed against a fixture with one suite-map row
  renamed away — docs/ai/tdd/red-20260727T164549Z-TEST-014-pin.log.
- Test IDs are stable — do not renumber after freeze.

## Verification
- Commands to run:
  - `bash tests/skills/test-aai-suite-select.sh`
  - `bash tests/skills/test-aai-hygiene-pack.sh`
  - `bash tests/skills/test-aai-layer-profiles.sh`
  - `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0097-spec-ci-test-impact-selection.md`
  - `node .aai/scripts/docs-audit.mjs --check`
  - Live: this PR's own CI run on GitHub Actions (Spec-AC-04/06 evidence).
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal
  status (Spec-AC-04/06 currently `deferred`, Review-By 2026-08-15,
  pending the live PR CI run) AND the three targeted suites green locally.

## Evidence contract
For each artifact, record: ref_id; Spec-AC and TEST-xxx links; command or
review scope; exit code or review verdict; evidence path; commit SHA or diff
range when available.

- Spec-AC-01/02/05: `bash tests/skills/test-aai-suite-select.sh` exit 0 —
  docs/ai/tdd/red-20260727T164423Z-TEST-001-012.log,
  docs/ai/tdd/green-20260727T164524Z-TEST-001-013.log.
- Spec-AC-03: `bash tests/skills/test-aai-hygiene-pack.sh` exit 0 —
  docs/ai/tdd/red-20260727T164549Z-TEST-014-pin.log,
  docs/ai/tdd/green-20260727T164553Z-hygiene-pack-full.log.
- Spec-AC-04: TEST-013 grep contracts green in the same suite-select log
  above. Live CI run: attach the GitHub Actions run URL to this row once
  this branch is opened as a PR (SKILL_PR ceremony).
- Spec-AC-06: wrapper run of the three targeted suites, all exit 0 (same
  logs as above). Live CI run: same PR-time attachment as Spec-AC-04.
- Spec-AC-07: `bash tests/skills/test-aai-layer-profiles.sh` exit 0 (TEST-001
  manifest conformance: core=131 extended=56 total=187, 100%).
- Code review dispositions (dual-verdict pass, functional PASS / quality
  CONCERNS, 2026-07-27): (1) core-name charset asymmetry — REMEDIATED in
  tree: `parseSuiteMap` now rejects core entries violating `[A-Za-z0-9_-]+`
  (throw -> `FULL_RUN reason=internal-error`, never emitted to the workflow
  shell); pinned by TEST-017. (2) required-check continuity — REMEDIATED in
  tree: branch protection requires the pre-split check name, and the
  mutually-exclusive selected/full leaf jobs never both report; an
  aggregating `gate` job keeps the exact required name
  ("skill test suite (tests/skills/, via test-framework.sh)"), runs on
  `always()`, and fails unless the mode-relevant leaf succeeded; pinned by
  TEST-018. (3) INFO duplicate-suite-key overwrite — ACCEPTED: bounded by
  fail-open (a newly-unmapped path escalates to FULL_RUN; worst case is
  over-selection, not silent coverage loss).
- L2 review discipline (WORKFLOW ceremony table): code_review required
  (full single dual-verdict pass); no protected surface touched, so no
  operator merge-time checkpoint beyond the normal PR ceremony
  (Constitution Article 7 — the agent never merges).

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
