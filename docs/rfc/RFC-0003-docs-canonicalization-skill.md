---
id: RFC-0003
type: rfc
status: done
links:
  rfc: RFC-0002
  spec: SPEC-0002
  pr: []
  commits:
    - 8391ea2
---

# RFC-0003 — Docs Canonicalization Skill (`aai-docs-canon`)

## Context

### Problem or opportunity

Large AAI-consuming projects accumulate layered documentation: an original
intake (PRD/CHANGE/ISSUE) spawns a chain of specs, sub-specs, addendums, and
corrections that progressively amend or supersede the original intent. Over
time there is **no single "final" view** of what a feature actually does today.
The reader must reconstruct the current state by manually tracing breadcrumbs
across folders, status fields, and in-body deprecation notices.

A concrete example was measured in the consuming project
`/Users/ales/Projects/FiledHockey/fh-workspace/docs` (782 markdown files):

- **Umbrella IDs with no canonical doc:** 24 distinct files share
  `id: SPEC-CHANGE-010`. Finding "the current spec" requires reading the parent
  issue, filtering `status: done` vs `superseded`, and skipping deprecated
  iterations by hand.
- **Supersession is not machine-readable:** recorded only as
  `status: superseded`, free-text body notes
  (`DEPRECATED 2026-05-26 — SUPERSEDED BY ...`), and a limited INDEX.md table.
  There is no `canonical:`/`supersedes:`/`replaces:` frontmatter to follow
  forward or backward.
- **Cross-folder fragmentation:** one feature (e.g. person activation) is split
  across `/issues/`, `/requirements/`, `/specs/`, `/architecture/processes/`,
  and `/plans/` with no single index linking them.
- **In-place amendments without precedence:** addendums
  (`## Match list UX addendum (added 2026-06-06)`) are appended to docs with no
  "v2 / amended" signaling, so a reader cannot tell if a doc is complete as-is.

The result is a documentation set that is exhaustive for audit but unusable as a
working reference. The desired outcome: a **canonical, function-categorized
"current state" layer** that the team works against going forward, with the
original layered documents preserved aside as an auditable history and linked
bidirectionally.

### Drivers/constraints

- Must reuse existing AAI doc infrastructure: frontmatter (`id/type/status/
  links`), `docs-audit.mjs`, `generate-docs-index.mjs`, and the RFC-0002 docs
  hygiene model — not invent a parallel system.
- Originals must never be destroyed (consuming project convention:
  "shipped specs are never deleted" — preserve audit trail).
- Decisions buried in superseded docs are valuable and must be **harvested**,
  not just archived.
- Domain boundaries are project-specific and must be **human-approved**, not
  silently auto-chosen.
- Must be **idempotent and re-runnable** as documentation keeps growing.

### Prior art studied

- **OpenSpec / Spec-Driven Development** — separates `specs/` (canonical
  *current behavior*, source of truth) from `changes/` (proposed/in-flight
  changes). Directly maps to "work against the reworked layer, keep originals
  aside." https://intent-driven.dev/knowledge/openspec/
- **Diátaxis** (adopted by Canonical, Python) — every doc is exactly one of four
  types; used to restructure legacy docs into a predictable shape. Considered as
  a categorization axis but rejected as primary (it targets *end-user reader
  docs*, not spec-driven engineering docs).
  https://diataxis.fr/
- **Docs-as-Code / Live-Docs** — version-controlled docs in-repo, regenerated
  from source on change; reinforces the re-runnable, drift-detecting design.
  https://www.writethedocs.org/guide/docs-as-code/

## Proposal

### Recommended option

Build a new re-runnable AAI skill **`aai-docs-canon`** that produces and
maintains a **canonical documentation layer** in `docs/canonical/`, while
preserving and back-linking the original layered docs in `docs/_archive/`. This
is the **OpenSpec split adapted to AAI conventions** (canonical current-state
vs. preserved change history), categorized on a **hybrid axis** — one canonical
document **per functional domain** (the feature view that is currently missing),
each internally structured into **fixed layer sections** (Overview/Intent · UI ·
Processes · Data model · Superseded decisions) — with full **auto-synthesis**
gated by **human domain approval**.

The skill runs as a two-phase, idempotent pipeline:

**Phase 1 — Analyze & propose (human gate):**
1. Ingest a target doc set (path/glob). Parse frontmatter and body.
2. Build a **supersession/dependency graph**: detect umbrella IDs (N files,
   one ID), `status: superseded` chains, free-text `SUPERSEDED BY` / `DEPRECATED`
   / `addendum` markers, and PRD↔SPEC↔ISSUE cross-references.
