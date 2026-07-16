# Code Review — advisory-skills (scout / deslop / interrogate)

Reviewer: Code Review role (independent — did not implement or validate this scope), model claude-fable-5.
Date: 2026-07-16T16:12:49Z
Scope: worktree /Users/ales/Projects/aai-p3-advisory, branch feat/advisory-skills, uncommitted diff vs main (explicit path list per spec inline_review_scope).
Spec: docs/specs/SPEC-DRAFT-advisory-skills.md (frozen, ceremony_level 2, 5 Spec-AC).

```yaml
review:
  scope: "worktree feat/advisory-skills uncommitted diff vs main — .aai/SKILL_{SCOUT,DESLOP,INTERROGATE}.prompt.md (new), {.claude,.codex,.gemini}/skills/aai-{scout,deslop,interrogate}/SKILL.md (new x9), tests/skills/test-aai-advisory-skills.sh (new), SKILLS.md, .aai/AGENTS.md, docs/issues/CHANGE-DRAFT-advisory-skills.md, docs/specs/SPEC-DRAFT-advisory-skills.md, docs/INDEX.md, docs/ai/tests/test-runs.jsonl"
  spec: docs/specs/SPEC-DRAFT-advisory-skills.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/SKILL_SCOUT.prompt.md (59 lines): 5 dimensions lines 24-28, 0-100 scale line 18, GO/HOLD@70 lines 31-32+47, ADVISORY literal lines 3-4; TEST-001..003 re-run PASS by reviewer" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/SKILL_DESLOP.prompt.md (56 lines): 5-row slop table lines 23-29, behavior-unchanged rule via aai-run-tests.sh lines 31-36, SKILL_VERIFY cross-link line 53, ADVISORY literal lines 3-4; TEST-004..006 re-run PASS by reviewer" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/SKILL_INTERROGATE.prompt.md (65 lines): one-question rule lines 27-28, recommended-answer rule lines 29-31, 'inferred: <path>' line 25, ledger format line 44 (ref_id — post-validation remediation confirmed against real decisions.jsonl lines), ADVISORY literal lines 3-4; TEST-007..009 re-run PASS by reviewer" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "9 wrappers verified (TEST-010 re-run PASS; shape matches aai-verify/aai-debug exemplars incl. per-tree description style and not-found fallback); SKILLS.md +3 rows, .aai/AGENTS.md +3 Follow lines (git diff read); git status --porcelain shows zero edits to ORCHESTRATION*/orchestration-dispatch.mjs/orchestration-mode.mjs/workflow/WORKFLOW.md; TEST-012 negative grep re-run PASS" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "reviewer re-ran: advisory suite 14/14 exit 0; prompt-diet suite exit 0 (TEST-013); strict docs audit exit 0 (TEST-014); sibling gates verify/debug exit 0; index idempotence re-probed by reviewer (consecutive runs differ only in Generated line; committed INDEX matches regeneration; file restored byte-identical); full-sweep 25/26 evidence = docs/ai/tests/test-runs.jsonl last row + validation report (sweep itself not re-run by reviewer — see cannot_verify)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-advisory-skills.sh, line: 141,
          issue: "TEST-009 pins '\"type\":\"planning_decision\"' but not the '\"ref_id\"' ledger key, so the exact defect validation caught (prompt keyed 'ref' from decisions.jsonl's stale header) could regress with the suite staying green",
          failure_scenario: "future prompt edit copies the ledger line shape from decisions.jsonl's header comment (which still shows \"ref\":\"PRD-001\"), reverting ref_id→ref; suite passes; interrogate ledger lines silently diverge from every real consumer keyed on ref_id (e.g. aai-replay)" }
      - { rank: INFO, file: docs/specs/SPEC-DRAFT-advisory-skills.md, line: 184,
          issue: "AC table note says INTERROGATE is 3,041 bytes; actual is 3,044 (the ref→ref_id remediation added 3 bytes after the note was written; line count 65 still accurate)",
          failure_scenario: "none — notes-accuracy only; no gate consumes the byte figure" }
      - { rank: INFO, file: tests/skills/test-aai-advisory-skills.sh, line: 96,
          issue: "grep -c '^\\s*|' relies on \\s in BRE (GNU extension); under strict BSD semantics the pattern degrades but still matches the file's '|'-first table rows",
          failure_scenario: "none realistic for this file — would only miscount if table rows gained leading whitespace on a non-GNU grep; noted for portability awareness only" }
  cannot_verify:
    - { claim: "full tests/skills sweep 25/26 with sole failure = LEARNED environmental aai-worktree fixture",
        closes_with: "re-running bash tests/skills/test-framework.sh in this worktree; accepted here on docs/ai/tests/test-runs.jsonl (last row 26/25/1), the validation report, and the LEARNED.md 2026-07-15 rule (line 34) documenting the deterministic environmental failure" }
    - { claim: "the three advisory prompts, when actually invoked by an agent, behave advisory-only (never block) and interrogate writes well-formed ledger lines",
        closes_with: "runtime/behavioral evidence — the writers are LLMs following prompt text, not scripts (spec Seam S5 names this residual risk); grep suite proves the literals exist, not the behavior. Validation's functional walks are the closest existing evidence" }
    - { claim: "upstream fidelity to pro-workflow (RES-0001 P3 rec 15) scout/deslop/interrogate patterns",
        closes_with: "fetching the upstream repo; validation recorded this fetch and 'high fidelity, disclosed adaptations only' — not independently re-fetched by review" }
  overall: pass
```

