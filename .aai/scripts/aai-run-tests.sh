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
#   AAI_SHIPPING_WRITE_FATAL=1  opt-in teeth (D5,
#                      spec-adhoc-probes-unisolated-report-only): unset (the
#                      default), an ad-hoc command that dirties the shipping
#                      repository still exits with its own real status. Set,
#                      and only for an ad-hoc invocation whose tripwire state
#                      is dirty, a wrapped command that exited 0 exits 12
#                      instead; a wrapped command that already failed keeps
#                      its own non-zero status. Never affects a suite run or
#                      test-framework.sh.
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

# Resolved ONCE, up front, because the isolation block below may `cd` into a
# disposable checkout: after that, `dirname "$0"` no longer resolves for a
# relative invocation. Every later user of this script's own location reads
# these two instead of re-deriving them.
AAI_SELF_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || AAI_SELF_DIR=''
AAI_REPO_ROOT=''
if [ -n "$AAI_SELF_DIR" ]; then
  AAI_REPO_ROOT=$(cd "$AAI_SELF_DIR/../.." 2>/dev/null && pwd) || AAI_REPO_ROOT=''
fi

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
AAI_TW_DIR="$AAI_SELF_DIR"
if [ -z "$AAI_TW_DIR" ]; then
  AAI_TW_WHY='cannot resolve this script directory'
elif [ ! -f "$AAI_TW_DIR/lib/repo-tripwire.sh" ]; then
  AAI_TW_WHY="library not found: $AAI_TW_DIR/lib/repo-tripwire.sh"
else
  . "$AAI_TW_DIR/lib/repo-tripwire.sh"
  AAI_TW_ROOT="$AAI_REPO_ROOT"
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
  fc_scriptdir="$AAI_SELF_DIR"
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

# --- DISPOSABLE-WORKTREE ISOLATION (spec-suites-run-in-a-disposable-worktree) -
# A SUITE run through this ad hoc funnel gets the same throwaway checkout the
# framework gives it. The tripwire above only tells you afterwards; this stops
# it happening.
#
# SCOPED TO SUITE RUNS, deliberately. This wrapper carries arbitrary commands -
# builds, generators, npm scripts - and isolating those would throw the artifact
# away with the checkout, which is a regression rather than a guard.
# tests/skills/test-framework.sh is excluded for the mirror-image reason: it
# isolates per suite itself, and its run ledger has to land in the real tree.
# AAI_TEST_ISOLATION=0 turns this off. The exit-code contract is untouched
# either way: nothing below this line can change the wrapped command's status.
AAI_ISO_BASE=''
AAI_ISO_WT=''

# The status this invocation reports for itself, in the SAME two words the
# framework's summary line uses (spec-a-run-must-say-whether-isolation-armed):
# `isolated` - the unit ran with its own disposable checkout as its working
# tree; `degraded` - it ran with the shipping repository as its working tree.
# The third value is the one the two funnels must not be read as disagreeing
# about: `not-applicable` covers an invocation isolation was never meant to
# cover (a build, a generator, and the framework itself, which reports for its
# own 83 suites and would have its run ledger discarded if this wrapper isolated
# it). Nothing is printed for that value - a line on every build is a line the
# operator learns to skip, which is the same defect one surface over.
AAI_ISO_STATUS='not-applicable'
AAI_ISO_WHY='the wrapped command is not a suite run'

# The SECOND axis, in the framework's three words
# (spec-a-half-seeded-checkout-says-it-is-isolated): `seeded` - a disposable
# checkout was made and every seeding step completed; `partial` - one was made
# and a seeding step failed, so the checkout exists but is missing content;
# `skipped` - none was made, so there was nothing to seed. It is a SEPARATE axis
# and not a fourth value of the one above, because a half-seeded checkout is
# still a checkout: the command could not reach the shipping repository, so
# calling it `degraded` would make that word untrue. Default `skipped`, so every
# branch that makes no checkout is already correct.
AAI_SEED_STATUS='skipped'
AAI_SEED_WHY=''

# aai_seed_fail <reason> - one failing seeding step. Downgrades the status and
# adds the reason to a DISTINCT set, tested against the delimited form so a
# reason that is a substring of another still gets its own entry.
aai_seed_fail() {
  AAI_SEED_STATUS='partial'
  [ -n "$1" ] || return 0
  case "; $AAI_SEED_WHY; " in
    *"; $1; "*) return 0 ;;
  esac
  AAI_SEED_WHY="${AAI_SEED_WHY:+$AAI_SEED_WHY; }$1"
  return 0
}

