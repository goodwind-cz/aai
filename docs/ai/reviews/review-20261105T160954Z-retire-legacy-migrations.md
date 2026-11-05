# Code review - retire-legacy-migrations

security_relevant: true

- Scope: `git diff origin/main...HEAD` (origin/main = merge base f324b66f, head dc0a1fbb, 38 files)
- Spec: docs/specs/SPEC-DRAFT-spec-retire-legacy-migrations.md, including the post-freeze amendments:
  - 15:35:25Z contract, unsigned and tracked by `fu-amend-spec-retire-legacy-migrations`;
  - 15:37:24Z measurement;
  - five earlier measurement records.
- Reviewer: claude-opus-5-5. The implementer and remediator were sonnet. The same context ran validation r2 just before this review, which is disclosed here; this reviewer wrote none of the implementation.
- Coaching check: the dispatch told the validation where to attack. It did not pre-rate or scope-exclude anything for this review. The full scope was reviewed.
- security_relevant is true: it carries over from the validation reports (M-2, the shell-injection class, is closed).

```yaml
review:
  scope: origin/main...HEAD (f324b66f..dc0a1fbb)
  spec: docs/specs/SPEC-DRAFT-spec-retire-legacy-migrations.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/migrate-state-to-local.mjs:21-69; TEST-3380 PASS, replay RED" }
      - { ac: Spec-AC-02, call: compliant, citation: "mjs:72-169; TEST-3381 PASS; parity matrix r1==r2 22/22" }
      - { ac: Spec-AC-03, call: compliant, citation: "mjs:79-93,101-104,157; TEST-3382 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "mjs:18,114-120; TEST-3383, TEST-3384, TEST-3401 PASS; TEST-3401 RED on 91d97349; probes P1-P5" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/migrate-state-to-local.sh:1-9, .ps1:1-12; TEST-3385, TEST-3386 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-3387 PASS (bash, sh, dash; path with space)" }
      - { ac: Spec-AC-07, call: compliant, citation: ".ps1:3 [CmdletBinding()]; tests/skills/legacy-migrations.Tests.ps1:91-100; Pester 7/7; -DyRun RED on 91d97349" }
      - { ac: Spec-AC-08, call: compliant, citation: "aai-canonicalize.{sh,ps1}, migrate-yaml-to-jsonl.{sh,ps1}; TEST-3389, TEST-3390 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: ".aai/SKILL_CANONICALIZE.prompt.md:1-12; four wrappers; TEST-3391 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: ".aai/AGENTS.md:94,148,216; SKILLS.md; docs/USER_GUIDE.md; TEST-3392 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-3393, TEST-3394 PASS" }
      - { ac: Spec-AC-12, call: compliant, citation: ".aai/system/PROFILES.yaml:223; TEST-3395 PASS (as amended 13:49:29Z)" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-3396 PASS; aai-doctor TEST-439 PASS after B5" }
      - { ac: Spec-AC-14, call: compliant, citation: "PROFILES, suite-map.yaml:1168-1180, ps1-quality.yml:82,109, cd-subshell baseline; TEST-3397 PASS; suite-weights.tsv:118-119" }
      - { ac: Spec-AC-15, call: compliant, citation: "prompt-diet-ledger.sh:269, test-aai-prompt-diet.sh:1029, test-aai-pr-preflight.sh:235; TEST-3398 PASS" }
      - { ac: Spec-AC-16, call: compliant, citation: "docs/rfc/RFC-0017 inventory; TEST-3399 PASS" }
      - { ac: Spec-AC-17, call: compliant, citation: "TEST-3400: after 182, module 158 of 160 code lines, 181 of 200 lines" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/migrate-state-to-local.mjs, line: 114,
          issue: "update-index --force-remove exits 0 when it skips a path, either a verify_path rejection ('Ignoring path') or a name that does not survive the utf8 decode of ls-files, so success and the Files untracked count are claimed for a file that stays tracked",
          failure_scenario: "a tracked docs/ai/tdd/git~1/a.log (or a Latin-1 named log) -> rc 0, 'Files untracked: 3', file still in the index; old sh and r1 untracked git~1 correctly (probes P8, P9)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/migrate-state-to-local.mjs, line: 97,
          issue: "under a sparse index the module untracks skip-worktree evidence that is not on disk; old sh and r1 refused (git rm sparse guard)",
          failure_scenario: "sparse-checkout cone without docs/ai/loop -> rc 0, docs/ai/loop/* leave the index, the migration commit drops them from the tip with no local copy (history keeps them)" }
      - { rank: NON-BLOCKING, file: tests/skills/lib/migrate-state-to-local.test.mjs, line: 252,
          issue: "TEST-3383 has no newline-bearing name, so NUL framing is not pinned",
          failure_scenario: "a refactor to '--stdin' plus join('\\n') passes TEST-3383 and TEST-3401 (mutant m2) yet mis-handles a tracked name containing a newline or starting with a double quote" }
      - { rank: NON-BLOCKING, file: .aai/scripts/migrate-state-to-local.mjs, line: 46,
          issue: "parseArgs refuses with exit 2 before honouring -h when a second positional precedes it (r1 NB2)",
          failure_scenario: "node migrate-state-to-local.mjs a b -h -> 'unexpected argument: b' exit 2 instead of usage" }
      - { rank: NON-BLOCKING, file: docs/ai/tdd/retire-legacy-migrations/red/red-TEST-3401.log, line: 1,
          issue: "the two r1-remediation RED logs (red-TEST-3401.log, red-TEST-3388-dyrun.log) carry no RED_CLASS line",
          failure_scenario: "tdd-evidence-check --red returns rc 2 UNCLASSIFIED; a later gate reading these logs refuses them as RED-proof" }
  cannot_verify:
    - { claim: "Windows PowerShell 5.1: the [CmdletBinding()] binding error exits non-zero with no change, and .ProviderPath works", closes_with: "the hosted Windows Pester job (5.1 and pwsh 7 legs) green on the PR" }
    - { claim: "the whole tree after the r2 delta (only the selected and core suites ran)", closes_with: "the close-out full sweep (AAI_TEST_TIMEOUT=3600) green" }
    - { claim: "real downstream monorepo installs migrate end to end", closes_with: "a scratch aai-sync install into a subdirectory target followed by doctor CAT-10 PASS (TEST-3401 proves the module seam only)" }
  overall: pass
```

