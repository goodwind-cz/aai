---
id: spec-model-tiering-with-teeth
type: spec
number: 18
status: implementing
links:
  change: CHANGE-0010
  research: RES-0001
  rfc: null
  pr: []
  commits: []
---

# SPEC — Model Tiering With Teeth (dispatch MODEL field, mechanical independence check, live pricing, token capture)

SPEC-FROZEN: true

## Links
- Change: CHANGE-0010 (docs/issues/CHANGE-0010-model-tiering-with-teeth.md)
- Research: RES-0001 finding F2 / recommendation P1.2
  (docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md)
- Naming precedent: SPEC-0016 (`spec-` id prefix avoids PK collision with the
  CHANGE slug `model-tiering-with-teeth`)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (this doc)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: as per template

## Problem (evidence-verified 2026-07-15)
RES-0001 F2: model selection guidance exists only as one prose section in
`.aai/ORCHESTRATION.prompt.md` (lines 121–133) and is enforced nowhere.
Evidence on current main:
1. `.aai/SUBAGENT_PROTOCOL.md` call contract table (ROLE/SCOPE/INPUT/
   EXPECTED_OUTPUT/SYSTEM_PROMPT) has NO MODEL field; the validator section
   only says "Prefer a model different from the implementer's".
2. `.aai/ORCHESTRATION_PARALLEL.prompt.md` contains zero model-tiering text.
3. `state.mjs set-validation` accepts a verdict from any caller with no
   mechanical maker≠checker check (the one recorded violation, RFC-0006, was
   caught post-hoc by a human).
4. `.aai/system/PRICING.yaml` is stale/wrong: `claude-opus-4-6` listed at
   $15/$75 (actual $5/$25), `claude-haiku-4-5` at $0.80/$4.00 (actual $1/$5),
   and NONE of the 5 model ids actually recorded in `docs/ai/METRICS.jsonl`
   history (`claude-opus-4-8[1m]`, `claude-sonnet-4-6`, `claude-sonnet-5`,
   `claude-fable-5`, `deepseek-v4-flash`) resolves: 4 have no entry, and the
   `[1m]` suffix has no normalization rule. `anthropic-pricing.last_verified_utc`
   is null.
5. `append-run` already accepts and persists `--tokens-in/--tokens-out`
   (state.mjs lines 894–912) but callers omit them silently: tokens_in/out are
   null in 100% of METRICS.jsonl runs, so `cost_usd` has never been computed.
6. No `.claude/skills/*/SKILL.md` wrapper carries `model:` frontmatter (0/27).

## Design decisions

### D1 — MODEL is a mandatory dispatch-contract field
`.aai/SUBAGENT_PROTOCOL.md` call contract table gains a required `MODEL` row:
an explicit model id (preferred) or a tier (`mechanical | standard | premium`)
when the platform maps tiers itself. The validator-spawn section is updated
from "Prefer a model different" to: the dispatch MUST record the validator
model, and it MUST differ from the implementer's recorded model whenever the
platform supports model selection (single-model environments record the reuse
as a residual risk). `.aai/ORCHESTRATION_PARALLEL.prompt.md` gains a
`MODEL SELECTION` section with the same tiering text as
`.aai/ORCHESTRATION.prompt.md` (mechanical/standard/premium mapping + validator
independence rule) and `MODEL` added to the per-workstream dispatch fields in
its SUBAGENT EXECUTION and OUTPUT FORMAT sections.

### D2 — Mechanical independence check in `set-validation`
New optional flag `--model <id>` on `state.mjs set-validation` (the validator's
model id, same string the role will pass to `append-run`).

- Trigger: the check runs only when a verdict is being set
  (`--status pass|fail`) AND `--model` was provided. `--status not_run` and
  clear-only invocations never trigger it.
- Implementer model source: scan `metrics.work_items[<ref>].agent_runs` in the
  same STATE file (line engine, no YAML lib) where `<ref>` = `--ref` if given,
  else the existing `last_validation.ref_id` scalar. Take the LAST run whose
  `role` is `Implementation` or `TDD Implementation` and read its `model_id`.
- Comparison semantics (exact, closed): both ids are normalized as
  `normalizeModelId(s) = s.trim().toLowerCase()` with one trailing
  bracket-suffix stripped (`/\[[^\]]*\]$/` → removed), then compared for FULL
  STRING EQUALITY of the normalized base id.
  - `claude-opus-4-8[1m]` vs `claude-opus-4-8` → EQUAL (a context-window
    variant runs the same weights, hence the same blind spots) → violation.
  - `claude-sonnet-5` vs `claude-fable-5` (same vendor family, different
    size/weights) → DIFFERENT → independent, silent pass. No family taxonomy
    is maintained; different weights are treated as independent by design.
