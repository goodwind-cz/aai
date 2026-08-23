#!/usr/bin/env bash
#
# AAI Skills Test Framework
# Runs comprehensive tests for all AAI skills
#
# Usage:
#   bash tests/skills/test-framework.sh [OPTIONS]
#
# Options:
#   --skill SKILL    Test specific skill only (e.g., aai-share)
#   --fix            Auto-fix common issues
#   --verbose        Show detailed output
#   --help           Show this help message
#
# Exit codes:
#   0 - All tests passed
#   1 - Some tests failed
#   2 - Framework error (setup failed, invalid arguments)

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Shipping-repository write tripwire (spec-suites-must-not-touch-the-shipping-repo).
# This is the funnel CI runs, so it is the load-bearing placement: a tripwire
# only in .aai/scripts/aai-run-tests.sh would miss CI entirely.
TRIPWIRE_LIB="$PROJECT_ROOT/.aai/scripts/lib/repo-tripwire.sh"
if [[ ! -f "$TRIPWIRE_LIB" ]]; then
  echo "[FAIL] tripwire library not found: $TRIPWIRE_LIB" >&2
  echo "       Refusing to run suites unguarded — a suite that writes to the" >&2
  echo "       shipping repository would pass quietly." >&2
  exit 2
fi
# shellcheck source=../../.aai/scripts/lib/repo-tripwire.sh
source "$TRIPWIRE_LIB"

# Known-offender ratchet (D8). The tripwire landed on a tree that ALREADY had
# four suites writing to the shipping repository, so failing every one of them
# on day one would have made CI permanently red and the guard unlandable. The
# four were listed here instead, and the list is a RATCHET: it only shrinks.
#
# IT IS EMPTY, and that is the point. Disposable-worktree isolation
# (spec-suites-run-in-a-disposable-worktree) removed the cause; all four suites
# were then re-measured one at a time through the real framework and none of
# them reaches the shipping repository UNDER ISOLATION, so the four entries went
# and their four registry items were closed against the measurement
# (spec-drain-the-tripwire-known-offender-list). Every suite is now held to the
# same rule.
#
# Say exactly that and no more. An earlier version of this comment said the four
# "no longer write", which validation measured to be FALSE: at
# AAI_TEST_ISOLATION=0, aai-state and aai-token-capture still write the shipping
# tree. Isolation REDIRECTS those writes, it did not fix the suites, and the
# zero-ALLOWED evidence behind the drain proves unreachability rather than
# repair — the ALLOWED branch cannot be reached at all while isolation holds.
# The drain is still right, because an exemption that cannot fire protects
# nothing and its removal can only make the guard stricter. Tracked as
# fu-drained-suites-still-write-unisolated.
#
# The emptiness is not left to good intentions: it is a LENGTH RATCHET, asserted
# by tests/skills/test-aai-repo-tripwire.sh TEST-014 against a declared maximum
# of zero. What that buys over a bare emptiness assertion is a NAMED NUMBER in
# the diff and a failure that prints count, maximum and the offending entries.
# It does NOT buy a one-line legal edit: validation measured that raising the
# maximum leaves TEST-013 red, so an exemption costs two edits. The earlier
# claim that "the cheapest legal edit keeps the arm alive" overstated it.
#
# The format below is LIVE CODE, not history. tripwire_allowlist_entry splits on
# '|' and tripwire_ratchet_init strips two fields to reach the paths, so the
# parser demands all three fields whether or not an entry exists today. Write a
# two-field entry and its first path is silently eaten as the registry id.
#
# Format, one entry per line:  <suite>|<registry item id>|<path> [<path>...]
#
# Every rule this list obeys exists because the alternative is a hole:
#   - an entry names its registry item, so a suite cannot be exempted without a
#     filed reason somebody has to close;
#   - an entry lists the exact PATHS it covers, so an allowlisted suite that
#     dirties anything else still fails the run — an entry is not blanket
#     permission for the suite that holds it;
#   - a HEAD move is never covered, whoever the suite is (see
#     aai_tripwire_changed_paths);
#   - an allowlisted hit is reported loudly and counted separately, never
#     folded into the attested-clean count.
# A suite that is NOT on this list still fails the run. Nothing goes in here
# without a registry item id.
#
# The list is drained by HAND, deliberately. An earlier version printed a STALE
# line for any entry whose suite "changed nothing in this run", which is true of
# a suite that skipped (exit 42) or crashed — it told the operator to delete a
# live entry and close a real defect as fixed. Draining is a convenience, not
# part of the guard, so it was removed rather than conditioned.
# The multi-line form is deliberate on an empty table: every arm that needs the
# ratchet MECHANISM seeds its own entries by inserting lines after this anchor,
# so collapsing it to `=()` would put those lines outside the array.
TRIPWIRE_KNOWN_OFFENDERS=(
)

# The ratchet's own paths are additionally CONTENT-HASHED around EVERY suite,
# listed or not — the one place where the D7 status-class limit is closed rather
# than accepted, and it is closed here because the ratchet is what would
# otherwise manufacture the masking it is exempted under. Left status-only, the
# first allowlisted suite dirties docs/INDEX.md, and from that suite onward
# every later write to that same path leaves `git status --porcelain=v1`
# byte-identical: the writer prints a bare PASS and is counted attested clean.
# Measured, not feared — an
# UNLISTED suite writing docs/INDEX.md after aai-hitl-propagation had dirtied it
# passed a full framework run at exit 0 with the write landed. Hashing this
# fixed, tiny path set costs one read per ratchet path per suite, adds no `git`
# call (Spec-AC-05's pair budget is untouched), and makes Spec-AC-06's "a suite
# that is not on the list still fails" true for these paths instead of true only
# until the ratchet fires.
#
# With the table drained this set WOULD BE empty, and the D7 status-class blind
# spot would be back for those three paths — not because the ratchet still masks
# them, but because a FAILING suite does not revert its write either, so a second
# writer of the same path later in the same run still leaves porcelain
# byte-identical. Validation measured exactly that: without the floor below, the
# second same-run writer of docs/INDEX.md prints a bare PASS and is counted
# attested clean with the write landed.
# FIXED here rather than filed, because this scope CAUSED it. Deriving the
# hashed set from the exemption table coupled two unrelated questions — "which
# suite is forgiven" and "which path is worth hashing" — so draining the table
# silently emptied the hash half. The floor below decouples them: these three
# paths are hashed on every run whether or not anything is exempt. They are the
# three a suite has ever actually written (the four drained entries named these
# and nothing else), and they are the ones the D7 status-class blind spot hurts
# most, because they are regenerated artifacts a second writer can leave
# byte-identical in porcelain. The table's paths are still added on top.
TRIPWIRE_ALWAYS_WATCH=(
  "docs/INDEX.md"
  "docs/ai/overview.html"
  "docs/ai/overview-data.json"
)
TRIPWIRE_WATCH_PATHS=("${TRIPWIRE_ALWAYS_WATCH[@]}")
TRIPWIRE_HASH_DEGRADED=false

# tripwire_allowlist_entry <suite> — echoes "<id>|<paths>" for a listed suite,
# and returns 1 for an unlisted one.
tripwire_allowlist_entry() {
  local suite="$1" entry
  for entry in "${TRIPWIRE_KNOWN_OFFENDERS[@]:-}"; do
    if [[ -n "$entry" && "${entry%%|*}" == "$suite" ]]; then
      echo "${entry#*|}"
      return 0
    fi
  done
  return 1
}

