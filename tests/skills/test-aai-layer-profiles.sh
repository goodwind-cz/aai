#!/usr/bin/env bash
#
# Test: vendored-layer core/extended profiles (CHANGE layer-profiles /
# SPEC spec-layer-profiles)
#
# Verifies .aai/system/PROFILES.yaml (100% classification of the vendored
# .aai tree, conformance against the LIVE tree), aai-sync.sh/.ps1
# --profile core|extended (default extended, byte-identical to the
# pre-change sync; core = exactly the core set; sticky pin resolution;
# prune with target-only preservation; idempotence), the AAI_PIN
# `- Profile:` stamp, and the SKILL_DOCTOR CAT-13 profile display.
# Implements TEST-001..TEST-008 from the frozen spec.
#
# ZERO REAL NETWORK: fixture sources are local `git init` copies of this
# repository's distribution surfaces; the only remote strings are
# non-routable example.invalid placeholders (never contacted).
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-layer-profiles"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/pipe-safe.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
SYNC_SH="$PROJECT_ROOT/.aai/scripts/aai-sync.sh"
SYNC_PS1="$PROJECT_ROOT/.aai/scripts/aai-sync.ps1"
DOCTOR_PROMPT="$PROJECT_ROOT/.aai/SKILL_DOCTOR.prompt.md"
DOCTOR_SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-doctor.mjs"
PIN_CONTRACT="$PROJECT_ROOT/.aai/system/AAI_PIN.md"

TMP_ROOT=""
FIX_SRC=""       # fixture source with the NEW (working-tree) engine
FIX_SRC_OLD=""   # identical tree, but HEAD's (pre-change) aai-sync.sh engine

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixtures under $TMP_ROOT"
    return 0
  fi
  if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

# Spec-AC-02 / D2: an assertion that fires on a payload rendering as zero
# visible lines (e.g. a lone newline or whitespace byte — non-empty as a
# string, invisible when printed) must dump that payload byte for byte
# instead of silently printing what looks like an empty list. This is the
# exact shape CI run 34737181188 produced: `[[ -z "$missing" ]]` was false on
# a value with no visible lines.
assert_list_empty() {
  local val="$1" msg="$2"
  [[ -z "$val" ]] && return 0
  if [[ -z "$(printf '%s' "$val" | tr -d '[:space:]')" ]]; then
    log_fail "$msg (payload is non-empty but renders as zero visible lines — byte dump follows):"$'\n'"$(printf '%s' "$val" | od -c | qhead -20)"
  fi
  log_fail "$msg:"$'\n'"$val"
}

# Spec-AC-02 / D2: a `--profile core` sync's own "missing in source" WARN
# line (aai-sync.sh:297) must be captured and failed on directly, rather than
# discarded to /dev/null and left to surface only as a downstream
# missing-file set two tests later (or not at all, if nothing else notices).
sync_output_ok() {
  # Pipe-free membership check (spec-assertions-must-not-die-on-their-own-payload):
  # piping a large captured payload into `grep -q` can take SIGPIPE past the
  # 64 KiB pipe buffer, turning a MATCHED payload into a false "not found"
  # under `set -o pipefail`. `case` pattern matching has no pipe.
  case "$1" in
    *'missing in source'*) return 1 ;;
    *) return 0 ;;
  esac
}

run_sync_or_fail() {
  local desc="$1"; shift
  local out rc=0
  out="$(bash "$@" 2>&1)" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_fail "$desc (exit $rc): $out"
  fi
  if ! sync_output_ok "$out"; then
    log_fail "$desc: sync reported a 'missing in source' WARN it should never hit against this fixture:"$'\n'"$(printf '%s\n' "$out" | grep 'missing in source')"
  fi
}

# Extract one profile's path list from a PROFILES.yaml (line-based, no yaml lib —
# the same discipline the sync scripts use).
profile_list() {
  local manifest="$1" key="$2"
  awk -v key="$2:" '
    $0 == key { f = 1; next }
    /^[^ ]/   { f = 0 }
    f && sub(/^  - /, "") { sub(/[ \t\r]+$/, ""); print }
  ' "$manifest"
}

digest_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then echo "sha256sum"
  else echo "shasum -a 256"; fi
}

# Content manifest of a target tree, excluding .git, the volatile pin, and
# docs/ai/reports/ (the sync's timestamp-named runtime advisories — emitted
# identically by old and new engines on every fresh sync, pre-existing
# behavior; runtime evidence, not vendored content).
tree_manifest() {
  local root="$1"
  (
    cd "$root"
    find . -type f ! -path './.git/*' ! -path './.aai/system/AAI_PIN.md' \
      ! -path './docs/ai/reports/*' -print0 |
      LC_ALL=C sort -z | xargs -0 $(digest_cmd) 2>/dev/null
  )
}

# .aai file listing (repo-relative), excluding runtime cache.
aai_files_of() {
  (cd "$1" && find .aai -type f ! -path '.aai/cache/*' | LC_ALL=C sort)
}

# Pin content minus volatile lines (source path, commit, timestamp differ per
# fixture/run by construction).
pin_stable() {
  tr -d '\r' < "$1" | grep -v -e '^- Source path: ' -e '^- Template commit: ' -e '^- Synced at (UTC): '
}

new_target() {
  local t="$1"
  mkdir -p "$t"
  git -C "$t" init -q -b main
}

check_deps() {
  log_info "Checking dependencies..."
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  command -v awk >/dev/null 2>&1 || log_skip "awk not found"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-layer-profiles-test.XXXXXX")"
  log_pass "Dependencies checked"
}

# Spec-AC-01 / D2: every `cp -R` the fixture build issues is checked, and a
# failure names both sides of the copy instead of aborting on a bare `set -e`
# trace. `AAI_TEST_LP_CP_FAIL_ITEM` is a test-only hook (unset in every real
# run) that forces one named item's copy to fail against a real, nonexistent
# source path — a genuine cp failure, not a mock.
copy_fixture_item() {
  local item="$1" src="$2" dst="$3"
  if [[ -n "${AAI_TEST_LP_CP_FAIL_ITEM:-}" && "$item" == "${AAI_TEST_LP_CP_FAIL_ITEM}" ]]; then
    src="$src/__aai_test_forced_missing__"
  fi
  cp -R "$src" "$dst" || log_fail "fixture build: cp -R failed copying '$item' from $src to $dst"
}

