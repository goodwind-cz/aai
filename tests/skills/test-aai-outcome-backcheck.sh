#!/usr/bin/env bash
set -euo pipefail

TEST_NAME="aai-outcome-backcheck"
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CHECKER="$PROJECT_ROOT/.aai/scripts/validation-outcome-check.mjs"
FIXTURES="$PROJECT_ROOT/tests/fixtures/outcome-backcheck"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/aai-outcome-backcheck.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

log_info() { echo "INFO: $*"; }
log_pass() { echo "PASS: $*"; }
CURRENT_TEST_ID=""
log_fail() { echo "FAIL: ${CURRENT_TEST_ID:-unknown}: $*" >&2; exit 1; }

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

run_check() {
  node "$CHECKER" "$@"
}

assert_refusal() {
  local expected=$1
  shift
  local output rc
  set +e
  output="$(run_check "$@" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 1 ]] || log_fail "expected evidence refusal (1), got $rc: $output"
  [[ "$output" == *"OUTCOME-CHECK: $expected"* ]] || log_fail "expected refusal '$expected', got: $output"
}

assert_admissible() {
  local output rc
  set +e
  output="$(run_check "$@" 2>&1)"; rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || log_fail "expected admissible report (0), got $rc: $output"
}

make_fixture() {
  local name=$1 kind=${2:-repository}
  local root="$TMP_ROOT/$name"
  mkdir -p "$root/evidence" "$root/output"
  printf '%s\n' '# Request' 'Deliver the requested result exactly.' > "$root/intake.md"
  printf '%s\n' '# Spec' '- Spec-AC-01: deliver the requested result.' > "$root/spec.md"
  printf '%s\n' 'verification passed' > "$root/evidence/check.log"
  printf '%s\n' 'DELIVERED' > "$root/output/final.txt"
  local intake_hash spec_hash evidence_hash target_hash
  intake_hash="$(sha256_file "$root/intake.md")"
  spec_hash="$(sha256_file "$root/spec.md")"
  evidence_hash="$(sha256_file "$root/evidence/check.log")"
  target_hash="$(sha256_file "$root/output/final.txt")"
  node - "$root" "$name" "$kind" "$intake_hash" "$spec_hash" "$evidence_hash" "$target_hash" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const [root, ref, kind, intakeHash, specHash, evidenceHash, targetHash] = process.argv.slice(2);
const target = kind === 'local_file'
  ? { kind, expected_identity: 'output/final.txt', observed_identity: 'output/final.txt', consumed_path: 'output/final.txt', consumed_sha256: targetHash }
  : kind === 'external'
    ? { kind, expected_identity: 'workspace/object@live', observed_identity: 'workspace/object@live', dynamic: true }
    : { kind, expected_identity: 'worktree/result', observed_identity: 'worktree/result' };
const persistence = kind === 'local_file'
  ? { applicable: true, boundary: 'saved' }
  : { applicable: false, reason: kind === 'repository' ? 'repository code only' : 'observation only' };
const operation = kind === 'local_file' ? 'reopen and read-back exact saved file' : 'run repository verification';
const data = {
  version: 1,
  ref,
  validation_started_utc: '2026-06-01T00:00:00Z',
  sources: [
    { kind: 'intake', path: 'intake.md', sha256: intakeHash },
    { kind: 'spec', path: 'spec.md', sha256: specHash },
  ],
  requirements: [{
    id: 'REQ-001',
    source: { path: 'intake.md', quote: 'Deliver the requested result exactly.' },
    constraint: 'Deliver the requested result exactly.',
    spec_ac_ids: ['Spec-AC-01'],
    assessment: 'aligned',
    rationale: 'The frozen spec and observed result preserve the request.',
    required: true,
    outcome_ids: ['OUT-001'],
  }],
  outcomes: [{
    id: 'OUT-001',
    requirement_ids: ['REQ-001'],
    target,
    verification: {
      operation,
      evidence_path: 'evidence/check.log',
      evidence_sha256: evidenceHash,
      observed_at_utc: '2026-06-01T00:01:00Z',
      result: 'satisfied',
    },
    persistence,
  }],
};
fs.writeFileSync(path.join(root, 'report.md'), `# Validation report\n\n\`\`\`aai-outcome-v1\n${JSON.stringify(data, null, 2)}\n\`\`\`\n`);
NODE
  printf '%s\n' "$root"
}

replace_once() {
  local file=$1 from=$2 to=$3
  node - "$file" "$from" "$to" <<'NODE'
const fs = require('node:fs');
const [file, from, to] = process.argv.slice(2);
const before = fs.readFileSync(file, 'utf8');
if (!before.includes(from)) process.exit(4);
fs.writeFileSync(file, before.replace(from, to));
NODE
}

