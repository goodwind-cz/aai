---
id: CANON-<domain>
type: canonical
domain: <domain-slug>
status: accepted
sources:
  - docs/_archive/<...>.md
---

# Canonical: <domain>

<!-- Canonical domain doc contract (RFC-0003 / SPEC-0002; Requirements section
  added by RFC-0011, the delta-spec lifecycle). Canonical docs are GENERATED
  by `node .aai/scripts/docs-canon.mjs --phase2` (renderCanonicalDoc enforces
  this shape mechanically); this template is the human-readable reference for
  the contract, not a copy-paste scaffold.

  Frontmatter: `type: canonical`, `domain:` a lowercase kebab slug matching
  DOMAIN_SLUG_RE ([a-z0-9][a-z0-9-]*), non-empty `sources:` pointing at the
  archived originals (bidirectional link-integrity enforced).

  Body: exactly these SIX level-2 sections, in this order
  (CANONICAL_SECTIONS in .aai/scripts/lib/docs-model.mjs, enforced by
  validateSectionContract). Docs generated before RFC-0011 carry five
  sections; re-enter compliance via `docs-canon.mjs --phase2 --resync`. -->

## Overview / Intent

<Merged intent prose synthesized from the live layers of the sources.>

## Requirements

<!-- The per-domain requirements contract (RFC-0011) — the authoritative
  "current state" requirement set for this domain and the merge target for
  RFC-0011's close-time delta merges. Each requirement block is:

    ### REQ-<DOMAIN>-NNN — <title>
    <exactly ONE normative SHALL statement>

    - Scenario: WHEN <trigger> THEN <observable outcome>   (optional, 0..n)

    Provenance: —

  Grammar (shared source of truth: REQ_ID_RE / REQ_HEADING_RE /
  parseRequirementsSection in .aai/scripts/lib/docs-model.mjs):
  - <DOMAIN> derives from this doc's `domain:` slug by UPPERCASE kebab→snake
    (domainToReqDomain): "auth" -> "AUTH", "oauth2-login" -> "OAUTH2_LOGIN".
  - NNN is per-domain sequential, zero-padded to at least 3 digits, unbounded.
  - STABLE IDS: never renumber, never reuse. A removed requirement retires its
    id permanently (gaps are legal). New requirements take the next unused NNN.
  - The Provenance line names the spec that merged the block into this doc.
    It stays the literal `Provenance: —` until a delta merge (RFC-0011
    stage 3, at PR ceremony) fills it, e.g. `Provenance: SPEC-0031`.
  - An EMPTY section (placeholder only, no blocks) is a VALID, complete state.

  Worked example (title/text illustrative; shown at column 0 so the exact
  shape is unambiguous — this whole block is a comment, never rendered):

### REQ-AUTH-001 — Session expiry
The system SHALL expire an authenticated session after 30 minutes of
inactivity.

- Scenario: WHEN a session is idle for 30 minutes THEN the next request
  is rejected with 401 and the session is destroyed.

Provenance: —
-->

_No requirements recorded for this domain yet._

## UI

<Merged UI-layer prose, or the synthesis placeholder.>

## Processes / Behavior

<Merged behavior prose.>

## Data model

<Merged data-model prose.>

## Superseded decisions

<Harvested links to superseded sources ONLY — what was decided, why it
changed, link to the archived source. Never place superseded content in the
earlier sections.>
