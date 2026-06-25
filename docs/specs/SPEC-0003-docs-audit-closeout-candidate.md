---
id: SPEC-0003
type: spec
status: done
links:
  requirement: null
  rfc: RFC-0002
  change: CHANGE-0004
  pr: []
  commits: []
---

# SPEC-0003 — docs-audit parent closeout-candidate detection (CHANGE-0004)

SPEC-FROZEN: true

## Links
- Change request: docs/issues/CHANGE-0004-docs-audit-parent-closeout-candidate.md
- Parent RFC (hygiene authority): docs/rfc/RFC-0002-docs-hygiene-and-drift-audit.md
- Prior art (verify mode that retro-closed RFC-0001): docs/issues/CHANGE-0003-docs-audit-verify-mode.md
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written / frozen for implementation, work not yet started
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Problem (WHAT/WHY lives in CHANGE-0004)
The loop roles advance a SPEC to `done`, but nothing advances the originating
RFC/PRD. The parent stays non-terminal and is bucketed under "Active
(implementing)" long after the work shipped (observed: RFC-0001 closed
retroactively in e838b43; RFC-0003 left `proposed` after SPEC-0002 reached
`done`). This spec adds a READ-ONLY hygiene classification that surfaces such
parents as `closeout-candidate` so a human can close them. It never auto-closes.

## Design decisions (load-bearing — read before implementing)
1. NO existing parent->spec resolver. The engine in
   `.aai/scripts/lib/docs-audit-core.mjs` classifies every doc independently;
   `fm.links.spec` / `fm.links.rfc` are parsed by `parseFrontmatter` but never
   used relationally. This change ADDS a resolver. It must reuse the existing
   per-doc id index (the `docs[]` array already built in `runAudit`, keyed by
   `doc.id`) and the existing `asList()` helper from `docs-model.mjs` to read
   link lists. Do NOT add a second filesystem scan or a parallel id parser.
2. The detection runs as a POST-CLASSIFICATION pass (after the per-doc loop, like
   the existing `backlogDoneClaims` pass) so that every linked spec's status is
   already resolved regardless of scan order.
3. Parent scope is `type ∈ {rfc, prd}` ONLY. `change`-type docs also carry
   `links.spec` (CHANGE-0001/0002/0003 all link the many-to-one SPEC-0001) and
   would create false positives; the intake explicitly scopes the parent to
   RFC/PRD. This is the primary false-positive guard.
4. Non-terminal parent statuses that can be candidates: `proposed`, `accepted`,
   `implementing` (per CHANGE-0004 AC-001). `draft` is excluded (parent not yet
   ready). Terminal statuses `done | rejected | superseded | deferred` are never
   candidates.
5. Linked-spec resolution is the UNION of:
   - forward: `asList(parent.fm.links.spec)`
   - reverse: any scanned `type: spec` doc whose `fm.links.rfc` or
     `fm.links.requirement` equals the parent id.
6. A parent is flagged iff it resolves AT LEAST ONE linked spec AND EVERY
   resolved linked spec has `status: done`. If any linked spec id cannot be
   resolved to a scanned doc (e.g. a scoped `--path` run), the parent is NOT
   flagged (cannot prove all-done) — avoids false positives.
7. Report-only. The closeout-candidate result is NOT added to `hardFail` and NOT
   added to the `needsTriage` count. `--check` / `--check --strict` exit codes
   are unchanged by this classification. It renders in its own digest section
   (and is available to `--list`/`--check` stdout), never as a `--check`
   failure, honoring "audit reports; operator decides".

