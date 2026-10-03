---
id: spec-ci-test-selection-narrowing-and-sharding
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: d81b2aeff50022cdda22a277d1fe9d82eaeed84f47ec60c71773ba266d245b44
ceremony_level: 2
links:
  requirement: null
  rfc: null
  intake: docs/issues/DEBT-DRAFT-ci-test-selection-narrowing-and-sharding.md
  pr: []
  commits: []
---

# Spec — The full sweep runs across four runners; lib-graph narrowing is deferred by measurement

SPEC-FROZEN: true

## Amendment (post-freeze, 2026-10-03 — code review BLOCKING-1 remediation)

This is a FROZEN spec, amended after the freeze and disclosed here rather
than rewritten silently, per the additive-with-disclosure convention (see
e.g. `docs/specs/SPEC-0178-...md` `## Amendment`).

Authority: `docs/ai/decisions.jsonl`, `type: spec_amendment`, ts
`2026-10-03T12:55:43Z`, `ref_id: ci-test-selection-narrowing-and-sharding`,
tracked by `fu-amend-ci-test-selection-narrow-a3ef7d` (owner sign-off owed).

`docs/ai/reviews/review-20261003T124300Z.md` BLOCKING-1 found that
`tests/skills/lib/shard-plan-check.sh --check`'s membership proof walks
`tests/skills/` RECURSIVELY (mirroring `select-suites.mjs`'s
`discoverSuiteNames`), but each CI leg executes its shard through
`test-framework.sh --skill <name>`, which resolves only a TOP-LEVEL
`tests/skills/test-<name>.sh` (`test-framework.sh` `discover_tests()`,
`SPECIFIC_SKILLS` branch) — and that function's own `exit 2` on a missing
file is swallowed by the caller's process-substitution pipe. A suite moved
into (or added inside) a subdirectory is still proven "complete" by the
recursive check, then silently never runs inside its leg while the leg still
exits 0: a coverage regression behind a green gate. This amendment adds
Spec-AC-04 a new TEST-1440: `--check` now also fails, naming the suite, when
a planned name does not match `^[A-Za-z0-9_-]+$` or has no top-level
`tests/skills/test-<name>.sh`. See `## Acceptance Criteria Status`
(Spec-AC-04) and `## Test Plan` (TEST-1440) below for the landed text. The
owner may still accept or reverse the underlying scope choice (the tracked
item above remains open for that decision); this disclosure only makes the
spec match the fix already remediated.

## Links
- Intake: docs/issues/DEBT-DRAFT-ci-test-selection-narrowing-and-sharding.md
- Prior spec this extends: docs/specs/SPEC-0097-spec-ci-test-impact-selection.md
- Product doc: docs/product/ci-test-impact-selection.md
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Problem, as measured

Every number below was measured on 2026-10-03 at `9f718c08` under plain `bash`
with `/usr/bin/grep` spelled absolutely.

1. **The full sweep is 101 suites, not 103.** `tests/skills/test-framework.sh`
   `discover_tests()` runs `find "$SCRIPT_DIR" -name "test-aai-*.sh" -type f`.
   `find tests/skills -name 'test-aai-*.sh' -type f | wc -l` = 101 (the same
   with `-maxdepth 1`). The intake's 103 counted `test-framework.sh` and
   `test-ps1-quality.sh`, which the sweep does not run. `suite-map.yaml` has
   101 suite rows.
2. **The full sweep takes ~18-20 minutes, on one runner.** `skills-full` job
   durations of the last five full runs on `main` (`gh run view <id> --json jobs`):
   37069590585 = 1161 s, 37062133719 = 1178 s, 37048638068 = 1062 s,
   37036602291 = 1120 s, 37046693671 = 981 s. Median **1120 s**.
3. **Its floor is one suite.** Per-suite durations parsed from the
   37069590585 `skills-full` log (`[ n/101] <suite> PASS (<s>s)` lines) sum to
   4009 s; the longest is `aai-learned-append` = 434 s, then `aai-hygiene-pack`
   313 s, `aai-delta-stage3` 278 s. The framework's refilling queue
   (`AAI_TEST_PARALLEL=4`) makes a pool-of-4 simulation predict 1003 s for one
   runner, against the 1120 s observed (+12 %).
4. **Sharding reaches that floor at three or more runners, but only when
   balanced.** Pool-of-4 simulation per shard, same durations:

   | Shards | LPT by measured weight, longest-first | Round-robin, name order |
   |---|---|---|
   | 2 | 502 s | 712 s |
   | 3 | 434 s | 577 s |
   | 4 | 434 s | 500 s |

   With LPT at four shards the shard weight-sums are 1003, 1002, 1002, 1002
   (ideal ceil(4009/4) = 1003); round-robin over the weight-sorted list gives a
   worst shard of 1187.
