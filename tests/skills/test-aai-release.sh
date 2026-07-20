#!/usr/bin/env bash
#
# Test: aai-release.sh — deterministic release-cut engine (aai-release-skill /
# SPEC-DRAFT-spec-aai-release-skill, TEST-001..021).
#
# Covers the CHANGELOG [unreleased] rollup transform (D1), release-notes
# extraction (D2, SEAM-1), version resolution (D3), the operator gate (D4),
# the remote seam (D5), the fail-closed precondition matrix (D6), the cut
# sequence (D7), portability (D8), and the layer-profiles + docs integrity
# seams (D9/D10, SEAM-2).
#
# ZERO REAL NETWORK / ZERO REAL PUBLISH: every cut runs against a throwaway
# scratch git repo under a temp dir; the remote arm (TEST-006/007) pushes only
# to a local `file://` bare repo and calls a STUB `gh` (records args, never
# contacts github.com); AAI_RELEASE_NO_REMOTE / --no-remote is used everywhere
# else. This suite MUST NOT publish a real release or push to `origin`.
#
# bash-3.2 compatible (no associative arrays, no `${var^^}`, no `mapfile`).
# mktemp always uses a FULL `...XXXXXX` template (GNU/BSD portable, no
# `-t <bare-prefix>`); scratch repos `git init -b main` (fresh-checkout
# hermeticity, LEARNED 2026-07-19). Run via .aai/scripts/aai-run-tests.sh.
#
# Usage:
#   bash tests/skills/test-aai-release.sh
#   bash tests/skills/test-aai-release.sh test_003_cut_rolls_changelog
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-release"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

RELEASE_SH="$PROJECT_ROOT/.aai/scripts/aai-release.sh"
RELEASE_PS1="$PROJECT_ROOT/.aai/scripts/aai-release.ps1"

TMP_ROOT=""

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

cleanup() {
  [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]] && rm -rf "$TMP_ROOT"
  true
}
trap cleanup EXIT

check_deps() {
  log_info "Checking dependencies..."
  [[ -f "$RELEASE_SH" ]] || log_fail "aai-release.sh not found: $RELEASE_SH"
  command -v git >/dev/null 2>&1 || log_fail "git not found"
  command -v awk >/dev/null 2>&1 || log_fail "awk not found"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-release-test.XXXXXX")"
  log_pass "Dependencies checked"
}

digest_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then echo "sha256sum"
  else echo "shasum -a 256"; fi
}
sha_of() { $(digest_cmd) "$1" | awk '{print $1}'; }

# --- Fixture builders --------------------------------------------------

new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "AAI Release Test"
}

commit_all() {
  local dir="$1" msg="$2"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "$msg"
}

# kind: two_entries | scaffold_only | absent | malformed
seed_changelog() {
  local dir="$1" kind="$2"
  case "$kind" in
    two_entries)
      printf '# Changelog\n\nSome preamble text.\n\n## [unreleased] — feat: first entry (REF-1)\n\n- line one\n- line two\n\n## [unreleased] — fix: second entry (REF-2)\n\n- fix line\n\n## [v2026.01.01] — feat: old release (REF-0)\n\n- old content\n' > "$dir/CHANGELOG.md"
      ;;
    scaffold_only)
      printf '# Changelog\n\n## [unreleased]\n\n## [v2026.01.01] — feat: old release (REF-0)\n\n- old content\n' > "$dir/CHANGELOG.md"
      ;;
    absent)
      printf '# Changelog\n\n## [v2026.01.01] — feat: old release (REF-0)\n\n- old content\n' > "$dir/CHANGELOG.md"
      ;;
    malformed)
      printf '# Changelog\n\n## [unreleased]\n\nstray body line under a bare scaffold heading\n\n## [v2026.01.01] — feat: old release (REF-0)\n\n- old content\n' > "$dir/CHANGELOG.md"
      ;;
    *) log_fail "seed_changelog: unknown kind $kind" ;;
  esac
}

build_repo() {
  # $1 = dir, $2 = changelog kind
  local dir="$1" kind="$2"
  new_repo "$dir"
  seed_changelog "$dir" "$kind"
  commit_all "$dir" "init"
}

# A stub `gh` that records every invocation's argv, and captures the
# --notes-file / --title values so SEAM-1 (TEST-006) can inspect them after
# the real script has already cleaned up its own temp notes file.
build_stub_gh() {
  local bin_dir="$1" log_file="$2" auth_exit="${3:-0}"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/gh" <<STUBEOF
#!/usr/bin/env bash
{
  printf 'ARGS:'
  for a in "\$@"; do printf ' %s' "\$a"; done
  printf '\n'
} >> "$log_file"
prev=""
for a in "\$@"; do
  if [[ "\$prev" == "--notes-file" ]]; then cp "\$a" "$log_file.notes" 2>/dev/null || true; fi
  if [[ "\$prev" == "--title" ]]; then printf '%s' "\$a" > "$log_file.title"; fi
  prev="\$a"
done
if [[ "\${1:-}" == "auth" ]]; then exit $auth_exit; fi
exit 0
STUBEOF
  chmod +x "$bin_dir/gh"
}

