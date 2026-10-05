# Code Review — roadmap-maintenance-budget-advisory (CHANGE-0203)

```yaml
review:
  scope: "git diff 6e257659..ee1b7e65 (branch change/roadmap-maintenance-budget-advisory, worktree)"
  spec: docs/specs/SPEC-DRAFT-spec-roadmap-maintenance-budget-advisory.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/lib/roadmap-model.mjs:51-52,66-80; TEST-1600 PASS (rerun)" }
      - { ac: Spec-AC-02, call: compliant, citation: "roadmap-model.mjs:51-52 (duplicates), 68-77 (combined/empty/mode/threshold/MAX_SAFE); TEST-1601..1605 PASS (rerun)" }
      - { ac: Spec-AC-03, call: compliant, citation: "structural by D2 (rm.budget null in advisory, roadmap-model.mjs:79); TEST-1606 PASS (7-ref matrix + on control)" }
      - { ac: Spec-AC-04, call: compliant, citation: "ride-select.mjs waitingMaintenance/openIntakes/adviseMaintenance; TEST-1607..1612 PASS (deviation DEV-1 recorded below)" }
      - { ac: Spec-AC-05, call: compliant, citation: "ride-select.mjs adviseMaintenance (related wins); TEST-1613..1615 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "ride-select.mjs lastClosedCapability; TEST-1616..1620 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "ride-select.mjs main next branch (offJson/offText shared, proposal key order, bind before advisory); TEST-1621..1627, TEST-1645 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "ride-select.mjs cmdWaiting (runs before loadRoadmap); TEST-1628, TEST-1629 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "ride-select.mjs cmdShow advisory line + json key after budget; TEST-1630 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: ".aai/scripts/roadmap-edit.mjs parseArgs --threshold, setBudgetBlock, cmdBudget; TEST-1631..1635 PASS; reviewer probe of off->advisory->off->advisory->on->advisory chain on a budget-after-pairs fixture" }
      - { ac: Spec-AC-11, call: compliant, citation: "structural by D2; TEST-1636 PASS" }
      - { ac: Spec-AC-12, call: compliant, citation: ".aai/scripts/nothing-left-behind.mjs readRoadmapPairs (loadRoadmap first, line-scan only on invalid); TEST-1637 PASS" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-1638 PASS; tests/skills/test-aai-merge-policy.sh exit 0 (rerun)" }
      - { ac: Spec-AC-14, call: compliant, citation: ".aai/SKILL_ROADMAP.prompt.md action 7; TEST-1639 PASS" }
      - { ac: Spec-AC-15, call: compliant, citation: ".aai/SKILL_SHIP.prompt.md INPUT (round-1 B1 fix present: option (2) routed as a direct next --json answer); TEST-1640 PASS" }
      - { ac: Spec-AC-16, call: compliant, citation: "tests/skills/lib/prompt-diet-ledger.sh +736 and +131 entries; wc -c 3020->3434, 7714->8167 independently re-measured; TEST-1641 + TEST-012 (52109) PASS" }
      - { ac: Spec-AC-17, call: compliant, citation: "docs/USER_GUIDE.md posture row + Example 4; docs/product/roadmap.md Worked examples; TEST-1642, TEST-1643 PASS" }
      - { ac: Spec-AC-18, call: compliant, citation: "tests/skills/suite-map.yaml aai-ride-select block; TEST-1644 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/ride-select.mjs, line: 73,
          issue: "D3 closed-status set is TERMINAL_DOC_STATUS (adds legacy/current) and matched case-sensitively; recorded as a measurement-class amendment although it changes which intakes count",
          failure_scenario: "an issue/techdebt intake carrying status: current (or legacy) silently drops out of W; one carrying status: Done keeps counting. Live corpus today: 0 such docs (262 done, 15 draft, 24 superseded), so no observed bite. Same as validation round-1 NB3." }
      - { rank: NON-BLOCKING, file: .aai/scripts/ride-select.mjs, line: 173,
          issue: "--ledger (and the pre-existing --events) default to the vendored ROOT's ledgers even when --docs points at another tree",
          failure_scenario: "a caller runs `ride-select.mjs waiting --docs /other/project/docs` (or advisory next with only --roadmap/--docs) and W silently includes this checkout's 78 open P2 follow-ups. Every test and every prompt passes explicit or default-consistent paths, so no observed bite. Same as validation round-1 NB5." }
  cannot_verify:
    - { claim: "An LLM driving /aai-ship with no argument actually renders the propose_maintenance answer as ONE two-option menu and routes option (2) like a direct next answer (spec R1/S6)",
        closes_with: "a scripted /aai-ship dry run against a firing advisory fixture roadmap; TEST-1640 pins the prose only" }
    - { claim: "Every mutation record (45 rows incl. the round-1 remediated TEST-1601/1634/1640/1645) is RED against the current head",
        closes_with: "node .aai/scripts/mutation-gate.mjs over this spec at ee1b7e65 (evidence is gitignored/local-only; reviewer saw verdict: RED in the four remediated records but did not re-run the gate)" }
    - { claim: "Full-sweep green at ee1b7e65 (spec Verification: one full sweep before close)",
        closes_with: "AAI_TEST_TIMEOUT=3000 full sweep on the remediated head (round-1 sweep predates ee1b7e65)" }
  overall: pass
```