replace_report_spec_ac() {
  local report=$1 spec=$2 ac_id=$3
  node - "$report" "$spec" "$ac_id" <<'NODE'
const fs = require('node:fs');
const crypto = require('node:crypto');
const [report, spec, acId] = process.argv.slice(2);
const before = fs.readFileSync(report, 'utf8');
const match = /```aai-outcome-v1\n([\s\S]*?)\n```/.exec(before);
if (!match) process.exit(4);
const data = JSON.parse(match[1]);
data.sources.find((source) => source.kind === 'spec').sha256 = crypto.createHash('sha256').update(fs.readFileSync(spec)).digest('hex');
data.requirements[0].spec_ac_ids = [acId];
fs.writeFileSync(report, before.replace(match[1], JSON.stringify(data, null, 2)));
NODE
}

make_state_fixture() {
  local name=$1 ref=${2:-original-request-outcome-backcheck}
  local primary_path=${3:-docs/issues/CHANGE-0189-original-request-outcome-backcheck.md}
  local spec_path=${4:-docs/specs/SPEC-0183-spec-original-request-outcome-backcheck.md}
  local state="$TMP_ROOT/$name-state.yaml"
  cp "$PROJECT_ROOT/.aai/templates/STATE_TEMPLATE.yaml" "$state"
  node "$PROJECT_ROOT/.aai/scripts/state.mjs" set-focus --state "$state" \
    --type intake_change --ref "$ref" \
    --path "$primary_path" --spec-path "$spec_path" >/dev/null
  node "$PROJECT_ROOT/.aai/scripts/state.mjs" set-strategy --state "$state" \
    --selected tdd --source "$spec_path" \
    --rationale fixture >/dev/null
  node "$PROJECT_ROOT/.aai/scripts/state.mjs" set-worktree --state "$state" \
    --recommendation recommended --user-decision worktree --base-ref HEAD \
    --branch fixture --path "$PROJECT_ROOT" --rationale fixture >/dev/null
  node - "$state" <<'NODE'
const fs = require('node:fs');
const file = process.argv[2];
const before = fs.readFileSync(file, 'utf8');
const after = before.replace('code_review:\n  required: false', 'code_review:\n  required: true');
if (after === before) process.exit(4);
fs.writeFileSync(file, after);
NODE
  printf '%s\n' "$state"
}

test_001_requirement_assessments() {
  log_info "TEST-001: aligned control passes; semantic gaps and violated outcomes refuse"
  local root variant assessment
  root="$(make_fixture test-001)"
  run_check --report report.md --ref test-001 --since 2026-06-01T00:00:00Z --root "$root" >/dev/null
  for assessment in omitted weakened unknown; do
    variant="$TMP_ROOT/test-001-$assessment"
    cp -R "$root" "$variant"
    replace_once "$variant/report.md" '"assessment": "aligned"' "\"assessment\": \"$assessment\""
    assert_refusal "requirement REQ-001 is $assessment" --report report.md --ref test-001 --since 2026-06-01T00:00:00Z --root "$variant"
  done
  variant="$TMP_ROOT/test-001-violated"
  cp -R "$root" "$variant"
  replace_once "$variant/report.md" '"result": "satisfied"' '"result": "violated"'
  assert_refusal 'outcome OUT-001 result is violated' --report report.md --ref test-001 --since 2026-06-01T00:00:00Z --root "$variant"
  log_pass "TEST-001 requirement assessments"
}

test_003_saved_target_identity() {
  log_info "TEST-003: exact saved target and consumed bytes are enforced"
  local root variant
  root="$(make_fixture test-003 local_file)"
  run_check --report report.md --ref test-003 --since 2026-06-01T00:00:00Z --root "$root" >/dev/null
  variant="$TMP_ROOT/test-003-canonical-equivalent"
  cp -R "$root" "$variant"
  replace_once "$variant/report.md" '"observed_identity": "output/final.txt"' '"observed_identity": "./output/final.txt"'
  replace_once "$variant/report.md" '"consumed_path": "output/final.txt"' '"consumed_path": "./output/final.txt"'
  run_check --report report.md --ref test-003 --since 2026-06-01T00:00:00Z --root "$variant" >/dev/null
  variant="$TMP_ROOT/test-003-preview"
  cp -R "$root" "$variant"
  replace_once "$variant/report.md" 'reopen and read-back exact saved file' 'render preview only'
  assert_refusal 'outcome OUT-001 lacks a read-back or reopen operation' --report report.md --ref test-003 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-003-wrong-path"
  cp -R "$root" "$variant"
  replace_once "$variant/report.md" '"observed_identity": "output/final.txt"' '"observed_identity": "output/draft.txt"'
  assert_refusal 'outcome OUT-001 target identity mismatch' --report report.md --ref test-003 --since 2026-06-01T00:00:00Z --root "$variant"
  printf '%s\n' 'CHANGED' > "$root/output/final.txt"
  assert_refusal 'outcome OUT-001 consumed file hash mismatch: output/final.txt' --report report.md --ref test-003 --since 2026-06-01T00:00:00Z --root "$root"
  log_pass "TEST-003 saved target identity"
}

