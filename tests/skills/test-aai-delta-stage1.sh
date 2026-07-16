#!/usr/bin/env bash
#
# Test: RFC-0011 stage 1 — canonical-layer requirements contract
# (spec-delta-stage-1). Verifies the CANONICAL_TEMPLATE.md contract shape, the
# REQ-<DOMAIN>-NNN grammar + domain derivation + Requirements-section parser in
# docs-model.mjs, the docs-canon Requirements-skeleton emission (fixture run,
# incl. the re-run idempotence probe), the SKILL_DOCS_CANON contract text, and
# the existing docs-canon suite as the seam-survival invariant.
#
# Single shell file per repo convention; stanzas map to the
# spec-delta-stage-1 Test Plan IDs (TEST-001..TEST-007).
#
# Per-stanza runs (TDD RED/GREEN evidence): ONLY=TEST-00N bash <this file>
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-delta-stage1"
TEST_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="$PROJECT_ROOT/.aai/templates/CANONICAL_TEMPLATE.md"
PROMPT="$PROJECT_ROOT/.aai/SKILL_DOCS_CANON.prompt.md"

cleanup() {
  if [[ -n "${KEEP_TEST_DIR:-}" ]]; then
    [[ -n "${TEST_DIR:-}" ]] && echo "INFO: keeping fixture at $TEST_DIR"
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
assert_contains() { grep -qF -- "$2" "$1" || log_fail "Expected '$2' in $1"; }

# Run a node snippet against the REAL repo libs (contract lives in the repo).
node_repo() { (cd "$PROJECT_ROOT" && node --input-type=module -e "$1"); }
# Run a node snippet inside the fixture repo (vendored libs).
node_eval() { (cd "$TEST_DIR" && node --input-type=module -e "$1"); }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$PROJECT_ROOT/.aai/scripts/docs-canon.mjs" ]] || log_fail "docs-canon.mjs not found"
  log_pass "Dependencies checked"
}

# ---------------------------------------------------------------------------
# TEST-001 (Spec-AC-01) — CANONICAL_TEMPLATE.md contract shape
# ---------------------------------------------------------------------------
test_001_template_shape() {
  log_info "TEST-001: CANONICAL_TEMPLATE.md carries the full Requirements contract (unit)..."
  assert_file "$TEMPLATE"
  # six fixed sections present, in order
  node_repo '
    import fs from "node:fs";
    const c = fs.readFileSync(".aai/templates/CANONICAL_TEMPLATE.md", "utf8");
    const want = ["## Overview / Intent", "## Requirements", "## UI",
                  "## Processes / Behavior", "## Data model", "## Superseded decisions"];
    let at = -1;
    for (const w of want) {
      const i = c.indexOf("\n" + w);
      if (i < 0) { console.error("missing section " + w); process.exit(1); }
      if (i < at) { console.error("out of order " + w); process.exit(1); }
      at = i;
    }
  ' || log_fail "TEST-001: template must carry six ordered sections"
  # REQ block contract elements
  assert_contains "$TEMPLATE" '### REQ-<DOMAIN>-NNN — <title>'
  assert_contains "$TEMPLATE" 'SHALL'
  assert_contains "$TEMPLATE" '- Scenario:'
  assert_contains "$TEMPLATE" 'Provenance:'
  assert_contains "$TEMPLATE" 'never renumber'
  # domain derivation rule with the digit-bearing example (kebab→snake).
  # NOTE: the example slug must avoid the retired review-taxonomy tokens the
  # hygiene-pack guard bans on .aai surfaces (e.g. "stage-1"), so the swept
  # files use oauth2-login; the feature slug itself is exercised end-to-end
  # in TEST-002 (unit) and TEST-005 (fixture repo), which are unswept.
  assert_contains "$TEMPLATE" 'oauth2-login'
  assert_contains "$TEMPLATE" 'OAUTH2_LOGIN'
  # a fully-worked example block (grammar shown concretely)
  grep -qE '^### REQ-[A-Z0-9][A-Z0-9_]*-[0-9]{3,} — ' "$TEMPLATE" \
    || log_fail "TEST-001: template must show a concrete REQ example heading"
  log_pass "TEST-001: template documents sections, REQ grammar, SHALL, Scenario, Provenance, stability, derivation"
}

