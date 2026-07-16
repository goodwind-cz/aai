#!/usr/bin/env bash
#
# Test: RFC-0011 (delta-spec lifecycle) — SPEC `## Deltas` section + shape
# validation (spec-delta-stage-2). Verifies the reversible domain mapping
# (reqDomainToSlug, inverse of domainToReqDomain) and the shared
# parseDeltasSection reader in docs-model.mjs, the SPEC_TEMPLATE + PLANNING
# wiring (taxonomy-guard clean), and seam survival (the existing spec-lint and
# delta-stage1 suites plus the strict repo audit stay green over the changed
# core).
#
# Single shell file per repo convention; stanzas map to the spec-delta-stage-2
# Test Plan IDs (TEST-001, TEST-002, TEST-005, TEST-006). The spec-lint
# integration stanzas (TEST-003/TEST-004) live in tests/skills/test-aai-spec-lint.sh.
#
# Per-stanza runs (TDD RED/GREEN evidence): ONLY=TEST-00N bash <this file>
#
# Exit codes:
#   0  - All tests passed
#   1  - Tests failed
#   42 - Tests skipped (missing dependencies)

set -euo pipefail

TEST_NAME="aai-delta-stage2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE="$PROJECT_ROOT/.aai/templates/SPEC_TEMPLATE.md"
PLANNING="$PROJECT_ROOT/.aai/PLANNING.prompt.md"

log_pass() { echo "PASS: $*"; }
log_fail() { echo "FAIL: $*" >&2; exit 1; }
log_skip() { echo "SKIP: $*"; exit 42; }
log_info() { echo "INFO: $*"; }

assert_file() { [[ -f "$1" ]] || log_fail "Missing file: $1"; }
assert_contains() { grep -qF -- "$2" "$1" || log_fail "Expected '$2' in $1"; }

# Run a node snippet against the REAL repo libs (contract lives in the repo).
node_repo() { (cd "$PROJECT_ROOT" && node --input-type=module -e "$1"); }

check_deps() {
  log_info "Checking dependencies..."
  command -v node >/dev/null 2>&1 || log_skip "node not found"
  command -v git >/dev/null 2>&1 || log_skip "git not found"
  [[ -f "$PROJECT_ROOT/.aai/scripts/lib/docs-model.mjs" ]] || log_fail "docs-model.mjs not found"
  log_pass "Dependencies checked"
}

# ---------------------------------------------------------------------------
# TEST-001 (Spec-AC-01) — reqDomainToSlug is the exact inverse of domainToReqDomain
# ---------------------------------------------------------------------------
test_001_domain_reverse() {
  log_info "TEST-001: reqDomainToSlug inverse round-trip + rejection fixtures (unit)..."
  node_repo '
    import { reqDomainToSlug, domainToReqDomain, DOMAIN_SLUG_RE }
      from "./.aai/scripts/lib/docs-model.mjs";

    // 1) documented reversals
    const cases = [["OAUTH2_LOGIN", "oauth2-login"], ["AUTH", "auth"],
                   ["DELTA_MERGE", "delta-merge"], ["A2B_C", "a2b-c"], ["1X", "1x"]];
    for (const [tok, want] of cases) {
      const got = reqDomainToSlug(tok);
      if (got !== want) { console.error(`reverse ${tok}: got ${got}, want ${want}`); process.exit(1); }
      if (!DOMAIN_SLUG_RE.test(got)) { console.error(`reverse ${tok}: not a slug`); process.exit(1); }
    }

    // 2) true inverse: round-trips domainToReqDomain both ways for every valid slug
    const slugs = ["auth", "oauth2-login", "delta-merge", "match-lifecycle", "a2b-c", "1x"];
    for (const s of slugs) {
      const tok = domainToReqDomain(s);
      if (reqDomainToSlug(tok) !== s) { console.error(`round-trip failed for ${s}`); process.exit(1); }
      if (domainToReqDomain(reqDomainToSlug(tok)) !== tok) { console.error(`token round-trip failed for ${tok}`); process.exit(1); }
    }

    // 3) rejects tokens that do not reverse to a DOMAIN_SLUG_RE slug (throw-consistent
    //    with domainToReqDomain fail-fast). Lowercase input is NOT a canonical REQ
    //    domain token, so it must be rejected too (not silently lowercased).
    const bad = ["auth", "_AUTH", "-AUTH", "", "  ", "AUTH-BILLING", "OAUTH2 LOGIN"];
    for (const t of bad) {
      let threw = false;
      try { reqDomainToSlug(t); } catch { threw = true; }
      if (!threw) { console.error(`should reject ${JSON.stringify(t)}`); process.exit(1); }
    }
  ' || log_fail "TEST-001: reqDomainToSlug inverse/rejection wrong"
  log_pass "TEST-001: reqDomainToSlug reverses OAUTH2_LOGIN->oauth2-login, round-trips domainToReqDomain, rejects non-reversible tokens"
}

