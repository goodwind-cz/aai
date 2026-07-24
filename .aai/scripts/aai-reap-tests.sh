#!/bin/sh
#
# aai-reap-tests.sh — workspace + etime scoped reaper for leaked test processes
# (SPEC-0009 / ISSUE-0002 fix #3). Defence-in-depth sweep the loop runs AFTER a
# test-running tick to kill hung `vitest`/`esbuild` trees that escaped the
# wrapper.
#
# SAFETY INVARIANT (load-bearing): this reaper is NEVER global. It kills ONLY
# processes whose command line matches `vitest`/`esbuild` AND contains the
# current workspace path, AND that are OLDER than the step-start age threshold.
# It never runs a bare `pkill -f vitest`. Two guards must both hold:
#   - WORKSPACE scope: the process command line must contain the workspace path
#     (AAI_REAP_WORKSPACE, default $PWD). A matching process in a DIFFERENT
#     workspace (a sibling checkout) is left alone.
#   - AGE guard (Guard 3): under concurrent subagents, a matching process that
#     is part of THIS step's own in-flight work is NEVER killed. Only trees
#     that predate the step are reaped. Two modes (deterministic epoch mode
#     preferred; fixed-threshold legacy mode is the fail-safe fallback):
#       - EPOCH MODE (AAI_REAP_STEP_START_EPOCH set + valid): capture
#         SNAP_NOW=$(date +%s) at the SAME instant as the `ps` snapshot; per
#         process compute start_epoch = SNAP_NOW - etime_secs; REAP iff
#         start_epoch < AAI_REAP_STEP_START_EPOCH - AAI_REAP_GRACE_SECS, else
#         SPARE. Reaper overhead/host load inflates SNAP_NOW and the sampled
#         etime by the SAME amount, so start_epoch (and the decision) is
#         invariant to it — this is what makes the guard deterministic instead
#         of a wall-clock race against a fixed constant.
#       - LEGACY MODE (AAI_REAP_STEP_START_EPOCH unset/invalid/future — the
#         SAFETY-CRITICAL fail-safe): reap iff etime_secs >= AAI_REAP_MIN_AGE_SECS,
#         exactly the pre-epoch behavior. NEVER "reap everything" on invalid
#         input — legacy mode is workspace+token scoped like every other mode.
#
# Usage:
#   .aai/scripts/aai-reap-tests.sh
#
# Environment:
#   AAI_REAP_WORKSPACE        workspace path to scope by (default $PWD)
#   AAI_REAP_MIN_AGE_SECS     LEGACY MODE minimum process age in seconds to be
#                             eligible (default 0; a younger matching process
#                             is spared). Used only when EPOCH MODE is not
#                             active (see AAI_REAP_STEP_START_EPOCH below).
#   AAI_REAP_STEP_START_EPOCH step-start Unix epoch seconds (e.g.
#                             `$(date +%s)` captured by the step owner —
#                             SKILL_LOOP / VALIDATION — before the test step
#                             launches). Activates EPOCH MODE when it is a
#                             valid positive integer <= the reaper's own
#                             `date +%s` at snapshot time; a process is reaped
#                             iff its computed start time is before
#                             (this value - AAI_REAP_GRACE_SECS). Unset, empty,
#                             non-integer, negative, zero, or a FUTURE value
#                             (clock skew) all fall back to LEGACY MODE —
#                             never a global kill. Additive: omitting it keeps
#                             today's LEGACY MODE behavior byte-for-byte.
#   AAI_REAP_GRACE_SECS       EPOCH MODE grace window in seconds absorbing
#                             `ps etime` whole-second truncation + snapshot
#                             sampling skew (default 2). A non-negative integer
#                             overrides it (for deterministic testing, not
#                             production tuning); anything else coerces to the
#                             default. Ignored in LEGACY MODE.
#
# Output: prints the number of reaped process trees ("reaped: N"). No-op (exit 0)
# when nothing matches.
#
# Platform matrix (Spec-AC-07 / SPEC-0046-spec-test-wrapper-windows-fallback;
# kept identical across this header, aai-run-tests.sh, aai-run-tests.ps1,
# aai-reap-tests.ps1, and docs/TECHNOLOGY.md):
#   macOS                              - full contract above (BSD ps etime + pid/ppid walk)
#   Linux                              - full contract above (GNU ps etime + pid/ppid walk)
#   Windows + WSL                      - full contract, via WSL delegation (aai-reap-tests.ps1)
#   Windows + Git-Bash-only (no WSL)   - this POSIX file is not the primary reap path on
#                                         native Windows; aai-reap-tests.ps1's native (Windows
#                                         process table) reap covers it — see that file
#   Windows, neither WSL nor Git Bash  - AAI-ENV-ERROR path lives in aai-run-tests.ps1; this
#                                         POSIX file is never reached in that configuration
#
# POSIX sh; works on macOS (BSD ps) + Linux (GNU ps).

