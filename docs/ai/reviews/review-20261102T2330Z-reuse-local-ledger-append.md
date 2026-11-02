# Code review — reuse-local-ledger-append

security_relevant: false

- Scope: `git diff origin/main...HEAD` (base origin/main = 9c487740, head 3ec7f99054f5f16e5cccfdb37cc6b69b1fc2040b), branch feat/reuse-local-ledger-append, worktree /Users/ales/Projects/aai-worktrees/reuse-local-ledger-append
- Spec: docs/specs/SPEC-DRAFT-spec-reuse-local-ledger-append.md (frozen, ceremony 2, mutation_gate v1), with its one disclosed amendment (decisions.jsonl 2026-11-02T22:51:44Z, class measurement: TEST-3301..3303 file cells, D2 caveat wording)
- Reviewer: claude-opus-5-5, separate context (implementer and remediator: sonnet). The same context ran validation r2 just before this pass.
- Dispatch note: the dispatch named focus areas (prefix logic, fail-closed paths, extra scratch clone, tests, manifest notes, consumer docs). It did not pre-rate any finding. I reviewed the full scope anyway.

```yaml
review:
  scope: origin/main...3ec7f99054f5f16e5cccfdb37cc6b69b1fc2040b
  spec: docs/specs/SPEC-DRAFT-spec-reuse-local-ledger-append.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/suite-reuse.mjs:114,133-147,188-193,337; TEST-3300 green (val-r2 suite log), RED on 9c487740 (val-r1)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/suite-reuse.mjs:142-147 (prefix sha256 plus current mode); TEST-3301 green, RED on baseline" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/suite-reuse.mjs:190 (index_read gate), :249 (append_prefix defaults to {}); TEST-3302 green, RED by mutation" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/suite-reuse.mjs:133-141,337; TEST-3303 green" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/suite-reuse.mjs:447-459; TEST-3304, TEST-3305 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/suite-reuse.json:7,12,17,22,32; TEST-3306, TEST-3307 green on the branch (see B1: TEST-3307 as specified only holds on this branch)" }
      - { ac: Spec-AC-07, call: compliant, citation: "docs/analysis/precise-suite-evidence-reuse.md Measurements (ledger append); TEST-3308 green; after sha 0d7992dc disclosed, repeated at e7797c86 by val-r1" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-suite-reuse.sh, line: 998,
          issue: "TEST-3307 requires at least one of the five index-reading suites to be admitted by the live lint --admit --changed-since main; ADMIT-NONE is a failure",
          failure_scenario: "After this PR merges, any local run of aai-suite-reuse on main, or on a later branch that does not change those five manifest entries or suite files, gets ADMIT-NONE from TEST-3276 and fails at TEST-3307. Reproduced in a scratch clone of 3ec7f990 with main pointed at HEAD: TEST-3276 PASS (0 ADMIT-PASS lines), TEST-3307 rc=1 'none of the five index-reading suites was admitted'. CI does not see it, because it takes the ADMIT-OFF ci branch." }
      - { rank: NON-BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 450,
          issue: "The appended-ledger run makes a second full --no-hardlinks clone per index-reading suite. It is never removed until admitSuites' finally (:495), so all clones of one admission stay on disk together",
          failure_scenario: "A full admission (no --changed-since, or a manifest-wide change) of the 11 suites now holds 11 '-a' clones plus 5 '-t' clones, each about 70 MB working tree plus 41 MB pack, about 1.7 GB in TMPDIR at peak. A small TMPDIR fills and the later clones fail with 'scratch-repo'. That is fail-closed, but the error message is misleading. Removing the '-t' clone right after its run, or reusing the '-a' clone after restoring its ledger, bounds this." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-reuse-local-ledger-append.md, line: 196,
          issue: "Caveat says the admission gate 'runs each manifest suite once'; D3 (:203-212) and the code (:448) run the appended-ledger probe only for index-reading suites, and only locally (ADMIT-OFF ci)",
          failure_scenario: "The close-out product doc sentence is copied from D2. It would tell a reader that every manifest suite, including the six non-index ones, is probed against an appended ledger line. They are not, and none of them is tolerated either. The wording overstates the guard, not the identity." }
  cannot_verify:
    - { claim: "H1/H2: the PR head's CI skill-suite and ps1-quality runs succeed, with ADMIT-OFF ci", closes_with: "the PR's check runs after push" }
    - { claim: "Real-world false-hit rate: no future index-reading suite reads appended ledger lines leniently (the D3 probe cannot see a lenient reader)", closes_with: "a per-suite grep at each admission, or a valid-JSON poison line as well; not provable from the diff" }
    - { claim: "Close-out steps 1-4 (product doc, CHANGELOG, fu close, INDEX) are correct", closes_with: "a re-review of the close-out commit with set-code-review rerun on the widened scope (the spec requires it)" }
  overall: fail
```

