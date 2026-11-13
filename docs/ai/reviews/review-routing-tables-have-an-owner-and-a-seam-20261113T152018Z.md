# Code Review: routing-tables-have-an-owner-and-a-seam (round 2 of 2)

```yaml
review:
  scope: "git diff origin/main...HEAD (dee62b53) over code_review.scope + tests/skills/test-aai-harness-shims.sh"
  spec: docs/specs/SPEC-0289-spec-routing-tables-have-an-owner-and-a-seam.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "MODEL_ROUTING.yaml:122-132 routing_meta; TEST-3660 green" }
      - { ac: Spec-AC-02, call: compliant, citation: "table-freshness.mjs checkTables; TEST-3661 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "table-freshness.mjs readMarker + validateMarker (future rule); TEST-3662 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "aai-doctor.mjs catRoutingTables; TEST-3663 (adds unreadable-table WARN case), TEST-3664; sweep test-20261113-145745" }
      - { ac: Spec-AC-05, call: compliant, citation: "table-freshness.mjs stampGuard uses validateMarker(head, now); TEST-3665 future + one-day boundary cases; repro-cr1-future-stamp-passes-guard.sh exit 0 (not reproduced)" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-3666 live guard vs origin/main merge-base green at HEAD" }
      - { ac: Spec-AC-07, call: compliant, citation: "routedCheck unchanged; TEST-3667 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3668 derives --since from routing_meta date (2026-11-13 at HEAD), empty TEST_3668_ALLOW_STALE; TEST-3669 green" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-3670; sweep green" }
      - { ac: Spec-AC-10, call: compliant, citation: "ROUTING_REFRESH.routine.md step 2/3 reworded; TEST-3671 (sweep + val3-suite-routine.log)" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-3672" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-3673" }
      - { ac: Spec-AC-13, call: compliant, citation: "CHANGELOG.md; TEST-3675/3676" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "refreshed ids and list prices match the vendor pages", closes_with: "an independent re-read of the URLs in refresh-record.md" }
    - { claim: "live stamp-guard (TEST-3666) is green on the PR merge-commit checkout and post-merge main/nightly", closes_with: "green skill-suite CI run on the PR head and the first post-merge main run" }
    - { claim: "ROUTING_REFRESH run by a scheduled agent reads only primary sources and stops in a downstream install", closes_with: "the owner's TEST AT CREATION run (R2)" }
    - { claim: "aai-sync.ps1 core profile delivers table-freshness.mjs", closes_with: "pwsh run of TEST-3673 or the install-path parity suite (R7)" }
  overall: pass
```

security_relevant: false

## Scope

- Diff: `git diff origin/main...HEAD`. HEAD is `dee62b53`, three commits. The remediation commit `dee62b53` is reviewed in full against the r1 findings.
- Spec: the frozen `SPEC-0289-spec-routing-tables-have-an-owner-and-a-seam.md`.
- Dispatch note: the dispatch named the r1 findings and listed focus areas. It did not pre-rate anything. I reviewed the full scope.
- What I ran at HEAD:
  - `test-aai-pricing.sh` through aai-run-tests: rc 0, all cases PASS (TEST-3660..3670).
  - Both r1 repros: exit 0, NOT REPRODUCED.
  - A scratch probe of new edges: `scratchpad/cr2/probe.sh`.
- I did not re-run the full sweep. It was green at this HEAD (test-20261113-145745).

## Closure of r1 findings

- **B1, closed at the cause.** `validateMarker(text, kind, now)` is now the single validity definition. `checkTables` uses it, and so does `stampGuard`, for both the head and the base marker.
  - A future head stamp now gives `VIOLATION invalid head marker: future last_updated_utc`, exit 1.
  - A stamp exactly one day ahead still passes. The rule is `>` DAY_MS in both places.
  - A base that already carries a future stamp is INVALID, so it "imposes no ordering" (D-GUARD). The correcting PR therefore passes as RESTAMPED (probe A). The r1 dead-end ("lowered", forever) is gone.
  - Clock dependence is limited to stamps more than 24 h ahead of the clock. Every TEST-3665 future case pins `--now`. The live TEST-3666 runs on the shipped past stamp.
- **NB1, closed.**
  - `gitShow` returns null only when `git ls-tree` exits 0 with empty output, meaning the path is genuinely absent. Probes B and C confirm this, including a sibling `MODEL_ROUTING.yaml.bak`: no prefix match.
  - Any ls-tree or show failure throws GitError, which gives exit 2.
  - The blobless-offline repro now exits 2, and the full clone exits 1.
  - TEST-3665 deletes the base blob and asserts RC=2 plus `git show failed`.
- **NB2, closed.**
  - TEST-3668 reads `--since` from the `routing_meta` `last_updated_utc` date. The awk anchor `^  last_updated_utc:` matches only line 131. Comment lines start with `#`.
  - The test takes an explicit `TEST_3668_ALLOW_STALE` array, allows ALLOWED only when the array is non-empty, and still fails on ALLOW-UNUSED. A verified id therefore has to leave the list.
  - Step 2 of the routine now names that array.
  - Empty-array handling holds under bash 3.2 with `set -u` (checked).
- **NB3, closed.**
  - `checkTables` catches the read error and reports `INVALID <file> unreadable (<code>)`. The CLI `check` exit is 1 (probe F).
  - The doctor falls back on RangeError only, which is the horizon override. Any other error is a WARN.
  - TEST-3663 asserts `CAT-21 WARN … PRICING.yaml … unreadable` with rc 0.
- **INFO, fixed.** The stale `claude-sonnet-5` comment in MODEL_ROUTING.yaml now reads `claude-sonnet-5-5`.

## Deviations from the frozen spec

These are additive and fail closed. None of them changes an AC call. Recommended disposition: disclose them in the PR body or as an additive spec-amend record. The orchestrator decides which.
1. `stamp-guard` accepts `--now <ISO>`. The D-CLI does not list this flag.
2. `stamp-guard` exits 2 when git cannot read a table at a resolvable base. D-CLI exit 2 covers only "usage error or a base git cannot resolve".
3. `check` reports an unreadable table as `INVALID … unreadable (<code>)`. That reason is not in D-READ's list.
4. TEST-3668 derives `--since` from the stamp date instead of the literal `2026-11-13` that Spec-AC-08 names. The two are equal at HEAD, and later refreshes can only be stricter.

## Findings

No BLOCKING or NON-BLOCKING findings.

### INFO (never gates)
- **Nested install root.** `stamp-guard` with `--root` set to a subdirectory of a repository now exits 2. The ls-tree call resolves the path relative to the cwd, but `git show <rev>:<path>` resolves it from the top level (probe D). Before this change the same setup silently passed. This tool runs upstream only, and it now fails closed.
- **Head table is a directory.** `stamp-guard` throws an uncaught EISDIR stack trace and exits 1 (probe F). That is fail-closed and pre-existing; only the message is unfriendly.
- **Unreachable doctor branch.** The doctor's non-RangeError branch is effectively unreachable now that `checkTables` catches read errors. It is harmless and untested.

## Next steps
Both verdicts pass. Proceed to the PR. Carry the deviation disclosure above and the cannot_verify items, which need CI and the owner's routine test-at-creation run.
