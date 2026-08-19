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
# four are listed here instead, and the list is a RATCHET: it only shrinks.
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
TRIPWIRE_KNOWN_OFFENDERS=(
  "aai-hitl-propagation|fu-hitl-propagation-writes-real-index|docs/INDEX.md"
  "aai-metrics|fu-metrics-suite-writes-real-overview|docs/ai/overview.html docs/ai/overview-data.json"
  "aai-state|fu-state-suite-writes-real-index|docs/INDEX.md"
  "aai-token-capture|fu-token-capture-writes-overview|docs/ai/overview.html docs/ai/overview-data.json"
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
TRIPWIRE_WATCH_PATHS=()
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

  if [[ "$VERBOSE" == "true" ]]; then
    bash "$test_file" 2>&1 | tee "$log_file" || exit_code=$?
  else
    bash "$test_file" &> "$log_file" || exit_code=$?
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
    local tw_shown
    while IFS= read -r tw_shown; do
      if [[ -n "$tw_shown" ]]; then
        echo "AAI-TRIPWIRE   changed: $tw_shown"
      fi
    done <<< "$tw_dirty_paths"
    if [[ -n "$tw_hash_paths" ]]; then
      local tw_ahp
      while IFS= read -r tw_ahp; do
        if [[ -n "$tw_ahp" ]]; then
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

  # Record in project metrics
  if [[ -d "$PROJECT_ROOT/docs/ai/tests" ]] || mkdir -p "$PROJECT_ROOT/docs/ai/tests" 2>/dev/null; then
    echo "{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"type\":\"skill_test\",\"run_id\":\"$RUN_ID\",\"total\":$TOTAL_TESTS,\"passed\":$PASSED_TESTS,\"failed\":$FAILED_TESTS,\"skipped\":$SKIPPED_TESTS}" >> "$PROJECT_ROOT/docs/ai/tests/test-runs.jsonl"
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
