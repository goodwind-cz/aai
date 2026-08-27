---
id: isolation-shares-the-shipping-git
type: issue
number: null
status: draft
links:
  pr: []
  commits: []
---

# Suite isolation moves the working directory but never removes reach

## Summary
- A suite running in a disposable `git worktree` is called isolated, but the
  worktree shares the shipping repository's `.git`. Isolation therefore
  relocates the working directory and removes nothing: refs, `config` and
  `hooks` of the live repository stay writable from inside the "isolated"
  run, and the degraded gate never fires because the suite looks isolated by
  the only measure it takes.

## Type
- bug

## Impact
- Measured directly on this repo (2026-08-27, disposable
  `git worktree add --detach`): from inside the worktree,
  `git rev-parse --git-common-dir` returns `/Users/ales/Projects/aai/.git`
  and `git config --local probe.isolation <value>` succeeds; the shipping
  checkout reads the value back immediately. Cleaned up afterwards.
- This is the mechanism behind two P1s and at least two P2s:
  `fu-isolated-suite-reaches-shipping-repo` (isolation moves cwd, not reach —
  degraded never fires, and once the tripwire is retired nothing observes the
  write), `fu-subagent-probe-hits-real-repo` (a read-only role's probe ran git
  against the shipping repo and created two commits on `main`; recovered by
  hand, and the finding's own words are "nothing structurally prevented it"),
  `fu-worktree-shares-git-admin-surface`, and
  `fu-worktree-hook-disarms-later-suites` (one suite can arm a failing
  `post-checkout` hook through the shared `.git`, after which every LATER
  suite in the run executes in the live tree).
- Severity/priority: P1. The blast radius is the shipping repository during a
  routine test run, and the only thing that has caught it so far is luck plus
  a tripwire the project has already debated retiring.

## Current Behavior
- `tests/skills/test-framework.sh` and `.aai/scripts/aai-run-tests.sh` place a
  suite in a disposable worktree and record it as isolated. The isolation
  measure is positional (which directory the suite runs in). Nothing asserts
  that the suite's git administrative surface is separate from the shipping
  one, so `--git-common-dir` pointing at the live `.git` is invisible to the
  gate.
- The repo-tripwire compensates AFTER the fact by noticing the shipping tree
  changed; it observes damage, it does not prevent reach, and it cannot see a
  write that leaves the working tree clean (refs, config, hooks).

## Expected Behavior
- A suite declared isolated cannot reach the shipping repository's git
  administrative surface. Concretely: from inside an isolated run,
  `git rev-parse --git-common-dir` must NOT resolve into the shipping
  checkout, and a write to `config`, `refs` or `hooks` must land somewhere
  the shipping repository never reads.
- The isolation gate MEASURES that property rather than assuming it: a suite
  whose git surface still resolves to the shipping `.git` is reported
  degraded (or refused), not counted as isolated.
- A test proves both directions: a suite given a separated git surface passes
  the new assertion, and a suite given today's shared-`.git` worktree fails
  it.

## Steps to Reproduce (if applicable)
1) `git worktree add --detach <scratch> HEAD`
2) `cd <scratch> && git rev-parse --git-common-dir` -> the shipping `.git`.
3) `git config --local probe.isolation x` from inside the worktree.
4) In the shipping checkout: `git config --local --get probe.isolation`
   returns `x` — the "isolated" run wrote the live repository.
5) `git config --local --unset probe.isolation`;
   `git worktree remove --force <scratch>`.

## Verification
- A new suite arm asserts the separation property and is shown red against
  today's shared-`.git` isolation and green after, with a mutation proof and
  an unmutated control.
- `bash tests/skills/test-framework.sh` full sweep green, and the isolation
  accounting still reports every suite (no suite silently drops out of the
  isolated set to satisfy the new assertion).

## Constraints / Risks
- Whatever replaces the shared-`.git` worktree must keep the suites' legitimate
  git needs working (fixtures that commit, `git worktree add` inside a suite,
  history reads). A separated surface that breaks those trades one defect for
  a dozen; Planning decides the mechanism (own `GIT_DIR`, a local clone, or a
  hard refusal at the boundary) and states its cost.
- Cost is a real constraint, not an afterthought: the full sweep is 81 suites
  and already takes ~22 minutes. A per-suite `clone` that adds seconds each is
  a measurable regression and must be measured, not assumed.
- `.aai/scripts/aai-run-tests.sh` has a PowerShell twin; the owner decided on
  2026-08-25 that the dual `sh`/`ps1` surface is an accepted standing cost, so
  a change here owes the twin the same treatment or an explicit note.
- protected_paths_l3 must not be edited. `.aai/scripts/close-work-item.mjs` is
  content-hash pinned and must not be touched.
- This issue closes the SHARED-GIT mechanism only. It does NOT close the
  tripwire reporting findings, the ISOLATION_BASES reset, the wrapper's trap
  reaping, or the framework run-dir collision — those are separate items and
  stay open.
- No secrets referenced.

## Notes
- Registry: targets `fu-isolated-suite-reaches-shipping-repo` (P1),
  `fu-worktree-shares-git-admin-surface` (P2),
  `fu-worktree-hook-disarms-later-suites` (P2), and the structural half of
  `fu-subagent-probe-hits-real-repo` (P1) — the recovery already happened; what
  is missing is the prevention.
- The two most prolific registry sources are `suites-must-not-touch-the-
  shipping-repo` (10 open) and `suites-run-in-a-disposable-worktree` (9 open).
  Both describe this one mechanism from different angles.
