#!/usr/bin/env bash
#
# Test: deterministic close-ceremony mechanism (CHANGE-0037 /
# docs/specs/SPEC-0053-spec-deterministic-close-ceremony.md, TEST-001..009).
#
# Covers .aai/scripts/close-work-item.mjs — the script that mechanizes the
# work-item close ceremony (frontmatter status transition, links.pr/
# links.commits stamping, the slug-reffed close event set, and a self-verify
# against the REAL docs-audit engine with total rollback on drift) — plus its
# canon wiring into .aai/SKILL_PR.prompt.md / .aai/VALIDATION.prompt.md.
#
#   - TEST-001 (Spec-AC-01): draft-close — a `draft` change-doc fixture closes
#     to `status: done`, doc_lifecycle from=draft to=done (bare slug ref), exit 0.
#   - TEST-002 (Spec-AC-01, SPEC-0046 regression): implementing-close — an
#     `implementing` fixture closes to done, doc_lifecycle from=implementing
#     to=done; a REAL audit afterward shows tracked-done, never
#     probable-false-open.
#   - TEST-003 (Spec-AC-01): non-done-terminal guard — `deferred` and
#     `superseded` fixtures both refuse with exit 2 and a named reason; the
#     doc file and EVENTS.jsonl are byte/length-unchanged.
#   - TEST-004 (Spec-AC-02, SEAM 1/2): ref-form + real-audit CLEAN — every
#     emitted event carries the bare slug ref (never the numbered fileId);
#     the REAL docs-audit.mjs classifies the ref tracked-done/aligned with no
#     false-done/false-open/missing-close-telemetry.
#   - TEST-005 (Spec-AC-03): pair close — --ref <change> --spec <spec> flips
#     BOTH docs to done with the complete slug-reffed event set each; real
#     audit CLEAN for both refs.
#   - TEST-006 (Spec-AC-03): pair pre-write abort — an unresolvable --spec
#     aborts with exit 2 BEFORE any write; the primary doc and EVENTS.jsonl
#     are untouched.
#   - TEST-007 (Spec-AC-04): idempotent re-run — running close twice appends
#     zero new EVENTS lines and no duplicate links on the second run; exit 0.
#   - TEST-008 (Spec-AC-04, fail-closed): a spec fixture rigged with a
#     non-terminal AC row makes the post-close self-verify audit NOT CLEAN —
#     exit 1, a named finding, and total rollback (doc content + EVENTS.jsonl
#     byte-identical to their pre-run snapshots).
#   - TEST-009 (Spec-AC-05): canon grep contract — SKILL_PR.prompt.md names
#     close-work-item.mjs; VALIDATION.prompt.md no longer hand-emits
#     work_item_closed nor hand-instructs a status:done flip; repo-wide
#     strict docs-audit stays exit 0.
#   - TEST-010 (Spec-AC-04, code-review B1 regression): post-apply INDEX
#     regen failure (rigged docs/INDEX.md marker guard) must NOT bypass
#     rollback via an uncatchable process.exit — the doc frontmatter and
#     EVENTS.jsonl must be restored to their pre-run snapshot and the process
#     must still exit non-zero.
#   - TEST-011 (code-review B2 regression): appending a NEW links.pr value to
#     a doc whose frontmatter already carries an INLINE non-empty list
#     (`pr: [42]`) must normalize to block form, not splice a bare block item
#     after the inline line (malformed mixed YAML).
#   - TEST-012 (code-review B3 regression): a doc resolved via the
#     display-id fallback whose frontmatter carries no `id:` key (fmId null)
#     must be rejected with a clean, named, PRE-WRITE exit 2 — never an
#     internal-error apply/rollback cycle.
#
# Fixture diversity checklist (SPEC-0013 H7), mapped:
#   - degenerate/empty            -> TEST-007 second run: zero new events/links
#   - zero-remainder               -> TEST-001: single-doc close, exact event set
#   - multi-source/multi-writer    -> TEST-005: pair close, two docs same transaction
#   - mid-operation failure        -> TEST-008: rigged spec AC row aborts post-write,
#                                      full rollback of a partially-applied close
#   - negative control              -> TEST-003: deferred/superseded MUST NOT close
#
# ALL fixtures are throwaway git repos under a mktemp dir (docs/ + docs/ai/
# EVENTS.jsonl + docs/ai/docs-audit.yaml + `git init`), cleaned on EXIT. The
# real repo's docs/ and docs/ai/EVENTS.jsonl are NEVER touched by TEST-001..008
# (the script under test always runs with cwd = the fixture dir).
#
# bash 3.2 compatible (no ${var^^}, no declare -A). Run via
# .aai/scripts/aai-run-tests.sh per the LEARNED wrapper rule.
#
# Usage:
#   bash tests/skills/test-aai-close-work-item.sh            # run all tests
#   bash tests/skills/test-aai-close-work-item.sh test_002_implementing_close
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-close-work-item"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

CLOSE_SCRIPT="$PROJECT_ROOT/.aai/scripts/close-work-item.mjs"
DOCS_AUDIT="$PROJECT_ROOT/.aai/scripts/docs-audit.mjs"
SKILL_PR="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
VALIDATION_PROMPT="$PROJECT_ROOT/.aai/VALIDATION.prompt.md"
TEST_SELF="$PROJECT_ROOT/tests/skills/test-aai-close-work-item.sh"
GUARD_CONFIG_LIB="$PROJECT_ROOT/.aai/scripts/lib/guard-config.mjs"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixture at $TEST_DIR"
  elif [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
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
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$DOCS_AUDIT" ]] || log_fail "docs-audit.mjs not found: $DOCS_AUDIT"
  [[ -f "$SKILL_PR" ]] || log_fail "SKILL_PR.prompt.md not found: $SKILL_PR"
  [[ -f "$VALIDATION_PROMPT" ]] || log_fail "VALIDATION.prompt.md not found: $VALIDATION_PROMPT"
  # NOTE: CLOSE_SCRIPT is intentionally NOT required here — TEST-001..008 RED
  # naturally (invocation fails / wrong exits) while the script does not yet
  # exist, per the spec's RED-proof note.
  log_pass "Dependencies checked"
}

setup_fixture() {
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-close-work-item-test.XXXXXX")"
}

# --- fixture repo builders ---------------------------------------------------

# new_fixture_repo <name> -> prints the fixture repo's absolute path. A
# throwaway git repo with docs/{issues,specs}, docs/ai/EVENTS.jsonl (empty),
# docs/ai/docs-audit.yaml (enforced mode), and an initial commit so the
# audit's git probes have something to read.
new_fixture_repo() {
  local name="$1"
  local dir="$TEST_DIR/$name"
  mkdir -p "$dir/docs/issues" "$dir/docs/specs" "$dir/docs/ai"
  : > "$dir/docs/ai/EVENTS.jsonl"
  cat > "$dir/docs/ai/docs-audit.yaml" <<'YAML'
legacy_until_date: 2020-01-01
stale_after_days: 90
scan_exclude: []
backlog_globs: []
close_gate: report-only
doc_number_guard: report-only
protected_paths_l3: []
YAML
  git init -q "$dir"
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  git -C "$dir" add -A
  git -C "$dir" commit -q -m init
  echo "$dir"
}

# new_fixture_repo_with_remote <name> -> prints the fixture repo's absolute
# path. Same as new_fixture_repo, PLUS a bare "origin" remote (SEAM-5,
# role-verification-guards G1): the init commit is pushed to origin main and
# refs/remotes/origin/HEAD is set, so `git merge-base --is-ancestor` has a
# real upstream default ref to resolve. The bare remote lives alongside the
# working copy under $TEST_DIR (never inside it), so `cp -r` on the working
# copy alone still leaves a valid `origin` (both copies share the same
# throwaway remote path).
new_fixture_repo_with_remote() {
  local name="$1"
  local dir; dir=$(new_fixture_repo "$name")
  local remote="$TEST_DIR/${name}-remote.git"
  git init -q --bare "$remote" >/dev/null
  git -C "$dir" remote add origin "$remote"
  git -C "$dir" push -q origin HEAD:refs/heads/main
  git -C "$dir" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  echo "$dir"
}

# push_head_to_origin_main <dir> — pushes the fixture's CURRENT HEAD to
# origin main (the "merged order" shape: the delivery commit already sits on
# the upstream default ref BEFORE close runs).
push_head_to_origin_main() {
  local dir="$1"
  git -C "$dir" push -q origin HEAD:refs/heads/main
}

# PRE_G1_CLOSE_WORK_ITEM_BLOB — the git blob sha of
# .aai/scripts/close-work-item.mjs exactly as it stood immediately before
# this scope's G1 edit landed (recorded once, by hand, from
# `git rev-parse HEAD:.aai/scripts/close-work-item.mjs` on the pre-change
# tree). validation-20260816T131500Z B2: deriving "pre-change" from
# `git archive HEAD` broke the moment this scope's own delivery commit became
# HEAD, because HEAD then IS the post-G1 tree and the "pre-change" run started
# emitting the very warning it was there to prove absent. A pinned blob sha is
# stable regardless of where HEAD points, now or after any future commit,
# because the object stays reachable as an ancestor of every commit that
# descends from the pre-change tree.
PRE_G1_CLOSE_WORK_ITEM_BLOB="4594d98cb2598d2380116c0f48f70c6481c55278"

# pre_change_close_script -> prints the path to a runnable copy of the
# PRE-G1 close-work-item.mjs. Siblings (append-event.mjs, the generate-*.mjs
# best-effort regenerators, lib/*.mjs — none of which G1 touches) come from
# the CURRENT tree so every relative import/execFileSync sibling call
# resolves on any commit; only close-work-item.mjs itself is swapped for the
# pinned pre-G1 blob. Memoized per suite run — the scratch tree is static
# content, built once.
_PRE_CHANGE_CLOSE_SCRIPT=""
pre_change_close_script() {
  if [[ -n "$_PRE_CHANGE_CLOSE_SCRIPT" && -f "$_PRE_CHANGE_CLOSE_SCRIPT" ]]; then
    echo "$_PRE_CHANGE_CLOSE_SCRIPT"
    return
  fi
  local root="$TEST_DIR/pre-change-tree"
  mkdir -p "$root/.aai"
  cp -r "$PROJECT_ROOT/.aai/scripts" "$root/.aai/scripts"
  local content
  content=$(cd "$PROJECT_ROOT" && git cat-file -p "$PRE_G1_CLOSE_WORK_ITEM_BLOB") \
    || log_fail "pre_change_close_script: git cat-file of the pinned pre-G1 blob failed"
  case "$content" in
    *post-merge-close*)
      log_fail "pre_change_close_script: the pinned pre-G1 blob unexpectedly already carries post-merge-close — PRE_G1_CLOSE_WORK_ITEM_BLOB points at the wrong object"
      ;;
  esac
  printf '%s\n' "$content" > "$root/.aai/scripts/close-work-item.mjs"
  _PRE_CHANGE_CLOSE_SCRIPT="$root/.aai/scripts/close-work-item.mjs"
  echo "$_PRE_CHANGE_CLOSE_SCRIPT"
}

commit_fixture_docs() {
  local dir="$1"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "add fixture doc(s)"
}

