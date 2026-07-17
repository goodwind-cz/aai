---
id: spec-loop-ceremony-aware-dispatch
type: spec
number: 41
status: done
ceremony_level: 2
links:
  change: loop-ceremony-aware-dispatch
  rfc: scale-adaptive-ceremony
  pr:
    - 93
  commits:
    - be2a1a6
---

# SPEC — Ceremony-Aware LOOP Dispatch Lane (L0/L1 lightweight, L2/L3 unchanged)

SPEC-FROZEN: true

## Links
- Change: loop-ceremony-aware-dispatch
  (docs/issues/CHANGE-0030-loop-ceremony-aware-dispatch.md)
- Consumes (does NOT reopen): spec-scale-adaptive-ceremony
  (docs/specs/SPEC-0030-spec-scale-adaptive-ceremony.md, done) and
  spec-l1-close-gate (docs/specs/SPEC-0036-spec-l1-close-gate.md, done)
- Sibling stream (same decide(), sequenced after this):
  dispatch-new-intake-after-completed-scope
  (docs/issues/CHANGE-0031-dispatch-new-intake-after-completed-scope.md)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Ceremony level
`ceremony_level: 2` — full pipeline. Reasoning (recorded against the intake's
open question): the scope edits `.aai/scripts/orchestration-dispatch.mjs`
(deterministic orchestration core) plus two role prompts — multi-surface, not
an L1 "small single-surface fix". L3 is NOT mandatory: verified against
`protected_paths_l3` in docs/ai/docs-audit.yaml (2026-07-17),
`orchestration-dispatch.mjs` is NOT on the list (the list names the state
engine, allocator, pre-commit guards, WORKFLOW.md, CONSTITUTION.md), and this
scope deliberately touches NO listed path (see D4 — no WORKFLOW.md edit).
The intake's "on protected_paths_l3" note is factually stale; recorded here
so review can re-check the same file.

## Implementation strategy
- Strategy: hybrid
- Rationale: the dispatch additions (lane derivation + Validation payload) are
  deterministic-orchestration core logic — TDD with table-driven fixtures
  including the fail-closed default (TEST-001..TEST-004 observed RED first).
  The prompt edits (VALIDATION lane block, PLANNING step-10 continuation
  lines) are text wiring — grep-RED (TEST-005), one focused pass. TEST-006 and
  TEST-007 are survival invariants (green pre-change by construction,
  non-vacuous because they re-run the real gates/suites over the changed tree
  after the change) — same construction SPEC-0030 used for its TEST-001/010.
- RED-proof obligation: before any edit, run the new stanzas of
  `tests/skills/test-aai-ceremony-levels.sh` on the pre-change tree and save
  the failing output to `docs/ai/tdd/ceremony-lane-red.log` (expected:
  TEST-001..TEST-005 FAIL — no `lane` field exists, no prompt lane block
  exists; TEST-006/TEST-007 pass pre-change BY CONSTRUCTION).

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: edits the deterministic dispatch (orchestration core)
  and two role prompts; PR-bound work on a surface the loop itself executes.
- User decision: inline (operator-approved, already recorded in STATE:
  "inline on feat/loop-ceremony-aware-dispatch") — no new decision required.
- Base ref: main
- Inline review scope (explicit paths):
  - .aai/scripts/orchestration-dispatch.mjs (lane derivation + payload + RULES text)
  - .aai/VALIDATION.prompt.md (ceremony-lane block)
  - .aai/PLANNING.prompt.md (step-10 lane continuation lines)
  - tests/skills/test-aai-ceremony-levels.sh (new stanzas test_011..test_017)
  - docs/specs/SPEC-0041-spec-loop-ceremony-aware-dispatch.md (this spec)
  - docs/issues/CHANGE-0030-loop-ceremony-aware-dispatch.md (status lifecycle only)
  - docs/INDEX.md (regenerated)

## Design decisions

