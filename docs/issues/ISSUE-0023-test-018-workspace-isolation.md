---
id: test-018-workspace-isolation
number: 23
type: issue
status: done
links:
  pr:
    - 128
  commits:
    - 1f725c291cc3bc5e9f211b00bf4212eee237910e
---

# TEST-018 reaper fail-safe still flakes: 6 cases share one workspace (cross-iteration proc pollution)

## Summary
- `tests/skills/test-aai-run-tests.sh` TEST-018 (reaper legacy fail-safe) is still
  intermittently red on CI despite the CHANGE-0043-follow-up split-direction fix
  (SPEC-0064; `reaper-failsafe-test-margins` PR #123). Root cause of the RESIDUAL
  flake: all six invalid-epoch cases (UNSET/EMPTY/abc/-5/0/future) share ONE
  workspace `$ws` (line ~568, a single `mktemp -d` above the `for invalid` loop).
  The reaper matches by `AAI_REAP_WORKSPACE`, so a `spare-fresh` reap in a later
  case (MIN_AGE=60) can match/reap a leaked process from an EARLIER case's
  `reap-old` direction that outlived its reap — producing the observed
  "fail-safe broken (case='-5'): … must still spare the fresh match (reaper
  output: reaped: 1)". The split-direction MARGINS were right; the SHARED
  WORKSPACE was not addressed. Blocked release PR #127 (a pure CHANGELOG rollup).

## Type
- bug

## Impact
- `aai-run-tests` is a REQUIRED CI check (branch protection); this residual flake
  intermittently BLOCKS every merge (release #127 + any PR), each costing a ~8-min
  re-run. The deterministic EPOCH-mode tests (TEST-006/016/017) pass reliably — the
  flake is isolated to the inherently-racy LEGACY fallback path TEST-018 exercises.
  Severity: medium — no product impact, but it erodes the enforced gate.

## Current Behavior
- One `$ws = mktemp -d …/ws18.XXXXXX` is reused for all 6 cases and BOTH directions.
  Direction 1 (`reap-old`, MIN_AGE=1) spawns `vitest_old18_${ws}`; direction 2
  (`spare-fresh`, MIN_AGE=60) spawns `vitest_fresh18_${ws}`. Because both markers
  carry the same `$ws` and the reaper matches by workspace, any process that
  outlives its intended reap (or a slow/late kill under load) remains matchable by
  a subsequent case's reap → an unexpected "reaped: N" flips the spare assertion.

## Expected Behavior
- Each case's spare/reap assertion sees ONLY its own two processes; no process from
  a prior case or the other direction can be matched. The legacy fail-safe is
  proven deterministically (invalid epoch → legacy MIN_AGE behavior, both
  directions) with no shared-state race.

## Steps to Reproduce (if applicable)
1) Under CI load, run `tests/skills/test-aai-run-tests.sh` repeatedly; TEST-018
   intermittently fails on a `spare-fresh` case with "reaper output: reaped: 1"
   (observed on PR #122 and PR #127).

## Verification
- Each of the 6 cases (and ideally each direction) uses a FRESH workspace, so the
  reaper can never match a process spawned by another case/direction.
- Every process spawned in a case is guaranteed dead before the next case begins
  (explicit kill of BOTH old and fresh, not only the fresh; `reap-old` also cleans
  up if the reap missed).
- `bash tests/skills/test-aai-run-tests.sh` exits 0 on macOS across repeated runs;
  the CI `skill-suite` job is green on Ubuntu across a repeated run (the flake
  reproduces only under Linux CI load — CI is the authoritative environment).
- The split-direction load-immune margins (MIN_AGE=1 reap-old, MIN_AGE=60
  spare-fresh) are PRESERVED; both directions still prove the LEGACY path was taken.

## Constraints / Risks
- Do not "widen" a margin again (that only diluted the flake). The fix is
  STATE ISOLATION: a fresh `AAI_REAP_WORKSPACE` per case (per direction is even
  safer) + deterministic teardown of every spawned marker process each iteration.
- Keep it Linux-portable (LEARNED 2026-07-19): `mktemp` full template, `git init -b
  main` n/a here, no `stat -f`-first, honor shebang; the reaper is invoked via `sh`
  and `dash` in adjacent tests — keep POSIX-safe.
- Do NOT touch the reaper `.aai/scripts/aai-reap-tests.sh` — its epoch guard is
  correct and deterministically tested (TEST-006/016/017). This is a TEST-ONLY
  isolation fix; the production reaper is unchanged.
- Honest verification: the residual flake is load-related and does not reproduce
  reliably on macOS — CI (Ubuntu) is authoritative; verify green across a repeated
  CI run, and the isolation removes the mechanism rather than relying on luck.
- No secret referenced — SECRETS PREFLIGHT skipped.

## Notes
- This is the second correction to the same test; the first (PR #123) fixed the
  single-threshold-for-both-directions race but left the shared-workspace vector.
  Root-cause honesty: the LEGACY fixed-threshold reap is inherently racy (that is
  why epoch mode exists); the test must therefore isolate state, not out-margin the
  race.
