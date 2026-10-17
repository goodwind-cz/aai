```yaml
review:
  scope: 7b024468..91914f69 (delta since r3 PASS / r4 FAIL; commits 5d69bd13, f4e9cb97, 91914f69; PR #471)
  spec: docs/specs/SPEC-0233-spec-release-command-finish.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/release-finish.mjs:164-178 covered set for numbered merges (M^1..M^2), :173 numbered inner commits audited as their own PR, :178 unnumbered merges skipped, :190-201 rebase attribution via gh api /commits/{sha}/pulls with merged_at, direct commits need own notes or no-notes body; TEST-050 arms (numbered merge, rebase, unmerged association, gitflow S9 cited/uncited, lone direct, unnumbered merge pass/fail); B-1 repro no longer refuses" }
      - { ac: Spec-AC-02, call: compliant, citation: "release-finish.mjs:347-351 queuedOrRefuse counts only isInMergeQueue===true (N-2 fixed); :439 before unchangedBase, :449 after merge; :441 failed checks named; watcher --required :443; TEST-052, TEST-053 (exit 8, no second merge, completion after queue settles), TEST-054 (armed auto-merge + failing check refuses 20)" }
      - { ac: Spec-AC-03, call: compliant, citation: "publication path unchanged in delta; TEST-006/007 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "processAlive :243-250 Z/X dead (/proc, ps fallback, win32 skip); deadOwner :64 reuses it; base-busy ignores worker once phase=updated :257; resume while queued does not re-merge (TEST-053); TEST-051 real zombie" }
      - { ac: Spec-AC-05, call: compliant, citation: "frontends only gain header comments (aai-release.sh:27-28, aai-release.ps1:22-23); sh uses exec node (:108), ps1 exit $LASTEXITCODE (:131-132) so exit 8 propagates on both; validation r13 hosted ps1/Pester legs green on 91914f69" }
      - { ac: Spec-AC-06, call: compliant, citation: "SKILL_RELEASE.prompt.md:86 documents exit 8 (N-1 fixed); docs/product/release-command-finish.md:48,51 describe required-only watching, PENDING exit 8, commit classification and the evil-merge limit; CHANGELOG [unreleased] entry" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-release.sh, line: 1606,
          issue: "R13-1: no test pins the `!merge` half of the covered-skip guard (release-finish.mjs:173). Validation mutant mC (drop !merge) survives. The code is correct: reviewer scratch repro (#11 merged into #12's branch) reports #11 when only #12 is cited and nothing when both are",
          failure_scenario: "A later edit simplifies :173 to `covered.has(commit)&&!last`; a stacked PR merged into a feature branch as 'Merge pull request #11' is then silently skipped (fail-open), and the suite stays green" }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 193,
          issue: "A failed commit-to-PR lookup (gh api non-zero, rate limit, network, bad JSON) becomes prs=[] and falls into the 'no PR number; add notes or a no-notes: line' finding. Fail-closed, but the named cause is wrong",
          failure_scenario: "Online confirm on a rebase-merge repo while the GitHub API rate-limits: every rebase commit of a correctly noted PR is reported as missing-notes, and the operator is told to edit notes/messages instead of retrying. Spec item 4 asks for one named reason" }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 164,
          issue: "R13-2: a branch commit inside a numbered merge whose subject ends in an issue reference '(#7)' is audited as PR #7. Offline it is a finding. Online, `gh pr view 7` fails, giving REFUSED github-command (json() at :205). Same behavior as the r3-validated engine (7b024468) and as main's shell audit, so it is not a regression of this delta",
          failure_scenario: "Merge-commit workflow, branch commit 'fix: crash (#7)' where #7 is an issue, notes cite only the PR: the release refuses with a gh error. The workaround is to mention #7 in the notes" }
    info:
      - "release-finish.mjs:194 takes the first merged PR the API associates with the commit, whatever its base. A commit that went through a stacked PR into a feature branch can be attributed to the inner PR. Fail-closed: the notes must then cite that PR"
      - "S11 (validation): an inner commit that carries the outer number produces a duplicate '#N' line. Cosmetic"
      - "Offline and non-GitHub cuts (no lookup) now require every unnumbered shipped commit to add its own notes or carry a no-notes body. This is disclosed in docs/product/release-command-finish.md:51 and is the intended answer to the bot P1"
      - "Subject-based PR attribution trusts commit subjects, as before. A spoofed 'Merge pull request #N' subject extends coverage to its side commits, but the notes must still cite #N"
  cannot_verify:
    - { claim: "gh pr merge --squash --match-head-commit on a merge-queue base enqueues (exit 0) rather than erroring, and isInMergeQueue/autoMergeRequest have the modelled semantics", closes_with: "One live release on a repository with a required merge queue" }
    - { claim: "GitHub /commits/{sha}/pulls lists the rebase-merged PR, with merged_at set, for each rebased commit", closes_with: "Live online --audit on a repo with a rebase-merged PR; the fixture stubs the response" }
    - { claim: "Queue ejection and a queue merge on a moved base", closes_with: "Live queue run; disclosed in the product doc Limits" }
  overall: pass
```

