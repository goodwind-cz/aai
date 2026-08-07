---
id: live-status-dashboard
number: 127
type: change
status: draft
user_visible: true
ceremony_level: 1
---

# Change — Optional zero-token live-status dashboard (factory sidecar)

## Summary
- Owner ask (2026-08-07): "ten dashboard co nebude úplně moc vyžírat tokeny
  by se asi hodil, jako optional" — after reviewing Blume Sidecar
  (blume.codes). Full analysis: docs/analysis/blume-and-alternatives.md.
- Deliver a live operational view the existing three generators lack
  (dashboard = per-ride telemetry, factory-report = time-series efficiency,
  overview = what shipped): what is running NOW, what it costs TODAY, and
  official plan-quota headroom — with ZERO LLM tokens, zero network,
  node stdlib only (docs/TECHNOLOGY.md contract), opt-in, never coupled to
  ride ceremony.
- UNIVERSAL across harnesses (owner requirement 2026-08-07): a per-harness
  parser registry normalizing every agent's on-disk session format into one
  model (sessions, activity, token usage) — Blume's proven architecture
  (parser.<agent>-canonical) and ccusage precedent (~15 harnesses). Adding
  an agent = adding one parser module, nothing else changes.
- Mechanisms (proven by the OSS landscape, see analysis §3):
  session-JSONL parsing (ccusage-style dedup on message.id+requestId over
  `~/.claude/projects/**/*.jsonl`, incremental via mtime cutoff — corpus is
  ~484 MB), statusline-tap spool for server-authoritative
  rate_limits.five_hour/seven_day percentages (no hardcoded limit guesses),
  optional hooks spool (Stop/Notification) for
  running/waiting-on-approval/finished liveness. Local ground truth for the
  first parsers exists on the owner's machine: `~/.codex/sessions/<year>/…`
  + `~/.codex/session_index.jsonl` + `~/.codex/history.jsonl`, and
  `~/.gemini/tmp/<project>/logs.json`.
- Explicit non-goals: Blume's config-drift pillar (docs-audit + diet ledger
  + TEST pins already cover it deterministically in CI); any LLM-generated
  suggestions; OAuth usage-API polling (undocumented, network); PTY
  wrapping; OTel stack.

## Acceptance Criteria
- AC-001: New `.aai/scripts/generate-live-status.mjs` emits
  `docs/ai/live-status.html` + `live-status-data.json` via a per-harness
  parser registry (each parser: discover session files, yield normalized
  {session, project, timestamps, model, tokens} records): active sessions
  (mtime-window detection, per-project), token spend today/7d per
  project/model/harness with per-harness dedup keys (Claude Code:
  message.id+requestId); node stdlib only, zero network, exits 0 on
  absent/partial data (missing harness dirs named as ABSENT per harness,
  never fatal); outputs are runtime sidecars (RUNTIME_IGNORE class, never
  committed).
- AC-005: Registry ships with parsers for Claude Code
  (`~/.claude/projects/**/*.jsonl` + CLAUDE_CONFIG_DIR) and Codex
  (`~/.codex/sessions/**` with session_index.jsonl), plus Gemini CLI
  best-effort (`~/.gemini/tmp/*/logs.json`) — a harness whose format yields
  no usage fields renders sessions/liveness only, with the usage column
  honestly marked N/A (never fabricated); parser contract documented so
  adding a harness touches exactly one module + one registry row + tests.
- AC-002: Statusline tap: a tiny installer-provided script appends the
  statusline stdin JSON to a local spool; when the spool exists the report
  renders official five_hour/seven_day used % + resets_at; when absent the
  section degrades to a named SKIP (no estimates, no fabricated limits).
- AC-003: Liveness (optional hooks spool): Stop/Notification hook lines give
  running/waiting/finished per session; absent spool degrades to
  mtime-only heuristic labeled as heuristic.
- AC-004: Opt-in only: no ride/ceremony/CI coupling; documented in
  USER_GUIDE (install + uninstall of tap/hooks); tests cover parser dedup,
  incremental cutoff, degradation paths (RED-first per suite conventions).