5. **The selector replay, re-measured.** Replaying
   `select-suites.mjs --files-from -` over the 40 commits ending at `9f718c08`
   (first-parent squash merges, `git diff --name-only <c>^ <c>`): 17 FULL_RUN
   (13 shared-lib, 2 protected-l3, 2 unmapped), 23 SELECTED. The intake's
   16 / 12 did not reproduce, either here or over the 40 commits ending at
   `367caa41` (18 FULL_RUN, 14 shared-lib there). This spec uses the figure
   measured at `9f718c08`. The shape is the same: shared-lib is three quarters
   of all full runs.

## Scope decision — why this ride shards and does not narrow

The intake offered five steps. Planning prototyped step 2 (lib-graph
narrowing) in a scratch copy before choosing, because its value had not been
measured. The prototype used a TEXTUAL reference graph (a file references a
lib when it names the lib's basename at a token boundary; lib-to-lib edges
followed to closure; the 34 files that name the lib directory generically,
among them 25 suites, 16 of which `cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs`
into fixtures, count as referrers of every lib; each referrer then re-run through the existing
protected-l3 / suite-glob / unmapped logic). Results over the 13 shared-lib
merges:

- 7 stay FULL_RUN anyway: 6 because `.aai/scripts/allocate-doc-number.mjs`
  (a `protected_paths_l3` file) imports `lib/docs-model.mjs` and
  `lib/guard-config.mjs`, so their closures reach L3; 1 because the merge also
  touched the unmapped `.aai/feedback.yaml`.
- 6 become SELECTED, but each selects 41-55 of the 101 suites; their summed
  measured durations are 2297-3228 s, a predicted 574-807 s on one runner.
- Precondition found on the way: `.aai/scripts/check-cd-subshell-leak.mjs` has
  no suite-map row, so every narrowing would have escalated through it until
  mapped.

Sharded full mode is predicted at about 434 s plus runner setup. **A narrowed
selected run (574-807 s, unsharded) would be slower than the sharded full run
it replaces.** Sharding lands on every full run: 17 of 40 PR runs, every push
to `main`, every nightly. It changes no coverage. Narrowing would convert 6 of
40 PRs, and its only remaining benefit after sharding is runner-minutes. It
also narrows a fail-open guard, and its soundness rests on a premise (every
load of a lib names the lib in some tracked file) that no test can prove
complete. By the numbers, this ride is sharding. The rest is recorded as
suggested follow-ups (`## Out of scope`), with the measurements above, so the
decision can be re-taken once sharding has landed.

## Implementation strategy
- Strategy: tdd
- Rationale: recorded by the owner at intake ("cokoliv to zrychli ale nesnizi
  kvalitu je vitano" — anything that speeds CI up without lowering quality is
  welcome), STATE `implementation_strategy.source: intake`,
  `ref_id: ci-test-selection-narrowing-and-sharding`. Kept, and it still fits
  the narrowed scope: the one hazard here is a shard assignment that silently
  drops a suite. The completeness tests below have to exist and be observed RED
  before the assignment code exists.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound CI-workflow change, verified only by a live
  `ci-full` CI run on its own branch. The main checkout is shared by
  concurrent sessions (another planning dispatch was live during this one), and
  a branch checkout in the shared tree has displaced other sessions before.
- User decision: undecided
- Base ref: main
- Worktree branch/path: chosen at Implementation Preparation
- Inline review scope: the paths listed under `## Review scope`

## Design

### D1 — shard mode in the existing selector, not a new `.aai/` file
`.aai/scripts/select-suites.mjs` gains one mode:

```
node .aai/scripts/select-suites.mjs --shards <N> [--repo-root <dir>] [--weights <path>]
```

It enumerates suites with the SAME rule `discover_tests()` uses: every regular
file named `test-aai-*.sh` anywhere under `<repo-root>/tests/skills/`. A
suite's name is the basename with `test-` and `.sh` stripped. It reads
weights from `--weights` (default `tests/skills/suite-weights.tsv`), assigns
suites to shards by LPT (longest processing time first) and prints the plan:

```
SHARD <i> <suite> weight=<w>        one per suite; i is 1-based
SHARDS count=<k> suites=<total>     exactly one, last
```

plus optional report lines that never carry suites: `WEIGHT_ORPHAN <name>`
(a weight row naming no on-disk suite) and `WEIGHTS_IGNORED reason=<...>`.
On a degrade it prints `SHARD_FALLBACK reason=<...>` and NO `SHARD` line.
Exit is always 0, like every other mode. With no `--shards` flag, every
existing mode is byte-for-byte unchanged.

Extending the selector rather than adding a script keeps the vendored
`.aai/` inventory the same (no `PROFILES.yaml` obligation) and keeps the
code next to the enumeration rule it must mirror.

### D2 — the assignment
- Weight of a suite = its row in the weights file; a suite with no row gets
  the largest known weight (`maxKnownWeight`), so an unmeasured suite is
  scheduled early rather than last. With no usable weights, every weight is 1.
