#!/usr/bin/env bash
# Linked-worktree seed integration tests. Every fixture is private to this run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/aai-worktree-seed.XXXXXX")"
SOURCE="$SCRATCH/installed source"
SEED="$ROOT/.aai/scripts/worktree-seed.mjs"
SELECTED=""
if [[ $# -ne 0 ]]; then
  if [[ $# -eq 2 && "$1" == "--test" ]]; then SELECTED="$2"
  elif [[ $# -eq 1 && "$1" == test_* ]]; then SELECTED="$1"
  else echo 'Usage: test-aai-worktree-seed.sh [--test TEST-xxx]' >&2; exit 2
  fi
fi

cleanup() {
  if [[ -d "$SOURCE/.git" ]]; then
    git -C "$SOURCE" worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r path; do
      [[ "$path" == "$SOURCE" ]] || git -C "$SOURCE" worktree remove --force "$path" >/dev/null 2>&1 || true
    done
  fi
  [[ -n "${KEEP_TEST_DIR:-}" ]] || rm -rf "$SCRATCH"
}
trap cleanup EXIT

fail() { echo "FAIL: $1 $2" >&2; exit 1; }
run() { "$@" || fail SETUP "command failed: $*"; }
case_start() { [[ -z "$SELECTED" || "$SELECTED" == "$1" ]]; }
refuses() {
  local id="$1" reason="$2" out rc=0
  shift 2
  out="$("$@" 2>&1)" || rc=$?
  [[ "$rc" -ne 0 ]] || fail "$id" "expected refusal: $reason"
  case "$out" in *"$reason"*) ;; *) fail "$id" "missing $reason in $out" ;; esac
}
new_worktree() {
  local name="$1"
  local branch="${name// /_}"
  WT="$SCRATCH/$name"
  run git -C "$SOURCE" worktree add -q -b "$branch" "$WT" main
}
seed() { node "$SEED" --source "$SOURCE" --target "$WT"; }

run mkdir -p "$SOURCE"
run git -C "$SOURCE" init -q -b main
run git -C "$SOURCE" config user.name 'AAI Fixture'
run git -C "$SOURCE" config user.email 'fixture@example.invalid'
printf 'seed fixture\n' > "$SOURCE/README.md"
run bash "$ROOT/.aai/scripts/aai-sync.sh" "$SOURCE" --profile core
run git -C "$SOURCE" add README.md .gitignore
run git -C "$SOURCE" commit -qm 'project baseline'

test_001_core() {
  new_worktree core_one
  [[ ! -e "$WT/.aai/scripts/check-state.mjs" ]] || fail TEST-001 'pre-seed layer unexpectedly present'
  seed || fail TEST-001 'seed refused real core installation'
  [[ -f "$WT/.aai/scripts/check-state.mjs" ]] || fail TEST-001 'state checker absent after seed'
  [[ -f "$WT/.aai/system/AAI_PIN.md" ]] || fail TEST-001 'pin absent after seed'
  run cmp "$SOURCE/.aai/system/AAI_PIN.md" "$WT/.aai/system/AAI_PIN.md"
  local_roots='.agents/skills .claude/skills .codex/skills .gemini/skills'
  for rel in $local_roots; do
    [[ -d "$WT/$rel" ]] || fail TEST-001 "missing $rel"
    diff -rq "$SOURCE/$rel" "$WT/$rel" >/dev/null || fail TEST-001 "different $rel"
  done
  diff -rq -x cache "$SOURCE/.aai" "$WT/.aai" || fail TEST-001 'different .aai inventory/bytes'
  echo 'PASS: TEST-001 core snapshot'
}

test_002_extended() {
  run bash "$ROOT/.aai/scripts/aai-sync.sh" "$SOURCE" --profile extended
  printf 'extended addition\n' > "$SOURCE/.aai/extended-test-only.txt"
  new_worktree extended_two
  seed || fail TEST-002 'extended seed failed'
  cmp "$SOURCE/.aai/extended-test-only.txt" "$WT/.aai/extended-test-only.txt" || fail TEST-002 'extended addition absent or different'
  cmp "$SOURCE/.aai/system/AAI_PIN.md" "$WT/.aai/system/AAI_PIN.md" || fail TEST-002 'installed pin differs'
  diff -rq -x cache "$SOURCE/.aai" "$WT/.aai" >/dev/null || fail TEST-002 'extended inventory differs'
  echo 'PASS: TEST-002 extended snapshot'
}

test_003_initializer() {
  new_worktree initialize_three
  printf 'origin live state sentinel\n' > "$SOURCE/docs/ai/STATE.yaml"
  seed || fail TEST-003 'seed failed'
  [[ ! -e "$WT/docs/ai/STATE.yaml" ]] || fail TEST-003 'live STATE copied before initializer'
  ([[ -n "$WT" && "$WT" = /* ]] && cd "$WT" && node .aai/scripts/check-state.mjs --repair && node .aai/scripts/check-state.mjs) || fail TEST-003 'canonical initializer/check failed'
  [[ -f "$WT/docs/ai/STATE.yaml" ]] || fail TEST-003 'state absent'
  if grep -q 'origin live state sentinel' "$WT/docs/ai/STATE.yaml"; then fail TEST-003 'origin state leaked'; fi
  echo 'PASS: TEST-003 canonical initializer'
}

test_004_safety() {
  new_worktree safety_four
  refuses TEST-004 ROOT_OVERLAP node "$SEED" --source "$SOURCE" --target "$SOURCE"
  run mkdir -p "$SCRATCH/foreign"
  run git -C "$SCRATCH/foreign" init -q
  refuses TEST-004 FOREIGN_WORKTREE node "$SEED" --source "$SOURCE" --target "$SCRATCH/foreign"
  run mkdir -p "$SOURCE/nested"
  refuses TEST-004 ROOT node "$SEED" --source "$SOURCE" --target "$SOURCE/nested"
  run mv "$SOURCE/.aai/templates/STATE_TEMPLATE.yaml" "$SCRATCH/state-template"
  refuses TEST-004 SOURCE_MISSING node "$SEED" --source "$SOURCE" --target "$WT"
  run mv "$SCRATCH/state-template" "$SOURCE/.aai/templates/STATE_TEMPLATE.yaml"
  run mkdir -p "$WT/.aai"
  run mkdir -p "$WT/.aai/AGENTS.md"
  refuses TEST-004 DESTINATION_TYPE node "$SEED" --source "$SOURCE" --target "$WT"
  run rmdir "$WT/.aai/AGENTS.md"
  run rmdir "$WT/.aai"
  run ln -s "$SCRATCH" "$WT/.aai"
  refuses TEST-004 SYMLINK node "$SEED" --source "$SOURCE" --target "$WT"
  run rm "$WT/.aai"
  run mv "$SOURCE/.agents" "$SCRATCH/source-agents"
  run ln -s "$SCRATCH/source-agents" "$SOURCE/.agents"
  refuses TEST-004 SYMLINK node "$SEED" --source "$SOURCE" --target "$WT"
  run rm "$SOURCE/.agents"
  run mv "$SCRATCH/source-agents" "$SOURCE/.agents"
  [[ ! -e "$WT/.aai/scripts/check-state.mjs" ]] || fail TEST-004 'wrote after refusal'

  local registered_template="$SCRATCH/registered-template"
  local unregistered_copy="$SCRATCH/unregistered-copy"
  run git -C "$SOURCE" worktree add -q -b registered_template "$registered_template" main
  run cp -R "$registered_template" "$unregistered_copy"
  refuses TEST-004 NOT_REGISTERED node "$SEED" --source "$SOURCE" --target "$unregistered_copy"

  local unavailable="$SCRATCH/temporarily-unavailable"
  local unavailable_moved="$SCRATCH/temporarily-unavailable.moved"
  run git -C "$SOURCE" worktree add -q -b unavailable_sibling "$unavailable" main
  run mv "$unavailable" "$unavailable_moved"
  refuses TEST-004 ENOENT node "$SEED" --source "$SOURCE" --target "$unavailable"
  [[ ! -e "$unavailable" ]] || fail TEST-004 'unavailable registered target was recreated'
  if ! seed; then
    mv "$unavailable_moved" "$unavailable"
    fail TEST-004 'unavailable unrelated registered worktree blocked valid target'
  fi
  run mv "$unavailable_moved" "$unavailable"
  [[ -f "$WT/.aai/scripts/check-state.mjs" ]] || fail TEST-004 'valid target was not seeded with unavailable sibling'

  # A real EACCES must not be confused with the ENOENT case above. Register the
  # unreadable sibling before a fresh valid target so membership scans encounter
  # it first. Privileged runners can bypass mode 000; prove the control or emit a
  # visible platform skip instead of turning that bypass into false-green proof.
  local blocked_parent="$SCRATCH/000-inaccessible"
  local unreadable="$blocked_parent/sibling"
  run mkdir -p "$blocked_parent"
  run git -C "$SOURCE" worktree add -q -b unreadable_sibling "$unreadable" main
  new_worktree permission_target
  (
    restore_unreadable_parent() { chmod 700 "$blocked_parent" >/dev/null 2>&1 || true; }
    trap restore_unreadable_parent EXIT HUP INT TERM
    run chmod 000 "$blocked_parent"
    local control_out control_rc=0
    control_out="$(node -e 'require("node:fs").realpathSync(process.argv[1])' "$unreadable" 2>&1)" || control_rc=$?
    if [[ "$control_rc" -eq 0 ]]; then
      echo 'SKIP: TEST-004 real EACCES control unavailable (mode 000 bypassed by platform privileges)'
      exit 0
    fi
    case "$control_out" in
      *EACCES*|*'permission denied'*) ;;
      *) fail TEST-004 "unreadable sibling control did not produce EACCES: $control_out" ;;
    esac
    seed || fail TEST-004 'unreadable unrelated registered worktree blocked valid target'
  )
  [[ -f "$WT/.aai/scripts/check-state.mjs" ]] || fail TEST-004 'valid target was not seeded with unreadable sibling'

  local forged="$SCRATCH/forged-after-unreadable"
  run cp -R "$registered_template" "$forged"
  refuses TEST-004 NOT_REGISTERED node "$SEED" --source "$SOURCE" --target "$forged"
  echo 'PASS: TEST-004 refusals'
}

test_005_gate() {
  new_worktree ordering_five
  gate="$SCRATCH/setup-gate.sh"
  awk '/AAI_WORKTREE_SEED_GATE_BEGIN/{on=1;next} /AAI_WORKTREE_SEED_GATE_END/{on=0} on{print}' "$ROOT/.aai/SKILL_WORKTREE.prompt.md" > "$gate"
  [[ -s "$gate" ]] || fail TEST-005 'prompt has no executable setup gate'
  printf '\nprintf "success and dispatch reached\\n" > "$AAI_TARGET_ROOT/setup-success"\n' >> "$gate"
  run mkdir -p "$WT/.aai"
  run mkdir -p "$WT/.aai/AGENTS.md"
  if AAI_SOURCE_ROOT="$SOURCE" AAI_TARGET_ROOT="$WT" bash "$gate"; then fail TEST-005 'setup continued through seed refusal'; fi
  [[ ! -e "$WT/docs/ai/STATE.yaml" ]] || fail TEST-005 'state initialized on seed refusal'
  [[ ! -e "$WT/docs/ai" ]] || fail TEST-005 'initializer path entered after seed refusal'
  [[ ! -e "$WT/setup-success" ]] || fail TEST-005 'success/dispatch reached after refusal'
  run rmdir "$WT/.aai/AGENTS.md"
  run rmdir "$WT/.aai"
  AAI_SOURCE_ROOT="$SOURCE" AAI_TARGET_ROOT="$WT" bash "$gate" || fail TEST-005 'setup gate failed success case'
  [[ -f "$WT/docs/ai/STATE.yaml" ]] || fail TEST-005 'initializer not reached'
  [[ -f "$WT/setup-success" ]] || fail TEST-005 'success/dispatch not reached after successful initialization'
  echo 'PASS: TEST-005 prompt gate'
}

test_006_tracked() {
  run git -C "$SOURCE" add -f .aai/AGENTS.md
  run git -C "$SOURCE" commit -qm 'track branch-local AAI file'
  new_worktree tracked_six
  printf 'branch-local guidance\n' > "$WT/.aai/AGENTS.md"
  run git -C "$WT" add -f .aai/AGENTS.md
  run git -C "$WT" commit -qm 'branch-local edit'
  seed || fail TEST-006 'seed refused tracked file'
  [[ "$(cat "$WT/.aai/AGENTS.md")" == 'branch-local guidance' ]] || fail TEST-006 'tracked file overwritten'
  [[ -f "$WT/.aai/scripts/check-state.mjs" ]] || fail TEST-006 'mixed root not copied'
  ([[ -n "$WT" && "$WT" = /* ]] && cd "$WT" && node .aai/scripts/check-state.mjs --repair && node .aai/scripts/check-state.mjs) || fail TEST-006 'tracked-layer initializer failed'
  echo 'PASS: TEST-006 tracked preservation'
}

test_007_ignored() {
  new_worktree ignore_seven
  run mkdir -p "$SOURCE/.aai/cache" "$SOURCE/.codex/skills.local"
  printf 'cache sentinel\n' > "$SOURCE/.aai/cache/sentinel"
  printf 'local sentinel\n' > "$SOURCE/.codex/skills.local/sentinel"
  local skill_root skill_name index=0
  for skill_root in .agents/skills .claude/skills .codex/skills .gemini/skills; do
    index=$((index + 1))
    skill_name="metadata-$index"
    run mkdir -p "$SOURCE/$skill_root/$skill_name"
    printf 'ordinary skill payload %s\n' "$index" > "$SOURCE/$skill_root/$skill_name/SKILL.md"
    if [[ $((index % 2)) -eq 0 ]]; then
      printf 'gitdir: %s\n' "$SOURCE/.git/worktrees/foreign-$index" > "$SOURCE/$skill_root/$skill_name/.git"
    else
      run mkdir -p "$SOURCE/$skill_root/$skill_name/.git"
      printf 'nested git metadata\n' > "$SOURCE/$skill_root/$skill_name/.git/config"
    fi
  done
  seed || fail TEST-007 'seed failed'
  [[ ! -e "$WT/.aai/cache/sentinel" && ! -e "$WT/.codex/skills.local/sentinel" ]] || fail TEST-007 'excluded runtime copied'
  index=0
  for skill_root in .agents/skills .claude/skills .codex/skills .gemini/skills; do
    index=$((index + 1))
    skill_name="metadata-$index"
    [[ -f "$WT/$skill_root/$skill_name/SKILL.md" ]] || fail TEST-007 "ordinary skill file missing from $skill_root"
    [[ ! -e "$WT/$skill_root/$skill_name/.git" ]] || fail TEST-007 "nested Git metadata copied from $skill_root"
  done
  run git -C "$WT" add -A
  added="$(git -C "$WT" diff --cached --name-only --diff-filter=A)"
  [[ -z "$added" ]] || fail TEST-007 "seeded additions staged: $added"
  run git -C "$WT" reset -q
  new_worktree unsafe_seven
  printf 'README.md\n' > "$WT/.gitignore"
  refuses TEST-007 IGNORE_UNSAFE node "$SEED" --source "$SOURCE" --target "$WT"
  [[ ! -e "$WT/.aai/scripts/check-state.mjs" ]] || fail TEST-007 'wrote before ignore validation'
  echo 'PASS: TEST-007 ignored-only and exclusions'
}

test_008_spaces() {
  new_worktree 'space target eight'
  seed || fail TEST-008 'seeder rejected spaced paths'
  [[ -f "$WT/.aai/scripts/check-state.mjs" ]] || fail TEST-008 'layer absent at spaced path'
  echo 'PASS: TEST-008 spaced-path seeder (native PowerShell in Pester lane)'
}

test_009_drift() {
  new_worktree drift_nine
  seed || fail TEST-009 'initial seed failed'
  before="$(shasum -a 256 "$WT/.aai/system/AAI_PIN.md")"
  seed || fail TEST-009 'identical rerun failed'
  [[ "$(shasum -a 256 "$WT/.aai/system/AAI_PIN.md")" == "$before" ]] || fail TEST-009 'identical rerun changed pin'
  printf 'origin update\n' >> "$SOURCE/.aai/system/AAI_PIN.md"
  refuses TEST-009 DESTINATION_CONFLICT node "$SEED" --source "$SOURCE" --target "$WT"
  [[ "$(shasum -a 256 "$WT/.aai/system/AAI_PIN.md")" == "$before" ]] || fail TEST-009 'origin update propagated'
  printf 'target update\n' >> "$WT/.aai/scripts/check-state.mjs"
  if grep -q 'target update' "$SOURCE/.aai/scripts/check-state.mjs"; then fail TEST-009 'target update propagated'; fi
  echo 'PASS: TEST-009 independent snapshot'
}

test_010_distribution() {
  grep -qx '  - .aai/scripts/worktree-seed.mjs' "$ROOT/.aai/system/PROFILES.yaml" || fail TEST-010 'helper absent from core profile'
  grep -q 'aai-worktree-seed:' "$ROOT/tests/skills/suite-map.yaml" || fail TEST-010 'suite not registered'
  grep -q 'worktree-lacks-vendored-aai-layer-downstream' "$ROOT/tests/skills/lib/prompt-diet-ledger.sh" || fail TEST-010 'prompt growth uncredited'
  [[ -f "$SOURCE/.aai/scripts/worktree-seed.mjs" ]] || fail TEST-010 'real core installation omitted helper'
  printf '%s\n' '.aai/scripts/worktree-seed.mjs' > "$SCRATCH/changed-paths"
  node "$ROOT/.aai/scripts/select-suites.mjs" --files-from "$SCRATCH/changed-paths" > "$SCRATCH/selection"
  grep -q 'aai-worktree-seed' "$SCRATCH/selection" || fail TEST-010 'helper does not select its regression suite'
  echo 'PASS: TEST-010 distribution contracts'
}

test_011_subdirectory_source_root() {
  local capture subdir resolved
  capture="$(grep -E '^   AAI_SOURCE_ROOT=' "$ROOT/.aai/SKILL_WORKTREE.prompt.md" | sed 's/^   //' | head -1)"
  [[ -n "$capture" ]] || fail TEST-011 'Bash source-root capture absent from prompt'
  subdir="$SOURCE/nested/setup-directory"
  run mkdir -p "$subdir"
  resolved="$(cd "$subdir" && eval "$capture" && printf '%s' "$AAI_SOURCE_ROOT")"
  [[ "$(cd "$resolved" && pwd -P)" == "$(cd "$SOURCE" && pwd -P)" ]] \
    || fail TEST-011 "Bash setup from a subdirectory resolved source as $resolved"
  grep -qF '$AaiSourceRoot = (Resolve-Path -LiteralPath (& git rev-parse --show-toplevel)).Path' "$ROOT/.aai/SKILL_WORKTREE.prompt.md" \
    || fail TEST-011 'PowerShell source-root capture does not use the Git top level'
  echo 'PASS: TEST-011 subdirectory source root'
}

case "$SELECTED" in
  '') test_001_core; test_002_extended; test_003_initializer; test_004_safety; test_005_gate; test_006_tracked; test_007_ignored; test_008_spaces; test_009_drift; test_010_distribution; test_011_subdirectory_source_root ;;
  TEST-001|test_001_core) test_001_core ;;
  TEST-002|test_002_extended) test_002_extended ;;
  TEST-003|test_003_initializer) test_003_initializer ;;
  TEST-004|test_004_safety) test_004_safety ;;
  TEST-005|test_005_gate) test_005_gate ;;
  TEST-006|test_006_tracked) test_006_tracked ;;
  TEST-007|test_007_ignored) test_007_ignored ;;
  TEST-008|test_008_spaces) test_008_spaces ;;
  TEST-009|test_009_drift) test_009_drift ;;
  TEST-010|test_010_distribution) test_010_distribution ;;
  TEST-011|test_011_subdirectory_source_root) test_011_subdirectory_source_root ;;
  *) fail SELECTOR "unknown test $SELECTED" ;;
esac
