---
id: ride-status-and-resume
type: product
capability: ride-status-and-resume
status: current
delivered_by:
  - ride-status-and-resume
spec: docs/specs/SPEC-0264-spec-ride-status-and-resume.md
updated: 2026-10-31
---

# Where a ride stands, and picking it up again

## What it does

One command now answers where the current piece of work (a "ride") stands:
what is happening, what evidence exists, what blocks it and who acts next.
Before, that answer was spread over the state file, the event log, the loop's
tick lines and the agent's own prose. The same command has a second mode that
checks whether the ride's outside effects (the push, the pull request, the
close, the metrics record) already happened, so an interrupted ride does not
repeat them. A plain `/aai-ship` with no argument now continues the ride in
progress instead of starting a different one.

## How to use it

Status of the current ride:

```
node .aai/scripts/ride-status.mjs
```

prints six lines, for example:

```
ride: ride-status-and-resume (intake_change) spec=docs/specs/SPEC-0264-spec-ride-status-and-resume.md ceremony=2
current action: phase=code_review status=in_progress; dispatcher: dispatch rule 11 -> Validation
evidence: validation=not_run; review=not_run required=true; tdd=GREEN mutation_records=20; pr=none
blocker: none
next decision: loop: /aai-loop - dispatch of Validation by rule 11
decisions: strategy=tdd ref=ride-status-and-resume reused=true; worktree=recommended/worktree ref_binding=none
```

With no ride in focus the first line reads `ride: none (no current focus)`.
A damaged state file is reported as the blocker `state_invalid`.

Already-done check:

```
node .aai/scripts/ride-status.mjs probe
```

prints `pushed`, `pr_open`, `closed` and `flushed`, each `done`, `not_done`,
`unknown` or `skipped`, with the evidence it used (for example the open pull
request's number). Its last line, `resume:`, says how a
no-argument `/aai-ship` continues: `merge pr=<n>` (the ride is closed, pushed
and its pull request is open), `pr_step5 ref=<slug>` (the ride is closed but
its branch is not pushed at its head or has no pull request), `loop` (the ride
is still in progress) or `none` (no ride to resume, for example a fresh branch
or the base branch). One exception: when the pull request list cannot be read
and the closed ride's branch is already pushed, the line also says `none`,
so a no-argument `/aai-ship` moves on instead of stopping; run `probe` and
check `pr_open` before trusting it. Both modes take `--json`, `--state <path>` and
`--root <dir>`; `probe` also takes `--branch <name>`.

Where the agents use it:

- `/aai-ship` with no argument follows the `resume:` line. It continues a ride
  in progress; for a closed ride whose branch or pull request is not out yet
  it re-runs the pull request step from its first gate (validation, review and
  branch checks all run again); for a closed ride with its pull request open
  it stops and points to `/aai-merge <n>`. A damaged state file stops it with a
  pointer to `/aai-check-state`. With no ride to resume it picks the next
  roadmap item as before.
- The pull request step runs the check first: a branch already pushed at its
  head is not pushed again, and an open pull request is reported and watched
  instead of creating a second one.
- The autonomous loop prints the status lines after its summary.

## Data model

None. The command reads the existing state file, event log, metrics ledger and
decision ledger and writes nothing in either mode.

## Interfaces and contracts

- New read-only script `.aai/scripts/ride-status.mjs` (Node only, no shell
  launcher). Exit 0 when a report is printed, 2 on a usage error, 1 on an
  internal error.
- The current action and the next decision are taken from the dispatcher's own
  decision function, so the status cannot disagree with what the loop will do.
- The probe asks git and the platform adapter (`gh` on GitHub) read-only
  questions; it never pushes, creates, closes or flushes.
- Routine decisions survive a resume: a strategy recorded for the ride is
  reused (`reused=true`) and a recorded worktree decision is not asked again.
- Known limit: the worktree decision is not yet tied to the ride it was made
  for, so the status line prints `ref_binding=none`; tracked as follow-up
  `fu-worktree-decision-not-ref-bound`.
- `/aai-ship`, the pull request step and the loop prompts changed as listed
  above; no decision rule of the dispatcher changed.
