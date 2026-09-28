# Code Review — strategy-unscoped-from-current-focus (SPEC-0192)

```yaml
review:
  scope: >-
    inline (worktree.user_decision=inline) — `git diff e21dd1b -- <STATE
    code_review.scope paths>` = committed bebb2c4+659ee91 (ISSUE-0086, SPEC-0192
    freeze) plus working-tree diff vs HEAD 659ee91 plus untracked
    docs/decisions/DECISION-strategy-unscoped-from-current-focus-worktree.md.
    Paths: .aai/scripts/state.mjs .aai/scripts/lane-gate.mjs
    .aai/scripts/orchestration-dispatch.mjs .aai/templates/STATE_TEMPLATE.yaml
    .aai/SKILL_TDD.prompt.md .aai/IMPLEMENTATION.prompt.md .aai/VALIDATION.prompt.md
    .aai/INTAKE_COMMON.md .aai/SKILL_INTAKE.prompt.md .aai/PLANNING.prompt.md
    tests/skills/test-aai-state.sh tests/skills/test-aai-lightweight-lane.sh
    tests/skills/test-aai-orchestration-dispatch.sh tests/skills/test-aai-implementation-mode.sh
    tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh
    tests/skills/test-aai-r-guard.sh docs/knowledge/FACTS.md
    docs/decisions/DECISION-strategy-unscoped-from-current-focus-worktree.md
    docs/issues/ISSUE-0086-strategy-unscoped-from-current-focus.md
    docs/specs/SPEC-0192-spec-strategy-unscoped-from-current-focus.md docs/ai/decisions.jsonl
  spec: docs/specs/SPEC-0192-spec-strategy-unscoped-from-current-focus.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/state.mjs:1047-1060 (bindRef = explicitRef ?? focusRef; setField ref_id); TEST-001 test_079 PASS; mutation-TEST-001.txt RED" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/state.mjs:1049-1051 fail(... disagrees ...) at 1050 pre-editBlock; TEST-002 test_080 PASS (exit 2, both refs, cmp byte-identical); mutation-TEST-002.txt RED" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/state.mjs:1052-1054 fail('--ref is required when current_focus.ref_id is unset'); TEST-003 test_081 PASS; mutation-TEST-003.txt RED (see NB-1 for empty --ref edge)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/lane-gate.mjs:186-215 readStrategy ok:false on non-null mismatch; .aai/scripts/orchestration-dispatch.mjs:964-968 strategy_selected=undecided; TEST-004 test_192_stale_untested_leftover_heavy PASS, TEST-005 test_192_stale_strategy_is_undecided PASS (rule 7 Planning); mutation-TEST-004/005 RED" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "lane-gate.mjs:215 legacy FAST_STRATEGIES path; dispatch legacy = full existing dispatch suite green (fixtures carry no ref_id); state.mjs:1044-1046 untested-rationale refusal kept first; TEST-007 test_082 PASS; test_061 unchanged PASS; mutation-TEST-007.txt RED" }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/SKILL_TDD.prompt.md:45, .aai/IMPLEMENTATION.prompt.md:62, .aai/VALIDATION.prompt.md:154-157 STALE BINDING bullets name both fields + undecided; TEST-006 test_008 PASS; mutation-TEST-006.txt RED; prompt-diet TEST-010/TEST-012 PASS (see NB-2 on pin strength)" }
      - { ac: Spec-AC-07, call: compliant,
          citation: ".aai/INTAKE_COMMON.md:99-109 --ref + LIVE OTHER FOCUS fallback; .aai/SKILL_INTAKE.prompt.md:73; .aai/PLANNING.prompt.md:43-44,160-165; TEST-008 test_083 PASS; TEST-009 test_009 PASS; mutation-TEST-008/009 RED" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/state.mjs, line: 1041,
          issue: "set-strategy --ref is not shape-validated (set-focus --ref is); empty and whitespace-bearing values are accepted and written as a bind",
          failure_scenario: "focus unset (post clear-focus), intake runs `set-strategy --selected untested --rationale r --ref \"$REF\"` with REF empty -> exit 0, writes `ref_id: ''` (probed). Planning set-focus NEW then sees a disagreeing stamp -> dispatch undecided -> Planning does not skip and there is no intake Notes line (the write 'succeeded'), so the user's recorded intake choice is silently dropped. `--ref 'a b'` writes unquoted `ref_id: a b`, which lane-gate reads as `a` and dispatch reads as `a b` (reader disagreement). Fail-closed (never a rigor downgrade), but it contradicts S4's claim that a skipped --ref surfaces as a CLI refusal." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-implementation-mode.sh, line: 173,
          issue: "TEST-006 `grep -qiF undecided` is pre-satisfied in SKILL_TDD and IMPLEMENTATION by the existing 'If strategy is `undecided`' line, so the 'instruct treating a disagreeing pair as undecided' half of Spec-AC-06 is pinned only in VALIDATION",
          failure_scenario: "an edit that keeps both field names in SKILL_TDD/IMPLEMENTATION but drops or inverts 'treat strategy as undecided' in the STALE BINDING bullet stays green (HEAD:.aai/SKILL_TDD.prompt.md and HEAD:.aai/IMPLEMENTATION.prompt.md each already match 'undecided' once)." }
  cannot_verify:
    - { claim: "Agents actually obey the three prompt STALE BINDING bullets and the PLANNING skip-only-when-matching rule (S3/S4, R1)",
        closes_with: "a live agent run on a retargeted-focus fixture; grep tests pin text presence only" }
    - { claim: "The originally observed Windows downstream pairing (bezdinek/scada) is fixed in that working tree",
        closes_with: "re-run ISSUE-0086 Steps to Reproduce against the downstream STATE after aai-sync; fixture-level only here" }
    - { claim: "Owner acceptance of the three post-freeze amendments (incl. the new Spec-AC-07)",
        closes_with: "owner sign-off closing fu-amend-strategy-unscoped-from-c-4f2cdf (currently unsigned-tracked, open)" }
    - { claim: "Validation's full 98-suite sweep (89 PASS, 9 locale-collation failures attributed as pre-existing)",
        closes_with: "reviewer re-ran only the 6 in-scope suites; a same-locale sweep on origin/main e21dd1b showing the same 9 failures" }
    - { claim: "No vendoring project calls set-strategy with an unset focus and no --ref (Article 5 break, e.g. the R-guard fixture needed --ref)",
        closes_with: "cross-repo grep of downstream harnesses/scripts after sync" }
  overall: pass
