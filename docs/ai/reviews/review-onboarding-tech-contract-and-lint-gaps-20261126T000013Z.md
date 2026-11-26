# Code Review — onboarding-tech-contract-and-lint-gaps (round 1, independent reviewer)

```yaml
review:
  scope: "git diff 5f02b0e5..30928e24 (fix/onboarding-issues; STATE code_review.scope path list, 18 paths + append-only ledgers)"
  spec: docs/specs/SPEC-0317-spec-onboarding-tech-contract-and-lint-gaps.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/aai-doctor.mjs:209-222,237; TEST-4123 PASS (re-run this review)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/aai-doctor.mjs:237 (hint pushed only when isTechSeed); TEST-4124 PASS (re-run)" }
      - { ac: Spec-AC-03, call: compliant, citation: "aai-doctor.mjs:212-222 == aai-bootstrap.mjs:589-600 (identical isTechSeed); TEST-4126 PASS (re-run)" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:625,800-801; TEST-4125 PASS (node --test re-run)" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:371,377,492; TEST-4127 PASS (re-run)" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:365-368,376; TEST-4128 PASS (re-run)" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:374-376; TEST-4128 PASS (re-run)" }
      - { ac: Spec-AC-08, call: compliant, citation: "tests/skills/lib/aai-bootstrap-fixtures.mjs DR12; aai-bootstrap.test.mjs applyDrift/runCorpus; TEST-4130, TEST-3949 PASS (validation r3 full sweep)" }
      - { ac: Spec-AC-09, call: compliant, citation: ".aai/TECH_EXTRACT.prompt.md:22,35; TEST-4131 PASS (validation r3)" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-4132 PASS (re-run)" }
      - { ac: Spec-AC-11, call: compliant, citation: ".aai/SKILL_BOOTSTRAP.prompt.md:37,109; TEST-4129, TEST-4133 PASS (validation r3)" }
      - { ac: Spec-AC-12, call: compliant, citation: "corpus 376746 - 376171 = 575 = ledger credit (measured, bash + /usr/bin/wc); ORCHESTRATION unchanged; no added .aai/ file; TEST-4134 PASS on this tree (but see BLOCKING F1)" }
      - { ac: Spec-AC-13, call: compliant, citation: "CHANGELOG.md:33; SPEC-0306 amendment section + DR-12 row; spec-amend list --strict rc 0 (re-run); TEST-4135 PASS (validation r3)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-prompt-diet.sh, line: 2860,
          issue: "TEST-4134 pins the WHOLE live prompt corpus (cat .aai/*.prompt.md) against the stored 5f02b0e5 size and requires growth == this entry's credit, without subtracting the credits of ledger entries appended after it",
          failure_scenario: "the next ride that grows any .aai/*.prompt.md and credits its own JUSTIFIED_ADDITIONS entry 1:1 (the canonical D-GOV path) turns TEST-4134 red: repro shows TEST-012 rc 0, TEST-2824 rc 0, TEST-4134 rc 1 ('corpus grew 585 B ... entry credits 575 B'). Same defect class as validation F3 (TEST-4019 live-tree pin) that this ride itself had to fix" }
      - { rank: NON-BLOCKING, file: .aai/TECH_EXTRACT.prompt.md, line: 35,
          issue: "step 8 set-focus overwrites any active current_focus unconditionally, and the focus it leaves behind has no work item, so the next orchestration tick dispatches Planning for the phantom ref technology-extraction",
          failure_scenario: "a project mid-ride (focus intake_change CHANGE-0042) whose docs/TECHNOLOGY.md is still the seed: the operator follows the new doctor/bootstrap pointer and runs TECH_EXTRACT as sole agent -> focus becomes technology_extraction/technology-extraction -> orchestration-dispatch returns 'dispatch 5 Planning technology-extraction' (repro)" }
      - { rank: NON-BLOCKING, file: .aai/TECH_EXTRACT.prompt.md, line: 22,
          issue: "under AAI_ROLE=subagent step 1's check-state.mjs --repair is NOT refused (check-state has no single-writer guard) and writes STATE, while step 8's set-focus IS refused; the prompt's 'skip the STATE steps and say so' replaces the SUBAGENT_CONTRACT D1 path (return the command under state_update_commands)",
          failure_scenario: "a dispatched TECH_EXTRACT subagent in a project without STATE creates docs/ai/STATE.yaml itself (probe: CREATED ..., rc 0) against the single-writer rule; with STATE present it drops the focus record instead of returning set-focus to the orchestrator" }
  cannot_verify:
    - { claim: "the Windows CI leg (and any CRLF checkout of .aai/*.prompt.md, which .gitattributes does not pin to LF) keeps TEST-4134's byte measurement equal to the LF credit", closes_with: "hosted skill-suite run on the PR head incl. Windows legs (or confirmation that aai-prompt-diet runs only on Ubuntu)" }
    - { claim: "npx eslint@8 . actually lints a legacy-eslintrc project (plugins resolvable, exit semantics) — tests prove only the argv via a stub npx", closes_with: "a manual run of the generated aai-lint skill in a real legacy eslintrc project (network)" }
    - { claim: "the PowerShell launcher writes the same aai-lint SKILL.md and Technology contract block as the module on native Windows", closes_with: "hosted Windows leg / Pester run on the PR head (spec Residual risks)" }
    - { claim: "TEST-4126's bare `timeout 120` exists on every host that runs test-aai-doctor.sh (first and only bare timeout use in this suite; present on this macOS, Ubuntu and Git for Windows)", closes_with: "hosted run on the PR head; older macOS without /usr/bin/timeout untested" }
  overall: fail
```

