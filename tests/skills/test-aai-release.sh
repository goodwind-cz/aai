#!/usr/bin/env bash
#
# Test: aai-release.sh — deterministic release-cut engine (aai-release-skill /
# SPEC-0063-spec-aai-release-skill, TEST-001..021), plus the live-CHANGELOG
# integrity pins: scaffold invariants (test_022/023), no-deleted-unreleased-
# heading vs merge-base (test_024, CHANGE-0135), the released-region class
# pin vs the latest ancestor release tag (test_025/026, CHANGE-0141) and the
# protected-branch PR fallback (test_027..034,
# spec-release-protected-branch-fallback).
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

# kind: two_entries | scaffold_plus_entries | scaffold_only | absent | malformed
seed_changelog() {
  local dir="$1" kind="$2"
  case "$kind" in
    two_entries)
      printf '# Changelog\n\nSome preamble text.\n\n## [unreleased] — feat: first entry (REF-1)\n\n- line one\n- line two\n\n## [unreleased] — fix: second entry (REF-2)\n\n- fix line\n\n## [v2026.01.01] — feat: old release (REF-0)\n\n- old content\n' > "$dir/CHANGELOG.md"
      ;;
    scaffold_plus_entries)
      printf '# Changelog\n\n## [unreleased]\n\n## [unreleased] — feat: first entry (REF-1)\n\n- line one\n\n## [v2026.01.01] — feat: old release (REF-0)\n\n- old content\n' > "$dir/CHANGELOG.md"
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
if [[ "\${1:-}" == "pr" && "\${2:-}" == "create" ]]; then
  # Real \`gh pr create\` prints a progress line to STDERR non-interactively
  # while the URL alone goes to stdout. The stub reproduces that split: a stub
  # that is silent on stderr cannot catch an engine that captures stdout and
  # stderr together and then treats the whole capture as the URL (the ps1
  # \`Invoke-NativeChecked | Select-Object -Last 1\` defect, remediation F2).
  printf '\n' >&2
  printf 'Creating pull request for chore/release-branch into main in aai-fixture/aai\n' >&2
  printf '%s\n' "$STUB_PR_URL"
  exit 0
fi
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

# --- Released-region class pin helper (CHANGE-0141 Spec-AC-01, D1+D3) -------
#
# released_region_verdict <repo_dir> <scratch_prefix>
#
# Emits EXACTLY ONE verdict line on stdout and always returns 0 (the caller
# interprets the verdict — log_fail exits the suite, so the scratch matrix in
# test_026 needs a non-exiting core):
#   PASS <tag>            released region byte-identical vs <tag>'s own copy
#   SKIP <named reason>   no usable tag (D1.3 — never a silent pass)
#   FAIL <tag> <detail>   divergence, naming the tag and the first divergence
#
# D1 tag resolution: candidates from `git tag --list 'v[0-9]*'
# --sort=-v:refname` captured into a variable (NEVER a pipeline — this suite
# runs `set -euo pipefail`; `… | head -1` dies of SIGPIPE on CI), iterated via
# here-string; the FIRST candidate that is an ancestor of HEAD wins.
# D3 region: from the first `^## [v` line through EOF, byte-compared (cmp).
# A live CHANGELOG with no released heading while the tag's region is
# non-empty is a FAIL, never a skip — that is the total-glue/deletion case
# this pin exists for.
released_region_verdict() {
  local dir="$1" prefix="$2"
  local tags tag resolved=""
  tags="$(git -C "$dir" tag --list 'v[0-9]*' --sort=-v:refname)"
  if [[ -z "$tags" ]]; then
    printf 'SKIP no tag matching v[0-9]* exists in this repo\n'
    return 0
  fi
  while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    if git -C "$dir" merge-base --is-ancestor "$tag" HEAD 2>/dev/null; then
      resolved="$tag"
      break
    fi
  done <<<"$tags"
  if [[ -z "$resolved" ]]; then
    printf 'SKIP no v[0-9]* tag is an ancestor of HEAD\n'
    return 0
  fi
  if ! git -C "$dir" show "$resolved:CHANGELOG.md" > "$prefix-tag-changelog.md" 2>/dev/null; then
    printf 'SKIP git show %s:CHANGELOG.md failed (tag carries no CHANGELOG.md)\n' "$resolved"
    return 0
  fi
  # EOF-byte fidelity (PR #256 bot sweep): awk's `print` always emits a
  # trailing newline, so two files differing ONLY in whether the last line
  # is newline-terminated would extract byte-identical. Capture each file's
  # final-byte state alongside the region and compare it too.
  eof_state() {
    local f="$1"
    if [[ ! -s "$f" ]]; then printf 'empty\n'; return 0; fi
    local last
    last="$(tail -c 1 "$f" | od -An -tx1 | tr -d ' \n')"
    if [[ "$last" == "0a" ]]; then printf 'newline\n'; else printf 'no-newline\n'; fi
  }
  awk 'f { print; next } /^## \[v/ { f = 1; print }' "$prefix-tag-changelog.md" > "$prefix-tag-region"
  if [[ ! -s "$prefix-tag-region" ]]; then
    printf 'SKIP %s CHANGELOG.md contains no released heading (^## [v)\n' "$resolved"
    return 0
  fi
  if [[ ! -f "$dir/CHANGELOG.md" ]]; then
    printf 'FAIL %s live CHANGELOG.md is missing while the tag region is non-empty\n' "$resolved"
    return 0
  fi
  # A RELEASE PR legitimately inserts a NEW `## [vX]` section ABOVE everything
  # the tag knows about, so "first ^## [v to EOF" diverges at line 1 and this
  # guard failed every release PR. It never fired on the old path because the
  # release script tagged AND pushed together: by the time CI ran on main the
  # new tag was the latest ancestor and the tag's file WAS the live file.
  # Routing releases through a PR (enforce_admins on main) exposed it.
  # The property that actually matters is unchanged: everything the tag already
  # published must survive byte-identically. So anchor the live region at the
  # TAG's own first released heading rather than at the live file's — a new
  # section above it is a release, a single byte changed below it is the
  # glue/deletion/retitle this guard exists to catch.
  local anchor
  anchor="$(head -1 "$prefix-tag-region")"
  awk -v a="$anchor" 'f { print; next } $0 == a { f = 1; print }' "$dir/CHANGELOG.md" > "$prefix-live-region"
  if [[ ! -s "$prefix-live-region" ]]; then
    printf 'FAIL %s live CHANGELOG has NO released heading while the tag region is non-empty (total glue/deletion)\n' "$resolved"
    return 0
  fi
  local rc=0 cmp_out
  cmp_out="$(cmp "$prefix-live-region" "$prefix-tag-region" 2>&1)" || rc=$?
  if [[ "$rc" != "0" ]]; then
    printf 'FAIL %s released region diverges from the tag'"'"'s own copy: %s\n' "$resolved" "$cmp_out"
    return 0
  fi
  local live_eof tag_eof
  live_eof="$(eof_state "$dir/CHANGELOG.md")"
  tag_eof="$(eof_state "$prefix-tag-changelog.md")"
  if [[ "$live_eof" != "$tag_eof" ]]; then
    printf 'FAIL %s released region matches but the file EOF state differs (live=%s tag=%s)\n' \
      "$resolved" "$live_eof" "$tag_eof"
    return 0
  fi
  printf 'PASS %s\n' "$resolved"
}