write_change_doc() {
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
- fixture doc for close-work-item tests.

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

# write_spec_doc <path> <id> <status> <ac_status> <evidence>
write_spec_doc() {
  local path="$1" id="$2" status="$3" ac_status="${4:-done}" evidence="${5:-commit-abc}"
  cat > "$path" <<EOF
---
id: $id
type: spec
number: null
status: $status
ceremony_level: 2
links:
  requirement: null
  rfc: null
  pr: []
  commits: []
---

# SPEC — Fixture $id

SPEC-FROZEN: true

## Acceptance Criteria Status

| Spec-AC    | Description | Status      | Evidence     | Review-By | Notes |
|------------|--------------|-------------|--------------|-----------|-------|
| Spec-AC-01 | fixture      | $ac_status  | $evidence    | —         | —     |

## Test Plan

| Test ID  | Spec-AC    | Type | File path | Description | Status |
|----------|------------|------|-----------|--------------|--------|
| TEST-001 | Spec-AC-01 | unit | n/a       | fixture      | green  |
EOF
}

# --- product-doc-gate fixture builders (product-docs-enforced) --------------

# write_user_visible_change_doc <path> <id> <status> — same shape as
# write_change_doc but with `user_visible: true` in frontmatter (D1 trigger key).
write_user_visible_change_doc() {
  local path="$1" id="$2" status="$3"
  cat > "$path" <<EOF
---
id: $id
type: change
status: $status
user_visible: true
links:
  pr: []
  commits: []
---

# Change — Fixture $id (user_visible)

## Summary
- fixture doc for close-work-item product-doc gate tests.

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

# set_product_doc_gate_dial <fixture_dir> <enforce|report-only|bogus> —
# appends the dial to the fixture's docs-audit.yaml (first occurrence wins in
# guard-config.mjs's column-0 scan, and the fixture's base file has no
# pre-existing product_doc_gate line).
set_product_doc_gate_dial() {
  local dir="$1" value="$2"
  printf 'product_doc_gate: %s\n' "$value" >> "$dir/docs/ai/docs-audit.yaml"
}

# --- usage-capture-gate fixture builders (spec-telemetry-completeness) -------

# set_usage_capture_gate_dial <fixture_dir> <enforce|report-only|bogus> —
# appends the dial to the fixture's docs-audit.yaml (first occurrence wins in
# guard-config.mjs's column-0 scan; the base fixture has no such line).
set_usage_capture_gate_dial() {
  local dir="$1" value="$2"
  printf 'usage_capture_gate: %s\n' "$value" >> "$dir/docs/ai/docs-audit.yaml"
}

# --- evidence-path-gate fixture builders (CHANGE-0131 / spec-evidence-path-gate)

# set_evidence_path_gate_dial <fixture_dir> <enforce|report-only|bogus> —
# appends the dial to the fixture's docs-audit.yaml (first occurrence wins in
# guard-config.mjs's column-0 scan; the base fixture has no such line).
set_evidence_path_gate_dial() {
  local dir="$1" value="$2"
  printf 'evidence_path_gate: %s\n' "$value" >> "$dir/docs/ai/docs-audit.yaml"
}

# state_begin <fixture_dir> <ref> — start a docs/ai/STATE.yaml carrying the
# metrics.work_items.<ref>.agent_runs block (append runs with state_add_run).
state_begin() {
  local dir="$1" ref="$2"
  mkdir -p "$dir/docs/ai"
  cat > "$dir/docs/ai/STATE.yaml" <<EOF
metrics:
  work_items:
    $ref:
      human_time_minutes:
        intake: null
        reviews: null
      agent_runs:
EOF
}

# state_add_run <fixture_dir> <role> <note> [tokens_in] [tokens_out] — append
# one agent_run (folded `note: >-` scalar, matching state.mjs append-run's
# on-disk shape) to the STATE.yaml opened by state_begin.
state_add_run() {
  local dir="$1" role="$2" note="$3" ti="${4:-null}" to="${5:-null}"
  cat >> "$dir/docs/ai/STATE.yaml" <<EOF
        - role: $role
          model_id: "test-model"
          note: >-
            $note
          started_utc: 2026-07-01T00:00:00Z
          ended_utc: 2026-07-01T00:01:00Z
          duration_seconds: 60
          tokens_in: $ti
          tokens_out: $to
          cost_usd: null
EOF
}

# write_real_product_doc <fixture_dir> <slug> — a REAL (non-placeholder)
# product doc at docs/product/<slug>.md: every required section filled
# ("None." for Data model/Interfaces, matching PRODUCT_TEMPLATE's explicit
# positive-empty marker).
write_real_product_doc() {
  local dir="$1" slug="$2"
  mkdir -p "$dir/docs/product"
  cat > "$dir/docs/product/$slug.md" <<EOF
---
id: $slug
type: product
status: current
spec: docs/specs/SPEC-9999-spec-$slug.md
updated: 2026-01-01
---

# Fixture Feature $slug

## What it does

Functional description for the $slug fixture product doc.

## How to use it

Usage instructions for $slug.

## Data model

None.

## Interfaces and contracts

None.

## Limits and non-goals

None.

## Links

- Request: docs/issues/CHANGE-DRAFT-$slug.md
- Spec: docs/specs/SPEC-9999-spec-$slug.md
EOF
}

# write_placeholder_data_model_product_doc <fixture_dir> <slug> — the Data
# model section still carries the unfilled template angle-bracket token;
# Interfaces and contracts is real (isolates the Data-model placeholder case).
write_placeholder_data_model_product_doc() {
  local dir="$1" slug="$2"
  mkdir -p "$dir/docs/product"
  cat > "$dir/docs/product/$slug.md" <<EOF
---
id: $slug
type: product
status: current
spec: docs/specs/SPEC-9999-spec-$slug.md
updated: 2026-01-01
---

# Fixture Feature $slug

## What it does

Functional description for the $slug fixture product doc.

## How to use it

Usage instructions for $slug.

## Data model

<Entities/records/files this feature introduces or changes: name, fields
worth knowing, where stored, retention. "None." if no data shape changed.>

## Interfaces and contracts

None.

## Limits and non-goals

None.

## Links

- Request: docs/issues/CHANGE-DRAFT-$slug.md
- Spec: docs/specs/SPEC-9999-spec-$slug.md
EOF
}

# write_placeholder_interfaces_product_doc <fixture_dir> <slug> — Interfaces
# and contracts still carries the unfilled template token; Data model is
# real (isolates the Interfaces placeholder case, TEST-006).
write_placeholder_interfaces_product_doc() {
  local dir="$1" slug="$2"
  mkdir -p "$dir/docs/product"
  cat > "$dir/docs/product/$slug.md" <<EOF
---
id: $slug
type: product
status: current
spec: docs/specs/SPEC-9999-spec-$slug.md
updated: 2026-01-01
---

# Fixture Feature $slug

## What it does

Functional description for the $slug fixture product doc.

## How to use it

Usage instructions for $slug.

## Data model

None.

## Interfaces and contracts

<Public surfaces this feature adds or changes: CLI commands and exit codes,
API endpoints, file formats, events, env vars. One line each: surface,
shape, stability promise. "None." if no public surface changed.>

## Limits and non-goals

None.

## Links

- Request: docs/issues/CHANGE-DRAFT-$slug.md
- Spec: docs/specs/SPEC-9999-spec-$slug.md
EOF
}

# write_none_dot_product_doc <fixture_dir> <slug> — Data model AND Interfaces
# both read the literal "None." (TEST-006: must count as REAL and PASS).
write_none_dot_product_doc() {
  write_real_product_doc "$1" "$2"
}

# --- capability-keyed product-doc-gate fixtures (spec-product-docs-capability-model) --
#
# SEAM-2: `capability` on the intake frontmatter is PRODUCED by intake and
# READ by close-work-item's gate AND its delivered_by upsert.

# write_user_visible_change_doc_with_capability <path> <id> <status> <capability>
# — same shape as write_user_visible_change_doc, plus a `capability:` field
# naming the user-facing capability this ref delivers/extends (independent
# of the ref's own id).
write_user_visible_change_doc_with_capability() {
  local path="$1" id="$2" status="$3" cap="$4"
  cat > "$path" <<EOF
---
id: $id
type: change
status: $status
user_visible: true
capability: $cap
links:
  pr: []
  commits: []
---

# Change — Fixture $id (user_visible, capability=$cap)

## Summary
- fixture doc for close-work-item capability-gate tests.

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

# write_capability_product_doc <fixture_dir> <capability> — a REAL product
# doc at docs/product/<capability>.md carrying `capability:` + an initially
# EMPTY-ish `delivered_by:` placeholder list (a single throwaway seed ref
# that no test ref will ever equal, so append-if-absent behavior is exercised
# honestly for every closing ref used against it).
write_capability_product_doc() {
  local dir="$1" cap="$2"
  mkdir -p "$dir/docs/product"
  cat > "$dir/docs/product/$cap.md" <<EOF
---
id: $cap
type: product
capability: $cap
status: current
delivered_by:
  - seed-ref-$cap
spec: docs/specs/SPEC-9999-spec-$cap.md
updated: 2026-01-01
---

# Fixture Feature $cap

## What it does

Functional description for the $cap fixture product doc.

## How to use it

Usage instructions for $cap.

## Data model

None.

## Interfaces and contracts

None.

## Limits and non-goals

None.

## Links

- Request: docs/issues/CHANGE-DRAFT-$cap.md
- Spec: docs/specs/SPEC-9999-spec-$cap.md
EOF
}

# delivered_by_contains <product_doc_path> <ref> -> "1" if present, else "0"
delivered_by_contains() {
  local path="$1" ref="$2"
  node -e '
    const fs = require("fs");
    const [file, ref] = process.argv.slice(1);
    const c = fs.readFileSync(file, "utf8");
    const m = c.match(/^delivered_by:\s*\n((?:  - .*\n?)*)/m);
    const items = m ? m[1].split("\n").map((l) => l.replace(/^\s*-\s*/, "").trim()).filter(Boolean) : [];
    process.stdout.write(items.includes(ref) ? "1" : "0");
  ' "$path" "$ref"
}

# --- invocation + assertion helpers ------------------------------------------

# run_close <fixture_dir> <outfile> <errfile> <args...> — echoes the exit code.
run_close() {
  local dir="$1" outfile="$2" errfile="$3"
  shift 3
  local code=0
  ( cd "$dir" && node "$CLOSE_SCRIPT" "$@" > "$outfile" 2> "$errfile" ) || code=$?
  echo "$code"
}

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  [[ "$actual" == "$expected" ]] \
    || log_fail "$desc: expected exit $expected, got $actual"
}

file_size() { wc -c < "$1" | tr -d ' '; }

# events_count <events_file> <event> <ref> [payload_key] [payload_val]
events_count() {
  node -e '
    const fs = require("fs");
    const [file, ev, ref, pk, pv] = process.argv.slice(1);
    const lines = fs.readFileSync(file, "utf8").split("\n").filter(Boolean);
    let n = 0;
    for (const l of lines) {
      let o; try { o = JSON.parse(l); } catch { continue; }
      if (o.event !== ev || o.ref !== ref) continue;
      if (pk && String(o.payload && o.payload[pk]) !== pv) continue;
      n += 1;
    }
    process.stdout.write(String(n));
  ' "$@"
}

# --- spec-close-leaves-state-stale fixture/assert helpers (TEST-051..054) ---

# write_reconcile_state <dir> <item_ref> <item_status> <item_phase> \
#   <item_primary_path> <item_spec_path|-> \
#   [<focus_ref|-> <focus_type> <focus_primary_path> <focus_spec_path|->]
#
# Writes a minimal docs/ai/STATE.yaml with ONE active_work_items entry and
# (when focus_ref != "-") a current_focus block. "-" for item_spec_path /
# focus_spec_path omits that field; a focus_ref of "-" (the default) omits
# current_focus entirely.
write_reconcile_state() {
  local dir="$1" ref="$2" status="$3" phase="$4" ppath="$5" spath="$6"
  local fref="${7:--}" ftype="${8:-intake_change}" fppath="${9:-}" fspath="${10:--}"
  mkdir -p "$dir/docs/ai"
  {
    echo "project_status: active"
    if [[ "$fref" != "-" ]]; then
      echo "current_focus:"
      echo "  type: $ftype"
      echo "  ref_id: $fref"
      echo "  primary_path: $fppath"
      if [[ "$fspath" != "-" ]]; then
        echo "  spec_path: $fspath"
      fi
    fi
    echo "active_work_items:"
    echo "  - ref_id: $ref"
    echo "    status: $status"
    echo "    phase: $phase"
    echo "    primary_path: $ppath"
    if [[ "$spath" != "-" ]]; then
      echo "    spec_path: $spath"
    fi
  } > "$dir/docs/ai/STATE.yaml"
}

# state_snapshot_json <state_file> <outfile> — dumps {items:[...], focus:{...}}
# via the SAME shared line-engine helpers (lib/state-engine.mjs,
# lib/state-core.mjs) production code uses, so the test never drifts from a
# hand-rolled YAML parser.
state_snapshot_json() {
  local f="$1" outfile="$2"
  cat > "$TEST_DIR/_dump_reconcile_state.mjs" <<'EOF'
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
const root = process.argv[2];
const statePath = process.argv[3];
const { findBlock, readScalar, unquoteScalar } =
  await import(pathToFileURL(path.join(root, '.aai/scripts/lib/state-engine.mjs')).href);
const { splitLines } = await import(pathToFileURL(path.join(root, '.aai/scripts/lib/state-core.mjs')).href);
const raw = fs.readFileSync(statePath, 'utf8');
const { lines } = splitLines(raw);
function parseItems() {
  const b = findBlock(lines, 'active_work_items');
  if (!b) return [];
  const items = [];
  let cur = null;
  for (let i = b.start + 1; i < b.end; i += 1) {
    const l = lines[i];
    if (l.trim() === '' || l.trim().startsWith('#')) continue;
    if (/^ {2}- /.test(l)) { cur = {}; items.push(cur); }
    if (!cur) continue;
    const indent = l.length - l.trimStart().length;
    const m = l.match(/^(?: {2}- | {4})([\w-]+):\s*(.*)$/);
    if (m && indent <= 4) {
      const v = m[2].trim();
      cur[m[1]] = v === '' || v === 'null' ? null : unquoteScalar(v);
    }
  }
  return items;
}
function focusField(name) {
  const v = readScalar(lines, 'current_focus', name);
  return v === null ? null : unquoteScalar(v);
}
console.log(JSON.stringify({
  items: parseItems(),
  focus: {
    type: focusField('type'), ref_id: focusField('ref_id'),
    primary_path: focusField('primary_path'), spec_path: focusField('spec_path'),
  },
}));
EOF
  node "$TEST_DIR/_dump_reconcile_state.mjs" "$PROJECT_ROOT" "$f" > "$outfile"
}

# jassert <json-file> <js-boolean-expr over `o`>
jassert() {
  node -e '
    const fs = require("fs");
    const o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const expr = process.argv[2];
    const fn = new Function("o", "return (" + expr + ");");
    if (!fn(o)) { console.error("assert failed: " + expr + "\n  got: " + JSON.stringify(o)); process.exit(1); }
  ' "$1" "$2" || log_fail "JSON assertion failed on $1: $2"
}

# --- TEST-001 (Spec-AC-01): draft-close --------------------------------------

test_001_draft_close() {
  log_info "Test: draft-close -> status: done, doc_lifecycle from=draft to=done, exit 0 (TEST-001)..."
  local dir; dir=$(new_fixture_repo "t001")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t001.md" "t001-slug" "draft"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t001.out" err="$TEST_DIR/t001.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t001-slug --pr 1 --commit a0a0a01)
  assert_exit "draft close" 0 "$code"

  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t001.md" \
    || log_fail "t001: frontmatter status was not flipped to done"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" doc_lifecycle t001-slug from draft)" -ge 1 ]] \
    || log_fail "t001: missing doc_lifecycle event with from=draft"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" doc_lifecycle t001-slug to done)" -ge 1 ]] \
    || log_fail "t001: missing doc_lifecycle event with to=done"

  log_pass "Draft-close: status flipped, bare-slug doc_lifecycle event, exit 0 (TEST-001)"
}

# --- TEST-002 (Spec-AC-01, SPEC-0046 regression): implementing-close --------

test_002_implementing_close() {
  log_info "Test: implementing-close (SPEC-0046 regression) -> done; real audit tracked-done, never probable-false-open (TEST-002)..."
  local dir; dir=$(new_fixture_repo "t002")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t002.md" "t002-slug" "implementing"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t002.out" err="$TEST_DIR/t002.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t002-slug --pr 2 --commit b0b0b02)
  assert_exit "implementing close" 0 "$code"

  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t002.md" \
    || log_fail "t002: frontmatter status was not flipped to done (SPEC-0046 flip-miss regression)"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" doc_lifecycle t002-slug from implementing)" -ge 1 ]] \
    || log_fail "t002: missing doc_lifecycle event with from=implementing (ACTUAL status, not an assumed draft)"

  local audit_out="$TEST_DIR/t002-audit.out"
  ( cd "$dir" && node "$DOCS_AUDIT" --list --no-event ) > "$audit_out" 2>&1 || true
  grep -qF "| t002-slug | tracked-done |" "$audit_out" \
    || log_fail "t002: real audit does not classify t002-slug tracked-done: $(cat "$audit_out")"
  if grep -F "t002-slug" "$audit_out" | grep -q "probable-false-open"; then
    log_fail "t002: real audit flags probable-false-open (the exact SPEC-0046 incident class)"
  fi

  log_pass "Implementing-close: status flipped from ACTUAL value, real audit tracked-done never false-open (TEST-002)"
}

# --- TEST-003 (Spec-AC-01): non-done-terminal guard --------------------------

test_003_non_done_terminal_guard() {
  log_info "Test: non-done-terminal guard -> deferred/superseded refuse with exit 2, doc + EVENTS untouched (TEST-003)..."
  local dir; dir=$(new_fixture_repo "t003")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t003a.md" "t003a-slug" "deferred"
  write_change_doc "$dir/docs/issues/CHANGE-0002-t003b.md" "t003b-slug" "superseded"
  commit_fixture_docs "$dir"
  cp "$dir/docs/issues/CHANGE-0001-t003a.md" "$TEST_DIR/t003a-before.md"
  cp "$dir/docs/issues/CHANGE-0002-t003b.md" "$TEST_DIR/t003b-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t003a.out" err="$TEST_DIR/t003a.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t003a-slug --pr 3 --commit c0c0c03)
  assert_exit "deferred doc refuses close" 2 "$code"
  grep -qiE "deferred|non-done-terminal|refus" "$err" \
    || log_fail "t003a: expected a named reason in stderr, got: $(cat "$err")"

  out="$TEST_DIR/t003b.out"; err="$TEST_DIR/t003b.err"
  code=$(run_close "$dir" "$out" "$err" --ref t003b-slug --pr 3 --commit d0d0d03)
  assert_exit "superseded doc refuses close" 2 "$code"
  grep -qiE "superseded|non-done-terminal|refus" "$err" \
    || log_fail "t003b: expected a named reason in stderr, got: $(cat "$err")"

  diff -q "$TEST_DIR/t003a-before.md" "$dir/docs/issues/CHANGE-0001-t003a.md" >/dev/null \
    || log_fail "t003a: doc was mutated despite exit 2"
  diff -q "$TEST_DIR/t003b-before.md" "$dir/docs/issues/CHANGE-0002-t003b.md" >/dev/null \
    || log_fail "t003b: doc was mutated despite exit 2"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t003: EVENTS.jsonl grew despite exit 2"

  log_pass "Non-done-terminal guard: deferred + superseded refuse with a named reason, nothing written (TEST-003)"
}

# --- TEST-004 (Spec-AC-02, SEAM 1/2): ref-form + real-audit CLEAN ------------

test_004_ref_form_and_audit_clean() {
  log_info "Test: ref-form (bare slug, never numbered) + REAL audit CLEAN for the closed ref (TEST-004)..."
  local dir; dir=$(new_fixture_repo "t004")
  write_change_doc "$dir/docs/issues/CHANGE-0007-t004.md" "t004-slug" "draft"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t004.out" err="$TEST_DIR/t004.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t004-slug --pr 7 --commit e0e0e04)
  assert_exit "t004 close" 0 "$code"

  if grep -qF '"CHANGE-0007"' "$dir/docs/ai/EVENTS.jsonl"; then
    log_fail "t004: a numbered ref (CHANGE-0007) leaked into EVENTS.jsonl — must be the bare slug"
  fi
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" doc_lifecycle t004-slug from draft)" -ge 1 ]] \
    || log_fail "t004: missing doc_lifecycle with the bare slug ref"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" work_item_closed t004-slug)" -ge 1 ]] \
    || log_fail "t004: missing work_item_closed with the bare slug ref"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" ac_evidence t004-slug commit e0e0e04)" -ge 1 ]] \
    || log_fail "t004: missing ac_evidence with the bare slug ref + commit"

  local audit_out="$TEST_DIR/t004-audit.out"
  ( cd "$dir" && node "$DOCS_AUDIT" --list --no-event ) > "$audit_out" 2>&1 || true
  grep -qF "| t004-slug | tracked-done | done | aligned |" "$audit_out" \
    || log_fail "t004: real audit does not classify t004-slug tracked-done/aligned: $(cat "$audit_out")"
  if grep -F "t004-slug" "$audit_out" | grep -qE "probable-false-done|probable-false-open|missing-close-telemetry"; then
    log_fail "t004: real audit flags false-done/false-open/missing-close-telemetry for t004-slug"
  fi

  log_pass "Ref-form + real-audit CLEAN: every event uses the bare slug, audit classifies tracked-done/aligned (TEST-004)"
}

# --- TEST-005 (Spec-AC-03): pair close ---------------------------------------

test_005_pair_close() {
  log_info "Test: pair close --ref <change> --spec <spec> -> BOTH done, BOTH full event set, real audit CLEAN for both (TEST-005)..."
  local dir; dir=$(new_fixture_repo "t005")
  write_change_doc "$dir/docs/issues/CHANGE-0009-t005.md" "t005-change-slug" "implementing"
  write_spec_doc "$dir/docs/specs/SPEC-0009-t005.md" "t005-spec-slug" "implementing" "done"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t005.out" err="$TEST_DIR/t005.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t005-change-slug --spec t005-spec-slug --pr 9 --commit f0f0f05)
  assert_exit "pair close" 0 "$code"

  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0009-t005.md" || log_fail "t005: change doc not flipped to done"
  grep -q '^status: done$' "$dir/docs/specs/SPEC-0009-t005.md" || log_fail "t005: spec doc not flipped to done"

  local ev="$dir/docs/ai/EVENTS.jsonl"
  [[ "$(events_count "$ev" doc_lifecycle t005-change-slug from implementing)" -ge 1 ]] || log_fail "t005: change missing doc_lifecycle"
  [[ "$(events_count "$ev" work_item_closed t005-change-slug)" -ge 1 ]] || log_fail "t005: change missing work_item_closed"
  [[ "$(events_count "$ev" ac_evidence t005-change-slug commit f0f0f05)" -ge 1 ]] || log_fail "t005: change missing ac_evidence"
  [[ "$(events_count "$ev" doc_lifecycle t005-spec-slug from implementing)" -ge 1 ]] || log_fail "t005: spec missing doc_lifecycle"
  [[ "$(events_count "$ev" work_item_closed t005-spec-slug)" -ge 1 ]] || log_fail "t005: spec missing work_item_closed"
  [[ "$(events_count "$ev" ac_evidence t005-spec-slug commit f0f0f05)" -ge 1 ]] || log_fail "t005: spec missing ac_evidence (D5 symmetry)"

  local audit_out="$TEST_DIR/t005-audit.out"
  ( cd "$dir" && node "$DOCS_AUDIT" --list --no-event ) > "$audit_out" 2>&1 || true
  grep -qF "| t005-change-slug | tracked-done | done | aligned |" "$audit_out" || log_fail "t005: change not tracked-done/aligned"
  grep -qF "| t005-spec-slug | tracked-done | done | aligned |" "$audit_out" || log_fail "t005: spec not tracked-done/aligned"

  log_pass "Pair close: both docs done, both carry the complete slug-reffed event set, real audit CLEAN (TEST-005)"
}

# --- TEST-006 (Spec-AC-03): pair pre-write abort -----------------------------

test_006_pair_pre_write_abort() {
  log_info "Test: pair pre-write abort -> unresolvable --spec exits 2 BEFORE any write (TEST-006)..."
  local dir; dir=$(new_fixture_repo "t006")
  write_change_doc "$dir/docs/issues/CHANGE-0011-t006.md" "t006-change-slug" "draft"
  commit_fixture_docs "$dir"
  cp "$dir/docs/issues/CHANGE-0011-t006.md" "$TEST_DIR/t006-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t006.out" err="$TEST_DIR/t006.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t006-change-slug --spec no-such-spec-slug --pr 11 --commit 11a11a1)
  assert_exit "unresolvable spec aborts pre-write" 2 "$code"
  grep -qiE "no scanned doc resolves|unresolv" "$err" \
    || log_fail "t006: expected a named unresolvable-ref reason, got: $(cat "$err")"

  diff -q "$TEST_DIR/t006-before.md" "$dir/docs/issues/CHANGE-0011-t006.md" >/dev/null \
    || log_fail "t006: primary doc was mutated despite pre-write abort"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t006: EVENTS.jsonl grew despite pre-write abort"

  log_pass "Pair pre-write abort: unresolvable spec exits 2, primary doc + EVENTS untouched, never half-closed (TEST-006)"
}

# --- TEST-007 (Spec-AC-04): idempotent re-run --------------------------------

