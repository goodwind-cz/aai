#!/usr/bin/env bash
#
# Test: branch-per-work-item hygiene guard (SPEC-DRAFT-spec-branch-per-work-item-hygiene)
# Verifies .aai/scripts/branch-guard.mjs — a deterministic, READ-ONLY guard that
# fails closed when the current git branch does not correspond to
# current_focus.ref_id. Implements TEST-001..008 from the frozen spec.
#
# Behavioral tests run the guard inside throwaway git repos (one per condition),
# each carrying its own minimal docs/ai/STATE.yaml, and assert the guard's exit
# code + stderr/stdout. TEST-001 crosses the STATE seam for real: it sets
# current_focus via the REAL writer (state.mjs set-focus), then the guard reads
# it back — producer and consumer both exercised, neither mocked.
#
# The GUARD script under test is overridable so the RED phase can prove the
# tests genuinely discriminate (the guard does not exist pre-fix, so every
# invocation fails ENOENT/non-zero before branch-guard.mjs is implemented):
#   AAI_BRANCH_GUARD   guard under test (default .aai/scripts/branch-guard.mjs)
#
# Usage:
#   bash tests/skills/test-aai-branch-guard.sh            # run all (TEST-001..008)
#   bash tests/skills/test-aai-branch-guard.sh 001 006    # run only selected tests
#
# Exit codes:
#   0  - All selected tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-branch-guard"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

GUARD="${AAI_BRANCH_GUARD:-$PROJECT_ROOT/.aai/scripts/branch-guard.mjs}"
STATE_CLI="$PROJECT_ROOT/.aai/scripts/state.mjs"

# Wiring targets (grep asserts).
SKILL_PR_DOC="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
AGENTS_DOC="$PROJECT_ROOT/.aai/AGENTS.md"

TMP_ROOT=""

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

