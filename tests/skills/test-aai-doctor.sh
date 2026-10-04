#!/usr/bin/env bash
#
# Test: aai-doctor deterministic engine (CHANGE-0079 / spec-doctor-determinize)
#
# Verifies .aai/scripts/aai-doctor.mjs — the deterministic replacement for the
# 11 prose-computed categories that used to live inside
# .aai/SKILL_DOCTOR.prompt.md (file existence, line counts, git-status
# parsing, hook wiring, dynamic-skills presence, RFC-0001 migration matrix) —
# plus the CAT-11/CAT-13 subprocess wiring to docs-audit.mjs and
# layer-drift.mjs (unchanged behavior, still real scripts).
#
# Fixtures are built under mktemp; the real helper scripts
# (check-state.mjs, docs-audit.mjs, layer-drift.mjs) are copied alongside a
# copy of aai-doctor.mjs itself into each fixture's .aai/scripts/ so the
# script-location-derived default root AND the sibling-script resolution
# both exercise the real production code path (mirrors the technique
# test-aai-layer-drift.sh test_space_in_path uses).
#
# Covers TEST-001..022 from docs/specs/SPEC-0100-spec-doctor-determinize.md.
#
# Covers TEST-619..620 (Spec-AC-07) from
# docs/specs/SPEC-0184-spec-update-installs-ref-guard-undisclosed.md: CAT-17
# consults lib/guard-config.mjs's readRefGuardPolicy for a non-counting
# DECLINED state when no AAI guard is present, and reality (an armed or a
# foreign hook) outranks the declaration (D4).
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-doctor"
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/pipe-safe.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCTOR="$PROJECT_ROOT/.aai/scripts/aai-doctor.mjs"
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"

# dr_line_hit <payload> <ere> — true (rc 0) iff some LINE of <payload> matches
# <ere>, tested one line at a time so `.` can never span a newline the way it
# would under a single whole-string `[[ =~ ]]` (Spec-AC-11 anchor/multiline
# trap). Unlike assert_payload_line_matches this NEVER calls log_fail — some
# call sites below accumulate several independent checks into one `ok` flag
# and report ONE verdict at the end, so an escalating helper would be wrong
# here (it would abort the whole suite on the FIRST failing sub-check instead
# of collecting all of them).
dr_line_hit() {
  local _dr_payload="$1" _dr_ere="$2" _dr_line
  while IFS= read -r _dr_line; do
    if [[ "$_dr_line" =~ $_dr_ere ]]; then
      return 0
    fi
  done <<EOF
$_dr_payload
EOF
  return 1
}

TMP_ROOT=""
FAILED=0

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixtures under $TMP_ROOT"
    return 0
  fi
  [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]] && rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; FAILED=1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$DOCTOR" ]] || log_skip "aai-doctor.mjs not found: $DOCTOR"
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-doctor-test.XXXXXX")"
}

# --- fixture builders ---------------------------------------------------------

# Bare-bones fixture: nothing present except a git init. Used for the FAIL /
# missing-file assertions.
new_bare_fixture() {
  local name="$1"
  local d="$TMP_ROOT/$name"
  mkdir -p "$d"
  echo "$d"
}

# A fixture with its OWN copy of aai-doctor.mjs (and optionally the helper
# scripts) under .aai/scripts/, so invoking THAT copy directly resolves its
# default root to the fixture itself (no --root needed) — proves the
# script-location root resolution, not just the --root override path.
install_doctor_copy() {
  local d="$1"; shift
  mkdir -p "$d/.aai/scripts/lib"
  cp "$DOCTOR" "$d/.aai/scripts/aai-doctor.mjs"
  # aai-doctor.mjs's own pipe-exit-discipline import (cli-exit-truncates-pipe-
  # sweep) and CAT-17's readRefGuardPolicy import (Spec-AC-07) — both hard
  # dependencies of every copy, not opt-in helpers like the ones below
  # (check-vendored-script-deps.mjs gates a vendored engine missing either).
  cp "$PROJECT_ROOT/.aai/scripts/lib/cli-pipe-guard.mjs" "$d/.aai/scripts/lib/cli-pipe-guard.mjs"
  cp "$PROJECT_ROOT/.aai/scripts/lib/guard-config.mjs" "$d/.aai/scripts/lib/guard-config.mjs"
  local helper
  for helper in "$@"; do
    mkdir -p "$d/.aai/scripts/$(dirname "$helper")"
    cp "$PROJECT_ROOT/.aai/scripts/$helper" "$d/.aai/scripts/$helper"
  done
}

# All CAT-01/CAT-02 required files (does not by itself satisfy every other
# category — callers layer on top for a fully-clean fixture).
add_core_and_role_files() {
  local d="$1"
  mkdir -p "$d/.aai" "$d/docs/ai" "$d/.aai/workflow"
  : > "$d/.aai/AGENTS.md"
  : > "$d/.aai/PLAYBOOK.md"
  : > "$d/.aai/ORCHESTRATION.prompt.md"
  : > "$d/docs/ai/STATE.yaml"
  : > "$d/CLAUDE.md"
  : > "$d/docs/TECHNOLOGY.md"
  : > "$d/.aai/workflow/WORKFLOW.md"
  : > "$d/.aai/PLANNING.prompt.md"
  : > "$d/.aai/IMPLEMENTATION.prompt.md"
  : > "$d/.aai/VALIDATION.prompt.md"
  : > "$d/.aai/REMEDIATION.prompt.md"
}

# Build a fixture on which EVERY category should report PASS. Includes fake
# always-clean docs-audit.mjs / layer-drift.mjs stubs (real script behavior
# is covered by their own dedicated suites, not re-tested here) and a real
# copy of check-state.mjs (structural check IS this script's own contract).
build_clean_fixture() {
  # CHANGE-0135: accepts an optional distinct name so a test can build its
  # OWN clean fixture without colliding with one an earlier test already
  # git-init'd/pushed at the same fixed path (the original single-caller
  # "clean" name is the default, preserved for the pre-existing caller).
  local suffix="${1:-clean}"
  local d="$TMP_ROOT/$suffix"
  mkdir -p "$d"
  add_core_and_role_files "$d"
  install_doctor_copy "$d" "check-state.mjs"
  mkdir -p "$d/.aai/scripts/lib"
  cp "$PROJECT_ROOT/.aai/scripts/lib/state-core.mjs" "$d/.aai/scripts/lib/state-core.mjs"

  # CAT-03: a universal skill with no dangling prompt reference.
  mkdir -p "$d/.claude/skills/aai-fixture"
  cat > "$d/.claude/skills/aai-fixture/SKILL.md" <<'EOF'
---
name: aai-fixture
description: fixture skill, no prompt reference
---
Nothing to see here.
EOF

  # CAT-04: a dynamic skill present.
  mkdir -p "$d/.claude/skills/aai-test-unit"
  echo "unit" > "$d/.claude/skills/aai-test-unit/SKILL.md"

  # CAT-05: non-empty knowledge files.
  mkdir -p "$d/docs/knowledge"
  printf 'fact one\nfact two\n' > "$d/docs/knowledge/FACTS.md"
  printf 'pattern one\n' > "$d/docs/knowledge/PATTERNS.md"
  : > "$d/docs/knowledge/UI_MAP.md"
  : > "$d/docs/knowledge/LEARNED.md"

  # CAT-06: valid single-key-per-block STATE.yaml (real check-state.mjs OK).
  cat > "$d/docs/ai/STATE.yaml" <<'EOF'
project_status: active
updated_at_utc: 2026-07-27T00:00:00Z
EOF

  # CAT-07: non-empty telemetry.
  printf '{"a":1}\n' > "$d/docs/ai/METRICS.jsonl"
  printf '{"b":1}\n' > "$d/docs/ai/decisions.jsonl"
  : > "$d/docs/ai/LOOP_TICKS.jsonl"

  # CAT-09: both pre-compact hook scripts.
  : > "$d/.aai/scripts/pre-compact-save.sh"
  : > "$d/.aai/scripts/pre-compact-save.ps1"

  # CAT-10: STATE.yaml + LOOP_TICKS.jsonl gitignored and untracked;
  # EVENTS.jsonl present and tracked.
  printf 'docs/ai/STATE.yaml\ndocs/ai/LOOP_TICKS.jsonl\n' > "$d/.gitignore"
  printf '{"e":1}\n' > "$d/docs/ai/EVENTS.jsonl"

  # CAT-11: stub docs-audit.mjs that always reports CLEAN.
  cat > "$d/.aai/scripts/docs-audit.mjs" <<'EOF'
#!/usr/bin/env node
console.log("## Docs Audit — fixture\n\n### Verdict: CLEAN");
process.exit(0);
EOF
  : > "$d/docs/ai/docs-audit.yaml"

  # CAT-12: pre-commit hook with the AAI marker.
  mkdir -p "$d/.git/hooks"
  printf '#!/bin/sh\n# AAI:INDEX-AUTOGEN\n' > "$d/.git/hooks/pre-commit"
  chmod +x "$d/.git/hooks/pre-commit"

  # CAT-13: stub layer-drift.mjs that always reports up-to-date.
  cat > "$d/.aai/scripts/layer-drift.mjs" <<'EOF'
#!/usr/bin/env node
console.log("layer up-to-date (pin abc1234 == canonical main)");
process.exit(0);
EOF

  # git init with a real commit + upstream tracking so CAT-08 is fully clean.
  git -C "$d" init -q -b main
  git -C "$d" config user.email "test@example.invalid"
  git -C "$d" config user.name "AAI Test"
  git -C "$d" add -A
  git -C "$d" commit -qm "fixture: clean doctor tree"
  local bare="$TMP_ROOT/$suffix-bare.git"
  git init -q --bare "$bare"
  git -C "$d" remote add origin "$bare"
  git -C "$d" push -q -u origin main

  # CAT-17: a GENUINELY armed reference-transaction hook, installed LAST
  # (after the fixture's own commit/push above) so it never intercepts this
  # function's own ref writes. PR #302 (Copilot): the prior fixture here was
  # `exit 0` unconditionally — exactly the decorative-hook-that-never-
  # refuses shape the review flagged. CAT-17 now behaviourally probes the
  # hook (invokes it directly with synthetic prepared/refs-heads-main
  # input), so a decorative body correctly earns WARN, not PASS, and this
  # fixture must ship the real predicate to still be "clean".
  cat > "$d/.git/hooks/reference-transaction" <<'REFTXHOOK'
#!/bin/sh
# AAI:REF-GUARD -- refuses a refs/heads/main ref update unless AAI_GIT_WRITE=1.
aai_state="$1"
if [ "$aai_state" != "prepared" ]; then
  exit 0
fi
aai_guarded=0
while read -r aai_old aai_new aai_ref; do
  if [ "$aai_ref" = "refs/heads/main" ]; then
    aai_guarded=1
  fi
done
if [ "$aai_guarded" != "1" ]; then
  exit 0
fi
if [ "$AAI_GIT_WRITE" = "1" ]; then
  exit 0
fi
# SEAM-1 (spec-a-check-cannot-tell-silence-from-a-verdict D1): the REAL hook
# body install-pre-commit-hook.sh writes announces its refusal on stderr, and
# CAT-17's probe now reads that marker rather than trusting a bare non-zero
# exit. A fixture modelling the installed hook must announce it too.
echo "AAI:REF-GUARD refused this refs/heads/main update." >&2
exit 1
REFTXHOOK
  chmod +x "$d/.git/hooks/reference-transaction"

  echo "$d"
}

# --- TEST-001 — CAT-01 required file missing -> FAIL, names the file --------
test_001_cat01_fail_named() {
  local d fixture out
  fixture="$(new_bare_fixture t001)"
  mkdir -p "$fixture/.aai" "$fixture/docs/ai"
  : > "$fixture/.aai/PLAYBOOK.md"
  : > "$fixture/.aai/ORCHESTRATION.prompt.md"
  : > "$fixture/docs/ai/STATE.yaml"
  : > "$fixture/CLAUDE.md"
  # .aai/AGENTS.md deliberately missing.
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if dr_line_hit "$out" '^CAT-01 FAIL' && [[ "$(echo "$out" | grep '^CAT-01')" == *"AGENTS.md"* ]]; then
    log_pass "TEST-001 CAT-01 FAIL names the missing required file"
  else
    log_info "TEST-001: got: $(echo "$out" | grep '^CAT-01')"
    log_fail "TEST-001 CAT-01 missing-file FAIL"
  fi
}

# --- TEST-002 — CAT-02 role prompt missing -> FAIL, names the file ----------
test_002_cat02_fail_named() {
  local fixture out
  fixture="$(new_bare_fixture t002)"
  add_core_and_role_files "$fixture"
  rm -f "$fixture/.aai/VALIDATION.prompt.md"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if echo "$out" | grep "^CAT-02" | qgrep -q "FAIL" && echo "$out" | grep "^CAT-02" | qgrep -q "VALIDATION.prompt.md"; then
    log_pass "TEST-002 CAT-02 FAIL names the missing role prompt"
  else
    log_info "TEST-002: got: $(echo "$out" | grep '^CAT-02')"
    log_fail "TEST-002 CAT-02 missing-role-prompt FAIL"
  fi
}

# --- TEST-003 — CAT-03 dangling prompt reference -> WARN, names the skill --
test_003_cat03_orphan_warn() {
  local fixture out
  fixture="$(new_bare_fixture t003)"
  add_core_and_role_files "$fixture"
  mkdir -p "$fixture/.claude/skills/aai-orphan"
  echo 'Read the file `.aai/SKILL_NOPE.prompt.md`' > "$fixture/.claude/skills/aai-orphan/SKILL.md"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if echo "$out" | grep "^CAT-03" | qgrep -q "WARN" && echo "$out" | grep "^CAT-03" | qgrep -q "aai-orphan"; then
    log_pass "TEST-003 CAT-03 WARN names the orphaned skill"
  else
    log_info "TEST-003: got: $(echo "$out" | grep '^CAT-03')"
    log_fail "TEST-003 CAT-03 orphan detection"
  fi
}

# --- TEST-004 — CAT-04 none found -> WARN; some found -> PASS ---------------
test_004_cat04_dynamic_skills() {
  local fixture out
  fixture="$(new_bare_fixture t004a)"
  add_core_and_role_files "$fixture"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if ! echo "$out" | grep "^CAT-04" | qgrep -q "WARN"; then
    log_info "TEST-004a: got: $(echo "$out" | grep '^CAT-04')"
    log_fail "TEST-004a CAT-04 none-found WARN"
    return
  fi
  local fixture2
  fixture2="$(new_bare_fixture t004b)"
  add_core_and_role_files "$fixture2"
  mkdir -p "$fixture2/.claude/skills/aai-build"
  echo "x" > "$fixture2/.claude/skills/aai-build/SKILL.md"
  out="$(node "$DOCTOR" --root "$fixture2" 2>&1)"
  if echo "$out" | grep "^CAT-04" | qgrep -q "PASS"; then
    log_pass "TEST-004 CAT-04 none->WARN, some->PASS"
  else
    log_info "TEST-004b: got: $(echo "$out" | grep '^CAT-04')"
    log_fail "TEST-004b CAT-04 some-found PASS"
  fi
}

# --- TEST-005 — CAT-05 missing/empty -> WARN with names ----------------------
test_005_cat05_knowledge() {
  local fixture out
  fixture="$(new_bare_fixture t005)"
  add_core_and_role_files "$fixture"
  mkdir -p "$fixture/docs/knowledge"
  : > "$fixture/docs/knowledge/FACTS.md"   # empty
  # PATTERNS.md deliberately missing entirely
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if echo "$out" | grep "^CAT-05" | qgrep -q "WARN" \
    && echo "$out" | grep "^CAT-05" | qgrep -q "FACTS.md empty" \
    && echo "$out" | grep "^CAT-05" | qgrep -q "PATTERNS.md missing"; then
    log_pass "TEST-005 CAT-05 empty+missing knowledge files WARN"
  else
    log_info "TEST-005: got: $(echo "$out" | grep '^CAT-05')"
    log_fail "TEST-005 CAT-05 knowledge files"
  fi
}

# --- TEST-006 — CAT-06 STATE.yaml duplicate key -> FAIL (real check-state.mjs) -
test_006_cat06_duplicate_key_fail() {
  local fixture
  fixture="$(new_bare_fixture t006)"
  add_core_and_role_files "$fixture"
  mkdir -p "$fixture/.aai/scripts/lib"
  cp "$PROJECT_ROOT/.aai/scripts/check-state.mjs" "$fixture/.aai/scripts/check-state.mjs"
  cp "$PROJECT_ROOT/.aai/scripts/lib/state-core.mjs" "$fixture/.aai/scripts/lib/state-core.mjs"
  # check-state.mjs's OTHER real import (check-vendored-script-deps.mjs,
  # Amendment 21). Never actually resolved from this copy today —
  # aai-doctor.mjs's CAT-06 spawns check-state.mjs via its OWN real
  # scriptDir (import.meta.url), never `$fixture` — but copied anyway so
  # this fixture is never one `import.meta.url` refactor away from a
  # silent ERR_MODULE_NOT_FOUND.
  cp "$PROJECT_ROOT/.aai/scripts/lib/cli-pipe-guard.mjs" "$fixture/.aai/scripts/lib/cli-pipe-guard.mjs"
  cat > "$fixture/docs/ai/STATE.yaml" <<'EOF'
project_status: active
metrics:
  work_items: {}
metrics:
  work_items: {}
EOF
  local out
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if echo "$out" | grep "^CAT-06" | qgrep -q "FAIL"; then
    log_pass "TEST-006 CAT-06 duplicate top-level key -> FAIL (real check-state.mjs)"
  else
    log_info "TEST-006: got: $(echo "$out" | grep '^CAT-06')"
    log_fail "TEST-006 CAT-06 duplicate-key FAIL"
  fi

  # STATE.yaml absent entirely -> WARN everywhere, exit 0: it is a per-dev,
  # gitignored runtime file (RFC-0001) legitimately missing on fresh
  # checkouts/CI — CAT-01 must NOT list it as required (PR #178 CI repro),
  # CAT-06 owns the absence with an init hint.
  local fixture2 out2 rc2=0
  fixture2="$(new_bare_fixture t006b)"
  add_core_and_role_files "$fixture2"
  rm -f "$fixture2/docs/ai/STATE.yaml"
  out2="$(node "$DOCTOR" --root "$fixture2" 2>&1)" || rc2=$?
  if echo "$out2" | grep "^CAT-01" | qgrep -vq FAIL && echo "$out2" | grep "^CAT-06" | qgrep -q "WARN" && [[ "$rc2" -eq 0 ]]; then
    log_pass "TEST-006b missing STATE.yaml -> CAT-06 WARN, CAT-01 unaffected, exit 0 (CI-checkout parity)"
  else
    log_info "TEST-006b: rc=$rc2 CAT-01=$(echo "$out2" | grep '^CAT-01') CAT-06=$(echo "$out2" | grep '^CAT-06')"
    log_fail "TEST-006b missing-state must be WARN-only with exit 0"
  fi
}

