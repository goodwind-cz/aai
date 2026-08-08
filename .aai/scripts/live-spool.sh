#!/usr/bin/env bash
#
# live-spool.sh — statusline/hook tap writer (SPEC-DRAFT-spec-live-status-dashboard).
#
# Reads ONE JSON payload on stdin, projects a WHITELIST of fields, appends
# one line to docs/ai/live/<kind>.jsonl (kind = statusline|hooks, first
# positional arg, default statusline), caps the file by line count, and
# ALWAYS exits 0 — a statusline or hook writer must never disturb the
# harness it is tapping. The repo root is resolved from THIS SCRIPT's own
# location, so the caller's cwd is irrelevant. AAI_LIVE_SPOOL_DIR overrides
# the spool directory (fixtures, tests).
#
# Usage (wired by .aai/templates/hooks/live-status-hooks.json, opt-in only):
#   echo "$STATUSLINE_JSON" | bash live-spool.sh statusline
#   echo "$HOOK_JSON"       | bash live-spool.sh hooks

set -uo pipefail   # deliberately NOT -e: this script must always reach exit 0

KIND="${1:-statusline}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPOOL_DIR="${AAI_LIVE_SPOOL_DIR:-$REPO_ROOT/docs/ai/live}"
MAX_LINES=500

PAYLOAD="$(cat 2>/dev/null || true)"

if [[ -n "$PAYLOAD" ]]; then
  mkdir -p "$SPOOL_DIR" 2>/dev/null || true
  FILE="$SPOOL_DIR/$KIND.jsonl"

  PROJECTED="$(printf '%s' "$PAYLOAD" | node -e '
    const fs = require("fs");
    let raw = "";
    try { raw = fs.readFileSync(0, "utf8"); } catch { raw = ""; }
    let obj = null;
    try { obj = JSON.parse(raw); } catch { obj = null; }
    if (obj && typeof obj === "object" && !Array.isArray(obj)) {
      const kind = process.argv[1];
      const common = ["session_id", "cwd", "model"];
      const statuslineFields = ["rate_limits", "cost"];
      const hookFields = ["hook_event_name"];
      const allow = common.concat(kind === "hooks" ? hookFields : statuslineFields);
      const out = { ts: new Date().toISOString() };
      for (const k of allow) if (k in obj) out[k] = obj[k];
      process.stdout.write(JSON.stringify(out) + "\n");
    }
  ' "$KIND" 2>/dev/null || true)"

  if [[ -n "$PROJECTED" ]]; then
    # $(...) strips the trailing newline the node one-liner wrote — re-add it
    # explicitly, or consecutive spools concatenate onto one JSONL line.
    printf '%s\n' "$PROJECTED" >> "$FILE" 2>/dev/null || true
    LINES="$(wc -l < "$FILE" 2>/dev/null || echo 0)"
    if [[ "$LINES" -gt "$MAX_LINES" ]]; then
      tail -n "$MAX_LINES" "$FILE" > "$FILE.tmp" 2>/dev/null && mv "$FILE.tmp" "$FILE" 2>/dev/null || true
    fi
  fi
fi

if [[ "$KIND" == "statusline" ]]; then
  # Minimal stdout passthrough so a statusLine command never renders blank
  # (product doc documents composing with an existing statusline via tee).
  echo "(aai-live tap active)"
fi

exit 0
