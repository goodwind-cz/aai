```yaml
review:
  scope: "main...0c84b61a (full diff), focus delta e7290ba4..0c84b61a"
  spec: docs/specs/SPEC-0261-spec-watch-ci-cancelled-runs-and-release-gate-docs.md (incl. post-freeze Amendment 2026-10-29)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "github-checks.mjs:136-188; TEST-2701, TEST-2702 PASS (aai-current-head-ci rc=0)" }
      - { ac: Spec-AC-02, call: compliant, citation: "github-checks.mjs:169-174 (same workflow_id+event, newer only); TEST-2703 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "github-checks.mjs:141-152, :187 drop + :226 required refusal; TEST-2704 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "run-list request only at github-checks.mjs:141, gated by :137; TEST-2705 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "release-notes-gate.mjs isShipped; TEST-2706 PASS (aai-release-notes rc=0)" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-2707 PASS; NB-5 comment at release-notes-gate.mjs:11 leaves the mutation anchor intact" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2708 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-2709 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "CHANGELOG.md:33 entry (NB-2 rewording); TEST-2710 PASS" }
      - { ac: "Amendment NB-1 (TEST-2711)", call: compliant, citation: "github-checks.mjs:157-162; TEST-2711 PASS; this reviewer's mutation (drop :161) -> TEST-2711 not ok" }
      - { ac: "Amendment NB-3", call: compliant, citation: "docs/USER_GUIDE.md:810, :2909" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/github-checks.mjs, line: 109,
          issue: "the workflows cache is kept across the two check-run reads, so a run cached as in-progress on read 1 keeps that conclusion on read 2",
          failure_scenario: "cancelled run C exists; run W (same workflow+event, newer than C) is in_progress at read 1 and cached; a push-free re-trigger W2 cancels W between read 1 and read 2; read 2 sees W's check as cancelled, but W is not in cancelledRuns (cache says in_progress) and W2 is not in the run list, so W's check is reported cancel and watch-ci exits 5 on a superseded run for one invocation. Fails in the safe direction (false red, never false green); the re-read widens the window by the length of the run-list fetch" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/github-checks.mjs, line: 162,
          issue: "the 'workflow state moved during observation' refusal is not exercised by any committed test",
          failure_scenario: "replacing line 162 with a comment leaves aai-current-head-ci all green except the scratch-only TEST-004 baseline failure; a regression that deletes the guard would ship unnoticed (it would then treat a newly cancelled run's check by its own cancel bucket, which is again fail-safe)" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0261-spec-watch-ci-cancelled-runs-and-release-gate-docs.md, line: 365,
          issue: "the amendment says the TEST-2711 test files are beyond the frozen file list, and the decisions.jsonl spec_amendment record (ts 2026-10-29T21:38:47Z) says both changes are outside the list; both test files and github-checks.mjs are on the list (spec :308, :311-312). Only docs/USER_GUIDE.md is beyond it",
          failure_scenario: "the owner signing fu-amend-watch-ci-cancelled-runs-f5717d reads a scope breach that did not happen; an audit counting out-of-list files from the ledger over-counts by three" }
      - { rank: NON-BLOCKING, file: docs/USER_GUIDE.md, line: 810,
          issue: "says the user guide and product pages count as shipped and 'other docs ... are exempt', without the root files (README.md, AGENTS.md, CLAUDE.md, CODEX.md, GEMINI.md, SKILLS.md); :2909 does name them",
          failure_scenario: "a contributor reading only the 'Release notes for pull requests' paragraph edits README.md, expects an exemption, and is refused by the gate" }
      - { rank: NON-BLOCKING, file: docs/ai/tdd/, line: 0,
          issue: "TEST-2711 has no stored RED log and is not a Test Plan row, so mutation_gate v1 does not gate it (validation r2 F1)",
          failure_scenario: "the evidence trail for the amendment test rests on reviewer and validator scratch runs, not on a committed artifact" }
  cannot_verify:
    - { claim: "live GitHub ordering: a sibling's check-run is visible on /commits/{sha}/check-runs before the run list reports that sibling completed",
        closes_with: "a live replay against a real PR with a superseded run, or GitHub API documentation of the ordering" }
    - { claim: "API cost on long polls: every poll on a head that carries a cancelled run now makes two paginated check-run reads plus the run list",
        closes_with: "rate-limit headers from a real watch-ci session on a head like PR #515" }
  overall: pass
```

# Code review r2: watch-ci-cancelled-runs-and-release-gate-docs

security_relevant: false

## Scope and preflight

- Worktree `/Users/ales/Projects/aai-wt-watch-ci-release-gate`, branch `fix/watch-ci-cancelled-runs-and-release-gate-docs`, head `0c84b61a`. Scope `main...HEAD` (19 files), with the r2 delta `e7290ba4..0c84b61a` (10 files) read in full.
- `git status --porcelain` shows only `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl` modified. These are runtime ledger appends from the validator and test runs, not part of the scope.
- Spec: the frozen SPEC-DRAFT plus its post-freeze Amendment. `spec-amend list --strict` reports the amendment as `unsigned-tracked` under `fu-amend-watch-ci-cancelled-runs-f5717d` (open), and exits 0.
- Note on the dispatch: the dispatch prompt summarised the r1 findings and validation r2 F1/F3, and stated the owner's standing blocking threshold. I treated that as round context rather than coaching. I reviewed the whole delta and its interactions anyway, and the findings below are my own.

## The delta: re-read of check runs (NB-1 fix)

