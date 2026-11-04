# Code Review — reuse-split-corpus-cases (round 2, re-pass)

security_relevant: false

```yaml
review:
  scope: origin/main...HEAD (6db05ffa...91e4e42a), worktree /Users/ales/Projects/aai-worktrees/reuse-split-corpus-cases; delta since round 1 = 18037b97..91e4e42a
  spec: docs/specs/SPEC-0271-spec-reuse-split-corpus-cases.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "docs/analysis/precise-suite-evidence-reuse.md Measurements (corpus split); TEST-3330 (unchanged in the delta; r1 PASS)" }
      - { ac: Spec-AC-02, call: compliant, citation: "amended text; tests/skills/test-aai-suite-reuse.sh:1101-1128 TEST-3331; validator r2 probes H1-H5 (added green, dropped/duplicated/unplaced red); mutation replay RED at 91e4e42a" }
      - { ac: Spec-AC-03, call: compliant, citation: "amended text; tests/skills/test-aai-suite-reuse.sh:1144-1179 TEST-3332; validator r2 probes W1-W7; mutation replay RED at 91e4e42a" }
      - { ac: Spec-AC-04, call: compliant, citation: "tests/skills/test-aai-hygiene-corpus.sh; TEST-3333/TEST-3334 (unchanged in the delta except the test_* dispatch guard, :25)" }
      - { ac: Spec-AC-05, call: compliant, citation: "tests/skills/suite-map.yaml core + companion; TEST-3335 (unchanged)" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/suite-reuse.json; TEST-3336" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-3337 :1263-1290 passes on ADMIT-NONE (main=HEAD, rc 0) and checks all four on the branch (main=6db05ffa, '4 admitted split suites', rc 0); mutation replay RED; TEST-3338 :2387-2414 accepts 212-unsampled or measured, mutation replay RED" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3339 (unchanged)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-reuse.sh, line: 1288,
          issue: "TEST-3337 fails when the admission admitted only manifest suites other than the four split suites (no ADMIT-NONE line, n=0). The same shape already exists on main in TEST-3307 (:1006).",
          failure_scenario: "A later branch edits only tests/skills/test-aai-pricing.sh (that selects aai-suite-reuse) and runs the suite locally: the admission prints ADMIT-PASS aai-pricing and nothing for the four, so TEST-3337 fails 'none of the four split suites was admitted'. Reproduced on a scratch clone, rc 1. TEST-3307 fails first on the same input (reproduced, rc 1), also on origin/main, so this ride adds no new red suite outcome." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-reuse.sh, line: 1091,
          issue: "split_defined_names recognises <<- heredocs, but it ends one only on an exact, unindented terminator line. A tab-indented terminator leaves it in heredoc mode until end of file.",
          failure_scenario: "A future hygiene case uses `cat <<-EOF` with a tab-indented EOF, and an unregistered test_ function is defined after it. TEST-3331's own exactly-one-half check does not see that function. check-test-registration.mjs (run in the same test) still catches it (probe H8, rc 1), so no coverage is lost today. There is no <<- in either definition file now." }
  cannot_verify:
    - { claim: "PR skill-suite run green with aai-hygiene-corpus in core and ADMIT-OFF ci (H1)", closes_with: "the PR head's skill-suite run" }
    - { claim: "CI shard balance with two 212 placeholder rows (R4)", closes_with: "H2 weights reseed / one full CI run's shard times" }
    - { claim: "REUSED outcome of the fixture halves on hosts other than the one M4 Max measurement host", closes_with: "a second-host rerun of the D6 protocol" }
  overall: pass
```

## Scope

- Diff `origin/main...HEAD`: 20 files, merge base main 6db05ffa, head 91e4e42a. The worktree is clean.
- Since round 1 (`18037b97..91e4e42a`) these changed: `.github/workflows/skill-suite.yml` (comment only), `docs/ai/decisions.jsonl` (+2: one contract amendment, one follow-up), the round-1 review report, the spec (D5 disclosure, Spec-AC-02/03 text, four Test Plan rows, Files list, frozen hash), `tests/skills/suite-reuse.json` (one note text), `tests/skills/test-aai-hygiene-corpus.sh` (the dispatch guard), `tests/skills/test-aai-suite-reuse.sh` (TEST-3331, 3332, 3337) and `tests/skills/test-aai-suite-select.sh` (TEST-3338). No production code changed. No `.aai/**` file changed.
- Dispatch note: the dispatch listed the round-1 dispositions it wanted confirmed and asked for anything new. It did not pre-rate severity or exclude any area. I reviewed the whole scope, with the most depth on the delta.

## Round-1 dispositions

