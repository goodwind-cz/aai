---
id: spec-loop-token-usage-capture
type: spec
number: 43
status: draft
ceremony_level: 2
links:
  change: loop-token-usage-capture
  rfc: null
  pr: []
  commits: []
---

# SPEC — Capture Harness-Reported Token Usage into log-tick / append-run (prompt-layer wiring)

SPEC-FROZEN: true

## Links
- Change: loop-token-usage-capture
  (docs/issues/CHANGE-0032-loop-token-usage-capture.md)
- Consumes (does NOT reopen): CHANGE-0010 D5 token-capture teeth
  (`state.mjs` warn-on-null append-run; PRICING.yaml cost lookup in
  `metrics-flush.mjs`) and SPEC-0012 transactional state CLI.
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Ceremony level
`ceremony_level: 2` — full pipeline. Multi-surface prompt-layer canon change
(SKILL_LOOP + SUBAGENT_PROTOCOL + ORCHESTRATION + five role prompts + one new
test suite), so not L1 (single surface); it touches NO `protected_paths_l3`
entry (`state.mjs`, `metrics-flush.mjs` and `WORKFLOW.md` are explicitly
NOT edited — verify-only), so L3 is not forced.

## Problem statement (verified facts)
1. Every `agent_runs[]` entry flushed on 2026-07-16/17 has
   `tokens_in: null, tokens_out: null, cost_usd: null`;
   `metrics-flush.mjs:356` prints `cost unattributable — tokens not recorded`
   for each (condition: either token field null).
2. The flag surface ALREADY exists and is tested:
   `append-run` accepts `--tokens-in --tokens-out --note` (state.mjs:191,
   706-707); `log-tick` accepts `--tokens-in --tokens-out --cache-read --cost`
   (state.mjs:192-194). `runCostUsd` (lib/pricing.mjs:85-91) computes cost
   ONLY when BOTH token counts are integers. No schema change is needed.
3. The gap is caller-side: no canon instruction tells the dispatching PARENT
   (the only party that can see a subagent's usage — the harness reports it in
   the Agent tool result on completion, e.g. `subagent_tokens: 262134`) to
   carry that figure into the CLI calls. Role prompts instruct roles to
   self-append their run, but a role agent CANNOT observe its own usage, so
   those entries are structurally null forever.
4. The harness-exposed shape varies by execution path:
   - DECOMPOSED: e.g. headless `claude -p --output-format json` returns a
     `usage` object (`input_tokens`, `output_tokens`,
     `cache_read_input_tokens`) and `total_cost_usd`.
   - UNDECOMPOSED TOTAL: the in-session Agent tool reports a single combined
     token count per completed subagent. A total cannot honestly populate
     `tokens_in`/`tokens_out` (splitting or relabeling it fabricates a
     component claim, and input/output prices differ, so a mislabeled total
     would also poison `cost_usd`).
   - NOTHING: some paths expose no usage at all.

## Design decisions (attribution semantics — decided, not deferred)
- D1 (source of truth): usage is captured ONLY from the harness-level result
  visible to the dispatching parent. A subagent's self-reported number is
  never accepted (it cannot observe its own usage; any figure it produced
  would be fabricated).
- D2 (decomposed shape): pass values through the EXISTING flags —
  `append-run --tokens-in N --tokens-out N`;
  `log-tick --tokens-in N --tokens-out N [--cache-read N] [--cost X]`
  (`--cost` only when the runtime itself reports a real cost figure).
- D3 (undecomposed total): record the total VERBATIM in the append-run note
  using the fixed grammar token `usage_total_tokens=<integer>` (recommended
  full form: `usage_total_tokens=<N> (harness total; in/out not exposed)`).
  Numeric token flags are OMITTED. Never split a total into in/out
  components; never relabel it as `tokens_out` or `tokens_in`. The
  "cost unattributable" flush warning CONTINUES to fire for such runs — that
  is CORRECT (dollars genuinely cannot be computed from an undecomposed
  total), not a defect. Grammar is defined ONCE in `.aai/SUBAGENT_PROTOCOL.md`.
