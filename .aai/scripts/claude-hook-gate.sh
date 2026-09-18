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
#       genuine gate verdict, never for adapter errors. ONE deliberate
#       exception (B2, validation-round1): the `merge` gate's PR-number
#       resolution failing is itself a verdict ("cannot check a sweep record
#       for a PR I cannot identify"), not an adapter error, so it denies too.
#
# HONESTY NOTE: this is a guardrail against habit, not a security boundary —
# an agent inside the session could unset the hook or set the env marker.
# Doing so without the operator's explicit direction violates constitution
# article 7; the hook makes the violation deliberate instead of accidental.
#
# Payload contract (Claude Code 2.x hooks): stdin JSON with the invoked Bash
# command at .tool_input.command; $CLAUDE_PROJECT_DIR points at the project
# root (fallback: cwd). See docs/specs/SPEC-0029-spec-hook-enforced-gates.md D6
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
    if [ "${AAI_OPERATOR_MERGE:-}" != "1" ]; then
      {
        echo "Merge denied: constitution article 7 (operator-only merge) — the agent never merges;"
        echo "the PR ceremony ends at 'gh pr create' (.aai/SKILL_PR.prompt.md step 6)."
        echo "If the OPERATOR explicitly directed this merge, run it with AAI_OPERATOR_MERGE=1."
        echo "(Guardrail, not a security boundary — setting the marker without operator direction"
        echo "is a constitution violation.)"
      } >&2
      exit 2
    fi
    # Mirror gate 2b (Spec-AC-34, GitHub issue 338): a `gh pr merge <N>`
    # additionally needs a recorded, consistent post-open review sweep
    # (CHANGE-0060 step 5d). CALLS lane-gate.mjs --sweep-check — never
    # reimplements its predicate (this file's own header rule). Scoped to an
    # ACTUAL `gh pr merge` invocation only (MERGE_SEG below) — a plain
    # `git merge` matched the outer `merge` case's regex too (article 7 is
    # unconditional for both) but names no PR and has no sweep record to
    # check; it must keep falling through to exit 0 once article 7 clears.
    #
    # B2 (validation-round1): the PR number is NOT always positional right
    # after `merge` -- `gh pr merge --squash 385`, `gh pr merge --squash
    # --delete-branch 385`, and the numberless `gh pr merge --squash`
    # .aai/SKILL_PR.prompt.md:488 itself tells the role to run all parsed as
    # "no PR number" under the old regex, which fell through to exit 0
    # (ALLOW) — treating "couldn't parse it" as an adapter error let every one
    # of those forms bypass the gate this section exists for. Take the number
    # from ANY positional (non-flag) argument in the merge command segment
    # (skipping a `-R`/`--repo` value, the one flag that legitimately carries
    # a slash-form target rather than the PR itself); when none is found,
    # resolve it the same way `gh pr merge` itself would — from the current
    # branch via `gh pr view`. UNLIKE every other adapter-trouble path in this
    # file, failing to resolve a PR number for an actual `gh pr merge` is NOT
    # allowed to fall through to exit 0: an unidentified PR means this gate
    # cannot judge anything, and "cannot judge" must never read as "nothing
    # to enforce".
    MERGE_SEG="$(printf '%s' "$CMD" | grep -oE 'gh[[:space:]]+pr[[:space:]]+merge([[:space:]][^;&|]*)?' | head -1)"
    if [ -n "$MERGE_SEG" ]; then
      PR_SEARCH="$(printf '%s' "$MERGE_SEG" | sed -E 's/(^|[[:space:]])(-R|--repo)[[:space:]]+[^[:space:]]+//g')"
      PR="$(printf '%s' "$PR_SEARCH" | grep -oE '(^|[[:space:]])[0-9]+([[:space:]]|$)' | grep -oE '[0-9]+' | head -1)"
      if [ -z "$PR" ] && command -v gh >/dev/null 2>&1; then
        PR="$(cd "$ROOT" 2>/dev/null && gh pr view --json number -q .number 2>/dev/null || true)"
        printf '%s' "$PR" | grep -Eq '^[0-9]+$' || PR=""
      fi
      if [ -z "$PR" ]; then
        {
          echo "Merge denied: could not determine which PR this merge command targets."
          echo "Command: $CMD"
          echo "No positional PR number, and 'gh pr view --json number' (current branch) did"
          echo "not resolve one either (Spec-AC-34, issue 338) -- this gate refuses to guess"
          echo "rather than allow a merge it cannot check a sweep record for."
          echo "Run 'gh pr merge <N> ...' naming the PR explicitly, or merge from a branch"
          echo "with exactly one open PR."
        } >&2
        exit 2
      fi
      if command -v node >/dev/null 2>&1 && [ -f "$ROOT/.aai/scripts/lane-gate.mjs" ]; then
        SWEEP_ARGS=(--sweep-check --pr "$PR" --repo-root "$ROOT")
        [ -n "${AAI_SWEEP_SPEC:-}" ] && SWEEP_ARGS+=(--spec "$AAI_SWEEP_SPEC")
        [ -n "${AAI_SWEEP_INTAKE:-}" ] && SWEEP_ARGS+=(--intake "$AAI_SWEEP_INTAKE")
        [ -n "${AAI_SWEEP_STATE:-}" ] && SWEEP_ARGS+=(--state "$AAI_SWEEP_STATE")
        [ -n "${AAI_SWEEP_BASE_REF:-}" ] && SWEEP_ARGS+=(--base-ref "$AAI_SWEEP_BASE_REF")
        SWEEP_OUT="$(cd "$ROOT" 2>/dev/null && node "$ROOT/.aai/scripts/lane-gate.mjs" "${SWEEP_ARGS[@]}" 2>&1)"
        SWEEP_RC=$?
        if [ "$SWEEP_RC" -eq 5 ]; then
          {
            echo "Merge denied: no valid post-open review sweep record for PR $PR (Spec-AC-34, issue 338)."
            printf '%s\n' "$SWEEP_OUT" | tail -5
            echo "Record one with .aai/scripts/append-event.mjs --event pr_sweep ..., then retry."
          } >&2
          exit 2
        fi
        # rc 0 (verified) or anything else (adapter trouble, e.g. no node/script) -> allow.
      fi
    fi
    exit 0
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
