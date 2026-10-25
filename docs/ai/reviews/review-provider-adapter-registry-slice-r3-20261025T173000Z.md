```yaml
review:
  scope: 15359acf..79a0f2e4 (worktree /private/tmp/aai-adapter-slice, branch change/provider-adapter-registry-slice, PR #502), round 3
  spec: docs/specs/SPEC-0253-spec-provider-adapter-registry-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "untouched by delta; r2 PASS; TEST-3001 PASS this round" }
      - { ac: Spec-AC-02, call: compliant, citation: "untouched by delta; TEST-3002 PASS this round" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/lib/harness-shims.mjs:145-174 assertRealPath + loadShims; TEST-3003/3004/3015 PASS; reviewer probes for shipped-list, parent-not-dir, leaf-not-file arms all exit 2 before any write" }
      - { ac: Spec-AC-04, call: compliant, citation: "hygiene-pack PASS (test_111); TEST-3005 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "untouched by delta; TEST-3007/3008/3009 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "untouched by delta; TEST-3010/3011 PASS in suite run" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-3012/3013 PASS; spec-amend list --strict rc=0" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3014 PASS (line cap 260 holds: lib is 235 lines)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/product/provider-adapter-registry.md, line: 49,
          issue: "Doc says the generator 'never writes through a link out of the project'; the guard checks symbolic links only. A hard link passes lstat isFile() and writeFileSync truncates the shared inode.",
          failure_scenario: "ln /outside/victim <root>/CLAUDE.md; sync-harness-skills.mjs --write --root <root> exits 0 and /outside/victim now holds the CLAUDE.md shim (reviewer probe 8). Git cannot commit a hard link, so this is not the Codex threat model, but the sentence promises more than the guard compares." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-harness-shims.sh, line: 394,
          issue: "TEST-3015 exercises only two of the five refusal arms the amended Spec-AC-03 names (symlinked leaf, symlinked parent). The shipped-list, parent-not-a-directory and leaf-not-a-regular-file arms have no test.",
          failure_scenario: "Deleting `assertRealPath(root, SHIPPED_LIST_REL);` (harness-shims.mjs:173) leaves the whole suite green, and a symlinked .aai/system/COPILOT_SHIM_SHIPPED.list would then be appended through on --write (appendFileSync at :230)." }
  cannot_verify:
    - { claim: "Windows junctions refuse like symlinks (Node lstat reports a junction as isSymbolicLink)", closes_with: "TEST-3015 equivalent run on a Windows host with mklink /J .cursor" }
    - { claim: "TEST-3015 passes on Linux CI (ln -s / ls -A semantics)", closes_with: "green PR #502 CI run at head 79a0f2e4 or later" }
    - { claim: "No regression outside the selected suites", closes_with: "select-suites reports FULL_RUN reason=shared-lib for lib/harness-shims.mjs; only harness-shims + CORE (hygiene-pack, check-state, docs-audit, spec-lint) were run this round; the r2 full sweep (114/114) predates the delta. lib/harness-shims.mjs is imported only by sync-harness-skills.mjs and the harness-shims suite (grep), so the residual is low; PR CI or one full sweep closes it." }
  overall: pass
```

security_relevant: true

# Code Review — provider-adapter-registry-slice, round 3

- Scope: delta `15359acf..79a0f2e4` (commits 8b5c9429 close ceremony, 79a0f2e4 Codex P1 fix). Worktree read-only; clean `git status` before and after.
- Spec: `docs/specs/SPEC-0253-spec-provider-adapter-registry-slice.md` (frozen, amended Spec-AC-03 + TEST-3015 row).
- Dispatch-coaching check: the dispatch listed candidate bypasses to examine (symlinked HARNESS_SHIMS.md, root symlink, TOCTOU, --check exit 2, junctions). It did not pre-rate severity or exclude areas; recorded here, and the full delta was reviewed anyway.

## Evidence run this round

| Command | rc |
|---|---|
| `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-harness-shims.sh` | 0 (TEST-3001..3015 all PASS) |
| same for test-aai-hygiene-pack.sh, test-aai-check-state.sh, test-aai-docs-audit.sh, test-aai-spec-lint.sh | 0 each |
| `node .aai/scripts/spec-amend.mjs list --strict` | 0 (3 contract amendments unsigned-tracked by `fu-amend-provider-adapter-registry-slice`, open) |
| `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0253-...md` | GATE PASS: 15 rows, degraded=0 |
| `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0253-...md` | LINT PASS |
| `node .aai/scripts/select-suites.mjs --base-ref 15359acf` | FULL_RUN reason=shared-lib |

