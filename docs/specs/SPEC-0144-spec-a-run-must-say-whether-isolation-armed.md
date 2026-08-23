---
id: spec-a-run-must-say-whether-isolation-armed
type: spec
number: 144
status: done
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0156-a-run-must-say-whether-isolation-armed.md
  rfc: null
  pr:
    - 273
  commits:
    - cf6120946f4c07c27fa7d1db25a9fd49e0dfe4d4
---

# Spec — a run must say whether isolation armed

SPEC-FROZEN: true

Ceremony justification: two surfaces (`tests/skills/test-framework.sh` and
`.aai/scripts/aai-run-tests.sh`), no protected path from `protected_paths_l3`,
and the change is additive REPORTING only — three counters, two output lines and
two JSON fields. No exit code, no gate, no control flow that decides whether a
suite runs. The regression net is the suite that already owns both funnels
(`tests/skills/test-aai-suite-isolation.sh`), plus the full framework.

## Links
- Requirement: docs/issues/CHANGE-0156-a-run-must-say-whether-isolation-armed.md
- Isolation mechanism this reports on: SPEC-0138
  (`spec-suites-run-in-a-disposable-worktree`).
- The guard this unlocks the removal of, but does NOT remove: SPEC-0137
  (`spec-suites-must-not-touch-the-shipping-repo`), the tripwire.
  **CORRECTION (2026-08-23):** that guard's removal is NOT unlocked and is no
  longer planned — the tripwire is permanent. See the superseding
  `hitl_decision` at 2026-08-23T20:05:00Z in `docs/ai/decisions.jsonl`, which
  withdraws the 2026-08-19 one on the measurement that a disposable worktree
  shares the shipping repo's git common dir. This scope's own delivery is
  unaffected: it reports on isolation, it never removed anything.
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: direct
- Rationale: the defect is a MISSING statement, not a wrong one — there is no
  behavior to drive out with a red test, only output and a ledger field that do
  not exist yet. The intake's evidence (line numbers verified on this machine)
  already characterises every degrade path. Each new assertion still carries a
  bite proof by mutation with an unmutated green control, and AC-001's three
  paths are each forced ONE AT A TIME by environment, not by mutation, so the
  arms exercise the real code.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: two files on a dedicated branch; no parallel scope
  competes for either funnel.
- User decision: inline
- Base ref: main (2d1d57c)
- Worktree branch/path: feat/isolation-status-is-reported (inline)
- Inline review scope: `tests/skills/test-framework.sh`,
  `.aai/scripts/aai-run-tests.sh`,
  `tests/skills/test-aai-suite-isolation.sh`,
  `docs/specs/SPEC-0144-spec-a-run-must-say-whether-isolation-armed.md`

## The vocabulary, decided once

Two status tokens, lowercase, one word each, used VERBATIM in every surface and
in both funnels. A unit is a SUITE in the framework and the WRAPPED COMMAND in
the wrapper.

- `isolated` — the unit ran with its own disposable checkout as its working tree.
- `degraded` — the unit ran with the shipping repository as its working tree.

Why these two and not the obvious alternatives:

- `armed` / `unarmed` describes the framework's INTENT at probe time, not what a
  given suite actually got. A run can probe clean and still degrade per suite
  (the two per-suite paths). On such a run "armed" is true and useless — which
  is exactly the reading this scope exists to remove.
- `enabled` / `disabled` reads as a configuration switch, so it stays true when
  the switch is on and the mechanism failed underneath it. Same failure, one
  word over.
- `clean` / `dirty` are already the tripwire's verdict words. Two different
  verdicts sharing one word is how a reader learns to skim both.
- `isolated` / `degraded` are PER-UNIT facts, so a partly degraded run is stated
  exactly rather than rounded to one of two adjectives: `77/81 suite(s)
  isolated; 4 degraded`. `degraded` is also the word the Constitution's
  degrade-with-a-NOTE rule already uses for this class of event.

