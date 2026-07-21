---
id: spec-hitl-decision-propagation
type: spec
number: 66
status: done
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0020-hitl-decision-propagation.md
  rfc: null
  pr:
    - 122
  commits:
    - 1908a3a27ae4039edcf2bb90e52e4de82be9178c
---

# Spec: HITL resolution propagates the answer to the STATE field it governs

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0020-hitl-decision-propagation.md
- Decision records: docs/ai/decisions.jsonl (HITL entries), docs/CONSTITUTION.md Article 6
- Technology contract: docs/TECHNOLOGY.md

## Problem (one paragraph)

`.aai/ORCHESTRATION_HITL.prompt.md` raises a HITL block whose gate lives in a
`docs/ai/STATE.yaml` field (most visibly `worktree.user_decision`, read by
`orchestration-dispatch.mjs` rule 8). `.aai/SKILL_HITL.prompt.md` STEP 5 and its
STRICT RULES forbid the resolver from writing anything except `human_input`, so the
answer never reaches the gate: the next tick re-raises the same question, or the
SKILL_LOOP stagnation guard halts the loop. The fix must let the answer reach
exactly ONE declared field — and no more.

## Design decision — Option A (prompt-only), REJECTED Option B (schema)

**CHOSEN: Option A — prompt-only, existing typed setters, declared mapping.**
The resolver applies the answer by invoking the EXISTING `.aai/scripts/state.mjs`
typed setters, driven by an explicit trigger→setter mapping table declared in
`.aai/SKILL_HITL.prompt.md`. No STATE schema change, no new CLI flag, no
protected-path edit.

Rationale:
- **Ceremony:** touches only `.aai/SKILL_HITL.prompt.md`,
  `.aai/ORCHESTRATION_HITL.prompt.md`, a new test suite and the diet ledger —
  none of which appear in `protected_paths_l3` (docs/ai/docs-audit.yaml lines
  30-38). Stays `ceremony_level: 2`.
- **Constitution Article 6 (single-writer state):** Option A *strengthens* it —
  every write still goes through `state.mjs`. A new `human_input.decision_target`
  field would add a second concept to the state schema without adding a writer.
- **Constitution Article 2 (YAGNI):** the enums the answers must land in already
  exist (`USER_DECISIONS`, `REVIEW_STATUSES`); a `decision_target` field only
  re-encodes information the trigger id already carries.
- **Constitution Article 5 (additive first):** a mapping table plus a narrowed
  guardrail sentence is additive prompt prose; a schema field is a public-boundary
  change to STATE.

**REJECTED: Option B — add `human_input.decision_target`.** It requires editing
`.aai/scripts/state.mjs`, which IS in `protected_paths_l3`, so
`ceremony_level: 3` would become MANDATORY — and L3 in turn makes the worktree
decision mandatory (dispatch rule 8 `l3_worktree_mandatory`), i.e. the fix for the
broken worktree gate would itself have to pass through the broken worktree gate.
It also buys nothing Option A lacks: Spec-AC-04 gets the same unambiguous target
resolution from a `[HITL-<n>]` token in the existing free-text `blocking_reason`.

## Scope

IN scope:
- `.aai/SKILL_HITL.prompt.md` — trigger→target mapping, narrowed guardrail,
  answer normalization, fail-closed rule, write ordering.
- `.aai/ORCHESTRATION_HITL.prompt.md` — raise side stamps the trigger id.
- `tests/skills/test-aai-hitl-propagation.sh` — new suite (prompt contract +
  deterministic dispatch proof).
- `tests/skills/lib/prompt-diet-ledger.sh` — `JUSTIFIED_ADDITIONS` true-up.

OUT of scope (explicitly):
- Any change to `.aai/scripts/state.mjs`, `orchestration-dispatch.mjs`, or the
  STATE schema. Any new enum value. Any new CLI flag.
- Triggers whose answers do not gate on a STATE field (see mapping below) — they
  keep today's `human_input`-only behavior.

## Trigger → target mapping (the frozen contract)

