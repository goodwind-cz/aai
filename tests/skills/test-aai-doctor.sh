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
  local d="$TMP_ROOT/clean"
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
  local bare="$TMP_ROOT/clean-bare.git"
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

  # STATE.yaml absent entirely -> WARN, not FAIL (per-dev runtime file).
  local fixture2 out2
  fixture2="$(new_bare_fixture t006b)"
  add_core_and_role_files "$fixture2"
  rm -f "$fixture2/docs/ai/STATE.yaml"
  out2="$(node "$DOCTOR" --root "$fixture2" 2>&1)"
  if echo "$out2" | grep "^CAT-01" | grep -q FAIL && echo "$out2" | grep "^CAT-06" | grep -q "WARN"; then
    log_pass "TEST-006b CAT-06 missing STATE.yaml -> WARN (CAT-01 owns the FAIL)"
  else
    log_info "TEST-006b: got CAT-01=$(echo "$out2" | grep '^CAT-01') CAT-06=$(echo "$out2" | grep '^CAT-06')"
    log_fail "TEST-006b CAT-06 missing-state WARN"
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

# --- TEST-014 — fully clean fixture -> DOCTOR CLEAN, exit 0 -----------------
test_014_clean_fixture_doctor_clean() {
  local fixture out rc
  fixture="$(build_clean_fixture)"
  # Invoke the FIXTURE's own copy directly (not --root against the real
  # $DOCTOR) so its default-root resolution picks up the fixture's own
  # stubbed docs-audit.mjs / layer-drift.mjs siblings, not the real repo's.
  out="$(node "$fixture/.aai/scripts/aai-doctor.mjs" 2>&1)"; rc=$?
  if echo "$out" | grep -q "^DOCTOR CLEAN$" && [[ "$rc" -eq 0 ]]; then
    log_pass "TEST-014 fully-clean fixture -> DOCTOR CLEAN, exit 0"
  else
    log_info "TEST-014: rc=$rc, full output:"
    log_info "$out"
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
      if (!Array.isArray(j.categories) || j.categories.length !== 13) die("categories: want array of 13, got " + (j.categories && j.categories.length));
      const wantIds = [];
      for (let i = 1; i <= 13; i++) wantIds.push("CAT-" + String(i).padStart(2, "0"));
      const gotIds = j.categories.map(c => c.id);
      if (JSON.stringify(gotIds) !== JSON.stringify(wantIds)) die("category ids: " + JSON.stringify(gotIds));
      for (const c of j.categories) {
        if (!["PASS","WARN","FAIL","SKIP"].includes(c.status)) die("bad status for " + c.id + ": " + c.status);
        if (typeof c.reason !== "string" || c.reason.length === 0) die("empty reason for " + c.id);
        if (typeof c.name !== "string" || c.name.length === 0) die("empty name for " + c.id);
      }
      if (!["CLEAN","ISSUES"].includes(j.verdict)) die("bad verdict: " + j.verdict);
      if (typeof j.issues !== "number") die("issues not a number");
      if (typeof j.exit !== "number") die("exit not a number");
    });
  ' && log_pass "TEST-015 --json emits the documented shape (13 categories, CAT-01..13)" \
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

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="
  check_deps
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
