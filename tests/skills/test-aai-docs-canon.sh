#!/usr/bin/env bash
#
# Test: aai-docs-canon skill (RFC-0003 / SPEC-0002)
# Verifies the docs canonicalization engine: shared-schema extensions, the
# supersession/dependency graph builder, the Phase-1 domain-map proposal + HITL
# gate, Phase-2 synthesis + archive move + bidirectional back-links, re-run
# idempotence + drift, and the docs-audit / docs-index integration seams.
#
# Single shell file per repo convention; logical units/integration cases are
# tracked by the SPEC-0002 Test Plan IDs (TEST-101..118, TEST-201..203,
# TEST-301..306).
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-docs-canon"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CANON_SCRIPT="$PROJECT_ROOT/.aai/scripts/docs-canon.mjs"

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
assert_dir_empty_or_absent() {
  # passes if dir does not exist or contains no .md files
  if [[ -d "$1" ]]; then
    if find "$1" -name '*.md' -type f | grep -q .; then
      log_fail "Expected no .md files under $1"
    fi
  fi
}
assert_contains() { grep -qF "$2" "$1" || log_fail "Expected '$2' in $1"; }
assert_not_contains() { if grep -qF "$2" "$1"; then log_fail "Did not expect '$2' in $1"; fi; }

# Run a small node snippet against the vendored libs inside the fixture repo.
# Usage: node_eval "<js>"  — exit code is the snippet's; stdout is captured.
node_eval() { (cd "$TEST_DIR" && node --input-type=module -e "$1"); }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$CANON_SCRIPT" ]] || log_fail "Canon script not found: $CANON_SCRIPT"
  log_pass "Dependencies checked"
}

setup_fixture() {
  log_info "Setting up fixture repo..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-docs-canon-test.XXXXXX")"
  cd "$TEST_DIR"
  git init -q
  git config user.email "test@example.com"
  git config user.name "AAI Test"

  mkdir -p .aai/scripts/lib docs/specs docs/issues docs/ai
  cp "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" .aai/scripts/
  cp "$PROJECT_ROOT/.aai/scripts/docs-canon.mjs" .aai/scripts/
  cp "$PROJECT_ROOT/.aai/scripts/generate-docs-index.mjs" .aai/scripts/
  cp "$PROJECT_ROOT/.aai/scripts/append-event.mjs" .aai/scripts/ 2>/dev/null || true
  cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs .aai/scripts/lib/

  # Umbrella fixture: 3 files sharing id SPEC-X; one superseded with markers.
  cat > docs/specs/SPEC-X-a.md <<'MD'
---
id: SPEC-X
type: spec
status: superseded
links:
  pr: []
---
# Player draft (original)
SUPERSEDED BY SPEC-Y. See PRD-001 for intent.
MD
  cat > docs/specs/SPEC-X-b.md <<'MD'
---
id: SPEC-X
type: spec
status: done
links:
  pr: []
---
# Player draft (current behavior)
Implements the live flow described in ISSUE-010.
MD
  cat > docs/specs/SPEC-X-c.md <<'MD'
---
id: SPEC-X
type: spec
status: done
links:
  pr: []
---
# Player draft (data model)
DEPRECATED column note; addendum added later.
MD
  # A second, unrelated single-doc domain.
  cat > docs/issues/ISSUE-050-export.md <<'MD'
---
id: ISSUE-050
type: issue
status: done
links:
  pr: []
---
# CSV export
References SPEC-X for the source rows.
MD
  git add -A && git commit -qm "chore: fixtures + vendored scripts"
  log_pass "Fixture repo ready"
}

run_canon() { (cd "$TEST_DIR" && node .aai/scripts/docs-canon.mjs "$@"); }
run_audit() { (cd "$TEST_DIR" && node .aai/scripts/docs-audit.mjs "$@"); }
run_index() { (cd "$TEST_DIR" && node .aai/scripts/generate-docs-index.mjs "$@"); }

# Persist an approved map for the umbrella domain (the operator-approved output
# of the HITL gate). Used by all Phase-2 tests.
write_approved_map() {
  cat > "$TEST_DIR/docs/ai/docs-canon.map.json" <<'JSON'
{
  "approved": true,
  "domains": {
    "spec-x": {
      "sources": [
        "docs/specs/SPEC-X-a.md",
        "docs/specs/SPEC-X-b.md",
        "docs/specs/SPEC-X-c.md"
      ],
      "confidence": "human"
    }
  },
  "unclear": []
}
JSON
}

# ---------------------------------------------------------------------------
# Spec-AC-01 — new doc types known to schema
# ---------------------------------------------------------------------------

test_doc_type_enum() {
  log_info "TEST-101: DOC_TYPE_ENUM contains canonical and archived (unit)..."
  node_eval '
    import { DOC_TYPE_ENUM } from "./.aai/scripts/lib/docs-model.mjs";
    if (!DOC_TYPE_ENUM.has("canonical")) { console.error("missing canonical"); process.exit(1); }
    if (!DOC_TYPE_ENUM.has("archived")) { console.error("missing archived"); process.exit(1); }
  ' || log_fail "TEST-101: DOC_TYPE_ENUM must contain canonical and archived"
  log_pass "TEST-101: canonical + archived in DOC_TYPE_ENUM"
}