# Repo-relative file listing under <root>/<item> (same idiom as aai_files_of /
# tree_manifest above: the `cd` lives inside this function's OWN subshell, not
# textually inside a `$(...)` command substitution at the call site — the
# shape the repo's cd-subshell-leak ratchet counts).
find_files_relative() {
  local root="$1" item="$2"
  ( cd "$root" 2>/dev/null && find "$item" -type f ! -path '.aai/cache/*' 2>/dev/null | LC_ALL=C sort )
}

# Spec-AC-01 / D2: after every copy, compare the file set the build PRODUCED
# against the file set it copied FROM, and exit non-zero naming every path
# that is missing — before any assertion (TEST-001 etc.) runs. A `cp -R` that
# succeeds INCOMPLETELY used to be invisible; this makes it loud.
verify_fixture_copy_completeness() {
  local item missing_all=""
  for item in .aai CLAUDE.md CODEX.md GEMINI.md SKILLS.md README.md hooks \
              .claude .codex .gemini .cursor .claude-plugin docs/knowledge; do
    [[ -e "$PROJECT_ROOT/$item" ]] || continue
    local src_files dst_files missing
    src_files="$(find_files_relative "$PROJECT_ROOT" "$item")"
    dst_files="$(find_files_relative "$FIX_SRC" "$item")"
    missing="$(comm -23 <(printf '%s\n' "$src_files") <(printf '%s\n' "$dst_files"))"
    [[ -z "$missing" ]] || missing_all="${missing_all}${missing}"$'\n'
  done
  [[ -z "$missing_all" ]] || log_fail "fixture build incomplete: files copied from the project root but missing under $FIX_SRC:"$'\n'"$missing_all"
}

# Copy this repo's distribution surfaces into a fixture source and git-init it.
build_fixture_sources() {
  log_info "Building fixture sources (real distribution tree, no network)..."
  FIX_SRC="$TMP_ROOT/src-new"
  mkdir -p "$FIX_SRC"
  local item
  for item in .aai CLAUDE.md CODEX.md GEMINI.md SKILLS.md README.md hooks \
              .claude .codex .gemini .cursor .claude-plugin; do
    if [[ -e "$PROJECT_ROOT/$item" ]]; then
      copy_fixture_item "$item" "$PROJECT_ROOT/$item" "$FIX_SRC/$item"
    fi
  done
  mkdir -p "$FIX_SRC/.github" "$FIX_SRC/docs/knowledge"
  [[ -f "$PROJECT_ROOT/.github/copilot-instructions.md" ]] &&
    cp "$PROJECT_ROOT/.github/copilot-instructions.md" "$FIX_SRC/.github/"
  if [[ -d "$PROJECT_ROOT/docs/knowledge" ]]; then
    copy_fixture_item "docs/knowledge" "$PROJECT_ROOT/docs/knowledge/." "$FIX_SRC/docs/knowledge/"
  fi
  rm -rf "$FIX_SRC/.aai/cache"

  # Test-only fault injection (unset in every real run): simulate a copy that
  # succeeded but was INCOMPLETE, to prove the completeness check below
  # actually catches it (Spec-AC-01, TEST-401).
  if [[ -n "${AAI_TEST_LP_DROP_FILE:-}" ]]; then
    rm -f "$FIX_SRC/${AAI_TEST_LP_DROP_FILE}"
  fi
  verify_fixture_copy_completeness

  git -C "$FIX_SRC" init -q -b main
  git -C "$FIX_SRC" config user.email "test@example.invalid"
  git -C "$FIX_SRC" config user.name "AAI Test"
  git -C "$FIX_SRC" remote add origin "https://example.invalid/goodwind-cz/aai.git"
  git -C "$FIX_SRC" add -A
  git -C "$FIX_SRC" commit -qm "fixture source (new engine)"

  # Identical tree, but the ENGINE we run is the PRE-PROFILE aai-sync.sh. While
  # the layer-profiles change was unmerged this was simply HEAD (working tree =
  # new engine, HEAD = old); once #84 merged, HEAD IS the profile engine and a
  # HEAD baseline makes this test a no-op (empty pin diff). Pin the baseline
  # durably to the PARENT of the commit that introduced profile support — the
  # oldest commit touching the `PROFILES.yaml` marker in this file — so the
  # "default == pre-profile behavior" guarantee stays provable as HEAD advances.
  FIX_SRC_OLD="$TMP_ROOT/src-old"
  cp -R "$FIX_SRC" "$FIX_SRC_OLD"
  rm -rf "$FIX_SRC_OLD/.git"
  local profile_intro
  profile_intro="$(git -C "$PROJECT_ROOT" log --reverse --format='%H' -S 'PROFILES.yaml' -- .aai/scripts/aai-sync.sh | qhead -1)"
  [[ -n "$profile_intro" ]] || log_fail "cannot locate the commit that introduced profile support in aai-sync.sh"
  git -C "$PROJECT_ROOT" show "${profile_intro}^:.aai/scripts/aai-sync.sh" > "$FIX_SRC_OLD/.aai/scripts/aai-sync.sh" \
    || log_fail "cannot extract pre-profile aai-sync.sh at ${profile_intro}^ (shallow clone missing history?)"
  git -C "$FIX_SRC_OLD" init -q -b main
  git -C "$FIX_SRC_OLD" config user.email "test@example.invalid"
  git -C "$FIX_SRC_OLD" config user.name "AAI Test"
  git -C "$FIX_SRC_OLD" remote add origin "https://example.invalid/goodwind-cz/aai.git"
  git -C "$FIX_SRC_OLD" add -A
  git -C "$FIX_SRC_OLD" commit -qm "fixture source (old engine)"
  log_pass "Fixture sources built"
}

