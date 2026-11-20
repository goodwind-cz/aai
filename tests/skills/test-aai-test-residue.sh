#!/usr/bin/env bash
#
# Test: test runs remove only the container residue they provably created,
# and cannot reach a daemon unless they opt in
# (docs/specs/SPEC-0303-spec-test-residue-safe-cleanup.md, TEST-3900 to
# TEST-3914), and the run temp root and leftover processes
# (spec-test-residue-files-and-processes, TEST-3923 to TEST-3933).
#
# SAFETY RULE OF THIS FILE. No case here ever invokes a real container CLI.
# Every cleanup runs against STUB_CLI, a shell script written into this
# suite's own scratch directory that keeps its "objects" as files, records
# every call, and carries the sentinel line the library requires inside a
# test. The recorder CLI used by the refusal cases has no sentinel and only
# logs. On top of that, every wrapper invocation below exports DOCKER_HOST,
# CONTAINER_HOST and CONTAINERD_ADDRESS pointing at sockets that do not
# exist, so a regression that slipped past the stub still could not reach a
# daemon. Background: on 2026-11-19 an earlier draft of this cleanup was
# mutation-tested against the owner's real daemon and deleted every
# container, volume and network on it.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-test-residue"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/pipe-safe.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

LIB="$PROJECT_ROOT/.aai/scripts/lib/test-residue.sh"
WRAP="$PROJECT_ROOT/.aai/scripts/aai-run-tests.sh"
FRAMEWORK="$PROJECT_ROOT/tests/skills/test-framework.sh"
MUTATION_RUN="$PROJECT_ROOT/.aai/scripts/mutation-run.mjs"

NO_DOCKER='unix:///nonexistent/aai-test-no-docker.sock'
NO_CONTAINERD='/nonexistent/aai-test-no-containerd.sock'
export DOCKER_HOST="$NO_DOCKER" CONTAINER_HOST="$NO_DOCKER" CONTAINERD_ADDRESS="$NO_CONTAINERD" DOCKER_CONTEXT=default
export AAI_FRICTION_CAPTURE=0

# A fixed run id and start for the library-level cases. START is
# 2026-11-19T12:00:00Z; AFTER and BEFORE sit on either side of it.
RID='aai-1795089600-4242-0123abcd'
OTHER_RID='aai-1795089600-4242-ffffffff'
START=1795089600
AT_START='2026-11-19T12:00:00Z'
AFTER='2026-11-19T12:30:00.5Z'
BEFORE='2026-11-01T00:00:00Z'

FAILED=0
log_pass() { echo "PASS $*"; }
log_fail() { echo "FAIL $*" >&2; FAILED=1; }
log_skip() { echo "SKIP $*"; exit 42; }
log_info() { echo "  $*"; }

TR_TMP="$(mktemp -d "${TMPDIR:-/tmp}/aai-test-residue.XXXXXX")" || { echo "FAIL $TEST_NAME: no scratch directory" >&2; exit 1; }
case "$TR_TMP" in
  /*/aai-test-residue.*) : ;;
  *) echo "FAIL $TEST_NAME: unsafe scratch directory '$TR_TMP'" >&2; exit 1 ;;
esac
cleanup() { reap_all_sandboxes 2>/dev/null; rm -rf "$TR_TMP"; }
trap cleanup EXIT

check_deps() {
  command -v awk >/dev/null 2>&1 || log_skip "awk not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  command -v node >/dev/null 2>&1 || log_skip "node not found"
}

# --- the stub CLI -------------------------------------------------------------
# Objects live at $AAI_STUB_DIR/obj/<kind>/<id>, one file each, with lines
#   label=<value>   (absent: the object carries no aai.test.run label)
#   created=<RFC 3339 time>
#   inspect=fail    (inspection by id fails)
#   rm=fail         (removal fails)
# Flags in $AAI_STUB_DIR: `lie` (listings ignore their filter), `down` (every
# call fails as if the daemon did not answer). Every call is appended to
# $AAI_STUB_DIR/calls.log, one line, arguments joined by spaces.
STUB_CLI="$TR_TMP/bin/stub-docker"
REC_CLI="$TR_TMP/bin/recorder-docker"
mkdir -p "$TR_TMP/bin"
cat > "$STUB_CLI" <<'STUB'
#!/bin/sh
# AAI-RESIDUE-STUB-SENTINEL-v1
# Stub container CLI of tests/skills/test-aai-test-residue.sh. It never talks
# to a daemon: objects are files under $AAI_STUB_DIR/obj.
S="${AAI_STUB_DIR:?AAI_STUB_DIR unset}"
printf '%s\n' "$*" >> "$S/calls.log"
if [ -f "$S/down2" ]; then
  echo "Error response from daemon: unavailable" >&2
  exit 2
fi
if [ -f "$S/down" ]; then
  echo "Cannot connect to the Docker daemon at unix:///stub.sock. Is the docker daemon running?" >&2
  exit 1
fi
mkdir -p "$S/obj/container" "$S/obj/volume" "$S/obj/network"
newid() { od -An -N32 -tx1 /dev/urandom | tr -d ' \n'; }
now() { date -u +%Y-%m-%dT%H:%M:%S.123456789Z; }
filter=''
label=''
prev=''
last=''
for a in "$@"; do
  case "$prev" in
    --filter) filter="$a" ;;
    --label) label="$a" ;;
  esac
  prev="$a"
  last="$a"
done
list() {
  for f in "$S/obj/$1"/* "$S/obj/$1"/.[!.]*; do
    [ -f "$f" ] || continue
    if [ -n "$filter" ] && [ ! -f "$S/lie" ]; then
      want="${filter#label=}"
      [ "${want%%=*}" = "aai.test.run" ] || continue
      grep -qxF -- "label=${want#*=}" "$f" || continue
    fi
    printf '%s\n' "${f##*/}"
  done
}
inspect() {
  f="$S/obj/$1/$2"
  [ -f "$f" ] || { echo "Error: No such object: $2" >&2; exit 1; }
  grep -qxF 'inspect=fail' "$f" && { echo "Error response from daemon: inspect failed" >&2; exit 1; }
  l=$(sed -n 's/^label=//p' "$f")
  c=$(sed -n 's/^created=//p' "$f")
  # A missing label inspects as an empty string, as on real docker and podman.
  printf '%s "%s"\n' "$l" "$c"
}
remove() {
  f="$S/obj/$1/$2"
  [ -f "$f" ] || { echo "Error: No such object: $2" >&2; exit 1; }
  grep -qxF 'rm=fail' "$f" && { echo "Error response from daemon: removal failed" >&2; exit 1; }
  rm -f -- "$f"
}
create() {
  f="$S/obj/$1/$2"
  { [ -n "$label" ] && printf 'label=%s\n' "${label#aai.test.run=}"; printf 'created=%s\n' "$(now)"; } > "$f"
  printf '%s\n' "$2"
}
case "$1 ${2:-}" in
  "ps "*) list container ;;
  "volume ls") list volume ;;
  "network ls") list network ;;
  "container inspect") inspect container "$last" ;;
  "volume inspect") inspect volume "$last" ;;
  "network inspect") inspect network "$last" ;;
  "rm -f") remove container "$last" ;;
  "volume rm") remove volume "$last" ;;
  "network rm") remove network "$last" ;;
  "run "*) create container "$(newid)" ;;
  "volume create") create volume "$last" ;;
  "network create") create network "$(newid)" ;;
  *) echo "stub-docker: unsupported call: $*" >&2; exit 64 ;;
esac
STUB
cat > "$REC_CLI" <<'REC'
#!/bin/sh
# A recording CLI that is NOT the AAI test stub: no sentinel line.
printf '%s\n' "$*" >> "${REC_LOG:?REC_LOG unset}"
exit 0
REC
chmod +x "$STUB_CLI" "$REC_CLI"
# Belt and braces: inside this suite a bare `docker`, `podman` or `nerdctl`
# resolves to a script that only logs and fails, and the cleanup's default
# CLI is the recorder. Each case that needs the stub names it explicitly.
cat > "$TR_TMP/bin/docker" <<'NOCLI'
#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >> "${AAI_NO_CLI_LOG:-/dev/null}"
echo "test-aai-test-residue: a real container CLI must never run here" >&2
exit 97
NOCLI
chmod +x "$TR_TMP/bin/docker"
cp "$TR_TMP/bin/docker" "$TR_TMP/bin/podman"
cp "$TR_TMP/bin/docker" "$TR_TMP/bin/nerdctl"
export PATH="$TR_TMP/bin:$PATH"
export AAI_NO_CLI_LOG="$TR_TMP/no-cli.log"
export AAI_RESIDUE_DOCKER="$REC_CLI" REC_LOG="$TR_TMP/rec-default.log"

