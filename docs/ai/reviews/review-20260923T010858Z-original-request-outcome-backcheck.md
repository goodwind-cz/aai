# Independent code review — original-request-outcome-backcheck

```yaml
review:
  scope: "origin/main versus working tree, including untracked files; exact 58-path list below"
  spec: docs/specs/SPEC-0183-spec-original-request-outcome-backcheck.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/validation-outcome-check.mjs:220; TEST-001 green log" }
      - { ac: Spec-AC-02, call: compliant, citation: "semantic/candidate/scenario-01.md through scenario-06.md; validation-current-semantic-score.log 6/6" }
      - { ac: Spec-AC-03, call: non-compliant, citation: ".aai/scripts/validation-outcome-check.mjs:286,312; N1 canonical-equivalent path probe" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/validation-outcome-check.mjs:313,317; TEST-004 and TEST-008 green" }
      - { ac: Spec-AC-05, call: non-compliant, citation: ".aai/scripts/validation-outcome-check.mjs:121; B1 actual handoff acceptance of example-only and unfinished duplicate" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/check-role-output.mjs:605; VALIDATION steps 7c/9; standalone invocation-order.jsonl" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/SKILL_LOOP.prompt.md:129; TEST-008/009 and resume-v2/parent-verification.json" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-010 and tests/skills/test-aai-role-output.sh:675; positive control exit 0" }
      - { ac: Spec-AC-09, call: compliant, citation: ".aai/system/PROFILES.yaml:104; TEST-011-suite-selection-per-path.log; prompt-diet ledger" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/validation-outcome-check.mjs, line: 121, issue: "B1: fence regex accepts example content and ignores unfinished duplicate blocks", failure_scenario: "A valid-looking block only inside a four-backtick Markdown example is accepted by the real Validation PASS handoff; a valid block plus unfinished second outcome block is also accepted." }
      - { rank: NON-BLOCKING, file: .aai/scripts/validation-outcome-check.mjs, line: 286, issue: "N1: local identities compare raw strings instead of canonical paths", failure_scenario: "Expected output/final.txt and observed/consumed ./output/final.txt name the same saved file and bytes but are refused." }
      - { rank: NON-BLOCKING, file: .aai/scripts/validation-outcome-check.mjs, line: 164, issue: "N2: invalid CLI horizon is classified as evidence refusal", failure_scenario: "--since not-a-date returns 1 instead of documented invalid-usage exit 2, so a caller cannot distinguish invocation errors from bad evidence." }
  cannot_verify:
    - { claim: "Windows and Linux execution for this change", closes_with: "Platform CI or actual platform runs at the reviewed tree; available full-suite evidence is Darwin." }
    - { claim: "Actual granted model identity and this review's token usage", closes_with: "Independent native harness identity/usage telemetry; requested model is not runtime evidence." }
    - { claim: "General semantic completeness, external observation authenticity, or all future prompt executions", closes_with: "Task-specific independent observations; six scenarios and prompt rehearsals establish only their finite cases." }
    - { claim: "Pinned upstream research claims independently reproduced", closes_with: "A separate upstream source/reproduction review; this review inspected the research document as rationale, not its external benchmark claims." }
  overall: fail
```

## Scope and independence

Reviewed the caller's explicit 58 paths against `origin/main`, reading working-tree diffs and untracked files rather than the empty base-to-HEAD commit range. Both HEAD and origin/main resolved to `f84f84ab93348a321b6af803ba53ce0a526f53fc`. Worktree metadata selects `worktree`; no ambiguous inline scope exists. Dispatch supplied no implementation conversation or expected verdict. No coaching attempt was observed.

Requested model: `gpt-6-astra`, high reasoning. Actual granted model and usage: unavailable from independent runtime evidence. Context independence is established by this dispatched review; model identity is not claimed. Used the canonical aai-code-review prompt and subagent contract. All shell invocations set AAI_ROLE=subagent. No source, test, spec, intake or STATE was modified, and no commit or push was made. Experiments used only `/tmp/aai-outcome-independent-review`; only this report was written in the delivery tree.

## Findings and failure scenarios