- Order = weight descending, then name ascending (byte order). That gives
  determinism, and longest-first inside each shard. `test-framework.sh` runs
  `--skill` suites in argument order, so emission order is run order.
- Each suite in that order goes to the shard with the smallest current load
  (lowest index on a tie). Shards that would be empty (N > suites) are not
  emitted.
- `N` must be an integer 1..8. Anything else is `SHARD_FALLBACK
  reason=invalid-shard-count`. Zero suites found is `SHARD_FALLBACK
  reason=no-suites`.

### D3 — weights file
`tests/skills/suite-weights.tsv`: `#` comments, blank lines, and
`<suite><whitespace><positive integer seconds>` rows. It is seeded from the
37069590585 `skills-full` log (a 0.0 s reading becomes 1) with the run id in
its header comment. A malformed line makes the whole file ignored
(`WEIGHTS_IGNORED reason=malformed-line line=<n>`). The plan is still complete,
just name-balanced. **Weights affect balance only, never membership.** A
stale or missing weight costs minutes, never coverage, and that is why the
file carries no hygiene pin.

### D4 — an independent plan check, in shell, that CI runs
`tests/skills/lib/shard-plan-check.sh` does not share code with the selector:

```
bash tests/skills/lib/shard-plan-check.sh --check   <plan-file> <skills-dir>
bash tests/skills/lib/shard-plan-check.sh --extract <shard-id>  <plan-file>
```

`--check` exits non-zero, naming the offender on stderr, unless the plan's
suite set equals the `find <skills-dir> -name 'test-aai-*.sh' -type f` set
exactly: no suite missing, none extra, none twice. On success it prints one
line, `shard_ids=[<distinct shard ids, ascending, comma-separated>]`. A plan
whose only content is a `SHARD_FALLBACK` line passes and prints
`shard_ids=["all"]`. `--extract <i>` prints shard i's suites in plan order, one
per line. `--extract all` on a fallback plan prints `__ALL__`. An id with no
suites exits non-zero. The matrix legs are derived from the same plan text the
check validated, so the union of legs is the union the check proved.

### D5 — workflow
In `.github/workflows/skill-suite.yml`:
- `select` job: a new step `id: shard` with NO `if:` condition. It runs before
  the mode decision, so non-PR events and the `ci-full` label get the plan too.
  It runs `select-suites.mjs --shards 4` into `shard-plan.txt`, runs `--check`
  on it (a failure fails `select`, which fails `gate`), and exports
  `shard_ids` and the multi-line `shard_plan` as job outputs.
- `skills-full` keeps its job id and its `if: needs.select.outputs.mode ==
  'full'`, and becomes a matrix: `strategy: fail-fast: false`, `matrix: shard:
  ${{ fromJSON(needs.select.outputs.shard_ids) }}`. Each leg keeps
  `fetch-depth: 0`, `AAI_TEST_PARALLEL: '4'` and `timeout-minutes: 30`. It
  receives the plan through `env:` (never inline-interpolated into the
  script), writes it to `shard-plan.txt`, and re-runs `--check` against its
  OWN checkout. A pull_request merge ref can move between jobs, and a suite
  added on the base in between would otherwise be missing from the plan. Then
  it runs `--extract` for its shard id and ONE `test-framework.sh` invocation
  with a repeated `--skill`, or bare `test-framework.sh` for `__ALL__`.
- `gate` keeps its exact name `skill test suite (tests/skills/, via
  test-framework.sh)`, its `needs: [select, skills-selected, skills-full]`, its
  `if: always()`, and its full-mode line requiring `needs.skills-full.result`
  = `success`. GitHub reports a matrix job's result as `success` only when
  every leg succeeded, so `gate` requires every shard.
- `skills-selected`, `self-hosting-smoke`, the triggers, the `ci-full` label
  and "non-PR events are always full" are unchanged.

### D6 — suite map
`tests/skills/suite-weights.tsv` and `tests/skills/lib/shard-plan-check.sh`
join `aai-suite-select`'s globs. Today the first is unmapped (FULL_RUN on
every edit), and the second selects only `aai-win-fallback` through
`tests/skills/lib/**`.

### Mandated shapes (mutation anchors)
Implementation MUST contain these exact lines, or restamp the affected
Mutation cells mechanically and disclose the restamp in the TDD record:

In `.aai/scripts/select-suites.mjs`:
- S1 `if (opts.shards !== null) return shardMain(opts);`
- S2 `const SUITE_FILE_RE = /^test-aai-.*\.sh$/;`
- S3 `const MAX_SHARDS = 8;`
- S4 `return b.w - a.w || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);`
  (the body of `function byWeightDescThenName(a, b)`)
- S5 `const unknownWeight = maxKnownWeight;`
- S6 `for (const o of order) {`
- S7 `const target = loads.indexOf(Math.min(...loads));`
- S8 `if (names.length === 0) return shardFallback('no-suites');`
- S9 the malformed-weights return begins
  `return { weights: new Map(), ignored:`