# --- TEST-007 — CAT-07 telemetry line counts ---------------------------------
test_007_cat07_telemetry() {
  local fixture out
  fixture="$(new_bare_fixture t007)"
  add_core_and_role_files "$fixture"
  printf '{"a":1}\n{"a":2}\n{"a":3}\n' > "$fixture/docs/ai/METRICS.jsonl"
  printf '{"b":1}\n' > "$fixture/docs/ai/decisions.jsonl"
  : > "$fixture/docs/ai/LOOP_TICKS.jsonl"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if echo "$out" | grep "^CAT-07" | qgrep -q "METRICS.jsonl: 3 entries" \
    && echo "$out" | grep "^CAT-07" | qgrep -q "decisions.jsonl: 1 entries"; then
    log_pass "TEST-007 CAT-07 telemetry line counts"
  else
    log_info "TEST-007: got: $(echo "$out" | grep '^CAT-07')"
    log_fail "TEST-007 CAT-07 telemetry counts"
  fi
}

# --- TEST-008 — CAT-08 git status (dirty vs clean, non-git SKIP) ------------
test_008_cat08_git_status() {
  local fixture out
  fixture="$(new_bare_fixture t008)"
  add_core_and_role_files "$fixture"
  git -C "$fixture" init -q -b main
  git -C "$fixture" config user.email "test@example.invalid"
  git -C "$fixture" config user.name "AAI Test"
  git -C "$fixture" add -A
  git -C "$fixture" commit -qm "init"
  echo "dirty" >> "$fixture/CLAUDE.md"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if ! (echo "$out" | grep "^CAT-08" | qgrep -q "WARN" && echo "$out" | grep "^CAT-08" | qgrep -q "changed file"); then
    log_info "TEST-008a: got: $(echo "$out" | grep '^CAT-08')"
    log_fail "TEST-008a CAT-08 dirty tree WARN"
    return
  fi

  local fixture2 out2
  fixture2="$(new_bare_fixture t008-nongit)"
  add_core_and_role_files "$fixture2"
  out2="$(node "$DOCTOR" --root "$fixture2" 2>&1)"
  if echo "$out2" | grep "^CAT-08" | qgrep -q "SKIP"; then
    log_pass "TEST-008 CAT-08 dirty->WARN, non-git->SKIP"
  else
    log_info "TEST-008b: got: $(echo "$out2" | grep '^CAT-08')"
    log_fail "TEST-008b CAT-08 non-git SKIP"
  fi
}

# --- TEST-009 — CAT-09 pre-compact hook presence -----------------------------
test_009_cat09_precompact() {
  local fixture out
  fixture="$(new_bare_fixture t009)"
  add_core_and_role_files "$fixture"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if ! echo "$out" | grep "^CAT-09" | qgrep -q "WARN"; then
    log_info "TEST-009a: got: $(echo "$out" | grep '^CAT-09')"
    log_fail "TEST-009a CAT-09 missing hook WARN"
    return
  fi
  mkdir -p "$fixture/.aai/scripts"
  : > "$fixture/.aai/scripts/pre-compact-save.sh"
  : > "$fixture/.aai/scripts/pre-compact-save.ps1"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if echo "$out" | grep "^CAT-09" | qgrep -q "PASS"; then
    log_pass "TEST-009 CAT-09 missing->WARN, both present->PASS"
  else
    log_info "TEST-009b: got: $(echo "$out" | grep '^CAT-09')"
    log_fail "TEST-009b CAT-09 present PASS"
  fi
}

# --- TEST-010 — CAT-10 RFC-0001 migration matrix -----------------------------
test_010_cat10_migration_matrix() {
  local fixture out
  fixture="$(new_bare_fixture t010)"
  add_core_and_role_files "$fixture"
  git -C "$fixture" init -q -b main
  git -C "$fixture" config user.email "test@example.invalid"
  git -C "$fixture" config user.name "AAI Test"
  # LEGACY: not gitignored, tracked.
  git -C "$fixture" add -A
  git -C "$fixture" commit -qm "init (STATE.yaml tracked, not gitignored)"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if ! (echo "$out" | grep "^CAT-10" | qgrep -q "LEGACY"); then
    log_info "TEST-010a: got: $(echo "$out" | grep '^CAT-10')"
    log_fail "TEST-010a CAT-10 LEGACY case"
    return
  fi
  # INCONSISTENT: gitignored but still tracked.
  printf 'docs/ai/STATE.yaml\n' > "$fixture/.gitignore"
  git -C "$fixture" add .gitignore
  git -C "$fixture" commit -qm "add gitignore (STATE.yaml stays tracked)"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if echo "$out" | grep "^CAT-10" | qgrep -q "INCONSISTENT"; then
    log_pass "TEST-010 CAT-10 LEGACY + INCONSISTENT cases"
  else
    log_info "TEST-010b: got: $(echo "$out" | grep '^CAT-10')"
    log_fail "TEST-010b CAT-10 INCONSISTENT case"
  fi
}

# --- TEST-011 — CAT-11 docs-audit missing -> WARN; stubbed CLEAN -> PASS ----
test_011_cat11_docs_hygiene() {
  local fixture out
  fixture="$(new_bare_fixture t011)"
  add_core_and_role_files "$fixture"
  # Script-presence is resolved relative to the INVOKED script's own
  # location (sibling scripts), not --root — install a fixture-local copy of
  # aai-doctor.mjs (no docs-audit.mjs sibling yet) and invoke THAT directly.
  install_doctor_copy "$fixture"
  out="$(node "$fixture/.aai/scripts/aai-doctor.mjs" 2>&1)"
  if ! (echo "$out" | grep "^CAT-11" | qgrep -q "WARN" && echo "$out" | grep "^CAT-11" | qgrep -qi "not installed"); then
    log_info "TEST-011a: got: $(echo "$out" | grep '^CAT-11')"
    log_fail "TEST-011a CAT-11 missing-script WARN"
    return
  fi
  cat > "$fixture/.aai/scripts/docs-audit.mjs" <<'EOF'
#!/usr/bin/env node
console.log("### Verdict: CLEAN");
process.exit(0);
EOF
  out="$(node "$fixture/.aai/scripts/aai-doctor.mjs" 2>&1)"
  if echo "$out" | grep "^CAT-11" | qgrep -q "PASS"; then
    log_pass "TEST-011 CAT-11 missing->WARN, stubbed CLEAN->PASS"
  else
    log_info "TEST-011b: got: $(echo "$out" | grep '^CAT-11')"
    log_fail "TEST-011b CAT-11 stubbed CLEAN PASS"
  fi
}

# --- TEST-012 — CAT-12 pre-commit hook marker states ------------------------
test_012_cat12_index_hook() {
  local fixture out
  fixture="$(new_bare_fixture t012)"
  add_core_and_role_files "$fixture"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if ! echo "$out" | grep "^CAT-12" | qgrep -q "WARN"; then
    log_info "TEST-012a: got: $(echo "$out" | grep '^CAT-12')"
    log_fail "TEST-012a CAT-12 not-installed WARN"
    return
  fi
  mkdir -p "$fixture/.git/hooks"
  printf '#!/bin/sh\nsome-foreign-hook\n' > "$fixture/.git/hooks/pre-commit"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if ! (echo "$out" | grep "^CAT-12" | qgrep -q "WARN" && echo "$out" | grep "^CAT-12" | qgrep -q "NOT AAI-managed"); then
    log_info "TEST-012b: got: $(echo "$out" | grep '^CAT-12')"
    log_fail "TEST-012b CAT-12 foreign-hook WARN"
    return
  fi
  printf '#!/bin/sh\n# AAI:INDEX-AUTOGEN\n' > "$fixture/.git/hooks/pre-commit"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if echo "$out" | grep "^CAT-12" | qgrep -q "PASS"; then
    log_pass "TEST-012 CAT-12 not-installed / foreign / AAI-managed states"
  else
    log_info "TEST-012c: got: $(echo "$out" | grep '^CAT-12')"
    log_fail "TEST-012c CAT-12 AAI-managed PASS"
  fi
}

# --- TEST-013 — CAT-13 layer-drift exit-4 tolerated (real script, no pin) --
test_013_cat13_exit4_tolerated() {
  local fixture out rc
  fixture="$(new_bare_fixture t013)"
  add_core_and_role_files "$fixture"
  mkdir -p "$fixture/.aai/scripts/lib"
  cp "$PROJECT_ROOT/.aai/scripts/layer-drift.mjs" "$fixture/.aai/scripts/layer-drift.mjs"
  # layer-drift.mjs's real import (check-vendored-script-deps.mjs, Amendment
  # 21) — see test_006's identical note: never actually resolved from this
  # copy today (aai-doctor.mjs's CAT-13 spawns it via its own real
  # scriptDir), copied anyway so this fixture stays correct if that changes.
  cp "$PROJECT_ROOT/.aai/scripts/lib/cli-pipe-guard.mjs" "$fixture/.aai/scripts/lib/cli-pipe-guard.mjs"
  # No .aai/system/AAI_PIN.md -> real layer-drift.mjs exits 4 (unverifiable).
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"; rc=$?
  if echo "$out" | grep "^CAT-13" | qgrep -q "WARN" \
    && echo "$out" | grep "^CAT-13" | qgrep -qi "unverifiable" \
    && [[ "$rc" -eq 0 ]]; then
    log_pass "TEST-013 CAT-13 layer-drift exit 4 -> WARN (never FAIL), doctor exit 0"
  else
    log_info "TEST-013: rc=$rc got: $(echo "$out" | grep '^CAT-13')"
    log_fail "TEST-013 CAT-13 exit-4 tolerance"
  fi
}

# --- TEST-014 — fully clean fixture -> DOCTOR CLEAN modulo CAT-14/15 -------
# CHANGE-0135: CAT-14 (Windows Self-Test) and CAT-15 (Windows Environment)
# are a legitimate, honest SKIP on any non-Windows host (D6) -- they spawn
# nothing there. "Fully clean" on THIS test host therefore means every OTHER
# category is PASS and the verdict is either CLEAN (both Windows categories
# somehow PASS) or exactly ISSUES(2) naming only CAT-14/CAT-15 as SKIP.
test_014_clean_fixture_doctor_clean() {
  local fixture out rc
  fixture="$(build_clean_fixture)"
  # Invoke the FIXTURE's own copy directly (not --root against the real
  # $DOCTOR) so its default-root resolution picks up the fixture's own
  # stubbed docs-audit.mjs / layer-drift.mjs siblings, not the real repo's.
  out="$(node "$fixture/.aai/scripts/aai-doctor.mjs" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_info "TEST-014: rc=$rc, full output:"
    log_info "$out"
    log_fail "TEST-014 clean fixture exit code"
    return
  fi
  local bad_lines
  bad_lines="$(echo "$out" | grep -E '^CAT-' | grep -vE '^CAT-14 |^CAT-15 ' | grep -v ' PASS ')"
  if [[ -n "$bad_lines" ]]; then
    log_info "TEST-014: unexpected non-PASS category outside CAT-14/CAT-15: $bad_lines"
    log_fail "TEST-014 clean fixture verdict"
    return
  fi
  if dr_line_hit "$out" '^DOCTOR CLEAN$'; then
    log_pass "TEST-014 fully-clean fixture -> DOCTOR CLEAN, exit 0"
  elif dr_line_hit "$out" '^DOCTOR ISSUES(2)$' \
    && [[ "$(echo "$out" | grep '^CAT-14')" == *SKIP* ]] \
    && [[ "$(echo "$out" | grep '^CAT-15')" == *SKIP* ]]; then
    log_pass "TEST-014 fully-clean fixture -> DOCTOR ISSUES(2) (CAT-14/CAT-15 SKIP off Windows), exit 0"
  else
    log_info "TEST-014: got: $out"
    log_fail "TEST-014 clean fixture verdict"
  fi
}

# --- TEST-015 — --json shape --------------------------------------------------
test_015_json_shape() {
  local out
  out="$(node "$DOCTOR" --root "$PROJECT_ROOT" --json 2>&1)"
  echo "$out" | node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      if (typeof j.root !== "string") die("root missing/wrong type");
      if (typeof j.generatedAt !== "string") die("generatedAt missing/wrong type");
      if (!Array.isArray(j.categories) || j.categories.length !== 19) die("categories: want array of 19, got " + (j.categories && j.categories.length));
      const wantIds = [];
      for (let i = 1; i <= 19; i++) wantIds.push("CAT-" + String(i).padStart(2, "0"));
      const gotIds = j.categories.map(c => c.id);
      if (JSON.stringify(gotIds) !== JSON.stringify(wantIds)) die("category ids: " + JSON.stringify(gotIds));
      for (const c of j.categories) {
        if (!["PASS","WARN","FAIL","SKIP"].includes(c.status)) die("bad status for " + c.id + ": " + c.status);
        if (typeof c.reason !== "string" || c.reason.length === 0) die("empty reason for " + c.id);
        if (typeof c.name !== "string" || c.name.length === 0) die("empty name for " + c.id);
      }
      // CHANGE-0135: CAT-14/CAT-15/CAT-16 each carry a structured detail object.
      for (const id of ["CAT-14", "CAT-15", "CAT-16"]) {
        const c = j.categories.find(x => x.id === id);
        if (!c || typeof c.detail !== "object" || c.detail === null) die(id + " missing a structured detail object");
      }
      if (!["CLEAN","ISSUES"].includes(j.verdict)) die("bad verdict: " + j.verdict);
      if (typeof j.issues !== "number") die("issues not a number");
      if (typeof j.exit !== "number") die("exit not a number");
    });
  ' && log_pass "TEST-015 --json emits the documented shape (19 categories on this repo -- CAT-01..18 plus CAT-19 Merge Policy, now that docs/ai/merge-policy.yaml exists here -- CAT-14/15/16 carry detail)" \
    || log_fail "TEST-015 --json shape"
}

# --- TEST-016 — exit codes: FAIL->1, WARN-only->0 ----------------------------
test_016_exit_codes() {
  local fixture rc
  fixture="$(new_bare_fixture t016-fail)"
  add_core_and_role_files "$fixture"
  rm -f "$fixture/.aai/AGENTS.md"
  node "$DOCTOR" --root "$fixture" >/dev/null 2>&1; rc=$?
  if [[ "$rc" -ne 1 ]]; then
    log_info "TEST-016a: expected exit 1 on a FAIL category, got $rc"
    log_fail "TEST-016a exit code on FAIL"
    return
  fi
  local fixture2
  fixture2="$(new_bare_fixture t016-warn)"
  add_core_and_role_files "$fixture2"
  # everything required present -> at most WARN categories (dynamic skills,
  # telemetry, etc.) -> exit 0.
  node "$DOCTOR" --root "$fixture2" >/dev/null 2>&1; rc=$?
  if [[ "$rc" -eq 0 ]]; then
    log_pass "TEST-016 exit codes: FAIL->1, WARN-only->0"
  else
    log_info "TEST-016b: expected exit 0 on WARN-only fixture, got $rc"
    log_fail "TEST-016b exit code on WARN-only"
  fi
}

# --- TEST-017 — cwd-independence ---------------------------------------------
test_017_cwd_independence() {
  local out_a out_b
  out_a="$(cd "$TMP_ROOT" && node "$DOCTOR" --json 2>&1)"
  out_b="$(cd "$PROJECT_ROOT" && node "$DOCTOR" --json 2>&1)"
  # Normalize away the volatile generatedAt timestamp before comparing.
  local norm_a norm_b
  norm_a="$(echo "$out_a" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const j=JSON.parse(d);delete j.generatedAt;console.log(JSON.stringify(j));});')"
  norm_b="$(echo "$out_b" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{const j=JSON.parse(d);delete j.generatedAt;console.log(JSON.stringify(j));});')"
  if [[ "$norm_a" == "$norm_b" ]]; then
    log_pass "TEST-017 same output regardless of caller's cwd (default root resolves via script location)"
  else
    log_info "TEST-017: cwd=$TMP_ROOT -> $norm_a"
    log_info "TEST-017: cwd=$PROJECT_ROOT -> $norm_b"
    log_fail "TEST-017 cwd-independence"
  fi
}

# --- TEST-018 — script-location default root (no --root, copy in fixture) --
test_018_script_location_default_root() {
  local fixture out
  fixture="$(new_bare_fixture t018)"
  add_core_and_role_files "$fixture"
  install_doctor_copy "$fixture"
  out="$(cd "$TMP_ROOT" && node "$fixture/.aai/scripts/aai-doctor.mjs" 2>&1)"
  if dr_line_hit "$out" '^CAT-01 PASS'; then
    log_pass "TEST-018 default root resolves from the invoked script's own location, no --root needed"
  else
    log_info "TEST-018: got: $(echo "$out" | grep '^CAT-01')"
    log_fail "TEST-018 script-location default root"
  fi
}

# --- TEST-019 — real-repo smoke: no crash, no unexpected FAIL (Spec-AC-03) --
test_019_real_repo_smoke() {
  local out rc
  out="$(node "$DOCTOR" 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 && "$rc" -ne 1 ]]; then
    log_info "TEST-019: unexpected exit $rc (want 0 or 1, never a crash)"
    log_fail "TEST-019 real-repo smoke exit code"
    return
  fi
  if ! dr_line_hit "$out" '^DOCTOR '; then
    log_info "TEST-019: no DOCTOR verdict line in output: $out"
    log_fail "TEST-019 real-repo smoke verdict line"
    return
  fi
  if echo "$out" | grep -E "^CAT-01 FAIL|^CAT-02 FAIL"; then
    log_info "TEST-019: real repo unexpectedly fails core-file/role-prompt checks: $out"
    log_fail "TEST-019 real-repo smoke unexpected FAIL"
    return
  fi
  log_pass "TEST-019 real-repo smoke (no crash, DOCTOR verdict present, no unexpected FAIL)"
}

