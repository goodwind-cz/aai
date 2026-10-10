# Code review: classify-same-ts-pair (round 1)

```yaml
review:
  scope: origin/main...HEAD (cf39c58f...49c9c520), worktree /Users/ales/Projects/aai-change-classify-same-ts-pair, branch change/classify-same-ts-pair
  spec: docs/specs/SPEC-0219-spec-classify-same-ts-pair.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/spec-amend.mjs cmdClassify --record branch (entry[RECORD_OVERLAY_FIELD], lookup via byRecord); fold D4 union; TEST-001, TEST-002" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "cmdClassify ambiguous/no-match/indistinguishable/format refusals via usageError (exit 2) before any append; TEST-003 four arms + positive control" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "independent probe: cf39c58f engine vs HEAD engine over cf39c58f ledger -> 380 items, counts, violations, notes all equal (record_key stripped); live ledger -> only ae5529c8b535 differs (the one targeted record); TEST-004, TEST-005" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "landedRecord + earlierInPair/collisionNote in cmdAdd and cmdRestamp; TEST-006, TEST-007" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "printedClassify + pairIsShared in cmdList and cmdRestamp; unshared token join byte-equal to the old template; USAGE/help name --record; record_key in list --json; TEST-008" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "decisions.jsonl appended lines (classifies_record ae5529c8b535, source cites 'Podepsat' and PR #448; two follow_up_status done); probe: HEAD engine list --strict exit 0 on the live ledger, 1c45f52a2649 measurement with classified_by null; TEST-009" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/spec-amend.mjs, line: 552,
          issue: "D7 mandates the duplicate-key NOTE tail change to 'only `classify` without --record refuses such a pair, as ambiguous'; the NOTE is unchanged and still says 'only `classify` refuses such a pair' (deviation from the frozen spec).",
          failure_scenario: "an operator runs `spec-amend list` on the live ledger (36 shared pairs), reads that classify refuses such a pair, and concludes the record cannot be signed at all - the new --record mode the scope exists for is hidden by the tool's own NOTE." }
      - { rank: NON-BLOCKING, file: .aai/scripts/spec-amend.mjs, line: 440,
          issue: "D4 union history is pair-overlays.concat(record-overlays).sort(byTsAscending); a same-second tie is broken by that concat order, not by ledger order, so a record-addressed overlay always beats a pair-addressed one with the same ts even when the pair overlay is the later line.",
          failure_scenario: "reproduced in scratch: record overlay (owner_signoff true) then, on a later line with the same ts, a pair overlay (owner_signoff false) on an unshared pair -> record folds signed. Live path: two classify calls on one record within one second (first --record ... --signoff owner, then a pair-addressed --signoff none, which --record on an unshared pair allows); the second call's post-append proof then exits 1 'did not land' although it appended." }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 0,
          issue: "Old-reader consequence on the LIVE ledger: the cf39c58f engine cannot see the record-addressed overlay (correct, D3) but now sees the record's tracker fu-amend-directed-merge-and-post-007bae as done, so it buckets ae5529c8b535 unsigned-untracked and `list --strict` exits 1, printing a pair-addressed remedy that is itself refused as ambiguous. Spec-AC-03 carves the targeted record out, so this is compliant; D3's 'an old reader keeps the record unsigned' is true but incomplete.",
          failure_scenario: "probe: node <cf39c58f spec-amend.mjs> list --strict --ledger <HEAD decisions.jsonl> -> rc=1 (cf39c58f ledger -> rc=0). Bites any reader that gets this ledger without the new engine (a ledger-only merge, an older vendored copy pointed at this ledger)." }
  cannot_verify:
    - { claim: "Mutation rows bite as declared (mutation-gate at close)",
        closes_with: "mutation-run.mjs per row + mutation-gate.mjs (Validation; not run here per dispatch)" }
    - { claim: "V1/V4 suites green under concurrent load and on CI Linux/Windows (incl. TEST-006/007 seed_window timing, -1..+8 s)",
        closes_with: "Validation V1/V4 runs and the PR CI legs" }
    - { claim: "PowerShell rendering of the --record remedy on Windows",
        closes_with: "CI Windows leg running TEST-1381-style verbatim execution (token is plain 12-hex, so low risk)" }
  overall: pass
```

