---
id: token-capture-canary
number: 58
type: change
status: done
links:
  pr:
    - 158
  commits:
    - b2d8041ed1da2dfe50ec0c71cab870f966552f37
---

# Change — Token-Capture Canary (make silent telemetry-capture gaps loud)

## Summary
- Make the three silent telemetry-capture failure modes loud and
  distinguishable: (1) metrics-flush cannot tell an honest null (undecomposed
  harness total recorded in the run note, cost unattributable by design) from
  a capture miss (no numeric tokens AND no usage note); (2) state.mjs
  log-tick silently accepts a bogus start time (duration_seconds collapses to
  0) and a missing --harness (harness_version "unknown"); (3) the
  SUBAGENT_PROTOCOL merge step leaves the usage_total_tokens note optional in
  practice, so most runs record no usage signal at all.

## Motivation / Business Value
- METRICS.jsonl carries 0 non-null tokens_in/tokens_out across 255 agent-run
  records; only 28 runs recorded the real harness total via the
  usage_total_tokens note grammar (SPEC-0043 D3). The remaining runs observed
  a real number and silently dropped it — so the cost of every role, and the
  payoff of model tiering (SPEC-0018) and MODEL_ROUTING, is unmeasurable.
- All 2026-07-25 loop ticks logged duration_seconds 0 and harness_version
  "unknown" (callers passed --started at log time and omitted --harness),
  versus the healthy 2026-07-19 tick (1157 s, "2.1.211 (Claude Code)").
  Time-per-role is currently the only real cost signal and it regressed
  silently.
- SPEC-0043 was deliberately prompt-only (zero-diff on state.mjs and
  metrics-flush.mjs) with residual risk R1: "tests pin the text, not the
  behavior." This change adds the mechanical teeth R1 anticipated.

## Scope
- In scope:
  - .aai/scripts/metrics-flush.mjs: per-run capture classification
    (decomposed | undecomposed-note | capture-missing) and distinct
    diagnostics (INFO for honest undecomposed totals, WARNING for
    capture-missing).
  - .aai/scripts/state.mjs cmdLogTick: post-write stderr WARNING when
    started == ended (duration 0) and when --harness is omitted, mirroring
    the existing append-run warn-on-null-tokens teeth.
  - .aai/SUBAGENT_PROTOCOL.md merge protocol + .aai/SKILL_LOOP.prompt.md
    step 4/6: make the usage_total_tokens=<N> note MANDATORY on every
    subagent completion whose harness result reported a total; reinforce
    passing the step-4 role_started_utc and the loop-start harness_version.
  - Tests for the new diagnostics in the affected suites.
- Out of scope:
  - Any estimation, splitting, or fabrication of token counts (D3/D4
    prohibitions stay byte-for-byte).
  - New METRICS.jsonl or LOOP_TICKS.jsonl schema fields.
  - Decomposed-usage capture for runtimes that do not expose it.

## Affected Area
- Telemetry pipeline: .aai/scripts/metrics-flush.mjs, .aai/scripts/state.mjs
  (log-tick only), .aai/SUBAGENT_PROTOCOL.md, .aai/SKILL_LOOP.prompt.md,
  tests/skills (metrics + state/token-capture suites).

## Desired Behavior (To-Be)
- A flush over runs that observed a harness total but stored neither numeric
  tokens nor a usage note prints a WARNING naming each capture-missing run;
  runs with the note print an INFO line ("undecomposed total N observed;
  cost unattributable by design") instead of the generic alarming warning.
- log-tick writing a tick whose duration computes to 0 or whose --harness is
  absent emits a loud stderr WARNING (the write still succeeds — warn, not
  block, matching existing teeth).
- The merge protocol makes the usage note non-optional whenever a total is
  visible, so "no usage signal" can only mean "harness exposed nothing".

## Acceptance Criteria
- AC-001: metrics-flush classifies every agent_run into exactly one of
  decomposed | undecomposed-note | capture-missing, and emits one WARNING
  line per capture-missing run and one INFO line per undecomposed-note run;
  verified by test fixtures covering all three classes.
- AC-002: state.mjs log-tick emits a stderr WARNING containing
  "duration" when started == ended and a stderr WARNING containing
  "harness" when --harness is omitted; exit code stays 0 and the tick line
  is still appended (fixture-verified both ways).
- AC-003: SUBAGENT_PROTOCOL.md "Merge protocol" and SKILL_LOOP.prompt.md
  step 4 contain the MANDATORY usage-note wording (greppable literal
  "usage_total_tokens"), and the prompt-diet ledger is trued-up for any
  corpus byte growth.
- AC-004: no existing suite regresses: the full skill test framework passes
  after the change.

## Verification
- bash tests/skills/test-aai-metrics.sh (new capture-classification stanzas)
- bash tests/skills/test-aai-state.sh or the token-capture suite (log-tick
  warning stanzas)
- bash tests/skills/test-framework.sh (AC-004, full run)

## Constraints / Risks
- No secrets referenced (secrets preflight skipped).
- Warn-not-block discipline: neither new diagnostic may fail a flush or a
  tick write — visibility only, no new gate (degrade-and-report principle).
- Prompt edits touch the byte-budgeted corpus: prompt-diet ledger true-up +
  TEST-012 pinned-total bump + PROFILES are companion obligations.
- state.mjs and the guards are protected surfaces (WORKFLOW.md L3 list):
  the spec must declare ceremony_level 3 and the worktree/review gates that
  come with it.

## Notes
- Root-cause evidence and file:line index: independent-audit session report
  (docs/project-sessions/2026-07-26-independent-audit-autonomy-pack.md,
  roadmap item 1) and the 2026-07-26 read-only trace: SPEC-0043 sections
  37-39/57-66/82-84/168-181/276-278; state.mjs 191-194, 700-805, 864-921;
  SUBAGENT_PROTOCOL.md 132-154, 197-206; SKILL_LOOP.prompt.md 114-117, 250,
  267, 320-338; metrics-flush.mjs 416-422.
- Autopilot intake (/aai-ship): metrics question skipped, human_time_minutes
  intake recorded as null.
