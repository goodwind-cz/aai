#!/usr/bin/env bash
#
# Test: parallel-safe doc numbering (SPEC-0015 / RFC-0007)
#
# Verifies slug-primary durable doc identity assigned at intake and the
# sequential TYPE-000N display number assigned at the MERGE serialization point
# by the allocator, with the CI/pre-commit no-DRAFT + duplicate-number guards as
# the backstop, and the index generator deriving the display id from `number`.
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-doc-numbering"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ALLOC_SCRIPT="$PROJECT_ROOT/.aai/scripts/allocate-doc-number.mjs"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    echo "INFO: keeping fixture at $TEST_DIR"
    return 0
  fi
  if [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]]; then
    rm -rf "$TEST_DIR"
  fi
}
trap cleanup EXIT

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

assert_file() { [[ -f "$1" ]] || log_fail "Missing file: $1"; }
assert_contains() { grep -qF "$2" "$1" || log_fail "Expected '$2' in $1"; }
assert_not_contains() {
  if grep -qF "$2" "$1"; then log_fail "Did not expect '$2' in $1"; fi
}

extract_section() {
  awk -v want="$2" '
    /^## / { insec = (index($0, want) == 1) }
    insec { print }
  ' "$1"
}

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$ALLOC_SCRIPT" ]] || log_fail "Allocator script not found: $ALLOC_SCRIPT (RED: not implemented yet)"
  log_pass "Dependencies checked"
}

# Vendor the doc-numbering toolchain into an isolated git repo. Echoes the path.
# CHANGE-0035 / SPEC-0047 D9 back-compat: every fixture gets a REAL bare-repo
# origin (local, zero network) so the new reservation-before-rename step
# succeeds silently in every existing test — no fixture here observes the D4
# provisional-marker fallback, so every pre-existing assertion in this suite
# stays byte-for-byte unmodified (the marker/warning-observing exception in D9
# applies to NO stanza in this file).
setup_iso_repo() {
  local d="$TEST_DIR/iso-$1"
  local bare="$TEST_DIR/origin-$1.git"
  rm -rf "$d" "$bare"
  mkdir -p "$d/.aai/scripts/lib" \
           "$d/docs/rfc" "$d/docs/specs" "$d/docs/issues" \
           "$d/docs/requirements" "$d/docs/releases" "$d/docs/ai"
  cp "$PROJECT_ROOT/.aai/scripts/allocate-doc-number.mjs" "$d/.aai/scripts/" 2>/dev/null || true
  cp "$PROJECT_ROOT/.aai/scripts/generate-docs-index.mjs" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/append-event.mjs" "$d/.aai/scripts/"
  cp "$PROJECT_ROOT/.aai/scripts/pre-commit-checks.sh" "$d/.aai/scripts/" 2>/dev/null || true
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs "$d/.aai/scripts/lib/"
  (cd "$d" && git init -q \
     && git config user.email test@example.com \
     && git config user.name "AAI Test")
  printf 'docs/INDEX.audit.md\n' > "$d/.gitignore"
  (cd "$d" && git add .aai .gitignore && git commit -qm "chore: vendor scripts")
  git init -q --bare "$bare"
  (cd "$d" && git remote add origin "$bare")
  printf '%s' "$d"
}

# Seed docs/rfc with RFC-0001..RFC-000N (fully-numbered) and commit on the
# current branch. Arg2 = highest number to create.
seed_rfcs() {
  local d="$1" top="$2" i n
  for i in $(seq 1 "$top"); do
    n="$(printf '%04d' "$i")"
    cat > "$d/docs/rfc/RFC-$n-seed-$i.md" <<MD
---
id: rfc-seed-$i
type: rfc
number: $i
status: done
links:
  pr: []
---
# Seed RFC $i
MD
  done
  (cd "$d" && git add docs/rfc && git commit -qm "docs: seed RFCs up to $top")
}

write_draft() {
  # write_draft <repo> <dir> <PREFIX> <slug>
  local d="$1" dir="$2" prefix="$3" slug="$4"
  cat > "$d/docs/$dir/$prefix-DRAFT-$slug.md" <<MD
---
id: $slug
type: rfc
number: null
status: draft
links:
  pr: []
---
# Draft: $slug
MD
}

# --- TEST-001: deriveSlug + draftFilename -----------------------------------
test_001_slug_and_filename() {
  log_info "TEST-001: deriveSlug cases + draftFilename assembly..."
  local d; d="$(setup_iso_repo t001)"
  cat > "$d/probe.mjs" <<'EOF'
import { deriveSlug, draftFilename } from './.aai/scripts/allocate-doc-number.mjs';
import assert from 'node:assert';
assert.strictEqual(deriveSlug('Parallel-Safe Doc Numbering!'), 'parallel-safe-doc-numbering');
assert.strictEqual(deriveSlug('  Mixed   CASE, punctuation... '), 'mixed-case-punctuation');
assert.strictEqual(deriveSlug('Přílíš žluťoučký kůň'), 'prilis-zlutoucky-kun', 'transliterate to ASCII');
// oversized topic truncated <= 48 at a hyphen boundary (never mid-word)
const big = deriveSlug('one two three four five six seven eight nine ten eleven twelve');
assert.ok(big.length <= 48, `slug length ${big.length} must be <= 48`);
assert.ok(!big.endsWith('-'), 'no trailing hyphen');
assert.ok(!/twe$|elev$|twel$/.test(big), 'must not cut mid-word: ' + big);
// empty-reduced topic rejected (returns '')
assert.strictEqual(deriveSlug('!!! @@@ ###'), '');
assert.strictEqual(deriveSlug(''), '');
// draftFilename assembles docs/<type>/<TYPE>-DRAFT-<slug>.md
assert.strictEqual(draftFilename('rfc', 'my-topic'), 'docs/rfc/RFC-DRAFT-my-topic.md');
assert.strictEqual(draftFilename('spec', 'my-topic'), 'docs/specs/SPEC-DRAFT-my-topic.md');
assert.strictEqual(draftFilename('change', 'my-topic'), 'docs/issues/CHANGE-DRAFT-my-topic.md');
console.log('ok');
EOF
  (cd "$d" && node probe.mjs) > "$d/probe.log" 2>&1 \
    || log_fail "TEST-001 slug/filename helpers incorrect: $(cat "$d/probe.log")"
  rm -rf "$d"
  log_pass "TEST-001 deriveSlug + draftFilename correct"
}

