#!/usr/bin/env bash
#
# Test: branch-per-work-item hygiene guard (SPEC-0070-spec-branch-per-work-item-hygiene)
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
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

GUARD="${AAI_BRANCH_GUARD:-$PROJECT_ROOT/.aai/scripts/branch-guard.mjs}"
STATE_CLI="$PROJECT_ROOT/.aai/scripts/state.mjs"

# CHANGE-0180 D4 — the three ceremony scripts that re-check the HEAD pin via
# --expect-branch (TEST-405..408). Overridable so a RED phase can point at a
# pre-change (flag-less) copy and observe the genuine failure.
CCS_SCRIPT="${AAI_CHECK_COMMITTED_SCOPE:-$PROJECT_ROOT/.aai/scripts/check-committed-scope.mjs}"
CBPG_SCRIPT="${AAI_CLOSE_BEFORE_PUSH_GUARD:-$PROJECT_ROOT/.aai/scripts/close-before-push-guard.mjs}"
CWI_SCRIPT="${AAI_CLOSE_WORK_ITEM:-$PROJECT_ROOT/.aai/scripts/close-work-item.mjs}"

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

# run_out <repo> <cmd...> — run <cmd...> inside <repo> via a REAL subshell and
# print what it printed. Every NEW call site added in this scope goes through
# this helper instead of a bare `$( cd "$repo" && ... )`: the `cd` then lives
# textually inside a function body, never inside a command substitution — the
# exact raw shape tests/skills/lib/cd-subshell-leak-baseline.tsv ratchets per
# file (check-cd-subshell-leak.mjs), which this file's TEST-403+ additions
# would otherwise have risen against (4 -> 20). Trailing redirections on the
# call (`run_out "$repo" cmd 2>&1`) still apply to the whole invocation, same
# as they did on the bare `cd && cmd` form.
run_out() {
  local repo="$1"; shift
  ( cd "$repo" && "$@" )
}

check_deps() {
  log_info "Checking dependencies..."
  command -v bash >/dev/null 2>&1 || log_skip "bash not found"
  command -v git  >/dev/null 2>&1 || log_skip "git not found"
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v mktemp >/dev/null 2>&1 || log_skip "mktemp not found"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-branch-guard-test.XXXXXX")"
  # Resolve through any $TMPDIR symlink (macOS: /tmp, /var -> /private/...) ONCE,
  # here. TEST-408 invokes a script copy under this root directly as node's
  # entry point; node's own module resolution realpaths import.meta.url, and
  # comparing that against an UNRESOLVED process.argv[1] is exactly the
  # fu-ismain-symlink-realpath defect (Spec-AC-22, a later AC in this same
  # scope, not fixed here) — every isMain guard in this repo has it today.
  # Building every fixture path from an already-resolved root sidesteps it for
  # THIS suite without touching that shared guard shape out of turn.
  TMP_ROOT="$(run_out "$TMP_ROOT" pwd -P)"
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
  assert_payload_contains "$OUT" "fix/$ref" "stdout must name the matching branch fix/$ref (got: $OUT)"
  assert_payload_contains "$OUT" "$ref" "stdout must name the ref_id $ref (got: $OUT)"
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
  assert_payload_contains "$ERR" "git checkout -b fix/$ref origin/main" "stderr must carry the exact remediation 'git checkout -b fix/$ref origin/main' (got: $ERR)"
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
  assert_payload_line_matches "$ERR" "git checkout -b .+ origin/main" \
    "detached exit must still print a copy-pasteable remediation (got: $ERR)"
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
  assert_payload_contains "$ERR" "git checkout -b fix/$ref origin/main" "mismatched exit must print the remediation 'git checkout -b fix/$ref origin/main' (got: $ERR)"
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
  assert_payload_contains_i "$ERR" "ref_id" \
    "exit-4 stderr must name the missing piece (ref_id) (got: $ERR)"
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
  local pair prefix branch repo ref="unrelated-work-item" _bg_nc_restore
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
    assert_payload_contains "$OUT" "$prefix" "stdout must name the matched prefix $prefix (got: $OUT)"
    # Distinct from the ref_id-match pass message — it must NOT claim a ref_id match.
    # Pipe-free, case-insensitive substring NEGATIVE check (spec-assertions-must-not-die-
    # on-their-own-payload): assert_payload_contains_i always auto-fails on a MISS, so it
    # cannot be wrapped in `if ... ; then log_fail` for a negative (found => fail) shape —
    # that would call log_fail on the expected/success (not-found) path instead.
    _bg_nc_restore="$(shopt -p nocasematch 2>/dev/null || printf 'shopt -u nocasematch')"
    shopt -s nocasematch
    case "$OUT" in
      *"matches current_focus.ref_id"*)
        eval "$_bg_nc_restore"
        log_fail "allowlist pass must use a DISTINCT message, not the ref_id-match line (got: $OUT)"
        ;;
    esac
    eval "$_bg_nc_restore"
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
  assert_payload_contains "$OUT" "chore/" "stdout must name the matched prefix chore/ (got: $OUT)"
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

