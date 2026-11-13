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
# refresh (opus-4-6 5/25, haiku-4-5 1/5, fable-5 10/50) and the 2026-11-13 refresh (sonnet-5 2/10, opus-5-5 4/20, sonnet-5-5 2/10, haiku-5-5 0.10/0.50), the
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
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PRICING_FILE="$PROJECT_ROOT/.aai/system/PRICING.yaml"
METRICS_FILE="$PROJECT_ROOT/docs/ai/METRICS.jsonl"

log_pass() { echo "PASS: $*"; }
# CASE_TAG names the running TEST-nnn in every FAIL line (mutation-run keys on it).
CASE_TAG=""
log_fail() { echo "FAIL: ${CASE_TAG:+[$CASE_TAG] }$*" >&2; exit 1; }
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
// The literal id "unknown" is the CANONICAL not-reported sentinel: METRICS_FLUSH
// mandates 'model_id: record exactly as reported; use "unknown" if not
// reported', and PRICING.yaml keeps the matching null-priced sentinel entry.
// A recorded "unknown" is therefore an acknowledged gap, not a resolution
// failure — exempt it from Assert 1 (it resolves to itself by design).
historyIds.delete('unknown');

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
  'claude-sonnet-5': [2.0, 10.0],
  // First refresh 2026-11-13 (primary vendor pages): every claude id routed
  // in MODEL_ROUTING.yaml, plus the priced-only fable-5-2.
  'claude-opus-5-5': [4.0, 20.0],
  'claude-sonnet-5-5': [2.0, 10.0],
  'claude-haiku-5-5': [0.10, 0.50],
  'claude-fable-5-2': [8.0, 40.0],
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