# --- TEST-020 — CLI usage errors exit 2 --------------------------------------
test_020_usage_errors() {
  local rc
  node "$DOCTOR" --bogus-flag >/dev/null 2>&1; rc=$?
  if [[ "$rc" -ne 2 ]]; then
    log_info "TEST-020a: unknown flag expected exit 2, got $rc"
    log_fail "TEST-020a usage error exit code"
    return
  fi
  node "$DOCTOR" --root >/dev/null 2>&1; rc=$?
  if [[ "$rc" -eq 2 ]]; then
    log_pass "TEST-020 CLI usage errors exit 2 (unknown flag, missing --root value)"
  else
    log_info "TEST-020b: --root without a value expected exit 2, got $rc"
    log_fail "TEST-020b missing-value usage error"
  fi
}

# --- TEST-021 — SKILL_DOCTOR.prompt.md thin wrapper (Spec-AC-02) ------------
test_021_skill_doctor_thin_wrapper() {
  local f="$PROJECT_ROOT/.aai/SKILL_DOCTOR.prompt.md" n
  [[ -f "$f" ]] || { log_fail "TEST-021 SKILL_DOCTOR.prompt.md not found"; return; }
  n=$(wc -l < "$f" | tr -d ' ')
  local ok=1
  if [[ "$n" -gt 100 ]]; then
    log_info "TEST-021: $f is $n lines (> 100, not a thin wrapper)"
    ok=0
  fi
  grep -qF "aai-doctor.mjs" "$f" || { log_info "TEST-021: does not name aai-doctor.mjs"; ok=0; }
  grep -qi "check-state" "$f" || { log_info "TEST-021: no pointer to /aai-check-state for the full invariant report"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-021 SKILL_DOCTOR.prompt.md is a thin wrapper ($n lines)" \
    || log_fail "TEST-021 SKILL_DOCTOR.prompt.md thin-wrapper shape"
}

# --- TEST-022 — suite-map.yaml has an aai-doctor row (hygiene pin) ----------
test_022_suite_map_row() {
  local map="$PROJECT_ROOT/tests/skills/suite-map.yaml"
  if grep -qE "^  aai-doctor:" "$map"; then
    log_pass "TEST-022 suite-map.yaml has an aai-doctor row"
  else
    log_fail "TEST-022 suite-map.yaml missing aai-doctor row"
  fi
}

# =============================================================================
# CHANGE-0135 / spec-doctor-win-selftest — CAT-14/CAT-15/CAT-16 additions.
# New-spec Test Plan TEST-001..015; TEST-002/004/006/007 are Pester (this
# host's macOS/Linux run stays on the SKIP branch of CAT-14/15, so their real
# behavior is unit-tested at the ps1 layer in aai-win-dispatch.Tests.ps1, not
# here) and TEST-015 lives in test-aai-win-fallback.sh (skip-budget pin).
# =============================================================================

# --- TEST-023 (Spec-AC-01) — CAT-14 SKIP off Windows, detail.spawned=false --
test_023_win_selftest_skip_off_windows() {
  local out rc
  out="$(node "$DOCTOR" --root "$PROJECT_ROOT" --json 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_info "TEST-023: rc=$rc (want 0 on the real repo)"
    log_fail "TEST-023 CAT-14 off-Windows SKIP contract"
    return
  fi
  echo "$out" | node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const c14 = j.categories.find(x => x.id === "CAT-14");
      if (!c14) die("CAT-14 missing");
      if (c14.status !== "SKIP") die("expected SKIP off Windows, got " + c14.status);
      if (!/not.*windows/i.test(c14.reason)) die("reason does not name the not-a-Windows-host precondition: " + c14.reason);
      if (!c14.detail || c14.detail.spawned !== false) die("detail.spawned must be false: " + JSON.stringify(c14.detail));
    });
  ' && log_pass "TEST-023 CAT-14 SKIP off Windows, detail.spawned=false, exit 0" \
    || log_fail "TEST-023 CAT-14 off-Windows SKIP contract"
}

# --- TEST-024 (Spec-AC-01) — structural arm pins on aai-win-selftest.ps1 ----
test_024_selftest_structural_arm_pins() {
  local f="$PROJECT_ROOT/.aai/scripts/aai-win-selftest.ps1"
  if [[ ! -f "$f" ]]; then
    log_fail "TEST-024 aai-win-selftest.ps1 not found"
    return
  fi
  local ok=1
  grep -qF 'RedirectStandardOutput' "$f" || { log_info "TEST-024: no RedirectStandardOutput"; ok=0; }
  grep -qF 'RedirectStandardError' "$f" || { log_info "TEST-024: no RedirectStandardError"; ok=0; }

  # .Handle discarded on the statement immediately after the Start-Process
  # assignment. Collapse backtick line-continuations first so the check sees
  # the logical statement boundary, not a physical-line artifact.
  local collapsed
  collapsed="$(node -e 'const fs=require("fs");process.stdout.write(fs.readFileSync(process.argv[1],"utf8").replace(/`\r?\n[ \t]*/g," "))' "$f")"
  if ! printf '%s\n' "$collapsed" | awk '
    /\$proc = Start-Process/ { want=1; next }
    want { if ($0 ~ /\$null = \$proc\.Handle/) { found=1 } want=0 }
    END { exit(found ? 0 : 1) }
  '; then
    log_info "TEST-024: \$null = \$proc.Handle does not immediately follow the Start-Process assignment"
    ok=0
  fi

  # Every AAI_TEST_TIMEOUT assignment lives inside the inner-script text
  # (backtick-escaped), never a live assignment executed on the calling
  # process — i.e. each arm sets its own environment in the spawned engine's
  # command text rather than relying on inheritance.
  local total escaped
  total="$(grep -cF '$env:AAI_TEST_TIMEOUT' "$f")"
  escaped="$(grep -cF '`$env:AAI_TEST_TIMEOUT' "$f")"
  if [[ "$total" -eq 0 || "$total" -ne "$escaped" ]]; then
    log_info "TEST-024: AAI_TEST_TIMEOUT total=$total escaped=$escaped (want equal and > 0)"
    ok=0
  fi

  # Never a Move-Item/Rename-Item, and Remove-Item never targets the decoy
  # bash path — the host Git installation can never be mutated. Comment
  # lines are stripped first so this pin checks CODE, not prose describing
  # the guarantee (a full-line '#' comment never counts as a violation).
  local code_only
  code_only="$(grep -vE '^\s*#' "$f")"
  dr_line_hit "$code_only" 'Move-Item|Rename-Item' \
    && { log_info "TEST-024: Move-Item/Rename-Item present in code"; ok=0; }
  dr_line_hit "$code_only" 'Remove-Item.*[Dd]ecoy[Bb]ash' \
    && { log_info "TEST-024: Remove-Item applied to the decoy bash path"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-024 structural arm pins (redirect + Handle + env-in-child-text + no mutate)" \
    || log_fail "TEST-024 structural arm pins"
}

# --- TEST-025 (Spec-AC-02) — REUSE structural pin ---------------------------
test_025_selftest_reuse_structural_pin() {
  local f="$PROJECT_ROOT/.aai/scripts/aai-win-selftest.ps1"
  if [[ ! -f "$f" ]]; then
    log_fail "TEST-025 aai-win-selftest.ps1 not found"
    return
  fi
  local ok=1

  # Dot-sources the wrapper exactly once, at unindented file/top-level scope.
  local dotcount
  dotcount="$(grep -cE "^\\. \\(Join-Path \\\$PSScriptRoot 'aai-run-tests\\.ps1'\\)" "$f")"
  [[ "$dotcount" -eq 1 ]] || { log_info "TEST-025: file-scope dot-source count=$dotcount (want 1)"; ok=0; }

  # Same-shaped direct-invocation guard as the wrapper.
  grep -qF "\$MyInvocation.InvocationName -ne '.'" "$f" \
    || { log_info "TEST-025: no direct-invocation guard of the wrapper's shape"; ok=0; }

  # References the wrapper's own probe functions, defines none of them.
  # F7: the redefinition check is anchored to allow leading whitespace
  # (`^\s*function `) -- an unanchored `^function ` is evaded by an indented
  # `  function Test-WslPresent { ... }`, which still silently shadows the
  # wrapper's real function inside a Pester block scope. Wait-ProcessWithTimeout
  # joins this pin list: the file's own header claims it calls that wrapper
  # function (it does, at the Invoke-SelfTestChildEngine wait), so a rename in
  # aai-run-tests.ps1 must break this probe with a POSIX-reachable signal.
  local fn
  for fn in Test-WslPresent Test-WslUsable Get-GitBashCandidates Find-GitBash \
            Get-ProcessEnvironmentSnapshot Get-CanonicalEnvironmentMap \
            Wait-ProcessWithTimeout; do
    grep -qF "$fn" "$f" || { log_info "TEST-025: does not reference $fn"; ok=0; }
    grep -qE "^\\s*function $fn\\b" "$f" && { log_info "TEST-025: redefines $fn"; ok=0; }
  done

  # No second Git-Bash candidate literal, no second System32 shim pattern,
  # and Set-CanonicalProcessEnvironment (the MUTATING call) is never named.
  grep -qF -- 'Git\bin\bash.exe' "$f" && { log_info "TEST-025: duplicates the Git-Bash candidate literal"; ok=0; }
  grep -qE 'System32.{0,3}bash' "$f" && { log_info "TEST-025: duplicates the System32 bash-shim pattern"; ok=0; }
  grep -qF -- 'Set-CanonicalProcessEnvironment' "$f" && { log_info "TEST-025: names Set-CanonicalProcessEnvironment"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-025 REUSE structural pin (dot-source once, guard shape, no redefinition, no mutation)" \
    || log_fail "TEST-025 REUSE structural pin"
}

# --- TEST-026 (Spec-AC-03) — CAT-16 fake-CLI PRESENT + empty-PATH ABSENT ---
test_026_agent_cli_probe_fake_and_absent() {
  local fakebin="$TMP_ROOT/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/claude" <<'EOF'
#!/bin/sh
echo "claude-fixture-version-9.9.9"
EOF
  chmod +x "$fakebin/claude"

  local out rc1
  out="$(PATH="$fakebin:$PATH" node "$DOCTOR" --json 2>&1)"
  echo "$out" | node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const c16 = j.categories.find(x => x.id === "CAT-16");
      if (!c16) die("CAT-16 missing");
      const claude = c16.detail.clis.claude;
      // CHANGE-0138 (Spec-AC-02): the record is the D2 tri-state — strict
      // present === true, verbatim version, reason null.
      if (!claude || claude.present !== true || claude.version !== "claude-fixture-version-9.9.9") {
        die("claude not PRESENT with the fixture version: " + JSON.stringify(claude));
      }
      if (claude.reason !== null) die("a versioned CLI must carry reason null: " + JSON.stringify(claude));
    });
  '
  rc1=$?

  # Resolve node's OWN absolute path first: PATH="" must empty the PATH the
  # SPAWNED doctor process sees for its own child-CLI resolution, without
  # also breaking this shell's ability to exec node itself (a bare "node"
  # command name needs PATH to be found at all).
  local node_bin
  node_bin="$(command -v node)"
  local out2 rc2
  out2="$(PATH="" "$node_bin" "$DOCTOR" --json 2>&1)"
  echo "$out2" | node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const clis = j.categories.find(x => x.id === "CAT-16").detail.clis;
      for (const name of ["claude", "codex", "gemini"]) {
        // CHANGE-0138 (Spec-AC-02): absent is the strict tri-state shape —
        // present false (never a truthy stand-in), version null, named reason.
        if (clis[name].present !== false) die(name + " unexpectedly PRESENT with an empty PATH: " + JSON.stringify(clis[name]));
        if (clis[name].version !== null) die(name + " unexpectedly carries a version with an empty PATH: " + clis[name].version);
        if (clis[name].reason !== "not found on PATH") die(name + " absent record must carry the not-found-on-PATH reason: " + JSON.stringify(clis[name]));
      }
    });
  '
  rc2=$?

  if [[ "$rc1" -eq 0 && "$rc2" -eq 0 ]]; then
    log_pass "TEST-026 CAT-16 fake-CLI PRESENT (verbatim version) + empty-PATH ABSENT (no invented version)"
  else
    log_fail "TEST-026 CAT-16 fake-CLI/empty-PATH fixtures"
  fi
}

# --- TEST-027 (Spec-AC-03) — four capability fields literal UNKNOWN --------
test_027_capability_fields_unknown() {
  local out
  out="$(node "$DOCTOR" --json 2>&1)"
  echo "$out" | node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const c16 = j.categories.find(x => x.id === "CAT-16");
      const caps = c16.detail.capabilities;
      const names = ["multi_agent_backend", "spawn_agent_available", "spawn_model_catalog", "fork_turns_supported"];
      for (const n of names) {
        if (!caps[n]) die("missing capability field " + n);
        if (caps[n].value !== "UNKNOWN") die(n + " must be the literal UNKNOWN, got " + JSON.stringify(caps[n].value));
        if (!/runtime/i.test(caps[n].reason) || !/agent session/i.test(caps[n].reason)) {
          die(n + " reason does not mention runtime resolution inside an agent session: " + caps[n].reason);
        }
      }
      if (c16.detail.codex_exec_subcommand === undefined) die("codex_exec_subcommand missing (must be its own separate key)");
      if (Object.prototype.hasOwnProperty.call(caps, "codex_exec_subcommand")) die("codex exec observation leaked into the capabilities object");
    });
  ' && log_pass "TEST-027 four capability fields literal UNKNOWN + codex_exec_subcommand as its own key" \
    || log_fail "TEST-027 capability fields UNKNOWN contract"
}

# --- TEST-028 (Spec-AC-04) — output shape: one line each, --json detail,
#     CAT-01..13 unchanged, categories grow 13 -> 17 on a clean fixture ------
test_028_output_shape_growth() {
  local out
  out="$(node "$DOCTOR" --root "$PROJECT_ROOT" 2>&1)"
  local c14 c15 c16
  c14="$(echo "$out" | grep -c '^CAT-14 ')"
  c15="$(echo "$out" | grep -c '^CAT-15 ')"
  c16="$(echo "$out" | grep -c '^CAT-16 ')"
  if [[ "$c14" -ne 1 || "$c15" -ne 1 || "$c16" -ne 1 ]]; then
    log_info "TEST-028: text-mode line counts CAT-14=$c14 CAT-15=$c15 CAT-16=$c16 (want 1 each)"
    log_fail "TEST-028 output shape: one line each"
    return
  fi

  local fixture jout
  fixture="$(build_clean_fixture clean-028)"
  jout="$(node "$fixture/.aai/scripts/aai-doctor.mjs" --json 2>&1)"
  echo "$jout" | node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      if (j.categories.length !== 18) die("categories.length=" + j.categories.length + " (want 18)");
      for (let i = 1; i <= 13; i++) {
        const id = "CAT-" + String(i).padStart(2, "0");
        const c = j.categories.find(x => x.id === id);
        if (!c || c.status !== "PASS") die(id + " changed on the clean fixture: " + JSON.stringify(c));
      }
      for (const id of ["CAT-14", "CAT-15", "CAT-16"]) {
        const c = j.categories.find(x => x.id === id);
        if (!c || typeof c.detail !== "object" || c.detail === null) die(id + " missing a structured detail object under --json");
      }
    });
  ' && log_pass "TEST-028 output shape: one line each, --json detail, CAT-01..13 unchanged, 13->18 growth (CAT-18 Guard Wiring, shipped-guards-have-no-downstream-trigger)" \
    || log_fail "TEST-028 output shape growth"
}

# --- TEST-029 (Spec-AC-04) — exit matrix ------------------------------------
test_029_exit_matrix() {
  # WARN (an existing always-WARN category, CAT-04, on a bare fixture): exits
  # 0 without --strict, 1 with --strict. CAT-14/CAT-15 cannot be forced into
  # WARN off Windows (D6 makes them SKIP there), so this reuses an existing
  # WARN category to exercise the matrix — the --strict LOGIC under test
  # (any WARN or FAIL -> 1) does not care which category produced the WARN.
  local fixture rc rc_strict
  fixture="$(new_bare_fixture t029-warn)"
  add_core_and_role_files "$fixture"
  node "$DOCTOR" --root "$fixture" >/dev/null 2>&1; rc=$?
  node "$DOCTOR" --root "$fixture" --strict >/dev/null 2>&1; rc_strict=$?
  if [[ "$rc" -ne 0 || "$rc_strict" -ne 1 ]]; then
    log_info "TEST-029a: rc=$rc rc_strict=$rc_strict (want 0 then 1)"
    log_fail "TEST-029a WARN matrix"
    return
  fi

  # SKIP-only fixture (the clean fixture: its only non-PASS categories on
  # this host are CAT-14/CAT-15 SKIP): --strict still exits 0.
  local fixture2 rc2_strict
  fixture2="$(build_clean_fixture clean-029)"
  node "$fixture2/.aai/scripts/aai-doctor.mjs" --strict >/dev/null 2>&1; rc2_strict=$?
  if [[ "$rc2_strict" -ne 0 ]]; then
    log_info "TEST-029b: --strict on a SKIP-only fixture exited $rc2_strict (want 0)"
    log_fail "TEST-029b SKIP-only --strict"
    return
  fi

  # A genuine CAT-01 FAIL still exits 1 without --strict.
  local fixture3 rc3
  fixture3="$(new_bare_fixture t029-fail)"
  mkdir -p "$fixture3/.aai" "$fixture3/docs/ai"
  : > "$fixture3/.aai/PLAYBOOK.md"
  node "$DOCTOR" --root "$fixture3" >/dev/null 2>&1; rc3=$?
  if [[ "$rc3" -ne 1 ]]; then
    log_info "TEST-029c: FAIL fixture without --strict exited $rc3 (want 1)"
    log_fail "TEST-029c FAIL fixture exit"
    return
  fi

  # An unknown flag still exits 2.
  local rc4
  node "$DOCTOR" --nope >/dev/null 2>&1; rc4=$?
  if [[ "$rc4" -ne 2 ]]; then
    log_info "TEST-029d: unknown flag exited $rc4 (want 2)"
    log_fail "TEST-029d usage error exit"
    return
  fi

  log_pass "TEST-029 exit matrix: WARN 0/--strict 1, SKIP-only --strict 0, FAIL 1, usage error 2"
}

