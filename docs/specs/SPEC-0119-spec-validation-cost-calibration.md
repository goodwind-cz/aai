---
id: spec-validation-cost-calibration
type: spec
number: 119
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0132-validation-cost-calibration.md
  rfc: null
  pr: []
  commits: []
---

# Spec — Validation cost calibration: lane-scaled depth + capability-detected validator isolation

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0132-validation-cost-calibration.md
- Prior spec (the lane the L0/L1 rule rides): docs/specs/SPEC-0041-spec-loop-ceremony-aware-dispatch.md
- Prior spec (the note-marker grammar this scope extends): docs/specs/SPEC-0089-spec-token-economics-end-to-end.md
- Prior spec (the KPI instrument): docs/specs/SPEC-0117-spec-role-token-trend.md
- Prior spec (validator-model independence): docs/specs/SPEC-0018-spec-model-tiering-with-teeth.md
- Product doc created by this scope: docs/product/validation-cost-calibration.md
- Technology contract: docs/TECHNOLOGY.md

## Summary

Validation is the most expensive phase in the factory (median 99k tokens/run,
18% share; Validation plus Review is 37%). The owner's downstream Codex ride
put ~10:45 of a ~40 min wall clock into independent validation alone. The cost
is not in the thinking — it is in the DUPLICATION: at every ceremony level the
validator re-executes the whole discovered suite, a proof that CI produces
again minutes later on the same commit.

This scope cuts the duplicated work and nothing else. Three levers:

1. The validation canon becomes lane-scaled: on ceremony L0/L1 the validator
   runs the DECLARED scope plus adversarial probes on the seams and does NOT
   run a blanket full-suite re-execution. L2/L3 depth is untouched. Every
   independence, adversarial-stance, AC-status-gate and evidence rule is
   untouched at every level.
2. Validator isolation stops being negotiated per harness name and starts
   being resolved from DETECTED capabilities. The owner's source-level
   correction is the trigger: current Codex CLI HAS native sub-agents
   (`spawn_agent(task_name, message, fork_turns, model, reasoning_effort)`,
   `fork_turns="none"` passing no surrounding context, per-child model
   override, `agents.default_subagent_model`, children spawning children), but
   the subagent model catalog is narrower than the top level and explicit
   overrides have historically been dropped (CLI ~0.145.0), and MultiAgentV1
   vs V2 differ. Capabilities are therefore DETECTED at runtime and the
   granted model VERIFIED — never assumed, and never keyed on a
   `harness == codex` string table.
3. Telemetry stops assuming the override took. When a model override is
   requested for a role, the run note records the requested and the actual
   model, so a silently-dropped override is visible in METRICS instead of
   being read as independence that never happened.

The change is prose plus one shared library plus tests. It deliberately does
NOT touch `.aai/scripts/state.mjs` (see "L3 avoidance" below).

## Pre-registered KPI (AC-005 — recorded before implementation)

Validation median tokens/run decreases while ride remediation rate does not
increase, read from the Role consumption section of the factory report
(SPEC-0117) after approximately 5 rides. A regression on either half is a
rollback of the lane rule.

Instrument: `node .aai/scripts/generate-factory-report.mjs`, section
`Role consumption`, row `Validation`, column `Median tokens/run` (overall and
the weekly table); remediation rate from the same report's
`remediation_distribution`. Baseline at freeze: Validation median 99k
tokens/run, 18% share, Validation plus Review 37%. Rollback action: revert the
CEREMONY LANE prohibition clause in `.aai/VALIDATION.prompt.md` to the
pre-change permissive wording; the capability-detection and telemetry work
(Spec-AC-02 to Spec-AC-04) is independently useful and is NOT rolled back with
it.

Honesty note: this KPI cannot be evaluated inside this ride. It is a
post-merge measurement, recorded here as the flip/rollback rule and carried as
an accepted residual risk below.

## L3 avoidance (recorded decision)

`protected_paths_l3` (docs/ai/docs-audit.yaml) lists `.aai/scripts/state.mjs`,
`lib/state-engine.mjs`, `lib/state-core.mjs`, `allocate-doc-number.mjs`, the
pre-commit guards, `.aai/workflow/WORKFLOW.md` and `docs/CONSTITUTION.md`.
None of them is in this scope's file list, so the declared level is 2:

- Spec-AC-04 is delivered as a NOTE-GRAMMAR extension in
  `.aai/scripts/lib/usage-note.mjs`, not a `state.mjs` schema change.
  `state.mjs append-run --note <t>` already accepts free text and
  `metrics-flush.mjs` already copies the note verbatim into
  `METRICS.jsonl` (`out.note = r.note`), so the markers reach METRICS with
  zero state-engine edits. Had the design required a new `append-run` flag or
  a new run field, that would be an L3 escalation and this spec would have
  stopped and said so instead of planning the edit.
- `.aai/VALIDATION.prompt.md` and `.aai/SUBAGENT_PROTOCOL.md` are NOT in
  `protected_paths_l3` (verified against the live list).
- `.aai/workflow/WORKFLOW.md` IS L3 and is NOT edited. Its "Ceremony levels"
  table already scales validation depth by level (L0 "required — suite run",
  L1 "required — suite re-run + targeted probe", L2/L3 full independent
  validation), which the lane rule refines rather than contradicts; the
  validation canon owns depth, the table owns the level map. If a reviewer
  judges the L0/L1 cells to CONFLICT with the new prohibition, that is an L3
  escalation to be raised to the operator — never a silent edit to WORKFLOW.md
  inside this ride.
- `.aai/ORCHESTRATION.prompt.md` is not edited either. It is a thin wrapper
  (40 lines against the 45-line ceiling pinned by test-aai-prompt-diet.sh
  TEST-011) that already routes the orchestrator to
  `.aai/SUBAGENT_PROTOCOL.md` for how to spawn a role, which is exactly where
  the capability contract lands. Adding the contract there instead of in the
  wrapper keeps the wrapper thin and costs zero prompt-diet bytes.

## Corpus sweep performed at planning (input to Spec-AC-03)

`grep -rniE '(no subagent|cannot spawn|does not support (subagent|spawn|concurrent))'`
over the repository returns NO instance of a "Codex has no subagents" claim.
What exists is two different shapes:

- Harness-NEUTRAL capability fallbacks: `.aai/VALIDATION.prompt.md` lines 6,
  22 and 235; `.aai/IMPLEMENTATION.prompt.md` lines 6 and 117;
  `.aai/SUBAGENT_PROTOCOL.md` lines 20, 109 and 234;
  `.aai/ORCHESTRATION_PARALLEL.prompt.md` line 158; `.aai/SKILL_LOOP.prompt.md`
  lines 309 to 312. None names a harness; each is a legitimate
  "if the capability is absent" clause. They stay. What they lack — and what
  Spec-AC-02 supplies — is HOW absence is established.
- One harness-NAMED but non-denying bullet: `.aai/SUBAGENT_PROTOCOL.md` line
  103, "Other in-session hosts (Codex, Gemini, …): use that host's
  subagent/task primitive with the same INPUT contract and a distinct model
  where available." It is vague rather than wrong, and it is the bullet the
  Spec-AC-03 hierarchy REPLACES.

Spec-AC-03 therefore delivers the replacement plus a standing corpus negative
control (TEST-006) so the assumption cannot re-enter. The audit rows in
`docs/analysis/unhobbling-audit.md` that propose DELETING the neutral
fallbacks outright are a different, larger scope and are not executed here.

## Implementation strategy
- Strategy: hybrid
- Rationale: Spec-AC-04 is real executable code (regex grammar plus extractors
  in a shared library with four existing consumers) and Spec-AC-05 is a
  numeric ledger pin — both are cheap to observe RED first and expensive to
  get silently wrong, so they take the TDD lane. Spec-AC-01 to Spec-AC-03 and
  Spec-AC-06 are canon prose and a product doc verified by grep and
  section-presence pins; those take the loop lane, with the RED observation
  still recorded (the pins fail on the pre-change tree by construction).

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: the file list is small and touches no protected surface,
  but it edits shared canon (`.aai/VALIDATION.prompt.md`,
  `.aai/SUBAGENT_PROTOCOL.md`) and a shared library
  (`.aai/scripts/lib/usage-note.mjs`) that four scripts import, so isolation
  is useful if any other ride is in flight. Implementation Preparation asks
  and decides.