# --- TEST-002: deterministic collision suffix -------------------------------
test_002_collision_suffix() {
  log_info "TEST-002: deterministic 4-char base36 collision suffix..."
  local d; d="$(setup_iso_repo t002)"
  cat > "$d/probe.mjs" <<'EOF'
import { collisionSuffix, draftFilename } from './.aai/scripts/allocate-doc-number.mjs';
import assert from 'node:assert';
const a1 = collisionSuffix('feature/parallel-safe-doc-numbering');
const a2 = collisionSuffix('feature/parallel-safe-doc-numbering');
const b1 = collisionSuffix('feature/other-branch');
assert.strictEqual(a1, a2, 'same seed must be deterministic');
assert.notStrictEqual(a1, b1, 'different branches must differ');
assert.ok(/^[a-z0-9]{4}$/.test(a1), `suffix must be 4-char lowercase base36, got "${a1}"`);
// suffix applied via draftFilename optional arg -> "-abcd" appended before .md
const fn = draftFilename('rfc', 'my-topic', a1);
assert.strictEqual(fn, `docs/rfc/RFC-DRAFT-my-topic-${a1}.md`);
console.log('ok');
EOF
  (cd "$d" && node probe.mjs) > "$d/probe.log" 2>&1 \
    || log_fail "TEST-002 collision suffix incorrect: $(cat "$d/probe.log")"
  rm -rf "$d"
  log_pass "TEST-002 collision suffix deterministic + applied"
}

# --- TEST-003: DRAFT frontmatter passes audit + index -----------------------
test_003_draft_passes_audit_and_index() {
  log_info "TEST-003: DRAFT (id=slug, number:null, status:draft) passes audit + index..."
  local d; d="$(setup_iso_repo t003)"
  write_draft "$d" rfc RFC parallel-safe-doc-numbering
  (cd "$d" && git add docs/rfc && git commit -qm "docs: add draft" >/dev/null)
  (cd "$d" && node .aai/scripts/docs-audit.mjs --check --strict --no-event \
      --path docs/rfc/RFC-DRAFT-parallel-safe-doc-numbering.md > audit.log 2>&1) \
    || log_fail "DRAFT doc must pass docs-audit --check --strict: $(cat "$d/audit.log")"
  (cd "$d" && node .aai/scripts/generate-docs-index.mjs > gen.log 2>&1) \
    || log_fail "generate-docs-index must place a DRAFT without failing: $(cat "$d/gen.log")"
  local index="$d/docs/INDEX.md"
  extract_section "$index" "## Drafts" > "$d/drafts.txt"
  grep -qF "parallel-safe-doc-numbering" "$d/drafts.txt" \
    || log_fail "DRAFT must appear in the Drafts section under its slug"
  # No schema violation / coverage gap for the DRAFT.
  assert_not_contains "$index" "Coverage gaps"
  if [[ -f "$d/docs/INDEX.violations.md" ]]; then
    assert_not_contains "$d/docs/INDEX.violations.md" "RFC-DRAFT-parallel-safe-doc-numbering"
  fi
  rm -rf "$d"
  log_pass "TEST-003 DRAFT passes audit + placed in Drafts, no violation"
}

# --- TEST-004: allocator rename + stamp + index -----------------------------
test_004_allocator_renames() {
  log_info "TEST-004: allocator renames DRAFT->RFC-0007, stamps number, keeps slug, rewrites refs..."
  local d; d="$(setup_iso_repo t004)"
  seed_rfcs "$d" 6
  # A branch carrying an unnumbered draft, plus an in-branch reference to it.
  (cd "$d" && git checkout -q -b feature/alloc)
  write_draft "$d" rfc RFC parallel-safe-doc-numbering
  cat > "$d/docs/specs/SPEC-DRAFT-refers.md" <<'MD'
---
id: refers
type: spec
number: null
status: draft
links:
  pr: []
---
# Refers to RFC-DRAFT-parallel-safe-doc-numbering.md in its body
See docs/rfc/RFC-DRAFT-parallel-safe-doc-numbering.md for details.
MD
  (cd "$d" && git add docs && git commit -qm "docs: add draft + referrer" >/dev/null)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-parallel-safe-doc-numbering.md --base-ref main \
      > alloc.log 2>&1) \
    || log_fail "allocator must exit 0: $(cat "$d/alloc.log")"
  assert_file "$d/docs/rfc/RFC-0007-parallel-safe-doc-numbering.md"
  [[ ! -f "$d/docs/rfc/RFC-DRAFT-parallel-safe-doc-numbering.md" ]] \
    || log_fail "DRAFT file must be renamed away"
  local out="$d/docs/rfc/RFC-0007-parallel-safe-doc-numbering.md"
  grep -qE '^number:[[:space:]]*7[[:space:]]*$' "$out" \
    || log_fail "stamped number must be 7"
  grep -qE '^id:[[:space:]]*parallel-safe-doc-numbering[[:space:]]*$' "$out" \
    || log_fail "id must stay the slug (unchanged)"
  # reference rewritten in the referrer doc
  assert_contains "$d/docs/specs/SPEC-DRAFT-refers.md" "RFC-0007-parallel-safe-doc-numbering.md"
  assert_not_contains "$d/docs/specs/SPEC-DRAFT-refers.md" "RFC-DRAFT-parallel-safe-doc-numbering.md"
  # index regenerated shows the display id RFC-0007
  assert_file "$d/docs/INDEX.md"
  assert_contains "$d/docs/INDEX.md" "RFC-0007"
  rm -rf "$d"
  log_pass "TEST-004 allocator renamed, stamped, rewrote refs, regenerated index"
}

