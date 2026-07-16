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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$PROJECT_ROOT/.aai/system/PROFILES.yaml"
SYNC_SH="$PROJECT_ROOT/.aai/scripts/aai-sync.sh"
SYNC_PS1="$PROJECT_ROOT/.aai/scripts/aai-sync.ps1"
DOCTOR_PROMPT="$PROJECT_ROOT/.aai/SKILL_DOCTOR.prompt.md"
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

# Copy this repo's distribution surfaces into a fixture source and git-init it.
build_fixture_sources() {
  log_info "Building fixture sources (real distribution tree, no network)..."
  FIX_SRC="$TMP_ROOT/src-new"
  mkdir -p "$FIX_SRC"
  local item
  for item in .aai CLAUDE.md CODEX.md GEMINI.md SKILLS.md README.md hooks \
              .claude .codex .gemini .cursor .claude-plugin; do
    if [[ -e "$PROJECT_ROOT/$item" ]]; then
      cp -R "$PROJECT_ROOT/$item" "$FIX_SRC/$item"
    fi
  done
  mkdir -p "$FIX_SRC/.github" "$FIX_SRC/docs/knowledge"
  [[ -f "$PROJECT_ROOT/.github/copilot-instructions.md" ]] &&
    cp "$PROJECT_ROOT/.github/copilot-instructions.md" "$FIX_SRC/.github/"
  if [[ -d "$PROJECT_ROOT/docs/knowledge" ]]; then
    cp -R "$PROJECT_ROOT/docs/knowledge/." "$FIX_SRC/docs/knowledge/"
  fi
  rm -rf "$FIX_SRC/.aai/cache"

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
  profile_intro="$(git -C "$PROJECT_ROOT" log --reverse --format='%H' -S 'PROFILES.yaml' -- .aai/scripts/aai-sync.sh | head -1)"
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
  [[ -z "$dupes" ]] || log_fail "duplicate/overlapping manifest entries:"$'\n'"$dupes"
  overlap="$(comm -12 <(printf '%s\n' "$core" | LC_ALL=C sort) <(printf '%s\n' "$extended" | LC_ALL=C sort))"
  [[ -z "$overlap" ]] || log_fail "paths listed in BOTH profiles:"$'\n'"$overlap"

  local unclassified stale
  unclassified="$(comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$listed"))"
  [[ -z "$unclassified" ]] || log_fail "UNCLASSIFIED vendored files (add to PROFILES.yaml):"$'\n'"$unclassified"
  stale="$(comm -13 <(printf '%s\n' "$actual") <(printf '%s\n' "$listed"))"
  [[ -z "$stale" ]] || log_fail "stale manifest entries (no such file):"$'\n'"$stale"

  local n_core n_ext n_all
  n_core="$(printf '%s\n' "$core" | grep -c .)"
  n_ext="$(printf '%s\n' "$extended" | grep -c .)"
  n_all="$(printf '%s\n' "$actual" | grep -c .)"
  [[ $((n_core + n_ext)) -eq "$n_all" ]] || log_fail "count mismatch: core($n_core)+extended($n_ext) != tree($n_all)"
  echo "$core" | grep -qx '.aai/system/PROFILES.yaml' || log_fail "PROFILES.yaml must classify itself as core"
  log_pass "TEST-001 manifest conformance: core=$n_core extended=$n_ext total=$n_all (100%)"
}

