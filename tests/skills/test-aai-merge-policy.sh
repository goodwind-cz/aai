#!/usr/bin/env bash
#
# Test: configurable merge-policy lanes evaluator
# (SPEC-DRAFT spec-configurable-merge-policy-lanes).
#
# Verifies .aai/scripts/merge-policy.mjs — the deterministic evaluator for a
# project-owned, owner-signed merge policy (docs/ai/merge-policy.yaml).
#
# BATCH 1 of this TDD ride covered:
#   TEST-1501 (Spec-AC-01) — no_policy verdict, --check and --validate
#   TEST-1503..1505 (Spec-AC-03) — reads come from the BASE commit only
#   TEST-1506..1507 (Spec-AC-04) — GUARD_PATHS beats everything else
# BATCH 2 added:
#   TEST-1508 (Spec-AC-05) — classifyFiles order: guard, architecture, kind
#   TEST-1509 (Spec-AC-06) — globToRegExp semantics through --classify
#   TEST-1510 (Spec-AC-07) — requesterApproved (latest deciding review, at head)
# BATCH 3 added:
#   TEST-1511 (Spec-AC-08) — ciGreen: CheckRun/StatusContext per-entry rules
#   TEST-1512 (Spec-AC-09) — lane-gate.mjs --sweep-check spawn; CI/sweep never
#                            configurable via a `requires` key
#   TEST-1514, 1515 (Spec-AC-11) — ceremony_exceeds, DEFAULT_MAX_CEREMONY,
#                            and agreement with lane-gate.mjs's own reader
# BATCH 4 adds:
#   TEST-1513 (Spec-AC-10) — public_effect_not_opted_in opt-in rule
#   TEST-1516..1518 (Spec-AC-12) — deploy consistency (reaches_inconsistent),
#                            decision-binding codes, and the structural
#                            validate codes (duplicate_lane, undefined_kind,
#                            requester_missing)
#   TEST-1519 (Spec-AC-13) — MARKER_RE-backed bad_marker/duplicate_marker
# Every other TEST-15xx row in the spec's Test Plan lands in a later batch.
# From this batch on, any fixture that reaches the per-lane evaluation loop
# (an "allowed" or a lane-level deny reason) needs write_sweep_record too —
# the sweep check is no longer a permissive stub.
#
# All fixtures are scratch git repositories that set their own user.email/
# user.name. `gh` is a stub on PATH that serves JSON from a fixture file and
# appends its argv to a log — no network call anywhere in this suite.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -uo pipefail

TEST_NAME="aai-merge-policy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/assert-payload.sh
. "$SCRIPT_DIR/lib/assert-payload.sh"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

MP="${MERGE_POLICY_SCRIPT:-$PROJECT_ROOT/.aai/scripts/merge-policy.mjs}"

FAILED=0
FIXTURES=()

cleanup() {
  local d
  for d in "${FIXTURES[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
  done
}
trap cleanup EXIT

log_pass() { echo "PASS $*"; }
log_fail() { echo "FAIL $*" >&2; FAILED=1; }
log_skip() { echo "SKIP $*"; exit 42; }
log_info() { echo "  $*"; }

check_deps() {
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -d .aai ]] || log_skip ".aai directory not found"
}

mk() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/aai-merge-policy.XXXXXX")"
  FIXTURES+=("$d")
  TEST_DIR="$d"
}

# new_repo <dir> — an empty git repo on branch main, with its own identity.
new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  (
    cd "$dir" \
      && git init -q \
      && git checkout -q -b main 2>/dev/null \
      && git config user.email "merge-policy-test@example.com" \
      && git config user.name "AAI Merge Policy Test"
  ) >/dev/null 2>&1
}

commit_all() {
  local dir="$1" msg="$2"
  (cd "$dir" && git add -A && git commit -q -m "$msg") >/dev/null 2>&1
}

head_sha() { (cd "$1" && git rev-parse HEAD); }

# build_gh_stub <bin_dir> <json_file> <log_file> — on `gh pr view <n> --json
# ...` cats <json_file> and logs the argv; anything else exits 1 (this
# evaluator's --check must only ever call `pr view`, Spec-AC-16).
build_gh_stub() {
  local bin_dir="$1" json_file="$2" log_file="$3"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/gh" <<STUBEOF
#!/usr/bin/env bash
{
  printf 'ARGS:'
  for a in "\$@"; do printf ' %s' "\$a"; done
  printf '\n'
} >> "$log_file"
if [[ "\${1:-}" == "pr" && "\${2:-}" == "view" ]]; then
  cat "$json_file"
  exit 0
fi
exit 1
STUBEOF
  chmod +x "$bin_dir/gh"
}

# run_check <repo> <ghbin> <pr> [extra_arg...] — prints stdout+stderr, sets
# $RC. Any extra args (e.g. --spec <path> --debug-inputs) are appended
# verbatim after --repo-root.
run_check() {
  local repo="$1" ghbin="$2" pr="$3"
  shift 3
  OUT="$(PATH="$ghbin:$PATH" node "$MP" --check --pr "$pr" --repo-root "$repo" "$@" 2>&1)" && RC=0 || RC=$?
}

# write_sweep_record <repo> <pr> — an EVENTS.jsonl pr_sweep record this
# evaluator's own runSweepCheck spawn (lane-gate.mjs --sweep-check) accepts
# (Spec-AC-09). Every fixture repo in this suite has no origin remote and no
# STATE carrying a fast-lane strategy, so lane-gate.mjs always computes
# lane=heavy for it regardless of which --spec this test may also pass
# through -- `internal_substituted` is the one outcome legal on that lane
# without also claiming a reviewer-bot sweep actually ran. Written directly
# to the working tree, never committed: a committed copy would enter the
# PR's own file diff and trip GUARD_PATHS/classification.
write_sweep_record() {
  local repo="$1" pr="$2"
  mkdir -p "$repo/docs/ai"
  printf '{"event":"pr_sweep","payload":{"pr":%s,"lane":"heavy","outcome":"internal_substituted","threads_seen":0,"threads_unresolved":0,"reviewer_bots":"none"}}\n' \
    "$pr" >> "$repo/docs/ai/EVENTS.jsonl"
}