# Independent Code Review r5: release-command-finish

**Verdict: PASS.** No BLOCKING findings and no spec non-compliance. Three NON-BLOCKING findings need a disposition before closeout.

## Scope

- Worktree `/Users/ales/Projects/aai-change-release-finish-one-command`, branch `change/release-command-finish-ship`, HEAD `91914f69` (verified).
- Reviewed delta: `git diff 7b024468..91914f69`.
  - Commits: 5d69bd13 (bot fixes), f4e9cb97 (r4 fixes), 91914f69 (r12 fix).
  - Files: `release-finish.mjs`, `watch-ci.mjs`, `aai-release.sh` and `aai-release.ps1` headers, `SKILL_RELEASE.prompt.md`, product doc, CHANGELOG, `test-aai-release.sh`, `decisions.jsonl`, INDEX.
- Dispatch note: the prompt listed focus areas and named R13-1/R13-2 as questions. It did not pre-rate severity or exclude anything, so no coaching is recorded. The whole delta was reviewed.
- Report location: canon (`SKILL_CODE_REVIEW`) puts reports in `docs/ai/reviews/`, and r4 lives there. The dispatch said `docs/ai/reports/`; canon was followed.

## r4 findings

| r4 | Status | Evidence |
|---|---|---|
| B-1 false missing-notes for commits of a numbered PR | **Resolved.** | Numbered merge side commits are covered (:166-170, :173). Rebase commits are attributed through the lookup, and only merged PRs count (:190-196). TEST-050 arms fail if the covered set, the lookup or the merged_at filter is removed. 91914f69 restores per-PR auditing for numbered commits inside the range (gitflow S9). |
| N-1 exit 8 missing from the skill | **Resolved.** | SKILL_RELEASE.prompt.md:86; both frontend headers. |
| N-2 armed auto-merge read as queued | **Resolved.** | Only `isInMergeQueue===true` is pending (:350). TEST-054 refuses with the failing check named. |
| N-3 unnumbered merge untested; evil merge | **Resolved / recorded.** | Unnumbered-merge pass/fail arms are in TEST-050. Evil merge is disclosed in the product doc :51 and filed as follow-up `fu-release-unnumbered-merge-content` (P3). |
| N-4 `ps` rc1 with empty output reads as dead | **Recorded.** | follow-up `fu-release-ps-liveness-empty-output` (P3). Code unchanged. |

## Focus checks

