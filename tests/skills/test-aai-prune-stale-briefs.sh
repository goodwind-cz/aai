#!/usr/bin/env bash
#
# Test: .aai/scripts/prune-stale-briefs.mjs — the AAI-level stale-brief sweep
# (docs-lifecycle hygiene). A brief docs/ai/briefs/<REF-ID>.md is a gitignored
# Planning handoff; it is LIVE only while its work item is open, and dead clutter
# once the item is terminal (done|deferred|rejected|superseded|legacy) or its doc
# no longer exists (orphan). This sweep prunes the stale ones and keeps the live.
#
#   - TEST-001: a brief for a DONE doc (by slug id) is pruned.
#   - TEST-002: a brief for the same doc by its DISPLAY id (CHANGE-0001.md) is pruned.
#   - TEST-003: a brief for an OPEN (implementing) doc is KEPT — a live handoff is
#     never removed.
#   - TEST-004: an ORPHAN brief (no matching doc) is pruned.
#   - TEST-005: --dry-run removes NOTHING but reports the same set; --json shape.
#   - TEST-006: .gitkeep is never touched; exit 0 always.
#
# bash 3.2 compatible. Run via .aai/scripts/aai-run-tests.sh per the wrapper rule.
#
# Exit codes: 0 pass / 1 fail / 42 skip (missing deps)

set -euo pipefail

TEST_NAME="aai-prune-stale-briefs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PRUNE="$PROJECT_ROOT/.aai/scripts/prune-stale-briefs.mjs"
TEST_DIR=""

cleanup() { [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR" || true; }
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

command -v node >/dev/null 2>&1 || log_skip "node not found"
[[ -f "$PRUNE" ]] || log_fail "prune-stale-briefs.mjs not found: $PRUNE"

# write_doc <path> <id> <status>
write_doc() {
  cat > "$1" <<EOF
---
id: $2
type: change
status: $3
links:
  pr: []
  commits: []
---
# Fixture $2
## Summary
- fixture.
EOF
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-prune-briefs.XXXXXX")"
  mkdir -p "$TEST_DIR/docs/issues" "$TEST_DIR/docs/ai/briefs"
  # A DONE doc (display id CHANGE-0001, slug done-slug) + an OPEN one (implementing).
  write_doc "$TEST_DIR/docs/issues/CHANGE-0001-done.md" "done-slug" "done"
  write_doc "$TEST_DIR/docs/issues/CHANGE-0002-open.md" "open-slug" "implementing"
  # Briefs: slug-named done, display-id-named done, slug-named open, and an orphan.
  printf 'b\n' > "$TEST_DIR/docs/ai/briefs/done-slug.md"
  printf 'b\n' > "$TEST_DIR/docs/ai/briefs/CHANGE-0001.md"
  printf 'b\n' > "$TEST_DIR/docs/ai/briefs/open-slug.md"
  printf 'b\n' > "$TEST_DIR/docs/ai/briefs/nobody-here.md"
  : > "$TEST_DIR/docs/ai/briefs/.gitkeep"
}

run() { ( cd "$TEST_DIR" && node "$PRUNE" "$@" ); }
b() { [[ -e "$TEST_DIR/docs/ai/briefs/$1" ]]; }

main() {
  echo "=== $TEST_NAME ==="
  setup_fixture

  # TEST-005 first: --dry-run must remove NOTHING.
  log_info "TEST-005: --dry-run removes nothing, reports the stale set..."
  local out; out="$(run --dry-run)"
  b done-slug.md && b CHANGE-0001.md && b nobody-here.md && b open-slug.md \
    || log_fail "TEST-005: --dry-run must not remove any brief"
  echo "$out" | grep -q "would prune 3" \
    || log_fail "TEST-005: --dry-run must report 3 stale (done slug + done display-id + orphan), got: $out"
  local jout; jout="$(run --dry-run --json)"
  echo "$jout" | grep -q '"kept_open": 1' || log_fail "TEST-005: --json must report kept_open:1"
  echo "$jout" | grep -q '"dry_run": true' || log_fail "TEST-005: --json must report dry_run:true"
  log_pass "TEST-005: --dry-run reports 3 stale / 1 live, removes nothing, --json shape ok"

  # Real sweep.
  log_info "TEST-001..004: real sweep prunes terminal + orphan, keeps open..."
  run >/dev/null
  b done-slug.md    && log_fail "TEST-001: DONE doc's slug brief must be pruned"
  b CHANGE-0001.md  && log_fail "TEST-002: DONE doc's DISPLAY-id brief must be pruned"
  b open-slug.md    || log_fail "TEST-003: OPEN (implementing) doc's brief must be KEPT (live handoff)"
  b nobody-here.md  && log_fail "TEST-004: ORPHAN brief (no doc) must be pruned"
  log_pass "TEST-001..004: terminal (slug + display-id) + orphan pruned; open kept"

  # TEST-006: .gitkeep survives; a second run is a clean no-op (idempotent).
  log_info "TEST-006: .gitkeep untouched, idempotent no-op second run..."
  b .gitkeep || log_fail "TEST-006: .gitkeep must never be pruned"
  local out2; out2="$(run)"
  echo "$out2" | grep -q "nothing to prune" || log_fail "TEST-006: second run must be a no-op, got: $out2"
  log_pass "TEST-006: .gitkeep preserved; second run is a clean no-op"

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
