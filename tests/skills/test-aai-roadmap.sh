#!/usr/bin/env bash
#
# Test: SPEC roadmap-serves-downstream-projects — the roadmap is an ordered
# capability list with an opt-in maintenance budget, edited by one small script
# (.aai/scripts/roadmap-edit.mjs). Slice A: TEST-1311, TEST-1317..1319. Slice B: TEST-1312..1316, TEST-1320..1324. Slice C: TEST-1325..1329, TEST-1331..1335, TEST-1337
# (TEST-1330 lives in test-aai-ride-select.sh test_744, TEST-1336 in test-aai-prompt-diet.sh).
#
# Every case runs against a FIXTURE roadmap and a fixture docs tree; the shipped
# docs/ai/roadmap.yaml is never written.

set -u
TEST_NAME="test-aai-roadmap"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EDIT="$PROJECT_ROOT/.aai/scripts/roadmap-edit.mjs"
SELECT="$PROJECT_ROOT/.aai/scripts/ride-select.mjs"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_info() { echo "INFO: $*"; }
log_skip() { echo "SKIP: $*"; exit 42; }
command -v node >/dev/null 2>&1 || log_skip "node not found"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-roadmap.XXXXXX")"
[[ -n "$TEST_DIR" && "$TEST_DIR" = /* ]] || log_fail "scratch dir must be non-empty and absolute"
trap 'rm -rf "$TEST_DIR"' EXIT

# run_edit <args...> -> exit code on stdout; stdout/stderr land in $TEST_DIR/out|err
run_edit() { local rc=0; node "$EDIT" "$@" > "$TEST_DIR/out" 2> "$TEST_DIR/err" || rc=$?; echo "$rc"; }
run_select() { local rc=0; node "$SELECT" "$@" > "$TEST_DIR/sout" 2> "$TEST_DIR/serr" || rc=$?; echo "$rc"; }
out() { cat "$TEST_DIR/out"; }
err() { cat "$TEST_DIR/err"; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

# fx_doc <docsRoot> <slug> <type> <status> — a fixture intake document
fx_doc() {
  mkdir -p "$1/issues"
  printf -- '---\nid: %s\nnumber: null\ntype: %s\nstatus: %s\nlinks:\n  pr: []\n---\n\n# %s\n' "$2" "$3" "$4" "$2" > "$1/issues/CHANGE-DRAFT-$2.md"
}
# fx_dir <name> — a fresh absolute fixture directory
fx_dir() {
  local d="$TEST_DIR/$1"
  [[ -n "$d" && "$d" = /* ]] || log_fail "fx_dir: path must be non-empty and absolute"
  rm -rf "$d"; mkdir -p "$d"; echo "$d"
}
# same_bytes <fileA> <fileB>
same_bytes() { cmp -s "$1" "$2"; }

# --- TEST-1311 (Spec-AC-05): add ------------------------------------------------
test_1311_add() {
  log_info "Test: add appends a planned capability-only pair before wave_2, --at 1 puts it first, an absent path is created (TEST-1311)..."
  local d; d="$(fx_dir t1311)"
  cat > "$d/roadmap.yaml" <<'YAML'
# header comment kept
pairs:
  - capability: cap-a
    maintenance: maint-a
    status: planned
  - capability: cap-b
    status: planned
wave_2:
  - later-thing
YAML
  local R="$d/roadmap.yaml"
  [ "$(run_edit add --ref cap-new --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1311: add must exit 0: $(err)"
  cat > "$d/expect-end.yaml" <<'YAML'
# header comment kept
pairs:
  - capability: cap-a
    maintenance: maint-a
    status: planned
  - capability: cap-b
    status: planned
  - capability: cap-new
    status: planned
wave_2:
  - later-thing
YAML
  same_bytes "$R" "$d/expect-end.yaml" || log_fail "TEST-1311: add must insert the planned pair after the last pair and before wave_2, prior bytes unchanged; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1311: validate must accept the edited roadmap: $(cat "$TEST_DIR/serr")"
  # --at 1 puts the new pair first, every other line unchanged
  [ "$(run_edit add --ref cap-first --at 1 --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1311: add --at 1 must exit 0: $(err)"
  cat > "$d/expect-first.yaml" <<'YAML'
# header comment kept
pairs:
  - capability: cap-first
    status: planned
  - capability: cap-a
    maintenance: maint-a
    status: planned
  - capability: cap-b
    status: planned
  - capability: cap-new
    status: planned
wave_2:
  - later-thing
YAML
  same_bytes "$R" "$d/expect-first.yaml" || log_fail "TEST-1311: add --at 1 must put the pair first; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1311: validate must accept after --at 1: $(cat "$TEST_DIR/serr")"
  # promotion: a wave_2 ref added as a capability leaves wave_2
  [ "$(run_edit add --ref later-thing --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1311: add of a wave_2 ref must exit 0: $(err)"
  if grep -q '^  - later-thing$' "$R"; then log_fail "TEST-1311: a promoted ref must leave wave_2: $(cat "$R")"; fi
  grep -q 'capability: later-thing' "$R" || log_fail "TEST-1311: the promoted ref must become a capability"
  [ "$(run_select validate --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1311: validate must accept after promotion: $(cat "$TEST_DIR/serr")"
  # an absent path is created without a budget and discloses the gate
  local A="$d/sub/absent-roadmap.yaml"
  [ ! -e "$A" ] || log_fail "TEST-1311: fixture precondition — the path must be absent"
  [ "$(run_edit add --ref cap-x --roadmap "$A" --docs "$d/docs")" = "0" ] || log_fail "TEST-1311: add over an absent path must exit 0: $(err)"
  [ -f "$A" ] || log_fail "TEST-1311: add over an absent path must create the roadmap"
  printf 'pairs:\n  - capability: cap-x\n    status: planned\n' > "$d/expect-new.yaml"
  same_bytes "$A" "$d/expect-new.yaml" || log_fail "TEST-1311: a created roadmap must carry no budget block; got: $(cat "$A")"
  grep -q 'the ride gate is now ON' "$TEST_DIR/out" || log_fail "TEST-1311: creating a roadmap must say the ride gate is now ON, got: $(out)"
  [ "$(run_select validate --roadmap "$A" --docs "$d/docs")" = "0" ] || log_fail "TEST-1311: validate must accept the created roadmap: $(cat "$TEST_DIR/serr")"
  log_pass "add inserts before wave_2, --at 1 first, promotes from wave_2, creates a budget-free roadmap (TEST-1311)"
}

# ship_fixture <dir> [budget] — roadmap + an appendable change intake
ship_fixture() {
  local d="$1"
  {
    [ -n "${2:-}" ] && printf 'budget:\n  maintenance_per_capability: 1\n'
    printf 'pairs:\n  - capability: cap-a\n    status: planned\n  - capability: cap-b\n    status: planned\nwave_2:\n  - later-thing\n'
  } > "$d/roadmap.yaml"
  fx_doc "$d/docs" chg-ship change draft
  fx_doc "$d/docs" iss-ship issue draft
  fx_doc "$d/docs" later-thing change draft
}

# --- TEST-1317 (Spec-AC-06): ship-append appends an active capability ----------
test_1317_ship_append_writes() {
  log_info "Test: ship-append appends an active capability before wave_2 and prints exactly one line (TEST-1317)..."
  local d; d="$(fx_dir t1317)"; ship_fixture "$d"
  local R="$d/roadmap.yaml" I="$d/docs/issues/CHANGE-DRAFT-chg-ship.md"
  [ "$(run_edit ship-append --ref chg-ship --intake "$I" --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1317: ship-append must exit 0: $(err)"
  [ "$(out)" = "roadmap: appended chg-ship" ] || log_fail "TEST-1317: the line must be exactly 'roadmap: appended chg-ship', got: $(out)"
  cat > "$d/expect.yaml" <<'YAML'
pairs:
  - capability: cap-a
    status: planned
  - capability: cap-b
    status: planned
  - capability: chg-ship
    status: active
wave_2:
  - later-thing
YAML
  same_bytes "$R" "$d/expect.yaml" || log_fail "TEST-1317: the appended pair must be active and sit before wave_2; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1317: validate must accept: $(cat "$TEST_DIR/serr")"
  [ "$(run_select gate --ref chg-ship --intake "$I" --roadmap "$R" --docs "$d/docs" --events "$d/ev.jsonl")" = "0" ] || log_fail "TEST-1317: gate must admit the appended ref: $(cat "$TEST_DIR/serr")"
  # promotion: an intake whose id is listed in wave_2 leaves wave_2
  [ "$(run_edit ship-append --ref later-thing --intake "$d/docs/issues/CHANGE-DRAFT-later-thing.md" --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1317: ship-append of a wave_2 ref must exit 0: $(err)"
  if grep -q '^  - later-thing$' "$R"; then log_fail "TEST-1317: a promoted ref must leave wave_2: $(cat "$R")"; fi
  grep -q 'capability: later-thing' "$R" || log_fail "TEST-1317: the promoted ref must become a capability"
  [ "$(run_select validate --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1317: validate must accept after promotion: $(cat "$TEST_DIR/serr")"
  log_pass "ship-append appends an active capability, gate admits it, wave_2 promotion works (TEST-1317)"
}

# --- TEST-1318 (Spec-AC-06): named no-ops leave the file byte-identical --------
test_1318_ship_append_noops() {
  log_info "Test: ship-append no-op arms exit 0, print one line, leave the file byte-identical; the appendable control writes (TEST-1318)..."
  local d; d="$(fx_dir t1318)"
  local R="$d/roadmap.yaml" before
  # budget on
  ship_fixture "$d" yes; before="$(sha "$R")"
  [ "$(run_edit ship-append --ref chg-ship --intake "$d/docs/issues/CHANGE-DRAFT-chg-ship.md" --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1318: budget-on arm must exit 0: $(err)"
  [ "$(sha "$R")" = "$before" ] || log_fail "TEST-1318: budget-on arm must leave the roadmap byte-identical"
  [ "$(out | wc -l | tr -d ' ')" = "1" ] || log_fail "TEST-1318: budget-on arm must print exactly one line, got: $(out)"
  grep -q 'budget' "$TEST_DIR/out" || log_fail "TEST-1318: the budget-on line must name its reason, got: $(out)"
  # maintenance type
  ship_fixture "$d"; before="$(sha "$R")"
  [ "$(run_edit ship-append --ref iss-ship --intake "$d/docs/issues/CHANGE-DRAFT-iss-ship.md" --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1318: issue-type arm must exit 0: $(err)"
  [ "$(sha "$R")" = "$before" ] || log_fail "TEST-1318: issue-type arm must leave the roadmap byte-identical"
  grep -q 'maintenance' "$TEST_DIR/out" || log_fail "TEST-1318: the issue-type line must name its reason, got: $(out)"
  # ref already a pair capability, and already a pair maintenance
  fx_doc "$d/docs" cap-a change draft; before="$(sha "$R")"
  [ "$(run_edit ship-append --ref cap-a --intake "$d/docs/issues/CHANGE-DRAFT-cap-a.md" --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1318: already-listed arm must exit 0: $(err)"
  [ "$(sha "$R")" = "$before" ] || log_fail "TEST-1318: already-listed arm must leave the roadmap byte-identical"
  grep -q 'already' "$TEST_DIR/out" || log_fail "TEST-1318: the already-listed line must say already, got: $(out)"
  printf 'pairs:\n  - capability: cap-a\n    maintenance: chg-ship\n    status: planned\n' > "$R"; before="$(sha "$R")"
  [ "$(run_edit ship-append --ref chg-ship --intake "$d/docs/issues/CHANGE-DRAFT-chg-ship.md" --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1318: maintenance-listed arm must exit 0: $(err)"
  [ "$(sha "$R")" = "$before" ] || log_fail "TEST-1318: maintenance-listed arm must leave the roadmap byte-identical"
  # an intake whose id differs from --ref is a usage error, file untouched
  ship_fixture "$d"; before="$(sha "$R")"
  [ "$(run_edit ship-append --ref chg-other --intake "$d/docs/issues/CHANGE-DRAFT-chg-ship.md" --roadmap "$R" --docs "$d/docs")" = "2" ] || log_fail "TEST-1318: an id mismatch must exit 2"
  [ "$(sha "$R")" = "$before" ] || log_fail "TEST-1318: a usage error must leave the roadmap untouched"
  # positive control: the same call on the appendable fixture really writes
  [ "$(run_edit ship-append --ref chg-ship --intake "$d/docs/issues/CHANGE-DRAFT-chg-ship.md" --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1318: control must exit 0: $(err)"
  [ "$(sha "$R")" != "$before" ] || log_fail "TEST-1318: control — the appendable fixture must change the roadmap (otherwise the no-op arms prove nothing)"
  log_pass "ship-append no-op arms are byte-identical; the appendable control writes (TEST-1318)"
}

# --- TEST-1319 (Spec-AC-06): absent roadmap -------------------------------------
test_1319_ship_append_absent() {
  log_info "Test: ship-append against an absent roadmap exits 0, creates nothing, and gate still admits (TEST-1319)..."
  local d; d="$(fx_dir t1319)"
  fx_doc "$d/docs" chg-ship change draft
  local R="$d/docs/ai/roadmap.yaml" listing_before listing_after
  listing_before="$(listing "$d")"
  [ "$(run_edit ship-append --ref chg-ship --intake "$d/docs/issues/CHANGE-DRAFT-chg-ship.md" --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1319: absent roadmap must exit 0: $(err)"
  grep -q 'roadmap absent' "$TEST_DIR/out" || log_fail "TEST-1319: the line must say roadmap absent, got: $(out)"
  [ ! -e "$R" ] || log_fail "TEST-1319: no roadmap may be created"
  listing_after="$(listing "$d")"
  [ "$listing_before" = "$listing_after" ] || log_fail "TEST-1319: no file or directory may be created"
  [ "$(run_select gate --ref chg-ship --roadmap "$R" --docs "$d/docs" --events "$d/ev.jsonl")" = "0" ] || log_fail "TEST-1319: gate must still admit: $(cat "$TEST_DIR/serr")"
  grep -q 'roadmap absent' "$TEST_DIR/sout" || log_fail "TEST-1319: gate must still say roadmap absent, got: $(cat "$TEST_DIR/sout")"
  log_pass "ship-append over an absent roadmap is a named no-op; gate still admits (TEST-1319)"
}

# --- slice B helpers --------------------------------------------------------------
# jval <json-file> <dotted.path> — prints the value (String()) at the path
jval() {
  node -e '
    const o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const v = process.argv[2].split(".").reduce((a, k) => (a == null ? a : a[k]), o);
    process.stdout.write(String(v));
  ' "$1" "$2"
}
# listing <dir> — sorted find output, to prove "no extra file left behind"
listing() { ( [[ -n "$1" && "$1" = /* ]] || exit 1; cd "$1" && find . | LC_ALL=C sort ); }
# fx_doc_dir <docsRoot> <slug> <status> — change doc (shorthand)
fxc() { fx_doc "$1" "$2" change "$3"; }
# write_expect <file> — heredoc from stdin into a file (named for readability)
write_expect() { cat > "$1"; }

# --- TEST-1312 (Spec-AC-05): move ------------------------------------------------
test_1312_move() {
  log_info "Test: move --to 1 makes the pair first with its own lines intact; no-budget next then names it (TEST-1312)..."
  local d; d="$(fx_dir t1312)"; local R="$d/roadmap.yaml" D="$d/docs"
  fxc "$D" cap-a draft; fxc "$D" cap-b done; fxc "$D" maint-b done; fxc "$D" cap-c implementing; fxc "$D" maint-c draft
  cat > "$R" <<'YAML'
# header comment kept
pairs:
  - capability: cap-a
    status: planned
  - capability: cap-b
    maintenance: maint-b
    status: done
  - capability: cap-c
    maintenance: maint-c
    status: active
wave_2:
  - later-thing
YAML
  [ "$(run_select next --json --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1312: precondition next must exit 0: $(cat "$TEST_DIR/serr")"
  [ "$(jval "$TEST_DIR/sout" next)" = "cap-a" ] || log_fail "TEST-1312: control — before the move next must name cap-a, got: $(cat "$TEST_DIR/sout")"
  [ "$(run_edit move --ref cap-c --to 1 --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1312: move must exit 0: $(err)"
  write_expect "$d/expect.yaml" <<'YAML'
# header comment kept
pairs:
  - capability: cap-c
    maintenance: maint-c
    status: active
  - capability: cap-a
    status: planned
  - capability: cap-b
    maintenance: maint-b
    status: done
wave_2:
  - later-thing
YAML
  same_bytes "$R" "$d/expect.yaml" || log_fail "TEST-1312: move --to 1 must put cap-c first and keep every pair block's own lines; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1312: validate must accept: $(cat "$TEST_DIR/serr")"
  [ "$(run_select next --json --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1312: next must exit 0"
  [ "$(jval "$TEST_DIR/sout" next)" = "cap-c" ] || log_fail "TEST-1312: no-budget next must name the moved pair cap-c, got: $(cat "$TEST_DIR/sout")"
  # downwards: the first pair to the end, in front of nothing else but wave_2
  [ "$(run_edit move --ref cap-c --to 3 --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1312: move --to 3 must exit 0: $(err)"
  write_expect "$d/expect3.yaml" <<'YAML'
# header comment kept
pairs:
  - capability: cap-a
    status: planned
  - capability: cap-b
    maintenance: maint-b
    status: done
  - capability: cap-c
    maintenance: maint-c
    status: active
wave_2:
  - later-thing
YAML
  same_bytes "$R" "$d/expect3.yaml" || log_fail "TEST-1312: move --to 3 must restore the original order exactly; got: $(cat "$R")"
  # moving to the pair's own position is a named no-op, bytes identical
  local before; before="$(sha "$R")"
  [ "$(run_edit move --ref cap-a --to 1 --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1312: move to the own position must exit 0: $(err)"
  [ "$(sha "$R")" = "$before" ] || log_fail "TEST-1312: move to the own position must not change bytes"
  log_pass "move reorders pair blocks with their own lines, no-budget next follows the order (TEST-1312)"
}

# --- TEST-1313 (Spec-AC-05): done and drop ---------------------------------------
test_1313_done_drop() {
  log_info "Test: done flips one pair to status done; drop removes a pair block incl. maintenance and, separately, a wave_2 entry (TEST-1313)..."
  local d; d="$(fx_dir t1313)"; local R="$d/roadmap.yaml" D="$d/docs"
  fxc "$D" cap-a implementing; fxc "$D" cap-b draft; fxc "$D" maint-b draft
  cat > "$R" <<'YAML'
pairs:
  - capability: cap-a
    status: active
  - capability: cap-b
    maintenance: maint-b
    status: planned
  - capability: cap-c
    status: planned
wave_2:
  - later-thing
  - other-thing
YAML
  [ "$(run_edit done --ref cap-a --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1313: done must exit 0: $(err)"
  write_expect "$d/expect-done.yaml" <<'YAML'
pairs:
  - capability: cap-a
    status: done
  - capability: cap-b
    maintenance: maint-b
    status: planned
  - capability: cap-c
    status: planned
wave_2:
  - later-thing
  - other-thing
YAML
  same_bytes "$R" "$d/expect-done.yaml" || log_fail "TEST-1313: done must flip only cap-a's status line; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1313: validate must accept after done: $(cat "$TEST_DIR/serr")"
  # drop a pair block, maintenance line included
  [ "$(run_edit drop --ref cap-b --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1313: drop of a pair must exit 0: $(err)"
  write_expect "$d/expect-drop.yaml" <<'YAML'
pairs:
  - capability: cap-a
    status: done
  - capability: cap-c
    status: planned
wave_2:
  - later-thing
  - other-thing
YAML
  same_bytes "$R" "$d/expect-drop.yaml" || log_fail "TEST-1313: drop must remove the whole cap-b block including maint-b; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1313: validate must accept after drop: $(cat "$TEST_DIR/serr")"
  # drop a wave_2 entry, nothing else changes
  [ "$(run_edit drop --ref later-thing --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1313: drop of a wave_2 entry must exit 0: $(err)"
  write_expect "$d/expect-w2.yaml" <<'YAML'
pairs:
  - capability: cap-a
    status: done
  - capability: cap-c
    status: planned
wave_2:
  - other-thing
YAML
  same_bytes "$R" "$d/expect-w2.yaml" || log_fail "TEST-1313: drop of a wave_2 entry must remove only that line; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1313: validate must accept after the wave_2 drop: $(cat "$TEST_DIR/serr")"
  log_pass "done flips one status line; drop removes a pair block or a wave_2 line (TEST-1313)"
}

# --- TEST-1314 (Spec-AC-05): budget on / off -------------------------------------
test_1314_budget_toggle() {
  log_info "Test: budget on adds the block (next proposes bind), budget off removes it (maintenance lines stay inert), repeats refuse byte-identical (TEST-1314)..."
  local d; d="$(fx_dir t1314)"; local R="$d/roadmap.yaml" D="$d/docs"
  fxc "$D" cap-a implementing
  cat > "$d/original.yaml" <<'YAML'
# roadmap header
pairs:
  - capability: cap-a
    status: active
  - capability: cap-b
    maintenance: maint-b
    status: planned
wave_2:
  - later-thing
YAML
  cp "$d/original.yaml" "$R"
  [ "$(run_select show --json --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1314: precondition show must exit 0"
  [ "$(jval "$TEST_DIR/sout" budget)" = "false" ] || log_fail "TEST-1314: control — the fixture starts without a budget"
  [ "$(run_edit budget on --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1314: budget on must exit 0: $(err)"
  write_expect "$d/expect-on.yaml" <<'YAML'
# roadmap header
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-a
    status: active
  - capability: cap-b
    maintenance: maint-b
    status: planned
wave_2:
  - later-thing
YAML
  same_bytes "$R" "$d/expect-on.yaml" || log_fail "TEST-1314: budget on must insert the block directly before pairs:; got: $(cat "$R")"
  [ "$(run_select show --json --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1314: show after on must exit 0: $(cat "$TEST_DIR/serr")"
  [ "$(jval "$TEST_DIR/sout" budget)" = "true" ] || log_fail "TEST-1314: show json must report budget true after on, got: $(cat "$TEST_DIR/sout")"
  [ "$(jval "$TEST_DIR/sout" next.action)" = "bind" ] || log_fail "TEST-1314: with the budget on, next must propose bind for the started capability-only pair, got: $(cat "$TEST_DIR/sout")"
  local before; before="$(sha "$R")"
  [ "$(run_edit budget on --roadmap "$R" --docs "$D")" = "1" ] || log_fail "TEST-1314: repeating budget on must exit 1"
  [ "$(sha "$R")" = "$before" ] || log_fail "TEST-1314: repeating budget on must leave the bytes identical"
  [ "$(run_edit budget off --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1314: budget off must exit 0: $(err)"
  same_bytes "$R" "$d/original.yaml" || log_fail "TEST-1314: budget off must remove exactly the block (the maintenance line stays); got: $(cat "$R")"
  [ "$(run_select show --json --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1314: show after off must exit 0: $(cat "$TEST_DIR/serr")"
  [ "$(jval "$TEST_DIR/sout" budget)" = "false" ] || log_fail "TEST-1314: show json must report budget false after off, got: $(cat "$TEST_DIR/sout")"
  [ "$(jval "$TEST_DIR/sout" next.ref)" = "cap-a" ] || log_fail "TEST-1314: without a budget next must name cap-a, got: $(cat "$TEST_DIR/sout")"
  before="$(sha "$R")"
  [ "$(run_edit budget off --roadmap "$R" --docs "$D")" = "1" ] || log_fail "TEST-1314: repeating budget off must exit 1"
  [ "$(sha "$R")" = "$before" ] || log_fail "TEST-1314: repeating budget off must leave the bytes identical"
  [ "$(run_edit budget maybe --roadmap "$R" --docs "$D")" = "2" ] || log_fail "TEST-1314: budget with an unknown state must exit 2"
  # Codex P2 (PR #419): a blank line and an unindented comment inside the
  # budget section are valid (loadRoadmap filters them); budget off must
  # remove the whole section up to the next top-level key, not stop at them.
  cat > "$R" <<'YAML'
budget:

# kept apart on purpose
  maintenance_per_capability: 1

# this comment belongs to pairs and must survive
pairs:
  - capability: cap-a
    status: active
YAML
  [ "$(run_select validate --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1314 (gapped budget): precondition — the gapped roadmap must validate"
  [ "$(run_edit budget off --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1314 (gapped budget): budget off must exit 0 across a blank line and a comment: $(err)"
  write_expect "$d/expect-gapped.yaml" <<'YAML'

# this comment belongs to pairs and must survive
pairs:
  - capability: cap-a
    status: active
YAML
  same_bytes "$R" "$d/expect-gapped.yaml" || log_fail "TEST-1314 (gapped budget): budget off must remove the whole section; got: $(cat "$R")"
  log_pass "budget on/off is reversible, show json follows, repeats refuse byte-identical, gapped section removed whole (TEST-1314)"
}

# --- TEST-1315 (Spec-AC-05): off --confirm ---------------------------------------
test_1315_off() {
  log_info "Test: off --confirm removes the roadmap and gate then admits roadmap absent; without --confirm exit 2 intact; absent path exit 1 (TEST-1315)..."
  local d; d="$(fx_dir t1315)"; local R="$d/roadmap.yaml" D="$d/docs"
  fxc "$D" cap-a draft
  printf 'pairs:\n  - capability: cap-a\n    status: planned\n' > "$R"
  local before; before="$(sha "$R")"
  [ "$(run_edit off --roadmap "$R" --docs "$D")" = "2" ] || log_fail "TEST-1315: off without --confirm must exit 2"
  [ "$(sha "$R")" = "$before" ] || log_fail "TEST-1315: off without --confirm must leave the roadmap intact"
  [ "$(run_select gate --ref cap-a --roadmap "$R" --docs "$D" --events "$d/ev.jsonl")" = "0" ] || log_fail "TEST-1315: control — gate over the present roadmap admits cap-a"
  if grep -q 'roadmap absent' "$TEST_DIR/sout"; then log_fail "TEST-1315: control — a present roadmap must not read as absent"; fi
  [ "$(run_edit off --confirm --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1315: off --confirm must exit 0: $(err)"
  [ ! -e "$R" ] || log_fail "TEST-1315: off --confirm must remove the roadmap file"
  [ -d "$D" ] || log_fail "TEST-1315: off must leave the docs tree alone"
  [ "$(run_select gate --ref cap-a --roadmap "$R" --docs "$D" --events "$d/ev.jsonl")" = "0" ] || log_fail "TEST-1315: gate must admit after off: $(cat "$TEST_DIR/serr")"
  grep -q 'roadmap absent' "$TEST_DIR/sout" || log_fail "TEST-1315: gate after off must say roadmap absent, got: $(cat "$TEST_DIR/sout")"
  [ "$(run_edit off --confirm --roadmap "$R" --docs "$D")" = "1" ] || log_fail "TEST-1315: off over an absent path must exit 1"
  [ ! -e "$R" ] || log_fail "TEST-1315: off over an absent path must not create the file"
  log_pass "off --confirm removes the roadmap, gate reads absent; no --confirm and absent path refuse (TEST-1315)"
}

# --- TEST-1316 (Spec-AC-05): refusal matrix --------------------------------------
# refuses <want_rc> <label> <args...> — one edit call against $MR/$MD; the exit
# code must match, the roadmap sha256 and the directory listing must not move.
# REFUSES_LABEL_PREFIX names the TEST id in refuses()'s own log_fail messages;
# each caller sets it before use (default kept for test_1316's original calls).
REFUSES_LABEL_PREFIX="TEST-1316"
refuses() {
  local want="$1" label="$2"; shift 2
  local b_sha b_list a_list rc
  b_sha="$(sha "$MR")"; b_list="$(listing "$MROOT")"
  rc="$(run_edit "$@" --roadmap "$MR" --docs "$MD")"
  [ "$rc" = "$want" ] || log_fail "$REFUSES_LABEL_PREFIX ($label): expected exit $want, got $rc: $(err)"
  [ "$(sha "$MR")" = "$b_sha" ] || log_fail "$REFUSES_LABEL_PREFIX ($label): the roadmap bytes changed"
  a_list="$(listing "$MROOT")"
  [ "$a_list" = "$b_list" ] || log_fail "$REFUSES_LABEL_PREFIX ($label): a file appeared or vanished next to the roadmap"
}
test_1316_refusal_matrix() {
  log_info "Test: every verb's invalid input exits 1 or 2 with the roadmap sha256 and directory listing unchanged; the certification arm really wrote and restored (TEST-1316)..."
  local d; d="$(fx_dir t1316)"; MROOT="$d"; MR="$d/roadmap.yaml"; MD="$d/docs"
  fxc "$MD" cap-a draft
  cat > "$MR" <<'YAML'
pairs:
  - capability: cap-a
    maintenance: maint-a
    status: planned
  - capability: cap-b
    status: planned
wave_2:
  - wave-thing
YAML
  refuses 1 "add duplicate"            add --ref cap-a
  refuses 1 "add duplicate maintenance" add --ref maint-a
  refuses 2 "add non-slug"             add --ref Bad_Slug
  refuses 2 "add --at out of range"    add --ref cap-new --at 9
  refuses 2 "add --at zero"            add --ref cap-new --at 0
  refuses 1 "move unknown ref"         move --ref nope-ref --to 1
  refuses 2 "move --to out of range"   move --ref cap-a --to 9
  refuses 2 "move --to zero"           move --ref cap-a --to 0
  refuses 2 "move without --to"        move --ref cap-a
  refuses 1 "done unknown ref"         done --ref nope-ref
  refuses 1 "done wave_2 ref"          done --ref wave-thing
  refuses 1 "done maintenance ref"     done --ref maint-a
  refuses 1 "drop unknown ref"         drop --ref nope-ref
  refuses 1 "drop maintenance-only ref" drop --ref maint-a
  refuses 1 "budget off without budget" budget off
  refuses 2 "budget bad state"         budget maybe
  refuses 2 "off without --confirm"    off
  refuses 2 "advance non-slug"         advance --ref Bad_Slug
  refuses 2 "unknown verb"             frobnicate --ref cap-a
  # certification arm: cap-b is planned with NO document, so done is well-formed
  # but the edited roadmap fails validate (a done pair needs a document). The
  # validator's stderr being echoed proves the file WAS written and restored.
  refuses 1 "done fails certification" done --ref cap-b
  grep -q 'matches no document id' "$TEST_DIR/err" || log_fail "TEST-1316: positive control — the certification refusal must echo the validator's reason, got: $(err)"
  grep -q 'original bytes restored' "$TEST_DIR/err" || log_fail "TEST-1316: the refusal must say the original bytes were restored, got: $(err)"
  # an already-invalid roadmap is never edited, by any verb
  printf 'budget:\n  maintenance_per_capability: 2\npairs:\n  - capability: cap-a\n    status: planned\n' > "$MR"
  refuses 1 "invalid roadmap: add"      add --ref cap-new
  refuses 1 "invalid roadmap: move"     move --ref cap-a --to 1
  refuses 1 "invalid roadmap: done"     done --ref cap-a
  refuses 1 "invalid roadmap: drop"     drop --ref cap-a
  refuses 1 "invalid roadmap: budget on"  budget on
  refuses 1 "invalid roadmap: budget off" budget off
  refuses 1 "invalid roadmap: off"      off --confirm
  refuses 1 "invalid roadmap: advance"  advance --ref cap-a
  [ -f "$MR" ] || log_fail "TEST-1316: an invalid roadmap must survive off --confirm"
  # negative control: a valid call through the SAME harness must change the bytes
  printf 'pairs:\n  - capability: cap-a\n    status: planned\n' > "$MR"
  local b; b="$(sha "$MR")"
  [ "$(run_edit add --ref cap-new --roadmap "$MR" --docs "$MD")" = "0" ] || log_fail "TEST-1316: control add must exit 0: $(err)"
  [ "$(sha "$MR")" != "$b" ] || log_fail "TEST-1316: negative control — a valid add must change the bytes (otherwise the matrix proves nothing)"
  log_pass "refusal matrix: exit 1 or 2, bytes and directory listing unchanged, certification refusal restored (TEST-1316)"
}

# --- TEST-1320 (Spec-AC-07): advance, no budget -----------------------------------
test_1320_advance_no_budget() {
  log_info "Test: no-budget advance flips a pair only when the capability document is done; every other case is a byte-identical no-op (TEST-1320)..."
  local d; d="$(fx_dir t1320)"; local R="$d/roadmap.yaml" D="$d/docs"
  fxc "$D" cap-a done; fxc "$D" cap-b implementing; fxc "$D" cap-c draft; fxc "$D" cap-d done; fxc "$D" maint-d draft
  cat > "$R" <<'YAML'
pairs:
  - capability: cap-a
    status: active
  - capability: cap-b
    status: active
  - capability: cap-c
    status: planned
  - capability: cap-d
    maintenance: maint-d
    status: active
wave_2:
  - later-thing
YAML
  local before
  noop_arm() { # <label> <ref>
    before="$(sha "$R")"
    [ "$(run_edit advance --ref "$2" --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1320 ($1): advance must exit 0: $(err)"
    [ "$(sha "$R")" = "$before" ] || log_fail "TEST-1320 ($1): a no-op must leave the roadmap byte-identical"
    [ "$(out | wc -l | tr -d ' ')" = "1" ] || log_fail "TEST-1320 ($1): a no-op prints exactly one line, got: $(out)"
  }
  noop_arm "capability implementing" cap-b
  noop_arm "capability draft" cap-c
  noop_arm "off the roadmap" nowhere-ref
  noop_arm "wave_2 ref" later-thing
  noop_arm "maintenance ref without a budget" maint-d
  # control: the same call on a done capability really writes
  [ "$(run_edit advance --ref cap-a --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1320: advance of a done capability must exit 0: $(err)"
  [ "$(sha "$R")" != "$before" ] || log_fail "TEST-1320: control — a done capability must change the roadmap"
  write_expect "$d/expect.yaml" <<'YAML'
pairs:
  - capability: cap-a
    status: done
  - capability: cap-b
    status: active
  - capability: cap-c
    status: planned
  - capability: cap-d
    maintenance: maint-d
    status: active
wave_2:
  - later-thing
YAML
  same_bytes "$R" "$d/expect.yaml" || log_fail "TEST-1320: advance must flip only cap-a's status; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1320: validate must accept: $(cat "$TEST_DIR/serr")"
  noop_arm "pair already done" cap-a
  # the maintenance half is ignored without a budget: cap-d done is enough
  [ "$(run_edit advance --ref cap-d --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1320: advance of cap-d must exit 0: $(err)"
  grep -A2 'capability: cap-d' "$R" > "$TEST_DIR/capd.txt" || true
  grep -q 'status: active' "$TEST_DIR/capd.txt" && log_fail "TEST-1320: with no budget cap-d's done document is enough; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1320: validate after cap-d must accept: $(cat "$TEST_DIR/serr")"
  # absent roadmap: no-op, nothing created
  local A="$d/sub/none.yaml" lb la
  lb="$(listing "$d")"
  [ "$(run_edit advance --ref cap-a --roadmap "$A" --docs "$D")" = "0" ] || log_fail "TEST-1320: advance over an absent roadmap must exit 0: $(err)"
  la="$(listing "$d")"
  [ "$lb" = "$la" ] || log_fail "TEST-1320: advance over an absent roadmap must create nothing"
  grep -q 'roadmap absent' "$TEST_DIR/out" || log_fail "TEST-1320: the absent line must say roadmap absent, got: $(out)"
  log_pass "no-budget advance flips on a done capability document only; every other arm is a named no-op (TEST-1320)"
}

# --- TEST-1321 (Spec-AC-07): advance, budget --------------------------------------
test_1321_advance_budget() {
  log_info "Test: budget advance flips a pair only when capability AND bound maintenance documents are done (TEST-1321)..."
  local d; d="$(fx_dir t1321)"; local R="$d/roadmap.yaml" D="$d/docs"
  fxc "$D" cap-a done; fxc "$D" maint-a draft; fxc "$D" cap-b done; fxc "$D" cap-c done
  cat > "$R" <<'YAML'
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-a
    maintenance: maint-a
    status: active
  - capability: cap-b
    status: active
  - capability: cap-c
    maintenance: maint-c
    status: planned
wave_2:
  - later-thing
YAML
  local before
  noop_arm() { # <label> <ref>
    before="$(sha "$R")"
    [ "$(run_edit advance --ref "$2" --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1321 ($1): advance must exit 0: $(err)"
    [ "$(sha "$R")" = "$before" ] || log_fail "TEST-1321 ($1): a no-op must leave the roadmap byte-identical"
    [ "$(out | wc -l | tr -d ' ')" = "1" ] || log_fail "TEST-1321 ($1): a no-op prints exactly one line, got: $(out)"
  }
  noop_arm "capability done, maintenance draft" cap-a
  noop_arm "maintenance ref, maintenance draft" maint-a
  noop_arm "maintenance slot unbound" cap-b
  noop_arm "maintenance bound but no document" cap-c
  # both documents done: either half flips the pair
  fxc "$D" maint-a done
  [ "$(run_edit advance --ref maint-a --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1321: advance via the maintenance ref must exit 0: $(err)"
  [ "$(sha "$R")" != "$before" ] || log_fail "TEST-1321: control — both documents done must change the roadmap"
  write_expect "$d/expect.yaml" <<'YAML'
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-a
    maintenance: maint-a
    status: done
  - capability: cap-b
    status: active
  - capability: cap-c
    maintenance: maint-c
    status: planned
wave_2:
  - later-thing
YAML
  same_bytes "$R" "$d/expect.yaml" || log_fail "TEST-1321: advance must flip only the cap-a pair; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1321: validate must accept: $(cat "$TEST_DIR/serr")"
  # the capability ref flips an equally ready pair too
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-a\n    maintenance: maint-a\n    status: active\n' > "$R"
  [ "$(run_edit advance --ref cap-a --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1321: advance via the capability ref must exit 0: $(err)"
  grep -q 'status: done' "$R" || log_fail "TEST-1321: advance via the capability ref must flip the ready pair; got: $(cat "$R")"
  log_pass "budget advance needs both documents done; unbound or open halves are named no-ops (TEST-1321)"
}

# --- TEST-1322 (Spec-AC-08, seam S1): the REAL close-work-item.mjs ----------------
CLOSE_SCRIPT="$PROJECT_ROOT/.aai/scripts/close-work-item.mjs"
write_change_doc() { # <path> <id> <status> — copied from test-aai-close-work-item.sh
  cat > "$1" <<EOF
---
id: $2
type: change
status: $3
links:
  pr: []
  commits: []
---

# Change — Fixture $2

## Summary
- fixture doc for the roadmap close seam.

## Motivation / Business Value
- n/a

## Scope
- In scope: fixture only.
- Out of scope: everything else.

## Affected Area
- test fixture.

## Desired Behavior (To-Be)
- n/a

## Acceptance Criteria
- AC-001: fixture.

## Verification
- n/a

## Constraints / Risks
- n/a

## Notes
- ephemeral fixture; never committed to the real repo.
EOF
}
# new_fixture_repo <name> — throwaway git repo (own identity, checked setup) with docs/ai/docs-audit.yaml
new_fixture_repo() {
  local dir="$TEST_DIR/$1"
  [[ -n "$dir" && "$dir" = /* ]] || log_fail "new_fixture_repo: path must be non-empty and absolute"
  rm -rf "$dir"
  mkdir -p "$dir/docs/issues" "$dir/docs/specs" "$dir/docs/ai" "$dir/.aai/scripts"
  : > "$dir/docs/ai/EVENTS.jsonl"
  : > "$dir/.aai/scripts/state.mjs"
  cat > "$dir/docs/ai/docs-audit.yaml" <<'YAML'
legacy_until_date: 2020-01-01
stale_after_days: 90
scan_exclude: []
backlog_globs: []
close_gate: report-only
doc_number_guard: report-only
protected_paths_l3: []
YAML
  git init -q -b main "$dir" || log_fail "new_fixture_repo: git init failed"
  git -C "$dir" config user.email test@example.com || log_fail "new_fixture_repo: git config email failed"
  git -C "$dir" config user.name test || log_fail "new_fixture_repo: git config name failed"
  git -C "$dir" add -A || log_fail "new_fixture_repo: git add failed"
  git -C "$dir" commit -q -m init || log_fail "new_fixture_repo: initial commit failed"
  echo "$dir"
}
test_1322_close_seam() {
  log_info "Test: seam — advance is a no-op before the REAL close-work-item.mjs, flips the pair after it, next then names the second pair; the engine blob is untouched (TEST-1322)..."
  local dir; dir="$(new_fixture_repo t1322)"
  [[ -n "$dir" && "$dir" = /* ]] || log_fail "TEST-1322: fixture path must be non-empty and absolute"
  write_change_doc "$dir/docs/issues/CHANGE-0001-cap-one.md" cap-one implementing
  write_change_doc "$dir/docs/issues/CHANGE-0002-cap-two.md" cap-two draft
  local R="$dir/docs/ai/roadmap.yaml" D="$dir/docs"
  cat > "$R" <<'YAML'
pairs:
  - capability: cap-one
    status: active
  - capability: cap-two
    status: planned
YAML
  git -C "$dir" add -A && git -C "$dir" commit -q -m "add fixture docs" || log_fail "TEST-1322: fixture commit failed"
  local before; before="$(sha "$R")"
  [ "$(run_edit advance --ref cap-one --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1322: advance before the close must exit 0: $(err)"
  [ "$(sha "$R")" = "$before" ] || log_fail "TEST-1322: advance before the close must be a no-op"
  [ "$(run_select next --json --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1322: next before the close must exit 0"
  [ "$(jval "$TEST_DIR/sout" next)" = "cap-one" ] || log_fail "TEST-1322: before the close next names cap-one, got: $(cat "$TEST_DIR/sout")"
  local crc=0
  ( cd "$dir" && env -u AAI_ROLE node "$CLOSE_SCRIPT" --ref cap-one --pr 1 --commit a0a0a01 > "$TEST_DIR/close.out" 2> "$TEST_DIR/close.err" ) || crc=$?
  [ "$crc" = "0" ] || log_fail "TEST-1322: the real close must exit 0, got $crc: $(cat "$TEST_DIR/close.err")"
  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-cap-one.md" || log_fail "TEST-1322: the real close must flip the capability document to done"
  [ "$(sha "$R")" = "$before" ] || log_fail "TEST-1322: the close engine must not touch the roadmap (D4: advance is a sibling call)"
  [ "$(run_edit advance --ref cap-one --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1322: advance after the close must exit 0: $(err)"
  write_expect "$dir/expect.yaml" <<'YAML'
pairs:
  - capability: cap-one
    status: done
  - capability: cap-two
    status: planned
YAML
  same_bytes "$R" "$dir/expect.yaml" || log_fail "TEST-1322: advance after the close must flip cap-one to done; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1322: validate must accept: $(cat "$TEST_DIR/serr")"
  [ "$(run_select next --json --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1322: next after advance must exit 0"
  [ "$(jval "$TEST_DIR/sout" next)" = "cap-two" ] || log_fail "TEST-1322: after advance next must name cap-two, got: $(cat "$TEST_DIR/sout")"
  # the engine is hash-pinned: byte-identical to its blob at the merge-base with origin/main
  local mb live base
  mb="$(git -C "$PROJECT_ROOT" merge-base HEAD origin/main 2>/dev/null)" || mb=""
  if [ -z "$mb" ]; then
    log_info "TEST-1322: engine blob check SKIPPED — origin/main is not resolvable from this checkout (named reason: no merge-base)"
  else
    live="$(git -C "$PROJECT_ROOT" hash-object .aai/scripts/close-work-item.mjs)"
    base="$(git -C "$PROJECT_ROOT" rev-parse "$mb:.aai/scripts/close-work-item.mjs" 2>/dev/null)" || base=""
    [ -n "$base" ] || log_fail "TEST-1322: the merge-base $mb carries no close-work-item.mjs blob"
    [ "$live" = "$base" ] || log_fail "TEST-1322: close-work-item.mjs must be byte-identical to its merge-base blob ($live vs $base)"
  fi
  log_pass "advance is a no-op before the real close, flips after it, next follows; engine untouched (TEST-1322)"
}

# --- TEST-1323 (Spec-AC-09, seam S2): dispatch gate vs CLI gate ------------------
mk_dispatch_project() { # <name> <budget:yes|no|advisory>
  local d="$TEST_DIR/$1"
  [[ -n "$d" && "$d" = /* ]] || log_fail "mk_dispatch_project: fixture path not absolute: '$d'"
  rm -rf "$d"
  mkdir -p "$d/.aai/scripts/lib" "$d/docs/ai" "$d/docs/specs" "$d/docs/issues"
  cp "$PROJECT_ROOT"/.aai/scripts/{ride-select,spec-amend,follow-ups,orchestration-dispatch}.mjs "$d/.aai/scripts/"
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs "$d/.aai/scripts/lib/"
  : > "$d/docs/ai/decisions.jsonl"
  {
    [ "$2" = "yes" ] && printf 'budget:\n  maintenance_per_capability: 1\n'
    [ "$2" = "advisory" ] && printf 'budget:\n  mode: advisory\n  maintenance_threshold: 50\n'
    printf 'pairs:\n  - capability: cap-a\n    status: planned\n'
  } > "$d/docs/ai/roadmap.yaml"
  cat > "$d/docs/specs/SPEC-0001-fx.md" <<MD
---
id: spec-fixture-ride
type: spec
number: 1
status: implementing
links:
  requirement: docs/issues/CHANGE-0002-fx.md
  pr: []
  commits: []
---

# Spec fixture

SPEC-FROZEN: true
MD
  cat > "$d/docs/issues/CHANGE-0002-fx.md" <<MD
---
id: fixture-ride
type: issue
number: 2
status: draft
links:
  pr: []
  commits: []
---

# Fixture intake
MD
  cat > "$d/docs/ai/STATE.yaml" <<YAML
project_status: active
current_focus:
  type: intake_change
  ref_id: CHANGE-0001
  primary_path: docs/issues/CHANGE-0001-none.md
active_work_items:
  - ref_id: CHANGE-0001
    status: done
    phase: validation
    primary_path: docs/issues/CHANGE-0001-none.md
code_review:
  required: true
  status: pass
last_validation:
  status: pass
  ref_id: CHANGE-0001
human_input:
  required: false
  question: null
YAML
  printf '%s' "$d"
}
test_1323_dispatch_seam() {
  log_info "Test: seam — dispatch buildSnapshot candidate gate.admitted equals the CLI gate (exit 0): true without a budget, false with one, consulted in both (TEST-1323)..."
  local kind d cli_rc snap admitted consulted
  for kind in no yes; do
    d="$(mk_dispatch_project "t1323-$kind" "$kind")"
    cli_rc=0
    ( cd "$d" && node .aai/scripts/ride-select.mjs gate --ref fixture-ride --intake docs/issues/CHANGE-0002-fx.md ) > "$TEST_DIR/cli.out" 2>&1 || cli_rc=$?
    ( cd "$d" && node --input-type=module -e '
      import { buildSnapshot } from "./.aai/scripts/orchestration-dispatch.mjs";
      import path from "node:path";
      const root = process.argv[1];
      const { snapshot, problems } = buildSnapshot(path.join(root, "docs/ai/STATE.yaml"), root);
      if (!snapshot) { process.stdout.write("problems:" + problems.join(",")); process.exit(0); }
      const c = (snapshot.open_intakes || []).find((x) => x.ref_id === process.argv[2]);
      process.stdout.write(c && c.gate ? `${c.gate.admitted} ${c.gate.consulted}` : "none");
    ' "$d" fixture-ride ) > "$TEST_DIR/snap.out" 2>&1 || log_fail "TEST-1323 ($kind): buildSnapshot probe crashed: $(cat "$TEST_DIR/snap.out")"
    snap="$(cat "$TEST_DIR/snap.out")"
    [[ "$snap" != "none" && "$snap" != problems:* ]] || log_fail "TEST-1323 ($kind): the fixture intake was not an open-intake candidate: $snap"
    admitted="${snap%% *}"; consulted="${snap##* }"
    [[ "$consulted" == "true" ]] || log_fail "TEST-1323 ($kind): the roadmap is present, so consulted must be true, got $consulted"
    if [[ "$cli_rc" -eq 0 ]]; then
      [[ "$admitted" == "true" ]] || log_fail "TEST-1323 ($kind): CLI gate exit 0 but dispatch admitted=$admitted"
    else
      [[ "$admitted" == "false" ]] || log_fail "TEST-1323 ($kind): CLI gate exit $cli_rc but dispatch admitted=$admitted"
    fi
    if [[ "$kind" == "no" ]]; then
      [[ "$cli_rc" -eq 0 && "$admitted" == "true" ]] || log_fail "TEST-1323: no budget must admit an off-roadmap issue (cli=$cli_rc admitted=$admitted): $(cat "$TEST_DIR/cli.out")"
      grep -q 'no maintenance budget' "$TEST_DIR/cli.out" || log_fail "TEST-1323: the no-budget admit line must say no maintenance budget, got: $(cat "$TEST_DIR/cli.out")"
    else
      [[ "$cli_rc" -eq 1 && "$admitted" == "false" ]] || log_fail "TEST-1323: a budget must refuse the same intake (cli=$cli_rc admitted=$admitted): $(cat "$TEST_DIR/cli.out")"
    fi
  done
  log_pass "dispatch candidate gate agrees with the CLI gate: admit without a budget, refuse with one (TEST-1323)"
}

# --- TEST-1324 (Spec-AC-10, seam S3): two parsers of one switch ------------------
test_1324_nlb_seam() {
  log_info "Test: seam — nothing-left-behind reports the paired maintenance half only when the budget is on, in agreement with show json (TEST-1324)..."
  local NLB="$PROJECT_ROOT/.aai/scripts/nothing-left-behind.mjs" kind root open budget
  for kind in no yes; do
    root="$TEST_DIR/t1324-$kind"
    [[ -n "$root" && "$root" = /* ]] || log_fail "TEST-1324: fixture path must be non-empty and absolute"
    rm -rf "$root"; mkdir -p "$root/docs/ai" "$root/docs/issues"
    {
      [ "$kind" = "yes" ] && printf 'budget:\n  maintenance_per_capability: 1\n'
      printf 'pairs:\n  - capability: nlb-cap\n    maintenance: nlb-maint\n    status: done\n'
    } > "$root/docs/ai/roadmap.yaml"
    fx_doc "$root/docs" nlb-cap change done
    fx_doc "$root/docs" nlb-maint issue draft
    ( cd "$root" && git init -q -b main && git config user.email nlb1324@example.com && git config user.name nlb1324 && git add -A && git commit -q -m "feat: nlb-cap ships" ) \
      || log_fail "TEST-1324 ($kind): fixture git init/commit must succeed (a CI runner has no default git identity)"
    node "$NLB" --ref nlb-cap --root "$root" --json > "$TEST_DIR/nlb.json" 2> "$TEST_DIR/nlb.err" || true
    open="$(jval "$TEST_DIR/nlb.json" docs_open)"
    [ "$(run_select show --json --roadmap "$root/docs/ai/roadmap.yaml" --docs "$root/docs")" = "0" ] || log_fail "TEST-1324 ($kind): show must exit 0: $(cat "$TEST_DIR/serr")"
    budget="$(jval "$TEST_DIR/sout" budget)"
    if [ "$kind" = "no" ]; then
      [ "$open" = "0" ] || log_fail "TEST-1324: without a budget docs_open must be 0, got $open: $(cat "$TEST_DIR/nlb.json")"
      [ "$budget" = "false" ] || log_fail "TEST-1324: show must report budget false, got $budget"
    else
      [ "$open" = "1" ] || log_fail "TEST-1324: with a budget the draft maintenance half must count, docs_open 1, got $open: $(cat "$TEST_DIR/nlb.json")"
      grep -q 'paired maintenance half' "$TEST_DIR/nlb.json" || log_fail "TEST-1324: the budgeted report must name the paired maintenance half"
      [ "$budget" = "true" ] || log_fail "TEST-1324: show must report budget true, got $budget"
    fi
  done
  log_pass "nothing-left-behind and show json agree on the budget switch (TEST-1324)"
}

# ============================ Slice C: skill, canon prose, docs, governance =====

# file_has <file> <fixed needle> — a fixed-string membership test, no pipe
file_has() { grep -qF -- "$2" "$1"; }
# region <file> <start-regex> <end-regex> — lines from start up to (not incl.) end
region() { RS_S="$2" RS_E="$3" awk '$0 ~ ENVIRON["RS_S"] {f=1} f && $0 ~ ENVIRON["RS_E"] && !($0 ~ ENVIRON["RS_S"]) {exit} f' "$1"; }
# run_suite <suite-file> <selector> -> exit code on stdout, output in $TEST_DIR/suite-out
run_suite() { local rc=0; ( cd "$PROJECT_ROOT" && env -u AAI_ROLE bash "tests/skills/$1" "$2" ) > "$TEST_DIR/suite-out" 2>&1 || rc=$?; echo "$rc"; }
# run_sourced <suite-file> <test fn> — a hygiene-pack test reads $TEST_DIR that only an earlier test sets,
# so the isolated run sources the suite (its documented per-test entry) and supplies a scratch dir itself
run_sourced() {
  local rc=0 scratch="$TEST_DIR/sourced-scratch"; mkdir -p "$scratch"
  ( cd "$PROJECT_ROOT" && env -u AAI_ROLE SUITE="tests/skills/$1" FN="$2" SCRATCH="$scratch" bash -c 'source "$SUITE"; TEST_DIR="$SCRATCH"; check_deps; "$FN"' ) > "$TEST_DIR/suite-out" 2>&1 || rc=$?
  echo "$rc"
}

# --- TEST-1325 (Spec-AC-12): wrapper + mirrors --------------------------------------
test_1325_wrapper_and_mirrors() {
  log_info "Test: the aai-roadmap wrapper is thin, and all three mirror trees carry it under sync --check (TEST-1325)..."
  local W="$PROJECT_ROOT/.claude/skills/aai-roadmap/SKILL.md"
  [ -f "$W" ] || log_fail "TEST-1325: wrapper missing: $W"
  grep -q '^name: aai-roadmap$' "$W" || log_fail "TEST-1325: wrapper must carry 'name: aai-roadmap'"
  grep -q '^description: .\{20,\}' "$W" || log_fail "TEST-1325: wrapper must carry a description line"
  file_has "$W" '.aai/SKILL_ROADMAP.prompt.md' || log_fail "TEST-1325: wrapper must point at .aai/SKILL_ROADMAP.prompt.md"
  local n; n="$(wc -l < "$W" | tr -d ' ')"
  [ "$n" -le 45 ] || log_fail "TEST-1325: wrapper must stay within 45 lines, got $n"
  local rc=0
  node "$PROJECT_ROOT/.aai/scripts/sync-harness-skills.mjs" --check > "$TEST_DIR/sync-out" 2>&1 || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-1325: sync-harness-skills --check must exit 0, got $rc: $(cat "$TEST_DIR/sync-out")"
  local tree
  for tree in .agents/skills .codex/skills .gemini/skills; do
    [ -f "$PROJECT_ROOT/$tree/aai-roadmap/SKILL.md" ] || log_fail "TEST-1325: mirror tree $tree carries no aai-roadmap/SKILL.md"
  done
  log_pass "wrapper is thin (${n} lines), three mirrors carry it, sync --check exits 0 (TEST-1325)"
}

# --- TEST-1326 (Spec-AC-12): PROFILES core classification ----------------------------
test_1326_profiles_core() {
  log_info "Test: the three roadmap files are classified core exactly once, the manifest union holds, vendored deps are clean (TEST-1326)..."
  local P="$PROJECT_ROOT/.aai/system/PROFILES.yaml" f c
  for f in .aai/SKILL_ROADMAP.prompt.md .aai/scripts/roadmap-edit.mjs .aai/scripts/lib/roadmap-model.mjs; do
    [ -f "$PROJECT_ROOT/$f" ] || log_fail "TEST-1326: $f does not exist on disk"
    c="$(grep -cFx -- "  - $f" "$P" || true)"
    [ "$c" = "1" ] || log_fail "TEST-1326: $f must appear exactly once in PROFILES.yaml, found $c"
  done
  # core, not extended: the line sits before the extended: key
  local ext_ln road_ln
  ext_ln="$(grep -n '^extended:' "$P" || true)"; ext_ln="${ext_ln%%:*}"
  road_ln="$(grep -nFx -- '  - .aai/scripts/roadmap-edit.mjs' "$P" || true)"; road_ln="${road_ln%%:*}"
  if [ -n "$ext_ln" ]; then [ "$road_ln" -lt "$ext_ln" ] || log_fail "TEST-1326: roadmap-edit.mjs must sit in the core list, above extended: (line $road_ln vs $ext_ln)"; fi
  local rc=0
  node "$PROJECT_ROOT/.aai/scripts/check-vendored-script-deps.mjs" > "$TEST_DIR/deps-out" 2>&1 || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-1326: check-vendored-script-deps must be CLEAN, got $rc: $(cat "$TEST_DIR/deps-out")"
  [ "$(run_suite test-aai-layer-profiles.sh test_manifest_conformance)" = "0" ] || log_fail "TEST-1326: layer-profiles manifest conformance must exit 0: $(tail -5 "$TEST_DIR/suite-out")"
  log_pass "three roadmap files classified core exactly once, manifest union and vendored deps clean (TEST-1326)"
}

# --- TEST-1327 (Spec-AC-12): suite-map row -------------------------------------------
test_1327_suite_map_row() {
  log_info "Test: suite-map carries exactly one aai-roadmap row that select-suites picks for a roadmap-edit or SKILL_ROADMAP diff (TEST-1327)..."
  local M="$PROJECT_ROOT/tests/skills/suite-map.yaml" c
  c="$(grep -c '^  aai-roadmap:$' "$M" || true)"
  [ "$c" = "1" ] || log_fail "TEST-1327: suite-map must carry exactly one aai-roadmap row, found $c"
  local p
  for p in .aai/scripts/roadmap-edit.mjs .aai/SKILL_ROADMAP.prompt.md; do
    printf '%s\n' "$p" > "$TEST_DIR/changed.txt"
    node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from "$TEST_DIR/changed.txt" --repo-root "$PROJECT_ROOT" > "$TEST_DIR/sel.txt" 2>&1 || true
    grep -q '^SELECTED aai-roadmap ' "$TEST_DIR/sel.txt" || log_fail "TEST-1327: a diff of $p must SELECT aai-roadmap, got: $(cat "$TEST_DIR/sel.txt")"
  done
  # negative control: an unrelated path never selects it
  printf '%s\n' ".aai/scripts/spec-amend.mjs" > "$TEST_DIR/changed.txt"
  node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from "$TEST_DIR/changed.txt" --repo-root "$PROJECT_ROOT" > "$TEST_DIR/sel.txt" 2>&1 || true
  if grep -q '^SELECTED aai-roadmap ' "$TEST_DIR/sel.txt"; then log_fail "TEST-1327: an unrelated diff must not select aai-roadmap"; fi
  [ -s "$TEST_DIR/sel.txt" ] || log_fail "TEST-1327: negative control produced no selector output"
  log_pass "suite-map row selected for roadmap-edit and SKILL_ROADMAP diffs, not for an unrelated one (TEST-1327)"
}

# --- TEST-1328 (Spec-AC-12): USER_GUIDE catalog + quick reference --------------------
test_1328_userguide_skill_lists() {
  log_info "Test: aai-roadmap sits in the USER_GUIDE Skills Catalog and Quick Reference, hygiene test_120 exits 0 (TEST-1328)..."
  local G="$PROJECT_ROOT/docs/USER_GUIDE.md"
  grep -q '^#### `/aai-roadmap`$' "$G" || log_fail "TEST-1328: the Skills Catalog needs a '#### \`/aai-roadmap\`' chapter"
  local qr; qr="$(awk '/^## Quick Reference/{f=1; next} f && /^## /{exit} f' "$G")"
  case "$qr" in *'/aai-roadmap'*) ;; *) log_fail "TEST-1328: the Quick Reference tables must name /aai-roadmap" ;; esac
  [ "$(run_sourced test-aai-hygiene-pack.sh test_120_userguide_catalog_covers_every_skill)" = "0" ] || log_fail "TEST-1328: hygiene test_120 must exit 0: $(tail -5 "$TEST_DIR/suite-out")"
  log_pass "aai-roadmap is in the catalog and the quick reference; hygiene test_120 passes (TEST-1328)"
}

# --- TEST-1329 (Spec-AC-13): SKILL_ROADMAP action map --------------------------------
test_1329_skill_action_map() {
  log_info "Test: SKILL_ROADMAP maps the nine actions to one command each, as a menu with a default, and never edits YAML by hand (TEST-1329)..."
  local S="$PROJECT_ROOT/.aai/SKILL_ROADMAP.prompt.md" cmd
  [ -f "$S" ] || log_fail "TEST-1329: $S does not exist"
  for cmd in 'ride-select.mjs show' 'roadmap-edit.mjs add' 'roadmap-edit.mjs move' \
             'roadmap-propose.mjs harvest --direction' 'roadmap-propose.mjs write --pick' \
             'roadmap-edit.mjs done' 'roadmap-edit.mjs drop' 'roadmap-edit.mjs budget on' \
             'roadmap-edit.mjs budget off' 'roadmap-edit.mjs off --confirm'; do
    file_has "$S" "$cmd" || log_fail "TEST-1329: SKILL_ROADMAP must name the command '$cmd'"
  done
  file_has "$S" 'menu' || log_fail "TEST-1329: SKILL_ROADMAP must say each action is offered as a menu"
  file_has "$S" 'recommended default' || log_fail "TEST-1329: SKILL_ROADMAP must name a recommended default"
  file_has "$S" 'never hand-edit' || log_fail "TEST-1329: SKILL_ROADMAP must say never hand-edit"
  # no instruction to edit the YAML: the only line that mentions hand-editing is the prohibition
  local bad; bad="$(grep -ciE '(open|edit|modify|change|patch) (the )?(yaml|roadmap file|docs/ai/roadmap)' "$S" || true)"
  [ "$bad" = "0" ] || log_fail "TEST-1329: SKILL_ROADMAP must not instruct editing the roadmap file ($bad line(s))"
  log_pass "SKILL_ROADMAP maps every action to its command as a menu with a default (TEST-1329)"
}

# --- TEST-1331 (Spec-AC-14): SKILL_SHIP wiring ---------------------------------------
test_1331_ship_wiring() {
  log_info "Test: SKILL_SHIP INPUT rides the next roadmap path, 1a appends, step 6 reports (TEST-1331)..."
  local SH="$PROJECT_ROOT/.aai/SKILL_SHIP.prompt.md" input one_a step6
  input="$(region "$SH" '^INPUT' '^AUTOPILOT DEFAULTS')"
  one_a="$(region "$SH" '^   1a\. RIDE GATE' '^   1b\. ')"
  step6="$(region "$SH" '^6\. MERGE CHECKPOINT' '^7\. ')"
  case "$input" in *'ride-select.mjs next --json'*) ;; *) log_fail "TEST-1331: INPUT must name ride-select.mjs next --json" ;; esac
  case "$input" in *'`path`'*) ;; *) log_fail "TEST-1331: INPUT must name the path field" ;; esac
  case "$one_a" in *'roadmap-edit.mjs ship-append --ref <ref_id> --intake <primary_path>'*) ;; *) log_fail "TEST-1331: step 1a must name the ship-append command" ;; esac
  case "$one_a" in *'roadmap: appended'*) ;; *) log_fail "TEST-1331: step 1a must name 'roadmap: appended'" ;; esac
  case "$step6" in *'roadmap:'*) ;; *) log_fail "TEST-1331: step 6 must carry a roadmap: line" ;; esac
  [ "$(run_suite test-aai-downstream-autopilot.sh test_1210_ship_step_1a_absent_admit)" = "0" ] || log_fail "TEST-1331: TEST-1210 must stay green: $(tail -5 "$TEST_DIR/suite-out")"
  [ "$(run_suite test-aai-downstream-autopilot.sh test_1211_signoff_none_is_the_no_question_default)" = "0" ] || log_fail "TEST-1331: TEST-1211 must stay green: $(tail -5 "$TEST_DIR/suite-out")"
  log_pass "SKILL_SHIP INPUT/1a/6 wired to next --json, ship-append and the roadmap line (TEST-1331)"
}

# --- TEST-1332 (Spec-AC-14): SKILL_PR step 4c advance --------------------------------
test_1332_pr_advance_wiring() {
  log_info "Test: SKILL_PR 4c runs roadmap-edit advance after the close call and before the close commit, and stages the roadmap (TEST-1332)..."
  local PR="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md" close_ln adv_ln commit_ln hit
  hit="$(grep -nF -m1 -- 'close-work-item.mjs --ref <slug> --pr <TBD|NONE>' "$PR" || true)"; close_ln="${hit%%:*}"
  hit="$(grep -nF -m1 -- 'roadmap-edit.mjs advance --ref <slug>' "$PR" || true)"; adv_ln="${hit%%:*}"
  hit="$(grep -nF -m1 -- 'chore(close): <ref> close ceremony (PR pending)' "$PR" || true)"; commit_ln="${hit%%:*}"
  [ -n "$close_ln" ] || log_fail "TEST-1332: SKILL_PR lost the close-work-item call line"
  [ -n "$adv_ln" ] || log_fail "TEST-1332: SKILL_PR step 4c must name roadmap-edit.mjs advance --ref <slug>"
  [ -n "$commit_ln" ] || log_fail "TEST-1332: SKILL_PR lost the close commit line"
  [ "$close_ln" -lt "$adv_ln" ] && [ "$adv_ln" -lt "$commit_ln" ] || log_fail "TEST-1332: advance ($adv_ln) must sit after the close call ($close_ln) and before the close commit ($commit_ln)"
  local win; win="$(sed -n "${adv_ln},$((adv_ln + 12))p" "$PR")"
  case "$win" in *'docs/ai/roadmap.yaml'*) ;; *) log_fail "TEST-1332: the advance bullet must name docs/ai/roadmap.yaml as staged when changed" ;; esac
  case "$win" in *'check-committed-scope'*) ;; *) log_fail "TEST-1332: the advance bullet must add the roadmap to the check-committed-scope path list" ;; esac
  [ "$(run_suite test-aai-golden-flow.sh test_006_record_reads_gate_and_skill_pr_wiring)" = "0" ] || log_fail "TEST-1332: golden-flow TEST-006 must stay green: $(tail -5 "$TEST_DIR/suite-out")"
  log_pass "SKILL_PR 4c: close call < advance < close commit, roadmap staged and scope-checked (TEST-1332)"
}

# --- TEST-1333 (Spec-AC-15): USER_GUIDE section + README pointer ---------------------
test_1333_userguide_section() {
  log_info "Test: USER_GUIDE carries the Roadmap section with a TOC entry and three worked examples, README links it (TEST-1333)..."
  local G="$PROJECT_ROOT/docs/USER_GUIDE.md" R="$PROJECT_ROOT/README.md"
  grep -qx '## Roadmap: when and how' "$G" || log_fail "TEST-1333: USER_GUIDE needs the '## Roadmap: when and how' H2"
  grep -qxF -- '- [Roadmap: when and how](#roadmap-when-and-how)' "$G" || log_fail "TEST-1333: the Table of Contents needs the Roadmap entry"
  local sec; sec="$(awk '/^## Roadmap: when and how$/{f=1; next} f && /^## /{exit} f' "$G")"
  printf '%s\n' "$sec" > "$TEST_DIR/roadmap-section.md"
  local h3; h3="$(grep -c '^### ' "$TEST_DIR/roadmap-section.md" || true)"
  [ "$h3" = "4" ] || log_fail "TEST-1333: the section needs exactly four H3 worked examples (advisory budget added, Spec-AC-17), found $h3"
  local want
  for want in 'no roadmap' 'without a budget' 'with a budget' 'an advisory budget'; do
    grep -qi "^### .*$want" "$TEST_DIR/roadmap-section.md" || log_fail "TEST-1333: an H3 example must be about '$want'"
  done
  # each example block names a skill invocation
  awk 'BEGIN{n=0} /^### /{n++} n>0{print > ("'"$TEST_DIR"'/ex" n ".md")}' "$TEST_DIR/roadmap-section.md"
  local i
  for i in 1 2 3 4; do
    [ -f "$TEST_DIR/ex$i.md" ] || log_fail "TEST-1333: example $i missing"
    if ! grep -qE '/aai-(roadmap|ship)' "$TEST_DIR/ex$i.md"; then log_fail "TEST-1333: example $i must show an /aai-roadmap or /aai-ship invocation"; fi
  done
  grep -qF 'docs/USER_GUIDE.md#roadmap-when-and-how' "$R" || log_fail "TEST-1333: README must link docs/USER_GUIDE.md#roadmap-when-and-how"
  log_pass "USER_GUIDE roadmap section has TOC, four examples with invocations; README links it (TEST-1333)"
}

# --- TEST-1334 (Spec-AC-15): product doc ---------------------------------------------
test_1334_product_doc() {
  log_info "Test: docs/product/roadmap.md passes the product frontmatter and section checks (TEST-1334)..."
  local P="$PROJECT_ROOT/docs/product/roadmap.md"
  [ -f "$P" ] || log_fail "TEST-1334: $P does not exist"
  local rc=0
  PRODUCT_DOC="$P" LIBDIR="$PROJECT_ROOT/.aai/scripts/lib" node --input-type=module -e '
    import fs from "node:fs";
    const lib = process.env.LIBDIR;
    const dm = await import(lib + "/docs-model.mjs");
    const pd = await import(lib + "/product-doc.mjs");
    const text = fs.readFileSync(process.env.PRODUCT_DOC, "utf8");
    const fm = dm.parseFrontmatter(text);
    const v = dm.validateProductFrontmatter(fm);
    const miss = pd.missingProductSections(text);
    const by = Array.isArray(fm && fm.delivered_by) ? fm.delivered_by : [fm && fm.delivered_by];
    const errs = [];
    if (!v.ok) errs.push("frontmatter: " + v.violations.join("; "));
    if (miss.length) errs.push("missing sections: " + miss.join(", "));
    if (fm.capability !== "roadmap") errs.push("capability must be roadmap, got " + fm.capability);
    if (!by.includes("roadmap-serves-downstream-projects")) errs.push("delivered_by must name roadmap-serves-downstream-projects");
    if (errs.length) { console.error(errs.join(" | ")); process.exit(1); }
  ' > "$TEST_DIR/pd-out" 2>&1 || rc=$?
  [ "$rc" = "0" ] || log_fail "TEST-1334: product doc check failed: $(cat "$TEST_DIR/pd-out")"
  log_pass "product doc roadmap.md has valid frontmatter and every required section (TEST-1334)"
}

# --- TEST-1335 (Spec-AC-15): AGENTS rule 4 --------------------------------------------
test_1335_agents_rule4() {
  log_info "Test: AGENTS rule 4 states order, opt-in budget, the absent switch and /aai-roadmap inside a 40-line contract (TEST-1335)..."
  local A="$PROJECT_ROOT/.aai/AGENTS.md"
  awk '/^### Operator contract/{f=1;next} /^### |^## /{if(f)exit} f' "$A" > "$TEST_DIR/contract.txt"
  region "$TEST_DIR/contract.txt" '^4\. \*\*' '^5\. \*\*' > "$TEST_DIR/rule4.txt"
  [ -s "$TEST_DIR/rule4.txt" ] || log_fail "TEST-1335: AGENTS operator contract rule 4 not found"
  local k
  for k in 'order' 'budget is opt-in' '1:1' 'docs/ai/roadmap.yaml' 'absent' 'not consulted' '/aai-roadmap'; do
    grep -qF -- "$k" "$TEST_DIR/rule4.txt" || log_fail "TEST-1335: rule 4 must contain '$k'"
  done
  local n; n="$(wc -l < "$TEST_DIR/contract.txt" | tr -d ' ')"
  [ "$n" -le 40 ] || log_fail "TEST-1335: the operator contract must stay at most 40 lines, got $n"
  [ "$(run_suite test-aai-ride-select.sh test_007_wiring)" = "0" ] || log_fail "TEST-1335: TEST-007 must stay green: $(tail -5 "$TEST_DIR/suite-out")"
  [ "$(run_suite test-aai-ride-select.sh test_1209_header_and_rule4_state_the_switch)" = "0" ] || log_fail "TEST-1335: TEST-1209 must stay green: $(tail -5 "$TEST_DIR/suite-out")"
  log_pass "AGENTS rule 4 states order, opt-in budget and /aai-roadmap; contract $n lines (TEST-1335)"
}

# --- no-argument ship, simulated with the real scripts (TEST-1338, TEST-1339) ---------
# ship_noarg <fixture dir> — the steps SKILL_SHIP INPUT/1/1a name, in order. Prints
# one result line on $TEST_DIR/ship-result: 'need' (no roadmap or nothing to ride),
# 'path <ref>' (ridden as passed) or 'filed <ref>' (file-intake ridden under the roadmap slug).
ship_noarg() {
  local d="$1" R="$1/roadmap.yaml" ref action
  rm -f "$TEST_DIR/ship-result"
  run_select show --roadmap "$R" --docs "$d/docs" >/dev/null
  if grep -q 'no roadmap' "$TEST_DIR/sout"; then echo need > "$TEST_DIR/ship-result"; return 0; fi
  [ "$(run_select next --json --roadmap "$R" --docs "$d/docs")" = "0" ] || { echo need > "$TEST_DIR/ship-result"; return 0; }
  action="$(sed -n 's/.*"action":"\([a-z-]*\)".*/\1/p' "$TEST_DIR/sout")"
  ref="$(sed -n 's/.*"ref":"\([^"]*\)".*/\1/p' "$TEST_DIR/sout")"
  case "$action" in
    file-intake)
      # step 1: the intake is filed with a topic-derived FILE NAME but id: <ref> (the roadmap slug wins)
      mkdir -p "$d/docs/issues"
      printf -- '---\nid: %s\nnumber: null\ntype: change\nstatus: draft\nlinks:\n  pr: []\n---\n\n# the %s capability\n' "$ref" "$ref" > "$d/docs/issues/CHANGE-DRAFT-topic-words-of-$ref.md"
      [ "$(run_select gate --ref "$ref" --intake "$d/docs/issues/CHANGE-DRAFT-topic-words-of-$ref.md" --roadmap "$R" --docs "$d/docs" --events "$d/ev.jsonl")" = "0" ] || log_fail "ship_noarg: the gate must admit the filed intake of $ref: $(cat "$TEST_DIR/sout") $(cat "$TEST_DIR/serr")"
      [ "$(run_edit ship-append --ref "$ref" --intake "$d/docs/issues/CHANGE-DRAFT-topic-words-of-$ref.md" --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "ship_noarg: ship-append must exit 0: $(err)"
      case "$(out)" in *'already on the roadmap'*|*'budget is on'*) ;; *) log_fail "ship_noarg: ship-append must be a no-op for a listed ref, got: $(out)" ;; esac
      echo "filed $ref" > "$TEST_DIR/ship-result" ;;
    '') echo need > "$TEST_DIR/ship-result" ;;
    *) if grep -q '"path"' "$TEST_DIR/sout"; then echo "path $ref" > "$TEST_DIR/ship-result"; else echo need > "$TEST_DIR/ship-result"; fi ;;
  esac
}
caps_in() { grep -c '^  - capability:' "$1" || true; }