test_004_verification_horizon() {
  log_info "TEST-004: dynamic evidence obeys the caller horizon; immutable local bytes are reusable"
  local root immutable
  root="$(make_fixture test-004 external)"
  assert_refusal 'outcome OUT-001 dynamic observation predates verification horizon' --report report.md --ref test-004 --since 2026-06-01T00:02:00Z --root "$root"
  run_check --report report.md --ref test-004 --since 2026-06-01T00:01:00Z --root "$root" >/dev/null
  immutable="$(make_fixture test-004-immutable local_file)"
  run_check --report report.md --ref test-004-immutable --since 2026-09-01T00:00:00Z --root "$immutable" >/dev/null
  printf '%s\n' 'NEW BYTES' > "$immutable/output/final.txt"
  assert_refusal 'outcome OUT-001 consumed file hash mismatch: output/final.txt' --report report.md --ref test-004-immutable --since 2026-09-01T00:00:00Z --root "$immutable"
  log_pass "TEST-004 verification horizon"
}

test_005_fail_closed_schema() {
  log_info "TEST-005: malformed, missing, duplicate, dangling, stale and contradictory data refuse"
  local root variant tick
  tick='`'
  root="$(make_fixture test-005)"
  run_check --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$root" >/dev/null

  variant="$TMP_ROOT/test-005-no-block"; cp -R "$root" "$variant"; replace_once "$variant/report.md" 'aai-outcome-v1' 'json'
  assert_refusal 'expected exactly one aai-outcome-v1 block, found 0' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-example-only"; cp -R "$root" "$variant"
  node - "$variant/report.md" <<'NODE'
const fs = require('node:fs');
const file = process.argv[2];
fs.writeFileSync(file, `\`\`\`\`markdown\n${fs.readFileSync(file, 'utf8')}\`\`\`\`\n`);
NODE
  assert_refusal 'expected exactly one aai-outcome-v1 block, found 0' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-unclosed-second"; cp -R "$root" "$variant"; printf '\n%s\n' '```aai-outcome-v1' '{"version": 1}' >> "$variant/report.md"
  assert_refusal 'unterminated aai-outcome-v1 block' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-duplicate-block"; cp -R "$root" "$variant"; printf '\n%s\n' '```aai-outcome-v1' '{}' '```' >> "$variant/report.md"
  assert_refusal 'expected exactly one aai-outcome-v1 block, found 2' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-malformed"; cp -R "$root" "$variant"; replace_once "$variant/report.md" '"version": 1' '"version": '
  assert_refusal 'aai-outcome-v1 JSON is malformed:' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-non-object"; cp -R "$root" "$variant"; printf '%s\n' '```aai-outcome-v1' 'null' '```' > "$variant/report.md"
  assert_refusal 'outcome block must be a JSON object' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-source"; cp -R "$root" "$variant"; replace_once "$variant/report.md" 'intake.md' 'missing.md'
  assert_refusal 'source intake is unreadable: missing.md' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-evidence"; cp -R "$root" "$variant"; replace_once "$variant/report.md" 'evidence/check.log' 'evidence/missing.log'
  assert_refusal 'outcome OUT-001 evidence is unreadable: evidence/missing.log' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-duplicate"; cp -R "$root" "$variant"; replace_once "$variant/report.md" '"outcomes": [' '"outcomes": [{"id":"OUT-001","requirement_ids":["REQ-001"],"target":{"kind":"repository","expected_identity":"x","observed_identity":"x"},"verification":{"operation":"x","evidence_path":"evidence/check.log","evidence_sha256":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","observed_at_utc":"2026-06-01T00:01:00Z","result":"satisfied"},"persistence":{"applicable":false,"reason":"x"}},'
  assert_refusal 'duplicate outcome id: OUT-001' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-dangling"; cp -R "$root" "$variant"; replace_once "$variant/report.md" '"outcome_ids": [' '"outcome_ids": ["OUT-MISSING", '
  assert_refusal 'requirement REQ-001 has dangling outcome link: OUT-MISSING' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-future"; cp -R "$root" "$variant"; replace_once "$variant/report.md" '2026-06-01T00:01:00Z' '2999-06-01T00:01:00Z'
  assert_refusal 'outcome OUT-001 observation is in the future' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-empty-ac"; cp -R "$root" "$variant"; replace_once "$variant/report.md" $'"spec_ac_ids": [\n        "Spec-AC-01"\n      ]' '"spec_ac_ids": []'
  assert_refusal 'aligned requirement REQ-001 must map to at least one Spec-AC' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-undefined-ac"; cp -R "$root" "$variant"; replace_once "$variant/report.md" '"Spec-AC-01"' '"Spec-AC-999"'
  assert_refusal 'requirement REQ-001 references undefined Spec-AC: Spec-AC-999' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-fenced-spec-ac"; cp -R "$root" "$variant"; printf '%s\n' '```markdown' '## Acceptance Criteria' '| Spec-AC | Description | Status |' '|---|---|---|' '| Spec-AC-999 | example only | done |' '```' >> "$variant/spec.md"; replace_report_spec_ac "$variant/report.md" "$variant/spec.md" Spec-AC-999
  assert_refusal 'requirement REQ-001 references undefined Spec-AC: Spec-AC-999' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-commented-spec-ac"; cp -R "$root" "$variant"; printf '%s\n' '<!--' '## Acceptance Criteria' '| Spec-AC | Description | Status |' '|---|---|---|' '| Spec-AC-999 | example only | done |' '-->' >> "$variant/spec.md"; replace_report_spec_ac "$variant/report.md" "$variant/spec.md" Spec-AC-999
  assert_refusal 'requirement REQ-001 references undefined Spec-AC: Spec-AC-999' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-second-spec-table"; cp -R "$root" "$variant"; printf '%s\n' '# Spec' '## Acceptance Criteria' '' '| Spec-AC | Description | Status |' '|---|---|---|' '| Spec-AC-01 | defined criterion | done |' '' '| Spec-AC | Description | Status |' '|---|---|---|' '| Spec-AC-999 | later illustration | done |' > "$variant/spec.md"; replace_report_spec_ac "$variant/report.md" "$variant/spec.md" Spec-AC-999
  assert_refusal 'requirement REQ-001 references undefined Spec-AC: Spec-AC-999' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-malformed-first-table"; cp -R "$root" "$variant"; printf '%s\n' '## Acceptance Criteria Status' '| Spec-AC | Description | Status | Review-By |' '| INVALID SEPARATOR |' '| Spec-AC-02 | actual | done | |' '' 'Example only:' '| Spec-AC | Description | Status | Review-By |' '|---|---|---|---|' '| Spec-AC-01 | illustration | done | |' > "$variant/spec.md"; replace_report_spec_ac "$variant/report.md" "$variant/spec.md" Spec-AC-01
  assert_refusal 'requirement REQ-001 references undefined Spec-AC: Spec-AC-01' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-multiline-inline-list-declaration"; cp -R "$root" "$variant"; printf '%s\n' '# Spec' "Example $tick" '- Spec-AC-01: actual list declaration.' "$tick ends here." > "$variant/spec.md"; replace_report_spec_ac "$variant/report.md" "$variant/spec.md" Spec-AC-01
  assert_admissible --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-multiline-inline-then-compact"; cp -R "$root" "$variant"; printf '%s\n' '# Spec' "Example $tick" '- Spec-AC-999: fake example.' "$tick ends here." '- Spec-AC-01: actual declaration.' > "$variant/spec.md"; replace_report_spec_ac "$variant/report.md" "$variant/spec.md" Spec-AC-01
  assert_admissible --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-unmatched-before-fence"; cp -R "$root" "$variant"; printf '%s\n' '# Spec' "A literal unmatched $tick marker." '```markdown' "- Spec-AC-999: example $tick text." '```' '## Acceptance Criteria Status' '| Spec-AC | Description | Status | Review-By |' '|---|---|---|---|' '| Spec-AC-01 | desired condition | done | |' > "$variant/spec.md"; replace_report_spec_ac "$variant/report.md" "$variant/spec.md" Spec-AC-01
  assert_admissible --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-unmatched-before-paragraph"; cp -R "$root" "$variant"; printf '%s\n' '# Spec' "A literal unmatched $tick marker." '' '- Spec-AC-01: actual declaration.' > "$variant/spec.md"; replace_report_spec_ac "$variant/report.md" "$variant/spec.md" Spec-AC-01
  assert_admissible --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-unmatched-at-eof"; cp -R "$root" "$variant"; printf '%s\n' '# Spec' '- Spec-AC-01: actual declaration.' "A literal unmatched $tick marker." > "$variant/spec.md"; replace_report_spec_ac "$variant/report.md" "$variant/spec.md" Spec-AC-01
  assert_admissible --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-lean-status"; cp -R "$root" "$variant"; printf '%s\n' '## Acceptance Criteria Status' '| Spec-AC | Description | Status |' '|---|---|---|' '| Spec-AC-01 | defined criterion | done |' > "$variant/spec.md"; replace_report_spec_ac "$variant/report.md" "$variant/spec.md" Spec-AC-01
  assert_admissible --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-inline-span"; cp -R "$root" "$variant"; printf '%s\n' '``` x ```' '## Acceptance Criteria Status' '| Spec-AC | Description | Status | Review-By |' '|---|---|---|---|' '| Spec-AC-01 | defined criterion | done | |' > "$variant/spec.md"; replace_report_spec_ac "$variant/report.md" "$variant/spec.md" Spec-AC-01
  assert_admissible --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-comment-in-fence"; cp -R "$root" "$variant"; printf '%s\n' '```html' '<!--' '```' '## Acceptance Criteria Status' '| Spec-AC | Description | Status | Review-By |' '|---|---|---|---|' '| Spec-AC-01 | defined criterion | done | |' > "$variant/spec.md"; replace_report_spec_ac "$variant/report.md" "$variant/spec.md" Spec-AC-01
  assert_admissible --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-comment-in-inline"; cp -R "$root" "$variant"; printf '%s\n' 'Text `<!--` is example syntax.' '## Acceptance Criteria Status' '| Spec-AC | Description | Status | Review-By |' '|---|---|---|---|' '| Spec-AC-01 | defined criterion | done | |' > "$variant/spec.md"; replace_report_spec_ac "$variant/report.md" "$variant/spec.md" Spec-AC-01
  assert_admissible --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-lone-cr"; cp -R "$root" "$variant"; node - "$variant/spec.md" <<'NODE'
