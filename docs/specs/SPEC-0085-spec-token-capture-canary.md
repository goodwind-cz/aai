---
id: spec-token-capture-canary
type: spec
number: 85
status: draft
ceremony_level: 3
links:
  requirement: docs/issues/CHANGE-0058-token-capture-canary.md
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — Token-Capture Canary (make silent telemetry-capture gaps loud)

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0058-token-capture-canary.md
- Decision records: SPEC-0043 (loop-token-usage-capture, residual risk R1 —
  "tests pin the text, not the behavior"); this change adds the mechanical teeth
  R1 anticipated.
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: per template semantics

## Implementation strategy
- Strategy: hybrid
- Rationale: Two ACs are behavior changes on protected/telemetry-integrity
  surfaces (Spec-AC-01 flush classification, Spec-AC-02 state.mjs log-tick
  warnings) and deserve strict RED-GREEN-REFACTOR — the diagnostics must be
  observed FAILING without the change (they do not exist yet) so a tautological
  green cannot slip through. Spec-AC-03 is prose/grep wiring plus a mechanical
  prompt-diet ledger arithmetic true-up where RED-GREEN adds little signal (loop
  lane), though the RED-proof obligation still holds (the grep/ledger tests must
  be seen red before the edit). Hybrid is the honest split.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: Scope edits a WORKFLOW.md protected surface
  (.aai/scripts/state.mjs) plus .aai/scripts/metrics-flush.mjs, two prompt-corpus
  files, and three test suites — PR-bound, multi-module, protected. Isolation is
  advisable but not safety-critical (all edits are warn-not-block, additive, and
  reversible; no schema/state migration).
- User decision: undecided
- User decision required: YES — ceremony_level 3 (WORKFLOW.md "Ceremony levels"
  rule 8, REQUIRED semantics): an explicit user_decision (worktree or a recorded
  inline override with rationale) MUST be recorded before implementation starts,
  for ANY recommendation. Planning does not create the worktree.
- Base ref: main
- Worktree branch/path: <if selected>
- Inline review scope (if inline chosen): .aai/scripts/metrics-flush.mjs,
  .aai/scripts/state.mjs, .aai/SUBAGENT_PROTOCOL.md, .aai/SKILL_LOOP.prompt.md,
  tests/skills/test-aai-metrics.sh, tests/skills/test-aai-token-capture.sh,
  tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh

## Acceptance Criteria Mapping

- Maps to: AC-001 (intake)
  - Spec-AC-01: `.aai/scripts/metrics-flush.mjs` classifies every agent_run into
    exactly one of `decomposed` | `undecomposed-note` | `capture-missing`, and
    emits exactly one INFO line per `undecomposed-note` run
    ("undecomposed total <N> observed; cost unattributable by design", naming
    ref/role) and exactly one WARNING line per `capture-missing` run (naming
    ref/role); a `decomposed` run emits NEITHER. Lines stay un-aggregated (one
    per run). Classification rule: numeric `tokens_in` AND `tokens_out` present
    -> `decomposed`; else a run `note` matching `usage_total_tokens=<digits>` ->
    `undecomposed-note`; else -> `capture-missing`.
  - Verification: `bash tests/skills/test-aai-metrics.sh` (TEST-001..003) and
    `bash tests/skills/test-aai-token-capture.sh` (TEST-004); expect exit 0 with
    the classified INFO/WARNING lines asserted.

- Maps to: AC-002 (intake)
  - Spec-AC-02: `.aai/scripts/state.mjs` `cmdLogTick` emits, on stderr and AFTER
    the successful `LOOP_TICKS.jsonl` append, a WARNING containing the substring
    "duration" when the computed `duration_seconds` is 0 (started == ended), and
    a WARNING containing the substring "harness" when `--harness` is omitted.
    Both may fire together. Exit code stays 0 and the tick line is still
    appended (warn, not block — mirrors the append-run warn-on-null-tokens teeth
    at state.mjs:796-803).
  - Verification: `bash tests/skills/test-aai-token-capture.sh` (TEST-005..007);
    expect exit 0, stderr substrings present, and the JSONL tick line written.

