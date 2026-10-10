# Code review — win-fallback-test028-red-on-bash-3 (round 1)

```yaml
review:
  scope: origin/main...HEAD (ebc5d72b..b28ac995), worktree /Users/ales/Projects/aai-fix-win-fallback-test028-red-on-bash-3
  spec: docs/specs/SPEC-DRAFT-spec-win-fallback-test028-red-on-bash-3.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-aai-win-fallback.sh:810-815 gate; `bash tests/skills/test-aai-win-fallback.sh 028 042` rc=0 on bash 3.2.57 with the named SKIP line" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "test-aai-win-fallback.sh:778-789 helpers (probe reads PATH `bash`, decision fails closed to run on empty/non-numeric/>=4); test_042 forced-major loop and stub-bash arm" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "translation asserts at :796-808 precede the gate; test_042 fake-lib arm asserts rc=1 + 'git-bash path wrong' (mechanism is a fake PROJECT_ROOT lib, not an in-process redefinition — INFO deviation, see body)" }
      - { ac: Spec-AC-04, call: non-compliant,
          citation: "diff itself touches no .aai/ path (compliant fact), but TEST-004 as implemented (test_042 live `git diff origin/main...HEAD` arm) is a permanent suite assertion that goes red on every future branch touching .aai/ — B1; and the spec's own Verification bullet `spec-lint ... shows no errors` fails — B2" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-win-fallback.sh, line: 1474,
          issue: "TEST-004 arm asserts the CURRENT checkout's diff vs origin/main touches no .aai/ path; this is a one-ride scope fact baked into a permanent suite",
          failure_scenario: "Any later branch that edits .aai/ (e.g. .aai/scripts/lib/git-bash-path.sh or aai-run-tests.sh, exactly the files that make the selector run this suite; CI checks out with fetch-depth 0 so origin/main exists) makes test_042 fail. Reproduced: scratch clone at b28ac995, origin/main=ebc5d72b, one-line commit to .aai/scripts/lib/git-bash-path.sh -> `test-aai-win-fallback.sh 042` rc=1 'FAIL: TEST-004: diff touches a path under .aai/'" }
      - { rank: BLOCKING, file: docs/specs/SPEC-DRAFT-spec-win-fallback-test028-red-on-bash-3.md, line: 85,
          issue: "AC Status evidence cells cite docs/ai/tdd/... paths on a `direct` strategy spec; spec-lint flags strategy-evidence-mismatch and exits 1",
          failure_scenario: "`node .aai/scripts/spec-lint.mjs --path <this spec>` rc=1; aai-spec-lint real-corpus arms (TEST-009, TEST-004 delta-stage-2, TEST-005 dupac, TEST-007 stratev, TEST-004 halffrozen, TEST-005 actest, TEST-009 clarify) FAIL in this run -> CI red. Also the cited docs/ai/tdd files are gitignored, so the citation is unreachable from the PR" }
      - { rank: BLOCKING, file: tests/skills/test-aai-win-fallback.sh, line: 1480,
          issue: "test_042 final log_pass message contains the word 'skipped', which the degenerate-pass ratchet counts",
          failure_scenario: "aai-hygiene-pack test_124 FAIL: 'the degenerate-pass ratchet diverges from tests/skills/lib/degenerate-pass-baseline.tsv: NEW test-aai-win-fallback.sh 0 1' -> hygiene-pack red on every host and CI" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-win-fallback.sh, line: 1432,
          issue: "on a bash >= 4 host test_042 drives the full wrapper execution arm four times (real host + forced 4, 5, empty) plus test_028's own run",
          failure_scenario: "CI Ubuntu leg pays ~4 extra wrapper spawns for this suite; a cost, not a correctness defect" }
  cannot_verify:
    - { claim: "the bash >= 4 execution arm still prints the unchanged pass line and no SKIP line (TEST-001 else-branch, SEAM-2)",
        closes_with: "CI skill-suite Ubuntu (bash 5) run on the PR head showing 'TEST-028 Windows Python path translated in-process and executed under Git Bash' and test_042 PASS" }
  overall: fail
```

