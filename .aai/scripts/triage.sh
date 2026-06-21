#!/usr/bin/env bash
# AAI L1 Triage — read-only health snapshot. Writes nothing; safe to schedule.
#
# Surfaces docs drift, runtime-state presence, and working-tree cleanliness so an
# operator (or an L1 scheduled run) sees problems BEFORE launching a full,
# write-capable loop. This is the cheapest rung of autonomy: read and report only.
#
# Usage:
#   ./.aai/scripts/triage.sh           # print report, always exit 0
#   ./.aai/scripts/triage.sh --check   # exit 1 if anything needs triage (CI gate)
#
# Schedule it (example): a cron / `/schedule` routine running this with --check
# turns it into a daily L1 drift alarm without ever touching the repo.
set -euo pipefail

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

STATE="docs/ai/STATE.yaml"
TICKS="docs/ai/LOOP_TICKS.jsonl"
issues=0

echo "## AAI L1 Triage — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

# 1) Runtime state presence
if [ -f "$STATE" ] && grep -q '^project_status:' "$STATE" 2>/dev/null; then
  ps="$(grep '^project_status:' "$STATE" | head -1 | awk '{print $2}')"
  echo "- State: present (project_status=${ps:-unknown})"
else
  # Benign before the first run — the orchestrator auto-creates state. Informational only.
  echo "- State: not present yet ($STATE) — orchestrator will init, or run /aai-check-state"
fi

# 2) Working tree
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  n="$(git status --porcelain | wc -l | tr -d ' ')"
  echo "- Working tree: $n uncommitted change(s)"
else
  echo "- Working tree: clean"
fi

# 3) Last recorded tick
if [ -f "$TICKS" ] && [ -s "$TICKS" ]; then
  echo "- Last tick: $(tail -1 "$TICKS")"
else
  echo "- Last tick: none recorded"
fi

# 4) Docs audit (quick is read-only: --quick skips the EVENTS append)
echo
if command -v node >/dev/null 2>&1 && [ -f .aai/scripts/docs-audit.mjs ]; then
  audit="$(node .aai/scripts/docs-audit.mjs --quick 2>/dev/null || true)"
  echo "$audit" | grep -E '^- (Mode|Scanned|Tracked):|^### Verdict:' || echo "- Docs audit: (no output)"
  if echo "$audit" | grep -q 'NEEDS-TRIAGE'; then issues=$((issues + 1)); fi
else
  echo "- Docs audit: skipped (node or docs-audit.mjs unavailable)"
fi

echo
if [ "$issues" -eq 0 ]; then
  echo "### Triage verdict: CLEAN"
else
  echo "### Triage verdict: NEEDS-ATTENTION ($issues area(s))"
  [ "$CHECK" -eq 1 ] && exit 1
fi
exit 0