## Implementation strategy
- Strategy: tdd
- Rationale: touches the shared docs-audit hygiene engine consumed by intake
  gating, loop ticks, and CI; introduces a new data-classification with real
  false-positive and gate-neutrality risk. RED-proof is mandatory per AC. The
  negative cases (AC-002/003/005) are self-evaluation traps — an "is NOT
  flagged" assertion passes trivially before the feature exists — so each
  negative test embeds a positive control parent in the same fixture; the test
  fails RED on the control before the engine change and only goes GREEN once
  flagging works. TDD is the discipline that makes those RED states real.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: small, additive, single-module change (one engine pass +
  one CLI section + one test file) on the existing feature branch
  `feat/docs-audit-closeout-candidate`; no schema, migration, or protected
  workflow rewrite; report-only so no behavior change to existing gates.
- User decision: inline (already recorded in STATE.yaml worktree.user_decision)
- Base ref: main
- Worktree branch/path: n/a (inline on feat/docs-audit-closeout-candidate)
- Inline review scope:
  - `.aai/scripts/lib/docs-audit-core.mjs`
  - `.aai/scripts/docs-audit.mjs`
  - `tests/skills/test-aai-docs-audit.sh`
  - `docs/specs/SPEC-0003-docs-audit-closeout-candidate.md`
  - `docs/issues/CHANGE-0004-docs-audit-parent-closeout-candidate.md` (links.spec)

## Acceptance Criteria Mapping

- Maps to: CHANGE-0004 AC-001
  - Spec-AC-01: `runAudit` produces a `closeoutCandidates` result (and the CLI a
    "Closeout candidates" digest section) for every non-terminal parent
    (`type ∈ {rfc,prd}`, `status ∈ {proposed,accepted,implementing}`) whose
    every resolved linked spec is `done`, listing the parent id and the
    satisfying spec id(s). Resolution = `asList(links.spec)` ∪ reverse
    `links.rfc`/`links.requirement`, over the existing doc-id index.
  - Verification: `bash tests/skills/test-aai-docs-audit.sh` (TEST-001);
    `node .aai/scripts/docs-audit.mjs --no-event` over a fixture with
    RFC(proposed)+SPEC(done) prints the closeout-candidate section naming both ids.

- Maps to: CHANGE-0004 AC-002
  - Spec-AC-02: A non-terminal parent with at least one resolved linked spec NOT
    `done` (or any unresolvable linked spec id) is NOT flagged.
  - Verification: TEST-002.

- Maps to: CHANGE-0004 AC-003
  - Spec-AC-03: A parent in a terminal status (`done|rejected|superseded|
    deferred`) or in `draft` is never flagged, even when all linked specs are done.
  - Verification: TEST-003.

- Maps to: CHANGE-0004 AC-004
  - Spec-AC-04: Running the audit (including when closeout-candidates exist)
    mutates no document file — no frontmatter write outside operator-approved
    remediate mode.
  - Verification: TEST-004 (git working-tree / file-hash unchanged before vs after).