security_relevant: false

## Scope and inputs

- Scope: `git diff 5f02b0e5..HEAD` on `fix/onboarding-issues` at `30928e24` in
  `/Users/ales/Projects/aai-worktrees/onboarding-issues-588-590` (worktree decision;
  STATE `code_review.scope` lists the 18 paths reviewed). The only uncommitted change
  in the tree is an `docs/ai/EVENTS.jsonl` append, outside the reviewed range.
- Spec: `docs/specs/SPEC-0317-spec-onboarding-tech-contract-and-lint-gaps.md`
  (frozen, two post-freeze amendments). Intake read as data only.
- Earlier evidence read: validation reports r1–r3 (latest
  `VALIDATION-20261125T225143Z-...`).
- Anti-gaming note: the dispatch listed areas to "pay attention to" (CRLF/BOM,
  eslint detection edges, twin parity, TECH_EXTRACT under `AAI_ROLE=subagent`,
  test hygiene, amendments). It did not pre-rate severity or exclude areas; recorded
  here as a possible characterisation, and the full scope was reviewed regardless.

## Verdict 1 — spec_compliance: PASS

The AC walk is in the YAML block. Every row is compliant, and the claimed tests
exist and pass. This review re-ran: TEST-4123, 4124, 4126, 4132 (doctor suite,
single-test mode, all PASS); TEST-4125/4127/4128 (`node --test`, 12/12 PASS);
`spec-amend.mjs list --strict` rc 0; `spec-lint` on the ride spec LINT PASS;
corpus `376746 − 376171 = 575` = ledger credit; `.aai/ORCHESTRATION.prompt.md`
unchanged; `git diff --name-status 5f02b0e5 HEAD -- .aai/` shows only `M`.
EVENTS.jsonl and decisions.jsonl at 5f02b0e5 are byte prefixes of HEAD.

Deviations from the frozen spec (all disclosed or reasonable):
1. D4 step 1 narrowed by the post-freeze amendment (a local bin counts only beside
   an `.eslintrc*`). Recorded as an unsigned contract amendment tracked by
   `fu-amend-onboarding-tech-contract-d587c5`. Owner sign-off is still owed.
2. Test Plan File path cells of TEST-4125/4127/4128/4130 moved to the bash suite
   (amendment, same tracker).
3. The spec's "Review scope (explicit paths)" did not list
   `tests/skills/test-aai-pr-preflight.sh`, `test-aai-suite-reuse.sh`,
   `test-aai-sync-node.sh` or `docs/specs/SPEC-0310-spec-sync-on-node.md`. These
   were touched because other prompt-size pins broke (pr-preflight and suite-reuse
   needed the +575 credit; TEST-4019 was re-based onto history). STATE's review scope
   includes them. SPEC-0310 has a measurement-class amendment for this (2 records,
   unsigned. `--strict` accepts them).