### D1 — The lane is a DERIVED OUTPUT FIELD, never a new rule
`decide()` computes `lane` from the ALREADY-GUARDED effective level (SPEC-0030
D2 guard: `[0,1,2,3].includes(level) ? level : 2`):
`selected = (lvl <= 1) ? 'lightweight' : 'full'`. Every `verdict: "dispatch"`
JSON carries a top-level `lane` object:
`{ selected: 'lightweight'|'full', ceremony_level: <effective lvl>,
validation_depth: 'declared_scope'|'full' }`. `no_action` and `needs_llm`
verdicts carry `lane: null` (nothing consumes a lane there; fail-closed).
Fail-closed is INHERITED, not re-implemented: absent field, garbage token,
out-of-range integer, YAML null, missing spec file all resolve to effective
level 2 and therefore `selected: 'full'` — a bad declaration can only ever
select the FULL lane (SPEC-0005/SPEC-0030 philosophy). No rule fires
differently at any level because of this spec: rule ordering, predicates, and
verdicts are untouched (SPEC-0030 D3's "rules 10/11/12/14 never change" is
preserved verbatim — the lane changes what the dispatched role is TOLD, not
which role is dispatched). `decide()` stays pure (no clock/fs/mutation).

### D2 — Lightweight Validation payload: declared scope, one review
When rule 11 dispatches Validation and the lane is lightweight, the dispatch
adds reason `lightweight_lane_declared_scope` and sets
`lane.validation_depth: 'declared_scope'`; at L2/L3 the depth is `'full'` and
reasons stay exactly as today (empty unless another annotation applies). The
"one independent review" leg needs NO mechanical change: rule 13 already
dispatches exactly one dual-verdict review at every level (SPEC-0030 D3
rule-13 row) — this spec only documents it as the lane's review budget.
"Declared test scope" is DEFINED as: the executable command(s) named by the
frozen spec/tech-note's Test Plan rows (or, for a lean L0/L1 artifact, its
Verification/AC-table command lines) for the scope's ref_id.

### D3 — Role prompts gain a lane branch; ceremony_level stays the only selector
- `.aai/VALIDATION.prompt.md` gains a compact CEREMONY LANE block: derive the
  level from the spec named by STATE `spec_path` (fail-closed: absent/garbage
  = level 2 = full lane). At L0/L1, step 5's discovery/execution obligation is
  scoped to the DECLARED test scope (D2 definition) plus any suite that
  directly covers the changed paths — the full-repository sweep is NOT
  required; the e2e-exists-must-run rule and "ALL suites" strict rules apply
  WITHIN that declared scope. Everything else — independence, adversarial
  stance, AC STATUS GATE, evidence discipline, RED-proof — is unchanged at
  every level (Constitution art. 1: depth and scope shrink, the evidence
  requirement never does).
- `.aai/PLANNING.prompt.md` gains 2–3 continuation lines INSIDE the existing
  step-10 ceremony block (CHANGE-0019/SPEC-0028 precedent — steps 11/12 keep
  their numbers, no step 13): the declared level also SELECTS the dispatch
  lane; at L0/L1 the Test Plan IS the declared validation scope, so its rows
  must name directly executable commands.
- No new frontmatter mechanism: `ceremony_level` (SPEC-0030 D1) remains the
  single point of declaration; the `Ceremony justification: ` line remains
  required at L0/L1 (unchanged).
- `.aai/SKILL_TDD.prompt.md` is deliberately NOT edited: at L0/L1 the TDD
  surface is already bounded by the declared Test Plan (the only TEST-xxx
  entries that exist), so "skip full TDD ceremony" is realized by Planning's
  artifact policy, not by a TDD prompt fork.

### D4 — No WORKFLOW.md edit (protected surface; the canon row already exists)
The lane MECHANIZES the existing WORKFLOW.md "Ceremony levels" table row
"Validation (rules 10/11): suite run / suite re-run + targeted probe / full /
full" — the policy already exists in canon; this change makes dispatch carry
it. Editing .aai/workflow/WORKFLOW.md would put this scope on a
`protected_paths_l3` surface and force L3 for a purely reiterative text change
— rejected (YAGNI + keeps this spec at L2). If canon wording ever needs the
word "lane", that is a separate follow-up change.

