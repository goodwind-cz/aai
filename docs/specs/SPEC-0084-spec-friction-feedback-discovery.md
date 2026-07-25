---
id: spec-friction-feedback-discovery
type: spec
number: 84
status: done
ceremony_level: 2
links:
  requirement: CHANGE-0051-friction-feedback-discovery
  rfc: RFC-0012
  pr:
    - 150
  commits:
    - 523b48f00cbba166c3c9a0cefe008dee90d9f733
---

# SPEC — RFC-0012 friction feedback discovery + gh auth preflight + user docs

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0051-friction-feedback-discovery.md
- Foundation: aai-feedback-triage.mjs, aai-feedback-upsert.mjs, feedback.yaml
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: Deterministic offline counters + a mockable read-only auth probe — a
  clean RED/GREEN with a mock `gh` on PATH. Docs + wrap-up wiring are grep-assertable.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: One new offline script + an auth preflight + wrap-up wiring +
  user docs + tests; reversible; no protected_paths_l3.
- User decision: inline
- Base ref: main
- Inline review scope: .aai/scripts/aai-feedback-status.mjs, .aai/scripts/aai-feedback-upsert.mjs (auth preflight only), .aai/SKILL_WRAP_UP.prompt.md, docs/USER_GUIDE.md, .aai/system/PROFILES.yaml, tests/skills/test-aai-feedback-status.sh, tests/skills/lib/prompt-diet-ledger.sh + tests/skills/test-aai-prompt-diet.sh

## Acceptance Criteria Mapping
- Spec-AC-01 (AC-001/002/003): `aai-feedback-status.mjs` reports the spool
  observation count + pending-draft count + gh state (ready/unauthenticated/absent)
  and valid --json; never fails the caller; no mutating gh call (only read-only
  `gh auth status`). Verification: TEST-001..004 with a mock gh.
- Spec-AC-02 (AC-004): the upsert prepare + publish paths run a gh auth preflight
  and emit a clear `gh auth login` message when unauthenticated; the
  no-write-without-confirm invariant is unchanged. Verification: upsert suite green +
  a mock-unauthenticated publish exits non-zero with the hint.
- Spec-AC-03 (AC-005): SKILL_WRAP_UP wires the status nudge (grep-assertable) and is
  silent when nothing is captured. Verification: grep + the status TEST-004 silent case.
- Spec-AC-04 (AC-006): USER_GUIDE has a "Friction feedback loop" section covering
  the workflow + the `gh auth login` prerequisite. Verification: grep.
- Spec-AC-05 (AC-007): companion — new `.aai/**` file classified in PROFILES.yaml;
  prompt-diet trued up for the SKILL_WRAP_UP growth; layer-profiles + prompt-diet green.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                          | Status  | Evidence | Review-By | Notes |
|------------|------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | status script: counts + gh state, offline, no mutation | done  | test-aai-feedback-status.sh | — | GREEN |
| Spec-AC-02 | upsert gh auth preflight; confirm invariant intact    | done  | test-aai-feedback-upsert.sh | — | GREEN |
| Spec-AC-03 | wrap-up nudge wiring, silent when empty                | done  | grep + status TEST-004     | — | GREEN |
| Spec-AC-04 | USER_GUIDE friction feedback section + auth prereq     | done  | grep                        | — | GREEN |
| Spec-AC-05 | companion PROFILES + prompt-diet true-up               | done  | both suites green           | — | GREEN |

## Implementation plan
- `.aai/scripts/aai-feedback-status.mjs`: countObservations + countDrafts (fs) +
  ghState (`gh auth status`, read-only) -> human line or --json; silent when empty.
- `.aai/scripts/aai-feedback-upsert.mjs`: ghAuthState()/ghAuthHint(); publish
  preflight (fail fast) + prepare note.
- `.aai/SKILL_WRAP_UP.prompt.md`: step 6 FRICTION FEEDBACK NUDGE.
- `docs/USER_GUIDE.md`: "Friction feedback loop" section.
- PROFILES.yaml: classify aai-feedback-status.mjs. prompt-diet: +608 B true-up.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description                                       | Status |
|----------|------------|-------------|-----------------------------------------|---------------------------------------------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-feedback-status.sh | counts observations + drafts; valid --json        | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-feedback-status.sh | gh ready/unauthenticated/absent; caller never fails | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-feedback-status.sh | no mutating gh call; only read-only auth status   | green |
| TEST-004 | Spec-AC-03 | unit        | tests/skills/test-aai-feedback-status.sh | empty spool -> quiet, exit 0 (silent nudge)       | green |

RED-proof: TEST-001..004 written against the absent status script (product_red).

## Verification
- `bash tests/skills/test-aai-feedback-status.sh` (green)
- `bash tests/skills/test-aai-feedback-upsert.sh` (auth preflight; green)
- `bash tests/skills/test-aai-layer-profiles.sh` + `test-aai-prompt-diet.sh` green
- `node .aai/scripts/docs-audit.mjs` CLEAN
- PASS: all TEST-xxx green + all Spec-AC terminal

## Evidence contract
Per artifact: ref_id friction-feedback-discovery; Spec-AC + TEST links; command;
exit code; evidence path; commit SHA.

Notes: This document defines HOW, not WHAT/WHY. It does not define workflow.
