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

# base_ref — prints the ref that guards in this suite compare against, or
# NOTHING when no base exists. A BARE `main` does not resolve on a GitHub
# `pull_request` checkout: actions/checkout leaves a detached HEAD and only
# fetches the base as `origin/main`, so `git show main:<path>` throws there
# and every guard hanging off it silently stops guarding. Fourth occurrence
# of that exact class in this repository (docs/knowledge/LEARNED.md
# 2026-07-19; the same fallback is written at
# tests/skills/test-aai-spec-lint.sh, and .github/workflows/skill-suite.yml
# uses origin/<base>). Callers MUST fail closed on the empty result — a
# guard that cannot read its source of truth must not report PASS.
base_ref() {
  if (cd "$PROJECT_ROOT" && git rev-parse --verify -q origin/main >/dev/null 2>&1); then
    printf 'origin/main'
  elif (cd "$PROJECT_ROOT" && git rev-parse --verify -q main >/dev/null 2>&1); then
    printf 'main'
  fi
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
  # Re-baselined 3 -> 4 by spec-deslop-corpus-honesty (D1): the type filter is
  # now directory-independent, so SPEC-notaspec.md (type: issue, status: done,
  # created above to exercise the OLD type-only filter) is a legitimate corpus
  # member — it sits under docs/issues in spirit but is physically placed in
  # docs/specs, and D1 admits `issue` regardless of which allowlisted
  # directory it lives in. Do NOT "fix" this back to 3: the count genuinely
  # grew when the corpus semantics changed, it did not regress.
  node_check "$json" 'd.requirement_corpus.count === 4 && d.requirement_corpus.excluded.draft === 1 && d.requirement_corpus.excluded.proposed === 1 && d.requirement_corpus.excluded.rejected === 1 && d.requirement_corpus.excluded.superseded === 1 && d.requirement_corpus.excluded.deferred === 1' \
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
  # OUTSIDE the scanned globs (.aai/scripts/**/*.{mjs,sh,ps1}, .aai/system/
  # *.yaml) must never be reported as "empty diff": that told a downstream
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

# ---------------------------------------------------------------------------
# TEST-018 (Spec-AC-07) — PR #260 Codex finding (line 713): both refs of a
# --base range can resolve individually yet share no merge base (two
# unrelated histories) — `git diff <base>...HEAD` then exits 128 instead of
# printing a diff. That failure must surface as an explicit git-failure
# NOTE, never as the ordinary "empty diff" clean-scan note.
# ---------------------------------------------------------------------------
test_018_range_diff_failure_surfaced() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-018 init_repo failed"; return; }
  cat > "$d/.aai/scripts/x.mjs" <<'EOF'
if (tok === '--brand-new-flag') { /* handled */ }
EOF
  (cd "$d" && git add -A && git commit -q -m 'main-side baseline')

  # an orphan branch shares NO commit history with main, so main and this
  # branch's HEAD both resolve individually (--verify succeeds for both)
  # but have no merge base.
  (cd "$d" && git checkout -q --orphan other && git rm -rf -q . >/dev/null 2>&1)
  mkdir -p "$d/.aai/scripts"
  cat > "$d/.aai/scripts/y.mjs" <<'EOF'
if (tok === '--other-branch-flag') { /* handled */ }
EOF
  (cd "$d" && git add -A && git commit -q -m 'unrelated orphan history')

  local out code body
  out="$(run_engine "$d" --diff --base main)"
  code="$(engine_exit_code "$out")"
  body="$(engine_body "$out")"
  [[ "$code" == "0" ]] || { log_info "TEST-018: exit=$code (want 0)"; ok=0; }
  if grep -qF "NOTE: empty diff" <<<"$body"; then
    log_info "TEST-018: a range diff that fails outright (no merge base) must not read as 'empty diff': $body"
    ok=0
  fi
  grep -qF "no merge base" <<<"$body" \
    || { log_info "TEST-018: missing an explicit git-failure NOTE for the failed range diff: $body"; ok=0; }
  grep -qF "Candidates: 0" <<<"$body" \
    || { log_info "TEST-018: a failed range diff can produce no candidates (nothing was checked): $body"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-018 a --base range diff that fails outright (no merge base between two unrelated histories) surfaces an explicit git-failure NOTE rather than reading as a clean empty-diff scan" \
    || log_fail "TEST-018 range-diff failure honesty"
}

# ---------------------------------------------------------------------------
# TEST-019 (Spec-AC-07) — PR #260 Codex finding (line 748): a COMPLETE file
# deletion never emits `+++ b/<path>` (git prints `+++ /dev/null` for the
# new side instead), so the file previously got no Map entry at all. When
# it is the ONLY change, that misread the diff as empty. Same honesty class
# as V4-6 (a partial in-file deletion), one level up: the whole file, not
# just its content, was removed.
# ---------------------------------------------------------------------------
test_019_full_file_deletion_not_empty_diff() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-019 init_repo failed"; return; }
  cat > "$d/.aai/scripts/z.mjs" <<'EOF'
if (tok === '--doomed-flag') { /* handled */ }
EOF
  (cd "$d" && git add -A && git commit -q -m 'baseline with a file about to be deleted entirely')
  (cd "$d" && git rm -q .aai/scripts/z.mjs)

  local out code body
  out="$(run_engine "$d" --diff)"
  code="$(engine_exit_code "$out")"
  body="$(engine_body "$out")"
  [[ "$code" == "0" ]] || { log_info "TEST-019: exit=$code (want 0)"; ok=0; }
  if grep -qF "NOTE: empty diff" <<<"$body"; then
    log_info "TEST-019: a COMPLETE file deletion (+++ /dev/null, no +++ b/<path>) must not read as 'empty diff': $body"
    ok=0
  fi
  grep -qF "Surface scanned: 1 files" <<<"$body" \
    || { log_info "TEST-019: the deleted path must still count as a touched/scanned file: $body"; ok=0; }
  grep -qF "Candidates: 0" <<<"$body" \
    || { log_info "TEST-019: a pure deletion has nothing added, expected zero candidates: $body"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-019 a diff whose only change is a COMPLETE file deletion (+++ /dev/null) is preserved as touched, never misread as an empty diff" \
    || log_fail "TEST-019 full-file-deletion honesty"
}

# ---------------------------------------------------------------------------
# TEST-020 (Spec-AC-04) — PR #260 Codex finding (line 241): a stale or
# unreadable STATE.yaml spec_path/primary_path was silently dropped inside
# buildCorpusText while the result still reported the corpus count and kept
# empty: false — a corpus that failed to load looked identical to a corpus
# that had nothing to say. Mirrors resolveAllCorpus's own named-degrade
# pattern: fully-unreadable degrades to the EMPTY-corpus note; a partial
# read names every skipped path instead of dropping it.
# ---------------------------------------------------------------------------
test_020_unreadable_state_corpus_document_named() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-020(a) init_repo failed"; return; }
  # (a) BOTH focus paths are stale (point at documents that do not exist):
  # must degrade to the same named EMPTY-corpus note an absent/unparseable
  # STATE already produces, not silently drop the paths at empty: false.
  cat > "$d/docs/ai/STATE.yaml" <<'EOF'
current_focus:
  type: intake_change
  ref_id: x
  primary_path: docs/issues/CHANGE-does-not-exist.md
  spec_path: docs/specs/SPEC-does-not-exist.md
EOF
  cat > "$d/.aai/scripts/x.mjs" <<'EOF'
const USAGE = 'baseline, nothing new yet';
EOF
  (cd "$d" && git add -A && git commit -q -m 'baseline, stale STATE already committed')
  cat >> "$d/.aai/scripts/x.mjs" <<'EOF'
if (tok === '--brand-new-flag') { /* handled */ }
EOF

  local out json code
  out="$(run_engine "$d" --diff --json)"
  code="$(engine_exit_code "$out")"
  json="$(engine_body "$out")"
  [[ "$code" == "0" ]] || { log_info "TEST-020(a): exit=$code (want 0)"; ok=0; }
  node_check "$json" 'd.requirement_corpus.empty === true && d.requirement_corpus.empty_reason.includes("SPEC-does-not-exist.md") && d.requirement_corpus.empty_reason.includes("CHANGE-does-not-exist.md")' \
    || { log_info "TEST-020(a): a fully-stale STATE corpus should degrade to empty, naming both unreadable paths: $json"; ok=0; }
  node_check "$json" 'd.candidates.length === 1 && d.candidates[0].symbol === "--brand-new-flag"' \
    || { log_info "TEST-020(a): a degraded-to-empty corpus should report every extracted symbol, none silently suppressed: $json"; ok=0; }
  # V-1 (validation round 6): the FULLY-unreadable --diff branch used to omit
  # `unreadable` from its return, so renderJson's diffUnreadable fell back to
  # 0 and this run printed `count 0 / examined 0 / excluded.unreadable 0`
  # right beside a reason naming two unreadable paths. The equation held only
  # because both sides collapsed to zero — exactly the residue-hiding shape
  # D4 forbids — and `--all`'s equivalent branch (TEST-025) was already
  # honest, so the two scopes disagreed. No arm covered this branch in either
  # direction; this is that pin.
  node_check "$json" '
    const c = d.requirement_corpus;
    const sum = Object.values(c.excluded).reduce((a,b)=>a+b, 0);
    c.count === 0 && c.excluded.unreadable === 2 && c.examined === 2 && c.examined === c.count + sum
  ' || { log_info "TEST-020(a): a fully-unreadable --diff corpus must COUNT its unreadable documents (count 0 / examined 2 / unreadable 2), never zero the bucket beside a reason that names them: $json"; ok=0; }

  # (b) ONE focus path is readable, the OTHER is stale: the corpus is NOT
  # empty (real requirement text still informs matching), but the skipped
  # path must be NAMED, and the readable document must still suppress the
  # symbol it names.
  local d2
  d2="$(new_fixture)" || return
  init_repo "$d2" || { log_fail "TEST-020(b) init_repo failed"; return; }
  cat > "$d2/docs/specs/SPEC-x.md" <<'EOF'
---
id: spec-x
type: spec
number: null
status: done
---
# Spec X

This change adds --named-flag to sample.mjs.
EOF
  cat > "$d2/docs/ai/STATE.yaml" <<'EOF'
current_focus:
  type: intake_change
  ref_id: x
  primary_path: docs/issues/CHANGE-does-not-exist.md
  spec_path: docs/specs/SPEC-x.md
EOF
  cat > "$d2/.aai/scripts/x.mjs" <<'EOF'
const USAGE = 'baseline';
EOF
  (cd "$d2" && git add -A && git commit -q -m 'one stale path, one readable path')
  cat >> "$d2/.aai/scripts/x.mjs" <<'EOF'
if (tok === '--named-flag') { /* handled */ }
if (tok === '--unnamed-flag') { /* handled */ }
EOF

  local out2 json2 code2
  out2="$(run_engine "$d2" --diff --json)"
  code2="$(engine_exit_code "$out2")"
  json2="$(engine_body "$out2")"
  [[ "$code2" == "0" ]] || { log_info "TEST-020(b): exit=$code2 (want 0)"; ok=0; }
  node_check "$json2" 'd.notes.some(n => n.includes("requirement document(s) unreadable, skipped") && n.includes("CHANGE-does-not-exist.md"))' \
    || { log_info "TEST-020(b): a partially-stale corpus must name the skipped document: $json2"; ok=0; }
  node_check "$json2" 'd.requirement_corpus.count === 1 && d.candidates.length === 1 && d.candidates[0].symbol === "--unnamed-flag"' \
    || { log_info "TEST-020(b): the readable document should still count toward the corpus and still suppress the symbol it names: $json2"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-020 a stale/unreadable STATE.yaml focus path is never silently dropped: a fully-stale corpus degrades to the named EMPTY-corpus note, a partially-stale corpus names the skipped path while the readable document still suppresses" \
    || log_fail "TEST-020 unreadable-corpus-document honesty"
}

# ---------------------------------------------------------------------------
# TEST-021 (Spec-AC-06) — PR #260 Codex finding (line 93): `--base --json`
# silently consumed `--json` as the ref, dropping the requested JSON mode
# and falling back to the working-tree diff at exit 0. A flag-shaped token
# must never be accepted as a --base value.
# ---------------------------------------------------------------------------
test_021_base_rejects_flag_shaped_value() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-021 init_repo failed"; return; }

  local out code body
  out="$(run_engine "$d" --diff --base --json)"
  code="$(engine_exit_code "$out")"
  body="$(engine_body "$out")"
  [[ "$code" == "2" ]] \
    || { log_info "TEST-021: --base --json exit=$code (want 2 — --json must not be silently consumed as the --base ref value)"; ok=0; }
  grep -qF -- "--diff" <<<"$body" || { log_info "TEST-021: usage text missing --diff: $body"; ok=0; }
  if grep -qE '^\{' <<<"$body"; then
    log_info "TEST-021: JSON output leaked even though the malformed invocation should be rejected: $body"
    ok=0
  fi

  local out2 code2
  out2="$(run_engine "$d" --diff --base --all)"
  code2="$(engine_exit_code "$out2")"
  [[ "$code2" == "2" ]] || { log_info "TEST-021: --base --all exit=$code2 (want 2)"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-021 a flag-shaped token following --base (--json, --all) is rejected as a usage error rather than silently consumed as the ref" \
    || log_fail "TEST-021 --base flag-shaped-value rejection"
}

# ---------------------------------------------------------------------------
# TEST-022 (Spec-AC-01, spec-deslop-corpus-honesty D1) — the widened corpus
# rule the code applies and the rule the header/json describe are the same
# rule: three directories (docs/specs, docs/issues, docs/rfc), a closed
# five-type set, directory-independent of type.
# ---------------------------------------------------------------------------
test_022_corpus_rule_and_header_agree() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-022 init_repo failed"; return; }
  mkdir -p "$d/docs/rfc" "$d/docs/product"

  cat > "$d/docs/specs/DOC-spec.md" <<'EOF'
---
id: doc-spec
type: spec
number: null
status: done
---
spec
EOF
  cat > "$d/docs/issues/DOC-change.md" <<'EOF'
---
id: doc-change
type: change
number: null
status: done
---
change
EOF
  cat > "$d/docs/issues/DOC-issue.md" <<'EOF'
---
id: doc-issue
type: issue
number: null
status: done
---
issue
EOF
  cat > "$d/docs/issues/DOC-techdebt.md" <<'EOF'
---
id: doc-techdebt
type: techdebt
number: null
status: done
---
techdebt
EOF
  cat > "$d/docs/rfc/DOC-rfc.md" <<'EOF'
---
id: doc-rfc
type: rfc
number: null
status: done
---
rfc
EOF
  cat > "$d/docs/product/DOC-outside.md" <<'EOF'
---
id: doc-outside
type: spec
number: null
status: done
---
outside the allowlist
EOF
  (cd "$d" && git add -A && git commit -q -m 'AC-01 fixture')

  local out code json
  out="$(run_engine "$d" --all --json)"
  code="$(engine_exit_code "$out")"
  json="$(engine_body "$out")"
  [[ "$code" == "0" ]] || { log_info "TEST-022: exit=$code (want 0)"; ok=0; }
  node_check "$json" 'd.requirement_corpus.count === 5' \
    || { log_info "TEST-022: expected 5 admitted documents: $json"; ok=0; }
  local expected='
    const want = ["docs/specs/DOC-spec.md","docs/issues/DOC-change.md","docs/issues/DOC-issue.md","docs/issues/DOC-techdebt.md","docs/rfc/DOC-rfc.md"];
    const got = [...d.requirement_corpus.documents].sort();
    JSON.stringify(got) === JSON.stringify([...want].sort())
  '
  node_check "$json" "$expected" \
    || { log_info "TEST-022: admitted document set mismatch: $json"; ok=0; }
  node_check "$json" '!d.requirement_corpus.documents.some(p => p.startsWith("docs/product"))' \
    || { log_info "TEST-022: a document outside the allowlisted directories leaked into the corpus: $json"; ok=0; }
  node_check "$json" 'JSON.stringify(d.requirement_corpus.dirs) === JSON.stringify(["docs/specs","docs/issues","docs/rfc"])' \
    || { log_info "TEST-022: requirement_corpus.dirs mismatch: $json"; ok=0; }
  node_check "$json" 'JSON.stringify(d.requirement_corpus.types) === JSON.stringify(["spec","change","issue","techdebt","rfc"])' \
    || { log_info "TEST-022: requirement_corpus.types mismatch: $json"; ok=0; }
  node_check "$json" 'JSON.stringify(d.requirement_corpus.statuses) === JSON.stringify(["accepted","implementing","done"])' \
    || { log_info "TEST-022: requirement_corpus.statuses mismatch: $json"; ok=0; }

  local outHuman bodyHuman
  outHuman="$(run_engine "$d" --all)"
  bodyHuman="$(engine_body "$outHuman")"
  # R-20 (delta review NB-3): these were two UNANCHORED `grep -qF` substring
  # probes, the same hole R-15 closed two arms away in TEST-026. A header that
  # named a SUPERSTRING of either list — an extra directory, an extra type —
  # still contained the wanted substring and passed, so the assertion could not
  # fail for the drift it exists to catch. Pinned as ONE whole-line match
  # against the exact header renderHuman emits: dirs, types and statuses all
  # live on that single line, so a whole-line pin covers all three claims and
  # no superstring of any of them can satisfy it.
  local wantCorpusHeader='  Requirement corpus: 5 documents (dirs: docs/specs, docs/issues, docs/rfc; types: spec, change, issue, techdebt, rfc; statuses: accepted/implementing/done)'
  grep -qxF "$wantCorpusHeader" <<<"$bodyHuman" \
    || { log_info "TEST-022: human header is not the exact corpus line naming the three directories, the five types and the three statuses (want: $wantCorpusHeader): $bodyHuman"; ok=0; }
  if grep -qF "type spec, status accepted/implementing/done" <<<"$bodyHuman"; then
    log_info "TEST-022: human header still claims the corpus is type spec only: $bodyHuman"
    ok=0
  fi

  # F-2 (PR #265 Codex P2, CHANGE-0150): Spec-AC-01 requires the header and the
  # json to state the SAME rule — in every reachable branch. The empty branch
  # printed the reason ALONE and dropped the dirs/types/statuses clause, so in
  # exactly the case where a reader most needs to know what the filter was, the
  # header did not say. Pinned as a whole line (-x), consistent with the arms
  # already anchored in this suite: a substring probe would survive re-dropping
  # the clause as long as the reason text stayed. The json side is pinned in the
  # same breath — it already carried dirs/types/statuses in the empty case, and
  # that must not silently become conditional either.
  local d2 outEmpty bodyEmpty jsonEmpty
  d2="$(new_fixture)" || return
  init_repo "$d2" || { log_fail "TEST-022 (empty-corpus header) init_repo failed"; return; }
  cat > "$d2/docs/specs/DOC-draft.md" <<'EOF'
---
id: doc-draft
type: spec
number: null
status: draft
---
the only corpus document, and the filter rejects it
EOF
  (cd "$d2" && git add -A && git commit -q -m 'AC-01 empty-corpus fixture')

  outEmpty="$(run_engine "$d2" --all)"
  bodyEmpty="$(engine_body "$outEmpty")"
  local wantEmptyHeader='  Requirement corpus: 0 documents (dirs: docs/specs, docs/issues, docs/rfc; types: spec, change, issue, techdebt, rfc; statuses: accepted/implementing/done) — EMPTY: no docs/specs, docs/issues or docs/rfc document with type in spec|change|issue|techdebt|rfc and status in accepted|implementing|done'
  grep -qxF "$wantEmptyHeader" <<<"$bodyEmpty" \
    || { log_info "TEST-022: the EMPTY-corpus human header does not state the selection rule (dirs, types, statuses) alongside the reason (want: $wantEmptyHeader): $bodyEmpty"; ok=0; }
  jsonEmpty="$(engine_body "$(run_engine "$d2" --all --json)")"
  node_check "$jsonEmpty" '
    const c = d.requirement_corpus;
    c.empty === true
      && JSON.stringify(c.dirs) === JSON.stringify(["docs/specs","docs/issues","docs/rfc"])
      && JSON.stringify(c.types) === JSON.stringify(["spec","change","issue","techdebt","rfc"])
      && JSON.stringify(c.statuses) === JSON.stringify(["accepted","implementing","done"])
  ' || { log_info "TEST-022: the EMPTY-corpus json payload does not state the selection rule: $jsonEmpty"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-022 the widened corpus rule the code applies and the rule the header/json state are the same rule, in the populated AND the empty branch" \
    || log_fail "TEST-022 corpus rule and header agreement"
}

