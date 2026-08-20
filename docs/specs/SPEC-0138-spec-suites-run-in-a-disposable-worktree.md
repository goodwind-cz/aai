---
id: spec-suites-run-in-a-disposable-worktree
type: spec
number: 138
status: done
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0152-suites-run-in-a-disposable-worktree.md
  rfc: null
  pr:
    - 267
  commits:
    - a7f40dcd2102f14860c5e2d0a0b4f2a8f6523b86
---

# Spec — every suite runs in a disposable worktree

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0152-suites-run-in-a-disposable-worktree.md
- Predecessor (the tripwire this removes the cause of, and does NOT delete):
  docs/specs/SPEC-0137-spec-suites-must-not-touch-the-shipping-repo.md
- Funnel that CI runs (load-bearing): tests/skills/test-framework.sh
- Funnel roles invoke ad hoc: .aai/scripts/aai-run-tests.sh
- Suite that gates this scope (new): tests/skills/test-aai-suite-isolation.sh
- Suite that had to change (one line): tests/skills/test-aai-repo-tripwire.sh
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1. Two funnel files, one new suite, and one
one-line change to an existing suite. No product surface, no schema, no
`protected_paths_l3` path, no new dependency, and no new file under `.aai/`.
The intake fixed the acceptance criteria and the design question was already
settled by measurement, so Planning froze them rather than re-opening it.

## Summary

Four suites write to the shipping repository today and are held open by a
ratchet in `tests/skills/test-framework.sh`. The tripwire that found them can
only report a write after it has landed; roles work around it by skipping the
suites that dirty the tree, so the surface those suites cover goes unverified
exactly when it matters.

This scope removes the CAUSE rather than improving the report: both funnels run
each suite in a throwaway `git worktree` seeded from the working tree.

What that does and does not prevent, stated plainly, because a `git worktree`
SHARES the `.git` of the repository it was cut from:

- The shipping WORKING TREE is protected from the ordinary path, and observably
  so. A suite's writes land in the copy; `git rev-parse HEAD` and
  `git status --porcelain=v1` on the shipping repository come back
  byte-identical, which is what AC-001 asks for and what TEST-001 proves. The
  honest verb is "not by accident, and observably so" rather than "cannot": the
  copy is one `git rev-parse --git-common-dir` away from the shipping tree's
  path, so a suite that goes looking still finds it. What is removed is the
  accident — a suite resolving its own `PROJECT_ROOT` and writing there, which
  is what all four known writers did.
- The shared `.git` ADMINISTRATIVE SURFACE is not protected. From inside the
  disposable checkout a suite can still write the shipping repository's refs,
  `.git/config` and `.git/hooks`. Measured during validation: a tag, a branch,
  a config key and an executable `post-checkout` hook all landed, with `HEAD`
  and the porcelain unmoved and the tripwire silent. This is not a regression —
  it was equally true before this change — and closing it is out of scope and
  filed as `fu-worktree-shares-git-admin-surface` and
  `fu-worktree-hook-disarms-later-suites` (validation round 1, F1 and F2).
  D7 carries the detail.

No suite had to be made hermetic in its own right, because every suite in this
repository resolves
`PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"` — point the script at a copy
and its whole world moves with it.

The tripwire, its ratchet and the ratchet-path hashing are deliberately LEFT IN
PLACE. They are deleted by a separate change, after a CI cycle has shown
isolation holding on Linux. If isolation is complete the tripwire simply never
fires; if it fires, that is information rather than a conflict.

Four things were measured during this ride. Three of them changed the shipped
code, and none of them is visible by reading the naive patch.

1. **A worktree checks out a COMMIT, so the naive patch is wrong.** Uncommitted
   edits and brand-new untracked suite files are invisible to it, and a
   brand-new suite reports as `No such file or directory` and is counted a test
   failure — a TDD RED that can never go red. Three things are replayed into
   the checkout instead: the tracked diff (`git diff HEAD --binary`, staged and
   unstaged, binary-safe), the untracked-but-not-ignored files, and the
   gitignored per-dev files suites READ.

2. **Without the third of those, four assertion groups become PASSING SKIPS.**
   `docs/ai/STATE.yaml` is gitignored, so a worktree has none, and
   `test-aai-check-state` TEST-010 and TEST-002, `test-aai-orchestration-mode`
   TEST-016 and `test-aai-orchestration-dispatch`'s repo-wide `check-state`
   gate all take their documented "no local STATE, skipping" branch. That is a
   greener run that tests less: the exact failure mode the tripwire exists to
   prevent, arriving through the fix for it.