// Assert 7 (CHANGE-0197 AC-001): catalog families priced or documented as omitted.
const catalog = [
  'claude-fable-5-1', 'claude-fable-5-2', 'claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5',
  'gpt-5.6-sol', 'gpt-5.6-terra', 'gemini-3.8-flash', 'grok-4.7',
  'gpt-6-astra', 'gpt-6-sol', 'gpt-6-luna', 'gpt-6.1-sol', 'gpt-6.1-terra',
];
const omitted = ['composer-2.5', 'cursor-grok-4.6', 'muse-spark-1.3'];
const pricingText = fs.readFileSync(pricingPath, 'utf8');
for (const id of catalog) {
  const e = models[id];
  if (!e) { fail('010', `catalog family "${id}" missing models entry`); continue; }
  if (!(typeof e.input === 'number' && typeof e.output === 'number' && e.input > 0 && e.output > 0)) {
    fail('010', `catalog family "${id}" must have finite input/output rates`);
  }
  if (!e.last_verified) fail('010', `catalog family "${id}" missing last_verified_utc`);
}
for (const id of omitted) {
  // An omitted family stays key-less until a run of it lands in METRICS.jsonl
  // history; from then on PRICING's own on_unknown_model / prune_rule require a
  // NULL-priced key so Assert 1 resolves it. A priced key is never allowed.
  const inHistory = [...historyIds].some((h) => h.startsWith(id));
  if (Object.prototype.hasOwnProperty.call(models, id)) {
    const e = models[id];
    if (!inHistory) fail('011', `omitted catalog family "${id}" must not have a models key`);
    else if (e.input !== null || e.output !== null) fail('011', `omitted catalog family "${id}" recorded in history must be null-priced`);
  }
  const noteLine = pricingText.split('\n').find((l) => l.includes(id) && /https?:\/\//.test(l));
  if (!noteLine) {
    fail('011', `omitted catalog family "${id}" must appear in PRICING.yaml notes with a checked URL (https://...)`);
  }
}
for (const id of catalog) {
  for (const suffix of ['', '-high', '-xhigh']) {
    const runtime = id + suffix;
    const key = resolve(runtime);
    if (key !== id) fail('012', `resolver ${runtime} -> ${key}, expected ${id}`);
    else console.log(`RESOLVED: ${runtime} -> ${key}`);
  }
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
  assert_payload_line_matches "$out" '^RESOLVED: ' "resolver produced no RESOLVED lines (vacuous run)"
  log_pass "All historical model ids resolve non-unknown; D4 prices, stamps, alias and prune rule hold (CHANGE-0010 TEST-006)"
}

# --- routing-table keeper (spec-routing-tables-have-an-owner-and-a-seam) ------
# Every case pins --now (or a horizon) so no case depends on the wall clock.
FRESHNESS_SCRIPT="$PROJECT_ROOT/.aai/scripts/table-freshness.mjs"
ROUTING_FILE="$PROJECT_ROOT/.aai/system/MODEL_ROUTING.yaml"

# make_tables_root <dir> <routing-stamp> <pricing-stamp>: a fixture root holding
# a marker-only MODEL_ROUTING.yaml and PRICING.yaml.
make_tables_root() {
  local d="$1" rs="$2" ps="$3"
  mkdir -p "$d/.aai/system"
  printf 'routing_meta:\n  last_updated_utc: "%s"\n  cadence_days: 30\n' "$rs" > "$d/.aai/system/MODEL_ROUTING.yaml"
  printf 'pricing_meta:\n  last_updated_utc: "%s"\nupdate_policy:\n  cadence_days: 30\n' "$ps" > "$d/.aai/system/PRICING.yaml"
}

# freshness <args...>: runs the CLI, prints its output and a trailing RC=<n>
# line (an explicit capture that survives `set -e`). FRESH_H injects
# AAI_TABLES_HORIZON_DAYS; unset/empty means no env override.
freshness() {
  local out rc=0
  out="$(env -u AAI_ROLE AAI_TABLES_HORIZON_DAYS="${FRESH_H:-}" node "$FRESHNESS_SCRIPT" "$@" 2>&1)" || rc=$?
  printf '%s\nRC=%s\n' "$out" "$rc"
}

test_routing_marker_and_resolution_unchanged() {
  CASE_TAG=TEST-3660
  log_info "Test: MODEL_ROUTING routing_meta marker is valid and changes no resolution (TEST-3660)..."
  [[ -f "$FRESHNESS_SCRIPT" ]] || log_fail "table-freshness.mjs missing"
  local scratch out ec=0
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/aai-pricing-3660.XXXXXX")"
  mkdir -p "$scratch/.aai/system"
  # Same file with the routing_meta block (and its two rows) removed.
  awk '/^routing_meta:/{skip=1; next} skip && /^  /{next} {skip=0; print}' "$ROUTING_FILE" > "$scratch/.aai/system/MODEL_ROUTING.yaml"
  if /usr/bin/grep -q '^routing_meta:' "$scratch/.aai/system/MODEL_ROUTING.yaml"; then
    rm -rf "$scratch"; log_fail "scratch copy still carries routing_meta"
  fi
  out="$(PROJECT_ROOT="$PROJECT_ROOT" SCRATCH="$scratch" node --input-type=module - <<'NODE' 2>&1
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const root = process.env.PROJECT_ROOT;
const od = await import(pathToFileURL(path.join(root, '.aai/scripts/orchestration-dispatch.mjs')).href);
const tf = await import(pathToFileURL(path.join(root, '.aai/scripts/table-freshness.mjs')).href);
const failures = [];
const marker = tf.readMarker(fs.readFileSync(path.join(root, '.aai/system/MODEL_ROUTING.yaml'), 'utf8'), 'routing');
if (!marker.ok) failures.push('FAIL-001 shipped marker not ok: ' + marker.reason);
else if (marker.cadence !== 30) failures.push('FAIL-002 cadence is ' + marker.cadence);
const withBlock = od.loadModelRouting(root);
const without = od.loadModelRouting(process.env.SCRATCH);
const roles = ['Planning', 'Implementation', 'TDD Implementation', 'Validation', 'Code Review', 'Remediation', 'Metrics Flush', 'Research', 'Intake'];
const tiers = ['mechanical', 'standard', 'premium'];
let n = 0;
for (const harness of ['claude', 'codex', 'gemini']) {
  for (const role of roles) for (const tier of tiers) for (const lane of ['lightweight', 'full']) {
    const mk = () => ({ verdict: 'dispatch', role, suggested_tier: tier, harness, lane: { selected: lane } });
    const a = mk(), b = mk();
    const ra = { m: od.suggestModel(a, withBlock), e: od.suggestEffort(a, withBlock) };
    const rb = { m: od.suggestModel(b, without), e: od.suggestEffort(b, without) };
    n++;
    if (JSON.stringify(ra) !== JSON.stringify(rb)) failures.push(`FAIL-003 ${harness}/${role}/${tier}/${lane} differs: ${JSON.stringify(ra)} vs ${JSON.stringify(rb)}`);
  }
}
if (n < 100) failures.push('FAIL-004 vacuous: only ' + n + ' comparisons');
if (!withBlock || withBlock.mode !== 'B') failures.push('FAIL-005 shipped routing is not Mode B');
if (failures.length) { for (const f of failures) console.error(f); process.exit(1); }
console.log('COMPARED: ' + n);
NODE
)" || ec=$?
  rm -rf "$scratch"
  echo "$out"
  [[ "$ec" == 0 ]] || log_fail "marker/resolution check failed (exit $ec)"
  assert_payload_line_matches "$out" '^COMPARED: [0-9]+$' "no COMPARED line (vacuous run)"
  [[ "$(/usr/bin/grep -c 'CHANGE-DRAFT-routing-tables-have-an-owner-and-a-seam' "$ROUTING_FILE" || true)" == 0 ]] \
    || log_fail "UPGRADING comment still names the draft id"
  /usr/bin/grep -q 'CHANGE-0192' "$ROUTING_FILE" || log_fail "UPGRADING comment does not name CHANGE-0192"
  log_pass "routing_meta valid, resolution identical with and without it, UPGRADING id corrected (TEST-3660)"
}