# ---------------------------------------------------------------------------
# TEST-023 (Spec-AC-02) — a symbol named in a done change document is
# suppressed; the same symbol shape named only in a draft change document is
# still reported (proving the status filter is live, not assumed). Real-repo
# arm: the three real-tree symbols the intake named are gone from
# candidates, and each is genuinely named in a corpus document that is a
# corpus member ONLY under the new rule (docs/issues or docs/rfc).
# NB-1 (round-5 code review): the citation search used to accept ANY corpus
# document, and this ride's own spec (type: spec, status: implementing, under
# docs/specs) names all three symbols in its Summary and sorts first, so the
# loop matched it and the arm stayed green with D1 reverted — a tautology.
# Requiring the citing document to live outside docs/specs makes the arm bite:
# under the pre-D1 docs/specs-only corpus no such document can exist.
# ---------------------------------------------------------------------------
test_023_change_and_rfc_documents_suppress() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-023 init_repo failed"; return; }

  cat > "$d/.aai/scripts/x.mjs" <<'EOF'
if (tok === '--flag-done') { /* handled */ }
if (tok === '--flag-draft') { /* handled */ }
EOF
  cat > "$d/docs/issues/CHANGE-done.md" <<'EOF'
---
id: change-done
type: change
number: null
status: done
---
Mentions --flag-done.
EOF
  cat > "$d/docs/issues/CHANGE-draft.md" <<'EOF'