# tripwire_path_listed <path> <space-separated allowlisted paths>
# The split of $2 runs under `set -f`: without it an entry path is a GLOB, and
# `docs/*` would silently cover whatever it happens to match in the framework's
# working directory. Entry paths are matched literally, always. The previous
# noglob state is restored, so this cannot leak into a suite's environment.
tripwire_path_listed() {
  local needle="$1" listed rc=1 tw_pl_reglob=false
  case $- in
    *f*) ;;
    *) tw_pl_reglob=true; set -f ;;
  esac
  for listed in $2; do
    if [[ "$needle" == "$listed" ]]; then
      rc=0
      break
    fi
  done
  if [[ "$tw_pl_reglob" == "true" ]]; then
    set +f
  fi
  return "$rc"
}

# tripwire_ratchet_init — validate the table once, and derive the set of paths
# whose CONTENT is watched. Two collisions the table cannot report on its own
# are named here rather than left to the first-match lookup:
#   - a second entry for the same suite is unreachable, so one of the two path
#     lists is not in force and nothing would otherwise say which;
#   - a path field carrying a glob metacharacter matches nothing (paths are
#     compared literally), so the entry exempts less than its author thinks.
tripwire_ratchet_init() {
  local entry suite paths p seen_suites="" seen_paths="" tw_ri_reglob=false
  # Seed the dedup set with the always-watch floor, or a table entry naming one
  # of those three would append it a second time and the path would be hashed
  # twice per snapshot.
  for p in "${TRIPWIRE_ALWAYS_WATCH[@]}"; do
    seen_paths="$seen_paths $p"
  done
  case $- in
    *f*) ;;
    *) tw_ri_reglob=true; set -f ;;
  esac
  for entry in "${TRIPWIRE_KNOWN_OFFENDERS[@]:-}"; do
    if [[ -z "$entry" ]]; then
      continue
    fi
    suite="${entry%%|*}"
    paths="${entry#*|}"
    paths="${paths#*|}"
    if [[ " $seen_suites " == *" $suite "* ]]; then
      log_warn "Tripwire: DUPLICATE ratchet entry for suite '$suite' — the FIRST entry wins and this one ('$entry') is dead code; its paths are NOT covered"
    else
      seen_suites="$seen_suites $suite"
    fi
    for p in $paths; do
      if [[ -z "$p" ]]; then
        continue
      fi
      case "$p" in
        *[\*\?\[]*)
          log_warn "Tripwire: ratchet entry for '$suite' names path '$p', which contains a glob metacharacter — entry paths are matched literally, so this path exempts nothing. Write the paths out."
          ;;
      esac
      if [[ " $seen_paths " != *" $p "* ]]; then
        seen_paths="$seen_paths $p"
        TRIPWIRE_WATCH_PATHS+=("$p")
      fi
    done
  done
  if [[ "$tw_ri_reglob" == "true" ]]; then
    set +f
  fi

  # Degrade with a NOTE, never silently: without a digest tool the ratchet paths
  # fall back to status-class comparison and D7 re-opens for exactly them.
  local tw_ri_probe="$RUN_DIR/ratchet-hash.probe"
  aai_tripwire_hash_snapshot "$PROJECT_ROOT" "$tw_ri_probe" "${TRIPWIRE_WATCH_PATHS[@]:-}"
  if ! aai_tripwire_hash_usable "$tw_ri_probe"; then
    TRIPWIRE_HASH_DEGRADED=true
    log_warn "Tripwire: no content hasher (shasum / sha256sum / cksum) on this machine — the ${#TRIPWIRE_WATCH_PATHS[@]} ratchet path(s) are compared by git status class only, so a SECOND write to one of them in the same run is invisible (D7)"
  fi
}

# tripwire_union_paths <newline list> <newline list> — one deduplicated,
# blank-free list. A path can arrive from the status comparison, from the
# content hash, or from both.
tripwire_union_paths() {
  printf '%s\n%s\n' "$1" "$2" | awk 'NF && !seen[$0]++'
}

# tripwire_hash_line <path> <newline list of status-changed paths> — the report
# line for one content-hash hit. "git status class unmoved" is a CLAIM about
# what the status comparison saw, so it is printed only for a path the status
# comparison did NOT report: a hash hit on a path whose class DID move (every
# ratchet path on a clean checkout, which is every real CI run) is named
# plainly, and appears in the `changed:` list as well.
tripwire_hash_line() {
  if tripwire_path_listed "$1" "$2"; then
    printf 'AAI-TRIPWIRE   content changed (caught by the ratchet-path hash): %s\n' "$1"
  else
    printf 'AAI-TRIPWIRE   content changed (git status class unmoved, caught by the ratchet-path hash): %s\n' "$1"
  fi
}

# --- DISPOSABLE-WORKTREE ISOLATION (spec-suites-run-in-a-disposable-worktree) -
# Every suite runs in a throwaway `git worktree` seeded from the WORKING TREE,
# so a suite's writes do not reach the shipping WORKING TREE by accident, and it
# is observable when they do. Not `cannot`: a worktree links back to the
# repository's common directory, so `git -C "$PROJECT_ROOT" rev-parse
# --git-common-dir` hands a suite the shipping tree's path in ONE command, and
# refs, `.git/config` and `.git/hooks` are reachable the same way (measured;
# spec D7). What this closes is the ordinary path — a suite resolving its own
# root and writing there — not a determined one. That is not closed here. The tripwire above is
# deliberately left armed on the real checkout: if isolation is complete it
# simply never fires, and if it fires that is information.
#
# Seeded from the working tree, not from HEAD, because `git worktree add`
# checks out a COMMIT: uncommitted edits and brand-new untracked suite files
# would be invisible, and a TDD RED could never go red. Measured on the naive
# form: a new suite reports `No such file or directory` and is counted a test
# failure. Three things are therefore replayed into the checkout —
#   1. the tracked diff, staged and unstaged, binary-safe (`git diff HEAD`);
#   2. the untracked-but-not-ignored files (a brand-new suite is exactly this);
#   3. the gitignored per-dev files suites READ. Without (3) four assertion
#      groups silently become PASSING SKIPS — check-state TEST-010/TEST-002,
#      orchestration-mode TEST-016 and orchestration-dispatch's repo-wide gate
#      all skip when docs/ai/STATE.yaml is absent, which is a greener run that
#      tests less: the exact failure mode the tripwire exists to prevent.
# The seed list is overridable (AAI_TEST_ISOLATION_SEED) so a downstream project
# with different per-dev files does not have to fork this file.
ISOLATION_SEED_PATHS="${AAI_TEST_ISOLATION_SEED:-docs/ai/STATE.yaml docs/ai/LOOP_TICKS.jsonl docs/ai/hitl-channel.json}"
ISOLATION_ENABLED=true
ISOLATION_WHY=""
# At most one live disposable checkout at a time (each suite's is destroyed
# before the next is made); the array is what the signal traps below drain, so a
# watchdog kill or a Ctrl-C cannot leak one.
ISOLATION_BASES=()

iso_git() { git --no-optional-locks -C "$PROJECT_ROOT" "$@"; }