set -u

WORKSPACE="${AAI_REAP_WORKSPACE:-$PWD}"
WORKSPACE="${WORKSPACE%/}"    # strip any trailing slash once (prevents double-slash in guard)
MIN_AGE="${AAI_REAP_MIN_AGE_SECS:-0}"
case "$MIN_AGE" in
  '' | *[!0-9]*) MIN_AGE=0 ;;
esac

# Strip leading zeros from a digit string so POSIX $(()) never treats a
# zero-padded value as octal (bash's 10# base-notation errors under dash —
# W1). Empty input -> "0".
strip_lz() {
  _v="$1"
  _v="${_v#"${_v%%[!0]*}"}"
  printf '%s' "${_v:-0}"
}

# Convert a ps ELAPSED/etime field to whole seconds. Handles the BSD/GNU forms:
#   SS            (rare)
#   MM:SS
#   HH:MM:SS
#   D-HH:MM:SS
etime_to_secs() {
  et="$1"
  days=0
  case "$et" in
    *-*)
      days="${et%%-*}"
      et="${et#*-}"
      ;;
  esac
  # Split the HH:MM:SS / MM:SS / SS portion on ':'.
  h=0
  m=0
  s=0
  case "$et" in
    *:*:*)
      h="${et%%:*}"
      rest="${et#*:}"
      m="${rest%%:*}"
      s="${rest#*:}"
      ;;
    *:*)
      m="${et%%:*}"
      s="${et#*:}"
      ;;
    *)
      s="$et"
      ;;
  esac
  # Strip leading zeros so POSIX $(()) never treats a zero-padded field as octal.
  # (bash's 10# base-notation errors under /bin/sh (dash) — W1.) Empty -> 0.
  days="${days:-0}"; days="${days#"${days%%[!0]*}"}"; days="${days:-0}"
  h="${h:-0}";       h="${h#"${h%%[!0]*}"}";          h="${h:-0}"
  m="${m:-0}";       m="${m#"${m%%[!0]*}"}";          m="${m:-0}"
  s="${s:-0}";       s="${s#"${s%%[!0]*}"}";          s="${s:-0}"
  echo $(((days * 86400) + (h * 3600) + (m * 60) + s))
}

# Print a matched pid followed by ALL its transitive descendants, computed with a
# portable PPID walk over a single `pid ppid` snapshot ($2). POSIX sh; no arrays,
# no recursion — a frontier queue with a dedup guard. Used so a leaked runner's
# child whose argv no longer carries the vitest/esbuild token (SPEC-0009 P2) is
# still reaped. Lineage keeps every descendant inside the SAME workspace as the
# matched (E1-guarded) root, so this widens completeness WITHOUT widening scope.
subtree_pids() {
  _root="$1"
  _snap="$2"
  _frontier="$_root"
  _out="$_root"
  while [ -n "$_frontier" ]; do
    _next=""
    for _p in $_frontier; do
      _kids="$(while read -r _cpid _cppid; do
        [ "$_cppid" = "$_p" ] && printf '%s\n' "$_cpid"
      done < "$_snap")"
      for _k in $_kids; do
        case " $_out " in *" $_k "*) continue ;; esac
        _out="$_out $_k"
        _next="$_next $_k"
      done
    done
    _frontier="$_next"
  done
  printf '%s' "$_out"
}

