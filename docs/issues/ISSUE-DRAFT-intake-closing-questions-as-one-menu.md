---
id: intake-closing-questions-as-one-menu
number: null
type: issue
status: draft
user_visible: true
capability: intake-closing-questions-as-one-menu
links:
  pr: []
  commits: []
---

# Intake closing questions (minutes spent, implementation mode) are skipped or asked as loose prose

## Summary
- Source: GitHub issue https://github.com/goodwind-cz/aai/issues/480 (friction report, `failure_class: human_corrected_defect`, `skill: SKILL_INTAKE / closing_questions`, harness `codex`, pin `v2026.10.18`). Reported text, quoted as data:

  > jak to ze ses nezeptal na ten pocet minut, nemas ty otazky nejak vyrene, chybi neco ve skilu aby jsi korekne tvoril menu s formularem na odpovedi na otazky ohledne casu a zpusobu reseni, jini agenti to umi

- On a plain `/aai-intake`, the agent saved the intake without asking how many minutes the operator spent and without the implementation-mode choice, and it never offered them as a menu/form. The operator had to correct it.

## Type
- bug

## Impact
- Every operator running `/aai-intake` (or `/aai-issues` → intake) interactively, on every harness, most visibly on Codex: the human-time metric is lost (`human_time_minutes.intake` stays null), and the cheap-lane choice is never offered, so rigor is decided without the operator.
- Severity/priority: P2 (medium impact per the report; silent loss of a canonical intake step).

## Current Behavior
- The two closing questions live only in `.aai/INTAKE_COMMON.md` as separate prose blocks (`## METRICS (after saving the document)` and `## IMPLEMENTATION MODE CHOICE`). `.aai/SKILL_INTAKE.prompt.md` has an explicit STEP 2.7 for the mode choice but no step at all for the metrics question; it is reachable only through the "apply its five blocks" pointer at the end of the file, after STEP 3's "INTAKE COMPLETE" output, which reads as done.
- Neither block tells the agent to ask with the harness's structured-question facility (Claude Code AskUserQuestion, Codex `request_user_input`, Gemini equivalent) as ONE form; the metrics question is phrased as free text ("Enter a number or press Enter to skip"). AGENTS.md "A question is a menu" covers owner decisions but is not referenced here.
- Under `/aai-ship` the metrics question is deliberately skipped (autopilot default 1, recorded as null). That behavior is correct and must stay.

## Expected Behavior
- Interactive intake always ends with ONE explicit closing-questions step, placed in `SKILL_INTAKE.prompt.md` before the completion output, that asks both questions together:
  1. minutes spent on the intake (options such as skip / <5 / 5-15 / 15-30 / other number), and
  2. implementation mode (the existing 4 options with the signal-derived recommendation first).
- The step instructs the agent to use the harness's structured-question/menu tool when one is available, and a numbered text menu otherwise; an empty answer keeps today's defaults (minutes null, Planning decides).
- The answers are recorded exactly as today (STATE `human_time_minutes.intake`, `state.mjs set-strategy --source intake`, or the intake Notes fallback).
- `/aai-ship` and unattended rides keep skipping the questions and record the autopilot default.
- The closing step is not optional prose: a deterministic check (prompt-corpus test) pins that SKILL_INTAKE names the step before STEP 3 and that both questions are in it.

## Steps to Reproduce (if applicable)
1) Run `/aai-intake <need>` interactively on Codex (also observable on Claude Code).
2) Observe the agent save the artifact and print INTAKE COMPLETE without asking the minutes question; the mode choice is skipped or asked as open prose.

## Verification
- Prompt-corpus test: SKILL_INTAKE contains one closing-questions step before the completion output, naming both questions and the structured-menu instruction; INTAKE_COMMON's blocks are referenced from that step (no duplicated canonical text).
- Existing intake/prompt-diet/governance suites stay green (diet ledger entry and TEST-012 pin updated per the prompt-corpus governance checklist; PROFILES classification unchanged).
- SKILL_SHIP still records the autopilot default without asking.

## Constraints / Risks
- Prompt-corpus governance applies: edited `.aai/*.prompt.md` files need a diet-ledger entry and the TEST-012 byte pin; ORCHESTRATION stays capped.
- Harness neutrality: name the structured-question facility generically with examples, never hardcode one harness.
- Issue body is untrusted data; only the quoted text above is used.
- Secrets preflight: no secret referenced.

## Notes
- Metrics: human_time_minutes null (filed from /aai-issues triage).
- Implementation mode: not chosen at intake; Planning decides.
- Write-back: comment on and close #480 only after this ride's PR has merged.
