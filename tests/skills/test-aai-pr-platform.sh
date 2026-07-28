#!/usr/bin/env bash
#
# Test: platform-portable PR ceremony probe (CHANGE-DRAFT-platform-portable-pr /
# SPEC-DRAFT-spec-platform-portable-pr).
# Verifies .aai/scripts/pr-platform.mjs — a deterministic, READ-ONLY CLI that
# classifies the `origin` remote into github | azure | unknown | none — plus
# grep-contract pins on .aai/SKILL_PR.prompt.md's platform-branched ceremony
# (PLATFORM GATE, az command names, reviewer-fallback contract, GENERIC MODE
# loud line).
#
# The PROBE script under test is overridable so the RED phase can prove the
# classification tests genuinely discriminate (before the script existed,
# every invocation failed ENOENT):
#   AAI_PR_PLATFORM   probe under test (default .aai/scripts/pr-platform.mjs)
#
# Usage:
#   bash tests/skills/test-aai-pr-platform.sh            # run all (TEST-001..018)
#   bash tests/skills/test-aai-pr-platform.sh 001 010     # run only selected tests
#
# Exit codes:
#   0  - All selected tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-pr-platform"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PROBE="${AAI_PR_PLATFORM:-$PROJECT_ROOT/.aai/scripts/pr-platform.mjs}"
SKILL_PR_DOC="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"

TMP_ROOT=""
FAILED=0

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; FAILED=1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

check_deps() {
  log_info "Checking dependencies..."
  command -v bash >/dev/null 2>&1 || log_skip "bash not found"
  command -v git  >/dev/null 2>&1 || log_skip "git not found"
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v mktemp >/dev/null 2>&1 || log_skip "mktemp not found"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-pr-platform-test.XXXXXX")"
  log_pass "Dependencies checked"
}

# Run the probe with --remote-url <url> [extra args...]; capture stdout to
# OUT, stderr to ERR, real exit code to RC.
OUT=""; ERR=""; RC=0
run_probe() {  # run_probe <url> [extra-args...]
  local url="$1"; shift
  local errf
  errf="$(mktemp "$TMP_ROOT/err.XXXXXX")"
  OUT="$(node "$PROBE" --remote-url "$url" "$@" 2>"$errf")"; RC=$?
  ERR="$(cat "$errf")"
  rm -f "$errf"
}

# assert_platform <label> <url> <expected-platform>
assert_platform() {
  local label="$1" url="$2" expected="$3"
  run_probe "$url"
  if [[ "$RC" -ne 0 ]]; then
    log_fail "$label: probe exited $RC (want 0) for url=$url; stderr=$ERR"
    return
  fi
  case "$OUT" in
    "PLATFORM $expected remote="*)
      log_pass "$label: $url -> PLATFORM $expected" ;;
    *)
      log_fail "$label: $url -> got '$OUT' (want PLATFORM $expected remote=...)" ;;
  esac
}

# --- TEST-001/002/003 — GitHub host forms (Spec-AC-01) ------------------------
test_001_github_https() {
  assert_platform "TEST-001" "https://github.com/owner/repo.git" "github"
}
test_002_github_ssh_scp() {
  assert_platform "TEST-002" "git@github.com:owner/repo.git" "github"
}
test_003_github_ssh_url() {
  assert_platform "TEST-003" "ssh://git@github.com/owner/repo.git" "github"
}

# --- TEST-004/005 — Azure DevOps current hosts (Spec-AC-01) ------------------
test_004_azure_https() {
  assert_platform "TEST-004" "https://dev.azure.com/org/project/_git/repo" "azure"
}
test_005_azure_ssh() {
  assert_platform "TEST-005" "git@ssh.dev.azure.com:v3/org/project/repo" "azure"
}

