# Code review: release-checks-registration-grace

```yaml
review:
  scope: "git diff ac42210e..3307c5f9 (.aai/scripts/release-finish.mjs, tests/skills/test-aai-release.sh, docs/product/release-command-finish.md, CHANGELOG.md, docs/specs/SPEC-0234-spec-release-checks-registration-grace.md, docs/issues/ISSUE-0101-release-checks-registration-grace.md; plus generated docs/INDEX.md and docs/ai/EVENTS.jsonl)"
  spec: docs/specs/SPEC-0234-spec-release-checks-registration-grace.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/release-finish.mjs:39,358-360,365-373,453; TEST-060/TEST-061 PASS (re-run by reviewer); mutation-TEST-060/061 RED" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/release-finish.mjs:370; TEST-062 PASS; mutation-TEST-062 RED" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/release-finish.mjs:356,359-360,369,453; TEST-063 PASS (ci/skipped/odd-error, one engine read each); mutation-TEST-063 RED" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/release-finish.mjs:457 (requiredChecks() strict, allowEmpty=false); TEST-064 PASS; mutation-TEST-064 RED" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/release-finish.mjs:375 (guard before any gh call); TEST-065 PASS; mutation-TEST-065 RED" }
      - { ac: Spec-AC-06, call: compliant, citation: "docs/product/release-command-finish.md:48,54,62; TEST-066 PASS; mutation-TEST-066 RED" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-release.sh, line: 1541,
          issue: "TEST-060..TEST-066 run on RELEASE_FINISH_CASE=all as well as under their own selectors; frozen spec Implementation plan step 7 says they run ONLY when the selector equals their id",
          failure_scenario: "a full run of tests/skills/test-aai-release.sh executes each grace case twice (reviewer full run printed 14 'PASS: TEST-06x' lines for 7 cases); TEST-062/063 each spend real grace seconds per mode, doubled; a failure surfaces twice under two different test functions" }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 39,
          issue: "AAI_RELEASE_CHECKS_GRACE_SECONDS uses ?? while its siblings use ||, so an empty or whitespace-only value coerces to Number('')=0 and passes the guard as grace 0 (no grace) instead of the documented default 60 or an arguments refusal",
          failure_scenario: "operator/CI template exports AAI_RELEASE_CHECKS_GRACE_SECONDS= (empty) -> grace silently disabled -> first /aai-release --confirm refuses required-checks again exactly as before this fix (fail-closed, resume works; no false record)" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-release.sh, line: 1711,
          issue: "Spec-AC-04 names 'an empty or not-registered result' post-watch; TEST-064 (settle-empty) exercises only the empty-array shape, not gh's exit-1 'no required checks reported' shape after watch-ci",
          failure_scenario: "a future change that special-cases the gh shape inside requiredChecks() for allowEmpty=false (e.g. returning [] before the strict check) would not be caught by TEST-064; today the shared code path (release-finish.mjs:358-360) refuses both shapes identically" }
  cannot_verify:
    - { claim: "Live gh wording ('no (required )?checks reported on the '<branch>' branch') stays stable in future gh versions, and GitHub registers required checks within 60s",
        closes_with: "first live /aai-release --confirm after merge (spec residual; a wording change degrades to today's github-checks refusal, fail-closed)" }
    - { claim: "tests/skills/test-framework.sh --skill aai-release --skill aai-learned-routing still passes (spec Verification regression line)",
        closes_with: "Validation run of that command; not run by this reviewer (the release suite itself was run in full: exit 0, 3m29s)" }
  overall: pass
```

## Scope and spec

- Worktree /Users/ales/Projects/aai-fix-release-checks-registration-grace, branch fix/release-checks-registration-grace, HEAD 3307c5f9 verified; base ac42210e.
- Working tree: only `docs/ai/tests/test-runs.jsonl` modified (test-runner telemetry, outside scope).
- Frozen spec read in full. Diff read in full; out-of-list paths are the generated INDEX.md rows and one doc_lifecycle event (both expected).
- Dispatch note: the dispatch prompt listed focus areas (no severity pre-rating or exclusions). Recorded per the anti-gaming contract; the full scope was reviewed.

## Reviewer-run evidence

