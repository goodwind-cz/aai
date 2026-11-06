```yaml
review:
  scope: "git diff main...HEAD (main 8293605d ... refactor/retire-shell-loop-runner b6d9e3fa, 7 commits, 28 files)"
  spec: docs/specs/SPEC-0274-spec-retire-shell-loop-runner.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/autonomous-loop.sh:1-4; TEST-3403 PASS (bash, sh, dash, no SKIP-CASE) in r3 sweep test-20261106-111519" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/autonomous-loop.ps1:1-3; TEST-3404 PASS; TEST-3405 PASS Total=4 Passed=4 Failed=0 Skipped=0" }
      - { ac: Spec-AC-03, call: compliant, citation: "both launchers ASCII, 100644 (git ls-files -s), sh 4 lines / ps1 3 lines, no param block; TEST-3406 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/AGENTS.md:142 and former :220; SKILL_LOOP:4; BOOTSTRAP_DIFF:7; README.md:218,239; TECHNOLOGY.md:47; USER_GUIDE.md:2224-2228; git grep autonomous-loop outside docs/tests/CHANGELOG = launchers + PROFILES only; TEST-3407 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/system/AUTONOMOUS_LOOP.md:220-238; loop-digest.mjs --write exists (loop-digest.mjs:24); TEST-3408 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/test-aai-check-state.sh:579-589; TEST-3409 PASS incl. positive control; aai-check-state PASS in sweep" }
      - { ac: Spec-AC-07, call: compliant, citation: "tests/skills/lib/prompt-diet-ledger.sh:270 (-67); test-aai-prompt-diet.sh:1029-1030 pin 64221; TEST-3410 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "tests/skills/suite-map.yaml:1186-1192; PROFILES.yaml:107-108 unchanged; TEST-3411 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-3412 PASS (core install into a path with a space, target launchers under bash and pwsh)" }
      - { ac: Spec-AC-10, call: compliant, citation: "RFC-0017 phase 5 row :308 and inventory row :322; TEST-3413 PASS incl. TEST-2624" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-3414 PASS: 793 before, 4 after" }
      - { ac: Spec-AC-12, call: compliant, citation: "docs/ai/decisions.jsonl fu-delete-retired-shell-loop-runner (P3); TEST-3415 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/system/AUTONOMOUS_LOOP.md, line: 55,
          issue: "Section 4 still says the run budget is enforced as 'wall-clock on the runners'. The runner's --max-run-seconds cap (main:.aai/scripts/autonomous-loop.sh:32,356-366) is gone, nothing else in .aai enforces a wall-clock cap, and neither the CHANGELOG entry nor D-PROPOSE names this loss; only --propose-only is declared unported.",
          failure_scenario: "An operator plans an overnight unattended ride, reads section 4 and relies on a wall-clock stop that no remaining runner or skill provides; the ride is bounded only by ticks and in-session token/USD telemetry, and the release notes never told them the cap went away." }
  cannot_verify:
    - { claim: "autonomous-loop.ps1 and retired-loop-runner.Tests.ps1 behave the same under Windows PowerShell 5.1 and native-Windows pwsh 7",
        closes_with: "green hosted ps1-quality Windows Pester jobs on the PR with retired-loop-runner.Tests.ps1 discovered and not skipped (H1)" }
    - { claim: "No downstream consumer still calls the runners from cron, CI or a wrapper",
        closes_with: "cross-repo evidence; the scope only proves no shipped AAI path calls them (CHANGELOG names the break)" }
  overall: pass
```

# Code review: retire-shell-loop-runner

security_relevant: false

- Scope: `git diff main...HEAD` in worktree `/Users/ales/Projects/aai-worktrees/retire-shell-loop-runner`, base main `8293605d`, head `b6d9e3fa` (7 commits, 28 files, +1148/-1045).
- Spec: `docs/specs/SPEC-0274-spec-retire-shell-loop-runner.md` (frozen, ceremony_level 2, two unsigned contract amendments under `fu-amend-spec-retire-shell-loop-runner`).
- Preflight: STATE `worktree.user_decision: worktree`, base `main`; `git status --porcelain` holds only the gitignored-in-intent runtime ledgers `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl`, both outside the review scope. No committed gitignored artifacts (`git ls-files -ci --exclude-standard` empty).
- Dispatch prompt: it named the scope, the spec and the validation report and pointed at carried NBs. It did not pre-rate findings or exclude areas. The full scope was reviewed.
- Evidence reused: the r3 full sweep on this exact HEAD (`docs/ai/validation/retire-shell-loop-runner/r3-full-sweep.log`, 126 pass / 0 fail / 1 unmapped skip; suite log `tests/skills/results/test-20261106-111519/aai-retired-loop-runner.log` shows TEST-3403..3415 all PASS with no SKIP-CASE). No suite was re-run by this review.

## Verdict 1: spec_compliance = pass

All twelve Spec-AC rows are compliant (table above). Every TEST-3403..3415 row exists in `tests/skills/test-aai-retired-loop-runner.sh` and passed in the r3 sweep. The AC Status table still reads `planned`; the validator's Rule-1 carve (rows flip at close) covers it.

Deviations from the frozen spec (all reasonable, listed as the canon requires):

