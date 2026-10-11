# Code review: merge-cleanup-ride-leftovers, round r1

- Ref: merge-cleanup-ride-leftovers
- Spec: docs/specs/SPEC-DRAFT-spec-merge-cleanup-ride-leftovers.md (frozen, ceremony_level 2)
- Scope: `git diff 6d12eb41..194cb494` in the worktree, branch change/merge-cleanup-ride-leftovers. Files: .aai/scripts/merge-cleanup.mjs, tests/skills/test-aai-merge-cleanup.sh, docs/INDEX.md, the CHANGE draft and the SPEC draft.
- Validation input: docs/ai/validation/VALIDATION-20261011T1426Z-merge-cleanup-ride-leftovers-r1.md (PASS, NB-1 to NB-4).
- Reviewer: claude-opus-5-5. Independent context, read-only.
- Reviewer runs: `env -u AAI_ROLE bash tests/skills/test-aai-merge-cleanup.sh TEST-047` passed (rc 0). The same command for TEST-050 also passed (rc 0).
- Coaching note: the dispatch prompt named the areas to examine and listed the validation NBs. It did not pre-rate their severity or exclude any scope. The full diff was reviewed.

```yaml
review:
  scope: 6d12eb41..194cb494 (worktree /Users/ales/Projects/aai-change-merge-cleanup-ride-leftovers)
  spec: docs/specs/SPEC-DRAFT-spec-merge-cleanup-ride-leftovers.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "merge-cleanup.mjs stripRideEntries/roadmapTexts/rideChangedRefs/roadmapRideOnly (+437-485), planSync isRoadmap branch, syncBase ROADMAP_PATH entry, resumeSync INDEX_PATH key, sync-base planner line; TEST-045 incl. crash arm" }
      - { ac: Spec-AC-02, call: compliant, citation: "planSync staged check precedes isRoadmap; roadmapRideOnly fail-closed returns; TEST-046 foreign/mixed/staged/incoming-lacks + positive control" }
      - { ac: Spec-AC-03, call: compliant, citation: "ledgerTails (appendOnly), moveLedgerTails, movedFromManifest, emit/renderReport/buildReport moved, remove-worktree planner; TEST-047 incl. crash arm (reviewer re-run PASS)" }
      - { ac: Spec-AC-04, call: compliant, citation: "worktreeVerdict allowTails, strict late verdict in removeWorktree; TEST-048 five refuse arms + late arm" }
      - { ac: Spec-AC-05, call: compliant, citation: "ENGINE_FILE/ENGINE_STARTUP_SHA/REEXEC_ENV, reexecIfReplaced, reload-engine synthetic step in runApplyOrPlan; TEST-049" }
      - { ac: Spec-AC-06, call: compliant, citation: "guard `if (process.env[REEXEC_ENV]) return null;`; TEST-050 guard + interrupted arms (reviewer re-run PASS)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 999, issue: "The resume key counts the CURRENT tail's own archive, which is written before any append, as already moved. On a first run with no crash, a tail found at a line start anywhere in the main ledger is never appended.", failure_scenario: "The ride appends line X after its last commit, and main's test-runs.jsonl already holds a byte-identical X. apply archives X, already = len(X), appends 0 bytes, resets the ride file to H and removes the worktree. Main keeps 1 copy where 2 were written, and the second exists only in the archive (validator probe L6)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1021, issue: "movedFromManifest reports every ride_ledger_tail archive and not what was appended. The report overcounts after a resume and claims a move that dedupe skipped.", failure_scenario: "Probe L3: a crash after the append, then a late line, then a re-run. The report prints 'moved 2 line(s)' AND 'moved 3 line(s)' for EVENTS, but 3 lines moved. Probe L6: it prints 'moved 1 line(s)' when 0 bytes were appended. Both are false statements in the owner report and the saved report." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1598, issue: "exit(r.status ?? 4) passes the child's status through unchanged. That includes 1 (load failure, raw stack trace) and 3 (REFUSE, which canon reads as 'nothing written') after the parent has already archived drafts and fast-forwarded the base.", failure_scenario: "(a) The merged engine has a syntax error, so apply exits 1 with a node stack trace on every re-run (validator probe E1). (b) The merged engine adds a refusal in planChecks that the post-sync world trips. The child prints REFUSE and exits 3, so SKILL_MERGE relays 'nothing written', but sync-base done and archive-drafts done are in the journal. A signal-killed child gives exit 4 with no STOPPED line." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 446, issue: "D2 by design: every line indented 4+ spaces after `  - capability: <ride>` belongs to the ride block, so a foreign edit inside it counts as ride-only.", failure_scenario: "The owner edits `    maintenance:` or adds an indented comment inside the ride's pair block in the main checkout. apply takes the incoming roadmap. The local bytes are archived byte-exact (pre_sync_local_state), and the plan line names only 'archive ride entry foo' (validator probe R1)." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-merge-cleanup.sh, line: 1326, issue: "TEST-004's fixture was changed (an appended ledger line was swapped for a README edit). The frozen spec's Test Plan does not name this change, and decisions.jsonl holds no spec_amendment record for it. Separately, the Implementation plan says HELP names the three behaviours, but HELP is unchanged.", failure_scenario: "At close, spec-amend list --strict and the frozen contract still show TEST-004 as untouched, so the regression-test edit is disclosed only in the validation report. A later reader of the spec cannot see that TEST-004's dirt changed meaning." }
  cannot_verify:
    - { claim: "Re-exec on native Windows: spawnSync with stdio inherit, realpath ENGINE_FILE vs origin, and git replacing the engine file under a running node.", closes_with: "A Windows CI leg running TEST-049/050, which are bash-only today. Pester TEST-016 covers only the wrapper surface." }
    - { claim: "The ledger move under core.autocrlf / eol=crlf attributes fails closed (prefix test fails) and never writes a converted H.", closes_with: "A fixture with .gitattributes eol=crlf on a ledger, or a Windows run." }
    - { claim: "The real-world false-skip rate of the content-dedupe key (finding 1) is negligible.", closes_with: "The reviewer's measurement: 0 duplicate lines across 6051 lines of the four live ledgers (every line is timestamped). That is evidence for the current data, not a guarantee." }
    - { claim: "A pre-existing skip-worktree hidden edit in the ride is removed without refusal (validator NB-4).", closes_with: "Out of scope here. Origin/main behaves the same way (validator probe 'OLD-ENGINE L10'). It needs its own intake." }
  overall: pass
```

