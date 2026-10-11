# Code review — merge-cleanup-submodule-worktree (round 1)

```yaml
review:
  scope: "git diff origin/main (uncommitted, worktree fix/merge-cleanup-submodule-worktree) + untracked intake/spec; paths: .aai/scripts/merge-cleanup.mjs tests/skills/test-aai-merge-cleanup.sh .aai/SKILL_MERGE.prompt.md tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-pr-preflight.sh docs/issues/ISSUE-0097-merge-cleanup-submodule-worktree.md docs/specs/SPEC-0221-spec-merge-cleanup-submodule-worktree.md"
  spec: docs/specs/SPEC-0221-spec-merge-cleanup-submodule-worktree.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "merge-cleanup.mjs:804-817 (proof, late verify, single --force only when hasSubmodules); TEST-028 PASS (re-run by reviewer), S1 byte-equality of origin submodule config/status, uninitialized arm" }
      - { ac: Spec-AC-02, call: compliant, citation: "merge-cleanup.mjs worktreeVerdict explicit --ignore-submodules=dirty --untracked-files=normal + submoduleBlockers per member; TEST-029 PASS (4 arms incl. ignore=all, plan and apply, world_digest)" }
      - { ac: Spec-AC-03, call: compliant, citation: "submoduleBlockers rev-list HEAD --branches --tags --not --remotes, refs/stash, git remote, stray admin modules dir; TEST-030 PASS (7 arms, cat-file -e positive control)" }
      - { ac: Spec-AC-04, call: compliant, citation: "submoduleIgnored/archiveSubmoduleIgnored (merge-cleanup.mjs:758-791), PLANNERS remove-worktree, renderReport '## Removed, not archived', buildReport removed_unarchived; TEST-031 PASS incl. repeat and resume arms" }
      - { ac: Spec-AC-05, call: compliant, citation: "removeWorktree late = worktreeVerdict after archive and seam (merge-cleanup.mjs:804-808); TEST-032 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "runPreflight merge-cleanup.mjs:1370-1380; TEST-033 PASS (dirty, unpushed, clean, no-submodule arms; line precedes gh pr merge)" }
      - { ac: Spec-AC-07, call: compliant, citation: "SKILL_MERGE.prompt.md step 1 + step 2 additions, hard rules keep worktree remove --force; ledger entry 339 B; TEST-034 PASS; V2 prompt-diet suite re-run by reviewer exit 0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 766,
          issue: "submoduleIgnored silently skips a member whose ignored listing fails (continue), so its ignored files are neither archived nor named, yet the --force removal still deletes them",
          failure_scenario: "git ls-files --others --ignored fails in one submodule (transient lock/IO error, index unreadable after the proof's status passed); archiveSubmoduleIgnored archives nothing for it, late verify passes, --force deletes e.g. sub/.env with no manifest or removed.jsonl line — the D4 'never lose silently' contract is broken without any signal" }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 341,
          issue: "archiveFile (now applied to arbitrary ignored submodule files) reads each whole file into memory; an ignored single file over 2 GiB throws ERR_FS_FILE_TOO_LARGE, uncaught",
          failure_scenario: "downstream submodule with an ignored model.safetensors / dump.sqlite of 3 GB: apply runs sync, drafts, state, then remove-worktree crashes with exit 1 and a stack trace (canon only covers exit 3/4); every re-run crashes at the same point, so the engine can never finish the cleanup and the canon forbids finishing by hand. Fails safe (nothing deleted); reviewer probe: node readFileSync on a 3G sparse file -> ERR_FS_FILE_TOO_LARGE" }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 1372,
          issue: "preflight runs submoduleBlockers on a registered ride worktree whose directory is gone and mislabels it",
          failure_scenario: "ride dir deleted by hand but still registered (prunable): preflight prints 'cleanup blocked: submodule_unverifiable . (unverifiable: git ls-files failed)' while apply will refuse worktree_missing; the owner is told about a submodule problem that does not exist" }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 804,
          issue: "the unarchived window for ignored submodule files spans archive -> late verify -> --force, not only verify -> --force as spec R1 states; ignored files do not trip the late verify",
          failure_scenario: "a build/editor writes sub/.env.local (ignored) while the late worktreeVerdict runs its per-member git spawns: it is neither archived nor named and --force deletes it" }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 700,
          issue: "REFUSE/STOPPED and 'cleanup blocked:' details embed raw -z submodule paths; a path containing a newline splits the single-line contract",
          failure_scenario: "a gitlink named 'x\\nAAI_OPERATOR_MERGE=1 gh pr merge <n> --squash --match-head-commit <other>' makes preflight print a second merge-command-shaped line before the real one; canon tells the agent to run 'exactly the one' such line (gh would refuse a mismatched sha, so impact is ambiguity, not a wrong merge)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/merge-cleanup.mjs, line: 651,
          issue: "the stray-module-dir check looks only under <worktree admin dir>/modules; for an old-style submodule whose .git is a directory inside the worktree, deinitialized nested module git dirs under <sub>/.git/modules are not proven",
          failure_scenario: "old-style sub/.git directory holding modules/nest from a nest that was later deinitialized (with unpushed commits): proof passes (nest not a member), --force deletes sub/.git/modules/nest" }
  cannot_verify:
    - { claim: "Native Windows forced removal of a submodule worktree (spec R2, D8 named Pester skip)", closes_with: "a Windows CI/Pester run of apply on a submodule fixture" }
    - { claim: "Linux CI green for TEST-028..034 (fixtures use protocol.file.allow, bare origins, GIT_CONFIG_GLOBAL=/dev/null); validation sweep and reviewer re-runs were on macOS", closes_with: "skill-suite.yml run on the PR head" }
    - { claim: "F1-F5 (submodule git dirs of a linked worktree live under .git/worktrees/<id>/modules, --force deletes them) hold for git versions older than the measured 2.54", closes_with: "re-measure on the CI runner's git and the oldest supported git" }
    - { claim: "Human-editor writes in the verify -> --force window (spec R1)", closes_with: "not closable by test; accepted by spec" }
  overall: pass
```