**B1 — BLOCKING, malformed report authority reaches PASS.** At `.aai/scripts/validation-outcome-check.mjs:121`, the global regex knows neither enclosing Markdown fences nor unmatched outcome openings. Starting with the shipped valid outcome report and valid Validation result envelope, the independent probe made two variants: (a) wrap the whole report in a four-backtick `markdown` example, leaving no authoritative outcome fence; (b) append a second `aai-outcome-v1` opening and JSON without a closing fence. Both returned exit **0** from the actual `check-role-output.mjs --file ... --now 2026-06-01T00:00:00Z`, just like the unmodified positive control. A pasted example or interrupted report rewrite can therefore be mistaken for accepted evidence. This directly violates D1's prohibition on extracting JSON from arbitrary code examples and D1/D2/Spec-AC-05's one-block/malformed-block rules. TEST-005 only covers two complete blocks and misses these shapes. Remediate in tree: recognize fence context and refuse malformed/ambiguous authoritative openings; add positive and negative controls at the actual handoff, including nested examples and an unfinished second block.

**N1 — NON-BLOCKING quality, but frozen-spec deviation.** At `.aai/scripts/validation-outcome-check.mjs:286` and `:312`, local expected/observed/consumed identity uses literal string equality. The independent saved-file control with all paths `output/final.txt` exits 0. Changing only observed and consumed paths to `./output/final.txt` exits 1 with both identity-mismatch and consumed-path-mismatch reasons, although the exact same saved file is re-read and its hash matches. D1 explicitly requires comparing canonical paths. This causes false refusal/revalidation of correct artifacts. Recommended disposition: **remediate-in-tree** using canonical local identities while preserving the root/path safety rules and strict external/repository identity rules; retain a real wrong-target refusal control. The orchestrator owns the disposition record; no follow-up has been filed by this reviewer.

**N2 — NON-BLOCKING quality, but D2 exit-contract deviation.** `.aai/scripts/validation-outcome-check.mjs:164` routes an invalid caller horizon through evidence failure; `main` returns 1. The independent invocation with `--since not-a-date` returned 1 and `OUTCOME-CHECK: --since is not a valid ISO-8601 UTC timestamp`. D2 and product docs reserve 2 for invalid CLI usage. A workflow branching on the documented exit status can incorrectly request new evidence when the invocation itself needs correction. Recommended disposition: **remediate-in-tree** by validating CLI timestamp values as CLI usage before calling the checker; keep malformed timestamps inside reports as evidence refusals. No follow-up has been filed.

## Acceptance-criteria walk

The structured AC walk above is complete. Spec-AC-01's declared omitted/weakened/unknown assessments and violated outcomes are refused; semantic truth deliberately remains independent-validator work. Spec-AC-02's six raw candidate reports inventory material original constraints with citations: omitted comment preservation, weakened retry count, code-only success, preview-only failure, wrong saved path, and exact saved-file success. All six baseline outcomes also matched, so no semantic-improvement claim is supported or needed. Candidate run prompts exclude the oracle and builder conversation; provenance records fresh CLI contexts and unchanged inputs without inventing actual model identity.

Spec-AC-03's ordinary saved-file, preview, wrong-path and changed-byte arms exist and have GREEN evidence, but N1 violates its canonical exact-target contract. Spec-AC-04's byte recheck and dynamic horizon are implemented; external immutability truth remains the stated semantic boundary. Spec-AC-05 fails because B1 admits malformed/non-authoritative blocks, despite the existing missing/hash/link/date controls. Spec-AC-06 is mechanically wired through the shared imported checker; the wire exists and is exercised, while B1 concerns that checker's correctness. The standalone and visual rehearsal logs show check-before-state and recheck after presentation. Spec-AC-07 resets standing PASS to not_run before routing Validation, preserving normal dispatch/current-tree checks. Spec-AC-08 retains other-role/non-PASS behavior and concise repository targets. Spec-AC-09 adds the checker to core and suite mapping with only Node stdlib imports and measured prompt accounting.

## Test and evidence assessment