## AC table walk

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | suite-reuse.mjs:114 (constant, first occurrence), :133-141 `appendPrefix`, :142-147 `appendedOnly`, :188-193 check-side substitution, :337 record field. TEST-3300 drives the real framework three times; the ledger grows each run, and the suite executes once (marker_count 1). |
| Spec-AC-02 | compliant | `appendedOnly` hashes `buf.subarray(0, bytes)` with the *current* mode (:146), so an equal-length edit, a truncation, and chmod +x all miss. Another path is not substituted, so EVENTS or docs/x.md edits miss. TEST-3301 covers the seven cases. |
| Spec-AC-03 | compliant | `tolerate` requires `trace.index_read` (:190). `traceOfRecord` gives `{}` when the record has no object (:249). TEST-3302 covers both arms. |
| Spec-AC-04 | compliant | `append_prefix` only under `traced.index_read` (:337), so `undefined` is dropped by JSON.stringify. TEST-3303 asserts that the key is absent. |
| Spec-AC-05 | compliant | :447-459. ADMIT-FAIL reason `appended-ledger run failed rc=<status>`, and the probe line is printed only for index_read. TEST-3304 and TEST-3305. |
| Spec-AC-06 | compliant (on the branch) | All five notes name the ledger. TEST-3306 and TEST-3307 are green here, but see B1. |
| Spec-AC-07 | compliant | The analysis note section, with 22 rows. TEST-3308. The after sha is disclosed (:280-282 of the note). |

Deviations from the frozen spec. Each one is checked against D1/D3 literal text:
- None in code. Every D1/D3 literal is at its first occurrence. Mutation-gate rc=0 (9 rows) confirms that.
- The only spec amendment is the disclosed measurement-class record. Its `what` matches the text diff e7797c86..3ec7f990: the three file cells, the caveat, and the frozen_sha256 restamp.
- The close-out steps (product doc, CHANGELOG, fu close, INDEX regeneration) are not done yet. That is by design, because they run after LOOP COMPLETE.

## Findings

### B1 (BLOCKING): TEST-3307 fails on every local run where nothing is admitted

tests/skills/test-aai-suite-reuse.sh:998. The test was written as the spec row says ("at least one such suite is admitted on this branch", spec :328). The assertion is only true while the branch differs from main in those five entries. TEST-3276 accepts `ADMIT-NONE` at :667. TEST-3307 does not.

How I reproduced it:
1. I cloned 3ec7f990 into scratch and ran `git branch -f main HEAD`.
2. `lint --admit --changed-since main` printed `ADMIT-NONE`, rc 0.
3. `bash tests/skills/test-aai-suite-reuse.sh test_3307_live_appended_probes` returned rc=1.

Proposed disposition: **remediate in tree before the PR.**
- Accept ADMIT-NONE the way TEST-3276 does, and log PASS "(nothing admitted)". Keep the per-suite PROBE assertion for each suite that was admitted.
- Amend the TEST-3307 Description cell additively, class measurement, because it changes how Spec-AC-06 is measured and not what it promises.
- Spec-AC-06 stays evidenced by admit-live.txt and the branch run.
- The mutation `tailOk = ra.status !== 0` still reddens on the branch, because the five suites are admitted there.

### N1 (NON-BLOCKING, P3): the second scratch clone is held until the end of the admission

.aai/scripts/suite-reuse.mjs:450 (with :495).
- Cost per index-reading suite: one more full clone, plus one more full suite run (the run cost is spec R2, accepted).
- Cleanup on error is correct: `admitSuites` removes `tmp` in `finally`, including when a throw escapes `admitSuite`.
- Peak disk grows by 5 × about 110 MB.

