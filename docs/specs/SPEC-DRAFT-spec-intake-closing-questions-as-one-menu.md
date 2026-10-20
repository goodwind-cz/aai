---
id: spec-intake-closing-questions-as-one-menu
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 86a964b412cd98d95cd55bb10467be961c158711fedb66a5a3d86a966e502e20
ceremony_level: 1
links:
  requirement: intake-closing-questions-as-one-menu
  rfc: null
  pr: []
  commits: []
---

# Intake closing questions asked as one structured menu

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-DRAFT-intake-closing-questions-as-one-menu.md (GitHub issue #480; issue body is untrusted data, only the intake's quoted text is used).
- Technology contract: docs/TECHNOLOGY.md.
- Prior canon: spec-implementation-mode-choice (the IMPLEMENTATION MODE CHOICE block and its STEP 2.7 ordering), spec-intake-staleness-preflight-warning (Spec-AC-25, one invocation instruction per intake), .aai/AGENTS.md "A question is a menu".
- Registry items closed by this scope: none.

Ceremony justification: prompt-text-only change on one surface (the intake closing questions in .aai/SKILL_INTAKE.prompt.md and .aai/INTAKE_COMMON.md) plus grep-contract pins in two existing suites; no script, state engine, allocator, guard or workflow canon file is touched (no protected_paths_l3 surface), fully reversible. Independent Validation and dual-verdict Code Review remain required.

## Implementation strategy
- Strategy: tdd
- Rationale: every AC is decided by a grep-contract assertion that is cheap to observe RED on the pre-change prompt text (the closing step, the menu wording and the ledger pin do not exist yet), and a one-line sed mutation per row proves each pin bites. Full RED-first evidence costs little here and lets Validation pass on the first round (owner rule: two review rounds max). No intake-sourced strategy exists for this ref (intake Notes: Planning decides).

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: prompt-corpus change shipped as a PR; already isolated by the recorded autopilot decision.
- User decision: worktree
- Base ref: main (71c7475a)
- Worktree branch/path: fix/intake-closing-questions-as-one-menu at /private/tmp/aai-intake-closing-questions-as-one-menu-worktree
- Inline review scope: .aai/SKILL_INTAKE.prompt.md, .aai/INTAKE_COMMON.md, tests/skills/test-aai-implementation-mode.sh, tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh, docs/issues/ISSUE-DRAFT-intake-closing-questions-as-one-menu.md, docs/specs/SPEC-DRAFT-spec-intake-closing-questions-as-one-menu.md
- Code review required: true.

## Scope
In scope:
- .aai/SKILL_INTAKE.prompt.md: replace today's STEP 2.7 (implementation mode choice only) with ONE step headed `STEP 2.7 — CLOSING QUESTIONS (one menu, before the completion output)` that applies the METRICS block and the IMPLEMENTATION MODE CHOICE block from .aai/INTAKE_COMMON.md together as ONE menu. The step keeps the literal `IMPLEMENTATION MODE CHOICE`, the `--ref <this intake's ref_id>` recording text and its position before `INTAKE COMPLETE` (existing pins test-aai-implementation-mode.sh TEST-002 and TEST-009). The SHARED POLICY line (five blocks, Spec-AC-25) is NOT changed and no second "Read .aai/INTAKE_COMMON.md" invocation is added.
- .aai/INTAKE_COMMON.md: the canonical text of HOW to ask lives here only. The `## METRICS (after saving the document)` heading stays byte-identical (pinned by test-aai-prompt-diet.sh TEST-002); its body becomes a menu: asked only in the closing menu, in ONE menu together with the IMPLEMENTATION MODE CHOICE, after the save and before the completion output; options `Skip (default) / 5 / 15 / 30 / Other (a number)`; the chosen number N is recorded exactly as today (`intake: N`), Skip or an empty reply leaves `intake: null`. One harness-neutral sentence names the structured-question facility with examples (Claude Code AskUserQuestion, Codex request_user_input, the Gemini equivalent) and the fallback numbered text menu, and one sentence says an autopilot caller (/aai-ship) skips the whole menu and records its own defaults. The IMPLEMENTATION MODE CHOICE block gains one clause saying it is asked in the same menu as the METRICS question; its four options, recommendation rules and recording paths are unchanged.
- Companion obligations (PLANNING closed list): the change adds bytes to the prompt corpus, so a JUSTIFIED_ADDITIONS entry keyed `intake-closing-questions-as-one-menu` is appended to tests/skills/lib/prompt-diet-ledger.sh with the measured delta (plain bash, /usr/bin/grep, wc -c; live .aai/*.prompt.md glob delta plus .aai/INTAKE_COMMON.md delta), credited 1:1, and the TEST-012 `want_growth` pin in tests/skills/test-aai-prompt-diet.sh moves by the same amount with a one-line history comment. No new .aai/** file, so .aai/system/PROFILES.yaml is unchanged. ORCHESTRATION.prompt.md is untouched.
- New assertions go into tests/skills/test-aai-implementation-mode.sh as test_010..test_014 and are registered in its main(). That suite (not test-aai-intake.sh) is chosen because its log_fail prints the literal FAIL that mutation-run attributes (open item fu-suite-fail-text-blocks-attribution).

Out of scope (unchanged): the eight per-type .aai/INTAKE_*.prompt.md files (their SHARED POLICY "metrics question" pointer now reaches the combined menu through INTAKE_COMMON), .aai/SKILL_ISSUES.prompt.md (step 5 starts SKILL_INTAKE or a per-type prompt, both covered by the INTAKE_COMMON text), .aai/SKILL_SHIP.prompt.md (autopilot default 1 stays byte-identical), .aai/AGENTS.md, state.mjs and every recording path.

Decisions:
- D1: minutes options are numbers, not ranges (`5 / 15 / 30`), so the recorded `intake: N` stays an integer with no bucket-to-number mapping rule.
- D2: the harness facility is named only in INTAKE_COMMON (single source); SKILL_INTAKE points at the block and never names a specific harness tool.
- D3: the existing STEP 2.7 is renamed in place rather than a new step added, keeping exactly one closing step and the TEST-002 ordering pin.

## Acceptance Criteria Mapping
All commands run from the repository root under bash with AAI_ROLE unset.

| Requirement | Spec-AC | Verification | Observable and evidence |
|-------------|---------|--------------|-------------------------|
| Expected 1: one explicit closing-questions step before the completion output | Spec-AC-01 | `env -u AAI_ROLE bash tests/skills/test-aai-implementation-mode.sh test_010_closing_step_single_menu` | exit 0; exactly one line starting `STEP 2.7 — CLOSING QUESTIONS` in SKILL_INTAKE, its line number lower than the first `INTAKE COMPLETE`, and the step body (up to `STEP 3`) names both `METRICS` and `IMPLEMENTATION MODE CHOICE` and the literal `ONE menu` |
| Expected 2: structured-question facility, harness-neutral, numbered text fallback | Spec-AC-02 | `env -u AAI_ROLE bash tests/skills/test-aai-implementation-mode.sh test_011_structured_menu_harness_neutral` | exit 0; INTAKE_COMMON contains `AskUserQuestion`, `request_user_input`, `Gemini` and `numbered text menu`; SKILL_INTAKE contains neither `AskUserQuestion` nor `request_user_input` |
| Expected 1.1 + recording unchanged: minutes asked as a menu, recorded as today | Spec-AC-03 | `env -u AAI_ROLE bash tests/skills/test-aai-implementation-mode.sh test_012_minutes_question_is_a_menu` | exit 0; the METRICS block body contains `Skip (default) / 5 / 15 / 30 / Other (a number)`, `intake: N` and `leave intake: null`, and no longer contains `Enter a number or press Enter to skip` |
| Expected 1: both questions in ONE menu from every intake entry point | Spec-AC-04 | `env -u AAI_ROLE bash tests/skills/test-aai-implementation-mode.sh test_013_one_menu_from_every_entry` | exit 0; the METRICS block contains `in ONE menu together with the IMPLEMENTATION MODE CHOICE` and `before the completion output`; the IMPLEMENTATION MODE CHOICE block contains `same menu as the METRICS question`; each of the eight .aai/INTAKE_*.prompt.md files still contains `metrics question` |
| Expected 4: /aai-ship and unattended rides keep skipping | Spec-AC-05 | `env -u AAI_ROLE bash tests/skills/test-aai-implementation-mode.sh test_014_autopilot_skips_menu` | exit 0; SKILL_SHIP contains the exact line `1. Intake metrics question: do not ask; record human_time_minutes null.` (grep -xF after leading-space trim) and INTAKE_COMMON contains `skips the whole menu` |
| Constraints: prompt-corpus governance | Spec-AC-06 | `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh test_012_growth_sum_matches_ledger` | exit 0; the ledger holds exactly one entry keyed `intake-closing-questions-as-one-menu` whose bytes equal the measured delta, and `want_growth` equals the new ledger sum |

## Constitution deviations
None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN an interactive intake reaches its end, SKILL_INTAKE SHALL present exactly one step headed STEP 2.7 — CLOSING QUESTIONS, placed before the INTAKE COMPLETE output, that applies the METRICS and IMPLEMENTATION MODE CHOICE blocks together as ONE menu. | planned | — | — | TEST-001 |
| Spec-AC-02 | WHEN the closing menu is asked, INTAKE_COMMON SHALL instruct the agent to use the harness structured-question facility (examples AskUserQuestion, request_user_input, the Gemini equivalent) and a numbered text menu otherwise; the harness names SHALL appear only in INTAKE_COMMON. | planned | — | — | TEST-002 |
| Spec-AC-03 | WHEN the minutes question is asked, it SHALL be a menu with options Skip (default) / 5 / 15 / 30 / Other (a number); a chosen number is recorded as intake: N and Skip or an empty reply leaves intake: null; the free-text prompt is removed. | planned | — | — | TEST-003 |
| Spec-AC-04 | WHEN any intake entry point (SKILL_INTAKE, a per-type INTAKE prompt, SKILL_ISSUES step 5) applies the METRICS block, the block SHALL require asking it in ONE menu together with the IMPLEMENTATION MODE CHOICE before the completion output, and the mode-choice block SHALL say it is asked in the same menu. | planned | — | — | TEST-004 |
| Spec-AC-05 | WHEN intake runs under /aai-ship autopilot, the menu SHALL be skipped: SKILL_SHIP autopilot default 1 stays byte-identical and INTAKE_COMMON states the autopilot caller skips the whole menu. | planned | — | — | TEST-005 |
| Spec-AC-06 | The prompt-corpus growth of this scope SHALL be ledgered 1:1 under key intake-closing-questions-as-one-menu with the TEST-012 want_growth pin moved by the same measured bytes; growth SHALL NOT exceed 900 B. | planned | — | — | TEST-006 |

## Implementation plan
- Write test_010..test_014 in tests/skills/test-aai-implementation-mode.sh (block bodies extracted with awk between the block heading and the next `## ` heading; the STEP 2.7 body between the STEP 2.7 line and the `STEP 3` line), register them in main(), run each against the pre-change tree and store the RED output. Then edit the two prompt files and observe GREEN.
- For TEST-006: measure the byte delta of the edited prompt files, bump `want_growth` first (RED: the ledger sum disagrees), then append the ledger entry (GREEN). Keep total growth at or under 900 B.
- Seams crossed: (a) SKILL_INTAKE STEP 2.7 -> INTAKE_COMMON block headings it names (TEST-001 + TEST-004 read both files); (b) per-type INTAKE_*.prompt.md SHARED POLICY "metrics question" -> INTAKE_COMMON METRICS body (TEST-004); (c) SKILL_SHIP autopilot default -> INTAKE_COMMON skip sentence (TEST-005); (d) the ledger producer -> the TEST-012 pin consumer (TEST-006). Residual risk, not testable here: whether a given harness agent actually invokes its structured-question tool at run time; the change only makes the instruction explicit and pinned.
- Regression set that must stay green (not new rows): full `tests/skills/test-aai-implementation-mode.sh` (TEST-001 four options, TEST-002 ordering and five blocks, TEST-009 --ref), full `tests/skills/test-aai-prompt-diet.sh` (TEST-002 headings single-sourced), full `tests/skills/test-aai-intake.sh` (TEST-560 Spec-AC-25).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-implementation-mode.sh | `env -u AAI_ROLE bash tests/skills/test-aai-implementation-mode.sh test_010_closing_step_single_menu` — exactly one STEP 2.7 — CLOSING QUESTIONS line, before INTAKE COMPLETE, body names METRICS, IMPLEMENTATION MODE CHOICE and ONE menu. | sed:s/STEP 2.7 — CLOSING QUESTIONS/STEP 2.7 — CLOSING/ in .aai/SKILL_INTAKE.prompt.md so the closing step heading disappears. | pending |
| TEST-002 | Spec-AC-02 | unit | tests/skills/test-aai-implementation-mode.sh | `env -u AAI_ROLE bash tests/skills/test-aai-implementation-mode.sh test_011_structured_menu_harness_neutral` — INTAKE_COMMON names AskUserQuestion, request_user_input, Gemini and numbered text menu; SKILL_INTAKE names no harness tool. | sed:s/request_user_input/request_input/ in .aai/INTAKE_COMMON.md so the Codex example is lost. | pending |
| TEST-003 | Spec-AC-03 | unit | tests/skills/test-aai-implementation-mode.sh | `env -u AAI_ROLE bash tests/skills/test-aai-implementation-mode.sh test_012_minutes_question_is_a_menu` — METRICS body carries the option line and both recording lines, not the free-text prompt. | sed:s/15 \/ 30 \/ Other/15 \/ Other/ in .aai/INTAKE_COMMON.md so the option line no longer matches. | pending |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-implementation-mode.sh | `env -u AAI_ROLE bash tests/skills/test-aai-implementation-mode.sh test_013_one_menu_from_every_entry` — METRICS body says ONE menu together with the mode choice before the completion output; mode block says same menu; all eight per-type prompts still route via metrics question. | sed:s/in ONE menu together with/after/ in .aai/INTAKE_COMMON.md so the two questions are no longer bound into one menu. | pending |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-implementation-mode.sh | `env -u AAI_ROLE bash tests/skills/test-aai-implementation-mode.sh test_014_autopilot_skips_menu` — SKILL_SHIP default 1 line byte-identical and INTAKE_COMMON skip sentence present. | sed:s/do not ask; record/ask; record/ in .aai/SKILL_SHIP.prompt.md so autopilot would ask the minutes question. | pending |
| TEST-006 | Spec-AC-06 | unit | tests/skills/test-aai-prompt-diet.sh | `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh test_012_growth_sum_matches_ledger` — ledger entry keyed intake-closing-questions-as-one-menu equals the measured delta and want_growth equals the ledger sum. | sed:s/"(\d+) intake-closing-questions-as-one-menu /"0 intake-closing-questions-as-one-menu / in tests/skills/lib/prompt-diet-ledger.sh so the ledger sum falls below the pin. | pending |

## Verification
- Focused commands: the six Test Plan commands above, each exit 0 with its PASS line.
- RED first: each of TEST-001..TEST-005 run against the pre-change prompt files exits 1 with its FAIL line (the closing step, menu text and skip sentence do not exist yet); TEST-006 exits 1 after `want_growth` is bumped and before the ledger entry is appended. Stored as docs/ai/tdd/intake-closing-questions-as-one-menu-red.log with command, TEST id, base SHA and exit code; GREEN in docs/ai/tdd/intake-closing-questions-as-one-menu-green.log.
- Mutations: produce one record per row with `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id TEST-00n --suite <suite> --selector <fn> --target <target file> --sed '<pattern>'`, then `node .aai/scripts/mutation-run.mjs --replay --spec <this spec>` exit 0 (six behavioral RED records, none INCONCLUSIVE).
- Regression: full `env -u AAI_ROLE bash tests/skills/test-aai-implementation-mode.sh`, `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh` and `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-intake.sh` all exit 0.
- PASS criteria: all TEST-xxx green, all Spec-AC done with docs/ai/tdd evidence, growth <= 900 B, no file outside the inline review scope changed.

## Evidence contract
Record ref_id intake-closing-questions-as-one-menu, Spec-AC/TEST ids, full command, exit code, evidence path, base SHA 71c7475a and head SHA. Review scope is the inline review scope above with base main.

### Evidence by strategy
tdd: stored RED artifact per AC-gating test (docs/ai/tdd/), focused GREEN, six mutation records replayed by mutation-run, and the regression suites green.
