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
# BATCH 8 (final) adds:
#   TEST-1530 (Spec-AC-22) — PROFILES/DOCS_AI_CANON/suite-map companion
#                            wiring (verified, not newly authored: batches
#                            1-7 already classified merge-policy.mjs/.yaml)
#   TEST-1532 (Spec-AC-23) — CHANGELOG '## [unreleased] — ' breaking-change
#                            entry
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
// validation-round1 NB-3: lane-gate.mjs SPAWNS select-suites.mjs
// (runSelectSuites, a child process -- not an `import`, so the closure walk
// above never finds it) and both of them READ these two config files
// directly (profilesCore / the docs-audit.yaml protected_paths_l3 reader).
// Editing any of the four changes the --sweep-check verdict exactly as
// editing lane-gate.mjs itself would, so GUARD_PATHS must cover them too.
closure.add('.aai/scripts/select-suites.mjs');
closure.add('tests/skills/suite-map.yaml');
closure.add('docs/ai/docs-audit.yaml');
closure.add('.aai/system/PROFILES.yaml');

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

# --- TEST-1521 (Spec-AC-15) --------------------------------------------------
# write_intake <path> <id> <type> — a minimal intake doc fixture: only the
# frontmatter fields readIntakeMeta reads (id, type) matter to this suite.
write_intake() {
  local path="$1" id="$2" type="$3"
  cat > "$path" <<MD
---
id: $id
type: $type
---

# intake fixture
MD
}

# write_state <path> <validation_status> <review_status> — a minimal
# STATE.yaml fixture carrying only the two top-level blocks readStateStatus
# reads.
write_state() {
  local path="$1" validation="$2" review="$3"
  cat > "$path" <<YAML
last_validation:
  status: $validation
code_review:
  status: $review
YAML
}

test_1521_requires_keys() {
  log_info "TEST-1521: one fixture per requires key unmet (intake type rfc, ref listed as a base roadmap capability, STATE last_validation fail, code_review fail, body lacking the literal) gives its own reason; the fixture meeting all five is allowed"
  local case_name
  for case_name in intake_type roadmap_capability validation_not_pass review_not_pass pr_body_missing allowed; do
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
  - id: lane-requires
    decision_ref: test1521-ride@2026-10-03T19:00:00Z
    decision_match: "MERGE LANE test1521"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_REQUIRES1521_MERGE
    requires:
      intake_types: [change, issue]
      exclude_roadmap_capability: true
      validation_pass: true
      review_pass: true
      pr_body_contains: "Residual"
YAML
    cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1521-ride","ts":"2026-10-03T19:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1521 approved"}
JSONL
    # The roadmap-capability case needs its ride's ref committed into the
    # BASE roadmap as a `- capability:` entry (S4: read from base, never
    # head/working tree); every other case leaves roadmap.yaml absent so
    # exclude_roadmap_capability never has anything to match.
    if [[ "$case_name" == "roadmap_capability" ]]; then
      cat > "$repo/docs/ai/roadmap.yaml" <<'YAML'
pairs:
  - capability: ride-1521
    status: planned
YAML
    fi
    echo "base doc" > "$repo/docs/base.md"
    commit_all "$repo" "base ($case_name)"
    local base; base="$(head_sha "$repo")"
    echo "a docs change" > "$repo/docs/changed-$case_name.md"
    commit_all "$repo" "head ($case_name)"
    local head; head="$(head_sha "$repo")"
    write_sweep_record "$repo" 30

    local intake_type="change" body="plan carries a Residual risk"
    [[ "$case_name" == "intake_type" ]] && intake_type="rfc"
    [[ "$case_name" == "pr_body_missing" ]] && body="no matching literal here"
    write_intake "$TEST_DIR/intake.md" "ride-1521" "$intake_type"

    local validation_status="pass" review_status="pass"
    [[ "$case_name" == "validation_not_pass" ]] && validation_status="fail"
    [[ "$case_name" == "review_not_pass" ]] && review_status="fail"
    write_state "$TEST_DIR/STATE.yaml" "$validation_status" "$review_status"

    local ghbin="$TEST_DIR/gh-bin" json="$TEST_DIR/pr.json" log="$TEST_DIR/gh.log"
    cat > "$json" <<JSON
{"number":30,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}],"body":"$body"}
JSON
    build_gh_stub "$ghbin" "$json" "$log"

    run_check "$repo" "$ghbin" 30 --intake "$TEST_DIR/intake.md" --state "$TEST_DIR/STATE.yaml"

    case "$case_name" in
      allowed)
        assert_payload_has_line "$OUT" "MERGE-POLICY allowed pr=30 lane=lane-requires marker=AAI_REQUIRES1521_MERGE decision_ref=test1521-ride@2026-10-03T19:00:00Z merge_reaches=nothing" \
          "TEST-1521 [$case_name]: expected allowed when every requires key is met, got: $OUT"
        [[ "$RC" -eq 0 ]] || log_fail "TEST-1521 [$case_name]: expected exit 0, got $RC: $OUT"
        ;;
      intake_type)
        assert_payload_has_line "$OUT" "lane=lane-requires reason=intake_type" \
          "TEST-1521 [$case_name]: expected reason=intake_type, got: $OUT"
        [[ "$RC" -eq 3 ]] || log_fail "TEST-1521 [$case_name]: expected exit 3, got $RC: $OUT"
        ;;
      roadmap_capability)
        assert_payload_has_line "$OUT" "lane=lane-requires reason=roadmap_capability" \
          "TEST-1521 [$case_name]: expected reason=roadmap_capability, got: $OUT"
        [[ "$RC" -eq 3 ]] || log_fail "TEST-1521 [$case_name]: expected exit 3, got $RC: $OUT"
        ;;
      validation_not_pass)
        assert_payload_has_line "$OUT" "lane=lane-requires reason=validation_not_pass" \
          "TEST-1521 [$case_name]: expected reason=validation_not_pass, got: $OUT"
        [[ "$RC" -eq 3 ]] || log_fail "TEST-1521 [$case_name]: expected exit 3, got $RC: $OUT"
        ;;
      review_not_pass)
        assert_payload_has_line "$OUT" "lane=lane-requires reason=review_not_pass" \
          "TEST-1521 [$case_name]: expected reason=review_not_pass, got: $OUT"
        [[ "$RC" -eq 3 ]] || log_fail "TEST-1521 [$case_name]: expected exit 3, got $RC: $OUT"
        ;;
      pr_body_missing)
        assert_payload_has_line "$OUT" "lane=lane-requires reason=pr_body_missing" \
          "TEST-1521 [$case_name]: expected reason=pr_body_missing, got: $OUT"
        [[ "$RC" -eq 3 ]] || log_fail "TEST-1521 [$case_name]: expected exit 3, got $RC: $OUT"
        ;;
    esac
  done

  log_pass "TEST-1521: intake_types, exclude_roadmap_capability, validation_pass, review_pass and pr_body_contains each give their own unmet reason; all five met together is allowed"
}

# --- TEST-1522 (Spec-AC-16) --------------------------------------------------
test_1522_pr_state_and_api_errors() {
  log_info "TEST-1522: CLOSED state and isDraft true both give pr_not_open; a gh stub exiting non-zero and gh absent from PATH both give api_unavailable; an unresolvable baseRefOid gives base_unavailable -- every case exits 3"
  mk
  local spec_dir="$TEST_DIR"
  local repo="$spec_dir/repo"
  new_repo "$repo"
  mkdir -p "$repo/docs/ai" "$repo/docs"
  cat > "$repo/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-1522
    decision_ref: test1522-ride@2026-10-03T20:00:00Z
    decision_match: "MERGE LANE test1522"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_API1522_MERGE
YAML
  cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1522-ride","ts":"2026-10-03T20:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1522 approved"}
JSONL
  echo "base doc" > "$repo/docs/base.md"
  commit_all "$repo" "base"
  local base; base="$(head_sha "$repo")"
  echo "a docs change" > "$repo/docs/changed.md"
  commit_all "$repo" "head"
  local head; head="$(head_sha "$repo")"
  write_sweep_record "$repo" 40

  local case_name
  for case_name in closed_state draft gh_exits_nonzero gh_absent bad_base_oid; do
    local ghbin="$TEST_DIR/gh-bin-$case_name" json="$TEST_DIR/pr-$case_name.json" log="$TEST_DIR/gh-$case_name.log"
    case "$case_name" in
      closed_state)
        cat > "$json" <<JSON
{"number":40,"state":"CLOSED","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[],"body":""}
JSON
        build_gh_stub "$ghbin" "$json" "$log"
        run_check "$repo" "$ghbin" 40
        assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=40 reason=pr_not_open" \
          "TEST-1522 [$case_name]: expected reason=pr_not_open, got: $OUT"
        ;;
      draft)
        cat > "$json" <<JSON
{"number":40,"state":"OPEN","isDraft":true,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[],"body":""}
JSON
        build_gh_stub "$ghbin" "$json" "$log"
        run_check "$repo" "$ghbin" 40
        assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=40 reason=pr_not_open" \
          "TEST-1522 [$case_name]: expected reason=pr_not_open, got: $OUT"
        ;;
      gh_exits_nonzero)
        mkdir -p "$ghbin"
        cat > "$ghbin/gh" <<STUBEOF