# --- TEST-013 — git REFUSES to read the repo -> relay git's own message ---
# Bites the real downstream failure: a Windows Codex run hit a safe.directory
# ownership refusal and the guard answered "not inside a git work tree", which
# is both false (the caller IS in a work tree) and useless (it drops the exact
# `git config --global --add safe.directory ...` line git had just printed).
# safe.directory itself needs a foreign owner, so this arm reproduces the same
# CLASS with a portable fixture: a .git file pointing at a gitdir that is not
# there. What is asserted is the PROPERTY — whatever git said reaches the
# operator — never git's exact wording, which differs by version and platform
# (macOS names the missing gitdir; the Linux CI runner prints "(null)").
test_013() {
  log_info "TEST-013: git refuses the repo -> guard relays git stderr, never the false work-tree claim..."
  local repo="$TMP_ROOT/t013" missing="$TMP_ROOT/t013-absent-gitdir"
  mkdir -p "$repo" || log_fail "fixture setup: could not create $repo"
  printf 'gitdir: %s\n' "$missing" > "$repo/.git" \
    || log_fail "fixture setup: could not write the dangling .git link"

  # Precondition: git really refuses this fixture, and says something. Take
  # git's FIRST line as the thing that must survive to the operator.
  local git_said
  git_said="$( cd "$repo" && git rev-parse --is-inside-work-tree 2>&1 >/dev/null | head -1 )"
  [[ -n "$git_said" ]] \
    || log_fail "fixture is not exercising a git refusal (git printed nothing)"
  [[ "$git_said" == fatal:* ]] \
    || log_fail "fixture did not produce a git refusal (git said: $git_said)"

  run_guard "$repo"
  [[ "$RC" -eq 4 ]] || log_fail "a git refusal must still exit 4 (got $RC; stderr: $ERR)"
  # 1. git's own diagnosis reaches the operator, verbatim. This is the whole
  #    point: for safe.directory that line carries the remediation.
  [[ "$ERR" == *"$git_said"* ]] \
    || log_fail "guard did not relay git's own message (git said: $git_said; guard said: $ERR)"
  # 2. and the false claim must NOT be what the operator is told instead.
  [[ "$ERR" != *"not inside a git work tree"* ]] \
    || log_fail "guard still asserts 'not inside a git work tree' for a git refusal (stderr: $ERR)"

  # The OTHER failure that lands here: no repository at all. git writes a fatal
  # for that too, so stderr alone cannot separate the two — and telling someone
  # standing in an empty directory that git "refused to read this repository"
  # is just a second false diagnosis replacing the first. This control pins the
  # discrimination, not merely the exit code.
  local bare="$TMP_ROOT/t013-no-repo"
  mkdir -p "$bare" || log_fail "fixture setup: could not create $bare"
  run_guard "$bare"
  [[ "$RC" -eq 4 ]] || log_fail "a directory outside any repo must exit 4 (got $RC; stderr: $ERR)"
  [[ "$ERR" == *"not inside a git work tree"* ]] \
    || log_fail "outside any repository the plain sentence is the TRUE one and must be used (stderr: $ERR)"
  [[ "$ERR" != *"refused to read this repository"* ]] \
    || log_fail "no repository is not a refusal; the guard must not report one (stderr: $ERR)"

  log_pass "git refusal -> git's own message relayed verbatim, false work-tree claim withheld"
}

