```yaml
review:
  scope: "main...refactor/pre-commit-checks-ps1-retire @ 230a7f7c (merge-base 3e6b52d5), path list from STATE code_review.scope (23 paths)"
  spec: docs/specs/SPEC-0279-spec-pre-commit-checks-ps1-retire.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/pre-commit-checks.ps1:1-3; tests/skills/test-aai-pre-commit-checks.sh:255-277 TEST-3448 (re-run here: PASS)" }
      - { ac: Spec-AC-02, call: compliant, citation: "tests/skills/pre-commit-checks-retired.Tests.ps1:6-86 (3 It, engine = (Get-Process -Id $PID).Path); TEST-3449 re-run here under pwsh 7: Total=3 Passed=3 Failed=0 Skipped=0; 5.1 is H1 (cannot_verify)" }
      - { ac: Spec-AC-03, call: compliant, citation: "pre-commit-checks.ps1 3 lines, ASCII, git mode 100644 (git ls-files -s), no param; TEST-3450 suite:302-336 with positive control" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/pre-commit-checks.sh:42,48,146,147 here-strings; TEST-3451 suite:136-140 (small and >=300000-byte twins)" }
      - { ac: Spec-AC-05, call: compliant, citation: "pre-commit-checks.sh:168-169; TEST-3452 suite:142-152 incl. --strict exit 1" }
      - { ac: Spec-AC-06, call: compliant, citation: "pre-commit-checks.sh:105; TEST-3453 suite:154-175 (exit 0, 3 indented lines, summary, commit through installed hook moves HEAD)" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-3454 suite:204-223; git diff --numstat 3e6b52d5 on the script = 7 7 (checked here)" }
      - { ac: Spec-AC-08, call: compliant, citation: "tests/skills/lib/pipe-grep-q-ratchet.sh deferral removed (diff -7 lines); TEST-3455 suite:230-251 (0 now, 7 baseline, test_128 PASS)" }
      - { ac: Spec-AC-09, call: compliant, citation: ".aai/AGENTS.md:262, docs/TECHNOLOGY.md:214, guard-config.mjs:35,149, docs-audit.yaml:15; TEST-3456 suite:338-374 with positive control" }
      - { ac: Spec-AC-10, call: compliant, citation: "test-aai-doc-numbering.sh -54 (test_809 gone), test-aai-tracked-ignored.sh test_1708 + ps1 arm gone, test-aai-suite-select.sh:1198; TEST-3457 suite:376-394; whole suites: r1 full sweep + r2 selected (validation reports)" }
      - { ac: Spec-AC-11, call: compliant, citation: "tests/skills/suite-map.yaml new row + two rows drop the ps1; suite-weights.tsv row; hygiene-pack pins 130; cd baseline row; TEST-3458 suite:405-440" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-3459 suite:442-462 (spaced target, cmp both files, launcher exit 1, PGQ 0)" }
      - { ac: Spec-AC-13, call: compliant, citation: "docs/rfc/RFC-0017...md:308 (phase 5 sentence), :325 (row reason, 323/281 kept); TEST-3460 suite:468-483" }
      - { ac: Spec-AC-14, call: compliant, citation: "launcher 3/2 lines, sh 323/239; decisions.jsonl fu-delete-retired-pre-commit-checks-ps1 P3 open; TEST-3461 suite:488-512" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-pre-commit-checks.sh, line: 220,
          issue: "TEST-3454 (numstat 7 7 vs 3e6b52d5 and byte parity with the 3e6b52d5 script) and TEST-3461:495 (sh exactly 323/239) are delivery measurements encoded as permanent gates on a live guard script",
          failure_scenario: "the next ride that legitimately edits pre-commit-checks.sh (a new check, a reworded message) gets TEST-3454 'numstat reads 9 7, expected 7 7' and TEST-3461 'expected 323 and 239' and must edit this suite; the failure reads like a regression of this ride" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-pre-commit-checks.sh, line: 423,
          issue: "TEST-3458 adds a fourth hard pin of the suite-map row count (130) and a fifth pin on the literal count of '-eq 130 ]]' in test-aai-hygiene-pack.sh (line 424)",
          failure_scenario: "the next ride that adds a suite must move the pin in hygiene-pack (x2), cloudflare-share TEST-3428 and this suite (x2); missing one fails a suite unrelated to its scope, as already happened in this ride (Amendment 1: the cloudflare-share pin was not in the Measurements)" }
  cannot_verify:
    - { claim: "Launcher behaviour and Pester file under Windows PowerShell 5.1 and native-Windows pwsh 7 (H1)", closes_with: "hosted ps1-quality Windows jobs green on the PR with pre-commit-checks-retired.Tests.ps1 discovered, 3 passed, 0 skipped, and the parse step passing on the launcher" }
    - { claim: "No downstream project calls the .ps1 from its own tooling (breaking change by design, exit 1)", closes_with: "not closable from this repository; CHANGELOG names the replacement" }
    - { claim: "Whole suites test-aai-doc-numbering, test-aai-tracked-ignored, test-aai-suite-select and test-aai-expert-fetch exit 0 at head 230a7f7c", closes_with: "r1 full sweep log at b017db94 plus r2 selected run (validation reports); not re-run by this reviewer per dispatch (no full sweep); the only delta since r1 is spec/ledger text" }
    - { claim: "TEST-3454/3455 positive controls on CI need commit 3e6b52d5 in the clone", closes_with: "skill-suite.yml jobs use fetch-depth: 0 (checked); the hosted run on the PR confirms" }
  overall: pass
```

