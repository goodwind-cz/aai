#!/usr/bin/env bash
#
# Test: platform-portable PR ceremony probe (CHANGE-0085-platform-portable-pr /
# SPEC-0103-spec-platform-portable-pr).
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
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/pipe-safe.sh"
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
  log_info "TEST-011: --json emits exactly platform/remote/reviewer_bots — remote SANITIZED, never the raw url (credential-leak review pin)..."
  local ok=1 keys
  keys=$(node "$PROBE" --remote-url "https://github.com/o/r.git" --json 2>/dev/null | node -e '
    let d = ""; process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => { console.log(Object.keys(JSON.parse(d)).sort().join(",")); });
  ')
  if [[ "$keys" != "platform,remote,reviewer_bots" ]]; then
    log_info "TEST-011: classified-case keys='$keys' (want platform,remote,reviewer_bots)"
    ok=0
  fi
  # credential masking in --json (PR #185 review): raw token must never appear
  if node "$PROBE" --remote-url "https://ghost:hunter2@github.com/o/r.git" --json 2>/dev/null | qgrep -q "hunter2"; then
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

# --- TEST-019 — reviewer_bots knob classification (R1 GitHub-no-bots hardening,
# CHANGE-DRAFT-github-no-bots-hardening) — deterministic tri-state read of the
# repo-local docs/ai/pr-config.yaml `reviewer_bots:` knob via --pr-config
# override: absent file/key -> none (assume-none, safest default -> internal
# review, never wait for bots that may never arrive); `expected` -> expected;
# `none` -> none; any other value -> unknown (+ stderr warn, behaves as none) --
test_019_reviewer_bots_knob() {
  log_info "TEST-019: reviewer_bots knob none(default)/expected/none/unknown..."
  local ok=1
  local ghurl="https://github.com/owner/repo.git"
  # absent config file -> none (assume-none)
  local missing="$TMP_ROOT/pr-config-absent.yaml"  # never created
  run_probe "$ghurl" --pr-config "$missing"
  if [[ "$OUT" != *"reviewer_bots=none"* ]]; then
    log_info "TEST-019: absent config got '$OUT' (want reviewer_bots=none)"; ok=0
  fi
  # explicit expected
  local expcfg="$TMP_ROOT/pr-config-expected.yaml"
  printf 'reviewer_bots: expected\n' >"$expcfg"
  run_probe "$ghurl" --pr-config "$expcfg"
  if [[ "$OUT" != *"reviewer_bots=expected"* ]]; then
    log_info "TEST-019: expected config got '$OUT' (want reviewer_bots=expected)"; ok=0
  fi
  # explicit none
  local nonecfg="$TMP_ROOT/pr-config-none.yaml"
  printf 'reviewer_bots: none\n' >"$nonecfg"
  run_probe "$ghurl" --pr-config "$nonecfg"
  if [[ "$OUT" != *"reviewer_bots=none"* ]]; then
    log_info "TEST-019: none config got '$OUT' (want reviewer_bots=none)"; ok=0
  fi
  # invalid value -> unknown + stderr warn, exit still 0 (read-only, fail-open)
  local badcfg="$TMP_ROOT/pr-config-bad.yaml"
  printf 'reviewer_bots: yesplease\n' >"$badcfg"
  run_probe "$ghurl" --pr-config "$badcfg"
  if [[ "$RC" -ne 0 ]]; then
    log_info "TEST-019: invalid value exited $RC (want 0, fail-open)"; ok=0
  fi
  if [[ "$OUT" != *"reviewer_bots=unknown"* ]]; then
    log_info "TEST-019: invalid value got '$OUT' (want reviewer_bots=unknown)"; ok=0
  fi
  if [[ -z "$ERR" ]]; then
    log_info "TEST-019: invalid value printed no stderr warning (want a fail-open notice)"; ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-019 reviewer_bots knob (none-default/expected/none/unknown)" \
    || log_fail "TEST-019 reviewer_bots knob"
}