All 9 `.aai/ORCHESTRATION_HITL.prompt.md` HITL TRIGGERS audited. `none` is an
explicit, asserted verdict — it forbids the resolver from inventing a setter.

| Trigger | Blocking question | STATE gate | Declared target command |
|---------|-------------------|------------|-------------------------|
| `[HITL-1]` | Product intent ambiguity / contradictory requirements | none (answer lands in the intake/spec doc) | none |
| `[HITL-2]` | Technology contract conflict | none (answer lands in docs/TECHNOLOGY.md) | none |
| `[HITL-3]` | Security/privacy risk ambiguity | none | none |
| `[HITL-4]` | Irreversible migration semantics | none | none |
| `[HITL-5]` | Unspecified numeric threshold | none (answer lands in the spec AC) | none |
| `[HITL-6]` | Validation blocked by missing creds/infra | none — `last_validation.status` has NO waiver value (`pass\|fail\|not_run`); forcing `pass` would forge evidence (Article 1) | none |
| `[HITL-7]` | Worktree recommendation unanswered (dispatch rule 8) | `worktree.user_decision` | `node .aai/scripts/state.mjs set-worktree --user-decision <worktree\|inline\|waived>` |
| `[HITL-8]` | Inline review scope dirty/ambiguous | `code_review.scope` (contract field consumed by Code Review; not a dispatch predicate) | `node .aai/scripts/state.mjs set-code-review --scope "<explicit paths or diff range>"` |
| `[HITL-9]` | Code Review BLOCKING findings — fix or waive (dispatch rules 12/13) | `code_review.status` | waive: `node .aai/scripts/state.mjs set-code-review --status waived` · fix: `node .aai/scripts/state.mjs set-code-review --status fail` |

`[HITL-9]` L3 caveat the resolver MUST surface: at `ceremony_level: 3` a recorded
`waived` makes dispatch return `needs_llm l3_review_waived_requires_operator_checkpoint`
— the waiver does not silently proceed.

## Answer normalization (free text → enum) and fail-closed

| Trigger | Accepted answer forms (case-insensitive, trimmed) | Enum written |
|---------|--------------------------------------------------|--------------|
| `[HITL-7]` | `w`, `wt`, `worktree`, "use a worktree", "isolate" | `worktree` |
| `[HITL-7]` | `i`, `inline`, "stay inline", "current tree", "no worktree" | `inline` |
| `[HITL-7]` | `waive`, `waived`, `waiver`, "accept the risk" | `waived` |
| `[HITL-9]` | `waive`, `waived`, `waiver`, "accept", "ship it" | `waived` |
| `[HITL-9]` | `fix`, `remediate`, "fix them" | `fail` (routes rule 12 → Remediation) |
| `[HITL-8]` | any non-empty path list or diff range, verbatim | free text |

FAIL-CLOSED rule (frozen wording obligations):
- An answer that does not map to exactly one enum value is UNMAPPABLE. The
  resolver MUST NOT guess, MUST NOT pick a default, and MUST NOT clear
  `human_input`.
- On UNMAPPABLE: ask ONE targeted follow-up (existing STEP 3 budget). If still
  unmappable, leave the gate unresolved, leave `human_input.required: true`, and
  print `HITL UNRESOLVED` naming the trigger and the accepted forms.
- WRITE ORDERING: apply the target setter BEFORE clearing `human_input`. A crash
  between the two then leaves the block RAISED (safe, re-askable) rather than
  cleared-with-unset-gate (silent, the exact failure this spec fixes).

## Narrowed guardrail (replaces the absolute prohibition)

REMOVED (current text, the observed RED):
- STEP 5 `Do NOT change any other fields.`
- STRICT RULES `Do NOT modify any STATE.yaml field other than human_input and updated_at_utc.`

REPLACED BY (must be present, grep-assertable):
- The resolver may write `human_input` PLUS the ONE declared target field for the
  answered trigger, via the typed `state.mjs` CLI — nothing else.
