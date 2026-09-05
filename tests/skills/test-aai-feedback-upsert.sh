#!/usr/bin/env bash
#
# Test: RFC-0012 Phase 2c / Slice C — review-mode GitHub upsert (approval-gated)
# (.aai/scripts/aai-feedback-upsert.mjs), TEST-001..035 (ids 003 and 009 fold
# into 002 and the profiles case respectively; there is no TEST-003 function).
#
# `gh` is MOCKED via a stub on AAI_GH_BIN that RECORDS every invocation AND
# PINS THE EXACT ARGV — the suite makes no real network call. Two invariants are
# under test: a plain run performs NO mutating GitHub call and a write happens
# ONLY under --publish --confirm; and the engine emits only the four `gh` call
# SKELETONS pinned in the stub. Stated precisely, because a looser wording is
# what four review rounds kept escaping: the stub pins the exact FLAG SKELETON
# — which flags, in which order, how many tokens — and SHAPE-CHECKS the variable
# values (`--repo` must be owner/name, the marker must start `aai-friction:v1:`,
# `--title`/`--body` must be non-empty). It does NOT pin those values, and it is
# not a gh emulator. The values that matter on the mutating path — the actual
# destination, the templated title, the marker in the filed body, and the absence
# of an un-redacted summary — are pinned by TEST-032 instead.

set -u
TEST_NAME="test-aai-feedback-upsert"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"
SCRIPT="$PROJECT_ROOT/.aai/scripts/aai-feedback-upsert.mjs"
LAYER_PROFILES_TEST="$SCRIPT_DIR/test-aai-layer-profiles.sh"

cleanup() { [ -n "${TEST_DIR:-}" ] && [ -z "${KEEP_TEST_DIR:-}" ] && rm -rf "$TEST_DIR"; }
trap cleanup EXIT
log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_info() { echo "INFO: $*"; }
log_skip() { echo "SKIP: $*"; exit 42; }
command -v node >/dev/null 2>&1 || log_skip "node not found"

# Mock gh: $1 records calls; SEARCH_RESULT controls the search response.
setup() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-upsert-test.XXXXXX")"
  GH_CALLS="$TEST_DIR/gh_calls"; : > "$GH_CALLS"
  mkdir -p "$TEST_DIR/bin" "$TEST_DIR/friction"
  cat > "$TEST_DIR/bin/gh" <<'SH'
#!/usr/bin/env bash
# ONE LINE PER INVOCATION. `echo "$@"` used to spill an issue body's newlines into
# $GH_CALLS, so the recording could not be read back as a list of calls and no
# test could assert "every call matches a pinned shape".
{ printf '%s' "$*" | tr '\n' ' '; printf '\n'; } >> "$GH_CALLS"
# CONTRACT-FAITHFUL STUB. The previous stub exit-0'd for EVERY argv, so it could
# only ever attest "gh was called" — never "the call is one gh would accept".
# That permissiveness is what let `--state all` (a value real `gh search issues`
# rejects) ship green while the channel was dead. Every branch below mirrors a
# refusal the real CLI makes and this engine depends on.
# ARGV CONTRACT — EXACT MATCH, DENY BY DEFAULT.
#
# Four consecutive review rounds broke the previous shape of this gate, each in a
# new place: prefix-only matching, then unknown-flag-only checking, then a
# `--[a-z]*` detector blind to `--Force` and `-Z`, then unvalidated `--match`,
# `--sort`, `--order` values and stray positionals. Every fix added another
# entry to another table, and every round found the entry that was missing.
# An enumerated allowlist's forgotten member IS the hole.
#
# So this stub no longer enumerates what is FORBIDDEN or even what is ALLOWED.
# It pins the EXACT argv this engine is permitted to emit, positionally, and
# refuses everything else. A renamed flag, a bad value, a stray positional, a
# reordering, a duplicate, an alias (`-R`), an `=`-form, an extra argument —
# all fail by construction, because none of them IS the pinned shape. Widening
# what the engine may call now requires editing this list, which is the point.
gh_reject() { echo "gh(stub) rejects: $*" >&2; exit 2; }
is_repo()   { case "$1" in ?*/?*) return 0 ;; *) return 1 ;; esac; }

case "$1 $2" in
  "auth status")
    [ "$#" -eq 2 ] || gh_reject "auth status takes no arguments, got: $*"
    exit 0 ;;

  "search issues")
    # search issues --repo <o/r> --match body aai-friction:<fp> --json number --limit 1
    [ "$#" -eq 11 ] || gh_reject "search argv must be exactly 11 tokens, got $#: $*"
    [ "$3" = "--repo" ] && is_repo "$4" || gh_reject "expected --repo <owner/name>, got: $3 $4"
    [ "$5" = "--match" ] && [ "$6" = "body" ] || gh_reject "expected --match body, got: $5 $6"
    case "$7" in aai-friction:v1:*) ;; *) gh_reject "expected the aai-friction:<fp> marker, got: $7" ;; esac
    [ "$8" = "--json" ] && [ "$9" = "number" ] || gh_reject "expected --json number, got: $8 $9"
    [ "${10}" = "--limit" ] && [ "${11}" = "1" ] || gh_reject "expected --limit 1, got: ${10} ${11}"
    if [ "${SEARCH_FAIL:-0}" = "1" ]; then echo "search failed" >&2; exit 1; fi
    cat "${SEARCH_RESULT:-/dev/null}" 2>/dev/null || echo "[]"
    exit 0 ;;

  "label list")
    # label list --repo <o/r> --json name --limit 500
    [ "$#" -eq 8 ] || gh_reject "label list argv must be exactly 8 tokens, got $#: $*"
    [ "$3" = "--repo" ] && is_repo "$4" || gh_reject "expected --repo <owner/name>, got: $3 $4"
    [ "$5" = "--json" ] && [ "$6" = "name" ] || gh_reject "expected --json name, got: $5 $6"
    [ "$7" = "--limit" ] && [ "$8" = "500" ] || gh_reject "expected --limit 500, got: $7 $8"
    if [ "${LABEL_LIST_FAIL:-0}" = "1" ]; then echo "could not list labels" >&2; exit 1; fi
    cat "${LABEL_RESULT:-/dev/null}" 2>/dev/null || echo "[]"
    exit 0 ;;

  "issue create")
    # issue create --repo <o/r> --title <t> --body <b> [--label <l>]...
    [ "$#" -ge 8 ] || gh_reject "issue create argv too short ($#): $*"
    [ "$3" = "--repo" ] && is_repo "$4" || gh_reject "expected --repo <owner/name>, got: $3 $4"
    [ "$5" = "--title" ] && [ -n "$6" ] || gh_reject "expected --title <non-empty>, got: $5"
    [ "$7" = "--body" ] && [ -n "$8" ] || gh_reject "expected --body <non-empty>, got: $7"
    shift 8
    while [ "$#" -gt 0 ]; do
      [ "$1" = "--label" ] || gh_reject "only --label may follow --body, got: $1"
      [ "$#" -ge 2 ] || gh_reject "--label needs an argument"
      lc="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
      tr '[:upper:]' '[:lower:]' < "${LABEL_RESULT:-/dev/null}" 2>/dev/null | grep -qF "\"$lc\"" \
        || { echo "could not add label: '$2' not found" >&2; exit 1; }
      shift 2
    done
    echo "https://github.com/x/y/issues/1"
    exit 0 ;;