# --- TEST-005: exit codes 2/3/4 + dry-run -----------------------------------
test_005_exit_codes() {
  log_info "TEST-005: allocator exit codes (2 bad args, 3 unreachable, 4 malformed, dry-run 0)..."
  local d; d="$(setup_iso_repo t005)"
  seed_rfcs "$d" 6
  # bad args -> 2
  set +e
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --bogus-flag > bad.log 2>&1)
  local rc=$?
  set -e
  [[ "$rc" -eq 2 ]] || log_fail "unknown flag must exit 2 (got $rc)"
  # stray POSITIONAL arg -> 2, no writes (FIX 1: parseArgs _extra bug)
  local pos_before; pos_before="$(ls "$d/docs/rfc" | sort | tr '\n' ',')"
  set +e
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs stray-positional > pos.log 2>&1)
  rc=$?
  set -e
  [[ "$rc" -eq 2 ]] || log_fail "stray positional arg must exit 2 (got $rc): $(cat "$d/pos.log")"
  local pos_after; pos_after="$(ls "$d/docs/rfc" | sort | tr '\n' ',')"
  [[ "$pos_before" == "$pos_after" ]] || log_fail "stray positional must not write (dir changed)"
  # neither --path nor --all -> 2 with guidance (FIX 4: --all semantics)
  set +e
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --base-ref main > noselect.log 2>&1)
  rc=$?
  set -e
  [[ "$rc" -eq 2 ]] || log_fail "path-less call without --all must exit 2 (got $rc): $(cat "$d/noselect.log")"
  grep -qiE 'specify --path|--all' "$d/noselect.log" \
    || log_fail "no-selection error must guide toward --path/--all"
  # base ref unreachable -> 3, DRAFT byte-identical
  (cd "$d" && git checkout -q -b feature/x)
  write_draft "$d" rfc RFC unreachable-topic
  local before; before="$(shasum "$d/docs/rfc/RFC-DRAFT-unreachable-topic.md" | awk '{print $1}')"
  set +e
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-unreachable-topic.md --base-ref origin/nonexistent \
      > unreach.log 2>&1)
  rc=$?
  set -e
  [[ "$rc" -eq 3 ]] || log_fail "unreachable base ref must exit 3 (got $rc): $(cat "$d/unreach.log")"
  local after; after="$(shasum "$d/docs/rfc/RFC-DRAFT-unreachable-topic.md" | awk '{print $1}')"
  [[ "$before" == "$after" ]] || log_fail "DRAFT must be byte-identical after exit 3"
  assert_file "$d/docs/rfc/RFC-DRAFT-unreachable-topic.md"
  # malformed DRAFT frontmatter (no slug id) -> 4
  cat > "$d/docs/rfc/RFC-DRAFT-noid.md" <<'MD'
---
type: rfc
number: null
status: draft
---
# No id
MD
  set +e
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-noid.md --base-ref main > noid.log 2>&1)
  rc=$?
  set -e
  [[ "$rc" -eq 4 ]] || log_fail "malformed DRAFT (no id) must exit 4 (got $rc): $(cat "$d/noid.log")"
  assert_file "$d/docs/rfc/RFC-DRAFT-noid.md"
  [[ ! -f "$d/docs/rfc/RFC-0007-noid.md" ]] || log_fail "no partial rename on exit 4"
  # --dry-run prints plan, exits 0, writes nothing
  rm "$d/docs/rfc/RFC-DRAFT-noid.md"
  local sha_before; sha_before="$(shasum "$d/docs/rfc/RFC-DRAFT-unreachable-topic.md" | awk '{print $1}')"
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-unreachable-topic.md --base-ref main --dry-run \
      > dry.log 2>&1) \
    || log_fail "--dry-run must exit 0: $(cat "$d/dry.log")"
  assert_contains "$d/dry.log" "RFC-0007-unreachable-topic.md"
  local sha_after; sha_after="$(shasum "$d/docs/rfc/RFC-DRAFT-unreachable-topic.md" | awk '{print $1}')"
  [[ "$sha_before" == "$sha_after" ]] || log_fail "--dry-run must write nothing"
  assert_file "$d/docs/rfc/RFC-DRAFT-unreachable-topic.md"
  rm -rf "$d"
  log_pass "TEST-005 exit codes 2/3/4 + dry-run correct"
}

# --- TEST-006: CONCURRENCY centerpiece --------------------------------------
test_006_concurrency() {
  log_info "TEST-006 (CONCURRENCY): two branches off one main serialize-merge without a duplicate..."
  local d; d="$(setup_iso_repo t006)"
  seed_rfcs "$d" 6   # main max = RFC-0006
  # branch A and branch B both off the SAME main.
  (cd "$d" && git checkout -q -b branchA main)
  write_draft "$d" rfc RFC topic-a
  (cd "$d" && git add docs/rfc && git commit -qm "docs: draft A" >/dev/null)
  (cd "$d" && git checkout -q -b branchB main)
  write_draft "$d" rfc RFC topic-b
  (cd "$d" && git add docs/rfc && git commit -qm "docs: draft B" >/dev/null)

  # A allocates against main (max 0006) -> RFC-0007, then merges to main.
  (cd "$d" && git checkout -q branchA \
     && node .aai/scripts/allocate-doc-number.mjs \
          --path docs/rfc/RFC-DRAFT-topic-a.md --base-ref main > allocA.log 2>&1) \
    || log_fail "A allocation failed: $(cat "$d/allocA.log")"
  assert_file "$d/docs/rfc/RFC-0007-topic-a.md"
  # Serialized merge to main. -X theirs auto-resolves the regenerated docs/INDEX.md
  # (a harness artifact both branches touch); the RFC files themselves never
  # conflict — that is the point being proven.
  (cd "$d" && git add -A && git commit -qm "docs: number A -> 0007" >/dev/null \
     && git checkout -q main && git merge -q --no-ff -X theirs branchA -m "merge A" >/dev/null)

  # B allocates against the UPDATED main (now max 0007) -> must re-derive 0008.
  (cd "$d" && git checkout -q branchB \
     && node .aai/scripts/allocate-doc-number.mjs \
          --path docs/rfc/RFC-DRAFT-topic-b.md --base-ref main > allocB.log 2>&1) \
    || log_fail "B allocation failed: $(cat "$d/allocB.log")"
  assert_file "$d/docs/rfc/RFC-0008-topic-b.md"
  [[ ! -f "$d/docs/rfc/RFC-0007-topic-b.md" ]] \
    || log_fail "B must NOT re-mint RFC-0007 (that is the RFC-0007 collision bug)"
  # merge B and assert main has exactly one RFC-0007 and one RFC-0008
  (cd "$d" && git add -A && git commit -qm "docs: number B -> 0008" >/dev/null \
     && git checkout -q main && git merge -q --no-ff -X theirs branchB -m "merge B" >/dev/null)
  local n7 n8
  n7="$(ls "$d/docs/rfc" | grep -c '^RFC-0007-' || true)"
  n8="$(ls "$d/docs/rfc" | grep -c '^RFC-0008-' || true)"
  [[ "$n7" -eq 1 ]] || log_fail "exactly one RFC-0007 must exist on main (got $n7)"
  [[ "$n8" -eq 1 ]] || log_fail "exactly one RFC-0008 must exist on main (got $n8)"
  rm -rf "$d"
  log_pass "TEST-006 concurrency: second branch re-derived RFC-0008, no duplicate 0007"
}