- D4 (nothing exposed): omit all usage flags — existing null behavior is
  preserved byte-for-byte. No estimation path exists anywhere.
- D5 (append ownership): when a role runs as a DISPATCHED SUBAGENT, the
  orchestrator/parent appends its run (`append-run`) at merge time, attaching
  harness-reported usage per D2/D3 — this aligns live practice with the
  EXISTING single-writer rule (SUBAGENT_PROTOCOL "Single-writer rule" +
  merge step 3, Constitution art. 6). Role prompts get a short subagent-mode
  carve-out; DIRECT execution (operator dispatches the role with no
  orchestrating parent, or in-session fallback) keeps today's self-append
  with usage flags omitted.
- D6 (run-budget guard): SKILL_LOOP stop condition f's cumulative tally
  counts BOTH tick-line `input_tokens + output_tokens` sums AND the
  harness-reported undecomposed totals observed at subagent completions this
  run. No usage observed → the guard remains a no-op (unchanged).
- D7 (byte discipline): the prompt-diet corpus (`.aai/*.prompt.md`) has an
  already-failing byte floor (TEST-010, ~485 B short on clean main — see
  docs/knowledge/LEARNED.md 2026-07-17). Detailed protocol text therefore
  lives in `.aai/SUBAGENT_PROTOCOL.md` (NOT in the corpus); each
  `.aai/*.prompt.md` edit is at most ~2 lean lines.

## Implementation strategy
- Strategy: loop
- Rationale: prompt-layer canon text plus one bash contract/fixture suite —
  mechanical wiring with no core script logic; RED-GREEN per test adds little
  signal. RED-proof obligation still applies: TEST-001..004 must be observed
  FAILING on the unedited canon before edits (see Test Plan).

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: multi-file but low-risk prompt/docs/tests-only scope; no
  protected paths, no migrations. Operator has ALREADY recorded
  `user_decision: inline` on `feat/loop-token-usage-capture` in STATE — that
  recorded decision stands; Planning does not override it.
- User decision: inline (pre-recorded by operator)
- Base ref: main
- Inline review scope: see Code review scope below.
- Code review required: true (workflow-canon + test changes)
- Code review scope (explicit paths):
  `.aai/SKILL_LOOP.prompt.md`, `.aai/SUBAGENT_PROTOCOL.md`,
  `.aai/ORCHESTRATION.prompt.md`, `.aai/PLANNING.prompt.md`,
  `.aai/IMPLEMENTATION.prompt.md`, `.aai/VALIDATION.prompt.md`,
  `.aai/REMEDIATION.prompt.md`, `.aai/SKILL_TDD.prompt.md`,
  `tests/skills/test-aai-token-capture.sh`,
  `docs/specs/SPEC-0043-spec-loop-token-usage-capture.md`,
  `docs/issues/CHANGE-0032-loop-token-usage-capture.md`, `docs/INDEX.md`

## Acceptance Criteria Mapping
- Maps to: CHANGE-0032 AC-001
  - Spec-AC-01: Canon instructs the dispatching parent to read the
    harness-reported usage from each completed subagent's tool result and,
    when the shape is DECOMPOSED, pass it via `append-run
    --tokens-in/--tokens-out` and `log-tick --tokens-in/--tokens-out
    [--cache-read] [--cost]` (D1/D2). Instruction present in
    `.aai/SKILL_LOOP.prompt.md` (step 4 capture + step 6 flags) and
    `.aai/SUBAGENT_PROTOCOL.md` (usage-capture section + merge step 3).
  - Verification: TEST-001 (canon contract, REDs on baseline); TEST-006
    (existing substrate proof: flags → non-null → computed `cost_usd`, no
    warning).