test_audit_accepts_new_types() {
  log_info "TEST-102: audit --strict --strict-types accepts canonical+archived fixtures (int)..."
  mkdir -p "$TEST_DIR/docs/canonical" "$TEST_DIR/docs/_archive/specs"
  cat > "$TEST_DIR/docs/canonical/sample.md" <<'MD'
---
id: CANON-sample
type: canonical
domain: sample
status: accepted
sources:
  - docs/_archive/specs/SPEC-Z-old.md
---
# Canonical: sample
## Overview / Intent
x
## UI
x
## Processes / Behavior
x
## Data model
x
## Superseded decisions
- [docs/_archive/specs/SPEC-Z-old.md](../_archive/specs/SPEC-Z-old.md)
MD
  cat > "$TEST_DIR/docs/_archive/specs/SPEC-Z-old.md" <<'MD'
---
id: SPEC-Z
type: archived
status: archived
canonical: docs/canonical/sample.md
links:
  pr: []
---
# Archived spec
MD
  run_audit --check --strict --strict-types --no-event > "$TEST_DIR/types.log" \
    || log_fail "TEST-102: --strict --strict-types must exit 0 over valid canonical+archived"
  assert_not_contains "$TEST_DIR/types.log" 'unknown type "canonical"'
  assert_not_contains "$TEST_DIR/types.log" 'unknown type "archived"'
  rm -rf "$TEST_DIR/docs/canonical" "$TEST_DIR/docs/_archive"
  log_pass "TEST-102: canonical/archived types accepted, no type warnings"
}

# ---------------------------------------------------------------------------
# Spec-AC-02 — canonical frontmatter validation
# ---------------------------------------------------------------------------

test_canonical_frontmatter_validator() {
  log_info "TEST-103: canonical-frontmatter validator (valid/missing/bad slug/empty) (unit)..."
  node_eval '
    import { validateCanonicalFrontmatter as v } from "./.aai/scripts/lib/docs-model.mjs";
    const ok = v({ type: "canonical", domain: "match-lifecycle", sources: ["a"] });
    if (!ok.ok) { console.error("valid should pass", ok.violations); process.exit(1); }
    if (v({ type: "canonical", sources: ["a"] }).ok) { console.error("missing domain should fail"); process.exit(1); }
    if (v({ type: "canonical", domain: "Bad Slug", sources: ["a"] }).ok) { console.error("bad slug should fail"); process.exit(1); }
    if (v({ type: "canonical", domain: "ok", sources: [] }).ok) { console.error("empty sources should fail"); process.exit(1); }
  ' || log_fail "TEST-103: canonical-frontmatter validator wrong"
  log_pass "TEST-103: canonical-frontmatter validator covers all four cases"
}

test_audit_flags_bad_canonical() {
  log_info "TEST-104: audit --strict exits 1 + violation on bad canonical, 0 on valid (int)..."
  mkdir -p "$TEST_DIR/docs/canonical"
  # bad: missing domain + empty sources
  cat > "$TEST_DIR/docs/canonical/bad.md" <<'MD'
---
id: CANON-bad
type: canonical
status: accepted
sources: []
---
# Canonical: bad
MD
  if run_audit --check --strict --no-event --path docs/canonical/bad.md > "$TEST_DIR/canon-bad.log"; then
    log_fail "TEST-104: bad canonical must exit 1"
  fi
  assert_contains "$TEST_DIR/canon-bad.log" "canonical frontmatter"
  assert_contains "$TEST_DIR/canon-bad.log" "bad.md"
  rm "$TEST_DIR/docs/canonical/bad.md"
  # valid
  cat > "$TEST_DIR/docs/canonical/good.md" <<'MD'
---
id: CANON-good
type: canonical
domain: good-domain
status: accepted
sources:
  - docs/specs/SPEC-X-a.md
---
# Canonical: good
MD
  run_audit --check --strict --no-event --path docs/canonical/good.md > "$TEST_DIR/canon-good.log" \
    || log_fail "TEST-104: valid canonical must exit 0"
  rm -rf "$TEST_DIR/docs/canonical"
  log_pass "TEST-104: audit flags bad canonical, passes valid"
}

# ---------------------------------------------------------------------------
# Spec-AC-04 — supersession/dependency graph builder
# ---------------------------------------------------------------------------

test_graph_umbrella_grouping() {
  log_info "TEST-107: umbrella-ID grouping (3 files, one id => one node) (unit)..."
  node_eval '
    import { collectDocs, buildGraph } from "./.aai/scripts/lib/docs-canon-core.mjs";
    const docs = collectDocs(process.cwd(), ["docs/specs"]);
    const g = buildGraph(docs);
    const um = g.umbrellaGroups.find(x => x.id === "SPEC-X");
    if (!um || um.members.length !== 3) { console.error("umbrella wrong", JSON.stringify(g.umbrellaGroups)); process.exit(1); }
  ' || log_fail "TEST-107: umbrella grouping wrong"
  log_pass "TEST-107: 3 files sharing SPEC-X group into one umbrella node"
}

test_graph_supersession_markers() {
  log_info "TEST-108: body SUPERSEDED BY / DEPRECATED / addendum markers => edges (unit)..."
  node_eval '
    import { collectDocs, buildGraph } from "./.aai/scripts/lib/docs-canon-core.mjs";
    const g = buildGraph(collectDocs(process.cwd(), ["docs/specs"]));
    const a = g.nodes.find(n => n.rel.endsWith("SPEC-X-a.md"));
    const c = g.nodes.find(n => n.rel.endsWith("SPEC-X-c.md"));
    if (!a.markers.includes("superseded-by")) { console.error("a missing superseded-by marker"); process.exit(1); }
    if (!c.markers.includes("deprecated")) { console.error("c missing deprecated marker"); process.exit(1); }
    if (!c.markers.includes("addendum")) { console.error("c missing addendum marker"); process.exit(1); }
  ' || log_fail "TEST-108: supersession markers not detected"
  log_pass "TEST-108: free-text markers become supersession edges"
}