SNAP="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/aai-reap.$$.snap")"
# Snapshot processes: pid, etime, full args. `=` headers suppress the header row.
ps axo pid=,etime=,args= > "$SNAP" 2>/dev/null || {
  rm -f "$SNAP"
  echo "reaped: 0"
  # Additive diagnostic (SPEC test-018-legacy-spare-attribution / Spec-AC-01):
  # a stable, always-present companion line to `reaped: N` reporting the pid
  # list. Empty tail here (ps snapshot failed => nothing matched). Reporting
  # only — no decision surface.
  echo "reaped pids:"
  exit 0
}
# SNAP_NOW is captured IMMEDIATELY adjacent to the ps snapshot instant above —
# this is what makes EPOCH MODE deterministic: whatever overhead delayed this
# point (mktemp, the ps fork+exec itself, host load) delays SNAP_NOW and every
# process's sampled etime by the SAME amount, so start_epoch = SNAP_NOW - etime
# is unaffected by it (ps etime + date +%s ONLY — no `ps -o lstart`, no
# BSD/GNU `date -d`/`date -j` string parsing; LEARNED 2026-07-19).
SNAP_NOW="$(date +%s)"

# Parse AAI_REAP_STEP_START_EPOCH: EPOCH MODE activates ONLY when it is a
# valid positive integer <= SNAP_NOW (a future step-start is nonsense — clock
# skew). Unset / empty / non-integer / negative / zero / future all leave
# STEP_START empty, which falls back to the EXACT legacy AAI_REAP_MIN_AGE_SECS
# behavior below (SAFETY-CRITICAL fail-safe — never "reap everything").
STEP_START=""
_step_start_raw="${AAI_REAP_STEP_START_EPOCH:-}"
case "$_step_start_raw" in
  '' | *[!0-9]*) ;;
  *)
    _step_start_norm="$(strip_lz "$_step_start_raw")"
    if [ "$_step_start_norm" -gt 0 ] 2>/dev/null && [ "$_step_start_norm" -le "$SNAP_NOW" ] 2>/dev/null; then
      STEP_START="$_step_start_norm"
    fi
    ;;
esac

# Parse AAI_REAP_GRACE_SECS (EPOCH MODE only): default 2 (1s etime truncation +
# 1s snapshot sampling skew). A non-negative integer overrides it (deterministic
# testing only, not production tuning); anything else coerces to the default.
GRACE=2
_grace_raw="${AAI_REAP_GRACE_SECS:-}"
case "$_grace_raw" in
  '') ;;
  *[!0-9]*) ;;
  *) GRACE="$(strip_lz "$_grace_raw")" ;;
esac