- S10 the plan line is emitted by
  `console.log(`SHARD ${i + 1} ${o.name} weight=${o.w}`);`

In `tests/skills/lib/shard-plan-check.sh`:
- H1 `if [[ "$dup_count" -ne 0 ]]; then`
- H2 `if [[ "$planned_set" != "$expected_set" ]]; then` (`planned_set` is
  built with `sort -u`, so this comparison does not double as the duplicate
  check)
- H3 `echo 'shard_ids=["all"]'`
- H4 the extraction filter contains `$2 == idx`
- H5 the id list is built with `sort -un`

In `.github/workflows/skill-suite.yml`:
- W1 `fail-fast: false`
- W2 `--shards 4`
- W3 the leg's own re-check line
  `bash tests/skills/lib/shard-plan-check.sh --check shard-plan.txt tests/skills >/dev/null`
- W4 the gate's unchanged full-mode line
  `[ "${{ needs.skills-full.result }}" = "success" ] || { echo "full-mode run failed"; exit 1; }`

## Implementation plan
- Components: `.aai/scripts/select-suites.mjs` (D1, D2, D3),
  `tests/skills/suite-weights.tsv` (new, D3),
  `tests/skills/lib/shard-plan-check.sh` (new, D4),
  `.github/workflows/skill-suite.yml` (D5, and its header comment rewritten
  to describe sharding), `tests/skills/suite-map.yaml` (D6),
  `tests/skills/test-aai-suite-select.sh` (new tests, wired into `main()`).
- After LOOP COMPLETE (not before): `docs/product/ci-test-impact-selection.md`
  gains a sharding section, and `CHANGELOG.md` gains one
  `## [unreleased] — ci: <title>` heading.
- Data flow: `select` (checkout) → `select-suites.mjs --shards 4` →
  `shard-plan.txt` → `shard-plan-check.sh --check` → outputs `shard_ids` +
  `shard_plan` → `skills-full` leg i (own checkout) → `--check` again →
  `--extract i` → `test-framework.sh --skill ...` → matrix result → `gate`.
- Edge cases: N > suites (only non-empty shards emitted); a weight row for a
  removed suite (WEIGHT_ORPHAN, ignored); a new suite with no weight (max
  weight, scheduled first); a weights file whose tabs became spaces (still
  parses: any whitespace); a fallback plan (one leg runs the bare framework,
  which is today's behaviour); a moved merge ref (the leg's re-check fails
  loudly).
- Test hygiene, all CI-only failure classes measured in this repo: tests run
  under `set -euo pipefail`. No `printf | grep -q` or `grep | head`; use the
  `assert-payload.sh` helpers or `qgrep`. No bare `rc=$?` after a command that
  can fail; use `rc=0; cmd || rc=$?`. Fixture trees are scratch temp dirs with
  absolute, non-empty paths checked before every `cd`. No fixture needs git.
  The helper is also linted by `test-aai-hygiene-pack.sh` (pipe ratchet,
  `local` cross-reference), and every new test function is wired into
  `main()`, because `check-test-registration.mjs` fails orphan test functions.

## Seams this change crosses

| Seam | Producer | Consumer | Test that crosses it |
|---|---|---|---|
| enumeration rule | `discover_tests()` find rule | `select-suites.mjs --shards` enumeration | TEST-1420 (real tree vs the same `find`) |
| plan text | `select-suites.mjs --shards` | `shard-plan-check.sh --check/--extract` | TEST-1435 (real repo, real script into real helper) |
| plan to matrix | `--check` stdout `shard_ids` | GitHub `matrix.shard` | TEST-1436 (wiring pin) plus the live ci-full run (Verification) |
| leg to framework | `--extract` output | `test-framework.sh --skill` argument order | live ci-full run: every leg log's PASS lines united equal the 101 suites |
| legs to gate | matrix aggregate result | `gate` full-mode line | TEST-1437 (pin); GitHub's aggregation itself is residual risk RR-2 |
| new paths to map | `suite-map.yaml` globs | the selector on a PR touching them | TEST-1439 (real map replay) |

## Acceptance Criteria Mapping
- Intake Target State "when the full sweep is the right answer, it finishes in
  a fraction of the wall clock by running across several runners" maps to
  Spec-AC-02, Spec-AC-05 and the live-run PASS criterion.
- Intake Verification "the union of shard suite lists must equal the unsharded
  list exactly, asserted in CI" maps to Spec-AC-01, Spec-AC-04 and Spec-AC-05.
- Intake constraints (zero-dep, exit 0, check name, `fetch-depth: 0`, `ci-full`,
  non-PR full) map to Spec-AC-03 and Spec-AC-05.
- Intake steps 1-4 (graph narrowing, shell-lib tracing, inert class) are out of
  scope by the decision above.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description | Status  | Evidence | Review-By | Notes |
