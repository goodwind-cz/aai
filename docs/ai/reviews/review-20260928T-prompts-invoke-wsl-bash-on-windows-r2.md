# Independent code re-review — prompts-invoke-wsl-bash-on-windows

```yaml
review:
  scope: "origin/main...HEAD plus the unstaged scoped implementation paths and untracked frozen spec"
  spec: docs/specs/SPEC-0191-spec-prompts-invoke-wsl-bash-on-windows.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/test-aai-win-fallback.sh:640-655; independent full-suite TEST-024 rerun exit 0" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/SKILL_TEST_SKILLS.prompt.md:8-22; .aai/VALIDATION.prompt.md:189-190; tests/skills/test-aai-win-fallback.sh:658-693; independent host-bash negative control exit 1 as expected" }
      - { ac: Spec-AC-03, call: compliant, citation: "tests/skills/test-aai-win-fallback.sh:670-678; listed prompt corpus sweep found every POSIX wrapper prefix paired with the Windows prefix" }
      - { ac: Spec-AC-04, call: compliant, citation: "tests/skills/test-aai-win-fallback.sh:769-775; independent full tests/skills/test-aai-win-fallback.sh rerun exit 0" }
      - { ac: Spec-AC-05, call: compliant, citation: "tests/skills/lib/prompt-diet-ledger.sh:220-221; independent TEST-010, TEST-012, and TEST-028 selector reruns exit 0" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Live Windows behavior when WSL CreateInstance is denied and Git Bash is available", closes_with: "A Windows-host run showing the PowerShell wrapper selects Git Bash and preserves the wrapped exit code; this wrapper behavior is explicitly outside the frozen spec." }
    - { claim: "NUL-free UTF-8 handling of WSL denial output", closes_with: "A Windows-host assertion over captured denial bytes; NUL sanitization is explicitly outside the frozen spec." }
  overall: pass
```

## Scope

Re-reviewed `origin/main...HEAD`, the unstaged implementation changes named by the frozen spec, `tests/skills/test-aai-prompt-diet.sh`, the append-only workflow records, and the untracked frozen spec. The implementation is inline and the caller supplied the branch, spec, prior findings, and exact report destination. The prior finding summary was used only as remediation context; the complete scope was re-read and both verdicts were decided independently.

## Acceptance-criteria walk

- **Spec-AC-01 — compliant.** TEST-024 still pins both canonical literals, the repository-root rule, and the direct-interpreter prohibition in `TECHNOLOGY.md`, `TECHNOLOGY_TEMPLATE.md`, and `AGENTS.md`. The independently rerun full Windows-fallback suite passed TEST-024.
- **Spec-AC-02 — compliant.** All eight listed prompt surfaces now contain the Windows wrapper prefix or the canonical-invocation pointer. The two prior escapes are closed: `SKILL_TEST_SKILLS` fences Windows usage and provides wrapper-pair examples, while the Validation c2 sweep presents the Windows and POSIX wrapper forms together. TEST-024 now rejects a `bash tests/...` instruction unless that same line is a canonical wrapper-prefix line. An adversarial injected host-bash line made TEST-024 exit 1 with the expected diagnostic.
- **Spec-AC-03 — compliant.** TEST-024 requires the Windows prefix whenever a listed prompt contains the POSIX prefix. A corpus search confirmed no listed prompt carries the POSIX prefix alone.
- **Spec-AC-04 — compliant.** The complete `test-aai-win-fallback.sh` suite independently exited 0 and executed TEST-024. TEST-027 remains registered and its replayed mutation reddened.
- **Spec-AC-05 — compliant.** Independent selector runs for TEST-010, TEST-012, and TEST-028 each exited 0. The prompt-diet ledger accounts for the original 802-byte scope and the 492-byte review remediation.

## Code-quality findings

No BLOCKING or NON-BLOCKING findings.

The direct-host-bash assertion is narrowly aligned with the defect: it examines each listed prompt line, rejects `bash tests/...`, and exempts only lines carrying one of the two canonical wrapper prefixes. The guard therefore no longer certifies either prior escape. The implementation remains bash-3.2 compatible.

## Test and evidence assessment

Independent re-review runs:

1. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-win-fallback.sh` — exit 0.
2. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh test_010_audit_and_reduction` — exit 0.
3. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh test_012_growth_sum_matches_ledger` — exit 0.
4. `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh test_028_windows_prompt_credit` — exit 0.
5. `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0191-spec-prompts-invoke-wsl-bash-on-windows.md` — exit 0; TEST-024, TEST-027, and TEST-028 reddened, 3/3.
6. Temporary host-bash negative control: append `bash tests/skills/test-framework.sh` to a listed prompt and run TEST-024 — exit 1 as expected, with the direct-host-bash diagnostic. The wrapper reported that this command shape could not be isolated, so the injected line was removed from the working file immediately after the run and the intended diff was rechecked.

## cannot_verify

The two Windows-host gaps in the structured block remain explicit and do not block this prompt-only scope. The frozen spec excludes wrapper fallback implementation and NUL sanitization.

## Warning dispositions

There are no NON-BLOCKING findings requiring disposition.

## Verdict

Both `spec_compliance` and `code_quality` pass. Overall review verdict: **PASS**.

## State update commands

```bash
node .aai/scripts/state.mjs set-code-review --required true --status pass --scope "origin/main...HEAD plus unstaged scoped implementation paths and untracked frozen spec" --base-ref origin/main --head-ref HEAD --report docs/ai/reviews/review-20260928T-prompts-invoke-wsl-bash-on-windows-r2.md --notes "Both verdicts pass; no findings or warnings. Windows-host fallback and denial-byte behavior remain out-of-scope cannot-verify items."
node .aai/scripts/state.mjs append-run --ref prompts-invoke-wsl-bash-on-windows --role "Code Review" --model gpt-5.6-sol --started 2026-09-28T19:31:00Z --harness cursor --tokens-total 0 --verdict pass --note "Independent remediation re-review PASS; report docs/ai/reviews/review-20260928T-prompts-invoke-wsl-bash-on-windows-r2.md"
```
