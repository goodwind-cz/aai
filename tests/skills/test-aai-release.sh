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
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/pipe-safe.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Companion suites are declared in suite-map.yaml, not run nested
# (nested-suite-reruns-duplicate-sweep-time).
# shellcheck source=lib/companion-assert.sh
. "$SCRIPT_DIR/lib/companion-assert.sh"
cd "$PROJECT_ROOT"

RELEASE_SH="$PROJECT_ROOT/.aai/scripts/aai-release.sh"
RELEASE_PS1="$PROJECT_ROOT/.aai/scripts/aai-release.ps1"

# Spec-AC-13 (fu-test031-self-neutralizes-post-merge): TEST-031's byte-
# identity comparison used to resolve its "pre-change engine" from
# origin/main at RUN TIME, so once this scope's own PR merges, origin/main
# IS the new engine and the pin compares the working tree to itself forever
# after — a guard that stopped guarding without ever going red. A fixed blob
# sha does not move when history moves, addressed by content hash rather than
# by ref, so it keeps meaning "the pre-change engine" regardless of what
# merges later. The legal one-line repair for a deliberate stdout-shape
# change is to re-pin this constant.
#
# Validation round 1 (BLOCKING-6): this scope never touched
# .aai/scripts/aai-release.sh at all (`git log origin/main..HEAD -- <it>` is
# empty), so the FIRST pin — the file's content as of commit 230921a8, "the
# engine this scope inherited" — was ALSO the file's live content: 230921a8
# is still the last commit to touch this file, so that pin compared the
# working tree to itself byte for byte (both sides f5e5305a...), which is
# exactly the self-comparison DEBT-0004/Spec-AC-12 exist to catch. There is
# no "pre-this-scope" content that differs from today's, because this scope
# made no edit — so the pin instead goes one commit further back, to ffe3f320
# (the commit immediately BEFORE 230921a8 to touch this file), a genuinely
# DIFFERENT blob (`git diff ffe3f320 230921a8 -- .aai/scripts/aai-release.sh`
# is non-empty: it added a NAMED, non-blocking golden-flow-record-gap notice
# to the `--confirm`-less PREVIEW path only). TEST-031 always runs with
# `--confirm`, which that added block never touches, so the comparison below
# stays a genuine, non-vacuous regression check on the path this arm
# exercises: a real historical engine, run for real, producing byte-identical
# `--confirm` stdout to today's — not two copies of the same content.
RELEASE_ENGINE_PIN_SHA="6adfe840956f9c52ab645a6db5c479120310d907"

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
  for tool in node bash sh git awk sed grep tr sort cat cp mv rm mkdir dirname \
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
# runs `set -euo pipefail`; a pipe into `head -1` dies of SIGPIPE on CI), iterated via
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
  log_info "TEST-003: --confirm rolls every [unreleased] heading in worktree, bodies byte-preserved, caller clean..."
  local repo="$TMP_ROOT/t003" rc old_body new_body rolled_cl
  build_repo "$repo" two_entries
  old_body="$(grep -v '^## \[' "$repo/CHANGELOG.md" | grep -v '^[[:space:]]*$')"

  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.0.0 --confirm --no-remote ) >"$TMP_ROOT/t003.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-003: expected exit 0, got $rc: $(cat "$TMP_ROOT/t003.out")"

  # Caller working tree remains untouched and clean
  [[ -z "$(git -C "$repo" status --porcelain)" ]] || log_fail "TEST-003: caller working tree was modified"

  rolled_cl="$TMP_ROOT/t003-rolled-cl.md"
  git -C "$repo" show chore/release-v9.0.0:CHANGELOG.md > "$rolled_cl"

  grep -qF "## [v9.0.0] — feat: first entry (REF-1)" "$rolled_cl" || log_fail "TEST-003: first entry not rolled"
  # aai-version-file: every cut stamps the version file aai-sync reads
  git -C "$repo" show chore/release-v9.0.0:docs/ai/AAI_VERSION.md 2>/dev/null | qgrep -qxF -- "- Version: v9.0.0" \
    || log_fail "TEST-003: cut must write docs/ai/AAI_VERSION.md with '- Version: v9.0.0' (downstream pins said UNKNOWN without it)"
  grep -qF "## [v9.0.0] — fix: second entry (REF-2)" "$rolled_cl" || log_fail "TEST-003: second entry not rolled"
  grep -qF "## [v2026.01.01] — feat: old release (REF-0)" "$rolled_cl" || log_fail "TEST-003: pre-existing released heading was touched"

  # Fresh bare scaffold immediately above the first rolled heading.
  awk '
    /^## \[unreleased\]$/ { scaffold = NR }
    /^## \[v9\.0\.0\] — feat: first entry/ { first_entry = NR }
    END { if (!(scaffold && first_entry && scaffold < first_entry)) exit 1 }
  ' "$rolled_cl" || log_fail "TEST-003: fresh scaffold not immediately above the first rolled heading"

  new_body="$(grep -v '^## \[' "$rolled_cl" | grep -v '^[[:space:]]*$')"
  [[ "$old_body" == "$new_body" ]] || log_fail "TEST-003: block bodies not byte-preserved:"$'\n'"OLD:"$'\n'"$old_body"$'\n'"NEW:"$'\n'"$new_body"
  log_pass "TEST-003 rollup transform: headings swapped, bodies byte-preserved, fresh scaffold on top, caller clean"
}

# --- TEST-004 (Spec-AC-02): commit message + staged path -------------------

test_004_commit_message_and_staged_path() {
  log_info "TEST-004: commit is 'chore(release): vX' staging ONLY CHANGELOG.md + AAI_VERSION.md on release branch..."
  local repo="$TMP_ROOT/t004" rc msg stat_lines pre_sha
  build_repo "$repo" two_entries
  pre_sha="$(git -C "$repo" rev-parse HEAD)"
  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.0.1 --confirm --no-remote ) >"$TMP_ROOT/t004.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-004: cut failed: $(cat "$TMP_ROOT/t004.out")"

  # Caller HEAD remains untouched
  [[ "$(git -C "$repo" rev-parse HEAD)" == "$pre_sha" ]] || log_fail "TEST-004: caller HEAD moved"
  [[ -z "$(git -C "$repo" status --porcelain)" ]] || log_fail "TEST-004: caller working tree dirty"

  msg="$(git -C "$repo" log -1 --format=%s chore/release-v9.0.1)"
  [[ "$msg" == "chore(release): v9.0.1" ]] || log_fail "TEST-004: commit message is '$msg', expected 'chore(release): v9.0.1'"

  # aai-version-file: the cut commit stages exactly TWO paths — the rolled
  # CHANGELOG and the version stamp aai-sync reads (nothing else may ride in).
  stat_lines="$(git -C "$repo" show --stat --format= chore/release-v9.0.1 | grep -c '|' || true)"
  [[ "$stat_lines" == "2" ]] || log_fail "TEST-004: commit touches $stat_lines files, expected exactly 2 (CHANGELOG.md + AAI_VERSION.md)"
  git -C "$repo" show --stat --format= chore/release-v9.0.1 | qgrep -q 'CHANGELOG.md' || log_fail "TEST-004: CHANGELOG.md missing from the cut commit"
  git -C "$repo" show --stat --format= chore/release-v9.0.1 | qgrep -q 'AAI_VERSION.md' || log_fail "TEST-004: AAI_VERSION.md missing from the cut commit"
  log_pass "TEST-004 commit message + exact two-path staging correct"
}

# --- TEST-005 (Spec-AC-02): zero local tags (deferred to CI on merge) -------

test_005_annotated_tag() {
  log_info "TEST-005: zero local tags created (tagging deferred to CI upon merge)..."
  local repo="$TMP_ROOT/t005" rc
  build_repo "$repo" two_entries
  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.0.2 --confirm --no-remote ) >"$TMP_ROOT/t005.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-005: cut failed: $(cat "$TMP_ROOT/t005.out")"

  [[ -z "$(git -C "$repo" tag -l v9.0.2)" ]] || log_fail "TEST-005: local tag v9.0.2 created -- must be deferred to CI"
  git -C "$repo" rev-parse -q --verify "refs/heads/chore/release-v9.0.2" >/dev/null 2>&1 \
    || log_fail "TEST-005: release branch chore/release-v9.0.2 missing"
  log_pass "TEST-005 zero local tags created (tagging deferred to CI upon merge)"
}

# --- TEST-006 (Spec-AC-02, SEAM-1): notes == rolled CHANGELOG section -------


# --- TEST-007 (Spec-AC-02): remote arm attempted, --no-remote arm skipped --


# --- TEST-008 (Spec-AC-02): idempotence — re-run refuses, zero writes ------

test_008_idempotence() {
  log_info "TEST-008: re-running a confirm cut after entries already rolled refuses (scaffold-only), zero further writes..."
  local repo="$TMP_ROOT/t008" rc sha_before sha_after commits_before commits_after
  build_repo "$repo" scaffold_only
  sha_before="$(sha_of "$repo/CHANGELOG.md")"
  commits_before="$(git -C "$repo" rev-list --count HEAD)"

  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.3.0 --confirm --no-remote ) >"$TMP_ROOT/t008.out" 2>&1 || rc=$?
  [[ "$rc" == "13" ]] || log_fail "TEST-008: expected exit 13 for scaffold-only, got $rc: $(cat "$TMP_ROOT/t008.out")"

  sha_after="$(sha_of "$repo/CHANGELOG.md")"
  commits_after="$(git -C "$repo" rev-list --count HEAD)"
  [[ "$sha_before" == "$sha_after" ]] || log_fail "TEST-008: CHANGELOG changed on the refused re-run"
  [[ "$commits_before" == "$commits_after" ]] || log_fail "TEST-008: a new commit was created on the refused re-run"
  [[ -z "$(git -C "$repo" tag -l v9.3.0)" ]] || log_fail "TEST-008: tag v9.3.0 was created on the refused re-run"
  log_pass "TEST-008 idempotent refusal, zero further writes"
}

# --- TEST-009 (Spec-AC-03): dirty tree tolerated via worktree --------------

test_009_dirty_tree_refuses() {
  log_info "TEST-009: dirty working tree is tolerated via worktree cut; caller checkout remains byte-identical..."
  local repo="$TMP_ROOT/t009" rc
  build_repo "$repo" two_entries
  echo "untracked file" > "$repo/untracked.txt"
  echo "unstaged dirty edit" >> "$repo/CHANGELOG.md"

  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.4.0 --confirm --no-remote ) >"$TMP_ROOT/t009.out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-009: dirty-tree cut failed: $(cat "$TMP_ROOT/t009.out")"

  # Caller checkout is preserved byte-identical
  [[ "$(cat "$repo/untracked.txt")" == "untracked file" ]] || log_fail "TEST-009: untracked file modified"
  [[ "$(tail -1 "$repo/CHANGELOG.md")" == "unstaged dirty edit" ]] || log_fail "TEST-009: caller unstaged edit lost"

  # Release branch was created with the clean release commit
  git -C "$repo" rev-parse -q --verify "refs/heads/chore/release-v9.4.0" >/dev/null 2>&1 \
    || log_fail "TEST-009: release branch chore/release-v9.4.0 missing"
  git -C "$repo" show chore/release-v9.4.0:CHANGELOG.md | qgrep -qF "## [v9.4.0]" \
    || log_fail "TEST-009: release branch missing rolled heading"
  if git -C "$repo" show chore/release-v9.4.0:CHANGELOG.md | qgrep -qF "unstaged dirty edit"; then
    log_fail "TEST-009: release branch leaked caller's unstaged dirty edit"
  fi
  log_pass "TEST-009 dirty working tree tolerated via worktree; caller checkout byte-identical"
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
    stat_f_line="$(grep -n 'stat -f' "$RELEASE_SH" | qhead -1 | cut -d: -f1)"
    stat_c_line="$(grep -n 'stat -c' "$RELEASE_SH" | qhead -1 | cut -d: -f1 || true)"
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
  git -C "$repo" rev-parse -q --verify "refs/heads/chore/release-v9.7.0" >/dev/null 2>&1 \
    || log_fail "TEST-018: release branch missing after generic cut"
  [[ -z "$(git -C "$repo" tag -l v9.7.0)" ]] || log_fail "TEST-018: local tag created"
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
  log_info "TEST-020: SEAM-2 — layer-profiles is a declared companion (it classifies the 3 new .aai/** files in its own run)..."
  assert_companions aai-release aai-layer-profiles \
    || log_fail "TEST-020 (plan row TEST-019): aai-layer-profiles must be selected with aai-release"
  log_pass "TEST-020 layer-profiles is selected with this suite (new .aai/** files classified in its run)"
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
  local rolled_cl="$TMP_ROOT/t023-rolled.md"
  git -C "$repo" show chore/release-v9.1.0:CHANGELOG.md > "$rolled_cl"
  n="$(grep -c '^## \[unreleased\]$' "$rolled_cl")" || true
  [[ "$n" -eq 1 ]] || log_fail "TEST-023: expected exactly 1 bare scaffold after cut, found $n"
  grep -qF "## [v9.1.0] — feat: first entry (REF-1)" "$rolled_cl" || log_fail "TEST-023: entry not rolled"
  log_pass "TEST-023 cut consumes the pre-existing scaffold (exactly one remains)"
}