3. **On macOS the disposable checkout must be at a REALPATH, not at the
   `mktemp` spelling.** `$TMPDIR` lives under `/var`, a symlink to
   `/private/var`. Every `.mjs` CLI in this repository guards its entry point
   with `path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)`;
   `path.resolve` keeps the symlinked spelling while `import.meta.url` carries
   the real one, so from an unresolved checkout the guard is FALSE, `main()`
   never runs, and the CLI exits 0 having printed nothing. Measured:
   `tests/skills/test-aai-hitl-propagation.sh` TEST-010, TEST-011 and TEST-012
   got empty stdout at exit 0 from `orchestration-dispatch.mjs` and read as
   three assertion failures. `pwd -P` on the checkout closes it and is a no-op
   wherever `$TMPDIR` is already real. The underlying `isMain` fragility is not
   this scope's to fix and is filed.

4. **One existing suite had to change, and only one.**
   `tests/skills/test-aai-repo-tripwire.sh` runs byte copies of the framework
   over fixture suites whose entire job is to dirty their own fixture
   repository. Under isolation those fixtures dirty a throwaway worktree and
   the tripwire never sees the write it exists to catch — which is the right
   behaviour and the wrong test. MEASURED, twice, rather than reasoned:
   remove the export and 6 of the 12 arms go RED — TEST-001, TEST-002,
   TEST-008, TEST-009, TEST-011 and TEST-012 — against a 12/12 green control.
   The other six stay green, and whether any of those then passes for the wrong
   reason was not measured. One exported `AAI_TEST_ISOLATION=0` turns isolation
   off for that suite's children. Nothing else in `tests/skills/` was touched.

## Design decisions