- Maps to: CHANGE-0032 AC-001 + AC-002 (single-total honesty)
  - Spec-AC-02: `.aai/SUBAGENT_PROTOCOL.md` defines the
    `usage_total_tokens=<N>` note grammar for UNDECOMPOSED totals (D3) and
    explicitly prohibits splitting or relabeling a total into
    `tokens_in`/`tokens_out`; absent usage → omit flags (D4, unchanged
    behavior).
  - Verification: TEST-002 (canon contract, REDs); TEST-005 (integration
    seam fixture: note round-trips append-run → STATE → metrics-flush →
    METRICS.jsonl with tokens null and the warning still firing).
- Maps to: CHANGE-0032 AC-001 (who can capture) + Constitution art. 6
  - Spec-AC-03: All five role prompts (`PLANNING`, `IMPLEMENTATION`,
    `VALIDATION`, `REMEDIATION`, `SKILL_TDD` `.prompt.md`) carry a
    subagent-mode carve-out in their METRICS section: dispatched-as-subagent
    → do NOT self-append; return the result block and the orchestrator
    appends the run with harness-reported usage (D5, referencing
    `.aai/SUBAGENT_PROTOCOL.md`); direct execution → self-append unchanged.
    `.aai/ORCHESTRATION.prompt.md` instructs the orchestrator to append the
    completed role's run with usage per the protocol.
  - Verification: TEST-003 (canon contract across all six files, REDs).
- Maps to: CHANGE-0032 Desired Behavior (run-budget guard effective)
  - Spec-AC-04: `.aai/SKILL_LOOP.prompt.md` stop condition f counts
    harness-reported undecomposed totals observed this run in the cumulative
    token tally, alongside tick-line `input_tokens + output_tokens` (D6);
    the never-fabricate no-op clause for absent data is retained verbatim.
  - Verification: TEST-004 (canon contract, REDs).
