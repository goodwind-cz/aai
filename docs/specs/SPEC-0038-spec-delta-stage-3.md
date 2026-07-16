---
id: spec-delta-stage-3
type: spec
number: 38
status: implementing
ceremony_level: 2
links:
  change: delta-stage-3
  rfc: delta-spec-lifecycle
  pr: []
  commits: []
---

# SPEC — Delta-Spec Lifecycle, Stage 3: Close-Time Delta Merge + Provenance Drift

SPEC-FROZEN: true

## Links
- RFC: delta-spec-lifecycle (docs/rfc/RFC-0011-delta-spec-lifecycle.md, ACCEPTED
  2026-07-16; this delivers the third and final staged SPEC).
- Change: delta-stage-3 (docs/issues/CHANGE-0026-delta-stage-3.md)
- Builds on: spec-delta-stage-1 (SPEC-0034 — `parseRequirementsSection`, REQ
  grammar, `domainToReqDomain`) and spec-delta-stage-2 (SPEC-0037 —
  `parseDeltasSection`, `reqDomainToSlug`, the FAIL-CLOSED consumption contract).
- Technology contract: docs/TECHNOLOGY.md

## Ceremony level
`ceremony_level: 2` (full pipeline). A new merge engine that writes canonical
docs plus a docs-audit gate — a multi-surface governance change, above level
0/1. It touches no `protected_paths_l3` surface (state engine, allocator,
pre-commit guards, WORKFLOW.md, CONSTITUTION untouched); level 3 not mandatory.

Ceremony justification: not applicable at level 2 (justification is the level-0/1
lean-close requirement).

## Stage boundary
This delivers the close-time merge and the drift gate. `docs/canonical/` is
EMPTY in this repo, so the merge and the drift check are NO-OPS on the live tree
— they ship fixture-tested and ready for a project that carries canonical docs.
The merge writes deterministically with NO LLM in the write path (RFC-0011
alternative D rejected LLM-merged deltas).

## Implementation strategy
- Strategy: tdd
- Rationale: a deterministic writer into governance docs + a new audit gate
  need RED-proven regression: every operation (ADDED/MODIFIED/REMOVED) proven on
  fixtures, fail-closed paths proven, idempotence proven by a second run, and
  the drift check proven both ways (untraced → finding; fully traced → CLEAN;
  empty canonical → no false positive).
- RED-proof obligation: before any edit, write the new suite + the docs-audit
  drift stanzas and run them on the pre-change tree; save the failing output to
  `docs/ai/tdd/delta-stage3-red.log` (delta-merge tests and drift tests FAIL;
  the empty-canonical no-op control and the existing-suite survival stanza pass
  pre-change by construction).

## Isolation and review
- Worktree: /Users/ales/Projects/aai-delta3, branch feat/delta-stage-3, base main.
- Base ref: main (56efb39 at branch creation).
- Inline review scope (explicit paths):
  - docs/specs/SPEC-0038-spec-delta-stage-3.md, docs/issues/CHANGE-0026-delta-stage-3.md
  - .aai/scripts/delta-merge.mjs (new — the merge engine + CLI)
  - .aai/scripts/lib/docs-model.mjs (only if a shared helper is genuinely needed;
    prefer reusing parseDeltasSection/parseRequirementsSection as-is)
  - .aai/scripts/lib/docs-audit-core.mjs (provenance drift check)
  - .aai/SKILL_PR.prompt.md (delta-merge ceremony step)
  - tests/skills/test-aai-delta-stage3.sh (new suite)
  - tests/skills/test-aai-docs-audit.sh (drift-check stanza)
  - docs/INDEX.md (regenerated)

## Design decisions

