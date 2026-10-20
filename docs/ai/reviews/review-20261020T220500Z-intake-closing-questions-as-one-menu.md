```yaml
review:
  scope: git diff main...HEAD (base main 71c7475a, head 75cffd12, branch fix/intake-closing-questions-as-one-menu)
  spec: docs/specs/SPEC-0238-spec-intake-closing-questions-as-one-menu.md (frozen, ceremony_level 1)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/SKILL_INTAKE.prompt.md:68-72 (STEP 2.7 — CLOSING QUESTIONS, before INTAKE COMPLETE at :77); TEST-001 = test_010 PASS" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/INTAKE_COMMON.md:73-75; SKILL_INTAKE names no harness tool; TEST-002 = test_011 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/INTAKE_COMMON.md:77-85 (options line, intake: N, leave intake: null; free-text prompt removed); TEST-003 = test_012 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/INTAKE_COMMON.md:72 + :88; 8/8 INTAKE_*.prompt.md keep 'metrics question'; TEST-004 = test_013 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/INTAKE_COMMON.md:76; SKILL_SHIP.prompt.md:33 unchanged; TEST-005 = test_014 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/lib/prompt-diet-ledger.sh:257 (+261); test-aai-prompt-diet.sh want_growth 57344; independently measured 7139->7564 (+425), glob 365041->364877 (-164), net +261; TEST-006 = test_012 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/INTAKE_COMMON.md, line: 78,
          issue: "Minutes menu lists 5 options incl. an explicit 'Other'; Claude Code AskUserQuestion caps options at 4 and adds its own free-text Other.",
          failure_scenario: "Claude Code agent passes Skip/5/15/30/Other verbatim -> tool rejects or the agent silently drops an option / shows Other twice; Codex request_user_input likely has a tighter cap (also hits the 4-option mode choice)." }
      - { rank: NON-BLOCKING, file: .aai/INTAKE_COMMON.md, line: 72,
          issue: "METRICS now binds to the IMPLEMENTATION MODE CHOICE, but the eight per-type INTAKE_*.prompt.md SHARED POLICY lines list five blocks WITHOUT the mode choice.",
          failure_scenario: "/aai-intake routed to INTAKE_CHANGE: agent applies 'metrics question' which says 'in ONE menu together with the IMPLEMENTATION MODE CHOICE' — a block it was not told to apply; harnesses diverge (one asks the mode choice, one asks minutes alone)." }
  cannot_verify:
    - { claim: "A given harness agent actually invokes its structured-question tool at run time (spec's own residual).",
        closes_with: "Live intake transcript per harness (Claude Code, Codex, Gemini) showing one structured call with both questions." }
    - { claim: "Codex request_user_input availability/limits (option count, collaboration-mode restriction) and the 'Gemini equivalent' existence.",
        closes_with: "Current Codex/Gemini CLI tool docs or a live Codex intake run." }
    - { claim: "RED evidence and mutation records cited in the AC table (docs/ai/tdd/*) — gitignored, not in the diff; relied on the Validation PASS report.",
        closes_with: "docs/ai/tdd/intake-closing-questions-as-one-menu-red-TEST-00{1..6}.log + mutation-run --replay exit 0 (Validation already checked)." }
  overall: pass
```

# Code Review — intake-closing-questions-as-one-menu

Scope: `git diff main...HEAD` (9 files, +274/-16). Spec: SPEC-0238-spec-intake-closing-questions-as-one-menu (frozen L1). Validation: docs/ai/reports/VALIDATION-20261020T213953Z-intake-closing-questions-as-one-menu.md (PASS).

Process notes:
- Coaching: the dispatch pre-named two known non-blocking items and listed focus areas. Recorded per the anti-gaming contract; the full scope was reviewed anyway. Both pre-named items were independently re-derived (findings NB-1, NB-2).
- Report location: written to docs/ai/reports/ (gitignored) as the dispatch required so that no tracked file is touched and the validation stamp stays valid. The prompt's default is docs/ai/reviews/. If the review report must be committed later, the orchestrator should copy it there.
- STATE write: this reviewer was dispatched, so the D1 sole-agent carve does not apply even though AAI_ROLE is unset. The set-code-review and append-run commands are returned to the orchestrator instead of being run.

## Spec compliance — PASS
All six ACs comply (see the YAML walk). Re-run here: `env -u AAI_ROLE bash tests/skills/test-aai-implementation-mode.sh` exit 0, `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh` exit 0.
Ledger arithmetic was re-measured independently with git show + wc -c on main and HEAD: INTAKE_COMMON +425 B, prompt glob -164 B, net +261 B, which is within the 900 B cap. 57083 + 261 = 57344 matches the pin. There is exactly one ledger entry with this key.
Scope matches the spec's inline review scope. docs/INDEX.md and docs/ai/EVENTS.jsonl changed only through regeneration and append-only events. Under D1-D3 there are no spec deviations. The stale "3-way" wording in the old STEP 2.7 is gone, which is an improvement.
No duplicated canonical text: SKILL_INTAKE only points to the blocks, and AGENTS.md rule 2 stays the generic principle.

## Code quality — PASS (2 NON-BLOCKING)
- **NB-1** `.aai/INTAKE_COMMON.md:78`: the 5-option minutes menu, with an explicit Other, goes over the AskUserQuestion 4-option cap, and the tool already adds its own Other. Disposition: **promote-to-follow-up-ref**, the existing `fu-intake-menu-option-caps`. Suggested fix: "Skip (default) / 5 / 15 / 30; free-text Other supplied by the facility or as a 5th numbered line in the text fallback". Also check Codex's option cap against the 4-option mode choice.
- **NB-2** `.aai/INTAKE_COMMON.md:72`: the per-type intake prompts apply "metrics question" but not the mode-choice block, so "together with the IMPLEMENTATION MODE CHOICE" is ambiguous on those entry points. Disposition: **promote-to-follow-up-ref**, the existing `fu-intake-pertype-closing-step`.

INFO (not gating):
- `test_011` is described as "single-sourced" but only checks SKILL_INTAKE for two tool names. The name makes no universal-negative claim, so the rule does not apply.
- An "Other" reply that is not a number has no defined handling. Leaving `intake: null` is the obvious reading.
- Tests are not brittle. They pin semantic phrases, and only one exact line is pinned: the SKILL_SHIP default, which the spec requires to stay byte-identical. The per-type glob is resolved from PROJECT_ROOT, and a failed glob fails closed.

## Cannot verify
See the YAML: run-time tool invocation per harness, the Codex/Gemini facility contract, and the gitignored RED and mutation evidence (relied on Validation).

## Next steps
Orchestrator: record NB-1 and NB-2 dispositions against the existing follow-ups, run the returned state commands, then go to PR.
