---
id: disposable-checkout-lifecycle-residuals
type: issue
number: 39
status: draft
links:
  pr: []
  commits: []
---

# The disposable checkout is created and destroyed by bookkeeping that loses track of it

## Summary
- Nine registry items were filed under the ride `suites-run-in-a-disposable-worktree`.
  Two are closed by the ride now in flight. The rest are the LIFECYCLE around the
  checkout rather than the checkout itself: the registry of live bases is reset wholesale,
  the wrapper's signal traps delete the checkout out from under a still-running suite, and
  three of the ancillary items are about probes and ceremonies that fail closed to a
  number or an order nobody checks.

## Type
- bug

## Impact
- Affected: `tests/skills/test-framework.sh` (the isolation bookkeeping),
  `.aai/scripts/aai-run-tests.sh` (the wrapper traps), and any interrupted run.
- The trap case is the sharp one: Ctrl-C can leave a suite executing with its cwd
  unlinked, writing into a deleted directory or resolving relative paths against whatever
  remains.

## Current Behavior
Verified in a disposable clone of `origin/main` (`c6b32d0`):

- `fu-iso-bases-reset-discards-entries` (P2, code review NB-3). `ISOLATION_BASES=()`
  resets the array WHOLESALE at `tests/skills/test-framework.sh:757` (the
  not-in-the-disposable-checkout degrade branch) and `:795` (the post-run destroy),
  discarding any entry it did not create. The array is what the EXIT/INT/TERM/HUP traps
  drain, so a wholesale reset is only correct while exactly one checkout is ever live.
  The paired hole is at `:394`: `iso_create` appends the base BEFORE the three seeding
  steps that begin at `:395`, so an abort between the append and the caller's success
  leaves the base registered while the caller never destroys it — and the next wholesale
  reset then discards both a directory and a git registration past the trap.
- `fu-iso-wrapper-traps-dont-reap-group` (P2, code review NB-4).
  `.aai/scripts/aai-run-tests.sh:512-514` installs
  `trap 'aai_iso_cleanup; exit 130' INT` and its TERM/HUP siblings. They call cleanup and
  exit WITHOUT reaping the wrapped command's process group first, even though the
  setsid/pgid machinery immediately below those lines exists for exactly that and the
  comment above them says a pass and a failure "both reach the removal after the group
  reap below". Ctrl-C therefore removes the checkout while the suite is still in it.
- `fu-ismain-symlink-realpath` (P2, measured 2026-08-20 under macOS TMPDIR). A `.mjs`
  CLI that guards `main()` with
  `path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)` is FALSE whenever
  the checkout is reached through a symlink, so the CLI exits 0 having printed nothing —
  indistinguishable from success. Measured on macOS, where TMPDIR lives under `/var`, a
  symlink to `/private/var`: `orchestration-dispatch.mjs` produced empty stdout at exit 0
  and three hitl-propagation arms read as assertion failures. Worked around by
  realpathing the disposable checkout in `test-framework.sh` `iso_create` and
  `aai-run-tests.sh`, NOT fixed at the guard. Measured today: 18 of the 52 top-level
  `.aai/scripts/*.mjs` files reference `process.argv[1]`.
- `fu-orchestrator-monitor-uses-gnu-find` (P2). The orchestrator's liveness check used GNU
  `find -newermt '-N minutes'` with stderr to `/dev/null`; on this host `find` rejects it,
  so a silent command failure was reported as a measured zero. On 2026-08-20 that
  fabricated zero was the sole evidence for killing a subagent mid-run at 38 of 81 suites
  while it was working correctly. Measured today: `/usr/bin/grep -rn newermt .aai` returns
  nothing, so this lives in the orchestrator's own shell habits, not in a repository file.