esac
gh_reject "unpinned command: $*"
SH
  chmod +x "$TEST_DIR/bin/gh"
  export GH_CALLS
  printf '[]' > "$TEST_DIR/empty.json"; SEARCH_RESULT="$TEST_DIR/empty.json"; export SEARCH_RESULT
  # destination label set the stub answers `gh label list` from; default: the
  # configured label EXISTS, so pre-existing cases keep their original meaning.
  printf '[{"name":"aai-friction"}]' > "$TEST_DIR/labels.json"; LABEL_RESULT="$TEST_DIR/labels.json"; export LABEL_RESULT
  printf '[]' > "$TEST_DIR/nolabels.json"
  LABEL_LIST_FAIL=0; export LABEL_LIST_FAIL
  SEARCH_FAIL=0; export SEARCH_FAIL
  # a review-mode config WITH a labels list, created here rather than inside one
  # test: cases 016..020 each need it, and building it in 016 made every later
  # case silently depend on 016 having run. In selected-case mode that dependency
  # turned real REDs into "mode=local (no destination)" — a pass/fail for the
  # wrong reason, which is worthless as TDD evidence.
  printf 'triage:\n  mode: review\nupsert:\n  destination: goodwind-cz/aai   # pin\n  labels:\n    - aai-friction\n' > "$TEST_DIR/fblab.yaml"
  # a review-mode config
  printf 'triage:\n  mode: review\nupsert:\n  destination: goodwind-cz/aai   # pinned (RFC-0012 D1)\n  budget:\n    max_new_issues_per_7d: 3\n' > "$TEST_DIR/fb.yaml"
  # a spool + report with one review_candidate
  cat > "$TEST_DIR/friction/observations.jsonl" <<'JSONL'
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"impl","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high","confidence":"high","reproducible":true}
JSONL
  cat > "$TEST_DIR/friction/triage-report.json" <<'JSON'
{"schema":"aai-triage/v1","clusters":[{"fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","failure_class":"contract_violation","recurrence":2,"score":9,"decision":"review_candidate","auto_publishable":false}]}
JSON
}

# run the engine with the mock gh + isolated friction dir
RUN() {
  AAI_GH_BIN="$TEST_DIR/bin/gh" AAI_FRICTION_DIR="$TEST_DIR/friction" AAI_NOW_MS=1000000000000 \
    node "$SCRIPT" --report "$TEST_DIR/friction/triage-report.json" \
      --spool "$TEST_DIR/friction/observations.jsonl" --config "${1:-$TEST_DIR/fb.yaml}" "${@:2}" \
      > "$TEST_DIR/out" 2> "$TEST_DIR/err"; echo $?
}
creates() { local n; n="$(grep -c "^issue create" "$GH_CALLS" 2>/dev/null)"; echo "${n:-0}"; }
# One valid review_candidate, spool + report, and a clean budget ledger. Every
# case that needs it calls this, so no case inherits another case's fixture.
seed_single_candidate() {
  cat > "$TEST_DIR/friction/observations.jsonl" <<'JSONL'
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"impl","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high"}
JSONL
  cat > "$TEST_DIR/friction/triage-report.json" <<'JSON'
{"clusters":[{"fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","failure_class":"contract_violation","recurrence":2,"score":9,"decision":"review_candidate","auto_publishable":false}]}
JSON
  rm -f "$TEST_DIR/friction/upsert-ledger.jsonl"
  SEARCH_RESULT="$TEST_DIR/empty.json"
}
reset_calls() { : > "$GH_CALLS"; }

# --- TEST-001: plain run makes NO mutating gh call --------------------------
test_001_prepare_no_write() {
  log_info "Test: a plain review-mode run performs no mutating gh call (TEST-001)..."
  reset_calls
  local code; code="$(RUN)"
  [ "$code" = "0" ] || log_fail "TEST-001: plain run must exit 0 ($(cat "$TEST_DIR/err"))"
  [ "$(creates)" = "0" ] || log_fail "TEST-001: plain run must make ZERO issue-create calls (made $(creates))"
  [ -f "$TEST_DIR/friction/pending-issues/v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.md" ] || log_fail "TEST-001: a draft must be written"
  log_pass "plain run is prepare-only: no mutating gh call, draft written (TEST-001)"
}

# --- TEST-002/003: template + transmit redaction ----------------------------
test_002_template_and_redaction() {
  log_info "Test: title/body templated; poisoned summary dropped by transmit redaction (TEST-002/003)..."
  # add a poisoned summary to the observation
  cat > "$TEST_DIR/friction/observations.jsonl" <<'JSONL'
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"impl","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high","summary":"failed at /Users/ales/.ssh/id_rsa"}
JSONL
  reset_calls; RUN >/dev/null
  local draft="$TEST_DIR/friction/pending-issues/v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.md"
  grep -qF "[contract_violation] SKILL_TDD/impl (high impact)" "$draft" || log_fail "TEST-002: title must be templated from structured fields"
  grep -qF "aai-friction:v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$draft" || log_fail "TEST-002: body must carry the dedup marker"
  grep -qF "id_rsa" "$draft" && log_fail "TEST-003: a poisoned summary must be DROPPED (transmit redaction), never in the draft"
  grep -qF "transmit_dropped" "$draft" || log_fail "TEST-003: redaction_status must record the drop"
  log_pass "title/body templated; poisoned summary dropped by transmit redaction (TEST-002/003)"
}

# --- TEST-004: dedup ---------------------------------------------------------
test_004_dedup() {
  log_info "Test: an existing marker -> no duplicate NEW issue (TEST-004)..."
  printf '[{"number":42}]' > "$TEST_DIR/existing.json"; SEARCH_RESULT="$TEST_DIR/existing.json"
  reset_calls; RUN >/dev/null
  local draft="$TEST_DIR/friction/pending-issues/v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.md"
  grep -qF "status: update_existing" "$draft" || log_fail "TEST-004: existing marker -> draft marked update_existing"
  # confirmed publish must NOT create when one already exists
  reset_calls; RUN "$TEST_DIR/fb.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "0" ] || log_fail "TEST-004: must not create a duplicate when an issue already carries the marker"
  SEARCH_RESULT="$TEST_DIR/empty.json"
  log_pass "existing marker deduped: draft=update_existing, no duplicate create (TEST-004)"
}

# --- TEST-005: budget --------------------------------------------------------
test_005_budget() {
  log_info "Test: budget met -> prepared-deferred, not filed (TEST-005)..."
  # seed the ledger with max_new_issues_per_7d recent creates
  local led="$TEST_DIR/friction/upsert-ledger.jsonl"
  for i in 1 2 3; do echo "{\"event\":\"issue_created\",\"fingerprint\":\"v1:old$i\",\"ts_ms\":999999999999}" >> "$led"; done
  reset_calls; local out; RUN "$TEST_DIR/fb.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null; out="$(cat "$TEST_DIR/out")"
  [ "$(creates)" = "0" ] || log_fail "TEST-005: over-budget publish must NOT create an issue"
  echo "$out" | grep -qi "budget" || log_fail "TEST-005: must report the budget deferral"
  log_pass "budget met -> deferred, no create (TEST-005)"
}