- Skip paths (never block honest work): no implementer run found for the ref,
  or ref unresolvable → one stderr info line
  (`independence not checked: <reason>`), write proceeds, exit 0. `--model`
  omitted while a verdict is set → same info line (backward compatible).
- Violation behavior is governed by the `independence:` config key (D3):
  - `report-only` (default): stderr line
    `state: set-validation: WARNING independence violation — validator model
    "<v>" equals implementer model "<i>" for <ref>`; write proceeds; exit 0.
  - `enforce`: NO write performed (STATE byte-identical), stderr error naming
    both models and the config key, exit 1. The state.mjs header exit-code
    contract is extended: exit 1 also covers "policy refusal (independence
    enforce violation) — no write performed".

### D3 — Config key location: reuse `docs/ai/docs-audit.yaml`
Key: `independence: enforce | report-only` (column-0). Default when the file,
the key, or a valid value is absent: `report-only` (fail-open to warn — the
constraint says enforcement must not block single-model environments unless
explicitly opted in).

Justification for reuse over a new file: `docs/ai/docs-audit.yaml` is already
the committed, project-owned guard-policy file hosting exactly this
enforce/report-only dial pattern (`close_gate` per SPEC-0011 G5,
`doc_number_guard` per SPEC-0015); operators find all guard dials in one
place, and state.mjs stays YAML-lib-free by reading the key with the same
column-0 line scan it uses on STATE. The path is derived as
`path.join(path.dirname(statePath), 'docs-audit.yaml')` — for the default
`docs/ai/STATE.yaml` this is exactly `docs/ai/docs-audit.yaml`, and tests get
config isolation for free via `--state <scratch>/STATE.yaml`. Residual: the
file name no longer describes its full scope; a rename to `guards.yaml` is a
candidate future change, out of scope here.

### D4 — PRICING.yaml refresh (values verified 2026-07-15 against vendor docs)
All prices USD per 1M tokens (input/output):

| model id | input | output | action |
|---|---|---|---|
| claude-fable-5 | 10.00 | 50.00 | add |
| claude-opus-4-8 | 5.00 | 25.00 | add |
| claude-opus-4-7 | 5.00 | 25.00 | add |
| claude-opus-4-6 | 5.00 | 25.00 | fix (was 15/75) |
| claude-sonnet-5 | 3.00 | 15.00 | add; note: intro $2/$10 through 2026-08-31 |
| claude-sonnet-4-6 | 3.00 | 15.00 | add |
| claude-sonnet-4-5 | 3.00 | 15.00 | keep |
| claude-haiku-4-5 | 1.00 | 5.00 | fix (was 0.80/4.00) |
| deepseek-v4-flash | null | null | add per `on_unknown_model` policy + new `deepseek-pricing` source; verify in a follow-up |

- Every refreshed/added entry gets `last_verified_utc: "2026-07-15T00:00:00Z"`
  (implementation stamps the real edit-time UTC); `sources.anthropic-pricing.
  last_verified_utc` and `pricing_meta.last_updated_utc` are stamped likewise.
- New `lookup_rules:` section documenting the deterministic resolution order
  for calculators/flush: (1) strip one trailing bracket suffix `[...]` from the
  runtime id (`claude-opus-4-8[1m]` → `claude-opus-4-8`); (2) apply
  `model_aliases`; (3) exact key match in `models`; (4) longest-prefix match
  against `models` keys; (5) fall back to `unknown`.
- Belt-and-braces alias for the one bracketed id already in history:
  `"claude-opus-4-8[1m]": claude-opus-4-8` in `model_aliases` (quoted key), so
  alias-only readers resolve it without implementing suffix stripping.
- Prune rule (measurable): delete every `models:` entry that has null pricing
  AND does not appear in METRICS.jsonl history — on current data:
  `claude-3-7-sonnet`, `claude-3-5-sonnet`, `claude-3-5-haiku`,
  `gemini-1.5-flash`, `gemini-1.5-flash-8b`, `gemini-2.0-pro`, `gpt-4.1`,
  `gpt-4.1-mini`, `gpt-4.1-nano`, `o1`, `o1-mini`, `o3-mini`, `o4` — plus their
  now-dangling `model_aliases` rows (`claude-3-5-sonnet-latest`,
  `gemini-1.5-flash-latest`, `o3-mini`). `unknown` is always kept. Priced
  non-Claude entries stay (valid data, other AAI projects may record them).

