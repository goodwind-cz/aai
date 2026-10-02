---
review:
  scope: "the round-3 remediation on change/amendment-signature-asks-the-owner-too-often in /Users/ales/Projects/aai-amend (PR #422) — .aai/scripts/spec-amend.mjs, .aai/system/AUTONOMOUS_LOOP.md, tests/skills/test-aai-spec-amend.sh, docs/ai/decisions.jsonl and docs/specs/SPEC-0205-spec-amendment-signature-asks-the-owner-too-often.md, as they stood at commit 38797614 plus the uncommitted Spec-AC-19..21 / TEST-1375..1377 work"
  spec: docs/specs/SPEC-0205-spec-amendment-signature-asks-the-owner-too-often.md
  round: 3 (remediation of round-2's BLOCKING finding on the hardcoded restamp class, plus the migration-cohort correction)
  report_written_at: 2026-10-02T13:05Z by the Remediation role at round 4
  report_is_a_transcription: true
  covers_commits_up_to: 0db79662
  does_not_cover: "the round-4 changes (Spec-AC-22 / TEST-1378 shell quoting, Spec-AC-23 / TEST-1379 Test Plan summary guard, and the TEST-015 / TEST-016 assertion follow-through). Those are UNREVIEWED and need a fresh independent round."
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1354 PASS, full tests/skills/test-aai-spec-amend.sh run at 0db79662 + round-4 tree" }
      - { ac: Spec-AC-02, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1355 PASS, same run" }
      - { ac: Spec-AC-03, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1356 PASS, same run" }
      - { ac: Spec-AC-04, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1357 PASS, same run" }
      - { ac: Spec-AC-05, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1358 PASS, same run" }
      - { ac: Spec-AC-06, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1359 PASS, same run" }
      - { ac: Spec-AC-07, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1360 and TEST-1361 PASS, same run (both negative controls)" }
      - { ac: Spec-AC-08, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1362 PASS, same run" }
      - { ac: Spec-AC-09, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1363 PASS, same run" }
      - { ac: Spec-AC-10, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1364 PASS, same run" }
      - { ac: Spec-AC-11, call: compliant, derived_by: "round-3 review (evidenced by its own BLOCKING finding, which names this row)", citation: "the round-3 review found this row ASSERTING the retired hardcode claim and raised finding 1 against it; the row now reads conditional on Spec-AC-18's reversal (commit 94ed4888) and TEST-1365 PASSes at the final head" }
      - { ac: Spec-AC-12, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1366 PASS, same run" }
      - { ac: Spec-AC-13, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1367 and TEST-1368 PASS, same run" }
      - { ac: Spec-AC-14, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1369 PASS, same run" }
      - { ac: Spec-AC-15, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1370 PASS, same run; the conservation law and the selector are separated into Spec-AC-15 and Spec-AC-19 by the round-3 remediation this review was dispatched over" }
      - { ac: Spec-AC-16, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1371 PASS (spec-amend suite) and TEST-1372 PASS (tests/skills/test-aai-prompt-diet.sh, amendment-class-partition entry itemized, pin 50036 -> 50333)" }
      - { ac: Spec-AC-17, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1373 PASS, same run" }
      - { ac: Spec-AC-18, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1374 PASS, same run" }
      - { ac: Spec-AC-19, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1375 PASS, same run; docs/ai/reports/amendment-class-migration-correction-20261002T112955Z.md records the 13 reversed records" }
      - { ac: Spec-AC-20, call: compliant, derived_by: "round-3 review (evidenced by its own NON-BLOCKING finding 3, which names this row's wording against TEST-1376's guard)", citation: "TEST-1376 PASS; the review recorded that the guard is narrower than the row's wording — filed as fu-flagspecs-guard-line-scoped, NOT closed by this report" }
      - { ac: Spec-AC-21, call: compliant, derived_by: "re-derived at transcription", citation: "TEST-1377 PASS, same run" }
  code_quality:
    verdict_as_returned: fail (1 BLOCKING)
    verdict_after_the_blocking_fix: "the BLOCKING finding's own claim was re-checked at transcription and no longer holds (see below); this is a re-derivation of ONE finding, not a fresh verdict over the final code"
    findings:
      - { rank: BLOCKING, number: 1,
          file: "docs/specs/SPEC-0205-spec-amendment-signature-asks-the-owner-too-often.md",
          line: "the D1 section and the Spec-AC-11 row",
          issue: "The spec still asserted, unqualified, that `restamp` is reached only on allocator drift and therefore hardcodes `measurement` — the exact claim this ride retired from .aai/system/AUTONOMOUS_LOOP.md section 6a under Spec-AC-21, and the exact claim D3 Amendment 3 names as the root of three remediation rounds. A grep for the retired phrasing across every .md in the repository found it surviving in one place: this spec, two sections upstream of its own correction. A frozen spec cited as prior art that teaches the defect it cures is worse than no spec.",
          status: FIXED,
          fixed_in: 94ed4888500bd4e9bf9acbb35247d765fb736f0a,
          fix: "D1 now states that restamp MEASURES its cause and takes `contract` when the reversal does not prove the allocator, keeping the old sentence as a quoted retraction so the history stays legible; Spec-AC-11 is conditional on Spec-AC-18's reversal." }
      - { rank: NON-BLOCKING, number: 2,
          file: ".aai/scripts/spec-amend.mjs",
          line: "cmdClassify",
          issue: "cmdClassify has no duplicate-overlay guard, and its implicit tracked_by path skips the closed-tracker refusal that only fires for an explicit --tracked-by.",
          failure_scenario: "Re-running a correction after a partial failure appends a second redundant overlay (harmless to the fold, permanent on an append-only ledger), and if an owner closed the tracker in between, the overlay lands pointing at a closed item and only then exits 1. No test exercises a retry.",
          status: FILED,
          disposition: "follow-up fu-classify-rerun-not-deduped (P3, ref amendment-signature-asks-the-owner-too-often, filed 2026-10-02T12:34:35Z, open)" }
      - { rank: NON-BLOCKING, number: 3,
          file: "tests/skills/test-aai-spec-amend.sh",
          line: "TEST-1376 arm 2 (the FLAG_SPECS guard)",
          issue: "TEST-1376's FLAG_SPECS guard extracts flags only from the same physical line as the subcommand token, so the multi-line USAGE block's continuation lines are unchecked.",
          failure_scenario: "Spec-AC-20 is worded as every place the CLI prints a command; the three single-line printed remedies are covered but a bad flag on a USAGE continuation line would pass.",
          status: FILED,
          disposition: "follow-up fu-flagspecs-guard-line-scoped (P3, ref amendment-signature-asks-the-owner-too-often, filed 2026-10-02T12:34:35Z, open)" }
  cannot_verify:
    - { claim: "That the round-3 review's per-row citations for Spec-AC-01..10, 12..19 and 21 were the ones recorded in this file.",
        reason: "The round-3 review's report was never written to the tree; only its three findings survive, in commit 94ed4888's message and in the two follow-up records. Every row NOT marked `derived_by: round-3 review` above carries a citation re-derived at transcription, not the reviewer's own.",
        closes_with: "Nothing — the original artifact does not exist. The re-derived citations are reproducible by re-running the two suites; the provenance label is what keeps them from being read as the reviewer's." }
    - { claim: "That this report covers the code as it now stands.",
        reason: "It covers the tree up to 0db79662. The round-4 remediation (Spec-AC-22 / Spec-AC-23 and their tests, plus the TEST-015 and TEST-016 assertion follow-through) landed after it.",
        closes_with: "A fresh independent code review dispatched over the round-4 diff." }
  overall: "pass for Spec-AC-01..21 at 0db79662, with the BLOCKING finding fixed in 94ed4888 and two NON-BLOCKING findings filed as open follow-ups; NOT a verdict over the round-4 changes"
---

# Code Review — amendment-signature-asks-the-owner-too-often (round 3)

## What this file is, and what it is not

This is the round-3 code review's record, **written into the tree at
remediation round 4 on 2026-10-02 by the Remediation role**, because the
round-3 review ran, returned its findings, and its report was never saved.
Codex raised that as a P1 on PR #422: `code_review.report` pointed at
`review-amendment-signature-asks-the-owner-too-often-20261002T094327Z.md`,
whose AC walk stops at Spec-AC-17 and certifies the pre-round-2 hardcoded
restamp behaviour, so the recorded PASS did not cover the code that shipped.

The filename carries `20261002T123435Z` — the moment the round-3 review's
findings were filed to the ledger — because that is when the review
concluded, not when this transcription was typed. Both facts are in the
frontmatter.

Three things are therefore stated plainly rather than smoothed over:

1. **The three findings are the reviewer's own.** They are reproduced from
   where they were recorded at the time: finding 1 from the body of commit
   `94ed4888`, which was written to fix it, and findings 2 and 3 verbatim
   from the two `follow_up` records appended at `2026-10-02T12:34:35Z`
   (`fu-classify-rerun-not-deduped`, `fu-flagspecs-guard-line-scoped`), each
   of which names itself "code review round 3 on PR #422, NON-BLOCKING
   finding 2 / 3". No finding has been added, softened or invented.
2. **Most of the AC walk is re-derived, not recovered.** Only Spec-AC-11 and
   Spec-AC-20 can be shown to have been walked by the round-3 reviewer, from
   the two findings that name them. Every other row is marked
   `derived_by: re-derived at transcription` and cites a test outcome
   observed at the final head, not a citation the reviewer wrote.
3. **This report does not cover the round-4 code.** Spec-AC-22, Spec-AC-23,
   TEST-1378, TEST-1379 and the TEST-015 / TEST-016 assertion changes landed
   after it. They are unreviewed.

## Re-derivation performed at transcription

Run on the round-4 tree (branch `change/amendment-signature-asks-the-owner-too-often`,
base commit `0db79662`), `env -u AAI_ROLE`:

- `bash tests/skills/test-aai-spec-amend.sh` — exit 0, all tests pass
  (TEST-1354..1379 inclusive).
- `bash tests/skills/test-aai-prompt-diet.sh` — exit 0, TEST-1372 reports
  the itemized `amendment-class-partition` ledger entry and the 297 B
  ROLE_COMMON pointer credited 1:1.
- `bash tests/skills/test-aai-follow-ups.sh` — exit 0.
- The BLOCKING finding's own test: `/usr/bin/grep` for the retired phrasings
  across the repository. `so it hardcodes` and `reachable only from allocator
  anchor drift` are absent from `.aai/system/AUTONOMOUS_LOOP.md`, and the
  spec's D1 section now carries the measured-cause rule with the retired
  sentence quoted as a retraction — which is what TEST-1377 pins.

## Disposition of the NON-BLOCKING findings

Both remain OPEN follow-ups against this ride's ref. Neither is closed by
this report, and neither was fixed at round 3 or round 4:

| Follow-up | Severity | Status | What it holds |
|-----------|----------|--------|---------------|
| `fu-classify-rerun-not-deduped` | P3 | open | no duplicate-overlay guard on a classify retry, and the implicit `tracked_by` path skips the closed-tracker refusal |
| `fu-flagspecs-guard-line-scoped` | P3 | open | TEST-1376's guard is scoped to one physical line, so the USAGE block's continuation lines are unchecked |

Round 4's TEST-1378 arm 2 adds a second source-wide guard over printed
commands (shell quoting) and is scoped the same way — to the physical line
carrying the command token. It does not close
`fu-flagspecs-guard-line-scoped`; it inherits the same limit, which is
recorded here so the follow-up is read as covering both guards.