## AC table walk (spec_compliance: pass)

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | `stripRideEntries`, `roadmapRideOnly`, `planSync` `isRoadmap`, the `syncBase` archive+journal+rewrite loop, and the `resumeSync` `e.rel === INDEX_PATH` key. TEST-045 covers apply, plan and the crash at sync-after-rewrite. Mutation replay RED (validation log). |
| Spec-AC-02 | compliant | The staged refusal is checked before the roadmap branch. `roadmapTexts` returns null and refuses on an unreadable/deleted file or a missing blob. TEST-046 has four refuse arms and a positive control. The widening mutation is RED. |
| Spec-AC-03 | compliant | `ledgerTails` (D6 `const appendOnly`), `moveLedgerTails` (D8 archive, then append, then `crashAt`, then compare-then-write), `movedFromManifest`/`emit`/`renderReport` (D10), and the remove-worktree planner. TEST-047 asserts main-ledger bytes with `tail -c` and archive bytes with cmp (seam S2). The reviewer re-ran it: PASS. |
| Spec-AC-04 | compliant | `worktreeVerdict(..., { allowTails })` with the strict late verdict. TEST-048 has the rewrite/partial/staged/plus-file/plus-untracked arms. The late arm runs through the real removal (seam S3). |
| Spec-AC-05 | compliant | `ENGINE_FILE` (realpath), `ENGINE_STARTUP_SHA`, `reexecIfReplaced` after the journal write and the STOP_AFTER check, and `reload-engine` inserted right after sync-base. TEST-049 parses `--json` as one document and finds exactly one stderr line and one reexec record. |
| Spec-AC-06 | compliant | The guard line matches the anchor exactly. In the TEST-050 guard arm the self-touching variant is loaded once, and under the guard mutation it reaches the third-load exit 99. In the interrupted arm, STOP_AFTER=state in the child gives exit 4, and the re-run runs the marker once. The reviewer re-ran it: PASS. |

