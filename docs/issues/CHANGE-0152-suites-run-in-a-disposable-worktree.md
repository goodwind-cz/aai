---
id: suites-run-in-a-disposable-worktree
number: 152
type: change
status: done
user_visible: false
ceremony_level: 1
capability: aai-test-harness
links:
  pr:
    - 267
  commits:
    - a7f40dcd2102f14860c5e2d0a0b4f2a8f6523b86
---

# Change — every suite runs in a disposable worktree

## Summary
- Both suite funnels run each suite in a throwaway `git worktree` seeded with the
  working tree, instead of in the live checkout. A suite's writes then land in the
  copy: the shipping **working tree** is protected, and observably so — `git
  rev-parse HEAD` and `git status --porcelain=v1` come back byte-identical.
- What isolation does **not** prevent, said plainly: a `git worktree` shares one
  `.git`, so from inside the disposable checkout a suite can still write the
  shipping repository's refs, `.git/config` and `.git/hooks`. Measured in
  validation — a tag, a branch, a config key and an executable `post-checkout`
  hook all landed, with HEAD and the porcelain unmoved and the tripwire silent.
  Not a regression, and not closed here: filed as
  `fu-worktree-shares-git-admin-surface` and
  `fu-worktree-hook-disarms-later-suites`, detailed in the spec's D7.
- This removes the **cause** that CHANGE-0151's tripwire was built to detect. The
  tripwire is deliberately **left in place by this change** and deleted by a
  separate one, after a CI cycle has shown isolation holding on Linux.

**CORRECTION (2026-08-23).** The deletion described above did not happen and is
no longer planned. A superseding `hitl_decision` in `docs/ai/decisions.jsonl`
withdraws the 2026-08-19 one: the disposable worktree landed and does NOT remove
a suite's REACH — from inside the checkout,
`dirname $(git rev-parse --git-common-dir)` names the shipping tree in one call,
because a worktree shares the common git dir
(`fu-isolated-suite-reaches-shipping-repo`, P1). The retirement scope measured
the counterfactual and stopped on its own acceptance criterion. The tripwire is a
PERMANENT layer. Exactly one registry item closed as moot
(`fu-tripwire-removal-needs-a-gate`); every other tripwire defect stays open.

## Motivation / Business Value
- Four suites write to the shipping repository today and are exempted by a ratchet.
  With isolation they simply cannot, and the exemptions become meaningless.
- Roles currently skip suites that dirty the tree, so the surface those suites
  cover goes unverified exactly when it matters.
- Measured on 2026-08-19/20: 13 of 13 sampled suites pass under isolation with **no
  suite edits**, because every suite resolves `PROJECT_ROOT` from its own path. All
  four known writers wrote into the copy and the shipping tree came back empty.

## Scope
- In scope: `tests/skills/test-framework.sh`, `.aai/scripts/aai-run-tests.sh`, and the
  seeding of gitignored per-dev files the suites read.
- Out of scope, deliberately: deleting the tripwire, its ratchet and the ratchet-path
  hashing (~1140 lines). That is the follow-on change and must not land here.
  *(2026-08-23: that follow-on change was attempted and STOPPED by its own
  measurement. See the correction above.)*
- Out of scope: making any suite hermetic in its own right; anything under
  `protected_paths_l3`.

## Affected Area
- `tests/skills/test-framework.sh` — invokes each suite with a bare `bash "$test_file"`.
- `.aai/scripts/aai-run-tests.sh` — wraps an **arbitrary command**, used ad hoc by roles.
  It is in scope: while it is unguarded, a role can still run a suite against the live
  tree, which is why the tripwire cannot be removed until this lands.

## Desired Behavior (To-Be)
- D1 — a suite runs in a disposable checkout and its writes never reach the shipping
  **working tree** (the shared `.git` surface is out of scope, see the Summary).
  Verified by `git status --porcelain=v1` and `git rev-parse HEAD` being
  byte-identical across a run of the four known writers.
- D2 — the disposable checkout reflects the **working tree**, not `HEAD`. A worktree
  checks out a commit, so uncommitted edits and brand-new suite files are invisible
  and a TDD RED can never go red. Measured: the naive patch reports a new suite as
  `No such file or directory` and calls it a test failure. The tracked diff is
  replayed and untracked-not-ignored files are copied. Cost measured at 0.04s.
- D3 — gitignored per-dev files the suites read are seeded into the copy. Without this
  four assertion groups silently become **passing skips** — a greener run that tests
  less, the exact failure mode the tripwire exists to prevent. Measured and verified
  on 2026-08-20: seeding restores all four.
- D4 — the disposable checkout is removed after the suite, including when the suite
  fails, times out, or the run is interrupted.
- D5 — the harness's own writes (the run ledger under `tests/skills/results/`) still
  land where the operator expects them, not in the discarded copy.

## Acceptance Criteria
- AC-001: running the four known writers leaves `git rev-parse HEAD` and
  `git status --porcelain=v1` byte-identical on the shipping tree, demonstrated by
  running them.
- AC-002: an uncommitted edit to a suite, an uncommitted edit to a production file,
  and a brand-new untracked suite file are all visible to the run.
- AC-003: no assertion that runs today becomes a skip. Demonstrated on the four groups
  named in D3, by comparing the run output against the same suites in the live tree.
- AC-004: the disposable checkout is gone after a passing run, a failing run, and a
  run killed by the watchdog; no `git worktree list` entry survives.
- AC-005: `.aai/scripts/aai-run-tests.sh` isolates too, and still never alters the
  wrapped command's exit code.
- AC-006: added wall-clock is under 2 seconds per suite, measured, not estimated.

## Verification
- run the four known writers and diff `git status --porcelain=v1` before and after
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed files>`
  returns; a `.aai/scripts/lib/**` or harness change triggers the full framework
- a **full 80-suite run**, observed rather than extrapolated, reporting the aggregate
  and the wall-clock delta against a baseline run
- prove each new assertion **bites** by mutation, at full-suite level, with an
  unmutated green control

## Constraints / Risks
- The tripwire stays and must keep passing. If isolation is complete it will simply
  never fire; if it fires, that is information, not a conflict.
- Unmeasured and stated: CI/Linux behaviour, the PowerShell and WSL paths, parallel
  execution, and 67 of ~80 suites. None blocks a start; CI is the first Linux datum.
- `git worktree add --detach` leaves a detached HEAD, so `branch --show-current`
  returns empty. Three suites call it and all three passed, but `-b <throwaway>`
  removes the question if it bites.
- Bash only, no dependencies. No change to `protected_paths_l3`.
- No secret is referenced by this scope.

## Notes
- Registry items this scope closes: none directly. It makes ~12 tripwire items and
  4 known-writer items **deletable by the follow-on change**, which is where they
  are closed.
- Ride discipline: ship on these acceptance criteria and nothing else. A finding
  outside them is filed, not fixed here. Two validation rounds maximum.
- Prior measurement lives in `docs/ai/decisions.jsonl` under
  `suites-must-not-touch-the-shipping-repo`: the feasibility probe, and the
  verification that seeding restores the four skipped groups.