# A minimal PATH containing ONLY explicitly-resolved real tool binaries (no
# directory-level inclusion), so `gh` is reliably absent regardless of where
# the host happens to have gh installed (CI images often ship it alongside
# git in the very same directory that a naive directory-exclusion would keep).
build_isolated_path() {
  local bin="$1" tool resolved
  mkdir -p "$bin"
  for tool in bash sh git awk sed grep tr sort cat cp mv rm mkdir dirname \
              basename comm wc diff find xargs head tail id chmod printf \
              date mktemp od env true false ls; do
    resolved="$(command -v "$tool" 2>/dev/null || true)"
    [[ -n "$resolved" ]] && ln -sf "$resolved" "$bin/$tool" 2>/dev/null || true
  done
  if command -v sha256sum >/dev/null 2>&1; then ln -sf "$(command -v sha256sum)" "$bin/sha256sum"; fi
  if command -v shasum >/dev/null 2>&1; then ln -sf "$(command -v shasum)" "$bin/shasum"; fi
}

# Extract the "rolled section" for a version directly from a written
# CHANGELOG.md: every line from the first `## [<version>] — ` heading through
# the line before the next `## [` heading (or EOF), blank-trimmed. Independent
# re-derivation of D2 used only to CHECK the script's own notes output.
extract_rolled_section() {
  local file="$1" version="$2"
  awk -v version="$version" '
    BEGIN { started = 0 }
    /^## \[/ {
      if (started && $0 !~ ("^## \\[" version "\\] — ")) { exit }
    }
    $0 ~ ("^## \\[" version "\\] — ") { started = 1 }
    started { print }
  ' "$file" | awk '
    { buf[NR] = $0 }
    END {
      s = 1; e = NR
      while (s <= e && buf[s] ~ /^[ \t]*$/) s++
      while (e >= s && buf[e] ~ /^[ \t]*$/) e--
      for (i = s; i <= e; i++) print buf[i]
    }
  '
}

# --- TEST-001 (Spec-AC-01): --dry-run plan-only, default-safe --------------

test_001_dry_run_plan_only() {
  log_info "TEST-001: --dry-run prints version+rollup+tag+notes preview, exit 0, zero writes..."
  local repo="$TMP_ROOT/t001" out rc head_before head_after
  build_repo "$repo" two_entries
  head_before="$(git -C "$repo" rev-parse HEAD)"

  out="$TMP_ROOT/t001.out"
  rc=0
  ( cd "$repo" && AAI_RELEASE_DATE=2026-07-20 bash "$RELEASE_SH" --dry-run ) > "$out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-001: expected exit 0, got $rc: $(cat "$out")"

  grep -qF "Resolved version: v2026.07.20" "$out" || log_fail "TEST-001: missing resolved version in output"
  grep -qF "Tag to create:    v2026.07.20 (annotated)" "$out" || log_fail "TEST-001: missing tag name in output"
  grep -qF "## [v2026.07.20] — feat: first entry (REF-1)" "$out" || log_fail "TEST-001: missing CHANGELOG rollup preview"
  grep -qF -- "- line one" "$out" || log_fail "TEST-001: missing release-notes preview body"

  [[ -z "$(git -C "$repo" status --porcelain)" ]] || log_fail "TEST-001: dry-run left the tree dirty"
  [[ -z "$(git -C "$repo" tag -l)" ]] || log_fail "TEST-001: dry-run created a tag"
  head_after="$(git -C "$repo" rev-parse HEAD)"
  [[ "$head_before" == "$head_after" ]] || log_fail "TEST-001: dry-run created a commit"
  log_pass "TEST-001 --dry-run is plan-only, default-safe"
}

# --- TEST-002 (Spec-AC-01): bare invocation is plan-only (negative control) --

test_002_bare_invocation_plan_only() {
  log_info "TEST-002: bare invocation (no --confirm, no --dry-run) is plan-only..."
  local repo="$TMP_ROOT/t002" out rc head_before head_after
  build_repo "$repo" two_entries
  head_before="$(git -C "$repo" rev-parse HEAD)"

  out="$TMP_ROOT/t002.out"
  rc=0
  ( cd "$repo" && AAI_RELEASE_DATE=2026-07-20 bash "$RELEASE_SH" ) > "$out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-002: expected exit 0, got $rc: $(cat "$out")"
  grep -qF "Resolved version: v2026.07.20" "$out" || log_fail "TEST-002: missing resolved version"

  [[ -z "$(git -C "$repo" status --porcelain)" ]] || log_fail "TEST-002: bare invocation left the tree dirty"
  [[ -z "$(git -C "$repo" tag -l)" ]] || log_fail "TEST-002: bare invocation created a tag (must never auto-cut)"
  head_after="$(git -C "$repo" rev-parse HEAD)"
  [[ "$head_before" == "$head_after" ]] || log_fail "TEST-002: bare invocation created a commit"
  log_pass "TEST-002 bare invocation is default-safe plan-only"
}