# --- TEST-1501 (Spec-AC-01) --------------------------------------------------
test_1501_no_policy() {
  log_info "TEST-1501: base carries no merge-policy.yaml -> --check prints no_policy, exits 4; --validate on an absent path exits 4"
  mk
  local repo="$TEST_DIR/repo"
  new_repo "$repo"
  echo "hello" > "$repo/readme.md"
  commit_all "$repo" "base"
  local base; base="$(head_sha "$repo")"

  local ghbin="$TEST_DIR/gh-bin" json="$TEST_DIR/pr.json" log="$TEST_DIR/gh.log"
  cat > "$json" <<JSON
{"number":1,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$base","reviews":[],"statusCheckRollup":[],"body":""}
JSON
  build_gh_stub "$ghbin" "$json" "$log"

  run_check "$repo" "$ghbin" 1
  assert_payload_has_line "$OUT" "MERGE-POLICY no_policy pr=1" "TEST-1501: expected the no_policy line, got: $OUT"
  [[ "$RC" -eq 4 ]] || log_fail "TEST-1501: --check on an absent base policy must exit 4, got $RC: $OUT"

  local vout vrc
  vout="$(node "$MP" --validate --path "$repo/docs/ai/merge-policy.yaml" --repo-root "$repo" 2>&1)" && vrc=0 || vrc=$?
  [[ "$vrc" -eq 4 ]] || log_fail "TEST-1501: --validate on an absent path must exit 4, got $vrc: $vout"

  log_pass "TEST-1501: no_policy verdict for both --check and --validate"
}

# --- TEST-1503 (Spec-AC-03) --------------------------------------------------
test_1503_base_absent_head_permissive() {
  log_info "TEST-1503: base has no policy; head commit AND the working tree carry an allow-all policy -> still no_policy (base-only read)"
  mk
  local repo="$TEST_DIR/repo"
  new_repo "$repo"

  # A realistic "base moved forward independently" shape: the common
  # ancestor (what becomes HEAD, below) carries an allow-all policy; base's
  # own branch tip then DELETES it in a later commit. `git diff --no-renames
  # <base>...<head>` (P3's mandated triple-dot form) diffs from
  # merge-base(base,head) — which IS head here — to head itself, i.e. EMPTY,
  # so classification never even sees the policy path. This is what proves
  # --check reads docs/ai/merge-policy.yaml via `git show <baseRefOid>:...`
  # and nothing else: the policy is genuinely absent AT THE BASE COMMIT, and
  # is never derived from the (empty, in this shape) PR diff.
  mkdir -p "$repo/docs/ai"
  cat > "$repo/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
kinds:
  - id: repo
    globs: ["**"]
lanes:
  - id: allow-all
    decision_ref: allowallref@2026-01-01T00:00:00Z
    decision_match: "x"
    signed_by: someone
    kinds: [repo]
    merge_reaches: nothing
    marker: AAI_ALLOWALL_MERGE
YAML
  commit_all "$repo" "common ancestor: an allow-all policy exists here (this becomes HEAD)"
  local head; head="$(head_sha "$repo")"

  rm -f "$repo/docs/ai/merge-policy.yaml"
  commit_all "$repo" "base: the policy is deleted on this branch tip (this becomes BASE)"
  local base; base="$(head_sha "$repo")"

  # The working tree ALSO carries the permissive policy (uncommitted, dirty)
  # -- --check must ignore this too.
  cat > "$repo/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
kinds:
  - id: repo
    globs: ["**"]
lanes:
  - id: allow-all
    decision_ref: allowallref@2026-01-01T00:00:00Z
    decision_match: "x"
    signed_by: someone
    kinds: [repo]
    merge_reaches: nothing
    marker: AAI_ALLOWALL_MERGE
YAML

  local ghbin="$TEST_DIR/gh-bin" json="$TEST_DIR/pr.json" log="$TEST_DIR/gh.log"
  cat > "$json" <<JSON
{"number":2,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[],"body":""}
JSON
  build_gh_stub "$ghbin" "$json" "$log"

  run_check "$repo" "$ghbin" 2
  assert_payload_has_line "$OUT" "MERGE-POLICY no_policy pr=2" "TEST-1503: expected no_policy reading the BASE commit, got: $OUT"
  [[ "$RC" -eq 4 ]] || log_fail "TEST-1503: expected exit 4, got $RC: $OUT"

  log_pass "TEST-1503: --check reads the policy from the base commit only, never the head commit or the working tree"
}

# --- TEST-1504 (Spec-AC-03) --------------------------------------------------
test_1504_base_restrictive_head_widens() {
  log_info "TEST-1504: restrictive base policy denies even though the head/working-tree copy widens the lane (no_lane_matched)"
  mk
  local repo="$TEST_DIR/repo"
  new_repo "$repo"
  mkdir -p "$repo/docs/ai"
  cat > "$repo/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
  - id: other
    globs: ["other/**"]
lanes:
  - id: lane-other
    decision_ref: test1504-ride@2026-10-01T10:00:00Z
    decision_match: "MERGE LANE test1504"
    signed_by: owner-login
    kinds: [other]
    merge_reaches: nothing
    marker: AAI_OTHER_MERGE
    max_ceremony: 3
YAML
  cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1504-ride","ts":"2026-10-01T10:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1504 approved"}
JSONL
  commit_all "$repo" "base: restrictive policy (lane-other does not cover docs)"
  local base; base="$(head_sha "$repo")"

  mkdir -p "$repo/docs"
  echo "a docs change" > "$repo/docs/changed.md"
  commit_all "$repo" "head: an unrelated docs change (policy file untouched)"
  local head; head="$(head_sha "$repo")"

  # A FURTHER, committed change to the repo's actual checked-out ref (NOT
  # named by headRefOid below) that widens lane-other to cover "docs" too --
  # this is what the files on disk ("the working tree") now carry. --check
  # must read docs/ai/merge-policy.yaml via `git show <baseRefOid>:...`
  # using the BASE sha specifically, never the repo's current checkout --
  # proving the mutation that replaces that sha with the literal `HEAD`
  # reddens this test (TEST-1504's own mutation cell).
  cat > "$repo/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
  - id: other
    globs: ["other/**"]
lanes:
  - id: lane-other
    decision_ref: test1504-ride@2026-10-01T10:00:00Z
    decision_match: "MERGE LANE test1504"
    signed_by: owner-login
    kinds: [other, docs]
    merge_reaches: nothing
    marker: AAI_OTHER_MERGE
    max_ceremony: 3
YAML
  commit_all "$repo" "the repo's current checkout (not the PR's headRefOid) widens the lane"
  write_sweep_record "$repo" 3

  local ghbin="$TEST_DIR/gh-bin" json="$TEST_DIR/pr.json" log="$TEST_DIR/gh.log"
  cat > "$json" <<JSON
{"number":3,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"state":"SUCCESS"}],"body":""}
JSON
  build_gh_stub "$ghbin" "$json" "$log"

  run_check "$repo" "$ghbin" 3
  assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=3 reason=no_lane_matched" \
    "TEST-1504: expected no_lane_matched from the BASE (restrictive) policy, got: $OUT"
  [[ "$RC" -eq 3 ]] || log_fail "TEST-1504: expected exit 3, got $RC: $OUT"

  log_pass "TEST-1504: the widened head/working-tree copy never overrides the restrictive base lane"
}

# --- TEST-1505 (Spec-AC-03) --------------------------------------------------
test_1505_decision_only_in_head() {
  log_info "TEST-1505: a decision record appended only in HEAD -> denied reason=policy_invalid naming decision_missing (base-only read)"
  mk
  local repo="$TEST_DIR/repo"
  new_repo "$repo"
  mkdir -p "$repo/docs/ai"
  cat > "$repo/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-docs
    decision_ref: test1505-ride@2026-10-02T10:00:00Z
    decision_match: "MERGE LANE test1505"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_DOCS_MERGE
YAML
  : > "$repo/docs/ai/decisions.jsonl"
  commit_all "$repo" "base: policy present, decisions.jsonl has no matching record yet"
  local base; base="$(head_sha "$repo")"

  cat >> "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1505-ride","ts":"2026-10-02T10:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1505 approved"}
JSONL
  mkdir -p "$repo/docs"
  echo "doc" > "$repo/docs/x.md"
  commit_all "$repo" "head: appends the owner decision (base must not see it)"
  local head; head="$(head_sha "$repo")"

  local ghbin="$TEST_DIR/gh-bin" json="$TEST_DIR/pr.json" log="$TEST_DIR/gh.log"
  cat > "$json" <<JSON
{"number":4,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[],"body":""}
JSON
  build_gh_stub "$ghbin" "$json" "$log"

  run_check "$repo" "$ghbin" 4
  assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=4 reason=policy_invalid" "TEST-1505: expected policy_invalid, got: $OUT"
  assert_payload_contains "$OUT" "decision_missing" "TEST-1505: expected stdout to name decision_missing, got: $OUT"
  [[ "$RC" -eq 3 ]] || log_fail "TEST-1505: expected exit 3, got $RC: $OUT"

  log_pass "TEST-1505: the decision binder reads decisions.jsonl from the base commit only"
}