### D5 — Token capture teeth on `append-run` + flush warning
- `append-run` keeps its existing persist behavior; NEW: after a successful
  write, when `--tokens-in` or `--tokens-out` was not provided, print ONE
  stderr line
  (`state: append-run: WARNING tokens_in/tokens_out null for <ref> role=<role>
  — cost_usd cannot be computed at flush; pass --tokens-in/--tokens-out when
  the platform exposes usage`) and still exit 0 (warn, never block).
- `.aai/METRICS_FLUSH.prompt.md`: the flush-report contract gains an explicit
  visible warning line per run with null tokens ("cost unattributable — tokens
  not recorded"), and its pricing step references the new `lookup_rules`
  (suffix-normalize before lookup). Cost formula unchanged.

### D6 — `model:` frontmatter on cheap-tier skill wrappers
Add `model: haiku` to the YAML frontmatter of 4 wrappers whose work is
mechanical routing/validation/reporting: `.claude/skills/aai-intake/SKILL.md`
(router), `.claude/skills/aai-check-state/SKILL.md`,
`.claude/skills/aai-flush/SKILL.md`,
`.claude/skills/aai-validate-report/SKILL.md`. The alias form (`haiku`) is
used so the pin survives model-version churn; unknown frontmatter keys are
harmlessly ignored by non-Claude readers.

## Acceptance Criteria Mapping
- Maps to: CHANGE-0010 AC-001 → Spec-AC-01
- Maps to: CHANGE-0010 AC-002 → Spec-AC-02
- Maps to: CHANGE-0010 AC-003 → Spec-AC-03
- Maps to: CHANGE-0010 AC-004 → Spec-AC-04
- Maps to: CHANGE-0010 AC-005 → Spec-AC-05

Verification commands are enumerated per TEST-xxx in the Test Plan.

## Acceptance Criteria Status

| Spec-AC    | Description | Status  | Evidence | Review-By | Notes |
|------------|-------------|---------|----------|-----------|-------|
| Spec-AC-01 | MODEL is a documented required dispatch field: `MODEL` row in the SUBAGENT_PROTOCOL contract table; `MODEL SELECTION` tiering text present in BOTH orchestration prompts; PARALLEL dispatch fields include MODEL | done | docs/ai/tdd/green-20260715T191855Z-change0010-TEST-008.log | — | grep-wired by TEST-008 |
| Spec-AC-02 | `set-validation --model` independence check per D2: same normalized model → warn+exit 0 (default) / no-write+exit 1 (`independence: enforce`); different models silent; `[1m]`-suffixed id equals its base; missing implementer run or missing --model skips safely with exit 0 | done | docs/ai/tdd/red-20260715T191632Z-change0010-TEST-001.log + docs/ai/tdd/green-20260715T191855Z-change0010-TEST-00{1..5}.log | — | TEST-001..005 |
| Spec-AC-03 | PRICING.yaml resolves ALL 5 model ids recorded in METRICS.jsonl history via `lookup_rules` (incl. bracket-suffix normalization); current Claude family priced per D4 table; opus-4-6 and haiku-4-5 corrected; `last_verified_utc` stamped; prune rule holds (no null-priced never-recorded entry except `unknown`) | done | docs/ai/tdd/red-20260715T191632Z-change0010-TEST-006.log + docs/ai/tdd/green-20260715T191855Z-change0010-TEST-006.log | — | TEST-006 |
| Spec-AC-04 | `append-run --tokens-in/--tokens-out` persists integer values into `agent_runs`; omitting them emits ONE stderr warning and exits 0; METRICS_FLUSH prompt mandates a visible null-token warning line in the flush report and suffix-normalized pricing lookup | done | docs/ai/tdd/green-20260715T191855Z-change0010-TEST-007.log + -TEST-010.log | — | TEST-007, TEST-010 |
| Spec-AC-05 | ≥3 wrappers carry `model:` frontmatter (D6 names 4); docs-audit `--check --strict` and existing suites stay green | done | docs/ai/tdd/green-20260715T191855Z-change0010-TEST-009.log + -TEST-011.log | — | TEST-009, TEST-011 |

Status values: planned | implementing | done | deferred | blocked | rejected
(gate behavior as per template).

## Implementation plan
- `.aai/scripts/state.mjs`: `CMD_FLAGS['set-validation']` gains `model`;
  `normalizeModelId()`; agent_runs scanner (reuses findBlock/indentOf over the
  `metrics` block); `readGuardKey()` reading
  `<dirname(statePath)>/docs-audit.yaml` column-0 `independence:`; violation
  branch (warn/exit-1-pre-write) placed BEFORE `editBlock` so enforce refusals
  never touch the file; `cmdAppendRun` gains the post-write null-token stderr
  warning; header comment blocks updated (exit-code contract, subcommand
  synopsis).
- `.aai/system/PRICING.yaml`: D4 table, `lookup_rules:`, aliases, prune,
  stamps.
- `.aai/SUBAGENT_PROTOCOL.md` + `.aai/ORCHESTRATION_PARALLEL.prompt.md`: D1
  text. `.aai/ORCHESTRATION.prompt.md` is NOT edited (already has the text;
  TEST-008 asserts it stays).
- `.aai/METRICS_FLUSH.prompt.md`: D5 flush-report warning + lookup_rules ref.
- 4 wrapper SKILL.md frontmatter edits (D6).
- Tests: extend `tests/skills/test-aai-state.sh` (independence + append-run
  warn stanzas); new `tests/skills/test-aai-pricing.sh` (resolver over real
  METRICS.jsonl ids + prune/stamp assertions); grep-wiring stanzas may live in
  either suite.
- Edge cases: ref present in metrics but with zero Implementation-role runs;
  agent_runs in inline `[]` form; docs-audit.yaml with `independence:` present
  alongside existing keys; bracket suffix other than `[1m]`; validator model
  differing only by case.

## Seam analysis
- Seam A (append-run writes `model_id` → set-validation reads it): covered by
  integration TESTs 001/003/004 which build the fixture STATE by actually
  running `append-run` first, then run `set-validation` against the same file —
  no mocked STATE contents.
- Seam B (METRICS.jsonl history ↔ PRICING.yaml lookup, consumed by flush):
  TEST-006 reads the REAL `docs/ai/METRICS.jsonl` distinct model ids and
  resolves each against the real PRICING.yaml with a resolver implementing
  `lookup_rules` verbatim.
- Seam C (docs-audit.yaml shared by docs-audit tooling and now state.mjs):
  TEST-002 fixture file carries `close_gate`, `doc_number_guard` AND
  `independence` together, proving coexistence; TEST-011 re-runs the docs-audit
  suite/check unchanged.
- Residual risk (explicit): the flush cost computation itself is performed by
  an LLM following `.aai/METRICS_FLUSH.prompt.md` — the prompt text and the
  pricing data are testable (TEST-006/TEST-010), the LLM execution is not
  automatable here. Accepted; first real flush after this change should be
  operator-observed.

## Implementation strategy
- Strategy: hybrid
- Rationale: the `state.mjs` independence check and the pricing resolver are
  new guard behavior with real failure modes (silent wrong-verdict acceptance,
  wrong cost data) — TDD with observed RED for TEST-001..007. The prompt-text,
  PRICING data-entry, and wrapper-frontmatter edits are mechanical
  configuration where RED-GREEN adds little signal — loop, but their gating
  greps (TEST-008/009) must still be observed failing on pre-change main
  (RED-proof obligation) before counting as evidence.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: parallel stream — CHANGE-0011 runs concurrently on main
  docs this tick; the scope spans 5+ independent surfaces (scripts, system
  config, two prompts, wrappers, tests) and isolation avoids cross-talk with
  the concurrent stream and keeps the enforce-refusal experiments off the live
  STATE. Not `required`: changes are additive/reversible, no schema migration.
- User decision: undecided (operator decides at preparation)
- Base ref: main
- Worktree branch/path: proposed `feat/change-0010-model-tiering` (if selected)
- Inline review scope (if inline is selected): .aai/scripts/state.mjs,
  .aai/system/PRICING.yaml, .aai/SUBAGENT_PROTOCOL.md,
  .aai/ORCHESTRATION_PARALLEL.prompt.md, .aai/METRICS_FLUSH.prompt.md,
  .claude/skills/aai-intake/SKILL.md, .claude/skills/aai-check-state/SKILL.md,
  .claude/skills/aai-flush/SKILL.md,
  .claude/skills/aai-validate-report/SKILL.md, tests/skills/test-aai-state.sh,
  tests/skills/test-aai-pricing.sh,
  docs/specs/SPEC-0018-spec-model-tiering-with-teeth.md
- Code review: required: true (guard-path code + workflow contract changes);
  status not_run; scope = the explicit path list above (or the worktree diff
  range if a worktree is chosen).

NOTE (parallel-safe discipline, this tick): the shared single-slot STATE blocks
(`implementation_strategy`, `worktree`, `code_review`, `current_focus`) are NOT
written by this planning run — they still carry the concurrent stream's values.
The orchestrator applies them from this section when CHANGE-0010 becomes the
active focus.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-02 | integration | tests/skills/test-aai-state.sh | Scratch STATE: `append-run --role Implementation --model claude-fable-5` then `set-validation --status pass --model claude-fable-5` (no config key) → exit 0, stderr contains `WARNING independence violation`, status written | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-state.sh | Same fixture + sibling docs-audit.yaml with `independence: enforce` (alongside close_gate/doc_number_guard keys) → exit 1, stderr names both models and the key, STATE byte-identical (no write) | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-state.sh | Implementer `claude-fable-5`, validator `claude-sonnet-5`, `independence: enforce` → exit 0, NO warning on stderr, status written (different weights = independent) | green |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-state.sh | Suffix normalization: implementer `claude-opus-4-8[1m]`, validator `claude-opus-4-8` (and case variant) → treated EQUAL → warning under default, exit 1 under enforce | green |
| TEST-005 | Spec-AC-02 | unit | tests/skills/test-aai-state.sh | Safe skips: (a) verdict set with `--model` but ref has no Implementation-role run; (b) verdict set without `--model`; (c) `--status not_run --model X`; (d) clear-only — all exit 0, stderr info line for a+b, no violation text | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-pricing.sh | Resolver implementing `lookup_rules` (strip bracket suffix → aliases → exact → longest prefix → unknown) resolves EVERY distinct model_id in real docs/ai/METRICS.jsonl to a non-`unknown` entry; asserts opus-4-6=5/25, haiku-4-5=1/5, fable-5=10/50, sonnet-5=3/15; asserts `last_verified_utc` non-null on all Claude-family entries; asserts no null-priced entry outside METRICS history except `unknown` | green |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-state.sh | `append-run --tokens-in 1200 --tokens-out 340` → values persisted as integers in agent_runs (grep STATE); `append-run` WITHOUT tokens → exit 0 AND single stderr `WARNING tokens_in/tokens_out null` line | green |
| TEST-008 | Spec-AC-01 | unit | tests/skills/test-aai-state.sh | Grep-wiring: `MODEL` row present in the SUBAGENT_PROTOCOL.md contract table; `MODEL SELECTION` present in BOTH .aai/ORCHESTRATION.prompt.md and .aai/ORCHESTRATION_PARALLEL.prompt.md; PARALLEL dispatch fields include MODEL | green |
| TEST-009 | Spec-AC-05 | unit | tests/skills/test-aai-state.sh | ≥3 files matching `.claude/skills/*/SKILL.md` contain a frontmatter `model:` line (grep count ≥3); the 4 D6 wrappers each carry `model: haiku` | green |
| TEST-010 | Spec-AC-04 | unit | tests/skills/test-aai-state.sh | Grep-wiring: .aai/METRICS_FLUSH.prompt.md mandates a visible flush-report warning for null-token runs and references suffix-normalized/lookup_rules pricing resolution | green |
| TEST-011 | Spec-AC-05 | integration | tests/skills/test-aai-state.sh | Regression: full test-aai-state.sh suite exit 0; `docs-audit --check --strict --no-event` exit 0 on the changed docs | green |

RED-proof obligation: every TEST above must be observed FAILING on pre-change
main before its pass counts as evidence (TEST-001..005/007 fail as unknown-flag
exit 2 / missing warning; TEST-006 fails on 4 unresolvable ids + wrong prices;
TEST-008/009/010 greps fail on absent text).

## Verification
- `bash tests/skills/test-aai-state.sh` → exit 0 (includes new stanzas)
- `bash tests/skills/test-aai-pricing.sh` → exit 0
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0
- PASS criteria: all TEST-001..011 green AND all Spec-AC in a terminal status.

## Evidence contract
Per artifact record: ref_id CHANGE-0010 (slug spec-model-tiering-with-teeth),
Spec-AC + TEST-xxx links, command/review scope, exit code or verdict, evidence
path under docs/ai/tdd/ or docs/ai/reports/, commit SHA or diff range.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.

## Review warning dispositions (2026-07-15)

- W1 (present-but-invalid `independence:` value silently fell open to
  report-only): REMEDIATED — readIndependencePolicy now emits a stderr WARNING
  naming the invalid value and the fail-open default; covered by a new stanza
  in test_043.
- W2 (three drift-prone parsers of docs-audit.yaml across state.mjs /
  pre-commit-checks.sh / install-pre-commit-hook.ps1, plus the undocumented
  file-presence coupling in docs-audit.mjs): PROMOTED — consolidating config
  parsing is CHANGE-0009 territory (mechanize deterministic ticks); recorded
  here as the follow-up pointer.