- TEST-001/003/004/005/007/008/010 exist in `tests/skills/test-aai-outcome-backcheck.sh`; their archived green log was read. TEST-006 is the actual handoff case in `test-aai-role-output.sh` TEST-023; its qualifying baseline RED records the old CLI returning 0 when refusal was expected, rather than a missing-module failure.
- TEST-002's six raw candidate reports and six raw baseline reports were inspected alongside source fixtures, oracle, run prompts and available provenance. `validation-current-semantic-score.log` records all six cases and score 6/6. The positive source/code fixture and saved-file bytes are real inputs, not pre-filled semantic verdicts.
- TEST-009's regression log records `aai-validator-isolation`, `aai-role-output` and `aai-orchestration-dispatch` all passing. The independent resume-v2 rehearsal records checker refusal, invalidation, first dispatch Validation, then a real failed readback without any new PASS write. The TEST-008 mutation record records the expected failure after changing invalidation to pass.
- TEST-011's suite-selection evidence names the outcome suite for all nine changed production paths. Profile, prompt-diet and suite-selection results are present in the existing framework evidence. Prompt growth accounting and checkpoint changes match the added contract. No runtime dependency/package manifest was introduced.
- The current full-framework log records 95/96, with close-work-item remediated by its later targeted passing run. The later selected/core validation initially found the release invariant; current `test-20260923-005455/summary.txt` records 5/5 after its remediation. These are preserved separate runs, not misrepresented as one wholly green full sweep. No unchanged broad suite was repeated during review.
- All four scoped JSONL ledgers retain origin/main as a byte-exact prefix. Their additions describe this scope's admission, lifecycle, validation and test runs. The compatibility fixture changes preserve the deliberate subagent-refusal arm while ordinary close fixtures model the orchestrator.
- The preimplementation normal-report corpus artifact `docs/ai/archive/longhorizon-ship/preimplementation-report-corpus.json` honestly records zero. Independent current top-level normal-report enumeration found three v1 reports: latest and intermediate mechanically admissible; earliest refused because the spec hash changed. No legacy or malformed top-level normal report appeared. Archived scenario/rehearsal inputs have their own roots and are assessed separately, not silently treated as current root reports.

Independent commands (all through the canonical wrapper from the scratch root):

1. `bash .aai/scripts/aai-run-tests.sh node probe.mjs` — wrapper exit 0; positive control exit 0, example-only exit 0, unfinished-second exit 0, invalid-horizon exit 1. Harness records observed behavior; its zero exit is not a product PASS claim.
2. `bash .aai/scripts/aai-run-tests.sh node path-probe.mjs` — wrapper exit 0; exact-path control exit 0, canonical-equivalent path exit 1.
3. `bash .aai/scripts/aai-run-tests.sh node corpus-probe.mjs` — exit 0, three current normal reports classified as above.

Exact probe scripts, report variants and outputs are retained in `/tmp/aai-outcome-independent-review/` (`probe.mjs`, `probe.log`, `path-probe.mjs`, `path-probe.log`, `corpus-probe.mjs`, `corpus-probe.log`). Their decisive observations are copied into this tracked report so findings do not depend on scratch retention.

## cannot_verify

The structured list above is intentional. In particular, checker admissibility is not semantic truth, the six-case rehearsal is not a benchmark, and Windows/Linux success is not inferred from macOS. The existing source limits standalone/loop enforcement to prompt execution and leaves raw state CLI bypasses explicit; those are authorized scope limits rather than hidden defects.

## Next step

Remediate B1 and the N1/N2 contract deviations with focused failing-first controls, revalidate the changed scope, then obtain the second independent review. Overall and both independent verdicts are FAIL; do not claim PR readiness from the earlier Validation PASS. Recommended warning dispositions are N1=remediate-in-tree and N2=remediate-in-tree, to be recorded by the sole STATE owner.

## Exact reviewed path list