# --- TEST-030 (Spec-AC-04) — zero-network / zero-LLM pin --------------------
test_030_zero_network_pin() {
  local tokens=("fetch(" "node:http" "require('http')" "node:https" "require('https')" \
    "Invoke-WebRequest" "Invoke-RestMethod" "curl " "wget " "git fetch" "git ls-remote" "git clone")
  local files=("$PROJECT_ROOT/.aai/scripts/aai-doctor.mjs" "$PROJECT_ROOT/.aai/scripts/aai-win-selftest.ps1")
  local ok=1 f t
  for f in "${files[@]}"; do
    for t in "${tokens[@]}"; do
      if grep -qF -- "$t" "$f"; then
        log_info "TEST-030: $f references a network/LLM token: $t"
        ok=0
      fi
    done
  done
  [[ $ok -eq 1 ]] && log_pass "TEST-030 zero-network/zero-LLM pin (aai-doctor.mjs + aai-win-selftest.ps1)" \
    || log_fail "TEST-030 zero-network pin"
}

# --- TEST-031 (Spec-AC-05) — hygiene set ------------------------------------
test_031_hygiene_set() {
  local ok=1 tmp

  tmp="$(mktemp "${TMPDIR:-/tmp}/aai-doctor-ctr.XXXXXX")"
  if ! node "$PROJECT_ROOT/.aai/scripts/check-test-registration.mjs" >"$tmp" 2>&1; then
    log_info "TEST-031: check-test-registration.mjs reported orphans: $(cat "$tmp")"
    ok=0
  fi
  rm -f "$tmp"

  grep -qF '.aai/scripts/aai-win-selftest.ps1' "$PROJECT_ROOT/tests/skills/suite-map.yaml" \
    || { log_info "TEST-031: suite-map.yaml aai-doctor row missing aai-win-selftest.ps1"; ok=0; }
  grep -qF 'tests/skills/aai-win-dispatch.Tests.ps1' "$PROJECT_ROOT/tests/skills/suite-map.yaml" \
    || { log_info "TEST-031: suite-map.yaml aai-doctor row missing aai-win-dispatch.Tests.ps1"; ok=0; }

  local profcount
  profcount="$(grep -cF '.aai/scripts/aai-win-selftest.ps1' "$PROJECT_ROOT/.aai/system/PROFILES.yaml")"
  [[ "$profcount" -eq 1 ]] || { log_info "TEST-031: PROFILES.yaml lists aai-win-selftest.ps1 $profcount time(s) (want 1)"; ok=0; }

  tmp="$(mktemp "${TMPDIR:-/tmp}/aai-doctor-lp.XXXXXX")"
  if ! bash "$PROJECT_ROOT/tests/skills/test-aai-layer-profiles.sh" >"$tmp" 2>&1; then
    log_info "TEST-031: test-aai-layer-profiles.sh failed: $(tail -20 "$tmp")"
    ok=0
  fi
  rm -f "$tmp"

  tmp="$(mktemp "${TMPDIR:-/tmp}/aai-doctor-ss.XXXXXX")"
  if ! bash "$PROJECT_ROOT/tests/skills/test-aai-suite-select.sh" >"$tmp" 2>&1; then
    log_info "TEST-031: test-aai-suite-select.sh failed: $(tail -20 "$tmp")"
    ok=0
  fi
  rm -f "$tmp"

  [[ $ok -eq 1 ]] && log_pass "TEST-031 hygiene set: registration clean, suite-map row, PROFILES entry once, layer-profiles/suite-select green" \
    || log_fail "TEST-031 hygiene set"
}

# --- TEST-032 (Spec-AC-05) — documentation pin ------------------------------
test_032_documentation_pin() {
  local ok=1
  local pdoc="$PROJECT_ROOT/docs/product/aai-doctor.md"
  if [[ ! -f "$pdoc" ]]; then
    log_info "TEST-032: $pdoc does not exist"
    ok=0
  else
    local sec
    for sec in "## What it does" "## How to use it" "## Data model" "## Interfaces and contracts" "## Limits and non-goals"; do
      grep -qF -- "$sec" "$pdoc" || { log_info "TEST-032: $pdoc missing section: $sec"; ok=0; }
    done
    grep -qi 'self-test' "$pdoc" || { log_info "TEST-032: $pdoc does not mention the self-test"; ok=0; }
    grep -qiE 'does not prove|cannot prove|never proves|not prove' "$pdoc" \
      || { log_info "TEST-032: $pdoc does not state what the self-test does NOT prove"; ok=0; }
    # CHANGE-0138 (Spec-AC-06): the doc tells the new CAT-16 truths — the
    # tri-state presence record, the unknown-vs-absent count line, and the
    # honest no-Commands:-block UNKNOWN for the codex exec observation.
    grep -qi 'tri-state' "$pdoc" || { log_info "TEST-032: $pdoc does not document the tri-state presence record"; ok=0; }
    grep -qF 'without version' "$pdoc" || { log_info "TEST-032: $pdoc does not document the without-version count segment"; ok=0; }
    grep -qiE 'unknown.*(never|not).*(absent|present)|absent.*(never|not).*unknown|distinguish' "$pdoc" \
      || { log_info "TEST-032: $pdoc does not state the unknown-vs-absent line semantics"; ok=0; }
    grep -qF 'no Commands: block' "$pdoc" \
      || { log_info "TEST-032: $pdoc does not document the honest no-Commands:-block UNKNOWN"; ok=0; }
  fi

  grep -qF '/aai-doctor' "$PROJECT_ROOT/docs/USER_GUIDE.md" || { log_info "TEST-032: USER_GUIDE.md missing /aai-doctor"; ok=0; }
  grep -qF -- '--strict' "$PROJECT_ROOT/docs/USER_GUIDE.md" || { log_info "TEST-032: USER_GUIDE.md missing --strict"; ok=0; }
  grep -qF 'UNKNOWN' "$PROJECT_ROOT/docs/USER_GUIDE.md" || { log_info "TEST-032: USER_GUIDE.md missing the UNKNOWN capability-reporting note"; ok=0; }

  # Release-tolerant: /aai-release legitimately rolls unreleased headings
  # into a '## [vYYYY.MM.DD...]' section at cut time (the v2026.08.13 release
  # rolled the doctor entries; an unreleased-only pin rots at every release).
  grep -qE '^## \[(unreleased|v[0-9][^]]*)\] — .*[Dd]octor' "$PROJECT_ROOT/CHANGELOG.md" \
    || { log_info "TEST-032: CHANGELOG.md missing an own-heading entry for this scope"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-032 documentation pin: product doc sections, USER_GUIDE, CHANGELOG heading" \
    || log_fail "TEST-032 documentation pin"
}

# --- TEST-033 (F4, Spec-AC-03) — codex exec detection is not fooled by prose,
#     and still fires on a real command-list line -----------------------------
# CHANGE-0138 (Spec-AC-01): the prose-only fixture has NO Commands: block, so
# the D1 block parse honestly reports UNKNOWN there — the old pin expected
# false, which the line-shape heuristic could only fabricate. The positive
# command-list fixture stays available:true.
test_033_codex_exec_detection_honesty() {
  local fakebin="$TMP_ROOT/fakebin-exec"
  mkdir -p "$fakebin"

  # Negative fixture: --help PROSE that merely contains the word "exec" in a
  # sentence and carries no Commands:/Subcommands: block at all. The D1
  # block-anchored parse reports the honest UNKNOWN (prose can never produce
  # a boolean either way).
  cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "codex-fixture-1.0.0"
  exit 0
fi
cat <<'HELP'
codex-fixture 1.0.0
This tool will never exec anything on your behalf without confirmation.
HELP
exit 0
EOF
  chmod +x "$fakebin/codex"

  local out rc1
  out="$(PATH="$fakebin:$PATH" node "$DOCTOR" --json 2>&1)"
  node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const c16 = j.categories.find(x => x.id === "CAT-16");
      const obs = c16.detail.codex_exec_subcommand;
      if (obs.available !== "UNKNOWN") die("prose-only help with no Commands: block must be UNKNOWN: " + JSON.stringify(obs));
      if (!/no Commands: block/.test(obs.reason || "")) die("UNKNOWN reason must name the missing Commands: block: " + JSON.stringify(obs));
    });
  ' <<<"$out"
  rc1=$?

  # Positive fixture: a real command-list line (`Usage:` + `Commands:` shape),
  # line-anchored, two-space-indented -- the shape F4 anchors to.
  cat > "$fakebin/codex" <<'EOF'
#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "codex-fixture-1.0.0"
  exit 0
fi
cat <<'HELP'
Usage: codex [OPTIONS] <COMMAND>

Commands:
  exec         Run Codex non-interactively
  login        Manage login
HELP
exit 0
EOF
  chmod +x "$fakebin/codex"

  local out2 rc2
  out2="$(PATH="$fakebin:$PATH" node "$DOCTOR" --json 2>&1)"
  node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const c16 = j.categories.find(x => x.id === "CAT-16");
      const obs = c16.detail.codex_exec_subcommand;
      if (obs.available !== true) die("real command-list line did not register available=true: " + JSON.stringify(obs));
    });
  ' <<<"$out2"
  rc2=$?

  if [[ "$rc1" -eq 0 && "$rc2" -eq 0 ]]; then
    log_pass "TEST-033 codex exec detection: honest UNKNOWN on prose-only help, fires on a real Commands: block (true)"
  else
    log_fail "TEST-033 codex exec detection honesty"
  fi
}

# --- TEST-034 (F9, Spec-AC-01) — CAT-14 WARN branch, exercised for real ------
test_034_cat14_warn_branch_and_strict() {
  # D6 gates CAT-14 on process.platform === 'win32', which this suite cannot
  # be (it must run off Windows too). A `--import` ESM preload flips
  # process.platform for a genuinely spawned doctor child process only --
  # nothing here mocks catWinSelfTest's mapping logic. On this host (no WSL,
  # no Windows Git Bash) the real .aai/scripts/aai-win-selftest.ps1 probe then
  # genuinely runs and genuinely produces a non-all-PASS report (the same
  # named edge case D3/D6 document: success/timeout arms hit the wrapper's
  # own AAI-ENV-ERROR exit 78), giving CAT-14 status WARN for real -- the
  # highest-value untested branch (a permanently degraded CAT-14 would
  # otherwise read green in CI forever, per the validation report's F9).
  local preload="$TMP_ROOT/aai-platform-preload.mjs"
  cat > "$preload" <<'EOF'
Object.defineProperty(process, 'platform', { value: 'win32', configurable: true });
EOF

  local out rc
  out="$(node --import "$preload" "$DOCTOR" --json 2>&1)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    log_info "TEST-034: plain run rc=$rc (want 0 on a WARN-only categories set)"
    log_fail "TEST-034 CAT-14 WARN branch"
    return
  fi
  echo "$out" | node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const c14 = j.categories.find(x => x.id === "CAT-14");
      if (!c14) die("CAT-14 missing");
      if (c14.status !== "WARN") die("expected WARN on this no-WSL/no-Git-Bash host, got " + c14.status + ": " + JSON.stringify(c14));
      if (c14.detail.spawned !== true) die("detail.spawned must be true (the probe genuinely ran): " + JSON.stringify(c14.detail));
      if (c14.detail.failed !== true) die("detail.failed must be true: " + JSON.stringify(c14.detail));
      if (!Array.isArray(c14.detail.arms) || c14.detail.arms.length !== 3) die("expected 3 real arm results: " + JSON.stringify(c14.detail.arms));
    });
  '
  local rc_shape=$?

  local rc_strict
  node --import "$preload" "$DOCTOR" --strict >/dev/null 2>&1; rc_strict=$?

  if [[ "$rc_shape" -eq 0 && "$rc_strict" -eq 1 ]]; then
    log_pass "TEST-034 CAT-14 WARN branch exercised for real (genuine spawn, non-all-PASS arms) + --strict exit 1"
  else
    log_info "TEST-034: rc_shape=$rc_shape rc_strict=$rc_strict (want 0 then 1)"
    log_fail "TEST-034 CAT-14 WARN branch and --strict"
  fi
}

# =============================================================================
# CHANGE-0138 / spec-doctor-honesty-batch — CAT-16 honesty: D1 Commands:-block
# parse (0138-TEST-001), D2 version-probe tri-state (0138-TEST-002), the
# unknown-vs-absent count line (0138-TEST-003). All fixtures drive the REAL
# doctor via PATH-injected fake CLIs; new assertions use here-strings, never
# echo|grep pipes (LEARNED shell-options rule).
# =============================================================================

# Shared fast fake CLI writer: a shell stub that prints <version> for
# --version (empty string => prints nothing) and <helpfile>'s bytes for
# anything else (missing helpfile => prints nothing).
write_fake_cli() {
  local path="$1" version="$2" helpfile="${3:-}"
  {
    printf '#!/bin/sh\n'
    printf 'if [ "$1" = "--version" ]; then\n'
    if [[ -n "$version" ]]; then
      printf '  echo "%s"\n' "$version"
    fi
    printf '  exit 0\nfi\n'
    if [[ -n "$helpfile" ]]; then
      printf 'cat "%s"\n' "$helpfile"
    fi
    printf 'exit 0\n'
  } > "$path"
  chmod +x "$path"
}

# --- 0138-TEST-001 (Spec-AC-01) — the 11-fixture D1 block-parse battery ------
# FX-01..FX-07 are the 0135 rescope report's A..G; FX-08..FX-11 are new.
# Every fixture is a real fake-codex --help driven through the REAL doctor.
BATTERY_FAILED=0

run_battery_fixture() {
  local fx="$1" expect="$2" reasonre="$3" helpfile="$4" fakebin="$5" fixroot="$6"
  write_fake_cli "$fakebin/codex" "codex-fixture-1.0.0" "$helpfile"
  local out rc=0
  out="$(PATH="$fakebin:$PATH" node "$DOCTOR" --root "$fixroot" --json 2>&1)"
  node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const c16 = j.categories.find(x => x.id === "CAT-16");
      if (!c16) die("CAT-16 missing");
      const obs = c16.detail.codex_exec_subcommand;
      const expect = process.argv[1];
      const want = expect === "true" ? true : expect === "false" ? false : "UNKNOWN";
      if (obs.available !== want) die("available=" + JSON.stringify(obs.available) + " want " + expect + " (reason: " + obs.reason + ")");
      if (!new RegExp(process.argv[2]).test(obs.reason || "")) die("reason class mismatch: " + JSON.stringify(obs.reason));
      if (c16.status !== "PASS") die("CAT-16 must stay PASS-only on every fixture, got " + c16.status);
    });
  ' "$expect" "$reasonre" <<<"$out" || rc=1
  if [[ "$rc" -eq 0 ]]; then
    log_info "0138-TEST-001 $fx -> $expect (ok)"
  else
    log_info "0138-TEST-001 $fx: expected $expect, assertion failed (see above)"
    BATTERY_FAILED=1
  fi
}

test_035_0138_codex_exec_block_battery() {
  local fakebin="$TMP_ROOT/fakebin-0138-battery" fxdir="$TMP_ROOT/fx-0138" fixroot="$TMP_ROOT/fx-0138-root"
  mkdir -p "$fakebin" "$fxdir" "$fixroot"
  # Fast fake claude/gemini so no battery run ever probes a real CLI.
  write_fake_cli "$fakebin/claude" "claude-fixture-1.0.0"
  write_fake_cli "$fakebin/gemini" "gemini-fixture-1.0.0"

  # FX-01 (was A): prose-only help, 4-space-indented line starting `exec` plus
  # two spaces, no Commands: header -> UNKNOWN (was the false positive).
  printf 'codex-fixture 1.0.0\n\nBehavior notes:\n    exec  is mentioned here purely as prose\n' > "$fxdir/fx01.txt"
  # FX-02 (was B): real clap Commands: block, 2-space indent, column-aligned.
  printf 'Usage: codex [OPTIONS] <COMMAND>\n\nCommands:\n  exec         Run Codex non-interactively\n  login        Manage login\n' > "$fxdir/fx02.txt"
  # FX-03 (was C): Commands: block, TAB separator after `exec` (was the false
  # negative).
  printf 'Usage: codex [OPTIONS] <COMMAND>\n\nCommands:\n  exec\tRun Codex non-interactively\n  login\tManage login\n' > "$fxdir/fx03.txt"
  # FX-04 (was D): Commands: block, single-space separator (was the false
  # negative).
  printf 'Commands:\n  exec Run Codex non-interactively\n  login Manage login\n' > "$fxdir/fx04.txt"
  # FX-05 (was E): Commands: block listing run/login only, no exec anywhere.
  printf 'Commands:\n  run     Run something once\n  login   Manage login\n' > "$fxdir/fx05.txt"
  # FX-06 (was F): the filed unindented prose sentence containing `exec`,
  # above a Commands: block that lacks exec.
  printf 'This tool will never exec anything on your behalf.\n\nCommands:\n  run     Run something once\n  login   Manage login\n' > "$fxdir/fx06.txt"
  # FX-07 (was G): Commands: block without exec, then a column-0 Options:
  # line, then 2-space-indented prose starting `exec` (block bounding kills
  # the second false positive).
  printf 'Commands:\n  run     Run something once\n  login   Manage login\n\nOptions:\n  exec  and eval are words we deliberately avoid.\n' > "$fxdir/fx07.txt"
  # FX-08: SUBCOMMANDS: header variant with an exec row — written with CRLF
  # line endings (the D1 parse must tolerate CRLF child output).
  printf 'USAGE: codex <SUBCOMMAND>\r\n\r\nSUBCOMMANDS:\r\n    exec    Run non-interactively\r\n    help    Print help\r\n' > "$fxdir/fx08.txt"
  # FX-09: Commands: block whose exec row is TAB-indented.
  printf 'Commands:\n\texec\tRun Codex non-interactively\n\tlogin\tManage login\n' > "$fxdir/fx09.txt"
  # FX-10: prose-only help containing exec mid-sentence, no header anywhere.
  printf 'codex-fixture 1.0.0\nThis tool will never exec anything on your behalf.\n' > "$fxdir/fx10.txt"
  # FX-11: Commands: block listing `execute` but never `exec`.
  printf 'Commands:\n  execute   Run a task\n  login     Manage login\n' > "$fxdir/fx11.txt"
  # FX-12 (review NB-1): a BLANK line inside the block must NOT end it —
  # clap groups subcommand rows with blank separators; the block is bounded
  # by the next non-empty column-0 line, so exec AFTER the blank still
  # counts. A parser simplified to stop at blank lines passes FX-01..11 but
  # false-negatives here.
  printf 'Commands:\n  login     Manage login\n\n  exec      Run non-interactively\n\nOptions:\n  -h  Help\n' > "$fxdir/fx12.txt"

  local re_true='Commands: block lists an exec subcommand'
  local re_false='Commands: block does not list an exec subcommand'
  local re_unknown='no Commands: block'
  BATTERY_FAILED=0
  run_battery_fixture FX-01 UNKNOWN "$re_unknown" "$fxdir/fx01.txt" "$fakebin" "$fixroot"
  run_battery_fixture FX-02 true    "$re_true"    "$fxdir/fx02.txt" "$fakebin" "$fixroot"
  run_battery_fixture FX-03 true    "$re_true"    "$fxdir/fx03.txt" "$fakebin" "$fixroot"
  run_battery_fixture FX-04 true    "$re_true"    "$fxdir/fx04.txt" "$fakebin" "$fixroot"
  run_battery_fixture FX-05 false   "$re_false"   "$fxdir/fx05.txt" "$fakebin" "$fixroot"
  run_battery_fixture FX-06 false   "$re_false"   "$fxdir/fx06.txt" "$fakebin" "$fixroot"
  run_battery_fixture FX-07 false   "$re_false"   "$fxdir/fx07.txt" "$fakebin" "$fixroot"
  run_battery_fixture FX-08 true    "$re_true"    "$fxdir/fx08.txt" "$fakebin" "$fixroot"
  run_battery_fixture FX-09 true    "$re_true"    "$fxdir/fx09.txt" "$fakebin" "$fixroot"
  run_battery_fixture FX-10 UNKNOWN "$re_unknown" "$fxdir/fx10.txt" "$fakebin" "$fixroot"
  run_battery_fixture FX-11 false   "$re_false"   "$fxdir/fx11.txt" "$fakebin" "$fixroot"
  run_battery_fixture FX-12 true    "$re_true"    "$fxdir/fx12.txt" "$fakebin" "$fixroot"

  if [[ "$BATTERY_FAILED" -eq 0 ]]; then
    log_pass "TEST-035 (0138-TEST-001) 12-fixture D1 battery: block-anchored verdicts, blank-line-tolerant bounding, honest no-block UNKNOWN, CAT-16 PASS-only"
  else
    log_fail "TEST-035 (0138-TEST-001) D1 block-parse battery"
  fi
}