- User decision: undecided
- Base ref: feat/validation-cost-calibration
- Worktree branch/path: <if selected>
- Inline review scope: .aai/VALIDATION.prompt.md .aai/SUBAGENT_PROTOCOL.md .aai/scripts/lib/usage-note.mjs tests/skills/test-aai-validator-isolation.sh tests/skills/test-aai-ceremony-levels.sh tests/skills/test-aai-token-capture.sh tests/skills/test-aai-metrics.sh tests/skills/test-aai-prompt-diet.sh tests/skills/lib/prompt-diet-ledger.sh tests/skills/suite-map.yaml tests/skills/test-aai-product-docs.sh docs/product/validation-cost-calibration.md

## Acceptance Criteria Mapping

- Maps to: CHANGE-0132 AC-001
  - Spec-AC-01: the validation canon states the lane-scaled depth rule and the
    dispatch already surfaces the lane it keys on.
  - Verification: `bash tests/skills/test-aai-ceremony-levels.sh`; observables
    are the grep pins inside the awk-extracted CEREMONY LANE block and the
    rule-11 dispatch JSON fields.
- Maps to: CHANGE-0132 AC-002
  - Spec-AC-02: the subagent protocol carries a runtime capability-detection
    contract over four named fields, with an explicit ban on harness-name
    string matching.
  - Verification: `bash tests/skills/test-aai-validator-isolation.sh`;
    observables are the four field names in the new section plus a corpus
    negative control returning zero hits.
- Maps to: CHANGE-0132 AC-003
  - Spec-AC-03: the four-tier isolation fallback hierarchy is documented in
    order and keyed on detected capabilities; no corpus file asserts a named
    harness lacks subagents.
  - Verification: `bash tests/skills/test-aai-validator-isolation.sh`;
    observables are the ordered tier tokens and a zero-hit corpus sweep.
- Maps to: CHANGE-0132 AC-004
  - Spec-AC-04: `lib/usage-note.mjs` gains a requested/actual model marker
    grammar, single-sourced, boundary-disciplined, surviving the flush into
    METRICS.jsonl.
  - Verification: `bash tests/skills/test-aai-token-capture.sh` and
    `bash tests/skills/test-aai-metrics.sh`; observables are extractor return
    values, a one-file grep count, and the note text read back out of a real
    METRICS.jsonl line.
- Maps to: CHANGE-0132 AC-005
  - Spec-AC-05: the prompt-corpus growth rides the diet ledger at MEASURED
    bytes with the pin re-summed and headroom in range, and this spec records
    the pre-registered KPI verbatim.
  - Verification: `bash tests/skills/test-aai-prompt-diet.sh` and
    `bash tests/skills/test-aai-ceremony-levels.sh`; observables are the
    suite's own headroom line and the KPI grep pin.
- Maps to: close-time product-doc gate (user_visible intake)
  - Spec-AC-06: the user-visible scope ships its product doc with all required
    sections non-placeholder.
  - Verification: `bash tests/skills/test-aai-product-docs.sh`; observable is
    `missingProductSections()` returning an empty list.

## Constitution deviations

