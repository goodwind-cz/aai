# Independent code review — prompts-invoke-wsl-bash-on-windows

```yaml
review:
  scope: "origin/main...HEAD plus all unstaged and untracked changes"
  spec: docs/specs/SPEC-0191-spec-prompts-invoke-wsl-bash-on-windows.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/test-aai-win-fallback.sh:642-655; TEST-024 rerun exit 0" }
      - { ac: Spec-AC-02, call: non-compliant, citation: ".aai/SKILL_TEST_SKILLS.prompt.md:10-13 and .aai/VALIDATION.prompt.md:189 still direct agents to run bash tests; TEST-024 scans only aai-run-tests wrapper mentions" }
      - { ac: Spec-AC-03, call: compliant, citation: "tests/skills/test-aai-win-fallback.sh:669-677; every listed POSIX wrapper prefix has the Windows .ps1 prefix" }
      - { ac: Spec-AC-04, call: compliant, citation: "full tests/skills/test-aai-win-fallback.sh independent rerun exit 0; TEST-027 mutation record RED" }
      - { ac: Spec-AC-05, call: compliant, citation: "independent TEST-010, TEST-012 and TEST-028 selector reruns exit 0; TEST-028 mutation record RED" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/SKILL_TEST_SKILLS.prompt.md, line: 10, issue: "The Windows-facing skill still presents direct bash test commands before the new platform-specific wrapper guidance.", failure_scenario: "On the reported Windows configuration, an agent follows the primary all-skills example `bash tests/skills/test-framework.sh`; host command resolution selects the blocked WSL bash shim and fails with E_ACCESSDENIED before the test framework runs." }
      - { rank: BLOCKING, file: tests/skills/test-aai-win-fallback.sh, line: 637, issue: "TEST-024 claims the listed prompts are Windows-safe while checking only canonical aai-run-tests wrapper mentions, so the universal safety claim omits direct bash test commands.", failure_scenario: "The direct bash examples at SKILL_TEST_SKILLS.prompt.md:10-13 or VALIDATION.prompt.md:189 remain unchanged and TEST-024 still passes; the regression guard therefore certifies the exact Windows failure mode as safe." }
  cannot_verify:
    - { claim: "Live Windows behavior when WSL CreateInstance is denied and Git Bash is available", closes_with: "A Windows-host run showing direct bash fails and the PowerShell wrapper selects Git Bash and preserves the wrapped exit code." }
    - { claim: "NUL-free UTF-8 handling of WSL denial output", closes_with: "A Windows-host assertion over captured denial bytes; the frozen spec explicitly leaves wrapper NUL sanitization out of scope." }
  overall: fail
```

## Scope

Reviewed `origin/main...HEAD`, all unstaged tracked changes, and the untracked frozen spec. The effective implementation scope includes the eight prompt/document surfaces, `tests/skills/test-aai-win-fallback.sh`, `tests/skills/test-aai-prompt-diet.sh`, `tests/skills/lib/prompt-diet-ledger.sh`, the intake/spec documents, generated index, and append-only event/decision additions. No coaching attempt or pre-rated finding was supplied.

## Acceptance-criteria walk

- **Spec-AC-01 — compliant.** The guidance trio pin remains intact. The independently rerun TEST-024 passed.
- **Spec-AC-02 — non-compliant.** The changed test describes its contract as “listed skill prompts are Windows-safe,” but `.aai/SKILL_TEST_SKILLS.prompt.md:10-13` still leads with four direct `bash tests/skills/test-framework.sh` commands. `.aai/VALIDATION.prompt.md:189` also retains a direct bash test invocation. The guard only scans occurrences of `.aai/scripts/aai-run-tests.sh`, so these Windows-unsafe instructions are invisible. This defeats the frozen spec's title and the AC's stated Windows-safe prompt contract.
- **Spec-AC-03 — compliant.** Every listed prompt that names the POSIX process-group wrapper also names the Windows PowerShell wrapper in the same file.
- **Spec-AC-04 — compliant.** The complete Windows-fallback suite independently exited 0 and executed TEST-024. The TEST-027 mutation record proves removal of 024 from `ALL_TESTS` is detected.
- **Spec-AC-05 — compliant.** Independent selector runs for TEST-010, TEST-012, and TEST-028 each exited 0. The ledger credit is measured at 802 bytes and the TEST-028 mutation record proves the new credit pin bites.

## Blocking findings

### B1 — direct bash remains the primary test-skills instruction

`.aai/SKILL_TEST_SKILLS.prompt.md:10-13` presents direct host `bash` commands as the first executable instructions. The new text only says to prefer the platform wrapper “when running under a loop/orchestrator.” A Windows agent running the skill directly can therefore follow the first examples, resolve `bash` to the blocked WSL shim, and reproduce the intake's `E_ACCESSDENIED` failure before any test runs. `.aai/VALIDATION.prompt.md:189` retains the same direct-command shape.

Remediate in tree: make every test-running instruction in the listed prompts platform-aware and route it through the canonical wrapper pair, not only references to `aai-run-tests.sh`.

### B2 — TEST-024 overclaims a universal safety property

`tests/skills/test-aai-win-fallback.sh:637` and its success message call the listed prompts Windows-safe, while the assertions at lines 669-677 inspect only the two canonical wrapper literals and bare `.aai/scripts/aai-run-tests.sh` residue. Direct `bash <test>` commands are outside the asserted corpus. This is the review policy's prohibited shape: a test names a universal negative/safety property while proving only a subset.

Remediate in tree: add a corpus assertion that rejects direct host `bash`, `bash.exe`, `sh`, or `wsl` test invocations in the listed prompts, with narrowly documented exclusions for non-test tooling if required. Preserve a positive control or mutation proving a direct `bash tests/...` instruction makes TEST-024 fail.

## Test and evidence assessment

Independent review reruns:

1. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-win-fallback.sh` — exit 0; full suite and TEST-024 passed.
2. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh test_010_audit_and_reduction` — exit 0.
3. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh test_012_growth_sum_matches_ledger` — exit 0.
4. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh test_028_windows_prompt_credit` — exit 0.

The three mutation records are well-formed and RED for TEST-024, TEST-027, and TEST-028. Their passing mutation gate does not cover B1: TEST-024's mutation changes the PowerShell wrapper literal, not a remaining direct bash test instruction.

## cannot_verify

The two gaps in the structured block are explicit. They do not create the FAIL verdict; B1/B2 do. The frozen spec marks wrapper WSL-denial and NUL sanitization as out of scope, so this review does not infer those Windows-host properties from Linux prompt tests.

## Warning dispositions

There are no NON-BLOCKING findings requiring a warning disposition.

## Next step

Remediate B1 and strengthen TEST-024 for B2 with failing-first evidence, rerun the Windows-fallback and prompt-diet acceptance tests plus the mutation gate, then re-review. Both independent verdicts and the overall verdict are **FAIL**.