4. The SPEC-0306 amendment record carries `owner_signoff: true` on the authority of
   the owner's intake triage. That is what D-AMEND specifies, and the section says
   the owner may reverse it. A later correction record
   (`fu-amend-bootstrap-on-node-20261125t2122`) is unsigned and tracked.

## Verdict 2 — code_quality: FAIL (1 BLOCKING)

### F1 BLOCKING — TEST-4134 breaks on the next prompt-editing ride
- `tests/skills/test-aai-prompt-diet.sh:2860-2872` (`test_4134_onboarding_ledger_entry`):
  `now=$(cat .aai/*.prompt.md | wc -c)`, `growth = now − 376171`, then
  `lead != growth` fails.
- Failure scenario: any later scope that adds N bytes to any prompt and credits its
  own ledger entry 1:1 (D-GOV, which TEST-010/012 already enforce) makes
  `growth = 575 + N`. TEST-4134 then fails, and so does every later ride until
  someone edits this test. That is the same class as validation F3 (TEST-4019
  byte-pinned the live corpus), which this ride had to fix.
- The sibling `test_2824_diet_entry_for_binding` already solves this. It subtracts
  the credits of entries appended after its own entry (the `later` sum).
- backed-by: repro `docs/ai/reviews/repro-onboarding-test-4134-next-ride.sh`
  (exit 0 = reproduced). Output: `baseline TEST-4134 rc=0; after a later
  1:1-credited ride: TEST-012 rc=0 TEST-2824 rc=0 TEST-4134 rc=1` /
  `FAIL TEST-4134: the corpus grew 585 B over 376171 but the entry credits '575' B`.
- Fix (spec-compatible, because at merge the credit still equals the measured
  growth): subtract the credits of `JUSTIFIED_ADDITIONS` entries after the
  onboarding entry before comparing, as TEST-2824 does. The fix changes no prompt
  bytes, so there is no ledger impact. The TEST-4134 Mutation cell
  (`BEGIN NOW.` + unaccounted growth with no entry) still bites.

### NB-1 (P2) — TECH_EXTRACT step 8 clobbers an active focus and leaves a phantom ref
- `.aai/TECH_EXTRACT.prompt.md:35`. `state.mjs set-focus` replaces
  `current_focus` unconditionally. TECH_EXTRACT no longer touches
  `active_work_items`, so the focus it writes has no work item.
