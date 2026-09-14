---
id: test-framework-sweep
type: change
number: 185
status: draft
capability: test-framework-sweep
links:
  pr: []
  commits: []
---

# The test framework is fast, hermetic and honest about what it ran

## Summary
- Wave 3, sweep 2 (`docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md`).
  Paired maintenance half: `residuals-of-the-per-suite-clone-ride` (CHANGE-0166).
- The full skills sweep is the cost every ride pays: 92 suites, 32 minutes
  sequential locally, 19 to 25 minutes on CI. It is also the least trusted
  gate in the factory: PR #376 needed six CI runs for one change, three of
  them red on a failure that never reproduced locally in twelve isolated
  runs. That failure was already on file as `fu-layer-profiles-fixture-build-race`
  (2026-09-02, P3): the layer-profiles fixture build swallows the sync's
  "core-listed file missing in source" warning, so a build that copied an
  incomplete tree under parallel load reads as a mystery MISSING list, and
  the two wrappers that nest the suite (`feedback-upsert` TEST-009,
  `friction-wiring` TEST-006) printed only `tail -3` of it.
- The registry holds 84 open items whose subject is the framework itself
  (isolation, seeding, tripwire, ratchets, fixture leaks, pins that tax later
  scopes, assertions that die on their own payload). CHANGE-0180 (P1: one
  agent's branch switch moves another agent's HEAD in a shared worktree),
  DEBT-0004 (guards vacuously green on an unexercised path), DEBT-0006 (389
  assertions still pipe their payload into grep), ISSUE-0039/0041/0043/0044
  and GitHub #368 (a Windows deterministic script failure in REMEDIATION
  reproduce) belong to the same subsystem.

## Motivation / Business Value
- Every later sweep runs this framework three to six times per ride. A
  minute saved here is saved forty times a week; a flake fixed here removes a
  CI rerun from every ride.
- A gate that reports the wrong thing (tripwire), hides the failing line
  (nested wrappers), passes when it scanned nothing (vacuous guards) or dies
  on its own payload (pipe-into-grep) is not a gate. The owner's mandate is a
  framework that is functional, and functional starts with the thing that
  decides what functional means.

## Scope
- In scope, fixed with a test each:
  - the layer-profiles fixture build fails loudly on any copy or sync warning,
    and the two nesting wrappers print the nested suite's failure lines;
  - CHANGE-0180: the ceremony refuses to run in a worktree another live
    session holds, and the close/PR scripts pin the HEAD they started on;
  - CHANGE-0166: the sweep no longer runs sequentially where suite isolation
    already makes it safe to run wide (measure the wall-clock before and
    after; state the width and why);
  - the isolation and seeding items (`fu-iso-*`, `fu-seed-*`,
    `fu-isolation-suite-*`, `fu-tripwire-*`, `fu-wrapper-hidden-suite-run-unreported`,
    `fu-drained-suites-still-write-unisolated`);
  - the pin and ratchet items that tax later scopes
    (`fu-ceremony-test016-blanket-byte-pin`, `fu-test031-*`, `fu-usage-pin-*`,
    `fu-exit-contract-pin-*`, `fu-closure-allowlist-pin-*`, `fu-test029-count-not-subset`,
    `fu-test013-uncovered-on-legal-max-raise`);
  - `fu-drain-pipe-grep-q-ratchet` and DEBT-0006 (drain the pipe-into-grep
    idiom to zero, ratchet held at zero);
  - DEBT-0004 (self-comparing guards get a negative control);
  - `fu-validation-ignores-suite-selector`, `fu-tdd-skips-full-sweep`
    (validation and TDD pick suites the way CI does);
  - `fu-ismain-symlink-realpath` and `fu-cli-exit-truncates-pipe-sweep`
    where the framework's own CLIs are affected;
  - GitHub #368.
- Rejected or re-homed with a recorded reason: any item in the bucket whose
  fix is prose only, whose claim has since been withdrawn, or whose subject is
  a different subsystem (the ride names each in `## Registry items closed by
  this scope` of its spec, with `follow-ups.mjs close --status dropped`).
- Out of scope: `close-work-item.mjs` internals (sweep 4); the dispatcher
  (sweep 3); Windows Pester legs beyond #368.

## Affected Area
- `tests/skills/test-framework.sh`, `.aai/scripts/aai-run-tests.sh`,
  `tests/skills/lib/*.sh`, `tests/skills/test-aai-layer-profiles.sh`,
  `tests/skills/test-aai-feedback-upsert.sh`, `tests/skills/test-aai-friction-wiring.sh`,
  `tests/skills/test-aai-repo-tripwire.sh`, `tests/skills/test-aai-suite-isolation.sh`,
  the pinned suites named above, `.aai/scripts/select-suites.mjs`,
  `.aai/scripts/branch-guard.mjs` and the close/PR scripts for the HEAD pin,
  `.aai/VALIDATION.prompt.md` / `.aai/TDD.prompt.md` suite-selection text.

## Desired Behavior (To-Be)
- A red sweep names the failing assertion and the file list it compared, at
  the top level, never behind a wrapper's tail.
- A suite that could not build its fixture completely fails at the build,
  naming what it could not copy.
- The full sweep runs wide by default with the attribution guarantee kept
  (a shipping-repository change is still attributed serially), and its
  wall-clock is stated in the spec before and after.
- No test in `tests/skills` pins a count it does not compute, compares a file
  against itself, or pipes an assertion payload into `grep -q`.
- Two sessions cannot move each other's HEAD: the ceremony refuses on a
  worktree another live session holds.

## Notes
- The bucket query that defines this sweep: open follow-ups whose id or
  finding mentions test, suite, framework, hygiene, isolation, tripwire,
  sweep, fixture, mutation, ratchet, flake, seed, checkout, worktree or clone
  (84 on 2026-09-13; the spec freezes the list by id).
- Ceremony 2, TDD, mutation checks per test; validator independence; runs in
  a sibling worktree because it edits the framework the validation itself runs.
