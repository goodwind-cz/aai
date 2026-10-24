# Code Review r4: cheap-transitions-slice (FULL mode)

Intended path: docs/ai/reviews/review-cheap-transitions-slice-20261024T151951Z.md

```yaml
review:
  scope: "ba552b89..ffc7b7b9 (delta since r3: 26befd35..ffc7b7b9)"
  spec: docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-2701 green (node 42/42)" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-2702 green" }
      - { ac: Spec-AC-03, call: non-compliant, citation: "row text still names 'AAI_RECHECK_MODE=full (forced_full)'; code emits recheck_disabled (recheck.mjs:352); TEST-2706 Test Plan row says the same; NB-12" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-2707/2708/2709 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-2710/2711 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-2712/2713 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2714 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "recheck-measure.mjs rc 0: CR 33082/11336 (0.343), V 45843/11335 (0.247)" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-2716 green; RFC row 32720 to 11336, 45467 to 11335" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-2717 green" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-2718/2719 green" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-2720/2721/2722 green; prompt-diet suite rc 0" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-2723 green" }
      - { ac: Spec-AC-14, call: compliant, citation: "TEST-2725/2737 green" }
      - { ac: Spec-AC-15, call: compliant, citation: "TEST-2724 green" }
      - { ac: Spec-AC-16, call: non-compliant, citation: "B-10: an uncommitted in-place rewrite of an uncommitted earlier stamp gives delta, not ledger_rewritten (probe p1.log)" }
      - { ac: Spec-AC-17, call: compliant, citation: "TEST-2731/2732/2738 green; recheck.mjs:110-116" }
      - { ac: Spec-AC-18, call: compliant, citation: "TEST-2733 green" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/lib/recheck.mjs, line: 153,
          issue: "B-10: ledger_rewritten only covers lines that were committed before they were rewritten. Spec-AC-16 and D5 claim that an uncommitted rewrite of an earlier stamp refuses, and that no live read can lower a stamped true.",
          failure_scenario: "With AAI_RECHECK_MODE=delta set: a tick appends check_verdict{validation, head B, security_relevant:true} to the worktree, so it is uncommitted. The Remediation subagent flips it to false in place, flips the gitignored report marker (Q9), touches a test and commits. The next tick gives mode delta with no reasons. Neither the live file, the HEAD blob nor any commit in the range ever held the true line." }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 24,
          issue: "NB-11 (P3): the heading and first sentence say a re-check round 'now runs on a slim payload', and 'Downstream impact: re-check rounds are dispatched differently after /aai-update'. With the default off, rounds are dispatched as before.",
          failure_scenario: "A downstream operator reads the release notes and expects delta rounds after /aai-update. None happen unless they export AAI_RECHECK_MODE=delta." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md, line: 495,
          issue: "NB-12 (P3): the Spec-AC-03 row and the TEST-2706 Test Plan row (line 557) still name forced_full. The r3 amendment renamed that reason to recheck_disabled but did not edit these rows.",
          failure_scenario: "A validator walks AC-03 literally, looks for forced_full and finds the code never emits it. The frozen table and the code disagree." }
  cannot_verify:
    - { claim: "ledger_rewritten does not falsely refuse on a Windows checkout with core.autocrlf=true. EVENTS.jsonl has no eol attribute, so the live file may be CRLF while the blob is LF; this would refuse safely, but every round would be full",
        closes_with: "a run of recheckMode on a native Windows clone with autocrlf=true" }
    - { claim: "mutation-gate 37/37 and the mutation replay for the new TEST-2738..2741 cells",
        closes_with: "mutation-run --replay / mutation-gate in the ride worktree (the evidence is gitignored, so the clone cannot show it)" }
    - { claim: "hosted CI (Node 24 and the Node 22 floor, Linux) and the Windows Pester leg",
        closes_with: "PR checks" }
    - { claim: "no harness exports AAI_ROLE into the orchestrator's own shell. If one did, every check stamp would be refused silently and every round would be full",
        closes_with: "a live --confirm tick under each supported harness" }
  overall: fail
```

security_relevant: true

## Scope

- Review range: `ba552b89..ffc7b7b9`, with the r4 focus on the delta `26befd35..ffc7b7b9` (commit ffc7b7b9, remediation round 3).
- Spec: `docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md`, ceremony 3.
- Probes ran in the clone `cr22-work`. The ride worktree was only read.
- The marker stays true. It is sticky from r1 to r3, and B-10 is a gap in a security guard.
- Dispatch note: the owner decision and the six check items name the areas to check. They do not pre-rate severity or exclude scope, so this is not coaching. I reviewed the full range.

