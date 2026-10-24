---
id: cheap-transitions-slice
type: change
number: null
status: draft
capability: lean-agent-context
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Cheap transitions: stop paying a full role context for routine re-checks

## Summary
- RFC-0017 phase 4, first remaining slice (proposal section 4): routine
  transitions and re-checks should not each start a model context of the full
  role size. Code decides what it can; the model keeps design, implementation,
  ambiguous analysis and independent judgment.
- One bounded mechanism, chosen by measured evidence, ships in this slice with
  a measured before/after.
- The ride also signs the owner-directed merge of PR #497.

## Motivation / Business Value
- The third phase 3 ride (node-first-third-slice, PR #497) ran 5 code review
  and 5 validation rounds after Planning, plus 5 remediation rounds. Late rounds
  re-checked deltas of tests, spec text and one ledger line, yet each started a
  fresh role context of the same size as round 1 (about 30 to 45 KB of prompt
  plus re-reading the scope).
- The time and token cost of a ride is dominated by these repeated contexts,
  not by the first implementation.

## Scope
- In scope:
  - Planning measures where repeated role contexts go across recent rides
    (METRICS.jsonl runs per ride and role, tokens, durations; the review and
    validation reports of the last rides) and picks ONE mechanism. Candidates:
    - a delta re-check mode: when a remediation changes no production path,
      the re-review or re-validation gets a slim payload (the delta, the prior
      report, the open findings) instead of the full role prompt and scope;
    - deterministic triage of review findings: code classifies a finding as
      text-only, test-only or production, and routes text-only fixes to the
      remediator plus an automated check instead of a new review round;
    - a structured, machine-readable verdict and finding format that dispatch
      reads, so the next transition is decided by code instead of by the
      orchestrator reading prose;
    - another mechanism the evidence shows is larger.
  - The chosen mechanism extends the existing paths (canon.mjs, orchestration
    dispatch, the L0/L1 lanes, state.mjs); no competing workflow.
  - A before/after measurement on comparable work: prompt bytes per dispatch
    and, where the harness exposes them, tokens per round; recorded in the
    spec and the RFC phase 4 row.
  - Sign the owner-directed merge of PR #497 (merged 2026-10-24): the unsigned
    contract amendments on spec-node-first-third-slice are signed and
    `fu-amend-spec-node-first-third-slice` closes.
- Out of scope:
  - Weakening an independent check. Protected state, destructive actions,
    security guards and public contracts keep an independent model review;
    a security-relevant finding is never downgraded to an automated check.
  - Generated provider adapters and token telemetry plumbing (later phase 4
    slices).
  - Rewriting STATE storage or the append-only ledgers.

## Affected Area
- `.aai/scripts/canon.mjs`, `.aai/scripts/orchestration-dispatch.mjs`,
  `.aai/scripts/state.mjs` and the role prompts it composes, as the chosen
  mechanism needs
- Their tests under `tests/skills/`
- docs/rfc/RFC-0017 phase 4 row; the workflow or product doc that describes
  the dispatched rounds

## Desired Behavior (To-Be)
- A routine re-check costs measurably less model context than a first-round
  check, with the same independence guarantees where they matter.

## Acceptance Criteria
- AC-001: Planning records the measured cost of repeated role contexts across
  at least three recent rides and justifies the chosen mechanism against the
  other candidates.
- AC-002: The mechanism is implemented by extending existing scripts, with
  tests for when it applies and, explicitly, for when it must NOT apply
  (production change, security-relevant finding, protected path).
- AC-003: A before/after measurement on comparable dispatches shows a lower
  prompt size (and token count where available), recorded in the spec and the
  RFC phase 4 row.
- AC-004: No independent check required today for protected state, security or
  public contracts is skipped or downgraded (a test proves the refusal paths).
- AC-005: The RFC-0017 phase 4 row records this slice and stays `in progress`.
- AC-006: The #497 amendments are signed with the owner's merge as the source,
  and `fu-amend-spec-node-first-third-slice` is closed.

## Verification
- The changed scripts' suites pass (rc 0), including the refusal-path tests.
- The before/after numbers are reproducible from a recorded command.

## Constraints / Risks
- The workflow is self-hosting: a change to dispatch or canon changes how this
  very ride is reviewed. Planning states how the ride itself is validated
  (the new mechanism must not judge its own delivery).
- Changing role prompts touches the prompt-corpus governance (diet ledger,
  TEST-012 counts, PROFILES classification; ORCHESTRATION capped at 40 lines).
- Consumer-visible (downstream installs dispatch differently): merge needs the
  owner's menu.
- No secrets referenced.

## Notes
- Source: RFC-0017 proposal section 4 and phase 4 row; owner chat answer
  2026-10-24 "ano" to starting phase 4 with cheap transitions.
- Assumption (autopilot default): Planning chooses the mechanism; the owner is
  asked only if the evidence is evenly split or the choice weakens a check.