- The target is read from the mapping table above; a trigger whose target is
  `none` permits NO STATE write beyond `human_input`.
- Never hand-edit `docs/ai/STATE.yaml`; never invent a setter or flag that the
  mapping table does not name.

## Raise side records the trigger (Spec-AC-04 decision)

DECIDED: YES — the raise side records it, as a literal token, not a schema field.
`.aai/ORCHESTRATION_HITL.prompt.md` MUST prefix `human_input.blocking_reason` with
the literal `[HITL-<n>]` token for the firing trigger (existing free-text
`--reason` flag; no schema change). The resolver resolves the target from that
token. If the token is absent (legacy block), the resolver MAY infer the trigger
from `blocking_reason` text, and if inference is not unambiguous it MUST fail
closed per the rule above rather than pick a target.

## Implementation strategy
- Strategy: hybrid
- Rationale: TEST-012 (declared-command → CLI → dispatch seam) and TEST-010/011
  encode real behavior and deserve an observed RED before the prompt edits; the
  remaining prompt-contract greps and the ledger true-up are mechanical wiring
  where RED-GREEN-REFACTOR adds little beyond the mandatory RED-proof.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: four files, no protected path, no migration, no
  cross-cutting refactor — a single logical surface (the HITL prompt pair plus its
  new test suite). Declaring `recommended` would fire dispatch rule 8 and force
  this scope through the very gate it is repairing, while the repair is unlanded.
- User decision: undecided
- Base ref: main
- Worktree branch/path: n/a (branch `fix/hitl-decision-propagation`)
- Inline review scope: `.aai/SKILL_HITL.prompt.md`,
  `.aai/ORCHESTRATION_HITL.prompt.md`,
  `tests/skills/test-aai-hitl-propagation.sh`,
  `tests/skills/lib/prompt-diet-ledger.sh` (diff range `main...HEAD`)

## Acceptance Criteria Mapping

- Maps to: intake "Expected Behavior" bullet 1 + "Verification" bullet 2
  - Spec-AC-01: `.aai/SKILL_HITL.prompt.md` contains a trigger→target mapping row
    for EVERY trigger `[HITL-1]`..`[HITL-9]`; each STATE-gated row names the exact
    typed `state.mjs` command, each non-gated row names the literal `none`.
  - Verification: `bash tests/skills/test-aai-hitl-propagation.sh` TEST-001/002 —
    9 rows found, 3 typed commands matched literally.

- Maps to: intake "Expected Behavior" bullet 2 + "Constraints / Risks" bullet 2
  - Spec-AC-02: the absolute prohibition is GONE and replaced by the narrowed
    guardrail (`human_input` PLUS the ONE declared target field, via the typed
    CLI, nothing else), and the write-ordering rule (target setter BEFORE clearing
    `human_input`) is present.
  - Verification: TEST-003 (old sentences absent), TEST-004 (narrowed wording
    present), TEST-005 (ordering wording present).

- Maps to: intake "Constraints / Risks" bullet 3 (answer normalization)
  - Spec-AC-03: the resolver declares the normalization table and a fail-closed
    rule: an UNMAPPABLE answer writes NO target, leaves `human_input.required:
    true`, and prints `HITL UNRESOLVED`.
  - Verification: TEST-006 (normalization synonyms present), TEST-007 (all three
    fail-closed obligations present).

- Maps to: intake "Verification" bullet 2 (unambiguous target)
  - Spec-AC-04: `.aai/ORCHESTRATION_HITL.prompt.md` stamps `[HITL-<n>]` into
    `blocking_reason`, and `.aai/SKILL_HITL.prompt.md` declares it reads that
    token and fails closed when the trigger is not unambiguously resolvable.
  - Verification: TEST-008 (raise side), TEST-009 (resolve side).