### D1 — `delta-merge.mjs` behavior (line-surgical, deterministic)
CLI: `node .aai/scripts/delta-merge.mjs --spec <path> [--root <dir>] [--check]`.
Reads the merging spec's `## Deltas` via `parseDeltasSection` (SPEC-0037). The
merging-spec ref written into `Provenance` is the spec's display id (its
`SPEC-000N` number when allocated, else its slug `id`). FAIL-CLOSED preconditions
(exit non-zero, ZERO writes, name the reason): any `violations` from
`parseDeltasSection` (the SPEC-0037 contract); a target `docs/canonical/<slug>.md`
that does not exist (a domain doc must exist first — RFC-0011: deltas stay
optional until a domain doc exists); a MODIFIED/REMOVED id absent from that doc's
`## Requirements`; an ADDED whose title collides with an existing requirement in
the domain. Otherwise apply, per delta, into the target's `## Requirements`:
- MODIFIED `REQ-<DOMAIN>-NNN`: replace that block's SHALL line and `- Scenario:`
  bullets with the delta's; set `Provenance: <merging-spec>`. Heading/title line
  updated to the delta's title.
- REMOVED `REQ-<DOMAIN>-NNN`: delete the whole block (heading + body). The id is
  retired permanently — never reused (SPEC-0034 D1); gaps are legal.
- ADDED `REQ-<DOMAIN>`: assign NNN = (max existing NNN in the domain doc) + 1,
  zero-padded to ≥3; append a new `### REQ-<DOMAIN>-NNN — <title>` block with the
  delta's SHALL + scenarios + `Provenance: <merging-spec>` at the END of the
  `## Requirements` section (stable append; existing block order untouched).
Writes are line-surgical (same discipline as state.mjs): only the touched
blocks' lines change; the rest of the file is byte-identical.

### D2 — idempotence and determinism
Re-running `delta-merge --spec X` after X already merged is byte-idempotent:
- MODIFIED/REMOVED are naturally idempotent (target already in final form; a
  REMOVED whose id is already gone is a satisfied post-condition, NOT a
  fail-closed "id absent" error when the block's `Provenance` history shows this
  spec — see below);
- ADDED is guarded: an ADDED is SKIPPED (not re-appended) when the domain doc
  already has a requirement whose `Provenance` == this merging spec AND whose
  title matches the delta's. So a second run adds nothing.
Determinism: no timestamps, no ordering by clock; deltas apply in document
order; NNN assignment is a pure function of the target doc's current max.
To keep idempotence and the "id absent" precondition consistent, the absent-id
check for MODIFIED/REMOVED is: absent AND not already retired-by-this-spec →
fail-closed; absent because THIS spec removed it on a prior run → no-op.

### D3 — docs-audit provenance drift check
docs-audit `--check` gains a check over every `docs/canonical/*.md`: parse
`## Requirements` (`parseRequirementsSection`); for each requirement, an empty/`—`
`Provenance` (`provenance === null`) is an `untraced-canonical-requirement`
finding, and a `Provenance` naming a spec id that resolves to no scanned doc is a
`broken-canonical-provenance` finding. Fully-traced canonical docs are CLEAN.
NO canonical docs (empty/absent `docs/canonical/`) → the check contributes
nothing (no false positive) — verified as a first-class control, since that is
this repo's live state.