# ---------------------------------------------------------------------------
# TEST-002 (Spec-AC-01) — parseDeltasSection shape + violations
# ---------------------------------------------------------------------------
test_002_parse_deltas() {
  log_info "TEST-002: parseDeltasSection valid blocks + violation codes + absent/empty states (unit)..."
  node_repo '
    import { parseDeltasSection } from "./.aai/scripts/lib/docs-model.mjs";
    const DASH = "—"; // em dash
    const wrap = (blocks) => `# Spec\n\nSPEC-FROZEN: true\n\n## Deltas\n\n${blocks}\n## Verification\nx\n`;

    // 1) a well-formed section: one ADDED (no NNN), one MODIFIED, one REMOVED
    const good = wrap(
`### ADDED REQ-OAUTH2_LOGIN ${DASH} Password grant retired
The system SHALL reject the OAuth2 password grant on the login endpoint.

- Scenario: WHEN a password-grant token request arrives THEN it is refused with 400.

### MODIFIED REQ-AUTH-001 ${DASH} Session expiry tightened
The system SHALL expire an idle session after 15 minutes.

### REMOVED REQ-AUTH-009
`);
    let r = parseDeltasSection(good);
    if (!r.present) { console.error("section not detected"); process.exit(1); }
    if (r.violations.length) { console.error("clean section flagged:", r.violations); process.exit(1); }
    if (r.deltas.length !== 3) { console.error("want 3 deltas, got", r.deltas.length); process.exit(1); }
    const [a, m, x] = r.deltas;
    if (a.op !== "ADDED" || a.id !== "REQ-OAUTH2_LOGIN" || a.domain !== "OAUTH2_LOGIN"
        || a.slug !== "oauth2-login" || a.title !== "Password grant retired"
        || a.shallCount !== 1 || a.scenarios.length !== 1) { console.error("ADDED wrong", a); process.exit(1); }
    if (m.op !== "MODIFIED" || m.id !== "REQ-AUTH-001" || m.domain !== "AUTH"
        || m.slug !== "auth" || m.title !== "Session expiry tightened"
        || m.shallCount !== 1) { console.error("MODIFIED wrong", m); process.exit(1); }
    if (x.op !== "REMOVED" || x.id !== "REQ-AUTH-009" || x.domain !== "AUTH"
        || x.slug !== "auth" || x.title !== null || x.shallCount !== 0
        || x.scenarios.length !== 0) { console.error("REMOVED wrong", x); process.exit(1); }

    // 2) each malformed variant surfaces its precise D2 code
    const codeOf = (blocks) => parseDeltasSection(wrap(blocks)).violations.map(v => v.code);
    const expect = (blocks, code) => {
      const codes = codeOf(blocks);
      if (!codes.includes(code)) { console.error(`expected ${code} for block, got`, codes); process.exit(1); }
    };
    expect(`### RENAMED REQ-AUTH-001 ${DASH} bad op\nThe system SHALL x.\n`, "delta-op-invalid");
    expect(`### ADDED REQ-AUTH-001 ${DASH} numbered add\nThe system SHALL x.\n`, "delta-added-numbered");
    expect(`### MODIFIED REQ-auth-1 ${DASH} bad id\nThe system SHALL x.\n`, "delta-id-malformed");
    expect(`### ADDED REQ-Auth ${DASH} underivable domain\nThe system SHALL x.\n`, "delta-domain-underivable");
    expect(`### ADDED REQ-AUTH ${DASH} two shalls\nThe system SHALL a.\nThe system SHALL b.\n`, "delta-shall-count");
    expect(`### MODIFIED REQ-AUTH-002 ${DASH} no shall\nJust prose here.\n`, "delta-shall-count");
    expect(`### REMOVED REQ-AUTH-003\nThe system SHALL still here.\n`, "delta-shall-count");
    expect(`### ADDED REQ-AUTH ${DASH} bad scenario\nThe system SHALL x.\n\n- Scenario: no when/then here.\n`, "delta-scenario-malformed");
    // duplicate numbered id across two blocks
    expect(`### MODIFIED REQ-AUTH-004 ${DASH} a\nThe system SHALL a.\n\n### REMOVED REQ-AUTH-004\n`, "delta-duplicate");
    // duplicate ADDED title in the same domain (case-insensitive)
    expect(`### ADDED REQ-AUTH ${DASH} Same Title\nThe system SHALL a.\n\n### ADDED REQ-AUTH ${DASH} same title\nThe system SHALL b.\n`, "delta-duplicate");

    // 3) absent section vs present-but-empty section
    const absent = parseDeltasSection("# Spec\n\n## Verification\nx\n");
    if (absent.present || absent.deltas.length || absent.violations.length) { console.error("absent must be empty/false", absent); process.exit(1); }
    const empty = parseDeltasSection("# Spec\n\n## Deltas\n\n## Verification\nx\n");
    if (!empty.present || empty.deltas.length || empty.violations.length) { console.error("empty section must be present/clean", empty); process.exit(1); }

    // 4) `## Deltas Rationale` must NOT be treated as the Deltas section (exact heading)
    const decoy = parseDeltasSection("# Spec\n\n## Deltas Rationale\n\n### ADDED REQ-AUTH-001 " + DASH + " x\n");
    if (decoy.present) { console.error("## Deltas Rationale wrongly matched"); process.exit(1); }

    // 5) HTML-comment stripping (review F1): a `## Deltas` section wholly inside
    // an HTML comment (SPEC_TEMPLATE ships the example commented) must be INERT —
    // present:false, no phantom deltas that the delta merge would later apply.
    const commented = parseDeltasSection("# Spec\n\n<!--\n## Deltas\n\n### ADDED REQ-AUTH " + DASH + " x\nThe system SHALL x.\n-->\n\n## Verification\nx\n");
    if (commented.present || commented.deltas.length || commented.violations.length) { console.error("commented Deltas section must be inert", commented); process.exit(1); }
    // a commented-out block inside a LIVE section must not be parsed or linted
    const liveCommented = parseDeltasSection("# Spec\n\n## Deltas\n\n### ADDED REQ-AUTH " + DASH + " live\nThe system SHALL a.\n\n<!-- ### RENAMED REQ-AUTH-001 " + DASH + " disabled\nThe system SHALL b. -->\n\n## Verification\nx\n");
    if (liveCommented.deltas.length !== 1 || liveCommented.violations.length) { console.error("commented-out block must not be parsed/linted", liveCommented); process.exit(1); }
  ' || log_fail "TEST-002: parseDeltasSection shape/violations wrong"
  log_pass "TEST-002: parseDeltasSection parses ADDED/MODIFIED/REMOVED, emits every D2 code, handles absent/empty/decoy"
}

