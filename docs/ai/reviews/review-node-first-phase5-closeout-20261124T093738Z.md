# Code review: node-first-phase5-closeout (L3, delta recheck of review round 1)

security_relevant: true

```yaml
review:
  scope: "git diff 0c9ba67a..b315e492 (b3e9295d, f8c82711 and the EVENTS-only commits 9ecc17c3, 4194a7b5, b315e492); delta recheck of review r1 (0ff18d63..0c9ba67a)"
  spec: docs/specs/SPEC-0311-spec-node-first-phase5-closeout.md (frozen, plus the spec_amendment records of ref node-first-phase5-closeout); docs/specs/SPEC-0310-spec-sync-on-node.md for TEST-4021 and TEST-4022
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-4024 PASS (reviewer full-suite run on a scratch clone at b315e492); delta does not touch its paths" }
      - { ac: Spec-AC-02, call: compliant, citation: "tests/skills/lib/script-classes.mjs:83-152 adds readers only, strictProblems unchanged; script-classes.mjs strict --root rc 0; hygiene test_4025_kept_native_gate_and_bite PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "delta touches CHANGELOG.md:37 only (N2 sentence); code unchanged since r1; aai-release.test.mjs:677 covers -DryRun $false" }
      - { ac: Spec-AC-04, call: compliant, citation: "unchanged since r1 (r1 citation); delta does not touch .aai/scripts" }
      - { ac: Spec-AC-05, call: compliant, citation: "unchanged since r1; hosted ps1-quality 45359846557 attempt 2 success on f8c82711 (gh run view)" }
      - { ac: Spec-AC-06, call: compliant, citation: "unchanged since r1 (r1 citation)" }
      - { ac: Spec-AC-07, call: compliant, citation: "unchanged since r1 (r1 citation)" }
      - { ac: Spec-AC-08, call: compliant, citation: "unchanged since r1; root-cause clause waived by owner (hitl_decision 2026-11-23T17:26:32Z); D-ALLOW deviation still undisclosed, see deviation 5" }
      - { ac: Spec-AC-09, call: compliant, citation: "unchanged since r1 (r1 citation)" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-4033 and TEST-4022 PASS; section 7 file table equals the live measurement incl. code lines at b315e492 (reviewer probe); count/latest narrowing disclosed by amendments 2026-11-23T22:52:31Z, 22:52:43Z, 2026-11-24T08:38:55Z" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-4034 and TEST-4021 PASS; record-based readers disclosed by amendments 2026-11-23T22:52:31Z and 2026-11-24T08:39:01Z" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-4035 PASS (33 launchers, 17 ps1) in the reviewer full-suite run" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-4036 PASS; tests/skills/test-aai-phase5-closeout.sh:487-489 accepts [unreleased] or [vYYYY.MM.DD]; spec-amend list --strict rc 0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/lib/script-classes.mjs, line: 30,
          issue: "fileTableProblems never compares code-line counts, also not for the LATEST re-measure section (TEST-4022 is the live guard of the latest section); the counts column of every future re-measure record is unchecked by any test",
          failure_scenario: "a later ride writes section 8 with aai-run-tests.sh at 999 code lines (actual 540): TEST-4022 and TEST-4033 both exit 0 (reviewer probe 'later section 8 (and section 7 count edited)'). Today's section 7 counts equal the measurement exactly, so no false record exists now; disclosed by the 22:52:43Z SPEC-0310 amendment" }
      - { rank: NON-BLOCKING, file: tests/skills/lib/script-classes.mjs, line: 54,
          issue: "recordsThroughDate folds the ledger through the END of the record date, so a follow-up record dated on or before 2026-11-23 that reaches main later (a parallel branch union-merged after this PR) still changes the as-of state",
          failure_scenario: "a branch that filed a P2 follow_up under a node-first* or plan ref with ts 2026-11-23T12:00:00Z merges after this PR: TEST-4033 and TEST-4022 fail on that branch's PR with 'the section 7 follow-up table differs from the ledger as of 2026-11-23' (reviewer probe). No carrier exists today: the only unmerged branches (origin/codex/singleton-reservation-portability, origin/docs/hermes-trust-after-update) carry no in-scope follow-up record; new writes carry the current ts and cannot enter the window" }
  cannot_verify:
    - { claim: "The final head b315e492 is green on the hosted runners (it adds EVENTS.jsonl lines only on top of f8c82711, whose ps1-quality 45359846557 attempt 2 and skill-suite 45359851798 concluded success; the skill-suite log shows aai-phase5-closeout PASS)", closes_with: "the pull request's ps1-quality and skill-suite runs on its final head (D-HOSTED step 5)" }
    - { claim: "ps1-quality 45359846557 attempt 1 failure is an unrelated CAT-14 doctor selftest case under pwsh 7 (dispatcher statement; the reviewer read only attempt 2's conclusion)", closes_with: "gh run view 45359846557 --attempt 1 --log-failed read against the delta paths" }
    - { claim: "The dispatch prompt hash 8e6aae0d... names the assembled payload; the canon file read hashes to 439064541433be5b...", closes_with: "the orchestrator's payload hash recipe applied to canon-review2.txt plus the scope section" }
  overall: pass
```