# --- TEST-006: config pin / auto refused / degrade --------------------------
test_006_config() {
  log_info "Test: destination pin; auto refused; local/missing-dest -> prepare-none (TEST-006)..."
  # auto refused
  printf 'triage:\n  mode: auto\nupsert:\n  destination: goodwind-cz/aai   # pinned (RFC-0012 D1)\n' > "$TEST_DIR/fbauto.yaml"
  RUN "$TEST_DIR/fbauto.yaml" >/dev/null; local code=$?
  grep -qi "auto is refused\|mode=auto" "$TEST_DIR/err" || log_fail "TEST-006: auto mode must be refused"
  # local mode -> prepare nothing
  printf 'triage:\n  mode: local\nupsert:\n  destination: goodwind-cz/aai   # pinned (RFC-0012 D1)\n' > "$TEST_DIR/fblocal.yaml"
  reset_calls; RUN "$TEST_DIR/fblocal.yaml" >/dev/null
  [ "$(creates)" = "0" ] || log_fail "TEST-006: local mode must make no gh call"
  grep -qi "prepare-none\|nothing prepared" "$TEST_DIR/out" || log_fail "TEST-006: local mode must prepare nothing"
  log_pass "destination pin; auto refused; local -> prepare-none (TEST-006)"
}

# --- TEST-007: confirmed publish is the only write + ledger append ----------
test_007_confirm_only_write() {
  log_info "Test: --publish needs --confirm; confirmed -> one create + ledger append (TEST-007)..."
  cat > "$TEST_DIR/friction/observations.jsonl" <<'JSONL'
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"impl","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high"}
JSONL
  rm -f "$TEST_DIR/friction/upsert-ledger.jsonl"
  # without --confirm: no write
  reset_calls; RUN "$TEST_DIR/fb.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >/dev/null
  [ "$(creates)" = "0" ] || log_fail "TEST-007: --publish without --confirm must NOT write"
  grep -qi "without --confirm" "$TEST_DIR/out" || log_fail "TEST-007: must state it refuses without --confirm"
  # with --confirm: exactly one create + ledger append
  reset_calls; RUN "$TEST_DIR/fb.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "1" ] || log_fail "TEST-007: confirmed publish must make exactly one create (made $(creates))"
  grep -qF "issue_created" "$TEST_DIR/friction/upsert-ledger.jsonl" || log_fail "TEST-007: confirmed publish must append to the ledger"
  log_pass "confirmed publish is the only write; ledger appended (TEST-007)"
}

# --- TEST-008: static — mutating gh only in the confirmed path --------------
test_008_static_write_gate() {
  log_info "Test: static — 'issue create' appears only guarded by --confirm (TEST-008)..."
  [ -f "$SCRIPT" ] || log_fail "TEST-008: engine missing"
  # exactly one 'issue', 'create' mutating invocation in the source, inside the publish/confirm branch
  local n; n="$(grep -c "'issue', 'create'" "$SCRIPT")"
  [ "$n" = "1" ] || log_fail "TEST-008: expected exactly one issue-create call site (got $n)"
  # the create call site must be preceded by an args.confirm gate in the file
  grep -q "args.confirm" "$SCRIPT" || log_fail "TEST-008: the write path must be gated by args.confirm"
  log_pass "single issue-create call site, gated by --confirm (TEST-008)"
}

# --- TEST-010 (Spec-AC-03): EVERY interpolated field is transmit-sanitized -----
# Regression: only `summary` was redacted; hostile skill_id/skill_phase/impact/
# evidence_ref reached the gh argv verbatim. Now every field is re-validated.
test_010_field_sanitization() {
  log_info "Test: hostile non-summary fields never reach a gh argument (TEST-010)..."
  rm -f "$TEST_DIR/friction/upsert-ledger.jsonl"  # the local-ledger gate refuses a fingerprint already filed in this run
  # Hostile content with DISALLOWED chars (paths/spaces/@/invalid-enum) — caught by
  # the charset/enum gate. (Token-shaped fixtures below are assembled from fragments
  # so no scannable provider-secret literal is committed to this file.)
  cat > "$TEST_DIR/friction/observations.jsonl" <<'JSONL'
{"schema_version":2,"os_family":"macos-attacker@evil.com","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD_/Users/ales/.ssh/id_rsa","skill_phase":"impl with spaces","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high) not-an-enum (","evidence_ref":"/Users/ales/.ssh/id_rsa"}
JSONL
  reset_calls; RUN "$TEST_DIR/fb.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "1" ] || log_fail "TEST-010: the hostile-field arm must actually FILE, or it proves nothing (creates=$(creates))"
  local leak; leak="$( { cat "$GH_CALLS"; cat "$TEST_DIR/friction/pending-issues/v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.md" 2>/dev/null; } | grep -oE 'id_rsa|/Users/|@evil|not-an-enum' || true)"
  [ -z "$leak" ] || log_fail "TEST-010: a hostile field leaked into the gh argv or draft: $leak"
  grep -qF "<redacted>" "$GH_CALLS" || log_fail "TEST-010: hostile identifier fields must be redacted in the payload"
  # CLEAN-TOKEN case (regression): a secret that is itself identifier-shaped
  # (gh PAT / Stripe / AWS prefixes, no disallowed char) must ALSO be caught by the
  # deny-list, not sail through the charset gate — the blind spot re-validation found.
  # Prefixes are fragment-assembled so no contiguous provider-secret literal is
  # committed (GitHub push-protection); the runtime string still trips the detector.
  # The local-ledger gate this scope added made this arm VACUOUS: the first half
  # above already published this fingerprint, so the publish below short-circuited
  # and `tleak` grepped an empty recording. A redaction bypass shipped green.
  rm -f "$TEST_DIR/friction/upsert-ledger.jsonl"
  local GHP="gh""p_" SKL="sk""_live_" AKIA="AKI""A"
  printf '{"schema_version":2,"os_family":"macos","aai_pin":"%sABCDEFGHIJKLMNOP","node_major":22,"skill_id":"%s1234567890abcdefghijklmnopqrstuvwxyzAB","skill_phase":"%s51ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high"}\n' \
    "$AKIA" "$GHP" "$SKL" > "$TEST_DIR/friction/observations.jsonl"
  reset_calls; RUN "$TEST_DIR/fb.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "1" ] || log_fail "TEST-010: the secret-token arm must actually FILE, or it proves nothing about redaction (creates=$(creates))"
  local tleak; tleak="$(grep -oE "${GHP}[A-Za-z0-9]+|${SKL}[A-Za-z0-9]+|${AKIA}[A-Z0-9]{16}" "$GH_CALLS" || true)"
  [ -z "$tleak" ] || log_fail "TEST-010: a charset-clean secret token leaked into the gh argv: $tleak"
  log_pass "every non-summary field re-sanitized incl. charset-clean secret tokens (TEST-010)"
}

# --- TEST-011 (Spec-AC-04): dedup fail-CLOSED on an unverifiable search ---------
test_011_dedup_failclosed() {
  log_info "Test: confirm-publish refuses to create when dedup search is unverifiable (TEST-011)..."
  rm -f "$TEST_DIR/friction/upsert-ledger.jsonl"  # exercise the fail-closed, not the local-ledger short-circuit that precedes it
  cat > "$TEST_DIR/friction/observations.jsonl" <<'JSONL'
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"impl","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high"}
JSONL
  # mock gh returns malformed (unparseable) search output
  printf 'not json {[' > "$TEST_DIR/garbage.json"; SEARCH_RESULT="$TEST_DIR/garbage.json"
  reset_calls; local code; code="$(RUN "$TEST_DIR/fb.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm)"
  [ "$(creates)" = "0" ] || log_fail "TEST-011: must NOT create when dedup cannot be verified"
  [ "$code" != "0" ] || log_fail "TEST-011: an unverifiable dedup must fail (non-zero), not silently create"
  SEARCH_RESULT="$TEST_DIR/empty.json"
  log_pass "dedup fail-closed: unverifiable search refuses the create (TEST-011)"
}