# --- TEST-014 — absent-vs-corrupt STATE discrimination (state-route-exists-but-is-undiscoverable) --
# Tier A (fileReadable:false) collapsed "does not exist" and "exists but
# unreadable" into one false message ("ref_id is not set in STATE.yaml" is a
# lie when there is no STATE.yaml at all) plus a remediation that fixes
# nothing for the absent case (`git checkout -b ...` never creates the file).
# Three fixtures: genuinely ABSENT (no file at all), genuinely UNREADABLE-BUT-
# PRESENT (a directory sits where the file should be — a real fs-level read
# failure, not a parse failure), and genuinely MALFORMED CONTENT (a file that
# exists and reads fine but contains no parseable YAML at all, per the issue's
# own "deliberately corrupted YAML" fixture). Only the first may name
# check-state.mjs --repair; the other two must keep today's cautious text
# UNCHANGED and must NOT suggest --repair, which would silently do nothing to
# a file `check-state.mjs`'s own `createFromTemplate` skips (it only fires
# `if (!fs.existsSync(abs))`).
test_014() {
  log_info "TEST-014: absent STATE names the real bootstrap route; a present-but-unreadable/malformed STATE keeps today's cautious text and never suggests --repair..."
  local repo

  # Case A — genuinely absent: no docs/ai/STATE.yaml at all.
  repo="$(make_repo t014a)"
  ( cd "$repo" && git checkout -b "fix/whatever" >/dev/null 2>&1 ) \
    || log_fail "fixture setup: could not create fix/whatever"
  run_guard "$repo" --base main
  [[ "$RC" -eq 4 ]] || log_fail "absent STATE must exit 4 (got $RC; stderr: $ERR)"
  [[ "$ERR" == *"does not exist"* ]] \
    || log_fail "absent STATE must say the file does not exist (got: $ERR)"
  [[ "$ERR" == *"check-state.mjs --repair"* ]] \
    || log_fail "absent STATE must name check-state.mjs --repair (got: $ERR)"
  [[ "$ERR" == *"state.mjs set-focus"* ]] \
    || log_fail "absent STATE must name state.mjs set-focus (got: $ERR)"
  [[ "$ERR" != *"ref_id is not set in STATE.yaml"* ]] \
    || log_fail "absent STATE must NOT claim a field 'is not set' in a file that does not exist (got: $ERR)"
  [[ "$ERR" != *"git checkout -b chore/<ref-id>"* ]] \
    || log_fail "absent STATE must NOT print the checkout remediation, which fixes nothing here (got: $ERR)"

  # Case B — present but genuinely unreadable at the fs level: a directory
  # sits where STATE.yaml should be, so fs.readFileSync fails even though
  # fs.existsSync is true. This is the real "exists but corrupt" branch of the
  # fix, distinct from Case A only via existsSync, per the ride's own
  # instruction ("fs.existsSync is enough").
  repo="$(make_repo t014b)"
  mkdir -p "$repo/docs/ai/STATE.yaml" \
    || log_fail "fixture setup: could not create the directory-as-STATE.yaml fixture"
  ( cd "$repo" && git checkout -b "fix/whatever" >/dev/null 2>&1 ) \
    || log_fail "fixture setup: could not create fix/whatever"
  run_guard "$repo" --base main
  [[ "$RC" -eq 4 ]] || log_fail "unreadable-but-present STATE must exit 4 (got $RC; stderr: $ERR)"
  [[ "$ERR" == *"ref_id is not set in STATE.yaml"* ]] \
    || log_fail "unreadable-but-present STATE must keep today's cautious text (got: $ERR)"
  [[ "$ERR" != *"check-state.mjs --repair"* ]] \
    || log_fail "unreadable-but-present STATE must NOT suggest --repair (it would silently do nothing) (got: $ERR)"
  [[ "$ERR" != *"does not exist"* ]] \
    || log_fail "unreadable-but-present STATE must NOT be reported as absent (got: $ERR)"

  # Case C — present, reads fine, but the content is not parseable YAML at
  # all (the issue's own "deliberately corrupted YAML" fixture). readScalar
  # simply finds no ref_id in it, landing on the SAME cautious Tier-B message
  # as "STATE exists but no focus was ever set" — correct, since that message
  # is still true of this file (no ref_id IS found in it).
  repo="$(make_repo t014c)"
  mkdir -p "$repo/docs/ai" \
    || log_fail "fixture setup: could not create $repo/docs/ai"
  printf ': : : garbage {{{ not yaml at all\n' > "$repo/docs/ai/STATE.yaml"
  ( cd "$repo" && git checkout -b "fix/whatever" >/dev/null 2>&1 ) \
    || log_fail "fixture setup: could not create fix/whatever"
  run_guard "$repo" --base main
  [[ "$RC" -eq 4 ]] || log_fail "malformed-content STATE must exit 4 (got $RC; stderr: $ERR)"
  [[ "$ERR" == *"ref_id is not set in STATE.yaml"* ]] \
    || log_fail "malformed-content STATE must keep today's cautious text (got: $ERR)"
  [[ "$ERR" != *"check-state.mjs --repair"* ]] \
    || log_fail "malformed-content STATE must NOT suggest --repair (got: $ERR)"
  [[ "$ERR" != *"does not exist"* ]] \
    || log_fail "malformed-content STATE must NOT be reported as absent (got: $ERR)"

  log_pass "absent STATE names the real bootstrap route; unreadable-but-present and malformed-content STATE both keep today's cautious text with no --repair suggestion"
}

