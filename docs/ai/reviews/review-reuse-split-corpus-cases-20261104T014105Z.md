# Code Review — reuse-split-corpus-cases (round 1)

security_relevant: false

```yaml
review:
  scope: origin/main...HEAD (6db05ffa...18037b97), worktree /Users/ales/Projects/aai-worktrees/reuse-split-corpus-cases
  spec: docs/specs/SPEC-DRAFT-spec-reuse-split-corpus-cases.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "docs/analysis/precise-suite-evidence-reuse.md Measurements (corpus split); TEST-3330 PASS (246 rows, 34 corpus rows)" }
      - { ac: Spec-AC-02, call: compliant, citation: "tests/skills/test-aai-hygiene-pack.sh HYGIENE_CORPUS_CASES + main(); TEST-3331 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "tests/skills/test-aai-win-fallback.sh:1483 WIN_FALLBACK_CORPUS_TESTS, main() at :1492; TEST-3332 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "tests/skills/test-aai-hygiene-corpus.sh; TEST-3333/TEST-3334 (validator r1 + mutation records)" }
      - { ac: Spec-AC-05, call: compliant, citation: "tests/skills/suite-map.yaml core + companions; TEST-3335 PASS (11 glob paths)" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/suite-reuse.json; TEST-3336 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "admission on the branch (validator r1 ADMIT-PASS x4); TEST-3338 PASS; see BLOCKING B1 for post-merge behaviour" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3339 PASS (E1 106.4->71.5, E2 106->71.1)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-suite-reuse.sh, line: 1243,
          issue: "TEST-3337 requires ADMIT-PASS for all four split suites from a --changed-since main admission and has no ADMIT-NONE / not-admitted branch",
          failure_scenario: "After merge, any local run of test-aai-suite-reuse.sh on main (or on a branch that does not change all four entries/suite files) gets ADMIT-NONE or a partial admission; TEST-3337 fails 'no ADMIT-PASS line for aai-hygiene-pack'. Reproduced: scratch clone with main at 18037b97 -> ADMIT-NONE, rc 1. CI passes (ADMIT-OFF ci), so it lands green and bites the next local full sweep." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-reuse.sh, line: 1103,
          issue: "TEST-3331 (and TEST-3332 at :1135) pin the halves to the frozen baseline 6db05ffa: main must be exactly 66 and main+corpus exactly the 95 baseline names; ALL_TESTS exactly the baseline 32",
          failure_scenario: "The next ride that adds a hygiene case (39 commits touched this file in the last two months) turns aai-suite-reuse red in CI: 'main of the hygiene pack should register 66 cases, found 67' (reproduced on a scratch clone). A baseline-commit equality cannot be bumped, only rewritten." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-select.sh, line: 2392,
          issue: "TEST-3338 pins the new weights rows to the unsampled placeholder 212 and to a 'fallback unsampled' sample line",
          failure_scenario: "The planned H2 weights reseed rewrites both rows as measured; TEST-3338 then fails 'the weight of aai-hygiene-corpus must be the documented maximum 212'." }
      - { rank: NON-BLOCKING, file: .github/workflows/skill-suite.yml, line: 16,
          issue: "Comment lists the always-on core as four suites (validator NB-1); D5 deviation",
          failure_scenario: "A reader auditing CI cost from the workflow undercounts the core by one suite; no runtime effect." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-hygiene-corpus.sh, line: 25,
          issue: "Single-case dispatch accepts any declared function (validator NB-6)",
          failure_scenario: "'bash test-aai-hygiene-corpus.sh main' runs the 66-case fixture main under the corpus suite name; a mis-typed mutation selector naming a helper exits 0 instead of 2." }
  cannot_verify:
    - { claim: "PR skill-suite run green with aai-hygiene-corpus in core and ADMIT-OFF ci (H1)", closes_with: "the PR head's skill-suite run" }
    - { claim: "CI shard balance with two 212 placeholder rows and the now-overstated aai-hygiene-pack 97", closes_with: "H2 reseed / one full CI run's shard times" }
    - { claim: "Reuse REUSED outcome on other hosts (measurement is one M4 Max host)", closes_with: "a second-host rerun of D6" }
  overall: fail
```

## Scope

- Diff `origin/main...HEAD`, 18 files (merge base = main 6db05ffa, head 18037b97). Worktree clean.
- Spec `docs/specs/SPEC-DRAFT-spec-reuse-split-corpus-cases.md` with the three disclosed amendments (one contract: map rows, pin bumps, allowlist row; two measurement: TEST-3334 and TEST-3337 mutation cells as patches). Intake `docs/issues/CHANGE-DRAFT-reuse-split-corpus-cases.md`.
- Dispatch note: the dispatch named focus areas and said which validator notes close-out plans to fix. It did not pre-rate severity or exclude scope. I reviewed the full diff.