- Maps to: intake "Verification" bullet 1 + bullet 3 (the loop actually advances)
  - Spec-AC-05: with `worktree.recommendation: recommended`, a fixture STATE at
    `user_decision: undecided` dispatches rule 8, and at `user_decision: inline`
    does NOT; and running the command literally extracted from the Spec-AC-01
    mapping row for `[HITL-7]` against the undecided fixture flips it so rule 8
    stops firing.
  - Verification: TEST-010, TEST-011, TEST-012 (exit 0, asserted JSON `rule`).

- Maps to: intake "Constraints / Risks" bullet 4 (prompt-diet floor)
  - Spec-AC-06: `tests/skills/lib/prompt-diet-ledger.sh` carries a new itemized
    `JUSTIFIED_ADDITIONS` entry for this scope and the diet suite is green
    (headroom within `[0, HEADROOM_CAP]`).
  - Verification: TEST-013 exit 0.

- Maps to: intake "Constraints / Risks" bullet 1 (ceremony stays L2)
  - Spec-AC-07: the branch diff touches NO path listed in `protected_paths_l3`,
    and the pre-existing dispatch/state/hitl-adjacent suites stay green.
  - Verification: TEST-014 (empty protected-path intersection), TEST-015 (suites
    exit 0).

## Constitution deviations

None.

- Article 1 (evidence): every AC has an executable command; RED-proof required.
- Article 2 (simplicity): Option A adds no schema, no flag, no enum.
- Article 4 (degrade and report): the fail-closed path reports `HITL UNRESOLVED`
  instead of guessing.
- Article 5 (additive): prompt prose additions; the only REMOVAL is the two
  guardrail sentences the fix exists to narrow, replaced in place.
- Article 6 (single-writer): all propagation goes through `state.mjs`.

## Seam analysis

- SEAM 1 — prompt-declared command string ↔ `state.mjs` CLI ↔
  `orchestration-dispatch.mjs` rule 8. A mapping row could name a flag or enum the
  CLI does not accept, and the greps would still pass. Covered end-to-end by
  **TEST-012**, which EXTRACTS the command text from the prompt, RUNS it against a
  fixture STATE, and asserts the dispatch verdict on the other side — not two
  mocked halves.
- SEAM 2 — `[HITL-<n>]` token written by `ORCHESTRATION_HITL` ↔ read by
  `SKILL_HITL`. Both sides are agent-executed prompts; the contract is asserted by
  TEST-008/TEST-009 on the literal token in both files.
  **RESIDUAL RISK (accepted):** no automated test can prove an LLM resolver
  actually obeys the mapping at runtime. Mitigations: the fail-closed default is
  "leave blocked" (the pre-fix behavior, never worse), and the write-ordering rule
  makes a partial failure re-askable. Manual smoke: resolve one real `[HITL-7]`
  block via `/aai-hitl` and confirm rule 8 stops firing.
- SEAM 3 — prompt corpus ↔ diet ledger. Covered by TEST-013.

## Acceptance Criteria Status

| Spec-AC    | Description                                        | Status  | Evidence | Review-By | Notes |
|------------|----------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | 9-row trigger→target mapping with typed commands   | done | `bash tests/skills/test-aai-hitl-propagation.sh` TEST-001/002 exit 0; docs/ai/reports/green-hitl-decision-propagation-suite-20260721T093249Z.log | — | 9-row table added at `.aai/SKILL_HITL.prompt.md` STEP 4c |
| Spec-AC-02 | Narrowed guardrail replaces absolute prohibition   | done | TEST-003/004/005 exit 0; docs/ai/tdd/red-hitl-decision-propagation-contradiction-20260721T092502Z.log (pre-fix contradiction, `1`/`0`) | — | old sentences removed; narrowed wording + write-ordering rule present |
| Spec-AC-03 | Answer normalization + fail-closed                  | done | TEST-006/007 exit 0 | — | normalization table + UNMAPPABLE/HITL UNRESOLVED wording present |
| Spec-AC-04 | Raise side stamps `[HITL-<n>]`; resolver reads it   | done | TEST-008/009 exit 0 | — | ORCHESTRATION_HITL stamps token; SKILL_HITL declares it reads + fails closed |
| Spec-AC-05 | Dispatch actually advances (rule 8 stops firing)   | done | TEST-010/011 (control, green before+after) + TEST-012 SEAM exit 0 | — | seam test extracts the literal `[HITL-7]` command from the prompt and runs it |
| Spec-AC-06 | Prompt-diet ledger true-up green                    | done | `bash tests/skills/test-aai-prompt-diet.sh` exit 0 (net reduction 28672 B, headroom 0/2048) | — | itemized 4848 B entry appended to `tests/skills/lib/prompt-diet-ledger.sh` |
| Spec-AC-07 | No protected path touched; existing suites green    | done | TEST-014 exit 0 (empty intersection); `test-aai-orchestration-dispatch.sh`/`test-aai-state.sh`/`test-aai-layer-profiles.sh` exit 0 | — | ceremony_level stays 2 |