STUB_SEQ=0
# new_stub -> prints a fresh, empty stub state directory.
new_stub() {
  STUB_SEQ=$((STUB_SEQ + 1))
  local d="$TR_TMP/stub-$STUB_SEQ-$RANDOM"
  mkdir -p "$d/obj/container" "$d/obj/volume" "$d/obj/network"
  : > "$d/calls.log"
  printf '%s\n' "$d"
}
hexid() { printf '%064x' "$1"; }
# stub_add <stub> <kind> <id> <label or -> <created> [extra line...]
stub_add() {
  local s="$1" kind="$2" id="$3" label="$4" created="$5"
  shift 5
  {
    [[ "$label" == "-" ]] || printf 'label=%s\n' "$label"
    printf 'created=%s\n' "$created"
    local x
    for x in "$@"; do printf '%s\n' "$x"; done
  } > "$s/obj/$kind/$id"
}
has_obj() { [[ -f "$1/obj/$2/$3" ]]; }
count_obj() { local n=0 f; for f in "$1/obj/$2"/* "$1/obj/$2"/.[!.]*; do [[ -f "$f" ]] && n=$((n + 1)); done; echo "$n"; }

# lib_run <stub> <run id> <start> [lib path] — source the library in a
# subshell and run one cleanup against the stub; sets LIB_OUT and LIB_RC.
lib_run() {
  local s="$1" id="$2" st="$3" lib="${4:-$LIB}"
  LIB_RC=0
  LIB_OUT="$(
    AAI_STUB_DIR="$s" AAI_RESIDUE_DOCKER="$STUB_CLI" AAI_RESIDUE_IN_TEST=1 \
      AAI_RESIDUE_DRY_RUN="${AAI_RESIDUE_DRY_RUN:-0}" sh -c '. "$1" || exit 99; aai_residue_cleanup "$2" "$3"' residue-case "$lib" "$id" "$st" 2>&1
  )" || LIB_RC=$?
}

# filter_check <stub> <run id> — 0 when every listing call in the stub's log
# carried exactly the run's label filter, and there were three of them.
filter_check() {
  local s="$1" id="$2" n=0 line
  while IFS= read -r line; do
    case "$line" in
      "ps "* | "volume ls"* | "network ls"*)
        n=$((n + 1))
        [[ " $line " == *" --filter label=aai.test.run=$id "* ]] || return 1
        ;;
    esac
  done < "$s/calls.log"
  [[ "$n" -eq 3 ]]
}

# mutating_calls <stub> — the stub log's removal calls, one per line.
mutating_calls() {
  command grep -E '^(rm|volume rm|network rm)( |$)' "$1/calls.log" || true
}

# wrap_optin <stub> <cmd...> — the REAL wrapper, opted in, against the stub;
# sets W_OUT and W_RC.
wrap_optin() {
  local s="$1"
  shift
  W_RC=0
  W_OUT="$(
    env -u AAI_TEST_RUN_ID -u AAI_TEST_RUN_START AAI_TEST_DOCKER=1 \
      AAI_TEST_TIMEOUT="${AAI_TEST_TIMEOUT:-3000}" AAI_RESIDUE_DOCKER="${WRAP_CLI:-$STUB_CLI}" AAI_STUB_DIR="$s" \
      bash "$WRAP" "$@" 2>&1
  )" || W_RC=$?
}

# --- TEST-3900 (Spec-AC-01, A) -----------------------------------------------
test_3900_per_object_ownership_survives_a_lying_listing() {
  local s ok=1
  s="$(new_stub)"
  : > "$s/lie"
  stub_add "$s" container "$(hexid 1)" "$RID" "$AFTER"
  stub_add "$s" volume own-vol "$RID" "$AFTER"
  stub_add "$s" network "$(hexid 2)" "$RID" "$AFTER"
  stub_add "$s" volume unlabelled-vol - "$AFTER"
  stub_add "$s" container "$(hexid 3)" "$OTHER_RID" "$AFTER"
  stub_add "$s" volume old-vol "$RID" "$BEFORE"
  stub_add "$s" network "$(hexid 4)" "$RID" "$AFTER" 'inspect=fail'
  stub_add "$s" volume -rf "$RID" "$AFTER"
  lib_run "$s" "$RID" "$START"

  [[ "$LIB_RC" -eq 0 ]] || { log_fail "TEST-3900 cleanup exit $LIB_RC (want 0): $LIB_OUT"; ok=0; }
  has_obj "$s" container "$(hexid 1)" && { log_fail "TEST-3900 owned container still present"; ok=0; }
  has_obj "$s" volume own-vol && { log_fail "TEST-3900 owned volume still present"; ok=0; }
  has_obj "$s" network "$(hexid 2)" && { log_fail "TEST-3900 owned network still present"; ok=0; }
  local k i
  for k in "volume unlabelled-vol" "container $(hexid 3)" "volume old-vol" "network $(hexid 4)" "volume -rf"; do
    has_obj "$s" ${k% *} "${k#* }" || { log_fail "TEST-3900 $k was removed but this run does not own it"; ok=0; }
  done
  command grep -qF "skipped volume unlabelled-vol - label aai.test.run is '', not this run's id" <<<"$LIB_OUT" \
    || { log_fail "TEST-3900 no skipped line with the label reason for the unlabelled volume: $LIB_OUT"; ok=0; }
  command grep -qF "skipped container $(hexid 3) - label aai.test.run is '$OTHER_RID', not this run's id" <<<"$LIB_OUT" \
    || { log_fail "TEST-3900 no skipped line naming the foreign label: $LIB_OUT"; ok=0; }
  command grep -qF "skipped volume old-vol - created $BEFORE, before this run started" <<<"$LIB_OUT" \
    || { log_fail "TEST-3900 no skipped line naming the creation time: $LIB_OUT"; ok=0; }
  command grep -qF "skipped network $(hexid 4) - inspect by id failed" <<<"$LIB_OUT" \
    || { log_fail "TEST-3900 no skipped line for the failed inspection: $LIB_OUT"; ok=0; }
  command grep -qF "skipped volume '-rf' - the listing returned something that is not an id" <<<"$LIB_OUT" \
    || { log_fail "TEST-3900 no skipped line for the option-shaped token: $LIB_OUT"; ok=0; }
  i="$(command grep -cE '^(container|volume|network) inspect ' "$s/calls.log")"
  [[ "$i" -eq 7 ]] || { log_fail "TEST-3900 want 7 inspections by id (one per id-shaped candidate), got $i"; ok=0; }
  # The per-object check validates its own inputs: with an empty run id an
  # unlabelled object (empty label) must still be refused (validation NB-1).
  local vout vrc
  for k in "" "not-a-run-id"; do
    vrc=0
    vout="$(AAI_STUB_DIR="$s" AAI_RESIDUE_DOCKER="$STUB_CLI" sh -c '. "$1" || exit 99; aai_residue_verify volume unlabelled-vol "$2" "$3"' residue-case "$LIB" "$k" "$START" 2>&1)" || vrc=$?
    [[ "$vrc" -ne 0 ]] || { log_fail "TEST-3900 aai_residue_verify accepted the unlabelled volume with run id [$k]: $vout"; ok=0; }
  done
  vrc=0
  vout="$(AAI_STUB_DIR="$s" AAI_RESIDUE_DOCKER="$STUB_CLI" sh -c '. "$1" || exit 99; aai_residue_verify volume unlabelled-vol "$2" ""' residue-case "$LIB" "$RID" 2>&1)" || vrc=$?
  [[ "$vrc" -ne 0 ]] || { log_fail "TEST-3900 aai_residue_verify accepted an empty run start: $vout"; ok=0; }
  filter_check "$s" "$RID" || { log_fail "TEST-3900 a listing call did not carry --filter label=aai.test.run=$RID: $(cat "$s/calls.log")"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3900 only the three owned objects removed; unlabelled, foreign, old, uninspectable and option-shaped candidates left in place with reasons; every listing filtered by the run id"
}

# --- TEST-3901 (Spec-AC-01, A: time) -----------------------------------------
test_3901_creation_time_boundaries_and_formats() {
  local s ok=1
  s="$(new_stub)"
  stub_add "$s" volume at-start "$RID" "$AT_START"
  stub_add "$s" container "$(hexid 5)" "$RID" '2026-11-19T12:59:59+01:00'
  stub_add "$s" network "$(hexid 6)" "$RID" '2026-11-19T14:00:00.123456789+02:00'
  stub_add "$s" volume bad-time "$RID" 'yesterday'
  lib_run "$s" "$RID" "$START"
  has_obj "$s" volume at-start && { log_fail "TEST-3901 a volume created exactly at the run start was kept: $LIB_OUT"; ok=0; }
  has_obj "$s" container "$(hexid 5)" || { log_fail "TEST-3901 a container created one second before the start (offset form) was removed"; ok=0; }
  has_obj "$s" network "$(hexid 6)" && { log_fail "TEST-3901 a network created at the start (fraction, +02:00) was kept: $LIB_OUT"; ok=0; }
  has_obj "$s" volume bad-time || { log_fail "TEST-3901 a volume with an unreadable creation time was removed"; ok=0; }
  command grep -qF "skipped volume bad-time - creation time 'yesterday' is unreadable" <<<"$LIB_OUT" \
    || { log_fail "TEST-3901 no skipped line for the unreadable time: $LIB_OUT"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3901 created at the start removed (Z and offset forms), a second before and an unreadable time left in place"
}

# --- TEST-3902 (Spec-AC-02, B) -----------------------------------------------
test_3902_no_run_id_never_means_all() {
  local s ok=1 bad case_id case_st
  s="$(new_stub)"
  stub_add "$s" volume v1 "$RID" "$AFTER"
  stub_add "$s" volume v2 - "$AFTER"
  for bad in '' 'aai-123' "$RID"$'\n'x 'AAI-1795089600-4242-0123ABCD' 'aai-1795089600-4242-0123abc' "label=aai.test.run=$RID" '*'; do
    lib_run "$s" "$bad" "$START"
    [[ "$LIB_RC" -eq 2 ]] || { log_fail "TEST-3902 run id [$bad]: exit $LIB_RC (want 2): $LIB_OUT"; ok=0; }
    command grep -qF 'REFUSED - run id' <<<"$LIB_OUT" || { log_fail "TEST-3902 run id [$bad]: no REFUSED line: $LIB_OUT"; ok=0; }
  done
  for case_st in '' '12a' '-1'; do
    lib_run "$s" "$RID" "$case_st"
    [[ "$LIB_RC" -eq 2 ]] || { log_fail "TEST-3902 run start [$case_st]: exit $LIB_RC (want 2): $LIB_OUT"; ok=0; }
    command grep -qF 'REFUSED - run start' <<<"$LIB_OUT" || { log_fail "TEST-3902 run start [$case_st]: no REFUSED line: $LIB_OUT"; ok=0; }
  done
  for case_id in '' 'not-a-run-id'; do
    LIB_RC=0
    LIB_OUT="$(AAI_STUB_DIR="$s" AAI_RESIDUE_DOCKER="$STUB_CLI" sh -c '. "$1" || exit 99; aai_residue_list volume "$2"' residue-case "$LIB" "$case_id" 2>&1)" || LIB_RC=$?
    [[ "$LIB_RC" -eq 2 ]] || { log_fail "TEST-3902 aai_residue_list with [$case_id]: exit $LIB_RC (want 2): $LIB_OUT"; ok=0; }
    command grep -qF 'REFUSED - listing volume objects needs this run' <<<"$LIB_OUT" || { log_fail "TEST-3902 aai_residue_list with [$case_id]: no REFUSED line: $LIB_OUT"; ok=0; }
  done
  [[ -s "$s/calls.log" ]] && { log_fail "TEST-3902 the stub was called although every input was refused: $(cat "$s/calls.log")"; ok=0; }
  [[ "$(count_obj "$s" volume)" -eq 2 ]] || { log_fail "TEST-3902 an object disappeared"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3902 empty, malformed and newline-carrying run ids and bad starts refused with exit 2 before any CLI call; the listing refuses without a valid id"
}

# --- TEST-3903 (Spec-AC-03, C) -----------------------------------------------
test_3903_single_object_verbs_only() {
  local s ok=1 calls want code n
  s="$(new_stub)"
  stub_add "$s" container "$(hexid 7)" "$RID" "$AFTER"
  stub_add "$s" volume own-vol "$RID" "$AFTER"
  stub_add "$s" network "$(hexid 8)" "$RID" "$AFTER"
  lib_run "$s" "$RID" "$START"
  calls="$(mutating_calls "$s")"
  want="rm -f $(hexid 7)
volume rm own-vol
network rm $(hexid 8)"
  [[ "$calls" == "$want" ]] || { log_fail "TEST-3903 mutating calls were [$calls], want exactly [$want]"; ok=0; }
  if [[ -f "$LIB" ]]; then
    code="$(command grep -vE '^[[:space:]]*#' "$LIB")"
    command grep -nE 'prune|compose|--all|[[:space:]]system[[:space:]]' <<<"$code" \
      && { log_fail "TEST-3903 the library carries a bulk verb (lines above)"; ok=0; }
    n="$(command grep -cE '"\$AAI_RESIDUE_DOCKER" (rm|volume rm|network rm) ' <<<"$code")"
    [[ "$n" -eq 3 ]] || { log_fail "TEST-3903 want exactly 3 mutating call lines in the library, got $n"; ok=0; }
    # Every line that runs the CLI (a `command -v` lookup runs nothing).
    n="$(command grep -E '"\$AAI_RESIDUE_DOCKER" ' <<<"$code" | command grep -cvF 'command -v')"
    [[ "$n" -eq 9 ]] || { log_fail "TEST-3903 want exactly 9 CLI call lines (3 listings, 3 inspections, 3 removals), got $n"; ok=0; }
  else
    log_fail "TEST-3903 library not found: $LIB"; ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-3903 removals are exactly rm -f <id>, volume rm <name>, network rm <id>; no prune, compose, --all or system in the library"
}

# --- TEST-3904 (Spec-AC-04, D) -----------------------------------------------
test_3904_cap_refuses_everything_above_25() {
  local s ok=1 i
  s="$(new_stub)"
  for i in $(seq 1 26); do stub_add "$s" volume "cap-$i" "$RID" "$AFTER"; done
  lib_run "$s" "$RID" "$START"
  [[ "$LIB_RC" -eq 4 ]] || { log_fail "TEST-3904 26 candidates: exit $LIB_RC (want 4): $LIB_OUT"; ok=0; }
  command grep -qF 'REFUSED - 26 objects carry this run' <<<"$LIB_OUT" && command grep -qF 'cap of 25' <<<"$LIB_OUT" \
    || { log_fail "TEST-3904 the refusal does not name 26 and the cap 25: $LIB_OUT"; ok=0; }
  [[ -z "$(mutating_calls "$s")" ]] || { log_fail "TEST-3904 removals happened above the cap: $(mutating_calls "$s")"; ok=0; }
  [[ "$(count_obj "$s" volume)" -eq 26 ]] || { log_fail "TEST-3904 objects disappeared above the cap"; ok=0; }
  rm -f "$s/obj/volume/cap-26"
  lib_run "$s" "$RID" "$START"
  [[ "$LIB_RC" -eq 0 && "$(count_obj "$s" volume)" -eq 0 ]] \
    || { log_fail "TEST-3904 25 candidates: exit $LIB_RC, $(count_obj "$s" volume) left (want 0 and 0): $LIB_OUT"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3904 26 labelled objects: nothing removed, refusal names 26 and 25; 25: all removed"
}

# --- TEST-3905 (Spec-AC-05, E: guard) ----------------------------------------
test_3905_test_context_requires_the_stub() {
  local s ok=1 rec="$TR_TMP/rec-3905.log" marker out rc
  s="$(new_stub)"
  stub_add "$s" volume own-vol "$RID" "$AFTER"
  for marker in 1 yes; do
    rm -f "$rec"
    rc=0
    out="$(REC_LOG="$rec" AAI_RESIDUE_DOCKER="$REC_CLI" AAI_RESIDUE_IN_TEST="$marker" \
      sh -c '. "$1" || exit 99; aai_residue_cleanup "$2" "$3"' residue-case "$LIB" "$RID" "$START" 2>&1)" || rc=$?
    [[ "$rc" -eq 3 ]] || { log_fail "TEST-3905 marker [$marker], recorder CLI: exit $rc (want 3): $out"; ok=0; }
    command grep -qF 'REFUSED - this cleanup runs inside a test' <<<"$out" || { log_fail "TEST-3905 marker [$marker]: no REFUSED line: $out"; ok=0; }
    [[ -e "$rec" ]] && { log_fail "TEST-3905 marker [$marker]: the non-stub CLI was called: $(cat "$rec")"; ok=0; }
  done
  lib_run "$s" "$RID" "$START"
  [[ "$LIB_RC" -eq 0 ]] && ! has_obj "$s" volume own-vol || { log_fail "TEST-3905 the stub (sentinel present) did not proceed: exit $LIB_RC: $LIB_OUT"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3905 inside a test a CLI without the stub sentinel is refused with exit 3 before any call; the stub proceeds"
}

# --- TEST-3906 (Spec-AC-05, E: through the outer wrapper) ---------------------
test_3906_outer_wrapper_marks_inner_runs_as_tests() {
  local ok=1 rec="$TR_TMP/rec-3906.log" out rc=0
  rm -f "$rec"
  out="$(env -u AAI_RESIDUE_IN_TEST -u AAI_TEST_DOCKER -u AAI_TEST_RUN_ID -u AAI_TEST_RUN_START \
    REC_LOG="$rec" INNER_CLI="$REC_CLI" WRAP_PATH="$WRAP" bash "$WRAP" sh -c '
      echo "MARK=${AAI_RESIDUE_IN_TEST:-unset}"
      AAI_TEST_DOCKER=1 AAI_RESIDUE_DOCKER="$INNER_CLI" bash "$WRAP_PATH" sh -c "exit 0"
      echo "INNER_RC=$?"' 2>&1)" || rc=$?
  command grep -qx 'MARK=1' <<<"$out" || { log_fail "TEST-3906 the wrapped command did not see AAI_RESIDUE_IN_TEST=1: $out"; ok=0; }
  command grep -qx 'INNER_RC=13' <<<"$out" || { log_fail "TEST-3906 the inner opted-in wrapper did not exit 13: $out"; ok=0; }
  command grep -qF 'REFUSED - this cleanup runs inside a test' <<<"$out" || { log_fail "TEST-3906 no REFUSED line from the inner wrapper: $out"; ok=0; }
  [[ -e "$rec" ]] && { log_fail "TEST-3906 the non-stub CLI was called through the outer wrapper: $(cat "$rec")"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3906 the outer wrapper marks its command as a test; an inner opted-in wrapper with a non-stub CLI exits 13 without a single CLI call"
}

# --- TEST-3907 (Spec-AC-05, E: wrapper isolation) -----------------------------
test_3907_wrapper_isolates_unless_opted_in() {
  local ok=1 out rc=0 s probe
  probe='echo "DH=$DOCKER_HOST"; echo "CH=$CONTAINER_HOST"; echo "CA=$CONTAINERD_ADDRESS"; echo "DC=$DOCKER_CONTEXT"'
  out="$(env -u AAI_TEST_DOCKER DOCKER_HOST="unix://$TR_TMP/caller.sock" CONTAINER_HOST="unix://$TR_TMP/caller.sock" \
    CONTAINERD_ADDRESS="$TR_TMP/caller-containerd.sock" DOCKER_CONTEXT=caller-context bash "$WRAP" sh -c "$probe" 2>&1)" || rc=$?
  command grep -qxF "DH=$NO_DOCKER" <<<"$out" || { log_fail "TEST-3907 DOCKER_HOST not isolated: $out"; ok=0; }
  command grep -qxF "CH=$NO_DOCKER" <<<"$out" || { log_fail "TEST-3907 CONTAINER_HOST not isolated: $out"; ok=0; }
  command grep -qxF "CA=$NO_CONTAINERD" <<<"$out" || { log_fail "TEST-3907 CONTAINERD_ADDRESS not isolated: $out"; ok=0; }
  command grep -qxF "DC=default" <<<"$out" || { log_fail "TEST-3907 DOCKER_CONTEXT not reset: $out"; ok=0; }
  s="$(new_stub)"
  W_RC=0
  W_OUT="$(env -u AAI_TEST_RUN_ID AAI_TEST_DOCKER=1 AAI_RESIDUE_DOCKER="$STUB_CLI" AAI_STUB_DIR="$s" \
    DOCKER_HOST="unix://$TR_TMP/caller.sock" bash "$WRAP" sh -c "$probe" 2>&1)" || W_RC=$?
  command grep -qxF "DH=unix://$TR_TMP/caller.sock" <<<"$W_OUT" || { log_fail "TEST-3907 the opt-in did not pass the caller's DOCKER_HOST through: $W_OUT"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3907 without the opt-in the command sees four unreachable daemon variables; with it, the caller's DOCKER_HOST"
}

# --- TEST-3908 (Spec-AC-05, E: framework isolation) ---------------------------
test_3908_framework_isolates_every_suite() {
  local ok=1 d out rc=0 probe="$TR_TMP/probe-3908.txt"
  d="$TR_TMP/fw-3908"
  mkdir -p "$d/tests/skills/lib" "$d/.aai/scripts/lib" "$d/docs/ai/tests"
  cp "$FRAMEWORK" "$d/tests/skills/test-framework.sh"
  cp "$PROJECT_ROOT/tests/skills/lib/pipe-safe.sh" "$d/tests/skills/lib/pipe-safe.sh"
  cp "$PROJECT_ROOT/.aai/scripts/lib/repo-tripwire.sh" "$d/.aai/scripts/lib/repo-tripwire.sh"
  cp "$PROJECT_ROOT/.aai/scripts/lib/append-lock.sh" "$d/.aai/scripts/lib/append-lock.sh"
  printf 'tests/skills/results/\ndocs/ai/tests/test-runs.jsonl\n' > "$d/.gitignore"
  cat > "$d/tests/skills/test-aai-envprobe.sh" <<'EOS'
#!/usr/bin/env bash
{
  echo "DH=${DOCKER_HOST-unset}"
  echo "CH=${CONTAINER_HOST-unset}"
  echo "CA=${CONTAINERD_ADDRESS-unset}"
  echo "DC=${DOCKER_CONTEXT-unset}"
  echo "IT=${AAI_RESIDUE_IN_TEST-unset}"
  echo "OPT=${AAI_TEST_DOCKER-unset}"
  echo "RUNID=${AAI_TEST_RUN_ID-unset}"
} > "$PROBE_OUT"
exit 0
EOS
  ( cd "$d" && git init -q -b main && git config user.email t@example.com && git config user.name fixture \
      && git add -A && git commit -q -m fixture ) || { log_fail "TEST-3908 fixture repo init failed"; return; }
  out="$(cd "$d" && env -u AAI_RESIDUE_IN_TEST AAI_TEST_ISOLATION=0 AAI_TEST_DOCKER=1 AAI_TEST_RUN_ID="$RID" \
    DOCKER_HOST="unix://$TR_TMP/caller.sock" CONTAINER_HOST="unix://$TR_TMP/caller.sock" \
    CONTAINERD_ADDRESS="$TR_TMP/caller-containerd.sock" DOCKER_CONTEXT=caller-context PROBE_OUT="$probe" \
    bash tests/skills/test-framework.sh 2>&1)" || rc=$?
  [[ -f "$probe" ]] || { log_fail "TEST-3908 the fixture suite never ran (framework exit $rc): $out"; return; }
  local want
  for want in "DH=$NO_DOCKER" "CH=$NO_DOCKER" "CA=$NO_CONTAINERD" "DC=default" "IT=1" "OPT=unset" "RUNID=unset"; do
    command grep -qxF "$want" "$probe" || { log_fail "TEST-3908 the suite's environment lacks $want: $(tr '\n' ' ' < "$probe")"; ok=0; }
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-3908 a framework suite sees the unreachable daemon variables, the test marker, and no opt-in or run id from its caller"
}

# --- TEST-3909 (Spec-AC-06, F: two independent layers) -------------------------
test_3909_two_layers_under_the_incident_mutation() {
  local ok=1 s m1="$TR_TMP/lib-m1.sh" m2="$TR_TMP/lib-m2.sh"
  [[ -f "$LIB" ]] || { log_fail "TEST-3909 library not found: $LIB"; return; }
  sed 's/ --filter "\$rl_filter"//g' "$LIB" > "$m1"
  sed 's/aai_residue_list "\$rc_kind" "\$rc_id"/aai_residue_list "$rc_kind" '"''"'/' "$LIB" > "$m2"
  cmp -s "$LIB" "$m1" && { log_fail "TEST-3909 the filter-dropping mutation did not apply"; ok=0; }
  cmp -s "$LIB" "$m2" && { log_fail "TEST-3909 the empty-id mutation did not apply"; ok=0; }

  # Control: the unmutated library passes the filter check.
  s="$(new_stub)"
  stub_add "$s" volume own-vol "$RID" "$AFTER"
  lib_run "$s" "$RID" "$START"
  filter_check "$s" "$RID" || { log_fail "TEST-3909 control: the unmutated library failed the filter check"; ok=0; }

  # Layer 1 catches the dropped filter; layer 2 still protects every
  # object this run does not own (the stub lists everything without a filter).
  s="$(new_stub)"
  stub_add "$s" container "$(hexid 11)" "$RID" "$AFTER"
  stub_add "$s" volume own-vol "$RID" "$AFTER"
  stub_add "$s" volume unlabelled-vol - "$AFTER"
  stub_add "$s" volume foreign-vol "$OTHER_RID" "$AFTER"
  stub_add "$s" network "$(hexid 12)" - "$AFTER"
  stub_add "$s" container "$(hexid 13)" "$OTHER_RID" "$AFTER"
  lib_run "$s" "$RID" "$START" "$m1"
  filter_check "$s" "$RID" && { log_fail "TEST-3909 the filter check did not catch the dropped filter"; ok=0; }
  has_obj "$s" volume unlabelled-vol || { log_fail "TEST-3909 filter dropped: the unlabelled volume was removed: $LIB_OUT"; ok=0; }
  has_obj "$s" volume foreign-vol || { log_fail "TEST-3909 filter dropped: the foreign volume was removed: $LIB_OUT"; ok=0; }
  has_obj "$s" network "$(hexid 12)" || { log_fail "TEST-3909 filter dropped: the unlabelled network was removed: $LIB_OUT"; ok=0; }
  has_obj "$s" container "$(hexid 13)" || { log_fail "TEST-3909 filter dropped: the foreign container was removed: $LIB_OUT"; ok=0; }
  has_obj "$s" volume own-vol && { log_fail "TEST-3909 filter dropped: the owned volume was not removed: $LIB_OUT"; ok=0; }

  # The incident's literal shape: an empty id handed to the listing.
  s="$(new_stub)"
  stub_add "$s" volume own-vol "$RID" "$AFTER"
  stub_add "$s" volume unlabelled-vol - "$AFTER"
  lib_run "$s" "$RID" "$START" "$m2"
  [[ "$LIB_RC" -eq 2 ]] || { log_fail "TEST-3909 empty id to the listing: exit $LIB_RC (want 2): $LIB_OUT"; ok=0; }
  [[ "$(count_obj "$s" volume)" -eq 2 && -z "$(mutating_calls "$s")" ]] \
    || { log_fail "TEST-3909 empty id to the listing: something was removed"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3909 a dropped filter is caught by the filter check and the per-object check still removes only owned objects; an empty id to the listing refuses with exit 2"
}

# --- TEST-3910 (Spec-AC-06, F: the mutation runner isolates) --------------------
test_3910_mutation_runner_isolates_the_suite() {
  local ok=1 fx="$TR_TMP/mr-3910" out rc=0 rec
  mkdir -p "$fx/.aai/scripts" "$fx/tests/skills" "$fx/lib" "$fx/docs/specs"
  # The fixture's wrapper passes its environment through untouched, so the
  # suite sees exactly what mutation-run.mjs gave the wrapper.
  printf '#!/bin/sh\nexec "$@"\n' > "$fx/.aai/scripts/aai-run-tests.sh"
  printf 'docs/ai/tdd/\n' > "$fx/.gitignore"
  printf 'a\n' > "$fx/lib/x.txt"
  cat > "$fx/tests/skills/fixture-suite.sh" <<'EOS'
#!/usr/bin/env bash
test_9100_env() {
  echo "FAIL TEST-9100 env DH=[${DOCKER_HOST-unset}] IT=[${AAI_RESIDUE_IN_TEST-unset}] OPT=[${AAI_TEST_DOCKER-unset}] RUNID=[${AAI_TEST_RUN_ID-unset}]" >&2
  exit 1
}
"$1"
EOS
  printf -- '---\nid: fixture-spec-3910\ntype: spec\nstatus: implementing\n---\n\n# Fixture\n' > "$fx/docs/specs/fixture-spec.md"
  ( cd "$fx" && git init -q -b main && git config user.email t@example.com && git config user.name fixture \
      && git add -A && git commit -q -m base ) || { log_fail "TEST-3910 fixture repo init failed"; return; }
  out="$(cd "$fx" && env -u AAI_RESIDUE_IN_TEST AAI_TEST_DOCKER=1 AAI_TEST_RUN_ID="$RID" \
    DOCKER_HOST="unix://$TR_TMP/caller.sock" node "$MUTATION_RUN" --spec docs/specs/fixture-spec.md \
    --test-id TEST-9100 --suite tests/skills/fixture-suite.sh --selector test_9100_env \
    --target lib/x.txt --sed 's/a/b/' 2>&1)" || rc=$?
  rec="$fx/docs/ai/tdd/fixture-spec-3910/mutation-TEST-9100.txt"
  [[ -f "$rec" ]] || { log_fail "TEST-3910 no mutation record (exit $rc): $out"; return; }
  command grep -qF "DH=[$NO_DOCKER]" "$rec" || { log_fail "TEST-3910 the suite saw a reachable DOCKER_HOST: $(command grep -F 'TEST-9100 env' "$rec")"; ok=0; }
  command grep -qF "IT=[1]" "$rec" || { log_fail "TEST-3910 the suite was not marked as a test: $(command grep -F 'TEST-9100 env' "$rec")"; ok=0; }
  command grep -qF "OPT=[unset]" "$rec" || { log_fail "TEST-3910 the caller's AAI_TEST_DOCKER reached the suite: $(command grep -F 'TEST-9100 env' "$rec")"; ok=0; }
  command grep -qF "RUNID=[unset]" "$rec" || { log_fail "TEST-3910 the caller's AAI_TEST_RUN_ID reached the suite: $(command grep -F 'TEST-9100 env' "$rec")"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3910 mutation-run.mjs hands its suite an unreachable DOCKER_HOST, AAI_RESIDUE_IN_TEST=1 and no opt-in or run id"
}

# --- TEST-3911 (Spec-AC-07, G) -------------------------------------------------
test_3911_report_and_dry_run() {
  local s ok=1
  s="$(new_stub)"
  stub_add "$s" container "$(hexid 21)" "$RID" "$AFTER"
  stub_add "$s" volume own-vol "$RID" "$AFTER"
  stub_add "$s" volume old-vol "$RID" "$BEFORE"
  stub_add "$s" network "$(hexid 22)" "$RID" "$AFTER" 'rm=fail'
  AAI_RESIDUE_DRY_RUN=1 lib_run "$s" "$RID" "$START"
  command grep -qF "AAI-RESIDUE: would delete container $(hexid 21)" <<<"$LIB_OUT" \
    && command grep -qF "AAI-RESIDUE: would delete volume own-vol" <<<"$LIB_OUT" \
    || { log_fail "TEST-3911 dry run: no would-delete lines: $LIB_OUT"; ok=0; }
  command grep -qF "AAI-RESIDUE: run $RID (dry run): would delete 3, skipped 1" <<<"$LIB_OUT" \
    || { log_fail "TEST-3911 dry run: no dry-run summary: $LIB_OUT"; ok=0; }
  [[ -z "$(mutating_calls "$s")" ]] || { log_fail "TEST-3911 dry run removed something: $(mutating_calls "$s")"; ok=0; }
  [[ "$(count_obj "$s" volume)" -eq 2 && "$(count_obj "$s" container)" -eq 1 ]] || { log_fail "TEST-3911 dry run: objects disappeared"; ok=0; }

  lib_run "$s" "$RID" "$START"
  command grep -qF "AAI-RESIDUE: deleted container $(hexid 21) (label and creation time match this run)" <<<"$LIB_OUT" \
    && command grep -qF "AAI-RESIDUE: deleted volume own-vol (label and creation time match this run)" <<<"$LIB_OUT" \
    || { log_fail "TEST-3911 no deleted lines: $LIB_OUT"; ok=0; }
  command grep -qF "AAI-RESIDUE: skipped volume old-vol - created $BEFORE, before this run started" <<<"$LIB_OUT" \
    || { log_fail "TEST-3911 no skipped line with its reason: $LIB_OUT"; ok=0; }
  command grep -qF "AAI-RESIDUE: FAILED to delete network $(hexid 22)" <<<"$LIB_OUT" \
    || { log_fail "TEST-3911 no line for the failed removal: $LIB_OUT"; ok=0; }
  command grep -qF "AAI-RESIDUE: run $RID: deleted 2, skipped 1, failed 1" <<<"$LIB_OUT" \
    || { log_fail "TEST-3911 no summary with the three counts: $LIB_OUT"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3911 one line per deleted, kept and failed object and a summary; the dry run reports and removes nothing"
}

# --- TEST-3912 (Spec-AC-08, H) -------------------------------------------------
test_3912_no_daemon_is_a_noted_no_op() {
  local ok=1 s code n
  for code in 0 3; do
    s="$(new_stub)"
    WRAP_CLI="$TR_TMP/bin/no-such-docker" wrap_optin "$s" sh -c "exit $code"
    [[ "$W_RC" -eq "$code" ]] || { log_fail "TEST-3912 absent CLI, command exit $code: wrapper exit $W_RC: $W_OUT"; ok=0; }
    n="$(command grep -c '^AAI-RESIDUE:' <<<"$W_OUT")"
    [[ "$n" -eq 1 ]] && command grep -qF 'AAI-RESIDUE: NOTE - no container CLI' <<<"$W_OUT" \
      || { log_fail "TEST-3912 absent CLI: want exactly one AAI-RESIDUE NOTE line, got $n: $W_OUT"; ok=0; }

    s="$(new_stub)"
    stub_add "$s" volume own-vol "$RID" "$AFTER"
    : > "$s/down"
    wrap_optin "$s" sh -c "exit $code"
    [[ "$W_RC" -eq "$code" ]] || { log_fail "TEST-3912 daemon down, command exit $code: wrapper exit $W_RC: $W_OUT"; ok=0; }
    n="$(command grep -c '^AAI-RESIDUE:' <<<"$W_OUT")"
    [[ "$n" -eq 1 ]] && command grep -qF 'AAI-RESIDUE: NOTE - the container daemon did not answer' <<<"$W_OUT" \
      || { log_fail "TEST-3912 daemon down: want exactly one AAI-RESIDUE NOTE line, got $n: $W_OUT"; ok=0; }
    [[ -z "$(mutating_calls "$s")" ]] || { log_fail "TEST-3912 daemon down: a removal was attempted"; ok=0; }

    # A CLI that itself exits 2 is a daemon error, not a refusal (review NB-1).
    s="$(new_stub)"
    : > "$s/down2"
    wrap_optin "$s" sh -c "exit $code"
    [[ "$W_RC" -eq "$code" ]] || { log_fail "TEST-3912 CLI exiting 2, command exit $code: wrapper exit $W_RC: $W_OUT"; ok=0; }
    n="$(command grep -c '^AAI-RESIDUE:' <<<"$W_OUT")"
    [[ "$n" -eq 1 ]] && command grep -qF 'AAI-RESIDUE: NOTE - the container daemon did not answer' <<<"$W_OUT" \
      || { log_fail "TEST-3912 CLI exiting 2: want exactly one AAI-RESIDUE NOTE line, got $n: $W_OUT"; ok=0; }
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-3912 an absent CLI or a daemon that does not answer: one NOTE line, no removal, the command's exit code kept (0 and 3)"
}

# --- TEST-3913 (Spec-AC-09, the wrapper seam) -----------------------------------
test_3913_wrapper_end_to_end_on_the_stub() {
  local ok=1 s
  s="$(new_stub)"
  stub_add "$s" volume pre-unlabelled - "$BEFORE"
  stub_add "$s" volume pre-other-run "$OTHER_RID" "$BEFORE"
  wrap_optin "$s" sh -c '
    "$AAI_RESIDUE_DOCKER" run -d --label "aai.test.run=$AAI_TEST_RUN_ID" busybox >/dev/null
    "$AAI_RESIDUE_DOCKER" volume create --label "aai.test.run=$AAI_TEST_RUN_ID" leak-vol >/dev/null
    "$AAI_RESIDUE_DOCKER" network create --label "aai.test.run=$AAI_TEST_RUN_ID" leak-net >/dev/null
    echo "SEEN RID=$AAI_TEST_RUN_ID START=$AAI_TEST_RUN_START"
    exit 1'
  [[ "$W_RC" -eq 1 ]] || { log_fail "TEST-3913 wrapper exit $W_RC (want the command's 1): $W_OUT"; ok=0; }
  command grep -qE '^SEEN RID=aai-[0-9]{10}-[0-9]+-[0-9a-f]{8} START=[0-9]{10}$' <<<"$W_OUT" \
    || { log_fail "TEST-3913 the command did not receive a run id and start: $W_OUT"; ok=0; }
  [[ "$(count_obj "$s" container)" -eq 0 && "$(count_obj "$s" network)" -eq 0 ]] \
    || { log_fail "TEST-3913 the labelled container or network survived: $W_OUT"; ok=0; }
  has_obj "$s" volume leak-vol && { log_fail "TEST-3913 the labelled volume survived: $W_OUT"; ok=0; }
  has_obj "$s" volume pre-unlabelled && has_obj "$s" volume pre-other-run \
    || { log_fail "TEST-3913 a pre-existing object was removed: $W_OUT"; ok=0; }

  s="$(new_stub)"
  AAI_TEST_TIMEOUT=2 wrap_optin "$s" sh -c '
    "$AAI_RESIDUE_DOCKER" volume create --label "aai.test.run=$AAI_TEST_RUN_ID" hung-vol >/dev/null
    sleep 30'
  [[ "$W_RC" -eq 124 ]] || { log_fail "TEST-3913 watchdog: wrapper exit $W_RC (want 124): $W_OUT"; ok=0; }
  has_obj "$s" volume hung-vol && { log_fail "TEST-3913 watchdog: the labelled volume survived: $W_OUT"; ok=0; }

  s="$(new_stub)"
  W_RC=0
  W_OUT="$(AAI_TEST_DOCKER=1 AAI_TEST_RUN_ID="$RID" AAI_TEST_RUN_START="$START" AAI_RESIDUE_DOCKER="$STUB_CLI" \
    AAI_STUB_DIR="$s" bash "$WRAP" sh -c 'exit 0' 2>&1)" || W_RC=$?
  [[ "$W_RC" -eq 0 && ! -s "$s/calls.log" ]] || { log_fail "TEST-3913 an inherited run id: exit $W_RC, calls [$(cat "$s/calls.log")] (want 0 and none)"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3913 the wrapper's run id is the label the command writes and the cleanup removes (exit 1 and watchdog 124 kept); pre-existing objects stay; a nested wrapper makes no call"
}

# --- TEST-3914 (Spec-AC-10) ------------------------------------------------------
test_3914_classification_and_consumer_record() {
  local ok=1 n
  n="$(awk '/^[a-z_]+:/ { sect = $1 } $0 == "  - .aai/scripts/lib/test-residue.sh" { print sect }' .aai/system/PROFILES.yaml)"
  [[ "$n" == "core:" ]] || { log_fail "TEST-3914 PROFILES.yaml lists the library under [$n] (want exactly once, under core)"; ok=0; }
  command grep -qF 'AAI_TEST_DOCKER' docs/TECHNOLOGY.md && command grep -qE 'exit(s)? 13|13 ' docs/TECHNOLOGY.md \
    || { log_fail "TEST-3914 docs/TECHNOLOGY.md does not name AAI_TEST_DOCKER and exit 13"; ok=0; }
  # A release cut rolls the heading to its version; both forms count.
  command grep -qE '^## \[(unreleased|v[0-9]{4}\.[0-9]{2}\.[0-9]{2})\] — .*container residue' CHANGELOG.md \
    || { log_fail "TEST-3914 CHANGELOG.md has no unreleased per-entry heading for the container residue change"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3914 the library is classified core once; TECHNOLOGY and CHANGELOG carry the consumer record"
}

# =============================================================================
# spec-test-residue-files-and-processes (TEST-3923 to TEST-3930): the run temp
# root and the leftover processes. SAFETY RULE OF THESE CASES: everything that
# can be removed or signalled is created by the case itself inside a sandbox
# directory under this suite's scratch directory; every pid a case starts is a
# detached `sleep 127` recorded in the sandbox's pids file, and the case reaps
# exactly those pids (after checking they are still a `sleep 127`) at its end.
# The library refuses, in a test context, to signal any pid not in that file.
# =============================================================================
TID='aai-1795089600-4242-0123abcd'
TID_OTHER='aai-1795089600-4242-ffffffff'
SB_ALL=''

# sandbox_new <name> — a fresh physical directory for one case.
sandbox_new() {
  local d="$TR_TMP/sb-$1"
  rm -rf "$d"
  mkdir -p "$d" && (cd "$d" && pwd -P)
}

# sb_spawn <sandbox> <keep9|close9|fd8|keep9-unlisted> <marker> — start a detached `sleep 127`
# reparented to init (double fork, new session); print its pid and record it in <sandbox>/pids
# (keep9-unlisted records it in <sandbox>/own-pids only, for the case's own reap).
sb_spawn() {
  local sb="$1" how="$2" m="$3" pf="$1/pids.tmp" pid
  rm -f "$pf"
  case "$how" in
    keep9|keep9-unlisted) ( perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' -- sleep 127 9<"$m" </dev/null >/dev/null 2>&1 & echo $! > "$pf" ) ;;
    close9) ( perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' -- sleep 127 9<&- </dev/null >/dev/null 2>&1 & echo $! > "$pf" ) ;;
    fd8) ( perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' -- sleep 127 8<"$m" 9<&- </dev/null >/dev/null 2>&1 & echo $! > "$pf" ) ;;
  esac
  pid="$(cat "$pf")"
  rm -f "$pf"
  echo "$pid" >> "$sb/own-pids"
  [[ "$how" == keep9-unlisted ]] || echo "$pid" >> "$sb/pids"
  SB_ALL="$SB_ALL $sb"
  sleep 0.3
  printf '%s\n' "$pid"
}

# alive <pid> — 0 while the pid runs (a zombie does not count).
alive() {
  local st
  st="$(ps -o stat= -p "$1" 2>/dev/null)" || return 1
  case "$st" in '' | *Z*) return 1 ;; esac
  return 0
}

# gone_within <pid> <seconds>
gone_within() {
  local i=0
  while [[ $i -lt $(( $2 * 10 )) ]]; do alive "$1" || return 0; sleep 0.1; i=$((i + 1)); done
  return 1
}

# sb_reap <sandbox> — kill the case's own sleeps, each only while it is still a `sleep 127`.
sb_reap() {
  local p c
  [[ -f "$1/own-pids" ]] || return 0
  while IFS= read -r p; do
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    c="$(ps -o command= -p "$p" 2>/dev/null || true)"
    [[ "$c" == "sleep 127" ]] && kill "$p" 2>/dev/null
  done < "$1/own-pids"
  return 0
}
reap_all_sandboxes() { local s; for s in $SB_ALL; do sb_reap "$s"; done; }

# tree_wrap <sandbox> <cmd...> — the REAL wrapper as a test-context run with this sandbox; sets W_OUT, W_RC.
tree_wrap() {
  local sb="$1"
  shift
  W_RC=0
  W_OUT="$(env -u AAI_TEST_OWNER -u AAI_TEST_OWNER_START AAI_RESIDUE_IN_TEST=1 AAI_RESIDUE_SANDBOX="$sb" TMPDIR="$sb" \
    WRAP_PATH="$WRAP" AAI_TEST_TIMEOUT="${TREE_TIMEOUT:-60}" bash "$WRAP" "$@" 2>&1)" || W_RC=$?
}

# lib_tree <sandbox> <lib> <function> [args...] — one library call in sandbox mode; sets T_OUT, T_RC.
lib_tree() {
  local sb="$1" lib="$2"
  shift 2
  T_RC=0
  T_OUT="$(AAI_RESIDUE_IN_TEST=1 AAI_RESIDUE_SANDBOX="$sb" TMPDIR="$sb" AAI_RESIDUE_LSOF="${TREE_LSOF:-lsof}" \
    AAI_RESIDUE_DRY_RUN="${AAI_RESIDUE_DRY_RUN:-0}" sh -c '. "$1" || exit 99; shift; "$@"' tree-case "$lib" "$@" 2>&1)" || T_RC=$?
}

# lsof_shim <sandbox> [lie26 <pid>] — a logging lsof that runs the real one (or, for lie26, answers every
# listing call with 26 copies of the given pid); its log is <sandbox>/lsof.log.
lsof_shim() {
  local real
  real="$(command -v lsof)"
  mkdir -p "$1/bin"
  {
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> %q\n' "$1/lsof.log"
    if [[ "${2:-}" == lie26 ]]; then
      printf 'case " $* " in *" -p "*) ;; *) %q "$@"; rc=$?; i=0; while [ $i -lt 26 ]; do echo p%s; i=$((i+1)); done; exit $rc ;; esac\n' "$real" "$3"
    fi
    if [[ "${2:-}" == silent1 ]]; then
      printf 'case " $* " in *" -p "*) ;; *) exit 1 ;; esac\n'
    fi
    if [[ "${2:-}" == fail ]]; then
      printf 'case " $* " in *" -p "*) ;; *) echo "lsof: simulated failure" >&2; exit 1 ;; esac\n'
    fi
    if [[ "${2:-}" == partial ]]; then
      printf 'case " $* " in *" -p "*) ;; *) echo p%s; exit 2 ;; esac\n' "$3"
    fi
    printf 'exec %q "$@"\n' "$real"
  } > "$1/bin/lsof"
  chmod +x "$1/bin/lsof"
  printf '%s\n' "$1/bin/lsof"
}

# listing_filter_ok <sandbox> <marker> — 0 when every listing call in the shim log carried -a, -d 9 and the marker.
listing_filter_ok() {
  local line n=0
  [[ -f "$1/lsof.log" ]] || return 1
  while IFS= read -r line; do
    [[ " $line " == *" -p "* ]] && continue
    n=$((n + 1))
    [[ " $line " == *" -a "* && " $line " == *" -d 9 "* && " $line " == *" $2"* ]] || return 1
  done < "$1/lsof.log"
  [[ $n -ge 1 ]]
}

need_lsof() {
  command -v lsof >/dev/null 2>&1 && command -v perl >/dev/null 2>&1 && return 0
  [[ -z "${CI:-}" ]] || { log_fail "$1 lsof and perl are required on CI"; return 1; }
  echo "SKIP-CASE: $1 needs lsof and perl"
  return 1
}

# --- TEST-3923 (Spec-AC-01: the owner's temp root) ----------------------------
test_3923_owner_temp_root_lifecycle() {
  local ok=1 sb sb2 tmp mark owner
  sb="$(sandbox_new 3923)"
  tree_wrap "$sb" sh -c 'echo "TMP=$TMPDIR"; echo "OWNER=$AAI_TEST_OWNER $AAI_TEST_OWNER_START"; echo "MARK=$(cat "$TMPDIR/.aai-test-run" 2>/dev/null)"; mkdir -p "$TMPDIR/sub" && echo x > "$TMPDIR/sub/f"; bash "$WRAP_PATH" sh -c "echo INNER=\$TMPDIR"; exit 0'
  tmp="$(sed -n 's/^TMP=//p' <<<"$W_OUT")"
  owner="$(sed -n 's/^OWNER=//p' <<<"$W_OUT")"
  mark="$(sed -n 's/^MARK=//p' <<<"$W_OUT")"
  [[ "$W_RC" -eq 0 ]] || { log_fail "TEST-3923 pass run exited $W_RC: $W_OUT"; ok=0; }
  [[ "$tmp" =~ ^"$sb"/aai-tr-[0-9a-f]{8}$ ]] || { log_fail "TEST-3923 the command saw TMPDIR [$tmp], want $sb/aai-tr-<8 hex>: $W_OUT"; ok=0; }
  [[ -n "$mark" && "$mark" == "$owner" ]] || { log_fail "TEST-3923 the marker [$mark] does not name the owner and start [$owner]"; ok=0; }
  command grep -qxF "INNER=$tmp" <<<"$W_OUT" || { log_fail "TEST-3923 a nested wrapper made its own root or lost TMPDIR: $W_OUT"; ok=0; }
  [[ -n "$tmp" && ! -e "$tmp" ]] || { log_fail "TEST-3923 the root $tmp is still there after a pass"; ok=0; }
  tree_wrap "$sb" sh -c 'exit 3'
  [[ "$W_RC" -eq 3 ]] || { log_fail "TEST-3923 fail run exited $W_RC, want 3: $W_OUT"; ok=0; }
  TREE_TIMEOUT=2 tree_wrap "$sb" sh -c 'sleep 30'
  [[ "$W_RC" -eq 124 ]] || { log_fail "TEST-3923 watchdog run exited $W_RC, want 124: $W_OUT"; ok=0; }
  ls -d "$sb"/aai-tr-* >/dev/null 2>&1 && { log_fail "TEST-3923 a root is left after the fail or watchdog run: $(ls -a "$sb")"; ok=0; }
  sb2="$(sandbox_new 3923-off)"
  W_RC=0
  W_OUT="$(env -u AAI_TEST_OWNER -u AAI_TEST_OWNER_START -u AAI_RESIDUE_SANDBOX AAI_RESIDUE_IN_TEST=1 TMPDIR="$sb2" \
    bash "$WRAP" sh -c 'echo "TMP=$TMPDIR"' 2>&1)" || W_RC=$?
  command grep -qxF "TMP=$sb2" <<<"$W_OUT" || { log_fail "TEST-3923 a test-context wrapper without a sandbox changed TMPDIR: $W_OUT"; ok=0; }
  command grep -qF 'AAI-RESIDUE' <<<"$W_OUT" && { log_fail "TEST-3923 a test-context wrapper without a sandbox printed an AAI-RESIDUE line: $W_OUT"; ok=0; }
  ls -d "$sb2"/aai-tr-* >/dev/null 2>&1 && { log_fail "TEST-3923 a test-context wrapper without a sandbox made a root"; ok=0; }
  # an owning wrapper outside a test whose library is missing says the cleanup is unavailable (nothing can be removed)
  sb2="$(sandbox_new 3923-nolib)"
  mkdir -p "$sb2/w/.aai/scripts"
  cp "$WRAP" "$sb2/w/.aai/scripts/aai-run-tests.sh"
  W_RC=0
  W_OUT="$(cd "$sb2/w" && env -u AAI_TEST_OWNER -u AAI_TEST_OWNER_START -u AAI_RESIDUE_IN_TEST -u AAI_RESIDUE_SANDBOX TMPDIR="$sb2" \
    bash .aai/scripts/aai-run-tests.sh sh -c 'exit 0' 2>&1)" || W_RC=$?
  command grep -qF 'AAI-RESIDUE: NOTE - lib/test-residue.sh not found' <<<"$W_OUT" || { log_fail "TEST-3923 a missing residue library was silent on an owning run: rc $W_RC $W_OUT"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3923 the owning wrapper hands its command a private aai-tr-<hex> root with a marker naming the owner, removes it after a pass, a failure and a watchdog kill; nested and off-mode wrappers make none"
}

# --- TEST-3924 (Spec-AC-02: a root that is not provably this run's is kept) ---
test_3924_tampered_roots_are_kept() {
  local ok=1 sb st root t why
  sb="$(sandbox_new 3924)"
  st=$(( $(date +%s) - 5 ))
  root="$sb/aai-tr-0123abcd"
  # mk_root <dir> <marker line or ""> — a directory with a file in it and, optionally, a marker.
  mk_root() { rm -rf "$1"; mkdir -p "$1"; echo keep > "$1/keep.txt"; [[ -z "$2" ]] || printf '%s\n' "$2" > "$1/.aai-test-run"; }
  kept() { # kept <label> <dir> <reason fragment>
    [[ -f "$2/keep.txt" ]] || { log_fail "TEST-3924 ($1) $2 was removed: $T_OUT"; ok=0; return; }
    command grep -qF -- "$3" <<<"$T_OUT" || { log_fail "TEST-3924 ($1) the output does not name the reason [$3]: $T_OUT"; ok=0; }
  }
  # control: a valid root is removed
  mk_root "$root" "$TID $st"
  lib_tree "$sb" "$LIB" aai_residue_tmp_cleanup "$TID" "$st" "$sb" "$root"
  [[ "$T_RC" -eq 0 && ! -e "$root" ]] || { log_fail "TEST-3924 control: a valid root was not removed (rc $T_RC): $T_OUT"; ok=0; }
  mk_root "$sb/aai-tr-deadbeef" "$TID $st"
  lib_tree "$sb" "$LIB" aai_residue_tmp_cleanup "$TID" "$st" "$sb" "$sb/aai-tr-deadbeef"
  kept "wrong name" "$sb/aai-tr-deadbeef" "kept temp root"
  mk_root "$sb/target" "$TID $st"; rm -rf "$root"; ln -s "$sb/target" "$root"
  lib_tree "$sb" "$LIB" aai_residue_tmp_cleanup "$TID" "$st" "$sb" "$root"
  kept "symlink" "$sb/target" "symlink"
  [[ -L "$root" ]] || { log_fail "TEST-3924 (symlink) the link itself was removed"; ok=0; }
  rm -f "$root"
  mk_root "$root" ""
  lib_tree "$sb" "$LIB" aai_residue_tmp_cleanup "$TID" "$st" "$sb" "$root"
  kept "no marker" "$root" "marker"
  mk_root "$root" "$TID_OTHER $st"
  lib_tree "$sb" "$LIB" aai_residue_tmp_cleanup "$TID" "$st" "$sb" "$root"
  kept "foreign marker" "$root" "marker"
  mk_root "$root" "$TID $st"; touch -t 202001010000 "$root/.aai-test-run"
  lib_tree "$sb" "$LIB" aai_residue_tmp_cleanup "$TID" "$st" "$sb" "$root"
  kept "old marker" "$root" "older than"
  mk_root "$root" "$TID $st"
  lib_tree "$sb" "$LIB" aai_residue_tmp_cleanup "$TID" "$st" "" "$root"
  kept "empty base" "$root" "REFUSED"
  [[ "$T_RC" -eq 2 ]] || { log_fail "TEST-3924 (empty base) exit $T_RC, want 2"; ok=0; }
  ( cd "$sb" && lib_tree "$sb" "$LIB" aai_residue_tmp_cleanup "$TID" "$st" "." "./aai-tr-0123abcd"; printf '%s' "$T_OUT" > "$sb/rel.out" )
  T_OUT="$(cat "$sb/rel.out")"
  kept "relative base" "$root" "base"
  lib_tree "$sb" "$LIB" aai_residue_tmp_cleanup "$TID" "$st" "/" "/aai-tr-0123abcd"
  command grep -qF 'base' <<<"$T_OUT" || { log_fail "TEST-3924 (slash base) no reason: $T_OUT"; ok=0; }
  T_RC=0
  T_OUT="$(HOME="$sb" AAI_RESIDUE_IN_TEST=1 AAI_RESIDUE_SANDBOX="$sb" TMPDIR="$sb" \
    sh -c '. "$1" || exit 99; shift; "$@"' tree-case "$LIB" aai_residue_tmp_cleanup "$TID" "$st" "$sb" "$root" 2>&1)" || T_RC=$?
  kept "HOME base" "$root" "HOME"
  # a base the cleanup would refuse (HOME) is refused at creation too, so no root is made that cannot be removed
  T_RC=0
  T_OUT="$(HOME="$sb" AAI_RESIDUE_IN_TEST=1 AAI_RESIDUE_SANDBOX="$sb" TMPDIR="$sb" \
    sh -c '. "$1" || exit 99; shift; "$@"' tree-case "$LIB" aai_residue_tmp_create "$TID_OTHER" "$st" "$sb" 2>&1)" || T_RC=$?
  [[ "$T_RC" -ne 0 && ! -e "$sb/aai-tr-ffffffff" ]] || { log_fail "TEST-3924 a root was created under HOME, which the cleanup refuses (rc $T_RC)"; ok=0; rm -rf "$sb/aai-tr-ffffffff"; }
  # a marker that cannot be written (file size limit) rolls the new root back
  T_RC=0
  T_OUT="$(AAI_RESIDUE_IN_TEST=1 AAI_RESIDUE_SANDBOX="$sb" TMPDIR="$sb" \
    sh -c 'trap "" XFSZ; ulimit -f 0; . "$1" || exit 99; shift; "$@"' tree-case "$LIB" aai_residue_tmp_create "$TID_OTHER" "$st" "$sb" 2>&1)" || T_RC=$?
  [[ "$T_RC" -ne 0 ]] || { log_fail "TEST-3924 a root whose marker could not be written was reported as made: $T_OUT"; ok=0; }
  [[ ! -e "$sb/aai-tr-ffffffff" ]] || { log_fail "TEST-3924 a root whose marker could not be written was left behind"; ok=0; }
  for t in "" "aai-x" ; do
    lib_tree "$sb" "$LIB" aai_residue_tmp_cleanup "$t" "$st" "$sb" "$root"
    [[ "$T_RC" -eq 2 && -f "$root/keep.txt" ]] || { log_fail "TEST-3924 id [$t]: exit $T_RC (want 2) or the root was touched: $T_OUT"; ok=0; }
  done
  lib_tree "$sb" "$LIB" aai_residue_tmp_cleanup "$TID" "12a" "$sb" "$root"
  [[ "$T_RC" -eq 2 && -f "$root/keep.txt" ]] || { log_fail "TEST-3924 start 12a: exit $T_RC (want 2) or the root was touched: $T_OUT"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3924 a valid root is removed; a wrong name, a symlink, a missing, foreign or old marker, an empty, relative, slash or HOME base each keep the directory with the reason; a bad id or start exits 2"
}

# --- TEST-3925 (Spec-AC-03: outside the root is reported, never removed) ------
test_3925_outside_entries_reported_and_kept() {
  local ok=1 sb
  sb="$(sandbox_new 3925)"
  tree_wrap "$sb" sh -c 'sleep 1; echo x > "$AAI_RESIDUE_SANDBOX/outside.txt"; echo y > "$TMPDIR/inside.txt"'
  [[ "$W_RC" -eq 0 ]] || { log_fail "TEST-3925 wrapper exited $W_RC: $W_OUT"; ok=0; }
  [[ -f "$sb/outside.txt" ]] || { log_fail "TEST-3925 outside.txt was removed"; ok=0; }
  command grep -qE 'AAI-RESIDUE: NOTE.*outside\.txt' <<<"$W_OUT" || { log_fail "TEST-3925 no NOTE line names outside.txt: $W_OUT"; ok=0; }
  ls -d "$sb"/aai-tr-* >/dev/null 2>&1 && { log_fail "TEST-3925 the root was not removed"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3925 a temp entry made outside the root during the run is named in one NOTE line and kept; the root is removed"
}

# --- TEST-3926 (Spec-AC-04: a process holding the marker is terminated) -------
test_3926_owned_process_terminated_foreign_kept() {
  local ok=1 sb p1 p2 cmd
  need_lsof TEST-3926 || return 0
  cmd='perl -e "use POSIX qw(setsid); setsid(); exec @ARGV" -- sleep 127 </dev/null >/dev/null 2>&1 & echo $! >> "$AAI_RESIDUE_SANDBOX/pids"
perl -e "use POSIX qw(setsid); setsid(); exec @ARGV" -- sleep 127 9<&- </dev/null >/dev/null 2>&1 & echo $! >> "$AAI_RESIDUE_SANDBOX/pids"
sleep 0.5; exit 0'
  for mode in real dry; do
    sb="$(sandbox_new "3926-$mode")"
    SB_ALL="$SB_ALL $sb"
    if [[ "$mode" == dry ]]; then AAI_RESIDUE_DRY_RUN=1 tree_wrap "$sb" sh -c "$cmd"; else tree_wrap "$sb" sh -c "$cmd"; fi
    cp "$sb/pids" "$sb/own-pids" 2>/dev/null
    p1="$(sed -n 1p "$sb/pids" 2>/dev/null)"; p2="$(sed -n 2p "$sb/pids" 2>/dev/null)"
    [[ -n "$p1" && -n "$p2" ]] || { log_fail "TEST-3926 ($mode) the command did not record two pids: $W_OUT"; ok=0; continue; }
    alive "$p2" || { log_fail "TEST-3926 ($mode) the process without the marker was terminated: $W_OUT"; ok=0; }
    if [[ "$mode" == dry ]]; then
      alive "$p1" || { log_fail "TEST-3926 (dry) the marker holder was terminated in a dry run: $W_OUT"; ok=0; }
      command grep -qF "would terminate" <<<"$W_OUT" || { log_fail "TEST-3926 (dry) no would terminate line: $W_OUT"; ok=0; }
    else
      gone_within "$p1" 5 || { log_fail "TEST-3926 the marker holder $p1 is still running: $W_OUT"; ok=0; }
    fi
    sb_reap "$sb"
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-3926 a detached process still holding the marker on descriptor 9 is terminated, one that closed it survives, and a dry run terminates nothing"
}

# --- TEST-3927 (Spec-AC-05: the per-process check) ---------------------------
test_3927_per_process_check_refusals() {
  local ok=1 sb m st p
  need_lsof TEST-3927 || return 0
  sb="$(sandbox_new 3927)"
  lib_tree "$sb" "$LIB" aai_residue_tmp_create "$TID" 0 "$sb"
  m="$sb/aai-tr-0123abcd/.aai-test-run"
  [[ -f "$m" ]] || { log_fail "TEST-3927 no marker could be made: $T_OUT"; return; }
  st=0
  lib_tree "$sb" "$LIB" aai_residue_proc_verify 1 "$m" "$st"
  [[ "$T_RC" -ne 0 ]] || { log_fail "TEST-3927 pid 1 passed the check"; ok=0; }
  # the calling shell and its parent, each listed in the sandbox and holding the marker on descriptor 9
  T_RC=0
  T_OUT="$(AAI_RESIDUE_IN_TEST=1 AAI_RESIDUE_SANDBOX="$sb" TMPDIR="$sb" sh -c 'echo $$ >> "$AAI_RESIDUE_SANDBOX/pids"; . "$1" || exit 99; aai_residue_proc_verify $$ "$2" 0' tree-case "$LIB" "$m" 9<"$m" 2>&1)" || T_RC=$?
  [[ "$T_RC" -ne 0 ]] && command grep -qF 'ancestors' <<<"$T_OUT" || { log_fail "TEST-3927 the calling shell passed the check: rc $T_RC $T_OUT"; ok=0; }
  T_RC=0
  T_OUT="$(AAI_RESIDUE_IN_TEST=1 AAI_RESIDUE_SANDBOX="$sb" TMPDIR="$sb" sh -c 'sh -c "echo \$PPID >> \"\$AAI_RESIDUE_SANDBOX/pids\"; . \"\$1\" || exit 99; aai_residue_proc_verify \$PPID \"\$2\" 0" x "$1" "$2"' tree-case "$LIB" "$m" 9<"$m" 2>&1)" || T_RC=$?
  [[ "$T_RC" -ne 0 ]] && command grep -qF 'ancestors' <<<"$T_OUT" || { log_fail "TEST-3927 the parent passed the check: rc $T_RC $T_OUT"; ok=0; }
  p="$(sb_spawn "$sb" keep9-unlisted "$m")"
  lib_tree "$sb" "$LIB" aai_residue_proc_verify "$p" "$m" 0
  [[ "$T_RC" -ne 0 ]] && command grep -qF 'sandbox' <<<"$T_OUT" || { log_fail "TEST-3927 a pid outside the sandbox list passed: $T_OUT"; ok=0; }
  p="$(sb_spawn "$sb" keep9 "$m")"
  lib_tree "$sb" "$LIB" aai_residue_proc_verify "$p" "$m" 0
  [[ "$T_RC" -eq 0 && -n "$T_OUT" ]] || { log_fail "TEST-3927 control: a listed marker holder failed the check: $T_OUT"; ok=0; }
  lib_tree "$sb" "$LIB" aai_residue_proc_verify "$p" "$m" "$(( $(date +%s) + 3600 ))"
  [[ "$T_RC" -ne 0 ]] && command grep -qF 'before this run' <<<"$T_OUT" || { log_fail "TEST-3927 a process started before the run start passed: $T_OUT"; ok=0; }
  # a per-process lsof that prints the f9 record but then fails is not a completed ownership check
  mkdir -p "$sb/bin3927"
  printf '#!/bin/sh\ncase " $* " in *" -p "*) echo p%s; echo f9; exit 1 ;; esac\nexec %q "$@"\n' "$p" "$(command -v lsof)" > "$sb/bin3927/lsof"
  chmod +x "$sb/bin3927/lsof"
  TREE_LSOF="$sb/bin3927/lsof" lib_tree "$sb" "$LIB" aai_residue_proc_verify "$p" "$m" 0
  [[ "$T_RC" -ne 0 ]] || { log_fail "TEST-3927 a failed per-process lsof still passed the check: $T_OUT"; ok=0; }
  lib_tree "$sb" "$LIB" aai_residue_proc_signal "$p" TERM "$m" 0 "bogus identity"
  [[ "$T_RC" -ne 0 ]] || { log_fail "TEST-3927 a changed identity was signalled"; ok=0; }
  alive "$p" || { log_fail "TEST-3927 the process with a changed identity was terminated"; ok=0; }
  sb_reap "$sb"
  [[ $ok -eq 1 ]] && log_pass "TEST-3927 pid 1, the calling shell, its parent, an unlisted pid and a process older than the run start fail the check; a changed identity is never signalled"
}

# --- TEST-3928 (Spec-AC-06: the listing filter, its refusal and the cap) ------
test_3928_listing_filter_refusal_and_cap() {
  local ok=1 sb m p shim
  need_lsof TEST-3928 || return 0
  sb="$(sandbox_new 3928)"
  lib_tree "$sb" "$LIB" aai_residue_tmp_create "$TID" 0 "$sb"
  m="$sb/aai-tr-0123abcd/.aai-test-run"
  p="$(sb_spawn "$sb" keep9 "$m")"
  shim="$(lsof_shim "$sb")"
  TREE_LSOF="$shim" lib_tree "$sb" "$LIB" aai_residue_proc_cleanup "$TID" 0 "$m"
  listing_filter_ok "$sb" "$m" || { log_fail "TEST-3928 a listing call lacked -a, -d 9 or the marker: $(cat "$sb/lsof.log" 2>/dev/null)"; ok=0; }
  gone_within "$p" 5 || { log_fail "TEST-3928 the listed marker holder survived: $T_OUT"; ok=0; }
  rm -f "$sb/lsof.log"
  TREE_LSOF="$shim" lib_tree "$sb" "$LIB" aai_residue_proc_cleanup "$TID" 0 ""
  [[ "$T_RC" -eq 2 && ! -e "$sb/lsof.log" ]] || { log_fail "TEST-3928 an empty marker: exit $T_RC (want 2), lsof called: $(cat "$sb/lsof.log" 2>/dev/null)"; ok=0; }
  TREE_LSOF="$shim" lib_tree "$sb" "$LIB" aai_residue_proc_cleanup "$TID" 0 "$sb/aai-tr-ffffffff/.aai-test-run"
  [[ "$T_RC" -eq 2 && ! -e "$sb/lsof.log" ]] || { log_fail "TEST-3928 a missing marker: exit $T_RC (want 2), lsof called"; ok=0; }
  TREE_LSOF="$shim" lib_tree "$sb" "$LIB" aai_residue_proc_cleanup "$TID_OTHER" 0 "$m"
  [[ "$T_RC" -eq 2 && ! -e "$sb/lsof.log" ]] || { log_fail "TEST-3928 a marker naming another run: exit $T_RC (want 2), lsof called"; ok=0; }
  p="$(sb_spawn "$sb" keep9 "$m")"
  shim="$(lsof_shim "$sb" lie26 "$p")"
  TREE_LSOF="$shim" lib_tree "$sb" "$LIB" aai_residue_proc_cleanup "$TID" 0 "$m"
  [[ "$T_RC" -eq 4 ]] || { log_fail "TEST-3928 26 candidates: exit $T_RC, want 4: $T_OUT"; ok=0; }
  alive "$p" || { log_fail "TEST-3928 26 candidates: a process was signalled"; ok=0; }
  # a listing that fails (error text, exit 1) or stops part-way (exit 2 after one record) checks nothing and says so
  shim="$(lsof_shim "$sb" fail)"
  TREE_LSOF="$shim" lib_tree "$sb" "$LIB" aai_residue_proc_cleanup "$TID" 0 "$m"
  command grep -qF 'listing failed' <<<"$T_OUT" || { log_fail "TEST-3928 a failing lsof listing was read as no process: rc $T_RC $T_OUT"; ok=0; }
  # exit 1 with no output at all is not "nothing found": lsof also exits 1 on an error whose warning -w hides
  shim="$(lsof_shim "$sb" silent1)"
  TREE_LSOF="$shim" lib_tree "$sb" "$LIB" aai_residue_proc_cleanup "$TID" 0 "$m"
  command grep -qF 'listing failed' <<<"$T_OUT" || { log_fail "TEST-3928 a silent lsof exit 1 was read as no process: rc $T_RC $T_OUT"; ok=0; }
  shim="$(lsof_shim "$sb" partial "$p")"
  TREE_LSOF="$shim" lib_tree "$sb" "$LIB" aai_residue_proc_cleanup "$TID" 0 "$m"
  command grep -qF 'listing failed' <<<"$T_OUT" || { log_fail "TEST-3928 a partial lsof listing was trusted: rc $T_RC $T_OUT"; ok=0; }
  alive "$p" || { log_fail "TEST-3928 a partial lsof listing led to a signal"; ok=0; }
  sb_reap "$sb"
  [[ $ok -eq 1 ]] && log_pass "TEST-3928 every listing carries -a, -d 9 and the marker; an empty or missing marker, or one naming another run, exits 2 without lsof; 26 candidates exit 4 and signal nothing; a failed or partial listing signals nothing and says so"
}

# --- TEST-3929 (Spec-AC-07: two independent layers under mutation) -----------
test_3929_two_layers_under_mutation() {
  local ok=1 sb m pown pfor shim m1="$TR_TMP/lib-tree-m1.sh" m2="$TR_TMP/lib-tree-m2.sh" m3="$TR_TMP/lib-tree-m3.sh" st
  need_lsof TEST-3929 || return 0
  sed 's/"\$AAI_RESIDUE_LSOF" -a -d 9 -F p/"$AAI_RESIDUE_LSOF" -F p/' "$LIB" > "$m1"
  command grep -v 'layer:name' "$LIB" > "$m2"
  command grep -v 'layer:marker' "$LIB" > "$m3"
  cmp -s "$LIB" "$m1" && { log_fail "TEST-3929 the listing mutation did not apply"; ok=0; }
  cmp -s "$LIB" "$m2" && { log_fail "TEST-3929 the name-layer mutation did not apply"; ok=0; }
  cmp -s "$LIB" "$m3" && { log_fail "TEST-3929 the marker-layer mutation did not apply"; ok=0; }
  # control: the unmutated listing passes the filter check
  sb="$(sandbox_new 3929-ctl)"
  lib_tree "$sb" "$LIB" aai_residue_tmp_create "$TID" 0 "$sb"
  m="$sb/aai-tr-0123abcd/.aai-test-run"
  shim="$(lsof_shim "$sb")"
  TREE_LSOF="$shim" lib_tree "$sb" "$LIB" aai_residue_proc_cleanup "$TID" 0 "$m"
  listing_filter_ok "$sb" "$m" || { log_fail "TEST-3929 control: the unmutated listing failed the filter check"; ok=0; }
  # layer 1 catches the dropped filter; layer 2 still spares a foreign holder of the marker on descriptor 8
  sb="$(sandbox_new 3929-proc)"
  lib_tree "$sb" "$LIB" aai_residue_tmp_create "$TID" 0 "$sb"
  m="$sb/aai-tr-0123abcd/.aai-test-run"
  pown="$(sb_spawn "$sb" keep9 "$m")"
  pfor="$(sb_spawn "$sb" fd8 "$m")"
  shim="$(lsof_shim "$sb")"
  TREE_LSOF="$shim" lib_tree "$sb" "$m1" aai_residue_proc_cleanup "$TID" 0 "$m"
  listing_filter_ok "$sb" "$m" && { log_fail "TEST-3929 the filter check did not catch the dropped -d 9"; ok=0; }
  alive "$pfor" || { log_fail "TEST-3929 filter dropped: the foreign holder on descriptor 8 was terminated: $T_OUT"; ok=0; }
  gone_within "$pown" 5 || { log_fail "TEST-3929 filter dropped: the owned holder was not terminated: $T_OUT"; ok=0; }
  sb_reap "$sb"
  # files: without the name layer the marker layer keeps a decoy; without the marker layer the name layer does
  sb="$(sandbox_new 3929-tmp)"
  st=$(( $(date +%s) - 5 ))
  mkdir -p "$sb/victim"; echo keep > "$sb/victim/keep.txt"
  lib_tree "$sb" "$m2" aai_residue_tmp_cleanup "$TID" "$st" "$sb" "$sb/victim"
  [[ -f "$sb/victim/keep.txt" ]] || { log_fail "TEST-3929 name layer removed: a decoy without a marker was deleted: $T_OUT"; ok=0; }
  mkdir -p "$sb/aai-tr-ffffffff"; echo keep > "$sb/aai-tr-ffffffff/keep.txt"; printf '%s %s\n' "$TID_OTHER" "$st" > "$sb/aai-tr-ffffffff/.aai-test-run"
  lib_tree "$sb" "$m3" aai_residue_tmp_cleanup "$TID" "$st" "$sb" "$sb/aai-tr-ffffffff"
  [[ -f "$sb/aai-tr-ffffffff/keep.txt" ]] || { log_fail "TEST-3929 marker layer removed: another run's root was deleted: $T_OUT"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3929 a dropped descriptor filter is caught by the filter check and the per-process check still spares a foreign holder; each root layer alone keeps a decoy when the other is removed"
}

# --- TEST-3930 (Spec-AC-08: consumer record) ----------------------------------
test_3930_consumer_record() {
  local ok=1 n
  n="$(command grep -cE '^## \[(unreleased|v[0-9]{4}\.[0-9]{2}\.[0-9]{2})\] — feat: test runs remove the temp root and leftover processes' CHANGELOG.md || true)"
  [[ "$n" -eq 1 ]] || { log_fail "TEST-3930 CHANGELOG.md holds $n headings for this change, want 1"; ok=0; }
  command grep -qF 'AAI_TEST_OWNER' docs/TECHNOLOGY.md && command grep -qF 'aai-tr-' docs/TECHNOLOGY.md \
    || { log_fail "TEST-3930 docs/TECHNOLOGY.md does not name AAI_TEST_OWNER and the aai-tr- root"; ok=0; }
  command grep -qF "only while it holds the run's marker" docs/product/test-residue-safe-cleanup.md \
    || { log_fail "TEST-3930 the product doc does not state the marker condition"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3930 CHANGELOG, TECHNOLOGY and the product doc carry the consumer record"
}

# --- TEST-3931 (Spec-AC-09: the mount guard keeps the root on any doubt) ------
# One table: each row plants a find and/or mount shim (or none) for one cleanup of a valid root and says whether the
# root must survive and which reason the output must name. Every probe failure, and every mount sign, keeps the root.
#   row = name|find mode|mount mode|expect (kept or removed)|reason fragment
TREE_MOUNT_TABLE='xdev-differs|xdevdrop|real|kept|mounted inside
find-fails|fail|real|kept|did not complete
xdev-fails|xdevfail|real|kept|did not complete
find-empty|empty|real|kept|listed nothing
mount-fails|real|fail|kept|could not be read
mount-empty|real|empty|kept|could not be read
mount-at-root|real|atroot|kept|at or inside
mount-below|real|below|kept|at or inside
control|real|real|removed|'
test_3931_mounted_filesystem_inside_root_is_kept() {
  local ok=1 sb st root fsd realfind img row name fm mm want why
  sb="$(sandbox_new 3931)"
  st=$(( $(date +%s) - 5 ))
  root="$sb/aai-tr-0123abcd"
  fsd="$sb/bin"
  realfind="$(command -v find)"
  while IFS='|' read -r name fm mm want why; do
    [[ -n "$name" ]] || continue
    rm -rf "$root" "$fsd"; mkdir -p "$root/mnt/deep" "$fsd"
    echo keep > "$root/mnt/deep/keep.txt"; printf '%s %s\n' "$TID" "$st" > "$root/.aai-test-run"
    case "$fm" in
      xdevdrop) printf '#!/bin/sh\ncase " $* " in *" -xdev "*) %q "$@" | sed "/\\/mnt\\//d" ;; *) exec %q "$@" ;; esac\n' "$realfind" "$realfind" > "$fsd/find" ;;
      fail) printf '#!/bin/sh\n%q "$@"\nexit 1\n' "$realfind" > "$fsd/find" ;;
      xdevfail) printf '#!/bin/sh\ncase " $* " in *" -xdev "*) %q "$@"; exit 1 ;; *) exec %q "$@" ;; esac\n' "$realfind" "$realfind" > "$fsd/find" ;;
      empty) printf '#!/bin/sh\nexit 0\n' > "$fsd/find" ;;
    esac
    case "$mm" in
      fail) printf '#!/bin/sh\nexit 1\n' > "$fsd/mount" ;;
      empty) printf '#!/bin/sh\nexit 0\n' > "$fsd/mount" ;;
      atroot) printf '#!/bin/sh\necho "/dev/fake on %s type none (rw,bind)"\n' "$root" > "$fsd/mount" ;;
      below) printf '#!/bin/sh\necho "/dev/fake on %s/mnt type none (rw,bind)"\n' "$root" > "$fsd/mount" ;;
    esac
    chmod +x "$fsd"/* 2>/dev/null
    T_RC=0
    T_OUT="$(PATH="$fsd:$PATH" AAI_RESIDUE_IN_TEST=1 AAI_RESIDUE_SANDBOX="$sb" TMPDIR="$sb" \
      sh -c '. "$1" || exit 99; shift; "$@"' tree-case "$LIB" aai_residue_tmp_cleanup "$TID" "$st" "$sb" "$root" 2>&1)" || T_RC=$?
    if [[ "$want" == kept ]]; then
      [[ -f "$root/mnt/deep/keep.txt" ]] || { log_fail "TEST-3931 ($name) the root was removed: $T_OUT"; ok=0; }
      command grep -qF -- "$why" <<<"$T_OUT" || { log_fail "TEST-3931 ($name) the output does not name [$why]: $T_OUT"; ok=0; }
    else
      [[ ! -e "$root" ]] || { log_fail "TEST-3931 ($name) a root with no mount sign was kept: $T_OUT"; ok=0; }
    fi
  done <<<"$TREE_MOUNT_TABLE"
  rm -rf "$fsd"
  # the real thing where it can be made without privileges (macOS disk image); elsewhere the shim rows stand
  if [[ "$(uname -s)" == Darwin ]] && command -v hdiutil >/dev/null 2>&1; then
    rm -rf "$root"; mkdir -p "$root/mnt" "$sb/src"; echo precious > "$sb/src/precious.txt"
    printf '%s %s\n' "$TID" "$st" > "$root/.aai-test-run"
    img="$sb/img.dmg"
    if hdiutil create -quiet -srcfolder "$sb/src" -volname aai3931 -format UDRW "$img" && hdiutil attach -quiet -nobrowse -mountpoint "$root/mnt" "$img"; then
      lib_tree "$sb" "$LIB" aai_residue_tmp_cleanup "$TID" "$st" "$sb" "$root"
      [[ -f "$root/mnt/precious.txt" ]] || { log_fail "TEST-3931 a file on a disk image mounted inside the root was deleted: $T_OUT"; ok=0; }
      hdiutil detach -quiet "$root/mnt" || hdiutil detach -quiet -force "$root/mnt"
    else
      echo "SKIP-CASE: TEST-3931 could not attach a disk image here"
    fi
  fi
  # a swap while the probes run: the mount shim renames the verified root away and moves a decoy (no marker) into its
  # path; the removal must act only on the directory it verified, so the decoy survives
  rm -rf "$root" "$sb/decoy" "$sb/moved" "$fsd"; mkdir -p "$root" "$sb/decoy" "$fsd"
  printf '%s %s\n' "$TID" "$st" > "$root/.aai-test-run"; echo keep > "$sb/decoy/keep.txt"
  printf '#!/bin/sh\nif [ ! -e %q ]; then mv %q %q && mv %q %q; fi\nexec %q "$@"\n' "$sb/moved" "$root" "$sb/moved" "$sb/decoy" "$root" "$(command -v mount)" > "$fsd/mount"
  chmod +x "$fsd/mount"
  T_RC=0
  T_OUT="$(PATH="$fsd:$PATH" AAI_RESIDUE_IN_TEST=1 AAI_RESIDUE_SANDBOX="$sb" TMPDIR="$sb" \
    sh -c '. "$1" || exit 99; shift; "$@"' tree-case "$LIB" aai_residue_tmp_cleanup "$TID" "$st" "$sb" "$root" 2>&1)" || T_RC=$?
  [[ -e "$sb/moved" ]] || { log_fail "TEST-3931 (swap) the mount shim never swapped the root, the case is not exercising the window: $T_OUT"; ok=0; }
  [[ -n "$(find "$sb" -name keep.txt 2>/dev/null)" ]] || { log_fail "TEST-3931 (swap) the decoy moved into the root's path was deleted: $T_OUT"; ok=0; }
  # a swap of the moved-aside name during the second mount probe: removal must go through the pinned directory, never
  # through a pathname a child could have pointed elsewhere
  rm -rf "$root" "$sb/decoy" "$sb/moved" "$sb/moved2" "$sb"/aai-tr-0123abcd.removing.* "$fsd"; mkdir -p "$root" "$sb/decoy" "$fsd"
  printf '%s %s\n' "$TID" "$st" > "$root/.aai-test-run"; echo keep > "$sb/decoy/keep.txt"
  printf '#!/bin/sh\nn=$(cat %q 2>/dev/null || echo 0); n=$((n+1)); echo $n > %q\nif [ "$n" -eq 2 ]; then for q in %q.removing.*; do [ -d "$q" ] && mv "$q" %q && mv %q "$q"; done; fi\nexec %q "$@"\n' \
    "$fsd/n" "$fsd/n" "$root" "$sb/moved2" "$sb/decoy" "$(command -v mount)" > "$fsd/mount"
  chmod +x "$fsd/mount"
  T_RC=0
  T_OUT="$(PATH="$fsd:$PATH" AAI_RESIDUE_IN_TEST=1 AAI_RESIDUE_SANDBOX="$sb" TMPDIR="$sb" \
    sh -c '. "$1" || exit 99; shift; "$@"' tree-case "$LIB" aai_residue_tmp_cleanup "$TID" "$st" "$sb" "$root" 2>&1)" || T_RC=$?
  [[ -e "$sb/moved2" ]] || { log_fail "TEST-3931 (swap 2) the mount shim never swapped the moved-aside name: $T_OUT"; ok=0; }
  [[ -n "$(find "$sb" -name keep.txt 2>/dev/null)" ]] || { log_fail "TEST-3931 (swap 2) the decoy swapped into the moved-aside name was deleted: $T_OUT"; ok=0; }
  rm -rf "$fsd"
  [[ $ok -eq 1 ]] && log_pass "TEST-3931 every probe failure (find, find -xdev, mount) and every mount sign (a shorter -xdev walk, a mount at or below the root, a real disk image on macOS) keeps the root with its reason; a root with none is removed"
}

# --- TEST-3933 (Spec-AC-11: an incomplete outside scan, and no lsof) ------------
test_3933_outside_scan_failure_and_no_lsof() {
  local ok=1 sb root fsd realfind
  sb="$(sandbox_new 3933)"
  lib_tree "$sb" "$LIB" aai_residue_tmp_create "$TID" 0 "$sb"
  root="$sb/aai-tr-0123abcd"
  fsd="$sb/bin"; mkdir -p "$fsd"
  realfind="$(command -v find)"
  printf '#!/bin/sh\ncase " $* " in *" -maxdepth 1 "*) exit 1 ;; *) exec %q "$@" ;; esac\n' "$realfind" > "$fsd/find"
  chmod +x "$fsd/find"
  T_RC=0
  T_OUT="$(PATH="$fsd:$PATH" AAI_RESIDUE_IN_TEST=1 AAI_RESIDUE_SANDBOX="$sb" TMPDIR="$sb" \
    sh -c '. "$1" || exit 99; shift; "$@"' tree-case "$LIB" aai_residue_tmp_outside "$sb" "$root" 2>&1)" || T_RC=$?
  command grep -qF 'did not complete' <<<"$T_OUT" || { log_fail "TEST-3933 a failed outside scan was read as complete: $T_OUT"; ok=0; }
  TREE_LSOF="$sb/no-such-lsof" lib_tree "$sb" "$LIB" aai_residue_proc_cleanup "$TID" 0 "$root/.aai-test-run"
  [[ "$T_RC" -eq 0 && -z "$T_OUT" ]] || { log_fail "TEST-3933 a host without lsof printed or failed (rc $T_RC): $T_OUT"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-3933 an outside scan that fails says so; a host without lsof skips the process check silently (a machine constant, not news about the run)"
}

# --- TEST-3932 (Spec-AC-10: AAI_TEST_TMPDIR=keep) ------------------------------
test_3932_tmpdir_opt_out_keeps_caller_tmpdir() {
  local ok=1 sb p
  need_lsof TEST-3932 || return 0
  sb="$(sandbox_new 3932)"
  SB_ALL="$SB_ALL $sb"
  AAI_TEST_TMPDIR=keep tree_wrap "$sb" sh -c 'echo "TMP=$TMPDIR"; perl -e "use POSIX qw(setsid); setsid(); exec @ARGV" -- sleep 127 </dev/null >/dev/null 2>&1 & echo $! >> "$AAI_RESIDUE_SANDBOX/pids"; sleep 0.5'
  cp "$sb/pids" "$sb/own-pids" 2>/dev/null
  command grep -qxF "TMP=$sb" <<<"$W_OUT" || { log_fail "TEST-3932 AAI_TEST_TMPDIR=keep did not keep the caller's TMPDIR: $W_OUT"; ok=0; }
  p="$(sed -n 1p "$sb/pids" 2>/dev/null)"
  [[ -n "$p" ]] && gone_within "$p" 5 || { log_fail "TEST-3932 with the opt-out the marker holder was not terminated: $W_OUT"; ok=0; }
  ls -d "$sb"/aai-tr-* >/dev/null 2>&1 && { log_fail "TEST-3932 the root was left behind"; ok=0; }
  sb_reap "$sb"
  [[ $ok -eq 1 ]] && log_pass "TEST-3932 AAI_TEST_TMPDIR=keep leaves the command's TMPDIR alone while the marker, the process check and the root removal still run"
}

main() {
  echo "=== Test: $TEST_NAME (spec-test-residue-safe-cleanup) ==="
  check_deps
  if [[ $# -ge 1 ]]; then
    declare -F "$1" >/dev/null 2>&1 || { echo "unknown test function: $1" >&2; exit 2; }
    "$1"
    if [[ $FAILED -ne 0 ]]; then echo "=== $TEST_NAME: SELECTED TEST FAILED ($1) ===" >&2; exit 1; fi
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    exit 0
  fi
  test_3900_per_object_ownership_survives_a_lying_listing
  test_3901_creation_time_boundaries_and_formats
  test_3902_no_run_id_never_means_all
  test_3903_single_object_verbs_only
  test_3904_cap_refuses_everything_above_25
  test_3905_test_context_requires_the_stub
  test_3906_outer_wrapper_marks_inner_runs_as_tests
  test_3907_wrapper_isolates_unless_opted_in
  test_3908_framework_isolates_every_suite
  test_3909_two_layers_under_the_incident_mutation
  test_3910_mutation_runner_isolates_the_suite
  test_3911_report_and_dry_run
  test_3912_no_daemon_is_a_noted_no_op
  test_3913_wrapper_end_to_end_on_the_stub
  test_3914_classification_and_consumer_record
  test_3923_owner_temp_root_lifecycle
  test_3924_tampered_roots_are_kept
  test_3925_outside_entries_reported_and_kept
  test_3926_owned_process_terminated_foreign_kept
  test_3927_per_process_check_refusals
  test_3928_listing_filter_refusal_and_cap
  test_3929_two_layers_under_mutation
  test_3930_consumer_record
  test_3931_mounted_filesystem_inside_root_is_kept
  test_3932_tmpdir_opt_out_keeps_caller_tmpdir
  test_3933_outside_scan_failure_and_no_lsof
  if [[ -s "$AAI_NO_CLI_LOG" ]]; then
    log_fail "$TEST_NAME a bare container CLI was invoked during the run: $(cat "$AAI_NO_CLI_LOG")"
  fi
  echo ""
  if [[ $FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
  fi
  echo "Some tests failed."
  exit 1
}

main "$@"