#!/usr/bin/env bash
{ printf 'ARGS:'; for a in "\$@"; do printf ' %s' "\$a"; done; printf '\n'; } >> "$log"
exit 1
STUBEOF
        chmod +x "$ghbin/gh"
        run_check "$repo" "$ghbin" 40
        assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=40 reason=api_unavailable" \
          "TEST-1522 [$case_name]: expected reason=api_unavailable, got: $OUT"
        ;;
      gh_absent)
        mkdir -p "$ghbin"
        run_check "$repo" "$ghbin" 40
        assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=40 reason=api_unavailable" \
          "TEST-1522 [$case_name]: expected reason=api_unavailable with no gh on PATH, got: $OUT"
        ;;
      bad_base_oid)
        cat > "$json" <<JSON
{"number":40,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","headRefOid":"$head","reviews":[],"statusCheckRollup":[],"body":""}
JSON
        build_gh_stub "$ghbin" "$json" "$log"
        run_check "$repo" "$ghbin" 40
        assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=40 reason=base_unavailable" \
          "TEST-1522 [$case_name]: expected reason=base_unavailable with an unresolvable baseRefOid, got: $OUT"
        ;;
    esac
    [[ "$RC" -eq 3 ]] || log_fail "TEST-1522 [$case_name]: expected exit 3, got $RC: $OUT"
  done

  log_pass "TEST-1522: CLOSED/draft give pr_not_open, a failing or absent gh gives api_unavailable, and an unresolvable baseRefOid gives base_unavailable, every case exit 3"
}

# --- TEST-1523 (Spec-AC-16) --------------------------------------------------
test_1523_gh_argv_only_pr_view() {
  log_info "TEST-1523: across repeated --check calls (allowed and denied), plus --classify and --validate, every logged gh invocation on the stub's shared log is a 'pr view' call"
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
  - id: lane-1523
    decision_ref: test1523-ride@2026-10-03T21:00:00Z
    decision_match: "MERGE LANE test1523"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    max_ceremony: 3
    marker: AAI_ARGV1523_MERGE
YAML
  cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1523-ride","ts":"2026-10-03T21:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1523 approved"}
JSONL
  echo "base doc" > "$repo/docs/base.md"
  commit_all "$repo" "base"
  local base; base="$(head_sha "$repo")"
  echo "a docs change" > "$repo/docs/changed.md"
  commit_all "$repo" "head"
  local head; head="$(head_sha "$repo")"
  write_sweep_record "$repo" 50
  write_sweep_record "$repo" 51

  local ghbin="$TEST_DIR/gh-bin" log="$TEST_DIR/gh-argv.log"
  local json_ok="$TEST_DIR/pr-ok.json" json_closed="$TEST_DIR/pr-closed.json"
  cat > "$json_ok" <<JSON
{"number":50,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}],"body":""}
JSON
  build_gh_stub "$ghbin" "$json_ok" "$log"
  run_check "$repo" "$ghbin" 50
  assert_payload_has_line "$OUT" "MERGE-POLICY allowed pr=50 lane=lane-1523 marker=AAI_ARGV1523_MERGE decision_ref=test1523-ride@2026-10-03T21:00:00Z merge_reaches=nothing" \
    "TEST-1523: expected the first call to be allowed, got: $OUT"
  [[ "$RC" -eq 0 ]] || log_fail "TEST-1523: expected exit 0 on the first call, got $RC: $OUT"

  cat > "$json_closed" <<JSON
{"number":51,"state":"CLOSED","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[],"body":""}
JSON
  build_gh_stub "$ghbin" "$json_closed" "$log"
  run_check "$repo" "$ghbin" 51
  assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=51 reason=pr_not_open" \
    "TEST-1523: expected the second call to be denied pr_not_open, got: $OUT"
  [[ "$RC" -eq 3 ]] || log_fail "TEST-1523: expected exit 3 on the second call, got $RC: $OUT"

  # --classify and --validate must never spawn gh at all -- they share the
  # same gh-equipped PATH, so a stray call would still land in the log.
  printf '%s\n' "docs/base.md" \
    | PATH="$ghbin:$PATH" node "$MP" --classify --path "$repo/docs/ai/merge-policy.yaml" --files-from - --repo-root "$repo" >/dev/null 2>&1
  PATH="$ghbin:$PATH" node "$MP" --validate --repo-root "$repo" >/dev/null 2>&1

  local log_content="" bad_line=""
  if [[ -f "$log" ]]; then
    log_content="$(cat "$log")"
  fi
  [[ -n "$log_content" ]] || log_fail "TEST-1523: expected at least one logged gh invocation (positive control), got none"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$line" in
      "ARGS: pr view "*) : ;;
      *) bad_line="$line" ;;
    esac
  done <<< "$log_content"
  [[ -z "$bad_line" ]] || log_fail "TEST-1523: found a gh invocation that was not 'pr view': $bad_line"

  log_pass "TEST-1523: every gh invocation this evaluator makes, across allowed and denied --check calls plus --classify/--validate, starts with 'pr view'"
}

# --- TEST-1524 (Spec-AC-17) --------------------------------------------------
test_1524_output_contract() {
  log_info "TEST-1524: two satisfiable lanes -- the allowed line names the first in file order; reordering the file names the other; three failing lanes print no_lane_matched plus exactly one lane=.. line per lane"
  mk
  local repo="$TEST_DIR/repo"
  new_repo "$repo"
  mkdir -p "$repo/docs/ai" "$repo/docs"

  local lane_a='  - id: lane-a
    decision_ref: test1524-a@2026-10-03T22:00:00Z
    decision_match: "MERGE LANE test1524 a"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    max_ceremony: 3
    marker: AAI_ORDERA1524_MERGE'
  local lane_b='  - id: lane-b
    decision_ref: test1524-b@2026-10-03T22:00:00Z
    decision_match: "MERGE LANE test1524 b"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    max_ceremony: 3
    marker: AAI_ORDERB1524_MERGE'

  cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1524-a","ts":"2026-10-03T22:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1524 a approved"}
{"type":"hitl_decision","ref_id":"test1524-b","ts":"2026-10-03T22:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1524 b approved"}
JSONL

  local case_name
  for case_name in a_first b_first three_failing; do
    local policy_lanes
    case "$case_name" in
      a_first) policy_lanes="$lane_a
$lane_b" ;;
      b_first) policy_lanes="$lane_b
$lane_a" ;;
      three_failing) policy_lanes="" ;;
    esac

    {
      echo "version: 1"
      echo "kinds:"
      echo "  - id: docs"
      echo "    globs: [\"docs/**\"]"
      if [[ "$case_name" == "three_failing" ]]; then
        echo "  - id: other"
        echo "    globs: [\"other/**\"]"
      fi
      echo "lanes:"
      if [[ "$case_name" == "three_failing" ]]; then
        echo "  - id: lane-x
    decision_ref: test1524-x@2026-10-03T22:00:00Z
    decision_match: \"MERGE LANE test1524 x\"
    signed_by: owner-login
    kinds: [other]
    merge_reaches: nothing
    max_ceremony: 3
    marker: AAI_ORDERX1524_MERGE"
        echo "  - id: lane-y
    decision_ref: test1524-y@2026-10-03T22:00:00Z
    decision_match: \"MERGE LANE test1524 y\"
    signed_by: owner-login
    kinds: [other]
    merge_reaches: nothing
    max_ceremony: 3
    marker: AAI_ORDERY1524_MERGE"
        echo "  - id: lane-z
    decision_ref: test1524-z@2026-10-03T22:00:00Z
    decision_match: \"MERGE LANE test1524 z\"
    signed_by: owner-login
    kinds: [other]
    merge_reaches: nothing
    max_ceremony: 3
    marker: AAI_ORDERZ1524_MERGE"
      else
        printf '%s\n' "$policy_lanes"
      fi
    } > "$repo/docs/ai/merge-policy.yaml"

    if [[ "$case_name" == "three_failing" ]]; then
      cat >> "$repo/docs/ai/merge-policy.yaml" <<'YAML'
architecture: []
YAML
      cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1524-x","ts":"2026-10-03T22:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1524 x approved"}
{"type":"hitl_decision","ref_id":"test1524-y","ts":"2026-10-03T22:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1524 y approved"}
{"type":"hitl_decision","ref_id":"test1524-z","ts":"2026-10-03T22:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1524 z approved"}
JSONL
    fi

    echo "base doc ($case_name)" > "$repo/docs/base-$case_name.md"
    commit_all "$repo" "base ($case_name)"
    local base; base="$(head_sha "$repo")"
    echo "a docs change ($case_name)" > "$repo/docs/changed-$case_name.md"
    commit_all "$repo" "head ($case_name)"
    local head; head="$(head_sha "$repo")"
    local pr
    case "$case_name" in
      a_first) pr=60 ;;
      b_first) pr=61 ;;
      three_failing) pr=62 ;;
    esac
    write_sweep_record "$repo" "$pr"

    local ghbin="$TEST_DIR/gh-bin-$case_name" json="$TEST_DIR/pr-$case_name.json" log="$TEST_DIR/gh-$case_name.log"
    cat > "$json" <<JSON
{"number":$pr,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}],"body":""}
JSON
    build_gh_stub "$ghbin" "$json" "$log"
    run_check "$repo" "$ghbin" "$pr"

    case "$case_name" in
      a_first)
        assert_payload_has_line "$OUT" "MERGE-POLICY allowed pr=$pr lane=lane-a marker=AAI_ORDERA1524_MERGE decision_ref=test1524-a@2026-10-03T22:00:00Z merge_reaches=nothing" \
          "TEST-1524 [$case_name]: expected the FIRST lane in file order to win, got: $OUT"
        [[ "$RC" -eq 0 ]] || log_fail "TEST-1524 [$case_name]: expected exit 0, got $RC: $OUT"
        ;;
      b_first)
        assert_payload_has_line "$OUT" "MERGE-POLICY allowed pr=$pr lane=lane-b marker=AAI_ORDERB1524_MERGE decision_ref=test1524-b@2026-10-03T22:00:00Z merge_reaches=nothing" \
          "TEST-1524 [$case_name]: expected the REORDERED first lane to win, got: $OUT"
        [[ "$RC" -eq 0 ]] || log_fail "TEST-1524 [$case_name]: expected exit 0, got $RC: $OUT"
        ;;
      three_failing)
        assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=$pr reason=no_lane_matched" \
          "TEST-1524 [$case_name]: expected no_lane_matched, got: $OUT"
        local lane_id
        for lane_id in lane-x lane-y lane-z; do
          assert_payload_has_line "$OUT" "lane=$lane_id reason=kind_not_in_lane" \
            "TEST-1524 [$case_name]: expected exactly one lane line for $lane_id, got: $OUT"
        done
        local line_count=0 out_line
        while IFS= read -r out_line; do
          case "$out_line" in
            lane=*) line_count=$((line_count + 1)) ;;
          esac
        done <<< "$OUT"
        [[ "$line_count" -eq 3 ]] || log_fail "TEST-1524 [$case_name]: expected exactly 3 lane= lines (one per lane), got $line_count: $OUT"
        [[ "$RC" -eq 3 ]] || log_fail "TEST-1524 [$case_name]: expected exit 3, got $RC: $OUT"
        ;;
    esac
  done

  log_pass "TEST-1524: the first lane in file order whose conditions hold wins, in both orderings; a fully denied PR prints no_lane_matched plus exactly one lane=.. reason=.. line per lane evaluated"
}

