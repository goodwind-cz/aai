---
id: session-loose-ends
number: 86
type: change
status: done
user_visible: false
links:
  pr:
    - 188
  commits:
    - 1566fe8679efe3669abdef7b36b690bddbf9ab37
---

# Change — session loose ends: phase-boundary audit, inheritance provenance, NOTE convention, POSTPROCESSING wontfix

## Summary
- Operator direction 2026-07-28: close the four items left open across the
  session journals:
  (a) roadmap#8 — audit every role dispatch surface (canonical prompts +
      SUBAGENT_PROTOCOL/CONTRACT) for phase-boundary leaks: only ARTIFACT
      PATHS may cross a phase boundary, never transcript/context prose;
      findings fixed in-tree.
  (b) promptbook#4 — dispatch stamps inheritance provenance: alongside the
      SPEC-0096 prompt_hash, the dispatch output names the component
      versions the role inherits (CONTRACT@<12hex>, LEARNED@<12hex>), so
      "which instruction stack produced this run" is answerable per
      component, not only in aggregate.
  (c) promptbook#5 — the degrade-with-NOTE practice (docs-hub NOTEs,
      rollup EXCLUDED lines) is promoted to a one-sentence universal
      convention in AGENTS.md.
  (d) promptbook#6 — POSTPROCESSING declarations are dispositioned WONTFIX
      in the session doc (no real use-case materialized across 31 PRs;
      speculative structure).

## Acceptance Criteria
- AC-001: dispatch human block + JSON carry component provenance
  (contract_hash, learned_hash 12-hex; ABSENT for missing files) —
  suite-verified RED-first; prompt_hash behavior unchanged.
- AC-002: phase-boundary audit report delivered; every finding either
  fixed in this ride or explicitly dispositioned; zero prose-context
  handoff instructions remain in canonical role prompts.
- AC-003: AGENTS.md carries the degrade-with-NOTE convention (ledger
  credit per AGENTS precedent); session doc carries the POSTPROCESSING
  WONTFIX disposition.

## Verification
- tests/skills/test-aai-orchestration-dispatch.sh (extended)
- prompt-diet + verify-gate (AGENTS credit)
- audit report in the PR body / session doc

## Constraints / Risks
- Ceremony L2 (orchestration-dispatch.mjs is NOT protected-L3; verify);
  review: dual-verdict on the dispatch change.