# --- TEST-1338 (Spec-AC-14, D13 amendment): no-argument ship rides a file-intake item ----
test_1338_noarg_ship_rides_roadmap_item() {
  log_info "Test: add then no-argument ship files the intake under the roadmap slug, no duplicate entry, next moves on (TEST-1338)..."
  local d; d="$(fx_dir t1338)"; local R="$d/roadmap.yaml"
  [ "$(run_edit add --ref export-dates --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1338: add must exit 0: $(err)"
  [ "$(run_edit add --ref csv-import --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1338: add must exit 0: $(err)"
  ship_noarg "$d"
  [ "$(cat "$TEST_DIR/ship-result")" = "filed export-dates" ] || log_fail "TEST-1338: the first no-argument ship must file the intake of export-dates, got: $(cat "$TEST_DIR/ship-result")"
  [ "$(caps_in "$R")" = "2" ] || log_fail "TEST-1338: exactly the two added entries must remain (no duplicate); got: $(cat "$R")"
  grep -q '^id: export-dates$' "$d/docs/issues/CHANGE-DRAFT-topic-words-of-export-dates.md" || log_fail "TEST-1338: the intake id must be the roadmap slug"
  [ "$(run_select next --json --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1338: next must exit 0"
  case "$(cat "$TEST_DIR/sout")" in *'"action":"file-intake"'*"export-dates"*) log_fail "TEST-1338: next must not return file-intake for export-dates once filed: $(cat "$TEST_DIR/sout")" ;; esac
  grep -q '"path"' "$TEST_DIR/sout" || log_fail "TEST-1338: next must carry the path of the filed document: $(cat "$TEST_DIR/sout")"
  # delivery: the close flips the document, advance flips the pair, the next no-argument ship moves on to csv-import
  sed -i.bak 's/^status: draft$/status: done/' "$d/docs/issues/CHANGE-DRAFT-topic-words-of-export-dates.md" && rm -f "$d/docs/issues/CHANGE-DRAFT-topic-words-of-export-dates.md.bak"
  [ "$(run_edit advance --ref export-dates --roadmap "$R" --docs "$d/docs")" = "0" ] || log_fail "TEST-1338: advance must exit 0: $(err)"
  ship_noarg "$d"
  [ "$(cat "$TEST_DIR/ship-result")" = "filed csv-import" ] || log_fail "TEST-1338: the second no-argument ship must take csv-import, got: $(cat "$TEST_DIR/ship-result")"
  [ "$(caps_in "$R")" = "2" ] || log_fail "TEST-1338: still exactly two entries after the second ship"
  # control: an intake filed under a topic-derived id (the old behavior) DOES duplicate the roadmap
  local c; c="$(fx_dir t1338c)"
  [ "$(run_edit add --ref export-dates --roadmap "$c/roadmap.yaml" --docs "$c/docs")" = "0" ] || log_fail "TEST-1338: control add must exit 0"
  fx_doc "$c/docs" export-includes-creation-date change draft
  [ "$(run_edit ship-append --ref export-includes-creation-date --intake "$c/docs/issues/CHANGE-DRAFT-export-includes-creation-date.md" --roadmap "$c/roadmap.yaml" --docs "$c/docs")" = "0" ] || log_fail "TEST-1338: control ship-append must exit 0"
  [ "$(caps_in "$c/roadmap.yaml")" = "2" ] || log_fail "TEST-1338: control — a topic-derived id must append a second entry (this is the defect the slug carve removes)"
  # the prompt names the carve
  local input; input="$(region "$PROJECT_ROOT/.aai/SKILL_SHIP.prompt.md" '^INPUT' '^AUTOPILOT DEFAULTS')"
  case "$input" in *'`file-intake`'*'id: <ref>'*'wins over the topic-derived slug'*) ;; *) log_fail "TEST-1338: SKILL_SHIP INPUT must ride file-intake with id: <ref> that wins over the topic-derived slug" ;; esac
  log_pass "no-argument ship files the intake under the roadmap slug: one entry, next moves on (TEST-1338)"
}