- Maps to: CHANGE-0004 AC-005
  - Spec-AC-05: No new false positives — docs with no `links.spec` and no parent
    relationship, `change`-type docs that link an all-done spec, and parents
    with an unresolvable linked spec id are all NOT flagged.
  - Spec-AC-06: The classification is report-only — it does not change the
    `--check` / `--check --strict` exit code (not part of `hardFail`/
    `needsTriage`); the existing docs-audit suite still passes except the one
    known pre-existing failure `test_index_continue_on_error` (unrelated to this
    change, present on clean main).
  - Verification: TEST-005 (Spec-AC-05), TEST-006 (Spec-AC-06).

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | Non-terminal rfc/prd parent with all linked specs done is flagged closeout-candidate; lists parent + satisfying spec id(s); resolver reuses doc-id index + asList | done | TEST-001 PASS bash tests/skills/test-aai-docs-audit.sh 2026-06-25T20:53Z (29 PASS/1 pre-existing fail); RED: docs/ai/tdd/red-closeout-20260625T205016Z.log; GREEN: docs/ai/tdd/green-closeout-20260625T205100Z.log; Validation: claude-sonnet-4-6 2026-06-25T21:01Z | TDD | core case 1 (positive); independently validated |
| Spec-AC-02 | Parent with any linked spec not done, or any unresolvable spec id, is NOT flagged | done | TEST-002 PASS 2026-06-25T20:53Z; positive-control RFC-0010 asserted flagged (anti-tautology confirmed); Validation: claude-sonnet-4-6 | TDD | core case 2; positive-control RED-proofed |
| Spec-AC-03 | Terminal (done/rejected/superseded/deferred) or draft parent is never flagged | done | TEST-003 PASS 2026-06-25T20:53Z; RFC-0030/RFC-0032/RFC-0034 NOT flagged; RFC-0010 positive-control IS flagged; Validation: claude-sonnet-4-6 | TDD | core case 3 |
| Spec-AC-04 | Audit run makes zero doc-file mutations even when candidates exist (read-only) | done | TEST-004 PASS 2026-06-25T20:53Z; shasum bb68cd5f unchanged before/after; git porcelain clean; Validation: claude-sonnet-4-6 | TDD | independent hash verification |
| Spec-AC-05 | No new false positives: no-link docs, change-type docs, unresolvable links | done | TEST-005 PASS 2026-06-25T20:53Z; RFC-0050/CHANGE-0050/RFC-0052 NOT flagged; RFC-0010 positive-control IS flagged; real-repo Closeout candidates: 0; Validation: claude-sonnet-4-6 | TDD | parent scope = rfc/prd only |
| Spec-AC-06 | Report-only: does not alter --check/--strict exit code; existing suite passes except known test_index_continue_on_error | done | TEST-006 PASS; --check --strict --no-event exit 0 real-repo 2026-06-25T21:01Z; pre-existing fail confirmed on stashed main (EXIT_CODE=1 same test); Validation: claude-sonnet-4-6 | TDD | gate-neutral seam confirmed |