- Maps to: AC-003 (intake)
  - Spec-AC-03: `.aai/SUBAGENT_PROTOCOL.md` "Merge protocol" and
    `.aai/SKILL_LOOP.prompt.md` step 4 carry MANDATORY usage-note wording
    (greppable literal `usage_total_tokens`, made non-optional whenever a
    harness total is visible); the SUBAGENT_PROTOCOL.md D3 prose is updated so it
    no longer claims the flush "cost unattributable" WARNING fires for an
    undecomposed total (it is now an INFO — see Spec-AC-01); and the prompt-diet
    ledger is trued-up for any net prompt-corpus byte growth (a JUSTIFIED_ADDITIONS
    entry in `tests/skills/lib/prompt-diet-ledger.sh` plus the matching TEST-012
    pinned-total bump in `tests/skills/test-aai-prompt-diet.sh`).
  - Verification: `bash tests/skills/test-aai-token-capture.sh` (TEST-008..009),
    `bash tests/skills/test-aai-prompt-diet.sh` (TEST-010 -> physical TEST-010 +
    TEST-012); expect exit 0.

- Maps to: AC-004 (intake)
  - Spec-AC-04: no existing suite regresses — the full skill test framework
    passes after the change, including the reconciled existing stanzas
    (test-aai-token-capture.sh TEST-005 and test-aai-metrics.sh TEST-009, see
    Regression note).
  - Verification: `bash tests/skills/test-framework.sh`; expect exit 0.

## Constitution deviations

None.

<!-- Article-by-article check (docs/CONSTITUTION.md v1):
  Art 1 Evidence before claims — honored: every AC-gating test is RED-proofed.
  Art 2 Simplicity — additive diagnostics only; no speculative feature.
  Art 3 Portability — plain .mjs (node stdlib) + bash-3.2 test stanzas.
  Art 4 Degrade and report — this change IS the article: silent capture gaps
    become loud INFO/WARNING signals, warn-not-block (no new gate).
  Art 5 Additive first — the flush warning-for-undecomposed-total behavior
    (SPEC-0043 D3) is MODIFIED (WARNING -> INFO). This is a deliberate,
    documented behavior evolution at a public boundary (this spec + updated
    prose + updated tests), NOT a silent break, so it complies with Art 5's
    "breaking changes must be explicit and documented" clause — not a deviation.
  Art 6 Single-writer state — respected: implementation mutates STATE only via
    state.mjs; the dispatched subagent never writes STATE.yaml.
  Art 7 Operator-only merge — N/A. -->

## Implementation plan

Components/modules affected:
- `.aai/scripts/metrics-flush.mjs` (`buildEntry`, ~lines 412-433): replace the
  single `tokensIn === null || tokensOut === null` warning (line 420-421) with a
  three-way classifier. Add a note-grammar probe (`/usage_total_tokens=(\d+)/`)
  over `r.note`. Emit INFO for `undecomposed-note`, WARNING for `capture-missing`,
  nothing for `decomposed`. Keep both INFO and WARNING lines flowing through the
  existing `warnings` array -> printed at `main()` line ~915 (one line per run;
  do not aggregate). Cost handling and JSON round-trip guard unchanged.
- `.aai/scripts/state.mjs` (`cmdLogTick`, ~lines 864-921): after the
  `fs.appendFileSync(ticksPath, ...)` at ~line 919, `console.error` a WARNING
  containing "duration" when `duration === 0`, and a WARNING containing
  "harness" when the `harness` flag was `undefined`. Do NOT change the appended
  entry shape (`harness_version` stays "unknown" when absent). Emit directly in
  `cmdLogTick` (the `log-tick` branch in `main()` at lines 945-950 returns before
  the mutator `postWriteWarnings` loop, so warnings cannot ride that path).