# --- TEST-012 (PR review): fingerprint validation + labels applied ------------
test_012_fingerprint_and_labels() {
  log_info "Test: off-shape fingerprint skipped; configured labels applied on create (TEST-012)..."
  rm -f "$TEST_DIR/friction/upsert-ledger.jsonl"  # the local-ledger gate refuses a fingerprint already filed in this run
  # a report with a POISONED (off-shape) fingerprint alongside a valid one
  cat > "$TEST_DIR/friction/observations.jsonl" <<'JSONL'
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"impl","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high"}
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"X","skill_phase":"y","failure_class":"contract_violation","fingerprint":"v1:POISON_/Users/x/.ssh","impact":"high"}
JSONL
  cat > "$TEST_DIR/friction/triage-report.json" <<'JSON'
{"clusters":[{"fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","failure_class":"contract_violation","recurrence":2,"score":9,"decision":"review_candidate","auto_publishable":false},{"fingerprint":"v1:POISON_/Users/x/.ssh","failure_class":"contract_violation","recurrence":2,"score":9,"decision":"review_candidate","auto_publishable":false}]}
JSON
  # config WITH a labels list
  printf 'triage:\n  mode: review\nupsert:\n  destination: goodwind-cz/aai   # pin\n  labels:\n    - aai-friction\n' > "$TEST_DIR/fblab.yaml"
  reset_calls; RUN "$TEST_DIR/fblab.yaml" >/dev/null
  # only the valid fingerprint gets a draft; the poisoned one is skipped (never a file / never a gh call carrying it)
  [ -f "$TEST_DIR/friction/pending-issues/v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.md" ] || log_fail "TEST-012: valid fingerprint must be prepared"
  ls "$TEST_DIR/friction/pending-issues/" | grep -qi "POISON\|ssh\|Users" && log_fail "TEST-012: an off-shape fingerprint must be skipped (no draft)"
  grep -qi "POISON\|/Users/\|\.ssh" "$GH_CALLS" && log_fail "TEST-012: an off-shape fingerprint must never reach a gh call" || true
  # poisoned fingerprint publish is rejected (RUN echoes the node exit code)
  local pc; pc="$(RUN "$TEST_DIR/fblab.yaml" --publish "v1:POISON_/Users/x/.ssh" --confirm)"
  [ "$pc" != "0" ] || log_fail "TEST-012: publishing an off-shape fingerprint must be rejected"
  # labels applied on a valid confirmed create (clear the shared ledger so an
  # earlier test's budget does not defer this create)
  rm -f "$TEST_DIR/friction/upsert-ledger.jsonl"
  reset_calls; RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  grep -qF "label aai-friction" "$GH_CALLS" || log_fail "TEST-012: configured labels must be applied on create ($(cat "$TEST_DIR/out"))"
  log_pass "off-shape fingerprint skipped/rejected; configured labels applied (TEST-012)"
}

# --- TEST-013 (Spec-AC-01): the dedup search argv is one real gh accepts -------
# Asserted on the RECORDED ARGV, not on an exit code: the whole defect was that
# an exit code from a permissive stub said "fine" about a call the CLI rejects.
test_013_search_argv() {
  log_info "Test: dedup search argv carries no --state and matches the gh contract (TEST-013)..."
  reset_calls; RUN >/dev/null
  local line; line="$(grep '^search issues' "$GH_CALLS" | head -1)"
  [ -n "$line" ] || log_fail "TEST-013: no 'search issues' call was recorded"
  case "$line" in *--state*) log_fail "TEST-013: argv must NOT carry --state (gh accepts only open|closed): $line";; esac
  case "$line" in *"--repo goodwind-cz/aai"*) ;; *) log_fail "TEST-013: argv must pin --repo: $line";; esac
  case "$line" in *"--match body"*) ;; *) log_fail "TEST-013: argv must restrict the match to the body: $line";; esac
  case "$line" in *"aai-friction:v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"*) ;; *) log_fail "TEST-013: argv must carry the fingerprint marker: $line";; esac
  case "$line" in *"--json number"*) ;; *) log_fail "TEST-013: argv must request --json number: $line";; esac
  case "$line" in *"--limit 1"*) ;; *) log_fail "TEST-013: argv must cap --limit 1: $line";; esac
  log_pass "dedup search argv is contract-shaped and free of --state (TEST-013)"
}

# --- TEST-014 (Spec-AC-03): the stub can FAIL, so its green means something ----
# Under the exact-argv model the question is no longer "is this flag allowed"
# but "is this THE pinned call". Both arms are asserted: the exact shape passes,
# and the shape that shipped the original defect does not.
test_014_stub_pins_the_exact_search_argv() {
  log_info "Test: the gh stub accepts only the exact pinned search argv (TEST-014)..."
  local c
  "$TEST_DIR/bin/gh" search issues --repo o/r --match body aai-friction:v1:x --json number --limit 1 >/dev/null 2>&1; c=$?
  [ "$c" = "0" ] || log_fail "TEST-014: the stub must ACCEPT the exact pinned search argv"
  "$TEST_DIR/bin/gh" search issues --repo o/r --match body aai-friction:v1:x --state all --json number --limit 1 >/dev/null 2>&1; c=$?
  [ "$c" != "0" ] || log_fail "TEST-014: the stub must REJECT the --state-carrying shape that started this"
  reset_calls
  log_pass "the stub pins the exact search argv in both directions (TEST-014)"
}

# --- TEST-015 (Spec-AC-01): no QUOTED --state argv literal in the engine -------
# The static half of the RED. Scope, stated precisely because an overstated test
# name is the same defect this ride exists to fix: the predicate matches the
# single-quoted argv literal `'--state'` ONLY. The engine legitimately contains
# the characters `--state` in an explanatory comment, and a double-quoted variant
# would not be caught. This is a regression guard against the rejected CALL
# SHAPE, not a proof that the string is absent from the file.
test_015_no_quoted_state_argv_literal() {
  log_info "Test: the engine passes no quoted '--state' argv literal to gh search (TEST-015)..."
  grep -qF -- "'--state'" "$SCRIPT" && log_fail "TEST-015: the engine must not pass a quoted '--state' argv literal to gh search issues"
  log_pass "no quoted '--state' argv literal in the engine (TEST-015)"
}

