# Code review: node-first-leftovers (delta round, single dual-verdict pass)

```yaml
review:
  scope: "delta 06ceb099..HEAD, read inside origin/main...HEAD of chore/node-first-leftovers (head 35a5854f, base 492f8b26)"
  spec: docs/specs/SPEC-0312-spec-node-first-leftovers.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/cloudflare-share.mjs unchanged since 06ceb099 (gapped pass, GAP_SLACK = 2); TEST-4049; covered by the full sweep at ed75833f (run test-20261124-222835)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/aai-update.mjs:66-129 (BOOL_WORDS, colon split and join; isOption:75-79 now knows the colon forms); TEST-4050 tests/skills/lib/aai-update.test.mjs:595-615 incl. the two NB-A asserts; aai-update-node suite PASS run test-20261124-225632" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/aai-update.ps1 unchanged since 06ceb099; TEST-4051 in tests/skills/test-aai-update-node.sh, PASS in run test-20261124-225632" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/aai-sync.mjs unchanged since 06ceb099; TEST-4052; full sweep at ed75833f" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/aai-sync.ps1:12 unchanged; TEST-4053 (pwsh 7 in the full sweep); 5.1 GREEN on hosted run 45477504577 per the round-1 validation (5.1 RED not observed, see cannot_verify)" }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/scripts/aai-sync.mjs writeFd loop unchanged; TEST-4054; full sweep at ed75833f" }
      - { ac: Spec-AC-07, call: compliant,
          citation: ".aai/scripts/lib/guard-config.mjs unchanged since 06ceb099; TEST-4055, aai-pre-commit-checks PASS run test-20261124-225933" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "shell mirrors unchanged; TEST-4056, aai-pre-commit-checks PASS run test-20261124-225933; TEST-3454 text now reads 243/40 (tests/skills/test-aai-pre-commit-checks.sh:237-240)" }
      - { ac: Spec-AC-09, call: compliant,
          citation: "guard-config.mjs winnerLine and install-pre-commit-hook.mjs unchanged; TEST-4057; full sweep at ed75833f" }
      - { ac: Spec-AC-10, call: compliant,
          citation: "tests/skills/lib/install-pre-commit-hook.test.mjs SOCK_BASE unchanged; TEST-4058; full sweep at ed75833f" }
      - { ac: Spec-AC-11, call: compliant,
          citation: "SPEC-0308 DR-20 cell, CHANGELOG.md and the contract amendments unchanged since 06ceb099; TEST-4059; spec-amend list --strict 0 per round-2 validation" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/guard-config.mjs, line: 300,
          issue: "carried from the 06ceb099 review (NB-B): winnerLine names line 1 as 'the first one with a value' when no ref_guard line has a value",
          failure_scenario: "docs-audit.yaml 'ref_guard:\\nb: 1\\nref_guard:\\n' -> the installer warns '(lines 1, 3); the first one with a value wins (line 1)' while readRefGuardPolicy takes no line. Disposition already recorded: follow-up fu-doubled-key-warning-no-valued-line (decisions.jsonl, 2026-11-24T22:11:47Z)" }
      - { rank: NON-BLOCKING, file: tests/skills/lib/install-pre-commit-hook.test.mjs, line: 1880,
          issue: "carried from the 06ceb099 review (NB-D): mkdtempSync under a hard-coded /tmp sits outside the try",
          failure_scenario: "a POSIX host without a writable /tmp fails the TEST-3987 classify case with EACCES or ENOENT. Disposition: accepted residual, see the report body" }
  cannot_verify:
    - { claim: "Spec-AC-05 under Windows PowerShell 5.1: the unfixed launcher actually breaks the trailing backslash (the RED)",
        closes_with: "one hosted ps1-quality workflow_dispatch on a branch with the D-PS51 line removed, showing the Pester case red (round-1 validation NB-5)" }
    - { claim: "the D-PS51 line in aai-update.ps1 behaves like the tested aai-sync.ps1 copy under 5.1",
        closes_with: "a case driving aai-update.ps1 through powershell.exe on the hosted leg (filed: fu-update-ps1-backslash-line-untested)" }
    - { claim: "the BOM-tolerant greps behave the same under GNU grep (Ubuntu CI, Git for Windows) as under BSD grep here",
        closes_with: "the skill-suite run on the pull request head (TEST-4056, hygiene test_031)" }
  overall: pass
```

