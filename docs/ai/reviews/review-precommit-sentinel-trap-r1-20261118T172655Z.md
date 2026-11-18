# Code Review r1 — precommit-sentinel-trap

```yaml
review:
  scope: "git diff origin/main (59ca96e2) -- .aai/scripts/pre-commit-checks.sh tests/skills/test-aai-pre-commit-checks.sh; untracked docs/issues/ISSUE-0123-precommit-sentinel-trap.md, docs/specs/SPEC-0302-spec-precommit-sentinel-trap.md"
  spec: docs/specs/SPEC-0302-spec-precommit-sentinel-trap.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/pre-commit-checks.sh:105 (PCC_PARSED=0), :202 (no :-0 default); TEST-3883 PASS (reviewer run); reviewer mutant dropping line 105 reddens TEST-3883 (exit 0, expected 1)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/pre-commit-checks.sh:202 keyed on IN_REPO; TEST-3884 PASS; reviewer mutant re-keying on PCC_LIST reddens TEST-3884 (exit 0) while TEST-3883 stays green, so each sentinel defect has its own killer" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/pre-commit-checks.sh:108 trap unchanged; TEST-3885 PASS; reviewer probe on /bin/bash 3.2.57: mutant without the close leaves the scratch dir at ulimit -n 5 only (4, 6, 7 clean), the delivered script leaves none at 4-7" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/pre-commit-checks.sh:279-280 comment, skip lists :253 vs :282 verified subset; TEST-3886 PASS; mutation-TEST-3886.txt shows exit 0 under the CHECK-4-skips-.js mutant" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "tests/skills/test-aai-pre-commit-checks.sh:233-234 (192 30), :513 (485/361); TEST-3887 PASS (reviewer run, 8 s); full-suite exit 0 is the validator's run 1 and green-full-suite.log, not re-run here" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0302-spec-precommit-sentinel-trap.md, line: 0,
          issue: "D3 says that because TEST-3883 also exports PCC_LIST=0 and IN_REPO=0 'an initialisation removed later from any of them is seen'. TEST-3883 does not see either removal; and the filed follow-up fu-precommit-sibling-init-pin says the opposite but is wrong too ('not seen by the suite'): TEST-3875 does see both removals, through set -u",
          failure_scenario: "Reviewer scratch mutants: dropping '^IN_REPO=0$' or '^PCC_LIST=0$' keeps TEST-3883 PASS and makes TEST-3875 FAIL ('a non-repository directory with a missing TMPDIR exited 1, expected 0'), because the script reads the unset flag under set -u in a non-repository directory. Two ledger records now say different false things about what pins these lines" }
    info:
      - "TEST-3885 text pin (test:1059) is grep -qF over the whole file, so on bash 5 (CI), where the behavioural half cannot kill, a commented copy of the old trap line would satisfy it. Assurance-strength only"
      - "TEST-3886's shim removes the copy after the shell has already opened CHECK 3's '< $blob' stdin (mutation record output still shows 'Debug statements in app.js'). It pins CHECK 4's re-test, not the pre-open 'reads as no matches' variant the comment at :279-280 describes. CHECK 4's [ -f ] test does not depend on CHECK 3's result, so the seam is pinned either way"
      - "docs/ai/tdd/spec-precommit-sentinel-trap/mutation-TEST-3883.2026-11-18T16:19:33Z.txt is the superseded mutant that was killed only by a syntax error (exit 2). The directory is gitignored local evidence and is not shipped"
      - "TEST-3887 re-runs six cases that main() already runs (about 8 s more per full suite run). A cost, not a defect"
  cannot_verify:
    - { claim: "bash 5 / GNU userland behaviour of TEST-3883..3887",
        closes_with: "CI Ubuntu leg green on the pushed head (only the implementer's green-linux-bash52.log exists; not run by the reviewer)" }
    - { claim: "the full test suite and the full skill sweep exit 0 on this head",
        closes_with: "orchestrator's full sweep with AAI_TEST_TIMEOUT=3600 before close; the reviewer ran only the five new selectors (TEST-3887 runs 3454, 3461, 3873, 3875, 3880 and 3882)" }
    - { claim: "the dispatch prompt hash 8e6aae0d...ccc86 matches the canon payload read",
        closes_with: "canon-build's own hash recipe; shasum -a 256 of canon-cr.txt gives fee4a08a...7a85b, and stripping the trailer line gives b6a4ef56..., neither matches" }
    - { claim: "Windows (Git Bash) behaviour",
        closes_with: "not in CI; residual risk the spec already states" }
  overall: pass
```

security_relevant: true

## Scope and spec

- Scope: the explicit path list above, diffed against origin/main 59ca96e2 in the worktree
  `/Users/ales/Projects/aai-worktrees/precommit-sentinel-trap` (branch fix/precommit-sentinel-trap). Ledger appends
  (EVENTS, decisions, INDEX, test-runs) were not reviewed, as instructed. I only read decisions.jsonl to check the
  follow-up record.
- Spec: docs/specs/SPEC-0302-spec-precommit-sentinel-trap.md (frozen, ceremony_level 3).
- Coaching check: the dispatch named focus areas (fail-open, mutant kills, hygiene, spec vs code). It did not
  pre-rate any finding or leave any area out of scope. It did mention that the validator's NB-1 is filed. I
  re-measured that finding myself rather than relying on the note.

