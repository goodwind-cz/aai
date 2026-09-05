---
id: spec-roadmap-driven-ride-selection-with-budget
type: spec
number: 168
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0174-roadmap-driven-ride-selection-with-budget.md
  rfc: null
  pr:
    - 345
  commits:
    - c3381428
---

# Spec — rides come from the roadmap, and every maintenance ride is paired with a capability

SPEC-FROZEN: true

## Links
- Requirement: `docs/issues/CHANGE-0174-roadmap-driven-ride-selection-with-budget.md`
- Roadmap: `docs/project-sessions/2026-09-05-capability-roadmap.md` (wave 1, pair 1, maintenance half; paired capability: CHANGE-0173 `/aai-live`, merged in #344)
- Owner decisions (`hitl_decision`, `owner_signoff: true`, 2026-09-05): `capability-roadmap-drives-rides`, `maintenance-budget-one-to-one`, `internal-work-without-asking`, `review-round-cap`
- Wiring points: `.aai/SKILL_SHIP.prompt.md` RUN step 1, `.aai/SKILL_LOOP.prompt.md` new-intake dispatch, `.aai/VALIDATION.prompt.md` c2, `.aai/AGENTS.md` (vendored; carried downstream by `/aai-update`)
- Precedent for a config under `docs/ai/`: `docs/ai/pr-config.yaml`, `docs/ai/docs-audit.yaml`
- Technology contract: `docs/TECHNOLOGY.md` (Node stdlib only, zero deps, bash 3.2 suites); `.aai/ORCHESTRATION.prompt.md` is at its 40-line cap and is NOT touched

Registry items closed by this scope: none. `follow-ups.mjs list --status open | grep -iE 'roadmap|budget|pair'` names no open item; the four decisions are ledger lines nothing reads yet.

## Design decisions
- **D1 — the roadmap is data, the narrative doc is prose.** `docs/ai/roadmap.yaml`: ordered `pairs[]`, each `{capability: <ref>, maintenance: <ref>, status: planned|active|done}` plus `wave_2[]` and `budget: {maintenance_per_capability: 1}`. A validator refuses a pair with two maintenance refs or two capability refs, a ref that is not a slug, and a duplicate ref.
- **D2 — one script, two verbs.** `ride-select.mjs next` prints the ride to start (first pair not done, capability half first unless the capability is already `implementing`/`done`, then the maintenance half). `ride-select.mjs gate --ref <r> [--intake <path>]` exits 0 when `<r>` may start now, else non-zero with ONE named reason and the remedy.
- **D3 — deny by default, four named exits.** The gate refuses: (a) a maintenance ride whose paired capability is not at least `implementing` — "pair first"; (b) any ref not on the roadmap whose intake type is issue/hotfix/techdebt, or whose slug/title says fix/guard/harness — "file it to the backlog: `node .aai/scripts/follow-ups.mjs add …`", unless the intake carries `blocks: <roadmap ref>` naming a roadmap ref that exists and is not done; (c) an unreadable or invalid roadmap — refuse, never "no roadmap, anything goes"; (d) a ref that is done. A ref on the roadmap as a capability always passes.
- **D4 — the owner can override, never silently.** `--override "<reason>"` lets any ref through, appends an `override` event to `docs/ai/EVENTS.jsonl` naming ref and reason, and prints that it did. There is no environment-variable override.
- **D5 — the rules live where every agent and every downstream project reads them.** `.aai/AGENTS.md` gains `### Operator contract` (≤ 40 lines, four rules in operator terms). `.aai/VALIDATION.prompt.md` c2 gains the two-round STOP: a third finding-bearing round is a STOP with "split the ride", not a fourth round. Prompt-corpus growth is credited at the measured byte count.

## Implementation strategy
- Strategy: tdd
- Rationale: the value is in the refusals (D3 a–d); a suite that only proves `next` prints something would pass while the gate let a fix through.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | `docs/ai/roadmap.yaml` exists with wave-1 pairs in the roadmap doc's order and `ride-select.mjs validate` exits 0 on it; a fixture with two maintenance refs in one pair, a duplicate ref, and a non-slug ref each exit 2 naming the pair | done | TEST-001, tests/skills/test-aai-ride-select.sh (eight malformed shapes, each refused by its named reason); docs/ai/tdd/roadmap-driven-ride-selection-with-budget-green.log; RED in docs/ai/tdd/roadmap-driven-ride-selection-with-budget-red.log | tdd:2026-09-05 | D1; duplicate keys inside a pair and duplicate sections refuse (round 1 F-03) |
| Spec-AC-02 | `ride-select.mjs next` on the shipped roadmap prints a ref the shipped `gate` ADMITS, or `wave 1 complete` (an invariant, never a literal ride name — Amendment 3); on a fixture where pair 1's capability is `planned` it prints that capability; when every pair is done it prints `wave 1 complete` and exits 0 | done | TEST-002, tests/skills/test-aai-ride-select.sh; docs/ai/tdd/roadmap-driven-ride-selection-with-budget-green.log; shipped arm is an INVARIANT (next is gate-admitted or wave 1 complete), re-verified with the intake flipped to done in docs/ai/validation/roadmap-driven-ride-selection-with-budget-round2.md | tdd:2026-09-05 | D2; capability first unless STARTED (round 1 F-02) |
| Spec-AC-03 | `gate --ref <maintenance>` exits non-zero with "pair first" while its capability is `planned`, and 0 once the capability is `implementing` or `done` | done | TEST-003, tests/skills/test-aai-ride-select.sh; docs/ai/tdd/roadmap-driven-ride-selection-with-budget-green.log; pair-done arm added | tdd:2026-09-05 | D3a |
| Spec-AC-04 | `gate --ref some-fix --intake <issue-type intake>` exits non-zero with "file it to the backlog" and the follow-ups command; the same intake carrying `blocks: live-agent-dashboard` (a roadmap ref) exits 0; carrying `blocks: not-on-roadmap` exits non-zero naming the unknown ref | done | TEST-004, tests/skills/test-aai-ride-select.sh; docs/ai/tdd/roadmap-driven-ride-selection-with-budget-green.log; blocks: on a done target refuses; slug-word and title arms assert the reason | tdd:2026-09-05 | D3b both arms |
| Spec-AC-05 | `gate` with a missing or invalid roadmap exits non-zero — never passes — and a done ref is refused as done | done | TEST-005, tests/skills/test-aai-ride-select.sh; docs/ai/tdd/roadmap-driven-ride-selection-with-budget-green.log; parse reason asserted | tdd:2026-09-05 | D3c, D3d fail closed |
| Spec-AC-06 | `gate --ref some-fix --override "owner: hotfix"` exits 0 AND appends exactly one `override` event to the EVENTS ledger given by `--events`, carrying ref and reason; without a reason the flag is a usage error | done | TEST-006, tests/skills/test-aai-ride-select.sh; docs/ai/tdd/roadmap-driven-ride-selection-with-budget-green.log; event ride_gate_override with the git actor slug (append-event.mjs shape) | tdd:2026-09-05 | D4; intake/ref mismatch is usage |
| Spec-AC-07 | `SKILL_SHIP.prompt.md` and `SKILL_LOOP.prompt.md` invoke the gate before a new ride starts and STOP on non-zero, quoting its message; `VALIDATION.prompt.md` c2 carries the two-round STOP; `AGENTS.md` carries `### Operator contract` with the four rules in ≤ 40 lines; prompt-diet credit equals the MEASURED growth, TEST-012 pin bumped 1:1, layer-profiles green | done | TEST-007, tests/skills/test-aai-ride-select.sh + test_0rs_arm4a_roadmap_gate in test-aai-orchestration-dispatch.sh (71 PASS); prompt-diet (+976 in-glob, +1461 AGENTS re-measured, pin 15084) and layer-profiles green; docs/ai/tdd/roadmap-driven-ride-selection-with-budget-green.log; full sweep 88/88 | tdd:2026-09-05 | D5; the autonomous path is gated in orchestration-dispatch 4a (round 1 F-01) |

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                     | Description | Status |
|----------|------------|------|------------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-ride-select.sh | validate: shipped roadmap 0; three malformed fixtures exit 2 naming the pair | pending |
| TEST-002 | Spec-AC-02 | unit | tests/skills/test-aai-ride-select.sh | next: shipped roadmap prints the maintenance half; fixture with planned capability prints it; all-done prints wave 1 complete | pending |
| TEST-003 | Spec-AC-03 | unit | tests/skills/test-aai-ride-select.sh | gate pair-first: refused while capability planned, allowed once implementing | pending |
| TEST-004 | Spec-AC-04 | unit | tests/skills/test-aai-ride-select.sh | gate off-roadmap fix: refused with the follow-ups remedy; allowed with a valid blocks:; refused with an unknown blocks: | pending |
| TEST-005 | Spec-AC-05 | unit | tests/skills/test-aai-ride-select.sh | fail closed: missing roadmap, invalid roadmap, done ref | pending |
| TEST-006 | Spec-AC-06 | int  | tests/skills/test-aai-ride-select.sh | override: passes, appends exactly one event with ref+reason to a fixture ledger; missing reason is a usage error | pending |
| TEST-007 | Spec-AC-07 | int  | tests/skills/test-aai-ride-select.sh | wiring: SHIP and LOOP name ride-select.mjs gate; VALIDATION c2 names the two-round STOP; AGENTS has the contract heading with four rules | pending |
| TEST-008 | Spec-AC-07 | int  | tests/skills/test-aai-prompt-diet.sh | ledger credit equals measured growth; pin bumped | pending |

## Implementation plan
- **NEW** `docs/ai/roadmap.yaml`; **NEW** `.aai/scripts/ride-select.mjs` (`validate | next | gate`, flags `--roadmap`, `--ref`, `--intake`, `--override`, `--events`, `--json`); **NEW** `tests/skills/test-aai-ride-select.sh`.
- **EDIT** `.aai/SKILL_SHIP.prompt.md` (RUN 1), `.aai/SKILL_LOOP.prompt.md` (new-intake dispatch), `.aai/VALIDATION.prompt.md` (c2), `.aai/AGENTS.md` (`### Operator contract`), `.aai/system/PROFILES.yaml`, `tests/skills/suite-map.yaml`, prompt-diet ledger + pin.

## Constraints / Risks
- The gate reads `docs/ai/roadmap.yaml` with a line-level parser for the closed shape above; any other shape is invalid (fail closed), never guessed.
- Type detection for "fix-class" uses the intake's frontmatter `type` first and the slug words second; a capability intake that happens to contain the word "fix" in its slug is still admitted because it is ON the roadmap (roadmap membership wins).
- ORCHESTRATION.prompt.md is not edited (42 lines against a 40-line cap already).