# --- TEST-020 — text output carries reviewer_bots for a remote; the bare
# no-remote `PLATFORM none` line stays bare (GENERIC MODE, no PR ceremony) -----
test_020_reviewer_bots_text_shape() {
  log_info "TEST-020: text line appends reviewer_bots= for a remote, bare PLATFORM none unchanged..."
  local ok=1
  local expcfg="$TMP_ROOT/pr-config-t020.yaml"
  printf 'reviewer_bots: expected\n' >"$expcfg"
  run_probe "https://github.com/o/r.git" --pr-config "$expcfg"
  if [[ "$OUT" != "PLATFORM github remote="*" reviewer_bots=expected" ]]; then
    log_info "TEST-020: remote line got '$OUT' (want 'PLATFORM github remote=... reviewer_bots=expected')"; ok=0
  fi
  run_probe "" --pr-config "$expcfg"
  if [[ "$OUT" != "PLATFORM none" ]]; then
    log_info "TEST-020: no-remote line got '$OUT' (want bare 'PLATFORM none')"; ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-020 reviewer_bots text shape (appended on remote, bare none)" \
    || log_fail "TEST-020 reviewer_bots text shape"
}

# --- TEST-021 — --json carries the reviewer_bots value -----------------------
test_021_reviewer_bots_json() {
  log_info "TEST-021: --json reviewer_bots value tracks the knob..."
  local ok=1 rb
  local nonecfg="$TMP_ROOT/pr-config-t021.yaml"
  printf 'reviewer_bots: none\n' >"$nonecfg"
  rb=$(node "$PROBE" --remote-url "https://github.com/o/r.git" --pr-config "$nonecfg" --json 2>/dev/null | node -e '
    let d = ""; process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => { console.log(JSON.parse(d).reviewer_bots); });
  ')
  if [[ "$rb" != "none" ]]; then
    log_info "TEST-021: --json reviewer_bots='$rb' (want none)"; ok=0
  fi
  # Trailing tokens must NOT silently enable the bot-only path: the value is
  # the entire rest of the line and must EXACTLY equal a closed-set token
  # ("expected extra" -> unknown + warning, bot-review P2 hardening).
  local trailcfg="$TMP_ROOT/pr-config-t021-trail.yaml"
  printf 'reviewer_bots: expected extra\n' >"$trailcfg"
  rb=$(node "$PROBE" --remote-url "https://github.com/o/r.git" --pr-config "$trailcfg" --json 2>/dev/null | node -e '
    let d = ""; process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => { console.log(JSON.parse(d).reviewer_bots); });
  ')
  if [[ "$rb" != "unknown" ]]; then
    log_info "TEST-021: trailing-token value gave reviewer_bots='$rb' (want unknown)"; ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-021 --json reviewer_bots value (+trailing-token -> unknown)" || log_fail "TEST-021 --json reviewer_bots value"
}