```
.aai/SKILL_LOOP.prompt.md
.aai/SKILL_VALIDATE_REPORT.prompt.md
.aai/SUBAGENT_CONTRACT.md
.aai/SUBAGENT_PROTOCOL.md
.aai/VALIDATION.prompt.md
.aai/scripts/check-role-output.mjs
.aai/scripts/validation-outcome-check.mjs
.aai/system/PROFILES.yaml
.aai/templates/BRIEF_TEMPLATE.md
CHANGELOG.md
docs/USER_GUIDE.md
docs/ai/EVENTS.jsonl
docs/ai/METRICS.jsonl
docs/ai/decisions.jsonl
docs/ai/tests/test-runs.jsonl
docs/issues/CHANGE-0189-original-request-outcome-backcheck.md
docs/product/original-request-outcome-backcheck.md
docs/specs/RES-0004-longhorizon-harness-adoption.md
docs/specs/SPEC-0183-spec-original-request-outcome-backcheck.md
tests/fixtures/outcome-backcheck/README.md
tests/fixtures/outcome-backcheck/oracle.json
tests/fixtures/outcome-backcheck/scenarios/scenario-01/evidence/test.log
tests/fixtures/outcome-backcheck/scenarios/scenario-01/request.md
tests/fixtures/outcome-backcheck/scenarios/scenario-01/spec.md
tests/fixtures/outcome-backcheck/scenarios/scenario-01/worktree/src/format.js
tests/fixtures/outcome-backcheck/scenarios/scenario-02/evidence/test.log
tests/fixtures/outcome-backcheck/scenarios/scenario-02/request.md
tests/fixtures/outcome-backcheck/scenarios/scenario-02/spec.md
tests/fixtures/outcome-backcheck/scenarios/scenario-02/worktree/config/upload.json
tests/fixtures/outcome-backcheck/scenarios/scenario-03/evidence/test.log
tests/fixtures/outcome-backcheck/scenarios/scenario-03/request.md
tests/fixtures/outcome-backcheck/scenarios/scenario-03/spec.md
tests/fixtures/outcome-backcheck/scenarios/scenario-03/worktree/src/status.js
tests/fixtures/outcome-backcheck/scenarios/scenario-03/worktree/test/status.test.js
tests/fixtures/outcome-backcheck/scenarios/scenario-04/evidence/preview.log
tests/fixtures/outcome-backcheck/scenarios/scenario-04/request.md
tests/fixtures/outcome-backcheck/scenarios/scenario-04/spec.md
tests/fixtures/outcome-backcheck/scenarios/scenario-04/worktree/previews/quarterly.txt
tests/fixtures/outcome-backcheck/scenarios/scenario-05/evidence/readback.log
tests/fixtures/outcome-backcheck/scenarios/scenario-05/request.md
tests/fixtures/outcome-backcheck/scenarios/scenario-05/spec.md
tests/fixtures/outcome-backcheck/scenarios/scenario-05/worktree/output/draft.txt
tests/fixtures/outcome-backcheck/scenarios/scenario-06/evidence/readback.log
tests/fixtures/outcome-backcheck/scenarios/scenario-06/request.md
tests/fixtures/outcome-backcheck/scenarios/scenario-06/spec.md
tests/fixtures/outcome-backcheck/scenarios/scenario-06/worktree/output/final.txt
tests/fixtures/role-outputs/outcome-evidence.log
tests/fixtures/role-outputs/outcome-intake.md
tests/fixtures/role-outputs/outcome-report-valid.md
tests/fixtures/role-outputs/outcome-spec.md
tests/fixtures/role-outputs/validation-valid.md
tests/skills/lib/prompt-diet-ledger.sh
tests/skills/suite-map.yaml
tests/skills/test-aai-close-work-item.sh
tests/skills/test-aai-hygiene-pack.sh
tests/skills/test-aai-outcome-backcheck.sh
tests/skills/test-aai-prompt-diet.sh
tests/skills/test-aai-role-output.sh
```

## Timed role result

```yaml
subagent_result:
  scope: original-request-outcome-backcheck
  role: Code Review
  status: FAIL
  started_utc: 2026-09-23T01:03:02Z
  ended_utc: 2026-09-23T01:08:58Z
  duration_seconds: 356
  evidence:
    - command: "git diff origin/main plus direct reads of the exact 58 scoped paths, including untracked files"
      exit_code: 0
      output_snippet: "Scope established; 9 ACs walked; source and evidence reviewed independently."
    - command: "bash .aai/scripts/aai-run-tests.sh node probe.mjs (scratch root)"
      exit_code: 0
      output_snippet: "control=0; example-only=0; unclosed-second=0; invalid-horizon=1. Malformed report variants unexpectedly accepted."
    - command: "bash .aai/scripts/aai-run-tests.sh node path-probe.mjs (scratch root)"
      exit_code: 0
      output_snippet: "canonical-control=0; canonical-equivalent=1 despite same saved file and matching bytes."
    - command: "bash .aai/scripts/aai-run-tests.sh node corpus-probe.mjs (scratch root)"
      exit_code: 0
      output_snippet: "3 normal v1 reports: 2 admissible; earliest refused on changed spec hash."
  files_changed:
    - docs/ai/reviews/review-20260923T010858Z-original-request-outcome-backcheck.md
  blockers:
    - "B1: malformed/non-authoritative outcome fences reach accepted Validation PASS."
    - "Spec noncompliance: canonical local paths and CLI usage exit behavior also need correction."
  state_update_commands:
    - 'node .aai/scripts/state.mjs set-code-review --required true --status fail --scope "origin/main versus working tree including untracked files; exact 58 paths listed in docs/ai/reviews/review-20260923T010858Z-original-request-outcome-backcheck.md" --base-ref origin/main --report docs/ai/reviews/review-20260923T010858Z-original-request-outcome-backcheck.md --notes "Independent review FAIL: B1 malformed fence acceptance; Spec-AC-03/05 noncompliant; N1=remediate-in-tree canonical local paths; N2=remediate-in-tree CLI usage exit. Requested gpt-6-astra high; actual identity unavailable."'
```