# ---------------------------------------------------------------------------
# TEST-002 (Spec-AC-02) — REQ_ID_RE + domainToReqDomain fixtures
# ---------------------------------------------------------------------------
test_002_req_id_grammar() {
  log_info "TEST-002: REQ id regex valid/invalid fixtures + domain derivation (unit)..."
  node_repo '
    import { REQ_ID_RE, domainToReqDomain } from "./.aai/scripts/lib/docs-model.mjs";
    const valid = ["REQ-AUTH-001", "REQ-DELTA_STAGE_1-042", "REQ-AUTH-1042",
                   "REQ-A2B_C-999", "REQ-1X-003"];
    const invalid = ["REQ-auth-001",          // lowercase domain
                     "REQ-AUTH-1",            // unpadded NNN
                     "REQ-AUTH-01",           // 2-digit NNN
                     "REQ-DELTA-STAGE-1-001", // kebab domain (must be snake)
                     "REQ--001",              // empty domain
                     "REQ-AUTH-",             // missing NNN
                     "AUTH-001",              // missing REQ prefix
                     "REQ-AUTH_001",          // underscore before NNN
                     "REQ-AUTH-001 ",         // trailing space
                     "req-AUTH-001"];         // lowercase prefix
    for (const v of valid) if (!REQ_ID_RE.test(v)) { console.error("should accept " + v); process.exit(1); }
    for (const v of invalid) if (REQ_ID_RE.test(v)) { console.error("should reject " + JSON.stringify(v)); process.exit(1); }
    const derive = [["auth", "AUTH"], ["delta-stage-1", "DELTA_STAGE_1"],
                    ["match-lifecycle", "MATCH_LIFECYCLE"]];
    for (const [slug, want] of derive) {
      const got = domainToReqDomain(slug);
      if (got !== want) { console.error(`derive ${slug}: got ${got}, want ${want}`); process.exit(1); }
    }
    // derived domains must themselves form valid REQ ids
    for (const [slug] of derive) {
      if (!REQ_ID_RE.test(`REQ-${domainToReqDomain(slug)}-001`)) {
        console.error("derived domain not REQ-valid: " + slug); process.exit(1);
      }
    }
  ' || log_fail "TEST-002: REQ id grammar / derivation wrong"

  # Review NB-2: validatePhase2Plan must REJECT an invalid domain slug at
  # pre-flight (before any archiveSource mutation), so a bad key can't leave a
  # half-mutated tree when renderCanonicalDoc later throws on it.
  (cd "$PROJECT_ROOT" && node --input-type=module -e '
    import { validatePhase2Plan } from "./.aai/scripts/lib/docs-canon-core.mjs";
    const bad = validatePhase2Plan(process.cwd(), { domains: { "Auth": { sources: ["docs/x.md"] } } });
    if (bad.ok) { console.error("bad domain slug Auth accepted"); process.exit(1); }
    if (!bad.errors.some(e => /not a valid slug/.test(e))) { console.error("wrong error: " + JSON.stringify(bad.errors)); process.exit(1); }
    const bad2 = validatePhase2Plan(process.cwd(), { domains: { "spec_x": { sources: ["docs/x.md"] } } });
    if (bad2.ok) { console.error("underscore domain accepted"); process.exit(1); }
  ') || log_fail "TEST-002: validatePhase2Plan must reject invalid domain slugs pre-flight (NB-2)"

  log_pass "TEST-002: REQ_ID_RE fixtures + kebab→snake derivation + pre-flight domain-slug rejection (NB-2)"
}

# ---------------------------------------------------------------------------
# TEST-003 (Spec-AC-02) — parseRequirementsSection fixtures
# ---------------------------------------------------------------------------
test_003_requirements_parser() {
  log_info "TEST-003: parseRequirementsSection valid/violation fixtures (unit)..."
  node_repo '
    import { parseRequirementsSection } from "./.aai/scripts/lib/docs-model.mjs";
    const doc = (reqs) => `# Canonical: auth\n\n## Overview / Intent\nx\n\n## Requirements\n\n${reqs}\n## UI\nx\n`;

    // 1) valid block parses fully
    const good = doc(`### REQ-AUTH-001 — Session expiry
The system SHALL expire an authenticated session after 30 minutes of inactivity.

- Scenario: WHEN a session is idle for 30 minutes THEN the next request is rejected with 401.

Provenance: —
`);
    let r = parseRequirementsSection(good, { domain: "auth" });
    if (!r.present) { console.error("section not detected"); process.exit(1); }
    if (r.violations.length) { console.error("valid block flagged:", r.violations); process.exit(1); }
    if (r.requirements.length !== 1) { console.error("want 1 requirement"); process.exit(1); }
    const q = r.requirements[0];
    if (q.id !== "REQ-AUTH-001" || q.title !== "Session expiry") { console.error("id/title wrong", q); process.exit(1); }
    if (q.shallCount !== 1) { console.error("shallCount wrong", q); process.exit(1); }
    if (q.scenarios.length !== 1 || !q.scenarios[0].includes("WHEN")) { console.error("scenario wrong", q); process.exit(1); }
    if (q.provenance !== null) { console.error("empty provenance must read null", q); process.exit(1); }

    // 2) filled provenance surfaces the ref
    const merged = doc("### REQ-AUTH-002 — Lockout\nThe system SHALL lock the account after 5 failed logins.\n\nProvenance: SPEC-0031\n");
    r = parseRequirementsSection(merged, { domain: "auth" });
    if (r.violations.length) { console.error("merged flagged:", r.violations); process.exit(1); }
    if (r.requirements[0].provenance !== "SPEC-0031") { console.error("provenance ref lost"); process.exit(1); }

    // 3) violations: no SHALL / two SHALLs / missing Provenance / bad heading / dup id / domain mismatch
    const cases = [
      [doc("### REQ-AUTH-003 — No shall\nJust prose.\n\nProvenance: —\n"), "SHALL"],
      [doc("### REQ-AUTH-003 — Two shalls\nThe system SHALL a.\nThe system SHALL b.\n\nProvenance: —\n"), "SHALL"],
      [doc("### REQ-AUTH-004 — No provenance\nThe system SHALL x.\n"), "Provenance"],
      [doc("### Freeform heading\nThe system SHALL x.\n\nProvenance: —\n"), "heading"],
      [doc("### REQ-AUTH-005 — A\nThe system SHALL x.\n\nProvenance: —\n\n### REQ-AUTH-005 — B\nThe system SHALL y.\n\nProvenance: —\n"), "duplicate"],
      [doc("### REQ-BILLING-001 — Wrong domain\nThe system SHALL x.\n\nProvenance: —\n"), "domain"],
    ];
    for (const [text, needle] of cases) {
      const rr = parseRequirementsSection(text, { domain: "auth" });
      if (!rr.violations.length) { console.error("expected violation for: " + needle); process.exit(1); }
      if (!rr.violations.some(v => v.toLowerCase().includes(needle.toLowerCase()))) {
        console.error(`violation for ${needle} missing keyword:`, rr.violations); process.exit(1);
      }
    }

    // 4) empty section (skeleton) is VALID; absent section is a violation
    const empty = doc("_No requirements recorded for this domain yet._\n");
    r = parseRequirementsSection(empty, { domain: "auth" });
    if (!r.present || r.violations.length || r.requirements.length !== 0) {
      console.error("empty skeleton must be valid", r); process.exit(1);
    }
    const absent = "## Overview / Intent\nx\n## UI\nx\n";
    r = parseRequirementsSection(absent, { domain: "auth" });
    if (r.present || !r.violations.length) { console.error("absent section must violate"); process.exit(1); }
  ' || log_fail "TEST-003: parseRequirementsSection wrong"
  log_pass "TEST-003: parser accepts valid/empty, flags SHALL/provenance/heading/dup/domain violations"
}

# ---------------------------------------------------------------------------
# TEST-004 (Spec-AC-03) — section list + render skeleton + contract validator
# ---------------------------------------------------------------------------
test_004_render_and_contract() {
  log_info "TEST-004: CANONICAL_SECTIONS + renderCanonicalDoc skeleton + validateSectionContract (unit)..."
  node_repo '
    import { CANONICAL_SECTIONS, validateSectionContract, parseRequirementsSection } from "./.aai/scripts/lib/docs-model.mjs";
    import { renderCanonicalDoc } from "./.aai/scripts/lib/docs-canon-core.mjs";
    if (CANONICAL_SECTIONS[0] !== "Overview / Intent" || CANONICAL_SECTIONS[1] !== "Requirements") {
      console.error("Requirements must be the second fixed section", CANONICAL_SECTIONS); process.exit(1);
    }
    if (CANONICAL_SECTIONS.length !== 6) { console.error("want six fixed sections"); process.exit(1); }

    const text = renderCanonicalDoc({ domain: "delta-stage-1", sources: ["docs/_archive/specs/A.md"] });
    // skeleton present, empty-valid placeholder, positioned before ## UI
    const iReq = text.indexOf("## Requirements");
    const iUi = text.indexOf("## UI");
    const iOv = text.indexOf("## Overview / Intent");
    if (iReq < 0 || !(iOv < iReq && iReq < iUi)) { console.error("skeleton missing or misplaced"); process.exit(1); }
    if (text.includes("## Requirements\n\n_To be synthesized._")) {
      console.error("Requirements must not use the synthesis placeholder (empty is valid)"); process.exit(1);
    }
    if (!text.includes("REQ-<DOMAIN>-NNN")) { console.error("contract comment missing from skeleton"); process.exit(1); }
    // rendered doc satisfies the section contract and parses as a valid empty section
    const v = validateSectionContract(text);
    if (!v.ok) { console.error("rendered doc violates contract", v.violations); process.exit(1); }
    const p = parseRequirementsSection(text, { domain: "delta-stage-1" });
    if (!p.present || p.violations.length || p.requirements.length !== 0) {
      console.error("rendered skeleton must parse as valid empty", p); process.exit(1);
    }
    // agent-supplied requirements body flows through
    const filled = renderCanonicalDoc({ domain: "auth", sources: ["a.md"],
      sectionBodies: { requirements: "### REQ-AUTH-001 — T\nThe system SHALL x.\n\nProvenance: —" } });
    const pf = parseRequirementsSection(filled, { domain: "auth" });
    if (pf.requirements.length !== 1 || pf.violations.length) { console.error("sectionBodies.requirements not honored", pf); process.exit(1); }
    // legacy five-section body is now a contract violation (D3 — explicit tightening)
    const legacy = "## Overview / Intent\nx\n## UI\nx\n## Processes / Behavior\nx\n## Data model\nx\n## Superseded decisions\nx";
    if (validateSectionContract(legacy).ok) { console.error("legacy five-section body must violate"); process.exit(1); }
  ' || log_fail "TEST-004: render/contract wrong"
  log_pass "TEST-004: six-section contract enforced; skeleton rendered second, empty-valid, comment carried"
}

# ---------------------------------------------------------------------------
# TEST-005 (Spec-AC-03) — fixture-repo docs-canon run + idempotence probe
# ---------------------------------------------------------------------------
setup_fixture() {
  log_info "Setting up isolated fixture repo..."
  TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aai-delta-stage1-test.XXXXXX")"
  (
    cd "$TEST_DIR"
    git init -q
    git config user.email "test@example.com"
    git config user.name "AAI Test"
    mkdir -p .aai/scripts/lib docs/specs docs/ai
    cp "$PROJECT_ROOT/.aai/scripts/docs-canon.mjs" .aai/scripts/
    cp "$PROJECT_ROOT"/.aai/scripts/lib/*.mjs .aai/scripts/lib/
    cat > docs/specs/SPEC-D-one.md <<'MD'
---
id: SPEC-D
type: spec
status: done
links:
  pr: []
---
# Delta domain source
Body content for synthesis.
MD
    git add -A && git commit -qm "fixture"
  )
  cat > "$TEST_DIR/docs/ai/docs-canon.map.json" <<'JSON'
{
  "approved": true,
  "domains": {
    "delta-stage-1": {
      "sources": ["docs/specs/SPEC-D-one.md"],
      "confidence": "human"
    }
  },
  "unclear": []
}
JSON
  log_pass "Fixture repo ready"
}

test_005_canon_emits_skeleton() {
  log_info "TEST-005: docs-canon --phase2 emits Requirements skeleton; re-run idempotent (int)..."
  setup_fixture
  (cd "$TEST_DIR" && node .aai/scripts/docs-canon.mjs --phase2 > phase2.log) \
    || log_fail "TEST-005: phase2 must succeed"
  local canon="$TEST_DIR/docs/canonical/delta-stage-1.md"
  assert_file "$canon"
  assert_contains "$canon" '## Requirements'
  assert_contains "$canon" 'REQ-<DOMAIN>-NNN'
  assert_contains "$canon" '_No requirements recorded for this domain yet._'
  # skeleton sits between Overview and UI; empty section parses valid for the digit-bearing slug
  node_eval '
    import fs from "node:fs";
    import { validateSectionContract, parseRequirementsSection } from "./.aai/scripts/lib/docs-model.mjs";
    const c = fs.readFileSync("docs/canonical/delta-stage-1.md", "utf8");
    const v = validateSectionContract(c);
    if (!v.ok) { console.error("contract", v.violations); process.exit(1); }
    const p = parseRequirementsSection(c, { domain: "delta-stage-1" });
    if (!p.present || p.violations.length) { console.error("skeleton parse", p.violations); process.exit(1); }
  ' || log_fail "TEST-005: emitted skeleton invalid"
  # real idempotence probe: re-run skips the domain and the file is byte-identical
  local before after
  before=$(shasum -a 256 "$canon" | awk '{print $1}')
  (cd "$TEST_DIR" && node .aai/scripts/docs-canon.mjs --phase2 > rerun.log) \
    || log_fail "TEST-005: phase2 re-run must succeed"
  grep -q 'Skipped (unchanged): 1' "$TEST_DIR/rerun.log" \
    || log_fail "TEST-005: re-run must skip the unchanged domain"
  after=$(shasum -a 256 "$canon" | awk '{print $1}')
  [[ "$before" == "$after" ]] || log_fail "TEST-005: canonical changed on idempotent re-run"
  log_pass "TEST-005: canonical carries valid empty skeleton; re-run skips, byte-identical"
}

# ---------------------------------------------------------------------------
# TEST-006 (Spec-AC-03) — SKILL_DOCS_CANON prompt documents the contract
# ---------------------------------------------------------------------------
test_006_prompt_contract() {
  log_info "TEST-006: SKILL_DOCS_CANON.prompt.md documents the six-section + REQ contract (unit)..."
  assert_file "$PROMPT"
  assert_contains "$PROMPT" 'SIX fixed layer sections'
  assert_contains "$PROMPT" '## Requirements'
  assert_contains "$PROMPT" 'REQ-<DOMAIN>-NNN'
  assert_contains "$PROMPT" 'SHALL'
  assert_contains "$PROMPT" 'Provenance'
  # derivation rule with the digit-bearing example (see TEST-001 note on why
  # the swept .aai surfaces use oauth2-login rather than the feature slug)
  assert_contains "$PROMPT" 'OAUTH2_LOGIN'
  # empty-allowed skeleton is explicit
  grep -qi 'empty.*allowed\|empty.*valid' "$PROMPT" \
    || log_fail "TEST-006: prompt must state the skeleton may be empty"
  log_pass "TEST-006: prompt carries contract, derivation rule, empty-allowed skeleton"
}

# ---------------------------------------------------------------------------
# TEST-007 (Spec-AC-04) — seam survival: existing docs-canon suite green
# ---------------------------------------------------------------------------
test_007_docs_canon_suite() {
  log_info "TEST-007: existing test-aai-docs-canon.sh passes over the changed core (int)..."
  bash "$SCRIPT_DIR/test-aai-docs-canon.sh" > /tmp/aai-delta-stage1-canon-suite.log 2>&1 \
    || { tail -20 /tmp/aai-delta-stage1-canon-suite.log >&2; log_fail "TEST-007: docs-canon suite failed"; }
  log_pass "TEST-007: docs-canon suite green (seam survival)"
}

# ---------------------------------------------------------------------------

main() {
  echo "=== Test: $TEST_NAME (spec-delta-stage-1 / RFC-0011 stage 1) ==="
  check_deps
  local only="${ONLY:-}"
  run_stanza() {
    local id="$1"; shift
    if [[ -z "$only" || "$only" == "$id" ]]; then "$@"; fi
  }
  run_stanza TEST-001 test_001_template_shape
  run_stanza TEST-002 test_002_req_id_grammar
  run_stanza TEST-003 test_003_requirements_parser
  run_stanza TEST-004 test_004_render_and_contract
  run_stanza TEST-005 test_005_canon_emits_skeleton
  run_stanza TEST-006 test_006_prompt_contract
  run_stanza TEST-007 test_007_docs_canon_suite
  echo "=== All $TEST_NAME tests passed ==="
}

main "$@"
