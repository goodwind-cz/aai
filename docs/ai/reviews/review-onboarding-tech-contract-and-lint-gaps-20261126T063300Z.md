# Code Review — onboarding-tech-contract-and-lint-gaps (round 2, delta re-check)

```yaml
review:
  scope: "delta 30928e24..1c1ac27a (fix/onboarding-issues): db002fb5, 367415b6, 1c1ac27a; ride range 5f02b0e5..1c1ac27a"
  spec: docs/specs/SPEC-0317-spec-onboarding-tech-contract-and-lint-gaps.md
  prior_reports:
    - docs/ai/reviews/review-onboarding-tech-contract-and-lint-gaps-20261126T000013Z.md
    - docs/ai/reports/VALIDATION-20261126T000626Z-onboarding-tech-contract-and-lint-gaps.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-12, call: compliant, citation: "tests/skills/test-aai-prompt-diet.sh:2860-2869; TEST-4134 PASS in a fresh wrapper run of the prompt-diet suite (46 PASS / 0 FAIL); Mutation cell still RED (rc 1)" }
      - { ac: "Spec-AC-01..11, 13", call: compliant, citation: "delta touches none of their bytes; round-1 walk stands" }
  code_quality:
    verdict: pass
    prior_findings:
      - { id: F1, rank: BLOCKING, status: fixed, evidence: "repro-onboarding-test-4134-next-ride.sh on HEAD: 'TEST-012 rc=0 TEST-2824 rc=0 TEST-4134 rc=0', repro exit 1 (defect no longer reproduces)" }
      - { id: NB-1, rank: NON-BLOCKING P2, status: "open, disposition follow-up fu-tech-extract-focus-clobber (filed, listed open by follow-ups.mjs list)" }
      - { id: NB-2, rank: NON-BLOCKING P3, status: "open, folded into fu-tech-extract-focus-clobber (finding text names the AAI_ROLE=subagent path)" }
    findings:
      - { rank: NON-BLOCKING, id: R2-NB-1, severity: P3, file: tests/skills/test-aai-prompt-diet.sh, line: 2866,
          issue: "the later-credit sum is positional: only JUSTIFIED_ADDITIONS lines after the onboarding entry are subtracted",
          failure_scenario: "another prompt-growing PR lands on main before this one, and the merge puts main's ledger line above the onboarding line; TEST-4134 then fails with 'the corpus grew 585 B over 376171 but the entry credits 575 B' while TEST-012 and TEST-2824 pass (probe C)",
          disposition: "accepted residual: positional later-entry sum, the same assumption TEST-2824 has; unreachable while main == 5f02b0e5 (local refs); CI shows it red on the PR and the fix is reordering two ledger lines (P3, assurance-only)" }
  cannot_verify:
    - { claim: "the Windows CI leg and any CRLF checkout of .aai/*.prompt.md keep TEST-4134's byte measurement equal to the LF credit (carried from r1)", closes_with: "hosted skill-suite run on the PR head including the Windows legs" }
    - { claim: "npx eslint@8 . lints a real legacy-eslintrc project (carried from r1)", closes_with: "a manual run of the generated aai-lint skill in a real legacy eslintrc project (network)" }
    - { claim: "the PowerShell launcher writes the same aai-lint SKILL.md and Technology contract block on native Windows (carried from r1)", closes_with: "hosted Windows leg / Pester run on the PR head" }
    - { claim: "bare `timeout 120` in TEST-4126 exists on every host (carried from r1)", closes_with: "hosted run on the PR head" }
    - { claim: "origin/main has not moved past 5f02b0e5 (R2-NB-1 reachability); read from local refs, no fetch this round", closes_with: "git fetch before the PR merge, or the PR's own CI run" }
  overall: pass
```

security_relevant: false

## What the delta is

- `db002fb5` adds a `later` sum to `test_4134_onboarding_ledger_entry`.
  It adds the credits of `JUSTIFIED_ADDITIONS` entries after the onboarding entry,
  then subtracts that sum from the measured growth. This is the TEST-2824 pattern,
  copied line for line, including the `later=0; continue` on a match.
- `367415b6` commits the round-1 report, its two repro scripts, and the
  `fu-tech-extract-focus-clobber` follow-up record in `docs/ai/decisions.jsonl`.
  It also changes the INDEX date line.
- `1c1ac27a` appends telemetry to EVENTS and test-runs.

## Prior findings

### F1 (BLOCKING): FIXED at root
- **Root.** The test compared the whole live corpus against a frozen base and
  ignored growth that later entries credit. Subtracting those later credits makes it
  measure only this ride's share. That is the property Spec-AC-12 states: measured
  growth credited 1:1.