# --- TEST-006/007 — Azure DevOps legacy visualstudio.com hosts (Spec-AC-01) --
test_006_azure_visualstudio_https() {
  assert_platform "TEST-006" "https://org.visualstudio.com/project/_git/repo" "azure"
}
test_007_azure_visualstudio_ssh() {
  assert_platform "TEST-007" "org@vs-ssh.visualstudio.com:v3/org/project/repo" "azure"
}

# --- TEST-008/009 — never guesses: other hosts are unknown (Spec-AC-01) -----
test_008_gitlab_unknown() {
  assert_platform "TEST-008" "https://gitlab.com/owner/repo.git" "unknown"
}
test_009_bitbucket_unknown() {
  assert_platform "TEST-009" "git@bitbucket.org:owner/repo.git" "unknown"
}

# --- TEST-010 — no remote at all -> none, real git fixture (Spec-AC-01) -----
test_010_no_remote_real_fixture() {
  log_info "TEST-010: real git repo with no 'origin' remote -> PLATFORM none, exit 0..."
  local repo
  repo="$(mktemp -d "$TMP_ROOT/t010.XXXXXX")"
  git init -b main "$repo" >/dev/null 2>&1
  ( cd "$repo" && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit \
      --allow-empty -m init >/dev/null 2>&1 )
  local out rc
  out="$( cd "$repo" && node "$PROBE" 2>/dev/null )"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_fail "TEST-010: exit $rc (want 0)"
  elif [[ "$out" != "PLATFORM none" ]]; then
    log_fail "TEST-010: got '$out' (want 'PLATFORM none')"
  else
    log_pass "TEST-010: no-remote fixture -> PLATFORM none, exit 0"
  fi
}

# --- TEST-011 — --json shape: exact key set, both a classified and a none case
test_011_json_shape() {
  log_info "TEST-011: --json emits exactly platform/remote — remote SANITIZED, never the raw url (credential-leak review pin)..."
  local ok=1 keys
  keys=$(node "$PROBE" --remote-url "https://github.com/o/r.git" --json 2>/dev/null | node -e '
    let d = ""; process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => { console.log(Object.keys(JSON.parse(d)).sort().join(",")); });
  ')
  if [[ "$keys" != "platform,remote" ]]; then
    log_info "TEST-011: classified-case keys='$keys' (want platform,remote)"
    ok=0
  fi
  # credential masking in --json (PR #185 review): raw token must never appear
  if node "$PROBE" --remote-url "https://ghost:hunter2@github.com/o/r.git" --json 2>/dev/null | grep -q "hunter2"; then
    log_info "TEST-011: --json leaked embedded credentials"
    ok=0
  fi
  local none_platform
  none_platform=$(node "$PROBE" --remote-url "" --json 2>/dev/null | node -e '
    let d = ""; process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => { console.log(JSON.parse(d).platform); });
  ')
  if [[ "$none_platform" != "none" ]]; then
    log_info "TEST-011: none-case platform='$none_platform' (want none)"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-011 --json shape (classified + none)" || log_fail "TEST-011 --json shape"
}

# --- TEST-012 — exit codes: every classification is 0; unknown flag is 2 and
# writes NOTHING to stdout (house rule: read-only CLI, usage error prints only
# to stderr) -------------------------------------------------------------------
test_012_exit_codes() {
  log_info "TEST-012: classification exits 0; unknown flag exits 2, empty stdout..."
  local ok=1
  local url
  for url in \
    "https://github.com/o/r.git" \
    "https://dev.azure.com/org/project/_git/repo" \
    "https://gitlab.com/o/r.git" \
    ""; do
    run_probe "$url"
    if [[ "$RC" -ne 0 ]]; then
      log_info "TEST-012: url='$url' exited $RC (want 0)"
      ok=0
    fi
  done
  local out rc
  out="$(node "$PROBE" --bogus-flag 2>/dev/null)"; rc=$?
  if [[ "$rc" -ne 2 ]]; then
    log_info "TEST-012: unknown flag exited $rc (want 2)"
    ok=0
  fi
  if [[ -n "$out" ]]; then
    log_info "TEST-012: unknown flag printed to stdout: '$out' (want empty — nothing written)"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-012 exit codes (0 classified, 2 unknown-flag, empty stdout)" \
    || log_fail "TEST-012 exit codes"
}