## AC walk

All 17 Spec-AC rows are compliant (see the block above). Each claimed TEST-3380 to TEST-3401 exists in `tests/skills/test-aai-legacy-migrations.sh` and passed at dc0a1fbb: 22 of 22, with Pester 7 of 7. `mutation-run --replay` reddens 22 of 22 records.

Deviations from the frozen spec, each covered by an amendment:

- D1 RM_ARGS is now `update-index --force-remove -z --stdin`, and D2 gains `[CmdletBinding()]` and `.ProviderPath`. Contract amendment 15:35:25Z: **unsigned**, tracked by the open `fu-amend-spec-retire-legacy-migrations`. The owner's sign-off is still owed.
- The TEST-3383 mutation column changed. Measurement amendment 15:37:24Z, verified by grep and replay.
- The error and dry-run texts still say `git rm --cached` although the command is now update-index. The spec's Known limitations discloses this.
- The earlier measurement amendments are unchanged from r1. r1 NB1 judged two of them (13:31 and 13:49) borderline-contract; that judgement stands as disclosure.

## Findings and dispositions (H6)

| # | Rank | Location | Disposition (recommended) |
|---|---|---|---|
| NB-1 | P2 | `.aai/scripts/migrate-state-to-local.mjs:114` | (a) Remediate in the tree: after the removal, re-list `ls-files -z -- <toRemove>` and fail with the D1 line on any survivor. The module has 2 lines of headroom. Otherwise (b) the follow-up `fu-migrate-state-silent-skip` (suggested, not filed). |
| NB-2 | P3 | `.aai/scripts/migrate-state-to-local.mjs:97` | (d) accepted residual: sparse-index users untrack evidence that is not on disk. The data stays in history and the migration's purpose is unchanged. No bite has been observed, and no false record is left. |
| NB-3 | P3 | `tests/skills/lib/migrate-state-to-local.test.mjs:252` | (a) Remediate in the tree: add one name containing a newline to the TEST-3383 fixture. Its count assertion follows from `names.length`. |
| NB-4 | P3 | `.aai/scripts/migrate-state-to-local.mjs:46` | (d) accepted residual: the help ordering is cosmetic and the refusal is safe. |
| NB-5 | P3 | `docs/ai/tdd/retire-legacy-migrations/red/red-TEST-3401.log`, `red-TEST-3388-dyrun.log` | (a) Remediate before close: append `RED_CLASS: product_red`. The validator re-proved both REDs (r2 evidence file). |

accepted residual: NB-2 sparse-index untracking of not-on-disk evidence (P3, no bite, no false record)
accepted residual: NB-4 -h after a second positional exits 2 (P3, cosmetic)

INFO (non-gating):

- `GIT_LITERAL_PATHSPECS` (`mjs:17`) now only reaches `ls-files` over constant paths.
- `[CmdletBinding()]` makes `-D` ambiguous between `-Debug` and `-DryRun`.
- TEST-3396 pins the caller lines to f324b66f by design (Spec-AC-13). Any later edit to the aai-doctor or aai-sync hint must move that pin.
- M-12 could state that its exit 2 is the module's contract and that the ps1 launcher's binding error stays exit 1.

## Next steps

1. The orchestrator records the dispositions above. NB-1, NB-3 and NB-5 are cheap in-tree fixes. If NB-1 is fixed, it needs a TEST and RED of its own, and a contract note, because it is D1 module behaviour.
2. The owner signs `fu-amend-spec-retire-legacy-migrations`.
3. Run the close-out full sweep, then the PR, then the Windows Pester job.
