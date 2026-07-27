---
id: ci-test-impact-selection
type: product
status: current
spec: docs/specs/SPEC-0097-spec-ci-test-impact-selection.md
updated: 2026-07-27
---

# CI test impact selection

## What it does

CI used to run the whole `tests/skills/` framework (~50 suites, ~25 minutes)
on every single push to a pull request — including review-fix pushes that
touch one file. A weekend of iteration on one PR could burn 12+ CI-hours
this way.

Now a PR push runs only the suites its diff could plausibly affect, plus a
cheap always-on core (`aai-check-state`, `aai-docs-audit`, `aai-spec-lint`).
A deterministic selector reads the diff, maps changed paths onto suites via
a declared suite map, and prints which suites to run and why. The full
framework still runs — on every push to `main`, every night, and on demand
via a `ci-full` label — so the safety net moves later in the pipeline
instead of disappearing.

The selector is deliberately cautious: it never tries to narrow coverage on
a path it can't confidently classify. Any changed path that isn't mapped to
a suite, that touches shared library code (`.aai/scripts/lib/**`), or that
touches a protected surface (`docs/ai/docs-audit.yaml` `protected_paths_l3`)
escalates straight back to a full run instead of guessing.

## How to use it

Nothing is required for a normal PR — selection is automatic:

- Push to a PR branch. The workflow's `select` job prints the selection
  (which suites and why) in the Actions log; the suites it names then run
  via `bash tests/skills/test-framework.sh --skill <name>`.
- Need the full framework on a specific PR regardless of the diff? Add the
  `ci-full` label. (GitHub only re-evaluates labels on the next
  synchronize/re-run — add the label, then push again or re-run the
  workflow.)
- Push to `main`, or wait for the nightly run (~03:17 UTC) — both always run
  the complete framework, no selection involved.
- Branch protection: keep the aggregating `gate` job ("skill test suite
  (tests/skills/, via test-framework.sh)") as the required status check —
  never the selected/full leaf jobs, which are mutually exclusive (one is
  always skipped and a skipped required check blocks merges). The gate
  reports on every run and fails unless the mode-relevant leaf succeeded.
- Adding a new `tests/skills/test-aai-*.sh` suite? Add a matching row to
  `tests/skills/suite-map.yaml` — a suite with no row fails
  `tests/skills/test-aai-hygiene-pack.sh`'s pin check, both locally and in
  CI.

## Data model

- `tests/skills/suite-map.yaml` — one row per existing suite under
  `suites.<name>.globs` (watched path globs, deliberately generous), a
  `core:` list of always-on suites, and `full_run_triggers.shared_lib_globs`
  naming the shared-library fail-open trigger. A fixed, hand-authored
  schema — not general YAML (its own header documents the exact
  indentation contract).
- `docs/ai/docs-audit.yaml` `protected_paths_l3` — read live by the selector
  as one of the three fail-open trigger classes (checked FIRST, before
  shared-lib and unmapped); never duplicated into the suite map.

## Interfaces and contracts

- `.aai/scripts/select-suites.mjs --base-ref <ref>` (or `--files-from
  <path|->` for deterministic testing) — zero-dependency Node CLI. Exit
  code is always 0. Stdout is either:
  - `FULL_RUN reason=<protected-l3|shared-lib|unmapped|internal-error> path=<path>`, or
  - one `CORE <suite> reason=core` line per always-on suite, one
    `SELECTED <suite> reason=<matched path>` line per diff-matched suite,
    and exactly one `DROPPED <n>` line naming how many mapped suites were
    skipped.
- `.github/workflows/skill-suite.yml` — the `select` job resolves a
  `mode: full|selected` output (and the suite list, when selected) on
  every trigger; `skills-selected` and `skills-full` key off it.