## Scope and preflight

- STATE: `worktree.user_decision: worktree`, branch `change/roadmap-maintenance-budget-advisory`, base `main`.
- `git status --porcelain` clean at head `ee1b7e65`; one scope: `git diff 6e257659..ee1b7e65` (7 commits, 19 files, +2484/-89).
- Spec: `docs/specs/SPEC-DRAFT-spec-roadmap-maintenance-budget-advisory.md` (frozen, three post-freeze contract amendments for validation round-1 NB1/NB2/B1, tracked by `fu-amend-roadmap-maintenance-budg-024dad`; one measurement amendment for TEST-1611). `spec-amend list --strict` exit 0.
- Coaching check: the dispatch named scope, refs and inputs only; it did not characterize findings or exclude areas.

## What was executed (reviewer's own runs, head ee1b7e65)

| Command | Exit |
|---|---|
| `env -u AAI_ROLE bash tests/skills/test-aai-ride-select.sh` | 0 |
| `env -u AAI_ROLE bash tests/skills/test-aai-roadmap.sh` | 0 |
| `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh` | 0 |
| `env -u AAI_ROLE bash tests/skills/test-aai-golden-flow.sh` | 0 |
| `env -u AAI_ROLE bash tests/skills/test-aai-spec-amend.sh` | 0 |
| `env -u AAI_ROLE bash tests/skills/test-aai-merge-policy.sh` | 0 |
| `node .aai/scripts/check-vendored-script-deps.mjs` | 0 (CLEAN, follow-ups.mjs and ride-select.mjs both `core` in PROFILES.yaml) |
| append-only prefix check of EVENTS.jsonl, decisions.jsonl, tests/test-runs.jsonl (base bytes are an exact prefix of head) | OK x3 |
| live-data probe: copy of docs/ai/roadmap.yaml + advisory threshold 95 → `validate` 0; `waiting --json` count 89, recommended 94; `next --json` → `related`, capability `configurable-merge-policy-lanes` (events), 2 candidates, alternative = off answer; text form = 3 lines | as spec'd |
| parser probes: `mode:advisory` (no space), trailing whitespace, budget after pairs, comment line inside the block → valid; budget twice → exit 2; mode+threshold+per_capability 2 → "cannot be combined" | consistent with D1 |
| roadmap-edit transition chain on a budget-after-pairs fixture | each step validates; block moved before `pairs:` |

## Spec deviations (listed even where reasonable)