test_007_idempotent_rerun() {
  log_info "Test: idempotent re-run -> second close appends zero new events, no duplicate links, exit 0 (TEST-007)..."
  local dir; dir=$(new_fixture_repo "t007")
  write_change_doc "$dir/docs/issues/CHANGE-0013-t007.md" "t007-slug" "draft"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t007a.out" err="$TEST_DIR/t007a.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t007-slug --pr 13 --commit 22b22b2)
  assert_exit "t007 first close" 0 "$code"

  local events_after_first; events_after_first=$(file_size "$dir/docs/ai/EVENTS.jsonl")
  local doc_after_first; doc_after_first=$(cat "$dir/docs/issues/CHANGE-0013-t007.md")

  out="$TEST_DIR/t007b.out"; err="$TEST_DIR/t007b.err"
  code=$(run_close "$dir" "$out" "$err" --ref t007-slug --pr 13 --commit 22b22b2)
  assert_exit "t007 second (idempotent) close" 0 "$code"

  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_after_first" ]] \
    || log_fail "t007: second run appended new EVENTS.jsonl lines (not idempotent)"
  [[ "$(cat "$dir/docs/issues/CHANGE-0013-t007.md")" == "$doc_after_first" ]] \
    || log_fail "t007: second run mutated the doc again (duplicate links.pr/links.commits?)"

  log_pass "Idempotent re-run: zero new events, zero duplicate links, exit 0 (TEST-007)"
}

# --- TEST-008 (Spec-AC-04, fail-closed): rigged self-verify failure ---------

test_008_fail_closed_rollback() {
  log_info "Test: fail-closed rollback -> rigged non-terminal AC row fails self-verify, exit non-zero, total rollback (TEST-008)..."
  local dir; dir=$(new_fixture_repo "t008")
  write_change_doc "$dir/docs/issues/CHANGE-0015-t008.md" "t008-change-slug" "implementing"
  write_spec_doc "$dir/docs/specs/SPEC-0015-t008.md" "t008-spec-slug" "implementing" "planned" "—"
  commit_fixture_docs "$dir"
  cp "$dir/docs/issues/CHANGE-0015-t008.md" "$TEST_DIR/t008-change-before.md"
  cp "$dir/docs/specs/SPEC-0015-t008.md" "$TEST_DIR/t008-spec-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t008.out" err="$TEST_DIR/t008.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t008-change-slug --spec t008-spec-slug --pr 15 --commit 33c33c3)
  [[ "$code" != "0" ]] || log_fail "t008: expected a non-zero exit (self-verify must catch the rigged non-terminal AC row), got 0"
  grep -qiE "not clean|rolled back|probable-false-done|non-terminal" "$err" \
    || log_fail "t008: expected a named finding in stderr, got: $(cat "$err")"

  diff -q "$TEST_DIR/t008-change-before.md" "$dir/docs/issues/CHANGE-0015-t008.md" >/dev/null \
    || log_fail "t008: change doc was not restored to its pre-run snapshot"
  diff -q "$TEST_DIR/t008-spec-before.md" "$dir/docs/specs/SPEC-0015-t008.md" >/dev/null \
    || log_fail "t008: spec doc was not restored to its pre-run snapshot"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t008: EVENTS.jsonl was not truncated back to its pre-run byte length"

  log_pass "Fail-closed rollback: rigged non-terminal AC row rolls back BOTH docs + EVENTS byte-length, named finding (TEST-008)"
}

# --- TEST-009 (Spec-AC-05): canon grep contract ------------------------------

test_009_canon_grep_contract() {
  log_info "Test: canon grep contract — SKILL_PR names the script, VALIDATION drops hand-flip/hand-emit, strict audit exit 0 (TEST-009)..."

  grep -qF "close-work-item.mjs" "$SKILL_PR" \
    || log_fail "t009: SKILL_PR.prompt.md must name close-work-item.mjs"
  grep -qF "close-work-item.mjs" "$VALIDATION_PROMPT" \
    || log_fail "t009: VALIDATION.prompt.md must point to close-work-item.mjs"

  if grep -qF "append-event.mjs --event work_item_closed" "$VALIDATION_PROMPT"; then
    log_fail "t009: VALIDATION.prompt.md still hand-emits work_item_closed via append-event.mjs"
  fi
  if grep -qF 'writing `status: done`' "$VALIDATION_PROMPT"; then
    log_fail "t009: VALIDATION.prompt.md still instructs a hand status:done flip"
  fi

  local audit_log="$TEST_DIR/t009-strict-audit.log"
  ( cd "$PROJECT_ROOT" && node "$DOCS_AUDIT" --check --strict --no-event > "$audit_log" 2>&1 ) \
    || log_fail "t009: repo-wide strict docs-audit must exit 0: $(tail -20 "$audit_log")"

  log_pass "Canon grep contract: SKILL_PR names the script, VALIDATION drops hand-flip/hand-emit, strict audit clean (TEST-009)"
}

# --- TEST-010 (Spec-AC-04, code-review B1 regression): post-apply INDEX ------
# regen failure must not bypass rollback -----------------------------------

test_010_fail_closed_index_regen_rollback() {
  log_info "Test: fail-closed rollback -> post-apply INDEX regen failure (rigged marker-guard) must run rollback via the catch, never bypass it via an uncatchable process.exit (TEST-010, code-review B1)..."
  local dir; dir=$(new_fixture_repo "t010")
  write_change_doc "$dir/docs/issues/CHANGE-0021-t010.md" "t010-slug" "draft"
  commit_fixture_docs "$dir"
  # Rig docs/INDEX.md so generate-docs-index.mjs's own marker guard (checkMarker)
  # refuses to overwrite it and exits non-zero — a deterministic, in-repo way to
  # make the post-apply self-verify's INDEX regeneration fail without touching
  # any shared script (mirrors the spec's R4 downstream-missing-generator case:
  # self-verify cannot complete, so the close must not proceed silently).
  printf 'not the auto-generated marker\n' > "$dir/docs/INDEX.md"

  cp "$dir/docs/issues/CHANGE-0021-t010.md" "$TEST_DIR/t010-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t010.out" err="$TEST_DIR/t010.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t010-slug --pr 21 --commit 44d44d4)
  [[ "$code" != "0" ]] \
    || log_fail "t010: expected a non-zero exit (INDEX regen failure must not silently succeed), got 0"
  grep -qiE "internal error|index regeneration|rolled back" "$err" \
    || log_fail "t010: expected a named finding in stderr, got: $(cat "$err")"

  diff -q "$TEST_DIR/t010-before.md" "$dir/docs/issues/CHANGE-0021-t010.md" >/dev/null \
    || log_fail "t010: doc was NOT restored to its pre-run snapshot (B1: half-closed doc left on disk)"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t010: EVENTS.jsonl was NOT truncated back to its pre-run byte length (B1: half-closed event set left on disk)"

  log_pass "Fail-closed rollback: post-apply INDEX regen failure rolls back doc + EVENTS (no half-close), exit non-zero (TEST-010, B1)"
}

# --- TEST-011 (code-review B2 regression): inline non-empty links.pr --------
# normalized to block form before appending ----------------------------------

test_011_inline_nonempty_links_normalized() {
  log_info "Test: stampLink normalizes a pre-existing INLINE non-empty links.pr list to block form before appending, instead of splicing a block item after the inline line (TEST-011, code-review B2)..."
  local dir; dir=$(new_fixture_repo "t011")
  local doc="$dir/docs/issues/CHANGE-0022-t011.md"
  cat > "$doc" <<'EOF'
---
id: t011-slug
type: change
status: draft
links:
  pr: [42]
  commits: []
---

# Change — Fixture t011-slug

## Summary
- fixture doc for close-work-item tests (inline non-empty links.pr).

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
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t011.out" err="$TEST_DIR/t011.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t011-slug --pr 99 --commit 55e55e5)
  assert_exit "t011 close with pre-existing inline non-empty links.pr" 0 "$code"

  # The malformed-mixed-YAML bug (B2) left the raw inline line `  pr: [42]`
  # in place and spliced a bare block item (`    - 99`) directly after it.
  # Assert that shape is ABSENT — the inline line must be normalized away.
  if grep -qF '  pr: [42]' "$doc"; then
    log_fail "t011: links.pr still carries the raw inline form — not normalized to block (malformed mixed YAML)"
  fi
  grep -q '^  pr:$' "$doc" || log_fail "t011: links.pr was not normalized to block form"
  grep -qF '    - 42' "$doc" || log_fail "t011: pre-existing inline value 42 was lost during normalization"
  grep -qF '    - 99' "$doc" || log_fail "t011: newly stamped value 99 is missing"

  local doc_after_first; doc_after_first=$(cat "$doc")

  # Re-run with the SAME args: this exercises the normalized block form
  # through the script's OWN reader (locateLinksField/hasLinkValue) — the
  # idempotency short-circuit must recognize both 42 and 99 as already
  # present and write nothing further (proves the normalized shape round-trips
  # cleanly through the script's own parser, not just a generic YAML parser).
  out="$TEST_DIR/t011b.out"; err="$TEST_DIR/t011b.err"
  code=$(run_close "$dir" "$out" "$err" --ref t011-slug --pr 99 --commit 55e55e5)
  assert_exit "t011 second (idempotent) close after normalization" 0 "$code"
  [[ "$(cat "$doc")" == "$doc_after_first" ]] \
    || log_fail "t011: second run mutated the normalized doc again (not idempotent / not round-trippable)"

  log_pass "Inline non-empty links.pr normalized to block form on append, both values present, idempotent re-run confirms round-trip (TEST-011, B2)"
}

# --- TEST-012 (code-review B3 regression): null fm.id pre-write guard -------

test_012_null_fm_id_pre_write_guard() {
  log_info "Test: a doc with no frontmatter id (resolved only by display-id) is rejected with a clean PRE-WRITE exit 2, never an internal-error apply/rollback cycle (TEST-012, code-review B3)..."
  local dir; dir=$(new_fixture_repo "t012")
  local doc="$dir/docs/issues/CHANGE-0023-t012.md"
  cat > "$doc" <<'EOF'
---
type: change
status: draft
links:
  pr: []
  commits: []
---

# Change — Fixture CHANGE-0023-t012 (no frontmatter id)

## Summary
- fixture doc for close-work-item tests (missing id: key).

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
  commit_fixture_docs "$dir"
  cp "$doc" "$TEST_DIR/t012-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t012.out" err="$TEST_DIR/t012.err" code
  code=$(run_close "$dir" "$out" "$err" --ref CHANGE-0023 --pr 23 --commit 66f66f6)
  assert_exit "null fm.id resolved-by-display-id refuses pre-write" 2 "$code"
  grep -qiE 'no frontmatter.*id|frontmatter has no.*id|has no.*"?id"?' "$err" \
    || log_fail "t012: expected a named missing-id reason in stderr, got: $(cat "$err")"

  diff -q "$TEST_DIR/t012-before.md" "$doc" >/dev/null \
    || log_fail "t012: doc was mutated despite exit 2 (must be pre-write)"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t012: EVENTS.jsonl grew despite exit 2 (must be pre-write)"

  log_pass "Null fm.id resolved by display-id: clean pre-write exit 2, doc + EVENTS untouched (TEST-012, B3)"
}

# --- TEST-013 (CHANGE-0052): brief auto-cleanup on close ---------------------

test_013_brief_cleanup_on_close() {
  log_info "Test: brief auto-cleanup -> a durable close prunes docs/ai/briefs/<ref>.md, spares an unrelated brief, never fails the close (TEST-013)..."
  local dir; dir=$(new_fixture_repo "t013")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t013.md" "t013-slug" "implementing"
  commit_fixture_docs "$dir"

  # Three briefs: the SLUG-named brief (t013-slug.md), the DISPLAY-ID-named brief
  # (CHANGE-0001.md — PLANNING has historically named briefs by either form), and
  # an unrelated one that MUST survive.
  mkdir -p "$dir/docs/ai/briefs"
  printf 'brief for t013-slug\n' > "$dir/docs/ai/briefs/t013-slug.md"
  printf 'brief for CHANGE-0001 display id\n' > "$dir/docs/ai/briefs/CHANGE-0001.md"
  printf 'brief for someone else\n' > "$dir/docs/ai/briefs/other-slug.md"

  local out="$TEST_DIR/t013.out" err="$TEST_DIR/t013.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t013-slug --pr 13 --commit e0e0e13)
  assert_exit "brief-cleanup close" 0 "$code"

  [[ ! -e "$dir/docs/ai/briefs/t013-slug.md" ]] \
    || log_fail "t013: SLUG-named brief for the closed ref was NOT pruned"
  [[ ! -e "$dir/docs/ai/briefs/CHANGE-0001.md" ]] \
    || log_fail "t013: DISPLAY-ID-named brief for the closed ref was NOT pruned (bot-review P2)"
  [[ -e "$dir/docs/ai/briefs/other-slug.md" ]] \
    || log_fail "t013: an UNRELATED brief was wrongly pruned"
  grep -qF "pruned brief" "$out" \
    || log_fail "t013: success line did not report the pruned brief: $(cat "$out")"

  # No-brief close must still succeed cleanly (best-effort, missing brief is a no-op).
  local dir2; dir2=$(new_fixture_repo "t013b")
  write_change_doc "$dir2/docs/issues/CHANGE-0001-t013b.md" "t013b-slug" "implementing"
  commit_fixture_docs "$dir2"
  out="$TEST_DIR/t013b.out"; err="$TEST_DIR/t013b.err"
  code=$(run_close "$dir2" "$out" "$err" --ref t013b-slug --pr 14 --commit f0f0f14)
  assert_exit "no-brief close still succeeds" 0 "$code"
  grep -qF "pruned brief" "$out" \
    && log_fail "t013b: reported a pruned brief when none existed: $(cat "$out")"

  log_pass "Brief auto-cleanup: closed ref's brief pruned, unrelated brief spared, no-brief close clean (TEST-013)"
}

# --- token-economics-end-to-end TEST-008/TEST-009 (Spec-AC-06) ---------------
# best-effort overview-data regen as the STRICTLY LAST step of a successful
# close (after self-verify + pruneBriefs); a generator failure is swallowed —
# never changes the close exit code, never reaches rollback (negative
# control). RED-proof obligation: both are integrity-critical rows.

test_014_overview_regen_best_effort() {  # token-economics TEST-008
  log_info "Test: a successful close regenerates overview-data.json best-effort and exits 0 (token-economics TEST-008)..."
  local dir; dir=$(new_fixture_repo "t014")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t014.md" "t014-slug" "draft"
  commit_fixture_docs "$dir"

  [[ -e "$dir/docs/ai/overview-data.json" ]] \
    && log_fail "t014: fixture setup bug — overview-data.json must not pre-exist"

  local out="$TEST_DIR/t014.out" err="$TEST_DIR/t014.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t014-slug --pr 14 --commit c0c0c14)
  assert_exit "close with overview regen" 0 "$code"

  [[ -f "$dir/docs/ai/overview-data.json" ]] \
    || log_fail "t014: close did not regenerate docs/ai/overview-data.json (Spec-AC-06 best-effort hook)"
  node -e '
    const fs = require("fs");
    const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const hit = m.delivered.find(x => x.ref === "t014-slug");
    if (!hit) { console.error("t014-slug not present in regenerated delivered list"); process.exit(1); }
    if (hit.status !== "done") { console.error("regenerated overview shows non-done status: " + hit.status); process.exit(1); }
  ' "$dir/docs/ai/overview-data.json" || log_fail "t014: regenerated overview-data.json does not reflect the just-closed item"

  log_pass "Successful close regenerates overview-data.json best-effort, closed item present as done, exit 0 (token-economics TEST-008)"
}

test_015_overview_regen_failure_negative_control() {  # token-economics TEST-009
  log_info "Test: NEGATIVE CONTROL — a rigged overview-generator failure leaves close exit 0, the doc still done, close events intact (no rollback) (token-economics TEST-009)..."
  local dir; dir=$(new_fixture_repo "t015")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t015.md" "t015-slug" "draft"
  commit_fixture_docs "$dir"

  # Rig the generator to fail: put a DIRECTORY where it must write a file, so
  # generate-overview.mjs's fs.writeFileSync throws EISDIR. No flag/mock
  # needed -- this exercises the REAL generator failing for real.
  mkdir -p "$dir/docs/ai/overview-data.json"

  local out="$TEST_DIR/t015.out" err="$TEST_DIR/t015.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t015-slug --pr 15 --commit d0d0d15)
  assert_exit "close survives a rigged generator failure" 0 "$code"

  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t015.md" \
    || log_fail "t015: the close itself must NOT be rolled back by a generator failure -- doc must still be done"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" work_item_closed t015-slug)" -ge 1 ]] \
    || log_fail "t015: work_item_closed event must still be present (no rollback triggered by the generator failure)"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" doc_lifecycle t015-slug)" -ge 1 ]] \
    || log_fail "t015: doc_lifecycle event must still be present (no rollback triggered by the generator failure)"

  log_pass "Generator failure is swallowed: close exit 0, doc still done, close events intact, no rollback (token-economics TEST-009)"
}

# --- product-docs-enforced TEST-001 (Spec-AC-01): report-only warns ---------

test_016_gate_report_only_warns() {
  log_info "Test: user_visible + missing product doc + report-only dial: WARNING on stderr, close exit 0, doc flipped (product-docs-enforced TEST-001)..."
  local dir; dir=$(new_fixture_repo "t016")
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0001-t016.md" "t016-slug" "draft"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t016.out" err="$TEST_DIR/t016.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t016-slug --pr 16 --commit a1a1a16)
  assert_exit "report-only gate close" 0 "$code"

  grep -qi 'WARNING.*product-doc gate' "$err" \
    || log_fail "t016: expected a product-doc-gate WARNING on stderr, got: $(cat "$err")"
  grep -qF 't016-slug' "$err" || log_fail "t016: WARNING did not name the scope"
  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t016.md" \
    || log_fail "t016: report-only must still let the close proceed (status not flipped)"

  log_pass "Report-only gate: WARNING on stderr, close proceeds, doc flipped (product-docs-enforced TEST-001)"
}

# --- product-docs-enforced TEST-002 (Spec-AC-01): enforce refuses pre-write -

test_017_gate_enforce_refuses_pre_write() {
  log_info "Test: user_visible + missing product doc + enforce dial: refuse exit non-zero, doc bytes + EVENTS length unchanged (pre-write) (product-docs-enforced TEST-002)..."
  local dir; dir=$(new_fixture_repo "t017")
  set_product_doc_gate_dial "$dir" "enforce"
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0001-t017.md" "t017-slug" "draft"
  commit_fixture_docs "$dir"
  cp "$dir/docs/issues/CHANGE-0001-t017.md" "$TEST_DIR/t017-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t017.out" err="$TEST_DIR/t017.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t017-slug --pr 17 --commit b1b1b17)
  assert_exit "enforce gate refuses" 3 "$code"
  grep -qi 'REFUSED.*product-doc gate' "$err" \
    || log_fail "t017: expected a product-doc-gate REFUSED line on stderr, got: $(cat "$err")"
  grep -qF 't017-slug' "$err" || log_fail "t017: REFUSED reason did not name the scope"

  diff -q "$TEST_DIR/t017-before.md" "$dir/docs/issues/CHANGE-0001-t017.md" >/dev/null \
    || log_fail "t017: doc was mutated despite a pre-write refusal"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t017: EVENTS.jsonl grew despite a pre-write refusal"
  [[ ! -e "$dir/docs/INDEX.md" ]] \
    || log_fail "t017: docs/INDEX.md was created despite a pre-write refusal (gate must fire before ANY write, including self-verify's INDEX regen)"

  log_pass "Enforce gate: refuse exit 3, nothing written (doc + EVENTS + INDEX untouched) (product-docs-enforced TEST-002)"
}

