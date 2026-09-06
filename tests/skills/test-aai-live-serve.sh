#!/usr/bin/env bash
#
# Test: SPEC live-agent-dashboard-served-locally — a loopback-only HTTP server
# that shows every agent's heartbeat, what waits on the owner, and ages.
# (.aai/scripts/aai-live-serve.mjs), TEST-001..012. The option parser is a
# separate ride (validation round 2 split); TEST-008 pins the free-text fallback.
#
# Fixtures only: heartbeat slots go to a temp --heartbeat-dir, STATE to a temp
# --state, and the transcript scan is disabled with --no-live-status. The server
# must write nothing under the repository (TEST-005 runs the tripwire check).

set -u
TEST_NAME="test-aai-live-serve"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENGINE="$PROJECT_ROOT/.aai/scripts/aai-live-serve.mjs"
HEARTBEAT="$PROJECT_ROOT/.aai/scripts/heartbeat.mjs"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; stop_server; exit 1; }
log_info() { echo "INFO: $*"; }
log_skip() { echo "SKIP: $*"; exit 42; }
command -v node >/dev/null 2>&1 || log_skip "node not found"
command -v curl >/dev/null 2>&1 || log_skip "curl not found"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-live-serve.XXXXXX")"
SERVER_PID=""
PORT=""

cleanup() { stop_server; rm -rf "$TEST_DIR"; }
trap cleanup EXIT

stop_server() {
  # Bounded: an unbounded `wait` would turn a broken SIGINT handler into a hung
  # suite instead of a failed one.
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -INT "$SERVER_PID" 2>/dev/null
    local k=0; while [ "$k" -lt 30 ] && kill -0 "$SERVER_PID" 2>/dev/null; do sleep 0.1; k=$((k+1)); done
    if kill -0 "$SERVER_PID" 2>/dev/null; then kill -9 "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""; echo "FAIL: server ignored SIGINT for 3s and was killed" >&2; exit 1; fi
    wait "$SERVER_PID" 2>/dev/null
  fi
  SERVER_PID=""
}

# A free loopback port: try a random high port until nothing answers on it.
pick_port() {
  local p tries=0
  while [ "$tries" -lt 20 ]; do
    p=$((17000 + RANDOM % 2000))
    if ! curl -s --max-time 1 "http://127.0.0.1:$p/" >/dev/null 2>&1; then echo "$p"; return 0; fi
    tries=$((tries + 1))
  done
  return 1
}

write_state_q() { # $1=required  $2=question body, already indented four spaces
  cat > "$TEST_DIR/STATE.yaml" <<YAML
project_status: active
current_focus:
  type: intake_change
  ref_id: a-ride
human_input:
  required: $1
  question: >-
$2
  blocking_reason: "[HITL-7] waiting for the owner"
YAML
}
start_server_answers() {
  PORT="$(pick_port)" || log_fail "no free port"
  node "$ENGINE" --port "$PORT" --heartbeat-dir "$TEST_DIR/hb" --state "$TEST_DIR/STATE.yaml" --answers "$TEST_DIR/answers.jsonl" --no-live-status \
    > "$TEST_DIR/server.out" 2> "$TEST_DIR/server.err" &
  SERVER_PID=$!
  local i=0; while [ "$i" -lt 30 ]; do curl -s --max-time 1 "http://127.0.0.1:$PORT/data.json" >/dev/null 2>&1 && return 0; sleep 0.2; i=$((i+1)); done
  log_fail "server did not answer on 127.0.0.1:$PORT: $(cat "$TEST_DIR/server.err")"
}
post_answer() { # $1 = raw JSON body -> prints the HTTP status
  curl -s --max-time 3 -o "$TEST_DIR/resp" -w '%{http_code}' -X POST -H 'content-type: application/json' --data "$1" "http://127.0.0.1:$PORT/answer"
}
post_raw() { # $1 = body, rest = extra curl args -> prints the HTTP status
  local body="$1"; shift
  curl -s --max-time 3 -o "$TEST_DIR/resp" -w '%{http_code}' -X POST --data "$body" "$@" "http://127.0.0.1:$PORT/answer"
}
write_state() { # $1=required(true|false) $2=question
  cat > "$TEST_DIR/STATE.yaml" <<YAML
project_status: active
human_input:
  required: $1
  question: $2
  blocking_reason: $([ "$1" = "true" ] && echo "waiting for the owner" || echo null)
YAML
}

start_server() { # extra flags in "$@"
  PORT="$(pick_port)" || log_fail "no free port"
  node "$ENGINE" --port "$PORT" --heartbeat-dir "$TEST_DIR/hb" --state "$TEST_DIR/STATE.yaml" --no-live-status \
    > "$TEST_DIR/server.out" 2> "$TEST_DIR/server.err" "$@" &
  SERVER_PID=$!
  local i=0
  while [ "$i" -lt 30 ]; do
    if curl -s --max-time 1 "http://127.0.0.1:$PORT/data.json" >/dev/null 2>&1; then return 0; fi
    kill -0 "$SERVER_PID" 2>/dev/null || log_fail "server exited early: $(cat "$TEST_DIR/server.err")"
    sleep 0.2; i=$((i + 1))
  done
  log_fail "server did not answer on 127.0.0.1:$PORT within 6s: $(cat "$TEST_DIR/server.err")"
}

json_get() { # $1=json file  $2=js expression over `d`
  node -e 'const d=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); const v=(function(d){return eval(process.argv[2]);})(d); process.stdout.write(v===undefined?"undefined":JSON.stringify(v));' "$1" "$2"
}

# --- TEST-001 (Spec-AC-01): loopback only, one URL line, / and /data.json -----
test_001_loopback_and_routes() {
  log_info "Test: binds loopback, serves / and /data.json, refuses a non-loopback host (TEST-001)..."
  mkdir -p "$TEST_DIR/hb"; write_state false null
  start_server
  local urls; urls="$(grep -c 'http://127.0.0.1' "$TEST_DIR/server.out")"
  [ "$urls" = "1" ] || log_fail "TEST-001: exactly one URL line expected, got $urls: $(cat "$TEST_DIR/server.out")"
  local ct; ct="$(curl -s --max-time 2 -o "$TEST_DIR/index.html" -w '%{http_code} %{content_type}' "http://127.0.0.1:$PORT/")"
  case "$ct" in "200 text/html"*) ;; *) log_fail "TEST-001: GET / must be 200 text/html, got: $ct";; esac
  local dj; dj="$(curl -s --max-time 2 -o "$TEST_DIR/data.json" -w '%{http_code} %{content_type}' "http://127.0.0.1:$PORT/data.json")"
  case "$dj" in "200 application/json"*) ;; *) log_fail "TEST-001: GET /data.json must be 200 application/json, got: $dj";; esac
  stop_server
  # refusal arm: a non-loopback host must exit 2 and open nothing
  local p; p="$(pick_port)"
  # Bounded: a server that IGNORES --host would sit there forever, and that is a
  # failure to report, not a hang to wait through (bash 3.2 has no `timeout`).
  node "$ENGINE" --port "$p" --host 0.0.0.0 --heartbeat-dir "$TEST_DIR/hb" --state "$TEST_DIR/STATE.yaml" --no-live-status \
    > "$TEST_DIR/bad.out" 2> "$TEST_DIR/bad.err" &
  local bpid=$! rc="" j=0
  while [ "$j" -lt 30 ]; do
    if ! kill -0 "$bpid" 2>/dev/null; then wait "$bpid" 2>/dev/null; rc=$?; break; fi
    sleep 0.1; j=$((j+1))
  done
  if [ -z "$rc" ]; then kill "$bpid" 2>/dev/null; wait "$bpid" 2>/dev/null; log_fail "TEST-001: --host 0.0.0.0 must exit promptly with 2; it kept running (a refusal that does not refuse)"; fi
  [ "$rc" = "2" ] || log_fail "TEST-001: --host 0.0.0.0 must exit 2, got $rc"
  grep -qi "loopback" "$TEST_DIR/bad.err" || log_fail "TEST-001: the refusal must name loopback: $(cat "$TEST_DIR/bad.err")"
  curl -s --max-time 1 "http://127.0.0.1:$p/" >/dev/null 2>&1 && log_fail "TEST-001: nothing may listen after a refused bind"
  log_pass "loopback bind, both routes, non-loopback refused (TEST-001)"
}

