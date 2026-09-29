---
id: spec-strategy-unscoped-from-current-focus
type: spec
number: 192
status: done
mutation_gate: v1
frozen_sha256: 3d0dc40169721db22183005b307fb383db7e851c14728fef4427827c02f6f048
ceremony_level: 3
links:
  requirement: docs/issues/ISSUE-0086-strategy-unscoped-from-current-focus.md
  rfc: null
  pr:
    - 405
  commits:
    - d1fe5091373c81a7c148d145d136fe8246a169c6
---

# Spec — bind implementation_strategy to the live current_focus ref_id

SPEC-FROZEN: true

## Ceremony level (RFC-0009)

`ceremony_level: 3` — MANDATORY. The scope edits `.aai/scripts/state.mjs`, listed
verbatim in `protected_paths_l3` (docs/ai/docs-audit.yaml) and in WORKFLOW.md
Protected surfaces (state engine). A scope that touches a protected surface MUST
declare level 3. L3 consequences carried:

- Worktree gate (rule 8): REQUIRED semantics — an explicit user_decision must be
  recorded for any recommendation. Autopilot never records this decision.
- Code review (rule 13): MANDATORY on the most capable tier. No auto-waiver.
- PR ceremony: operator checkpoint before merge.
- Evidence-before-claims and full independent validation are not pruned.

## Links
- Requirement: docs/issues/ISSUE-0086-strategy-unscoped-from-current-focus.md
- Related done work that does not close this: ISSUE-0040 / ISSUE-0069 (stale
  spec_path), CHANGE-0100 / SPEC-0109 (mode choice), CHANGE-0107 / SPEC-0113
  (R-guard), CHANGE-0031 / SPEC-0042 (dispatch after completed scope)
- Engine: `.aai/scripts/state.mjs` (writer), `.aai/scripts/lane-gate.mjs` and
  `.aai/scripts/orchestration-dispatch.mjs` (readers)
- Technology contract: docs/TECHNOLOGY.md

## Problem

`implementation_strategy` is a single global block. `set-strategy` writes
`selected` / `source` / `rationale` without a `ref_id`. `set-focus` retargets
`current_focus` without clearing or rebinding that block. A leftover
`untested` (or any other selected) from item A is then consumed by TDD
preflight, Validation, and lane-gate as if it belonged to item B.

Observed pairing (Windows working tree, 2026-09-24): focus
`bezdinek-aggregation-block-failure` with strategy rationale belonging to
`scada-history-chunk-import`.

## Design decisions (resolved — do not reopen during implementation)

### D1 — additive `ref_id` on the existing global block

Do not nest strategy under `active_work_items` and do not invent a second
strategy map. Add `implementation_strategy.ref_id` (scalar, `null` when
unset). `set-strategy` always writes it. Constitution Article 5: additive at
the schema boundary; existing fixtures without the key remain valid.

### D2 — bind source

`set-strategy --ref` is optional. Bind target is `--ref` if given, else
`current_focus.ref_id`. If both are non-null and they differ: exit 2, named
error containing `disagrees`, both refs, and no write. If neither is a
non-null ref: exit 2 naming `--ref`, no write. Documented sequence
`set-focus` then `set-strategy` without `--ref` stays green (derive).
Intake (CHANGE-0100) is the other documented sequence: after the artifact is
saved and before Planning `set-focus`, record
`set-strategy --source intake --ref <this intake's ref_id>`. That bind is
legal because `--ref` is allowed when `current_focus.ref_id` is unset
(post-`clear-focus`). A live focus on a different item still `disagrees` —
do not bypass; record the intake Notes fallback and let Planning
`set-focus` then `--ref` this item.

### D3 — `set-focus` does not mutate strategy

ISSUE-0069 / ISSUE-0040 already rewrite `current_focus.spec_path` on retarget.
This scope does not also clear `implementation_strategy` on `set-focus`.
Stale leftover is detected by readers (D4). Keeps CHANGE-0100 / CHANGE-0107
writer ownership of that block on `set-strategy` only.

### D4 — readers: mismatch is stale; missing `ref_id` is legacy

When `implementation_strategy.ref_id` is non-null AND `current_focus.ref_id`
is non-null AND they differ, the strategy does not apply to the live focus:

