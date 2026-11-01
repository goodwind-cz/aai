# Code Review: precise-suite-evidence-reuse (round 6)

```yaml
review:
  scope: main...HEAD (feat/precise-suite-evidence-reuse, head 6fd8a8c1, main be55884f merged at 5ccaf71c); delta since round 5 17f42f7d..6fd8a8c1 (49ca5e73, ecd7275f, bfcda4ca, merge 5ccaf71c, 6fd8a8c1)
  spec: docs/specs/SPEC-DRAFT-spec-precise-suite-evidence-reuse.md (frozen, amended; contract amendments 13:34:48Z and 19:39:13Z plus restamp 19:43:08Z, all owner_signoff false, tracked by fu-amend-precise-suite-evidence-reuse)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "framework unchanged since r5; TEST-3165 PASS in validation r11 full sweep at ecd7275f" }
      - { ac: Spec-AC-02, call: compliant, citation: "suite-reuse.mjs:143-148 afterLiteral shared by token (:187), lib/ (:203) and relative() (:216); lib/ loop now runs for every tests/ file (:195); reviewer probe at 6fd8a8c1: all r5 B1/B2/N1 rows unresolvable; TEST-3167 rows; node --test 30/30. r11 N1-N3 latent shapes filed as follow-ups" }
      - { ac: Spec-AC-03, call: compliant, citation: "computeIdentity unchanged; TEST-3168..3172 PASS (r11 sweep)" }
      - { ac: Spec-AC-04, call: compliant, citation: "loadManifest/checkSuites unchanged; TEST-3173/3174 PASS (r11)" }
      - { ac: Spec-AC-05, call: compliant, citation: "unchanged; TEST-3175/3176 PASS (r11)" }
      - { ac: Spec-AC-06, call: compliant, citation: "unchanged; TEST-3177..3179 PASS (r11)" }
      - { ac: Spec-AC-07, call: compliant, citation: "unchanged; TEST-3180/3181 PASS (r11)" }
      - { ac: Spec-AC-08, call: compliant, citation: "reviewer at 6fd8a8c1: suite-reuse lint rc 0; lint --minimal-tree 5/5 MINIMAL-TREE-PASS rc 0; manifest lists 5 suites" }
      - { ac: Spec-AC-09, call: compliant, citation: "select-suites.mjs unchanged since r5; TEST-3183/3190 PASS (r11)" }
      - { ac: Spec-AC-10, call: compliant, citation: "no ps1 path in delta; TEST-3184/3185 PASS (r11); native Windows is post-PR" }
      - { ac: Spec-AC-11, call: compliant, citation: "prompts unchanged in delta; TEST-3186/3187 PASS (r11)" }
      - { ac: Spec-AC-12, call: compliant, citation: "imports unchanged; TEST-3188 PASS (r11)" }
      - { ac: Spec-AC-13, call: compliant, citation: "docs/analysis/precise-suite-evidence-reuse.md:94 says only 3 of the 5 manifest suites can reuse at head; TEST-3189 PASS (r11)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: docs/ai/decisions.jsonl, line: 2650,
          issue: "6fd8a8c1 appends follow_up_status done for fu-amend-spec-doctor-determinize ('signed by the #522 merge'). The amendment that item tracks, ts 2026-11-01T12:38:15Z ref doctor-determinize (decisions.jsonl:2612), is NOT signed: the merge-time signature fold (spec-amend.mjs:657-668) keys on the record's own ref_id, and the doctor-determinize ride merged long before 12:38:15Z. Only the re-filed record under node-first-small-pairs (:2615, 17:06:53Z) is signed by the #522 merge. Closing the tracker leaves the 12:38 record unsigned-untracked, so the ledger now carries a false 'done' and spec-amend --strict fails.",
          failure_scenario: "At 6fd8a8c1: node .aai/scripts/spec-amend.mjs list --strict gives rc 1, unsigned-untracked=1, STRICT-VIOLATION ts=2026-11-01T12:38:15Z ref=doctor-determinize. At the merge commit 5ccaf71c the same command gives unsigned-untracked=0. env -u AAI_ROLE AAI_SUITE_REUSE=0 bash tests/skills/test-framework.sh --skill aai-spec-amend: FAIL, TEST-009 ('list --strict over the live ledger must exit 0 ... got 1'). main (be55884f) still has the item open, so this branch turns a green suite red on merge and in CI." }
      - { rank: NON-BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 203,
          issue: "Behaviour regression from ecd7275f: the trusted lib/ site now calls addPath, which strips trailing dots (:170-171), so `cat lib/x.` hashes tests/skills/lib/x instead of lib/x. (r11 N3.)",
          failure_scenario: "Reviewer probe: a suite reading tests/skills/lib/x. reuses after that file is edited (FALSE REUSE; at 17f42f7d it was detected). No tracked file ends in '.', no live suite has the shape, and the token and SCRIPT_DIR sites have always behaved this way. Already filed: fu-reuse-trailing-dot-literal." }
  cannot_verify:
    - { claim: "Full sweep of the merged head (main's suite-map rows, the hygiene-pack pin 122, the new aai-validate-skills/aai-live suites) is green apart from the BLOCKING item", closes_with: "validator close-time full sweep on the remediated head (AAI_TEST_TIMEOUT=3600); reviewer ran only aai-spec-amend, node --test and lint --minimal-tree" }
    - { claim: "SKILL_VERIFY reuse exception links docs/product/precise-suite-evidence-reuse.md", closes_with: "the product doc written after LOOP COMPLETE (carried since round 1)" }
    - { claim: "Windows behaviour of the Pester twin", closes_with: "native Windows pwsh run (post-PR, carried)" }
    - { claim: "Read channels the R1 residual names (bash cat/cp/source, optional reads, $HOME paths) for the 3 reusable suites", closes_with: "the manifest note plus minimal-tree gate are the only evidence; reviewer literal review of test-aai-feedback-status.sh, test-aai-pricing.sh, test-aai-redact.sh found no read outside their closures" }
  overall: fail
```