## Implementation plan

Components affected:
1. `.aai/SKILL_HITL.prompt.md`
   - New STEP 4c (before STEP 5) "PROPAGATE THE DECISION": the mapping table, the
     normalization table, the fail-closed rule, the typed-CLI invocation.
   - STEP 5: replace `Do NOT change any other fields.` with the narrowed guardrail
     and the write-ordering rule (setter first, then clear `human_input`).
   - STRICT RULES: replace the absolute prohibition with the narrowed one.
   - STEP 6 output gains the applied target line; add the `HITL UNRESOLVED` exit.
2. `.aai/ORCHESTRATION_HITL.prompt.md`
   - HITL TRIGGERS list gains the `[HITL-<n>]` tokens.
   - STATE WRITEBACK gains: `blocking_reason` MUST be prefixed with the token.
3. `tests/skills/test-aai-hitl-propagation.sh` (new, bash-3.2, exit 0/1/42,
   scratch `mktemp -d` fixtures, `--state`/`--root` overrides, real runtime files
   never written).
4. `tests/skills/lib/prompt-diet-ledger.sh` — append one itemized
   `JUSTIFIED_ADDITIONS` entry sized from the measured deficit.

Data flow (the fix, end to end):
`ORCHESTRATION_HITL` raises `[HITL-7] …` → `SKILL_HITL` surfaces → human answers
"inline" → normalize → `state.mjs set-worktree --user-decision inline` → clear
`human_input` → next `orchestration-dispatch.mjs` tick: rule 8 no longer matches →
loop advances.

Edge cases:
- Answer maps to no enum → `HITL UNRESOLVED`, block stays raised.
- Answer maps to two enums (e.g. "inline, but waive review") → ambiguous → fail
  closed; ask which gate.