const fs = require('node:fs');
fs.writeFileSync(process.argv[2], '## Acceptance Criteria Status\n| Spec-AC | Description | Status | Review-By |\n|---|---|---|---|\n| Spec-AC-01 | defined criterion | done | |\n'.replaceAll('\n', '\r'));
NODE
  replace_report_spec_ac "$variant/report.md" "$variant/spec.md" Spec-AC-01
  assert_admissible --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-malformed-ac"; cp -R "$root" "$variant"
  node - "$variant/report.md" <<'NODE'
const fs = require('node:fs');
const file = process.argv[2];
const markdown = fs.readFileSync(file, 'utf8');
const match = /^```aai-outcome-v1\n([\s\S]*?)^```$/m.exec(markdown);
const data = JSON.parse(match[1]);
data.requirements[0].spec_ac_ids = [null];
fs.writeFileSync(file, markdown.replace(match[1], `${JSON.stringify(data, null, 2)}\n`));
NODE
  assert_refusal 'requirement REQ-001 has malformed Spec-AC link' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-malformed-reciprocal"; cp -R "$root" "$variant"
  node - "$variant/report.md" <<'NODE'
const fs = require('node:fs');
const file = process.argv[2];
const markdown = fs.readFileSync(file, 'utf8');
const match = /^```aai-outcome-v1\n([\s\S]*?)^```$/m.exec(markdown);
const data = JSON.parse(match[1]);
data.requirements[0].outcome_ids = {};
fs.writeFileSync(file, markdown.replace(match[1], `${JSON.stringify(data, null, 2)}\n`));
NODE
  assert_refusal 'requirement REQ-001 has no outcome links' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  variant="$TMP_ROOT/test-005-crossed-links"; cp -R "$root" "$variant"
  node - "$variant/report.md" <<'NODE'
