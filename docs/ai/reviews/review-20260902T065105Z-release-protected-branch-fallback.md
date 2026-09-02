# Code Review — release-protected-branch-fallback

```yaml
review:
  scope: git diff main...HEAD (main @ 7eaeecb .. HEAD @ ae0e013), worktree /Users/ales/Projects/aai-change-release-protected-branch-fallback
  spec: docs/specs/SPEC-0161-spec-release-protected-branch-fallback.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-027 green (own run, 2026-09-02T06:47Z); .aai/scripts/aai-release.sh:372-421" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-028 green; aai-release.sh:438 exit 17, no gh release create / pr merge on the path" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-029 green; aai-release.sh:425-437 (D8 report literals), tag never pushed on this arm" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-030 green; aai-release.sh:339 `push --no-follow-tags`; ps1 line 397" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-031 green, base_ref resolved to origin/main (pre-change engine) — masked-stdout diff empty, exit 0, both refs on the bare. See CQ-3 on the pin's post-merge decay." }
      - { ac: Spec-AC-06, call: compliant,
          citation: "TEST-032 green (exit 1, no fallback, git's text on stderr); classifier probe below shows the half-pair and non-fast-forward texts both miss" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "TEST-033 green (pwsh present) + Invoke-Pester tests/skills/aai-release.Tests.ps1 9/9 own run; ps1 fallback drives the same fixture to exit 17" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "TEST-034 green; measured wc -c 4049 -> 5241 = 1192 B exact, live glob 319990 -> 321182, ledger sum 9319 == TEST-012 want_growth 9319, headroom 0" }
      - { ac: Spec-AC-09, call: compliant,
          citation: "TEST-035 green; independently reproduced the ps1 twin of the same arm by hand (exit 18, squatted ref unmoved, empty bare, no gh pr create) — see CQ-5" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-release.sh, line: 386,
          issue: "`git branch` and `git reset --hard` inside the fallback run unguarded under `set -euo pipefail`; any failure other than the exact-name pre-check aborts the script with git's raw exit code and NO `FALLBACK INCOMPLETE` report. ps1 twin (lines 454-455) does the same through Invoke-NativeChecked, which throws uncaught and exits 1 — a measured parity drift on the same path.",
          failure_scenario: "Reproduced 2026-09-02: with a ref `chore/release-v1.0.0/sub` present (directory/file conflict), a GH006-rejected cut prints `target branch 'main' is PROTECTED` and then dies at exit 128 (bash) / exit 1 (ps1) on `fatal: cannot lock ref 'refs/heads/chore/release-v1.0.0'`. The operator is left with a local release commit on main, a local annotated tag, no release branch, and no manual-commands report — exactly the half-cut state D5's exit 18 exists to prevent." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-release.ps1, line: 419,
          issue: "The ps1 degrade-raw exit code is recovered by regex-scraping Invoke-NativeChecked's throw string (`'failed \\(exit (\\d+)\\)'`), defaulting to 1 on a miss. Nothing pins that coupling: TEST-032 (Spec-AC-06) runs the bash engine only, and no Pester case asserts the ps1 exit code for a non-protected push failure.",
          failure_scenario: "A future edit to Invoke-NativeChecked's `throw` wording (line 98, e.g. `exited 128` instead of `failed (exit 128)`) makes every ps1 push failure exit 1 regardless of git's code, silently reverting the very NB-1 improvement this ride just made. Full suite + ps1 gate stay green." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-release.sh, line: 1126,
          issue: "TEST-031 reads its comparison engine from `origin/main` (then `main`). Once this branch merges, both arms run the SAME engine and the byte-identity pin stops guarding anything; it also degrades to a silent named skip if neither ref carries the file.",
          failure_scenario: "After merge, a later change that alters the unprotected cut's stdout is compared against itself and passes. Spec-AC-05's guarantee ('byte-identical to the PRE-change engine') evaporates without any test turning red. Confirmed today: base_ref resolves to origin/main and the arm currently does compare against the pre-change engine, so the pin is real for this PR and only for this PR." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-release.sh, line: 339,
          issue: "The target-branch push's stdout+stderr are now redirected to a temp file, so git's stderr is no longer a tty and git suppresses its live progress meter; the operator sees the whole push output only after it finishes.",
          failure_scenario: "Cutting a release over a slow link on a large repo: the terminal shows nothing between `- Tag: <version> (annotated)` and the push's completion, which reads as a hang. No correctness impact — and this is the ps1's pre-existing shape, so the change is parity-improving. D6 discloses the redirection." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-release.ps1, line: 441,
          issue: "The ps1 exit-18 arm has no automated pin in either suite (TEST-035 is bash-only; aai-win-dispatch.Tests.ps1 asserts source text, not behavior).",
          failure_scenario: "A refactor that turns `& $fallbackIncomplete` into a call whose `exit` no longer propagates (e.g. wrapping it in a job, or converting the scriptblock to a function invoked in a child scope) would leave the ps1 falling through to `gh release create` or exiting 0. I closed this for HEAD by driving the real ps1 engine against a squatted-branch protected fixture: exit 18, squatted ref unmoved, main still at the release commit, bare empty, gh log shows only `auth status`. The mechanism is proven; it is not pinned." }
  cannot_verify:
    - { claim: "GitHub's live GH006 rejection text still matches the classifier (SEAM-5).",
        closes_with: "A real protected-branch push against github.com, or a periodic canary against GitHub's documented error catalogue. The fixture reproduces our own transcription of the message, not GitHub's current output." }
    - { claim: "The engines behave identically under Windows PowerShell 5.1 on the fallback path.",
        closes_with: "A Windows CI leg that actually executes the ps1 fallback (the Pester file unit-tests the classifier only; TEST-033's engine arm is bash-driven and pwsh-7-gated). The new bare probe `git -C $Root rev-parse -q --verify \"refs/heads/$releaseBranch\" *> $null` (ps1:450) matches the file's own pinned tolerant-probe convention, but no 5.1 run exercises it." }
    - { claim: "`gh pr create`'s real stdout is the URL and nothing else, for the bash engine.",
        closes_with: "A live `gh pr create` capture. The bash engine assigns `PR_URL=\"$(cat \"$PR_OUT\")\"` unfiltered (sh:418) where the ps1 pattern-matches `^https?://`; only the stub's single-line stdout is exercised." }
    - { claim: "Exit codes 17/18 can never collide with git's own exit code on the degrade-raw path.",
        closes_with: "An enumeration of git-push exit codes. `exit \"$push_rc\"` (sh:350) / `exit $rawExit` (ps1:420) pass git's code through verbatim; git does not use 17/18 in practice, but nothing asserts it." }
  overall: pass