# Replicate the exact bc056cd damage shape on a CHANGELOG copy: the FIRST
# released heading's tail (everything after `## [vX]`) is glued onto the last
# non-blank line above it; the heading line and the blanks between vanish.
glue_first_released_heading() {
  # $1 = pristine source, $2 = destination
  awk '
    { lines[++n] = $0 }
    END {
      idx = 0
      for (i = 1; i <= n; i++) if (lines[i] ~ /^## \[v/) { idx = i; break }
      tail = lines[idx]
      sub(/^## \[v[^\]]*\]/, "", tail)
      m = idx - 1
      while (m >= 1 && lines[m] ~ /^[ \t]*$/) m--
      lines[m] = lines[m] tail
      for (i = 1; i <= n; i++) { if (i > m && i <= idx) continue; print lines[i] }
    }
  ' "$1" > "$2"
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
  # aai-version-file: every cut stamps the version file aai-sync reads
  grep -qxF -- "- Version: v9.0.0" "$repo/docs/ai/AAI_VERSION.md" 2>/dev/null \
    || log_fail "TEST-003: cut must write docs/ai/AAI_VERSION.md with '- Version: v9.0.0' (downstream pins said UNKNOWN without it)"
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
  log_info "TEST-004: commit is 'chore(release): vX' staging ONLY CHANGELOG.md + AAI_VERSION.md..."
  local repo="$TMP_ROOT/t004" rc msg stat_lines
  build_repo "$repo" two_entries
  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.0.1 --confirm --no-remote ) >"$TMP_ROOT/t004.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-004: cut failed: $(cat "$TMP_ROOT/t004.out")"

  msg="$(git -C "$repo" log -1 --format=%s)"
  [[ "$msg" == "chore(release): v9.0.1" ]] || log_fail "TEST-004: commit message is '$msg', expected 'chore(release): v9.0.1'"

  # aai-version-file: the cut commit stages exactly TWO paths — the rolled
  # CHANGELOG and the version stamp aai-sync reads (nothing else may ride in).
  stat_lines="$(git -C "$repo" show --stat --format= HEAD | grep -c '|' || true)"
  [[ "$stat_lines" == "2" ]] || log_fail "TEST-004: commit touches $stat_lines files, expected exactly 2 (CHANGELOG.md + AAI_VERSION.md)"
  git -C "$repo" show --stat --format= HEAD | grep -q 'CHANGELOG.md' || log_fail "TEST-004: CHANGELOG.md missing from the cut commit"
  git -C "$repo" show --stat --format= HEAD | grep -q 'AAI_VERSION.md' || log_fail "TEST-004: AAI_VERSION.md missing from the cut commit"
  log_pass "TEST-004 commit message + exact two-path staging correct"
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

test_022_live_changelog_scaffold_invariants() {
  # Recurring class (3x: #211 bot finding, re-created, cleaned by #214):
  # automated CHANGELOG inserts leave a SECOND bare "## [unreleased]" scaffold,
  # which release-cut then rolls INTO the versioned section where it corrupts
  # the next cut's block parsing. Enforce the invariants deterministically at
  # PR time on the LIVE file (release-cut checks only fire at cut time):
  #   1. exactly ONE bare scaffold line;
  #   2. it precedes every versioned "## [vX]" heading;
  #   3. no bare scaffold anywhere below the first versioned heading.
  log_info "TEST-022: live CHANGELOG has exactly one bare [unreleased] scaffold, above all versioned sections..."
  local cl="$PROJECT_ROOT/CHANGELOG.md"
  local bare_count first_bare first_versioned
  bare_count="$(grep -c '^## \[unreleased\]$' "$cl")" || true
  if [[ "$bare_count" -ne 1 ]]; then
    log_fail "TEST-022: expected exactly 1 bare '## [unreleased]' scaffold, found $bare_count (lines: $(grep -n '^## \[unreleased\]$' "$cl" | cut -d: -f1 | tr '\n' ' '))"
    return 1
  fi
  # single-process awk, no pipelines: grep|head|cut under set -o pipefail dies
  # on SIGPIPE (many matches) or exit 1 (zero matches) — bot-caught, and the
  # same class as the test_092 set -e incident the same day.
  first_bare="$(awk '/^## \[unreleased\]$/{print NR; exit}' "$cl")"
  first_versioned="$(awk '/^## \[v/{print NR; exit}' "$cl")"
  if [[ -n "$first_versioned" && "$first_bare" -gt "$first_versioned" ]]; then
    log_fail "TEST-022: bare scaffold (line $first_bare) sits BELOW the first versioned heading (line $first_versioned)"
    return 1
  fi
  log_pass "TEST-022 live CHANGELOG scaffold invariants hold (1 scaffold, above all versioned sections)"
}

test_023_cut_consumes_existing_scaffold() {
  # Root cause of the recurring duplicate-scaffold class (planted by BOTH the
  # v2026.08.02 and v2026.08.03 cuts on the real repo): the roll inserted a
  # fresh scaffold AND copied the pre-existing one through into the versioned
  # region. The real CHANGELOG always has scaffold+entries; the two_entries
  # fixture never did, so TEST-003 could not see it.
  log_info "TEST-023: a cut over scaffold+entries leaves EXACTLY ONE bare scaffold..."
  local repo="$TMP_ROOT/t023" rc n
  build_repo "$repo" scaffold_plus_entries
  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.1.0 --confirm --no-remote ) >"$TMP_ROOT/t023.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-023: expected exit 0, got $rc: $(cat "$TMP_ROOT/t023.out")"
  n="$(grep -c '^## \[unreleased\]$' "$repo/CHANGELOG.md")" || true
  [[ "$n" -eq 1 ]] || log_fail "TEST-023: expected exactly 1 bare scaffold after cut, found $n"
  grep -qF "## [v9.1.0] — feat: first entry (REF-1)" "$repo/CHANGELOG.md" || log_fail "TEST-023: entry not rolled"
  log_pass "TEST-023 cut consumes the pre-existing scaffold (exactly one remains)"
}

test_024_no_deleted_unreleased_heading_vs_main() {
  # CLASS guard (code review, CHANGE-0135): the second heading-deletion
  # incident in one week (CHANGE-0128, then cf6f037 on this branch) — a docs
  # closeout commit REPLACED a pre-existing '## [unreleased] — ...' heading
  # with its own instead of adding a new one above it, silently
  # re-attributing the deleted heading's bullets to the wrong scope. TEST-032
  # (aai-doctor) only greps for A heading matching the current scope; it
  # cannot see one that vanished. Cheap, local, honest guard: every
  # unreleased ENTRY heading present at this branch's merge-base with main
  # must still be present verbatim in the live CHANGELOG — a PR may ADD
  # headings, never make one it did not itself write disappear. Single awk
  # pass over two files, no pipelines (this suite's own set -o pipefail
  # trap), soft-skips when neither origin/main nor main resolves, or the
  # merge-base / base CHANGELOG aren't reachable (fresh clone without the
  # remote, template repo with no CHANGELOG.md).
  log_info "TEST-024: no pre-existing unreleased heading is deleted relative to the branch's merge-base with main..."
  # Base-ref resolution prefers origin/main: GitHub Actions PR checkouts are
  # detached-HEAD with only origin/main fetched (no local 'main' branch), so
  # resolving the bare ref 'main' made this pin vacuous exactly where it
  # matters most. Repo precedent: .aai/scripts/allocate-doc-number.mjs
  # defaults to origin/main. Soft-skip only when NEITHER ref resolves.
  local base_ref=""
  if git -C "$PROJECT_ROOT" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    base_ref="origin/main"
  elif git -C "$PROJECT_ROOT" rev-parse --verify --quiet main >/dev/null 2>&1; then
    base_ref="main"
  else
    log_pass "TEST-024 skipped: neither 'origin/main' nor 'main' ref reachable"
    return
  fi
  local base
  base="$(git -C "$PROJECT_ROOT" merge-base HEAD "$base_ref" 2>/dev/null)" || base=""
  if [[ -z "$base" ]]; then
    log_pass "TEST-024 skipped: no merge-base with main"
    return
  fi
  local base_file="$TMP_ROOT/t024-base-changelog.md"
  if ! git -C "$PROJECT_ROOT" show "$base:CHANGELOG.md" >"$base_file" 2>/dev/null; then
    log_pass "TEST-024 skipped: CHANGELOG.md not present at merge-base $base"
    return
  fi
  local missing
  # A merge-base unreleased heading may legitimately disappear in exactly ONE
  # way: a release roll renames `## [unreleased] — <title>` to
  # `## [vX] — <title>`. The first version of this guard did not know that, so
  # it failed EVERY release PR — all nine headings at once — while passing on a
  # direct push to main, where merge-base(HEAD, main) is HEAD and the base file
  # IS the live file, so nothing can differ. The bug was latent for as long as
  # releases bypassed the PR path; enabling `enforce_admins` on main forced them
  # onto it and turned it into a hard block. The title (everything after the
  # first " — ") is the identity that must survive; only the version marker may
  # change, and a title vanishing from BOTH forms is still the deletion this
  # guard was built to catch.
  missing="$(awk '
    function title(line) { sub(/^## \[[^]]*\] — /, "", line); return line }
    NR==FNR { if ($0 ~ /^## \[unreleased\] — /) base[title($0)]=$0; next }
    $0 ~ /^## \[[^]]*\] — / { live[title($0)]=1 }
    END { for (t in base) if (!(t in live)) print base[t] }
  ' "$base_file" "$PROJECT_ROOT/CHANGELOG.md")"
  if [[ -n "$missing" ]]; then
    log_fail "TEST-024: unreleased heading(s) present at merge-base ($base) are missing from the live CHANGELOG — deleted rather than added above: $missing"
    return
  fi
  log_pass "TEST-024 every merge-base unreleased heading is still present verbatim in the live CHANGELOG"
}

test_025_released_region_pin_vs_tag() {
  # CLASS guard (CHANGE-0141 Spec-AC-01 / TEST-001): the THIRD glued/damaged
  # released-heading incident (bc056cd glued the released v2026.08.13.2
  # heading onto a CHANGE-0140 bullet) was caught only because a
  # scope-specific pin happened to cover the immediately-previous scope.
  # Release history is immutable by definition, so the class guard is a
  # byte-compare of the live released region (first `^## [v` line to EOF)
  # against the SAME region of the latest ancestor release tag's own
  # CHANGELOG.md. Unreleased-zone edits (the normal life of a PR) never
  # enter the compare; glue/deletion/retitle/reorder at ANY depth fails
  # naming the tag and the first divergence.
  log_info "TEST-025: live CHANGELOG released region byte-identical vs the latest ancestor release tag (D1+D3)..."
  local verdict
  verdict="$(released_region_verdict "$PROJECT_ROOT" "$TMP_ROOT/t025")"
  case "$verdict" in
    PASS\ *)
      log_pass "TEST-025 released region byte-identical vs ${verdict#PASS } (latest ancestor release tag)"
      ;;
    SKIP\ *)
      log_pass "TEST-025 skipped: ${verdict#SKIP }"
      ;;
    FAIL\ *)
      log_fail "TEST-025: ${verdict#FAIL }"
      ;;
    *)
      log_fail "TEST-025: unexpected verdict from released_region_verdict: $verdict"
      ;;
  esac
}

test_026_released_region_scratch_matrix() {
  # In-suite negative control for the class pin (CHANGE-0141 Spec-AC-01 /
  # TEST-002): drives the SAME released_region_verdict helper test_025 uses
  # through a scratch repo where the suite itself owns the tags, so the
  # guard's bite is proven on every run, not only in the one-off RED replay:
  #   (a) exact bc056cd glue of the newest released heading  -> FAIL
  #   (b) deep-history retitle (the v2026.08.08-era heading) -> FAIL
  #   (c) unreleased-zone-only edit                          -> PASS
  #   (d) tagless repo                                       -> NAMED skip
  log_info "TEST-026: scratch matrix — glue FAILS, deep retitle FAILS, unreleased edit PASSES, tagless is a NAMED skip..."
  local repo="$TMP_ROOT/t026" pristine="$TMP_ROOT/t026-pristine.md" verdict

  # Fixture: two releases cut in sequence (annotated CalVer tags where
  # -v:refname must rank v2026.08.13.2 above v2026.08.08), then a
  # post-release unreleased entry on top — the real repo's shape.
  new_repo "$repo"
  printf '# Changelog\n\n## [unreleased]\n\n## [v2026.08.08] — feat: older release (REF-A)\n\n- older bullet\n' > "$repo/CHANGELOG.md"
  commit_all "$repo" "release v2026.08.08"
  git -C "$repo" tag -a v2026.08.08 -m v2026.08.08
  printf '# Changelog\n\n## [unreleased]\n\n## [v2026.08.13.2] — feat: newest release (REF-B)\n\n- newest bullet\n\n## [v2026.08.08] — feat: older release (REF-A)\n\n- older bullet\n' > "$repo/CHANGELOG.md"
  commit_all "$repo" "release v2026.08.13.2"
  git -C "$repo" tag -a v2026.08.13.2 -m v2026.08.13.2
  printf '# Changelog\n\n## [unreleased]\n\n## [unreleased] — feat: pending work (REF-C)\n\n- pending bullet\n\n## [v2026.08.13.2] — feat: newest release (REF-B)\n\n- newest bullet\n\n## [v2026.08.08] — feat: older release (REF-A)\n\n- older bullet\n' > "$repo/CHANGELOG.md"
  commit_all "$repo" "docs: pending unreleased entry"
  cp "$repo/CHANGELOG.md" "$pristine"

  # Baseline: intact repo passes, naming the version-sorted newest ancestor
  # tag (v2026.08.13.2, NOT v2026.08.08 — the -v:refname + ancestor rule).
  verdict="$(released_region_verdict "$repo" "$TMP_ROOT/t026-base")"
  [[ "$verdict" == "PASS v2026.08.13.2" ]] \
    || log_fail "TEST-026 baseline: intact scratch repo must PASS naming v2026.08.13.2, got: $verdict"

  # (a) glue: the exact bc056cd damage shape on the newest released heading.
  glue_first_released_heading "$pristine" "$repo/CHANGELOG.md"
  verdict="$(released_region_verdict "$repo" "$TMP_ROOT/t026-glue")"
  [[ "$verdict" == FAIL\ v2026.08.13.2* ]] \
    || log_fail "TEST-026 glue arm: bc056cd-shape glue must FAIL naming v2026.08.13.2, got: $verdict"

  # (b) deep-history retitle of the OLDER released heading.
  sed -E 's/^## \[v2026\.08\.08\] — .*/## [v2026.08.08] — feat: RETITLED deep-history heading (mutation)/' "$pristine" > "$repo/CHANGELOG.md"
  verdict="$(released_region_verdict "$repo" "$TMP_ROOT/t026-retitle")"
  [[ "$verdict" == FAIL\ v2026.08.13.2* ]] \
    || log_fail "TEST-026 retitle arm: deep-history retitle must FAIL naming v2026.08.13.2, got: $verdict"

  # (c) unreleased-zone-only edit (the normal life of a PR) never trips it.
  awk '{ print; if ($0 == "- pending bullet") print "- added unreleased-zone bullet" }' "$pristine" > "$repo/CHANGELOG.md"
  verdict="$(released_region_verdict "$repo" "$TMP_ROOT/t026-unrel")"
  [[ "$verdict" == "PASS v2026.08.13.2" ]] \
    || log_fail "TEST-026 unreleased arm: unreleased-zone-only edit must PASS, got: $verdict"

  # (d) tagless repo: NAMED soft-skip, never a silent pass.
  local repo2="$TMP_ROOT/t026b"
  new_repo "$repo2"
  printf '# Changelog\n\n## [unreleased]\n\n## [v2026.01.01] — feat: looks released, never tagged (REF-Z)\n\n- bullet\n' > "$repo2/CHANGELOG.md"
  commit_all "$repo2" "init without tags"
  verdict="$(released_region_verdict "$repo2" "$TMP_ROOT/t026-tagless")"
  [[ "$verdict" == SKIP\ no\ tag\ matching* ]] \
    || log_fail "TEST-026 tagless arm: must SKIP with the named no-tag reason, got: $verdict"

  log_pass "TEST-026 scratch matrix: glue FAILS, deep retitle FAILS, unreleased edit PASSES, tagless yields the named skip (all naming v2026.08.13.2 where resolved)"
}

# --- Protected-branch PR fallback (release-protected-branch-fallback) -------
#
# TEST-027..TEST-034 pin the CONFIRM path's behavior when the target branch is
# a GitHub-protected branch requiring status checks: the engines fall back to
# a release branch + `gh pr create` and STOP, never publishing and never
# merging (Constitution article 7).
#
# Fixture note (probed 2026-09-02, spec D-plan): the bare remote rejects via a
# PER-REF `hooks/update` hook, never `pre-receive`. GitHub's protection is
# per-ref and non-atomic, so a rejected branch push still lets OTHER refs of
# the same push through — which is exactly how `push.followTags=true` orphaned
# refs/tags/v2026.09.01 on the real incident (PR #329). A `pre-receive`
# rejection is atomic and would block the tag too, hiding the very orphan
# TEST-030 exists to catch.

STUB_PR_URL="https://github.com/aai-fixture/aai/pull/4242"

build_protected_bare() {
  # $1 = bare repo path, $2 = fully-qualified ref this remote refuses
  local bare="$1" ref="$2"
  git init -q --bare "$bare"
  mkdir -p "$bare/hooks"
  cat > "$bare/hooks/update" <<HOOKEOF
#!/usr/bin/env bash
if [ "\$1" = "$ref" ]; then
  echo "remote: error: GH006: Protected branch update failed for $ref." >&2
  echo "remote: error: 3 of 3 required status checks are expected." >&2
  exit 1
fi
exit 0
HOOKEOF
  chmod +x "$bare/hooks/update"
}

# setup_protected_fixture <name> [followtags]
# $TMP_ROOT/<name>          scratch repo (two_entries CHANGELOG, remote origin)
# $TMP_ROOT/<name>-bare.git bare remote refusing refs/heads/main
# $TMP_ROOT/<name>-stub     stub gh dir, $TMP_ROOT/<name>-ghlog its argv log
setup_protected_fixture() {
  local name="$1" followtags="${2:-0}"
  local repo="$TMP_ROOT/$name" bare="$TMP_ROOT/$name-bare.git"
  build_repo "$repo" two_entries
  build_protected_bare "$bare" "refs/heads/main"
  git -C "$repo" remote add origin "file://$bare"
  if [[ "$followtags" == "1" ]]; then
    git -C "$repo" config push.followTags true
  fi
  build_stub_gh "$TMP_ROOT/$name-stub" "$TMP_ROOT/$name-ghlog" 0
}

# --- TEST-027 (Spec-AC-01): the fallback sequence itself --------------------

test_027_protected_branch_fallback() {
  log_info "TEST-027: a GH006-rejected branch push falls back to chore/release-<version> + gh pr create..."
  local repo="$TMP_ROOT/t027" bare="$TMP_ROOT/t027-bare.git" stub="$TMP_ROOT/t027-stub" log="$TMP_ROOT/t027-ghlog"
  setup_protected_fixture t027
  local pre_sha rc=0 n
  pre_sha="$(git -C "$repo" rev-parse HEAD)"

  ( cd "$repo" && PATH="$stub:$PATH" bash "$RELEASE_SH" --version v9.3.0 --confirm ) \
    >"$TMP_ROOT/t027.out" 2>"$TMP_ROOT/t027.err" || rc=$?

  [[ "$rc" == "17" ]] || log_fail "TEST-027: expected exit 17 (fallback complete), got $rc:"$'\n'"$(cat "$TMP_ROOT/t027.out" "$TMP_ROOT/t027.err")"
  git -C "$repo" rev-parse -q --verify "refs/heads/chore/release-v9.3.0" >/dev/null 2>&1 \
    || log_fail "TEST-027: local release branch chore/release-v9.3.0 was not created"
  [[ "$(git -C "$repo" rev-parse HEAD)" == "$pre_sha" ]] \
    || log_fail "TEST-027: target branch main was not reset to its pre-cut SHA ($pre_sha)"
  [[ "$(git -C "$repo" rev-parse "refs/heads/chore/release-v9.3.0")" != "$pre_sha" ]] \
    || log_fail "TEST-027: the release commit did not survive on the release branch"
  git -C "$bare" show-ref --verify --quiet "refs/heads/chore/release-v9.3.0" \
    || log_fail "TEST-027: release branch was not pushed to the remote"
  [[ -f "$log" ]] || log_fail "TEST-027: gh was never invoked (no PR opened)"
  n="$(grep -c '^ARGS: pr create ' "$log" || true)"
  [[ "$n" == "1" ]] || log_fail "TEST-027: expected exactly 1 'gh pr create', got $n:"$'\n'"$(cat "$log")"
  grep -qF -- "--base main" "$log" || log_fail "TEST-027: gh pr create did not target --base main: $(cat "$log")"
  grep -qF -- "--head chore/release-v9.3.0" "$log" || log_fail "TEST-027: gh pr create did not carry --head chore/release-v9.3.0: $(cat "$log")"
  log_pass "TEST-027 protected-branch fallback: release branch created+pushed, target reset, exactly one gh pr create"
}

# --- TEST-028 (Spec-AC-02): never publishes, never merges -------------------

test_028_fallback_never_publishes_or_merges() {
  log_info "TEST-028: the fallback exits 17 and calls neither 'gh release create' nor 'gh pr merge'..."
  local repo="$TMP_ROOT/t028" stub="$TMP_ROOT/t028-stub" log="$TMP_ROOT/t028-ghlog" rc=0
  setup_protected_fixture t028

  ( cd "$repo" && PATH="$stub:$PATH" bash "$RELEASE_SH" --version v9.3.1 --confirm ) \
    >"$TMP_ROOT/t028.out" 2>"$TMP_ROOT/t028.err" || rc=$?
  [[ "$rc" == "17" ]] || log_fail "TEST-028: expected exit 17, got $rc:"$'\n'"$(cat "$TMP_ROOT/t028.out" "$TMP_ROOT/t028.err")"

  if grep -q 'release create' "$log"; then
    log_fail "TEST-028: the fallback path invoked 'gh release create' — a protected-branch fallback must NEVER publish: $(cat "$log")"
  fi
  if grep -q 'pr merge' "$log"; then
    log_fail "TEST-028: the fallback path invoked 'gh pr merge' — Constitution article 7 (operator-only merge): $(cat "$log")"
  fi
  log_pass "TEST-028 fallback exits 17 with zero 'release create' and zero 'pr merge' invocations"
}

# --- TEST-029 (Spec-AC-03): tag stays LOCAL, report names the re-point ------

test_029_tag_is_local_and_report_names_the_repoint() {
  log_info "TEST-029: no remote tag, a local annotated tag at the release commit, and the re-tag sequence on stdout..."
  local repo="$TMP_ROOT/t029" bare="$TMP_ROOT/t029-bare.git" stub="$TMP_ROOT/t029-stub" rc=0 out="$TMP_ROOT/t029.out"
  setup_protected_fixture t029

  ( cd "$repo" && PATH="$stub:$PATH" bash "$RELEASE_SH" --version v9.3.2 --confirm ) \
    >"$out" 2>"$TMP_ROOT/t029.err" || rc=$?
  [[ "$rc" == "17" ]] || log_fail "TEST-029: expected exit 17, got $rc:"$'\n'"$(cat "$out" "$TMP_ROOT/t029.err")"

  [[ -z "$(git -C "$bare" show-ref --tags 2>/dev/null || true)" ]] \
    || log_fail "TEST-029: the remote carries a tag after the fallback — the tag must stay local: $(git -C "$bare" show-ref --tags)"
  [[ "$(git -C "$repo" cat-file -t v9.3.2 2>/dev/null)" == "tag" ]] \
    || log_fail "TEST-029: local annotated tag v9.3.2 is missing after the fallback"
  [[ "$(git -C "$repo" rev-parse 'v9.3.2^{commit}')" == "$(git -C "$repo" rev-parse 'refs/heads/chore/release-v9.3.2')" ]] \
    || log_fail "TEST-029: local tag v9.3.2 does not point at the release commit"

  local pr_line
  pr_line="$(sed -n 's/^- PR:[[:space:]]*//p' "$out")"
  [[ "$pr_line" == "$STUB_PR_URL" ]] \
    || log_fail "TEST-029: the report's '- PR:' line must carry the PR URL and nothing else (gh writes a progress line to stderr; it must not be folded into the captured URL) — got '$pr_line':"$'\n'"$(cat "$out")"
  grep -qF "git tag -d" "$out" || log_fail "TEST-029: report does not name 'git tag -d': $(cat "$out")"
  grep -qF "git tag -a" "$out" || log_fail "TEST-029: report does not name 'git tag -a': $(cat "$out")"
  grep -qF "git push origin refs/tags/" "$out" || log_fail "TEST-029: report does not name 'git push origin refs/tags/': $(cat "$out")"
  grep -qF "gh release create" "$out" || log_fail "TEST-029: report does not name the post-merge 'gh release create': $(cat "$out")"
  log_pass "TEST-029 tag is local-only and the report spells out the post-merge re-tag sequence"
}

# --- TEST-030 (Spec-AC-04): push.followTags can never orphan the tag --------

test_030_followtags_cannot_orphan_the_tag() {
  log_info "TEST-030: push.followTags=true + a rejected branch push leaves NO refs/tags on the remote..."
  local repo="$TMP_ROOT/t030" bare="$TMP_ROOT/t030-bare.git" stub="$TMP_ROOT/t030-stub" rc=0
  setup_protected_fixture t030 1
  [[ "$(git -C "$repo" config --get push.followTags)" == "true" ]] \
    || log_fail "TEST-030 fixture bug: push.followTags is not set in the scratch repo"

  ( cd "$repo" && PATH="$stub:$PATH" bash "$RELEASE_SH" --version v9.4.0 --confirm ) \
    >"$TMP_ROOT/t030.out" 2>"$TMP_ROOT/t030.err" || rc=$?

  local remote_tags
  remote_tags="$(git -C "$bare" show-ref --tags 2>/dev/null || true)"
  [[ -z "$remote_tags" ]] \
    || log_fail "TEST-030: the rejected branch push published a tag anyway (the PR #329 orphan) — expected none, got:"$'\n'"$remote_tags"
  log_pass "TEST-030 --no-follow-tags: a rejected branch push cannot publish refs/tags/<version> (rc=$rc)"
}

# --- TEST-031 (Spec-AC-05): unprotected path unchanged ----------------------

test_031_unprotected_path_byte_identical() {
  log_info "TEST-031: on an UNPROTECTED remote the cut's SHA-masked stdout matches the pre-change engine byte for byte..."
  local old_engine="$TMP_ROOT/t031-old-release.sh" ref base_ref=""
  for ref in origin/main main; do
    if git -C "$PROJECT_ROOT" show "$ref:.aai/scripts/aai-release.sh" > "$old_engine" 2>/dev/null; then
      base_ref="$ref"
      break
    fi
  done

  # Arm A — the working-tree engine over an unprotected bare.
  local repoA="$TMP_ROOT/t031a" bareA="$TMP_ROOT/t031a-bare.git" stubA="$TMP_ROOT/t031a-stub" rcA=0
  build_repo "$repoA" two_entries
  git init -q --bare "$bareA"
  git -C "$repoA" remote add origin "file://$bareA"
  build_stub_gh "$stubA" "$TMP_ROOT/t031a-ghlog" 0
  ( cd "$repoA" && PATH="$stubA:$PATH" bash "$RELEASE_SH" --version v9.5.5 --confirm ) \
    >"$TMP_ROOT/t031a.out" 2>"$TMP_ROOT/t031a.err" || rcA=$?
  [[ "$rcA" == "0" ]] || log_fail "TEST-031: unprotected cut exited $rcA, expected 0:"$'\n'"$(cat "$TMP_ROOT/t031a.out" "$TMP_ROOT/t031a.err")"
  git -C "$bareA" show-ref --verify --quiet refs/heads/main || log_fail "TEST-031: refs/heads/main missing on the unprotected remote"
  git -C "$bareA" show-ref --verify --quiet refs/tags/v9.5.5 || log_fail "TEST-031: refs/tags/v9.5.5 missing on the unprotected remote"

  if [[ -z "$base_ref" ]]; then
    log_info "TEST-031: neither origin/main nor main carries .aai/scripts/aai-release.sh here — stdout byte-comparison arm skipped (degrade and report)"
    log_pass "TEST-031 unprotected path: exit 0 and both refs pushed (byte-comparison arm skipped, no base engine)"
    return 0
  fi

  # Arm B — the pre-change engine over an identically seeded fixture.
  local repoB="$TMP_ROOT/t031b" bareB="$TMP_ROOT/t031b-bare.git" stubB="$TMP_ROOT/t031b-stub" rcB=0
  build_repo "$repoB" two_entries
  git init -q --bare "$bareB"
  git -C "$repoB" remote add origin "file://$bareB"
  build_stub_gh "$stubB" "$TMP_ROOT/t031b-ghlog" 0
  ( cd "$repoB" && PATH="$stubB:$PATH" bash "$old_engine" --version v9.5.5 --confirm ) \
    >"$TMP_ROOT/t031b.out" 2>"$TMP_ROOT/t031b.err" || rcB=$?
  [[ "$rcB" == "0" ]] || log_fail "TEST-031: the $base_ref engine exited $rcB over the same fixture:"$'\n'"$(cat "$TMP_ROOT/t031b.out" "$TMP_ROOT/t031b.err")"

  sed 's/^- Commit:.*$/- Commit:  <masked>/' "$TMP_ROOT/t031a.out" > "$TMP_ROOT/t031a.masked"
  sed 's/^- Commit:.*$/- Commit:  <masked>/' "$TMP_ROOT/t031b.out" > "$TMP_ROOT/t031b.masked"
  local dcmp=0
  diff -u "$TMP_ROOT/t031b.masked" "$TMP_ROOT/t031a.masked" > "$TMP_ROOT/t031.diff" 2>&1 || dcmp=$?
  [[ "$dcmp" == "0" ]] \
    || log_fail "TEST-031: unprotected-path stdout diverged from the $base_ref engine:"$'\n'"$(cat "$TMP_ROOT/t031.diff")"
  log_pass "TEST-031 unprotected path byte-identical to the $base_ref engine (masked commit line), exit 0, both refs pushed"
}

# --- TEST-032 (Spec-AC-06): any OTHER push failure degrades raw -------------

test_032_non_protected_failure_degrades_raw() {
  log_info "TEST-032: a non-fast-forward rejection keeps today's raw behavior (no fallback, git's own exit code)..."
  local repo="$TMP_ROOT/t032" bare="$TMP_ROOT/t032-bare.git" stub="$TMP_ROOT/t032-stub" other="$TMP_ROOT/t032-other" rc=0
  build_repo "$repo" two_entries
  git init -q --bare "$bare"
  git -C "$repo" remote add origin "file://$bare"
  git -C "$repo" push -q origin main
  git clone -q "$bare" "$other"
  git -C "$other" config user.email "test@example.com"
  git -C "$other" config user.name "AAI Release Test"
  echo "diverged" > "$other/diverged.txt"
  git -C "$other" add -A
  git -C "$other" commit -q -m "diverge the remote"
  git -C "$other" push -q origin main
  build_stub_gh "$stub" "$TMP_ROOT/t032-ghlog" 0

  ( cd "$repo" && PATH="$stub:$PATH" bash "$RELEASE_SH" --version v9.6.0 --confirm ) \
    >"$TMP_ROOT/t032.out" 2>"$TMP_ROOT/t032.err" || rc=$?

  [[ "$rc" != "0" ]] || log_fail "TEST-032: the cut reported success against a diverged remote"
  [[ "$rc" != "17" && "$rc" != "18" ]] \
    || log_fail "TEST-032: a non-fast-forward rejection engaged the protected-branch fallback (exit $rc) — it must degrade raw"
  if git -C "$repo" rev-parse -q --verify "refs/heads/chore/release-v9.6.0" >/dev/null 2>&1; then
    log_fail "TEST-032: a release branch was created for a non-protected failure"
  fi
  [[ "$(git -C "$repo" log -1 --format=%s)" == "chore(release): v9.6.0" ]] \
    || log_fail "TEST-032: the target branch HEAD moved off the release commit (got '$(git -C "$repo" log -1 --format=%s)')"
  grep -qi "rejected" "$TMP_ROOT/t032.err" \
    || log_fail "TEST-032: git's own rejection text never reached stderr:"$'\n'"$(cat "$TMP_ROOT/t032.err")"
  log_pass "TEST-032 non-fast-forward rejection degrades raw (exit $rc, no fallback, git's diagnostic preserved)"
}

# --- TEST-033 (Spec-AC-07, SEAM-3): ps1 twin drives the same fixture --------

test_033_ps1_fallback_parity() {
  log_info "TEST-033: SEAM-3 — the ps1 twin's classifier and fallback match the bash arm on the same fixture..."
  if ! command -v pwsh >/dev/null 2>&1; then
    log_info "TEST-033: pwsh is absent on this host — the ps1 parity arm cannot run here; the CI 'ps1 gate' runs it"
    log_pass "TEST-033 SKIPPED with a named reason (pwsh absent)"
    return 0
  fi

  # (a) classifier unit check through the dot-source seam (the function must
  #     live ABOVE the InvocationName guard, or dot-sourcing defines nothing).
  local cls
  cls="$(pwsh -NoProfile -Command '
    . "'"$RELEASE_PS1"'"
    $yes = Test-ProtectedBranchRejection -Text "remote: error: GH006: Protected branch update failed for refs/heads/main.`nremote: error: 3 of 3 required status checks are expected."
    $no  = Test-ProtectedBranchRejection -Text " ! [rejected] main -> main (non-fast-forward)"
    Write-Output "$yes/$no"
  ' 2>&1)"
  [[ "$cls" == "True/False" ]] \
    || log_fail "TEST-033: dot-sourced Test-ProtectedBranchRejection gave '$cls', expected 'True/False'"

  # (b) the same protected fixture, driven through the ps1 engine.
  local repo="$TMP_ROOT/t033" bare="$TMP_ROOT/t033-bare.git" stub="$TMP_ROOT/t033-stub" log="$TMP_ROOT/t033-ghlog" rc=0 pre_sha n pr_line
  setup_protected_fixture t033
  pre_sha="$(git -C "$repo" rev-parse HEAD)"
  ( cd "$repo" && PATH="$stub:$PATH" pwsh -NoProfile -File "$RELEASE_PS1" --version v9.7.5 --confirm ) \
    >"$TMP_ROOT/t033.out" 2>"$TMP_ROOT/t033.err" || rc=$?
  [[ "$rc" == "17" ]] || log_fail "TEST-033: ps1 engine exited $rc, expected 17:"$'\n'"$(cat "$TMP_ROOT/t033.out" "$TMP_ROOT/t033.err")"
  git -C "$repo" rev-parse -q --verify "refs/heads/chore/release-v9.7.5" >/dev/null 2>&1 \
    || log_fail "TEST-033: ps1 engine did not create chore/release-v9.7.5"
  [[ "$(git -C "$repo" rev-parse HEAD)" == "$pre_sha" ]] \
    || log_fail "TEST-033: ps1 engine did not reset main to its pre-cut SHA"
  git -C "$bare" show-ref --verify --quiet "refs/heads/chore/release-v9.7.5" \
    || log_fail "TEST-033: ps1 engine did not push the release branch"
  [[ -z "$(git -C "$bare" show-ref --tags 2>/dev/null || true)" ]] \
    || log_fail "TEST-033: ps1 engine published a tag on the fallback path"
  n="$(grep -c '^ARGS: pr create ' "$log" || true)"
  [[ "$n" == "1" ]] || log_fail "TEST-033: expected exactly 1 ps1-side 'gh pr create', got $n:"$'\n'"$(cat "$log" 2>/dev/null || true)"
  # SEAM-3, remediation F2: the ps1 helper folds the child's stdout AND stderr
  # into one captured array, so the report line must be pinned to the URL
  # ALONE — gh's stderr progress line (the stub emits one, like the real gh)
  # must never end up interpolated onto the end of it.
  pr_line="$(sed -n 's/^- PR:[[:space:]]*//p' "$TMP_ROOT/t033.out")"
  [[ "$pr_line" == "$STUB_PR_URL" ]] \
    || log_fail "TEST-033: the ps1 report's '- PR:' line must carry the PR URL and nothing else — got '$pr_line':"$'\n'"$(cat "$TMP_ROOT/t033.out")"
  if grep -q 'release create' "$log"; then log_fail "TEST-033: ps1 fallback invoked 'gh release create'"; fi
  if grep -q 'pr merge' "$log"; then log_fail "TEST-033: ps1 fallback invoked 'gh pr merge'"; fi
  log_pass "TEST-033 SEAM-3: ps1 twin classifier + fallback match the bash arm (exit 17, branch, reset, one PR, no tag)"
}

# --- TEST-034 (Spec-AC-08, SEAM-2): exit codes documented + ledger true-up --

test_034_exit_codes_documented() {
  log_info "TEST-034: SEAM-2 — every non-zero exit code aai-release.sh emits is documented in SKILL_RELEASE.prompt.md..."
  local prompt="$PROJECT_ROOT/.aai/SKILL_RELEASE.prompt.md"
  [[ -f "$prompt" ]] || log_fail "TEST-034: .aai/SKILL_RELEASE.prompt.md not found"

  local codes_file="$TMP_ROOT/t034-codes.txt" code
  sed -n 's/^[[:space:]]*exit \([0-9][0-9]*\).*$/\1/p' "$RELEASE_SH" | LC_ALL=C sort -u > "$codes_file"
  [[ -s "$codes_file" ]] || log_fail "TEST-034: no literal 'exit <n>' statements found in aai-release.sh (parser bug)"
  while IFS= read -r code; do
    if [[ -z "$code" || "$code" == "0" ]]; then continue; fi
    grep -qF "exit $code =" "$prompt" \
      || log_fail "TEST-034: aai-release.sh emits exit $code but SKILL_RELEASE.prompt.md never documents it (SEAM-2 drift)"
  done < "$codes_file"

  grep -qF "chore/release-" "$prompt" || log_fail "TEST-034: the prompt never names the chore/release-<version> branch shape"
  grep -qF "git tag -d" "$prompt" || log_fail "TEST-034: the prompt never names 'git tag -d' in the post-merge re-tag sequence"
  grep -qF "git tag -a" "$prompt" || log_fail "TEST-034: the prompt never names 'git tag -a' in the post-merge re-tag sequence"
  grep -qF "git push origin refs/tags/" "$prompt" || log_fail "TEST-034: the prompt never names 'git push origin refs/tags/'"

  # SEAM-4: the diet ledger's own sum must equal the TEST-012 pin this scope bumped.
  local ledger="$PROJECT_ROOT/tests/skills/lib/prompt-diet-ledger.sh"
  local diet="$PROJECT_ROOT/tests/skills/test-aai-prompt-diet.sh"
  local want live
  want="$(sed -n 's/^[[:space:]]*local want_growth=\([-0-9][0-9]*\)[[:space:]]*$/\1/p' "$diet")"
  live="$(bash -c 'set -e; . "$1" >/dev/null 2>&1; printf "%s" "$JUSTIFIED_GROWTH_BYTES"' _ "$ledger")"
  [[ -n "$want" ]] || log_fail "TEST-034: could not read want_growth out of test-aai-prompt-diet.sh"
  [[ "$want" == "$live" ]] \
    || log_fail "TEST-034: prompt-diet ledger sum is $live but TEST-012 pins want_growth=$want — the companion true-up is unpaid"
  log_pass "TEST-034 SEAM-2/SEAM-4: all non-zero exit codes documented, branch shape + re-tag sequence named, ledger sum == TEST-012 pin ($live)"
}

# --- TEST-035 (Spec-AC-09, D5): the fallback's INCOMPLETE arm, exit 18 ------

test_035_fallback_incomplete_exits_18() {
  log_info "TEST-035: a taken chore/release-<version> ref stops the fallback at exit 18 — no clobber, no reset, no PR..."
  local repo="$TMP_ROOT/t035" bare="$TMP_ROOT/t035-bare.git" stub="$TMP_ROOT/t035-stub" log="$TMP_ROOT/t035-ghlog" rc=0 out="$TMP_ROOT/t035.out" squatter
  setup_protected_fixture t035
  # Squat the release branch name at the PRE-cut commit. D3 step 1 must refuse
  # rather than move or reuse an existing ref.
  git -C "$repo" branch "chore/release-v9.8.0" HEAD
  squatter="$(git -C "$repo" rev-parse "refs/heads/chore/release-v9.8.0")"

  ( cd "$repo" && PATH="$stub:$PATH" bash "$RELEASE_SH" --version v9.8.0 --confirm ) \
    >"$out" 2>"$TMP_ROOT/t035.err" || rc=$?

  [[ "$rc" == "18" ]] \
    || log_fail "TEST-035: expected exit 18 (fallback INCOMPLETE), got $rc:"$'\n'"$(cat "$out" "$TMP_ROOT/t035.err")"
  [[ "$(git -C "$repo" rev-parse "refs/heads/chore/release-v9.8.0")" == "$squatter" ]] \
    || log_fail "TEST-035: the pre-existing chore/release-v9.8.0 ref was clobbered"
  [[ "$(git -C "$repo" log -1 --format=%s)" == "chore(release): v9.8.0" ]] \
    || log_fail "TEST-035: the target branch was reset even though the fallback stopped at the branch-name check"
  grep -qF "FALLBACK INCOMPLETE" "$out" || log_fail "TEST-035: the report never names the incomplete fallback:"$'\n'"$(cat "$out")"
  grep -qF "already exists" "$out" || log_fail "TEST-035: the report never names the reason (branch already exists):"$'\n'"$(cat "$out")"
  grep -qF "gh pr create --base main --head chore/release-v9.8.0" "$out" \
    || log_fail "TEST-035: the report does not name the manual 'gh pr create' command:"$'\n'"$(cat "$out")"
  if [[ -f "$log" ]] && grep -q 'pr create' "$log"; then
    log_fail "TEST-035: the INCOMPLETE fallback opened a PR anyway: $(cat "$log")"
  fi
  [[ -z "$(git -C "$bare" show-ref 2>/dev/null || true)" ]] \
    || log_fail "TEST-035: the INCOMPLETE fallback published refs to the remote: $(git -C "$bare" show-ref)"
  log_pass "TEST-035 D5 exit 18: a taken release-branch name stops the fallback before the reset, names the manual commands, opens no PR"
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
  test_022_live_changelog_scaffold_invariants
  test_023_cut_consumes_existing_scaffold
  test_024_no_deleted_unreleased_heading_vs_main
  test_025_released_region_pin_vs_tag
  test_026_released_region_scratch_matrix
  test_027_protected_branch_fallback
  test_028_fallback_never_publishes_or_merges
  test_029_tag_is_local_and_report_names_the_repoint
  test_030_followtags_cannot_orphan_the_tag
  test_031_unprotected_path_byte_identical
  test_032_non_protected_failure_degrades_raw
  test_033_ps1_fallback_parity
  test_034_exit_codes_documented
  test_035_fallback_incomplete_exits_18

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
