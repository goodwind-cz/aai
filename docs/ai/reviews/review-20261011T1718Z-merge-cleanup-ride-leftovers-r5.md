# Code review: merge-cleanup-ride-leftovers, round r5 (delta)

- Ref: merge-cleanup-ride-leftovers (CHANGE-0210). Spec: docs/specs/SPEC-0223-spec-merge-cleanup-ride-leftovers.md (status done, frozen_sha256 827e9ba9..., ceremony_level 2, 11 Spec-ACs).
- Scope: `git diff 746c78e4..436b51f9`, one commit, worktree /Users/ales/Projects/aai-change-merge-cleanup-ride-leftovers (branch change/merge-cleanup-ride-leftovers, not pushed). Files:
  - .aai/scripts/merge-cleanup.mjs (`judgedMissing`, loop index);
  - tests/skills/test-aai-merge-cleanup.sh (TEST-055 and its selector);
  - the spec (D8 supersede rule, malformed-field policy, intent shape, Spec-AC-11, TEST-055 row, V1, plan);
  - docs/ai/decisions.jsonl (16:39:32Z amendment), docs/ai/EVENTS.jsonl (ac_status Spec-AC-11), docs/INDEX.md (timestamp), and the r4 review report (added).
- I re-read the whole resume loop (merge-cleanup.mjs:1004-1045) and movedFromManifest (1060-1072), because the delta changes which intents are counted.
- Validation input: docs/ai/validation/VALIDATION-20261011T1718Z-merge-cleanup-ride-leftovers-r5.md (same round, PASS).
- Reviewer: claude-opus-5-5, independent, read-only. Implementer: claude-sonnet-5-5. The owner approved this fifth round.
- Coaching note: the dispatch asked for a counterexample to the supersede rule and for segOffset 0 vs equal-length sequences. It did not pre-rate severity or exclude scope. I reviewed the full delta.

```yaml
review:
  scope: 746c78e4..436b51f9, worktree /Users/ales/Projects/aai-change-merge-cleanup-ride-leftovers
  spec: docs/specs/SPEC-0223-spec-merge-cleanup-ride-leftovers.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "untouched; TEST-045 PASS (r5 suite); replay RED" }
      - { ac: Spec-AC-02, call: compliant, citation: "untouched; TEST-046 PASS; replay RED" }
      - { ac: Spec-AC-03, call: compliant, citation: "append path merge-cleanup.mjs:1038-1046 unchanged; TEST-047 PASS; 806 crash sequences byte-exact" }
      - { ac: Spec-AC-04, call: compliant, citation: "untouched; TEST-048 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "untouched; TEST-049 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "untouched; TEST-050 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "moved = lines appended in 181/181 (r4 series, previously 22 wrong) and 625/625 quadruple sequences; merge-cleanup.mjs:1021,1026. Caveat NB-r5-1: holds for a main ledger that is only appended to" }
      - { ac: Spec-AC-08, call: compliant, citation: "untouched; TEST-052 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "reset retirement and once-per-archive done unchanged; TEST-053 PASS; SEG0b: two intents on one archive give one done" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-054 PASS; segOffset-equal-length arms SEGEQ/SEGEQ2 exact; an equal offset never supersedes (j's done precedes the later intent)" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-055 ovc/itc PASS; RED log product_red (moved 5 vs 3); mutation row RED on replay; validator SEG0 (later segOffset 0) exact" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1021, issue: "The supersede rule assumes that a run which did not see an earlier intent j means j's append never happened. That holds while the main ledger is only appended to. If another writer rewrites main in a way that is not an append (e.g. drops an earlier line) between a crash after j's append and the resume, the resume misses j's shifted bytes and re-appends from 0. Its segOffset-0 intent then supersedes j, which never gets a done record. Moved reports 3 of 5 line writes; the duplicate stays visible in main and no byte is lost. Pre-delta gave 3 or 5 depending on whether the re-append crashed; r5 makes it 3 either way. D8's 'The moved count therefore equals the lines actually appended' does not state the append-only premise.", failure_scenario: "probe_r5_supersede.sh CX1: CRASH_AT ledger-move-after-append; tail -n +2 on main EVENTS; late line in the ride; CRASH_AT ledger-move-after-append; apply --json: EV1/EV2 twice, L1 once, moved 3 (pre-fix 5); CX1n (no second crash): moved 3 on both engines. Disposition: accepted residual; optionally add 'for a main ledger only appended to' to the D8 sentence at the next touch." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1021, issue: "Mutants of judgedMissing survive TEST-051/053/054/055: (a) '<' to '<=', (b) drop the 'segOffset <= l.length' validity clause, (c) only the immediately next intent may supersede. I judge all three equivalent on reachable journals: a run that sees j writes j's done before its own intent (1034-1037 before 1041), so an equal offset never matters; tails only grow between resets, so the next intent's offset is below len_j exactly when that run missed j; validity only matters for a corrupted journal. INFO; no test needed.", failure_scenario: "probe_r5_mutants.sh le/novalid/first: all PASS; ctrl (the Test Plan mutation) fails TEST-055 with moved 5 vs 3." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1021, issue: "judgedMissing checks a later intent's segOffset against its recorded `length`; segAt (1030) checks against the archive bytes. A later intent that the malformed-field policy ignores (garbage segSha256, valid segOffset) still acts as a superseder. Corrupted-journal only: worst case moved under-counts, never a loss. INFO.", failure_scenario: "Hand-edit a later intent's segSha256 in journal.jsonl; the earlier appended intent gets no done record. Not reachable without journal corruption." }
  cannot_verify:
    - { claim: "No live journal in the main checkout carries ledger-append intents from this branch's earlier engines.", closes_with: "Read-only scan of /Users/ales/Projects/aai/docs/ai/archive/merge-cleanup/*/journal.jsonl for step ledger-append (out of bounds for this dispatch); ledger-append is absent from origin/main's engine." }
    - { claim: "Re-exec stdout piping on native Windows.", closes_with: "A Windows leg running TEST-049/050/052; unchanged by this delta." }
  overall: pass
```