3. **Cluster by functional domain.** AI *proposes* a domain map (e.g. "YouTube
   integration", "Person/membership", "Match lifecycle") with the source docs
   assigned to each, plus a confidence note and "unclear" bucket.
4. Emit the proposed domain map for **human approval** (HITL). The operator
   edits/approves the clustering before any synthesis or file moves.

**Phase 2 — Synthesize & canonicalize (auto):**
5. For each approved domain, **auto-synthesize a finished canonical document**
   that merges all live layers (applies addendums, drops superseded content)
   into a single current-state view, organized into a **fixed section
   structure** so each fragment is classified by layer:
   - `## Overview / Intent` — purpose and acceptance criteria (from PRD/CHANGE
     intake docs)
   - `## UI` — screens, navigation, access (from `SPEC-FE-*`, frontend specs)
   - `## Processes / Behavior` — runtime behavior and flows (from change specs,
     architecture processes)
   - `## Data model` — entities and relationships (from data-model docs)
   - `## Superseded decisions` — harvested audit trail (see step 6)

   This is the **hybrid axis**: the *document* is categorized by functional
   domain (the missing "feature view"), while *within* each document the content
   is categorized by layer (UI / process / data). It deliberately mirrors what
   the consuming project already does informally — `specs/` are feature-named
   while `architecture/{frontend,processes,data-model}/` are layer-split — and
   unifies both into one navigable artifact.
6. **Harvest superseded docs into the `## Superseded decisions` section** of the
   canonical doc (what was decided, why it changed, link to source), so the
   rationale survives even though the obsolete content does not.
7. Write each canonical doc to `docs/canonical/<domain>.md` with machine-readable
   provenance: `type: canonical`, `domain: <slug>`, and a `sources:` list of
   every contributing original doc.
8. Move originals to `docs/_archive/` (preserving relative structure), set their
   `status: archived`, and add a forward `canonical: docs/canonical/<domain>.md`
   pointer in frontmatter — making supersession finally machine-readable in both
   directions.
9. Regenerate the docs index (extend `generate-docs-index.mjs` to surface the
   canonical layer) and run `docs-audit.mjs --check --strict` on all outputs.

**Re-run / incremental mode:** on subsequent runs, only newly added or changed
source docs are diffed into their existing canonical domain; unchanged domains
are untouched. The skill reports **drift** (source docs that changed since the
canonical was last synthesized) so the canonical layer stays live.

### Rationale

- **Matches the user's mental model exactly:** final categorized view + originals
  kept aside + bidirectional links + work-forward-against-canonical.
- **Closes the exact machine-readability gap** found in the field
  (`canonical:`/`sources:` frontmatter that no current doc has).
- **Reuses, not replaces,** AAI infra (frontmatter, docs-audit, index generator,
  HITL, RFC-0002 hygiene model) — low conceptual surface area.
- **Hybrid axis (domain document × layer sections) over either pure axis.**
  Validated against the consuming project's real corpus: a pure *functional
  domain* axis answers "what does feature X do today?" but produces large docs
  that blur UI/process/data; a pure *layer* axis (UI/process/data) duplicates
  what `architecture/{frontend,processes,data-model}/` already provides and
  re-shreds each feature across folders — the exact fragmentation we are trying
  to remove, and it has no clean home for acceptance criteria. The hybrid keeps
  the missing **feature view** as the primary unit while giving consistent
  in-document **layer navigation** and a home for intent/AC.
- **Human gate on clustering + auto-synthesis after** balances safety (the
  risky judgment call is domain boundaries, which the human owns) with speed
  (the mechanical merge is automated).

## Alternatives Considered

- **Option A1 — Pure functional-domain axis (no fixed layer sections).** One doc
  per feature, free-form inside. Pros: simplest synthesis. Cons: large docs blur
  UI/process/data with no consistent navigation. *Folded into the hybrid as the
  primary axis, but with mandatory layer sections added.*
- **Option A2 — Pure layer axis (UI / process / data-model).** Canonical docs
  grouped by layer. Pros: single place for "all screens" / "the data model".
  Cons: validated against the real corpus — largely duplicates the existing
  `architecture/{frontend,processes,data-model}/` split, re-fragments each
  feature across three folders (the pain we are removing), and leaves
  intent/acceptance-criteria homeless. *Rejected; retained only as the
  intra-document section scheme.*
- **Option A3 — Diátaxis 4-type as the primary axis.** Pros: established
  standard. Cons: designed for end-user reader docs, not spec-driven engineering
  artifacts; obscures feature boundaries. *Rejected as primary.*
- **Option B — In-place status flip only (no canonical layer).** Just add
  `canonical:`/`supersedes:` frontmatter and a richer INDEX, leaving all docs in
  their folders. Pros: minimal movement, smallest change. Cons: folders stay
  mixed old+new; there is still no single "final" document to read per feature —
  the core pain (no consolidated view) is not solved.
- **Option C — One-shot migration script (not a skill).** A single big cleanup,
  then maintain canonical docs by hand. Pros: simplest to build. Cons: the
  layering problem returns as soon as new docs land; no drift detection. *Rejected
  in favor of a re-runnable skill.*
- **Option D — Full OpenSpec rename (`docs/specs/` = canonical, `docs/changes/`
  = history).** Pros: closest to the published standard. Cons: large disruption
  to existing AAI folder conventions and every consuming project; `docs/canonical/`
  + `docs/_archive/` achieves the same separation additively. *Rejected for
  compatibility.*

## Consequences

### Technical impact

- New skill `aai-docs-canon` (skill manifest + prompt + helper script under
  `.aai/scripts/`), following the existing skill pattern (cf. `aai-docs-audit`).
- New doc type `canonical` and new frontmatter fields (`domain`, `sources`,
  `canonical`) added to the docs schema / templates and to `docs-audit.mjs`
  validation.
- `generate-docs-index.mjs` extended to index `docs/canonical/` and to treat
  `docs/_archive/` as preserved-but-not-active.
- New conventional directories: `docs/canonical/`, `docs/_archive/`.

### Operational impact

- Adds a HITL approval step (domain map) to the canonicalization run.
- Going forward, contributors author/update intake docs as today; the canonical
  layer is regenerated by re-running the skill, which reports drift.

### Migration/compatibility notes

- Additive: existing folders and IDs are untouched until a run moves originals to
  `docs/_archive/` (a tracked, reviewable git move). Consuming projects opt in by
  running the skill; not running it changes nothing.
- The `canonical:` back-pointer makes any future tooling able to resolve "current
  doc for this archived spec" deterministically.

## Risks

- **Merge fidelity (auto-synthesis loses or invents content).** Mitigations:
  every canonical doc carries a `sources:` provenance list and a harvested
  "Superseded decisions" section linking back to originals; originals are
  preserved in `docs/_archive/` (nothing is destroyed); `docs-audit.mjs --strict`
  gates output; drift mode re-flags divergence. *Operator chose full
  auto-synthesis over per-doc diff review for speed — provenance + preserved
  originals are the safety net; a `--review` diff mode should be offered as an
  opt-in flag.*
- **Domain clustering wrong/unstable across runs.** Mitigation: human approves
  the map each run; approved domain map is persisted so re-runs are stable.
- **Scope creep into non-spec folders** (`ai/`, `plans/`, `architecture/`).
  Mitigation: target set is an explicit input glob; default to
  `{issues,requirements,specs,rfc}` like the current index.
- **Archive churn in git history** from large moves. Mitigation: moves are
  batched per domain and committed with clear provenance.

## Open Questions

- The hybrid section scheme is fixed (Overview/Intent · UI · Processes · Data
  model · Superseded decisions). Open: when a domain is very large (e.g. YouTube
  integration's 24 sub-specs), should a layer section be allowed to split into
  per-concern child files under `docs/canonical/<domain>/`? Lean: single doc with
  sections, split only past a size threshold.
- Should `--review` (per-doc merge diff approval) be a first-class mode in v1 or
  a fast-follow, given the operator preference for full auto-synthesis?
- How should the skill relate to `aai-docs-audit` — invoke it as the drift/
  hygiene gate, or remain independent and compose in the loop?
- Naming: `aai-docs-canon` vs `aai-docs-consolidate` vs `aai-canonicalize`
  (latter already exists for repo structure — avoid collision).

## Approvals

- Required approvers (roles/names): Project owner (ales@holubec.net); AAI
  maintainer.

## Notes

- Decisions captured during intake (2026-06-25): categorization axis = **hybrid**
  (functional domain per document × fixed layer sections within — Overview/Intent
  · UI · Processes · Data model · Superseded decisions), chosen after comparing
  pure-domain vs pure-layer on the real fh-workspace corpus; domain discovery =
  AI-proposed, human-approved; superseded docs = harvested into audit trail;
  synthesis = full auto after domain approval; location = `docs/canonical/` +
  `docs/_archive/` with `canonical:` pointer; scope = re-runnable skill with
  incremental update and drift detection.
- Follow-on: a SPEC document should define the frontmatter schema additions, the
  supersession-graph heuristics, and the skill's CLI/HITL contract before
  implementation.
