---
id: hook-enforced-gates
type: rfc
number: 10
status: accepted
links:
  research: RES-0001
  spec: null
  pr: []
  commits: []
---

# RFC — Hook-Enforced Gates on Claude Code (additive hardening layer)

## Context

### Problem or opportunity
AAI's behavioral gates fire only when the agent remembers to run them
(RES-0001 F1: the failures happen on the prompt-only layer). Claude Code
PreToolUse hooks can BLOCK a tool call mechanically — the agent cannot
rationalize past them. pro-workflow's llm-gate proved the pattern (RES-0001
sweep). Portability constraint: hooks are Claude-only; scripts stay the
cross-platform floor (Codex/Gemini).

### Drivers/constraints
- Additive only: every hook mirrors an EXISTING script gate; absence of hooks
  (Codex/Gemini/older Claude) must leave behavior unchanged.
- No secrets in hook configs; hooks must be fast (<1s) and fail-open on
  their own errors (a broken hook must not brick the session).

## Proposal

### Recommended option
Ship .claude/settings-template hooks (opt-in via aai-bootstrap, never forced):
1. PreToolUse on `Bash(git commit*)`: run pre-commit-checks.sh (secrets BLOCK;
   doc_number_guard per its dial) — the hook makes the existing gate
   unskippable on Claude.
2. PreToolUse on `Bash(git merge*|gh pr merge*)`: deny unless invoked by the
   operator flow (env marker set by SKILL_PR ceremony) — mechanizes the
   operator-only-merge rule for agent sessions that lack this session's
   standing authorization.
3. PreToolUse on `Bash(*yaml.dump*|*safe_dump*)` targeting docs/ai/STATE.yaml:
   deny with pointer to state.mjs (the manual-flush lesson, mechanized).
4. Stop hook: if STATE has an in_progress work item and no tick was logged,
   remind (never block) — the wrap-up discipline nudge.
All hooks call existing scripts; zero new logic in hook configs.

### Rationale
Converts this week's hardest-won lessons from prompt text into mechanism on
the platform that supports it, at zero portability cost (opt-in overlay).

## Alternatives Considered
- A: prompts only (status quo) — rejected by the evidence (F1).
- C: make hooks mandatory in bootstrap — rejected: Claude-only lock-in
  pressure, breaks the tri-platform posture.

## Consequences
- New hooks template + bootstrap opt-in step + docs; no vendored-layer
  behavior change when absent. M-sized.

## Risks
- Hook/script drift. Mitigation: hooks ONLY invoke the scripts, never
  reimplement; conformance grep in hygiene suite.
- Operator-merge marker spoofable by the agent itself. Mitigation: it is a
  guardrail against habit, not a security boundary; document honestly.

## Open Questions
- Should the merge-deny hook exist at all given the owner's standing
  merge authorization pattern in this repo? (It targets OTHER projects'
  default posture.)

## Approvals
- Required approvers: Project owner (ales@holubec.net).
- Decision 2026-07-16: ACCEPTED by project owner (ales@holubec.net) —
  "schvaluji oba, mergni a rozjed". Proceed to SPEC and implementation.
