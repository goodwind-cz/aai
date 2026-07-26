# Shared role METRICS / append-run block (prompt-dedup-canonical-includes)

Applies to every role prompt that records `agent_runs` metrics at the end of
its run: `.aai/PLANNING.prompt.md`, `.aai/IMPLEMENTATION.prompt.md`,
`.aai/VALIDATION.prompt.md`, `.aai/REMEDIATION.prompt.md`, and
`.aai/SKILL_TDD.prompt.md`. Each references this file with a pointer line
naming its own `--role` value; apply the block below exactly as written,
substituting `<ThisRole>` with that role's declared value (quote it when it
contains a space, e.g. `"TDD Implementation"`).

## METRICS (record in docs/ai/STATE.yaml)
Subagent-mode carve-out (D5): dispatched as a subagent -> do NOT self-append; return the result block — the orchestrator appends with harness usage per SUBAGENT_PROTOCOL.md; direct execution -> self-append below, usage omitted.
Capture `started_utc` from the system clock (`date -u +%Y-%m-%dT%H:%M:%SZ`)
immediately before this role's first step begins.
PRIMARY PATH — after completing, append your agent run via the transactional CLI:
  node .aai/scripts/state.mjs append-run --ref <REF-ID> --role <ThisRole> \
    --model <your model identifier> --started <started_utc> \
    [--note "<summary>"] [--tokens-in N --tokens-out N]
The CLI self-stamps `ended_utc` and computes `duration_seconds` from the system
clock, keeps `cost_usd: null`, and auto-initializes a missing
metrics.work_items entry — never a second top-level `metrics:` key.
FALLBACK — if .aai/scripts/state.mjs is absent: read .aai/STATE_FALLBACK.md and
follow it (agent_runs hand-append + write-safety rules).
Do NOT estimate any timing or token values. Only record measured/platform values.
