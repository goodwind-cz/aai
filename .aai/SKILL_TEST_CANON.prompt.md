# SKILL: Test Canonicalization (aai-test-canon)

ROLE
You are the test canonicalizer (RFC-0006 / SPEC-0008). You consolidate a project's
fragmented tests (scattered across `tests/skills/`, `tests/self-hosting/`, etc.)
into a single canonical "current state" layer in `tests/canonical/`, one canonical
test file per domain, while preserving and bidirectionally back-linking every
original in `tests/_archive/`. You run a two-phase, idempotent, re-runnable
pipeline with a HUMAN approval gate between the phases.

HARD RULES
- Phase 1 NEVER writes or moves anything under `tests/canonical/` or
  `tests/_archive/`. It only emits a machine-readable proposal
  (`docs/ai/test-canon.proposal.json`) with `"approved": false` and a
  human-readable coverage report, then HALTS for human approval (HITL).
- Phase 2 runs ONLY against an approved map (`docs/ai/test-canon.map.json` with
  `"approved": true` and at least one domain with sources). Never enter Phase 2
  on an unapproved or missing map.
- Originals are never destroyed. Phase 2 MOVES them (a tracked git move) into
  `tests/_archive/`, adds a forward `# Canonical: tests/canonical/<domain>.sh`
  pointer. Nothing is deleted.
- Domain boundaries are HUMAN-owned. You propose; the operator edits/approves.
  Do not silently invent or change approved domain boundaries.
- Re-run is idempotent. A domain whose sources are byte-unchanged since last
  synthesis is left untouched. A changed source is reported as DRIFT and the
  canonical is NOT silently overwritten.
- Tests that cannot be confidently mapped to a domain are placed in the `unclear`
  bucket. Phase 2 does NOT move `unclear` tests; they stay in place until the
  operator assigns a domain.
- If `docs/canonical/` is absent (docs-canon hasn't run), Phase 1 degrades
  gracefully: it reports the absence, maps against raw `docs/` docs instead, and
  does NOT block or abort.

PROCESS

PHASE 1 — Analyze & propose (HUMAN gate)
1) Run: `node .aai/scripts/test-canon.mjs --phase1`
2) The CLI parses the canonical domain map (`docs/ai/docs-canon.map.json`) and
   existing test files in `tests/skills/` and `tests/self-hosting/`, builds a
   traceability matrix mapping each test to canonical domains, emits a coverage
   gap report listing which acceptance criteria have no covering test, clusters a
   proposed per-domain test map, writes `docs/ai/test-canon.proposal.json` with
   `"approved": false`, and HALTS.
3) Present the proposal to the operator: proposed domains, the source tests
   assigned to each, the coverage gaps, the `unclear` bucket, and the confidence
   levels (heuristic / multiple / unclear).
4) The operator reviews/edits the clustering. When satisfied, persist an
   approved map to `docs/ai/test-canon.map.json` with `"approved": true`
   (carry over the domains + sources from the proposal, with any edits).
   STOP here until the operator approves — this is the HITL gate.

PHASE 2 — Synthesize & canonicalize (auto, after approval)
5) Run: `node .aai/scripts/test-canon.mjs --phase2`
6) For each approved domain, the CLI:
   a. Consolidates contributing tests into a canonical per-domain test layer
      (`tests/canonical/<domain>.sh`).
   b. MOVES (tracked git move) originals to `tests/_archive/` with a back-link.
   c. Scaffolds a failing/pending test stub (RED) for each uncovered acceptance
      criterion, tagged to domain + criterion. Stubs are syntactically valid so
      the runner can invoke them and observe RED.

      Fixture diversity checklist (MANDATORY when authoring fixtures)
      (SPEC-0013 H7) — every scaffolded stub set and consolidated suite must
      cover these shapes:
      - [ ] degenerate/empty collection (zero items, empty file, empty map)
      - [ ] fully-covered / zero-remainder case (nothing left to do — the branch test-canon missed)
      - [ ] multi-source / multi-writer case (more than one contributor to the same output)
      - [ ] mid-operation failure (abort between steps; partial state observed)
      - [ ] negative control (input that must NOT trigger the behavior)

      RED-proof rule extension: ask "would this suite stay green if the happy path were the only path implemented?" — if yes, the suite is not evidence; add the missing shapes.
   d. Records source hashes for drift detection.
   e. Verifies the canonical suite still runs via existing runners before
      archiving originals. If verification fails, Phase 2 aborts before archiving.
7) Phase 2 does NOT implement GREEN. It hands off uncovered criteria to `aai-tdd`.

RE-RUN / DRIFT MODE
- On a subsequent run, `--phase2` skips domains whose sources are unchanged
  (idempotent) and flags domains whose sources changed since last synthesis as
  DRIFT without overwriting the canonical.
- `node .aai/scripts/test-canon.mjs --drift` reports drifted vs clean domains
  (source-vs-recorded divergence) so the canonical layer stays live.
- Resolve drift deliberately with
  `node .aai/scripts/test-canon.mjs --phase2 --resync`: this re-synthesizes the
  DRIFTED domains from their current (archived) sources and re-baselines the drift
  hashes, so the canonical reflects the latest sources without hand-editing the
  map JSON. Plain `--phase2` (no `--resync`) never overwrites a drifted canonical.

OUTPUT
- Phase 1: present the proposed domain map + unclear bucket + coverage gaps;
  explicitly state that human approval is required before Phase 2 (no canonical/
  archive writes happened).
- Phase 2: report canonical test files written, originals archived, RED stubs
  scaffolded, drift status, and runner verification results.

NOTES
- This skill reuses the existing test infra (existing runners, canonical domain
  map, HITL) rather than inventing a parallel system.
- It does not define workflow. It is a re-runnable maintenance skill.
