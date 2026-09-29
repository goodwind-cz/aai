---
id: spec-mutation-clone-windows-run-chain
type: spec
number: 195
status: done
frozen_sha256: 4ba754ed5d314d2c442258cd4bd1bba436b849bc61035702875fc73adc8754ac
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0088-mutation-clone-windows-run-chain.md
  rfc: null
  pr:
    - TBD
  commits:
    - 1912fae483177a4bcc0d591d023e8e4df355df95
---

# Spec — Windows mutation clone reaches the mutated test

SPEC-FROZEN: true

## Ceremony level (RFC-0009)

`ceremony_level: 2` — `mutation-run.mjs` and the platform test wrapper are not in `protected_paths_l3`. Full pipeline, mandatory review. Not L3: the worktree gate is not required.

## Links
- Requirement: docs/issues/ISSUE-0088-mutation-clone-windows-run-chain.md
- Related done work that this ride must not redo: SPEC-0193 (tracked CRLF overlay, untracked-not-ignored copy, EOL-only diagnostic, symlink ROOT safety; PR 406). `--include` stays out of scope.
- Engine: `.aai/scripts/mutation-run.mjs` `buildIsolatedClone` and `runSuite`; `.aai/scripts/aai-run-tests.sh`; `.aai/scripts/aai-run-tests.ps1`; `.aai/scripts/lib/git-bash-path.sh`
- Technology contract: docs/TECHNOLOGY.md

## Problem

After SPEC-0193, a Windows mutation run still stops before the mutated test. Three defects show up in order:

1. `git clone --local` hits Git's clone protection. An active `post-checkout` hook (the Git LFS hook) is refused, checkout fails, and `buildIsolatedClone` never reaches the working-tree overlay.
2. `.aai` is gitignored, so the clone has no `.aai/scripts/aai-run-tests.sh` and no `.aai/scripts/aai-run-tests.ps1`. `runSuite` cannot launch the wrapper.
3. Once the wrapper is present, a project Python path spelled as a Windows path is handed to Git Bash unchanged. The translation step must not itself be a missing helper command. The run exits 127 before the mutated assertion.

Local settings stay where they already are. This ride does not copy them into the clone and does not add or edit per-project settings templates.

## Design decisions (resolved — do not reopen during implementation)

### D1 — local clone of the operator tree may run the LFS hook

`buildIsolatedClone` clones with `git clone --local --no-hardlinks` and sets `GIT_CLONE_PROTECTION_ACTIVE=false` on that clone invocation only. The source is the operator's own working tree, already trusted. The documented Git remedy for "active post-checkout hook found during git clone" is that variable. Later git commands in the same run do not inherit a process-wide override beyond that one spawn. SPEC-0193 overlay, untracked copy, EOL diagnostic, and symlink ROOT safety stay as they are.

### D2 — reproduce the test wrapper when gitignore hid it

After clone-fidelity succeeds, if `.aai/scripts/aai-run-tests.sh` or `.aai/scripts/aai-run-tests.ps1` exists in the source tree and is absent from the clone, copy that file into the clone. Tracked or already-copied wrappers are left untouched. No other gitignored path is copied. In particular this ride does not copy local settings files and does not read them.

### D3 — translate a Windows Python path in-process

A Windows absolute path (`C:\...` or `C:/...`) becomes the Git Bash path `/c/...` by string conversion. The reverse (`/c/...` to `C:\...`) is the same pure function. Neither direction spawns `cygpath` or `wslpath`. The PowerShell Git Bash launch translates command arguments that are Windows absolute paths and leaves every other argument, including the wrapper script path, unchanged. Under the MSYS branch, `aai-run-tests.sh` rewrites its own command arguments the same way and exports `BASH_ENV` so a child bash suite recovers a backslash Windows path via `command_not_found_handle` when that translated file exists.

### D4 — never write the shipping tree

SPEC-0181 D7 is unchanged. The isolated mutation does not write the source working tree.

## Implementation strategy
- Strategy: direct
- Rationale: three bounded seams (one clone spawn, one wrapper copy, one path function) with targeted regression tests. Stored RED artifacts and a mutation column are not demanded for `direct`.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: one feature branch; no parallel scope shares this checkout; the surfaces are not protected L3.
- User decision: inline (autopilot default for not_needed)
- Base ref: main
- Inline review scope: `.aai/scripts/mutation-run.mjs .aai/scripts/aai-run-tests.sh .aai/scripts/aai-run-tests.ps1 .aai/scripts/lib/git-bash-path.sh tests/skills/test-aai-mutation-gate.sh tests/skills/test-aai-win-fallback.sh tests/skills/aai-win-dispatch.Tests.ps1 docs/issues/ISSUE-0088-mutation-clone-windows-run-chain.md docs/specs/SPEC-0195-spec-mutation-clone-windows-run-chain.md docs/INDEX.md docs/ai/EVENTS.jsonl`

