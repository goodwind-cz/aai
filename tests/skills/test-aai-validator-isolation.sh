#!/usr/bin/env bash
#
# Test: aai-validator-isolation — capability-detected validator isolation
# (CHANGE-0132 / docs/specs/SPEC-0119-spec-validation-cost-calibration.md,
# spec TEST-003..006 / Spec-AC-02..03).
#
# Verifies .aai/SUBAGENT_PROTOCOL.md:
#   - TEST-001 (spec TEST-003/Spec-AC-02): the capability-detection contract
#     names all four fields (multi_agent_backend, spawn_agent_available,
#     spawn_model_catalog, fork_turns_supported), states runtime resolution
#     before the first dispatch, re-resolution after a refused spawn, and
#     fail-closed-on-unknown to the next isolation tier.
#   - TEST-002 (spec TEST-004/Spec-AC-02): corpus negative control over
#     .aai/*.md (canon prose only, scripts excluded) — zero hits for a
#     harness-name equality test gating subagent behavior.
#   - TEST-003 (spec TEST-005/Spec-AC-03): the four isolation tiers appear in
#     the "Spawning a validator" section IN FILE ORDER carrying their
#     required tokens, plus the verify-the-granted-model clause.
#   - TEST-004 (spec TEST-006/Spec-AC-03): corpus sweep over .aai/*.md for a
#     named-harness subagent denial ("Codex has no subagents"-shaped claims);
#     expected zero hits.
#
# ALL greps run against the LIVE repo tree (this is a canon-prose suite, no
# fixtures to author). bash 3.2 compatible.
#
# Exit codes: 0 pass, 1 fail, 42 skip.

set -euo pipefail

TEST_NAME="aai-validator-isolation"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Pipe-free payload assertions (spec-assertions-must-not-die-on-their-own-payload).
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROTOCOL="$PROJECT_ROOT/.aai/SUBAGENT_PROTOCOL.md"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v grep >/dev/null 2>&1 || log_skip "grep not found"
  [[ -f "$PROTOCOL" ]] || log_fail "SUBAGENT_PROTOCOL.md not found: $PROTOCOL"
  log_pass "Dependencies checked"
}

# --- TEST-001 (spec TEST-003/Spec-AC-02): capability-detection contract ------

test_001_capability_detection_contract() {
  log_info "Test: capability-detection section names all four fields, runtime resolution, re-resolution, fail-closed (spec TEST-003)..."
  grep -qF '## Capability detection' "$PROTOCOL" \
    || log_fail "TEST-001: SUBAGENT_PROTOCOL.md must carry a Capability detection section"
  local block
  block="$(awk '/^## Capability detection/{f=1} /^## /{if (f && !/^## Capability detection/) f=0} f' "$PROTOCOL")"
  [[ -n "$block" ]] || log_fail "TEST-001: Capability detection section body not found"

  assert_payload_contains "$block" "multi_agent_backend" "TEST-001: Capability detection section must name multi_agent_backend"
  assert_payload_contains "$block" "spawn_agent_available" "TEST-001: Capability detection section must name spawn_agent_available"
  assert_payload_contains "$block" "spawn_model_catalog" "TEST-001: Capability detection section must name spawn_model_catalog"
  assert_payload_contains "$block" "fork_turns_supported" "TEST-001: Capability detection section must name fork_turns_supported"

  echo "$block" | grep -qiF 'runtime' \
    || log_fail "TEST-001: capabilities must be resolved AT RUNTIME"
  echo "$block" | grep -qiF 're-resolved' \
    || log_fail "TEST-001: capabilities must be re-resolved when a spawn call is refused"
  echo "$block" | grep -qiF 'fail' \
    || log_fail "TEST-001: an unknown capability must fail closed to the next isolation tier"
  echo "$block" | grep -qiF 'harness' \
    && echo "$block" | grep -qiF 'not on harness name equality' \
    || log_fail "TEST-001: behavior must be keyed on detected capabilities, NOT harness-name equality"

  log_pass "Capability-detection contract: four fields + runtime/re-resolution/fail-closed/no-harness-equality wording (TEST-001/spec TEST-003)"
}

# --- TEST-002 (spec TEST-004/Spec-AC-02): corpus negative control -----------
# harness-name equality test gating subagent behavior — zero hits across
# .aai/*.md canon prose (scripts, which legitimately branch on harness for
# host-specific command rendering, e.g. routine-emit.mjs, are excluded by
# the --include='*.md' scope: no .md files live under .aai/scripts).
#
# The identifier alternation is not limited to a variable literally named
# `harness` (Codex P2, review-20260812T083704Z): a harness-equality gate is
# just as real when it is spelled `agent`, `backend`, `platform`, or `tool`
# (optionally suffixed, e.g. `agent_name`, `platformType`) compared to a
# harness-name string literal. Widened 2026-08-12; re-verified zero hits on
# the live corpus (mutation-proven to still catch a synthetic
# `agent_name === "claude"` / `platformType is "codex"` violation).

