---
id: spec-lightweight-e2e-lane
type: spec
number: 112
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0103-lightweight-e2e-lane.md
  rfc: null
  pr:
    - 206
  commits:
    - 87911f324576239b39de9f24728a29fe66271b39
---

# Implementation Spec — Lightweight end-to-end lane (deterministic PR fast-path)

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0103-lightweight-e2e-lane.md (Option A)
- Related: docs/specs/SPEC-0041-spec-loop-ceremony-aware-dispatch.md
  (validation-depth lane), docs/specs/SPEC-0097-spec-ci-test-impact-selection.md
  (CI suite selection + FULL_RUN triad), docs/rfc/RFC-0009-scale-adaptive-ceremony.md
  (ceremony levels), docs/specs/SPEC-0053-spec-deterministic-close-ceremony.md
  (close-work-item.mjs contract)
- Technology contract: docs/TECHNOLOGY.md

## Summary

Deliver Option A from the intake: a DETERMINISTIC PR fast-lane that lightens
the flat governance envelope for provably-small, provably-safe rides, with a
named compensating control for every lightened step and the HEAVY lane staying
the byte-for-byte default for everything else. The lane is computed by a NEW
deterministic script (`.aai/scripts/lane-gate.mjs`) — never agent prose-judgment
— so a bad or inflated declaration can only ever select the HEAVY lane
(fail-closed, inheriting the SPEC-0041 / SPEC-0097 philosophy).

Three effects, each gated on `LANE fast`:
- EFFECT 1 (narrowed close round): the close-ceremony commit's docs-only diff
  routes to the CORE suites via select-suites.mjs — one narrowed feature round
  plus one CORE-only close round, not two full-framework rounds. NOTE: a literal
  single commit is NOT achievable — close-work-item.mjs mandates `--pr N` (needs
  the PR open first) and is frozen by AC-006; EFFECT 1 is therefore realized as
  "remove the second FULL round", exactly as the intake's Option A specifies.
- EFFECT 2 (narrowed CI): already delivered by SPEC-0097 for a mapped diff; this
  spec pins it with a regression test and composes the gate on top.
- EFFECT 3 (sweep on-demand): SKILL_PR step 5d external-bot sweep becomes
  optional-on-demand on the fast lane; the MANDATORY internal dual-verdict code
  review (WORKFLOW rule 13) stays the compensating control; any reviewer/bot may
  re-arm the sweep and a review may reclassify the ride upward.

## Frontmatter status values
- draft, implementing, done, deferred, rejected, superseded (standard).

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD (RED-first) for the anti-gaming core — the lane-gate predicate
  matrix in tests/skills/test-aai-lightweight-lane.sh was written and observed
  RED before .aai/scripts/lane-gate.mjs existed, because the whole value of the
  gate is deterministic fail-closed behavior that must be pinned test-first
  (self-evaluation trap). Loop/direct for the mechanical wiring (SKILL_PR prose,
  PROFILES classification, suite-map row, prompt-diet ledger true-up, CHANGELOG)
  where RED-GREEN adds little signal.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: framework-self change touching a core workflow prompt
  (SKILL_PR) and adding a new deterministic gate script; isolation keeps the
  main checkout stable. (This ride already runs in an isolated worktree.)
- User decision: waived
- Base ref: main
- Inline review scope: .aai/scripts/lane-gate.mjs, .aai/SKILL_PR.prompt.md,
  tests/skills/test-aai-lightweight-lane.sh, tests/skills/suite-map.yaml,
  .aai/system/PROFILES.yaml, tests/skills/lib/prompt-diet-ledger.sh,
  tests/skills/test-aai-prompt-diet.sh, docs/specs/SPEC-0112-spec-lightweight-e2e-lane.md,
  CHANGELOG.md