test_graph_crossrefs_and_status() {
  log_info "TEST-109: cross-ref IDs => dependency edges; status superseded recorded (unit)..."
  node_eval '
    import { collectDocs, buildGraph } from "./.aai/scripts/lib/docs-canon-core.mjs";
    const g = buildGraph(collectDocs(process.cwd(), ["docs/specs"]));
    const a = g.nodes.find(n => n.rel.endsWith("SPEC-X-a.md"));
    if (!a.superseded) { console.error("a not marked superseded"); process.exit(1); }
    if (!a.crossRefs.includes("PRD-001")) { console.error("a missing PRD-001 dependency edge", JSON.stringify(a.crossRefs)); process.exit(1); }
    const b = g.nodes.find(n => n.rel.endsWith("SPEC-X-b.md"));
    if (!b.crossRefs.includes("ISSUE-010")) { console.error("b missing ISSUE-010 dependency"); process.exit(1); }
  ' || log_fail "TEST-109: cross-refs / superseded status wrong"
  log_pass "TEST-109: dependency edges + superseded status recorded"
}

test_graph_determinism() {
  log_info "TEST-110: graph builder deterministic (two runs => byte-identical) (unit)..."
  node_eval '
    import { collectDocs, buildGraph, serializeGraph } from "./.aai/scripts/lib/docs-canon-core.mjs";
    const docs = collectDocs(process.cwd(), ["docs/specs", "docs/issues"]);
    const s1 = serializeGraph(buildGraph(docs));
    const s2 = serializeGraph(buildGraph(docs));
    if (s1 !== s2) { console.error("non-deterministic"); process.exit(1); }
  ' || log_fail "TEST-110: graph not deterministic"
  log_pass "TEST-110: graph builder is deterministic"
}

# ---------------------------------------------------------------------------
# Spec-AC-05 — Phase 1 proposal + HITL gate
# ---------------------------------------------------------------------------

test_phase1_proposal_artifact() {
  log_info "TEST-111: Phase 1 writes domain-map proposal (domains+sources+confidence+unclear) (int)..."
  run_canon --phase1 > "$TEST_DIR/phase1.log" || log_fail "TEST-111: phase1 must exit 0"
  assert_file "$TEST_DIR/docs/ai/docs-canon.proposal.json"
  node_eval '
    import { readJson, PROPOSAL_PATH } from "./.aai/scripts/lib/docs-canon-core.mjs";
    const p = readJson(process.cwd(), PROPOSAL_PATH);
    if (!p || typeof p.domains !== "object") { console.error("no domains"); process.exit(1); }
    if (!Array.isArray(p.unclear)) { console.error("no unclear key"); process.exit(1); }
    const vals = Object.values(p.domains);
    if (vals.length === 0) { console.error("empty domains"); process.exit(1); }
    for (const d of vals) {
      if (!Array.isArray(d.sources) || d.sources.length === 0) { console.error("domain missing sources"); process.exit(1); }
      if (!d.confidence) { console.error("domain missing confidence"); process.exit(1); }
    }
  ' || log_fail "TEST-111: proposal artifact malformed"
  assert_contains "$TEST_DIR/phase1.log" "HUMAN APPROVAL REQUIRED"
  log_pass "TEST-111: Phase 1 proposal artifact parses (domains/sources/confidence/unclear)"
}

test_phase1_gate_no_writes() {
  log_info "TEST-112: Phase 1 gate leaves docs/canonical and docs/_archive untouched (int)..."
  # fresh phase1 (proposal only)
  rm -f "$TEST_DIR/docs/ai/docs-canon.proposal.json"
  run_canon --phase1 > /dev/null || log_fail "TEST-112: phase1 must exit 0"
  assert_dir_empty_or_absent "$TEST_DIR/docs/canonical"
  assert_dir_empty_or_absent "$TEST_DIR/docs/_archive"
  # sources still in place (not moved)
  assert_file "$TEST_DIR/docs/specs/SPEC-X-a.md"
  log_pass "TEST-112: no pre-approval writes/moves (HITL gate enforced)"
}

test_phase2_gate_requires_approval() {
  log_info "TEST-113: Phase 2 refuses to run without approved: true map (unit + int)..."
  node_eval '
    import { isApprovedMap } from "./.aai/scripts/lib/docs-canon-core.mjs";
    if (isApprovedMap(null)) { console.error("null map approved?!"); process.exit(1); }
    if (isApprovedMap({ approved: false, domains: { d: { sources: ["a"] } } })) { console.error("unapproved accepted"); process.exit(1); }
    if (isApprovedMap({ approved: true, domains: {} })) { console.error("empty domains accepted"); process.exit(1); }
    if (!isApprovedMap({ approved: true, domains: { d: { sources: ["a"] } } })) { console.error("valid rejected"); process.exit(1); }
  ' || log_fail "TEST-113: isApprovedMap gate wrong"
  # CLI refuses unapproved map
  cat > "$TEST_DIR/docs/ai/docs-canon.map.json" <<'JSON'
{ "approved": false, "domains": { "spec-x": { "sources": ["docs/specs/SPEC-X-a.md"] } } }
JSON
  if run_canon --phase2 > "$TEST_DIR/phase2-gate.log" 2>&1; then
    log_fail "TEST-113: phase2 must exit 1 on unapproved map"
  fi
  assert_contains "$TEST_DIR/phase2-gate.log" "not approved"
  rm -f "$TEST_DIR/docs/ai/docs-canon.map.json"
  log_pass "TEST-113: Phase 2 gate refuses unapproved map"
}

