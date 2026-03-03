#!/usr/bin/env bash
set -euo pipefail

# Migrate legacy AAI YAML runtime files to JSONL format.
#
# Run this in the target project root BEFORE aai-sync so the JSONL files
# are populated and the sync script will preserve them.
#
# Usage:
#   ./scripts/migrate-yaml-to-jsonl.sh [path-to-target-project]
#   (defaults to current directory)
#
# Requires: python3 + PyYAML  (pip install pyyaml)
#
# What it does:
#   docs/ai/LOOP_TICKS.yaml  (events list)  -> appended to  docs/ai/LOOP_TICKS.jsonl
#   docs/ai/METRICS.yaml     (entries list)  -> appended to  docs/ai/METRICS.jsonl
#
# Significance filter (keeps only meaningful entries):
#   - explicit significant=true
#   - errors/warnings/exceptions
#   - result not in noop/no_change/skipped/none/ok/success
#   - any change-ish fields (changes/diff/files_changed/summary/notes/decision/action)
#   - numeric value/delta/count != 0

TARGET="$(cd "${1:-$(pwd)}" && pwd)"
echo "Target project: $TARGET"

if [[ ! -d "$TARGET/docs/ai" ]]; then
  echo "ERROR: $TARGET/docs/ai not found. Is this an AAI project?"
  exit 1
fi

if ! python3 -c "import yaml" 2>/dev/null; then
  echo "ERROR: python3 + PyYAML required.  Run: pip install pyyaml"
  exit 1
fi

migrate() {
  local src="$1" dst="$2" key="$3"

  if [[ ! -f "$src" ]]; then
    echo "  SKIP (not found):  $(basename "$src")"
    return
  fi

  # Ensure destination JSONL exists (may be a new stub from sync or not yet created)
  touch "$dst"

  local n
  n=$(python3 - "$src" "$dst" "$key" <<'PYEOF'
import yaml, json, sys

def _truthy(v):
    if v is None:
        return False
    if isinstance(v, (list, dict, str)):
        return len(v) > 0
    return bool(v)

def _significant(item):
    if not isinstance(item, dict):
        return True

    if item.get("significant") is True:
        return True

    for k in ("error", "errors", "warning", "warnings", "exception", "traceback"):
        if _truthy(item.get(k)):
            return True

    result = str(item.get("result", "")).strip().lower()
    if result and result not in ("noop", "no_change", "skipped", "none", "ok", "success"):
        return True

    for k in (
        "changes", "change", "diff", "patch", "files_changed", "file_changes",
        "updated_files", "applied", "writes", "writes_count", "edits",
        "summary", "notes", "decision", "action", "step", "event",
    ):
        if _truthy(item.get(k)):
            return True

    for k in ("value", "delta", "count", "errors", "warnings"):
        v = item.get(k)
        if isinstance(v, (int, float)) and v != 0:
            return True

    return False

src, dst, key = sys.argv[1], sys.argv[2], sys.argv[3]

with open(src, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}

items = data.get(key) or []
total = len(items)
items = [i for i in items if _significant(i)]
kept = len(items)

if items:
    with open(dst, "a", encoding="utf-8") as out:
        for item in items:
            out.write(json.dumps(item, separators=(",", ":"), ensure_ascii=False) + "\n")

print(f"{kept} {total}")
PYEOF
)

  kept="${n%% *}"
  total="${n##* }"
  filtered="$((total - kept))"

  if [[ "$total" -eq 0 ]]; then
    echo "  SKIP (empty):      $(basename "$src") has no '$key' entries"
  elif [[ "$kept" -gt 0 ]]; then
    echo "  MIGRATED: $kept of $total entries (filtered $filtered)  $(basename "$src") -> $(basename "$dst")"
  else
    echo "  SKIP (no significant): $(basename "$src") filtered $filtered of $total"
  fi
}

migrate "$TARGET/docs/ai/LOOP_TICKS.yaml" "$TARGET/docs/ai/LOOP_TICKS.jsonl" "events"
migrate "$TARGET/docs/ai/METRICS.yaml"    "$TARGET/docs/ai/METRICS.jsonl"    "entries"

echo "Done. Review: git -C \"$TARGET\" diff docs/ai/"