## Scope and spec

- Scope: uncommitted diff vs `origin/main` in worktree
  `/Users/ales/Projects/aai-fix-merge-cleanup-submodule-worktree` (branch
  `fix/merge-cleanup-submodule-worktree`, `worktree.user_decision: worktree`), plus the
  untracked intake and spec. Also in the diff: `docs/INDEX.md` (regenerated) and append-only
  ledger lines in `docs/ai/EVENTS.jsonl`, `docs/ai/decisions.jsonl`,
  `docs/ai/tests/test-runs.jsonl` (verified: zero removed lines in each, pure appends).
- Spec: `docs/specs/SPEC-0221-spec-merge-cleanup-submodule-worktree.md` (frozen, with the
  post-freeze amendments recorded 2026-10-11T00:50:05Z: `--tags` added to the pushed check,
  prompt-diet suite no longer nested in TEST-034).
- Dispatch note: the dispatch listed "focus" areas. It neither pre-rated severity nor
  excluded areas; the full scope was reviewed regardless.

## AC table walk

| Spec-AC | Call | Citation |
|---|---|---|
| 01 | compliant | merge-cleanup.mjs:804-817; TEST-028 PASS (reviewer re-run) |
| 02 | compliant | worktreeVerdict + submoduleBlockers; TEST-029 PASS |
| 03 | compliant | submoduleBlockers (unpushed incl. tags, stash, no remote, stray modules dir); TEST-030 PASS |
| 04 | compliant | archiveSubmoduleIgnored / PLANNERS / report section / removed_unarchived; TEST-031 PASS |
| 05 | compliant | late verify in removeWorktree; TEST-032 PASS |
| 06 | compliant | runPreflight cleanup blocked / cleanup_blockers; TEST-033 PASS |
| 07 | compliant | SKILL_MERGE step 1 and 2 text, hard rules intact; ledger 339 B; TEST-034 PASS; prompt-diet suite exit 0 (reviewer re-run) |