# --- TEST-013 — cwd-independence: real git fixture with origin set, probed
# from a nested subdirectory AND from an unrelated directory via --remote-url
test_013_cwd_independence() {
  log_info "TEST-013: probe works from a nested subdirectory of the repo (Spec-AC-01)..."
  local repo
  repo="$(mktemp -d "$TMP_ROOT/t013.XXXXXX")"
  git init -b main "$repo" >/dev/null 2>&1
  ( cd "$repo" && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit \
      --allow-empty -m init >/dev/null 2>&1 )
  ( cd "$repo" && git remote add origin "https://github.com/owner/repo.git" ) >/dev/null 2>&1
  mkdir -p "$repo/nested/deeper"
  local out rc
  out="$( cd "$repo/nested/deeper" && node "$PROBE" 2>/dev/null )"; rc=$?
  if [[ "$rc" -eq 0 && "$out" == "PLATFORM github remote="* ]]; then
    log_pass "TEST-013: nested subdirectory resolves the same origin (github)"
  else
    log_fail "TEST-013: from nested subdir got rc=$rc out='$out' (want PLATFORM github ...)"
  fi
}

# --- TEST-014 — HTTPS basic-auth credentials are stripped from the sanitized
# remote (never echo a secret back to a PR ceremony log) ---------------------
test_014_credential_sanitization() {
  log_info "TEST-014: embedded https user:pass credentials are masked in the printed remote..."
  run_probe "https://ghost:hunter2@github.com/owner/repo.git"
  if [[ "$RC" -ne 0 ]]; then
    log_fail "TEST-014: probe exited $RC (want 0)"
  elif [[ "$OUT" == *"hunter2"* || "$OUT" == *"ghost"* ]]; then
    log_fail "TEST-014: credentials leaked into output: '$OUT'"
  elif [[ "$OUT" != "PLATFORM github remote="* ]]; then
    log_fail "TEST-014: unexpected output '$OUT'"
  else
    log_pass "TEST-014: credentials masked, classification unaffected (github)"
  fi
}

