#!/usr/bin/env bash
#
# Test: deslop scope-as-parameter + class-4 unrequested-surface engine
# (spec-deslop-scope-and-unrequested-engine). Exercises
# .aai/scripts/deslop-unrequested.mjs directly against mktemp git fixtures
# (TEST-001..008, TEST-010, TEST-013), the rewritten
# .aai/SKILL_DESLOP.prompt.md Scope section (TEST-009), the two pre-existing
# survival suites (TEST-011/012), the seven description-surface drift check
# plus catalog regeneration idempotence (TEST-014), and the wrong-cwd
# empty-surface NOTE degrade (TEST-016).
#
# 2026-08-15 AMENDMENT (owner hitl_decision, docs/ai/decisions.jsonl
# ref_id deslop-scope-and-unrequested-engine, ts 2026-08-15T08:14:24Z):
# the extractor-kind set narrowed from five kinds to two (cli-flag,
# yaml-key) — mjs-export/sh-func/ps1-func extracted INTERNAL symbols no
# requirement is expected to name, and are REMOVED, not gated. TEST-015 is
# REPURPOSED (its original mjs-export brace-list coverage no longer applies)
# to prove the companion cli-flag precision fix (closes follow-up
# fu-deslop-cliflag-kind-precision): CSS custom properties and flags this
# code merely passes to an external subprocess are excluded from cli-flag
# candidates, while a flag passed to `node` (this repo's own other scripts)
# and a genuine own-flag both still match.
#
# Covers TEST-001..017 from
# docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md,
# including two round-4 code-review regression arms folded into the table by
# this amendment (round-3's F12 precedent: every arm must be listed):
# TEST-007's added noScannedPath arm (B2 — a non-empty diff outside the
# scanned globs must never read as "empty diff") and TEST-017 (NB-1 — a git
# failure in a non-git cwd must say so, not read as a clean empty-diff
# scan).
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-deslop"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

ENGINE="$PROJECT_ROOT/.aai/scripts/deslop-unrequested.mjs"
DESLOP_PROMPT="$PROJECT_ROOT/.aai/SKILL_DESLOP.prompt.md"

FAILED=0
WORKDIRS=()

cleanup() {
  local d
  for d in "${WORKDIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
}
trap cleanup EXIT

log_pass() { echo "PASS $*"; }
log_fail() { echo "FAIL $*" >&2; FAILED=1; }
log_skip() { echo "SKIP $*"; exit 42; }
log_info() { echo "  $*"; }

check_deps() {
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  [[ -f "$ENGINE" ]] || log_skip "$ENGINE not found"
}

sha_cmd() {
  if command -v shasum >/dev/null 2>&1; then
    echo "shasum -a 256"
  else
    echo "sha256sum"
  fi
}

# manifest_of <dir> — sorted "<hash>  <relpath>" lines for every file.
manifest_of() {
  local dir="$1"
  (cd "$dir" && find . -type f | LC_ALL=C sort | xargs $(sha_cmd) 2>/dev/null)
}