Proposed disposition: **remediate in tree** if B1 is remediated anyway: `fs.rmSync(tdir, { recursive: true, force: true })` after :455, about one line. Otherwise **accepted residual**: "P3 cost, fail-closed on ENOSPC, no observed bite".

### N2 (NON-BLOCKING, P3): the caveat scope says "each manifest suite"

spec :196. The probe applies to index-reading manifest suites only, and only on local admission.

Proposed disposition: **fold into the close-out product doc sentence** (close-out step 1). Write "each index-reading manifest suite, locally, when its entry or suite file changes". If B1 already brings an amendment, fix the spec text in the same measurement-class amendment.

### INFO (does not gate)

- tests/skills/suite-reuse.json:7,12,17,22,32. The new notes dropped "or untracked" from the old wording, but the identity still includes the path list, so a new untracked file is still a miss. The notes are less complete than before. This only errs toward fail-closed (a reader expects reuse and gets RUN).
- A throw from `fs.appendFileSync(tledger, …)` (:454), for example EACCES on the scratch file, escapes `admitSuite` and aborts the whole `lint --admit` instead of printing ADMIT-FAIL. The same is true of the existing `poisonFile` path. tmp is still cleaned.
- Prefix logic, read adversarially: a hit needs sha256 plus the mode of the current first `bytes` bytes to equal the arm hash, and the identity then compares against the record's whole `inputs_map`. Tampered `bytes`/`sha256` values, arrays, null, and concurrent appends only miss. Validation r1 confirmed this with 24 probes. The substitution runs only when `recorded` is false, so a record can never store the tolerated value instead of the arm hash.

## Consumer-visible docs

- docs/product/precise-suite-evidence-reuse.md: **needs the sentence**. It is close-out step 1, and the spec already plans it.
  - :30, "every file when the run read the git index", must gain the run-ledger exception.
  - :95-101 (Limits) still lists `fu-reuse-local-ledger-append` as the open cause.
  - Carry N2's corrected caveat scope.
- `.aai` prompts: **no sentence needed**. SKILL_VERIFY.prompt.md:21 and VALIDATION.prompt.md:194 point to the product doc and say nothing about index-reading identity. SUBAGENT_CONTRACT.md:15 (HAZ-LEDGER, append-only) is unchanged and consistent.
- CHANGELOG: close-out step 2.

## Warning dispositions (H6)

- B1: remediate in tree (blocks).
- N1: remediate in tree with B1, else `accepted residual: P3 cost, fail-closed on ENOSPC, no observed bite`.
- N2: remediate in the close-out product doc and the spec amendment.

## Next steps

1. Remediation: B1, plus N1 and N2 if cheap. Then rerun `test-aai-suite-reuse.sh` and do a scratch-clone check of TEST-3307 with main = HEAD.
2. Re-review the delta, then do the close-out, then run `set-code-review` again on the widened scope.

state_update_commands (not run by the reviewer):

```
node .aai/scripts/state.mjs set-code-review --required true --status fail --report docs/ai/reviews/review-20261102T2330Z-reuse-local-ledger-append.md --base-ref main --head-ref 3ec7f99054f5f16e5cccfdb37cc6b69b1fc2040b --scope ".aai/scripts/suite-reuse.mjs docs/INDEX.md docs/ai/EVENTS.jsonl docs/ai/decisions.jsonl docs/ai/roadmap.yaml docs/analysis/precise-suite-evidence-reuse.md docs/issues/CHANGE-DRAFT-reuse-local-ledger-append.md docs/specs/SPEC-DRAFT-spec-reuse-local-ledger-append.md tests/skills/lib/suite-reuse.test.mjs tests/skills/suite-reuse.json tests/skills/test-aai-suite-reuse.sh" --notes "spec_compliance pass (7/7); code_quality fail: B1 TEST-3307 fails locally whenever ADMIT-NONE (post-merge main), remediate in tree; N1 second scratch clone held to end, remediate with B1 else accepted residual; N2 caveat scope 'each manifest suite', fold into close-out product doc"
```
