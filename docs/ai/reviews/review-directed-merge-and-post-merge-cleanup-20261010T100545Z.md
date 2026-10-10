# Code review — directed-merge-and-post-merge-cleanup (round 1)

```yaml
review:
  scope: origin/main...HEAD (2836dcc5...3dd377cd, branch change/directed-merge-and-post-merge-cleanup, 27 files +2884/-16)
  spec: docs/specs/SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/SKILL_MERGE.prompt.md:19-41 marked blocks; four aai-merge wrappers; SKILL_PR.prompt.md:555, SKILL_SHIP.prompt.md:112, SKILL_WORKTREE.prompt.md:268; TEST-001/002 green logs" }
      - { ac: Spec-AC-02, call: compliant, citation: "merge-cleanup.mjs:710-748 (refusal order, exit 10, one printed command, never runs gh pr merge); TEST-003/004" }
      - { ac: Spec-AC-03, call: compliant, citation: "merge-cleanup.mjs:146-162 read-back gate before classifyDrafts/planChecks; TEST-005" }
      - { ac: Spec-AC-04, call: compliant, citation: "merge-cleanup.mjs:166-235 id + blob identity, 259-290 archive-then-unlink; TEST-006/007" }
      - { ac: Spec-AC-05, call: compliant, citation: "merge-cleanup.mjs:300-394 ff-only, prefix check, ledger-merge, restore on ff failure; TEST-008/009 (crash-window residual: finding NB-2)" }
      - { ac: Spec-AC-06, call: compliant, citation: "merge-cleanup.mjs:414-479 verdict, archive-runtime before remove, worktree remove without --force, update-ref -d CAS; TEST-010/011" }
      - { ac: Spec-AC-07, call: non-compliant, citation: "merge-cleanup.mjs:500-507 + 166-178: 'merged ref' = frontmatter id of EVERY .md the PR added OR MODIFIED plus the branch-name tail; reproduced: a PR that only modifies another in-flight item's doc clears that item's origin focus (finding B-1)" }
      - { ac: Spec-AC-08, call: compliant, citation: "per-step live re-derivation + journal; reportStep no-op; TEST-013/014 (step-boundary interruptions only)" }
      - { ac: Spec-AC-09, call: cannot-verify, citation: "Bash half TEST-015 green; PowerShell half local pwsh 7.6.3 only; native Windows verdict is PR CI only (spec V2)" }
      - { ac: Spec-AC-10, call: compliant, citation: "PROFILES.yaml core +2, suite-map row, prompt-diet-ledger.sh +3049 with TEST-012 pin 59467, ps1-quality.yml filters; TEST-017" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 500,
          issue: "mergedRefs() treats the frontmatter id of every added OR MODIFIED .md doc (deliveredIds, --diff-filter=AM, line 167) plus the last branch-name segment as 'the merged ref'; stateStep then runs state.mjs clear-focus, which nulls current_focus AND marks that work item phase=closed status=done, with no archive of the origin STATE.yaml (gitignored, irreversible)",
          failure_scenario: "Reproduced in a scratch fixture: main checkout focus = other-item (in flight); merged PR #5 only appends a cross-link to docs/issues/ISSUE-0002-other-item.md; apply exits 0 reporting 'state: done (cleared focus other-item)' and STATE now reads type none / ref_id null. A branch tail colliding with an unrelated ref id bites the same way." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 732,
          issue: "preflight binds the printed merge command to gh's headRefOid but lane-gate --sweep-check judges the sweep record against the LOCAL HEAD of --origin; nothing checks that the local HEAD equals headRefOid",
          failure_scenario: "Ride checkout at swept head A with a valid pr_sweep record; a commit B is pushed to the PR from elsewhere (bot autofix, another machine) and CI goes green; the owner types /aai-merge <n> without a sha, the prompt takes headRefOid=B as the judged head, sweep-check compares the record to local A and passes, preflight exits 10 and the prompt merges unswept B. Fix: refuse (e.g. head_not_local) when git rev-parse HEAD in --origin differs from headRefOid." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 358,
          issue: "sync-base rewrites dirty ledgers to the HEAD blob BEFORE the fast-forward and re-appends the local tail only in the same process; a resume re-derives from live state and never re-applies the archived tail",
          failure_scenario: "Process killed (SIGKILL, terminal closed) after line 363 wrote the HEAD blob and before line 386; on re-run planSync sees the ledger clean, fast-forwards, and the local EVENTS/decisions lines exist only in docs/ai/archive/merge-cleanup/pr-<n>/sync/; the report lists nothing under remaining, so the loss is silent (Spec-AC-08 'lose no file' holds only at step boundaries, which is all TEST-014 exercises)." }
      - { rank: NON-BLOCKING, file: .aai/SKILL_MERGE.prompt.md, line: 36,
          issue: "PowerShell block passes --pid $PID (the one-shot pwsh process) while the bash block passes $PPID (the harness, which is what session-lock acquire records per SKILL_PR/SKILL_WORKTREE)",
          failure_scenario: "On Windows the same session that ran the ride (lock held under the harness pid in the ride worktree) runs /aai-merge: lockStatus reports a live holder != $PID and apply refuses session_locked, so the positive cleanup is not at parity with Bash (fails safe, not destructive)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 51,
          issue: "spec implementation-plan edge cases not implemented: PR url repo vs origin remote mismatch refusal (url is read and never used) and worktree_missing (a registered worktree whose directory is gone is refused as worktree_dirty)",
          failure_scenario: "gh default repo set to an upstream while origin is a fork: the read targets another repository's PR #n; the CAS branch delete and ancestry check limit damage, but the refusal reason the spec names never appears; a deleted-directory worktree gets a misleading worktree_dirty reason." }
  cannot_verify:
    - { claim: "Native Windows PowerShell 5.1 / pwsh 7 behavior of the PS block and Pester suite (Spec-AC-09)", closes_with: "ps1-quality and skill-suite PR CI run ids on the PR head" }
    - { claim: "Real GitHub field shapes of gh pr view (statusCheckRollup entries, mergeStateStatus values) and gh pr merge --match-head-commit behavior", closes_with: "one live directed merge on a real PR, or recorded gh output fixtures from GitHub" }
    - { claim: "The hooks overlay (claude-hook-gate.sh) accepts the printed AAI_OPERATOR_MERGE=1 gh pr merge line unmodified", closes_with: "hook-gate suite run against the exact printed command" }
    - { claim: "Suite and mutation results (dispatch forbade running them here)", closes_with: "the concurrent Validation run of V1-V4 and mutation-run --replay" }
  overall: fail
```