# --- TEST-1339 (Spec-AC-15): USER_GUIDE examples 2 and 3 replayed literally --------------
test_1339_userguide_examples_replay() {
  log_info "Test: the commands of USER_GUIDE Examples 2 and 3 run, in order, in a fresh fixture project and each step succeeds (TEST-1339)..."
  local G="$PROJECT_ROOT/docs/USER_GUIDE.md" n d line cmd i adds
  local sec; sec="$(awk '/^## Roadmap: when and how$/{f=1; next} f && /^## /{exit} f' "$G")"
  for n in 2 3; do
    d="$(fx_dir t1339-$n)"
    printf '%s\n' "$sec" | awk -v n="$n" '/^### Example /{c=($0 ~ "^### Example " n ":")} c && /^```/{b=!b; next} c && b{print}' > "$TEST_DIR/ex-$n.cmds"
    [ -s "$TEST_DIR/ex-$n.cmds" ] || log_fail "TEST-1339: Example $n has no command block"
    adds=0
    while IFS= read -r line; do
      cmd="${line%%#*}"; cmd="$(printf '%s' "$cmd" | sed 's/[[:space:]]*$//')"
      [ -n "$cmd" ] || continue
      case "$cmd" in
        '/aai-roadmap add') adds=$((adds + 1))
          [ "$(run_edit add --ref "capability-$adds" --roadmap "$d/roadmap.yaml" --docs "$d/docs")" = "0" ] || log_fail "TEST-1339: Example $n step '$cmd' must succeed: $(err)" ;;
        '/aai-roadmap') [ "$(run_select show --roadmap "$d/roadmap.yaml" --docs "$d/docs")" = "0" ] || log_fail "TEST-1339: Example $n step '$cmd' must succeed: $(cat "$TEST_DIR/serr")" ;;
        '/aai-roadmap budget') [ "$(run_edit budget on --roadmap "$d/roadmap.yaml" --docs "$d/docs")" = "0" ] || log_fail "TEST-1339: Example $n step '$cmd' must succeed: $(err)"
          [ "$(run_select show --roadmap "$d/roadmap.yaml" --docs "$d/docs")" = "0" ] && grep -q 'maintenance budget: on' "$TEST_DIR/sout" || log_fail "TEST-1339: Example $n step '$cmd' must leave the budget on" ;;
        '/aai-ship')
          ship_noarg "$d"
          case "$(cat "$TEST_DIR/ship-result")" in 'filed capability-1'|'path capability-1') ;; *) log_fail "TEST-1339: Example $n step '$cmd' must ride the first item, got: $(cat "$TEST_DIR/ship-result")" ;; esac ;;
        *) log_fail "TEST-1339: Example $n step '$cmd' has no replay mapping — extend the test with the docs" ;;
      esac
    done < "$TEST_DIR/ex-$n.cmds"
  done
  # Example 1 quotes the real gate line verbatim (name and path substituted)
  local e1; e1="$(fx_dir t1339-1)"
  fx_doc "$e1/docs" the-export change draft
  [ "$(run_select gate --ref the-export --intake "$e1/docs/issues/CHANGE-DRAFT-the-export.md" --roadmap "$e1/docs/ai/roadmap.yaml" --docs "$e1/docs" --events "$e1/ev.jsonl")" = "0" ] || log_fail "TEST-1339: the absent-roadmap gate must admit"
  local real; real="$(sed -e 's/ADMIT the-export/ADMIT <name>/' -e 's#(.*roadmap.yaml)#(docs/ai/roadmap.yaml)#' -e 's/^ride-select: //' "$TEST_DIR/sout")"
  grep -qF -- "$real" "$G" || log_fail "TEST-1339: Example 1 must quote the real gate line: $real"
  log_pass "USER_GUIDE Examples 2 and 3 replay green; Example 1 quotes the real ADMIT line (TEST-1339)"
}