# --- TEST-1525 (Spec-AC-18) ---------------------------------------------------
# This repository's OWN docs/ai/merge-policy.yaml, read live (never a copy --
# the Evidence contract requires this test run against the real files), must
# validate against the real docs/ai/decisions.jsonl and carry the exact field
# values Spec-AC-18 names for the migrated internal-standing lane.
test_1525_live_policy_validates() {
  log_info "TEST-1525: the live docs/ai/merge-policy.yaml validates against the live decisions ledger (exit 0), and its one lane carries every field value Spec-AC-18 names"
  local out rc
  out="$(node "$MP" --validate --repo-root "$PROJECT_ROOT" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -ne 0 || "$out" != "VALID lanes=1" ]]; then
    log_info "TEST-1525: expected 'VALID lanes=1' exit 0, got rc=$rc: $out"
    log_fail "TEST-1525 live merge-policy.yaml validates"
    return
  fi

  local policy="$PROJECT_ROOT/docs/ai/merge-policy.yaml"
  local ok=1
  grep -qF "id: internal-standing" "$policy" \
    || { log_info "TEST-1525: missing lane id internal-standing"; ok=0; }
  grep -qF "decision_ref: wave-2-roadmap@2026-09-12T19:56:52Z" "$policy" \
    || { log_info "TEST-1525: missing decision_ref wave-2-roadmap@2026-09-12T19:56:52Z"; ok=0; }
  grep -qF 'decision_match: "STANDING MERGE AUTHORIZATION"' "$policy" \
    || { log_info "TEST-1525: missing decision_match STANDING MERGE AUTHORIZATION"; ok=0; }
  grep -qF "merge_reaches: nothing" "$policy" \
    || { log_info "TEST-1525: missing merge_reaches nothing"; ok=0; }
  grep -qF "max_ceremony" "$policy" \
    && { log_info "TEST-1525: max_ceremony must be absent (implicit DEFAULT_MAX_CEREMONY=2)"; ok=0; }
  grep -qF "validation_pass: true" "$policy" \
    || { log_info "TEST-1525: missing requires.validation_pass true"; ok=0; }
  grep -qF "review_pass: true" "$policy" \
    || { log_info "TEST-1525: missing requires.review_pass true"; ok=0; }
  grep -qF 'pr_body_contains: "Residual"' "$policy" \
    || { log_info "TEST-1525: missing requires.pr_body_contains Residual"; ok=0; }
  grep -qF "intake_types: [change, issue, techdebt, hotfix]" "$policy" \
    || { log_info "TEST-1525: missing requires.intake_types [change, issue, techdebt, hotfix]"; ok=0; }
  grep -qF "exclude_roadmap_capability: true" "$policy" \
    || { log_info "TEST-1525: missing requires.exclude_roadmap_capability true"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-1525: the live policy validates and internal-standing carries every Spec-AC-18 field value" \
    || log_fail "TEST-1525 live internal-standing field values"
}

# --- TEST-1526 (Spec-AC-18) ---------------------------------------------------
# A scratch base commit per case carries a COPY of this repository's own
# live docs/ai/merge-policy.yaml and the live wave-2-roadmap hitl_decision
# records (copied verbatim via grep from the real docs/ai/decisions.jsonl --
# TEST-1525 already pins that these live bytes validate). A conforming
# internal ride is allowed; five more each violate exactly one condition of
# the migrated internal-standing lane and deny with their own reason --
# including the two HITL-2 tightenings (an architecture-glob hooks path, and
# the GUARD_PATHS-backed policy_touched case is already covered by
# TEST-1506/1507, so this row exercises roadmap_capability/ceremony_exceeds/
# validation_not_pass/pr_body_missing/architecture instead).
test_1526_live_policy_fixture() {
  log_info "TEST-1526: a fixture base carrying the live merge-policy.yaml and the live wave-2-roadmap records -- a conforming internal ride is allowed, and a capability ride, a ceremony-3 ride, a validation fail, a body without Residual and a hooks-path change each deny with their own reason"
  local case_name
  for case_name in allowed capability ceremony3 validation_fail body_missing hooks_path; do
    mk
    local repo="$TEST_DIR/repo"
    new_repo "$repo"
    mkdir -p "$repo/docs/ai" "$repo/docs" "$repo/hooks"
    cp "$PROJECT_ROOT/docs/ai/merge-policy.yaml" "$repo/docs/ai/merge-policy.yaml"
    grep -F 'wave-2-roadmap' "$PROJECT_ROOT/docs/ai/decisions.jsonl" > "$repo/docs/ai/decisions.jsonl"
    local nrec; nrec="$(wc -l < "$repo/docs/ai/decisions.jsonl" | tr -d ' ')"
    if [[ "$nrec" -lt 3 ]]; then
      log_fail "TEST-1526 [$case_name]: fixture precondition failed -- expected >=3 live wave-2-roadmap records copied from the real ledger, got $nrec"
      continue
    fi

    if [[ "$case_name" == "capability" ]]; then
      cat > "$repo/docs/ai/roadmap.yaml" <<'YAML'
pairs:
  - capability: ride-1526
    status: planned
YAML
    fi

    echo "base doc" > "$repo/docs/base.md"
    commit_all "$repo" "base ($case_name)"
    local base; base="$(head_sha "$repo")"

    if [[ "$case_name" == "hooks_path" ]]; then
      echo "#!/bin/sh" > "$repo/hooks/pre-commit"
    else
      echo "a docs change ($case_name)" > "$repo/docs/changed-$case_name.md"
    fi
    commit_all "$repo" "head ($case_name)"
    local head; head="$(head_sha "$repo")"
    write_sweep_record "$repo" 70

    local body="plan carries a Residual risk"
    [[ "$case_name" == "body_missing" ]] && body="no matching literal here"
    write_intake "$TEST_DIR/intake.md" "ride-1526" "change"
    local vstatus="pass"
    [[ "$case_name" == "validation_fail" ]] && vstatus="fail"
    write_state "$TEST_DIR/STATE.yaml" "$vstatus" "pass"

    local ghbin="$TEST_DIR/gh-bin" json="$TEST_DIR/pr.json" log="$TEST_DIR/gh.log"
    cat > "$json" <<JSON
{"number":70,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}],"body":"$body"}
JSON
    build_gh_stub "$ghbin" "$json" "$log"

    # bash-3.2 trap: an empty `local arr=()` expanded as "${arr[@]}" under
    # `set -u` is "unbound variable" on this platform's /bin/bash (fixed only
    # in bash 4.4+) -- branch on the one optional flag directly instead of
    # building an args array (docs/knowledge/LEARNED.md bash-3.2 traps).
    if [[ "$case_name" == "ceremony3" ]]; then
      cat > "$TEST_DIR/spec3.md" <<'MD'
---
id: spec-test1526
type: spec
ceremony_level: 3
---