The keys a later grep-based CI check can hold, all stable by this spec:

| surface | key |
|---|---|
| framework summary | the line prefix `Isolation: ` plus the trailing ` degraded` count |
| wrapper stderr | the token `AAI-ISOLATION: ` plus `isolated` or `degraded` |
| run ledger | the JSON keys `suites_isolated` and `suites_degraded` |

## What the counter counts, and why

It counts SUITES, one increment per suite per run, and the code makes the other
reading impossible rather than merely unlikely: `run_test` sets ONE per-suite
variable (`iso_status`), whichever degrade path fires assigns it, and exactly
ONE site reads it and increments.

The three degrade paths are already mutually exclusive by control flow — the
global-probe path skips the whole per-suite block; the "suite not in the
checkout" path lives inside the success branch of `iso_create` and the "no
checkout" path is that branch's `else` — so suites and degrade EVENTS coincide
1:1 today. The single increment site is what keeps that true if a fourth path is
added inside the block later. A per-event counter would let one suite be counted
twice and would break the invariant the ledger is read by:

    suites_isolated + suites_degraded == total

## The ledger record for a run that never probed

There is none, and this spec deliberately invents no sentinel for a state that
cannot be written. `iso_probe` runs in `main()` before discovery;
`generate_summary` — which owns the ledger append — runs only after the suite
loop; the single exit between them (`No tests to run`, exit 2) returns before
both. Every record ever appended therefore has a completed probe behind it.

What the record carries INSTEAD of a probe-state field is the invariant above,
which a reader can check with no context: `suites_isolated + suites_degraded`
must equal `total`. A record where it does not is a defect by construction, and
TEST-105 asserts it on a clean and on a fully degraded run. A run killed
mid-flight appends no record at all — absence, not a wrong number.

## Why a degraded run does not fail the run

AC-004 asks for the argument, not the assertion. Five reasons, in the order they
would have to be defeated to change the answer:

1. **It is the owner's call, and it is recorded.** The intake says report-only
   in two places. A scope that adds a gate the intake refused is a scope that
   decided something it was not asked to decide.
2. **Isolation degrades on facts about the MACHINE, not about the code under
   test.** All three probe reasons — `AAI_TEST_ISOLATION=0`, `git not found`,
   `PROJECT_ROOT is not a git checkout` — are environment. Failing on them turns
   the test framework into a gate on where it is allowed to run, and the
   environments it would lock out (a container with no git, a source tarball
   with no `.git`) are the ones with the least other coverage.
3. **The exception would immediately be a hole.** `AAI_TEST_ISOLATION=0` is set
   ON PURPOSE by `tests/skills/test-aai-repo-tripwire.sh` for its own children:
   that suite's fixtures MUST reach their fixture repository so the tripwire can
   catch them (stated at `tests/skills/test-aai-suite-isolation.sh:19-22`). A
   gate would need a carve-out for it, and a carve-out inside a gate is the
   thing the gate was supposed to be.
4. **Nothing can yet tell a deliberate degrade from an accidental one.**
   `iso_probe` sees the same `AAI_TEST_ISOLATION=0` whether an operator typed it
   while debugging or a broken CI job exported it. A gate that cannot
   distinguish intent produces exactly one behavior: people export the variable
   to make it stop.
5. **The harm is still caught red today.** The tripwire is armed, so a write
   that actually reaches the shipping repository still fails the run. This scope
   is the PRECONDITION for deleting the tripwire; the gating question is
   correctly part of THAT decision, on that scope's evidence, and coupling them
   here would ship a gate across 83 suites and every CI run whose blast radius
   nobody measured.

Conclusion: report-only is right FOR NOW, and it is right conditionally. The
condition — that the tripwire is still armed — is exactly what the next ride
removes. So the gating question is filed rather than dropped
(`fu-isolation-degrade-not-a-gate`), as an input the tripwire-deletion scope
must answer before it deletes anything.

