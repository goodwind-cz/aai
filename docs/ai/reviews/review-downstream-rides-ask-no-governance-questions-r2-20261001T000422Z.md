# Code Review — downstream-rides-ask-no-governance-questions (round 2 of 2, re-review after remediation)

- Reviewer: claude-opus-5-5, dispatched Code Review role (AAI_ROLE=subagent, read-only on implementation files)
- Scope: working tree of /Users/ales/Projects/aai-autopilot (branch change/downstream-rides-ask-no-governance-questions, uncommitted) vs base `main` (4c3d8a5d) — full diff re-walked, with focus on the round-1 fold: .aai/scripts/ride-select.mjs (gate block), .aai/SKILL_SHIP.prompt.md (1a, STRICT RULES), tests/skills/test-aai-downstream-autopilot.sh (mk_project), tests/skills/lib/prompt-diet-ledger.sh + tests/skills/test-aai-prompt-diet.sh (credit 656 -> 826, TEST-012 pin 45517 -> 45687), spec Test Plan TEST-1215 Mutation cell (second spec_amendment, decisions.jsonl ts 2026-09-30T23:34:58Z, tracked by fu-amend-downstream-rides-ask-no-d8106d), regenerated TEST-1206 patch, re-run TEST-1215 record.
- Round-1 report: docs/ai/reviews/review-downstream-rides-ask-no-governance-questions-20260930T232702Z.md
- Spec: docs/specs/SPEC-0200-spec-downstream-rides-ask-no-governance-questions.md
- No coaching in the dispatch (paths named, no expected findings or severities).

```yaml
review:
  scope: "main (4c3d8a5d) vs working tree of change/downstream-rides-ask-no-governance-questions (uncommitted), round 2"
  spec: docs/specs/SPEC-0200-spec-downstream-rides-ask-no-governance-questions.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/ride-select.mjs:274-287; TEST-1201/1202, test-aai-ride-select.sh exit 0" }
      - { ac: Spec-AC-02, call: compliant, citation: "branch gated on cmd==='gate'; TEST-1203/1204/1205 exit 0" }
      - { ac: Spec-AC-03, call: compliant, citation: "ride-select.mjs:275-277 precede the existsSync branch; TEST-1206 exit 0; regenerated mutation-TEST-1206.patch moves the branch above all four checks and is RED" }
      - { ac: Spec-AC-04, call: compliant, citation: "same predicate as orchestration-dispatch.mjs:732; TEST-1207 exit 0" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-1208 exit 0" }
      - { ac: Spec-AC-06, call: compliant, citation: "ride-select.mjs:13-18; .aai/AGENTS.md:317; TEST-1209 exit 0" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/SKILL_SHIP.prompt.md:39-46 and step 6 ride gate line; TEST-1210 exit 0" }
      - { ac: Spec-AC-08, call: compliant, citation: "four surfaces + SKILL_SHIP.prompt.md:104-105 STRICT RULES carve; TEST-1211 + test-aai-spec-amend.sh exit 0" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-1212/1213 exit 0" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-1214 exit 0" }
      - { ac: Spec-AC-11, call: compliant, citation: "prompt-diet-ledger.sh entry 826 B (659+84+83; reviewer measured SKILL_SHIP 6121 -> 6780 with /usr/bin/wc), want_growth 45687 = 44861+826, TEST-1215; prompt-diet exit 0; TEST-1216 exit 0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/ride-select.mjs, line: 280,
          issue: "The NB-3 fold (an --intake/--ref id mismatch is a usage error before the absent admit) ships with no regression test: no arm runs an absent roadmap with a mismatched --intake",
          failure_scenario: "A later edit moves line 280 below the existsSync branch at 283 (exactly what the regenerated mutation-TEST-1206.patch does, among other moves): TEST-006 still passes because it uses a present roadmap, TEST-1206 has no intake arm, the suite stays green, and the absent posture silently admits a mismatched intake again while the comment at 278-279 still claims otherwise" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-downstream-autopilot.sh, line: 40,
          issue: "The NB-4 fold moved the guard above rm -rf, but the guard cannot fail: d is \"$TEST_DIR/$1\", which is absolute whenever $1 is non-empty, even when TEST_DIR is empty; the mktemp result at line 30 is still unchecked",
          failure_scenario: "mktemp -d fails (unwritable TMPDIR): TEST_DIR='' so d='/t1207-absent', the guard passes, and `rm -rf /t1207-absent` plus mkdir under / run; harmless for a non-root user in practice, but the guard does not protect the case it was added for" }
  cannot_verify:
    - { claim: "Downstream agents actually stop asking roadmap/amendment questions (spec R1)",
        closes_with: "The owner's next real downstream /aai-ship ride transcript" }
    - { claim: "The new suite and the TEST-1208 default-roadmap arm pass on the Ubuntu CI runner",
        closes_with: "skill-suite.yml CI run on the PR head, headSha-matched" }
    - { claim: "Roadmap whose parent directory is unsearchable (existsSync false on EACCES) admits in both readers although D2 says a permission error refuses",
        closes_with: "A chmod 000 probe on docs/ai, or acceptance under the R2 residual" }
    - { claim: "Full sweep 100 suites (99 pass, win-fallback TEST-028 pre-existing) — taken from the validation round-2 report; the reviewer re-ran only ride-select, downstream-autopilot, prompt-diet, spec-amend, mutation-gate and spec-amend list --strict",
        closes_with: "docs/ai/reports/VALIDATION-20260930T233803Z-downstream-rides-ask-no-governance-questions.md evidence folder (already present)" }
  overall: pass
```