# --- TEST-001 — manifest classifies 100% of the LIVE .aai tree (Spec-AC-01) ---
test_manifest_conformance() {
  log_info "TEST-001: PROFILES.yaml exists and classifies 100% of .aai (live tree)..."
  [[ -f "$MANIFEST" ]] || log_fail "manifest not found: $MANIFEST"

  local core extended listed actual dupes overlap
  core="$(profile_list "$MANIFEST" core)"
  extended="$(profile_list "$MANIFEST" extended)"
  [[ -n "$core" ]] || log_fail "manifest has no core entries"
  [[ -n "$extended" ]] || log_fail "manifest has no extended entries"

  listed="$(printf '%s\n%s\n' "$core" "$extended" | LC_ALL=C sort)"
  actual="$(cd "$PROJECT_ROOT" && find .aai -type f ! -path '.aai/cache/*' | LC_ALL=C sort)"

  dupes="$(printf '%s\n' "$listed" | uniq -d)"
  assert_list_empty "$dupes" "duplicate/overlapping manifest entries"
  overlap="$(comm -12 <(printf '%s\n' "$core" | LC_ALL=C sort) <(printf '%s\n' "$extended" | LC_ALL=C sort))"
  assert_list_empty "$overlap" "paths listed in BOTH profiles"

  local unclassified stale
  unclassified="$(comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$listed"))"
  assert_list_empty "$unclassified" "UNCLASSIFIED vendored files (add to PROFILES.yaml)"
  stale="$(comm -13 <(printf '%s\n' "$actual") <(printf '%s\n' "$listed"))"
  assert_list_empty "$stale" "stale manifest entries (no such file)"

  local n_core n_ext n_all
  n_core="$(printf '%s\n' "$core" | grep -c .)"
  n_ext="$(printf '%s\n' "$extended" | grep -c .)"
  n_all="$(printf '%s\n' "$actual" | grep -c .)"
  [[ $((n_core + n_ext)) -eq "$n_all" ]] || log_fail "count mismatch: core($n_core)+extended($n_ext) != tree($n_all)"
  assert_payload_has_line "$core" ".aai/system/PROFILES.yaml" "PROFILES.yaml must classify itself as core"
  log_pass "TEST-001 manifest conformance: core=$n_core extended=$n_ext total=$n_all (100%)"
}

# --- TEST-009L (spec TEST-009L, Spec-AC-21) — the three dispatch-state-sweep
# .aai files are classified, each in exactly one list. TEST-001 above already
# proves the whole-tree union (these three files are part of "actual"), so
# this narrows to the three files this scope adds, named individually so a
# regression on any ONE of them is legible on its own (M39).
test_new_files_classified() {
  log_info "TEST-009L: lib/iso-time.mjs, watch-ci.mjs and check-dispatch-text.mjs are each classified in exactly one profile list..."
  [[ -f "$MANIFEST" ]] || log_fail "TEST-009L: manifest not found: $MANIFEST"
  local core extended
  core="$(profile_list "$MANIFEST" core)"
  extended="$(profile_list "$MANIFEST" extended)"
  local f n_core n_ext
  for f in .aai/scripts/lib/iso-time.mjs .aai/scripts/watch-ci.mjs .aai/scripts/check-dispatch-text.mjs; do
    [[ -f "$PROJECT_ROOT/$f" ]] || log_fail "TEST-009L: $f does not exist on disk"
    n_core="$(printf '%s\n' "$core" | grep -cFx "$f")" || true
    n_ext="$(printf '%s\n' "$extended" | grep -cFx "$f")" || true
    [[ $((n_core + n_ext)) -eq 1 ]] \
      || log_fail "TEST-009L: $f must be classified in EXACTLY ONE of core/extended, found core=$n_core extended=$n_ext"
  done
  log_pass "TEST-009L: iso-time.mjs, watch-ci.mjs and check-dispatch-text.mjs each classified exactly once"
}

# --- TEST-488 (spec-mutation-gate-for-tests Spec-AC-18) — the mutation-gate
# scripts existing so far are each classified exactly once. TEST-001 above
# already proves the whole-tree union (these files are part of "actual");
# this narrows to the files THIS scope adds, named individually (same
# precedent as TEST-009L above). lib/spec-contract-hash.mjs is a LATER run's
# file (not yet on disk) and is deliberately absent from this list — see the
# spec's own D17.
test_488_mutation_gate_files_classified() {
  log_info "TEST-488: mutation-run.mjs, mutation-gate.mjs and lib/mutation-record.mjs are each classified in exactly one profile list..."
  [[ -f "$MANIFEST" ]] || log_fail "TEST-488: manifest not found: $MANIFEST"
  local core extended
  core="$(profile_list "$MANIFEST" core)"
  extended="$(profile_list "$MANIFEST" extended)"
  local f n_core n_ext
  for f in .aai/scripts/mutation-run.mjs .aai/scripts/mutation-gate.mjs .aai/scripts/lib/mutation-record.mjs; do
    [[ -f "$PROJECT_ROOT/$f" ]] || log_fail "TEST-488: $f does not exist on disk"
    n_core="$(printf '%s\n' "$core" | grep -cFx "$f")" || true
    n_ext="$(printf '%s\n' "$extended" | grep -cFx "$f")" || true
    [[ $((n_core + n_ext)) -eq 1 ]] \
      || log_fail "TEST-488: $f must be classified in EXACTLY ONE of core/extended, found core=$n_core extended=$n_ext"
    [[ "$n_core" -eq 1 ]] \
      || log_fail "TEST-488: $f must be classified as CORE (a gate, per the classification rule) — found core=$n_core extended=$n_ext"
  done
  log_pass "TEST-488: mutation-run.mjs, mutation-gate.mjs and lib/mutation-record.mjs each classified exactly once, as core"
}