# --- TEST-007: no-DRAFT-at-merge guard --------------------------------------
test_007_no_draft_guard() {
  log_info "TEST-007: no-DRAFT-at-merge guard rejects a DRAFT tree, passes a numbered tree..."
  local d; d="$(setup_iso_repo t007)"
  seed_rfcs "$d" 6
  # clean numbered tree -> guard exit 0
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --guard > guard-clean.log 2>&1) \
    || log_fail "guard must exit 0 on a fully-numbered tree: $(cat "$d/guard-clean.log")"
  # add a DRAFT -> guard exit non-zero naming the draft. The guard checks the
  # STAGED/MERGED tree (SPEC-0015 D6), so the draft must be git-added to be seen.
  write_draft "$d" rfc RFC still-a-draft
  (cd "$d" && git add docs/rfc/RFC-DRAFT-still-a-draft.md)
  set +e
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --guard > guard-draft.log 2>&1)
  local rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || log_fail "guard must exit non-zero when a DRAFT is present"
  assert_contains "$d/guard-draft.log" "RFC-DRAFT-still-a-draft"
  rm -rf "$d"
  log_pass "TEST-007 no-DRAFT guard rejects DRAFT tree, passes numbered tree"
}

# --- TEST-008: duplicate-number guard ---------------------------------------
test_008_duplicate_guard() {
  log_info "TEST-008: duplicate-number guard rejects a colliding pair, passes unique numbers..."
  local d; d="$(setup_iso_repo t008)"
  seed_rfcs "$d" 6
  # unique numbers -> exit 0
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --guard > guard-unique.log 2>&1) \
    || log_fail "guard must exit 0 with unique numbers: $(cat "$d/guard-unique.log")"
  # two RFC docs both resolving to RFC-0007 -> non-zero listing the pair
  cat > "$d/docs/rfc/RFC-0007-alpha.md" <<'MD'
---
id: alpha
type: rfc
number: 7
status: done
links:
  pr: []
---
# Alpha
MD
  cat > "$d/docs/rfc/RFC-0007-beta.md" <<'MD'
---
id: beta
type: rfc
number: 7
status: done
links:
  pr: []
---
# Beta
MD
  # guard checks the STAGED/MERGED tree (SPEC-0015 D6): stage the colliding pair.
  (cd "$d" && git add docs/rfc/RFC-0007-alpha.md docs/rfc/RFC-0007-beta.md)
  set +e
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --guard > guard-dup.log 2>&1)
  local rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || log_fail "guard must exit non-zero on a duplicate number"
  assert_contains "$d/guard-dup.log" "RFC-0007"
  grep -qF "alpha" "$d/guard-dup.log" && grep -qF "beta" "$d/guard-dup.log" \
    || log_fail "guard must list the colliding pair (alpha + beta)"
  rm -rf "$d"
  log_pass "TEST-008 duplicate-number guard rejects colliding pair, passes unique"
}

# --- TEST-009: index display-id + unnumbered draft + idempotence ------------
test_009_index_display_id() {
  log_info "TEST-009: index renders TYPE-000N for numbered docs, slug for drafts, byte-idempotent..."
  local d; d="$(setup_iso_repo t009)"
  # A numbered doc whose SLUG deliberately shares no substring with its display
  # id, so the display id can only come from the `number` field (D5), not the
  # filename/path leaking into a weak assertion.
  cat > "$d/docs/rfc/RFC-0007-widget-pipeline.md" <<'MD'
---
id: widget-pipeline
type: rfc
number: 7
status: done
links:
  pr: []
---
# Numbered
MD
  # a number:null DRAFT whose slug does NOT contain the word "unnumbered"
  write_draft "$d" rfc RFC gadget-flow
  (cd "$d" && node .aai/scripts/generate-docs-index.mjs > gen1.log 2>&1) \
    || log_fail "index gen failed: $(cat "$d/gen1.log")"
  local index="$d/docs/INDEX.md"
  # numbered doc's DONE row shows display id RFC-0007 in the ID column (derived
  # from number), and NOT its slug id.
  extract_section "$index" "## Done" > "$d/done.txt"
  grep -qE '^\|[[:space:]]*RFC-0007[[:space:]]*\|' "$d/done.txt" \
    || log_fail "Done row must render the display id RFC-0007 in the ID column (from number)"
  if grep -qF "| widget-pipeline " "$d/done.txt"; then
    log_fail "numbered doc must NOT render its slug id in the ID column"
  fi
  # the DRAFT shows its slug in a distinct unnumbered surface (annotation, not slug text)
  extract_section "$index" "## Drafts" > "$d/drafts.txt"
  grep -qF "gadget-flow" "$d/drafts.txt" \
    || log_fail "DRAFT slug must appear in Drafts"
  grep -qiF "unnumbered draft" "$d/drafts.txt" \
    || log_fail "DRAFT must be surfaced distinctly as an unnumbered draft"
  # byte-idempotent modulo Generated
  grep -v '^Generated:' "$index" > "$d/run1.snap"
  (cd "$d" && node .aai/scripts/generate-docs-index.mjs > gen2.log 2>&1)
  grep -v '^Generated:' "$index" > "$d/run2.snap"
  diff -q "$d/run1.snap" "$d/run2.snap" >/dev/null \
    || log_fail "index must be byte-idempotent modulo the Generated line"
  rm -rf "$d"
  log_pass "TEST-009 display-id from number + distinct unnumbered draft + idempotent"
}

# --- TEST-010: allocator-absent degrade-and-report --------------------------
test_010_allocator_absent_fallback() {
  log_info "TEST-010: allocator-absent path degrades, guard still backstops a collision..."
  # (a) grep-wiring: the intake + PR prompts document the allocator-absent fallback.
  local intake="$PROJECT_ROOT/.aai/SKILL_INTAKE.prompt.md"
  local pr="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
  assert_file "$intake"; assert_file "$pr"
  grep -qiE "allocate-doc-number|allocator" "$pr" \
    || log_fail "SKILL_PR must reference the allocator"
  grep -qiE "absent|missing|does not exist|fall.?back|scan-and-mint" "$pr" \
    || log_fail "SKILL_PR must document the allocator-absent fallback"
  grep -qiE "absent|missing|fall.?back|scan-and-mint|legacy" "$intake" \
    || log_fail "SKILL_INTAKE must document the scan-and-mint fallback"
  # (b) functional: with the allocator renamed away, the guard (independent tool)
  # still catches a resulting duplicate-number collision.
  local d; d="$(setup_iso_repo t010)"
  # keep the guard tool available under a different name to prove independence
  cp "$d/.aai/scripts/allocate-doc-number.mjs" "$d/.aai/scripts/guard-only.mjs"
  rm "$d/.aai/scripts/allocate-doc-number.mjs"
  cat > "$d/docs/rfc/RFC-0007-one.md" <<'MD'
---
id: one
type: rfc
number: 7
status: done
links:
  pr: []
---
# One
MD
  cat > "$d/docs/rfc/RFC-0007-two.md" <<'MD'
---
id: two
type: rfc
number: 7
status: done
links:
  pr: []
---
# Two
MD
  # guard checks the STAGED/MERGED tree (SPEC-0015 D6): stage the colliding pair.
  (cd "$d" && git add docs/rfc/RFC-0007-one.md docs/rfc/RFC-0007-two.md)
  set +e
  (cd "$d" && node .aai/scripts/guard-only.mjs --guard > guard.log 2>&1)
  local rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || log_fail "guard backstop must still catch the collision when the allocator is absent"
  assert_contains "$d/guard.log" "RFC-0007"
  rm -rf "$d"
  log_pass "TEST-010 allocator-absent documented + guard backstop still fires"
}

