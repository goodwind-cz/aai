#!/usr/bin/env bash
#
# test-aai-golden-flow.sh — the deterministic downstream golden flow and the
# route-independent "nothing left behind" gate
# (ref simple-and-friendly-to-use / SPEC-0172-spec-simple-and-friendly-to-use,
# TEST-001..007).
#
# Covers .aai/scripts/golden-flow.mjs (builds a fresh downstream target from
# tests/fixtures/target-project + aai-sync.sh, drives one feature ride and one
# bug-fix ride through the ride's own CLIs with stdin closed and a per-step
# timeout, appends ONE record line, `--diff` compares the last two) and
# .aai/scripts/nothing-left-behind.mjs (four classes: git status, docs-audit
# strict, the ride's own intake+spec status, self-referential open follow-ups).
#
#   TEST-001  full run under env -i: exit 0; steps_failed 0, questions_asked 0,
#             files_left 0, docs_open 0; intake docs read status: done; main
#             carries the merge and close commits
#   TEST-002  seam S1: origin is bare with HEAD on refs/heads/main; every step's
#             command path starts with the fixture root, never this checkout
#   TEST-003  --steps-from with a stdin-reading step and an exit-3 step: exit 1,
#             `questions` lists both with command, exit code, output text; a
#             step that outlives its timeout is recorded as timed out
#   TEST-004  gate, five arms: CLEAN exits 0; untracked file, false-open doc,
#             draft intake for a merged ref, open ceremony follow-up each exit 1
#             ALONE and are named under the right class; --json counts match
#   TEST-005  the class-4 id-prefix rule is a closed list: a ceremony-subject id
#             (fu-close-*) IS counted; fu-amend-* and fu-gate-* are NOT, however
#             they are worded; another ref_id is ignored
#   TEST-006  the record's three gate fields equal the gate's --json on the same
#             fixture (mutation: a planted untracked file moves files_left to 1
#             in both); SKILL_PR names the gate after the close ceremony and
#             before the push, and says STOP
#   TEST-007  two runs append two lines and the first stays byte-identical;
#             every named field present; --diff exits 0 on equal counts and 1
#             when a planted second run raised files_left; tokens_median_last10
#             is null without --metrics and 1640003 on a fixture ledger of ten
#   TEST-008  the terminal doc-status set and the docs EXCLUDE_DIRS list each
#             live in exactly ONE file (lib/docs-model.mjs, lib/docs-audit-core.mjs),
#             the gate imports both, and it obeys them: `status: current` is
#             terminal and a doc under docs/templates/ is invisible; and the
#             ceremony-subject prefix list lives only in nothing-left-behind.mjs
#
# Every fixture lives under one mktemp root (HAZ-SCRATCH); every path is
# asserted non-empty and absolute before a `cd` or a `-C` (HAZ-CD); the flow
# is never pointed at this checkout's .git.
#
# Usage:
#   bash tests/skills/test-aai-golden-flow.sh              # all tests
#   bash tests/skills/test-aai-golden-flow.sh test_004_gate_five_arms
#
# Exit codes: 0 all passed; 1 a test failed; 42 skipped (missing deps).

set -euo pipefail

TEST_NAME="aai-golden-flow"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FLOW="$PROJECT_ROOT/.aai/scripts/golden-flow.mjs"
GATE="$PROJECT_ROOT/.aai/scripts/nothing-left-behind.mjs"
FOLLOW_UPS="$PROJECT_ROOT/.aai/scripts/follow-ups.mjs"
APPEND_EVENT="$PROJECT_ROOT/.aai/scripts/append-event.mjs"
SKILL_PR="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"

