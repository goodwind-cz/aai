---
id: spec-implementation-mode-choice
type: spec
number: 109
status: done
ceremony_level: 3
links:
  requirement: docs/issues/CHANGE-0100-implementation-mode-choice.md
  rfc: null
  pr:
    - 203
  commits:
    - 89dc08a24e668b0fd9b8685cfb51269e0043cd8b
---

# Implementation Spec — implementation-mode-choice

SPEC-FROZEN: true

## Ceremony level (RFC-0009)

`ceremony_level: 3` — MANDATORY, not discretionary. The scope edits
`.aai/scripts/state.mjs`, listed verbatim in `protected_paths_l3`
(docs/ai/docs-audit.yaml) and in the WORKFLOW.md "Protected surfaces" list
(state engine). A scope that touches a protected surface MUST declare level 3 —
same basis as the precedent SPEC-0107 (CHANGE-0097, allocator). L3 consequences
carried:

- Worktree gate (rule 8): REQUIRED semantics — work is on the dedicated isolated
  worktree branch off main; the operator's run-level authorization is the
  recorded decision.
- Code review (rule 13): MANDATORY on the most capable tier. No auto-waiver.
- PR ceremony: adds an OPERATOR CHECKPOINT before merge (explicit final-diff
  sign-off; the orchestrator owns operator sign-off at PR time).
- Evidence-before-claims and full independent validation are NOT pruned; L3
  scales artifact weight and review, never the evidence bar.

## Links
- Requirement / intake: docs/issues/CHANGE-0100-implementation-mode-choice.md
- Precedent (L3 protected-surface spec, context only): docs/specs/SPEC-0107-spec-allocator-header-rewrite.md
- Prior strategy/dispatch specs (context, not modified): SPEC-0012 (state CLI),
  SPEC-0041 (loop ceremony-aware dispatch)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded

## Problem

After a full intake AAI silently routes to Planning's strategy pick, which for
small changes tends to be the full TDD loop (~3-5% of a weekly token limit for a
comparable small change). The owner has to manually intervene each time and steer
to direct implementation. AAI also writes tests even for tuning/run scripts unless
explicitly told not to. There is no user-facing choice of implementation mode.

## Scope

In scope:
- `.aai/scripts/state.mjs`: extend `STRATEGIES` with `direct` and `untested`
  (back-compat: existing values unchanged); `set-strategy` REJECTS `untested`
  without a non-empty `--rationale` (exit 2 pre-write, nothing written).
- `.aai/scripts/orchestration-dispatch.mjs`: mirror the enum so a STATE the CLI
  writes is not rejected by the dispatcher's `checkEnum` (producer/consumer seam);
  `direct`/`untested` fall through rule 9c to the regular Implementation agent.
- Intake surface: single-source the 3-way choice block in `.aai/INTAKE_COMMON.md`,
  apply it at the end of the flow from `.aai/SKILL_INTAKE.prompt.md` (STEP 3.5).
- Downstream honor: PLANNING respect-clause (step 7 + set-strategy enum),
  IMPLEMENTATION direct/untested lanes (step 4), SKILL_TDD non-TDD-lane hand-off
  (Phase 0 step 5), VALIDATION STRATEGY-CONDITIONAL EVIDENCE (step 5g).
- Governance: prompt-diet ledger true-up (JUSTIFIED_ADDITIONS +4774 B) + TEST-012
  pin bump; L3 spec + intake (user_visible); CHANGELOG NEW entry.

Out of scope:
- Any change to the rigor of the `tdd`/`hybrid`/`loop` lanes.
- Auto-detection of scope size (a new detection script is a separate, larger scope).
- No new `.aai/**` file (so no PROFILES.yaml classification is required per
  PLANNING step 3a).

## Design