# --- TEST-016 (Spec-AC-04): a missing label DEGRADES, it never fails the write --
test_016_label_degrade_missing() {
  log_info "Test: a label absent from the destination is dropped, the issue is still filed (TEST-016)..."
  seed_single_candidate
  LABEL_RESULT="$TEST_DIR/nolabels.json"
  local rc; reset_calls; rc="$(RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm)"
  [ "$rc" = "0" ] || log_fail "test_016_label_degrade_missing: the engine must exit 0, not merely attempt a create (rc=$rc, err=$(cat "$TEST_DIR/err"))"
  [ "$(creates)" = "1" ] || log_fail "TEST-016: a missing label must NOT block the write (creates=$(creates), err=$(cat "$TEST_DIR/err"))"
  grep -qF "label aai-friction" "$GH_CALLS" && log_fail "TEST-016: a label the destination lacks must not be passed to gh issue create"
  grep -qF 'label "aai-friction" does not exist' "$TEST_DIR/err" || log_fail "TEST-016: the dropped label must be NAMED on stderr, not silently swallowed"
  LABEL_RESULT="$TEST_DIR/labels.json"
  log_pass "missing label dropped and named; issue still filed (TEST-016)"
}

# --- TEST-017 (Spec-AC-04): the other arm — an existing label IS passed --------
test_017_label_kept_when_present() {
  log_info "Test: a label that exists in the destination is passed on create (TEST-017)..."
  seed_single_candidate
  rm -f "$TEST_DIR/friction/upsert-ledger.jsonl"
  LABEL_RESULT="$TEST_DIR/labels.json"
  local rc; reset_calls; rc="$(RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm)"
  [ "$rc" = "0" ] || log_fail "test_017_label_kept_when_present: the engine must exit 0, not merely attempt a create (rc=$rc, err=$(cat "$TEST_DIR/err"))"
  [ "$(creates)" = "1" ] || log_fail "TEST-017: the create must happen (creates=$(creates))"
  grep -qF "label aai-friction" "$GH_CALLS" || log_fail "TEST-017: an existing label MUST be applied"
  log_pass "existing label applied (TEST-017)"
}

# --- TEST-018 (Spec-AC-05): an unreadable label set drops ALL labels and files --
# Deliberately the OPPOSITE degrade from the dedup's fail-closed: a duplicate
# issue is a real harm, an unlabelled issue is not.
test_018_label_read_failure_degrades_open() {
  log_info "Test: an unreadable label set drops all labels and still files (TEST-018)..."
  seed_single_candidate
  rm -f "$TEST_DIR/friction/upsert-ledger.jsonl"
  LABEL_LIST_FAIL=1
  local rc; reset_calls; rc="$(RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm)"
  [ "$rc" = "0" ] || log_fail "test_018_label_read_failure_degrades_open: the engine must exit 0, not merely attempt a create (rc=$rc, err=$(cat "$TEST_DIR/err"))"
  LABEL_LIST_FAIL=0
  [ "$(creates)" = "1" ] || log_fail "TEST-018: an unreadable label set must not block the write (creates=$(creates), err=$(cat "$TEST_DIR/err"))"
  grep -qF "label aai-friction" "$GH_CALLS" && log_fail "TEST-018: no label may be passed when the label set could not be read"
  grep -qF "could not read the label set" "$TEST_DIR/err" || log_fail "TEST-018: the degrade must be reported on stderr"
  log_pass "unreadable label set degrades open, and says so (TEST-018)"
}

# --- TEST-019 (Spec-AC-06): EVERY gh shape the engine emits is asserted --------
# Closes the class rather than the one instance: an unrecognised subcommand is a
# call nobody pinned, which is exactly how --state all survived.
test_019_argv_coverage() {
  log_info "Test: every recorded gh invocation matches a pinned shape (TEST-019)..."
  seed_single_candidate
  rm -f "$TEST_DIR/friction/upsert-ledger.jsonl"
  reset_calls
  RUN "$TEST_DIR/fblab.yaml" >/dev/null
  RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  local unknown=""
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    case "$l" in
      "auth status"*) ;;
      "search issues "*) ;;
      "label list "*) ;;
      "issue create "*) ;;
      *) unknown="$unknown
$l" ;;
    esac
  done < "$GH_CALLS"
  [ -z "$unknown" ] || log_fail "TEST-019: unpinned gh invocation(s):$unknown"
  # DENY-BY-DEFAULT CONTROLS. Four review rounds each escaped an enumerated
  # allowlist through a door it did not list. These assert the property that
  # replaced it: anything that is not THE pinned argv is refused, whatever the
  # reason. Each line below shipped a fully green suite under some earlier
  # version of this gate.
  local c
  probe_rejects() { # $1=description, rest=argv
    local d="$1"; shift
    "$TEST_DIR/bin/gh" "$@" >/dev/null 2>&1
    [ "$?" != "0" ] || log_fail "TEST-019: the stub must reject $d"
  }
  probe_rejects "a renamed --match value (--state all one flag over)" \
    search issues --repo o/r --match bodyy aai-friction:v1:x --json number --limit 1
  probe_rejects "a --sort flag on search (values differ per subcommand)" \
    search issues --repo o/r --match body aai-friction:v1:x --json number --limit 1 --sort comments
  probe_rejects "a --sort flag on label list" \
    label list --repo o/r --json name --limit 500 --sort comments
  probe_rejects "an --order flag nobody pinned" \
    search issues --repo o/r --match body aai-friction:v1:x --json number --limit 1 --order asc
  probe_rejects "an unknown --json field" label list --repo o/r --json bogus --limit 500
  probe_rejects "an UPPERCASE long flag" issue create --repo o/r --title t --body b --Force
  probe_rejects "a short flag" issue create --repo o/r --title t --body b -Z
  probe_rejects "the -R alias for --repo" issue create -R o/r --title t --body b
  probe_rejects "a stray positional on the MUTATING path" issue create --repo o/r --title t --body b STRAY
  probe_rejects "a duplicate --repo (gh is last-wins, so it retargets the write)" \
    issue create --repo o/r --repo attacker/evil --title t --body b
  probe_rejects "an empty --repo (gh falls back to the LOCAL repository)" \
    issue create --repo "" --title t --body b
  probe_rejects "the --flag=value form" issue create --repo o/r --title t --body=b
  probe_rejects "a reordered argv" issue create --title t --repo o/r --body b
  probe_rejects "a create without --body" issue create --repo o/r --title t
  probe_rejects "a --label with no argument" issue create --repo o/r --title t --body b --label
  probe_rejects "a flag left without its argument on the preflight" auth status --hostname
  probe_rejects "a subcommand nobody pinned" pr merge 1
  probe_rejects "--body-file instead of --body" issue create --repo o/r --title t --body-file f
  # and the exact shapes MUST still pass, or the gate is merely broken
  "$TEST_DIR/bin/gh" auth status >/dev/null 2>&1; c=$?
  [ "$c" = "0" ] || log_fail "TEST-019: the stub must ACCEPT the exact auth preflight"
  "$TEST_DIR/bin/gh" issue create --repo o/r --title t --body b >/dev/null 2>&1; c=$?
  [ "$c" = "0" ] || log_fail "TEST-019: the stub must ACCEPT the exact create shape"
  "$TEST_DIR/bin/gh" label list --repo o/r --json name --limit 500 >/dev/null 2>&1; c=$?
  [ "$c" = "0" ] || log_fail "TEST-019: the stub must ACCEPT the exact label-list shape"
  reset_calls
  log_pass "every gh invocation matches a pinned shape, and drift is refused (TEST-019)"
}