const fs = require('node:fs');
const file = process.argv[2];
const markdown = fs.readFileSync(file, 'utf8');
const match = /^```aai-outcome-v1\n([\s\S]*?)^```$/m.exec(markdown);
const data = JSON.parse(match[1]);
data.requirements.push({ ...data.requirements[0], id: 'REQ-002', outcome_ids: ['OUT-002'] });
data.requirements[0].outcome_ids = ['OUT-001'];
data.outcomes.push({ ...data.outcomes[0], id: 'OUT-002', requirement_ids: ['REQ-001'] });
  data.outcomes[0].requirement_ids = ['REQ-002'];
  fs.writeFileSync(file, markdown.replace(match[1], `${JSON.stringify(data, null, 2)}\n`));
NODE
  assert_refusal 'requirement REQ-001 link to OUT-001 is not reciprocal' --report report.md --ref test-005 --since 2026-06-01T00:00:00Z --root "$variant"
  local usage_output usage_rc
  set +e
  usage_output="$(run_check --report report.md --ref test-005 --since not-a-date --root "$root" 2>&1)"; usage_rc=$?
  set -e
  [[ "$usage_rc" -eq 2 ]] || log_fail "invalid --since expected usage exit 2, got $usage_rc: $usage_output"
  [[ "$usage_output" == *'validation-outcome-check: --since is not a valid ISO-8601 UTC timestamp'* ]] \
    || log_fail "invalid --since expected usage diagnostic, got: $usage_output"
  log_pass "TEST-005 fail-closed schema"
}