### D4 — PR-ceremony wiring (the approved merge trigger)
`.aai/SKILL_PR.prompt.md` gains a step AFTER number allocation and before the
commit: for each in-scope merging spec that carries a `## Deltas` section, run
`delta-merge.mjs --spec <path>` so the canonical diff lands IN the PR (reviewable
— the RFC's chosen trigger over per-item flush). Fail-closed: if delta-merge
exits non-zero, STOP the ceremony (do not commit a partial canonical). The step
is documented as a no-op when the spec has no `## Deltas` section or the repo
has no `docs/canonical/`. The agent still never merges (operator-only).

### D5 — Single source of truth (reuse stages 1 & 2)
delta-merge consumes `parseDeltasSection` (SPEC-0037) for the source deltas and
`parseRequirementsSection` (SPEC-0034) to locate/validate target blocks and to
compute the per-domain max NNN. The drift check consumes
`parseRequirementsSection`. No grammar is re-expressed; the readers are the
contract.

### D6 — NB-1 (SPEC-0034 promoted): resolved by the drift gate
SPEC-0034 promoted NB-1 ("`docs-canon --phase2 --resync` does not re-render an
old five-section canonical when sources are unchanged") to "where the section
contract becomes a gate." That gate is D3: docs-audit now REPORTS an old-shape or
untraced canonical requirement, which is exactly the enforcement the promotion
asked for. NB-1's remaining part — resync AUTO-re-rendering a stale doc — is a
docs-canon UX convenience, NOT a correctness gap now that drift is reported and
the operator's sanctioned fix (delete + re-synthesize, SPEC-0034 D3) exists.
With `docs/canonical/` empty here there is zero live exposure; the auto-re-render
nicety is re-tracked as a docs-canon follow-up, explicitly out of this scope.

### D7 — Empty-canonical is the tested live state
Every merge and drift path has an empty-`docs/canonical/` control proving a
no-op / no-false-positive, because that is this repo's reality. The engine's real
behavior is proven on ISOLATED fixture repos (a synthesized canonical doc + a
spec with deltas), never by mutating this repo's (absent) canonical tree.

## Acceptance Criteria Mapping
- Maps to CHANGE AC-001 (merge engine)
  - Spec-AC-01: `delta-merge.mjs` applies ADDED/MODIFIED/REMOVED into a fixture
    `docs/canonical/<slug>.md` correctly (next-NNN, body replace, block delete,
    `Provenance` set to the merging spec); is FAIL-CLOSED (exit≠0, no writes) on
    a violation'd spec, a missing canonical doc, an absent MODIFIED/REMOVED id,
    and an ADDED title collision; a second run is byte-idempotent.
  - Verification: TEST-001, TEST-002, TEST-003.
- Maps to CHANGE AC-002 (drift check)
  - Spec-AC-02: docs-audit `--check` emits `untraced-canonical-requirement` for a
    fixture canonical requirement with empty `Provenance`, `broken-canonical-
    provenance` for one naming a non-existent spec, is CLEAN when every
    requirement traces, and contributes NOTHING when `docs/canonical/` is
    empty/absent (this repo stays CLEAN).
  - Verification: TEST-004, TEST-005.
- Maps to CHANGE AC-003 (wiring + flow intact + NB-1)
  - Spec-AC-03: SKILL_PR documents the delta-merge ceremony step (post-allocation,
    fail-closed, no-op when no Deltas/canonical); the delta-stage1/2, spec-lint,
    docs-audit, ceremony-levels suites pass; repo-wide `--check --strict` CLEAN;
    index idempotent; check-state OK; D6 records the NB-1 resolution. No stage-N
    token on any edited `.aai` surface (taxonomy guard).
  - Verification: TEST-006, TEST-007.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | delta-merge applies ADDED/MODIFIED/REMOVED; fail-closed; idempotent | done | TEST-001/002/003 RED→GREEN (docs/ai/tdd/delta-stage3-red.log, docs/ai/tdd/delta-stage3-green.log); .aai/scripts/delta-merge.mjs | tdd:2026-07-16 | ADDED next-NNN (retired ids not reused via tombstone), MODIFIED body/title/Provenance, REMOVED tombstone; all four fail-closed paths ZERO-write; 2nd run byte-identical |
| Spec-AC-02 | docs-audit provenance drift check; empty-canonical no-op           | done | TEST-004/005 RED→GREEN (docs/ai/tdd/delta-stage3-green.log); .aai/scripts/lib/docs-audit-core.mjs D3 | tdd:2026-07-16 | untraced/broken emitted + hard-fail under enforced/--strict; empty/absent docs/canonical/ contributes nothing; real repo `--check --strict` exit 0 CLEAN |
| Spec-AC-03 | ceremony wiring; flow intact; NB-1 resolved (D6); taxonomy clean   | done | TEST-006/007 (docs/ai/tdd/delta-stage3-green.log); .aai/SKILL_PR.prompt.md step 1c | tdd:2026-07-16 | SKILL_PR post-allocation fail-closed no-op-documented step; stage1/2 + spec-lint + docs-audit + hygiene suites green; taxonomy grep clean; index idempotent |

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                       | Description                                                                                                                | Status  |
|----------|------------|-------------|---------------------------------------------|--------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-delta-stage3.sh       | isolated fixture: a canonical doc + a spec with one ADDED/MODIFIED/REMOVED delta → delta-merge assigns next NNN, replaces the MODIFIED body, deletes the REMOVED block, writes Provenance; untouched lines byte-identical | planned |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-delta-stage3.sh       | fail-closed: a spec with a delta violation, a missing canonical doc, an absent MODIFIED/REMOVED id, an ADDED title collision → exit≠0, canonical byte-UNCHANGED, reason named | planned |
| TEST-003 | Spec-AC-01 | integration | tests/skills/test-aai-delta-stage3.sh       | idempotence: running delta-merge twice for the same spec leaves the canonical doc byte-identical after the second run (ADDED not duplicated; REMOVED-already-gone is a no-op, not an error) | planned |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh         | drift: a fixture canonical requirement with empty Provenance → `untraced-canonical-requirement`; one naming a non-existent spec → `broken-canonical-provenance`; fully-traced → CLEAN | planned |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh         | empty-canonical control: with no `docs/canonical/`, docs-audit `--check --strict` emits NO provenance finding (the real repo stays CLEAN) | planned |
| TEST-006 | Spec-AC-03 | unit        | tests/skills/test-aai-delta-stage3.sh       | SKILL_PR documents the delta-merge step (post-allocation, fail-closed, no-op-when-no-Deltas); no `stage N` token on any edited `.aai` surface | planned |
| TEST-007 | Spec-AC-03 | integration | tests/skills/test-aai-delta-stage3.sh       | seam survival: delta-stage1 + delta-stage2 + spec-lint + docs-audit suites pass post-change; strict audit CLEAN over the real repo | planned |

Seam analysis:
- Seam S1 — delta-merge consumes parseDeltasSection + parseRequirementsSection.
  Crossing test: TEST-001 drives the real CLI end-to-end on a fixture repo.
- Seam S2 — the drift check feeds docs-audit --check verdicts and the index.
  Crossing test: TEST-004 runs the real `--check` on a fixture; TEST-005 + the
  sweep confirm no false positive on the real (empty-canonical) repo.
- Seam S3 — the PR ceremony invokes delta-merge (SKILL_PR text). No automated
  test drives the human ceremony; TEST-006 asserts the documented contract and
  the fail-closed wording; the engine itself is covered by TEST-001..003.
- Residual risk (recorded): the ceremony step is documented, not executed by a
  test (prompt text). Mitigation: delta-merge is fully covered as a CLI; the
  step is a fail-closed one-liner (`delta-merge || STOP`).

## Constitution deviations
None.

Honest per-article check (docs/CONSTITUTION.md v1): Art. 1 — every AC has
executable verification; RED-proof recorded. Art. 2 — no speculative machinery;
the merge is the minimal deterministic writer the RFC mandates. Art. 3 — plain
mjs/markdown/bash. Art. 4 — fail-closed on every precondition, reasons named;
empty-canonical is a defined no-op. Art. 5 — additive: a new script + a new audit
check; no existing behavior changes (byte-identity of unrelated docs-audit
paths). Art. 6 — delta-merge writes docs/canonical/ only, never STATE. Art. 7 —
delta-merge writes files but NEVER commits or merges; it runs inside the
operator-owned PR ceremony, which still ends at `gh pr create`.

## Verification
- `bash tests/skills/test-aai-delta-stage3.sh` → exit 0 (all stanzas).
- `bash tests/skills/test-aai-docs-audit.sh` → exit 0 (drift stanza + regression).
- `bash tests/skills/test-aai-delta-stage1.sh` and `-stage2.sh` → exit 0 (reuse intact).
- `bash tests/skills/test-aai-spec-lint.sh` → exit 0.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0 CLEAN.
- `node .aai/scripts/generate-docs-index.mjs` twice → content idempotent.
- `node .aai/scripts/check-state.mjs docs/ai/STATE.yaml` → OK.
- Taxonomy grep: no `stage 1`/`stage-1`/`stage 2`/`stage-2`/`stage 3`/`stage-3`
  token on the edited `.aai` surfaces.

## Evidence contract
For each artifact record: ref_id delta-stage-3, Spec-AC and TEST-xxx links,
command, exit code, evidence path (docs/ai/tdd/delta-stage3-red.log,
docs/ai/tdd/delta-stage3-green.log), diff range when available.
