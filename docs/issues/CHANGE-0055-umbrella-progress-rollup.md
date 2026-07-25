---
id: umbrella-progress-rollup
number: 55
type: change
status: done
links:
  spec: null
  pr:
    - 154
  commits:
    - 068c3aafefc9aa7e0dc12c81d866f98e723665a4
---

# Umbrella progress rollup (docs-audit) + RFC Rollout Status table

## Summary
- An in-flight umbrella RFC/PRD shows only a coarse `status: implementing` — never
  how far along it is; progress lives scattered across done child docs and is not
  aggregated. This adds BOTH an automatic rollup and a human roadmap:
  1. **docs-audit rollup** — for every non-terminal rfc/prd parent with children,
     `docs-audit` now reports `done/total` child docs (a `- Rollout:` summary line
     on every run + a `### Rollout progress` table under `--list`). General: any
     parent with linked children, keyed on BOTH slug id and numbered display id.
  2. **RFC Rollout Status table** — a human-maintained phase/proposal roadmap added
     to RFC-0012 and RFC-0013 (and an RFC_TEMPLATE stub), capturing not-started
     phases that have no child doc yet — work the automatic rollup cannot see.
- Root-cause prerequisite: the shared `parseFrontmatter` DROPPED `links.rfc` /
  `links.requirement` whenever the `links:` block also contained a block-style list
  (`pr:\n  - 147`) — a block-list item clobbered the whole nested object. This
  silently broke EVERY reverse-link consumer (the rollup AND closeout-candidate
  detection). Fixed by tracking the nested key so block-list items attach to the
  right sub-key.

## Type
- change (docs-audit engine + shared parser fix + RFC docs; report-only surface)

## Motivation / Business Value
- "Why does RFC-0012 `implementing` show no progress, when it is part-done?" — the
  status enum is binary-ish and nothing rolled child completion up to the parent.
  This is the same class of friction RFC-0012's own loop is meant to catch. The
  fix is general (any umbrella) and dogfoods on RFC-0012/0013.

## Scope
- In scope:
  - `.aai/scripts/lib/docs-model.mjs`: `parseFrontmatter` nested-key tracking so a
    block-list under a nested key no longer clobbers sibling scalar keys.
  - `.aai/scripts/lib/docs-audit-core.mjs`: `parentProgressFor(docs)` (done/total
    per non-terminal rfc/prd parent, matched on slug id OR display id, forward
    links.spec ∪ reverse links.rfc/requirement); wired into `runAudit` result.
  - `.aai/scripts/docs-audit.mjs`: always-shown `- Rollout:` summary line +
    `### Rollout progress` table under `--list`. Report-only (never affects exit).
  - `docs/rfc/RFC-0012-*.md`, `docs/rfc/RFC-0013-*.md`: `## Rollout Status` table.
  - `.aai/templates/RFC_TEMPLATE.md`: `## Rollout Status` stub for future umbrellas.
  - `tests/skills/test-aai-docs-audit.sh`: rollout fixture + 3 tests (slug-id parent
    resolved via display-id + block-list links; summary line; report-only).
- Out of scope:
  - `closeoutCandidatesFor`'s own slug-only matching (a separate latent limitation;
    the parser fix helps it, but the id-and-display fix is applied only to the new
    rollup here). No change to hard-fail / exit-code behavior.

## Desired Behavior (To-Be)
- `docs-audit` surfaces `RFC-0012 10/11 · RFC-0013 2/2`-style progress on every run,
  and a per-parent table under `--list`, so partial umbrella progress is visible.
- `parseFrontmatter` preserves `links.rfc`/`links.requirement` alongside block-list
  `pr`/`commits`.
- RFC-0012/0013 carry a phase roadmap; new umbrella RFCs inherit the stub.

## Acceptance Criteria
- AC-001: for a non-terminal rfc parent with a SLUG frontmatter id whose children
  reverse-link it by DISPLAY id via BLOCK-LIST `pr`/`commits`, `docs-audit --list`
  reports `### Rollout progress` with that parent at the correct `done/total (%)`;
  a plain `docs-audit --check` shows the `- Rollout:` one-liner. Report-only (exit
  unaffected). Deterministic fixture tests, RED without the change.
- AC-002: `parseFrontmatter` on a `links:` block mixing scalar keys (`rfc`,
  `requirement`) and block-lists (`pr:\n  - N`) returns ALL keys (rfc/requirement
  preserved), not just the last. Verified end-to-end by AC-001's block-list fixture
  (children resolve only when links.rfc survives).
- AC-003: full `test-aai-docs-audit.sh` + the docs suites
  (close-work-item, doc-numbering, doc-number-reservation, docs-canon, test-canon)
  stay green (shared-parser change causes no regression).

## Verification
- `bash tests/skills/test-aai-docs-audit.sh` (all green, incl. 3 rollout tests).
- Regression: close-work-item, doc-numbering, doc-number-reservation, docs-canon,
  test-canon all pass locally after the parser change.
- Real repo: `docs-audit --check` shows `- Rollout: RFC-0012 10/11 · RFC-0013 2/2`;
  audit CLEAN, body lint 0.

## Constraints / Risks
- The parser fix is a shared-behavior change: reverse-link consumers now resolve
  links they previously dropped. Verified no test regression; the only behavior
  change is MORE-correct link resolution (report-only surfaces).
- Rollout progress is informational — never part of hardFail/needsTriage.
- None of the touched scripts are protected_paths_l3 (all L2).

## Notes
- Related: closeoutCandidatesFor (SPEC-0003, the sibling resolver reused as a
  pattern), RFC-0012/RFC-0013 (the dogfood umbrellas). The RFC Rollout Status table
  is the human roadmap; the docs-audit rollup is the automatic per-child view.