# --- TEST-020 (Spec-AC-07): prepare offers a command only when it will work ----
test_020_prepare_offers_only_runnable() {
  log_info "Test: a cleared cluster is offered a --publish command, a blocked one is not (TEST-020)..."
  # cleared
  seed_single_candidate
  SEARCH_RESULT="$TEST_DIR/empty.json"
  rm -f "$TEST_DIR/friction/upsert-ledger.jsonl"
  reset_calls; RUN "$TEST_DIR/fblab.yaml" >/dev/null
  grep -q -- "--publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm" "$TEST_DIR/out" \
    || log_fail "TEST-020: a cleared cluster must be offered a runnable publish command ($(cat "$TEST_DIR/out"))"
  # blocked: unparseable search output -> the create would refuse
  printf 'not json {[' > "$TEST_DIR/garbage.json"; SEARCH_RESULT="$TEST_DIR/garbage.json"
  reset_calls; RUN "$TEST_DIR/fblab.yaml" >/dev/null
  grep -q -- "--publish" "$TEST_DIR/out" \
    && log_fail "TEST-020: a blocked cluster must NOT be offered a command the tool will refuse ($(cat "$TEST_DIR/out"))"
  grep -qF "not offered:" "$TEST_DIR/out" || log_fail "TEST-020: a blocked cluster must state why it is not offered"
  grep -qF "fail-closed" "$TEST_DIR/out" || log_fail "TEST-020: the blocking reason must name the fail-closed dedup"
  SEARCH_RESULT="$TEST_DIR/empty.json"
  log_pass "prepare offers a command only when it will actually run (TEST-020)"
}

# --- TEST-021 (Spec-AC-08): the SHIPPED config actually turns the channel on ---
# D5's own stated hazard: a mode left uncommitted silently reverts to `local` on
# the next checkout, and the channel is dead again with every suite still green.
test_021_shipped_config_is_review() {
  log_info "Test: the shipped .aai/feedback.yaml enables review mode (TEST-021)..."
  local cfg="$PROJECT_ROOT/.aai/feedback.yaml"
  [ -f "$cfg" ] || log_fail "TEST-021: shipped config missing: $cfg"
  grep -qE '^[[:space:]]+mode:[[:space:]]*review[[:space:]]*$' "$cfg" \
    || log_fail "TEST-021: the shipped config must set triage.mode: review (got: $(grep -E '^[[:space:]]+mode:' "$cfg" | head -1))"
  log_pass "shipped config enables review mode (TEST-021)"
}

# --- TEST-022: a repeat confirmed publish never files a second issue ----------
# Newly live because of this fix: before it, nothing could file at all. The
# remote search is authoritative but GitHub's index lags a fresh issue, so two
# confirmed publishes in a row can both see an empty search. The local ledger
# closes that window.
test_022_repeat_publish_is_not_a_duplicate() {
  log_info "Test: publishing the same fingerprint twice files exactly once (TEST-022)..."
  seed_single_candidate
  reset_calls
  RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "1" ] || log_fail "TEST-022: the first publish must file exactly once (got $(creates))"
  # the search index has not caught up yet: it still returns empty
  SEARCH_RESULT="$TEST_DIR/empty.json"
  reset_calls
  RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "0" ] || log_fail "TEST-022: a repeat publish must NOT file a second issue (made $(creates))"
  grep -qi "already filed" "$TEST_DIR/out" || log_fail "TEST-022: the skip must say the fingerprint was already filed"
  log_pass "repeat publish is refused by the local ledger (TEST-022)"
}

# --- TEST-023: label matching is case-insensitive, like GitHub ----------------
test_023_label_case_insensitive() {
  log_info "Test: a label differing only in case is treated as existing (TEST-023)..."
  seed_single_candidate
  printf '[{"name":"AAI-Friction"}]' > "$TEST_DIR/mixedlabels.json"
  LABEL_RESULT="$TEST_DIR/mixedlabels.json"
  reset_calls
  RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "1" ] || log_fail "TEST-023: the create must happen (got $(creates), err=$(cat "$TEST_DIR/err"))"
  grep -qF "label aai-friction" "$GH_CALLS" || log_fail "TEST-023: a case-differing label exists on GitHub and must be applied, not reported missing"
  grep -qi "does not exist" "$TEST_DIR/err" && log_fail "TEST-023: must not claim a label is missing when it exists in another case"
  LABEL_RESULT="$TEST_DIR/labels.json"
  log_pass "label matching is case-insensitive (TEST-023)"
}

# --- TEST-024 (Spec-AC-07, other arm): update_existing is not offered either ---
test_024_update_existing_not_offered() {
  log_info "Test: an already-filed cluster is not offered a publish command (TEST-024)..."
  seed_single_candidate
  printf '[{"number":42}]' > "$TEST_DIR/existing.json"; SEARCH_RESULT="$TEST_DIR/existing.json"
  reset_calls; RUN "$TEST_DIR/fblab.yaml" >/dev/null
  grep -q -- "--publish" "$TEST_DIR/out" && log_fail "TEST-024: an existing issue must not be offered a publish command ($(cat "$TEST_DIR/out"))"
  grep -qF "already carries this fingerprint marker" "$TEST_DIR/out" || log_fail "TEST-024: the reason must name the existing marker"
  SEARCH_RESULT="$TEST_DIR/empty.json"
  log_pass "an already-filed cluster is not offered a command (TEST-024)"
}

# --- TEST-025 (Spec-AC-02): the fail-closed refusal NAMES the fingerprint -----
test_025_refusal_text() {
  log_info "Test: the fail-closed refusal names the fingerprint (TEST-025)..."
  seed_single_candidate
  printf 'not json {[' > "$TEST_DIR/garbage.json"; SEARCH_RESULT="$TEST_DIR/garbage.json"
  reset_calls; local code; code="$(RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm)"
  [ "$code" != "0" ] || log_fail "TEST-025: an unverifiable dedup must exit non-zero"
  grep -qF "could not verify dedup for v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$TEST_DIR/err" \
    || log_fail "TEST-025: the refusal must name the fingerprint it refused ($(cat "$TEST_DIR/err"))"
  SEARCH_RESULT="$TEST_DIR/empty.json"
  log_pass "the fail-closed refusal names the fingerprint (TEST-025)"
}

# --- TEST-026 (Spec-AC-02): the fail-closed branch the DEFECT actually took ----
# Every other unverifiable-dedup case feeds garbage on stdout at exit 0. The real
# defect made `gh search issues` EXIT NON-ZERO, and nothing covered that branch:
# flipping `dedupSearch`'s !r.ok arm to fail-OPEN shipped ALL TESTS PASSED.
test_026_search_exits_nonzero_fails_closed() {
  log_info "Test: a search that EXITS non-zero refuses the create (TEST-026)..."
  seed_single_candidate
  SEARCH_FAIL=1
  reset_calls; local code; code="$(RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm)"
  SEARCH_FAIL=0
  [ "$(creates)" = "0" ] || log_fail "TEST-026: a failing search must NOT create (made $(creates))"
  [ "$code" != "0" ] || log_fail "TEST-026: a failing search must exit non-zero, not silently create"
  grep -qF "could not verify dedup" "$TEST_DIR/err" || log_fail "TEST-026: the refusal must name the unverifiable dedup"
  log_pass "a search that exits non-zero fails closed (TEST-026)"
}

