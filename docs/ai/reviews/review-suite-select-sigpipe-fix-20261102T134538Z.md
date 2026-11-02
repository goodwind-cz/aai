```yaml
review:
  scope: "origin/main...cef5b5bf (worktree fix/suite-select-sigpipe-fix)"
  spec: docs/specs/SPEC-DRAFT-suite-select-sigpipe-fix.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-aai-suite-select.sh:1939-1947 (here-string + seen-flag readers); TEST-3280 PASS on macOS bash 3.2 and on Linux bash 5.2/GNU grep 3.11 (container). The behavior holds. The test's ability to catch a regression on Linux is a separate code_quality finding (B1)." }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/test-aai-suite-select.sh:1987-2032 TEST-3281; self-test of 22 probes plus a full-file scan PASS on macOS and on Linux (GNU grep, glibc regex)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "tests/skills/test-aai-suite-select.sh:1949-1966 TEST-016; every assertion and literal is unchanged, only the extraction moved into the helpers; PASS" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-suite-select.sh, line: 1971,
          issue: "TEST-3280 depends on set -e inside a command substitution that sits on the left of '||'. Bash 4+ ignores set -e in that context, so on the CI runner's bash the test cannot detect the regression it was written for.",
          failure_scenario: "Put the old early-exit reader bodies (printf | awk ...exit) back into the helpers and run TEST-3280 under bash 5.2 (Linux CI). printf prints 'write error: Broken pipe' twice, the values are still correct, the subshell keeps going, and TEST-3280 PASSES (red_rc=0). Under macOS /bin/bash 3.2 the same mutation FAILS. Minimal proof: out=\"$( set -e; false; echo after )\" || echo caught prints 'caught' on bash 3.2 and out=[after] on bash 5.2." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-select.sh, line: 2029,
          issue: "The probe-block exclusion is not anchored to one BEGIN/END pair",
          failure_scenario: "A later edit adds a comment containing '# PROBE-BEGIN' with no matching END. Every line after it is skipped, and TEST-3281 passes over a real early-closing reader." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-select.sh, line: 1992,
          issue: "The pattern does not flag 'grep -m1' / '-m 1' (another early-closing reader); it also cannot see pipelines continued onto the next line with a backslash",
          failure_scenario: "A future edit adds 'printf ... | grep -m1 x' or 'printf ... \\\\n | awk ...exit' to the suite. TEST-3281 passes, and the EPIPE flake comes back on CI." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-suite-select-sigpipe-fix.md, line: 55,
          issue: "D2 (needs ';' before exit) contradicts D3 (exit with or without ';')",
          failure_scenario: "A reader of the spec trusts D2 and expects the no-semicolon carry-forward shape to go unflagged. The spec text then disagrees with the test it governs." }
  cannot_verify:
    - { claim: "The fix removes the intermittent TEST-016 CI failure on the real GitHub runner",
        closes_with: "Several green CI runs of the suite-select leg on the PR, and no recurrence on later PRs. The branch is not pushed yet." }
    - { claim: "TEST-3281 behaves the same under the runner's awk (gawk or mawk) and on Windows/Git-Bash legs, if this suite runs there",
        closes_with: "CI legs on the PR. Linux was checked locally with Debian bash 5.2.37, GNU grep 3.11 and mawk only." }
  overall: fail
```

security_relevant: false

# Code review: suite-select-sigpipe-fix (ceremony 1)

- Scope: `git diff origin/main...HEAD` at cef5b5bf, in the worktree `/Users/ales/Projects/aai-worktrees/suite-select-sigpipe-fix`. Files: docs/INDEX.md, docs/ai/decisions.jsonl, docs/issues/ISSUE-DRAFT-suite-select-sigpipe-fix.md, docs/specs/SPEC-DRAFT-suite-select-sigpipe-fix.md, tests/skills/test-aai-suite-select.sh
- Spec: docs/specs/SPEC-DRAFT-suite-select-sigpipe-fix.md, frozen, with the disclosed contract amendment (owner sign-off owed through `fu-amend-spec-suite-select-sigpipe-fix`)
- Inputs: the intake, validation r2 (PASS) and its four non-blocking notes
- Dispatch coaching: the dispatch named three validation notes to read. These are prior artifacts, not severity ratings. I reviewed the whole scope anyway.