## Acceptance Criteria Mapping
For each requirement AC:
- Maps to: CHANGE-0103-lightweight-e2e-lane AC-001..AC-007
- Spec-AC-01..07 below map 1:1 onto the intake's AC-001..007.
- Verification: see the Verification section and the Test Plan.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                                                                                     | Status | Evidence                          | Review-By | Notes |
|------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|--------|-----------------------------------|-----------|-------|
| Spec-AC-01 | WHEN all four predicates hold (ceremony_level in 0 or 1; strategy in direct/untested/loop; select-suites not FULL_RUN; changed-files under N and classes allowed) the gate SHALL print LANE fast              | done | TEST-001, TEST-013, TEST-015, TEST-016 | —         | four-predicate conjunction |
| Spec-AC-02 | WHEN any single predicate is false, absent, garbage, or degenerate the gate SHALL print LANE heavy naming the first failing predicate (fail-closed, anti-gaming) | done | TEST-002..TEST-012, TEST-014      | —         | each predicate flipped independently |
| Spec-AC-03 | WHEN LANE fast fires SKILL_PR step 5d SHALL make the external bot sweep optional-on-demand while the internal dual-verdict review stays a mandatory merge-readiness precondition and any reviewer/bot may re-arm the sweep | done | TEST-018                          | —         | compensating control pinned by grep-contract |
| Spec-AC-04 | WHEN the close-ceremony commit diff is docs frontmatter plus EVENTS.jsonl plus INDEX.md select-suites SHALL route it to the CORE suites and never FULL_RUN       | done | TEST-017                          | —         | second FULL round removed |
| Spec-AC-05 | WHEN ceremony_level is 2 or more or any FULL_RUN triad path is present or the file count exceeds N the ride SHALL take the unchanged HEAVY lane                   | done | TEST-002, TEST-006, TEST-008      | —         | heavy is the default |
| Spec-AC-06 | The docs-audit close gate, doc-number allocator, state engine, pre-commit guards, WORKFLOW.md, and operator-only merge SHALL be untouched by this scope          | done | git diff empty over protected surfaces; docs-audit --check --strict --no-event exit 0 | — | no protected_paths_l3 change |
| Spec-AC-07 | The gate SHALL emit the selected lane and the predicate values that chose it so a reviewer can see WHY a ride went light                                          | done | TEST-013; SKILL_PR PR body Lane section (TEST-018) | — | never a hidden decision |

Status values: planned, implementing, done, deferred, blocked, rejected.

## Implementation plan
- New: `.aai/scripts/lane-gate.mjs` — reads ceremony_level (frozen spec
  frontmatter, same reader as orchestration-dispatch.mjs, fail-closed), strategy
  (STATE implementation_strategy.selected, indentation-scoped reader),
  select-suites.mjs result (subprocess, `--files-from -`, reusing the FULL_RUN
  triad verbatim), and the diff surface (count under N plus class membership).
  Always exit 0; verdict + predicate lines on stdout; `--json` mode.
- Edit: `.aai/SKILL_PR.prompt.md` — step 5 LANE classification, PR body Lane
  section, step 5c CORE-only close routing note, step 5d optional-on-demand
  sweep with the mandatory internal review kept as the compensating control.
- Companions: PROFILES.yaml (core classification of the new script), suite-map
  row (hygiene pin), prompt-diet ledger true-up (+2544 B credited 1:1) and the
  TEST-012 checkpoint bump.
- Data flow: gate reads only machine sources; no writes anywhere.
- Edge cases: empty diff (fast if metadata ok); unreadable diff/spec/state
  (heavy); mapped-but-unclassified surface (heavy — predicate 4 is stricter than
  predicate 3); internal error (heavy, exit 0).

## Seam analysis
- SEAM: lane-gate.mjs consumes select-suites.mjs output. Covered end-to-end by
  TEST-006/TEST-007 (real select-suites subprocess produces FULL_RUN, gate reads
  it) and TEST-017 (real select-suites over a real docs-only close diff) — not a
  mocked boundary.
- SEAM: lane-gate.mjs reads the spec frontmatter and STATE that Planning writes.
  Covered by TEST-001..005/012 with real on-disk fixtures.
- Residual: the live end-to-end wall-clock saving (CI-round count vs the ~42-min
  heavy floor) is deferred live evidence, captured on the first real lightweight
  ride (SPEC-0041 precedent) — recorded as a residual risk, not automatable
  here without a network CI round.

## Test Plan