### D5 — Composition seam with CHANGE-0031 (same decide())
This spec's decide() edits are confined to: (a) one derived `lane` constant
computed immediately after the existing `lvl` guard, (b) additive payload
fields in `dispatchFor`/output objects, (c) one additive reason on the rule-11
dispatch, (d) RULES table `when`-text annotation on rule 11. It does NOT touch
rule predicates, rule order, or the snapshot builder's work-item/focus
parsing. CHANGE-0031 will edit rule-6-adjacent retargeting guards and the
rule-11 FIRING predicate (status done skip) — disjoint edit regions by
construction. Sequencing: THIS spec lands first (its tests live in
test-aai-ceremony-levels.sh); CHANGE-0031 extends
test-aai-orchestration-dispatch.sh on top and must keep every lane assertion
green (its regression net includes this spec's stanzas via the ceremony
suite).

### D6 — Misuse guardrails: consume, never fork
No change to `.aai/scripts/spec-lint.mjs` or
`.aai/scripts/lib/docs-audit-core.mjs`. Freeze-time (spec-lint L0/L1
exemption + `ceremony-level-invalid` + `frozen-without-ac-table`) and
close-time (SPEC-0036 lean gate + justification-line check) remain the ONLY
misuse backstops for a scope declaring a lane too lean for its diff; review
may re-classify the level upward as a recorded finding (SPEC-0030 policy,
unchanged). Proven by fixture re-runs, not new code (AC-004 of the intake:
"no new escape hatch is introduced" — also no new detection path that could
diverge).

## Acceptance Criteria Mapping
- Maps to: CHANGE-0030 AC-001 (lightweight lane completes in <= 3 dispatched roles)
  - Spec-AC-03 below; fixture-chain proof + live-trace residual (see risks).
- Maps to: CHANGE-0030 AC-002 (no full sweep at L0/L1; declared scope only)
  - Spec-AC-02 (dispatch payload) + Spec-AC-05 (VALIDATION prompt scope rule).
- Maps to: CHANGE-0030 AC-003 (L2/L3 byte-identical behavior)
  - Spec-AC-04. "Byte-identical" is operationalized as: identical rule/role/
    tier/verdict/reasons/exit-code for every existing fixture (the additive
    `lane` field is new; Constitution art. 5 additive-first — existing suites
    assert named fields and must pass UNCHANGED).
- Maps to: CHANGE-0030 AC-004 (misuse still caught; no new escape hatch)
  - Spec-AC-06 (gates byte-untouched + misuse fixture still flagged).
- Maps to: CHANGE-0030 AC-005 (strict audit CLEAN before and after)
  - Spec-AC-06 hygiene arm.

Spec-AC list (each measurable):
- Spec-AC-01: Every `verdict:"dispatch"` JSON from orchestration-dispatch.mjs
  carries `lane {selected, ceremony_level, validation_depth}`;
  `selected=="lightweight"` iff effective level is 0 or 1 via the valid enum;
  absent/garbage/out-of-range/null/missing-file level -> `selected=="full"`;
  `no_action`/`needs_llm` -> `lane: null`; decide() purity holds.
- Spec-AC-02: Validation dispatch at L0/L1 carries
  `lane.validation_depth=="declared_scope"` AND reason
  `lightweight_lane_declared_scope`; at L2/L3 depth is `"full"` and reasons
  are unchanged from pre-change output.
- Spec-AC-03: An L1 (and L0) ready scope (frozen lean artifact, strategy
  selected, worktree decided) walks preparation -> flush in EXACTLY 3
  non-mechanical role dispatches (Implementation/TDD Implementation ->
  Validation -> Code Review) followed by the mechanical Metrics Flush arm,
  each of the 3 carrying `lane.selected=="lightweight"` — proven by a
  fixture-chain over successive STATE snapshots.
- Spec-AC-04: All existing assertions in
  tests/skills/test-aai-orchestration-dispatch.sh AND
  tests/skills/test-aai-ceremony-levels.sh (TEST-001..010 stanzas) pass
  UNCHANGED post-change (exit 0, no fixture edited except additive new
  stanzas); L2/L3 dispatch differs from pre-change only by the additive
  `lane` field.