# --- TEST-002 — default run byte-identical to the pre-change sync (Spec-AC-02) -
test_default_byte_identity() {
  log_info "TEST-002: flag-less run byte-identical to HEAD engine; --profile extended == default..."
  local t_old="$TMP_ROOT/t-old" t_new="$TMP_ROOT/t-new" t_ext="$TMP_ROOT/t-ext"
  new_target "$t_old"; new_target "$t_new"; new_target "$t_ext"

  bash "$FIX_SRC_OLD/.aai/scripts/aai-sync.sh" "$t_old" >/dev/null 2>&1 || log_fail "old-engine sync failed"
  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t_new" >/dev/null 2>&1 || log_fail "new-engine default sync failed"
  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t_ext" --profile extended >/dev/null 2>&1 || log_fail "--profile extended sync failed"

  # (a) default == --profile extended, byte-for-byte apart from pin timestamp.
  diff <(tree_manifest "$t_new") <(tree_manifest "$t_ext") >/dev/null \
    || log_fail "default and --profile extended trees differ"
  diff <(pin_stable "$t_new/.aai/system/AAI_PIN.md") <(pin_stable "$t_ext/.aai/system/AAI_PIN.md") >/dev/null \
    || log_fail "default and --profile extended pins differ beyond volatile lines"

  # (b) new default vs OLD engine: identical trees except the engine's own file.
  # (docs/ai/reports sync-conflict advisories are timestamp-named runtime
  # evidence emitted identically by both engines — excluded, see tree_manifest.)
  local differing
  differing="$(diff -rq "$t_old" "$t_new" 2>/dev/null | grep -v '/\.git' | grep -v 'docs/ai/reports' | grep '^Files ' | awk '{print $2}' | sed "s|^$t_old/||" || true)"
  local allowed=".aai/scripts/aai-sync.sh
.aai/system/AAI_PIN.md"
  local unexpected
  unexpected="$(comm -23 <(printf '%s\n' "$differing" | LC_ALL=C sort) <(printf '%s\n' "$allowed" | LC_ALL=C sort))"
  [[ -z "$unexpected" ]] || log_fail "default run NOT byte-identical to pre-change sync; unexpected diffs:"$'\n'"$unexpected"
  # Paths present in one target only (excluding .git, runtime reports) would be a copy-set change.
  local only
  only="$(diff -rq "$t_old" "$t_new" 2>/dev/null | grep -v '/\.git' | grep -v 'docs/ai/reports' | grep '^Only in ' || true)"
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
  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t_core" --profile core >/dev/null 2>&1 \
    || log_fail "--profile core sync failed"

  local want got
  want="$(profile_list "$FIX_SRC/.aai/system/PROFILES.yaml" core | LC_ALL=C sort)"
  got="$(aai_files_of "$t_core")"
  local missing extra
  missing="$(comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$got"))"
  extra="$(comm -13 <(printf '%s\n' "$want") <(printf '%s\n' "$got"))"
  [[ -z "$missing" ]] || log_fail "core sync MISSING core-listed files:"$'\n'"$missing"
  [[ -z "$extra" ]] || log_fail "core sync copied files beyond the core set:"$'\n'"$extra"
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
  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t" >/dev/null 2>&1 || log_fail "seed extended sync failed"
  [[ -f "$t/.aai/SKILL_DASHBOARD.prompt.md" ]] || log_fail "seed extended install incomplete"
  echo "#!/usr/bin/env bash" > "$t/.aai/scripts/project-custom.sh"

  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t" --profile core >/dev/null 2>&1 \
    || log_fail "core re-sync over extended target failed"
  [[ ! -f "$t/.aai/SKILL_DASHBOARD.prompt.md" ]] || log_fail "extended-only file survived core re-sync (no prune)"
  [[ ! -f "$t/.aai/scripts/generate-dashboard.mjs" ]] || log_fail "extended-only script survived core re-sync"
  [[ -f "$t/.aai/scripts/project-custom.sh" ]] || log_fail "target-only script was NOT preserved by core prune"

  local snap1 snap2
  snap1="$(tree_manifest "$t")"
  local pin1; pin1="$(pin_stable "$t/.aai/system/AAI_PIN.md")"
  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t" --profile core >/dev/null 2>&1 \
    || log_fail "second core sync failed"
  snap2="$(tree_manifest "$t")"
  local pin2; pin2="$(pin_stable "$t/.aai/system/AAI_PIN.md")"
  [[ "$snap1" == "$snap2" ]] || log_fail "core sync not idempotent (tree changed on second run)"
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
  echo "$out" | grep -qi "profile" || log_fail "error must name the profile flag, got: $out"
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
  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$tb" --profile core >/dev/null 2>&1 \
    || log_fail "core sync into a bracket-path target failed"
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
  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t" --profile core >/dev/null 2>&1 || log_fail "core sync failed"
  grep -q '^- Profile: core$' "$t/.aai/system/AAI_PIN.md" \
    || log_fail "pin lacks '- Profile: core':"$'\n'"$(cat "$t/.aai/system/AAI_PIN.md")"

  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t" >/dev/null 2>&1 || log_fail "flag-less re-sync failed"
  grep -q '^- Profile: core$' "$t/.aai/system/AAI_PIN.md" \
    || log_fail "flag-less re-sync lost the sticky core profile (pin now: $(grep '^- Profile:' "$t/.aai/system/AAI_PIN.md" || echo '<absent>'))"
  [[ ! -f "$t/.aai/SKILL_DASHBOARD.prompt.md" ]] \
    || log_fail "flag-less re-sync reinstalled the extended layer over a core target"

  # Explicit upgrade still works: core -> extended by flag.
  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t" --profile extended >/dev/null 2>&1 || log_fail "core->extended upgrade failed"
  grep -q '^- Profile: extended$' "$t/.aai/system/AAI_PIN.md" || log_fail "upgrade did not restamp pin to extended"
  [[ -f "$t/.aai/SKILL_DASHBOARD.prompt.md" ]] || log_fail "upgrade did not reinstall extended files"
  # Pin contract documents the field.
  grep -q 'Profile' "$PIN_CONTRACT" || log_fail ".aai/system/AAI_PIN.md contract does not document the Profile field"
  log_pass "TEST-006 pin stamp + sticky resolution + explicit upgrade"
}