# new_fixture — an empty, absolute mktemp dir. Fixture-helper rule (LEARNED
# 2026-07-27): never hand back / operate on an empty or relative path.
new_fixture() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/aai-deslop-fixture.XXXXXX")"
  if [[ -z "$d" || "$d" != /* ]]; then
    log_fail "new_fixture: unsafe temp dir '$d'"
    return 1
  fi
  WORKDIRS+=("$d")
  echo "$d"
}

# init_repo <dir> — git init -b main (a fresh checkout has no local main),
# minimal identity, one initial commit so HEAD exists.
init_repo() {
  local d="$1"
  [[ -n "$d" && "$d" = /* ]] || { log_fail "init_repo: unsafe dir '$d'"; return 1; }
  (
    cd "$d" &&
    git init -q -b main &&
    git config user.email 'deslop-test@example.com' &&
    git config user.name 'deslop-test' &&
    mkdir -p .aai/scripts .aai/system docs/specs docs/ai docs/issues &&
    echo '# fixture' > README.md &&
    git add -A &&
    git commit -q -m 'init'
  )
}

# run_engine <dir> <args...> — invokes the REAL engine (absolute path)
# against the fixture cwd. Combined stdout+stderr, trailing EXIT:<n> marker.
run_engine() {
  local d="$1"; shift
  (cd "$d" && node "$ENGINE" "$@" 2>&1; echo "EXIT:$?")
}

engine_exit_code() {
  tail -1 <<<"$1" | sed -n 's/^EXIT:\([0-9]*\)$/\1/p'
}

engine_body() {
  sed '$d' <<<"$1"
}

# node_check <json_text> <js_bool_expr referencing d> — 0 == expr true.
node_check() {
  local json="$1" expr="$2"
  node -e '
    let s = "";
    process.stdin.on("data", c => s += c);
    process.stdin.on("end", () => {
      let d;
      try { d = JSON.parse(s); } catch (e) { console.error("JSON parse failed: " + e.message); process.exit(2); }
      let ok;
      try { ok = !!(eval(process.argv[1])); } catch (e) { console.error("expr threw: " + e.message); process.exit(2); }
      process.exit(ok ? 0 : 1);
    });
  ' "$expr" <<<"$json"
}

# ---------------------------------------------------------------------------
# TEST-001 (Spec-AC-01) — no scope flag, unknown flag, and both-scopes-given
# all fail closed: exit 2, usage names both flags, zero candidate lines.
# ---------------------------------------------------------------------------
test_001_no_scope_fails_closed() {
  local d out code body ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-001 init_repo failed"; return; }

  out="$(run_engine "$d")"
  code="$(engine_exit_code "$out")"
  body="$(engine_body "$out")"
  [[ "$code" == "2" ]] || { log_info "TEST-001: no-flag exit=$code (want 2)"; ok=0; }
  grep -qF -- "--diff" <<<"$body" || { log_info "TEST-001: usage text missing --diff"; ok=0; }
  grep -qF -- "--all" <<<"$body" || { log_info "TEST-001: usage text missing --all"; ok=0; }
  if grep -qE '(cli-flag|yaml-key)' <<<"$body"; then
    log_info "TEST-001: a candidate/kind token leaked into a usage error"
    ok=0
  fi

  local out2 code2
  out2="$(run_engine "$d" --bogus)"
  code2="$(engine_exit_code "$out2")"
  [[ "$code2" == "2" ]] || { log_info "TEST-001: unknown flag exit=$code2 (want 2)"; ok=0; }

  local out3 code3
  out3="$(run_engine "$d" --diff --all)"
  code3="$(engine_exit_code "$out3")"
  [[ "$code3" == "2" ]] || { log_info "TEST-001: --diff --all together exit=$code3 (want 2, ambiguous scope)"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-001 no-scope / unknown-flag / ambiguous-scope all fail closed at exit 2, usage names both flags" \
    || log_fail "TEST-001 fail-closed usage"
}

# ---------------------------------------------------------------------------
# TEST-002 (Spec-AC-02) — diff scope reports exactly the added unnamed
# symbol; a context-line (pre-existing) symbol never appears; explicit
# --base and a missing --base both resolve correctly (SEAM-2).
# ---------------------------------------------------------------------------
test_002_diff_scope_added_symbol_only() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-002 init_repo failed"; return; }

  cat > "$d/.aai/scripts/sample.mjs" <<'EOF'
const USAGE = 'Usage: sample.mjs --already-there-flag <v>';
EOF
  cat > "$d/docs/specs/SPEC-x.md" <<'EOF'
---
id: spec-x
type: spec
number: null
status: done
---
# Spec X

This change adds --named-flag to sample.mjs.
EOF
  cat > "$d/docs/ai/STATE.yaml" <<'EOF'
current_focus:
  type: intake_change
  ref_id: x
  primary_path: null
  spec_path: docs/specs/SPEC-x.md
EOF
  (cd "$d" && git add -A && git commit -q -m 'baseline')

  # working-tree change: two new flags, one named by the corpus, one not.
  cat >> "$d/.aai/scripts/sample.mjs" <<'EOF'
if (tok === '--named-flag') { /* handled */ }
if (tok === '--unnamed-flag') { /* handled */ }
EOF

  local json out code
  out="$(run_engine "$d" --diff --base main --json)"
  code="$(engine_exit_code "$out")"
  json="$(engine_body "$out")"
  [[ "$code" == "0" ]] || { log_info "TEST-002: --base main exit=$code (want 0)"; ok=0; }
  node_check "$json" 'd.candidates.length === 1' \
    || { log_info "TEST-002: --base main candidates.length != 1: $json"; ok=0; }
  node_check "$json" 'd.candidates[0] && d.candidates[0].symbol === "--unnamed-flag" && d.candidates[0].kind === "cli-flag" && d.candidates[0].path === ".aai/scripts/sample.mjs" && d.candidates[0].line === 3' \
    || { log_info "TEST-002: --base main candidate row mismatch: $json"; ok=0; }
  node_check "$json" 'd.diff_input === "working tree"' \
    || { log_info "TEST-002: --base main pointing at HEAD should fall back to working tree: $json"; ok=0; }
  node_check "$json" 'd.limits.length === 4' \
    || { log_info "TEST-002: working-tree mode should carry exactly 4 limits (no range-mode disclosure): $json"; ok=0; }

  # missing/nonexistent --base ref: same fallback, same result (SEAM-2).
  local out4 json4 code4
  out4="$(run_engine "$d" --diff --base does-not-exist-ref --json)"
  code4="$(engine_exit_code "$out4")"
  json4="$(engine_body "$out4")"
  [[ "$code4" == "0" ]] || { log_info "TEST-002: missing --base exit=$code4 (want 0)"; ok=0; }
  node_check "$json4" 'd.diff_input === "working tree" && d.candidates.length === 1 && d.candidates[0].symbol === "--unnamed-flag"' \
    || { log_info "TEST-002: missing --base fallback result mismatch: $json4"; ok=0; }

  # range-mode arm (F3): the two arms above both take the working-tree
  # fallback because HEAD == main in a freshly committed fixture — the
  # range branch (`git diff --unified=0 <base>...HEAD`) was never exercised
  # by any fixture. Fold the prior working-tree change into main first (so
  # it does not leak into this arm's diff), then diverge main and HEAD with
  # a feature-branch commit that adds exactly one new symbol.
  (cd "$d" && git add -A && git commit -q -m 'fold prior working-tree change into main')
  (cd "$d" && git checkout -q -b feature)
  cat >> "$d/.aai/scripts/sample.mjs" <<'EOF'
if (tok === '--unnamed-flag-two') { /* handled */ }
EOF
  (cd "$d" && git add -A && git commit -q -m 'feature branch commit')

  local out5 json5 code5
  out5="$(run_engine "$d" --diff --base main --json)"
  code5="$(engine_exit_code "$out5")"
  json5="$(engine_body "$out5")"
  [[ "$code5" == "0" ]] || { log_info "TEST-002: range-mode (main != HEAD) exit=$code5 (want 0)"; ok=0; }
  node_check "$json5" 'd.diff_input === "main...HEAD"' \
    || { log_info "TEST-002: range-mode diff_input mismatch (want main...HEAD): $json5"; ok=0; }
  node_check "$json5" 'd.candidates.length === 1 && d.candidates[0].symbol === "--unnamed-flag-two" && d.candidates[0].kind === "cli-flag"' \
    || { log_info "TEST-002: range-mode candidate mismatch: $json5"; ok=0; }
  # V4-1 (fu-deslop-range-mode-dirty-worktree, tracked OPEN, not fixed —
  # only disclosed): range mode carries a 4th LIMITS line naming the open
  # dirty-worktree caveat; working-tree mode above must not.
  node_check "$json5" 'd.limits.length === 5 && d.limits[4].includes("RANGE MODE") && d.limits[4].includes("fu-deslop-range-mode-dirty-worktree")' \
    || { log_info "TEST-002: range-mode should disclose the open dirty-worktree LIMITS line: $json5"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-002 diff scope reports exactly the unnamed added symbol; context line excluded; explicit + missing --base both fall back to working tree; a diverged main resolves to range mode and discloses the open dirty-worktree caveat" \
    || log_fail "TEST-002 diff scope added-symbol reporting"
}

# ---------------------------------------------------------------------------
# TEST-003 (Spec-AC-03) — wide scope reports every unmentioned symbol across
# both extractor kinds (NARROWED 2026-08-15 from five to two — cli-flag,
# yaml-key — per the owner amendment; see spec D3) and none of the mentioned
# ones; a file present in both a --diff and an --all run yields
# byte-identical candidate rows for that file (one shared extraction+match
# path).
# ---------------------------------------------------------------------------
test_003_all_scope_both_kinds_and_shared_engine() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-003 init_repo failed"; return; }

  cat > "$d/.aai/scripts/lib_a.mjs" <<'EOF'
if (tok === '--keep-flag-a') { /* handled */ }
if (tok === '--drop-flag-a') { /* handled */ }
EOF
  cat > "$d/.aai/scripts/tool.sh" <<'EOF'
echo "Usage: tool.sh --keep-flag --drop-flag"
EOF
  cat > "$d/.aai/scripts/tool.ps1" <<'EOF'
$null = '--keep-flag-ps1 <v>'
$null = '--drop-flag-ps1 <v>'
EOF
  cat > "$d/.aai/system/config.yaml" <<'EOF'
keepKey: 1
dropKey: 2
EOF
  cat > "$d/docs/specs/SPEC-0001-fixture.md" <<'EOF'
---
id: spec-0001-fixture
type: spec
number: null
status: done
---
# Fixture Spec

Mentions --keep-flag-a, --keep-flag, --keep-flag-ps1, keepKey, and
--shared-named-flag explicitly.
EOF
  cat > "$d/docs/ai/STATE.yaml" <<'EOF'
current_focus:
  type: intake_change
  ref_id: fixture
  primary_path: null
  spec_path: docs/specs/SPEC-0001-fixture.md
EOF
  (cd "$d" && git add -A && git commit -q -m 'surface baseline')

  # working-tree-only addition: a file present in BOTH scopes' scanned set.
  cat > "$d/.aai/scripts/shared.mjs" <<'EOF'
if (tok === '--shared-named-flag') { /* handled */ }
if (tok === '--shared-unnamed-flag') { /* handled */ }
EOF

  local outAll jsonAll codeAll
  outAll="$(run_engine "$d" --all --json)"
  codeAll="$(engine_exit_code "$outAll")"
  jsonAll="$(engine_body "$outAll")"
  [[ "$codeAll" == "0" ]] || { log_info "TEST-003: --all exit=$codeAll (want 0)"; ok=0; }
  node_check "$jsonAll" 'd.surface.extractor_kinds === 2' \
    || { log_info "TEST-003: extractor_kinds should be 2 (narrowed from five): $jsonAll"; ok=0; }

  local expected='
    const want = [
      { path: ".aai/scripts/lib_a.mjs", line: 2, kind: "cli-flag", symbol: "--drop-flag-a" },
      { path: ".aai/scripts/tool.sh", line: 1, kind: "cli-flag", symbol: "--drop-flag" },
      { path: ".aai/scripts/tool.ps1", line: 2, kind: "cli-flag", symbol: "--drop-flag-ps1" },
      { path: ".aai/system/config.yaml", line: 2, kind: "yaml-key", symbol: "dropKey" },
      { path: ".aai/scripts/shared.mjs", line: 2, kind: "cli-flag", symbol: "--shared-unnamed-flag" },
    ];
    const norm = a => JSON.stringify([...a].sort((x,y)=> (x.path+x.kind+x.symbol).localeCompare(y.path+y.kind+y.symbol)));
    norm(d.candidates) === norm(want)
  '
  node_check "$jsonAll" "$expected" \
    || { log_info "TEST-003: --all candidate set mismatch: $jsonAll"; ok=0; }

  local outDiff jsonDiff codeDiff
  outDiff="$(run_engine "$d" --diff --base main --json)"
  codeDiff="$(engine_exit_code "$outDiff")"
  jsonDiff="$(engine_body "$outDiff")"
  [[ "$codeDiff" == "0" ]] || { log_info "TEST-003: --diff exit=$codeDiff (want 0)"; ok=0; }
  node_check "$jsonDiff" 'd.candidates.length === 1 && d.candidates[0].path === ".aai/scripts/shared.mjs" && d.candidates[0].symbol === "--shared-unnamed-flag"' \
    || { log_info "TEST-003: --diff candidate set mismatch (should be ONLY shared.mjs --shared-unnamed-flag): $jsonDiff"; ok=0; }

  # one-engine proof: the shared.mjs row is byte-identical across scopes.
  local rowAll rowDiff
  rowAll="$(node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8")); console.log(JSON.stringify(d.candidates.find(c=>c.path===".aai/scripts/shared.mjs")));' <<<"$jsonAll")"
  rowDiff="$(node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8")); console.log(JSON.stringify(d.candidates[0]));' <<<"$jsonDiff")"
  if [[ "$rowAll" != "$rowDiff" ]]; then
    log_info "TEST-003: shared.mjs candidate row differs between scopes: all=$rowAll diff=$rowDiff"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-003 wide scope covers both extractor kinds correctly; shared-file row byte-identical across scopes (one engine)" \
    || log_fail "TEST-003 wide scope + shared-engine proof"
}