# --- TEST-002 — default run byte-identical to the pre-change sync (Spec-AC-02) -
test_default_byte_identity() {
  log_info "TEST-002: flag-less run byte-identical to HEAD engine; --profile extended == default..."
  local t_old="$TMP_ROOT/t-old" t_new="$TMP_ROOT/t-new" t_ext="$TMP_ROOT/t-ext"
  new_target "$t_old"; new_target "$t_new"; new_target "$t_ext"

  run_sync_or_fail "old-engine sync failed" "$FIX_SRC_OLD/.aai/scripts/aai-sync.sh" "$t_old"
  run_sync_or_fail "new-engine default sync failed" "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t_new"
  run_sync_or_fail "--profile extended sync failed" "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t_ext" --profile extended

  # (a) default == --profile extended, byte-for-byte apart from pin timestamp.
  diff <(tree_manifest "$t_new") <(tree_manifest "$t_ext") >/dev/null \
    || log_fail "default and --profile extended trees differ"
  diff <(pin_stable "$t_new/.aai/system/AAI_PIN.md") <(pin_stable "$t_ext/.aai/system/AAI_PIN.md") >/dev/null \
    || log_fail "default and --profile extended pins differ beyond volatile lines"

  # (b) new default vs OLD engine: identical trees except the engine's own file.
  # (docs/ai/reports sync-conflict advisories are timestamp-named runtime
  # evidence emitted identically by both engines — excluded, see tree_manifest.)
  # docs/ai/update-config.yaml (CHANGE seed-update-config) and
  # docs/ai/docs-audit.yaml (CHANGE-0121) are seed-when-missing files added
  # AFTER the pre-profile OLD engine, so the OLD engine never emits them —
  # legitimate additive seeds, excluded from this profile-refactor copy-set
  # invariant just like the TECHNOLOGY.md seed predates them in both.
  # .agents/skills is the same case: the mirror Gemini CLI / Cursor read as
  # their primary discovery path, added to the sync copy set AFTER the
  # pre-profile OLD engine (fix(harness): aai-sync manages the .agents/skills
  # mirror), so it too is a legitimate additive copy the OLD engine never emits.
  local differing
  differing="$(diff -rq "$t_old" "$t_new" 2>/dev/null | grep -v '/\.git' | grep -v 'docs/ai/reports' | grep -v 'update-config.yaml' | grep -v 'docs-audit.yaml' | grep -v '\.agents' | grep '^Files ' | awk '{print $2}' | sed "s|^$t_old/||" || true)"
  local allowed=".aai/scripts/aai-sync.sh
.aai/system/AAI_PIN.md"
  local unexpected
  unexpected="$(comm -23 <(printf '%s\n' "$differing" | LC_ALL=C sort) <(printf '%s\n' "$allowed" | LC_ALL=C sort))"
  [[ -z "$unexpected" ]] || log_fail "default run NOT byte-identical to pre-change sync; unexpected diffs:"$'\n'"$unexpected"
  # Paths present in one target only (excluding .git, runtime reports, the
  # post-profile update-config / docs-audit seeds, and the post-profile
  # .agents/skills mirror) would be a copy-set change.
  local only
  only="$(diff -rq "$t_old" "$t_new" 2>/dev/null | grep -v '/\.git' | grep -v 'docs/ai/reports' | grep -v 'update-config.yaml' | grep -v 'docs-audit.yaml' | grep -v '\.agents' | grep '^Only in ' || true)"
  [[ -z "$only" ]] || log_fail "default run changed the copied file SET vs pre-change sync:"$'\n'"$only"

  # (c) the pin diff is EXACTLY the additive documented Profile line.
  local pin_added
  pin_added="$(diff <(pin_stable "$t_old/.aai/system/AAI_PIN.md") <(pin_stable "$t_new/.aai/system/AAI_PIN.md") | grep '^[<>]' || true)"
  [[ "$pin_added" == "> - Profile: extended" ]] \
    || log_fail "pin diff vs pre-change sync must be exactly '> - Profile: extended', got:"$'\n'"$pin_added"
  log_pass "TEST-002 default run byte-identical (engine file + documented pin line only)"
}

# --- TEST-003 — --profile core copies exactly the core set (Spec-AC-02) -------
test_core_exact_set() {
  log_info "TEST-003: --profile core installs exactly the manifest core set..."
  local t_core="$TMP_ROOT/t-core"
  new_target "$t_core"
  run_sync_or_fail "--profile core sync failed" "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t_core" --profile core

  local want got
  want="$(profile_list "$FIX_SRC/.aai/system/PROFILES.yaml" core | LC_ALL=C sort)"
  got="$(aai_files_of "$t_core")"
  local missing extra
  missing="$(comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$got"))"
  extra="$(comm -13 <(printf '%s\n' "$want") <(printf '%s\n' "$got"))"
  assert_list_empty "$missing" "core sync MISSING core-listed files"
  assert_list_empty "$extra" "core sync copied files beyond the core set"
  [[ -f "$t_core/.aai/PLANNING.prompt.md" ]] || log_fail "workflow engine file absent from core install"
  [[ ! -f "$t_core/.aai/SKILL_DASHBOARD.prompt.md" ]] || log_fail "extended-only prompt leaked into core install"
  # Non-.aai surfaces are profile-independent (D3): shims/hooks/wrappers still land.
  [[ -f "$t_core/CLAUDE.md" && -d "$t_core/hooks" ]] || log_fail "profile-independent surfaces missing in core install"
  log_pass "TEST-003 core = exact manifest set (two-way)"
}

# --- TEST-004 — extended->core prune, target-only preserved, idempotent -------
test_core_prune_and_idempotence() {
  log_info "TEST-004: extended->core re-sync prunes; target-only script preserved; core re-run idempotent..."
  local t="$TMP_ROOT/t-downgrade"
  new_target "$t"
  run_sync_or_fail "seed extended sync failed" "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t"
  [[ -f "$t/.aai/SKILL_DASHBOARD.prompt.md" ]] || log_fail "seed extended install incomplete"
  echo "#!/usr/bin/env bash" > "$t/.aai/scripts/project-custom.sh"

  run_sync_or_fail "core re-sync over extended target failed" "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t" --profile core
  [[ ! -f "$t/.aai/SKILL_DASHBOARD.prompt.md" ]] || log_fail "extended-only file survived core re-sync (no prune)"
  [[ ! -f "$t/.aai/scripts/generate-dashboard.mjs" ]] || log_fail "extended-only script survived core re-sync"
  [[ -f "$t/.aai/scripts/project-custom.sh" ]] || log_fail "target-only script was NOT preserved by core prune"

  local snap1 snap2
  snap1="$(tree_manifest "$t")"
  local pin1; pin1="$(pin_stable "$t/.aai/system/AAI_PIN.md")"
  run_sync_or_fail "second core sync failed" "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t" --profile core
  snap2="$(tree_manifest "$t")"
  local pin2; pin2="$(pin_stable "$t/.aai/system/AAI_PIN.md")"
  # fu-sync-hash-compare-fails-open: a hash-pipeline hiccup used to take the
  # copilot merge branch and plant this directory. Pin it so a regression is
  # named, not just "tree changed".
  [[ ! -e "$t/docs/ai/project-overrides" ]] \
    || log_fail "core re-sync planted docs/ai/project-overrides (hash-compare fail-open)"
  if [[ "$snap1" != "$snap2" ]]; then
    log_fail "core sync not idempotent (tree changed on second run):"$'\n'"$(diff -u <(printf '%s\n' "$snap1") <(printf '%s\n' "$snap2") || true)"
  fi
  [[ "$pin1" == "$pin2" ]] || log_fail "core sync not idempotent (pin changed beyond volatile lines)"
  log_pass "TEST-004 prune + preserve + real idempotence probe"
}