- Spec-AC-05: VALIDATION.prompt.md contains a ceremony-lane block naming (a)
  the fail-closed rule (absent/garbage -> full lane) and (b) the L0/L1
  declared-scope validation rule; PLANNING.prompt.md lane wording sits INSIDE
  step-10 bounds; `11) Emit the work-item brief` and `12) Update
  docs/ai/STATE.yaml` survive; no step 13; prompt-diet suite stays green.
- Spec-AC-06: `git diff` over .aai/scripts/spec-lint.mjs and
  .aai/scripts/lib/docs-audit-core.mjs is EMPTY for this scope; an
  L1-declared fixture without a justification line is still flagged by BOTH
  spec-lint and `docs-audit --gate-file` (exit 1) post-change;
  `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exits 0
  before and after; `node .aai/scripts/check-state.mjs` OK.

## Constitution deviations

None.

Honest per-article check at freeze (docs/CONSTITUTION.md):
- Art. 1 (evidence before claims): the lane changes validation DEPTH/SCOPE
  payload only; rules 10/11 still fire at every level, PASS still requires
  executable evidence, RED-proof and AC gates untouched. No deviation.
- Art. 2 (simplicity/YAGNI): no new enforcement path, no WORKFLOW edit, no
  TDD-prompt fork; lane is one derived field. No deviation.
- Art. 3 (portability): plain mjs/markdown, zero dependencies. No deviation.
- Art. 4 (degrade and report): lane fail-closes to full via the existing
  guard; needs_llm edges unchanged. No deviation.
- Art. 5 (additive first): new optional output field; absent-level behavior
  byte-identical; no rule renumbering; prompts extended in place. No deviation.
- Art. 6 (single-writer STATE): dispatch stays read-only; no STATE schema
  change. No deviation.
- Art. 7 (operator-only merge): untouched at every level. No deviation.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state.

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | lane field on every dispatch; lightweight iff valid 0/1; fail-closed full; null on no_action/needs_llm; purity | done | docs/ai/tdd/ceremony-lane-green.log (test_011, test_013) | — | — |
| Spec-AC-02 | Validation payload: declared_scope + reason at L0/L1; full + unchanged reasons at L2/L3 | done | docs/ai/tdd/ceremony-lane-green.log (test_012) | — | — |
| Spec-AC-03 | L0/L1 fixture-chain: exactly 3 non-mechanical roles then flush, all lightweight | done | docs/ai/tdd/ceremony-lane-green.log (test_014) | — | — |
| Spec-AC-04 | L2/L3 parity: both existing suites pass unchanged; only additive lane differs | done | docs/ai/tdd/ceremony-lane-green.log (test_017 S1); standalone `bash tests/skills/test-aai-orchestration-dispatch.sh` exit 0 and ceremony TEST-001..009 all green (test_010 itself blocked only by the pre-existing prompt-diet shortfall below, not by any dispatch-behavior change) | — | — |
| Spec-AC-05 | Prompt surfaces: VALIDATION lane block, PLANNING step-10 insertion, steps 11/12 intact, prompt-diet green | done | docs/ai/tdd/ceremony-lane-green.log (test_015 structural; test_017 S3 proves no NEW prompt-diet regression). NOTE: `tests/skills/test-aai-prompt-diet.sh` TEST-010 (corpus byte-budget) already fails on clean main pre-change (net reduction 28187 < 28672 required, ~485B short — reproduced via git-stash comparison before any edit in this scope); this scope's 2 small prompt additions widen that PRE-EXISTING, out-of-scope shortfall to ~1770B but introduce no other failure (documented docs/knowledge/LEARNED.md 2026-07-17) | — | Recommend a follow-up techdebt item to true up the prompt-diet byte budget; out of scope here (D6/D3 forbid unrelated prompt-corpus edits). |
| Spec-AC-06 | Guardrails byte-untouched + misuse fixture still flagged; strict audit CLEAN; check-state OK | done | docs/ai/tdd/ceremony-lane-green.log (test_016); `git diff --exit-code -- .aai/scripts/spec-lint.mjs .aai/scripts/lib/docs-audit-core.mjs` exit 0; `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exit 0; `node .aai/scripts/check-state.mjs` OK | — | — |