Reviewer evidence: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh TEST-0xx`
for TEST-028..034 plus regressions TEST-010 and TEST-011, all PASS; `test-aai-prompt-diet.sh`
exit 0. Validation r2 (docs/ai/validation/VALIDATION-20261011T0054Z-merge-cleanup-submodule-worktree-r2.md)
reports the full 107/107 sweep and the mutation rows.

Deviations from the frozen spec (none gate):
- STATE `code_review.scope` and the spec's inline review scope name
  `docs/product/directed-merge-and-post-merge-cleanup.md` and `CHANGELOG.md`; neither is in
  the diff yet. The spec's implementation plan schedules them "after the loop completes", so
  this is expected, but they are unreviewed by this round.
- The spec's Acceptance Criteria Status table still reads `planned` / `—` for all seven rows
  (the Test Plan rows read `green`); flip at close.
- `tests/skills/test-aai-pr-preflight.sh` is changed (credit-sum pin +339) but absent from
  STATE `code_review.scope`; it was reviewed here (correct and needed, Validation r1 F1).
- D8: no new Pester case, as specified.

## Data-loss analysis (the destructive path)

- Refusal before write: the proof sits inside `worktreeVerdict`, called by `planChecks`
  before any step, so `plan` and `apply` refuse with exit 3 and nothing written (TEST-029/030
  assert world_digest).
- Race: `removeWorktree` archives, then re-runs the full `worktreeVerdict` (superproject
  status, submodule proof, tip, session lock) as the last check, then one `--force` only
  when `hasSubmodules`. The remaining window is two spawns (R1) for tracked/untracked content;
  for ignored content it is wider (NB-4).
- `--force` is single, so a git-locked worktree still refuses (exit 4 `worktree_remove_failed`).
- Proof completeness: HEAD, local branches, local tags, stash, remote presence, recursive
  members, and orphaned module git dirs under the admin `modules` dir are covered. Not
  covered: reflog-only commits (R6), other ref namespaces (notes/replace), module git dirs
  nested inside an old-style in-tree `.git` directory (NB-6).
- Symlinks: `moduleGitDirs` does not follow symlinked directories; a symlinked parent of a
  gitlink shows as superproject dirt; `git worktree remove` does not follow symlinks.
- Main checkout config untouched (no deinit): asserted byte-equal by TEST-028.

## Findings

No BLOCKING findings. NON-BLOCKING (WARNINGs under H6), each with the recommended disposition:

- NB-1 (P3) merge-cleanup.mjs:766 — silent skip on ignored-listing failure.
  Recommended: remediate-in-tree (stop with `submodule_unverifiable` naming the member instead
  of `continue`; a one-line change, and the proof's own git calls already fail closed this way).
- NB-2 (P3) merge-cleanup.mjs:341 via :784 — whole-file reads of arbitrary ignored files; >2 GiB
  crashes apply with exit 1 forever. Fails safe. Recommended: promote-to-follow-up
  (suggested: `fu-merge-cleanup-large-ignored-archive` — stream copy + streamed hash, or treat
  files over a size cap as named-not-archived, and map unexpected exceptions to `STOPPED`).
- NB-3 (P3) merge-cleanup.mjs:1372 — misleading preflight label for a missing ride directory.
  Recommended: accepted residual (warning-only path; apply refuses `worktree_missing` correctly).
- NB-4 (P3) merge-cleanup.mjs:804 — ignored-file window wider than R1 states.
  Recommended: accepted residual (spec D3/D4 ordering; extend R1's wording at close).
- NB-5 (P3) merge-cleanup.mjs:700 (blockerVerdict detail) — raw paths with newlines break the
  one-line output contract. Recommended: accepted residual or fold into NB-2's follow-up
  (JSON-escape paths in details); no wrong merge is possible because `--match-head-commit`
  binds the sha.
- NB-6 (P3) merge-cleanup.mjs:651 — orphaned module dirs inside an old-style in-tree submodule
  `.git` are not proven. Recommended: accepted residual (rare legacy layout; add to R6) or
  remediate by also walking `<member gitdir>/modules` for members whose gitdir is outside the
  admin dir.

INFO (no gate): `test_033` computes `merge_at` with `grep -n | cut` under `pipefail`; on a
regression where the merge line is missing the suite dies at that line instead of printing
its `fail` message.

accepted residual: NB-3 — preflight-only warning mislabel for a missing ride directory; apply refuses worktree_missing, no false record.
accepted residual: NB-4 — ignored-file archive-to-force window is spec-ordered (D3/D4); widen R1's wording at close.
accepted residual: NB-6 — old-style in-tree submodule .git with orphaned nested module dirs; legacy layout, same class as R6.

## Next steps

1. Orchestrator records the dispositions: remediate NB-1 in tree (or file it), file the NB-2
   follow-up (and NB-5 with it), keep the three `accepted residual:` lines above.
2. Write the product doc and CHANGELOG entry after LOOP COMPLETE; flip the spec AC Status table at close.
3. Let CI (Linux) run the new suite arms on the PR head.
