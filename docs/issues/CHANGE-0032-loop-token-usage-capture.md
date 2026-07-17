---
id: loop-token-usage-capture
type: change
number: 32
status: draft
links:
  pr: []
  commits: []
---

# Change — Capture Real Runtime Token Usage into log-tick / append-run

## Summary
The loop runner currently discards real runtime token usage. Subagent
results carry actual token counts (input/output/cache), but by the time a
tick or a run is recorded via `state.mjs log-tick` and
`state.mjs append-run`, those fields are passed as null — every single
`agent_runs` entry in `docs/ai/METRICS.jsonl` across two full days of
operation (2026-07-16, 2026-07-17) has `tokens_in: null, tokens_out: null,
cost_usd: null`. This change wires the runtime-exposed usage values through
`log-tick --tokens-*` and `append-run --tokens-in/--tokens-out` when the
harness actually provides them, while strictly preserving the existing
never-fabricate rule (a value the runtime does not expose stays null, never
estimated).

## Motivation / Business Value
- `.aai/scripts/metrics-flush.mjs:356` emits
  `WARNING <ref> run <role> (<model>): cost unattributable — tokens not
  recorded` for every run with null tokens — confirmed firing across all-day
  METRICS.jsonl entries on both 2026-07-16 and 2026-07-17 (5 date-matching
  entries sampled, every `agent_runs[].tokens_in/tokens_out/cost_usd` field
  null, e.g. `CHANGE-0010`, `doctor-vendored-layer-drift`,
  `single-dual-verdict-review`, `ISSUE-0007`, `learned-to-layer-promotion`,
  `CHANGE-0014`).
- `.aai/SKILL_TDD.prompt.md` and `state.mjs` both document `--tokens-in
  N --tokens-out N` as an ACCEPTED but apparently never-populated flag
  (`state.mjs:706-707`, `append-run --tokens-in/--tokens-out`), and
  `state.mjs:797-800` prints a WARNING when tokens are null but has no path
  that ever supplies them from the actual agent/subagent result.
- Consequence: the run-budget guard (`max_run_tokens`, referenced by the
  metrics/budget machinery) is currently inert — it can never fire because
  the values it would compare against are never recorded. This mirrors the
  EEX downstream complaint (a run burning ~20% of a weekly token budget with
  no attribution) — without real capture, no guard or dashboard can ever
  show WHERE the budget went.
- Subagent/tool-runner results DO carry usage in the harness (documented in
  the `claude-api` skill and standard Claude Agent SDK/Messages API
  response shape: `usage.input_tokens`, `usage.output_tokens`,
  `usage.cache_read_input_tokens`, etc.) — the gap is plumbing that value
  from the role/subagent result into the `log-tick`/`append-run` CLI calls
  the role prompts already issue, not a missing capability of the runtime.

## Scope
- In scope:
  - `.aai/scripts/state.mjs` `cmdLogTick`/`cmdAppendRun` — already accept
    `--tokens-in`/`--tokens-out` (log-tick also `--cache-read`, `--cost`);
    no schema change expected, this is a CALLER-side wiring change.
  - Role prompts / orchestration wrapper code paths that invoke
    `log-tick`/`append-run` after a subagent or role execution — extend them
    to read the real usage value the runtime/tool-runner result exposes and
    pass it through, when present.
  - `.aai/scripts/metrics-flush.mjs` — confirm the existing warning and
    `cost_usd` computation activate correctly once real values start
    flowing (no change expected if the flush logic is already
    value-agnostic; verify only).
- Out of scope:
  - Redesigning the METRICS.jsonl schema or the PRICING.yaml lookup
    machinery (CHANGE-0010) — reuse as-is.
  - Estimating or backfilling tokens for historical runs (the existing null
    entries stay null — no retroactive fabrication).
  - Any new budget-enforcement behavior beyond what `max_run_tokens` already
    specifies; this change only makes the guard's INPUT real, not its logic.

## Affected Area
- `.aai/scripts/state.mjs` (`log-tick`, `append-run` call sites in role
  prompts / orchestration wrappers).