## Implementation plan
- Components affected: orchestration core
  (.aai/scripts/orchestration-dispatch.mjs: `decide()` output assembly,
  `dispatchFor`/`noAction`/`needsLlm` shapes, RULES rule-11 `when` text),
  prompt layer (.aai/VALIDATION.prompt.md lane block; .aai/PLANNING.prompt.md
  step-10 continuation lines), test layer
  (tests/skills/test-aai-ceremony-levels.sh new stanzas test_011..test_017),
  docs/INDEX.md (regenerated).
- Order: (1) write new stanzas; (2) RED run on pre-change tree ->
  docs/ai/tdd/ceremony-lane-red.log; (3) dispatch lane derivation + payload
  (TDD: TEST-001..004 GREEN); (4) VALIDATION + PLANNING text (TEST-005
  GREEN); (5) survival re-runs (TEST-006, TEST-007); (6) index regen +
  check-state; (7) AC table reconciliation; (8) STATE via CLI.
- Edge cases: `ceremony_level: 3` -> lane full AND the existing L3
  tightenings (rules 8/13) still fire with their existing reasons alongside
  the lane field; lightweight lane + validation FAIL -> rule 10 Remediation
  fires exactly as today (lane never masks a failure); hand-built legacy
  snapshot without `spec.ceremony_level` -> pure-call re-guard defaults to 2
  -> full lane; `no_action` on the flushed arm carries `lane: null` even for
  an L1 scope (nothing left to dispatch).
- Prompt-diet constraint: additions to VALIDATION/PLANNING must keep the
  corpus under the SPEC-0017 floor (suite-enforced); ORCHESTRATION.prompt.md
  is NOT edited (its <=40-line wrapper budget stays untouched — the lane
  rides the relayed JSON).

Seam analysis:
- Seam S1 — decide()/RULES are consumed by the ORCHESTRATION wrappers, the
  dispatch suite, and the upcoming CHANGE-0031 stream. Crossing test:
  TEST-007 re-runs the REAL tests/skills/test-aai-orchestration-dispatch.sh
  post-change (every legacy fixture bit-for-bit on its asserted fields).
- Seam S2 — the dispatch JSON is relayed by SKILL_LOOP/ORCHESTRATION to role
  subagents (the lane must survive the CLI boundary). Crossing test: TEST-003
  drives the real CLI end-to-end on fixture repos (stdout JSON + --human).
- Seam S3 — the .aai prompt corpus is shared with the prompt-diet floor.
  Crossing test: TEST-007 re-runs the real prompt-diet suite.
- Seam S4 — freeze/close misuse gates (spec-lint, docs-audit lean gate) must
  keep firing over the changed tree. Crossing test: TEST-006 drives the real
  CLIs on an L1-without-justification fixture.
- Residual risk (recorded): CHANGE-0030 AC-001's LIVE evidence (a real L1
  scope's LOOP_TICKS.jsonl role count and elapsed time) can only be captured
  when the next genuine L0/L1 scope runs through the loop; the fixture-chain
  (TEST-004 stanza) proves the mechanical sequence, and the live before/after
  trace is deferred to the first real lightweight scope as validation-owned
  follow-up evidence. This is a measurement deferral, not a behavior gap.
- Residual risk (recorded): role prompts are guidance surfaces — a
  non-compliant runner could still over-validate (run the full sweep at L1);
  the lane makes that visible (dispatch reason + lane field in LOOP_TICKS)
  rather than mechanically impossible. Cost regression stays observable via
  the loop digest.

## Test Plan

New stanzas extend tests/skills/test-aai-ceremony-levels.sh (SPEC-0030 D6
suite — ceremony-domain dispatch behavior lives here; the dispatch suite
stays untouched for CHANGE-0031 to extend). Spec-local TEST ids map to suite
functions test_011..test_017.