# aai_iso_cleanup - remove the checkout. A clone never registers anything in
# the shipping repository (spec-isolation-shares-the-shipping-git D1), so
# there is no admin entry to clear here: unlike a linked worktree, a plain
# `rm -rf` of the checkout's own directory is the whole cleanup. This also
# retires `aai_iso_deregister`, the last code path in this wrapper that
# reached into `<shipping>/.git/worktrees/` and `rm -rf`d an entry there - the
# hazard it existed for (`git worktree prune` deregistering a
# live-but-unreachable operator worktree, measured on git 2.50.1) cannot occur
# when the wrapper never calls `git worktree` against the shipping repository
# at all.
aai_iso_cleanup() {
  [ -n "$AAI_ISO_BASE" ] || return 0
  rm -rf "$AAI_ISO_BASE" >/dev/null 2>&1
  AAI_ISO_BASE=''
  return 0
}

# aai_iso_separated <wt> - spec-isolation-shares-the-shipping-git D3: THE GATE.
# `isolated` means more than "a disposable checkout was made" - it means the
# checkout's own git administrative surface is not the shipping repository's.
# Both sides are resolved through `pwd -P` so a symlinked $TMPDIR cannot
# produce a false equal or a false prefix match. Not separated - including
# when either side cannot be resolved at all - is the fail-closed default
# (return 1), because a probe that cannot answer must never be read as a pass.
aai_iso_separated() {
  ai_wt="$1"
  # HAZ-CD: the git-common-dir output is resolved into a variable and checked
  # non-empty BEFORE it is ever handed to `cd` - `cd ""` is a silent no-op
  # (returns 0, stays put) under sh/dash/bash alike, so a failed `git
  # rev-parse` falling straight into `cd "$(...)"` would leave `pwd -P`
  # reporting the CALLER's own directory - non-empty, not equal, not
  # prefixed - and a probe that could not answer would read as separated.
  case "$ai_wt" in /*) : ;; *) return 1 ;; esac
  ai_iso_gcd=$(cd "$ai_wt" 2>/dev/null && git --no-optional-locks rev-parse --git-common-dir 2>/dev/null)
  [ -n "$ai_iso_gcd" ] || return 1
  ai_iso_common=$(cd "$ai_wt" 2>/dev/null && cd "$ai_iso_gcd" 2>/dev/null && pwd -P 2>/dev/null)
  [ -n "$ai_iso_common" ] || return 1
  case "$AAI_REPO_ROOT" in /*) : ;; *) return 1 ;; esac
  ai_ship_gcd=$(cd "$AAI_REPO_ROOT" 2>/dev/null && git --no-optional-locks rev-parse --git-common-dir 2>/dev/null)
  [ -n "$ai_ship_gcd" ] || return 1
  ai_ship_common=$(cd "$AAI_REPO_ROOT" 2>/dev/null && cd "$ai_ship_gcd" 2>/dev/null && pwd -P 2>/dev/null)
  [ -n "$ai_ship_common" ] || return 1
  [ "$ai_iso_common" != "$ai_ship_common" ] || return 1
  case "$ai_iso_common" in
    "$AAI_REPO_ROOT"/*) return 1 ;;
  esac
  return 0
}

# aai_iso_exec_script - print the path of the script the wrapped command
# actually EXECUTES, or nothing when it executes no script file (`sh -c '...'`,
# `npm test`, a binary). `bash <suite> tests/skills/test-framework.sh` executes
# <suite>: the framework name there is an ARGUMENT OF that suite, not the
# program being run, and the opt-out below must not see it.
aai_iso_exec_script() {
  [ "$#" -gt 0 ] || return 0
  case "${1##*/}" in
    sh|bash|dash|ash|ksh|ksh93|zsh)
      shift
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -c) return 0 ;;
          --) shift; break ;;
          -o|+o) shift; [ "$#" -gt 0 ] && shift ;;
          -*|+*) shift ;;
          *) break ;;
        esac
      done
      ;;
  esac
  [ "$#" -gt 0 ] || return 0
  printf '%s\n' "$1"
  return 0
}