# --- TEST-005 — invalid profile fails fast, target untouched (Spec-AC-02) -----
test_invalid_profile() {
  log_info "TEST-005: --profile bogus fails fast without touching the target..."
  local t="$TMP_ROOT/t-invalid" out rc
  mkdir -p "$t"
  set +e
  out="$(bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t" --profile bogus 2>&1)"; rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || log_fail "--profile bogus must fail (got exit 0)"
  assert_payload_contains_i "$out" "profile" "error must name the profile flag, got: $out"
  [[ ! -d "$t/.aai" ]] || log_fail "invalid profile run must not create .aai in the target"
  set +e
  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t" --profile >/dev/null 2>&1; rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || log_fail "--profile without a value must fail"

  # Review F1 regression: a target path containing glob metacharacters must
  # not break the prefix-strip and mass-delete the just-copied core layer.
  # Pre-fix `${tgt#$DST_ROOT/}` glob-interpreted DST_ROOT, leaving rel absolute
  # so the prune loop deleted every core file (only the pin survived).
  local tb="$TMP_ROOT/t-bracket[1]"
  mkdir -p "$tb"
  run_sync_or_fail "core sync into a bracket-path target failed" "$FIX_SRC/.aai/scripts/aai-sync.sh" "$tb" --profile core
  local n; n="$(find "$tb/.aai" -type f | wc -l | tr -d ' ')"
  [[ "$n" -gt 50 ]] || log_fail "F1: bracket-path core sync left only $n .aai files (mass-delete regression)"
  [[ -f "$tb/.aai/scripts/state.mjs" ]] || log_fail "F1: core file state.mjs missing after bracket-path sync"

  log_pass "TEST-005 invalid profile fails fast, target untouched; bracket-path core sync intact (F1)"
}

# --- TEST-006 — pin stamp + sticky flag-less re-sync (Spec-AC-03) -------------
test_pin_stamp_and_sticky() {
  log_info "TEST-006: pin records the profile; flag-less re-sync honors the sticky pin..."
  local t="$TMP_ROOT/t-sticky"
  new_target "$t"
  run_sync_or_fail "core sync failed" "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t" --profile core
  grep -q '^- Profile: core$' "$t/.aai/system/AAI_PIN.md" \
    || log_fail "pin lacks '- Profile: core':"$'\n'"$(cat "$t/.aai/system/AAI_PIN.md")"

  run_sync_or_fail "flag-less re-sync failed" "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t"
  grep -q '^- Profile: core$' "$t/.aai/system/AAI_PIN.md" \
    || log_fail "flag-less re-sync lost the sticky core profile (pin now: $(grep '^- Profile:' "$t/.aai/system/AAI_PIN.md" || echo '<absent>'))"
  [[ ! -f "$t/.aai/SKILL_DASHBOARD.prompt.md" ]] \
    || log_fail "flag-less re-sync reinstalled the extended layer over a core target"

  # Explicit upgrade still works: core -> extended by flag.
  run_sync_or_fail "core->extended upgrade failed" "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t" --profile extended
  grep -q '^- Profile: extended$' "$t/.aai/system/AAI_PIN.md" || log_fail "upgrade did not restamp pin to extended"
  [[ -f "$t/.aai/SKILL_DASHBOARD.prompt.md" ]] || log_fail "upgrade did not reinstall extended files"
  # Pin contract documents the field.
  grep -q 'Profile' "$PIN_CONTRACT" || log_fail ".aai/system/AAI_PIN.md contract does not document the Profile field"
  log_pass "TEST-006 pin stamp + sticky resolution + explicit upgrade"
}

# --- TEST-007 — SKILL_DOCTOR CAT-13 displays the profile (Spec-AC-03) ---------
# CHANGE-0079 / spec-doctor-determinize moved the profile-display mechanics
# into aai-doctor.mjs (readProfileFromPin + catLayerDrift); the prompt is now
# a thin wrapper that just relays the script's CAT-13 line verbatim.
test_doctor_display() {
  log_info "TEST-007: aai-doctor.mjs CAT-13 reads and displays the layer profile..."
  [[ -f "$DOCTOR_SCRIPT" ]] || log_fail "doctor script not found: $DOCTOR_SCRIPT"
  grep -q "Profile" "$DOCTOR_SCRIPT" || log_fail "aai-doctor.mjs does not read the pin's '- Profile:' line"
  grep -qi 'extended (implicit)' "$DOCTOR_SCRIPT" || log_fail "aai-doctor.mjs lacks the absent->extended (implicit) rule"
  # Behavioral pin only — never grep the JS source for a template literal
  # (a behavior-preserving refactor must not break this test; review PR #178).
  node "$DOCTOR_SCRIPT" 2>&1 | grep '^CAT-13' | qgrep -q 'profile:' \
    || log_fail "live CAT-13 output line does not contain 'profile:'"
  log_pass "TEST-007 doctor CAT-13 profile display"
}

