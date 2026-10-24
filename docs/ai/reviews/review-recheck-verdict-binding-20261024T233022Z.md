# Code Review r3 — recheck-verdict-binding (59ee0ff2..b9bdc239, delta 5b70bca8..b9bdc239)

Intended tracked path: `docs/ai/reviews/review-recheck-verdict-binding-20261024T233022Z.md`

```yaml
review:
  scope: 59ee0ff2..b9bdc239 (delta 5b70bca8..b9bdc239 = b9bdc239 round-2 remediation)
  spec: docs/specs/SPEC-DRAFT-spec-recheck-verdict-binding.md (L3, amended D7, D9, D13, D14, D15)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "planBindCheck dispatch path unchanged in delta; TEST-2801/2802 green (suite rc 0)" }
      - { ac: Spec-AC-02, call: compliant, citation: "planBindCheck verdict path unchanged; TEST-2803/2804 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "recheck.mjs:246-257 unchanged; TEST-2805/2806 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-2807..2813 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-2814/2815 green; probe SUBCMDS: every state.mjs subcommand and check-state --repair leave check_sticky byte-identical" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-2816 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2817 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-2818 green; append-event.mjs:178-182 comment now says the stamps are telemetry" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-2802 green" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-2819 green; SUBAGENT_PROTOCOL.md:66, CHANGELOG.md:32-40 name both writers and the per-STATE-file gap (B-1 r2 wording closed, see B-1 r3 for the remaining test name)" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-2820/2821 green; recheck.mjs:76 DEFAULT_ON; TEST-2821 extended (SPEC-0250 risk line, both recheck CHANGELOG headings, append-event.mjs)" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-2822..2824 green; no PROFILES or suite-map change in delta" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-2825 green; RFC-0017:307" }
      - { ac: Spec-AC-14, call: compliant, citation: "TEST-2826 green" }
      - { ac: Spec-AC-15, call: compliant, citation: "TEST-2827 green (title no longer says opt-in)" }
      - { ac: Spec-AC-16, call: compliant, citation: "TEST-2828 green; spec-amend list --strict rc 0 (read directly)" }
      - { ac: Spec-AC-17, call: compliant, citation: "TEST-2829/2830 green" }
      - { ac: Spec-AC-18, call: compliant, citation: "TEST-2831/2832 green" }
      - { ac: Spec-AC-19, call: compliant, citation: "check-binding.mjs:466-538 (keptLines, headerLine, duplicate merge), ride-handoff.mjs:448-458; TEST-2833..2839 green; TEST-2838/2839 mutation records RED; probes HOSTILE/DUP full, FRESH/BACK delta as the stated gap" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/lib/recheck.test.mjs, line: 3077,
          issue: "TEST-2837 is still titled 'the record is raise-only', and its selector is test_2837_record_raise_only (test-aai-recheck.sh:460, spec row line 694, mutation record selector). That is a universal claim (the record never goes down) over a test that asserts four paths: partial flush, full flush, reset-block and one later bind. The new D9 clause (spec line 345) says the claim 'that it can only go up' is made in no text of this scope. That statement is false while this title stands. r2 B-1 judged 'only ever raised' false, and this is the same claim; I missed it in r2",
          failure_scenario: "A reader of the suite output or the spec's Test Plan reads 'the record is raise-only'. Probes FRESH and BACK on b9bdc239 show the entry for the ref going from true to absent or false in the STATE file being decided, and both give delta. D9 claims no such text exists. Fix (either one): (a) retitle the node case to what it asserts (for example 'a flush and reset-block leave the record ...'; run_recheck_node_tests selects by the TEST id, so a title change is free), rename the selector to test_2837_record_kept in test-aai-recheck.sh and the spec row, and re-run mutation-run for TEST-2837 so the record's selector matches; or (b) retitle the node case and add to the D9 clause that the selector name is kept for its mutation record" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/check-binding.mjs, line: 510,
          issue: "The rebuild keeps an inline header byte for byte. With `check_sticky: []`, which is valid YAML and parses on its own, the rebuild emits `check_sticky: []` followed by item lines. state.mjs refuses that write ('would splice child lines under an inline-valued top-level header'), so bind-check fails for every ref in that STATE file. bindCheck in orchestration-dispatch.mjs:1586-1595 swallows the failure. The D15 sentence 'the entry for the ref being written gets security true' does not hold here, because nothing is written. On 5b70bca8 the same bind succeeded, normalised the header and raised the written ref",
          failure_scenario: "Probe INL: one hand edit to `check_sticky: []`, then bind-check --on dispatch for hotfix-two gives rc 1 and then for ride-one rc 1, and the STATE is unchanged. Every later tick binds nothing, silently, and every round is full. It fails closed (sticky_record_ambiguous) and needs an edit outside state.mjs, so it costs liveness, not security. Recommended disposition: follow-up P3 (suggested: fu-sticky-inline-header-blocks-bind). Possible fix: write a bare `check_sticky:` header and keep the inline value as an unparseable child line, so the reader stays ambiguous and the bind goes through" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-recheck-verdict-binding.md, line: 298,
          issue: "D7 recipe step 3 says '.aai/ORCHESTRATION.prompt.md can stay'. The flip f79fa2dc changed that file from 'opt-in, off unless AAI_RECHECK_MODE=delta' to 'default on; AAI_RECHECK_MODE=full opts out'. After the recipe runs, it would still say the default is on. Step 2's inverted TEST-2821 covers ORCHESTRATION.prompt.md, so it would also go red",
          failure_scenario: "If the owner declines the flip and someone follows the recipe as written, the orchestrator prompt states the wrong default. The gate in step 5 then fails without the recipe saying why. Recommended disposition: remediate in tree (add the file to step 3, including its prompt-diet byte delta), or fold it into fu-amend-spec-recheck-verdict-binding" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-recheck-verdict-binding.md, line: 678,
          issue: "TEST-2821's mutation cell moved from WORKFLOW.md to append-event.mjs. The shared five-document assertion (includes AAI_RECHECK_MODE=full, no opt-in sentence) no longer has its own mutation record",
          failure_scenario: "None observed. I applied the old cell (sed s/AAI_RECHECK_MODE=full/AAI_RECHECK_MODE=off/g on WORKFLOW.md) to a copy at b9bdc239 and TEST-2821 failed 1 ('workflow lacks AAI_RECHECK_MODE=full'). The new cell also fails 1. The assertion is intact; only the record that proves it bites is gone. accepted residual: P3 assurance strength, one mutation cell per row is the gate's model, the old cell still bites on b9bdc239 (probe this round), and no false record is left" }
  cannot_verify:
    - { claim: "The green logs Spec-AC-19 cites, docs/ai/tdd/recheck-verdict-binding/green/TEST-2838.log and TEST-2839.log", closes_with: "Both files are present. They were absent from the worktree at 23:2x UTC; the running validator was regenerating green logs (2833..2837 at 23:44) and may write them. My own suite run passed both cases" }
    - { claim: "The D7 recipe, end to end", closes_with: "Executing it on a scratch branch. I checked the nine-file conflict list (exact match), that the DEFAULT_ON toggle alone reproduces the pre-flip deltaEnabled, and every line reference (recheck.mjs 7-8/71-76, orchestration-dispatch ~1716, recheck.test.mjs 8-12, WORKFLOW 68, PARALLEL 149, RFC-0017 307)" }
    - { claim: "Linux CI and the Windows Pester leg on b9bdc239", closes_with: "PR CI run" }
    - { claim: "Full sweep (append-event.mjs is mapped by about 17 suites)", closes_with: "The validator's sweep. I ran aai-recheck, aai-ride-handoff and aai-spec-amend" }
    - { claim: "A live ride's delta round after the flip behaves like the fixtures", closes_with: "The first post-merge ride with an eligible round (D12)" }
  overall: fail
```