security_relevant: true

## Scope and inputs

- Scope: the delta `git diff 06ceb099..HEAD` (3 commits: 441e9bf1, ed75833f, 35a5854f), read in the context of the whole diff `git diff origin/main...HEAD` (33 files). Worktree /Users/ales/Projects/aai-worktrees/node-first-leftovers, HEAD 35a5854f, base 492f8b26.
- Spec: docs/specs/SPEC-0312-spec-node-first-leftovers.md (frozen, ceremony_level 3). It has not changed since 06ceb099.
- Prior record: docs/ai/reviews/review-node-first-leftovers-20261124T2156Z.md (PASS at 06ceb099). Read, not relied on: docs/ai/reports/VALIDATION-20261124T2212Z-node-first-leftovers.md (round 2, PASS at ed75833f).
- Dispatch note (anti-gaming rule): the dispatch named the content of the delta (the NB-A fix, the NB-C text, ledger lines). It did not pre-rate severity or exclude an area. The whole diff was still read for context.
- Preflight: STATE has `worktree.user_decision: worktree` and `base_ref: origin/main`. `git status --porcelain` was clean before the review. Only the two suite-run lines that the framework appends to docs/ai/tests/test-runs.jsonl were added during the review (see Probes).

## What the delta changes

- `.aai/scripts/aai-update.mjs:72-79`: `isOption` now cuts a single-dash word at its first `:` and a double-dash word at its first `=`. A known flag in colon form (`-DryRun:true`, `-Ref:x`, `-Force:`) therefore counts as an option. After a value flag it is a missing value (outcome `value`), and it is never read as the value. The comment now names the colon forms. Both call sites (line 100, the 5.1 split-form join, and line 117, the value check) get the fix.
- `tests/skills/lib/aai-update.test.mjs:612-614`: two TEST-4050 asserts (`-Ref -DryRun:true` gives `value arg=-Ref`, and `-Repo: -Force:false` gives `value`).
- `tests/skills/test-aai-pre-commit-checks.sh:237-240`: the TEST-3454 provenance comment gains `+1 -1 from node-first-leftovers (D-BOM ...)`, and the pass text reads 243/40. The pin (`243 40`) is unchanged. The comment chain sums to 243 added and 40 removed lines.
- Ledgers: 6 EVENTS lines (two full_sweep, check verdicts, evidence_digest), 4 decisions.jsonl follow_up records (fu-doubled-key-warning-no-valued-line, fu-docs-audit-config-bom-close-gate, fu-mutation-replay-skip-reads-green, fu-update-ps1-backslash-line-untested), 16 test-runs lines, and the prior review report.

No spec, intake or other shipped-script byte changed in the delta (`git diff --stat 06ceb099..HEAD -- docs/specs .aai/scripts` lists only aai-update.mjs).

## AC table walk

All eleven rows are compliant (see the YAML block). The only row whose code moved is Spec-AC-02. Its five frozen forms still give the frozen results, because the NB-A fix changes only words that follow a value flag and no Spec-AC-02 form puts a flag there. The TEST-4050 mutation `s/\$true/$maybe/` still applies at HEAD; the round-2 validation replayed 11/11 mutations red. Deviations from the frozen spec are the same three disclosed amendments listed in the 06ceb099 review. The delta adds none.

## Probes run by the reviewer