## Implementation plan
- Components/modules affected:
  - `.aai/scripts/lib/docs-audit-core.mjs`: add a post-classification pass in
    `runAudit` that builds an `id -> doc` map from `docs[]`, computes
    `closeoutCandidates` (array of `{ id, rel, status, specs: [doneSpecId...] }`),
    and returns it (and a `counts.closeoutCandidates` integer) WITHOUT touching
    `hardFail`/`needsTriage`. Import `asList` from `docs-model.mjs`. Add a
    `suggestedStep`-style next-step string ("advance <PARENT> to done/accepted;
    record the implementing commit").
  - `.aai/scripts/docs-audit.mjs`: render a "Closeout candidates" section
    (parent id, status, satisfying spec id(s), suggested step) inside the
    existing `if (!args.quick)` block; never feed it into the exit-code path.
  - `tests/skills/test-aai-docs-audit.sh`: add TEST-001..006 as new
    `test_*` functions and call them in `main()` BEFORE
    `test_index_continue_on_error` (the suite uses `log_fail`/`set -e` and stops
    at the first failure, so anything after the known-failing test never runs).
- Data flows: read-only frontmatter (`fm.links.spec`, `fm.links.rfc`,
  `fm.links.requirement`, `fm.type`, `doc.status`) already parsed during the
  per-doc loop; no git probes required, so the pass is cheap and quick-safe.
- Edge cases:
  - inline-array `spec: [SPEC-0001, SPEC-0002]` under `links` is parsed by
    `parseFrontmatter` as a string; `asList` normalizes it.
  - scoped `--path` runs where a linked spec is outside the scan set =>
    unresolvable => not flagged.
  - reverse-link parent that does not itself list `links.spec` (RFC lists spec
    AND spec lists rfc both supported).
  - a parent with zero resolved specs => not flagged (no false positive).

## Seam analysis
SEAM-1 (engine -> shared CLI exit-code gate): the new classification is produced
by the engine that backs intake gating (`--strict --path`), loop ticks
(`--quick`), and CI (`--check`). The risk is that surfacing a closeout-candidate
inadvertently changes a gate's exit code. TEST-006 crosses this seam
end-to-end: it produces a real closeout-candidate on one side (fixture
RFC+SPEC) and asserts the actual gate result on the other (`--check --strict`
exit 0 AND the section present) — not two mocked unit checks.

SEAM-2 (engine -> index generator): `generate-docs-index.mjs` consumes the same
`docs-model`/audit lib. This change does not modify the index generator and adds
no field it must render; residual risk is low. The existing
`test_index_sections_and_idempotence` regression (run by TEST-006's suite
execution) guards index stability.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                   | Description | Status |
|----------|------------|-------------|----------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | RFC(proposed) + linked SPEC(done): digest "Closeout candidates" section names the RFC and the done spec id | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh | RFC(implementing) with 2 linked specs (1 done, 1 implementing) NOT flagged; positive-control RFC in same fixture IS flagged (RED-proof) | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh | done parent + all-done specs NOT flagged; superseded and draft parents NOT flagged; positive-control parent IS flagged (RED-proof) | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh | file hashes / `git status --porcelain docs` identical before vs after an audit run over the closeout fixture | green |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-docs-audit.sh | no-link doc, change-type doc linking an all-done spec, and parent with unresolvable spec id all NOT flagged; positive-control IS flagged (RED-proof) | green |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-docs-audit.sh | seam: `--check --strict --no-event` over closeout fixture exits 0 AND section present; full suite pass count preserved except known test_index_continue_on_error | green |
| TEST-007 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | post-review WARN-1: reverse-ONLY association (parent has no links.spec; child names it via links.rfc) is flagged — independently exercises the reverse-resolution path; proven non-tautological by mutation (disabling the reverse block fails this test) | green |
| TEST-008 | Spec-AC-05 | integration | tests/skills/test-aai-docs-audit.sh | post-review INFO-1: forward links.spec naming a NON-spec done doc (a done CHANGE) is NOT flagged — resolver now requires every resolved target to be type spec; positive control IS flagged (RED-proof) | green |

RED-proof obligation (all AC-gating tests, regardless of strategy):
- TEST-001 fails before the engine change because the "Closeout candidates"
  section / `closeoutCandidates` result does not exist yet.
- TEST-002/003/005 are negative assertions and would pass trivially without the
  feature; each therefore embeds a POSITIVE-CONTROL parent in the same fixture
  and asserts it IS flagged. Pre-change the control assertion fails (RED);
  post-change the control is flagged and the negatives hold (GREEN). This is the
  required guard against the self-evaluation trap.
- TEST-004/006 also assert the section is present for the positive fixture, so
  they too observe a genuine RED before implementation.

## Verification
- `bash tests/skills/test-aai-docs-audit.sh` — TEST-001..006 green; pre-existing
  pass set preserved (only `test_index_continue_on_error` known-fails, as on
  clean main).
- `node .aai/scripts/docs-audit.mjs --no-event` over a fixture with
  RFC(proposed)+SPEC(done) prints a "Closeout candidates" section naming both ids.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` over the same
  fixture exits 0 (report-only; gate unaffected).
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id (CHANGE-0004 / SPEC-0003)
- Spec-AC and TEST-xxx links
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY (CHANGE-0004 owns WHAT/WHY).
This document does not define workflow.

Post-review remediation (code review, 2026-06-25):
- WARN-1 — added TEST-007 covering the reverse-only association (a done spec's
  `links.rfc` reaching a parent that has no forward `links.spec`). Previously
  every fixture duplicated the reverse link with a forward one, so the reverse
  resolution path was never independently exercised. Proven non-tautological by
  a mutation check (disabling the reverse block fails TEST-007).
- INFO-1 — the resolver now requires every resolved linked-spec id to be an
  actual `type: spec` doc, not merely any done doc. A misfiled forward
  `links.spec` naming a non-spec done doc (e.g. a done CHANGE) no longer
  satisfies "all linked specs done". Covered by TEST-008 (RED-proofed).