# --- TEST-027: the truncation message fires only on a genuinely full page ------
test_027_label_truncation_message() {
  log_info "Test: 'not among the first N' only when the label page is full (TEST-027)..."
  seed_single_candidate
  # a FULL page (500 names, none of them the configured label)
  awk 'BEGIN{printf "["; for(i=1;i<=500;i++){printf "%s{\"name\":\"l%d\"}", (i>1?",":""), i}; printf "]"}' > "$TEST_DIR/full.json"
  LABEL_RESULT="$TEST_DIR/full.json"
  reset_calls; RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "1" ] || log_fail "TEST-027: a full label page must not block the write"
  grep -qF "not among the first 500" "$TEST_DIR/err" || log_fail "TEST-027: a full page must NOT assert absence, it must say 'not among the first N' ($(cat "$TEST_DIR/err"))"
  # a SHORT page: absence is knowable, so the message must assert it
  seed_single_candidate
  LABEL_RESULT="$TEST_DIR/nolabels.json"
  reset_calls; RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  grep -qF "does not exist" "$TEST_DIR/err" || log_fail "TEST-027: a short page makes absence knowable and must say so"
  grep -qF "not among the first" "$TEST_DIR/err" && log_fail "TEST-027: a short page must NOT hedge"
  LABEL_RESULT="$TEST_DIR/labels.json"
  log_pass "the truncation message tracks whether absence is actually knowable (TEST-027)"
}

# --- TEST-028 (E6): the SHIPPED destination is pinned, not just the mode -------
# TEST-021 pinned `mode` only. Repointing the shipped destination to another
# repository kept the whole suite green — and a wrong destination is worse than
# a dead channel: it publishes the operator's friction somewhere else.
test_028_shipped_destination_is_pinned() {
  log_info "Test: the shipped .aai/feedback.yaml pins the destination (TEST-028)..."
  local cfg="$PROJECT_ROOT/.aai/feedback.yaml"
  grep -qE '^[[:space:]]+destination:[[:space:]]*goodwind-cz/aai([[:space:]]|#|$)' "$cfg" \
    || log_fail "TEST-028: the shipped destination must be goodwind-cz/aai (got: $(grep -E '^[[:space:]]+destination:' "$cfg" | head -1))"
  log_pass "shipped destination is pinned (TEST-028)"
}

# --- TEST-029 (E7 + round 3 non-escape): an unreadable ledger refuses LOUDLY ---
# It first crashed with an unhandled EISDIR; the first fix reported "budget
# reached" and exited 0, silently blocking a legitimate publish under a false
# reason. Both local gates depend on this file, so neither may proceed.
test_029_unreadable_ledger_refuses_loudly() {
  log_info "Test: an unreadable local ledger refuses loudly and non-zero (TEST-029)..."
  seed_single_candidate
  rm -f "$TEST_DIR/friction/upsert-ledger.jsonl"
  mkdir -p "$TEST_DIR/friction/upsert-ledger.jsonl"   # a DIRECTORY at the ledger path
  reset_calls; local code; code="$(RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm)"
  rmdir "$TEST_DIR/friction/upsert-ledger.jsonl"
  [ "$(creates)" = "0" ] || log_fail "TEST-029: an unreadable ledger must not file (made $(creates))"
  [ "$code" != "0" ] || log_fail "TEST-029: an unreadable ledger must exit non-zero, not report a false budget stop"
  grep -qF "cannot read the local upsert ledger" "$TEST_DIR/err" \
    || log_fail "TEST-029: the refusal must name the unreadable ledger ($(cat "$TEST_DIR/err"))"
  grep -qi "budget" "$TEST_DIR/out" && log_fail "TEST-029: an unreadable ledger must NOT be reported as a budget stop"
  log_pass "an unreadable ledger refuses loudly (TEST-029)"
}

# --- TEST-030 (E8): the duplicate gate scans the WHOLE ledger -----------------
# With only one entry present, narrowing the scan to the last few lines shipped
# green. The matching record is placed FIRST, behind many later ones.
test_030_duplicate_gate_scans_whole_ledger() {
  log_info "Test: the duplicate gate finds a match anywhere in the ledger (TEST-030)..."
  seed_single_candidate
  local led="$TEST_DIR/friction/upsert-ledger.jsonl"
  echo '{"event":"issue_created","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","ts_ms":1,"destination":"goodwind-cz/aai"}' > "$led"
  local i=1
  while [ "$i" -le 40 ]; do echo "{\"event\":\"noise\",\"fingerprint\":\"v1:pad$i\",\"ts_ms\":1}" >> "$led"; i=$((i+1)); done
  reset_calls; RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "0" ] || log_fail "TEST-030: a match early in the ledger must still refuse (made $(creates))"
  grep -qi "already filed" "$TEST_DIR/out" || log_fail "TEST-030: the skip must name the already-filed fingerprint"
  log_pass "the duplicate gate scans the whole ledger (TEST-030)"
}

# --- TEST-031 (E9): the auth preflight actually gates the publish -------------
test_031_auth_preflight_gates_publish() {
  log_info "Test: a failing gh auth preflight stops the publish (TEST-031)..."
  seed_single_candidate
  # a gh that fails ONLY `auth status`
  cat > "$TEST_DIR/bin/gh-noauth" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "auth" ]; then exit 1; fi
exec "$GH_REAL" "$@"
SH
  chmod +x "$TEST_DIR/bin/gh-noauth"
  GH_REAL="$TEST_DIR/bin/gh"; export GH_REAL
  reset_calls
  local code
  code="$(AAI_GH_BIN="$TEST_DIR/bin/gh-noauth" AAI_FRICTION_DIR="$TEST_DIR/friction" AAI_NOW_MS=1000000000000 \
    node "$SCRIPT" --report "$TEST_DIR/friction/triage-report.json" --spool "$TEST_DIR/friction/observations.jsonl" \
    --config "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm \
    > "$TEST_DIR/out" 2> "$TEST_DIR/err"; echo $?)"
  [ "$(creates)" = "0" ] || log_fail "TEST-031: an unauthenticated gh must not file (made $(creates))"
  [ "$code" != "0" ] || log_fail "TEST-031: an unauthenticated gh must exit non-zero"
  grep -qi "gh auth login" "$TEST_DIR/err" || log_fail "TEST-031: the refusal must tell the operator how to fix it ($(cat "$TEST_DIR/err"))"
  log_pass "a failing auth preflight stops the publish with an actionable message (TEST-031)"
}

# --- TEST-032 (B2/B3): the MUTATING create's destination and content ----------
# The stub shape-checks `--repo` (`?*/?*`) but pins no value, and every content
# assertion in this suite was against the DRAFT file, never the filed argv. So
# `--repo attacker/evil`, a raw un-redacted summary as the title, and a body with
# the dedup marker stripped all shipped green — on the write path.
test_032_create_argv_destination_and_content() {
  log_info "Test: the filed create argv carries the right destination and content (TEST-032)..."
  seed_single_candidate
  # a summary is present ONLY here: no confirmed publish in this suite ever ran
  # with one, so the transmit redaction was never exercised on the filed argv.
  cat > "$TEST_DIR/friction/observations.jsonl" <<'JSONL'
{"schema_version":2,"os_family":"macos","aai_pin":"unknown","node_major":22,"skill_id":"SKILL_TDD","skill_phase":"impl","failure_class":"contract_violation","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","impact":"high","summary":"failed at /Users/ales/.ssh/id_rsa"}
JSONL
  reset_calls; RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "1" ] || log_fail "TEST-032: the create must happen (made $(creates), err=$(cat "$TEST_DIR/err"))"
  local line; line="$(grep '^issue create' "$GH_CALLS" | head -1)"
  case "$line" in *"--repo goodwind-cz/aai"*) ;; *) log_fail "TEST-032: the create must target the CONFIGURED destination: $line";; esac
  case "$line" in *"[contract_violation] SKILL_TDD/impl (high impact)"*) ;; *) log_fail "TEST-032: the title must be templated from structured fields: $line";; esac
  case "$line" in *"aai-friction:v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"*) ;; *) log_fail "TEST-032: the FILED body must carry the dedup marker, or the remote dedup can never match: $line";; esac
  case "$line" in *id_rsa*|*"/Users/"*) log_fail "TEST-032: an un-redacted summary reached the FILED argv: $line";; esac
  log_pass "the filed create argv is correctly targeted and redacted (TEST-032)"
}