security_relevant: false

## Scope and method

Branch feat/precise-suite-evidence-reuse at 6fd8a8c1, read-only. Diff main...HEAD; focus on the delta since round 5 (17f42f7d). Probes: the round-5 probe set re-run against the shipped helper at head (`/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/r6/probe.mjs`, `probe2.mjs`, `closure.mjs`), identity compared before and after editing each target. Commands run: `node --test tests/skills/lib/suite-reuse.test.mjs` (30/30), `suite-reuse.mjs lint` (rc 0), `lint --minimal-tree` (5/5 PASS, rc 0), `explain` for the 5 manifest suites, `spec-lint --path <spec>` (LINT PASS), `generate-docs-index.mjs --check` (rc 0, index fresh), `spec-amend list --strict` at head and at 5ccaf71c, and `--skill aai-spec-amend` (FAIL). My test run appended one line to tracked `docs/ai/tests/test-runs.jsonl`; I restored that file, so the tree is clean apart from this report.

Dispatch note: the dispatch set the owner's final-round rule and named the commits and filed follow-ups. That is scope and policy, not coaching. I reviewed the full delta, including the ledger commit.

## Round-5 findings: resolution

| id | status | evidence |
|---|---|---|
| B1 quote-closed literal accepted at lib/, SCRIPT_DIR, dirname sites | resolved | `afterLiteral` (:143-148) is used at all three sites (:187, :203, :216). Probe rows `"$SCRIPT_DIR/lib/fix"$n.json`, `"$SCRIPT_DIR/fixtures/fix"$n.json`/`_a.json`, `"lib/fix"$n.json`/`_a.json`/`-a.json`, `'lib/fix'_a.json`, `"$(dirname "$0")/lib/fix"_a.json`: all unresolvable |
| B2 lib/ check limited to tests/skills/ | resolved | gate removed (:195 block now runs for every `tests/` file). Probe rows `tests/other/h.sh` (`cat lib/x`) and `tests/other/a.mjs` (`readFileSync('lib/x')`): unresolvable |
| N1 `"$ROOT/docs/pro".md` | resolved | `.` or `-` after a quote gives `bad`; probe and TEST-3167 rows |
| N5 args (accepted residual) | carried | unchanged |

## Merge 5ccaf71c