| R1 finding | Disposition | Evidence |
|---|---|---|
| B1 TEST-3337 has no ADMIT-NONE branch | **Fixed** | `:1271` passes on ADMIT-NONE. The four suites are judged only when admitted (`:1274-1287`), ADMIT-FAIL of any of them fails, and at least one must be admitted. Scratch clone with `main` = HEAD: rc 0, `PASS: TEST-3337 (ADMIT-NONE ...)`. Scratch clone with `main` = 6db05ffa: rc 0, `4 admitted split suites` (304 s). The mutation (test_562 back in the fixture main) replays RED. One residual of the same class remains open; see NB-1. |
| N1 TEST-3331/3332 baseline-equality count pins | **Fixed** | The 66/95/32 counts are gone. The checks now are: baseline ⊆ main ∪ corpus; every column-0 test_ function outside heredocs in exactly one half; no duplicates; no half names an undefined function. For win-fallback: ALL_TESTS ⊇ baseline, no duplicates, defined ⇔ ALL_TESTS. Probes are below. The HYGIENE_CORPUS_CASES 29-name list pin and the five-number corpus pin stay, because Spec-AC-02/03 require them. |
| N2 TEST-3338 pins weight 212 | **Fixed** | Accepts exactly one `fallback unsampled` or `measured` sample line, and requires 212 only for an unsampled row. The mutation replays RED. |
| N3 workflow comment | **Fixed** | `.github/workflows/skill-suite.yml:16` lists hygiene-corpus. |
| N4 corpus dispatch accepts any function | **Fixed** | `tests/skills/test-aai-hygiene-corpus.sh:25` requires `test_*`. |
| NB-2/3 disclosure | **Fixed** | D5 has a new paragraph, and the Files list names the allowlist and the workflow. |

## N1 partition probes (scratch clone of 91e4e42a, `main` = 6db05ffa)

Hygiene, TEST-3331:

| Probe | Expected | Result |
|---|---|---|
| H1 case defined and added to main | green | green (29 + 67) |
| H2 baseline case dropped from main | red | red: `baseline cases in neither half: test_120_...` |
| H3 case registered twice | red | red: `names in both halves or registered twice` |
| H4 case defined, in neither half | red | red: `defined cases not in exactly one half: test_998_unregistered (0x)` |
| H5 case moved main → corpus | red, by design | red: the 29-name pin (Spec-AC-02 text). A deliberate move must edit the test's expected list. |
| H6 heredoc fixture with a column-0 test_ fn | green from the partition | The partition awk excludes the fake. The real file already holds one such heredoc function, and the awk gives 96 where a plain grep gives 98. The test still went red, from `check-test-registration.mjs` (`ORPHAN TEST: test_fake_in_heredoc`). That lint predates this ride and does not know about heredocs. It is not a defect of this delta. |
| H7/H8 `<<-` heredoc | — | See NB-2. |

Win-fallback, TEST-3332:

| Probe | Expected | Result |
|---|---|---|
| W1 add (defined and in ALL_TESTS) | green | green |
| W2 drop a number | red | red |
| W3 duplicate a number | red | red |
| W4 defined but not listed | red | red |
| W5 move to corpus | red, by design | red: the five-number pin (Spec-AC-03) |
| W6 heredoc fixture `test_097` | green | green |
| W7 listed but undefined | red | red |

## Findings and recommended dispositions

- **NB-1** (`tests/skills/test-aai-suite-reuse.sh:1288`, and the pre-existing `:1006`): recommended disposition (b), a follow-up covering both TEST-3307 and TEST-3337, suggested id `fu-admit-tests-red-on-other-suites` (P3). The fix is to pass when the admission admitted other suites but none of this test's set, mirroring ADMIT-NONE. The class predates this ride (TEST-3307 on main), TEST-3307 fails first on that input, and fixing it in-tree here would cost a third round on a scope already at the two-round cap. Not filed by me; the reviewer is read-only.
- **NB-2** (`tests/skills/test-aai-suite-reuse.sh:1091`): recommended disposition (d): `accepted residual: split_defined_names does not end a <<- heredoc whose terminator is tab-indented; no <<- exists in either definition file, and check-test-registration.mjs in the same test catches an unregistered function hidden this way (probe H8), so the gap has no observed bite` (P3 assurance strength).

INFO (does not gate):
- The `aai-hygiene-corpus` note still says `reads=1972` exactly. The NB-5 fix changed only the win-fallback-corpus note to "about". Cosmetic; no test pins the number.
- `tests/skills/test-aai-win-fallback-corpus.sh:26` passes any argument to `main`, so `... 009` runs a fixture case under the corpus name. This is the win-fallback analogue of N4. The definition file's own `main` rejects unknown numbers, so there is no wrong exit code.

## Spec amendment check

The 2026-11-04T01:50:03Z record (`amendment_class: contract`, unsigned, `tracked_by: fu-amend-spec-reuse-split-corpus-cases`) names Spec-AC-02/03 and the TEST-3331/3332/3337/3338 rows, the D5 disclosure and the Files list. `git diff 18037b97..91e4e42a -- <spec>` changes exactly those, plus the frozen hash restamp. Widening AC text is a contract change, so the class is honest. `spec-amend list --strict` rc 0, `unsigned-untracked=0`.

## Next steps

Run the PR flow when validation r2 passes. The orchestrator records the NB-1 follow-up and quotes the NB-2 `accepted residual:` line in `code_review.notes`.
