---
id: live-status-dashboard
type: product
capability: live-status-dashboard
status: current
delivered_by:
  - CHANGE-0127
spec: docs/specs/SPEC-DRAFT-spec-live-status-dashboard.md
updated: 2026-08-08
---

# Live status dashboard

## What it does

Answers what the existing three generators (dashboard, factory-report,
overview) cannot: **what is running NOW**, **what it has cost TODAY**, and
**how much official plan-quota headroom is left** — with zero LLM tokens,
zero network calls, node stdlib only. It reads harness session transcripts
(Claude Code, Codex, Gemini CLI) through a per-harness parser registry and
renders one self-contained page, `docs/ai/live-status.html`, plus its
machine-readable twin `docs/ai/live-status-data.json`. It is strictly
OPTIONAL: nothing in the ride path (close-work-item, the autonomous loop, CI)
ever invokes it, and it is never coupled to ride ceremony.

## How to use it

- One-shot: `node .aai/scripts/generate-live-status.mjs` writes both output
  files and exits 0, even when every harness directory is absent (each
  absence named in a `degraded` array — never fatal, never fabricated).
- Watch mode: `node .aai/scripts/generate-live-status.mjs --watch --interval
  30` regenerates on an interval; the page's own `<meta http-equiv="refresh">`
  matches the interval, so one open browser tab stays current. `Ctrl+C` exits
  cleanly (exit 0, no leftover child process). No server, no port.
- Convenience launcher: `bash .aai/scripts/aai-live.sh [--watch]` (Windows:
  `aai-live.ps1`) generates and opens the page via the platform opener
  (`open` / `xdg-open` / `Start-Process`); it refuses with a named error
  instead of hanging when no opener is found.
- `--data-only` writes just `live-status-data.json`. `--home <dir>` overrides
  the resolved home directory (fixtures/tests only).

## Data model

- Inputs (read-only): harness session transcripts discovered via
  `os.homedir()` (or the harness's own env override — `CLAUDE_CONFIG_DIR`,
  `CODEX_HOME`, `GEMINI_HOME`) — `~/.claude/projects/**/*.jsonl`,
  `~/.codex/sessions/**/*.jsonl`, `~/.gemini/tmp/*/logs.json`; plus two
  OPTIONAL local spools (see Install below).
- Outputs: `docs/ai/live-status.html` (self-contained, inline CSS) +
  `live-status-data.json` (field-for-field the same model). Both are runtime
  sidecars — unlike factory-report/dashboard/overview they are never
  regenerated-and-committed at close, so they are gitignored and never
  tracked (Spec-AC-11).
- Incremental cache: `.aai/cache/live-status-index.json` (already
  gitignored) keyed on `path -> {mtimeMs, size, records}` — a session file
  whose mtime and size are unchanged is never re-read.

## Interfaces and contracts

- **Parser registry** (`.aai/scripts/live-parsers/registry.mjs`): one module
  per harness (`claude-code.mjs`, `codex.mjs`, `gemini-cli.mjs`), each
  declaring `id`, `roots(env)`, `discover(roots)`, `parse(file, ctx)`, an
  `accumulation` mode, and `project(record)`. Adding a harness means adding
  one module + one registry row — nothing else changes.
  `registerParsers()` refuses a malformed entry with a named error rather
  than silently producing partial totals.
- **Accumulation modes** (the honesty-critical core): `event_sum_dedup`
  (Claude Code — sums usage, skipping any repeated `message.id`+`requestId`
  so a duplicated on-disk line never inflates spend);
  `session_cumulative_last` (Codex — per session, the LAST `token_count`
  event's cumulative total; summing every event would multiply real spend by
  the event count); `none` (Gemini CLI — no usage field exists in the
  format, so usage renders the literal text `N/A`, never a fabricated zero).
- **Official quotas**: the quotas section renders `five_hour`/`seven_day`
  used-percentage + `resets_at` from the statusline-tap spool when present;
  else from a harness's own in-session server-authoritative rate limits
  (Codex) when present; else a named `SKIP` with an install hint — never an
  estimated limit.
- **Liveness**: a session's state badge reads `finished` or
  `waiting-on-approval` when the hooks spool carries a `Stop`/`Notification`
  line for it; otherwise it falls back to an mtime-window heuristic and the
  rendered state carries the literal word `heuristic`.
- **Install** (both opt-in, both OFF by default): merge
  `.aai/templates/hooks/live-status-hooks.json` into `.claude/settings.json`
  (wires the Claude Code `statusLine` and the `Stop`/`Notification` hooks to
  `.aai/scripts/live-spool.sh`, which whitelists fields and appends to
  `docs/ai/live/{statusline,hooks}.jsonl`; it always exits 0 so a spool
  failure never disturbs the harness, and it spools only `session_id`,
  `cwd`, `model`, `rate_limits`, `cost` (statusline) or `hook_event_name`
  (hooks) — never message or transcript content).
- **Uninstall**: remove the `statusLine` key and the `Stop`/`Notification`
  hook entries from `.claude/settings.json` (or delete `docs/ai/live/` to
  reset the spools without a full uninstall). Absence of either spool leaves
  the dashboard on its tested, honest fallback paths (quotas `SKIP`,
  liveness `heuristic`) — never a broken one.
- Cross-platform: every root and spool path is built through `os.homedir()`
  or an env override joined with `path.join` — no hardcoded POSIX string.
  `live-spool.sh`/`aai-live.sh` ship PowerShell twins
  (`live-spool.ps1`/`aai-live.ps1`).

## Limits and non-goals

- The statusline stdin payload shape is documented by each harness, not by
  this repo, and the real payload was not observed live at spec time — if
  the real field names differ from the documented shape, the quotas section
  degrades to its tested `SKIP` path rather than lying.
- No config-drift detection, no LLM-generated suggestions, no OAuth
  usage-API polling — those are explicitly out of scope (see the change
  request's non-goals).
- Real Windows execution is not exercised by this repo's CI; the `.ps1`
  twins get parse-level and PSScriptAnalyzer coverage plus path-construction
  assertions.

## Links

- Request: docs/issues/CHANGE-0127-live-status-dashboard.md
- Spec: docs/specs/SPEC-DRAFT-spec-live-status-dashboard.md
- Analysis: docs/analysis/blume-and-alternatives.md
