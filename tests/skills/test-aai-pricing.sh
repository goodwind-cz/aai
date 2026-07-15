#!/usr/bin/env bash
#
# Test: aai-pricing — .aai/system/PRICING.yaml lookup contract
# (CHANGE-0010 / spec-model-tiering-with-teeth, spec-local TEST-006 / Spec-AC-03).
#
# A resolver implementing the PRICING.yaml `lookup_rules` VERBATIM
# (strip one trailing bracket suffix -> model_aliases -> exact -> longest
# prefix -> unknown) must resolve EVERY distinct model_id recorded in the real
# docs/ai/METRICS.jsonl history to a non-`unknown` entry (Seam B: real ledger
# against the real pricing table, no mocked ids). Also asserts the D4 price
# refresh (opus-4-6 5/25, haiku-4-5 1/5, fable-5 10/50, sonnet-5 3/15), the
# non-null last_verified_utc stamp on all Claude-family entries, the
# belt-and-braces "claude-opus-4-8[1m]" alias, and the prune rule (no
# null-priced entry outside METRICS history except `unknown`).
#
# bash 3.2 compatible (no ${var^^}, no declare -A, no mapfile).
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-pricing"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PRICING_FILE="$PROJECT_ROOT/.aai/system/PRICING.yaml"
METRICS_FILE="$PROJECT_ROOT/docs/ai/METRICS.jsonl"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$PRICING_FILE" ]] || log_fail "PRICING.yaml not found: $PRICING_FILE"
  [[ -f "$METRICS_FILE" ]] || log_skip "METRICS.jsonl not found (nothing recorded yet): $METRICS_FILE"
  log_pass "Dependencies checked"
}

# The whole contract check runs as ONE node script: PRICING.yaml is parsed with
# the same line-discipline the AAI tooling uses (no YAML lib), METRICS.jsonl
# model ids are extracted from the real ledger, and the lookup_rules resolver
# is implemented verbatim. Any violated assertion prints FAIL-NNN and exits 1.
run_contract() {
  node - "$PRICING_FILE" "$METRICS_FILE" <<'NODE'
const fs = require('fs');
const [pricingPath, metricsPath] = process.argv.slice(2);
const failures = [];
const fail = (id, msg) => failures.push(`FAIL-${id}: ${msg}`);

// --- parse PRICING.yaml (line engine: 2-space keys under model_aliases/models)
const lines = fs.readFileSync(pricingPath, 'utf8').split(/\r?\n/);
const aliases = {};   // runtime id -> canonical key
const models = {};    // key -> { input, output, last_verified }
let section = null;   // 'model_aliases' | 'models' | null
let current = null;
const unq = s => {
  s = s.trim();
  if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) return s.slice(1, -1);
  if (s.startsWith("'") && s.endsWith("'") && s.length >= 2) return s.slice(1, -1).replace(/''/g, "'");
  return s;
};
for (const line of lines) {
  if (/^\S/.test(line)) {
    const m = line.match(/^([A-Za-z_][\w-]*):/);
    section = m ? m[1] : null;
    current = null;
    continue;
  }
  if (line.trim() === '' || line.trim().startsWith('#')) continue;
  if (section === 'model_aliases') {
    const m = line.match(/^ {2}(\S+|"[^"]*"):\s*(\S+)\s*$/);
    if (m) aliases[unq(m[1])] = unq(m[2]);
  } else if (section === 'models') {
    let m = line.match(/^ {2}([^\s:]+):\s*$/);
    if (m) { current = unq(m[1]); models[current] = { input: undefined, output: undefined, last_verified: undefined }; continue; }
    if (!current) continue;
    m = line.match(/^ {4}(\w+):\s*(.*)$/);
    if (!m) continue;
    const v = unq(m[2]);
    if (m[1] === 'input_usd_per_m') models[current].input = v === 'null' ? null : Number(v);
    if (m[1] === 'output_usd_per_m') models[current].output = v === 'null' ? null : Number(v);
    if (m[1] === 'last_verified_utc') models[current].last_verified = v === 'null' ? null : v;
  }
}
if (Object.keys(models).length === 0) fail('000', 'no models parsed from PRICING.yaml');

// --- lookup_rules resolver, VERBATIM order (CHANGE-0010 D4):
// 1) strip one trailing bracket suffix; 2) model_aliases; 3) exact match;
// 4) longest-prefix match against models keys; 5) fall back to `unknown`.
function resolve(runtimeId) {
  let id = String(runtimeId).trim().replace(/\[[^\]]*\]$/, '');   // rule 1
  if (Object.prototype.hasOwnProperty.call(aliases, id)) id = aliases[id];   // rule 2
  if (Object.prototype.hasOwnProperty.call(models, id)) return id;           // rule 3
  let best = null;                                                           // rule 4
  for (const key of Object.keys(models)) {
    if (key !== 'unknown' && id.startsWith(key) && (best === null || key.length > best.length)) best = key;
  }
  if (best !== null) return best;
  return 'unknown';                                                          // rule 5
}