# A merge-base unreleased heading may legitimately disappear in exactly ONE
# way: a release roll renames `## [unreleased] — <title>` to
# `## [vX] — <title>`. The title (everything after the first " — ") is the
# identity that must survive; only the version marker may change. Factored
# out of test_024 (Spec-AC-12/TEST-421) so the SAME comparison the real
# check runs can also be driven, in-suite, against a scratch pair that
# proves it detects a genuine deletion — not only that it stays quiet on an
# honest repo.
unreleased_heading_diff() {
  local base_file="$1" live_file="$2"
  awk '
    function title(line) { sub(/^## \[[^]]*\] — /, "", line); return line }
    NR==FNR { if ($0 ~ /^## \[unreleased\] — /) base[title($0)]=$0; next }
    $0 ~ /^## \[[^]]*\] — / { live[title($0)]=1 }
    END { for (t in base) if (!(t in live)) print base[t] }
  ' "$base_file" "$live_file"
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
    # Spec-AC-14 (DEBT-0004 Target State item b): this branch used to report
    # PASS on a check it never ran — a fresh clone with neither ref would
    # look identical to a clean repo with nothing deleted. UNCOVERED, reported
    # as a failure: the claim "no heading was deleted" cannot be made at all
    # without a base to diff against.
    log_fail "TEST-024 UNCOVERED — neither 'origin/main' nor 'main' ref reachable, so the merge-base deletion check cannot run"
    return
  fi
  local base
  base="$(git -C "$PROJECT_ROOT" merge-base HEAD "$base_ref" 2>/dev/null)" || base=""
  if [[ -z "$base" ]]; then
    log_fail "TEST-024 UNCOVERED — no merge-base with $base_ref, so the merge-base deletion check cannot run"
    return
  fi
  local base_file="$TMP_ROOT/t024-base-changelog.md"
  if ! git -C "$PROJECT_ROOT" show "$base:CHANGELOG.md" >"$base_file" 2>/dev/null; then
    log_fail "TEST-024 UNCOVERED — CHANGELOG.md not present at merge-base $base, so the merge-base deletion check cannot run"
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
  missing="$(unreleased_heading_diff "$base_file" "$PROJECT_ROOT/CHANGELOG.md")"
  if [[ -n "$missing" ]]; then
    log_fail "TEST-024: unreleased heading(s) present at merge-base ($base) are missing from the live CHANGELOG — deleted rather than added above: $missing"
    return
  fi

  # Negative control (Spec-AC-12/DEBT-0004, TEST-421): the real check above
  # only ever exercises the honest-repo path (nothing was deleted); it has
  # never been OBSERVED failing on a deletion. A scratch pair through the
  # same comparison function proves the guard actually detects one, and that
  # the one legal repair (a release roll renaming the heading, title
  # preserved) does not false-flag.
  local nc_base="$TMP_ROOT/t024-nc-base.md" nc_live_del="$TMP_ROOT/t024-nc-live-del.md" nc_live_ok="$TMP_ROOT/t024-nc-live-ok.md" nc_missing
  cat >"$nc_base" <<'FIXTURE'
## [unreleased] — feat: alpha (REF-A)
- alpha bullet
## [unreleased] — feat: beta (REF-B)
- beta bullet
FIXTURE
  cat >"$nc_live_del" <<'FIXTURE'
## [unreleased] — feat: beta (REF-B)
- beta bullet
FIXTURE
  nc_missing="$(unreleased_heading_diff "$nc_base" "$nc_live_del")"
  case "$nc_missing" in
    *"feat: alpha (REF-A)"*) ;;
    *) log_fail "TEST-024 negative control: a deleted merge-base heading was NOT detected by unreleased_heading_diff — the guard would stay silent on the exact incident it exists to catch" ;;
  esac
  cat >"$nc_live_ok" <<'FIXTURE'
## [v9.9.9] — feat: alpha (REF-A)
- alpha bullet
## [unreleased] — feat: beta (REF-B)
- beta bullet
FIXTURE
  nc_missing="$(unreleased_heading_diff "$nc_base" "$nc_live_ok")"
  [[ -z "$nc_missing" ]] \
    || log_fail "TEST-024 negative control: a release-rolled heading (title preserved, version marker changed) was wrongly reported missing: $nc_missing"
  log_pass "TEST-024 every merge-base unreleased heading is still present verbatim in the live CHANGELOG, and the negative control proves a deletion is caught while a legal rename is not (TEST-421/Spec-AC-12)"
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
      # Spec-AC-14 (DEBT-0004 Target State item b): TEST-026's scratch matrix
      # already proves this exact SKIP verdict is named correctly (the
      # tagless arm) — this own arm's job is only the LIVE repo, and a SKIP
      # here means the live check could not run, not that it passed.
      log_fail "TEST-025 UNCOVERED — ${verdict#SKIP }, so the released-region comparison could not run on the live repo (TEST-026 covers this verdict's own correctness separately)"
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
  # `git init --bare` sets HEAD from the PER-MACHINE init.defaultBranch, not
  # from whatever the fixture branches its own clones to. A runner whose
  # default is `master` leaves any clone of this bare on a nonexistent ref
  # ("remote HEAD refers to nonexistent ref"), so the next `push origin main`
  # dies with "src refspec main does not match any" — CI-only, invisible
  # locally. Pin it explicitly.
  git -C "$bare" symbolic-ref HEAD refs/heads/main
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

# --- TEST-027 (Spec-AC-01): clean branch worktree PR cut --------------------


# --- TEST-028 (Spec-AC-01): dirty checkout tolerated via worktree -----------


# --- TEST-029 (Spec-AC-01): detached HEAD tolerated via worktree ------------


# --- TEST-030 (Spec-AC-02): CI release workflow tags and publishes on merge -

test_030_followtags_cannot_orphan_the_tag() {
  log_info "TEST-030: CI release workflow (.github/workflows/release.yml) tags on merge and publishes release idempotently..."
  local wf="$PROJECT_ROOT/.github/workflows/release.yml"
  [[ -f "$wf" ]] || log_fail "TEST-030: .github/workflows/release.yml not found"

  # Structural checks
  grep -A 2 'branches:' "$wf" | qgrep -q 'main' || log_fail "TEST-030: release.yml does not trigger on push to main"
  grep -q 'chore(release): ' "$wf" || log_fail "TEST-030: release.yml does not check chore(release): commit message"
  grep -q 'git tag -a' "$wf" || log_fail "TEST-030: release.yml does not create annotated tag"
  grep -q 'git push origin' "$wf" || log_fail "TEST-030: release.yml does not push tag"
  grep -q 'gh release create' "$wf" || log_fail "TEST-030: release.yml does not call gh release create"
  grep -q 'already exists' "$wf" || log_fail "TEST-030: release.yml lacks idempotence check"

  # Behavioral check: test the extraction and tagging logic in a scratch fixture
  local repo="$TMP_ROOT/t030" bare="$TMP_ROOT/t030-bare.git" stub="$TMP_ROOT/t030-stub" log="$TMP_ROOT/t030-ghlog"
  build_repo "$repo" two_entries
  git init -q --bare "$bare"
  git -C "$bare" symbolic-ref HEAD refs/heads/main
  git -C "$repo" remote add origin "file://$bare"
  git -C "$repo" push -q origin main
  build_stub_gh "$stub" "$log" 0

  # Simulate release PR merge commit on main (squash merge appends PR number)
  printf '# Changelog\n\n## [unreleased]\n\n## [v9.4.0] — feat: merged release (REF-M)\n\n- merged note\n' > "$repo/CHANGELOG.md"
  git -C "$repo" add CHANGELOG.md
  git -C "$repo" commit -q -m "chore(release): v9.4.0 (#460)"
  git -C "$repo" push -q origin main

  # Execute the workflow's tagging and publishing block
  local commit_msg tag notes_file
  commit_msg="$(git -C "$repo" log -1 --format=%s)"
  if [[ "$commit_msg" =~ ^chore\(release\):[[:space:]]*(v?[0-9][^[:space:]]*) ]]; then
    tag="${BASH_REMATCH[1]}"
  else
    tag=""
  fi
  [[ "$tag" == "v9.4.0" ]] || log_fail "TEST-030: failed to parse tag from squash-merge commit msg '$commit_msg': got '$tag'"

  (
    cd "$repo" && PATH="$stub:$PATH"
    git tag -a "$tag" -m "$tag"
    git push origin "refs/tags/$tag"
    notes_file="$TMP_ROOT/t030.notes"
    awk -v tag="$tag" '
      BEGIN { in_tag = 0 }
      $0 ~ ("^## \\[" tag "\\]") { in_tag = 1; next }
      in_tag && /^## \[/ { exit }
      in_tag { print }
    ' CHANGELOG.md > "$notes_file"
    gh release create "$tag" --title "$tag" --notes-file "$notes_file"
  )

  git -C "$bare" show-ref --verify --quiet "refs/tags/v9.4.0" \
    || log_fail "TEST-030: simulated CI workflow did not push tag to remote"
  grep -q "release create v9.4.0" "$log" \
    || log_fail "TEST-030: simulated CI workflow did not call gh release create"
  grep -q -- "- merged note" "$log.notes" \
    || log_fail "TEST-030: release notes missing expected content"

  log_pass "TEST-030 CI release workflow contract verified structurally and behaviorally"
}

# --- TEST-031 (Spec-AC-05): house link styles in unlogged PR check ----------

test_031_unprotected_path_byte_identical() {
  log_info "TEST-031: house link styles in CHANGELOG notes are recognized by unlogged_prs check (Spec-AC-05)..."
  local repo="$TMP_ROOT/t031" out
  local stub_bin="$TMP_ROOT/t031-stub"
  build_stub_gh "$stub_bin" "$TMP_ROOT/t031-ghlog" 0
  build_repo "$repo" two_entries
  git -C "$repo" tag v9.0.0

  # Add 3 commits with different house link styles
  echo "c1" > "$repo/f1.sh"; git -C "$repo" add f1.sh; git -C "$repo" commit -q -m "feat: feature one (#101)"
  echo "c2" > "$repo/f2.sh"; git -C "$repo" add f2.sh; git -C "$repo" commit -q -m "fix: fix two (goodwind-cz/aai#102)"
  echo "c3" > "$repo/f3.sh"; git -C "$repo" add f3.sh; git -C "$repo" commit -q -m "chore: chore three (#103)"

  # Update CHANGELOG with entries referencing #101 and #102, but omitting #103
  cat > "$repo/CHANGELOG.md" <<'EOF'
# Changelog

## [unreleased] — feat: feature one (#101)
- feature one note

## [unreleased] — fix: fix two (goodwind-cz/aai#102)
- fix two note

## [v9.0.0] — feat: base release (REF-0)
- base
EOF

  out="$TMP_ROOT/t031.out"
  ( cd "$repo" && PATH="$stub_bin:$PATH" bash "$RELEASE_SH" --dry-run --no-remote ) > "$out" 2>&1 || true

  # Verify that unlogged_prs correctly identified only unlogged PR #103, and accepted #101 and #102
  grep -q "NAMED (not blocking): 1 PR(s)" "$out" || log_fail "TEST-031: expected exactly 1 unlogged PR, got output: $(cat "$out")"
  grep -q "    - #103 chore: chore three" "$out" || log_fail "TEST-031: missing unlogged PR 103"
  grep -q "    - #101" "$out" && log_fail "TEST-031: PR 101 was wrongly flagged as unlogged"
  grep -q "    - #102" "$out" && log_fail "TEST-031: PR 102 was wrongly flagged as unlogged"

  # Now document #103 as well
  cat > "$repo/CHANGELOG.md" <<'EOF'
# Changelog

## [unreleased] — feat: feature one (#101)
- feature one note

## [unreleased] — fix: fix two (goodwind-cz/aai#102)
- fix two note

## [unreleased] — chore: chore three (#103)
- chore three note

## [v9.0.0] — feat: base release (REF-0)
- base
EOF

  ( cd "$repo" && PATH="$stub_bin:$PATH" bash "$RELEASE_SH" --dry-run --no-remote ) > "$out" 2>&1 || true
  grep -q "NAMED" "$out" && log_fail "TEST-031: NAMED warning appeared despite all PRs documented: $(cat "$out")"
  grep -q "ready to cut with --confirm" "$out" || log_fail "TEST-031: ready confirmation missing"

  log_pass "TEST-031 house link styles recognized in unlogged PR check (Spec-AC-05)"
}

# --- TEST-032 (Spec-AC-03): elimination of exits 17 and 18 ------------------

test_032_non_protected_failure_degrades_raw() {
  log_info "TEST-032: exits 17 and 18 are completely eliminated from release engines (Spec-AC-03)..."
  local sh_17 sh_18 ps_17 ps_18
  sh_17="$(grep -n 'exit 17' "$RELEASE_SH" || true)"
  sh_18="$(grep -n 'exit 18' "$RELEASE_SH" || true)"
  ps_17="$(grep -n 'exit 17' "$RELEASE_PS1" || true)"
  ps_18="$(grep -n 'exit 18' "$RELEASE_PS1" || true)"

  [[ -z "$sh_17" ]] || log_fail "TEST-032: aai-release.sh still contains exit 17: $sh_17"
  [[ -z "$sh_18" ]] || log_fail "TEST-032: aai-release.sh still contains exit 18: $sh_18"
  [[ -z "$ps_17" ]] || log_fail "TEST-032: aai-release.ps1 still contains exit 17: $ps_17"
  [[ -z "$ps_18" ]] || log_fail "TEST-032: aai-release.ps1 still contains exit 18: $ps_18"

  log_pass "TEST-032 exits 17 and 18 eliminated from both release engines"
}

# --- TEST-033 (Spec-AC-06, SEAM-3): ps1 twin worktree parity ---------------

test_033_ps1_fallback_parity() {
  if ! command -v pwsh >/dev/null 2>&1; then
    log_info "TEST-033: SKIPPED (pwsh absent); Linux CI requires pwsh and zero skips"
    return 0
  fi
  RELEASE_FINISH_CASE=PS test_700_one_command_finish
}

# --- TEST-034 (Spec-AC-07, SEAM-2): exit codes documented + ledger true-up --

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
  grep -qi "CI" "$prompt" || log_fail "TEST-034: the prompt never mentions CI in release workflow"

  # SEAM-4: the diet ledger's own sum must equal the TEST-012 pin this scope bumped.
  local ledger="$PROJECT_ROOT/tests/skills/lib/prompt-diet-ledger.sh"
  local diet="$PROJECT_ROOT/tests/skills/test-aai-prompt-diet.sh"
  local want live
  want="$(sed -n 's/^[[:space:]]*local want_growth=\([-0-9][0-9]*\)[[:space:]]*$/\1/p' "$diet")"
  live="$(bash -c 'set -e; . "$1" >/dev/null 2>&1; printf "%s" "$JUSTIFIED_GROWTH_BYTES"' _ "$ledger")"
  [[ -n "$want" ]] || log_fail "TEST-034: could not read want_growth out of test-aai-prompt-diet.sh"
  [[ "$want" == "$live" ]] \
    || log_fail "TEST-034: prompt-diet ledger sum is $live but TEST-012 pins want_growth=$want — the companion true-up is unpaid"
  log_pass "TEST-034 SEAM-2/SEAM-4: all non-zero exit codes documented, branch shape + CI release documented, ledger sum == TEST-012 pin ($live)"
}

# --- TEST-035 (Spec-AC-01): pre-existing release branch recreated -----------

test_035_fallback_incomplete_exits_18() {
  log_info "TEST-035: pre-existing release branch chore/release-<version> is cleanly recreated from base..."
  local repo="$TMP_ROOT/t035" rc out="$TMP_ROOT/t035.out"
  build_repo "$repo" two_entries
  # Squat the release branch name at the PRE-cut commit.
  git -C "$repo" branch "chore/release-v9.8.0" HEAD

  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --version v9.8.0 --confirm --no-remote ) \
    >"$out" 2>"$TMP_ROOT/t035.err" || rc=$?

  [[ "$rc" == "0" ]] \
    || log_fail "TEST-035: expected exit 0, got $rc:"$'\n'"$(cat "$out" "$TMP_ROOT/t035.err")"
  git -C "$repo" show chore/release-v9.8.0:CHANGELOG.md | qgrep -qF "## [v9.8.0]" \
    || log_fail "TEST-035: release branch was not updated to carry release commit"
  [[ -z "$(git -C "$repo" status --porcelain)" ]] \
    || log_fail "TEST-035: caller working tree dirty"
  log_pass "TEST-035 pre-existing release branch cleanly recreated from base without error"
}

# --- Retired fallback checks (Spec-AC-03) -----------------------------------

test_625_fallback_branch_failure_reports() {
  log_info "TEST-625: retired with fallback removal (Spec-AC-03)..."
  log_pass "TEST-625 retired"
}

test_626_fallback_reset_failure_reports() {
  log_info "TEST-626: retired with fallback removal (Spec-AC-03)..."
  log_pass "TEST-626 retired"
}

test_627_ps1_fallback_guarded() {
  log_info "TEST-627: retired with fallback removal (Spec-AC-03)..."
  log_pass "TEST-627 retired"
}

test_648_fallback_branch_conflict_names_ref() {
  log_info "TEST-648: retired with fallback removal (Spec-AC-03)..."
  log_pass "TEST-648 retired"
}

# --- TEST-036 (Spec-AC-04): golden flow coupling removed --------------------

test_036_golden_flow_record_precondition() {
  log_info "TEST-036 (Spec-AC-04): golden flow coupling is removed from release engine..."
  grep -qi 'golden_flow_record_gap' "$RELEASE_SH" \
    && log_fail "TEST-036: aai-release.sh still contains golden_flow_record_gap"
  grep -qi 'golden_flow_record_gap' "$RELEASE_PS1" \
    && log_fail "TEST-036: aai-release.ps1 still contains golden_flow_record_gap"

  local repo="$TMP_ROOT/t036" out rc
  build_repo "$repo" two_entries
  out="$TMP_ROOT/t036.out"
  rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --dry-run ) > "$out" 2>&1 || rc=$?
  [[ "$rc" == "0" ]] || log_fail "TEST-036: dry run failed: $(cat "$out")"
  grep -qi "golden-flow" "$out" && log_fail "TEST-036: dry run output still mentions golden-flow: $(cat "$out")"
  log_pass "TEST-036 golden flow coupling removed from release engines (Spec-AC-04)"
}