# iso_probe — decide ONCE whether isolation is possible, and name the reason
# when it is not (Constitution art. 4: degrade with a NOTE, never silently).
iso_probe() {
  if [[ "${AAI_TEST_ISOLATION:-1}" == "0" ]]; then
    ISOLATION_ENABLED=false
    ISOLATION_WHY="AAI_TEST_ISOLATION=0"
  elif ! command -v git >/dev/null 2>&1; then
    ISOLATION_ENABLED=false
    ISOLATION_WHY="git not found"
  elif ! iso_git rev-parse --verify -q HEAD >/dev/null 2>&1; then
    ISOLATION_ENABLED=false
    ISOLATION_WHY="$PROJECT_ROOT is not a git checkout with a commit to branch from"
  fi
}

# iso_note_reason <reason> — add one reason to the DISTINCT set the summary
# reports. Membership is tested against the delimited form ('; ' on both sides)
# so a reason that is a prefix or a substring of another still gets its own
# entry — "git not found" must not be swallowed by a longer reason containing
# those words.
iso_note_reason() {
  local r="$1"
  [[ -n "$r" ]] || return 0
  case "; $ISOLATION_REASONS; " in
    *"; $r; "*) return 0 ;;
  esac
  ISOLATION_REASONS="${ISOLATION_REASONS:+$ISOLATION_REASONS; }$r"
}

# seed_note_reason <reason> — the same DISTINCT set, for the seeding axis. A
# twin rather than a shared helper on purpose: bash 3.2.57 is a supported host,
# it has no name references, and the eval form that would be needed to write one
# generic function is a worse thing to have in a test funnel than six duplicated
# lines. Membership is tested against the delimited form for the same reason as
# above — a reason that is a substring of another must still get its own entry.
seed_note_reason() {
  local r="$1"
  [[ -n "$r" ]] || return 0
  case "; $SEEDING_REASONS; " in
    *"; $r; "*) return 0 ;;
  esac
  SEEDING_REASONS="${SEEDING_REASONS:+$SEEDING_REASONS; }$r"
}

# iso_seed_fail <reason> — one failing seeding step. It downgrades the PER-SUITE
# status and notes the run-level reason; it counts NOTHING, so however many steps
# fail for one suite that suite is still counted exactly once, at the single
# increment site in run_test.
#
# Noting the reason HERE rather than at the increment site is the one deliberate
# difference from the isolation axis, and it is safe by construction: a suite can
# fail two steps, so its reason is not one string, and every `return 1` path in
# iso_create is BEFORE the first seeding step — so a reason can only be recorded
# on a run of iso_create that goes on to succeed and therefore to be counted.
iso_seed_fail() {
  ISO_LAST_SEED="partial"
  seed_note_reason "$1"
}