test_007_prompt_sequence() {
  log_info "TEST-007: real checker gates state mutation and visual rewrite rechecks preserved block"
  local validation="$PROJECT_ROOT/.aai/VALIDATION.prompt.md"
  local visual="$PROJECT_ROOT/.aai/SKILL_VALIDATE_REPORT.prompt.md"
  local check_line state_line preserve_line rerun_line root state before after poison visual_report rc
  check_line="$(awk '/validation-outcome-check\.mjs/{print NR; exit}' "$validation")"
  state_line="$(awk '/state\.mjs set-validation/{print NR; exit}' "$validation")"
  [[ -n "$check_line" && -n "$state_line" && "$check_line" -lt "$state_line" ]] || log_fail "Validation prompt must check outcome before set-validation"
  preserve_line="$(awk '/aai-outcome-v1/{print NR; exit}' "$visual")"
  rerun_line="$(awk '/validation-outcome-check\.mjs/{print NR; exit}' "$visual")"
  [[ -n "$preserve_line" && -n "$rerun_line" && "$preserve_line" -lt "$rerun_line" ]] || log_fail "visual report prompt must preserve block and rerun checker"
  root="$(make_fixture test-007 local_file)"
  state="$(make_state_fixture test-007)"
  run_check --report report.md --ref test-007 --since 2026-06-01T00:00:00Z --root "$root" >/dev/null
  before="$(sha256_file "$state")"
  node "$PROJECT_ROOT/.aai/scripts/state.mjs" set-validation --state "$state" \
    --status pass --ref test-007 --evidence "$root/report.md" --notes fixture >/dev/null
  after="$(sha256_file "$state")"
  [[ "$before" != "$after" ]] || log_fail "admissible report did not reach the real state CLI"
  grep -F "$root/report.md" "$state" >/dev/null || log_fail "state evidence does not name the checked report"

  poison="$root/poison.md"
  cp "$root/report.md" "$poison"
  replace_once "$poison" '"result": "satisfied"' '"result": "violated"'
  before="$(sha256_file "$state")"
  rc=0
  if run_check --report poison.md --ref test-007 --since 2026-06-01T00:00:00Z --root "$root" >/dev/null 2>&1; then
    node "$PROJECT_ROOT/.aai/scripts/state.mjs" set-validation --state "$state" \
      --status pass --ref test-007 --evidence "$poison" --notes poison >/dev/null
  else
    rc=$?
  fi
  [[ "$rc" -eq 1 ]] || log_fail "poison evidence must be refused before state mutation"
  after="$(sha256_file "$state")"
  [[ "$before" == "$after" ]] || log_fail "poison evidence changed state despite checker refusal"

  visual_report="$root/visual-report.md"
  cp "$root/report.md" "$visual_report"
  printf '\n## Screenshot gallery\n\nNo screenshots were required.\n' >> "$visual_report"
  run_check --report visual-report.md --ref test-007 --since 2026-06-01T00:00:00Z --root "$root" >/dev/null
  log_pass "TEST-007 checker/state/visual sequence"
}

test_008_loop_resume_wiring() {
  log_info "TEST-008: two real horizons route standing PASS to Code Review or fresh Validation"
  local loop="$PROJECT_ROOT/.aai/SKILL_LOOP.prompt.md"
  local invalidate_line phase_line
  grep 'validation-outcome-check.mjs' "$loop" >/dev/null || log_fail "loop lacks outcome checker invocation"
  grep 'LOOP_VERIFICATION_HORIZON' "$loop" >/dev/null || log_fail "loop lacks verification horizon contract"
  grep 'fresh Validation' "$loop" >/dev/null || log_fail "loop lacks refused-report routing to fresh Validation"
  invalidate_line="$(awk '/set-validation --status not_run --ref <focus-ref>/{print NR; exit}' "$loop")"
  phase_line="$(awk '/set-phase --ref <focus-ref> --phase validation/{print NR; exit}' "$loop")"
  [[ -n "$invalidate_line" && -n "$phase_line" && "$invalidate_line" -lt "$phase_line" ]] \
    || log_fail "refused standing PASS must invalidate last_validation before validation phase routing"
  local root state dispatch immutable before_focus after_focus fixture_ref=test-008-resume
  local fixture_intake="$FIXTURES/dispatch-eligible-intake.md"
  local fixture_spec="$FIXTURES/dispatch-eligible-spec.md"
  if grep -F '"event":"validation_verdict","ref":"test-008-resume"' "$PROJECT_ROOT/docs/ai/EVENTS.jsonl" >/dev/null; then
    log_fail "TEST-008 fixture ref must not reuse a historical validation verdict"
  fi
  root="$(make_fixture "$fixture_ref" external)"
  state="$(make_state_fixture test-008 "$fixture_ref" "$fixture_intake" "$fixture_spec")"
  before_focus="$(awk '/^current_focus:/{inside=1;next} inside && /ref_id:/{print $2;exit}' "$state")"

  run_check --report report.md --ref "$fixture_ref" \
    --since 2026-06-01T00:00:00Z --root "$root" >/dev/null
  node "$PROJECT_ROOT/.aai/scripts/state.mjs" set-validation --state "$state" \
    --status pass --ref "$fixture_ref" --evidence "$root/report.md" --notes fresh >/dev/null
  node "$PROJECT_ROOT/.aai/scripts/state.mjs" set-phase --state "$state" \
    --ref "$fixture_ref" --phase validation --status done >/dev/null
  dispatch="$TMP_ROOT/test-008-code-review.json"
  node "$PROJECT_ROOT/.aai/scripts/orchestration-dispatch.mjs" --state "$state" --root "$PROJECT_ROOT" > "$dispatch"
  node - "$dispatch" <<'NODE'
const fs = require('node:fs');
const data = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (data.verdict !== 'dispatch' || data.role !== 'Code Review') process.exit(1);
NODE

  assert_refusal 'outcome OUT-001 dynamic observation predates verification horizon' \
    --report report.md --ref "$fixture_ref" \
    --since 2026-06-01T00:02:00Z --root "$root"
  node "$PROJECT_ROOT/.aai/scripts/state.mjs" set-validation --state "$state" \
    --status not_run --ref "$fixture_ref" --notes refresh >/dev/null
  node "$PROJECT_ROOT/.aai/scripts/state.mjs" set-phase --state "$state" \
    --ref "$fixture_ref" --phase validation --status in_progress >/dev/null
  dispatch="$TMP_ROOT/test-008-validation.json"
  node "$PROJECT_ROOT/.aai/scripts/orchestration-dispatch.mjs" --state "$state" --root "$PROJECT_ROOT" > "$dispatch"
  node - "$dispatch" <<'NODE'
const fs = require('node:fs');
const data = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
if (data.verdict !== 'dispatch' || data.role !== 'Validation') process.exit(1);
NODE
  after_focus="$(awk '/^current_focus:/{inside=1;next} inside && /ref_id:/{print $2;exit}' "$state")"
  [[ "$before_focus" == "$after_focus" ]] || log_fail "resume routing changed an unrelated/current focus"

  immutable="$(make_fixture test-008-immutable local_file)"
  run_check --report report.md --ref test-008-immutable --since 2026-09-01T00:00:00Z --root "$immutable" >/dev/null
  printf '%s\n' 'changed after validation' > "$immutable/output/final.txt"
  assert_refusal 'outcome OUT-001 consumed file hash mismatch: output/final.txt' \
    --report report.md --ref test-008-immutable --since 2026-09-01T00:00:00Z --root "$immutable"
  assert_refusal 'report is unreadable: missing-legacy.md' \
    --report missing-legacy.md --ref "$fixture_ref" \
    --since 2026-06-01T00:02:00Z --root "$root"
  log_pass "TEST-008 two-horizon state/dispatch resume"
}