test_freshness_check_lapse_and_horizon() {
  CASE_TAG=TEST-3661
  log_info "Test: table-freshness check FRESH/LAPSED and horizon precedence (TEST-3661)..."
  local d out
  d="$(mktemp -d "${TMPDIR:-/tmp}/aai-pricing-3661.XXXXXX")"
  make_tables_root "$d" "2026-10-01T00:00:00Z" "2026-10-01T00:00:00Z"
  out="$(freshness check --root "$d" --now 2026-10-02T00:00:00Z)"
  echo "$out"
  assert_payload_line_matches "$out" '^FRESH \.aai/system/MODEL_ROUTING\.yaml 2026-10-01T00:00:00Z age=1d horizon=30d$' "routing not FRESH"
  assert_payload_line_matches "$out" '^FRESH \.aai/system/PRICING\.yaml 2026-10-01T00:00:00Z age=1d horizon=30d$' "pricing not FRESH"
  assert_payload_line_matches "$out" '^RC=0$' "fresh run did not exit 0"
  # pricing stamp 31 days old
  make_tables_root "$d" "2026-10-01T00:00:00Z" "2026-09-01T00:00:00Z"
  out="$(freshness check --root "$d" --now 2026-10-02T00:00:00Z)"
  echo "$out"
  assert_payload_line_matches "$out" '^LAPSED \.aai/system/PRICING\.yaml 2026-09-01T00:00:00Z age=31d horizon=30d$' "lapse not reported"
  assert_payload_line_matches "$out" '^RC=1$' "lapse did not exit 1"
  # horizon precedence: flag > env > cadence
  out="$(freshness check --root "$d" --now 2026-10-02T00:00:00Z --horizon-days 60)"
  assert_payload_line_matches "$out" '^FRESH \.aai/system/PRICING\.yaml .* horizon=60d$' "--horizon-days 60 did not give FRESH"
  out="$(FRESH_H=60 freshness check --root "$d" --now 2026-10-02T00:00:00Z)"
  assert_payload_line_matches "$out" '^FRESH \.aai/system/PRICING\.yaml .* horizon=60d$' "env 60 did not give FRESH"
  out="$(FRESH_H=60 freshness check --root "$d" --now 2026-10-02T00:00:00Z --horizon-days 10)"
  assert_payload_line_matches "$out" '^LAPSED \.aai/system/PRICING\.yaml .* horizon=10d$' "flag 10 did not beat env 60"
  # usage errors
  local bad
  for bad in 0 abc -3 1.5; do
    out="$(freshness check --root "$d" --now 2026-10-02T00:00:00Z --horizon-days "$bad")"
    assert_payload_line_matches "$out" '^RC=2$' "--horizon-days $bad did not exit 2"
  done
  out="$(FRESH_H=abc freshness check --root "$d" --now 2026-10-02T00:00:00Z)"
  assert_payload_line_matches "$out" '^RC=2$' "env abc did not exit 2"
  rm -rf "$d"
  log_pass "check reports FRESH/LAPSED, flag beats env beats cadence, bad overrides exit 2 (TEST-3661)"
}

test_freshness_check_invalid_and_absent() {
  CASE_TAG=TEST-3662
  log_info "Test: table-freshness check INVALID markers and ABSENT table (TEST-3662)..."
  local d out reason sub pat
  d="$(mktemp -d "${TMPDIR:-/tmp}/aai-pricing-3662.XXXXXX")"
  local now="2026-10-02T00:00:00Z"
  # case: "<routing-file-body>|<expected reason>" built per fixture below
  _inv() { # <label> <reason> <routing body printf-format arg>
    make_tables_root "$d" "2026-10-01T00:00:00Z" "2026-10-01T00:00:00Z"
    printf '%b' "$3" > "$d/.aai/system/MODEL_ROUTING.yaml"
    out="$(freshness check --root "$d" --now "$now")"
    echo "[$1] $out"
    assert_payload_line_matches "$out" "^INVALID \\.aai/system/MODEL_ROUTING\\.yaml $2\$" "$1: no INVALID line with reason '$2'"
    assert_payload_line_matches "$out" '^RC=1$' "$1: did not exit 1"
  }
  _inv no-marker "missing last_updated_utc" 'tiers@claude:\n  standard: x\n'
  _inv bad-month "malformed last_updated_utc" 'routing_meta:\n  last_updated_utc: "2026-13-45T00:00:00Z"\n  cadence_days: 30\n'
  _inv feb-31 "malformed last_updated_utc" 'routing_meta:\n  last_updated_utc: "2026-02-31T00:00:00Z"\n  cadence_days: 30\n'
  _inv cadence-zero "malformed cadence_days" 'routing_meta:\n  last_updated_utc: "2026-10-01T00:00:00Z"\n  cadence_days: 0\n'
  _inv cadence-absent "missing cadence_days" 'routing_meta:\n  last_updated_utc: "2026-10-01T00:00:00Z"\n'
  _inv future "future last_updated_utc" 'routing_meta:\n  last_updated_utc: "2026-10-05T00:00:00Z"\n  cadence_days: 30\n'
  # negative control: a valid unquoted stamp with CRLF is FRESH, not INVALID
  make_tables_root "$d" "2026-10-01T00:00:00Z" "2026-10-01T00:00:00Z"
  printf 'routing_meta:\r\n  last_updated_utc: 2026-10-01T00:00:00Z\r\n  cadence_days: 30\r\n' > "$d/.aai/system/MODEL_ROUTING.yaml"
  out="$(freshness check --root "$d" --now "$now")"
  assert_payload_line_matches "$out" '^FRESH \.aai/system/MODEL_ROUTING\.yaml ' "unquoted CRLF stamp not FRESH"
  # pricing without a marker is INVALID too
  printf 'models:\n  x:\n    input_usd_per_m: 1\n' > "$d/.aai/system/PRICING.yaml"
  out="$(freshness check --root "$d" --now "$now")"
  assert_payload_line_matches "$out" '^INVALID \.aai/system/PRICING\.yaml missing last_updated_utc$' "pricing without marker not INVALID"
  # ABSENT is not a finding
  make_tables_root "$d" "2026-10-01T00:00:00Z" "2026-10-01T00:00:00Z"
  rm -f "$d/.aai/system/MODEL_ROUTING.yaml"
  out="$(freshness check --root "$d" --now "$now")"
  echo "$out"
  assert_payload_line_matches "$out" '^ABSENT \.aai/system/MODEL_ROUTING\.yaml$' "deleted routing not ABSENT"
  assert_payload_line_matches "$out" '^RC=0$' "ABSENT changed the exit code"
  rm -rf "$d"
  log_pass "INVALID names file and reason and exits 1; ABSENT exits 0 (TEST-3662)"
}