TEST_DIR=""
cleanup() {
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

# abs_nonempty <path> <label> — HAZ-CD: refuse an empty or relative path
# before it reaches a `cd`, a `-C`, or an `rm -rf`.
abs_nonempty() {
  local p="$1" label="$2"
  [[ -n "$p" ]] || log_fail "$label: path is empty"
  case "$p" in /*) ;; *) log_fail "$label: path is not absolute: $p" ;; esac
}

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$FOLLOW_UPS" ]] || log_fail "follow-ups.mjs not found: $FOLLOW_UPS"
  [[ -f "$APPEND_EVENT" ]] || log_fail "append-event.mjs not found: $APPEND_EVENT"
  # FLOW and GATE are deliberately NOT required here: TEST-004 and TEST-007
  # RED while the scripts are absent (script-absent RED, stored under docs/ai/tdd/).
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-golden-flow.XXXXXX")"
  abs_nonempty "$TEST_DIR" "TEST_DIR"
  # macOS exports TMPDIR with a trailing slash, so mktemp yields a `//` path;
  # the flow normalizes its --out, so every path this suite compares against
  # the flow's own (origin URL, steps.log) must be normalized the same way.
  TEST_DIR="$(cd "$TEST_DIR" && pwd)"
  log_pass "Dependencies checked"
}

# json_field <file> <js-expression over the LAST JSON line as `r`> — prints
# the value; a pipe-free node read so an assertion never dies on its payload.
json_field() {
  local file="$1" expr="$2"
  node -e '
    const fs = require("node:fs");
    const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter(l => l.trim());
    const r = JSON.parse(lines[lines.length - 1]);
    const v = (new Function("r", "return (" + process.argv[2] + ")"))(r);
    process.stdout.write(v === null ? "null" : typeof v === "object" ? JSON.stringify(v) : String(v));
  ' "$file" "$expr"
}

# --- gate fixture builders --------------------------------------------------

# new_gate_repo <name> <slug> <intake_status> <spec_status> -> prints the repo
# path. A throwaway git repo with an intake CHANGE doc (frontmatter id = slug),
# a spec linked to it, an enforced docs-audit.yaml, empty EVENTS + decisions
# ledgers, one commit, and a bare origin whose HEAD is refs/heads/main.
new_gate_repo() {
  local name="$1" slug="$2" intake_status="$3" spec_status="$4"
  local dir="$TEST_DIR/$name"
  abs_nonempty "$dir" "new_gate_repo dir"
  mkdir -p "$dir/docs/issues" "$dir/docs/specs" "$dir/docs/ai"
  : > "$dir/docs/ai/EVENTS.jsonl"
  : > "$dir/docs/ai/decisions.jsonl"
  cat > "$dir/docs/ai/docs-audit.yaml" <<'YAML'
legacy_until_date: 2020-01-01
stale_after_days: 90
scan_exclude: []
backlog_globs: []
close_gate: report-only
doc_number_guard: report-only
protected_paths_l3: []
YAML
  write_gate_change_doc "$dir/docs/issues/CHANGE-DRAFT-$slug.md" "$slug" "$intake_status"
  write_gate_spec_doc "$dir/docs/specs/SPEC-DRAFT-spec-$slug.md" "spec-$slug" "$spec_status" "docs/issues/CHANGE-DRAFT-$slug.md"
  git init -q "$dir"
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  git -C "$dir" config user.email gate@example.com
  git -C "$dir" config user.name gate
  git -C "$dir" add -A
  # A done doc needs delivery evidence docs-audit can see (a commit naming the
  # id + a terminal evidenced AC table, written by write_gate_spec_doc), else
  # the audit names it probable-false-done and the CLEAN arm is unreachable.
  git -C "$dir" commit -q -m "init fixture: deliver $slug (spec-$slug)"
  local remote="$TEST_DIR/$name-origin.git"
  git init -q --bare "$remote"
  git -C "$remote" symbolic-ref HEAD refs/heads/main
  git -C "$dir" remote add origin "$remote"
  git -C "$dir" push -q origin HEAD:refs/heads/main
  git -C "$dir" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  echo "$dir"
}

write_gate_change_doc() {
  local path="$1" id="$2" status="$3"
  cat > "$path" <<EOF
---
id: $id
type: change
status: $status
links:
  pr: []
  commits: []
---

# Change — Fixture $id

## Summary
- gate fixture doc.

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
- ephemeral fixture.
EOF
}

write_gate_spec_doc() {
  local path="$1" id="$2" status="$3" req="$4"
  local ac_status="planned" ac_evidence="—" test_status="pending"
  if [[ "$status" == "done" ]]; then ac_status="done"; ac_evidence="commit init fixture"; test_status="green"; fi
  cat > "$path" <<EOF
---
id: $id
type: spec
number: null
status: $status
ceremony_level: 1
links:
  requirement: $req
  rfc: null
  pr: []
  commits: []
---

# SPEC — Fixture $id

SPEC-FROZEN: true

## Implementation strategy
- Strategy: loop
- Rationale: fixture.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | fixture     | $ac_status | $ac_evidence | — | — |

## Test Plan

| Test ID  | Spec-AC    | Type | File path | Description | Status |
|----------|------------|------|-----------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit | n/a       | fixture     | $test_status |
EOF
}

# run_gate <repo> <slug> [extra flags...] — runs the gate with cwd=repo;
# captures stdout+stderr to $OUT and the exit code to $CODE.
run_gate() {
  local repo="$1" slug="$2"; shift 2
  abs_nonempty "$repo" "run_gate repo"
  CODE=0
  OUT="$(node "$GATE" --root "$repo" --ref "$slug" "$@" 2>&1)" || CODE=$?
}

# --- TEST-004 (Spec-AC-03): five arms, one class at a time ----------------

test_004_gate_five_arms() {
  log_info "TEST-004: CLEAN exits 0; each of the four classes alone exits 1 and is named under its class; --json counts match..."
  local repo slug="gate-ride"

  # Arm 1 — CLEAN: intake and spec terminal, tree clean, audit clean, no follow-ups.
  repo="$(new_gate_repo t004-clean "$slug" done done)"
  run_gate "$repo" "$slug"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-004 clean: expected exit 0, got $CODE: $OUT"
  case "$OUT" in *CLEAN*) ;; *) log_fail "TEST-004 clean: output must say CLEAN: $OUT" ;; esac
  run_gate "$repo" "$slug" --json
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-004 clean --json: expected exit 0, got $CODE: $OUT"
  printf '%s\n' "$OUT" > "$TEST_DIR/t004-clean.json"
  [[ "$(json_field "$TEST_DIR/t004-clean.json" 'r.files_left + r.docs_open + r.audit_findings + r.registry_self_items')" == "0" ]] \
    || log_fail "TEST-004 clean --json: all four counts must be 0: $OUT"

  # Arm 2 — one untracked file: files_left 1, everything else 0.
  repo="$(new_gate_repo t004-files "$slug" done done)"
  echo "left behind" > "$repo/stray.txt"
  run_gate "$repo" "$slug"
  [[ "$CODE" -eq 1 ]] || log_fail "TEST-004 files: expected exit 1, got $CODE: $OUT"
  case "$OUT" in *"files_left"*"stray.txt"*) ;; *) log_fail "TEST-004 files: stray.txt must be named under files_left: $OUT" ;; esac
  run_gate "$repo" "$slug" --json
  printf '%s\n' "$OUT" > "$TEST_DIR/t004-files.json"
  [[ "$(json_field "$TEST_DIR/t004-files.json" '[r.files_left, r.docs_open, r.audit_findings, r.registry_self_items].join(",")')" == "1,0,0,0" ]] \
    || log_fail "TEST-004 files: counts must be 1,0,0,0: $OUT"

  # Arm 3 — one false-open doc (another ride's draft doc with a work_item_closed
  # event, docs-audit's Arm C): audit_findings 1, everything else 0.
  repo="$(new_gate_repo t004-audit "$slug" done done)"
  write_gate_change_doc "$repo/docs/issues/CHANGE-DRAFT-other-ride.md" other-ride draft
  ( cd "$repo" && node "$APPEND_EVENT" --event work_item_closed --ref other-ride --validation pass --code-review none >/dev/null )
  git -C "$repo" add -A && git -C "$repo" commit -q -m "add other-ride (closed but still draft)"
  run_gate "$repo" "$slug"
  [[ "$CODE" -eq 1 ]] || log_fail "TEST-004 audit: expected exit 1, got $CODE: $OUT"
  case "$OUT" in *"audit_findings"*"other-ride"*) ;; *) log_fail "TEST-004 audit: other-ride must be named under audit_findings: $OUT" ;; esac
  run_gate "$repo" "$slug" --json
  printf '%s\n' "$OUT" > "$TEST_DIR/t004-audit.json"
  [[ "$(json_field "$TEST_DIR/t004-audit.json" '[r.files_left, r.docs_open, r.audit_findings, r.registry_self_items].join(",")')" == "0,0,1,0" ]] \
    || log_fail "TEST-004 audit: counts must be 0,0,1,0: $OUT"

  # Arm 4 — the ride's own intake still `status: draft` after its branch merged
  # (no delivery evidence docs-audit can see, so only the gate's own class
  # fires): docs_open 1, everything else 0.
  repo="$(new_gate_repo t004-docs "$slug" draft done)"
  git -C "$repo" checkout -q -b feat/ride
  echo "delivered" > "$repo/feature.txt"
  git -C "$repo" add -A && git -C "$repo" commit -q -m "deliver the feature file"
  git -C "$repo" checkout -q main
  git -C "$repo" merge -q --no-ff -m "merge feat/ride" feat/ride
  git -C "$repo" push -q origin main
  run_gate "$repo" "$slug"
  [[ "$CODE" -eq 1 ]] || log_fail "TEST-004 docs: expected exit 1, got $CODE: $OUT"
  case "$OUT" in *"docs_open"*"CHANGE-DRAFT-$slug.md"*"draft"*) ;; *) log_fail "TEST-004 docs: the draft intake must be named under docs_open with its status: $OUT" ;; esac
  run_gate "$repo" "$slug" --json
  printf '%s\n' "$OUT" > "$TEST_DIR/t004-docs.json"
  [[ "$(json_field "$TEST_DIR/t004-docs.json" '[r.files_left, r.docs_open, r.audit_findings, r.registry_self_items].join(",")')" == "0,1,0,0" ]] \
    || log_fail "TEST-004 docs: counts must be 0,1,0,0: $OUT"

  # Arm 5 — one open follow-up with ref_id == slug whose finding is about the
  # ride's own ceremony: registry_self_items 1, everything else 0. Built
  # through the CLI (seam S3), then committed so files_left stays 0.
  repo="$(new_gate_repo t004-registry "$slug" done done)"
  node "$FOLLOW_UPS" add --id fu-stamp-gate-ride-links-pr --ref "$slug" --severity P2 \
    --what "the close ceremony did not stamp links.pr" --why "fixture" --source "fixture" \
    --ledger "$repo/docs/ai/decisions.jsonl" >/dev/null
  git -C "$repo" add -A && git -C "$repo" commit -q -m "record follow-up"
  run_gate "$repo" "$slug"
  [[ "$CODE" -eq 1 ]] || log_fail "TEST-004 registry: expected exit 1, got $CODE: $OUT"
  case "$OUT" in *"registry_self_items"*"fu-stamp-gate-ride-links-pr"*) ;; *) log_fail "TEST-004 registry: fu-stamp-gate-ride-links-pr must be named under registry_self_items: $OUT" ;; esac
  run_gate "$repo" "$slug" --json
  printf '%s\n' "$OUT" > "$TEST_DIR/t004-registry.json"
  [[ "$(json_field "$TEST_DIR/t004-registry.json" '[r.files_left, r.docs_open, r.audit_findings, r.registry_self_items].join(",")')" == "0,0,0,1" ]] \
    || log_fail "TEST-004 registry: counts must be 0,0,0,1: $OUT"

  log_pass "TEST-004 gate: CLEAN exits 0; each class alone exits 1, named under its heading, --json counts match"
}

# --- TEST-005 (Spec-AC-03): the id-prefix rule is a closed list -------------

test_005_registry_id_prefix_closed_list() {
  log_info "TEST-005: class 4 is decided by the follow-up id prefix — a ceremony-subject id IS counted; fu-amend-* and fu-gate-* are NOT, whatever their prose says..."
  local repo slug="gate-ride" ledger
  repo="$(new_gate_repo t005 "$slug" done done)"
  ledger="$repo/docs/ai/decisions.jsonl"
  # Negative control 1: an amendment sign-off owed to the owner (SPEC-0165).
  # Excluded STRUCTURALLY by its `fu-amend-` subject, not by its wording.
  node "$FOLLOW_UPS" add --id fu-amend-gate-ride --ref "$slug" --severity P3 \
    --what "spec amendment awaits owner sign-off" --why "SPEC-0165 additive-with-disclosure" --source "fixture" --ledger "$ledger" >/dev/null
  # Negative control 2: a ceremony-subject item raised by ANOTHER ride — the id
  # WOULD count, so this control isolates the ref_id filter and nothing else.
  node "$FOLLOW_UPS" add --id fu-ceremony-other-ride-close --ref other-ride --severity P2 \
    --what "close-work-item ran after the push" --why "fixture" --source "fixture" --ledger "$ledger" >/dev/null
  git -C "$repo" add -A && git -C "$repo" commit -q -m "record two follow-ups that must not count"
  run_gate "$repo" "$slug" --json
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-005: with only fu-amend-<ref> and a foreign ref the gate must exit 0, got $CODE: $OUT"
  printf '%s\n' "$OUT" > "$TEST_DIR/t005-a.json"
  [[ "$(json_field "$TEST_DIR/t005-a.json" 'r.registry_self_items')" == "0" ]] \
    || log_fail "TEST-005: registry_self_items must be 0 for fu-amend + foreign ref: $OUT"
  # Positive: the same ride, an item whose SUBJECT is the close ceremony.
  node "$FOLLOW_UPS" add --id fu-close-gate-ride-work-item-late --ref "$slug" --severity P2 \
    --what "close-work-item must run before the push" --why "fixture" --source "fixture" --ledger "$ledger" >/dev/null
  git -C "$repo" add -A && git -C "$repo" commit -q -m "record a self-referential follow-up"
  run_gate "$repo" "$slug" --json
  [[ "$CODE" -eq 1 ]] || log_fail "TEST-005: a ceremony-subject item for the ride must exit 1, got $CODE: $OUT"
  printf '%s\n' "$OUT" > "$TEST_DIR/t005-b.json"
  [[ "$(json_field "$TEST_DIR/t005-b.json" 'r.registry_self_items')" == "1" ]] \
    || log_fail "TEST-005: registry_self_items must be exactly 1 (only fu-close-gate-ride-work-item-late): $OUT"
  run_gate "$repo" "$slug"
  case "$OUT" in *"fu-close-gate-ride-work-item-late"*) ;; *) log_fail "TEST-005: fu-close-gate-ride-work-item-late must be named: $OUT" ;; esac
  case "$OUT" in *"fu-amend-gate-ride"*) log_fail "TEST-005: fu-amend-gate-ride must NOT be named: $OUT" ;; esac
  case "$OUT" in *"fu-ceremony-other-ride-close"*) log_fail "TEST-005: a foreign ref's item must NOT be named: $OUT" ;; esac

  # The list is CLOSED: a seventh prefix must not arrive quietly. The literal
  # itself is pinned to exactly one file by TEST-008; here, the declaration is
  # unique and the rule is behaviourally closed — a plausible non-ceremony
  # subject is NOT counted.
  local decls
  decls="$(grep -c 'CEREMONY_FOLLOW_UP_ID_PREFIXES *=' "$GATE" || true)"
  [[ "$decls" == "1" ]] || log_fail "TEST-005: CEREMONY_FOLLOW_UP_ID_PREFIXES must be declared exactly once in $GATE (got $decls)"
  # `finding` must not be read at all any more: the prose word is gone from the rule.
  if grep -qF "REGISTRY_SELF_RE" "$GATE"; then
    log_fail "TEST-005: the amended Spec-AC-03 decides class 4 from the id prefix; the six-word finding-TEXT regex REGISTRY_SELF_RE must be gone from $GATE"
  fi
  node "$FOLLOW_UPS" add --id fu-orphan-gate-ride-doc --ref "$slug" --severity P3 \
    --what "orphan doc left behind by the ride" --why "fixture: a subject OUTSIDE the closed prefix list" --source "fixture" --ledger "$ledger" >/dev/null
  git -C "$repo" add -A && git -C "$repo" commit -q -m "record a follow-up whose subject is outside the list"
  run_gate "$repo" "$slug" --json
  printf '%s\n' "$OUT" > "$TEST_DIR/t005-c.json"
  [[ "$(json_field "$TEST_DIR/t005-c.json" 'r.registry_self_items')" == "1" ]] \
    || log_fail "TEST-005: a subject outside the closed prefix list must not be counted (still 1): $OUT"

  # THE SCAR the owner-signed amendment bought (fu-gate-ref-id-shape-mismatch):
  # a follow-up whose SUBJECT is the gate this ride DELIVERS, worded — as any
  # honest description of that defect must be — with the word "ceremony". The
  # old finding-TEXT rule counted it and stopped the push; the id-prefix rule
  # does not. Rewording the finding was never the fix; the rule was.
  node "$FOLLOW_UPS" add --id fu-gate-ride-ref-id-shape --ref "$slug" --severity P2 \
    --what "the gate's class 4 matches ref_id === slug, so a ceremony follow-up filed under a doc id is invisible to it" \
    --why "fixture: a defect IN the delivered gate, described in the only words that describe it" --source "fixture" --ledger "$ledger" >/dev/null
  # ...and the fu-amend exclusion is now STRUCTURAL, not a wording accident
  # (fu-amend-exclusion-rests-on-wording): the same amend item worded with a
  # ceremony word is still excluded, by its subject.
  node "$FOLLOW_UPS" add --id fu-amend-gate-ride-worded --ref "$slug" --severity P3 \
    --what "amendment sign-off owed before the close ceremony" --why "fixture: SPEC-0165 wording that DOES carry a ceremony word" --source "fixture" --ledger "$ledger" >/dev/null
  git -C "$repo" add -A && git -C "$repo" commit -q -m "record a gate-subject and an amend follow-up, both worded with a ceremony word"
  run_gate "$repo" "$slug" --json
  printf '%s\n' "$OUT" > "$TEST_DIR/t005-d.json"
  [[ "$(json_field "$TEST_DIR/t005-d.json" 'r.registry_self_items')" == "1" ]] \
    || log_fail "TEST-005: neither a fu-gate-* nor a fu-amend-* item counts, however it is worded (expected still 1): $OUT"
  run_gate "$repo" "$slug"
  case "$OUT" in *"fu-gate-ride-ref-id-shape"*) log_fail "TEST-005: a follow-up ABOUT the delivered gate must NOT be named: $OUT" ;; esac
  case "$OUT" in *"fu-amend-gate-ride-worded"*) log_fail "TEST-005: the worded amend item must NOT be named — the exclusion is structural: $OUT" ;; esac
  case "$OUT" in *"fu-orphan-gate-ride-doc"*) log_fail "TEST-005: the outside-the-list item must NOT be named: $OUT" ;; esac

  log_pass "TEST-005 id-prefix rule is a closed list: declaration unique, prose regex gone, ceremony subject counted, gate/amend subjects excluded structurally, foreign ref ignored"
}

# --- TEST-008 (review round 2): the gate borrows the layer's canon ---------
# An un-pinned de-duplication drifts back, so both halves are pinned the way
# test-aai-metrics.sh pins the usage-note literal (the literal lives in exactly
# ONE file) AND behaviourally (the imported vocabulary is actually in force).

test_008_no_forked_canon() {
  log_info "TEST-008: terminal doc-status set and the docs EXCLUDE_DIRS list each live in exactly one file, and the gate obeys both..."
  local hits n slug="gate-ride" repo

  # Pin 1 — the terminal doc-status literal: lib/docs-model.mjs only.
  hits="$(grep -rlF "'done', 'deferred', 'rejected', 'superseded'" "$PROJECT_ROOT/.aai/scripts" 2>/dev/null || true)"
  n="$(printf '%s\n' "$hits" | grep -c . || true)"
  [[ "$n" == "1" ]] || log_fail "TEST-008: the terminal doc-status literal must exist in exactly one file (got $n): $hits"
  case "$hits" in */.aai/scripts/lib/docs-model.mjs) ;; *) log_fail "TEST-008: the terminal doc-status literal must live in lib/docs-model.mjs, found: $hits" ;; esac

  # Pin 2 — the docs-corpus exclude list: lib/docs-audit-core.mjs only.
  hits="$(grep -rlF "'ai', 'knowledge', 'archive', '_archive', 'project-sessions', 'templates'" "$PROJECT_ROOT/.aai/scripts" 2>/dev/null || true)"
  n="$(printf '%s\n' "$hits" | grep -c . || true)"
  [[ "$n" == "1" ]] || log_fail "TEST-008: the docs EXCLUDE_DIRS literal must exist in exactly one file (got $n): $hits"
  case "$hits" in */.aai/scripts/lib/docs-audit-core.mjs) ;; *) log_fail "TEST-008: the docs EXCLUDE_DIRS literal must live in lib/docs-audit-core.mjs, found: $hits" ;; esac

  # Pin 3 — the gate imports them rather than declaring its own.
  grep -qF "TERMINAL_DOC_STATUS" "$GATE" || log_fail "TEST-008: the gate must use the imported TERMINAL_DOC_STATUS"
  grep -qF "scanAuditDocs" "$GATE" || log_fail "TEST-008: the gate must walk the corpus with the imported scanAuditDocs"
  # `cmd && log_fail` would make the whole statement exit 1 under this suite's
  # own `set -euo pipefail` when the grep finds nothing — the pass path. `if`.
  if grep -qF "TERMINAL_DOC_STATUSES" "$GATE"; then
    log_fail "TEST-008: the gate must not re-declare a private TERMINAL_DOC_STATUSES set"
  fi

  # Pin 4 (behaviour) — `current`, the steady state of a capability-keyed
  # product doc, is terminal: the gate must not report it open forever.
  repo="$(new_gate_repo t008-current "$slug" current done)"
  run_gate "$repo" "$slug" --json
  printf '%s\n' "$OUT" > "$TEST_DIR/t008-current.json"
  [[ "$(json_field "$TEST_DIR/t008-current.json" 'r.docs_open')" == "0" ]] \
    || log_fail "TEST-008: an intake doc at status: current must NOT be counted open: $OUT"

  # Pin 5 (behaviour) — a doc under an EXCLUDE_DIRS directory is invisible to
  # the gate exactly as it is to docs-audit; the old private walk counted it.
  repo="$(new_gate_repo t008-excluded "$slug" done done)"
  mkdir -p "$repo/docs/templates"
  write_gate_spec_doc "$repo/docs/templates/SPEC-DRAFT-spec-template-ride.md" \
    spec-template-ride draft "docs/issues/CHANGE-DRAFT-$slug.md"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "add a template spec linked to the ride"
  run_gate "$repo" "$slug"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-008: a draft spec under docs/templates/ must be excluded like docs-audit excludes it, got exit $CODE: $OUT"
  case "$OUT" in *"template-ride"*) log_fail "TEST-008: an excluded-dir doc must never be named by the gate: $OUT" ;; esac

  # Pin 6 — the amended Spec-AC-03's ceremony-subject prefix list. It decides
  # whether a push is stopped, so it gets the same treatment as the other two
  # canon literals: the closed list exists in EXACTLY ONE file, and that file
  # is the gate. A second copy (a helper, a test fixture generator, a doc
  # generator) is how a closed list quietly acquires a tenth prefix.
  hits="$(grep -rlF "'fu-ac-flip-', 'fu-acflip-', 'fu-allocator-', 'fu-ceremony-', 'fu-close-', 'fu-closeworkitem-', 'fu-false-open-', 'fu-index-', 'fu-stamp-'" "$PROJECT_ROOT/.aai/scripts" 2>/dev/null || true)"
  n="$(printf '%s\n' "$hits" | grep -c . || true)"
  [[ "$n" == "1" ]] || log_fail "TEST-008: the ceremony-subject prefix literal must exist in exactly one file (got $n): $hits"
  case "$hits" in */.aai/scripts/nothing-left-behind.mjs) ;; *) log_fail "TEST-008: the ceremony-subject prefix literal must live in nothing-left-behind.mjs, found: $hits" ;; esac

  log_pass "TEST-008 no forked canon: terminal-status, EXCLUDE_DIRS and ceremony-prefix literals each in one file; the gate imports/obeys them"
}

