```yaml
review:
  scope: ".aai/scripts/mutation-run.mjs .aai/scripts/aai-run-tests.sh .aai/scripts/aai-run-tests.ps1 .aai/scripts/lib/git-bash-path.sh .aai/system/PROFILES.yaml tests/skills/test-aai-mutation-gate.sh tests/skills/test-aai-win-fallback.sh tests/skills/aai-win-dispatch.Tests.ps1 docs/issues/ISSUE-0088-mutation-clone-windows-run-chain.md docs/specs/SPEC-0195-spec-mutation-clone-windows-run-chain.md docs/ai/EVENTS.jsonl"
  spec: docs/specs/SPEC-0195-spec-mutation-clone-windows-run-chain.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/mutation-run.mjs:653-656 GIT_CLONE_PROTECTION_ACTIVE=false on the clone spawn only; TEST-007 exit 0, probe allowed" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/mutation-run.mjs:607-626 and :770 copy the two wrappers after the fidelity hash; TEST-008 exit 0 reaches the greeting mismatch" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/lib/git-bash-path.sh:10-58; .aai/scripts/aai-run-tests.sh:766-782; .aai/scripts/aai-run-tests.ps1:632-681; TEST-028 exit 0 PYOK; Pester ScriptArgs keep the Windows wrapper path" }
    deviations:
      - ".aai/system/PROFILES.yaml classifies the new vendored lib as core. The frozen inline scope did not name that inventory file. The 100% classification test requires it. No design decision changes."
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "A real Windows Git LFS checkout completes when clone protection would refuse the post-checkout hook.",
        closes_with: "A Windows host whose git still refuses an active post-checkout hook during git clone --local. TEST-007 is a PATH shim, because this environment's git does not enforce that refusal." }
    - { claim: "Git Bash on Windows executes the translated project Python path.",
        closes_with: "A Windows Git Bash run of the wrapper. TEST-028 forces AAI_UNAME=MSYS_NT on Linux and prefixes AAI_GIT_BASH_FS_ROOT. The Pester example mocks Start-GitBashProcess." }
  overall: pass
```

# Code review: mutation-clone-windows-run-chain

- Reviewer: sole agent, read-only on implementation files. `AAI_ROLE` unset.
- Spec: `docs/specs/SPEC-0195-spec-mutation-clone-windows-run-chain.md` (frozen, ceremony level 2, strategy direct).
- Worktree decision: inline. Scope is the path list above, plus the profile inventory the new lib requires.
- Overall: pass. No BLOCKING findings. No NON-BLOCKING findings.

## AC walk

| Spec-AC | Call | Citation |
|---------|------|----------|
| Spec-AC-01 | compliant | Clone spawn sets `GIT_CLONE_PROTECTION_ACTIVE=false` only on that `execFileSync`. TEST-007 refuses the clone unless the variable is false, then records RED. |
| Spec-AC-02 | compliant | After the fidelity hash matches, only `.aai/scripts/aai-run-tests.sh` and `.aai/scripts/aai-run-tests.ps1` are copied when missing. TEST-008 gitignores `.aai`, sees both files, and fails the greeting assertion inside the clone. |
| Spec-AC-03 | compliant | Path conversion is string-only in both directions. PowerShell translates command arguments and leaves the wrapper script path unchanged. The MSYS branch rewrites arguments and exports `BASH_ENV` so a child bash recovers a backslash path. TEST-028 prints `PYOK`. |

## Extra file

`.aai/system/PROFILES.yaml` lists `.aai/scripts/lib/git-bash-path.sh` under core, next to the other wrapper libs. Without that line the live-tree classification test exits 1. This does not change D1-D4.

## cannot_verify

Real Windows Git LFS clone protection, and a real Git Bash process, are not executed here. The shim, the `AAI_UNAME` seam, and the Pester mock cover the contracts those hosts would exercise.
