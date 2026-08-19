#!/bin/sh
#
# aai-run-tests.sh — run a test/build command inside its own killable process
# group, with an inline timeout watchdog, guaranteeing that no descendant of the
# command can outlive this call (SPEC-0009 / ISSUE-0002 fix #1).
#
# Usage (canonical invocation, CHANGE-0139 - run from the repository root):
#   bash .aai/scripts/aai-run-tests.sh <command> [args...]
#
#   Run it from the repository root; when elsewhere, cd to the repo root
#   first - never rewrite the script path relative to the current directory,
#   and never invoke bash.exe, sh, or wsl directly for test runs - the
#   dispatcher layer owns interpreter routing (Windows enters through
#   aai-run-tests.ps1, which delegates here).
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
# Exit-code contract (CHANGE-0133 / SPEC-0120-spec-ps1-wrapper-path-dup,
# Spec-AC-06 parity check — the ONE sanctioned behavior change in this file is
# the perl-fallback exec-failure fidelity fix below (ENOENT -> 127, anything
# else -> 126, matching native POSIX shell semantics); everything else here is
# characterization only): 124 means a process that RAN and was killed at
# AAI_TEST_TIMEOUT (the watchdog below); 125 is the aai-run-tests.ps1
# dispatcher's spawn/infrastructure-failure code and is NEVER produced by
# this POSIX file. This file has no separate "could not start the command"
# branch of its own to masquerade as a timeout: an unlaunchable command
# surfaces the SHELL's own real code instead — 127 for a command not found,
# 126 for a file that exists but is not executable — both distinct from, and
# never confused with, 124.
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

# Snapshot the wrapped command for the friction observation below (feeds only
# the fingerprint — never persisted). Captured now, at script scope, because
# the capture helper runs after `wait` where a function body's own $@ would
# shadow the wrapper's positional parameters.
AAI_CMD_DESC="$*"

# --- SHIPPING-REPOSITORY WRITE TRIPWIRE ------------------------------------
# (spec-suites-must-not-touch-the-shipping-repo, D1/D2.) This is the funnel
# roles invoke ad hoc; tests/skills/test-framework.sh is the one CI runs and
# carries the same tripwire. Here the tripwire is REPORT-ONLY on purpose: this
# wrapper's exit code is a pinned contract (124 watchdog, the command's real
# status otherwise), and the canonical whole-suite invocation legitimately
# appends to the tracked-but-gitignored docs/ai/tests/test-runs.jsonl, so
# turning dirt into an exit code here would make the most common invocation
# permanently red. The framework tripwire is the one that fails a run.
AAI_TW_ARMED=0
AAI_TW_WHY=''
AAI_TW_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || AAI_TW_DIR=''
if [ -z "$AAI_TW_DIR" ]; then
  AAI_TW_WHY='cannot resolve this script directory'
elif [ ! -f "$AAI_TW_DIR/lib/repo-tripwire.sh" ]; then
  AAI_TW_WHY="library not found: $AAI_TW_DIR/lib/repo-tripwire.sh"
else
  . "$AAI_TW_DIR/lib/repo-tripwire.sh"
  AAI_TW_ROOT=$(cd "$AAI_TW_DIR/../.." 2>/dev/null && pwd) || AAI_TW_ROOT=''
  AAI_TW_BEFORE="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/aai-tripwire-b.$$")"
  AAI_TW_AFTER="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/aai-tripwire-a.$$")"
  if [ -n "$AAI_TW_ROOT" ] && [ -n "$AAI_TW_BEFORE" ] && [ -n "$AAI_TW_AFTER" ]; then
    aai_tripwire_snapshot "$AAI_TW_ROOT" "$AAI_TW_BEFORE"
    AAI_TW_ARMED=1
  else
    AAI_TW_WHY='cannot resolve the repository root or a snapshot file'
  fi
fi
if [ "$AAI_TW_ARMED" -eq 0 ]; then
  echo "AAI-TRIPWIRE: NOTE - not armed ($AAI_TW_WHY); a write to the shipping repository would go unreported." >&2
fi