# --- TEST-1506 (Spec-AC-04) --------------------------------------------------
test_1506_guard_paths_denied() {
  log_info "TEST-1506: a PR diff that adds, modifies or deletes docs/ai/merge-policy.yaml, or touches .aai/scripts/merge-policy.mjs, is always denied policy_touched"
  local case_name target
  for case_name in add modify delete script; do
    mk
    local repo="$TEST_DIR/repo"
    new_repo "$repo"
    mkdir -p "$repo/docs/ai"
    echo "base file" > "$repo/readme.md"

    case "$case_name" in
      add) target="docs/ai/merge-policy.yaml" ;; # base has none at all yet
      modify|delete)
        printf 'version: 1\nkinds: []\nlanes: []\n' > "$repo/docs/ai/merge-policy.yaml"
        target="docs/ai/merge-policy.yaml"
        ;;
      script)
        mkdir -p "$repo/.aai/scripts"
        echo "// placeholder" > "$repo/.aai/scripts/merge-policy.mjs"
        target=".aai/scripts/merge-policy.mjs"
        ;;
    esac
    commit_all "$repo" "base ($case_name)"
    local base; base="$(head_sha "$repo")"

    case "$case_name" in
      add) printf 'version: 1\nkinds: []\nlanes: []\n' > "$repo/docs/ai/merge-policy.yaml" ;;
      modify) printf 'version: 1\nkinds: []\nlanes: []\n# modified\n' > "$repo/docs/ai/merge-policy.yaml" ;;
      delete) rm -f "$repo/docs/ai/merge-policy.yaml" ;;
      script) echo "// changed" > "$repo/.aai/scripts/merge-policy.mjs" ;;
    esac
    commit_all "$repo" "head: touch $target ($case_name)"
    local head; head="$(head_sha "$repo")"

    local ghbin="$TEST_DIR/gh-bin-$case_name" json="$TEST_DIR/pr-$case_name.json" log="$TEST_DIR/gh-$case_name.log"
    cat > "$json" <<JSON
{"number":5,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"state":"SUCCESS"}],"body":""}
JSON
    build_gh_stub "$ghbin" "$json" "$log"

    run_check "$repo" "$ghbin" 5
    assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=5 reason=policy_touched path=$target" \
      "TEST-1506 [$case_name]: expected policy_touched naming $target, got: $OUT"
    [[ "$RC" -eq 3 ]] || log_fail "TEST-1506 [$case_name]: expected exit 3, got $RC: $OUT"
  done

  log_pass "TEST-1506: GUARD_PATHS additions/modifications/deletions deny policy_touched, whatever else is true"
}

# --- TEST-1507 (Spec-AC-04) --------------------------------------------------
test_1507_guard_paths_superset_of_import_closure() {
  log_info "TEST-1507: GUARD_PATHS is a superset of the real import closure of merge-policy.mjs + lane-gate.mjs, plus claude-hook-gate.sh and the policy path"
  mk
  local probe="$TEST_DIR/closure-probe.mjs"
  cat > "$probe" <<'NODE'
import { readFileSync } from 'node:fs';
import { dirname, resolve, relative } from 'node:path';
import { pathToFileURL } from 'node:url';

const mpPath = process.argv[2];
const ROOT = process.argv[3];
const { GUARD_PATHS, POLICY_PATH } = await import(pathToFileURL(mpPath).href);

function importClosure(entry) {
  const seen = new Set();
  const stack = [entry];
  while (stack.length) {
    const f = stack.pop();
    const rel = relative(ROOT, f).split('\\').join('/');
    if (seen.has(rel)) continue;
    seen.add(rel);
    let text;
    try { text = readFileSync(f, 'utf8'); } catch { continue; }
    // Only real `import ... from '...'` statements -- a doc-comment example
    // (cli-pipe-guard.mjs's own header shows "import ... from
    // './lib/cli-pipe-guard.mjs'" as USAGE prose) must never be mistaken for
    // a live import, or the closure resolves a bogus doubled path.
    for (const line of text.split('\n')) {
      const t = line.trim();
      if (!t.startsWith('import ')) continue;
      const m = /from\s+['"](\.[^'"]+)['"]/.exec(t);
      if (!m || !m[1].endsWith('.mjs')) continue;
      stack.push(resolve(dirname(f), m[1]));
    }
  }
  seen.delete(relative(ROOT, entry).split('\\').join('/'));
  return seen;
}

const closure = new Set([
  ...importClosure(resolve(ROOT, '.aai/scripts/merge-policy.mjs')),
  ...importClosure(resolve(ROOT, '.aai/scripts/lane-gate.mjs')),
]);
closure.add('.aai/scripts/lane-gate.mjs');
closure.add('.aai/scripts/merge-policy.mjs');
closure.add('.aai/scripts/claude-hook-gate.sh');
closure.add(POLICY_PATH);

const guardSet = new Set(GUARD_PATHS);
const missing = [...closure].filter((p) => !guardSet.has(p));
if (missing.length) {
  console.log('MISSING ' + missing.join(','));
  process.exit(1);
}
console.log('OK');
process.exit(0);
NODE

  local out rc
  out="$(node "$probe" "$MP" "$PROJECT_ROOT" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 && "$out" == "OK" ]] || log_fail "TEST-1507: GUARD_PATHS is missing import-closure entries: $out (rc=$rc)"

  log_pass "TEST-1507: GUARD_PATHS covers the evaluator's and lane-gate.mjs's real import closure"
}

# --- TEST-1508 (Spec-AC-05) --------------------------------------------------
test_1508_classification_order() {
  log_info "TEST-1508: architecture beats a kind match on the same path; no kind match is unclassified; a kind file renamed onto an architecture path is architecture"
  local case_name
  for case_name in dockerfile_both unclassified_bin rename_to_architecture; do
    mk
    local repo="$TEST_DIR/repo"
    new_repo "$repo"
    mkdir -p "$repo/docs/ai" "$repo/src"
    cat > "$repo/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
architecture:
  - id: containers
    globs: ["Dockerfile", "**/Dockerfile"]
kinds:
  - id: content
    globs: ["src/**/*.md", "Dockerfile"]
lanes:
  - id: lane-content
    decision_ref: test1508-ride@2026-10-03T12:00:00Z
    decision_match: "MERGE LANE test1508"
    signed_by: owner-login
    kinds: [content]
    merge_reaches: nothing
    marker: AAI_CONTENT1508_MERGE
YAML
    cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1508-ride","ts":"2026-10-03T12:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1508 approved"}
JSONL
    echo "readme" > "$repo/src/readme.md"
    commit_all "$repo" "base ($case_name)"
    local base; base="$(head_sha "$repo")"

    local expect_reason expect_path
    case "$case_name" in
      dockerfile_both)
        echo "FROM scratch" > "$repo/Dockerfile"
        expect_reason="architecture"; expect_path="Dockerfile"
        ;;
      unclassified_bin)
        printf 'binary-not-md' > "$repo/src/x.bin"
        expect_reason="unclassified"; expect_path="src/x.bin"
        ;;
      rename_to_architecture)
        (cd "$repo" && git mv src/readme.md Dockerfile) >/dev/null 2>&1
        expect_reason="architecture"; expect_path="Dockerfile"
        ;;
    esac
    commit_all "$repo" "head ($case_name)"
    local head; head="$(head_sha "$repo")"

    local ghbin="$TEST_DIR/gh-bin-$case_name" json="$TEST_DIR/pr-$case_name.json" log="$TEST_DIR/gh-$case_name.log"
    cat > "$json" <<JSON
{"number":6,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"state":"SUCCESS"}],"body":""}
JSON
    build_gh_stub "$ghbin" "$json" "$log"

    run_check "$repo" "$ghbin" 6
    assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=6 reason=$expect_reason path=$expect_path" \
      "TEST-1508 [$case_name]: expected reason=$expect_reason path=$expect_path, got: $OUT"
    [[ "$RC" -eq 3 ]] || log_fail "TEST-1508 [$case_name]: expected exit 3, got $RC: $OUT"
  done

  log_pass "TEST-1508: classifyFiles checks GUARD_PATHS, then architecture, then kind, in that order -- architecture wins over a simultaneous kind match"
}

