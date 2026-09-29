---
id: spec-mutation-clone-fidelity-windows-eol
type: spec
number: 193
status: done
mutation_gate: v1
frozen_sha256: 0e81bcd62d6a4a621ed97d8980ef3e69c06671a32fa8ba282a28c8ee05ed5d2e
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0087-mutation-clone-fidelity-windows-eol.md
  rfc: null
  pr:
    - 406
  commits:
    - 46f9241662700e4004b8babf49989371ab779633
---

# Spec — Mutation clone fidelity matches working-tree bytes on mixed EOL

## Ceremony level (RFC-0009)

`ceremony_level: 2` — mutation-run.mjs is not in `protected_paths_l3`. Full
pipeline, mandatory review, TDD + mutation_gate. Not L3: the worktree gate is
not required.

Ceremony justification is not required at level 2.

## Links
- Requirement: docs/issues/ISSUE-0087-mutation-clone-fidelity-windows-eol.md
- Related done work that does not close this: CHANGE-0187 / SPEC-0181 D4
  clone-fidelity, ISSUE-0045 isolation-shares-the-shipping-git
- Pair (do not merge the rides): prompts-invoke-wsl-bash-on-windows
- Engine: `.aai/scripts/mutation-run.mjs` `buildIsolatedClone`,
  `.aai/scripts/lib/tree-hash.mjs` `describeTreeDiff`
- Technology contract: docs/TECHNOLOGY.md

## Problem

`buildIsolatedClone()` reconstructs the working tree with `git clone` +
`checkout HEAD` + `git diff HEAD | git apply` + copy of every
untracked-not-ignored path, then byte-hashes the clone against the source.
On Windows (`core.autocrlf=true`) checkout and apply change line endings
even when Python/content is equivalent, so clone-fidelity refuses or yields
INCONCLUSIVE and the mutation never tests the changed behavior.

SPEC-0181 D4 still holds: the clone must reproduce the source working tree.
This ride changes *how* that reproduction is built (working-tree byte overlay
of the fidelity set), not the invariant. Root-level untracked files are
copied and hashed (D2); omitting them false-REDs a suite that needs a new
root file. ISSUE Expected Behavior "Unrelated untracked files do not
participate in clone-fidelity" is descoped for that reason.

## Design decisions (resolved — do not reopen during implementation)

### D1 — overlay tracked working-tree bytes after checkout

After `git clone` + `checkout` of HEAD, copy each tracked path's
**working-tree bytes** from the source tree into the clone (`copyFileSync` /
read+write of the source path). Do not rely on `git diff | git apply` to
reproduce dirty tracked files: apply is a text reconstruction and can change
EOL. Overlay makes the clone's tracked files byte-identical to the source
working tree, including mixed LF/CRLF. `git apply` of `git diff HEAD` may
remain as a no-op-or-pre-step; the overlay is the fidelity source of truth
for tracked paths.

### D2 — root-level untracked files are copied and hashed

Untracked-not-ignored paths, including **root-level** files (`scratch.tmp`),
participate in copy and the D4 hash, the same as nested untracked
(`lib/extra.txt`). Omitting root-level files from the clone false-REDs a
suite that needs a newly added root file (the file is untracked at mutation
time because rides commit after validation). Clone-fidelity succeeds because
both trees carry the same bytes. Overlay, untracked copy, and allowlist
writers walk each clone ancestor of the destination with lstat and replace
a symlink or non-directory with a real directory, then unlink the leaf
(never following). mkdir/copy therefore cannot follow a leftover clone
symlink into ROOT (D4) when `git apply` of a typechange plus dirty binary
is warning-only. `--include` stays out of scope.

### D3 — mismatch names paths and classifies EOL-only

When clone and source hashes differ, the existing `describeTreeDiff` path
list stays. For every `changed` path whose source and clone bytes differ
only by the presence of CR (`\r`), the message SHALL contain the token
`EOL-only difference` and the path. Other byte diffs stay unnamed as
EOL-only.