Structure. The body of the check-run loop is wrapped unchanged in a `readCheckRuns` closure (github-checks.mjs:89-134). The closure reassigns the outer `let observations` and fills the shared `workflows` cache. It runs once at :135, and a second time at :161 only inside the `cancelledRuns.length` branch, after the run list. I compared the re-indent hunk line by line with e7290ba4: the only logic changes are `observations=[]` and moving `const workflows` before the closure. The re-indent is about 45 lines but mechanical. The extra nesting is a fair price for having one parser for both reads.

Correctness.
- r1 NB-1 race (the sibling completes between the check snapshot and the run list): read 2 happens after the run list. A run the list shows as completed has registered its checks by then, so the line :180 "sibling has the same name" test finds the sibling's check and keeps it, and `newer()` then selects it. **Bite proven:** in a scratch copy (HAZ-SCRATCH) I replaced :161 with a comment and TEST-2711 failed (`not ok 1`). With :161 restored it passes.
- The sibling's status still comes from the run list, which is older than read 2. If the sibling completes after the list without the check, the reader rewrites C's check as `pending`, the safe direction. If it completes with the check, read 2 shows the check and it wins. I found no ordering that yields a false pass.
- A new cancelled workflow seen only on read 2 refuses closed (:162). watch-ci turns the throw into `degrade` (watch-ci.mjs:128-144), so the result is exit 3, never a pass.
- Fail-closed paths on read 2 are the same as on read 1 (pagination, duplicate id, head SHA, malformed identity, transport). All of them throw.
- `drop` holds object references from the read-2 observations, and the splice at :187 runs on that same array. This is consistent.
- Residual (NB-A): the workflow cache is not refreshed on read 2. See the failure scenario in the YAML block. Its only outcome is a false red for one invocation, never a false green.

API cost. Read 2 runs only when the first read already holds a cancelled run, which is the same gate as the run-list call (Spec-AC-04's zero-call arm is unaffected; TEST-2705 PASS). Workflow fetches stay cached per run id. On a head that permanently carries a superseded run, every poll costs one more paginated check-runs read. This is acceptable, and listed under cannot_verify.

## r1 NB resolution

| r1 | Status at 0c84b61a | Evidence |
|---|---|---|
| NB-1 | resolved in tree (r1 suggested a follow-up; remediation chose a fix plus an amendment) | github-checks.mjs:157-162, TEST-2711, mutation bite above |
| NB-2 | resolved | CHANGELOG.md:33 no longer says "named above"; it points to docs/product/release-notes-gate.md |
| NB-3 | resolved, with a residual (NB-D) | USER_GUIDE.md:810 and :2909 both drop the blanket docs exemption; :810 omits the root files |
| NB-4 | follow-up `fu-skill-pr-3b-shipped-docs-wording` already in decisions.jsonl | ledger line ts 2026-10-29T21:36:23Z |
| NB-5 | resolved | release-notes-gate.mjs:11 comment; the TEST-2707 sed anchor `^docs/product/` does not occur in the comment |

## Tests run (this reviewer, sequential, `env -u AAI_ROLE`)

- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-current-head-ci.sh`: rc=0. PASS TEST-001..004, 2701..2705, 2711.
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release-notes.sh`: rc=0.
- Scratch mutations (copy of `.aai` + `tests` under the session scratchpad):
  - drop :161 → TEST-2711 fails.
  - drop :162 → no test fails. TEST-004 also fails in scratch without any mutation, because the docs tree is absent there.

## Spec deviations (listed per prompt)

1. TEST-2711 appears in neither the AC Status table nor the Test Plan table. It exists only in the Amendment, so mutation_gate v1 does not gate it.
2. The Amendment's file-list sentence and the matching decisions.jsonl `why` are inaccurate (NB-C).
3. The owner has not signed the amendment. It is tracked as open `fu-amend-watch-ci-cancelled-runs-f5717d`.

## Warning dispositions (H6)

None of these needs another in-tree round, per the standing decision.

- NB-A (stale workflow cache on read 2, P3): promote to follow-up. suggested: `fu-current-head-ci-reread-stale-cache`. Fix by re-fetching cached workflows on read 2, or by refusing when a read-2 check turns cancelled under a cached non-cancelled run.
- NB-B (guard :162 unexercised, P3): accepted residual: fail-closed guard with no observed bite; removing it degrades to the pre-amendment fail-safe behaviour; no false record.
- NB-C (amendment file-list wording, P3): it leaves a false statement in a ledger record, so (d) is not available. Promote to the tracked ref `fu-amend-watch-ci-cancelled-runs-f5717d`: the owner's sign-off record (or an appended correction record) states that only docs/USER_GUIDE.md was beyond the frozen list.
- NB-D (USER_GUIDE :810 omits the root files, P3): fold into the existing follow-up `fu-skill-pr-3b-shipped-docs-wording`, which already covers shipped-docs wording, and extend its `what` to include USER_GUIDE.md:810. Alternative: suggested `fu-user-guide-release-notes-root-files`.
- NB-E (TEST-2711 has no RED log or mutation row, P3): accepted residual: RED was established independently by the validator (r2 F1) and by this reviewer's :161 mutation; evidence-hygiene only, no false record.

## Next steps

1. Orchestrator: record the dispositions above (follow-ups.mjs for NB-A, and NB-C and NB-D notes on the named refs), then run `set-code-review` with the command returned.
2. Owner: sign or reverse the amendment (`fu-amend-watch-ci-cancelled-runs-f5717d`). Note NB-C when signing.
