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
#   - ETIME guard: under concurrent subagents, a matching process YOUNGER than
#     AAI_REAP_MIN_AGE_SECS (a sibling's in-flight run started after this step
#     began) is NEVER killed. Only trees older than the threshold are reaped.
#
# Usage:
#   .aai/scripts/aai-reap-tests.sh
#
# Environment:
#   AAI_REAP_WORKSPACE    workspace path to scope by (default $PWD)
#   AAI_REAP_MIN_AGE_SECS minimum process age in seconds to be eligible
#                         (default 0; a younger matching process is spared)
#
# Output: prints the number of reaped process trees ("reaped: N"). No-op (exit 0)
# when nothing matches.
#
# POSIX sh; works on macOS (BSD ps) + Linux (GNU ps).

set -u

WORKSPACE="${AAI_REAP_WORKSPACE:-$PWD}"
WORKSPACE="${WORKSPACE%/}"    # strip any trailing slash once (prevents double-slash in guard)
MIN_AGE="${AAI_REAP_MIN_AGE_SECS:-0}"
case "$MIN_AGE" in
  '' | *[!0-9]*) MIN_AGE=0 ;;
esac

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

SNAP="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/aai-reap.$$.snap")"
# Snapshot processes: pid, etime, full args. `=` headers suppress the header row.
ps axo pid=,etime=,args= > "$SNAP" 2>/dev/null || {
  rm -f "$SNAP"
  echo "reaped: 0"
  exit 0
}

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
  # Guard 3: etime — spare anything younger than the step-start threshold.
  age="$(etime_to_secs "$etime")"
  [ "$age" -ge "$MIN_AGE" ] 2>/dev/null || continue
  MATCH_PIDS="$MATCH_PIDS $pid"
done < "$SNAP"
rm -f "$SNAP"

REAPED=0
for pid in $MATCH_PIDS; do
  # TERM first, short grace, then KILL — mirror the wrapper's escalation.
  kill -TERM "$pid" 2>/dev/null
  REAPED=$((REAPED + 1))
done
if [ "$REAPED" -gt 0 ]; then
  sleep 1
  for pid in $MATCH_PIDS; do
    kill -KILL "$pid" 2>/dev/null
  done
fi

echo "reaped: $REAPED"
exit 0
