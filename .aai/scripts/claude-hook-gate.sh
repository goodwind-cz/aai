#!/usr/bin/env bash
# claude-hook-gate.sh — thin Claude Code hook launcher (RFC-0010 /
# spec-hook-enforced-gates). Bridges Claude Code PreToolUse/Stop hook payloads
# (JSON on stdin) to the gate decisions in .aai/scripts/hook-gate.mjs, which
# mirror EXISTING gates and never reimplement one: .aai/scripts/pre-commit-checks.sh
# (commit), docs/CONSTITUTION.md article 7 plus .aai/scripts/merge-policy.mjs
# and lane-gate.mjs (merge), article 6 / .aai/scripts/state.mjs (state-dump).
#
# Usage: claude-hook-gate.sh <gate>
#   commit      PreToolUse Bash(git commit*)             -> run pre-commit-checks.sh
#   merge       PreToolUse Bash(git merge*, gh pr merge*, the Azure merge forms)
#                                                         -> deny unless AAI_OPERATOR_MERGE=1,
#               or a merge-policy lane marker is set and merge-policy.mjs allows it
#   state-dump  PreToolUse Bash(yaml.dump/safe_dump writes touching STATE.yaml)
#                                                         -> deny, point to state.mjs
#   stop-nudge  Stop event                               -> wrap-up reminder, NEVER blocks
#
# Exit codes (Claude Code hook contract): 0 allow, 2 block (stderr is shown to
# the model). Every internal failure -- node or the module missing, unreadable
# stdin, an unknown gate -- exits 0: FAIL-OPEN BY DESIGN (RFC-0010: a broken hook
# must not brick the session; every mirrored gate still runs at its original
# call site). ONE exception: with a merge-policy lane marker set in the
# environment, a merge-shaped payload that cannot be decided (no node, no
# module) is denied -- the lane path may only ever add an allow.
#
# HONESTY NOTE: a guardrail against habit, not a security boundary.
#
# Payload contract (Claude Code 2.x hooks): stdin JSON with the invoked Bash
# command at .tool_input.command; $CLAUDE_PROJECT_DIR points at the project root.

set -u  # deliberately NOT -e / pipefail: unexpected failures must fall through to exit 0

GATE="${1:-}"
ROOT="${CLAUDE_PROJECT_DIR:-.}"
case "${BASH_SOURCE[0]}" in
  */*) HERE="${BASH_SOURCE[0]%/*}" ;;
  *) HERE="." ;;
esac
PAYLOAD="$(cat 2>/dev/null || true)"

# Pre-filter, no process started: a payload that cannot concern its gate exits 0
# here. The triggers are substrings of the raw payload; a backslash-u escape
# (the JSON-escaped command, DG-05) always continues, `completed` is matched in
# any letter case (az takes `--status Completed`), and stop-nudge needs a STATE.
case "$GATE:$PAYLOAD" in
  *\\u*) ;;
  commit:*commit*) ;;
  merge:*merge*) ;;
  merge:*[Cc][Oo][Mm][Pp][Ll][Ee][Tt][Ee][Dd]*) ;;
  state-dump:*dump*) ;;
  stop-nudge:*) [ -f "$ROOT/docs/ai/STATE.yaml" ] || exit 0 ;;
  *) exit 0 ;;
esac

# The no-node lane guard: a lane marker (AAI_*_MERGE=1, never AAI_OPERATOR_MERGE)
# in the environment plus a merge-shaped payload is denied when the decision
# cannot be made.
lane_guard() {
  local n
  [ "$GATE" = merge ] || return 0
  case "$PAYLOAD" in *merge*) ;; *) return 0 ;; esac
  for n in $(compgen -e 2>/dev/null); do
    [[ $n =~ ^AAI_[A-Z0-9_]+_MERGE$ ]] || continue
    [ "$n" != "AAI_OPERATOR_MERGE" ] || continue
    [ "${!n:-}" = "1" ] || continue
    {
      echo "Merge denied: constitution article 7 (operator-only merge) — the agent never merges;"
      echo "the PR ceremony ends at 'gh pr create' (.aai/SKILL_PR.prompt.md step 6)."
      echo "If the OPERATOR explicitly directed this merge, run it with AAI_OPERATOR_MERGE=1."
      echo "(Guardrail, not a security boundary — setting the marker without operator direction"
      echo "is a constitution violation.)"
      echo "merge-policy: evaluator unavailable: node not found (the command could not be read)"
    } >&2
    exit 2
  done
  return 0
}

if ! command -v node >/dev/null 2>&1 || [ ! -f "$HERE/hook-gate.mjs" ]; then
  lane_guard
  exit 0
fi
node "$HERE/hook-gate.mjs" "$GATE" <<<"$PAYLOAD"
rc=$?
[ "$rc" -eq 2 ] && exit 2
exit 0
