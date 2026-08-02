---
id: prompt-diet-2026-08
number: 110
type: change
status: done
user_visible: false
links:
  pr:
    - 213
  commits:
    - af1059abb2a1d8e22f497940439f47381e2b7b70
---

# Change — prompt diet 2026-08: buy back TEST-010 headroom so the corpus stops running a zero-headroom treadmill

## Summary
- The prompt-diet byte budget (tests/skills/test-aai-prompt-diet.sh TEST-010)
  sat at `headroom 0/2048` with `JUSTIFIED_GROWTH_BYTES=1116`. At zero headroom
  EVERY prompt byte added by any ride immediately breaches the floor and forces
  a ledger true-up in the same commit.
- Trim 1530 genuinely dead bytes out of the three largest corpus prompts so the
  headroom lands mid-band and the next few small prompt additions are absorbed
  by slack instead of ceremony.
- No credit change: per the ledger's own remediation guidance,
  `JUSTIFIED_GROWTH_BYTES` is lowered only when a shrink would push headroom
  ABOVE the cap. 1530 < 2048, so the credit (and the TEST-012 pin `1116`)
  stays exactly as it is.

## Motivation / Business Value
- Weakness 5 of the 2026-08-01 factory audit: zero-headroom treadmill.
- Evidence, week of 2026-07-27 — six forced ledger true-ups in seven days, each
  one an itemized `JUSTIFIED_ADDITIONS` entry authored purely because headroom
  was 0, not because the growth was in question:
  `196 runtime-state-consolidation`, `238 r-guard-runtime-enforcement`,
  `551 async-hitl-botfix`, `262 async-hitl-resolve-lifecycle`,
  `349 lightweight-lane-botfix`, `73 cache-friendly-dispatch-reorder`.
- Headroom has been pinned at 0 since the CHANGE-0090 implementation-mode ride
  consumed the last slack ("credited 1:1 so headroom stays 0").
- Cost: the true-up is a multi-minute research + write task on every ride that
  touches a prompt, and it competes for attention with the actual change. The
  floor's purpose (catch UNJUSTIFIED growth) is served just as well from
  mid-band; at 0 it also taxes justified growth.

## Scope
- In scope: `.aai/SKILL_LOOP.prompt.md`, `.aai/SKILL_PR.prompt.md`,
  `.aai/VALIDATION.prompt.md`; one documenting comment line in
  `tests/skills/lib/prompt-diet-ledger.sh`; `CHANGELOG.md`.
- Out of scope: `.aai/ORCHESTRATION.prompt.md` (40-line cap, already at the
  floor), the freshly-landed R-GUARD and lightweight-lane blocks, and every
  `JUSTIFIED_ADDITIONS` value (no credit is changed, no pin is moved).

## Affected Area
- Prompt corpus (the `.aai/*.prompt.md` glob TEST-010 measures) and the
  prompt-diet floor accounting that reads it.

## Desired Behavior (To-Be)
- TEST-010 reports headroom in the 1200-1900 band instead of 0.
- Every rule, gate, invocation and pinned literal that existed before the trim
  still exists after it — the trim removes only restatement and cosmetics.

## Acceptance Criteria
- AC-001: `bash tests/skills/test-aai-prompt-diet.sh` reports TEST-010 headroom
  in the closed range 1200-1900 (hard ceiling: TEST-010 fails above
  `HEADROOM_CAP=2048`) and exits 0.
- AC-002: TEST-012 still reports `JUSTIFIED_GROWTH_BYTES == 1116 ==
  independent re-sum` — the credit and its pin are untouched.
- AC-003: every test suite that greps a touched prompt file exits 0. The set is
  derived mechanically by `grep -l` for the filename across `tests/skills/*.sh`:
  hygiene-pack, orchestration-mode, token-capture, run-tests, state,
  branch-guard, close-work-item, delta-stage3, friction-wiring, doc-numbering,
  hooks-overlay, feedback-triage, lightweight-lane, pr-platform,
  reconcile-telemetry, ceremony-levels, docs-audit, doctor,
  implementation-mode, orchestration-dispatch, spec-lint, verify-gate,
  tdd-evidence — plus layer-profiles.
- AC-004: `node .aai/scripts/docs-audit.mjs --check --strict --no-event` is
  CLEAN.
- AC-005: zero semantic rule loss. Reviewer-checkable without re-reading the
  prompts: the diffstat shows only (a) cosmetic byte reduction, (b) a
  duplicated block collapsed to a pointer at its surviving single definition,
  and (c) two sentences merged that said the same thing twice; and the pin
  suites of AC-003 — which assert the literal presence of every gate,
  invocation and rule sentence in these three files — stay green.

## Verification
- `bash tests/skills/test-aai-prompt-diet.sh` -> TEST-010 `headroom 1530/2048`,
  TEST-012 `== 1116`, all tests passed.
- Each AC-003 suite run individually -> exit 0.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0.

## Constraints / Risks
- The band is bounded on BOTH sides: trimming too much (> 2048) fails TEST-010
  just as growing does, and the remediation would be a credit reduction. The
  trim was sized to land at 1530, ~500 B clear of the cap.
- No secrets referenced.

## Notes
- What was actually cut (all three files, 1530 B total):
  - `.aai/SKILL_LOOP.prompt.md` 26130 -> 24833 (-1297):
    - Six full-width U+2500 box-drawing rules in the CHECKPOINT GATE output
      templates replaced by the `---` separator the same file already uses for
      its HITL OUTPUT FORMAT block. `─` is 3 bytes in UTF-8, so those six
      cosmetic lines alone cost ~726 B. The blocks still render as delimited
      blocks; only the glyph changed.
    - The `LOOP PARAMETERS` `stop_conditions:` list collapsed to a one-line
      pointer at step 2. All six conditions (paused, human input, validation
      pass + review gate, max_ticks, stagnation, run budget) were already
      defined in step 2 a-f in fuller form; the parameters block was a
      verbatim second copy. Step 2 is untouched.
  - `.aai/VALIDATION.prompt.md` 19429 -> 19220 (-209): the AC STATUS GATE
    opening paragraph and the `Detection:` bullet list stated the same opt-in
    rule twice (`Review-By` column present -> gate applies; otherwise legacy
    bypass). Merged into one paragraph carrying both the literal column name,
    the case-sensitivity note, the SPEC_TEMPLATE pointer and the legacy-bypass
    rule.
  - `.aai/SKILL_PR.prompt.md` 21168 -> 21144 (-24): step 5 re-invoked
    `node .aai/scripts/pr-platform.mjs` a second time, ~25 lines after the
    PLATFORM GATE already ran it, to introduce the branch table. Reworded to
    branch on the value the step-5 probe printed. The script is still named in
    the PLATFORM GATE (the TEST-015 pin needs one occurrence).
- Residual diet opportunity, deliberately NOT taken here (it would overshoot
  the cap): `.aai/SKILL_WORKTREE.prompt.md` (15245 B) still carries the exact
  dead-weight shapes CHANGE-0076/core-prompt-diet retired elsewhere — a "What
  are Git Worktrees?" explainer, a "Token Optimization" benefits section, an
  "Example Session" transcript, an "Integration with AAI Workflow" walkthrough,
  and a stale "Inspired by Superpowers framework" attribution — roughly 2 KB of
  prose with no rule content. It is the natural next diet ride once this
  headroom is spent.