security_relevant: true

## Scope and preflight

- Scope: `59ee0ff2..b9bdc239`, focused on the delta `5b70bca8..b9bdc239` (one commit, b9bdc239). Reviewed in the scratch clone `cr29-work` at b9bdc239. It holds two scratch worktrees: `.base5b` (5b70bca8, for the before/after probes) and `.rev` (the trial revert, aborted). The worktree `/private/tmp/aai-recheck-binding` was only read.
- `AAI_RECHECK_MODE=full` and `env -u AAI_ROLE` on every run of mine; the fixtures set or unset the variable themselves.
- Coaching check: the dispatch listed the r2 findings and asked for specific checks. It said "mark only real defects BLOCKING", which is guidance on severity. I applied the role prompt's ranking rules instead (a universal-claim test name is BLOCKING). I reviewed the full delta.

## Evidence I ran

| Command | rc / result |
|---|---|
| `bash tests/skills/test-aai-recheck.sh` | 0 (84 PASS, incl. TEST-2838, 2839) |
| `bash tests/skills/test-aai-ride-handoff.sh`, `test-aai-spec-amend.sh` | 0, 0 |
| `node .aai/scripts/spec-amend.mjs list --strict` (rc read directly, output to file) | 0 |
| `node .aai/scripts/mutation-gate.mjs --spec <binding spec>` on the worktree's tdd evidence (copied) | 0, GATE PASS 39 rows |
| `node .aai/scripts/spec-lint.mjs --path <binding spec>` | 0 |
| decisions.jsonl, EVENTS.jsonl, tests/test-runs.jsonl at 59ee0ff2 and 5b70bca8 are byte prefixes of b9bdc239 (node byte compare) | all prefix OK |
| `git revert f79fa2dc` on b9bdc239 (scratch, aborted) | conflicts in exactly the nine files D7 names |
| TEST-2821 under the old WORKFLOW cell, and under the new append-event cell (copies, restored with cp) | fail 1, fail 1; baseline pass |
| probe file `cr29-work/tests/skills/lib/probe3.test.mjs` (r2 probes plus HDR, INL, SELF, FF, WTDMG, SHAPEBIND) | see below |

## Check 1 — B-1 closed

