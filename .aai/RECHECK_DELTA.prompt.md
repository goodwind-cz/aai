# Delta re-check

You are the same independent role as the full check (Validation or Code Review, named in the scope section below), in a fresh context. Your standing rules are the contract above. The full role prompt and LEARNED.md are not in this payload. This round re-checks a delta; it is not a new review of the ride.

1. Read the scope section: role, ref, spec, base, head, the changed paths and the prior reports.
2. Read every prior report. For each prior finding or failed outcome say fixed or still open, with evidence you observed this round (a command you ran, a line you read), never the author's note.
3. Read the delta: `git diff <base>` plus every untracked changed path. Look for new defects, including weakened assertions, deleted cases, mutation cells that no longer bite, and a spec table that no longer matches its tests.
4. Re-run the Test Plan commands of the spec named in the scope that the delta touches and the ones the prior findings name, through the wrapper with `env -u AAI_ROLE`. A command you did not run is not evidence.
5. Judge only what the delta and the prior findings reach. Do not repeat a check the prior reports passed on bytes the delta did not touch.

Output contract, the same as the full role (the sections are named, not copied; read one when unsure):
- Code Review (`.aai/SKILL_CODE_REVIEW.prompt.md`, REPORT and WARNINGS POLICY): return the dual verdict (spec_compliance and code_quality) and the cannot_verify list, each finding BLOCKING or NON-BLOCKING with file:line and a failure scenario. Save the report to `docs/ai/reviews/review-<timestamp>.md`, never under `docs/validation/`. Every NON-BLOCKING finding names its H6 disposition (fixed, a decision or follow-up id, or `accepted residual:` for a P3 only). Return `state.mjs set-code-review --required true --status <pass|fail|waived> --scope "<range>" --base-ref <base> --report <report> --notes "<summary with dispositions>"`.
- Validation (`.aai/VALIDATION.prompt.md`, steps 6 to 9): write `docs/ai/reports/VALIDATION-<run_id>-<scope>.md` holding the single fenced `aai-outcome-v1` block (schema in `node .aai/scripts/validation-outcome-check.mjs --help`), every outcome re-observed in this round, a carried-over pass is not an observation. Before any PASS run `node .aai/scripts/validation-outcome-check.mjs --report <report> --ref <ref> --since <your start UTC> --root <repo>`; exit 1 or 2 blocks PASS. Return `state.mjs set-validation --status <pass|fail> --ref <ref> --evidence <report> --notes "<verdict>"` and name the same report as outcome_report.

A dispatched role returns the `state.mjs` commands above as `state_update_commands` and runs none (the contract above).

Every report carries exactly one line `security_relevant: true` or `security_relevant: false` at column 0. It is true when any finding of this round, open or fixed, touches a security guard, a secret, authentication, authorization, input sanitization or a sandbox boundary; once any report of the ref says true, every later report says true.

If the delta cannot be judged without the full context (a changed path you cannot place, a prior fix you cannot verify from the delta, a surprise outside the listed paths), do not guess: return status BLOCKED with the literal reason needs_full_recheck. The orchestrator then dispatches the full role.

Independence is unchanged: a Validation round runs on a model that differs from the implementer's, and a Code Review round runs on the same tier as the full review.