# --- TEST-1340 (Spec-AC-13/14): skill prose for the first-run paths ---------------------
test_1340_first_run_prose() {
  log_info "Test: SKILL_ROADMAP offers add-first for budget on with no roadmap and names the last-pair rule; SKILL_SHIP checks show first (TEST-1340)..."
  local RM="$PROJECT_ROOT/.aai/SKILL_ROADMAP.prompt.md" SH="$PROJECT_ROOT/.aai/SKILL_SHIP.prompt.md" input
  file_has "$RM" 'offer "add a first capability"' || log_fail "TEST-1340: SKILL_ROADMAP budget on must offer add a first capability when no roadmap exists"
  file_has "$RM" 'last remaining pair cannot be dropped' || log_fail "TEST-1340: SKILL_ROADMAP drop must say the last pair cannot be dropped"
  local drop_region; drop_region="$(region "$RM" '^6\. drop' '^7\. budget')"
  [[ "$drop_region" == *'`off`'* ]] || log_fail "TEST-1340: SKILL_ROADMAP drop must point to off"
  input="$(region "$SH" '^INPUT' '^AUTOPILOT DEFAULTS')"
  case "$input" in *'ride-select.mjs show'*'no roadmap'*'ask for the need'*) ;; *) log_fail "TEST-1340: SKILL_SHIP INPUT must run show first and ask for the need on no roadmap" ;; esac
  # the behaviour behind it: budget on over an absent roadmap is a refusal that creates nothing, show says no roadmap
  local d; d="$(fx_dir t1340)"
  [ "$(run_edit budget on --roadmap "$d/roadmap.yaml" --docs "$d/docs")" = "1" ] || log_fail "TEST-1340: budget on over an absent roadmap must refuse with exit 1"
  [ ! -e "$d/roadmap.yaml" ] || log_fail "TEST-1340: the refusal must create no file"
  [ "$(run_select show --roadmap "$d/roadmap.yaml" --docs "$d/docs")" = "0" ] && grep -q 'no roadmap' "$TEST_DIR/sout" || log_fail "TEST-1340: show over an absent roadmap must print no roadmap and exit 0"
  log_pass "first-run prose: add-first offer, last-pair rule, show-before-next (TEST-1340)"
}

