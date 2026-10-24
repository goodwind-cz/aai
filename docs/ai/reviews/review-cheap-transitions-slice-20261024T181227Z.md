# Code Review — cheap-transitions-slice, round 8 (post-PR delta)

Intended path: docs/ai/reviews/review-cheap-transitions-slice-20261024T181227Z.md

```yaml
review:
  scope: "delta bee57db1..8c05ba7a (remediation round 6, unpushed); full range ba552b89..8c05ba7a; PR #498 at bee57db1"
  spec: docs/specs/SPEC-0250-spec-cheap-transitions-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "untouched by delta; TEST-2701 green in test-aai-recheck.sh (rc 0)" }
      - { ac: Spec-AC-02, call: compliant, citation: "untouched by delta; TEST-2702 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "untouched by delta; TEST-2703..2706 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "orchestration-dispatch.mjs:1789-1795 hashOpts; delta prompt_hash == canon --print-hash --recheck delta == independent sha256 over framed RECHECK_DELTA+CONTRACT (TEST-2745); fallback hash stays full (orchestration-dispatch.mjs:1717); TEST-2708 parity green with stripped env" }
      - { ac: Spec-AC-05, call: compliant, citation: "untouched; TEST-2710.. green" }
      - { ac: Spec-AC-06, call: compliant, citation: "canon.mjs:406-410 delta skips learned only under opts.delta; TEST-2745 asserts no LEARNED text in delta payload" }
      - { ac: Spec-AC-07, call: compliant, citation: "untouched; suite green" }
      - { ac: Spec-AC-08, call: compliant, citation: "recheck-measure.mjs re-run: CR 33082/11395 0.344, V 45843/11394 0.249 = D11 and decisions.jsonl measurement record" }
      - { ac: Spec-AC-09, call: compliant, citation: "RFC-0017 phase 4 row 32720 to 11395, 45467 to 11394, status in progress" }
      - { ac: Spec-AC-10, call: compliant, citation: "untouched; suite green" }
      - { ac: Spec-AC-11, call: compliant, citation: "RECHECK_DELTA 3557 B <= 4096; ORCHESTRATION 45 lines <= 45; TEST-2718/2719/2746 green" }
      - { ac: Spec-AC-12, call: compliant, citation: "no new files in delta; suite green" }
      - { ac: Spec-AC-13, call: compliant, citation: "spec-amend list --strict rc=0 (read directly)" }
      - { ac: Spec-AC-14, call: compliant, citation: "untouched; suite green" }
      - { ac: Spec-AC-15, call: compliant, citation: "untouched; suite green" }
      - { ac: Spec-AC-16, call: compliant, citation: "untouched; suite green" }
      - { ac: Spec-AC-17, call: compliant, citation: "unsetEnv/cleanEnv still scrub/force AAI_RECHECK_MODE; TEST-2738 green" }
      - { ac: Spec-AC-18, call: compliant, citation: "RECHECK_DELTA contracts intact; suite green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/check-role-output.mjs, line: 959,
          issue: "RECHECK-ESCALATION is printed for ANY role and ANY round (full or delta): the checker cannot see recheck.mode, yet its stdout text says 'not a human stop: re-run ... and dispatch the full role' unconditionally. Spec D8 and SUBAGENT_PROTOCOL say the same reason from a full round is an ordinary BLOCKED; only the LLM orchestrator's memory of the dispatch JSON separates the two. TEST-2746 has no full-round control.",
          failure_scenario: "The full role re-dispatched after an escalation (or any full Validation/Code Review/Implementation role echoing the wording) returns BLOCKED with blockers [needs_full_recheck]. check-role-output exits 0 and tells the orchestrator it is not a human stop and to re-run full; an orchestrator that relays checker output re-dispatches full again instead of raising human_input. The loop is bounded only by the word 'once' in prose." }
      - { rank: NON-BLOCKING, file: .aai/ORCHESTRATION.prompt.md, line: 14,
          issue: "The EXCEPTION line sits after 'append its run ... Then run any returned state_update_commands. Then step 5.' and does not say to skip state_update_commands, while SUBAGENT_PROTOCOL.md:330 says 'merge nothing from it'. Two canon sites disagree on whether the escalated round's commands run.",
          failure_scenario: "A delta checker returns BLOCKED needs_full_recheck together with a set-validation/set-code-review command. A serial orchestrator reading ORCHESTRATION literally runs it (recording a verdict for a round that judged nothing, which can also plan a check_verdict stamp and change the next delta eligibility), while the parallel path following SUBAGENT_PROTOCOL drops it." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/prompt-diet-ledger.sh, line: 262,
          issue: "The new 307 B entry narrates 'the 4000 B round 1 to 3 credit held 61 B headroom, the round 6 growth is 368 B'. Measured: ORCHESTRATION 3641 -> 3889 (+248) and RECHECK_DELTA 3498 -> 3557 (+59) = +307; the 4000 B entry itself records headroom 0/2048, and TEST-010 now prints headroom 0/2048. The credited number (307) is right; the narrative is a false record of growth and headroom.",
          failure_scenario: "A later diet audit reconciling entries against wc -c finds a claimed 368 B growth and 61 B prior headroom that no measurement reproduces, and either re-credits the phantom 61 B or distrusts the ledger." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0250-spec-cheap-transitions-slice.md, line: 521,
          issue: "Test Plan rows map TEST-2745 to Spec-AC-04 and TEST-2746 to Spec-AC-11, but the AC Status rows for Spec-AC-04 (line 521) and Spec-AC-11 (line 528) still cite only TEST-2707..2709 and TEST-2718/2719 and their logs. spec-lint passes, so nothing enforces it.",
          failure_scenario: "A reader or docs-audit verify of Spec-AC-04/11 walks the AC row evidence and never reaches the tests that pin the delta identity and the escalation; dropping TEST-2745/2746 later would leave the AC rows looking fully evidenced." }
  cannot_verify:
    - { claim: "TEST-009 and TEST-2708 go green on the hosted Linux runner", closes_with: "CI run on 8c05ba7a after push (headSha match); macOS has no 128 KiB MAX_ARG_STRLEN, so the stdin fix was verified by reading and by local suite rc 0, and TEST-2708 by a stripped env -i run" }
    - { claim: "An LLM orchestrator actually takes the escalation path (no human_input, one full re-run) and does not loop", closes_with: "a live ride where a delta round returns needs_full_recheck; TEST-2746 pins prose, checker output and dispatch re-run only" }
    - { claim: "Codex threads 4367919430 and 4367919433 are answered and resolved", closes_with: "inline replies citing 8c05ba7a + TEST-2745/2746 and GraphQL resolve after push" }
  overall: pass
```

