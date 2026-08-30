---
id: cli-exit-truncates-pipe-sweep
type: issue
number: 49
status: draft
---

# P2 backlog cluster: cli-output-survives-a-pipe (4 items)

## Summary
- Consolidated registry intake for 4 open P2 follow-up(s) filed against `cli-output-survives-a-pipe`: `fu-cli-exit-truncates-pipe-sweep`, `fu-orchestrator-mutated-real-file`, `fu-test021c-precondition-unasserted`, `fu-main-push-conflicts-open-pr`. Filed via batch intake (owner directive: intake all P2 clusters first, ship the highest-value ones next).

## Type
- bug

## Current Behavior
- **`fu-cli-exit-truncates-pipe-sweep`**: 41 of the .aai/scripts/*.mjs CLIs still print with console.log and then call process.exit, the exact shape that truncated follow-ups.mjs list --json at 65536 bytes on a pipe; docs-audit.mjs (23 logs), test-canon.mjs (28), docs-canon.mjs (23) and metrics-flush.mjs (15) are the largest payloads
  - Measured: cli-output-survives-a-pipe deliberately fixed ONE file; a repo-wide sweep needs its own scope, its own per-CLI exit-code proof and its own regression pins, and doing it inside that ride would have made the diff unreviewable
  - Source: docs/specs/SPEC-0139-spec-cli-output-survives-a-pipe.md D7

- **`fu-orchestrator-mutated-real-file`**: the orchestrator ran a bite-proof mutation against the tracked suite file instead of a copy, and the first restore attempt silently failed on a mis-anchored sed pattern
  - Measured: every role dispatch this week forbids exactly this, and the near-miss was shipping a test with a shrunken fixture that cannot fail, inside a ride about assertions that cannot fail; the restore also had no verification step until one was added by hand afterwards
  - Source: 2026-08-21 03:35Z; mutation applied to tests/skills/test-aai-follow-ups.sh in place, detected by git diff --stat, reversed and re-verified (396 insertions 0 deletions, suite green, no t022big 5 artefact)

- **`fu-test021c-precondition-unasserted`**: TEST-021(c) never asserts its own precondition that the reader is gone before the write, so the arm reaches the same observable with the guard removed and an open reader
  - Measured: measured 10 of 10 both ways, so the arm can go green without ever invoking installPipeGuard; it is the only arm holding the load-bearing half of the EPIPE guard, and it does not hold it
  - Source: code review NB-1, cli-output-survives-a-pipe, 2026-08-21

- **`fu-main-push-conflicts-open-pr`**: the orchestrator pushed a commit to main that regenerated docs/INDEX.md while a PR shipping the same generated file was open, turning that PR CONFLICTING
  - Measured: fourth instance in two days of writing to a tree something else depends on (parallel roles, a merge mid-framework-run, a commit mid-run, now a push mid-PR); each cost a rerun, and the shared generated files docs/INDEX.md, overview.* and factory-report.* make it near-certain whenever a doc lands on main during an open PR
  - Source: 2026-08-21 04:28Z; PR 268 went CONFLICTING after main commit 8980a07, resolved by merging main into the branch and regenerating the index

## Expected Behavior
- Each item's own Expected Behavior is scoped at Planning/implementation time from the measured decision text above — this intake's job is to make the cluster a numbered, trackable work item, not to pre-design the fix.

## Notes
- Registry ref: `cli-output-survives-a-pipe`. This intake may close some, all, or none of the member `fu-*` ids depending on what Planning finds still applies when work starts — do not assume every listed item survives triage unchanged (two sibling items in this same backlog were found already-fixed-but-not-closed today; check before implementing).