# Spec
MD
      run_check "$repo" "$ghbin" 70 --intake "$TEST_DIR/intake.md" --state "$TEST_DIR/STATE.yaml" --spec "$TEST_DIR/spec3.md"
    else
      run_check "$repo" "$ghbin" 70 --intake "$TEST_DIR/intake.md" --state "$TEST_DIR/STATE.yaml"
    fi

    case "$case_name" in
      allowed)
        assert_payload_has_line "$OUT" "MERGE-POLICY allowed pr=70 lane=internal-standing marker=AAI_INTERNAL_STANDING_MERGE decision_ref=wave-2-roadmap@2026-09-12T19:56:52Z merge_reaches=nothing" \
          "TEST-1526 [$case_name]: expected the conforming internal ride allowed, got: $OUT"
        [[ "$RC" -eq 0 ]] || log_fail "TEST-1526 [$case_name]: expected exit 0, got $RC: $OUT"
        ;;
      capability)
        assert_payload_has_line "$OUT" "lane=internal-standing reason=roadmap_capability" \
          "TEST-1526 [$case_name]: expected reason=roadmap_capability, got: $OUT"
        [[ "$RC" -eq 3 ]] || log_fail "TEST-1526 [$case_name]: expected exit 3, got $RC: $OUT"
        ;;
      ceremony3)
        assert_payload_has_line "$OUT" "lane=internal-standing reason=ceremony_exceeds" \
          "TEST-1526 [$case_name]: expected reason=ceremony_exceeds, got: $OUT"
        [[ "$RC" -eq 3 ]] || log_fail "TEST-1526 [$case_name]: expected exit 3, got $RC: $OUT"
        ;;
      validation_fail)
        assert_payload_has_line "$OUT" "lane=internal-standing reason=validation_not_pass" \
          "TEST-1526 [$case_name]: expected reason=validation_not_pass, got: $OUT"
        [[ "$RC" -eq 3 ]] || log_fail "TEST-1526 [$case_name]: expected exit 3, got $RC: $OUT"
        ;;
      body_missing)
        assert_payload_has_line "$OUT" "lane=internal-standing reason=pr_body_missing" \
          "TEST-1526 [$case_name]: expected reason=pr_body_missing, got: $OUT"
        [[ "$RC" -eq 3 ]] || log_fail "TEST-1526 [$case_name]: expected exit 3, got $RC: $OUT"
        ;;
      hooks_path)
        assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=70 reason=architecture path=hooks/pre-commit" \
          "TEST-1526 [$case_name]: expected reason=architecture naming hooks/pre-commit, got: $OUT"
        [[ "$RC" -eq 3 ]] || log_fail "TEST-1526 [$case_name]: expected exit 3, got $RC: $OUT"
        ;;
    esac
  done

  log_pass "TEST-1526: the live internal-standing lane allows a conforming internal ride and denies a capability ride, a ceremony-3 ride, a validation fail, a body without Residual and a hooks-path change, each with its own reason"
}

# --- TEST-1527 (Spec-AC-19) ---------------------------------------------------
# One path now: SKILL_PR.prompt.md step 6 no longer carries the STANDING
# AUTHORIZATION prose exception or the wave-2-roadmap ref literal, and
# instructs merge-policy.mjs --check --pr with the lane marker and
# decision_ref citation; AGENTS.md closeout and SKILL_SHIP step 6 name
# merge-policy.mjs instead of standing authorization; the hooks TEST-012
# literals (AAI_OPERATOR_MERGE, guardrail, not a security boundary, NEVER
# merge, operator) all survive unchanged.
test_1527_prompts_defer_to_evaluator() {
  log_info "TEST-1527: SKILL_PR/AGENTS.md/SKILL_SHIP defer to merge-policy.mjs; the old STANDING AUTHORIZATION prose and wave-2-roadmap ref are gone; the hooks TEST-012 literals survive"
  local skill_pr="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
  local agents="$PROJECT_ROOT/.aai/AGENTS.md"
  local skill_ship="$PROJECT_ROOT/.aai/SKILL_SHIP.prompt.md"
  local ok=1 n

  n="$(grep -cF 'wave-2-roadmap' "$skill_pr")"
  [[ "$n" -eq 0 ]] || { log_info "TEST-1527: SKILL_PR.prompt.md still names ref wave-2-roadmap ($n occurrences)"; ok=0; }
  n="$(grep -cF 'STANDING AUTHORIZATION' "$skill_pr")"
  [[ "$n" -eq 0 ]] || { log_info "TEST-1527: SKILL_PR.prompt.md still carries the STANDING AUTHORIZATION paragraph ($n occurrences)"; ok=0; }

  grep -qF 'merge-policy.mjs --check --pr' "$skill_pr" \
    || { log_info "TEST-1527: SKILL_PR.prompt.md step 6 does not instruct merge-policy.mjs --check --pr"; ok=0; }
  grep -qiF 'marker' "$skill_pr" \
    || { log_info "TEST-1527: SKILL_PR.prompt.md step 6 does not mention the lane marker"; ok=0; }
  grep -qF 'decision_ref' "$skill_pr" \
    || { log_info "TEST-1527: SKILL_PR.prompt.md step 6 does not cite decision_ref"; ok=0; }

  grep -qF 'merge-policy.mjs' "$agents" \
    || { log_info "TEST-1527: AGENTS.md closeout does not name merge-policy.mjs"; ok=0; }
  grep -qF 'merge-policy.mjs' "$skill_ship" \
    || { log_info "TEST-1527: SKILL_SHIP.prompt.md step 6 does not name merge-policy.mjs"; ok=0; }

  # The hooks TEST-012 literals (test-aai-hooks-overlay.sh test_012_skill_pr_marker)
  grep -qF 'AAI_OPERATOR_MERGE' "$skill_pr" \
    || { log_info "TEST-1527: AAI_OPERATOR_MERGE no longer documented in SKILL_PR.prompt.md"; ok=0; }
  grep -qi 'guardrail' "$skill_pr" \
    || { log_info "TEST-1527: guardrail framing missing from SKILL_PR.prompt.md"; ok=0; }
  grep -qi 'not a security boundary' "$skill_pr" \
    || { log_info "TEST-1527: not-a-security-boundary honesty missing from SKILL_PR.prompt.md"; ok=0; }
  grep -qF 'NEVER merge' "$skill_pr" \
    || { log_info "TEST-1527: the NEVER-merge boundary text no longer survives in SKILL_PR.prompt.md"; ok=0; }
  grep -qi 'operator' "$skill_pr" \
    || { log_info "TEST-1527: operator wording missing from SKILL_PR.prompt.md"; ok=0; }

  [[ $ok -eq 1 ]] && log_pass "TEST-1527: SKILL_PR/AGENTS.md/SKILL_SHIP defer to merge-policy.mjs; TEST-012 literals intact" \
    || log_fail "TEST-1527 prompts defer to the evaluator"
}

# --- TEST-1530 (Spec-AC-22) --------------------------------------------------
test_1530_companion_wiring() {
  log_info "TEST-1530: PROFILES.yaml core entry, DOCS_AI_CANON.list entry, suite-map maps the evaluator; select-suites selects aai-merge-policy with no FULL_RUN; layer-profiles suite green"
  local ok=1

  grep -qF '.aai/scripts/merge-policy.mjs' "$PROJECT_ROOT/.aai/system/PROFILES.yaml" \
    || { log_info "TEST-1530: .aai/system/PROFILES.yaml does not classify .aai/scripts/merge-policy.mjs"; ok=0; }
  grep -qxF 'merge-policy.yaml' "$PROJECT_ROOT/.aai/system/DOCS_AI_CANON.list" \
    || { log_info "TEST-1530: .aai/system/DOCS_AI_CANON.list is missing the exact line 'merge-policy.yaml'"; ok=0; }
  grep -qF '.aai/scripts/merge-policy.mjs' "$PROJECT_ROOT/tests/skills/suite-map.yaml" \
    || { log_info "TEST-1530: tests/skills/suite-map.yaml does not map .aai/scripts/merge-policy.mjs to a suite"; ok=0; }

  local files_list out
  files_list="$(mktemp "${TMPDIR:-/tmp}/aai-merge-policy-files.XXXXXX")"
  FIXTURES+=("$files_list")
  printf '%s\n' ".aai/scripts/merge-policy.mjs" > "$files_list"
  out="$(node "$PROJECT_ROOT/.aai/scripts/select-suites.mjs" --files-from "$files_list" 2>&1)"
  assert_payload_not_contains "$out" "FULL_RUN" \
    "TEST-1530: select-suites.mjs fell back to FULL_RUN for a change scoped to merge-policy.mjs" || ok=0
  assert_payload_line_matches "$out" '^SELECTED aai-merge-policy ' \
    "TEST-1530: select-suites.mjs did not select aai-merge-policy" || ok=0

  if ! bash "$PROJECT_ROOT/tests/skills/test-aai-layer-profiles.sh" >/dev/null 2>&1; then
    log_info "TEST-1530: tests/skills/test-aai-layer-profiles.sh failed"
    ok=0
  fi

  [[ $ok -eq 1 ]] && log_pass "TEST-1530: PROFILES/DOCS_AI_CANON/suite-map wiring complete; select-suites selects aai-merge-policy with no FULL_RUN; layer-profiles suite green" \
    || log_fail "TEST-1530 companion wiring (PROFILES/canon/suite-map)"
}

# --- TEST-1532 (Spec-AC-23) --------------------------------------------------
test_1532_changelog_unreleased_entry() {
  log_info "TEST-1532: CHANGELOG.md carries a '## [unreleased] — ' heading declaring the merge-policy breaking change"
  local changelog="$PROJECT_ROOT/CHANGELOG.md"
  if [[ ! -f "$changelog" ]]; then
    log_fail "TEST-1532 $changelog does not exist"
    return
  fi
  local ok=1 body
  # Concatenate the body of every '## [unreleased] — ' heading (up to the
  # next '## ' heading), pipe-free single read of one bounded file.
  body="$(awk '
    /^## \[unreleased\] — / { capture=1; next }
    /^## / { capture=0 }
    capture { print }
  ' "$changelog")"
  if [[ -z "$body" ]]; then
    log_fail "TEST-1532: no '## [unreleased] — ' heading found in CHANGELOG.md"
    return
  fi
  assert_payload_contains "$body" "merge-policy.yaml" \
    "TEST-1532: unreleased entry body does not name docs/ai/merge-policy.yaml" || ok=0
  assert_payload_contains "$body" "merge-policy.mjs --validate" \
    "TEST-1532: unreleased entry body does not name merge-policy.mjs --validate" || ok=0
  assert_payload_contains_i "$body" "standing" \
    "TEST-1532: unreleased entry body does not name the standing authorization removal" || ok=0

  [[ $ok -eq 1 ]] && log_pass "TEST-1532: CHANGELOG.md declares the merge-policy.yaml breaking change and its migration step" \
    || log_fail "TEST-1532 CHANGELOG unreleased heading"
}