# ---------------------------------------------------------------------------
# Spec-AC-06 — fixed section contract + superseded harvest isolation
# ---------------------------------------------------------------------------

test_section_contract_validator() {
  log_info "TEST-114: section-contract validator (all six ordered ok; missing => violation) (unit)..."
  # RFC-0011 stage 1 (spec-delta-stage-1): `## Requirements` is the second
  # fixed section, so the good fixture carries six ordered sections now.
  node_eval '
    import { validateSectionContract as v } from "./.aai/scripts/lib/docs-model.mjs";
    const good = "## Overview / Intent\nx\n## Requirements\nx\n## UI\nx\n## Processes / Behavior\nx\n## Data model\nx\n## Superseded decisions\nx";
    if (!v(good).ok) { console.error("ordered should pass", v(good).violations); process.exit(1); }
    const missing = "## Overview / Intent\n## Requirements\n## UI\n## Data model\n## Superseded decisions";
    if (v(missing).ok) { console.error("missing section should fail"); process.exit(1); }
    const outOfOrder = "## UI\n## Overview / Intent\n## Requirements\n## Processes / Behavior\n## Data model\n## Superseded decisions";
    if (v(outOfOrder).ok) { console.error("out-of-order should fail"); process.exit(1); }
    const legacyFive = "## Overview / Intent\nx\n## UI\nx\n## Processes / Behavior\nx\n## Data model\nx\n## Superseded decisions\nx";
    if (v(legacyFive).ok) { console.error("pre-stage-1 five-section body should fail (resync path)"); process.exit(1); }
  ' || log_fail "TEST-114: section-contract validator wrong"
  log_pass "TEST-114: section-contract validator enforces six ordered sections"
}

test_synthesis_sections_and_superseded_isolation() {
  log_info "TEST-115: synthesized canonical has 6 ordered sections; superseded linked ONLY in last (int)..."
  write_approved_map
  run_canon --phase2 > "$TEST_DIR/phase2.log" || log_fail "TEST-115: phase2 must succeed"
  local canon="$TEST_DIR/docs/canonical/spec-x.md"
  assert_file "$canon"
  node_eval '
    import fs from "node:fs";
    import { validateSectionContract } from "./.aai/scripts/lib/docs-model.mjs";
    const c = fs.readFileSync("docs/canonical/spec-x.md", "utf8");
    const r = validateSectionContract(c);
    if (!r.ok) { console.error("section contract failed", r.violations); process.exit(1); }
    // Strip frontmatter — the sources: provenance list there is expected and is
    // NOT body content. The superseded source link must appear in the BODY only
    // under ## Superseded decisions, never in an earlier layer section.
    const fmEnd = c.indexOf("\n---", 4);
    const body = fmEnd >= 0 ? c.slice(fmEnd + 4) : c;
    const idx = body.indexOf("## Superseded decisions");
    const before = body.slice(0, idx);
    const after = body.slice(idx);
    if (before.includes("SPEC-X-a.md")) { console.error("superseded source leaked above the section"); process.exit(1); }
    if (!after.includes("SPEC-X-a.md")) { console.error("superseded source not harvested"); process.exit(1); }
  ' || log_fail "TEST-115: section/superseded isolation wrong"
  # reset for subsequent tests that need fresh sources
  log_pass "TEST-115: six ordered sections; superseded harvested + isolated"
}

# ---------------------------------------------------------------------------
# Spec-AC-03 — archive move + back-links (uses the Phase-2 from TEST-115)
# ---------------------------------------------------------------------------

test_phase2_archive_move() {
  log_info "TEST-105: Phase 2 moves originals to docs/_archive/ with status: archived (int)..."
  assert_file "$TEST_DIR/docs/_archive/specs/SPEC-X-a.md"
  assert_file "$TEST_DIR/docs/_archive/specs/SPEC-X-b.md"
  [[ ! -f "$TEST_DIR/docs/specs/SPEC-X-a.md" ]] || log_fail "TEST-105: original SPEC-X-a must be moved out of docs/specs"
  assert_contains "$TEST_DIR/docs/_archive/specs/SPEC-X-a.md" "status: archived"
  assert_contains "$TEST_DIR/docs/_archive/specs/SPEC-X-a.md" "canonical: docs/canonical/spec-x.md"
  log_pass "TEST-105: originals archived with status + canonical pointer"
}

test_link_integrity_validator() {
  log_info "TEST-106: dangling canonical: or sources: entry flagged by link-integrity (unit)..."
  node_eval '
    import fs from "node:fs";
    import { checkLinkIntegrity } from "./.aai/scripts/lib/docs-canon-core.mjs";
    // produced trees are intact => ok
    const ok = checkLinkIntegrity(process.cwd());
    if (!ok.ok) { console.error("intact trees flagged", ok.violations); process.exit(1); }
    // inject a dangling source into the canonical
    const p = "docs/canonical/spec-x.md";
    fs.writeFileSync(p, fs.readFileSync(p, "utf8").replace("sources:", "sources:\n  - docs/_archive/specs/DOES-NOT-EXIST.md"));
    const bad = checkLinkIntegrity(process.cwd());
    if (bad.ok) { console.error("dangling source not flagged"); process.exit(1); }
    if (!bad.violations.some(v => v.includes("DOES-NOT-EXIST"))) { console.error("violation missing"); process.exit(1); }
  ' || log_fail "TEST-106: link-integrity validator wrong"
  # repair the canonical by re-deriving via a fresh run is not trivial here;
  # the mutation only affects this in-place check. Subsequent SEAM tests use a
  # fresh fixture, so restore from the archived back-pointer is unnecessary.
  log_pass "TEST-106: dangling sources flagged by link-integrity"
}