test_002_no_harness_equality_gate() {
  log_info "Test: corpus negative control — no harness-name equality test gates subagent behavior (spec TEST-004)..."
  local hits
  hits="$(grep -rniE "(harness|agent|backend|platform|tool)[a-zA-Z_]*[[:space:]]*(==|===|is|equals|matches)[[:space:]]*['\"]?(claude|codex|gemini)" \
    "$PROJECT_ROOT/.aai" --include='*.md' 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    echo "$hits" >&2
    log_fail "TEST-002: a harness-name equality test gating subagent behavior was found (see hits above)"
  fi
  log_pass "Corpus negative control: zero harness-name equality gates (TEST-002/spec TEST-004)"
}

# --- TEST-003 (spec TEST-005/Spec-AC-03): four isolation tiers in order -----

test_003_four_tiers_in_order() {
  log_info "Test: four isolation tiers appear IN FILE ORDER in 'Spawning a validator' with required tokens + verify-the-granted-model clause (spec TEST-005)..."
  grep -qF '## Spawning a validator' "$PROTOCOL" \
    || log_fail "TEST-003: SUBAGENT_PROTOCOL.md must carry a 'Spawning a validator' section"
  local block
  block="$(awk '/^## Spawning a validator/{f=1} /^## Harness-reported usage capture/{f=0} f' "$PROTOCOL")"
  [[ -n "$block" ]] || log_fail "TEST-003: 'Spawning a validator' section body not found (must end before Harness-reported usage capture)"

  # awk first-match (NOT `grep -n ... | head -1 | cut -d: -f1`): under this
  # file's `set -euo pipefail`, a grep with ZERO matches exits 1, and that
  # exit status survives through `head`/`cut` under pipefail, aborting the
  # whole script at the assignment -- BEFORE the `[[ -n ... ]] || log_fail`
  # diagnostics below ever run (the repo's own learned pipefail trap,
  # review-20260812T083704Z CQ-3). `awk '{...; exit}'` exits 0 whether or
  # not it finds a match, so a missing token now reaches its own log_fail
  # with a named reason instead of a silent mid-test abort.
  local pos_spawn_agent pos_fork_turns pos_catalog_retry pos_codex_exec pos_last_resort
  pos_spawn_agent="$(printf '%s\n' "$block" | awk '/spawn_agent/{print NR; exit}')"
  pos_fork_turns="$(printf '%s\n' "$block" | awk '/fork_turns/{print NR; exit}')"
  pos_catalog_retry="$(printf '%s\n' "$block" | awk '/spawn_model_catalog/{print NR; exit}')"
  pos_codex_exec="$(printf '%s\n' "$block" | awk '/codex exec -m/{print NR; exit}')"
  pos_last_resort="$(printf '%s\n' "$block" | awk 'tolower($0) ~ /last resort/{print NR; exit}')"

  [[ -n "$pos_spawn_agent" ]] || log_fail "TEST-003: tier 1 (native spawn_agent) token 'spawn_agent' not found"
  [[ -n "$pos_fork_turns" ]] || log_fail "TEST-003: tier 1 token 'fork_turns' not found"
  [[ -n "$pos_catalog_retry" ]] || log_fail "TEST-003: tier 2 token 'spawn_model_catalog' not found"
  [[ -n "$pos_codex_exec" ]] || log_fail "TEST-003: tier 3 token 'codex exec -m' not found"
  [[ -n "$pos_last_resort" ]] || log_fail "TEST-003: tier 4 'last resort' wording not found"

  echo "$block" | grep -qiF 'residual risk' \
    || log_fail "TEST-003: tier 4 (last resort) must record a residual risk"

  # File-order check: tier 1 tokens < tier-2 catalog retry < tier-3 codex exec < tier-4 last resort.
  if ! [[ "$pos_spawn_agent" -lt "$pos_catalog_retry" && "$pos_fork_turns" -lt "$pos_catalog_retry" \
        && "$pos_catalog_retry" -lt "$pos_codex_exec" && "$pos_codex_exec" -lt "$pos_last_resort" ]]; then
    log_fail "TEST-003: the four tiers must appear IN FILE ORDER (spawn_agent/fork_turns < spawn_model_catalog retry < codex exec -m < last resort); got positions $pos_spawn_agent/$pos_fork_turns/$pos_catalog_retry/$pos_codex_exec/$pos_last_resort"
  fi

  echo "$block" | grep -qiF 'verify' \
    || log_fail "TEST-003: the orchestrator must VERIFY the granted model rather than assume the override took"

  log_pass "Four isolation tiers in file order + residual-risk + verify-granted-model clause (TEST-003/spec TEST-005)"
}

# --- TEST-004 (spec TEST-006/Spec-AC-03): corpus sweep, named-harness denial -

test_004_no_named_harness_denial() {
  log_info "Test: corpus sweep — no file asserts a named harness lacks subagents or cannot spawn (spec TEST-006)..."
  local deny_re harness_re hits
  # `\b` is a GNU/PCRE extension, not a POSIX ERE metacharacter (Copilot
  # finding, review-20260812T083704Z): a BSD `grep -E` is free to treat it as
  # unspecified/literal, producing silent false negatives. Use an ERE-safe
  # boundary instead — a non-alnum/underscore character or line start/end on
  # each side — so the sweep behaves identically on GNU and BSD grep.
  harness_re='(^|[^[:alnum:]_])(claude|codex|gemini)([^[:alnum:]_]|$)'
  deny_re='(has no|have no|no native|cannot spawn|does not support)[^.]{0,60}(subagent|spawn)'
  hits="$(grep -rniE "$harness_re" "$PROJECT_ROOT/.aai" --include='*.md' 2>/dev/null \
    | grep -iE "$deny_re" || true)"
  if [[ -n "$hits" ]]; then
    echo "$hits" >&2
    log_fail "TEST-004: a named-harness subagent-denial claim was found (see hits above)"
  fi
  log_pass "Corpus sweep: zero named-harness subagent-denial claims (TEST-004/spec TEST-006)"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps

  test_001_capability_detection_contract
  test_002_no_harness_equality_gate
  test_003_four_tiers_in_order
  test_004_no_named_harness_denial

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
