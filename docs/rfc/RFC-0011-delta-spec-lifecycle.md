---
id: delta-spec-lifecycle
type: rfc
number: 11
status: accepted
links:
  research: RES-0001
  spec: null
  pr: []
  commits: []
---

# RFC — Delta-Spec Lifecycle: Prevent Doc Sprawl by Construction

## Context

### Problem or opportunity
AAI's doc corpus grows one full document per change (this repo: 70 docs, 30
specs, after ~3 weeks of use). There is no single "current state" view per
feature — docs-canon (RFC-0003) and docs-audit (RFC-0002) exist to REMEDIATE
that sprawl after the fact. RES-0001 F5: OpenSpec prevents it by
construction — a change carries DELTAS (ADDED/MODIFIED/REMOVED requirements)
against a canonical per-domain spec; archiving the change merges the deltas
forward into the canonical layer automatically, and the change folder
remains as dated history. AAI already owns the target shape: docs/canonical/
(RFC-0003) and docs/_archive/ exist.

### Drivers/constraints
- Must not invalidate the current flow (intake -> SPEC -> pipeline): deltas
  change what a SPEC CONTAINS and what CLOSE does, not the gates.
- Slug/number identity (SPEC-0015), ceremony levels (SPEC-0030), spec-lint
  (in flight), and the docs-audit machinery must all keep working — the SPEC
  format change is the highest-coupling move in the repo; L-sized for a
  reason.
- Tri-platform, file-based, deterministic merge (script, not LLM).

## Proposal

### Recommended option
Three-stage adoption, each independently shippable:
1. **Canonical layer becomes authoritative per domain** (exists via
   docs-canon; formalize: every domain doc carries a Requirements section
   with stable REQ ids).
2. **New specs gain an optional `## Deltas` section** declaring
   ADDED/MODIFIED/REMOVED requirement blocks against named canonical docs
   (spec-lint validates shape; legacy specs unaffected).
3. **Close-time merge**: a new `delta-merge.mjs` (line-surgical, same
   discipline as state-engine) applies the deltas into docs/canonical/ at
   work-item closeout (flush step or PR ceremony), archives nothing new —
   the numbered spec IS the history. docs-audit gains a drift check:
   canonical requirement blocks must trace to a merging spec.

### Rationale
Prevention beats remediation (F5); the canonical layer finally gets a
mechanical reason to stay current; full-doc history remains (specs are
immutable dated records); zero disruption for changes that do not touch
canonical requirements (Deltas optional).

## Alternatives Considered
- A: status quo + periodic docs-canon runs — rejected: remediation-only,
  canonical layer decays between runs.
- C: OpenSpec verbatim (change folders + archive move) — rejected: replaces
  AAI's numbered-doc identity and ceremony; too invasive.
- D: LLM-merged deltas — rejected: close-time writes must be deterministic.

## Consequences
- SPEC_TEMPLATE + spec-lint + PLANNING (Deltas guidance), new delta-merge.mjs
  + suite, flush/ceremony wiring, docs-audit drift check. L-sized; suggest
  3 shippable stages as separate SPECs under one accepted RFC.

## Risks
- Merge conflicts between concurrent deltas to one canonical doc —
  mitigation: REQ-id granularity + the existing lock discipline (scope =
  canonical domain), fail-closed on overlapping REQ edits.
- Canonical layer bootstrap cost in projects that never ran docs-canon —
  mitigation: Deltas stay optional until a domain doc exists.

## Open Questions
- Merge trigger: flush (per work item) vs PR ceremony (pre-merge, so the PR
  carries the canonical diff too — reviewable)? Lean: PR ceremony.
- REQ id scheme: per-domain sequential (REQ-AUTH-001) vs global?

## Approvals
- Required approvers: Project owner (ales@holubec.net).
- Decision 2026-07-16: ACCEPTED by project owner (ales@holubec.net) —
  "schvaluji RFC-0011, mergni a rozjed". Open questions resolved per the
  RFC's leans, delegated by the wholesale approval: merge trigger = PR
  ceremony (canonical diff reviewable in the PR); REQ ids = per-domain
  sequential (REQ-<DOMAIN>-NNN). Delivery in the three staged SPECs.
