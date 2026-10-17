```yaml
review:
  scope: 7b024468..5d69bd13 (delta since r3, PR #471 bot-finding fixes; cumulative ride scope b6f740783f6df8885bfc49a56fb3b4225f7538e5..5d69bd13)
  spec: docs/specs/SPEC-0233-spec-release-command-finish.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: non-compliant, citation: ".aai/scripts/release-finish.mjs:167-187 — unnumbered side commits of a numbered 'Merge pull request #N' are now audited individually and refused; reproduced on a scratch fixture (see B-1). Spec body 3: complete noted history SHALL produce zero false REFUSE findings" }
      - { ac: Spec-AC-02, call: compliant, citation: "release-finish.mjs:427-431 watcher now --required (TEST-052); merge still --squash --match-head-commit after unchangedBase(); queued PR is never merged twice (TEST-053). Edge deviation N-2 (auto-merge armed + failed check reports PENDING instead of refusing) is NON-BLOCKING" }
      - { ac: Spec-AC-03, call: compliant, citation: "post-merge publication path unchanged in delta (release-finish.mjs:437-441); TEST-006" }
      - { ac: Spec-AC-04, call: compliant, citation: "base-busy: release-finish.mjs:243 ignores worker liveness once phase=updated (worker writes 'updated' only after read-tree returns, :259); processAlive :229-236 treats Z/X as dead; TEST-051, TEST-026; queued resume does not re-merge (TEST-053)" }
      - { ac: Spec-AC-05, call: compliant, citation: "no platform-frontend change in delta; processAlive skips the ps probe on win32 (:231); hosted evidence from r3 still covers the frontends" }
      - { ac: Spec-AC-06, call: compliant, citation: "docs/product/release-command-finish.md:48,51 describe required-only watching, merge-queue PENDING exit 8 and the unnumbered-commit rule; Limits :58 already disclaims a guarantee that every commit at the eventual merge was audited. Gap N-1 (SKILL_RELEASE exit-code list lacks 8) is NON-BLOCKING" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/release-finish.mjs, line: 183,
          issue: "Unnumbered commits that belong to a numbered PR are refused as missing-notes. git log prev..head lists the side-branch commits of a 'Merge pull request #N' merge (and every commit of a rebase-merged PR); the new !numbered branch requires each of them to add surviving notes itself or carry a no-notes: body line, although the PR is covered by notes naming #N. Before this delta they were skipped",
          failure_scenario: "Repo using GitHub's 'Create a merge commit' strategy: tag v0; PR branch commits 'wip: add b' and 'address review' touch .aai/scripts/b.mjs; merged as 'Merge pull request #12 from o/feat'; notes '## [v1] — feat: b (#12)'. New engine: audit prints both branch commits '(no PR number; ...)' -> --confirm refuses missing-notes; 7b024468 engine: zero findings. History is immutable, so the release can never be cut without a false no-notes edit. Same for a rebase-merged 3-commit PR whose notes are added by only one commit" }
      - { rank: NON-BLOCKING, file: .aai/SKILL_RELEASE.prompt.md, line: 78,
          issue: "Exit-code contract lists 0/1/10/11/12/13/15/16/20; the new finish exit 8 (PENDING: merge-queue) is absent, while the product doc (:53) says local exit codes are listed in the release skill",
          failure_scenario: "Agent runs /aai-release --confirm on a merge-queue repo, gets exit 8; the skill's table has no row for it, so the relay is unspecified (likely reported as a failure instead of 'queued, resume later')" }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 336,
          issue: "queuedOrRefuse treats any armed autoMergeRequest as merge-queue pending and returns before requiredChecks()",
          failure_scenario: "Someone arms auto-merge on the release PR in a repo without a merge queue, then a required check fails. Every resume exits 8 'PENDING: merge-queue ... queued in the merge queue' forever; the failed check is never named and Spec-AC-02's refusal of failed checks is not reached (no merge happens, so no safety loss)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 171,
          issue: "Unnumbered merge commits are skipped wholesale; content introduced by the merge itself (conflict resolution / evil merge) is not audited, and no test exercises an unnumbered merge commit",
          failure_scenario: "Direct push of 'Merge branch x' whose conflict resolution adds a new .aai/ file absent from both parents: the side commits are audited, the added file is not. Deleting the skip line fails no test" }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 234,
          issue: "processAlive returns false (dead) whenever ps exits 1 with empty stdout, without distinguishing 'no such process' from a failing ps",
          failure_scenario: "Non-Linux host without /proc where ps is restricted or a stripped ps rejects '-o stat= -p' with rc 1 and nothing on stdout: a live claim owner or live base worker is read as dead and its lock is reclaimed. Not reproducible on stock macOS/BSD ps (rc 1 only for an absent pid)" }
  cannot_verify:
    - { claim: "gh pr merge --squash --match-head-commit on a merge-queue base enqueues (not errors) and gh pr view exposes isInMergeQueue/autoMergeRequest with these semantics", closes_with: "One live release on a repository with a required merge queue; the fixture models only the happy queue path" }
    - { claim: "Queue ejection recovery: ejected PR (OPEN, not queued) is re-enqueued on resume only if the base did not move; in a busy queue repo the base usually moves and resume refuses base-moved", closes_with: "Live queue-ejection run; currently no test. Conservative (refuses, retains journal), so not a defect" }
    - { claim: "Release merged by a queue on a moved base absorbs commits the audit did not see", closes_with: "Not closable client-side; covered generically by product doc Limits :58 ('no ... guarantee that every commit at the eventual merge was audited')" }
  overall: fail
```

