# PR 388 external-review triage

Reviewed snapshot: 44456f85c9f70b80f3462045d4d6fd96e6c353be. Numbered SPEC-0183 and CHANGE-0189 read. Shipping source, STATE and git untouched. No outbound comments sent. Entire HEAD was archived read-only into /tmp/aai-outcome-independent-review2/external; tests used its canonical wrapper. AAI_ROLE=subagent remained set. No git repository was created or modified. Scratch copies only; external/raw contains command/stdout/stderr/exit records.

| Comment | Classification | Disposition |
|---|---|---|
| 4080183829 | disputed | Outside-root acceptance is reproduced, but a generic checker report containment requirement is not in the frozen contract. Keep existing generic API; explain actual trust boundary and intentional separate-report-root use. |
| 4080183860 | disputed | Production changelog AWK parser exits 0 and rolls the feature entry. The next same-level heading terminates the bare scaffold's empty body; no parser fix is warranted. |
| 4080201437 | real, BLOCKING | TEST-008 is red after the feature spec closes. Remediate the test fixture in tree with an independently created frozen implementing spec; preserve failing-first evidence. |
| 4080201445 | duplicate of disputed 4080183829 | Same unrestricted report locator, with a retention rationale. No additional concrete handoff defect beyond that behavior is established. Runtime report retention is explicitly outside the contract; canonical reports are also ephemeral/uncommitted. |

## Confirmed TEST-008 failure and isolation control

Current suite source points every fixture at docs/specs/SPEC-0183-spec-original-request-outcome-backcheck.md (make_state_fixture, lines 116-126). The feature spec has status: done. Unmodified selected TEST-008 exits 1 (test008-second.*). Diagnostic source-only harness calls the same function and captures the dispatch before its assertion exits (route-probe.*, route-dispatch.json): verdict=dispatch, rule=6, role=Planning, ref=test-008-resume; spec.present=true, frozen=true, frontmatter_status=done. This precisely reaches the reported failure, rather than an infrastructure gate.

Changing ONLY the scratch copy's spec status from done to implementing makes the identical selected test pass exit 0 (test008-control.*). The original scratch spec bytes are retained in spec-original.md. This is a causal control, not the proposed shipping fix: never reopen the delivered feature spec merely to satisfy this test.

Minimal proposed fix: make_state_fixture should create its own tiny intake and frozen spec under TMP_ROOT, with id spec-<fixture-ref>, status implementing, ceremony_level 2 and SPEC-FROZEN: true. Pass their absolute fixture paths to set-focus and the fixture spec to set-strategy; dispatch already resolves absolute paths against root. Keep unique synthetic ref test-008-resume and the guard against reusing historical feature verdicts. Do not change production orchestration/state engines. A positive test must continue to reach Code Review, then Validation after invalidation; demonstrate that closing/renumbering/removing the real feature document has no effect on the synthetic fixture. A single copied implementing spec override is insufficient hermeticity.

The first attempt (test008.*) used temp fixtures under the archived project root and was refused by the existing single-writer guard, exit 3. It is explicitly infrastructure evidence, not the qualifying failure. The decisive reruns use TMPDIR=/tmp/aai-outcome-independent-review2/temp, a sibling outside the archived project. AAI_TEST_ISOLATION=0 is deliberate because the entire test CWD is already the copied artifact root; its generic shipping warning does not mean the actual delivery tree was touched. The diagnostic harness preserves temp artifacts in that same named scratch root.

## Report path observations and contract

report-probe.mjs invokes actual check-role-output on a valid envelope in three cases: repository-relative report, absolute report in the scratch parent, and ../outside-authoritative.md. Each exits 0 (relative/absolute/traversal.{stdout,stderr,exit}). Thus the behavior cited by both comments is real; the claimed contract violation is disputed.

SPEC-0183 D1 explicitly requires repository-relative paths for intake/spec sources, and rehashes source/evidence/consumed files against root. D2 documents --report <path>, with no corresponding report-locator containment rule. The report is a separately supplied input. The semantic scorer intentionally resolves reportPath to an absolute path at test-aai-outcome-backcheck.sh:408 and checks it with root: runtimeRoot at :437, which is the sibling inputs/scenario root. Enforcing resolveLocal on the shared report locator breaks that designed use. The normal producer must write docs/ai/reports/VALIDATION-*.md (VALIDATION.prompt.md:227), but this is producer/prompt guidance; neither spec AC-06 nor D3 requires the mechanical handoff to enforce a directory allowlist. No elevated permission, sandbox boundary, network request, or report-content execution is present.

The P2 retention narrative is not closed by directory confinement: docs/USER_GUIDE.md:731-732 explicitly calls the canonical directory ephemeral and uncommitted; D3 deliberately revalidates missing legacy/current evidence at resume. The same report disappears on another checkout whether it originally lived in /tmp or docs/ai/reports. A new handoff-only directory policy could be a separately specified hardening change, but is not justified as a required bug fix here. Do not add a superficial lexical check and claim symlink confinement or durability.

## Changelog parser reproduction

Extracted the exact unchanged AWK heredoc from aai-release.sh into release-parser.awk and ran it through the wrapper against archived current CHANGELOG.md. parser-probe.exit and changelog-parser.exit are 0. rolled.md contains the versioned feature heading and notes.md retains its feature text. Parser lines 250-260 enumerate each /^## / heading and set body_end to the next heading minus one; lines 265-270 classify the first bare heading as an empty SCAFFOLD. No git release/cut/push operation was run.

## Independence and limits

Before receiving the parent's subsequent contract interpretation, the reviewer had already reported the parser refutation, outside-root behavior, intentional semantic scorer use, and done-spec cause. The parent later directed preservation of the generic API; this did not change the independent classifications or omit a scope. This is a bounded four-thread triage, not a new full-scope PASS. The confirmed test regression blocks current PR readiness until fixed and revalidated. CI is watched by the parent; no CI conclusion is claimed here. Model/usage identity is unavailable.

## Timed result

```yaml
subagent_result:
  scope: original-request-outcome-backcheck-pr388-external-triage
  role: Code Review
  status: FAIL
  started_utc: 2026-09-23T07:53:45Z
  ended_utc: 2026-09-23T07:58:09Z
  duration_seconds: 264
  evidence:
    - command: "Canonical wrapped TEST-008 on HEAD archive with temporary fixtures outside archived project root"
      exit_code: 1
      output_snippet: "Captured dispatch rule 6 Planning; frozen spec frontmatter_status done."
    - command: "Identical selected TEST-008 after scratch-only status implementing control"
      exit_code: 0
      output_snippet: "PASS: TEST-008 two-horizon state/dispatch resume"
    - command: "Canonical wrapped report-probe.mjs"
      exit_code: 0
      output_snippet: "relative=0; absolute=0; traversal=0; behavior confirmed, proposed generic restriction disputed."
    - command: "Canonical wrapped exact production changelog AWK parser"
      exit_code: 0
      output_snippet: "Feature entry rolled and retained in notes; empty scaffold accepted."
  files_changed: []
  blockers:
    - "4080201437: current TEST-008 depends on closed production spec and fails; fixture must be hermetic."
  state_update_commands: []
```