| Probe | Result |
|---|---|
| probe.mjs (17 argv shapes) against HEAD and against a scratch copy of the module with the pre-fix isOption line (cr-b2/mut/) | HEAD: every known flag in colon form after `-Repo`, `-Ref`, `--repo` or `-Repo:` gives `value`; `-Repo C:\path`, `-Repo: C:\path`, `-Ref -:`, `-Repo -x:y` still take the value; `-Repo:x -DryRun:false -Force:$true` gives repo x, force true. Pre-fix copy: `-Ref -DryRun:true` gives ref `-DryRun:true`, outcome run (the NB-A defect). So the two new asserts redden on the pre-fix module |
| `node --test --test-name-pattern TEST-4050 tests/skills/lib/aai-update.test.mjs` | pass 1, fail 0 |
| aai-run-tests.sh test-framework.sh --skill aai-update-node (fresh XDG_CACHE_HOME, env -u AAI_ROLE) | rc 0, run test-20261124-225632, framework tripwire 1/1 attested clean |
| the same for aai-pre-commit-checks | rc 0, run test-20261124-225933, framework tripwire 1/1 attested clean |
| Byte-prefix check of EVENTS.jsonl, decisions.jsonl and tests/test-runs.jsonl at HEAD against 06ceb099 and origin/main (Node Buffer compare) | prefix OK for all six pairs |

The wrapper printed `AAI-TRIPWIRE FAIL ... M docs/ai/tests/test-runs.jsonl` after the first suite. This is the documented report-only wrapper note (aai-run-tests.sh:172-180): the canonical invocation appends its run record to that file. The framework tripwire, the one that fails runs, attested the suite clean. This report was written after both suites had exited.

The probe scripts live in the session scratch directory /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/cr-b2 (probe.mjs, mut/). They were not added to the tree.

## Findings

No BLOCKING finding.

Status of the 06ceb099 review's NON-BLOCKING items at HEAD:

- NB-A (`aai-update.mjs` isOption colon forms): remediated in tree in 441e9bf1 with RED-proven asserts (see Probes). Closed.
- NB-B (`guard-config.mjs:300` winnerLine with no valued line): still present. It is promoted to follow-up fu-doubled-key-warning-no-valued-line (P3, decisions.jsonl). Recorded.
- NB-C (`test-aai-pre-commit-checks.sh` TEST-3454 text and comment chain): remediated in tree. The text reads 243/40 and the chain sums to the pin. Closed.
- NB-D (`install-pre-commit-hook.test.mjs:1880` mkdtemp on /tmp outside the try): accepted residual: the spec froze `/tmp` for SOCK_BASE; every supported dev host and CI runner has a writable /tmp; no observed bite and no false record left anywhere (P3 assurance-strength).

New in the delta: none.

INFO (not gating):

- `isOption` still treats `--dry-run:true`, `-h:x` and `--help:x` as values. parseArgs does not accept those words as flags on their own either, so this matches the parser grammar. A value like that goes to git as a ref or repo and fails there. (The round-2 validation listed the same thing as NB-R2-2, P4.)
- The CHANGELOG line "a valueless first line is not the winner" is true for the tested shape. The no-valued-line shape is the filed NB-B follow-up.
- The round-2 validation follow-ups fu-mutation-replay-skip-reads-green and fu-update-ps1-backslash-line-untested are filed. Round-1 NB-5 (no observed hosted 5.1 RED) remains a cannot_verify item.

## Warning dispositions (H6)

| Finding | Disposition |
|---|---|
| NB-A | remediated in tree (441e9bf1, TEST-4050 asserts at aai-update.test.mjs:612-614) |
| NB-B | follow-up fu-doubled-key-warning-no-valued-line (P3), filed in decisions.jsonl |
| NB-C | remediated in tree (441e9bf1) |
| NB-D | accepted residual: the spec froze /tmp; all supported hosts have a writable /tmp; no observed bite and no false record |

## Next steps

1. Orchestrator: record this review (set-code-review pass) and decide what to do with the two test-runs.jsonl lines these suite runs appended (they are canonical run records, as in the prior round).
2. The full sweep at ed75833f still covers HEAD, because 35a5854f changes ledgers only.
3. PR, then the owner merges (L3). The sibling PR that lands second re-pins TEST-308.