## Scope and spec

Diff `origin/main...HEAD` (2836dcc5..3dd377cd) in worktree
`/Users/ales/Projects/aai-change-directed-merge-and-post-merge-cleanup`, read
in full for the engine, prompt, wrappers, edited prompts, companion wiring,
ledger appends; the test suite read for fixture shape and stub. Frozen spec
`docs/specs/SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md`. Per
dispatch, no suites or mutation runs were executed; one scratch fixture
outside the worktree was run against the engine.

Coaching check: the dispatch listed focus areas without pre-rating severity
or excluding scope; the full scope was reviewed.

## Focus areas checked

- Merge authority: the engine has no `gh pr merge` call path; its only gh
  call is the fixed `pr view` (line 120-127). The prompt runs the printed
  line only on an explicit `/aai-merge <n>`; wrapper carries SUBAGENT-STOP;
  SKILL_SHIP states /aai-ship never invokes it; Article 7 deviation is
  disclosed in the spec and not ratified (owner decision). See NB-1 for the
  sweep/head binding gap.
- Destructive operations: no `--force`, `branch -D`, stash, reset, restore,
  clean or prune anywhere in the engine; archive (copy + byte compare) precedes
  every unlink; branch delete is `update-ref -d <ref> <headRefOid>`.
- Ledger prefix: this PR appends 1 EVENTS line and 2 decisions lines at the
  end only. Engine sync keeps the incoming blob as prefix via ledger-merge.
- Test-only seams `AAI_MERGE_CLEANUP_GH_NODE` / `AAI_MERGE_CLEANUP_STOP_AFTER`
  are inert when unset (an attacker able to set env could equally shadow
  `gh` on PATH) — INFO only.
- Fixtures: one mktemp root, HAZ-CD guards, private git identity, deny-by-default
  gh stub pinning the exact argv skeleton.

## Reproduction of B-1

Scratch script (outside the worktree):
`/private/tmp/claude-501/-Users-ales-Projects-aai/687516a7-9bb3-4b30-9ccf-230f17be6426/scratchpad/cr-probe/probe.sh`.
Output: focus before `ref_id: other-item`; apply rc=0 with
`state: done (cleared focus other-item)`; focus after `type: none, ref_id: null`.
The CHANGELOG line "clears the focus only for the merged work item" is
therefore false as shipped.

Recommended fix: derive the merged ref from the delivered intake doc only
(spec A1: the doc whose `links.pr` carries this PR number, or the work item
whose close event names the PR), drop the branch-tail heuristic or require it
to agree with that id, archive the origin STATE.yaml into the per-PR archive
before clear-focus, and add a TEST-012 arm where the PR modifies another
item's doc while the origin focus names that item.

## Warning dispositions (H6, recommended; orchestrator records)

- NB-1 (sweep judged on local HEAD, merge bound to remote head): remediate-in-tree
  (small refusal + arm), else promote to follow-up P2 `fu-merge-preflight-local-head-binding`.
- NB-2 (ledger tail crash window): promote to follow-up P2
  `fu-merge-sync-ledger-crash-window` (or remediate by journaling the pending
  ledger re-append and re-applying it on resume).
- NB-3 (PowerShell $PID vs harness pid): remediate-in-tree (use the parent pid,
  e.g. `(Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId`)
  or promote P3 `fu-merge-ps-pid-parity`.
- NB-4 (url mismatch and worktree_missing edge cases): promote P3
  `fu-merge-edge-cases-url-missing-wt`, or disclose as a spec amendment.

## Next steps

Remediate B-1 with a RED-first regression arm, address or disposition NB-1..4,
then re-review (round 2).