# --- TEST-1509 (Spec-AC-06) --------------------------------------------------
test_1509_classify_glob_table() {
  log_info "TEST-1509: --classify prints one path/class line per row and matches the P5 glob semantics on a 10-case table"
  mk
  local rows=(
    "*.md|a/b.md|unclassified"
    "*.md|b.md|k"
    "**/*.md|b.md|k"
    "**/*.md|a/b/c/d.md|k"
    "src/**|src|unclassified"
    "src/**|src/file.js|k"
    "a?c|abc|k"
    "a?c|a/c|unclassified"
    "file.txt|fileXtxt|unclassified"
    "file.txt|file.txt|k"
  )
  local row glob path expected rest policy files out rc idx
  idx=0
  for row in "${rows[@]}"; do
    idx=$((idx + 1))
    glob="${row%%|*}"
    rest="${row#*|}"
    path="${rest%%|*}"
    expected="${rest#*|}"

    policy="$TEST_DIR/policy-$idx.yaml"
    cat > "$policy" <<YAML
version: 1
kinds:
  - id: k
    globs: ["$glob"]
YAML
    files="$TEST_DIR/files-$idx.txt"
    printf '%s\n' "$path" > "$files"

    out="$(node "$MP" --classify --path "$policy" --files-from "$files" --repo-root "$PROJECT_ROOT" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -eq 0 ]] || log_fail "TEST-1509 [row $idx: glob=$glob path=$path]: --classify exited $rc: $out"
    assert_payload_has_line "$out" "$path $expected" \
      "TEST-1509 [row $idx: glob=$glob path=$path]: expected class '$expected', got: $out"
  done

  log_pass "TEST-1509: globToRegExp matches the P5 glob table across 10 rows (star stops at slash, ** spans segments, ? excludes slash, no implicit basename match, literal dot)"
}

# --- TEST-1510 (Spec-AC-07) --------------------------------------------------
test_1510_requester_approved() {
  log_info "TEST-1510: a lane listing requester_logins allows only a listed login's latest deciding review, APPROVED at headRefOid; COMMENTED never revokes"
  local case_name
  for case_name in listed_approved unlisted stale_commit changes_requested dismissed label_only commented_after; do
    mk
    local repo="$TEST_DIR/repo"
    new_repo "$repo"
    mkdir -p "$repo/docs/ai" "$repo/docs"
    cat > "$repo/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-requester
    decision_ref: test1510-ride@2026-10-03T13:00:00Z
    decision_match: "MERGE LANE test1510"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_REQ1510_MERGE
    requester_logins: [alice]
    max_ceremony: 3
YAML
    cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1510-ride","ts":"2026-10-03T13:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1510 approved"}
JSONL
    echo "base doc" > "$repo/docs/base.md"
    commit_all "$repo" "base ($case_name)"
    local base; base="$(head_sha "$repo")"

    echo "a docs change" > "$repo/docs/changed-$case_name.md"
    commit_all "$repo" "head ($case_name)"
    local head; head="$(head_sha "$repo")"
    # This batch (Spec-AC-11) makes the sweep check and ceremony real; a
    # test written before that (Spec-AC-07) must now also carry a passing
    # sweep record and an explicit max_ceremony, or the unresolved-ceremony
    # default (3, no --spec/--intake given) and the missing sweep record
    # would both deny BEFORE evaluateLane ever reaches the requester check
    # this test exists to prove.
    write_sweep_record "$repo" 7

    local reviews allowed
    case "$case_name" in
      listed_approved)
        reviews="[{\"author\":{\"login\":\"alice\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-03T14:00:00Z\",\"commit\":{\"oid\":\"$head\"}}]"
        allowed=1
        ;;
      unlisted)
        reviews="[{\"author\":{\"login\":\"bob\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-03T14:00:00Z\",\"commit\":{\"oid\":\"$head\"}}]"
        allowed=0
        ;;
      stale_commit)
        reviews="[{\"author\":{\"login\":\"alice\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-03T14:00:00Z\",\"commit\":{\"oid\":\"$base\"}}]"
        allowed=0
        ;;
      changes_requested)
        reviews="[{\"author\":{\"login\":\"alice\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-03T14:00:00Z\",\"commit\":{\"oid\":\"$head\"}},{\"author\":{\"login\":\"alice\"},\"state\":\"CHANGES_REQUESTED\",\"submittedAt\":\"2026-10-03T15:00:00Z\",\"commit\":{\"oid\":\"$head\"}}]"
        allowed=0
        ;;
      dismissed)
        reviews="[{\"author\":{\"login\":\"alice\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-03T14:00:00Z\",\"commit\":{\"oid\":\"$head\"}},{\"author\":{\"login\":\"alice\"},\"state\":\"DISMISSED\",\"submittedAt\":\"2026-10-03T15:00:00Z\",\"commit\":{\"oid\":\"$head\"}}]"
        allowed=0
        ;;
      label_only)
        reviews="[]"
        allowed=0
        ;;
      commented_after)
        reviews="[{\"author\":{\"login\":\"alice\"},\"state\":\"APPROVED\",\"submittedAt\":\"2026-10-03T14:00:00Z\",\"commit\":{\"oid\":\"$head\"}},{\"author\":{\"login\":\"alice\"},\"state\":\"COMMENTED\",\"submittedAt\":\"2026-10-03T15:00:00Z\",\"commit\":{\"oid\":\"$head\"}}]"
        allowed=1
        ;;
    esac

    local ghbin="$TEST_DIR/gh-bin-$case_name" json="$TEST_DIR/pr-$case_name.json" log="$TEST_DIR/gh-$case_name.log"
    cat > "$json" <<JSON
{"number":7,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":$reviews,"statusCheckRollup":[{"state":"SUCCESS"}],"body":""}
JSON
    build_gh_stub "$ghbin" "$json" "$log"

    run_check "$repo" "$ghbin" 7
    if [[ "$allowed" -eq 1 ]]; then
      assert_payload_has_line "$OUT" "MERGE-POLICY allowed pr=7 lane=lane-requester marker=AAI_REQ1510_MERGE decision_ref=test1510-ride@2026-10-03T13:00:00Z merge_reaches=nothing" \
        "TEST-1510 [$case_name]: expected allowed, got: $OUT"
      [[ "$RC" -eq 0 ]] || log_fail "TEST-1510 [$case_name]: expected exit 0, got $RC: $OUT"
    else
      assert_payload_has_line "$OUT" "lane=lane-requester reason=requester_approval_missing" \
        "TEST-1510 [$case_name]: expected lane reason=requester_approval_missing, got: $OUT"
      [[ "$RC" -eq 3 ]] || log_fail "TEST-1510 [$case_name]: expected exit 3, got $RC: $OUT"
    fi
  done

  log_pass "TEST-1510: requesterApproved honors the latest deciding review per listed login, at headRefOid, with COMMENTED never overriding an approval"
}