# --- TEST-002 (Spec-AC-02): roles from heartbeat slots, stale marked ----------
test_002_roles_and_stale() {
  log_info "Test: every heartbeat slot is listed; an old one is stale, not hidden (TEST-002)..."
  rm -rf "$TEST_DIR/hb"; mkdir -p "$TEST_DIR/hb"; write_state false null
  node "$HEARTBEAT" write --ref fresh-ride --role Implementation --message "editing" --dir "$TEST_DIR/hb" >/dev/null 2>&1 \
    || log_fail "TEST-002: heartbeat write (fresh) failed"
  node "$HEARTBEAT" write --ref old-ride --role Validation --message "waiting on sweep" --dir "$TEST_DIR/hb" >/dev/null 2>&1 \
    || log_fail "TEST-002: heartbeat write (old) failed"
  # age the second slot by ten minutes
  node -e '
    const fs=require("fs"),p=require("path"); const dir=process.argv[1];
    for (const n of fs.readdirSync(dir)) { if (!n.includes("old-ride")) continue;
      const f=p.join(dir,n); const d=JSON.parse(fs.readFileSync(f,"utf8"));
      d.updated_at=new Date(Date.now()-600000).toISOString(); fs.writeFileSync(f, JSON.stringify(d)); }' "$TEST_DIR/hb"
  start_server
  curl -s --max-time 2 -o "$TEST_DIR/data.json" "http://127.0.0.1:$PORT/data.json"
  local n; n="$(json_get "$TEST_DIR/data.json" 'd.roles.length')"
  [ "$n" = "2" ] || log_fail "TEST-002: two slots must yield two roles, got $n"
  local fresh old
  fresh="$(json_get "$TEST_DIR/data.json" 'd.roles.find(r=>r.ref_id==="fresh-ride").stale')"
  old="$(json_get "$TEST_DIR/data.json" 'd.roles.find(r=>r.ref_id==="old-ride").stale')"
  [ "$fresh" = "false" ] || log_fail "TEST-002: a fresh slot must not be stale (got $fresh)"
  [ "$old" = "true" ] || log_fail "TEST-002: a 10-minute-old slot must be stale (got $old)"
  local msg; msg="$(json_get "$TEST_DIR/data.json" 'd.roles.find(r=>r.ref_id==="old-ride").message')"
  [ "$msg" = '"waiting on sweep"' ] || log_fail "TEST-002: the slot message must pass through, got $msg"
  stop_server
  log_pass "roles listed from heartbeat, stale marked not hidden (TEST-002)"
}

# --- TEST-003 (Spec-AC-03): what waits on the owner comes first ---------------
test_003_waiting_first() {
  log_info "Test: a pending human_input is first; none -> null and the one-line message (TEST-003)..."
  rm -rf "$TEST_DIR/hb"; mkdir -p "$TEST_DIR/hb"
  node "$HEARTBEAT" write --ref r --role Planning --message "m" --dir "$TEST_DIR/hb" >/dev/null 2>&1
  write_state true '"Merge PR 999 or hold?"'
  start_server
  curl -s --max-time 2 -o "$TEST_DIR/data.json" "http://127.0.0.1:$PORT/data.json"
  curl -s --max-time 2 -o "$TEST_DIR/index.html" "http://127.0.0.1:$PORT/"
  local q; q="$(json_get "$TEST_DIR/data.json" 'd.waiting && d.waiting.question')"
  [ "$q" = '"Merge PR 999 or hold?"' ] || log_fail "TEST-003: waiting.question must carry the STATE question, got $q"
  json_get "$TEST_DIR/data.json" 'typeof d.waiting.since' | grep -q '"string"' || log_fail "TEST-003: waiting.since must be present"
  # in the HTML the waiting block precedes the roles block
  local wpos rpos
  wpos="$(grep -n 'id="waiting"' "$TEST_DIR/index.html" | head -1 | cut -d: -f1)"
  rpos="$(grep -n 'id="roles"' "$TEST_DIR/index.html" | head -1 | cut -d: -f1)"
  [ -n "$wpos" ] && [ -n "$rpos" ] || log_fail "TEST-003: HTML must have #waiting and #roles sections"
  [ "$wpos" -lt "$rpos" ] || log_fail "TEST-003: #waiting must precede #roles (waiting at $wpos, roles at $rpos)"
  stop_server
  # the shape the REAL writer emits (state.mjs set-human-input): a folded block scalar
  cat > "$TEST_DIR/STATE.yaml" <<'YAML'
project_status: active
human_input:
  required: true
  question: >-
    Merge PR 999,
    or hold it?
  blocking_reason: >-
    waiting for the owner
updated_at_utc: 2026-09-05T00:00:00Z
YAML
  start_server
  curl -s --max-time 2 -o "$TEST_DIR/data3.json" "http://127.0.0.1:$PORT/data.json"
  local fq; fq="$(json_get "$TEST_DIR/data3.json" 'd.waiting && d.waiting.question')"
  [ "$fq" = '"Merge PR 999, or hold it?"' ] || log_fail "TEST-003: a folded block scalar (what state.mjs writes) must read as one line, got $fq"
  stop_server
  write_state false null
  start_server
  curl -s --max-time 2 -o "$TEST_DIR/data2.json" "http://127.0.0.1:$PORT/data.json"
  [ "$(json_get "$TEST_DIR/data2.json" 'd.waiting')" = "null" ] || log_fail "TEST-003: with required:false, waiting must be null"
  curl -s --max-time 2 "http://127.0.0.1:$PORT/" | grep -qi "nothing waits on you" || log_fail "TEST-003: the no-wait one-liner must be in the page"
  stop_server
  log_pass "waiting-on-you first; absent -> null and the one-liner (TEST-003)"
}

# --- TEST-004 (Spec-AC-04): the page polls and survives a dead server ---------
test_004_page_polls_and_survives() {
  log_info "Test: page polls /data.json every 5s and keeps last data when the server dies (TEST-004)..."
  mkdir -p "$TEST_DIR/hb"; write_state false null
  start_server
  curl -s --max-time 2 -o "$TEST_DIR/index.html" "http://127.0.0.1:$PORT/"
  grep -q "setInterval" "$TEST_DIR/index.html" || log_fail "TEST-004: the page must poll (setInterval)"
  grep -qE "5000" "$TEST_DIR/index.html" || log_fail "TEST-004: the poll interval must be 5000 ms"
  grep -q "/data.json" "$TEST_DIR/index.html" || log_fail "TEST-004: the page must poll /data.json"
  grep -qi "stale since" "$TEST_DIR/index.html" || log_fail "TEST-004: the page must carry the stale-since marker for failed polls"
  grep -qi "last refresh" "$TEST_DIR/index.html" || log_fail "TEST-004: the page must show its last refresh time"
  stop_server
  curl -s --max-time 1 "http://127.0.0.1:$PORT/data.json" >/dev/null 2>&1 && log_fail "TEST-004: the server must be down after stop"
  log_pass "page polls at 5s, shows last refresh, marks stale on failure (TEST-004)"
}

