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
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-doctor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCTOR="$PROJECT_ROOT/.aai/scripts/aai-doctor.mjs"

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
  mkdir -p "$d/.aai/scripts"
  cp "$DOCTOR" "$d/.aai/scripts/aai-doctor.mjs"
  local helper
  for helper in "$@"; do
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
  if echo "$out" | grep -q "^CAT-01 FAIL" && echo "$out" | grep "^CAT-01" | grep -q "AGENTS.md"; then
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
  if echo "$out" | grep "^CAT-02" | grep -q "FAIL" && echo "$out" | grep "^CAT-02" | grep -q "VALIDATION.prompt.md"; then
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
  if echo "$out" | grep "^CAT-03" | grep -q "WARN" && echo "$out" | grep "^CAT-03" | grep -q "aai-orphan"; then
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
  if ! echo "$out" | grep "^CAT-04" | grep -q "WARN"; then
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
  if echo "$out" | grep "^CAT-04" | grep -q "PASS"; then
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
  if echo "$out" | grep "^CAT-05" | grep -q "WARN" \
    && echo "$out" | grep "^CAT-05" | grep -q "FACTS.md empty" \
    && echo "$out" | grep "^CAT-05" | grep -q "PATTERNS.md missing"; then
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
  cat > "$fixture/docs/ai/STATE.yaml" <<'EOF'
project_status: active
metrics:
  work_items: {}
metrics:
  work_items: {}
