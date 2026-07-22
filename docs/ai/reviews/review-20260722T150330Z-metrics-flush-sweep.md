---
title: Code Review — metrics-flush --sweep (durable-provenance stranded-ref flush)
ref_id: metrics-flush-strands-completed-refs
spec: docs/specs/SPEC-DRAFT-spec-metrics-flush-sweep.md
scope: git diff main...HEAD (feat/metrics-flush-sweep @ 7ab1381)
reviewer_model: claude-opus-4-8
---

```yaml
review:
  scope: "main...HEAD (feat/metrics-flush-sweep @7ab1381) — .aai/scripts/metrics-flush.mjs, .aai/METRICS_FLUSH.prompt.md, tests/skills/test-aai-metrics.sh, tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh"
  spec: docs/specs/SPEC-DRAFT-spec-metrics-flush-sweep.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "metrics-flush.mjs:109 sweep:false + :115 --sweep boolean parse + :124 usage lists --sweep; TEST-101 PASS" }
      - { ac: Spec-AC-02, call: compliant, citation: "metrics-flush.mjs:636-671 D1 gate → toFlush; TEST-102 PASS (golden key-set/order, verdict PASS)" }
      - { ac: Spec-AC-03, call: compliant, citation: "metrics-flush.mjs:656-664 fail-closed skips (no close event / non-done); TEST-103 PASS (ledger cmp -s byte-identical, in-flight byte-present)" }
      - { ac: Spec-AC-04, call: compliant, citation: "metrics-flush.mjs:606 closed set read only under opts.sweep; refactored default gate byte-equivalent; TEST-104 golden byte-equal + full TEST-006..023 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "metrics-flush.mjs:684-712 reused removeMetricsEntries/removeDoneWorkItems + integrity refusal; TEST-105 (in_progress untouched, no spurious reset) + TEST-106 (duplicate-key refusal, STATE+ledger byte-identical) PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "metrics-flush.mjs inLedger→toResume path unchanged; TEST-107 PASS (re-sweep Nothing to flush + after-ledger crash resume, no duplicate line)" }
      - { ac: Spec-AC-07, call: compliant, citation: "metrics-flush.mjs:631 pre-existing --ref filter; TEST-108 PASS (only ITEM-B flushed, ITEM-E not selected)" }
      - { ac: Spec-AC-08, call: compliant, citation: "closedRefs() read-only, empty Set when absent, never creates file; TEST-109 PASS (real close-work-item.mjs seam + absent-EVENTS fail-closed, no file created)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-prompt-diet.sh, line: 415,
          issue: "TEST-012 comment prose says the sweep added a '418 B itemized entry' to 'the prior 18560 B total', but the actual ledger entry is 738 B and the asserted total 19298 = 18560 + 738; the 418 in the comment is stale (superseded by commit 7ab1381 which corrected the ledger entry to 738 but not this comment).",
          failure_scenario: "A future maintainer trusting the comment recomputes 18560 + 418 = 18978 and 'corrects' JUSTIFIED_GROWTH_BYTES/the assertion to 18978, breaking TEST-012 (independent re-sum is 19298). Cosmetic only — the test currently passes because the assertion uses the entry's 738 prefix, not the comment." }
  cannot_verify:
    - { claim: "CI skill-suite is green at headSha == HEAD (7ab1381)",
        closes_with: "GitHub run 29931360344 is still in_progress at review time; the prior commit ebbe49e concluded success and I reproduced both suites (test-aai-metrics.sh + test-aai-prompt-diet.sh) green locally at HEAD — awaiting the HEAD run's terminal conclusion closes it." }
  overall: pass
```

## Scope & spec

- Diff: `git diff main...HEAD` on `feat/metrics-flush-sweep` (3 commits: 5a5efd0 feat, ebbe49e prompt reword, 7ab1381 ledger text).
- Spec: `docs/specs/SPEC-DRAFT-spec-metrics-flush-sweep.md` (SPEC-FROZEN: true, ceremony_level 2).
- Files: `.aai/scripts/metrics-flush.mjs`, `.aai/METRICS_FLUSH.prompt.md`, `tests/skills/test-aai-metrics.sh`, `tests/skills/lib/prompt-diet-ledger.sh`, `tests/skills/test-aai-prompt-diet.sh`.

## TELEMETRY-INTEGRITY scrutiny (dispatch checklist)

**STRICT provenance gate — genuine AND, close-event mandatory (PASS).**
The sweep block (metrics-flush.mjs ~636-671) is reached ONLY after the ref is not in the ledger (`inLedger.has` → resume path) and the default gate has failed. Inside it, flush requires ALL of: `entry.runs.length > 0` (else skip), `closed.has(ref)` (else `skip: no durable work_item_closed event — fail-closed`), and `statusByRef.get(ref) === 'done'` (else `skip: active_work_items status ... — fail-closed`). Each failing check `continue`s to the next entry; the only path to `toFlush.push` + `sweptRefs.push` is passing all three. The close-event check is a hard `if (!closed.has(ref)) { skip; continue; }` — it is AND-ed, never OR-ed away. No path flushes a swept ref without the committed close event.

**Exact-ref match — predicate parity (PASS).** `closedRefs()` builds the set from lines where `o.event === 'work_item_closed' && typeof o.ref === 'string'`, matched by `closed.has(ref)` (exact string equality). This is the same predicate as `close-work-item.mjs:279 hasWorkItemClosed`: `e.event === 'work_item_closed' && e.ref === ref`. No fuzzy/prefix/refMatches broadening. The numbered-vs-slug residual mismatch is documented in the spec (SEAM-1 RESIDUAL RISK) and fail-closes in the safe direction (no fabricated PASS).