# --- TEST-008 — ps1 parity: parse + structure + end-to-end (Spec-AC-02) -------
test_ps1_parity() {
  log_info "TEST-008: aai-sync.ps1 parity (structural + end-to-end when pwsh present)..."
  [[ -f "$SYNC_PS1" ]] || log_fail "aai-sync.ps1 not found"
  # Structural parity of the filter logic (both engines carry the same seams).
  grep -q '\$Profile' "$SYNC_PS1" || log_fail "ps1 lacks a Profile parameter"
  grep -q 'PROFILES.yaml' "$SYNC_PS1" || log_fail "ps1 does not read PROFILES.yaml"
  grep -q -- '- Profile: ' "$SYNC_PS1" || log_fail "ps1 does not stamp '- Profile:' into the pin"
  grep -q 'PROFILE prune' "$SYNC_PS1" || log_fail "ps1 lacks the prune message seam"
  grep -q 'PRESERVE target-only script' "$SYNC_PS1" || log_fail "ps1 lacks target-only preservation"
  grep -q 'PROFILE prune' "$SYNC_SH" || log_fail "sh lacks the prune message seam (structural diff broken)"

  if ! command -v pwsh >/dev/null 2>&1; then
    log_info "TEST-008 note: pwsh absent — structural parity only (end-to-end + parse skipped)"
    log_pass "TEST-008 ps1 structural parity"
    return 0
  fi

  # Parse gate (same class test-ps1-quality.sh runs repo-wide).
  pwsh -NoProfile -Command '
    $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile("'"$FIX_SRC"'/.aai/scripts/aai-sync.ps1", [ref]$null, [ref]$errs) | Out-Null
    if ($errs -and $errs.Count) { $errs | ForEach-Object { Write-Output $_.Message }; exit 1 }
  ' || log_fail "aai-sync.ps1 has parse errors"

  # End-to-end: ps1 core run produces the same .aai file set as the sh core run.
  local t_sh="$TMP_ROOT/t-par-sh" t_ps="$TMP_ROOT/t-par-ps"
  new_target "$t_sh"; new_target "$t_ps"
  run_sync_or_fail "sh core run failed" "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t_sh" --profile core
  pwsh -NoProfile -File "$FIX_SRC/.aai/scripts/aai-sync.ps1" -TargetRoot "$t_ps" -Profile core >/dev/null 2>&1 \
    || log_fail "ps1 core run failed"
  diff <(aai_files_of "$t_sh") <(aai_files_of "$t_ps") >/dev/null \
    || log_fail "ps1 core install file set differs from sh:"$'\n'"$(diff <(aai_files_of "$t_sh") <(aai_files_of "$t_ps") || true)"
  grep -q '^- Profile: core$' "$t_ps/.aai/system/AAI_PIN.md" || log_fail "ps1 pin lacks Profile stamp"

  # ps1 default run stays extended (full set parity with sh default).
  local t_ps_def="$TMP_ROOT/t-par-ps-def" t_sh_def="$TMP_ROOT/t-par-sh-def"
  new_target "$t_ps_def"; new_target "$t_sh_def"
  run_sync_or_fail "sh default run failed" "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t_sh_def"
  pwsh -NoProfile -File "$FIX_SRC/.aai/scripts/aai-sync.ps1" -TargetRoot "$t_ps_def" >/dev/null 2>&1 \
    || log_fail "ps1 default run failed"
  diff <(aai_files_of "$t_sh_def") <(aai_files_of "$t_ps_def") >/dev/null \
    || log_fail "ps1 default install file set differs from sh default"
  grep -q '^- Profile: extended$' "$t_ps_def/.aai/system/AAI_PIN.md" || log_fail "ps1 default pin not stamped extended"
  log_pass "TEST-008 ps1 parity (parse + structure + end-to-end set equality)"
}

# --- TEST-401 — fixture build fails loudly on an incomplete or failed copy
# (Spec-AC-01) ----------------------------------------------------------------
test_401_fixture_build_completeness() {
  log_info "TEST-401: fixture build verifies its own copy completeness..."
  local out rc

  rc=0
  out="$(AAI_TEST_LP_DROP_FILE=".aai/PLANNING.prompt.md" bash "${BASH_SOURCE[0]}" __fixture_build_probe 2>&1)" || rc=$?
  [[ "$rc" -ne 0 ]] || log_fail "TEST-401: build must fail when a copied file is missing from the fixture, got exit 0: $out"
  assert_payload_contains "$out" ".aai/PLANNING.prompt.md" "TEST-401: failure must name the missing path .aai/PLANNING.prompt.md"

  rc=0
  out="$(AAI_TEST_LP_CP_FAIL_ITEM="hooks" bash "${BASH_SOURCE[0]}" __fixture_build_probe 2>&1)" || rc=$?
  [[ "$rc" -ne 0 ]] || log_fail "TEST-401: build must fail when a cp -R fails, got exit 0: $out"
  assert_payload_contains "$out" "hooks" "TEST-401: cp failure must name the failed item"
  assert_payload_contains "$out" "cp -R failed" "TEST-401: cp failure message must identify itself as a cp -R failure"

  log_pass "TEST-401 fixture build fails loudly on incomplete/failed copies (Spec-AC-01)"
}

# --- TEST-402 — core sync's own WARN is captured and failed on, not left to
# the downstream missing-file set (Spec-AC-02) --------------------------------
test_402_core_sync_warn_captured() {
  log_info "TEST-402: sync_output_ok catches a real 'missing in source' WARN..."
  local victim backup out rc
  victim="$(profile_list "$FIX_SRC/.aai/system/PROFILES.yaml" core | qgrep -m1 '^\.aai/')"
  [[ -n "$victim" ]] || log_fail "TEST-402: could not pick a core-listed victim file from the fixture"
  backup="$TMP_ROOT/402-backup-$(basename "$victim")"
  cp "$FIX_SRC/$victim" "$backup"
  rm -f "$FIX_SRC/$victim"

  rc=0
  new_target "$TMP_ROOT/t-402"
  out="$(bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$TMP_ROOT/t-402" --profile core 2>&1)" || rc=$?

  # restore the fixture immediately so later tests are unaffected
  mkdir -p "$FIX_SRC/$(dirname "$victim")"
  cp "$backup" "$FIX_SRC/$victim"

  assert_payload_contains "$out" "$victim" "TEST-402: real sync output must name the missing path $victim"
  if sync_output_ok "$out"; then
    log_fail "TEST-402: sync_output_ok must detect the 'missing in source' WARN for $victim, reported ok. out: $out"
  fi

  # run_sync_or_fail (what every happy-path call site now goes through) must
  # itself refuse on that captured output, naming the WARN, rather than
  # silently letting the caller fall through to a downstream missing-file
  # check two tests later. Exercised against a FRESH victim (the first was
  # already restored above) so the fixture is left clean either way.
  local victim2 backup2
  victim2="$(profile_list "$FIX_SRC/.aai/system/PROFILES.yaml" core | grep -v -F "$victim" | qgrep -m1 '^\.aai/')"
  [[ -n "$victim2" ]] || log_fail "TEST-402: could not pick a second core-listed victim file"
  backup2="$TMP_ROOT/402-backup2-$(basename "$victim2")"
  cp "$FIX_SRC/$victim2" "$backup2"
  rm -f "$FIX_SRC/$victim2"
  rc=0
  new_target "$TMP_ROOT/t-402c"
  out="$(run_sync_or_fail "victim2 sync" "$FIX_SRC/.aai/scripts/aai-sync.sh" "$TMP_ROOT/t-402c" --profile core 2>&1)" || rc=$?
  mkdir -p "$FIX_SRC/$(dirname "$victim2")"
  cp "$backup2" "$FIX_SRC/$victim2"
  [[ "$rc" -ne 0 ]] || log_fail "TEST-402: run_sync_or_fail must refuse on a real 'missing in source' WARN, got exit 0"
  assert_payload_contains "$out" "$victim2" "TEST-402: run_sync_or_fail's refusal must name the missing path $victim2"

  log_pass "TEST-402 core sync WARN captured and failed on before the downstream miss-check (Spec-AC-02)"
}