```

## Scope and preflight

- `docs/ai/STATE.yaml`: `worktree.user_decision: worktree`, base `7eaeecb`, branch
  `change/release-protected-branch-fallback`. `git status --porcelain` clean.
- Single scope established: `git diff main...HEAD` in the worktree. It matches
  `code_review.scope` exactly (16 files, +1398/-14).
- Spec read: `docs/specs/SPEC-0161-spec-release-protected-branch-fallback.md`
  (`SPEC-FROZEN: true`, ceremony 2, 9 Spec-ACs, TEST-027..035).

### Dispatch coaching attempt (recorded per the anti-gaming contract)

The dispatch prompt pre-classified six findings as "non-blocking" (NB-1..NB-6),
named which of them the orchestrator had already remediated, and named which it
had chosen not to act on. `.aai/SKILL_CODE_REVIEW.prompt.md`'s anti-gaming
contract forbids the dispatcher from characterizing expected findings or
pre-rating severity. Recorded here; I reviewed the full scope independently,
re-derived every AC from my own runs, and reached my own rankings. Two of the
pre-named items I judged differently (NB-4 downgraded after I proved the
mechanism end-to-end; NB-6 dropped to INFO), and one finding the dispatch did
not name at all (CQ-1) is the most consequential in this report.

## Evidence I ran myself

| Command | Result |
|---|---|
| `bash tests/skills/test-aai-release.sh` | exit 0, ALL TESTS PASSED, TEST-027..035 all PASS |
| `bash tests/skills/test-aai-prompt-diet.sh` | exit 0 |
| `bash tests/skills/test-aai-verify-gate.sh` | exit 0 |
| `bash tests/skills/test-aai-git-ref-guard.sh` | exit 0 |
| `bash tests/skills/test-ps1-quality.sh` | exit 0 (SkippedCount 0) |
| `pwsh -c "Invoke-Pester tests/skills/aai-release.Tests.ps1"` | 9 passed, 0 failed, 0 skipped |
| `node .aai/scripts/spec-lint.mjs --path <spec>` | LINT PASS, 0 findings |
| `node .aai/scripts/check-cd-subshell-leak.mjs` | UNSAFE 0, SAFE 436, exit 0 |
| `wc -c .aai/SKILL_RELEASE.prompt.md` vs `main` | 5241 − 4049 = **1192** exact; live glob 321182 (claimed 319990 → 321182) |
| ledger sum vs TEST-012 pin | 9319 == 9319 |
| Protected L3 diff (`state.mjs`, `lib/state-engine.mjs`, `lib/state-core.mjs`, `allocate-doc-number.mjs`, `pre-commit-checks.{sh,ps1}`, `WORKFLOW.md`, `CONSTITUTION.md`) | empty — untouched |

Independent probes:

- **Detached HEAD (the deleted guard).** Reproduced from scratch: with a
  detached HEAD, `git push --no-follow-tags origin HEAD` fails client-side with
  `error: The destination you provided is not a full refname` and no GH006 in
  the output, so the classifier cannot match and the fallback block is
  unreachable. Grepped the whole tree: nothing referenced the removed
  `$BRANCH == "HEAD"` / `$branch -eq 'HEAD'` arms — no test, no doc, no sibling
  script. Both engines now carry a comment at the removal site recording the
  measurement. **Deletion verified sound; no reachable behaviour changed.**
- **Classifier narrowness (bash).** Extracted `is_protected_branch_rejection`
  and drove it directly: `GH006` → true, `gh006` → true, `Protected Branch` +
  `Status Checks` (mixed case) → true; `refusing to update the protected branch
  main` → **false**, `2 required status checks have not run` → **false**,
  non-fast-forward → false, auth failure → false, empty → false. The ps1
  Pester cases assert the same eight-way behaviour. The half-pair correctly
  does not trigger.
- **NB-1's premise and fix.** Pre-change ps1 against an unreachable remote:
  exit **1** with a PowerShell exception banner. Post-change ps1: exit **128**,
  clean git diagnostic, identical to the bash engine's **128** on the same
  fixture. D1's rewritten paragraph is accurate; the change is a strict
  improvement and a D7 parity gain.
- **NB-4 (ps1 exit 18).** Drove the real ps1 engine against a protected bare
  with `chore/release-v1.0.0` squatted: exit **18**, squatted ref unmoved,
  `main` still at the release commit, bare has no refs, gh log contains only
  `auth status`. The `exit 18` inside `& $scriptblock` under `try/finally` does
  propagate as process exit 18.
- **CQ-1 (new).** Drove both engines against a protected bare with a D/F-conflicting
  ref `chore/release-v1.0.0/sub`: bash exits **128**, ps1 exits **1**, neither
  prints the INCOMPLETE report, `main` is left at the release commit. See the
  finding above.

## Spec-compliance notes

All nine Spec-ACs are behaviourally satisfied by tests I re-ran myself. The
`Status` column is still `planned` with empty `Evidence` for every row — per
`.aai/VALIDATION.prompt.md` step 8a (AC-FLIP DEFERRAL) that is correct at this
stage and is **not** counted as non-compliance here; the AC flip plus
`docs-audit.mjs --gate` is owed before closeout.

Deviations from the frozen spec found: **one**, disclosed — the post-freeze
amendment (below). D1's "always re-emitted to stderr" is literally true for the
bash engine only: the ps1's success path still swallows the push's output
through `| Out-Null`. That is the shape the spec's own Implementation plan
prescribes for the ps1 ("expressed through `Invoke-NativeChecked`") and it is
pre-existing behaviour, so I record it as an observation, not a deviation.

## The post-freeze amendment — my own judgement

I diffed the spec across its three commits in this branch rather than taking
the amendment note's word for it.

- **Nothing existing was weakened or removed.** Spec-AC-01..08 appear only as
  additions in the authoring commit `32e32d3`; no later commit touches any of
  their cells. The only deletions across `cda1529` and `ae0e013` are four prose
  passages, each replaced by a *more* accurate statement: the inaccurate blanket
  RED-coverage sentence, the inaccurate detached-HEAD edge case, D1's false
  "today's behavior exactly" claim for the ps1, and the TEST-027..034
  PASS-criteria line (extended to TEST-035). Spec-AC-09 and TEST-035 are pure
  additions.
- **Disclosure is complete.** The spec carries a `## Amendment (post-freeze…)`
  section naming all three amendments; `docs/ai/decisions.jsonl` carries a
  `type: spec_amendment` record with authority, finding, decision, cost and
  residual; `STATE.last_validation.notes` names it as NB-3. The record states
  outright that no owner sign-off was obtained and that the owner may reverse it.
