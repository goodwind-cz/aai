---
id: CHANGE-0002
type: change
status: done
links:
  rfc: RFC-0002
  spec: SPEC-0001
  change: CHANGE-0001
  pr: []
  commits: []
---

# CHANGE-0002 — docs-audit engine improvements, round 2 (D10-D15)

## Summary

Follow-up to CHANGE-0001 (D1-D9, commit 3ef5ccc). Six further deficiencies
from the downstream second remediation pass (fh-workspace at PR #118 tip).
Downstream impact of round 1 for context: 162 -> 363 docs scanned, orphan
rate 85% -> 6%, NEEDS-TRIAGE 140 -> 37.

## Triage (D10-D15)

| Item | Verdict | Reasoning |
|---|---|---|
| D10 Review-By actor+method | Accepted | `<actor> <method>` validates where actor matches the Claude model-id pattern or `human`/`operator`/`human:<name>`/`operator:<name>`, and method is a known label, an extended method (`PlaywrightSuites`, `Validation`, `TDD-snapshot-scripts`, extensible via `review_by_methods` config), or `method:date` combo. Bare actor without method rejected, per the brief — the method is what asserts validation. Single-label behavior unchanged. |
| D11 EVENTS sub-item refs | Accepted (helper already compliant + engine hardening) | `append-event.mjs` never validated ref shape, so `PARENT-ID/sub-item` works today (same scheme as `SPEC-XXXX/Spec-AC-YY`). The real defect found while verifying: the engine's evidence lookup used bare `startsWith(id)`, so `CHANGE-0045` events counted as evidence for `CHANGE-004`. Fixed to exact-match-or-`id + '/'` boundary. Sub-ref convention documented in SKILL_LOOP EVENTS section. |
| D12 plans leniency | Accepted, option 1 | `plan_scan_mode: lenient` (default): `docs/plans/**` files without canonical frontmatter inventory by filename ID as tracked-open with an "operator plan file" note — no orphan count, no hard fail. `strict` restores current behavior. Plan files that do carry frontmatter are processed normally in both modes. Option 2 (staging files) rejected: writing `<original>.suggested.md` litters the operator's tree. |
| D13 implicit legacy skip in index gen | Accepted (adapted) | When `legacy_until_date` is set, `generate-docs-index.mjs` auto-demotes schema violations in legacy-classified docs (first commit before the date) to the Skipped section, tagged `[legacy — auto-skipped]`. Non-legacy violations still hard-fail, so the window closes itself as legacy docs migrate — no flag flip needed. `--continue-on-error` unchanged for the rest. |
| D14 multi-ID suggestion | Accepted | `extractDocIds` collects numeric siblings (`PRD-022-024-025` -> PRD-022 primary + PRD-024 + PRD-025) and embedded ID shapes (`PRD-022-TEST-021-...` -> PRD-022 primary + TEST-021). Orphan table renders `primary (primary) + related...`. Single-ID filenames unchanged. |
| D15 category prefixes | Accepted | `category_prefixes` config (default `PHASE`, `MILESTONE`, `EPIC`). `DECISION-PHASE-0-scope.md` now derives the unique filename-slug ID `DECISION-PHASE-0-scope` plus scope `PHASE-0`; sibling docs in the same phase no longer collide. `--list` gains a Scope column. The zero-config `-disambig` alternative rejected: nondeterministic IDs depending on scan order. |

## Scope

- In scope: `.aai/scripts/lib/docs-model.mjs`, `lib/docs-audit-core.mjs`,
  `docs-audit.mjs`, `generate-docs-index.mjs`, `SKILL_LOOP.prompt.md`
  (EVENTS sub-ref note), fixtures in `tests/skills/test-aai-docs-audit.sh`.
- Out of scope: append-event ref validation (deliberately shapeless),
  new doc classes.

## Verification

- Fixture-first; every accepted item lands with the brief's fixture shapes
  (actor+method literals incl. the rejected bare actor, CHANGE-004 vs
  CHANGE-0045 boundary, lenient/strict plans, legacy auto-skip, multi-ID
  filenames, PHASE-scoped decisions).
- Full suite `bash tests/skills/test-aai-docs-audit.sh` PASS; existing
  fixtures must pass unchanged (backward compat).
