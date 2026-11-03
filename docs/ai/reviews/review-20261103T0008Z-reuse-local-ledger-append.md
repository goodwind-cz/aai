# Code review re-pass — reuse-local-ledger-append

security_relevant: false

- Scope: `git diff origin/main...HEAD` (base origin/main = 9c487740, head 3ab1c080ebe12f4e21b0d64b3424ac8098a4ed82), branch feat/reuse-local-ledger-append, worktree /Users/ales/Projects/aai-worktrees/reuse-local-ledger-append. Remediation delta: 3ec7f990..3ab1c080.
- Spec: docs/specs/SPEC-0270-spec-reuse-local-ledger-append.md (frozen, ceremony 2, mutation_gate v1), with two disclosed measurement-class amendments (decisions.jsonl 2026-11-02T22:51:44Z and 2026-11-02T23:25:07Z).
- Reviewer: claude-opus-5-5. The remediator was sonnet. This same context wrote the r1 review and ran validation r3 just before this pass. That is a residual independence limit on a re-pass, not a review of my own code.
- Dispatch note: the dispatch listed the remediation's claimed dispositions (B1, N1, N2, amendment) and asked me to confirm them. It did not pre-rate new findings or exclude any area. I re-read the full scope diff and walked the delta line by line.

```yaml
review:
  scope: origin/main...3ab1c080ebe12f4e21b0d64b3424ac8098a4ed82
  spec: docs/specs/SPEC-0270-spec-reuse-local-ledger-append.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/suite-reuse.mjs:133-147,185-193,337 (unchanged in delta); TEST-3300 green at 3ab1c080 (val-r3 suite log)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/suite-reuse.mjs:142-147; TEST-3301 green at 3ab1c080" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/suite-reuse.mjs:190,249; TEST-3302 green; mutation-gate rc 0" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/suite-reuse.mjs:337; TEST-3303 green" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/suite-reuse.mjs:448-460 (D3 literal still first occurrence at :456; new rmSync at :457 is outside the contract); TEST-3304, TEST-3305 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/test-aai-suite-reuse.sh:985-1000 matches the amended TEST-3307 row (spec :328); green on the branch with 5 probes and on main=HEAD with ADMIT-NONE (val-r3); mutation replay RED" }
      - { ac: Spec-AC-07, call: compliant, citation: "docs/analysis/precise-suite-evidence-reuse.md (unchanged in delta); TEST-3308 green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-reuse.sh, line: 992,
          issue: "The TEST-3307 mutation record can only redden where suites are admitted. The new ADMIT-NONE short-circuit makes the record stay green when it is replayed from a main checkout after merge",
          failure_scenario: "mutation-run.mjs clones its source with `git clone --local` (:653). From a feature-branch checkout the clone has no local `main`, so changedBase returns null and all suites are admitted: RED, as recorded. From the main checkout after merge, the clone's `main` is HEAD, so the run prints ADMIT-NONE, TEST-3307 passes under the mutation, and `--replay --spec` reports this record as STAYED GREEN (exit 1). That would only happen if this done spec is re-validated from main. The mutation site itself stays guarded on main by TEST-3305: `tailOk = ra.status !== 0` turns its tailok suite into ADMIT-FAIL." }
  cannot_verify:
    - { claim: "The PR head's CI skill-suite and ps1-quality runs succeed (TEST-3276/3307 take ADMIT-OFF ci there)", closes_with: "the PR's check runs after push" }
    - { claim: "No future index-reading suite reads appended ledger lines leniently (the D3 probe cannot see a lenient reader)", closes_with: "not provable from the diff; the spec caveat states it" }
    - { claim: "Close-out steps (product doc sentence with N2's scope, CHANGELOG, fu close, INDEX) are correct", closes_with: "a re-review of the close-out commit, then set-code-review rerun on the widened scope" }
  overall: pass
```

## r1 findings: dispositions confirmed

### B1 (BLOCKING): RESOLVED

tests/skills/test-aai-suite-reuse.sh:992 adds `ADMIT-NONE` as a pass, after the ADMIT-OFF branch and before the per-suite loop. That mirrors TEST-3276 at :667. `ADMIT-NONE` is printed only when nothing was picked (suite-reuse.mjs:559), so it can never appear next to ADMIT-PASS or ADMIT-FAIL lines and mask a failed probe.

Validation r3 reproduced both cases:
- In a scratch clone of 3ab1c080 with main = HEAD, the admission printed ADMIT-NONE, and the whole suite returned rc 0 with 58 PASS.
- On the branch, TEST-3307 checked the appended-probe line of all five suites.

The recorded mutation still reddens on a branch (replayed: rc 1, recorded first_fail). The spec row (:328) was amended to match, and the amendment is disclosed.

### N1 (NON-BLOCKING): RESOLVED

suite-reuse.mjs:457 removes `tdir` right after `spawnSync` returns. The child has exited by then, `ra.status` and `tailOk` are read first, and nothing uses `tdir` afterwards. Error paths:
- A spawn error gives `status: null`. The clone is removed, and the run reports ADMIT-FAIL `rc=null`.
- A throw between the clone and the run (:453-454) escapes to `admitSuites`' `finally` (:496), which removes `tmp`, and `tmp` contains `tdir`.

