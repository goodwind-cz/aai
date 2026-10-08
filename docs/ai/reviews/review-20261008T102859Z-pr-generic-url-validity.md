```yaml
review:
  scope: "1691558c034e13258a31b8288df5642f6263a8cb plus working changes and 123 artifacts in pr434-generic-20261008T102859Z/scope-snapshot.json"
  spec: docs/specs/SPEC-0211-spec-pr-generic-url-validity.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:153 and :206; TEST-001 fresh reviewer test001.log" }
      - { ac: Spec-AC-02, call: compliant, citation: "tests/skills/test-aai-pr-preflight.sh:210-217; TEST-007 fresh reviewer test007.log; retained full8.log" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/ai/overview-data.json, line: 3446, issue: "A parent compatibility-suite log is attributed as the code review of layer-profiles", failure_scenario: "A reader follows the new code-review link for delivered CHANGE-0023 and receives a test log from the PR434 run, containing no dual review verdict for that scope" }
  cannot_verify:
    - { claim: "Native Windows and full assembled-source CI success", closes_with: "Final source-bound native and ci-full runs after both child integrations" }
    - { claim: "Parent PR434 is ready to merge", closes_with: "Sibling case-identity repair, final assembly Review, authorized lifecycle/generated reconciliation, independent Validation and external review sweep" }
    - { claim: "Live provider compatibility or future PR create permission", closes_with: "Authorized provider round-trip evidence; local strict fixtures establish only their named seams" }
    - { claim: "Actual serving-model distinction from the maker", closes_with: "Harness serving-model metadata; requested model names alone do not establish this" }
  overall: pass
```

# Child review: pr-generic-url-validity

Both child verdicts PASS. No blocking source/test defect was found. One non-blocking delivery-evidence finding requires root disposition before closeout; this is a conditional child PASS, not parent merge readiness.

## Scope and independence

Started at system UTC 2026-10-08T10:28:59Z. This is a fresh dispatched Code Review context; requested route gpt-6-astra, actual serving identity unknown. Machine dispatch selects rule 13 for this child. No implementation or STATE changes were made by this reviewer.

STATE selects worktree, inline_review_scope null, base and actual HEAD 1691558c034e13258a31b8288df5642f6263a8cb, branch fix/pr-generic-url-validity. Because HEAD is still the base, the reviewed scope is the actual staged plus unstaged changes and explicit manifest-listed companions, not an empty three-dot diff. The complete actual HEAD diff is 892907 bytes, SHA256 8493d195f6d69052873c7b7d894134c7fc0abeb4e6cca6cdc8759bd5394c9302. Separate staged/unstaged diff hashes are retained in diff-inventory.json. All 123 current inventory paths matched their supplied hashes. Governing child/sibling documents, owner split decision, parent assembly marker, ledger appends, generated changes, prior review dependency and maker/Validation/root receipts were included. Historical log inventories were checked mechanically with relevant raw outcomes read; this is not a claim that every historical CI log line was manually read or rerun.

The dispatch supplied an inventory and historical evidence status, not an inline diff. No expected verdict or severity coaching was adopted. The child scope does not erase the parent's known B2 finding; ISSUE-0095/SPEC-0212 accurately retain it as pending work. The original parent SPEC-0210 remains unchanged.

## Acceptance criteria and executable evidence

| AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | validateExplicitUrl at source lines 153–156 constructs URL from raw effective bytes. Its call at 206 follows exact fetch/push equality and precedes classification/generic success. TEST-001 lines 144–152 configures equal malformed github.com:bad and gitlab.com:bad endpoints, verifies effective Git bytes, then asserts exit 2, IDENTITY_INVALID and zero calls. A lawful GitHub control reaches three calls. Fresh reviewer run exits 0. |
| Spec-AC-02 | compliant | TEST-007 lines 210–217 preserves valid generic URL, numeric port 8443, credential/query/fragment redaction and explicit local-null success, with zero providers. Malformed generic port refuses. Existing destination-divergence checks remain before parsing; TEST-001 asserts their operation and zero calls. Fresh reviewer TEST-007 exits 0. |

Both TEST-001/007 exist and are registered in the runner; the native extraction delimiter is preserved. Each strict client checks complete allowlisted argv and environment. The new refusals have reached positive controls, not merely empty-log assertions. No new runtime sidecar, dependency, prompt growth or universal-negative test name was introduced. The diagnostic change to the fixture's JSON parse failure reports actual status/stderr rather than altering the oracle.

Fresh reviewer commands were run serially in `/private/tmp/aai-pr434-generic-review-scratch/copy`, with AAI_PREFLIGHT_SCRATCH pointing beneath the same absolute scratch root:

- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_001`: exit 0, explicit_malformed_scheme_refusal and lawful_github_calls=3.
- Same command with `test_007`: exit 0, valid generic/local controls, malformed refusal and SSH443 positive.
- `node .aai/scripts/spec-amend.mjs --strict`: exit 0, zero unsigned-untracked amendments.
- `node .aai/scripts/validation-outcome-check.mjs --report docs/ai/reports/VALIDATION-20261008T101336Z-pr-generic-url-validity.md --ref pr-generic-url-validity --since 2026-10-08T10:13:36Z --intake docs/issues/ISSUE-0094-pr-generic-url-validity.md --spec docs/specs/SPEC-0211-spec-pr-generic-url-validity.md`: exit 0.

The wrapper prints degraded isolation because this private copied root is not a Git checkout. Its wording calls its working directory the shipping repository, but the command's actual working directory was the private copy; fixture Git writes remained under the private scratch root. Source/test copied bytes match the reviewed shipping hashes. No source mutation experiment was needed.

Retained independent Validation evidence supplies the full eight-row PASS and replay 2/2 behavioral RED, zero inconclusive and zero restamps. Both stored product REDs show actual 0 versus expected 2; the identical one-line mutation patches remove the new call, leaving parseable code and lawful controls. These retained runs are historical, not claimed as fresh reviewer executions. The first Validation FAIL and interrupted aggregate exit 130 remain intact. Subsequent metadata remediation and fresh checked Validation explain the resolved amendment/audit failures without converting the earlier aggregate to green.

## Delivery evidence and deviations

The new parent umbrella marker describes the explicitly authorized two-child assembly while keeping implementing status and the historical parent FAIL. It does not claim delivery. EVENTS and decisions preserve the base as a byte-exact prefix. The appended human decision records split authorization; unsigned amendment follow-ups remain openly tracked rather than falsely signed.

Historical manifest checks: prior review 34/34, first Validation root 9/9 and current revalidation root 14/14 match. Planning's four DRAFT paths were later numbered; maker's spec hash predates the disclosed evidence-summary amendment; older metadata STATE/EVENTS hashes predate recorded runtime transitions and append-only audit telemetry. These differences are recorded in historical-manifest-check.json, not silently restamped. The current 123-file inventory matches throughout this review.

Bookkeeping deviations from the frozen prose are visible: the planned combined `pr-generic-url-validity-red.log`/`-green.log` names became per-TEST files under `docs/ai/tdd/spec-pr-generic-url-validity/`; the current AC table and intake cite the real artifacts. The behavioral evidence obligation is satisfied. Parent semantic amendment reconciliation is still an integration duty; no child PASS discharges `fu-amend-spec-pr-capability-preflight`. Numbering restamps retain their unsigned tracked amendment debt. No behavioral AC deviation was found.

The generated INDEX/overview were produced at 09:13 before implementation. INDEX line 17 still says two planned ACs and line 577 places ISSUE-0094 under Drafts; overview-data line 213 still says draft. The dated generation times explain their age, but root must refresh these current-state views during the already-required generated reconciliation. This is an explicit closeout task, not a claim that the snapshots match current lifecycle.

## N1 — NON-BLOCKING: unrelated suite output is labeled code review

`docs/ai/overview-data.json:3446` newly assigns `docs/ai/reviews/review-20261007T232901Z-layer-profiles.log` as the delivered layer-profiles scope's review (also repeated at line 7121 and rendered in overview.html). Reading that artifact shows an AAI layer-profiles compatibility test log from the parent PR review, not a Code Review report of CHANGE-0023. A user following the rendered code-review link receives no spec_compliance/code_quality verdict for the claimed scope.

Recommended H6 disposition: **remediate-in-tree before closeout**, ensuring generated review associations select actual scope review reports and the generated entry no longer labels this raw log as that review. Keep the historical log intact. Merely regenerating with the same permissive association may reproduce it; verify the resulting entry. Alternatively root may file a tracked follow-up with this evidence, but none was filed by this reviewer. Suggested only: `fu-overview-review-log-misattribution`. This is an observed false association, so accepted-residual disposition is not appropriate. Root must record the actual disposition in the ledger/ref and code_review.notes as required; the conditional PASS alone does not complete that duty.

## Cannot verify and handoff

The supplied PR snapshot is open PR434, head1691558c, label ci-full. It is a retained observation, not a live re-query or a current-source CI success. The old source-bound CI evidence retains its failures/pending status. No local Bash result establishes Windows, assembled-source full CI, live provider access or model-weight independence. Parent review/validation and external replies/resolutions remain owed; this reviewer made no external writes.

The before/after boundary matches all 125 pinned files (123 inventory plus STATE and parent spec), HEAD and index listing. Only this report and its new companions were written in the shipping tree. Root alone should stage them with the child delivery, settle N1, apply the returned child set-code-review command, and continue the authorized workflow. Do not apply this child verdict to parent PR434 or bypass its remaining gates. The typed result checker establishes return shape only, not semantic correctness. Artifact hashes and actual timing are sealed in the companion manifest.