# --- TEST-405 — --pin + a plain checkout of another branch -> --verify-pin
#     exits non-zero, naming expected/actual and citing a concurrent session
#     (CHANGE-0180 AC-001/AC-003, Spec-AC-03) --------------------------------
test_405() {
  log_info "TEST-405: --pin then a plain checkout of another branch -> --verify-pin refuses, citing a concurrent session..."
  local repo; repo="$(make_repo t405)"
  ( cd "$repo" && git checkout -qb feat/pinned ) \
    || log_fail "fixture setup: could not create feat/pinned"
  ( cd "$repo" && git checkout -qb other/session main ) \
    || log_fail "fixture setup: could not create other/session"
  ( cd "$repo" && git checkout -q feat/pinned ) \
    || log_fail "fixture setup: could not return to feat/pinned"

  run_guard "$repo" --pin
  [[ "$RC" -eq 0 ]] || log_fail "--pin on a clean branch must exit 0 (got $RC; stderr: $ERR)"

  # A plain `git checkout` of another EXISTING branch — the real shape of a
  # second live session in the same worktree moving HEAD (the P1 scar).
  ( cd "$repo" && git checkout -q other/session ) \
    || log_fail "fixture setup: could not simulate the concurrent checkout"

  run_guard "$repo" --verify-pin
  [[ "$RC" -ne 0 ]] || log_fail "--verify-pin after a concurrent checkout must exit non-zero (got 0)"
  assert_payload_contains "$ERR" "feat/pinned" "refusal must name the EXPECTED branch"
  assert_payload_contains "$ERR" "other/session" "refusal must name the ACTUAL branch"
  assert_payload_contains "$ERR" "concurrent session" "refusal must cite a concurrent session"

  # SAME branch name, DIFFERENT sha (a concurrent session resetting/rebasing
  # this exact branch, or a later commit landing under the ceremony) must
  # ALSO refuse — the pin compares the SHA, not merely the branch name. A
  # guard that dropped the sha half of the comparison would pass this.
  ( cd "$repo" && git checkout -q feat/pinned ) \
    || log_fail "fixture setup: could not return to feat/pinned for the same-branch/new-sha case"
  run_guard "$repo" --pin
  [[ "$RC" -eq 0 ]] || log_fail "--pin (second round) must exit 0 (got $RC; stderr: $ERR)"
  ( cd "$repo" && git commit --allow-empty -qm "concurrent commit on the same branch" ) \
    || log_fail "fixture setup: could not add a new commit on feat/pinned"
  run_guard "$repo" --verify-pin
  [[ "$RC" -ne 0 ]] || log_fail "--verify-pin must refuse a SAME-branch, DIFFERENT-sha move (got exit 0) — the sha half of the comparison is not being checked"
  assert_payload_contains "$ERR" "feat/pinned" "same-branch/new-sha refusal must still name the branch"

  log_pass "--verify-pin refuses a plain concurrent checkout, naming expected/actual and citing a concurrent session; a same-branch new-sha move also refuses"
}

