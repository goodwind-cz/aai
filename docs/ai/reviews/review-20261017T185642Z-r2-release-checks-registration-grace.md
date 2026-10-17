# Code review r2: release-checks-registration-grace (remediation delta)

```yaml
review:
  scope: "git diff 7922cb1c..fccff841 (.aai/scripts/release-finish.mjs, tests/skills/test-aai-release.sh, docs/product/release-command-finish.md, docs/ai/decisions.jsonl)"
  spec: docs/specs/SPEC-0234-spec-release-checks-registration-grace.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/release-finish.mjs:39-41 (unset -> '60' via ??60; blank -> 60); TEST-060 (unset plus '', '   ', '\\t ') PASS; mutation-TEST-060 RED, gate PASS" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-062 PASS (now also explicit grace 0 = exactly one engine read, test-aai-release.sh:1710-1711); mutation-TEST-062 RED" }
      - { ac: Spec-AC-03, call: compliant, citation: "logic unchanged in delta; TEST-063 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-064 PASS for settle-empty and new settle-gh (gh exit-1 'no checks reported' shape post-watch, test-aai-release.sh:1466,1723-1724); mutation-TEST-064 RED" }
      - { ac: Spec-AC-05, call: compliant, citation: "release-finish.mjs:41,377; TEST-065 PASS for -1, abc, NaN, Infinity, 1e400, 1,5, 0x10; mutation-TEST-065 RED. Blank-means-default and plain-decimal-only are disclosed by the 2026-10-17T18:40:39Z spec_amendment" }
      - { ac: Spec-AC-06, call: compliant, citation: "docs/product/release-command-finish.md:54; TEST-066 PASS; mutation-TEST-066 RED" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 2165,
          issue: "spec_amendment 'what' lists 'TEST-060/064/065 extended' but the delta also extends TEST-062 (explicit-0 one-read arm, folded in by fccff841 after the record was written); the frozen Test Plan descriptions for TEST-064 (settle-empty only) and TEST-065 ('-1 and abc') also now understate the tests",
          failure_scenario: "the owner signing fu-amend-release-checks-registrat-c77eb7 reads the amendment as the complete list of contract-test changes and does not see that TEST-062 now pins 'explicit 0 = exactly one read' as tested behavior; incomplete, not false (explicit 0 is named in the same record's text)" }
  cannot_verify:
    - { claim: "Live gh wording and GitHub registration latency (unchanged from r1)",
        closes_with: "first live /aai-release --confirm after merge; wording drift falls back to the github-checks refusal (fail-closed)" }
    - { claim: "tests/skills/test-framework.sh --skill aai-release --skill aai-learned-routing still passes on fccff841",
        closes_with: "Validation run of that command; this reviewer ran the release suite in full (rc 0) and the changed selectors only" }
  overall: pass
```

## Scope and preflight

- Worktree /Users/ales/Projects/aai-fix-release-checks-registration-grace, branch fix/release-checks-registration-grace, HEAD fccff841 verified. `git status --porcelain` clean before the review.
- Delta commits: f4d5d7ca (fix), 322658dd (follow-up closures), fccff841 (TEST-062 folded into one check()).
- Dispatch note (anti-gaming contract): the dispatch named focus areas (parser, anchors, tests, doc, amendment) without pre-rating severity or excluding scope. Recorded; the whole delta was reviewed.

## Reviewer-run evidence

- Full suite `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh`: rc 0, `ALL TESTS PASSED`. Exactly 7 `PASS: TEST-06x` lines (r1 saw 14), so each grace case now runs once, via its own bash selector (plan step 7 met).
- Selectors test_704, test_706, test_708, test_709, test_710: each printed its PASS line.
- `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0234-...`: `GATE PASS: 7 row(s) satisfied degraded=0 unstamped=0 uncomparable=0` (records refreshed 20:40 against the new engine bytes).
- `node .aai/scripts/spec-amend.mjs list --strict`: rc 0; both amendments for this ref are `unsigned-tracked` under fu-amend-release-checks-registrat-c77eb7 (open). Spec frozen_sha256 unchanged in the delta (the amendment is ledger-only, spec body untouched).
- Parser probe (same expression run under node): unset -> 60; '' / ' ' / '\t ' -> 60; '0' -> 0; '-0' -> -0 (accepted as 0, prints `0s`); '+5', '1.', '.5', ' 5 ' -> accepted; '.', '-', '1e3', '0x10', 'Infinity', '5s', '1_000', '0b1', full-width digit -> NaN -> `arguments` refusal; '-1' passes the regex and is refused by `checksGrace<0`; a 400-digit string -> Infinity -> refused by `!Number.isFinite`.