# --- CAPTURE POINT 1 — deterministic friction capture (CHANGE deterministic-
# friction-capture) ----------------------------------------------------------
# When the wrapped command fails, append ONE raw schema-v2 observation to the
# offline spool via the existing aai-friction.mjs `record` CLI, so the friction
# loop gathers deterministic evidence no prose hook depends on. RAW only — no
# ownership judgment here; confidence is `low` and triage stays review-mode.
#
# NEVER-MASK-THE-CALLER: this helper is best-effort and ALWAYS returns 0; every
# failure (absent CLI/node, unwritable spool, rejected input) is swallowed so
# the wrapper's own exit code is the sole contract (FRICTION_PROTOCOL.md
# "Capture never masks the caller").
#
# ISOLATION (pinned by tests/skills/test-aai-friction-capture-points.sh):
#   - off-switch: AAI_FRICTION_CAPTURE=0 disables capture entirely (the wrapper
#     regression suite sets it so its deliberately-failing commands never
#     pollute the real spool);
#   - existence gate: capture fires only when the resolved spool DIR already
#     exists. A fixture repo has no docs/ai/friction, so it can never create or
#     write a spool. The spool dir is AAI_FRICTION_SPOOL_DIR when set, else this
#     script's own repo-root docs/ai/friction.
aai_capture_friction() {
  # $1 = exit code (integer), $2 = failure_class (taxonomy enum)
  [ "${AAI_FRICTION_CAPTURE:-1}" != "0" ] || return 0
  command -v node >/dev/null 2>&1 || return 0
  fc_scriptdir=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || return 0
  [ -n "$fc_scriptdir" ] || return 0
  fc_cli="$fc_scriptdir/aai-friction.mjs"
  [ -f "$fc_cli" ] || return 0
  if [ -n "${AAI_FRICTION_SPOOL_DIR:-}" ]; then
    fc_dir="$AAI_FRICTION_SPOOL_DIR"
  else
    fc_dir="$fc_scriptdir/../../docs/ai/friction"
  fi
  [ -d "$fc_dir" ] || return 0
  # Sanitize the command for the (non-persisted) fingerprint: drop the only
  # JSON-hostile characters (double-quote, backslash, control chars) and cap the
  # length, so a command with odd characters can never produce invalid JSON.
  fc_cmd=$(printf '%s' "$AAI_CMD_DESC" | tr -d '"\\' | tr -d '[:cntrl:]' | cut -c1-180)
  fc_json=$(printf '{"schema_version":2,"skill_id":"aai-run-tests","skill_phase":"test-execution","failure_class":"%s","expected_behavior":"the wrapped command exits 0 under aai-run-tests","observed_behavior":"wrapped command exited %s: %s","confidence":"low"}' "$2" "$1" "$fc_cmd")
  printf '%s' "$fc_json" | AAI_FRICTION_SPOOL_DIR="$fc_dir" node "$fc_cli" record --input - >/dev/null 2>&1 || true
  return 0
}

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
  # CHANGE-0133 Spec-AC-06: `exec @ARGV or exit 127` collapsed EVERY exec
  # failure to 127, including a non-executable file (EACCES), which should
  # report the shell's real 126 -- discovered via the TEST-024 characterization
  # guard on a setsid-less host (this branch is exactly where that host lands).
  # `exec` never returns on success; on failure $! carries the OS errno, so
  # ENOENT (not found) -> 127, anything else (not executable, etc.) -> 126,
  # matching native POSIX shell exec-failure semantics on the setsid(1) path.
  perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV; exit($!{ENOENT} ? 127 : 126)' -- "$@" &
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

# Tripwire, second half — fires on EVERY exit path (success, failure, timeout),
# because a command killed at the watchdog is exactly the case most likely to
# have left the repository half-written.
if [ "$AAI_TW_ARMED" -eq 1 ]; then
  aai_tripwire_snapshot "$AAI_TW_ROOT" "$AAI_TW_AFTER"
  AAI_TW_STATE=$(aai_tripwire_state "$AAI_TW_BEFORE" "$AAI_TW_AFTER")
  case "$AAI_TW_STATE" in
    dirty)
      aai_tripwire_report "$AAI_TW_BEFORE" "$AAI_TW_AFTER" \
        "the wrapped command [$AAI_CMD_DESC]" "AAI-TRIPWIRE" >&2
      ;;
    unavailable)
      echo "AAI-TRIPWIRE: NOTE - snapshot unusable for $AAI_TW_ROOT; this run is NOT attested clean." >&2
      ;;
  esac
  rm -f "$AAI_TW_BEFORE" "$AAI_TW_AFTER"
fi

if [ "$TIMED_OUT" -eq 1 ]; then
  aai_capture_friction 124 stalled_progress
  exit 124
fi
if [ "$STATUS" -ne 0 ]; then
  aai_capture_friction "$STATUS" deterministic_script_failure
fi
exit "$STATUS"