- `lane-gate.mjs` `readStrategy`: `ok=false` (fail-closed HEAVY). Leftover
  `untested` MUST NOT select the fast lane.
- `orchestration-dispatch.mjs`: treat `strategy_selected` as `undecided`
  (rule 7 → Planning). Do not dispatch TDD/Implementation on another item's
  lane.
- SKILL_TDD Phase 0 step 5, IMPLEMENTATION step 4, VALIDATION
  STRATEGY-CONDITIONAL EVIDENCE: behave as `undecided`. Do not hand off to
  the no-tests lane, do not skip RED, do not skip RED-proof, for another
  item's selected value.

When `ref_id` is absent or `null`: honor `selected` as today (legacy STATE
and every pre-change fixture).

### D5 — untested-rationale and R-guard stay

`set-strategy --selected untested` still requires a non-empty `--rationale`
(exit 2 pre-write). R-GUARD (`AAI_ROLE=subagent` refuses mutators) is
untouched. No new `.aai/**` file (no PROFILES.yaml row).

### D6 — out of scope (intake Notes)

A fast path for a small edit of the active uncommitted scope, and an operator
instruction "do not repeat whole TDD" beating ceremony, stay out. File as a
CHANGE after this ownership bug if still needed.

## Implementation strategy
- Strategy: tdd
- Rationale: owner invoked `/aai-ship` with TDD. The defect is a missing
  ownership invariant on a protected writer plus three readers. Only a RED
  observed against leftover `untested` on a retargeted focus, then GREEN
  after the bind, proves the leftover can no longer choose the wrong lane.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: ceremony L3 / protected `state.mjs`. Rule 8 requires an
  explicit user_decision for any recommendation. Autopilot does not record it.
- User decision: inline
- Base ref: main
- Worktree branch/path: none (operator HITL-7 chose inline)
- Inline review scope: `.aai/scripts/state.mjs`,
  `.aai/scripts/lane-gate.mjs`, `.aai/scripts/orchestration-dispatch.mjs`,
  `.aai/templates/STATE_TEMPLATE.yaml`, `.aai/SKILL_TDD.prompt.md`,
  `.aai/IMPLEMENTATION.prompt.md`, `.aai/VALIDATION.prompt.md`,
  `.aai/INTAKE_COMMON.md`, `.aai/SKILL_INTAKE.prompt.md`,
  `.aai/PLANNING.prompt.md`,
  `tests/skills/test-aai-state.sh`, `tests/skills/test-aai-lightweight-lane.sh`,
  `tests/skills/test-aai-orchestration-dispatch.sh`,
  `tests/skills/test-aai-implementation-mode.sh`,
  `tests/skills/lib/prompt-diet-ledger.sh`,
  `tests/skills/test-aai-prompt-diet.sh`,
  `tests/skills/test-aai-r-guard.sh`,
  `docs/knowledge/FACTS.md`,
  `docs/decisions/DECISION-strategy-unscoped-from-current-focus-worktree.md`

## Acceptance Criteria Mapping
- Maps to: docs/issues/ISSUE-0086-strategy-unscoped-from-current-focus.md
  Expected Behavior

## Constitution deviations

- Article 5 (Additive first). Spec-AC-03 newly refuses `set-strategy` when
  neither `--ref` nor `current_focus.ref_id` binds. That is a new failure at
  a public CLI boundary. Justified: the intake requires an unambiguous bind;
  the documented sequence `set-focus` then `set-strategy` (existing suite
  arms) is unchanged and still derives; the CHANGE-0100 intake path
  additionally passes `--ref <this item>` before Planning `set-focus`. The
  refusal is named (`--ref`) and writes nothing (Article 4). It is the
  defect, not a silent incompatibility.

## Acceptance Criteria Status