# --- product-docs-enforced TEST-003 (Spec-AC-01): absent key negative control

test_018_gate_absent_user_visible_negative_control() {
  log_info "Test: user_visible absent (legacy) -- gate silent, close proceeds regardless of product doc, even under enforce (product-docs-enforced TEST-003)..."
  local dir; dir=$(new_fixture_repo "t018")
  set_product_doc_gate_dial "$dir" "enforce"
  write_change_doc "$dir/docs/issues/CHANGE-0001-t018.md" "t018-slug" "draft"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t018.out" err="$TEST_DIR/t018.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t018-slug --pr 18 --commit c1c1c18)
  assert_exit "absent user_visible proceeds under enforce" 0 "$code"
  if grep -qi 'product-doc gate' "$err"; then
    log_fail "t018: gate must be SILENT when user_visible is absent, got: $(cat "$err")"
  fi
  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t018.md" \
    || log_fail "t018: close did not proceed for a legacy (non-user_visible) doc"

  log_pass "Negative control: absent user_visible is silent and unaffected by the enforce dial (product-docs-enforced TEST-003)"
}

# --- product-docs-enforced TEST-004 (Spec-AC-01): real product doc passes ---

test_019_gate_real_product_doc_passes_enforce() {
  log_info "Test: user_visible + real product doc present under enforce: close proceeds, no warning (product-docs-enforced TEST-004)..."
  local dir; dir=$(new_fixture_repo "t019")
  set_product_doc_gate_dial "$dir" "enforce"
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0001-t019.md" "t019-slug" "draft"
  write_real_product_doc "$dir" "t019-slug"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t019.out" err="$TEST_DIR/t019.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t019-slug --pr 19 --commit d1d1d19)
  assert_exit "real product doc under enforce proceeds" 0 "$code"
  if grep -qi 'product-doc gate' "$err"; then
    log_fail "t019: a REAL product doc must not warn/refuse, got: $(cat "$err")"
  fi
  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t019.md" \
    || log_fail "t019: close did not proceed despite a real product doc"

  log_pass "Real product doc present: enforce proceeds silently (product-docs-enforced TEST-004)"
}

# --- product-docs-enforced TEST-005 (Spec-AC-02): placeholder Data model ----

test_020_gate_placeholder_data_model_counts_missing() {
  log_info "Test: a product doc with a placeholder Data model section counts as missing (enforce refuses) (product-docs-enforced TEST-005)..."
  local dir; dir=$(new_fixture_repo "t020")
  set_product_doc_gate_dial "$dir" "enforce"
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0001-t020.md" "t020-slug" "draft"
  write_placeholder_data_model_product_doc "$dir" "t020-slug"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t020.out" err="$TEST_DIR/t020.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t020-slug --pr 20 --commit e1e1e20)
  assert_exit "placeholder Data model refuses under enforce" 3 "$code"
  grep -qF 'Data model' "$err" \
    || log_fail "t020: REFUSED reason did not name the placeholder Data model section, got: $(cat "$err")"

  log_pass "Placeholder Data model counts as missing: enforce refuses, names the section (product-docs-enforced TEST-005)"
}

# --- product-docs-enforced TEST-006 (Spec-AC-02): placeholder Interfaces + --
# an explicit None. section counts as real --------------------------------

test_021_gate_placeholder_interfaces_and_none_dot_passes() {
  log_info "Test: placeholder Interfaces section counts as missing; a section reading None. counts as real and passes (product-docs-enforced TEST-006)..."
  local dir; dir=$(new_fixture_repo "t021")
  set_product_doc_gate_dial "$dir" "enforce"
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0001-t021a.md" "t021a-slug" "draft"
  write_placeholder_interfaces_product_doc "$dir" "t021a-slug"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t021a.out" err="$TEST_DIR/t021a.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t021a-slug --pr 21 --commit f1f1f21)
  assert_exit "placeholder Interfaces refuses under enforce" 3 "$code"
  grep -qF 'Interfaces and contracts' "$err" \
    || log_fail "t021a: REFUSED reason did not name the placeholder Interfaces section, got: $(cat "$err")"

  # Sibling case in the SAME fixture repo: a doc whose Data model AND
  # Interfaces both read the literal "None." must PASS (D2: "None." is REAL).
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0002-t021b.md" "t021b-slug" "draft"
  write_none_dot_product_doc "$dir" "t021b-slug"
  commit_fixture_docs "$dir"

  out="$TEST_DIR/t021b.out"; err="$TEST_DIR/t021b.err"
  code=$(run_close "$dir" "$out" "$err" --ref t021b-slug --pr 21 --commit 01f1f21)
  assert_exit "None. sections pass under enforce" 0 "$code"
  if grep -qi 'product-doc gate' "$err"; then
    log_fail "t021b: explicit None. sections must PASS (be treated as real), got: $(cat "$err")"
  fi

  log_pass "Placeholder Interfaces refuses (named); explicit None. sections pass (product-docs-enforced TEST-006)"
}

# --- product-docs-enforced TEST-011 (Spec-AC-04 SEAM): best-effort rollup ---
# hook updates USER_GUIDE on a real close --------------------------------

test_022_seam_close_updates_userguide_rollup() {
  log_info "Test: SEAM -- a real close of a user_visible item with a real product doc updates the USER_GUIDE marked region (product-docs-enforced TEST-011)..."
  local dir; dir=$(new_fixture_repo "t022")
  write_user_visible_change_doc "$dir/docs/issues/CHANGE-0001-t022.md" "t022-slug" "draft"
  write_real_product_doc "$dir" "t022-slug"
  commit_fixture_docs "$dir"

  [[ ! -e "$dir/docs/USER_GUIDE.md" ]] \
    || log_fail "t022: fixture setup bug -- docs/USER_GUIDE.md must not pre-exist"

  local out="$TEST_DIR/t022.out" err="$TEST_DIR/t022.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t022-slug --pr 22 --commit a2a2a22)
  assert_exit "close with rollup hook" 0 "$code"

  [[ -f "$dir/docs/USER_GUIDE.md" ]] \
    || log_fail "t022: close did not regenerate docs/USER_GUIDE.md (best-effort rollup hook, D5)"
  grep -qF '<!-- AAI:USERGUIDE-ROLLUP:BEGIN' "$dir/docs/USER_GUIDE.md" \
    || log_fail "t022: USER_GUIDE.md missing the rollup BEGIN marker"
  grep -qF 'Fixture Feature t022-slug' "$dir/docs/USER_GUIDE.md" \
    || log_fail "t022: rendered rollup does not carry the just-closed item's product doc title"

  log_pass "SEAM: a real close regenerates USER_GUIDE with the product doc rendered in the marked region (product-docs-enforced TEST-011)"
}

# --- product-docs-enforced TEST-012 (Spec-AC-04): negative control ----------
# a rigged rollup failure never changes the close exit code -----------------

test_023_negative_control_rollup_failure() {
  log_info "Test: NEGATIVE CONTROL -- a rigged rollup-generator failure leaves close exit 0, doc done, close events intact (no rollback) (product-docs-enforced TEST-012)..."
  local dir; dir=$(new_fixture_repo "t023")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t023.md" "t023-slug" "draft"
  commit_fixture_docs "$dir"

  # Rig the generator to fail: put a DIRECTORY where it must write a file, so
  # generate-userguide-rollup.mjs's fs.writeFileSync throws EISDIR -- the same
  # deterministic in-repo rigging technique as the overview-regen negative
  # control (test_015).
  mkdir -p "$dir/docs/USER_GUIDE.md"

  local out="$TEST_DIR/t023.out" err="$TEST_DIR/t023.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t023-slug --pr 23 --commit b2b2b23)
  assert_exit "close survives a rigged rollup failure" 0 "$code"

  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t023.md" \
    || log_fail "t023: the close itself must NOT be rolled back by a rollup-generator failure -- doc must still be done"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" work_item_closed t023-slug)" -ge 1 ]] \
    || log_fail "t023: work_item_closed event must still be present (no rollback triggered by the rollup failure)"
  [[ "$(events_count "$dir/docs/ai/EVENTS.jsonl" doc_lifecycle t023-slug)" -ge 1 ]] \
    || log_fail "t023: doc_lifecycle event must still be present (no rollback triggered by the rollup failure)"
  grep -qi 'userguide rollup regen skipped' "$out" "$err" 2>/dev/null || true

  log_pass "Generator failure is swallowed: close exit 0, doc still done, close events intact, no rollback (product-docs-enforced TEST-012)"
}

# --- product-docs-enforced TEST-013 (Spec-AC-05): legacy suite regression ---

test_024_legacy_suite_regression() {
  log_info "Test: full existing close-work-item suite (legacy TEST-001..015) stays green -- no regression from the product-doc gate + rollup hook (product-docs-enforced TEST-013)..."
  local legacy_tests="test_001_draft_close test_002_implementing_close test_003_non_done_terminal_guard \
test_004_ref_form_and_audit_clean test_005_pair_close test_006_pair_pre_write_abort \
test_007_idempotent_rerun test_008_fail_closed_rollback test_009_canon_grep_contract \
test_010_fail_closed_index_regen_rollback test_011_inline_nonempty_links_normalized \
test_012_null_fm_id_pre_write_guard test_013_brief_cleanup_on_close \
test_014_overview_regen_best_effort test_015_overview_regen_failure_negative_control"
  local t out
  for t in $legacy_tests; do
    out="$TEST_DIR/regress-$t.out"
    if ! bash "$TEST_SELF" "$t" > "$out" 2>&1; then
      log_fail "product-docs-enforced TEST-013: legacy $t FAILED under regression re-run: $(tail -20 "$out")"
    fi
  done
  log_pass "Legacy suite regression: all 15 pre-existing close-work-item tests still pass standalone (product-docs-enforced TEST-013)"
}

# --- product-docs-enforced TEST-014 (Spec-AC-05): guard-config dial (unit) --

test_025_guard_config_product_doc_gate_dial() {
  log_info "Test: guard-config readGuardConfig returns product_doc_gate for enforce, report-only, and invalid-value fail-open (product-docs-enforced TEST-014, unit)..."
  local dir="$TEST_DIR/t025-guard-config"
  mkdir -p "$dir"
  local probe="$TEST_DIR/t025-probe.mjs"
  cat > "$probe" <<PROBE
import { readGuardConfig } from '$GUARD_CONFIG_LIB';
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];

fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'product_doc_gate: enforce\n');
let cfg = readGuardConfig(dir, { warn: () => {} });
if (cfg.product_doc_gate !== 'enforce') { console.error('expected enforce, got ' + cfg.product_doc_gate); process.exit(1); }

fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'product_doc_gate: report-only\n');
cfg = readGuardConfig(dir, { warn: () => {} });
if (cfg.product_doc_gate !== 'report-only') { console.error('expected report-only, got ' + cfg.product_doc_gate); process.exit(1); }

let warned = false;
fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'product_doc_gate: bogus\n');
cfg = readGuardConfig(dir, { warn: () => { warned = true; } });
if (cfg.product_doc_gate !== 'report-only') { console.error('expected fail-open report-only for an invalid value, got ' + cfg.product_doc_gate); process.exit(1); }
if (!warned) { console.error('expected a warning callback on an invalid product_doc_gate value'); process.exit(1); }

fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'legacy_until_date: 2020-01-01\n');
cfg = readGuardConfig(dir, { warn: () => {} });
if (cfg.product_doc_gate !== 'report-only') { console.error('expected default report-only when the key is absent, got ' + cfg.product_doc_gate); process.exit(1); }

console.log('OK');
PROBE

  node "$probe" "$dir" > "$TEST_DIR/t025.out" 2>&1 \
    || log_fail "product-docs-enforced TEST-014: guard-config product_doc_gate dial checks failed: $(cat "$TEST_DIR/t025.out")"

  log_pass "guard-config product_doc_gate: enforce / report-only / invalid-fail-open / absent-default all correct (product-docs-enforced TEST-014)"
}

# --- spec-product-docs-capability-model TEST-006 (Spec-AC-03, SEAM-2) -------

test_026_capability_gate_resolves() {
  log_info "Test: close a user_visible ref carrying capability C -> gate resolves docs/product/C.md (not docs/product/<ref>.md) and passes (spec-product-docs-capability-model TEST-006, SEAM-2)..."
  local dir; dir=$(new_fixture_repo "t026")
  write_user_visible_change_doc_with_capability "$dir/docs/issues/CHANGE-0001-t026.md" "t026-slug" "draft" "cap-t026"
  write_capability_product_doc "$dir" "cap-t026"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t026.out" err="$TEST_DIR/t026.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t026-slug --pr 26 --commit c026c026)
  assert_exit "capability-keyed gate resolves + passes" 0 "$code"
  if grep -qi 'product-doc gate' "$err"; then
    log_fail "t026: a real product doc at the CAPABILITY path must not warn/refuse: $(cat "$err")"
  fi
  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t026.md" \
    || log_fail "t026: close did not proceed"
  [[ "$(delivered_by_contains "$dir/docs/product/cap-t026.md" "t026-slug")" == "1" ]] \
    || log_fail "t026: delivered_by must be stamped with the closing ref t026-slug"

  log_pass "Capability-keyed gate resolves docs/product/<capability>.md and passes (spec-product-docs-capability-model TEST-006, SEAM-2)"
}

# --- spec-product-docs-capability-model TEST-007 (Spec-AC-03) --------------

test_027_capability_shared_two_refs() {
  log_info "Test: two refs sharing capability C -> ONE docs/product/C.md, delivered_by carries BOTH refs (spec-product-docs-capability-model TEST-007)..."
  local dir; dir=$(new_fixture_repo "t027")
  write_user_visible_change_doc_with_capability "$dir/docs/issues/CHANGE-0001-t027a.md" "t027a-slug" "draft" "cap-t027"
  write_user_visible_change_doc_with_capability "$dir/docs/issues/CHANGE-0002-t027b.md" "t027b-slug" "draft" "cap-t027"
  write_capability_product_doc "$dir" "cap-t027"
  commit_fixture_docs "$dir"

  local out_a="$TEST_DIR/t027a.out" err_a="$TEST_DIR/t027a.err" code_a
  code_a=$(run_close "$dir" "$out_a" "$err_a" --ref t027a-slug --pr 27 --commit a027a027)
  assert_exit "first close of shared-capability ref A" 0 "$code_a"

  local out_b="$TEST_DIR/t027b.out" err_b="$TEST_DIR/t027b.err" code_b
  code_b=$(run_close "$dir" "$out_b" "$err_b" --ref t027b-slug --pr 27 --commit b027b027)
  assert_exit "second close of shared-capability ref B" 0 "$code_b"

  [[ -f "$dir/docs/product/cap-t027.md" ]] \
    || log_fail "t027: exactly one docs/product/cap-t027.md must exist (no second file spawned)"
  [[ "$(delivered_by_contains "$dir/docs/product/cap-t027.md" "t027a-slug")" == "1" ]] \
    || log_fail "t027: delivered_by must carry ref A (t027a-slug)"
  [[ "$(delivered_by_contains "$dir/docs/product/cap-t027.md" "t027b-slug")" == "1" ]] \
    || log_fail "t027: delivered_by must carry ref B (t027b-slug)"

  log_pass "Two refs sharing one capability update ONE product doc; delivered_by carries both (spec-product-docs-capability-model TEST-007)"
}

# --- spec-product-docs-capability-model TEST-008 (Spec-AC-03) --------------

test_028_delivered_by_byte_idempotent() {
  log_info "Test: delivered_by/updated upsert leaves prose byte-identical; a repeat close of the SAME ref is a no-op (spec-product-docs-capability-model TEST-008)..."
  local dir; dir=$(new_fixture_repo "t028")
  write_user_visible_change_doc_with_capability "$dir/docs/issues/CHANGE-0001-t028.md" "t028-slug" "draft" "cap-t028"
  write_capability_product_doc "$dir" "cap-t028"
  commit_fixture_docs "$dir"
  local prose_before; prose_before=$(sed -n '/^# Fixture Feature/,$p' "$dir/docs/product/cap-t028.md")

  local out1="$TEST_DIR/t028-1.out" err1="$TEST_DIR/t028-1.err" code1
  code1=$(run_close "$dir" "$out1" "$err1" --ref t028-slug --pr 28 --commit d028d028)
  assert_exit "first close stamps delivered_by" 0 "$code1"
  [[ "$(delivered_by_contains "$dir/docs/product/cap-t028.md" "t028-slug")" == "1" ]] \
    || log_fail "t028: the first close must actually append t028-slug to delivered_by (real upsert, not a no-op)"
  local prose_after1; prose_after1=$(sed -n '/^# Fixture Feature/,$p' "$dir/docs/product/cap-t028.md")
  [[ "$prose_before" == "$prose_after1" ]] \
    || log_fail "t028: authored prose (everything from the H1 onward) must be byte-identical after the upsert"
  local content_after1; content_after1=$(cat "$dir/docs/product/cap-t028.md")

  local out2="$TEST_DIR/t028-2.out" err2="$TEST_DIR/t028-2.err" code2
  code2=$(run_close "$dir" "$out2" "$err2" --ref t028-slug --pr 28 --commit d028d028)
  assert_exit "repeat close of the same ref is a no-op" 0 "$code2"
  grep -qF 'nothing to do' "$out2" \
    || log_fail "t028: repeat close must report nothing-to-do: $(cat "$out2")"
  local content_after2; content_after2=$(cat "$dir/docs/product/cap-t028.md")
  [[ "$content_after1" == "$content_after2" ]] \
    || log_fail "t028: repeat close must leave the product doc byte-identical (byte-idempotent)"

  log_pass "delivered_by/updated upsert is byte-idempotent; prose untouched; repeat close is a no-op (spec-product-docs-capability-model TEST-008)"
}

# --- spec-product-docs-capability-model TEST-009 (Spec-AC-03) --------------