# ---------------------------------------------------------------------------
# TEST-004 (Spec-AC-04) — corpus selection by status with per-status
# excluded counts (--all); STATE present is read and cmp-proven unchanged;
# STATE absent / STATE truncated each give the named EMPTY-corpus note.
# ---------------------------------------------------------------------------
test_004_corpus_selection_and_state_handling() {
  local ok=1

  # (a) --all: status-bucket counts.
  local d
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-004(a) init_repo failed"; return; }
  local status
  for status in accepted implementing done draft proposed rejected superseded deferred; do
    cat > "$d/docs/specs/SPEC-$status.md" <<EOF
---
id: spec-$status
type: spec
number: null
status: $status
---
# Spec $status
EOF
  done
  cat > "$d/docs/specs/SPEC-notaspec.md" <<'EOF'
---
id: spec-notaspec
type: issue
number: null
status: done
---
# Not a spec
EOF
  (cd "$d" && git add -A && git commit -q -m 'status fixtures')
  local out json
  out="$(run_engine "$d" --all --json)"
  json="$(engine_body "$out")"
  node_check "$json" 'd.requirement_corpus.count === 3 && d.requirement_corpus.excluded.draft === 1 && d.requirement_corpus.excluded.proposed === 1 && d.requirement_corpus.excluded.rejected === 1 && d.requirement_corpus.excluded.superseded === 1 && d.requirement_corpus.excluded.deferred === 1' \
    || { log_info "TEST-004(a): status-bucket counts wrong: $json"; ok=0; }
  # NB-3 regression guard (round-4 code review; previously unguarded per
  # round-4 validation V4-5): the NOT_SCANNED_NOTE must state POSITIVELY
  # what IS scanned ("scanned surface is exactly ...") rather than only
  # listing what is not — a negative-only note would let a reader assume
  # all of .aai/ is scanned when only scripts/*.{mjs,sh,ps1} and
  # system/*.yaml actually are.
  node_check "$json" 'd.notes.some(n => n.includes("scanned surface is exactly") && n.includes(".aai/scripts/**/*.{mjs,sh,ps1}") && n.includes(".aai/system/*.yaml"))' \
    || { log_info "TEST-004(a): NOT_SCANNED_NOTE missing its positive scanned-surface statement: $json"; ok=0; }

  # (b) --diff: STATE present, read-only (cmp-proven unchanged).
  local d2
  d2="$(new_fixture)" || return
  init_repo "$d2" || { log_fail "TEST-004(b) init_repo failed"; return; }
  cat > "$d2/docs/ai/STATE.yaml" <<'EOF'
current_focus:
  type: intake_change
  ref_id: x
  primary_path: null
  spec_path: null
EOF
  (cd "$d2" && git add -A && git commit -q -m 'state fixture')
  local sum_cmd before after
  sum_cmd="$(sha_cmd)"
  before="$(cd "$d2" && $sum_cmd docs/ai/STATE.yaml)"
  run_engine "$d2" --diff --json >/dev/null
  after="$(cd "$d2" && $sum_cmd docs/ai/STATE.yaml)"
  [[ "$before" == "$after" ]] || { log_info "TEST-004(b): STATE.yaml changed after a --diff run"; ok=0; }

  # (c) --diff: STATE absent.
  local d3 out3 code3 body3
  d3="$(new_fixture)" || return
  init_repo "$d3" || { log_fail "TEST-004(c) init_repo failed"; return; }
  rm -f "$d3/docs/ai/STATE.yaml"
  out3="$(run_engine "$d3" --diff)"
  code3="$(engine_exit_code "$out3")"
  body3="$(engine_body "$out3")"
  [[ "$code3" == "0" ]] || { log_info "TEST-004(c): STATE absent exit=$code3 (want 0)"; ok=0; }
  grep -qF "requirement corpus EMPTY" <<<"$body3" || { log_info "TEST-004(c): no EMPTY-corpus note with STATE absent"; ok=0; }
  grep -qF "STATE.yaml absent" <<<"$body3" || { log_info "TEST-004(c): EMPTY-corpus reason does not name STATE.yaml absent"; ok=0; }

  # (d) --diff: STATE present but truncated before current_focus.
  local d4 out4 code4 body4
  d4="$(new_fixture)" || return
  init_repo "$d4" || { log_fail "TEST-004(d) init_repo failed"; return; }
  cat > "$d4/docs/ai/STATE.yaml" <<'EOF'
# docs/ai/STATE.yaml - AAI runtime state
project_status: active
EOF
  out4="$(run_engine "$d4" --diff)"
  code4="$(engine_exit_code "$out4")"
  body4="$(engine_body "$out4")"
  [[ "$code4" == "0" ]] || { log_info "TEST-004(d): STATE truncated exit=$code4 (want 0)"; ok=0; }
  grep -qF "requirement corpus EMPTY" <<<"$body4" || { log_info "TEST-004(d): no EMPTY-corpus note with STATE truncated"; ok=0; }
  grep -qi "unparseable" <<<"$body4" || { log_info "TEST-004(d): EMPTY-corpus reason does not name unparseable"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-004 corpus status-bucket counts + STATE read-only/absent/truncated all handled" \
    || log_fail "TEST-004 corpus selection + STATE handling"
}

# ---------------------------------------------------------------------------
# TEST-005 (Spec-AC-05) — the fixture tree is byte-identical (sha256
# manifest) and path-identical before and after both scopes run.
# ---------------------------------------------------------------------------
test_005_no_write_proof() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-005 init_repo failed"; return; }
  cat > "$d/.aai/scripts/x.mjs" <<'EOF'
if (tok === '--keep-x-flag') { /* handled */ }
if (tok === '--drop-x-flag') { /* handled */ }
EOF
  cat > "$d/docs/specs/SPEC-x.md" <<'EOF'
---
id: spec-x
type: spec
number: null
status: done
---
# Spec X
Mentions --keep-x-flag in prose.
EOF
  cat > "$d/docs/ai/STATE.yaml" <<'EOF'
current_focus:
  type: intake_change
  ref_id: x
  primary_path: null
  spec_path: docs/specs/SPEC-x.md
EOF
  (cd "$d" && git add -A && git commit -q -m 'fixture surface')

  local before after files_before files_after
  before="$(manifest_of "$d")"
  files_before="$(cd "$d" && find . -type f | LC_ALL=C sort)"

  run_engine "$d" --all --json >/dev/null
  run_engine "$d" --diff --base main --json >/dev/null

  after="$(manifest_of "$d")"
  files_after="$(cd "$d" && find . -type f | LC_ALL=C sort)"

  if [[ "$before" != "$after" ]]; then
    log_info "TEST-005: fixture content manifest changed after both scopes ran"
    ok=0
  fi
  if [[ "$files_before" != "$files_after" ]]; then
    log_info "TEST-005: fixture file list changed (a new path was created) after both scopes ran"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-005 fixture tree byte-identical and path-identical after both scopes run" \
    || log_fail "TEST-005 no-write proof"
}