- `docs/ai/decisions.jsonl`, `docs/ai/EVENTS.jsonl`: main's blob (be55884f) is a byte prefix of the merged file. The lines after it are exactly the branch-only lines (bfcda4ca minus the 89a63814 base), in order. Line counts: decisions 2618 + 2636 - 2609 = 2645, EVENTS 3554 + 3553 - 3544 = 3563. No line from either side is missing and there are no duplicates. The 15 non-JSON lines in decisions.jsonl are on both parents already. `docs/ai/METRICS.jsonl` takes main's side, and the branch did not touch it. HEAD is append-only over the merge.
- Every other file: for each file, the branch's own changes and main's own changes come through the merge unchanged. The two exceptions are `tests/skills/test-aai-hygiene-pack.sh` (the pin) and `docs/INDEX.md`, which was regenerated (`--check` rc 0).
- Pin: `suite-map.yaml` has 122 top-level rows (121 on main plus aai-suite-reuse). test_090 and test_129 both pin 122, and their messages are updated. Correct.

## Live suites

`explain`/`computeClosure` at head: aai-feedback-status, aai-pricing and aai-redact have 0 unresolved entries. aai-orchestration-mode and aai-runtime-file are inputs-unresolvable because of a `${VAR:-path}` literal. That matches the analysis note (:94, "only 3 of the 5 manifest suites can reuse"). I read the reads in the three reusable suites literally. Their data reads are `$PROJECT_ROOT/.aai/system/PRICING.yaml`, `docs/ai/METRICS.jsonl`, `.aai/scripts/aai-feedback-status.mjs` and `.aai/scripts/lib/aai-redact.mjs`, and all are in their closures. None uses a N1-N3 shape. I found no false REUSE reachable by a live suite.

## Spec-AC walk

See `ac_walk`. Deviations from the amended spec: none in code. The amendments are unsigned and tracked by fu-amend-precise-suite-evidence-reuse (the documented additive-with-disclosure path).

## BLOCKING

- **B1 `docs/ai/decisions.jsonl:2650`** (6fd8a8c1): fu-amend-spec-doctor-determinize was closed as signed, but its record (:2612, ref doctor-determinize, 12:38:15Z) is not signed. The merge fold only signs records whose own ref merged after them. Result: `spec-amend list --strict` rc 1 and aai-spec-amend TEST-009 FAIL at head, green at 5ccaf71c and on main. Remedy (append-only, no in-place edit): `node .aai/scripts/follow-ups.mjs reopen --id fu-amend-spec-doctor-determinize --reason "12:38:15Z doctor-determinize record is not merge-signed; only the 17:06:53Z node-first-small-pairs re-file is"` (or get an owner signature for that record). Then confirm `spec-amend list --strict` rc 0 and `--skill aai-spec-amend` PASS. The branch-merge correctness of the ledger itself is fine. This is a new append, not a merge error.

## NON-BLOCKING and dispositions (H6)

- NB-1 `.aai/scripts/suite-reuse.mjs:203`: the trailing dot of a lib/ literal is stripped (r11 N3). Strictly this is a behaviour regression, but only on a filename shape that no tracked file has and no live suite reads. Non-blocking under the owner's final-round rule. Disposition (b): already promoted as fu-reuse-trailing-dot-literal.
- r11 N1 (dirname base, `suite-reuse.mjs:202`), N2 (`${ROOT}lib/x`), N4 (unrecorded mutations): latent, filed (fu-reuse-lib-dirname-base, fu-reuse-lib-after-expansion, fu-reuse-mutation-rows-3167). The ledger lines exist at decisions.jsonl:2646-2649. Disposition (b).
- accepted residual (carried from round 1): N5 - the args component is the helper's constant default, not passed by the framework; today's vector is constant and equals the default, no bite observed and no false record (P3).

INFO (does not gate): a SCRIPT_DIR reassigned in a sourced helper (probe: FALSE REUSE) remains an R1 derived form, as in round 5. The tokenizer change makes any token followed by `,`, `:`, `]`, `}` or a backtick unresolvable. That only fails closed, and it is why two manifest suites no longer reuse. The note discloses this.

## Next steps

1. Remediation: append the reopen (or get the owner's signature) for fu-amend-spec-doctor-determinize. Re-run `spec-amend list --strict` and `--skill aai-spec-amend`. No code change.
2. Validator: the close-time full sweep on the remediated merged head.
3. Orchestrator: quote the N5 accepted residual in `code_review.notes`. NB-1 and r11 N1/N2/N4 are already filed.