# --- stamp guard (Spec-AC-05 / Spec-AC-06) -----------------------------------
# guard_fixture <dir> <routing-stamp|-> <std-id> <pricing-stamp> <input-rate> <alias>
# writes both tables into a scratch git repo. A "-" routing stamp omits the
# routing_meta block (the pre-marker shape).
guard_fixture() {
  local d="$1" rs="$2" std="$3" ps="$4" rate="$5" alias="$6"
  mkdir -p "$d/.aai/system"
  {
    if [[ "$rs" != "-" ]]; then
      printf 'routing_meta:\n  last_updated_utc: "%s"\n  cadence_days: 30\n' "$rs"
    fi
    printf '# a comment\ntiers@claude:\n  mechanical: m1\n  standard: %s\n  premium: p1\nroles@claude:\n  Planning: p1\nvalidation_alternate@claude: p1\neffort_tiers:\n  mechanical: low\n' "$std"
  } > "$d/.aai/system/MODEL_ROUTING.yaml"
  printf 'pricing_meta:\n  last_updated_utc: "%s"\nupdate_policy:\n  cadence_days: 30\nmodels:\n  m1:\n    input_usd_per_m: %s\n    output_usd_per_m: 5\nmodel_aliases:\n  foo: %s\n' "$ps" "$rate" "$alias" > "$d/.aai/system/PRICING.yaml"
}

# guard <dir> <base-rev>: prints output and RC=<n>.
guard() {
  local d="$1" base="$2" out rc=0
  out="$(env -u AAI_ROLE node "$FRESHNESS_SCRIPT" stamp-guard --root "$d" --base "$base" 2>&1)" || rc=$?
  printf '%s\nRC=%s\n' "$out" "$rc"
}

test_stamp_guard_compares_stamped_lines() {
  CASE_TAG=TEST-3665
  log_info "Test: stamp-guard compares id/price lines against a base revision (TEST-3665)..."
  local d out
  d="$(mktemp -d "${TMPDIR:-/tmp}/aai-pricing-3665.XXXXXX")"
  git -C "$d" init -q
  git -C "$d" config user.email t@example.invalid
  git -C "$d" config user.name t
  local S1="2026-11-01T00:00:00Z" S2="2026-11-02T00:00:00Z" S0="2026-10-01T00:00:00Z"
  guard_fixture "$d" "$S1" s1 "$S1" 1 m1
  git -C "$d" add -A && git -C "$d" commit -q -m base
  local base; base="$(git -C "$d" rev-parse HEAD)"
  # unchanged tree
  out="$(guard "$d" "$base")"
  assert_payload_line_matches "$out" '^UNCHANGED \.aai/system/MODEL_ROUTING\.yaml' "identical tree not UNCHANGED (routing)"
  assert_payload_line_matches "$out" '^RC=0$' "identical tree did not exit 0"
  # changed tiers row, same stamp
  guard_fixture "$d" "$S1" s2 "$S1" 1 m1
  out="$(guard "$d" "$base")"
  assert_payload_line_matches "$out" '^VIOLATION \.aai/system/MODEL_ROUTING\.yaml ' "unstamped routing change not VIOLATION"
  assert_payload_line_matches "$out" '^RC=1$' "unstamped routing change did not exit 1"
  # changed row, later stamp
  guard_fixture "$d" "$S2" s2 "$S1" 1 m1
  out="$(guard "$d" "$base")"
  assert_payload_line_matches "$out" '^CHANGED-STAMPED \.aai/system/MODEL_ROUTING\.yaml' "stamped change not CHANGED-STAMPED"
  assert_payload_line_matches "$out" '^RC=0$' "stamped change did not exit 0"
  # comment line, blank line and an effort_params row added, same stamp
  guard_fixture "$d" "$S1" s1 "$S1" 1 m1
  printf '# new comment\n\neffort_params@claude:\n  mechanical: x\n' >> "$d/.aai/system/MODEL_ROUTING.yaml"
  out="$(guard "$d" "$base")"
  assert_payload_line_matches "$out" '^UNCHANGED \.aai/system/MODEL_ROUTING\.yaml' "comment/effort-only change not UNCHANGED"
  assert_payload_line_matches "$out" '^RC=0$' "comment/effort-only change did not exit 0"
  # stamp lowered
  guard_fixture "$d" "$S0" s1 "$S1" 1 m1
  out="$(guard "$d" "$base")"
  assert_payload_line_matches "$out" '^VIOLATION \.aai/system/MODEL_ROUTING\.yaml ' "lowered stamp not VIOLATION"
  assert_payload_line_matches "$out" '^RC=1$' "lowered stamp did not exit 1"
  # malformed head stamp
  guard_fixture "$d" "2026-13-45T00:00:00Z" s1 "$S1" 1 m1
  out="$(guard "$d" "$base")"
  assert_payload_line_matches "$out" '^VIOLATION \.aai/system/MODEL_ROUTING\.yaml ' "malformed head stamp not VIOLATION"
  # PRICING rate change, same stamp
  guard_fixture "$d" "$S1" s1 "$S1" 2 m1
  out="$(guard "$d" "$base")"
  assert_payload_line_matches "$out" '^VIOLATION \.aai/system/PRICING\.yaml ' "unstamped rate change not VIOLATION"
  assert_payload_line_matches "$out" '^RC=1$' "unstamped rate change did not exit 1"
  # PRICING alias change, same stamp
  guard_fixture "$d" "$S1" s1 "$S1" 1 m2
  out="$(guard "$d" "$base")"
  assert_payload_line_matches "$out" '^VIOLATION \.aai/system/PRICING\.yaml ' "unstamped alias change not VIOLATION"
  # PRICING rate change with a later stamp passes
  guard_fixture "$d" "$S1" s1 "$S2" 2 m1
  out="$(guard "$d" "$base")"
  assert_payload_line_matches "$out" '^CHANGED-STAMPED \.aai/system/PRICING\.yaml' "stamped rate change not CHANGED-STAMPED"
  assert_payload_line_matches "$out" '^RC=0$' "stamped rate change did not exit 0"
  # head table deleted while the base has it
  rm -f "$d/.aai/system/MODEL_ROUTING.yaml"
  guard_fixture "$d" "$S1" s1 "$S1" 1 m1; rm -f "$d/.aai/system/MODEL_ROUTING.yaml"
  out="$(guard "$d" "$base")"
  assert_payload_line_matches "$out" '^VIOLATION \.aai/system/MODEL_ROUTING\.yaml ' "deleted head table not VIOLATION"
  # pre-marker base + valid head marker -> RESTAMPED, exit 0
  guard_fixture "$d" "-" s1 "$S1" 1 m1
  git -C "$d" add -A && git -C "$d" commit -q -m premarker
  local pre; pre="$(git -C "$d" rev-parse HEAD)"
  guard_fixture "$d" "$S1" s1 "$S1" 1 m1
  out="$(guard "$d" "$pre")"
  assert_payload_line_matches "$out" '^RESTAMPED \.aai/system/MODEL_ROUTING\.yaml' "pre-marker base with valid head not RESTAMPED"
  assert_payload_line_matches "$out" '^RC=0$' "pre-marker base with valid head did not exit 0"
  # pre-marker base + no head marker -> VIOLATION
  guard_fixture "$d" "-" s1 "$S1" 1 m1
  out="$(guard "$d" "$pre")"
  assert_payload_line_matches "$out" '^VIOLATION \.aai/system/MODEL_ROUTING\.yaml ' "pre-marker base with no head marker not VIOLATION"
  # unresolvable base
  out="$(guard "$d" nosuchref)"
  assert_payload_line_matches "$out" '^RC=2$' "unresolvable base did not exit 2"
  rm -rf "$d"
  log_pass "stamp-guard: changed id/price line needs a later stamp; comments and effort sections ignored; bad base exits 2 (TEST-3665)"
}