EOF
  local out
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if echo "$out" | grep "^CAT-06" | grep -q "FAIL"; then
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
  if echo "$out2" | grep "^CAT-01" | grep -vq FAIL && echo "$out2" | grep "^CAT-06" | grep -q "WARN" && [[ "$rc2" -eq 0 ]]; then
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
  if echo "$out" | grep "^CAT-07" | grep -q "METRICS.jsonl: 3 entries" \
    && echo "$out" | grep "^CAT-07" | grep -q "decisions.jsonl: 1 entries"; then
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
  if ! (echo "$out" | grep "^CAT-08" | grep -q "WARN" && echo "$out" | grep "^CAT-08" | grep -q "changed file"); then
    log_info "TEST-008a: got: $(echo "$out" | grep '^CAT-08')"
    log_fail "TEST-008a CAT-08 dirty tree WARN"
    return
  fi

  local fixture2 out2
  fixture2="$(new_bare_fixture t008-nongit)"
  add_core_and_role_files "$fixture2"
  out2="$(node "$DOCTOR" --root "$fixture2" 2>&1)"
  if echo "$out2" | grep "^CAT-08" | grep -q "SKIP"; then
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
  if ! echo "$out" | grep "^CAT-09" | grep -q "WARN"; then
    log_info "TEST-009a: got: $(echo "$out" | grep '^CAT-09')"
    log_fail "TEST-009a CAT-09 missing hook WARN"
    return
  fi
  mkdir -p "$fixture/.aai/scripts"
  : > "$fixture/.aai/scripts/pre-compact-save.sh"
  : > "$fixture/.aai/scripts/pre-compact-save.ps1"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if echo "$out" | grep "^CAT-09" | grep -q "PASS"; then
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
  if ! (echo "$out" | grep "^CAT-10" | grep -q "LEGACY"); then
    log_info "TEST-010a: got: $(echo "$out" | grep '^CAT-10')"
    log_fail "TEST-010a CAT-10 LEGACY case"
    return
  fi
  # INCONSISTENT: gitignored but still tracked.
  printf 'docs/ai/STATE.yaml\n' > "$fixture/.gitignore"
  git -C "$fixture" add .gitignore
  git -C "$fixture" commit -qm "add gitignore (STATE.yaml stays tracked)"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if echo "$out" | grep "^CAT-10" | grep -q "INCONSISTENT"; then
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
  if ! (echo "$out" | grep "^CAT-11" | grep -q "WARN" && echo "$out" | grep "^CAT-11" | grep -qi "not installed"); then
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
  if echo "$out" | grep "^CAT-11" | grep -q "PASS"; then
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
  if ! echo "$out" | grep "^CAT-12" | grep -q "WARN"; then
    log_info "TEST-012a: got: $(echo "$out" | grep '^CAT-12')"
    log_fail "TEST-012a CAT-12 not-installed WARN"
    return
  fi
  mkdir -p "$fixture/.git/hooks"
  printf '#!/bin/sh\nsome-foreign-hook\n' > "$fixture/.git/hooks/pre-commit"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if ! (echo "$out" | grep "^CAT-12" | grep -q "WARN" && echo "$out" | grep "^CAT-12" | grep -q "NOT AAI-managed"); then
    log_info "TEST-012b: got: $(echo "$out" | grep '^CAT-12')"
    log_fail "TEST-012b CAT-12 foreign-hook WARN"
    return
  fi
  printf '#!/bin/sh\n# AAI:INDEX-AUTOGEN\n' > "$fixture/.git/hooks/pre-commit"
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"
  if echo "$out" | grep "^CAT-12" | grep -q "PASS"; then
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
  mkdir -p "$fixture/.aai/scripts"
  cp "$PROJECT_ROOT/.aai/scripts/layer-drift.mjs" "$fixture/.aai/scripts/layer-drift.mjs"
  # No .aai/system/AAI_PIN.md -> real layer-drift.mjs exits 4 (unverifiable).
  out="$(node "$DOCTOR" --root "$fixture" 2>&1)"; rc=$?
  if echo "$out" | grep "^CAT-13" | grep -q "WARN" \
    && echo "$out" | grep "^CAT-13" | grep -qi "unverifiable" \
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
  if echo "$out" | grep -q "^DOCTOR CLEAN$"; then
    log_pass "TEST-014 fully-clean fixture -> DOCTOR CLEAN, exit 0"
  elif echo "$out" | grep -q "^DOCTOR ISSUES(2)$" \
    && echo "$out" | grep "^CAT-14" | grep -q "SKIP" \
    && echo "$out" | grep "^CAT-15" | grep -q "SKIP"; then
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
      if (!Array.isArray(j.categories) || j.categories.length !== 16) die("categories: want array of 16, got " + (j.categories && j.categories.length));
      const wantIds = [];
      for (let i = 1; i <= 16; i++) wantIds.push("CAT-" + String(i).padStart(2, "0"));
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
  ' && log_pass "TEST-015 --json emits the documented shape (16 categories, CAT-01..16, CAT-14/15/16 carry detail)" \
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
  if echo "$out" | grep -q "^CAT-01 PASS"; then
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
  if ! echo "$out" | grep -q "^DOCTOR "; then
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
  printf '%s\n' "$code_only" | grep -qE 'Move-Item|Rename-Item' \
    && { log_info "TEST-024: Move-Item/Rename-Item present in code"; ok=0; }
  printf '%s\n' "$code_only" | grep -qE 'Remove-Item.*[Dd]ecoy[Bb]ash' \
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
#     CAT-01..13 unchanged, categories grow 13 -> 16 on a clean fixture ------
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
      if (j.categories.length !== 16) die("categories.length=" + j.categories.length + " (want 16)");
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
  ' && log_pass "TEST-028 output shape: one line each, --json detail, CAT-01..13 unchanged, 13->16 growth" \
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

  grep -qE '^## \[unreleased\] — .*[Dd]octor' "$PROJECT_ROOT/CHANGELOG.md" \
    || { log_info "TEST-032: CHANGELOG.md missing an unreleased heading for this scope"; ok=0; }

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
  echo "$out2" | node -e '
    let d = "";
    process.stdin.on("data", c => d += c);
    process.stdin.on("end", () => {
      const j = JSON.parse(d);
      const die = (m) => { console.error(m); process.exit(1); };
      const c16 = j.categories.find(x => x.id === "CAT-16");
      const obs = c16.detail.codex_exec_subcommand;
      if (obs.available !== true) die("real command-list line did not register available=true: " + JSON.stringify(obs));
    });
  '
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

  if [[ "$BATTERY_FAILED" -eq 0 ]]; then
    log_pass "TEST-035 (0138-TEST-001) 11-fixture D1 battery: block-anchored verdicts, honest no-block UNKNOWN, CAT-16 PASS-only"
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

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="
  check_deps
  if [[ $# -gt 0 ]]; then
    # Single-test mode (mirrors test-aai-update.sh): used by the TDD lane to
    # capture per-test RED/GREEN evidence without running the whole suite.
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