## Correctness walk

- Parser (release-finish.mjs:39-41): fail-closed. Anything that is not empty-after-trim and not a plain ASCII decimal becomes NaN and is refused by the unchanged guard at :377 before any gh call. `\d` without the `u` flag is ASCII-only. No new path accepts a value the old code refused, except blank (which the amendment discloses: it now means 60 instead of silently 0).
- Explicit 0 stays one read: '0' matches the regex -> 0 -> end=now, one read, refuse `within 0s`; asserted by TEST-062 (:1710-1711).
- Mutation anchors still bind to live code:
  - `AAI_RELEASE_CHECKS_GRACE_SECONDS??60` is the live unset path: `String(undefined??60)` = '60' -> 60. Mutating to `??0` yields grace 0 on unset, which breaks TEST-060's unset arm. Not dead text. (INFO: the anchor is now semantically redundant with the `''?60` branch, since `??''` would behave the same; it is still exercised and still bites.)
  - `checksGrace<0` is live: '-1' passes the regex, so only this comparison refuses it; mutation to `<-1` accepts -1 and TEST-065 bites.
  - The new `graceRaw===''?60` default has no Mutation cell, but TEST-060's blank loop would fail under `''?0` (grace 0 -> one read -> refusal). Covered by test, not by a recorded mutation; acceptable.
- TEST-064 settle-gh (:1466): first `--repo` read passes, every later `--repo` read emits the gh not-registered bytes with exit 1; asserts one `required-checks` refusal, exactly 2 engine reads, watch-ci reads >= 1, zero merges. Closes r1 NB-3.
- check() filter (:1542-1543): `selected==='all'` now skips TEST-060..066; selectors still run them. A failure still prints FAIL and rethrows. Closes r1 NB-1.
- Product doc (:54): matches behavior exactly (unset or blank -> 60, explicit 0 -> one read, non-plain-decimal -> `arguments`).
- Follow-up closures (decisions.jsonl:2166-2167) cite f4d5d7ca, which does contain both fixes (the TEST-062 fold in fccff841 only merges two blocks with the same id).

## Amendment record vs actual change

decisions.jsonl:2165 (2026-10-17T18:40:39Z, contract class, owner_signoff false, tracked_by fu-amend-release-checks-registrat-c77eb7): blank/whitespace -> 60, explicit 0 valid, plain decimals only with 0x10/1e400/Infinity/NaN refused, step 1 statement now `graceRaw` with `??60` preserved, TEST-060..066 run only under their own selectors. All verified against the code and tests. The one gap is NB-1 below (TEST-062 extension and Test Plan descriptions not named).

## INFO (non-gating)

- Sibling variables AAI_RELEASE_WAIT_SECONDS / AAI_RELEASE_POLL_SECONDS still use `Number(x||default)` and accept hex/exponent; the stricter parser applies only to the grace variable. Out of this scope.
- '-0' is accepted as a zero grace; harmless.

## Warning dispositions (recommended; orchestrator records)

- NB-1 (amendment omits the TEST-062 extension; Test Plan descriptions understate TEST-064/065): accepted residual: P3 record-completeness gap, the owner sign-off on fu-amend-release-checks-registrat-c77eb7 is still open and can read this report; or remediate by appending a short addendum note to the same tracked item before sign-off.

## Next steps

- Orchestrator records the NB-1 disposition and runs set-code-review (command returned to the dispatcher).
- Validation re-runs the test-framework regression line named in cannot_verify.