# live_guard <upstream-ref>: runs stamp-guard against the merge-base of HEAD and
# <upstream-ref> in this checkout. Fails closed: returns 3 (never 0) when the
# merge-base cannot be computed. Prints the guard output.
live_guard() {
  local up="$1" base
  if ! base="$(git -C "$PROJECT_ROOT" merge-base HEAD "$up" 2>&1)" || [[ -z "$base" ]]; then
    echo "NO-MERGE-BASE: cannot compute merge-base of HEAD and $up ($base); CI must check out with fetch-depth: 0 so origin/main exists"
    return 3
  fi
  env -u AAI_ROLE node "$FRESHNESS_SCRIPT" stamp-guard --root "$PROJECT_ROOT" --base "$base" 2>&1
}

test_live_stamp_guard_and_selector() {
  CASE_TAG=TEST-3666
  log_info "Test: live stamp-guard against the merge-base with origin/main, fail-closed, selector wiring (TEST-3666)..."
  local out rc=0
  # fail-closed branch: an upstream that does not exist must be a nonzero failure
  out="$(live_guard origin/no-such-branch-3666)" || rc=$?
  [[ "$rc" == 3 ]] || log_fail "uncomputable merge-base did not fail closed (rc=$rc): $out"
  assert_payload_line_matches "$out" '^NO-MERGE-BASE: ' "fail-closed branch printed no explanation"
  # live: this tree against origin/main
  rc=0
  out="$(live_guard origin/main)" || rc=$?
  echo "$out"
  [[ "$rc" == 0 ]] || log_fail "live stamp-guard against merge-base of origin/main failed (rc=$rc): changed routed/priced lines need a later stamp. $out"
  assert_payload_line_matches "$out" '^(UNCHANGED|RESTAMPED|CHANGED-STAMPED) \.aai/system/MODEL_ROUTING\.yaml' "live guard printed no routing verdict"
  assert_payload_line_matches "$out" '^(UNCHANGED|RESTAMPED|CHANGED-STAMPED) \.aai/system/PRICING\.yaml' "live guard printed no pricing verdict"
  # selector: each of the three paths selects aai-pricing (never FULL_RUN)
  local f sel
  for f in .aai/system/MODEL_ROUTING.yaml .aai/system/PRICING.yaml .aai/scripts/table-freshness.mjs; do
    sel="$(printf '%s\n' "$f" | node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from - --repo-root "$PROJECT_ROOT" 2>&1)"
    assert_payload_line_matches "$sel" '^SELECTED aai-pricing ' "select-suites does not select aai-pricing for $f"
  done
  log_pass "live stamp-guard passes against origin/main merge-base, fails closed without one, selector maps all three paths (TEST-3666)"
}