- Article 5 (Additive first) — the Spec-AC-01 lane rule is NOT purely
  additive at the L0/L1 public boundary: it converts a permissive clause
  ("the full-repository sweep is NOT required") into a prohibition ("do not
  run a blanket full-suite re-execution"), which narrows what a lightweight
  validation may do. Justified and explicit per the article's own escape
  clause: the change is documented here, pinned by TEST-001, carries a
  pre-registered KPI with a named rollback action, and the full-suite proof it
  removes still lands in CI on the same commit (close-before-CI ordering), so
  no evidence is lost — only a duplicate execution of it. L2/L3 behavior is
  byte-unchanged, and the fail-closed default (absent or garbage
  ceremony_level resolves to full) is untouched.
- Article 3 (Portability) — NOT deviated, and the point is worth stating:
  Spec-AC-02 exists precisely so tri-platform behavior is resolved from
  detected capabilities rather than a Claude/Codex/Gemini string table. The
  literal `codex exec -m <model>` appears only as a named EXAMPLE of tier 3's
  host-equivalent headless invocation, never as a branch condition.
- Articles 1, 2, 4, 6, 7 — no deviation.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the CEREMONY LANE block of .aai/VALIDATION.prompt.md is read THEN it states that on lane.selected lightweight the validator runs the declared test scope plus adversarial probes on the seams and does NOT run a blanket full-suite re-execution, names close-before-CI ordering as the reason the full-suite proof still exists, and leaves the L2/L3 full-depth clause and the fail-closed default unchanged; AND the rule-11 Validation dispatch continues to surface lane.validation_depth declared_scope with reason lightweight_lane_declared_scope on L0/L1 | done | 345305d | — | dispatch side is a regression pin, no code change; TEST-001 (test_015 extension) + TEST-002 (pre-existing test_012_validation_dispatch_payload) both green |
| Spec-AC-02 | WHEN .aai/SUBAGENT_PROTOCOL.md is read THEN it carries a capability-detection contract naming multi_agent_backend, spawn_agent_available, spawn_model_catalog and fork_turns_supported, states they are resolved AT RUNTIME by the orchestrating agent before the first dispatch and re-resolved when a spawn call is refused, states that an unknown capability fails closed to the next isolation tier, and states that behavior is keyed on detected capabilities and NOT on harness name equality; AND no file under .aai/ gates subagent behavior on a harness-name equality test | done | 0082691 | — | AC-002 explicitly bans harness == X tables; TEST-003/TEST-004 green in tests/skills/test-aai-validator-isolation.sh |
| Spec-AC-03 | WHEN .aai/SUBAGENT_PROTOCOL.md "Spawning a validator" is read THEN it documents four isolation tiers IN ORDER — native spawn_agent with a different model and fork_turns none, spawn_agent retried with an available spawn_model_catalog model when the requested one is rejected, a separate role-per-invocation process such as codex exec -m as hard isolation, and in-parent-session execution as LAST resort with a recorded residual risk — and requires the orchestrator to VERIFY the granted model rather than assume the override took; AND no file under .aai/ asserts that a named harness lacks subagents or cannot spawn | done | 0082691 | — | replaces the vague "other in-session hosts" bullet; TEST-005/TEST-006 green in tests/skills/test-aai-validator-isolation.sh |
| Spec-AC-04 | WHEN a run note carries requested_model and actual_model markers THEN .aai/scripts/lib/usage-note.mjs extracts both with the same both-sides boundary discipline as USAGE_NOTE_RE, accepts a bracketed context-window id such as claude-opus-4-8 with a 1m suffix, returns null for a prefixed key or an empty or malformed value, and reports a dropped override when the two differ; AND the raw literal of each new regex exists in exactly one source file; AND a note carrying both markers alongside usage_total_tokens survives append-run and metrics-flush into METRICS.jsonl with extractUsageTotal still returning the total; AND .aai/SUBAGENT_PROTOCOL.md states that model_id records the GRANTED model, that both markers are recorded whenever an override was requested, and that validator-independence claims cite actual_model | done | 7d725ed | — | note-grammar path; state.mjs untouched (L3 avoided); TEST-007/TEST-008/TEST-009/TEST-010 all green |
| Spec-AC-05 | WHEN the prompt corpus grows by this scope THEN tests/skills/lib/prompt-diet-ledger.sh carries one JUSTIFIED_ADDITIONS entry whose byte figure is the MEASURED delta of the in-glob files, the test-aai-prompt-diet.sh TEST-012 pin equals the independent re-sum of the ledger, and TEST-010 headroom stays within 0 to 2048; AND this spec records the pre-registered KPI sentence and its rollback action verbatim | done | 345305d | — | measured +466 B (17407 -> 17873), credited 1:1, headroom unchanged 1150/2048; TEST-011 (suite TEST-012 pin) + TEST-012 (suite TEST-019 KPI pin) green |
| Spec-AC-06 | WHEN the close-time product-doc gate evaluates this user_visible scope THEN docs/product/validation-cost-calibration.md exists with What it does, Data model, and Interfaces and contracts all present and non-placeholder, so missingProductSections returns an empty list | done | f04ee0f | — | intake carries user_visible true and no capability override, so the gate resolves docs/product/<slug>.md; TEST-013 (suite TEST-014) green |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components/modules affected:

- `.aai/VALIDATION.prompt.md` — the CEREMONY LANE block gains the prohibition,
  the adversarial-seam-probe obligation and the close-before-CI rationale. The
  new prose MUST live between the literal line start `CEREMONY LANE` and the
  literal line `PROCESS` (the existing test extracts the block with
  `awk '/^CEREMONY LANE/{f=1} /^PROCESS$/{f=0} f'`; prose outside those
  boundaries is invisible to the pin). The INDEPENDENCE REQUIREMENT block's
  "cannot spawn a separate validator" clause gains a one-line pointer to the
  SUBAGENT_PROTOCOL isolation hierarchy so in-parent execution is reached as
  tier 4, not as the first fallback. This is the ONLY in-glob file in the
  scope — every byte added here is measured for Spec-AC-05.
- `.aai/SUBAGENT_PROTOCOL.md` — new "Capability detection (runtime, never a
  harness table)" section; the "Spawning a validator in a separate agent"
  bullet list is rewritten as the four ordered tiers; the "Harness-reported
  usage capture" section gains the requested/actual model rule. Outside
  TEST-010's `.aai/*.prompt.md` glob AND outside its extra accounting
  (INTAKE_COMMON, STATE_FALLBACK, ROLE_COMMON only) — zero ledger cost, the
  same treatment CHANGE-0061 and SPEC-0113 applied.
