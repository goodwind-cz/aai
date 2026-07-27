#!/usr/bin/env bash
#
# Test: aai-prompt-hash — content-addressed identity of the EFFECTIVE
# instruction stack a role ran under (prompt-hash-telemetry /
# SPEC-0096-spec-prompt-hash-telemetry, TEST-001 / Spec-AC-01).
#
# Verifies .aai/scripts/lib/prompt-hash.mjs:
#   computeEffectivePromptHash(rolePromptPath, root) — sha256 over the role
#   prompt file + .aai/SUBAGENT_CONTRACT.md + docs/knowledge/LEARNED.md
#   (fixed order, filename-separated); a missing input contributes the
#   literal ABSENT marker; never throws.
#   shortHash(hash) — first 12 hex chars.
#
# ALL fixtures are scratch temp-dir trees; the real repo's .aai/
# SUBAGENT_CONTRACT.md and docs/knowledge/LEARNED.md are NEVER read or
# mutated by this suite (only the `root` param is exercised against fixture
# trees). bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-prompt-hash"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$PROJECT_ROOT/.aai/scripts/lib/prompt-hash.mjs"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixture at $TEST_DIR"
    return 0
  fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$LIB" ]] || log_fail "lib not found: $LIB (RED until prompt-hash-telemetry lands)"
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-prompt-hash-test.XXXXXX")"
}

# write_fixture_root <dir> — a minimal fixture tree with a role prompt,
# SUBAGENT_CONTRACT.md, and docs/knowledge/LEARNED.md, all present.
write_fixture_root() {
  local d="$1"
  mkdir -p "$d/.aai" "$d/docs/knowledge"
  printf 'Role prompt body v1.\n' > "$d/.aai/ROLE.prompt.md"
  printf 'Contract body v1.\n' > "$d/.aai/SUBAGENT_CONTRACT.md"
  printf 'Learned rules v1.\n' > "$d/docs/knowledge/LEARNED.md"
}

# node_eval <js-snippet> — imports the lib against the REAL PROJECT_ROOT
# (lib code itself, not the fixture data) and runs the snippet.
node_eval() {
  (cd "$PROJECT_ROOT" && node --input-type=module -e "$1")
}