# --- TEST-1511 (Spec-AC-08) --------------------------------------------------
test_1511_ci_green() {
  log_info "TEST-1511: an empty, in-progress, failed or pending rollup entry denies ci_not_green; SUCCESS plus NEUTRAL plus SKIPPED never trips that reason"
  local case_name
  for case_name in empty_rollup checkrun_in_progress checkrun_failure statuscontext_pending all_green; do
    mk
    local repo="$TEST_DIR/repo"
    new_repo "$repo"
    mkdir -p "$repo/docs/ai" "$repo/docs"
    cat > "$repo/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-ci
    decision_ref: test1511-ride@2026-10-03T16:00:00Z
    decision_match: "MERGE LANE test1511"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_CI1511_MERGE
YAML
    cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1511-ride","ts":"2026-10-03T16:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1511 approved"}
JSONL
    echo "base doc" > "$repo/docs/base.md"
    commit_all "$repo" "base ($case_name)"
    local base; base="$(head_sha "$repo")"
    echo "a docs change" > "$repo/docs/changed-$case_name.md"
    commit_all "$repo" "head ($case_name)"
    local head; head="$(head_sha "$repo")"

    local rollup
    case "$case_name" in
      empty_rollup) rollup='[]' ;;
      checkrun_in_progress) rollup='[{"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":null}]' ;;
      checkrun_failure) rollup='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"}]' ;;
      statuscontext_pending) rollup='[{"__typename":"StatusContext","state":"PENDING"}]' ;;
      all_green) rollup='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"NEUTRAL"},{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SKIPPED"},{"__typename":"StatusContext","state":"SUCCESS"}]' ;;
    esac

    local ghbin="$TEST_DIR/gh-bin-$case_name" json="$TEST_DIR/pr-$case_name.json" log="$TEST_DIR/gh-$case_name.log"
    cat > "$json" <<JSON
{"number":8,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":$rollup,"body":""}
JSON
    build_gh_stub "$ghbin" "$json" "$log"

    run_check "$repo" "$ghbin" 8
    if [[ "$case_name" == "all_green" ]]; then
      # Whatever this evaluator decides past CI (sweep check, ceremony, lane
      # match — each its own Spec-AC) is out of scope here; this test only
      # proves a fully green rollup never itself trips ci_not_green.
      assert_payload_not_contains "$OUT" "reason=ci_not_green" \
        "TEST-1511 [$case_name]: a fully green rollup must never be denied ci_not_green, got: $OUT"
    else
      assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=8 reason=ci_not_green" \
        "TEST-1511 [$case_name]: expected reason=ci_not_green, got: $OUT"
      [[ "$RC" -eq 3 ]] || log_fail "TEST-1511 [$case_name]: expected exit 3, got $RC: $OUT"
    fi
  done

  log_pass "TEST-1511: ciGreen denies an empty, in-progress, failed or pending rollup entry as ci_not_green; COMPLETED SUCCESS/NEUTRAL/SKIPPED CheckRuns and a SUCCESS StatusContext never trip that reason"
}

# --- TEST-1512 (Spec-AC-09) --------------------------------------------------
test_1512_sweep_check() {
  log_info "TEST-1512: a missing pr_sweep record denies sweep_check_failed (lane-gate.mjs --sweep-check exit 5); requires: { ci: false } or { sweep_check: false } is always unknown_key, never configurable"
  mk
  local repo="$TEST_DIR/repo"
  new_repo "$repo"
  mkdir -p "$repo/docs/ai" "$repo/docs"
  cat > "$repo/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-sweep
    decision_ref: test1512-ride@2026-10-03T17:00:00Z
    decision_match: "MERGE LANE test1512"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_SWEEP1512_MERGE
YAML
  cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1512-ride","ts":"2026-10-03T17:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1512 approved"}
JSONL
  echo "base doc" > "$repo/docs/base.md"
  commit_all "$repo" "base"
  local base; base="$(head_sha "$repo")"
  echo "a docs change" > "$repo/docs/changed.md"
  commit_all "$repo" "head"
  local head; head="$(head_sha "$repo")"
  # Deliberately NO write_sweep_record -- docs/ai/EVENTS.jsonl carries no
  # pr_sweep record at all, so the spawned lane-gate.mjs --sweep-check must
  # exit 5 (reason=missing-record).

  local ghbin="$TEST_DIR/gh-bin" json="$TEST_DIR/pr.json" log="$TEST_DIR/gh.log"
  cat > "$json" <<JSON
{"number":9,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}],"body":""}
JSON
  build_gh_stub "$ghbin" "$json" "$log"

  run_check "$repo" "$ghbin" 9
  assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=9 reason=sweep_check_failed" \
    "TEST-1512: expected reason=sweep_check_failed with no pr_sweep record, got: $OUT"
  [[ "$RC" -eq 3 ]] || log_fail "TEST-1512: expected exit 3, got $RC: $OUT"

  local bad_key
  for bad_key in ci sweep_check; do
    mk
    local vrepo="$TEST_DIR/vrepo"
    mkdir -p "$vrepo/docs/ai"
    cat > "$vrepo/docs/ai/merge-policy.yaml" <<YAML
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-nokey
    decision_ref: test1512-nokey@2026-10-03T17:30:00Z
    decision_match: "MERGE LANE test1512 nokey"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_NOKEY1512_MERGE
    requires:
      $bad_key: false
YAML
    local vout vrc
    vout="$(node "$MP" --validate --path "$vrepo/docs/ai/merge-policy.yaml" --repo-root "$vrepo" 2>&1)" && vrc=0 || vrc=$?
    [[ "$vrc" -eq 1 ]] || log_fail "TEST-1512 [requires.$bad_key]: --validate must exit 1, got $vrc: $vout"
    assert_payload_has_line "$vout" "INVALID lane=lane-nokey code=unknown_key" \
      "TEST-1512 [requires.$bad_key]: expected unknown_key, got: $vout"
  done

  log_pass "TEST-1512: lane-gate.mjs --sweep-check's exit 5 maps to sweep_check_failed; a requires key that would disable CI or the sweep check is always unknown_key"
}

# --- TEST-1513 (Spec-AC-10) --------------------------------------------------
test_1513_public_effect_opt_in() {
  log_info "TEST-1513: a production lane, or a preview lane on a public-preview repo, without allow_public_side_effect: true fails --validate with public_effect_not_opted_in; --check on such a base policy denies policy_invalid; opting in validates both"
  mk
  local root="$TEST_DIR"
  mkdir -p "$root/docs/ai"
  cat > "$root/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1513-prod","ts":"2026-10-03T20:30:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1513 prod approved"}
{"type":"hitl_decision","ref_id":"test1513-prev","ts":"2026-10-03T20:31:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1513 preview approved"}
JSONL

  local prod_no_optin="$root/policy-prod-no-optin.yaml"
  cat > "$prod_no_optin" <<'YAML'
version: 1
deploy:
  preview: none
  production_on_merge: true
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-prod
    decision_ref: test1513-prod@2026-10-03T20:30:00Z
    decision_match: "MERGE LANE test1513 prod"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: production
    marker: AAI_PROD1513_MERGE
    requester_logins: [alice]
YAML
  local out rc
  out="$(node "$MP" --validate --path "$prod_no_optin" --repo-root "$root" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-1513 [prod_no_optin]: expected exit 1, got $rc: $out"
  assert_payload_has_line "$out" "INVALID lane=lane-prod code=public_effect_not_opted_in" \
    "TEST-1513 [prod_no_optin]: expected public_effect_not_opted_in, got: $out"

  local prev_no_optin="$root/policy-prev-no-optin.yaml"
  cat > "$prev_no_optin" <<'YAML'
version: 1
deploy:
  preview: public
  production_on_merge: false
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-prev
    decision_ref: test1513-prev@2026-10-03T20:31:00Z
    decision_match: "MERGE LANE test1513 preview"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: preview
    marker: AAI_PREV1513_MERGE
    requester_logins: [alice]
YAML
  out="$(node "$MP" --validate --path "$prev_no_optin" --repo-root "$root" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-1513 [prev_no_optin]: expected exit 1, got $rc: $out"
  assert_payload_has_line "$out" "INVALID lane=lane-prev code=public_effect_not_opted_in" \
    "TEST-1513 [prev_no_optin]: expected public_effect_not_opted_in, got: $out"

  local both_optin="$root/policy-both-optin.yaml"
  cat > "$both_optin" <<'YAML'
version: 1
deploy:
  preview: public
  production_on_merge: true
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-prod
    decision_ref: test1513-prod@2026-10-03T20:30:00Z
    decision_match: "MERGE LANE test1513 prod"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: production
    allow_public_side_effect: true
    marker: AAI_PROD1513_MERGE
    requester_logins: [alice]