# --- TEST-1533 (Spec-AC-18/11, validation-round1 B1) ------------------------
# P8's "defaulting to STATE current_focus": the documented no-flags
# invocation (`merge-policy.mjs --check --pr <n>`, SKILL_PR step 6 / the hook
# lane path with no AAI_SWEEP_* set) must resolve spec/intake from STATE
# current_focus.spec_path/primary_path, the same way lane-gate.mjs's own
# resolveDefaultSpecFromState does, and allow a qualifying internal-standing
# ride on that default alone.
test_1533_default_ride_inputs_from_state() {
  log_info "TEST-1533: --check --pr <n> with NO --spec/--intake/--state resolves ride inputs from STATE current_focus and allows a qualifying internal-standing ride"
  mk
  local repo="$TEST_DIR/repo"
  new_repo "$repo"
  mkdir -p "$repo/docs/ai" "$repo/docs"
  cp "$PROJECT_ROOT/docs/ai/merge-policy.yaml" "$repo/docs/ai/merge-policy.yaml"
  grep -F 'wave-2-roadmap' "$PROJECT_ROOT/docs/ai/decisions.jsonl" > "$repo/docs/ai/decisions.jsonl"
  local nrec; nrec="$(wc -l < "$repo/docs/ai/decisions.jsonl" | tr -d ' ')"
  if [[ "$nrec" -lt 3 ]]; then
    log_fail "TEST-1533: fixture precondition failed -- expected >=3 live wave-2-roadmap records, got $nrec"
    return
  fi
  write_intake "$repo/docs/intake-1533.md" "ride-1533" "change"
  cat > "$repo/docs/spec-1533.md" <<'MD'
---
id: spec-test1533
type: spec
ceremony_level: 2
---

# Spec
MD
  echo "base doc" > "$repo/docs/base.md"
  commit_all "$repo" "base"
  local base; base="$(head_sha "$repo")"
  echo "a docs change" > "$repo/docs/changed-1533.md"
  commit_all "$repo" "head"
  local head; head="$(head_sha "$repo")"
  write_sweep_record "$repo" 70

  # STATE.yaml at the DEFAULT path (no --state given): current_focus names
  # the spec/intake this evaluator must resolve on its own, same as
  # lane-gate.mjs's own resolveDefaultSpecFromState reads.
  cat > "$repo/docs/ai/STATE.yaml" <<'YAML'
current_focus:
  type: intake_change
  ref_id: ride-1533
  primary_path: docs/intake-1533.md
  spec_path: docs/spec-1533.md
last_validation:
  status: pass
code_review:
  status: pass
YAML

  local ghbin="$TEST_DIR/gh-bin" json="$TEST_DIR/pr.json" log="$TEST_DIR/gh.log"
  cat > "$json" <<JSON
{"number":70,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}],"body":"plan carries a Residual risk"}
JSON
  build_gh_stub "$ghbin" "$json" "$log"

  # The documented no-flags invocation (SKILL_PR step 6 / the hook lane path
  # with no AAI_SWEEP_* in its environment), with --debug-inputs to also
  # prove the resolved inputs themselves (ceremony/intake_type/ref), not only
  # the final verdict.
  run_check "$repo" "$ghbin" 70 --debug-inputs
  assert_payload_has_line "$OUT" "ceremony=2 intake_type=change ref=ride-1533" \
    "TEST-1533: expected ceremony=2 intake_type=change ref=ride-1533 resolved from STATE current_focus with no flags, got: $OUT"
  assert_payload_has_line "$OUT" "MERGE-POLICY allowed pr=70 lane=internal-standing marker=AAI_INTERNAL_STANDING_MERGE decision_ref=wave-2-roadmap@2026-09-12T19:56:52Z merge_reaches=nothing" \
    "TEST-1533: expected the conforming internal ride allowed with NO flags, got: $OUT"
  [[ "$RC" -eq 0 ]] || log_fail "TEST-1533: expected exit 0 with no flags, got $RC: $OUT"

  log_pass "TEST-1533: merge-policy.mjs --check --pr <n> with no ride flags defaults to STATE current_focus and allows a qualifying internal-standing ride"
}

# --- TEST-1534 (validation-round1 B2) ---------------------------------------
# Boolean-typed scalars accept ONLY the canonical true/false token (bare or
# quoted); a case variant, a yes/no word, or any other value is a
# parse_error -- never a value that silently reads as "not true" while the
# author intended "true" (the quoted-production_on_merge/opt-in bypass the
# validator found).
test_1534_boolean_scalar_strictness() {
  log_info "TEST-1534: boolean-typed scalars accept only true/false (bare or quoted); True/yes/publik-shaped non-canonical values are parse_error, never a silently-false reroute"
  local case_name policy_body expect_ok
  for case_name in quoted_true_production_on_merge bad_true_case bad_yes_word quoted_false_ok; do
    mk
    case "$case_name" in
      quoted_true_production_on_merge)
        policy_body=$'version: 1\ndeploy:\n  preview: none\n  production_on_merge: "true"\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1534-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1534 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: production\n    allow_public_side_effect: true\n    marker: AAI_T1534A_MERGE\n    requester_logins: [requester-login]\n'
        expect_ok=1
        ;;
      bad_true_case)
        policy_body=$'version: 1\ndeploy:\n  preview: none\n  production_on_merge: True\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1534-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1534 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1534A_MERGE\n'
        expect_ok=0
        ;;
      bad_yes_word)
        policy_body=$'version: 1\ndeploy:\n  preview: none\n  production_on_merge: yes\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1534-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1534 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1534A_MERGE\n'
        expect_ok=0
        ;;
      quoted_false_ok)
        policy_body=$'version: 1\ndeploy:\n  preview: none\n  production_on_merge: "false"\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1534-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1534 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1534A_MERGE\n'
        expect_ok=1
        ;;
    esac
    printf '%s' "$policy_body" > "$TEST_DIR/policy-$case_name.yaml"
    cat > "$TEST_DIR/decisions-$case_name.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"t1534-a","ts":"2026-10-04T00:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE t1534 a approved"}
JSONL
    local out rc
    # --validate reads decisions.jsonl from --repo-root's own docs/ai/ path;
    # point --repo-root at a scratch dir carrying exactly that layout.
    mkdir -p "$TEST_DIR/root-$case_name/docs/ai"
    cp "$TEST_DIR/policy-$case_name.yaml" "$TEST_DIR/root-$case_name/docs/ai/merge-policy.yaml"
    cp "$TEST_DIR/decisions-$case_name.jsonl" "$TEST_DIR/root-$case_name/docs/ai/decisions.jsonl"
    out="$(node "$MP" --validate --repo-root "$TEST_DIR/root-$case_name" 2>&1)" && rc=0 || rc=$?
    if [[ "$expect_ok" -eq 1 ]]; then
      [[ "$rc" -eq 0 ]] || log_fail "TEST-1534 [$case_name]: expected VALID (exit 0), got $rc: $out"
      assert_payload_has_line "$out" "VALID lanes=1" "TEST-1534 [$case_name]: expected VALID lanes=1, got: $out"
    else
      [[ "$rc" -eq 1 ]] || log_fail "TEST-1534 [$case_name]: expected INVALID (exit 1), got $rc: $out"
      assert_payload_contains "$out" "code=parse_error" "TEST-1534 [$case_name]: expected parse_error, got: $out"
    fi
  done

  log_pass "TEST-1534: boolean fields accept only true/false (quoted forms normalized, not rejected); any other value (True, yes) is parse_error, never a silent reroute"
}

# --- TEST-1535 (validation-round1 B2) ---------------------------------------
# The two closed-set enums P1 defines (deploy.preview, lane.merge_reaches)
# reject any out-of-set value as parse_error -- never a value that silently
# satisfies (or silently fails to satisfy) a later string comparison such as
# `deploy.preview === 'public'` (the PUBLIC/publik opt-in bypass).
test_1535_enum_rejection() {
  log_info "TEST-1535: deploy.preview and merge_reaches reject out-of-set values as parse_error (PUBLIC/publik/typo'd merge_reaches)"
  local case_name policy_body
  for case_name in preview_uppercase preview_typo merge_reaches_typo; do
    mk
    case "$case_name" in
      preview_uppercase)
        policy_body=$'version: 1\ndeploy:\n  preview: PUBLIC\n  production_on_merge: false\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1535-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1535 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: preview\n    marker: AAI_T1535A_MERGE\n'
        ;;
      preview_typo)
        policy_body=$'version: 1\ndeploy:\n  preview: publik\n  production_on_merge: false\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1535-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1535 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: preview\n    marker: AAI_T1535A_MERGE\n'
        ;;
      merge_reaches_typo)
        policy_body=$'version: 1\ndeploy:\n  preview: none\n  production_on_merge: false\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1535-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1535 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: Nothing\n    marker: AAI_T1535A_MERGE\n'
        ;;
    esac
    mkdir -p "$TEST_DIR/root-$case_name/docs/ai"
    printf '%s' "$policy_body" > "$TEST_DIR/root-$case_name/docs/ai/merge-policy.yaml"
    local out rc
    out="$(node "$MP" --validate --repo-root "$TEST_DIR/root-$case_name" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -eq 1 ]] || log_fail "TEST-1535 [$case_name]: expected INVALID (exit 1), got $rc: $out"
    assert_payload_contains "$out" "code=parse_error" "TEST-1535 [$case_name]: expected parse_error, got: $out"
  done

  log_pass "TEST-1535: an out-of-enum deploy.preview or merge_reaches value is parse_error, never silently misread as neither member of its set"
}