test_029_capability_enforce_missing_doc_refuse() {
  log_info "Test: product_doc_gate enforce + missing docs/product/<capability>.md -> exit 3 refuse, preserved under the capability key (spec-product-docs-capability-model TEST-009)..."
  local dir; dir=$(new_fixture_repo "t029")
  set_product_doc_gate_dial "$dir" "enforce"
  write_user_visible_change_doc_with_capability "$dir/docs/issues/CHANGE-0001-t029.md" "t029-slug" "draft" "cap-t029"
  # deliberately do NOT create docs/product/cap-t029.md (and never a
  # docs/product/t029-slug.md either -- the gate must key on the CAPABILITY).
  commit_fixture_docs "$dir"
  cp "$dir/docs/issues/CHANGE-0001-t029.md" "$TEST_DIR/t029-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t029.out" err="$TEST_DIR/t029.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t029-slug --pr 29 --commit e029e029)
  assert_exit "capability-keyed enforce gate refuses" 3 "$code"
  grep -qi 'REFUSED.*product-doc gate' "$err" \
    || log_fail "t029: expected a product-doc-gate REFUSED line on stderr, got: $(cat "$err")"
  grep -qF 'cap-t029' "$err" \
    || log_fail "t029: REFUSED reason must name the CAPABILITY (cap-t029), not the ref: $(cat "$err")"

  diff -q "$TEST_DIR/t029-before.md" "$dir/docs/issues/CHANGE-0001-t029.md" >/dev/null \
    || log_fail "t029: doc was mutated despite a pre-write refusal"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t029: EVENTS.jsonl grew despite a pre-write refusal"

  log_pass "Capability-keyed enforce gate refuses (exit 3) on a missing capability doc; nothing written (spec-product-docs-capability-model TEST-009)"
}

# ===== usage-capture gate (spec-telemetry-completeness, Enforcement design A) =

# TEST-030 (AC-001) — absent dial defaults to report-only: an unmarked
# harness-dispatched run WARNS (naming ref + role) but the close still proceeds.
test_030_usage_gate_report_only_warns() {
  log_info "Test: unmarked harness-role run + absent dial -> report-only WARNING, close proceeds (telemetry-completeness AC-001)..."
  local dir; dir=$(new_fixture_repo "t030")
  # NB: no usage_capture_gate line in docs-audit.yaml -> fail-open report-only.
  write_change_doc "$dir/docs/issues/CHANGE-0001-t030.md" "t030-slug" "draft"
  commit_fixture_docs "$dir"
  state_begin "$dir" "t030-slug"
  state_add_run "$dir" "Implementation" "did the work, forgot the marker"

  local out="$TEST_DIR/t030.out" err="$TEST_DIR/t030.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t030-slug --pr 30 --commit a030a030)
  assert_exit "report-only default proceeds" 0 "$code"
  grep -qi 'WARNING (usage-capture gate)' "$err" \
    || log_fail "t030: expected a usage-capture-gate WARNING on stderr, got: $(cat "$err")"
  grep -qF 'Implementation' "$err" || log_fail "t030: WARNING must name the unmarked role"
  grep -qF 't030-slug' "$err" || log_fail "t030: WARNING must name the ride ref"
  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t030.md" \
    || log_fail "t030: report-only close must still proceed to done"
  log_pass "Absent dial = report-only: WARNS naming ref+role, close proceeds (AC-001)"
}

# TEST-031 (AC-001) — enforce dial refuses BEFORE any write (exit 4); doc bytes,
# EVENTS length, and docs/INDEX.md are all untouched.
test_031_usage_gate_enforce_refuses_pre_write() {
  log_info "Test: unmarked harness-role run + enforce dial -> exit 4 refuse, nothing written (telemetry-completeness AC-001)..."
  local dir; dir=$(new_fixture_repo "t031")
  set_usage_capture_gate_dial "$dir" "enforce"
  write_change_doc "$dir/docs/issues/CHANGE-0001-t031.md" "t031-slug" "draft"
  commit_fixture_docs "$dir"
  state_begin "$dir" "t031-slug"
  state_add_run "$dir" "Validation" "verdict PASS, no usage recorded"
  cp "$dir/docs/issues/CHANGE-0001-t031.md" "$TEST_DIR/t031-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t031.out" err="$TEST_DIR/t031.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t031-slug --pr 31 --commit b031b031)
  assert_exit "enforce gate refuses" 4 "$code"
  grep -qi 'REFUSED (usage-capture gate)' "$err" \
    || log_fail "t031: expected a usage-capture-gate REFUSED line, got: $(cat "$err")"
  grep -qF 'Validation' "$err" || log_fail "t031: REFUSED reason must name the unmarked role"
  diff -q "$TEST_DIR/t031-before.md" "$dir/docs/issues/CHANGE-0001-t031.md" >/dev/null \
    || log_fail "t031: doc mutated despite a pre-write refusal"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t031: EVENTS.jsonl grew despite a pre-write refusal"
  [[ ! -e "$dir/docs/INDEX.md" ]] \
    || log_fail "t031: docs/INDEX.md created despite a pre-write refusal (gate must fire before ANY write)"
  log_pass "Enforce gate: exit 4 refuse, nothing written (doc + EVENTS + INDEX untouched) (AC-001)"
}

# TEST-032 (Constraints escape hatch) — a run recording the honest-gap sentinel
# usage_capture=none passes even under enforce.
test_032_usage_gate_sentinel_passes_enforce() {
  log_info "Test: usage_capture=none sentinel passes under enforce (honest-gap escape hatch)..."
  local dir; dir=$(new_fixture_repo "t032")
  set_usage_capture_gate_dial "$dir" "enforce"
  write_change_doc "$dir/docs/issues/CHANGE-0001-t032.md" "t032-slug" "draft"
  commit_fixture_docs "$dir"
  state_begin "$dir" "t032-slug"
  state_add_run "$dir" "Planning" "harness exposed no usage this run usage_capture=none"

  local out="$TEST_DIR/t032.out" err="$TEST_DIR/t032.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t032-slug --pr 32 --commit c032c032)
  assert_exit "sentinel passes under enforce" 0 "$code"
  if grep -qi 'usage-capture gate' "$err"; then
    log_fail "t032: a usage_capture=none run must not warn/refuse, got: $(cat "$err")"
  fi
  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t032.md" \
    || log_fail "t032: close did not proceed despite an honest-gap sentinel"
  log_pass "Sentinel usage_capture=none passes even under enforce (escape hatch)"
}

# TEST-033 (AC-002) — negative control: a valid marker, decomposed tokens, and a
# meta-role (Orchestration) unmarked run all pass clean under enforce.
test_033_usage_gate_captured_and_metarole_pass() {
  log_info "Test: marked + decomposed + meta-role runs pass clean under enforce (telemetry-completeness AC-002)..."
  local dir; dir=$(new_fixture_repo "t033")
  set_usage_capture_gate_dial "$dir" "enforce"
  write_change_doc "$dir/docs/issues/CHANGE-0001-t033.md" "t033-slug" "draft"
  commit_fixture_docs "$dir"
  state_begin "$dir" "t033-slug"
  state_add_run "$dir" "Planning" "planned it usage_total_tokens=1234"
  state_add_run "$dir" "TDD Implementation" "decomposed run" "500" "700"
  # Orchestration is a meta-role -> never gated even with no marker.
  state_add_run "$dir" "Orchestration" "dispatched next role, no usage"

  local out="$TEST_DIR/t033.out" err="$TEST_DIR/t033.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t033-slug --pr 33 --commit d033d033)
  assert_exit "captured + meta-role runs pass under enforce" 0 "$code"
  if grep -qi 'usage-capture gate' "$err"; then
    log_fail "t033: marked/decomposed/meta-role runs must NOT trip the gate, got: $(cat "$err")"
  fi
  grep -q '^status: done$' "$dir/docs/issues/CHANGE-0001-t033.md" \
    || log_fail "t033: close did not proceed for a fully-captured ride"
  # negative decomposed counts are NOT capture (bot P2): -1/-1 must trip the
  # gate under enforce — a fresh fixture so the earlier clean close cannot mask it.
  local dir2; dir2=$(new_fixture_repo "t033n")
  set_usage_capture_gate_dial "$dir2" "enforce"
  write_change_doc "$dir2/docs/issues/CHANGE-0001-t033n.md" "t033n-slug" "draft"
  commit_fixture_docs "$dir2"
  state_begin "$dir2" "t033n-slug"
  state_add_run "$dir2" "Implementation" "negative counts" "-1" "-1"
  local out2="$TEST_DIR/t033n.out" err2="$TEST_DIR/t033n.err" code2
  code2=$(run_close "$dir2" "$out2" "$err2" --ref t033n-slug --pr 33 --commit f033f033)
  assert_exit "negative tokens_in/out must not count as captured" 4 "$code2"
  log_pass "Marker OR decomposed tokens never trip the gate; meta-roles never gated (AC-002)"
}

# TEST-034 (AC-003) — --dry-run never acts on the gate: no refusal, no write,
# and the verdict is reported informationally in the JSON.
test_034_usage_gate_dry_run_noop() {
  log_info "Test: --dry-run reports the usage-capture verdict but never refuses/writes (telemetry-completeness AC-003)..."
  local dir; dir=$(new_fixture_repo "t034")
  set_usage_capture_gate_dial "$dir" "enforce"
  write_change_doc "$dir/docs/issues/CHANGE-0001-t034.md" "t034-slug" "draft"
  commit_fixture_docs "$dir"
  state_begin "$dir" "t034-slug"
  state_add_run "$dir" "Implementation" "no marker here"
  cp "$dir/docs/issues/CHANGE-0001-t034.md" "$TEST_DIR/t034-before.md"

  local out="$TEST_DIR/t034.out" err="$TEST_DIR/t034.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t034-slug --pr 34 --commit e034e034 --dry-run)
  assert_exit "dry-run never refuses" 0 "$code"
  grep -qF 'usageCaptureGate' "$out" \
    || log_fail "t034: dry-run JSON must carry the usageCaptureGate verdict, got: $(cat "$out")"
  node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); if(j.usageCaptureGate.severity!=="refuse"){console.error("expected severity refuse in dry-run JSON, got "+j.usageCaptureGate.severity);process.exit(1)}' "$out" \
    || log_fail "t034: dry-run must report the would-be refuse verdict"
  diff -q "$TEST_DIR/t034-before.md" "$dir/docs/issues/CHANGE-0001-t034.md" >/dev/null \
    || log_fail "t034: --dry-run mutated the doc"
  [[ ! -e "$dir/docs/INDEX.md" ]] || log_fail "t034: --dry-run wrote docs/INDEX.md"
  log_pass "--dry-run reports the verdict, never refuses/writes (AC-003)"
}

# TEST-035 (AC-006) — guard-config unit: usage_capture_gate enforce /
# report-only / invalid-fail-open (with a stderr notice) / absent-default.
test_035_guard_config_usage_capture_gate_dial() {
  log_info "Test: guard-config readGuardConfig returns usage_capture_gate for enforce/report-only/invalid-fail-open/absent (telemetry-completeness AC-006)..."
  node --input-type=module > "$TEST_DIR/t035.out" 2>&1 <<NODE || log_fail "telemetry-completeness AC-006: guard-config usage_capture_gate checks failed: $(cat "$TEST_DIR/t035.out")"
import { readGuardConfig, GUARD_DIALS } from '${GUARD_CONFIG_LIB}';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
if (!GUARD_DIALS.includes('usage_capture_gate')) { console.error('GUARD_DIALS must list usage_capture_gate'); process.exit(1); }
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ucg-'));
fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'usage_capture_gate: enforce\n');
if (readGuardConfig(dir).usage_capture_gate !== 'enforce') { console.error('expected enforce'); process.exit(1); }
fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'usage_capture_gate: report-only\n');
if (readGuardConfig(dir).usage_capture_gate !== 'report-only') { console.error('expected report-only'); process.exit(1); }
let warned = false;
fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'usage_capture_gate: enforced\n');
if (readGuardConfig(dir, { warn: () => { warned = true; } }).usage_capture_gate !== 'report-only') { console.error('expected fail-open report-only for invalid value'); process.exit(1); }
if (!warned) { console.error('expected a stderr notice on an invalid value'); process.exit(1); }
fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'legacy_until_date: 2020-01-01\n');
if (readGuardConfig(dir).usage_capture_gate !== 'report-only') { console.error('expected default report-only when the key is absent'); process.exit(1); }
console.log('ok');
NODE
  grep -qF 'ok' "$TEST_DIR/t035.out" || log_fail "t035: guard-config usage_capture_gate assertions did not all pass: $(cat "$TEST_DIR/t035.out")"
  log_pass "guard-config usage_capture_gate: enforce/report-only/invalid-fail-open/absent-default all correct (AC-006)"
}

# ===== evidence-path gate (CHANGE-0131 / spec-evidence-path-gate) ============
#
# The close-time gate that catches a spec's AC Status Evidence cell citing a
# docs/ai/tdd/... transcript that resolves only inside a deleted worktree
# (the CHANGE-0127 incident). Six-rule extraction grammar in
# .aai/scripts/lib/evidence-paths.mjs (D2), a fail-open GUARD_DIALS dial
# (D7), placed BEFORE readEvents/regenerateIndex (D8, exit code 5).

# TEST-036 (Spec-AC-01) — extractEvidencePaths: one real citation extracts
# clean; every hostile prose shape (test-id ranges, slash commands, absolute
# paths, URLs, line-number citations, globs, brace expansions, digests, run
# IDs, backtick-glued joins, and the SPEC-0114 ellipsis abbreviation) yields
# nothing. Pure unit test — no close invocation.
test_036_evidence_path_extraction_grammar() {
  log_info "Test: extractEvidencePaths — six-rule grammar over a hostile corpus (Spec-AC-01)..."
  local lib="$PROJECT_ROOT/.aai/scripts/lib/evidence-paths.mjs"
  EVIDENCE_LIB="$lib" EVIDENCE_ROOT="$PROJECT_ROOT" node --input-type=module > "$TEST_DIR/t036.out" 2>&1 <<'NODE' || log_fail "TEST-036: extraction-grammar assertions failed: $(cat "$TEST_DIR/t036.out")"
const { extractEvidencePaths } = await import(process.env.EVIDENCE_LIB);
const root = process.env.EVIDENCE_ROOT;
function eq(desc, got, want) {
  if (JSON.stringify(got) !== JSON.stringify(want)) {
    console.error(desc + ': got ' + JSON.stringify(got) + ' want ' + JSON.stringify(want));
    process.exit(1);
  }
}
eq('clean citation with trailing comma+paren',
  extractEvidencePaths('see (docs/ai/tdd/green-example.log),', root),
  ['docs/ai/tdd/green-example.log']);
eq('TEST-id range', extractEvidencePaths('TEST-001/002', root), []);
eq('dotdot traversal segment skips (D2 rule 5)', extractEvidencePaths('docs/../etc/passwd and ../../etc/passwd', root), []);
eq('prose A/B', extractEvidencePaths('A/B', root), []);
eq('slash command', extractEvidencePaths('/aai-release', root), []);
eq('absolute bin', extractEvidencePaths('/bin/bash', root), []);
eq('https URL', extractEvidencePaths('https://github.com/goodwind-cz/aai/actions/runs/30289358425', root), []);
eq('line-number citation', extractEvidencePaths('.aai/scripts/lib/docs-audit-core.mjs:591', root), []);
eq('star glob', extractEvidencePaths('docs/ai/reports/test-canon-coverage-*.md', root), []);
eq('brace expansion', extractEvidencePaths('docs/ai/tdd/green-...-TEST-00{1..5}.log', root), []);
eq('sha256 digest', extractEvidencePaths('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b8', root), []);
eq('run id', extractEvidencePaths('30289358425', root), []);
eq('backtick-glued join', extractEvidencePaths('`test-aai-state.sh`/`test-aai-layer-profiles.sh`', root), []);
eq('SPEC-0114 ellipsis abbreviation', extractEvidencePaths('docs/ai/tdd/red-...test_011/012/014...log', root), []);
console.log('ok');
NODE
  grep -qF 'ok' "$TEST_DIR/t036.out" || log_fail "TEST-036: extraction-grammar assertions failed: $(cat "$TEST_DIR/t036.out")"
  log_pass "extractEvidencePaths: accepts one clean citation, rejects every hostile shape (Spec-AC-01)"
}

# TEST-037 (Spec-AC-02) — grep contract: the lib imports parseAcTable +
# parseLeanAcTable from lib/docs-model.mjs and declares no local
# heading-regex; behavioral: zero citations for a table-less doc, non-zero
# for a lean L1 table carrying an Evidence column.
test_037_evidence_paths_shared_parser_contract() {
  log_info "Test: evidence-paths.mjs reuses ONLY the shared AC-table readers, no forked heading regex (Spec-AC-02)..."
  local lib="$PROJECT_ROOT/.aai/scripts/lib/evidence-paths.mjs"
  [[ -f "$lib" ]] || log_fail "missing $lib (RED until CHANGE-0131 lands)"
  grep -qF "parseAcTable" "$lib" || log_fail "TEST-037: lib must import parseAcTable from lib/docs-model.mjs"
  grep -qF "parseLeanAcTable" "$lib" || log_fail "TEST-037: lib must import parseLeanAcTable from lib/docs-model.mjs"
  grep -qE "docs-model\.mjs" "$lib" || log_fail "TEST-037: lib must import from lib/docs-model.mjs, not re-declare a reader"
  if grep -qF "Acceptance Criteria Status" "$lib"; then
    log_fail "TEST-037: lib must declare no local 'Acceptance Criteria Status' heading regex — S2, no fourth table parser"
  fi

  EVIDENCE_LIB="$lib" node --input-type=module > "$TEST_DIR/t037.out" 2>&1 <<'NODE' || log_fail "TEST-037: shared-parser behavioral assertions failed: $(cat "$TEST_DIR/t037.out")"
const { evidenceCitations } = await import(process.env.EVIDENCE_LIB);
const noTable = '# Doc\n\nno AC table here.\n';
const noTableResult = evidenceCitations(noTable, process.cwd());
if (noTableResult.length !== 0) { console.error('table-less doc must yield zero citations, got ' + JSON.stringify(noTableResult)); process.exit(1); }

const lean = [
  '---',
  'id: t037-lean',
  'type: change',
  'status: implementing',
  '---',
  '',
  '## Acceptance Criteria Status',
  '',
  '| Spec-AC    | Status | Evidence |',
  '|------------|--------|----------|',
  '| Spec-AC-01 | done   | docs/ai/tdd/green-t037.log |',
  '',
].join('\n');
const leanResult = evidenceCitations(lean, process.cwd());
if (leanResult.length === 0) { console.error('lean L1 table with an Evidence column must yield a non-empty result'); process.exit(1); }
console.log('ok');
NODE
  grep -qF 'ok' "$TEST_DIR/t037.out" || log_fail "TEST-037: shared-parser behavioral assertions failed: $(cat "$TEST_DIR/t037.out")"
  log_pass "evidence-paths.mjs reuses parseAcTable/parseLeanAcTable exclusively, declares no local heading regex (Spec-AC-02)"
}

