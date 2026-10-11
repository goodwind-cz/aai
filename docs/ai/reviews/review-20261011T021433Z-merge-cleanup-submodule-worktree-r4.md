```yaml
review:
  scope: c94ebbff..c21f2574 (delta round 4, branch fix/merge-cleanup-submodule-worktree)
  spec: docs/specs/SPEC-0221-spec-merge-cleanup-submodule-worktree.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "delta does not touch the D1/D2 paths; TEST-028 re-run PASS this round" }
      - { ac: Spec-AC-02, call: compliant, citation: "delta does not touch the dirty proof; r3 PASS; full suite run by the concurrent validator" }
      - { ac: Spec-AC-03, call: compliant, citation: "rev-list proof unchanged (merge-cleanup.mjs:692); TEST-035 unpushed arm still exits 3" }
      - { ac: Spec-AC-04, call: compliant, citation: "archiveSubmoduleIgnored unchanged; TEST-031 re-run PASS this round" }
      - { ac: Spec-AC-05, call: compliant, citation: "late worktreeVerdict still after both archives (merge-cleanup.mjs:863-866); r3 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "preflight untouched by the delta" }
      - { ac: Spec-AC-07, call: compliant, citation: "SKILL_MERGE.prompt.md untouched by the delta" }
      - { ac: Spec-AC-08, call: compliant, citation: "merge-cleanup.mjs:806-849,1244-1245; TEST-035 test-aai-merge-cleanup.sh:2444-2489 PASS this round" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 692,
          issue: "refs/notes/* is neither proved nor archived: the rev-list proof walks --branches --tags only, and D4b archives refs/tags only",
          failure_scenario: "in a ride submodule `git notes add -m x HEAD` on a pushed commit; proof count is 0 (probed, git 2.50); apply passes and --force deletes the notes commit, tree and blob, none of which are on any remote. Not named in R6 either." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 841,
          issue: "a tag whose target is not a commit keeps only its name and oid: the target object is not archived and the proof does not walk it",
          failure_scenario: "`git tag t $(echo x | git hash-object -w --stdin)` (blob), a tree tag, or a nested annotated tag whose inner tag ref was deleted: proof count 0 (probed), tags.txt records the oid, but the blob/tree/inner tag object goes with the git dir; the D4b restore recipe then creates a ref to a missing object." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 838,
          issue: "the manifest `original` for tag archives is a synthetic worktree path (`worktree:<sub>/.aai-submodule-tags/...`) that shares the namespace of real ignored files",
          failure_scenario: "a submodule that ignores a file at `.aai-submodule-tags/tags.txt` (or any file under that dir): archiveSubmoduleIgnored archives it to the same destBase first, the tag list lands at `tags.txt.1`, both manifest lines carry the identical `original`, and the D4b restore text ('tags.txt') points at the user's file. Nothing is lost (reason field differs), but the record reads as if the worktree held a file it never held." }
  cannot_verify:
    - { claim: "nested submodule tags are archived under worktree-submodules/<sub>/<nest>/.aai-submodule-tags", closes_with: "a TEST-035 arm with build_sub_world's nested member holding a tag (code path is the same submoduleMembers walk, so this is a coverage gap, not a suspected defect)" }
    - { claim: "tag-listing failure stops with submodule_unverifiable exit 4 at the archive step", closes_with: "a seam-driven arm like TEST-032's FAIL_IGNORED_LS for for-each-ref; no test reaches submoduleTags' stop()" }
    - { claim: "a tag created between archiveSubmoduleTags and the --force call is lost", closes_with: "same window class as R1; not named for refs in the Residual risks section" }
  overall: pass
```

# Code Review r4 (delta) — merge-cleanup-submodule-worktree

Scope: `c94ebbff..c21f2574` in `/Users/ales/Projects/aai-fix-merge-cleanup-submodule-worktree` (one commit, the fix for Codex P1 thread 4239924983 on PR #453).
Spec: `docs/specs/SPEC-0221-spec-merge-cleanup-submodule-worktree.md` (D4b, Spec-AC-08 and TEST-035 added as a contract amendment, decisions.jsonl 2026-10-11T02:07:54Z, tracked_by `fu-amend-merge-cleanup-submodule-d6d779`).
Dispatch coaching check: the dispatch listed questions to examine and did not pre-rate severity or exclude areas. Nothing to record.

## Judgement against the thread

The thread says local-only lightweight and annotated tags on pushed commits are lost by `--force`. The fix archives them before the removal: `tags.txt` (`<ref> <oid> <type>`) plus `objects/<oid>.tag` with the raw `git cat-file tag` bytes, both through `archiveFile` (sha256, reason `submodule_tags`). The thread's scenario is closed.

- Restorability, including signatures: probed in scratch. An SSH-signed annotated tag was archived with `cat-file tag`, its ref deleted and gc'd (the object was gone), then `git hash-object -t tag -w --stdin` restored it. The oid was identical (`544a495a…` both ways), so the signature survives byte-exact. The D4b recipe is correct.
- Nested submodules: `submoduleMembers` recurses, so a nested member gets its own `worktree-submodules/<sub>/<nest>/.aai-submodule-tags`. No path collision with the parent's dir. No test covers this (cannot_verify 1).
- Tag listing failure: `stop('submodule_unverifiable')` gives exit 4 and fails closed, both at apply and in the planner. No test reaches it (cannot_verify 2).
- Idempotence and resume: object files are keyed by oid, so their content is fixed. `tags.txt` is deduped by original+sha. If the tag set changed between runs, a `tags.txt.1` is written and nothing is overwritten. TEST-035 proves that a second apply appends nothing.
- Archive path collisions: NB-3.
- Is anything still lost? Yes, but outside the thread's scenario: NB-1 (refs/notes) and NB-2 (tag targets that are not commits). Both were probed under the same `rev-list --count HEAD --branches --tags --not --remotes` command, which printed 0.
- An unpushed commit is still refused. TEST-035's second arm shows that a commit reachable only from a local tag exits 3.

## Regression check

I re-ran TEST-028, TEST-031 and TEST-035 under `env -u AAI_ROLE`, and all PASS. The delta adds one call, `archiveSubmoduleTags`, after `archiveSubmoduleIgnored` and before `touchAt`/late verify, so TEST-032's seam ordering is unchanged. It also adds plan target lines that appear only when tags exist, so TEST-028..033 plan assertions on tagless worlds are unaffected. The concurrent validator runs the full suite.

## Warning dispositions (H6), recommended

- NB-1 (refs/notes unproved and unarchived): **promote to follow-up**, P3. Suggested id `fu-merge-submodule-notes-refs-lost`. Remedy: archive or prove `refs/notes/*` the way D4b does tags, or name it in R6.
- NB-2 (tag targets that are not commits): **accepted residual: a tag pointing at a blob, tree or deleted-ref inner tag keeps its name and oid but not the target object; no observed bite, P3 edge outside the thread's scenario.** Alternatively fold it into NB-1's follow-up and name it in Residual risks.
- NB-3 (synthetic `original` in the worktree namespace, collision with an ignored file of the same path): **remediate-in-tree if a round is open anyway.** Use an `original` such as `tags:<member>/...`. Otherwise promote to a follow-up. It leaves a misleading provenance record, so disposition (d) does not apply.

## Next steps

Merge readiness is unaffected (no BLOCKING finding). The orchestrator records the NB dispositions above, then runs set-code-review.
