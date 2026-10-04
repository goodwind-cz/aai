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
#   merge       PreToolUse Bash(git merge*|gh pr merge*) -> deny unless AAI_OPERATOR_MERGE=1,
#               or a lane marker is set and .aai/scripts/merge-policy.mjs
#               allows that marker's lane (the evaluator decides; see P9
#               of spec-configurable-merge-policy-lanes)
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
#       exception (B2, validation-round1; ordering fixed by
#       fu-hookgate-capability-before-deny): the `merge` gate's PR-number
#       resolution failing is itself a verdict ("cannot check a sweep record
#       for a PR I cannot identify"), not an adapter error, so it denies too
#       -- but ONLY when the tooling to look was actually present (`gh` on
#       PATH to resolve a branch-implicit PR; `node` + lane-gate.mjs to check
#       a record). When that tooling itself is absent there is nothing to
#       resolve or check, which is an ordinary capability-absent case and
#       falls open like every other one.
#       A SECOND deliberate exception: once a merge-policy lane marker is
#       set, every lane-path failure (missing node or evaluator, evaluator
#       error, unparseable command) denies -- the lane path may only ever
#       add an allow, never turn an error into one.
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

# ---------------------------------------------------------------------------
# Merge gate helpers (used only by the `merge)` case below).
# ---------------------------------------------------------------------------

# merge_target_pr — the ONE PR-resolution routine of the merge gate (gate 2b,
# Spec-AC-34, issue 338), shared by gate 2b and the merge-policy lane path so
# both judge the same PR. Reads $MERGE_SEG, $CMD and $ROOT; prints the PR
# number (or nothing when it is capability-absent-unresolvable). Called as
# `PR="$(merge_target_pr)"`: a genuinely-unresolvable target prints its deny
# text on stderr and `exit 2`s the command-substitution subshell, which the
# caller turns into its own deny.
merge_target_pr() {
  # Strip a value-taking flag's value WHOLE, including a quoted phrase
  # carrying embedded spaces (`--subject "fix 123"`) -- the single
  # bare-token pattern alone (third -e below) only ever consumed up to
  # the first space inside the quotes, leaving a stray `123"` behind
  # that then read as a (wrong) positional target. Quoted forms first
  # (double, then single), bare token last, so an already-stripped
  # quoted value is never re-matched by the bare-token pass.
  PR_SEARCH="$(printf '%s' "$MERGE_SEG" | sed -E \
    -e 's/(^|[[:space:]])(-R|--repo|-b|--body|-F|--body-file|-t|--subject|--match-head-commit)[[:space:]]+"[^"]*"//g' \
    -e "s/(^|[[:space:]])(-R|--repo|-b|--body|-F|--body-file|-t|--subject|--match-head-commit)[[:space:]]+'[^']*'//g" \
    -e 's/(^|[[:space:]])(-R|--repo|-b|--body|-F|--body-file|-t|--subject|--match-head-commit)[[:space:]]+[^[:space:]]+//g')"
  # NB-2 (validation-round2): a quoted bare number (`gh pr merge "385"`)
  # is not a bare token under the digit scan below, so it fell through to
  # branch resolution and was judged against a DIFFERENT PR's record.
  # Strip quotes ONLY around a token that is nothing but digits -- never a
  # quoted PHRASE that happens to contain one (`--subject "fix 123"` is
  # already gone whole, above; this rule still protects any OTHER quoted
  # phrase — validation-round1 B2's own control, still armed).
  PR_SEARCH="$(printf '%s' "$PR_SEARCH" | sed -E "s/\"([0-9]+)\"/ \1 /g; s/'([0-9]+)'/ \1 /g")"
  # Drop the "gh pr merge" prefix, then every remaining boolean flag
  # (-A/--auto, --admin, -d/--delete-branch, --disable-auto, -m/--merge,
  # -r/--rebase, -s/--squash, or any future one), leaving only bare
  # positional tokens. The first one, if any, is the target.
  TARGET_SEARCH="$(printf '%s' "$PR_SEARCH" | sed -E 's/^[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge//')"
  TARGET_SEARCH="$(printf '%s' "$TARGET_SEARCH" | sed -E 's/(^|[[:space:]])-[A-Za-z0-9-]+//g')"
  TARGET="$(printf '%s' "$TARGET_SEARCH" | tr -s '[:space:]' '\n' | grep -v '^$' | head -1)"
  PR=""
  if printf '%s' "$TARGET" | grep -Eq '^[0-9]+$'; then
    PR="$TARGET"
  elif [ -n "$TARGET" ]; then
    # A non-numeric target (<url> | <branch>) needs `gh pr view <target>`
    # to resolve — same capability-before-deny split as the bare-command
    # case below: no `gh` at all means nothing can resolve it (fall
    # through, allow); `gh` present but unable to name a PR for THIS
    # target means the tool looked and genuinely could not (deny).
    if command -v gh >/dev/null 2>&1; then
      PR="$(cd "$ROOT" 2>/dev/null && gh pr view "$TARGET" --json number -q .number 2>/dev/null || true)"
      printf '%s' "$PR" | grep -Eq '^[0-9]+$' || PR=""
      if [ -z "$PR" ]; then
        {
          echo "Merge denied: could not resolve a PR for target \"$TARGET\"."
          echo "Command: $CMD"
          echo "'gh pr view $TARGET --json number' did not resolve one (Spec-AC-34, issue"
          echo "338) -- this gate refuses to guess rather than allow a merge it cannot check"
          echo "a sweep record for."
        } >&2
        exit 2
      fi
    fi
  fi
  if [ -z "$PR" ] && [ -z "$TARGET" ] && command -v gh >/dev/null 2>&1; then
    PR="$(cd "$ROOT" 2>/dev/null && gh pr view --json number -q .number 2>/dev/null || true)"
    printf '%s' "$PR" | grep -Eq '^[0-9]+$' || PR=""
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
  fi
  printf '%s' "$PR"
}