## Scope and preflight

- Worktree /Users/ales/Projects/aai-worktrees/node-first-phase5-closeout, branch chore/node-first-phase5-closeout, HEAD b315e492 (origin at f8c82711; b315e492 adds EVENTS.jsonl lines only). `git status --porcelain`: ` M docs/ai/EVENTS.jsonl` only, outside the reviewed code.
- Delta: `git diff 0c9ba67a..HEAD`, 10 files: CHANGELOG.md, docs/INDEX.md (date line), EVENTS.jsonl, decisions.jsonl (5 amendments, 1 fu-amend filing), the r1 report and its two repro scripts, tests/skills/lib/script-classes.mjs, tests/skills/test-aai-phase5-closeout.sh, tests/skills/test-aai-sync-docs.sh.
- Dispatch: it named check areas and the r1 findings by id. It did not pre-rate severity or predict findings. The line "the owner stops the ride on any new BLOCKING finding" was read as a consequence statement, not coaching. Full delta reviewed.
- Validation r5 PASS report read for context only.

## Prior findings (r1)

| Id | Status | Evidence observed this round |
|---|---|---|
| B1 (TEST-4036 release roll) | fixed | r1 repro-B1.sh on a scratch clone of b315e492: control PASS, rolled PASS, "does not bite" (exit 1). Also M7: two D-WIRE headings fail, a changed title fails. |
| B2 (later follow-up closes) | fixed | r1 repro-B2.sh: after closing fu-parity-win-odd-root-cause and fu-release-pwsh-identity-crash, TEST-4033 and TEST-4034 PASS, "does not bite". A wider probe (close successor, drop fu-hook-gate-skips-renamed-doc, reopen fu-cfshare-redact-escape-robust, fu-parity-win-source-path and fu-parity-win-odd-root-dirs, close the three TEST-4021 items, file a new node-first P2, all dated 2026-12-02): TEST-4033, 4034, 4021 and 4022 PASS. |
| N1 (later re-measure / live tree) | fixed | `git rm` of the seven retirement launchers plus two lines appended to aai-run-tests.sh: TEST-4033 and TEST-4022 PASS. A section 8 appended after section 7: TEST-4033 (dated-record mode), TEST-4034 and TEST-4022 PASS. |
| N2 (space-separated switch value) | fixed | CHANGELOG.md:37 names the form; amendment 2026-11-23T22:52:49Z (measurement); aai-release.test.mjs:676-677 covers `-DryRun $true` and `-DryRun $false`. |
| r1 deviation 4 (D-ALLOW row tracked, not accepted/removed) | still undisclosed | No spec_amendment of the ref names the allowlist row or D-ALLOW (ledger scan). Not a finding; see deviation 5. |

## New readers: correct and not vacuous

The readers fold the ledger with the shipped `readDecisionsLedger`/`foldFollowUps` (no Date.now dependence for the verdict; ages are unused). Every ledger follow_up/follow_up_status record has a `Z` timestamp (0 without ts, 0 non-Z), so the string cut in `recordsThroughDate` is exact.