# ---------------------------------------------------------------------------
# TEST-005 (Spec-AC-03) — SPEC_TEMPLATE + PLANNING wiring, taxonomy-guard clean
# ---------------------------------------------------------------------------
test_005_template_and_planning() {
  log_info "TEST-005: SPEC_TEMPLATE + PLANNING document the optional Deltas section; no stage-N token (unit)..."
  assert_file "$TEMPLATE"
  assert_file "$PLANNING"

  # SPEC_TEMPLATE: optional section, the three ops, the one-SHALL rule, derivation example
  assert_contains "$TEMPLATE" '## Deltas'
  assert_contains "$TEMPLATE" '### ADDED REQ-'
  assert_contains "$TEMPLATE" '### MODIFIED REQ-'
  assert_contains "$TEMPLATE" '### REMOVED REQ-'
  assert_contains "$TEMPLATE" 'SHALL'
  grep -qi 'optional' "$TEMPLATE" || log_fail "TEST-005: template must mark the Deltas section optional"
  grep -qiE 'exactly one SHALL|one SHALL' "$TEMPLATE" || log_fail "TEST-005: template must state the one-SHALL rule"
  assert_contains "$TEMPLATE" 'oauth2-login'
  assert_contains "$TEMPLATE" 'OAUTH2_LOGIN'

  # review F1: the template ships the whole `## Deltas` example inside an HTML
  # comment, so parsing the real template MUST report present:false (no phantom
  # deltas) — otherwise every template-derived spec would carry the example
  # blocks and the delta merge would write them into docs/canonical/.
  node_repo '
    import { parseDeltasSection } from "./.aai/scripts/lib/docs-model.mjs";
    import fs from "node:fs";
    const r = parseDeltasSection(fs.readFileSync(".aai/templates/SPEC_TEMPLATE.md", "utf8"));
    if (r.present || r.deltas.length) { console.error("SPEC_TEMPLATE Deltas example must parse INERT (commented)", r); process.exit(1); }
  ' || log_fail "TEST-005: SPEC_TEMPLATE commented Deltas example must parse present:false"

  # PLANNING: one paragraph on declaring Deltas when a change alters canonical requirements
  assert_contains "$PLANNING" 'Deltas'
  grep -qi 'canonical' "$PLANNING" || log_fail "TEST-005: PLANNING Deltas guidance must mention canonical requirements"
  grep -qi 'RFC-0011' "$PLANNING" || log_fail "TEST-005: PLANNING must reference RFC-0011 by content"

  # taxonomy guard: NO stage-N token on any edited .aai surface (hygiene-pack
  # review-taxonomy guard bans stage 1/stage-1/stage 2/... on .aai surfaces).
  local edited=(
    "$PROJECT_ROOT/.aai/scripts/spec-lint.mjs"
    "$PROJECT_ROOT/.aai/scripts/lib/docs-model.mjs"
    "$TEMPLATE"
    "$PLANNING"
  )
  if grep -rnE 'stage[ -][123]' "${edited[@]}"; then
    log_fail "TEST-005: a stage-N taxonomy token leaked onto an edited .aai surface"
  fi
  log_pass "TEST-005: template + PLANNING document the optional section, three ops, one-SHALL rule, derivation example; taxonomy clean"
}

