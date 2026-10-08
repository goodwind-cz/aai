```yaml
review:
  scope: "8dd7a88a59a43ed094088b17361ca08cd13c855a to working tree; 33 paths pinned in pr434-case-20261008T114239Z/boundary.json"
  spec: docs/specs/SPEC-0212-spec-pr-github-case-identity.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:271; TEST-007; pr434-case-20261008T114239Z/test007.log and probes.log" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:207 and :221; TEST-001; pr434-case-20261008T114239Z/test001.log and probes.log" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Native Windows and full CI on the repaired integrated source", closes_with: "Source-bound final native/full CI; published 1691 source is older" }
    - { claim: "Parent integration and mutation validity after this source change", closes_with: "Root final assembly Review, parent eight and first-child two mutation remeasurements, fresh parent Validation, metadata closure and external sweep" }
    - { claim: "Live provider behavior or future create permission", closes_with: "Authorized live provider checks; invocation-time read fixtures do not establish future writes" }
    - { claim: "Maker/validator/reviewer model-weight independence", closes_with: "Harness serving-model attestations; requested model names are insufficient" }
  overall: pass
```

# Child review: pr-github-case-identity

Both verdicts PASS for ISSUE-0095 / SPEC-0212. No new findings or warnings. This is not parent PR434 delivery approval.

## Scope and independence

Read STATE (worktree.user_decision=worktree, inline_review_scope=null), status and the actual working-tree diff against 8dd7a88a59a43ed094088b17361ca08cd13c855a. HEAD equals that base; base...HEAD would incorrectly review an empty scope. The explicit 33-path boundary includes four tracked modifications and the supplied ignored evidence companions. Reviewed source, tests, spec status edits, the one appended validation event, maker/validator manifests and root handoff companions. All 33 hashes match; STATE and raw NUL index match the supplied boundary; base EVENTS bytes remain an exact prefix. Scope and artifact pins are retained, without copying historical evidence.

Anti-gaming disclosure: the dispatch characterized expected metadata as “not fakeparentdone”, described source behavior and earlier proof as successful, and characterized N1 as already filed. These are coaching/expected-outcome statements, not review evidence. I independently inspected the full supplied scope and checked the cited ledger entry, boundary, diff, proof records and outcome schema. No implementation area in the supplied scope was excluded on that basis. This is a fresh context; actual model identities are unknown. No self-dispatch, source/index/STATE/lifecycle/ledger write or external action occurred.

## Spec compliance evidence

| AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | Source :146-149 implements ASCII-only folding; :271 compares both provider name and URL path. TEST-007 at suite :200-207 covers each field and both together with exact argv and three probes, and different owner/repository in each field. Fresh test007.log passes. Fresh probes.log additionally verifies simultaneous input/name/path casing on public and enterprise hosts and SSH443. |
| Spec-AC-02 | compliant | Source :221 folds input identity while :207 retains exact fetch/push bytes. Suite :105-108 verifies positive input and two zero-provider mismatches; :141 verifies case-only endpoint divergence at git.push-destination. Fresh test001.log passes. |

TEST-001 and TEST-007 exist, remain registered and pass independently through the canonical wrapper. The source uses existing standard String APIs only. No dependencies, route capabilities, provider argv or native extraction delimiters changed. No semantic AC deviation was found. One literal Test Plan example differs: checked-in TEST-001 uses org/Repo rather than org/repo; independent combined-casing probes exercise both segments, including lower-case org/repo on SSH443. This does not change the acceptance behavior.

Stored RED is actual exit 2 versus expected 0 for input and exit 3 versus expected 0 for provider fields, on the pinned shipping ancestor. Current mutation patches restore precisely the respective old comparisons, and their records target current source e0d14f2b5dc9d5726fbae36e03b1bb346204c459cd6ab988015b57069396caaf. The validator's sealed replay reports two RED, zero inconclusive and zero restamps; this review inspected that evidence rather than rerunning a redundant mutation sweep. Earlier timestamped records remain historical. Root raw handoff retains the misspelled spec path and a separate normalization receipt identifies it; no corrected historical record was substituted. The validator's aai-outcome-v1 report was independently accepted by validation-outcome-check (exit 0). Maker 14 immutable pins and validator 16 immutable pins match; validator STATE/EVENTS were subsequently advanced by root and are historical pins, not claimed equal to current state.

The maker full8row log contains eight PASS records. That retained run is corroboration, not claimed as this reviewer's full-suite execution. No broad framework rerun was performed. Child status is implementing with evidenced done AC rows; root must reconcile lifecycle and stale “Validation outstanding” prose at closure. No parent completion claim is introduced by the delta.

## Quality and executed probes

The helper checks string types before folding only A-Z; it cannot broaden comparison through Unicode case folding. Resolved remote spelling is preserved for gh repo view. Provider host/protocol/userinfo/query/fragment checks remain in the same conjunction. Exact endpoint comparison occurs before provider probes and before identity folding. Strict provider fixtures retain full argv matching and environment checks. No new runtime sidecar or unsupported universal-negative test claim was introduced.

Fresh executions, each exit 0, from /private/tmp/aai-pr434-case-review-scratch:

- AAI_PREFLIGHT_SCRATCH=/private/tmp/aai-pr434-case-review-scratch/fixtures bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_001 — test001.log.
- Same command with test_007 on the unmodified copied suite — test007.log.
- Same command with test_007 after replacing only its body in the scratch suite with retained probe-additions.js — probes.log: 3 positive routes and 10 negative controls, all asserted. Positives check exactly three allowlisted calls; input negatives check zero, returned URL negatives check three. Non-ASCII lookalikes remain distinct.

The wrapper labels isolation “degraded” because this deliberately reused copy has no .git. Its phrase “shipping repository” refers to its current working directory, the named scratch copy; the real shipping tree was not its cwd. The original boundary is rechecked at seal. Tests exited without retained sessions. No probe uses live provider service access.

## Cannot verify and warning disposition

The structured cannot_verify list is binding. Parent and first-child mutation records on prior target hashes need final integration proof. Root still owes unsigned semantic amendment handling (fu-amend-spec-pr-capability-preflight remains open), final assembly Review, authorized metadata/generated reconciliation, source-bound native/full CI, fresh parent Validation and external sweep under DECISION-pr434-identity-split.md. No child PASS discharges these. Live Azure follow-up remains open.

No new NON-BLOCKING finding requires a disposition. Existing N1 is not claimed fixed: decisions.jsonl:1625 contains filed fu-review-log-attribution, P3, with original report source; maintain that existing disposition. No follow-up was filed by this reviewer.

## Handoff

Root owns the returned set-code-review command and staging this report plus its manifest-listed companions. Index is intentionally untouched by this dispatched reviewer. This child review authorizes no merge or parent closure. Boundary and manifest are under docs/ai/reviews/pr434-case-20261008T114239Z/; result.md contains the typed handoff.