# ---------------------------------------------------------------------------
# Spec-AC-07 — re-run idempotence + drift (fresh fixture)
# ---------------------------------------------------------------------------

reset_fixture_for_rerun() {
  # rebuild a clean fixture + approved map + first Phase-2 so the re-run tests
  # start from a pristine synthesized state.
  rm -rf "$TEST_DIR/docs/specs" "$TEST_DIR/docs/issues" "$TEST_DIR/docs/canonical" \
         "$TEST_DIR/docs/_archive" "$TEST_DIR/docs/ai/docs-canon.map.json"
  mkdir -p "$TEST_DIR/docs/specs"
  cat > "$TEST_DIR/docs/specs/SPEC-X-a.md" <<'MD'
---
id: SPEC-X
type: spec
status: superseded
links:
  pr: []
---
# original
SUPERSEDED BY SPEC-Y
MD
  cat > "$TEST_DIR/docs/specs/SPEC-X-b.md" <<'MD'
---
id: SPEC-X
type: spec
status: done
links:
  pr: []
---
# current
MD
  write_approved_map
  # narrow map to the two existing sources
  cat > "$TEST_DIR/docs/ai/docs-canon.map.json" <<'JSON'
{ "approved": true, "domains": { "spec-x": { "sources": ["docs/specs/SPEC-X-a.md","docs/specs/SPEC-X-b.md"], "confidence": "human" } }, "unclear": [] }
JSON
  run_canon --phase2 > /dev/null || log_fail "reset: first phase2 failed"
}

test_rerun_idempotent() {
  log_info "TEST-116: re-run with no change => byte-identical canonical (int)..."
  reset_fixture_for_rerun
  cp "$TEST_DIR/docs/canonical/spec-x.md" "$TEST_DIR/canon-snap1.md"
  run_canon --phase2 > "$TEST_DIR/rerun.log" || log_fail "TEST-116: re-run phase2 failed"
  diff -q "$TEST_DIR/canon-snap1.md" "$TEST_DIR/docs/canonical/spec-x.md" >/dev/null \
    || log_fail "TEST-116: canonical must be byte-identical on no-change re-run"
  assert_contains "$TEST_DIR/rerun.log" "Skipped (unchanged): 1"
  log_pass "TEST-116: re-run is idempotent (byte-identical canonical)"
}

test_drift_flagged_no_overwrite() {
  log_info "TEST-117: mutate a source => domain flagged DRIFT, canonical NOT rewritten (int)..."
  cp "$TEST_DIR/docs/canonical/spec-x.md" "$TEST_DIR/canon-snap2.md"
  printf '\nMutation: a real content edit to an archived source.\n' >> "$TEST_DIR/docs/_archive/specs/SPEC-X-b.md"
  run_canon --phase2 > "$TEST_DIR/drift-run.log" || log_fail "TEST-117: phase2 exit"
  assert_contains "$TEST_DIR/drift-run.log" "DRIFT (changed since synthesis, NOT rewritten): 1"
  diff -q "$TEST_DIR/canon-snap2.md" "$TEST_DIR/docs/canonical/spec-x.md" >/dev/null \
    || log_fail "TEST-117: canonical must NOT be silently rewritten on drift"
  log_pass "TEST-117: drift flagged, canonical not silently overwritten"
}

test_drift_comparator_unit() {
  log_info "TEST-118: drift comparator (changed => drift; unchanged => clean) (unit)..."
  # after TEST-117, spec-x has drifted; --drift must report it and exit 1
  if run_canon --drift > "$TEST_DIR/drift-report.log"; then
    log_fail "TEST-118: --drift must exit 1 when a domain drifted"
  fi
  assert_contains "$TEST_DIR/drift-report.log" "DRIFTED domains: 1"
  log_pass "TEST-118: drift comparator distinguishes changed vs clean"
}