- **Repro on HEAD.** I ran `docs/ai/reviews/repro-onboarding-test-4134-next-ride.sh`.
  It printed `baseline TEST-4134 rc=0; after a later 1:1-credited ride: TEST-012 rc=0 TEST-2824 rc=0 TEST-4134 rc=0`
  and exited 1, so the defect no longer reproduces. The before-fix RED is in the
  round-1 report and was confirmed again by validation round 4 on 30928e24.
- **Unaccounted growth still bites.** On a scratch copy of HEAD I added a simulated
  later ride and the Mutation-cell text. The result was
  `FAIL TEST-4134: the corpus grew 624 B over 376171 but the entry credits '575' B`.
- **Mutation cell on HEAD.** I applied the spec's `sed` on
  `.aai/TECH_EXTRACT.prompt.md` to a scratch copy. The result was
  `FAIL TEST-4134: ... grew 624 B ... credits '575' B`, rc 1.
- **Ledgered reduction stays green (probe A).** A later ride removed 9 B and
  recorded its own negative `RECLAIMED` entry, with the TEST-012 pin moved by −9.
  TEST-012, TEST-2824 and TEST-4134 all passed. Validation r4 NB-1 noted that the
  test assumes the corpus only grows. Probe A narrows that note: only an *unledgered*
  reduction turns TEST-4134 red. Such a reduction already breaks the headroom-0
  convention, and TEST-2824 goes red on it too. The validator's accepted residual
  stands.
- **Suite.** `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
  gave rc 0 with 46 PASS and 0 FAIL. It was a fresh isolated run, not a reused one.
  TEST-010, 012, 2824 and 4134 all passed.
- **Spec table.** The TEST-4134 row (positive-integer credit, exactly one entry,
  TEST-010 and TEST-012 pass) still matches the test. The delta weakens no
  assertion and deletes no case.

### NB-1 (P2) and NB-2 (P3): dispositions acceptable
- `fu-tech-extract-focus-clobber` (P2) is in `docs/ai/decisions.jsonl` and shows
  up in `follow-ups.mjs list --ref onboarding-tech-contract-and-lint-gaps` as
  `open`. Its finding text covers both the focus overwrite (NB-1) and the
  `AAI_ROLE=subagent` check-state / skip-and-say-so path (NB-2). Round 1
  recommended exactly this: one TECH_EXTRACT STATE-semantics item. Both repros are
  committed.

## New in the delta

- **R2-NB-1 (P3)** is in the YAML block. The probe used a scratch copy of HEAD.
  One simulated concurrent ride's +10 B entry was inserted directly above the
  onboarding entry, and the TEST-012 pin was moved to 68759. Results: TEST-012
  rc 0, TEST-2824 rc 0, TEST-4134 rc 1. Once this PR merges, later rides append
  below the onboarding line, so the window is only the time before merge.
- **Ledgers.** The 30928e24 blobs of `EVENTS.jsonl`, `decisions.jsonl` and
  `tests/test-runs.jsonl` are byte-exact prefixes of the working tree. The HEAD
  blobs are too. The uncommitted EVENTS append comes after HEAD.
- **Gitignore.** `git ls-files -ci --exclude-standard` is empty. No gitignored
  artifact is committed, and the files under `docs/ai/reviews/` are not ignored.
- **INFO (no gate).** The `Usage:` lines of the two committed repro scripts give
  the shorter names (`repro-tech-extract-focus-clobber.sh`,
  `repro-test-4134-next-ride.sh`), not the committed file names. They are comments
  only, and the scripts take paths as arguments.
- **INFO (no gate).** The follow-up record's `decision` field holds the failure
  scenario, not a decision. The ledger reader accepts it.

## Warning dispositions (H6)

- F1: fixed (db002fb5).
- NB-1 (P2): follow-up `fu-tech-extract-focus-clobber` (filed, open).
- NB-2 (P3): folded into `fu-tech-extract-focus-clobber`.
- R2-NB-1 (P3): `accepted residual: positional later-entry sum, the same assumption TEST-2824 has; unreachable while main == 5f02b0e5; CI shows it red on the PR and the fix is reordering two ledger lines (P3, assurance-only)`.

## Next steps

1. Owner sign-off is still owed on the unsigned amendments
   (`fu-amend-onboarding-tech-contract-d587c5`,
   `fu-amend-bootstrap-on-node-20261125t2122`). This was carried from round 1 and
   does not gate this review.
2. Fetch main before the PR and confirm that no prompt-growing ledger entry has
   landed above the onboarding line (R2-NB-1).
