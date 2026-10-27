```yaml
review:
  scope: "87ab5a8c..67186ba4 (c52325ef, 67186ba4) in /private/tmp/aai-relrec, branch change/release-same-version-recovery, PR #506 — round 3 delta"
  spec: docs/specs/SPEC-0255-spec-release-same-version-recovery.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "untouched by delta; r2 PASS stands (re-cut push path unchanged)" }
      - { ac: Spec-AC-02, call: compliant, citation: "untouched by delta; r2 PASS stands" }
      - { ac: Spec-AC-03, call: compliant, citation: "amended merged-old-head clause: .aai/scripts/release-finish.mjs:652-657 (MERGED on last recuts fromHead -> restoreMergedBinding(...,true); otherwise refuse identity naming both SHAs); TEST-123 / test_751 green here; mutation sed of TEST-123 reddens it (re-run in scratch copy)" }
      - { ac: Spec-AC-04, call: compliant, citation: "untouched; restoreMergedBinding extraction (release-finish.mjs:388-407) keeps abandonRecut behaviour identical (dropLastRecut=false path is the old body)" }
      - { ac: Spec-AC-05, call: compliant, citation: "untouched by delta" }
      - { ac: Spec-AC-06, call: compliant, citation: "untouched by delta" }
      - { ac: Spec-AC-07, call: compliant, citation: "untouched by delta" }
      - { ac: Spec-AC-08, call: compliant, citation: "delta adds no forbidden phrase (0 matches of new --version/newly audited/fresh audited in added lines); product doc still contains re-cut, --force-with-lease, release-preflight, base-moved, deliberate repair; SKILL_RELEASE untouched" }
      - { ac: Spec-AC-09, call: cannot-verify, citation: "TEST-115 live acceptance, deferred as in r2" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 388,
          issue: "abandonRecut's pushed-but-unjournaled branch (remote at record.head != cut.fromHead, PR MERGED on cut.fromHead) calls restoreMergedBinding(cut,false) and never adds the pushed re-cut head to `superseded`, so the new cleanup tolerance does not cover it",
          failure_scenario: "re-cut leased push succeeds, process dies before the recuts journal write, GitHub merges the old head; resume publishes the release correctly, then every run refuses cleanup-head-moved with the remote branch on the re-cut head (Validation r3 R1, probe TEST-990). Fail-closed after publication; manual branch delete recovers." }
  cannot_verify:
    - { claim: "GitHub really can report MERGED on the pre-push head after a force-push was accepted (the race the fix targets) and the squash merge commit is then the merge SHA release.yml tags",
        closes_with: "live observation or GitHub docs on PR head sync vs merge; the stub (mergeOldHead) models it" }
    - { claim: "Spec-AC-09 live acceptance (TEST-115)", closes_with: "run with AAI_RELEASE_LIVE_ACCEPTANCE=v2026.10.26 after the live release" }
  overall: pass
```

security_relevant: false

# Code Review — release-same-version-recovery, round 3 delta

Scope: `git diff 87ab5a8c..HEAD` (HEAD 67186ba4) in /private/tmp/aai-relrec — c52325ef (fix) and 67186ba4 (ledger close). Spec: SPEC-0255 (amended D11(e), Spec-AC-03, TEST-123 row, mutation-target range). No coaching in the dispatch: the ride context describes the change, does not pre-rate findings or exclude areas.

## What changed (read in full)
- `restoreMergedBinding(cut, dropLastRecut)` extracted from `abandonRecut`; the `false` path is byte-for-byte the previous body, the `true` path additionally drops the last `recuts` entry and appends its `toHead` to `superseded`.
- Post-push poll (release-finish.mjs:648-658): PR not OPEN and head != record.head → restore only when MERGED on `last.fromHead` (non-null), else refuse `identity` with both SHAs.
- `journalShape` accepts optional `superseded` (array of full SHAs); additive, old journals load unchanged. No other reader of the journal exists (grep: only the engine and the suite).
- Cleanup (line 706): remote head may be `record.head` or a `superseded` SHA; lease is now on the observed head — equivalent safety since the head is validated against the same allow-list immediately before.

## Correctness walk
- Resume safety: if the poll times out (PR still OPEN on the old head) and GitHub later merges the old head, the journal stays at stage `pushed` with the recuts entry, the start-of-run reconcile returns early for a MERGED PR with no pending `recut`, and the poll block re-runs and takes the restore path. A crash inside `restoreMergedBinding` before `stage('pr')` is idempotent (local branch already gone → `ours`).
- After restore, `identity()` compares the PR head with `record.head` = `fromHead` = merged head; notes recomputed from `fromBase` match what the merged CHANGELOG carries (verified against the blob before any mutation).
- `last` is always defined on this path (block guarded by `recuts.length`).

## Tests and evidence (re-run here, scratch copy of HEAD)
- `test_751_merged_old_head_after_recut_push` → PASS.
- TEST-123 mutation (`if(false)`) → FAIL (bites).
- Extra mutation, removing the `superseded` cleanup tolerance → FAIL (the `releaseRef(f)===''` assertion covers it).
- Spec's TEST-123 Mutation cell parses and applies (single match).

## Findings
- NB-1 (above), already found by Validation r3 as R1. **Recommended disposition: (b) follow-up** — `fu-release-unjournaled-recut-merged-old` (P3) is present in the worktree's `docs/ai/decisions.jsonl` but uncommitted at review time; the orchestrator must commit it with the ride. Fix direction: in `abandonRecut`'s restore path, record the remote re-cut head in `superseded` when remote == record.head != cut.fromHead.
- INFO: dropping the recuts entry loses its `fromBase/toBase/at` from the journal (only `toHead` survives in `superseded`); no failure mode, as spec D11(e) prescribes.

## cannot_verify
See the YAML block: GitHub's real race behaviour (stub-modelled only) and the deferred live acceptance TEST-115.

## Next steps
Commit the filed follow-up line; overall PASS/PASS for the delta.