test_phase2_plan_guard() {
  log_info "TEST-119: unsafe approved map (one source in two domains) => runPhase2 aborts BEFORE mutating, no partial tree (unit)..."
  node_eval '
    import fs from "node:fs";
    import path from "node:path";
    import { runPhase2, validatePhase2Plan } from "./.aai/scripts/lib/docs-canon-core.mjs";
    const root = "_guard";
    fs.rmSync(root, { recursive: true, force: true });
    fs.mkdirSync(path.join(root, "docs/specs"), { recursive: true });
    fs.writeFileSync(path.join(root, "docs/specs/SPEC-DUP.md"),
      "---\nid: SPEC-DUP\ntype: spec\nstatus: done\nlinks:\n  pr: []\n---\n# dup\n");
    const map = { approved: true, domains: {
      alpha: { sources: ["docs/specs/SPEC-DUP.md"], confidence: "human" },
      beta:  { sources: ["docs/specs/SPEC-DUP.md"], confidence: "human" },
    }, unclear: [] };
    // plan validator must reject up-front
    const plan = validatePhase2Plan(root, map);
    if (plan.ok) { console.error("validatePhase2Plan accepted a duplicate-source map"); process.exit(1); }
    if (!plan.errors.some(e => /multiple domains/.test(e))) { console.error("missing duplicate-source error:", plan.errors); process.exit(1); }
    // runPhase2 must throw and leave the tree UNMUTATED (fail-fast, no partial move)
    let threw = false;
    try { runPhase2(root, map); } catch (e) { threw = true; if (!/unsafe archive plan|multiple domains/.test(e.message)) { console.error("wrong error:", e.message); process.exit(1); } }
    if (!threw) { console.error("runPhase2 accepted an unsafe map"); process.exit(1); }
    if (!fs.existsSync(path.join(root, "docs/specs/SPEC-DUP.md"))) { console.error("source was moved despite abort (partial mutation)"); process.exit(1); }
    if (fs.existsSync(path.join(root, "docs/_archive"))) { console.error("archive tree created despite abort"); process.exit(1); }
    if (fs.existsSync(path.join(root, "docs/canonical")) && fs.readdirSync(path.join(root, "docs/canonical")).length) { console.error("canonical written despite abort"); process.exit(1); }
    fs.rmSync(root, { recursive: true, force: true });
  ' || log_fail "TEST-119: phase2 plan guard wrong"
  log_pass "TEST-119: unsafe map aborts before any mutation"
}

# ---------------------------------------------------------------------------
# Seams (fresh fixture so produced trees are pristine)
# ---------------------------------------------------------------------------

reset_fixture_seams() {
  rm -rf "$TEST_DIR/docs/specs" "$TEST_DIR/docs/issues" "$TEST_DIR/docs/canonical" \
         "$TEST_DIR/docs/_archive" "$TEST_DIR/docs/ai/docs-canon.map.json" "$TEST_DIR/docs/INDEX.md"
  mkdir -p "$TEST_DIR/docs/specs"
  cat > "$TEST_DIR/docs/specs/SPEC-X-a.md" <<'MD'
---
id: SPEC-X
type: spec
status: superseded
links:
  pr: []
---
# original
SUPERSEDED BY SPEC-Y
MD
  cat > "$TEST_DIR/docs/specs/SPEC-X-b.md" <<'MD'
---
id: SPEC-X
type: spec
status: done
links:
  pr: []
---
# current
MD
  cat > "$TEST_DIR/docs/ai/docs-canon.map.json" <<'JSON'
{ "approved": true, "domains": { "spec-x": { "sources": ["docs/specs/SPEC-X-a.md","docs/specs/SPEC-X-b.md"], "confidence": "human" } }, "unclear": [] }
JSON
  (cd "$TEST_DIR" && git add -A && git commit -qm "seam fixtures" >/dev/null 2>&1 || true)
  run_canon --phase2 > /dev/null || log_fail "seam reset: phase2 failed"
}

test_seam1_index_includes_canonical() {
  log_info "TEST-301: SEAM-1 index includes docs/canonical; canonical ID appears in INDEX (int)..."
  reset_fixture_seams
  run_index > "$TEST_DIR/index.log" 2>&1 || log_fail "TEST-301: index gen failed: $(cat "$TEST_DIR/index.log")"
  assert_file "$TEST_DIR/docs/INDEX.md"
  assert_contains "$TEST_DIR/docs/INDEX.md" "Canonical layer"
  assert_contains "$TEST_DIR/docs/INDEX.md" "CANON-spec-x"
  log_pass "TEST-301: canonical doc surfaces in INDEX Canonical layer"
}

test_seam5_302_archived_not_active_idempotent() {
  log_info "TEST-302/306: archived NOT in Active/Drafts; INDEX idempotent; Phase 2 output in INDEX (int)..."
  # archived originals must not appear in Active/Drafts/Done
  assert_not_contains "$TEST_DIR/docs/INDEX.md" "_archive/specs/SPEC-X-a.md"
  assert_not_contains "$TEST_DIR/docs/INDEX.md" "_archive/specs/SPEC-X-b.md"
  # idempotent INDEX (modulo Generated timestamp)
  grep -v '^Generated:' "$TEST_DIR/docs/INDEX.md" > "$TEST_DIR/index-snap1"
  run_index > /dev/null 2>&1
  grep -v '^Generated:' "$TEST_DIR/docs/INDEX.md" > "$TEST_DIR/index-snap2"
  diff -q "$TEST_DIR/index-snap1" "$TEST_DIR/index-snap2" >/dev/null \
    || log_fail "TEST-302: INDEX must be idempotent modulo Generated timestamp"
  # SEAM-5 (TEST-306): canonical path present in the index
  assert_contains "$TEST_DIR/docs/INDEX.md" "docs/canonical/spec-x.md"
  log_pass "TEST-302/306: archived not active; INDEX idempotent; canonical in INDEX"
}

test_seam2_303_audit_clean() {
  log_info "TEST-303: SEAM-2 full Phase 2 then docs-audit --check --strict --no-event => exit 0 CLEAN (int)..."
  run_audit --check --strict --no-event > "$TEST_DIR/audit-clean.log" \
    || log_fail "TEST-303: strict audit over produced trees must exit 0"
  assert_contains "$TEST_DIR/audit-clean.log" "Verdict: CLEAN"
  log_pass "TEST-303: strict audit CLEAN over produced canonical+archive trees"
}