1. `docs/README.md:10` drops "loop runner reference". The file is not in the spec's inline review scope list and no amendment names it. The edit is consistent with D4 (the USER_GUIDE no longer holds a runner reference).
2. `tests/skills/retired-loop-runner.Tests.ps1:77-81` adds a fourth case (an unknown switch) beyond the three named in TEST-3405. This is additive, and TEST-3405 requires at least 3.
3. `tests/skills/suite-map.yaml:973-974,1183-1184,1547-1548` map the prompt-diet ledger and suite to `aai-platform-adapter`, `aai-legacy-migrations` and `aai-pr-preflight` as well. The 10:07:24Z amendment covers this.
4. The cd-subshell baseline row, the hygiene-pack 126 to 127 pins and the companion TEST-012 pins are covered by the two recorded amendments. Owner sign-off on those amendments is still owed (validator NB6).

## Verdict 2: code_quality = pass

No BLOCKING findings.

### NB-1 (NON-BLOCKING, P2): stale wall-clock budget claim

- `.aai/system/AUTONOMOUS_LOOP.md:55` still says the run budget is enforced as "wall-clock on the runners".
- The retired `.sh` runner was the only place a wall-clock cap lived (`--max-run-seconds`, `main:.aai/scripts/autonomous-loop.sh:32,356-366`).
- A `git grep` over `.aai/` finds no other wall-clock run cap. Neither `unattended-gate.mjs`, SKILL_LOOP nor SKILL_SHIP has one.
- TEST-3407 does not catch this because the line does not name `autonomous-loop`.
- The CHANGELOG entry and D-PROPOSE declare only `--propose-only` as unported, so the loss of the wall-clock cap is not disclosed anywhere.
- Failure scenario: an operator plans an unattended overnight ride and trusts a wall-clock stop that nothing enforces any more.
- Recommended disposition: (a) remediate in tree.
  - Drop "wall-clock on the runners; " from line 55.
  - Add one clause to the CHANGELOG bullet on unported features: `--max-run-seconds` / `-MaxRunSeconds` is not ported either, and the run budget is now ticks plus in-session token/USD telemetry.
  - `.aai/system/*.md` is outside the TEST-010 prompt glob, so the edit carries no ledger cost. It needs a delta re-check only.
  - The fallback is (b), a typed follow-up `fu-loop-wall-clock-budget-doc` (P2).

### Carried from validation r3 (not re-ranked; dispositions are the orchestrator's)

- NB1-residual (`tests/skills/test-aai-retired-loop-runner.sh:277-279`): TEST-3410 compares a live byte count of two prompts. Recommended disposition: fold it into `fu-delete-retired-shell-loop-runner`, because the deleting release removes the suite. Otherwise (b).
- NB3: the RED logs lack `RED_CLASS`. Accepted residual per the validator; mutation replay 13/13 compensates.
- NB6: two amendments are still unsigned (`fu-amend-spec-retire-shell-loop-runner`, P2, open).
- NB7: "sources" is the wrong verb for TEST-3410 in the spec and in the decisions entry. This is wording only.

### INFO (no failure scenario; never gates)

- `tests/skills/test-aai-retired-loop-runner.sh:285-286` and `tests/skills/test-aai-legacy-migrations.sh:573-574`: `later` and `pin` are not declared `local`. They are harmless in a one-shot suite.
- `tests/skills/test-aai-retired-loop-runner.sh:309`: `aai-sync.sh` output goes to `/dev/null`. A failure reports only "failed" with no diagnostics.
- `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md:308`: the second-slice sentence "aai-run-tests and autonomous-loop are later slices" now sits in the same row as the sixth-slice sentence that retires autonomous-loop. It reads as history; D6 asked only for the added sentence.
- The `.sh` launcher keeps git mode 100644 as on main, so the old `./.aai/scripts/autonomous-loop.sh` invocation on a fresh clone gives "Permission denied" rather than the retirement line. This is not a regression: the old file had the same mode.

## cannot_verify

1. Windows PowerShell 5.1 and native-Windows pwsh 7 behaviour of the `.ps1` launcher and its Pester file. This closes with the hosted ps1-quality Windows jobs passing on the PR, with the file discovered and not skipped (H1).
2. Downstream consumers that call the runners from cron, CI or wrappers. The diff only proves that no shipped AAI path calls them. This closes only with cross-repo evidence; the CHANGELOG discloses the break.

## Warning dispositions (H6)

| Warning | Recommended disposition | Artifact the orchestrator records |
|---|---|---|
| NB-1 AUTONOMOUS_LOOP.md:55 stale wall-clock claim, undisclosed loss of --max-run-seconds | (a) remediate in tree; fallback (b) | the fixing commit, or follow-up `fu-loop-wall-clock-budget-doc` |
| carried NB1-residual TEST-3410 live byte pin | fold into `fu-delete-retired-shell-loop-runner`, or (b) | follow-up id |
| carried NB3 RED_CLASS | (d) as recorded by validation r3 | validation r3 report |
| carried NB6 unsigned amendments | (c) | `fu-amend-spec-retire-shell-loop-runner` |
| carried NB7 verb | (a) or (d) | — |

## Next steps

1. The orchestrator records the NB-1 disposition. If it chooses (a), it makes the two-line doc edit and runs a delta re-check.
2. PR, with H1 watched on the hosted Windows jobs.
3. Owner signs the two amendments (NB6).
