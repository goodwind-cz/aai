# Code review: merge-cleanup-ride-leftovers, round r4 (delta)

- Ref: merge-cleanup-ride-leftovers (CHANGE-0210). Spec: docs/specs/SPEC-0223-spec-merge-cleanup-ride-leftovers.md (status done, frozen_sha256 6426c823..., ceremony_level 2, 10 Spec-ACs).
- Scope: `git diff HEAD~1..HEAD` = df72d175..746c78e4 in /Users/ales/Projects/aai-change-merge-cleanup-ride-leftovers (branch change/merge-cleanup-ride-leftovers, not pushed). Files: .aai/scripts/merge-cleanup.mjs (resume segment match, intent fields), tests/skills/test-aai-merge-cleanup.sh (TEST-054), the spec (D8, Spec-AC-10, TEST-054 row, V1, plan), docs/ai/decisions.jsonl (16:06:04Z amendment), docs/INDEX.md, docs/ai/EVENTS.jsonl. The surrounding resume loop (merge-cleanup.mjs:1004-1035) was re-read in full because the delta changes its match predicate.
- External input: Codex P2 on PR 455 (segment tracking in resume intents).
- Validation input: docs/ai/validation/VALIDATION-20261011T1627Z-merge-cleanup-ride-leftovers-r4.md (same round, FAIL on F-r4-1).
- Reviewer: claude-opus-5-5, independent, read-only. Implementer: claude-sonnet-5-5.
- Coaching note: the dispatch listed probe shapes to try (crash series, older intents, digest mismatch, earlier occurrence, empty segment). It did not pre-rate severity or exclude scope. The full delta was reviewed.

```yaml
review:
  scope: HEAD~1..HEAD (df72d175..746c78e4), worktree /Users/ales/Projects/aai-change-merge-cleanup-ride-leftovers
  spec: docs/specs/SPEC-0223-spec-merge-cleanup-ride-leftovers.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "untouched; TEST-045 PASS (r4 suite); replay RED" }
      - { ac: Spec-AC-02, call: compliant, citation: "untouched; TEST-046 PASS; replay RED" }
      - { ac: Spec-AC-03, call: compliant, citation: "merge-cleanup.mjs:1036-1043 append path unchanged except intent fields; TEST-047 PASS; validator crash series 181/181 byte-exact" }
      - { ac: Spec-AC-04, call: compliant, citation: "predicate untouched; TEST-048 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "untouched; TEST-049 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "untouched; TEST-050 PASS" }
      - { ac: Spec-AC-07, call: non-compliant, citation: "named gap F-r4-1: 'in every case the moved list SHALL hold ... lines equal the lines actually appended' fails after a crash at ledger-move-after-intent, a late line, and a crash at after-append/after-done (moved 5, appended 3); merge-cleanup.mjs:1019-1033; predates the delta" }
      - { ac: Spec-AC-08, call: compliant, citation: "untouched; TEST-052 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "reset retirement and once-per-archive done unchanged; TEST-053 PASS; replay RED" }
      - { ac: Spec-AC-10, call: non-compliant, citation: "its WHEN scenario holds (TEST-054 PASS, mutation RED, validator P2 sequence pre L1=2 vs HEAD L1=1) and the intent records segOffset/segSha256 (merge-cleanup.mjs:1038); but 'the moved list SHALL count each appended line once' fails in F-r4-1 (intent>+L1>append>+L2>* triples: moved 6 vs 4)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1028, issue: "Each open intent is matched independently. An intent that crashed before its append has the same mainLen as the next intent, whose append begins with the same archived bytes, so the never-appended intent matches inside the later append; it gets a resume done record (line 1030-1032) with its own lines and movedFromManifest (line 1064) sums both. Ledger bytes stay correct; the moved report and the journal hold a false record. Predates the delta (HEAD~1 identical).", failure_scenario: "CRASH_AT ledger-move-after-intent on a two-line EVENTS tail; append a late line to the ride EVENTS; CRASH_AT ledger-move-after-append; apply --json: journal intent A1 (2 lines, never appended), intent A2 (3), done A1 2, done A2 3; moved EVENTS 5, appended 3. Repro: docs/ai/validation/merge-cleanup-ride-leftovers-r4/probe_r4_overcount.sh; 22/181 crash sequences in probe-crash.log. Fix: an earlier intent counts as appended only if no later open intent for the ledger has segOffset < that intent's archive length (the later run already judged it unappended), or scan latest-first and stop at the first match; add a regression arm (intent crash, late line, append crash, moved 3)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1027, issue: "A segSha256 or segOffset that does not match the archive makes the resume ignore the intent, so its segment is appended again (duplicate) and moved under-counts the ignored append. No stop, no loss. The spec states no mismatch policy, and no test exercises the digest check (a mutant removing it would survive).", failure_scenario: "probe_r4_edges.sh TM sha-garbage / off-garbage / off-beyond / off-neg / off-string / off-equal-len: L1=2 after an edited journal intent. Reachable only through journal corruption." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0223-spec-merge-cleanup-ride-leftovers.md, line: 206, issue: "D8 step 2 still lists the intent record as { step, status, ledger, archive, sha256, mainLen, lines }; the engine also writes length, segOffset, segSha256 (the paragraph above names the last two).", failure_scenario: "A reader or a future journal parser keyed on the step-2 shape misses the segment fields. Documentation only." }
  cannot_verify:
    - { claim: "No live journal in the main checkout carries ledger-append intents from this branch's earlier engines (segment-only intents without segOffset would duplicate, probe O3).", closes_with: "Read-only scan of /Users/ales/Projects/aai/docs/ai/archive/merge-cleanup/*/journal.jsonl for step ledger-append (out of bounds for this dispatch); ledger-append is absent from origin/main's engine." }
    - { claim: "Re-exec stdout piping on native Windows.", closes_with: "A Windows leg running TEST-049/050/052; unchanged by this delta." }
  overall: fail
```