## Check items

**1. Is the opt-in default fail-closed?** Yes, at every site.
- `deltaEnabled` (recheck.mjs:110) returns true only when the value trims and lower-cases to exactly `delta`. Unset, empty and every other value give `recheck_disabled`.
- canon exits 11 and the dispatch field is `full` with the full `system_prompt` (TEST-2738, probed through a scrubbed env).
- The prose agrees: ORCHESTRATION:7, ORCHESTRATION_PARALLEL:149, SUBAGENT_PROTOCOL:62, RECHECK_DELTA:19 and WORKFLOW.md:68.
- WORKFLOW.md is L3-protected. This ride is L3, so the edit is legitimate, but it falls under the operator checkpoint before merge.
- `grep forced_full` finds no live code path. The only hits are the two stale spec rows (NB-12).
- CHANGELOG: the body says OPT-IN, but the heading and the downstream-impact line overstate (NB-11).

**2. `ledger_rewritten`: correctness and cost.**
- The per-commit chain works. It uses first parents and `--topo-order`, and refuses when it cannot read something.
- TEST-2739 and TEST-2740 cover two cases: an uncommitted flip of a committed stamp, and a committed flip inside the range.
- Gap, B-10: a stamp that is still uncommitted when it is rewritten leaves no trace in any blob, so the refusal never fires. Probe `cr22-probes/p1.mjs`, log `logs/p1.log`:
  - Before the flip: `security_relevant:stamp:validation`.
  - After an uncommitted flip: `delta`, reasons `[]`.
  - After committing the flipped tail: `delta`.
  - The same tree with the default env: `full [recheck_disabled]`.
- This is the realistic shape. The tick writes stamps into the worktree, and the next Remediation round runs before anyone commits them. Under the owner's framing it is raw-write forgery, but the spec claims it is closed:
  - Spec-AC-16: "an in-place rewrite of an earlier EVENTS.jsonl stamp (uncommitted, …) SHALL give ledger_rewritten".
  - D5: "no live read can lower a stamped true".
  - The residual as named covers only a forged append. An append cannot defeat a sticky true; this rewrite can.