- **Classification order.** Each commit goes through these steps in turn:
  1. Covered unnumbered commits are skipped.
  2. Unnumbered merges are skipped.
  3. Non-shipped commits are skipped.
  4. The release-cut exemption applies.
  5. Unnumbered single-parent commits get the online lookup.
  6. Commits still unnumbered need their own notes or a no-notes body.
  7. Numbered commits go through the existing notes, title, added-notes and PR-body checks.

  No path guesses clean. A failed lookup refuses, though under the wrong name (N5-2).
- **Nested merges.** Reviewer scratch repro (`scratchpad/r5`): #11 merged into #12's branch, two unnumbered sub commits, plus an inner `fix: thing (#7)`.
  - With only #12 cited, the findings are `#7` and `#11`. The unnumbered sub commits stay covered.
  - With all three cited, there are no findings.
  - This matches validation probes S12/S15. The behavior is correct, but nothing pins it (N5-1).
- **Exit 8 vs 20.** `pending()` sets `e.pending`. The single top-level handler prints `PENDING` and the resume command, then sets exit 8. `finally` still releases the claim. No inner catch swallows or rewraps the error. The queue check runs before `unchangedBase`, so a queued PR on a moved base is reported as pending, not as base-moved. The moved-base absorption limit is disclosed.
- **processAlive.**
  - The `/proc` stat parse is a greedy match up to the last `) `, which is safe for commands containing parentheses.
  - If `ps` is missing, the process counts as alive (conservative).
  - EPERM counts as alive.
  - The deadOwner semantics are unchanged apart from treating zombies as dead.
- **watch-ci `--required`.** The flag is opt-in, so the default argv of other callers is unchanged. TEST-052 asserts every poll carries `--required`.
- **PS1/bash parity.** The engine is shared Node code. Both frontends pass exit 8 through unchanged (`exec node` in bash, `exit $LASTEXITCODE` in ps1). There is still no PS test for exit 8 (validation R12-5, carried).
- **R13-1 / R13-2.** Neither blocks. R13-1 is a test gap on correct code. R13-2 is fail-closed, matches the r3-validated engine and main, and the notes can work around it.

## Findings and dispositions (H6)

- **N5-1 (R13-1), P3: missing test for the `!merge` guard at :173.** Disposition **(a) remediate in tree**: add a TEST-050 arm with the S12 shape (inner `Merge pull request #11` under #12, only #12 cited → 20 naming #11). Fallback if the ride closes first: follow-up `fu-release-nested-merge-test`.
- **N5-2, P3: failed lookup reported as missing-notes (:192-201).** Disposition **(b) follow-up** `fu-release-pr-lookup-failure-cause`. Fix: when gh api fails (`r.error || r.status!==0`) or returns unparseable JSON, refuse with `notes-history` naming the commit and saying "retry". Keep `[]` meaning "no PR".
- **N5-3 (R13-2), P3: issue reference `(#7)` audited as a PR.** Disposition **(b) follow-up** `fu-release-issue-ref-as-pr`. Options: a docs note, or online, treat a `gh pr view` "not a PR" answer as unnumbered and fall through to the lookup.
- INFO items do not gate.

## Test evidence

- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh` at 91914f69 returned rc=0 and `=== aai-release: ALL TESTS PASSED ===`. TEST-050..054, TEST-026 and TEST-034 all passed. Log: `/private/tmp/claude-501/-Users-ales-Projects-aai/84834df3-26b2-4169-98af-6a142178eee5/scratchpad/r5-release-suite.log`.
- Test quality: each new arm fails under its mutant. This was checked by reading the code (removing the covered set, the lookup, merged_at, the unnumbered-merge skip, the 91914f69 guard, or the queue/armed logic would each flip an assertion) and agrees with validation r13's mutation runs. The only survivor is mC (N5-1).
- Latest validation: `docs/ai/reports/VALIDATION-20261017T161441Z-release-command-finish.md` (PASS).

## Next steps

1. Optionally fold N5-1 into the ride (one test arm). Otherwise file the three follow-ups named above.
2. Orchestrator runs the returned `set-code-review` command.