# --- TEST-011: backfill idempotence -----------------------------------------
test_011_backfill() {
  log_info "TEST-011: --backfill stamps number from filename, no rename, idempotent..."
  local d; d="$(setup_iso_repo t011)"
  # a legacy numbered doc WITHOUT a number field
  cat > "$d/docs/rfc/RFC-0006-legacy.md" <<'MD'
---
id: legacy-topic
type: rfc
status: done
links:
  pr: []
---
# Legacy numbered doc without a number field
MD
  local before; before="$(cat "$d/docs/rfc/RFC-0006-legacy.md")"
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --backfill \
      --path docs/rfc/RFC-0006-legacy.md > bf1.log 2>&1) \
    || log_fail "--backfill must exit 0: $(cat "$d/bf1.log")"
  assert_file "$d/docs/rfc/RFC-0006-legacy.md"   # no rename
  grep -qE '^number:[[:space:]]*6[[:space:]]*$' "$d/docs/rfc/RFC-0006-legacy.md" \
    || log_fail "--backfill must stamp number: 6 from the filename"
  # body content byte-preserved (title line intact)
  assert_contains "$d/docs/rfc/RFC-0006-legacy.md" "# Legacy numbered doc without a number field"
  # second run byte-identical (idempotent)
  local snap1; snap1="$(shasum "$d/docs/rfc/RFC-0006-legacy.md" | awk '{print $1}')"
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --backfill \
      --path docs/rfc/RFC-0006-legacy.md > bf2.log 2>&1) \
    || log_fail "second --backfill must exit 0"
  local snap2; snap2="$(shasum "$d/docs/rfc/RFC-0006-legacy.md" | awk '{print $1}')"
  [[ "$snap1" == "$snap2" ]] || log_fail "--backfill must be idempotent (byte-identical on re-run)"
  # a doc already carrying the correct number is untouched
  cat > "$d/docs/rfc/RFC-0005-already.md" <<'MD'
---
id: already
type: rfc
number: 5
status: done
links:
  pr: []
---
# Already numbered
MD
  local pre; pre="$(shasum "$d/docs/rfc/RFC-0005-already.md" | awk '{print $1}')"
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --backfill \
      --path docs/rfc/RFC-0005-already.md > bf3.log 2>&1) \
    || log_fail "--backfill on an already-correct doc must exit 0"
  local post; post="$(shasum "$d/docs/rfc/RFC-0005-already.md" | awk '{print $1}')"
  [[ "$pre" == "$post" ]] || log_fail "an already-correct doc must be byte-untouched by --backfill"
  rm -rf "$d"
  log_pass "TEST-011 backfill stamps from filename, no rename, idempotent"
}

# --- TEST-012: wiring grep ---------------------------------------------------
test_012_wiring() {
  log_info "TEST-012: SKILL_PR + SKILL_INTAKE + INTAKE_* + templates + pre-commit host wiring..."
  local pr="$PROJECT_ROOT/.aai/SKILL_PR.prompt.md"
  local intake="$PROJECT_ROOT/.aai/SKILL_INTAKE.prompt.md"
  assert_file "$pr"; assert_file "$intake"
  # SKILL_PR invokes the allocator before staging, per in-scope --path (FIX 7):
  # a blanket --all would sweep in out-of-scope drafts left behind in inline mode.
  grep -qF "allocate-doc-number.mjs" "$pr" \
    || log_fail "SKILL_PR must invoke allocate-doc-number.mjs"
  grep -qE "allocate-doc-number\.mjs.*--path" "$pr" \
    || log_fail "SKILL_PR must invoke the allocator per in-scope --path"
  if grep -qE "allocate-doc-number\.mjs.*--all" "$pr"; then
    log_fail "SKILL_PR must NOT invoke the allocator with a blanket --all (out-of-scope sweep)"
  fi
  # SKILL_INTAKE (+ INTAKE_*) create *-DRAFT-* with number: null. Since
  # CHANGE-0011 the DURABLE DOC IDENTITY block is single-sourced in
  # .aai/INTAKE_COMMON.md and the intake prompts reference it.
  local common="$PROJECT_ROOT/.aai/INTAKE_COMMON.md"
  assert_file "$common"
  grep -qF "DRAFT" "$common" || log_fail "INTAKE_COMMON.md must reference the DRAFT filename convention"
  grep -qF "number: null" "$common" || log_fail "INTAKE_COMMON.md must set number: null on intake"
  grep -qF "INTAKE_COMMON.md" "$intake" \
    || log_fail "SKILL_INTAKE must reference INTAKE_COMMON.md (single-sourced DRAFT identity block)"
  local wired=0 f
  for f in "$PROJECT_ROOT"/.aai/INTAKE_*.prompt.md; do
    if grep -qF "INTAKE_COMMON.md" "$f"; then
      wired=$((wired+1))
    fi
  done
  [[ "$wired" -ge 1 ]] || log_fail "at least one INTAKE_*.prompt.md must reference INTAKE_COMMON.md"
  # templates carry a number field + slug-as-primary-key note
  local rfct="$PROJECT_ROOT/.aai/templates/RFC_TEMPLATE.md"
  local spect="$PROJECT_ROOT/.aai/templates/SPEC_TEMPLATE.md"
  assert_file "$rfct"; assert_file "$spect"
  grep -qE '^number:' "$rfct" || log_fail "RFC_TEMPLATE must carry a number field"
  grep -qE '^number:' "$spect" || log_fail "SPEC_TEMPLATE must carry a number field"
  grep -qiE "slug.*(primary key|canonical|stable id)|primary key" "$rfct" \
    || log_fail "RFC_TEMPLATE must note slug-as-primary-key"
  grep -qiE "slug.*(primary key|canonical|stable id)|primary key" "$spect" \
    || log_fail "SPEC_TEMPLATE must note slug-as-primary-key"
  # pre-commit host references both guards
  local host="$PROJECT_ROOT/.aai/scripts/pre-commit-checks.sh"
  assert_file "$host"
  grep -qiE "no-?draft|DRAFT" "$host" || log_fail "pre-commit host must reference the no-DRAFT guard"
  grep -qiE "duplicate.?number|--guard" "$host" || log_fail "pre-commit host must reference the duplicate-number guard"
  # CI mirror of the guards (FIX 8 / SPEC-0015 D6 "mirrored in CI")
  local wf="$PROJECT_ROOT/.github/workflows/docs-numbering.yml"
  assert_file "$wf"
  grep -qF "allocate-doc-number.mjs --guard" "$wf" \
    || log_fail "CI workflow must run the allocator --guard"
  grep -qF "docs-audit.mjs" "$wf" \
    || log_fail "CI workflow must run docs-audit --check"
  grep -qF "fetch-depth: 0" "$wf" \
    || log_fail "CI workflow must checkout full history (fetch-depth: 0)"
  grep -qiE "continue-on-error:[[:space:]]*true|report-only" "$wf" \
    || log_fail "CI workflow must be report-only by default (non-blocking)"
  log_pass "TEST-012 wiring present across PR/intake/templates/pre-commit host/CI mirror"
}