Validation r3 observed both behaviours:
- With two admitted suites, each `-t` clone existed during its own run and was gone before the next suite's `-t` clone appeared.
- An injected throw left TMPDIR empty.

### N2 (NON-BLOCKING): RESOLVED

Spec :196 now reads "runs each index-reading suite once when it is admitted locally". That matches D3 (:203-212) and the code (:448 `trace.index_read`, :557 `ADMIT-OFF ci`). The close-out product doc sentence still has to carry this scope. That is listed under cannot_verify.

### Amendment

The 2026-11-02T23:25:07Z record's `what` covers exactly the text diff of the spec in 3ec7f990..3ab1c080: the TEST-3307 cell, the caveat sentence, and the frozen_sha256 restamp. The class `measurement` is honest. No AC predicate, AC count or mutation changed: the row's Description gained an accepted outcome for a state the AC never promised to cover (nothing to admit). One naming nit: the record says "D3 caveat", but the sentence is in the D2 section and describes the D3 guard. `spec-amend list --strict` rc 0.

## New in the delta

### NB1 (NON-BLOCKING, P3): the TEST-3307 mutation record is branch-bound

See the YAML block. The record proved what it was written to prove: on the branch, the live admission catches an inverted `tailOk`. After merge, a replay from main can no longer reach the mutated line through TEST-3307. The same site is covered there by the fixture tests TEST-3304 (`tailOk = true`) and TEST-3305 (`tailOk = false`, and by extension `!== 0`), which do not depend on main.

Proposed disposition: **(d) accepted residual**, with this line:

`accepted residual: NB1 TEST-3307 mutation record reddens only where suites are admitted (branch time); after merge a replay from main stays green on ADMIT-NONE; P3 assurance-strength, no bite, TEST-3304/3305 guard the same site on main`

If the orchestrator would rather not carry a record that will one day replay green, the alternative is (b): `fu-mutation-record-branch-bound`, P3. That would let mutation-run or the record declare a branch-only precondition.

### INFO (does not gate)

- suite-reuse.mjs:457. When a run times out, `spawnSync` kills only the bash child. A surviving grandchild still writing into `tdir` could make `rmSync` throw ENOTEMPTY and abort the admission. Before N1 the same throw came from the `finally` at :496, so the outcome is unchanged. Only the timing moves.
- N1 bounds only the `-t` clones. The `-a` clone per suite and the `-p` clone of a non-index suite are still held until the end. The review r1 sizing was mostly about `-t` × 5, which is now gone.
- No test asserts N1's early removal. No AC requires it, and validation r3 observed it directly.

## Consumer-visible docs

These are unchanged from r1. docs/product/precise-suite-evidence-reuse.md needs the close-out sentence, including N2's "index-reading suites, locally" scope. No `.aai` prompt needs a sentence.

## Warning dispositions (H6)

- B1: remediated (3ab1c080).
- N1: remediated (3ab1c080).
- N2: remediated in the spec (3ab1c080). The product-doc wording follows at close-out.
- NB1: proposed `accepted residual: NB1 TEST-3307 mutation record reddens only where suites are admitted (branch time); after merge a replay from main stays green on ADMIT-NONE; P3 assurance-strength, no bite, TEST-3304/3305 guard the same site on main`. The alternative is a follow-up, fu-mutation-record-branch-bound (P3).

## Next steps

1. Record the NB1 disposition, then run the close-out: product doc, CHANGELOG, fu close before the cited sweep (val-r2 B2 precondition), INDEX, and one full sweep.
2. Re-review the close-out commit, and run set-code-review again on the widened scope.

state_update_commands (not run by the reviewer):

```
node .aai/scripts/state.mjs set-code-review --required true --status pass --report docs/ai/reviews/review-20261103T0008Z-reuse-local-ledger-append.md --base-ref main --head-ref 3ab1c080ebe12f4e21b0d64b3424ac8098a4ed82 --scope ".aai/scripts/suite-reuse.mjs docs/INDEX.md docs/ai/EVENTS.jsonl docs/ai/decisions.jsonl docs/ai/reviews/review-20261102T2330Z-reuse-local-ledger-append.md docs/ai/roadmap.yaml docs/analysis/precise-suite-evidence-reuse.md docs/issues/CHANGE-0243-reuse-local-ledger-append.md docs/specs/SPEC-0270-spec-reuse-local-ledger-append.md tests/skills/lib/suite-reuse.test.mjs tests/skills/suite-reuse.json tests/skills/test-aai-suite-reuse.sh" --notes "re-pass: spec_compliance pass (7/7); code_quality pass; B1 N1 N2 remediated at 3ab1c080; NB1 'accepted residual: NB1 TEST-3307 mutation record reddens only where suites are admitted (branch time); after merge a replay from main stays green on ADMIT-NONE; P3 assurance-strength, no bite, TEST-3304/3305 guard the same site on main'"
```
