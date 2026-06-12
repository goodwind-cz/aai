---
id: SPEC-0001
type: spec
status: done
links:
  rfc: RFC-0002
  pr: []
  commits: []
---

# SPEC-0001 — Docs Hygiene and Drift Audit (RFC-0002 implementation)

## Links
- Decision: docs/rfc/RFC-0002-docs-hygiene-and-drift-audit.md
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: loop
- Rationale: mechanical extension of an existing, tested script layer
  (RFC-0001 layer 4) with a shell test suite per `tests/skills/` convention;
  behavior is fully specified by RFC-0002 including fixtures.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: additive scripts and prompt edits on main; no schema or
  protected-workflow rewrites.
- User decision: inline (operator instructed implementation on main)
- Base ref: main
- Inline review scope: paths listed in RFC-0002 "Files changed" inventory

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | Shared parser lib `.aai/scripts/lib/docs-model.mjs` extracted; `generate-docs-index.mjs` consumes it with unchanged INDEX output | done | test-aai-docs-audit.sh TEST-007 PASS 2026-06-12 | — | — |
| Spec-AC-02 | `docs-audit.mjs` classifies every prefixed doc into the six RFC-0002 classes | done | test-aai-docs-audit.sh TEST-001/002 PASS 2026-06-12 | — | — |
| Spec-AC-03 | Drift heuristics emit `aligned` / `probable-false-done` / `probable-stale-open` / `probable-partial` per RFC-0002 rules | done | test-aai-docs-audit.sh TEST-002 PASS 2026-06-12 | — | — |
| Spec-AC-04 | `docs/ai/docs-audit.yaml` config honored; legacy/new split by first-commit date; report-only mode when config absent | done | test-aai-docs-audit.sh TEST-001/003 PASS 2026-06-12 | — | — |
| Spec-AC-05 | `--check` exits non-zero only on hard failures (new orphan, schema violation) | done | test-aai-docs-audit.sh TEST-001/003 + strict gate PASS 2026-06-12 | — | — |
| Spec-AC-06 | `--quick` mode runs without git probes or EVENTS scan | done | test-aai-docs-audit.sh TEST-006 PASS 2026-06-12 | — | — |
| Spec-AC-07 | `append-event.mjs` accepts `docs_audit` event with counts payload | done | test-aai-docs-audit.sh TEST-004 PASS 2026-06-12 | — | — |
| Spec-AC-08 | INDEX gains `Orphans (need triage)` and `Drift report` sections | done | test-aai-docs-audit.sh TEST-005 PASS 2026-06-12 | — | — |
| Spec-AC-09 | `aai-docs-audit` skill shipped (SKILL.md + `.aai/SKILL_DOCS_AUDIT.prompt.md`) incl. remediation mode per RFC Appendix B | done | files present; sections match RFC Appendix A/B | — | — |
| Spec-AC-10 | Enforcement hooks landed in SKILL_INTAKE + INTAKE_* (post-save check), SKILL_LOOP (quick tick summary), VALIDATION (done-transition assertion), SKILL_DOCTOR (audit category) | done | SKILL_INTAKE STEP 2.5; 8 INTAKE_* POST-SAVE CHECK; LOOP tick check; VALIDATION 8b; DOCTOR CAT-11; intake test regression PASS | — | — |
| Spec-AC-11 | Portable CI wrapper template `.aai/templates/DOCS_AUDIT_TEST_TEMPLATE.md` shipped | done | file present (plain CI / vitest / pytest variants) | — | — |
| Spec-AC-12 | `tests/skills/test-aai-docs-audit.sh` implements RFC Appendix C fixtures and passes | done | full suite PASS 2026-06-12 (8 test groups) | — | — |

## Test Plan

- TEST-001: new orphan hard-fails `--check`; legacy orphan soft-warns (fixtures ISSUE-101 / ISSUE-001)
- TEST-002: false-done, partial, stale-open, aligned verdicts (fixtures SPEC-201/202, ISSUE-203, SPEC-204)
- TEST-003: missing config means report-only (`--check` exits 0 with hint)
- TEST-004: full run appends a `docs_audit` event with counts
- TEST-005: INDEX idempotence — second run byte-identical, new sections present
- TEST-006: `--quick` produces counts without invoking git
- TEST-007: existing INDEX output for RFC-0001-style docs unchanged after lib extraction