# --- 0138-TEST-002 (Spec-AC-02) — version-probe tri-state through the doctor -
test_036_0138_cli_version_tristate() {
  local fakebin="$TMP_ROOT/fakebin-0138-tristate"
  mkdir -p "$fakebin" "$TMP_ROOT/fx-0138-root-b"
  # claude: version on STDERR only (exit 0) — present, no version, and the
  # stderr text must never be presented as a version.
  printf '#!/bin/sh\nif [ "$1" = "--version" ]; then\n  echo "claude-stderr-secret-7.7.7" >&2\n  exit 0\nfi\nexit 0\n' > "$fakebin/claude"
  chmod +x "$fakebin/claude"
  # codex: prints nothing anywhere, exits 1 — present, no version, named reason.
  printf '#!/bin/sh\nif [ "$1" = "--version" ]; then\n  exit 1\nfi\nexit 0\n' > "$fakebin/codex"
  chmod +x "$fakebin/codex"
  # gemini: a normal versioned CLI (control).
  write_fake_cli "$fakebin/gemini" "gemini-fixture-2.0.0"

  local out rc=0
  out="$(PATH="$fakebin:$PATH" node "$DOCTOR" --root "$TMP_ROOT/fx-0138-root-b" --json 2>&1)"
  node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const clis = j.categories.find(x => x.id === "CAT-16").detail.clis;
      for (const name of ["claude", "codex", "gemini"]) {
        const rec = clis[name];
        for (const field of ["present", "version", "reason"]) {
          if (!Object.prototype.hasOwnProperty.call(rec, field)) die(name + " record missing the " + field + " field: " + JSON.stringify(rec));
        }
      }
      const claude = clis.claude;
      if (claude.present !== true || claude.version !== null) die("stderr-only CLI must be present true / version null: " + JSON.stringify(claude));
      if (typeof claude.reason !== "string" || !/no stdout/.test(claude.reason)) die("stderr-only CLI must carry a named no-stdout reason: " + JSON.stringify(claude));
      if (JSON.stringify(clis).includes("claude-stderr-secret")) die("stderr diagnostic leaked into the CLI detail: " + JSON.stringify(clis));
      const codex = clis.codex;
      if (codex.present !== true || codex.version !== null) die("no-output CLI must be present true / version null: " + JSON.stringify(codex));
      if (typeof codex.reason !== "string" || !/no stdout/.test(codex.reason)) die("no-output CLI must carry a named no-stdout reason: " + JSON.stringify(codex));
      const gemini = clis.gemini;
      if (gemini.present !== true || gemini.version !== "gemini-fixture-2.0.0" || gemini.reason !== null) {
        die("versioned control CLI record wrong: " + JSON.stringify(gemini));
      }
    });
  ' <<<"$out" || rc=1
  if [[ "$rc" -eq 0 ]]; then
    log_pass "TEST-036 (0138-TEST-002) tri-state: stderr-only/no-output CLIs are present-no-version with named reasons; stderr never a version"
  else
    log_fail "TEST-036 (0138-TEST-002) version-probe tri-state"
  fi
}

# --- 0138-TEST-003 (Spec-AC-03) — CAT-16 count-line composition ---------------
test_037_0138_count_line_composition() {
  local fakebin="$TMP_ROOT/fakebin-0138-countline"
  mkdir -p "$fakebin" "$TMP_ROOT/fx-0138-root-c" "$TMP_ROOT/fx-0138-root-d"
  # One versioned claude, one no-stdout codex, one SLEEPING gemini (the
  # --version timeout arm: 5s doctor bound, honest UNKNOWN).
  write_fake_cli "$fakebin/claude" "claude-fixture-3.0.0"
  printf '#!/bin/sh\nexit 0\n' > "$fakebin/codex"
  chmod +x "$fakebin/codex"
  printf '#!/bin/sh\nif [ "$1" = "--version" ]; then\n  sleep 30\nfi\nexit 0\n' > "$fakebin/gemini"
  chmod +x "$fakebin/gemini"

  local out rc1=0
  out="$(PATH="$fakebin:$PATH" node "$DOCTOR" --root "$TMP_ROOT/fx-0138-root-c" --json 2>&1)"
  node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const c16 = j.categories.find(x => x.id === "CAT-16");
      if (c16.status !== "PASS") die("CAT-16 must stay PASS, got " + c16.status);
      if (!c16.reason.includes("2/3 agent CLI(s) present (1 without version), 1 unknown")) {
        die("count line segment wrong: " + c16.reason);
      }
      if (!c16.reason.includes("; four SUBAGENT_PROTOCOL capability fields reported UNKNOWN (")) {
        die("capability tail changed: " + c16.reason);
      }
      const gem = c16.detail.clis.gemini;
      if (gem.present !== "UNKNOWN" || gem.version !== null || !/timed out/.test(gem.reason || "")) {
        die("sleeping CLI must be the literal UNKNOWN with a timed-out reason: " + JSON.stringify(gem));
      }
    });
  ' <<<"$out" || rc1=1

  # All-versioned PATH: 3/3 with neither optional segment.
  local fakebin2="$TMP_ROOT/fakebin-0138-countline-all"
  mkdir -p "$fakebin2"
  local cli
  for cli in claude codex gemini; do
    write_fake_cli "$fakebin2/$cli" "$cli-fixture-4.0.0"
  done
  local out2 rc2=0
  out2="$(PATH="$fakebin2:$PATH" node "$DOCTOR" --root "$TMP_ROOT/fx-0138-root-d" --json 2>&1)"
  node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const c16 = j.categories.find(x => x.id === "CAT-16");
      if (!c16.reason.startsWith("3/3 agent CLI(s) present; four SUBAGENT_PROTOCOL")) {
        die("all-versioned line must be 3/3 with neither optional segment: " + c16.reason);
      }
      if (c16.reason.includes("without version") || /\d+ unknown/.test(c16.reason)) {
        die("optional segments must be absent when their counts are zero: " + c16.reason);
      }
    });
  ' <<<"$out2" || rc2=1

  if [[ "$rc1" -eq 0 && "$rc2" -eq 0 ]]; then
    log_pass "TEST-037 (0138-TEST-003) count line: 2/3 present (1 without version), 1 unknown; 3/3 clean; tail + PASS frozen"
  else
    log_fail "TEST-037 (0138-TEST-003) count-line composition"
  fi
}

# =============================================================================
# CHANGE-0139 / spec-canonical-test-invocation — CAT-16 detail gains the
# canonical_invocation tri-state contract probe (spec TEST-004 / TEST-005).
# The probe greps .aai/AGENTS.md under --root for the two allowlist prefix
# literals; carried is true / false / the literal 'UNKNOWN' with named
# reasons; CAT-16 stays PASS-only; detail under --json only; no spawn.
# =============================================================================

CANON_WIN_PREFIX='powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1'
CANON_POSIX_PREFIX='bash .aai/scripts/aai-run-tests.sh'

# Builds a core-files fixture whose .aai/AGENTS.md carries BOTH canonical
# prefix literals (the carried=true shape).
build_canonical_true_fixture() {
  local name="$1" d
  d="$(new_bare_fixture "$name")"
  add_core_and_role_files "$d"
  {
    printf '# Agent Guide fixture\n\n### Canonical test invocation\n\n'
    printf -- '- Windows: `%s <command...>`\n' "$CANON_WIN_PREFIX"
    printf -- '- POSIX: `%s <command...>`\n' "$CANON_POSIX_PREFIX"
  } > "$d/.aai/AGENTS.md"
  echo "$d"
}

# --- TEST-038 (0139-TEST-004, Spec-AC-03) — probe fixture matrix -------------
test_038_0139_canonical_invocation_fixtures() {
  local fx_true fx_false fx_absent out rc1=0 rc2=0 rc3=0

  # Fixture 1: AGENTS.md carries BOTH prefix literals -> carried === true.
  fx_true="$(build_canonical_true_fixture t038-true)"
  out="$(node "$DOCTOR" --root "$fx_true" --json 2>&1)"
  node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const c16 = j.categories.find(x => x.id === "CAT-16");
      if (!c16) die("CAT-16 missing");
      const ci = c16.detail && c16.detail.canonical_invocation;
      if (!ci) die("detail.canonical_invocation missing: " + JSON.stringify(c16.detail));
      if (ci.file !== ".aai/AGENTS.md") die("file must be .aai/AGENTS.md: " + JSON.stringify(ci));
      if (ci.carried !== true) die("both-literals fixture must report carried true: " + JSON.stringify(ci));
      if (c16.status !== "PASS") die("CAT-16 must stay PASS-only, got " + c16.status);
    });
  ' <<<"$out" || rc1=1

  # Fixture 2: AGENTS.md readable but the WINDOWS literal is missing ->
  # carried === false with a reason naming the /aai-update remedy.
  fx_false="$(new_bare_fixture t038-false)"
  add_core_and_role_files "$fx_false"
  printf 'POSIX only: `%s <command...>`\n' "$CANON_POSIX_PREFIX" > "$fx_false/.aai/AGENTS.md"
  out="$(node "$DOCTOR" --root "$fx_false" --json 2>&1)"
  node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const c16 = j.categories.find(x => x.id === "CAT-16");
      const ci = c16.detail && c16.detail.canonical_invocation;
      if (!ci) die("detail.canonical_invocation missing");
      if (ci.carried !== false) die("missing-Windows-literal fixture must report carried false: " + JSON.stringify(ci));
      if (typeof ci.reason !== "string" || !ci.reason.includes("/aai-update")) {
        die("carried-false reason must name the /aai-update remedy: " + JSON.stringify(ci));
      }
      if (!/missing/i.test(ci.reason)) die("carried-false reason must name the missing contract: " + JSON.stringify(ci));
      if (c16.status !== "PASS") die("CAT-16 must stay PASS-only, got " + c16.status);
    });
  ' <<<"$out" || rc2=1

  # Fixture 3: no .aai/AGENTS.md at all -> carried === the literal UNKNOWN
  # with a reason (honest degrade, never a fabricated false). CAT-01 FAILs on
  # this fixture (doctor exit 1) — the probe's verdict is read from --json
  # regardless.
  fx_absent="$(new_bare_fixture t038-absent)"
  add_core_and_role_files "$fx_absent"
  rm -f "$fx_absent/.aai/AGENTS.md"
  out="$(node "$DOCTOR" --root "$fx_absent" --json 2>&1)"
  node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const c16 = j.categories.find(x => x.id === "CAT-16");
      const ci = c16.detail && c16.detail.canonical_invocation;
      if (!ci) die("detail.canonical_invocation missing");
      if (ci.carried !== "UNKNOWN") die("absent-file fixture must report the literal UNKNOWN: " + JSON.stringify(ci));
      if (typeof ci.reason !== "string" || ci.reason.length === 0) die("UNKNOWN must carry a non-empty reason: " + JSON.stringify(ci));
      if (c16.status !== "PASS") die("CAT-16 must stay PASS-only, got " + c16.status);
    });
  ' <<<"$out" || rc3=1

  if [[ "$rc1" -eq 0 && "$rc2" -eq 0 && "$rc3" -eq 0 ]]; then
    log_pass "TEST-038 (0139-TEST-004) canonical_invocation fixture matrix: true / false (+/aai-update reason) / literal UNKNOWN, CAT-16 PASS-only"
  else
    log_fail "TEST-038 (0139-TEST-004) canonical_invocation fixture matrix"
  fi
}

# --- TEST-039 (0139-TEST-005, Spec-AC-03) — shape invariants + real repo ----
test_039_0139_canonical_invocation_shape() {
  local fixture out_text out_json ok=1

  # Text mode on the carried=true fixture: exactly one CAT-16 line, the
  # contract segment appended to its reason, no detail leaked into text mode.
  fixture="$(build_canonical_true_fixture t039-true)"
  out_text="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  local n_lines
  n_lines="$(grep -c '^CAT-16 ' <<<"$out_text")"
  if [[ "$n_lines" -ne 1 ]]; then
    log_info "TEST-039: text mode printed $n_lines CAT-16 lines (want exactly 1)"
    ok=0
  fi
  local c16_line
  c16_line="$(grep '^CAT-16 ' <<<"$out_text")"
  if ! grep -qF 'canonical test-invocation contract' <<<"$c16_line"; then
    log_info "TEST-039: CAT-16 text line missing the contract segment: $c16_line"
    ok=0
  fi
  if ! grep -qF 'CAT-16 PASS' <<<"$c16_line"; then
    log_info "TEST-039: CAT-16 must stay PASS: $c16_line"
    ok=0
  fi
  if grep -qF '"carried"' <<<"$out_text"; then
    log_info "TEST-039: structured detail leaked into text mode"
    ok=0
  fi

  # SEAM-1 crossed for real: the actual doctor over the ACTUAL repo root must
  # report carried true (the guidance edits and the probe literals agree).
  out_json="$(node "$DOCTOR" --root "$PROJECT_ROOT" --json 2>&1)"
  node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const c16 = j.categories.find(x => x.id === "CAT-16");
      const ci = c16.detail && c16.detail.canonical_invocation;
      if (!ci) die("real repo: detail.canonical_invocation missing");
      if (ci.carried !== true) die("real repo root must report carried true: " + JSON.stringify(ci));
      if (c16.status !== "PASS") die("real repo CAT-16 must stay PASS, got " + c16.status);
    });
  ' <<<"$out_json" || ok=0

  # No-spawn/no-network structural pin on the probe itself: the
  # probeCanonicalInvocation function body performs pure fs reads — no
  # spawnSync, no run(), no network primitive (TEST-030 re-pins the whole
  # file; this pins the NEW code path by name).
  local body
  body="$(awk '/^function probeCanonicalInvocation/{f=1} f{print; if ($0 ~ /^}/) exit}' "$DOCTOR")"
  if [[ -z "$body" ]]; then
    log_info "TEST-039: probeCanonicalInvocation function not found in $DOCTOR"
    ok=0
  fi
  if grep -qE 'spawnSync|[^A-Za-z]run\(' <<<"$body"; then
    log_info "TEST-039: probeCanonicalInvocation spawns a process"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-039 (0139-TEST-005) shape invariants: one CAT-16 text line with contract segment, detail json-only, real repo carried=true, probe spawn-free" \
    || log_fail "TEST-039 (0139-TEST-005) canonical_invocation shape invariants"
}

