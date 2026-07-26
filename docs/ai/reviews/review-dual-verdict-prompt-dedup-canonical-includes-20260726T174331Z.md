---
title: Code Review (dual-verdict) — prompt-dedup-canonical-includes
scope: prompt-dedup-canonical-includes
role: Code Review
date: 2026-07-26T17:43:31Z
---

# Code Review — prompt-dedup-canonical-includes (single dual-verdict)

```yaml
review:
  scope: "git diff main + untracked (.aai/ROLE_COMMON.md, docs/specs/SPEC-0086-spec-prompt-dedup-canonical-includes.md, docs/issues/CHANGE-0059-prompt-dedup-canonical-includes.md); declared scope = STATE worktree.inline_review_scope"
  spec: docs/specs/SPEC-0086-spec-prompt-dedup-canonical-includes.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/PLANNING.prompt.md step 10 (paraphrase removed, WORKFLOW.md pointer + residue kept); tests/skills/test-aai-ceremony-levels.sh test_018 (TEST-001)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/VALIDATION.prompt.md L57-97 (MECHANICAL CHECKS -> --gate; PROSE RULES 3/4-anti-cheat retained); tests/skills/test-aai-docs-audit.sh test_pdci_validation_gate_delegation + test_pdci_gate_characterization_temporal_gap (TEST-003/004); gate coverage confirmed in .aai/scripts/lib/docs-audit-core.mjs gateContent" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/ROLE_COMMON.md L12 (sole copy of carve-out body); 5 pointers with correct --role; tests/skills/test-aai-token-capture.sh test_003 (TEST-005)" }
      - { ac: Spec-AC-04, call: compliant, citation: "corpus 349697->345010 (-4687) measured; ROLE_COMMON.md=1666B in TEST-010 extra; ledger -3021 entry, JUSTIFIED_GROWTH_BYTES 29802->26781 re-sum verified; .aai/system/PROFILES.yaml core" }
      - { ac: Spec-AC-05, call: cannot-verify, citation: "deferred by design (Review-By 2026-08-15); full test-framework.sh not run per operator efficiency directive; CI runs it on the PR" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/ai/overview.html, line: 1,
          issue: "Three generated artifacts (docs/ai/EVENTS.jsonl, docs/ai/overview-data.json, docs/ai/overview.html) are modified in the working tree but are NOT in the declared inline_review_scope; their content reflects the prior token-capture-canary closeout, not this scope.",
          failure_scenario: "A blanket `git add -A` at PR time would bundle unrelated token-capture-canary telemetry/overview regeneration into the prompt-dedup commit. SKILL_PR stages by scope list so this is contained, but the working tree is not clean w.r.t. the declared scope." }
  cannot_verify:
    - { claim: "Full skill framework green with no stale pinned-prose stanza (Spec-AC-05 / TEST-010).",
        closes_with: "bash tests/skills/test-framework.sh exit 0 on the PR CI run (deferred by design; not run here per operator directive)." }
    - { claim: "VALIDATION prompt delegation is semantically correct end-to-end when an agent actually executes it (SEAM-4 / RR-1).",
        closes_with: "No test runs the prompt as an agent; rests on source read of gateContent + characterization guard TEST-004 + grep TEST-003 (all confirmed here)." }
  overall: pass
```

## Scope and preflight

- Branch `feat/prompt-dedup-canonical-includes`; `worktree.user_decision: inline`.
- Reviewed `git diff main` for tracked files plus the three untracked in-scope files. Declared scope = `worktree.inline_review_scope` (16 paths). No coaching on findings was present in the dispatch; severity is my own.
- Efficiency directive honored: no test suites executed; validation report treated as context.

## Verdict 1 — spec_compliance: PASS

AC walk above. Every terminal Spec-AC is compliant with cited evidence; Spec-AC-05 is a by-design deferral (dispatch bars Implementation from the full framework) with a valid Review-By, recorded as cannot-verify rather than a gap.

Key confirmations:
- **Gate coverage is honest (Spec-AC-02, the highest-risk claim).** Source read of `.aai/scripts/lib/docs-audit-core.mjs` `gateContent` confirms it computes exactly Rule 1 (non-terminal row), Rule 2 (done row with empty Evidence), and Rule 4-format (schema-invalid Review-By via `parseReviewBy`). It performs **zero** date-vs-today arithmetic, and `gateDoc` resolves/gates exactly one doc — so Rule 3 (repo-wide overdue) and Rule 4-anti-cheat (14-day-future) are genuinely non-delegable. The VALIDATION prose correctly delegates only 1/2/4-format and retains 3/4-anti-cheat verbatim in intent. No enforcement was silently lost; the deleted "unparseable ISO date" prose is fully subsumed by the script's schema check (which is in fact stricter — it checks all rows, not just deferred/blocked).
- **5 D5 pointers name the right file and role:** Implementation, Validation, Remediation, Planning, "TDD Implementation" — all pointing at `.aai/ROLE_COMMON.md`. The literal "Subagent-mode carve-out" body exists in exactly one file (grep-confirmed). SKILL_TDD's `--tdd-tests` residue and its "before Phase 1 (RED)" timing note are preserved on the pointer.
- **PLANNING step 10 residue intact:** `ceremony_level`, `Ceremony justification:`, `dispatch lane`, `L0/L1` all present; the four-level paraphrase and the "MANDATORY when the scope touches" restatement are gone; a WORKFLOW.md pointer is present; no `| ... | L0 | L1 | L2 | L3 |` table row leaks into PLANNING or VALIDATION.
- **VALIDATION step 8b untouched** (close-work-item.mjs / DONE-TRANSITION ASSERTION preserved).

## Verdict 2 — code_quality: PASS

**Ledger math is honest.** Measured independently:
- ROLE_COMMON.md = 1666 B; corpus `cat .aai/*.prompt.md | wc -c` = 345010 (working tree) vs 349697 (main) = −4687 B.
- Genuine reduction = 4687 − 1666 (relocation neutralization) = 3021 B → the NEGATIVE ledger entry is `-3021`, correctly sized.
- `JUSTIFIED_GROWTH_BYTES` = 29802 − 3021 = 26781; independent re-sum of `JUSTIFIED_ADDITIONS` = 26781 (verified by sourcing the ledger). TEST-012 expected total and TEST-013 negative-shape allowance updated consistently. TEST-010 `extra` accounting adds ROLE_COMMON.md.

One NON-BLOCKING finding (scope hygiene) — see block above.
- **Disposition (reviewer-recommended):** remediate-in-tree — the orchestrator/PR step should keep `docs/ai/EVENTS.jsonl`, `docs/ai/overview-data.json`, `docs/ai/overview.html` out of the prompt-dedup commit (stage by scope list only). No decisions.jsonl entry or follow-up ref needed; it is a staging-discipline note, not a code defect.

## cannot_verify

See the two entries in the YAML block. Neither blocks; both are visible for merge-readiness judgment. The Spec-AC-05 deferral and RR-1 (SEAM-4) are accepted-risk items already recorded in the spec.

## Overall: PASS

Both verdicts pass. The one NON-BLOCKING finding is a working-tree staging-discipline note with a named disposition, not a defect in the change itself.