# --- TEST-013: regression backstop ------------------------------------------
test_013_regression() {
  log_info "TEST-013: repo docs-audit CLEAN + index byte-idempotent (regression backstop)..."
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event \
      > "$TEST_DIR/repo-audit.log" 2>&1) \
    || log_fail "repo docs-audit --check --strict --no-event must be CLEAN (exit 0): $(tail -5 "$TEST_DIR/repo-audit.log")"
  assert_contains "$TEST_DIR/repo-audit.log" "CLEAN"
  # index byte-idempotent on the real repo (does not stage; compares regen output)
  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs > /dev/null 2>&1) \
    || log_fail "repo index gen (run 1) failed"
  grep -v '^Generated:' "$PROJECT_ROOT/docs/INDEX.md" > "$TEST_DIR/repo-run1.snap"
  (cd "$PROJECT_ROOT" && node .aai/scripts/generate-docs-index.mjs > /dev/null 2>&1) \
    || log_fail "repo index gen (run 2) failed"
  grep -v '^Generated:' "$PROJECT_ROOT/docs/INDEX.md" > "$TEST_DIR/repo-run2.snap"
  diff -q "$TEST_DIR/repo-run1.snap" "$TEST_DIR/repo-run2.snap" >/dev/null \
    || log_fail "repo index must be byte-idempotent modulo Generated"
  log_pass "TEST-013 repo docs-audit CLEAN + index byte-idempotent"
}

# --- TEST-014: CRLF frontmatter preserved on stamp -------------------------
test_014_crlf_stamp() {
  log_info "TEST-014: a CRLF DRAFT is stamped and its \\r\\n endings preserved byte-for-byte..."
  local d; d="$(setup_iso_repo t014)"
  seed_rfcs "$d" 6
  (cd "$d" && git checkout -q -b feature/crlf)
  # Build a DRAFT with CRLF (\r\n) line endings byte-for-byte (%b interprets \r\n).
  printf '%b' '---\r\nid: crlf-topic\r\ntype: rfc\r\nnumber: null\r\nstatus: draft\r\nlinks:\r\n  pr: []\r\n---\r\n# CRLF draft body\r\nSecond line\r\n' \
    > "$d/docs/rfc/RFC-DRAFT-crlf-topic.md"
  # sanity: the fixture really is CRLF (equal \r and \n counts, both > 0)
  local cr0 lf0
  cr0="$(tr -cd '\r' < "$d/docs/rfc/RFC-DRAFT-crlf-topic.md" | wc -c | tr -d ' ')"
  lf0="$(tr -cd '\n' < "$d/docs/rfc/RFC-DRAFT-crlf-topic.md" | wc -c | tr -d ' ')"
  [[ "$cr0" == "$lf0" && "$cr0" -gt 0 ]] || log_fail "fixture must be CRLF (cr=$cr0 lf=$lf0)"
  (cd "$d" && git add docs/rfc && git commit -qm "docs: crlf draft" >/dev/null)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-crlf-topic.md --base-ref main > crlf.log 2>&1) \
    || log_fail "allocator must stamp a CRLF draft (not silently skip): $(cat "$d/crlf.log")"
  local out="$d/docs/rfc/RFC-0007-crlf-topic.md"
  assert_file "$out"
  [[ ! -f "$d/docs/rfc/RFC-DRAFT-crlf-topic.md" ]] || log_fail "CRLF DRAFT must be renamed away"
  # number stamped (the bug: a CRLF file silently returned null -> no number)
  grep -qF "number: 7" "$out" || log_fail "CRLF draft must be stamped number: 7"
  grep -qF "id: crlf-topic" "$out" || log_fail "id must stay the slug"
  grep -qF "# CRLF draft body" "$out" || log_fail "body must be preserved"
  # CRLF preserved byte-for-byte: every \n still paired with a \r, none dropped.
  local cr1 lf1
  cr1="$(tr -cd '\r' < "$out" | wc -c | tr -d ' ')"
  lf1="$(tr -cd '\n' < "$out" | wc -c | tr -d ' ')"
  [[ "$cr1" == "$lf1" ]] || log_fail "CRLF must be preserved after stamp (cr=$cr1 lf=$lf1 — a bare LF leaked)"
  # the fixture already carried `number: null`, so stampNumber REPLACES that line
  # in place (no line added/removed): the CRLF count is unchanged byte-for-byte.
  [[ "$cr1" -eq "$cr0" ]] || log_fail "in-place number replace must not change line count (cr0=$cr0 cr1=$cr1)"
  # INSERT branch: a CRLF draft with NO `number` field -> number inserted after id
  # with a CRLF-terminated line (not a bare LF).
  printf '%b' '---\r\nid: crlf-insert\r\ntype: rfc\r\nstatus: draft\r\nlinks:\r\n  pr: []\r\n---\r\n# body\r\n' \
    > "$d/docs/rfc/RFC-DRAFT-crlf-insert.md"
  local cr2; cr2="$(tr -cd '\r' < "$d/docs/rfc/RFC-DRAFT-crlf-insert.md" | wc -c | tr -d ' ')"
  (cd "$d" && git add docs/rfc && git commit -qm "docs: crlf insert draft" >/dev/null)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-crlf-insert.md --base-ref main > crlf2.log 2>&1) \
    || log_fail "allocator must stamp a CRLF draft with no number field: $(cat "$d/crlf2.log")"
  local out2="$d/docs/rfc/RFC-0008-crlf-insert.md"
  assert_file "$out2"
  grep -qF "number: 8" "$out2" || log_fail "inserted number must be 8"
  local cr3 lf3
  cr3="$(tr -cd '\r' < "$out2" | wc -c | tr -d ' ')"
  lf3="$(tr -cd '\n' < "$out2" | wc -c | tr -d ' ')"
  [[ "$cr3" == "$lf3" ]] || log_fail "inserted number line must be CRLF-terminated (cr=$cr3 lf=$lf3 — bare LF leaked)"
  [[ "$cr3" -eq $((cr2 + 1)) ]] || log_fail "insert must add exactly one CRLF line (cr2=$cr2 cr3=$cr3)"
  rm -rf "$d"
  log_pass "TEST-014 CRLF draft stamped (replace + insert), \\r\\n endings preserved byte-for-byte"
}