# --- TEST-022 — grep-contract: SKILL_PR 5d GitHub-no-bots hardening
# (CHANGE-DRAFT-github-no-bots-hardening) — the empty-sweep shortcut is legal
# ONLY when reviewer_bots == expected (a github repo with reviewer_bots !=
# expected takes the internal-review fallback), plus the bounded-wait rule so
# the sweep never waits forever for comments that never arrive ----------------
test_022_skill_pr_no_bots_hardening() {
  log_info "TEST-022: SKILL_PR 5d reviewer_bots-gated shortcut + bounded-wait rule..."
  local ok=1
  [[ -f "$SKILL_PR_DOC" ]] || { log_fail "TEST-022: $SKILL_PR_DOC missing"; return; }
  grep -qF "reviewer_bots=" "$SKILL_PR_DOC" \
    || { log_info "TEST-022: probe reviewer_bots= field not referenced in 5d"; ok=0; }
  grep -qF "reviewer_bots == expected" "$SKILL_PR_DOC" \
    || { log_info "TEST-022: empty-sweep shortcut not gated on reviewer_bots == expected"; ok=0; }
  grep -qF "reviewer_bots != expected" "$SKILL_PR_DOC" \
    || { log_info "TEST-022: github-without-bots fallback trigger (reviewer_bots != expected) missing"; ok=0; }
  grep -qiF "bounded wait" "$SKILL_PR_DOC" \
    || { log_info "TEST-022: bounded-wait rule missing"; ok=0; }
  grep -qiF "never wait" "$SKILL_PR_DOC" \
    || { log_info "TEST-022: never-wait-forever guarantee missing"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-022 SKILL_PR 5d GitHub-no-bots hardening pinned" \
    || log_fail "TEST-022 SKILL_PR 5d GitHub-no-bots hardening"
}

# --- TEST-569 (Spec-AC-30): shared-page push check names an overlapping ----
# open PR and refuses; a non-overlapping PR is silent (deny-by-default gh
# stub: it only answers the EXACT expected invocation, per LEARNED
# fu-learned-deny-by-default-mocks — anything else is a test bug, not a
# tolerated call).
build_gh_stub_pr_list() {  # $1=bin path  $2=json body for `pr list --state open --json number,files`
  local bin="$1" body="$2"
  cat > "$bin" <<STUBEOF
#!/usr/bin/env bash
if [[ "\$1" == "pr" && "\$2" == "list" && "\$3" == "--state" && "\$4" == "open" && "\$5" == "--json" && "\$6" == "number,files" && \$# -eq 6 ]]; then
  cat <<'JSON'
$body
JSON
  exit 0
fi
echo "gh stub: unexpected invocation: \$*" >&2
exit 99
STUBEOF
  chmod +x "$bin"
}

test_569_shared_page_push_names_open_prs() {
  log_info "TEST-569: an open PR touching docs/INDEX.md makes the pre-push check name it and refuse; no overlap is silent (Spec-AC-30)..."
  local bin="$TMP_ROOT/gh-t569"
  build_gh_stub_pr_list "$bin" '[{"number":42,"files":[{"path":"docs/INDEX.md"},{"path":"src/foo.js"}]}]'
  local out rc
  out="$(node "$PROBE" --check-shared-page-conflicts --remote-url "https://github.com/o/r.git" --gh-bin "$bin" 2>&1)"; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    log_fail "TEST-569: an overlapping open PR must refuse (exit non-zero), got 0: $out"
  elif [[ "$out" != *"42"* || "$out" != *"docs/INDEX.md"* ]]; then
    log_fail "TEST-569: the refusal must name the PR number and the overlapping path: $out"
  else
    log_pass "TEST-569: overlapping open PR named and refused"
  fi

  build_gh_stub_pr_list "$bin" '[{"number":7,"files":[{"path":"src/bar.js"}]}]'
  out="$(node "$PROBE" --check-shared-page-conflicts --remote-url "https://github.com/o/r.git" --gh-bin "$bin" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_fail "TEST-569: a non-overlapping open PR must exit 0, got $rc: $out"
  elif [[ "$out" == *"CONFLICT"* ]]; then
    log_fail "TEST-569: a non-overlapping open PR must be silent about a conflict, got: $out"
  else
    log_pass "TEST-569: non-overlapping open PR is silent (CLEAR)"
  fi

  # non-github platform: never blocks, names the reason (degrade-with-NOTE)
  out="$(node "$PROBE" --check-shared-page-conflicts --remote-url "https://gitlab.com/o/r.git" --gh-bin "$bin" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_fail "TEST-569: a non-github platform must never block, got rc=$rc: $out"
  elif [[ "$out" != *"SKIP"* ]]; then
    log_fail "TEST-569: a non-github platform must name the skip: $out"
  else
    log_pass "TEST-569: non-github platform skips, never blocks"
  fi
}

# --- TEST-580 (Spec-AC-30): SHARED_GENERATED_PAGES names a real path for -----
# EVERY page it lists, one arm per page — B4's wrong-path finding (a hand-
# maintained 'docs/overview.html' that no such file answers to, silently
# never matched by sharedPageConflicts()'s exact Set.has()) is pinned per
# entry, not just for docs/INDEX.md (TEST-569's only fixture path).
#
# T-NEW-1 (validation-round2): the ORIGINAL version of this test looped over
# the very set it was testing (`pages`, read back from SHARED_GENERATED_PAGES
# itself), so deleting a member kept it green — one conflict arm fewer, no
# assertion left to notice. Round-2's fix replaced the loop with a literal,
# hand-written twin list inside THIS file.
#
# B1-R4 (validation-round4, Amendment 20): the hand-written twin was itself
# the hole. Round 3 (Amendment 19) corrected both `SHARED_GENERATED_PAGES`
# and the twin list here to name SEVEN pages, in the SAME edit — so when both
# omitted `docs/ai/factory-report-data.json` (generate-factory-report.mjs
# writes it unconditionally, one line before the HTML the twin DID name),
# nothing could tell: an equality check between two hand-written lists that
# drift TOGETHER cannot see a shared omission (validation-round4 section 5,
# arm E5). This is the third time a hand count of this set was wrong.
#
# Fixed structurally, not by counting again: the twin list is GONE. This test
# now RUNS the regen tail's five generators — exactly as close-work-item.mjs
# invokes them (`node <generator>`, no arguments, its own default output
# path) — in an isolated scratch clone, and MEASURES which tracked paths they
# actually wrote (see build below). `SHARED_GENERATED_PAGES` is asserted
# equal to that MEASURED set, never to a second hand-written copy of it. A
# page a generator writes can no longer go uncounted just because a human
# forgot it twice in the same edit — the measurement doesn't require anyone
# to remember it once.
test_580_shared_page_set_covers_every_generated_page() {
  log_info "TEST-580: SHARED_GENERATED_PAGES matches disk and equals the pages the close ceremony's regen tail is MEASURED to actually write, one conflict arm per page (Spec-AC-30)..."
  local bin="$TMP_ROOT/gh-t580" page rc out ok=1

  # --- Build an isolated scratch clone -----------------------------------
  # Same recipe mutation-run.mjs's buildIsolatedClone() uses (D4): clone
  # HEAD, then reproduce the developer's own UNCOMMITTED tracked edits via
  # `git diff HEAD | git apply`, so a mid-ride edit to lib/docs-model.mjs or
  # to a generator is measured before it is ever committed — without a
  # generator run ever writing a regenerated page into the real working
  # tree (running these generators dirties tracked pages; this suite must
  # leave the tree clean).
  local clone_dir
  clone_dir="$(mktemp -d "$TMP_ROOT/regen-clone.XXXXXX")" \
    || { log_fail "TEST-580: could not create the scratch clone directory"; return; }
  git clone --local --no-hardlinks --quiet "$PROJECT_ROOT" "$clone_dir" \
    || { log_fail "TEST-580: could not build the scratch clone"; return; }
  local base_commit
  base_commit="$(cd "$PROJECT_ROOT" && git rev-parse HEAD)"
  (cd "$clone_dir" && git checkout --quiet "$base_commit") \
    || { log_fail "TEST-580: could not checkout $base_commit in the scratch clone"; return; }
  local wt_diff
  wt_diff="$(cd "$PROJECT_ROOT" && git diff HEAD)"
  if [[ -n "$wt_diff" ]]; then
    printf '%s\n' "$wt_diff" | (cd "$clone_dir" && git apply) \
      || { log_fail "TEST-580: could not reproduce uncommitted tracked edits in the scratch clone"; return; }
  fi

  # --- Run the regen tail's five generators, exactly as invoked -----------
  # close-work-item.mjs's regen tail: regenerateIndex() (also run inside
  # selfVerify() and on both rollback paths) plus the four
  # regenerate*BestEffort() calls after the success log line. Every one is
  # `execFileSync('node', [<generator>], { cwd: ROOT })` — no arguments — so
  # exercising them with no arguments here is what actually runs in
  # production, not a --output flag this test would have to keep in sync by
  # hand.
  local -a REGEN_TAIL_GENERATORS=(
    "generate-docs-index.mjs"
    "generate-overview.mjs"
    "generate-userguide-rollup.mjs"
    "generate-docs-hub.mjs"
    "generate-factory-report.mjs"
  )
  # A marker file's mtime, taken AFTER the clone is fully built and BEFORE
  # any generator runs, turns "did this generator write this path" into a
  # content-INDEPENDENT signal. `git status --porcelain` alone is not enough:
  # measured directly, a generator run against unchanged source data is
  # idempotent BYTE-FOR-BYTE for some pages (docs/USER_GUIDE.md and
  # docs/SKILL_CATALOG.html both regenerate identical bytes today), and such
  # a page shows NOTHING in `git status --porcelain` even though
  # fs.writeFileSync() genuinely opened, truncated and rewrote it — porcelain
  # diffs content, not writes. `sleep 1` guards the comparison against 1s
  # mtime resolution on some filesystems (same guard test-aai-live-status.sh
  # already uses for the same reason).
  local marker="$clone_dir/.regen-marker"
  touch "$marker" || { log_fail "TEST-580: could not create the mtime marker"; return; }
  sleep 1
  local gen gen_out gen_rc
  for gen in "${REGEN_TAIL_GENERATORS[@]}"; do
    gen_out="$(cd "$clone_dir" && node ".aai/scripts/$gen" 2>&1)"; gen_rc=$?
    [[ $gen_rc -eq 0 ]] \
      || { log_fail "TEST-580: $gen must exit 0 in the scratch clone, got $gen_rc: $gen_out"; rm -rf "$clone_dir"; return; }
  done

  # --- Derive the measured set --------------------------------------------
  # `git ls-files` in the clone is a TRACKED-paths-only list, so an untracked
  # near-miss (generate-docs-index.mjs's docs/INDEX.violations.md, written
  # only on a non-terminal near-miss) or a gitignored artefact
  # (docs/INDEX.audit.md) can never reach `derived` — no separate exclusion
  # code is needed for either class because neither is a member of the list
  # this loop reads from. A path is MEASURED written iff it is tracked AND
  # its mtime moved past the marker.
  local -a derived=()
  local tf
  while IFS= read -r tf; do
    [[ -n "$tf" ]] || continue
    [[ -f "$clone_dir/$tf" && "$clone_dir/$tf" -nt "$marker" ]] || continue
    derived+=("$tf")
  done < <(cd "$clone_dir" && git ls-files)

  if [[ ${#derived[@]} -eq 0 ]]; then
    log_fail "TEST-580: the regen tail wrote nothing the derivation could measure (scratch-clone defect, not a real-repo finding)"
    rm -rf "$clone_dir"
    return
  fi

  # Explicit, justified exclusions — belt-and-suspenders over the structural
  # ones above. Neither class can reach `derived` TODAY: none of the five
  # generators above appends to a ledger or writes under these directories.
  # Named here anyway (not left as an implicit non-match) because a FUTURE
  # generator edit that started doing either would be a DIFFERENT conflict
  # class from "a wholesale-rewritten shared page" and must not silently
  # join this set:
  #   - append-only ledgers: appended to by close-work-item.mjs's own
  #     emitEvent()/applyDocMutation(), never rewritten wholesale — a PR
  #     touching one merges by history, it does not clobber it outright.
  #   - the ride's own documents (docs/specs/**, docs/ai/briefs/**,
  #     docs/issues/**): written by this ride's own tooling (spec-amend,
  #     intake), ride-specific by construction, never shared across PRs the
  #     way a regenerated catalog page is.
  local -a EXCLUDED_LEDGERS=(
    "docs/ai/EVENTS.jsonl"
    "docs/ai/METRICS.jsonl"
    "docs/ai/decisions.jsonl"
    "docs/ai/tests/test-runs.jsonl"
  )
  local -a filtered=()
  local excluded_hit lg
  for tf in "${derived[@]}"; do
    excluded_hit=0
    for lg in "${EXCLUDED_LEDGERS[@]}"; do
      [[ "$tf" == "$lg" ]] && { excluded_hit=1; break; }
    done
    case "$tf" in
      docs/specs/*|docs/ai/briefs/*|docs/issues/*) excluded_hit=1 ;;
    esac
    [[ $excluded_hit -eq 0 ]] && filtered+=("$tf")
  done
  derived=("${filtered[@]:-}")

  local pages
  pages="$(node -e '
    import("'"$PROJECT_ROOT"'/.aai/scripts/lib/docs-model.mjs").then(m => {
      console.log([...m.SHARED_GENERATED_PAGES].join("\n"));
    });
  ')"
  [[ -n "$pages" ]] || { log_fail "TEST-580: SHARED_GENERATED_PAGES is empty or unreadable"; rm -rf "$clone_dir"; return; }
  grep -qF "docs/overview.html" <<<"$pages" \
    && { log_fail "TEST-580: SHARED_GENERATED_PAGES still names the non-existent docs/overview.html"; ok=0; }

  # Every page the scratch clone MEASURED written must be a member of the
  # set — drift in the "set lost a real page" direction reddens HERE,
  # independent of the conflict-detection loop below.
  for page in "${derived[@]:-}"; do
    grep -qF "$page" <<<"$pages" \
      || { log_info "TEST-580: SHARED_GENERATED_PAGES is missing '$page' — the scratch clone measured this page WRITTEN by the regen tail"; ok=0; }
  done

  # Every path the set DOES name must exist on disk (stat it) — drift in the
  # OTHER direction (a stale or renamed entry) reddens too.
  while IFS= read -r page; do
    [[ -n "$page" ]] || continue
    [[ -f "$PROJECT_ROOT/$page" ]] \
      || { log_info "TEST-580: SHARED_GENERATED_PAGES names '$page', which does not exist in the repo"; ok=0; }
  done <<<"$pages"

  # D3 (validation-round3): containment alone only catches a MISSING member;
  # an EXTRA member that exists on disk but is never actually regenerated
  # (e.g. docs/TECHNOLOGY.md) would pass the stat loop and every conflict arm
  # silently. Assert EXACT equality between the set and the MEASURED list —
  # an extra entry reddens as loudly as a missing one, and — the fix for
  # B1-R4 specifically — a page the set is missing reddens even when NO
  # hand-written twin list was ever updated to notice it either.
  local sorted_pages sorted_derived
  sorted_pages="$(sort <<<"$pages")"
  sorted_derived="$(printf '%s\n' "${derived[@]:-}" | sort)"
  [[ "$sorted_pages" == "$sorted_derived" ]] \
    || { log_info "TEST-580: SHARED_GENERATED_PAGES must equal the pages MEASURED written by the regen tail EXACTLY (declared: $(tr '\n' ' ' <<<"$sorted_pages") | measured: $(tr '\n' ' ' <<<"$sorted_derived"))"; ok=0; }

  # One conflict-detection arm per page the scratch clone MEASURED written —
  # the measured list, not the set under test, so a page dropped FROM the
  # set still gets its own arm and reddens as "not individually caught",
  # rather than simply producing one arm fewer.
  for page in "${derived[@]:-}"; do
    build_gh_stub_pr_list "$bin" "[{\"number\":580,\"files\":[{\"path\":\"$page\"}]}]"
    out="$(node "$PROBE" --check-shared-page-conflicts --remote-url "https://github.com/o/r.git" --gh-bin "$bin" 2>&1)"; rc=$?
    if [[ "$rc" -eq 0 ]]; then
      log_info "TEST-580: a PR touching '$page' must refuse (exit non-zero), got 0: $out"; ok=0
    elif [[ "$out" != *"$page"* ]]; then
      log_info "TEST-580: the refusal for '$page' must name that path: $out"; ok=0
    fi
  done

  rm -rf "$clone_dir"

  [[ $ok -eq 1 ]] && log_pass "TEST-580: SHARED_GENERATED_PAGES matches disk and equals the pages the regen tail's five generators are MEASURED to actually write, each individually caught as a conflict" \
    || log_fail "TEST-580 shared-page set coverage"
}

# --- TEST-590 (Spec-AC-30, validation-round5 B3-R5) --------------------------
# TEST-580 above RUNS the five REGEN_TAIL_GENERATORS, but nothing made
# `tests/skills/suite-map.yaml`'s `aai-pr-platform` row NAME them — so
# `select-suites.mjs --files-from` on a diff touching only one of the five
# generators selected zero pr-platform, and the suite that measures "does
# this generator's page belong to the shared set" never re-ran on the very
# diff that could change the answer (measured live, validation round 5:
# DROPPED 89 for every one of the five). Pinned from the SAME literal array
# TEST-580 already runs, so the two rows can never drift apart the way three
# earlier hand-written page lists did (Amendments 19/20).
test_590_suite_map_names_the_regen_tail_generators() {
  log_info "TEST-590: the aai-pr-platform suite-map row names every REGEN_TAIL_GENERATORS script (Spec-AC-30)..."
  local map="$PROJECT_ROOT/tests/skills/suite-map.yaml"
  [[ -f "$map" ]] || { log_fail "TEST-590: $map missing"; return; }
  local row; row="$(awk '/^  aai-pr-platform:/{on=1;next} on&&/^  [a-z]/{on=0} on' "$map")"
  [[ -n "$row" ]] || log_fail "TEST-590: no aai-pr-platform row in $map"
  local -a REGEN_TAIL_GENERATORS=(
    "generate-docs-index.mjs"
    "generate-overview.mjs"
    "generate-userguide-rollup.mjs"
    "generate-docs-hub.mjs"
    "generate-factory-report.mjs"
  )
  local gen
  for gen in "${REGEN_TAIL_GENERATORS[@]}"; do
    grep -qF ".aai/scripts/$gen" <<< "$row" \
      || log_fail "TEST-590: suite-map aai-pr-platform row must list .aai/scripts/$gen so a diff touching it re-selects the suite that runs TEST-580 over it"
  done
  grep -qF "lib/docs-model.mjs" <<< "$row" \
    || log_fail "TEST-590: suite-map aai-pr-platform row must list .aai/scripts/lib/docs-model.mjs, the SHARED_GENERATED_PAGES authority TEST-580 asserts equality against"
  log_pass "TEST-590: aai-pr-platform suite-map row names every regen-tail generator plus the shared-set authority"
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
  test_019_reviewer_bots_knob
  test_020_reviewer_bots_text_shape
  test_021_reviewer_bots_json
  test_022_skill_pr_no_bots_hardening
  test_569_shared_page_push_names_open_prs
  test_580_shared_page_set_covers_every_generated_page
  test_590_suite_map_names_the_regen_tail_generators
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
        # exact-name match first (mutation-run.mjs's --selector convention
        # passes the full function name, per every other suite in this repo)
        [[ "$cand" == "$sel" || "$cand" == *"_${sel}_"* || "$cand" == "test_${sel}"* ]] && fn="$cand"
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
