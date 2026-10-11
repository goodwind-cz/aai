# Code review: merge-cleanup-ride-leftovers, round r3 (delta)

- Ref: merge-cleanup-ride-leftovers.
- Spec: docs/specs/SPEC-0223-spec-merge-cleanup-ride-leftovers.md (frozen_sha256 858367bf..., ceremony_level 2, 9 Spec-ACs).
- Scope: `git diff 8d959eec..04645431` in /Users/ales/Projects/aai-change-merge-cleanup-ride-leftovers, branch change/merge-cleanup-ride-leftovers. Files in the delta:
  - .aai/scripts/merge-cleanup.mjs: D8 reset record and resume scan, the once-per-archive done record, the movedFromManifest intent key, HELP.
  - tests/skills/test-aai-merge-cleanup.sh: TEST-053.
  - The spec: D8 step 5 and its disclosure, Spec-AC-09, the TEST-053 row, the TEST-051 mutation cell, V1.
  - docs/INDEX.md and the r2 review report.
  - Earlier surfaces were reviewed in r1/r2 and are in scope only where the delta touches them.
- Validation input: docs/ai/validation/VALIDATION-20261011T1537Z-merge-cleanup-ride-leftovers-r3.md (same round, PASS, NB-r3-1/2).
- Reviewer: claude-opus-5-5. Independent context, read-only. Implementer: claude-sonnet-5-5.
- Coaching note: the dispatch named the probes (crash at every point including reset/reset-record, older-engine journals) and called the reset-window residual "disclosed". The reviewer checked that claim against the spec text and found it is not disclosed there (finding 1). No severity was pre-rated and no scope excluded.

```yaml
review:
  scope: 8d959eec..04645431 (worktree /Users/ales/Projects/aai-change-merge-cleanup-ride-leftovers)
  spec: docs/specs/SPEC-0223-spec-merge-cleanup-ride-leftovers.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "untouched by the delta; TEST-045 PASS (r3 suite); replay RED" }
      - { ac: Spec-AC-02, call: compliant, citation: "untouched; TEST-046 PASS; replay RED" }
      - { ac: Spec-AC-03, call: compliant, citation: "merge-cleanup.mjs:1031-1046 intent/append/done/compare/reset; TEST-047 PASS; replay RED; validator crash series 5 points + 20 pairs all exact" }
      - { ac: Spec-AC-04, call: compliant, citation: "predicate unchanged; TEST-048 late arm PASS (stop before reset leaves intents open, re-run moves the late line once)" }
      - { ac: Spec-AC-05, call: compliant, citation: "untouched; TEST-049 PASS; probes R1, R3 identical to r2" }
      - { ac: Spec-AC-06, call: compliant, citation: "untouched; TEST-050 PASS; probe R7 one load" }
      - { ac: Spec-AC-07, call: compliant, citation: "merge-cleanup.mjs:1010-1029 (scan with retirement), 1060 (moved key); TEST-051 four arms PASS; re-pointed mutation 'for (const r of [])' RED" }
      - { ac: Spec-AC-08, call: compliant, citation: "code untouched, HELP line 67 now <n|signal>; TEST-052 PASS; probes R2, R4-R6" }
      - { ac: Spec-AC-09, call: compliant, citation: "merge-cleanup.mjs:1015 reset clears open intents and done set, 1026-1028 one done per archive with intent key, 1046 reset record, 1060 moved keyed by intent; TEST-053 ident + dint arms PASS; Test Plan mutation RED; validator mutants mut-a (done guard) and mut-b (moved key) both killed by TEST-053" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1045, issue: "The reset record is written after the ride file write. A crash between them leaves the moved intent open, and a later ride tail whose leading bytes equal the moved tail is then skipped as already moved and reset away (kept only in the archive). D8 step 5 says such a tail 'is appended, never skipped'. The residual paragraph names only the foreign-writer-at-mainLen case, so this window is undisclosed in the spec.", failure_scenario: "Validator probe_r3_crash.sh with the after-reset-write seam from make_eng.sh: crash rc 137, the identical EV1+EV2 is appended to the ride EVENTS again, the re-run exits 0 with EV1=1 and EV2=1 where 2 were written. With identical prefix + a first-time line M, the prefix is skipped and M appended. First-time lines alone are always appended; no crash point or pair double-appends (28 sequences). Fix: add the window to the D8 residual sentence, or trade the loss for a visible duplicate by journalling a pre-write 'resetting' record and retiring intents on resume when the ride file no longer equals the recorded tail." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0223-spec-merge-cleanup-ride-leftovers.md, line: 481, issue: "Risk R5 still describes the pre-intent behaviour: hand-copied lines 'are skipped only when the whole tail, or an earlier archived tail of this PR, already occurs at a line start'. D8 (since r2) says a hand-copied tail with no intent is appended again. Stale text that predates this delta.", failure_scenario: "A reader of the Risks section expects a hand-copied tail to be skipped; the engine appends it again (validator P6 shape). Documentation only." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1015, issue: "Informational, no change asked: journals written by this branch's own r1/r2 engines have no reset records, so the r2 skip (P7) persists for them (validator O2a) and the r1 shape duplicates (P6). No engine on main writes ledger-append records, so only local runs of this unmerged branch are exposed.", failure_scenario: "probe_r3_oldjournal.sh O2a: main 1 where 2 written after the reset records and intent keys are stripped." }
  cannot_verify:
    - { claim: "No live journal in the main checkout carries ledger-append records from this branch's earlier engines.", closes_with: "A read-only scan of /Users/ales/Projects/aai/docs/ai/archive/merge-cleanup/*/journal.jsonl for step ledger-append (out of bounds for this dispatch)." }
    - { claim: "Re-exec stdout piping on native Windows.", closes_with: "A Windows leg running TEST-049/050/052; unchanged from r2." }
  overall: pass
```