# --- TEST-003 (Spec-AC-02): confirm cut rolls CHANGELOG, byte-preserved -----

test_003_cut_rolls_changelog() {
  log_info "TEST-003: --confirm rolls every [unreleased] heading, bodies byte-preserved, fresh scaffold on top..."
  local repo="$TMP_ROOT/t003" rc old_body new_body
  build_repo "$repo" two_entries
  old_body="$(grep -v '^## \[' "$repo/CHANGELOG.md" | grep -v '^[[:space:]]*$')"

  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.0.0 --confirm --no-remote ) >"$TMP_ROOT/t003.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-003: expected exit 0, got $rc: $(cat "$TMP_ROOT/t003.out")"

  grep -qF "## [v9.0.0] — feat: first entry (REF-1)" "$repo/CHANGELOG.md" || log_fail "TEST-003: first entry not rolled"
  grep -qF "## [v9.0.0] — fix: second entry (REF-2)" "$repo/CHANGELOG.md" || log_fail "TEST-003: second entry not rolled"
  grep -qF "## [v2026.01.01] — feat: old release (REF-0)" "$repo/CHANGELOG.md" || log_fail "TEST-003: pre-existing released heading was touched"

  # Fresh bare scaffold immediately above the first rolled heading.
  awk '
    /^## \[unreleased\]$/ { scaffold = NR }
    /^## \[v9\.0\.0\] — feat: first entry/ { first_entry = NR }
    END { if (!(scaffold && first_entry && scaffold < first_entry)) exit 1 }
  ' "$repo/CHANGELOG.md" || log_fail "TEST-003: fresh scaffold not immediately above the first rolled heading"

  new_body="$(grep -v '^## \[' "$repo/CHANGELOG.md" | grep -v '^[[:space:]]*$')"
  [[ "$old_body" == "$new_body" ]] || log_fail "TEST-003: block bodies not byte-preserved:"$'\n'"OLD:"$'\n'"$old_body"$'\n'"NEW:"$'\n'"$new_body"
  log_pass "TEST-003 rollup transform: headings swapped, bodies byte-preserved, fresh scaffold on top"
}

# --- TEST-004 (Spec-AC-02): commit message + staged path -------------------

test_004_commit_message_and_staged_path() {
  log_info "TEST-004: commit is 'chore(release): vX' staging ONLY CHANGELOG.md..."
  local repo="$TMP_ROOT/t004" rc msg stat_lines
  build_repo "$repo" two_entries
  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.0.1 --confirm --no-remote ) >"$TMP_ROOT/t004.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-004: cut failed: $(cat "$TMP_ROOT/t004.out")"

  msg="$(git -C "$repo" log -1 --format=%s)"
  [[ "$msg" == "chore(release): v9.0.1" ]] || log_fail "TEST-004: commit message is '$msg', expected 'chore(release): v9.0.1'"

  stat_lines="$(git -C "$repo" show --stat --format= HEAD | grep -c '|' || true)"
  [[ "$stat_lines" == "1" ]] || log_fail "TEST-004: commit touches $stat_lines files, expected exactly 1"
  git -C "$repo" show --stat --format= HEAD | grep -q 'CHANGELOG.md' || log_fail "TEST-004: the one changed file is not CHANGELOG.md"
  log_pass "TEST-004 commit message + single-path staging correct"
}

# --- TEST-005 (Spec-AC-02): annotated tag -----------------------------------

test_005_annotated_tag() {
  log_info "TEST-005: annotated tag vX created..."
  local repo="$TMP_ROOT/t005" rc kind
  build_repo "$repo" two_entries
  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.0.2 --confirm --no-remote ) >"$TMP_ROOT/t005.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-005: cut failed: $(cat "$TMP_ROOT/t005.out")"

  kind="$(git -C "$repo" cat-file -t v9.0.2 2>&1)" || log_fail "TEST-005: tag v9.0.2 not found"
  [[ "$kind" == "tag" ]] || log_fail "TEST-005: v9.0.2 is a '$kind' object, expected 'tag' (annotated)"
  log_pass "TEST-005 annotated tag created"
}

# --- TEST-006 (Spec-AC-02, SEAM-1): notes == rolled CHANGELOG section -------