## Scope

`git diff origin/main...HEAD` in the worktree, base cf39c58f, head 49c9c520
(f04b4d2f, 58a4d0b8, a879b9fc, 45042846, 49c9c520). Spec frozen, ceremony L2,
strategy tdd. No suites or mutation runs executed (dispatch: Validation runs
them concurrently); scratch probes ran on copies under the session scratchpad
with `--ledger`, never on the shipping ledger.

Coaching check: the dispatch named focus areas (append-only, fold invariance,
old-reader safety, remedy byte-identity, fail-open writers). These match the
spec's own ACs and are not pre-rated findings; the full scope was reviewed.

## Focus checks

- Append-only: `docs/ai/decisions.jsonl`, `docs/ai/EVENTS.jsonl`,
  `docs/ai/tests/test-runs.jsonl` - origin/main blob is a byte-exact prefix of
  the HEAD file (cmp of `git show origin/main:<f>` vs `head -c <base size>`),
  and committed HEAD equals the worktree file. Appended: 1 directed_merge
  (PR #448, orchestrator move), 1 classification overlay, 2 follow_up_status.
- Fold invariance: cf39c58f vs HEAD engine over the cf39c58f ledger: 380/380
  items equal with record_key removed, counts, violations and notes equal,
  380 distinct keys. Live ledger: exactly one item differs (ae5529c8b535,
  unsigned-untracked under old vs signed under new) - the targeted record.
- Old reader never applies a record overlay: confirmed by construction
  (`overlayKey(undefined, undefined) === null` -> dangling) and by probe (old
  engine: record not signed, dangling NOTE 1). See NB-3 for the strict exit.
- Remedy byte-identity: `printedClassify` joins the same tokens the old
  template interpolated; for an unshared pair the line is identical for both
  `list --strict` and the unverified-restamp NOTE.
- Fail-open writers: `add`/`restamp` never refuse on collision; the timestamp
  is untouched; the proof reads the appended record by content key.
- Other readers of `spec_amendment_classification`: none outside
  spec-amend.mjs and its suite (grep over .aai and tests).
- No gitignored file in the diff (`git check-ignore --no-index` empty).

## Deviations from the frozen spec

1. D7 duplicate-key NOTE text not changed (NB-1).
2. TEST-006/007 seed window is -1..+8 s (10 records) where the Test Plan says
   a 6 s window - wider, strictly safer; disclosed, no action.
3. CHANGELOG entry not present yet - the spec places it at the product-docs
   step, so not a deviation at this point; Validation/PR should confirm it lands.

## Findings and dispositions (H6)

- NB-1 (P3, spec deviation, misleading output): recommended disposition
  **remediate-in-tree** - one string at spec-amend.mjs:552; no test pins the
  current text (grep), TEST-004 does not compare notes.
- NB-2 (P3, same-second tie order across the D4 union): recommended
  disposition **promote-to-follow-up-ref** (suggested: fu-record-overlay-tie-order)
  - the fix (sort by ts then ledger index) needs its own RED test and touches
  D4's literal wording; or remediate-in-tree if the orchestrator prefers.
- NB-3 (P3, old-reader strict red on the live ledger after the tracker
  closed): recommended disposition **accepted residual** - "accepted residual:
  an old engine reading this ledger without the new engine reports
  ae5529c8b535 unsigned-untracked and exits 1 on --strict; only reachable in
  a mixed-version window, no false record is written" - and disclose it in
  the CHANGELOG entry.

INFO: TEST-009's `"by":null` substring is satisfied by the sibling row; the
signed row's `classified_by` being set is implied by bucket signed but not
asserted directly.

## Next steps

Remediate NB-1 in tree (or record a disposition), record NB-2 and NB-3
dispositions, then Validation V1-V4 and mutation gate.