**Default byte-unchanged (PASS).** The default gate was refactored from three `continue`-guards into an else-if chain producing `defaultReason` with the SAME precedence (validation → review → runs) and SAME message strings; `if (defaultReason === null) toFlush` else (no sweep) `skipped[ref] = defaultReason`. Behaviourally identical when `opts.sweep` is false. `eventsPath` is resolved but `closed` is `opts.sweep ? closedRefs(eventsPath) : new Set()`, so the default path never opens EVENTS.jsonl. Verified: TEST-104 golden ledger line byte-equal to TEST-006; full TEST-006..023 green.

**EVENTS.jsonl read-only, fail-closed (PASS).** `closedRefs()` only `readFileSync`s, returns an empty Set when the file is absent (no crash), defensively `try/catch`-skips malformed lines and `#`/blank lines, and never writes or creates the file. TEST-109 asserts `[[ ! -f EVENTS.jsonl ]]` after an absent-EVENTS sweep. No literal `work_item_closed`/`doc_lifecycle` emission anywhere in the flush path.

**Integrity / rollback / ordering reused (PASS).** Swept refs join `toFlush`; `completedRefs = toFlush + toResume` flows into the SAME `removeMetricsEntries`/`removeDoneWorkItems`, the SAME in-memory `duplicateKeys`/`inlineChildConflicts` pre-validation with `integrity refusal` (nothing written, original preserved), the SAME ledger-first-then-STATE ordering + atomic write + post-commit check-state. TEST-106 proves a structurally-invalid planned STATE under `--sweep` exits 1 with STATE and ledger byte-identical.

**Idempotence (PASS).** After a sweep the entries are gone from `metrics.work_items` → second `--sweep` matches nothing → `Nothing to flush.`; `inLedger` guard routes an already-appended ref to cleanup-only resume. TEST-107 covers both (incl. `AAI_FLUSH_INJECT_CRASH=after-ledger` resume with no duplicate line).

**STATE hygiene (PASS).** `removeDoneWorkItems` removes only `status === 'done'` items; swept non-focus refs are excluded from `partialRefs` (`r === focusRef || refMatches(vRef, r)`), so no spurious verdict-block reset. TEST-105 proves the `in_progress` item stays byte-present, `code_review` is not reset, and `implementation_strategy` is untouched.

**SPEC-0054 boundary (PASS).** The prompt reword states the sweep "Consumes that close record as provenance; it never emits one — close-work-item.mjs remains the sole emitter", and `--events` is read-only under `--sweep`. `grep` for `work_item_closed`/`doc_lifecycle` in the prompt returns none (prose "work-item close event" only).

**Ledger true-up (PASS).** Measured prompt byte-growth is exactly 738 B (`METRICS_FLUSH.prompt.md` 2454 → 3192). The ledger entry credits 738 B ("418 B initial + 320 B code-review reword") for 0 B headroom, within [0, 2048]. `JUSTIFIED_GROWTH_BYTES` re-sums to 19298 (18560 + 738); TEST-012 asserts 19298 == independent re-sum, green.

**No L3 path touched (PASS).** `docs-audit.yaml protected_paths_l3` lists state.mjs, state-engine.mjs, state-core.mjs, allocate-doc-number.mjs, pre-commit-checks.{sh,ps1}, WORKFLOW.md, CONSTITUTION.md — none of the five changed files. The design makes no STATE-schema/state.mjs change.

## Test quality

TEST-101..109 genuinely discriminate: TEST-102/108/109 assert the golden key-set/order and exact ledger ref; TEST-103 uses `cmp -s` for byte-identity and a NEGATIVE CONTROL (close event present but `in_progress` → never swept); TEST-104 pins the default path to the TEST-006 golden byte-for-byte AND proves a closed non-focus ref stays skipped without the flag; TEST-109's SEAM-1 drives the REAL `close-work-item.mjs` (no mock) to stamp the event, then sweeps it, plus an absent-EVENTS fail-closed leg. All fixtures are `mktemp -d` scratch repos (`mk_repo`/`mk_seam_repo`); no test reads or mutates the real `docs/ai/{STATE,METRICS,EVENTS}` — verified `git status --porcelain` clean of telemetry after running both suites.

## Anti-gaming note

The dispatch prompt characterized expected scrutiny areas (the STRICT gate, exact-ref, byte-unchanged, etc.). Per the ANTI-GAMING CONTRACT this is recorded, and the full scope was reviewed independently regardless. No area was scope-excluded.

## Warning disposition (H6)

- NON-BLOCKING #1 (TEST-012 stale comment "418 B" vs actual 738 B): recommended disposition — **remediate-in-tree** (one-line comment fix in `tests/skills/test-aai-prompt-diet.sh` to read 738 B / 19298). It does not gate merge (assertion passes; cosmetic only). The orchestrator records the disposition (decisions.jsonl or a follow-up ref) per the read-only-reviewer rule.

## Overall

**PASS** — both verdicts pass. Sweep eligibility is a genuine fail-closed AND on durable, tamper-evident provenance; the default path is byte-unchanged; integrity/rollback/idempotence machinery is reused unchanged; tests discriminate and touch only temp fixtures. One NON-BLOCKING cosmetic comment drift. One cannot_verify: the HEAD CI run is still in_progress (both suites reproduced green locally at HEAD).