# ---------------------------------------------------------------------------
# TEST-006 (Spec-AC-06) — exit 0 with no candidates, exit 0 with candidates,
# exit 0 over an empty input set; the only nonzero exit anywhere is 2.
# ---------------------------------------------------------------------------
test_006_exit_code_contract() {
  local ok=1

  # clean: a real corpus + real surface, but every symbol is matched.
  local dClean
  dClean="$(new_fixture)" || return
  init_repo "$dClean" || { log_fail "TEST-006(clean) init_repo failed"; return; }
  cat > "$dClean/.aai/scripts/all_named.mjs" <<'EOF'
if (tok === '--everything-named-flag') { /* handled */ }
EOF
  cat > "$dClean/docs/specs/SPEC-clean.md" <<'EOF'
---
id: spec-clean
type: spec
number: null
status: done
---
Mentions --everything-named-flag.
EOF
  (cd "$dClean" && git add -A && git commit -q -m 'clean fixture')
  local outClean codeClean jsonClean
  outClean="$(run_engine "$dClean" --all --json)"
  codeClean="$(engine_exit_code "$outClean")"
  jsonClean="$(engine_body "$outClean")"
  [[ "$codeClean" == "0" ]] || { log_info "TEST-006: clean run exit=$codeClean (want 0)"; ok=0; }
  node_check "$jsonClean" 'd.candidates.length === 0' \
    || { log_info "TEST-006: clean run still produced candidates: $jsonClean"; ok=0; }

  # with candidates: reuse TEST-005's fixture shape.
  local dWith
  dWith="$(new_fixture)" || return
  init_repo "$dWith" || { log_fail "TEST-006(with) init_repo failed"; return; }
  cat > "$dWith/.aai/scripts/x.mjs" <<'EOF'
if (tok === '--drop-me-flag') { /* handled */ }
EOF
  (cd "$dWith" && git add -A && git commit -q -m 'with-candidates fixture')
  local outWith codeWith
  outWith="$(run_engine "$dWith" --all --json)"
  codeWith="$(engine_exit_code "$outWith")"
  [[ "$codeWith" == "0" ]] || { log_info "TEST-006: with-candidates run exit=$codeWith (want 0)"; ok=0; }

  # empty input set: no .aai/scripts files, no docs/specs — --all trivially empty.
  local dEmpty outEmpty codeEmpty
  dEmpty="$(new_fixture)" || return
  init_repo "$dEmpty" || { log_fail "TEST-006(empty) init_repo failed"; return; }
  outEmpty="$(run_engine "$dEmpty" --all --json)"
  codeEmpty="$(engine_exit_code "$outEmpty")"
  [[ "$codeEmpty" == "0" ]] || { log_info "TEST-006: empty-input-set run exit=$codeEmpty (want 0)"; ok=0; }

  # exit 2 for an unknown flag.
  local outBad codeBad
  outBad="$(run_engine "$dEmpty" --nope)"
  codeBad="$(engine_exit_code "$outBad")"
  [[ "$codeBad" == "2" ]] || { log_info "TEST-006: unknown flag exit=$codeBad (want 2)"; ok=0; }

  # source-level proof: no process.exit call anywhere uses a value other
  # than 0 or 2.
  local bad_exits
  bad_exits="$(grep -oE 'process\.exit\([0-9]+\)' "$ENGINE" | grep -vE 'process\.exit\((0|2)\)' || true)"
  if [[ -n "$bad_exits" ]]; then
    log_info "TEST-006: engine source has a non-0/2 process.exit call: $bad_exits"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-006 exit 0 (clean / with-candidates / empty-input-set), exit 2 only for usage errors, source-proven" \
    || log_fail "TEST-006 exit-code contract"
}

# ---------------------------------------------------------------------------
# TEST-007 (Spec-AC-07) — an empty diff exits 0 with the literal
# rerun-with-all note; the prompt offers the wide scope at that point.
# ---------------------------------------------------------------------------
test_007_empty_diff_offers_all() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-007 init_repo failed"; return; }
  # no changes at all: working tree == HEAD == main.
  local out code body
  out="$(run_engine "$d" --diff)"
  code="$(engine_exit_code "$out")"
  body="$(engine_body "$out")"
  [[ "$code" == "0" ]] || { log_info "TEST-007: empty diff exit=$code (want 0)"; ok=0; }
  grep -qF "NOTE: empty diff — rerun with --all to scan accumulated surface." <<<"$body" \
    || { log_info "TEST-007: literal empty-diff note missing: $body"; ok=0; }

  grep -qF "rerun with --all" "$DESLOP_PROMPT" \
    || { log_info "TEST-007: prompt does not offer the wide scope on an empty diff"; ok=0; }
  if grep -qi "nothing to deslop" "$DESLOP_PROMPT"; then
    log_info "TEST-007: prompt still carries the retired terminal 'nothing to deslop' stop wording"
    ok=0
  fi

  # B2 (round-4 review) — a NON-empty diff whose only changed file sits
  # OUTSIDE the scanned globs (.aai/scripts/**.{mjs,sh,ps1}, .aai/system/*.
  # yaml) must never be reported as "empty diff": that told a downstream
  # project (whose changes are almost never under .aai/) that its real,
  # non-empty diff was empty. Reproduced pre-fix: a staged src/app.mjs
  # printed the literal empty-diff note at exit 0.
  local d2 out2 code2 body2
  d2="$(new_fixture)" || return
  init_repo "$d2" || { log_fail "TEST-007 (noScannedPath arm) init_repo failed"; return; }
  mkdir -p "$d2/src"
  cat > "$d2/src/app.mjs" <<'EOF'
export function brandNew() {}
EOF
  out2="$(run_engine "$d2" --diff)"
  code2="$(engine_exit_code "$out2")"
  body2="$(engine_body "$out2")"
  [[ "$code2" == "0" ]] || { log_info "TEST-007 (noScannedPath arm): exit=$code2 (want 0)"; ok=0; }
  if grep -qF "NOTE: empty diff" <<<"$body2"; then
    log_info "TEST-007 (noScannedPath arm): a non-empty diff outside the scanned surface must not read as 'empty diff': $body2"
    ok=0
  fi
  grep -qF "none are under the scanned surface" <<<"$body2" \
    || { log_info "TEST-007 (noScannedPath arm): missing the out-of-scope-but-not-empty note: $body2"; ok=0; }

  # V4-6 (round-4 validation, residual of the same B2 conflation) — a
  # DELETION-ONLY change to an existing scanned file (its `+++ b/<path>`
  # diff header appears, but zero lines are ADDED) must never read as
  # "empty diff": the diff genuinely touched a file, it just added nothing.
  # Reproduced pre-fix: touchedFiles filtered on `lines.size > 0`, which
  # drops a deletion-only file's Map entry (an empty Set, but still an
  # entry) and made the whole diff look empty.
  local d3 out3 code3 body3
  d3="$(new_fixture)" || return
  init_repo "$d3" || { log_fail "TEST-007 (deletion-only arm) init_repo failed"; return; }
  cat > "$d3/.aai/scripts/x.mjs" <<'EOF'
if (tok === '--flag-one') { /* handled */ }
if (tok === '--flag-two') { /* handled */ }
EOF
  (cd "$d3" && git add -A && git commit -q -m 'deletion-only baseline')
  cat > "$d3/.aai/scripts/x.mjs" <<'EOF'
if (tok === '--flag-one') { /* handled */ }
EOF
  out3="$(run_engine "$d3" --diff)"
  code3="$(engine_exit_code "$out3")"
  body3="$(engine_body "$out3")"
  [[ "$code3" == "0" ]] || { log_info "TEST-007 (deletion-only arm): exit=$code3 (want 0)"; ok=0; }
  if grep -qF "NOTE: empty diff" <<<"$body3"; then
    log_info "TEST-007 (deletion-only arm): a deletion-only diff must not read as 'empty diff': $body3"
    ok=0
  fi
  grep -qF "Candidates: 0" <<<"$body3" \
    || { log_info "TEST-007 (deletion-only arm): expected zero candidates (nothing was added): $body3"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-007 empty diff exits 0 with the literal rerun-with-all note (prompt offers --all, no terminal stop wording); a non-empty diff outside the scanned surface and a deletion-only diff each get their own honest treatment, never 'empty diff'" \
    || log_fail "TEST-007 empty diff + prompt offer + out-of-scope-diff + deletion-only honesty"
}