## What the delta gets right

- The P2 sequence is fixed: the pre-fix engine leaves the late line twice (L1=2), HEAD leaves it once, moved 3 (probe_r4_edges.sh P2). TEST-054 segcc/segtc pass, the Test Plan mutation (segment = whole archive) reddens on replay, RED log accepted as product_red.
- `segAt` validation (integer, 0..c.length, else 0) and the digest check are fail-safe: every malformed value degrades to "not appended", i.e. a duplicate, never a loss.
- The `from = mainLen` floor still holds for the segment: a segment present in main only before mainLen is not taken as appended (E1: seed + one move).
- An intent without segOffset is read as the whole archive (O1/O2 exact); the one shape it cannot read (segment-only intent from the HEAD~1 engine, O3) exists only on this unmerged branch, and D8 discloses it.
- Empty segment: after an after-append crash the resume writes no new intent (intents=1); a crafted empty segment is rejected by `atLineStart`.

## Deviations from the frozen spec

- DEV-1 (F-r4-1): Spec-AC-07 "in every case" and Spec-AC-10 "count each appended line once" do not hold for an after-intent crash followed by a later append of a longer tail.
- DEV-2 (NB-r4-2): D8 step 2 record shape is stale.
- Amendment 16:06:04Z vs diff: matches (D8 paragraph, Spec-AC-10, TEST-054, V1 range, frozen_sha256 restamp). spec-amend --strict rc 0.

## Warning dispositions (H6)

- F-r4-1 (BLOCKING, P2, leaves a false record): (a) remediate in tree if the owner grants a fifth round; otherwise, per the review-round cap (fourth finding-bearing round, standing extension already used in r3), split it out: (b) a typed follow-up (suggested id fu-merge-ledger-moved-overcount, P2) plus a disclosed contract amendment narrowing Spec-AC-07/10's moved clause until it lands. Recommended: (b) split, since the bug is separable and predates the P2 fix.
- NB-r4-1 (P3): (d) accepted residual is possible only with a D8 sentence stating the mismatch policy; recommended: fold the sentence into the F-r4-1 amendment.
- NB-r4-2 (P3): remediate in tree (one-line doc fix) with whichever commit carries the F-r4-1 disposition.

## Next steps

1. Orchestrator: STOP per round cap; choose split (follow-up + amendment) or ask the owner for a fifth round.
2. state_update_commands (dispatched; not run): `node .aai/scripts/state.mjs set-code-review --required true --status fail --scope "HEAD~1..HEAD (df72d175..746c78e4)" --base-ref df72d175 --report docs/ai/reviews/review-20261011T1627Z-merge-cleanup-ride-leftovers-r4.md --notes "r4 fail: F-r4-1 BLOCKING moved over-count + false done record (predates delta) -> split per round cap (fu-merge-ledger-moved-overcount); NB-r4-1 D8 mismatch-policy sentence; NB-r4-2 D8 step 2 shape"`