# merge_deny_article7 — constitution article 7's deny text (bytes unchanged
# since before the lane path existed; spec-configurable-merge-policy-lanes
# Spec-AC-02 pins them against the base-commit adapter). The lane path adds
# exactly one `merge-policy: <verdict>` line; with no lane marker
# LANE_VERDICT is empty and nothing is added.
merge_deny_article7() {
  echo "Merge denied: constitution article 7 (operator-only merge) — the agent never merges;"
  echo "the PR ceremony ends at 'gh pr create' (.aai/SKILL_PR.prompt.md step 6)."
  echo "If the OPERATOR explicitly directed this merge, run it with AAI_OPERATOR_MERGE=1."
  echo "(Guardrail, not a security boundary — setting the marker without operator direction"
  echo "is a constitution violation.)"
  [ -z "${LANE_VERDICT:-}" ] || echo "merge-policy: $LANE_VERDICT"
}

# --- Merge-policy lane path (spec-configurable-merge-policy-lanes P9) -------
# A lane marker is a variable named ^AAI_[A-Z0-9_]+_MERGE$ (never
# AAI_OPERATOR_MERGE) with the value 1, set in this hook's environment or as
# a leading NAME=1 assignment of the `gh pr merge` command segment. Without
# one, none of the code below changes what the gate does. With one, the lane
# path can only ever ADD an allow: every refusal, error or missing tool ends
# in today's article-7 deny plus one `merge-policy:` line. The decision is
# .aai/scripts/merge-policy.mjs's (`--check`); this file only parses the
# command and compares the allowed lane's marker with the markers set.
LANE_NL='
'
LANE_MARKER_ERE='^AAI_[A-Z0-9_]+_MERGE$'
LANE_ASSIGNS_ERE='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*$'
LANE_SOLE_MERGE_ERE='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)'
LANE_ALLOWED_ERE='^MERGE-POLICY allowed pr=([0-9]+) lane=[^[:space:]]+ marker=([A-Z0-9_]+) '
# --match-head-commit's value, gh's own flag for refusing to merge a head
# other than the one named (used here to pin the lane path to the exact PR
# head this invocation resolves below, NB-1).
LANE_MATCH_HEAD_ERE='--match-head-commit[[:space:]]+([0-9a-fA-F]+)'

# R2-B1 (validation-round2): a deny-list keyed on flag spelling
# (LANE_BAD_FLAG_ERE/LANE_REPO_FLAG_ERE, dropped here) is bypassed by
# quoting a flag ('--admin') and by gh's own pflag parser, which accepts
# `--admin=<bool>`/`--auto=<bool>` as real flags -- the regex never saw
# those spellings as --auto/--admin at all. lane_check_merge_shape (below)
# replaces both with an ALLOW-LIST over the merge segment's own tokens: the
# only shapes a lane merge may ever take are a bare PR number, one of
# --squash/--merge/--rebase, an optional --delete-branch, and exactly one
# --match-head-commit <value> -- every other token, including any
# --flag=value spelling, refuses closed.