- Cheapest fix: one contract amendment of AC-16, D5, SUBAGENT_PROTOCOL:62 and the CHANGELOG. Scope `ledger_rewritten` to lines committed at or before HEAD. Name the rewrite of the uncommitted tail as part of the residual in `fu-recheck-verdict-not-bound-to-check`. Add a test that pins it as a known residual. No code change is needed if the owner accepts it as residual. A code fix would need state the delta cannot write, which is the same follow-up.
- Cost, measured:
  - Real ledger (627 KB, the clone's EVENTS.jsonl; the dispatch said about 2 MB): 97 ms with one commit in the range.
  - Synthetic 1.25 MB ledger: 85 ms for 1 commit, 410 ms for 10, 1155 ms for 30, 2326 ms for 60. That is linear, about 40 ms per commit in the range that touches EVENTS. Extrapolated (not measured), 2 MB would be about 65 ms per commit.
  - It runs on every Validation or Code Review dispatch even while `recheck_disabled`, because reasons are collected, not first-match. INFO: short-circuit it when disabled.
  - Main's own history has a non-append commit, 71c7475a (#482). A ride that merges main with "base lines first" resolution also refuses. Both fail closed. INFO.
  - If EVENTS.jsonl were gitignored, the check would pass vacuously. Not the case here. INFO.

**3. Does the append-event `AAI_ROLE` refusal break a legitimate caller?** No.
- The only callers of `check_*` are `orchestration-dispatch.mjs` `recordCheckEvent` (1562-1576, which swallows failures) and the recheck tests.
- ORCHESTRATION's ENV row keeps `AAI_ROLE` unset for the orchestrator.
- No other suite greps for `check_verdict` or `check_dispatched`, and other event types are untouched (TEST-2741).
- The guard is stricter than state.mjs: it refuses any non-empty value, where state.mjs refuses only `subagent`. That fails closed.
- INFO: the state.mjs:1652 comment "append-event.mjs … never reads AAI_ROLE" is now stale.

**4. B8 (TEST-009): a legitimate correction, not a weakening.**
- `fitItemId` drops `spec-` and appends a hash when the stamped id exceeds 40 characters. I verified it: `sha256("spec-node-first-third-slice-20261024t1342")[:6] = 6a231a`, which is exactly `fu-amend-node-first-third-slice-2-6a231a`.
- So the old stem rule could never pass for a re-amended long spec id. Validation r3's statement that pickAmendItemId does not produce this id is refuted.
- The new arm is anchored: `startsWith("owner sign-off owed on the post-freeze amendment(s) to <sid>:")`, with the colon closing the id. The tracker must still be OPEN.
- SPEC-0165 Spec-AC-07 and TEST-009 promise "one open item per unsigned spec". The stem rule was the test's own mechanism, so no contract changes and no SPEC-0165 amendment is required. The rationale is recorded (remediation_decision, 14:56:19Z).
- INFO: a tighter check would recompute `amendItemIdStamped(sid, stampFor(ts))`.
- Stray line 2322 (`fu-amend-spec-node-first-third-slice` set to `open`): only follow-ups.mjs and spec-amend.mjs read `follow_up_status`, and `follow-ups.mjs list --status all` projects it as `done`. Its reason text ("reopened so the canonical id is open again") is wrong, but the 14:56:19Z decision record corrects it in the ledger. Harmless. INFO.

**5. B7: fixed.**
- `spec-amend list --strict` exit code read directly: 0, twice.
- frozen_sha256 moved from e962ca30 to 52235c77, disclosed by the 14:56:31Z contract record.
- `spec-lint --path` gives LINT PASS (rc 0).
- The aai-spec-amend suite is green, including TEST-007 and TEST-009.

**6. Diet ledger and pins.**
- The ledger credit is 4000.
- TEST-012 passes: `62478 == independent re-sum`.
- The pr-preflight regex constant is `+4000`, and TEST-008 is green.
- TEST-010 headroom is 0/2048.
- The `.aai/*.prompt.md` glob grew by exactly 61 B in round 3: ORCHESTRATION +44, ORCHESTRATION_PARALLEL +44, RECHECK_DELTA -27.
- INFO: the ledger text credits the 61 B partly to SUBAGENT_PROTOCOL, WORKFLOW and the ledger_rewritten wording. Those files are outside the glob. The number is right; the attribution is not.

## Prior findings

| Finding | Status |
|---|---|
| B-7 (r3) | Fixed. strict rc 0, anchor restamped. |
| NB-9 (r3) | Disposition recorded: opt-in default, append-event guard and named residual (decision 14:56:19Z). The B-10 gap is outside what that residual names. |
| Validation B7 / B8 / B9 F7 | Fixed, fixed, and partly fixed (B-10). |

## Evidence

All commands ran in the clone with `AAI_RECHECK_MODE=full` and `env -u AAI_ROLE`.

| Command | rc |
|---|---|
| node --test tests/skills/lib/recheck.test.mjs | 0 (42/42) |
| aai-run-tests.sh test-aai-recheck.sh | 0 |
| aai-run-tests.sh test-aai-spec-amend.sh | 0 (TEST-007 and TEST-009 PASS) |
| aai-run-tests.sh test-aai-prompt-diet.sh | 0 (TEST-012 62478, TEST-2722 4000) |
| aai-run-tests.sh test-aai-pr-preflight.sh | 0 |
| spec-amend list --strict | 0 |
| spec-lint --path SPEC-DRAFT… | 0 |
| recheck-measure.mjs | 0 |
| probe p1.mjs (B-10) | delta after an uncommitted rewrite and after committing it |
| eventsAppendOnly timing | 85 ms to 2326 ms (1 to 60 commits, 1.25 MB) |

## Warning dispositions (H6)

- **B-10 (BLOCKING):** fix in tree. Amend Spec-AC-16, D5, SUBAGENT_PROTOCOL:62 and the CHANGELOG to scope `ledger_rewritten` to committed lines, and name the rewrite of the uncommitted tail as part of the `fu-recheck-verdict-not-bound-to-check` residual. Add a test that pins the residual. Re-stamp last.
- **NB-11 (P3):** fix in tree. Make the CHANGELOG heading and the downstream line say the mode is opt-in.
- **NB-12 (P3):** fix in tree, in the same amendment. Rename forced_full to recheck_disabled in the Spec-AC-03 and TEST-2706 rows.
- **INFO items (no disposition owed):** the stale state.mjs comment, the diet-ledger attribution, the cost while disabled, the fail-closed false refusals, the tighter TEST-009 check, and line 2322.

## Next steps

1. Write one `spec-amend add` contract record covering B-10 and NB-12 (it re-stamps), and edit the CHANGELOG for NB-11. Run `list --strict` and mutation-gate afterwards.
2. Re-check is mechanical: wording plus one residual test. No production code changes.