# iso_create <skill> — make a fresh disposable checkout seeded from the working
# tree and publish it in ISO_LAST_WT, or return 1.
#
# It sets a global instead of echoing the path, and that is load-bearing: a
# command substitution runs in a SUBSHELL, so `ISOLATION_BASES+=(...)` inside
# one is invisible to the parent and the signal traps below would then drain an
# empty list. Measured — with the echoing form, a watchdog kill left both the
# directory and the `git worktree list` registration behind.
#
# ISO_LAST_SEED rides along for the same reason and by the same mechanism: the
# seeding steps below are the only place that knows a copy failed, and a caller
# cannot read a variable a subshell set.
ISO_LAST_WT=""
ISO_LAST_SEED="seeded"
iso_create() {
  local skill="$1" base wt patch f d
  local n_untracked=0 n_untracked_fail=0 first_untracked_fail=""
  local n_seed=0 n_seed_fail=0 first_seed_fail=""
  ISO_LAST_WT=""
  ISO_LAST_SEED="seeded"
  base="$(mktemp -d "${TMPDIR:-/tmp}/aai-iso-${skill}.XXXXXX" 2>/dev/null)" || return 1
  [[ -n "$base" && "$base" == /* ]] || return 1
  # SYMLINKS RESOLVED, and this is load-bearing, not tidiness. On macOS $TMPDIR
  # is under /var, which is a symlink to /private/var. Every .mjs CLI in this
  # repository guards its entry point with
  # `path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)`;
  # path.resolve keeps the symlinked spelling while import.meta.url carries the
  # real one, so from an unresolved checkout the guard is FALSE, main() never
  # runs, and the CLI exits 0 having printed nothing. Measured: with the raw
  # mktemp path, tests/skills/test-aai-hitl-propagation.sh TEST-010/011/012 got
  # empty stdout at exit 0 from orchestration-dispatch.mjs and read as three
  # assertion failures. `pwd -P` is a no-op wherever TMPDIR is already real.
  base="$(cd "$base" 2>/dev/null && pwd -P)" || return 1
  [[ -n "$base" && "$base" == /* ]] || return 1
  wt="$base/wt"
  if ! iso_git worktree add --detach --quiet "$wt" HEAD >/dev/null 2>&1; then
    rm -rf "$base"
    return 1
  fi
  ISOLATION_BASES+=("$base")
  # THE THREE SEEDING STEPS. Each one may fail without aborting the run — that
  # tolerance is deliberate and is KEPT: a single unreadable file in someone's
  # working tree must not take out every suite. What changes is that the failure
  # is now named. Every step below branches instead of swallowing, so `|| true`
  # has become `else say so`.
  #
  # STEP 1 — replay the tracked working-tree diff. Two distinct failures, because
  # they mean different things: the diff could not be CAPTURED (git failed, or the
  # patch could not be written), and the diff could not be APPLIED. An empty patch
  # is neither — it means there was no work to do.
  patch="$base/working-tree.patch"
  if ! iso_git diff HEAD --binary > "$patch" 2>/dev/null; then
    iso_seed_fail "the working-tree diff could not be captured"
    log_warn "Seeding: '$skill' — the working-tree diff could not be captured, so its disposable checkout is plain HEAD and every uncommitted edit is invisible to it"
  elif [[ -s "$patch" ]] && ! git -C "$wt" apply --whitespace=nowarn "$patch" >/dev/null 2>&1; then
    iso_seed_fail "the working-tree diff could not be replayed"
    log_warn "Seeding: '$skill' — the working-tree diff could not be replayed into its disposable checkout, so it runs against HEAD and uncommitted edits are invisible to it"
  fi

  # STEP 2 — the untracked-but-not-ignored files. A brand-new suite file is
  # exactly this, so a failure here is the one that can remove a suite from its
  # own checkout. ONE note per suite naming the count and the first offender,
  # never one per file: 83 suites times N files is a flood, and a flood is the
  # other way to be unreadable.
  while IFS= read -r -d '' f; do
    n_untracked=$((n_untracked + 1))
    d="$(dirname "$f")"
    [[ "$d" == "." ]] || mkdir -p "$wt/$d" 2>/dev/null || true
    if ! cp -p "$PROJECT_ROOT/$f" "$wt/$f" 2>/dev/null; then
      n_untracked_fail=$((n_untracked_fail + 1))
      [[ -n "$first_untracked_fail" ]] || first_untracked_fail="$f"
    fi
  done < <(iso_git ls-files --others --exclude-standard -z 2>/dev/null)
  if [[ "$n_untracked_fail" -gt 0 ]]; then
    iso_seed_fail "an untracked file could not be copied into the disposable checkout"
    log_warn "Seeding: '$skill' — $n_untracked_fail of $n_untracked untracked file(s) could not be copied into its disposable checkout (first: $first_untracked_fail); a brand-new suite lost here is missing from its own checkout"
  fi

  # STEP 3 — the gitignored per-dev files suites READ. A loss here is the
  # quietest failure of the three: the suite still runs, finds the file absent,
  # and turns its assertion into a passing skip.
  for f in $ISOLATION_SEED_PATHS; do
    [[ -f "$PROJECT_ROOT/$f" ]] || continue
    n_seed=$((n_seed + 1))
    d="$(dirname "$f")"
    [[ "$d" == "." ]] || mkdir -p "$wt/$d" 2>/dev/null || true
    if ! cp -p "$PROJECT_ROOT/$f" "$wt/$f" 2>/dev/null; then
      n_seed_fail=$((n_seed_fail + 1))
      [[ -n "$first_seed_fail" ]] || first_seed_fail="$f"
    fi
  done
  if [[ "$n_seed_fail" -gt 0 ]]; then
    iso_seed_fail "a seed path could not be copied into the disposable checkout"
    log_warn "Seeding: '$skill' — $n_seed_fail of $n_seed seed path(s) could not be copied into its disposable checkout (first: $first_seed_fail); a suite that reads one of them degrades to a passing skip"
  fi
  ISO_LAST_WT="$wt"
}

# iso_deregister <wt> — drop the admin entry for ONE worktree path: the entry a
# `git worktree prune` would drop for it, and no other. Matched by the `gitdir`
# file, which holds the path verbatim as it was given to `worktree add`.
#
# This exists instead of `git worktree prune` because prune is REPOSITORY-WIDE
# and judges every registration by whether its directory is reachable RIGHT NOW.
# An operator worktree parked on an unmounted volume, a detached external disk
# or a temporarily renamed path is unreachable but perfectly alive, and prune
# deletes its `.git/worktrees/<name>` metadata — after which the registration is
# gone for good. Measured on git 2.50.1, both halves of that: `git worktree
# repair <path>` answers `error: unable to locate repository; .git file does not
# reference a repository: <path>/.git` (rc 1), and any git command run INSIDE
# the restored directory answers `fatal: not a git repository:
# <common-dir>/worktrees/<name>` (rc 128). A test harness must not be able to do
# that to the operator's own repository, ~81 times a run.
iso_deregister() {
  local wt="$1" common admin
  [[ -n "$wt" && "$wt" == /* ]] || return 0
  common="$(cd "$PROJECT_ROOT" 2>/dev/null && cd "$(git --no-optional-locks rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd)" || return 0
  [[ -n "$common" && -d "$common/worktrees" ]] || return 0
  for admin in "$common"/worktrees/*; do
    [[ -d "$admin" && -f "$admin/gitdir" ]] || continue
    [[ "$(cat "$admin/gitdir" 2>/dev/null)" == "$wt/.git" ]] || continue
    rm -rf "$admin" 2>/dev/null || true
  done
  return 0
}

# iso_destroy <base> — remove the checkout AND its registration. On the happy
# path `git worktree remove --force` clears both and nothing else runs. Only
# when that removal FAILS — a suite that deleted its own checkout's `.git` link
# leaves `remove` with nothing it recognises, which is the case TEST-004(e)
# holds — is the registration cleared, and then for this one checkout only.
iso_destroy() {
  local base="$1" removed=1
  [[ -n "$base" && "$base" == /* ]] || return 0
  if ! iso_git worktree remove --force "$base/wt" >/dev/null 2>&1; then
    removed=0
  fi
  rm -rf "$base" 2>/dev/null || true
  [[ "$removed" -eq 1 ]] || iso_deregister "$base/wt"
  return 0
}

iso_cleanup_all() {
  local b
  for b in "${ISOLATION_BASES[@]:-}"; do
    [[ -n "$b" ]] && iso_destroy "$b"
  done
  ISOLATION_BASES=()
}

# A pass and a failure both fall through to the removal at the end of run_test;
# a watchdog kill, a hangup and a Ctrl-C do not, so they are trapped. Bash does
# not run an EXIT trap in a subshell or a command substitution, so this cannot
# fire mid-suite.
trap 'iso_cleanup_all' EXIT
trap 'iso_cleanup_all; exit 130' INT
trap 'iso_cleanup_all; exit 143' TERM
trap 'iso_cleanup_all; exit 129' HUP

# Configuration
RESULTS_DIR="$SCRIPT_DIR/results"
RUN_ID="test-$(date -u +%Y%m%d-%H%M%S)"
RUN_DIR="$RESULTS_DIR/$RUN_ID"
VERBOSE=false
AUTO_FIX=false
SPECIFIC_SKILL=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0
TRIPWIRE_FAILED=0
TRIPWIRE_UNATTESTED=0
TRIPWIRE_ALLOWED=0
# Isolation accounting (spec-a-run-must-say-whether-isolation-armed). Two
# counters and a reason set, because "how many suites ran isolated" is the
# question a reader and a CI check both have to be able to answer AFTER the run,
# and until now nothing counted it: the degrade paths were log_warn only, so a
# 1500-line log ended `Passed: 81 (100%)` with isolation off. Every suite lands
# in exactly one of the two — the invariant the summary line and the run ledger
# are both read by is ISOLATION_ISOLATED + ISOLATION_DEGRADED == TOTAL_TESTS.
ISOLATION_ISOLATED=0
ISOLATION_DEGRADED=0
# DISTINCT reasons only, joined with '; '. A fully degraded 83-suite run has one
# reason, not 83 copies of it. A plain string rather than an array: bash 3.2.57
# is a supported host and `local -a x=()` with `${#x[@]}` under `set -u` is a
# hard error there.
ISOLATION_REASONS=""
# Seeding accounting (spec-a-half-seeded-checkout-says-it-is-isolated). The
# SECOND axis, and deliberately not folded into the first: `isolated` says the
# suite ran in a disposable tree, which stays TRUE when that tree was only half
# built. These three say whether it was completely built. Same shape as the two
# above — one per-suite status, ONE increment site, an invariant the summary
# CHECKS: SEEDING_SEEDED + SEEDING_PARTIAL + SEEDING_SKIPPED == TOTAL_TESTS.
# `skipped` is a real state with its own name rather than an absent line: no
# checkout was made, so there was nothing to seed.
SEEDING_SEEDED=0
SEEDING_PARTIAL=0
SEEDING_SKIPPED=0
SEEDING_REASONS=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --skill)
      SPECIFIC_SKILL="$2"
      shift 2
      ;;
    --fix)
      AUTO_FIX=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --help)
      grep '^#' "$0" | grep -v '#!/usr/bin/env' | sed 's/^# //'
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 2
      ;;
  esac
done

# Logging functions
log() {
  echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[PASS]${NC} $*"
}

log_fail() {
  echo -e "${RED}[FAIL]${NC} $*" >&2
}

log_skip() {
  echo -e "${YELLOW}[SKIP]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo -e "${BLUE}[DEBUG]${NC} $*"
  fi
}

# Setup results directory
setup_results_dir() {
  log "Setting up results directory: $RUN_DIR"
  mkdir -p "$RUN_DIR"
  echo "Test run started at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$RUN_DIR/summary.txt"
}

# Discover all skill test files
discover_tests() {
  if [[ -n "$SPECIFIC_SKILL" ]]; then
    # Test specific skill
    local test_file="$SCRIPT_DIR/test-${SPECIFIC_SKILL}.sh"
    if [[ -f "$test_file" ]]; then
      echo "$test_file"
    else
      log_fail "Test file not found: $test_file"
      exit 2
    fi
  else
    # Find all test files
    find "$SCRIPT_DIR" -name "test-aai-*.sh" -type f | sort
  fi
}

# Check system dependencies
check_dependencies() {
  log "Checking system dependencies..."

  local deps_ok=true

  # Core dependencies
  for cmd in git bash; do
    if command -v "$cmd" &> /dev/null; then
      local version
      version=$("$cmd" --version 2>&1 | head -n1 || echo "unknown")
      log_verbose "$cmd: $version"
    else
      log_fail "Required dependency not found: $cmd"
      deps_ok=false
    fi
  done

  # Optional dependencies (check but don't fail)
  for cmd in npm wrangler pandoc pytest cargo; do
    if command -v "$cmd" &> /dev/null; then
      local version
      version=$("$cmd" --version 2>&1 | head -n1 || echo "unknown")
      log_verbose "$cmd: $version"
    else
      log_verbose "$cmd: not found (optional)"
    fi
  done

  if [[ "$deps_ok" == "false" ]]; then
    log_fail "Missing required dependencies"
    exit 2
  fi

  log_success "Dependencies checked"
}

# Run a single test file
run_test() {
  local test_file="$1"
  local test_name
  test_name=$(basename "$test_file" .sh)
  local skill_name="${test_name#test-}"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  # PAIRED with the single isolation increment ~66 lines below. Code review
  # found the comment there documents single-site-ness (nothing is counted
  # TWICE) and says nothing about reach (nothing is counted ZERO times). An
  # early `return` added between here and there would leave TOTAL_TESTS bumped
  # and neither isolation counter bumped, and the summary would read a
  # well-formed "80/81 isolated; 0 degraded" that is simply wrong. There is no
  # such return today. If you add one, bump the isolation counters first — and
  # if you forget, generate_summary's invariant check will say so out loud.

  # Create log file
  local log_file="$RUN_DIR/${skill_name}.log"

  # Progress indicator
  printf "[%2d/%2d] %-20s " "$TOTAL_TESTS" "${#test_files[@]}" "$skill_name"

  # Run test and capture output
  local start_time
  start_time=$(date +%s)
  local exit_code=0

  # TRIPWIRE, half one: snapshot the shipping repository BEFORE the suite runs.
  # Exactly one snapshot pair per suite (Spec-AC-05). The snapshot files live
  # under RUN_DIR (tests/skills/results/, .gitignore'd), so arming the tripwire
  # can never be the write the tripwire reports.
  local tw_before="$RUN_DIR/${skill_name}.tripwire-before"
  local tw_after="$RUN_DIR/${skill_name}.tripwire-after"
  aai_tripwire_snapshot "$PROJECT_ROOT" "$tw_before"
  # ...and one CONTENT snapshot of the ratchet's paths, for every suite. No git
  # call: a plain read per watched path.
  local tw_hash_before="$RUN_DIR/${skill_name}.tripwire-hash-before"
  local tw_hash_after="$RUN_DIR/${skill_name}.tripwire-hash-after"
  aai_tripwire_hash_snapshot "$PROJECT_ROOT" "$tw_hash_before" "${TRIPWIRE_WATCH_PATHS[@]:-}"

  # The suite runs in its own disposable checkout, never in the shipping
  # repository. The framework's OWN artifacts stay behind: $log_file, the
  # snapshot files and metrics.jsonl all live under RUN_DIR in the real tree
  # (D5), so the operator finds the run ledger where it has always been, while
  # everything the SUITE writes under tests/skills/results/ goes with the copy.
  # ONE per-suite verdict, and exactly ONE increment site for it below. Every
  # degrade path assigns iso_status/iso_status_why and nothing else counts, so a
  # suite cannot be counted twice however many paths a later change adds inside
  # this block — the alternative (a counter bumped at each degrade path) breaks
  # the isolated + degraded == total invariant the ledger is read by the first
  # time two paths fire for one suite.
  #
  # The SEEDING verdict rides in the same block and is assigned the moment a
  # checkout EXISTS — before the "is the suite in it" question below, not after.
  # That ordering is the whole reason the denominator is TOTAL_TESTS: a failed
  # untracked copy is what REMOVES a brand-new suite from its own checkout, so
  # the degrade path below and a partial seed are the same event seen twice. A
  # seeding denominator of "isolated suites" would drop exactly that case.
  local iso_base="" iso_root="$PROJECT_ROOT" iso_target="$test_file" iso_rel
  local iso_status="isolated" iso_status_why=""
  local seed_status="skipped"
  if [[ "$ISOLATION_ENABLED" == "true" ]]; then
    if iso_create "$skill_name" && [[ -n "$ISO_LAST_WT" ]]; then
      seed_status="$ISO_LAST_SEED"
      iso_base="$(dirname "$ISO_LAST_WT")"
      iso_rel="${test_file#"$PROJECT_ROOT"/}"
      if [[ -f "$ISO_LAST_WT/$iso_rel" ]]; then
        iso_root="$ISO_LAST_WT"
        iso_target="$ISO_LAST_WT/$iso_rel"
      else
        # The seeding missed this suite. Never let that read as a suite
        # failure: `No such file or directory` on a brand-new suite is exactly
        # the silent TDD failure this design exists to avoid.
        iso_status="degraded"
        iso_status_why="a suite was not in the disposable checkout"
        log_warn "Isolation: '$skill_name' ($iso_rel) runs degraded — it is not in the disposable checkout, so it runs against the shipping repository instead"
        iso_destroy "$iso_base"
        ISOLATION_BASES=()
        iso_base=""
      fi
    else
      iso_status="degraded"
      iso_status_why="no disposable checkout could be made"
      log_warn "Isolation: '$skill_name' runs degraded — no disposable checkout could be made, so it runs against the shipping repository instead"
    fi
  else
    iso_status="degraded"
    iso_status_why="$ISOLATION_WHY"
  fi
  if [[ "$iso_status" == "degraded" ]]; then
    ISOLATION_DEGRADED=$((ISOLATION_DEGRADED + 1))
    iso_note_reason "$iso_status_why"
  else
    ISOLATION_ISOLATED=$((ISOLATION_ISOLATED + 1))
  fi
  # The seeding axis's ONE increment site, beside the isolation one and for the
  # same reason. Every failing step assigns `partial` and counts nothing, so a
  # suite that failed two steps is still one increment. The `*` arm is `skipped`
  # rather than an error: it is the state of a suite that never got a checkout.
  case "$seed_status" in
    seeded)  SEEDING_SEEDED=$((SEEDING_SEEDED + 1)) ;;
    partial) SEEDING_PARTIAL=$((SEEDING_PARTIAL + 1)) ;;
    *)       SEEDING_SKIPPED=$((SEEDING_SKIPPED + 1)) ;;
  esac

  if [[ "$VERBOSE" == "true" ]]; then
    ( [[ -z "$iso_base" ]] || cd "$iso_root"; bash "$iso_target" ) 2>&1 | tee "$log_file" || exit_code=$?
  else
    ( [[ -z "$iso_base" ]] || cd "$iso_root"; bash "$iso_target" ) &> "$log_file" || exit_code=$?
  fi

  # Removed BEFORE the after-snapshot, so the removal itself is inside the
  # tripwire's window rather than after it.
  if [[ -n "$iso_base" ]]; then
    iso_destroy "$iso_base"
    ISOLATION_BASES=()
  fi

  # TRIPWIRE, half two.
  aai_tripwire_snapshot "$PROJECT_ROOT" "$tw_after"
  aai_tripwire_hash_snapshot "$PROJECT_ROOT" "$tw_hash_after" "${TRIPWIRE_WATCH_PATHS[@]:-}"
  local tw_state tw_hash_paths
  tw_state="$(aai_tripwire_state "$tw_before" "$tw_after")"
  tw_hash_paths="$(aai_tripwire_hash_changed "$tw_hash_before" "$tw_hash_after")"

  # A ratchet path whose CONTENT moved is a write, whatever `git status` says
  # about its class. This is the branch that stops the ratchet from masking its
  # own paths: the second and every later writer of docs/INDEX.md in one run is
  # seen here, not lost to a byte-identical porcelain comparison.
  if [[ -n "$tw_hash_paths" && "$tw_state" == "clean" ]]; then
    tw_state="dirty"
  fi

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))

  # The known-offender ratchet (D8). A dirty suite escapes the run-killing
  # verdict only when it is on the seeded allowlist AND every path it moved is
  # one its own entry names. Anything else — an unlisted path, an unlisted
  # suite, a HEAD move — is still a failure.
  local tw_allowed=false tw_allow_id="" tw_allow_paths="" tw_dirty_paths="" tw_unlisted=""
  local tw_status_paths=""
  if [[ "$tw_state" == "dirty" ]]; then
    local tw_entry="" tw_path
    # Status-class changes and ratchet-path content changes are ONE list: a
    # suite that only rewrote an already-dirty ratchet path has an empty status
    # difference and a non-empty content difference, and it must be held to the
    # same path-subset test as any other writer. The status half is kept
    # separately as well, so the report can tell which half saw each path.
    tw_status_paths="$(aai_tripwire_changed_paths "$tw_before" "$tw_after")"
    tw_dirty_paths="$(tripwire_union_paths "$tw_status_paths" "$tw_hash_paths")"
    if tw_entry="$(tripwire_allowlist_entry "$skill_name")"; then
      tw_allow_id="${tw_entry%%|*}"
      tw_allow_paths="${tw_entry#*|}"
      while IFS= read -r tw_path; do
        if [[ -n "$tw_path" ]] && ! tripwire_path_listed "$tw_path" "$tw_allow_paths"; then
          tw_unlisted="${tw_unlisted:+$tw_unlisted }$tw_path"
        fi
      done <<< "$tw_dirty_paths"
      # A commit is never ratcheted, whoever the suite is: it moves HEAD, which
      # no path list can name. An empty path list on a dirty verdict is itself
      # a commit-shaped change, so both halves are required.
      local tw_head_moved=false
      if [[ "$(head -n 1 "$tw_before")" != "$(head -n 1 "$tw_after")" ]]; then
        tw_head_moved=true
        tw_unlisted="${tw_unlisted:+$tw_unlisted }(HEAD moved)"
      fi
      if [[ "$tw_head_moved" == "false" && -z "$tw_unlisted" && -n "$tw_dirty_paths" ]]; then
        tw_allowed=true
        TRIPWIRE_ALLOWED=$((TRIPWIRE_ALLOWED + 1))
      fi
    fi
  fi

  # An unchanged tree does NOT mean the suite ran: a skipped or crashed suite
  # touches nothing and is trivially clean. Keep the two apart (D4) so silence
  # is never mistaken for coverage.
  local tw_attested=false
  local tw_note
  local tw_fail_kind=""
  case "$tw_state" in
    clean)
      if [[ $exit_code -eq 0 ]]; then
        tw_attested=true
        tw_note="tripwire clean"
      elif [[ $exit_code -eq 42 ]]; then
        tw_note="tripwire NOT ATTESTED — suite skipped (exit 42), it never ran"
      else
        tw_note="tripwire NOT ATTESTED — suite exited $exit_code before completing"
      fi
      ;;
    dirty)
      if [[ "$tw_allowed" == "true" ]]; then
        tw_note="tripwire ALLOWED — known offender $tw_allow_id, inside its listed path(s)"
      else
        tw_note="tripwire FAIL — the shipping repository changed"
        tw_fail_kind="dirty"
      fi
      ;;
    *)
      if aai_tripwire_usable "$tw_before"; then
        # The tripwire WAS armed and the after-snapshot is gone: the suite took
        # the repository (or git) down with it. An unavailable snapshot is not
        # evidence of a clean tree, so this fails CLOSED — the alternative,
        # measured before this branch existed, is a green run with a PASS line
        # for a suite that had just deleted .git
        # (`fu-tripwire-unavailable-not-red`).
        tw_note="tripwire FAIL — the after-snapshot could not be taken; the suite left the repository unreadable"
        tw_fail_kind="lost"
      else
        tw_note="tripwire NOT ARMED — no usable git snapshot of $PROJECT_ROOT"
      fi
      ;;
  esac
  if [[ "$tw_attested" != "true" ]]; then
    TRIPWIRE_UNATTESTED=$((TRIPWIRE_UNATTESTED + 1))
  fi

  # A suite that changed the shipping repository FAILS and names itself,
  # whatever its own exit code said (D1).
  local outcome="$exit_code"
  if [[ -n "$tw_fail_kind" ]]; then
    outcome="tripwire"
  fi

  # Check result
  case $outcome in
    0)
      # An exit-0 suite whose tripwire did not attest carries the reason on its
      # OWN line, not only in the aggregate: a bare PASS beside an unarmed or
      # allowlisted tripwire is exactly the reading Spec-AC-04 forbids
      # (`fu-tripwire-unarmed-pass-line-unlabelled`).
      if [[ "$tw_attested" == "true" ]]; then
        printf "${GREEN}PASS${NC} (%.1fs)\n" "$duration"
      else
        printf "${GREEN}PASS${NC} (%.1fs) [%s]\n" "$duration" "$tw_note"
      fi
      PASSED_TESTS=$((PASSED_TESTS + 1))
      echo "PASS" > "$RUN_DIR/${skill_name}.result"
      ;;
    42)
      printf "${YELLOW}SKIP${NC} (%.1fs) [%s]\n" "$duration" "$tw_note"
      SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
      echo "SKIP" > "$RUN_DIR/${skill_name}.result"
      ;;
    tripwire)
      if [[ "$tw_fail_kind" == "lost" ]]; then
        printf "${RED}FAIL${NC} (%.1fs) [TRIPWIRE UNAVAILABLE]\n" "$duration"
      else
        printf "${RED}FAIL${NC} (%.1fs) [TRIPWIRE]\n" "$duration"
      fi
      FAILED_TESTS=$((FAILED_TESTS + 1))
      TRIPWIRE_FAILED=$((TRIPWIRE_FAILED + 1))
      echo "FAIL" > "$RUN_DIR/${skill_name}.result"

      # Name the suite AND what it touched, so the next reader does not have to
      # reproduce the run to find out (D2).
      echo "--- TRIPWIRE VIOLATION ($skill_name) ---"
      if [[ "$tw_fail_kind" == "lost" ]]; then
        echo "AAI-TRIPWIRE FAIL: test suite '$skill_name' (suite exit code $exit_code) left no readable snapshot of the shipping repository."
        echo "AAI-TRIPWIRE   The before-snapshot was taken; the after-snapshot was not — .git or git itself is gone, or the index is unreadable."
        echo "AAI-TRIPWIRE   An unavailable snapshot is not evidence of a clean tree, so this fails closed."
      else
        aai_tripwire_report "$tw_before" "$tw_after" \
          "test suite '$skill_name' (suite exit code $exit_code)" "AAI-TRIPWIRE"
        # A content-only write has NO status line to print — the path was
        # already dirty and its class did not move. Name it explicitly, or the
        # violation block would name a suite and no path at all.
        if [[ -n "$tw_hash_paths" ]]; then
          local tw_hp
          while IFS= read -r tw_hp; do
            if [[ -n "$tw_hp" ]]; then
              tripwire_hash_line "$tw_hp" "$tw_status_paths"
            fi
          done <<< "$tw_hash_paths"
        fi
        if [[ -n "$tw_allow_id" ]]; then
          echo "AAI-TRIPWIRE   NOTE: '$skill_name' is on the known-offender ratchet ($tw_allow_id) for: $tw_allow_paths"
          echo "AAI-TRIPWIRE   It also changed: $tw_unlisted — outside its entry, so the ratchet does not cover this run."
        fi
      fi
      echo "--- end tripwire ($skill_name) ---"
      ;;
    *)
      printf "${RED}FAIL${NC} (%.1fs) [%s]\n" "$duration" "$tw_note"
      FAILED_TESTS=$((FAILED_TESTS + 1))
      echo "FAIL" > "$RUN_DIR/${skill_name}.result"

      # Always surface failure details (not just in --verbose): a non-verbose
      # aggregate run that only prints PASS/FAIL is undiagnosable in CI, which
      # is exactly how the Linux-only skill-suite reds stayed opaque. Dump the
      # failing suite's output tail so a CI log alone explains the failure.
      echo "--- Error Details ($skill_name) ---"
      # A plain tail is NOT enough: verbose suites (e.g. aai-test-canon) push the
      # failing assertion far above a 30-line window, so the CI log showed only a
      # "N/M passed" summary and the failure stayed undiagnosable. Surface every
      # failure line from the WHOLE log first, then the tail for surrounding
      # context. Portable: grep -E only (no -P), non-match tolerated.
      echo "--- failure lines (whole log) ---"
      grep -nE '(^|[[:space:]])(FAIL|ERROR|not ok|✗)' "$log_file" 2>/dev/null | head -n 25 \
        || echo "(no explicit failure marker matched — see tail below)"
      echo "--- tail (last 30 lines) ---"
      tail -n 30 "$log_file"
      echo "--- end $skill_name ---"
      ;;
  esac

  # An allowlisted write is a WARNING, never silence: it names the suite, the
  # paths it moved and the registry item that owes the fix, whatever the suite's
  # own exit code was.
  if [[ "$tw_allowed" == "true" ]]; then
    echo "--- TRIPWIRE ALLOWED ($skill_name) ---"
    echo "AAI-TRIPWIRE WARNING: test suite '$skill_name' changed the shipping repository."
    echo "AAI-TRIPWIRE   allowed by the known-offender ratchet: $tw_allow_id"
    echo "AAI-TRIPWIRE   entry covers: $tw_allow_paths"
    # Every path the suite moved is named EXACTLY once, and the two halves split
    # the list rather than overlapping it: the status half here, the content-only
    # half below. Printing the union in both loops named each hash-watched path
    # twice, under two different wordings, which reads as two separate writes.
    local tw_shown
    while IFS= read -r tw_shown; do
      if [[ -n "$tw_shown" ]]; then
        echo "AAI-TRIPWIRE   changed: $tw_shown"
      fi
    done <<< "$tw_status_paths"
    if [[ -n "$tw_hash_paths" ]]; then
      local tw_ahp
      while IFS= read -r tw_ahp; do
        if [[ -n "$tw_ahp" ]] && ! tripwire_path_listed "$tw_ahp" "$tw_status_paths"; then
          tripwire_hash_line "$tw_ahp" "$tw_status_paths"
        fi
      done <<< "$tw_hash_paths"
    fi
    echo "AAI-TRIPWIRE   This is a filed defect being ratcheted out, not permission. Fix the suite, then delete the entry."
    echo "--- end tripwire ($skill_name) ---"
  fi

  # Record metrics
  echo "{\"skill\":\"$skill_name\",\"status\":\"$(cat "$RUN_DIR/${skill_name}.result")\",\"duration_seconds\":$duration,\"exit_code\":$exit_code,\"tripwire\":\"$tw_state\",\"tripwire_attested\":$tw_attested,\"tripwire_allowed\":$tw_allowed}" >> "$RUN_DIR/metrics.jsonl"
}

# Generate summary report
generate_summary() {
  log ""
  log "========================================="
  log "Test Summary"
  log "========================================="
  log "Total:   $TOTAL_TESTS"
  log_success "Passed:  $PASSED_TESTS ($(( TOTAL_TESTS > 0 ? PASSED_TESTS * 100 / TOTAL_TESTS : 0 ))%)"

  if [[ $FAILED_TESTS -gt 0 ]]; then
    log_fail "Failed:  $FAILED_TESTS ($(( TOTAL_TESTS > 0 ? FAILED_TESTS * 100 / TOTAL_TESTS : 0 ))%)"
  fi

  if [[ $SKIPPED_TESTS -gt 0 ]]; then
    log_skip "Skipped: $SKIPPED_TESTS ($(( TOTAL_TESTS > 0 ? SKIPPED_TESTS * 100 / TOTAL_TESTS : 0 ))%)"
  fi

  # Tripwire accounting. "Attested" is deliberately narrower than "passed": it
  # counts only suites that RAN TO COMPLETION and left the shipping repository
  # untouched. A skipped, crashed or unguarded suite is reported as such, never
  # folded into the clean count.
  if [[ $TRIPWIRE_FAILED -gt 0 ]]; then
    log_fail "Tripwire: $TRIPWIRE_FAILED suite(s) failed the shipping-repository tripwire (changed it, or left it unreadable)"
  fi
  if [[ $TRIPWIRE_ALLOWED -gt 0 ]]; then
    log_warn "Tripwire: $TRIPWIRE_ALLOWED known-offender suite(s) changed the shipping repository inside their allowlisted paths (ratchet, not permission — see the WARNING blocks above)"
  fi
  log "Tripwire: $(( TOTAL_TESTS - TRIPWIRE_UNATTESTED ))/$TOTAL_TESTS suite(s) attested clean; $TRIPWIRE_UNATTESTED not attested (skipped, failed, allowlisted, or unguarded)"
  if [[ "$TRIPWIRE_HASH_DEGRADED" == "true" ]]; then
    log_warn "Tripwire: the count above is CLASS-ONLY for the ratchet's paths — no digest tool on this machine, so a second write to one of them in this run was invisible (D7)"
  fi

  # Isolation accounting, same two-line shape as the tripwire above: a warning
  # only when there is something to warn about, then an UNCONDITIONAL accounting
  # line. The unconditional line is the point — a line that appears only on
  # failure is one a reader learns to expect the absence of, and a machine
  # cannot tell "isolation was fine" from "this build predates the line".
  # Report-only by design: nothing here touches FAILED_TESTS or the exit code
  # (spec section "Why a degraded run does not fail the run").
  if [[ $ISOLATION_DEGRADED -gt 0 ]]; then
    # A degrade with no reason is worse than no line: code review MEASURED
    # "Reason(s): " with nothing after it when a path marks a suite degraded and
    # forgets to set the reason. Today's three paths all set one; a fourth might
    # not, and an empty tail reads as "no reason to give" rather than "the reason
    # was lost". Name the gap instead of trailing off.
    local iso_reasons_shown="$ISOLATION_REASONS"
    [[ -n "$iso_reasons_shown" ]] \
      || iso_reasons_shown="(none recorded — a degrade path did not name its reason; this is a defect in the framework, not in the suite)"
    log_warn "Isolation: $ISOLATION_DEGRADED suite(s) ran degraded — against the shipping repository, with only the tripwire between them and it. Reason(s): $iso_reasons_shown"
  fi
  log "Isolation: $ISOLATION_ISOLATED/$TOTAL_TESTS suite(s) isolated; $ISOLATION_DEGRADED degraded"
  # The invariant this number is read by, checked rather than assumed. It holds
  # only while every path that bumps TOTAL_TESTS also reaches the isolation
  # increment, and nothing structural enforces that — see the note at the
  # TOTAL_TESTS site. An under-count is otherwise a well-formed lie. Report
  # only: this must not change the exit code (Spec-AC-04).
  if [[ $(( ISOLATION_ISOLATED + ISOLATION_DEGRADED )) -ne "$TOTAL_TESTS" ]]; then
    log_warn "Isolation: ACCOUNTING BROKEN — $ISOLATION_ISOLATED + $ISOLATION_DEGRADED does not equal $TOTAL_TESTS. Some suite ran without being classified; treat both numbers above as unreliable."
  fi

  # Seeding accounting — the SECOND axis, in the same three-part shape: a warning
  # only when there is something to warn about, then an UNCONDITIONAL accounting
  # line, then the invariant CHECKED rather than assumed. `isolated` above and
  # `fully seeded` here answer two different questions, and a run can be 81/81 on
  # the first and 0/81 on the second.
  # Report-only by design: nothing here touches FAILED_TESTS or the exit code
  # (spec section "Why an incomplete seed does not fail the run").
  if [[ $SEEDING_PARTIAL -gt 0 ]]; then
    local seed_reasons_shown="$SEEDING_REASONS"
    [[ -n "$seed_reasons_shown" ]] \
      || seed_reasons_shown="(none recorded — a seeding step failed without naming its reason; this is a defect in the framework, not in the suite)"
    log_warn "Seeding: $SEEDING_PARTIAL suite(s) ran in a PARTLY SEEDED disposable checkout — the isolation held, but content they may read never arrived, so a failure can be unrelated to the suite and a pass can be an assertion that skipped itself. Reason(s): $seed_reasons_shown"
  fi
  log "Seeding: $SEEDING_SEEDED/$TOTAL_TESTS suite(s) fully seeded; $SEEDING_PARTIAL partial; $SEEDING_SKIPPED skipped"
  if [[ $(( SEEDING_SEEDED + SEEDING_PARTIAL + SEEDING_SKIPPED )) -ne "$TOTAL_TESTS" ]]; then
    log_warn "Seeding: ACCOUNTING BROKEN — $SEEDING_SEEDED + $SEEDING_PARTIAL + $SEEDING_SKIPPED does not equal $TOTAL_TESTS. Some suite ran without being classified; treat all three numbers above as unreliable."
  fi

  log ""
  log "Results saved to: $RUN_DIR"

  # Write summary file
  cat > "$RUN_DIR/summary.txt" <<EOF
AAI Skills Test Summary
=======================

Run ID: $RUN_ID
Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Environment: $(uname -s) $(uname -r)

Results:
--------
Total:   $TOTAL_TESTS
Passed:  $PASSED_TESTS ($(( TOTAL_TESTS > 0 ? PASSED_TESTS * 100 / TOTAL_TESTS : 0 ))%)
Failed:  $FAILED_TESTS ($(( TOTAL_TESTS > 0 ? FAILED_TESTS * 100 / TOTAL_TESTS : 0 ))%)
Skipped: $SKIPPED_TESTS ($(( TOTAL_TESTS > 0 ? SKIPPED_TESTS * 100 / TOTAL_TESTS : 0 ))%)

Failed Tests:
EOF

  # List failed tests
  if [[ $FAILED_TESTS -gt 0 ]]; then
    for result_file in "$RUN_DIR"/*.result; do
      if grep -q "FAIL" "$result_file"; then
        local skill_name
        skill_name=$(basename "$result_file" .result)
        echo "  - $skill_name" >> "$RUN_DIR/summary.txt"
      fi
    done
  else
    echo "  (none)" >> "$RUN_DIR/summary.txt"
  fi

  # Record in project metrics.
  #
  # `suites_isolated` / `suites_degraded` carry the same two numbers as the
  # summary line for this RUN_ID, and `suites_seeded` / `suites_partly_seeded` /
  # `suites_seed_skipped` the same three from the seeding line, so both claims
  # survive the scrollback. There is
  # deliberately NO probe-state sentinel: iso_probe runs in main() before
  # discovery and this append runs only after the suite loop, so no record can
  # exist without a completed probe behind it. What a reader checks instead is
  # the invariant suites_isolated + suites_degraded == total, and its seeding
  # twin suites_seeded + suites_partly_seeded + suites_seed_skipped == total.
  #
  # NOT tripwire-covered, and that is pre-existing: this append writes to the
  # TRACKED docs/ai/tests/test-runs.jsonl AFTER the last suite's tripwire
  # snapshot, so the tripwire is structurally blind to it
  # (fu-framework-appends-tracked-testruns). All five accounting fields ride on
  # that one write; they add no new one.
  if [[ -d "$PROJECT_ROOT/docs/ai/tests" ]] || mkdir -p "$PROJECT_ROOT/docs/ai/tests" 2>/dev/null; then
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"type\":\"skill_test\",\"run_id\":\"$RUN_ID\",\"total\":$TOTAL_TESTS,\"passed\":$PASSED_TESTS,\"failed\":$FAILED_TESTS,\"skipped\":$SKIPPED_TESTS,\"suites_isolated\":$ISOLATION_ISOLATED,\"suites_degraded\":$ISOLATION_DEGRADED,\"suites_seeded\":$SEEDING_SEEDED,\"suites_partly_seeded\":$SEEDING_PARTIAL,\"suites_seed_skipped\":$SEEDING_SKIPPED}" >> "$PROJECT_ROOT/docs/ai/tests/test-runs.jsonl"
  fi
}

# Main execution
main() {
  echo ""
  echo "AAI Skills Test Framework"
  echo "========================="
  echo ""

  # Setup
  setup_results_dir
  check_dependencies
  tripwire_ratchet_init
  iso_probe
  if [[ "$ISOLATION_ENABLED" == "true" ]]; then
    log "Isolation: every suite runs isolated in a disposable git worktree seeded from the working tree"
  else
    log_warn "Isolation: every suite runs degraded ($ISOLATION_WHY) — against the shipping repository, with only the tripwire between them and it"
  fi

  # Discover tests
  log "Discovering skill tests..."
  local test_files=()
  while IFS= read -r test_file; do
    test_files+=("$test_file")
  done < <(discover_tests)

  if [[ ${#test_files[@]} -eq 0 ]]; then
    log_fail "No tests to run"
    exit 2
  fi

  log "Found ${#test_files[@]} test(s)"

  # Run tests
  log ""
  log "Running tests..."
  log ""

  for test_file in "${test_files[@]}"; do
    run_test "$test_file"
  done

  # Generate summary
  log ""
  generate_summary

  # Determine exit code
  if [[ $FAILED_TESTS -gt 0 ]]; then
    exit 1
  else
    exit 0
  fi
}

# Run main
main "$@"
