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
#   AAI_UNAME         test-only override for the `uname -s` probe below
#                      (SPEC-0046 Spec-AC-05); unset on macOS/Linux in normal
#                      use — this file's behavior there is UNCHANGED.
#
# Platform matrix (Spec-AC-07 / SPEC-0046-spec-test-wrapper-windows-fallback;
# kept identical across this header, aai-reap-tests.sh, aai-run-tests.ps1,
# aai-reap-tests.ps1, and docs/TECHNOLOGY.md):
#   macOS                              - full contract above (setsid/perl-setsid group-kill)
#   Linux                              - full contract above (setsid group-kill)
#   Windows + WSL                      - full contract, via WSL delegation (aai-run-tests.ps1)
#   Windows + Git-Bash-only (no WSL)   - DEGRADED (this file's MSYS branch below): no
#                                         setsid/perl-setsid pretence; best-effort Windows
#                                         `taskkill //T` tree-kill when available, else plain
#                                         `kill`; detached/reparented descendants NOT guaranteed
#                                         reaped (no POSIX sessions on Windows) — weaker than
#                                         the contract above; announced once on stderr
#   Windows, neither WSL nor Git Bash  - AAI-ENV-ERROR: ..., exit 78 (aai-run-tests.ps1); this
#                                         POSIX file is never reached in that configuration
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

# MSYS/MINGW detection (Spec-AC-05): running directly INSIDE Git Bash (no WSL,
# no real POSIX session support) needs a documented degraded launch/cleanup
# chain, never the setsid/perl-setsid pretence below (those primitives do not
# give real process-group isolation under MSYS). AAI_UNAME is a test-only
# override so this branch is unit-testable on macOS/Linux (tests/skills/
# test-aai-win-fallback.sh TEST-007); with it UNSET, `uname -s` reports
# Darwin/Linux and this is a no-op — byte-identical to pre-change behavior.
UNAME_S="${AAI_UNAME:-$(uname -s 2>/dev/null || echo unknown)}"
DEGRADED_MSYS=0
case "$UNAME_S" in
  MSYS*|MINGW*) DEGRADED_MSYS=1 ;;
esac
if [ "$DEGRADED_MSYS" -eq 1 ]; then
  echo "AAI-DEGRADED-MODE: running under Git-Bash/MSYS ($UNAME_S) - no POSIX process-group guarantee; using best-effort Windows tree-kill (taskkill //T) or plain kill; detached/reparented descendants are NOT guaranteed reaped (see docs/TECHNOLOGY.md platform matrix)." >&2
fi

if [ "$#" -eq 0 ]; then
  echo "usage: aai-run-tests.sh <command> [args...]" >&2
  exit 2
fi

# Launch the command as the leader of a NEW session / process group so that even
# descendants it REPARENTS away (double-fork, `( ... ) & exit 0`) stay inside one
# killable group (its pgid == its pid) and a single `kill -<sig> -<pgid>` reaps the
# whole tree. `set -m` ALONE is not enough: under a non-interactive POSIX shell
# (dash — the Linux /bin/sh) job control does NOT create the group, so a reparented
# child escapes and survives (SPEC-0009 P1). Portable precedence:
#   1. setsid(1)      — real new session leader (Linux; absent on macOS).
#   2. perl POSIX::setsid — present on macOS + Linux; perl setsid()s then exec()s
#      the command, so pid is unchanged (exit-code fidelity kept) and pgid == pid.
#   3. bash job control (set -m) — ONLY when the wrapper itself runs under bash.
#   4. bare background — last resort (no isolation) when none of the above exist.
if [ "$DEGRADED_MSYS" -eq 1 ]; then
  "$@" &
  CMD_PID=$!
elif command -v setsid >/dev/null 2>&1; then
  setsid "$@" &
  CMD_PID=$!
elif command -v perl >/dev/null 2>&1; then
  perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV or exit 127' -- "$@" &
  CMD_PID=$!
elif [ -n "${BASH_VERSION:-}" ]; then
  set -m
  "$@" &
  CMD_PID=$!
else
  "$@" &
  CMD_PID=$!
fi
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
  if [ "$DEGRADED_MSYS" -eq 1 ]; then
    if command -v taskkill >/dev/null 2>&1; then
      taskkill //PID "$CMD_PID" //T >/dev/null 2>&1 || kill -TERM "$CMD_PID" 2>/dev/null
    else
      kill -TERM "$CMD_PID" 2>/dev/null
    fi
  else
    kill -TERM -"$PGID" 2>/dev/null || kill -TERM "$CMD_PID" 2>/dev/null
  fi
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
if [ "$DEGRADED_MSYS" -eq 1 ]; then
  if command -v taskkill >/dev/null 2>&1; then
    taskkill //PID "$CMD_PID" //T >/dev/null 2>&1 || kill -TERM "$CMD_PID" 2>/dev/null
    sleep 1
    taskkill //PID "$CMD_PID" //T //F >/dev/null 2>&1 || kill -KILL "$CMD_PID" 2>/dev/null
  else
    kill -TERM "$CMD_PID" 2>/dev/null
    sleep 1
    kill -KILL "$CMD_PID" 2>/dev/null
  fi
else
  kill -TERM -"$PGID" 2>/dev/null
  sleep 1
  kill -KILL -"$PGID" 2>/dev/null
fi

if [ "$TIMED_OUT" -eq 1 ]; then
  exit 124
fi
exit "$STATUS"