# --- flow helpers -------------------------------------------------------------

# flow_env_run <out-dir> <record> [flow args...] — runs the flow under a
# minimal environment (no harness variable, no global git config, stdin closed),
# capturing stdout+stderr to $OUT and the exit code to $CODE.
flow_env_run() {
  local out="$1" record="$2"; shift 2
  abs_nonempty "$out" "flow out"
  abs_nonempty "$record" "flow record"
  mkdir -p "$TEST_DIR/home"
  CODE=0
  OUT="$(env -i PATH="$PATH" HOME="$TEST_DIR/home" TMPDIR="$TEST_DIR" \
    node "$FLOW" --out "$out" --record "$record" "$@" </dev/null 2>&1)" || CODE=$?
}

# --- TEST-001 (Spec-AC-01): the whole ride, no question, nothing left ------

test_001_full_run_clean() {
  log_info "TEST-001: full run under env -i with stdin closed: exit 0, record clean, fixture docs done, main carries merge + close commits..."
  local out="$TEST_DIR/t001-out" record="$TEST_DIR/t001-record.jsonl"
  flow_env_run "$out" "$record"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-001: expected exit 0, got $CODE: $OUT"
  [[ -f "$record" ]] || log_fail "TEST-001: record file not written: $record"
  [[ "$(json_field "$record" '[r.steps_failed, r.questions_asked, r.files_left, r.docs_open].join(",")')" == "0,0,0,0" ]] \
    || log_fail "TEST-001: steps_failed/questions_asked/files_left/docs_open must all be 0: $(cat "$record")"
  local fixture="$out/target"
  abs_nonempty "$fixture" "fixture"
  local d
  for d in "$fixture"/docs/issues/*.md; do
    grep -q '^status: done$' "$d" || log_fail "TEST-001: intake doc must read status: done: $d"
  done
  local subjects; subjects="$(git -C "$fixture" log --format=%s main)"
  case "$subjects" in *"merge"*) ;; *) log_fail "TEST-001: main must carry the merge commit: $subjects" ;; esac
  case "$subjects" in *"close"*) ;; *) log_fail "TEST-001: main must carry the close commit: $subjects" ;; esac
  [[ -z "$(git -C "$fixture" status --porcelain)" ]] || log_fail "TEST-001: fixture tree must be clean after the run: $(git -C "$fixture" status --porcelain)"
  log_pass "TEST-001 full run: exit 0, clean record, docs done, merge + close on main"
}

# --- TEST-002 (Spec-AC-01, seam S1): the fixture's own layer, not ours -----

test_002_seam_fixture_layer() {
  log_info "TEST-002: origin is bare with HEAD on refs/heads/main; every step command path starts with the fixture root..."
  local out="$TEST_DIR/t001-out" fixture="$TEST_DIR/t001-out/target" origin="$TEST_DIR/t001-out/origin.git"
  # Order-independent (the file header advertises the single-test form for this
  # arm): reuse TEST-001's fixture when the suite ran in order, and build it
  # here when this arm runs alone. The flow is idempotent on its own --out.
  if [[ ! -d "$fixture" ]]; then
    log_info "TEST-002: TEST-001's fixture is absent (single-test invocation) — building it here..."
    flow_env_run "$out" "$TEST_DIR/t002-record.jsonl"
    [[ "$CODE" -eq 0 ]] || log_fail "TEST-002: the fixture-building run must exit 0, got $CODE: $OUT"
  fi
  [[ -d "$fixture" ]] || log_fail "TEST-002: fixture still missing after the build: $fixture"
  [[ "$(git -C "$origin" rev-parse --is-bare-repository)" == "true" ]] || log_fail "TEST-002: origin must be bare"
  [[ "$(git -C "$origin" symbolic-ref HEAD)" == "refs/heads/main" ]] || log_fail "TEST-002: origin HEAD must be refs/heads/main"
  [[ "$(git -C "$fixture" remote get-url origin)" == "$origin" ]] || log_fail "TEST-002: fixture origin must be the bare repo"
  local steps="$out/steps.log"
  [[ -s "$steps" ]] || log_fail "TEST-002: steps.log missing or empty: $steps"
  local n=0 line
  while IFS= read -r line; do
    case "$line" in
      *"$PROJECT_ROOT/.aai/"*) log_fail "TEST-002: a step resolves a CLI under this checkout, not the fixture: $line" ;;
    esac
    case "$line" in
      *".aai/scripts/"*)
        n=$((n + 1))
        case "$line" in *"$fixture/.aai/scripts/"*) ;; *) log_fail "TEST-002: a CLI step must resolve under the fixture root: $line" ;; esac ;;
    esac
  done < "$steps"
  [[ "$n" -ge 4 ]] || log_fail "TEST-002: expected at least four CLI steps under the fixture layer, saw $n"
  log_pass "TEST-002 seam S1: bare origin on main; $n CLI steps resolve under the fixture layer"
}

# --- TEST-003 (Spec-AC-02): a question is observed, not hung ---------------

test_003_steps_from_questions() {
  log_info "TEST-003: --steps-from with a stdin-reading step, an exit-3 step and a timeout step: exit 1, all three under questions with command, exit code and output..."
  local out="$TEST_DIR/t003-out" record="$TEST_DIR/t003-record.jsonl" steps="$TEST_DIR/t003-steps.jsonl"
  {
    # -e: a prompt whose read hits EOF aborts the step, the shape a real CLI
    # takes when it needs an answer and stdin is closed — observed, not hung.
    printf '%s\n' '{"name":"ask-operator","run":["bash","-ec","printf \"which option? \"; read -r answer; echo \"got $answer\""]}'
    printf '%s\n' '{"name":"exit-three","run":["bash","-c","echo \"refused: fixture step\"; exit 3"]}'
    printf '%s\n' '{"name":"sleeps-past-timeout","run":["bash","-c","sleep 20"],"timeout_ms":1500}'
    printf '%s\n' '{"name":"still-runs","run":["bash","-c","echo after"]}'
  } > "$steps"
  flow_env_run "$out" "$record" --steps-from "$steps"
  [[ "$CODE" -eq 1 ]] || log_fail "TEST-003: expected exit 1, got $CODE: $OUT"
  [[ -f "$record" ]] || log_fail "TEST-003: record not written"
  [[ "$(json_field "$record" 'r.steps_total')" == "4" ]] || log_fail "TEST-003: steps_total must be 4: $(cat "$record")"
  [[ "$(json_field "$record" 'r.steps_failed')" == "3" ]] || log_fail "TEST-003: steps_failed must be 3: $(cat "$record")"
  [[ "$(json_field "$record" 'r.questions_asked')" == "3" ]] || log_fail "TEST-003: questions_asked must be 3: $(cat "$record")"
  [[ "$(json_field "$record" 'r.questions.length')" == "3" ]] || log_fail "TEST-003: questions must list 3 entries"
  [[ "$(json_field "$record" 'r.questions[0].step')" == "ask-operator" ]] || log_fail "TEST-003: first question must be the stdin step"
  [[ "$(json_field "$record" 'r.questions[0].exit_code')" != "0" ]] || log_fail "TEST-003: the stdin-reading step must not exit 0 with stdin closed"
  case "$(json_field "$record" 'r.questions[0].command')" in *"read -r answer"*) ;; *) log_fail "TEST-003: question must carry its command" ;; esac
  case "$(json_field "$record" 'r.questions[0].output')" in *"which option?"*) ;; *) log_fail "TEST-003: question must carry the step's output text" ;; esac
  [[ "$(json_field "$record" 'r.questions[1].exit_code')" == "3" ]] || log_fail "TEST-003: exit-three step must record exit code 3"
  case "$(json_field "$record" 'r.questions[1].output')" in *"refused: fixture step"*) ;; *) log_fail "TEST-003: exit-three output missing" ;; esac
  [[ "$(json_field "$record" 'r.questions[2].timed_out')" == "true" ]] || log_fail "TEST-003: the sleeping step must be recorded as timed out: $(cat "$record")"
  log_pass "TEST-003 questions recorded with command, exit code, output; timeout observed, not hung"
}

# --- TEST-006 (Spec-AC-04): the record reads the gate, never recomputes ----

test_006_record_reads_gate_and_skill_pr_wiring() {
  log_info "TEST-006: record gate fields equal the gate's --json on the same fixture (planted untracked file moves both to 1); SKILL_PR wires the gate between close and push with STOP..."
  local out="$TEST_DIR/t006-out" record="$TEST_DIR/t006-record.jsonl" steps="$TEST_DIR/t006-steps.jsonl"
  # Default steps plus one planted step that leaves an untracked file behind
  # right before the gate reads the fixture.
  node "$FLOW" --print-steps > "$steps"
  [[ -s "$steps" ]] || log_fail "TEST-006: --print-steps produced nothing"
  printf '%s\n' '{"name":"plant-leftover","run":["bash","-c","echo leftover > {fixture}/leftover.txt"]}' >> "$steps"
  flow_env_run "$out" "$record" --steps-from "$steps"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-006: a leftover file is a finding, not a failed step; expected exit 0, got $CODE: $OUT"
  local fixture="$out/target" gate_json="$TEST_DIR/t006-gate.json" ref
  ref="$(json_field "$record" 'r.gate_ref')"
  [[ -n "$ref" && "$ref" != "null" ]] || log_fail "TEST-006: record must name the gate_ref it was read for"
  CODE=0
  node "$fixture/.aai/scripts/nothing-left-behind.mjs" --root "$fixture" --ref "$ref" --json > "$gate_json" 2>/dev/null || CODE=$?
  [[ "$CODE" -eq 1 ]] || log_fail "TEST-006: the gate on the mutated fixture must exit 1, got $CODE: $(cat "$gate_json")"
  local rec_triple gate_triple
  rec_triple="$(json_field "$record" '[r.files_left, r.docs_open, r.registry_self_items].join(",")')"
  gate_triple="$(json_field "$gate_json" '[r.files_left, r.docs_open, r.registry_self_items].join(",")')"
  [[ "$rec_triple" == "$gate_triple" ]] || log_fail "TEST-006: record triple $rec_triple != gate triple $gate_triple"
  [[ "$rec_triple" == "1,0,0" ]] || log_fail "TEST-006: the planted file must move files_left to 1 in both: $rec_triple"
  # Grep contract on SKILL_PR: the gate line sits after the close ceremony and
  # before the push line, and the surrounding text says STOP.
  # Pipe-free line lookups: `grep | head | cut` dies silently under pipefail
  # when a needle is absent (the RED shape of this very arm).
  first_line_of() {  # <fixed needle> <file> -> line number or empty
    local hit; hit="$(grep -n -m1 -F -- "$1" "$2" || true)"
    printf '%s' "${hit%%:*}"
  }
  local close_ln gate_ln push_ln
  close_ln="$(first_line_of 'close-work-item.mjs --ref <slug> --pr <TBD|NONE>' "$SKILL_PR")"
  gate_ln="$(first_line_of 'nothing-left-behind.mjs --ref <slug>' "$SKILL_PR")"
  push_ln="$(first_line_of 'git push -u origin <branch>' "$SKILL_PR")"
  [[ -n "$close_ln" && -n "$gate_ln" && -n "$push_ln" ]] || log_fail "TEST-006: SKILL_PR must name close-work-item (line '$close_ln'), nothing-left-behind (line '$gate_ln') and the push (line '$push_ln')"
  [[ "$close_ln" -lt "$gate_ln" && "$gate_ln" -lt "$push_ln" ]] || log_fail "TEST-006: SKILL_PR order must be close ($close_ln) < gate ($gate_ln) < push ($push_ln)"
  local window; window="$(sed -n "$((gate_ln - 2)),$((gate_ln + 6))p" "$SKILL_PR")"
  case "$window" in *STOP*) ;; *) log_fail "TEST-006: the gate bullet must say STOP on non-zero: $window" ;; esac
  log_pass "TEST-006 record reads the gate (1,0,0 in both); SKILL_PR wires the gate between close and push with STOP"
}

# --- TEST-007 (Spec-AC-05): append-only record, --diff is the verdict ------

test_007_record_append_only_and_diff() {
  log_info "TEST-007: two runs append two lines, first byte-identical; every field present; --diff 0 on equal, 1 when files_left rose; tokens median null / 1640003..."
  local record="$TEST_DIR/t007-record.jsonl" out1="$TEST_DIR/t007-out1" out2="$TEST_DIR/t007-out2" steps="$TEST_DIR/t007-steps.jsonl"
  # Run 1 — clean, no --metrics.
  flow_env_run "$out1" "$record"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-007 run1: expected exit 0, got $CODE: $OUT"
  [[ "$(wc -l < "$record" | tr -d ' ')" == "1" ]] || log_fail "TEST-007 run1: record must have exactly one line"
  local first; first="$(head -1 "$record")"
  local f
  for f in v run_utc aai_version node_major os_family steps_total steps_failed questions_asked questions \
           files_left docs_open audit_findings registry_self_items tokens_median_last10 tokens_ceiling ci_docs_only_full_run; do
    [[ "$(json_field "$record" "Object.prototype.hasOwnProperty.call(r, \"$f\")")" == "true" ]] || log_fail "TEST-007: record lacks field $f: $first"
  done
  [[ "$(json_field "$record" 'r.v')" == "1" ]] || log_fail "TEST-007: v must be 1"
  [[ "$(json_field "$record" 'r.tokens_ceiling')" == "1640003" ]] || log_fail "TEST-007: tokens_ceiling must be 1640003"
  [[ "$(json_field "$record" 'r.tokens_median_last10')" == "null" ]] || log_fail "TEST-007: tokens_median_last10 must be null without --metrics"
  [[ "$(json_field "$record" 'r.aai_version')" == "$(sed -n 's/^- Version: //p' "$PROJECT_ROOT/docs/ai/AAI_VERSION.md" | head -1)" ]] \
    || log_fail "TEST-007: aai_version must be read from docs/ai/AAI_VERSION.md"
  [[ "$(json_field "$record" 'typeof r.ci_docs_only_full_run')" == "boolean" ]] || log_fail "TEST-007: ci_docs_only_full_run must be a boolean"
  # --diff with one line: nothing to compare, exit 0 and say so.
  CODE=0; OUT="$(node "$FLOW" --diff --record "$record" 2>&1)" || CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-007: --diff on a single line must exit 0: $OUT"
  # Run 2 — the SAME clean flow with a fixture metrics ledger of ten known rides.
  local ledger="$TEST_DIR/t007-metrics.jsonl" i
  : > "$ledger"
  for i in 735322 855025 1045424 1276927 1348307 1931699 2223982 2287044 3269106 4316563; do
    printf '{"date_utc":"2026-08-31","ref_id":"ride-%s","agent_runs":[{"role":"Implementation","note":"usage_total_tokens=%s (harness total)"}],"verdict":"PASS"}\n' "$i" "$i" >> "$ledger"
  done
  # An eleventh ride WITHOUT a usage marker must not enter the median.
  printf '{"date_utc":"2026-09-01","ref_id":"ride-unmarked","agent_runs":[{"role":"Implementation","note":"no capture"}],"verdict":"PASS"}\n' >> "$ledger"
  flow_env_run "$out2" "$record" --metrics "$ledger"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-007 run2: expected exit 0, got $CODE: $OUT"
  [[ "$(wc -l < "$record" | tr -d ' ')" == "2" ]] || log_fail "TEST-007 run2: record must have exactly two lines"
  [[ "$(head -1 "$record")" == "$first" ]] || log_fail "TEST-007: the first line must stay byte-identical"
  [[ "$(json_field "$record" 'r.tokens_median_last10')" == "1640003" ]] || log_fail "TEST-007: tokens_median_last10 must be 1640003 on the fixture ledger: $(tail -1 "$record")"
  CODE=0; OUT="$(node "$FLOW" --diff --record "$record" 2>&1)" || CODE=$?
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-007: --diff on equal counts must exit 0: $OUT"
  # Run 3 — planted leftover raises files_left: --diff exits 1 and names the field.
  node "$FLOW" --print-steps > "$steps"
  printf '%s\n' '{"name":"plant-leftover","run":["bash","-c","echo leftover > {fixture}/leftover.txt"]}' >> "$steps"
  flow_env_run "$TEST_DIR/t007-out3" "$record" --steps-from "$steps"
  [[ "$CODE" -eq 0 ]] || log_fail "TEST-007 run3: expected exit 0, got $CODE: $OUT"
  [[ "$(wc -l < "$record" | tr -d ' ')" == "3" ]] || log_fail "TEST-007 run3: record must have three lines"
  [[ "$(head -1 "$record")" == "$first" ]] || log_fail "TEST-007: the first line must still be byte-identical after run 3"
  CODE=0; OUT="$(node "$FLOW" --diff --record "$record" 2>&1)" || CODE=$?
  [[ "$CODE" -eq 1 ]] || log_fail "TEST-007: --diff must exit 1 when files_left rose, got $CODE: $OUT"
  case "$OUT" in *"files_left"*"0"*"1"*) ;; *) log_fail "TEST-007: --diff must name files_left with both values: $OUT" ;; esac
  log_pass "TEST-007 record append-only; fields present; --diff 0 on equal, 1 on a raised files_left; median null / 1640003"
}

main() {
  echo "Testing $TEST_NAME (simple-and-friendly-to-use / SPEC-0172-spec-simple-and-friendly-to-use)"
  check_deps
  if [[ $# -gt 0 ]]; then
    "$1"
    echo "PASS: $TEST_NAME selected test passed ($1)"
    return
  fi
  test_004_gate_five_arms
  test_005_registry_id_prefix_closed_list
  test_008_no_forked_canon
  test_001_full_run_clean
  test_002_seam_fixture_layer
  test_003_steps_from_questions
  test_006_record_reads_gate_and_skill_pr_wiring
  test_007_record_append_only_and_diff
  echo ""
  log_pass "All $TEST_NAME tests passed"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