### Enum (state.mjs, orchestration-dispatch.mjs)
`STRATEGIES = ['loop','tdd','hybrid','direct','untested','undecided']`. `direct` =
direct implementation + targeted regression tests, no RED/GREEN ceremony;
`untested` = direct implementation, NO tests. `cmdSetStrategy` fails exit-2
pre-write when `selected === 'untested'` and `--rationale` is missing or blank.
Dispatch rule 7 (re-plan) fires only on `undecided`/missing, so the new lanes are
never re-planned; rules 9a/9b (tdd/hybrid) skip them; rule 9c dispatches the
regular Implementation agent, which reads `implementation_strategy.selected` and
runs the chosen lane.

### Intake surface (single-sourced)
The "IMPLEMENTATION MODE CHOICE" block lives once in `.aai/INTAKE_COMMON.md`
(the shared-policy home; SKILL_INTAKE's SHARED POLICY line now names five blocks)
and is applied at the guaranteed end-of-flow point (SKILL_INTAKE STEP 3.5). It
presents 3 options WITH a recommendation derived from deterministic signals
(script/tuning/config-only -> untested; small single-surface -> direct;
behavioral/multi-surface/core/L2-L3 -> tdd), records the choice via
`set-strategy --source intake --rationale "<user words>"`, and is a no-op when the
user does not choose (Planning decides — back-compat).

### Strategy-conditional evidence (VALIDATION)
The RED-proof demand of step 5g is conditional on the strategy and NEVER weakens
suite execution or the AC STATUS GATE: tdd/hybrid unchanged (full 5g incl.
tdd-evidence-check.mjs/infra_fail/RED_CLASS/Legacy); direct -> targeted-test exit
codes, no RED-proof; untested -> the declared verification (smoke/manual) + the
recorded rationale.

## Companion obligations (PLANNING step 3a)
- Prompt-corpus byte growth -> prompt-diet ledger true-up: applies. New
  JUSTIFIED_ADDITIONS entry (+4774 B, measured deficit, credited 1:1 so headroom
  stays 0/2048) + TEST-012 pin bump (-10006 -> -5232). Guarded by
  tests/skills/lib/prompt-diet-ledger.sh via TEST-010/TEST-012.
- New `.aai/**` file -> PROFILES.yaml classification: does NOT apply (all edited
  files pre-exist; no new `.aai/**` file added).

## Implementation strategy
- Strategy: tdd
- Rationale: touches a PROTECTED core script (L3) where the failure class is a
  silently mis-validated strategy (loop stranded / rigor silently downgraded). The
  AC-gating enum + rationale-guard tests were observed RED before GREEN
  (docs/ai/tdd/implementation-mode-choice-state-RED.log ->
  implementation-mode-choice-state-GREEN.log); the prompt-wiring grep-contract
  pins were RED at HEAD (docs/ai/tdd/implementation-mode-choice-prompts-RED.log).
  The codebase precedent on the same protected surface (SPEC-0012, SPEC-0107) is
  TDD.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: L3 protected surface (state engine). Rule-8 REQUIRED
  semantics mandate a RECORDED user_decision; the change edits the shared
  transactional STATE CLI every ride depends on.
- User decision: recorded from the operator's run-level authorization. Work is on
  the dedicated isolated worktree branch off main (feat/implementation-mode-choice).
- Base ref: main
- Inline review scope (if inline is recorded):
  .aai/scripts/state.mjs, .aai/scripts/orchestration-dispatch.mjs,
  .aai/INTAKE_COMMON.md, .aai/SKILL_INTAKE.prompt.md, .aai/PLANNING.prompt.md,
  .aai/IMPLEMENTATION.prompt.md, .aai/SKILL_TDD.prompt.md, .aai/VALIDATION.prompt.md,
  tests/skills/test-aai-state.sh, tests/skills/test-aai-implementation-mode.sh,
  tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh,
  tests/skills/suite-map.yaml,
  docs/specs/SPEC-0109-spec-implementation-mode-choice.md,
  docs/issues/CHANGE-0100-implementation-mode-choice.md, CHANGELOG.md

## Acceptance Criteria Mapping
- Maps to: intake AC-001
  - Spec-AC-01: `set-strategy` accepts `direct` and `untested`; legacy values still
    work. Verification: bash tests/skills/test-aai-state.sh (test_060). Exit 0.
- Maps to: intake AC-002
  - Spec-AC-02: `set-strategy --selected untested` without a non-empty `--rationale`
    exits 2 and writes nothing; `direct` needs none. Verification:
    bash tests/skills/test-aai-state.sh (test_061). Exit 0.
- Maps to: intake AC-003
  - Spec-AC-03: the 3-way choice with a recommendation is surfaced at end of intake,
    recorded via `set-strategy --source intake`, and no-ops when unchosen.
    Verification: bash tests/skills/test-aai-implementation-mode.sh (TEST-001/002).
- Maps to: intake AC-004
  - Spec-AC-04: the chosen lane is honored in PLANNING/IMPLEMENTATION/SKILL_TDD and
    VALIDATION's RED-proof demand is strategy-conditional (tdd/hybrid never weakened).
    Verification: bash tests/skills/test-aai-implementation-mode.sh (TEST-003..007).
- Maps to: intake AC-001..004 (L3 + governance)
  - Spec-AC-05: the L3 touch is authorized by this frozen ceremony_level:3 spec and
    the prompt-diet ledger is trued up. Verification:
    bash tests/skills/test-aai-hitl-propagation.sh (TEST-014) and
    bash tests/skills/test-aai-prompt-diet.sh (TEST-010/TEST-012). Exit 0.

## Constitution deviations
None.

## Seam analysis
- Seam S1 (set-strategy writer -> orchestration-dispatch reader): a strategy value
  written by `state.mjs set-strategy` is later read by
  `orchestration-dispatch.mjs` `checkEnum(STRATEGIES)`. If the two enums drift, a
  legitimately recorded `direct`/`untested` STATE would be rejected and the loop
  stranded. Covered end-to-end by test-aai-state.sh (writes direct/untested +
  check-state) AND test-aai-implementation-mode.sh TEST-007 (both enum literals
  include the new values).
- Seam S2 (intake choice -> downstream lane behavior): the choice recorded at
  intake must actually change Planning/Implementation/TDD/Validation behavior.
  Covered by the grep-contract pins TEST-002..006 (each consuming prompt carries
  the honoring clause) plus the dispatch regression suite (rule 9c routing).

Residual risks (accepted):
- RR-1: the intake presentation + recommendation is prompt-driven (LLM), not a
  deterministic script; the grep-contract pins prove the instruction is PRESENT
  and single-sourced, not that a given run phrased it perfectly. Auto-detection of
  scope size is deliberately out of scope (would be a separate script).
- RR-2: `untested` skips scope tests by design; the rationale guard + visible
  hand-off + VALIDATION declared-verification requirement are the compensating
  controls (never a silent downgrade).
- RR-3 (L3 review): this change RAISES THE PAYOFF of the pre-existing accepted
  residual R-GUARD (SUBAGENT_PROTOCOL.md — no runtime git-diff guard on STATE
  writes): an out-of-contract subagent `set-strategy` write used to mean a lost
  update; it can now mean a rigor downgrade (tdd -> untested escapes RED-proof).
  Mitigations: the single-writer prohibition (SUBAGENT_CONTRACT.md) still bans
  the write as a process rule, VALIDATION keys off the RECORDED strategy (a lazy
  implementer who skips RED while STATE says tdd still FAILS 5g), and `untested`
  cannot be recorded without a rationale. If R-GUARD is ever built, strategy
  flips should be among its watched mutations.

## Acceptance Criteria Status

| Spec-AC    | Description                                                          | Status | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | set-strategy accepts direct + untested; legacy values unchanged     | done | test-aai-state.sh test_060 green; docs/ai/tdd/implementation-mode-choice-state-RED.log, implementation-mode-choice-state-GREEN.log | — | — |
| Spec-AC-02 | untested without a non-empty rationale exits 2, writes nothing       | done | test-aai-state.sh test_061 green; docs/ai/tdd/implementation-mode-choice-state-GREEN.log | — | — |
| Spec-AC-03 | 3-way intake choice + recommendation surfaced, recorded, back-compat | done | test-aai-implementation-mode.sh TEST-001/002 green; docs/ai/tdd/implementation-mode-choice-prompts-RED.log, implementation-mode-choice-prompts-GREEN.log | — | — |
| Spec-AC-04 | downstream honor + strategy-conditional evidence, tdd/hybrid intact  | done | test-aai-implementation-mode.sh TEST-003..007 green; implementation-mode-choice-prompts-GREEN.log | — | — |
| Spec-AC-05 | L3 authorized by this frozen spec + prompt-diet ledger trued up      | done | test-aai-hitl-propagation.sh TEST-014 green; test-aai-prompt-diet.sh TEST-010/012 green | — | — |

## Implementation plan
- Components/modules affected: .aai/scripts/state.mjs (enum + untested guard),
  .aai/scripts/orchestration-dispatch.mjs (enum + rule-9c comment), five prompt
  files + INTAKE_COMMON.md, the two test suites + suite-map + ledger.
- Data flows: intake -> set-strategy (STATE) -> orchestration-dispatch reads
  strategy -> Implementation/TDD lane -> Validation evidence gate. No new JSONL.
- Edge cases: untested missing/blank rationale (reject); direct without rationale
  (allowed); user declines the choice (planner decides); legacy STATE with a
  legacy strategy (unchanged).

## Test Plan

Test ID / Spec-AC / Type / File / Description / Status:

- TEST-060 / Spec-AC-01 / unit / tests/skills/test-aai-state.sh / set-strategy accepts direct+untested + all legacy values, check-state clean / green
- TEST-061 / Spec-AC-02 / unit / tests/skills/test-aai-state.sh / untested demands a non-empty rationale (exit 2, no write); direct does not / green
- TEST-IM-001 / Spec-AC-03 / integration / tests/skills/test-aai-implementation-mode.sh / intake choice block single-sourced, 3 options + recommendation + back-compat / green
- TEST-IM-002 / Spec-AC-03 / integration / tests/skills/test-aai-implementation-mode.sh / SKILL_INTAKE surfaces the choice at end of flow / green
- TEST-IM-003..006 / Spec-AC-04 / integration / tests/skills/test-aai-implementation-mode.sh / PLANNING respect-clause, IMPLEMENTATION lanes, SKILL_TDD routing, VALIDATION conditional evidence / green
- TEST-IM-007 / Spec-AC-04 / integration / tests/skills/test-aai-implementation-mode.sh / producer/consumer enum seam + untested guard / green
- TEST-014 / Spec-AC-05 / integration / tests/skills/test-aai-hitl-propagation.sh / touched protected_paths_l3 path authorized by this frozen ceremony_level:3 spec / green
- TEST-010/012 / Spec-AC-05 / integration / tests/skills/test-aai-prompt-diet.sh / prompt-diet floor holds + JUSTIFIED_GROWTH_BYTES re-sum matches / green

RED-proof obligation: the AC-gating state tests (TEST-060/061) were observed
FAILING against the unmodified state.mjs (implementation-mode-choice-state-RED.log)
before GREEN; the prompt-wiring pins were observed absent at HEAD
(implementation-mode-choice-prompts-RED.log).

## Verification
- Commands:
  - bash tests/skills/test-aai-state.sh
  - bash tests/skills/test-aai-implementation-mode.sh
  - bash tests/skills/test-aai-hitl-propagation.sh
  - bash tests/skills/test-aai-verify-gate.sh
  - bash tests/skills/test-aai-tdd-evidence.sh
  - bash tests/skills/test-aai-prompt-diet.sh
  - bash tests/skills/test-aai-hygiene-pack.sh
  - bash tests/skills/test-aai-layer-profiles.sh
  - node .aai/scripts/docs-audit.mjs --check --strict --no-event
  - node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0109-spec-implementation-mode-choice.md
- Evidence artifacts: suite stdout (exit 0), RED/GREEN logs under docs/ai/tdd/.
- PASS criteria: all TEST green AND all Spec-AC terminal AND full framework green.

## Evidence contract
Per artifact record: ref_id (implementation-mode-choice); Spec-AC and TEST links;
command or review scope; exit code or review verdict; evidence path; commit SHA or
diff range when available.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