# --- TEST-406 — detached HEAD and a renamed branch produce DISTINCT
#     messages/exit codes, neither the concurrent-session text (Spec-AC-03) --
test_406() {
  log_info "TEST-406: detached HEAD and a renamed pinned branch each get a distinct message and exit code, neither the concurrent-session text..."
  local repo; repo="$(make_repo t406)"

  # (a) detached HEAD under the pin.
  ( cd "$repo" && git checkout -qb feat/detach-me ) \
    || log_fail "fixture setup: could not create feat/detach-me"
  run_guard "$repo" --pin
  [[ "$RC" -eq 0 ]] || log_fail "--pin must exit 0 (got $RC; stderr: $ERR)"
  ( cd "$repo" && git checkout -q --detach HEAD ) \
    || log_fail "fixture setup: could not detach HEAD"
  run_guard "$repo" --verify-pin
  local detached_rc="$RC" detached_err="$ERR"
  [[ "$detached_rc" -ne 0 ]] || log_fail "--verify-pin under detached HEAD must exit non-zero (got 0)"
  assert_payload_contains "$detached_err" "detach" "detached-HEAD message must say so"
  assert_payload_not_contains "$detached_err" "concurrent session" "detached HEAD must NOT read as the concurrent-session cause"

  # (b) branch renamed under the pin (still on it, same sha, new name).
  repo="$(make_repo t406b)"
  ( cd "$repo" && git checkout -qb feat/rename-me ) \
    || log_fail "fixture setup: could not create feat/rename-me"
  run_guard "$repo" --pin
  [[ "$RC" -eq 0 ]] || log_fail "--pin must exit 0 (got $RC; stderr: $ERR)"
  ( cd "$repo" && git branch -m feat/rename-me feat/renamed-under-pin ) \
    || log_fail "fixture setup: could not rename the pinned branch"
  run_guard "$repo" --verify-pin
  local renamed_rc="$RC" renamed_err="$ERR"
  [[ "$renamed_rc" -ne 0 ]] || log_fail "--verify-pin after a rename must exit non-zero (got 0)"
  assert_payload_contains "$renamed_err" "renamed" "renamed-branch message must say so"
  assert_payload_not_contains "$renamed_err" "concurrent session" "a rename must NOT read as the concurrent-session cause"

  [[ "$detached_rc" -ne "$renamed_rc" ]] \
    || log_fail "detached HEAD and a renamed branch must produce DISTINCT exit codes (both were $detached_rc)"

  log_pass "detached HEAD and a renamed pinned branch each report distinctly, never as a concurrent session, with distinct exit codes ($detached_rc vs $renamed_rc)"
}