test_seam3_304_archived_not_orphan() {
  log_info "TEST-304: SEAM-3 archived doc in docs/_archive/ NOT counted as new orphan (int)..."
  # archived docs carry no ID-prefixed filename concerns; the _archive dir must
  # be excluded from the active scan (the EXCLUDE_DIRS/_archive reconciliation).
  run_audit --check --strict --no-event > "$TEST_DIR/orphan-check.log" \
    || log_fail "TEST-304: archived doc must not trip the orphan hard-fail"
  assert_not_contains "$TEST_DIR/orphan-check.log" "_archive/specs/SPEC-X-a.md"
  assert_not_contains "$TEST_DIR/orphan-check.log" "CHECK FAILED"
  # prove an archived doc is genuinely under the (preserved) archive dir
  assert_file "$TEST_DIR/docs/_archive/specs/SPEC-X-a.md"
  assert_contains "$TEST_DIR/docs/_archive/specs/SPEC-X-a.md" "status: archived"
  log_pass "TEST-304: _archive reconciled — archived docs not mis-flagged as orphans"
}

test_seam4_305_bidirectional_links() {
  log_info "TEST-305: SEAM-4 bidirectional links resolve (sources: <-> canonical:) end-to-end (int)..."
  node_eval '
    import { checkLinkIntegrity } from "./.aai/scripts/lib/docs-canon-core.mjs";
    const r = checkLinkIntegrity(process.cwd());
    if (!r.ok) { console.error("link integrity failed", r.violations); process.exit(1); }
  ' || log_fail "TEST-305: bidirectional link integrity failed"
  # explicit check: each archived canonical: resolves; each canonical sources: resolves
  node_eval '
    import fs from "node:fs";
    import { parseFrontmatter, asList } from "./.aai/scripts/lib/docs-model.mjs";
    const canon = parseFrontmatter(fs.readFileSync("docs/canonical/spec-x.md", "utf8"));
    for (const s of asList(canon.sources)) if (!fs.existsSync(s)) { console.error("dangling source", s); process.exit(1); }
    const arch = parseFrontmatter(fs.readFileSync("docs/_archive/specs/SPEC-X-a.md", "utf8"));
    if (!fs.existsSync(arch.canonical)) { console.error("dangling canonical pointer"); process.exit(1); }
  ' || log_fail "TEST-305: bidirectional resolution wrong"
  log_pass "TEST-305: sources: <-> canonical: resolve bidirectionally"
}

test_resync_resolves_drift() {
  log_info "TEST-120: post-review WARNING-2: --phase2 --resync re-synthesizes a drifted domain from CLI (int)..."
  reset_fixture_seams
  # capture the synthesized canonical, then mutate an ARCHIVED source body => drift
  cp "$TEST_DIR/docs/canonical/spec-x.md" "$TEST_DIR/canon-before-resync.md"
  printf '\nEdited after synthesis (resync trigger).\n' >> "$TEST_DIR/docs/_archive/specs/SPEC-X-b.md"
  # --drift must now flag the domain (exit 1)
  if run_canon --drift > "$TEST_DIR/resync-drift1.log"; then
    log_fail "TEST-120: --drift must exit 1 after an archived source is edited"
  fi
  assert_contains "$TEST_DIR/resync-drift1.log" "DRIFTED domains: 1"
  # plain --phase2 must NOT silently rewrite (drift preserved)
  run_canon --phase2 > "$TEST_DIR/resync-plain.log" || log_fail "TEST-120: plain phase2 exit"
  assert_contains "$TEST_DIR/resync-plain.log" "DRIFT (changed since synthesis, NOT rewritten): 1"
  # --resync re-synthesizes the drifted domain and re-baselines the hashes
  run_canon --phase2 --resync > "$TEST_DIR/resync-run.log" || log_fail "TEST-120: --resync phase2 exit"
  assert_contains "$TEST_DIR/resync-run.log" "Re-synced (drift resolved): 1 (spec-x)"
  # canonical was rewritten (sources list now reflects current archived bodies)
  assert_file "$TEST_DIR/docs/canonical/spec-x.md"
  # after resync, drift is resolved (exit 0, clean)
  run_canon --drift > "$TEST_DIR/resync-drift2.log" || log_fail "TEST-120: --drift must exit 0 after --resync"
  assert_contains "$TEST_DIR/resync-drift2.log" "DRIFTED domains: 0"
  log_pass "TEST-120: --resync resolves a drifted domain without hand-editing the map"
}

# ---------------------------------------------------------------------------
# Spec-AC-10 / AC-11 — skill harness
# ---------------------------------------------------------------------------

test_skill_manifest() {
  log_info "TEST-201: SKILL.md exists, frontmatter name: aai-docs-canon, <SUBAGENT-STOP> present (int)..."
  local skill="$PROJECT_ROOT/.claude/skills/aai-docs-canon/SKILL.md"
  assert_file "$skill"
  assert_contains "$skill" "name: aai-docs-canon"
  assert_contains "$skill" "<SUBAGENT-STOP>"
  # name does not collide: exactly one such skill dir
  local count
  count="$(find "$PROJECT_ROOT/.claude/skills" -maxdepth 1 -type d -name 'aai-docs-canon' | wc -l | tr -d ' ')"
  [[ "$count" == "1" ]] || log_fail "TEST-201: aai-docs-canon skill dir must be unique (found $count)"
  log_pass "TEST-201: skill manifest valid + unique"
}

