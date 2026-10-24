# Code Review r5: cheap-transitions-slice (FULL mode)

Intended path: docs/ai/reviews/review-cheap-transitions-slice-20261024T160754Z.md

```yaml
review:
  scope: "ba552b89..9ef9b7e3 (delta since r4: ffc7b7b9..9ef9b7e3)"
  spec: docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-2701 green (recheck node 45/45)" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-2702 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "row now names recheck_disabled; recheck.mjs:75-79 deltaEnabled; TEST-2706 asserts recheck_disabled for AAI_RECHECK_MODE=full (recheck.test.mjs ~417-420); no forced_full left in .aai/, tests/, docs/specs, CHANGELOG (NB-12 closed)" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-2707/2708/2709 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-2710/2711 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-2712/2713 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2714 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "recheck-measure.mjs: CR 33082/11336 (0.343), V 45843/11335 (0.247); RECHECK_DELTA and SUBAGENT_CONTRACT unchanged in the delta, so D11 unchanged is true" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-2716 green" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-2717 green" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-2718/2719 green" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-2720/2721/2722 green; test-aai-prompt-diet.sh rc 0; SUBAGENT_PROTOCOL +209 B measured" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-2723 green" }
      - { ac: Spec-AC-14, call: compliant, citation: "TEST-2725/2737 green" }
      - { ac: Spec-AC-15, call: compliant, citation: "TEST-2724 green" }
      - { ac: Spec-AC-16, call: non-compliant, citation: "B-11: the row says an in-place rewrite of a stamp already in a committed blob (committed inside the range) SHALL give ledger_rewritten; a git commit --amend flip of that commit, or a reset dropping it, gives delta with no reasons (probes P2, P3). merge_in_range, the uncommitted residual and whitespace AAI_ROLE parts are compliant (TEST-2742/2743/2744 green, mutations killed)" }
      - { ac: Spec-AC-17, call: compliant, citation: "TEST-2731/2732/2738 green" }
      - { ac: Spec-AC-18, call: compliant, citation: "TEST-2733 green" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md, line: 296,
          issue: "B-11 (overclaim, same class as B-10): D4 says 'What the ledger rules DO close is the rewrite of a stamp that is already in a committed blob', and Spec-AC-16 (line 516) lists 'committed inside the range' as covered. A history rewrite that replaces or removes the commit holding the stamp (commit --amend, reset, rebase -i drop) is not seen: eventsAppendOnly (recheck.mjs:139-163) checks only the live file, the base and HEAD blobs, and each commit of the CURRENT base..HEAD against its first parent; the rewritten commit is no longer in that range, and merge_in_range does not fire on a linear rewrite. No fu names this shape: fu-recheck-uncommitted-stamp-rewrite is scoped to stamps never committed.",
          failure_scenario: "With AAI_RECHECK_MODE=delta: commit S holds the false stamps; commit C1 appends check_verdict{validation, head S, security_relevant:true}. Either `git commit -a --amend` after flipping true to false in place (P2), or `git reset --hard HEAD~1` (P3). Touch a test file. recheckMode gives mode delta, reasons [] (probe log cr23-work/probes.log; positive control P1 before the rewrite gives full with security_relevant:stamp:validation). The fixture's reports say false, so in a real ride the true round's report must also be edited or dropped, the same extra step the B-10 scenario needed (a gitignored Validation report survives a reset; a tracked review report dropped with C1 does not)." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/prompt-diet-ledger.sh, line: 261,
          issue: "INFO-grade text staleness: the entry still says RECHECK_DELTA.prompt.md '0 -> 3525 B'; the file is 3498 B since round 3. The total (4209) and the per-round 209 B are correct; only the delivery-size narrative is stale.",
          failure_scenario: "A later diet audit re-measures RECHECK_DELTA from the entry text and gets 27 B off; the numeric credit is unaffected. Recommended disposition: (d) accepted residual (P3, no false credit) or fold into the B-11 remediation commit." }
  cannot_verify:
    - { claim: "ledger_rewritten does not falsely refuse on a Windows checkout with core.autocrlf=true (carried from r4)",
        closes_with: "recheckMode on a native Windows clone with autocrlf=true" }
    - { claim: "mutation-gate and mutation replay for TEST-2741..2744 in the ride worktree (the evidence is gitignored). Locally, all four Test Plan seds applied to a copy and each was killed by its node case (rc 1)",
        closes_with: "mutation-run --replay / mutation-gate in /private/tmp/aai-cheap-transitions" }
    - { claim: "hosted CI (Node 24, Node 22 floor, Linux) and the Windows Pester leg",
        closes_with: "PR checks" }
    - { claim: "the skill_test record of 2026-10-24T15:35:35Z (109/113, 4 failed) appended in this commit; it does not name the failing suites, and it predates the round 4 commit",
        closes_with: "the validator's full sweep on 9ef9b7e3" }
    - { claim: "no harness exports AAI_ROLE into the orchestrator's own shell (carried from r4; with whitespace now counted as set, the exposure is slightly wider)",
        closes_with: "a live --confirm tick under each supported harness" }
  overall: fail
```

security_relevant: true

## Scope

- Review range: `ba552b89..9ef9b7e3`. The r5 focus is the delta `ffc7b7b9..9ef9b7e3` (commit 9ef9b7e3, remediation round 4).
- Spec: `docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md`, ceremony 3.
- The ride worktree was only read. Probes ran in the clone `scratchpad/cr23-work/repo`, detached at 9ef9b7e3. The probe file is `cr23-work/probe.test.mjs` and its log is `cr23-work/probes.log`.
- The marker stays true. It is sticky, and B-11 is a gap in a security guard.
- Dispatch note: the owner rules and the five check items name areas and a severity rule ("a residual named accurately and gated is not blocking"). That is a policy statement, not a pre-rating of findings, so it is not coaching. I reviewed the full range.