# --- TEST-407 — a pin in place + HEAD moved -> all three ceremony scripts
#     refuse BEFORE writing (CHANGE-0180 D4, Spec-AC-03) ---------------------
test_407() {
  log_info "TEST-407: pin + moved HEAD -> check-committed-scope, close-before-push-guard and close-work-item all refuse before writing..."
  local repo; repo="$(make_repo t407)"
  ( cd "$repo" && git checkout -qb feat/ceremony ) \
    || log_fail "fixture setup: could not create feat/ceremony"
  ( cd "$repo" && git checkout -qb other/concurrent main ) \
    || log_fail "fixture setup: could not create other/concurrent"
  ( cd "$repo" && git checkout -q feat/ceremony ) \
    || log_fail "fixture setup: could not return to feat/ceremony"
  run_guard "$repo" --pin
  [[ "$RC" -eq 0 ]] || log_fail "--pin must exit 0 (got $RC; stderr: $ERR)"

  local before_log before_status
  before_log="$(run_out "$repo" git log --format=%H --all)"
  before_status="$(run_out "$repo" git status --porcelain)"

  # A second session moves HEAD in this same worktree.
  ( cd "$repo" && git checkout -q other/concurrent ) \
    || log_fail "fixture setup: could not simulate the concurrent checkout"

  local rc out
  out="$(run_out "$repo" node "$CCS_SCRIPT" --expect-branch feat/ceremony --from-state 2>&1)"; rc=$?
  [[ "$rc" -ne 0 ]] || log_fail "check-committed-scope.mjs must refuse when HEAD moved under the pin (got exit 0; output: $out)"
  assert_payload_contains "$out" "REFUSED" "check-committed-scope.mjs must name the refusal"

  out="$(run_out "$repo" node "$CBPG_SCRIPT" --ref whatever-slug --expect-branch feat/ceremony 2>&1)"; rc=$?
  [[ "$rc" -ne 0 ]] || log_fail "close-before-push-guard.mjs must refuse when HEAD moved under the pin (got exit 0; output: $out)"
  assert_payload_contains "$out" "REFUSED" "close-before-push-guard.mjs must name the refusal"

  out="$(run_out "$repo" node "$CWI_SCRIPT" --ref whatever-slug --pr TBD --commit deadbeef --expect-branch feat/ceremony 2>&1)"; rc=$?
  [[ "$rc" -ne 0 ]] || log_fail "close-work-item.mjs must refuse when HEAD moved under the pin (got exit 0; output: $out)"
  assert_payload_contains "$out" "REFUSED" "close-work-item.mjs must name the refusal"

  local after_log after_status
  after_log="$(run_out "$repo" git log --format=%H --all)"
  after_status="$(run_out "$repo" git status --porcelain)"
  [[ "$after_log" == "$before_log" ]] \
    || log_fail "no commit must have been created by any of the three refused invocations"
  [[ "$after_status" == "$before_status" ]] \
    || log_fail "no path must have been staged/modified by any of the three refused invocations (before: [$before_status] after: [$after_status])"

  log_pass "all three ceremony scripts refuse before writing when HEAD moved under the pin; git log/status unchanged"
}