**CORRECTION (2026-08-23).** "Exactly what the next ride removes" is withdrawn.
No ride removes it: the tripwire is permanent, so the condition this conclusion
rests on holds indefinitely rather than briefly. `fu-isolation-degrade-not-a-gate`
therefore stops being an input to a deletion scope and becomes a standing
question about the isolation report on its own terms — it is neither closed nor
resolved by this correction. Superseding record: the `hitl_decision` at
2026-08-23T20:05:00Z in `docs/ai/decisions.jsonl`, which also names the three
measurable conditions that would reopen the deletion question.

The exit-code contract is untouched in the letter as well as the spirit:
`exit 1 iff FAILED_TESTS > 0` is unchanged, and this scope adds no path that can
reach `FAILED_TESTS`.

## The write this rides on, named

The ledger append the new fields ride on is itself a known hole: it writes to the
TRACKED `docs/ai/tests/test-runs.jsonl` AFTER the last suite's tripwire
snapshot, so the tripwire is structurally blind to it
(`fu-framework-appends-tracked-testruns`, P3, validation argued P2). This scope
does NOT fix it and does not make it worse — the two new fields are two more
integers on a line that was already being written, with no new write, no new
path and no change to when it happens. Stated here so the field is never read as
tripwire-covered.

OBSERVED LIVE during this scope's own full framework run, and recorded rather
than smoothed over. The framework's OWN tripwire reported
`81/81 suite(s) attested clean`, because the append happens after the last
suite's after-snapshot and is therefore outside every window it takes. The
WRAPPER's tripwire, which brackets the whole invocation, saw it:

    AAI-TRIPWIRE FAIL: the wrapped command [bash tests/skills/test-framework.sh]
    AAI-TRIPWIRE   now:  M docs/ai/tests/test-runs.jsonl

So the field AC-003 adds is written by a call one tripwire reports as a
violation and the other cannot see. Three things follow, none of which change
what this scope does:

- The ledger line is REAL and correct regardless. The run wrote it, and its two
  numbers match the summary line of the same `run_id`.
- The write is APPEND-ONLY, verified rather than assumed: `git diff --numstat`
  on the file is `1 0` (one line added, none removed), and the first 17 540
  bytes of the working file are byte-identical to `git show HEAD:` of it. The
  new fields extend the record format forward; they rewrite no history.
- The resulting ` M docs/ai/tests/test-runs.jsonl` in the working tree is the
  RUN's own noise, not this change's content. It is append-only live data and
  carries no part of the diff under review, so it is not staged with this scope.

## Acceptance Criteria Mapping

- Maps to: CHANGE AC-001
  - Spec-AC-01: WHEN a suite runs, the framework SHALL classify it as exactly one
    of `isolated` or `degraded` and increment the matching per-run counter
    exactly once, at EVERY degrade path — the global probe failure and both
    per-suite paths.
  - Verification: `bash tests/skills/test-aai-suite-isolation.sh` TEST-101..104.
    Each of the three degrade paths is forced ONE AT A TIME by environment, not
    by mutation: `AAI_TEST_ISOLATION=0` for the probe path, an unusable `TMPDIR`
    for the no-checkout path, a gitignored-but-present suite file for the
    not-in-the-checkout path. Each arm asserts the path-specific warn text AND
    the resulting counters, so an arm cannot pass on the wrong path. TEST-101 is
    the unmutated control showing `N/N suite(s) isolated; 0 degraded`.

- Maps to: CHANGE AC-002
  - Spec-AC-02: The summary block SHALL print the line
    `Isolation: <I>/<T> suite(s) isolated; <D> degraded` on EVERY run, including
    the all-clear, with the same shape and the same words in both cases.
  - Verification: TEST-101 (all-clear) and TEST-102/103/104 (degraded) each grep
    the summary for the literal prefix `Isolation: ` and then for the exact
    counts. TEST-101 is what makes the line's presence on a clean run a pinned
    fact rather than a habit.