Logs: /private/tmp/claude-501/-Users-ales-Projects-aai/84834df3-26b2-4169-98af-6a142178eee5/scratchpad/pa-cr-r3/*.log

## The P1 fix: bypass probes (scratch copy from `git archive HEAD`)

| # | Setup | Result |
|---|---|---|
| 1 | shipped list is a symlink to an outside file | `--write` rc=2 "…COPILOT_SHIM_SHIPPED.list is a symlink" |
| 2 | `.aai/system` dir is a symlink (fragments + list) | rc=2 ".aai/system is a symlink"; the fragment file is still READ through the link first. That is harmless: a read, and the repo already controls the fragment text |
| 3 | `.github` dir is a symlink | rc=2, the outside file is untouched |
| 4 | `--check` with `CLAUDE.md -> AGENTS.md` | rc=2 refusing (the check is in loadShims, so it also runs in --check mode) |
| 5 | `.cursor` is a regular file | rc=2 "is not a directory" |
| 6 | `GEMINI.md` is a directory | rc=2 "not a regular file" |
| 7 | `--root` itself is a symlink | rc=0. The guard checks only components below root; the root is chosen by the caller, which is correct |
| 8 | `CLAUDE.md` hard-linked to an outside file | rc=0, outside file overwritten (finding N1) |
| 9 | `.cursor` absent | rc=0, real dirs created via mkdir; the walk stops at the first ENOENT, which is correct |

TOCTOU: the check runs in loadShims and the writes come later in applyShims, after the skill-tree writes. To exploit the gap, an actor needs concurrent write access to the repo directory at the same privilege, which already lets it write anything. INFO only, no failure scenario across a privilege boundary. An `O_NOFOLLOW` open would close it for the leaf only.

## Deviations from the frozen spec (listed even if reasonable)

- D-1: the amended Spec-AC-03 says "`--write` SHALL exit 2". Because the check sits in `loadShims`, `--check` also exits 2 on a symlinked or non-regular shim (probe 4). Before the fix, a `CLAUDE.md -> AGENTS.md` symlink, a common downstream convention, gave `DIVERGE` and exit 1. It now gives exit 2. Both are non-zero. aai-sync does not call the generator downstream (grep), and the product doc describes the refusal without naming a mode. INFO. Name it in the spec on the next amendment.
- D-2: the CHANGELOG entry does not mention the symlink refusal. The product doc (lines 46-49) does. INFO.

## Findings

- N1 NON-BLOCKING (P3): see the YAML. Recommended disposition: (a) remediate-in-tree. Change the doc to "never writes through a symbolic link out of the project". Optionally also refuse `st.nlink > 1` on the leaf.
- N2 NON-BLOCKING (P3): see the YAML. Recommended disposition: (a) remediate-in-tree. Add a shipped-list-symlink arm to TEST-3015 (this is the arm whose deletion survives the suite). Or (b) file a P3 follow-up.
- INFO: a non-ENOENT lstat error (e.g. EACCES) is rethrown as a raw Error and surfaces as "unexpected error" with a stack, not as a clean ShimError exit 2. This is a cosmetic gap in the same family as `fu-shim-list-validated-after-write`.

## Spec amendment and close ceremony

- The 17:01:58Z `spec_amendment` (contract, unsigned, `tracked_by: fu-amend-provider-adapter-registry-slice`) matches the diff text of the Spec-AC-03 row and the TEST-3015 row. I checked it against the diff, not the report. The 16:18:27Z restamp record discloses an unverified drift cause honestly. The frontmatter anchor validates: mutation-gate PASS, spec-amend --strict rc=0.
- RED log `red-TEST-3015.log` (product_red on 8b5c9429, exit 1) and `mutation-TEST-3015.txt` (verdict RED, selector honoured) are present and consistent.
- Product doc and USER_GUIDE section match the shipped behaviour, except for the N1 wording. The numbering rename (DRAFT to 0253/0228) is consistent in the spec links and scope list.

## Warning dispositions (H6)

- N1: recommend (a) remediate-in-tree, a one-line doc fix. Or (d) `accepted residual: hard links cannot be committed by git; the guard targets committed symlinks` only if the doc wording is also fixed, since otherwise a false record remains.
- N2: recommend (a) remediate-in-tree. Fallback (b) `follow-ups.mjs add --id fu-shim-guard-untested-arms --severity P3`.
- The orchestrator records the chosen artifact. The reviewer files nothing.

## Next steps

Fold N1 and N2, or record their dispositions. Confirm PR #502 CI is green at the final head (closes cannot_verify 2 and 3).