Never use pipe characters inside cells.

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN set-strategy runs with current_focus.ref_id set and no --ref THEN implementation_strategy.ref_id SHALL equal that focus ref_id | done | docs/ai/tdd/spec-strategy-unscoped-from-current-focus/green-TEST-001-20260928T200005Z.log | — | derive bind; D2; mutation-TEST-001.txt RED |
| Spec-AC-02 | WHEN set-strategy --ref A runs while current_focus.ref_id is B THEN the command SHALL exit 2, stderr SHALL contain disagrees plus both refs, and STATE SHALL be byte-identical | done | docs/ai/tdd/spec-strategy-unscoped-from-current-focus/green-TEST-002-20260928T200005Z.log | — | mismatch refuse; D2; mutation-TEST-002.txt RED |
| Spec-AC-03 | WHEN set-strategy runs with neither --ref nor a non-null current_focus.ref_id THEN the command SHALL exit 2 naming --ref and write nothing | done | docs/ai/tdd/spec-strategy-unscoped-from-current-focus/green-TEST-003-20260928T200005Z.log | — | unbound refuse; D2; mutation-TEST-003.txt RED |
| Spec-AC-04 | WHEN implementation_strategy.ref_id is non-null and differs from current_focus.ref_id THEN lane-gate SHALL NOT treat selected=untested as a fast strategy predicate and orchestration-dispatch SHALL treat strategy_selected as undecided | done | docs/ai/tdd/spec-strategy-unscoped-from-current-focus/green-TEST-004-20260928T200005Z.log | — | reader stale; D4; also green-TEST-005; mutation-TEST-004/005 RED |
| Spec-AC-05 | WHEN implementation_strategy.ref_id is absent or null THEN readers SHALL honor selected as today, AND set-strategy --selected untested without --rationale SHALL still exit 2 with no write | done | docs/ai/tdd/spec-strategy-unscoped-from-current-focus/green-TEST-007-20260928T200005Z.log | — | legacy + untested pin; D4 D5; mutation-TEST-007.txt RED |
| Spec-AC-06 | WHEN SKILL_TDD Phase 0 step 5, IMPLEMENTATION step 4, and VALIDATION STRATEGY-CONDITIONAL EVIDENCE are read THEN each file SHALL name implementation_strategy.ref_id and current_focus.ref_id together and SHALL instruct treating a disagreeing non-null pair as undecided | done | docs/ai/tdd/spec-strategy-unscoped-from-current-focus/green-TEST-006-20260928T200005Z.log | — | prompt readers; diet companion; mutation-TEST-006.txt RED |
| Spec-AC-07 | WHEN intake records set-strategy --source intake --ref NEW while current_focus.ref_id is unset, then Planning set-focus to NEW, THEN the stamp SHALL match NEW (not stale), INTAKE_COMMON SHALL document --ref, and PLANNING SHALL skip later set-strategy only when implementation_strategy.ref_id equals this item's ref_id | done | docs/ai/tdd/spec-strategy-unscoped-from-current-focus/green-TEST-008-20260928T221651Z.log | — | CHANGE-0100 seam; D2; also green-TEST-009; mutation-TEST-008/009 RED |

Status values: planned, implementing, done, deferred, blocked, rejected.

## Implementation plan

1. `.aai/scripts/state.mjs`
   - Add `ref` to `CMD_FLAGS` / `CMD_FLAG_META` for `set-strategy` (optional).
   - Header comment and `--help` grammar gain `[--ref <id>]`.
   - `cmdSetStrategy`: resolve bind = `--ref` else `current_focus.ref_id`
     (via existing `readScalar`). Mismatch → `fail('set-strategy: --ref <A>
     disagrees with current_focus.ref_id <B>')`. Unbound →
     `fail('set-strategy: --ref is required when current_focus.ref_id is unset')`.
     On success `setField` `ref_id` inside the existing block. Keep the
     untested-rationale pre-write refusal unchanged and first.
   - `set-focus` is not edited.
2. `.aai/templates/STATE_TEMPLATE.yaml` body (not the comment header): add
   `ref_id: null` under `implementation_strategy`. Do not edit the leading
   `#` header (test-aai-check-state header-parity).
3. `.aai/scripts/lane-gate.mjs` `readStrategy`: after locating `selected`,
   also read `ref_id` in the same block and `current_focus.ref_id`. If both
   are non-null and differ, return `{ value, ok: false }`. Missing `ref_id`
   keeps today's `ok = FAST_STRATEGIES.has(v)`.
4. `.aai/scripts/orchestration-dispatch.mjs` snapshot builder (around the
   `implementation_strategy.selected` `readScalar`): if strategy `ref_id` and
   `current_focus.ref_id` are both non-null and differ, set `strategy_selected`
   to `undecided`. Do not change `decide()`.