# TEST-038 (Spec-AC-03) — guard-config unit: evidence_path_gate enforce /
# report-only / invalid-fail-open (with a stderr notice) / absent-default;
# plus the shipped docs-audit.yaml carries exactly one column-0 line.
test_038_guard_config_evidence_path_gate_dial() {
  log_info "Test: guard-config readGuardConfig returns evidence_path_gate for enforce/report-only/invalid-fail-open/absent (Spec-AC-03)..."
  node --input-type=module > "$TEST_DIR/t038.out" 2>&1 <<NODE || log_fail "Spec-AC-03: guard-config evidence_path_gate checks failed: $(cat "$TEST_DIR/t038.out")"
import { readGuardConfig, GUARD_DIALS } from '${GUARD_CONFIG_LIB}';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
if (!GUARD_DIALS.includes('evidence_path_gate')) { console.error('GUARD_DIALS must list evidence_path_gate'); process.exit(1); }
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'epg-'));
fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'evidence_path_gate: enforce\n');
if (readGuardConfig(dir).evidence_path_gate !== 'enforce') { console.error('expected enforce'); process.exit(1); }
fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'evidence_path_gate: report-only\n');
if (readGuardConfig(dir).evidence_path_gate !== 'report-only') { console.error('expected report-only'); process.exit(1); }
let warned = false;
fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'evidence_path_gate: enforced\n');
if (readGuardConfig(dir, { warn: () => { warned = true; } }).evidence_path_gate !== 'report-only') { console.error('expected fail-open report-only for invalid value'); process.exit(1); }
if (!warned) { console.error('expected a stderr notice on an invalid value'); process.exit(1); }
fs.writeFileSync(path.join(dir, 'docs-audit.yaml'), 'legacy_until_date: 2020-01-01\n');
if (readGuardConfig(dir).evidence_path_gate !== 'report-only') { console.error('expected default report-only when the key is absent'); process.exit(1); }
console.log('ok');
NODE
  grep -qF 'ok' "$TEST_DIR/t038.out" || log_fail "t038: guard-config evidence_path_gate assertions did not all pass: $(cat "$TEST_DIR/t038.out")"

  local n
  n="$(grep -c -- '^evidence_path_gate: report-only$' "$PROJECT_ROOT/docs/ai/docs-audit.yaml" || true)"
  [[ "$n" == "1" ]] || log_fail "t038: expected exactly one column-0 'evidence_path_gate: report-only' line in the shipped docs-audit.yaml, got $n"

  log_pass "guard-config evidence_path_gate: enforce/report-only/invalid-fail-open/absent-default all correct; shipped dial documented (Spec-AC-03)"
}

# TEST-039 (Spec-AC-04) — absent dial defaults to report-only: one absent +
# one present evidence path WARNS (naming the doc, the absent path, the
# Spec-AC row id — NOT the resolvable path) but the close still proceeds.
test_039_evidence_gate_report_only_warns() {
  log_info "Test: one absent + one present evidence path, no dial line -> report-only WARNING, close proceeds (Spec-AC-04)..."
  local dir; dir=$(new_fixture_repo "t039")
  # NB: no evidence_path_gate line in docs-audit.yaml -> fail-open report-only.
  write_change_doc "$dir/docs/issues/CHANGE-0001-t039.md" "t039-change-slug" "draft"
  mkdir -p "$dir/docs/ai/tdd"
  : > "$dir/docs/ai/tdd/green-t039.log"
  write_spec_doc "$dir/docs/specs/SPEC-0001-t039.md" "t039-spec-slug" "implementing" "done" "docs/ai/tdd/green-t039.log docs/ai/tdd/red-t039-missing.log"
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t039.out" err="$TEST_DIR/t039.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t039-change-slug --spec t039-spec-slug --pr 39 --commit a039a039)
  assert_exit "report-only default proceeds" 0 "$code"
  grep -q -- 'WARNING (evidence-path gate)' "$err" \
    || log_fail "t039: expected an evidence-path-gate WARNING on stderr, got: $(cat "$err")"
  grep -qF 'docs/ai/tdd/red-t039-missing.log' "$err" \
    || log_fail "t039: WARNING must name the unresolvable path"
  grep -qF 'SPEC-0001-t039.md' "$err" \
    || log_fail "t039: WARNING must name the doc"
  grep -qF 'Spec-AC-01' "$err" \
    || log_fail "t039: WARNING must name the Spec-AC row id"
  if grep -qF 'docs/ai/tdd/green-t039.log' "$err"; then
    log_fail "t039: WARNING must NOT name the resolvable path, got: $(cat "$err")"
  fi
  grep -q '^status: done$' "$dir/docs/specs/SPEC-0001-t039.md" \
    || log_fail "t039: report-only close must still proceed to done"
  log_pass "Absent dial = report-only: WARNS naming the doc, the AC row and the absent path only, close proceeds (Spec-AC-04)"
}

# TEST-040 (Spec-AC-05) — enforce refuses BEFORE any write (exit 5); doc
# bytes, EVENTS length, and docs/INDEX.md are all untouched (S1).
test_040_evidence_gate_enforce_refuses_pre_write() {
  log_info "Test: same fixture under enforce -> exit 5 REFUSED, nothing written, docs/INDEX.md never created (Spec-AC-05)..."
  local dir; dir=$(new_fixture_repo "t040")
  set_evidence_path_gate_dial "$dir" "enforce"
  write_change_doc "$dir/docs/issues/CHANGE-0001-t040.md" "t040-change-slug" "draft"
  mkdir -p "$dir/docs/ai/tdd"
  : > "$dir/docs/ai/tdd/green-t040.log"
  write_spec_doc "$dir/docs/specs/SPEC-0001-t040.md" "t040-spec-slug" "implementing" "done" "docs/ai/tdd/green-t040.log docs/ai/tdd/red-t040-missing.log"
  commit_fixture_docs "$dir"
  cp "$dir/docs/issues/CHANGE-0001-t040.md" "$TEST_DIR/t040-change-before.md"
  cp "$dir/docs/specs/SPEC-0001-t040.md" "$TEST_DIR/t040-spec-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t040.out" err="$TEST_DIR/t040.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t040-change-slug --spec t040-spec-slug --pr 40 --commit b040b040)
  assert_exit "enforce gate refuses" 5 "$code"
  grep -q -- 'REFUSED (evidence-path gate)' "$err" \
    || log_fail "t040: expected an evidence-path-gate REFUSED line, got: $(cat "$err")"
  grep -qF 'docs/ai/tdd/red-t040-missing.log' "$err" \
    || log_fail "t040: REFUSED reason must name the unresolvable path"
  diff -q "$TEST_DIR/t040-change-before.md" "$dir/docs/issues/CHANGE-0001-t040.md" >/dev/null \
    || log_fail "t040: change doc mutated despite a pre-write refusal"
  diff -q "$TEST_DIR/t040-spec-before.md" "$dir/docs/specs/SPEC-0001-t040.md" >/dev/null \
    || log_fail "t040: spec doc mutated despite a pre-write refusal"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t040: EVENTS.jsonl grew despite a pre-write refusal"
  [[ ! -e "$dir/docs/INDEX.md" ]] \
    || log_fail "t040: docs/INDEX.md created despite a pre-write refusal (gate must fire before ANY write)"
  log_pass "Enforce gate: exit 5 refuse, nothing written (doc + EVENTS + INDEX untouched) (Spec-AC-05)"
}

# TEST-041 (Spec-AC-06) — existence, not tracking (D4): a gitignored-but-
# present file and an existing directory pass under enforce; deleting only
# the gitignored file flips the SAME close to refuse.
test_041_evidence_gate_existence_not_tracking() {
  log_info "Test: existence not tracking — gitignored-but-present file + existing dir pass; deleting the file alone flips to refuse (Spec-AC-06)..."
  local dir; dir=$(new_fixture_repo "t041")
  set_evidence_path_gate_dial "$dir" "enforce"
  printf 'docs/ai/tdd/\n' >> "$dir/.gitignore"
  write_change_doc "$dir/docs/issues/CHANGE-0001-t041.md" "t041-change-slug" "draft"
  mkdir -p "$dir/docs/ai/tdd"
  : > "$dir/docs/ai/tdd/green-t041.log"
  write_spec_doc "$dir/docs/specs/SPEC-0001-t041.md" "t041-spec-slug" "implementing" "done" "docs/ai/tdd/green-t041.log docs/specs"
  commit_fixture_docs "$dir"
  git -C "$dir" check-ignore -v "docs/ai/tdd/green-t041.log" >/dev/null \
    || log_fail "t041: fixture setup error — docs/ai/tdd/green-t041.log must be gitignored"

  local out1="$TEST_DIR/t041a.out" err1="$TEST_DIR/t041a.err" code1
  code1=$(run_close "$dir" "$out1" "$err1" --ref t041-change-slug --spec t041-spec-slug --pr 41 --commit c041c041)
  assert_exit "gitignored-but-present file + directory pass under enforce" 0 "$code1"
  if grep -qi -- 'evidence-path gate' "$err1"; then
    log_fail "t041: a present (gitignored) file and an existing directory must not trip the gate, got: $(cat "$err1")"
  fi

  rm -f "$dir/docs/ai/tdd/green-t041.log"
  local out2="$TEST_DIR/t041b.out" err2="$TEST_DIR/t041b.err" code2
  code2=$(run_close "$dir" "$out2" "$err2" --ref t041-change-slug --spec t041-spec-slug --pr 41 --commit c041c041)
  assert_exit "deleting the gitignored file alone flips to refuse" 5 "$code2"
  grep -qF 'docs/ai/tdd/green-t041.log' "$err2" \
    || log_fail "t041: second (post-delete) REFUSED reason must name the now-missing path"

  log_pass "Existence, not tracking: gitignored-but-present + directory pass; deleting the file alone refuses (Spec-AC-06, D4)"
}

# TEST-042 (Spec-AC-07) — the intake hard requirement: Evidence cells holding
# ONLY hostile prose shapes never trip the gate, even under enforce.
test_042_evidence_gate_prose_never_refuses() {
  log_info "Test: Evidence cells holding ONLY hostile prose shapes never trip the gate, even under enforce (Spec-AC-07)..."
  local dir; dir=$(new_fixture_repo "t042")
  set_evidence_path_gate_dial "$dir" "enforce"
  write_change_doc "$dir/docs/issues/CHANGE-0001-t042.md" "t042-change-slug" "draft"
  cat > "$dir/docs/specs/SPEC-0001-t042.md" <<'EOF'
---
id: t042-spec-slug
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: null
  rfc: null
  pr: []
  commits: []
---

# SPEC — Fixture t042-spec-slug

SPEC-FROZEN: true

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|--------------|--------|----------|-----------|-------|
| Spec-AC-01 | fixture      | done   | TEST-001/002, see run 30289358425 | — | — |
| Spec-AC-02 | fixture      | done   | /aai-release and /bin/bash        | — | — |
| Spec-AC-03 | fixture      | done   | .aai/scripts/lib/docs-audit-core.mjs:591 | — | — |

## Test Plan

| Test ID  | Spec-AC    | Type | File path | Description | Status |
|----------|------------|------|-----------|--------------|--------|
| TEST-001 | Spec-AC-01 | unit | n/a       | fixture      | green  |
EOF
  commit_fixture_docs "$dir"

  local out="$TEST_DIR/t042.out" err="$TEST_DIR/t042.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t042-change-slug --spec t042-spec-slug --pr 42 --commit e042e042)
  assert_exit "prose-only evidence never refuses under enforce" 0 "$code"
  if grep -qi -- 'evidence-path gate' "$err"; then
    log_fail "t042: hostile prose-only Evidence cells must never emit a gate line, got: $(cat "$err")"
  fi
  grep -q '^status: done$' "$dir/docs/specs/SPEC-0001-t042.md" \
    || log_fail "t042: close did not proceed"
  log_pass "Hostile prose shapes (test-id ranges, slash commands, line-number citations) never trip the gate, even under enforce (Spec-AC-07)"
}

# TEST-043 (Spec-AC-08) — --dry-run under enforce against an unresolvable
# citation: exit 0, evidencePathGate JSON verdict names the path, nothing written.
test_043_evidence_gate_dry_run_noop() {
  log_info "Test: --dry-run reports the evidence-path verdict but never refuses/writes (Spec-AC-08)..."
  local dir; dir=$(new_fixture_repo "t043")
  set_evidence_path_gate_dial "$dir" "enforce"
  write_change_doc "$dir/docs/issues/CHANGE-0001-t043.md" "t043-change-slug" "draft"
  write_spec_doc "$dir/docs/specs/SPEC-0001-t043.md" "t043-spec-slug" "implementing" "done" "docs/ai/tdd/red-t043-missing.log"
  commit_fixture_docs "$dir"
  cp "$dir/docs/specs/SPEC-0001-t043.md" "$TEST_DIR/t043-before.md"
  local events_before; events_before=$(file_size "$dir/docs/ai/EVENTS.jsonl")

  local out="$TEST_DIR/t043.out" err="$TEST_DIR/t043.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t043-change-slug --spec t043-spec-slug --pr 43 --commit f043f043 --dry-run)
  assert_exit "dry-run never refuses" 0 "$code"
  grep -qF 'evidencePathGate' "$out" \
    || log_fail "t043: dry-run JSON must carry the evidencePathGate verdict, got: $(cat "$out")"
  node -e 'const j=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); if(j.evidencePathGate.severity!=="refuse"){console.error("expected severity refuse in dry-run JSON, got "+j.evidencePathGate.severity);process.exit(1)}; const s=JSON.stringify(j.evidencePathGate); if(!s.includes("docs/ai/tdd/red-t043-missing.log")){console.error("expected the unresolvable path listed in evidencePathGate, got "+s);process.exit(1)}' "$out" \
    || log_fail "t043: dry-run must report the would-be refuse verdict naming the unresolvable path"
  diff -q "$TEST_DIR/t043-before.md" "$dir/docs/specs/SPEC-0001-t043.md" >/dev/null \
    || log_fail "t043: --dry-run mutated the doc"
  [[ "$(file_size "$dir/docs/ai/EVENTS.jsonl")" == "$events_before" ]] \
    || log_fail "t043: --dry-run grew EVENTS.jsonl"
  [[ ! -e "$dir/docs/INDEX.md" ]] || log_fail "t043: --dry-run wrote docs/INDEX.md"
  log_pass "--dry-run reports the evidence-path verdict, never refuses/writes (Spec-AC-08)"
}

# TEST-046 (PR #245 Codex P1 / CHANGE-0127 regression) — the evidence-path
# gate must resolve cited paths against the MAIN checkout, never against
# process.cwd(), because SKILL_PR step 5c runs close-work-item FROM a linked
# git worktree. Resolving against cwd there lets worktree-stranded evidence
# resolve "fine" and silently defeats the gate's whole purpose. Two docs in
# ONE fixture, closed from ONE linked worktree: doc A's evidence exists ONLY
# in the worktree (must WARN — absent from the main tree); doc B's evidence
# (the control) exists ONLY in the main tree, created AFTER the worktree
# exists so it cannot leak into it (must NOT warn — present in the main
# tree). A third pass checks the dry-run JSON's evidencePathGate carries a
# resolutionRoot naming the main tree, not the worktree.
test_046_evidence_gate_worktree_resolves_against_main_tree() {
  log_info "Test: evidence-path gate resolves cited paths against the MAIN checkout, not a linked worktree's cwd (PR #245 Codex P1 / CHANGE-0127)..."
  local dir; dir=$(new_fixture_repo "t046")

  # Doc A: evidence path that will exist ONLY inside the worktree.
  write_change_doc "$dir/docs/issues/CHANGE-0001-t046a.md" "t046a-change-slug" "draft"
  write_spec_doc "$dir/docs/specs/SPEC-0001-t046a.md" "t046a-spec-slug" "implementing" "done" "docs/ai/tdd/red-t046a-worktree-only.log"

  # Doc B (control): evidence path that will exist ONLY in the main tree.
  write_change_doc "$dir/docs/issues/CHANGE-0002-t046b.md" "t046b-change-slug" "draft"
  write_spec_doc "$dir/docs/specs/SPEC-0002-t046b.md" "t046b-spec-slug" "implementing" "done" "docs/ai/tdd/green-t046b-maintree-only.log"
  commit_fixture_docs "$dir"

  # Spin up a linked worktree off the fixture's HEAD — the exact shape
  # SKILL_PR step 5c runs a scope close from.
  local wt="$TEST_DIR/t046-wt"
  git -C "$dir" worktree add -q -b t046-wt-branch "$wt" HEAD \
    || log_fail "t046: fixture setup error — could not create a linked worktree"

  # Doc A's evidence: created ONLY inside the worktree.
  mkdir -p "$wt/docs/ai/tdd"
  : > "$wt/docs/ai/tdd/red-t046a-worktree-only.log"
  [[ ! -e "$dir/docs/ai/tdd/red-t046a-worktree-only.log" ]] \
    || log_fail "t046: fixture setup error — worktree-only evidence leaked into the main tree"

  # Doc B's evidence: created ONLY in the main tree, AFTER the worktree
  # already exists, so it cannot appear in the worktree's own working copy.
  mkdir -p "$dir/docs/ai/tdd"
  : > "$dir/docs/ai/tdd/green-t046b-maintree-only.log"
  [[ ! -e "$wt/docs/ai/tdd/green-t046b-maintree-only.log" ]] \
    || log_fail "t046: fixture setup error — main-tree evidence leaked into the worktree"

  # Close doc A FROM the worktree, report-only (no dial line -> default):
  # its evidence does not exist in the main tree -> must WARN.
  local outA="$TEST_DIR/t046a.out" errA="$TEST_DIR/t046a.err" codeA
  codeA=$(run_close "$wt" "$outA" "$errA" --ref t046a-change-slug --spec t046a-spec-slug --pr 46 --commit a046a046)
  assert_exit "worktree-stranded evidence: report-only proceeds" 0 "$codeA"
  grep -q -- 'WARNING (evidence-path gate)' "$errA" \
    || log_fail "t046: worktree-only evidence must WARN when resolved against the main tree (absent there), got: $(cat "$errA")"
  grep -qF 'docs/ai/tdd/red-t046a-worktree-only.log' "$errA" \
    || log_fail "t046: WARNING must name the worktree-stranded path"

  # Close doc B FROM the SAME worktree: its evidence exists only in the main
  # tree -> resolving against the main tree must find it -> must NOT warn.
  local outB="$TEST_DIR/t046b.out" errB="$TEST_DIR/t046b.err" codeB
  codeB=$(run_close "$wt" "$outB" "$errB" --ref t046b-change-slug --spec t046b-spec-slug --pr 46 --commit b046b046)
  assert_exit "main-tree evidence: report-only proceeds" 0 "$codeB"
  if grep -qi -- 'evidence-path gate' "$errB"; then
    log_fail "t046: main-tree evidence must resolve cleanly (no gate line) when closed from a worktree, got: $(cat "$errB")"
  fi

  # --dry-run from the worktree must report a resolutionRoot naming the main
  # tree (not the worktree) — the resolution root made observable (Codex P1).
  local dir_real wt_real
  dir_real=$(cd "$dir" && pwd -P)
  wt_real=$(cd "$wt" && pwd -P)
  local outC="$TEST_DIR/t046c.out" errC="$TEST_DIR/t046c.err" codeC
  codeC=$(run_close "$wt" "$outC" "$errC" --ref t046a-change-slug --spec t046a-spec-slug --pr 46 --commit a046a046 --dry-run)
  assert_exit "dry-run never refuses" 0 "$codeC"
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const root = j.evidencePathGate && j.evidencePathGate.resolutionRoot;
    if (!root) { console.error("expected evidencePathGate.resolutionRoot in the dry-run JSON"); process.exit(1); }
    if (root !== process.argv[2]) { console.error("expected resolutionRoot " + process.argv[2] + ", got " + root); process.exit(1); }
    if (root === process.argv[3]) { console.error("resolutionRoot must NOT be the worktree cwd"); process.exit(1); }
  ' "$outC" "$dir_real" "$wt_real" \
    || log_fail "t046: dry-run resolutionRoot must name the main checkout, not the worktree cwd"

  log_pass "Evidence-path gate resolves against the main checkout from a linked worktree: worktree-only evidence warns, main-tree evidence resolves clean, resolutionRoot observable (PR #245 Codex P1 / CHANGE-0127)"
}