# Code Review — pre-commit-checks-ps1-retire (round 1)

security_relevant: false

- Scope: `git diff main...HEAD` on branch `refactor/pre-commit-checks-ps1-retire`, head `230a7f7c`, merge-base `3e6b52d5`. Path list: STATE `code_review.scope` (23 paths). `check-committed-scope.mjs --from-state` says clean: 23 paths match the index. `git status --porcelain` shows only `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl` modified and uncommitted (orchestrator telemetry, outside the review).
- Spec: `docs/specs/SPEC-0279-spec-pre-commit-checks-ps1-retire.md` (frozen, ceremony 3). It has two amendments: Amendment 1 is a contract change, unsigned, tracked by `fu-amend-pre-commit-checks-ps1-retire` (P2, open); Amendment 2 is a measurement change.
- Dispatch prompt: no coaching. It did not characterize findings, pre-rate severity or exclude any area, so the full scope was reviewed.
- Tier: L3 mandatory review, most capable tier (claude-opus-5-5).

## Evidence I gathered myself

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash tests/skills/test-aai-pre-commit-checks.sh` gave rc 0. All 14 rows PASS, including TEST-3449 under pwsh 7 (Pester 3/3) and the nested selectors. Runtime was 24 s under the bash on PATH, which is 3.2.57, so the here-strings are proven on bash 3.2 too.
- `git diff --numstat 3e6b52d5 -- .aai/scripts/pre-commit-checks.sh` reads `7 7`.
- `git diff --stat 3e6b52d5 HEAD` over WORKFLOW.md, `.aai/templates/`, claude-hook-gate.sh, both installers, PROFILES.yaml, `.github/` and `.aai/*.prompt.md` is empty.
- A pipe inventory of `pre-commit-checks.sh` found no early-closing reader left. The remaining pipes go into `awk` (lines 43 and 141) or `sed` (lines 105, 244, 247, 267 and 298), and those read to EOF.
- `spec-lint` reports LINT PASS. `mutation-gate` reports GATE PASS with 14 rows, degraded=0. RED logs exist for all 14 rows, and there are 14 mutation records plus 5 patches.
- `git ls-files -ci --exclude-standard` is empty: no ignored artifact is committed. `.gitattributes` sets `*.ps1 text eol=lf`, so the launcher stays LF downstream.

## AC table walk

All 14 rows are compliant. The citations are in the YAML above. Deviations from the frozen text, each listed even where reasonable:

1. Amendment 1 is a contract change, unsigned. It covers the TEST-3457 and TEST-3458 selectors, `test_1736` looping over sh only, the cloudflare-share pin moving to 130, the cd-baseline row and the two-part secret fixture. It is disclosed, and owner sign-off is still owed under `fu-amend-pre-commit-checks-ps1-retire`. D-REF says "TEST-1706/1707 keep running unchanged"; that holds, but `test_1736` did change, which the amendment discloses.
2. Amendment 2 is a measurement change: closure-line wording, plus cloudflare-share added to the review scope.
3. The branch diff carries two append-only ledger lines outside the scope list. One is a `docs/ai/EVENTS.jsonl` doc_lifecycle event (draft to implementing, in commit 22c903f0). The other is a `docs/ai/tests/test-runs.jsonl` line from the r1 sweep (in commit 230a7f7c). This is INFO only: both are append-only telemetry, and neither is a code change.

## Findings

No BLOCKING findings.

### NB-1 (P3): Delivery measurements are pinned as permanent gates
- Where: `tests/skills/test-aai-pre-commit-checks.sh:220` (TEST-3454 numstat `7 7` and byte parity against `3e6b52d5`) and `:495` (TEST-3461, the `.sh` must be exactly 323/239). TEST-3461 at `:499-501` also requires the delete follow-up to be open.
- Failure scenario: a later ride edits `pre-commit-checks.sh` legitimately, for example to add a check. TEST-3454 and TEST-3461 then fail with messages that read as a regression of this ride, so that ride has to edit this suite as well.
- Why this is not a defect today: the spec mandated these rows (Spec-AC-07, Spec-AC-14). The script routes to FULL_RUN protected-l3, so the failure is loud and is seen at once. The D-FU delete ride has to rewrite this suite anyway.
- Recommended disposition: (d). accepted residual: P3 maintenance cost of spec-mandated ride-scoped pins; loud failure on FULL_RUN, no observed bite and no false record; the fu-delete-retired-pre-commit-checks-ps1 ride rewrites this suite.

### NB-2 (P3): Suite-map row-count pins are spreading
- Where: `tests/skills/test-aai-pre-commit-checks.sh:423-424` (TEST-3458).
- The problem: this is the fourth hard-coded suite-map row count (130). It is also a pin on how many times the literal `-eq 130 ]]` appears in `test-aai-hygiene-pack.sh`.
- Failure scenario: the next ride that adds a suite has to move five pins across three suites. Missing one fails an unrelated suite. That already happened in this ride: the cloudflare-share pin was absent from the Measurements and needed Amendment 1.
- Why it is spec-driven: Spec-AC-11 asks that both hygiene pins read 130. But re-asserting the count inside this suite duplicates what `test_090` and `test_129` already check, and the suite runs those selectors anyway at line 425.
- Recommended disposition: (b). The orchestrator files a P3 follow-up, for example `fu-suite-map-row-count-pin-sprawl`. It would cover collapsing the row-count pins to the hygiene-pack pair and dropping the re-asserted counts in cloudflare-share TEST-3428 and pre-commit-checks TEST-3458.

### INFO (not a finding)
- With bash 3.2, and with bash 5.1 or later once the payload exceeds the pipe buffer, the here-strings need a writable temp dir (TMPDIR, falling back to /tmp). If no temp dir is writable, the `grep -q <<<` conditions evaluate false. This environment was not observed anywhere, and the old `echo |` form was already broken on large input, so it is not ranked.

## cannot_verify

See the YAML block: H1 on native Windows (5.1 and pwsh 7), downstream callers of the `.ps1`, the whole-suite exits of the four touched suites at head (evidence comes from the validation rounds, not re-run here), and the CI history depth for the `3e6b52d5` controls (`fetch-depth: 0` is confirmed in skill-suite.yml).

## Warning dispositions (H6)

- NB-1: (d), the `accepted residual:` line quoted above.
- NB-2: (b), a P3 follow-up the orchestrator files with `follow-ups.mjs add`. The reviewer does not file refs.

## Next steps

- The orchestrator records NB-2's follow-up, and runs the set-code-review command.
- Before merge: the H1 hosted Windows Pester jobs, owner sign-off on Amendment 1 (`fu-amend-pre-commit-checks-ps1-retire`), and the L3 operator final-diff sign-off.