## Round-1 fold — judged per finding

| Round-1 | Fold | Verdict |
|---|---|---|
| NB-1 STRICT RULES amendment carve | SKILL_SHIP.prompt.md:104-105 "A post-freeze spec amendment is NOT one of them: `--signoff none` (default 5), never a question." | correct and complete |
| NB-2 rationale has no home | SKILL_SHIP.prompt.md:41-42 now says to carry the rationale into the step 6 `ride gate:` line and that STATE has no field for it | correct and complete. The rule "every autopilot decision is written to STATE" (line 101) is not qualified, but the 1a parenthetical removes the dead end |
| NB-3 --intake mismatch skipped when roadmap absent | ride-select.mjs:280 early check; the old late check is removed, so the governed posture also uses the early check (TEST-006 still green) | behaviour correct (reviewer probe: absent + mismatched intake now exit 2; absent + missing intake file still ADMIT, which is consistent with "not consulted"; governed refusal of an unresolvable intake, TEST-588, is unchanged). **Incomplete: no regression test** -> R2-NB-1 |
| NB-4 guard after rm -rf | guard moved to line 40, before the rm | **partial**: ordering fixed, but the guard is vacuous for the empty-TEST_DIR case it was meant for -> R2-NB-2 |

## New-introduction check
- Usage order in the governed posture changed: an id mismatch (exit 2) is now reported before a broken-roadmap refusal (exit 1). This is consistent with D3's "a malformed call is malformed in either posture". No existing test depends on the old order (ride-select suite exit 0).
- In the governed posture, readIntake now runs twice (once early, once at line 329). This is a cheap file read with no correctness effect.
- Spec deviation (listed even though it is reasonable): D3 enumerates three usage checks that precede the posture decision. The fold adds a fourth (the intake id mismatch) without a spec amendment. It extends D3's stated principle rather than contradicting it. The second spec_amendment covers only the TEST-1215 cell, and its claim matches the spec text (`[0-9]*` anchor). mutation-gate: GATE PASS 16 rows, uncomparable=0. `spec-amend list --strict`: exit 0.
- Ledgers: EVENTS.jsonl +4, decisions.jsonl +3, tests/test-runs.jsonl +1, all with 0 deletions (append-only).

## Evidence re-run by the reviewer (round 2)
- `bash tests/skills/test-aai-ride-select.sh` exit 0
- `bash tests/skills/test-aai-downstream-autopilot.sh` exit 0
- `bash tests/skills/test-aai-prompt-diet.sh` exit 0
- `bash tests/skills/test-aai-spec-amend.sh` exit 0
- `node .aai/scripts/mutation-gate.mjs --spec <spec>` GATE PASS 16 rows
- `node .aai/scripts/spec-amend.mjs list --strict` exit 0
- probe: `gate --ref cap-one --intake <id other-ref> --roadmap <absent>` exit 2 (before the fold: exit 0)

## Findings
BLOCKING: none.

NON-BLOCKING (recommended dispositions; the orchestrator records them):
- R2-NB-1 `.aai/scripts/ride-select.mjs:280`: the NB-3 behaviour is unpinned. Recommended: remediate in the tree by adding one arm to `test_1206_usage_checks_before_absent` (tests/skills/test-aai-ride-select.sh:302): absent roadmap plus an `--intake` whose id differs must exit 2, and it must be RED-proofed by moving line 280 below the existsSync branch. The alternative is to promote it to a follow-up (suggested: fu-ride-select-absent-intake-mismatch-pin). P3.
- R2-NB-2 `tests/skills/test-aai-downstream-autopilot.sh:40`: the guard is vacuous for an empty TEST_DIR. Recommended: (d) accepted residual. It is P3, an assurance-strength gap with no observed bite: the target path is a non-existent root-level directory, and the file leaves no false record. A one-line remediation is also possible: `[[ -n "$TEST_DIR" && -d "$TEST_DIR" ]] || exit 1` after line 30.

## Warning dispositions (H6)
Round-1 NB-1 and NB-2: remediated in tree. Round-1 NB-3: remediated in tree, with its test owed (R2-NB-1). Round-1 NB-4: partially remediated (R2-NB-2). If R2-NB-2 takes (d): accepted residual: the mk_project guard cannot detect an empty TEST_DIR, but a failed mktemp only targets a non-existent root-level path, never the repository.

## Next steps
Overall pass. This was round 2 of 2, so no further review round. The orchestrator records dispositions for R2-NB-1 and R2-NB-2 in code_review.notes before close. If R2-NB-1 is remediated in the tree, it is a test-only change that does not reopen review.