# --- TEST-040 (PR #302 review: Codex P1 / Copilot P2) — CAT-17 effective
# hooks path + behavioural probe ---------------------------------------------
# A hook FILE carrying the AAI:REF-GUARD marker is not evidence git will run
# it. This pins the three ways that lied before this fix, plus a control:
#   1) core.hooksPath redirects git elsewhere -> the marker'd file at the
#      DEFAULT path is dead weight; CAT-17 must say NOT armed. A "naive"
#      re-implementation of the PRE-FIX resolution (git-common-dir join,
#      marker-only, no --git-path) is run against the SAME fixture and shown
#      to say PASS -- proving this fixture actually exercises the bug, not
#      a strawman.
#   2) A decorative hook (marker present, unconditionally exits 0, never
#      refuses) -> CAT-17's behavioural probe must catch it.
#   3) A hook without the executable bit (POSIX only) -> git silently never
#      runs it; CAT-17 must say NOT armed.
#   4) Control: a genuinely armed hook at the default path -> PASS.
test_040_cat17_effective_path_and_probe() {
  local ok=1

  local reftx_body='#!/bin/sh
# AAI:REF-GUARD
aai_state="$1"
if [ "$aai_state" != "prepared" ]; then exit 0; fi
aai_guarded=0
while read -r o n r; do [ "$r" = "refs/heads/main" ] && aai_guarded=1; done
[ "$aai_guarded" = "1" ] || exit 0
[ "$AAI_GIT_WRITE" = "1" ] && exit 0
echo "AAI:REF-GUARD refused this refs/heads/main update." >&2
exit 1
'

  # --- Fixture 1: core.hooksPath override -------------------------------
  local d1="$TMP_ROOT/t040-hookspath"
  rm -rf "$d1"; mkdir -p "$d1/.git/hooks" "$d1/altdir_hooks"
  git -C "$d1" init -q -b main >/dev/null
  git -C "$d1" config user.email "test@example.invalid"; git -C "$d1" config user.name "AAI Test"
  git -C "$d1" commit -q --allow-empty -m init
  printf '%s' "$reftx_body" > "$d1/.git/hooks/reference-transaction"
  chmod +x "$d1/.git/hooks/reference-transaction"
  git -C "$d1" config core.hooksPath altdir_hooks

  local out1
  out1="$(node "$DOCTOR" --root "$d1" 2>&1 | grep '^CAT-17')"
  if [[ "$out1" == *' PASS '* ]]; then
    log_info "TEST-040 hooksPath: got PASS (git.ignores this file once hooksPath is set): $out1"
    ok=0
  fi

  # Mutation proof: the PRE-FIX resolution (git-common-dir join + marker
  # substring, no --git-path, no probe) reading the SAME fixture.
  local naive
  naive="$(node -e '
    const fs=require("node:fs"), path=require("node:path"), cp=require("node:child_process");
    const root=process.argv[1];
    let gitDir=path.join(root,".git");
    const r=cp.spawnSync("git",["rev-parse","--git-common-dir"],{cwd:root,encoding:"utf8"});
    if(r.status===0 && r.stdout.trim()!==""){
      const c=r.stdout.trim();
      gitDir = path.isAbsolute(c)?c:path.join(root,c);
    }
    const hookPath=path.join(gitDir,"hooks/reference-transaction");
    const body=fs.existsSync(hookPath)?fs.readFileSync(hookPath,"utf8"):"";
    process.stdout.write(body.includes("AAI:REF-GUARD") ? "PASS" : "WARN");
  ' "$d1")"
  if [[ "$naive" != "PASS" ]]; then
    log_info "TEST-040: fixture sanity check failed — the pre-fix (marker-only) resolution did not say PASS on this fixture (got $naive), so it would not have caught the F-A regression"
    ok=0
  fi
  git -C "$d1" config --unset core.hooksPath

  # --- Fixture 2: decorative hook (marker present, never refuses) ------
  local d2="$TMP_ROOT/t040-decorative"
  rm -rf "$d2"; mkdir -p "$d2/.git/hooks"
  git -C "$d2" init -q -b main >/dev/null
  git -C "$d2" config user.email "test@example.invalid"; git -C "$d2" config user.name "AAI Test"
  git -C "$d2" commit -q --allow-empty -m init
  printf '#!/bin/sh\n# AAI:REF-GUARD\nexit 0\n' > "$d2/.git/hooks/reference-transaction"
  chmod +x "$d2/.git/hooks/reference-transaction"
  local out2
  out2="$(node "$DOCTOR" --root "$d2" 2>&1 | grep '^CAT-17')"
  if [[ "$out2" == *' PASS '* ]]; then
    log_info "TEST-040 decorative: got PASS on a hook that never refuses: $out2"
    ok=0
  fi
  if [[ "$(printf '%s' "$out2" | tr 'A-Z' 'a-z')" != *'does not behave as a guard'* ]]; then
    log_info "TEST-040 decorative: WARN reason does not name the behavioural mismatch: $out2"
    ok=0
  fi

  # --- Fixture 5: decorative hook that closes its stdin at once, so the
  # probe's input write gets EPIPE deterministically (a fast `exit 0` hook
  # did this on the Linux CI runner, PR #381 run 34815192336). The verdict
  # must still be the behavioural one, never "could not be verified (EPIPE)".
  local d5="$TMP_ROOT/t040-epipe"
  rm -rf "$d5"; mkdir -p "$d5/.git/hooks"
  git -C "$d5" init -q -b main >/dev/null
  git -C "$d5" config user.email "test@example.invalid"; git -C "$d5" config user.name "AAI Test"
  git -C "$d5" commit -q --allow-empty -m init
  printf '#!/bin/sh\n# AAI:REF-GUARD\nexec 0<&-\nsleep 0.3\nexit 0\n' > "$d5/.git/hooks/reference-transaction"
  chmod +x "$d5/.git/hooks/reference-transaction"
  local out5
  out5="$(node "$DOCTOR" --root "$d5" 2>&1 | grep '^CAT-17')"
  if [[ "$out5" == *' PASS '* ]]; then
    log_info "TEST-040 epipe: got PASS on a hook that never refuses: $out5"
    ok=0
  fi
  if [[ "$(printf '%s' "$out5" | tr 'A-Z' 'a-z')" == *'could not be behaviourally verified'* ]]; then
    log_info "TEST-040 epipe: the probe gave up (any error code) instead of judging the hook by its exit status: $out5"
    ok=0
  fi
  if [[ "$(printf '%s' "$out5" | tr 'A-Z' 'a-z')" != *'does not behave as a guard'* ]]; then
    log_info "TEST-040 epipe: WARN reason does not name the behavioural mismatch: $out5"
    ok=0
  fi

  # --- Fixture 3: non-executable hook (POSIX only) ----------------------
  case "$(uname -s)" in
    MINGW*|CYGWIN*|MSYS*) : ;; # git hooks run through an interpreter there regardless of mode bits
    *)
      local d3="$TMP_ROOT/t040-noexec"
      rm -rf "$d3"; mkdir -p "$d3/.git/hooks"
      git -C "$d3" init -q -b main >/dev/null
      git -C "$d3" config user.email "test@example.invalid"; git -C "$d3" config user.name "AAI Test"
      git -C "$d3" commit -q --allow-empty -m init
      printf '%s' "$reftx_body" > "$d3/.git/hooks/reference-transaction"
      chmod -x "$d3/.git/hooks/reference-transaction"
      local out3
      out3="$(node "$DOCTOR" --root "$d3" 2>&1 | grep '^CAT-17')"
      if [[ "$out3" == *' PASS '* ]]; then
        log_info "TEST-040 non-executable: got PASS on a hook without the executable bit: $out3"
        ok=0
      fi
      if [[ "$(printf '%s' "$out3" | tr 'A-Z' 'a-z')" != *'not executable'* ]]; then
        log_info "TEST-040 non-executable: WARN reason does not name the missing executable bit: $out3"
        ok=0
      fi
      ;;
  esac

  # --- Fixture 4 (control): genuinely armed hook -> PASS ----------------
  local d4="$TMP_ROOT/t040-armed"
  rm -rf "$d4"; mkdir -p "$d4/.git/hooks"
  git -C "$d4" init -q -b main >/dev/null
  git -C "$d4" config user.email "test@example.invalid"; git -C "$d4" config user.name "AAI Test"
  git -C "$d4" commit -q --allow-empty -m init
  printf '%s' "$reftx_body" > "$d4/.git/hooks/reference-transaction"
  chmod +x "$d4/.git/hooks/reference-transaction"
  local out4
  out4="$(node "$DOCTOR" --root "$d4" 2>&1 | grep '^CAT-17')"
  if [[ "$out4" != *' PASS '* ]]; then
    log_info "TEST-040 armed control: expected PASS, got: $out4"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-040 CAT-17 resolves the EFFECTIVE hooks path (core.hooksPath override -> NOT armed; pre-fix marker-only resolution DOES wrongly say PASS on the same fixture) and behaviourally probes the hook (decorative/non-executable -> NOT armed; a real guard -> PASS)" \
    || log_fail "TEST-040 CAT-17 effective-path + behavioural-probe"
}

# --- TEST-1341..1344 (SPEC-DRAFT spec-a-check-cannot-tell-silence-from-a-verdict,
# Spec-AC-01..04) — CAT-17 says what it OBSERVED, or says it could not observe.
#
# Before this ride the probe derived `refuses` from `status !== 0` alone and
# had two arms only. A hook that cannot execute, that crashes, or that refuses
# for a reason of its own therefore scored as a PASSING refuse arm, and the
# category rendered "does NOT behave as a guard ... NOT armed" — a verdict it
# had not earned (spec M1/M2/M3). Three states move OUT of "NOT armed" and
# into "could not be behaviourally verified"; none moves in.

# cat17_hook_fixture <name> <hook-body> — a git repo carrying <hook-body> as an
# EXECUTABLE reference-transaction hook at the default (effective) hooks path.
# Echoes the fixture path. Its own git identity, because a CI runner has none.
cat17_hook_fixture() {
  local name="$1" body="$2"
  local d="$TMP_ROOT/$name"
  rm -rf "$d"; mkdir -p "$d/.git/hooks"
  git -C "$d" init -q -b main >/dev/null
  git -C "$d" config user.email "test@example.invalid"
  git -C "$d" config user.name "AAI Test"
  git -C "$d" commit -q --allow-empty -m init
  printf '%s' "$body" > "$d/.git/hooks/reference-transaction"
  chmod +x "$d/.git/hooks/reference-transaction"
  printf '%s' "$d"
}

# cat17_line <root> — the CAT-17 line of a doctor run over <root>, or the empty
# string. Never non-zero (callers accumulate into their own `ok` flag), and the
# reader consumes all of stdout so nothing can SIGPIPE the doctor under pipefail.
cat17_line() {
  local out
  out="$(node "$DOCTOR" --root "$1" 2>&1)" || true
  printf '%s\n' "$out" | while IFS= read -r line; do
    case "$line" in CAT-17*) printf '%s' "$line" ;; esac
  done
}

# cat17_assert_unverified <label> <line> <reason-token> — the shared shape of
# Spec-AC-01..03: the category must name the reason, must say it could not
# verify, and must NOT claim the hook is NOT armed and must not claim PASS.
# Returns 1 and log_info's each violation, so callers collect all of them.
cat17_assert_unverified() {
  local label="$1" line="$2" token="$3" ok=1 lower
  lower="$(printf '%s' "$line" | tr 'A-Z' 'a-z')"
  if [[ "$line" == *' PASS '* ]]; then
    log_info "$label: got PASS on a hook whose guard behaviour was never observed: $line"; ok=0
  fi
  if [[ "$lower" != *'could not be behaviourally verified'* ]]; then
    log_info "$label: CAT-17 does not say it could not behaviourally verify the hook: $line"; ok=0
  fi
  if [[ "$line" != *"$token"* ]]; then
    log_info "$label: CAT-17 does not name the reason '$token': $line"; ok=0
  fi
  if [[ "$lower" == *'not armed'* ]]; then
    log_info "$label: CAT-17 still claims 'NOT armed' for a state it could not observe: $line"; ok=0
  fi
  return $(( ok == 1 ? 0 : 1 ))
}

# --- TEST-1341 (Spec-AC-01) — a non-zero refuse arm with NO AAI:REF-GUARD on
# stderr is not evidence this guard refused. ---------------------------------
test_1341_cat17_no_refusal_marker() {
  local ok=1
  # Marker in the BODY, refuses refs/heads/main with a bare `exit 1`, prints
  # nothing: exactly the pre-ride fixture shape, and exactly the shape a
  # crashing or mis-launched hook produces.
  local body='#!/bin/sh
# AAI:REF-GUARD
[ "$1" = "prepared" ] || exit 0
aai_guarded=0
while read -r o n r; do [ "$r" = "refs/heads/main" ] && aai_guarded=1; done
[ "$aai_guarded" = "1" ] || exit 0
[ "$AAI_GIT_WRITE" = "1" ] && exit 0
exit 1
'
  local d; d="$(cat17_hook_fixture t1341-silent-refuser "$body")"
  local line; line="$(cat17_line "$d")"
  if [[ -z "$line" ]]; then
    log_info "TEST-1341: the doctor emitted no CAT-17 line at all"; ok=0
  fi
  cat17_assert_unverified "TEST-1341" "$line" "no-refusal-marker" || ok=0

  [[ $ok -eq 1 ]] && log_pass "TEST-1341 a marker'd hook that refuses refs/heads/main with a silent non-zero exit is reported as could not be behaviourally verified (no-refusal-marker), never as NOT armed" \
    || log_fail "TEST-1341 CAT-17 no-refusal-marker discrimination"
}

# --- TEST-1342 (Spec-AC-02) — the CONTROL arm: a hook that will not exit 0 on
# a ref it is meant to IGNORE is a hook we could not run as a guard. ---------
test_1342_cat17_control_arm_nonzero() {
  local ok=1
  # Refuses EVERY transaction, marker and all. Its refuse arm looks perfect;
  # only a control transaction naming a ref no guard cares about exposes it.
  local body='#!/bin/sh
# AAI:REF-GUARD
echo "AAI:REF-GUARD refused this refs/heads/main update." >&2
exit 1
'
  local d; d="$(cat17_hook_fixture t1342-always-refuses "$body")"
  local line; line="$(cat17_line "$d")"
  if [[ -z "$line" ]]; then
    log_info "TEST-1342: the doctor emitted no CAT-17 line at all"; ok=0
  fi
  cat17_assert_unverified "TEST-1342" "$line" "control-arm-nonzero" || ok=0

  [[ $ok -eq 1 ]] && log_pass "TEST-1342 a marker'd hook that exits non-zero even on a transaction naming only refs/heads/aai-doctor-probe-control is reported as could not be behaviourally verified (control-arm-nonzero), never as NOT armed" \
    || log_fail "TEST-1342 CAT-17 control-arm discrimination"
}

# --- TEST-1343 (Spec-AC-03) — the #369 signature: both arms refuse. The honest
# reading is "the interpreter did not receive AAI_GIT_WRITE", not "broken". --
test_1343_cat17_permit_arm_refused() {
  local ok=1
  # Prints the real refusal marker on refs/heads/main and never consults
  # AAI_GIT_WRITE, so the permit arm refuses too.
  local body='#!/bin/sh
# AAI:REF-GUARD
[ "$1" = "prepared" ] || exit 0
aai_guarded=0
while read -r o n r; do [ "$r" = "refs/heads/main" ] && aai_guarded=1; done
[ "$aai_guarded" = "1" ] || exit 0
echo "AAI:REF-GUARD refused this refs/heads/main update." >&2
exit 1
'
  local d; d="$(cat17_hook_fixture t1343-env-blind "$body")"
  local line; line="$(cat17_line "$d")"
  if [[ -z "$line" ]]; then
    log_info "TEST-1343: the doctor emitted no CAT-17 line at all"; ok=0
  fi
  cat17_assert_unverified "TEST-1343" "$line" "permit-arm-refused" || ok=0
  if [[ "$line" != *'AAI_GIT_WRITE'* ]]; then
    log_info "TEST-1343: the reason does not name AAI_GIT_WRITE as the variable the interpreter may not have received: $line"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-1343 a marker'd hook whose permit arm still refuses with AAI_GIT_WRITE=1 set is reported as permit-arm-refused and names AAI_GIT_WRITE, never as NOT armed" \
    || log_fail "TEST-1343 CAT-17 permit-arm discrimination"
}

# --- TEST-1344 (Spec-AC-04, SEAM-1) — positive control against over-refusal.
# The hook body is written by install-pre-commit-hook.sh and the marker is read
# by aai-doctor.mjs: two files, one contract. Both sides are the REAL scripts —
# a mock of either would test the mock. This row is admitted by its MUTATION
# (blunt the installer's marker line and this test reddens), not by a RED
# against pre-ride code: a control that was already green is the point of it.
test_1344_cat17_seam1_installed_hook_passes() {
  local ok=1
  local d="$TMP_ROOT/t1344-seam1"
  rm -rf "$d"; mkdir -p "$d/.aai/scripts"
  git -C "$d" init -q -b main >/dev/null
  git -C "$d" config user.email "test@example.invalid"
  git -C "$d" config user.name "AAI Test"
  git -C "$d" commit -q --allow-empty -m init
  cp "$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.sh" "$d/.aai/scripts/install-pre-commit-hook.sh"
  # HAZ: the installer resolves its target from `git rev-parse --show-toplevel`,
  # so it MUST run with the fixture as cwd and never against $PROJECT_ROOT.
  ( cd "$d" && bash .aai/scripts/install-pre-commit-hook.sh --arm-ref-guard >/dev/null 2>&1 ) || true

  # Hard precondition: without an installed, marker'd hook the assertion below
  # would be vacuous rather than a crossing test.
  if [[ ! -f "$d/.git/hooks/reference-transaction" ]]; then
    log_info "TEST-1344: the real installer wrote no reference-transaction hook into the fixture"
    ok=0
  elif ! command grep -qF 'AAI:REF-GUARD' "$d/.git/hooks/reference-transaction"; then
    log_info "TEST-1344: the installed hook carries no AAI:REF-GUARD body marker"
    ok=0
  fi

  local line; line="$(cat17_line "$d")"
  if [[ "$line" != *' PASS '* ]]; then
    log_info "TEST-1344: the hook the REAL installer writes is not reported PASS by the REAL doctor: $line"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-1344 SEAM-1 the reference-transaction hook written by install-pre-commit-hook.sh is probed PASS by aai-doctor.mjs (installer-emitted AAI:REF-GUARD marker and doctor-read marker are one contract)" \
    || log_fail "TEST-1344 SEAM-1 installed hook probes PASS"
}