- `.aai/scripts/lib/usage-note.mjs` — add `REQUESTED_MODEL_RE`,
  `ACTUAL_MODEL_RE`, `extractRequestedModel()`, `extractActualModel()`,
  `modelOverrideDropped()`. `USAGE_NOTE_RE`, `USAGE_SENTINEL_RE`,
  `CANONICAL_ROLES` and `normalizeRole` are byte-unchanged.
- `tests/skills/test-aai-validator-isolation.sh` — NEW suite (Spec-AC-02 and
  Spec-AC-03), plus its required row in `tests/skills/suite-map.yaml` (the
  hygiene pin in test-aai-hygiene-pack.sh fails a suite with no row).
- `tests/skills/test-aai-ceremony-levels.sh`, `test-aai-token-capture.sh`,
  `test-aai-metrics.sh`, `test-aai-prompt-diet.sh`,
  `tests/skills/lib/prompt-diet-ledger.sh`, `test-aai-product-docs.sh` — new
  cases and the ledger true-up.
- `docs/product/validation-cost-calibration.md` — NEW product doc.

Data flows:

The marker grammar is single-sourced in `lib/usage-note.mjs` and travels
`state.mjs append-run --note` (free text, no schema change) into
`docs/ai/STATE.yaml`, then `metrics-flush.mjs` copies the note verbatim into
`docs/ai/METRICS.jsonl` `agent_runs[].note`, where `metrics-report.mjs`,
`generate-overview.mjs`, `generate-factory-report.mjs` and
`close-work-item.mjs` already read the same field for `usage_total_tokens`.
The new markers ride that existing pipe.

Marker grammar (decided here so implementation does not invent it):

- `requested_model=<id>` and `actual_model=<id>`, both delimited on BOTH
  sides exactly like `USAGE_NOTE_RE` — left `(?:^|[\s"'(\[])`, right
  `(?=$|[\s"'),\].;])`.
- `<id>` is a base id `[A-Za-z0-9][A-Za-z0-9._:@/+-]*` plus an OPTIONAL
  bracketed context-window suffix `(?:\[[A-Za-z0-9._-]+\])?`. The suffix is
  required because `claude-opus-4-8[1m]` is a real recorded model id and the
  bare `USAGE_NOTE_RE` right-boundary class does not admit `[`.
- Both markers are recorded TOGETHER whenever an override was requested, even
  when they are equal — an equal pair is the positive evidence the override
  took, and its absence must not be readable as either outcome.
- `append-run --model` keeps recording the ACTUAL granted model, so pricing
  and `cost_usd` stay honest; the note is where the REQUEST is preserved.

Edge cases:

- Prefixed key (`not_requested_model=x`) and empty value
  (`requested_model=`) never match, by the same boundary discipline that
  already rejects `not_usage_total_tokens=456`.
- A note carrying all three markers must not perturb `extractUsageTotal` —
  covered by TEST-009, not by inspection.
- Scope-decision, OUT: `generate-factory-report.mjs` rendering of the
  requested/actual split. AC-004's requirement is that a dropped override be
  VISIBLE IN METRICS, which the note pass-through already delivers and TEST-009
  proves end to end; the "reports must cite actual_model" clause binds the
  validation report and the independence claim, which is prose in
  `.aai/SUBAGENT_PROTOCOL.md` (TEST-010). Adding an HTML column would grow the
  most-consumed generator for a signal with zero recorded instances today.
  Recorded as a follow-up candidate, not carried here.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                          | Description | Status |