// --- distinct model ids actually recorded in the real METRICS.jsonl history
const metricsRaw = fs.readFileSync(metricsPath, 'utf8');
const historyIds = new Set();
for (const m of metricsRaw.matchAll(/"model_id"\s*:\s*"([^"]*)"/g)) historyIds.add(m[1]);
if (historyIds.size === 0) fail('001', 'no model_id values found in METRICS.jsonl (test would be vacuous)');

// Assert 1: every historical id resolves to a non-unknown entry.
for (const id of historyIds) {
  const key = resolve(id);
  if (key === 'unknown') fail('002', `historical model_id "${id}" resolves to unknown`);
  else console.log(`RESOLVED: ${id} -> ${key}`);
}

// Assert 2: D4 price refresh values.
const expect = {
  'claude-opus-4-6': [5.0, 25.0],
  'claude-haiku-4-5': [1.0, 5.0],
  'claude-fable-5': [10.0, 50.0],
  'claude-sonnet-5': [3.0, 15.0],
};
for (const [key, [inp, out]] of Object.entries(expect)) {
  const e = models[key];
  if (!e) { fail('003', `expected models entry "${key}" missing`); continue; }
  if (e.input !== inp || e.output !== out) {
    fail('004', `${key} priced ${e.input}/${e.output}, expected ${inp}/${out}`);
  }
}

// Assert 3: the belt-and-braces alias for the one bracketed historical id.
if (aliases['claude-opus-4-8[1m]'] !== 'claude-opus-4-8') {
  fail('005', 'model_aliases must map "claude-opus-4-8[1m]" -> claude-opus-4-8');
}
// The bracketed id must resolve to claude-opus-4-8 via suffix strip too.
if (resolve('claude-opus-4-8[1m]') !== 'claude-opus-4-8') {
  fail('006', 'claude-opus-4-8[1m] must resolve to claude-opus-4-8');
}

// Assert 4: last_verified_utc non-null on ALL Claude-family entries.
for (const [key, e] of Object.entries(models)) {
  if (key.startsWith('claude-') && (e.last_verified === null || e.last_verified === undefined)) {
    fail('007', `Claude-family entry ${key} has null last_verified_utc`);
  }
}

// Assert 5 (prune rule): no null-priced entry outside METRICS history except
// `unknown`. Historical ids are compared through the resolver so a bracketed
// runtime id protects its base entry.
const historyKeys = new Set([...historyIds].map(resolve));
for (const [key, e] of Object.entries(models)) {
  if (key === 'unknown') continue;
  if ((e.input === null || e.output === null) && !historyKeys.has(key)) {
    fail('008', `null-priced entry "${key}" is absent from METRICS.jsonl history — prune rule violated`);
  }
}

// Assert 6: the lookup_rules section itself is documented in the file.
if (!/^lookup_rules:/m.test(fs.readFileSync(pricingPath, 'utf8'))) {
  fail('009', 'PRICING.yaml must document a top-level lookup_rules: section');
}

if (failures.length > 0) {
  for (const f of failures) console.error(f);
  process.exit(1);
}
console.log('CONTRACT: all pricing lookup assertions hold');
NODE
}

test_pricing_contract() {
  log_info "Test: PRICING.yaml lookup_rules resolve all METRICS.jsonl history ids + D4 refresh (CHANGE-0010 TEST-006)..."
  local out ec=0
  out="$(run_contract 2>&1)" || ec=$?
  echo "$out"
  [[ "$ec" == 0 ]] || log_fail "pricing contract violated (exit $ec)"
  echo "$out" | grep -q '^RESOLVED: ' || log_fail "resolver produced no RESOLVED lines (vacuous run)"
  log_pass "All historical model ids resolve non-unknown; D4 prices, stamps, alias and prune rule hold (CHANGE-0010 TEST-006)"
}

main() {
  echo "Testing $TEST_NAME (PRICING.yaml lookup contract — CHANGE-0010 TEST-006)"
  check_deps
  test_pricing_contract
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

# Allow sourcing for isolated per-test execution (TDD RED/GREEN evidence);
# run the full suite only when invoked directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then
    check_deps
    "$1"
  else
    main
  fi
fi