# --- TEST-1345 (Spec-AC-05) — the regression guard on the DIRECTION of the
# change. D2 moves three states OUT of "NOT armed"; this row pins that none
# moved IN. A hook that carries the body marker, exits 0 on the control
# transaction AND exits 0 on refs/heads/main with no AAI_GIT_WRITE is
# decorative, and the probe OBSERVED it letting a guarded ref through — so
# "NOT armed" is a verdict this category earned and must keep saying.
#
# HONESTY: no RED is available for this row. Pre-ride code and post-ride code
# both say "NOT armed" on this fixture, which is precisely the property being
# pinned, so the row is admitted by its MUTATION (blunt the renderer's
# "NOT armed" words and this test reddens), exactly like TEST-1344.
test_1345_cat17_decorative_hook_still_not_armed() {
  local ok=1
  # Marker in the body, nothing else: never reads stdin, never refuses.
  local body='#!/bin/sh
# AAI:REF-GUARD
exit 0
'
  local d; d="$(cat17_hook_fixture t1345-decorative "$body")"
  local line; line="$(cat17_line "$d")"
  local lower; lower="$(printf '%s' "$line" | tr 'A-Z' 'a-z')"
  if [[ -z "$line" ]]; then
    log_info "TEST-1345: the doctor emitted no CAT-17 line at all"; ok=0
  fi
  if [[ "$line" == *' PASS '* ]]; then
    log_info "TEST-1345: got PASS on a hook that lets refs/heads/main through without AAI_GIT_WRITE=1: $line"; ok=0
  fi
  if [[ "$lower" != *'not armed'* ]]; then
    log_info "TEST-1345: CAT-17 stopped saying NOT armed about a hook it OBSERVED letting refs/heads/main through — that state must NOT have moved into 'could not be verified': $line"; ok=0
  fi
  if [[ "$lower" == *'could not be behaviourally verified'* ]]; then
    log_info "TEST-1345: CAT-17 claims it could not verify a hook whose decorative behaviour it DID observe: $line"; ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-1345 a marker'd hook that exits 0 on refs/heads/main without AAI_GIT_WRITE is still reported NOT armed (no state moved INTO the armed-unknown verdict)" \
    || log_fail "TEST-1345 CAT-17 decorative hook keeps the NOT armed verdict"
}

# --- TEST-1346 (Spec-AC-06) — the interpreter LOOKUP, as a pure function.
# On win32 the probe used to try bare `sh` then bare `bash`; on a PowerShell
# host without Git Bash on PATH that is ENOENT followed by WSL's
# C:\Windows\system32\bash.exe (spec M4). resolveRefGuardLaunchers derives Git
# for Windows' OWN shell from `git --exec-path` and puts it FIRST.
#
# It is a PURE function with injected `platform`, `gitExecPath` and `exists`,
# so this row runs on any OS. What it does NOT prove is that a real Git for
# Windows install has that layout — residual risk R1; the behavioural half is
# the CI step TEST-1347 pins the presence of.
test_1346_resolve_ref_guard_launchers() {
  local ok=1
  local probe="$TMP_ROOT/t1346-launchers.mjs"
  cat > "$probe" <<'T1346_PROBE'
import { pathToFileURL } from 'node:url';

const mod = await import(pathToFileURL(process.argv[2]).href);
const fn = mod.resolveRefGuardLaunchers;
if (typeof fn !== 'function') {
  console.log('MISSING_EXPORT: resolveRefGuardLaunchers');
  process.exit(0);
}
const slash = (v) => String(v).replace(/\\/g, '/');
const GIT_EXEC = 'C:\\Program Files\\Git\\mingw64\\libexec\\git-core';
const GIT_SH = 'C:\\Program Files\\Git\\usr\\bin\\sh.exe';
const HOOK_WIN = 'C:\\repo\\.git\\hooks\\reference-transaction';
const win = fn({
  platform: 'win32',
  hookPath: HOOK_WIN,
  gitExecPath: GIT_EXEC,
  exists: (p) => slash(p) === slash(GIT_SH),
});
console.log('WIN_CMDS: ' + win.map((l) => slash(l[0])).join(','));
console.log('WIN_FIRST_ARGS: ' + JSON.stringify(win[0] ? win[0][1].map(slash) : null));
const posix = fn({ platform: 'linux', hookPath: '/tmp/hook', gitExecPath: '', exists: () => false });
console.log('POSIX_COUNT: ' + posix.length);
console.log('POSIX_FIRST: ' + String(posix[0] ? posix[0][0] : ''));
console.log('POSIX_ARGS: ' + JSON.stringify(posix[0] ? posix[0][1] : null));
T1346_PROBE

  local out
  out="$(node "$probe" "$PROJECT_ROOT/.aai/scripts/lib/guard-config.mjs" 2>&1)" || true

  if [[ "$out" == *'MISSING_EXPORT'* ]]; then
    log_info "TEST-1346: lib/guard-config.mjs does not export resolveRefGuardLaunchers"; ok=0
  fi
  # win32: Git for Windows' own sh.exe FIRST, bare sh and bare bash behind it.
  if [[ "$out" != *'WIN_CMDS: C:/Program Files/Git/usr/bin/sh.exe,sh,bash'* ]]; then
    log_info "TEST-1346: win32 launcher order is not [Git-for-Windows sh.exe, sh, bash]: $out"; ok=0
  fi
  if [[ "$out" != *'WIN_FIRST_ARGS: ["C:/repo/.git/hooks/reference-transaction","prepared"]'* ]]; then
    log_info "TEST-1346: the win32 first launcher is not invoked as <interpreter> <hook> prepared: $out"; ok=0
  fi
  # non-win32: exactly ONE launcher, and it execs the hook file directly.
  if [[ "$out" != *'POSIX_COUNT: 1'* ]]; then
    log_info "TEST-1346: a non-win32 platform does not resolve to exactly one launcher: $out"; ok=0
  fi
  if [[ "$out" != *'POSIX_FIRST: /tmp/hook'* ]]; then
    log_info "TEST-1346: the non-win32 launcher is not a DIRECT exec of the hook file: $out"; ok=0
  fi
  if [[ "$out" != *'POSIX_ARGS: ["prepared"]'* ]]; then
    log_info "TEST-1346: the non-win32 launcher does not pass the 'prepared' transaction state: $out"; ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-1346 resolveRefGuardLaunchers puts Git for Windows' own usr/bin/sh.exe ahead of bare sh and bare bash on win32 and resolves to exactly one direct-exec launcher elsewhere" \
    || log_fail "TEST-1346 resolveRefGuardLaunchers win32 interpreter lookup"
}

# --- TEST-1347 (Spec-AC-07) — the Windows evidence is a CI STEP, not a Pester
# `It`: a Windows-only `It` SKIPS on Linux and the POSIX gate asserts
# SkippedCount -eq 0 (spec M12/D4), so it would redden the Linux leg. What is
# provable HERE is presence only — that the windows-wsl1 job carries a step
# which installs the ref guard, runs the doctor, and fails the job unless the
# CAT-17 line carries PASS. The behavioural proof is that step's own CI log.
test_1347_ps1_quality_windows_cat17_step() {
  local ok=1
  local wf="$PROJECT_ROOT/.github/workflows/ps1-quality.yml"
  local step=""
  if [[ ! -f "$wf" ]]; then
    log_info "TEST-1347: $wf is absent"; ok=0
  else
    # ONE step inside the windows-wsl1 job: the job block is bounded by the
    # next job header at the same indent, and the step block by the next
    # `- ` step marker. Scoped deliberately — asserting over the whole file,
    # or even the whole job, would be satisfied by the pieces already there
    # (the selftest step ALREADY runs aai-doctor.mjs --json), so the install,
    # the doctor run and the PASS assertion must be ONE step to count.
    step="$(awk '
      /^  windows-wsl1:/ { injob = 1; next }
      injob && /^  [A-Za-z0-9_-]+:/ { injob = 0 }
      !injob { next }
      /^      - / { instep = ($0 ~ /CAT-17/) }
      instep { print }
    ' "$wf")"
    if [[ -z "$step" ]]; then
      log_info "TEST-1347: the windows-wsl1 job of $wf carries no CAT-17 step at all"; ok=0
    fi
  fi

  if [[ "$step" != *'install-pre-commit-hook.sh --arm-ref-guard'* ]]; then
    log_info "TEST-1347: the windows-wsl1 CAT-17 step never installs the ref guard (no install-pre-commit-hook.sh --arm-ref-guard)"; ok=0
  fi
  if [[ "$step" != *'aai-doctor.mjs'* ]]; then
    log_info "TEST-1347: the windows-wsl1 CAT-17 step never runs aai-doctor.mjs"; ok=0
  fi
  # The assertion itself: a required token that is literally PASS, and a
  # non-zero exit when the CAT-17 line does not carry it.
  if [[ "$step" != *'$CAT17_REQUIRED_TOKEN = " PASS "'* ]]; then
    log_info "TEST-1347: the windows-wsl1 CAT-17 step does not require the literal PASS token on the CAT-17 line"; ok=0
  fi
  # -cnotlike, not -notlike (code review finding 1): PowerShell's default
  # comparison is CASE-INSENSITIVE, so a future reason string carrying
  # "bypass" or "passed through" would satisfy "* PASS *" and let the step
  # print OK on a verdict that was never PASS. The gate must read the status
  # token the renderer actually wrote, so the test requires the case-sensitive
  # operator rather than merely "some comparison against the token".
  if [[ "$step" != *'-cnotlike "*$CAT17_REQUIRED_TOKEN*"'* ]]; then
    log_info "TEST-1347: the windows-wsl1 CAT-17 step does not test the CAT-17 line against the required token CASE-SENSITIVELY (-cnotlike)"; ok=0
  fi
  if [[ "$step" != *'AAI-WIN-CAT17-FAIL'* ]]; then
    log_info "TEST-1347: the windows-wsl1 CAT-17 step has no named loud failure (AAI-WIN-CAT17-FAIL) to fail the job with"; ok=0
  fi
  if [[ "$step" != *'exit 1'* ]]; then
    log_info "TEST-1347: the windows-wsl1 CAT-17 step never fails the job (no non-zero exit)"; ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-1347 the windows-wsl1 job of ps1-quality.yml installs the ref guard, runs aai-doctor.mjs and fails the job unless the CAT-17 line carries PASS (presence only — the behavioural proof is the CI run)" \
    || log_fail "TEST-1347 windows-wsl1 CAT-17 doctor step presence"
}

# --- TEST-619 (Spec-AC-07) — a declared decline is a non-counting state ----
test_619_cat17_declined_is_not_an_issue() {
  local ok=1
  local d; d="$(build_clean_fixture t619)"
  rm -f "$d/.git/hooks/reference-transaction"
  printf 'ref_guard: declined\n' > "$d/docs/ai/docs-audit.yaml"
  # docs-audit.yaml is TRACKED (build_clean_fixture commits it); commit and
  # push the edit too, or CAT-08's git-status check WARNs on the dirty tree
  # and pollutes the "only CAT-17 would have WARNed" premise this test needs.
  git -C "$d" add -A
  git -C "$d" commit -q -m "t619: decline the ref guard"
  git -C "$d" push -q origin main

  local out rc
  # The FIXTURE's own vendored copy (not --root against $DOCTOR): CAT-11/
  # CAT-13 resolve their docs-audit.mjs/layer-drift.mjs siblings relative to
  # the INVOKED script's own location, so only the fixture's own copy picks
  # up build_clean_fixture's always-clean stubs (test_014's discipline).
  out="$(node "$d/.aai/scripts/aai-doctor.mjs" --strict 2>&1)"; rc=$?
  local cat17; cat17="$(echo "$out" | grep '^CAT-17')"
  if [[ "$(printf '%s' "$cat17" | tr 'A-Z' 'a-z')" != *'declined'* ]]; then
    log_info "TEST-619: CAT-17 does not name the declined state: $cat17"
    ok=0
  fi
  if [[ "$cat17" != *"docs-audit.yaml"* ]]; then
    log_info "TEST-619: CAT-17 does not name the config path: $cat17"
    ok=0
  fi
  if [[ "$cat17" != *"--arm-ref-guard"* ]]; then
    log_info "TEST-619: CAT-17 does not name the re-arm command: $cat17"
    ok=0
  fi
  if ! dr_line_hit "$out" '^DOCTOR CLEAN$'; then
    log_info "TEST-619: DOCTOR summary counted the declined category: $(echo "$out" | grep '^DOCTOR')"
    ok=0
  fi
  if [[ "$rc" -ne 0 ]]; then
    log_info "TEST-619: --strict expected exit 0 when only CAT-17 would have WARNed (declined), got $rc"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-619 CAT-17 reports a declined state naming docs/ai/docs-audit.yaml and --arm-ref-guard, DOCTOR ISSUES does not count it, and --strict exits 0" \
    || log_fail "TEST-619 CAT-17 declined non-counting state"
}

# --- TEST-620 (Spec-AC-07) — reality outranks the declaration (D4) ---------
test_620_cat17_declaration_never_over_reads() {
  local ok=1
  local reftx_body='#!/bin/sh
# AAI:REF-GUARD
aai_state="$1"
if [ "$aai_state" != "prepared" ]; then exit 0; fi
aai_guarded=0
while read -r o n r; do [ "$r" = "refs/heads/main" ] && aai_guarded=1; done
[ "$aai_guarded" = "1" ] || exit 0
[ "$AAI_GIT_WRITE" = "1" ] && exit 0
echo "AAI:REF-GUARD refused this refs/heads/main update." >&2
exit 1
'

  # (a) a GENUINELY armed guard + a declined declaration -> PASS armed
  # regardless (D4: reality outranks the declaration).
  local da="$TMP_ROOT/t620-armed"
  rm -rf "$da"; mkdir -p "$da/.git/hooks" "$da/docs/ai"
  git -C "$da" init -q -b main >/dev/null
  git -C "$da" config user.email "test@example.invalid"; git -C "$da" config user.name "AAI Test"
  git -C "$da" commit -q --allow-empty -m init
  printf '%s' "$reftx_body" > "$da/.git/hooks/reference-transaction"
  chmod +x "$da/.git/hooks/reference-transaction"
  printf 'ref_guard: declined\n' > "$da/docs/ai/docs-audit.yaml"
  local outa; outa="$(node "$DOCTOR" --root "$da" 2>&1 | grep '^CAT-17')"
  if [[ "$outa" != *' PASS '* ]]; then
    log_info "TEST-620: armed guard with a declined declaration did not report PASS: $outa"
    ok=0
  fi

  # (b) a FOREIGN reference-transaction hook + a declined declaration -> the
  # existing "not AAI-managed" WARN is not suppressed by the declaration.
  local db="$TMP_ROOT/t620-foreign"
  rm -rf "$db"; mkdir -p "$db/.git/hooks" "$db/docs/ai"
  git -C "$db" init -q -b main >/dev/null
  git -C "$db" config user.email "test@example.invalid"; git -C "$db" config user.name "AAI Test"
  git -C "$db" commit -q --allow-empty -m init
  printf '#!/bin/sh\necho foreign-reftx\n' > "$db/.git/hooks/reference-transaction"
  chmod +x "$db/.git/hooks/reference-transaction"
  printf 'ref_guard: declined\n' > "$db/docs/ai/docs-audit.yaml"
  local outb; outb="$(node "$DOCTOR" --root "$db" 2>&1 | grep '^CAT-17')"
  if [[ "$(printf '%s' "$outb" | tr 'A-Z' 'a-z')" != *'not aai-managed'* ]]; then
    log_info "TEST-620: a foreign reference-transaction hook's WARN was suppressed by a declined declaration: $outb"
    ok=0
  fi
  if [[ "$(printf '%s' "$outb" | tr 'A-Z' 'a-z')" == *'declined'* ]]; then
    log_info "TEST-620: the foreign-hook WARN mentions 'declined' -- the declaration must not reach this branch: $outb"
    ok=0
  fi

  # (c) no declaration at all, absent guard -> the current WARN text is
  # unchanged verbatim (this fixture root carries no installer file, so the
  # "installer missing" wording is the one exercised).
  local dc="$TMP_ROOT/t620-undeclared"
  rm -rf "$dc"; mkdir -p "$dc/.git/hooks"
  git -C "$dc" init -q -b main >/dev/null
  git -C "$dc" config user.email "test@example.invalid"; git -C "$dc" config user.name "AAI Test"
  git -C "$dc" commit -q --allow-empty -m init
  local outc; outc="$(node "$DOCTOR" --root "$dc" 2>&1 | grep '^CAT-17')"
  if [[ "$(printf '%s' "$outc" | tr 'A-Z' 'a-z')" != *'not armed and installer missing'* ]]; then
    log_info "TEST-620: the undeclared WARN text changed: $outc"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-620 an armed guard reports PASS armed despite a declined declaration, a foreign reference-transaction hook still WARNs despite it, and an undeclared fixture keeps the current not-armed WARN text verbatim" \
    || log_fail "TEST-620 CAT-17 declaration never over-reads"
}

# --- TEST-439 (spec-test-framework-sweep Spec-AC-22) — every CLI main()
# guard resolves both sides through realpath, so invoking the script through
# a SYMLINKED checkout still runs main() instead of silently no-op'ing.
# `path.resolve`/`pathToFileURL`/`.endsWith` shapes do not follow a symlink
# component the way `fs.realpathSync` does, and Node's ESM loader can settle
# `import.meta.url` and a raw `process.argv[1]` on different sides of that
# symlink — the guard then never fires and the CLI exits 0 having done
# nothing, no error, no output.
test_439_argv1_guard_resolves_symlinks() {
  local ok=1 unresolved

  # Part A: no main-guard call site compares process.argv[1] without going
  # through a real*Resolve helper. Comments (heartbeat.mjs, this file's own
  # history) are excluded by requiring an actual comparison operator.
  # allocate-doc-number.mjs is EXCLUDED on purpose: it is one of the eight
  # docs/ai/docs-audit.yaml protected_paths_l3 surfaces, touching it requires
  # a FROZEN ceremony_level:3 spec (test-aai-hitl-propagation.sh TEST-014
  # enforces this repo-wide), and this ride is ceremony 2 (established fact
  # 9 / the spec's own D-decisions never claim an L3 escalation). Its guard
  # keeps the pre-existing unresolved shape as a named residual, not a fix.
  unresolved="$(grep -rn 'process\.argv\[1\]' "$PROJECT_ROOT/.aai/scripts" --include='*.mjs' \
    | grep -v -E '^[^:]+:[0-9]+:[[:space:]]*//' \
    | grep -v 'allocate-doc-number\.mjs' \
    | grep -E '===|\.endsWith\(' \
    | grep -v -iE 'realorresolve|realpathorresolve')"
  if [[ -n "$unresolved" ]]; then
    log_info "TEST-439: unresolved main-guard shape(s) found:"
    log_info "$unresolved"
    ok=0
  fi

  # Part B: three named CLIs, invoked through a symlinked checkout, produce
  # the same stdout and exit code as invoking the real path directly.
  local symdir cli d_out d_rc s_out s_rc
  symdir="$(mktemp -d "${TMPDIR:-/tmp}/aai-doctor-argv1-symlink.XXXXXX")"
  ln -s "$PROJECT_ROOT" "$symdir/repo"
  for cli in orchestration-mode.mjs pr-platform.mjs validation-waiver.mjs; do
    d_out="$(node "$PROJECT_ROOT/.aai/scripts/$cli" --help 2>&1)"; d_rc=$?
    s_out="$(node "$symdir/repo/.aai/scripts/$cli" --help 2>&1)"; s_rc=$?
    if [[ "$d_out" != "$s_out" || "$d_rc" -ne "$s_rc" ]]; then
      log_info "TEST-439: $cli differs through a symlinked checkout (direct rc=$d_rc, symlink rc=$s_rc)"
      ok=0
    fi
  done
  rm -rf "$symdir"

  [[ $ok -eq 1 ]] && log_pass "TEST-439 every main() guard resolves via realpath; symlinked-checkout invocation matches direct invocation" \
    || log_fail "TEST-439 argv[1] main-guard symlink resolution"
}