test_012_cli_symlink_entrypoint() {
  log_info "TEST-012: symlinked checker entrypoint runs its CLI"
  local root target link symlinked_root help_output help_rc
  root="$(make_fixture test-012 local_file)"
  target="$TMP_ROOT/validation-outcome-check-real.mjs"
  link="$TMP_ROOT/validation-outcome-check-link.mjs"
  symlinked_root="$TMP_ROOT/test-012-symlinked-root"
  cp "$CHECKER" "$target"
  ln -s "$target" "$link"
  ln -s "$root" "$symlinked_root"
  set +e
  help_output="$(node "$link" --help 2>&1)"; help_rc=$?
  set -e
  [[ "$help_rc" -eq 0 ]] || log_fail "symlinked --help expected exit 0, got $help_rc: $help_output"
  [[ "$help_output" == *'validate one aai-outcome-v1 JSON report block'* ]] \
    || log_fail "symlinked --help did not run the checker CLI: $help_output"
  node "$link" --report report.md --ref test-012 --since 2026-06-01T00:00:00Z --root "$symlinked_root" >/dev/null
  log_pass "TEST-012 symlinked CLI entrypoint"
}

test_010_code_only_and_compatibility() {
  log_info "TEST-010: concise repository-only outcome needs no GUI/account/save fields"
  local root
  root="$(make_fixture test-010 repository)"
  run_check --report report.md --ref test-010 --since 2026-06-01T00:00:00Z --root "$root" >/dev/null
  if grep -E 'account|workspace_id|screenshot|saved_path' "$root/report.md" >/dev/null; then
    log_fail "repository-only control fabricated GUI/account/persistence fields"
  fi
  log_pass "TEST-010 code-only compatibility"
}

