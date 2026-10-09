---
id: spec-nested-suite-reruns-duplicate-sweep-time
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 867870284a10fc48a82dce113099b83e899214953d1d2b2c8304617c2a145196
ceremony_level: 2
links:
  requirement: null
  rfc: null
  intake: docs/issues/DEBT-DRAFT-nested-suite-reruns-duplicate-sweep-time.md
  pr: []
  commits: []
---

# Spec — Suites stop re-running other suites; suite-map.yaml declares companions and select-suites selects them

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/DEBT-DRAFT-nested-suite-reruns-duplicate-sweep-time.md (techdebt intake, id `nested-suite-reruns-duplicate-sweep-time`)
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only for `.aai/scripts/*.mjs`; bash suites under `tests/skills/`)

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Problem, as re-verified by Planning (2026-10-09)

Planning did not take the intake's numbers on trust. It measured on a
disposable detached worktree of `8f6590f1` (this branch's base), on this host
(16 CPU, sweep width 8).

### Method

1. A full traced sweep: `BASH_ENV=<tracer> AAI_TEST_TIMEOUT=3000 env -u
   AAI_ROLE bash tests/skills/test-framework.sh`. The tracer is sourced by
   every non-interactive bash. When the process runs a `test-aai-*.sh` file it
   logs the suite name, its positional arguments, and the nearest ancestor
   process that is itself running a `test-aai-*.sh` file (walked with `ps`).
   A nested run with no positional argument is a WHOLE-suite run; one with an
   argument is a selector run. Wall time 799 s, 106 suites, 104 PASS, 1 SKIP
   (`aai-state`, exit 42, local environment), 1 FAIL (`aai-win-fallback`,
   python-path fixture, local environment, unrelated to this scope).
   Summed per-suite time (the sweep CPU): **4,379 s**.
2. A static cross-check: every non-comment line in the 106 suites that names
   another on-disk suite, read back to its enclosing function.
3. Six worst cases profiled again, in parallel, with per-line timestamps
   (`env -u AAI_ROLE AAI_TEST_TIMEOUT=3000 bash tests/skills/test-<suite>.sh`).

### Inventory: 26 suites, 34 functions run another whole suite

Duplicate time is the time spent inside the nested run, taken from the sweep
durations of the nested suite (or from the profile where marked P).

| Outer suite | Function | Nested whole suites | Frozen row it backs (preliminary) | Duplicate s |
|---|---|---|---|---|
| aai-learned-append | test_015_profiles_classified | layer-profiles | SPEC-0095 TEST-015 | 77 (P) |
| aai-learned-append | test_016_prompt_diet_ledger | prompt-diet | SPEC-0095 TEST-016 | 4 (P) |
| aai-learned-append | test_017_companion_suites_green | friction-wiring, hygiene-pack | SPEC-0095 TEST-017 | 364 (P) |
| aai-delta-stage3 | test_007_seam_survival | delta-stage1, delta-stage2, spec-lint, docs-audit | SPEC-0038 TEST-007 | 199 (P) |
| aai-delta-stage2 | test_006_seam_survival | delta-stage1, spec-lint | SPEC-0037 TEST-006 | 38 |
| aai-delta-stage1 | test_007_docs_canon_suite | docs-canon | SPEC-0034 TEST-007 | 3 |
| aai-repo-tripwire | test_019_full_run_leaves_no_temp_directory_behind | repo-tripwire (itself) | SPEC-0179 TEST-437 | 81 (P) |
| aai-repo-tripwire | test_006_fixed_suites_leave_the_real_tree_untouched | doc-numbering, deslop | SPEC-0137 TEST-006 | 68 (P) |
| aai-sync-seed | test_781_regression_suites_exit_zero | layer-drift, layer-profiles, bootstrap, hooks-overlay | SPEC-0199 TEST-781 | 110 (P) |
| aai-doctor | test_031_hygiene_set | layer-profiles, suite-select | SPEC-0100 (doctor) TEST-031 | 83 (P) |
| aai-ceremony-levels | test_010_seam_survival | orchestration-dispatch, prompt-diet | SPEC-0030 TEST-010 | 34 (P) |
| aai-ceremony-levels | test_017_seam_survival_spec0041 | orchestration-dispatch, prompt-diet, plus its own test_001..010 by selector | SPEC-0041 TEST-007 | 36 (P) |
| aai-feedback-upsert | test_009_profiles | layer-profiles | SPEC-0082 TEST-009 | 84 |
| aai-feedback-upsert | test_1312_surfaces_state_the_contract | prompt-diet | SPEC-0203 TEST-1312 | 4 |
| aai-friction-wiring | test_006_companion_suites | layer-profiles, prompt-diet | SPEC-0079 TEST-006 | 88 |
| aai-friction | test_014_profiles_classified | layer-profiles | SPEC-0078 TEST-014 | 84 |
| aai-ledger-merge | test_667_new_script_is_classified | layer-profiles | SPEC-0185 TEST-667 | 84 |
| aai-merge-policy | test_1530_companion_wiring | layer-profiles | SPEC-0207 TEST-1530 | 84 |
| aai-release | test_020_seam2_layer_profiles | layer-profiles | SPEC-0063 TEST-020 | 84 |
| aai-hitl-propagation | test_015_existing_suites_green | orchestration-dispatch, state | SPEC-0066 TEST-015 | 49 |
| aai-doc-number-reservation | test_011_backcompat_suite | doc-numbering (via aai-run-tests.sh) | SPEC-0047 TEST-011 | 42 |
| aai-doc-number-reservation | test_107_regression_doc_numbering_suite | doc-numbering | SPEC-0090 TEST-107 | 42 |
| aai-secrets-preflight | test_006_additive_budget_regression | intake | SPEC-0045 TEST-006 | 19 |
| aai-deslop | test_011_advisory_skills_suite_still_green | advisory-skills | SPEC-0132 TEST-011 | 9 |
| aai-deslop | test_012_prompt_diet_ledger_true_up | prompt-diet | SPEC-0132 TEST-012 | 4 |
| aai-advisory-skills | test_013_prompt_diet_floor | prompt-diet | SPEC-0031 TEST-013 | 4 |
| aai-constitution | test_009_prompt_diet_floor | prompt-diet | SPEC-0028 TEST-009 | 4 |
| aai-debug-gate | test_007_prompt_diet_suite | prompt-diet | SPEC-0027 TEST-007 | 4 |
| aai-git-ref-guard | test_312_contract_and_diet | prompt-diet | SPEC-0156 TEST-312 | 4 |
| aai-hooks-overlay | test_014_prompt_diet_floor | prompt-diet | SPEC-0029 TEST-014 | 4 |
| aai-spec-lint | test_011_seam_survival | prompt-diet | SPEC-0033 TEST-011 | 4 |
| aai-state | test_008_lib_extraction_regression | check-state | SPEC-0012 TEST-008 | 1 |
| aai-state | test_071_rguard_predicate_which_file | check-state (under AAI_ROLE=subagent) | SPEC-0180 TEST-037 | 1 |
| aai-tdd-evidence | test_005_additive_regression | tdd | SPEC-0044 TEST-005 | 0 |

The "frozen row" column is PRELIMINARY: Planning read each function's header
citation and the matching Test Plan row, but several outer suites cite more
than one spec. Implementation confirms every citation before writing the
disclosure records (Spec-AC-13) and corrects the list there, never silently.

Sum of duplicate time: about **1,800 s of 4,379 s (41%)**. Removing the 32
functions that need no allowlist (all but the two `aai-repo-tripwire` /
`aai-state` rows decided in D6) is expected to cut about **1,730 s (40%)**.

Six worst cases, profiled (seconds of the suite total spent in nested runs):
`aai-learned-append` 445 of 446, `aai-delta-stage3` 199 of 200,
`aai-repo-tripwire` 150 of 164, `aai-sync-seed` 110 of 371, `aai-doctor` 83
of 173, `aai-ceremony-levels` 70 of 73.

Selector-form cross-suite runs exist too (`aai-hygiene-pack` probes 70 suites
with `no_such_test_xyz` and runs eight single functions; `aai-roadmap` runs
seven single functions; `aai-orchestration-dispatch` runs six
`aai-ceremony-levels` functions). They are cheap, they pin specific
contracts, and they are OUT of this scope (D7).

### Corrections to the intake

1. **26 suites and 34 functions, not 28 and 54.** The higher count included
   selector-form runs and fixture suites whose file names match real suites
   (for example `aai-repo-tripwire`'s ratchet fixtures named
   `test-aai-state.sh` and `test-aai-metrics.sh`, which take under 1 s and
   are not the real suites).
2. **The duplicate share is about 41%, not 32–38%**, on this host.
3. **"A change to the companion's mapped paths selects both suites" is the
   wrong direction.** A nested run fired when the OUTER suite was selected.
   When only the companion's own paths change, the companion is selected by
   its own globs, and the outer suite was never involved. The preserved
   property is: when suite X is selected (by any path, or as core), every
   companion X declares is selected too. Spec-AC-01 and Spec-AC-04 pin that.
4. **Two nested runs prove something no companion entry can**, and the
   self-run in `aai-repo-tripwire` proves a property of the suite's own full
   run. See D5 and D6. The intake's "no suite runs another whole suite"
   becomes "none outside a three-row reasoned allowlist".

## Root cause (decided)

`select-suites.mjs` maps changed paths to suites by glob only. When a change
touched a file another suite pins (a new `.aai/**` file that
`aai-layer-profiles` classifies, prompt bytes that `aai-prompt-diet` counts),
the only way to make the pinning suite run in selected mode was to call it
from the suite that was selected. In full mode the companion runs on its own
anyway, so every nested call is pure duplication there.

## Implementation strategy
- Strategy: tdd
- Rationale: The owner chose `tdd` at intake. It is recorded in STATE with
  `source: intake` and `ref_id: nested-suite-reruns-duplicate-sweep-time`,
  and in the intake `## Notes` line "Implementation mode (user choice): tdd".
  Planning agrees: this changes selector behavior that CI depends on, and it
  rewrites 34 test functions whose only safety net is that each rewritten
  assertion is first observed failing. Every per-suite RED comes naturally:
  the new `assert_companions` call fails until the companion row is declared.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: the scope touches 26 suites, the CI selector and the
  shard weights, and it needs a pushed branch for the full-mode CI run that
  re-seeds the weights. The main checkout is shared with other live sessions.
  The worktree already exists.
- User decision: worktree (already in use)
- Base ref: main
- Worktree branch/path: `debt/nested-suite-reruns-duplicate-sweep-time` at `/Users/ales/Projects/aai-debt-nested-suite-reruns-duplicate-sweep-time`
- Inline review scope: `.aai/scripts/select-suites.mjs`, `tests/skills/suite-map.yaml`, `tests/skills/suite-weights.tsv`, `tests/skills/lib/companion-assert.sh`, `tests/skills/lib/nested-suite-lint.mjs`, `tests/skills/lib/nested-suite-allowlist.tsv`, `tests/skills/test-aai-suite-select.sh`, `tests/skills/test-aai-hygiene-pack.sh`, and the 24 outer suites named in the inventory (`tests/skills/test-aai-{learned-append,delta-stage1,delta-stage2,delta-stage3,repo-tripwire,sync-seed,doctor,ceremony-levels,feedback-upsert,friction-wiring,friction,ledger-merge,merge-policy,release,hitl-propagation,doc-number-reservation,secrets-preflight,deslop,advisory-skills,constitution,debug-gate,git-ref-guard,hooks-overlay,spec-lint,state,tdd-evidence}.sh`)

## Design decisions

### D1. The companion declaration

Each `suites:` row may carry an optional `companions:` list, placed BEFORE
`globs:`, at the same indentation as `globs:` (4 spaces), with items at 6
spaces, sorted by name:

```
  aai-learned-append:
    companions:
      - aai-friction-wiring
      - aai-layer-profiles
      - aai-prompt-diet
    globs:
      - .aai/scripts/learned-append.mjs
```

Meaning: whenever this suite is selected, or is core, every suite it names is
selected too. A companion entry never adds a glob and never changes which
paths are mapped, so it cannot turn an unmapped path into a mapped one.

Rules, enforced in `loadContext` (fail-open, like the core-entry checks):
- a companion name matches `[A-Za-z0-9_-]+`, else the map is malformed;
- `if (!suites[comp])` the map is malformed: `companion has no suites row: <suite> -> <comp>`;
- a suite naming itself is malformed: `companion names its own row: <suite>`;
- a malformed map yields `FULL_RUN reason=internal-error` in whole-PR mode
  and `DELTA_REFUSED reason=internal-error` in delta mode, exactly as a ghost
  core entry does today.

A core suite is never declared as a companion. It is redundant, because core
always runs, and a redundant edge cannot be pinned by a mutation. The outer
suite's own `assert_companions` call (D4) still names it, and accepts a `CORE`
line, so a core suite that later leaves core reddens every outer suite that
relied on it.

The parser keeps its line-based shape. `companions:` at indent 4 switches the
row into companion mode and `globs:` switches it back, so a companion item can
never be read as a glob. The row-count pin in `aai-hygiene-pack`
(`^  [a-z0-9][a-z0-9-]*:$`, 106) is unaffected because companion lines sit at
indent 4 and 6. The header comment of `suite-map.yaml` gains a `companions`
paragraph in its CONTRACT.

### D2. Selection is transitive

`expandCompanions(selected, ctx)` returns the selection with companions added.
It walks a worklist named `queue`, seeded with the core suites and then the
selected suites in their existing order. For each suite taken from `queue`,
each companion `comp` that is neither core nor already selected is added with
the value `'companion:' + parent` (where `parent` is the suite that named it),
and then `queue.push(comp)`. A suite is added at most once, so a cycle
terminates. Insertion order is deterministic.

Transitive closure is what the nested runs did: `aai-delta-stage3` ran
`aai-delta-stage2`, which ran `aai-delta-stage1`, which ran `aai-docs-canon`.
A non-transitive rule would drop `aai-docs-canon` from a stage3-only change.

Output: companions print as ordinary lines after the path-selected ones,
`SELECTED <suite> reason=companion:<parent>`. `DROPPED` counts companions as
selected. The workflow reads only the second field of `SELECTED`/`CORE` lines
(`.github/workflows/skill-suite.yml`), and `lane-gate.mjs` reads only
`FULL_RUN`, so neither changes. `ci-select.mjs` passes the selector's lines
through unchanged in both whole-PR and delta mode, so it needs no change.

Every outcome that prints a selection uses `printSelection`. The two
empty-diff branches (whole-PR and delta) call `printSelection(ctx, new Map())`
instead of printing only `CORE` lines, so the companions of a core suite are
selected on every PR. Today that adds exactly one suite: `aai-spec-lint` is
core and declares `aai-prompt-diet` (4 s), which it already ran nested on
every PR. With no `companions:` anywhere in a map, every output is
byte-identical to today's.

Shard mode (`--shards`) is unchanged: it plans the full sweep, which runs
every suite.

### D3. The declared edge set (36 edges, 24 rows)

Derived from the inventory, minus core companions (D1), minus the allowlist
(D6), minus self-runs:

| Row | Companions |
|---|---|
| aai-advisory-skills | aai-prompt-diet |
| aai-ceremony-levels | aai-orchestration-dispatch, aai-prompt-diet |
| aai-constitution | aai-prompt-diet |
| aai-debug-gate | aai-prompt-diet |
| aai-delta-stage1 | aai-docs-canon |
| aai-delta-stage2 | aai-delta-stage1 |
| aai-delta-stage3 | aai-delta-stage1, aai-delta-stage2 |
| aai-deslop | aai-advisory-skills, aai-prompt-diet |
| aai-doc-number-reservation | aai-doc-numbering |
| aai-doctor | aai-layer-profiles, aai-suite-select |
| aai-feedback-upsert | aai-layer-profiles, aai-prompt-diet |
| aai-friction | aai-layer-profiles |
| aai-friction-wiring | aai-layer-profiles, aai-prompt-diet |
| aai-git-ref-guard | aai-prompt-diet |
| aai-hitl-propagation | aai-orchestration-dispatch, aai-state |
| aai-hooks-overlay | aai-prompt-diet |
| aai-learned-append | aai-friction-wiring, aai-layer-profiles, aai-prompt-diet |
| aai-ledger-merge | aai-layer-profiles |
| aai-merge-policy | aai-layer-profiles |
| aai-release | aai-layer-profiles |
| aai-secrets-preflight | aai-intake |
| aai-spec-lint | aai-prompt-diet |
| aai-sync-seed | aai-bootstrap, aai-hooks-overlay, aai-layer-drift, aai-layer-profiles |
| aai-tdd-evidence | aai-tdd |

Not declared (core): `aai-hygiene-pack` for learned-append, `aai-spec-lint`
for delta-stage2 and delta-stage3, `aai-docs-audit` for delta-stage3,
`aai-check-state` for state. Each is still named in the outer suite's
`assert_companions` call. `aai-spec-lint` is itself core, so its one
companion is selected on every PR (D2).

Edges that a transitive path already implies (for example learned-append to
layer-profiles, implied by learned-append to friction-wiring) stay declared,
because each records exactly what the removed function asserted. Only the
edge-set pin (TEST-032) can catch their removal, and it does.

### D4. What replaces a nested run: `assert_companions`

A new sourced helper, `tests/skills/lib/companion-assert.sh`, defines
`assert_companions <outer-suite> <companion>...`. It feeds
`tests/skills/test-<outer-suite>.sh` to
`node .aai/scripts/select-suites.mjs --files-from - --repo-root <root>` (the
REAL map; `<root>` defaults to the suite's `PROJECT_ROOT`), and requires a
`SELECTED <companion> ` or `CORE <companion> ` line for every companion
named. On a miss it prints `MISSING companion <companion> for <outer-suite>`
and runs `return 1`; on success it prints one INFO line naming the companions,
so a developer who runs the outer suite alone sees which suites to run next.
It takes about 0.1 s.

Each of the 32 rewritten functions keeps its name, its TEST id and every
assertion that is not a nested run (for example `aai-delta-stage3` TEST-007
keeps its strict repo audit, `aai-doctor` TEST-031 keeps its registration,
suite-map and PROFILES checks, `aai-learned-append` TEST-015 keeps its
PROFILES classification check). Only the nested invocation is replaced by an
`assert_companions` call naming the same suites. This is an integration test
across the real seam: the outer suite's own file path, through the real
selector, against the real map.

Suites whose `main` ignores positional arguments gain the house single-test
idiom (`if [[ $# -ge 1 ]]; then check_deps; "$1"; else main; fi`, adapted to
each file's existing setup) only where `mutation-run.mjs --selector` needs it
for a Test Plan row below. Planning found ten candidates: advisory-skills,
constitution, debug-gate, doc-number-reservation, hitl-propagation,
hooks-overlay, repo-tripwire, spec-lint, tdd-evidence, and delta-stage3
(which selects by the `ONLY` env var today). Implementation verifies each
before adding it.

### D5. What each nested run actually proved

- **Pure duplication (30 functions).** The nested run asserted "suite Y exits
  0 on this tree". In full mode Y runs on its own on the same tree. In
  selected mode, D2 selects Y whenever the outer suite is selected. The
  companion entry plus `assert_companions` preserves the coverage exactly.
- **`aai-ceremony-levels` test_017 re-runs its own test_001..010 by selector.**
  The same run already executes those ten functions in `main`. The loop is
  deleted, with nothing in its place.
- **`aai-repo-tripwire` TEST-437 (test_019) re-runs its whole suite** to prove
  that a full run leaves no `aai-tripwire-fixture.*` or
  `aai-tripwire-registry.*` entry behind. That is a property of the suite's
  own run, so no companion can carry it. Replacement, in-process: the cleanup
  loop becomes a function `drain_workdirs`, which the EXIT trap also calls.
  test_019 runs LAST in `main`. It creates one fixture through the exact
  defect shape, `d="$(new_fixture)"` (a command substitution, so a subshell),
  as a positive control. It records how many directories the registry holds,
  calls `drain_workdirs`, and then requires that no directory the registry
  named still exists and that the registry held at least one entry. A broken
  `register_workdir` (the 2026-09 defect, 13 leaked directories) reddens it.
  The `AAI_TRIPWIRE_NESTED_437` recursion guard is deleted. The claim of
  SPEC-0179 TEST-437 ("a full run leaves no temporary directory") holds
  under every run that reaches test_019 in `main`.

### D6. The allowlist: three rows, each a distinct proof

`tests/skills/lib/nested-suite-allowlist.tsv`, tab-separated
`<outer suite file>`, `<function>`, `<nested suite file>`, `<reason>`:

1. `test-aai-repo-tripwire.sh`, `test_006_fixed_suites_leave_the_real_tree_untouched`, `test-aai-doc-numbering.sh`
2. `test-aai-repo-tripwire.sh`, `test_006_fixed_suites_leave_the_real_tree_untouched`, `test-aai-deslop.sh`
   Reason for both: SPEC-0137 TEST-006 runs the two suites that once
   rewrote tracked files against the REAL checkout and compares
   `git status --porcelain=v1` and HEAD before and after. Under framework
   isolation every suite runs in a disposable clone, and the framework
   tripwire watches only the shipping checkout, so nothing else observes
   these two suites writing to the checkout they run in. About 68 s.
3. `test-aai-state.sh`, `test_071_rguard_predicate_which_file`, `test-aai-check-state.sh`
   Reason: SPEC-0180 TEST-037 (d) runs the core suite under
   `AAI_ROLE=subagent` with no environment scrub. Sweeps and CI run without
   `AAI_ROLE`, so no companion run carries that environment. About 1 s.

The allowlist only shrinks: the lint fails on a row that matches no finding
(stale), and TEST-034 pins the row count at 3.

### D7. The hygiene ratchet: `tests/skills/lib/nested-suite-lint.mjs`

A Node stdlib scanner over `tests/skills/test-aai-*.sh`. It reports a WHOLE
nested run: an invocation by `bash`, `sh`, or `aai-run-tests.sh` (literal
path or a variable holding it), whose suite argument resolves to an on-disk
`tests/skills/test-aai-*.sh`, and which is followed by no further positional
argument before a redirection, a pipe, a closing parenthesis, `;`, `&&`,
`||` or end of line. The suite argument resolves through:
1. a literal containing `test-aai-<name>.sh`;
2. a `$VAR` or `${VAR}` whose assignment in the same file ends in
   `test-aai-<name>.sh` (`resolveVarSuite(name, vars)`);
3. a token holding the loop variable of an enclosing `for <var> in <list>`
   whose list names `test-aai-*.sh` files or `tests/skills/test-aai-*.sh`
   paths;
4. the suite's own path by `$0`, `${BASH_SOURCE[0]}` or a `*_SELF` variable.

Comment lines and heredoc bodies are skipped. A name that is not an on-disk
suite (a fixture such as `test-aai-wsuite.sh` or `test-aai-t-clean.sh`) is
never reported. A selector-form call (a positional argument after the suite)
is never reported: it is cheap, it pins one contract, and the dynamic trace
showed none of them re-running a whole suite (Residual risk RR-3).

Output: one `<file>:<line>: <function>: nested whole-suite run of <suite>`
per finding, then `TOTAL: <n>`. With `--allowlist <tsv>` it subtracts
allowlisted findings, adds one `STALE allowlist row: ...` line per row that
matches nothing, and exits 1 when anything is left; it exits 2 on its own
plumbing failure. It is wired into `aai-hygiene-pack` (core, so it gates
every PR, the same reasoning as the pipe-into-grep ratchet).

Its recall is proven against reality, not against its author: run over the
BASE tree (`git archive` of the merge base into a temp directory), it must
report every one of the 34 inventory functions.

### D8. Frozen-spec amendments: measurement class, ledger only

No frozen spec text changes. Every Test Plan row in the inventory keeps its
TEST id, its function and its claim ("suite Y stays green"); only HOW the
claim is measured changes, from a nested execution to a companion selection
plus Y's own run. That is the `measurement` class of `.aai/system/AUTONOMOUS_LOOP.md` section 6a.
Implementation records one disclosure per affected spec:

`node .aai/scripts/spec-amend.mjs add --spec <spec path> --ref nested-suite-reruns-duplicate-sweep-time --class measurement --signoff none --what "<rows>: nested run of <suites> replaced by a companion declaration plus assert_companions" --why "duplicate sweep time; coverage kept by select-suites companion selection"`

Not editing the frozen bytes keeps every `frozen_sha256` valid. The two
replacement cases (D5, TEST-437 and ceremony-levels test_017) are also
`measurement`: the predicate is unchanged and still decided by a test in the
same suite. The three allowlisted rows (D6) are unchanged and get no record.
No row needs `contract` class, so no owner signature is owed (see HITL Q1 for
the one judgement the owner may want to see).

Preliminary spec list (Implementation confirms it in Batch 5 and pins the
final list in TEST-036): SPEC-0012, SPEC-0027, SPEC-0028, SPEC-0029,
SPEC-0030, SPEC-0031, SPEC-0033, SPEC-0034, SPEC-0037, SPEC-0038, SPEC-0041,
SPEC-0044, SPEC-0045, SPEC-0047, SPEC-0063, SPEC-0066, SPEC-0078, SPEC-0079,
SPEC-0082, SPEC-0090, SPEC-0095, SPEC-0100, SPEC-0132, SPEC-0156, SPEC-0179,
SPEC-0185, SPEC-0199, SPEC-0203, SPEC-0207.

Mutation records: Planning searched every local record under
`docs/ai/tdd/*/mutation-TEST-*.txt` for a suite plus selector in the
inventory. One matches: SPEC-0203 TEST-1312
(`test-aai-feedback-upsert.sh`, `test_1312_surfaces_state_the_contract`,
target `.aai/SKILL_FEEDBACK_UPSERT.prompt.md`). Its first FAIL line comes from
the function's static prompt assertion, not from the nested run, so it should
still redden. Implementation proves that with
`node .aai/scripts/mutation-run.mjs --replay --spec <SPEC-0203 path>` and
re-points nothing unless the replay says otherwise. These records are
gitignored and local to the main checkout (`mutation-gate` does not run in
CI); a record elsewhere is out of reach and is named as a residual risk.

### D9. Suite weights and shard balance

`tests/skills/suite-weights.tsv` is re-seeded from a full-mode CI run of THIS
branch after Batch 4 is green (`gh workflow run skill-suite.yml --ref <branch>`
if the PR selection is not already FULL_RUN), parsed from the four legs'
`[ n/NN] <suite> PASS (<s>s)` lines, with the run id, the job ids and the
head SHA in the file header, as the header's own convention asks. If no
full-mode CI run can be had, the local sweep is the fallback source and the
header says so. The existing TEST-1423 balance bound (largest shard at most
1.05 times the ideal, or the heaviest single suite) must stay green with the
new weights.

## Implementation plan

Five TDD batches, worst-first so the largest saving lands first. Each batch
writes its tests, observes RED, implements, observes GREEN, records mutations,
and runs the touched suites plus `aai-suite-select` and `aai-hygiene-pack`.

- **Batch 1 — selector (Spec-AC-01..04).** `select-suites.mjs` parse,
  validation, `expandCompanions`, empty-diff branches; `suite-map.yaml`
  CONTRACT paragraph; `tests/skills/lib/companion-assert.sh`. Fixture maps
  only, no real-map edges yet.
- **Batch 2 — the three worst (Spec-AC-05..07).** learned-append,
  delta-stage1/2/3, repo-tripwire TEST-437. Their real-map edges land in the
  same commit as their `assert_companions` calls, so each call is observed RED
  first.
- **Batch 3 — the next heavy group (Spec-AC-08, Spec-AC-09).** sync-seed,
  doctor, ceremony-levels; then the layer-profiles group: feedback-upsert,
  friction-wiring, friction, ledger-merge, merge-policy, release.
- **Batch 4 — the rest (Spec-AC-10).** advisory-skills, constitution,
  debug-gate, deslop, doc-number-reservation, git-ref-guard,
  hitl-propagation, hooks-overlay, secrets-preflight, spec-lint, state
  (test_008 only), tdd-evidence.
- **Batch 5 — ratchet, weights, disclosure (Spec-AC-11..13).** Edge-set pin,
  lint plus allowlist, weights re-seed, the measured sweep, the
  `spec-amend` records.

Rollback is per suite: restoring one nested call is local, and the lint names
it.

## Seams this change crosses

- SEAM-1. `select-suites.mjs` output into the workflow's suite extraction
  (`skill-suite.yml`, the `grep -E '^(SELECTED` ... `awk '{print $2}'` line).
  Crossed by TEST-004, which reads that exact line from the real workflow
  file and runs it on a companion selection.
- SEAM-2. `ci-select.mjs` carry-forward passes delta-mode selector lines
  through. Crossed by TEST-004's delta arm (real `--delta-base` on a scratch
  git fixture); `ci-select.mjs` itself is unchanged.
- SEAM-3. `lane-gate.mjs` reads only `FULL_RUN`. A malformed companion now
  makes the lane heavy (fail-open), which TEST-003 pins on the selector side.
- SEAM-4. Other block readers of `suite-map.yaml` (the row-count grep in
  `aai-hygiene-pack`, awk block readers in `aai-update`, `aai-roadmap`,
  `aai-downstream-autopilot`, `aai-doc-numbering`). Crossed by the one full
  sweep before close, which must stay green.
- SEAM-5. Each outer suite and the real map: crossed by every per-suite row
  (TEST-006 to TEST-031), which run the outer suite's own file path through
  the real selector.
- SEAM-6. Full-mode coverage: every companion still runs as its own suite.
  Crossed by the full sweep and the full-mode CI run (Spec-AC-12).
- SEAM-7. `merge-policy.mjs` GUARD_PATHS lists `select-suites.mjs` and
  `suite-map.yaml`, so this PR takes the heavy lane. Expected; no change.

## Acceptance Criteria Mapping
- Maps to: intake Target State bullet 1 (companion field plus selection).
  Spec-AC-01 to Spec-AC-04, verified by TEST-001 to TEST-005.
- Maps to: intake Target State bullet 2 (no suite runs another whole suite;
  a hygiene check refuses a new one). Spec-AC-05 to Spec-AC-11, verified by
  TEST-006 to TEST-034.
- Maps to: intake Verification bullets (learned-append under 10 s, sweep CPU
  down by about a third, shard balance). Spec-AC-12, TEST-035 plus the
  measured sweep and CI run.
- Maps to: intake Constraints (frozen-spec amendments, mutation records).
  Spec-AC-13, TEST-036, plus D8's replay.

## Constitution deviations

None.

Article 1 (evidence before claims): every removal is backed by a RED-first
`assert_companions` call and a mutation record, and the saving is measured,
not estimated. Article 2 (simplicity): one optional list, one helper, one
lint; no new CLI. Article 4 (degrade and report): a malformed companion fails
open to a full run. Article 5 (additive first): a map without `companions:`
selects byte-identically.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN a changed path selects a suite whose suite-map.yaml row declares companions, select-suites.mjs SHALL also print one SELECTED line per companion with reason=companion:<parent>, SHALL follow companions transitively, SHALL print each suite at most once even through a cycle, and SHALL count companions in DROPPED. | planned | — | — | D1, D2 |
| Spec-AC-02 | WHEN a companion entry names no suites row, names its own row, or breaks the name charset, select-suites.mjs SHALL print FULL_RUN reason=internal-error in whole-PR mode and DELTA_REFUSED reason=internal-error in delta mode, and SHALL exit 0. | planned | — | — | D1 fail-open |
| Spec-AC-03 | WHEN a core suite declares companions, every selection outcome including an empty diff and an empty delta SHALL select them; WHEN no row declares companions, every output SHALL be byte-identical to the pre-change selector; and the workflow's own SUITES extraction line SHALL yield the companion names from both whole-PR and delta output. | planned | — | — | D2, SEAM-1, SEAM-2 |
| Spec-AC-04 | assert_companions in tests/skills/lib/companion-assert.sh SHALL return 0 when the real selector selects (or runs as core) every named companion for the outer suite's own test file, and SHALL return 1 printing MISSING companion <name> for <outer> otherwise. | planned | — | — | D4 |
| Spec-AC-05 | WHEN test-aai-learned-append.sh runs, test_015, test_016 and test_017 SHALL invoke no other suite, SHALL assert their companions through assert_companions, SHALL keep their non-nested assertions, and the whole suite SHALL finish in at most 10 s on the measuring host. | planned | — | — | worst case 1 (445 of 446 s) |
| Spec-AC-06 | WHEN the delta-stage1, delta-stage2 and delta-stage3 suites run, their seam functions SHALL invoke no other suite, SHALL assert their companions through assert_companions, and delta-stage3 TEST-007 SHALL keep its repo-wide strict docs-audit check. | planned | — | — | worst case 2 (199 s) |
| Spec-AC-07 | WHEN test-aai-repo-tripwire.sh runs, test_019 SHALL run last in main without re-running the suite, SHALL create one fixture through a command substitution as a positive control, and SHALL fail when any directory its registry named survives drain_workdirs or when the registry held no entry. | planned | — | — | D5; SPEC-0179 TEST-437 claim kept |
| Spec-AC-08 | WHEN the sync-seed, doctor and ceremony-levels suites run, test_781, test_031, test_010 and test_017 SHALL invoke no other suite (ceremony-levels test_017 also drops its own-function loop) and SHALL assert their companions through assert_companions. | planned | — | — | worst cases 4 to 6 |
| Spec-AC-09 | WHEN the feedback-upsert, friction-wiring, friction, ledger-merge, merge-policy and release suites run, their inventory functions SHALL invoke no other suite and SHALL assert their companions through assert_companions. | planned | — | — | layer-profiles group, 84 s each |
| Spec-AC-10 | WHEN the advisory-skills, constitution, debug-gate, deslop, doc-number-reservation, git-ref-guard, hitl-propagation, hooks-overlay, secrets-preflight, spec-lint, state and tdd-evidence suites run, their inventory functions (state test_008 only) SHALL invoke no other suite and SHALL assert their companions through assert_companions. | planned | — | — | prompt-diet group and the rest |
| Spec-AC-11 | The real suite-map.yaml SHALL declare exactly the 36 companion edges of D3; nested-suite-lint.mjs SHALL report every whole-suite nested run of the four D7 shapes and no selector-form or fixture-suite call; over the live tree with the allowlist it SHALL exit 0 with exactly 3 allowlist rows and none stale; over the base tree it SHALL report all 34 inventory functions. | planned | — | — | D3, D6, D7 |
| Spec-AC-12 | tests/skills/suite-weights.tsv SHALL be re-seeded from a named run of this branch, SHALL give aai-learned-append a weight of at most 15 and aai-delta-stage3 at most 30, the TEST-1423 balance bound SHALL hold, and a full local sweep on the measuring host SHALL sum to at most 3,065 s (0.70 of the 4,379 s baseline) with the slowest full-mode CI leg at most 1.25 times the mean leg. | planned | — | — | D9 |
| Spec-AC-13 | Every frozen spec whose Test Plan row is backed by a rewritten function SHALL carry a spec_amendment record of class measurement with ref nested-suite-reruns-duplicate-sweep-time, and no allowlisted row SHALL carry one. | planned | — | — | D8 |

Status values: planned | implementing | done | deferred | blocked | rejected

## Test Plan

Fixtures live in `mktemp -d` scratch directories. RED observations go under
`docs/ai/tdd/` as `nested-suite-reruns-duplicate-sweep-time-red-<TEST-ID>.log`,
mutation records under
`docs/ai/tdd/spec-nested-suite-reruns-duplicate-sweep-time/mutation-<TEST-ID>.txt`.
The Mutation cells target shapes this spec MANDATES (D1 to D7) or a declared
`suite-map.yaml` edge. A companion-deletion mutation always deletes an edge
that no other declared edge implies, so the outer suite's own assertion must
redden. If Implementation renames a mandated shape, it restamps the mutation
mechanically and discloses the restamp in the TDD record. Every row runs as
`bash tests/skills/<file> <selector>`, using the D4 selector idiom where a
suite lacks one.

| Test ID  | Spec-AC    | Type        | File path (expected) | Description | Mutation | Status |
|----------|------------|-------------|----------------------|-------------|----------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-suite-select.sh | test_1750: a fixture map where aai-x declares aai-y; a diff selecting aai-x prints SELECTED aai-x reason=<path> then SELECTED aai-y reason=companion:aai-x, and DROPPED equals rows minus core minus 2 | sed:s/'companion:' \+ parent/'companion-of:' + parent/ | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-suite-select.sh | test_1751: aai-x to aai-y to aai-z selects all three in that order; a cycle aai-x to aai-y to aai-x terminates with each suite printed once; a companion that is core prints no SELECTED line | sed:s/queue\.push\(comp\)/void comp/ | green |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-suite-select.sh | test_1752: a companion with no row, a self-companion and a bad-charset companion each give FULL_RUN reason=internal-error (whole-PR) and DELTA_REFUSED reason=internal-error (delta), always exit 0 | sed:s/if \(!suites\[comp\]\)/if (false)/ | green |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-suite-select.sh | test_1753: core aai-c declaring aai-y selects aai-y on an empty diff and on an empty delta (scratch git fixture); a map without companions gives byte-identical output to a frozen golden for five diffs; the SUITES extraction line read from the real skill-suite.yml yields aai-y from whole-PR and delta output | sed:s/printSelection\(ctx, new Map\(\)\)/void 0/ | green |
| TEST-005 | Spec-AC-04 | unit        | tests/skills/test-aai-suite-select.sh | test_1754: on a fixture repo root, assert_companions returns 0 for a declared and for a core companion, returns 1 and prints MISSING companion aai-y for aai-x when the edge is absent | sed:s/return 1/return 0/ | green |
| TEST-006 | Spec-AC-05 | integration | tests/skills/test-aai-learned-append.sh | test_017_companion_suites_green: no nested run; assert_companions aai-learned-append aai-friction-wiring aai-hygiene-pack passes against the real map; test_015 and test_016 likewise for layer-profiles and prompt-diet; suite total at most 10 s | sed:s/(  aai-learned-append:\n    companions:\n)      - aai-friction-wiring\n/$1/ | green |
| TEST-007 | Spec-AC-06 | integration | tests/skills/test-aai-delta-stage3.sh | test_007_seam_survival: no nested run; assert_companions aai-delta-stage3 for delta-stage1, delta-stage2, spec-lint, docs-audit passes; the strict docs-audit check stays | sed:s/(  aai-delta-stage3:\n    companions:\n      - aai-delta-stage1\n)      - aai-delta-stage2\n/$1/ | green |
| TEST-008 | Spec-AC-06 | integration | tests/skills/test-aai-delta-stage2.sh | test_006_seam_survival: no nested run; assert_companions aai-delta-stage2 for delta-stage1 and spec-lint passes | sed:s/(  aai-delta-stage2:\n    companions:\n)      - aai-delta-stage1\n/$1/ | green |
| TEST-009 | Spec-AC-06 | integration | tests/skills/test-aai-delta-stage1.sh | test_007_docs_canon_suite: no nested run; assert_companions aai-delta-stage1 aai-docs-canon passes | sed:s/(  aai-delta-stage1:\n    companions:\n)      - aai-docs-canon\n/$1/ | green |
| TEST-010 | Spec-AC-07 | integration | tests/skills/test-aai-repo-tripwire.sh | test_019: runs last in main and as a single selected function; positive control of at least one registry entry including one made through a command substitution; no registry-named directory survives drain_workdirs; AAI_TRIPWIRE_NESTED_437 no longer appears in the file | sed:s/  register_workdir "\$d"/  true/ | green |
| TEST-011 | Spec-AC-08 | integration | tests/skills/test-aai-sync-seed.sh | test_781_regression_suites_exit_zero: no nested run; assert_companions aai-sync-seed for bootstrap, hooks-overlay, layer-drift, layer-profiles passes | sed:s/(  aai-sync-seed:\n    companions:\n)      - aai-bootstrap\n/$1/ | green |
| TEST-012 | Spec-AC-08 | integration | tests/skills/test-aai-doctor.sh | test_031_hygiene_set: no nested run; registration, suite-map and PROFILES checks kept; assert_companions aai-doctor aai-layer-profiles aai-suite-select passes | sed:s/(  aai-doctor:\n    companions:\n)      - aai-layer-profiles\n/$1/ | green |
| TEST-013 | Spec-AC-08 | integration | tests/skills/test-aai-ceremony-levels.sh | test_010_seam_survival and test_017_seam_survival_spec0041: no nested run and no own-function loop; strict audit kept; assert_companions aai-ceremony-levels aai-orchestration-dispatch aai-prompt-diet passes | sed:s/(  aai-ceremony-levels:\n    companions:\n)      - aai-orchestration-dispatch\n/$1/ | green |
| TEST-014 | Spec-AC-09 | integration | tests/skills/test-aai-feedback-upsert.sh | test_009_profiles and test_1312: no nested run; assert_companions for layer-profiles and prompt-diet passes; the TEST-1312 static prompt assertion kept | sed:s/(  aai-feedback-upsert:\n    companions:\n)      - aai-layer-profiles\n/$1/ | green |
| TEST-015 | Spec-AC-09 | integration | tests/skills/test-aai-friction-wiring.sh | test_006_companion_suites: no nested run; assert_companions aai-friction-wiring aai-layer-profiles aai-prompt-diet passes | sed:s/(  aai-friction-wiring:\n    companions:\n)      - aai-layer-profiles\n/$1/ | green |
| TEST-016 | Spec-AC-09 | integration | tests/skills/test-aai-friction.sh | test_014_profiles_classified: no nested run; PROFILES checks kept; assert_companions aai-friction aai-layer-profiles passes | sed:s/(  aai-friction:\n    companions:\n)      - aai-layer-profiles\n/$1/ | green |
| TEST-017 | Spec-AC-09 | integration | tests/skills/test-aai-ledger-merge.sh | test_667_new_script_is_classified: no nested run; classification check kept; assert_companions aai-ledger-merge aai-layer-profiles passes | sed:s/(  aai-ledger-merge:\n    companions:\n)      - aai-layer-profiles\n/$1/ | green |
| TEST-018 | Spec-AC-09 | integration | tests/skills/test-aai-merge-policy.sh | test_1530_companion_wiring: no nested run; its other wiring checks kept; assert_companions aai-merge-policy aai-layer-profiles passes | sed:s/(  aai-merge-policy:\n    companions:\n)      - aai-layer-profiles\n/$1/ | green |
| TEST-019 | Spec-AC-09 | integration | tests/skills/test-aai-release.sh | test_020_seam2_layer_profiles: no nested run; classification check kept; assert_companions aai-release aai-layer-profiles passes | sed:s/(  aai-release:\n    companions:\n)      - aai-layer-profiles\n/$1/ | green |
| TEST-020 | Spec-AC-10 | integration | tests/skills/test-aai-advisory-skills.sh | test_013_prompt_diet_floor: no nested run; assert_companions aai-advisory-skills aai-prompt-diet passes | sed:s/(  aai-advisory-skills:\n    companions:\n)      - aai-prompt-diet\n/$1/ | pending |
| TEST-021 | Spec-AC-10 | integration | tests/skills/test-aai-constitution.sh | test_009_prompt_diet_floor: no nested run; assert_companions aai-constitution aai-prompt-diet passes | sed:s/(  aai-constitution:\n    companions:\n)      - aai-prompt-diet\n/$1/ | pending |
| TEST-022 | Spec-AC-10 | integration | tests/skills/test-aai-debug-gate.sh | test_007_prompt_diet_suite: no nested run; assert_companions aai-debug-gate aai-prompt-diet passes | sed:s/(  aai-debug-gate:\n    companions:\n)      - aai-prompt-diet\n/$1/ | pending |
| TEST-023 | Spec-AC-10 | integration | tests/skills/test-aai-deslop.sh | test_011 and test_012: no nested run; assert_companions aai-deslop aai-advisory-skills aai-prompt-diet passes | sed:s/(  aai-deslop:\n    companions:\n)      - aai-advisory-skills\n/$1/ | pending |
| TEST-024 | Spec-AC-10 | integration | tests/skills/test-aai-doc-number-reservation.sh | test_011_backcompat_suite and test_107: no nested run; assert_companions aai-doc-number-reservation aai-doc-numbering passes | sed:s/(  aai-doc-number-reservation:\n    companions:\n)      - aai-doc-numbering\n/$1/ | pending |
| TEST-025 | Spec-AC-10 | integration | tests/skills/test-aai-git-ref-guard.sh | test_312_contract_and_diet: no nested run; the SUBAGENT_CONTRACT anchor checks kept; assert_companions aai-git-ref-guard aai-prompt-diet passes | sed:s/(  aai-git-ref-guard:\n    companions:\n)      - aai-prompt-diet\n/$1/ | pending |
| TEST-026 | Spec-AC-10 | integration | tests/skills/test-aai-hitl-propagation.sh | test_015_existing_suites_green: no nested run; assert_companions aai-hitl-propagation aai-orchestration-dispatch aai-state passes | sed:s/(  aai-hitl-propagation:\n    companions:\n)      - aai-orchestration-dispatch\n/$1/ | pending |
| TEST-027 | Spec-AC-10 | integration | tests/skills/test-aai-hooks-overlay.sh | test_014_prompt_diet_floor: no nested run; assert_companions aai-hooks-overlay aai-prompt-diet passes | sed:s/(  aai-hooks-overlay:\n    companions:\n)      - aai-prompt-diet\n/$1/ | pending |
| TEST-028 | Spec-AC-10 | integration | tests/skills/test-aai-secrets-preflight.sh | test_006_additive_budget_regression: no nested run; strict audit, line budget and heading checks kept; assert_companions aai-secrets-preflight aai-intake passes | sed:s/(  aai-secrets-preflight:\n    companions:\n)      - aai-intake\n/$1/ | pending |
| TEST-029 | Spec-AC-10 | integration | tests/skills/test-aai-spec-lint.sh | test_011_seam_survival: no nested run; assert_companions aai-spec-lint aai-prompt-diet passes (spec-lint is core, so this also proves D2's core-companion rule on the real map) | sed:s/(  aai-spec-lint:\n    companions:\n)      - aai-prompt-diet\n/$1/ | pending |
| TEST-030 | Spec-AC-10 | integration | tests/skills/test-aai-state.sh | test_008_lib_extraction_regression: no nested run; assert_companions aai-state aai-check-state passes through the CORE line; test_071 unchanged | sed:s/  - aai-check-state\n// | pending |
| TEST-031 | Spec-AC-10 | integration | tests/skills/test-aai-tdd-evidence.sh | test_005_additive_regression: no nested run; state.mjs zero-diff and strict audit kept; assert_companions aai-tdd-evidence aai-tdd passes | sed:s/(  aai-tdd-evidence:\n    companions:\n)      - aai-tdd\n/$1/ | pending |
| TEST-032 | Spec-AC-11 | integration | tests/skills/test-aai-suite-select.sh | test_1755: the real map declares exactly the 36 D3 edges (pinned list, item count 36, no edge to a core suite), and feeding each row's own test file selects its whole closure | sed:s/(  aai-learned-append:\n    companions:\n      - aai-friction-wiring\n)      - aai-layer-profiles\n/$1/ | pending |
| TEST-033 | Spec-AC-11 | unit        | tests/skills/test-aai-hygiene-pack.sh | test_14x_nested_suite_lint_shapes: a fixture tree with one planted call per D7 shape (literal, variable, loop variable, wrapper, self) is reported with its function name; a selector call, a comment, a heredoc body and a non-existent fixture suite name are not; TOTAL equals the planted count | sed:s/function resolveVarSuite\(name, vars\) \{/function resolveVarSuite(name, vars) { return null;/ | pending |
| TEST-034 | Spec-AC-11 | integration | tests/skills/test-aai-hygiene-pack.sh | test_14y_nested_suite_lint_live: over the live tree with the allowlist the lint exits 0 with exactly 3 allowlist rows and no STALE line; over the base tree (git archive of the merge base) it reports all 34 inventory functions (pinned list) | sed:s/test_071_rguard_predicate_which_file/test_071_renamed/ | pending |
| TEST-035 | Spec-AC-12 | unit        | tests/skills/test-aai-suite-select.sh | test_1756: the weights header names a run id or the local-sweep fallback and a head SHA; aai-learned-append weight at most 15 and aai-delta-stage3 at most 30; TEST-1423 stays green | sed:s/(aai-learned-append\s+)[0-9]+/$1999/ | pending |
| TEST-036 | Spec-AC-13 | integration | tests/skills/test-aai-hygiene-pack.sh | test_14z_nested_suite_disclosures: spec-amend list --status measurement --json carries at least one item with ref nested-suite-reruns-duplicate-sweep-time for every spec in the final pinned list, and none for SPEC-0137 or SPEC-0180 | sed:s/"ref_id":"nested-suite-reruns-duplicate-sweep-time"/"ref_id":"nested-x"/g | pending |

Test status values: pending → red → green

Counts: 36 rows. Unit 6 (TEST-001, 002, 003, 005, 033, 035), integration 30. Seams crossed: SEAM-1
and SEAM-2 by TEST-004; SEAM-3 by TEST-003; SEAM-5 by TEST-006 to TEST-031
and TEST-032; SEAM-4 and SEAM-6 by the full sweep and the CI run.

## Verification

Commands, all run from the worktree root, suites under `env -u AAI_ROLE`:
- Per batch: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-select.sh`,
  `... test-aai-hygiene-pack.sh`, and every outer suite the batch touched.
- Per row: `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id <id> --suite <file> --selector <fn> --target <path> --sed '<expr>'`,
  then `node .aai/scripts/mutation-gate.mjs --spec <this spec>`.
- `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0203-spec-friction-issues-arrive-without-a-description.md` (D8, from the main checkout where the record lives).
- `node tests/skills/lib/nested-suite-lint.mjs --allowlist tests/skills/lib/nested-suite-allowlist.tsv tests/skills` (exit 0, TOTAL 3 allowlisted).
- Recall cross-check (independent of the lint): repeat Planning's BASH_ENV trace
  (Method step 1) over the full sweep on the final tree and require zero
  WHOLE nested runs outside the three allowlist rows.
- One full local sweep before close, same host and width as the baseline:
  `AAI_TEST_TIMEOUT=3000 env -u AAI_ROLE bash tests/skills/test-framework.sh`;
  sum the `[ n/106] <suite> ... (<s>s)` durations; at most 3,065 s.
- CI: the branch's full-mode skill-suite run; `gh run view <run> --json jobs`
  for leg durations (slowest at most 1.25 times the mean) and the four logs
  for the weight re-seed. Wait about 40 s after a push before watching.
- `node .aai/scripts/spec-amend.mjs list --status measurement --json`
- `node .aai/scripts/spec-lint.mjs --path <this spec>`; `node .aai/scripts/docs-audit.mjs --strict`.

PASS criteria:
- All TEST-xxx green with mutation records, all Spec-AC terminal.
- Local sweep sum at most 3,065 s and `aai-learned-append` at most 10 s in it.
- The trace shows no WHOLE nested run outside the allowlist.
- CI full-mode legs within the 1.25 bound; TEST-1423 green on the new weights.
- `docs-audit --strict` CLEAN; `spec-amend list --strict` exit 0.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: `nested-suite-reruns-duplicate-sweep-time`
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available (for CI: run id, job ids, headSha)

### Evidence by strategy

The recorded strategy is `tdd`, so the demanded evidence is the `tdd / hybrid`
row: a stored RED artifact per AC-gating test under `docs/ai/tdd/`, a verified
Mutation record per Test Plan row, the sweep log with its computed sum, the CI
run artifacts, and the verification matrix above.

| Strategy     | Evidence this spec may demand                                   |
|--------------|-----------------------------------------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop         | per-TEST-xxx green runs; RED-proof observed, storage optional    |
| direct       | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested     | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |

## Registry items closed by this scope

Source: `node .aai/scripts/follow-ups.mjs list`, read on 2026-10-09 and
scanned for nested, companion, suite-map, select, weight, shard, selector,
layer-profiles and prompt-diet subjects.

This scope closes none of the registry items below.

NOT CLOSED, with reason:
- `fu-lib-graph-narrowing-after-sharding` (P2). Same file
  (`select-suites.mjs`), different subject: the shared-lib FULL_RUN rule. Not
  touched.
- `fu-prompt-diet-fixture-real-root-race` (P2). Removing twelve nested
  `aai-prompt-diet` runs removes most of the bare runs that exposed the race,
  but the suite still writes its E2E draft into the real root when run bare.
  Exposure shrinks; the defect stays.
- `fu-mutation-selector-vs-bare-dispatch` (P2). D4 adds the positional
  selector idiom to touched suites that lack one, which sidesteps it for this
  spec's rows; `mutation-run.mjs` itself is unchanged.
- `fu-docs-audit-suite-has-no-selector` (P2). `aai-docs-audit` becomes a
  companion only through core; no row here mutates through it.

## Residual risks

- RR-1. The static lint can be evaded by a shape it does not model (`eval`, a
  computed function name, a suite path assembled across lines). Mitigation:
  its recall is checked against the base tree, and Validation repeats the
  dynamic trace, which sees every bash process whatever its syntax.
- RR-2. A developer running only an outer suite locally no longer runs its
  companions. `assert_companions` prints the companion names on every run;
  the framework, CI full mode and CI selected mode all still run them.
- RR-3. Selector-form cross-suite runs stay (hygiene-pack, roadmap,
  orchestration-dispatch). The trace showed none of them re-running a whole
  suite, but a suite that silently ignores an unknown selector would run in
  full. Not ratcheted here; a follow-up is suggested
  (`suggested: fu-selector-runs-unratcheted`).
- RR-4. The allowlist keeps about 69 s of nested work (D6).
- RR-5. Mutation records live only in the main checkout's gitignored
  `docs/ai/tdd/`. Planning searched that one tree; a record on another host or
  worktree that names an inventory function is out of reach.
- RR-6. The baseline sweep had one local failure (`aai-win-fallback`,
  python-path fixture) and one skip (`aai-state`, exit 42). Both predate this
  scope. The 0.70 bound compares like with like on the same host, and
  Validation must name either if it recurs.
- RR-7. The frozen-row column of the inventory is preliminary (D8);
  Spec-AC-13 is where it becomes exact.