test_001_hash_lib_contract() {  # TEST-001 / Spec-AC-01
  log_info "Test: hash deterministic; sensitive to role/CONTRACT/LEARNED bytes; ABSENT marker; short form (TEST-001)..."
  local d1 d2
  d1="$TEST_DIR/fx1"
  d2="$TEST_DIR/fx2"
  write_fixture_root "$d1"
  write_fixture_root "$d2"

  # (a) deterministic on double-run over identical fixture trees.
  node_eval "
    import { computeEffectivePromptHash } from '$LIB';
    const h1 = computeEffectivePromptHash('.aai/ROLE.prompt.md', '$d1');
    const h2 = computeEffectivePromptHash('.aai/ROLE.prompt.md', '$d1');
    if (h1 !== h2) { console.error('not deterministic: ' + h1 + ' vs ' + h2); process.exit(1); }
    if (!/^[0-9a-f]{64}\$/.test(h1)) { console.error('not a 64-char lowercase hex: ' + h1); process.exit(1); }
    console.log('OK ' + h1);
  " || log_fail "(a) hash must be deterministic and a 64-char lowercase hex digest"

  # (b) identical fixture trees -> identical hash (cross-tree stability).
  local hb1 hb2
  hb1="$(node_eval "
    import { computeEffectivePromptHash } from '$LIB';
    process.stdout.write(computeEffectivePromptHash('.aai/ROLE.prompt.md', '$d1'));
  ")"
  hb2="$(node_eval "
    import { computeEffectivePromptHash } from '$LIB';
    process.stdout.write(computeEffectivePromptHash('.aai/ROLE.prompt.md', '$d2'));
  ")"
  [[ "$hb1" == "$hb2" ]] || log_fail "(b) identical role/CONTRACT/LEARNED bytes across trees must hash identically"

  # (c) changing the ROLE PROMPT changes the hash.
  printf 'Role prompt body v2 (changed).\n' > "$d2/.aai/ROLE.prompt.md"
  local hc
  hc="$(node_eval "
    import { computeEffectivePromptHash } from '$LIB';
    process.stdout.write(computeEffectivePromptHash('.aai/ROLE.prompt.md', '$d2'));
  ")"
  [[ "$hc" != "$hb1" ]] || log_fail "(c) changing the role prompt bytes must change the hash"
  write_fixture_root "$d2"   # reset

  # (d) changing SUBAGENT_CONTRACT.md changes the hash.
  printf 'Contract body v2 (changed).\n' > "$d2/.aai/SUBAGENT_CONTRACT.md"
  local hd
  hd="$(node_eval "
    import { computeEffectivePromptHash } from '$LIB';
    process.stdout.write(computeEffectivePromptHash('.aai/ROLE.prompt.md', '$d2'));
  ")"
  [[ "$hd" != "$hb1" ]] || log_fail "(d) changing SUBAGENT_CONTRACT.md bytes must change the hash"
  write_fixture_root "$d2"   # reset

  # (e) changing LEARNED.md changes the hash.
  printf 'Learned rules v2 (changed).\n' > "$d2/docs/knowledge/LEARNED.md"
  local he
  he="$(node_eval "
    import { computeEffectivePromptHash } from '$LIB';
    process.stdout.write(computeEffectivePromptHash('.aai/ROLE.prompt.md', '$d2'));
  ")"
  [[ "$he" != "$hb1" ]] || log_fail "(e) changing LEARNED.md bytes must change the hash"

  # (f) a missing LEARNED.md contributes the ABSENT marker, never throws, and
  # differs from the present-LEARNED hash.
  local d3
  d3="$TEST_DIR/fx3"
  write_fixture_root "$d3"
  rm -f "$d3/docs/knowledge/LEARNED.md"
  local hf ec
  ec=0
  hf="$(node_eval "
    import { computeEffectivePromptHash } from '$LIB';
    process.stdout.write(computeEffectivePromptHash('.aai/ROLE.prompt.md', '$d3'));
  ")" || ec=$?
  [[ "$ec" == 0 ]] || log_fail "(f) a missing LEARNED.md must never throw (exit $ec)"
  [[ -n "$hf" ]] || log_fail "(f) missing LEARNED.md must still produce a hash"
  [[ "$hf" != "$hb1" ]] || log_fail "(f) missing LEARNED.md (ABSENT marker) must hash differently than present LEARNED.md"

  # (g) a missing role prompt file also never throws (ABSENT marker).
  local hg
  ec=0
  hg="$(node_eval "
    import { computeEffectivePromptHash } from '$LIB';
    process.stdout.write(computeEffectivePromptHash('.aai/NOPE.prompt.md', '$d1'));
  ")" || ec=$?
  [[ "$ec" == 0 ]] || log_fail "(g) a missing role prompt must never throw (exit $ec)"
  [[ -n "$hg" ]] || log_fail "(g) missing role prompt must still produce a hash"

  # (h) shortHash returns the first 12 hex chars of the full digest.
  node_eval "
    import { computeEffectivePromptHash, shortHash } from '$LIB';
    const full = computeEffectivePromptHash('.aai/ROLE.prompt.md', '$d1');
    const s = shortHash(full);
    if (s !== full.slice(0, 12)) { console.error('shortHash mismatch: ' + s + ' vs ' + full.slice(0, 12)); process.exit(1); }
    if (!/^[0-9a-f]{12}\$/.test(s)) { console.error('shortHash not 12 lowercase hex: ' + s); process.exit(1); }
  " || log_fail "(h) shortHash must be exactly the first 12 hex chars of the full digest"

  log_pass "Deterministic, input-sensitive (role/CONTRACT/LEARNED), ABSENT marker on missing input, never throws, shortHash = 12 hex (TEST-001)"
}

main() {
  echo "Testing $TEST_NAME (prompt-hash-telemetry TEST-001 / Spec-AC-01)"
  check_deps
  setup_fixture
  test_001_hash_lib_contract
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (TDD RED/GREEN evidence);
# run the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then
    check_deps
    setup_fixture
    "$1"
  else
    main
  fi
fi