Deviations from the frozen spec. Neither touches an AC:
- DEV-1: TEST-004's fixture was amended without a spec_amendment record (finding 5).
- DEV-2: the Implementation plan says HELP names the three behaviours. HELP (merge-cleanup.mjs:53-65) is unchanged, and only the header comment names them (finding 5).

## Answers to the areas the dispatch named

### Roadmap ride-only predicate: correct and fail-closed
- The predicate compares `strip(local)` against `strip(HEAD blob)`, never against incoming. Every change the merge brings is therefore taken from the merge commit, and every local change outside the ride's lines refuses. The incoming-must-carry-the-block clause (A2) means the incoming file is never missing the ride record.
- Every path that cannot prove the condition returns false and refuses `overlap`: a staged roadmap, a deleted or unreadable file, a missing blob, CRLF drift, an empty `mergedRefs`, prefix refs (Set equality), a ride ref appearing as a `maintenance:` half.
- Data safety does not depend on the predicate's precision. The whole local file is archived (`pre_sync_local_state`) before the HEAD-blob write. `restore()` and `resumeSync` put it back on a failed or interrupted fast-forward, and `resumeSync` no longer regenerates the index for a roadmap entry.
- NB-3 (validation) is the D2 shape itself: indented lines belong to the block. It is not blocking. Nothing is lost (the archive is byte-exact), and the frozen design chose a closed-shape line parser. Disposition: accepted residual. Narrowing it (strip only `status:` lines of the ride block) would need a spec amendment.

### Ledger-tail move: is dedupe-by-content the right resume key?
Mostly yes, and better than a byte-offset key in this file system. The reasons:
- The main checkout's ledgers are shared and append-only, and other sessions write to them concurrently (the main checkout is shared, per the spec's Isolation section). They are also rewritten by `sync-base` (HEAD blob plus `ledger-merge`) on any later apply.
- A byte-offset or "size before append" journal key would give false negatives in both of those cases. A concurrent append between the intent record and our append moves our bytes to a later offset. A later sync-base rewrite moves them again. In both cases a resume would append again, so lines would be duplicated.
- A content search at a line start survives both.

What is wrong is the candidate set, not the key:
- The current tail's own archive is written BEFORE the append. It is therefore a candidate on a first run that never appended anything, and that is what makes validation NB-1 / L6 bite with no crash at all.

Recommended fix: keep the content search, but count an archive as already moved only when a durable append-intent record precedes it. For example, append a journal line `{step:'ledger-append', ledger, sha256}` right before `fs.appendFileSync`, and take `already` only over tails with such a record. This gives:
- No first-run false skip.
- Crash-resume still idempotent: the intent is durable before the append, and a crash between the intent and the append only means a content search that finds nothing, so it appends.
- The residual false skip shrinks to crash + resume + a byte-identical pre-existing multi-line block.

This drops R5's hand-copy dedupe (a hand-copied tail would be appended again, visibly). That is the safer failure: a visible duplicate in an append-only ledger rather than a silent loss into a gitignored archive. The same journal records also give the report the true appended count, which fixes finding 2.

Measured context: the four live ledgers hold 0 duplicate lines in 6051 (every line is timestamped). The bite is real but improbable on today's data. Hence NON-BLOCKING (P2, because the bytes would leave the tracked ledger).

### Other ledger-move properties checked (no finding)
- Fail-closed throughout:
  - Porcelain `-z` parse: renames and copies yield a non-` M ` entry, which refuses.
  - Submodule entries refuse.
  - An empty HEAD blob is handled (a zero-length Buffer is truthy).
  - An absent main ledger is created.
  - An unaligned main ledger refuses at plan time (D9) and stops mid-run (exit 4) before any byte is appended to it.
- If `ledgerTails` turns null between the first verdict and the move, the move is a no-op and the strict late verdict stops with exit 4. Nothing is reset.
- The session lock is checked in the first verdict, before any move. Compare-then-write guards the worktree reset (R4 window accepted).

