---
id: spec-r-guard-runtime-enforcement
type: spec
number: 113
status: implementing
ceremony_level: 3
links:
  requirement: docs/issues/CHANGE-0107-r-guard-runtime-enforcement.md
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — r-guard-runtime-enforcement

SPEC-FROZEN: true

## Ceremony level (RFC-0009)

`ceremony_level: 3` — MANDATORY, not discretionary. Stage 1 edits
`.aai/scripts/state.mjs`, listed verbatim in `protected_paths_l3`
(docs/ai/docs-audit.yaml) and in the WORKFLOW.md "Protected surfaces" list
(state engine). A scope that touches a protected surface MUST declare level 3 —
same basis as the precedents SPEC-0107 (CHANGE-0097, allocator) and SPEC-0109
(CHANGE-0100, state.mjs strategy enum). L3 consequences carried:

- Worktree gate (rule 8): REQUIRED semantics — work is on the dedicated isolated
  worktree branch off main; the operator's run-level authorization is the
  recorded decision.
- Code review (rule 13): MANDATORY on the most capable tier. No auto-waiver.
- PR ceremony: adds an OPERATOR CHECKPOINT before merge (explicit final-diff
  sign-off; the orchestrator owns operator sign-off at PR time).
- Evidence-before-claims and full independent validation are NOT pruned; L3
  scales artifact weight and review, never the evidence bar.

The L3 blast is deliberately confined to ONE protected file: `state.mjs` gains
one additive guard clause. `lib/state-engine.mjs` and `lib/state-core.mjs`
(also L3) are NOT touched. Stages 2-3 land in `.aai/scripts/metrics-flush.mjs`
(NOT a protected surface).

## Links
- Requirement / intake (AUTHORITATIVE analysis, rule inventory, staged plan):
  docs/issues/CHANGE-0107-r-guard-runtime-enforcement.md
- Precedents (L3 protected-surface specs, context only):
  docs/specs/SPEC-0107-spec-allocator-header-rewrite.md,
  docs/specs/SPEC-0109-spec-implementation-mode-choice.md
