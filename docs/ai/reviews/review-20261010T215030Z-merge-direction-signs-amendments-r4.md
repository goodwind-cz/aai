```yaml
review:
  scope: 0fd520d7..378c84b7 (branch change/merge-direction-signs-amendments, delta round 4)
  spec: docs/specs/SPEC-0220-spec-merge-direction-signs-amendments.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/merge-cleanup.mjs:825-831,886-888; TEST-027 (red-TEST-027.log at 0fd520d7, green-TEST-027.log, mutation-TEST-027.txt replay RED); PFA-8" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "merge-cleanup.mjs:889 D9 anchor unchanged; no --direction + no human record -> recordDirection returns null (mode apply, empty direction) -> noop no_human_direction; TEST-020 mutation replay RED" }
      - { ac: Spec-AC-03, call: compliant, citation: "signable/rideKeys untouched by delta; TEST-021 replay RED" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "idempotence/resume: second apply with same --direction finds the record (findLast exact answer) -> no new directed_merge; signRecords/closeFullySigned unchanged; TEST-022 replay RED" }
      - { ac: Spec-AC-05, call: compliant, citation: "preflight path untouched; TEST-023 replay RED" }
      - { ac: Spec-AC-06, call: compliant, citation: "canon untouched; TEST-024 replay RED" }
      - { ac: Spec-AC-07, call: compliant, citation: "sign-merged untouched; TEST-025 replay RED" }
      - { ac: Spec-AC-08, call: compliant, citation: "live ledger: one appended spec_amendment record only; TEST-026 replay RED; spec-amend list --strict exit 0" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "the full test-aai-merge-cleanup.sh suite (incl. TEST-027 four arms and TEST-018..026) passes at 378c84b7",
        closes_with: "Validation r4 suite run (dispatch: Code Review reads only); mutation-run --replay re-ran each selected function under its mutation (10/10 RED) but not the unmutated GREEN pass" }
  overall: pass
```

# Code Review r4 — merge-direction-signs-amendments (CHANGE-0208 / SPEC-0220)

Scope: `git diff 0fd520d7..378c84b7` in the worktree, HEAD 378c84b7 (not pushed).
Single delta: the fix for Codex P2 thread 4239287901 on PR #452 ("Bind signatures
to the current merge direction"). No coaching in the dispatch beyond naming the
thread and the regression areas to check; full delta reviewed.

## Judgement against the thread

The thread: a preflight re-run with other words leaves several `directed_merge`
records; the forward `.find()` cited the oldest. Requested: match
`ctx.opts.direction` when available, else the latest record.

`humanDirection(ledger, pr, head, wanted)` (merge-cleanup.mjs:825-831) now
filters all matching by-human records, picks `findLast(answer === wanted)` when
`wanted` is non-blank, else `mine.at(-1)`. `signAmendments` (886-888) records
`--direction` first only when the selected record's answer is not exactly the
wanted words. Exactly what the thread asked. The RED log at 0fd520d7 reproduces
the defect (cites "merge 433 please" when `--direction "retry: merge 433 now"`).

Case walk:
- no `--direction`, no record: recordDirection returns null (empty direction), noop `no_human_direction` (D9 anchor line 889 verbatim) — unchanged behavior.
- no `--direction`, records exist: answer is non-empty, so `=== ''` is false and recordDirection is called, but it returns null on empty direction — no write. Cites latest. Correct.
- whitespace-only `--direction`: same as above (both sides trim-check). Correct.
- `--direction` matches an existing record: no write, cites it. Exact (untrimmed) comparison is consistent with appendDirectedMerge storing `rec.direction` verbatim.
- `--direction` new words: recorded, then the re-read picks it. Covered by the new_words arm.
- idempotence/resume: a re-run with the same words finds the record written by the first run, writes nothing new; overlays dedupe through the unchanged signRecords path. A re-run without `--direction` cites the latest, which is the record the first run wrote. Consistent.

## TEST-027

Four arms, each with a positive control on the directed_merge count after sync,
step `done`, exactly two overlays, wanted answer and ts present and the other
answer absent. The direction_first arm proves the fix is not just "latest";
direction_second reproduces the thread; latest pins the fallback; new_words pins
record-first. Registered in both the all-run list and the selector case. The
mutation cell `sed:s/mine\.at\(-1\)/mine[0]/` is a JS RegExp (mutation-run usage
confirms `\(` is a literal paren) and replays RED.

## D9 anchors

All eight D9 literals untouched by the delta; `if (!direction) return { status: 'noop', detail: 'no_human_direction' };` still verbatim at line 889.

## Spec / ledger

- PFA-8 appended under Post-freeze amendments; Test Plan row TEST-027 added (no pipes in cells); Spec-AC-01 evidence and notes extended; frozen_sha256 restamped.
- decisions.jsonl: one appended `spec_amendment` (class contract, owner_signoff false, tracked_by `fu-amend-merge-direction-signs-am-c6ee47`, which is open). Append-only: base is a byte prefix.
- EVENTS.jsonl: two appended docs_audit lines. Append-only.
- docs/INDEX.md: timestamp only.

## Commands run

- `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0220-...md` -> rc 0, 10/10 still redden, 0 inconclusive, 0 re-stamped.
- `node .aai/scripts/mutation-gate.mjs --spec ...` -> rc 0, GATE PASS 10 rows, degraded=0 unstamped=0 uncomparable=0.
- `node .aai/scripts/spec-amend.mjs list --strict` -> rc 0; new record lists as unsigned-tracked, tracker open.
- Suite not run (dispatch: Validation runs it).

## Findings

None BLOCKING, none NON-BLOCKING.

INFO (no gate):
- `Array.prototype.findLast` is a first use in `.aai/scripts` (Node >= 18). CI pins Node 20 and docs/TECHNOLOGY.md documents no floor; no failure on any supported runner.
- Pre-existing, outside the delta: `appendDirectedMerge`'s dedupe (line 764) ignores `by`, so a hand-written `by: orchestrator` directed_merge carrying the exact `--direction` words would suppress the human record and the step would cite the latest other human record. No such writer exists (merge-cleanup writes only `by: human`); noted, not owed.

## Warning dispositions

No WARNINGs; nothing to dispose.

## Next steps

Validation r4 result on the suite; push 378c84b7, reply to and resolve Codex thread 4239287901 citing 378c84b7 and TEST-027.
