#!/bin/sh
#
# aai-run-tests.sh — run a test/build command inside its own killable process
# group, with an inline timeout watchdog, guaranteeing that no descendant of the
# command can outlive this call (SPEC-0009 / ISSUE-0002 fix #1).
#
# Usage:
#   .aai/scripts/aai-run-tests.sh <command> [args...]
#
# Contract (SPEC-0009 D2):
#   - Starts a NEW process group (set -m) so the command and ALL its descendants
#     share one killable process-group id (pgid == the command's pid).
#   - Runs the command as that group leader in the background.
#   - Arms an inline watchdog (macOS has no GNU `timeout`): after
#     AAI_TEST_TIMEOUT seconds (default 300) it TERMs the whole group.
#   - Waits for the command and records its REAL exit status.
#   - On EVERY exit path (success / failure / timeout) it ALWAYS sends TERM then,
#     after a short grace, KILL to the whole group — reaping hung descendants
#     (vitest fork workers, esbuild) so a leaky child that backgrounds work and
#     exits 0 still leaves NO survivor.
#   - Exits with the command's real exit code on normal completion, or 124
#     (GNU-timeout convention) when the watchdog fired — so the loop can tell a
#     hung run from an ordinary test failure.
#
# Environment:
#   AAI_TEST_TIMEOUT  timeout in seconds (default 300; non-integer or <=0 -> 300)
#
# POSIX sh; works on macOS + Linux (no GNU-only tools).

set -u

TIMEOUT="${AAI_TEST_TIMEOUT:-300}"
# Coerce a non-integer / empty / non-positive timeout to the safe default rather
# than never-timing-out or timing-out instantly.
case "$TIMEOUT" in
  '' | *[!0-9]*) TIMEOUT=300 ;;
esac
[ "$TIMEOUT" -gt 0 ] 2>/dev/null || TIMEOUT=300

if [ "$#" -eq 0 ]; then
  echo "usage: aai-run-tests.sh <command> [args...]" >&2
  exit 2
fi

# Enable job control so the backgrounded command becomes a process-group leader
# (its pgid == its pid). Every descendant it spawns inherits that group, so a
# single `kill -<signal> -<pgid>` reaps the whole tree.
set -m

"$@" &
CMD_PID=$!
PGID="$CMD_PID"

# Marker file the watchdog touches iff it fired (portable boolean across the
# subshell boundary).
TIMED_OUT_FILE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/aai-run-tests.$$.timeout")"
rm -f "$TIMED_OUT_FILE"

# Inline watchdog: poll the command once per second up to TIMEOUT, then TERM the
# whole group. Exits early (doing nothing) the moment the command finishes.
(
  i=0
  while [ "$i" -lt "$TIMEOUT" ]; do
    kill -0 "$CMD_PID" 2>/dev/null || exit 0
    sleep 1
    i=$((i + 1))
  done
  : > "$TIMED_OUT_FILE"
  kill -TERM -"$PGID" 2>/dev/null || kill -TERM "$CMD_PID" 2>/dev/null
) &
WATCHDOG_PID=$!

# Wait for the command; capture its REAL exit status.
wait "$CMD_PID"
STATUS=$?

# Stop the watchdog (it may already have exited).
kill "$WATCHDOG_PID" 2>/dev/null
wait "$WATCHDOG_PID" 2>/dev/null

TIMED_OUT=0
if [ -f "$TIMED_OUT_FILE" ]; then
  TIMED_OUT=1
fi
rm -f "$TIMED_OUT_FILE"

# ALWAYS reap the whole group on every exit path (success / failure / timeout),
# so a descendant that outlived the group leader (the classic hung-vitest leak)
# is TERM'd, then KILL'd after a short grace.
kill -TERM -"$PGID" 2>/dev/null
sleep 1
kill -KILL -"$PGID" 2>/dev/null

if [ "$TIMED_OUT" -eq 1 ]; then
  exit 124
fi
exit "$STATUS"