cleanup() {
  if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

# Create a throwaway git repo with an initial commit on `main` and print its
# path. Full mktemp template (LEARNED 2026-07-19); `git init -b main` (never
# assume a default local main). An initial commit makes HEAD born so
# `git rev-parse --abbrev-ref HEAD` returns a real branch name.
make_repo() {  # make_repo <slug>
  local repo
  repo="$(mktemp -d "$TMP_ROOT/${1}.XXXXXX")"
  git init -b main "$repo" >/dev/null 2>&1
  ( cd "$repo" \
    && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit \
         --allow-empty -m init >/dev/null 2>&1 )
  echo "$repo"
}

# Write a minimal STATE.yaml carrying a current_focus block. A `null` ref_id or
# type is written literally (the degenerate / broken-STATE fixture).
write_state() {  # write_state <repo> <type> <ref_id>
  mkdir -p "$1/docs/ai"
  cat > "$1/docs/ai/STATE.yaml" <<EOF
project_status: active
current_focus:
  type: $2
  ref_id: $3
  primary_path: docs/issues/ISSUE-DRAFT-$3.md
updated_at_utc: 2026-07-22T00:00:00Z
EOF
}

# Run the guard inside <repo>; capture stdout to the OUT global, stderr to ERR,
# and return the guard's real exit code in RC.
OUT=""; ERR=""; RC=0
run_guard() {  # run_guard <repo> [guard-args...]
  local repo="$1"; shift
  local errf
  errf="$(mktemp "$TMP_ROOT/err.XXXXXX")"
  OUT="$( cd "$repo" && node "$GUARD" "$@" 2>"$errf" )"; RC=$?
  ERR="$(cat "$errf")"
  rm -f "$errf"
}

check_deps() {
  log_info "Checking dependencies..."
  command -v bash >/dev/null 2>&1 || log_skip "bash not found"
  command -v git  >/dev/null 2>&1 || log_skip "git not found"
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v mktemp >/dev/null 2>&1 || log_skip "mktemp not found"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-branch-guard-test.XXXXXX")"
  log_pass "Dependencies checked"
}

# --- TEST-001 — correct branch passes; STATE seam crossed for real (Spec-AC-01) ---
test_001() {
  log_info "TEST-001: real state.mjs writer sets ref_id; correct fix/<ref> branch -> guard exit 0..."
  [[ -f "$STATE_CLI" ]] || log_fail "state.mjs writer not found: $STATE_CLI"
  local repo ref="my-feature"
  repo="$(make_repo t001)"
  write_state "$repo" intake_issue "placeholder"
  # Producer: the REAL writer sets current_focus (not a hand-edited fixture).
  ( cd "$repo" && node "$STATE_CLI" set-focus --type intake_issue --ref "$ref" \
      --path "docs/issues/ISSUE-DRAFT-$ref.md" ) >/dev/null 2>&1 \
    || log_fail "fixture setup: state.mjs set-focus failed"
  grep -q "ref_id: $ref" "$repo/docs/ai/STATE.yaml" \
    || log_fail "fixture setup: writer did not persist ref_id=$ref"
  ( cd "$repo" && git checkout -b "fix/$ref" >/dev/null 2>&1 ) \
    || log_fail "fixture setup: could not create fix/$ref"
  run_guard "$repo" --base main
  [[ "$RC" -eq 0 ]] || log_fail "correct branch fix/$ref must exit 0 (got $RC; stderr: $ERR)"
  echo "$OUT" | grep -qF "fix/$ref" \
    || log_fail "stdout must name the matching branch fix/$ref (got: $OUT)"
  echo "$OUT" | grep -qF "$ref" \
    || log_fail "stdout must name the ref_id $ref (got: $OUT)"
  log_pass "consumer reads back the writer's ref_id; correct branch exits 0 naming branch+ref_id"
}

# --- TEST-002 — on the base branch -> exit 1 + exact remediation (Spec-AC-02) ------
test_002() {
  log_info "TEST-002: on the base branch -> guard exit 1 with exact 'git checkout -b fix/<ref> origin/main' remediation..."
  local repo ref="my-feature"
  repo="$(make_repo t002)"
  write_state "$repo" intake_issue "$ref"
  # Still on `main` (the base) — the ambient-branch trap the issue describes.
  run_guard "$repo" --base main
  [[ "$RC" -eq 1 ]] || log_fail "on the base branch the guard must exit 1 (got $RC; stderr: $ERR)"
  echo "$ERR" | grep -qF "git checkout -b fix/$ref origin/main" \
    || log_fail "stderr must carry the exact remediation 'git checkout -b fix/$ref origin/main' (got: $ERR)"
  # Negative control / base-precedence: a base branch that COINCIDENTALLY contains
  # the ref_id substring must STILL be reported as exit 1 (base check wins over
  # the containment check), never a false exit-0 pass.
  local repo2
  repo2="$(make_repo t002b)"
  write_state "$repo2" intake_issue "$ref"
  ( cd "$repo2" && git checkout -b "release-$ref" >/dev/null 2>&1 ) \
    || log_fail "fixture setup: could not create release-$ref"
  run_guard "$repo2" --base "release-$ref"
  [[ "$RC" -eq 1 ]] \
    || log_fail "a base branch coincidentally containing the ref_id must still exit 1, never 0 (got $RC)"
  log_pass "base branch -> exit 1 with exact remediation; base precedence beats coincidental containment"
}

# --- TEST-003 — detached HEAD -> exit 2, precedes STATE read (Spec-AC-02) ----------
test_003() {
  log_info "TEST-003: detached HEAD -> guard exit 2 (with readable AND with broken STATE, proving detached precedes the STATE read)..."
  local repo ref="my-feature"
  repo="$(make_repo t003)"
  write_state "$repo" intake_issue "$ref"
  ( cd "$repo" && git checkout --detach >/dev/null 2>&1 ) \
    || log_fail "fixture setup: could not detach HEAD"
  run_guard "$repo" --base main
  [[ "$RC" -eq 2 ]] || log_fail "detached HEAD must exit 2 (got $RC; stderr: $ERR)"
  echo "$ERR" | grep -qE "git checkout -b .+ origin/main" \
    || log_fail "detached exit must still print a copy-pasteable remediation (got: $ERR)"
  # Sub-case: detached AND STATE unreadable -> STILL exit 2 (detached check at
  # order item 2 precedes the STATE read at item 3).
  rm -f "$repo/docs/ai/STATE.yaml"
  run_guard "$repo" --base main
  [[ "$RC" -eq 2 ]] \
    || log_fail "detached HEAD must exit 2 even when STATE is unreadable (got $RC) — detached must precede the STATE read"
  log_pass "detached HEAD -> exit 2 with remediation; detached check precedes the STATE read"
}

# --- TEST-004 — branch not containing the ref_id slug -> exit 3 (Spec-AC-02) -------
test_004() {
  log_info "TEST-004: a branch name that does not contain the ref_id slug -> guard exit 3 + remediation..."
  local repo ref="my-feature"
  repo="$(make_repo t004)"
  write_state "$repo" intake_issue "$ref"
  ( cd "$repo" && git checkout -b "feat/unrelated-name" >/dev/null 2>&1 ) \
    || log_fail "fixture setup: could not create feat/unrelated-name"
  run_guard "$repo" --base main
  [[ "$RC" -eq 3 ]] || log_fail "a mismatched branch must exit 3 (got $RC; stderr: $ERR)"
  echo "$ERR" | grep -qF "git checkout -b fix/$ref origin/main" \
    || log_fail "mismatched exit must print the remediation 'git checkout -b fix/$ref origin/main' (got: $ERR)"
  log_pass "mismatched branch -> exit 3 with remediation"
}

# --- TEST-005 — STATE/ref_id unresolvable -> exit 4, fail-closed + precedence (Spec-AC-03) --
test_005() {
  log_info "TEST-005: empty ref_id / unreadable STATE -> exit 4 (guard AND --suggest); precedence sub-cases..."
  local repo ref
  # Case A — ref_id empty/null: guard mode exit 4 (never a silent pass).
  repo="$(make_repo t005a)"
  write_state "$repo" intake_issue "null"
  ( cd "$repo" && git checkout -b "fix/whatever" >/dev/null 2>&1 ) \
    || log_fail "fixture setup: could not create fix/whatever"
  run_guard "$repo" --base main
  [[ "$RC" -eq 4 ]] || log_fail "empty/null ref_id must exit 4 in guard mode (got $RC; stderr: $ERR)"
  echo "$ERR" | grep -qi "ref_id" \
    || log_fail "exit-4 stderr must name the missing piece (ref_id) (got: $ERR)"
  # Case A' — --suggest with the same broken STATE also exits 4 (never a silent pass).
  run_guard "$repo" --suggest
  [[ "$RC" -eq 4 ]] || log_fail "empty/null ref_id must exit 4 in --suggest mode too (got $RC; stderr: $ERR)"
  # Case B — unreadable STATE (file absent) on a valid branch -> exit 4.
  local repo2
  repo2="$(make_repo t005b)"
  ( cd "$repo2" && git checkout -b "fix/anything" >/dev/null 2>&1 ) \
    || log_fail "fixture setup: could not create fix/anything"
  # no STATE.yaml written at all
  run_guard "$repo2" --base main
  [[ "$RC" -eq 4 ]] || log_fail "unreadable (absent) STATE must exit 4 (got $RC; stderr: $ERR)"
  # Case C — PRECEDENCE: on the base branch WITH broken STATE -> exit 4, NOT 1
  # (the STATE read at order item 3 wins over the base-branch check at item 4).
  local repo3
  repo3="$(make_repo t005c)"
  write_state "$repo3" intake_issue "null"
  # stay on main (the base)
  run_guard "$repo3" --base main
  [[ "$RC" -eq 4 ]] \
    || log_fail "base branch + broken STATE must exit 4 (not 1): STATE read precedes the base-branch check (got $RC)"
  # Case D — PRECEDENCE: detached WITH broken STATE -> exit 2, NOT 4 (detached at
  # item 2 precedes the STATE read at item 3).
  local repo4
  repo4="$(make_repo t005d)"
  ( cd "$repo4" && git checkout --detach >/dev/null 2>&1 ) \
    || log_fail "fixture setup: could not detach HEAD"
  # no STATE.yaml
  run_guard "$repo4" --base main
  [[ "$RC" -eq 2 ]] \
    || log_fail "detached + broken STATE must exit 2 (not 4): detached check precedes the STATE read (got $RC)"
  log_pass "empty/unreadable STATE -> exit 4 fail-closed (guard + --suggest); base<-STATE and detached<-STATE precedence hold"
}

# --- TEST-006 — --suggest prints canonical <type-token>/<ref-id> for all 10 types (Spec-AC-04) --
test_006() {
  log_info "TEST-006: --suggest prints exactly <type-token>/<ref-id> to stdout for each of the 10 mapped types, exit 0..."
  local ref="demo-ref" pair type token repo
  for pair in \
      intake_issue:fix intake_hotfix:fix \
      intake_change:feat intake_prd:feat intake_rfc:feat \
      intake_release:chore intake_research:chore \
      technology_extraction:chore maintenance:chore none:chore; do
    type="${pair%%:*}"; token="${pair##*:}"
    repo="$(make_repo "t006-$token")"
    write_state "$repo" "$type" "$ref"
    # Run --suggest from the BASE branch (main): --suggest performs no git-branch
    # check, so it must print identically regardless of the current branch.
    run_guard "$repo" --suggest
    [[ "$RC" -eq 0 ]] || log_fail "--suggest for type=$type must exit 0 (got $RC; stderr: $ERR)"
    [[ "$OUT" == "$token/$ref" ]] \
      || log_fail "--suggest for type=$type must print exactly '$token/$ref' to stdout (got: '$OUT')"
    # stderr must stay empty on the success path (stdout-only contract).
    [[ -z "$ERR" ]] || log_fail "--suggest must print to stdout ONLY; stderr should be empty (got: $ERR)"
  done
  log_pass "--suggest prints exactly <type-token>/<ref-id> for all 10 mapped types, stdout-only, exit 0"
}

# --- TEST-007 — SKILL_PR gains the '0. BRANCH HYGIENE' precondition (Spec-AC-05) ---
test_007() {
  log_info "TEST-007: SKILL_PR.prompt.md carries a '0. BRANCH HYGIENE' precondition naming branch-guard.mjs, before the PUSH step..."
  [[ -f "$SKILL_PR_DOC" ]] || log_fail "missing $SKILL_PR_DOC"
  grep -qF "BRANCH HYGIENE" "$SKILL_PR_DOC" \
    || log_fail "SKILL_PR must contain a '0. BRANCH HYGIENE' precondition (grep -c BRANCH HYGIENE = 0 — RED pre-fix)"
  grep -qF "branch-guard.mjs" "$SKILL_PR_DOC" \
    || log_fail "the BRANCH HYGIENE precondition must name branch-guard.mjs"
  grep -qiE "STOP|do not (stage|push)|non-zero" "$SKILL_PR_DOC" \
    || log_fail "the precondition must instruct STOP on non-zero exit before any push"
  # Ordering: the BRANCH HYGIENE line must appear BEFORE the '5. PUSH + PR' step
  # so it gates staging and push alike.
  local hy_line push_line
  hy_line="$(grep -nF "BRANCH HYGIENE" "$SKILL_PR_DOC" | head -1 | cut -d: -f1)"
  push_line="$(grep -nE "PUSH \+ PR|Push the branch" "$SKILL_PR_DOC" | head -1 | cut -d: -f1)"
  [[ -n "$hy_line" && -n "$push_line" ]] \
    || log_fail "could not locate both the BRANCH HYGIENE line ($hy_line) and the PUSH line ($push_line)"
  [[ "$hy_line" -lt "$push_line" ]] \
    || log_fail "BRANCH HYGIENE (line $hy_line) must precede the PUSH step (line $push_line)"
  log_pass "SKILL_PR carries the '0. BRANCH HYGIENE' precondition naming branch-guard.mjs before the PUSH step"
}

# --- TEST-008 — AGENTS.md documents the one-branch-per-work-item rule (Spec-AC-06) --
test_008() {
  log_info "TEST-008: AGENTS.md carries a one-branch-per-work-item note naming branch-guard.mjs..."
  [[ -f "$AGENTS_DOC" ]] || log_fail "missing $AGENTS_DOC"
  grep -qF "branch-guard.mjs" "$AGENTS_DOC" \
    || log_fail "AGENTS.md must name branch-guard.mjs (grep -c = 0 — RED pre-fix)"
  grep -qiE "one branch per work item|one-branch-per-work-item|branch per work item|dedicated branch" "$AGENTS_DOC" \
    || log_fail "AGENTS.md must document the one-branch-per-work-item rule"
  log_pass "AGENTS.md documents the one-branch-per-work-item rule naming branch-guard.mjs"
}

# --- TEST-009 — allowlisted non-work-item prefix, set-but-unrelated ref_id -> exit 0 (Spec-AC-01) --
test_009() {
  log_info "TEST-009: chore/, release/, docs/ prefixed branches with a set-but-unrelated ref_id -> guard exit 0 naming the matched prefix..."
  local pair prefix branch repo ref="unrelated-work-item"
  for pair in \
      "chore/:chore/tenant-cleanup" \
      "release/:release/v1.2.3" \
      "docs/:docs/typo-fix"; do
    prefix="${pair%%:*}"; branch="${pair##*:}"
    repo="$(make_repo "t009-${prefix%/}")"
    # ref_id is SET to a value the allowlisted branch name does NOT contain, so the
    # pre-fix guard would fall through to the containment check and exit 3 (RED).
    write_state "$repo" intake_issue "$ref"
    ( cd "$repo" && git checkout -b "$branch" >/dev/null 2>&1 ) \
      || log_fail "fixture setup: could not create $branch"
    run_guard "$repo" --base main
    [[ "$RC" -eq 0 ]] \
      || log_fail "allowlisted branch $branch with an unrelated ref_id must exit 0 (got $RC; stderr: $ERR)"
    echo "$OUT" | grep -qF "$prefix" \
      || log_fail "stdout must name the matched prefix $prefix (got: $OUT)"
    # Distinct from the ref_id-match pass message — it must NOT claim a ref_id match.
    echo "$OUT" | grep -qiF "matches current_focus.ref_id" \
      && log_fail "allowlist pass must use a DISTINCT message, not the ref_id-match line (got: $OUT)"
  done
  log_pass "chore//release//docs/ branches with an unrelated ref_id -> exit 0 with a distinct prefix-naming message"
}

# --- TEST-010 — allowlisted prefix with a CLEARED ref_id (Tier B, STATE readable) -> exit 0 (Spec-AC-01) --
test_010() {
  log_info "TEST-010: chore/ branch with a cleared/empty ref_id (STATE readable) -> guard exit 0 (Tier B)..."
  local repo
  repo="$(make_repo t010)"
  # STATE opens fine but carries no focus (ref_id null) — Tier B. Pre-fix this
  # exited 4 via the combined item-3 check; post-fix the allowlist lets it pass.
  write_state "$repo" intake_issue "null"
  ( cd "$repo" && git checkout -b "chore/tenant-cleanup" >/dev/null 2>&1 ) \
    || log_fail "fixture setup: could not create chore/tenant-cleanup"
  run_guard "$repo" --base main
  [[ "$RC" -eq 0 ]] \
    || log_fail "allowlisted branch with a cleared ref_id (Tier B) must exit 0 (got $RC; stderr: $ERR)"
  echo "$OUT" | grep -qF "chore/" \
    || log_fail "stdout must name the matched prefix chore/ (got: $OUT)"
  log_pass "allowlisted branch + cleared ref_id (Tier B) -> exit 0"
}

# --- TEST-011 — allowlisted prefix but STATE FILE ABSENT (Tier A) -> exit 4 (Spec-AC-04) --
# NON-DISCRIMINATING BY DESIGN: exit 4 both before and after this change. Pins that
# a genuinely unreadable STATE still fails closed even on an allowlisted branch.
test_011() {
  log_info "TEST-011: chore/ branch with STATE.yaml absent (Tier A) -> guard exit 4 (allowlist never overrides an unreadable file)..."
  local repo
  repo="$(make_repo t011)"
  # No write_state — STATE.yaml is genuinely absent (Tier A), not merely empty.
  ( cd "$repo" && git checkout -b "chore/tenant-cleanup" >/dev/null 2>&1 ) \
    || log_fail "fixture setup: could not create chore/tenant-cleanup"
  run_guard "$repo" --base main
  [[ "$RC" -eq 4 ]] \
    || log_fail "allowlisted branch with an absent STATE (Tier A) must exit 4 (got $RC; stderr: $ERR)"
  log_pass "allowlisted branch + absent STATE (Tier A) -> exit 4, fail-closed"
}

# --- TEST-012 — base-vs-allowlist collision -> exit 1, base wins (Spec-AC-02) --
# NON-DISCRIMINATING BY DESIGN: exit 1 both before and after. Pins that the
# base-branch check always precedes the allowlist check.
test_012() {
  log_info "TEST-012: branch AND --base both 'chore/legacy-main' -> guard exit 1 (base check precedes the allowlist)..."
  local repo ref="valid-unrelated-ref"
  repo="$(make_repo t012)"
  write_state "$repo" intake_issue "$ref"
  ( cd "$repo" && git checkout -b "chore/legacy-main" >/dev/null 2>&1 ) \
    || log_fail "fixture setup: could not create chore/legacy-main"
  run_guard "$repo" --base "chore/legacy-main"
  [[ "$RC" -eq 1 ]] \
    || log_fail "a branch that is simultaneously the base AND allowlist-shaped must exit 1, never 0 (got $RC; stderr: $ERR)"
  log_pass "base-vs-allowlist collision -> exit 1 (base check wins over the allowlist)"
}

ALL_TESTS="001 002 003 004 005 006 007 008 009 010 011 012"

main() {
  echo "Testing $TEST_NAME (deterministic branch-per-work-item hygiene guard)"
  check_deps
  local selected="$*"
  [[ -n "$selected" ]] || selected="$ALL_TESTS"
  local t
  for t in $selected; do
    t="${t#TEST-}"
    "test_${t}"
  done
  echo ""
  log_pass "All selected $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