## Acceptance Criteria Mapping
- Maps to: ISSUE mutation-clone-windows-run-chain Expected Behavior
- Spec-AC-01: clone protection does not abort the local clone
- Spec-AC-02: gitignored test wrapper is present in the clone
- Spec-AC-03: Windows Python path translates to a Git Bash path without exit 127 from a helper command
- Verification: the three TEST commands in Verification

## Constitution deviations

None.

## Acceptance Criteria Status

Never use pipe characters inside cells.

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN git clone --local would refuse because an active post-checkout hook is blocked by clone protection THEN buildIsolatedClone SHALL still build the clone by invoking that clone with GIT_CLONE_PROTECTION_ACTIVE=false | done | docs/ai/reports/VALIDATION-20260929T220559Z-mutation-clone-windows-run-chain.md | — | D1 |
| Spec-AC-02 | WHEN .aai/scripts/aai-run-tests.sh and .aai/scripts/aai-run-tests.ps1 exist on disk and are gitignored THEN the isolated clone SHALL contain both files and the suite SHALL run | done | docs/ai/reports/VALIDATION-20260929T220559Z-mutation-clone-windows-run-chain.md | — | D2; no other gitignored path is copied |
| Spec-AC-03 | WHEN a command argument or a bash command name is a Windows absolute path to the project Python interpreter THEN the Git Bash side SHALL execute the translated /drive/ path and the translation itself SHALL be an in-process string conversion | done | docs/ai/reports/VALIDATION-20260929T220559Z-mutation-clone-windows-run-chain.md | — | D3; reverse translation is the same function |

Status values: planned, implementing, done, deferred, blocked, rejected.

## Implementation plan

1. `.aai/scripts/mutation-run.mjs`
   - Pass `GIT_CLONE_PROTECTION_ACTIVE=false` on the `git clone --local --no-hardlinks` spawn only.
   - After the clone-fidelity hash matches, copy a missing test wrapper (`.sh` and `.ps1`) from the source tree.
2. `.aai/scripts/lib/git-bash-path.sh`
   - POSIX functions `aai_to_git_bash_path` and `aai_to_windows_path`.
   - `command_not_found_handle` execs the translated path when the file exists. `AAI_GIT_BASH_FS_ROOT`, when set, prefixes that path so a Linux test can place the sentinel file. Unset in production, so the path stays a real Git Bash path.
3. `.aai/scripts/aai-run-tests.sh`
   - On the MSYS branch, rewrite command arguments through `aai_to_git_bash_path` and export `BASH_ENV` to the lib.
4. `.aai/scripts/aai-run-tests.ps1`
   - `ConvertTo-GitBashPath` / `ConvertTo-WindowsPath`.
   - `Invoke-ViaGitBash` translates command arguments that are Windows absolute paths. The wrapper script path stays a Windows path.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Mutation | Status |
|----------|------------|------|----------------------|-------------|----------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-mutation-gate.sh | A git shim refuses clone unless GIT_CLONE_PROTECTION_ACTIVE=false and prints the post-checkout protection fatal. mutation-run still records RED (exit 0), and the shim records that the allowed clone ran. | n/a | pending |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-mutation-gate.sh | Fixture gitignores .aai. The wrapper sh and a sentinel ps1 exist only as ignored files. The suite inside the clone sees both files and the mutation records RED (exit 0). | n/a | pending |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-win-fallback.sh | Pure round-trip of a Windows Python path, plus a bash suite under AAI_UNAME=MSYS_NT whose command name is that Windows path and which executes a sentinel through command_not_found_handle. | n/a | pending |
| TEST-004 | Spec-AC-03 | integration | tests/skills/aai-win-dispatch.Tests.ps1 | ConvertTo-GitBashPath and ConvertTo-WindowsPath round-trip the project Python path. Invoke-ViaGitBash translates that command argument and still passes the wrapper script path through unchanged. | n/a | pending |

## Verification
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-mutation-gate.sh test_007_lfs_clone_protection`
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-mutation-gate.sh test_008_gitignored_test_wrapper`
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-win-fallback.sh 028`
- Pester `tests/skills/aai-win-dispatch.Tests.ps1` on a host with pwsh; the new example is the Git Bash Python-path example
- PASS: TEST-001..004 green, Spec-AC-01..03 done

## Evidence contract
- ref_id: mutation-clone-windows-run-chain
- Spec-AC / TEST links as in the tables
- Commands as Verification

### Evidence by strategy

direct: targeted regression tests green (exit codes) plus the scoped diff. No stored RED artifact.

## Residual risks

- R1: A `C:/` path inside a child script (forward slashes) is not recovered by `command_not_found_handle`, because bash treats a slash as a path and does not call the hook. The wrapper and the PowerShell boundary still translate that spelling when it is a command argument. Backslash paths are recovered in the child.
- R2: Disabling clone protection is limited to the one local clone of the operator tree. It is the upstream remedy for the LFS hook refusal. A hostile hook in that same tree could run; the tree is already the operator's checkout.
