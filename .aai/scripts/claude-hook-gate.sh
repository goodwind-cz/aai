#!/usr/bin/env bash
# claude-hook-gate.sh — thin Claude Code hook adapter (RFC-0010 /
# spec-hook-enforced-gates). Bridges Claude Code PreToolUse/Stop hook payloads
# (JSON on stdin) to EXISTING AAI gates. It contains ZERO gate logic of its
# own: what blocks is decided by the script it invokes
# (.aai/scripts/pre-commit-checks.sh) or by rules already ratified elsewhere
# (docs/CONSTITUTION.md article 7 operator-only merge; article 6 single-writer
# STATE via .aai/scripts/state.mjs). Never reimplement a predicate here —
# hook/script drift is the RFC-0010 risk this file exists to prevent.
#
# Usage: claude-hook-gate.sh <gate>
#   commit      PreToolUse Bash(git commit*)            -> run pre-commit-checks.sh
#   merge       PreToolUse Bash(git merge*|gh pr merge*) -> deny unless AAI_OPERATOR_MERGE=1
#   state-dump  PreToolUse Bash(yaml.dump/safe_dump writes touching STATE.yaml)
#                                                        -> deny, point to state.mjs
#   stop-nudge  Stop event                               -> wrap-up reminder, NEVER blocks
#
# Exit codes (Claude Code hook contract):
#   0 — allow. Includes EVERY internal failure: missing node, unreadable or
#       malformed stdin, unknown gate, missing target script. FAIL-OPEN BY
#       DESIGN (RFC-0010: a broken hook must not brick the session; every
#       mirrored gate still runs at its original call site, so a skipped
#       mirror loses nothing).
#   2 — block; stderr is shown to the model as the reason. Emitted ONLY for a
#       genuine gate verdict, never for adapter errors.
#
# HONESTY NOTE: this is a guardrail against habit, not a security boundary —
# an agent inside the session could unset the hook or set the env marker.
# Doing so without the operator's explicit direction violates constitution
# article 7; the hook makes the violation deliberate instead of accidental.
#
# Payload contract (Claude Code 2.x hooks): stdin JSON with the invoked Bash
# command at .tool_input.command; $CLAUDE_PROJECT_DIR points at the project
# root (fallback: cwd). See docs/specs/SPEC-DRAFT-hook-enforced-gates.md D6
# for the assumption ledger.

set -u  # deliberately NOT -e: unexpected failures must fall through to exit 0

GATE="${1:-}"
ROOT="${CLAUDE_PROJECT_DIR:-.}"

# Read the hook payload; extract the Bash command text (empty on any failure).
PAYLOAD="$(cat 2>/dev/null || true)"
CMD=""
if command -v node >/dev/null 2>&1; then
  CMD="$(printf '%s' "$PAYLOAD" | node -e '
    let d = "";
    process.stdin.on("data", (c) => { d += c; });
    process.stdin.on("end", () => {
      try {
        const j = JSON.parse(d);
        process.stdout.write(String((j.tool_input && j.tool_input.command) || ""));
      } catch (e) { /* fail-open: emit nothing */ }
    });' 2>/dev/null || true)"
fi

case "$GATE" in

  commit)
    # Mirror gate 1: the existing pre-commit quality gate, made unskippable.
    [ -n "$CMD" ] || exit 0
    printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-;&|[:space:]][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)' || exit 0
    CHECKS="$ROOT/.aai/scripts/pre-commit-checks.sh"
    [ -f "$CHECKS" ] || exit 0
    OUT="$(cd "$ROOT" 2>/dev/null && bash "$CHECKS" 2>&1)" && exit 0
    {
      echo "AAI pre-commit gate blocked this commit (.aai/scripts/pre-commit-checks.sh exited non-zero):"
      printf '%s\n' "$OUT" | tail -25
      echo "Fix the reported errors, then retry the commit. (Hook mirrors the existing gate; RFC-0010.)"
    } >&2
    exit 2
    ;;

  merge)
    # Mirror gate 2: constitution article 7 — operator-only merge (strict).
    [ -n "$CMD" ] || exit 0
    printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-;&|[:space:]][^[:space:]]*)?)*[[:space:]]+merge([[:space:]]|$)|(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)' || exit 0
    [ "${AAI_OPERATOR_MERGE:-}" = "1" ] && exit 0
    {
      echo "Merge denied: constitution article 7 (operator-only merge) — the agent never merges;"
      echo "the PR ceremony ends at 'gh pr create' (.aai/SKILL_PR.prompt.md step 6)."
      echo "If the OPERATOR explicitly directed this merge, run it with AAI_OPERATOR_MERGE=1."
      echo "(Guardrail, not a security boundary — setting the marker without operator direction"
      echo "is a constitution violation.)"
    } >&2
    exit 2
    ;;

  state-dump)
    # Mirror gate 3: constitution article 6 — single-writer STATE. Whole-file
    # YAML serialization destroys the commented schema header (the SPEC-0019
    # manual-flush lesson); .aai/scripts/state.mjs is the only STATE writer.
    [ -n "$CMD" ] || exit 0
    printf '%s' "$CMD" | grep -Eq 'yaml\.dump|safe_dump|dump_all' || exit 0
    printf '%s' "$CMD" | grep -q 'STATE\.yaml' || exit 0
    {
      echo "STATE write denied: docs/ai/STATE.yaml has exactly ONE writer — the transactional CLI"
      echo "node .aai/scripts/state.mjs (constitution article 6). Whole-file YAML serialization"
      echo "(yaml.dump/safe_dump) destroys the commented schema header and reorders keys"
      echo "(SPEC-0019 manual-flush lesson). Use the state.mjs subcommands instead."
    } >&2
    exit 2
    ;;

  stop-nudge)
    # Gate 4: wrap-up discipline reminder. NEVER blocks — no exit-2 path in
    # this branch by construction. Nudges when a work item is in_progress and
    # no tick was logged after the last STATE change (LOOP_TICKS.jsonl absent
    # or older than STATE.yaml — a deliberate, documented mtime heuristic).
    STATE="$ROOT/docs/ai/STATE.yaml"
    [ -f "$STATE" ] || exit 0
    grep -Eq '^[[:space:]]+status:[[:space:]]*in_progress' "$STATE" 2>/dev/null || exit 0
    TICKS="$ROOT/docs/ai/LOOP_TICKS.jsonl"
    if [ -f "$TICKS" ] && [ "$TICKS" -nt "$STATE" ]; then
      exit 0
    fi
    echo "AAI wrap-up nudge: docs/ai/STATE.yaml still has an in_progress work item and no loop tick was logged after the last state change. Consider /aai-wrap-up (capture learnings, close the item) or log the tick via node .aai/scripts/state.mjs log-tick. (Reminder only — never blocks.)"
    exit 0
    ;;

  *)
    # Unknown gate: fail-open.
    exit 0
    ;;
esac

exit 0