### D4 — never write the shipping tree

SPEC-0181 D7 is unchanged: the isolated mutation does not write the source
working tree. This ride adds no write to ROOT.

### D5 — no new CLI this ride

No `--include`. Windows agents still launch the runner through the platform
test wrapper (owned by the paired prompts ride).

## Implementation strategy
- Strategy: tdd
- Rationale: clone-fidelity is a byte-level invariant; each AC is a RED-first
  fixture against the real runner. mutation_gate v1 applies.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: dedicated feature branch already isolates the ride;
  mutation-run.mjs is not a protected L3 surface; no parallel scope shares
  this checkout.
- User decision: inline (autopilot default for not_needed)
- Base ref: main
- Inline review scope: `.aai/scripts/mutation-run.mjs .aai/scripts/lib/tree-hash.mjs tests/skills/test-aai-mutation-gate.sh docs/issues/ISSUE-0087-mutation-clone-fidelity-windows-eol.md docs/specs/SPEC-0193-spec-mutation-clone-fidelity-windows-eol.md docs/knowledge/FACTS.md docs/INDEX.md`

## Acceptance Criteria Mapping
- Maps to: ISSUE mutation-clone-fidelity-windows-eol Expected Behavior
- Spec-AC-01: tracked overlay
- Spec-AC-02: root-level untracked copy
- Spec-AC-03: EOL-only diagnostic
- Spec-AC-04: leftover clone symlink (leaf or ancestor) must not write ROOT
- Verification: TEST-001..005 via `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-mutation-gate.sh test_<id>`
- Descope: ISSUE Expected Behavior "Unrelated untracked files do not participate in clone-fidelity" (and Verification item 3). Reason: omitting a root-level untracked file from the clone false-REDs a suite that reads a newly added root file. Covered by D2 / Spec-AC-02 instead.

## Constitution deviations

None.

## Registry items closed by this scope

none — `fu-clone-untracked-copy-not-nul-split` stays open (newline vs `-z`
on the untracked copy loop). Payload filtering may hide some quoted-name
failures but does not close that item.

## Acceptance Criteria Status

Never use pipe characters inside cells.

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN a tracked dirty file in the source working tree holds CRLF bytes that differ from HEAD THEN buildIsolatedClone SHALL make the clone path byte-identical to those working-tree bytes (clone-fidelity hash equal, no TreeMismatchError) | done | docs/ai/tdd/spec-mutation-clone-fidelity-windows-eol/green-TEST-001-003.log | — | D1; mutation-TEST-001.txt RED |
| Spec-AC-02 | WHEN an untracked-not-ignored file sits at the repository root THEN buildIsolatedClone SHALL copy it and include it in the D4 hash so clone-fidelity still succeeds and a suite that reads that file does not false-RED | done | docs/ai/tdd/spec-mutation-clone-fidelity-windows-eol/green-TEST-001-003.log | — | D2 copy+hash; overlay unlinks dst; mutation-TEST-002.txt RED |
| Spec-AC-03 | WHEN clone and source hashes differ only by CR bytes on a named path THEN the TreeMismatchError message SHALL contain EOL-only difference and that path | done | docs/ai/tdd/spec-mutation-clone-fidelity-windows-eol/green-TEST-001-003.log | — | D3; mutation-TEST-003.txt RED via sed on ${eolSuffix} in the runner template |
| Spec-AC-04 | WHEN the clone still holds a HEAD symlink (file or directory) because git apply of a dirty binary failed and the working tree replaced that symlink with a regular file or directory THEN buildIsolatedClone SHALL leave the symlink target bytes in ROOT unchanged | done | docs/ai/tdd/spec-mutation-clone-fidelity-windows-eol/green-TEST-001-005.log | — | D2 parent-walk + leaf unlink; TEST-004 ancestor, TEST-005 leaf |

Status values: planned, implementing, done, deferred, blocked, rejected.