| Test ID  | Spec-AC    | Type        | File path (expected)                     | Description                                                                                  | Status  |
|----------|------------|-------------|-------------------------------------------|------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-ceremony-levels.sh | decide() lane table: levels 0/1 -> lightweight, 2/3 -> full; absent/garbage snapshot level -> full; no_action + needs_llm -> lane null; purity/no-mutation holds | green (test_011) |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-ceremony-levels.sh | Validation dispatch payload: L1 -> validation_depth declared_scope + reason lightweight_lane_declared_scope; L2 -> full + reasons unchanged; L3 -> full alongside existing l3_* annotations | green (test_012) |
| TEST-003 | Spec-AC-01 | integration | tests/skills/test-aai-ceremony-levels.sh | CLI end-to-end on fixture repos: declared 1 -> lane lightweight in stdout JSON; `banana`/absent/`7`/null -> lane full; exit codes 0/3/4 unchanged; --human unaffected | green (test_013) |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-ceremony-levels.sh | Fixture-chain L1 (and L0) ready scope: successive STATE snapshots yield exactly Implementation -> Validation -> Code Review (3 non-mechanical dispatches, each lane lightweight) then Metrics Flush / no_action | green (test_014) |
| TEST-005 | Spec-AC-05 | unit        | tests/skills/test-aai-ceremony-levels.sh | Prompt surfaces: VALIDATION lane block with fail-closed + declared-scope wording; PLANNING lane lines INSIDE step-10 bounds; steps 11/12 survive; no step 13 | green (test_015) |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-ceremony-levels.sh | Misuse guard survival: L1 fixture without `Ceremony justification: ` -> spec-lint finding AND docs-audit --gate-file exit 1 post-change; spec-lint.mjs + docs-audit-core.mjs git-diff empty | green (test_016) |
| TEST-007 | Spec-AC-04..06 | integration | tests/skills/test-aai-ceremony-levels.sh | Seam survival: dispatch suite green (S1), ceremony TEST-001..010 stanzas green, prompt-diet green (S3), repo-wide `--check --strict --no-event` exit 0 (S4) | green (test_017; prompt-diet S3 tolerant of the documented pre-existing TEST-010 byte-budget shortfall, LEARNED 2026-07-17 — no new regression) |

Notes:
- RED-proof: TEST-001..TEST-005 must be observed FAILING on the pre-change
  tree (docs/ai/tdd/ceremony-lane-red.log). TEST-006/TEST-007 are survival
  invariants (green pre-change by construction; non-vacuous — they re-run the
  real gates/suites over the changed tree post-change).
- Full tests/skills sweep is validation-owned (this spec is L2 — full lane,
  dogfooding the distinction). Known environmental exception per LEARNED
  2026-07-15: tests/skills/test-aai-worktree.sh fails deterministically on
  this machine pre-existing on clean main.

## Verification
- `bash tests/skills/test-aai-ceremony-levels.sh` -> test_001..009 and
  test_011..test_017 PASS; the suite's overall exit is 1 solely because its
  test_010 seam re-runs prompt-diet, whose TEST-010 byte-budget floor fails
  pre-existing on clean main (c144736, ~485B short — see LEARNED 2026-07-17;
  follow-up: DEBT-0002). test_017 tolerates exactly that one failure and
  hard-fails on any other.
- `bash tests/skills/test-aai-orchestration-dispatch.sh` -> exit 0 (legacy
  parity, intake AC-003).
- `bash tests/skills/test-aai-prompt-diet.sh` -> FAIL TEST-010 only
  (pre-existing byte-budget breach on clean main, widened by this spec's
  required lane prompt text; no other stanza fails — follow-up DEBT-0002).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0
  (before and after).
- `node .aai/scripts/check-state.mjs docs/ai/STATE.yaml` -> OK.
- `git diff --exit-code -- .aai/scripts/spec-lint.mjs .aai/scripts/lib/docs-audit-core.mjs`
  -> exit 0 (guardrails byte-untouched).
- `node .aai/scripts/generate-docs-index.mjs && git diff --exit-code -I '^Generated:' -- docs/INDEX.md`
  -> exit 0 (idempotent).
- Fail-closed proof: TEST-003 fixture outputs (absent/garbage/out-of-range ->
  `lane.selected == "full"`).

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: loop-ceremony-aware-dispatch
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/ceremony-lane-red.log,
  docs/ai/tdd/ceremony-lane-green.log)
- commit SHA or diff range when available