- Wording: SUBAGENT_PROTOCOL.md:66, CHANGELOG.md:32-40, check-binding.mjs:11-18, ride-handoff.mjs:448-451, D9 (new clause) and D15 Writers/Residual now name both writers (`state.mjs bind-check`, `ride-handoff.mjs out`, both through putStickyRaise), state the OR, list the commands that contain no code that opens the block, and state the per-STATE-file gap with its three cases. A code search confirms these are the only writers: only check-binding.mjs, ride-handoff.mjs and recheck.mjs reference the block, and `ride-handoff reconcile`/resetOrigin touch only focus, strategy, review, validation, tdd and worktree.
- Probes on b9bdc239:
  - HOSTILE: full [security_relevant:binding sticky_record_ambiguous]; on 5b70bca8 it was delta [].
  - DUP: full [security_relevant:binding security_relevant:sticky]; on 5b70bca8 it was delta [].
  - FRESH: delta [], the stated gap (STATE recreated in the same checkout).
  - BACK: delta [] with the origin entry false, the stated gap. Follow-up `fu-sticky-no-reverse-carry` is filed (decisions.jsonl).
  - COPY (a STATE file copied over another) gives delta after one re-bound round. That is an edit outside state.mjs, so the D9 residual covers it.
  - A3, A, B, THREE and FLUSH stay full. SUBCMDS, REPAIR and FLUSH leave the block byte-identical.
- Remaining: the TEST-2837 title and selector (B-1 r3 above).

## Check 2 — the rebuild

- Byte preservation: unparseable lines (string security, extra key, 4-space item, tab item, a bare `garbage: 1` mapping line) survive a bind for another ref byte for byte. They are appended after the sorted entries, so their position changes but their bytes do not. Every later round of every ref in that STATE file is full (sticky_record_ambiguous), and each tool still runs (check-state rc 0).
- Merge at the max flag:
  - Duplicates are merged at read time (OR of flags, union of paths). The rebuild writes one item, and the written ref is raised because `cur.problems.length > 0`. TEST-2839 covers both orders.
  - Probe FF: two false items for one ref read ambiguous (full) before any bind. After a bind for another ref they read as one clean false item, and the next round is delta. This matches "merge to the highest flag", and no true is lost (INFO).
- Interaction with ride-handoff:
  - Probe WTDMG: a worktree STATE with a damaged line keeps it through `ride-handoff out`, and the carried entry is raised.
  - An origin record with problems is carried as raised (TEST-2835).
- Fail-closed exception: an inline header (NB-1). Also, nothing clears a kept line except a hand repair, so one damaged line makes the whole STATE file full until then (INFO, liveness only; the spec's "every ref it might name" understates it, but errs in the safe direction).

## Check 3 — TEST-2821 WORKFLOW mutation cell

The assertion still bites under the old cell (fail 1). Only the mutation record for it is gone, and the gate models one cell per row. Disposition: accepted residual (NB-3 above). If more guard strength is wanted later, the alternative is a separate inspection row for the five-document loop.

## Check 4 — D7 recipe and ledger

- These match the code and history: the nine-file conflict list, the DEFAULT_ON toggle equivalence and the line references.
- The ORCHESTRATION.prompt.md "can stay" is wrong (NB-2).
- Ledgers are append-only (byte-prefix verified from both bases).
- spec-amend list --strict: rc 0.
- The corrective contract amendment (23:04:45Z) lists every section the delta edits: D7, D9, D15, Spec-AC-19, the TEST-2821/2838/2839 rows, plan step 10, Rollback and the RED line. It also lists what the 21:48:02Z record omitted, which closes r2 NB-5.
- The SPEC-0250 amendment covers its one line.

## Check 5 — stale overclaims

- The searches covered "only bind-check writes", "only ever raised", "raise-only", "can only go up" and the opt-in/off-by-default variants across .aai, docs (minus reviews, reports and archive), tests and CHANGELOG.
- The opt-in hits are all past tense or historical: SPEC-0250 lines 295, 306, 424, 680 and 696; CHANGELOG line 67; the D7 recipe.
- The one live overclaim is TEST-2837 (B-1 r3).
- The r2 NB-3 and NB-4 texts are fixed: the TEST-2742 pass line and the #498 heading, now pinned by TEST-2821.

## Warning dispositions (H6)

- NB-1 inline header blocks bind: promote to follow-up P3. Suggested id `fu-sticky-inline-header-blocks-bind`; the orchestrator files it.
- NB-2 D7 recipe ORCHESTRATION.prompt.md: remediate in tree, in the same commit as B-1 r3.
- NB-3 TEST-2821 cell: `accepted residual: P3 assurance strength; the old WORKFLOW cell still bites on b9bdc239 (fail 1, this round); no false record.`
- INFO: permanent ambiguity after a kept line; FF dedupe to false. No action.

## Next steps

1. Fix B-1 r3 with option (a) or (b), and NB-2 in the same commit. Option (a) needs a TEST-2837 mutation re-record; either option needs an amendment record for the D9 or Test Plan text.
2. Re-check round: delta-eligible only if no production path changes (a title-only change in recheck.test.mjs is test code). The ride is L3, so it stays full (ceremony_l3).