# --- routed-id check (Spec-AC-07) ---------------------------------------------
# rt_fixture <dir> <standard-id> <standard-last-verified> <mech-input> <prem-output>
# writes a claude-only routing table (3 tiers, one role, one alternate) and a
# pricing table whose ids m1/s1/p1 are priced and source-referenced.
rt_fixture() {
  local d="$1" std="$2" slv="$3" min="$4" pout="$5"
  mkdir -p "$d/.aai/system"
  printf 'routing_meta:\n  last_updated_utc: "2026-11-13T00:00:00Z"\n  cadence_days: 30\ntiers@claude:\n  mechanical: m1\n  standard: %s\n  premium: p1\nroles@claude:\n  Planning: p1\nvalidation_alternate@claude: p1\n' "$std" > "$d/.aai/system/MODEL_ROUTING.yaml"
  printf 'pricing_meta:\n  last_updated_utc: "2026-11-13T00:00:00Z"\nupdate_policy:\n  cadence_days: 30\nmodels:\n  m1:\n    input_usd_per_m: %s\n    output_usd_per_m: 0.5\n    source_ref: src\n    last_verified_utc: "2026-11-13T09:00:00Z"\n  s1:\n    input_usd_per_m: 2\n    output_usd_per_m: 10\n    source_ref: src\n    last_verified_utc: "%s"\n  p1:\n    input_usd_per_m: 4\n    output_usd_per_m: %s\n    source_ref: src\n    last_verified_utc: "2026-11-13T09:00:00Z"\n' "$min" "$slv" "$pout" > "$d/.aai/system/PRICING.yaml"
}

test_routed_check_statuses() {
  CASE_TAG=TEST-3667
  log_info "Test: table-freshness routed OK/STALE/UNPRICED/MISSING/ORDER/ALLOWED/ALLOW-UNUSED (TEST-3667)..."
  local d out
  d="$(mktemp -d "${TMPDIR:-/tmp}/aai-pricing-3667.XXXXXX")"
  rt_fixture "$d" s1 "2026-11-13T09:00:00Z" 0.1 20
  out="$(freshness routed --root "$d" --since 2026-11-13)"
  echo "$out"
  assert_payload_line_matches "$out" '^OK claude tiers/mechanical m1 2026-11-13T09:00:00Z$' "mechanical row not OK"
  assert_payload_line_matches "$out" '^OK claude roles/Planning p1 ' "role row not OK"
  assert_payload_line_matches "$out" '^OK claude validation_alternate/- p1 ' "validation_alternate row not OK"
  assert_payload_line_matches "$out" '^RC=0$' "all-OK run did not exit 0"
  # STALE: last_verified before --since
  rt_fixture "$d" s1 "2026-11-12T09:00:00Z" 0.1 20
  out="$(freshness routed --root "$d" --since 2026-11-13)"
  assert_payload_line_matches "$out" '^STALE claude tiers/standard s1 2026-11-12T09:00:00Z$' "stale row not reported"
  assert_payload_line_matches "$out" '^RC=1$' "STALE did not exit 1"
  # ALLOWED: the stale id named in --allow-stale
  out="$(freshness routed --root "$d" --since 2026-11-13 --allow-stale s1)"
  assert_payload_line_matches "$out" '^ALLOWED claude tiers/standard s1 ' "listed stale id not ALLOWED"
  assert_payload_line_matches "$out" '^RC=0$' "ALLOWED did not exit 0"
  # ALLOW-UNUSED: a listed id that is not stale
  out="$(freshness routed --root "$d" --since 2026-11-13 --allow-stale s1,m1)"
  assert_payload_line_matches "$out" '^ALLOW-UNUSED m1$' "unused allow id not reported"
  assert_payload_line_matches "$out" '^RC=1$' "ALLOW-UNUSED did not exit 1"
  # UNPRICED: a null rate
  rt_fixture "$d" s1 "2026-11-13T09:00:00Z" 0.1 null
  out="$(freshness routed --root "$d" --since 2026-11-13)"
  assert_payload_line_matches "$out" '^UNPRICED claude tiers/premium p1$' "null rate not UNPRICED"
  assert_payload_line_matches "$out" '^RC=1$' "UNPRICED did not exit 1"
  # MISSING: an id that only prefix-matches a key (no alias, no prefix match)
  rt_fixture "$d" s1-high "2026-11-13T09:00:00Z" 0.1 20
  out="$(freshness routed --root "$d" --since 2026-11-13)"
  assert_payload_line_matches "$out" '^MISSING claude tiers/standard s1-high' "prefix-only id not MISSING"
  assert_payload_line_matches "$out" '^RC=1$' "MISSING did not exit 1"
  # ORDER: mechanical priced above standard
  rt_fixture "$d" s1 "2026-11-13T09:00:00Z" 3 20
  out="$(freshness routed --root "$d" --since 2026-11-13)"
  assert_payload_line_matches "$out" '^ORDER claude mechanical standard$' "inverted tier price not ORDER"
  assert_payload_line_matches "$out" '^RC=1$' "ORDER did not exit 1"
  # usage errors
  out="$(freshness routed --root "$d")"
  assert_payload_line_matches "$out" '^RC=2$' "routed without --since did not exit 2"
  out="$(freshness routed --root "$d" --since 13-11-2026)"
  assert_payload_line_matches "$out" '^RC=2$' "routed with a malformed --since did not exit 2"
  rm -rf "$d"
  log_pass "routed reports OK/STALE/UNPRICED/MISSING/ORDER/ALLOWED/ALLOW-UNUSED with the right exit codes (TEST-3667)"
}