| Test ID  | Spec-AC    | Type | File path                                   | Description                                                        | Status |
|----------|------------|------|---------------------------------------------|-------------------------------------------------------------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-lightweight-lane.sh   | all four predicates true prints LANE fast                         | green  |
| TEST-002 | Spec-AC-02 | unit | tests/skills/test-aai-lightweight-lane.sh | ceremony_level 2 gives heavy reason ceremony_level (also Spec-AC-05) | green  |
| TEST-003 | Spec-AC-02 | unit | tests/skills/test-aai-lightweight-lane.sh   | garbage ceremony_level gives heavy                                | green  |
| TEST-004 | Spec-AC-02 | unit | tests/skills/test-aai-lightweight-lane.sh   | strategy tdd gives heavy reason strategy                          | green  |
| TEST-005 | Spec-AC-02 | unit | tests/skills/test-aai-lightweight-lane.sh   | absent strategy gives heavy                                       | green  |
| TEST-006 | Spec-AC-02 | unit | tests/skills/test-aai-lightweight-lane.sh | protected_paths_l3 path gives heavy reason full_run (also Spec-AC-05) | green  |
| TEST-007 | Spec-AC-02 | unit | tests/skills/test-aai-lightweight-lane.sh   | unmapped path gives heavy reason full_run                         | green  |
| TEST-008 | Spec-AC-02 | unit | tests/skills/test-aai-lightweight-lane.sh | file count at or above N gives heavy reason diff_surface (also Spec-AC-05) | green  |
| TEST-009 | Spec-AC-02 | unit | tests/skills/test-aai-lightweight-lane.sh   | two test files give heavy                                         | green  |
| TEST-010 | Spec-AC-02 | unit | tests/skills/test-aai-lightweight-lane.sh   | two script files give heavy                                       | green  |
| TEST-011 | Spec-AC-02 | unit | tests/skills/test-aai-lightweight-lane.sh   | mapped but unclassified surface gives heavy diff_surface          | green  |
| TEST-012 | Spec-AC-02 | unit | tests/skills/test-aai-lightweight-lane.sh   | missing spec file gives heavy                                     | green  |
| TEST-013 | Spec-AC-01 | unit | tests/skills/test-aai-lightweight-lane.sh | fast verdict emits every predicate value (also Spec-AC-07) | green  |
| TEST-014 | Spec-AC-01 | unit | tests/skills/test-aai-lightweight-lane.sh   | degenerate inputs still exit 0 defaulting to heavy               | green  |
| TEST-015 | Spec-AC-01 | unit | tests/skills/test-aai-lightweight-lane.sh   | ceremony_level 0 boundary is also fast-eligible                  | green  |
| TEST-016 | Spec-AC-01 | unit | tests/skills/test-aai-lightweight-lane.sh   | empty diff with ok metadata is fast                             | green  |
| TEST-017 | Spec-AC-04 | integration | tests/skills/test-aai-lightweight-lane.sh | real select-suites over a docs-only close diff never FULL_RUN | green  |
| TEST-018 | Spec-AC-03 | unit | tests/skills/test-aai-lightweight-lane.sh | SKILL_PR wires the gate, on-demand sweep, mandatory internal review (also Spec-AC-07) | green  |

Test status values: pending, red, green.

## Verification
- `bash tests/skills/test-aai-lightweight-lane.sh` exits 0 (TEST-001..018).
- `bash tests/skills/test-aai-prompt-diet.sh` exits 0 (ledger true-up + TEST-012 bump).
- `bash tests/skills/test-aai-hygiene-pack.sh` exits 0 (suite-map row for the new test).
- `bash tests/skills/test-aai-layer-profiles.sh` exits 0 (PROFILES classifies the new script).
- `bash tests/skills/test-aai-suite-select.sh` exits 0 (suite-map still valid).
- `bash tests/skills/test-aai-pr-platform.sh` exits 0 (SKILL_PR 5d TEST-022 intact).
- `bash tests/skills/test-aai-orchestration-dispatch.sh` exits 0 (unchanged lane concept).
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0112-spec-lightweight-e2e-lane.md` (report-only).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exits 0.
- AC-006: `git diff` over close-work-item.mjs / allocate-doc-number.mjs / state
  engine / pre-commit-checks / WORKFLOW.md / CONSTITUTION.md is empty.
- Live (deferred): first real lightweight ride records its CI-round count +
  wall-clock against the ~42-min heavy floor (SPEC-0041 precedent).

## Evidence contract
- ref_id: spec-lightweight-e2e-lane
- command / exit code / evidence path recorded per Verification above.
- commit SHA: recorded at commit time.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