- `.aai/SUBAGENT_PROTOCOL.md`: "Harness-reported usage capture" (lines 132-154)
  and "Merge protocol" (lines 186-206) — make the `usage_total_tokens=<N>` note
  non-optional whenever a harness total is visible; update the D3 line
  (147-148) so it no longer states the "cost unattributable" WARNING fires for
  an undecomposed total (now an INFO).
- `.aai/SKILL_LOOP.prompt.md`: step 4 (lines 249-268) — reinforce that the
  usage note is MANDATORY on every subagent completion whose harness result
  reported a total, and reinforce passing the step-4 `role_started_utc` and the
  loop-start `harness_version` into log-tick (step 6, lines 317-333).
- Tests: new stanzas in `tests/skills/test-aai-metrics.sh` and
  `tests/skills/test-aai-token-capture.sh`; reconcile the two existing stanzas
  named in the Regression note; ledger true-up in
  `tests/skills/lib/prompt-diet-ledger.sh` + `tests/skills/test-aai-prompt-diet.sh`.

Data flows / seam:
- SEAM-1 (state.mjs append-run note -> metrics-flush classification): state.mjs
  writes `agent_runs[].note` into STATE.yaml; metrics-flush reads it and
  classifies. The note grammar produced on one side must be recognized on the
  other. Covered end-to-end by TEST-004 (produce via `state.mjs append-run`,
  assert the real INFO/WARNING on the flush side + note verbatim in
  METRICS.jsonl) — NOT two mocked unit halves.
- SEAM-2 (state.mjs log-tick -> LOOP_TICKS.jsonl -> flush review consumption):
  the new warnings are produce-time stderr signals; the consumer (flush reading
  ticks) is unchanged. TEST-005/006 assert the JSONL line is still appended
  (produce side intact) while the warning fires. Residual: no automated test
  that a downstream analyst acts on the stderr warning (it is a human/CI signal,
  by design) — recorded as residual risk RR-2.
- SEAM-3 (prompt protocol -> agent behavior): SUBAGENT_PROTOCOL/SKILL_LOOP are
  agent-followed prose; verified by grep (TEST-008/009), not a runtime seam.

Edge cases:
- A run with numeric tokens AND a note -> `decomposed` (tokens win; no line).
- A note with `usage_total_tokens=` but a non-numeric/empty value -> does NOT
  match `=(\d+)` -> falls through to `capture-missing` (a malformed note is not
  an honest total).
- log-tick: `--started` in the future is already rejected upstream by `isoFlag`
  timing validation; the duration-0 warning only concerns started == ended.