# --- TEST-001 (Spec-AC-01, role-verification-guards G1): post-merge-close --

test_047_post_merge_close_warns_once() {
  log_info "Test: G1 post-merge-close warning fires exactly once, incl. on a pair-close (TEST-001)..."

  # Single-ref merged-order fixture: the delivery commit is pushed to
  # origin/main BEFORE close runs.
  local dir; dir=$(new_fixture_repo_with_remote "t047a")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t047a.md" "t047a-slug" "draft"
  commit_fixture_docs "$dir"
  local sha; sha=$(git -C "$dir" rev-parse HEAD)
  push_head_to_origin_main "$dir"

  local out="$TEST_DIR/t047a.out" err="$TEST_DIR/t047a.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t047a-slug --pr 47 --commit "$sha")
  assert_exit "merged-order close still succeeds" 0 "$code"
  [[ "$(grep -c post-merge-close "$err" || true)" -eq 1 ]] \
    || log_fail "t047a: expected exactly one post-merge-close line, got: $(cat "$err")"
  grep -qF "$sha" "$err" || log_fail "t047a: post-merge-close line must name the delivery sha"
  grep -qF "PR #47" "$err" || log_fail "t047a: post-merge-close line must name the PR number"
  grep -qF "origin/main" "$err" || log_fail "t047a: post-merge-close line must name the resolved upstream ref"

  # Pair-close: --ref + --spec in ONE invocation must still print exactly one
  # line (D1 — emitted ONCE PER INVOCATION, never once per ref).
  local dir2; dir2=$(new_fixture_repo_with_remote "t047b")
  write_change_doc "$dir2/docs/issues/CHANGE-0001-t047b.md" "t047b-change-slug" "draft"
  write_spec_doc "$dir2/docs/specs/SPEC-0001-t047b.md" "t047b-spec-slug" "implementing"
  commit_fixture_docs "$dir2"
  local sha2; sha2=$(git -C "$dir2" rev-parse HEAD)
  push_head_to_origin_main "$dir2"

  local out2="$TEST_DIR/t047b.out" err2="$TEST_DIR/t047b.err" code2
  code2=$(run_close "$dir2" "$out2" "$err2" --ref t047b-change-slug --spec t047b-spec-slug --pr 48 --commit "$sha2")
  assert_exit "merged-order pair-close still succeeds" 0 "$code2"
  [[ "$(grep -c post-merge-close "$err2" || true)" -eq 1 ]] \
    || log_fail "t047b: pair-close must still print exactly ONE post-merge-close line, got: $(cat "$err2")"

  log_pass "G1 post-merge-close warning fires exactly once per invocation, single-ref and pair-close alike (TEST-001)"
}

# --- TEST-002 (Spec-AC-01, role-verification-guards G1): negative controls -

test_048_post_merge_close_negative_controls() {
  log_info "Test: G1 negative controls — open-PR order and no-remote both print zero lines (TEST-002)..."

  # Open-PR-order: origin/main carries only the init commit; the delivery
  # commit exists ONLY on the local fixture, never pushed.
  local dir; dir=$(new_fixture_repo_with_remote "t048a")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t048a.md" "t048a-slug" "draft"
  commit_fixture_docs "$dir"
  local sha; sha=$(git -C "$dir" rev-parse HEAD)

  local out="$TEST_DIR/t048a.out" err="$TEST_DIR/t048a.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t048a-slug --pr 1 --commit "$sha")
  assert_exit "open-PR-order close succeeds" 0 "$code"
  [[ "$(grep -c post-merge-close "$err" || true)" -eq 0 ]] \
    || log_fail "t048a: open-PR-order fixture must print zero post-merge-close lines, got: $(cat "$err")"

  # No remote at all: resolveUpstreamDefaultRef must fail closed to silence,
  # never an error.
  local dir2; dir2=$(new_fixture_repo "t048b")
  write_change_doc "$dir2/docs/issues/CHANGE-0001-t048b.md" "t048b-slug" "draft"
  commit_fixture_docs "$dir2"
  local sha2; sha2=$(git -C "$dir2" rev-parse HEAD)

  local out2="$TEST_DIR/t048b.out" err2="$TEST_DIR/t048b.err" code2
  code2=$(run_close "$dir2" "$out2" "$err2" --ref t048b-slug --pr 2 --commit "$sha2")
  assert_exit "no-remote close succeeds" 0 "$code2"
  [[ "$(grep -c post-merge-close "$err2" || true)" -eq 0 ]] \
    || log_fail "t048b: no-remote fixture must print zero post-merge-close lines, got: $(cat "$err2")"

  # --dry-run: even on a MERGED-ORDER fixture (would otherwise warn), the
  # advisory is suppressed -- --dry-run already reports everything
  # informationally in its own JSON, matching the three pre-existing gates
  # beside it (Spec-AC-01 dry-run carve-out, validation-20260816T131500Z N7).
  local dir3; dir3=$(new_fixture_repo_with_remote "t048c")
  write_change_doc "$dir3/docs/issues/CHANGE-0001-t048c.md" "t048c-slug" "draft"
  commit_fixture_docs "$dir3"
  local sha3; sha3=$(git -C "$dir3" rev-parse HEAD)
  push_head_to_origin_main "$dir3"

  local out3="$TEST_DIR/t048c.out" err3="$TEST_DIR/t048c.err" code3
  code3=$(run_close "$dir3" "$out3" "$err3" --ref t048c-slug --pr 3 --commit "$sha3" --dry-run)
  assert_exit "merged-order --dry-run close succeeds" 0 "$code3"
  [[ "$(grep -c post-merge-close "$err3" || true)" -eq 0 ]] \
    || log_fail "t048c: --dry-run on a merged-order fixture must print zero post-merge-close lines, got: $(cat "$err3")"

  log_pass "G1 negative controls: open-PR order, no-remote and --dry-run (even merged-order) all silent (TEST-002)"
}

# --- TEST-003 (Spec-AC-02, role-verification-guards G1): report-only proof -

test_049_post_merge_close_report_only() {
  log_info "Test: G1 changes neither exit code nor stdout, on the warning path or the silent path (TEST-003)..."

  # Build ONE merged-order fixture, then literally COPY it (the whole
  # working tree, .git included, so the delivery commit sha is byte-for-byte
  # identical in both copies) before either copy is closed. One copy is
  # closed with the PRE-CHANGE close-work-item.mjs (the PRE_G1_CLOSE_WORK_ITEM_BLOB
  # pinned blob sha, NOT HEAD-relative -- N4/B2: HEAD IS the post-change tree
  # from this scope's delivery commit onward); the other with the real,
  # post-change script under test. Same docs, same ref/pr/commit -> stdout
  # and exit code must be byte-identical; only stderr may differ.
  local base; base=$(new_fixture_repo_with_remote "t049")
  write_change_doc "$base/docs/issues/CHANGE-0001-t049.md" "t049-slug" "draft"
  commit_fixture_docs "$base"
  local sha; sha=$(git -C "$base" rev-parse HEAD)
  push_head_to_origin_main "$base"

  local pre_dir="$TEST_DIR/t049-pre" post_dir="$TEST_DIR/t049-post"
  cp -r "$base" "$pre_dir"
  cp -r "$base" "$post_dir"

  # The pre-change script needs its sibling lib/ modules to resolve (none of
  # which this scope touches), so extract close-work-item.mjs alone from the
  # PRE_G1_CLOSE_WORK_ITEM_BLOB pinned blob (N4/B2: never HEAD-relative) into
  # a scratch scripts/ directory carrying a copy of the CURRENT (unmodified)
  # lib/ tree.
  local pre_script; pre_script=$(pre_change_close_script)

  local pre_out="$TEST_DIR/t049-pre.out" pre_err="$TEST_DIR/t049-pre.err" pre_code
  pre_code=0
  ( cd "$pre_dir" && node "$pre_script" --ref t049-slug --pr 49 --commit "$sha" > "$pre_out" 2> "$pre_err" ) || pre_code=$?

  local post_out="$TEST_DIR/t049-post.out" post_err="$TEST_DIR/t049-post.err" post_code
  post_code=$(run_close "$post_dir" "$post_out" "$post_err" --ref t049-slug --pr 49 --commit "$sha")

  assert_exit "pre-change close succeeds" 0 "$pre_code"
  assert_exit "post-change close succeeds identically" "$pre_code" "$post_code"
  cmp -s "$pre_out" "$post_out" \
    || log_fail "t049: stdout must be byte-identical pre- and post-G1, pre=[$(cat "$pre_out")] post=[$(cat "$post_out")]"

  # The post-change run DOES carry the warning on stderr (this fixture is
  # merged-order); the pre-change run cannot (the code did not exist yet).
  [[ "$(grep -c post-merge-close "$pre_err" || true)" -eq 0 ]] \
    || log_fail "t049: pre-change stderr must never carry post-merge-close (no such code existed)"
  [[ "$(grep -c post-merge-close "$post_err" || true)" -eq 1 ]] \
    || log_fail "t049: post-change stderr must carry exactly one post-merge-close line"

  # Same invariant on the non-warning (open-PR-order) path: build a second
  # pre/post pair that is never pushed to origin.
  local base2; base2=$(new_fixture_repo_with_remote "t049n")
  write_change_doc "$base2/docs/issues/CHANGE-0001-t049n.md" "t049n-slug" "draft"
  commit_fixture_docs "$base2"
  local sha2; sha2=$(git -C "$base2" rev-parse HEAD)
  # deliberately NOT pushed -> open-PR order

  local pre_dir2="$TEST_DIR/t049n-pre" post_dir2="$TEST_DIR/t049n-post"
  cp -r "$base2" "$pre_dir2"
  cp -r "$base2" "$post_dir2"

  local pre_out2="$TEST_DIR/t049n-pre.out" pre_err2="$TEST_DIR/t049n-pre.err" pre_code2
  pre_code2=0
  ( cd "$pre_dir2" && node "$pre_script" --ref t049n-slug --pr 50 --commit "$sha2" > "$pre_out2" 2> "$pre_err2" ) || pre_code2=$?

  local post_out2="$TEST_DIR/t049n-post.out" post_err2="$TEST_DIR/t049n-post.err" post_code2
  post_code2=$(run_close "$post_dir2" "$post_out2" "$post_err2" --ref t049n-slug --pr 50 --commit "$sha2")

  assert_exit "pre-change (non-merged) close succeeds" 0 "$pre_code2"
  assert_exit "post-change (non-merged) close succeeds identically" "$pre_code2" "$post_code2"
  cmp -s "$pre_out2" "$post_out2" \
    || log_fail "t049n: non-warning-path stdout must be byte-identical pre- and post-G1"
  [[ "$(grep -c post-merge-close "$post_err2" || true)" -eq 0 ]] \
    || log_fail "t049n: open-PR-order post-change stderr must stay silent too"

  log_pass "G1 report-only proof: stdout/exit code byte-identical pre- and post-change on both the warning and silent paths (TEST-003)"
}

# --- TEST-050 (spec-validation-defers-the-ac-flip-to-close TEST-001/002 /
# Spec-AC-01/02/04): the AC-flip deferral is canon at BOTH ends — validation
# defers, the close flips, and the flip is ordered before close-work-item.mjs.
# Deleting either end's rule text (or reordering the flip after the close
# invocation) must turn this red. ------------------------------------------

test_050_ac_flip_deferral_canon() {
  log_info "Test: AC-flip deferral canon at both ends, flip ordered before close-work-item.mjs (TEST-050)..."

  # Validation end: the deferral is stated as the rule, not an exception.
  grep -qF "AC-FLIP DEFERRAL" "$VALIDATION_PROMPT" \
    || log_fail "t050: VALIDATION.prompt.md must carry the AC-FLIP DEFERRAL rule"
  grep -qF "MUST NOT flip" "$VALIDATION_PROMPT" \
    || log_fail "t050: VALIDATION.prompt.md must forbid flipping AC rows on a still-open doc"
  # Copilot on PR #285: forbidding the bare token "EXCEPTION:" anywhere in the
  # file is broader than the intent and would red an unrelated future section
  # for using the word. Pin the RETIRED PARAGRAPH's own distinctive phrase
  # instead — that is what must never come back.
  if grep -qF "do NOT emit this event now" "$VALIDATION_PROMPT"; then
    log_fail "t050: the old 8a event-EXCEPTION paragraph is back — it must stay folded into the deferral rule, not stand beside it"
  fi

  # Close end: SKILL_PR names the flip as its own step, ordered BEFORE the
  # close-work-item.mjs invocation. awk (not grep|head) keeps this safe under
  # set -euo pipefail on every platform.
  local flip_line close_line
  flip_line=$(awk '/FLIP THE AC TABLE/{print NR; exit}' "$SKILL_PR")
  [[ -n "$flip_line" ]] \
    || log_fail "t050: SKILL_PR.prompt.md must name the AC-table flip as its own close step"
  close_line=$(awk '/close-work-item\.mjs --ref/{print NR; exit}' "$SKILL_PR")
  [[ -n "$close_line" ]] \
    || log_fail "t050: SKILL_PR.prompt.md lost its close-work-item.mjs invocation"
  [[ "$flip_line" -lt "$close_line" ]] \
    || log_fail "t050: the AC-table flip (line $flip_line) must be ordered before the close-work-item.mjs invocation (line $close_line)"

  log_pass "AC-flip deferral canon at both ends; flip ordered before close (TEST-050)"
}

# --- spec-close-leaves-state-stale (TEST-051..054 / TEST-001..004) ----------
# Surface 1 — the close ceremony's own STATE reconcile (D1-D6): after the
# self-verified close, active_work_items[<ref>].status flips to done and the
# path fields are rewritten to the paths THIS run resolved on disk, and
# current_focus follows suit only when it names this same scope.

# --- TEST-051 (spec TEST-001, Spec-AC-01): basic reconcile -------------------

test_051_state_reconcile_basic() {
  log_info "Test: close-time STATE reconcile flips active_work_items status to done and rewrites primary_path (work-item AND focus arms) (spec-close-leaves-state-stale TEST-001)..."
  local dir; dir=$(new_fixture_repo "t051")
  write_change_doc "$dir/docs/issues/CHANGE-0001-t051.md" "t051-slug" "implementing"
  commit_fixture_docs "$dir"
  write_reconcile_state "$dir" "CHANGE-0001" "in_progress" "implementation" \
    "docs/issues/CHANGE-DRAFT-t051.md" "-" \
    "t051-slug" "intake_change" "docs/issues/CHANGE-DRAFT-t051.md" "-"

  local out="$TEST_DIR/t051.out" err="$TEST_DIR/t051.err" code
  code=$(run_close "$dir" "$out" "$err" --ref t051-slug --pr 1 --commit aaaaaaa1)
  assert_exit "t051 close" 0 "$code"
  [[ ! -s "$err" ]] || log_fail "t051: expected no stderr from a clean reconcile, got: $(cat "$err")"

  local snap="$TEST_DIR/t051-state.json"
  state_snapshot_json "$dir/docs/ai/STATE.yaml" "$snap"
  jassert "$snap" 'o.items.find(i => i.ref_id === "CHANGE-0001").status === "done"'
  jassert "$snap" 'o.items.find(i => i.ref_id === "CHANGE-0001").primary_path === "docs/issues/CHANGE-0001-t051.md"'
  jassert "$snap" 'o.focus.ref_id === "t051-slug"'
  jassert "$snap" 'o.focus.primary_path === "docs/issues/CHANGE-0001-t051.md"'

  log_pass "STATE reconcile: work-item status/path + focus path both updated on close (TEST-051 / spec TEST-001)"
}

# --- TEST-052 (spec TEST-002, Spec-AC-01): scoping controls ------------------

