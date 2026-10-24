# Code Review r6: cheap-transitions-slice (FULL mode, text-only delta)

Intended path: docs/ai/reviews/review-cheap-transitions-slice-20261024T170008Z.md

```yaml
review:
  scope: "ba552b89..7047594e (delta since r5: 9ef9b7e3..7047594e)"
  spec: docs/specs/SPEC-0250-spec-cheap-transitions-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-2701 green (recheck node 45/45 at 7047594e)" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-2702 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-2706 green; row unchanged in delta" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-2707/2708/2709 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-2710/2711 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-2712/2713 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2714 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "RECHECK_DELTA.prompt.md and SUBAGENT_CONTRACT.md unchanged in delta (3498 B both ends), so D11 bytes unchanged" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-2716 green" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-2717 green" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-2718/2719 green" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-2720/2721/2722 green; test-aai-prompt-diet.sh rc 0, TEST-012 62911 == re-sum; see NB-15 on the credit" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-2723 green" }
      - { ac: Spec-AC-14, call: compliant, citation: "TEST-2725/2737 green" }
      - { ac: Spec-AC-15, call: compliant, citation: "TEST-2724 green" }
      - { ac: Spec-AC-16, call: compliant, citation: "Every SHALL in the row holds: committed-blob rewrites (uncommitted, committed before the base, committed inside the range) give ledger_rewritten (TEST-2739/2740), merge_in_range (TEST-2743), whitespace AAI_ROLE (TEST-2744); the r5 B-11 shapes (amend, rebase drop) are now outside the SHALL and named as the general residual, pinned by TEST-2742 (uncommitted + amend). The row's parenthetical guarantee overclaims (B-12, a code_quality finding, not a broken SHALL)" }
      - { ac: Spec-AC-17, call: compliant, citation: "TEST-2731/2732/2738 green" }
      - { ac: Spec-AC-18, call: compliant, citation: "TEST-2733 green" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: docs/specs/SPEC-0250-spec-cheap-transitions-slice.md, line: 299,
          issue: "B-12 (overclaim, same class as B-10/B-11): the new guarantee wording says ledger_rewritten guarantees 'lines in the base blob or in commits still reachable from HEAD' and D4 says the ledger rules 'DO close the rewrite of a line that is in the base blob or in a commit still reachable from HEAD'. eventsAppendOnly (.aai/scripts/lib/recheck.mjs:139-163) compares only the live file, the base and HEAD blobs, and each commit of base..HEAD against its first parent. A stamp line committed in X and rewritten by an ORDINARY commit Y that precedes the current base is in a commit still reachable from HEAD, yet is not caught. That shape is also not in the residual list, which names only rewrites 'before it is fixed in history' and history rewrites (amend, rebase, squash, replace) plus forgery. Same text at spec line 197 (D1 row), 299 (D4), 525 (Spec-AC-16 parenthetical), .aai/SUBAGENT_PROTOCOL.md:62, CHANGELOG.md:46-47, decisions.jsonl remediation_decision 16:43:09Z.",
          failure_scenario: "AAI_RECHECK_MODE=delta, probe in cr24-work clone at 7047594e (fixture = mkRepo trackEvents): base0; commit X appends check_verdict{validation, head base0, security_relevant:true}; commit Y flips it to false in place (plain commit, no rewrite); round 2 stamps both roles at head Y (false) and commits; touch a test file. recheckMode gives mode delta, reasons [] while X is an ancestor of HEAD. Real-ride precondition: round 2 ran full (the default, or delta refused) and its checker did not carry the true forward (gitignored Validation report flipped live), the same extra step B-10/B-11 needed. Remedy, text only, no code: scope the guarantee to 'lines in the base blob, and lines appended by a commit of base..HEAD still reachable from HEAD', and add 'a rewrite committed before the base' (any commit, not only a history rewrite) to the general residual in the same five places; amend record + spec-amend list --strict." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/prompt-diet-ledger.sh, line: 261,
          issue: "NB-15: the 4433 B entry says 'MEASURED by TEST-010 ... at zero headroom standing', but TEST-010 does not measure .aai/SUBAGENT_PROTOCOL.md (outside the live .aai/*.prompt.md glob; the suite's own note at test-aai-prompt-diet.sh:820-821 says SUBAGENT_PROTOCOL rule additions carry 'no ledger cost'). The round 4 (+209) and round 5 (+224) credits are SUBAGENT_PROTOCOL bytes, so TEST-010 headroom went 0/2048 at ffc7b7b9 -> 209 at 9ef9b7e3 -> 433 at 7047594e (measured in the clone). The arithmetic 4209+224=4433, 62687+224=62911 and the pr-preflight +4433 term are internally consistent; the credit itself is padded by 433 B and the 'zero headroom' text is false. (I called round 4's +209 consistent in r5; that was wrong.)",
          failure_scenario: "A later scope adds up to 433 B of uncredited .aai/*.prompt.md growth with no ledger line and TEST-010 stays green, because the padded credit absorbs it; the control the suite itself names as the one that 'catches an uncredited byte on disk' is blinded by 433 B. Recommended disposition: (a) remediate in tree, credit 4000 (pin 62478, pr-preflight +4000, narrative drops the round 4/5 SUBAGENT_PROTOCOL bytes); not (d), because the entry is a false record." }
  cannot_verify:
    - { claim: "that the verdict-to-STATE binding (a head or tree field written by set-validation, per fu-recheck-verdict-not-bound-to-check) actually closes the merged scope (uncommitted, amend, rebase, replace, forged stamps); the registry item's own finding text still names only the STATE-write ambiguity",
        closes_with: "the binding slice's spec, with TEST-2742 flipped to full for every listed shape" }
    - { claim: "ledger_rewritten does not falsely refuse on a Windows checkout with core.autocrlf=true (carried from r4/r5)",
        closes_with: "recheckMode on a native Windows clone with autocrlf=true" }
    - { claim: "mutation-gate and mutation replay records in the ride worktree (evidence gitignored). Locally the TEST-2742 Test Plan sed applied to a copy was killed (rc 1)",
        closes_with: "mutation-run --replay / mutation-gate in /private/tmp/aai-cheap-transitions" }
    - { claim: "hosted CI (Node 24, Node 22 floor, Linux) and the Windows Pester leg",
        closes_with: "PR checks" }
    - { claim: "no harness exports AAI_ROLE into the orchestrator's own shell (carried)",
        closes_with: "a live --confirm tick under each supported harness" }
  overall: fail
```