# ---------------------------------------------------------------------------
# TEST-006 (Spec-AC-03) — seam survival: sibling suites + strict audit green
# ---------------------------------------------------------------------------
test_006_seam_survival() {
  log_info "TEST-006: existing spec-lint + delta-stage1 suites and strict audit survive the change (int)..."
  bash "$SCRIPT_DIR/test-aai-spec-lint.sh" > /tmp/aai-delta-stage2-speclint.log 2>&1 \
    || { tail -25 /tmp/aai-delta-stage2-speclint.log >&2; log_fail "TEST-006: spec-lint suite failed"; }
  bash "$SCRIPT_DIR/test-aai-delta-stage1.sh" > /tmp/aai-delta-stage2-stage1.log 2>&1 \
    || { tail -25 /tmp/aai-delta-stage2-stage1.log >&2; log_fail "TEST-006: delta-stage1 suite failed"; }
  (cd "$PROJECT_ROOT" && node .aai/scripts/docs-audit.mjs --check --strict --no-event >/dev/null 2>&1) \
    || log_fail "TEST-006: repo-wide strict audit failed"
  log_pass "TEST-006: spec-lint + delta-stage1 suites green; strict audit CLEAN (seam survival)"
}

# ---------------------------------------------------------------------------

main() {
  echo "=== Test: $TEST_NAME (spec-delta-stage-2 / RFC-0011 delta-spec lifecycle) ==="
  check_deps
  local only="${ONLY:-}"
  run_stanza() {
    local id="$1"; shift
    if [[ -z "$only" || "$only" == "$id" ]]; then "$@"; fi
  }
  run_stanza TEST-001 test_001_domain_reverse
  run_stanza TEST-002 test_002_parse_deltas
  run_stanza TEST-005 test_005_template_and_planning
  run_stanza TEST-006 test_006_seam_survival
  echo "=== All $TEST_NAME tests passed ==="
}

main "$@"