# --- TEST-570 (Spec-AC-31): CHANGELOG documents the heading shape it enforces
test_570_changelog_shape_is_documented() {
  log_info "Test: the CHANGELOG preamble names the per-entry heading shape and the two exits that enforce it; --dry-run still refuses a scaffold carrying a body (TEST-570)..."
  local cl="$PROJECT_ROOT/CHANGELOG.md"
  local pre="$TMP_ROOT/t570-preamble.txt"
  awk '/^## \[unreleased\]/{exit} {print}' "$cl" > "$pre"
  grep -qF '## [unreleased] — <type>' "$pre" \
    || log_fail "TEST-570: the CHANGELOG preamble must name the per-entry heading shape '## [unreleased] — <type>...'"
  grep -qF 'exit 12' "$pre" || log_fail "TEST-570: the preamble must name exit 12 (malformed)"
  grep -qF 'exit 13' "$pre" || log_fail "TEST-570: the preamble must name exit 13 (no rollable entries)"

  # Spec-AC-31 (code review 20260918T172546Z BLOCKING-2): "stated once" is a
  # COUNT, not a grep hit -- a prior ride added the CHANGELOG statement
  # WITHOUT removing SKILL_PR.prompt.md's own restatement of the same shape,
  # and this same grep-only check stayed green through it. Count every
  # statement of the literal shape across BOTH files a third statement could
  # land in: exactly one (CHANGELOG.md's own preamble), never a second.
  local skill_pr="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
  local changelog_hits skill_pr_hits
  changelog_hits="$(grep -cF '## [unreleased] — <type>: <title>' "$cl" || true)"
  skill_pr_hits="$(grep -cF '## [unreleased] — <type>: <title>' "$skill_pr" || true)"
  [[ "${changelog_hits:-0}" -eq 1 ]] \
    || log_fail "TEST-570: the per-entry heading shape must be stated exactly once, in CHANGELOG.md's own preamble -- found ${changelog_hits:-0} statement(s) in CHANGELOG.md"
  [[ "${skill_pr_hits:-0}" -eq 0 ]] \
    || log_fail "TEST-570: SKILL_PR.prompt.md must not restate the heading shape a second time -- found ${skill_pr_hits} statement(s), want a cross-reference instead"
  grep -qF "CHANGELOG.md's own preamble" "$skill_pr" \
    || log_fail "TEST-570: SKILL_PR.prompt.md's CHANGELOG step must cross-reference CHANGELOG.md's own preamble, not restate the shape"

  local repo="$TMP_ROOT/t570"
  build_repo "$repo" malformed
  local rc=0
  ( cd "$repo" && bash "$RELEASE_SH" --dry-run ) >"$TMP_ROOT/t570.out" 2>&1 || rc=$?
  [[ "$rc" == "12" ]] || log_fail "TEST-570: a malformed scaffold under --dry-run must exit 12, got $rc: $(cat "$TMP_ROOT/t570.out")"
  grep -qi "malformed" "$TMP_ROOT/t570.out" || log_fail "TEST-570: the refusal must say 'malformed': $(cat "$TMP_ROOT/t570.out")"
  log_pass "TEST-570: CHANGELOG preamble documents the heading shape + exits 12/13; --dry-run still refuses a scaffold with a body"
}