# --- TEST-408 — no pin file -> all three scripts + branch-guard.mjs are
#     byte-identical to their pre-change selves (CHANGE-0180 AC-004) --------
test_408() {
  log_info "TEST-408: with no pin file, --expect-branch/--verify-pin are no-ops — stdout+exit identical to the pre-change scripts..."
  # The pre-change blob is simply what HEAD carries right now: this scope's
  # own edit to these four files is still UNSTAGED/uncommitted on this ride's
  # branch, so `git show HEAD:<path>` is the genuine pre-change script. Every
  # one of the four has relative `./lib/...` imports, so the extracted copies
  # must sit BESIDE an extracted lib/ directory, not as flat mktemp files, or
  # node's module resolution fails before the script's own logic ever runs.
  local oldroot oldccs oldcbpg oldcwi oldguard libfile
  oldroot="$(mktemp -d "$TMP_ROOT/old-scripts.XXXXXX")"
  mkdir -p "$oldroot/lib"
  for libfile in "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs; do
    ( cd "$PROJECT_ROOT" && git show "HEAD:.aai/scripts/lib/$(basename "$libfile")" ) \
      > "$oldroot/lib/$(basename "$libfile")" 2>/dev/null
  done
  oldccs="$oldroot/check-committed-scope.mjs"
  oldcbpg="$oldroot/close-before-push-guard.mjs"
  oldcwi="$oldroot/close-work-item.mjs"
  oldguard="$oldroot/branch-guard.mjs"
  ( cd "$PROJECT_ROOT" && git show HEAD:.aai/scripts/check-committed-scope.mjs ) > "$oldccs" \
    || log_fail "could not extract pre-change check-committed-scope.mjs from HEAD"
  ( cd "$PROJECT_ROOT" && git show HEAD:.aai/scripts/close-before-push-guard.mjs ) > "$oldcbpg" \
    || log_fail "could not extract pre-change close-before-push-guard.mjs from HEAD"
  ( cd "$PROJECT_ROOT" && git show HEAD:.aai/scripts/close-work-item.mjs ) > "$oldcwi" \
    || log_fail "could not extract pre-change close-work-item.mjs from HEAD"
  ( cd "$PROJECT_ROOT" && git show HEAD:.aai/scripts/branch-guard.mjs ) > "$oldguard" \
    || log_fail "could not extract pre-change branch-guard.mjs from HEAD"

  local repo; repo="$(make_repo t408)"
  # No --pin was ever run in this fixture — Spec-AC-04's absence branch.

  local new_out new_rc old_out old_rc

  new_out="$(run_out "$repo" node "$CCS_SCRIPT" --from-state 2>&1)"; new_rc=$?
  old_out="$(run_out "$repo" node "$oldccs" --from-state 2>&1)"; old_rc=$?
  [[ "$new_rc" -eq "$old_rc" ]] || log_fail "check-committed-scope.mjs exit code changed with no pin (old $old_rc, new $new_rc)"
  [[ "$new_out" == "$old_out" ]] || log_fail "check-committed-scope.mjs stdout changed with no pin (old: [$old_out] new: [$new_out])"

  new_out="$(run_out "$repo" node "$CBPG_SCRIPT" --ref bogus-slug 2>&1)"; new_rc=$?
  old_out="$(run_out "$repo" node "$oldcbpg" --ref bogus-slug 2>&1)"; old_rc=$?
  [[ "$new_rc" -eq "$old_rc" ]] || log_fail "close-before-push-guard.mjs exit code changed with no pin (old $old_rc, new $new_rc)"
  [[ "$new_out" == "$old_out" ]] || log_fail "close-before-push-guard.mjs stdout changed with no pin (old: [$old_out] new: [$new_out])"

  new_out="$(run_out "$repo" node "$CWI_SCRIPT" --ref bogus-slug --pr TBD --commit deadbeef 2>&1)"; new_rc=$?
  old_out="$(run_out "$repo" node "$oldcwi" --ref bogus-slug --pr TBD --commit deadbeef 2>&1)"; old_rc=$?
  [[ "$new_rc" -eq "$old_rc" ]] || log_fail "close-work-item.mjs exit code changed with no pin (old $old_rc, new $new_rc)"
  [[ "$new_out" == "$old_out" ]] || log_fail "close-work-item.mjs stdout changed with no pin (old: [$old_out] new: [$new_out])"

  # branch-guard.mjs itself, with NO new flag at all, on a real guard-mode run.
  ( cd "$repo" && git checkout -qb fix/whatever ) \
    || log_fail "fixture setup: could not create fix/whatever"
  new_out="$(run_out "$repo" node "$GUARD" --base main 2>&1)"; new_rc=$?
  old_out="$(run_out "$repo" node "$oldguard" --base main 2>&1)"; old_rc=$?
  [[ "$new_rc" -eq "$old_rc" ]] || log_fail "branch-guard.mjs exit code changed with no new flag (old $old_rc, new $new_rc)"
  [[ "$new_out" == "$old_out" ]] || log_fail "branch-guard.mjs stdout changed with no new flag (old: [$old_out] new: [$new_out])"

  # And the absence branch itself: --verify-pin with no pin file costs one
  # stat and exits 0.
  run_guard "$repo" --verify-pin
  [[ "$RC" -eq 0 ]] || log_fail "--verify-pin with no pin file must exit 0 (got $RC; stderr: $ERR)"
  # The no-pin path is a single `stat` and nothing else (Spec-AC-04): no git
  # call, no diagnostic. A mutation that runs the pin check before the
  # existence test (mutation-408) pays an extra git call here and prints
  # something — this is the assertion that mutation must redden.
  [[ -z "$ERR" ]] || log_fail "--verify-pin with no pin file must print nothing to stderr (got: $ERR)"
  [[ -z "$OUT" ]] || log_fail "--verify-pin with no pin file must print nothing to stdout (got: $OUT)"

  log_pass "no pin file -> all three ceremony scripts and branch-guard.mjs are byte-identical to their pre-change selves"
}

ALL_TESTS="001 002 003 004 005 006 007 008 009 010 011 012 013 014 405 406 407 408"

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