- Maps to: CHANGE-0032 AC-002 + AC-003 + AC-004
  - Spec-AC-05: No regression: `tests/skills/test-aai-state.sh` and
    `tests/skills/test-aai-metrics.sh` exit 0 unchanged;
    `.aai/scripts/state.mjs` and `.aai/scripts/metrics-flush.mjs` have ZERO
    diff (verify-only); repo docs audit stays clean
    (`node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0).
  - Verification: TEST-007 (suite re-runs + `git diff --stat` on the two
    scripts empty + docs-audit exit 0).

Honest refinement of intake AC-003 (recorded, not silent): "runs that
captured real usage" means runs with DECOMPOSED usage. A run whose harness
exposed only an undecomposed total keeps its flush warning — cost is
genuinely unattributable from a total, and silencing the warning would hide
that fact. This follows the intake's own never-fabricate constraint.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                             | Status  | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Parent captures decomposed usage into existing flags     | done | TEST-001 PASS, docs/ai/tdd/token-capture-green.log; SKILL_LOOP.prompt.md step 4/6, SUBAGENT_PROTOCOL.md "Harness-reported usage capture" (D1/D2) | — | working tree, branch feat/loop-token-usage-capture (inline, not yet committed) |
| Spec-AC-02 | `usage_total_tokens=` note grammar; never split totals   | done | TEST-002 + TEST-005 PASS, docs/ai/tdd/token-capture-green.log; SUBAGENT_PROTOCOL.md "Harness-reported usage capture" (D3/D4) | — | working tree, branch feat/loop-token-usage-capture (inline, not yet committed) |
| Spec-AC-03 | Subagent-mode append ownership (orchestrator appends)    | done | TEST-003 PASS, docs/ai/tdd/token-capture-green.log; carve-out in PLANNING/IMPLEMENTATION/VALIDATION/REMEDIATION/SKILL_TDD.prompt.md METRICS sections + ORCHESTRATION.prompt.md step 2 | — | working tree, branch feat/loop-token-usage-capture (inline, not yet committed) |
| Spec-AC-04 | Condition f tally counts observed totals                 | done | TEST-004 PASS, docs/ai/tdd/token-capture-green.log; SKILL_LOOP.prompt.md stop condition f | — | working tree, branch feat/loop-token-usage-capture (inline, not yet committed) |
| Spec-AC-05 | No regression; state/flush scripts verify-only zero-diff | done | docs/ai/tdd/token-capture-regression-state.log (exit 0), docs/ai/tdd/token-capture-regression-metrics.log (exit 0), `git diff --stat` on state.mjs+metrics-flush.mjs empty, docs-audit --check --strict --no-event exit 0 (Verdict: CLEAN); `tests/skills/test-aai-prompt-diet.sh` TEST-011 PASS (ORCHESTRATION.prompt.md restored to 40 lines by reclaiming one blank section-separator line — D5 append instruction wording untouched, verbatim) | — | REMEDIATION (validation FAIL 2026-07-17T13:33Z): ORCHESTRATION.prompt.md had grown 40->41 lines, a NEW TEST-011 regression (not the tolerated DEBT-0002 class); fixed at cause by removing one blank line elsewhere in the file (root cause: line-count budget, not the D5 wording), re-verified PASS. prompt-diet TEST-010 byte floor pre-existing failure (DEBT-0002) unaffected by this scope: 25061 B net reduction vs 28672 B required (R3 — small corpus addition worsens the pre-existing gap) |

## Implementation plan
Edit points (all additive; each `.aai/*.prompt.md` addition ≤ ~2 lines, D7):
1. `.aai/SUBAGENT_PROTOCOL.md` — new section "Harness-reported usage capture"
   (single source): D1 source-of-truth rule; D2 flag mapping; D3
   `usage_total_tokens=<N>` grammar + never-split prohibition; D4 omit rule.
   Amend merge protocol step 3 (agent_runs bullet) to include harness usage;
   add one rationalization row ("I'll estimate the in/out split from the
   total" → never — record the total in the note or nothing).
2. `.aai/SKILL_LOOP.prompt.md` — step 4: after role completion, read
   harness-reported usage from the tool result (pointer to SUBAGENT_PROTOCOL
   section); step 6 COST bullet: totals are NOT passed as numeric flags —
   they flow to the merge append (D3) and the run tally (D6); stop condition
   f: tally includes observed undecomposed totals (D6).
3. `.aai/ORCHESTRATION.prompt.md` — one line at step 2/5: after the spawned
   role completes, append its run via `state.mjs append-run` with the
   harness-reported usage per SUBAGENT_PROTOCOL.
4. Role prompts (`PLANNING`, `IMPLEMENTATION`, `VALIDATION`, `REMEDIATION`,
   `SKILL_TDD`) — one-sentence METRICS carve-out (D5).
5. `tests/skills/test-aai-token-capture.sh` — new bash-3.2-compatible suite
   (pattern: existing tests/skills fixtures; state/flush invoked with
   `--state`/`--ticks` fixture overrides).
Edge cases: multiple subagents in one tick → per-subagent totals each counted
in the tally; per-run attribution stays at the existing one-append-run-per-
role-run granularity (intake constraint). Recovery ticks (`type: recovery`)
follow the same rules. A total that includes cache reads stays a total — no
decomposition is guessed.

## Seam analysis
- Seam 1: note grammar (produced by canon-following parents via `append-run
  --note`) ↔ `metrics-flush.mjs` note passthrough into METRICS.jsonl →
  crossed end-to-end by TEST-005 (append-run → STATE → flush → METRICS line).
- Seam 2: role prompts' METRICS sections ↔ SUBAGENT_PROTOCOL append
  ownership (double-append / zero-append risk) → TEST-003 asserts every
  carve-out names `.aai/SUBAGENT_PROTOCOL.md` (single source). Residual
  risk R1 below covers behavioral adherence.
- Seam 3: condition f ↔ `log-tick` field emission → existing
  `test-aai-state.sh` TEST-012 (no fabricated cost fields) + TEST-004.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                       | Description                                                                                              | Status  |
|----------|------------|-------------|--------------------------------------------|----------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-token-capture.sh     | Canon contract: SKILL_LOOP step 4/6 + SUBAGENT_PROTOCOL instruct parent-side decomposed-usage capture into existing flags | green |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-token-capture.sh     | Canon contract: SUBAGENT_PROTOCOL defines `usage_total_tokens=` grammar and prohibits splitting/relabeling totals | green |
| TEST-003 | Spec-AC-03 | unit        | tests/skills/test-aai-token-capture.sh     | Canon contract: 5 role prompts carry the subagent-mode append carve-out referencing SUBAGENT_PROTOCOL; ORCHESTRATION appends with usage | green |
| TEST-004 | Spec-AC-04 | unit        | tests/skills/test-aai-token-capture.sh     | Canon contract: SKILL_LOOP condition f counts observed undecomposed totals; never-fabricate no-op clause retained | green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-token-capture.sh     | Seam 1 fixture: `append-run --note "usage_total_tokens=262134 …"` w/o token flags → STATE note verbatim, tokens null, warn fires; flush emits METRICS line carrying the note and the unattributable warning | green |
| TEST-006 | Spec-AC-01 | integration | tests/skills/test-aai-metrics.sh (existing) | Substrate: runs WITH tokens get PRICING-computed `cost_usd` and NO warning (existing golden-ledger coverage, re-run) | green |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-state.sh + test-aai-metrics.sh | Regression: both suites exit 0; `git diff` on state.mjs + metrics-flush.mjs empty; docs-audit strict exit 0 | green |

RED-proof: TEST-001..004 MUST be observed failing against unedited canon
before any prompt edit (they grep for text that does not yet exist).
TEST-005/006/007 are substrate/regression guards that are green on baseline
BY DESIGN — they pin the pre-existing behavior the protocol depends on
(recorded RED-waiver; the anti-tautology obligation for the change itself is
carried by TEST-001..004, and every Spec-AC has at least one REDing test
except the pure no-regression Spec-AC-05, whose gate is baseline-green
re-run + zero-diff).

## Verification
- `bash tests/skills/test-aai-token-capture.sh` → exit 0 (TEST-001..005).
- `bash tests/skills/test-aai-state.sh` and
  `bash tests/skills/test-aai-metrics.sh` → exit 0 (TEST-006/007); run via
  `.aai/scripts/aai-run-tests.sh` per LEARNED wrapper rule.
- `git diff --stat -- .aai/scripts/state.mjs .aai/scripts/metrics-flush.mjs`
  → empty (verify-only surfaces untouched).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0.
- Live probe (validation lane, this harness): after canon lands, one real
  subagent completion recorded with `usage_total_tokens=<N>` in its
  `agent_runs[].note` (contrast with the all-null 2026-07-16/17 baseline).
  Decomposed-path AC-001 evidence is fixture-based (TEST-006) unless a
  decomposed-usage runtime is available during validation.
- Known pre-existing failures (NOT gates for this scope, verified on clean
  main per LEARNED 2026-07-15/17): `test-aai-worktree.sh` scratch-git
  fixture; `test-aai-prompt-diet.sh` TEST-010 byte floor (this change adds a
  small number of corpus bytes under D7 — re-record the TEST-010 delta in
  validation notes).

## Residual risks
- R1: Prompt-protocol adherence by LLM agents is not mechanically enforced
  (same class as SUBAGENT_PROTOCOL's existing honesty note / R-GUARD). The
  canon-contract tests pin the text, not the behavior.
- R2: If an orchestrator crashes between role completion and merge-append, a
  subagent-mode run goes unrecorded (today it would be recorded with nulls).
  Accepted trade-off for honest usage capture; the role's result block still
  carries timing for manual recovery.
- R3: Prompt-diet TEST-010 net-reduction number worsens by the added corpus
  bytes (already failing pre-existing; D7 minimizes the delta).

## Evidence contract
For each implementation, validation, and code review artifact record:
ref_id `loop-token-usage-capture`, Spec-AC + TEST-xxx links, command or
review scope, exit code or verdict, evidence path, commit SHA/diff range.