|------------|-------------|---------|----------|-----------|-------|
| Spec-AC-01 | WHEN select-suites.mjs runs with --shards N for N in 1..8 the system SHALL emit SHARD lines that name every suite the test-framework.sh find rule discovers exactly once and no other name, and exit 0. | done | docs/ai/tdd/green-20261003T095318Z.log TEST-1420/1421 mutation-gate PASS | — | Completeness invariant verified locally (real tree 101 suites, fixture orphan case); the live ci-full run in Verification is Validation-owned and still outstanding. |
| Spec-AC-02 | WHEN the same tree and weights are sharded twice the system SHALL print byte-identical plans, emit each shard's suites in non-increasing weight order, give an unweighted suite the largest known weight, and on the real repo at N=4 keep the largest shard weight-sum at or below the larger of ceil(1.05 x ceil(total/4)) and the largest single weight. | done | docs/ai/tdd/green-20261003T095318Z.log TEST-1422/1423/1424/1425 mutation-gate PASS | — | Real-repo N=4 measured max shard sum 1005 against bound 1056 (total=4018, maxw=434). Live ci-full run still outstanding (Validation-owned). |
| Spec-AC-03 | WHEN the shard count is invalid, the weights file is malformed, or no suite is found the system SHALL exit 0 and either print a complete plan with a WEIGHTS_IGNORED line or print SHARD_FALLBACK with no SHARD line; WHEN --shards is absent every existing output is byte-identical to the pre-change output. | done | docs/ai/tdd/green-20261003T095318Z.log TEST-1426/1427/1428/1429 mutation-gate PASS | — | Degrade paths and the byte-identical negative control both verified locally. |
| Spec-AC-04 | WHEN shard-plan-check.sh --check reads a plan the system SHALL exit 0 printing shard_ids only if the plan's suites equal the find set with no missing, extra or duplicate name AND every planned name matches ^[A-Za-z0-9_-]+$ and resolves to a top-level tests/skills/test-<name>.sh, print shard_ids=["all"] for a fallback plan, and --extract SHALL print exactly one shard's suites in plan order. | done | docs/ai/tdd/green-20261003T095318Z.log TEST-1430..1435 mutation-gate PASS; TEST-1440 remediates BLOCKING-1 (review-20261003T124300Z.md), see Amendment above | — | Independent shell check verified locally, including the real-repo SEAM (TEST-1435) and the leg-resolvability check (TEST-1440). |
| Spec-AC-05 | skill-suite.yml SHALL run the shard step unconditionally in select with --shards 4 and --check, run skills-full as a fail-fast false matrix over shard_ids whose every leg keeps fetch-depth 0 and re-checks the plan on its own checkout, keep the gate's exact name, needs list, always() and full-mode success line, and map both new files to aai-suite-select. | done | docs/ai/tdd/green-20261003T095318Z.log TEST-1436..1439 mutation-gate PASS | — | Structure pins verified locally; the live ci-full run (4 green legs, 660s cap) in Verification is Validation-owned and still outstanding — this is the spec's own stated PASS criterion, not yet met. |

## Test Plan

Every RED observation is recorded under `docs/ai/tdd/` as
`ci-test-selection-narrowing-and-sharding-red-<TEST-ID>.log`, and every
mutation result as
`docs/ai/tdd/spec-ci-test-selection-narrowing-and-sharding/mutation-<TEST-ID>.txt`
(produced by `mutation-run.mjs`). The mutation target is
`.aai/scripts/select-suites.mjs` for TEST-1420..1429,
`tests/skills/lib/shard-plan-check.sh` for TEST-1430..1434 and TEST-1440,
`.aai/scripts/select-suites.mjs` for TEST-1435,
`.github/workflows/skill-suite.yml` for TEST-1436..1438 and
`tests/skills/suite-map.yaml` for TEST-1439. Mutation cells substitute the
mandated shapes above (regex semantics, `mutation-run.mjs` `applySedExpr`).
TEST-1440 (post-freeze amendment, see `## Amendment`) was added in the
BLOCKING-1 remediation round, 2026-10-03.

Pre-change RED: on `9f718c08` `--shards` is an unknown flag, so the selector
prints `FULL_RUN reason=internal-error`; the helper does not exist; the
workflow has no shard step. Every positive test fails. TEST-1429 and TEST-1437
are negative controls that pass on the pre-change tree by design. Their RED is
the mutation record, which the TDD record must say.

All tests live in `tests/skills/test-aai-suite-select.sh`. Fixtures are scratch
temp-dir trees holding a `tests/skills/` directory of stub `test-aai-*.sh`
files and their own weights file, passed with `--repo-root` and `--weights`.
TEST-1420, 1423, 1424 and 1435 read the real repository, read-only.