# --- TEST-005 (Spec-AC-05): the server writes nothing under the repository ----
test_005_no_repo_writes() {
  log_info "Test: a serve+poll cycle WITH live-status enabled leaves the repository untouched (TEST-005)..."
  mkdir -p "$TEST_DIR/hb"; write_state false null
  # `git status --porcelain` is blind to gitignored paths, and the one path this
  # server could write (the live-status index cache) IS gitignored. So: a marker
  # file, then every file under the repo newer than it — .git excluded.
  local marker="$TEST_DIR/marker"; : > "$marker"; sleep 1
  PORT="$(pick_port)" || log_fail "no free port"
  node "$ENGINE" --port "$PORT" --heartbeat-dir "$TEST_DIR/hb" --state "$TEST_DIR/STATE.yaml" --live-status-interval 1 \
    > "$TEST_DIR/server.out" 2> "$TEST_DIR/server.err" &
  SERVER_PID=$!
  local i=0; while [ "$i" -lt 60 ]; do curl -s --max-time 2 "http://127.0.0.1:$PORT/data.json" >/dev/null 2>&1 && break; sleep 0.2; i=$((i+1)); done
  i=0; while [ "$i" -lt 3 ]; do curl -s --max-time 25 "http://127.0.0.1:$PORT/data.json" >/dev/null; sleep 1.2; i=$((i+1)); done
  curl -s --max-time 2 "http://127.0.0.1:$PORT/" >/dev/null
  stop_server
  # tests/skills/results/ is the framework's own sink: a concurrent sweep writes
  # there and it is not a path this server can reach. Everything else counts.
  local newer; newer="$(find "$PROJECT_ROOT" -newer "$marker" -type f -not -path '*/.git/*' -not -path '*/tests/skills/results/*' 2>/dev/null)"
  [ -z "$newer" ] || log_fail "TEST-005: the server wrote under the repository (live-status enabled):
$newer"
  log_pass "no repository writes, live-status enabled, ignored paths included (TEST-005)"
}

# --- TEST-006 (Spec-AC-06): SIGINT exits 0 promptly, no orphan ---------------
test_006_sigint_clean() {
  log_info "Test: SIGINT -> exit 0 within 2s, no orphaned child (TEST-006)..."
  mkdir -p "$TEST_DIR/hb"; write_state false null
  start_server
  local pid="$SERVER_PID"
  kill -INT "$pid"
  local i=0 rc=""
  while [ "$i" -lt 20 ]; do
    if ! kill -0 "$pid" 2>/dev/null; then wait "$pid" 2>/dev/null; rc=$?; break; fi
    sleep 0.1; i=$((i+1))
  done
  SERVER_PID=""
  [ -n "$rc" ] || log_fail "TEST-006: server still alive 2s after SIGINT"
  [ "$rc" = "0" ] || log_fail "TEST-006: SIGINT must exit 0, got $rc"
  # After exit a child would be re-parented to 1, so ppid==pid can never match;
  # look for a survivor by its arguments instead (the server passes TEST_DIR).
  local orphans; orphans="$(ps -A -o pid=,command= 2>/dev/null | grep -F "$TEST_DIR" | grep -v grep | wc -l | tr -d ' ')"
  [ "$orphans" = "0" ] || log_fail "TEST-006: $orphans process(es) carrying $TEST_DIR survived the server"
  log_pass "SIGINT exits 0 promptly with no orphan (TEST-006)"
}