# --- TEST-007 — SKILL_DOCTOR CAT-13 displays the profile (Spec-AC-03) ---------
test_doctor_display() {
  log_info "TEST-007: SKILL_DOCTOR CAT-13 reads and displays the layer profile..."
  [[ -f "$DOCTOR_PROMPT" ]] || log_fail "doctor prompt not found"
  local cat13
  cat13="$(awk '/\[CAT-13\]/{f=1} /^OUTPUT FORMAT/{f=0} f' "$DOCTOR_PROMPT")"
  echo "$cat13" | grep -q -- '- Profile:' || log_fail "CAT-13 does not read the pin's '- Profile:' line"
  echo "$cat13" | grep -qi 'extended (implicit)' || log_fail "CAT-13 lacks the absent->extended (implicit) rule"
  awk '/^OUTPUT FORMAT/{f=1} f' "$DOCTOR_PROMPT" | grep '\[CAT-13\]' | grep -q 'profile' \
    || log_fail "OUTPUT FORMAT CAT-13 line does not display the profile"
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
  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t_sh" --profile core >/dev/null 2>&1 || log_fail "sh core run failed"
  pwsh -NoProfile -File "$FIX_SRC/.aai/scripts/aai-sync.ps1" -TargetRoot "$t_ps" -Profile core >/dev/null 2>&1 \
    || log_fail "ps1 core run failed"
  diff <(aai_files_of "$t_sh") <(aai_files_of "$t_ps") >/dev/null \
    || log_fail "ps1 core install file set differs from sh:"$'\n'"$(diff <(aai_files_of "$t_sh") <(aai_files_of "$t_ps") || true)"
  grep -q '^- Profile: core$' "$t_ps/.aai/system/AAI_PIN.md" || log_fail "ps1 pin lacks Profile stamp"

  # ps1 default run stays extended (full set parity with sh default).
  local t_ps_def="$TMP_ROOT/t-par-ps-def" t_sh_def="$TMP_ROOT/t-par-sh-def"
  new_target "$t_ps_def"; new_target "$t_sh_def"
  bash "$FIX_SRC/.aai/scripts/aai-sync.sh" "$t_sh_def" >/dev/null 2>&1 || log_fail "sh default run failed"
  pwsh -NoProfile -File "$FIX_SRC/.aai/scripts/aai-sync.ps1" -TargetRoot "$t_ps_def" >/dev/null 2>&1 \
    || log_fail "ps1 default run failed"
  diff <(aai_files_of "$t_sh_def") <(aai_files_of "$t_ps_def") >/dev/null \
    || log_fail "ps1 default install file set differs from sh default"
  grep -q '^- Profile: extended$' "$t_ps_def/.aai/system/AAI_PIN.md" || log_fail "ps1 default pin not stamped extended"
  log_pass "TEST-008 ps1 parity (parse + structure + end-to-end set equality)"
}

# --- Spec-AC self-check — no real network schemes in this suite ---------------
test_no_real_network() {
  log_info "Self-check: suite uses no real-network URL schemes..."
  if grep -nE "https?://" "${BASH_SOURCE[0]}" | grep -v "example.invalid" | grep -qv "^ *#"; then
    log_fail "suite references a routable http(s) URL"
  fi
  log_pass "Self-check: fixtures only (non-routable placeholders)"
}

main() {
  echo "=== AAI Skill Test: $TEST_NAME ==="
  check_deps
  test_manifest_conformance
  build_fixture_sources
  test_default_byte_identity
  test_core_exact_set
  test_core_prune_and_idempotence
  test_invalid_profile
  test_pin_stamp_and_sticky
  test_doctor_display
  test_ps1_parity
  test_no_real_network
  echo "=== ALL TESTS PASSED: $TEST_NAME ==="
}

main "$@"