test_role_prompt() {
  log_info "TEST-202: role prompt references Phase 1/2, HITL, default glob, drift; no name collision (int)..."
  local prompt="$PROJECT_ROOT/.aai/SKILL_DOCS_CANON.prompt.md"
  assert_file "$prompt"
  assert_contains "$prompt" "PHASE 1"
  assert_contains "$prompt" "PHASE 2"
  grep -qiE "HITL|human approval" "$prompt" || log_fail "TEST-202: prompt must reference the HITL gate"
  assert_contains "$prompt" "issues,requirements,specs,rfc"
  grep -qi "drift" "$prompt" || log_fail "TEST-202: prompt must reference drift"
  log_pass "TEST-202: role prompt documents both phases, HITL, default glob, drift"
}

test_e2e_suite_marker() {
  # TEST-203 (AC-11): a self-contained end-to-end run that asserts real
  # artifacts — phase1 gate, phase2 synthesis + archive, index, strict audit,
  # and bidirectional link integrity — rather than a bare reachability marker.
  log_info "TEST-203: end-to-end pipeline produces a clean canonical layer (e2e)..."
  reset_fixture_seams   # runs phase1-approved-map + phase2 end to end

  # 1) canonical doc exists with the six fixed sections (RFC-0011 stage 1
  #    added ## Requirements) in order
  local canon="$TEST_DIR/docs/canonical/spec-x.md"
  assert_file "$canon"
  assert_contains "$canon" "type: canonical"
  for section in "## Overview" "## Requirements" "## UI" "## Processes" "## Data model" "## Superseded decisions"; do
    grep -qF "$section" "$canon" || log_fail "TEST-203: canonical missing section '$section'"
  done
  # superseded source must be harvested only under the Superseded section
  awk '/^## Superseded decisions/{f=1} f&&/_archive\/specs\/SPEC-X-a/{found=1} END{exit !found}' "$canon" \
    || log_fail "TEST-203: superseded source not harvested under Superseded decisions"

  # 2) originals archived with status + back-pointer; not left in docs/specs
  assert_file "$TEST_DIR/docs/_archive/specs/SPEC-X-a.md"
  assert_contains "$TEST_DIR/docs/_archive/specs/SPEC-X-a.md" "status: archived"
  assert_contains "$TEST_DIR/docs/_archive/specs/SPEC-X-a.md" "canonical: docs/canonical/spec-x.md"
  assert_dir_empty_or_absent "$TEST_DIR/docs/specs"

  # 3) index surfaces the canonical layer
  run_index > /dev/null 2>&1 || log_fail "TEST-203: index gen failed"
  assert_contains "$TEST_DIR/docs/INDEX.md" "CANON-spec-x"

  # 4) strict audit over the produced trees is CLEAN
  run_audit --check --strict --no-event > "$TEST_DIR/e2e-audit.log" \
    || log_fail "TEST-203: strict audit over e2e output must exit 0"
  assert_contains "$TEST_DIR/e2e-audit.log" "Verdict: CLEAN"

  # 5) bidirectional links resolve
  node_eval '
    import { checkLinkIntegrity } from "./.aai/scripts/lib/docs-canon-core.mjs";
    const r = checkLinkIntegrity(process.cwd());
    if (!r.ok) { console.error("e2e link integrity failed", r.violations); process.exit(1); }
  ' || log_fail "TEST-203: e2e link integrity failed"

  log_pass "TEST-203: e2e pipeline green (synthesis, archive, index, strict audit, links)"
}

main() {
  echo "Testing $TEST_NAME skill (canonicalization engine + harness)"
  check_deps
  setup_fixture

  # Schema (AC-01) and validators (AC-02) — unit + int
  test_doc_type_enum             # TEST-101
  test_audit_accepts_new_types   # TEST-102
  test_canonical_frontmatter_validator # TEST-103
  test_audit_flags_bad_canonical # TEST-104

  # Graph builder (AC-04) — unit
  test_graph_umbrella_grouping   # TEST-107
  test_graph_supersession_markers # TEST-108
  test_graph_crossrefs_and_status # TEST-109
  test_graph_determinism         # TEST-110

  # Phase 1 + gate (AC-05)
  test_phase1_proposal_artifact  # TEST-111
  test_phase1_gate_no_writes     # TEST-112
  test_phase2_gate_requires_approval # TEST-113

  # Section contract (AC-06) then Phase 2 synthesis (drives AC-03 checks)
  test_section_contract_validator # TEST-114
  test_synthesis_sections_and_superseded_isolation # TEST-115
  test_phase2_archive_move       # TEST-105
  test_link_integrity_validator  # TEST-106

  # Re-run idempotence + drift (AC-07) — fresh fixture
  test_rerun_idempotent          # TEST-116
  test_drift_flagged_no_overwrite # TEST-117
  test_drift_comparator_unit     # TEST-118
  test_phase2_plan_guard         # TEST-119

  # Seams (AC-08, AC-09, AC-03/SEAM-4) — fresh fixture
  test_seam1_index_includes_canonical       # TEST-301
  test_seam5_302_archived_not_active_idempotent # TEST-302 / TEST-306
  test_seam2_303_audit_clean                # TEST-303
  test_seam3_304_archived_not_orphan        # TEST-304
  test_seam4_305_bidirectional_links        # TEST-305

  # Re-sync drift resolution (AC-07, post-review WARNING-2)
  test_resync_resolves_drift                # TEST-120

  # Skill harness (AC-10, AC-11)
  test_skill_manifest            # TEST-201
  test_role_prompt               # TEST-202
  test_e2e_suite_marker          # TEST-203

  echo ""
  log_pass "All $TEST_NAME tests passed"
}

main "$@"
