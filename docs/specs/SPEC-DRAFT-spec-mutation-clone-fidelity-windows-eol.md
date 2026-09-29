---
id: spec-mutation-clone-fidelity-windows-eol
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 2f709093b8f84271499603db7c3dda54f5dc920fa3b9e4d82222c9e55882b787
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-DRAFT-mutation-clone-fidelity-windows-eol.md
  rfc: null
  pr: []
  commits: []
---

# Spec — Mutation clone fidelity matches working-tree bytes on mixed EOL

## Ceremony level (RFC-0009)

`ceremony_level: 2` — mutation-run.mjs is not in `protected_paths_l3`. Full
pipeline, mandatory review, TDD + mutation_gate. Not L3: the worktree gate is
not required.

Ceremony justification is not required at level 2.

## Links
- Requirement: docs/issues/ISSUE-DRAFT-mutation-clone-fidelity-windows-eol.md
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
INCONCLUSIVE and the mutation never tests the changed behavior. Unrelated
dirty/untracked files also enter the hash.

SPEC-0181 D4 still holds: the clone must reproduce the source working tree.
This ride changes *how* that reproduction is built (working-tree byte overlay
of the fidelity set), not the invariant.

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

### D2 — unrelated untracked files are outside the fidelity set

Untracked-not-ignored paths participate in copy and D4 hash only when they
are mutation payload: they start with `.aai/`, `tests/`, or `docs/`, or they
are on `RUNTIME_ALLOWLIST`. Other untracked files are neither copied nor
compared. This is the closed list Planning froze; `--include` is out of
scope (intake allowed it as optional).

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
- Inline review scope: `.aai/scripts/mutation-run.mjs .aai/scripts/lib/tree-hash.mjs tests/skills/test-aai-mutation-gate.sh docs/issues/ISSUE-DRAFT-mutation-clone-fidelity-windows-eol.md docs/specs/SPEC-DRAFT-spec-mutation-clone-fidelity-windows-eol.md docs/knowledge/FACTS.md`

## Acceptance Criteria Mapping
- Maps to: ISSUE mutation-clone-fidelity-windows-eol Expected Behavior
- Spec-AC-01: tracked overlay
- Spec-AC-02: untracked filter
- Spec-AC-03: EOL-only diagnostic
- Verification: TEST-001..003 via `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-mutation-gate.sh test_<id>`

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
| Spec-AC-01 | WHEN a tracked dirty file in the source working tree holds CRLF bytes that differ from HEAD THEN buildIsolatedClone SHALL make the clone path byte-identical to those working-tree bytes (clone-fidelity hash equal, no TreeMismatchError) | planned | — | — | D1 |
| Spec-AC-02 | WHEN an untracked-not-ignored file sits outside .aai/, tests/, and docs/ THEN buildIsolatedClone SHALL omit it from copy and from the D4 hash so clone-fidelity still succeeds | planned | — | — | D2 |
| Spec-AC-03 | WHEN clone and source hashes differ only by CR bytes on a named path THEN the TreeMismatchError message SHALL contain EOL-only difference and that path | planned | — | — | D3 |

Status values: planned, implementing, done, deferred, blocked, rejected.

## Implementation plan

1. `.aai/scripts/mutation-run.mjs` `buildIsolatedClone`
   - After checkout (and optional apply), overlay every tracked path from
     `git ls-files -z` in ROOT onto the clone using source working-tree bytes.
   - Filter untracked copy + strip those paths from `sourceTreeFiles` unless
     they are payload (`.aai/`, `tests/`, `docs/`) or RUNTIME_ALLOWLIST.
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
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-mutation-gate.sh | Fixture repo with core.autocrlf=true, HEAD file LF, dirty working-tree CRLF on a tracked path; mutation-run clone-fidelity succeeds (exit not 3) and the clone file bytes equal the source working-tree bytes | sed:s/overlayTrackedWorkingTreeBytes(cloneDir, ROOT);// | pending |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-mutation-gate.sh | Same runner with an extra untracked file scratch.tmp at repo root; clone-fidelity succeeds and scratch.tmp is absent from the clone | sed:s/isPayloadUntracked(p)/true/ | pending |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-mutation-gate.sh | Force a clone vs source CR-only mismatch on a named path; stderr contains EOL-only difference and the path | sed:s/EOL-only difference/path-bytes-differ/ | pending |

## Verification
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-mutation-gate.sh test_001_tracked_crlf_overlay`
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-mutation-gate.sh test_002_unrelated_untracked_omitted`
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-mutation-gate.sh test_003_eol_only_mismatch_token`
- `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-DRAFT-spec-mutation-clone-fidelity-windows-eol.md`
- PASS: TEST-001..003 green, Spec-AC-01..03 done, 3/3 mutations RED

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
- R2: Payload prefix list may omit an untracked file a downstream project
  keeps outside `.aai/`/`tests/`/`docs/`. Fail-closed they must move it or
  a later `--include` ride must land. Documented, not this freeze.

SPEC-FROZEN: true