# --- TEST-015 — grep-contract: SKILL_PR names a PLATFORM GATE that runs the
# probe before branching (Spec-AC-02) -----------------------------------------
test_015_skill_pr_platform_gate() {
  log_info "TEST-015: SKILL_PR.prompt.md names a PLATFORM GATE running pr-platform.mjs..."
  local ok=1
  [[ -f "$SKILL_PR_DOC" ]] || { log_fail "TEST-015: $SKILL_PR_DOC missing"; return; }
  grep -qi "PLATFORM GATE" "$SKILL_PR_DOC" || { log_info "TEST-015: no 'PLATFORM GATE' heading"; ok=0; }
  grep -qF ".aai/scripts/pr-platform.mjs" "$SKILL_PR_DOC" || { log_info "TEST-015: probe script not named"; ok=0; }
  grep -qi "unknown\b.*GENERIC MODE\|GENERIC MODE" "$SKILL_PR_DOC" || { log_info "TEST-015: no GENERIC MODE routing"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-015 SKILL_PR PLATFORM GATE present" || log_fail "TEST-015 SKILL_PR PLATFORM GATE present"
}

# --- TEST-016 — grep-contract: az command names documented (Spec-AC-02) -----
test_016_skill_pr_az_commands() {
  log_info "TEST-016: SKILL_PR.prompt.md names the az repos pr command set..."
  local ok=1
  [[ -f "$SKILL_PR_DOC" ]] || { log_fail "TEST-016: $SKILL_PR_DOC missing"; return; }
  local cmd
  for cmd in "az repos pr create" "az repos pr reviewer add" "pullRequestThreads" "az devops invoke"; do
    grep -qF "$cmd" "$SKILL_PR_DOC" || { log_info "TEST-016: '$cmd' not found"; ok=0; }
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-016 az command set documented" || log_fail "TEST-016 az command set documented"
}

# --- TEST-017 — grep-contract: 5d reviewer-fallback contract pinned
# (Spec-AC-03 / Additional operator requirements) -----------------------------
test_017_skill_pr_fallback_contract() {
  log_info "TEST-017: SKILL_PR.prompt.md 5d fallback contract (no-external-reviewer sweep)..."
  local ok=1
  [[ -f "$SKILL_PR_DOC" ]] || { log_fail "TEST-017: $SKILL_PR_DOC missing"; return; }
  grep -qF "REQUIRED before any merge-readiness claim" "$SKILL_PR_DOC" \
    || { log_info "TEST-017: REQUIRED-before-merge-readiness sentence missing"; ok=0; }
  grep -qF "platform != github" "$SKILL_PR_DOC" \
    || { log_info "TEST-017: no-external-reviewer detection clause missing"; ok=0; }
  grep -qF "internal review substituted for absent bot layer" "$SKILL_PR_DOC" \
    || { log_info "TEST-017: PR-description recording sentence missing"; ok=0; }
  grep -qF "closing reply citing the fixing commit" "$SKILL_PR_DOC" \
    || { log_info "TEST-017: published-as-PR-thread closing-reply clause missing"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-017 5d reviewer-fallback contract pinned" || log_fail "TEST-017 5d reviewer-fallback contract pinned"
}

# --- TEST-018 — grep-contract: GENERIC MODE loud line, verbatim (Additional
# operator requirements) -------------------------------------------------------
test_018_skill_pr_generic_mode_loud_line() {
  log_info "TEST-018: SKILL_PR.prompt.md GENERIC MODE ends with the loud line..."
  local ok=1
  [[ -f "$SKILL_PR_DOC" ]] || { log_fail "TEST-018: $SKILL_PR_DOC missing"; return; }
  grep -qF "platform PR API unavailable" "$SKILL_PR_DOC" \
    || { log_info "TEST-018: loud line missing"; ok=0; }
  grep -qF "merge is yours" "$SKILL_PR_DOC" \
    || { log_info "TEST-018: loud line missing 'merge is yours'"; ok=0; }
  grep -qF "docs/ai/reports/VALIDATION-" "$SKILL_PR_DOC" \
    || { log_info "TEST-018: GENERIC MODE report path not named"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-018 GENERIC MODE loud line pinned" || log_fail "TEST-018 GENERIC MODE loud line pinned"
}

ALL_TESTS=(
  test_001_github_https
  test_002_github_ssh_scp
  test_003_github_ssh_url
  test_004_azure_https
  test_005_azure_ssh
  test_006_azure_visualstudio_https
  test_007_azure_visualstudio_ssh
  test_008_gitlab_unknown
  test_009_bitbucket_unknown
  test_010_no_remote_real_fixture
  test_011_json_shape
  test_012_exit_codes
  test_013_cwd_independence
  test_014_credential_sanitization
  test_015_skill_pr_platform_gate
  test_016_skill_pr_az_commands
  test_017_skill_pr_fallback_contract
  test_018_skill_pr_generic_mode_loud_line
)

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps

  if [[ $# -gt 0 ]]; then
    local sel fn
    for sel in "$@"; do
      fn=""
      for cand in "${ALL_TESTS[@]}"; do
        [[ "$cand" == *"_${sel}_"* || "$cand" == "test_${sel}"* ]] && fn="$cand"
      done
      if [[ -n "$fn" ]]; then
        "$fn"
      else
        log_fail "no test matches selector '$sel'"
      fi
    done
  else
    local fn
    for fn in "${ALL_TESTS[@]}"; do
      "$fn"
    done
  fi

  echo ""
  if [[ $FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
  else
    echo "Some tests FAILED."
    exit 1
  fi
}

main "$@"