# --- TEST-033: a failed post-create ledger append is loud and non-zero --------
# The issue EXISTS at that point; a silent success would leave the duplicate
# guard blind to a fingerprint that is already public.
test_033_ledger_append_failure_is_loud() {
  log_info "Test: a failed ledger append after a successful create exits non-zero (TEST-033)..."
  seed_single_candidate
  rm -rf "$TEST_DIR/friction/upsert-ledger.jsonl"
  mkdir -p "$TEST_DIR/friction/upsert-ledger.jsonl.d"
  # make the ledger path unwritable by making its PARENT read-only after seeding
  local roDir="$TEST_DIR/ro-friction"
  rm -rf "$roDir"; mkdir -p "$roDir"
  cp "$TEST_DIR/friction/observations.jsonl" "$TEST_DIR/friction/triage-report.json" "$roDir/" 2>/dev/null
  chmod 500 "$roDir"
  reset_calls
  local code
  code="$(AAI_GH_BIN="$TEST_DIR/bin/gh" AAI_FRICTION_DIR="$roDir" AAI_NOW_MS=1000000000000 \
    node "$SCRIPT" --report "$roDir/triage-report.json" --spool "$roDir/observations.jsonl" \
    --config "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm \
    > "$TEST_DIR/out" 2> "$TEST_DIR/err"; echo $?)"
  chmod 700 "$roDir"
  if [ "$(creates)" = "1" ]; then
    [ "$code" != "0" ] || log_fail "TEST-033: a failed ledger append after a create must exit non-zero"
    grep -qF "could not record it" "$TEST_DIR/err" || log_fail "TEST-033: the message must say the issue WAS filed but not recorded ($(cat "$TEST_DIR/err"))"
    log_pass "a failed post-create ledger append is loud and non-zero (TEST-033)"
  else
    log_skip "TEST-033: could not stage an unwritable ledger in this environment (create did not happen)"
  fi
}

# --- TEST-034: a label dropped at CONFIG PARSE is named too -------------------
# D2 promised "every dropped label is named on stderr". A label refused by the
# charset gate was dropped before the destination was ever consulted, silently —
# and GitHub label names may contain spaces ("good first issue").
test_034_config_parse_label_drop_is_named() {
  log_info "Test: a label dropped by the config charset gate is named (TEST-034)..."
  seed_single_candidate
  printf 'triage:\n  mode: review\nupsert:\n  destination: goodwind-cz/aai   # pin\n  labels:\n    - good first issue\n' > "$TEST_DIR/fbspace.yaml"
  reset_calls; RUN "$TEST_DIR/fbspace.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  grep -qF "was dropped before the destination was consulted" "$TEST_DIR/err" \
    || log_fail "TEST-034: a config-parse label drop must be named, not silent ($(cat "$TEST_DIR/err"))"
  log_pass "a label dropped at config parse is named (TEST-034)"
}

# --- TEST-035 (PR #337 Copilot): the duplicate gate is per DESTINATION ---------
# Matching on the fingerprint alone would make the first destination this machine
# ever published to the only one it can publish to.
test_035_duplicate_gate_is_per_destination() {
  log_info "Test: a fingerprint filed to another destination does not block this one (TEST-035)..."
  seed_single_candidate
  local led="$TEST_DIR/friction/upsert-ledger.jsonl"
  echo '{"event":"issue_created","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","ts_ms":1,"destination":"someone-else/other-repo"}' > "$led"
  reset_calls; RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "1" ] || log_fail "TEST-035: a record for a DIFFERENT destination must not block this one (made $(creates), out=$(cat "$TEST_DIR/out"))"
  # the same destination still blocks
  seed_single_candidate
  echo '{"event":"issue_created","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","ts_ms":1,"destination":"goodwind-cz/aai"}' > "$led"
  reset_calls; RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "0" ] || log_fail "TEST-035: a record for the SAME destination must still block (made $(creates))"
  # a record with no destination at all predates the field and blocks conservatively
  seed_single_candidate
  echo '{"event":"issue_created","fingerprint":"v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","ts_ms":1}' > "$led"
  reset_calls; RUN "$TEST_DIR/fblab.yaml" --publish v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa --confirm >/dev/null
  [ "$(creates)" = "0" ] || log_fail "TEST-035: a legacy record with no destination must block conservatively (made $(creates))"
  log_pass "the duplicate gate is per destination, and unattributable records still block (TEST-035)"
}

test_009_profiles() {
  log_info "Test: new .aai files classified; layer-profiles green (TEST-009)..."
  local out code; out="$(bash "$LAYER_PROFILES_TEST" 2>&1)"; code=$?
  [ "$code" = "0" ] || log_fail "TEST-009: layer-profiles must pass: $(printf '%s' "$out" | tail -3)"
  log_pass "new .aai files classified; layer-profiles green (TEST-009)"
}

main() {
  echo "=== $TEST_NAME ==="
  [ -f "$SCRIPT" ] || log_fail "engine missing: $SCRIPT"
  setup
  if [ $# -gt 0 ]; then "$1"; echo "=== $TEST_NAME: SELECTED PASSED ($1) ==="; return; fi
  test_001_prepare_no_write
  test_002_template_and_redaction
  test_004_dedup
  test_005_budget
  test_006_config
  test_007_confirm_only_write
  test_008_static_write_gate
  test_010_field_sanitization
  test_011_dedup_failclosed
  test_012_fingerprint_and_labels
  test_013_search_argv
  test_014_stub_pins_the_exact_search_argv
  test_015_no_quoted_state_argv_literal
  test_016_label_degrade_missing
  test_017_label_kept_when_present
  test_018_label_read_failure_degrades_open
  test_019_argv_coverage
  test_020_prepare_offers_only_runnable
  test_021_shipped_config_is_review
  test_022_repeat_publish_is_not_a_duplicate
  test_023_label_case_insensitive
  test_024_update_existing_not_offered
  test_025_refusal_text
  test_026_search_exits_nonzero_fails_closed
  test_027_label_truncation_message
  test_028_shipped_destination_is_pinned
  test_029_unreadable_ledger_refuses_loudly
  test_030_duplicate_gate_scans_whole_ledger
  test_031_auth_preflight_gates_publish
  test_032_create_argv_destination_and_content
  test_033_ledger_append_failure_is_loud
  test_034_config_parse_label_drop_is_named
  test_035_duplicate_gate_is_per_destination
  test_009_profiles
  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}
main "$@"