- DEV-1 (D3): the closed-status set is `TERMINAL_DOC_STATUS` (done, deferred, rejected, superseded, legacy, current), not D3's four literals; status match is case-sensitive. Disclosed as a measurement-class amendment; it does change the counted set for two extra values. Spec-AC-04's enumerated cases all hold. See NB-1.
- DEV-2 (D11, undisclosed, behavior-equivalent): for a VALID `on` roadmap, `readRoadmapPairs` now returns `loadRoadmap`'s pairs instead of the line-scan pairs. Valid shapes restrict refs to SLUG and status to planned|active|done, so both readers yield the same pairs. INFO only.

## Findings

### NON-BLOCKING

- NB-1 — `.aai/scripts/ride-select.mjs:73` (`openIntakes`): status vocabulary drift from D3 (DEV-1) plus case-sensitive matching. Failure scenario: an intake with `status: current` or `legacy` drops out of W, and `status: Done` keeps counting. No such doc in the live corpus. **Recommended disposition: (d) accepted residual: P3 assurance-strength, no observed bite, no false record left anywhere. The amendment already discloses the superset.** If the orchestrator prefers to track it, it can join R7 under `fu-roadmap-docstatus-two-parsers`.
- NB-2 — `.aai/scripts/ride-select.mjs:173` (`parseArgs` `ledger` default) with the `--events` default it copies: both stay pinned to the vendored ROOT when `--docs` points elsewhere. Failure scenario: `waiting --docs <other tree>` counts this checkout's follow-ups. **Recommended disposition: (d) accepted residual: P3. It follows the existing `--events` convention, every caller in the corpus is consistent, and there is no observed bite.**

### INFO (never gate)

- `.aai/scripts/ride-select.mjs` (advisory branch in `main`, the comment above the text-form print) still says the text form "lands with Spec-AC-07 (TEST-1625) — not yet exercised". That is stale: TEST-1625 now covers it.
- The section comment above TEST-1600 in `tests/skills/test-aai-ride-select.sh` says "This file covers Spec-AC-01/02 only". That is stale.
- The SHAPE header comment in `docs/ai/roadmap.yaml` lists only `budget.maintenance_per_capability: 1`, and ride-select.mjs points readers at that header. It is not updated for the advisory form. D13 keeps the budget block out but does not forbid the comment.
- `openIntakes` sorts with `<`, which compares UTF-16 code units. That differs from D6's codepoint order only for astral-plane ids.
- `EVENTS.jsonl` carries `ac_status` events for Spec-AC-01/02 only, while the table marks all 18 ACs done. This is ledger hygiene for close-work-item and docs-audit, not a code defect.

## Round-1 remediation check (validation B1/NB1/NB2)

- B1: present. The `.aai/SKILL_SHIP.prompt.md` INPUT option (2) is now "handled exactly as if `next --json` had answered it directly", and the old "any other answer below" link is gone. TEST-1640 pins both, and its +131 B is credited in the ledger and moves the TEST-012 pin to 52109.
- NB1: present in both places. `lib/roadmap-model.mjs` and `roadmap-edit.mjs --threshold` compare the raw digit string with BigInt against `MAX_SAFE_INTEGER` before `Number()`. TEST-1601 and TEST-1634 cover it, and the cap value itself still validates.
- NB2: present. `openIntakes` derives the id from `extractDocIds` primary, else from the filename stem. TEST-1645 covers it.

## Warning dispositions (H6)

| Finding | Recommended disposition |
|---|---|
| NB-1 | (d) `accepted residual: P3 status-vocabulary superset (legacy/current) and case-sensitive match in openIntakes; 0 such intakes in the corpus, disclosed by the TEST-1611 measurement amendment` |
| NB-2 | (d) `accepted residual: P3 --ledger/--events default to the vendored ROOT independent of --docs; matches the pre-existing --events convention, every caller passes consistent paths` |

## Next steps

1. Independent re-validation (in flight) re-runs the mutation gate and the full sweep on `ee1b7e65` (cannot_verify 2 and 3).
2. Orchestrator records NB-1 and NB-2 dispositions, then PR. `roadmap-model.mjs` is a merge-policy GUARD_PATH, so the operator merges.
3. The owner sign-off for `fu-amend-roadmap-maintenance-budg-024dad` stays owed.