test_052_state_reconcile_scoping() {
  log_info "Test: STATE reconcile scoping — a ref absent from STATE writes nothing; a differently-focused STATE reconciles the work item but leaves current_focus byte-identical (spec-close-leaves-state-stale TEST-002)..."

  # (a) ref absent from active_work_items AND current_focus -> STATE untouched.
  local dirA; dirA=$(new_fixture_repo "t052a")
  write_change_doc "$dirA/docs/issues/CHANGE-0002-t052a.md" "t052a-slug" "draft"
  commit_fixture_docs "$dirA"
  write_reconcile_state "$dirA" "CHANGE-9999" "in_progress" "implementation" \
    "docs/issues/CHANGE-9999-other.md" "-" \
    "some-other-ref" "intake_change" "docs/issues/CHANGE-9999-other.md" "-"
  local before after
  before=$(cat "$dirA/docs/ai/STATE.yaml")
  local outA="$TEST_DIR/t052a.out" errA="$TEST_DIR/t052a.err" codeA
  codeA=$(run_close "$dirA" "$outA" "$errA" --ref t052a-slug --pr 2 --commit bbbbbbb2)
  assert_exit "t052a close" 0 "$codeA"
  [[ ! -s "$errA" ]] || log_fail "t052a: a ref absent from STATE must never warn: $(cat "$errA")"
  after=$(cat "$dirA/docs/ai/STATE.yaml")
  [[ "$before" == "$after" ]] || log_fail "t052a: STATE.yaml must stay byte-identical when the closed ref is absent from it"

  # (b) current_focus names a DIFFERENT ref than the one being closed: focus
  # stays untouched, but the work item (which DOES match) still reconciles.
  local dirB; dirB=$(new_fixture_repo "t052b")
  write_change_doc "$dirB/docs/issues/CHANGE-0003-t052b.md" "t052b-slug" "implementing"
  commit_fixture_docs "$dirB"
  write_reconcile_state "$dirB" "CHANGE-0003" "in_progress" "implementation" \
    "docs/issues/CHANGE-DRAFT-t052b.md" "-" \
    "some-other-ref" "intake_change" "docs/issues/CHANGE-9999-other.md" "-"
  local focusBefore focusAfter
  focusBefore=$(sed -n '/^current_focus:/,/^active_work_items:/p' "$dirB/docs/ai/STATE.yaml" | sed '$d')
  local outB="$TEST_DIR/t052b.out" errB="$TEST_DIR/t052b.err" codeB
  codeB=$(run_close "$dirB" "$outB" "$errB" --ref t052b-slug --pr 3 --commit ccccccc3)
  assert_exit "t052b close" 0 "$codeB"
  focusAfter=$(sed -n '/^current_focus:/,/^active_work_items:/p' "$dirB/docs/ai/STATE.yaml" | sed '$d')
  [[ "$focusBefore" == "$focusAfter" ]] || log_fail "t052b: current_focus naming a DIFFERENT ref must stay byte-identical"
  local snapB="$TEST_DIR/t052b-state.json"
  state_snapshot_json "$dirB/docs/ai/STATE.yaml" "$snapB"
  jassert "$snapB" 'o.items.find(i => i.ref_id === "CHANGE-0003").status === "done"'
  jassert "$snapB" 'o.items.find(i => i.ref_id === "CHANGE-0003").primary_path === "docs/issues/CHANGE-0003-t052b.md"'
  jassert "$snapB" 'o.focus.ref_id === "some-other-ref"'

  log_pass "STATE reconcile scoping: absent ref no-op; unrelated current_focus untouched while the matching work item still reconciles (TEST-052 / spec TEST-002)"
}

# --- TEST-053 (spec TEST-003, Spec-AC-02): self-recovery + idempotency ------

test_053_state_reconcile_idempotent_recovery() {
  log_info "Test: STATE reconcile self-recovers when docs/events are already closed but STATE is stale, then makes zero writes on a further re-run (spec-close-leaves-state-stale TEST-003 / Spec-AC-02)..."
  local dir; dir=$(new_fixture_repo "t053")
  write_change_doc "$dir/docs/issues/CHANGE-0005-t053.md" "t053-slug" "implementing"
  commit_fixture_docs "$dir"

  # Run 1: close normally with NO STATE.yaml present yet (STATE absent -> a
  # silent no-op reconcile, never even creating the file).
  local out1="$TEST_DIR/t053-1.out" err1="$TEST_DIR/t053-1.err" code1
  code1=$(run_close "$dir" "$out1" "$err1" --ref t053-slug --pr 5 --commit ddddddd5)
  assert_exit "t053 run1" 0 "$code1"
  [[ ! -f "$dir/docs/ai/STATE.yaml" ]] || log_fail "t053: run1 must not CREATE a STATE.yaml (STATE-absent -> none, silent)"

  # STATE now shows up STALE, as if left behind before this scope existed:
  # docs/events are durably closed, but STATE still says in_progress with the
  # pre-allocation DRAFT path.
  write_reconcile_state "$dir" "CHANGE-0005" "in_progress" "implementation" \
    "docs/issues/CHANGE-DRAFT-t053.md" "-"

  # Run 2: docs/events need NOTHING (already closed) but STATE is stale ->
  # must still reconcile (Spec-AC-02 self-recovery), never short-circuit to
  # "nothing to do".
  local out2="$TEST_DIR/t053-2.out" err2="$TEST_DIR/t053-2.err" code2
  code2=$(run_close "$dir" "$out2" "$err2" --ref t053-slug --pr 5 --commit ddddddd5)
  assert_exit "t053 run2 (recovery)" 0 "$code2"
  [[ ! -s "$err2" ]] || log_fail "t053 run2: expected a clean silent reconcile, got: $(cat "$err2")"
  local snap2="$TEST_DIR/t053-2-state.json"
  state_snapshot_json "$dir/docs/ai/STATE.yaml" "$snap2"
  jassert "$snap2" 'o.items.find(i => i.ref_id === "CHANGE-0005").status === "done"'
  jassert "$snap2" 'o.items.find(i => i.ref_id === "CHANGE-0005").primary_path === "docs/issues/CHANGE-0005-t053.md"'

  # Run 3: everything (docs, events, STATE) is now already reconciled -> zero
  # writes, byte-identical STATE. Pin updated_at_utc to a sentinel FIRST
  # (mirrors test-aai-orchestration-dispatch.sh's run_at_utc pattern): state.mjs
  # stamps updated_at_utc via nowIso(), which truncates to whole seconds, so
  # two runs landing inside the same wall-clock second would make a genuine
  # spurious write invisible to a plain before/after byte compare (F-3). The
  # sentinel detaches "before" from the real clock so ANY write in run3 —
  # same-second or not — necessarily changes the file.
  sed -i.bak 's/^updated_at_utc:.*/updated_at_utc: 2030-01-01T00:00:00Z/' "$dir/docs/ai/STATE.yaml" \
    && rm -f "$dir/docs/ai/STATE.yaml.bak"
  local before after
  before=$(cat "$dir/docs/ai/STATE.yaml")
  local out3="$TEST_DIR/t053-3.out" err3="$TEST_DIR/t053-3.err" code3
  code3=$(run_close "$dir" "$out3" "$err3" --ref t053-slug --pr 5 --commit ddddddd5)
  assert_exit "t053 run3 (fully idempotent)" 0 "$code3"
  [[ ! -s "$err3" ]] || log_fail "t053 run3: a fully-reconciled STATE must never warn, got: $(cat "$err3")"
  after=$(cat "$dir/docs/ai/STATE.yaml")
  [[ "$before" == "$after" ]] || log_fail "t053 run3: STATE.yaml must be byte-identical on a fully idempotent re-run"

  log_pass "STATE reconcile self-recovers a closed-docs/stale-STATE repo and is byte-idempotent thereafter (TEST-053 / spec TEST-003)"
}

# --- TEST-054 (spec TEST-004, Spec-AC-03/04): WARN + PARTIAL arms -----------

test_054_state_reconcile_warn_and_partial() {
  log_info "Test: STATE reconcile degrades to a named WARN (nothing written) under AAI_ROLE=subagent and on a first-command failure, and to a PARTIAL block (exit 6) on a genuine mid-apply failure (spec-close-leaves-state-stale TEST-004 / Spec-AC-03/04)..."

  # Arm 1 — AAI_ROLE=subagent: exit 0, byte-identical STATE, exactly ONE WARN
  # line naming the single-writer refusal and echoing BOTH planned commands.
  # The doc itself still closes normally — only the reconcile degrades.
  local dir1; dir1=$(new_fixture_repo "t054a")
  write_change_doc "$dir1/docs/issues/CHANGE-0006-t054a.md" "t054a-slug" "implementing"
  commit_fixture_docs "$dir1"
  write_reconcile_state "$dir1" "CHANGE-0006" "in_progress" "implementation" \
    "docs/issues/CHANGE-DRAFT-t054a.md" "-" \
    "t054a-slug" "intake_change" "docs/issues/CHANGE-DRAFT-t054a.md" "-"
  local before1 after1
  before1=$(cat "$dir1/docs/ai/STATE.yaml")
  local out1="$TEST_DIR/t054a.out" err1="$TEST_DIR/t054a.err" code1=0
  ( cd "$dir1" && AAI_ROLE=subagent node "$CLOSE_SCRIPT" --ref t054a-slug --pr 6 --commit eeeeeee6 \
    > "$out1" 2> "$err1" ) || code1=$?
  assert_exit "t054a (AAI_ROLE=subagent)" 0 "$code1"
  after1=$(cat "$dir1/docs/ai/STATE.yaml")
  [[ "$before1" == "$after1" ]] || log_fail "t054a: STATE.yaml must stay byte-identical under AAI_ROLE=subagent"
  grep -q '^status: done$' "$dir1/docs/issues/CHANGE-0006-t054a.md" \
    || log_fail "t054a: the doc itself must still close normally despite the STATE WARN"
  [[ "$(grep -c 'close-work-item: WARN (state-reconcile)' "$err1")" == "1" ]] \
    || log_fail "t054a: expected EXACTLY one state-reconcile WARN line, got: $(cat "$err1")"
  grep -q 'single-writer' "$err1" \
    || log_fail "t054a: WARN must name the single-writer refusal: $(cat "$err1")"
  grep -q 'set-phase --ref CHANGE-0006' "$err1" \
    || log_fail "t054a: WARN must echo the set-phase command: $(cat "$err1")"
  grep -q 'set-focus --type intake_change --ref t054a-slug' "$err1" \
    || log_fail "t054a: WARN must echo the set-focus command: $(cat "$err1")"

  # Arm 2 — injected first-command failure that is NOT the R-GUARD: the
  # work-item's ref is a bare YAML-keyword slug ("off"), which passes this
  # ceremony's own shape pre-check (a real slug shape) but state.mjs's own
  # refFlag() refuses it (YAML_KEYWORD_SLUGS) — same WARN shape, exit 0,
  # nothing written, because the FIRST (only) planned command failed.
  local dir2; dir2=$(new_fixture_repo "t054b")
  write_change_doc "$dir2/docs/issues/CHANGE-0007-t054b.md" "off" "implementing"
  commit_fixture_docs "$dir2"
  write_reconcile_state "$dir2" "off" "in_progress" "implementation" \
    "docs/issues/CHANGE-DRAFT-t054b.md" "-"
  local before2 after2
  before2=$(cat "$dir2/docs/ai/STATE.yaml")
  local out2="$TEST_DIR/t054b.out" err2="$TEST_DIR/t054b.err" code2
  code2=$(run_close "$dir2" "$out2" "$err2" --ref off --pr 7 --commit fffffff7)
  assert_exit "t054b (injected first-command failure)" 0 "$code2"
  after2=$(cat "$dir2/docs/ai/STATE.yaml")
  [[ "$before2" == "$after2" ]] || log_fail "t054b: STATE.yaml must stay byte-identical when the only command fails"
  [[ "$(grep -c 'close-work-item: WARN (state-reconcile)' "$err2")" == "1" ]] \
    || log_fail "t054b: expected exactly one state-reconcile WARN line, got: $(cat "$err2")"

  # Arm 3 — injected SECOND-command failure: the work-item's ref ("CHANGE-0008")
  # is a normal ref and succeeds; current_focus's ref is the SAME doc's OTHER
  # identity member — the bare YAML-keyword slug "off" (the doc's frontmatter
  # id) — which state.mjs's refFlag() refuses. First command really applies,
  # second fails -> exit 6, PARTIAL block naming 1-of-2 and echoing the
  # remaining (failed) command.
  local dir3; dir3=$(new_fixture_repo "t054c")
  write_change_doc "$dir3/docs/issues/CHANGE-0008-t054c.md" "off" "implementing"
  commit_fixture_docs "$dir3"
  write_reconcile_state "$dir3" "CHANGE-0008" "in_progress" "implementation" \
    "docs/issues/CHANGE-DRAFT-t054c.md" "-" \
    "off" "intake_change" "docs/issues/CHANGE-DRAFT-t054c.md" "-"
  local out3="$TEST_DIR/t054c.out" err3="$TEST_DIR/t054c.err" code3
  code3=$(run_close "$dir3" "$out3" "$err3" --ref off --pr 8 --commit 08080808)
  assert_exit "t054c (injected second-command failure -> PARTIAL exit 6)" 6 "$code3"
  grep -q 'close-work-item: PARTIAL (state-reconcile)' "$err3" \
    || log_fail "t054c: expected a PARTIAL (state-reconcile) block, got: $(cat "$err3")"
  grep -q '1 of 2' "$err3" || log_fail "t054c: PARTIAL block must name applied-of-total (1 of 2): $(cat "$err3")"
  grep -q 'set-focus' "$err3" || log_fail "t054c: PARTIAL block must echo the remaining (failed) command: $(cat "$err3")"
  local snap3="$TEST_DIR/t054c-state.json"
  state_snapshot_json "$dir3/docs/ai/STATE.yaml" "$snap3"
  jassert "$snap3" 'o.items.find(i => i.ref_id === "CHANGE-0008").status === "done"'
  jassert "$snap3" 'o.focus.ref_id === "off"'
  jassert "$snap3" 'o.focus.primary_path === "docs/issues/CHANGE-DRAFT-t054c.md"'

  log_pass "STATE reconcile WARN (AAI_ROLE + first-command failure) and PARTIAL (second-command failure, exit 6) arms behave per D3 (TEST-054 / spec TEST-004)"
}

# --- TEST-055 (spec TEST-012, Spec-AC-10): the exit-6 carve in SKILL_PR step
# 5c is pinned as substance, not a surviving token. Reverting either half back
# to the pre-carve wording (commit 3ceaf3f^) must turn this red.  -----------

test_055_skill_pr_exit6_carve_pinned() {
  log_info "Test: SKILL_PR step 5c exit-6 carve is pinned — revert trigger names an exit OTHER THAN 6, and a following instruction keeps the flip and runs the echoed remaining state.mjs command(s) on exit 6 (spec-close-leaves-state-stale TEST-012 / Spec-AC-10)..."

  # Isolate step 5c's own text so a match elsewhere in the file (e.g. a
  # decoy sentence living in an unrelated step) cannot satisfy this arm.
  local block
  block=$(awk '/^5d\./{exit} /^5c\. CLOSE THE WORK ITEM/{flag=1} flag' "$SKILL_PR")
  [[ -n "$block" ]] || log_fail "t055: could not isolate step 5c's text in $SKILL_PR"

  # Assertion 1 — the revert trigger names a non-zero exit OTHER THAN 6, on
  # the single physical line that ties the exception to the REVERT verb.
  # A decoy that drops "other than 6" (the pre-carve blanket rule) or that
  # plants the token "other than 6" elsewhere, unconnected to REVERT, fails
  # this grep.
  echo "$block" | grep -qF 'non-zero other than 6, REVERT the flip' \
    || log_fail "t055: step 5c's revert trigger must name a non-zero exit OTHER THAN 6 before reverting the flip (pre-carve blanket wording, or an untied decoy token, must fail this)"

  # Assertion 2 — a following instruction in the SAME step gives exit 6 the
  # opposite imperative: keep the flip, and complete the echoed remaining
  # state.mjs command(s) rather than reverting. Join the block's wrapped
  # lines into one string first, since this sentence wraps across two
  # physical lines in the shipped file.
  local joined
  joined=$(printf '%s\n' "$block" | tr '\n' ' ' | tr -s ' ')
  printf '%s' "$joined" | grep -qF 'Exit 6 means the close STOOD: keep the flip; run the echoed remaining state.mjs command(s).' \
    || log_fail "t055: step 5c must instruct that exit 6 KEEPS the flip and runs the echoed remaining state.mjs command(s), not just mention exit 6 in passing"

  log_pass "SKILL_PR step 5c exit-6 carve pinned as substance: exit 6 is the one non-zero exit where the flip STAYS (TEST-055 / spec TEST-012)"
}

main() {
  echo "=== $TEST_NAME ==="
  check_deps
  setup_fixture

  if [[ $# -gt 0 ]]; then
    "$1"
    echo "=== $TEST_NAME: SELECTED TEST PASSED ($1) ==="
    return
  fi

  test_001_draft_close
  test_002_implementing_close
  test_003_non_done_terminal_guard
  test_004_ref_form_and_audit_clean
  test_005_pair_close
  test_006_pair_pre_write_abort
  test_007_idempotent_rerun
  test_008_fail_closed_rollback
  test_009_canon_grep_contract
  test_010_fail_closed_index_regen_rollback
  test_011_inline_nonempty_links_normalized
  test_012_null_fm_id_pre_write_guard
  test_013_brief_cleanup_on_close
  test_014_overview_regen_best_effort
  test_015_overview_regen_failure_negative_control
  test_016_gate_report_only_warns
  test_017_gate_enforce_refuses_pre_write
  test_018_gate_absent_user_visible_negative_control
  test_019_gate_real_product_doc_passes_enforce
  test_020_gate_placeholder_data_model_counts_missing
  test_021_gate_placeholder_interfaces_and_none_dot_passes
  test_022_seam_close_updates_userguide_rollup
  test_023_negative_control_rollup_failure
  test_024_legacy_suite_regression
  test_025_guard_config_product_doc_gate_dial
  test_026_capability_gate_resolves
  test_027_capability_shared_two_refs
  test_028_delivered_by_byte_idempotent
  test_029_capability_enforce_missing_doc_refuse
  test_030_usage_gate_report_only_warns
  test_031_usage_gate_enforce_refuses_pre_write
  test_032_usage_gate_sentinel_passes_enforce
  test_033_usage_gate_captured_and_metarole_pass
  test_034_usage_gate_dry_run_noop
  test_035_guard_config_usage_capture_gate_dial
  test_036_evidence_path_extraction_grammar
  test_037_evidence_paths_shared_parser_contract
  test_038_guard_config_evidence_path_gate_dial
  test_039_evidence_gate_report_only_warns
  test_040_evidence_gate_enforce_refuses_pre_write
  test_041_evidence_gate_existence_not_tracking
  test_042_evidence_gate_prose_never_refuses
  test_043_evidence_gate_dry_run_noop
  test_046_evidence_gate_worktree_resolves_against_main_tree
  test_047_post_merge_close_warns_once
  test_048_post_merge_close_negative_controls
  test_049_post_merge_close_report_only
  test_050_ac_flip_deferral_canon
  test_051_state_reconcile_basic
  test_052_state_reconcile_scoping
  test_053_state_reconcile_idempotent_recovery
  test_054_state_reconcile_warn_and_partial
  test_055_skill_pr_exit6_carve_pinned

  echo "=== $TEST_NAME: ALL TESTS PASSED ==="
}

main "$@"