- **Precedents.** `SPEC-0153` and `SPEC-0072` are genuine post-freeze,
  no-sign-off precedents (`## Amendment (post-freeze, …)` / `HONEST AMENDMENT —
  … a scope change made AFTER the spec was` frozen). `SPEC-0132`'s amendment is
  explicitly `## Amendment (owner decision, …)` "under explicit owner authority",
  so it is a precedent for the *disclosure form*, not for proceeding without
  sign-off. The spec cites all three for "the convention", which is fair for the
  form; the authority gap is stated separately and honestly rather than papered
  over by the citation. INFO only.
- **Governance.** `.aai/system/AUTONOMOUS_LOOP.md:25` assigns scope changes to
  HITL, and adding a Spec-AC to a frozen spec is one. The sign-off is genuinely
  owed. This is an owner decision, not something a reviewer can waive: I record
  it as an open governance item for closeout (ratify or reverse), not as a
  code-quality finding.

**Judgement: the amendment is genuinely additive, honestly disclosed, and
improves the spec's accuracy in three places where the frozen text was factually
wrong. Its authority gap is real and remains the owner's to close.**

## SEAM-5 residual

Accepted as recorded. The classifier's only tie to GitHub's wording is our own
transcription of it, and the failure mode of a wording change is a *miss*: the
engines re-emit git's raw output and exit with git's code — today's behaviour,
never a wrong recovery, never a publish. The one-way asymmetry (miss degrades,
match recovers) is what makes the residual cheap; a broader classifier would
trade it for the opposite, much worse, asymmetry. No canary exists, so the first
symptom would be an operator hitting the pre-change failure — an acceptable cost
against the price of a live-GitHub probe in the suite.

