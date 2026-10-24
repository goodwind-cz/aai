# Code Review r7: cheap-transitions-slice (FULL mode, text-only delta)

Intended path: docs/ai/reviews/review-cheap-transitions-slice-20261024T171650Z.md

```yaml
review:
  scope: "ba552b89..54e8d878 (delta since r6: 7047594e..54e8d878)"
  spec: docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-2701 green (recheck node 45/45 at 54e8d878)" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-2702 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-2706 green; row unchanged in delta" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-2707/2708/2709 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-2710/2711 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-2712/2713 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2714 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "No .aai/*.prompt.md or SUBAGENT_CONTRACT byte changed in delta (glob 391263 B at 7047594e and 54e8d878)" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-2716 green" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-2717 green" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-2718/2719 green" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-2720/2721/2722 green; test-aai-prompt-diet.sh rc 0: TEST-010 headroom 0/2048, TEST-012 62478 == re-sum; credit 4000 equals the measured deficit (see NB-18 on the narrative)" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-2723 green" }
      - { ac: Spec-AC-14, call: compliant, citation: "TEST-2725/2737 green" }
      - { ac: Spec-AC-15, call: compliant, citation: "TEST-2724 green" }
      - { ac: Spec-AC-16, call: compliant, citation: "TEST-2726..2730, 2734..2736, 2739..2744 green; parenthetical now matches eventsAppendOnly (.aai/scripts/lib/recheck.mjs:139-163) and the merge check (:415-418); B-12 probe falls in the named residual. Wording ambiguity: NB-16" }
      - { ac: Spec-AC-17, call: compliant, citation: "TEST-2731/2732/2738 green" }
      - { ac: Spec-AC-18, call: compliant, citation: "TEST-2733 green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md, line: 525,
          issue: "NB-16: the Spec-AC-16 SHALL says an in-place rewrite of a stamp 'already in a committed blob (uncommitted over a committed line, committed before the base or committed inside the range) SHALL give ledger_rewritten', and the same row's parenthetical (and D4 line 307) now names 'a rewrite committed before the base' as general residual. The intended reading (the LINE was committed before the base and is rewritten in the range, TEST-2739 'committed rewrite of a line that predates the base') holds; the literal reading (the REWRITE is committed before the base) is false: the B-12 probe gives delta.",
          failure_scenario: "A reader or a later validator walks the SHALL literally, builds the B-12 shape (X appends true, Y flips it, both before the base), sees delta, and files a non-compliance against a row that also declares the shape residual; or a closer of fu-recheck-verdict-not-bound-to-check thinks the pre-base shape is already covered. Text only: 'a stamp line committed before the base or inside the range and rewritten afterwards (uncommitted or in a commit of base..HEAD)'." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/recheck.test.mjs, line: 1473,
          issue: "NB-17: the TEST-2742 header comment still carries the B-12 text: 'ledger_rewritten and merge_in_range guarantee only lines in the base blob or in commits still reachable from HEAD' and names only 'git replace --graft'. The code comment at .aai/scripts/lib/recheck.mjs:134-138 says 'only lines already present in a committed blob are protected' (false for a pre-base committed rewrite) and names the dropped fu-recheck-uncommitted-stamp-rewrite. Neither is in the spec/protocol/CHANGELOG/decision set this round fixed.",
          failure_scenario: "The binding slice's author reads the residual test or eventsAppendOnly's comment (the two places the closer of fu-recheck-verdict-not-bound-to-check will open first), trusts the stated guarantee, and leaves the pre-base committed-rewrite shape out of the binding's tests. Recommended: suggested fu-recheck-comments-overclaim-scope (P3), fixed with the binding slice; the test comment may also be fixed in tree now." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/prompt-diet-ledger.sh, line: 261,
          issue: "NB-18: the 4000 B credit is honest (glob 386356 at ba552b89 -> 391263 at 54e8d878 = +4907; delivery 3425 B with deficit 2518 used the 907 B base headroom; then r1 +1361, r2 +60, r3 +61 in glob: ORCHESTRATION +44, ORCHESTRATION_PARALLEL +44, RECHECK_DELTA -27; total deficit 2518+1361+60+61 = 4000; TEST-010 prints headroom 0/2048). But the narrative says 'deficit 3939 B ... credited 4000 B to clear the reduction floor in round 3 (61 B headroom)' and the TEST-012 comment (test-aai-prompt-diet.sh:1013-1017) says 'measured deficit 3939 B, credited 4000 B to clear the reduction floor'. Round 3's 61 B is measured in-glob growth, not headroom; headroom is 0. Same class as NB-15 (a false record in the ledger), sign reversed (it now reads as 61 B padding that does not exist).",
          failure_scenario: "A later diet audit trusts the narrative, 'reclaims' 61 B of apparent padding (credit 3939), and TEST-010 goes red at headroom -61; or the round-3 in-glob opt-in wording is believed uncredited. Text only: 'deficit 4000 B (2518 delivery, 1361 r1, 60 r2, 61 r3: the opt-in wording in ORCHESTRATION and ORCHESTRATION_PARALLEL less the dropped switch clause in RECHECK_DELTA), headroom 0/2048'." }
  cannot_verify:
    - { claim: "that the verdict-to-STATE binding closes the whole stated residual (uncommitted, pre-base committed rewrite, amend, rebase, squash-ours, git replace, forged append) (carried)",
        closes_with: "the binding slice's spec, with TEST-2742 and the B-12 shape flipped to full" }
    - { claim: "ledger_rewritten does not falsely refuse on a Windows checkout with core.autocrlf=true (carried)",
        closes_with: "recheckMode on a native Windows clone with autocrlf=true" }
    - { claim: "mutation-gate and mutation replay records (evidence gitignored, ride worktree)",
        closes_with: "mutation-gate in /private/tmp/aai-cheap-transitions" }
    - { claim: "hosted CI (Node 24, Node 22 floor, Linux) and the Windows Pester leg",
        closes_with: "PR checks" }
    - { claim: "no harness exports AAI_ROLE into the orchestrator's own shell (carried)",
        closes_with: "a live --confirm tick under each supported harness" }
  overall: pass
```