# ---------------------------------------------------------------------------
# TEST-008 (Spec-AC-08) — a fixture with 3 matched + 2 unmatched symbols
# reports suppressed == 3 in both forms; both forms carry the three
# disclosure sentences.
# ---------------------------------------------------------------------------
test_008_suppressed_count_and_disclosures() {
  local d ok=1 n_human_limits
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-008 init_repo failed"; return; }
  cat > "$d/.aai/scripts/mix.mjs" <<'EOF'
if (tok === '--matched-one-flag') { /* handled */ }
if (tok === '--matched-two-flag') { /* handled */ }
if (tok === '--matched-three-flag') { /* handled */ }
if (tok === '--unmatched-one-flag') { /* handled */ }
if (tok === '--unmatched-two-flag') { /* handled */ }
EOF
  cat > "$d/docs/specs/SPEC-mix.md" <<'EOF'
---
id: spec-mix
type: spec
number: null
status: done
---
Mentions --matched-one-flag, --matched-two-flag and --matched-three-flag
explicitly.
EOF
  (cd "$d" && git add -A && git commit -q -m 'suppressed-count fixture')

  local outJson codeJson jsonBody
  outJson="$(run_engine "$d" --all --json)"
  codeJson="$(engine_exit_code "$outJson")"
  jsonBody="$(engine_body "$outJson")"
  [[ "$codeJson" == "0" ]] || { log_info "TEST-008: --json run exit=$codeJson (want 0)"; ok=0; }
  node_check "$jsonBody" 'd.suppressed === 3 && d.candidates.length === 2' \
    || { log_info "TEST-008: suppressed/candidates count wrong: $jsonBody"; ok=0; }
  for sentence in "Pattern-based extraction, not a parser" "FALSE NEGATIVES" "Report only. No file was written." "TEXT, NOT A FLAG"; do
    grep -qF "$sentence" <<<"$jsonBody" || { log_info "TEST-008: --json missing disclosure '$sentence'"; ok=0; }
  done

  local outHuman bodyHuman
  outHuman="$(run_engine "$d" --all)"
  bodyHuman="$(engine_body "$outHuman")"
  grep -qF "Suppressed this run: 3." <<<"$bodyHuman" \
    || { log_info "TEST-008: human form missing 'Suppressed this run: 3.': $bodyHuman"; ok=0; }
  for sentence in "Pattern-based extraction, not a parser" "FALSE NEGATIVES" "Report only. No file was written." "TEXT, NOT A FLAG"; do
    grep -qF "$sentence" <<<"$bodyHuman" || { log_info "TEST-008: human form missing disclosure '$sentence'"; ok=0; }
  done

  # Round-5 remediation regression arm: the residual-class disclosure (10 of
  # 70 real-tree candidates are flag-shaped TEXT, not an owned flag — see
  # docs/ai/reports/deslop-candidate-adjudication-20260815.md, summarized in
  # the spec's Amendment section) is now a FOURTH always-present LIMITS line
  # alongside the original three — assert the count in both forms so
  # deleting the line (leaving only the original three) turns this suite red.
  node_check "$jsonBody" 'd.limits.length === 4 && d.limits[3].includes("TEXT, NOT A FLAG")' \
    || { log_info "TEST-008: --json limits[] should carry exactly 4 lines, the 4th being the TEXT-NOT-A-FLAG residual-class disclosure: $jsonBody"; ok=0; }
  n_human_limits="$(grep -cE '^  - ' <<<"$bodyHuman")"
  [[ "$n_human_limits" == "4" ]] \
    || { log_info "TEST-008: human LIMITS block should render exactly 4 lines, got $n_human_limits: $bodyHuman"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-008 suppressed == 3 in both forms; both carry all four disclosure sentences (including the residual-class TEXT-NOT-A-FLAG line)" \
    || log_fail "TEST-008 suppressed count + disclosures"
}

# ---------------------------------------------------------------------------
# TEST-009 (Spec-AC-09, also the prompt half of Spec-AC-01) — prompt grep
# contracts: ask-and-stop rule, both scope tokens, the scope-bound rewrite
# of the diff-scoped rule, the engine invocation line, <=90 lines.
# ---------------------------------------------------------------------------
test_009_prompt_scope_contracts() {
  local ok=1
  local n
  n=$(wc -l < "$DESLOP_PROMPT" | tr -d ' ')
  [[ "$n" -le 90 ]] || { log_info "TEST-009: $DESLOP_PROMPT is $n lines (> 90)"; ok=0; }

  grep -qi "ASK the operator" "$DESLOP_PROMPT" || { log_info "TEST-009: no ask-the-operator instruction"; ok=0; }
  grep -qF "STOP until answered" "$DESLOP_PROMPT" || { log_info "TEST-009: no STOP-until-answered instruction"; ok=0; }
  grep -qF -- "--diff" "$DESLOP_PROMPT" || { log_info "TEST-009: --diff token missing"; ok=0; }
  grep -qF -- "--all" "$DESLOP_PROMPT" || { log_info "TEST-009: --all token missing"; ok=0; }
  grep -qF "node .aai/scripts/deslop-unrequested.mjs --diff" "$DESLOP_PROMPT" \
    || { log_info "TEST-009: engine --diff invocation line missing"; ok=0; }
  grep -qF "node .aai/scripts/deslop-unrequested.mjs --all" "$DESLOP_PROMPT" \
    || { log_info "TEST-009: engine --all invocation line missing"; ok=0; }
  grep -qF "Under \`--diff\`" "$DESLOP_PROMPT" \
    || { log_info "TEST-009: the diff-scoped rule is not rewritten to name the scope it binds"; ok=0; }
  if grep -qF "Diff-scoped only:" "$DESLOP_PROMPT"; then
    log_info "TEST-009: the old absolute 'Diff-scoped only:' phrasing is still present"
    ok=0
  fi
  # NB-4 (round-4 review): --diff must never be described as the default —
  # the engine fails closed (exit 2) with neither flag, and this prompt's
  # own ask-and-stop rule two lines above exists precisely so an agent never
  # decays "ask" into "assume".
  if grep -qi -- "--diff.*(default)\|(default).*--diff" "$DESLOP_PROMPT"; then
    log_info "TEST-009: prompt still claims --diff is the default scope"
    ok=0
  fi
  # B1 (round-4 review): the suppressed count is at most an upper bound on
  # PROSE-SUPPRESSION false negatives — never a lower bound ("floor").
  if grep -qi "false-negative floor" "$DESLOP_PROMPT"; then
    log_info "TEST-009: prompt still calls the suppressed count a false-negative FLOOR (inverted bound)"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-009 prompt Scope contracts (<=90 lines, ask-and-stop, both tokens, engine lines, scope-bound rule, no false default, no inverted bound)" \
    || log_fail "TEST-009 prompt scope contracts"
}

# ---------------------------------------------------------------------------
# TEST-010 (Spec-AC-04) — wide scope against the REAL repository exits 0
# with a well-formed header + LIMITS block; the candidate count is reported,
# never asserted (it moves with every merge).
# ---------------------------------------------------------------------------
test_010_real_repo_all_scope_sanity() {
  local out code json ok=1
  out="$(run_engine "$PROJECT_ROOT" --all --json)"
  code="$(engine_exit_code "$out")"
  json="$(engine_body "$out")"
  [[ "$code" == "0" ]] || { log_info "TEST-010: real-repo --all exit=$code (want 0)"; ok=0; }
  node_check "$json" 'd.scope === "all" && d.limits.length === 4 && d.requirement_corpus.count > 0 && d.surface.files_scanned > 0' \
    || { log_info "TEST-010: real-repo --all JSON malformed or empty-of-substance"; ok=0; }
  local n s
  n="$(node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8")); console.log(d.candidates.length);' <<<"$json" 2>/dev/null || echo '?')"
  s="$(node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8")); console.log(d.suppressed);' <<<"$json" 2>/dev/null || echo '?')"
  log_info "TEST-010 baseline (not asserted): real-repo --all candidates=$n suppressed=$s"

  [[ $ok -eq 1 ]] && log_pass "TEST-010 real-repo --all scope exits 0 with well-formed header + LIMITS (candidates=$n, not pinned)" \
    || log_fail "TEST-010 real-repo --all scope sanity"
}

