# Code Review r3 — merge-cleanup-delete-remote-branch

```yaml
review:
  scope: "git diff 29e6c947..1af9e576 (branch change/merge-cleanup-delete-remote-branch, worktree; delta for Codex P1 thread 4241568204)"
  spec: docs/specs/SPEC-0222-spec-merge-cleanup-delete-remote-branch.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01..08, call: compliant, citation: "unchanged since r2 except the new early retention; whole suite 43/43 at 1af9e576 (validation r5), Pester TEST-016 rc 0, replay 9/9" }
      - { ac: Spec-AC-09, call: compliant, citation: "merge-cleanup.mjs:917-925 compares get-url --all with get-url --push --all; differ, >1 URL either side, or failed read -> remote_unknown before ls-remote (:926), gh pr list (:944-945) and push (:963); plan (:1349), apply (:959), stale-info re-read (:969) all go through remoteProof. TEST-044 pushurl + pushInsteadOf arms PASS; the >1-URL clause is verified by validator probe only (NON-BLOCKING-1)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-merge-cleanup.sh, line: 2737,
          issue: "TEST-044 never configures more than one URL, never asserts the failed-read arm, and never asserts that insteadOf on both sides still deletes; the length checks in merge-cleanup.mjs:925 are unguarded.",
          failure_scenario: "A later edit that drops `fetchUrls.length !== 1 || pushUrls.length !== 1 ||` keeps TEST-044 and the mutation gate green; an owner with two remote.origin.pushurl values (mirror push, first equal to the fetch URL) then gets the branch deleted on the second URL, which no proof read. Reproduced in a scratch mirror of 1af9e576 (docs/ai/validation/merge-cleanup-delete-remote-branch-r5/probe.log). Fix: a third arm with two pushurls asserting retained remote_unknown and the branch on both bares; optionally an insteadOf-both-sides arm asserting status done." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 917,
          issue: "Comment cites '(D2 step 3)'; the spec calls this check D2 step 2b (step 3 is the ls-remote read the comment refers to).",
          failure_scenario: "None at runtime; a reader searching the spec for the check's step number lands on the ls-remote step." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 188,
          issue: "Pre-existing, outside the delta: checkRepo reads raw remote.origin.url (pre-insteadOf) while every proof and the push use the rewritten URL.",
          failure_scenario: "origin url github.com/me/repo with insteadOf -> github.com/other/repo passes repo_mismatch; the lease plus ls-remote at the exact merged head limit any deletion to a same-named branch at the same commit in the rewritten repo. No action this round." }
  cannot_verify:
    - { claim: "get-url --push equals the push target on every git version the factory supports (probed on git 2.54 only)",
        closes_with: "CI legs (ubuntu/windows git) running TEST-044; both commands read the same remote struct since get-url was added in git 2.7" }
    - { claim: "Windows native get-url output (CRLF) compares equal",
        closes_with: "CI ps1-quality / windows leg; code trims each line, so CRLF is stripped" }
    - { claim: "Codex thread 4241568204 resolved on GitHub",
        closes_with: "reply + GraphQL resolveReviewThread after push (orchestrator)" }
  overall: pass
```

## Scope and preflight

- Worktree /Users/ales/Projects/aai-change-merge-cleanup-delete-remote-branch,
  HEAD 1af9e576 (not pushed), delta `29e6c947..1af9e576`: merge-cleanup.mjs
  (+9 lines in remoteProof), TEST-044 (+33 lines and selector wiring), spec
  (D2 step 2b, Spec-AC-09, TEST-044 row, mutation targets, frozen_sha256),
  decisions.jsonl amendment 12:33:41Z, CHANGELOG, product doc, INDEX
  timestamp, three docs_audit EVENTS lines.
- Dispatch focus areas were treated as questions, not severity ratings; the
  whole delta was read.
- Runs are shared with validation r5 (same agent, same HEAD): whole suite
  43/43, Pester TEST-016, replay 9/9, GATE PASS 9 rows, spec-lint, spec-amend
  --strict, docs-audit --gate, all exit 0. Logs in
  docs/ai/validation/merge-cleanup-delete-remote-branch-r5/.

## The fix (Codex P1)

Before the delta, `ls-remote origin`, `gh pr list` and the lease all read or
assumed the fetch repository, while `git push origin :refs/heads/<b>` went to
`remote.origin.pushurl` (or a pushInsteadOf rewrite). The new block asks git
itself for both lists (`get-url --all`, `get-url --push --all`) and proceeds
only on exactly one URL each, byte-equal. This is the right seam: it reuses
git's own rewriting rather than re-implementing insteadOf/pushInsteadOf, and
it does no normalization, so it can only err toward retention.

Verified first-hand (git-url-probe.log): in seven configurations — plain,
insteadOf only, pushurl plus insteadOf, pushInsteadOf only, explicit pushurl
plus pushInsteadOf, two pushurls, pushDefault/pushRemote set to another
remote — the list `get-url --push --all origin` prints is exactly where
`git push origin` landed. Two pushurls push to both, which is why the length
check matters. `remote.pushDefault` and `branch.<b>.pushRemote` do not apply
because the engine names `origin`.

Ordering: the block sits after the two local checks (ref-format name,
isCrossRepository) and before the only network reads. Plan, apply and the
stale-info re-read all call `remoteProof`, so the comparison repeats on the
re-read. The detail text names no URL (good: no credential-bearing URL in
reports).

## Test quality (TEST-044)

- Good: each arm puts the branch on a second bare at the merged head, so a
  missing check would make the lease succeed and visibly delete it there;
  both bares are asserted. The pushurl arm also asserts plan retention and
  that plan changes nothing (world digest). The recorded mutation
  (`fetchUrls[0] !== pushUrls[0]` -> `false`) reddens.
- Gap: NON-BLOCKING-1 above, reproduced.

## Amendment

Record 2026-10-11T12:33:41Z (remediation, contract, owner_signoff false,
tracked_by fu-amend-merge-cleanup-delete-rem-353ede) describes what the spec
diff contains; spec-amend list --strict exit 0. It needs the owner signature
like the earlier records for this ref (the /aai-merge direction signs them).

## Next steps

1. Recommended before push (cheap, about 10 lines): fold NON-BLOCKING-1 as a
   third TEST-044 arm; re-run TEST-044 and replay.
2. Push, wait for CI, reply to and resolve Codex thread 4241568204.

## state_update_commands

```bash
node .aai/scripts/state.mjs set-code-review --required true --status pass \
  --scope "29e6c947..1af9e576" --base-ref main \
  --report docs/ai/reviews/review-20261011T1308Z-merge-cleanup-delete-remote-branch-r3.md \
  --notes "r3 delta PASS: push/fetch URL comparison precedes every remote read and the push; NB-1 TEST-044 lacks a two-pushurl arm (length check unguarded, reproduced); NB-2 comment step number; NB-3 pre-existing checkRepo raw url"
```
