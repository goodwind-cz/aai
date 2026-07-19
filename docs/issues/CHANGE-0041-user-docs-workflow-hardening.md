---
id: user-docs-workflow-hardening
type: change
number: 41
status: done
links:
  pr:
    - 114
  commits:
    - 0d542b5
---

# Change — user-facing docs for the workflow-hardening + collision-guard changes

## Summary
- Update the user-facing docs (USER_GUIDE.md, and the affected skill SKILL.md
  descriptions) to cover the user-visible behavior shipped this session, which
  is currently undocumented: the deterministic close ceremony, the L0/L1
  lightweight dispatch lane, the new docs-audit/spec-lint findings
  (duplicate-doc-id, spec-id-shape), the secrets-preflight intake helper, and
  the `spec-` id-prefix convention.

## Motivation / Business Value
- A grep of docs/USER_GUIDE.md shows 0 mentions of close-work-item, lightweight
  lane, ceremony_level, duplicate-doc-id, spec-id-shape, or secrets-preflight —
  all of which are now user-visible. Operators can't use or understand features
  that aren't documented; the docs must reflect the shipped behavior.

## Scope
- In scope: docs/USER_GUIDE.md (add/extend sections for the items below);
  the SKILL.md descriptions for the affected skills (aai-pr, aai-docs-audit,
  aai-intake, aai-loop) where their behavior changed; a CHANGELOG entry.
- Out of scope: internal-only mechanics with no operator surface (token-usage
  capture, RED_CLASS evidence classification, reconcile-telemetry internals,
  the prompt-diet ledger) — mention only where an operator would actually
  interact; no code/behavior change.

## Affected Area
- User documentation.

## Desired Behavior (To-Be) — the topics to document
- **Deterministic close ceremony** (`close-work-item.mjs`): work items are
  closed correctly-by-construction (status flip + links + slug-ref events +
  self-verifying audit + rollback); operators no longer hand-close. Note it
  fail-closes on an ambiguous/duplicate id.
- **Lightweight lane** (`ceremony_level` 0/1): small, single-surface scopes run
  a leaner pipeline (Implementation → declared-scope Validation → one review),
  vs the full L2/L3 pipeline; how to declare `ceremony_level` and what L0–L3
  mean (tie to the existing scale-adaptive ceremony content if present).
- **New docs-audit finding — duplicate-doc-id**: two docs sharing a frontmatter
  `id` are flagged (verdict-only, CI exit unchanged); how to remediate.
- **New spec-lint finding — spec-id-shape** + the **`spec-` id-prefix
  convention**: a spec's `id` must be `spec-<change-slug>` (or the legacy
  numbered `SPEC-NNNN`), never a bare slug that collides with its change.
- **secrets-preflight** (`secrets-preflight.mjs`): intake helper that checks a
  local secret (env var / config key) exists/non-empty WITHOUT reading or
  echoing the value.

## Acceptance Criteria
- AC-001: USER_GUIDE.md documents each of the five topics above accurately
  (matching the shipped behavior), in the appropriate existing sections
  (Skills Catalog / audit / intake / workflow), with runnable command examples
  where a CLI is involved.
- AC-002: the affected skills' SKILL.md descriptions reflect their changed
  behavior (aai-pr close step, aai-docs-audit duplicate-doc-id, aai-intake
  secrets preflight, aai-loop lightweight lane); a CHANGELOG entry is added;
  `docs-audit --check` stays exit 0 and the docs contain no broken references.

## Verification
- Grep USER_GUIDE.md for each topic term → present; cross-check each documented
  command against the real script (`--help`/behavior) for accuracy; `docs-audit
  --check --strict` exit 0; broken-reference check clean.

## Constraints / Risks
- Docs must match ACTUAL shipped behavior (verify against the scripts/specs, do
  not describe intended-but-unshipped behavior). No behavior/code change.

## Notes
- Source: operator feedback 2026-07-19 — the session's shipped skills/workflow
  changes were not reflected in user-facing docs. Covers CHANGE-0030 (lane),
  CHANGE-0034 (secrets preflight), CHANGE-0037 (close ceremony), ISSUE-0014
  (duplicate-doc-id), ISSUE-0016 (spec-id-shape).