# --- TEST-812 (shipped-guards-have-no-downstream-trigger, Spec-AC-09) ------
# CAT-18 Guard Wiring: a CLOSED table of guard -> (hook, marker) pairs —
# (pre-commit-checks.sh, pre-commit, AAI:GUARD-CHECKS) and
# (close-reconcile.mjs, pre-push, AAI:CLOSE-GATE). A pair whose guard file is
# absent is not reported; the effective hook path is resolved the way CAT-17
# does (`git rev-parse --git-path`, so core.hooksPath is honoured); PASS needs
# marker + executable bit. The PASS state is produced by the REAL installer
# (seam S6) so a drifted marker literal on either side reddens this test.
t812_repo() {
  local d="$TMP_ROOT/$1"
  rm -rf "$d"; mkdir -p "$d/.aai/scripts/lib"
  git -C "$d" init -q -b main
  git -C "$d" config user.email "test@example.invalid"; git -C "$d" config user.name "AAI Test"
  git -C "$d" commit -q --allow-empty -m init
  cp "$PROJECT_ROOT/.aai/scripts/pre-commit-checks.sh" "$d/.aai/scripts/pre-commit-checks.sh"
  cp "$PROJECT_ROOT/.aai/scripts/close-reconcile.mjs" "$d/.aai/scripts/close-reconcile.mjs"
  cp "$PROJECT_ROOT/.aai/scripts/pr-platform.mjs" "$d/.aai/scripts/pr-platform.mjs"
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs "$d/.aai/scripts/lib/"
  cp "$PROJECT_ROOT/.aai/scripts/install-pre-commit-hook.sh" "$d/.aai/scripts/install-pre-commit-hook.sh"
  printf '%s' "$d"
}
t812_install() {
  local d="$1"
  [[ -n "$d" && "$d" == /* ]] || { log_fail "t812_install: fixture path must be absolute (got '$d')"; return 1; }
  (cd "$d" && bash .aai/scripts/install-pre-commit-hook.sh --hooks index,close-gate)
}
t812_line() { node "$DOCTOR" --root "$1" 2>&1 | grep '^CAT-18' || true; }

test_812_cat18_guard_wiring() {
  local ok=1 d line

  # 1. both wired by the REAL installer -> PASS
  d="$(t812_repo t812-wired)"
  if ! t812_install "$d" >/dev/null 2>&1; then
    log_info "TEST-812: the real installer failed on the fixture"; ok=0
  fi
  line="$(t812_line "$d")"
  if [[ "$line" != "CAT-18 PASS"* ]]; then
    log_info "TEST-812 wired: expected 'CAT-18 PASS', got: ${line:-<no CAT-18 line>}"; ok=0
  fi

  # 2. pre-commit without the guard block -> WARN naming guard, marker, installer
  printf '#!/bin/sh\n# AAI:INDEX-AUTOGEN\n' > "$d/.git/hooks/pre-commit"
  chmod +x "$d/.git/hooks/pre-commit"
  line="$(t812_line "$d")"
  if [[ "$line" != "CAT-18 WARN"* || "$line" != *"pre-commit-checks.sh"* || "$line" != *"AAI:GUARD-CHECKS"* || "$line" != *"install-pre-commit-hook.sh"* ]]; then
    log_info "TEST-812 no-block: expected WARN naming pre-commit-checks.sh, AAI:GUARD-CHECKS and install-pre-commit-hook.sh, got: $line"; ok=0
  fi

  # 3. pre-push absent -> WARN naming close-reconcile.mjs and AAI:CLOSE-GATE
  d="$(t812_repo t812-nopush)"
  t812_install "$d" >/dev/null 2>&1 || { log_info "TEST-812: installer failed (nopush)"; ok=0; }
  rm -f "$d/.git/hooks/pre-push"
  line="$(t812_line "$d")"
  if [[ "$line" != "CAT-18 WARN"* || "$line" != *"close-reconcile.mjs"* || "$line" != *"AAI:CLOSE-GATE"* ]]; then
    log_info "TEST-812 pre-push absent: expected WARN naming close-reconcile.mjs and AAI:CLOSE-GATE, got: $line"; ok=0
  fi

  # 4. pre-push carries the marker but is not executable -> WARN naming it
  d="$(t812_repo t812-noexec)"
  t812_install "$d" >/dev/null 2>&1 || { log_info "TEST-812: installer failed (noexec)"; ok=0; }
  chmod -x "$d/.git/hooks/pre-push"
  line="$(t812_line "$d")"
  if [[ "$line" != "CAT-18 WARN"* || "$line" != *"not executable"* || "$line" != *"pre-push"* ]]; then
    log_info "TEST-812 not executable: expected WARN naming 'not executable' and pre-push, got: $line"; ok=0
  fi

  # 5. guard script absent -> the pair is not reported; the other pair PASSes
  d="$(t812_repo t812-noguard)"
  t812_install "$d" >/dev/null 2>&1 || { log_info "TEST-812: installer failed (noguard)"; ok=0; }
  rm -f "$d/.aai/scripts/close-reconcile.mjs" "$d/.git/hooks/pre-push"
  line="$(t812_line "$d")"
  if [[ "$line" != "CAT-18 PASS"* || "$line" == *"close-reconcile.mjs"* ]]; then
    log_info "TEST-812 guard absent: with close-reconcile.mjs absent the pre-push pair must not be reported and the line can be PASS, got: $line"; ok=0
  fi

  # 6. core.hooksPath honoured: hooks live in .custom-hooks, .git/hooks is empty
  d="$(t812_repo t812-hookspath)"
  git -C "$d" config core.hooksPath .custom-hooks
  t812_install "$d" >/dev/null 2>&1 || { log_info "TEST-812: installer failed (hooksPath)"; ok=0; }
  if [[ ! -f "$d/.custom-hooks/pre-push" ]]; then
    log_info "TEST-812 hooksPath: fixture precondition failed — the installer did not write into .custom-hooks"; ok=0
  fi
  rm -f "$d/.git/hooks/pre-commit" "$d/.git/hooks/pre-push"
  line="$(t812_line "$d")"
  if [[ "$line" != "CAT-18 PASS"* ]]; then
    log_info "TEST-812 hooksPath: expected PASS reading .custom-hooks, got: $line"; ok=0
  fi
  git -C "$d" config --unset core.hooksPath
  line="$(t812_line "$d")"
  if [[ "$line" != "CAT-18 WARN"* ]]; then
    log_info "TEST-812 hooksPath unset: with .git/hooks empty the verdict must be WARN, got: $line"; ok=0
  fi

  # 7. --json carries CAT-18
  local jout
  jout="$(node "$DOCTOR" --root "$TMP_ROOT/t812-wired" --json 2>&1)"
  if [[ "$jout" != *'"id": "CAT-18"'* ]]; then
    log_info "TEST-812 --json: missing \"id\": \"CAT-18\""; ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-812 CAT-18 guard wiring: wired PASS (real installer), missing block / missing pre-push / non-executable pre-push WARN by name, absent guard not reported, core.hooksPath honoured, --json carries CAT-18" \
    || log_fail "TEST-812 CAT-18 guard wiring"
}

# --- TEST-1528 (configurable-merge-policy-lanes Spec-AC-20) ----------------
# CAT-19 Merge Policy: absent docs/ai/merge-policy.yaml with no orphaned
# standing-authorization record is NOT REPORTED at all (no CAT-19 line, no
# CAT-19 id under --json); a valid policy is PASS lanes=N; an invalid one is
# WARN naming its validate code(s); an absent policy plus an owner-signed
# hitl_decision whose text contains STANDING MERGE AUTHORIZATION is WARN
# naming the record. Doctor runs the REAL .aai/scripts/merge-policy.mjs
# (found next to the real aai-doctor.mjs this suite invokes directly, same
# seam CAT-18's t812 helpers rely on) against each fixture's docs/ai/ files.
t1528_repo() {
  local d="$TMP_ROOT/$1"
  rm -rf "$d"; mkdir -p "$d/docs/ai"
  git -C "$d" init -q -b main
  git -C "$d" config user.email "test@example.invalid"; git -C "$d" config user.name "AAI Test"
  git -C "$d" commit -q --allow-empty -m init
  printf '%s' "$d"
}
t1528_line() { node "$DOCTOR" --root "$1" 2>&1 | grep '^CAT-19' || true; }

test_1528_cat19_merge_policy() {
  local ok=1 d line

  # 1. absent policy, no orphaned record -> not reported at all
  d="$(t1528_repo t1528-absent-clean)"
  line="$(t1528_line "$d")"
  if [[ -n "$line" ]]; then
    log_info "TEST-1528 absent clean: expected no CAT-19 line, got: $line"; ok=0
  fi
  local jout
  jout="$(node "$DOCTOR" --root "$d" --json 2>&1)"
  if [[ "$jout" == *'"id": "CAT-19"'* ]]; then
    log_info "TEST-1528 absent clean --json: unexpectedly carries CAT-19"; ok=0
  fi

  # 2. valid policy -> PASS lanes=1; --json carries CAT-19
  d="$(t1528_repo t1528-valid)"
  cat > "$d/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
kinds:
  - id: repo
    globs: ["**"]
lanes:
  - id: allow-all
    decision_ref: t1528ref@2026-01-01T00:00:00Z
    decision_match: approved
    signed_by: someone
    kinds: [repo]
    merge_reaches: nothing
    marker: AAI_T1528_MERGE
YAML
  cat > "$d/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"t1528ref","ts":"2026-01-01T00:00:00Z","owner_signoff":true,"actor":"someone","decision":"approved"}
JSONL
  line="$(t1528_line "$d")"
  if [[ "$line" != "CAT-19 PASS"* || "$line" != *"lanes=1"* ]]; then
    log_info "TEST-1528 valid: expected 'CAT-19 PASS' naming lanes=1, got: ${line:-<no CAT-19 line>}"; ok=0
  fi
  jout="$(node "$DOCTOR" --root "$d" --json 2>&1)"
  if [[ "$jout" != *'"id": "CAT-19"'* ]]; then
    log_info "TEST-1528 valid --json: missing \"id\": \"CAT-19\""; ok=0
  fi

  # 3. invalid policy -> WARN naming the validate code
  d="$(t1528_repo t1528-invalid)"
  cat > "$d/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
bogus_top_key: true
kinds:
  - id: repo
    globs: ["**"]
lanes: []
YAML
  line="$(t1528_line "$d")"
  if [[ "$line" != "CAT-19 WARN"* || "$line" != *"unknown_key"* ]]; then
    log_info "TEST-1528 invalid: expected 'CAT-19 WARN' naming unknown_key, got: ${line:-<no CAT-19 line>}"; ok=0
  fi

  # 4. absent policy, orphaned STANDING MERGE AUTHORIZATION record -> WARN
  #    naming it
  d="$(t1528_repo t1528-orphan)"
  cat > "$d/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"wave-2-roadmap","ts":"2026-09-12T19:56:52Z","owner_signoff":true,"actor":"someone","decision":"STANDING MERGE AUTHORIZATION for INTERNAL rides"}
JSONL
  line="$(t1528_line "$d")"
  if [[ "$line" != "CAT-19 WARN"* || "$line" != *"STANDING MERGE AUTHORIZATION"* || "$line" != *"wave-2-roadmap"* ]]; then
    log_info "TEST-1528 orphan: expected 'CAT-19 WARN' naming the orphaned wave-2-roadmap record, got: ${line:-<no CAT-19 line>}"; ok=0
  fi
  # an owner_signoff:false record is not a signed record -- still not reported
  d="$(t1528_repo t1528-unsigned)"
  cat > "$d/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"wave-2-roadmap","ts":"2026-09-12T19:56:52Z","owner_signoff":false,"actor":"someone","decision":"STANDING MERGE AUTHORIZATION for INTERNAL rides"}
JSONL
  line="$(t1528_line "$d")"
  if [[ -n "$line" ]]; then
    log_info "TEST-1528 unsigned: an owner_signoff:false record must not be reported as orphaned, got: $line"; ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-1528 CAT-19 merge policy: absent-clean not reported, valid PASS lanes=1, invalid WARN naming its code, an orphaned signed STANDING MERGE AUTHORIZATION record WARNs by name while an unsigned one stays unreported, --json carries CAT-19" \
    || log_fail "TEST-1528 CAT-19 merge policy"
}

# --- TEST-1558 (configurable-merge-policy-lanes Spec-AC-20, remediation round 5)
# A policy that parses but is not in the P1 canonical form (here: a quoted
# string where the canonical spelling is bare) is CAT-19 WARN naming
# code=noncanonical AND the one command that prints the canonical form
# (merge-policy.mjs --canonical), so the owner has the fix, not just the
# finding. Control: the same policy in canonical form is CAT-19 PASS.
test_1558_cat19_noncanonical_names_canonical_mode() {
  local ok=1 d line
  d="$(t1528_repo t1558-noncanonical)"
  cat > "$d/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
kinds:
  - id: repo
    globs: ["**"]
lanes:
  - id: allow-all
    decision_ref: t1558ref@2026-01-01T00:00:00Z
    decision_match: "approved"
    signed_by: someone
    kinds: [repo]
    merge_reaches: nothing
    marker: AAI_T1558_MERGE
YAML
  cat > "$d/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"t1558ref","ts":"2026-01-01T00:00:00Z","owner_signoff":true,"actor":"someone","decision":"approved"}
JSONL
  line="$(t1528_line "$d")"
  if [[ "$line" != "CAT-19 WARN"* || "$line" != *"code=noncanonical line=8"* ]]; then
    log_info "TEST-1558 noncanonical: expected 'CAT-19 WARN' naming code=noncanonical line=8, got: ${line:-<no CAT-19 line>}"; ok=0
  fi
  if [[ "$line" != *"merge-policy.mjs --canonical"* ]]; then
    log_info "TEST-1558 noncanonical: expected the WARN to name merge-policy.mjs --canonical, got: ${line:-<no CAT-19 line>}"; ok=0
  fi
  # control: the canonical spelling of the same policy is PASS
  sed -e 's/decision_match: "approved"/decision_match: approved/' "$d/docs/ai/merge-policy.yaml" > "$d/docs/ai/merge-policy.yaml.new"
  mv "$d/docs/ai/merge-policy.yaml.new" "$d/docs/ai/merge-policy.yaml"
  line="$(t1528_line "$d")"
  if [[ "$line" != "CAT-19 PASS"* ]]; then
    log_info "TEST-1558 canonical control: expected 'CAT-19 PASS', got: ${line:-<no CAT-19 line>}"; ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-1558 CAT-19: a noncanonical policy WARNs naming code=noncanonical and merge-policy.mjs --canonical; its canonical spelling is PASS" \
    || log_fail "TEST-1558 CAT-19 noncanonical names --canonical"
}

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="
  check_deps
  if [[ $# -gt 0 ]]; then
    # Single-test mode (mirrors test-aai-update.sh): used by the TDD lane to
    # capture per-test RED/GREEN evidence without running the whole suite.
    declare -F "$1" >/dev/null || { echo "Unknown test: $1" >&2; exit 2; }
    "$1"
    echo ""
    if [[ $FAILED -eq 0 ]]; then
      echo "Selected test passed."
      exit 0
    else
      echo "Selected test FAILED."
      exit 1
    fi
  fi
  test_001_cat01_fail_named
  test_002_cat02_fail_named
  test_003_cat03_orphan_warn
  test_004_cat04_dynamic_skills
  test_005_cat05_knowledge
  test_006_cat06_duplicate_key_fail
  test_007_cat07_telemetry
  test_008_cat08_git_status
  test_009_cat09_precompact
  test_010_cat10_migration_matrix
  test_011_cat11_docs_hygiene
  test_012_cat12_index_hook
  test_013_cat13_exit4_tolerated
  test_014_clean_fixture_doctor_clean
  test_015_json_shape
  test_016_exit_codes
  test_017_cwd_independence
  test_018_script_location_default_root
  test_019_real_repo_smoke
  test_020_usage_errors
  test_021_skill_doctor_thin_wrapper
  test_022_suite_map_row
  test_023_win_selftest_skip_off_windows
  test_024_selftest_structural_arm_pins
  test_025_selftest_reuse_structural_pin
  test_026_agent_cli_probe_fake_and_absent
  test_027_capability_fields_unknown
  test_028_output_shape_growth
  test_029_exit_matrix
  test_030_zero_network_pin
  test_031_hygiene_set
  test_032_documentation_pin
  test_033_codex_exec_detection_honesty
  test_034_cat14_warn_branch_and_strict
  test_035_0138_codex_exec_block_battery
  test_036_0138_cli_version_tristate
  test_037_0138_count_line_composition
  test_038_0139_canonical_invocation_fixtures
  test_039_0139_canonical_invocation_shape
  test_040_cat17_effective_path_and_probe
  test_1341_cat17_no_refusal_marker
  test_1342_cat17_control_arm_nonzero
  test_1343_cat17_permit_arm_refused
  test_1344_cat17_seam1_installed_hook_passes
  test_1345_cat17_decorative_hook_still_not_armed
  test_1346_resolve_ref_guard_launchers
  test_1347_ps1_quality_windows_cat17_step
  test_619_cat17_declined_is_not_an_issue
  test_620_cat17_declaration_never_over_reads
  test_812_cat18_guard_wiring
  test_1528_cat19_merge_policy
  test_1558_cat19_noncanonical_names_canonical_mode
  test_439_argv1_guard_resolves_symlinks

  echo ""
  if [[ $FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
  else
    echo "Some tests FAILED."
    exit 1
  fi
}

main "$@"
