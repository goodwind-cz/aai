# Code review: release-tagged-by-ci-after-merge

- Reviewer: Autonomous Code Reviewer (Single Dual-Verdict Review)
- Scope: `debt/release-tagged-by-ci-after-merge` on branch `debt/release-tagged-by-ci-after-merge`
- Spec: `docs/specs/SPEC-0228-spec-release-tagged-by-ci-after-merge.md`
- Files:
  - `.github/workflows/release.yml`
  - `.aai/scripts/aai-release.sh`
  - `.aai/scripts/aai-release.ps1`
  - `.aai/SKILL_RELEASE.prompt.md`
  - `tests/skills/test-aai-release.sh`
  - `tests/skills/aai-win-dispatch.Tests.ps1`
  - `docs/specs/SPEC-0228-spec-release-tagged-by-ci-after-merge.md`
  - `docs/issues/DEBT-0015-release-tagged-by-ci-after-merge.md`

```yaml
review:
  scope: debt/release-tagged-by-ci-after-merge
  spec: docs/specs/SPEC-0228-spec-release-tagged-by-ci-after-merge.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/aai-release.sh: temporary worktree cut builds chore(release): $VERSION, opens PR via gh pr create, leaves caller byte-identical; TEST-003, TEST-009, TEST-027..029 pass" }
      - { ac: Spec-AC-02, call: compliant, citation: ".github/workflows/release.yml: pushes to main trigger release job on chore(release): <version>, create annotated tag, push tag, extract CHANGELOG notes, publish via gh release create idempotently; TEST-030 pass" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/aai-release.sh: direct push, is_protected_branch_rejection, local tag, pre-cut reset, exits 17/18 eliminated; TEST-005, TEST-032 pass" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/aai-release.sh: golden_flow_record_gap and release-time warnings eliminated; TEST-036 pass" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/aai-release.sh: unlogged_prs regex recognizes house link styles (#123, (#123), owner/repo#123); TEST-031 pass" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/aai-release.ps1: full PowerShell parity for worktree cut, PR opening, and exit 17/18 removal; TEST-019, TEST-033, aai-win-dispatch.Tests.ps1 pass" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/SKILL_RELEASE.prompt.md: documents active exit codes (10, 11, 12, 13, 15, 16) and PR release model; prompt diet passes; TEST-034 pass" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Live GitHub pull request merge command execution", closes_with: "Operator manual execution of the printed merge command" }
  overall: pass
```

## Spec compliance
All seven acceptance criteria are satisfied cleanly according to SPEC-0228. The release process is transformed from an error-prone direct push fallback to a first-class PR-based model with CI tag-and-publish automation on merge.

## Code quality
The implementation eliminates complex fallback and recovery code paths (exits 17 and 18, protected branch classifiers, working tree reset logic), leaving the caller checkout untouched regardless of its state. Test coverage is comprehensive across Bash and PowerShell.

Overall verdict: **PASS**
