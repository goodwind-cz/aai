# Code review — directed-merge-and-post-merge-cleanup, round 4 (bot-sweep delta)

```yaml
review:
  scope: "01050055..a5e3f0ac (commit a5e3f0ac) on change/directed-merge-and-post-merge-cleanup; base origin/main 2836dcc5"
  spec: docs/specs/SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/merge-cleanup.mjs:291-292 (classified sha256), :359-372 (compare-then-unlink, divergent_after_plan); TEST-007 race arms before-archive/before-unlink; deviation NB-1 (race edge records edited bytes as superseded in the manifest)" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/merge-cleanup.mjs:855-865 remoteBranchNote (remote branch still never deleted; remote_unknown on ls-remote failure); TEST-010 remote_unknown/remote_absent arms" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/scripts/merge-cleanup.mjs:869-873 archivedFromManifest, :883 report.archived; TEST-012 archived paths incl. origin:docs/ai/STATE.yaml; TEST-014 resume keeps earlier draft archives" }
      - { ac: "Spec-AC-01..03, 05, 08, 09", call: compliant, citation: "untouched by the delta; round 3 PASS at bc041b26 stands; D2 plan grammar unchanged, plan output gains targets only (:928-931)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 359,
          issue: "The hash re-check runs AFTER archiveFile, so a draft edited between classification and archive is still copied into the archive and recorded in manifest.jsonl with reason 'superseded'; since the report's archived list is now read from the manifest, the same run reports the path as archived/superseded AND retained/divergent_after_plan.",
          failure_scenario: "Another session appends to docs/issues/ISSUE-DRAFT-x.md after classifyDrafts hashed it and before archiveDrafts reaches it (exactly TEST-007 arm before-archive). The working copy is correctly kept, but manifest.jsonl now carries {original: ISSUE-DRAFT-x.md, reason: superseded, sha256: <edited bytes>} for bytes that never appeared in the PR history - a false record that every later report of this PR repeats (Spec-AC-04 'archive only copies whose exact bytes appear in the PR history')." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 841,
          issue: "Plan targets are incomplete: the state planner names 'clear focus <ref>' but not the pre-clear STATE archive path (origin:docs/ai/STATE.yaml -> .../origin/docs/ai/STATE.yaml), and the sync-base planner names the range but not the dirty ledgers/INDEX it will archive and rewrite (plan.ledgers, plan.index, plan.removeEqual).",
          failure_scenario: "Owner runs plan before apply with a dirty docs/ai/EVENTS.jsonl tail on the origin: the preview shows 'main <a>..<b>' only and does not say the ledger will be archived and rewritten to the HEAD blob, which is the destructive-looking part the Codex thread asked to surface. No data loss (apply still archives first)." }
  cannot_verify:
    - { claim: "Suites (TEST-007/010/012/014 new arms) pass on this head and the frozen mutation anchors still bite", closes_with: "concurrent Validation round's suite + mutation-run evidence at a5e3f0ac (dispatch forbade running suites here); anchors verified textually still present: blobs.has(h.stdout.trim()) :291, rel !== STATE_REL && !fs.existsSync(dest), !mergedRefs(ctx).has(ref) in stateStep only" }
    - { claim: "remote_unknown wording on real network/auth failures of git ls-remote (stderr first line)", closes_with: "a live run against an unreachable origin; the test covers it only through a git shim" }
    - { claim: "Windows (Pester TEST-016) behaviour of the new plan targets and manifest-read report", closes_with: "CI windows leg green at a5e3f0ac after push" }
  overall: pass
```

## Scope and method

Delta only, per dispatch: `git diff 01050055..a5e3f0ac` (2 files: `.aai/scripts/merge-cleanup.mjs`, `tests/skills/test-aai-merge-cleanup.sh`). Each fix was judged against its Codex thread (scratchpad `codex-448.md`), then the surrounding engine was read for regressions (classifyDrafts, archiveFile, planSync, findRideWorktree, branchTip, mergedRefs/deliveredDoneRefs, stateStep, reportStep, runApplyOrPlan). Suites and mutation-run were not executed (dispatch: Validation runs them concurrently). No coaching in the dispatch beyond naming the delta and the four threads; nothing was scope-excluded.

## Thread-by-thread

1. **4237644336 revalidate before delete** — fixed. `classifyDrafts` now stores the classified sha256 (:291-292); `archiveDrafts` unlinks only when both the archived digest and a fresh read equal it, else retains `divergent_after_plan`, lists it under `remaining` as an owner decision (:892-893). Residual TOCTOU between the last read and `unlinkSync` is inherent to a filesystem without CAS-unlink and is microseconds wide. See NB-1 for the manifest side effect in the before-archive arm.
2. **4237644342 report lists every archived file** — fixed. `report.archived` is built from `manifest.jsonl` (:869-873), so runtime STATE/evidence (`worktree:`), the pre-clear origin STATE (`origin:`), sync ledger archives and an interrupted earlier run's drafts all appear. `ctx.archived` is gone with no remaining reader. INFO: in `plan` mode after a prior apply, `archived` lists those historical archives too; accurate but could read as part of the preview.
3. **4237644345 plan names concrete targets** — fixed for drafts, runtime archive, sync range, worktree and branch (:826-853); planners are pure reads (git ls-files/worktree list/rev-parse, `planSync` already pure and already run by `planChecks`, `deliveredDoneRefs` git reads only). Plan is proven write-free by TEST-010's `world_digest` equality and no-archive check. Gaps: NB-2.
4. **4237644348 ls-remote failure** — fixed. Non-zero exit now yields a `remote_unknown: ...` remaining item naming `origin/<headRef>` (:859-862); absent branch stays distinct (TEST-010 remote_absent arm with `unwanted` checks).

## Seam inertness

`racedEdit` (:344-346) reads through `seam()` (:123), which returns `undefined` unless `AAI_MERGE_CLEANUP_TEST_SEAMS === '1'`; `undefined === "<point>:<rel>"` is false, so a stray `AAI_MERGE_CLEANUP_EDIT_DRAFT` in production does nothing. Inert. INFO: the header comment at :22 still lists only `_GH_NODE, _STOP_AFTER, _CRASH_AT`; `_EDIT_DRAFT` is not named there.

## Deviations from the frozen spec (listed even though reasonable)

- New retained reason `divergent_after_plan` and new remaining item `remote_unknown` are not named in SPEC-0218 D6/D10 (additive, both strictly safer).
- Plan steps carry a new optional `targets` array (D2 grammar and exit codes unchanged).
- Report `archived` now includes non-draft archives (consistent with D7 manifest wording and Spec-AC-07 "report ... archived").

## Warning dispositions (recommended; orchestrator records)

- NB-1 (manifest false record on the before-archive race): **remediate-in-tree** — re-hash the source before `archiveFile` and skip the archive when it differs (the post-archive check can stay for the before-unlink window), and assert in TEST-007's before-archive arm that manifest.jsonl carries no record for the edited draft. Not eligible for (d): it leaves a false record.
- NB-2 (incomplete plan targets for state/sync-base): P3 assurance gap, no bite, no false record — recommended `accepted residual: plan names the sync range and focus ref but not the ledger/STATE archive paths those steps write first; apply still archives before every rewrite`, or promote to a follow-up if the owner wants a full preview.

## Next steps

Remediate NB-1 (one-line move of the hash check plus one assertion), let Validation's concurrent suite/mutation evidence close the first cannot_verify item, push, and re-run the bot sweep on PR #448 (reply to and resolve the four threads).