test_006_seam1_notes_equal_rolled_section() {
  log_info "TEST-006: SEAM-1 — stubbed gh --notes-file content equals the just-rolled CHANGELOG section..."
  local repo="$TMP_ROOT/t006" bare="$TMP_ROOT/t006-bare.git" stub_bin="$TMP_ROOT/t006-stub" log_file="$TMP_ROOT/t006-ghlog"
  build_repo "$repo" two_entries
  git init -q --bare "$bare"
  git -C "$repo" remote add origin "file://$bare"
  build_stub_gh "$stub_bin" "$log_file" 0

  local rc=0
  ( cd "$repo" && PATH="$stub_bin:$PATH" bash "$RELEASE_SH" --version v9.1.0 --confirm ) >"$TMP_ROOT/t006.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-006: cut failed: $(cat "$TMP_ROOT/t006.out")"

  [[ -f "$log_file.notes" ]] || log_fail "TEST-006: stub gh never received --notes-file"
  [[ -f "$log_file.title" ]] || log_fail "TEST-006: stub gh never received --title"
  [[ "$(cat "$log_file.title")" == "v9.1.0" ]] || log_fail "TEST-006: notes title is '$(cat "$log_file.title")', expected v9.1.0"

  local expected actual
  expected="$(extract_rolled_section "$repo/CHANGELOG.md" "v9.1.0")"
  actual="$(cat "$log_file.notes")"
  [[ "$expected" == "$actual" ]] || log_fail "TEST-006: notes body != rolled CHANGELOG section:"$'\n'"EXPECTED:"$'\n'"$expected"$'\n'"ACTUAL:"$'\n'"$actual"
  log_pass "TEST-006 SEAM-1: gh notes body == just-rolled CHANGELOG section"
}

# --- TEST-007 (Spec-AC-02): remote arm attempted, --no-remote arm skipped --

test_007_remote_seam() {
  log_info "TEST-007: remote-enabled arm attempts push+gh release create; --no-remote arm skips both..."

  # (a) remote-enabled arm
  local repo="$TMP_ROOT/t007a" bare="$TMP_ROOT/t007a-bare.git" stub_bin="$TMP_ROOT/t007a-stub" log_file="$TMP_ROOT/t007a-ghlog"
  build_repo "$repo" two_entries
  git init -q --bare "$bare"
  git -C "$repo" remote add origin "file://$bare"
  build_stub_gh "$stub_bin" "$log_file" 0
  local rc=0
  ( cd "$repo" && PATH="$stub_bin:$PATH" bash "$RELEASE_SH" --version v9.2.0 --confirm ) >"$TMP_ROOT/t007a.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-007a: cut failed: $(cat "$TMP_ROOT/t007a.out")"
  git -C "$bare" show-ref --tags | grep -q "refs/tags/v9.2.0" || log_fail "TEST-007a: tag v9.2.0 was not pushed to the remote"
  git -C "$bare" show-ref --heads | grep -q "refs/heads/main" || log_fail "TEST-007a: branch main was not pushed to the remote"
  [[ -f "$log_file" ]] || log_fail "TEST-007a: gh was never invoked"
  grep -q "release create v9.2.0" "$log_file" || log_fail "TEST-007a: gh release create v9.2.0 was not attempted"

  # (b) --no-remote arm: negative control — must skip both push and gh
  local repo2="$TMP_ROOT/t007b" bare2="$TMP_ROOT/t007b-bare.git" stub_bin2="$TMP_ROOT/t007b-stub" log_file2="$TMP_ROOT/t007b-ghlog"
  build_repo "$repo2" two_entries
  git init -q --bare "$bare2"
  git -C "$repo2" remote add origin "file://$bare2"
  build_stub_gh "$stub_bin2" "$log_file2" 0
  rc=0
  ( cd "$repo2" && PATH="$stub_bin2:$PATH" bash "$RELEASE_SH" --version v9.2.0 --confirm --no-remote ) >"$TMP_ROOT/t007b.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-007b: --no-remote cut failed: $(cat "$TMP_ROOT/t007b.out")"
  [[ -z "$(git -C "$bare2" show-ref 2>/dev/null || true)" ]] || log_fail "TEST-007b: --no-remote pushed something to the remote"
  [[ ! -f "$log_file2" ]] || log_fail "TEST-007b: --no-remote invoked gh ($(cat "$log_file2"))"

  log_pass "TEST-007 remote seam: enabled arm attempts push+publish, --no-remote arm skips both"
}

# --- TEST-008 (Spec-AC-02): idempotence — re-run refuses, zero writes ------

