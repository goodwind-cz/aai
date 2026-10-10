# Code review: directed-merge-and-post-merge-cleanup (round 3)

```yaml
review:
  scope: "delta 93e6be5c..bc041b26 plus regression origin/main...HEAD (2836dcc5...bc041b26), branch change/directed-merge-and-post-merge-cleanup"
  spec: docs/specs/SPEC-DRAFT-spec-directed-merge-and-post-merge-cleanup.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "SKILL_MERGE.prompt.md bash block now builds the optional --direction pair with set -- and forwards \"$@\"; TEST-002 runs the extracted block under bash AND zsh (named SKIP only when zsh is absent)" }
      - { ac: Spec-AC-02, call: compliant, citation: "merge-cleanup.mjs runPreflight: appendDirectedMerge into the main checkout ledger after every refusal gate, before the command is printed; refuse direction_unrecorded if it cannot write. TEST-003 asserts no decisions.jsonl after all refusal arms; TEST-004 asserts exactly one directed_merge record (verbatim answer, head, pr), no duplicate on repeat, and survival through a refused apply" }
      - { ac: Spec-AC-03, call: compliant, citation: "unchanged since r2; TEST-005" }
      - { ac: Spec-AC-04, call: compliant, citation: "unchanged since r1; TEST-006/007" }
      - { ac: Spec-AC-05, call: compliant, citation: "syncBase restore() and resumeSync use putBack (saved + live bytes past the HEAD blob); TEST-014 concurrent arm. r2 probe3 re-run at bc041b26: final ledger seed/pr/LOCAL-TAIL/CONCURRENT, rc 0 (NB-r2-1 fixed)" }
      - { ac: Spec-AC-06, call: compliant, citation: "unchanged since r2; TEST-010/011/016" }
      - { ac: Spec-AC-07, call: compliant, citation: "linkedPrs strict: bare N, #N, or this repository's /pull/N URL; TEST-012 arm (d) url-digits noop + two positive shapes. r2 probe2 urldigits arm re-run: state noop, STATE bytes unchanged (NB-r2-3 fixed)" }
      - { ac: Spec-AC-08, call: compliant, citation: "pendingJournals scans every pr-*/sync/pending.json; TEST-014 foreign arm (crash at sync-after-rewrite, apply of PR 434 puts PR 433's tail back once). Scratch probe4 (crash at sync-after-ff, then apply of PR 6): re-appended, LOCAL-TAIL once, rc 0 (NB-r2-4 fixed)" }
      - { ac: Spec-AC-09, call: compliant, citation: "gh run view 38049456260: workflow_dispatch, headSha fb18f947, conclusion success, all three jobs success. fb18f947..bc041b26 touches only the spec row and docs/INDEX.md. Root cause of the earlier red fixed in aai-merge-cleanup.Tests.ps1 AfterAll (Remove-Item Env: for a variable that was unset). Deviation kept from r2: evidence is a branch dispatch, not PR CI" }
      - { ac: Spec-AC-10, call: compliant, citation: "prompt-diet-ledger.sh +38 entry (round2), TEST-012 pin 59970 -> 60008, pr-preflight want_growth +38; prompt 3412 -> 3450 B" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 476,
          issue: "mergeLedgerTails derives its tmp dir and its ledger_merge_failed message from ctx.opts.pr. Since NB-r2-4 it also re-appends a FOREIGN PR's journal, so the message names pr-<current>/sync/<rel> while the local bytes live in pr-<journal PR>/sync/<rel> (the entry's e.archive).",
          failure_scenario: "apply --pr 5 is killed at sync-after-ff; later apply --pr 6 resumes PR 5's journal and ledger-merge.mjs exits non-zero (e.g. the live ledger was rewritten after the fast-forward). The STOPPED line says 'local bytes kept in docs/ai/archive/merge-cleanup/pr-6/sync/docs/ai/EVENTS.jsonl', which does not exist; the bytes are under pr-5. The journal is kept, so nothing is lost, but the pointer the operator follows is false. By reading, not reproduced (needs a ledger-merge failure). Fix: pass e.archive into the item and print it." }
  cannot_verify:
    - { claim: "Windows parity at the exact PR head and in PR CI (V2 names PR CI)", closes_with: "ps1-quality and skill-suite pull_request runs on the PR head; dispatch run 38049456260 is at fb18f947, code-identical to bc041b26" }
    - { claim: "Get-CimInstance ParentProcessId is the harness pid on a real Windows harness", closes_with: "one live /aai-merge cleanup on Windows with a held ride session lock" }
    - { claim: "Real GitHub shapes of gh pr view and gh pr merge --match-head-commit behaviour", closes_with: "one live directed merge, or recorded gh output fixtures" }
    - { claim: "Suite and mutation results at bc041b26 (dispatch forbade running suites or mutation-run here)", closes_with: "the concurrent Validation r3 run and mutation-run --replay" }
    - { claim: "The pending_diverged stops (resumeSync and restore()) behave as written", closes_with: "a seam that rewrites the ledger between planChecks and the resume, or between the rewrite and a failed fast-forward; see the judgement below" }
  overall: pass
```

## Scope and spec

Delta `93e6be5c..bc041b26` read in full: f3772b63 (round-2 remediation),
fb18f947 (test-run ledger), bc041b26 (AC-09 flip), 92afbc1d (follow-up drop,
r2 report). Regression over `origin/main...HEAD`: no new surfaces,
`git ls-files -ci --exclude-standard` empty, worktree clean at bc041b26.
Spec: the frozen DRAFT with now three unsigned amendments (two contract, one
measurement), all tracked by `fu-amend-directed-merge-and-post-007bae`.