# --- TEST-015: guard honors the staged/merged tree --------------------------
test_015_guard_staged_only() {
  log_info "TEST-015: an UNTRACKED draft does NOT trip the guard; a STAGED draft does..."
  local d; d="$(setup_iso_repo t015)"
  seed_rfcs "$d" 6   # tracked + committed -> clean numbered tree
  # (a) a purely-untracked local draft must NOT trip the guard (SPEC-0015 D6:
  # the guard checks the staged/merged tree, not the raw working dir).
  write_draft "$d" rfc RFC untracked-draft
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --guard > guard-untracked.log 2>&1) \
    || log_fail "an UNTRACKED draft must NOT trip the guard: $(cat "$d/guard-untracked.log")"
  # (b) once STAGED, the same draft must trip the guard, naming it.
  (cd "$d" && git add docs/rfc/RFC-DRAFT-untracked-draft.md)
  set +e
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --guard > guard-staged.log 2>&1)
  local rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || log_fail "a STAGED draft must trip the guard"
  assert_contains "$d/guard-staged.log" "RFC-DRAFT-untracked-draft"
  rm -rf "$d"
  log_pass "TEST-015 guard honors staged/merged tree (untracked ignored, staged caught)"
}

test_016_per_type_digit_width() {  # ISSUE per-type-digit-width AC-001..004
  log_info "TEST-016: number width follows the type's existing convention (PRD 3-digit)..."
  local d; d="$(setup_iso_repo t016)"

  # AC-001: existing PRD-001 -> next allocation is PRD-002 (3-digit inherited)
  mkdir -p "$d/docs/requirements"
  cat > "$d/docs/requirements/PRD-001-legacy-feature.md" <<'MD'
---
id: PRD-001
type: prd
status: done
links:
  pr: []
---
# Legacy 3-digit PRD
MD
  (cd "$d" && git add docs && git commit -qm "docs: legacy 3-digit PRD" >/dev/null)
  (cd "$d" && git checkout -q -b feature/prd-width)
  write_draft "$d" requirements PRD next-feature
  (cd "$d" && git add docs && git commit -qm "docs: PRD draft" >/dev/null)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/requirements/PRD-DRAFT-next-feature.md --base-ref main \
      > alloc1.log 2>&1) \
    || log_fail "PRD allocation must exit 0: $(cat "$d/alloc1.log")"
  assert_file "$d/docs/requirements/PRD-002-next-feature.md"
  [[ ! -f "$d/docs/requirements/PRD-0002-next-feature.md" ]] \
    || log_fail "must inherit 3-digit width (PRD-002), not mint PRD-0002"

  # AC-003: index display id is filename-verbatim (PRD-001, never PRD-0001)
  (cd "$d" && node .aai/scripts/generate-docs-index.mjs >/dev/null 2>&1)
  assert_contains "$d/docs/INDEX.md" "PRD-001"
  assert_not_contains "$d/docs/INDEX.md" "PRD-0001"

  # AC-002a: empty PRD type defaults to 3-digit (PRD-001)
  local d2; d2="$(setup_iso_repo t016b)"
  (cd "$d2" && git checkout -q -b feature/prd-first)
  mkdir -p "$d2/docs/requirements"
  write_draft "$d2" requirements PRD first-ever
  (cd "$d2" && git add docs && git commit -qm "docs: first PRD draft" >/dev/null)
  (cd "$d2" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/requirements/PRD-DRAFT-first-ever.md --base-ref main \
      > alloc2.log 2>&1) \
    || log_fail "first-PRD allocation must exit 0: $(cat "$d2/alloc2.log")"
  assert_file "$d2/docs/requirements/PRD-001-first-ever.md"

  # AC-002b: regression — RFC keeps 4-digit inheritance (seeded RFC-0006 -> 0007)
  seed_rfcs "$d2" 6
  (cd "$d2" && git add docs && git commit -qm "docs: seed rfcs" >/dev/null)
  write_draft "$d2" rfc RFC four-digit-regression
  (cd "$d2" && git add docs && git commit -qm "docs: rfc draft" >/dev/null)
  (cd "$d2" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-four-digit-regression.md --base-ref feature/prd-first \
      > alloc3.log 2>&1) \
    || log_fail "RFC allocation must exit 0: $(cat "$d2/alloc3.log")"
  assert_file "$d2/docs/rfc/RFC-0007-four-digit-regression.md"

  # AC-004: duplicate guard still flags PRD-001 vs PRD-0001 (numeric equality)
  cat > "$d/docs/requirements/PRD-0001-imposter.md" <<'MD'
---
id: imposter
type: prd
number: 1
status: draft
links:
  pr: []
---
# Imposter with same numeric id, different padding
MD
  (cd "$d" && git add docs/requirements/PRD-0001-imposter.md)
  local ec=0
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs --guard > guard.log 2>&1) || ec=$?
  [[ "$ec" != 0 ]] || log_fail "duplicate guard must flag PRD-001 vs PRD-0001: $(cat "$d/guard.log")"
  grep -q "PRD-001-legacy-feature.md" "$d/guard.log" && grep -q "PRD-0001-imposter.md" "$d/guard.log" \
    || log_fail "guard message must name both offending files: $(cat "$d/guard.log")"

  rm -rf "$d" "$d2"
  log_pass "TEST-016 width inherited (PRD-002), empty-type default PRD-001, RFC stays 4-digit, cross-padding duplicate flagged"
}