- **D1 — isolation at both funnels, with the teeth in different places.**
  `tests/skills/test-framework.sh` is what CI runs, so it isolates EVERY suite
  it discovers. `.aai/scripts/aai-run-tests.sh` is what roles invoke ad hoc, and
  it isolates a SUITE RUN only. The asymmetry is a measurement, not a
  preference: the wrapper carries arbitrary commands — builds, generators, npm
  scripts — and isolating those would throw the artifact away with the
  checkout, which is a regression wearing a guard's clothes. A suite run is
  recognised as an argument that names an existing file under this
  repository's `tests/` tree matching `test-*.sh`.

  `tests/skills/test-framework.sh` is excluded from the wrapper's detection for
  the mirror-image reason: it isolates per suite itself, so wrapping it would
  isolate twice, and its run ledger has to land in the real tree (D5). This
  keeps the canonical whole-suite invocation
  `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh`
  behaving exactly as before.

  That exclusion is matched by RESOLVED PATH and against the EXECUTED SCRIPT
  ONLY — the executed script's filename must be exactly `test-framework.sh`,
  the file must exist, and it must resolve to this repository's
  `tests/skills/test-framework.sh`. The executed script is the first argument,
  or the first non-option argument after it when the first names a shell
  interpreter (`sh`, `bash`, `dash`, `ash`, `ksh`, `zsh`); a `-c` invocation
  executes no script file at all and can never claim the opt-out.

  **CORRECTED 2026-08-20** (Codex review, PR #267). Two bypasses of the same
  class were closed on the way here, and only the pair states the rule
  honestly. The exclusion was first written as the suffix glob
  `*test-framework.sh` tried against every argument, so a single word ending in
  those characters, needing no file behind it at all, turned isolation off for
  the whole invocation (validation F4). Making the MATCH exact left the SCAN
  over every argument, so `bash <a-writing-suite> tests/skills/test-framework.sh`
  — the genuine framework path riding along as an ARGUMENT of another suite —
  still disarmed isolation for the whole invocation: the suite ran against the
  shipping checkout, and because this funnel's tripwire is report-only its
  writes stayed and the run still exited 0. Measured before the fix on the
  TEST-005 fixture: ` M tracked.txt` plus `?? untracked-dirt.txt`, exit 0.
  Both are silent bypasses of a guard, so both are fixed here rather than
  filed; TEST-005(e)/(f)/(g) hold the three directions.

  `AAI_TEST_ISOLATION=0` disables it at both funnels. It exists because one
  suite needs it (Summary point 4) and because a downstream project on a
  machine where `git worktree` is unavailable must still be able to run its
  tests. Where isolation cannot arm, both funnels DEGRADE WITH A NOTE and run
  the suite in the shipping repository — under the tripwire, which is still
  armed — rather than refusing.

- **D2 — the copy is the WORKING TREE, not HEAD.** Three replays, in this
  order, all measured at well under a tenth of a second on this repository:
  `git diff HEAD --binary` applied with `git apply`; every path from
  `git ls-files --others --exclude-standard` copied in; and the gitignored
  per-dev seed list copied in. The first two are what make an uncommitted edit
  and a brand-new suite visible; without them a TDD RED cannot go red, which
  would make the whole harness useless for the work it exists to support.

  A replay that fails is NAMED on stderr and the run continues against HEAD; it
  is not silently swallowed, and it is not fatal either.

- **D3 — the seed list is data, not policy.** It defaults to
  `docs/ai/STATE.yaml docs/ai/LOOP_TICKS.jsonl docs/ai/hitl-channel.json` — the
  three gitignored per-dev files suites in this repository read — and is
  overridable through `AAI_TEST_ISOLATION_SEED` so a downstream project with
  different per-dev files does not have to fork either funnel. A listed path
  that does not exist is skipped, so the default list is safe on a machine that
  has never run the loop.

  Seeding is CONTENT ONLY. The copy gets the files; it does not get any
  ownership of them, and nothing the suite does to its copy comes back.

- **D4 — the checkout is destroyed on all four exits, and the repository is
  never swept to do it.** A pass and a failure both reach the removal at the end
  of the per-suite block; a watchdog kill, a hangup and a Ctrl-C do not, so both
  funnels trap `INT`, `TERM` and `HUP`, and the framework also traps `EXIT`.
  Removal is `git worktree remove --force`, then `rm -rf`. On the happy path
  nothing else is needed: `remove --force` clears the directory **and** the
  registration by itself.

  **CORRECTED 2026-08-20** (code review NB-1, escalated by the operator). An
  earlier draft of this bullet argued for a repository-wide `git worktree prune`
  as the backstop. That operation was measured to be destructive: it deregisters
  **any** worktree whose directory is currently unreachable — an unmounted
  volume, a detached disk, a renamed path — and deletes its
  `.git/worktrees/<name>` metadata, after which `git worktree repair` reports
  `error: unable to locate repository`. Running it ~81 times per framework run
  put an operator's own worktrees at risk of unrecoverable loss to fix a
  cosmetic artifact. It is gone from both funnels. The failure path instead
  calls `iso_deregister` / `aai_iso_deregister`, which deletes exactly one admin
  entry: the one whose `gitdir` file holds this checkout's own path. Reproduced
  both ways — with the sweep restored an unreachable operator worktree does not
  survive a run; without it, it survives and is usable once the volume returns,
  while a genuinely stuck checkout is still cleaned. Measured at 81-suite scale
  with a name-colliding operator worktree: the admin-entry set is byte-identical
  before and after. The residual failure mode is now inert rather than
  destructive — a leaked entry the operator's own `prune` reclaims.

  The framework registers the live checkout in a shell ARRAY that the traps
  drain, and `iso_create` therefore sets a global rather than echoing the path:
  a command substitution runs in a subshell, so an array append inside one is
  invisible to the parent and the traps would drain an empty list. Measured —
  with the echoing form a watchdog kill left both the directory and the
  registration behind, and TEST-004(c) is the arm that found it.

  The wrapper uses no `EXIT` trap: dash runs one inside a subshell, and the
  wrapper forks its watchdog as a subshell.

- **D5 — the harness's own ledger stays in the real tree; the suite's copy of
  it does not.** `tests/skills/test-framework.sh` resolves `RESULTS_DIR` from
  its own `SCRIPT_DIR`, and the framework file that runs is always the one in
  the real checkout — only the SUITE is copied. So `$RUN_DIR/<skill>.log`,
  `metrics.jsonl`, `summary.txt`, the tripwire snapshot files and the
  end-of-run append to `docs/ai/tests/test-runs.jsonl` all land exactly where
  they have always landed, and the operator's run ledger is unchanged by this
  scope. Anything the SUITE writes under `tests/skills/results/` inside its own
  copy goes with the copy, which is correct: that is a suite's scratch, not the
  operator's ledger.

  This is also why the wrapper excludes `test-framework.sh` from isolation: had
  it not, the framework's own `SCRIPT_DIR` would have resolved inside the
  throwaway checkout and the whole run ledger would have been discarded.

- **D6 — the disposable checkout lives outside the repository, at a resolved
  path.** Outside, because a worktree inside the checkout would be an untracked
  directory and the tripwire would fire on every suite. At a resolved path
  because of the `isMain` interaction in the Summary, point 3.

- **D7 — what isolation still does not cover, stated rather than implied.**
  What is protected is the shipping WORKING TREE. What is NOT protected is the
  shared `.git`: `git worktree add` gives the copy a `.git` FILE pointing back
  at the shipping repository's common directory, so everything under that
  directory is one path away from the suite.

  Measured during validation round 1, from inside a disposable checkout, all
  four landing in the SHIPPING repository:

  - a ref created by `git tag`;
  - a ref created by `git branch`;
  - a key written into `.git/config`;
  - an executable `.git/hooks/post-checkout`.

  In every one of those, `git rev-parse HEAD` and `git status --porcelain=v1`
  on the shipping tree were unmoved and the tripwire stayed silent, because
  neither instrument looks at the administrative surface. The hook case is a
  persistent-code-execution shape, and it composes: a `post-checkout` hook that
  fails makes `git worktree add` fail, which disarms isolation for every LATER
  suite in the same run. That second-order path is at least named twice at
  runtime (a per-suite `log_warn`, then the tripwire failing the run).

  None of this is a regression — a suite has always been able to do it, and
  before this change it could reach the working tree as well. Closing it needs a
  separate object store and a scrubbed `.git` per suite; it is out of this
  scope, and filed as `fu-worktree-shares-git-admin-surface` and
  `fu-worktree-hook-disarms-later-suites` (validation round 1, F1 and F2).

  A commit made inside the copy is the mild member of the same family: it writes
  objects into the shared object database, unreferenced, until they are
  garbage-collected.

  The HARNESS itself writes to that same shared `.git` — one `git worktree add`
  registration under `.git/worktrees/` per suite, roughly 81 a run, each
  removed again by the matching `git worktree remove` (the repository-wide
  `git worktree prune` that used to follow every one of them is gone: it
  deregistered any operator worktree whose directory was merely unreachable at
  that moment, so removal now falls back to dropping only this checkout's own
  admin entry, and only when `worktree remove` failed).

  A suite that writes to an ABSOLUTE path outside its `PROJECT_ROOT` is not
  isolated by anything here. Nothing in this repository does, and the tripwire
  still catches it if one starts.

- **D8 — the tripwire, the ratchet and the ratchet-path hashing all stay.**
  They are ~1140 lines that this change makes deletable, and deleting them is
  the follow-on change, after CI has shown isolation holding on Linux. Keeping
  them costs one `git status` pair and one small content hash per suite, and
  buys the only independent check that isolation is actually working: with
  isolation on, `TRIPWIRE_ALLOWED` goes to zero and every suite is attested
  clean, which is an observation, not an assumption.

## Implementation strategy
- Strategy: direct
- Rationale: recorded in STATE before this ride began. The behavior is
  "run the same script from a different directory" — there is no algorithm to
  discover and no interface to negotiate. What can go wrong is entirely in the
  wiring (a subshell that swallows an array append, a path spelling that
  defeats a prefix test, a signal that a background shell ignores), and wiring
  is proven by running the real funnels. Direct does not waive the
  failing-first observation: see the discipline paragraph under the Test Plan.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: four files, no `protected_paths_l3` path. Isolation is
  offered only because verifying this scope means running the full framework,
  and a concurrent write into the checkout mid-run reads as a suite's write.
- User decision: undecided
- Base ref: main
- Inline review scope: tests/skills/test-framework.sh,
  .aai/scripts/aai-run-tests.sh, tests/skills/test-aai-suite-isolation.sh,
  tests/skills/test-aai-repo-tripwire.sh, tests/skills/suite-map.yaml,
  docs/specs/SPEC-0138-spec-suites-run-in-a-disposable-worktree.md,
  docs/issues/CHANGE-0152-suites-run-in-a-disposable-worktree.md

Code review required: true (test-harness and vendored-script changes); scope =
the explicit path list above as a diff against main.

## Acceptance Criteria Mapping

- Maps to: CHANGE AC-001
- Spec-AC-01: a suite's writes do not reach the shipping WORKING TREE by
  accident, and it is observable when they do — not `never`, because the copy is
  one `git rev-parse --git-common-dir` away from the shipping tree's path, so
  what is closed is the ordinary path (a suite resolving its own root and
  writing there) rather than a determined one (the shared
  `.git` administrative surface is explicitly outside this claim; see D7). A fixture
  suite that modifies a tracked file AND creates an untracked one, and a second
  that COMMITS, both run to a PASS while `git rev-parse HEAD` and
  `git status --porcelain=v1` on the repository they were launched from stay
  byte-identical. Each fixture records the `PROJECT_ROOT` it actually resolved
  and the state of the file it wrote, so the arm cannot pass by the suites not
  running or not writing. Demonstrated on the four known writers against the
  real checkout as well.
  - Verification: `bash tests/skills/test-aai-suite-isolation.sh` TEST-001,
    plus the four known writers run through the framework against the real
    tree. Evidence: suite stdout and the before/after snapshot pair.

- Maps to: CHANGE AC-002
- Spec-AC-02: the copy reflects the working tree. An uncommitted edit to an
  existing suite, an uncommitted edit to a production file that a suite reads,
  and a brand-new untracked suite file are all visible to the run: the edited
  suite's new behavior is what executes, the new suite is discovered and runs
  to a PASS rather than to `No such file or directory`, and it reads the edited
  production file's NEW content.
  - Verification: `bash tests/skills/test-aai-suite-isolation.sh` TEST-002.
    Evidence: suite stdout.

- Maps to: CHANGE AC-003
- Spec-AC-03: no assertion that runs today becomes a skip. The gitignored
  per-dev files suites read are seeded, proven by a fixture suite carrying the
  same present-or-skip shape the four real assertion groups use, with an
  in-arm NEGATIVE CONTROL: the same run with the seed list pointed at a
  non-existent path must degrade to the skip. Demonstrated on the four real
  groups by comparing the isolated run's output against the same suites in the
  live tree.
  - Verification: `bash tests/skills/test-aai-suite-isolation.sh` TEST-003,
    plus a live-tree comparison of `test-aai-check-state`,
    `test-aai-orchestration-mode` and `test-aai-orchestration-dispatch`.
    Evidence: suite stdout and the two log sets.

- Maps to: CHANGE AC-004
- Spec-AC-04: the checkout is gone after a passing run, a failing run, a
  watchdog kill and an interrupt, and no `git worktree list` entry survives
  either. Both halves are asserted every time: the registration count and the
  directory count under a per-arm `TMPDIR`. The kill arms assert that the
  fixture suite really was cut off mid-run, so they cannot pass by nothing
  being killed. A fifth exit covers the removal git itself cannot perform —
  a suite that deletes its own checkout's `.git` link — because on every other
  path `git worktree remove` clears the registration by itself, so the
  failure-path `iso_deregister` that backs it up is only falsifiable there.
  - Verification: `bash tests/skills/test-aai-suite-isolation.sh` TEST-004.
    Evidence: suite stdout.

- Maps to: CHANGE AC-005
- Spec-AC-05: `.aai/scripts/aai-run-tests.sh` isolates a suite run given by a
  relative path and by an absolute one, never alters the wrapped command's exit
  code (0 stays 0, 7 stays 7), leaks no worktree, and still runs a NON-suite
  command in the real tree so a build's artifact is not discarded with the
  checkout.
  - Verification: `bash tests/skills/test-aai-suite-isolation.sh` TEST-005,
    plus `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-deslop.sh`
    against the real tree. Evidence: suite stdout and the wrapper's exit code.

- Maps to: CHANGE AC-006
- Spec-AC-06: added wall clock is under 2 seconds per suite, MEASURED. The arm
  runs one fixture twice, with isolation off and on, over enough suites that a
  whole-second clock cannot dominate the per-suite figure, and prints both
  totals and the derived per-suite cost in its pass line. The whole-repository
  figure is reported from the full framework run against a baseline run.
  - Verification: `bash tests/skills/test-aai-suite-isolation.sh` TEST-006,
    plus the observed full-run delta. Evidence: suite stdout and both run
    wall clocks.

## Constitution deviations

None. Checked v1 articles 1 to 7.

Article 1 (evidence before claims): every Spec-AC names one executable command
and one read observable, and each new assertion is mutation-proved at
full-suite level with an unmutated control. Article 2 (simplicity): no new
file under `.aai/`, no new dependency, no configuration file — one env var and
one seed list. Article 3 (portability): POSIX sh in the wrapper, bash in the
framework, `git` only. Article 4 (degrade and report): every way isolation can
fail to arm is named on the run's own output and falls back to the previous
behavior under the tripwire, rather than refusing or degrading silently.
Article 5 (additive first): the wrapper's exit codes are untouched, the
exit-42-is-SKIP contract is untouched, the tripwire and its ratchet are
untouched, and the run ledger lands where it always has. Article 6
(single-writer state): no STATE write outside `.aai/scripts/state.mjs`.
Article 7 (operator-only merge): no merge is performed.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | int  | tests/skills/test-aai-suite-isolation.sh | in a throwaway git repository holding a byte copy of the real framework, one fixture suite appends to a tracked file and creates an untracked one and a second COMMITS; the framework exits 0, both read PASS, no tripwire block is printed, and `git rev-parse HEAD` plus `git status --porcelain=v1` on the fixture repository are byte-identical across the run. Each fixture records the PROJECT_ROOT it resolved, the line count of the file it appended to, and the sha it committed, so the arm cannot pass by the suites not running or not writing | green |
| TEST-002 | Spec-AC-02 | int  | tests/skills/test-aai-suite-isolation.sh | after the fixture repository is committed, an EXISTING suite is edited, a production file it reads is edited, and a brand-new untracked suite is added; the run discovers 2 tests, the edited suite's NEW body is what executed, the brand-new suite runs to a PASS, it reads the production file's NEW content, and no `No such file or directory` appears anywhere in the output | green |
| TEST-003 | Spec-AC-03 | int  | tests/skills/test-aai-suite-isolation.sh | a gitignored per-dev file is created in the fixture repository and a fixture suite reads it with the same present-or-skip shape the four real assertion groups use; the isolated run must print the ASSERTED line and never the SKIPPING line. In the same arm, the negative control: with `AAI_TEST_ISOLATION_SEED` pointed at a non-existent path the SAME suite must print the SKIPPING line, so the seeding is proven to be what made the positive half pass | green |
| TEST-004 | Spec-AC-04 | int  | tests/skills/test-aai-suite-isolation.sh | five exits, each asserting BOTH the `git worktree list` registration count and the on-disk directory count under a per-arm TMPDIR: a passing run at exit 0, a failing run at exit 1, a watchdog kill through the real wrapper at `AAI_TEST_TIMEOUT=3` returning 124, a SIGINT delivered to the framework's own process group, and a suite that deletes its own checkout's .git link so `git worktree remove` cannot do the job and only the fallback deregistration of that one admin entry can clear the registration. Both kill arms assert the fixture suite was cut off mid-run, so neither can pass by nothing being killed | green |
| TEST-005 | Spec-AC-05 | int  | tests/skills/test-aai-suite-isolation.sh | in a throwaway repository holding a byte copy of `.aai/scripts/aai-run-tests.sh`, a suite run by RELATIVE path leaves the repository byte-identical at exit 0, the same suite exiting 7 still surfaces 7 and still leaves it identical, the same suite by ABSOLUTE path from a foreign working directory is retargeted into the copy rather than run in place, a NON-suite command still writes its artifact into the real tree, a DECOY argument named my-test-framework.sh no longer buys the framework opt-out so the same suite is still isolated and the repository still byte-identical, the GENUINE tests/skills/test-framework.sh path carried as an argument of another suite no longer buys it either so that suite is isolated and the repository still byte-identical, the genuine tests/skills/test-framework.sh invocation itself is still excluded so its run ledger lands in the real tree, and no worktree registration survives any of them | green |
| TEST-006 | Spec-AC-06 | int  | tests/skills/test-aai-suite-isolation.sh | one fixture of 20 trivial suites run twice, once with `AAI_TEST_ISOLATION=0` and once isolated; the derived per-suite delta must be under 2000ms and the pass line prints the measured figure and both totals, so the number is read off the run rather than asserted | green |

Failing-first discipline (strategy `direct`, so exit codes are the record).
Every arm above asserts an observable that does not exist on the pre-change
tree — the disposable checkout, the seeded per-dev file, the removal on a kill,
the wrapper's retargeting — so each fails naturally before the edit. The
load-bearing evidence is therefore MUTATION at full-suite level with an
unmutated green control, recorded in the Implementation return record: for each
new assertion, one named single-point mutation of the shipped code that turns
exactly the expected arm red while the control run is green. An assertion
verified only by reading is not accepted.

## Verification

- `bash tests/skills/test-aai-suite-isolation.sh` exits 0
- `bash tests/skills/test-aai-repo-tripwire.sh` exits 0 — the tripwire stays
  and must keep passing
- `AAI_TEST_TIMEOUT=1800 bash tests/skills/test-framework.sh`; report the
  observed aggregate and name every failure, plus a baseline run for the
  wall-clock delta
- the four known writers run through the framework against the real checkout,
  with the `git rev-parse HEAD` plus `git status --porcelain=v1` pair
  byte-identical around them
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-deslop.sh`
- `node .aai/scripts/spec-lint.mjs` clean,
  `node .aai/scripts/check-test-registration.mjs` clean,
  `node .aai/scripts/docs-audit.mjs --check --strict --no-event` clean

## Evidence contract

- The new suite's stdout, including TEST-006's measured per-suite figure.
- The framework aggregate, with every failure named, and the baseline delta.
- The before/after snapshot pair around the four known writers.
- For every new assertion: the mutation applied, the arm that went red, and the
  unmutated control run that stayed green.
- The pre-change and post-change `git rev-parse HEAD` and
  `git status --porcelain=v1 -uno` line count for the whole ride.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN a suite writes to a tracked file, creates an untracked one, or commits THEN the shipping repository's HEAD and git status --porcelain=v1 are byte-identical after the run, and the suite still runs to completion | done | TEST-001 green; the four known writers green against the real tree with an identical snapshot pair | — | the tripwire is left armed and reports nothing, which is the independent check that isolation worked rather than that nothing was attempted; each fixture records the PROJECT_ROOT it resolved so the arm cannot pass by not running. KNOWN and accepted (D7), and the reason this row is about the WORKING TREE and nothing wider: a worktree shares one `.git`, so from the copy a suite can still write the shipping repository's refs, `.git/config` and `.git/hooks` — measured in validation round 1 as a tag, a branch, a config key and an executable post-checkout hook — and a commit inside the copy still writes unreferenced objects into the shared object database. Neither HEAD nor the porcelain moves in any of those, which is why they are filed as fu-worktree-shares-git-admin-surface and fu-worktree-hook-disarms-later-suites rather than fixed here |
| Spec-AC-02 | WHEN a suite is edited but not committed, a production file is edited but not committed, or a suite file is brand new and untracked THEN all three are visible to the run | done | TEST-002 green | — | the naive patch fails exactly here: `git worktree add` checks out a commit, so a new suite reports `No such file or directory` and is counted a test failure, which is a TDD RED that can never go red. Closed by replaying `git diff HEAD --binary` and copying the untracked-not-ignored set |
| Spec-AC-03 | WHEN a suite reads a gitignored per-dev file THEN it finds it in the disposable checkout, so no assertion that runs today silently becomes a skip | done | TEST-003 green including its in-arm negative control; live-tree comparison of the four named groups | — | the risk this scope was most likely to ship silently wrong: docs/ai/STATE.yaml is gitignored, so an unseeded worktree turns check-state TEST-010 and TEST-002, orchestration-mode TEST-016 and orchestration-dispatch's repo-wide gate into PASSING SKIPS. Proven by comparing output against the live tree, not by reading the code |
| Spec-AC-04 | WHEN a run passes, fails, is killed by the watchdog, or is interrupted THEN the disposable checkout is gone and no git worktree list entry survives | done | TEST-004 green over all five exits | — | both halves are asserted every time, because a leaked REGISTRATION is worse than a leaked directory. The arm found a real defect during this ride: `iso_create` originally echoed the checkout path, so the cleanup-list append ran in a command substitution's subshell and the traps drained an empty list; a watchdog kill leaked both the directory and the registration. A fifth exit was added after mutation: dropping the failure-path deregistration bit NOTHING, because on every other path `git worktree remove` clears the registration itself — the sub-arm where a suite deletes its own checkout's .git link is what makes it falsifiable. CORRECTED 2026-08-20 (code review NB-1): the backstop was a repository-wide `git worktree prune`, which was measured to destroy an operator's unreachable worktree metadata irrecoverably; it is removed and replaced by a single-entry `iso_deregister`, see D4 |
| Spec-AC-05 | WHEN a suite is run through .aai/scripts/aai-run-tests.sh THEN it is isolated too, and the wrapped command's exit code is unchanged | done | TEST-005 green | — | scoped to suite runs by measurement, not preference: this wrapper also carries builds and generators, and isolating those would discard the artifact with the checkout. tests/skills/test-framework.sh is excluded because it isolates per suite itself and its run ledger must land in the real tree (D5). The arm found a second real defect: an absolute suite path built from macOS's trailing-slash TMPDIR carries a `//` that no prefix test against a cd-normalised root matches, so the working directory moved while the suite path still pointed at the shipping repository. The framework opt-out is matched by RESOLVED PATH, not by suffix, and against the EXECUTED SCRIPT only: the original `*test-framework.sh` glob was tried against every argument, so one decoy word like my-test-framework.sh, with no file behind it, silently disabled isolation for the whole invocation (validation F4), and the exact match that replaced it was still scanned over every argument, so a writing suite carrying the genuine framework path as one of its own arguments disabled it too (Codex, PR #267 — measured as ` M tracked.txt` plus `?? untracked-dirt.txt` at exit 0 under the report-only tripwire). TEST-005(e), TEST-005(f) and TEST-005(g) hold the three directions |
| Spec-AC-06 | WHEN isolation is on THEN it adds under 2 seconds of wall clock per suite, measured rather than estimated | done | TEST-006 green, printing the measured per-suite figure; plus the observed full-run delta against a baseline run | — | the components were measured separately as well: worktree add, the working-tree replay and the removal. The arm derives the figure from two runs of one fixture rather than asserting a constant, so it tracks the machine it runs on |

Status values: planned | implementing | done | deferred | blocked | rejected

Every row reads `implementing` until the close ceremony, measured rather than
preferred: `docs-audit`'s false-open heuristic fails CLOSED on a fully terminal
AC Status table whose delivery is un-timestampable — no delivery commit, no
`ac_evidence` event — and reports `probable-false-open`. That verdict removes
the literal `CLEAN` token from the audit output, which turns
`tests/skills/test-aai-doc-numbering.sh` TEST-013 red. The same reasoning is
recorded at length in SPEC-0137 and tracked as `fu-acgate-vs-falseopen-catch22`.
The rows flip at the close ceremony, once the delivery commit exists.

## Implementation plan

Components:

- `tests/skills/test-framework.sh` (EDIT) — the isolation block (probe, create,
  destroy, drain) plus the four traps; `run_test` creates a checkout, runs the
  suite from it with the working directory moved there, and destroys it BEFORE
  the tripwire's after-snapshot so the removal falls inside the tripwire's
  window. Every degrade path names itself with `log_warn` and falls back to the
  previous behavior.
- `.aai/scripts/aai-run-tests.sh` (EDIT) — `AAI_SELF_DIR` and `AAI_REPO_ROOT`
  hoisted to the top (the isolation block changes the working directory, after
  which `dirname "$0"` no longer resolves for a relative invocation, and two
  existing readers of that location move onto them); the suite-run detection;
  the same three-step seeding; absolute-argument retargeting; the removal after
  the group reap and on `INT`, `TERM` and `HUP`.
- `tests/skills/test-aai-suite-isolation.sh` (NEW) — the six arms above.
- `tests/skills/test-aai-repo-tripwire.sh` (EDIT, one statement) —
  `export AAI_TEST_ISOLATION=0`, so its fixture suites can still reach their
  own fixture repositories and the tripwire arms still bite.
- `tests/skills/suite-map.yaml` (EDIT) — the `aai-suite-isolation` row.

Companion obligations (closed list). PROMPT CORPUS BYTES MOVE: NO — no
`.aai/*.prompt.md` and no `.aai/AGENTS.md` byte change, so no prompt-diet
ledger true-up is owed. NEW `.aai/**` FILE: NO — the isolation is inline in the
existing wrapper, so no `.aai/system/PROFILES.yaml` classification and no new
entry in `tests/skills/test-aai-spec-lint.sh` TEST-011(clarify)'s branch-diff
allowlist are owed; `.aai/scripts/aai-run-tests.sh` is already listed there.
The mechanical obligations that DO apply: the new suite needs a
`tests/skills/suite-map.yaml` row (`tests/skills/test-aai-hygiene-pack.sh`) and
every `test_*` function must be wired into `main()`
(`.aai/scripts/check-test-registration.mjs`).
