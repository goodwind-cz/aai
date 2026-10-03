---
id: ci-test-selection-narrowing-and-sharding
type: techdebt
number: null
status: draft
links:
  pr: []
  commits: []
---

# Tech Debt: CI runs the full 103-suite sweep on 40% of PRs, and runs it on one runner

## Debt Summary
CI test wall-clock is the dominant delivery friction. Two independent causes,
both measured, neither requiring any loss of coverage to fix:

1. **The impact selector escalates to `FULL_RUN` on 40% of PRs, and three
   quarters of those escalations come from a single blanket rule** —
   `full_run_triggers.shared_lib_globs: .aai/scripts/lib/**`. Any touch to any
   of the 30 files under `.aai/scripts/lib/` runs all 103 suites, regardless of
   that file's actual fan-out.
2. **The full sweep runs as one job on one runner** (`skills-full`,
   `AAI_TEST_PARALLEL: 4`, `timeout-minutes: 30`). There is no sharding across
   runners, so the full sweep's wall clock is bounded by a single machine.

`ps1-quality.yml` is explicitly **not** part of this debt: it already carries a
tight `paths:` filter for both `push` and `pull_request`, so the expensive
Windows legs only run when PowerShell surface actually changes. No action there.

## Root Cause
The selector (`.aai/scripts/select-suites.mjs`) is fail-open by design, which is
correct: under-selection silently drops coverage, over-selection only costs
minutes. But `shared_lib_globs` implements fail-open as a *blanket* rule over a
whole directory, because at the time it was written there was no dependency
graph to narrow it with. The rule treats `tree-hash.mjs` (1 consuming CLI
script) exactly like `cli-pipe-guard.mjs` (50). The conservatism is sound; its
granularity is not.

The single-runner full sweep is simply an un-exercised axis — `AAI_TEST_PARALLEL`
parallelises *within* a runner, and no one has yet split the suite list *across*
runners.

## Current Cost / Risk
Measured by replaying the live selector against the changed-path list of the
**40 most recent merges on `main`** (`select-suites.mjs --files-from -`):

| Outcome | Count | Share |
|---|---|---|
| `FULL_RUN` | 16 | 40% |
| `SELECTED` | 24 | 60% |

`FULL_RUN` causes, same 40 merges:

| Reason | Count | Share of full runs |
|---|---|---|
| `shared-lib` | 12 | 75% |
| `protected-l3` | 2 | 12.5% |
| `unmapped` | 2 | 12.5% |

True transitive reverse-import fan-out of the 30 files in `.aai/scripts/lib/`,
counted as the number of the repo's 76 non-lib CLI scripts that reach the lib
through real `import ... from './lib/x.mjs'` edges (lib-to-lib edges followed to
closure):

- **26 of 30 lib files reach 8 or fewer of the 76 CLI scripts.**
- Only two have broad fan-out: `cli-pipe-guard.mjs` (50) and `docs-model.mjs` (23).
- Six are shell libs with zero `.mjs` importers (`repo-tripwire.sh`,
  `append-lock.sh`, `git-bash-path.sh`, `gitignore-block.sh`) or no importer at
  all (`merge-hooks-json.mjs`, `session-lock.mjs` — reached only via other entry
  shapes).

So for the large majority of lib touches the blanket rule is running ~103 suites
to cover a change whose real reachable surface is a handful of scripts.

The two `unmapped` escalations were on genuinely test-inert paths:
`.gitattributes` and `docs/decisions/DECISION-original-request-outcome-backcheck-round-extension.md`.

Delivery cost: the full sweep is budgeted at 30 minutes of CI (and is known to
need `AAI_TEST_TIMEOUT=3000` locally, ~32 min), and it lands on 2 of every 5
PRs. That is the time the author waits before merge, repeated per push.

## Target State
- A lib-file touch selects the suites that actually cover the scripts reachable
  from that lib, derived deterministically from the import graph — not the whole
  sweep.
- A change confined to paths that provably cannot alter test outcomes runs the
  always-on core suites, not the whole sweep.
- When the full sweep *is* the right answer, it finishes in a fraction of the
  wall clock by running across several runners.
- Coverage is never reduced: every downgrade from `FULL_RUN` is backed by a
  mechanical argument, and everything the graph cannot resolve still escalates.

## Scope
In scope:
- `.aai/scripts/select-suites.mjs` — reverse-import-graph resolution for
  `shared_lib_globs`, retaining every existing fail-open path.
- `tests/skills/suite-map.yaml` — a new, narrow, explicitly-reviewed inert-path
  class; per-lib fan-out threshold declaration.
