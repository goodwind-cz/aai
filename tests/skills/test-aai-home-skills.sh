#!/usr/bin/env bash
# Publisher for Antigravity CLI home skill trees.
# Spec: docs/specs/SPEC-0194-spec-antigravity-cli-skill-paths.md
set -euo pipefail

TEST_NAME="aai-home-skills"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/pipe-safe.sh
. "$SCRIPT_DIR/lib/pipe-safe.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PUBLISH="$PROJECT_ROOT/.aai/scripts/publish-home-skills.mjs"
SYNC="$PROJECT_ROOT/.aai/scripts/sync-harness-skills.mjs"
PROFILES="$PROJECT_ROOT/.aai/system/PROFILES.yaml"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }

hash_tree() {
  local root="$1"
  if [[ ! -d "$root" ]]; then
    echo "ABSENT"
    return
  fi
  (cd "$root" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
    sha256sum "$f"
  done) | sha256sum | awk '{print $1}'
}

make_fixture() {
  local root="$1"
  mkdir -p "$root/.claude/skills/alpha" "$root/.claude/skills/beta" "$root/.agents/skills/keep"
  printf '%s\n' 'marker' > "$root/.agents/skills/keep/SKILL.md"
  cat > "$root/.claude/skills/alpha/SKILL.md" <<'EOF'
---
name: alpha
description: alpha skill
model: haiku
---

# Alpha
EOF
  cat > "$root/.claude/skills/beta/SKILL.md" <<'EOF'
---
name: beta
description: beta skill
model: haiku
---

# Beta
EOF
}

run_pub() {
  local decoy="$1" repo="$2" home="$3" mode="$4" out rc
  set +e
  out="$(GEMINI_HOME="$decoy" CLAUDE_CONFIG_DIR="$decoy" CODEX_HOME="$decoy" \
    node "$PUBLISH" --root "$repo" --home "$home" "$mode" 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "$out"
  return "$rc"
}

expect_pub() {
  local label="$1" want="$2" decoy="$3" repo="$4" home="$5" mode="$6" out rc
  set +e
  out="$(run_pub "$decoy" "$repo" "$home" "$mode")"
  rc=$?
  set -e
  [[ "$rc" == "$want" ]] || log_fail "$label must exit $want, got $rc ($out)"
  printf '%s\n' "$out"
}

test_001_check_names_both_missing_trees() {
  local work home out rc
  work="$(mktemp -d)"
  home="$work/home"
  make_fixture "$work/repo"
  mkdir -p "$home"
  set +e
  out="$(run_pub "$work/decoy" "$work/repo" "$home" --check)"
  rc=$?
  set -e
  [[ "$rc" == 1 ]] || log_fail "TEST-001: --check must exit 1, got $rc ($out)"
  printf '%s\n' "$out" | qgrep -q '.gemini/antigravity-cli/skills' \
    || log_fail "TEST-001: output must name .gemini/antigravity-cli/skills ($out)"
  printf '%s\n' "$out" | qgrep -q '.gemini/skills' \
    || log_fail "TEST-001: output must name .gemini/skills ($out)"
  log_pass "TEST-001: --check names both missing trees and exits 1"
}

test_002_write_copies_both_trees() {
  local work home repo out rc
  work="$(mktemp -d)"
  home="$work/home"
  repo="$work/repo"
  make_fixture "$repo"
  mkdir -p "$home"
  out="$(expect_pub "TEST-002: --write" 0 "$work/decoy" "$repo" "$home" --write)"
  for skill in alpha beta; do
    for tree in ".gemini/antigravity-cli/skills" ".gemini/skills"; do
      local dest="$home/$tree/$skill/SKILL.md"
      [[ -f "$dest" ]] || log_fail "TEST-002: missing $dest"
      cmp -s "$repo/.claude/skills/$skill/SKILL.md" "$dest" \
        || log_fail "TEST-002: $dest is not byte-identical to the source"
    done
  done
  local extra
  extra="$(find "$home/.gemini/antigravity-cli/skills" "$home/.gemini/skills" -mindepth 1 -maxdepth 1 -type d | sed 's#.*/##' | LC_ALL=C sort | uniq)"
  [[ "$extra" == $'alpha\nbeta' ]] || log_fail "TEST-002: unexpected skill directories: $extra"
  log_pass "TEST-002: --write copies both trees byte-identical"
}