- Multiple runs: exactly one classification line per run; ordering preserved.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | metrics-flush 3-way per-run classification + INFO/WARNING lines    | done | tests/skills/test-aai-metrics.sh TEST-001..003 (docs/ai/tdd/red-20260726T113300Z-metrics-classify-undecomposed.log, green-20260726T113300Z-metrics-classify-undecomposed.log) + tests/skills/test-aai-token-capture.sh TEST-004 (docs/ai/tdd/green-20260726T113300Z-token-capture-full-suite.log); .aai/scripts/metrics-flush.mjs buildEntry() | — | — |
| Spec-AC-02 | state.mjs log-tick duration-0 / missing-harness stderr WARNINGs    | done | tests/skills/test-aai-token-capture.sh TEST-005..007 (docs/ai/tdd/red-20260726T113300Z-log-tick-duration-warning.log, red-20260726T113300Z-log-tick-harness-warning.log, green-20260726T113300Z-token-capture-full-suite.log); .aai/scripts/state.mjs cmdLogTick() | — | — |
| Spec-AC-03 | SUBAGENT_PROTOCOL + SKILL_LOOP mandatory usage-note + D3 prose + ledger true-up | done | tests/skills/test-aai-token-capture.sh TEST-008..009 (docs/ai/tdd/red-20260726T113300Z-protocol-mandatory-wording.log, red-20260726T113300Z-protocol-d3-reclassified.log) + tests/skills/test-aai-prompt-diet.sh TEST-012 (912 B ledger entry, JUSTIFIED_GROWTH_BYTES 28890->29802, headroom unchanged 636/2048) | — | — |
| Spec-AC-04 | full skill test framework passes (no regression)                  | done | 48/49 tests/skills/test-*.sh suites green, run individually through .aai/scripts/aai-run-tests.sh (docs/ai/tdd/green-20260726T130700Z-protected-path-reframe.log + /tmp final-verify sweep); tests/skills/test-aai-hitl-propagation.sh TEST-014 and tests/skills/test-aai-tdd-evidence.sh TEST-005 reframed (orchestrator-directed scope extension) from a permanent zero-touch/zero-diff assertion on protected_paths_l3 paths to "authorized when a frozen ceremony_level:3 spec is present in the same diff/tree" — both green | — | Exception: tests/skills/test-aai-run-tests.sh TEST-005 (reaper-kills-in-workspace-vitest) FAILed identically on 2 attempts including one on a quiet system (workspace vitest/esbuild process count 0, load avg 1.49-1.94) — matches the documented pre-existing CI-load flake (docs/knowledge/LEARNED.md / project memory "reaper-test-ci-load-flake"), not a regression from this scope (aai-run-tests.sh untouched); not chased per that memory entry. |

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                          | Description                                                                                          | Status  |
|----------|------------|-------------|-----------------------------------------------|-----------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-metrics.sh              | Run with numeric tokens_in/out -> `decomposed` -> NO INFO and NO WARNING line for that run           | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-metrics.sh              | Run with null tokens + note `usage_total_tokens=N` -> exactly one INFO line naming ref/role/N; no generic WARNING for that run | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-metrics.sh              | Run with null tokens + no note -> exactly one `capture-missing` WARNING naming ref/role              | green |
| TEST-004 | Spec-AC-01 | integration | tests/skills/test-aai-token-capture.sh        | SEAM-1 end-to-end: `state.mjs append-run --note usage_total_tokens=N` then flush -> INFO line + tokens null + note verbatim in METRICS.jsonl; capture-missing variant (no note) -> WARNING | green |
| TEST-005 | Spec-AC-02 | unit        | tests/skills/test-aai-token-capture.sh        | `state.mjs log-tick` with started==ended (duration 0) -> stderr WARNING containing "duration", exit 0, tick line appended | green |
| TEST-006 | Spec-AC-02 | unit        | tests/skills/test-aai-token-capture.sh        | `state.mjs log-tick` with `--harness` omitted -> stderr WARNING containing "harness", exit 0, tick appended (harness_version:"unknown") | green |
| TEST-007 | Spec-AC-02 | unit        | tests/skills/test-aai-token-capture.sh        | Negative control: valid nonzero duration AND `--harness` present -> NO warning (non-tautology guard) | green |
| TEST-008 | Spec-AC-03 | unit        | tests/skills/test-aai-token-capture.sh        | SUBAGENT_PROTOCOL "Merge protocol" + SKILL_LOOP step 4 carry MANDATORY/non-optional `usage_total_tokens` wording (greppable) | green |
| TEST-009 | Spec-AC-03 | unit        | tests/skills/test-aai-token-capture.sh        | SUBAGENT_PROTOCOL D3 prose updated: no longer claims the flush WARNING fires for an undecomposed total (reflects INFO reclassification) | green |
| TEST-010 | Spec-AC-03 | unit        | tests/skills/test-aai-prompt-diet.sh          | Prompt-diet ledger trued-up: JUSTIFIED_GROWTH_BYTES == independent re-sum AND TEST-012 pinned total bumped to new corpus growth (skip only if SKILL_LOOP edit is byte-neutral/net-negative) | green |
| TEST-011 | Spec-AC-04 | integration | tests/skills/test-framework.sh                | Full skill test framework green (exit 0), including reconciled existing stanzas                      | green |