# Marker names set to 1 in the environment. compgen -e lists exported NAMES
# only, so a value carrying an embedded "AAI_X_MERGE=1" line cannot forge one.
lane_env_markers() {
  local n
  for n in $(compgen -e 2>/dev/null); do
    [[ $n =~ $LANE_MARKER_ERE ]] || continue
    [ "$n" != "AAI_OPERATOR_MERGE" ] || continue
    [ "${!n:-}" = "1" ] && printf '%s\n' "$n"
  done
  return 0
}

# The text between the last command separator before the FIRST
# `gh pr merge` and that `gh` (empty output + rc 1 when there is none).
lane_merge_prefix() {
  local re="(^|[;&|(${LANE_NL}])([^;&|(${LANE_NL}]*)gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|\$)"
  [[ $CMD =~ $re ]] || return 1
  printf '%s' "${BASH_REMATCH[2]}"
}

# Marker names given as leading NAME=1 assignments of the merge segment. A
# prefix that is not purely NAME=VALUE words (`echo "AAI_X_MERGE=1 ...`) is
# not an assignment and yields nothing.
lane_prefix_markers() {
  local pre w words
  pre="$(lane_merge_prefix)" || return 0
  [[ $pre =~ $LANE_ASSIGNS_ERE ]] || return 0
  read -r -a words <<< "$pre"
  for w in ${words[@]+"${words[@]}"}; do
    [ "${w%%=*}" != "AAI_OPERATOR_MERGE" ] || continue
    [ "${w#*=}" = "1" ] || continue
    [[ ${w%%=*} =~ $LANE_MARKER_ERE ]] && printf '%s\n' "${w%%=*}"
  done
  return 0
}

# lane_check_merge_shape — R2-B1: an ALLOW-LIST over the `gh pr merge`
# segment's own tokens (reads/writes $MERGE_SEG and $LANE_VERDICT; returns
# 1 and sets LANE_VERDICT on any refusal, 0 when every token is recognized).
# A quote character or a backslash anywhere in the segment refuses outright
# -- gh never sees them (the invoking shell strips them before gh's argv),
# so a quoted '--admin' or "--auto" reads here as the LITERAL bytes
# '--admin'/"--auto", which match no allowed token below and would refuse
# anyway, but the explicit check is the documented contract, not an
# accident of what the token loop happens to reject. Every token after
# `gh pr merge` must be exactly one of: a bare PR number (digits only, at
# most once), one of --squash/--merge/--rebase (at most once),
# --delete-branch (at most once), or --match-head-commit followed by a
# non-empty hex value (at most once) -- gh's own --flag=value spelling
# (e.g. --admin=true, --auto=1, a second --match-head-commit=...) is
# refused by the leading `*=*` case before any flag name is even compared,
# so no future addition to this list can be bypassed the same way. Whether
# --match-head-commit is present at all, and whether its value equals the
# PR head this invocation resolves, stays lane_path's own job (step 6b
# below already requires it and checks the value against that resolved
# head byte for byte); this function only validates the SHAPE of what is
# here -- a short or mismatched value still reaches step 6b and is denied
# there, by equality, not by this function guessing a length.
lane_check_merge_shape() {
  case "$MERGE_SEG" in
    *\'*)
      LANE_VERDICT="lane path refused: a quote character is not permitted on the merge-policy lane"
      return 1 ;;
    *\"*)
      LANE_VERDICT="lane path refused: a quote character is not permitted on the merge-policy lane"
      return 1 ;;
    *\\*)
      LANE_VERDICT="lane path refused: a backslash is not permitted on the merge-policy lane"
      return 1 ;;
  esac
  local rest tokens tok have_pr have_mode have_delete have_match idx
  rest="$(printf '%s' "$MERGE_SEG" | sed -E 's/^[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge//')"
  read -r -a tokens <<< "$rest"
  have_pr=0; have_mode=0; have_delete=0; have_match=0
  idx=0
  while [ "$idx" -lt "${#tokens[@]}" ]; do
    tok="${tokens[$idx]}"
    idx=$((idx + 1))
    case "$tok" in
      *=*)
        LANE_VERDICT="lane path refused: $tok is not permitted on the merge-policy lane"
        return 1 ;;
      --match-head-commit)
        if [ "$have_match" -ne 0 ]; then
          LANE_VERDICT="lane path refused: --match-head-commit is not permitted more than once on the merge-policy lane"
          return 1
        fi
        tok="${tokens[$idx]:-}"
        idx=$((idx + 1))
        if [ -z "$tok" ] || [[ $tok == *[!0-9a-fA-F]* ]]; then
          LANE_VERDICT="lane path refused: --match-head-commit requires a hex commit value"
          return 1
        fi
        have_match=1 ;;
      --squash|--merge|--rebase)
        if [ "$have_mode" -ne 0 ]; then
          LANE_VERDICT="lane path refused: $tok is not permitted on the merge-policy lane"
          return 1
        fi
        have_mode=1 ;;
      --delete-branch)
        if [ "$have_delete" -ne 0 ]; then
          LANE_VERDICT="lane path refused: --delete-branch is not permitted more than once on the merge-policy lane"
          return 1
        fi
        have_delete=1 ;;
      *[!0-9]*|'')
        LANE_VERDICT="lane path refused: ${tok:-<empty>} is not permitted on the merge-policy lane"
        return 1 ;;
      *)
        if [ "$have_pr" -ne 0 ]; then
          LANE_VERDICT="lane path refused: $tok is not permitted on the merge-policy lane"
          return 1
        fi
        have_pr=1 ;;
    esac
  done
  # P9 step 1: "one bare PR number" -- the branch-implicit form (no number,
  # relying on merge_target_pr's branch fallback) used to be accepted here,
  # letting the lane merge whatever PR the fallback resolves from $ROOT's
  # branch even though gh itself runs in the payload cwd, which may be a
  # linked worktree on a different branch (validation-round3 NB-1).
  if [ "$have_pr" -eq 0 ]; then
    LANE_VERDICT="lane path refused: a PR number is required on the merge-policy lane"
    return 1
  fi
  return 0
}