## Implementation plan

1. `.aai/scripts/mutation-run.mjs` `buildIsolatedClone`
   - After checkout (and optional apply), overlay every tracked path from
     `git ls-files -z` in ROOT onto the clone using source working-tree bytes.
   - Copy untracked-not-ignored files including root-level scratch. Overlay,
     untracked copy, and allowlist writers walk clone ancestors and replace
     symlink or non-directory components, then unlink the leaf, so a leftover
     clone symlink cannot write through to ROOT. D4 hashes the full map.
   - On hash mismatch, classify changed paths whose buffers differ only by CR
     and include `EOL-only difference` plus the path in TreeMismatchError.
2. `.aai/scripts/lib/tree-hash.mjs` only if the classification helper belongs
   there as a shared function; otherwise keep it local to mutation-run.mjs so
   D7 messages do not change.
3. Tests in `tests/skills/test-aai-mutation-gate.sh` using existing
   `mg_seed_repo` fixtures. Do not touch the shipping tree.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Mutation | Status |
|----------|------------|------|----------------------|-------------|----------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-mutation-gate.sh | Fixture repo with core.autocrlf=true, HEAD file LF, dirty working-tree CRLF on a tracked path; mutation-run clone-fidelity succeeds (exit not 3) and the clone file bytes equal the source working-tree bytes | sed:s/overlayTrackedWorkingTreeBytes\(cloneDir, ROOT\);// | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-mutation-gate.sh | Same runner with an extra untracked file scratch.tmp at repo root; clone-fidelity succeeds (exit not 3) and a NOTE names the copied root-level path | sed:s/if \(!p\) continue;/if (!p) continue; if (isRootLevelUntracked(p)) continue;/ | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-mutation-gate.sh | Fixture with tracked CRLF dirty file; a scratch copy of mutation-run.mjs with overlay removed refuses clone-fidelity (exit 3) and stderr contains EOL-only difference plus the path | sed:s/\${eolSuffix}// | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-mutation-gate.sh | Fixture HEAD tracks an absolute dir symlink plus a dirty binary so git apply fails; working tree replaces the symlink with a real dir and file (staged and unstaged); ROOT target bytes stay unchanged | sed:s/ensureCloneParentDirs\(cloneDir, rel\);//g | green |
| TEST-005 | Spec-AC-04 | integration | tests/skills/test-aai-mutation-gate.sh | Fixture HEAD tracks a leaf file symlink plus a dirty binary so git apply fails; working tree replaces the symlink with a regular file; ROOT target bytes stay unchanged | sed:s/unlinkIfExists\(dst\);//g | green |

## Verification
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-mutation-gate.sh test_001_tracked_crlf_overlay`
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-mutation-gate.sh test_002_root_untracked_copied`
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-mutation-gate.sh test_003_eol_only_mismatch_token`
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-mutation-gate.sh test_004_symlink_ancestor_does_not_write_root`
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-mutation-gate.sh test_005_symlink_leaf_does_not_write_root`
- `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0193-spec-mutation-clone-fidelity-windows-eol.md`
- PASS: TEST-001..005 green, Spec-AC-01..04 done, 5/5 mutations RED

## Evidence contract
- ref_id: mutation-clone-fidelity-windows-eol
- Spec-AC / TEST links as in the tables
- Commands as Verification
- Evidence under docs/ai/tdd/spec-mutation-clone-fidelity-windows-eol/

### Evidence by strategy

tdd: stored RED artifact per AC-gating test plus the verification matrix.

## Residual risks

- R1: Overlay copies every tracked file; large dirty trees pay I/O. Acceptable
  versus false INCONCLUSIVE on Windows.
- R2: An uncopyable root-level untracked file (locked or permission-denied)
  is counted in the copied NOTE then D4 refuses with `removed:`. Fail-closed.
  A Windows locked-file fixture is cannot_verify.

SPEC-FROZEN: true