test_008_idempotence() {
  log_info "TEST-008: re-running a confirm cut after a successful roll refuses (scaffold-only), zero further writes..."
  local repo="$TMP_ROOT/t008" rc sha_before sha_after commits_before commits_after
  build_repo "$repo" two_entries
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.3.0 --confirm --no-remote ) >"$TMP_ROOT/t008a.out" 2>&1 \
    || log_fail "TEST-008: first cut failed: $(cat "$TMP_ROOT/t008a.out")"

  sha_before="$(sha_of "$repo/CHANGELOG.md")"
  commits_before="$(git -C "$repo" rev-list --count HEAD)"

  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.3.1 --confirm --no-remote ) >"$TMP_ROOT/t008b.out" 2>&1 || rc=$?
  [[ "$rc" != "0" ]] || log_fail "TEST-008: second (idempotent) cut unexpectedly succeeded"

  sha_after="$(sha_of "$repo/CHANGELOG.md")"
  commits_after="$(git -C "$repo" rev-list --count HEAD)"
  [[ "$sha_before" == "$sha_after" ]] || log_fail "TEST-008: CHANGELOG changed on the refused re-run"
  [[ "$commits_before" == "$commits_after" ]] || log_fail "TEST-008: a new commit was created on the refused re-run"
  [[ -z "$(git -C "$repo" tag -l v9.3.1)" ]] || log_fail "TEST-008: tag v9.3.1 was created on the refused re-run"
  log_pass "TEST-008 idempotent refusal, zero further writes"
}

# --- TEST-009 (Spec-AC-03): dirty tree -> refuse, zero writes --------------

test_009_dirty_tree_refuses() {
  log_info "TEST-009: dirty working tree -> confirm cut refuses, zero writes..."
  local repo="$TMP_ROOT/t009" rc sha_before sha_after
  build_repo "$repo" two_entries
  sha_before="$(sha_of "$repo/CHANGELOG.md")"
  echo "untracked" > "$repo/untracked.txt"

  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.4.0 --confirm --no-remote ) >"$TMP_ROOT/t009.out" 2>&1 || rc=$?
  [[ "$rc" != "0" ]] || log_fail "TEST-009: dirty-tree cut unexpectedly succeeded"
  grep -qi "dirty" "$TMP_ROOT/t009.out" || log_fail "TEST-009: refusal message does not mention a dirty tree"

  sha_after="$(sha_of "$repo/CHANGELOG.md")"
  [[ "$sha_before" == "$sha_after" ]] || log_fail "TEST-009: CHANGELOG changed despite refusal"
  [[ -z "$(git -C "$repo" tag -l)" ]] || log_fail "TEST-009: a tag was created despite refusal"
  log_pass "TEST-009 dirty tree refuses, zero writes"
}

# --- TEST-010 (Spec-AC-03): empty (scaffold-only) unreleased -> refuse -----

test_010_empty_unreleased_refuses() {
  log_info "TEST-010: empty (scaffold-only) [unreleased] -> refuse, zero writes (ALWAYS-checked, even plan mode)..."
  local repo="$TMP_ROOT/t010" rc sha_before sha_after
  build_repo "$repo" scaffold_only
  sha_before="$(sha_of "$repo/CHANGELOG.md")"

  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" ) >"$TMP_ROOT/t010.out" 2>&1 || rc=$?
  [[ "$rc" != "0" ]] || log_fail "TEST-010: empty-unreleased run unexpectedly succeeded"

  sha_after="$(sha_of "$repo/CHANGELOG.md")"
  [[ "$sha_before" == "$sha_after" ]] || log_fail "TEST-010: CHANGELOG changed despite refusal"
  log_pass "TEST-010 empty unreleased refuses, zero writes"
}

# --- TEST-011 (Spec-AC-03): absent unreleased heading -> refuse -----------

test_011_absent_unreleased_refuses() {
  log_info "TEST-011: absent [unreleased] heading -> refuse, zero writes (ALWAYS-checked)..."
  local repo="$TMP_ROOT/t011" rc sha_before sha_after
  build_repo "$repo" absent
  sha_before="$(sha_of "$repo/CHANGELOG.md")"

  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" ) >"$TMP_ROOT/t011.out" 2>&1 || rc=$?
  [[ "$rc" != "0" ]] || log_fail "TEST-011: absent-unreleased run unexpectedly succeeded"

  sha_after="$(sha_of "$repo/CHANGELOG.md")"
  [[ "$sha_before" == "$sha_after" ]] || log_fail "TEST-011: CHANGELOG changed despite refusal"
  log_pass "TEST-011 absent unreleased refuses, zero writes"
}

# --- TEST-012 (Spec-AC-03): existing tag -> refuse, zero writes -----------