- `fu-docsaudit-t003-red-on-new-doc` (P3). `tests/skills/test-aai-docs-audit.sh` TEST-003
  regenerates `docs/INDEX.md` and diffs it against the committed one, so it is RED for the
  whole life of any scope that adds a doc, and `test-aai-delta-stage3.sh` TEST-007 inherits
  the failure. Proven pre-existing on a pre-change clone at `2372805`, where the same arm
  fails with only an intake draft present and passes with it moved aside.
- `fu-ac-flip-must-precede-close` (P3). The AC Status rows must be flipped to a terminal
  state BEFORE `close-work-item.mjs` runs; the tool's own post-close audit rejects a
  document going to `done` while its AC rows are non-terminal (`cls=drifted`,
  `verdict=probable-false-done`) and rolls the close back. The documented order is the
  opposite, so every ride rediscovers it.
- `fu-filed-list-trusted-again` (P2). The orchestrator treated a role's `filed:` list as
  proof a registry entry exists; `fu-iso-suite-leaks-its-own-fixture-dirs` was cited as
  filed in a dispatch and in a decision, and grep of `decisions.jsonl` returns zero. This
  is a recurrence of `fu-suggested-ids-read-as-filed` opened one day earlier, and its
  mechanical cause is `fu-report-ids-exceed-registry-cap`; all three are one problem seen
  from three seats and should be planned together, not three times.

Closed by work in flight, recorded here so they are not re-filed:

- `fu-worktree-shares-git-admin-surface` (P2) and `fu-worktree-hook-disarms-later-suites`
  (P2). `docs/specs/SPEC-DRAFT-isolation-shares-the-shipping-git.md` (branch
  `fix/suite-isolation-owns-its-git`) lists both under "CLOSED FULLY": after its D1 there
  is no shared `.git`, a hook armed by a suite lives in that suite's own clone and dies
  with it, and the harness no longer calls `git worktree add` against the shipping
  repository at all.

## Expected Behavior
- Removing one base removes THAT base, not the array; a failed `iso_create` destroys what
  it registered.
- A signal trap kills the wrapped process group, waits, and only then cleans up.
- A `.mjs` CLI invoked through a symlinked path either runs or fails loudly; it does not
  exit 0 having printed nothing.
- A liveness probe that cannot run reports that it cannot run, never a number.

## Steps to Reproduce (if applicable)
1) Reset discards entries: register two bases and take the degrade branch at
   `test-framework.sh:757`; the trap's view now holds neither.
2) Traps do not reap: start `aai-run-tests.sh` on a long suite and send INT; the checkout
   is removed while the suite keeps running.
3) Symlink main guard: invoke any affected CLI through a path containing a symlink and
   observe exit 0 with empty stdout.

## Verification
- After an INT during a long suite, the suite is dead before the checkout is removed, and
  the wrapper's exit code still distinguishes the signal.
- A two-base fixture survives a degrade branch with both registrations intact.
- The affected CLIs produce identical output through a real path and a symlinked path.

## Constraints / Risks
- The two reset sites are inside the block the in-flight ride edits and are deliberately
  left byte-identical by that ride's D5; this work must land AFTER it, or it will conflict.
- Fixing the main guard at the guard (rather than by realpathing callers) touches many
  files at once and needs a per-CLI exit-code proof.

## Notes
- OUT OF SCOPE: the shared-`.git` mechanism and the two items it closes, above.
- OUT OF SCOPE: the tripwire's reporting defects, filed with the
  `suites-must-not-touch-the-shipping-repo` residuals.
- Registry ids covered: `fu-iso-bases-reset-discards-entries`,
  `fu-iso-wrapper-traps-dont-reap-group`, `fu-ismain-symlink-realpath`,
  `fu-orchestrator-monitor-uses-gnu-find`, `fu-docsaudit-t003-red-on-new-doc`,
  `fu-ac-flip-must-precede-close`, `fu-filed-list-trusted-again`,
  `fu-worktree-shares-git-admin-surface` (closed by the ride in flight),
  `fu-worktree-hook-disarms-later-suites` (closed by the ride in flight).