## Scope and spec
Scope `origin/main...HEAD` (ebc5d72b..b28ac995): tests/skills/test-aai-win-fallback.sh, the intake, the frozen spec (AC/Test status columns only post-freeze), docs/INDEX.md, one EVENTS doc_lifecycle line, one decisions.jsonl measurement amendment. No `.aai/` file changed. Spec: docs/specs/SPEC-DRAFT-spec-win-fallback-test028-red-on-bash-3.md (direct, ceremony 1). No coaching in the dispatch beyond the host-capability note and the gate checks it asked for, which are within scope.

## Dispatch checks
- Gate cannot skip on bash >= 4: `win_fallback_exec_arm_decision` prints `skip` only for an all-digit value `-lt 4` (:784-789). Confirmed.
- Gate cannot skip on an unreadable version: empty or non-numeric -> `run` (`''|*[!0-9]*`). Probe failure collapses to empty via `|| true`. Confirmed; exercised by test_042 (`m=""`, `decision x`, `decision ''`).
- Version read from the invoked interpreter: probe runs bare `bash -c` on the same PATH that test_028 uses for `bash "$RUN_TESTS_SCRIPT" bash "$suite"`; the wrapper's child is also the PATH `bash` (BASH_ENV sourcing, aai-run-tests.sh:806-807). Stub-bash arm proves PATH resolution. Confirmed.

## AC walk
- Spec-AC-01 compliant — local run on bash 3.2.57: `bash tests/skills/test-aai-win-fallback.sh 028 042` rc=0, SKIP line present naming 3.x, no pass line.
- Spec-AC-02 compliant — forced 3/4/5/empty and stub bash 5/3 arms.
- Spec-AC-03 compliant — fake lib under a fake PROJECT_ROOT, rc=1 with 'git-bash path wrong'. INFO deviation: the spec says aai_to_git_bash_path is "redefined"; an in-process redefinition would be overwritten by test_028's own `. "$lib"`, so the fake-lib route is the correct realisation. Not disclosed in the amendment; INFO only.
- Spec-AC-04 non-compliant as verified — the scope fact holds, but its TEST-004 realisation is defect B1, and the Verification bullet "spec-lint shows no errors" fails (B2).

## Findings
B1 (BLOCKING) tests/skills/test-aai-win-fallback.sh:1474 — live diff arm. Reproduced in a scratch clone (removed afterwards). Recommended remediation: drop the live `origin/main...HEAD` arm from the permanent suite (Spec-AC-04 is a review/validation fact about this one diff, closed by `git diff --name-only origin/main...HEAD`), or pin it to this ride's immutable commit range; either changes the TEST-004 row and needs a disclosed amendment. Keeping the positive-control helper alone would test nothing about AC-04.
B2 (BLOCKING) spec:85 — reword the AC Status Evidence cells to cite the command + exit code (and, if kept, mark the mutation observation as optional for direct), without `docs/ai/tdd/` paths; re-run spec-lint to rc=0.
B3 (BLOCKING) test_042 log_pass at :1480 — replace "skipped" in the message (e.g. "gated by name"); re-run hygiene-pack test_124.
N1 (NON-BLOCKING) four wrapper runs per test_042 on bash >= 4. Recommended disposition: accepted residual: P3 cost only, no observed bite, no false record (option d), or fold into remediation by dropping forced majors 4/5 to the decision-helper level.

## Suites run (once, as dispatched)
`env -u AAI_ROLE AAI_TEST_TIMEOUT=3000 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-win-fallback --skill aai-hygiene-pack --skill aai-spec-lint --skill aai-docs-audit` -> 2/4 pass. aai-win-fallback PASS, aai-docs-audit PASS, aai-hygiene-pack FAIL (B3), aai-spec-lint FAIL (B2). The run also reported a tripwire on docs/ai/tests/test-runs.jsonl, attributed to the concurrent Validation run in the same worktree (environmental, not this diff). Mutation replay not run (owned by Validation).

## cannot_verify
- bash >= 4 arm green and unchanged pass line — closes with the CI Ubuntu bash 5 run on the PR head.

## Next steps
Remediate B1-B3 (B1 with a disclosed TEST-004 amendment), re-run the four suites, re-review.