|----------|------------|-------------|-----------------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-ceremony-levels.sh      | Extend test_015: the awk-extracted CEREMONY LANE block prohibits a blanket full-suite re-execution at lightweight, mandates the declared scope plus adversarial seam probes, and names the close-before-CI ordering as why the full-suite proof still exists; the existing fail-closed, declared and lane.selected pins still hold | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-ceremony-levels.sh      | Regression pin over the real orchestration-dispatch.mjs on a fixture STATE plus spec: a rule-11 Validation dispatch at ceremony_level 0 and 1 emits lane.validation_depth declared_scope and reasons containing lightweight_lane_declared_scope, and at 2 and 3 emits full without that reason | green |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-validator-isolation.sh  | The SUBAGENT_PROTOCOL capability-detection section names all four fields multi_agent_backend, spawn_agent_available, spawn_model_catalog and fork_turns_supported, and states runtime resolution, re-resolution after a refused spawn, and fail-closed-on-unknown | green |
| TEST-004 | Spec-AC-02 | unit        | tests/skills/test-aai-validator-isolation.sh  | Corpus negative control over .aai/ excluding scripts comments: zero hits for a harness-name equality test gating subagent behavior, matching harness followed by an equality operator and a quoted or bare claude, codex or gemini | green |
| TEST-005 | Spec-AC-03 | unit        | tests/skills/test-aai-validator-isolation.sh  | The four isolation tiers appear in the Spawning a validator section IN FILE ORDER carrying their required tokens spawn_agent, fork_turns, the alternate spawn_model_catalog retry, codex exec -m, and the last-resort in-parent execution with a recorded residual risk; plus the verify-the-granted-model clause | green |
| TEST-006 | Spec-AC-03 | unit        | tests/skills/test-aai-validator-isolation.sh  | Corpus sweep over .aai/ for a named-harness subagent denial, matching claude, codex or gemini within a short span of has no, have no, no native, cannot spawn or does not support followed by subagent or spawn; expected zero hits | green |
| TEST-007 | Spec-AC-04 | unit        | tests/skills/test-aai-token-capture.sh        | extractRequestedModel and extractActualModel return the id for a plain id and for a bracketed context-window id, return null for a prefixed key, an empty value and a malformed value, and modelOverrideDropped is true only when both are present and differ | green |
| TEST-008 | Spec-AC-04 | unit        | tests/skills/test-aai-metrics.sh              | Single-source grep contract extension alongside test_120: the raw literal of each new marker regex exists in exactly one file under .aai/scripts and that file is lib/usage-note.mjs | green |
| TEST-009 | Spec-AC-04 | integration | tests/skills/test-aai-token-capture.sh        | SEAM: state.mjs append-run writes a note carrying requested_model, actual_model and usage_total_tokens into a fixture STATE, metrics-flush.mjs flushes it, and the resulting METRICS.jsonl agent_runs note still yields the total from extractUsageTotal and both model ids from the new extractors | green |
| TEST-010 | Spec-AC-04 | unit        | tests/skills/test-aai-token-capture.sh        | SUBAGENT_PROTOCOL prose pin: the usage-capture section states that model_id records the granted model, that both markers are recorded whenever an override was requested, and that validator-independence claims cite actual_model | green |
| TEST-011 | Spec-AC-05 | unit        | tests/skills/test-aai-prompt-diet.sh          | The diet ledger carries a validation-cost-calibration JUSTIFIED_ADDITIONS entry, the suite's own TEST-012 pin equals the independent re-sum of the array, and the suite's own TEST-010 headroom is within 0 and 2048 inclusive against the live corpus | green |
| TEST-012 | Spec-AC-05 | unit        | tests/skills/test-aai-ceremony-levels.sh      | The lane rule's spec, matched by the glob docs/specs/*validation-cost-calibration.md so it survives the merge-time rename, records the pre-registered KPI sentence and the named rollback action | green |
| TEST-013 | Spec-AC-06 | integration | tests/skills/test-aai-product-docs.sh         | missingProductSections from lib/product-doc.mjs over docs/product/validation-cost-calibration.md returns an empty list, and evaluateProductDocGate severity for a fixture ref carrying this slug and user_visible true is none | green |