5. Prompts — one short STALE BINDING bullet each, naming both field paths and
   the `undecided` fallback:
   - `.aai/SKILL_TDD.prompt.md` Phase 0 step 5
   - `.aai/IMPLEMENTATION.prompt.md` step 4
   - `.aai/VALIDATION.prompt.md` STRATEGY-CONDITIONAL EVIDENCE
6. Tests
   - `tests/skills/test-aai-state.sh`: `test_079` (stamp/derive), `test_080`
     (mismatch), `test_081` (unbound). Register in `main()`. `log_fail` /
     `log_pass` lines MUST contain the spec-local `TEST-001` / `TEST-002` /
     `TEST-003` tokens. `t76_flags_for set-strategy` gains `--ref`.
   - `tests/skills/test-aai-lightweight-lane.sh`: leftover `untested` +
     disagreeing `ref_id` → `LANE heavy` (not `strategy=untested ok`).
   - `tests/skills/test-aai-orchestration-dispatch.sh`: same leftover →
     rule 7 Planning, not 9c Implementation.
   - `tests/skills/test-aai-implementation-mode.sh`: grep the three prompts
     for both field paths.
8. CHANGE-0100 intake bind (validation B1 / Spec-AC-07):
   - `.aai/INTAKE_COMMON.md` recording command gains `--ref <this intake's ref_id>`
     plus a Notes fallback when a live other focus `disagrees`.
   - `.aai/SKILL_INTAKE.prompt.md` STEP 2.7 names that `--ref`.
   - `.aai/PLANNING.prompt.md` skips later `set-strategy` only when
     `implementation_strategy.ref_id equals this item's ref_id`; Notes path
     passes `--ref <this REF-ID>`.
   - Do not weaken Spec-AC-03 unbound refuse or Spec-AC-02 mismatch refuse.
7. Prompt-diet companion: measure `.aai/*.prompt.md` growth, append one
   `JUSTIFIED_ADDITIONS` entry, bump `want_growth` in TEST-012 by the same
   integer. No new `.aai/**` file.

`tests/skills/test-aai-state.sh` existing arms stay green because bind
derives from the fixture focus (`CHANGE-0001`) and extra `ref_id` lives
inside the mutated block (TEST-020 locality).

Do not close `fu-lanegate-readstate-duplicate`: this scope adds a match
predicate inside the existing `readStrategy`; it does not collapse
`readStrategy` with `resolveDefaultSpecFromState`.

## Seams

- S1 — writer `set-strategy` stamps `ref_id`; lane-gate `readStrategy` consumes
  it. TEST-004 produces on the writer fixture and asserts the lane-gate
  verdict, not a mocked reader.
- S2 — same leftover STATE, orchestration-dispatch `strategy_selected`.
  TEST-005.
- S3 — prompt readers vs the machine readers. Prompts cannot be executed;
  TEST-006 greps the load-bearing field names. Residual: an agent can ignore
  the bullet. The scripts are the hard gate for dispatch and the PR lane.
- S4 — CHANGE-0100 intake `set-strategy --ref` before Planning `set-focus`.
  TEST-008 produces on the writer; TEST-009 greps INTAKE_COMMON, SKILL_INTAKE,
  and PLANNING. Residual: an agent can skip `--ref`; the CLI refuse (Spec-AC-03)
  then surfaces instead of a silent mis-bind.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected) | Description | Mutation | Status |