# --- TEST-403 — an invisible-but-nonempty payload dumps byte for byte
# (Spec-AC-02) ------------------------------------------------------------
test_403_payload_dump_on_invisible_nonempty() {
  log_info "TEST-403: assert_list_empty dumps byte-for-byte when a payload renders as zero visible lines..."
  local out rc

  rc=0
  out="$(assert_list_empty $'\n' "probe label" 2>&1)" || rc=$?
  [[ "$rc" -ne 0 ]] || log_fail "TEST-403: a non-empty whitespace-only payload must fail the check, got exit 0"
  assert_payload_contains "$out" "byte" "TEST-403: failure must announce a byte-for-byte dump for an invisible payload"

  rc=0
  out="$(assert_list_empty "real/path/here" "probe label" 2>&1)" || rc=$?
  [[ "$rc" -ne 0 ]] || log_fail "TEST-403: a real non-empty payload must still fail"
  assert_payload_contains "$out" "real/path/here" "TEST-403: a real payload should still print visibly"

  log_pass "TEST-403 invisible-but-nonempty payload triggers byte dump (Spec-AC-02)"
}

# True cause replacing the withdrawn TEST-463 (round 8 blamed `cp -a`
# silently leaving $dst absent; never reproduced, and the false-cause control
# is removed — see round 9). The real cause: `.aai/scripts/aai-sync.sh` runs
# under `set -euo pipefail`, and the core-prune / .gitignore-membership /
# first-line checks piped a writer into a reader that can close early
# (`grep -q`, `head -n1`). When the reader's first match/line happens before
# the writer finishes, the writer takes SIGPIPE, pipefail reports the
# pipeline as failed even though the reader DID match, and `!`/assignment
# logic reads that failure as "not found" — silently pruning a core-listed
# file or duplicating a re-checked .gitignore pattern. Deterministic with a
# writer payload bigger than the pipe buffer (real repro: CI run 34799612612).

# assert_core_files_present <target-root> <newline-separated relpaths> <label>
# — pure bash membership loop (no pipe: a large payload piped into grep -q
# is exactly the bug class TEST-464/465 exist to catch, so the assertion
# helper itself must not use one).
assert_core_files_present() {
  local root="$1" list="$2" label="$3" rel missing=""
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    [[ -f "$root/$rel" ]] || missing="${missing}${rel}"$'\n'
  done <<< "$list"
  [[ -z "$missing" ]] || log_fail "$label: real core file(s) missing after sync:"$'\n'"$missing"
}

# --- TEST-464 — core prune survives a core: list larger than the pipe
#     buffer (Spec-AC-04, deterministic form of the CI-load-only flake) -----
test_464_core_prune_survives_large_core_list() {
  log_info "TEST-464: core prune keeps every real core file when PROFILES.yaml's core: list is padded past the pipe buffer..."
  local src t out1 out2 rc real_core pad_count=20000

  # Private source clone: PROFILES.yaml is mutated below and must never
  # touch the shared $FIX_SRC other tests read.
  src="$TMP_ROOT/t-464-src"
  cp -a "$FIX_SRC" "$src"
  real_core="$(profile_list "$FIX_SRC/.aai/system/PROFILES.yaml" core)"
  [[ -n "$real_core" ]] || log_fail "TEST-464: fixture core: list is empty (precondition broken)"

  # Real core entries stay FIRST and untouched; append ~20000 nonexistent
  # padding paths inside the SAME core: block (before the next top-level
  # key) so CORE_FILES exceeds the pipe buffer. Padding paths don't exist in
  # $src, so the sync just WARNs "missing in source" and skips them.
  awk -v n="$pad_count" '
    $0 == "core:" { print; in_core = 1; next }
    in_core && /^[^ ]/ {
      for (i = 1; i <= n; i++) print "  - .aai/pad/f-" i
      in_core = 0
    }
    { print }
  ' "$FIX_SRC/.aai/system/PROFILES.yaml" > "$src/.aai/system/PROFILES.yaml"

  t="$TMP_ROOT/t-464-tgt"
  new_target "$t"

  out1="$TMP_ROOT/t-464-out1.log"
  rc=0
  bash "$src/.aai/scripts/aai-sync.sh" "$t" --profile core > "$out1" 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-464: first core sync against the padded list must exit 0 (got $rc); see $out1"
  assert_core_files_present "$t" "$real_core" "TEST-464 run 1"

  local snap1; snap1="$(tree_manifest "$t")"

  out2="$TMP_ROOT/t-464-out2.log"
  rc=0
  bash "$src/.aai/scripts/aai-sync.sh" "$t" --profile core > "$out2" 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-464: second core sync against the padded list must exit 0 (got $rc); see $out2"
  assert_core_files_present "$t" "$real_core" "TEST-464 run 2"

  local snap2; snap2="$(tree_manifest "$t")"
  [[ "$snap1" == "$snap2" ]] || log_fail "TEST-464: core sync not idempotent under a padded core list (tree changed on second run):"$'\n'"$(diff -u <(printf '%s\n' "$snap1") <(printf '%s\n' "$snap2") || true)"

  log_pass "TEST-464 core prune keeps every real core file when CORE_FILES exceeds the pipe buffer, both runs"
}