## Check items

**1. Do the claims match the code?** Mostly yes, with one overclaim (B-11).
- SUBAGENT_PROTOCOL:62, the CHANGELOG body, D1 row and the D4 "NOT closed" paragraph describe the committed-lines scope and `merge_in_range` correctly.
- The CHANGELOG heading and the downstream-impact line now say opt-in and default unchanged. NB-11 is closed.
- Spec-AC-03 and the TEST-2706 row name `recheck_disabled`. NB-12 is closed.
- Both fu texts are accurate within their stated scope.
- Overclaim (B-11): D4 line 296-300 and Spec-AC-16 still claim every rewrite of a committed stamp is closed. That holds only when the commit holding the stamp stays in history. An amend, reset or rebase that replaces or removes that commit leaves a linear, append-only chain and gives delta (P2, P3).
- The closing remedy is the same STATE binding, so under the owner rule this can be a gated residual. It has to be named, though: today the spec asserts the opposite. Remedy with no code needed: (a) narrow the D4 sentence and the Spec-AC-16 parenthetical to "while the commit holding it stays in base..HEAD"; (b) name history rewrite (amend, reset, rebase) as a residual, either by widening `fu-recheck-uncommitted-stamp-rewrite` or with a sibling fu; (c) optionally pin it like TEST-2742.

**2. Is `merge_in_range` correct and fail-closed?** Yes (recheck.mjs:413-421).
- `rev-list --min-parents=2 --max-count=1 base..HEAD` catches a two-parent merge (TEST-2743, P4) and a true three-parent octopus (P6, merge_in_range named).
- A merge reachable from the base is excluded by the range, so there is no false refusal (P5: delta).
- A failing rev-list sets gitFailed, which gives `git_error` and full. P8 used a fake git that fails only on `--min-parents=2`: result full, reasons `git_error`.
- It only runs when `diffBase === base`. Otherwise base_not_ancestor, first_round or git_error already forces full.
- The check is needed because `rev-list -- EVENTS_REL` with default history simplification never visits the merge.

**3. Is TEST-2742 honest?** Yes.
- Positive control: the unflipped true stamp is full with `security_relevant:stamp:validation`.
- After an uncommitted flip, it asserts delta with no `ledger_rewritten`. The default env gives exactly `['recheck_disabled']`.
- When the STATE binding lands, `after.mode` becomes full and the assertion fails. That forces the rewrite the comment promises.
- The mutation (`live.length > 0` returns false) was killed (rc 1).
- The title and comment carry KNOWN RESIDUAL, the fu id and the default-on condition.

**4. Ledger hygiene.**
- `spec-amend list --strict`: rc 0, read directly.
- `decisions.jsonl`, `EVENTS.jsonl` and `tests/test-runs.jsonl` at ba552b89 and at ffc7b7b9 are each a byte-exact prefix of 9ef9b7e3 (cmp).
- Both new amendments (15:46:57Z, 15:53:48Z) are class contract, tracked_by `fu-amend-spec-cheap-transitions-slice`, unsigned-tracked.
- Their text matches the diff:
  - D1, D4, D5 (line 328 is under D5) and Spec-AC-16 scoped.
  - The D1 row adds `merge_in_range`.
  - Whitespace AAI_ROLE appears in the Spec-AC-16 text and TEST-2744.
  - Spec-AC-03 and TEST-2706 are renamed.
  - Rows TEST-2742..2744 are added.
  - D11 is unchanged, and RECHECK_DELTA and SUBAGENT_CONTRACT have 0 B delta.
  - The TEST-2741 sed was re-anchored on the new `?? '') !== '') fail(` text. It applies and is killed.

**5. Is the diet accounting consistent?** Yes.
- SUBAGENT_PROTOCOL.md grew 28988 to 29197 = +209 B (wc -c on the two blobs). It is the only `.aai` doc changed in the delta.
- Ledger 4000 + 209 = 4209. TEST-012 pin 58478 + 4209 = 62687.
- The pr-preflight `want_growth` term moved +4000 to +4209.
- test-aai-prompt-diet.sh rc 0 and test-aai-pr-preflight.sh rc 0 (clone).
- One stale size in the entry's narrative: NB, line 261.

**Also checked:**
- append-event.mjs:184 `String(process.env.AAI_ROLE ?? '') !== ''`. A space, two spaces and a tab are all refused. Unset appends. An empty string `AAI_ROLE=` counts as unset, which matches the D1 sole-agent carve's "unset".
- test-aai-recheck.sh: 43/43 PASS lines, rc 0. node: 45/45.

## Warning dispositions (H6)
- B-11: BLOCKING. Remediate in tree with wording plus a named residual, as in check item 1. This needs a contract amendment of the frozen spec text.
- NB (diet entry narrative, P3): recommended disposition (d), `accepted residual: narrative delivery size 3525 B vs live 3498 B, numeric credit correct`, or fold it into the B-11 commit.

## Next steps
1. Remediation: narrow the D4 and Spec-AC-16 wording, name the history-rewrite residual (widen or add an fu), and optionally add a pinned residual test. Then record the amendment and run `spec-amend list --strict`.
2. Re-review (delta) on the wording-only change.