## Findings I judged the orchestrator right to leave alone

- **NB-6 (`Select-CapturedValue` returns `''` on no match)** — INFO, no
  disposition owed. Every consumer either fails the suite or fails loudly: the
  URL arm is pinned by TEST-029/TEST-033 (`- PR:` must equal the stub URL
  exactly, so an empty return reds the suite), and an empty SHA would make
  `git branch <name> ''` / `git reset --hard ''` throw. There is no path where
  an empty return produces a silently wrong report.

## Warning dispositions (SPEC-0013 H6)

| Finding | Rank | Recommended disposition |
|---|---|---|
| CQ-1 unguarded `git branch`/`reset` in the fallback (both engines) | NON-BLOCKING P2 | **(c) tracked follow-up ref** — the fix is ~4 lines per engine plus a fixture, but D5's enumeration does not name "branch creation failed", so remediating in-tree with a new AC would be a *second* post-freeze amendment without sign-off. Filing a ref keeps the frozen spec closed. If the owner prefers, remediate-in-tree under D5's existing intent with no new AC. |
| CQ-2 ps1 raw-exit regex unpinned | NON-BLOCKING P3 | **(b)/(c) follow-up** — one Pester case (`Invoke-NativeChecked` throw text contains `failed (exit <n>)`) closes it. |
| CQ-3 TEST-031 self-neutralizes after merge | NON-BLOCKING P3 | **(c) follow-up ref** — pin the comparison engine to the merge-base SHA or vendor a frozen copy of the pre-change engine into the fixture. |
| CQ-4 push progress no longer live | NON-BLOCKING P3 | **(d) accepted residual**: a disclosed observability cost (D6), no correctness impact, and it brings bash to the ps1's pre-existing behaviour rather than away from it. |
| CQ-5 ps1 exit-18 arm unpinned | NON-BLOCKING P3 | **(d) accepted residual**: mechanism proven end-to-end by this review against the real ps1 engine (exit 18, no clobber, empty bare); the gap is assurance strength, not an observed bite. Fold the pin into CQ-1's follow-up if one is filed. |
| Post-freeze amendment without sign-off | governance | **owner decision at closeout** — ratify or reverse; already recorded in `docs/ai/decisions.jsonl` (`type: spec_amendment`). Not waivable by a reviewer. |

## Next steps

1. Flip the nine Spec-AC rows to terminal status with evidence and run
   `node .aai/scripts/docs-audit.mjs --gate release-protected-branch-fallback`.
2. Record the CQ-1..CQ-3 dispositions (follow-up refs or decisions.jsonl
   entries) before closeout.
3. Surface the post-freeze amendment to the owner for ratification.
