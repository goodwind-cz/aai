# Code review: merge-cleanup-ride-leftovers, round r2 (delta)

- Ref: merge-cleanup-ride-leftovers
- Spec: docs/specs/SPEC-DRAFT-spec-merge-cleanup-ride-leftovers.md (frozen_sha256 e6af583b..., ceremony_level 2, now 8 Spec-ACs)
- Scope: `git diff 194cb494..8d959eec` in the worktree /Users/ales/Projects/aai-change-merge-cleanup-ride-leftovers, branch change/merge-cleanup-ride-leftovers. Files: .aai/scripts/merge-cleanup.mjs (D8 intent journal, D10 moved count, D12 child exit, HELP), tests/skills/test-aai-merge-cleanup.sh (TEST-051/052, variant FIXTURE_CHILD_EXIT), the spec (D8/D10/D12 text, Spec-AC-07/08, TEST-051/052 rows, TEST-004 disclosure), docs/INDEX.md, and the r1 review report. The r1 surface (6d12eb41..194cb494) was reviewed in r1 and is in scope here only where the delta touches it.
- Validation input: docs/ai/validation/VALIDATION-20261011T1502Z-merge-cleanup-ride-leftovers-r2.md (same round, PASS, NB-r2-1..4).
- Reviewer: claude-opus-5-5. Independent context, read-only. Implementer: claude-sonnet-5-5.
- Coaching note: the dispatch prompt named the probes to run (crash points, foreign writer, shortened ledger, old journal, maxBuffer, --json, guard). It did not pre-rate severity or exclude scope. The full delta was reviewed.

```yaml
review:
  scope: 194cb494..8d959eec (worktree /Users/ales/Projects/aai-change-merge-cleanup-ride-leftovers)
  spec: docs/specs/SPEC-DRAFT-spec-merge-cleanup-ride-leftovers.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "untouched by the delta; TEST-045 PASS in r2 suite run; mutation replay RED" }
      - { ac: Spec-AC-02, call: compliant, citation: "untouched by the delta; TEST-046 PASS; mutation replay RED" }
      - { ac: Spec-AC-03, call: compliant, citation: "merge-cleanup.mjs:1008-1028 intent/append/done; movedFromManifest:1041-1052; TEST-047 PASS; mutation replay RED" }
      - { ac: Spec-AC-04, call: compliant, citation: "untouched predicate; TEST-048 late arm PASS against the intent-gated resume" }
      - { ac: Spec-AC-05, call: compliant, citation: "merge-cleanup.mjs:1619-1624 pass-through of exit 0 with stdout forwarded; TEST-049 PASS (one JSON document)" }
      - { ac: Spec-AC-06, call: compliant, citation: "guard line 1609 unchanged; TEST-050 PASS; validator probe R7 one load" }
      - { ac: Spec-AC-07, call: compliant, citation: "merge-cleanup.mjs:1008-1028, 1041-1052; TEST-051 four arms PASS; mutation 'const records = [];' RED on replay; validator probes P1-P3, P5, P8, P9" }
      - { ac: Spec-AC-08, call: compliant, citation: "merge-cleanup.mjs:1619-1626; TEST-052 exit3/sig/syntax/pass-through arms PASS; mutation 'if (true) {' RED; validator probes R2b, R4-R6" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1012, issue: "An intent whose append completed AND whose worktree reset (line 1034) completed stays a resume candidate for later runs of the same PR. A NEW ride tail that starts with the same bytes is then taken as already moved, and the worktree file is reset to HEAD, so those new lines leave the tracked ledger (they survive only in the gitignored archive).", failure_scenario: "Validator probe P7: the ride appends line L; apply moves it (intent, append, done, reset), then another session appends a byte-identical L to the ride before the late re-verify, apply stops exit 4 worktree_dirty. The re-run finds intent(A_L) with L at mainLen, sets already = len(L), appends nothing, resets the ride file and removes the worktree. Main holds L once where it was written twice. No crash is needed and the block at mainLen is the engine's own append, so the spec's disclosed residual (crash + re-run + another writer's identical block) understates it. Fix: journal a `reset` record after the compare-then-write and drop archives with a reset record from the candidates." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1013, issue: "The resume key is offset-anchored: when the main ledger is rewritten shorter between the crash and the re-run (bytes before the tail removed, tail kept), `from` = min(mainLen, cur.length) lies past the moved bytes, the content test fails and the whole tail is appended a second time. Not fail-closed, and the spec's disclosure names only a hand-copied tail as the duplicate case.", failure_scenario: "Validator probe P4: CRASH_AT ledger-move-after-append, then the first line of main's EVENTS.jsonl is deleted (any rewrite that drops earlier bytes), re-run exit 0 with EV1 and EV2 each present twice. A growing rewrite (P4b, line inserted at the top) is handled. Suggested: when an intent without a done record finds cur.length < mainLen + its segment length and no match, stop `ledger_rewritten <rel>` (exit 4) instead of appending; or disclose in D8." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1017, issue: "`records` is read once before the loop, so two intent records for the same archive (left by a crash at ledger-move-after-intent followed by a crash at ledger-move-after-append) each append a `done` record. D8 says 'every completed append has exactly one done record'.", failure_scenario: "Validator probe P1: crash after intent, re-run crashes after append, third run writes two `done` records for the EVENTS archive. movedFromManifest de-duplicates by archive, so the report count stays right (EVENTS 2); only the journal carries the duplicate. Fix: push the new done record into `records` (or a Set of done archives) inside the loop." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 67, issue: "HELP names the stop line as `STOPPED reexec_child_exit_<n>`; the code and the spec produce `<n|signal>` (e.g. reexec_child_exit_SIGKILL).", failure_scenario: "An operator reading HELP after a signal-killed child sees a stop reason HELP does not describe. Documentation only." }
  cannot_verify:
    - { claim: "Re-exec stdout piping on native Windows (spawnSync with stdio ['inherit','pipe','inherit'] and the cli-pipe-guard drain).", closes_with: "A Windows leg running TEST-049/050/052; Pester TEST-016 covers only the wrapper surface." }
    - { claim: "No released engine wrote ride_ledger_tail archives without intent records, so the pre-intent journal duplicate (validator probe P6) cannot reach a user.", closes_with: "Verified for origin/main (no moveLedgerTails in main's engine); a downstream that ran the unmerged r1 engine of this branch is the only exposure. Nothing further needed unless such a downstream exists." }
    - { claim: "The live false-skip rate of findings 1 and the disclosed residual is negligible.", closes_with: "r1 measurement (0 duplicate lines in 6051 live ledger lines, every line timestamped) still holds; it is evidence on current data, not a guarantee." }
  overall: pass
```