security_relevant: true

## Scope

- Range `ba552b89..7047594e`; delta under review `9ef9b7e3..7047594e` (commit 7047594e, remediation round 5, text plus one test extension).
- Spec `docs/specs/SPEC-0250-spec-cheap-transitions-slice.md`, ceremony 3. Mode FULL (`AAI_RECHECK_MODE=full`).
- Ride worktree read only. Probes in clone `scratchpad/cr24-work/repo`, detached at 7047594e; tree left clean (`git status --porcelain` empty), scratch worktrees removed by path.
- Marker stays true (sticky; B-12 concerns a security guard).
- Dispatch note: the owner decisions and the six check items are a policy statement and a checklist, not a pre-rating; the full range was reviewed.

## Check items

1. **No `.aai/scripts` change in the delta.** Confirmed: `git diff --stat 9ef9b7e3..7047594e -- .aai` shows only `.aai/SUBAGENT_PROTOCOL.md` (1 line).
2. **Claims vs code.** The owner's general sentence ("with delta opted in, the check_* stamps are not tamper-proof; only the binding closes it") is now stated in spec D1/D4/D5, Spec-AC-16, TEST-2742 row, SUBAGENT_PROTOCOL:62, CHANGELOG and the decision record. B-11's amend and rebase shapes are named. `merge_in_range` wording ("only merges still visible in base..HEAD") is accurate. One overclaim remains in the positive half: B-12. "Lines in commits still reachable from HEAD" includes commits before the base, which the code never walks. Probe result: delta, reasons [].
3. **Follow-up consolidation.** Legitimate. The dropped record (16:43:09Z) names the target. Remediation decisions 14:56:19Z and 16:43:09Z put the default-on obligation on `fu-recheck-verdict-not-bound-to-check`, and spec D1/D4 repeat it. The obligation is also pinned structurally: TEST-2742 asserts `recheck_disabled` under the default env for both shapes, so making delta default-on fails a test whose comment names the residual. No owner obligation is lost. INFO: the open item's own registry text (2317) still names only the STATE-write ambiguity, because follow-ups.mjs has no edit. The merged scope lives in decisions 2323/2332 and spec D4. The closer of that item should read them (see cannot_verify 1). INFO: the comment at `.aai/scripts/lib/recheck.mjs:134-138` still names the dropped id. That is acceptable because the delta must not touch `.aai/scripts`, and the dropped record points to the merge target.
4. **TEST-2742 amend shape.** Honest. The true stamp is committed after the base, so the positive control is full. After a flip folded in with `commit -qa --amend`, the result is delta with no `ledger_rewritten`, and the default env gives exactly `['recheck_disabled']`. The Test Plan mutation (`live.length > 0`) was killed (rc 1). INFO: the test title still says only "uncommitted", and the amend positive control asserts mode, not reason.
5. **Diet accounting.** RECHECK_DELTA is 0 -> 3498 B (absent at ba552b89), so the narrative is now correct (r5 NB closed). SUBAGENT_PROTOCOL grew 29197 -> 29421 = +224 B. Ledger 4209+224=4433, TEST-012 pin 62911 == re-sum (PASS), and the pr-preflight term is +4433 (suite rc 0). These numbers agree with each other but rest on bytes TEST-010 does not measure, which gives headroom 433 rather than 0: NB-15.
6. **Ledger hygiene.** `spec-amend list --strict`: rc 0, read directly. The new 16:43:20Z record is class contract, tracked_by `fu-amend-spec-cheap-transitions-slice`, unsigned-tracked, and its text matches the diff. `decisions.jsonl`, `EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl` at ba552b89 and at 9ef9b7e3 are each byte-exact prefixes of 7047594e (cmp). The delta appends 3 decision lines and 1 docs_audit event. `spec-lint --path` on the spec: rc 0, 0 findings.

## Commands run (clone, `env -u AAI_ROLE`, `AAI_RECHECK_MODE=full`)

- `node --test tests/skills/lib/recheck.test.mjs`: rc 0, 45/45
- `bash tests/skills/test-aai-prompt-diet.sh`: rc 0 (TEST-010 headroom 433/2048; at 9ef9b7e3 209, at ffc7b7b9 0)
- `bash tests/skills/test-aai-pr-preflight.sh`: rc 0
- `node .aai/scripts/spec-amend.mjs list --strict`: rc 0
- B-12 probe (temporary test appended to a copy of recheck.test.mjs, then removed): mode delta, reasons [], X ancestor of HEAD

## Warning dispositions (H6)

- B-12: BLOCKING. Remediate in tree with text only, in the five places listed, and record an amendment. No code change is needed, and it fits the owner's "general risk as text" decision.
- NB-15 (P3 size, but a false record): recommended disposition (a), remediate in tree: credit 4000, pin 62478, pr-preflight +4000. (d) is not available.

## Next steps

1. Remediation round 6 (text only): fix B-12 wording plus NB-15 accounting, add the amendment record, and run `spec-amend list --strict`.
2. Re-review (delta) on that change.