Mutations on a scratch clone (each must fail; each did):

- M1: drop record of fu-parity-win-odd-root-dirs removed. TEST-4033 (table differs: the item is open P2 as of 2026-11-23) and TEST-4034 (no follow_up_status record of the ride) fail.
- M2: successor filed at P2. TEST-4033 and TEST-4034 fail.
- M3: successor filed after the drop. TEST-4034 fails.
- M4: hitl_decision removed. TEST-4034 fails.
- M5: an outside-ref id filed under a node-first ref. TEST-4033 fails.
- M6a and M6b: a row's class changed, or a kept-native row removed. TEST-4033 and TEST-4022 fail.
- M8: a TEST-4021 item filed at P2. TEST-4021 fails.
- M9: the cfshare close carries another resolved_by. TEST-4034 fails.
- M10: a P2 filed under a node-first ref on 2026-11-20. TEST-4033 and TEST-4022 fail.
- M11: the RFC row reads in progress. TEST-4033 and TEST-4022 fail.
- A record commit on the branch touching README.md fails TEST-4033 (the is-ancestor gate keeps the arm armed on the branch).

## Time-bomb sweep

- **Release cut:** fixed (B1).
- **Later follow-up closes:** fixed (B2, wider probe above).
- **Later re-measure section:** fixed (N1).
- **Squash merge:** `git merge --squash` onto 0ff18d63. TEST-4033 PASS with "INFO ... not an ancestor of HEAD". TEST-4034 and TEST-4036 also PASS.
- **Retirement-launcher deletion:** fixed (N1 probe).
- **Renamed or archived spec:** the delta reads no spec path (comments only). The SPEC-DRAFT allocator rename is covered only through `spec-amend list --strict`, which was already in TEST-4036 before this delta.
- **Clock and date:** the readers use the section date, not the clock. The remaining window is NON-BLOCKING finding 2.
- **Shallow CI clone:** `git clone --depth 1`. TEST-4033 logs "not in this checkout" and passes. TEST-4034, 4036, 4021 and 4022 pass. The skill-suite jobs use fetch-depth 0 anyway.
- **Merge-commit merge (INFO):** if the PR were merged with a merge commit instead of the pinned `--squash --match-head-commit` (.aai/SKILL_MERGE.prompt.md:14), the hosted sha would become an ancestor of main. Every later main commit that edits the plan without adding section 8 would then fail TEST-4033. The pinned path avoids this, and so does a rebase merge.

## Robustness and scratch safety

- Bash changes are confined to node `-e` bodies. The removed `follow-ups.mjs list > open.json` step leaves no pipe, and no new early-closing reader appears under `set -euo pipefail`.
- The `\x27` in TEST-4034 sits inside a JS comment.
- The `for (let i = at7 + 1; i > 0 ...)` guard handles a missing section 7.
- The delta creates no scratch directories.
- Full suites on the scratch clone: test-aai-phase5-closeout.sh rc 0 (TEST-4024, 4033 to 4036), test-aai-sync-docs.sh rc 0 (TEST-4020 to 4022).

## Spec compliance: deviations

1. TEST-4033 and TEST-4022 no longer compare code-line counts with the tree. Disclosed (contract amendments 22:52:31Z and 22:52:43Z, unsigned, tracked by fu-amend-spec-node-first-phase5-closeout and fu-amend-spec-sync-on-node-20261123t2252). At b315e492 the section 7 table equals the live measurement including counts (reviewer probe), so Spec-AC-10 holds at merge.
2. TEST-4033 checks the RFC row status, twin-duplication value and D-HOSTED diff only while section 7 is the latest. Disclosed (22:52:31Z).
3. The D-HOSTED per-commit check is skipped when the hosted sha is not an ancestor of HEAD. Disclosed (08:38:55Z).
4. TEST-4034 and TEST-4021 read filing and close records instead of the live `follow-ups list` state that Spec-AC-11 words. Disclosed (22:52:31Z and 08:39:01Z). At merge, the live list agrees.
5. Carried from r1, still undisclosed: D-ALLOW says remove or accept the `win-sh-odd-root-dirs` allowlist row. The row is instead tracked by the P3 follow-up fu-parity-odd-row-tracker-successor. The orchestrator should add the one-line disclosure amendment before close.
6. Amendment classes: the 22:52:31Z record calls the count removal "Additive disclosure" in the contract class. It narrows an assertion, so "additive" describes the disclosure, not the change. The owner sign-off items stay open for it.

