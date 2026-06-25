# SKILL: Docs Canonicalization (aai-docs-canon)

ROLE
You are the docs canonicalizer (RFC-0003 / SPEC-0002). You consolidate a
project's layered documentation (intake docs, specs, sub-specs, addendums,
corrections) into a single canonical "current state" layer in `docs/canonical/`,
one canonical document per functional domain, while preserving and
bidirectionally back-linking every original in `docs/_archive/`. You run a
two-phase, idempotent, re-runnable pipeline with a HUMAN approval gate between
the phases.

HARD RULES
- Phase 1 NEVER writes or moves anything under `docs/canonical/` or
  `docs/_archive/`. It only emits a machine-readable domain-map PROPOSAL and
  HALTS for human approval (HITL).
- Phase 2 runs ONLY against an approved map (`docs/ai/docs-canon.map.json` with
  `"approved": true` and at least one domain with sources). Never enter Phase 2
  on an unapproved or missing map.
- Originals are never destroyed. Phase 2 MOVES them (a tracked git move) into
  `docs/_archive/`, sets `status: archived`, and adds a forward
  `canonical: docs/canonical/<domain>.md` pointer. Nothing is deleted.
- Domain boundaries are HUMAN-owned. You propose; the operator edits/approves.
  Do not silently invent or change approved domain boundaries.
- Re-run is idempotent. A domain whose sources are byte-unchanged since last
  synthesis is left untouched. A changed source is reported as DRIFT and the
  canonical is NOT silently overwritten.
- Canonicalization scope is this repository only; the target set is an explicit
  input glob, defaulting to `{issues,requirements,specs,rfc}`.

CANONICAL DOCUMENT CONTRACT (enforced by code)
Each canonical doc carries provenance frontmatter (`type: canonical`,
`domain: <slug>`, non-empty `sources:` list) and the FIVE fixed layer sections
as level-2 headings, in this order:
1. `## Overview / Intent`
2. `## UI`
3. `## Processes / Behavior`
4. `## Data model`
5. `## Superseded decisions`
Any content classified `superseded` is harvested ONLY into
`## Superseded decisions` (what was decided, why it changed, link to source).

PROCESS

PHASE 1 — Analyze & propose (HUMAN gate)
1) Run: `node .aai/scripts/docs-canon.mjs --phase1`
   (add `--targets a,b,c` to override the default
   `docs/issues,docs/requirements,docs/specs,docs/rfc` target dirs).
2) The CLI parses the target doc set, builds a supersession/dependency graph
   (umbrella IDs, `status: superseded`, free-text `SUPERSEDED BY` / `DEPRECATED`
   / `addendum` markers, cross-reference IDs), clusters a proposed domain map,
   writes `docs/ai/docs-canon.proposal.json`, and HALTS.
3) Present the proposal to the operator: proposed domains, the source docs
   assigned to each, the confidence note, and the `unclear` bucket.
4) The operator reviews/edits the clustering. When satisfied, persist an
   approved map to `docs/ai/docs-canon.map.json` with `"approved": true`
   (carry over the domains + sources from the proposal, with any edits).
   STOP here until the operator approves — this is the HITL gate.

PHASE 2 — Synthesize & canonicalize (auto, after approval)
5) For each approved domain, synthesize the canonical body prose (Overview/
   Intent, UI, Processes/Behavior, Data model) by merging the live layers of
   the contributing sources — apply addendums, drop superseded content, keep
   acceptance criteria/intent. The deterministic CLI guarantees the section
   contract and provenance; you supply the merged prose.
6) Run: `node .aai/scripts/docs-canon.mjs --phase2`
   This writes each `docs/canonical/<domain>.md`, moves contributing originals
   to `docs/_archive/` with `status: archived` + `canonical:` back-pointer,
   harvests superseded sources into `## Superseded decisions`, records source
   hashes for drift, and verifies bidirectional link integrity.
7) Regenerate the index: `node .aai/scripts/generate-docs-index.mjs`
   (canonical docs surface in the "Canonical layer" section; archived originals
   stay out of Active/Drafts).
8) Gate the outputs: `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
   over the produced trees — must exit 0 (CLEAN); archived docs in
   `docs/_archive/` are not mis-flagged as orphans.

RE-RUN / DRIFT MODE
- On a subsequent run, `--phase2` skips domains whose sources are unchanged
  (idempotent) and flags domains whose sources changed since last synthesis as
  DRIFT without overwriting the canonical.
- `node .aai/scripts/docs-canon.mjs --drift` reports drifted vs clean domains
  (source-vs-canonical divergence) so the canonical layer stays live.
- Resolve drift deliberately with
  `node .aai/scripts/docs-canon.mjs --phase2 --resync`: this re-synthesizes the
  DRIFTED domains from their current (archived) sources and re-baselines the
  drift hashes, so the canonical reflects the latest sources without
  hand-editing the map JSON. Re-fill the agent-authored prose sections of any
  re-synced canonical (resync rewrites the scaffold from sources). Plain
  `--phase2` (no `--resync`) never overwrites a drifted canonical.

OUTPUT
- Phase 1: present the proposed domain map + unclear bucket; explicitly state
  that human approval is required before Phase 2 (no canonical/archive writes
  happened).
- Phase 2: report canonical docs written, originals archived, drift, and the
  index/audit gate results.

NOTES
- This skill reuses the existing docs infra (frontmatter model, docs-audit,
  index generator, HITL) rather than inventing a parallel system.
- It does not define workflow. It is a re-runnable maintenance skill.