# --- TEST-1337 (Spec-AC-16): ORCHESTRATION untouched ---------------------------------
test_1337_orchestration_untouched() {
  log_info "Test: .aai/ORCHESTRATION.prompt.md is byte-identical to its merge-base blob (TEST-1337)..."
  local mb live base
  mb="$(git -C "$PROJECT_ROOT" merge-base HEAD origin/main 2>/dev/null)" || mb=""
  if [ -z "$mb" ]; then
    log_info "TEST-1337: SKIPPED — origin/main is not resolvable from this checkout (named reason: no merge-base); nothing is asserted"
    return 0
  fi
  live="$(git -C "$PROJECT_ROOT" hash-object .aai/ORCHESTRATION.prompt.md)"
  base="$(git -C "$PROJECT_ROOT" rev-parse "$mb:.aai/ORCHESTRATION.prompt.md" 2>/dev/null)" || base=""
  [ -n "$base" ] || log_fail "TEST-1337: the merge-base $mb carries no ORCHESTRATION.prompt.md blob"
  [ "$live" = "$base" ] || log_fail "TEST-1337: ORCHESTRATION.prompt.md must be byte-identical to its merge-base blob ($live vs $base)"
  log_pass "ORCHESTRATION.prompt.md equals its merge-base blob $base (TEST-1337)"
}

