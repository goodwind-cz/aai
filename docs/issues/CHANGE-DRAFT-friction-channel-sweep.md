---
id: friction-channel-sweep
type: change
number: null
status: draft
capability: friction-channel-sweep
links:
  pr: []
  commits: []
---

# The friction channel files what happened, with the harness, in one shape

## Summary
- Wave 3, sweep 6 (`docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md`).
  Paired maintenance half: `hand-authored-friction-is-second-class` (CHANGE-0172).
- The channel the owner reads (`aai-friction.mjs` record, `aai-feedback-triage.mjs`,
  `aai-feedback-upsert.mjs`, the GitHub issues they file, `learned-append.mjs`)
  has three open shapes: a hand-authored observation cannot carry a score or
  prose and never reaches upsert (CHANGE-0172); a filed issue arrives with a
  failure class and no description (CHANGE-0179, half-settled by the
  reporter's own words in #371); a summary over the length cap is dropped
  fail-closed while `record` prints success (GitHub #361). Plus the residuals
  of PR #373: `existingLabels` discards the gh exit status, the dedup
  parse-failure refusal prints `(exit 0)`, the repository has no
  `aai-friction` label so filed issues ship unlabelled, and `learned-append`
  drifts from the LEARNED.md style.

## Motivation / Business Value
- This is the only channel by which a downstream project's pain reaches
  this repository without the owner copying text by hand. Every silent drop
  or prose-free issue is a defect the factory never hears about.

## Scope
- In scope, fixed with a test each: CHANGE-0172, CHANGE-0179 (the analysis
  comment the publish flow already prints is filed by the flow itself when
  the record carries prose), GitHub #361, `fu-existinglabels-discards-status`,
  `fu-upsert-refusal-prints-exit-zero`, `fu-friction-label-missing-in-destination`
  (the label is created on first use, disclosed), `fu-learned-append-style-drift`,
  `fu-learned-ledger-merge-procedure`, `fu-triage-undated-learned-log`,
  and `harness` on every observation (sweep 1 adds the field; this ride
  makes triage and upsert show it).
- Out of scope: the GitHub API surface beyond issues and labels; Azure.

## Affected Area
- `.aai/scripts/aai-friction.mjs`, `aai-feedback-triage.mjs`,
  `aai-feedback-upsert.mjs`, `learned-append.mjs`, `.aai/FRICTION_PROTOCOL.md`,
  `docs/knowledge/LEARNED.md` (the undated entries), the suites for each.

## Desired Behavior (To-Be)
- A hand-authored observation is a first-class record: scored, with prose,
  reaching upsert like a captured one.
- An issue filed by the channel carries a description, the harness, and the
  label; a refusal is a refusal on stdout and on the exit code.

## Notes
- Bucket on 2026-09-13: 6 open follow-ups plus the two intakes and one
  issue; the spec freezes the list.
- Ceremony 2, TDD; inline (no dispatcher or framework edits).
