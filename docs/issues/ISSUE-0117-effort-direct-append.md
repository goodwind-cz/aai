---
id: effort-direct-append
type: issue
number: 117
status: done
capability: telemetry
links:
  pr: []
  commits: []
---

# Directly executed role runs record no effort, so the effort report cannot tell them from old history

## Summary
Follow-up `fu-effort-direct-append-telemetry` (P2, source PR #552 Codex P2 on
`.aai/SKILL_LOOP.prompt.md`, filed by `model-effort-routing`). Per-role effort
routing (CHANGE-0256 / SPEC-0288) records `--requested-effort` and
`--effort-applied` only on the append-run the loop writes for a subagent
dispatch. A role executed directly (the loop's no-subagent fallback, or a role
prompt run by hand) self-appends with the canonical command in
`.aai/ROLE_COMMON.md`, which carries neither flag. Those runs land in
`docs/ai/METRICS.jsonl` with no effort fields and show as `unset` in
`metrics-report --by-effort`, exactly like runs recorded before the feature
existed. The owner is waiting on the effort-gain measurement
(`fu-effort-gain-remeasure`, baseline split 2026-11-13); mixing these runs into
the history row skews it.

A second skew in the same report: `--by-effort` groups by role and requested
effort only, so a run whose effort was really passed to the harness
(`effort_applied: param`) and a run where it was not (`not_supported`) share
one row. On the ledger at origin/main 16773cdf, from 2026-11-13: 42 `param`
runs, 29 `not_supported` runs with a requested level, 3 `not_supported` runs
without one, 5 runs with no effort fields.

## Type
bug

## Impact
- Every project that vendors the layer and reads `metrics-report --by-effort`.
- Severity: P2. Telemetry only; no gate reads the fields, but the owner's
  effort decision rests on this report.

## Current Behavior
- `.aai/ROLE_COMMON.md` METRICS block: the direct-execution append-run line has
  no effort flags, so the run carries no `requested_effort` and no
  `effort_applied`.
- `state.mjs append-run --effort-applied` accepts only `param`,
  `not_supported`, `overridden`; there is no value for "the role ran in the
  orchestrating session, no per-dispatch knob was used".
- `metrics-report --by-effort` prints `unset` for any run without
  `requested_effort` and does not show `effort_applied` at all.

## Expected Behavior
- Every run recorded after this fix states whether its effort was applied: a
  directly executed role records `--effort-applied direct` plus
  `--requested-effort <the dispatch's suggested_effort>` when the dispatch
  named one.
- `metrics-report --by-effort` separates runs by how effort was applied, so a
  direct or not-supported run never shares a row with history that recorded
  nothing.
- Runs recorded before the feature (no effort fields) still read `unset`.
  Nothing rewrites the ledger.

## Steps to Reproduce (if applicable)
1) Run a role prompt directly (no subagent) and follow `.aai/ROLE_COMMON.md`
   METRICS: `state.mjs append-run --ref <ref> --role Remediation --model ... --started ... --verdict none`.
2) Flush and run `node .aai/scripts/metrics-report.mjs --by-effort`.
3) Actual: the run is in the `Remediation | unset` row with pre-feature history.

## Verification
- New cases in `tests/skills/test-aai-model-effort.sh`, red before the fix:
  append-run accepts `--effort-applied direct` and writes it; flush carries
  it; `--by-effort` prints direct, not_supported, param and history (unset)
  runs in separate rows; a ledger with no effort fields still reads `unset`.
- A pin that the ROLE_COMMON direct-append line carries the effort flags.
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-model-effort.sh` passes.

## Constraints / Risks
- `.aai/scripts/state.mjs` is a protected L3 surface.
- A `.aai` prompt or ROLE_COMMON edit triggers prompt-corpus governance
  (diet-ledger entry, TEST-012 bump, PROFILES classification).
- The by-effort table shape is pinned byte-for-byte by TEST-3640; changing it
  is a disclosed change to SPEC-0288 D-REPORT.
- Do not touch `metrics-flush.mjs` unless needed: a parallel ride edits it.
  The flush already copies any `effort_applied` string.
- Secrets preflight results: no secret referenced.

## Notes
- Implementation mode (autopilot recommendation): tdd. Telemetry writer and
  report change on a protected script.
- Metrics question skipped by autopilot default: human_time_minutes null.
