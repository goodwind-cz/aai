```yaml
review:
  scope: "origin/main...e6273074 (worktree fix/suite-select-sigpipe-fix); re-pass after remediation cef5b5bf..e6273074"
  spec: docs/specs/SPEC-0269-spec-suite-select-sigpipe-fix.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-aai-suite-select.sh:1939-1947 helpers; TEST-3280 at :1968-1987 with explicit '|| exit 1' (:1979-1981). On scratch copies: fixed readers PASS on bash 3.2.57 and on Debian bash 5.2.15; main's early-exit readers FAIL on both; the control (old readers, no '|| exit 1') still PASSES on bash 5.2. Evidence: docs/ai/reports/val-sigpipe-r3/b1-bash32.log, b1-bash5.log" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-3281 at :1989-2038 PASS; marker-pair assertion :2031-2034 fails on doubled, stray-exact or extra-END markers (docs/ai/reports/val-sigpipe-r3/nb1.log); residual NB-A below" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-016 :1949-1966 unchanged since cef5b5bf; full suite rc 0, 83 PASS (docs/ai/reports/val-sigpipe-r3/suite-select.log)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-select.sh, line: 2035,
          issue: "The marker count is anchored to '^  # PROBE-BEGIN$', but the skip awk still matches '/# PROBE-BEGIN/' anywhere on a line. A marker that is not in the exact form is not counted, and it still turns skipping on.",
          failure_scenario: "Append '# PROBE-BEGIN' at column 0 (or 'x=1  # PROBE-BEGIN later') and then 'x=$(printf a | awk \"/a/ {exit}\")'. TEST-3281 PASSES (rc 0) and the reader stays hidden. Anchoring the skip awk to /^  # PROBE-BEGIN$/ and /^  # PROBE-END$/ makes the same mutation FAIL, and the clean suite still PASSES (nb1.log)." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0269-spec-suite-select-sigpipe-fix.md, line: 56,
          issue: "The reworded D2 says END {exit ...} is not flagged 'for the semicolon and no-semicolon shapes alike'. The semicolon branch of the pattern does flag an END block that has a statement before exit.",
          failure_scenario: "A reader trusts D2 and writes 'x | awk \"{n++} END {print n; exit}\"'. TEST-3281 flags it (d2.log). The failure is loud, but the spec text does not describe what the guard compares." }
  cannot_verify:
    - { claim: "The fix removes the intermittent TEST-016 CI failure on the real GitHub runner",
        closes_with: "Green CI legs on the PR (carry ci-full for the lightweight-lane pre-merge full-suite proof) and no recurrence afterwards" }
    - { claim: "TEST-3281 and TEST-3280 behave the same under the runner's awk (gawk or mawk) and on any Windows/Git-Bash leg",
        closes_with: "PR CI legs. Locally checked: macOS bash 3.2 with BSD tools, and Debian bookworm bash 5.2.15 with mawk and GNU grep" }
  overall: pass
```

security_relevant: false

# Code review re-pass: suite-select-sigpipe-fix (ceremony 1)

- Scope: `git diff origin/main...HEAD` at e6273074 (merge-base 9717801a). Files: docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/ai/decisions.jsonl, docs/ai/reviews/review-suite-select-sigpipe-fix-20261102T134538Z.md, docs/issues/ISSUE-0108-suite-select-sigpipe-fix.md, docs/specs/SPEC-0269-spec-suite-select-sigpipe-fix.md, tests/skills/test-aai-suite-select.sh
- Spec: docs/specs/SPEC-0269-spec-suite-select-sigpipe-fix.md, frozen. The two disclosed contract amendments (13:30:57Z and 13:48:32Z) are unsigned and tracked by `fu-amend-spec-suite-select-sigpipe-fix` (open). `spec-amend list --strict` returns rc 0.
- Inputs: the prior review (cef5b5bf, fail), validation r3 (PASS, docs/ai/reports/VALIDATION-suite-select-sigpipe-fix-r3.md)
- Dispatch coaching: the dispatch summarized what the remediation claims to have done for B1, NB-1, NB-2 and NB-3. It did not rate severity or exclude any area. I treated those claims as things to refute and reviewed the full scope.

## Prior findings: dispositions