security_relevant: true

## Scope

- Full range `ba552b89..54e8d878`; delta `7047594e..54e8d878` (one orchestrator commit answering r6 B-12 and NB-15).
- Spec `docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md`, ceremony 3. Mode FULL (`AAI_RECHECK_MODE=full`).
- Ride worktree read only. Probes ran in a clone at `scratchpad/cr25-work/repo`, detached at 54e8d878. The clone was left clean.
- Marker stays true (sticky).
- Dispatch note: the owner decisions and the four check items are a checklist. They do not pre-rate anything, and I reviewed the full range.

## Check items

1. **Claims vs code.** `eventsAppendOnly` (`recheck.mjs:139-163`) checks three things. The live file must begin with the base blob and with the HEAD blob. Every commit of `base..HEAD` that touches EVENTS must begin with its first parent's blob. The merge check (`:415-418`) is `rev-list --min-parents=2 base..HEAD`. The spec D1 row (197), D4 (298-311), D5 (338-340), the Spec-AC-16 parenthetical, `SUBAGENT_PROTOCOL.md:62` and `CHANGELOG.md:40-47` now say exactly this. The residual list adds "committed before the base" and "`git replace` in any form". B-12 is closed.
   - **B-12 probe re-run at 54e8d878.** Setup: X commits a true stamp, Y flips it in a plain commit, then round 2 stamps at Y, and a test file is touched. Result under the opt-in: `mode delta`, `reasons []`, X is an ancestor of HEAD (rc 0). With the default env: `full`, `['recheck_disabled']`. The shape is now named in the residual ("a rewrite committed before the base").
   - **Remaining overclaims, outside the five fixed places.**
     - The TEST-2742 header comment and the `recheck.mjs` comment still overclaim (NB-17).
     - The Spec-AC-16 SHALL list reads ambiguously against its own residual (NB-16).
     - The append-only round-5 records (decisions 2332/2333) keep the old wording. The new 17:10:37Z amendment explicitly replaces it ("instead of claiming every reachable commit"). That is acceptable for an append-only ledger.
2. **Diet accounting.** TEST-010's glob is `.aai/*.prompt.md` plus INTAKE_COMMON, STATE_FALLBACK and ROLE_COMMON. SUBAGENT_PROTOCOL is outside it.
   - Measured per commit, the glob grew by 4907 B: delivery 3425, r1 1361, r2 60, r3 61, rounds 4-6 0.
   - The delivery deficit of 2518 B already used the 907 B of headroom at the base. The real deficit is therefore 4000 B, and the suite prints headroom 0/2048. The credit is honest.
   - The TEST-012 pin is 62478, which equals the re-sum (PASS). The pr-preflight term is +4000 (suite rc 0). The three numbers agree.
   - The narrative wrongly calls round 3's 61 B "headroom" and says the deficit is 3939 B (NB-18).
3. **Amendment.** `spec-amend list --strict` returns rc 0, read directly. The 17:10:37Z record is class contract, unsigned-tracked by `fu-amend-spec-cheap-transitions-slice`, and its text matches the diff. `decisions.jsonl`, `EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl` at ba552b89 and at 7047594e are byte-exact prefixes of 54e8d878. `spec-lint --path` returns rc 0 with no findings.
4. **No `.aai/scripts` change.** `git diff --stat 7047594e..54e8d878 -- .aai/scripts` is empty. The only `.aai` change is `SUBAGENT_PROTOCOL.md:62`.

## Commands run (clone, `env -u AAI_ROLE`, `AAI_RECHECK_MODE=full`)

- `node --test tests/skills/lib/recheck.test.mjs`: rc 0, 45/45
- `bash tests/skills/test-aai-prompt-diet.sh`: rc 0 (TEST-010 net reduction 28672, headroom 0/2048; TEST-012 62478)
- `bash tests/skills/test-aai-pr-preflight.sh`: rc 0
- `node .aai/scripts/spec-amend.mjs list --strict`: rc 0
- `node .aai/scripts/spec-lint.mjs --path <spec>`: rc 0
- B-12 probe (a temporary copy of the test file, removed afterwards): delta / `[]` under the opt-in, full / `recheck_disabled` by default
- Per-commit glob byte totals for `ba552b89^..54e8d878` (`git cat-file -p | wc -c`)

## Warning dispositions (H6)

- **NB-16 (P3, ambiguous SHALL wording):** remediate in tree, text only (one phrase in the Spec-AC-16 row plus an amendment record). Alternatively, fold it into the suggested fu below. It is not (d), because a literal read is false.
- **NB-17 (P3, overclaiming comments):** suggested `fu-recheck-comments-overclaim-scope`, to be fixed with the verdict-to-STATE binding slice. The test comment may be fixed in tree now.
- **NB-18 (P3, a false narrative in the diet ledger; the number is correct):** remediate in tree, text only (the ledger entry narrative and the TEST-012 comment). It is not (d).

## Next steps

1. Optional text-only round for NB-16 and NB-18, plus the TEST-2742 comment. Otherwise the orchestrator records the dispositions above.
2. Proceed to PR. Hosted CI and the Windows leg remain cannot_verify.