YAML
  out="$(node "$MP" --validate --path "$both_optin" --repo-root "$root" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-1513 [opted_in]: expected exit 0, got $rc: $out"
  assert_payload_has_line "$out" "VALID lanes=1" "TEST-1513 [opted_in]: expected VALID lanes=1, got: $out"

  # --check on a base policy that fails validation denies policy_invalid.
  mk
  local repo="$TEST_DIR/repo"
  new_repo "$repo"
  mkdir -p "$repo/docs/ai" "$repo/docs"
  cp "$prod_no_optin" "$repo/docs/ai/merge-policy.yaml"
  cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1513-prod","ts":"2026-10-03T20:30:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1513 prod approved"}
JSONL
  echo "base doc" > "$repo/docs/base.md"
  commit_all "$repo" "base: production lane without opt-in"
  local base; base="$(head_sha "$repo")"
  echo "a docs change" > "$repo/docs/changed.md"
  commit_all "$repo" "head"
  local head; head="$(head_sha "$repo")"

  local ghbin="$TEST_DIR/gh-bin" json="$TEST_DIR/pr.json" log="$TEST_DIR/gh.log"
  cat > "$json" <<JSON
{"number":12,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"state":"SUCCESS"}],"body":""}
JSON
  build_gh_stub "$ghbin" "$json" "$log"

  run_check "$repo" "$ghbin" 12
  assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=12 reason=policy_invalid" \
    "TEST-1513 [check]: expected policy_invalid, got: $OUT"
  assert_payload_contains "$OUT" "public_effect_not_opted_in" \
    "TEST-1513 [check]: expected stdout to name public_effect_not_opted_in, got: $OUT"
  [[ "$RC" -eq 3 ]] || log_fail "TEST-1513 [check]: expected exit 3, got $RC: $OUT"

  log_pass "TEST-1513: production or public-preview reach without allow_public_side_effect: true fails validate and denies policy_invalid at check; opting in validates"
}

# --- TEST-1514 (Spec-AC-11) --------------------------------------------------
test_1514_ceremony_exceeds() {
  log_info "TEST-1514: a ceremony-3 ride denies a lane with no max_ceremony as ceremony_exceeds, and allows one with max_ceremony 3; a ride with no resolvable spec or intake counts as ceremony 3 too"
  mk
  local spec3="$TEST_DIR/spec-ceremony3.md"
  cat > "$spec3" <<'MD'
---
id: spec-test1514
type: spec
ceremony_level: 3
---

# Spec
MD

  local case_name
  for case_name in explicit_no_cap explicit_capped unresolved_defaults_to_3; do
    mk
    local repo="$TEST_DIR/repo"
    new_repo "$repo"
    mkdir -p "$repo/docs/ai" "$repo/docs"
    local max_line=""
    [[ "$case_name" == "explicit_capped" ]] && max_line="    max_ceremony: 3"
    cat > "$repo/docs/ai/merge-policy.yaml" <<YAML
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-ceremony
    decision_ref: test1514-ride@2026-10-03T18:00:00Z
    decision_match: "MERGE LANE test1514"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_CEREMONY1514_MERGE
$max_line
YAML
    cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1514-ride","ts":"2026-10-03T18:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1514 approved"}
JSONL
    echo "base doc" > "$repo/docs/base.md"
    commit_all "$repo" "base ($case_name)"
    local base; base="$(head_sha "$repo")"
    echo "a docs change" > "$repo/docs/changed-$case_name.md"
    commit_all "$repo" "head ($case_name)"
    local head; head="$(head_sha "$repo")"
    write_sweep_record "$repo" 10

    local ghbin="$TEST_DIR/gh-bin-$case_name" json="$TEST_DIR/pr-$case_name.json" log="$TEST_DIR/gh-$case_name.log"
    cat > "$json" <<JSON
{"number":10,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}],"body":""}
JSON
    build_gh_stub "$ghbin" "$json" "$log"

    case "$case_name" in
      explicit_no_cap)
        run_check "$repo" "$ghbin" 10 --spec "$spec3"
        assert_payload_has_line "$OUT" "lane=lane-ceremony reason=ceremony_exceeds" \
          "TEST-1514 [$case_name]: expected ceremony_exceeds, got: $OUT"
        assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=10 reason=no_lane_matched" \
          "TEST-1514 [$case_name]: expected no_lane_matched, got: $OUT"
        [[ "$RC" -eq 3 ]] || log_fail "TEST-1514 [$case_name]: expected exit 3, got $RC: $OUT"
        ;;
      explicit_capped)
        run_check "$repo" "$ghbin" 10 --spec "$spec3"
        assert_payload_has_line "$OUT" "MERGE-POLICY allowed pr=10 lane=lane-ceremony marker=AAI_CEREMONY1514_MERGE decision_ref=test1514-ride@2026-10-03T18:00:00Z merge_reaches=nothing" \
          "TEST-1514 [$case_name]: expected allowed with max_ceremony 3, got: $OUT"
        [[ "$RC" -eq 0 ]] || log_fail "TEST-1514 [$case_name]: expected exit 0, got $RC: $OUT"
        ;;
      unresolved_defaults_to_3)
        run_check "$repo" "$ghbin" 10
        assert_payload_has_line "$OUT" "lane=lane-ceremony reason=ceremony_exceeds" \
          "TEST-1514 [$case_name]: expected ceremony_exceeds with no --spec/--intake given, got: $OUT"
        [[ "$RC" -eq 3 ]] || log_fail "TEST-1514 [$case_name]: expected exit 3, got $RC: $OUT"
        ;;
    esac
  done

  log_pass "TEST-1514: DEFAULT_MAX_CEREMONY=2 denies a ceremony-3 ride as ceremony_exceeds unless the lane opts in with max_ceremony: 3; an unresolvable spec/intake defaults to ceremony 3"
}

# --- TEST-1515 (Spec-AC-11) --------------------------------------------------
test_1515_ceremony_agrees_with_lane_gate() {
  log_info "TEST-1515: the ceremony level this evaluator reads (--check --debug-inputs) agrees with the ceremony_level line lane-gate.mjs itself prints for the same spec, across levels 0, 2, 3 and an absent field"
  mk
  local specs_dir="$TEST_DIR/specs"
  mkdir -p "$specs_dir"
  cat > "$specs_dir/level0.md" <<'MD'
---
id: spec-test1515-l0
type: spec
ceremony_level: 0
---

# Spec
MD
  cat > "$specs_dir/level2.md" <<'MD'
---
id: spec-test1515-l2
type: spec
ceremony_level: 2
---

# Spec
MD
  cat > "$specs_dir/level3.md" <<'MD'
---
id: spec-test1515-l3
type: spec
ceremony_level: 3
---

# Spec
MD
  cat > "$specs_dir/absent.md" <<'MD'
---
id: spec-test1515-absent
type: spec
---

# Spec
MD

  local repo="$TEST_DIR/repo"
  new_repo "$repo"
  mkdir -p "$repo/docs/ai" "$repo/docs"
  cat > "$repo/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-seam
    decision_ref: test1515-ride@2026-10-03T19:00:00Z
    decision_match: "MERGE LANE test1515"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_SEAM1515_MERGE
    max_ceremony: 3
YAML
  cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1515-ride","ts":"2026-10-03T19:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1515 approved"}
JSONL
  echo "base doc" > "$repo/docs/base.md"
  commit_all "$repo" "base"
  local base; base="$(head_sha "$repo")"
  echo "a docs change" > "$repo/docs/changed.md"
  commit_all "$repo" "head"
  local head; head="$(head_sha "$repo")"
  write_sweep_record "$repo" 11

  local ghbin="$TEST_DIR/gh-bin" json="$TEST_DIR/pr.json" log="$TEST_DIR/gh.log"
  cat > "$json" <<JSON
{"number":11,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}],"body":""}
JSON
  build_gh_stub "$ghbin" "$json" "$log"

  local name spec lgout mpout lg_value mp_value expect_value
  for name in level0 level2 level3 absent; do
    spec="$specs_dir/$name.md"

    lgout="$(node "$PROJECT_ROOT/.aai/scripts/lane-gate.mjs" --spec "$spec" --repo-root "$PROJECT_ROOT" 2>&1)"
    lg_value=""
    if [[ "$lgout" =~ ceremony_level=([^[:space:]]+) ]]; then
      lg_value="${BASH_REMATCH[1]}"
    fi
    [[ -n "$lg_value" ]] || log_fail "TEST-1515 [$name]: could not parse lane-gate.mjs's own ceremony_level line, got: $lgout"
    expect_value="$lg_value"
    [[ "$lg_value" == "absent" ]] && expect_value=2

    run_check "$repo" "$ghbin" 11 --spec "$spec" --debug-inputs
    mp_value=""
    if [[ "$OUT" =~ ceremony=([^[:space:]]+) ]]; then
      mp_value="${BASH_REMATCH[1]}"
    fi
    [[ "$mp_value" == "$expect_value" ]] || log_fail "TEST-1515 [$name]: lane-gate prints ceremony_level=$lg_value but merge-policy read ceremony=$mp_value (expected $expect_value); full output: $OUT"
  done

  log_pass "TEST-1515: readRideCeremony agrees with lane-gate.mjs's own ceremony_level reading on levels 0, 2, 3 and an absent field (canon: absent is implicit 2)"
}