# lane_path — sets LANE_ALLOWED=1, or LANE_VERDICT to the reason it did not.
lane_path() {
  local pre w words pcwd root_git cwd_git mp_out mp_rc mp_line want_marker
  # 1. The command must be ONE simple `gh pr merge`: no separator, pipe,
  #    substitution, redirection or newline, so the PR the evaluator judges
  #    is the only thing the command can merge.
  case "$CMD" in
    *"$LANE_NL"*|*[\;\&\|\`\$\(\)\<\>\\]*)
      LANE_VERDICT="lane path refused: the command must be a single gh pr merge, with no chaining, substitution or redirection"
      return ;;
  esac
  if ! [[ $CMD =~ $LANE_SOLE_MERGE_ERE ]]; then
    LANE_VERDICT="lane path refused: lane markers cover gh pr merge only"
    return
  fi
  # 1b/3. R2-B1: an allow-list over the merge segment's own tokens (--auto,
  #    --admin, -R/--repo, a URL target, --flag=value, quoting -- anything
  #    not on the fixed token set lane_check_merge_shape recognizes) replaces
  #    the two deny-list regexes this used to be (LANE_BAD_FLAG_ERE,
  #    LANE_REPO_FLAG_ERE) -- a deny-list keyed on flag spelling is bypassed
  #    by exactly those two tricks (validation-round2).
  lane_check_merge_shape || return
  # 2. Every leading assignment must itself be a lane marker set to 1
  #    (GH_REPO=... or any other prefix could retarget what merges).
  pre="$(lane_merge_prefix)" || pre=""
  read -r -a words <<< "$pre"
  for w in ${words[@]+"${words[@]}"}; do
    if ! [[ ${w%%=*} =~ $LANE_MARKER_ERE ]] || [ "${w%%=*}" = "AAI_OPERATOR_MERGE" ] || [ "${w#*=}" != "1" ]; then
      LANE_VERDICT="lane path refused: leading assignment ${w%%=*} is not a lane marker"
      return
    fi
  done
  # 4. Tooling. Missing node, evaluator or gh is today's deny, never an
  #    allow (gh is also needed below, step 6b, to resolve the exact head).
  if ! command -v node >/dev/null 2>&1; then
    LANE_VERDICT="evaluator unavailable: node not found"
    return
  fi
  if [ ! -f "$ROOT/.aai/scripts/merge-policy.mjs" ]; then
    LANE_VERDICT="evaluator unavailable: .aai/scripts/merge-policy.mjs not found"
    return
  fi
  if ! command -v gh >/dev/null 2>&1; then
    LANE_VERDICT="evaluator unavailable: gh not found"
    return
  fi
  # 5. The Bash command runs in the payload's cwd; it must be the same
  #    repository (same git common dir, so linked worktrees qualify) as the
  #    project the evaluator judges.
  pcwd="$(printf '%s' "$PAYLOAD" | node -e '
    let d = "";
    process.stdin.on("data", (c) => { d += c; });
    process.stdin.on("end", () => {
      try { const j = JSON.parse(d); process.stdout.write(String(j.cwd || "")); } catch (e) { /* none */ }
    });' 2>/dev/null || true)"
  root_git="$(cd "$ROOT" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)" || root_git=""
  cwd_git=""
  if [ -n "$pcwd" ]; then
    cwd_git="$(cd "$pcwd" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)" || cwd_git=""
  fi
  if [ -z "$root_git" ] || [ "$root_git" != "$cwd_git" ]; then
    LANE_VERDICT="lane path refused: the command's cwd (${pcwd:-unknown}) is not this project's repository"
    return
  fi
  # 6. The PR, resolved exactly as gate 2b resolves it.
  LANE_PR="$(merge_target_pr 2>/dev/null)" || LANE_PR=""
  if ! [[ $LANE_PR =~ ^[0-9]+$ ]]; then
    LANE_VERDICT="lane path refused: could not resolve the PR this command merges"
    return
  fi
  # 6b. NB-1: the lane path may only ever merge the EXACT head this
  #     invocation is about to verify. Resolved independently via gh (the
  #     same call merge-policy.mjs's own getPrJson makes), so a stale or
  #     absent --match-head-commit is caught before the evaluator even runs.
  LANE_HEAD="$(cd "$ROOT" 2>/dev/null && gh pr view "$LANE_PR" --json headRefOid -q .headRefOid 2>/dev/null)"
  if ! [[ $LANE_HEAD =~ ^[0-9a-fA-F]+$ ]]; then
    LANE_VERDICT="lane path refused: could not resolve the head commit of PR $LANE_PR"
    return
  fi
  if [[ $MERGE_SEG =~ $LANE_MATCH_HEAD_ERE ]]; then
    if [ "${BASH_REMATCH[1]}" != "$LANE_HEAD" ]; then
      LANE_VERDICT="lane path refused: --match-head-commit ${BASH_REMATCH[1]} does not match PR $LANE_PR's head ($LANE_HEAD)"
      return
    fi
  else
    LANE_VERDICT="lane path refused: the merge-policy lane requires --match-head-commit $LANE_HEAD"
    return
  fi
  # 7. The evaluator decides; the allowed lane's OWN marker must be set.
  MP_EXTRA=()
  [ -n "${AAI_SWEEP_SPEC:-}" ] && MP_EXTRA+=(--spec "$AAI_SWEEP_SPEC")
  [ -n "${AAI_SWEEP_INTAKE:-}" ] && MP_EXTRA+=(--intake "$AAI_SWEEP_INTAKE")
  [ -n "${AAI_SWEEP_STATE:-}" ] && MP_EXTRA+=(--state "$AAI_SWEEP_STATE")
  mp_out="$(cd "$ROOT" 2>/dev/null && node "$ROOT/.aai/scripts/merge-policy.mjs" --check --pr "$LANE_PR" --repo-root "$ROOT" ${MP_EXTRA[@]+"${MP_EXTRA[@]}"} 2>/dev/null)"
  mp_rc=$?
  mp_line="${mp_out%%"$LANE_NL"*}"
  if [ "$mp_rc" -eq 0 ] && [[ $mp_line =~ $LANE_ALLOWED_ERE ]] \
     && [ "${BASH_REMATCH[1]}" = "$LANE_PR" ]; then
    want_marker="${BASH_REMATCH[2]}"
    case "$LANE_NL$LANE_MARKERS$LANE_NL" in
      *"$LANE_NL$want_marker$LANE_NL"*) LANE_ALLOWED=1; return ;;
    esac
    LANE_VERDICT="$mp_line (lane marker $want_marker is not set)"
    return
  fi
  LANE_VERDICT="${mp_line:-evaluator gave no verdict} (exit $mp_rc)"
}

# Without node the payload cannot be parsed at all (CMD is empty and every
# gate falls open). When a lane marker is set in the environment that
# fail-open would be the lane path turning an error into an allow, so a
# merge-shaped payload is denied instead. No marker: nothing changes.
lane_nonode_guard() {
  command -v node >/dev/null 2>&1 && return 0
  [ -n "$(lane_env_markers)" ] || return 0
  case "$PAYLOAD" in *merge*) ;; *) return 0 ;; esac
  LANE_VERDICT="evaluator unavailable: node not found (the command could not be read)"
  merge_deny_article7 >&2
  exit 2
}

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
    # Mirror gate 2: constitution article 7 — operator-only merge (strict),
    # with the one sanctioned exception: a merge-policy lane (spec-
    # configurable-merge-policy-lanes P9; helpers above). No lane marker =
    # exactly the gate as it was (Spec-AC-02 pins the bytes).
    [ -n "$CMD" ] || { lane_nonode_guard; exit 0; }
    printf '%s' "$CMD" | grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-;&|[:space:]][^[:space:]]*)?)*[[:space:]]+merge([[:space:]]|$)|(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)' || exit 0
    # The `gh pr merge` segment, if any (gate 2b below and the lane path).
    MERGE_SEG="$(printf '%s' "$CMD" | grep -oE 'gh[[:space:]]+pr[[:space:]]+merge([[:space:]][^;&|]*)?' | head -1)"
    LANE_ALLOWED=""
    LANE_VERDICT=""
    LANE_MARKERS=""
    if [ "${AAI_OPERATOR_MERGE:-}" != "1" ]; then
      LANE_MARKERS="$(lane_env_markers; lane_prefix_markers)"
      [ -z "$LANE_MARKERS" ] || lane_path
    fi
    if [ "${AAI_OPERATOR_MERGE:-}" != "1" ] && [ "$LANE_ALLOWED" != "1" ]; then
      merge_deny_article7 >&2
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
    # branch via `gh pr view`.
    #
    # fu-hookgate-capability-before-deny (code review round 1/2 of
    # close-ceremony-sweep): the capability tests (is `gh` on PATH to resolve
    # a branch-implicit PR; is `node` + lane-gate.mjs present to check a
    # record at all) MUST run before any attempt to treat "couldn't resolve"
    # as a verdict. Without them first, a machine that never had the tooling
    # to check anything (no gh, or no node/.aai layer) reads identically to
    # "checked, and it's unresolvable/missing" and gets denied for a check it
    # could never have run — exactly the fail-open contract this file's
    # header promises for every OTHER adapter-trouble path. Denying is
    # reserved for when the tooling to look IS present and what it finds is
    # genuinely absent or contradictory:
    #   - no positional target AND no `gh` on PATH: nothing can resolve
    #     the PR at all -- capability absent -> fall through, allow.
    #   - no positional target, `gh` present, but `gh pr view` itself
    #     can't name one (no PR on this branch, network/auth failure, ...):
    #     the tool to look existed and looked -- genuinely unresolvable ->
    #     deny (UNLIKE every other adapter-trouble path in this file: an
    #     unidentified PR means this gate cannot judge anything, and "cannot
    #     judge" must never read as "nothing to enforce").
    #   - a PR number is known (positional or resolved) but `node` or
    #     lane-gate.mjs is missing: nothing can check a sweep record at all
    #     -- capability absent -> fall through, allow.
    #   - a PR number is known AND node+lane-gate.mjs are present AND the
    #     sweep-check itself denies (rc 5): a genuine verdict -> deny.
    #
    # P1 (Codex, PR #385 bot review, Amendment 27): `gh pr merge --help`
    # documents THREE positional target forms — [<number> | <url> | <branch>]
    # — but this parser recognised only a bare digit token; a URL or a branch
    # name (`gh pr merge feature-branch`, or a PR URL) fell through to the
    # SAME "no positional target" path as a genuinely bare `gh pr merge`, and
    # was judged against whatever PR `gh pr view` (no arg) resolves for the
    # CURRENT branch instead — a different PR than the one actually named on
    # the command line. Fixed: after stripping every value-taking flag (now
    # -R/--repo, -b/--body, -F/--body-file, -t/--subject,
    # --match-head-commit — gh's full value-flag set for this subcommand, not
    # just -R/--repo) and every remaining boolean flag, the first surviving
    # bare token is the TARGET, in whichever of the three forms it takes.
    if [ -n "$MERGE_SEG" ]; then
      # PR resolution: merge_target_pr (above), shared with the lane path.
      PR="$(merge_target_pr)" || exit 2
      # PR is still empty here only when there was no resolvable positional
      # target AND no `gh` on PATH to try resolving one -- capability absent,
      # not a verdict; fall through to the unconditional exit 0 below.
      if [ -n "$PR" ]; then
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
          # rc 0 (verified) or anything else (adapter trouble, e.g. no script) -> allow.
        fi
        # capability absent (no node / no lane-gate.mjs): nothing to check -> allow.
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