# --- TEST-1536 (validation-round1 B2) ---------------------------------------
# A repeated `requires:` block, or a repeated lane scalar key, is
# duplicate_key invalid -- never last-writer-wins (a second, empty `requires:`
# block silently wiping a first one that carried real conditions).
test_1536_duplicate_key() {
  log_info "TEST-1536: a repeated requires: block or a repeated lane key is duplicate_key, not last-writer-wins"
  local case_name policy_body
  for case_name in duplicate_requires duplicate_lane_key; do
    mk
    case "$case_name" in
      duplicate_requires)
        policy_body=$'version: 1\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1536-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1536 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1536A_MERGE\n    requires:\n      validation_pass: true\n    requires:\n      pr_body_contains: "x"\n'
        ;;
      duplicate_lane_key)
        policy_body=$'version: 1\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1536-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1536 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1536A_MERGE\n    marker: AAI_T1536B_MERGE\n'
        ;;
    esac
    mkdir -p "$TEST_DIR/root-$case_name/docs/ai"
    printf '%s' "$policy_body" > "$TEST_DIR/root-$case_name/docs/ai/merge-policy.yaml"
    local out rc
    out="$(node "$MP" --validate --repo-root "$TEST_DIR/root-$case_name" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -eq 1 ]] || log_fail "TEST-1536 [$case_name]: expected INVALID (exit 1), got $rc: $out"
    assert_payload_contains "$out" "code=duplicate_key" "TEST-1536 [$case_name]: expected duplicate_key, got: $out"
  done

  log_pass "TEST-1536: a repeated requires: block or lane key is duplicate_key invalid, never last-writer-wins"
}

# --- TEST-1537 (validation-round1 B2) ---------------------------------------
# missing_key -- a lane omitting one of its required fields (decision_ref,
# decision_match, signed_by, kinds, merge_reaches, marker) is invalid, rather
# than silently defaulting/normalizing into some other, less legible code.
test_1537_missing_key() {
  log_info "TEST-1537: a lane missing a required field (marker) is missing_key"
  mk
  mkdir -p "$TEST_DIR/root/docs/ai"
  cat > "$TEST_DIR/root/docs/ai/merge-policy.yaml" <<'YAML'
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-a
    decision_ref: t1537-a@2026-10-04T00:00:00Z
    decision_match: "MERGE LANE t1537 a"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
YAML
  local out rc
  out="$(node "$MP" --validate --repo-root "$TEST_DIR/root" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-1537: expected INVALID (exit 1), got $rc: $out"
  assert_payload_contains "$out" "code=missing_key" "TEST-1537: expected missing_key, got: $out"

  log_pass "TEST-1537: a lane with no marker (a required key) is missing_key"
}

# --- TEST-1538 (validation-round1 B2) ---------------------------------------
# bad_ceremony -- an explicitly-written max_ceremony outside the four real
# ceremony levels (0-3) is invalid; max_ceremony is otherwise optional.
test_1538_bad_ceremony() {
  log_info "TEST-1538: an explicitly-written max_ceremony outside 0-3 is bad_ceremony"
  local case_name max_line
  for case_name in non_numeric out_of_range; do
    mk
    mkdir -p "$TEST_DIR/root-$case_name/docs/ai"
    [[ "$case_name" == "non_numeric" ]] && max_line="    max_ceremony: heavy"
    [[ "$case_name" == "out_of_range" ]] && max_line="    max_ceremony: 9"
    cat > "$TEST_DIR/root-$case_name/docs/ai/merge-policy.yaml" <<YAML
version: 1
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-a
    decision_ref: t1538-a@2026-10-04T00:00:00Z
    decision_match: "MERGE LANE t1538 a"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_T1538A_MERGE
$max_line
YAML
    local out rc
    out="$(node "$MP" --validate --repo-root "$TEST_DIR/root-$case_name" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -eq 1 ]] || log_fail "TEST-1538 [$case_name]: expected INVALID (exit 1), got $rc: $out"
    assert_payload_contains "$out" "code=bad_ceremony" "TEST-1538 [$case_name]: expected bad_ceremony, got: $out"
  done

  log_pass "TEST-1538: a non-numeric or out-of-range max_ceremony is bad_ceremony"
}

# --- TEST-1539 (validation-round1 NB-7) -------------------------------------
# `version` is checked: absent is missing_key, present-but-not-1 is
# parse_error -- never silently accepted (the spec's version:1 line is a
# forward-compat guard against a v2 schema this evaluator does not speak).
test_1539_version_checked() {
  log_info "TEST-1539: an absent version is missing_key; a version other than 1 is parse_error"
  mk
  mkdir -p "$TEST_DIR/root-absent/docs/ai"
  cat > "$TEST_DIR/root-absent/docs/ai/merge-policy.yaml" <<'YAML'
kinds:
  - id: docs
    globs: ["docs/**"]
lanes:
  - id: lane-a
    decision_ref: t1539-a@2026-10-04T00:00:00Z
    decision_match: "MERGE LANE t1539 a"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_T1539A_MERGE
YAML
  local out rc
  out="$(node "$MP" --validate --repo-root "$TEST_DIR/root-absent" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-1539 [absent]: expected INVALID (exit 1), got $rc: $out"
  assert_payload_contains "$out" "code=missing_key" "TEST-1539 [absent]: expected missing_key, got: $out"

  mkdir -p "$TEST_DIR/root-v2/docs/ai"
  sed 's/^kinds:/version: 2\nkinds:/' "$TEST_DIR/root-absent/docs/ai/merge-policy.yaml" > "$TEST_DIR/root-v2/docs/ai/merge-policy.yaml"
  out="$(node "$MP" --validate --repo-root "$TEST_DIR/root-v2" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 1 ]] || log_fail "TEST-1539 [v2]: expected INVALID (exit 1), got $rc: $out"
  assert_payload_contains "$out" "code=parse_error" "TEST-1539 [v2]: expected parse_error, got: $out"

  log_pass "TEST-1539: version absent is missing_key; version != 1 is parse_error"
}

# --- TEST-1540 (validation-round1 NB-2) -------------------------------------
# The S2 seam: readRideCeremony must agree with lane-gate.mjs's own
# readCeremonyLevel on non-canonical values -- a quoted/word ceremony_level
# fails closed (3), and an explicitly-given --spec that does not exist never
# falls back to --intake (lane-gate.mjs's own documented fail-closed rule).
test_1540_ceremony_fails_closed_like_lane_gate() {
  log_info "TEST-1540: a quoted or word ceremony_level fails closed to 3 (never the absent-field default of 2); an explicit --spec that is missing never falls back to --intake"
  mk
  cat > "$TEST_DIR/spec-quoted.md" <<'MD'
---
id: spec-test1540-quoted
type: spec
ceremony_level: "3"
---

# Spec
MD
  cat > "$TEST_DIR/intake-fallback.md" <<'MD'
---
id: ride-1540
type: change
ceremony_level: 0
---

# intake
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
  - id: lane-ceremony
    decision_ref: test1540-ride@2026-10-04T00:00:00Z
    decision_match: "MERGE LANE test1540"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_CEREMONY1540_MERGE
YAML
  cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"test1540-ride","ts":"2026-10-04T00:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE test1540 approved"}
JSONL
  echo "base doc" > "$repo/docs/base.md"
  commit_all "$repo" "base"
  local base; base="$(head_sha "$repo")"
  echo "a docs change" > "$repo/docs/changed.md"
  commit_all "$repo" "head"
  local head; head="$(head_sha "$repo")"
  write_sweep_record "$repo" 80

  local ghbin="$TEST_DIR/gh-bin" json="$TEST_DIR/pr.json" log="$TEST_DIR/gh.log"
  cat > "$json" <<JSON
{"number":80,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}],"body":""}
JSON
  build_gh_stub "$ghbin" "$json" "$log"

  # Quoted ceremony_level fails closed to 3 (no max_ceremony on the lane ->
  # ceremony_exceeds), never the absent-field default of 2 (which would be
  # <= DEFAULT_MAX_CEREMONY=2 and wrongly allow).
  run_check "$repo" "$ghbin" 80 --spec "$TEST_DIR/spec-quoted.md" --debug-inputs
  assert_payload_has_line "$OUT" "ceremony=3 intake_type=- ref=-" \
    "TEST-1540 [quoted]: expected ceremony=3 for a quoted ceremony_level, got: $OUT"
  assert_payload_has_line "$OUT" "lane=lane-ceremony reason=ceremony_exceeds" \
    "TEST-1540 [quoted]: expected ceremony_exceeds, got: $OUT"
  [[ "$RC" -eq 3 ]] || log_fail "TEST-1540 [quoted]: expected exit 3, got $RC: $OUT"

  # An explicit --spec that does not exist never falls back to --intake
  # (lane-gate.mjs's own readCeremonyLevel rule) -- even though the intake
  # here declares ceremony_level 0, the ride still counts as ceremony 3.
  run_check "$repo" "$ghbin" 80 --spec "$TEST_DIR/spec-missing-1540.md" --intake "$TEST_DIR/intake-fallback.md" --debug-inputs
  assert_payload_has_line "$OUT" "ceremony=3 intake_type=change ref=ride-1540" \
    "TEST-1540 [missing-spec-no-fallback]: expected ceremony=3 (no intake fallback), got: $OUT"
  assert_payload_has_line "$OUT" "lane=lane-ceremony reason=ceremony_exceeds" \
    "TEST-1540 [missing-spec-no-fallback]: expected ceremony_exceeds, got: $OUT"
  [[ "$RC" -eq 3 ]] || log_fail "TEST-1540 [missing-spec-no-fallback]: expected exit 3, got $RC: $OUT"

  log_pass "TEST-1540: readRideCeremony fails closed to 3 on a non-canonical ceremony_level and never falls back from an explicitly-missing --spec to --intake, agreeing with lane-gate.mjs"
}

