# Verify Skill - Verification-Before-Completion Gate

## Goal
Prevent completion claims (Implementation hand-off, TDD GREEN, Validation
verdicts) from outrunning the evidence backing them. This is the single
source of truth for the gate function and rationalization table referenced
by `.aai/IMPLEMENTATION.prompt.md`, `.aai/VALIDATION.prompt.md`, and
`.aai/SKILL_TDD.prompt.md`.

Source: RES-0001 P2 recommendation 7a — Superpowers
verification-before-completion pattern (Iron Law, gate function,
rationalization table, verify-subagent-reports-via-diff).

## Iron Law
NO COMPLETION CLAIM WITHOUT FRESH VERIFICATION EVIDENCE FROM THE CURRENT TREE
STATE. "Fresh" means produced after the last edit to any file in scope.
Evidence from before the latest change is void, no matter how recent it felt.

## Gate function
Every completion claim passes through this exact chain, in this order, with
no step skipped:

IDENTIFY → RUN → READ → VERIFY → CLAIM

1. IDENTIFY the specific claim about to be made — which test, which build,
   which behavior, on which files.
2. RUN the command that can falsify it. For test suites, run through
   `.aai/scripts/aai-run-tests.sh <cmd>` (LEARNED rule) — never invoke the
   test runner directly.
3. READ the full output, not just the exit-code banner and not just the
   tail.
4. VERIFY the output actually matches the claim: right suite, right tree
   state, zero exit code, no test silently skipped-and-counted-as-passed.
5. Only then CLAIM — citing the command, its exit code, and the evidence
   path or log.

A claim made before RUN, or based on output that was not READ in full, is not
a claim — it is a guess wearing a claim's clothes.

## Rationalization table
Stop and correct if you catch yourself thinking any of these:

| Rationalization | Counter |
|---|---|
| "Tests passed earlier this session" | State changed since then. Stale evidence is void — re-run against the current tree. |
| "I only changed docs/comments" | Prove it with `git diff --stat` first. If it touches code, the exemption does not apply. |
| "The subagent reported success" | A subagent's self-report is a claim, not evidence. Inspect the tree yourself before accepting it. |
| "The diff looks right, no need to run it" | Reading code is not executing it. Looks-right code fails at runtime constantly. |
| "I ran part of the suite, the rest can't be affected" | Run the whole suite. Blast radius is a guess until proven. |
| "Exit code was 0, no need to read the output" | Exit 0 with silently-skipped tests is a false green. Read the full output. |
| "It's a trivial one-line fix" | Trivial fixes break builds too. The gate carries no size exemption. |

## Verify-subagent-reports-via-diff rule
A subagent's self-reported "done" is a claim, not evidence — the same
strength as your own unverified claim. Before accepting it:
1. Run `git status --porcelain` and `git diff` in the real tree to confirm
   the reported files actually changed, and changed as described.
2. Re-run the gating check yourself, in the accepting context. Do not relay
   the subagent's own test-run output as if it were your evidence.

If the diff does not match the report, the report is void; treat the task as
not done.

## Applicability
This gate binds every completion boundary in the workflow:
- Implementation hand-off (`.aai/IMPLEMENTATION.prompt.md`)
- TDD GREEN and Phase 4 completion (`.aai/SKILL_TDD.prompt.md`)
- Validation PASS/FAIL verdicts (`.aai/VALIDATION.prompt.md`)

No role may skip this gate by citing scope size, model tier, or time
pressure.
