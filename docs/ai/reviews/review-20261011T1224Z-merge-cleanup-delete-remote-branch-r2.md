# Code Review r2 — merge-cleanup-delete-remote-branch

```yaml
review:
  scope: "git diff 029e9884..2bc94ba0 (branch change/merge-cleanup-delete-remote-branch, worktree); focus delta a2a4e174..2bc94ba0"
  spec: docs/specs/SPEC-0222-spec-merge-cleanup-delete-remote-branch.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "merge-cleanup.mjs deleteRemoteBranch lease push + [deleted] -> done; TEST-036 PASS (re-run r2), Pester TEST-016 stub answers both dependents argv" }
      - { ac: Spec-AC-02, call: compliant, citation: "remoteProof remote_moved + lease CAS + stale-info re-read; TEST-037 (validation r4 whole suite 42/42)" }
      - { ac: Spec-AC-03, call: compliant, citation: "{ absent: true } -> noop remote_absent, also after stale re-read; TEST-038" }
      - { ac: Spec-AC-04, call: compliant, citation: "isCrossRepository === true -> remote_fork, !== false -> remote_unknown, before any read; TEST-039 PASS (re-run r2)" }
      - { ac: Spec-AC-05, call: compliant, citation: "remote_is_base / remote_bad_name; TEST-040" }
      - { ac: Spec-AC-06, call: compliant, citation: "remote_delete_rejected with hook text, ls-remote failure remote_unknown, never stop(); TEST-041" }
      - { ac: Spec-AC-07, call: compliant, citation: "SKILL_MERGE.prompt.md unchanged since r1; TEST-042" }
      - { ac: Spec-AC-08, call: compliant, citation: "merge-cleanup.mjs:935-943 two reads (--base, --head), either null -> remote_unknown, any number -> remote_has_dependents naming based-on / opened-from; TEST-043 four arms PASS (re-run r2); second post-freeze amendment 2026-10-11T12:05:04Z (unsigned, tracked)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 935,
          issue: "No recorded mutation row guards the --base read any more: the single TEST-043 row now drops the --head read. The base arm is behaviourally covered (validation r4 probes: const based = [] and dropping based === null both redden TEST-043) but mutation-run --replay no longer replays it.",
          failure_scenario: "A later edit that replaces the base read with [] keeps GATE PASS on replay; only the TEST-043 dependents arm (still in the suite) catches it. The suite catches it, the gate does not." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1339,
          issue: "Carried from r1 NON-BLOCKING-1 (unchanged): a fork PR reports origin/<b> retained (remote_fork) as an owner decision even when origin has no such branch.",
          failure_scenario: "Contributor PR from someone:fix-typo merged; remaining line asks the owner about origin/fix-typo, which does not exist." }
  cannot_verify:
    - { claim: "GitHub rejects protected/ruleset deletions with a ! porcelain line or non-zero exit (spec R1)",
        closes_with: "live push against a protected branch on a scratch GitHub repo" }
    - { claim: "gh pr list --head matches headRefName exactly, across same-repo and fork PRs, with no search-index lag",
        closes_with: "scratch GitHub repo with an open PR from the branch; gh pr list --help documents name-only filtering, and both directions of a mismatch fail toward retention or are covered by the lease only for moved refs" }
    - { claim: "Windows native parsing of ls-remote/push output (spec R5)",
        closes_with: "CI ps1-quality Pester TEST-016 on windows-latest" }
    - { claim: "the two Spec-AC-08 amendment records (11:40:03Z, 12:05:04Z) ship with the PR",
        closes_with: "git show <PR head>:docs/ai/decisions.jsonl contains both; at 2bc94ba0 they live only in the uncommitted worktree decisions.jsonl" }
  overall: pass
```

## Scope and preflight

- Worktree /Users/ales/Projects/aai-change-merge-cleanup-delete-remote-branch,
  `git diff 029e9884..2bc94ba0`; the remediation delta `a2a4e174..2bc94ba0`
  touches merge-cleanup.mjs, both gh stubs, TEST-043, the spec
  (D2 step 6, Spec-AC-08, TEST-043 row, frozen_sha256 restamp), INDEX and the
  r1 report. Uncommitted worktree files (EVENTS, decisions, roadmap,
  test-runs) are outside the range.
