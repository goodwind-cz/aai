---
id: ismain-symlink-realpath
type: issue
number: 57
status: draft
---

# P2 backlog cluster: suites-run-in-a-disposable-worktree (5 items)

## Summary
- Consolidated registry intake for 5 open P2 follow-up(s) filed against `suites-run-in-a-disposable-worktree`: `fu-ismain-symlink-realpath`, `fu-orchestrator-monitor-uses-gnu-find`, `fu-filed-list-trusted-again`, `fu-iso-bases-reset-discards-entries`, `fu-iso-wrapper-traps-dont-reap-group`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-ismain-symlink-realpath`**: every .mjs CLI guards main() with path.resolve(process.argv[1]) === fileURLToPath(import.meta.url), which is FALSE whenever the checkout is reached through a symlink, so the CLI exits 0 having printed nothing
  - Measured: a silent no-op at exit 0 is indistinguishable from success to every caller; measured on macOS where TMPDIR lives under /var (a symlink to /private/var), orchestration-dispatch.mjs produced empty stdout at exit 0 and three hitl-propagation arms read as assertion failures. Worked around here by realpathing the disposable checkout, not fixed at the guard
  - Source: measured 2026-08-20 in a disposable worktree under macOS TMPDIR; fixed locally by pwd -P in tests/skills/test-framework.sh iso_create and .aai/scripts/aai-run-tests.sh

- **`fu-orchestrator-monitor-uses-gnu-find`**: the orchestrator's liveness check for running agents used GNU find syntax (-newermt '-N minutes') with stderr sent to /dev/null; on this host find rejects it, so the check reported zero writes as a RESULT when it was a silent command failure
  - Measured: on 2026-08-20 that fabricated zero was the sole evidence for concluding a subagent had stalled, and I killed it mid-run at 38 of 81 suites while it was working correctly; a monitoring probe that fails closed to a number indistinguishable from a real measurement is the same defect class this repo has been chasing, applied to a destructive decision instead of a green test
  - Source: reproduced 2026-08-20: find /tmp -name probe -newermt '-5 minutes' errors and yields 0 for a file created one second earlier; the killed agent's log full-copy-off.log had mtime 14:02Z while the check at 14:02Z reported no writes for 8 minutes

- **`fu-filed-list-trusted-again`**: the orchestrator again treated a role's 'filed:' list as proof a registry entry exists; fu-iso-suite-leaks-its-own-fixture-dirs was cited as filed in a dispatch and in a decision, and grep of decisions.jsonl returns zero
  - Measured: this is a recurrence of fu-suggested-ids-read-as-filed, opened one day earlier for the identical mistake, so the lesson did not survive a single day; a disposition of 'filed rather than fixed' that rests on a nonexistent filing is a silent drop dressed as a decision
  - Source: code review NB-6, suites-run-in-a-disposable-worktree, 2026-08-20

- **`fu-iso-bases-reset-discards-entries`**: ISOLATION_BASES=() resets the array WHOLESALE at tests/skills/test-framework.sh (run_test, both the seeding-missed branch and the post-run destroy), discarding any entry it did not create
  - Measured: The array is what the EXIT/INT/TERM/HUP traps drain. A wholesale reset is only correct while exactly one checkout is ever live; the moment a second exists the reset drops a live registration+directory from the trap's view. The paired hole: iso_create appends to ISOLATION_BASES BEFORE seeding, so a set -e abort between the append and ISO_LAST_WT leaves the base registered but the caller sees failure and never destroys it — and the next wholesale reset then discards it, leaking both a directory and a git worktree registration past the EXIT trap. Fix is to remove the specific base rather than reset, and to make iso_create's failure path destroy what it registered.
  - Source: code review NB-3, suites-run-in-a-disposable-worktree, 2026-08-20; sites tests/skills/test-framework.sh:517,535 and iso_create's append at :278

- **`fu-iso-wrapper-traps-dont-reap-group`**: the wrapper's INT/TERM/HUP traps (.aai/scripts/aai-run-tests.sh) call aai_iso_cleanup and exit WITHOUT reaping the wrapped command's process group first
  - Measured: Ctrl-C therefore deletes the disposable checkout out from under a suite that is still running in it: the trap fires, worktree remove --force plus rm -rf take the tree away, the wrapper exits 130, and the orphaned suite keeps executing with its cwd unlinked — writing into a deleted directory, or worse resolving a relative path against whatever remains. The wrapper already knows how to reap a group (the setsid/pgid machinery below the traps); the traps just do not use it. Order must be kill the group, wait, then clean up.
  - Source: code review NB-4, suites-run-in-a-disposable-worktree, 2026-08-20; traps at .aai/scripts/aai-run-tests.sh:349-351

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `suites-run-in-a-disposable-worktree`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
