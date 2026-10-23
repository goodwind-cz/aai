---
id: ci-test-impact-selection
type: product
capability: ci-test-impact-selection
status: current
delivered_by:
  - CHANGE-0071
  - selected-ci-scheduling-foundation
  - selected-ci-conditional-sharding
  - ci-body-only-rechecks
spec: docs/specs/SPEC-0097-spec-ci-test-impact-selection.md
updated: 2026-10-21
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

For a PR event that changes only the body, `ci-select.mjs` can emit the explicit
`body-reuse` mode. It requires a completed successful run at the same head,
base, PR, repository, workflow and pinned merge checkout. That run must publish
its execution identity and complete source-job plan through successful workflow
steps, and every expected source job must have succeeded in one attempt. The
current run still executes `select`, `release notes`, `tracked-ignored`, and
the required aggregate gate. The skill jobs, Windows seed and self-hosting
smoke are skipped. A missing or ambiguous field, API error, changed attempt,
cancelled source run, moved base, fork, `ci-full` label or mixed edit returns
to ordinary selection with a fallback reason in the select log. A body edit that cancels
its first source run therefore performs source validation again.

When the full framework does run, it no longer runs on one machine. The
`select` job splits the suites into four deterministic, weight-balanced
shards and the full sweep runs as a four-leg matrix in parallel. On the
first live run the longest leg took 427 s against a single-runner median of
1120 s. Every suite still runs exactly once: an independent shell checker
re-derives the shard plan in `select` and again in every leg, and fails the
build if any suite is missing, duplicated, extra, or not runnable by the
leg — so a sharding mistake turns CI red instead of silently shrinking
coverage.

Selected runs use one or two runners, each with four workers. The selected
membership is ordered by descending observed duration, with bytewise name order
for ties; duplicate names run once. A two-runner plan is eligible only when at
least eight suites are selected and the weight model predicts at least 120
seconds on one runner, at least 30 seconds saved, at least 20% shorter wall
time, and at most 25% more runner time. The model adds 30 seconds per runner
for startup. These are planning estimates, not a hosted speed guarantee.
Small sets and sets with missing, malformed or incomplete weights use one
runner. Invalid or empty suite names fail before framework dispatch. The
independent selected-plan checker verifies the selected set and each runnable
shard in the selection job and again in the consuming checkout. Each active
runner makes one framework invocation. `--order-from FILE` remains the
name-only ordering interface.

A fixed nine-suite local benchmark ran five paired real framework executions
on an Apple M4 Max with Node 26 and four workers per runner. Median wall time
was 279.169 seconds on one runner and 172.843 seconds on two, a 38.086% drop;
summed runner time rose 17.894%, within the policy's 25% modeled budget.
Every leg passed with no skips. The [benchmark review](../ai/reviews/review-20261021T094823Z-selected-sharding-follow-up.md)
records the five-pair method, measurements and limitations for that workload
and hardware class. Hosted small/large selected cases and
the full/platform regression are still required before merge-readiness.

The weights now cover all 109 runnable top-level suites, derived from five
successful full CI runs captured on 2026-10-20. Each measured row records its
sample count and source run IDs; source records name their SHAs. `aai-state`
was skipped in those runs and explicitly uses the largest measured weight
(212 seconds), rather than treating a skip as a successful timing. Historical
performance targets in earlier changes are historical observations; refreshed
weights may exceed them.

The read-only skill-suite workflow groups PR runs by workflow, event and PR
number and enables cancellation for superseded runs in that group. Other events
use unique run IDs and do not cancel one another. Local tests verify the
configuration; hosted cancellation (H1) and candidate full/platform regression
(H2) remain required after PR creation and before merge. This foundation does
not complete the parent runtime and faster-feedback rollout.

## Docs-audit body-lint test pilot

The always-on `aai-docs-audit` suite now invokes ten direct `node:test` cases
for five body-lint behavior groups, including separately counted CRLF variants.
The exact Node file path is in the suite map, so a change to it selects the
existing core suite. To run only those in-memory parser cases:

```bash
bash .aai/scripts/aai-run-tests.sh node --test tests/skills/lib/docs-audit-body.test.mjs
```

To run the complete docs-audit suite, including its retained CLI, staged-hook
and real-corpus checks:

```bash
AAI_TEST_PARALLEL=1 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-docs-audit
```

A five-pair local matched-workload measurement found a 0.570-second median for
the Node cases versus 2.006 seconds for the five original Bash behavior groups.
The ordinary suite ran once before and once after as correctness checks; those
two observations do not establish a full-suite speed change. See the
[tracked pilot report](../analysis/docs-audit-node-test-pilot.md) for every
sample, setup cost and coverage limit.

## Docs-audit suite speed

The always-on `aai-docs-audit` suite no longer repeats real-corpus work. Each
distinct full real-corpus audit runs once per suite run through `live_audit`
(14 launches became 3), and the real index is generated twice once through
`live_index_pair`, which restores `docs/INDEX.md` and the violations
companion before any assertion reads a snapshot. This also fixed a masked check:
a stale committed index now fails the staleness arm in `main()` order. The
per-file history oracle runs in worker-thread shards, and the closeout candidate
cases run as one `node:test` file. To prove the shared audit copies equal fresh
runs on your tree:

```bash
AAI_DOCS_AUDIT_LIVE_VERIFY=1 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh
```

Five alternating paired local runs of the ordinary suite gave a 116.5-second
median before and 79.3 seconds after (31.9% lower). Hosted durations vary far
more and are reported, not gated. See the
[analysis note](../analysis/docs-audit-suite-speed.md) for the per-function
profile, the closeout migration map and every sample.

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
  CI. Optionally add its duration to `tests/skills/suite-weights.tsv`; an
  unweighted suite is still planned (it gets the largest weight and is
  scheduled first), it just balances less well.
- Keep suites at the top level of `tests/skills/`. Each leg runs its shard
  through `test-framework.sh --skill`, which resolves top-level files only,
  so a suite in a subdirectory fails the shard check by name.
- A full run's four legs report as `skill test suite (full framework, via
  test-framework.sh) (1..4)`; the required `gate` check still aggregates
  them and fails if any leg fails.

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
- `tests/skills/suite-weights.tsv` — `<suite>\t<seconds>` rows, measured
  from a CI log, used only to balance the shards. A row for a deleted suite
  is ignored; a missing row gets the largest weight.

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
  `mode: full|selected|body-reuse` output. Selected mode uses `skills-selected`
  for one runner or `skills-selected-sharded` for two; full mode uses
  `skills-full`. Body reuse carries a `BODY_REUSE` line naming the earlier run
  and its source/base/checkout/workflow identity. The required `gate` job
  accepts only the successful path for that mode and requires the current
  `release notes` result on PRs.
- `.aai/scripts/select-suites.mjs --selected-plan-from <file>` — reads
  newline-separated selected names and emits `SHARD` lines, `SHARDS` count
  and a `SELECTED_DECISION` record with the model inputs, predicted wall and
  runner seconds, chosen runner count and reason. Invalid names exit nonzero;
  unusable weights retain one runner with a diagnostic.
- `tests/skills/lib/shard-plan-check.sh --check-selected <plan>
  <skills_dir> <expected_list>` — independently checks the selected set,
  record grammar and one or two contiguous nonempty runnable shards before
  names are extracted for framework execution.
- `.aai/scripts/select-suites.mjs --shards <N>` — prints one
  `SHARD <id> <suite> weight=<w>` line per suite (longest first, greedy
  balance, deterministic across runs). Still always exits 0; any internal
  error degrades to a single unsharded leg, never to a shorter list.
- `tests/skills/lib/shard-plan-check.sh --check <plan> <skills_dir>` —
  exits 1, naming the offender, when the plan's suite set differs from the
  `test-aai-*.sh` files on disk, lists a suite twice, or names a suite the
  leg cannot run (not a top-level `test-<name>.sh`, or a name outside
  `[A-Za-z0-9_-]`); prints `shard_ids=[...]` for the matrix on success.
  `--extract <id> <plan>` prints one leg's suite list.