# ---------------------------------------------------------------------------
# TEST-011 (Spec-AC-09, SEAM-3) — the four pre-existing deslop pins in
# tests/skills/test-aai-advisory-skills.sh still pass after the rewrite.
# ---------------------------------------------------------------------------
test_011_advisory_skills_suite_still_green() {
  if bash "$PROJECT_ROOT/tests/skills/test-aai-advisory-skills.sh" >/dev/null 2>&1; then
    log_pass "TEST-011 tests/skills/test-aai-advisory-skills.sh exits 0 after the deslop prompt rewrite"
  else
    log_fail "TEST-011 tests/skills/test-aai-advisory-skills.sh failed after the deslop prompt rewrite"
  fi
}

# ---------------------------------------------------------------------------
# TEST-012 (Spec-AC-11, SEAM-4) — the prompt-diet ledger true-up: the pin
# equals -5262 + G and the new entry names both files and their
# measurements.
# ---------------------------------------------------------------------------
test_012_prompt_diet_ledger_true_up() {
  local ok=1
  if ! bash "$PROJECT_ROOT/tests/skills/test-aai-prompt-diet.sh" >/dev/null 2>&1; then
    log_info "TEST-012: tests/skills/test-aai-prompt-diet.sh failed"
    ok=0
  fi
  local ledger="$PROJECT_ROOT/tests/skills/lib/prompt-diet-ledger.sh"
  grep -qF "deslop-scope-and-unrequested-engine" "$ledger" \
    || { log_info "TEST-012: ledger has no deslop-scope-and-unrequested-engine entry"; ok=0; }
  grep -qF ".aai/SKILL_DESLOP.prompt.md" "$ledger" \
    || { log_info "TEST-012: ledger entry does not name .aai/SKILL_DESLOP.prompt.md"; ok=0; }
  grep -qF ".aai/AGENTS.md" "$ledger" \
    || { log_info "TEST-012: ledger entry does not name .aai/AGENTS.md"; ok=0; }
  [[ $ok -eq 1 ]] && log_pass "TEST-012 prompt-diet ledger true-up (suite green, entry names both files)" \
    || log_fail "TEST-012 prompt-diet ledger true-up"
}

# ---------------------------------------------------------------------------
# TEST-013 (Spec-AC-11, SEAM-5) — governance companions: PROFILES extended
# entry, suites.aai-deslop row globbing the engine + this suite, and
# check-test-registration.mjs exits 0 (every test_* wired into main()).
# ---------------------------------------------------------------------------
test_013_governance_companions() {
  local ok=1
  grep -qF ".aai/scripts/deslop-unrequested.mjs" "$PROJECT_ROOT/.aai/system/PROFILES.yaml" \
    || { log_info "TEST-013: PROFILES.yaml missing an extended entry for the engine"; ok=0; }
  grep -qF "aai-deslop:" "$PROJECT_ROOT/tests/skills/suite-map.yaml" \
    || { log_info "TEST-013: suite-map.yaml missing the suites.aai-deslop row"; ok=0; }
  grep -qF "deslop-unrequested.mjs" "$PROJECT_ROOT/tests/skills/suite-map.yaml" \
    || { log_info "TEST-013: suite-map.yaml aai-deslop row does not glob the engine"; ok=0; }
  if ! node "$PROJECT_ROOT/.aai/scripts/check-test-registration.mjs" >/dev/null 2>&1; then
    log_info "TEST-013: check-test-registration.mjs failed (an orphan test_* function exists)"
    ok=0
  fi
  [[ $ok -eq 1 ]] && log_pass "TEST-013 governance companions (PROFILES extended entry, suite-map row, full test registration)" \
    || log_fail "TEST-013 governance companions"
}

# ---------------------------------------------------------------------------
# TEST-014 (Spec-AC-10, SEAM-6) — none of the seven description surfaces
# claims diff-only, each names the --all scope; regenerating the docs hub
# leaves the catalog byte-idempotent (HTML) / content-idempotent (JSON,
# modulo the documented generatedAt timestamp field).
# ---------------------------------------------------------------------------
DESCRIPTION_SURFACES=(
  .claude/skills/aai-deslop/SKILL.md
  .codex/skills/aai-deslop/SKILL.md
  .gemini/skills/aai-deslop/SKILL.md
  .agents/skills/aai-deslop/SKILL.md
  SKILLS.md
  .aai/AGENTS.md
  docs/USER_GUIDE.md
)

test_014_description_surfaces_and_catalog_idempotence() {
  local ok=1 f
  for f in "${DESCRIPTION_SURFACES[@]}"; do
    if [[ ! -f "$PROJECT_ROOT/$f" ]]; then
      log_info "TEST-014: $f does not exist"
      ok=0
      continue
    fi
    if grep -qiE "diff-scoped|current diff only|CURRENT DIFF only" "$PROJECT_ROOT/$f"; then
      log_info "TEST-014: $f still claims the pass is diff-only"
      ok=0
    fi
    if ! grep -qF -- "--all" "$PROJECT_ROOT/$f"; then
      log_info "TEST-014: $f does not name the --all scope"
      ok=0
    fi
    # NB-4 (round-4 review): neither scope is a default — the engine fails
    # closed (exit 2) when invoked with neither flag, and the prompt's own
    # ask-and-stop rule exists precisely so "ask" never decays into
    # "assume". A surface calling --diff "(default)" defeats that D4 layer.
    if grep -qi -- "--diff.*(default)\|(default).*--diff" "$PROJECT_ROOT/$f"; then
      log_info "TEST-014: $f still claims --diff is the default scope"
      ok=0
    fi
  done

  # AC-10's second half is a DRIFT check ("regenerated from the new
  # descriptions rather than left stale"), not a purity check — so the
  # pre-regeneration hash MUST come from the artifact AS COMMITTED, before
  # the generator ever runs. Taking it after the first regeneration (the
  # prior shape) made a stale committed catalog and a generator that never
  # ran hash identically (both no-ops), so neither half of this test had a
  # failing witness (F2). Both generator invocations' exit codes are also
  # checked now — a dead generator no longer passes by leaving stale content
  # untouched. The two tracked artifacts are backed up and restored so this
  # test never leaves the working tree dirty (F5).
  local sum_cmd html_hash_before html_hash_after1 html_hash_after2
  local json_before json_after1 json_after2
  local html_bak json_bak
  html_bak="$(mktemp "${TMPDIR:-/tmp}/aai-deslop-html.XXXXXX")"
  json_bak="$(mktemp "${TMPDIR:-/tmp}/aai-deslop-json.XXXXXX")"
  cp "$PROJECT_ROOT/docs/SKILL_CATALOG.html" "$html_bak"
  cp "$PROJECT_ROOT/docs/skill-catalog-data.json" "$json_bak"
  sum_cmd="$(sha_cmd)"

  html_hash_before="$(cd "$PROJECT_ROOT" && $sum_cmd docs/SKILL_CATALOG.html | awk '{print $1}')"
  json_before="$(cd "$PROJECT_ROOT" && node -e 'const d=JSON.parse(require("fs").readFileSync("docs/skill-catalog-data.json","utf8")); delete d.generatedAt; console.log(JSON.stringify(d));')"

  if ! (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-hub.mjs) >/dev/null 2>&1; then
    log_info "TEST-014: generate-docs-hub.mjs (run 1) exited non-zero"
    ok=0
  fi
  html_hash_after1="$(cd "$PROJECT_ROOT" && $sum_cmd docs/SKILL_CATALOG.html | awk '{print $1}')"
  json_after1="$(cd "$PROJECT_ROOT" && node -e 'const d=JSON.parse(require("fs").readFileSync("docs/skill-catalog-data.json","utf8")); delete d.generatedAt; console.log(JSON.stringify(d));')"

  if [[ "$html_hash_before" != "$html_hash_after1" ]]; then
    log_info "TEST-014: docs/SKILL_CATALOG.html was stale (committed content did not match the generator's output)"
    ok=0
  fi
  if [[ "$json_before" != "$json_after1" ]]; then
    log_info "TEST-014: docs/skill-catalog-data.json was stale (committed content did not match the generator's output, modulo generatedAt)"
    ok=0
  fi
  if ! grep -qF -- "--all" "$PROJECT_ROOT/docs/SKILL_CATALOG.html"; then
    log_info "TEST-014: regenerated docs/SKILL_CATALOG.html deslop card does not name --all"
    ok=0
  fi
  if grep -qiE "diff-scoped|current diff only" "$PROJECT_ROOT/docs/SKILL_CATALOG.html"; then
    log_info "TEST-014: regenerated docs/SKILL_CATALOG.html deslop card still claims diff-only"
    ok=0
  fi

  if ! (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-hub.mjs) >/dev/null 2>&1; then
    log_info "TEST-014: generate-docs-hub.mjs (run 2) exited non-zero"
    ok=0
  fi
  html_hash_after2="$(cd "$PROJECT_ROOT" && $sum_cmd docs/SKILL_CATALOG.html | awk '{print $1}')"
  json_after2="$(cd "$PROJECT_ROOT" && node -e 'const d=JSON.parse(require("fs").readFileSync("docs/skill-catalog-data.json","utf8")); delete d.generatedAt; console.log(JSON.stringify(d));')"
  if [[ "$html_hash_after1" != "$html_hash_after2" ]]; then
    log_info "TEST-014: docs/SKILL_CATALOG.html not byte-idempotent across two regenerations"
    ok=0
  fi
  if [[ "$json_after1" != "$json_after2" ]]; then
    log_info "TEST-014: docs/skill-catalog-data.json not content-idempotent (modulo generatedAt) across two regenerations"
    ok=0
  fi

  cp "$html_bak" "$PROJECT_ROOT/docs/SKILL_CATALOG.html"
  cp "$json_bak" "$PROJECT_ROOT/docs/skill-catalog-data.json"
  rm -f "$html_bak" "$json_bak"

  [[ $ok -eq 1 ]] && log_pass "TEST-014 no description surface claims diff-only; catalog regeneration matches committed content (not stale) and is idempotent" \
    || log_fail "TEST-014 description surfaces + catalog idempotence"
}