## Findings

### NB-1 (NON-BLOCKING, P3): re-measure code-line counts are no longer checked by any test

- **Where:** tests/skills/lib/script-classes.mjs:30-51, used by TEST-4022 (test-aai-sync-docs.sh:313) and TEST-4033.
- **Problem:** the r1 N1 fix removed the count comparison for every section, including the latest one. TEST-4022 is the live guard of the latest section, so a wrong count in a new record now passes.
- **Failure scenario:** the reviewer probe appended a section 8 with aai-run-tests.sh at 999 code lines (actual 540). TEST-4022 and TEST-4033 both exit 0.
- **Bounded by:** file and class are still compared, TEST-4025 still forbids undeclared logic, and the current record is exact.
- **Recommended disposition:** (d) `accepted residual:` a P3 assurance-strength gap with no bite and no false record today. The counts are the record's own measurement, and the claims that gate phase 5 (no logic row, file set, class) stay live. If the orchestrator prefers to keep it visible to whoever writes the next re-measure, use (b) `fu-remeasure-counts-unchecked` (P3).

### NB-2 (NON-BLOCKING, P3): the as-of-date fold still reacts to a late-merged record dated on or before the record date

- **Where:** tests/skills/lib/script-classes.mjs:54-57, used by test-aai-phase5-closeout.sh (TEST-4033 `recordsThroughDate(records, s7.m[3])`) and test-aai-sync-docs.sh (TEST-4022).
- **Failure scenario:** a branch cut before or on 2026-11-23 that filed a P1 or P2 follow-up under a plan ref, `install-path-parity-harness` or a `node-first*` ref, and merges after this PR, fails TEST-4033 and TEST-4022 on its own PR (reviewer probe: a P2 with ts 2026-11-23T12:00:00Z under ref node-first-parallel).
- **No carrier today:** the two unmerged branches carry only singleton-reservation-portability records. New records carry the current timestamp, so the window cannot reopen.
- **Recommended disposition:** (d) `accepted residual:` a P3 maintenance edge, closed for new writes, with no carrier and no false record. It is strictly narrower than the r1 live-state pin it replaced.

### INFO

- The CHANGELOG sentence says "three forms change at the public boundary" and then adds "One more form is accepted". The count reads slightly off but nothing is misstated.
- tests/skills/test-aai-sync-docs.sh TEST-4021 scans lines with `line.includes(id)` before parsing. That is correct, because the first `follow_up` filing wins, as it does in the fold.

## WARNING dispositions (H6)

- NB-1: recommended (d) `accepted residual: re-measure code-line counts are the record's own measurement; file, class and the strict check stay live; the current record is exact (P3, no bite)`. Fallback (b) `fu-remeasure-counts-unchecked` (P3). The orchestrator records the choice.
- NB-2: recommended (d) `accepted residual: the as-of-date fold reacts only to a late-merged in-scope record dated on or before 2026-11-23; no carrier exists and new writes cannot enter the window (P3)`.
- Deviation 5 is not a WARNING, but it is still owed: a one-line D-ALLOW disclosure amendment.

## Reviewer hazard disclosure

- All mutations, the squash simulation and the shallow clone ran under the session scratchpad (`rv2-p5c/clone`, `rv2-p5c/shallow`). The probe script refuses any other clone path and restores files from saved copies by `cp`.
- The only `git checkout`/`git reset` ran inside the scratch clone, to undo the probe's own `git rm`.
- On the branch checkout: read-only git, the two r1 repro scripts (which clone to scratch), `spec-amend list --strict`, `gh run view`, and this report file. No commit, push, stash or restore.

## Next steps

1. The orchestrator records the NB-1 and NB-2 dispositions and the D-ALLOW disclosure amendment (deviation 5).
2. Read the PR's final-head ps1-quality and skill-suite runs (D-HOSTED step 5) before merge.