| Finding | Claimed | Verified |
|---|---|---|
| B1 (BLOCKING) | `\|\| exit 1` on the three TEST-3280 assignments | **Closed.** Reproduced: old readers FAIL on bash 3.2 and 5.2. The control without `\|\| exit 1` still PASSES on 5.2, which shows the edit is what closes it. |
| NB-1 | assert exactly one PROBE-BEGIN/END pair | **Partly closed.** Exact-form stray, doubled or extra markers now FAIL. A non-exact marker still hides lines (NB-A). |
| NB-2 | disclosed in the spec out-of-scope list | **Closed as disclosure.** The spec text names `grep -m1` / `-m 1` and backslash-continued pipelines. `fu-pipefail-early-readers-other-suites` does not mention them, so the fold the review proposed did not happen. Disposition (d), quoted below. |
| NB-3 | D2 reworded through spec-amend | **Closed for the contradiction.** D2 no longer contradicts D3, but the new wording overclaims (NB-B). |

## AC walk
| AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | helpers :1939-1947 read all of their input; TEST-3280 now checks reader status explicitly and catches the regression on both bash 3.2 and 5.2 |
| Spec-AC-02 | compliant | TEST-3281 PASS; self-test of 22 probes plus a file scan; marker pair asserted |
| Spec-AC-03 | compliant | TEST-016 assertions are byte-identical to main except the three extraction calls; PASS |

Deviations from the frozen spec: only the disclosed amendments (out-of-scope list growth, D3, Review-By, D2 rewording, known-limits line). No AC wording changed.

## Findings

### NB-A: the skip awk is not anchored like the count (tests/skills/test-aai-suite-select.sh:2035)
The count checks `^  # PROBE-BEGIN$`. The skip awk triggers on `/# PROBE-BEGIN/` anywhere. The NB-1 failure scenario therefore still applies to any marker that is not in the exact form. Fix (one line, verified on a copy): `awk '/^  # PROBE-BEGIN$/{skip=1} !skip{...} /^  # PROBE-END$/{skip=0}'`. The scan line itself, which contains both marker strings, is then scanned too. Its only pipe goes into `grep -E` with no `-q`, so it is not flagged; the clean suite still PASSES.
Recommended disposition: remediate in tree (same function, one token class). Alternatively, promote it to a follow-up.

### NB-B: D2 overclaims (spec line 56)
`END {exit 1}`, `END{exit 1}` and `{n++}; END {exit n>0}` are not flagged. `END {print n; exit}`, `END {n=1;exit}` and `END {if (n) {print n; exit 1}}` are flagged by the `awk[^|]*;[[:space:]]*exit` branch. Better wording: "an `exit` that opens the END block is not flagged". A false positive fails loudly, so nothing is hidden. But the spec text would leave a false record of what the guard compares, so disposition (d) is not available.
Recommended disposition: remediate in tree (reword in the existing unsigned amendment's lane), or promote to a follow-up.

## Warning dispositions (H6)
- NB-A: remediate-in-tree recommended; otherwise a follow-up (e.g. `fu-suite-select-probe-marker-anchor`, suggested, not filed).
- NB-B: remediate-in-tree recommended; otherwise a follow-up. Not eligible for accepted residual, because it leaves a false record.
- Prior NB-2: accepted residual: P3 assurance-strength limit of a single-line scan (grep -m1, backslash continuation), with no such site in the suite, no observed bite, and the limit disclosed in the frozen spec's out-of-scope list, so no false record.

## Other checks
- `bash -n` rc 0. Full suite rc 0, 83 PASS. Selected + CORE suites rc 0 (validation r3).
- EVENTS.jsonl and decisions.jsonl: the merge-base bytes are a byte-exact prefix at HEAD (append-only).
- docs/INDEX.md matches the generator (`--strict` rc 0, no diff).
- `git ls-files -ci --exclude-standard`: empty.
- Here-strings: bash writes oversized here-strings to a temp file rather than a pipe, so the helpers have no writer that can EPIPE.

## Next steps
Optionally fold NB-A and NB-B in tree (a one-line test edit plus a D2 rewording, recheckable as a delta), or file follow-ups. Then open the PR with `ci-full`, and get the owner's sign-off on `fu-amend-spec-suite-select-sigpipe-fix`.
