---
id: factory-round-cap
type: change
number: 255
status: done
capability: factory-round-cap
links:
  pr: []
  commits: []
---

# Change: a ride's re-check loop stops at its round cap and pays the full sweep once

## Summary
- Make the existing two-round review cap (owner decision `review-round-cap`,
  2026-09-05, AGENTS.md operator contract rule 3, VALIDATION.prompt.md c2) a
  counted, enforced limit instead of prose, and make "a remediation round only
  for a BLOCKING finding backed by a failing check or a reproduction" a checked
  rule.
- Make "the full skills sweep runs once per ride" checkable: intermediate rounds
  run selected + CORE suites; a later round reuses the ride's green full sweep
  when everything changed since it is test or text only.

## Motivation / Business Value
- Owner priority (2026-11-12): visible speed and efficiency gains in AAI,
  deployable through a release.
- Evidence, ride 8 `install-path-parity-harness` (PR #546), from its six
  validation and three review reports:
  - 6 validation rounds and 3 code review rounds; the owner counts 7
    remediation rounds.
  - The full sweep (about 55 min each: 56 min in r1, 54 min in r4) ran three
    times (r1, r3, r4).
  - Validation r5 and r6 were PASS rounds re-run only because NON-BLOCKING
    findings were folded into the ride after a PASS (standing decision (b)
    forced re-validation).
  - Several rounds were driven by CI-only discoveries on Windows.
- Evidence, `update-ps1-git-stderr` (PR #547): 2 validation rounds, 1 review;
  the r1 FAIL was a full-sweep round.
- Neither ride left `check_dispatched` / `check_verdict` EVENTS lines or METRICS
  agent runs, so a counter that lives only in the dispatcher's telemetry would
  not have seen these rides. The one path both rides used is `state.mjs`
  (set-validation, reset-block).
- External evidence (scratchpad research-agentic-efficiency-2026-11.md, A1 and
  A5): impact-based test selection for inner rounds with the long sweep kept for
  pre-close (TDAD, arXiv 2603.17973); allow a further round only for a BLOCKING
  finding with a failing deterministic check; route NON-BLOCKING findings to
  follow-ups and never re-run a full sweep for them (Cognition 2026-04-22;
  arXiv 2606.18168).

## Scope
- In scope:
  1. Round cap with a blocking bar.
     - A deterministic per-ride round counter, recorded where every
       remediation path passes (the `state.mjs reset-block` transition).
     - Dispatch stops at the cap with an owner menu instead of dispatching
       Remediation.
     - Standing decision (a) (one extra round for a hazard introduced by the
       feature) recorded as a checkable extension.
     - A FAIL verdict must cite at least one BLOCKING finding backed by a
       failing check or a reproduction.
     - NON-BLOCKING findings go to follow-ups by default; folding one in after
       a PASS is a counted round.
  2. Full sweep once.
     - A deterministic sweep plan per ride (full or reuse) from the last green
       recorded full sweep and the delta since it.
     - Validation records the full sweep it ran.
     - A Validation PASS needs a reusable green sweep at its head.
     - The canon text (VALIDATION c2, SKILL_VERIFY reuse exception and its
       rationalization table, REMEDIATION, SKILL_CODE_REVIEW, AGENTS rule 3) is
       made consistent with both rules.
  3. Measurement: a deterministic replay of ride 8's round history against the
     new rules, plus per-ride rounds and sweep counts readable from EVENTS for
     every later ride.
- Out of scope: model or effort routing, Haiku verification passes, prompt
  caching, CI workflow changes, changing the cap value (2) or standing
  decisions (a) and (b) themselves.

## Affected Area
- `.aai/scripts/state.mjs` (reset-block), `.aai/scripts/orchestration-dispatch.mjs`
  (rules 10 and 12), `.aai/scripts/append-event.mjs` (new event types),
  `.aai/scripts/check-role-output.mjs` (FAIL and PASS postconditions), a new
  round and sweep counter script under `.aai/scripts/`.
- Canon prompts: VALIDATION, REMEDIATION, SKILL_CODE_REVIEW, SKILL_VERIFY,
  ORCHESTRATION (one line, within its line ceiling), AGENTS.md rule 3.

## Desired Behavior (To-Be)
- The third remediation round of a ride is never dispatched silently. Dispatch
  reports `review_round_cap` and sets a human-input menu: split the ride
  (recommended), one more round (recorded owner extension), or park. A hand-run
  `reset-block` refuses the same way.
- With standing decision (a) recorded once for the ride, the cap is 3. A second
  (a) extension on the same ride is refused.
- A Validation or Code Review FAIL that cites no backed BLOCKING finding is
  rejected by the role-output check. NON-BLOCKING findings become follow-ups.
- The full sweep runs at most once per ride unless something other than tests
  or text changed since the last green sweep, or that sweep was red.

## Acceptance Criteria
- AC-001: dispatch on a ride with two recorded remediation rounds and a fresh
  FAIL returns `review_round_cap` (no Remediation dispatch) and a menu-shaped
  human-input command.
- AC-002: `state.mjs reset-block` refuses the third round's reset with a
  named message and writes nothing. It accepts that reset after one recorded
  extension.
- AC-003: a Validation or Code Review FAIL result block with no backed BLOCKING
  blocker is rejected by `check-role-output.mjs`.
- AC-004: the sweep plan answers `reuse` for a test or text-only delta since a
  green recorded sweep, and `full` for a code delta, a red sweep or no sweep.
- AC-005: a replay of ride 8's round history under the new rules yields at most
  2 automatic remediation rounds (3 with the (a) extension) before the owner
  menu, and exactly 1 full sweep, against the recorded 7 rounds and 3 sweeps.
- AC-006: the canon prompts state one consistent rule each for the cap, the
  blocking bar and the sweep scope, with no contradicting sentence left
  (SKILL_VERIFY "run the whole suite" row).

## Verification
- Command(s) and expected results: the new suite and the existing suites
  `aai-state`, `aai-orchestration-dispatch`, `aai-role-output`, `aai-canon`,
  `aai-prompt-diet` exit 0. The ride's single full sweep is green.

## Constraints / Risks
- `state.mjs` is an L3 protected surface; ceremony is L3.
- A load-only failure of a ride's own suite (ride 8 r3 found one) is no longer
  caught by a re-run sweep after a test-only delta. CI and the one sweep remain.
- Downstream projects have no `tests/skills/test-framework.sh`. The sweep plan
  must degrade to a named not-applicable answer there, never a refusal.
- Prompt corpus growth needs a prompt-diet ledger entry and pin bumps.

## Notes
- Implementation mode (autopilot): Planning decides.
- Assumption: "unless a selected suite failed" means a red recorded sweep or a
  red selected run voids reuse. A round with a red selected suite is a FAIL and
  pays no sweep.
- Secrets preflight: no secret referenced.