## AC table walk (spec_compliance: pass)

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | Not touched by the delta. TEST-045 PASS in this round's suite run, mutation replay RED. |
| Spec-AC-02 | compliant | Not touched. TEST-046 PASS, replay RED. |
| Spec-AC-03 | compliant | The append now sits between an intent record (`mainLen`, `lines`) and a done record (merge-cleanup.mjs:1023-1028); `crashAt('ledger-move-after-append')` moved inside the append branch, which matches D8 step 3. TEST-047 PASS, replay RED. |
| Spec-AC-04 | compliant | The predicate is unchanged; TEST-048's late arm passes through the intent-gated resume (the late line is moved once). |
| Spec-AC-05 | compliant | Exit 0 forwards the held stdout verbatim (1624); TEST-049 parses one JSON document. Validator probe R1: a 20 MB child stdout plus the report reaches the caller in full (20002032 bytes, last line valid JSON), R3 the same through a real pipe reader. |
| Spec-AC-06 | compliant | Guard unchanged (1609). TEST-050 PASS; probe R7 self-touching variant loaded once. |
| Spec-AC-07 | compliant | A first run never counts its own archive (records hold no intent for it yet), so the dup arm appends the line (count 2). Crash after intent: `atLineStart(cur, c, mainLen)` finds nothing at or after mainLen, the segment is appended once. Crash after append: the tail is found at mainLen, nothing more appended, the missing done record is written. Moved = sum of done lines per archive. TEST-051 four arms PASS, mutation RED. |
| Spec-AC-08 | compliant | Any status outside {0, 4} or a signal: child stdout to stderr, `STOPPED reexec_child_exit_<status or signal>`, exit 4 (1625-1626). TEST-052 arms exit3/sig/syntax and the exit-4 pass-through PASS, mutation RED. |

Deviations from the frozen spec (none touches an AC):
- DEV-1: the intent record also carries `length` (not listed in D8). Harmless.
- DEV-2: D8's "every completed append has exactly one done record" does not hold after two intents for one archive (finding 3). The report is unaffected.
- DEV-3: HELP says `<n>`, spec and code `<n|signal>` (finding 4).