# --- TEST-007: escaping is applied at render, and /data.json is never frozen ----
# Mutations "esc removed" and "cache /data.json forever" both survived the first
# six cases. The page is client-rendered, so the escape is proven by extracting
# the page's own `esc` and running it; freshness by writing a heartbeat BETWEEN
# two polls.
test_007_escape_and_freshness() {
  log_info "Test: the page's esc() neutralises script/quotes; a new heartbeat shows on the next poll (TEST-007)..."
  rm -rf "$TEST_DIR/hb"; mkdir -p "$TEST_DIR/hb"; write_state false null
  node "$HEARTBEAT" write --ref r1 --role Planning --message '<script>alert(1)</script>"x' --dir "$TEST_DIR/hb" >/dev/null 2>&1
  start_server
  curl -s --max-time 2 -o "$TEST_DIR/index.html" "http://127.0.0.1:$PORT/"
  local escd; escd="$(node -e '
    const html=require("fs").readFileSync(process.argv[1],"utf8");
    // the entity map inside esc() contains ";" so the match must run to the closing "[c]));"
    const m=/const esc=(s=>[\s\S]*?\[c\]\)\));/.exec(html); if(!m){process.stdout.write("NO_ESC");process.exit(0);}
    const esc=eval(m[1]); process.stdout.write(esc("<script>alert(1)</script>\"x"));' "$TEST_DIR/index.html")"
  case "$escd" in *"<script>"*|*'"x'*|NO_ESC) log_fail "TEST-007: esc() must neutralise < > and quotes, got: $escd";; esac
  case "$escd" in *"&lt;script&gt;"*) ;; *) log_fail "TEST-007: esc() must entity-encode, got: $escd";; esac
  grep -q 'innerHTML=' "$TEST_DIR/index.html" || log_fail "TEST-007: expected innerHTML render sinks in the page"
  local sinks unesc; sinks="$(grep -o "innerHTML=[^;]*" "$TEST_DIR/index.html" | grep -c "esc(")"; unesc="$(grep -o "innerHTML=[^;]*" "$TEST_DIR/index.html" | grep -v "esc(" | grep -vc "map(esc)")"
  [ "$unesc" = "0" ] || log_fail "TEST-007: $unesc innerHTML sink(s) render without esc()"
  # freshness
  curl -s --max-time 2 -o "$TEST_DIR/d1.json" "http://127.0.0.1:$PORT/data.json"
  node "$HEARTBEAT" write --ref r2 --role Validation --message "arrived later" --dir "$TEST_DIR/hb" >/dev/null 2>&1
  curl -s --max-time 2 -o "$TEST_DIR/d2.json" "http://127.0.0.1:$PORT/data.json"
  local n1 n2; n1="$(json_get "$TEST_DIR/d1.json" 'd.roles.length')"; n2="$(json_get "$TEST_DIR/d2.json" 'd.roles.length')"
  [ "$n1" = "1" ] && [ "$n2" = "2" ] || log_fail "TEST-007: a heartbeat written between polls must appear on the next poll (got $n1 then $n2)"
  stop_server
  log_pass "escaping proven on the page's own esc(); /data.json is fresh per poll (TEST-007)"
}

# --- TEST-008 (Spec-AC-01, narrowed by the split): the free-text box, always ---
# The option parser left this scope (validation round 2). What remains is D5's
# documented fallback: `options` is always empty and the page always offers the
# free-text box. Asserted on the RENDERED block, not on the static template —
# the input is in the template whether or not anything pends, so grepping the
# page source would pass with `waiting: null`.
test_008_free_text_always() {
  log_info "Test: a pending decision renders the free-text box; this scope ships no menu (TEST-008)..."
  mkdir -p "$TEST_DIR/hb"; : > "$TEST_DIR/answers.jsonl"
  write_state_q true "    Merge PR 999 or hold?
    - hold it
    - merge now (recommended)"
  start_server_answers
  curl -s --max-time 2 -o "$TEST_DIR/data.json" "http://127.0.0.1:$PORT/data.json"
  [ "$(json_get "$TEST_DIR/data.json" 'd.waiting.options.length')" = "0" ] \
    || log_fail "TEST-008: this scope ships no parsed options — the parser is a separate ride: $(cat "$TEST_DIR/data.json")"
  [ "$(json_get "$TEST_DIR/data.json" 'd.waiting.token')" = '"HITL-7"' ] || log_fail "TEST-008: the [HITL-n] stamp must reach the page"
  [ "$(json_get "$TEST_DIR/data.json" 'd.waiting.ref')" = '"a-ride"' ] || log_fail "TEST-008: the focus ref must reach the page"
  curl -s --max-time 2 -o "$TEST_DIR/index.html" "http://127.0.0.1:$PORT/"
  node -e '
    const fs=require("fs");
    const html=fs.readFileSync(process.argv[1],"utf8");
    const d=JSON.parse(fs.readFileSync(process.argv[2],"utf8"));
    const m=/function render\(d\)\{([\s\S]*?)\n\}/.exec(html);
    if(!m){console.error("render() not found");process.exit(1);}
    const el=(id)=>({id,className:"",set innerHTML(v){this._h=v;},get innerHTML(){return this._h||"";},set textContent(v){this._h=v;},get textContent(){return this._h||"";},hidden:false,querySelector:()=>null});
    const store={};
    global.document={getElementById:(id)=>(store[id]=store[id]||el(id)),querySelector:()=>null};
    const esc=(s)=>String(s==null?"":s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;"}[c]));
    const ago=(s)=>s+" s";
    new Function("d","esc","ago","document", m[1])(d, esc, ago, global.document);
    const w=(store["waiting-body"]||{}).innerHTML||"";
    if(!/id="answer-text"/.test(w)){console.error("no free-text box in the rendered waiting block: "+w.slice(0,200));process.exit(1);}
    if(/class="opt/.test(w)){console.error("this scope must render NO option buttons: "+w.slice(0,200));process.exit(1);}
  ' "$TEST_DIR/index.html" "$TEST_DIR/data.json" \
    || log_fail "TEST-008: the rendered waiting block must carry the free-text box and no option buttons"
  stop_server
  log_pass "the free-text box always renders; no menu in this scope (TEST-008)"
}

# --- TEST-009 (Spec-AC-02/04/06): the write surface refuses more than it accepts
test_009_answer_write_surface() {
  log_info "Test: POST /answer records one line and refuses malformed/empty/oversized/mismatched/no-pending (TEST-009)..."
  mkdir -p "$TEST_DIR/hb"; : > "$TEST_DIR/answers.jsonl"
  write_state_q true "    Merge or hold?
    - hold"
  start_server_answers
  [ "$(post_answer '{"token":"HITL-7","ref":"a-ride","answer":"hold"}')" = "200" ] \
    || log_fail "TEST-009: a valid answer must be 200: $(cat "$TEST_DIR/resp")"
  [ "$(wc -l < "$TEST_DIR/answers.jsonl" | tr -d ' ')" = "1" ] || log_fail "TEST-009: exactly one record must be appended"
  grep -q '"source":"local-dashboard"' "$TEST_DIR/answers.jsonl" || log_fail "TEST-009: the record must name its source"
  # AC-002: the 200 ECHOES what it recorded — an empty 200 tells the operator
  # nothing about what the loop will actually see.
  [ "$(json_get "$TEST_DIR/resp" 'd.recorded.answer')" = '"hold"' ] \
    || log_fail "TEST-009: the 200 must echo the recorded answer, got $(cat "$TEST_DIR/resp")"
  [ "$(json_get "$TEST_DIR/resp" 'd.recorded.token')" = '"HITL-7"' ] \
    || log_fail "TEST-009: the 200 must echo the recorded token, got $(cat "$TEST_DIR/resp")"
  local before; before="$(cksum "$TEST_DIR/answers.jsonl")"
  [ "$(post_answer 'not json')" = "400" ] || log_fail "TEST-009: a malformed body must be 400"
  [ "$(post_answer '{"answer":"   "}')" = "400" ] || log_fail "TEST-009: an empty answer must be 400"
  local big; big="$(node -e 'process.stdout.write(JSON.stringify({answer:"x".repeat(5000)}))')"
  [ "$(post_answer "$big")" = "400" ] || log_fail "TEST-009: an oversized answer must be 400"
  [ "$(post_answer '{"token":"HITL-99","answer":"x"}')" = "400" ] || log_fail "TEST-009: a mismatched token must be 400"
  [ "$(post_answer '{"ref":"other-ride","answer":"x"}')" = "400" ] || log_fail "TEST-009: a mismatched ref must be 400"
  [ "$before" = "$(cksum "$TEST_DIR/answers.jsonl")" ] || log_fail "TEST-009: a refused answer must append NOTHING"
  # control/bidi characters are stripped on store, exactly as a GitHub reply body is
  local dirty; dirty="$(node -e 'process.stdout.write(JSON.stringify({answer:"a"+String.fromCharCode(9)+String.fromCharCode(0x202e)+"b"}))')"
  post_answer "$dirty" >/dev/null
  grep -q '"answer":"a b"' "$TEST_DIR/answers.jsonl" \
    || log_fail "TEST-009: control/bidi chars must be stripped on store: $(tail -1 "$TEST_DIR/answers.jsonl")"
  stop_server
  write_state false null
  start_server_answers
  local before409; before409="$(cksum "$TEST_DIR/answers.jsonl")"
  [ "$(post_answer '{"answer":"x"}')" = "409" ] || log_fail "TEST-009: with nothing pending the answer must be 409, got $(cat "$TEST_DIR/resp")"
  [ "$before409" = "$(cksum "$TEST_DIR/answers.jsonl")" ] || log_fail "TEST-009: a 409 must append NOTHING"
  stop_server
  log_pass "one record on success; malformed/empty/oversized/mismatched refused; 409 when nothing pends (TEST-009)"
}

# --- TEST-010 (Spec-AC-07): the answer cycle leaves the repository alone ------
test_010_answer_cycle_no_repo_writes() {
  log_info "Test: a full answer cycle writes only the gitignored sidecar (TEST-010)..."
  mkdir -p "$TEST_DIR/hb"; : > "$TEST_DIR/answers.jsonl"
  write_state_q true "    Decide
    - yes"
  local marker="$TEST_DIR/marker2"; : > "$marker"; sleep 1
  start_server_answers
  post_answer '{"answer":"yes"}' >/dev/null
  stop_server
  local newer; newer="$(find "$PROJECT_ROOT" -newer "$marker" -type f -not -path '*/.git/*' -not -path '*/tests/skills/results/*' 2>/dev/null)"
  [ -z "$newer" ] || log_fail "TEST-010: the answer cycle wrote under the repository:
$newer"
  [ "$(wc -l < "$TEST_DIR/answers.jsonl" | tr -d ' ')" = "1" ] || log_fail "TEST-010: the answer must be recorded in the fixture sidecar"
  log_pass "the answer cycle writes only its gitignored sidecar (TEST-010)"
}

# --- TEST-011 (code review B1): the browser can reach 127.0.0.1, so loopback is
# not a guard. A cross-site POST must be refused BEFORE anything is recorded.
test_011_csrf_guards() {
  log_info "Test: cross-site POST /answer is refused on content-type, Origin, Sec-Fetch-Site and Host (TEST-011)..."
  mkdir -p "$TEST_DIR/hb"; : > "$TEST_DIR/answers.jsonl"
  write_state_q true "    Merge or hold?
    - hold"
  start_server_answers
  local before; before="$(cksum "$TEST_DIR/answers.jsonl")"
  # 1. a CORS-safelisted content-type needs no preflight — this is the live exploit
  [ "$(post_raw '{"answer":"pwned"}' -H 'content-type: text/plain')" = "415" ] \
    || log_fail "TEST-011: text/plain must be refused 415 (it is CORS-safelisted, so it reaches us cross-site): $(cat "$TEST_DIR/resp")"
  [ "$(post_raw 'answer=pwned' -H 'content-type: application/x-www-form-urlencoded')" = "415" ] \
    || log_fail "TEST-011: a form content-type must be refused 415"
  [ "$(post_raw '{"answer":"pwned"}')" = "415" ] || log_fail "TEST-011: no content-type must be refused 415"
  # 2. a foreign Origin
  [ "$(post_raw '{"answer":"pwned"}' -H 'content-type: application/json' -H 'origin: https://evil.example')" = "403" ] \
    || log_fail "TEST-011: a cross-site Origin must be refused 403: $(cat "$TEST_DIR/resp")"
  # 3. Sec-Fetch-Site the browser attaches on a cross-site request
  [ "$(post_raw '{"answer":"pwned"}' -H 'content-type: application/json' -H 'sec-fetch-site: cross-site')" = "403" ] \
    || log_fail "TEST-011: Sec-Fetch-Site cross-site must be refused 403"
  # 4. DNS rebinding: a non-loopback Host is not this server
  [ "$(post_raw '{"answer":"pwned"}' -H 'content-type: application/json' -H 'host: evil.example')" = "403" ] \
    || log_fail "TEST-011: a non-loopback Host must be refused 403"
  [ "$before" = "$(cksum "$TEST_DIR/answers.jsonl")" ] || log_fail "TEST-011: a refused cross-site POST must append NOTHING"
  # only POST reaches the handler at all
  local meth
  for meth in GET PUT DELETE PATCH; do
    local code; code="$(curl -s --max-time 3 -o /dev/null -w '%{http_code}' -X "$meth" -H 'content-type: application/json' --data '{"answer":"x"}' "http://127.0.0.1:$PORT/answer")"
    [ "$code" = "404" ] || log_fail "TEST-011: $meth /answer must not reach the write handler (got $code)"
  done
  [ "$before" = "$(cksum "$TEST_DIR/answers.jsonl")" ] || log_fail "TEST-011: a non-POST method must append NOTHING"
  # a non-string answer is refused, never coerced ("[object Object]" was recorded)
  [ "$(post_answer '{"answer":{}}')" = "400" ] || log_fail "TEST-011: an object answer must be 400, not coerced"
  [ "$(post_answer '{"answer":["x"]}')" = "400" ] || log_fail "TEST-011: an array answer must be 400, not coerced"
  [ "$(post_answer '{"answer":123}')" = "400" ] || log_fail "TEST-011: a numeric answer must be 400, not coerced"
  [ "$before" = "$(cksum "$TEST_DIR/answers.jsonl")" ] || log_fail "TEST-011: a coerced-type refusal must append NOTHING"
  # and the page's OWN request still works, with the headers a browser sends
  [ "$(post_raw '{"answer":"hold"}' -H 'content-type: application/json' -H "origin: http://127.0.0.1:$PORT" -H 'sec-fetch-site: same-origin')" = "200" ] \
    || log_fail "TEST-011: the page's own same-origin request must still be accepted: $(cat "$TEST_DIR/resp")"
  [ "$(wc -l < "$TEST_DIR/answers.jsonl" | tr -d ' ')" = "1" ] || log_fail "TEST-011: exactly the legitimate answer must be recorded"
  stop_server
  log_pass "cross-site POSTs refused on four independent grounds; the page's own request unaffected (TEST-011)"
}

# --- TEST-012 (fu-live-page-blind-to-the-sweep): the page can see the sweep ---
# The longest job in the factory is the full test sweep, and the page could not
# see it: it lists heartbeat slots and the runner writes none. The operator asked
# three times in one session whether anything was running. The framework already
# writes one <suite>.result per finished suite, so this is a read, not plumbing.
test_012_sweep_progress() {
  log_info "Test: the page reports sweep progress from the results directory, and never invents a total (TEST-012)..."
  mkdir -p "$TEST_DIR/hb"; : > "$TEST_DIR/answers.jsonl"; write_state false null
  local rd="$TEST_DIR/results/test-20260906-000000"; rm -rf "$TEST_DIR/results"; mkdir -p "$rd"
  printf 'PASS\n' > "$rd/alpha.result"; printf 'PASS\n' > "$rd/beta.result"; printf 'FAIL\n' > "$rd/gamma.result"
  # a real run directory also holds logs; only .result files are suite verdicts,
  # and a log named FAIL-ish must not inflate either counter
  printf 'FAIL somewhere in the log text\n' > "$rd/gamma.log"; printf 'x\n' > "$rd/summary.txt"
  # the verdict is the first word of the file and nothing else: a SKIP whose
  # body mentions failure is a skip, not a failure
  printf 'SKIP\nnot run because an earlier FAIL blocked it\n' > "$rd/delta.result"
  # <suite>.log appears when a suite STARTS; six started, four finished
  for n in alpha beta gamma delta epsilon zeta; do printf 'log\n' > "$rd/$n.log"; done
  PORT="$(pick_port)" || log_fail "no free port"
  node "$ENGINE" --port "$PORT" --heartbeat-dir "$TEST_DIR/hb" --state "$TEST_DIR/STATE.yaml" \
    --answers "$TEST_DIR/answers.jsonl" --results-dir "$TEST_DIR/results" --no-live-status \
    > "$TEST_DIR/server.out" 2> "$TEST_DIR/server.err" &
  SERVER_PID=$!
  local i=0; while [ "$i" -lt 30 ]; do curl -s --max-time 1 "http://127.0.0.1:$PORT/data.json" >/dev/null 2>&1 && break; sleep 0.2; i=$((i+1)); done
  curl -s --max-time 2 -o "$TEST_DIR/sw.json" "http://127.0.0.1:$PORT/data.json"
  [ "$(json_get "$TEST_DIR/sw.json" 'd.sweep.done')" = "4" ] \
    || log_fail "TEST-012: the four .result files must count as four done: $(cat "$TEST_DIR/sw.json")"
  [ "$(json_get "$TEST_DIR/sw.json" 'd.sweep.failed')" = "1" ] || log_fail "TEST-012: exactly the FAIL .result counts as failed, logs must not inflate it"
  [ "$(json_get "$TEST_DIR/sw.json" 'd.sweep.started')" = "6" ] \
    || log_fail "TEST-012: started must count .log files, six of them: $(cat "$TEST_DIR/sw.json")"
  [ "$(json_get "$TEST_DIR/sw.json" 'd.sweep.run')" = '"test-20260906-000000"' ] || log_fail "TEST-012: the run directory must be named"
  [ "$(json_get "$TEST_DIR/sw.json" 'd.sweep.active')" = "true" ] || log_fail "TEST-012: a run whose newest result is seconds old must read as active"
  # a total is NOT invented: nothing publishes the expected suite count
  [ "$(json_get "$TEST_DIR/sw.json" 'd.sweep.total')" = "undefined" ] \
    || log_fail "TEST-012: the page must not invent an expected total, got $(json_get "$TEST_DIR/sw.json" 'd.sweep.total')"
  # an old run reads as not active, and is still reported rather than hidden
  node -e 'const fs=require("fs"),p=require("path");const d=process.argv[1];const t=new Date(Date.now()-3600e3);for(const n of fs.readdirSync(d))fs.utimesSync(p.join(d,n),t,t);fs.utimesSync(d,t,t);' "$rd"
  curl -s --max-time 2 -o "$TEST_DIR/sw2.json" "http://127.0.0.1:$PORT/data.json"
  [ "$(json_get "$TEST_DIR/sw2.json" 'd.sweep.active')" = "false" ] || log_fail "TEST-012: an hour-old run must not read as active"
  [ "$(json_get "$TEST_DIR/sw2.json" 'd.sweep.done')" = "4" ] || log_fail "TEST-012: an inactive run must still be REPORTED, never hidden"
  stop_server
  # a run that has JUST started has no .result yet: it is active all the same,
  # dated by its own directory. Found against a real sweep, where a 40-second-old
  # run reported inactive — the exact blindness this panel removes.
  local nd="$TEST_DIR/results/test-20260906-999999"; mkdir -p "$nd"
  PORT="$(pick_port)" || log_fail "no free port"
  node "$ENGINE" --port "$PORT" --heartbeat-dir "$TEST_DIR/hb" --state "$TEST_DIR/STATE.yaml" \
    --answers "$TEST_DIR/answers.jsonl" --results-dir "$TEST_DIR/results" --no-live-status \
    > "$TEST_DIR/server.out" 2> "$TEST_DIR/server.err" &
  SERVER_PID=$!
  i=0; while [ "$i" -lt 30 ]; do curl -s --max-time 1 "http://127.0.0.1:$PORT/data.json" >/dev/null 2>&1 && break; sleep 0.2; i=$((i+1)); done
  curl -s --max-time 2 -o "$TEST_DIR/sw4.json" "http://127.0.0.1:$PORT/data.json"
  [ "$(json_get "$TEST_DIR/sw4.json" 'd.sweep.run')" = '"test-20260906-999999"' ] \
    || log_fail "TEST-012: the newest run wins even with no results yet: $(cat "$TEST_DIR/sw4.json")"
  [ "$(json_get "$TEST_DIR/sw4.json" 'd.sweep.active')" = "true" ] \
    || log_fail "TEST-012: a just-started run with no .result yet must read as ACTIVE"
  [ "$(json_get "$TEST_DIR/sw4.json" 'd.sweep.started')" = "0" ] \
    || log_fail "TEST-012: an empty run directory has started=0"
  [ "$(json_get "$TEST_DIR/sw4.json" 'd.sweep.done')" = "0" ] \
    || log_fail "TEST-012: a just-started run has done=0, not a fabricated count"
  [ "$(json_get "$TEST_DIR/sw4.json" 'd.sweep.last_age_seconds')" = "null" ] \
    || log_fail "TEST-012: with no result yet there is no newest-result age to report"
  stop_server; rm -rf "$nd"
  # A STRAY FILE named test-… must not blank the panel, and must be NAMED.
  # statSync succeeds on a file, and the readdir that follows throws ENOTDIR —
  # which used to return a bare null the page rendered as the confident
  # "No sweep run on disk." while real runs sat right next to it.
  : > "$TEST_DIR/results/test-stray.txt"
  PORT="$(pick_port)" || log_fail "no free port"
  node "$ENGINE" --port "$PORT" --heartbeat-dir "$TEST_DIR/hb" --state "$TEST_DIR/STATE.yaml" \
    --answers "$TEST_DIR/answers.jsonl" --results-dir "$TEST_DIR/results" --no-live-status \
    > "$TEST_DIR/server.out" 2> "$TEST_DIR/server.err" &
  SERVER_PID=$!
  i=0; while [ "$i" -lt 30 ]; do curl -s --max-time 1 "http://127.0.0.1:$PORT/data.json" >/dev/null 2>&1 && break; sleep 0.2; i=$((i+1)); done
  curl -s --max-time 2 -o "$TEST_DIR/sw5.json" "http://127.0.0.1:$PORT/data.json"
  [ "$(json_get "$TEST_DIR/sw5.json" 'd.sweep.run')" = '"test-20260906-000000"' ] \
    || log_fail "TEST-012: a stray file named test-… must not hide the real run: $(cat "$TEST_DIR/sw5.json")"
  grep -q 'test-stray.txt' "$TEST_DIR/sw5.json" \
    || log_fail "TEST-012: the ignored stray must be NAMED in degraded, never dropped silently"
  rm -f "$TEST_DIR/results/test-stray.txt"
  # A FINISHED run says so at once. summary.txt gains its Total line only when
  # the run ends, so a run whose last suite landed seconds ago reads finished
  # rather than staying `running` for the rest of the stale window.
  # VACUOUS ARM, caught by round-two review: the arm above aged this run by an
  # hour, so `active:false` held for the age alone and the assertion said
  # nothing about `complete` — dropping `!complete &&` from the engine left the
  # test PASSING. Make the run fresh first, so only `complete` can explain it.
  touch "$rd"/*.result "$rd"
  printf 'AAI Skills Test Summary\n\nResults:\n--------\nTotal:   4\nPassed:  3\n' > "$rd/summary.txt"
  curl -s --max-time 2 -o "$TEST_DIR/sw6.json" "http://127.0.0.1:$PORT/data.json"
  [ "$(json_get "$TEST_DIR/sw6.json" 'd.sweep.complete')" = "true" ] \
    || log_fail "TEST-012: a run whose summary carries a Total line is complete: $(cat "$TEST_DIR/sw6.json")"
  [ "$(json_get "$TEST_DIR/sw6.json" 'd.sweep.active')" = "false" ] \
    || log_fail "TEST-012: a complete run must not keep reading as running"
  # the earlier arm aged this run an hour; make it fresh again so the assertion
  # below is about `complete`, not about staleness
  printf 'Test run started at 2026-09-06T00:00:00Z\n' > "$rd/summary.txt"
  touch "$rd/alpha.result" "$rd"
  curl -s --max-time 2 -o "$TEST_DIR/sw7.json" "http://127.0.0.1:$PORT/data.json"
  [ "$(json_get "$TEST_DIR/sw7.json" 'd.sweep.complete')" = "false" ] \
    || log_fail "TEST-012: an in-flight summary (start line only) is NOT complete"
  [ "$(json_get "$TEST_DIR/sw7.json" 'd.sweep.active')" = "true" ] \
    || log_fail "TEST-012: an in-flight run with fresh results is active again"
  rm -f "$rd/summary.txt"
  # A FIFO summary.txt must not wedge the request thread. readFileSync on a
  # FIFO blocks forever, and this read runs inside every /data.json request, so
  # the page would stop updating with no error at all — the exact blindness the
  # panel exists to remove.
  if command -v mkfifo >/dev/null 2>&1; then
    mkfifo "$rd/summary.txt" 2>/dev/null || true
    if [ -p "$rd/summary.txt" ]; then
      rc=0; curl -s --max-time 5 -o "$TEST_DIR/sw8.json" "http://127.0.0.1:$PORT/data.json" || rc=$?
      [ "$rc" = "0" ] || log_fail "TEST-012: a FIFO summary.txt must not hang /data.json (curl rc=$rc)"
      [ "$(json_get "$TEST_DIR/sw8.json" 'd.sweep.done')" = "4" ] \
        || log_fail "TEST-012: the run must still be reported past an unreadable summary"
      grep -q 'not a regular file' "$TEST_DIR/sw8.json" \
        || log_fail "TEST-012: a non-regular summary.txt must be NAMED in degraded, not swallowed"
    fi
    rm -f "$rd/summary.txt"
  fi
  # A short SELECTED run finishing while a full sweep is in flight creates a
  # NEWER directory; the panel must keep showing the sweep that is still going,
  # not the one-suite run that just finished.
  local lr="$TEST_DIR/results/test-20260906-000001"; mkdir -p "$lr"
  printf 'PASS\n' > "$lr/only.result"; printf 'log\n' > "$lr/only.log"
  printf 'Total:   1\n' > "$lr/summary.txt"
  touch "$rd"/*.result "$rd"; touch "$lr"/* "$lr"
  curl -s --max-time 2 -o "$TEST_DIR/sw9.json" "http://127.0.0.1:$PORT/data.json"
  [ "$(json_get "$TEST_DIR/sw9.json" 'd.sweep.run')" = '"test-20260906-000000"' ] \
    || log_fail "TEST-012: a finished newer run must not eclipse the sweep still in flight: $(cat "$TEST_DIR/sw9.json")"
  rm -rf "$lr"
  stop_server
  # no results directory at all: null, not a crash and not a fabricated zero-run
  PORT="$(pick_port)" || log_fail "no free port"
  node "$ENGINE" --port "$PORT" --heartbeat-dir "$TEST_DIR/hb" --state "$TEST_DIR/STATE.yaml" \
    --answers "$TEST_DIR/answers.jsonl" --results-dir "$TEST_DIR/no-such-results" --no-live-status \
    > "$TEST_DIR/server.out" 2> "$TEST_DIR/server.err" &
  SERVER_PID=$!
  i=0; while [ "$i" -lt 30 ]; do curl -s --max-time 1 "http://127.0.0.1:$PORT/data.json" >/dev/null 2>&1 && break; sleep 0.2; i=$((i+1)); done
  curl -s --max-time 2 -o "$TEST_DIR/sw3.json" "http://127.0.0.1:$PORT/data.json"
  [ "$(json_get "$TEST_DIR/sw3.json" 'd.sweep')" = "null" ] \
    || log_fail "TEST-012: with no results directory the page must say null, not invent a run: $(cat "$TEST_DIR/sw3.json")"
  stop_server
  log_pass "sweep progress read from disk; inactive runs still reported; no invented total (TEST-012)"
}

# render_block <index.html> <data.json> <elementId> — prints what the page's own
# render() actually puts into that element, by extracting render() and running
# it against a fake DOM. Asserting on the SERVED SOURCE instead is vacuous: the
# static template contains every heading and literal the page can ever show, so
# a grep over it passes with the rendering deleted. Review proved exactly that
# against four page-level mutations here; TEST-008 already knew and said so.
render_block() {
  node -e '
    const fs=require("fs");
    const html=fs.readFileSync(process.argv[1],"utf8");
    const d=JSON.parse(fs.readFileSync(process.argv[2],"utf8"));
    const m=/function render\(d\)\{([\s\S]*?)\n\}/.exec(html);
    if(!m){console.error("render() not found in the served page");process.exit(1);}
    const el=(id)=>({id,className:"",set innerHTML(v){this._h=v;},get innerHTML(){return this._h||"";},set textContent(v){this._h=v;},get textContent(){return this._h||"";},hidden:false,querySelector:()=>null});
    const store={};
    global.document={getElementById:(id)=>(store[id]=store[id]||el(id)),querySelector:()=>null};
    const esc=(s)=>String(s==null?"":s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;"}[c]));
    const ago=(s)=>s+" s";
    new Function("d","esc","ago","document", m[1])(d, esc, ago, global.document);
    process.stdout.write((store[process.argv[3]]||{}).innerHTML||"");
  ' "$1" "$2" "$3"
}

# --- TEST-013 (SPEC live-page-shows-dead-heartbeats AC-01..03) ----------------
# The reported defect: three slots from three days earlier sat under "Agents"
# as if work were in progress. The recorded pid cannot answer "is it alive" —
# heartbeat.mjs write stores the pid of the short-lived writer, which exits at
# once — so freshness is the signal, and it FAILS OPEN: a slot past the stale
# mark but inside the hide window stays listed.
test_013_stale_slots_withheld() {
  log_info "Test: slots older than the hide window are withheld and counted, never presented as agents (TEST-013)..."
  rm -rf "$TEST_DIR/hb"; mkdir -p "$TEST_DIR/hb"; write_state false null
  node "$HEARTBEAT" write --ref fresh-ride --role Implementation --message "editing" --dir "$TEST_DIR/hb" >/dev/null 2>&1 \
    || log_fail "TEST-013: heartbeat write (fresh) failed"
  node "$HEARTBEAT" write --ref thinking-ride --role Validation --message "reading the sweep" --dir "$TEST_DIR/hb" >/dev/null 2>&1 \
    || log_fail "TEST-013: heartbeat write (thinking) failed"
  node "$HEARTBEAT" write --ref ancient-ride --role Planning --message "three days ago" --dir "$TEST_DIR/hb" >/dev/null 2>&1 \
    || log_fail "TEST-013: heartbeat write (ancient) failed"
  # a SECOND withheld slot, so "newest withheld" is distinguishable from oldest
  # and from any: with one slot, min/max/first all agree and the assertion below
  # would pass for the wrong reason (review caught Math.min -> Math.max alive)
  node "$HEARTBEAT" write --ref older-ride --role Planning --message "two hours ago" --dir "$TEST_DIR/hb" >/dev/null 2>&1 \
    || log_fail "TEST-013: heartbeat write (older) failed"
  # thinking-ride: 10 minutes — past the stale mark, inside the hide window.
  # ancient-ride: 3 days — the shape actually observed on 2026-09-06.
  node -e '
    const fs=require("fs"),p=require("path"); const dir=process.argv[1];
    const age=(frag,ms)=>{for(const n of fs.readdirSync(dir)){if(!n.includes(frag))continue;
      const f=p.join(dir,n); const d=JSON.parse(fs.readFileSync(f,"utf8"));
      d.updated_at=new Date(Date.now()-ms).toISOString(); fs.writeFileSync(f,JSON.stringify(d));}};
    age("thinking-ride", 600000); age("older-ride", 2*3600*1000); age("ancient-ride", 3*24*3600*1000);' "$TEST_DIR/hb"
  start_server --results-dir "$TEST_DIR/no-results"
  curl -s --max-time 2 -o "$TEST_DIR/wh.json" "http://127.0.0.1:$PORT/data.json"
  curl -s --max-time 2 -o "$TEST_DIR/wh.html" "http://127.0.0.1:$PORT/"
  local ids
  ids="$(json_get "$TEST_DIR/wh.json" 'd.roles.map(r=>r.ref_id).sort().join(",")')"
  [ "$ids" = '"fresh-ride,thinking-ride"' ] \
    || log_fail "TEST-013: the three-day-old slot must be withheld and the other two kept, got '$ids'"
  # FAILS OPEN: past the stale mark is marked, not hidden
  [ "$(json_get "$TEST_DIR/wh.json" 'd.roles.find(r=>r.ref_id==="thinking-ride").stale')" = "true" ] \
    || log_fail "TEST-013: a 10-minute-old slot must still be LISTED and marked stale, never hidden"
  # what was withheld is COUNTED, with the newest age — a bare count cannot tell
  # minutes-old work from a graveyard
  [ "$(json_get "$TEST_DIR/wh.json" 'd.roles_withheld.count')" = "2" ] \
    || log_fail "TEST-013: both old slots must be counted: $(cat "$TEST_DIR/wh.json")"
  # NEWEST, not oldest: the two-hour slot, not the three-day one
  local age; age="$(json_get "$TEST_DIR/wh.json" 'd.roles_withheld.newest_age_seconds')"
  [ "$age" -gt 6000 ] && [ "$age" -lt 20000 ] 2>/dev/null \
    || log_fail "TEST-013: the NEWEST withheld age must be the two-hour slot (~7200 s), got $age"
  # the RENDERED block, not the served template
  local blk; blk="$(render_block "$TEST_DIR/wh.html" "$TEST_DIR/wh.json" 'roles-body')"
  case "$blk" in *"older slot(s) on disk"*) ;; *) log_fail "TEST-013: the rendered Agents block must state what was withheld, got: ${blk:0:200}";; esac
  case "$blk" in *"ancient-ride"*) log_fail "TEST-013: a withheld slot must NOT appear in the rendered Agents block";; esac
  case "$blk" in *"thinking-ride"*) ;; *) log_fail "TEST-013: the stale-but-recent slot must appear in the rendered block, got: ${blk:0:200}";; esac
  stop_server
  # and with ONLY ancient slots the section says so instead of listing a graveyard
  rm -rf "$TEST_DIR/hb"; mkdir -p "$TEST_DIR/hb"
  node "$HEARTBEAT" write --ref only-ancient --role Planning --message "gone" --dir "$TEST_DIR/hb" >/dev/null 2>&1
  node -e '
    const fs=require("fs"),p=require("path"); const dir=process.argv[1];
    for(const n of fs.readdirSync(dir)){const f=p.join(dir,n);const d=JSON.parse(fs.readFileSync(f,"utf8"));
      d.updated_at=new Date(Date.now()-3*24*3600*1000).toISOString(); fs.writeFileSync(f,JSON.stringify(d));}' "$TEST_DIR/hb"
  start_server --results-dir "$TEST_DIR/no-results"
  curl -s --max-time 2 -o "$TEST_DIR/wh2.json" "http://127.0.0.1:$PORT/data.json"
  [ "$(json_get "$TEST_DIR/wh2.json" 'd.roles.length')" = "0" ] \
    || log_fail "TEST-013: a directory of only ancient slots must yield no agents"
  [ "$(json_get "$TEST_DIR/wh2.json" 'd.roles_withheld.count')" = "1" ] \
    || log_fail "TEST-013: it must still say one slot is on disk"
  stop_server
  log_pass "old slots withheld and counted; a stale-but-recent slot still listed; the page states what it withheld (TEST-013)"
}

# --- TEST-014 (SPEC live-page-shows-dead-heartbeats AC-05..06) ----------------
# The page loaded per-session detail and threw it away, rendering the sentence
# "N active of M sessions" while harness, project and state sat in its own data.
test_014_live_sessions_rendered() {
  log_info "Test: /data.json carries a row per running session and the page renders them (TEST-014)..."
  rm -rf "$TEST_DIR/hb"; mkdir -p "$TEST_DIR/hb"; write_state false null
  local fake="$TEST_DIR/fake-live"; mkdir -p "$fake"
  # a stub live-status that emits a known payload: two running, one finished
  cat > "$fake/generate-live-status.mjs" <<'STUB'
import fs from 'node:fs'; import path from 'node:path';
const out = process.argv[process.argv.indexOf('--output') + 1];
const dir = path.dirname(out);
fs.writeFileSync(path.join(dir, 'live-status-data.json'), JSON.stringify({
  generatedAt: '2026-09-06T12:00:00Z',
  harnesses: [{ id: 'claude-code', available: true, sessions_total: 3 }],
  live_sessions: [
    { harness: 'claude-code', project: 'aai', state: 'running (heuristic)' },
    { harness: 'codex', project: 'other-repo', state: 'running' },
    { harness: 'claude-code', project: 'old', state: 'finished' },
  ],
  spend: {}, degraded: [],
}));
fs.writeFileSync(out, '<html></html>');
STUB
  PORT="$(pick_port)" || log_fail "no free port"
  node "$ENGINE" --port "$PORT" \
    --heartbeat-dir "$TEST_DIR/hb" --state "$TEST_DIR/STATE.yaml" --answers "$TEST_DIR/answers.jsonl" \
    --live-status-script "$fake/generate-live-status.mjs" --live-status-interval 1 \
    --results-dir "$TEST_DIR/no-results" \
    > "$TEST_DIR/server.out" 2> "$TEST_DIR/server.err" &
  SERVER_PID=$!
  # the same exited-early guard start_server carries: without it a server that
  # dies on startup turns into a curl timeout and a confusing later assertion
  local i=0
  while [ "$i" -lt 30 ]; do
    curl -s --max-time 1 "http://127.0.0.1:$PORT/data.json" >/dev/null 2>&1 && break
    kill -0 "$SERVER_PID" 2>/dev/null || log_fail "TEST-014: server exited early: $(cat "$TEST_DIR/server.err")"
    sleep 0.2; i=$((i+1))
  done
  curl -s --max-time 3 -o "$TEST_DIR/ls.json" "http://127.0.0.1:$PORT/data.json"
  local n; n="$(json_get "$TEST_DIR/ls.json" 'd.live && d.live.sessions ? d.live.sessions.length : "none"')"
  [ "$n" != "none" ] || log_fail "TEST-014: /data.json carries no session rows at all: $(cat "$TEST_DIR/ls.json")"
  [ "$n" = "2" ] || log_fail "TEST-014: only the two RUNNING sessions become rows, got $n: $(cat "$TEST_DIR/ls.json")"
  [ "$(json_get "$TEST_DIR/ls.json" 'd.live.sessions[0].project')" = '"aai"' ] \
    || log_fail "TEST-014: the row must carry the project, not just a count"
  [ "$(json_get "$TEST_DIR/ls.json" 'd.live.sessions_total')" = "3" ] \
    || log_fail "TEST-014: the finished session must still be counted in the total"
  # THE RENDERED BLOCK. Grepping the served page for 'Live sessions' matched the
  # static <h2> heading and passed with the entire rendering deleted — review
  # ran that mutation and it survived.
  curl -s --max-time 2 -o "$TEST_DIR/ls.html" "http://127.0.0.1:$PORT/"
  local blk; blk="$(render_block "$TEST_DIR/ls.html" "$TEST_DIR/ls.json" 'sessions-body')"
  case "$blk" in *"<table>"*) ;; *) log_fail "TEST-014: the rendered block must be a table of sessions, got: ${blk:0:200}";; esac
  case "$blk" in *"aai"*) ;; *) log_fail "TEST-014: the running session's project must be rendered, got: ${blk:0:200}";; esac
  case "$blk" in *"codex"*) ;; *) log_fail "TEST-014: every running session must get a row, got: ${blk:0:200}";; esac
  case "$blk" in *"old"*) log_fail "TEST-014: a FINISHED session must not be rendered as a row: ${blk:0:200}";; esac
  # the scan time it came from, so a frozen page cannot look current
  case "$blk" in *"2026-09-06T12:00:00Z"*) ;; *) log_fail "TEST-014: the rendered block must state the scan timestamp, got: ${blk:0:200}";; esac
  case "$blk" in *"2 running of 3"*) ;; *) log_fail "TEST-014: non-running sessions must be summarised as a count, got: ${blk:0:200}";; esac
  # The DEGRADED panel must name the file. heartbeat degrades are {source,reason}
  # objects, and a bare map(esc) rendered them as [object Object] on the very
  # page this ride fixes.
  local dg; dg="$(render_block "$TEST_DIR/ls.html" "$TEST_DIR/dg.json" 'degraded-body' 2>/dev/null || true)"
  printf '{"degraded":[{"source":"hb-bad.json","reason":"unreadable"}],"roles":[],"roles_withheld":null,"waiting":null,"live":null,"sweep":null}\n' > "$TEST_DIR/dg.json"
  dg="$(render_block "$TEST_DIR/ls.html" "$TEST_DIR/dg.json" 'degraded-body')"
  case "$dg" in *"hb-bad.json"*) ;; *) log_fail "TEST-014: a degrade object must render its source, got: ${dg:0:200}";; esac
  case "$dg" in *"[object Object]"*) log_fail "TEST-014: a degrade object must never render as [object Object]: ${dg:0:200}";; esac
  stop_server
  log_pass "running sessions become rows with harness, project and state; finished ones stay a count; a degrade names its file (TEST-014)"
}

main() {
  echo "=== $TEST_NAME ==="
  [ -f "$ENGINE" ] || log_fail "engine missing: $ENGINE"
  [ -f "$HEARTBEAT" ] || log_fail "heartbeat.mjs missing: $HEARTBEAT"
  if [ $# -gt 0 ]; then "$1"; echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="; return; fi
  test_001_loopback_and_routes
  test_002_roles_and_stale
  test_003_waiting_first
  test_004_page_polls_and_survives
  test_005_no_repo_writes
  test_006_sigint_clean
  test_007_escape_and_freshness
  test_008_free_text_always
  test_009_answer_write_surface
  test_010_answer_cycle_no_repo_writes
  test_011_csrf_guards
  test_012_sweep_progress
  test_013_stale_slots_withheld
  test_014_live_sessions_rendered
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