security_relevant: false

## Scope and method

- Delta read in full: `git diff bee57db1..8c05ba7a` (18 files). Full range ba552b89..8c05ba7a covered by suites, not re-read line by line (rounds 1-7 did).
- Probes in a scratch clone (`cr26-work/repo`, `cr26-work/probe`); worktree untouched; AAI_RECHECK_MODE=full, AAI_ROLE unset.
- Dispatch note (anti-gaming): the dispatch restated the commit's claims and listed focus checks; it did not pre-rate severity. The full delta was reviewed regardless.

## Evidence

| Command | rc |
|---|---|
| test-aai-recheck.sh | 0 |
| test-aai-spec-amend.sh | 0 |
| test-aai-prompt-diet.sh (TEST-010 headroom 0/2048) | 0 |
| test-aai-pr-preflight.sh | 0 |
| test-aai-prompt-hash.sh | 0 |
| test-aai-canon.sh | 0 |
| test-aai-orchestration-dispatch.sh | 0 |
| test-aai-role-output.sh | 0 |
| `env -i PATH HOME node --test recheck.test.mjs` (CI-like env, no harness vars) | 0, 47/47 |
| `spec-amend.mjs list --strict` | 0 |
| `spec-lint.mjs --path SPEC-0250` | 0 |
| `mutation-gate.mjs --spec SPEC-0250` with the worktree's mutation records copied in | 0, GATE PASS 46 rows, degraded 0 |
| `recheck-measure.mjs` | 0, 11395 / 11394 |

