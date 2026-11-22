# Code review: installer-l3-protected (round 1)

```yaml
review:
  scope: "git diff 077ee649..97b53e25 (branch chore/installer-l3-protected)"
  spec: docs/specs/SPEC-0309-spec-installer-l3-protected.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "docs/ai/docs-audit.yaml:93-99, .aai/templates/docs-audit.template.yaml:67-73; TEST-4001 PASS" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "select-suites.mjs parseProtectedPathsL3 on the real list; TEST-4000 (tests/skills/test-aai-suite-select.sh:1189-1201)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/workflow/WORKFLOW.md:77-81; TEST-4002 PASS" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-hook-installer-node.sh, line: 818,
          issue: "Three existing wiring tests assert that installer/template paths SELECT a named suite; on the new list the selector prints only FULL_RUN reason=protected-l3 for them, so TEST-3997, TEST-3443 and TEST-3571 now fail",
          failure_scenario: "CI full run of this PR (FULL_RUN because WORKFLOW.md is protected) runs aai-hook-installer-node, aai-git-hook-templates and aai-install-parity; each exits 1. Reproduced locally: test-aai-hook-installer-node.sh test_3997_wiring rc=1 (rc=0 on a git-archive of 077ee649), test-aai-git-hook-templates.sh test_3443_wiring rc=1, test-aai-install-parity.sh test_3571_wiring rc=1" }
      - { rank: NON-BLOCKING, file: docs/ai/docs-audit.yaml, line: 93,
          issue: ".aai/scripts/lib/guard-config.mjs (imported by install-pre-commit-hook.mjs for readRefGuardPolicy/writeRefGuardPolicy, and by state.mjs, allocate-doc-number.mjs and pre-commit-checks.sh) is not on the L3 list, unlike the state engine's libs state-engine.mjs/state-core.mjs",
          failure_scenario: "A PR editing only guard-config.mjs (e.g. how ref_guard is parsed or written) changes whether every install arms the ref guard, yet may freeze at L2 with no mandatory top-tier review; the selector (shared-lib FULL_RUN) and the recheck (production_path) still catch it, so the bite is the ceremony tier only" }
  cannot_verify:
    - { claim: "Downstream projects that hand-add the seven lines get the same selector/recheck behaviour",
        closes_with: "a scratch aai-sync install with the lines added, running select-suites on one of the paths" }
    - { claim: "No suite beyond the three named above asserts a non-FULL_RUN selection for one of the seven paths",
        closes_with: "the full sweep (not run by this reviewer by instruction) or CI on the PR" }
  overall: fail
```

security_relevant: false

## Scope and spec

Scope: `git diff 077ee649..97b53e25` in the worktree
/Users/ales/Projects/aai-worktrees/installer-l3-protected (two commits:
b8eb7e92 intake + spec, 97b53e25 the change). Spec: the frozen
docs/specs/SPEC-0309-spec-installer-l3-protected.md. Dispatch-prompt
note: the orchestrator asked specific questions (seven-path completeness,
consumer consistency, bash 3.2 soundness, CHANGELOG wording); these were
treated as questions, not as scope limits, and the full diff was reviewed.

## AC table walk (spec_compliance: pass)

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | both lists carry the seven entries, same order, between hook-gate.mjs and WORKFLOW.md (D3); TEST-4001 rc=0 here; sync-seed TEST-006 equality pin per validation r1 |
| Spec-AC-02 | compliant | TEST-4000 loops all seven through `real_select`; manual selector run prints `FULL_RUN reason=protected-l3 path=<p>` |
| Spec-AC-03 | compliant | WORKFLOW.md bullet `- hook installer:` names the three files and `.aai/templates/git-hooks/`; TEST-4002 rc=0 |

TEST-xxx: TEST-4000/4001/4002 exist and are wired into `main()`; RED logs
and mutation replay are on file (docs/ai/tdd/installer-l3-protected/,
validation r1). Deviation from the frozen spec: D5 says "Nothing else
changes" and lists the consumers checked; it missed the three suites that
pin the selector's output for these paths (finding B1). The implementation
matches the spec; the spec's consumer inventory is incomplete, so the fix
needs a spec amendment (additive, with disclosure) that adds those three
test files to the scope.

## Findings (code_quality: fail)

### B1 BLOCKING: three existing wiring tests go red

- tests/skills/test-aai-hook-installer-node.sh:814-820 (TEST-3997) expects
  `^SELECTED aai-hook-installer-node ` for install-pre-commit-hook.mjs,
  .ps1 and .sh.
- tests/skills/test-aai-git-hook-templates.sh:551-560 (TEST-3443) expects
  `SELECTED aai-git-hook-templates` for the four templates and the two
  launchers, and `SELECTED|CORE <helper suites>` for pre-push.sh.
- tests/skills/test-aai-install-parity.sh:432-437 (TEST-3571) expects
  `SELECTED aai-install-parity` for install-pre-commit-hook.sh and .ps1.