# --- TEST-1543 (Spec-AC-10/12/15, validation-round2 R2-B2) -----------------
# A list-typed policy key (`kinds`, `requester_logins`, `requires.
# intake_types`) is closed-shape: ONLY a well-formed `[...]` flow list, never
# a bare scalar silently read as a one-element list, a quoted STRING that
# merely looks like a list, or an unclosed one. `requires.pr_body_contains`
# must be a non-empty string. Each malformed case below used to validate as
# VALID and have evaluateLane silently skip the condition it named (round-1
# and round-2 both shipped this fail-open); each must now be parse_error. The
# two control rows (an explicit `intake_types: []`, and a well-formed
# `requester_logins: [alice]`) must stay exactly as they were -- an
# explicitly empty list is a real, if unusual, policy shape, not a parse
# failure, and this fix must not touch the well-formed case at all.
test_1543_list_typed_requires_closed_shape() {
  log_info "TEST-1543: a scalar, unclosed or quoted-pseudo-list value for a list-typed key (kinds, requester_logins, requires.intake_types) is parse_error; an empty requires.pr_body_contains is parse_error; an explicit [] list and a well-formed requester_logins stay VALID"
  local case_name policy_body expect_ok expect_code
  for case_name in \
    scalar_intake_types unclosed_intake_types quoted_pseudo_list_intake_types \
    empty_pr_body_contains unclosed_requester_logins scalar_kinds \
    empty_intake_types_control closed_requester_logins_control; do
    mk
    case "$case_name" in
      scalar_intake_types)
        policy_body=$'version: 1\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1543-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1543 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1543A_MERGE\n    requires:\n      intake_types: change\n'
        expect_ok=0; expect_code=parse_error
        ;;
      unclosed_intake_types)
        policy_body=$'version: 1\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1543-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1543 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1543A_MERGE\n    requires:\n      intake_types: [change, issue, techdebt, hotfix\n'
        expect_ok=0; expect_code=parse_error
        ;;
      quoted_pseudo_list_intake_types)
        policy_body=$'version: 1\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1543-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1543 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1543A_MERGE\n    requires:\n      intake_types: "[change]"\n'
        expect_ok=0; expect_code=parse_error
        ;;
      empty_pr_body_contains)
        policy_body=$'version: 1\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1543-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1543 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1543A_MERGE\n    requires:\n      pr_body_contains: ""\n'
        expect_ok=0; expect_code=parse_error
        ;;
      unclosed_requester_logins)
        policy_body=$'version: 1\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1543-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1543 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1543A_MERGE\n    requester_logins: [alice\n'
        expect_ok=0; expect_code=parse_error
        ;;
      scalar_kinds)
        policy_body=$'version: 1\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1543-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1543 a"\n    signed_by: owner-login\n    kinds: docs\n    merge_reaches: nothing\n    marker: AAI_T1543A_MERGE\n'
        expect_ok=0; expect_code=parse_error
        ;;
      empty_intake_types_control)
        policy_body=$'version: 1\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1543-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1543 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1543A_MERGE\n    requires:\n      intake_types: []\n'
        expect_ok=1
        ;;
      closed_requester_logins_control)
        policy_body=$'version: 1\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1543-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1543 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1543A_MERGE\n    requester_logins: [alice]\n'
        expect_ok=1
        ;;
    esac
    mkdir -p "$TEST_DIR/root-$case_name/docs/ai"
    printf '%s' "$policy_body" > "$TEST_DIR/root-$case_name/docs/ai/merge-policy.yaml"
    cat > "$TEST_DIR/root-$case_name/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"t1543-a","ts":"2026-10-04T00:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE t1543 a approved"}
JSONL
    local out rc
    out="$(node "$MP" --validate --repo-root "$TEST_DIR/root-$case_name" 2>&1)" && rc=0 || rc=$?
    if [[ "$expect_ok" -eq 1 ]]; then
      [[ "$rc" -eq 0 ]] || log_fail "TEST-1543 [$case_name]: expected VALID (exit 0), got $rc: $out"
      assert_payload_has_line "$out" "VALID lanes=1" "TEST-1543 [$case_name]: expected VALID lanes=1, got: $out"
    else
      [[ "$rc" -eq 1 ]] || log_fail "TEST-1543 [$case_name]: expected INVALID (exit 1), got $rc: $out"
      assert_payload_contains "$out" "code=$expect_code" "TEST-1543 [$case_name]: expected $expect_code, got: $out"
    fi
  done

  log_pass "TEST-1543: a scalar, unclosed or quoted-pseudo-list value for kinds/requester_logins/requires.intake_types, and an empty requires.pr_body_contains, are each parse_error; an explicit [] list and a well-formed requester_logins stay VALID"
}

# --- TEST-1544 (Spec-AC-15, validation-round2 R2-B2) ------------------------
# End to end through --check (not just --validate): a scalar
# `requires.intake_types` used to validate as VALID and have evaluateLane
# silently skip the intake_type condition (Array.isArray(req.intake_types)
# was false, so the whole `if` was never entered) -- allowing a `feature`
# intake through a lane whose only written restriction was `intake_types:
# change`. It must now deny reason=policy_invalid before evaluateLane is
# ever reached.
test_1544_check_denies_scalar_intake_types() {
  log_info "TEST-1544: --check denies reason=policy_invalid for a scalar requires.intake_types, never silently skipping the condition and allowing a non-matching intake"
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
  - id: lane-t1544
    decision_ref: t1544-a@2026-10-04T00:00:00Z
    decision_match: "MERGE LANE t1544 a"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    marker: AAI_T1544_MERGE
    requires:
      intake_types: change
YAML
  cat > "$repo/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"t1544-a","ts":"2026-10-04T00:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE t1544 a approved"}
JSONL
  commit_all "$repo" "base"
  local base; base="$(head_sha "$repo")"
  echo "a docs change" > "$repo/docs/changed-1544.md"
  commit_all "$repo" "head"
  local head; head="$(head_sha "$repo")"
  write_sweep_record "$repo" 95

  cat > "$repo/docs/intake-1544.md" <<'MD'
---
id: ride-1544
type: feature
---

# intake
MD

  local ghbin="$TEST_DIR/gh-bin" json="$TEST_DIR/pr.json" log="$TEST_DIR/gh.log"
  cat > "$json" <<JSON
{"number":95,"state":"OPEN","isDraft":false,"baseRefName":"main","baseRefOid":"$base","headRefOid":"$head","reviews":[],"statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}],"body":""}
JSON
  build_gh_stub "$ghbin" "$json" "$log"

  run_check "$repo" "$ghbin" 95 --intake "$repo/docs/intake-1544.md"
  assert_payload_has_line "$OUT" "MERGE-POLICY denied pr=95 reason=policy_invalid" \
    "TEST-1544: expected policy_invalid, got: $OUT"
  assert_payload_has_line "$OUT" "lane=lane-t1544 reason=parse_error" \
    "TEST-1544: expected lane=lane-t1544 reason=parse_error, got: $OUT"
  [[ "$RC" -eq 3 ]] || log_fail "TEST-1544: expected exit 3, got $RC: $OUT"

  log_pass "TEST-1544: a scalar requires.intake_types denies reason=policy_invalid at --check, never silently allowing a feature intake through a change-only lane"
}

# --- TEST-1545 (Spec-AC-10/12/15, validation-round3 R3-B1) -----------------
# The parser used to read ONLY the indented lines following a block header
# (`deploy:`, `architecture:`, `lanes:`, a lane's `requires:`) and never
# check `rest` -- the text on the SAME line as the colon. A flow-style
# mapping/list written inline on that header line is valid YAML, so an
# owner writing one (P1 explicitly allows flow style for lists) got an
# EMPTY block instead of a parse_error: the written conditions silently
# vanished and --validate still said VALID. Round-1 B2 and round-2 R2-B2
# found the same fail-open one layer down (a list-typed FIELD); this is the
# header itself. Each case here must now be `noncanonical` (the P1
# round-trip check, merge-policy.mjs) or `missing_key` (an architecture
# entry with no `globs` at all -- a related, smaller gap in the same spot).
test_1545_block_header_inline_value_is_invalid() {
  log_info "TEST-1545 (R3-B1): an inline flow value on a block header (deploy/architecture/requires), or an architecture entry missing globs entirely, is invalid -- never a silently-empty block"
  local case_name policy_body expect_code
  for case_name in requires_flowmap deploy_flowmap architecture_flowlist architecture_missing_globs; do
    mk
    case "$case_name" in
      requires_flowmap)
        policy_body=$'version: 1\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1545-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1545 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1545A_MERGE\n    requires: {intake_types: [change], validation_pass: true}\n'
        expect_code=noncanonical
        ;;
      deploy_flowmap)
        policy_body=$'version: 1\ndeploy: {preview: none, production_on_merge: false}\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1545-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1545 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1545A_MERGE\n'
        expect_code=noncanonical
        ;;
      architecture_flowlist)
        policy_body=$'version: 1\narchitecture: [{id: consumer-facing, globs: ["docs/**"]}]\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1545-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1545 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1545A_MERGE\n'
        expect_code=noncanonical
        ;;
      architecture_missing_globs)
        policy_body=$'version: 1\narchitecture:\n  - id: consumer-facing\nkinds:\n  - id: docs\n    globs: ["docs/**"]\nlanes:\n  - id: lane-a\n    decision_ref: t1545-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1545 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1545A_MERGE\n'
        expect_code=missing_key
        ;;
    esac
    mkdir -p "$TEST_DIR/root-$case_name/docs/ai"
    printf '%s' "$policy_body" > "$TEST_DIR/root-$case_name/docs/ai/merge-policy.yaml"
    cat > "$TEST_DIR/root-$case_name/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"t1545-a","ts":"2026-10-04T00:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE t1545 a approved"}