```

## Scope and spec

- Mode: inline (`worktree.user_decision: inline`, HITL-7 recorded in `docs/ai/decisions.jsonl` and the decision artifact). Scope = STATE `worktree.inline_review_scope`, identical to `code_review.scope` (22 paths).
- Base: local `main` (40dde3e) is stale; the true fork point is `origin/main` = `e21dd1b`. `main..HEAD` carries only bebb2c4 (ISSUE-0086) and 659ee91 (SPEC-0192 freeze). The review therefore covers `git diff e21dd1b -- <paths>`: the committed issue and spec plus the working-tree diff and the one untracked in-scope file.
- Dirty but out of scope: `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl`, both append-only workflow ledgers. They are not code changes, so the scope stays unambiguous and review proceeds.
- `docs/issues/ISSUE-0086-...md` has no working-tree diff; it was reviewed as committed in bebb2c4.
- Anti-gaming: the dispatch did not characterize findings, pre-rate severity, or exclude areas. No coaching was recorded.

## Evidence run by the reviewer

All runs used one scratch copy at `/tmp/aai-review-192/repo` (HAZ-SCRATCH), through the canonical wrapper `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>.sh`. The shipping ledgers stayed byte-identical (`sha256sum -c`: OK).

| Command | Exit |
|---|---|
| test-aai-state.sh (incl. test_079..083, test_061) | 0 |
| test-aai-lightweight-lane.sh (test_192 TEST-004) | 0 |
| test-aai-orchestration-dispatch.sh (test_192 TEST-005) | 0 |
| test-aai-implementation-mode.sh (TEST-006 test_008, TEST-009 test_009) | 0 |
| test-aai-prompt-diet.sh (TEST-010, TEST-012 = 42478) | 0 |
| test-aai-r-guard.sh (TEST-RG-PIN-03) | 0 |
| `spec-lint.mjs --path SPEC-0192 --strategy tdd` | 0 (LINT PASS) |
| `mutation-gate.mjs --spec SPEC-0192` | 0 (9 rows, degraded=0) |
| `spec-amend.mjs list --status all` | 0 (3 amendments unsigned-tracked) |
| probe: focus unset, `set-strategy --ref ''` | 0, wrote `ref_id: ''` (NB-1) |
| probe: focus unset, `set-strategy --ref 'a b'` | 0, wrote `ref_id: a b` (NB-1) |
| probe: `set-focus --ref 'a b'` | 2 (shape refused, contrast for NB-1) |

## AC table walk

All seven Spec-AC rows are compliant. Citations are in the YAML block. Every TEST-001..009 named in the Test Plan exists, passes in the reviewer's run, and has a RED mutation record whose selector matches the new test function.

Deviations from the frozen spec, all disclosed and none non-compliant:

1. Three post-freeze amendments (20:07Z, 21:03Z, 22:19Z) add Spec-AC-07, the D2 intake paragraph, plan step 8, S4, and TEST-008/009, and widen Isolation to r-guard, FACTS, the decision artifact and the three intake/planning prompts. Each is a `spec_amendment` record with `owner_signoff: false`, tracked by `fu-amend-strategy-unscoped-from-c-4f2cdf` (open).
2. The Verification line "`test_061` / TEST-007" is stale. TEST-007 lives in the new `test_082_untested_rationale_and_legacy_ref` (the mutation selector agrees); `test_061` prints impl-mode TEST-002. The Test Plan description "test_061 untested-without-rationale ..." carries the same drift. Doc-only.
3. The plan numbering reads 6, 8, 7. Cosmetic.
4. No `red-TEST-008-*.log` exists. The spec obliges stored RED logs only for TEST-001..007; TEST-008 RED is carried by `mutation-TEST-008.txt` (rc 1, RED).

## Findings

### NB-1 (NON-BLOCKING, P2): `set-strategy --ref` accepts empty and malformed refs
`.aai/scripts/state.mjs:1041` reads `explicitRef` through `strFlag` with no shape check, while `set-focus` enforces `^[A-Z]+-\d+$` or the slug shape.

Failure scenario: after `clear-focus`, an intake agent renders `--ref "$REF"` with REF empty. The command exits 0 and writes `ref_id: ''`. After Planning's `set-focus NEW`, both readers treat the stamp as stale, which is fail-closed. But Planning's skip rule does not match, and no intake Notes line was written because the CLI succeeded, so the user's intake choice is silently lost. That is the CHANGE-0100 friction this scope protects. Separately, `--ref 'a b'` is written unquoted, and lane-gate's `(\S+)` and dispatch's `readScalar` then read different values.

Recommended disposition: (a) remediate in tree. Validate `--ref` with the same ref-shape predicate `set-focus` uses (exit 2, no write), and add one RED-proofed arm to test-aai-state.sh. The fallback is (b) a typed follow-up; the suggested id is `fu-set-strategy-ref-shape`. Because this is P2, disposition (d) is not available.

### NB-2 (NON-BLOCKING, P3): TEST-006 only half-pins the "undecided" instruction
`tests/skills/test-aai-implementation-mode.sh:173`: the `undecided` grep is already satisfied by pre-existing text in SKILL_TDD and IMPLEMENTATION. The field-path greps do bite (mutation-TEST-006 RED), and by inspection the bullets do say "treat strategy as `undecided`".

Recommended disposition: (a) tighten the grep to `grep -qF 'treat strategy as \`undecided\`'` per file. Alternatively, this is eligible for (d): `accepted residual: TEST-006 undecided grep pre-satisfied in SKILL_TDD/IMPLEMENTATION; field-path greps bite, bullet text verified by review; P3 assurance-strength, no observed bite, no false record.`

### INFO (no disposition duty)
- `metrics-flush.mjs:1290` records `implementation_strategy.selected` into the flushed ref's METRICS row without checking `ref_id`, and `applyFullReset` (`metrics-flush.mjs:942-947`) leaves `ref_id` in place after resetting `selected` to `undecided`. Neither is in SPEC-0192's D4 reader list. On the sanctioned path, dispatch forces a re-plan on mismatch, so a mismatched stamp should not reach flush. The optional follow-up has the suggested id `fu-metrics-flush-strategy-ref-bind`.
- `.aai/STATE_FALLBACK.md:28` still lists the strategy fields as selected/source/rationale. A hand-edit therefore yields legacy (no `ref_id`), which is honored per D4/R2.
- `lane-gate.mjs` now scans the whole file instead of breaking at block end. The behavior is equivalent, and a column-0 comment inside the block still ends it, as before.

## Warning dispositions (H6)

| Warning | Rank | Recommended disposition |
|---|---|---|
| NB-1 | P2 | (a) remediate in tree; fallback (b) `suggested: fu-set-strategy-ref-shape` |
| NB-2 | P3 | (a) tighten grep, or (d) the accepted-residual line quoted in NB-2 |

The orchestrator records the chosen artifact. The reviewer filed nothing.

## Verdict and next steps

- spec_compliance: pass. code_quality: pass (no BLOCKING findings). Overall: pass. L3 has no waiver.
- The pass is conditional per H6: before closeout, NB-1 needs (a), (b) or (c), and NB-2 needs any of (a) through (d).
- The owner sign-off on the SPEC-0192 amendments (`fu-amend-strategy-unscoped-from-c-4f2cdf`) remains owed at the merge checkpoint.
- Stage this report with the scope commit (SPEC-0013 H4).