| Test ID   | Spec-AC    | Type        | File path (expected)                   | Description | Mutation | Status  |
|-----------|------------|-------------|----------------------------------------|-------------|----------|---------|
| TEST-1420 | Spec-AC-01 | integration | tests/skills/test-aai-suite-select.sh | real repo --shards 4: the sorted SHARD suite column equals the sorted find list of test-aai-*.sh, each once; SHARDS line says suites= that count; exit 0 | sed:s/for \(const o of order\) \{/for (const o of order.slice(1)) {/ | green |
| TEST-1421 | Spec-AC-01 | integration | tests/skills/test-aai-suite-select.sh | fixture of 5 suites (aai-alpha, aai-bravo, aai-delta, aai-echo, aai-zulu) with weights for 3 of them plus an orphan row: all 5 assigned exactly once, WEIGHT_ORPHAN names the orphan, the orphan is never assigned | sed:s/\^test-aai-\.\*/^test-aai-[a-c].*/ | green |
| TEST-1422 | Spec-AC-02 | integration | tests/skills/test-aai-suite-select.sh | fixture of 6 suites with a weight tie at N=2: stdout equals a golden plan byte for byte, and two runs are identical | sed:s/a\.name < b\.name \? -1/a.name < b.name ? 1/ | green |
| TEST-1423 | Spec-AC-02 | integration | tests/skills/test-aai-suite-select.sh | real repo with the committed weights at N=4: the largest shard weight-sum is at or below the larger of ceil(1.05 x ceil(total/4)) and the largest weight | sed:s/loads\.indexOf\(Math\.min\(\.\.\.loads\)\)/order.indexOf(o) % n/ | green |
| TEST-1424 | Spec-AC-02 | integration | tests/skills/test-aai-suite-select.sh | real repo N=4 and the TEST-1422 fixture: inside every shard the emitted weights never increase | sed:s/return b\.w - a\.w/return a.w - b.w/ | green |
| TEST-1425 | Spec-AC-02 | integration | tests/skills/test-aai-suite-select.sh | fixture suite with no weight row is emitted with weight= the largest known weight and is the first suite of its shard | sed:s/const unknownWeight = maxKnownWeight;/const unknownWeight = 1;/ | green |
| TEST-1426 | Spec-AC-03 | integration | tests/skills/test-aai-suite-select.sh | --shards 0, 9, abc and a missing value each print SHARD_FALLBACK reason=invalid-shard-count, no SHARD line, exit 0 | sed:s/const MAX_SHARDS = 8;/const MAX_SHARDS = 800;/ | green |
| TEST-1427 | Spec-AC-03 | integration | tests/skills/test-aai-suite-select.sh | a weights line that is not name-then-integer prints WEIGHTS_IGNORED reason=malformed-line line=N and still assigns every fixture suite exactly once, exit 0 | sed:s/return \{ weights: new Map\(\), ignored:/throw new Error('malformed'); return { weights: new Map(), ignored:/ | green |
| TEST-1428 | Spec-AC-03 | integration | tests/skills/test-aai-suite-select.sh | a repo root with no tests/skills suites prints SHARD_FALLBACK reason=no-suites and no SHARD line, exit 0 | sed:s/if \(names\.length === 0\)/if (false)/ | green |
| TEST-1429 | Spec-AC-03 | integration | tests/skills/test-aai-suite-select.sh | negative control: without --shards the default mode on the small_map fixture prints the golden pre-change output byte for byte and no SHARD line | sed:s/if \(opts\.shards !== null\)/if (true)/ | green |
| TEST-1430 | Spec-AC-04 | integration | tests/skills/test-aai-suite-select.sh | --check on a complete 3-shard fixture plan exits 0 and prints exactly shard_ids=[1,2,3] | sed:s/sort -un/sort -unr/ | green |
| TEST-1431 | Spec-AC-04 | integration | tests/skills/test-aai-suite-select.sh | --check exits non-zero naming the suite for a plan missing one on-disk suite, and for a plan naming a suite not on disk | sed:s/!= "\$expected_set"/!= "$planned_set"/ | green |
| TEST-1432 | Spec-AC-04 | integration | tests/skills/test-aai-suite-select.sh | --check exits non-zero naming the suite for a plan that assigns one suite to two shards | sed:s/"\$dup_count" -ne 0/"$dup_count" -lt 0/ | green |
| TEST-1433 | Spec-AC-04 | integration | tests/skills/test-aai-suite-select.sh | a plan holding only a SHARD_FALLBACK line passes --check printing shard_ids=["all"], and --extract all prints __ALL__ | sed:s/shard_ids=\["all"\]/shard_ids=[]/ | green |
| TEST-1434 | Spec-AC-04 | integration | tests/skills/test-aai-suite-select.sh | --extract 2 prints exactly shard 2's suites in plan order; --extract 7 on a 3-shard plan exits non-zero | sed:s/== idx/>= idx/ | green |
| TEST-1435 | Spec-AC-04 | integration (SEAM) | tests/skills/test-aai-suite-select.sh | real repo: select-suites.mjs --shards 4 into a plan file, --check prints shard_ids=[1,2,3,4], and the union of --extract for every id equals the find list, each once | sed:s/SHARD \$\{i \+ 1\} /SHARD ${i} / | green |
| TEST-1436 | Spec-AC-05 | integration | tests/skills/test-aai-suite-select.sh | workflow pin: select has a step id shard with no if running --shards 4 and --check and exporting shard_ids and shard_plan; skills-full has fail-fast false, a matrix over fromJSON of shard_ids, fetch-depth 0, the plan passed through env, --extract and one test-framework.sh call | sed:s/fail-fast: false/fail-fast: true/ | green |
| TEST-1437 | Spec-AC-05 | integration | tests/skills/test-aai-suite-select.sh | negative control: the gate keeps its exact name, needs list, always() and the full-mode success line W4; TEST-013 and TEST-018 stay green | sed:s/skills-full\.result \}\}" = "success"/skills-full.result }}" != "failure"/ | green |
| TEST-1438 | Spec-AC-05 | integration | tests/skills/test-aai-suite-select.sh | the skills-full leg re-runs --check on its own checkout (line W3) before --extract | sed:s/--check shard-plan\.txt tests\/skills >\/dev\/null/--extract 1 shard-plan.txt >\/dev\/null/ | green |
| TEST-1439 | Spec-AC-05 | integration | tests/skills/test-aai-suite-select.sh | real map replay: tests/skills/suite-weights.tsv and tests/skills/lib/shard-plan-check.sh each select aai-suite-select with no FULL_RUN line | sed:s/- tests\/skills\/suite-weights\.tsv/- tests\/skills\/suite-weights.tsx/ | green |
| TEST-1440 | Spec-AC-04 | integration | tests/skills/test-aai-suite-select.sh | BLOCKING-1 remediation (post-freeze, see Amendment): a plan naming a suite that exists only nested (recursively discoverable, no top-level test-<name>.sh) makes --check exit non-zero naming the suite, instead of passing on the recursive proof alone | sed:s/if \[\[ ! -f "\$skills_dir\/test-\$name\.sh" \]\]; then/if false; then/ | green |

## Verification

Commands, all from the repository root:
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-select.sh`
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hygiene-pack.sh`
  (one-row-per-suite pin, pipe ratchet on the new helper, test registration)
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-check-state.sh`,
  `test-aai-docs-audit.sh`, `test-aai-spec-lint.sh` (the always-on core)
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-lightweight-lane.sh`.
  It covers `lane-gate.mjs` (its suite-map row), which invokes the selector's
  default mode, so it must not move.
- the full sweep once before close: `AAI_TEST_TIMEOUT=3000 bash
  .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh`
- `node .aai/scripts/mutation-run.mjs` per Test Plan row, then
  `node .aai/scripts/mutation-gate.mjs --spec <this spec>`
- `node .aai/scripts/spec-lint.mjs --path <this spec>`
- `node .aai/scripts/docs-audit.mjs --strict`
- **Live CI run (the outcome the owner asked for).** Apply the `ci-full` label
  to the PR, then push, because the label is read when a run starts. On that
  run, `gh run view <id> --json jobs` and the leg logs must show: `gate`
  success; exactly 4 `skills-full` legs, all success; the `[ n/k] <suite>`
  PASS lines of the 4 leg logs united give every suite `find` lists at the
  PR head, each exactly once; the longest leg (startedAt to completedAt) at or
  below **660 s**, against the 1120 s baseline median. The PR's own
  selected-mode run duration is recorded alongside it, with no threshold,
  because selected mode does not change.

PASS criteria: every TEST-xxx green, every Spec-AC terminal, the named suites
green, the mutation gate satisfied, `docs-audit --strict` CLEAN, AND the live
CI run above meeting every stated observable.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: `ci-test-selection-narrowing-and-sharding`
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available
- for the live CI run: the run id, the head SHA it ran on (must equal the PR
  head), the 4 leg durations, and the union count

### Evidence by strategy

Recorded strategy is `tdd`, so this spec demands the `tdd / hybrid` row: a
stored RED artifact per AC-gating test under `docs/ai/tdd/`, the full
verification matrix above, and a verified mutation record per Test Plan row.

| Strategy     | Evidence this spec may demand                                   |
|--------------|-----------------------------------------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop         | per-TEST-xxx green runs; RED-proof observed, storage optional    |
| direct       | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested     | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |

## Review scope
`.aai/scripts/select-suites.mjs`, `tests/skills/suite-weights.tsv`,
`tests/skills/lib/shard-plan-check.sh`, `.github/workflows/skill-suite.yml`,
`tests/skills/suite-map.yaml`, `tests/skills/test-aai-suite-select.sh`,
`docs/product/ci-test-impact-selection.md`, `CHANGELOG.md`, this spec.

No file in this scope is in `docs/ai/docs-audit.yaml` `protected_paths_l3`
(state.mjs, lib/state-engine.mjs, lib/state-core.mjs, allocate-doc-number.mjs,
pre-commit-checks.sh/.ps1, WORKFLOW.md, CONSTITUTION.md), so the ceremony
level is 2. Companion obligations: no prompt-corpus bytes are added and no
new `.aai/**` file is created, so neither applies.

## Registry items closed by this scope

Read from `node .aai/scripts/follow-ups.mjs list` (170 lines) and scanned for
this scope's subjects (suite, shard, select, sweep, runner, CI timeout):

- none closed.

## Registry items touched, not closed

Two open items whose SUBJECT this scope touches, NOT CLOSED by it — each is
its own follow-up, unaffected by this scope's own closure claim above:
- `fu-watchdog-3000-exceeds-ci-timeout` (P3) — the inner watchdog
  (`AAI_TEST_TIMEOUT` 3000 s) sits above the CI job ceilings. Each leg keeps
  `timeout-minutes: 30`, so the inversion is unchanged. Sharding makes a leg
  about four times shorter, but the item is about the ordering of two limits,
  not about how long a leg runs. Stays open.
- `fu-ps1-quality-outside-sweep-glob` (P3) — `test-ps1-quality.sh` is outside
  the `test-aai-*.sh` rule. This scope deliberately keeps that rule as the
  definition of "every suite", so the item is neither fixed nor worsened.
  Stays open.

## Out of scope (suggested follow-ups, not filed)

These ids are `suggested:`. `follow-ups.mjs add` was not run by this planning
dispatch.
- suggested: `fu-lib-graph-narrowing-after-sharding` — intake steps 1-3.
  Re-measure once sharding has landed. Prototype facts for that ride: textual
  reference graph; 6 of 13 shared-lib merges convertible, at 41-55 of 101
  suites; 6 more stay FULL_RUN through `allocate-doc-number.mjs` (L3) importing
  `docs-model.mjs` and `guard-config.mjs`; `check-cd-subshell-leak.mjs` must be
  mapped first; 34 files reference the lib directory generically and must count
  as referrers of every lib; `canon.mjs` holds the repo's one computed
  `import()` (non-lib target, `validation-waiver.mjs`).
- suggested: `fu-inert-path-class` — intake step 4. `.gitattributes` and
  `docs/decisions/**` were the 2 unmapped FULL_RUNs out of 40. Its interaction
  with any future narrowing has to be specified there.
- suggested: `fu-sweep-floor-is-one-suite` — after sharding, the full run's
  floor is `aai-learned-append` (434 s). Only splitting that suite lowers it,
  and the intake rules suite content out of scope.
- suggested: `fu-framework-discover-exit-swallowed` — `code_review.md`
  BLOCKING-1 (review-20261003T124300Z.md). `test-framework.sh`'s
  `discover_tests()` calls `exit 2` on a missing `--skill` file inside
  `done < <(discover_tests)`; the process-substitution subshell's exit is
  discarded, so `--skill` keeps running the suites listed before the missing
  one and the leg still exits 0. This spec's own fix is in
  `shard-plan-check.sh --check` (TEST-1440, see Amendment), which now catches
  the shape before a leg ever runs; `test-framework.sh` itself is out of
  scope here (its own pre-existing defect, also reachable from plain
  selected-mode `--skill` usage outside sharding) and is named but not fixed.

## Residual risks
- RR-1. The 660 s observable is one CI run on a shared hosted runner. Runner
  noise can move it by tens of seconds. The threshold sits about 1.5x above
  the 434 s prediction for that reason. It does not prove the speed-up on
  every run.
- RR-2. `gate` relies on GitHub's documented rule that a matrix job's
  `result` is `success` only when every leg succeeded. No test in this repo
  can run GitHub's aggregator. The pin (TEST-1437) proves `gate` reads that
  result, not that GitHub computes it as documented.
- RR-3. A suite that silently depends on another suite having run earlier in
  the same job would break under a different order or runner. Suites already
  run concurrently and in isolated clones under `AAI_TEST_PARALLEL=4`, which
  would already surface such a dependency as a flake. Not proven absent.
- RR-4. Sharding uses about four times the runner count per full run.
  Wall-clock falls, runner-minutes rise slightly (setup per leg). Hosted-runner
  concurrency limits could queue legs on a busy day.
- RR-5. A pull_request merge ref that moves between `select` and a leg is
  caught by the leg's re-check (it fails loudly and needs a re-run). It is not
  prevented. The selected-mode path has the same pre-existing race on its diff
  and is untouched here.
- RR-6 (NB-4, review-20261003T124300Z.md, accepted residual). TEST-1436 does
  not pin that the shard step has no `if:` (AC-05's "unconditionally"), and
  its fetch-depth check is a file-wide count that cannot see a single leg.
  Both gaps fail LOUDLY or NARROWLY in CI (a workflow error, or a
  layer-profiles failure on a leg) rather than silently dropping coverage, so
  this is an assurance-strength finding with no observed bite, not remediated
  in this round.