- Failure scenario: a downstream project mid-ride (focus `intake_change CHANGE-0042`)
  still has the seed. The operator follows the new doctor/bootstrap pointer
  (#588) and runs TECH_EXTRACT as the sole agent. The ride's focus is replaced, and
  the next tick routes `dispatch 5 Planning technology-extraction`, a scope with no
  intake.
- backed-by: repro `docs/ai/reviews/repro-onboarding-tech-extract-focus-clobber.sh`
  (exit 0, prints both lines).
- Not a regression in intent: the old step 8 asked for the same `current_focus` hand
  edit. But D6 makes it deterministic, and this scope's pointer invites the run in
  established projects. Unbacked as must-fix: D6 is frozen text.
- Recommended disposition: **promote-to-follow-up** (P2). Candidate fix: record
  the focus only when `current_focus.type` is `none` (else skip with a note), or
  drop step 8.

### NB-2 (P3) — TECH_EXTRACT under `AAI_ROLE=subagent`
- `.aai/TECH_EXTRACT.prompt.md:22`. Under `AAI_ROLE=subagent`,
  `check-state.mjs --repair` creates STATE (probe: `CREATED: ... rc=0`) because
  check-state has no single-writer guard. `set-focus` is refused (rc 3).
- The prompt's fallback ("skip the STATE steps and say so") also departs from
  SUBAGENT_CONTRACT D1, which says return the command under
  `state_update_commands`.
- Reachability is narrow: `orchestration-dispatch` returns
  `needs_llm state_file_missing` without a STATE (probed), so the deterministic
  rule 3 dispatch always has a STATE. In practice this leaves the focus unrecorded,
  which is no false record.
- Recommended disposition: **promote-to-follow-up** together with NB-1 (one
  TECH_EXTRACT STATE-semantics item). Otherwise (d) accepted residual: P3, assurance
  only, no observed bite, no false record.

### Reviewed and found sound (no finding)
- **isTechSeed CRLF/BOM/parity.** Both copies are byte-identical logic. CRLF is
  stripped per line, the `## ` check runs on the raw line (CRLF-safe), and trailing
  space/tab is stripped. A BOM can only prefix line 1 (the H1), so the decision does
  not change. utf8 (doctor) vs latin1 (bootstrap) decoding cannot change an ASCII
  prefix match. A directory at `docs/TECHNOLOGY.md` → doctor `readText` null /
  bootstrap `isFile` false, so both agree.
- **eslint detection.** `pc.file` is `statSync`, so the usual npm symlink
  `.bin/eslint` counts and a dangling link does not. The `.eslintrc` prefix glob
  covers `.eslintrc`, `.json`, `.js`, `.cjs`, `.yml` and `.yaml` (TEST-4127 covers
  four names). `hasDep` checks all four blocks. `package.json` `eslintConfig` and
  hoisted parent eslint are spec non-goals, and behaviour there is unchanged. With
  Yarn PnP plus an eslint dependency, the result is `yarn exec eslint .`
  (unchanged). PnP without a dependency gets the pin, which can't resolve plugins
  either, as the spec's residual risk notes. `cmds.lint === ESLINT8_PIN` cannot
  collide with a runner or script result (those return `make …`, `<pm> run …`).
- **Twins.** The sh and ps1 launchers hold no logic (TEST-4133). The sh launcher
  writes the same skill bytes as the module (TEST-4129).
- **Test hygiene.** No network: bootstrap spawns only `process.execPath`, and
  the npx stub is first on PATH. Temp dirs are under trapped roots or
  `new_own_scratch`. The doctor suite is `set -uo pipefail` (no `-e`), so bare
  `rc=$?` is safe. Pipelines end in `|| true` or read fully. The bootstrap-node
  suite's `log_fail` exits, so `run_lint_skill` failures leave the `lintskill`
  scratch dir behind (failure path only, INFO).
- **TEST-4019 re-base** (`test-aai-sync-node.sh`): a history comparison
  077ee649↔0ff18d63. It fails closed when a commit is absent, and CI is
  `fetch-depth: 0`. The SPEC-0310 measurement amendment wording matches since
  30928e24.
- **DR-12** `applyDrift`: reference side only. An unmatched pair is reported, and
  the "without DR-12" run shows only eslint problems (TEST-4130).

INFO (no gate): the D4 pin block says "rerun .aai/scripts/aai-bootstrap.sh" with no
PowerShell form. That is frozen D4 text.

## cannot_verify

See the YAML block: Windows/CRLF measurement of TEST-4134, real ESLint 8 behaviour,
the native PowerShell launcher, and bare `timeout` portability for TEST-4126. Each
one closes with the hosted PR-head run (and one manual real-ESLint run).

## Warning dispositions (H6)

- F1 BLOCKING: remediate-in-tree (required before PASS).
- NB-1 (P2): recommended promote-to-follow-up (suggested id
  `fu-tech-extract-focus-clobber`). The orchestrator records it.
- NB-2 (P3): recommended promote-to-follow-up merged with NB-1. Otherwise:
  `accepted residual: TECH_EXTRACT under AAI_ROLE=subagent can create a missing STATE via check-state --repair and skips set-focus instead of returning it; unreachable from deterministic rule-3 dispatch (needs_llm without STATE), no false record (P3, assurance-only).`

## Next steps

1. Remediate F1 (TEST-4134 subtracts later entries' credits, TEST-2824 pattern).
   RED: the repro script above fails the current test. GREEN: the repro's TEST-4134
   rc 0 on the simulated later ride, while the Mutation cell still bites.
2. The orchestrator files NB-1 (and NB-2) follow-ups.
3. Re-review (delta) after remediation. Owner sign-off is still owed on the
   unsigned contract amendments (`fu-amend-onboarding-tech-contract-d587c5`,
   `fu-amend-bootstrap-on-node-20261125t2122`).