# ---------------------------------------------------------------------------
# TEST-015 (Spec-D3 cli-flag precision — REPURPOSED 2026-08-15, then AMENDED
# again by round-5 remediation V5-1/V5-2) — closes follow-up
# fu-deslop-cliflag-kind-precision plus the two round-5 blocking findings: a
# CSS custom-property declaration and its var() usage are excluded; a flag
# passed to git through all three detected .mjs shapes (the
# git()/tryGit()/runGh() local-wrapper naming convention, a direct
# execFileSync('git', ...) call, and an aai-doctor.mjs-style cmd-passthrough
# wrapper) is excluded, INCLUDING when the real argument list is built one
# level away as a local array and passed by reference (V5-2, closes the
# unadmitted `--body` finding); a flag passed to `node` (this repo's own
# OTHER script) stays a candidate; a flag mentioned ONLY in a comment is now
# excluded everywhere, not just external-tool comments (V5-2, closes
# `--grep`/`--no-renames`/`--ouput`/`--exec`), while a genuine own-flag in
# REAL CODE still survives; and the .sh/.ps1 external-tool exclusion is now
# COMMAND-WORD- and POSITION-based rather than a bare "the word appears
# anywhere in this line" test (V5-1) — a script's OWN flag sitting BEFORE an
# external invocation, or beside one only inside a comment or a quoted
# string, is never swept in, while a genuine external invocation — including
# one nested inside `"$(...)"` — is still excluded.
# ---------------------------------------------------------------------------
test_015_cli_flag_precision_css_and_external_tool() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-015 init_repo failed"; return; }

  cat > "$d/.aai/scripts/precision.mjs" <<'EOF'
function git(args) { return require('child_process').execFileSync('git', args); }
function run(cmd, args) { return require('child_process').spawnSync(cmd, args); }
function renderStyles() {
  return `:root { --accent-color: #fff; } .x { color: var(--accent-color); }`;
}
function viaWrapperName() {
  return git(['status', '--porcelain-a']);
}
function viaDirectCall() {
  return require('child_process').execFileSync('git', ['diff', '--unified-b=0']);
}
function viaCmdPassthrough() {
  return run('git', ['log', '--oneline-c']);
}
function viaNodeSelfInvoke() {
  return require('child_process').execFileSync('node', ['other.mjs', '--relay-flag']);
}
function viaLocalArrayIndirectionShape() {
  // SHAPE convention: the array is the SECOND argument to execFileSync.
  const ghArgs = ['issue', 'create', '--repo', 'x/y', '--indirect-flag-a', 'v'];
  return require('child_process').execFileSync('gh', ghArgs, { mutating: true });
}
function runGh(args) { return require('child_process').execFileSync('gh', args); }
function viaRunGhIndirectionNameConv() {
  // NAME convention: the array is the FIRST argument to a runGh()-named
  // local wrapper — the exact shape of the round-5 V5-2 `--body` finding.
  const ghArgs2 = ['issue', 'create', '--indirect-flag-b', 'v'];
  return runGh(ghArgs2);
}
if (tok === '--own-flag') { /* handled */ }
// legacy alias, see --comment-only-flag (never really implemented, V5-2)
EOF
  cat > "$d/docs/specs/SPEC-precision.md" <<'EOF'
---
id: spec-precision
type: spec
number: null
status: done
---
# Spec precision
Mentions nothing extracted below, so nothing is suppressed.
EOF
  (cd "$d" && git add -A && git commit -q -m 'cli-flag precision fixture')

  local outAll jsonAll codeAll
  outAll="$(run_engine "$d" --all --json)"
  codeAll="$(engine_exit_code "$outAll")"
  jsonAll="$(engine_body "$outAll")"
  [[ "$codeAll" == "0" ]] || { log_info "TEST-015: --all exit=$codeAll (want 0)"; ok=0; }

  local expected='
    const want = [
      { path: ".aai/scripts/precision.mjs", kind: "cli-flag", symbol: "--relay-flag" },
      { path: ".aai/scripts/precision.mjs", kind: "cli-flag", symbol: "--own-flag" },
    ];
    const norm = a => JSON.stringify([...a].map(({path,kind,symbol})=>({path,kind,symbol})).sort((x,y)=> (x.path+x.kind+x.symbol).localeCompare(y.path+y.kind+y.symbol)));
    norm(d.candidates) === norm(want)
  '
  node_check "$jsonAll" "$expected" \
    || { log_info "TEST-015: cli-flag precision candidate set mismatch (want ONLY --relay-flag [node self-invoke, internal] and --own-flag [real code]; --accent-color [CSS], --porcelain-a/--unified-b/--oneline-c [git() wrapper/direct-call/cmd-passthrough], --repo/--indirect-flag-a [execFileSync 2nd-arg indirection]/--indirect-flag-b [runGh() 1st-arg indirection, V5-2] and --comment-only-flag [comment-only occurrence, V5-2] must all be excluded): $jsonAll"; ok=0; }

  # --diff arm: the SAME exclusions apply to a freshly ADDED line, not only
  # to settled --all surface.
  local d2
  d2="$(new_fixture)" || return
  init_repo "$d2" || { log_fail "TEST-015 (diff arm) init_repo failed"; return; }
  cat > "$d2/.aai/scripts/precision2.mjs" <<'EOF'
function git(args) { return require('child_process').execFileSync('git', args); }
EOF
  (cd "$d2" && git add -A && git commit -q -m 'precision2.mjs baseline')
  cat >> "$d2/.aai/scripts/precision2.mjs" <<'EOF'