JSONL
    local out rc
    out="$(node "$MP" --validate --repo-root "$TEST_DIR/root-$case_name" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -eq 1 ]] || log_fail "TEST-1545 [$case_name]: expected INVALID (exit 1), got $rc: $out"
    assert_payload_contains "$out" "code=$expect_code" "TEST-1545 [$case_name]: expected $expect_code, got: $out"
  done

  log_pass "TEST-1545 (R3-B1) an inline flow value on a block header is noncanonical, and an architecture entry with no globs is missing_key -- never a silently-empty block"
}

# --- TEST-1546 (validation-round3 NB-3) -------------------------------------
# parseFlowList's comma split used to ignore quoting entirely, so a
# malformed list only ever NARROWED to junk items instead of failing
# closed: a trailing bracket pair after the list (`[a] [b]`) and a literal
# comma meant as DATA inside quotes (`["a,b"]`) both used to parse as some
# list other than the one written, silently. Folded into the R3-B1 fix:
# both are now parse_error.
test_1546_flow_list_tokenizer_folds() {
  log_info "TEST-1546 (NB-3): a trailing bracket pair after a flow list, or a quoted comma item, is parse_error -- never a silently narrowed list"
  local case_name globs_line
  for case_name in trailing_bracket quoted_comma_item; do
    mk
    case "$case_name" in
      trailing_bracket) globs_line='    globs: ["docs/**"] ["x"]' ;;
      quoted_comma_item) globs_line='    globs: ["docs/**,extra"]' ;;
    esac
    mkdir -p "$TEST_DIR/root-$case_name/docs/ai"
    printf 'version: 1\nkinds:\n  - id: docs\n%s\nlanes:\n  - id: lane-a\n    decision_ref: t1546-a@2026-10-04T00:00:00Z\n    decision_match: "MERGE LANE t1546 a"\n    signed_by: owner-login\n    kinds: [docs]\n    merge_reaches: nothing\n    marker: AAI_T1546A_MERGE\n' "$globs_line" \
      > "$TEST_DIR/root-$case_name/docs/ai/merge-policy.yaml"
    cat > "$TEST_DIR/root-$case_name/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"t1546-a","ts":"2026-10-04T00:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE t1546 a approved"}
JSONL
    local out rc
    out="$(node "$MP" --validate --repo-root "$TEST_DIR/root-$case_name" 2>&1)" && rc=0 || rc=$?
    [[ "$rc" -eq 1 ]] || log_fail "TEST-1546 [$case_name]: expected INVALID (exit 1), got $rc: $out"
    assert_payload_contains "$out" "code=parse_error" "TEST-1546 [$case_name]: expected parse_error, got: $out"
  done

  log_pass "TEST-1546 (NB-3) a trailing bracket pair after a flow list, and a quoted comma item, both fail closed as parse_error"
}

# --- TEST-1547 (P1 round-trip) -----------------------------------------------
# The round-trip check (merge-policy.mjs parsePolicy) must normalize, never
# reject, every spelling P1 already documents as equivalent: full-line and
# trailing comments, CRLF line endings, a quoted string where bare would do
# (and vice versa), and an explicit empty `requires: {}`/`architecture: []`
# (loses nothing -- the same as omitting the key). None of these may ever
# become `noncanonical`.
test_1547_round_trip_preserves_meaning() {
  log_info "TEST-1547 (P1 round-trip): comments, CRLF, quoted-vs-bare scalars and an explicit empty block all stay VALID"
  mk
  mkdir -p "$TEST_DIR/root/docs/ai"
  local body
  body='# full-line comment at the top
version: 1
deploy: {}
architecture: []
kinds:
  - id: docs
    globs: ["docs/**"]   # trailing comment after a flow list
lanes:
  - id: "lane-a"
    decision_ref: t1547-a@2026-10-04T00:00:00Z
    decision_match: "MERGE LANE t1547 a"
    signed_by: owner-login
    kinds: [docs]
    merge_reaches: nothing
    allow_public_side_effect: "false"
    marker: AAI_T1547A_MERGE
    requires:
      validation_pass: "true"
'
  printf '%s\r\n' "${body//$'\n'/$'\r\n'}" > "$TEST_DIR/root/docs/ai/merge-policy.yaml"
  cat > "$TEST_DIR/root/docs/ai/decisions.jsonl" <<'JSONL'
{"type":"hitl_decision","ref_id":"t1547-a","ts":"2026-10-04T00:00:00Z","owner_signoff":true,"actor":"owner-login","decision":"MERGE LANE t1547 a approved"}
JSONL
  local out rc
  out="$(node "$MP" --validate --repo-root "$TEST_DIR/root" 2>&1)" && rc=0 || rc=$?
  [[ "$rc" -eq 0 ]] || log_fail "TEST-1547: expected VALID (exit 0), got $rc: $out"
  assert_payload_has_line "$out" "VALID lanes=1" "TEST-1547: expected VALID lanes=1, got: $out"

  log_pass "TEST-1547 (P1 round-trip) comments, CRLF, quoted scalars and an explicit empty block all stay VALID -- the round-trip check normalizes, never rejects, an accepted equivalent spelling"
}

# --- TEST-1548 (validation-round3, structural round-trip fuzz) -------------
# Takes the LIVE docs/ai/merge-policy.yaml and applies, one at a time, a
# dozen single-line perturbations the parser does not actually consume
# (an inline value on a block header, a malformed flow-list item, a
# duplicated line at the wrong indent, an unknown trailing token after a
# well-formed list) -- each must be invalid. This is the generic backstop
# the P1 round-trip check exists for: it is not a list of hand-picked
# shapes, it is "anything the parser would otherwise silently drop".
test_1548_round_trip_fuzz_over_live_policy() {
  log_info "TEST-1548: a dozen single-line perturbations of the LIVE merge-policy.yaml, each one the parser would not consume, are all invalid"
  local live="$PROJECT_ROOT/docs/ai/merge-policy.yaml"
  [[ -f "$live" ]] || { log_fail "TEST-1548: $live does not exist"; return; }
  mk
  local -a perturbations=(
    "deploy_header_inline|14s/.*/deploy: {x: 1}/"
    "architecture_header_inline|17s/.*/architecture: [x]/"
    "kinds_header_inline|20s/.*/kinds: [x]/"
    "lanes_header_inline|23s/.*/lanes: [x]/"
    "requires_header_inline|31s/.*/    requires: {x: 1}/"
    "architecture_globs_trailing_bracket|19s/.*/    globs: [\"x\"] [\"y\"]/"
    "architecture_globs_quoted_comma|19s/.*/    globs: [\"x,y\"]/"
    "kinds_globs_trailing_bracket|22s/.*/    globs: [\"x\"] [\"y\"]/"
    "kinds_globs_quoted_comma|22s/.*/    globs: [\"x,y\"]/"
    "architecture_globs_deleted|19d"
    "duplicated_line_wrong_indent|16a\\
    production_on_merge: false"
    "lane_kinds_trailing_token|28s/.*/    kinds: [repo] extra/"
  )
  local entry name sed_expr f out rc failed=0
  for entry in "${perturbations[@]}"; do
    name="${entry%%|*}"
    sed_expr="${entry#*|}"
    f="$TEST_DIR/live-$name.yaml"
    sed -e "$sed_expr" "$live" > "$f"
    out="$(node "$MP" --validate --path "$f" --repo-root "$PROJECT_ROOT" 2>&1)" && rc=0 || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      log_fail "TEST-1548 [$name]: expected INVALID, got VALID: $out"
      failed=1
    fi
  done
  [[ "$failed" -eq 0 ]] && log_pass "TEST-1548: all 12 single-line perturbations of the live policy are invalid, none silently accepted"
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
  test_1521_requires_keys
  test_1522_pr_state_and_api_errors
  test_1524_output_contract
  test_1525_live_policy_validates
  test_1526_live_policy_fixture
  test_1527_prompts_defer_to_evaluator
  test_1530_companion_wiring
  test_1532_changelog_unreleased_entry
  test_1533_default_ride_inputs_from_state
  test_1534_boolean_scalar_strictness
  test_1535_enum_rejection
  test_1536_duplicate_key
  test_1537_missing_key
  test_1538_bad_ceremony
  test_1539_version_checked
  test_1540_ceremony_fails_closed_like_lane_gate
  test_1543_list_typed_requires_closed_shape
  test_1544_check_denies_scalar_intake_types
  test_1545_block_header_inline_value_is_invalid
  test_1546_flow_list_tokenizer_folds
  test_1547_round_trip_preserves_meaning
  test_1548_round_trip_fuzz_over_live_policy
  # 1523 last: it asserts over its OWN gh-argv log, built from calls this
  # function makes itself (standalone-runnable), not a suite-wide shared log.
  test_1523_gh_argv_only_pr_view

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