- `blocking_reason` has no token (legacy) → infer; ambiguous → fail closed.
- Trigger target `none` → clear `human_input` only (today's behavior, preserved).
- Setter exits non-zero → do NOT clear `human_input`; report the exit code.
- `[HITL-9]` waiver at ceremony L3 → warn about the operator checkpoint.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-hitl-propagation.sh | All 9 `[HITL-1]`..`[HITL-9]` mapping rows present in SKILL_HITL | green |
| TEST-002 | Spec-AC-01 | unit | tests/skills/test-aai-hitl-propagation.sh | Rows 7/8/9 name the literal typed commands; rows 1-6 name `none` | green |
| TEST-003 | Spec-AC-02 | unit | tests/skills/test-aai-hitl-propagation.sh | Absolute prohibition sentences absent (the observed RED) | green |
| TEST-004 | Spec-AC-02 | unit | tests/skills/test-aai-hitl-propagation.sh | Narrowed guardrail wording present (`ONE declared target field`, `typed`, `nothing else`) | green |
| TEST-005 | Spec-AC-02 | unit | tests/skills/test-aai-hitl-propagation.sh | Write-ordering rule present (setter BEFORE clearing `human_input`) | green |
| TEST-006 | Spec-AC-03 | unit | tests/skills/test-aai-hitl-propagation.sh | Normalization synonyms present for worktree/inline/waived and waive/fix | green |
| TEST-007 | Spec-AC-03 | unit | tests/skills/test-aai-hitl-propagation.sh | Fail-closed trio present: no guess, `human_input.required` stays true, `HITL UNRESOLVED` | green |
| TEST-008 | Spec-AC-04 | unit | tests/skills/test-aai-hitl-propagation.sh | ORCHESTRATION_HITL stamps `[HITL-<n>]` into `blocking_reason` | green |
| TEST-009 | Spec-AC-04 | unit | tests/skills/test-aai-hitl-propagation.sh | SKILL_HITL declares it reads the token and fails closed when ambiguous | green |
| TEST-010 | Spec-AC-05 | integration | tests/skills/test-aai-hitl-propagation.sh | Fixture `recommendation=recommended,user_decision=undecided` → dispatch JSON `rule == "8"` | control (green before+after) |
| TEST-011 | Spec-AC-05 | integration | tests/skills/test-aai-hitl-propagation.sh | Same fixture with `user_decision=inline` → rule 8 does NOT fire | control (green before+after) |
| TEST-012 | Spec-AC-05 | e2e (SEAM 1) | tests/skills/test-aai-hitl-propagation.sh | Extract the `[HITL-7]` command from SKILL_HITL, run it on the undecided fixture, re-dispatch → rule 8 no longer fires | green |
| TEST-013 | Spec-AC-06 | unit | tests/skills/test-aai-prompt-diet.sh | Diet floor + ledger-sum + entry-shape suite green after the prompt edits | green |
| TEST-014 | Spec-AC-07 | unit | tests/skills/test-aai-hitl-propagation.sh | Branch diff ∩ `protected_paths_l3` is empty (L2 stays valid) | green |
| TEST-015 | Spec-AC-07 | integration | tests/skills/test-aai-orchestration-dispatch.sh, tests/skills/test-aai-state.sh | Pre-existing dispatch + state suites stay green | green |

RED-proof obligation (all AC-gating tests): TEST-001..009 are RED today —
`grep -c '\[HITL-' .aai/SKILL_HITL.prompt.md` returns 0 and
`grep -c 'Do NOT modify any STATE.yaml field other than' .aai/SKILL_HITL.prompt.md`
returns 1 (line 98), which is the observed contradiction. TEST-012 is RED today
because the command to extract does not exist. TEST-010/011 are CONTROLS that pass
today (they prove the gate is real, so TEST-012's flip is meaningful) and must be
recorded as `control` rather than claimed as RED evidence.

## Verification

Directly executable commands (each Test Plan row):

```
# TEST-001..012, 014 (new suite)
bash tests/skills/test-aai-hitl-propagation.sh

# RED-proof for TEST-003 (run BEFORE the change; must print 1)
grep -c 'Do NOT modify any STATE.yaml field other than' .aai/SKILL_HITL.prompt.md

# RED-proof for TEST-001 (run BEFORE the change; must print 0)
grep -c '\[HITL-7\]' .aai/SKILL_HITL.prompt.md

# TEST-013
bash tests/skills/test-aai-prompt-diet.sh

# TEST-015
bash tests/skills/test-aai-orchestration-dispatch.sh
bash tests/skills/test-aai-state.sh

# TEST-014 standalone form (must print nothing)
git diff --name-only main...HEAD | grep -x -F -f <(sed -n 's/^  - //p' docs/ai/docs-audit.yaml | head -8)

# Full suite (close gate)
bash .aai/scripts/aai-run-tests.sh
```

Evidence artifacts: suite stdout captured under `docs/ai/tdd/` (RED) and
`docs/ai/reports/` (GREEN), plus the dispatch JSON emitted by TEST-010/011/012.

PASS criteria: all TEST-xxx green AND all Spec-AC terminal AND `ceremony_level: 2`
still correct (TEST-014 empty).

## Evidence contract

Per artifact record: `ref_id: hitl-decision-propagation`; the Spec-AC and TEST-xxx
links; the command or review scope; the exit code or review verdict; the evidence
path; the commit SHA or diff range (`main...HEAD`).