- Each selector test_704..test_710 via `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh <selector>`: all exit 0 with `PASS: TEST-060` .. `PASS: TEST-066`.
- Whole suite `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh`: exit 0 (includes SPEC-0233 TEST-010 refusal modes and TEST-033 PowerShell parity).
- Mutation records under docs/ai/tdd/spec-release-checks-registration-grace/: all seven verdict RED; their target_sha256 values match the current release-finish.mjs (e5069809...) and product doc (bbe79c5f...).
- RED log shows pre-change failures (e.g. TEST-060 refused `No required checks reported`).

## Correctness walk (focus points)

- Fail-closed recognition (release-finish.mjs:358): requires status 1 AND trimmed-empty stdout AND the anchored stderr phrase; anything else goes to JSON.parse and the existing `github-checks` refusal. Transport errors and statuses outside 0/1/8 are refused before recognition (356). TEST-063 odd-error proves the exit-1 path is phrase-gated.
- Empty-list handling (360): `allowEmpty` returns only a real array; a non-array JSON value (e.g. `{}`) still refuses. Status-8/status-1 consistency checks still run on non-empty lists, so a status-1 list without fail/cancel still refuses at once.
- Grace loop (365-373): deadline from Date.now() computed once; at least one read; refuse once `Date.now()>=end`; sleeps with Atomics.wait (no busy wait). The interval cannot be 0 (`||15` maps 0 to 15) and negatives are refused, so the loop is bounded by grace + interval + one gh call (gh timeout 60s). Grace 0 means exactly one read.
- Post-watch (457): still `requiredChecks()` with allowEmpty=false, so empty and not-registered both refuse `required-checks`.
- Exit codes and claims: grace refusal is a normal refuse() -> exit 20 with Completed/Resume lines (TEST-062 asserts Resume); no pending/exit-8 path changed. The run claim is pid-liveness based (no lease expiry), so a 60s blocking wait cannot lose it. On resume the grace re-runs from scratch, which is correct.
- Argument guard (375): runs before any gh call; also applies to the audit-only/dry-run path, consistent with the existing wait/poll guard.
- Regex robustness: `'[^']*'` does not bind to the record's branch; a branch containing `'` (git allows it; `validTagVersion` allows it in the version) is simply not recognized and falls back to today's `github-checks` refusal. Fail-closed; INFO only.
- Test harness check() (1541): prints `FAIL: <id>` then rethrows, so the node process still exits nonzero; no masking. (A thrown `null` would raise TypeError inside the catch; still nonzero. INFO.)
- Tests prove behavior: transport call counts separate engine reads (`--repo`) from watch-ci reads, so hand-off to the real watch-ci.mjs and zero merges are asserted, not mocked.

## Deviations from the frozen spec

1. Implementation plan step 7: new cases are not excluded from `all` (NB-1). Not an AC row; behavior unaffected.

No other deviation found: the literal mutation anchors (`AAI_RELEASE_CHECKS_GRACE_SECONDS??60`, `checksGrace<0`, `if(c.length)return c;`, `no (required )?checks reported`, `const settled=requiredChecks();`) are present verbatim; SKILL_RELEASE.prompt.md untouched; fixture grace 0.2 added as planned.

## INFO (non-gating)

- tests/skills/test-aai-release.sh:1898: the comment "Native capture is tested independently..." now sits above test_704 instead of test_701.
- Optional hardening: match the stderr branch against `record.branch` for exactness.

## Warning dispositions (recommended; orchestrator records)

- NB-1 (test double-run, plan step 7 deviation): remediate-in-tree (skip TEST-060..066 when selected==='all'), or if the owner prefers keeping coverage on `all`: accepted residual: P3 maintenance cost, no observed bite, no false record.
- NB-2 (empty env value disables grace): promote-to-follow-up ref (P3, e.g. fu-release-grace-empty-env); fixing it changes a spec mutation anchor (`??60`), so it needs a spec amendment rather than an in-tree tweak.
- NB-3 (AC-04 gh-shape post-watch untested): accepted residual: P3 assurance-strength gap; shared code path refuses both shapes today, no observed bite, no false record.

## Next steps

- Orchestrator records the three dispositions, then Validation (including the learned-routing regression suite).
