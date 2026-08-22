---
id: spec-a-half-seeded-checkout-says-it-is-isolated
type: spec
number: 145
status: done
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0157-a-half-seeded-checkout-says-it-is-isolated.md
  rfc: null
  pr:
    - 274
  commits:
    - 0645434f207509aa20e4d3c848ff145ffdc9dd24
---

# Spec — a half-seeded disposable checkout still reports isolated

SPEC-FROZEN: true

Ceremony justification: two surfaces (`tests/skills/test-framework.sh` and
`.aai/scripts/aai-run-tests.sh`), no protected path from `protected_paths_l3`, and
the change is additive REPORTING only — three counters, one summary line, three
JSON fields, one wrapper stderr line and four NOTE lines. No exit code, no gate,
no control flow that decides whether a suite runs; the `|| true` that keeps a
failed copy from aborting a run is preserved in effect at every step. The
regression net is the suite that already owns both funnels
(`tests/skills/test-aai-suite-isolation.sh`), plus one full framework run.

## Links
- Requirement: docs/issues/CHANGE-0157-a-half-seeded-checkout-says-it-is-isolated.md
- The sibling axis this copies the shape of: SPEC-0144
  (`spec-a-run-must-say-whether-isolation-armed`).
- The mechanism being reported on: SPEC-0138
  (`spec-suites-run-in-a-disposable-worktree`).