## AC table walk (spec_compliance: pass)

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01..06 | compliant | Not touched by the delta (01, 02, 04, 05, 06) or touched only in the resume scan (03). All pass in the r3 whole-suite run (52/52) and redden on replay. |
| Spec-AC-07 | compliant | The scan at 1010-1016 rebuilds `open` and `doneArchives` from the journal in order. The resume loop at 1019-1029 is unchanged in its content test. TEST-051 passes, and its re-pointed mutation (the scan iterates an empty list) is RED. |
| Spec-AC-08 | compliant | No code change. HELP is aligned with the code. |
| Spec-AC-09 | compliant | Ident arm: the stop after the move leaves a reset record, so the re-run's open list is empty and the identical late line is appended (main 2, moved 2 via distinct intent keys). Dint arm: three intents for one archive, and `doneArchives` gates the resume-path done record to one. TEST-053 mutation RED. Validator mutants mut-a and mut-b are both killed. |

Deviations from the frozen spec (none changes an AC outcome):
- DEV-1 (finding 1): D8 step 5's "never skipped" does not hold in the window between the ride file write and the reset record. The residual sentence omits it.
- DEV-2: done records now carry `intent` (not listed in D8 step 3's record shape, though step 5 implies it). Harmless; additive.
- DEV-3 (finding 2): R5 in Risks is stale against D8.

Amendment records vs the diff:
- 15:08:23Z (contract): matches. It records Spec-AC-09, TEST-053, D8 step 5, one done per archive, and the shortened-ledger disclosure.
- 15:22:13Z (measurement): matches. The TEST-051 cell now reads `sed:s/for \(const r of readJsonl\(journal\)\) \{/for (const r of []) {/`, and that anchor exists once at merge-cleanup.mjs:1011.
- Both records are in the uncommitted worktree ledger. The 14:40:17Z and 15:08:23Z contract records are unsigned-tracked under fu-amend-merge-cleanup-ride-leftovers (signed at merge by the owner's /aai-merge direction).

## Review of the delta

### Reset record and resume scan (D8 step 5)
- Ordering:
  - Intents before a reset are dropped.
  - Intents after it accumulate.
  - `doneArchives` is cleared with the reset. This is correct: an identical later tail may reuse the same archive path, because archiveFile is idempotent by content. Its new append must get its own done record.
- A `reset` is written on both the append path and the skip path. In both, the ride file has just been rewritten to HEAD, so every earlier intent is fully accounted for.
- The stop before the reset (`worktree_dirty`) correctly writes no reset record. TEST-048 late and the validator's TOUCH_AT probe show the late line moved once.
- The remaining gap is the crash window between write and record (finding 1). It is narrower than r2's NB-r2-1, which needed no crash. The fail direction is still loss-to-archive rather than duplicate, so it is worth stating in the spec.

### Done record once per archive; moved count keyed by intent
- `doneArchives.add` precedes the append. A crash between that add and appendJsonl only loses an in-memory entry, so a re-run re-derives it. Correct.
- The moved key `r.intent ?? r.archive`:
  - Two distinct appends that share an archive path (identical content) count twice.
  - Resume-path done records carry the matched intent's timestamp, so a done written at resume and one written inline never share a key for different appends.
  - r2-shaped done records (no `intent`) fall back to the archive and mix correctly (validator O2c, moved 2).
- Edge: two intents whose timestamps are equal to the millisecond would collapse. They come from separate processes separated by a crash and a re-run, so this is not a practical concern.

### Tests
- TEST-053 runs on real seams (TOUCH_AT, CRASH_AT x3) and checks byte counts, journal done counts and the JSON moved list.
- `grep -c ... || true` is safe under `set -euo pipefail` (count 0 prints and exits 1, which is swallowed).
- Gap (not blocking): no test pins the reset-write window. It needs a new seam, and finding 1 recommends disclosure over a test.

## Warning dispositions (recommended; the orchestrator records them)

| Finding | Severity | Recommended disposition |
|---|---|---|
| 1 reset-write/reset-record crash window skips a later identical tail | P3 | (d) accepted residual with one added D8 sentence (spec text edit = an amendment record), or (b) follow-up `fu-merge-ledger-reset-window` if the code fix is wanted. A third finding round is not required: no first-time line is lost and nothing double-appends. |
| 2 Risk R5 stale against D8 | P3 | (a) fold into the same spec touch as finding 1 (doc only). |
| 3 older-branch-engine journals | info | none |

## Next steps
1. The orchestrator records the dispositions.
2. Commit the 15:08:23Z and 15:22:13Z amendment records with the PR, together with the earlier ones.
3. Ship step 4 (product doc + CHANGELOG, V5) follows LOOP COMPLETE.
