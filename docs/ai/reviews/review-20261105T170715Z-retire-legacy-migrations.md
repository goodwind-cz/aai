# Code review re-pass (r4) - retire-legacy-migrations

security_relevant: true

- Scope: `git diff origin/main...HEAD`. origin/main is the merge base f324b66f; the head is fcf4b026; 39 files.
- Since the r2 review (head dc0a1fbb), the scope gained b33b8e9b (the review record), f71b52cf (r3: refuse skipped names, newline name) and fcf4b026 (r4: index byte restore).
- Spec: docs/specs/SPEC-0273-spec-retire-legacy-migrations.md with its post-freeze amendments:
  - contract records 15:35:25Z, 16:13:24Z and 16:43:22Z, all **unsigned** and tracked by the open `fu-amend-spec-retire-legacy-migrations`;
  - measurement record 15:37:24Z;
  - the five earlier measurement records.
- Reviewer: claude-opus-5-5. The implementer and remediator were sonnet.
  - The same context ran validation r2-r4 and the r2 review; this is disclosed here.
  - The reviewer wrote none of the implementation.
- Coaching check: the dispatch listed the carried residuals that the notes must state. It did not pre-rate new findings or exclude scope. The full scope was reviewed.
- Validation r4: PASS, docs/ai/reports/VALIDATION-retire-legacy-migrations-r4.md. Its probes and evidence are reused here and cited by id.

```yaml
review:
  scope: origin/main...HEAD (f324b66f..fcf4b026)
  spec: docs/specs/SPEC-0273-spec-retire-legacy-migrations.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/migrate-state-to-local.mjs:21-65; TEST-3380 PASS, replay RED" }
      - { ac: Spec-AC-02, call: compliant, citation: "mjs:69-163; TEST-3381 PASS; parity r3==r4 24/24" }
      - { ac: Spec-AC-03, call: compliant, citation: "mjs:76-95,103,150-151; TEST-3382 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "mjs:18,113-122; TEST-3383, TEST-3384, TEST-3401, TEST-3402 PASS (Linux 17/17, macOS 16+1 skip); TEST-3402 r4 RED on f71b52cf reproduced; probes S0-S9, A1-A8, L1-L5 identical (A3b/L6 exotic split-index config: NB-r4-1)" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/migrate-state-to-local.sh, .ps1; TEST-3385, TEST-3386 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-3387 PASS (bash, sh, dash; path with space)" }
      - { ac: Spec-AC-07, call: compliant, citation: "tests/skills/legacy-migrations.Tests.ps1; Pester 7/7 inside TEST-3388" }
      - { ac: Spec-AC-08, call: compliant, citation: "aai-canonicalize.{sh,ps1}, migrate-yaml-to-jsonl.{sh,ps1}; TEST-3389, TEST-3390 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: ".aai/SKILL_CANONICALIZE.prompt.md; four wrappers; TEST-3391 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: ".aai/AGENTS.md, SKILLS.md, docs/USER_GUIDE.md; TEST-3392 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-3393, TEST-3394 PASS" }
      - { ac: Spec-AC-12, call: compliant, citation: ".aai/system/PROFILES.yaml; TEST-3395 PASS" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-3396 PASS" }
      - { ac: Spec-AC-14, call: compliant, citation: "PROFILES, suite-map.yaml, ps1-quality.yml, cd-subshell baseline, suite-weights.tsv; TEST-3397 PASS" }
      - { ac: Spec-AC-15, call: compliant, citation: "prompt-diet-ledger.sh, test-aai-prompt-diet.sh, test-aai-pr-preflight.sh; TEST-3398 PASS; prompt-diet suite rc 0" }
      - { ac: Spec-AC-16, call: compliant, citation: "docs/rfc/RFC-0017 inventory; TEST-3399 PASS" }
      - { ac: Spec-AC-17, call: compliant, citation: "TEST-3400: before 893, after 184, module 160 of 160 code lines, 183 of 200 lines" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/migrate-state-to-local.mjs, line: 121,
          issue: "the byte restore can put back an index whose split-index shared file git expired during update-index (RM_ARGS at mjs:18 does not pin splitIndex.sharedIndexExpire)",
          failure_scenario: "core.splitIndex=true + splitIndex.maxPercentChange=0 + splitIndex.sharedIndexExpire=now + a git~1 or non-UTF-8 survivor -> rc 1 with 'the index is unchanged', but every git command then fails 'sharedindex.<sha>: index file open failed' (A3b macOS, L6 Linux); default maxPercentChange does not trigger it (A3d, A3e)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/migrate-state-to-local.mjs, line: 121,
          issue: "the restore is a plain truncate+write: no index.lock, no temp+rename; a write failure escapes run() as an uncaught exception",
          failure_scenario: "EIO on the restore -> Node stack trace, exit 1, no D1 line, index left with the planned paths staged as deleted (W1); ENOSPC mid-write -> truncated index (W2); a concurrent git writer between removal and restore wins the race (C1, C2), as it also did against the r3 reset" }
  cannot_verify:
    - { claim: "Windows PowerShell 5.1 and pwsh 7: the launchers and the Pester suite, including the -DyRun refusal", closes_with: "the hosted Windows Pester job green on the PR" }
    - { claim: "the whole tree after the r3 and r4 deltas (only the selected and core suites ran)", closes_with: "the close-out full sweep (AAI_TEST_TIMEOUT=3600) green" }
    - { claim: "the index byte restore on Windows (NTFS refuses git~1 on disk, file locking on .git/index by other processes)", closes_with: "a Windows run of TEST-3402 on the hosted job, or accept that the survivor path is not reachable there in the ordinary case" }
    - { claim: "real downstream monorepo installs migrate end to end", closes_with: "a scratch aai-sync install into a subdirectory target followed by doctor CAT-10 PASS (TEST-3401 proves the module seam only)" }
  overall: pass
```