## Verdict 1 — spec_compliance: PASS

AC walk above. Additional compliance notes:

- RED-proof obligation (spec Implementation strategy): docs/ai/tdd/advisory-skills-red.log shows TEST-001..012 FAILING on the pre-change tree with TEST-013/014 passing (survival invariants), exactly as the spec prescribes; green log shows 14/14. Reviewer independently re-ran the suite: 14/14, exit 0.
- Design decisions D1–D6 all observable in the diff: shared ADVISORY disclaimer literal (D1, byte budget honored — 9,057 B total for three prompts, prompt-diet floor holds per TEST-013 re-run); scout scoring anchors per dimension (D2); deslop diff-scoping + behavior-unchanged + VERIFY handoff (D3); interrogate three literal rules + additive planning_decision ledger type (D4); wrapper shape mirrors aai-verify/aai-debug in all three trees with no model: pin (D5); suite is bash-3.2-style, delegates byte-floor and audit to the real suites rather than duplicating constants (D6).
- Post-validation disposition (spec lines 272-277): the single NB finding (ledger key ref → ref_id) is remediated in .aai/SKILL_INTERROGATE.prompt.md line 44; reviewer confirmed every real decisions.jsonl line uses ref_id (14 occurrences) while only the stale header comment uses ref.
- Deviations from the frozen spec: none found. Constitution deviations: none claimed, none observed.

## Verdict 2 — code_quality: PASS

No BLOCKING findings. One NON-BLOCKING and two INFO findings — see the YAML block for file:line and failure scenarios.

WARNING (NON-BLOCKING) disposition recommendations (H6 — orchestrator records; reviewer is read-only):

- NB-1 (TEST-009 lacks ref_id key assertion): RECOMMEND remediate-in-tree — a one-line addition to test_009_interrogate_ledger, e.g. `grep -qF '"ref_id"' "$INTERROGATE"`, turns the already-remediated validation finding into a pinned regression. If not remediated in-tree, promote to a follow-up ref before closeout.
- INFO items carry no disposition duty.

Observation (out of diff scope, not a finding on this change): docs/ai/decisions.jsonl's header comment itself still documents the stale `"ref"` key (line 10) — the root cause of the validation NB. A follow-up touching that header would remove the trap for future writers; it was correctly left untouched by this additive-only scope.

## Verdict 3 — cannot_verify

Three entries — see YAML block. None blocks: each is either validation-owned with recorded evidence or an inherent prompt-skill limitation the spec itself names as residual risk (Seam S5).

## Meta-note (anti-gaming)

The dispatch prompt named the diff scope by path list and disclosed prior gate outcomes and the one post-validation disposition as context. It did not pre-rate severity, characterize expected findings, or scope-exclude areas. No coaching detected; full scope reviewed.

## Next steps

1. Orchestrator records NB-1 disposition (remediate-in-tree recommended; else follow-up ref) per H6.
2. Stage this report with the scope's commit (SPEC-0013 H4).
3. Scope is merge-ready from review's perspective once NB-1 disposition is recorded.