test_003_second_write_is_idempotent() {
  local work home repo before after out rc
  work="$(mktemp -d)"
  home="$work/home"
  repo="$work/repo"
  make_fixture "$repo"
  mkdir -p "$home"
  expect_pub "TEST-003: first --write" 0 "$work/decoy" "$repo" "$home" --write >/dev/null
  before="$(hash_tree "$home")"
  expect_pub "TEST-003: second --write" 0 "$work/decoy" "$repo" "$home" --write >/dev/null
  after="$(hash_tree "$home")"
  [[ "$before" == "$after" ]] || log_fail "TEST-003: second write changed bytes ($before -> $after)"
  expect_pub "TEST-003: --check" 0 "$work/decoy" "$repo" "$home" --check >/dev/null
  log_pass "TEST-003: second write is byte-identical and --check exits 0"
}

test_004_ignores_harness_env_and_project_mirror() {
  local work home repo decoy marker
  work="$(mktemp -d)"
  home="$work/home"
  repo="$work/repo"
  decoy="$work/decoy"
  make_fixture "$repo"
  mkdir -p "$home" "$decoy"
  marker="$(cat "$repo/.agents/skills/keep/SKILL.md")"
  expect_pub "TEST-004: --write" 0 "$decoy" "$repo" "$home" --write >/dev/null
  [[ -f "$home/.gemini/antigravity-cli/skills/alpha/SKILL.md" ]] \
    || log_fail "TEST-004: skill missing under --home"
  [[ ! -e "$decoy/.gemini/antigravity-cli/skills" && ! -e "$decoy/.gemini/skills" ]] \
    || log_fail "TEST-004: publisher wrote under GEMINI_HOME/CLAUDE_CONFIG_DIR/CODEX_HOME"
  [[ "$(cat "$repo/.agents/skills/keep/SKILL.md")" == "$marker" ]] \
    || log_fail "TEST-004: project .agents/skills was modified"
  log_pass "TEST-004: harness env is ignored and .agents/skills is untouched"
}

test_005_project_mirror_check_still_passes() {
  local work home out rc
  work="$(mktemp -d)"
  home="$work/home"
  mkdir -p "$home"
  expect_pub "TEST-005: --write" 0 "$work/decoy" "$PROJECT_ROOT" "$home" --write >/dev/null
  set +e
  out="$(node "$SYNC" --check 2>&1)"
  rc=$?
  set -e
  [[ "$rc" == 0 ]] || log_fail "TEST-005: sync-harness-skills --check exited $rc ($out)"
  log_pass "TEST-005: project mirror check still exits 0"
}

test_006_profiles_lists_the_script() {
  grep -qF 'publish-home-skills.mjs' "$PROFILES" \
    || log_fail "TEST-006: PROFILES.yaml does not list publish-home-skills.mjs"
  log_pass "TEST-006: PROFILES.yaml lists publish-home-skills.mjs"
}

main() {
  echo "=== AAI Skill Test: $TEST_NAME ==="
  if [[ $# -gt 0 ]]; then
    declare -F "$1" >/dev/null || { echo "Unknown test: $1" >&2; exit 2; }
    "$1"
    echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="
    return
  fi
  test_001_check_names_both_missing_trees
  test_002_write_copies_both_trees
  test_003_second_write_is_idempotent
  test_004_ignores_harness_env_and_project_mirror
  test_005_project_mirror_check_still_passes
  test_006_profiles_lists_the_script
  echo "=== $TEST_NAME: ALL PASSED ==="
}

main "$@"