# Independent Code Review r4 - release-command-finish

**Verdict: FAIL.** One BLOCKING regression in the audit fix (B-1). The other four bot findings are resolved. Four NON-BLOCKING items.

## Scope

- Worktree `/Users/ales/Projects/aai-change-release-finish-one-command`, HEAD `5d69bd13`, branch `change/release-command-finish-ship`.
- Delta: `git diff 7b024468..5d69bd13` (commit `5d69bd13`): `.aai/scripts/release-finish.mjs`, `.aai/scripts/watch-ci.mjs`, `tests/skills/test-aai-release.sh` (TEST-050..053, TEST-012 fixture body), `CHANGELOG.md`, `docs/product/release-command-finish.md`, `docs/INDEX.md`.
- Bot threads: `gh api repos/goodwind-cz/aai/pulls/471/comments` (Codex P1 x2, P2 x2; Copilot HEAD-lock comment).
- Dispatch note: the prompt named areas to look at but did not pre-rate severity or exclude any area. No coaching recorded. The whole delta was reviewed.

## Bot findings

| Thread | Finding | Status |
|---|---|---|
| 4302628397 (P1) | Unnumbered shipped commits skipped by the audit | Bypass closed (TEST-050), but the fix over-reaches: see B-1 |
| 4302628401 (P1) | Zombie worker keeps base-busy forever | Resolved two ways. Worker liveness is ignored once `phase=updated` (:243), and the worker writes that phase only after `read-tree` has returned (:259), so this is safe. `processAlive` also treats Z/X as dead (/proc on Linux, `ps` elsewhere, skipped on win32 where libuv `kill(pid,0)` already reports exited processes as ESRCH). TEST-051 makes a real zombie |
| 4302628404 (P2) | Optional checks block the watcher | Resolved. `--required` is opt-in in watch-ci (default argv unchanged, so the SKILL_PR caller at `.aai/SKILL_PR.prompt.md:301` is unaffected). TEST-052 asserts every poll carries `--required` |
| 4302628407 (P2) | Merge queue enqueues, engine refuses | Resolved as a named PENDING exit 8 plus a resume command instead of in-process polling. Resume while queued does not merge again; a merged queue completes (TEST-053). See N-1 and N-2 |
| Copilot | HEAD-lock comment overstated | Resolved. Comment at :204-206 now matches the mechanism |

## Findings

### B-1 BLOCKING: false missing-notes for commits that belong to a numbered PR

`release-finish.mjs:183-187`. The audit walks `git log prev..head` without `--first-parent`. That list includes:

- every side-branch commit of a `Merge pull request #N` merge, and
- every commit of a rebase-merged PR.

Before this delta these unnumbered commits hit `continue`. Now each one needs notes it added itself, or a `no-notes:` line in its own body. Notes that name `#N` do not count for them, even though the merge commit is audited and covered by those notes.

I reproduced this on a scratch repo under the session scratchpad:

- **Setup:** tag `v0`, then two branch commits touching `.aai/scripts/b.mjs`, then `--no-ff` merge `Merge pull request #12 from o/feat`. The notes file was `## [v1] — feat: b (#12)`.
- **5d69bd13:** `--audit` lists `db7b75ce address review` and `13df7ef7 wip: add b`, both marked "no PR number". `--confirm` would refuse `missing-notes`.
- **7b024468:** no findings.

Repos that merge with merge commits therefore can never release a range that contains such a PR. The commits are already in history, so the only escape is a false exemption. Spec body item 3 requires zero false REFUSE findings for complete noted history. This contradicts it, so Spec-AC-01 is non-compliant. No test covers merge-commit history: there is no `--no-ff` or `Merge pull request` fixture in `tests/skills/test-aai-release.sh`.