- Dispatch note: the dispatch named focus areas and summarised validation r4
  notes. Not treated as severity pre-ratings; the full range was re-read.
- Independent runs (env -u AAI_ROLE, aai-run-tests.sh): TEST-043, TEST-036,
  TEST-039 PASS. Validation r4 records the whole suite 42/42, Pester TEST-016,
  replay 8/8, GATE PASS.

## BLOCKING-1 (r1) — closed

`remoteProof` (merge-cleanup.mjs:935-943) now runs
`gh pr list --state open --base <b>` and `--head <b>` unconditionally (no
short-circuit), each through `dependentNumbers`, which returns null on spawn
error, timeout, non-zero exit or any non-integer row. Either null gives
`remote_unknown`; any number from either gives `remote_has_dependents` with
"based on it" / "opened from it". Plan, apply and the stale-info re-read all
call the same `remoteProof`, so both reads run in all three. The r1 repro
(PR #11 opened from `ride/foo` into another base) is now the TEST-043
head-of arm: plan and apply retain, bare ride/foo survives; the head-unlisted
arm fails closed. The merged PR itself cannot self-block (`--state open`,
MERGED proven by readAndGate). Stub argv is added in bash (separate
`heads-fail` / `heads-<key>.json`, independent of the base arm) and Pester
(exact argv answering `[]`). The amendment text matches the code.

## Search for any other wrongful deletion

Walked every path that reaches `git push ... :refs/heads/<b>`:

- Only `{ oid }` from remoteProof reaches the push; it requires valid name,
  `isCrossRepository === false`, readable ls-remote with a known default
  branch, `b` not base/default, remote at exactly the PR head oid, and both
  dependents reads empty. The push carries the lease at that oid.
- Stale-info path: a re-read that returns `{ oid }` falls through to
  `remote_delete_rejected`; no second push exists.
- Repository identity: gh dependents reads use the same implicit repo
  resolution as `gh pr view`, whose `url` checkRepo pins to
  `remote.origin.url`, so the dependents list is read from the same
  repository the push targets (local-path origin remains r1's cannot_verify).
- Residual, not a finding: an open PR created between the dependents read and
  the push is not seen (TOCTOU window of one push; the lease cannot express
  it). A `remote.origin.pushurl` different from the fetch URL would push to
  another repository, but the lease still only deletes a ref sitting at the
  merged head oid. Both INFO.

No remaining path found that deletes a branch the spec says to keep.

## Judgement of validation r4 notes

- NB-1 (base-arm mutation not recorded): agree non-blocking. The behaviour is
  guarded by a suite arm that runs in CI; only the replay gate lost it.
  Disposition: accept as a documented gap. If the owner wants the gate to
  hold it, split the head arm into its own TEST id in a later spec, not in
  this ride (it would be another amendment for a test-bookkeeping gain).
- NB-2 (fork same-name over-retention): agree harmless. `--head` filters by
  name only, so a fork PR from a same-named branch retains the same-repo
  branch with `remote_has_dependents`. That is the safe direction (owner
  relays), it cannot cause a deletion, and ride branch names
  (`change/...`, `ride/...`) make the collision rare. No action.
- NB-3..NB-7: agree; NB-4 worst-case latency (240 s per proof, 480 s with a
  re-read) is a latency bound, not safety.

## Warning dispositions (H6)

- NON-BLOCKING mutation gap: accept, documented (no follow-up required).
- NON-BLOCKING fork remaining line (carried r1): promote to follow-up
  `fu-merge-fork-remaining-line` (P3), filed by the orchestrator if not
  already.

## Next steps

1. Commit both Spec-AC-08 amendment records in docs/ai/decisions.jsonl with
   the PR.
2. Run (or cite CI full mode for) the pre-close full sweep, as validation r4
   noted; the last full sweep predates a2a4e174.
3. Proceed to PR.