## AC walk
| AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | Helpers at suite:1939-1947 read all input (here-string, seen flag). On the fixed code, TEST-3280 passes on bash 3.2 (macOS) and on bash 5.2 (Debian container, no stderr). |
| Spec-AC-02 | compliant | TEST-3281 at suite:1987-2032: the self-test and the file scan pass on BSD and GNU grep. |
| Spec-AC-03 | compliant | TEST-016 at suite:1949-1966: assertions and literals are byte-identical except the three extraction calls. It passes (run 39495369884). |

Each reader matches the old one: a seen flag replaces `exit`, so only the first match is printed. The jobs and SHA pipelines keep consumers that read all input (`grep -oE`, `sort`, `awk NR==1`). The full suite is rc 0 with 83 PASS (macOS).

Deviations from the frozen spec: the disclosed amendment (an extra out-of-scope list entry, D3, and Review-By). D2 was left contradicting D3 (NB-3).

## Findings

### B1 (BLOCKING): TEST-3280 cannot catch the regression on CI bash
`out="$( set -euo pipefail; ...; r="$(_weights_header_run "$big")"; ... )" || log_fail ...` (suite:1971-1981). The subshell sits on the left of `||`. Bash 4+ (non-POSIX mode) ignores `set -e` there, even when it is set explicitly inside. Bash 3.2 does not. The old early-exit readers still return correct values, so their only failure signal is the exit status. On bash 5.2 nothing checks that status.

How I reproduced it: I ran TEST-3280 against the old reader bodies.
- macOS `/bin/bash` 3.2: `FAIL: TEST-3280 ...`, rc 1
- `python:3.11-slim` (bash 5.2.37, GNU grep 3.11, network none): two `printf: write error: Broken pipe` lines, then `PASS: TEST-3280`, rc 0

The original flake happened on the Linux runner, and that is where the test is inert. TEST-3281 still catches a revert of these exact helper bodies statically, so practical exposure is limited. But the suite's only behavioral proof of AC-01 then depends on the platform. The RED evidence in docs/ai/tdd was captured on bash 3.2.

Fix (verified on bash 5.2: the mutation then FAILS): make each reader's status explicit inside the subshell, so the check does not rely on `set -e`.
```
r="$(_weights_header_run "$big")" || exit 1
j="$(_weights_header_jobs "$big")" || exit 1
h="$(_weights_header_sha "$big")" || exit 1
```
Disposition: remediate in tree. This is a three-token edit, and the next round can recheck it as a delta.

### NB-1: the PROBE marker is not anchored
A stray `# PROBE-BEGIN` with no END after it skips the rest of the file (suite:2029). Fix: assert exactly one BEGIN line and one END line, excluding the scan line, before the scan. Or match the markers only at column `^  # PROBE-`. Disposition: remediate in tree alongside B1. It is cheap and in the same function.

### NB-2: `grep -m1` and backslash-continued pipelines are not covered
Neither is required by the wording of Spec-AC-02, and the suite has no such site today. Disposition: promote to a follow-up. Fold it into `fu-pipefail-early-readers-other-suites`, which will want the same pattern for the other suites.

### NB-3: D2 contradicts D3 (spec:55)
Disposition: remediate in tree. Reword D2 as "superseded by D3", folded into the amendment that already exists and stays unsigned. It is additive and disclosed, and it changes no AC.

## cannot_verify
1. Whether the CI flake is actually gone on the GitHub runner. The branch is unpushed; this closes with green CI on the PR.
2. The pattern under the runner's awk and any Windows/Git-Bash leg. Linux was checked locally with mawk and GNU grep only; this closes with the CI legs.

## Other checks
- `bash -n`: implicit in the suite running. docs/INDEX.md hunks match the generator output (validation r2: `--strict` rc 0).
- decisions.jsonl: append-only, five lines. `fu-suite-select-sigpipe-test016` carries the prior ride's ref_id, as filed. Nothing is rewritten.
- No gitignored artifacts in the diff (the docs/ai/tdd logs are not part of the diff).

## Next steps
Remediation fixes B1 (plus NB-1 and NB-3 if wanted). Then a delta recheck of TEST-3280 under bash 5.x and 3.2. Then PR.