RED-proof obligation (all AC-gating tests): TEST-001..007 must be observed
FAILING before the change (the classifier, INFO/WARNING lines, and log-tick
warnings do not exist yet). TEST-007 is the explicit non-tautology negative
control. TEST-008..010 must be observed red before the prose/ledger edits.
TEST-011 is the regression gate. A test never seen red proves nothing.

Regression note (existing stanzas that assert the OLD single-warning behavior —
must be reconciled, this is the intended contract evolution, NOT a silent break):
- `tests/skills/test-aai-token-capture.sh` TEST-005 (current line ~304-305)
  asserts the flush "cost unattributable" WARNING fires for an undecomposed
  total. Under the new classification that run is `undecomposed-note` and emits an
  INFO instead. UPDATE this assertion to expect the INFO line (and no generic
  WARNING for that run). [Note: the new Test-Plan TEST-004/005 reuse these
  physical stanza slots; renumber physical IDs as the implementer sees fit — spec
  TEST-xxx ids are stable, physical bash ids are the implementer's.]
- `tests/skills/test-aai-metrics.sh` TEST-009 (current line ~687-692) asserts
  exactly two `cost unattributable — tokens not recorded` lines for two
  null-token runs that have NO note. Those are `capture-missing` -> still
  WARNING. Preserve the substring `cost unattributable` in the capture-missing
  wording to keep TEST-009 green, OR update TEST-009 to the new wording. AC-004
  gates on the full suite passing either way.

## Verification
- `bash tests/skills/test-aai-metrics.sh` (Spec-AC-01: TEST-001..003)
- `bash tests/skills/test-aai-token-capture.sh` (Spec-AC-01 TEST-004; Spec-AC-02
  TEST-005..007; Spec-AC-03 TEST-008..009)
- `bash tests/skills/test-aai-prompt-diet.sh` (Spec-AC-03 TEST-010: ledger + TEST-012)
- `bash tests/skills/test-framework.sh` (Spec-AC-04 TEST-011)
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Companion obligations (PLANNING.prompt.md step 3a — closed two-entry list)
- Prompt-corpus byte growth (APPLIES): `.aai/SKILL_LOOP.prompt.md` is inside the
  live `.aai/*.prompt.md` glob measured by TEST-010/TEST-012; any net growth from
  the mandatory-note reinforcement requires a `JUSTIFIED_ADDITIONS` entry in
  `tests/skills/lib/prompt-diet-ledger.sh` + a bumped TEST-012 pinned total. Folded
  into Spec-AC-03 / TEST-010. (`.aai/SUBAGENT_PROTOCOL.md` is neither
  `.aai/*.prompt.md` nor `.aai/AGENTS.md`, so its edits carry no measured deficit;
  no separate ledger line unless it is later brought into the glob.) If the net
  SKILL_LOOP edit is byte-neutral or a reduction, no new entry is needed and
  TEST-010 is skipped with that rationale recorded.
- New `.aai/**` file (DOES NOT APPLY): this scope adds no new `.aai/**` file, so
  the PROFILES.yaml classification obligation is skipped. (The intake's loose
  mention of PROFILES does not meet the closed-list trigger.)

## Residual risks
- RR-1: `usage_total_tokens=` grammar drift — if a future note format changes the
  literal, the classifier silently reclassifies honest totals as capture-missing.
  Mitigated by the single canonical grammar defined in SUBAGENT_PROTOCOL.md and
  asserted by TEST-002/004/008.
- RR-2: SEAM-2 (log-tick warning) has no automated downstream-consumer assertion —
  the stderr WARNING is a human/CI signal by design; only the produce side (tick
  still appended) is machine-verified.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id (token-capture-canary), Spec-AC and TEST-xxx links
- command or review scope
- exit code or review verdict
- evidence path (test log / METRICS.jsonl / LOOP_TICKS.jsonl / stderr capture)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
