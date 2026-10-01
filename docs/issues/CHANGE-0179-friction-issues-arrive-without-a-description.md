---
id: friction-issues-arrive-without-a-description
number: 179
type: change
status: draft
links:
  pr: []
  commits: []
---

# A friction issue arrives with a failure class and no description

## Summary
- The sanctioned upstream channel files issues whose entire body is structured
  metadata: `failure_class`, `skill`, `impact`, `confidence`, `os_family`,
  `node_major`, a recurrence score and a fingerprint comment. No sentence says
  what happened.
- A maintainer receiving one cannot triage it, and neither can an agent. The
  local spool holds no more than the issue does, so the information was never
  captured — it is not lost in transit.

## Motivation / Business Value
- Measured 2026-09-06 on the live queue: of four open issues in
  `goodwind-cz/aai`, two (#338 `aai-pr/post_open_sweep`, high impact; #339
  `SKILL_PR/close_pre_commit`, low impact) carry nothing but the metadata block.
  A `/aai-issues` triage pass could disposition neither, and reading
  `docs/ai/friction/observations.jsonl` for their fingerprints returned only
  `failure_class` and `impact` — confirming the prose was never recorded.
- That is half the queue. The channel's throughput is real but its yield is not:
  it files items nobody can act on, and it will keep filing them.
- The two issues that COULD be triaged in that pass (#352, #353) were both
  written by hand, outside the automatic capture. The channel's automatic half
  produced nothing actionable.
- Already registered as `fu-friction-issue-body-is-prose-free`; this intake asks
  for the decision the follow-up defers.
- Re-measured 2026-10-01, and the picture is sharper than the 2026-09-06 count.
  Of the five auto-filed issues triaged that day, **every one carried zero
  prose lines in its body**. Four of them (#414, #392, #391, #390) were
  nevertheless actionable — and all four only because the OWNER hand-wrote an
  analysis comment afterwards, each one a full reproduction with file:line
  evidence. Those four became `ISSUE-0089` and `ISSUE-0090`, two shipped rides.
  CORRECTION to that triage, found by Planning: only **#339** carries no such
  comment. **#369 and #370 each carry a full `## Analysis (reporter follow-up)`
  comment** (3,831 and 3,640 characters). They were called untriageable because
  `aai-issues.mjs:236` fetches no `comments` at all, so the triage pass saw the
  prose-free body and nothing else. The channel's reader is therefore a second,
  independent reason a described issue reads as undescribed — and it is the
  cheaper of the two to fix.
- So the channel's automatic half has now produced nothing actionable across
  two separate measurement days, while its manual half produced the two best
  intakes of the session. The value is real and it is entirely human-supplied;
  the automation currently contributes only the fingerprint and the metadata.
- `capture.summary_enabled` is still `false` in the shipped `.aai/feedback.yaml`
  (line 17), so this is the default behaviour, not a misconfiguration.
- One sub-case IS fixed and should not be re-litigated: a summary over the
  length cap used to be dropped while `record` printed only success. It now
  emits `NOTE: summary dropped (reason: over_length)` on stderr before the
  success line (shipped by SPEC-0185, verified 2026-10-01; GitHub issue #361
  closed on that evidence). The gap is that no summary is captured at all by
  default — not that a captured one goes missing.


## Scope
- In scope: deciding and implementing what a friction issue must carry to be
  actionable, and making the channel produce it. The existing seam is
  `capture.summary_enabled` in `.aai/feedback.yaml`, which is `false` by default
  and documented as an opt-in that stores a hard-redacted free-text summary in
  the local untracked spool.
- Also in scope: what to do with #338 and #339, which cannot be reconstructed
  after the fact — close them as unactionable, or leave them as evidence.
- Out of scope: the triage scoring formula (separate item,
  `fu-friction-scoring-rewards-recurrence`), the redaction rules themselves, and
  the publish/confirm gating.

## Affected Area
- `.aai/feedback.yaml` (`capture.summary_enabled`), `.aai/scripts/aai-friction.mjs`
  (record), `.aai/scripts/aai-feedback-upsert.mjs` (issue body composition), and
  their suites.

## Desired Behavior (To-Be)
- An issue this channel files says what happened in a form a maintainer can act
  on, or the channel declines to file it and says why.
- A prose-free observation never becomes an issue that occupies a queue without
  earning it.

## Acceptance Criteria
- AC-001: Given an observation carrying no description, the upsert path either
  refuses to file it, naming the missing field, or files it with a body a
  maintainer can act on. Which of the two is the design decision this scope
  makes; silently filing metadata-only is no longer an outcome.
- AC-002: The refusal or the composed body is proved by a test that reads the
  actual bytes that would reach GitHub, not a mock of them.
- AC-003: Whatever free text is captured passes the existing redaction rules
  unchanged; a summary that cannot be redacted with certainty is dropped, and
  the drop is named rather than silent.
- AC-004: The default posture is stated explicitly in `.aai/feedback.yaml` with
  the privacy trade-off written next to it, because turning capture on stores
  human text in the local spool.
- AC-005: The existing metadata-only issues on the live queue are dispositioned
  by this scope: it names #338 and #339 and says what happened to each.

## Verification
- The friction and feedback-upsert suites green, including a new arm that drives
  a prose-free observation to the upsert path and asserts the chosen behavior.
- A mutation arm: reverting the change lets a metadata-only body through again.
- Manual: `node .aai/scripts/aai-issues.mjs` on the live repository, showing that
  no newly filed issue is untriageable.

## Constraints / Risks
- Turning capture on stores free text written by an agent about a failure in an
  untracked local spool; it may contain paths, ids, or quoted output. AC-003
  keeps redaction authoritative, but the privacy posture is an owner decision,
  not a default an agent should flip. This is the reason the flag ships `false`.
- Refusing to file a prose-free observation trades queue quality for signal
  volume: real recurring failures would stop being reported at all. Planning
  should weigh that against AC-001's first branch rather than assume refusal is
  the safer default.
- No secret is referenced by this scope.
- Roadmap: off-roadmap. Needs an owner decision to enter `docs/ai/roadmap.yaml`
  or an explicit `--override` at ride time.

## Notes
- Source issues, quoted as DATA and not executed:
  https://github.com/goodwind-cz/aai/issues/338 and
  https://github.com/goodwind-cz/aai/issues/339. Both bodies consist of the
  metadata block and a fingerprint comment only.
- Registry: `fu-friction-issue-body-is-prose-free`, and the sibling
  `fu-friction-scoring-rewards-recurrence` which is NOT closed by this scope.