## AC walk

All 17 Spec-AC rows are compliant (see the block above).

- Each claimed test, TEST-3380 to TEST-3402, exists in `tests/skills/test-aai-legacy-migrations.sh`.
- At fcf4b026 the suite passed 23 of 23 rows, with Pester 7 of 7.
- `mutation-run --replay` reddens 23 of 23 records.
- `mutation-gate`, `spec-lint`, `spec-amend list --strict` and the docs-audit close gate each exit 0.

Deviations from the frozen spec, each covered by an amendment:

- D1 RM_ARGS is now `update-index`, and D2 gains `[CmdletBinding()]` (15:35:25Z).
- Spec-AC-04 covers names git skips without failing (16:13:24Z).
- The rollback is an index-file snapshot restore, not `git reset -q` (16:43:22Z). The Spec-AC-04 predicate text is unchanged; the TEST-3402 row was extended.
- All three contract records are **unsigned**. The owner's sign-off on `fu-amend-spec-retire-legacy-migrations` is still owed before close.

## r2 findings, now closed

| r2 finding | Status |
|---|---|
| NB-1, the silent skip | Closed by f71b52cf and fcf4b026. Survivors are refused with rc 1, the index is restored byte for byte, and TEST-3402 is RED-proved twice. |
| NB-3, newline framing | Closed. `line\nbreak.log` is in TEST-3383. |
| NB-5, RED_CLASS | Closed. All RED logs carry `RED_CLASS: product_red`, and `tdd-evidence-check --red` returns rc 0. |

## Findings and dispositions (H6)

| # | Rank | Location | Disposition (recommended) |
|---|---|---|---|
| NB-r4-1 | P3 | `.aai/scripts/migrate-state-to-local.mjs:18`, `:121` | Not (d), because when it bites it leaves a false "the index is unchanged". Either (a) remediate in the tree with `RM_ARGS = ['-c', 'splitIndex.sharedIndexExpire=never', 'update-index', '--force-remove', '-z', '--stdin']` (proved in scratch: A3b status clean; it fits the 160-line budget), plus a TEST case and a contract note; or (b) the follow-up `fu-migrate-state-split-index-expire` (P3, suggested, not filed). The orchestrator records the choice. |
| NB-r4-2 | P3 | `.aai/scripts/migrate-state-to-local.mjs:121` | (d) accepted residual (below). |
| NB-2 (r2) | P3 | `.aai/scripts/migrate-state-to-local.mjs:97` | (d) accepted residual, carried and unchanged. |
| NB-4 (r2) | P3 | `.aai/scripts/migrate-state-to-local.mjs:46` | (d) accepted residual, carried and unchanged. |
| dry-run git~1 (r3 INFO) | P3 | `.aai/scripts/migrate-state-to-local.mjs:103`, `:113` | (d) accepted residual. |

accepted residual: NB-r4-2 the index restore is a non-atomic write that ignores index.lock; a failed write crashes loudly (W1) or truncates the index (W2) without claiming the index unchanged, and the concurrent-writer race is the same as under the r3 reset (P3, no observed bite, no false record)
accepted residual: NB-2 sparse-index users untrack evidence that is not on disk; the data stays in history (P3, no bite, no false record)
accepted residual: NB-4 -h after a second positional exits 2 instead of printing usage (P3, cosmetic)
accepted residual: a dry run on a tree with a git~1 or non-UTF-8 evidence name exits 0 and predicts the untrack; the real run refuses with rc 1 and changes nothing (P3, the dry run cannot see git's skip)

INFO (non-gating):

- `docs/ai/tdd/retire-legacy-migrations/red/red-TEST-3402.log.new` is a stray local file. It is gitignored and untracked.
- `toRemove.includes` (mjs:120) is quadratic in the number of evidence files. That is negligible at realistic sizes.
- The D1 error and dry-run texts still say `git rm --cached`; Known limitations discloses this.

## Next steps

1. The orchestrator records the NB-r4-1 disposition: (a) fix in the tree, or (b) the follow-up.
2. The owner signs `fu-amend-spec-retire-legacy-migrations`, covering three contract records.
3. Run the close-out full sweep, then the PR, then the Windows Pester job.