backed-by: `env -u AAI_ROLE -u AAI_GIT_WRITE bash tests/skills/<suite>.sh
<test fn>` gives rc=1 for each at 97b53e25, e.g. `FAIL: TEST-3997:
select-suites does not route .aai/scripts/install-pre-commit-hook.mjs to
aai-hook-installer-node`; the same TEST-3997 call on a `git archive
077ee649` tree gives rc=0. The selector at HEAD prints only
`FULL_RUN reason=protected-l3 path=...` for these paths (no SELECTED
lines). The implementer's green set (8 suites) and validation r1 did not
run these three suites.

Fix, following the precedent already in tests/skills/test-aai-pre-commit-checks.sh:423-428
(TEST-3458, after pre-commit-checks.sh/.ps1 became protected): in each
test, split the seven protected paths out of the SELECTED loop and assert
`FULL_RUN reason=protected-l3` for them; keep the SELECTED assertion for
the non-protected paths (fixtures, helpers, Tests.ps1). TEST-3443's
helper-suite loop over pre-push.sh needs the same split. Add the three
files to the spec scope via amendment.

### NB1 NON-BLOCKING: lib/guard-config.mjs is not on the list

install-pre-commit-hook.mjs:17 imports readRefGuardPolicy and
writeRefGuardPolicy from ./lib/guard-config.mjs; the module decides
from it whether the ref guard is installed and writes the policy line. The
list's own precedent includes the state engine's libraries. Failure
scenario as in the YAML. Out of scope for this frozen spec: guard-config.mjs is
also imported by state.mjs, allocate-doc-number.mjs and pre-commit-checks.sh,
which are already L3, so the gap predates this change and covers more than
the installer, and widening the list to a shared lib is an owner policy
call. Recommended disposition: (b) promote to a typed follow-up, for example
`fu-guard-config-not-l3-protected`, P3.

### INFO

- .aai/templates/SPEC_TEMPLATE.md:36 still enumerates "(state engine,
  allocator, guards, workflow canon by default)", which was already stale
  (hook gate missing) and now also leaves out the installer. It points at the list,
  so nothing breaks; it can be tidied whenever someone next edits the template.
- Tests under `set -euo pipefail` on bash 3.2: sound. No arrays, no
  `printf | grep -q`; the unquoted `$INSTALLER_L3_PATHS` is a deliberate
  word split of a fixed constant; `assert_payload_contains` calls log_fail
  (exit 1) on a miss; `$(awk ...)` is fine under pipefail. TEST-4001's
  `import(root + "/...")` uses a bare path rather than pathToFileURL, the
  same as the existing TEST-009 two functions below, so it is no new
  portability risk. TEST-4000 reassigns TEST_DIR like the other 54 cases in
  that suite, and the runner removes the temp root it creates.
- CHANGELOG wording: accurate. The selector does FULL_RUN, recheck
  adds `protected_path:` (these paths were already refused as production
  paths, so "refuses a slim round" is true and was already true), and only
  new installs get the seed. Telling existing projects to add the seven
  paths by hand is correct, because nothing merges vendored defaults into a
  project-owned docs-audit.yaml (no other reader of the key exists in .aai/).
- Seven-path set: correct and complete for what the installer writes
  (TEMPLATE_FILES at install-pre-commit-hook.mjs:223 names exactly the four
  files in .aai/templates/git-hooks/). The two launchers only exec the
  module. The JSON files under .aai/templates/hooks/ are rightly left off
  (D1). The scripts the hook bodies call at run time (pre-commit-checks.sh
  is already L3; docs-audit.mjs, generate-docs-index.mjs and
  close-reconcile.mjs are not) are a separate policy question and do not
  count against this scope. The exact-path entries agree between the
  selector (exact match) and recheck `protectedMatch` (exact or dir prefix).
- Consumers: select-suites.mjs and lib/recheck.mjs (through loadConfig)
  read the list live; merge-policy.mjs names docs-audit.yaml only as a
  guarded config file; hitl-channel.mjs, nothing-left-behind.mjs and
  docs-model.mjs mention it only in comments. They are consistent. The
  inconsistency is in the tests (B1).

## cannot_verify

1. Downstream behaviour after a project hand-adds the lines. Closes with a
   scratch aai-sync install.
2. Whether any suite other than the three named pins a non-FULL_RUN
   selection for these paths. I found the three by grepping for selector
   calls next to the seven paths, but I did not run the full sweep (by
   instruction). Closes with the full sweep or CI.

## Warning dispositions (H6)

- NB1: recommended (b), a typed follow-up `fu-guard-config-not-l3-protected`
  (P3). The orchestrator records it.

## Local evidence

- test-aai-ceremony-levels.sh: rc=0 (TEST-4001, TEST-4002 PASS).
- test-aai-sync-seed.sh and test-aai-suite-select.sh were started and then
  stopped before they finished, so the checkout is free for the next role.
  Their green runs are on file in validation r1.
- test_3997_wiring rc=1 at HEAD, rc=0 at 077ee649; test_3443_wiring rc=1;
  test_3571_wiring rc=1.

## Next steps

Remediate B1 (amend the spec to add the three test files to its scope,
update TEST-3997, TEST-3443 and TEST-3571 to the protected-l3 split, then
run those three suites plus the spec's verification suites), record the NB1
follow-up, and re-review.