---
id: change-draft
type: change
number: null
status: draft
---
Mentions --flag-draft.
EOF
  (cd "$d" && git add -A && git commit -q -m 'AC-02 fixture')

  local out code json
  out="$(run_engine "$d" --all --json)"
  code="$(engine_exit_code "$out")"
  json="$(engine_body "$out")"
  [[ "$code" == "0" ]] || { log_info "TEST-023: exit=$code (want 0)"; ok=0; }
  node_check "$json" '!d.candidates.some(c => c.symbol === "--flag-done")' \
    || { log_info "TEST-023: --flag-done (named in a done change document) should be suppressed: $json"; ok=0; }
  node_check "$json" 'd.candidates.some(c => c.symbol === "--flag-draft")' \
    || { log_info "TEST-023: --flag-draft (named only in a draft change document) should still be reported: $json"; ok=0; }

  local realOut realCode realJson
  realOut="$(run_engine "$PROJECT_ROOT" --all --json)"
  realCode="$(engine_exit_code "$realOut")"
  realJson="$(engine_body "$realOut")"
  [[ "$realCode" == "0" ]] || { log_info "TEST-023: real-repo --all exit=$realCode (want 0)"; ok=0; }
  node_check "$realJson" '!d.candidates.some(c => ["--worktree-guard","--worktree-baseline","--pr-config"].includes(c.symbol))' \
    || { log_info "TEST-023: one of --worktree-guard/--worktree-baseline/--pr-config still reported on the real repo: $realJson"; ok=0; }

  # V-3 (validation round 6, non-blocking, tracked as
  # fu-deslop-ac02-single-citation): each of the three symbols has exactly ONE
  # citation outside docs/specs today (CHANGE-0125 twice, CHANGE-0096 once), so
  # a status flip, archive or move on either document turns this loop red for a
  # reason that has nothing to do with the corpus rule — and the arm's other
  # real-tree assertion above will NOT go red with it, because this ride's own
  # spec keeps the symbols suppressed from docs/specs. The loop still fails
  # closed (a real D1 revert must stay red), but it now names WHICH of the two
  # worlds it is in, so the red is diagnosable instead of misattributed.
  # The discriminator is the corpus RULE the payload publishes, NOT the mere
  # existence of a citing file: with D1 reverted, CHANGE-0125 still exists
  # under docs/issues and still names the symbol, so "a file names it but no
  # corpus member does" describes a real regression and a drifted citation
  # equally well. requirement_corpus.dirs separates them — the widening is
  # either still declared or it is not. Both branches were exercised in a
  # scratchpad copy (D1 reverted; and the three citing documents flipped to
  # draft) and each fails closed with the right message.
  local docsList sym found docpath drifted widened
  docsList="$(node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8")); console.log(d.requirement_corpus.documents.join("\n"));' <<<"$realJson")"
  if node_check "$realJson" 'd.requirement_corpus.dirs.includes("docs/issues") && d.requirement_corpus.dirs.includes("docs/rfc")'; then
    widened=1
  else
    widened=0
  fi
  for sym in --worktree-guard --worktree-baseline --pr-config; do
    found=0
    while IFS= read -r docpath; do
      [[ -z "$docpath" ]] && continue
      [[ "$docpath" == docs/specs/* ]] && continue
      grep -qF -- "$sym" "$PROJECT_ROOT/$docpath" 2>/dev/null && { found=1; break; }
    done <<<"$docsList"
    if [[ "$found" != "1" ]]; then
      drifted="$(cd "$PROJECT_ROOT" && grep -rlF -- "$sym" docs/issues docs/rfc 2>/dev/null | tr '\n' ' ')"
      if [[ "$widened" != "1" ]]; then
        log_info "TEST-023: $sym is not named in any corpus document outside docs/specs, and requirement_corpus.dirs no longer declares both docs/issues and docs/rfc — the corpus RULE itself regressed (D1). This is the failure this assertion exists to catch."
      elif [[ -n "$drifted" ]]; then
        log_info "TEST-023: $sym is named under docs/issues/docs/rfc (${drifted%% }) but by NO corpus member, while the corpus still declares both directories — the citation drifted out of the corpus (status flip, archive or move). This is citation drift, not a corpus-rule regression: re-point this arm at a live citation. Tracked as fu-deslop-ac02-single-citation."
      else
        log_info "TEST-023: $sym is not named in any corpus document outside docs/specs on the real repo, and no docs/issues or docs/rfc document names it at all — the widened corpus is what suppresses it, and only a docs/issues or docs/rfc citation proves that"
      fi
      ok=0
    fi
  done

  [[ $ok -eq 1 ]] && log_pass "TEST-023 a done change document suppresses the symbol it names, a draft one does not; the three real-tree symbols are gone and each is genuinely named in a corpus document outside docs/specs" \
    || log_fail "TEST-023 change/rfc document suppression"
}

# ---------------------------------------------------------------------------
# TEST-024 (Spec-AC-03, spec-deslop-corpus-honesty D2) — a document that
# records findings about this tool never suppresses the symbols it names.
# Real-repo arm: the corpus contains no docs/analysis path, the relocated
# adjudication document carries the coupling note and its rows,
# CHANGE-0145 carries a pointer instead of the table, and the prompt states
# the findings-outside-the-corpus convention.
# ---------------------------------------------------------------------------
test_024_findings_document_never_suppresses() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-024 init_repo failed"; return; }
  mkdir -p "$d/docs/analysis"

  cat > "$d/.aai/scripts/x.mjs" <<'EOF'
if (tok === '--findings-flag') { /* handled */ }
if (tok === '--corpus-flag') { /* handled */ }
EOF
  cat > "$d/docs/analysis/FINDINGS.md" <<'EOF'
---
id: findings-x
type: change
number: null
status: done
---
Mentions --findings-flag — a finding, not a request.
EOF
  cat > "$d/docs/specs/SPEC-corpus.md" <<'EOF'
---
id: spec-corpus
type: spec
number: null
status: done
---
Mentions --corpus-flag.
EOF
  (cd "$d" && git add -A && git commit -q -m 'AC-03 fixture')

  local out code json
  out="$(run_engine "$d" --all --json)"
  code="$(engine_exit_code "$out")"
  json="$(engine_body "$out")"
  [[ "$code" == "0" ]] || { log_info "TEST-024: exit=$code (want 0)"; ok=0; }
  node_check "$json" 'd.candidates.some(c => c.symbol === "--findings-flag")' \
    || { log_info "TEST-024: a symbol named only in a findings document outside the allowlist should still be a candidate: $json"; ok=0; }
  node_check "$json" '!d.candidates.some(c => c.symbol === "--corpus-flag")' \
    || { log_info "TEST-024: a symbol named in a corpus document should be suppressed: $json"; ok=0; }

  local realOut realJson
  realOut="$(run_engine "$PROJECT_ROOT" --all --json)"
  realJson="$(engine_body "$realOut")"
  node_check "$realJson" '!d.requirement_corpus.documents.some(p => p.startsWith("docs/analysis"))' \
    || { log_info "TEST-024: requirement_corpus.documents contains a path under docs/analysis: $realJson"; ok=0; }

  local adjFile="$PROJECT_ROOT/docs/analysis/deslop-candidate-adjudication-20260815.md"
  [[ -f "$adjFile" ]] || { log_info "TEST-024: $adjFile does not exist"; ok=0; }
  grep -qF "COUPLING (round-6 code review, NB-3)" "$adjFile" \
    || { log_info "TEST-024: relocated document missing the coupling note"; ok=0; }
  grep -qF "| 10 |" "$adjFile" \
    || { log_info "TEST-024: relocated document missing its tenth adjudication row"; ok=0; }

  local changeFile="$PROJECT_ROOT/docs/issues/CHANGE-0145-deslop-scope-and-unrequested-engine.md"
  if grep -qF "| # | symbol | site | why indefensible |" "$changeFile"; then
    log_info "TEST-024: CHANGE-0145 still carries the adjudication table (should carry a pointer instead)"
    ok=0
  fi
  grep -qF "docs/analysis/deslop-candidate-adjudication-20260815.md" "$changeFile" \
    || { log_info "TEST-024: CHANGE-0145 does not point at the relocated document"; ok=0; }

  grep -qi "docs/analysis" "$DESLOP_PROMPT" \
    || { log_info "TEST-024: deslop prompt does not state the findings-outside-the-corpus convention"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-024 a findings document never suppresses the symbols it names; the real adjudication table is relocated out of the corpus with a pointer left behind and the prompt states the convention" \
    || log_fail "TEST-024 findings-document non-suppression"
}

# ---------------------------------------------------------------------------
# TEST-025 (Spec-AC-04, spec-deslop-corpus-honesty D3) — an unreadable --all
# corpus document is named with the exact sentence the --diff path already
# emits; when every corpus document is unreadable, the EMPTY-corpus reason
# names the unreadable paths rather than claiming no document matched the
# filter. Both at exit 0.
# ---------------------------------------------------------------------------
test_025_unreadable_corpus_document_named() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-025 init_repo failed"; return; }

  cat > "$d/docs/specs/SPEC-good.md" <<'EOF'
---
id: spec-good
type: spec
number: null
status: done
---
Mentions --kept-flag.
EOF
  ln -s /nonexistent/path/SPEC-broken.md "$d/docs/specs/SPEC-broken.md"
  cat > "$d/.aai/scripts/x.mjs" <<'EOF'
if (tok === '--kept-flag') { /* handled */ }
if (tok === '--other-flag') { /* handled */ }
EOF
  (cd "$d" && git add -A && git commit -q -m 'AC-04 partial fixture')

  local out code json
  out="$(run_engine "$d" --all --json)"
  code="$(engine_exit_code "$out")"
  json="$(engine_body "$out")"
  [[ "$code" == "0" ]] || { log_info "TEST-025: partial-unreadable exit=$code (want 0)"; ok=0; }
  node_check "$json" 'd.notes.some(n => n.startsWith("NOTE: requirement document(s) unreadable, skipped (not searched):") && n.includes("docs/specs/SPEC-broken.md"))' \
    || { log_info "TEST-025: no unreadable-document note naming the symlink path: $json"; ok=0; }
  node_check "$json" '!d.candidates.some(c => c.symbol === "--kept-flag") && d.candidates.some(c => c.symbol === "--other-flag")' \
    || { log_info "TEST-025: the readable document should still suppress the symbol it names: $json"; ok=0; }

  local d2 out2 code2 json2
  d2="$(new_fixture)" || return
  init_repo "$d2" || { log_fail "TEST-025 (fully-unreadable) init_repo failed"; return; }
  ln -s /nonexistent/path/SPEC-broken.md "$d2/docs/specs/SPEC-broken.md"
  cat > "$d2/.aai/scripts/x.mjs" <<'EOF'
if (tok === '--only-flag') { /* handled */ }
EOF
  (cd "$d2" && git add -A && git commit -q -m 'AC-04 fully-unreadable fixture')

  out2="$(run_engine "$d2" --all --json)"
  code2="$(engine_exit_code "$out2")"
  json2="$(engine_body "$out2")"
  [[ "$code2" == "0" ]] || { log_info "TEST-025: fully-unreadable exit=$code2 (want 0)"; ok=0; }
  node_check "$json2" 'd.requirement_corpus.empty === true && d.requirement_corpus.empty_reason.includes("docs/specs/SPEC-broken.md")' \
    || { log_info "TEST-025: fully-unreadable corpus should degrade to empty, naming the unreadable path: $json2"; ok=0; }
  node_check "$json2" 'd.candidates.some(c => c.symbol === "--only-flag")' \
    || { log_info "TEST-025: a degraded-to-empty corpus should report every extracted symbol: $json2"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-025 an unreadable --all corpus document is named with the --diff path's own sentence; a fully-unreadable corpus degrades to the named EMPTY-corpus note, both at exit 0" \
    || log_fail "TEST-025 unreadable corpus document honesty"
}

# ---------------------------------------------------------------------------
# TEST-026 (Spec-AC-05, spec-deslop-corpus-honesty D4) — the document
# accounting balances: examined == count + sum(excluded), exhaustively
# bucketed, on a fixture forcing every bucket and on the real repository;
# the header prints examined plus every bucket; --diff emits the same
# excluded key set as --all AND balances the same way when STATE names an
# unreadable document.
# ---------------------------------------------------------------------------
test_026_document_accounting_balances() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-026 init_repo failed"; return; }
  mkdir -p "$d/docs/rfc"

  cat > "$d/docs/specs/SPEC-inc.md" <<'EOF'
---
id: spec-inc
type: spec
number: null
status: done
---
included
EOF
  cat > "$d/docs/specs/SPEC-draft.md" <<'EOF'
---
id: spec-draft
type: spec
number: null
status: draft
---
draft
EOF
  cat > "$d/docs/issues/CHANGE-proposed.md" <<'EOF'
---
id: change-proposed
type: change
number: null
status: proposed
---
proposed
EOF
  cat > "$d/docs/rfc/RFC-rejected.md" <<'EOF'
---
id: rfc-rejected
type: rfc
number: null
status: rejected
---
rejected
EOF
  cat > "$d/docs/issues/ISSUE-superseded.md" <<'EOF'
---
id: issue-superseded
type: issue
number: null
status: superseded
---
superseded
EOF
  cat > "$d/docs/specs/TECHDEBT-deferred.md" <<'EOF'
---
id: techdebt-deferred
type: techdebt
number: null
status: deferred
---
deferred
EOF
  cat > "$d/docs/specs/SPEC-other.md" <<'EOF'
---
id: spec-other
type: spec
number: null
status: current
---
other status
EOF
  cat > "$d/docs/specs/RESEARCH-x.md" <<'EOF'
---
id: research-x
type: research
number: null
status: done
---
not a requirement type
EOF
  cat > "$d/docs/specs/NOFM.md" <<'EOF'
# No frontmatter
plain body
EOF
  ln -s /nonexistent/BROKEN.md "$d/docs/specs/BROKEN.md"
  (cd "$d" && git add -A && git commit -q -m 'AC-05 exhaustive-bucket fixture')

  local out code json
  out="$(run_engine "$d" --all --json)"
  code="$(engine_exit_code "$out")"
  json="$(engine_body "$out")"
  [[ "$code" == "0" ]] || { log_info "TEST-026: exit=$code (want 0)"; ok=0; }
  local eq='
    const c = d.requirement_corpus;
    const sum = Object.values(c.excluded).reduce((a,b)=>a+b, 0);
    c.count === 1 && c.excluded.draft === 1 && c.excluded.proposed === 1 && c.excluded.rejected === 1 && c.excluded.superseded === 1 && c.excluded.deferred === 1 && c.excluded.other_status === 1 && c.excluded.not_requirement_type === 1 && c.excluded.unparseable_frontmatter === 1 && c.excluded.unreadable === 1 && c.examined === c.count + sum
  '
  node_check "$json" "$eq" \
    || { log_info "TEST-026: exhaustive-bucket equation or per-bucket count wrong: $json"; ok=0; }

  local outHuman bodyHuman
  outHuman="$(run_engine "$d" --all)"
  bodyHuman="$(engine_body "$outHuman")"
  # B-3 (validation round 7): this was `grep -qF "examined: 10"`, an UNANCHORED
  # substring match, and mutation proved it inert — printing
  # `examined: ${c.examined}${c.documents.length}` (header "examined: 101")
  # left all 28 arms green, because the right answer is a prefix of the wrong
  # one. Whole-line (-x) so a superstring cannot satisfy it. Eighth
  # "check that could not fail" on this ride, and it was living inside the
  # block added to fix the seventh.
  grep -qxF "    examined: 10" <<<"$bodyHuman" \
    || { log_info "TEST-026: human header does not print the examined count: $bodyHuman"; ok=0; }
  # R-20: the three bucket probes here were bare-name `grep -qF` substring
  # matches — they proved a bucket NAME appeared somewhere in the output and
  # nothing about its value or its line, so a superstring bucket line satisfied
  # them. Replaced with the whole-line pin already used by the empty-by-filter
  # arm below, which asserts every bucket name AND its measured value in order.
  grep -qxF "    excluded: 1 draft, 1 proposed, 1 rejected, 1 superseded, 1 deferred, 1 other_status, 1 not_requirement_type, 1 unparseable_frontmatter, 1 unreadable" <<<"$bodyHuman" \
    || { log_info "TEST-026: human header is not the exact bucket line (every bucket name with its measured value, one per bucket): $bodyHuman"; ok=0; }

  local realOut realJson
  realOut="$(run_engine "$PROJECT_ROOT" --all --json)"
  realJson="$(engine_body "$realOut")"
  node_check "$realJson" '
    const c = d.requirement_corpus;
    const sum = Object.values(c.excluded).reduce((a,b)=>a+b, 0);
    c.examined === c.count + sum
  ' || { log_info "TEST-026: real-repo accounting does not balance: $realJson"; ok=0; }

  # NB-2 (round-5 code review): the --diff arm used to check the excluded KEY
  # SET only, so it never noticed that the --diff payload broke D4's balance
  # rule — examined was synthesised as documents + unreadable while every
  # bucket, unreadable included, was hardcoded to 0 (count 1 / examined 2 /
  # sum 0). STATE now names one readable document and one dangling symlink, so
  # the diff corpus has a real unreadable path and the equation is asserted,
  # not just the shape.
  cat > "$d/docs/ai/STATE.yaml" <<'EOF'
current_focus:
  type: intake_change
  ref_id: accounting
  primary_path: docs/specs/BROKEN.md
  spec_path: docs/specs/SPEC-inc.md
EOF
  local diffOut diffJson
  diffOut="$(run_engine "$d" --diff --json)"
  diffJson="$(engine_body "$diffOut")"
  node_check "$diffJson" '
    const c = d.requirement_corpus;
    const sum = Object.values(c.excluded).reduce((a,b)=>a+b, 0);
    c.count === 1 && c.excluded.unreadable === 1 && c.examined === 2 && c.examined === c.count + sum
  ' || { log_info "TEST-026: --diff accounting does not balance (an unreadable STATE-named document must be counted, not zeroed): $diffJson"; ok=0; }
  local keyEq='
    const want = ["draft","proposed","rejected","superseded","deferred","other_status","not_requirement_type","unparseable_frontmatter","unreadable"];
    JSON.stringify(Object.keys(d.requirement_corpus.excluded).sort()) === JSON.stringify([...want].sort())
  '
  node_check "$json" "$keyEq" \
    || { log_info "TEST-026: --all excluded key set mismatch: $json"; ok=0; }
  node_check "$diffJson" "$keyEq" \
    || { log_info "TEST-026: --diff excluded key set mismatch: $diffJson"; ok=0; }

  # V-2 (validation round 6): the --all half of the accounting fix was pinned
  # by nothing. renderJson's excluded/examined selection once carried a
  # `&& !result.corpus.empty` guard; restoring it left all 28 arms green while
  # breaking D4's balance for an --all corpus that is empty BY FILTER — the
  # buckets fall back to the diff-shaped zero literal (sum 0) while `examined`
  # still reports the real walk (count 0 / examined 1 / sum 0). The fixture
  # above always admits one document so its --all corpus is never empty, and
  # TEST-025's fully-unreadable fixture survives that mutation by accident
  # (the fall-through reads corpus.unreadable, which resolveAllCorpus also
  # returns) and asserts no accounting at all. This is a corpus directory
  # holding exactly one DRAFT document plus one dangling symlink: empty by
  # filter AND carrying an unreadable member.
  #
  # B-4 (validation round 7), CORRECTED by R-19 (delta review NB-2,
  # re-measured 2026-08-19; see docs/ai/decisions.jsonl): the dangling symlink
  # is kept for COVERAGE, not because the fixture could not otherwise bite.
  # The original note claimed the draft-only fixture balanced under the
  # guard-restoration regression and that only the unreadable member made the
  # pin bite. That was wrong. Measured: with `&& !result.corpus.empty` restored
  # to renderJson's excludedBlock selection and NO symlink present, the
  # draft-only fixture already fails two clauses below — `excluded.draft`
  # reads 0 (the zero-literal fall-through) and the balance reads 1 vs 0.
  # What the symlink genuinely adds is the distinct shape "empty BY FILTER
  # *and* carrying an unreadable member", where the fall-through zeroes the
  # `unreadable` bucket while `examined` keeps counting the real walk
  # (examined 2 vs sum 1) — real coverage, just not the load-bearing reason
  # first recorded for it.
  local d3 out3 code3 json3
  d3="$(new_fixture)" || return
  init_repo "$d3" || { log_fail "TEST-026 (empty-by-filter) init_repo failed"; return; }
  cat > "$d3/docs/specs/SPEC-only-draft.md" <<'EOF'
---
id: spec-only-draft
type: spec
number: null
status: draft
---
Mentions --draft-only-flag, which must still be reported.
EOF
  cat > "$d3/.aai/scripts/x.mjs" <<'EOF'
if (tok === '--draft-only-flag') { /* handled */ }
EOF
  ln -s /nonexistent/BROKEN3.md "$d3/docs/specs/BROKEN3.md"
  (cd "$d3" && git add -A && git commit -q -m 'AC-05 empty-by-filter fixture')

  out3="$(run_engine "$d3" --all --json)"
  code3="$(engine_exit_code "$out3")"
  json3="$(engine_body "$out3")"
  [[ "$code3" == "0" ]] || { log_info "TEST-026: empty-by-filter exit=$code3 (want 0)"; ok=0; }
  node_check "$json3" '
    const c = d.requirement_corpus;
    const sum = Object.values(c.excluded).reduce((a,b)=>a+b, 0);
    c.count === 0 && c.empty === true && c.excluded.draft === 1 && c.excluded.unreadable === 1 && c.examined === 2 && c.examined === c.count + sum
  ' || { log_info "TEST-026: an --all corpus that is EMPTY BY FILTER and carries an unreadable member must still bucket and balance (count 0 / examined 2 / draft 1 / unreadable 1), never fall back to an excluded block that zeroes a bucket beside a non-zero examined: $json3"; ok=0; }
  node_check "$json3" "$keyEq" \
    || { log_info "TEST-026: empty-by-filter --all excluded key set mismatch: $json3"; ok=0; }
  local outHuman3 bodyHuman3
  outHuman3="$(run_engine "$d3" --all)"
  bodyHuman3="$(engine_body "$outHuman3")"
  # B-3: whole-line (-x), not substring — see the note on the main fixture's
  # examined assertion above. The old `grep -qF "examined: 1"` / `"1 draft"`
  # pair matched a header printing 10 and 10 as happily as 1 and 1.
  grep -qxF "    examined: 2" <<<"$bodyHuman3" \
    || { log_info "TEST-026: empty-by-filter human header does not print the examined count: $bodyHuman3"; ok=0; }
  grep -qxF "    excluded: 1 draft, 0 proposed, 0 rejected, 0 superseded, 0 deferred, 0 other_status, 0 not_requirement_type, 0 unparseable_frontmatter, 1 unreadable" <<<"$bodyHuman3" \
    || { log_info "TEST-026: empty-by-filter human header does not print the draft and unreadable buckets: $bodyHuman3"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-026 document accounting balances on a fixture covering every bucket, on the real repository, under --diff with an unreadable STATE-named document and under --all on a corpus empty by filter that also carries an unreadable member; the header prints every bucket on its own whole line; --diff carries the same excluded key set" \
    || log_fail "TEST-026 document accounting"
}

# ---------------------------------------------------------------------------
# TEST-028 (Spec-AC-07) — every shipped document that states the corpus rule
# states the new one: the deslop prompt, the product doc and the engine
# header carry no docs/specs-only or type:spec-only claim and each names the
# three directories; SPEC-0132 carries a dated Correction section plus
# superseded pointers with its historical measurements untouched; the
# released CHANGELOG v2026.08.16 section is byte-unchanged; docs-audit and
# spec-lint are both clean.
# ---------------------------------------------------------------------------
test_028_published_surfaces_state_the_new_rule() {
  local ok=1

  # V-5 (spec-deslop-corpus-honesty remediation, 2026-08-18): the previous
  # negative pattern "type spec only" never occurred verbatim even in the
  # PRE-change prompt (whose actual text was "`docs/specs/**` (`type:
  # spec`) only") — a negative assertion that never had anything to match
  # is not evidence. Uses the pre-change file's actual substring instead,
  # confirmed present in `main` and absent from the current prompt.
  if grep -qF '`type: spec`) only' "$DESLOP_PROMPT"; then
    log_info "TEST-028: deslop prompt still claims the corpus is type spec only"
    ok=0
  fi
  grep -qF "docs/specs/**" "$DESLOP_PROMPT" || { log_info "TEST-028: deslop prompt does not name docs/specs"; ok=0; }
  grep -qF "docs/issues/**" "$DESLOP_PROMPT" || { log_info "TEST-028: deslop prompt does not name docs/issues"; ok=0; }
  grep -qF "docs/rfc/**" "$DESLOP_PROMPT" || { log_info "TEST-028: deslop prompt does not name docs/rfc"; ok=0; }

  local productDoc="$PROJECT_ROOT/docs/product/aai-deslop.md"
  if grep -qF "docs/specs/**\` only" "$productDoc"; then
    log_info "TEST-028: product doc still claims the corpus is docs/specs only"
    ok=0
  fi
  grep -qF "docs/issues" "$productDoc" || { log_info "TEST-028: product doc does not name docs/issues"; ok=0; }
  grep -qF "docs/rfc" "$productDoc" || { log_info "TEST-028: product doc does not name docs/rfc"; ok=0; }

  if grep -qF "docs/specs/**/*.md whose frontmatter type is spec and status" "$ENGINE"; then
    log_info "TEST-028: engine header comment still states the old docs/specs-only rule"
    ok=0
  fi
  grep -qF "docs/specs, docs/issues" "$ENGINE" || { log_info "TEST-028: engine header comment does not name the widened directories"; ok=0; }

  local spec0132="$PROJECT_ROOT/docs/specs/SPEC-0132-spec-deslop-scope-and-unrequested-engine.md"
  grep -qF "## Correction" "$spec0132" || { log_info "TEST-028: SPEC-0132 has no dated Correction section"; ok=0; }
  local supersededCount
  supersededCount="$(grep -cF "SUPERSEDED 2026-08-18" "$spec0132" || true)"
  [[ "$supersededCount" -ge 4 ]] || { log_info "TEST-028: SPEC-0132 has $supersededCount SUPERSEDED pointers (want >= 4)"; ok=0; }
  grep -qF "131 of the" "$spec0132" || { log_info "TEST-028: SPEC-0132's historical 131-of-133 measurement was altered"; ok=0; }

  local realOut realCode
  realOut="$(run_engine "$PROJECT_ROOT" --all --json)"
  realCode="$(engine_exit_code "$realOut")"
  [[ "$realCode" == "0" ]] || { log_info "TEST-028: real-repo --all exit=$realCode (want 0)"; ok=0; }

  # V-4 (validation round 2): this used a bare `main` ref, which does not
  # resolve on a `pull_request` CI checkout, so the comparison threw and the
  # arm reported "the released section differs" when the section was in fact
  # byte-identical — failing safe but for a false reason. Base resolution now
  # goes through base_ref(), the node helper distinguishes "ref unreadable"
  # from "section differs" and the shell prints whichever actually happened.
  # FAILS CLOSED when no base resolves: this arm's whole job is to prove a
  # released section was not rewritten, and that claim is unverifiable
  # without the committed side — reporting PASS there would be the same
  # degrades-to-pass defect V-3 fixes one arm above, and both this suite's
  # CI lanes and every local checkout do have a base ref.
  local changelogBase changelogOut changelogRc
  changelogBase="$(base_ref)"
  if [[ -z "$changelogBase" ]]; then
    log_info "TEST-028: no base ref resolves (neither origin/main nor main) — cannot verify the released v2026.08.16 CHANGELOG section is byte-unchanged; FAILING CLOSED (this is a missing ref, NOT a detected difference)"
    ok=0
  else
    changelogOut="$(cd "$PROJECT_ROOT" && node -e '
      const fs = require("fs");
      const cp = require("child_process");
      const base = process.argv[1];
      let head;
      try {
        head = cp.execFileSync("git", ["show", base + ":CHANGELOG.md"], { encoding: "utf8" });
      } catch (e) {
        console.error("cannot read " + base + ":CHANGELOG.md (" + e.message.split("\n")[0] + ")");
        process.exit(2);
      }
      const work = fs.readFileSync("CHANGELOG.md", "utf8");
      function section(text) {
        const start = text.indexOf("## [v2026.08.16]");
        if (start === -1) return null;
        const rest = text.slice(start);
        const nextIdx = rest.indexOf("\n## [", 1);
        return nextIdx === -1 ? rest : rest.slice(0, nextIdx);
      }
      const a = section(head), b = section(work);
      if (a === null) { console.error("no v2026.08.16 section in " + base + ":CHANGELOG.md"); process.exit(1); }
      if (b === null) { console.error("no v2026.08.16 section in the working CHANGELOG.md"); process.exit(1); }
      if (a !== b) { console.error("the released v2026.08.16 section differs from " + base + " (must stay byte-identical): " + a.length + " vs " + b.length + " bytes"); process.exit(1); }
    ' "$changelogBase" 2>&1)"
    changelogRc=$?
    if [[ $changelogRc -ne 0 ]]; then
      log_info "TEST-028: released-CHANGELOG check failed (rc=$changelogRc): ${changelogOut:-no diagnostic}"
      ok=0
    fi
  fi

  if ! node "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" --check --strict --no-event >/dev/null 2>&1; then
    log_info "TEST-028: docs-audit.mjs --check --strict --no-event failed"
    ok=0
  fi
  if ! node "$PROJECT_ROOT/.aai/scripts/spec-lint.mjs" >/dev/null 2>&1; then
    log_info "TEST-028: spec-lint.mjs failed"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-028 the deslop prompt, product doc and engine header state the new corpus rule; SPEC-0132 carries a dated Correction plus superseded pointers with history unchanged; the released CHANGELOG section is byte-unchanged; docs-audit and spec-lint are clean" \
    || log_fail "TEST-028 published surfaces state the new rule"
}

# ---------------------------------------------------------------------------
# TEST-030 (Spec-AC-08) — all four deslop-corpus-honesty registry follow-ups
# are closed: none appears under --status open, and each appears done with
# resolved_by naming this scope under --status all.
# ---------------------------------------------------------------------------
test_030_registry_items_closed() {
  local ok=1
  local ids=(fu-deslop-all-corpus-specs-only fu-deslop-allcorpus-unreadable-silent fu-deslop-corpus-header-other-bucket fu-deslop-adjudication-self-suppression)

  # --ref-scoped (not the full ledger dump): the four items share ref_id
  # deslop-scope-and-unrequested-engine, and the full --status all dump is
  # large enough (~70KB) to hit an environment-specific command-substitution
  # truncation observed during this ride's own implementation; the --ref
  # filter keeps the captured JSON well under that ceiling.
  local openJson
  openJson="$(node "$PROJECT_ROOT/.aai/scripts/follow-ups.mjs" list --ref deslop-scope-and-unrequested-engine --status open --json 2>/dev/null)"
  local id
  for id in "${ids[@]}"; do
    node_check "$openJson" "!(d.items.some(x => x.id === \"$id\"))" \
      || { log_info "TEST-030: $id still appears under --status open"; ok=0; }
  done

  local allJson
  allJson="$(node "$PROJECT_ROOT/.aai/scripts/follow-ups.mjs" list --ref deslop-scope-and-unrequested-engine --status all --json 2>/dev/null)"
  for id in "${ids[@]}"; do
    node_check "$allJson" "d.items.some(x => x.id === \"$id\" && x.status === \"done\" && x.resolved_by === \"deslop-corpus-honesty\")" \
      || { log_info "TEST-030: $id is not status done with resolved_by deslop-corpus-honesty under --status all"; ok=0; }
  done

  [[ $ok -eq 1 ]] && log_pass "TEST-030 all four deslop-corpus-honesty registry follow-ups are closed" \
    || log_fail "TEST-030 registry items closed"
}

# ---------------------------------------------------------------------------
# TEST-031 (Spec-AC-04, F-1 / PR #265 Codex P2) — an unreadable corpus
# DIRECTORY is named, not swallowed. `walk()` used to wrap readdirSync in a
# bare `try { ... } catch { return out; }`, so an unreadable directory made
# every requirement inside it vanish while the accounting still BALANCED —
# those files were never counted as examined, so the residue was invisible by
# construction, and a symbol requested only in there was reported as
# unrequested. Report-only: exit stays 0 and no gate is added; the fix is that
# the failure is NAMED, in the notes, in the json and in the header, with the
# header saying in as many words that the directory is outside the balance.
# An ABSENT directory (ENOENT) is deliberately NOT named: it contributes a
# known zero, while an unreadable one contributes an unknown number.
# ---------------------------------------------------------------------------
test_031_unreadable_corpus_directory_named() {
  local d ok=1
  d="$(new_fixture)" || return
  init_repo "$d" || { log_fail "TEST-031 init_repo failed"; return; }
  mkdir -p "$d/docs/rfc/hidden"

  cat > "$d/docs/specs/SPEC-good.md" <<'EOF'
---
id: spec-good
type: spec
number: null
status: done
---
Mentions --kept-flag.
EOF
  cat > "$d/docs/rfc/hidden/RFC-unreachable.md" <<'EOF'
---
id: rfc-unreachable
type: rfc
number: null
status: accepted
---
Mentions --hidden-flag, which the walk will never reach.
EOF
  cat > "$d/.aai/scripts/x.mjs" <<'EOF'
if (tok === '--kept-flag') { /* handled */ }
if (tok === '--hidden-flag') { /* handled */ }
EOF
  (cd "$d" && git add -A && git commit -q -m 'F-1 unreadable-directory fixture')

  # PROBE 1 — the permission case named in the dispatch. chmod 000 does not
  # stop uid 0, and some CI images run as root, so the condition is PROBED
  # rather than assumed: when the directory is still readable the probe is
  # reported as inapplicable instead of asserting something the fixture failed
  # to create. Probe 2 below carries the same claim without any uid
  # dependency, so this arm never rests on a condition it could not establish.
  chmod 000 "$d/docs/rfc/hidden" 2>/dev/null
  if ls "$d/docs/rfc/hidden" >/dev/null 2>&1; then
    log_info "TEST-031: probe 1 inapplicable — chmod 000 did not make the directory unreadable for this uid (running as root?); the ELOOP probe below carries the claim"
  else
    local out code json
    out="$(run_engine "$d" --all --json)"
    code="$(engine_exit_code "$out")"
    json="$(engine_body "$out")"
    [[ "$code" == "0" ]] || { log_info "TEST-031: unreadable-directory exit=$code (want 0 — report-only, no gate)"; ok=0; }
    node_check "$json" 'd.notes.some(n => n.startsWith("NOTE: corpus directory unreadable, not walked") && n.includes("docs/rfc/hidden"))' \
      || { log_info "TEST-031: no note naming the unreadable corpus directory: $json"; ok=0; }
    node_check "$json" 'd.requirement_corpus.unreadable_dirs.length === 1 && d.requirement_corpus.unreadable_dirs[0].startsWith("docs/rfc/hidden ")' \
      || { log_info "TEST-031: requirement_corpus.unreadable_dirs does not name the directory: $json"; ok=0; }
  fi
  chmod 755 "$d/docs/rfc/hidden" 2>/dev/null

  # CONTROL — the same fixture with the directory readable again. The
  # `unreadable directories:` line is printed on EVERY --all run, so a reader
  # can tell "the walk was complete" apart from "this build never checked";
  # this pins the zero shape and proves the line tracks reality rather than
  # being a constant.
  local outCtl bodyCtl
  outCtl="$(run_engine "$d" --all)"
  bodyCtl="$(engine_body "$outCtl")"
  grep -qxF "    unreadable directories: 0" <<<"$bodyCtl" \
    || { log_info "TEST-031: a complete walk must still print the unreadable-directories line as 0: $bodyCtl"; ok=0; }
  node_check "$(engine_body "$(run_engine "$d" --all --json)")" \
    'd.requirement_corpus.unreadable_dirs.length === 0 && !d.notes.some(n => n.startsWith("NOTE: corpus directory unreadable"))' \
    || { log_info "TEST-031: a complete walk must report no unreadable directory"; ok=0; }

  # PROBE 2 — a directory-level symlink loop on the corpus directory ITSELF
  # (`docs/rfc` -> `docs/rfc`). readdirSync fails with ELOOP for every uid,
  # root included, so this probe is deterministic on every platform and is the
  # one that actually carries the arm. `docs/rfc` is one of the two directories
  # this ride newly admitted into the corpus, which is where the widened
  # exposure lives.
  local d2 out2 code2 json2 body2
  d2="$(new_fixture)" || return
  init_repo "$d2" || { log_fail "TEST-031 (ELOOP) init_repo failed"; return; }
  cat > "$d2/docs/specs/SPEC-good.md" <<'EOF'
---
id: spec-good
type: spec
number: null
status: done
---
Mentions --kept-flag.
EOF
  cat > "$d2/.aai/scripts/x.mjs" <<'EOF'
if (tok === '--kept-flag') { /* handled */ }
if (tok === '--other-flag') { /* handled */ }
EOF
  ln -s rfc "$d2/docs/rfc"
  (cd "$d2" && git add -A && git commit -q -m 'F-1 ELOOP fixture')

  out2="$(run_engine "$d2" --all --json)"
  code2="$(engine_exit_code "$out2")"
  json2="$(engine_body "$out2")"
  [[ "$code2" == "0" ]] || { log_info "TEST-031: ELOOP exit=$code2 (want 0 — report-only, no gate)"; ok=0; }
  node_check "$json2" 'd.notes.some(n => n.startsWith("NOTE: corpus directory unreadable, not walked") && n.includes("docs/rfc"))' \
    || { log_info "TEST-031: an unwalkable corpus directory must be named in notes: $json2"; ok=0; }
  node_check "$json2" 'd.requirement_corpus.unreadable_dirs.length === 1 && d.requirement_corpus.unreadable_dirs[0].startsWith("docs/rfc ")' \
    || { log_info "TEST-031: requirement_corpus.unreadable_dirs must name the unwalkable directory: $json2"; ok=0; }
  # The per-document accounting is UNCHANGED and still balances: an unreadable
  # directory hides an unknown number of documents, so folding it into a bucket
  # would have to invent a count. Pinned so the deliberate choice cannot be
  # quietly reversed into a fabricated figure.
  node_check "$json2" '
    const c = d.requirement_corpus;
    const sum = Object.values(c.excluded).reduce((a,b)=>a+b, 0);
    c.count === 1 && c.examined === 1 && c.examined === c.count + sum
  ' || { log_info "TEST-031: the per-document accounting must still balance over what the walk COULD see, with the directory outside it: $json2"; ok=0; }
  # The readable half of the corpus still works — the failure is named, not
  # escalated into an aborted scan.
  node_check "$json2" '!d.candidates.some(c => c.symbol === "--kept-flag") && d.candidates.some(c => c.symbol === "--other-flag")' \
    || { log_info "TEST-031: a readable corpus document must still suppress the symbol it names: $json2"; ok=0; }

  body2="$(engine_body "$(run_engine "$d2" --all)")"
  # Whole-line (-x), consistent with the anchored arms in TEST-022 and
  # TEST-026: an unanchored substring probe would survive dropping the
  # "NOT counted in examined" clause, which is the honest half of the line.
  # -E only so the errno spelling is not pinned (POSIX says ELOOP, but the
  # assertion is about the line's shape, not the platform's errno name); the
  # -x anchor still means no superstring can satisfy it.
  grep -qxE '    unreadable directories: 1 \(docs/rfc \([A-Z]+\)\) — NOT counted in examined or any excluded bucket above' <<<"$body2" \
    || { log_info "TEST-031: the human header does not name the unreadable directory AND state that it is outside the accounting: $body2"; ok=0; }

  # PROBE 3 — every readable corpus document gone AND a corpus directory
  # unwalkable: the EMPTY-corpus reason must name the directory rather than
  # claiming no document matched the type/status filter, which would be false.
  # Same rule D3 already applies to an unreadable DOCUMENT, one level up.
  local d3 json3
  d3="$(new_fixture)" || return
  init_repo "$d3" || { log_fail "TEST-031 (empty + ELOOP) init_repo failed"; return; }
  echo "if (tok === '--only-flag') { /* handled */ }" > "$d3/.aai/scripts/x.mjs"
  ln -s rfc "$d3/docs/rfc"
  (cd "$d3" && git add -A && git commit -q -m 'F-1 empty + ELOOP fixture')

  json3="$(engine_body "$(run_engine "$d3" --all --json)")"
  node_check "$json3" 'd.requirement_corpus.empty === true && d.requirement_corpus.empty_reason.includes("corpus directory unreadable, not walked: docs/rfc (")' \
    || { log_info "TEST-031: an empty corpus whose cause is an unwalkable directory must say so in empty_reason, not claim the filter matched nothing: $json3"; ok=0; }
  node_check "$json3" 'd.candidates.some(c => c.symbol === "--only-flag")' \
    || { log_info "TEST-031: a degraded-to-empty corpus should still report every extracted symbol: $json3"; ok=0; }

  # ABSENT is not UNREADABLE: d3 has no docs/issues directory at all and it is
  # never named — a known zero must not be dressed up as a gap, or the note
  # fires on every project that simply has no docs/rfc.
  node_check "$json3" '!d.requirement_corpus.unreadable_dirs.some(x => x.startsWith("docs/issues"))' \
    || { log_info "TEST-031: an ABSENT corpus directory (ENOENT) must not be reported as unreadable: $json3"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-031 an unreadable corpus directory is named in notes, in requirement_corpus.unreadable_dirs and in the header as outside the accounting; the readable half still suppresses; an empty corpus caused by one says so; an absent directory is not reported; every run exits 0" \
    || log_fail "TEST-031 unreadable corpus directory honesty"
}


main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps

  # V-7: the Test Plan documents per-arm commands
  # (`bash tests/skills/test-aai-deslop.sh <fn>`) but "$@" used to be
  # discarded, so each of those commands silently ran the WHOLE suite. Named
  # arms now run alone; an unknown name is a usage error (exit 2) rather than
  # a silent full run. No arguments = the full dispatch list, unchanged.
  if [[ $# -gt 0 ]]; then
    local fn
    for fn in "$@"; do
      [[ "$fn" == test_* && "$(type -t "$fn" 2>/dev/null || true)" == "function" ]] \
        || { echo "unknown test arm: $fn" >&2; exit 2; }
      "$fn"
    done
  else
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
    test_018_range_diff_failure_surfaced
    test_019_full_file_deletion_not_empty_diff
    test_020_unreadable_state_corpus_document_named
    test_021_base_rejects_flag_shaped_value
    test_022_corpus_rule_and_header_agree
    test_023_change_and_rfc_documents_suppress
    test_024_findings_document_never_suppresses
    test_025_unreadable_corpus_document_named
    test_026_document_accounting_balances
    test_028_published_surfaces_state_the_new_rule
    test_030_registry_items_closed
    test_031_unreadable_corpus_directory_named
  fi

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