test_012_existing_tag_refuses() {
  log_info "TEST-012: existing tag for resolved version -> refuse, zero writes..."
  local repo="$TMP_ROOT/t012" rc sha_before sha_after
  build_repo "$repo" two_entries
  git -C "$repo" tag -a v9.5.0 -m v9.5.0
  sha_before="$(sha_of "$repo/CHANGELOG.md")"

  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.5.0 --confirm --no-remote ) >"$TMP_ROOT/t012.out" 2>&1 || rc=$?
  [[ "$rc" != "0" ]] || log_fail "TEST-012: existing-tag cut unexpectedly succeeded"
  grep -qi "already exists" "$TMP_ROOT/t012.out" || log_fail "TEST-012: refusal message does not mention the existing tag"

  sha_after="$(sha_of "$repo/CHANGELOG.md")"
  [[ "$sha_before" == "$sha_after" ]] || log_fail "TEST-012: CHANGELOG changed despite refusal"
  local commit_count; commit_count="$(git -C "$repo" rev-list --count HEAD)"
  [[ "$commit_count" == "1" ]] || log_fail "TEST-012: a new commit was created despite refusal"
  log_pass "TEST-012 existing tag refuses, zero writes"
}

# --- TEST-013 (Spec-AC-03): gh absent/unauth on publish path --------------

test_013_gh_absent_unauth_publish_path() {
  log_info "TEST-013: gh absent/unauthenticated on the publish path refuses BEFORE any write; dry-run works offline..."
  local iso_bin="$TMP_ROOT/t013-iso"
  build_isolated_path "$iso_bin"

  # (a) gh absent entirely
  local repo="$TMP_ROOT/t013a" rc sha_before sha_after
  build_repo "$repo" two_entries
  sha_before="$(sha_of "$repo/CHANGELOG.md")"
  rc=0
  ( cd "$repo" && PATH="$iso_bin" bash "$RELEASE_SH" --version v9.6.0 --confirm ) >"$TMP_ROOT/t013a.out" 2>&1 || rc=$?
  [[ "$rc" != "0" ]] || log_fail "TEST-013a: cut with gh absent unexpectedly succeeded"
  sha_after="$(sha_of "$repo/CHANGELOG.md")"
  [[ "$sha_before" == "$sha_after" ]] || log_fail "TEST-013a: CHANGELOG changed despite gh being absent"
  [[ -z "$(git -C "$repo" tag -l)" ]] || log_fail "TEST-013a: a tag was created despite gh being absent"

  # (b) gh present but unauthenticated
  local repo2="$TMP_ROOT/t013b" stub_bin="$TMP_ROOT/t013b-stub" log_file="$TMP_ROOT/t013b-ghlog"
  build_repo "$repo2" two_entries
  sha_before="$(sha_of "$repo2/CHANGELOG.md")"
  build_stub_gh "$stub_bin" "$log_file" 1
  rc=0
  ( cd "$repo2" && PATH="$stub_bin:$iso_bin" bash "$RELEASE_SH" --version v9.6.0 --confirm ) >"$TMP_ROOT/t013b.out" 2>&1 || rc=$?
  [[ "$rc" != "0" ]] || log_fail "TEST-013b: cut with gh unauthenticated unexpectedly succeeded"
  sha_after="$(sha_of "$repo2/CHANGELOG.md")"
  [[ "$sha_before" == "$sha_after" ]] || log_fail "TEST-013b: CHANGELOG changed despite gh being unauthenticated"
  [[ -z "$(git -C "$repo2" tag -l)" ]] || log_fail "TEST-013b: a tag was created despite gh being unauthenticated"

  # (c) dry-run still works fully offline (no gh required at all)
  local repo3="$TMP_ROOT/t013c"
  build_repo "$repo3" two_entries
  rc=0
  ( cd "$repo3" && PATH="$iso_bin" bash "$RELEASE_SH" --dry-run ) >"$TMP_ROOT/t013c.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-013c: --dry-run with gh absent failed: $(cat "$TMP_ROOT/t013c.out")"

  log_pass "TEST-013 gh absent/unauth refuses before any write; dry-run works offline"
}

# --- TEST-014 (Spec-AC-03): not a git repo / no CHANGELOG.md --------------

test_014_not_git_repo_and_no_changelog() {
  log_info "TEST-014: not a git repo -> refuse; no CHANGELOG.md -> refuse; both zero writes..."
  local dir1="$TMP_ROOT/t014a" rc
  mkdir -p "$dir1"
  printf '## [unreleased] — feat: x (R1)\n\n- b\n' > "$dir1/CHANGELOG.md"
  rc=0
  ( cd "$dir1" && bash "$RELEASE_SH" --dry-run ) >"$TMP_ROOT/t014a.out" 2>&1 || rc=$?
  [[ "$rc" != "0" ]] || log_fail "TEST-014a: non-git-repo run unexpectedly succeeded"
  grep -qi "not a git repository" "$TMP_ROOT/t014a.out" || log_fail "TEST-014a: refusal does not mention 'not a git repository'"

  local dir2="$TMP_ROOT/t014b"
  new_repo "$dir2"
  echo "placeholder" > "$dir2/README.md"
  commit_all "$dir2" "init, no CHANGELOG.md"
  rc=0
  ( cd "$dir2" && bash "$RELEASE_SH" --dry-run ) >"$TMP_ROOT/t014b.out" 2>&1 || rc=$?
  [[ "$rc" != "0" ]] || log_fail "TEST-014b: no-CHANGELOG.md run unexpectedly succeeded"
  grep -qi "no CHANGELOG.md" "$TMP_ROOT/t014b.out" || log_fail "TEST-014b: refusal does not mention missing CHANGELOG.md"

  log_pass "TEST-014 not-a-git-repo and no-CHANGELOG.md both refuse"
}

