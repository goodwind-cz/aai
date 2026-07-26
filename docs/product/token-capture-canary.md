---
id: token-capture-canary
type: product
status: current
spec: docs/specs/SPEC-0085-spec-token-capture-canary.md
updated: 2026-07-26
---

# Telemetry capture canary (loud gaps in token/duration capture)

## What it does

The factory's telemetry used to fail silently: a run that observed real token
usage but never recorded it looked identical to a run where the runtime
exposed nothing, and a loop tick logged with a bogus start time quietly wrote
`duration_seconds: 0`. This feature makes every capture gap loud. The metrics
flush now tells you which runs honestly could not be costed versus which runs
dropped an observable number, and the tick logger warns the moment a caller
passes a log-time timestamp or omits the harness version.

## How to use it

Nothing to configure — the diagnostics are on by default and never block:

- Run a flush (`/aai-flush` or the loop's close pipeline) and read its
  output: `INFO` lines mark runs with an undecomposed harness total
  (cost unattributable by design), `WARNING` lines mark capture-missing runs
  (no numeric tokens AND no usage note — the defect class to chase).
- `node .aai/scripts/state.mjs log-tick ...` prints a stderr `WARNING` when
  the computed duration is 0 (start time equals log time) or when
  `--harness` is omitted. Exit codes are unchanged.
- When merging a subagent result, recording
  `--note "usage_total_tokens=<N> (harness total; in/out not exposed)"` is
  now mandatory whenever the harness reported a total.

## Data model

No schema change. Existing fields only: `agent_runs[].note` carries the
canonical `usage_total_tokens=<N>` grammar; METRICS.jsonl and
LOOP_TICKS.jsonl shapes are byte-compatible with prior records.

## Interfaces and contracts

- `metrics-flush.mjs`: three-way per-run classification
  (`decomposed` | `undecomposed-note` | `capture-missing`) surfaced as
  INFO/WARNING diagnostics; flush exit code unchanged (warn, never block).
- `state.mjs log-tick`: stderr WARNING on duration-0 and missing
  `--harness`; the tick line is still appended, exit 0.
- `SUBAGENT_PROTOCOL.md` merge protocol: the usage note is REQUIRED when a
  harness total is visible; splitting a total into in/out remains forbidden.
- L3 self-check tests: touching a protected path now passes the suite iff a
  frozen `ceremony_level: 3` spec ships in the same diff (previously any
  touch failed forever).

## Limits and non-goals

- No token estimation or in/out splitting — runs on runtimes that expose
  nothing stay null (honest-null), by design.
- The log-tick WARNING has no automated downstream consumer (human/CI
  signal); only the producing side is machine-verified.
- The reaper test suite's load-dependent flake is untouched and out of scope.

## Links

- Request: docs/issues/CHANGE-0058-token-capture-canary.md
- Spec: docs/specs/SPEC-0085-spec-token-capture-canary.md
- Validation evidence: docs/ai/reports/validation-token-capture-canary-20260726T131158Z.md
  (local runtime artifact, not committed; summarized with suite counts in PR #158)