MATCH_PIDS=""
# `while read < file` runs in the CURRENT shell (no pipe subshell), so the
# accumulated pid list survives the loop.
while read -r pid etime rest; do
  [ -n "$pid" ] || continue
  # Never touch this reaper or its direct parent (the caller/loop shell); a
  # caller whose command line happens to contain the marker strings must not be
  # reaped by its own defensive sweep.
  [ "$pid" = "$$" ] && continue
  [ "$pid" = "${PPID:-0}" ] && continue
  # Guard 1: must look like a test runner we own.
  case "$rest" in
    *vitest* | *esbuild*) ;;
    *) continue ;;
  esac
  # Guard 2: must belong to THIS workspace — path-prefix anchored, never substring.
  # Require the workspace path to be followed by '/' so that a checkout at
  # /home/user/aai does NOT match a process in /home/user/aai-fork (fixes E1).
  # POSIX `case` with a QUOTED pattern matches "${WORKSPACE}/" literally even when
  # the path contains glob metacharacters (* ? [ ]) — the surrounding * stay
  # wildcards (fixes I3) — and it runs under /bin/sh (dash), unlike the bash-only
  # double-bracket test this file's shebang cannot rely on (fixes W1).
  case "$rest" in
    *"${WORKSPACE}/"*) ;;
    *) continue ;;
  esac
  # Guard 3: age — spare anything that is this step's own in-flight work.
  age="$(etime_to_secs "$etime")"
  if [ -n "$STEP_START" ]; then
    # EPOCH MODE: start_epoch and STEP_START are both instants fixed before
    # this reaper ran, so the decision is invariant to reaper overhead.
    start_epoch=$((SNAP_NOW - age))
    threshold=$((STEP_START - GRACE))
    [ "$start_epoch" -lt "$threshold" ] 2>/dev/null || continue
  else
    # LEGACY MODE (fail-safe fallback): exact pre-epoch fixed-threshold behavior.
    [ "$age" -ge "$MIN_AGE" ] 2>/dev/null || continue
  fi
  MATCH_PIDS="$MATCH_PIDS $pid"
done < "$SNAP"
rm -f "$SNAP"

# Snapshot pid->ppid ONCE for the descendant walk below (avoids a per-pid ps).
# `axo` (like the match snapshot) so processes WITHOUT a controlling tty — every
# backgrounded test worker — are included; a bare `ps -o` under BSD would omit them.
PSNAP="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/aai-reap.$$.psnap")"
ps axo pid=,ppid= > "$PSNAP" 2>/dev/null || : > "$PSNAP"

# For each matched (workspace + etime guarded) pid, make the kill COMPLETE over its
# whole tree — a bare `kill $pid` leaves a descendant whose argv dropped the token
# resident (SPEC-0009 P2). This widens completeness for the MATCHED target only; it
# must NOT broaden scope to another workspace or a fresh sibling:
#   - If the matched pid is its OWN process-group leader (pgid == pid) — exactly what
#     the wrapper makes a leaked runner (setsid session leader) — TERM the whole
#     group so reparented descendants die too.
#   - Otherwise TERM the matched pid PLUS its descendant subtree (portable PPID walk).
# TERM first, short grace, then KILL — mirror the wrapper's escalation. Never a bare
# global pkill; the group/subtree is same-workspace by lineage.
REAPED=0
KILL_TARGETS=""    # space list: "-NNN" = a process group, "NNN" = a bare pid
for pid in $MATCH_PIDS; do
  pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -dc '0-9')"
  if [ -n "$pgid" ] && [ "$pgid" = "$pid" ]; then
    kill -TERM -"$pgid" 2>/dev/null
    KILL_TARGETS="$KILL_TARGETS -$pgid"
  else
    for spid in $(subtree_pids "$pid" "$PSNAP"); do
      kill -TERM "$spid" 2>/dev/null
      KILL_TARGETS="$KILL_TARGETS $spid"
    done
  fi
  REAPED=$((REAPED + 1))
done
if [ "$REAPED" -gt 0 ]; then
  sleep 1
  for t in $KILL_TARGETS; do
    kill -KILL "$t" 2>/dev/null
  done
fi
rm -f "$PSNAP"

echo "reaped: $REAPED"
# Additive diagnostic (SPEC test-018-legacy-spare-attribution / Spec-AC-01):
# report the exact pid set the `reaped: N` count above was derived from. Sourced
# verbatim from MATCH_PIDS (the already-computed match accumulator; it carries a
# leading space, giving `reaped pids: <p1> <p2> ...`), empty tail when N=0. This
# is a pure report of an already-decided value — it adds NO guard and changes
# NOTHING about which pids enter MATCH_PIDS or get killed. POSIX sh, no bashisms.
echo "reaped pids:$MATCH_PIDS"
exit 0