Coaching check: the dispatch named a known untested path and asked for a
judgement. It did not pre-rate it or exclude scope. Full scope reviewed.

## Round-2 findings re-checked

- NB-r2-1 (interrupted sync + concurrent append): fixed. `putBack` keeps
  anything appended after the HEAD blob behind the restored local bytes, in
  both `resumeSync` and `restore()`. Re-ran `cr-probe/probe3.sh`: the final
  ledger is seed/pr/LOCAL-TAIL/CONCURRENT, rc 0. TEST-014 has the arm.
- NB-r2-2 (direction recorded only after the merge): fixed. `preflight`
  appends the `directed_merge` record to the main checkout's ledger after
  the last refusal gate and before printing the command, and refuses
  `direction_unrecorded` when it cannot. `apply` dedupes on pr+answer+head.
  TEST-003 and TEST-004 cover the refusal, record, repeat and refused-apply arms.
- NB-r2-3 (links.pr digit scrape): fixed. Re-ran `cr-probe/probe2.sh`: the
  urldigits arm is a noop with STATE bytes unchanged. The f1/tail/pos/refuse
  arms are unchanged.
- NB-r2-4 (journal read by the same PR only): fixed. `pendingJournals`
  scans every PR's journal. TEST-014 has the foreign arm. A new probe
  (`cr-probe/probe4.sh`, crash at sync-after-ff, then apply for PR 6) also
  converges: LOCAL-TAIL is there once, rc 0.
- R2-F1 Pester env leak: the AfterAll removes a variable that was unset
  instead of setting it to ''. The dispatch run 38049456260 is green on all
  three jobs.
- R2-F3 zsh: TEST-002 now executes the real block under zsh too.

## Judgement: the untested pending_diverged stop

There are two new stop sites. In `resumeSync`, it fires when the live
ledger no longer starts with the journalled HEAD blob. In `restore()`, a
failed fast-forward finds a ledger it cannot prove.

- `resumeSync`, fast-forward not done: `planChecks` runs `planSync` on the
  live tree first. A ledger that is dirty and incoming must keep HEAD as a
  prefix, or `ledger_rewritten` refuses (exit 3) before the resume. So
  `pending_diverged` is reachable only when the current target no longer
  changes that ledger, for example after a revert on the base. In practice
  this guard sits behind another guard. The realistic case (someone
  rewrites the ledger after the crash) is covered end to end by the TEST-014
  diverged arm: exit 3, journal kept, live bytes untouched,
  `assert_nothing_lost`. The test asserts the reason that really fires
  (`ledger_rewritten`). It does not claim `pending_diverged`.
- `restore()`: reachable only if another session rewrites the ledger in the
  window between the engine's rewrite and a failed `git merge --ff-only`.
- Both sites fail closed. `resumeSync` proves every file before writing any.
  `restore()` writes only the files it can prove, keeps the journal and
  exits 4. No path deletes a journal or overwrites a live ledger it could
  not prove. The worst case is a stop that needs the operator, which the
  existing journal makes recoverable: restoring the ledger to HEAD and
  re-running puts the tail back.

Verdict: acceptable, not blocking. This is defensive code, and its failure
mode is a named stop, never a loss. The realistic trigger is gated earlier
and tested. accepted residual: P3 assurance-strength. The two stop
branches have no direct arm and no observed bite. They leave no false
record. Closing this would need a seam between `planChecks` and the resume.

## Other observations (INFO, no gate)

- The preflight `directed_merge` record carries no `merge_commit`, and
  `apply` will not add one because it dedupes on pr+answer+head. The merge
  commit is only in the run report and the saved report. If the printed
  merge then fails (for example, the head moves in between), the ledger
  holds a direction for a merge that never happened. The record text says
  "owner-directed merge ... at head X", which is accurate as a direction,
  and the head pins which merge it authorised.
- The preflight record's `ref_id` is the head branch tail. The ref that
  apply would have derived (the delivered done doc) can differ. Dedupe does
  not depend on it.
- Constitution Article 7 vs SKILL_PR step 6: unchanged since r2, and the
  owner must ratify it at merge. The r2 gap (direction recorded after the
  merge) is now closed, so step 6's "explicit, recorded direction" holds
  before the merge command runs.

## Warning dispositions (H6, recommended; the orchestrator records them)

- NB-r3-1 (foreign-journal archive path in the ledger_merge_failed message):
  remediate-in-tree (print e.archive). This is a one-line change plus an
  optional arm. Otherwise, promote it as P3 `fu-merge-foreign-journal-archive-path`.
  It is a false pointer in an error line, so it does not qualify for (d).
- pending_diverged stops: `accepted residual: P3 assurance-strength; both
  stop branches fail closed, the realistic trigger is refused earlier by
  ledger_rewritten and tested (TEST-014 diverged arm); no direct arm, no
  observed bite, no false record`.

## Next steps

No BLOCKING findings, so both verdicts pass. The PASS is conditional on the
NB-r3-1 disposition. Owner sign-offs are owed at merge, not as blockers:
`fu-amend-directed-merge-and-post-007bae` (three amendments) and Constitution
Article 7 vs SKILL_PR step 6.

Probes (outside the worktree):
`/private/tmp/claude-501/-Users-ales-Projects-aai/687516a7-9bb3-4b30-9ccf-230f17be6426/scratchpad/cr-probe/probe2.sh`, `probe3.sh`, `probe4.sh`.