|----------|------------|-------------|----------------------|-------------|----------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-state.sh | set-strategy without --ref writes ref_id equal to current_focus.ref_id | sed:s/setField\(bl, 2, 'ref_id', \[scalarLine\(2, 'ref_id', yq\(bindRef\)\)\]\);/void 0;/ | green |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-state.sh | set-strategy --ref A with focus B exits 2, names disagrees, byte-identical | sed:s/explicitRef !== focusRef/false && explicitRef !== focusRef/ | green |
| TEST-003 | Spec-AC-03 | unit        | tests/skills/test-aai-state.sh | set-strategy with no --ref and null focus ref exits 2 naming --ref, no write | sed:s/current_focus.ref_id is unset/current_focus.ref_id is optional/ | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-lightweight-lane.sh | leftover untested with disagreeing ref_id is HEAVY, not fast | sed:s/stratRef !== focusRef/false && stratRef !== focusRef/ | green |
| TEST-005 | Spec-AC-04 | integration | tests/skills/test-aai-orchestration-dispatch.sh | leftover untested with disagreeing ref_id yields rule 7 Planning | sed:s/stratRef !== focusRef/false && stratRef !== focusRef/ | green |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-implementation-mode.sh | SKILL_TDD, IMPLEMENTATION, VALIDATION each name both field paths and undecided-on-mismatch | sed:s/implementation_strategy.ref_id/implementation_strategy.selected/ | green |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-state.sh | test_061 untested-without-rationale still exit 2; missing ref_id still honored by lane-gate | sed:s/untested requires a non-empty --rationale/untested allows an empty --rationale/ | green |
| TEST-008 | Spec-AC-07 | integration | tests/skills/test-aai-state.sh | intake --ref NEW with unset focus then set-focus NEW keeps matching stamp | sed:s/explicitRef !== undefined \? explicitRef : focusRef/focusRef/ | green |
| TEST-009 | Spec-AC-07 | integration | tests/skills/test-aai-implementation-mode.sh | INTAKE_COMMON/SKILL_INTAKE document --ref; PLANNING skips only a matching stamp | sed:s/--ref <this intake's ref_id>// | green |

Prompt-diet TEST-010/TEST-012 are Verification commands for Spec-AC-06, not a
separate Test Plan row (the ledger key does not exist until GREEN measures
it; a placeholder mutation cell would be vacuous at freeze).

RED is observed FIRST for TEST-001..007 against the pre-change tree (or
against a fabricated leftover STATE for the reader rows). Each RED run is
stored under `docs/ai/tdd/spec-strategy-unscoped-from-current-focus/`.

## Verification
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-state.sh test_079` exits 0 and prints TEST-001.
- Same wrapper, `test_080` / TEST-002, `test_081` / TEST-003, `test_061` / TEST-007.
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-state.sh` exits 0 (existing suite green).
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-lightweight-lane.sh` exits 0 with the new leftover-untested arm.
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-orchestration-dispatch.sh` exits 0 with the new stale-strategy arm.
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-implementation-mode.sh` exits 0.
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-state.sh test_083` exits 0 and prints TEST-008.
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-implementation-mode.sh test_009_intake_bind_ref_before_focus` exits 0 and prints TEST-009.
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh` TEST-010 and TEST-012 exit 0.
- `node .aai/scripts/mutation-run.mjs` produces a RED record per Test Plan row
  and `node .aai/scripts/mutation-gate.mjs` exits 0 at close.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
- ref_id: strategy-unscoped-from-current-focus
- Spec-AC and TEST-xxx links per row above.
- Commands and exit codes as listed under Verification.
- Evidence paths: `docs/ai/tdd/spec-strategy-unscoped-from-current-focus/` RED
  and GREEN logs per TEST-xxx, mutation records under `docs/ai/mutation/`.
- Diff range: `main..cursor/strategy-unscoped-from-current-focus-a7ce`.

### Evidence by strategy

Strategy is `tdd`, so this spec demands a stored RED artifact per AC-gating
test plus the full verification matrix above.

## Registry items closed by this scope

none.

`node .aai/scripts/follow-ups.mjs list` (140 open) has no item on this
subject. Nearest class-sibling: `fu-lanegate-readstate-duplicate` (collapse
two lane-gate STATE readers). Not closed here — see Implementation plan.

## Residual risks

- R1 — prompt readers can be ignored by an agent that does not re-read Phase 0
  / step 4. Dispatch and lane-gate are the hard gates. S3.
- R2 — legacy STATE without `ref_id` still applies a leftover `selected`
  after `set-focus`. That is D4 on purpose (Article 5). The leftover is
  disarmed only after the next `set-strategy` stamps a ref. Operators who
  never call `set-strategy` after this ships keep today's bug until they do.
- R3 — prompt-diet TEST-012 `want_growth` is measured at GREEN. A wrong credit
  reddens TEST-012 in Verification, not a Test Plan mutation row.