## Check answers

1. **TEST-2708 pin is honest.** CI log line 733: `suggested_model ... null`; the delta/full `deepEqual` loop had already passed (null == null), so parity held on the runner. Null comes from Mode B routing with an undetected harness, which is pre-existing behavior identical in both modes, not a gap this slice adds. Mutation: with the pin removed under `env -i`, TEST-2708 fails (reproduces CI); with the pin it passes. The independence assertion still means something: under a known harness it proves the suggested model differs from the implementer and matches full mode. The new `harness === 'claude'` assert proves the pin took effect.
2. **TEST-009 stdin fix is correct.** `<<<"$open_json"` is a here-string, so no exec argv. The live `follow-ups list --json` is 236059 B, over 128 KiB. The other large-JSON sites in spec-amend use `json_field`, which is `printf` builtin piped to node (no exec argv), or pipelines and file paths (line 3010). No remaining argv hazard found in the touched suites.
3. **Hash identity.**
   - Full mode is byte-identical to base. The base `prompt-hash.mjs` and the head one give the same `computeEffectivePromptHash` and `componentHashes` for all 69 `.aai/*.prompt.md` files on the head tree. Base `canon.mjs --print-hash` and head give the same result for every role.
   - The delta hash covers exactly what is sent: role(recheck) + contract, framed. TEST-2745 compares it against an independent sha256, and mutating any of canon, dispatch or prompt-hash turns it RED. All three mutations were reproduced here.
   - `recheck.fallback.prompt_hash` stays the full hash.
   - The only consumer of `inherits.learned` is `humanBlock`, and it handles null.
4. **Escalation.**
   - No human-stop path is weakened: two blockers, another blocker, or invalid timing all stay ordinary BLOCKED, and a dodge by the delta checker still lands on a full role that can raise the stop.
   - No ledger noise on re-dispatch: `planCheckStamps` sees the same head and seen, and no verdict, so it is a repeat and stamps nothing.
   - Delta is already ineligible for security-relevant refs, and escalating only makes the check stronger.
   - Residual: the checker cannot tell a full round from a delta round (NB-1).
   - The serial and parallel canon disagree on state_update_commands (NB-2).
   - The 45-line squeeze reads dense but unambiguous.
5. **Accounting.**
   - The diet credit of 307 equals the measured +248 +59, and TEST-012 is 62785. The narrative is wrong (NB-3).
   - D11 matches the measurement, and so do the RFC row and both decisions records.
   - The spec restamp holds: `spec-amend list --strict` rc 0.
   - `git ls-files -ci` returned empty, so no gitignored artifact is committed.

## Warning dispositions (recommended; orchestrator records)

- NB-1 (P3): remediate in tree. Add an optional `--recheck-mode` to check-role-output, or make the message say "delta round only", and add a full-round control to TEST-2746. Otherwise promote to `fu-recheck-escalation-mode-blind`.
- NB-2 (P3): remediate in tree. Add "run none of its state_update_commands" to the ORCHESTRATION exception, which may need wording within 45 lines.
- NB-3 (P3): remediate in tree. Correct the narrative to "+248 and +59 = 307 B growth, prior headroom 0". This is text-only, and the number is unchanged.
- NB-4 (P3): remediate in tree. Add TEST-2745 to the Spec-AC-04 row and TEST-2746 to the Spec-AC-11 row. This is a contract amendment record.

## Next steps

Push 8c05ba7a, then watch CI for TEST-009 and TEST-2708 on Linux. Reply to both Codex threads, then resolve them. Fold NB-1..4 or file them per the dispositions above.