### Engine re-exec
- Guard: the env check is the first statement. The child carries the parent's startup sha. `reload-engine` is emitted only for a 64-hex value that differs from the child's own sha. A stray value only suppresses (D13).
- Locks and session-lock pid: the engine holds no lock of its own across the spawn. The child gets the same `--pid`, so `lockStatus`/`lockRelease` behave identically.
- Journal: `reexec` and `reload-engine` are new step names, and no reader in .aai/scripts parses journal.jsonl step ids (grep).
- stdout: the parent writes nothing before the child. `exit()` throws `ExitSignal`, so the parent's loop does not continue after the child.
- stdin: inherited, and the engine reads none.
- Environment: AAI_GIT_WRITE and the test seams are inherited as designed.
- Exit propagation: a child status of 1 or 3 after the parent's writes is the defect named in finding 3. Recommended fix: map any child status outside {0, 4} to `STOPPED reexec_child_exit_<n>` with exit 4. The parent has already written, and a re-run resumes with the new engine directly. That keeps canon's exit-3 promise ("nothing written") true. Also print a STOPPED line for a signal-killed child.
- Minor (INFO): when the spawn fails (`r.error`), a `reexec done` journal record precedes `STOPPED reexec_failed`.

### Test quality
- The new tests hit the real seams:
  - The real `roadmap-edit.mjs ship-append` (S1).
  - Byte-level `tail -c` and `cmp` on the main ledger and the archive (S2).
  - The real `git worktree remove` in the late arm (S3).
  - The engine variant tracked in the fixture origin, so the real fast-forward replaces the running file (S4).
- The variant generator uses index slicing, never a `$`-bearing replacement string, and asserts each anchor (positive control).
- Every assertion uses `|| fail`, and grep counts use `|| true` under `set -euo pipefail`.
- Gap: no test pins NB-1/NB-2 behaviour, a ride tail combined with a dirty main-checkout ledger that sync-base merges first, or a dirty roadmap the incoming range does not change. The validator's probes covered the first and second ad hoc. Not blocking.

### Code clarity
- The new functions are small and named for their decisions (D-ids in comments).
- `rideChangedRefs` computes a strip per ref (O(refs × lines)), which is trivial at roadmap size.
- `ledgerTails` is called up to 4 times per apply (planChecks, the two verdicts, move, planner). Each call costs one `git status`, which is acceptable.

## Validation NBs: blocking or not, and the fix

| NB | Blocking? | Disposition (recommended; the orchestrator records it) |
|---|---|---|
| NB-1 dedupe drops a legit duplicate; report overcounts | No (P2: ledger line can leave the tracked file; 0 dup lines in live ledgers) | Promote to a follow-up (b), e.g. `fu-merge-ledger-tail-intent-key`, P2. Fix: an append-intent journal record gates the `already` candidates, and the report counts the appended lines from those records (findings 1 and 2). Remediating in tree is an option, but it changes D8/D10 wording, so it is a spec amendment. |
| NB-2 broken merged engine exits 1 with a raw stack | No (P3; data safe, canon stops on any non-zero) | Promote to a follow-up (b), P3, merged with the exit-3-after-write case of finding 3. Fix: map a child status outside {0, 4} to `STOPPED reexec_child_exit_<n>` with exit 4. |
| NB-3 a foreign edit inside the ride block counts as ride-only | No (by frozen design D2; the bytes are archived byte-exact) | accepted residual: the D2 closed-shape block is the frozen design, the whole local roadmap is archived byte-exact before the rewrite, no observed bite, no false record. |
| NB-4 a skip-worktree hidden edit is removed without refusal | No (pre-existing on origin/main, not a regression) | Promote to a follow-up (b), P2: a separate intake for a `git ls-files -v` skip-worktree/assume-unchanged check in `worktreeVerdict`. |
| Finding 5 (TEST-004 amendment and HELP unrecorded) | No | Remediate in tree (a) before close. Record a spec_amendment for TEST-004 (additive-with-disclosure, citing the validation report's TEST-004 section) and either add a HELP line or amend the Implementation-plan sentence. |

## Next steps
1. The orchestrator records the dispositions above: follow-ups for NB-1+2 (finding 1/2), NB-2+finding 3, and NB-4; the accepted residual for NB-3; and the in-tree amendment record for finding 5.
2. Ship step 4 (product doc and CHANGELOG, V5) follows LOOP COMPLETE as planned.
