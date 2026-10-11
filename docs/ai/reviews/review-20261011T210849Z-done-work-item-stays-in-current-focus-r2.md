# Code review r2: done-work-item-stays-in-current-focus

- Reviewer: claude-opus-5-5, independent of the implementer (claude-sonnet-5-5). This is a delta review after r1 PASS.
- Scope: `git diff HEAD~1..HEAD` (`72a697e9..a8b188ad`), commit "fix(metrics): --release matches close events like dispatch and is resumable". It addresses the PR #456 Codex threads P1 (4243107893) and P2 (4243107899).
- Files:
  - `.aai/scripts/metrics-flush.mjs`
  - `.gitignore`
  - `docs/specs/SPEC-0224-…md`
  - `tests/skills/test-aai-metrics.sh`
  - `tests/skills/test-aai-orchestration-dispatch.sh`
  - `docs/INDEX.md`
  - `docs/ai/EVENTS.jsonl` (ac_status and docs_audit lines)
  - `docs/ai/decisions.jsonl` (two amendments)
- Behavioural evidence: the validation r4 probes in `docs/ai/validation/done-work-item-stays-in-current-focus-r4/`.

```yaml
review:
  scope: HEAD~1..HEAD (72a697e9..a8b188ad)
  spec: docs/specs/SPEC-0224-spec-done-work-item-stays-in-current-focus.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01..19, call: compliant, citation: "unchanged since r1; mutation replay 28/28, suites 9/9; TEST-1387 cell re-pointed to hasCloseEventFor (amendment 20:43:13Z) and reddens" }
      - { ac: Spec-AC-20, call: compliant, citation: "scanCloseEvents uses refMatches metrics-flush.mjs:369-385 (byte-identical to orchestration-dispatch.mjs:134); TEST-1748; r4 probe4p/probe7p 0 wedges; fuzz 228,858 cases 0 disagreements" }
      - { ac: Spec-AC-21, call: compliant, citation: "STATE-first + in-flight record metrics-flush.mjs:1313-1330, resume :1176-1195; TEST-1749/1750; r4 probe-p2 5 crash points no false claim, no duplicate" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 1184, issue: "N11: resume premise 'item gone => this record's commit landed' is false when another writer released the same ref; dedupe is exact-line (eventsHasLine), so a semantically equal event from another session is missed", failure_scenario: "session B fully releases R after A read STATE and before A renames its record in; A's commit is rejected (concurrent modification) and its record survives; the next --release R resumes and appends A's event (reason sessionA) as a 2nd work_item_released (probe-p2b.log). Telemetry-only; same duplicate existed under the old EVENTS-first order. Fix: resume only if no work_item_released for ref after the last close, else drop the record." }
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 1184, issue: "N12: the resume conjunction omits the guard-4 fail-verdict predicates and any existing-release check", failure_scenario: "forged or stale record + item absent + last_validation fail naming the ref -> resume appends a release event (probe-p2 FAB failverdict); with a prior release event -> 2nd event (FAB already-released)" }
      - { rank: NON-BLOCKING, file: .aai/system/RUNTIME_IGNORE.list, line: 8, issue: "N13: docs/ai/STATE.yaml.release-pending* added to .gitignore only; RUNTIME_IGNORE.list is the single source aai-bootstrap/aai-sync reconcile into downstream .gitignore", failure_scenario: "downstream: a rejected/crashed release leaves an untracked marker -> merge-cleanup worktree_dirty refusal (merge-cleanup.mjs:838) or it is swept into a broad git add; spec's '(gitignored)' holds only in this repo" }
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 1182, issue: "N14: single-slot record — a release of R1 overwrites R2's pending resume record, and the stale-drop branch deletes any record whose ref is still in STATE, including another session's in-flight one", failure_scenario: "R2 crashes after STATE, R1 released, --release R2 now refuses 'absent' and R2's event is lost forever (probe-p2 other-ref-marker)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 1317, issue: "N15: '<state>.release-pending.tmp-<pid>' orphaned by a crash between writeFileSync and renameSync; nothing removes it", failure_scenario: "probe-p2 before-marker: tmpLeft=1 after a successful retry" }
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 1140, issue: "N16: nothing (dispatch, check-state, doctor) reports a pending record; after an after-state crash focus is null so no one is prompted to re-run", failure_scenario: "operator sees a crash, dispatch moves on, the release event is never written" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-metrics.sh, line: 3979, issue: "N17: no suite case crashes after the event append (dedupe branch untested; mutant 'if (true) appendReleaseEvent' would survive); TEST-1748 pins the two refMatches copies on one shape only", failure_scenario: "a regression in eventsHasLine or a drift between the two refMatches copies passes the suite" }
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 362, issue: "scanCloseEvents re-reads and re-parses EVENTS.jsonl per probe (up to 4 full reads on the resume path, 2 on the normal path) and duplicates refMatches instead of importing it", failure_scenario: "slower release on a large ledger; copies can drift (see N17)" }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 2097, issue: "N18: amendment 'what' says 'additive rows only, no existing AC changed' but the commit also inverts the Data-flows ordering contract (EVENTS-before-STATE -> STATE-before-EVENTS) and adds two Edge-case bullets", failure_scenario: "owner signing fu-amend-…-6aea5b reads the record and misses the contract inversion" }
  cannot_verify:
    - { claim: "Codex will accept the two threads as resolved", closes_with: "bot re-review after push; threads must also be resolved via GraphQL" }
    - { claim: "the real CHANGE-0199 wedge on the shared checkout releases end-to-end", closes_with: "dispatch + printed remedy on the live STATE after merge (gitignored; fixtures only here)" }
  overall: pass
```

## Spec compliance

Both new ACs are implemented as written. The prior 19 are unchanged; the one mutation cell moved by the rename was re-pointed and still reddens.

- **Spec-AC-20.** `--release` close provenance now runs through `scanCloseEvents`, which uses the same `refMatches` the dispatcher uses. A `docs/issues/CHANGE-0001` close is accepted for `CHANGE-0001` and never for `CHANGE-00011` or `x-foo`. `closedRefs` stays exact for `--sweep`/`--retire`.
- **Spec-AC-21.** Order is now: in-flight record, then STATE commit, then event, then record removal. A crash or rejection never leaves EVENTS claiming a release. A retry resumes event-only, or drops a stale record and re-evaluates. I verified this at five kill points, plus dry runs.

## Code quality

The change is small, readable and well commented. The fault seam follows the existing `AAI_STATE_INJECT_*` precedent. Every finding above is NON-BLOCKING.

N11 is the one worth taking in this PR, because it sits in the new resume branch and its fix is one predicate. That predicate is "no `work_item_released` for the ref after its last close". The same predicate also closes half of N12. N13 is a one-line downstream ignore-list addition.