- Maps to: CHANGE AC-003
  - Spec-AC-03: The run-ledger record SHALL carry `suites_isolated` and
    `suites_degraded`, and the two SHALL equal the two numbers on the summary
    line of the SAME `run_id`.
  - Verification: TEST-105 — the fixture run's `run_id` is read off the summary
    output, the matching line is located in the fixture's
    `docs/ai/tests/test-runs.jsonl`, and its two fields are compared to the
    summary line's numbers, on a clean run and on a fully degraded run. The arm
    also asserts `suites_isolated + suites_degraded == total`. Vacuity guard: the
    arm FAILS if no ledger line carries that `run_id`.

- Maps to: CHANGE AC-004
  - Spec-AC-04: A fully degraded run SHALL differ visibly from a fully isolated
    one in all three surfaces — the stdout NOTE lines, the summary line and the
    ledger record — with an IDENTICAL exit code. This is reporting; it is not a
    gate. The argument for that is the `## Why a degraded run does not fail the
    run` section above, and it is conditional on the tripwire still being armed.
  - Verification: TEST-106 — the same fixture is run isolated and fully degraded;
    the three surfaces differ on both runs and the exit codes match pairwise,
    0 for a passing suite and 1 for a failing one in both isolation states.

- Maps to: CHANGE AC-005
  - Spec-AC-05: `aai-run-tests.sh` SHALL report its own suite-run isolation
    status on stderr in the SAME two words, once per invocation, and SHALL stay
    silent for an invocation isolation does not apply to (a non-suite command,
    and the framework invocation that reports for itself).
  - Verification: TEST-107 — a wrapped suite run prints
    `AAI-ISOLATION: isolated`; the same run under `AAI_TEST_ISOLATION=0` prints
    `AAI-ISOLATION: degraded` naming the reason; a non-suite command and the
    genuine framework invocation print neither; and the wrapped command's exit
    code is its own (0 and 7) in every case.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                       | Status       | Evidence | Review-By | Notes                                              |
|------------|-----------------------------------------------------------------------------------------------------|--------------|----------|-----------|-----------------------------------------------------|
| Spec-AC-01 | Every suite is classified isolated or degraded and counted exactly once at all three degrade paths    | done         | 3466f09; TEST-101..104 green; validation forced paths 2 and 3 on a real 81-suite repo clone and both two-condition collisions counted once | —         | three paths forced one at a time by environment      |
| Spec-AC-02 | The summary prints the isolation line on every run including the all-clear                            | done         | 3466f09; TEST-101 green; mutation M4 making the line conditional turns TEST-101, TEST-105 and TEST-106 red | —         | modelled on the existing tripwire accounting line    |
| Spec-AC-03 | The run-ledger record carries the same two numbers as the summary line for the same run_id            | done         | 3466f09; RUN_ID test-20260822-012816 record reads 81 isolated, 0 degraded, total 81, matching its summary line; TEST-105 green | —         | invariant isolated plus degraded equals total        |
| Spec-AC-04 | A fully degraded run differs visibly in all three surfaces with an unchanged exit code                | done         | 3466f09; TEST-106 green; validation ran an all-passing real-framework run that degraded and exited 0, and a pass-fail-skip run that stayed 3/3 isolated at exit 1 | —         | report-only argued, gating question filed            |
| Spec-AC-05 | aai-run-tests.sh reports its own suite-run status in the same two words                               | done         | 3466f09; TEST-107 green; deleting the wrapper degraded line turns TEST-107 red, widening the suite-run predicate turns TEST-005 and TEST-107 red | —         | silent where isolation does not apply                |

## Implementation plan

Components:

- `tests/skills/test-framework.sh`
  - three run-level variables beside the tripwire counters: `ISOLATION_ISOLATED`,
    `ISOLATION_DEGRADED`, `ISOLATION_REASONS` (a `; `-joined set of DISTINCT
    reason strings, so a fully degraded 83-suite run reports one reason, not 83).
  - in `run_test`, one per-suite `iso_status` / `iso_status_why` pair assigned by
    each degrade path, and exactly one increment site reading it, placed BEFORE
    the suite is executed.
  - the probe NOTE and the two per-suite NOTEs reworded to carry the word
    `degraded`.
  - in `generate_summary`, a conditional `log_warn` naming the count and the
    distinct reasons (only when degraded > 0), then the UNCONDITIONAL accounting
    line — the exact two-line shape the tripwire block already uses.
  - the ledger append gains `"suites_isolated"` and `"suites_degraded"`.

- `.aai/scripts/aai-run-tests.sh` (POSIX `sh`, no bashisms)
  - the isolation `if` is re-ordered so `aai_iso_is_suite_run` is evaluated FIRST
    and the two environment preconditions become reported branches inside it. The
    SET of invocations that get isolated is unchanged — the predicates are
    side-effect free and the conjunction is the same — only the reporting
    differs.
  - `AAI_ISO_STATUS` / `AAI_ISO_WHY` are set on every branch; one status line is
    printed to stderr after the block, and only when the invocation was a suite
    run.
  - the existing `no disposable checkout could be made` NOTE is folded into that
    single line rather than printed beside it. The other two NOTEs (working-tree
    diff not replayed, a quoted untracked path not seeded) stay as they are: they
    describe SEEDING COMPLETENESS inside a checkout that WAS made, which is a
    different axis from isolated-vs-degraded, and collapsing them into `degraded`
    would make the word untrue.

- `tests/skills/test-aai-suite-isolation.sh` — arms `test_101`..`test_107`, each
  registered in `main()`. The suite already carries the fixture machinery
  (`build_framework_repo` byte-copies BOTH funnels) and `tests/skills/suite-map.yaml`
  already maps it to both, so no map change is needed.

Decisions:

- D1 — the arms go in `test-aai-suite-isolation.sh`, not a new suite. It already
  owns both funnels in the suite map, already byte-copies both into a throwaway
  git repository, and this scope is a statement ABOUT the mechanism that suite
  tests. Numbered from 101 so the existing TEST-001..006 (SPEC-0138) keep their
  ids in the same file.
- D2 — the three degrade paths are forced by ENVIRONMENT, never by mutating the
  fixture's framework copy. A mutated framework proves a mutated framework
  increments; an unusable `TMPDIR` and a gitignored suite file make the REAL
  code take the real branch. (`mktemp -d "$TMPDIR/..."` is the framework's only
  `TMPDIR` use, so an unusable one reaches `iso_create`'s `|| return 1` and
  nothing else.) The unusable `TMPDIR` is a REGULAR FILE, not an absent
  directory: `mkdtemp` under a file is ENOTDIR and nothing can turn a file into
  a directory behind the arm's back, whereas an absent directory is racy —
  measured here, an unrelated node process sharing the exported `TMPDIR`
  created it mid-arm and the arm then measured a perfectly isolated run.
- D3 — a gitignored-but-present suite file reaches the not-in-the-checkout path
  precisely because the three seeding steps between them cannot see it:
  `discover_tests` globs the FILESYSTEM (`find … -name 'test-aai-*.sh'`), while
  the checkout is HEAD (it is not committed) plus `ls-files --others
  --exclude-standard` (it is ignored) plus the seed list (it is not on it).
- D4 — no per-suite isolation field is added to `RUN_DIR/metrics.jsonl` and no
  isolation line is added to `RUN_DIR/summary.txt`. Neither is named by an AC,
  the tripwire has neither, and the scope is a ride with a declared boundary.
- D5 — the degraded suite's own `PASS` line is NOT relabelled, even though the
  tripwire relabels its equivalent (`fu-tripwire-unarmed-pass-line-unlabelled`).
  Reason: the per-suite NOTE already names the suite immediately above its
  result line for both per-suite paths, and the global-probe path is a run-level
  fact the summary line states exactly. Filed rather than done here:
  `fu-isolation-degrade-not-on-pass-line`.