# --- first refresh (Spec-AC-08 / Spec-AC-09) ----------------------------------
# block <file> <start-regex> <end-regex>: the section between two divider lines.
section_block() {
  awk -v s="$2" -v e="$3" '$0 ~ s {on=1} on && $0 ~ e {exit} on {print}' "$1"
}

test_refresh_live_tables() {
  CASE_TAG=TEST-3668
  log_info "Test: shipped tables pass routed --since 2026-11-13 and bind the refreshed ids (TEST-3668)..."
  local out stamps line stamp
  out="$(freshness routed --root "$PROJECT_ROOT" --since 2026-11-13)"
  echo "$out"
  assert_payload_line_matches "$out" '^RC=0$' "shipped tables fail routed --since 2026-11-13"
  assert_payload_line_matches "$out" '^OK claude ' "no claude row checked (vacuous)"
  assert_payload_line_matches "$out" '^OK codex ' "no codex row checked (vacuous)"
  assert_payload_line_matches "$out" '^OK gemini ' "no gemini row checked (vacuous)"
  local bad
  for bad in MISSING UNPRICED ORDER ALLOW-UNUSED STALE ALLOWED; do
    [[ "$out" != *$'\n'"$bad "* && "$out" != "$bad "* ]] || log_fail "routed printed a $bad line on the shipped tables"
  done
  # both stamps on or after the refresh day
  stamps="$(FRESH_H=100000 freshness check --root "$PROJECT_ROOT")"
  assert_payload_line_matches "$stamps" '^RC=0$' "check over the shipped tables failed"
  while IFS= read -r line; do
    if [[ "$line" =~ ^FRESH\ [^\ ]+\ ([^\ ]+)\  ]]; then
      stamp="${BASH_REMATCH[1]}"
      [[ "$stamp" > "2026-11-13T00:00:00Z" || "$stamp" == "2026-11-13T00:00:00Z" ]] || log_fail "stamp $stamp is before the refresh day"
    fi
  done <<< "$stamps"
  # claude binding equals the decision
  local cl
  cl="$(section_block "$ROUTING_FILE" '^# --- claude ---' '^# --- codex ---')"
  local want
  for want in '  mechanical: claude-haiku-5-5' '  standard: claude-sonnet-5-5' '  premium: claude-opus-5-5' \
    '  Planning: claude-opus-5-5' '  Code Review: claude-opus-5-5' '  Metrics Flush: claude-haiku-5-5' \
    '  Validation@lightweight: claude-sonnet-5-5' 'validation_alternate@claude: claude-opus-5-5'; do
    [[ $'\n'"$cl"$'\n' == *$'\n'"$want"$'\n'* ]] || log_fail "claude section lacks the row '$want'"
  done
  [[ -z "$(printf '%s\n' "$cl" | /usr/bin/grep -E 'claude-opus-5([^-0-9]|$)|claude-sonnet-5([^-0-9]|$)|claude-haiku-4-5' | /usr/bin/grep -v '^ *#' || true)" ]] \
    || log_fail "claude section still names a retired id"
  # codex and gemini binding per the refresh decision
  local cx ge
  cx="$(section_block "$ROUTING_FILE" '^# --- codex ---' '^# --- gemini ---')"
  for want in '  mechanical: gpt-6.1-terra' '  standard: gpt-6.1-sol' '  premium: gpt-6-sol' \
    '  Planning: gpt-6-sol' '  Code Review: gpt-6-sol' '  Metrics Flush: gpt-6.1-terra' 'validation_alternate@codex: gpt-6-sol'; do
    [[ $'\n'"$cx"$'\n' == *$'\n'"$want"$'\n'* ]] || log_fail "codex section lacks the row '$want'"
  done
  ge="$(section_block "$ROUTING_FILE" '^# --- gemini ---' '^# --- cursor ---')"
  for want in '  mechanical: gemini-3-flash-preview' '  standard: gemini-3-flash-preview' '  premium: gemini-3.1-pro-preview' \
    '  Planning: gemini-3.1-pro-preview' '  Code Review: gemini-3.1-pro-preview' '  Metrics Flush: gemini-3-flash-preview' 'validation_alternate@gemini: gemini-3.1-pro-preview'; do
    [[ $'\n'"$ge"$'\n' == *$'\n'"$want"$'\n'* ]] || log_fail "gemini section lacks the row '$want'"
  done
  log_pass "shipped tables pass routed --since 2026-11-13, stamps current, claude/codex/gemini bind the refreshed ids (TEST-3668)"
}

