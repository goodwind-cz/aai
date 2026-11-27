---
id: ci-flake-root-causes
type: issue
number: null
status: draft
capability: ci-flake-root-causes
user_visible: false
links:
  pr: []
  commits: []
---

# Recurring CI flakes and the open test-infrastructure P2s, fixed at their cause

## Summary
- The owner asked (2026-11-27) to remove the recurring CI flakes and the
  open test-infrastructure P2 follow-ups, each at its root cause, under the
  READ, REPRODUCE, ISOLATE, FIX-AT-CAUSE protocol of
  `.aai/SKILL_DEBUG.prompt.md`. No retry is added and no timeout is widened.
- In scope, one item each:
  1. `tests/skills/test-aai-sweep-parallel.sh` TEST-006, "the run ledger
     survives concurrent framework runs": red on hosted shards (main
     5f02b0e5 run 45684256309, PR #592 runs 45722963303 and 45768710454,
     main runs 44516413473, 44729054551, 45820225151). Registry item
     `fu-sweep-parallel-t006-runid-collision`. The suspected cause (two
     framework runs started in the same second share one run directory) is
     to be confirmed or refuted by measurement.
  2. The release suite's TEST-3537 (`tests/skills/lib/aai-release.test.mjs`,
     run by `tests/skills/test-aai-release-cut.sh`): a signal sent to the
     whole process group during a git step sometimes ends with the
     git-command refusal (exit 20) instead of the interrupted line (exit
     143). Red on the first CI run of PR #597 (run 45851092185) and on main
     before; it passes locally.
  3. `.aai/scripts/close-reconcile.mjs` arm `id-mention-unpaired`: a
     delivered document that merely MENTIONS an open document's id is
     reported as a false-open (SPEC-0181 mentions DEBT-0007 and tripped the
     main push 5f02b0e5). Registry item `fu-reconcile-mention-vs-disclosure`.
     True positives (a delivered document that claims an open document as
     its paired half) must stay detected.
  4. `tests/skills/lib/release-first.test.mjs` fails under the release
     preflight's environment ("FAILS ON BASE TOO") while CI passes.
  5. `fu-xdg-fallback-path-is-shared` (P2): when no private cache directory
     can be made, `aai-run-tests.sh` and `test-framework.sh` fall back to the
     fixed `XDG_CACHE_HOME=/nonexistent/aai-test-no-xdg-cache`, which a
     root-run tool could create and share across runs.
- Also in scope: any other open follow-up whose finding is a CI flake in the
  same suites (sweep-parallel, the release suite, close-reconcile,
  release-first, the runner); each one taken is listed in the spec.

## Type
- bug

## Impact
- Every flake costs a rerun of a 30 to 55 minute sharded CI run and trains
  the operator to ignore red; item 3 blocks a main push on a correct merge.
- Severity/priority: P2 (CI reliability; no shipped behaviour is wrong
  except item 3's gate and item 5's isolation fallback).

## Current Behavior
- Items 1 and 2 fail intermittently on hosted Linux runners only.
- Item 3 reports `OPEN ... reason=id-mention-unpaired` for a document that a
  delivered document names only to say it is NOT absorbed or is a
  different ride.
- Item 4 fails whenever the test runs with a HOME that does not hold the
  developer's Pester module.
- Item 5 points the wrapped command's cache at a fixed shared path.

## Expected Behavior
- Items 1 and 2 have a measured root cause and a fix at that cause; their
  tests are deterministic.
- Item 3 items a document only when a delivered document claims it.
- Item 4 gives the same verdict in any environment, or names what it did
  not run.
- Item 5 never uses a shared or fixed cache path and never the user's real
  `~/.cache`.

## Steps to Reproduce (if applicable)
1) Items 1 and 2: the CI runs named above; locally the tests pass.
2) Item 3: `node .aai/scripts/close-reconcile.mjs --check --range 5f02b0e5^..5f02b0e5 --root .`
   prints `OPEN docs/issues/DEBT-0007-... reason=id-mention-unpaired`.
3) Item 4: run `node --test tests/skills/lib/release-first.test.mjs` in a
   `git clone --shared` with HOME, XDG_CACHE_HOME and XDG_CONFIG_HOME set
   to empty temporary directories (the release preflight's environment).
4) Item 5: `TMPDIR=/nonexistent bash .aai/scripts/aai-run-tests.sh env`
   prints `XDG_CACHE_HOME=/nonexistent/aai-test-no-xdg-cache`.

## Verification
- Command(s) and expected results:
  - each touched suite passes through `aai-run-tests.sh` with
    `env -u AAI_ROLE`;
  - a regression test per item fails before its fix and passes after it;
  - the item 3 replay over the last 150 first-parent merges of main names
    no document that is only mentioned.

## Constraints / Risks
- Known risks or constraints: tests never push to a real remote, never
  install hooks into a real repository, never touch the real docker daemon
  and never use the developer's real `~/.cache`. No `rm -rf` of an
  unguarded variable path.
- Secrets preflight results (if any secret referenced): no secret is
  referenced.

## Notes
- Assumption (autopilot): the ride runs in its own worktree,
  `/Users/ales/Projects/aai-worktrees/ci-flake-fixes`, decided by the
  owner's brief.
- Assumption (autopilot): Planning decides the implementation mode;
  human_time_minutes is recorded as null.
- Out of scope: PR #535.