# --- TEST-015 (Spec-AC-03): malformed unreleased -> refuse, never drop ----

test_015_malformed_refuses() {
  log_info "TEST-015: malformed [unreleased] (bare scaffold WITH body) -> refuse, zero writes (never silently drop)..."
  local repo="$TMP_ROOT/t015" rc sha_before sha_after
  build_repo "$repo" malformed
  sha_before="$(sha_of "$repo/CHANGELOG.md")"

  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" ) >"$TMP_ROOT/t015.out" 2>&1 || rc=$?
  [[ "$rc" != "0" ]] || log_fail "TEST-015: malformed-unreleased run unexpectedly succeeded"
  grep -qi "malformed" "$TMP_ROOT/t015.out" || log_fail "TEST-015: refusal does not mention 'malformed'"

  sha_after="$(sha_of "$repo/CHANGELOG.md")"
  [[ "$sha_before" == "$sha_after" ]] || log_fail "TEST-015: CHANGELOG changed despite refusal"
  log_pass "TEST-015 malformed unreleased refuses, zero writes"
}

# --- TEST-016 (Spec-AC-04): bash -n parses; no BSD-only constructs --------

test_016_portability_static() {
  log_info "TEST-016: bash -n aai-release.sh parses; no 'mktemp -t <bare>'; no 'stat -f'-first..."
  bash -n "$RELEASE_SH" || log_fail "TEST-016: bash -n aai-release.sh failed to parse"

  grep -qE 'mktemp[[:space:]]+-t[[:space:]]' "$RELEASE_SH" \
    && log_fail "TEST-016: aai-release.sh uses 'mktemp -t <bare-prefix>' (not GNU/BSD-portable)"

  if grep -n 'stat -f' "$RELEASE_SH" >/dev/null 2>&1; then
    local stat_f_line stat_c_line
    stat_f_line="$(grep -n 'stat -f' "$RELEASE_SH" | head -1 | cut -d: -f1)"
    stat_c_line="$(grep -n 'stat -c' "$RELEASE_SH" | head -1 | cut -d: -f1 || true)"
    [[ -n "$stat_c_line" && "$stat_c_line" -lt "$stat_f_line" ]] \
      || log_fail "TEST-016: 'stat -f' appears without a preceding 'stat -c' (GNU-first) fallback"
  fi
  log_pass "TEST-016 portability static checks pass"
}

# --- TEST-017 (Spec-AC-04): version resolution ------------------------------

test_017_version_resolution() {
  log_info "TEST-017: AAI_RELEASE_DATE pins CalVer default; --version wins verbatim over the date/clock..."
  local repo="$TMP_ROOT/t017" out rc
  build_repo "$repo" two_entries

  out="$TMP_ROOT/t017a.out"; rc=0
  ( cd "$repo" && AAI_RELEASE_DATE=2026-07-20 bash "$RELEASE_SH" --dry-run ) > "$out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-017a: dry-run failed: $(cat "$out")"
  grep -qF "Resolved version: v2026.07.20" "$out" || log_fail "TEST-017a: AAI_RELEASE_DATE=2026-07-20 did not resolve to v2026.07.20"

  out="$TMP_ROOT/t017b.out"; rc=0
  ( cd "$repo" && AAI_RELEASE_DATE=1999-01-01 bash "$RELEASE_SH" --version v1.2.3 --dry-run ) > "$out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-017b: dry-run failed: $(cat "$out")"
  grep -qF "Resolved version: v1.2.3" "$out" || log_fail "TEST-017b: --version v1.2.3 did not win verbatim over AAI_RELEASE_DATE"
  grep -qF "v1999.01.01" "$out" && log_fail "TEST-017b: the date was consulted despite an explicit --version"
  log_pass "TEST-017 version resolution: AAI_RELEASE_DATE pin + --version verbatim precedence"
}

# --- TEST-018 (Spec-AC-04): generic — no .aai/ layer in the target repo ----