- The guard whose removal this is the second input to, and which it does NOT
  remove: SPEC-0137 (`spec-suites-must-not-touch-the-shipping-repo`).
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: direct
- Rationale: the defect is a MISSING statement, not a wrong one. There is no
  behavior to drive out with a red test — only output, a counter and ledger
  fields that do not exist yet. The intake's evidence (line numbers verified on
  merged main) already characterises all three silent steps. Each new assertion
  still carries a bite proof by mutation with an unmutated green control, and
  each of the three steps is forced to fail ONE AT A TIME by a REAL,
  non-mutating lever (below), so the arms exercise the real code.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: two files on a dedicated branch; no parallel scope competes
  for either funnel. (Mutation proofs are taken in a throwaway `git worktree
  add --detach` clone that is removed with a targeted `git worktree remove`; that
  is a measurement harness, not the implementation's working tree.)
- User decision: inline
- Base ref: main (4988771)
- Worktree branch/path: feat/seeding-completeness-is-reported (inline)
- Inline review scope: `tests/skills/test-framework.sh`,
  `.aai/scripts/aai-run-tests.sh`,
  `tests/skills/test-aai-suite-isolation.sh`,
  `docs/specs/SPEC-0145-spec-a-half-seeded-checkout-says-it-is-isolated.md`

## The second axis, named once

SPEC-0144's two words answer *did this suite get its own disposable checkout*.
They cannot answer *was that checkout completely built*, and AC-002 forbids
folding the second question into the first. So this scope adds a SECOND AXIS with
its own noun and its own three tokens, used VERBATIM in both funnels.

Axis noun: **`Seeding`** (framework) / **`AAI-SEEDING`** (wrapper).

| token | meaning |
|---|---|
| `seeded` | a disposable checkout was made and every seeding step that had work to do completed. |
| `partial` | a disposable checkout was made and at least one seeding step failed. The checkout exists and the unit is still `isolated`; it is missing content. |
| `skipped` | no disposable checkout was made, so there was nothing to seed. Always paired with `degraded` on the isolation axis. |

Why the axes are NOT merged, which AC-002 asks for explicitly:

- `isolated` states a fact that remains TRUE for a half-seeded run: the suite ran
  in a disposable tree and could not reach the shipping repository. Setting it to
  `degraded` would make the word untrue.
- It would also break the reading a CI check is meant to have. `degraded` means
  "this unit's working tree WAS the shipping repository, with only the tripwire
  between them and it". A future `grep degraded` gate would then fire for a run
  where nothing could reach the shipping repository at all — the gate would be
  loudest exactly where the risk it names is zero.
- The two axes fail for different reasons and are fixed by different people. A
  degrade is a fact about the machine (no git, no `HEAD`, an unusable `TMPDIR`).
  A partial seed is a fact about the CONTENT of one checkout (an unreadable file,
  a full destination, a patch that will not apply).
- They are also not correlated: a `partial` seed can accompany `isolated` (the
  common case) or `degraded` (the seeding failure that CAUSED the suite to be
  missing from its own checkout — see "The interaction that decides the
  denominator").

Names considered and rejected:

- `degraded` reused, or `isolated` turned false — AC-002 forbids it, for the two
  reasons above.
- `complete` / `incomplete` as bare tokens — not greppable. Both words occur in
  ordinary framework prose, so a CI check on them matches text that has nothing
  to do with seeding. The axis noun `Seeding: ` is what makes the tokens
  greppable, and these two would still be weak on their own.
- `full` / `partial` — same problem one word over; `full` also collides with the
  intake's own "a full destination" (a disk-full cause, not a status).
- `clean` / `dirty` — already the tripwire's verdict words.
- `attested` / `unattested` — already the tripwire's counter words, and
  `attested` means "ran to completion and touched nothing", a third thing again.
- `armed` / `unarmed` — SPEC-0144 already rejected these for the isolation axis
  as describing INTENT rather than outcome; reusing them here would import the
  same defect and collide with that rejection.
- `hydrated` / `stale` — no precedent anywhere in this repository, and `stale` is
  already the docs-audit classifier's word.
- Two tokens instead of three (`seeded` / `partial` only, silent when no checkout
  exists) — rejected because a line that is absent on one of its states is a line
  a reader learns to expect the absence of, which is the exact defect CHANGE-0156
  was written to remove. `skipped` makes the third state say its own name.

The keys a later grep-based CI check can hold, all stable by this spec:

| surface | key |
|---|---|
| framework per-suite NOTE | the line prefix `Seeding: '<suite>' — ` |
| framework summary | the line prefix `Seeding: ` plus ` fully seeded; `, ` partial; `, ` skipped` |
| wrapper stderr | the token `AAI-SEEDING: ` plus `seeded`, `partial` or `skipped` |
| run ledger | the JSON keys `suites_seeded`, `suites_partly_seeded`, `suites_seed_skipped` |

## What the counters count, and why

They count SUITES, one increment per suite per run, and the code makes the other
reading impossible rather than merely unlikely — the shape CHANGE-0156
established and this scope copies:

- `iso_create` sets ONE per-suite variable, `ISO_LAST_SEED` (`seeded` or
  `partial`). Every failing step assigns `partial`; none of them counts anything.
- `run_test` copies it into a per-suite `seed_status`, defaulting to `skipped`
  when no checkout was made.
- Exactly ONE site — beside the existing isolation increment — reads
  `seed_status` and increments exactly one of three counters.

The invariant the summary line and the ledger are read by, checked rather than
assumed:

    suites_seeded + suites_partly_seeded + suites_seed_skipped == total

REASONS are the one thing recorded away from the increment site, deliberately.
A suite can fail two seeding steps, so its reason is not one string; each failing
step calls `seed_note_reason` at the point of failure, into the same DISTINCT-set
structure `iso_note_reason` uses (a `; `-joined string, because bash 3.2.57 is a
supported host and `local -a x=()` with `${#x[@]}` under `set -u` is a hard error
there). That cannot double-count, because reasons are a SET and the counters are
not touched there. It cannot orphan a reason either: every `return 1` path in
`iso_create` is BEFORE the first seeding step, so a reason can only be recorded on
a run of `iso_create` that goes on to succeed and therefore to be counted.

## The interaction that decides the denominator

The denominator is TOTAL_TESTS, not "isolated suites", and the reason is a real
interaction rather than tidiness.

A brand-new suite file is untracked, so it reaches the disposable checkout
through seeding step 2 and no other way. If step 2 fails for that file, the suite
is missing from its own checkout — which is exactly SPEC-0144's degrade path 3.
That run is `degraded` on the isolation axis and `partial` on the seeding axis,
and the seeding failure is the CAUSE of the degrade. A denominator of "isolated
suites" would drop that suite out of the seeding accounting entirely and hide the
most informative case this scope exists to report.

So `seed_status` is assigned whenever a checkout was CREATED, before the
"is the suite in it" question is asked, and a suite is `skipped` only when
`iso_create` never produced a checkout. The three counters therefore partition
TOTAL_TESTS directly, and the resulting cross-axis reading is exact:

| isolation | seeding | what happened |
|---|---|---|
| `isolated` | `seeded` | the all-clear |
| `isolated` | `partial` | ran in a disposable tree that was missing content |
| `degraded` | `skipped` | no checkout existed (probe off, or `iso_create` failed) |
| `degraded` | `partial` | a checkout existed but the seeding failure removed the suite from it |
| `degraded` | `seeded` | a fully seeded checkout that still did not contain the suite (a gitignored suite file — SPEC-0144 D3) |

## Why an incomplete seed does not fail the run

AC-004 asks for the argument and for a forward answer. Report-only, and the
reasons are NOT the same five as SPEC-0144's:

1. **It is the owner's call, and it is recorded.** The intake says report-only,
   and says in two places that a failed copy must not abort the run. A scope that
   adds a gate the intake refused decided something it was not asked to decide.
2. **The `|| true` is load-bearing and this change keeps it.** A seeding step
   that aborts a run turns a single unreadable file in someone's working tree
   into a total test outage. The defect was never that the failure was tolerated;
   it was that it was not mentioned.
3. **The failure is frequently not about the code under test at all.** An
   unreadable file, a full disk and a patch that will not apply are properties of
   one developer's machine at one moment.
4. **A gate here would have to fire on the common harmless case.** Untracked
   files are seeded wholesale; a machine with one stray unreadable artifact in
   the working tree would red every run of every suite, and the pressure that
   creates is to delete the check, not to fix the file.

Should it become a gate when the tripwire is deleted? **No — and this is the
opposite answer to SPEC-0144's.** The tripwire guards against a suite WRITING to
the shipping repository. A partial seed cannot write anywhere; it can only make a
run test LESS than it claims. Deleting the tripwire does not change that by one
bit, so nothing about this axis becomes more urgent when it goes.

There IS a gate worth having, on a different trigger, and it is filed rather than
smuggled in here: a seed path that is ON `ISOLATION_SEED_PATHS` and PRESENT in
the working tree but did NOT arrive in the checkout is the failure that silently
turns four assertion groups into passing skips (measured in SPEC-0138, held by
TEST-003). That is a coverage claim, not a repository-safety claim, it needs a
per-path assertion this scope does not build, and it belongs to whichever scope
owns the coverage question. Filed as `fu-seed-path-loss-not-a-gate`.

The exit-code contract is untouched in the letter as well as the spirit:
`exit 1 iff FAILED_TESTS > 0` is unchanged, and this scope adds no path that can
reach `FAILED_TESTS`.

## The wrapper is one unit, not many

In `.aai/scripts/aai-run-tests.sh` the unit is the WRAPPED COMMAND, so there are
no counters — one status, printed once, in the same three words. Two constraints
shape the implementation and both are POSIX-shell facts, not preferences:

- Seeding step 2 is `git ls-files … | while read`, and a pipeline's `while` runs
  in a SUBSHELL, so a variable assigned inside it is invisible afterwards. The
  step records its failures by APPENDING TO A FILE under the checkout's own base
  directory, which crosses the boundary; the status is derived after the loop.
  This is the identical defect, and the identical fix, that
  `tests/skills/test-aai-suite-isolation.sh` documents for its own registries.
- The script is `#!/bin/sh` under `set -u`: no `[[ ]]`, no `+=`, no arrays, and
  every new variable is initialised before first read. Verified with `sh -n` and
  `dash -n`, and the exit-code contract (124 watchdog, 125/127 unlaunchable, the
  wrapped command's own) is untouched.

The wrapper prints its seeding line only for an invocation isolation was meant to
cover — the same predicate that gates `AAI-ISOLATION` — so a build and the
framework's own invocation stay silent on both axes.

## Acceptance Criteria Mapping

- Maps to: CHANGE AC-001
  - Spec-AC-01: WHEN any of the three seeding steps fails for a suite's
    disposable checkout, the framework SHALL emit a `Seeding: '<suite>' — ` NOTE
    naming that step, and SHALL NOT abort the run: the suite still executes and
    the run's exit code is unchanged.
  - Verification: `bash tests/skills/test-aai-suite-isolation.sh` TEST-108..111.
    Each step is forced ONE AT A TIME by a REAL lever, never by mutating the
    fixture's copy of the framework: step 1 by a smudge-only content filter that
    makes the checkout differ from the index so `git apply` cannot apply
    (measured: `error: … patch does not apply`, rc 1); steps 2 and 3 by a
    `chmod 000` source file, which `git ls-files`/`test -f` still see and `cp`
    cannot read (measured rc 1). TEST-108 is the unmutated control, on a fixture
    where all three steps HAVE WORK TO DO.

- Maps to: CHANGE AC-002
  - Spec-AC-02: A partly seeded suite SHALL still be counted `isolated`. On a run
    where a seeding step fails but every checkout was made, the isolation summary
    line SHALL read `<N>/<N> suite(s) isolated; 0 degraded` unchanged, and the
    seeding line SHALL carry the whole difference.
  - Verification: TEST-109, TEST-110 and TEST-111 each assert BOTH lines on the
    SAME run: the isolation counts unchanged at `2/2 isolated; 0 degraded` and the
    seeding counts at `0/2 fully seeded; 2 partial; 0 skipped`.

- Maps to: CHANGE AC-003
  - Spec-AC-03: The seeding axis SHALL appear on all three surfaces — the run's
    NOTE lines, the summary block and the run-ledger record — and the summary
    line SHALL print on EVERY run including the all-clear, in the same shape and
    the same words in both cases. The ledger record SHALL carry
    `suites_seeded`, `suites_partly_seeded` and `suites_seed_skipped`, and they
    SHALL equal the three numbers on the summary line of the SAME `run_id`.
  - Verification: TEST-108 (the all-clear prints the line with no NOTE) and
    TEST-112, which reads all three surfaces off the same fixture run —
    fully seeded and partly seeded — and compares the ledger record for that
    run's own `run_id` against its summary line, asserting
    `suites_seeded + suites_partly_seeded + suites_seed_skipped == total`.
    Vacuity guard: the arm FAILS if no ledger line carries that `run_id`.

- Maps to: CHANGE AC-004
  - Spec-AC-04: A partly seeded run SHALL differ visibly from a fully seeded one
    in all three surfaces with an IDENTICAL exit code. This is reporting; it is
    not a gate.
  - Verification: TEST-112 — the same fixture is run fully seeded and partly
    seeded, the three surfaces differ on both runs, and the exit codes match
    pairwise: 0 for a passing suite and 1 for a failing one in both seeding
    states.

- Maps to: CHANGE AC-005
  - Spec-AC-05: `aai-run-tests.sh` SHALL report the same axis in the same three
    words, once per suite-run invocation, on stderr, and SHALL stay silent for an
    invocation isolation does not apply to (a non-suite command, and the
    framework invocation that reports for itself).
  - Verification: TEST-113 — a wrapped suite run prints `AAI-SEEDING: seeded`;
    the same run with an unreadable untracked file prints `AAI-SEEDING: partial`
    naming the step; the same run under `AAI_TEST_ISOLATION=0` prints
    `AAI-SEEDING: skipped` beside `AAI-ISOLATION: degraded`; a non-suite command
    and the genuine framework invocation print neither line; and the wrapped
    command's exit code is its own (0 and 7) in every case.

## Constitution deviations

None. The change is the degrade-with-a-NOTE convention (art. 4) applied to three
steps that currently degrade in silence.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                       | Status       | Evidence | Review-By | Notes                                              |
|------------|-----------------------------------------------------------------------------------------------------|--------------|----------|-----------|-----------------------------------------------------|
| Spec-AC-01 | Each of the three seeding steps reports its own failure by name and still does not abort the run      | done         | f77b62b (arms as shipped; the ccba52c evidence run predates the verdict fix and was re-derived at head, 19/19); TEST-108..111 green in run test-20260822-065708 (19/19, exit 0); validation rebuilt the three levers on its OWN fixtures and forced each step alone — probe I (smudge filter) emitted only the replay NOTE, probe B (chmod 000 untracked) only the untracked NOTE, probe J (chmod 000 seed path) only the seed-path NOTE, each at exit 0 with Passed 2 (100%); independent mutation MU3 silencing step 2 turns TEST-110 and TEST-112 red against a green unmutated control MU0 | —         | forced one at a time by real levers, not mutation    |
| Spec-AC-02 | A partly seeded suite stays isolated; the seeding axis carries the whole difference                   | done         | f77b62b (arms as shipped; the ccba52c evidence run predates the verdict fix and was re-derived at head, 19/19); TEST-109/110/111 green; validation probes B, I and J each printed Isolation 2/2 suite(s) isolated; 0 degraded on the SAME run that printed Seeding 0/2 fully seeded; 2 partial; 0 skipped, on fixtures the validator built; probe C reached the degraded-plus-partial cell (1/2 isolated; 1 degraded beside 0/2 fully seeded; 2 partial) with both invariants holding at once; independent mutation MU4 folding partial into degraded turns TEST-109, TEST-110 and TEST-111 red | —         | both summary lines asserted on the same run          |
| Spec-AC-03 | The axis appears on the NOTEs, the summary line on every run, and the ledger record                   | done         | f77b62b (arms as shipped; the ccba52c evidence run predates the verdict fix and was re-derived at head, 19/19); TEST-108 (all-clear prints the line, no NOTE) and TEST-112 green; full 81-suite run test-20260822-061705 printed Seeding 81/81 fully seeded; 0 partial; 0 skipped with ledger suites_seeded 81, suites_partly_seeded 0, suites_seed_skipped 0 summing to total 81; validation re-derived the invariant on eight fixtures it built (all-clear, each lever alone, two levers on one suite, isolation off, a failing suite, an exit-42 skip) and every one summed to total; independent mutations MU1 (summary line made conditional) and MU2 (three ledger fields dropped) turn TEST-108 plus TEST-112, and TEST-112, red | —         | invariant seeded plus partial plus skipped == total  |
| Spec-AC-04 | A partly seeded run differs visibly in all three surfaces with an unchanged exit code                 | done         | f77b62b (arms as shipped; the ccba52c evidence run predates the verdict fix and was re-derived at head, 19/19); TEST-112 green on both outcomes; validation probe B (partly seeded, all suites passing) exited 0 and probe F (same lever, one suite failing) exited 1, both differing from the fully seeded probe A in the NOTE lines, the summary line and the ledger record; probe H (an exit-42 skip beside a partial seed) exited 0; no new path reaches FAILED_TESTS, read-verified across the whole diff | —         | report-only argued, and not a gate after the tripwire |
| Spec-AC-05 | aai-run-tests.sh reports the same axis in the same three words, silent where isolation does not apply  | done         | f77b62b (arms as shipped; the ccba52c evidence run predates the verdict fix and was re-derived at head, 19/19); TEST-113 green; sh -n, dash -n and bash -n all exit 0; validation drove the real wrapper through thirteen probes — seeded, partial naming the step while still isolated, skipped under AAI_TEST_ISOLATION=0, silent for a non-suite command and for the framework invocation, and the exit-code contract intact at 0, 7, 124 (watchdog), 126 (not executable) and 127 (ENOENT); the step-2 marker files are recreated under a fresh mktemp base per invocation, so a second partial run does not accumulate and a repaired tree returns to seeded; no marker is ever inside the checkout, and no temp dir or worktree registration is left behind | —         | POSIX sh; step 2's subshell crossed by a file        |

## Implementation plan

Components:

- `tests/skills/test-framework.sh`
  - three run-level counters beside the isolation ones: `SEEDING_SEEDED`,
    `SEEDING_PARTIAL`, `SEEDING_SKIPPED`, plus `SEEDING_REASONS` (a `; `-joined
    set of DISTINCT reason strings) and `seed_note_reason`, the containment-tested
    twin of `iso_note_reason`.
  - `iso_create` gains `ISO_LAST_SEED` (published beside `ISO_LAST_WT`, and for
    the same measured reason: the function sets globals rather than echoing,
    because a command substitution would lose them) and `iso_seed_fail <reason>`,
    which sets it to `partial` and notes the reason.
  - each of the three steps gains its own failure branch and its own NOTE: the
    diff capture, the diff replay, the untracked copies (counted, with the first
    failing path named) and the seed-path copies (likewise). No step aborts; the
    `|| true` semantics are preserved by branching instead of ignoring.
  - in `run_test`, one per-suite `seed_status` defaulting to `skipped`, assigned
    from `ISO_LAST_SEED` whenever a checkout was created, and exactly ONE
    increment site reading it, beside the isolation one.
  - in `generate_summary`, a conditional `log_warn` naming the count and the
    distinct reasons (only when partial > 0), then the UNCONDITIONAL accounting
    line, then the invariant CHECK — the exact three-part shape the isolation
    block already uses.
  - the ledger append gains `"suites_seeded"`, `"suites_partly_seeded"` and
    `"suites_seed_skipped"`.

- `.aai/scripts/aai-run-tests.sh` (POSIX `sh`, no bashisms)
  - `AAI_SEED_STATUS` / `AAI_SEED_WHY` initialised beside `AAI_ISO_STATUS`;
    `skipped` on every branch where no checkout was made, `seeded` on the branch
    where one was, downgraded to `partial` by `aai_seed_fail`.
  - the two existing NOTEs (diff not replayed, a quoted untracked path) are
    rewritten under the `AAI-SEEDING: NOTE - ` prefix and now downgrade the
    status; two new NOTEs cover the untracked copies and the seed-path copies.
  - step 2's subshell reports through append-only marker files under
    `$AAI_ISO_BASE`, read after the pipeline.
  - one `AAI-SEEDING:` status line on stderr after the isolation line, under the
    same suite-run guard.

- `tests/skills/test-aai-suite-isolation.sh` — arms `test_108`..`test_113`,
  registered in `main()`. The suite already byte-copies BOTH funnels and
  `tests/skills/suite-map.yaml` already maps it to both, so no map change is
  needed.

Decisions:

- D1 — the arms go in `test-aai-suite-isolation.sh`, numbered from 108 so
  SPEC-0138's TEST-001..006 and SPEC-0144's TEST-101..107 keep their ids.
- D2 — every step is forced by a REAL lever, never by mutating the fixture's
  framework copy (SPEC-0144 D2's rule, and the same reason: a mutated framework
  proves only that a mutated framework reports). The levers were measured before
  being specified, on git 2.50.1 / macOS:
  - step 1: a smudge-only `filter` attribute (no `clean`) makes the worktree
    checkout differ from the index, so the working-tree patch cannot apply —
    `error: f.txt: patch does not apply`, rc 1. This is the git-lfs shape, not a
    contrivance. Two rejected alternatives: a file-to-directory swap in the
    working tree (measured — `git apply` SUCCEEDS, so it proves nothing), and a
    `post-checkout` hook chmodding the new checkout read-only (works, rc 128, but
    it breaks steps 2 and 3 in the same run and so cannot isolate step 1).
  - steps 2 and 3: a `chmod 000` source file. `git ls-files --others` and
    `test -f` both only stat, so the file is still SELECTED for copying, and
    `cp -p` then fails to read it (measured rc 1). Guarded: if the file is still
    readable after the chmod (a run as root), the sub-arm reports NOT COVERED
    instead of failing, the same shape TEST-004(d) uses for a missing `perl`.
- D3 — EACH ARM'S FIXTURE GIVES EVERY STEP GENUINE WORK, and the control asserts
  it. On this repository step 2 currently copies ZERO files, so a mutation that
  "breaks" it proves nothing; the fixtures therefore commit a baseline and THEN
  create (a) an uncommitted edit to a tracked file, (b) an untracked file, and
  (c) a gitignored seed file named through `AAI_TEST_ISOLATION_SEED`. TEST-108
  asserts all three ARRIVED — a fixture suite reads them from inside its own
  checkout and writes what it saw to an evidence directory — so the control is a
  proof of work, not an absence of noise.
- D4 — the denominator is TOTAL_TESTS and the third token exists, for the reason
  argued in "The interaction that decides the denominator". A two-counter version
  over isolated suites was designed first and rejected: it drops the
  `degraded` + `partial` case, which is the one that matters most.
- D5 — no per-suite seeding field is added to `RUN_DIR/metrics.jsonl` and no
  seeding line is added to `RUN_DIR/summary.txt`. Neither is named by an AC, the
  isolation axis has neither (SPEC-0144 D4), and this is a ride with a declared
  boundary.
- D6 — the degraded/partial suite's own `PASS` line is NOT relabelled, exactly as
  SPEC-0144 D5 decided for the isolation axis. Same reason: the per-suite NOTE
  already names the suite immediately above its result line. Rolled into the
  existing `fu-isolation-degrade-not-on-pass-line`, not filed twice.
- D7 — neither companion obligation applies: no bytes are added to
  `.aai/*.prompt.md` or `.aai/AGENTS.md`, and no NEW `.aai/**` file is created.

Edge cases:

- bash 3.2.57: no arrays for the reason set; a plain string with a containment
  test, the `iso_note_reason` shape.
- `set -euo pipefail` is on in the framework: every new failure branch is an
  `if ! cmd` or an `if [[ ]]`, never a bare `rc=$?` after a pipe.
- The wrapper is `#!/bin/sh` under `set -u`: `sh -n` and `dash -n` both clean, and
  step 2's subshell is crossed by a file rather than by a variable.
- A `printf | grep -q` assertion dies by SIGPIPE above 64 KiB under `pipefail`
  (this repo's ratchet at `tests/skills/lib/pipe-grep-q-ratchet.sh` fails the
  hygiene pack on a new occurrence). The new arms use the suite's existing
  `grep -qF <<<"$out"` herestring form, which is not a pipe.
- Every new fixture run states `AAI_TEST_ISOLATION` explicitly, as SPEC-0144's
  arms do; inheriting it is the filed defect `fu-isolation-suite-not-hermetic`.
- A fixture's ledger path must be gitignored in the fixture repo, or the append
  would dirty the fixture. `build_framework_repo` already ignores it.

## Test Plan

| Test ID  | Spec-AC                | Type        | File path (expected)                     | Description                                                                                                                             | Status  |
|----------|------------------------|-------------|------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-108 | Spec-AC-01, Spec-AC-03 | integration | tests/skills/test-aai-suite-isolation.sh | THE CONTROL — a fixture where all three steps HAVE WORK prints `Seeding: 2/2 suite(s) fully seeded; 0 partial; 0 skipped`, no NOTE, exit 0, and all three seeded artifacts are proven to have arrived | pending |
| TEST-109 | Spec-AC-01, Spec-AC-02 | integration | tests/skills/test-aai-suite-isolation.sh | STEP 1 ALONE — a smudge-only filter makes the working-tree patch unappliable; the replay NOTE fires, seeding reads `0/2 fully seeded; 2 partial; 0 skipped`, isolation stays `2/2 isolated; 0 degraded`, exit 0 | pending |
| TEST-110 | Spec-AC-01, Spec-AC-02 | integration | tests/skills/test-aai-suite-isolation.sh | STEP 2 ALONE — an unreadable untracked file; the untracked-copy NOTE names it and the count, seeding is partial, isolation unchanged, exit 0 | pending |
| TEST-111 | Spec-AC-01, Spec-AC-02 | integration | tests/skills/test-aai-suite-isolation.sh | STEP 3 ALONE — an unreadable seed path named through AAI_TEST_ISOLATION_SEED; the seed-path NOTE names it, seeding is partial, isolation unchanged, exit 0 | pending |
| TEST-112 | Spec-AC-03, Spec-AC-04 | integration | tests/skills/test-aai-suite-isolation.sh | ALL THREE SURFACES — fully seeded vs partly seeded differ in the NOTE lines, the summary line and the ledger record for their own run_id, the three ledger fields sum to total, and the exit codes match pairwise (0 passing, 1 failing) | pending |
| TEST-113 | Spec-AC-05             | integration | tests/skills/test-aai-suite-isolation.sh | THE WRAPPER — `AAI-SEEDING: seeded`, `AAI-SEEDING: partial` with an unreadable untracked file, `AAI-SEEDING: skipped` under AAI_TEST_ISOLATION=0, silent for a non-suite command and for the framework invocation, exit 0 and 7 preserved | pending |

## Verification
- `bash tests/skills/test-aai-suite-isolation.sh` — exit 0, TEST-001..006 and
  TEST-101..107 still PASS and TEST-108..113 PASS.
- `node .aai/scripts/check-test-registration.mjs tests/skills` — exit 0.
- `sh -n .aai/scripts/aai-run-tests.sh` and `dash -n .aai/scripts/aai-run-tests.sh`
  — exit 0 each.
- `node .aai/scripts/select-suites.mjs --files-from <changed>` — run whatever it
  returns.
- One full `bash tests/skills/test-framework.sh` run, read for the new summary
  line and for the three new ledger fields on the same `run_id`.
- Bite proof per new assertion: each mutated ONE AT A TIME in a throwaway
  `git worktree add --detach` clone of this repository with the working tree
  replayed into it, with the unmutated run as the green control. The clone is
  removed with a targeted `git worktree remove`, never a repository-wide prune.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
- ref_id: a-half-seeded-checkout-says-it-is-isolated
- Spec-AC-01..05 map to TEST-108..113 as tabled above.
- Commands and exit codes recorded per run.
- Strategy is `direct`: targeted regression tests green (exit codes) plus the
  scoped diff. No stored RED artifact is demanded; every new assertion still
  carries a bite proof with an unmutated control.
