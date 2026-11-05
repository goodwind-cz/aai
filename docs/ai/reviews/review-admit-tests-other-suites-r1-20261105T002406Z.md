# Code review — admit-tests-other-suites (round 1)

security_relevant: false

```yaml
review:
  scope: origin/main...HEAD (f8297dbc...dc1fab50) on fix/admit-tests-other-suites
  spec: docs/specs/SPEC-0272-spec-admit-tests-other-suites.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-aai-suite-reuse.sh:1059 (n=0 pass line); TEST-3370 :1358; old body rc 1 / new rc 0 reproduced on a pricing-only branch" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/test-aai-suite-reuse.sh:1342; TEST-3371 :1367; same reproduction" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "ADMIT-FAIL rejection and probe/poisoned checks kept at :1049-1056 and :1326-1340; TEST-3372 :1376-1402" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "tests/skills/test-aai-suite-reuse.sh:669-678; TEST-3341 reddens on two scratch suite-reuse.mjs mutants" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-suite-reuse.sh, line: 1059,
          issue: "the not-admitted pass path (also :1342 for TEST-3337) does not require any verdict line in the admission output",
          failure_scenario: "standalone run (empty LIVE_ADMIT_OUT, mutation-run dispatch or the spec's own Test Plan command): suite-reuse.mjs crashes or lint refuses before admission; the `|| true` capture holds no ADMIT- line, n stays 0, and the test passes with 'not admitted on this branch'. Before this change the same run failed." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-reuse.sh, line: 1381,
          issue: "TEST-3372 bad_noprobe cases (and :1386) assert only rc != 0, not the failure reason",
          failure_scenario: "a future edit that makes test_3307/test_3337 fail on any input with an own ADMIT-PASS line (e.g. a typo in expect) keeps TEST-3372 green for the wrong reason; the good-case assertion catches most of these, so the gap is narrow" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-reuse.sh, line: 1325,
          issue: "TEST-3337's own-suite list is a literal, not a shared variable like FIVE_INDEX_SUITES",
          failure_scenario: "a split-suite rename updated in the manifest and in TEST-3336 but missed here makes TEST-3337 read the renamed suite as not admitted and pass; TEST-3336 pins the manifest names, so the miss needs a coordinated half-rename" }
  cannot_verify:
    - { claim: "CI full-suite proof for the lightweight lane",
        closes_with: "the PR carries the ci-full label (the diff trips no fail-open trigger) and the full run is green" }
    - { claim: "the remaining SELECTED/CORE suites for the docs files (doc-numbering, follow-ups, spec-amend, check-state, docs-content, spec-lint, prompt-diet) are green on this head",
        closes_with: "selected+CORE run in the next validation round or the pre-close sweep" }
  overall: fail
```

## Scope and spec
Diff `origin/main...HEAD`: `tests/skills/test-aai-suite-reuse.sh` (+84/-9), the intake and spec drafts, `docs/INDEX.md` (regenerated rows for the two drafts plus the date line) and two `docs/ai/EVENTS.jsonl` lines (docs_audit, doc_lifecycle draft->implementing). No product file is touched (matches the spec's out-of-scope line). Spec read: `docs/specs/SPEC-0272-spec-admit-tests-other-suites.md` (frozen).

## AC walk
- Spec-AC-01 compliant: TEST-3307 judges only `FIVE_INDEX_SUITES` and passes with the not-admitted line at :1059; TEST-3370 drives it with an aai-pricing-only admission.
- Spec-AC-02 compliant: same for TEST-3337 at :1342; TEST-3371.
- Spec-AC-03 compliant: the ADMIT-FAIL rejection and the probe / poisoned checks are unchanged; TEST-3372 drives ADMIT-FAIL, missing probe (3307) and poisoned=0 (3337) beside an other-suite line, and a good admission.
- Spec-AC-04 compliant: `../x` and `tests/../../x` both cases, rc==1 and `no-source-file <path>` asserted, with a real file at `$base/x` so only the escape rule can reject; the manifest edit is asserted to have applied.
- TEST ids in the Test Plan exist and pass (suite rc 0).

Deviation listed (not an AC breach): the Scope line "Standalone mode (empty `LIVE_ADMIT_OUT`) is unchanged" holds for the code path but not for its outcome. See finding 1.

## Findings and dispositions
1. BLOCKING `tests/skills/test-aai-suite-reuse.sh:1059` and `:1342`: the pass path accepts an admission output with no verdict line. Disposition: (a) remediate in this ride. Fix verified in a scratch copy: inside the `n -eq 0` branch add
   `[[ $'\n'"$LIVE_ADMIT_OUT" =~ $'\n'ADMIT-(PASS|FAIL)\  ]] || { printf '%s\n' "$LIVE_ADMIT_OUT" >&2; log_fail "TEST-3307: the admission printed no verdict line"; }`
   (TEST-3337 likewise), plus a TEST-3372 case with a no-verdict output that expects rc != 0. Result in the scratch copy: crash and lint-refusal outputs give rc=1, ADMIT-OFF stays rc=0, and TEST-3370/3371/3372 stay rc=0. Hazard introduced by this feature, so standing decision (a) applies: one more round, no question.
2. NON-BLOCKING `:1381`/`:1386`: the bad_noprobe cases do not assert the reason. Disposition: (a) fold into the same remediation if cheap (`expect` on `ADMIT-PROBE` / `poisoned=0`); otherwise (d) accepted residual: P3 assurance-strength gap, no observed bite, no false record.
3. NON-BLOCKING `:1325`: the literal list. Disposition: (d) accepted residual: P3 maintenance; TEST-3336 already fails on a manifest-side rename, so a silent "not admitted" needs a coordinated half-rename.

## Probes run (validator, same session, see docs/ai/validation/admit-tests-other-suites/r1-probe-malformed-admission.log)
Own-suite ADMIT-FAIL beside a passing other suite: red. Own corpus suite admitted without its probe or with a probe ending FAIL: red. CI `ADMIT-OFF ci`: unchanged pass. Truncated `ADMIT-PASS <suite>` with no fields: read as not admitted. The producer at `.aai/scripts/suite-reuse.mjs:568` always prints the fields, so today nothing can produce that line.

## Next steps
Remediation: apply finding 1 (and optionally 2), re-run the suite, `bash -n`, the selected+CORE set, then re-validate and re-review. Before close, add the `ci-full` label to the PR.