- D6 — neither companion obligation applies: no bytes are added to
  `.aai/*.prompt.md` or `.aai/AGENTS.md`, and no NEW `.aai/**` file is created
  (`aai-run-tests.sh` already exists and is already classified).

Edge cases:

- bash 3.2.57: no arrays for the reason set (`local -a x=()` with `${#x[@]}`
  under `set -u` is the known trap here) — a plain string with a containment
  test.
- `set -euo pipefail` is on in the framework: every new assignment is
  unconditional or inside an `if` condition; no bare `rc=$?` after a pipe.
- The wrapper is `#!/bin/sh`: no `[[ ]]`, no `+=`, no arrays.
- A fixture's ledger path must be gitignored in the fixture repo, or the append
  would dirty the fixture and read as a different failure. `build_framework_repo`
  already ignores `docs/ai/tests/test-runs.jsonl`.

## Test Plan

| Test ID  | Spec-AC                | Type        | File path (expected)                     | Description                                                                                                                            | Status  |
|----------|------------------------|-------------|------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-101 | Spec-AC-01, Spec-AC-02 | integration | tests/skills/test-aai-suite-isolation.sh | THE CONTROL — an unmutated 2-suite fixture run prints `Isolation: 2/2 suite(s) isolated; 0 degraded`, exits 0, and emits no degrade NOTE | green   |
| TEST-102 | Spec-AC-01, Spec-AC-02 | integration | tests/skills/test-aai-suite-isolation.sh | degrade path 1 alone — `AAI_TEST_ISOLATION=0` gives `0/2 isolated; 2 degraded` with the probe reason named in the summary                | green   |
| TEST-103 | Spec-AC-01, Spec-AC-02 | integration | tests/skills/test-aai-suite-isolation.sh | degrade path 2 alone — an unusable TMPDIR gives `0/2 isolated; 2 degraded` and the no-disposable-checkout NOTE, not the probe reason      | green   |
| TEST-104 | Spec-AC-01, Spec-AC-02 | integration | tests/skills/test-aai-suite-isolation.sh | degrade path 3 alone — a gitignored suite gives a MIXED `2/3 isolated; 1 degraded` naming that suite, proving per-suite granularity       | green   |
| TEST-105 | Spec-AC-03             | integration | tests/skills/test-aai-suite-isolation.sh | the ledger line for the run's own run_id carries both numbers, they match the summary line, and they sum to total, clean and degraded     | green   |
| TEST-106 | Spec-AC-04             | integration | tests/skills/test-aai-suite-isolation.sh | isolated vs fully degraded differ in all three surfaces while exit codes match pairwise, 0 for a passing suite and 1 for a failing one    | green   |
| TEST-107 | Spec-AC-05             | integration | tests/skills/test-aai-suite-isolation.sh | the wrapper says isolated, says degraded under AAI_TEST_ISOLATION=0, stays silent for a non-suite command and for the framework itself    | green   |

## Verification
- `bash tests/skills/test-aai-suite-isolation.sh` — exit 0, TEST-001..006 still
  PASS and TEST-101..107 PASS.
- `node .aai/scripts/check-test-registration.mjs tests/skills` — exit 0.
- `node .aai/scripts/select-suites.mjs --files-from <changed>` — run whatever it
  returns.
- One full `bash tests/skills/test-framework.sh` run, read for the new summary
  line and for the two new ledger fields on the same `run_id`.
- Bite proof per new assertion: each mutated ONE AT A TIME in a scratchpad copy
  of the repository, with the unmutated run as the green control.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
- ref_id: a-run-must-say-whether-isolation-armed
- Spec-AC-01..05 map to TEST-101..107 as tabled above.
- Commands and exit codes recorded per run.
- Strategy is `direct`: targeted regression tests green (exit codes) plus the
  scoped diff. No stored RED artifact is demanded; every new assertion still
  carries a bite proof with an unmutated control.