## What the delta gets right

- The fix lives where the r4 analysis put it. A later intent's `segOffset` records what that run judged already appended, so it is the authority on whether an earlier intent landed. The rule is a single 1-line predicate plus one `continue`, with no new state.
- Ordering makes it safe. A resume writes the done record for every intent it sees before it writes its own intent (merge-cleanup.mjs:1034-1037 before 1041). Any later intent that would supersede an appended intent therefore comes from a run that did not see it. With an append-only main ledger that run cannot exist (the full argument is in the validation report).
- Validity guards stop a malformed later intent (non-integer, negative, beyond its own length) from superseding anything. Legacy intents without `segOffset` supersede nothing.
- TEST-055 pins both r4 shapes:
  - ovc: crash after intent, a late line, crash after append; moved 3.
  - itc: two after-intent crashes with late lines, then an append crash; moved 4 (r4 gave 9).
  - Its mutation row drops exactly the new `continue` and reddens.
- The D8 text now states the intent shape (NB-r4-2 closed). It also states the malformed-field policy with its duplicate residual (NB-r4-1 closed) and the supersede rule.
- `assert_no_merge_call` is kept and the selector case is wired; the default order runs TEST-055.

## Deviations from the frozen spec

- None against the amended spec. NB-r5-1 is a missing premise in D8's summary sentence, not a behavioural deviation.
- Amendment 16:39:32Z vs diff: matches (D8 supersede paragraph, malformed-field policy, shape, Spec-AC-11, TEST-055 row, V1 range, plan line, frozen_sha256 restamp). `spec-amend list --strict` rc 0; spec-lint 0 findings; docs-audit --gate SPEC-0223 PASS.
- The amendment is contract-class, signed by no one, tracked under fu-amend-merge-cleanup-ride-leftovers (open), like the earlier amendments of this ride. Owner signoff is still pending for the whole set.

## Warning dispositions (H6)

- NB-r5-1 (P3): (d) accepted residual. Reaching it takes a rewrite of the main ledger that is not an append, by another writer, inside a crash window. No byte is lost and the duplicate stays visible. The behaviour already existed without the crash. Optional one-clause D8 qualifier at the next touch; no follow-up.
- INFO-1 (equivalent mutants), INFO-2 (corrupted-journal superseder): no action.

## Next steps

1. Orchestrator: review gate pass; proceed to push / PR update.
2. state_update_commands (dispatched; not run): `node .aai/scripts/state.mjs set-code-review --required true --status pass --scope "746c78e4..436b51f9" --base-ref 746c78e4 --report docs/ai/reviews/review-20261011T1718Z-merge-cleanup-ride-leftovers-r5.md --notes "r5 pass: F-r4-1 fixed by later-segOffset supersede; NB-r5-1 accepted residual (non-append main-ledger rewrite); equivalent mutants INFO"`