# --- TEST-465 — .gitignore agent-skill pattern membership survives a
#     .gitignore larger than the pipe buffer (idempotence) -----------------
test_465_gitignore_membership_survives_large_gitignore() {
  log_info "TEST-465: .gitignore membership for agent-skill patterns survives a >200KB target .gitignore whose first line is already the pattern..."
  local t pattern=".agents/skills/" pattern2="docs/ai/STATE.yaml" rc out1 out2 count1 count2 count1b count2b

  # Both membership loops in aai-sync.sh (AGENT_SKILL_PATTERNS and
  # RUNTIME_STATE_PATTERNS) are exercised: one pattern of each class sits at
  # the top of the file, where an early-closing reader would bite first
  # (validation round 8 NB-2: the runtime-state loop had no behavioural test).
  t="$TMP_ROOT/t-465-tgt"
  new_target "$t"
  {
    printf '%s\n' "$pattern" "$pattern2"
    awk 'BEGIN { for (i = 1; i <= 15000; i++) print "# aai-test-465-pad-" i }'
  } > "$t/.gitignore"
  [[ "$(wc -c < "$t/.gitignore" | tr -d ' ')" -gt 204800 ]] \
    || log_fail "TEST-465: fixture .gitignore must exceed 200 KB (precondition broken)"

  # NOTE: aai-sync.sh's own end-of-run .gitignore de-dup self-heal (below the
  # membership loops) would silently erase a duplicate this membership check
  # wrongly created, masking the bug from a final-count-only assertion. Read
  # $out1/$out2 back, not just the resulting file: the membership check must
  # never have needed that self-heal in the first place.
  local out1_text out2_text
  out1="$TMP_ROOT/t-465-out1.log"
  rc=0
  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t" --profile core > "$out1" 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-465: first sync must exit 0 (got $rc); see $out1"
  out1_text="$(cat "$out1")"
  assert_payload_not_contains "$out1_text" "stale AAI-managed line" "TEST-465: sync 1 needed the .gitignore de-dup self-heal -- the membership check wrongly re-appended a pattern that was already present"
  count1="$(grep -cxF -- "$pattern" "$t/.gitignore")"
  [[ "$count1" -eq 1 ]] || log_fail "TEST-465: pattern '$pattern' must occur exactly once after sync 1, got $count1"
  count1b="$(grep -cxF -- "$pattern2" "$t/.gitignore")"
  [[ "$count1b" -eq 1 ]] || log_fail "TEST-465: runtime-state pattern '$pattern2' must occur exactly once after sync 1, got $count1b"

  out2="$TMP_ROOT/t-465-out2.log"
  rc=0
  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t" --profile core > "$out2" 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-465: second sync must exit 0 (got $rc); see $out2"
  out2_text="$(cat "$out2")"
  assert_payload_not_contains "$out2_text" "stale AAI-managed line" "TEST-465: sync 2 needed the .gitignore de-dup self-heal -- the membership check wrongly re-appended a pattern that was already present"
  count2="$(grep -cxF -- "$pattern" "$t/.gitignore")"
  [[ "$count2" -eq 1 ]] || log_fail "TEST-465: pattern '$pattern' must still occur exactly once after sync 2 (non-idempotent membership check), got $count2"
  count2b="$(grep -cxF -- "$pattern2" "$t/.gitignore")"
  [[ "$count2b" -eq 1 ]] || log_fail "TEST-465: runtime-state pattern '$pattern2' must still occur exactly once after sync 2, got $count2b"

  log_pass "TEST-465 .gitignore membership stays exact-once across two syncs against a >200KB file"
}

# --- TEST-466 — static ratchet: aai-sync.sh pipes nothing into grep -q or
#     head -n1 (both are early-closing readers under pipefail) -------------
test_466_no_pipe_into_early_closing_reader() {
  log_info "TEST-466: aai-sync.sh has zero real pipelines into grep -q (any spelling) / head -n1 (any spelling)..."
  local hits
  # A single `|` not immediately preceded by another `|` (excludes the
  # pre-existing, unrelated `[[ ! -f x ]] || grep -q ... x` at the
  # docs/knowledge sentinel check, which reads its file argument directly —
  # never a pipe — and is not part of this bug class).
  # Any spelling of the two early-closing readers (validation round 8 NB-1:
  # `grep --quiet`, `grep -xq`, `head -1` escaped the first regex).
  # Comment lines never count (validation round 10 NB-1): the same filter the
  # repo-wide ratchet applies.
  hits="$(/usr/bin/grep -vE '^[[:space:]]*#' "$SYNC_SH" | /usr/bin/grep -cE '[^|]\|[[:space:]]*((command[[:space:]]+)?\\?(/usr/bin/)?grep([[:space:]]+-[A-Za-z]+|[[:space:]]+--[a-z-]+)*[[:space:]]+(-[A-Za-z]*q|--quiet|--silent|-m[[:space:]]*[0-9]+)|(command[[:space:]]+)?\\?(/usr/bin/)?head([[:space:]]|$))' || true)"
  [[ "$hits" -eq 0 ]] || log_fail "TEST-466: aai-sync.sh still pipes into grep -q / head -n1 ($hits occurrence(s)) — pipefail + an early-closing reader can SIGPIPE the writer and flip a real match/line into a false negative or abort the sync"
  log_pass "TEST-466 aai-sync.sh: zero pipe-into-(grep -q|qhead -n1) sites"
}

# --- Spec-AC self-check — no real network schemes in this suite ---------------
test_no_real_network() {
  log_info "Self-check: suite uses no real-network URL schemes..."
  if grep -nE "https?://" "${BASH_SOURCE[0]}" | grep -v "example.invalid" | qgrep -qv "^ *#"; then
    log_fail "suite references a routable http(s) URL"
  fi
  log_pass "Self-check: fixtures only (non-routable placeholders)"
}

main() {
  echo "=== AAI Skill Test: $TEST_NAME ==="
  # Test-only probe entry point (Spec-AC-01, TEST-401): builds the fixture in
  # isolation, under fault-injection hooks, and exits — no other test runs.
  if [[ "${1:-}" == "__fixture_build_probe" ]]; then
    check_deps
    build_fixture_sources
    echo "PROBE_OK: $FIX_SRC"
    return 0
  fi
  check_deps
  if [[ $# -gt 0 ]]; then
    build_fixture_sources
    "$1"
    echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="
    return
  fi
  test_manifest_conformance
  test_new_files_classified
  test_488_mutation_gate_files_classified
  build_fixture_sources
  test_default_byte_identity
  test_core_exact_set
  test_core_prune_and_idempotence
  test_invalid_profile
  test_pin_stamp_and_sticky
  test_doctor_display
  test_ps1_parity
  test_401_fixture_build_completeness
  test_402_core_sync_warn_captured
  test_403_payload_dump_on_invisible_nonempty
  test_464_core_prune_survives_large_core_list
  test_465_gitignore_membership_survives_large_gitignore
  test_466_no_pipe_into_early_closing_reader
  test_no_real_network
  echo "=== ALL TESTS PASSED: $TEST_NAME ==="
}

main "$@"