- `.github/workflows/skill-suite.yml` — matrix sharding for `skills-full` (and
  the aggregating `gate` job's verdict logic, which must require every shard).
- `tests/skills/test-aai-suite-select.sh` — fixture cases for each new path.

Out of scope:
- `protected_paths_l3` escalation. It stays exactly as it is — it is the
  deliberate blast-radius rule for state/guard surface and is only 2 of 16 full
  runs. Not worth touching for the gain.
- `ps1-quality.yml` and the Windows legs. Already path-filtered.
- Rewriting or splitting any test suite's content. This item is about *which*
  suites run and *where*, never about what they assert.
- Making any suite faster internally.

## Plan / Migration
Incremental, each step independently shippable and independently revertible:

1. **Reverse import graph, report-only.** Add graph resolution to the selector
   behind an output-only mode: it still emits today's `FULL_RUN` for
   `shared-lib`, but also prints the narrowed set it *would* have chosen.
   Replay over recent merges and compare. No CI behaviour change yet.
2. **Flip shared-lib to graph-narrowed selection.** A lib touch now selects
   core + the suites covering the reachable scripts. Escalate to `FULL_RUN`
   anyway when: an importer cannot be resolved statically (dynamic/computed
   import), the lib is reached by a `protected_paths_l3` script, the resolved
   script set exceeds a declared fan-out threshold, or any reachable script has
   no suite-map row.
3. **Trace shell libs too.** Same treatment for `source`/`.` edges into
   `.aai/scripts/lib/*.sh`; until implemented those keep today's blanket
   escalation rather than falling through to a narrower answer.
4. **Inert-path class.** Add an explicit `inert_globs` list to
   `suite-map.yaml` for paths that cannot affect a test outcome. Anything not
   named keeps escalating via `unmapped`. The list is reviewed surface, not a
   wildcard.
5. **Shard the full sweep.** Split the 103 suites across a runner matrix with a
   deterministic, balanced assignment; `gate` requires all shards green.

Rollback: each step is a revert of one commit. Steps 2-4 are additionally
gate-able by restoring the blanket glob in `suite-map.yaml` alone, with no code
change.

## Verification
- `node .aai/scripts/select-suites.mjs --files-from -` replayed over the last 40
  merges on `main`, before and after: `FULL_RUN` share must fall from 16/40, and
  every merge that changes verdict must be listed with the reason.
- **Coverage-equivalence proof per downgrade:** for every merge that moves
  `FULL_RUN` to `SELECTED`, the selected set must be a superset of the suites
  whose globs match any changed path *and* the suites covering every script
  reachable from the changed libs. Asserted mechanically, not by inspection.
- `bash tests/skills/test-framework.sh --skill aai-suite-select` green, with new
  fixture cases for: low-fan-out lib, broad-fan-out lib, lib reached by a
  protected path, unresolvable import, inert path, and non-inert unknown path.
- `bash tests/skills/test-framework.sh --skill aai-hygiene-pack` green (it pins
  the one-row-per-suite invariant that the map edits must not break).
- Full sweep green post-sharding with the identical suite set: the union of
  shard suite lists must equal the unsharded list exactly, asserted in CI, so a
  shard-assignment bug cannot silently drop a suite.
- Wall-clock recorded before/after for both a selected-mode and a full-mode run.

## Constraints / Risks
- **Under-selection is the only real hazard here.** The selector's value is that
  it is fail-open; every change in this item narrows it. Each narrowing therefore
  needs the mechanical superset proof above, not a plausibility argument.
- **An exception can manufacture the state in which the guard stops applying.**
  A per-lib fan-out threshold and an inert-path list are both exceptions to a
  blanket rule: the threshold must be measured on a clean tree and the inert list
  must not be reachable by any suite's own fixtures. Evaluate the interaction of
  the new exceptions, not just each one alone.
- The hand-rolled `suite-map.yaml` parser depends on exact indentation and is not
  general YAML. New top-level keys (`inert_globs`, thresholds) must extend that
  parser deliberately and be covered by fixtures.
- The selector must stay zero-dependency, Node stdlib only (`docs/TECHNOLOGY.md`),
  and must keep exiting 0 on every internal error.
- Branch protection requires the exact check name
  `skill test suite (tests/skills/, via test-framework.sh)`. Sharding must not
  rename or remove the aggregating `gate` job that carries it.
- `tests/skills/test-aai-layer-profiles.sh` probes full git history and the
  selector needs the merge-base, so `fetch-depth: 0` must survive sharding.
- No secrets are referenced by this scope; the secrets preflight is skipped.

## Notes
Implementation mode (user choice): tdd — owner's words: "cokoliv to zrychli ale
nesnizi kvalitu je vitano". Signals that selected the recommendation: behavioral
change, multi-surface (selector + map + workflow + fixtures), and it narrows a
fail-open coverage guard where under-selection fails silently — the
superset-equivalence assertion has to exist as a RED test before the narrowing
lands. Recorded here rather than in `docs/ai/STATE.yaml` because
`set-strategy` exited 2: `current_focus.ref_id` still holds
`readme-portable-workflow-onboarding`. Planning's `set-focus` records it with
`--ref` (INTAKE_COMMON, LIVE OTHER FOCUS).

Measurement commands used for every number above, for reproduction:

```
# verdict + reason distribution over the last 40 merges
for c in $(git log --format=%h -40 main); do
  git diff --name-only "${c}^" "$c" \
    | node .aai/scripts/select-suites.mjs --files-from -
done
```

Fan-out was computed from real `import ... from './lib/<x>'` edges in the 76
non-lib `.aai/scripts/*.mjs` entry points, with lib-to-lib edges followed to
transitive closure. A plain `grep -rl` over the repo is NOT a valid proxy: test
suites mention lib paths inside assertion strings, which inflates the count by
an order of magnitude (e.g. `tree-hash.mjs` reads as 3 by grep, 1 by graph;
`guard-config.mjs` 228 by grep, 11 by graph).

Current shape for reference: `skill-suite.yml` has a `select` job feeding
mutually-exclusive `skills-selected` (15 min) and `skills-full` (30 min) jobs,
plus an always-reporting `gate` that carries the branch-protection check name,
plus an independent `self-hosting-smoke`. A `ci-full` PR label already forces
full mode, and non-PR events always run full — both behaviours are preserved.