- Payoff-raiser this closes: SPEC-0109 RR-3 ("If R-GUARD is ever built,
  strategy flips should be among its watched mutations").
- The prose rule this enforces: `.aai/SUBAGENT_CONTRACT.md` single-writer rule;
  `.aai/SUBAGENT_PROTOCOL.md` R-GUARD residual note; Constitution Article 6.
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded

## Problem

The factory's highest-blast-radius safety rule — the single-writer rule
(subagent MUST NOT write `docs/ai/STATE.yaml`; the orchestrator is the sole
STATE writer) — is prose, pinned only by grep tests that prove the instruction
EXISTS in a file, not that a run FOLLOWED it. `.aai/SUBAGENT_PROTOCOL.md` names
this accepted residual R-GUARD. CHANGE-0099 is empirical proof that prose hooks
do not fire (the friction-capture prose hook wrote ZERO observations until a
DETERMINISTIC capture point landed in a script). SPEC-0109 RAISED the payoff:
since the `untested` lane exists, an out-of-contract `set-strategy` from a
subagent can silently downgrade rigor (tdd -> untested escapes the RED proof),
not merely lose an update.

## Scope

In scope:
- Stage 1 (L3), `.aai/scripts/state.mjs`: ONE additive guard clause in `main()`,
  AFTER `rejectUnknownFlags(cmd, flags)` and BEFORE dispatching a STATE mutator.
  If the command is a STATE mutator (the nine `MUTATORS` keys plus `reset-block`)
  AND `process.env.AAI_ROLE === 'subagent'`, `fail(<message>, 3)` — a NEW
  dedicated exit code added to the closed exit-code contract comment — writing
  NOTHING. `log-tick` (writes LOOP_TICKS, not STATE) stays allowed; the SEPARATE
  script `append-event.mjs` (the sanctioned subagent append path) is untouched.
  Purely additive: byte-identical behavior when the marker is absent.
- Orchestrator wiring: `.aai/SUBAGENT_PROTOCOL.md` dispatch call contract +
  `.aai/ORCHESTRATION_PARALLEL.prompt.md` instruct setting `AAI_ROLE=subagent`
  in the subagent's environment/instructions on dispatch, and guarantee it is
  unset for the orchestrator's own writes.
- Stage 2 (NOT L3), `.aai/scripts/metrics-flush.mjs`: a WARN-only forensic
  strategy-provenance check at flush time (see Honest scope below).
- Stage 3 (NOT L3), `.aai/scripts/metrics-flush.mjs`: the strategy-flip
  narrowing (SPEC-0109 RR-3) + a cheap EVENTS.jsonl append-only predicate
  (line-count-non-decreasing vs `git show HEAD:docs/ai/EVENTS.jsonl`).
- Tests: extend `tests/skills/test-aai-state.sh` (Stage 1 refusal / back-compat),
  extend `tests/skills/test-aai-metrics.sh` (Stage 2/3 WARNs), add the pin suite
  `tests/skills/test-aai-r-guard.sh` (AAI_ROLE wiring) + its `suite-map.yaml` row.
- Governance: prompt-diet ledger true-up for the in-glob wiring bytes; CHANGELOG
  NEW entry; intake reconcile.

Out of scope:
- Guarding the other six inventoried prose rules (guard-sprawl discipline — the
  intake declines them explicitly).
- Activating the inert `claude-hook-gate` overlay (SPEC-0029); the check lives
  INSIDE the CLI on purpose so it fires regardless of hook wiring.
- Any change to `lib/state-engine.mjs` / `lib/state-core.mjs`.
- Any behavior change when the marker is absent.
- No new `.aai/**` file (so no PROFILES.yaml classification is required per
  PLANNING step 3a — all edited `.aai/**` files pre-exist; the new files are a
  spec, a test suite, and a suite-map row).

## Design

### Stage 1 — env-marker refusal (state.mjs, THE ONE L3 CLAUSE)
A subagent context is marked by `AAI_ROLE=subagent` (mirroring the EXISTING
`AAI_OPERATOR_MERGE=1` marker the merge gate uses). In `main()`, right after the
`MUTATORS` map literal is defined and before any command is dispatched:

    const STATE_MUTATORS = new Set([...Object.keys(MUTATORS), 'reset-block']);
    if (STATE_MUTATORS.has(cmd) && process.env.AAI_ROLE === 'subagent') {
      fail('<single-writer message naming SUBAGENT_CONTRACT.md + append-event escape>', 3);
    }

`fail(msg, 3)` prints `state: <msg>` and exits 3 with NO read/load and NO write —
placed before `loadState`, so the file is never opened. Ordering: it runs AFTER
`rejectUnknownFlags` so a typo still fails LOUD (exit 2) first (AC-004).
`log-tick` is not in `STATE_MUTATORS`, so it stays allowed (AC-003).

New exit code 3 is added to the closed exit-code contract comment (~L62-74).

### Honesty in the code comment (verbatim posture, MUST NOT be softened)
The clause carries the intake's anti-evasion honesty in a comment: this is a
guardrail against the honest/accidental path (the "my update is tiny"
rationalization row in SUBAGENT_CONTRACT.md), NOT a security boundary — an agent
that unsets or never inherits the marker defeats it; Stage 2 catches that case
after the fact via durable git history. It does NOT make a rogue subagent STATE
write impossible. This mirrors SKILL_PR's merge-marker posture ("a guardrail
against habit, not a security boundary").

### Stage 2 — strategy-provenance forensic WARN (metrics-flush.mjs)

HONEST SCOPE — the gap the intake flagged, confirmed and documented here:
`docs/ai/STATE.yaml` is GITIGNORED. There is therefore NO git history of STATE
writes, so the intake's design-option (d) sketch — "git log --follow on
STATE.yaml, cross each mutation timestamp against the recorded agent_runs
[started,ended] windows" — is NOT honestly implementable: a per-field STATE
write carries no independent, durable timestamp to place inside or outside a
subagent window. The agent_runs windows exist in STATE, but the STATE writes
they would be compared against leave no timeline. Rather than fake a timeline,
Stage 2 implements the honestly-detectable subset:

- At flush time, read `implementation_strategy.source`. The sanctioned writers
  always stamp a recognizable source: `SKILL_INTAKE` writes `set-strategy
  --source intake`; `PLANNING` writes `--source <spec-path>` (a `docs/**.md`
  path). A flushed ride whose recorded strategy has a source that is NEITHER
  `intake` NOR a spec-path-like `*.md` value is flagged with exactly one WARNING
  (naming the ref + the source value) — an out-of-contract subagent write
  typically would not reproduce a sanctioned provenance. WARN, never block
  (mirrors the flush's existing token-capture warn-don't-block posture).
- A clean ride (source `intake` or a `*.md` spec path, or no strategy selected)
  is SILENT — no false WARN, byte-unchanged output (AC-005).

### Stage 3 — strategy-flip narrowing + EVENTS append-only predicate

- Strategy-flip watch (SPEC-0109 RR-3): the Stage-2 check narrowed — when the
  suspicious-provenance strategy is a rigor-downgrade lane (`untested` or
  `direct`), the WARNING is escalated to name it specifically as a
  rigor-downgrade-provenance risk (the exact class SPEC-0109 RR-3 warned R-GUARD
  should watch). A legitimate orchestrator `set-strategy` (sanctioned source) is
  not flagged (AC-006).
- EVENTS append-only predicate: `docs/ai/EVENTS.jsonl` IS committed (unlike
  STATE), so a durable, honest git check is available. At flush time compare the
  working-tree line count against `git show HEAD:docs/ai/EVENTS.jsonl | wc -l`; a
  SHRINK (working < HEAD) is flagged as a truncation/rewrite (append-only
  violation — the exact failure mode behind the operator memory note "EVENTS
  restore wipes close telemetry"). An append-only change (working >= HEAD) is
  silent. Best-effort: outside a git repo, or when the file is untracked / git
  errors, the check degrades silently (no false WARN) — no new hard dependency
  on git for the flush's core path (AC-007).

## Companion obligations (PLANNING step 3a)
- Prompt-corpus byte growth -> prompt-diet ledger true-up: APPLIES for the
  in-glob wiring bytes (`.aai/ORCHESTRATION_PARALLEL.prompt.md`). Credited 1:1 at
  the measured deficit so headroom stays 0/2048. `.aai/SUBAGENT_PROTOCOL.md`
  sits OUTSIDE TEST-010's live `.aai/*.prompt.md` glob and its extra accounting
  (INTAKE_COMMON/STATE_FALLBACK/ROLE_COMMON only), so its growth carries no
  measured deficit — the same treatment CHANGE-0061 (subagent-protocol-slim)
  applied to SUBAGENT_PROTOCOL edits.
- New `.aai/**` file -> PROFILES.yaml classification: does NOT apply (no new
  `.aai/**` file; state.mjs / metrics-flush.mjs / the two prompt files pre-exist).

## Implementation strategy
- Strategy: tdd
- Rationale: touches a PROTECTED core script (L3) where the failure class is a
  silent single-writer breach / rigor downgrade. The refusal + back-compat
  byte-identity + allowed-path tests are observed RED before GREEN. Codebase
  precedent on the same protected surface (SPEC-0012, SPEC-0107, SPEC-0109) is
  TDD.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: L3 protected surface (state engine). Rule-8 REQUIRED
  semantics mandate a RECORDED user_decision; the change edits the shared
  transactional STATE CLI every ride depends on.
- User decision: recorded from the operator's run-level authorization. Work is on
  the dedicated isolated worktree branch off main.
- Base ref: main
- Inline review scope (if inline is recorded):
  .aai/scripts/state.mjs, .aai/scripts/metrics-flush.mjs,
  .aai/SUBAGENT_PROTOCOL.md, .aai/ORCHESTRATION_PARALLEL.prompt.md,
  tests/skills/test-aai-state.sh, tests/skills/test-aai-metrics.sh,
  tests/skills/test-aai-r-guard.sh, tests/skills/suite-map.yaml,
  tests/skills/lib/prompt-diet-ledger.sh,
  docs/specs/SPEC-0113-spec-r-guard-runtime-enforcement.md,
  docs/issues/CHANGE-0107-r-guard-runtime-enforcement.md, CHANGELOG.md

## Acceptance Criteria Mapping
- Maps to: intake AC-001 (negative control, Stage 1)
  - Spec-AC-01: with `AAI_ROLE=subagent`, every STATE-mutating subcommand exits 3
    and leaves STATE byte-identical (write count 0). Verification:
    bash tests/skills/test-aai-state.sh (R-GUARD refusal test).
- Maps to: intake AC-002 + AC-008 (false-positive / no-marker controls)
  - Spec-AC-02: with `AAI_ROLE` unset or != subagent, those subcommands succeed
    and write exactly as today (byte-identical to a pre-change baseline); the full
    existing state suite passes unchanged. Verification:
    bash tests/skills/test-aai-state.sh.
- Maps to: intake AC-003 (allowed subagent paths)
  - Spec-AC-03: under `AAI_ROLE=subagent`, `log-tick` still succeeds and
    `append-event.mjs` is unaffected. Verification: tests/skills/test-aai-state.sh.
- Maps to: intake AC-004 (closed contract / ordering)
  - Spec-AC-04: the refusal exits with the documented code 3 and prints a message
    naming the single-writer rule + SUBAGENT_CONTRACT.md + the append-event
    escape; an unknown-flag typo still fails exit 2 BEFORE the marker check.
    Verification: tests/skills/test-aai-state.sh.
- Maps to: intake AC-005 (forensic detection, Stage 2)
  - Spec-AC-05: a flushed ride whose strategy source is not intake/spec-path
    emits exactly one WARNING naming the ref; a sanctioned-source ride is silent.
    Verification: bash tests/skills/test-aai-metrics.sh.
- Maps to: intake AC-006 (strategy-flip watch, Stage 3)
  - Spec-AC-06: a downgrade-lane (untested/direct) strategy with a
    non-sanctioned source is flagged specifically as a rigor-downgrade risk; a
    legitimate orchestrator set-strategy is not. Verification:
    bash tests/skills/test-aai-metrics.sh.
- Maps to: intake AC-007 (EVENTS append-only, Stage 3)
  - Spec-AC-07: a flush whose working-tree EVENTS.jsonl has fewer lines than
    `git show HEAD:` is flagged; an append-only tree passes; non-git degrades
    silently. Verification: bash tests/skills/test-aai-metrics.sh.
- Maps to: intake AC-001..004 (orchestrator wiring + L3 governance)
  - Spec-AC-08: SUBAGENT_PROTOCOL.md + ORCHESTRATION_PARALLEL.prompt.md instruct
    setting AAI_ROLE=subagent on dispatch; the L3 touch is authorized by this
    frozen ceremony_level:3 spec and the prompt-diet ledger is trued up.
    Verification: bash tests/skills/test-aai-r-guard.sh,
    bash tests/skills/test-aai-hitl-propagation.sh (TEST-014),
    bash tests/skills/test-aai-prompt-diet.sh (TEST-010/TEST-012).

## Constitution deviations
None.

## Seam analysis
- Seam S1 (marker producer -> CLI consumer): the orchestrator wiring sets
  `AAI_ROLE=subagent` on dispatch; state.mjs reads `process.env.AAI_ROLE`. If the
  wiring is forgotten the guard fails OPEN (today's behavior) — deliberate: the
  alternative (default-assume-subagent) would block the orchestrator's own
  legitimate writes. Covered by the pin suite (wiring text present) + the state
  refusal test (the CLI honors the marker when set).
- Seam S2 (strategy writer -> flush reader): `set-strategy --source` value
  written to STATE is later read by the flush provenance check. Covered by
  test-aai-metrics.sh (sanctioned source silent; non-sanctioned source WARNs).

## Residual risks (accepted)
- RR-1 (R-EVADE — evadability honesty, MUST NOT be softened): Stage 1 is
  defeated by an agent that unsets or never sets `AAI_ROLE`. It is a guardrail
  against habit and accident and the honest-agent path, NOT a security boundary
  or a sandbox. Stage 2 is the after-the-fact backstop for the unset-marker
  case. R-GUARD raises the floor from "prose only" to "prose + a guardrail that
  stops the honest mistake + a forensic detector for the dishonest one." It does
  NOT claim to make a rogue subagent STATE write impossible. Any AC, comment, or
  changelog line implying otherwise is a defect.
- RR-2 (Stage-2 honesty gap): STATE is gitignored, so the intake's timeline
  cross-check is not implementable; Stage 2 is a provenance heuristic, not a
  timeline. A subagent that also stamps a sanctioned-looking `--source` evades
  it. Documented, accepted; the compensating control is that VALIDATION still
  keys off the RECORDED strategy and `untested` still needs a rationale.
- RR-3 (R-WIRE): Stage 1 protection only exists when the orchestrator SETS the
  marker on dispatch; forgetting it fails OPEN (today's behavior).
- RR-4 (R-FALSEPOS): marker leakage into orchestrator context would block
  legitimate writes; mitigated by explicit unset in the wiring + opt-in-present
  semantics + Stage 2 being WARN-only.

## Acceptance Criteria Status

| Spec-AC    | Description                                                          | Status | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | AAI_ROLE=subagent refuses every STATE mutator (exit 3, no write)    | implementing | tests/skills/test-aai-state.sh R-GUARD refusal | — | — |
| Spec-AC-02 | marker absent/other -> mutators write byte-identically; suite green | implementing | tests/skills/test-aai-state.sh | — | — |
| Spec-AC-03 | under the marker, log-tick allowed + append-event.mjs unaffected    | implementing | tests/skills/test-aai-state.sh | — | — |
| Spec-AC-04 | exit code 3 documented; message names the rule; typo fails 2 first  | implementing | tests/skills/test-aai-state.sh | — | — |
| Spec-AC-05 | flush WARNs on non-sanctioned strategy source; silent otherwise     | implementing | tests/skills/test-aai-metrics.sh | — | — |
| Spec-AC-06 | downgrade-lane + bad source flagged as rigor-downgrade risk         | implementing | tests/skills/test-aai-metrics.sh | — | — |
| Spec-AC-07 | EVENTS.jsonl shrink vs HEAD flagged; append-only passes; non-git ok | implementing | tests/skills/test-aai-metrics.sh | — | — |
| Spec-AC-08 | orchestrator wiring pinned; L3 authorized by this spec; ledger true | implementing | tests/skills/test-aai-r-guard.sh; test-aai-hitl-propagation.sh TEST-014; test-aai-prompt-diet.sh | — | — |

## Implementation plan
- Components/modules affected: .aai/scripts/state.mjs (one guard clause + exit
  code 3 in the contract comment), .aai/scripts/metrics-flush.mjs (Stage 2/3
  forensic WARNs), .aai/SUBAGENT_PROTOCOL.md + .aai/ORCHESTRATION_PARALLEL.prompt.md
  (marker wiring), the two extended test suites + the new pin suite + suite-map +
  the prompt-diet ledger.
- Data flows: dispatch sets AAI_ROLE=subagent -> state.mjs refuses STATE
  mutators -> subagent returns a result block -> orchestrator (no marker) merges
  via state.mjs. Flush reads implementation_strategy.source + EVENTS.jsonl git
  history -> WARN-only forensic lines.
- Edge cases: marker set + typo flag (exit 2 wins); marker set + log-tick
  (allowed); marker absent (byte-identical); strategy undecided/null (no
  provenance WARN); EVENTS untracked / non-git (silent).

## Test Plan

Test ID / Spec-AC / Type / File / Description / Status:

- TEST-RG-STATE-01 / Spec-AC-01 / unit / tests/skills/test-aai-state.sh / AAI_ROLE=subagent refuses all 10 STATE mutators, exit 3, byte-identical / pending
- TEST-RG-STATE-02 / Spec-AC-02 / unit / tests/skills/test-aai-state.sh / marker unset/other -> mutators write as today / pending
- TEST-RG-STATE-03 / Spec-AC-03 / unit / tests/skills/test-aai-state.sh / marker set -> log-tick allowed; append-event.mjs unaffected / pending
- TEST-RG-STATE-04 / Spec-AC-04 / unit / tests/skills/test-aai-state.sh / exit 3 message names the rule + escape; typo still exits 2 first / pending
- TEST-RG-FLUSH-05 / Spec-AC-05 / integration / tests/skills/test-aai-metrics.sh / non-sanctioned strategy source -> one WARNING; sanctioned silent / pending
- TEST-RG-FLUSH-06 / Spec-AC-06 / integration / tests/skills/test-aai-metrics.sh / downgrade lane + bad source -> rigor-downgrade WARNING / pending
- TEST-RG-FLUSH-07 / Spec-AC-07 / integration / tests/skills/test-aai-metrics.sh / EVENTS shrink vs HEAD flagged; append-only silent; non-git silent / pending
- TEST-RG-PIN-08 / Spec-AC-08 / integration / tests/skills/test-aai-r-guard.sh / SUBAGENT_PROTOCOL + ORCHESTRATION_PARALLEL carry the AAI_ROLE=subagent wiring / pending
- TEST-014 / Spec-AC-08 / integration / tests/skills/test-aai-hitl-propagation.sh / this L3 touch authorized by this frozen ceremony_level:3 spec / pending
- TEST-010/012 / Spec-AC-08 / integration / tests/skills/test-aai-prompt-diet.sh / prompt-diet floor holds + JUSTIFIED_GROWTH_BYTES re-sum matches / pending

RED-proof obligation: the Stage-1 refusal tests are observed FAILING against the
unmodified state.mjs (a mutator under AAI_ROLE=subagent exits 0 and writes today)
before GREEN; the flush WARN tests are observed absent at HEAD; the wiring pins
are observed absent at HEAD. RED/GREEN logs under docs/ai/tdd/.

## Verification
- Commands:
  - bash tests/skills/test-aai-state.sh
  - bash tests/skills/test-aai-metrics.sh
  - bash tests/skills/test-aai-r-guard.sh
  - bash tests/skills/test-aai-hitl-propagation.sh
  - bash tests/skills/test-aai-prompt-diet.sh
  - bash tests/skills/test-aai-hygiene-pack.sh
  - bash tests/skills/test-aai-layer-profiles.sh
  - node .aai/scripts/docs-audit.mjs --check --no-event
  - node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0113-spec-r-guard-runtime-enforcement.md
- Evidence artifacts: suite stdout (exit 0), RED/GREEN logs under docs/ai/tdd/.
- PASS criteria: all TEST green AND all Spec-AC terminal AND full framework green.

## Evidence contract
Per artifact record: ref_id (r-guard-runtime-enforcement); Spec-AC and TEST
links; command or review scope; exit code or review verdict; evidence path;
commit SHA or diff range when available.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