# aai_iso_is_framework_script - true when the script "$@" actually EXECUTES
# (per aai_iso_exec_script) resolves, by RESOLVED PATH and never by suffix, to
# this repository's own tests/skills/test-framework.sh. The single predicate
# behind D5's framework opt-out; shared by aai_iso_is_suite_run below and by
# the AAI_INVOCATION_KIND 'framework' classification further down (N3,
# spec-adhoc-probes-unisolated-report-only) so a future bypass fix only has to
# land in one place, never two.
aai_iso_is_framework_script() {
  ai_fs_exec=$(aai_iso_exec_script "$@")
  if [ -n "$ai_fs_exec" ] && [ "${ai_fs_exec##*/}" = "test-framework.sh" ] && [ -f "$ai_fs_exec" ]; then
    ai_fs_d=$(cd "$(dirname "$ai_fs_exec")" 2>/dev/null && pwd) || ai_fs_d=''
    if [ -n "$ai_fs_d" ] && [ "$ai_fs_d/test-framework.sh" = "$AAI_REPO_ROOT/tests/skills/test-framework.sh" ]; then
      return 0
    fi
  fi
  return 1
}

# aai_iso_is_suite_run - true when an argument names an existing test suite file
# inside this repository's tests/ tree. The framework is never a suite run.
#
# The framework opt-out (D5) is matched by RESOLVED PATH, never by suffix, and
# against the EXECUTED SCRIPT ONLY. Two bypasses, one class, both closed here:
# it used to be the glob `*test-framework.sh` (so the bare word
# `my-test-framework.sh` disarmed isolation), and the exact match that replaced
# it was still tried against EVERY argument (so
# `bash <a-writing-suite> tests/skills/test-framework.sh` disarmed it, and the
# suite then wrote to the shipping checkout under a report-only tripwire -
# Codex, PR #267). Only an invocation whose executed script IS this
# repository's tests/skills/test-framework.sh opts out; TEST-005(e)/(f)/(g)
# hold all three directions.
aai_iso_is_suite_run() {
  if aai_iso_is_framework_script "$@"; then
    return 1
  fi
  for ai_a in "$@"; do
    case "$ai_a" in
      *test-*.sh) ;;
      *) continue ;;
    esac
    [ -f "$ai_a" ] || continue
    ai_d=$(cd "$(dirname "$ai_a")" 2>/dev/null && pwd) || continue
    case "$ai_d/$(basename "$ai_a")" in
      "$AAI_REPO_ROOT"/tests/*) return 0 ;;
    esac
  done
  return 1
}

# --- INVOCATION KIND (D1, spec-adhoc-probes-unisolated-report-only) --------
# One of three words, read-only classification: `suite` (a real test suite
# file under this repository's tests/ tree), `framework` (this repository's
# own tests/skills/test-framework.sh, the isolation opt-out
# `aai_iso_is_suite_run` already carries), or `ad-hoc` (everything else - a
# build, a generator, a node one-liner, any probe). This NEVER feeds back into
# `aai_iso_is_suite_run`'s own predicate and never changes which invocations
# get isolated (SEAM-1) - it only lets the tripwire report below say which of
# the three it is instead of assuming every dirty run is a suite.
AAI_INVOCATION_KIND='ad-hoc'

# THE SUITE-RUN TEST COMES FIRST, and the two environment preconditions are
# reported branches inside it rather than silent members of one conjunction.
# The SET of invocations that get isolated is unchanged - all three predicates
# are side-effect free (`aai_iso_is_suite_run` only reads and `cd`s inside
# subshells) and a conjunction does not care about order. What changes is that a
# suite run which is NOT isolated can now say which of the three reasons it was,
# instead of being indistinguishable from a build.
if aai_iso_is_suite_run "$@"; then
 AAI_INVOCATION_KIND='suite'
 if [ -z "$AAI_REPO_ROOT" ]; then
  AAI_ISO_STATUS='degraded'
  AAI_ISO_WHY='no repository root could be resolved'
 elif [ "${AAI_TEST_ISOLATION:-1}" = "0" ]; then
  AAI_ISO_STATUS='degraded'
  AAI_ISO_WHY='AAI_TEST_ISOLATION=0'
 elif ! git --no-optional-locks -C "$AAI_REPO_ROOT" rev-parse --verify -q HEAD >/dev/null 2>&1; then
  AAI_ISO_STATUS='degraded'
  AAI_ISO_WHY="$AAI_REPO_ROOT is not a git checkout with a commit to branch from"
 else
  AAI_ISO_BASE=$(mktemp -d "${TMPDIR:-/tmp}/aai-iso-wrap.XXXXXX" 2>/dev/null) || AAI_ISO_BASE=''
  # Symlinks resolved, and it is load-bearing: on macOS $TMPDIR lives under
  # /var, a symlink to /private/var, and every .mjs CLI here guards main() with
  # path.resolve(process.argv[1]) === fileURLToPath(import.meta.url). From an
  # unresolved checkout that guard is false, so the CLI prints nothing and exits
  # 0 - a silent no-op that reads as an assertion failure. No-op elsewhere.
  if [ -n "$AAI_ISO_BASE" ]; then
    AAI_ISO_BASE=$(cd "$AAI_ISO_BASE" 2>/dev/null && pwd -P) || AAI_ISO_BASE=''
  fi
  AAI_ISO_WT="$AAI_ISO_BASE/wt"
  # spec-isolation-shares-the-shipping-git D1: a per-suite `git clone --local
  # --no-hardlinks` OWNS its git administrative surface, instead of a linked
  # worktree, whose `git rev-parse --git-common-dir` resolves straight back
  # into the shipping `.git`. `--no-hardlinks` over the default (hardlinking)
  # form: hardlinking loose objects one at a time measured SLOWER on APFS, and
  # over the `--shared` form, which writes `objects/info/alternates` pointing
  # back into the shipping `.git` - a literal path back into the surface this
  # scope exists to remove. A clone lands ON a branch; today's worktree is
  # detached, so `checkout --detach` keeps `git rev-parse --abbrev-ref HEAD`
  # answering the literal `HEAD`.
  if [ -z "$AAI_ISO_BASE" ] ||
     ! git --no-optional-locks -C "$AAI_REPO_ROOT" clone --local --no-hardlinks --quiet "$AAI_REPO_ROOT" "$AAI_ISO_WT" >/dev/null 2>&1 ||
     ! git --no-optional-locks -C "$AAI_ISO_WT" checkout --detach --quiet HEAD >/dev/null 2>&1; then
    [ -n "$AAI_ISO_BASE" ] && rm -rf "$AAI_ISO_BASE"
    AAI_ISO_BASE=''
    # No separate NOTE here any more: this IS the degraded case, and the single
    # status line printed below says so once, in the shared vocabulary, instead
    # of twice in two different wordings.
    AAI_ISO_STATUS='degraded'
    AAI_ISO_WHY='no disposable checkout could be made'
  elif ! aai_iso_separated "$AAI_ISO_WT"; then
    # D3 THE GATE: `isolated` means the MEASURED property, not just "a
    # checkout was made". A checkout whose git surface still resolves to the
    # shipping repository is never counted isolated, however it got that way.
    rm -rf "$AAI_ISO_BASE"
    AAI_ISO_BASE=''
    AAI_ISO_STATUS='degraded'
    AAI_ISO_WHY="the disposable checkout's git surface still resolves to the shipping repository"
  elif ! git -C "$AAI_ISO_WT" remote set-url origin "$AAI_ISO_WT/.git/ORIGIN-DISABLED-BY-ISOLATION" >/dev/null 2>&1; then
    # spec-isolation-shares-the-shipping-git FINDING 1 (bot review, PR #299):
    # a clone's `origin` remote is the clone SOURCE - $AAI_REPO_ROOT, the
    # shipping repository - so a push to `origin` from inside the disposable
    # checkout writes straight into the shipping repository, bypassing the
    # separate common directory D1 otherwise delivers. Measured over the
    # whole suite corpus: every `git push origin` / `git fetch origin` /
    # `git ls-remote origin` runs inside a suite's OWN nested fixture (its
    # own `git init` plus its own `git remote add origin <bare>`), never
    # against "$AAI_ISO_WT" itself; the read-only `origin/main` /
    # `origin/HEAD` resolution six suites rely on (D1) reads the
    # `refs/remotes/origin/*` NAMESPACE the clone and the ref-parity fetch
    # below populate, which does not depend on `origin`'s URL at all. `git
    # remote remove origin` is rejected: it also PRUNES
    # `refs/remotes/origin/*`, which would break that resolution. Repointing
    # the URL to a path that cannot exist leaves the refs alone and turns any
    # push or fetch through `origin` into an immediate, loud failure instead
    # of a silent write into the shipping repository. Placed AFTER the D3
    # gate above, not folded into the clone/checkout condition: a linked
    # worktree that never configured `origin` at all (the TEST-203/210
    # regression shape) would fail `remote set-url` for an unrelated reason
    # (no such remote) and must not steal the gate's own named reason - the
    # gate is what proves "$AAI_ISO_WT" is an owned clone before this command
    # assumes it. A failure here cannot be trusted to keep `origin` from
    # reaching the shipping repository, so it is treated exactly like a gate
    # failure: degraded, same reason, checkout destroyed.
    rm -rf "$AAI_ISO_BASE"
    AAI_ISO_BASE=''
    AAI_ISO_STATUS='degraded'
    AAI_ISO_WHY="the disposable checkout's git surface still resolves to the shipping repository"
  elif ! cd "$AAI_ISO_WT"; then
    rm -rf "$AAI_ISO_BASE"
    AAI_ISO_BASE=''
    AAI_ISO_STATUS='degraded'
    AAI_ISO_WHY='no disposable checkout could be made'
  else
    AAI_ISO_STATUS='isolated'
    AAI_SEED_STATUS='seeded'
    # Ref parity, best-effort like the seeding steps below: a bare local clone
    # carries full history but only ONE local head and a rewritten `origin/*`,
    # which breaks the suites that resolve a base ref as `origin/main` falling
    # back to `main`. A checkout with fewer refs is still a separated
    # checkout, so a fetch failure here does not change the isolation verdict.
    git --no-optional-locks -C "$AAI_ISO_WT" fetch -q --no-tags "$AAI_REPO_ROOT" \
      "+refs/heads/*:refs/heads/*" "+refs/remotes/*:refs/remotes/*" >/dev/null 2>&1
    # Identity, also best-effort: a clone does not inherit the source
    # repository's LOCAL config, so on a host where identity is repo-local
    # only a fixture that commits inside the checkout would fail with "Please
    # tell me who you are" without this.
    ai_uname=$(git --no-optional-locks -C "$AAI_REPO_ROOT" config --get user.name 2>/dev/null)
    [ -z "$ai_uname" ] || git -C "$AAI_ISO_WT" config user.name "$ai_uname" >/dev/null 2>&1
    ai_uemail=$(git --no-optional-locks -C "$AAI_REPO_ROOT" config --get user.email 2>/dev/null)
    [ -z "$ai_uemail" ] || git -C "$AAI_ISO_WT" config user.email "$ai_uemail" >/dev/null 2>&1
    # A worktree checks out a COMMIT, so without the three steps below the copy
    # is HEAD: uncommitted edits and brand-new untracked suite files would be
    # invisible and a TDD RED could never go red. Each step may fail without
    # aborting - that tolerance is deliberate and is KEPT - but no step may fail
    # in SILENCE any more: each one names itself and downgrades the axis.
    # (1) the tracked diff, staged and unstaged, binary-safe.
    if ! git --no-optional-locks -C "$AAI_REPO_ROOT" diff HEAD --binary > "$AAI_ISO_BASE/wt.patch" 2>/dev/null; then
      echo "AAI-SEEDING: NOTE - the working-tree diff could not be captured; the command sees plain HEAD, not your uncommitted edits." >&2
      aai_seed_fail 'the working-tree diff could not be captured'
    elif [ -s "$AAI_ISO_BASE/wt.patch" ] &&
       ! git -C "$AAI_ISO_WT" apply --whitespace=nowarn "$AAI_ISO_BASE/wt.patch" >/dev/null 2>&1; then
      echo "AAI-SEEDING: NOTE - the working-tree diff could not be replayed; the command sees HEAD, not your uncommitted edits." >&2
      aai_seed_fail 'the working-tree diff could not be replayed'
    fi
    # (2) untracked-but-not-ignored files - a brand-new suite is exactly this.
    #
    # The failures are recorded in FILES, not variables, and that is load-bearing
    # rather than a style: a `cmd | while` loop runs in a SUBSHELL, so
    # `aai_seed_fail` called inside it would set the status in a child that then
    # exits and the whole step would report nothing. This is the identical
    # boundary tests/skills/test-aai-suite-isolation.sh documents for its own
    # registries. The markers live in the checkout's BASE directory, beside the
    # patch, never inside the checkout itself.
    git --no-optional-locks -C "$AAI_REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null |
      while IFS= read -r ai_f; do
        case "$ai_f" in
          \"*) printf '%s\n' "$ai_f" >> "$AAI_ISO_BASE/seedfail-quoted"; continue ;;
        esac
        mkdir -p "$AAI_ISO_WT/$(dirname "$ai_f")" 2>/dev/null
        cp -p "$AAI_REPO_ROOT/$ai_f" "$AAI_ISO_WT/$ai_f" 2>/dev/null ||
          printf '%s\n' "$ai_f" >> "$AAI_ISO_BASE/seedfail-untracked"
      done
    if [ -s "$AAI_ISO_BASE/seedfail-quoted" ]; then
      echo "AAI-SEEDING: NOTE - $(wc -l < "$AAI_ISO_BASE/seedfail-quoted" | tr -d ' ') untracked path(s) carry a character git quotes and were NOT seeded into the disposable checkout (first: $(head -n 1 "$AAI_ISO_BASE/seedfail-quoted"))." >&2
      aai_seed_fail 'an untracked path git quotes was not seeded into the disposable checkout'
    fi
    if [ -s "$AAI_ISO_BASE/seedfail-untracked" ]; then
      echo "AAI-SEEDING: NOTE - $(wc -l < "$AAI_ISO_BASE/seedfail-untracked" | tr -d ' ') untracked file(s) could not be copied into the disposable checkout (first: $(head -n 1 "$AAI_ISO_BASE/seedfail-untracked")); a brand-new suite lost here is missing from the copy the command runs in." >&2
      aai_seed_fail 'an untracked file could not be copied into the disposable checkout'
    fi
    # (3) the gitignored per-dev files suites READ. Without these, four
    # assertion groups turn into PASSING SKIPS - a greener run that tests less.
    # This loop is NOT in a subshell, so it reports directly.
    ai_seedfail=0
    ai_seedfirst=''
    for ai_f in ${AAI_TEST_ISOLATION_SEED:-docs/ai/STATE.yaml docs/ai/LOOP_TICKS.jsonl docs/ai/hitl-channel.json}; do
      [ -f "$AAI_REPO_ROOT/$ai_f" ] || continue
      mkdir -p "$AAI_ISO_WT/$(dirname "$ai_f")" 2>/dev/null
      if ! cp -p "$AAI_REPO_ROOT/$ai_f" "$AAI_ISO_WT/$ai_f" 2>/dev/null; then
        ai_seedfail=$((ai_seedfail + 1))
        [ -n "$ai_seedfirst" ] || ai_seedfirst="$ai_f"
      fi
    done
    if [ "$ai_seedfail" -gt 0 ]; then
      echo "AAI-SEEDING: NOTE - $ai_seedfail seed path(s) could not be copied into the disposable checkout (first: $ai_seedfirst); a suite that reads one of them degrades to a passing skip." >&2
      aai_seed_fail 'a seed path could not be copied into the disposable checkout'
    fi
    # Absolute arguments pointing into the checkout are retargeted; relative
    # ones resolve against the new working directory by themselves. An existing
    # absolute path is NORMALISED before the prefix test, because a caller's
    # spelling need not match the root's: $TMPDIR ends in a slash on macOS, so
    # a path built from it carries a `//` that no prefix comparison against a
    # cd-normalised root can ever match. Measured - the un-normalised form left
    # an absolute suite path pointing back at the shipping repository while the
    # working directory had already moved, i.e. isolation that isolated nothing.
    ai_n=$#
    ai_i=0
    while [ "$ai_i" -lt "$ai_n" ]; do
      ai_a="$1"
      shift
      case "$ai_a" in
        /*)
          if [ -e "$ai_a" ]; then
            ai_p=$(cd "$(dirname "$ai_a")" 2>/dev/null && pwd)/$(basename "$ai_a")
            case "$ai_p" in
              "$AAI_REPO_ROOT"/*) ai_a="$AAI_ISO_WT/${ai_p#"$AAI_REPO_ROOT"/}" ;;
            esac
          fi
          ;;
      esac
      set -- "$@" "$ai_a"
      ai_i=$((ai_i + 1))
    done
  fi
 fi
fi

# The second half of D1's classification: this repository's own
# test-framework.sh is never a suite (the opt-out above already excludes it
# from `aai_iso_is_suite_run`), but it is not an ad-hoc probe either - it is
# the load-bearing funnel CI runs. Checked only when the invocation was not
# already classified `suite`, and read-only: `aai_iso_is_framework_script`
# only reads and `cd`s inside a subshell, so this cannot move a single
# invocation between isolation branches (SEAM-1). "$@" is unmodified here for
# a non-suite invocation - the retarget loop above only ever runs on the
# `isolated` path, which requires `suite`.
if [ "$AAI_INVOCATION_KIND" != 'suite' ] && aai_iso_is_framework_script "$@"; then
  AAI_INVOCATION_KIND='framework'
fi

# The status lines, on stderr, exactly once each, and only for an invocation
# isolation was meant to cover. Both vocabularies are the framework's own, so the
# two funnels cannot be read as disagreeing. The SEEDING notes above are
# deliberately NOT folded into the isolation line, because "the working-tree diff
# could not be replayed" describes an incomplete seed inside a checkout that WAS
# made - calling that `degraded` would make the word untrue. They get their own
# line instead, on their own axis.
case "$AAI_ISO_STATUS" in
  isolated)
    echo "AAI-ISOLATION: isolated - this suite run has its own disposable checkout; the shipping repository is not its working tree." >&2
    ;;
  degraded)
    echo "AAI-ISOLATION: degraded - $AAI_ISO_WHY; this suite run uses the shipping repository as its working tree." >&2
    ;;
esac
# The seeding line prints on EVERY suite run, including the all-clear and
# including the run that made no checkout at all. A line that appears only on
# failure is one a reader learns to expect the absence of, and a machine cannot
# tell "the seeding was fine" from "this build predates the line" - which is the
# defect this whole axis exists to remove, so it must not be reintroduced by the
# line's own shape.
if [ "$AAI_ISO_STATUS" != 'not-applicable' ]; then
  case "$AAI_SEED_STATUS" in
    seeded)
      echo "AAI-SEEDING: seeded - every seeding step completed; the disposable checkout carries your working tree." >&2
      ;;
    partial)
      echo "AAI-SEEDING: partial - $AAI_SEED_WHY; the disposable checkout is missing content, so a failure here can be unrelated to the command and a pass can be an assertion that skipped itself." >&2
      ;;
    *)
      # FINDING 2 (bot review, PR #299): this default also fires when the D3
      # gate destroys an ALREADY-MADE checkout (clone and checkout --detach
      # both succeeded) before any seeding step runs - AAI_SEED_STATUS is
      # never touched off its initial value on that path, so the original
      # "no disposable checkout was made" half of this sentence was false
      # there. Broadened rather than replaced, per TEST-113(c): that arm
      # greps the exact original substring for the genuine no-checkout path
      # (AAI_TEST_ISOLATION=0, no repo root, no HEAD to branch from - none of
      # which ever reach a clone), so the substring stays, and the second
      # clause covers the destroyed-checkout case truthfully instead of
      # needing a fourth AAI_SEED_STATUS value.
      echo "AAI-SEEDING: skipped - no disposable checkout was made, or one was made and then discarded before seeding could start (see the AAI-ISOLATION line above for why), so nothing was seeded." >&2
      ;;
  esac
fi

# A pass and a failure both reach the removal after the group reap below; a
# hangup and a Ctrl-C do not, so they are trapped. No EXIT trap: dash runs one
# inside a subshell, and this script forks the watchdog as a subshell.
trap 'aai_iso_cleanup; exit 130' INT
trap 'aai_iso_cleanup; exit 143' TERM
trap 'aai_iso_cleanup; exit 129' HUP

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
# AAI_CMD_REAL_STATUS is the wrapped command's own exit status, fixed here
# before anything below (namely the AAI_SHIPPING_WRITE_FATAL escalation to 12
# further down) can overwrite $STATUS. Friction capture at the tail of this
# script must judge the wrapped command by this value, not by the wrapper's
# own final exit code - a dirty-but-successful ad-hoc command escalated to 12
# did not fail, and must never be recorded as a deterministic_script_failure.
AAI_CMD_REAL_STATUS=$STATUS

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

# The disposable checkout goes BEFORE the after-snapshot, so its removal falls
# inside the tripwire's window instead of after it. This is the removal that
# covers a pass, a failure and a watchdog kill alike; the signal traps above
# cover the paths that never reach here.
aai_iso_cleanup

# Tripwire, second half — fires on EVERY exit path (success, failure, timeout),
# because a command killed at the watchdog is exactly the case most likely to
# have left the repository half-written.
if [ "$AAI_TW_ARMED" -eq 1 ]; then
  aai_tripwire_snapshot "$AAI_TW_ROOT" "$AAI_TW_AFTER"
  AAI_TW_STATE=$(aai_tripwire_state "$AAI_TW_BEFORE" "$AAI_TW_AFTER")
  case "$AAI_TW_STATE" in
    dirty)
      if [ "$AAI_INVOCATION_KIND" = 'ad-hoc' ]; then
        # D3: the trailing remediation line names the REAL remedy for an
        # ad-hoc invocation (a disposable checkout is not made for this kind,
        # D2) and the opt-in below, instead of the suite/fixture sentence that
        # sends the reader looking for a fixture that does not exist here.
        aai_tripwire_report "$AAI_TW_BEFORE" "$AAI_TW_AFTER" \
          "the wrapped command [$AAI_CMD_DESC]" "AAI-TRIPWIRE" \
          "This command's working tree was the shipping repository, not a disposable checkout. Set AAI_SHIPPING_WRITE_FATAL=1 to fail this exit code the next time an ad-hoc command writes to it." >&2
        # Spec-AC-01/D1: exactly one line naming the shipping repository path
        # as this command's working tree, printed only here - a clean ad-hoc
        # run (Spec-AC-02) and a suite/framework run (D3) never print it.
        echo "AAI-ADHOC: $AAI_TW_ROOT was this command's working tree (the shipping repository, not a disposable checkout)." >&2
        # D5: opt-in teeth. A wrapped command that already failed keeps its own
        # non-zero status - a real failure outranks the guard. The watchdog
        # path never reaches here with TIMED_OUT=1 meaningfully affected: the
        # final exit sequence below checks TIMED_OUT before STATUS, so 124
        # still outranks 12 unconditionally.
        if [ "${AAI_SHIPPING_WRITE_FATAL:-0}" = "1" ] && [ "$STATUS" -eq 0 ]; then
          STATUS=12
        fi
      else
        aai_tripwire_report "$AAI_TW_BEFORE" "$AAI_TW_AFTER" \
          "the wrapped command [$AAI_CMD_DESC]" "AAI-TRIPWIRE" >&2
      fi
      ;;
    unavailable)
      # Two opposite cases hide behind one `unavailable`, and the library keeps
      # them apart (aai_tripwire_usable). BEFORE taken, AFTER missing: the
      # wrapped command took the repository (or git) down with it — news about
      # THIS run, so it is reported (report-only, the exit code stays the
      # command's own). BEFORE already unusable: the tripwire could never arm in
      # this environment — a constant of the machine, not an observation of the
      # command — so the wrapper says nothing per run. Measured on the WSL1 CI
      # leg, where git cannot read the /mnt/d checkout: the note fired on EVERY
      # Windows invocation, and across the WSL1 boundary its stderr write
      # displaced aai-run-tests.ps1's own `AAI-BRANCH: WSL` diagnostic, so the
      # line's only lasting effect there was to destroy another one. The
      # load-bearing funnel still names the case where it costs nothing:
      # tests/skills/test-framework.sh prints `tripwire NOT ARMED` on the
      # suite's own progress line.
      if aai_tripwire_usable "$AAI_TW_BEFORE"; then
        echo "AAI-TRIPWIRE: NOTE - the after-snapshot of $AAI_TW_ROOT could not be taken; the wrapped command left the repository unreadable, so this run is NOT attested clean." >&2
      fi
      ;;
  esac
  rm -f "$AAI_TW_BEFORE" "$AAI_TW_AFTER"
fi

if [ "$TIMED_OUT" -eq 1 ]; then
  aai_capture_friction 124 stalled_progress
  exit 124
fi
if [ "$AAI_CMD_REAL_STATUS" -ne 0 ]; then
  aai_capture_friction "$AAI_CMD_REAL_STATUS" deterministic_script_failure
fi
exit "$STATUS"