Recommended fix (remediate in tree):

1. For every numbered merge commit M, treat the commits in `M^1..M^2` as covered by PR #N. M's own diff against `parents[1]` is audited already.
2. For the remaining unnumbered commits on the online path, resolve the PR through `gh api repos/{repo}/commits/{sha}/pulls`, as the bot suggested. When a PR is found, apply the numbered rules. Only a commit with no PR at all should need notes it added or a no-notes body.
3. Add TEST-050 arms for a `--no-ff` numbered merge with unnumbered branch commits (must pass) and for an unnumbered merge (the skip at :171).

### N-1 NON-BLOCKING: exit 8 missing from the release skill's exit-code contract

`.aai/SKILL_RELEASE.prompt.md:78-86` and the `aai-release.sh:24` / `aai-release.ps1:19` headers. The product doc (:53) points readers to the skill for exit codes. Disposition: **remediate in tree** with one line, for example "exit 8 = finish pending (merge queue); relay PENDING and the resume command". Follow the prompt-corpus checklist (diet ledger / TEST-012 bump) if needed.

### N-2 NON-BLOCKING: an armed auto-merge reads as merge-queue pending

`release-finish.mjs:333-337`. `autoMergeRequest` short-circuits before `requiredChecks()`, so a failed required check behind an armed auto-merge is never named. The message also says "merge queue" when there is none. Disposition: **remediate in tree**. Count only `isInMergeQueue===true` as pending. Alternatively, evaluate `requiredChecks()` first and refuse on fail or cancel.

### N-3 NON-BLOCKING: unnumbered merge skip is untested and does not audit merge-introduced content

`release-finish.mjs:171`. Disposition: **remediate in tree together with B-1** by adding the unnumbered-merge test arm. The evil-merge residual can then be recorded as an accepted residual (P3, assurance strength).

### N-4 NON-BLOCKING: `ps` exit 1 with empty stdout reads as a dead process

`release-finish.mjs:234`. A broken or restricted `ps` on a /proc-less host fails open. Disposition: **accepted residual (P3, assurance strength)** unless cheap to tighten. Stock macOS ps was checked locally: rc 1 with empty stdout only for an absent pid; `Ss` and rc 0 for a live one.

## Regression checks requested by the dispatch

- **Release commits:** an unnumbered `chore(release): vX` whose payload is CHANGELOG plus AAI_VERSION is still exempt, because the release exemption at :182 runs before the `!numbered` branch.
- **Reverts:** a local `Revert "..."` touching shipped paths now needs notes or a no-notes body. That is intended (it is a shipped change). A GitHub revert PR is numbered and unchanged.
- **Real history replay:** `--audit` was replayed on scratch clones at the bases of the v2026.09.21, v2026.08.29, v2026.10.17 and v2026.10.12 cuts. The only new unnumbered finding was `65fdfdc9 chore(close)`, a genuine direct push touching shipped paths, which is intended. The numbered findings in those replays pre-date this delta.
- **Fail-open:** `queuedOrRefuse` degrades to the old behaviour on gh error or an unknown JSON field: q=null, then the existing refuse path. `processAlive` returns alive when `ps` is absent (ENOENT), which is conservative. N-4 is the only fail-open edge.
- **Windows:** `ps` is never spawned on win32 (:231).
- **watch-ci other callers:** the flag is opt-in and the default argv is byte-identical.
- **Exit 8 and resume idempotency:** the claim is released in `finally`, and the journal stage stays at the PR stage. Resume checks the queue before `unchangedBase` or merge, so there is no double enqueue (TEST-053). Queue ejection leaves the PR OPEN and unqueued. Resume then re-runs base, checks and merge, and refuses `base-moved` if the base advanced (see cannot_verify).

## Test evidence

- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh` at 5d69bd13: `=== aai-release: ALL TESTS PASSED ===` (TEST-050/051/052/053, TEST-012, TEST-026 PASS). The wrapper's AAI-TRIPWIRE line names only this report, which the reviewer wrote while the suite ran; it is not a suite defect. TEST-034 ('all non-zero exit codes documented') passes although exit 8 is undocumented, because it does not parse release-finish.mjs exit codes. That is an N-1 coverage gap.
- B-1 reproduction: scratch repo under the session scratchpad (`mq/`). Commands are in the B-1 narrative; old engine taken from `git show 7b024468:.aai/scripts/release-finish.mjs`.

## Next steps

1. Remediate B-1 together with N-3 (new TEST-050 arms), then N-1 and N-2 in the same round.
2. Re-run `tests/skills/test-aai-release.sh` and request review r5 on the new delta.