function fetchAll() {
  return git(['fetch', '--depth-diff=1']);
}
if (tok === '--diff-own-flag') { /* handled */ }
// --diff-comment-only-flag never implemented (V5-2)
EOF

  local outDiff codeDiff jsonDiff
  outDiff="$(run_engine "$d2" --diff --json)"
  codeDiff="$(engine_exit_code "$outDiff")"
  jsonDiff="$(engine_body "$outDiff")"
  [[ "$codeDiff" == "0" ]] || { log_info "TEST-015 (diff arm): exit=$codeDiff (want 0)"; ok=0; }
  node_check "$jsonDiff" 'd.candidates.length === 1 && d.candidates[0].symbol === "--diff-own-flag" && d.candidates[0].kind === "cli-flag" && d.candidates[0].path === ".aai/scripts/precision2.mjs"' \
    || { log_info "TEST-015 (diff arm): expected ONLY --diff-own-flag (a git()-wrapper-passed --depth-diff must stay excluded, and a comment-only flag must never appear, even on an added line), got: $jsonDiff"; ok=0; }

  # --- shell arm (V5-1): the .sh/.ps1 external-tool exclusion is now
  # command-word- and position-based, not "does the WORD appear ANYWHERE in
  # this logical line". Reproduces the round-5 validation fixture directly:
  # of five flags a script genuinely owns, the pre-fix mechanism silently
  # dropped three (two only because the word "git" sat inside an echoed
  # string) — this arm proves all five now survive, while a REAL external
  # flag sitting AFTER "git" on the SAME line (--force-with-lease), and one
  # nested inside a double-quoted `"$(...)"` command substitution
  # (--git-path), are still excluded. This is the mutation witness:
  # deleting/no-opping findExternalSpansShell makes
  # --ownflag-near/--ownflag-comment/--dryflag reappear as FALSE exclusions
  # (this arm goes red) while --force-with-lease/--git-path would then leak
  # in as false candidates too.
  local d3
  d3="$(new_fixture)" || return
  init_repo "$d3" || { log_fail "TEST-015 (shell arm) init_repo failed"; return; }
  cat > "$d3/.aai/scripts/precision3.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --ownflag-far)     echo far ;;
  --ownflag-near)    git push origin main --force-with-lease ;;
  --ownflag-comment) echo "skips the git push step" ;;
  --dryflag)         echo "would run: git commit" ;;
  --subst-flag)      OUT="$(git rev-parse --git-path hooks/pre-push)" ;;
esac
EOF
  (cd "$d3" && git add -A && git commit -q -m 'shell precision fixture')

  local outShell codeShell jsonShell
  outShell="$(run_engine "$d3" --all --json)"
  codeShell="$(engine_exit_code "$outShell")"
  jsonShell="$(engine_body "$outShell")"
  [[ "$codeShell" == "0" ]] || { log_info "TEST-015 (shell arm): --all exit=$codeShell (want 0)"; ok=0; }
  local expectedShell='
    const want = [
      { path: ".aai/scripts/precision3.sh", kind: "cli-flag", symbol: "--ownflag-far" },
      { path: ".aai/scripts/precision3.sh", kind: "cli-flag", symbol: "--ownflag-near" },
      { path: ".aai/scripts/precision3.sh", kind: "cli-flag", symbol: "--ownflag-comment" },
      { path: ".aai/scripts/precision3.sh", kind: "cli-flag", symbol: "--dryflag" },
      { path: ".aai/scripts/precision3.sh", kind: "cli-flag", symbol: "--subst-flag" },
    ];
    const norm = a => JSON.stringify([...a].map(({path,kind,symbol})=>({path,kind,symbol})).sort((x,y)=> (x.path+x.kind+x.symbol).localeCompare(y.path+y.kind+y.symbol)));
    norm(d.candidates) === norm(want)
  '
  node_check "$jsonShell" "$expectedShell" \
    || { log_info "TEST-015 (shell arm): expected all five of this script's OWN case-label flags (--ownflag-far/--ownflag-near/--ownflag-comment/--dryflag/--subst-flag) to survive as candidates — 'git' on the SAME line as a case label (but AFTER it), in a comment, or inside a quoted string must never suppress it; only --force-with-lease [git's own flag, genuinely AFTER 'git' on the --ownflag-near line] and --git-path [git's own flag, reached through \"\$(...)\"] should be excluded): $jsonShell"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-015 cli-flag precision: CSS custom property, git()/direct-execFileSync/cmd-passthrough/local-array-indirection external-tool arguments and comment-only occurrences all excluded (.mjs); node self-invoke and genuine own-flags in real code survive under both scopes; the .sh external-tool exclusion is command-word/position-based so a script's own flag sitting BEFORE, or beside only in a comment/string, an external mention always survives, while a real (possibly \$(...)-nested) invocation genuinely AFTER the command word is still excluded" \
    || log_fail "TEST-015 cli-flag precision"
}

# ---------------------------------------------------------------------------
# TEST-016 (F6, Constitution art. 4 — no silent zero) — --all invoked from
# the wrong working directory (a subdirectory of the repo, e.g. .aai/) sees
# an empty surface (its .aai/scripts glob resolves relative to cwd) and must
# degrade with a NOTE, not report a clean-looking zero-candidate bill.
# ---------------------------------------------------------------------------
test_016_all_scope_empty_surface_note() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-016 init_repo failed"; return; }
  cat > "$d/.aai/scripts/lib.mjs" <<'EOF'
export function keepFn() {}
EOF
  (cd "$d" && git add -A && git commit -q -m 'surface fixture')

  local out code body
  out="$(cd "$d/.aai" && node "$ENGINE" --all 2>&1; echo "EXIT:$?")"
  code="$(engine_exit_code "$out")"
  body="$(engine_body "$out")"
  [[ "$code" == "0" ]] || { log_info "TEST-016: exit=$code (want 0)"; ok=0; }
  grep -qF "Surface scanned: 0 files" <<<"$body" \
    || { log_info "TEST-016: expected an empty surface when invoked from the wrong cwd: $body"; ok=0; }
  grep -qF "NOTE: surface EMPTY" <<<"$body" \
    || { log_info "TEST-016: empty-surface NOTE missing when invoked from the wrong directory: $body"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-016 --all scope invoked from the wrong cwd degrades with a NOTE instead of a silent zero-candidate clean bill" \
    || log_fail "TEST-016 empty-surface NOTE"
}

# ---------------------------------------------------------------------------
# TEST-017 (NB-1, Constitution art. 4 — degrade and report) — --diff invoked
# in a directory that is not a git repository (or where git itself is
# unusable) must say the git probe failed, not report a clean zero-candidate
# scan indistinguishable from a genuinely empty diff. Reproduced pre-fix:
# every tryGit() call swallowed its failure and the report read "Diff input:
# working tree" + "NOTE: empty diff" + "Candidates: 0" at exit 0.
# ---------------------------------------------------------------------------
test_017_git_failure_surfaced_not_silent() {
  local d ok=1
  d="$(mktemp -d "${TMPDIR:-/tmp}/aai-deslop-nongit.XXXXXX")"
  if [[ -z "$d" || "$d" != /* ]]; then
    log_fail "TEST-017: unsafe temp dir '$d'"
    return
  fi
  WORKDIRS+=("$d")
  # deliberately NOT a git repository: no init_repo call.

  local out code body
  out="$(cd "$d" && node "$ENGINE" --diff 2>&1; echo "EXIT:$?")"
  code="$(engine_exit_code "$out")"
  body="$(engine_body "$out")"
  [[ "$code" == "0" ]] || { log_info "TEST-017: exit=$code (want 0)"; ok=0; }
  grep -qF "NOTE: git failed" <<<"$body" \
    || { log_info "TEST-017: no git-failure NOTE in a non-git cwd: $body"; ok=0; }
  if grep -qF "NOTE: empty diff" <<<"$body"; then
    log_info "TEST-017: a git failure must not read as the ordinary empty-diff note (indistinguishable from a genuinely clean scan): $body"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-017 --diff in a non-git cwd surfaces the git failure explicitly, distinct from an empty-diff clean scan" \
    || log_fail "TEST-017 git-failure honesty"
}

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps

  test_001_no_scope_fails_closed
  test_002_diff_scope_added_symbol_only
  test_003_all_scope_both_kinds_and_shared_engine
  test_004_corpus_selection_and_state_handling
  test_005_no_write_proof
  test_006_exit_code_contract
  test_007_empty_diff_offers_all
  test_008_suppressed_count_and_disclosures
  test_009_prompt_scope_contracts
  test_010_real_repo_all_scope_sanity
  test_011_advisory_skills_suite_still_green
  test_012_prompt_diet_ledger_true_up
  test_013_governance_companions
  test_014_description_surfaces_and_catalog_idempotence
  test_015_cli_flag_precision_css_and_external_tool
  test_016_all_scope_empty_surface_note
  test_017_git_failure_surfaced_not_silent

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