Test status values: pending -> red -> green

## Seams crossed

- SEAM-1 — marker grammar to the METRICS ledger: `lib/usage-note.mjs` is
  imported by `metrics-flush.mjs`, `metrics-report.mjs`,
  `generate-overview.mjs`, `generate-factory-report.mjs` and
  `close-work-item.mjs`. Crossed by TEST-009 (real append-run, real flush,
  real METRICS.jsonl read back) — not by two mocked unit tests.
- SEAM-2 — prompt-corpus bytes to the diet gate: growth in
  `.aai/VALIDATION.prompt.md` changes TEST-010's measured reduction and
  therefore the TEST-012 pin. Crossed by TEST-011 against the LIVE corpus.
- SEAM-3 — canon prose to its extraction pin: `test_015` reads the CEREMONY
  LANE block by awk boundaries, so new prose placed outside them would pass
  review and fail the pin. Crossed by TEST-001, which asserts the new clauses
  from inside the extracted block.
- SEAM-4 — canon rule to the deterministic dispatch that feeds it: the lane
  rule is only reachable if the dispatch keeps emitting the lane fields.
  Crossed by TEST-002 against the real script.
- SEAM-5 — new product doc to the close-time gate: crossed by TEST-013 through
  the gate's own library, not by eyeballing the headings.
- SEAM-6 (residual, no automated crossing) — new suite to CI selection: a
  suite with no `suite-map.yaml` row silently escapes selection accounting.
  Not given its own test because `test-aai-hygiene-pack.sh` already owns that
  pin repo-wide; the Verification section runs it explicitly.

## Residual risks (accepted)

- RR-1 — the KPI itself cannot be verified in this ride. Validation median
  tokens/run and remediation rate are post-merge measurements over ~5 rides.
  Mitigation: pre-registered above with a named instrument and a named
  rollback action; no PASS in this ride may claim the cost reduction was
  achieved, only that the lever was installed.
- RR-2 — the capability-detection contract binds an LLM orchestrator in prose.
  There is no runtime probe script that resolves the four fields
  mechanically, so a lazy orchestrator can skip detection and fall to tier 4
  while claiming tier 1. Partial backstop: Spec-AC-04's actual_model marker
  makes a dropped override visible after the fact. A deterministic capability
  probe is a separate, larger scope, deliberately not built here.
- RR-3 — the lane rule reduces what a lightweight validation executes. If the
  close-before-CI ordering is ever broken for a ride, the full-suite proof
  would not land anywhere. Mitigation: the ordering is an existing, separately
  pinned property of the PR ceremony, and the rule cites it explicitly so a
  reviewer can see the dependency.
- RR-4 — `docs/analysis/unhobbling-audit.md` proposes deleting the
  harness-neutral capability fallbacks that this scope leaves in place. The
  two changes could conflict at the same lines later. Accepted: not merged
  into this ride to keep the diff auditable.

## Verification

Commands to run:

- `bash tests/skills/test-aai-ceremony-levels.sh`
- `bash tests/skills/test-aai-validator-isolation.sh`
- `bash tests/skills/test-aai-token-capture.sh`
- `bash tests/skills/test-aai-metrics.sh`
- `bash tests/skills/test-aai-prompt-diet.sh`
- `bash tests/skills/test-aai-product-docs.sh`
- `bash tests/skills/test-aai-hygiene-pack.sh` (suite-map row for the new suite)
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0119-spec-validation-cost-calibration.md`

Evidence artifacts: the RED logs under `docs/ai/tdd/` for the TDD-lane tests
(TEST-007 to TEST-009 and TEST-011), the suite stdout with exit codes for
every command above, the measured before/after byte figures for
`.aai/VALIDATION.prompt.md` (`wc -c`), and the resulting headroom line printed
by test-aai-prompt-diet.sh TEST-010.

PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal
status.

## Evidence contract

For each implementation, validation, TDD, and code review artifact, record:
- ref_id
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

### Evidence by strategy

Strategy is `hybrid`, so the full contract applies: a stored RED artifact per
AC-gating test under `docs/ai/tdd/`, plus the full verification matrix above.
For the loop-lane prose ACs the RED observation is the grep pin failing on the
pre-change tree; record it in the same way.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