# --- TEST-1516 (Spec-AC-12) --------------------------------------------------
test_1516_reaches_inconsistent() {
  log_info "TEST-1516: a lane's merge_reaches must agree with what deploy implies; three mismatches each give reaches_inconsistent, a consistent policy validates"
  mk
  local root="$TEST_DIR"
  mkdir -p "$root/docs/ai"

  local case_name policy out rc lane_id
  for case_name in preview_without_deploy nothing_with_production_on_merge production_without_deploy; do
    policy="$root/policy-$case_name.yaml"
    case "$case_name" in
      preview_without_deploy)
        lane_id=lane-x
        cat > "$policy" <<'YAML'
version: 1
deploy:
  preview: none
  production_on_merge: false
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-x
    decision_ref: some-ref@2026-01-01T00:00:00Z
    decision_match: "x"
    signed_by: owner
    kinds: [docs]
    merge_reaches: preview
    marker: AAI_X1516_MERGE
    requester_logins: [alice]
YAML
        ;;
      nothing_with_production_on_merge)
        lane_id=lane-y
        cat > "$policy" <<'YAML'
version: 1
deploy:
  preview: none
  production_on_merge: true
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-y
    decision_ref: some-ref@2026-01-01T00:00:00Z
    decision_match: "x"
    signed_by: owner
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_Y1516_MERGE
YAML
        ;;
      production_without_deploy)
        lane_id=lane-z
        cat > "$policy" <<'YAML'
version: 1
deploy:
  preview: private
  production_on_merge: false
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-z
    decision_ref: some-ref@2026-01-01T00:00:00Z
    decision_match: "x"
    signed_by: owner
    kinds: [docs]
    merge_reaches: production
    allow_public_side_effect: true
    requester_logins: [alice]
    marker: AAI_Z1516_MERGE
YAML
        ;;
    esac

    out="$(node "$MP" --validate --path "$policy" --repo-root "$root" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -eq 1 ]] || log_fail "TEST-1516 [$case_name]: expected exit 1, got $rc: $out"
    assert_payload_has_line "$out" "INVALID lane=$lane_id code=reaches_inconsistent" \
      "TEST-1516 [$case_name]: expected reaches_inconsistent, got: $out"
  done

  # A consistent policy: merge_reaches nothing with default deploy -> VALID.
  local good="$root/policy-consistent.yaml"
  cat > "$good" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-ok
    decision_ref: test1516-ride@2026-10-03T20:00:00Z
    decision_match: "MERGE LANE test1516"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_OK1516_MERGE
YAML
  cat > "$root/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1516-ride","ts":"2026-10-03T20:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1516 approved"}
JSONL
  out="$(node "$MP" --validate --path "$good" --repo-root "$root" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-1516 [consistent]: expected exit 0, got $rc: $out"
  assert_payload_has_line "$out" "VALID lanes=1" "TEST-1516 [consistent]: expected VALID lanes=1, got: $out"

  log_pass "TEST-1516: merge_reaches must agree with what deploy implies (reaches_inconsistent); a consistent policy validates"
}

# --- TEST-1517 (Spec-AC-12) --------------------------------------------------
test_1517_decision_binding_codes() {
  log_info "TEST-1517: decisions fixture: no match, two matches on shared ref+ts, owner_signoff false, other actor give decision_missing, decision_ambiguous, decision_unsigned, signer_mismatch"
  local case_name
  for case_name in no_match ambiguous unsigned wrong_actor; do
    mk
    local root="$TEST_DIR"
    mkdir -p "$root/docs/ai"
    local policy="$root/policy.yaml"
    cat > "$policy" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-dec
    decision_ref: test1517-ride@2026-10-03T21:00:00Z
    decision_match: "MERGE LANE test1517"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_DEC1517_MERGE
YAML
    local decisions="$root/docs/ai/decisions.jsonl"
    case "$case_name" in
      no_match)
        : > "$decisions"
        ;;
      ambiguous)
        cat > "$decisions" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1517-ride","ts":"2026-10-03T21:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1517 approved first"}
{"type":"hitl_decision","ref_id":"test1517-ride","ts":"2026-10-03T21:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1517 approved second"}
JSONL
        ;;
      unsigned)
        cat > "$decisions" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1517-ride","ts":"2026-10-03T21:00:00Z","owner_signoff":false,"actor":"owner-login","decision":"MERGE LANE test1517 approved"}
JSONL
        ;;
      wrong_actor)
        cat > "$decisions" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1517-ride","ts":"2026-10-03T21:00:00Z","owner_signoff":true,"actor":"someone-else","decision":"MERGE LANE test1517 approved"}
JSONL
        ;;
    esac

    local out rc expected_code
    case "$case_name" in
      no_match) expected_code=decision_missing ;;
      ambiguous) expected_code=decision_ambiguous ;;
      unsigned) expected_code=decision_unsigned ;;
      wrong_actor) expected_code=signer_mismatch ;;
    esac

    out="$(node "$MP" --validate --path "$policy" --repo-root "$root" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -eq 1 ]] || log_fail "TEST-1517 [$case_name]: expected exit 1, got $rc: $out"
    assert_payload_has_line "$out" "INVALID lane=lane-dec code=$expected_code" \
      "TEST-1517 [$case_name]: expected $expected_code, got: $out"
  done

  log_pass "TEST-1517: the decision binder gives decision_missing, decision_ambiguous, decision_unsigned and signer_mismatch for their fixtures"
}

# --- TEST-1518 (Spec-AC-12) --------------------------------------------------
test_1518_structural_validate_codes() {
  log_info "TEST-1518: unknown key, duplicate lane id, undefined kind, empty globs and reaches preview without requester_logins each give their own validate code"
  local case_name
  for case_name in unknown_key duplicate_lane undefined_kind empty_globs requester_missing; do
    mk
    local root="$TEST_DIR"
    mkdir -p "$root/docs/ai"
    local policy="$root/policy.yaml"
    case "$case_name" in
      unknown_key)
        cat > "$policy" <<'YAML'
version: 1
not_a_real_key: true
kinds:
  - id: docs
    globs: ["docs/**"]
lanes: []
YAML
        ;;
      duplicate_lane)
        cat > "$policy" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-dup
    decision_ref: test1518-dup-a@2026-10-03T21:10:00Z
    decision_match: "x"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_DUPA1518_MERGE
  - id: lane-dup
    decision_ref: test1518-dup-b@2026-10-03T21:11:00Z
    decision_match: "x"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_DUPB1518_MERGE
YAML
        ;;
      undefined_kind)
        cat > "$policy" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-badkind
    decision_ref: test1518-badkind@2026-10-03T21:12:00Z
    decision_match: "x"
    signed_by: owner-login
    kinds: [no-such-kind]
    merge_reaches: nothing
    marker: AAI_BADKIND1518_MERGE