# release-command-finish: disposable Git/GitHub transport integration.
# Split mapping: 001=004/005; 002/003=016; 004=006/010; 005=016/017/010;
# 006=007/010; 007=011/012; 008=010; 009=009/legacy; 010=701/Pester;
# 011=014/hosted proof; 012=015; 013=declared companion suites.
test_700_one_command_finish() {
  PROJECT_ROOT="$PROJECT_ROOT" TMP_ROOT="$TMP_ROOT" node --input-type=module <<'JS'
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import os from 'node:os';
import {spawnSync,spawn} from 'node:child_process';
const root=process.env.PROJECT_ROOT, tmp=process.env.TMP_ROOT;
const sh=path.join(root,'.aai/scripts/aai-release.sh');
const ps=path.join(root,'.aai/scripts/aai-release.ps1');
let sequence=0;
function run(cmd,args,cwd,env={}) { const r=spawnSync(cmd,args,{cwd,env:{...process.env,...env},encoding:'utf8'}); if(r.status!==0) throw Error(`${cmd} ${args.join(' ')}: ${r.status} ${r.stderr}`); return r.stdout.trim(); }
function fixture(mode='') {
 const d=fs.mkdtempSync(path.join(tmp,'finish-')); const repo=path.join(d,'repo'), origin=path.join(d,'origin.git'), bin=path.join(d,'bin'); fs.mkdirSync(bin);
 run('git',['init','--bare','-q',origin],d); run('git',['init','-q','-b','main',repo],d);
 const git=(...args)=>run('git',args,repo);
 git('config','user.name','Release Test');git('config','user.email','release@test.invalid');
 git('config',`url.file://${origin}.insteadOf`,'https://github.com/test/release.git');git('remote','add','origin','https://github.com/test/release.git');
 fs.writeFileSync(path.join(repo,'CHANGELOG.md'),'# Changelog\n\n## [unreleased] — feat: alpha (#101)\n\n- alpha\n\n## [unreleased] — fix: beta (#102)\n\n- beta\n\n## [v0] — old\n- old\n');
 fs.mkdirSync(path.join(repo,'.github/workflows'),{recursive:true}); const workflow=fs.readFileSync(path.join(root,'.github/workflows/release.yml'),'utf8');fs.writeFileSync(path.join(repo,'.github/workflows/release.yml'),workflow);
 const shell=workflow.split('        run: |\n')[1].split('\n').map(l=>l.startsWith('          ')?l.slice(10):l).join('\n');fs.writeFileSync(path.join(d,'publish.sh'),shell);
 fs.writeFileSync(path.join(repo,'keep.txt'),'keep\n');git('add','.');git('commit','-qm','seed');git('tag','v0');git('push','-q','origin','main','--tags');
 const state=path.join(d,'transport.json');fs.writeFileSync(state,JSON.stringify({mode,calls:[],prs:[],releases:{}}));
 const stub=String.raw`#!/usr/bin/env node
const fs=require('fs'),cp=require('child_process'),path=require('path');
const f=process.env.TRANSPORT, s=JSON.parse(fs.readFileSync(f)), a=process.argv.slice(2), repo=process.env.FIXTURE_REPO, origin=process.env.FIXTURE_ORIGIN;
s.calls.push(a);fs.writeFileSync(f,JSON.stringify(s));
const out=x=>process.stdout.write(typeof x==='string'?x+'\n':JSON.stringify(x)+'\n');
const die=m=>{process.stderr.write('deny-default gh stub: '+m+'\n');process.exit(91)};
const eq=x=>JSON.stringify(a)===JSON.stringify(x);
const get=x=>a[a.indexOf(x)+1];
const fields='number,url,title,baseRefName,headRefName,headRefOid,state,mergeCommit,headRepository,isCrossRepository';
const releasePr=()=>s.prs.find(p=>p.headRefName==='chore/release-v1');
const git=(...x)=>{const r=cp.spawnSync('git',x,{cwd:repo,encoding:'utf8'});if(r.status)die(r.stderr);return r.stdout.trim()};
function save(){fs.writeFileSync(f,JSON.stringify(s))}
if(eq(['--version']))out('gh fixture');
else if(eq(['auth','status'])){if(s.mode==='gh')process.exit(1)}
else if(eq(['repo','view','--json','nameWithOwner']))out({nameWithOwner:s.mode==='foreign-repo'?'foreign/repo':'test/release'});
else if(a[0]==='pr'&&a[1]==='view') {
 const p=s.prs.find(p=>String(p.number)===a[2]);if(!p)die('unknown PR');
 const expected=p.headRefName==='chore/release-v1'?['pr','view','1','--repo','test/release','--json',fields]:['pr','view',String(p.number),'--json','body,files'];
 if(!eq(expected))die('bad view argv');
 if(s.mode==='head'&&p.headRefName==='chore/release-v1'){const r=cp.spawnSync('git',['update-ref','refs/heads/'+p.headRefName,git('rev-parse','HEAD')],{cwd:origin,encoding:'utf8'});if(r.status)die(r.stderr);s.movedHead=true;save();}
 out(p);
}
else if(a[0]==='pr'&&a[1]==='list') {
 const dependent=eq(['pr','list','--repo','test/release','--base','chore/release-v1','--state','open','--json','number']);
 const release=eq(['pr','list','--repo','test/release','--head','chore/release-v1','--state','all','--json',fields]);
 if(!dependent&&!release)die('bad list argv');
 if(dependent){if(s.mode==='cleanup-head'){const p=releasePr();const r=cp.spawnSync('git',['update-ref','refs/heads/'+p.headRefName,p.mergeCommit.oid],{cwd:origin,encoding:'utf8'});if(r.status)die(r.stderr);}out(s.mode==='dependent'?[{number:99}]:[]);}
 else if(s.mode==='ambiguous')out([{number:7},{number:8}]);else out(s.prs.filter(p=>p.headRefName==='chore/release-v1'));
}
else if(a[0]==='pr'&&a[1]==='create') {
 if(s.mode==='hold-pr'&&!fs.existsSync(path.join(path.dirname(f),'pr-held'))){fs.writeFileSync(path.join(path.dirname(f),'pr-held'),'held');while(!fs.existsSync(path.join(path.dirname(f),'pr-go')))Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,10);}
 const body=get('--body-file');
 const expected=['pr','create','--repo','test/release','--base','main','--head','chore/release-v1','--title','chore(release): v1','--body-file',body];
 const journal=path.join(fs.realpathSync(path.resolve(repo,git('rev-parse','--git-common-dir'))),'aai/releases');
 if(!eq(expected)||!body||path.dirname(body)!==journal||!/^body-[a-f0-9]{12}\.md$/.test(path.basename(body)))die('bad create argv');
 const branch=get('--head'), sha=git('ls-remote','origin','refs/heads/'+branch).split(/\s/)[0];
 if(fs.readFileSync(body,'utf8')!==('Automated release cut for v1.\n\nBound release: test/release '+branch+' '+sha+'.\n\nno-notes: release rollup contains the previously recorded entries.\n'))die('bad bound PR body'); if(!/^[a-f0-9]{40}$/.test(sha))die('unpushed head');
 const p={number:1,url:'https://github.com/test/release/pull/1',title:get('--title'),baseRefName:'main',headRefName:branch,headRefOid:sha,state:'OPEN',mergeCommit:null,headRepository:{nameWithOwner:'test/release'},isCrossRepository:false};s.prs.push(p);save();out(p.url);
} else if(a[0]==='pr'&&a[1]==='checks') {
 const required=eq(['pr','checks','1','--repo','test/release','--required','--json','name,bucket,link']);
 const watched=eq(['pr','checks','1','--json','name,bucket,link']);if(!required&&!watched)die('bad checks argv');
 if(s.mode==='checks-error'){out([{name:'required',bucket:'pass',link:''}]);process.exit(3);}
 if(s.mode==='pending-empty'){out([]);process.exit(8);}
 if(s.mode==='pending-malformed'){out('not JSON');process.exit(8);}
 if(s.mode==='base-move'&&!s.baseMoved){
  const d=path.join(path.dirname(f),'ci-writer');git('clone','-q',origin,d);
  const g=(...x)=>{const r=cp.spawnSync('git',x,{cwd:d,encoding:'utf8'});if(r.status)die(r.stderr);return r.stdout.trim()};
  g('checkout','-q','main');g('config','user.name','Writer');g('config','user.email','writer@test.invalid');
  fs.mkdirSync(path.join(d,'.aai/scripts'),{recursive:true});fs.writeFileSync(path.join(d,'.aai/scripts/ci-unnoted.mjs'),'new behavior\n');g('add','.');g('commit','-qm','feat: during CI (#211)');g('push','-q','origin','main');s.baseMoved=true;save();
 }
 let bucket=s.mode==='ci'?'fail':'pass';
 if(s.mode==='pending'||s.mode==='pending-forever'){
  s.checkPolls=(s.checkPolls||0)+1;bucket=s.mode==='pending-forever'||s.checkPolls<=2?'pending':'pass';save();
 }
 out(s.mode==='missing-checks'?[]:[{name:'required',bucket,link:''}]);
 if(bucket==='pending')process.exit(8);if(bucket==='fail')process.exit(1);
} else if(a[0]==='pr'&&a[1]==='merge') {
 const p=releasePr();const expected=['pr','merge','1','--repo','test/release','--squash','--match-head-commit',p.headRefOid];if(!eq(expected))die('unbound merge '+JSON.stringify(a));
 const mergeDir=path.join(path.dirname(f),'runner');git('clone','-q',origin,mergeDir);const g=(...x)=>{const r=cp.spawnSync('git',x,{cwd:mergeDir,encoding:'utf8'});if(r.status)die(r.stderr);return r.stdout.trim()};
 g('checkout','-q','main');g('config','user.name','CI');g('config','user.email','ci@test.invalid');g('merge','--squash','origin/'+p.headRefName);g('commit','-qm',p.title);p.state='MERGED';p.mergeCommit={oid:g('rev-parse','HEAD')};g('push','-q','origin','main');s.runner=mergeDir;save();
} else if(a[0]==='run'&&a[1]==='list') {
 const p=releasePr();if(!p||p.state!=='MERGED'||!eq(['run','list','--repo','test/release','--workflow','release.yml','--commit',p.mergeCommit.oid,'--json','databaseId,headSha,status,conclusion']))die('bad workflow argv/SHA');
 if(s.mode==='workflow')out([{databaseId:8,headSha:p.mergeCommit.oid,status:'completed',conclusion:'failure'}]);
 else {if(!s.published){s.published=true;save(); const shell=s.mode==='workflow-spawn-error'?path.join(path.dirname(f),'missing-workflow-shell'):'bash';const r=cp.spawnSync(shell,[path.join(path.dirname(f),'publish.sh')],{cwd:s.runner,env:{...process.env,REF_TYPE:'branch',REF_NAME:'main'},encoding:'utf8'});if(r.status!==0)die('workflow shell '+(r.error?.code||('exit '+r.status))+' '+r.stderr+' '+r.stdout);Object.assign(s,JSON.parse(fs.readFileSync(f)));if(s.mode==='tag'){const bad=cp.spawnSync('git',['update-ref','refs/tags/v1',git('rev-parse','HEAD')],{cwd:origin,encoding:'utf8'});if(bad.status)die(bad.stderr);}}out([{databaseId:8,headSha:p.mergeCommit.oid,status:'completed',conclusion:'success'}]);}
} else if(a[0]==='release'&&a[1]==='view') {
 const client=eq(['release','view','v1','--repo','test/release','--json','body,url']);const workflow=eq(['release','view','v1']);if(!client&&!workflow)die('bad release view argv');
 const release=s.releases.v1;if(!release)process.exit(1);out(client?release:'release exists');
}
else if(a[0]==='release'&&a[1]==='create') {const notes=get('--notes-file');if(s.mode==='create-error'){process.stderr.write('workflow publication failure control\n');process.exit(7);}if(!eq(['release','create','v1','--title','v1','--notes-file',notes])||!notes||!path.isAbsolute(notes)||!fs.existsSync(notes))die('bad release create argv');if(fs.realpathSync(path.dirname(notes))!==fs.realpathSync(path.dirname(f))||fs.readFileSync(notes,'utf8').trim()!=='## [v1] — feat: alpha (#101)\n\n- alpha\n\n## [v1] — fix: beta (#102)\n\n- beta')die('bad notes file binding/content'); s.releases[a[2]]={body:fs.readFileSync(get('--notes-file'),'utf8'),url:'https://github.com/test/release/releases/tag/'+a[2]};if(s.mode==='notes')s.releases[a[2]].body='wrong';save();out(s.releases[a[2]].url)}
else die(JSON.stringify(a));
`;
 fs.writeFileSync(path.join(bin,'gh'),stub,{mode:0o755});
 // BSD/macOS mktemp ignores TMPDIR when called bare; the CI runner's GNU mktemp honors it.
 const realMktemp=run('which',['mktemp'],repo);fs.writeFileSync(path.join(bin,'mktemp'),`#!/bin/sh\nif [ "$#" -eq 0 ]; then exec "${realMktemp}" "\${TMPDIR:-/tmp}/tmp.XXXXXXXXXX"; fi\nexec "${realMktemp}" "$@"\n`,{mode:0o755});
 const realGit=run('which',['git'],repo);fs.writeFileSync(path.join(bin,'git'),`#!/bin/sh
if [ -n "$FIXTURE_GIT_LOG" ]; then
  for arg in "$@"; do printf '%s\\n' "$arg" >> "$FIXTURE_GIT_LOG"; done
  printf '%s\\n' '--END--' >> "$FIXTURE_GIT_LOG"
fi
if [ "$FIXTURE_MODE" = "lease-race" ] && [ "$1" = "push" ] && [ "$4" = ":refs/heads/chore/release-v1" ]; then
  "${realGit}" -C "$FIXTURE_ORIGIN" update-ref refs/heads/chore/release-v1 refs/heads/main
fi
if [ "$FIXTURE_MODE" = "late-base" ] && [ "$*" = "ls-remote origin refs/heads/main" ]; then
  count=0
  if [ -f "$FIXTURE_BASE_READS" ]; then read count < "$FIXTURE_BASE_READS"; fi
  count=$((count + 1))
  printf '%s\\n' "$count" > "$FIXTURE_BASE_READS"
  "${realGit}" "$@" || exit $?
  if [ "$count" = "10" ]; then "${realGit}" -C "$FIXTURE_LATE_WRITER" push -q origin main || exit $?; fi
  exit 0
fi
if [ "$*" = "remote get-url origin" ]; then printf '%s\\n' https://github.com/test/release.git; else exec "${realGit}" "$@"; fi
`,{mode:0o755});
 let lateWriter='';
 if(mode==='late-base'){
  lateWriter=path.join(d,'last-window-writer');git('clone','-q',origin,lateWriter);
  run('git',['checkout','-q','main'],lateWriter);run('git',['config','user.name','Late Writer'],lateWriter);run('git',['config','user.email','late@test.invalid'],lateWriter);
  fs.mkdirSync(path.join(lateWriter,'.aai/scripts'),{recursive:true});fs.writeFileSync(path.join(lateWriter,'.aai/scripts/last-window.mjs'),'new late behavior\n');run('git',['add','.'],lateWriter);run('git',['commit','-qm','feat: final observation window (#212)'],lateWriter);
 }
 const env={FIXTURE_LATE_WRITER:lateWriter,FIXTURE_BASE_READS:path.join(d,'base-reads'),TMPDIR:d,TEMP:d,TMP:d,PATH:bin+path.delimiter+process.env.PATH,FIXTURE_MODE:mode,FIXTURE_GIT_LOG:path.join(d,'git-argv.log'),TRANSPORT:state,FIXTURE_REPO:repo,FIXTURE_ORIGIN:origin,AAI_RELEASE_POLL_SECONDS:'0.01',AAI_RELEASE_WAIT_SECONDS:'2'};
 const invoke=(extra=[],engine='sh',caller=repo)=>spawnSync(engine==='ps'?'pwsh':'bash',engine==='ps'?['-NoProfile','-File',ps,'--version','v1','--confirm',...extra]:[sh,'--version','v1','--confirm',...extra],{cwd:caller,env:{...process.env,...env},encoding:'utf8'});
 return {d,repo,origin,state,env,git,invoke,transport:()=>JSON.parse(fs.readFileSync(state))};
}
function historical(f,number,file,body='') {
 fs.mkdirSync(path.dirname(path.join(f.repo,file)),{recursive:true});if(file==='CHANGELOG.md')fs.appendFileSync(path.join(f.repo,file),'\nnotes-only amendment\n');else fs.writeFileSync(path.join(f.repo,file),'change '+number+'\n');f.git('add',file);f.git('commit','-qm',`feat: shipped ${number} (#${number})`);f.git('push','-q','origin','main');const t=f.transport();t.prs.push({number,body,files:[{path:file}],headRefName:'historical-'+number});fs.writeFileSync(f.state,JSON.stringify(t));
}
function remoteCommit(f,number,file,body='') {
 const clone=path.join(f.d,'writer-'+number);f.git('clone','-q',f.origin,clone);
 run('git',['checkout','-q','main'],clone);run('git',['config','user.name','Writer'],clone);run('git',['config','user.email','writer@test.invalid'],clone);
 fs.mkdirSync(path.dirname(path.join(clone,file)),{recursive:true});fs.writeFileSync(path.join(clone,file),'remote '+number+'\n');
 run('git',['add',file],clone);run('git',['commit','-qm',`feat: remote ${number} (#${number})`],clone);run('git',['push','-q','origin','main'],clone);
 const t=f.transport();t.prs.push({number,body,files:[{path:file}],headRefName:'historical-'+number});fs.writeFileSync(f.state,JSON.stringify(t));
 return run('git',['rev-parse','HEAD'],clone);
}
const selected=process.env.RELEASE_FINISH_CASE||'all';
function check(id,fn){if(selected!=='all'&&selected!==id)return;fn();console.log('PASS: '+id+' release-command-finish');}
check('TEST-004',()=>{const f=fixture();historical(f,201,'CHANGELOG.md');historical(f,202,'docs/ai/AAI_VERSION.md');historical(f,203,'.aai/scripts/exempt.mjs','no-notes: internal refactor');historical(f,101,'.aai/scripts/noted.mjs');const r=spawnSync('bash',[sh,'--version','v1','--dry-run'],{cwd:f.repo,env:{...process.env,...f.env},encoding:'utf8'});assert.equal(r.status,0,r.stderr);assert.ok(!r.stdout.includes('NAMED'),r.stdout);});
check('TEST-005',()=>{const f=fixture();historical(f,205,'.aai/scripts/missing.mjs');const refs=f.git('show-ref'),bytes=fs.readFileSync(path.join(f.repo,'CHANGELOG.md'));for(const args of [[],['--dry-run'],['--dry-run','--confirm']]){const r=spawnSync('bash',[sh,'--version','v1',...args],{cwd:f.repo,env:{...process.env,...f.env},encoding:'utf8'});assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/NAMED/);assert.equal(f.git('show-ref'),refs);assert.deepEqual(fs.readFileSync(path.join(f.repo,'CHANGELOG.md')),bytes);assert.equal(f.transport().calls.filter(a=>['create','merge'].includes(a[1])).length,0);}const r=f.invoke();assert.notEqual(r.status,0);assert.match(r.stderr,/REFUSED: missing-notes/);assert.equal(f.git('show-ref'),refs);assert.equal(f.transport().calls.filter(a=>['create','merge'].includes(a[1])).length,0);
 const stale=fixture();historical(stale,206,'.aai/scripts/forgotten.mjs');stale.git('checkout','--detach','-q','v0');const before=stale.git('show-ref');const refused=stale.invoke();assert.equal(refused.status,20,refused.stderr);assert.match(refused.stderr,/missing-notes/);assert.equal(stale.git('show-ref'),before);assert.equal(stale.transport().calls.filter(a=>['create','merge'].includes(a[1])).length,0);assert.equal(Object.keys(stale.transport().releases).length,0);
 const blank=fixture();historical(blank,207,'.aai/scripts/forgotten.mjs','no-notes:\n\nUnrelated paragraph');const blocked=blank.invoke();assert.equal(blocked.status,20,blocked.stderr);assert.match(blocked.stderr,/missing-notes/);assert.equal(blank.transport().calls.filter(a=>['create','merge'].includes(a[1])).length,0);
});
check('TEST-016',()=>{
 for(const change of ['added','deleted','mode']) {
  const f=fixture();fs.writeFileSync(path.join(f.repo,'run-service'),'#!/bin/sh\necho behavior\n',{mode:0o755});
  if(change!=='added'){f.git('add','run-service');f.git('commit','-qm','seed executable');f.git('tag','-f','v0');}
  if(change==='deleted')f.git('rm','run-service');else if(change==='mode')fs.chmodSync(path.join(f.repo,'run-service'),0o644);
  f.git('add','-A');f.git('commit','-qm',`feat: executable ${change} (#208)`);f.git('push','-q','origin','main');
  const t=f.transport();t.prs.push({number:208,body:'',files:[{path:'run-service'}],headRefName:'historical-208'});fs.writeFileSync(f.state,JSON.stringify(t));
  const refs=f.git('show-ref'),r=f.invoke();assert.equal(r.status,20,change+r.stdout+r.stderr);assert.match(r.stderr,/missing-notes/);assert.equal(f.git('show-ref'),refs);assert.equal(f.transport().calls.filter(a=>['create','merge'].includes(a[1])).length,0);
 }
 const stale=fixture(),before=stale.git('rev-parse','origin/main'),actual=remoteCommit(stale,209,'.aai/scripts/unnoted.mjs');assert.notEqual(actual,before);
 const fetchHead=path.join(stale.repo,'.git/FETCH_HEAD');fs.writeFileSync(fetchHead,'owner-fetch-head\n');
 const refs=stale.git('show-ref');const preview=spawnSync('bash',[sh,'--version','v1','--dry-run'],{cwd:stale.repo,env:{...process.env,...stale.env},encoding:'utf8'});
 assert.equal(preview.status,20,preview.stdout+preview.stderr);assert.match(preview.stderr,/base-history/);assert.equal(stale.git('show-ref'),refs);assert.equal(fs.readFileSync(fetchHead,'utf8'),'owner-fetch-head\n');assert.ok(!fs.existsSync(path.join(stale.repo,'.git/aai/releases')));
 const r=stale.invoke();assert.equal(fs.readFileSync(fetchHead,'utf8'),'owner-fetch-head\n');assert.equal(r.status,20,r.stdout+r.stderr);assert.match(r.stderr,/missing-notes.*#209/);assert.equal(stale.git('show-ref'),refs);assert.equal(stale.transport().calls.filter(a=>['create','merge'].includes(a[1])).length,0);
 // A benign stale tracking ref succeeds using the real remote base, proving
 // this is authoritative audit rather than blanket stale-ref refusal.
 const benign=fixture(),remote=remoteCommit(benign,210,'docs/change.md');const ok=benign.invoke();assert.equal(ok.status,0,ok.stdout+ok.stderr);
 const journal=JSON.parse(fs.readFileSync(path.join(benign.repo,'.git/aai/releases',fs.readdirSync(path.join(benign.repo,'.git/aai/releases')).find(n=>n.endsWith('.json')))));assert.equal(journal.baseHead,remote);
 // Move the real bare-origin base during the checks transport, not merge.
 const moving=fixture('base-move');const blocked=moving.invoke();assert.equal(blocked.status,20,blocked.stdout+blocked.stderr);assert.match(blocked.stderr,/base-moved/);assert.equal(moving.transport().calls.filter(a=>a[0]==='pr'&&a[1]==='merge').length,0);assert.match(blocked.stderr,/Resume: .*--version v1 --confirm/);assert.equal(moving.invoke().status,20);
});
check('TEST-017',()=>{
 const f=fixture('late-base'),r=f.invoke();assert.equal(r.status,0,r.stdout+r.stderr);
 const journal=JSON.parse(fs.readFileSync(path.join(f.repo,'.git/aai/releases',fs.readdirSync(path.join(f.repo,'.git/aai/releases')).find(n=>n.endsWith('.json')))));
 const merge=f.transport().prs[0].mergeCommit.oid;assert.notEqual(f.git('rev-parse',merge+'^'),journal.baseHead);assert.equal(f.git('show',merge+':.aai/scripts/last-window.mjs'),'new late behavior');assert.ok(f.transport().releases.v1);assert.equal(fs.readFileSync(path.join(f.d,'base-reads'),'utf8').trim(),'10');
 console.log('KNOWN EXTERNAL LIMIT: real remote base push after final observation entered published merge; PR head pin is not an atomic base pin');
});
check('TEST-018',()=>{
 const noConfirm=fixture();const refs=noConfirm.git('show-ref');const denied=spawnSync(process.execPath,[path.join(root,'.aai/scripts/release-finish.mjs'),'--root',noConfirm.repo,'--version','v1'],{cwd:noConfirm.repo,env:{...process.env,...noConfirm.env},encoding:'utf8'});assert.equal(denied.status,20,denied.stdout+denied.stderr);assert.match(denied.stderr,/confirmation/);assert.equal(noConfirm.git('show-ref'),refs);assert.equal(noConfirm.transport().calls.filter(a=>['create','merge'].includes(a[1])).length,0);
 const collision=fixture();const dir=path.join(collision.repo,'.git/aai/releases');fs.mkdirSync(dir,{recursive:true});const name=crypto.createHash('sha256').update('v1').digest('hex')+'.json';const owner=path.join(collision.d,'owner.txt');fs.writeFileSync(owner,'owner bytes\n');fs.symlinkSync(owner,path.join(dir,name+'.tmp'));const completed=collision.invoke();assert.equal(completed.status,0,completed.stderr);assert.equal(fs.readFileSync(owner,'utf8'),'owner bytes\n');assert.ok(fs.lstatSync(path.join(dir,name+'.tmp')).isSymbolicLink());if(process.platform!=='win32')assert.equal(fs.statSync(path.join(dir,name)).mode&0o777,0o600);
 const corrupt=fixture();const corruptDir=path.join(corrupt.repo,'.git/aai/releases');fs.mkdirSync(corruptDir,{recursive:true});fs.writeFileSync(path.join(corruptDir,name),'null');const refused=corrupt.invoke();assert.equal(refused.status,20,refused.stderr);assert.match(refused.stderr,/journal-corrupt/);assert.equal(fs.readFileSync(path.join(corruptDir,name),'utf8'),'null');assert.equal(corrupt.transport().calls.filter(a=>['create','merge'].includes(a[1])).length,0);
});
check('TEST-019',()=>{
 for(const origin of ['git@github.com:test/release.git','ssh://git@github.com/test/release.git']){
  const f=fixture();f.git('config',`url.file://${f.origin}.insteadOf`,origin);f.git('remote','set-url','origin',origin);const r=f.invoke();assert.equal(r.status,0,r.stdout+r.stderr);assert.equal(f.transport().calls.filter(a=>a[0]==='pr'&&a[1]==='merge').length,1);
 }
 for(const origin of ['https://evilgithub.com/test/release.git','https://example.invalid/github.com/test/release.git','git@evilgithub.com:test/release.git']){
  const f=fixture();f.git('config',`url.file://${f.origin}.insteadOf`,origin);f.git('remote','set-url','origin',origin);const r=f.invoke();assert.equal(r.status,20,r.stdout+r.stderr);assert.match(r.stderr,/identity/);assert.equal(f.transport().calls.filter(a=>['create','merge'].includes(a[1])).length,0);
 }
});
check('TEST-006',()=>{const f=fixture(),r=f.invoke();assert.equal(r.status,0,r.stdout+r.stderr);const t=f.transport();assert.equal(t.prs.length,1);assert.equal(t.calls.filter(a=>a[0]==='pr'&&a[1]==='merge').length,1);assert.ok(t.calls.some(a=>a[0]==='pr'&&a[1]==='checks'&&a.includes('--required')));assert.match(r.stdout,/- Merge SHA:/);const waiting=fixture('pending'),wait=waiting.invoke();assert.equal(wait.status,0,wait.stderr);assert.ok(waiting.transport().checkPolls>=3);assert.match(wait.stdout,/waiting for required CI/);});
check('TEST-007',()=>{const f=fixture(),r=f.invoke();assert.equal(r.status,0,r.stdout+r.stderr);const t=f.transport(),tag=f.git('ls-remote','origin','refs/tags/v1^{}').split(/\s/)[0];assert.equal(tag,t.prs[0].mergeCommit.oid);assert.equal(t.releases.v1.body.trim(),'## [v1] — feat: alpha (#101)\n\n- alpha\n\n## [v1] — fix: beta (#102)\n\n- beta');const bad=fixture('notes'),b=bad.invoke();assert.notEqual(b.status,0);assert.match(b.stderr,/REFUSED: notes-mismatch/);assert.ok(bad.git('ls-remote','origin','refs/heads/chore/release-v1'));});
check('TEST-008',()=>{const f=fixture(),r=f.invoke();assert.equal(r.status,0,r.stderr);assert.equal(f.git('ls-remote','origin','refs/heads/chore/release-v1'),'');assert.equal(f.git('branch','--list','chore/release-v1'),'');assert.equal(f.git('rev-parse','HEAD'),f.transport().prs[0].mergeCommit.oid);const transcript=fs.readFileSync(path.join(f.d,'git-argv.log'),'utf8').split('--END--\n').map(block=>block.trimEnd().split('\n'));assert.ok(transcript.some(args=>JSON.stringify(args)===JSON.stringify(['push','--force-with-lease=refs/heads/chore/release-v1:'+f.transport().prs[0].headRefOid,'origin',':refs/heads/chore/release-v1'])),'expected-head lease deletion argv absent');const d=fixture('dependent'),b=d.invoke();assert.notEqual(b.status,0);assert.match(b.stderr,/REFUSED: dependent-pr/);assert.ok(d.git('ls-remote','origin','refs/heads/chore/release-v1'));});
check('TEST-009',()=>{const f=fixture();f.git('checkout','--detach','-q');fs.writeFileSync(path.join(f.repo,'keep.txt'),'owner dirty\n');const head=f.git('rev-parse','HEAD'),bytes=fs.readFileSync(path.join(f.repo,'keep.txt'));const r=f.invoke();assert.equal(r.status,0,r.stderr);assert.equal(f.git('rev-parse','HEAD'),head);assert.deepEqual(fs.readFileSync(path.join(f.repo,'keep.txt')),bytes);assert.match(r.stdout,/SKIPPED.*base checkout/);const d=fixture();fs.appendFileSync(path.join(d.repo,'CHANGELOG.md'),'dirty\n');const b=d.invoke();assert.notEqual(b.status,0);assert.match(b.stderr,/REFUSED: base-dirty-overlap/);
 const work=fixture(),feature=path.join(work.d,'feature');work.git('worktree','add','-q','-b','feature',feature);fs.writeFileSync(path.join(feature,'keep.txt'),'feature owner dirty\n');fs.writeFileSync(path.join(feature,'untracked.txt'),'owner untracked\n');const featureHead=run('git',['rev-parse','HEAD'],feature),featureStatus=run('git',['status','--porcelain'],feature);const cut=work.invoke([],'sh',feature);assert.equal(cut.status,0,cut.stderr);assert.equal(work.git('rev-parse','HEAD'),work.transport().prs.find(p=>p.headRefName==='chore/release-v1').mergeCommit.oid);assert.equal(run('git',['rev-parse','HEAD'],feature),featureHead);assert.equal(run('git',['status','--porcelain'],feature),featureStatus);assert.equal(fs.readFileSync(path.join(feature,'keep.txt'),'utf8'),'feature owner dirty\n');assert.equal(fs.readFileSync(path.join(feature,'untracked.txt'),'utf8'),'owner untracked\n');
 const hidden=fixture();hidden.git('update-index','--assume-unchanged','CHANGELOG.md');fs.appendFileSync(path.join(hidden.repo,'CHANGELOG.md'),'hidden owner bytes\n');const hiddenBytes=fs.readFileSync(path.join(hidden.repo,'CHANGELOG.md'));const hiddenCut=hidden.invoke();assert.equal(hiddenCut.status,20,hiddenCut.stderr);assert.match(hiddenCut.stderr,/base-hidden-edits/);assert.deepEqual(fs.readFileSync(path.join(hidden.repo,'CHANGELOG.md')),hiddenBytes);
 const divergent=fixture();fs.writeFileSync(path.join(divergent.repo,'local.txt'),'local only\n');divergent.git('add','local.txt');divergent.git('commit','-qm','unpublished base commit');const ownHead=divergent.git('rev-parse','HEAD'),localBytes=fs.readFileSync(path.join(divergent.repo,'local.txt'));const diverged=divergent.invoke();assert.notEqual(diverged.status,0);assert.match(diverged.stderr,/base-diverged/);assert.equal(divergent.git('rev-parse','HEAD'),ownHead);assert.deepEqual(fs.readFileSync(path.join(divergent.repo,'local.txt')),localBytes);
});
check('TEST-010',()=>{for(const mode of ['ci','missing-checks','checks-error','pending-empty','pending-malformed','pending-forever','head','workflow','notes','tag','cleanup-head','lease-race','dependent','gh']){const f=fixture(mode),r=f.invoke();assert.notEqual(r.status,0,mode);assert.equal((r.stderr.match(/REFUSED:/g)||[]).length,1,r.stderr);assert.match(r.stderr,/Resume: .*--version v1 --confirm/);const t=f.transport();if(['ci','missing-checks','checks-error','pending-empty','pending-malformed','pending-forever','head','gh'].includes(mode))assert.equal(t.calls.filter(a=>a[0]==='pr'&&a[1]==='merge').length,0);if(mode==='head'){assert.ok(t.prs[0],r.stdout+r.stderr);assert.equal(t.prs[0].state,'OPEN');assert.ok(t.movedHead);assert.match(r.stderr,/head-moved/);assert.notEqual(f.git('ls-remote','origin','refs/heads/chore/release-v1').split(/\s/)[0],t.prs[0].headRefOid);}if(['workflow','notes','tag','cleanup-head','lease-race','dependent'].includes(mode))assert.ok(f.git('ls-remote','origin','refs/heads/chore/release-v1'));if(mode==='dependent'){assert.match(r.stderr,/dependent-pr/);assert.ok(f.git('branch','--list','chore/release-v1'));}if(mode==='tag')assert.match(r.stderr,/tag-mismatch/);if(mode==='cleanup-head')assert.match(r.stderr,/cleanup-head-moved/);if(mode==='lease-race'){assert.match(r.stderr,/stale info/);assert.notEqual(f.git('ls-remote','origin','refs/heads/chore/release-v1').split(/\s/)[0],t.prs[0].headRefOid);assert.ok(f.git('branch','--list','chore/release-v1'));}}});
check('TEST-011',()=>{for(const step of ['worktree','payload','prepared','pushed','pr','merged','workflow','verified','remote-deleted','local-deleted','synced']){const f=fixture();const first=spawnSync('bash',[sh,'--version','v1','--confirm'],{cwd:f.repo,env:{...process.env,...f.env,AAI_RELEASE_TEST_STOP_AFTER:step},encoding:'utf8'});assert.notEqual(first.status,0,step);const next=f.invoke();assert.equal(next.status,0,step+next.stdout+next.stderr);assert.equal(f.transport().prs.length,1,step);assert.equal(f.transport().calls.filter(a=>a[0]==='pr'&&a[1]==='merge').length,1,step);assert.equal(Object.keys(f.transport().releases).length,1,step);}});
check('TEST-012',()=>{const f=fixture();let r=spawnSync('bash',[sh,'--version','v1','--dry-run','--confirm'],{cwd:f.repo,env:{...process.env,...f.env},encoding:'utf8'});assert.equal(r.status,0,r.stderr);assert.equal(f.git('branch','--list','chore/release-v1'),'');const gitDir=f.git('rev-parse','--git-common-dir');assert.ok(!fs.existsSync(path.resolve(f.repo,gitDir,'aai/releases')));r=f.invoke();assert.equal(r.status,0,r.stderr);let t=f.transport();t.prs[0].headRefOid='f'.repeat(40);fs.writeFileSync(f.state,JSON.stringify(t));r=f.invoke();assert.notEqual(r.status,0);assert.match(r.stderr,/REFUSED: identity/);
 const foreign=fixture('foreign-repo');assert.notEqual(foreign.invoke().status,0);assert.equal(foreign.git('branch','--list','chore/release-v1'),'');
 const ambiguous=fixture('ambiguous');assert.notEqual(ambiguous.invoke().status,0);assert.equal(ambiguous.git('branch','--list','chore/release-v1'),'');
 const manual=fixture();manual.git('rm','.github/workflows/release.yml');manual.git('commit','-qm','manual tagging');manual.git('push','-q','origin','main');const m=manual.invoke();assert.equal(m.status,0,m.stderr);assert.match(m.stdout,/SKIPPED.*manual tagging/);assert.equal(Object.keys(manual.transport().releases).length,0);
});
if(selected==='all'||selected==='TEST-020'){
 const f=fixture('hold-pr');const first=spawn('bash',[sh,'--version','v1','--confirm'],{cwd:f.repo,env:{...process.env,...f.env},stdio:['ignore','pipe','pipe']});let firstOutput='';first.stdout.on('data',b=>firstOutput+=b);first.stderr.on('data',b=>firstOutput+=b);const closed=new Promise(resolve=>first.on('close',code=>resolve(code)));
 try {
  const deadline=Date.now()+10000;while(!fs.existsSync(path.join(f.d,'pr-held'))){if(Date.now()>deadline)throw Error('first confirm did not reach actual PR create barrier: '+firstOutput);await new Promise(resolve=>setTimeout(resolve,10));}
  const second=f.invoke();assert.equal(second.status,20,second.stdout+second.stderr);assert.match(second.stderr,/release-busy/);assert.match(second.stderr,/Resume: .*--version v1 --confirm/);
 }finally{fs.writeFileSync(path.join(f.d,'pr-go'),'go');const result=await closed;if(result!==0)throw Error('first confirm failed: '+firstOutput);}
 assert.equal(f.transport().prs.length,1);assert.equal(f.transport().calls.filter(a=>a[0]==='pr'&&a[1]==='merge').length,1);console.log('PASS: TEST-020 simultaneous confirm exclusive ownership release-command-finish');
}
if(selected==='all'||selected==='TEST-021'){
 const f=fixture('hold-pr');const first=spawn('bash',[sh,'--version','v1','--confirm'],{cwd:f.repo,env:{...process.env,...f.env},stdio:['ignore','pipe','pipe']});const closed=new Promise(resolve=>first.on('close',(code,signal)=>resolve({code,signal})));first.stdout.resume();first.stderr.resume();
 const deadline=Date.now()+10000;while(!fs.existsSync(path.join(f.d,'pr-held'))){if(Date.now()>deadline)throw Error('kill control failed to reach prepared/pushed PR-create stage');await new Promise(resolve=>setTimeout(resolve,10));}
 first.kill('SIGKILL');const killed=await closed;assert.equal(killed.signal,'SIGKILL');fs.writeFileSync(path.join(f.d,'pr-go'),'go');
 const ready=Date.now()+10000;while(f.transport().prs.length!==1){if(Date.now()>ready)throw Error('orphan transport did not finish its bound create');await new Promise(resolve=>setTimeout(resolve,10));}
 const dir=path.join(f.repo,'.git/aai/releases');const journalPath=path.join(dir,crypto.createHash('sha256').update('v1').digest('hex')+'.json');assert.ok(fs.existsSync(journalPath+'.claim'));const saved=JSON.parse(fs.readFileSync(journalPath));assert.equal(saved.stage,'pushed');const abandoned=JSON.parse(fs.readFileSync(journalPath+'.claim'));const reclaimPath=journalPath+'.claim.reclaim.'+abandoned.token;fs.writeFileSync(reclaimPath,JSON.stringify({pid:first.pid,host:os.hostname(),token:'e'.repeat(32),version:'v1'}));
 const resumed=f.invoke();assert.equal(resumed.status,0,resumed.stdout+resumed.stderr);assert.equal(f.transport().prs.length,1);assert.equal(f.transport().calls.filter(a=>a[0]==='pr'&&a[1]==='merge').length,1);assert.ok(!fs.existsSync(journalPath+'.claim'));assert.ok(!fs.existsSync(reclaimPath));assert.equal(fs.readdirSync(dir).filter(n=>n.includes('.reclaim.')).length,0);assert.equal(JSON.parse(fs.readFileSync(journalPath)).head,saved.head);console.log('PASS: TEST-021 actual SIGKILL owner resumes same durable journal once');
 const foreign=fixture();const foreignDir=path.join(foreign.repo,'.git/aai/releases');fs.mkdirSync(foreignDir,{recursive:true});const foreignClaim=path.join(foreignDir,path.basename(journalPath)+'.claim');const foreignBody=JSON.stringify({pid:first.pid,host:'different-host.invalid',token:'d'.repeat(32),version:'v1'});fs.writeFileSync(foreignClaim,foreignBody);const refused=foreign.invoke();assert.equal(refused.status,20,refused.stderr);assert.match(refused.stderr,/release-busy/);assert.equal(fs.readFileSync(foreignClaim,'utf8'),foreignBody);assert.equal(foreign.transport().calls.filter(a=>['create','merge'].includes(a[1])).length,0);
}
check('TEST-023',()=>{
 const f=fixture();historical(f,299,'.aai/scripts/omission.mjs');f.git('tag','-d','v0');
 const before=f.git('show-ref'),head=f.git('rev-parse','HEAD'),index=fs.readFileSync(path.join(f.repo,'.git/index'));
 fs.writeFileSync(path.join(f.repo,'.git/FETCH_HEAD'),'caller fetch sentinel\n');
 const snapshot=()=>{const entries=[];function walk(dir){for(const name of fs.readdirSync(dir).sort()){const file=path.join(dir,name),st=fs.lstatSync(file);if(st.isDirectory())walk(file);else entries.push([path.relative(f.repo,file),st.mode,st.isSymbolicLink()?fs.readlinkSync(file):crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')]);}}walk(f.repo);return entries;};const beforeFiles=snapshot();
 const notes=path.join(f.d,'audit-notes');fs.writeFileSync(notes,'unrelated notes');
 const preview=spawnSync('node',[path.join(root,'.aai/scripts/release-finish.mjs'),'--root',f.repo,'--audit',notes,'--online'],{cwd:f.repo,env:{...process.env,...f.env},encoding:'utf8'});
 assert.equal(preview.status,0,preview.stderr);assert.match(preview.stdout,/#299/);
 assert.equal(f.git('show-ref'),before);assert.equal(f.git('rev-parse','HEAD'),head);assert.deepEqual(fs.readFileSync(path.join(f.repo,'.git/index')),index);assert.deepEqual(snapshot(),beforeFiles);
 const r=f.invoke();assert.equal(r.status,20,r.stdout+r.stderr);assert.match(r.stderr,/missing-notes.*#299/);assert.equal(f.transport().prs.filter(p=>p.headRefName==='chore/release-v1').length,0);
 const first=fixture();first.git('tag','-d','v0');first.git('push','-q','origin',':refs/tags/v0');historical(first,298,'.aai/scripts/first-omission.mjs');const denied=first.invoke();assert.equal(denied.status,20,denied.stdout+denied.stderr);assert.match(denied.stderr,/missing-notes.*#298/);
 const valid=fixture();valid.git('tag','-d','v0');valid.git('push','-q','origin',':refs/tags/v0');const ok=valid.invoke();assert.equal(ok.status,0,ok.stderr);
});
check('TEST-024',()=>{
 const f=fixture();f.git('branch','feature');const base=f.git('rev-parse','main'),feature=f.git('rev-parse','feature');
 const file=path.join(f.d,'bin/git'),real=run('which',['git'],f.repo);let wrapper=fs.readFileSync(file,'utf8');
 wrapper=wrapper.replace('if [ "$*" = "remote get-url origin" ]; then',`if { [ "$1" = "merge" ] && [ "$2" = "--ff-only" ]; } || [ "$1" = "read-tree" ]; then\n "${real}" checkout -q feature || exit $?\nfi\nif [ "$*" = "remote get-url origin" ]; then`);fs.writeFileSync(file,wrapper);
 const r=f.invoke();assert.equal(r.status,20,r.stdout+r.stderr);assert.doesNotMatch(r.stdout,/- Base: synced/);assert.equal(f.git('rev-parse','feature'),feature);assert.equal(f.git('rev-parse','main'),base);
 const t=f.transport();assert.equal(t.prs.find(p=>p.headRefName==='chore/release-v1').state,'MERGED');assert.ok(t.releases.v1);
 wrapper=wrapper.replace(/if \{ \[ "\$1" = "merge" \][\s\S]*?fi\n(?=if \[ "\$\*" = "remote get-url origin")/,'');fs.writeFileSync(file,wrapper);
 const resume=f.invoke();assert.equal(resume.status,0,resume.stdout+resume.stderr);assert.equal(f.git('rev-parse','main'),t.prs.find(p=>p.headRefName==='chore/release-v1').mergeCommit.oid);assert.equal(f.git('rev-parse','feature'),feature);
});
check('TEST-027',()=>{
 const annotated=fixture();annotated.git('tag','-d','v0');annotated.git('tag','-a','v0','-m','previous release');annotated.git('push','-q','--force','origin','refs/tags/v0');historical(annotated,297,'.aai/scripts/annotated-omission.mjs');annotated.git('tag','-d','v0');const missing=annotated.invoke();assert.equal(missing.status,20,missing.stderr);assert.match(missing.stderr,/missing-notes.*#297/);
 const shallow=fixture();fs.writeFileSync(path.join(shallow.repo,'.git/shallow'),shallow.git('rev-parse','HEAD')+'\n');const notes=path.join(shallow.d,'notes');fs.writeFileSync(notes,'notes');const r=spawnSync(process.execPath,[path.join(root,'.aai/scripts/release-finish.mjs'),'--root',shallow.repo,'--audit',notes,'--online'],{cwd:shallow.repo,env:{...process.env,...shallow.env},encoding:'utf8'});assert.equal(r.status,20,r.stdout+r.stderr);assert.match(r.stderr,/notes-history.*Complete release history/);assert.equal(shallow.transport().calls.filter(a=>['create','merge'].includes(a[1])).length,0);
 const moving=fixture();historical(moving,296,'docs/known.md');const wrapperFile=path.join(moving.d,'bin/git'),real=run('which',['git'],moving.repo);let wrapper=fs.readFileSync(wrapperFile,'utf8');wrapper=wrapper.replace('if [ "$*" = "remote get-url origin" ]; then',`if [ "$*" = "ls-remote --tags origin" ] && [ ! -f "$TMPDIR/tags-moved" ]; then\n "${real}" "$@" || exit $?\n "${real}" -C "$FIXTURE_ORIGIN" update-ref refs/tags/v0 refs/heads/main || exit $?\n touch "$TMPDIR/tags-moved"\n exit 0\nfi\nif [ "$*" = "remote get-url origin" ]; then`);fs.writeFileSync(wrapperFile,wrapper);const moved=moving.invoke();assert.equal(moved.status,20,moved.stdout+moved.stderr);assert.match(moved.stderr,/notes-history.*tags moved/);assert.equal(moving.transport().calls.filter(a=>['create','merge'].includes(a[1])).length,0);
});
check('TEST-028',()=>{
 const f=fixture();historical(f,299,'.aai/scripts/omission.mjs');historical(f,300,'CHANGELOG.md');f.git('tag','ci-marker');f.git('push','-q','origin','refs/tags/ci-marker');
 const r=f.invoke();assert.equal(r.status,20,'non-release tag narrowed the audit boundary: '+r.stdout+r.stderr);assert.match(r.stderr,/missing-notes.*#299/);assert.equal(f.transport().calls.filter(a=>a[0]==='pr'&&a[1]==='merge').length,0);
});
check('TEST-029',()=>{
 const f=fixture();f.git('tag','fixture-blob',f.git('rev-parse','HEAD:CHANGELOG.md'));f.git('push','-q','origin','refs/tags/fixture-blob');
 const r=f.invoke();assert.equal(r.status,0,'blob tag on origin refused an otherwise clean release: '+r.stdout+r.stderr);
 const audit=fixture();audit.git('tag','fixture-blob',audit.git('rev-parse','HEAD:CHANGELOG.md'));const notes=path.join(audit.d,'n');fs.writeFileSync(notes,'notes');fs.writeFileSync(path.join(audit.repo,'.git/shallow'),audit.git('rev-parse','HEAD')+'\n');
 const a=spawnSync(process.execPath,[path.join(root,'.aai/scripts/release-finish.mjs'),'--root',audit.repo,'--audit',notes,'--online'],{cwd:audit.repo,env:{...process.env,...audit.env},encoding:'utf8'});assert.equal(a.status,20);assert.doesNotMatch(a.stderr,/--version ''/);
});
check('TEST-025',()=>{
 const f=fixture();const base=f.git('rev-parse','main');const foreign=f.git('commit-tree',f.git('rev-parse','HEAD^{tree}'),'-p',base,'-m','concurrent foreign base move');f.git('branch','feature',foreign);
 const index=fs.readFileSync(path.join(f.repo,'.git/index')),files=fs.readFileSync(path.join(f.repo,'CHANGELOG.md'));
 const file=path.join(f.d,'bin/git'),real=run('which',['git'],f.repo);let wrapper=fs.readFileSync(file,'utf8');wrapper=wrapper.replace('if [ "$*" = "remote get-url origin" ]; then',`if { [ "$1" = "merge" ] && [ "$2" = "--ff-only" ]; } || [ "$1" = "read-tree" ]; then\n "${real}" update-ref refs/heads/main refs/heads/feature || exit $?\nfi\nif [ "$*" = "remote get-url origin" ]; then`);fs.writeFileSync(file,wrapper);
 const r=f.invoke();assert.equal(r.status,20,r.stdout+r.stderr);assert.doesNotMatch(r.stdout,/- Base: synced/);assert.equal(f.git('rev-parse','main'),base);assert.equal(f.git('rev-parse','feature'),foreign);assert.deepEqual(fs.readFileSync(path.join(f.repo,'.git/index')),index);assert.deepEqual(fs.readFileSync(path.join(f.repo,'CHANGELOG.md')),files);assert.equal(f.git('branch','--show-current'),'main');
});
if(selected==='all'||selected==='TEST-026'){
 const f=fixture();f.git('branch','feature');const old=f.git('rev-parse','main'),feature=f.git('rev-parse','feature');const wrapperFile=path.join(f.d,'bin/git');let wrapper=fs.readFileSync(wrapperFile,'utf8');
 wrapper=wrapper.replace('if [ "$*" = "remote get-url origin" ]; then',`if [ "$1" = "read-tree" ]; then\n touch "$TMPDIR/sync-held"\n while [ ! -f "$TMPDIR/sync-go" ]; do sleep 0.01; done\nfi\nif [ "$*" = "remote get-url origin" ]; then`);fs.writeFileSync(wrapperFile,wrapper);
 const child=spawn(process.execPath,[path.join(root,'.aai/scripts/release-finish.mjs'),'--root',f.repo,'--version','v1','--confirm'],{cwd:f.repo,env:{...process.env,...f.env},stdio:'ignore'});const closed=new Promise(resolve=>child.on('close',(code,signal)=>resolve({code,signal})));
 const deadline=Date.now()+15000;while(!fs.existsSync(path.join(f.d,'sync-held'))){if(Date.now()>deadline)throw Error('sync kill barrier not reached');await new Promise(resolve=>setTimeout(resolve,10));}
 child.kill('SIGKILL');assert.equal((await closed).signal,'SIGKILL');
 const busy=f.invoke();assert.equal(busy.status,20,busy.stdout+busy.stderr);assert.match(busy.stderr,/base-busy/);assert.equal(f.git('rev-parse','main'),old);assert.equal(f.git('rev-parse','feature'),feature);
 fs.writeFileSync(path.join(f.d,'sync-go'),'go');
 let resumed;const end=Date.now()+15000;do{await new Promise(resolve=>setTimeout(resolve,50));resumed=f.invoke();if(resumed.status===0)break;assert.match(resumed.stderr,/base-busy/);if(Date.now()>end)throw Error('killed sync owner did not recover: '+resumed.stderr);}while(true);
 assert.equal(f.git('rev-parse','main'),f.transport().prs.find(p=>p.headRefName==='chore/release-v1').mergeCommit.oid);assert.equal(f.git('rev-parse','feature'),feature);assert.equal(f.transport().prs.filter(p=>p.headRefName==='chore/release-v1').length,1);assert.equal(f.transport().calls.filter(a=>a[0]==='pr'&&a[1]==='merge').length,1);assert.ok(!fs.existsSync(path.join(f.repo,'.git/index.lock')));console.log('PASS: TEST-026 actual sync SIGKILL live worker refusal and same-journal recovery');
}
check('TEST-022',()=>{for(const [mode,cause] of [['workflow-spawn-error',/workflow shell ENOENT/],['create-error',/workflow shell exit 7.*workflow publication failure control/s]]){
 const f=fixture(mode),failed=f.invoke();assert.equal(failed.status,20,failed.stdout+failed.stderr);assert.match(failed.stderr,cause);assert.equal(f.transport().prs.filter(p=>p.headRefName==='chore/release-v1').length,1);assert.equal(Object.keys(f.transport().releases).length,0);assert.notEqual(f.git('ls-remote','origin','refs/heads/chore/release-v1'),'','no cleanup after failed publication');
 // A failed native/workflow attempt is not a completed publication. Permit the
 // same fixture run to retry it, then assert one bound PR/merge/release only.
 const t=f.transport();t.mode='';t.published=false;fs.writeFileSync(f.state,JSON.stringify(t));const resumed=f.invoke();assert.equal(resumed.status,0,resumed.stdout+resumed.stderr);assert.equal(f.transport().prs.length,1);assert.equal(f.transport().calls.filter(a=>a[0]==='pr'&&a[1]==='merge').length,1);assert.equal(Object.keys(f.transport().releases).length,1);
}});
check('TEST-014',()=>{const ci=fs.readFileSync(path.join(root,'.github/workflows/ps1-quality.yml'),'utf8');assert.match(ci,/test_033_ps1_fallback_parity/);assert.match(ci,/completed=20 skips=0/);assert.match(ci,/command -v pwsh/);});
check('TEST-015',()=>{const product=fs.readFileSync(path.join(root,'docs/product/release-command-finish.md'),'utf8');assert.match(product,/race/i);assert.match(product,/base-moved/);assert.match(product,/fresh audited cut|deliberate repair/i);assert.match(product,/fetch/i);for(const [file,need] of [['.aai/SKILL_RELEASE.prompt.md',['--match-head-commit','release-notes-gate.mjs','resume']],['.aai/system/PROFILES.yaml',['release-notes-gate.mjs','release-finish.mjs']],['tests/skills/suite-map.yaml',['release-notes-gate.mjs','release-finish.mjs','test-aai-release-notes.sh']],['docs/USER_GUIDE.md',['release notes','no-notes:']]]){const text=fs.readFileSync(path.join(root,file),'utf8');for(const token of need)assert.ok(text.toLowerCase().includes(token.toLowerCase()),file+' missing '+token);}});
// TEST-012/013 current composition replaces the dependency ride's obsolete
// absence assertions. Execute the copied stdlib import closure and prove both
// shared exports are reached by the actual audit, using scratch-only sentinels.
check('TEST-015',()=>{
 const helper=path.join(root,'.aai/scripts/release-finish.mjs');assert.ok(fs.statSync(helper).isFile());
 const profile=fs.readFileSync(path.join(root,'.aai/system/PROFILES.yaml'),'utf8');
 const core=profile.split('\ncore:\n')[1].split('\nextended:\n')[0];
 for(const file of ['.aai/scripts/release-finish.mjs','.aai/scripts/release-notes-gate.mjs','.aai/scripts/lib/runtime-file.mjs']){
  assert.equal(profile.split('\n').filter(l=>l==='  - '+file).length,1,'exact profile membership '+file);
  assert.ok(core.split('\n').includes('  - '+file),'core classification '+file);
 }
 const f=fixture();historical(f,220,'.aai/scripts/unnoted.mjs');
 const scripts=path.join(f.repo,'.aai/scripts'),lib=path.join(scripts,'lib');fs.mkdirSync(lib,{recursive:true});
 for(const name of ['aai-release.sh','aai-release.ps1','release-finish.mjs','release-notes-gate.mjs'])fs.copyFileSync(path.join(root,'.aai/scripts',name),path.join(scripts,name));
 fs.copyFileSync(path.join(root,'.aai/scripts/lib/runtime-file.mjs'),path.join(lib,'runtime-file.mjs'));
 const copied=path.join(scripts,'release-finish.mjs'),gate=path.join(scripts,'release-notes-gate.mjs'),notes=path.join(f.d,'audit-notes');fs.writeFileSync(notes,'unrelated notes');
 const audit=()=>spawnSync('node',[copied,'--root',f.repo,'--audit',notes,'--online'],{cwd:f.repo,env:{...process.env,...f.env},encoding:'utf8'});
 const normal=audit();assert.equal(normal.status,0,normal.stderr);assert.match(normal.stdout,/#220 feat: shipped 220/);assert.equal(f.transport().calls.filter(a=>a[0]==='pr'&&a[1]==='view'&&a[2]==='220').length,1,'real historical metadata read');
 // Also execute the copied frontend, which must find the complete helper closure.
 const preview=spawnSync('bash',[path.join(scripts,'aai-release.sh'),'--dry-run','--version','v1'],{cwd:f.repo,env:{...process.env,...f.env},encoding:'utf8'});assert.equal(preview.status,0,preview.stdout+preview.stderr);assert.match(preview.stdout,/NAMED/);assert.match(preview.stdout,/#220 feat: shipped 220/);
 const original=fs.readFileSync(gate,'utf8');
 for(const [declaration,label] of [['export function isShipped(path, mode = \'\') {','shared-classifier-reached'],['export function hasNoNotesReason(body) {','shared-marker-reached']]){
  assert.ok(original.includes(declaration),'actual shared export declaration');
  fs.writeFileSync(gate,original.replace(declaration,declaration+' throw Error(\''+label+'\');'));
  const changed=audit();assert.notEqual(changed.status,0);assert.match(changed.stderr,new RegExp(label));
 }
 // Only the disposable copied module changed; source dependency stays immutable.
 assert.equal(fs.readFileSync(path.join(root,'.aai/scripts/release-notes-gate.mjs'),'utf8'),original);
 assert.ok(!fs.existsSync(path.join(f.repo,'.git/aai/releases')),'read-only audit/preview writes no journal');
 console.log('PASS: TEST-012/013 real helper, exact core profile, copied import closure and actual shared audit consumption');
});
if(selected==='PS'){const f=fixture(),r=f.invoke([],'ps');assert.equal(r.status,0,r.stdout+r.stderr);assert.equal(f.transport().prs.length,1);assert.equal(f.git('ls-remote','origin','refs/heads/chore/release-v1'),'');console.log('PASS: TEST-033 one-command PowerShell finish parity');}
JS
}


# Native capture is tested independently from the Node finish delegation so the
# same controls can run under Linux pwsh and both declared Windows runtimes.
test_701_native_capture_controls() {
  if ! command -v pwsh >/dev/null 2>&1; then
    log_info "TEST-013: NOT VERIFIED native capture (pwsh absent)"
    return 0
  fi
  local probe="$TMP_ROOT/native-capture.ps1"
  cat > "$probe" <<'NATIVE_PROBE'
$ErrorActionPreference = 'Stop'
. $env:AAI_RELEASE_PS1_PROBE
$sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$captured = Invoke-NativeChecked -Exe 'pwsh' -Arguments @('-NoProfile', '-Command', "[Console]::WriteLine('$sha')")
$value = Select-CapturedValue -Captured $captured -Pattern '^(?:[0-9a-f]{40}|[0-9a-f]{64})$' -Name 'native-sha'
if ($value -ne $sha) { throw 'normal native SHA was not captured' }
$url = 'https://github.com/test/release/pull/1'
$captured = Invoke-NativeChecked -Exe 'pwsh' -Arguments @('-NoProfile', '-Command', "[Console]::Error.WriteLine('benign progress'); [Console]::WriteLine('$url')")
$value = Select-CapturedValue -Captured $captured -Pattern '^https://github\.com/.+/pull/[0-9]+$' -Name 'native-url'
if ($value -ne $url) { throw 'normal native URL was not captured separately from progress' }
$captured = Invoke-NativeChecked -Exe 'pwsh' -Arguments @('-NoProfile', '-Command', 'exit 0')
foreach ($name in @('native-sha', 'native-url')) {
  $refused = $false
  try {
    $pattern = '^(?:[0-9a-f]{40}|[0-9a-f]{64})$'
    if ($name -eq 'native-url') { $pattern = '^https://github\.com/.+/pull/[0-9]+$' }
    Select-CapturedValue -Captured $captured -Pattern $pattern -Name $name | Out-Null
  }
  catch { if ($_.Exception.Message -notlike "*REFUSED: empty-native-output*$name*") { throw }; $refused = $true }
  if (-not $refused) { throw "empty $name accepted before reuse" }
}
$failed = $false
try { Invoke-NativeChecked -Exe 'pwsh' -Arguments @('-NoProfile', '-Command', "[Console]::Error.WriteLine('native failure control'); exit 7") | Out-Null }
catch { if ($_.Exception.Message -notlike '*exit 7*native failure control*') { throw }; $failed = $true }
if (-not $failed) { throw 'failed native command accepted' }
Write-Output 'PASS: TEST-013 native SHA/URL normal, empty refused, failed native refused'
NATIVE_PROBE
  AAI_RELEASE_PS1_PROBE="$RELEASE_PS1" pwsh -NoProfile -File "$probe"
}

main() {
  echo "=== AAI Skill Test: $TEST_NAME ==="
  check_deps

  if [[ $# -gt 0 ]]; then
    "$1"
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    return
  fi

  test_700_one_command_finish
  test_001_dry_run_plan_only
  test_002_bare_invocation_plan_only
  test_003_cut_rolls_changelog
  test_004_commit_message_and_staged_path
  test_005_annotated_tag
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
  test_030_followtags_cannot_orphan_the_tag
  test_031_unprotected_path_byte_identical
  test_032_non_protected_failure_degrades_raw
  test_033_ps1_fallback_parity
  test_701_native_capture_controls
  test_034_exit_codes_documented
  test_035_fallback_incomplete_exits_18
  test_625_fallback_branch_failure_reports
  test_626_fallback_reset_failure_reports
  test_627_ps1_fallback_guarded
  test_648_fallback_branch_conflict_names_ref
  test_036_golden_flow_record_precondition
  test_570_changelog_shape_is_documented

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