## What the change does (verified against the code)

1. `PCC_PARSED=0` is set unconditionally at top level (line 105), before both staged-content blocks, so an
   inherited value is overwritten. The sentinel at line 202 reads `"$PCC_PARSED"` and no longer has a `:-0` default.
2. The sentinel is now keyed on `IN_REPO` (set at line 18-19 before anything else), not on `PCC_LIST`. Block 1
   either sets `PCC_LIST=1` or exits through `staged_read_fail`, and block 2 sets `PCC_PARSED=1` as its final
   statement. So for IN_REPO=1, any discard of either compound command (bash drops the whole top-level command
   on an arithmetic or expansion error and continues with rc 0) leaves `PCC_PARSED=0` and blocks. For IN_REPO=0,
   neither block runs and nothing is judged, which is the same as before. An in-repository run with an empty
   index still reaches `PCC_PARSED=1`: `${#arr[@]}` on an empty array is safe under `set -u` on bash 3.2.
3. A comment at CHECK 4's skip list states that it must stay a subset of CHECK 3's skip list.

Fail-open analysis (bash 3.2, `set -euo pipefail`):
- No statement between line 18 and line 202 that runs at top level outside the two `if` blocks contains an
  expansion that can abort.
- `PCC_PARSED=1` is the last statement of block 2, so a partial block cannot set it.
- The sentinel itself compares only values the script has assigned (0/1).
- `set -u` failures exit the shell non-zero, which fails closed.

I found no path where IN_REPO=1 and the parse is incomplete but the commit gets through. The validator's sweep of
43 inherited variable names agrees.

## Did the new tests kill the stated mutants? (reviewer-run, scratch copy, /bin/bash 3.2.57)

| Mutant | TEST-3883 | TEST-3884 | Other |
|---|---|---|---|
| drop `PCC_PARSED=0` | FAIL (exit 0) | FAIL (unbound / no fail-closed line) | — |
| sentinel re-keyed on `PCC_LIST` | PASS | FAIL (exit 0, "No staged files to check") | — |
| trap without `3<&- 4<&-` | — | — | TEST-3885: left behind at n=5 only (direct probe) |
| drop `IN_REPO=0` | PASS | — | TEST-3875 FAIL |
| drop `PCC_LIST=0` | PASS | — | TEST-3875 FAIL |

The five new selectors pass on the delivered tree (3883 0 s, 3884 1 s, 3885 0 s, 3886 0 s, 3887 8 s). No
`aai-pre-commit*` or suite directories were left in `$TMPDIR` afterwards, and the worktree status was unchanged.

Hygiene:
- Every new case uses suite-owned `$TEST_DIR` paths and a private `TMPDIR` where cleanup is asserted.
- The TEST-3886 shim deletes only `"$TMPDIR"/aai-pre-commit.*/[0-9]*` under that private directory.
- Each `sed` mutant is guarded by a `cmp` check against the shipped file, so a mutant that fails to apply is not
  mistaken for a pass.
- TEST-3886 asserts that its shim actually ran (the `done` marker).
- TEST-3885 checks that `ulimit` succeeded (rc 99).
- I found no assertion that can pass vacuously. TEST-3885 at n=4 and n=6 does not exercise the leftover path,
  but n=5 does, and the spec says so.

## Findings

### NB-1 (NON-BLOCKING, P3): the D3 claim and its follow-up record disagree, and both are wrong

- Location: spec D3, "The test sets the sibling flags in the environment as well (`PCC_LIST=0`, `IN_REPO=0`), so
  an initialisation removed later from any of them is seen."
- Measured: with either line removed, TEST-3883 still passes, so D3's attribution is false. TEST-3875 fails on
  both removals, because the non-repository run reads the unset flag under `set -u`. So the suite does see the
  removal.
- The filed follow-up `fu-precommit-sibling-init-pin` says "removing either initialisation is not seen by the
  suite", which is also false.
- What is actually unpinned is narrower: a removed init combined with an inherited `1` in a non-repository
  directory. That direction is fail-closed (a false block), and TEST-3875 would already redden on the removal.
- Recommended disposition: (a)/(c), not (d), because a false record is involved. The orchestrator should either:
  - reword the follow-up (or close it as covered by TEST-3875 and replace it with a correction note), and correct
    D3 by a measurement-class spec amendment, naming TEST-3875 as the pin; or
  - keep the follow-up's intent (export `1` in a non-repository fixture) but correct its finding text.

### INFO (none gate)

- TEST-3885's text pin matches comment lines too. On bash 5 that is the only kill.
- TEST-3886 models removal after CHECK 3 opened the copy. Because CHECK 4's re-test is independent of CHECK 3's
  result, it pins the same seam.
- The superseded dated mutation record (syntax-error kill) sits next to the current one. It is gitignored.
- TEST-3887 duplicates six cases that `main()` already runs, which costs about 8 s.

## Warning dispositions (H6)

- NB-1: recommended (c), correct the follow-up record `fu-precommit-sibling-init-pin` (its finding text is false),
  together with an amendment of the D3 wording. The orchestrator records this. A read-only reviewer files nothing.

## Next steps

1. The orchestrator handles NB-1's record correction.
2. Run the full skill sweep (`AAI_TEST_TIMEOUT=3600`) before close, as the validation report requires.
3. After pushing, confirm the CI bash 5 leg is green on the pushed head.