# ============================ Slice D (spec-roadmap-maintenance-budget-advisory):
# writer (D10) and seams (D11, D13) — TEST-1631..1638 (TEST-1644/AC-18 is
# Batch 5's scope: tests/skills/suite-map.yaml) ====================================

# --- TEST-1631 (Spec-AC-10): budget advisory --threshold writes the block --------
test_1631_budget_advisory_transitions() {
  log_info "Test: roadmap-edit budget advisory --threshold writes the two-line block from off, on and another advisory threshold; validate and show agree (TEST-1631)..."
  local d; d="$(fx_dir t1631)"; local R="$d/roadmap.yaml" D="$d/docs"
  fxc "$D" cap-a draft
  write_expect "$d/expect-advisory9.yaml" <<'YAML'
budget:
  mode: advisory
  maintenance_threshold: 9
pairs:
  - capability: cap-a
    status: planned
YAML
  # from off
  printf 'pairs:\n  - capability: cap-a\n    status: planned\n' > "$R"
  [ "$(run_edit budget advisory --threshold 9 --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1631 (from off): must exit 0: $(err)"
  same_bytes "$R" "$d/expect-advisory9.yaml" || log_fail "TEST-1631 (from off): must insert exactly the advisory block before pairs, pair lines unchanged; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1631 (from off): validate must accept: $(cat "$TEST_DIR/serr")"
  [ "$(run_select show --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1631 (from off): show must exit 0"
  local first_line1631; first_line1631="$(head -1 "$TEST_DIR/sout")"
  [ "$first_line1631" = 'maintenance budget: advisory (threshold 9)' ] || log_fail "TEST-1631 (from off): show must report threshold 9, got: $(cat "$TEST_DIR/sout")"
  # from on
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-a\n    status: planned\n' > "$R"
  [ "$(run_edit budget advisory --threshold 9 --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1631 (from on): must exit 0: $(err)"
  same_bytes "$R" "$d/expect-advisory9.yaml" || log_fail "TEST-1631 (from on): must replace the 1:1 block with the advisory one; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1631 (from on): validate must accept: $(cat "$TEST_DIR/serr")"
  # from advisory 4 to advisory 9 (threshold-first line order on read)
  printf 'budget:\n  maintenance_threshold: 4\n  mode: advisory\npairs:\n  - capability: cap-a\n    status: planned\n' > "$R"
  [ "$(run_edit budget advisory --threshold 9 --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1631 (from advisory 4): must exit 0: $(err)"
  same_bytes "$R" "$d/expect-advisory9.yaml" || log_fail "TEST-1631 (from advisory 4): must replace the old threshold; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1631 (from advisory 4): validate must accept: $(cat "$TEST_DIR/serr")"
  log_pass "budget advisory --threshold writes from off, on and another advisory threshold; validate and show agree (TEST-1631)"
}

# --- TEST-1632 (Spec-AC-10): budget off from advisory -----------------------------
test_1632_budget_off_from_advisory() {
  log_info "Test: budget off from advisory removes the block, validate accepts, show reports off (TEST-1632)..."
  local d; d="$(fx_dir t1632)"; local R="$d/roadmap.yaml" D="$d/docs"
  fxc "$D" cap-a draft
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 6\npairs:\n  - capability: cap-a\n    status: planned\n' > "$R"
  [ "$(run_edit budget off --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1632: budget off must exit 0: $(err)"
  write_expect "$d/expect.yaml" <<'YAML'
pairs:
  - capability: cap-a
    status: planned
YAML
  same_bytes "$R" "$d/expect.yaml" || log_fail "TEST-1632: budget off must remove exactly the advisory block; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1632: validate must accept: $(cat "$TEST_DIR/serr")"
  [ "$(run_select show --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1632: show must exit 0"
  local first_line1632; first_line1632="$(head -1 "$TEST_DIR/sout")"
  [ "$first_line1632" = 'maintenance budget: off' ] || log_fail "TEST-1632: show must report off, got: $(cat "$TEST_DIR/sout")"
  log_pass "budget off from advisory removes the block cleanly (TEST-1632)"
}

# --- TEST-1633 (Spec-AC-10): budget on from advisory -------------------------------
test_1633_budget_on_from_advisory() {
  log_info "Test: budget on from advisory leaves exactly maintenance_per_capability 1, validate accepts, show reports on (TEST-1633)..."
  local d; d="$(fx_dir t1633)"; local R="$d/roadmap.yaml" D="$d/docs"
  fxc "$D" cap-a draft
  printf 'budget:\n  maintenance_threshold: 6\n  mode: advisory\npairs:\n  - capability: cap-a\n    status: planned\n' > "$R"
  [ "$(run_edit budget on --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1633: budget on must exit 0: $(err)"
  write_expect "$d/expect.yaml" <<'YAML'
budget:
  maintenance_per_capability: 1
pairs:
  - capability: cap-a
    status: planned
YAML
  same_bytes "$R" "$d/expect.yaml" || log_fail "TEST-1633: budget on must leave exactly the 1:1 block; got: $(cat "$R")"
  [ "$(run_select validate --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1633: validate must accept: $(cat "$TEST_DIR/serr")"
  [ "$(run_select show --roadmap "$R" --docs "$D")" = "0" ] || log_fail "TEST-1633: show must exit 0"
  local first_line1633; first_line1633="$(head -1 "$TEST_DIR/sout")"
  [ "$first_line1633" = 'maintenance budget: on' ] || log_fail "TEST-1633: show must report on, got: $(cat "$TEST_DIR/sout")"
  log_pass "budget on from advisory leaves exactly the 1:1 block (TEST-1633)"
}

# --- TEST-1634 (Spec-AC-10): --threshold usage refusal matrix ---------------------
test_1634_budget_threshold_usage() {
  log_info "Test: every --threshold/advisory usage error exits 2 with the roadmap byte-identical and no new file (TEST-1634)..."
  local d; d="$(fx_dir t1634)"; MROOT="$d"; MR="$d/roadmap.yaml"; MD="$d/docs"
  fxc "$MD" cap-a draft
  printf 'pairs:\n  - capability: cap-a\n    status: planned\n' > "$MR"
  REFUSES_LABEL_PREFIX="TEST-1634"
  refuses 2 "advisory without --threshold" budget advisory
  refuses 2 "threshold zero"               budget advisory --threshold 0
  refuses 2 "threshold decimal"            budget advisory --threshold 1.5
  refuses 2 "threshold negative"           budget advisory --threshold -2
  refuses 2 "threshold leading zero"       budget advisory --threshold 05
  refuses 2 "threshold non-numeric"        budget advisory --threshold abc
  refuses 2 "threshold with budget on"     budget on --threshold 5
  refuses 2 "threshold with budget off"    budget off --threshold 5
  refuses 2 "threshold with add"           add --ref cap-new --threshold 5
  refuses 2 "budget bad state"             budget sometimes --threshold 5
  log_pass "every --threshold/advisory usage error exits 2, roadmap byte-identical, no file left behind (TEST-1634)"
}

# --- TEST-1635 (Spec-AC-10): repeat-state refusals are byte-identical -------------
test_1635_budget_repeat_refusals() {
  log_info "Test: budget advisory at its own threshold refuses byte-identical; on-when-on and off-when-off keep today's messages (TEST-1635)..."
  local d; d="$(fx_dir t1635)"; MROOT="$d"; MR="$d/roadmap.yaml"; MD="$d/docs"
  fxc "$MD" cap-a draft
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 4\npairs:\n  - capability: cap-a\n    status: planned\n' > "$MR"
  REFUSES_LABEL_PREFIX="TEST-1635"
  refuses 1 "advisory same threshold" budget advisory --threshold 4
  grep -q 'already advisory (threshold 4)' "$TEST_DIR/err" || log_fail "TEST-1635: the refusal must name the already-advisory threshold, got: $(err)"
  # control: a DIFFERENT threshold from the same advisory state is not a repeat
  [ "$(run_edit budget advisory --threshold 5 --roadmap "$MR" --docs "$MD")" = "0" ] || log_fail "TEST-1635: control — a different threshold must exit 0: $(err)"
  printf 'pairs:\n  - capability: cap-a\n    status: planned\n' > "$MR"
  refuses 1 "off when off" budget off
  grep -q 'already off' "$TEST_DIR/err" || log_fail "TEST-1635: budget off when off must keep today's message, got: $(err)"
  printf 'budget:\n  maintenance_per_capability: 1\npairs:\n  - capability: cap-a\n    status: planned\n' > "$MR"
  refuses 1 "on when on" budget on
  grep -q 'already on' "$TEST_DIR/err" || log_fail "TEST-1635: budget on when on must keep today's message, got: $(err)"
  log_pass "budget advisory repeat-threshold refusal is byte-identical; on/off repeat refusals keep today's messages (TEST-1635)"
}

# --- TEST-1636 (Spec-AC-11): ship-append and advance under advisory equal off -----
test_1636_ship_and_advance_advisory_equals_off() {
  log_info "Test: in advisory ship-append writes and advance ignores the maintenance half, matching the off fixture exactly (TEST-1636)..."
  local d; d="$(fx_dir t1636)"; local D="$d/docs"
  local R_off="$d/off.yaml" R_adv="$d/adv.yaml"
  printf 'pairs:\n  - capability: cap-a\n    status: planned\n  - capability: cap-b\n    status: planned\nwave_2:\n  - later-thing\n' > "$R_off"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 50\npairs:\n  - capability: cap-a\n    status: planned\n  - capability: cap-b\n    status: planned\nwave_2:\n  - later-thing\n' > "$R_adv"
  fx_doc "$D" chg-ship change draft
  fx_doc "$D" iss-ship issue draft
  local I="$D/issues/CHANGE-DRAFT-chg-ship.md"
  # a change intake appends an active pair identically in both postures
  [ "$(run_edit ship-append --ref chg-ship --intake "$I" --roadmap "$R_off" --docs "$D")" = "0" ] || log_fail "TEST-1636 (off): ship-append must exit 0: $(err)"
  [ "$(out)" = "roadmap: appended chg-ship" ] || log_fail "TEST-1636 (off): expected 'roadmap: appended chg-ship', got: $(out)"
  [ "$(run_edit ship-append --ref chg-ship --intake "$I" --roadmap "$R_adv" --docs "$D")" = "0" ] || log_fail "TEST-1636 (advisory): ship-append must exit 0: $(err)"
  [ "$(out)" = "roadmap: appended chg-ship" ] || log_fail "TEST-1636 (advisory): expected 'roadmap: appended chg-ship', got: $(out)"
  diff <(grep -vE '^budget:|^  mode: advisory|^  maintenance_threshold:' "$R_adv") "$R_off" > /dev/null \
    || log_fail "TEST-1636: the appended pairs must be identical in advisory and off apart from the budget block; off=$(cat "$R_off") advisory=$(cat "$R_adv")"
  # an issue intake is a named no-op, byte-identical, in both postures
  local before_off before_adv
  before_off="$(sha "$R_off")"; before_adv="$(sha "$R_adv")"
  local I2="$D/issues/CHANGE-DRAFT-iss-ship.md"
  [ "$(run_edit ship-append --ref iss-ship --intake "$I2" --roadmap "$R_off" --docs "$D")" = "0" ] || log_fail "TEST-1636 (off, issue): must exit 0: $(err)"
  grep -q 'maintenance' "$TEST_DIR/out" || log_fail "TEST-1636 (off, issue): must name the maintenance reason, got: $(out)"
  [ "$(sha "$R_off")" = "$before_off" ] || log_fail "TEST-1636 (off, issue): must leave the roadmap byte-identical"
  [ "$(run_edit ship-append --ref iss-ship --intake "$I2" --roadmap "$R_adv" --docs "$D")" = "0" ] || log_fail "TEST-1636 (advisory, issue): must exit 0: $(err)"
  grep -q 'maintenance' "$TEST_DIR/out" || log_fail "TEST-1636 (advisory, issue): must name the maintenance reason, got: $(out)"
  [ "$(sha "$R_adv")" = "$before_adv" ] || log_fail "TEST-1636 (advisory, issue): must leave the roadmap byte-identical"
  # advance: a done capability flips even though its bound maintenance half is draft, in both postures
  local R2_off="$d/adv2.yaml" R2_adv="$d/off2.yaml"
  fxc "$D" cap-c done
  fx_doc "$D" maint-c issue draft
  printf 'pairs:\n  - capability: cap-c\n    maintenance: maint-c\n    status: active\n' > "$R2_off"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 50\npairs:\n  - capability: cap-c\n    maintenance: maint-c\n    status: active\n' > "$R2_adv"
  [ "$(run_edit advance --ref cap-c --roadmap "$R2_off" --docs "$D")" = "0" ] || log_fail "TEST-1636 (off, advance): must exit 0: $(err)"
  grep -q 'status: done' "$R2_off" || log_fail "TEST-1636 (off, advance): must flip the pair to done even though the maintenance half is draft; got: $(cat "$R2_off")"
  [ "$(run_edit advance --ref cap-c --roadmap "$R2_adv" --docs "$D")" = "0" ] || log_fail "TEST-1636 (advisory, advance): must exit 0: $(err)"
  grep -q 'status: done' "$R2_adv" || log_fail "TEST-1636 (advisory, advance): must flip the pair to done exactly as off; got: $(cat "$R2_adv")"
  log_pass "ship-append and advance behave exactly as off under advisory (TEST-1636)"
}

# --- TEST-1637 (Spec-AC-12, seam S3): nothing-left-behind under advisory ----------
test_1637_nlb_seam_advisory() {
  log_info "Test: seam — nothing-left-behind reports no paired maintenance half under advisory, one under on, and the invalid-roadmap control is unchanged (TEST-1637)..."
  local NLB="$PROJECT_ROOT/.aai/scripts/nothing-left-behind.mjs" kind root open budget_block
  for kind in off on advisory invalid; do
    root="$TEST_DIR/t1637-$kind"
    [[ -n "$root" && "$root" = /* ]] || log_fail "TEST-1637: fixture path must be non-empty and absolute"
    rm -rf "$root"; mkdir -p "$root/docs/ai" "$root/docs/issues"
    case "$kind" in
      off) budget_block='' ;;
      on) budget_block=$'budget:\n  maintenance_per_capability: 1\n' ;;
      advisory) budget_block=$'budget:\n  mode: advisory\n  maintenance_threshold: 50\n' ;;
      invalid) budget_block=$'budget:\n  maintenance_per_capability: 2\n' ;;
    esac
    printf '%spairs:\n  - capability: nlb-cap\n    maintenance: nlb-maint\n    status: done\n' "$budget_block" > "$root/docs/ai/roadmap.yaml"
    fx_doc "$root/docs" nlb-cap change done
    fx_doc "$root/docs" nlb-maint issue draft
    ( cd "$root" && git init -q -b main && git config user.email nlb1637@example.com && git config user.name nlb1637 && git add -A && git commit -q -m "feat: nlb-cap ships" ) \
      || log_fail "TEST-1637 ($kind): fixture git init/commit must succeed (a CI runner has no default git identity)"
    node "$NLB" --ref nlb-cap --root "$root" --json > "$TEST_DIR/nlb-$kind.json" 2> "$TEST_DIR/nlb-$kind.err" || true
    open="$(jval "$TEST_DIR/nlb-$kind.json" docs_open)"
    case "$kind" in
      off|advisory)
        [ "$open" = "0" ] || log_fail "TEST-1637 ($kind): docs_open must be 0, got $open: $(cat "$TEST_DIR/nlb-$kind.json")" ;;
      on)
        [ "$open" = "1" ] || log_fail "TEST-1637 ($kind): docs_open must be 1, got $open: $(cat "$TEST_DIR/nlb-$kind.json")"
        grep -q 'paired maintenance half' "$TEST_DIR/nlb-$kind.json" || log_fail "TEST-1637 ($kind): must name the paired maintenance half" ;;
      invalid)
        [ "$open" = "1" ] || log_fail "TEST-1637 (invalid): the pre-existing line-scan must still pair on any top-level budget: line, got $open: $(cat "$TEST_DIR/nlb-$kind.json")"
        grep -q 'paired maintenance half' "$TEST_DIR/nlb-$kind.json" || log_fail "TEST-1637 (invalid): must still name the paired maintenance half" ;;
    esac
  done
  log_pass "nothing-left-behind pairs on posture on only; advisory joins off, the invalid-roadmap line-scan control is unchanged (TEST-1637)"
}

# --- TEST-1638 (Spec-AC-13, seams S2/S4): dispatch gate + loadRoadmap pairs -------
# load_pairs_json <roadmap-path> — JSON of loadRoadmap(p).roadmap.pairs, via the
# REAL lib/roadmap-model.mjs (no second parser)
load_pairs_json() {
  node -e '
    import(process.argv[1]).then(({ loadRoadmap }) => {
      const loaded = loadRoadmap(process.argv[2]);
      process.stdout.write(JSON.stringify(loaded.roadmap ? loaded.roadmap.pairs : { error: loaded.error }));
    });
  ' "$PROJECT_ROOT/.aai/scripts/lib/roadmap-model.mjs" "$1"
}
test_1638_dispatch_and_pairs_seam() {
  log_info "Test: seam — dispatch buildSnapshot candidate gate.admitted under advisory equals the CLI gate and the off verdict; loadRoadmap pairs equal advisory vs off (TEST-1638)..."
  local kind d cli_rc snap admitted consulted admitted_no admitted_advisory
  for kind in no advisory; do
    d="$(mk_dispatch_project "t1638-$kind" "$kind")"
    cli_rc=0
    ( cd "$d" && node .aai/scripts/ride-select.mjs gate --ref fixture-ride --intake docs/issues/CHANGE-0002-fx.md ) > "$TEST_DIR/cli.out" 2>&1 || cli_rc=$?
    ( cd "$d" && node --input-type=module -e '
      import { buildSnapshot } from "./.aai/scripts/orchestration-dispatch.mjs";
      import path from "node:path";
      const root = process.argv[1];
      const { snapshot, problems } = buildSnapshot(path.join(root, "docs/ai/STATE.yaml"), root);
      if (!snapshot) { process.stdout.write("problems:" + problems.join(",")); process.exit(0); }
      const c = (snapshot.open_intakes || []).find((x) => x.ref_id === process.argv[2]);
      process.stdout.write(c && c.gate ? `${c.gate.admitted} ${c.gate.consulted}` : "none");
    ' "$d" fixture-ride ) > "$TEST_DIR/snap.out" 2>&1 || log_fail "TEST-1638 ($kind): buildSnapshot probe crashed: $(cat "$TEST_DIR/snap.out")"
    snap="$(cat "$TEST_DIR/snap.out")"
    [[ "$snap" != "none" && "$snap" != problems:* ]] || log_fail "TEST-1638 ($kind): the fixture intake was not an open-intake candidate: $snap"
    admitted="${snap%% *}"; consulted="${snap##* }"
    [[ "$consulted" == "true" ]] || log_fail "TEST-1638 ($kind): the roadmap is present, so consulted must be true, got $consulted"
    [[ "$cli_rc" -eq 0 && "$admitted" == "true" ]] || log_fail "TEST-1638 ($kind): the advisory/off CLI gate must admit an off-roadmap issue (cli=$cli_rc admitted=$admitted): $(cat "$TEST_DIR/cli.out")"
    [ "$kind" = "no" ] && admitted_no="$admitted" || admitted_advisory="$admitted"
  done
  [ "$admitted_no" = "$admitted_advisory" ] || log_fail "TEST-1638: the advisory candidate gate verdict must equal the off verdict, got advisory=$admitted_advisory off=$admitted_no"

  # loadRoadmap pairs equal for the advisory and off variant of one roadmap
  local off_json adv_json
  printf 'pairs:\n  - capability: cap-a\n    maintenance: cap-b\n    status: active\n  - capability: cap-c\n    status: planned\n' > "$TEST_DIR/t1638-off.yaml"
  printf 'budget:\n  mode: advisory\n  maintenance_threshold: 50\npairs:\n  - capability: cap-a\n    maintenance: cap-b\n    status: active\n  - capability: cap-c\n    status: planned\n' > "$TEST_DIR/t1638-adv.yaml"
  off_json="$(load_pairs_json "$TEST_DIR/t1638-off.yaml")" || log_fail "TEST-1638: loadRoadmap over the off fixture must not crash: $off_json"
  adv_json="$(load_pairs_json "$TEST_DIR/t1638-adv.yaml")" || log_fail "TEST-1638: loadRoadmap over the advisory fixture must not crash: $adv_json"
  [ "$off_json" = "$adv_json" ] || log_fail "TEST-1638: loadRoadmap pairs must be identical for off and advisory, off=$off_json advisory=$adv_json"
  log_pass "dispatch candidate gate agrees under advisory, equals off; loadRoadmap pairs equal off vs advisory (TEST-1638)"
}

# --- TEST-1639 (Spec-AC-14): SKILL_ROADMAP action 7, three-posture menu ----------
test_1639_skill_roadmap_advisory_menu() {
  log_info "Test: SKILL_ROADMAP action 7 names on, advisory and off, the advisory command, waiting --json and recommended_threshold (TEST-1639)..."
  local S="$PROJECT_ROOT/.aai/SKILL_ROADMAP.prompt.md" action7
  action7="$(region "$S" '^7\. budget' '^8\. ')"
  [ -n "$action7" ] || log_fail "TEST-1639: SKILL_ROADMAP action 7 not found"
  printf '%s\n' "$action7" > "$TEST_DIR/action7.txt"
  file_has "$TEST_DIR/action7.txt" 'budget on' || log_fail "TEST-1639: action 7 must still name budget on"
  file_has "$TEST_DIR/action7.txt" 'budget off' || log_fail "TEST-1639: action 7 must still name budget off"
  file_has "$TEST_DIR/action7.txt" 'budget advisory' || log_fail "TEST-1639: action 7 must name budget advisory"
  file_has "$TEST_DIR/action7.txt" 'roadmap-edit.mjs budget advisory --threshold' || log_fail "TEST-1639: action 7 must name the advisory command roadmap-edit.mjs budget advisory --threshold"
  file_has "$TEST_DIR/action7.txt" 'ride-select.mjs waiting --json' || log_fail "TEST-1639: action 7 must name ride-select.mjs waiting --json"
  file_has "$TEST_DIR/action7.txt" 'recommended_threshold' || log_fail "TEST-1639: action 7 must name recommended_threshold"
  [ "$(run_suite test-aai-roadmap.sh test_1329_skill_action_map)" = "0" ] || log_fail "TEST-1639: TEST-1329 must stay green: $(tail -5 "$TEST_DIR/suite-out")"
  [ "$(run_suite test-aai-ride-select.sh test_744_no_automatic_invocation_site)" = "0" ] || log_fail "TEST-1639: TEST-1330 (test_744) must stay green: $(tail -5 "$TEST_DIR/suite-out")"
  log_pass "SKILL_ROADMAP action 7 offers on, advisory and off with the advisory command, waiting --json and recommended_threshold (TEST-1639)"
}

# --- TEST-1640 (Spec-AC-15): SKILL_SHIP INPUT propose_maintenance relay ----------
test_1640_skill_ship_propose_maintenance_relay() {
  log_info "Test: SKILL_SHIP INPUT relays propose_maintenance as one two-option menu and asks nothing else (TEST-1640)..."
  local SH="$PROJECT_ROOT/.aai/SKILL_SHIP.prompt.md" input
  input="$(region "$SH" '^INPUT' '^AUTOPILOT DEFAULTS')"
  [ -n "$input" ] || log_fail "TEST-1640: SKILL_SHIP INPUT section not found"
  printf '%s\n' "$input" > "$TEST_DIR/input.txt"
  file_has "$TEST_DIR/input.txt" 'propose_maintenance' || log_fail "TEST-1640: INPUT must name propose_maintenance"
  file_has "$TEST_DIR/input.txt" 'candidates' || log_fail "TEST-1640: INPUT must name candidates"
  file_has "$TEST_DIR/input.txt" 'alternative' || log_fail "TEST-1640: INPUT must name alternative"
  file_has "$TEST_DIR/input.txt" 'ONE menu' || log_fail "TEST-1640: INPUT must say it offers ONE menu"
  file_has "$TEST_DIR/input.txt" 'recommended' || log_fail "TEST-1640: INPUT must name a recommended option"
  file_has "$TEST_DIR/input.txt" 'asking nothing' || log_fail "TEST-1640: INPUT must say it asks nothing else"
  [ "$(run_suite test-aai-roadmap.sh test_1331_ship_wiring)" = "0" ] || log_fail "TEST-1640: TEST-1331 must stay green: $(tail -5 "$TEST_DIR/suite-out")"
  [ "$(run_suite test-aai-roadmap.sh test_1338_noarg_ship_rides_roadmap_item)" = "0" ] || log_fail "TEST-1640: TEST-1338 must stay green: $(tail -5 "$TEST_DIR/suite-out")"
  log_pass "SKILL_SHIP INPUT relays propose_maintenance as one two-option menu, asking nothing else (TEST-1640)"
}

# --- TEST-1642 (Spec-AC-17): USER_GUIDE advisory posture row + Example 4 ---------
test_1642_userguide_advisory_posture_and_example4() {
  log_info "Test: USER_GUIDE roadmap section gains an advisory posture row and Example 4; the /aai-roadmap note lists budget (on, advisory or off) (TEST-1642)..."
  local G="$PROJECT_ROOT/docs/USER_GUIDE.md"
  local sec; sec="$(awk '/^## Roadmap: when and how$/{f=1; next} f && /^## /{exit} f' "$G")"
  printf '%s\n' "$sec" > "$TEST_DIR/roadmap-section.md"
  grep -qE '^\|.*[Aa]dvisory.*\|' "$TEST_DIR/roadmap-section.md" || log_fail "TEST-1642: the posture table must carry an advisory row"
  grep -qxF -- '### Example 4: an advisory budget' "$TEST_DIR/roadmap-section.md" || log_fail "TEST-1642: the section must carry '### Example 4: an advisory budget'"
  local ex4; ex4="$(awk '/^### Example 4: an advisory budget$/{f=1; next} f && /^### /{exit} f' "$TEST_DIR/roadmap-section.md")"
  [ -n "$ex4" ] || log_fail "TEST-1642: Example 4 body must be non-empty"
  case "$ex4" in *'/aai-roadmap budget'*) ;; *) log_fail "TEST-1642: Example 4 must name /aai-roadmap budget" ;; esac
  case "$ex4" in *'/aai-ship'*) ;; *) log_fail "TEST-1642: Example 4 must name /aai-ship" ;; esac
  grep -qF -- 'budget (on, advisory or off)' "$G" || log_fail "TEST-1642: the /aai-roadmap note must list budget (on, advisory or off)"
  [ "$(run_suite test-aai-roadmap.sh test_1333_userguide_section)" = "0" ] || log_fail "TEST-1642: TEST-1333 must stay green: $(tail -5 "$TEST_DIR/suite-out")"
  log_pass "USER_GUIDE gains the advisory posture row, Example 4, and the updated budget note; TEST-1333 stays green (TEST-1642)"
}

# --- TEST-1643 (Spec-AC-17): product doc, three postures worked -----------------
test_1643_product_doc_three_postures() {
  log_info "Test: docs/product/roadmap.md names mode: advisory, maintenance_threshold, propose_maintenance, ride-select.mjs waiting and carries one worked example per posture (TEST-1643)..."
  local P="$PROJECT_ROOT/docs/product/roadmap.md" k
  for k in 'mode: advisory' 'maintenance_threshold' 'propose_maintenance' 'ride-select.mjs waiting'; do
    grep -qF -- "$k" "$P" || log_fail "TEST-1643: docs/product/roadmap.md must name '$k'"
  done
  local sec; sec="$(awk '/^## Worked examples$/{f=1; next} f && /^## /{exit} f' "$P")"
  [ -n "$sec" ] || log_fail "TEST-1643: docs/product/roadmap.md must carry a '## Worked examples' section"
  printf '%s\n' "$sec" > "$TEST_DIR/worked-examples.md"
  local h3; h3="$(grep -c '^### ' "$TEST_DIR/worked-examples.md" || true)"
  [ "$h3" = "3" ] || log_fail "TEST-1643: Worked examples needs exactly three H3 postures, found $h3"
  local p2
  for p2 in 'Off' 'On' 'Advisory'; do
    grep -qx "### $p2" "$TEST_DIR/worked-examples.md" || log_fail "TEST-1643: Worked examples must have a '### $p2' posture"
  done
  [ "$(run_suite test-aai-roadmap.sh test_1334_product_doc)" = "0" ] || log_fail "TEST-1643: TEST-1334 must stay green: $(tail -5 "$TEST_DIR/suite-out")"
  log_pass "docs/product/roadmap.md names the advisory vocabulary and carries one worked example per posture (TEST-1643)"
}

# --- TEST-1644 (Spec-AC-18): suite-map lists follow-ups.mjs under aai-ride-select --
test_1644_suite_map_followups_under_ride_select() {
  log_info "Test: suite-map lists .aai/scripts/follow-ups.mjs inside the aai-ride-select block, read by block not a file-wide grep (TEST-1644)..."
  local M="$PROJECT_ROOT/tests/skills/suite-map.yaml"
  local block; block="$(awk '/^  aai-ride-select:$/{f=1; next} f && /^  [a-zA-Z0-9_-]+:$/{exit} f' "$M")"
  [ -n "$block" ] || log_fail "TEST-1644: aai-ride-select block not found"
  printf '%s\n' "$block" > "$TEST_DIR/aai-ride-select-block.txt"
  grep -qF -- '.aai/scripts/follow-ups.mjs' "$TEST_DIR/aai-ride-select-block.txt" || log_fail "TEST-1644: .aai/scripts/follow-ups.mjs must be listed inside the aai-ride-select block"
  # independent re-derivation of the block's line range (never trust one awk alone)
  local line_no next_key
  line_no="$(awk '/^  aai-ride-select:$/{print NR; exit}' "$M")"
  [ -n "$line_no" ] || log_fail "TEST-1644: aai-ride-select: key line not found"
  next_key="$(awk -v start="$line_no" 'NR>start && /^  [a-zA-Z0-9_-]+:$/{print NR; exit}' "$M")"
  [ -n "$next_key" ] || log_fail "TEST-1644: next suite key after aai-ride-select not found"
  sed -n "${line_no},${next_key}p" "$M" > "$TEST_DIR/aai-ride-select-range.txt"
  grep -qF -- '.aai/scripts/follow-ups.mjs' "$TEST_DIR/aai-ride-select-range.txt" || log_fail "TEST-1644: the independent line-range re-derivation must also find follow-ups.mjs inside the block"
  # functional: a diff touching only follow-ups.mjs selects aai-ride-select
  printf '%s\n' ".aai/scripts/follow-ups.mjs" > "$TEST_DIR/changed.txt"
  node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from "$TEST_DIR/changed.txt" --repo-root "$PROJECT_ROOT" > "$TEST_DIR/sel.txt" 2>&1 || true
  grep -q '^SELECTED aai-ride-select ' "$TEST_DIR/sel.txt" || log_fail "TEST-1644: a follow-ups.mjs diff must SELECT aai-ride-select, got: $(cat "$TEST_DIR/sel.txt")"
  log_pass "suite-map lists follow-ups.mjs inside the aai-ride-select block; a diff of it selects the suite (TEST-1644)"
}

main() {
  echo "=== $TEST_NAME ==="
  [ -f "$SELECT" ] || log_fail "ride-select missing: $SELECT"
  if [ $# -gt 0 ]; then
    declare -F "$1" >/dev/null || { echo "Unknown test: $1" >&2; exit 2; }
    "$1"; echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="; return
  fi
  test_1311_add
  test_1317_ship_append_writes
  test_1318_ship_append_noops
  test_1319_ship_append_absent
  test_1312_move
  test_1313_done_drop
  test_1314_budget_toggle
  test_1315_off
  test_1316_refusal_matrix
  test_1320_advance_no_budget
  test_1321_advance_budget
  test_1322_close_seam
  test_1323_dispatch_seam
  test_1324_nlb_seam
  test_1325_wrapper_and_mirrors
  test_1326_profiles_core
  test_1327_suite_map_row
  test_1328_userguide_skill_lists
  test_1329_skill_action_map
  test_1331_ship_wiring
  test_1332_pr_advance_wiring
  test_1333_userguide_section
  test_1334_product_doc
  test_1335_agents_rule4
  test_1338_noarg_ship_rides_roadmap_item
  test_1339_userguide_examples_replay
  test_1340_first_run_prose
  test_1337_orchestration_untouched
  test_1631_budget_advisory_transitions
  test_1632_budget_off_from_advisory
  test_1633_budget_on_from_advisory
  test_1634_budget_threshold_usage
  test_1635_budget_repeat_refusals
  test_1636_ship_and_advance_advisory_equals_off
  test_1637_nlb_seam_advisory
  test_1638_dispatch_and_pairs_seam
  test_1639_skill_roadmap_advisory_menu
  test_1640_skill_ship_propose_maintenance_relay
  test_1642_userguide_advisory_posture_and_example4
  test_1643_product_doc_three_postures
  test_1644_suite_map_followups_under_ride_select
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