test_refresh_dispatch_seam() {
  CASE_TAG=TEST-3669
  log_info "Test: every shipped routed model resolves through the real resolver to itself with rates (TEST-3669)..."
  local out ec=0
  out="$(PROJECT_ROOT="$PROJECT_ROOT" node --input-type=module - <<'NODE' 2>&1
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const root = process.env.PROJECT_ROOT;
const imp = (p) => import(pathToFileURL(path.join(root, p)).href);
const od = await imp('.aai/scripts/orchestration-dispatch.mjs');
const pr = await imp('.aai/scripts/lib/pricing.mjs');
const routing = od.loadModelRouting(root);
const pricing = pr.loadPricing(path.join(root, '.aai/system/PRICING.yaml'));
const failures = [];
let n = 0;
for (const harness of ['claude', 'codex', 'gemini']) {
  for (const role of ['Planning', 'Validation', 'Metrics Flush', 'Code Review', 'Implementation']) {
    for (const tier of ['mechanical', 'standard', 'premium']) {
      for (const lane of ['lightweight', 'full']) {
        const v = { verdict: 'dispatch', role, suggested_tier: tier, harness, lane: { selected: lane } };
        const id = od.suggestModel(v, routing);
        n++;
        if (!id) { failures.push(`FAIL-001 ${harness}/${role}/${tier}/${lane}: no suggested_model`); continue; }
        const key = pr.resolveModelKey(pricing, id);
        const e = pricing.models[key];
        if (key !== id) failures.push(`FAIL-002 ${harness}/${role}: ${id} resolves to ${key}, not itself`);
        else if (!e || typeof e.input !== 'number' || typeof e.output !== 'number') failures.push(`FAIL-003 ${id} has null rates`);
      }
    }
  }
}
if (n < 90) failures.push('FAIL-004 vacuous: ' + n);
if (failures.length) { for (const f of failures) console.error(f); process.exit(1); }
console.log('RESOLVED-ROUTED: ' + n);
NODE
)" || ec=$?
  echo "$out"
  [[ "$ec" == 0 ]] || log_fail "routed model did not resolve to itself with rates (exit $ec)"
  assert_payload_line_matches "$out" '^RESOLVED-ROUTED: [0-9]+$' "no RESOLVED-ROUTED line (vacuous run)"
  log_pass "every routed model on claude, codex and gemini resolves to itself with non-null rates (TEST-3669)"
}

test_refresh_pins() {
  CASE_TAG=TEST-3670
  log_info "Test: the contract pins carry the refreshed claude rates and the dispatch suite pins the refreshed ids (TEST-3670)..."
  local out ec=0
  out="$(run_contract 2>&1)" || ec=$?
  echo "$out"
  [[ "$ec" == 0 ]] || log_fail "pricing contract failed (exit $ec)"
  assert_payload_line_matches "$out" '^CONTRACT: all pricing lookup assertions hold$' "contract did not complete"
  local f="$PROJECT_ROOT/tests/skills/test-aai-orchestration-dispatch.sh" id
  for id in claude-haiku-5-5 claude-sonnet-5-5 claude-opus-5-5 gpt-6.1-sol; do
    /usr/bin/grep -q "$id" "$f" || log_fail "dispatch suite does not pin $id"
  done
  local n
  n="$(/usr/bin/grep -cE '(Metrics Flush|Validation@lightweight|mechanical|standard|premium):\[\[:space:\]\]\*(claude-haiku-4-5|claude-sonnet-5|claude-opus-5)\[\[:space:\]\]' "$f" || true)"
  [[ "$n" == 0 ]] || log_fail "dispatch suite still pins $n retired shipped-file ids"
  n="$(/usr/bin/grep -cE 'suggested_model === "(claude-sonnet-5|gpt-5)"' "$f" || true)"
  [[ "$n" == 0 ]] || log_fail "dispatch suite still pins $n retired shipped-copy ids"
  log_pass "contract pins and dispatch-suite pins carry the refreshed ids (TEST-3670)"
}

test_changelog_entry() {
  CASE_TAG=TEST-3675
  log_info "Test: CHANGELOG carries exactly one routing-table freshness entry naming the seam (TEST-3675)..."
  local cl="$PROJECT_ROOT/CHANGELOG.md" n body
  n="$(/usr/bin/grep -cE '^## \[(unreleased|v[0-9]{4}\.[0-9]{2}\.[0-9]{2})\] — .*routing-table freshness' "$cl" || true)"
  [[ "$n" == 1 ]] || log_fail "CHANGELOG has $n routing-table freshness headings (want exactly 1)"
  body="$(awk '/^## \[(unreleased|v[0-9.]+)\] — .*routing-table freshness/{f=1;next} /^## \[/{f=0} f' "$cl")"
  local w
  for w in CAT-21 routing_meta stamp-guard ROUTING_REFRESH; do
    /usr/bin/grep -qF "$w" <<<"$body" || log_fail "CHANGELOG entry does not name $w"
  done
  log_pass "CHANGELOG carries one routing-table freshness entry naming CAT-21, routing_meta, stamp-guard and ROUTING_REFRESH (TEST-3675)"
}

main() {
  echo "Testing $TEST_NAME (PRICING.yaml lookup contract — CHANGE-0010 TEST-006)"
  check_deps
  test_pricing_contract
  test_routing_marker_and_resolution_unchanged
  test_freshness_check_lapse_and_horizon
  test_freshness_check_invalid_and_absent
  test_stamp_guard_compares_stamped_lines
  test_live_stamp_guard_and_selector
  test_routed_check_statuses
  test_refresh_live_tables
  test_refresh_dispatch_seam
  test_refresh_pins
  test_changelog_entry
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