- Role prompts that currently call these commands without token flags
  (`.aai/SKILL_TDD.prompt.md`, `.aai/VALIDATION.prompt.md`,
  `.aai/ORCHESTRATION.prompt.md`, and any wrapper script that shells out to
  `state.mjs` after a subagent completes).
- `.aai/scripts/metrics-flush.mjs` (warning/cost computation, verify-only).

## Desired Behavior (To-Be)
- Whenever the runtime/tool-runner exposes real usage for a completed role
  run or subagent invocation, the orchestration layer captures it
  immediately after the run and passes it to
  `state.mjs log-tick --tokens-in N --tokens-out N [--cache-read N] [--cost N]`
  and/or `state.mjs append-run --tokens-in N --tokens-out N` for that same
  run.
- When the runtime does NOT expose usage (e.g. a role executed without a
  tool-runner wrapper, or the field is genuinely unavailable in that
  execution context), the flags are omitted and the existing null/never-
  fabricate behavior is preserved byte-for-byte — this change adds a
  capture path, it never adds an estimation path.
- The `metrics-flush.mjs:356` "cost unattributable" warning stops firing for
  runs where real usage was captured (verified by absence of the warning in
  post-change flush output for such runs); it continues to fire, correctly,
  for any run where the runtime genuinely had no usage to report.
- `max_run_tokens` (or equivalent run-budget guard) becomes effective once
  fed real numbers, without this change altering its comparison logic.

## Acceptance Criteria
- AC-001: For at least one role/subagent execution path where the runtime
  exposes real token usage, the resulting `log-tick` and/or `append-run`
  call carries non-null `tokens_in`/`tokens_out` (and `cache_read`/`cost`
  where available) sourced from that real value — verified by inspecting
  the appended `docs/ai/LOOP_TICKS.jsonl` / `docs/ai/STATE.yaml` /
  `docs/ai/METRICS.jsonl` entry.
- AC-002: The never-fabricate rule holds: no code path computes or
  estimates a token value when the runtime did not expose one; a
  runtime-usage-absent run still records null exactly as before.
- AC-003: `metrics-flush.mjs`'s "cost unattributable — tokens not recorded"
  warning does not fire for a flushed work item whose runs all captured
  real usage; existing behavior (warning fires) is unchanged for runs
  without captured usage.
- AC-004: No existing `state.mjs`/`metrics-flush.mjs` test regresses;
  relevant suites (`tests/skills/test-aai-state.sh`,
  `tests/skills/test-aai-metrics*.sh` or equivalent) stay green.

## Verification
- Targeted re-run of `tests/skills/test-aai-state.sh` and the metrics/flush
  suite -> exit 0, including new fixtures for AC-001/AC-002.
- Live probe: run a role/subagent through the loop and confirm the resulting
  METRICS.jsonl `agent_runs[]` entry carries non-null token fields (dated
  after this change), contrasted with the null pattern observed in the
  2026-07-16/17 baseline.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0.

## Constraints / Risks
- Different harnesses/runtimes may expose usage under different field names
  or not at all — the capture code must degrade to "omit the flag" per
  runtime, never guess a shape that doesn't exist (Constitution art. 4).
- Risk of double-counting or mismatched attribution if a single tick spans
  multiple subagent calls — scope the capture to the granularity the
  existing `log-tick`/`append-run` calls already use (one call per role
  run/tick), not finer.
- No schema change to METRICS.jsonl/STATE.yaml is anticipated; if the
  runtime's usage shape requires a NEW field (e.g. cache-write tokens), that
  is a follow-up, not blocking this change.

## Notes
- Evidence: `.aai/scripts/metrics-flush.mjs:356` (warning text and
  condition); `.aai/scripts/state.mjs:706-707,797-800` (accepted-but-unfed
  `--tokens-in`/`--tokens-out` flags, warn-on-null print);
  `docs/ai/METRICS.jsonl` — every sampled 2026-07-16/2026-07-17 entry has
  null tokens/cost across Implementation, Validation, Code Review, and TDD
  Implementation roles.
- Filed as part of the same 2026-07-17 intake batch responding to EEX
  downstream operator feedback and independent in-repo confirmation.
