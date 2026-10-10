```yaml
review:
  scope: "b28ac995..034888d4 (round-2 delta) plus regression over origin/main(ebc5d72b)...HEAD(034888d4)"
  spec: docs/specs/SPEC-DRAFT-spec-win-fallback-test028-red-on-bash-3.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-aai-win-fallback.sh:811-815 gate + :1417-1426 TEST-001; suite 028 042 rc=0 on bash 3.2 prints SKIP line" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/test-aai-win-fallback.sh:778-790 helpers; :1430-1454 forced majors 3/4/5/empty + stub PATH bash; bash>=4 arm proven only by CI (cannot_verify)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "tests/skills/test-aai-win-fallback.sh:1457-1465 TEST-003 broken lib -> rc=1 on skip branch" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "read once now: git diff --name-only origin/main...HEAD = docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/ai/decisions.jsonl, docs/ai/reviews/review-...-20261010T065624Z.md, docs/ai/tests/test-runs.jsonl, intake, spec, tests/skills/test-aai-win-fallback.sh; no .aai/ path. Verification text amended (contract, unsigned, fu-amend-win-fallback-test028-red-fa32f7)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-win-fallback.sh, line: 1413,
          issue: "test_042 announces '... translation asserts precede the gate; no .aai/ change...' but round-1 remediation removed the only assertion of that property; the test's announced description now claims a universal negative it does not assert at all",
          failure_scenario: "any later branch that edits .aai/ runs the suite: the log prints 'no .aai/ change...' then 'PASS: TEST-042 ...', so a CI log reader (or sweep) reads an attestation that no .aai/ file changed while the branch did change one. Same class as round-1 B3 (log line claiming behaviour the test does not prove) and the reviewer contract's universal-negative test-name rule. Fix: drop '; no .aai/ change' or say '.aai/ path checker positive control'" }
  cannot_verify:
    - { claim: "bash>=4 execution arm still passes byte-for-byte (Spec-AC-02 run branch, Spec-AC-01 else-branch of TEST-001)",
        closes_with: "CI skill-suite run (Ubuntu bash 5) on the PR head printing 'TEST-028 Windows Python path translated in-process and executed under Git Bash' and no SKIP: TEST-028 line" }
    - { claim: "mutation cells TEST-001..004 still kill after 8e556c9b (TEST-004 now kills only via the positive control)",
        closes_with: "validation's mutation-run replay (owned by concurrent Validation per dispatch; not run here)" }
  overall: fail
```

# Code Review round 2 — win-fallback-test028-red-on-bash-3

- Scope: delta `b28ac995..034888d4` (remediation commit 8e556c9b + round-1 report commit 034888d4) plus regression over `origin/main...HEAD`. Worktree `/Users/ales/Projects/aai-fix-win-fallback-test028-red-on-bash-3`, HEAD 034888d4, base ebc5d72b.
- Spec: `docs/specs/SPEC-DRAFT-spec-win-fallback-test028-red-on-bash-3.md` (frozen, amended: one measurement record 06:50:52Z, one unsigned contract record 06:58:04Z tracked by `fu-amend-win-fallback-test028-red-fa32f7`, open).
- Dispatch coaching check: dispatch named round-1 blockers and their remediation (context, not severity pre-rating) and delegated the mutation replay to Validation; no scope exclusion of review areas. Full scope reviewed.

## Round-1 blockers re-checked
- B1 (live `git diff origin/main...HEAD` arm reddening future .aai branches): removed (test-aai-win-fallback.sh:1467-1473 now positive control only). Resolved.
- B2 (spec-lint strategy-evidence mismatch): `node .aai/scripts/spec-lint.mjs --path <spec>` -> LINT PASS, 0 findings. Resolved.
- B3 (test_042 log_pass said 'skipped'): log_pass reworded (:1473); aai-hygiene-pack PASS. Resolved. The sibling log_info line (:1413) was not updated in the same pass; see finding below.

## AC table walk
See yaml block. All four ACs compliant. Spec-AC-04 read once now: no `.aai/` path in `git diff --name-only origin/main...HEAD`. Deviation list: (1) TEST-004 mutation expression differs from Test Plan cell (disclosed, measurement amendment); (2) Spec-AC-04 Verification and TEST-004 description changed post-freeze (disclosed, contract amendment, owner sign-off owed at the merge checkpoint); `spec-amend list --strict` rc=0, classifies it `unsigned-tracked`.

## Findings
- BLOCKING tests/skills/test-aai-win-fallback.sh:1413 — the log_info line still announces "no .aai/ change". Failure scenario in the yaml block. Fix in tree: reword the log_info line. One line, no behaviour change.
- INFO (no failure mode): `win_fallback_aai_paths` (:1401-1410) is now used only by its own positive control. It is kept so the TEST-004 mutation cell has a target. Not gating.
- INFO: the run below printed `AAI-TRIPWIRE FAIL ... M docs/ai/tests/test-runs.jsonl`. This is the framework's own run-ledger append (one new `skill_test` line, run_id test-20261010-070123), the same shape as the already-committed lines, not a suite writing PROJECT_ROOT. Wrapper rc=0.

## Evidence
- `env -u AAI_ROLE bash tests/skills/test-aai-win-fallback.sh 028 042` -> rc=0, SKIP line for bash 3.x, PASS TEST-042.
- `env -u AAI_ROLE AAI_TEST_TIMEOUT=3000 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-win-fallback --skill aai-hygiene-pack --skill aai-spec-lint --skill aai-docs-audit` -> rc=0, 4/4 PASS (spec-lint 32s, win-fallback 36s, hygiene-pack 65s, docs-audit 118s).
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-win-fallback-test028-red-on-bash-3.md` -> rc=0 LINT PASS.
- `node .aai/scripts/spec-amend.mjs list --strict` -> rc=0.

## cannot_verify
See yaml block: the bash>=4 arm can only be checked in CI. The mutation replay is owned by Validation.

## Warning dispositions
No NON-BLOCKING findings. The BLOCKING finding must be remediated in tree.

## Next steps
Reword :1413 (for example "...translation asserts precede the gate; .aai/ path checker positive control..."), rerun `test-aai-win-fallback.sh 028 042` and the hygiene-pack suite, then do a round-3 re-review of that one-line delta.