test_017_project_dominant_width() {  # ISSUE project-dominant-width AC-001..004
  log_info "TEST-017: empty-type width falls back to the PROJECT's dominant width..."
  local d; d="$(setup_iso_repo t017)"

  # Fixture: an all-3-digit project (two types), no RFC docs at all.
  mkdir -p "$d/docs/requirements" "$d/docs/issues"
  cat > "$d/docs/requirements/PRD-001-legacy.md" <<'MD'
---
id: PRD-001
type: prd
status: done
links:
  pr: []
---
# 3-digit PRD
MD
  cat > "$d/docs/issues/ISSUE-042-legacy.md" <<'MD'
---
id: ISSUE-042
type: issue
status: done
links:
  pr: []
---
# 3-digit ISSUE
MD
  (cd "$d" && git add docs && git commit -qm "docs: all-3-digit project" >/dev/null)
  (cd "$d" && git checkout -q -b feature/first-rfc)
  write_draft "$d" rfc RFC first-rfc-ever
  (cd "$d" && git add docs && git commit -qm "docs: first RFC draft" >/dev/null)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/rfc/RFC-DRAFT-first-rfc-ever.md --base-ref main \
      > alloc.log 2>&1) \
    || log_fail "first-RFC allocation must exit 0: $(cat "$d/alloc.log")"
  # AC-001: dominant project width (3) wins over the generic 4-digit default
  assert_file "$d/docs/rfc/RFC-001-first-rfc-ever.md"
  [[ ! -f "$d/docs/rfc/RFC-0001-first-rfc-ever.md" ]] \
    || log_fail "empty type in a 3-digit project must mint RFC-001, not RFC-0001"

  # AC-003: type-own inheritance beats project-dominant (4-digit SPEC type
  # in the same mostly-3-digit project keeps 4-digit).
  mkdir -p "$d/docs/specs"
  cat > "$d/docs/specs/SPEC-0009-legacy.md" <<'MD'
---
id: SPEC-0009
type: spec
status: done
links:
  pr: []
---
# 4-digit SPEC
MD
  (cd "$d" && git add docs && git commit -qm "docs: 4-digit spec" >/dev/null)
  write_draft "$d" specs SPEC next-spec
  (cd "$d" && git add docs && git commit -qm "docs: spec draft" >/dev/null)
  (cd "$d" && node .aai/scripts/allocate-doc-number.mjs \
      --path docs/specs/SPEC-DRAFT-next-spec.md --base-ref feature/first-rfc \
      > alloc2.log 2>&1) \
    || log_fail "SPEC allocation must exit 0: $(cat "$d/alloc2.log")"
  assert_file "$d/docs/specs/SPEC-0010-next-spec.md"

  # AC-002/AC-004 regression: this template repo's layout (t016 already covers
  # empty-PRD greenfield default 3 and RFC 4-digit inheritance).
  rm -rf "$d"
  log_pass "TEST-017 project-dominant width for empty types; type-own inheritance still wins"
}

# --- TEST-018: doc_number_guard enforce flip -----------------------------
# spec-learned-to-layer-promotion Spec-AC-03: the repo default is now enforce,
# and the enforce path is safe for the DRAFT-carrying development flow because
# the guard evaluates the STAGED/MERGED tree (git ls-files, SPEC-0015 D6 /
# CHANGE-0012 FIX 3) and /aai-pr allocates numbers BEFORE staging — so a
# staged tree is DRAFT-free by construction and untracked working-tree drafts
# never block a commit. Drives the REAL pre-commit host end-to-end.
test_018_enforce_flip() {
  log_info "TEST-018: repo dial = enforce; host passes numbered staged tree, blocks staged DRAFT loud..."
  # (a) the repo's committed default is enforce
  grep -Eq '^doc_number_guard:[[:space:]]*enforce([[:space:]]|$)' \
      "$PROJECT_ROOT/docs/ai/docs-audit.yaml" \
    || log_fail "docs/ai/docs-audit.yaml must set doc_number_guard: enforce (RED: still report-only)"
  local d; d="$(setup_iso_repo t018)"
  seed_rfcs "$d" 4
  mkdir -p "$d/docs/ai"
  printf 'doc_number_guard: enforce\n' > "$d/docs/ai/docs-audit.yaml"
  # (b) enforce + fully-numbered STAGED tree -> host exits 0
  cat > "$d/docs/rfc/RFC-0005-numbered-scope.md" <<'MD'
---
id: numbered-scope
type: rfc
number: 5
status: draft
links:
  pr: []
---
# Numbered in-scope doc
MD
  (cd "$d" && git add docs/rfc/RFC-0005-numbered-scope.md docs/ai/docs-audit.yaml)
  (cd "$d" && bash .aai/scripts/pre-commit-checks.sh > pc-numbered.log 2>&1) \
    || log_fail "enforce + staged numbered tree must pass the host: $(tail -8 "$d/pc-numbered.log")"
  # (c) an UNTRACKED working-tree draft must NOT block (dev flow before allocation)
  write_draft "$d" rfc RFC in-flight-dev-draft
  (cd "$d" && bash .aai/scripts/pre-commit-checks.sh > pc-untracked.log 2>&1) \
    || log_fail "enforce + UNTRACKED draft must still pass (guard reads the staged tree): $(tail -8 "$d/pc-untracked.log")"
  # (d) enforce + STAGED draft -> host blocks loud (exit 1, names the draft + the dial)
  (cd "$d" && git add docs/rfc/RFC-DRAFT-in-flight-dev-draft.md)
  set +e
  (cd "$d" && bash .aai/scripts/pre-commit-checks.sh > pc-draft.log 2>&1)
  local rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || log_fail "enforce + STAGED draft must block the commit (exit 1)"
  assert_contains "$d/pc-draft.log" "RFC-DRAFT-in-flight-dev-draft"
  assert_contains "$d/pc-draft.log" "doc_number_guard: enforce"
  rm -rf "$d"
  log_pass "TEST-018 enforce flip: numbered staged tree passes, untracked draft ignored, staged DRAFT blocks loud"
}

main() {
  echo ""
  echo "AAI Doc-Numbering Test Suite (SPEC-0015 / RFC-0007)"
  echo "==================================================="
  echo ""
  check_deps
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-doc-numbering-test.XXXXXX")"

  test_001_slug_and_filename
  test_002_collision_suffix
  test_003_draft_passes_audit_and_index
  test_004_allocator_renames
  test_005_exit_codes
  test_006_concurrency
  test_007_no_draft_guard
  test_008_duplicate_guard
  test_009_index_display_id
  test_010_allocator_absent_fallback
  test_011_backfill
  test_012_wiring
  test_013_regression
  test_014_crlf_stamp
  test_015_guard_staged_only
  test_016_per_type_digit_width
  test_017_project_dominant_width
  test_018_enforce_flip

  echo ""
  echo "All doc-numbering tests passed."
}

main "$@"