test_018_generic_non_aai_repo() {
  log_info "TEST-018: a scratch repo with NO .aai/ layer (only root+CHANGELOG+git) cuts successfully..."
  local repo="$TMP_ROOT/t018" rc
  build_repo "$repo" two_entries
  [[ ! -d "$repo/.aai" ]] || log_fail "TEST-018 fixture bug: scratch repo unexpectedly has a .aai/ dir"

  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.7.0 --confirm --no-remote ) >"$TMP_ROOT/t018.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-018: cut in a non-AAI repo failed: $(cat "$TMP_ROOT/t018.out")"
  [[ "$(git -C "$repo" cat-file -t v9.7.0 2>/dev/null)" == "tag" ]] || log_fail "TEST-018: annotated tag missing after generic cut"
  log_pass "TEST-018 generic non-AAI repo cuts successfully"
}

# --- TEST-019 (Spec-AC-04): ps1 parity — same flags as the bash script -----

test_019_ps1_flag_parity() {
  log_info "TEST-019: aai-release.ps1 exists and exposes the same flags as aai-release.sh..."
  [[ -f "$RELEASE_PS1" ]] || log_fail "TEST-019: aai-release.ps1 not found"
  grep -q '\$DryRun'  "$RELEASE_PS1" || log_fail "TEST-019: ps1 lacks a DryRun switch"
  grep -q '\$Version' "$RELEASE_PS1" || log_fail "TEST-019: ps1 lacks a Version parameter"
  grep -q '\$Confirm' "$RELEASE_PS1" || log_fail "TEST-019: ps1 lacks a Confirm switch"
  grep -q '\$NoRemote' "$RELEASE_PS1" || log_fail "TEST-019: ps1 lacks a NoRemote switch"
  grep -q 'AAI_RELEASE_DATE'       "$RELEASE_PS1" || log_fail "TEST-019: ps1 does not read AAI_RELEASE_DATE"
  grep -q 'AAI_RELEASE_NO_REMOTE'  "$RELEASE_PS1" || log_fail "TEST-019: ps1 does not read AAI_RELEASE_NO_REMOTE"

  if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -Command '
      $errs = $null
      [System.Management.Automation.Language.Parser]::ParseFile("'"$RELEASE_PS1"'", [ref]$null, [ref]$errs) | Out-Null
      if ($errs -and $errs.Count) { $errs | ForEach-Object { Write-Output $_.Message }; exit 1 }
    ' || log_fail "TEST-019: aai-release.ps1 has parse errors"
  else
    log_info "TEST-019 note: pwsh absent — structural flag parity only (parse skipped)"
  fi
  log_pass "TEST-019 ps1 parity (flags present)"
}

# --- TEST-020 (Spec-AC-05, SEAM-2): layer-profiles classification ----------

test_020_seam2_layer_profiles() {
  log_info "TEST-020: SEAM-2 — test-aai-layer-profiles.sh exits 0 with the 3 new .aai/** files classified core..."
  local suite="$PROJECT_ROOT/tests/skills/test-aai-layer-profiles.sh" rc
  [[ -f "$suite" ]] || log_fail "TEST-020: test-aai-layer-profiles.sh not found"
  rc=0
  bash "$suite" >"$TMP_ROOT/t020.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-020: test-aai-layer-profiles.sh exited $rc:"$'\n'"$(tail -40 "$TMP_ROOT/t020.out")"
  log_pass "TEST-020 layer-profiles suite green (new .aai/** files classified)"
}

# --- TEST-021 (Spec-AC-05): docs document /aai-release ---------------------

test_021_docs_document_release() {
  log_info "TEST-021: docs/USER_GUIDE.md and CHANGELOG.md document /aai-release..."
  grep -q '/aai-release' "$PROJECT_ROOT/docs/USER_GUIDE.md" || log_fail "TEST-021: docs/USER_GUIDE.md does not mention /aai-release"
  grep -q '/aai-release' "$PROJECT_ROOT/CHANGELOG.md" || log_fail "TEST-021: CHANGELOG.md does not mention /aai-release"
  log_pass "TEST-021 docs document /aai-release"
}

main() {
  echo "=== AAI Skill Test: $TEST_NAME ==="
  check_deps

  if [[ $# -gt 0 ]]; then
    "$1"
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    return
  fi

  test_001_dry_run_plan_only
  test_002_bare_invocation_plan_only
  test_003_cut_rolls_changelog
  test_004_commit_message_and_staged_path
  test_005_annotated_tag
  test_006_seam1_notes_equal_rolled_section
  test_007_remote_seam
  test_008_idempotence
  test_009_dirty_tree_refuses
  test_010_empty_unreleased_refuses
  test_011_absent_unreleased_refuses
  test_012_existing_tag_refuses
  test_013_gh_absent_unauth_publish_path
  test_014_not_git_repo_and_no_changelog
  test_015_malformed_refuses
  test_016_portability_static
  test_017_version_resolution
  test_018_generic_non_aai_repo
  test_019_ps1_flag_parity
  test_020_seam2_layer_profiles
  test_021_docs_document_release

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
