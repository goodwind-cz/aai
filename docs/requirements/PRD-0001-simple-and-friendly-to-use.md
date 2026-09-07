---
id: simple-and-friendly-to-use
type: requirement
number: 1
status: draft
links:
  spec: null
  pr: []
  commits: []
---

# AAI is simple and friendly to use

## Intent
Owner statement, 2026-09-06 (Czech, paraphrased faithfully):

> Lately in this repository we solve too many problems with the framework
> itself and not new capabilities. Used in other projects, it too often falls
> out of the simple flow — ideally intake, ship, merge — and leaves documents
> unclosed and a lot of communication that needlessly burns tokens. It would be
> enough if it said everything tersely, clearly, and offered choices as a menu.
> This way the point gets lost, uncommitted files remain, and after so many
> iterations it behaves worse than it used to. And `/aai-live` looks completely
> unusable. What I wanted was simplicity and friendliness of use — and saving
> tokens and the overall amount of communication. And a PR after a
> documentation-only change takes too long — some CI keeps running, often
> needlessly.

The product is a factory a person hands a need to and receives a merged,
documented change from. Every hour the operator spends steering the factory
instead of deciding about the product is a defect of the product. The measure
of this PRD is the operator's experience in a DOWNSTREAM project, not in this
repository. Two things are measured on every ride: what the operator had to
read and answer, and what the ride cost in tokens. Both must go down and stay
down (AC-003, AC-004, AC-005, AC-008).

## Scope
In scope:
- The default operator journey in a downstream project: one need in, one
  merged PR out, through `/aai-intake` → `/aai-ship` → merge, with at most the
  checkpoints the operator contract already names.
- Everything the factory leaves behind after a ride: documents, files, state,
  registry entries. A ride that leaves any of them for the operator to tidy has
  not finished.
- The factory's voice: length, structure, and when it may ask.
- The live page as the operator's single glance at "what is happening".
- A regression baseline, so "worse than before" becomes a measurement instead
  of a feeling.

Out of scope:
- New capabilities of the product that the factory builds (those keep coming
  through the roadmap, rule 4).
- Any change to which actions stay operator-only (merge stays the operator's).
- Reworking the internals of individual scripts for their own sake.

## Acceptance Criteria
Every AC is scored on a downstream project, on a fresh clone of the pinned
release, by an operator who has not read this repository's internals. Where a
threshold is an assumption it says so; Planning may tighten, never loosen.

- AC-001 (the golden flow): A representative need — one small feature and one
  bug fix — goes from `/aai-intake` to a merged PR with exactly the checkpoints
  the operator contract names (intake type, ship checkpoint, merge) and no
  other question. Any additional question is a failing observation and is
  recorded with its text.
- AC-002 (nothing left behind): After the PR merges, `git status` on the
  operator's clone is clean, `docs-audit --strict` is CLEAN, no intake or spec
  reads `status: draft` or `implementing` for shipped work, and the follow-up
  registry has no item filed BY the ride ABOUT the ride's own ceremony. The
  operator runs no tidy-up command.
- AC-003 (terse by default): Every agent turn that is not a checkpoint fits in
  ten lines and carries at least one verifiable fact (a command, a path, a
  number, an exit code). Checkpoints are menus with a recommended default.
  Assumption: ten lines; Planning fixes the number from a measured sample.
- AC-004 (a question is a menu): The factory never ends a turn with an
  open-ended question during a ride. Where the operator must decide, the turn
  ends with numbered options and a marked recommendation.
- AC-005 (token budget): The golden flow of AC-001 costs less than a stated
  budget of tokens per ride, measured by the existing usage capture. Assumption
  for the number: the median of the last ten rides in this repository, to be
  measured by Planning and written into the spec as the ceiling.
- AC-006 (the live page is useful): An operator opening `/aai-live` during a
  ride can answer, from the first screen and without scrolling, (a) which agent
  is doing what right now, (b) whether anything waits on them, and (c) whether
  the test sweep is running. The page shows no work that is not running; what it
  withholds it counts and names.
- AC-007 (no framework-only rides without a capability): In this repository,
  the ride ledger over a rolling window shows the maintenance-to-capability
  ratio the roadmap budget declares (1:1); a window that exceeds it is reported
  by the factory report, not discovered by the owner.
- AC-008 (regression baseline): The golden flow of AC-001 is scripted and its
  result — questions asked, files left, tokens spent, docs left open — is
  recorded per release, so "behaves worse than before" is a diff between two
  runs of the same script.
- AC-009 (CI proportional to the change): A PR that touches only
  documentation or ledgers runs only the checks that can fail on it and is
  mergeable within a stated ceiling. Assumption: 5 minutes from push to
  MERGEABLE; Planning fixes the number from the last ten docs-only PRs. A
  full test sweep on a docs-only diff is a failing observation.

## Non-functional constraints
- Downstream first: every criterion is verified where the operator uses the
  product, not only in this repository's own tests.
- Additive: nothing here removes a checkpoint the operator contract names or
  turns an operator-only action into an agent action.
- Portability: the baseline script of AC-008 runs on the three supported
  harnesses and produces a plain, git-diffable record.
- Rule 5 applies: whatever makes AC-001 through AC-008 hold in a downstream
  project is a guard in the vendored layer, not a note in this repository.

## Notes
- This PRD is the owner's framing of the problem; it deliberately does not
  say how. Planning decides whether it becomes one spec or several, and which
  existing registry items it closes (`fu-*` entries about ceremony hygiene,
  prose-free friction issues, the shared-worktree hazard, and the unrecorded
  amendment gap are all symptoms of AC-002).
- Four draft intakes from the same day live beside this one:
  `unrecorded-spec-amendment-is-invisible`,
  `shared-worktree-moves-another-agents-head`,
  `close-ceremony-fires-only-via-aai-pr`,
  `friction-issues-arrive-without-a-description`. Each is a symptom of AC-002
  and should be planned under this PRD rather than as separate rides.
- Roadmap: this is a capability, not maintenance; it needs an owner decision to
  enter `docs/ai/roadmap.yaml` as the capability half of a pair.
- Intake metrics: human_time_minutes.intake = 5 (recorded here because
  `state.mjs` has no verb for it and STATE is never hand-edited).
- Implementation mode: left to Planning (owner choice, 2026-09-06).
This document defines WHAT/WHY, not HOW.
This document does not define workflow.