Amendment records vs the diff: both `spec_amendment` records at 2026-10-11T14:40:17Z describe exactly what the diff does (Spec-AC-07/08, TEST-051/052, D8/D10/D12, the HELP paragraph; TEST-004's dirt is a README edit, its assertions unchanged). They are `unsigned-tracked` under fu-amend-merge-cleanup-ride-leftovers (owner signs at merge). Note: they sit in the worktree's uncommitted docs/ai/decisions.jsonl, not in HEAD 8d959eec; they must be committed with the PR.

## Review of the delta

### Ledger-tail intent journal (D8/D10)
- The r1 recommendation is implemented as proposed: intent before the append, content test only over intent-backed archives, anchored at the recorded `mainLen`. Crash at every point of intent/append/done was exercised by the validator (P1, P9 plus TEST-051): nothing lost, nothing doubled.
- Another writer between crash and resume: an unrelated line (P2, P3) changes nothing. A byte-identical foreign block at mainLen after an intent crash is the disclosed residual false skip and reproduces as disclosed (P2b).
- `mainLen` past the current file: `from` clamps to `cur.length`, the search finds nothing and the tail is appended. When the rewrite removed the tail (P5, `git restore`) that is the right answer (no loss). When the rewrite only removed earlier bytes (P4) it is a visible duplicate (finding 2). Not fail-closed either way; the choice favours duplicate over loss, which is the spec's stated preference, but the shortened case is not disclosed.
- Old journal without intent records (P6): the tail is appended again (duplicate). Only the unmerged r1 engine could have produced such a journal; origin/main never moved ledger tails. Acceptable.
- Report: one entry per ledger, summed per archive. Correct in P1 even with the duplicate done record.
- Residual found this round: finding 1 (P7). It is the r1 NB-1 class surviving in a narrower form (it needs a whole earlier tail repeated byte-for-byte as the start of a later tail in the same PR), so it is ranked like r1's finding 1: NON-BLOCKING, P2 because bytes can leave the tracked ledger.

### Re-exec child exit (D12)
- stdout piped with a 256 MiB maxBuffer, stderr inherited. Exit 0/4 forward the held stdout; any other status or signal prints exactly one STOPPED line and exits 4, the child's stdout going to stderr in full (R2b: 20000095 bytes relayed). maxBuffer overflow becomes `r.error` -> `STOPPED reexec_failed` (exit 4), still resumable.
- `--json`: every path prints either the child's own single document, the child's own STOPPED line, or the parent's STOPPED line. One document or one stop line, never both.
- The exit-4 path resumes: after `reexec_child_exit_3` and `_SIGKILL` the plain re-run exits 0 with the marker step done once and one `reexec` record (R4, R5). A syntax-broken merged engine still exits 1 on the re-run because the re-run loads the broken file directly; that is outside this engine's reach and was accepted in r1.
- Pipe safety: `exit()` throws to `runMain`, which drains stdout before the process ends, so the forwarded payload is not truncated on macOS pipes (R3). Note: in probe R2 the fixture child itself truncated its own 20 MB at 64 KiB because the fixture used raw `process.exit`; that is fixture behaviour, not the engine's.

### Tests
- TEST-051 hits the real seams (`CRASH_AT ledger-move-after-intent` / `-after-append`, byte `tail -c`, JSON moved). TEST-052 uses the variant generator with anchor checks; the syntax arm appends `)(` to a copy. Both use `|| true` on grep counts under `set -euo pipefail`.
- Gap (not blocking): no test pins the double-done journal record, the shortened-ledger resume or the P7 repeat. Each is a finding above.

## Warning dispositions (recommended; the orchestrator records them)

| Finding | Severity | Recommended disposition |
|---|---|---|
| 1 identical later tail falsely skipped after a completed move (P7) | P2 | (a) remediate in tree if a third round is acceptable under the standing decision (the hazard is introduced by this feature), else (b) follow-up `fu-merge-ledger-tail-reset-record`, P2. Fix: a `reset` journal record after the compare-then-write; exclude archives with a reset record. Also correct the D8 residual sentence. |
| 2 shortened main ledger re-appends the tail (P4) | P3 | (b) follow-up (can share the id above) or (d) accepted residual: visible duplicate in an append-only ledger, no loss, requires an out-of-model rewrite between crash and resume. If (d), add one sentence to the D8 disclosure. |
| 3 duplicate done record for one archive (P1) | P3 | (a) remediate in tree with finding 1 (one line), or (d) accepted residual: the report de-duplicates by archive, no false count anywhere. |
| 4 HELP `<n>` vs `<n|signal>` | P3 | (a) remediate in tree (one word) at the next touch, or (d) accepted residual. |

## Next steps
1. The orchestrator records the dispositions above.
2. Commit the two `spec_amendment` records and the follow-up with the PR (they are uncommitted in the worktree ledger).
3. Ship step 4 (product doc and CHANGELOG, V5) follows LOOP COMPLETE as planned.