YAML
        ;;
      empty_globs)
        cat > "$policy" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: []
lanes: []
YAML
        ;;
      requester_missing)
        cat > "$policy" <<'YAML'
version: 1
deploy:
  preview: private
  production_on_merge: false
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-noreq
    decision_ref: test1518-noreq@2026-10-03T21:13:00Z
    decision_match: "x"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: preview
    marker: AAI_NOREQ1518_MERGE
YAML
        ;;
    esac

    local out rc expected_code lane_id
    case "$case_name" in
      unknown_key) expected_code=unknown_key; lane_id='-' ;;
      duplicate_lane) expected_code=duplicate_lane; lane_id=lane-dup ;;
      undefined_kind) expected_code=undefined_kind; lane_id=lane-badkind ;;
      empty_globs) expected_code=empty_globs; lane_id=docs ;;
      requester_missing) expected_code=requester_missing; lane_id=lane-noreq ;;
    esac

    out="$(node "$MP" --validate --path "$policy" --repo-root "$root" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -eq 1 ]] || log_fail "TEST-1518 [$case_name]: expected exit 1, got $rc: $out"
    assert_payload_has_line "$out" "INVALID lane=$lane_id code=$expected_code" \
      "TEST-1518 [$case_name]: expected $expected_code, got: $out"
  done

  log_pass "TEST-1518: unknown_key, duplicate_lane, undefined_kind, empty_globs and requester_missing are each their own validate code, one INVALID line per error"
}

# --- TEST-1519 (Spec-AC-13) --------------------------------------------------
test_1519_marker_validation() {
  log_info "TEST-1519: a marker failing MARKER_RE, or equal to AAI_OPERATOR_MERGE, is bad_marker; two lanes sharing one marker is duplicate_marker on the second; an allowed verdict names the lane's own marker"
  local case_name
  for case_name in valid_marker lowercase_marker operator_marker; do
    mk
    local root="$TEST_DIR"
    mkdir -p "$root/docs/ai"
    local marker
    case "$case_name" in
      valid_marker) marker="AAI_X_MERGE" ;;
      lowercase_marker) marker="aai_x_merge" ;;
      operator_marker) marker="AAI_OPERATOR_MERGE" ;;
    esac
    local policy="$root/policy.yaml"
    cat > "$policy" <<YAML
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-marker
    decision_ref: test1519-ride@2026-10-03T21:20:00Z
    decision_match: "x"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: $marker
YAML
    cat > "$root/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1519-ride","ts":"2026-10-03T21:20:00Z","owner_signoff":true,"actor":"owner-login","decision":"x"}
JSONL

    local out rc
    out="$(node "$MP" --validate --path "$policy" --repo-root "$root" 2>&1)" && rc=0 || rc=$?
    case "$case_name" in
      valid_marker)
        [[ "$rc" -eq 0 ]] || log_fail "TEST-1519 [$case_name]: expected exit 0, got $rc: $out"
        assert_payload_has_line "$out" "VALID lanes=1" "TEST-1519 [$case_name]: expected VALID lanes=1, got: $out"
        ;;
      lowercase_marker|operator_marker)
        [[ "$rc" -eq 1 ]] || log_fail "TEST-1519 [$case_name]: expected exit 1, got $rc: $out"
        assert_payload_has_line "$out" "INVALID lane=lane-marker code=bad_marker" \
          "TEST-1519 [$case_name]: expected bad_marker, got: $out"
        ;;
    esac
  done

  mk
  local root2="$TEST_DIR"
  mkdir -p "$root2/docs/ai"
  local dup_policy="$root2/policy-dup.yaml"
  cat > "$dup_policy" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-dup-a
    decision_ref: test1519-dup-a@2026-10-03T21:21:00Z
    decision_match: "x"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_SHARED1519_MERGE
  - id: lane-dup-b
    decision_ref: test1519-dup-b@2026-10-03T21:22:00Z
    decision_match: "x"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_SHARED1519_MERGE
YAML
  local out2 rc2
  out2="$(node "$MP" --validate --path "$dup_policy" --repo-root "$root2" 2>&1)" && rc2=0 || rc2=$?
  [[ "$rc2" -eq 1 ]] || log_fail "TEST-1519 [duplicate_marker]: expected exit 1, got $rc2: $out2"
  assert_payload_has_line "$out2" "INVALID lane=lane-dup-b code=duplicate_marker" \
    "TEST-1519 [duplicate_marker]: expected duplicate_marker on the second lane, got: $out2"

  # An allowed verdict names the lane's own marker.
  mk
  local repo="$TEST_DIR/repo"
  new_repo "$repo"
  mkdir -p "$repo/docs/ai" "$repo/docs"
  cat > "$repo/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-allowed1519
    decision_ref: test1519-allowed@2026-10-03T21:23:00Z
    decision_match: "MERGE LANE test1519 allowed"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_ALLOWED1519_MERGE
    max_ceremony: 3
YAML
  cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1519-allowed","ts":"2026-10-03T21:23:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1519 allowed approved"}
JSONL
  echo "base doc" > "$repo/docs/base.md"
  commit_all "$repo" "base"
  local base; base="$(head_sha "$repo")"
  echo "a docs change" > "$repo/docs/changed.md"
  commit_all "$repo" "head"
  local head; head="$(head_sha "$repo")"
  write_sweep_record "$repo" 13

  local ghbin="$TEST_DIR/gh-bin" json="$TEST_DIR/pr.json" log="$TEST_DIR/gh.log"
  cat > "$json" <<JSON
{"number":13,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"state":"SUCCESS"}],"body":""}
JSON
  build_gh_stub "$ghbin" "$json" "$log"

  run_check "$repo" "$ghbin" 13
  assert_payload_has_line "$OUT" "MERGE-POLICY allowed pr=13 lane=lane-allowed1519 marker=AAI_ALLOWED1519_MERGE decision_ref=test1519-allowed@2026-10-03T21:23:00Z merge_reaches=nothing" \
    "TEST-1519 [allowed]: expected allowed naming the lane's own marker, got: $OUT"
  [[ "$RC" -eq 0 ]] || log_fail "TEST-1519 [allowed]: expected exit 0, got $RC: $OUT"

  log_pass "TEST-1519: MARKER_RE-backed bad_marker, operator-marker collision, duplicate_marker, and the allowed line naming the lane's own marker"
}

main() {
  echo "Testing: $TEST_NAME"
  echo "===================="

  check_deps

  test_1501_no_policy
  test_1503_base_absent_head_permissive
  test_1504_base_restrictive_head_widens
  test_1505_decision_only_in_head
  test_1506_guard_paths_denied
  test_1507_guard_paths_superset_of_import_closure
  test_1508_classification_order
  test_1509_classify_glob_table
  test_1510_requester_approved
  test_1511_ci_green
  test_1512_sweep_check
  test_1513_public_effect_opt_in
  test_1514_ceremony_exceeds
  test_1515_ceremony_agrees_with_lane_gate
  test_1516_reaches_inconsistent
  test_1517_decision_binding_codes
  test_1518_structural_validate_codes
  test_1519_marker_validation

  echo ""
  if [[ $FAILED -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
  else
    echo "Some tests FAILED."
    exit 1
  fi
}

# Allow sourcing/invoking a single test function for isolated RED/GREEN
# evidence capture (LEARNED convention); run the full suite otherwise. An
# UNKNOWN selector must refuse (non-zero exit), never fail-open (TEST-473,
# tests/skills/test-aai-hygiene-pack.sh test_094) — `set -uo pipefail` alone
# does not abort on a failed/undefined command, so the call's own exit code
# is captured and checked explicitly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -ge 1 ]]; then
    check_deps
    sel_rc=0
    "$1" || sel_rc=$?
    if [[ "$sel_rc" -ne 0 || "$FAILED" -ne 0 ]]; then exit 1; fi
  else
    main
  fi
fi