score_semantic_reports() {
  local reports=$1
  [[ -d "$reports" ]] || log_fail "semantic report directory does not exist: $reports"
  node - "$CHECKER" "$FIXTURES" "$reports" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const [checkerPath, fixtures, reports] = process.argv.slice(2);
(async () => {
  const { checkOutcomeReport } = await import(pathToFileURL(checkerPath));
  const oracle = JSON.parse(fs.readFileSync(path.join(fixtures, 'oracle.json'), 'utf8'));
  const files = fs.readdirSync(reports).filter((name) => /^scenario-\d\d\.md$/.test(name)).sort();
  const expectedFiles = oracle.cases.map((entry) => `${entry.ref}.md`).sort();
  if (JSON.stringify(files) !== JSON.stringify(expectedFiles)) throw new Error(`expected exactly ${expectedFiles.join(', ')}, got ${files.join(', ')}`);
  function filesBelow(root, relative = '') {
    const current = path.join(root, relative);
    if (!fs.existsSync(current)) return [];
    const stat = fs.statSync(current);
    if (stat.isFile()) return [relative];
    return fs.readdirSync(current).sort().flatMap((name) => filesBelow(root, path.join(relative, name)));
  }
  let correct = 0;
  for (const expected of oracle.cases) {
    const reportPath = path.resolve(reports, `${expected.ref}.md`);
    const runtimeRoot = path.join(reports, 'inputs', expected.ref);
    if (!fs.statSync(runtimeRoot, { throwIfNoEntry: false })?.isDirectory()) throw new Error(`${expected.ref}: archived runtime input root is missing`);
    const canonicalRoot = path.join(fixtures, 'scenarios', expected.ref);
    const pinned = ['request.md', 'spec.md', ...filesBelow(canonicalRoot, 'worktree')].sort();
    for (const relative of pinned) {
      const canonical = fs.readFileSync(path.join(canonicalRoot, relative));
      let archived;
      try { archived = fs.readFileSync(path.join(runtimeRoot, relative)); }
      catch { throw new Error(`${expected.ref}: archived input is missing ${relative}`); }
      if (!canonical.equals(archived)) throw new Error(`${expected.ref}: archived input differs from canonical ${relative}`);
    }
    const markdown = fs.readFileSync(reportPath, 'utf8');
    const blocks = [...markdown.matchAll(/^```aai-outcome-v1[ \t]*\r?\n([\s\S]*?)^```[ \t]*$/gm)];
    if (blocks.length !== 1) throw new Error(`${expected.ref}: expected one aai-outcome-v1 block, got ${blocks.length}`);
    const data = JSON.parse(blocks[0][1]);
    const assessments = data.requirements?.map((entry) => entry.assessment) ?? [];
    const results = data.outcomes?.map((entry) => entry.verification?.result) ?? [];
    const verdict = assessments.every((value) => value === 'aligned') && results.every((value) => value === 'satisfied') ? 'pass' : 'fail';
    if (verdict !== expected.verdict) throw new Error(`${expected.ref}: expected ${expected.verdict}, got ${verdict}`);
    if (!assessments.includes(expected.assessment)) throw new Error(`${expected.ref}: missing assessment ${expected.assessment}`);
    const normalize = (value) => String(value ?? '').replace(/\s+/g, ' ').trim();
    const cited = data.requirements?.some((entry) => normalize(entry.source?.quote).includes(normalize(expected.citation)));
    if (!cited) throw new Error(`${expected.ref}: missing required original-request citation`);
    if (verdict === 'pass') {
      const checked = checkOutcomeReport({
        reportPath,
        ref: expected.ref,
        since: data.validation_started_utc,
        root: runtimeRoot,
      });
      if (!checked.ok) throw new Error(`${expected.ref}: positive report is not checker-admissible: ${checked.reasons.join('; ')}`);
    }
    correct += 1;
    process.stdout.write(`PASS: ${expected.ref} ${verdict} ${expected.assessment}\n`);
  }
  process.stdout.write(`SEMANTIC SCORE: ${correct}/${oracle.cases.length}\n`);
})().catch((error) => { process.stderr.write(`FAIL: ${error.message}\n`); process.exitCode = 1; });
NODE
}

main() {
  if [[ "${1:-}" == "--semantic-reports" ]]; then
    [[ -n "${2:-}" ]] || log_fail "--semantic-reports requires a directory"
    [[ $# -eq 2 ]] || log_fail "unknown semantic scorer arguments"
    score_semantic_reports "$2"
    return
  fi
  [[ $# -le 1 ]] || log_fail "unknown selector: $*"
  [[ -f "$CHECKER" ]] || log_fail "missing checker: $CHECKER"
  local selected="${1:-all}"
  case "$selected" in
    all)
      CURRENT_TEST_ID=TEST-001; test_001_requirement_assessments
      CURRENT_TEST_ID=TEST-003; test_003_saved_target_identity
      CURRENT_TEST_ID=TEST-004; test_004_verification_horizon
      CURRENT_TEST_ID=TEST-005; test_005_fail_closed_schema
      CURRENT_TEST_ID=TEST-007; test_007_prompt_sequence
      CURRENT_TEST_ID=TEST-008; test_008_loop_resume_wiring
      CURRENT_TEST_ID=TEST-012; test_012_cli_symlink_entrypoint
      CURRENT_TEST_ID=TEST-010; test_010_code_only_and_compatibility
      ;;
    test_001_requirement_assessments) CURRENT_TEST_ID=TEST-001; test_001_requirement_assessments ;;
    test_003_saved_target_identity) CURRENT_TEST_ID=TEST-003; test_003_saved_target_identity ;;
    test_004_verification_horizon) CURRENT_TEST_ID=TEST-004; test_004_verification_horizon ;;
    test_005_fail_closed_schema) CURRENT_TEST_ID=TEST-005; test_005_fail_closed_schema ;;
    test_007_prompt_sequence) CURRENT_TEST_ID=TEST-007; test_007_prompt_sequence ;;
    test_008_loop_resume_wiring) CURRENT_TEST_ID=TEST-008; test_008_loop_resume_wiring ;;
    test_012_cli_symlink_entrypoint) CURRENT_TEST_ID=TEST-012; test_012_cli_symlink_entrypoint ;;
    test_010_code_only_and_compatibility) CURRENT_TEST_ID=TEST-010; test_010_code_only_and_compatibility ;;
    *) log_fail "unknown selector: $selected" ;;
  esac
  echo "=== ALL TESTS PASSED: $TEST_NAME ==="
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