## What I checked

- **Split mechanics.** Sourcing guards work: the definition files run `main` only when `BASH_SOURCE[0] == $0`. When the corpus file sources them, they define functions and nothing else. `TEST_DIR=""` at the definition file's top, and `check_deps` creates the directory, so a case no longer inherits it from an earlier case. TEST-3334 covers this with test_120 alone. `ap_tmpdir` uses the same template, so behaviour is unchanged. The EXIT trap and cleanup are inherited by the corpus suite. The win-fallback corpus overrides `TEST_NAME` after sourcing and reuses `main`, so its exit codes are the definition file's: 0, 1, 42, and 2 for an unknown case. With no arguments, win-fallback `main` runs ALL_TESTS minus the corpus list. The win-fallback union is therefore structural: every ALL_TESTS number runs in exactly one half, whatever is added later.
- **Suite map.** The core list has five suites. The two new rows glob their own file plus the definition file. The companion edge aai-win-fallback → aai-win-fallback-corpus is there, and TEST-032 is bumped 38→39 / 25→26 to match. The aai-suite-reuse globs gain both files.
- **Manifest.** The two corpus entries use the SPEC-0270 note form. The fixture-half notes carry the new reads/poisoned counts. NB-5 (1951 vs 1957) is cosmetic.
- **Weights.** The two `fallback unsampled` 212 rows follow precedent: 17 such rows already exist.
- **Targeted runs** (scratch clone of 18037b97, `env -u AAI_ROLE`). TEST-3330, 3331, 3332, 3335, 3336, 3338 and 3339 PASS. TEST-3337 FAILs once `main` = HEAD (B1).

## Findings and dispositions

- **B1 (BLOCKING): TEST-3337 goes permanently red locally after merge.** Proposed disposition: remediate in-tree before the PR. Mirror TEST-3307 (test-aai-suite-reuse.sh:994-1006): pass on `ADMIT-NONE`, then judge each of the four suites only when its ADMIT line is present, failing on any `ADMIT-FAIL`. If the AC-07 proof should stay unconditional when run alone, an alternative is to run the admission with explicit `--suite` flags for the four suites. The mutation record should still bite either way: the TEST-3337 patch changes the hygiene-pack file, so that entry is admitted. Re-run mutation-gate after the edit. Disclose this as additive with disclosure: the Test Plan cell's described behaviour widens.
- **N1: TEST-3331 and TEST-3332 are baseline-equality pins.** Proposed disposition: remediate in-tree (recommended), or promote to a follow-up before the next hygiene ride. Keep the frozen-baseline check as "baseline ⊆ main ∪ corpus". Add the durable invariant in its place: every `test_*` function the definition file defines is in exactly one half. Drop the hard 66 and 32 counts. Today the only durable guard is `check-test-registration.mjs`, which treats a name's mention in HYGIENE_CORPUS_CASES as registration, plus TEST-3331's generic duplicate check. **The coverage-union guarantee was checked once against the baseline. It is not enforced for future edits.** The amendment is a contract class change to Spec-AC-02/03 wording.
- **N2: TEST-3338 pins the placeholder weight.** Proposed disposition: remediate in-tree. Accept either the unsampled 212 row or one measured sample line.
- **N3: the workflow comment (validator NB-1).** Proposed disposition: fix in close-out as planned.

### Validator notes 1–6: should any block?

None of them should block. B1 is new and was not among the validator's notes.

- **NB-1:** the comment fix as planned is fine (N3).
- **NB-2:** disclosure is enough. Both pin changes keep their meaning: LEDGER_APPEND_SUITES preserves TEST-3308's historical set.
- **NB-3:** the allowlist row is reviewed here. It is justified and has a TEST-2304 precedent. Add it to the scope; it is already in the command below.
- **NB-4:** delete the stray log. The checker accepting rc 127 as product_red is a real gate weakness, so record it as a follow-up (suggested: `fu-tdd-red-accepts-rc127`). It is not a fix in this ride.
- **NB-5:** fix as planned.
- **NB-6:** fix as planned, by adding the `test_*` guard (N-level).

## Deviations from the frozen spec

- D5 says the workflow is not touched unless its comment becomes false. The comment is now incomplete (N3).
- The TEST-032 and LEDGER_APPEND_SUITES pin changes are not named in D5 or the amendment (validator NB-2).
- The amendment covers the extra allowlist row, which the Files list omits.

## Next steps

Fix B1. Preferably also fix N1 and N2 in the same round. Re-run TEST-3337 with `main` at HEAD on a scratch clone and confirm it passes, then re-run mutation-gate. Then do a delta re-review.
