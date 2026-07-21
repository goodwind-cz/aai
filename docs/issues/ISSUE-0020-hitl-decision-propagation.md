---
id: hitl-decision-propagation
number: 20
type: issue
status: draft
links:
  pr: []
  commits: []
---

# HITL resolve is a no-op for the loop: the answer never reaches the STATE field that gates it

## Summary
- Resolving a human-in-the-loop block records the decision but CANNOT write it into
  the `docs/ai/STATE.yaml` field the loop actually reads, because the resolver is
  explicitly forbidden from touching anything but `human_input`. The next tick
  therefore re-raises the same question (or the stagnation guard halts the loop).
  Reported from a downstream AAI deployment (agent restarted without context after
  HITL) and independently reproduced twice in this repo's own sessions.

## Type
- bug

## Impact
- The loop **cannot make progress through a HITL gate** without a human hand-editing
  STATE (or an operator running the right `state.mjs` setter manually). Every
  STATE-gated HITL trigger is affected — most visibly the worktree decision
  (trigger #7). Severity: **high** — it breaks the core autonomous-loop promise at
  exactly the point designed for human input, and it is silent (the decision looks
  recorded; only the loop's non-progress reveals it).

## Current Behavior (root cause — exact contradiction)
1. `.aai/ORCHESTRATION_HITL.prompt.md` HITL TRIGGER **#7** raises a block:
   "Worktree recommendation is `recommended` or `required` and the user has not
   chosen worktree, inline, or waiver".
2. `.aai/SKILL_HITL.prompt.md` resolves it but is forbidden from propagating:
   - STEP 5: "Update … `human_input.required: false` … **Do NOT change any other fields.**"
   - STRICT RULES: "**Do NOT modify any STATE.yaml field other than `human_input` and `updated_at_utc`.**"
3. `.aai/scripts/state.mjs` `set-human-input` edits only the `human_input` block
   (`editBlock(state.lines, 'human_input', …)`) — it cannot set `worktree.user_decision`.
4. `orchestration-dispatch.mjs` **rule 8** gates on the field nobody is allowed to write:
   `IF worktree.recommendation in {recommended, required} AND user_decision == undecided
    -> dispatch Worktree decision`.

Net effect: human answers "inline" → decision written to `docs/decisions/` +
`decisions.jsonl` → `human_input` cleared → `worktree.user_decision` still
`undecided` → rule 8 fires again → same question, or stagnation guard halts.

## Expected Behavior
- Resolving a HITL block **actually unblocks the loop**: the answer is applied to the
  STATE field the question governs, so the next tick advances instead of re-asking.
- The safety intent of the original rule (a resolver must not make sweeping,
  unrelated STATE edits) is preserved — narrowed, not removed.

## Steps to Reproduce (if applicable)
1) Reach a scope whose spec sets `worktree.recommendation: recommended` with
   `worktree.user_decision: undecided`.
2) Run a tick → rule 8 dispatches the worktree decision → HITL block raised.
3) Answer "inline" via the HITL resolver (`/aai-hitl`).
4) Run a tick again → rule 8 fires AGAIN (`user_decision` is still `undecided`).
   Observed in a downstream deployment (loop halted by the stagnation guard) and
   twice in this repo (worked around by manually running
   `state.mjs set-worktree --user-decision inline`).

## Verification
- A resolved worktree HITL leaves `worktree.user_decision` set (e.g. `inline`), and a
  subsequent `orchestration-dispatch.mjs` tick does NOT re-dispatch rule 8.
- The resolver prompt declares an explicit trigger→target mapping (grep-assertable)
  and still forbids edits beyond `human_input` + the one declared target field.
- `./tests/skills/test-aai-orchestration-dispatch.sh` (or the suite Planning picks)
  proves: STATE with `recommendation=recommended, user_decision=inline` → rule 8 does
  NOT fire; with `undecided` → it does.
- Existing suites stay green; `skill-suite` CI green on Ubuntu.

## Constraints / Risks
- **Ceremony/scope trade-off (Planning must decide):** adding a `decision_target`
  field to the `human_input` block would require changing `.aai/scripts/state.mjs`,
  which is in `protected_paths_l3` (docs/ai/docs-audit.yaml) → **ceremony_level 3
  becomes mandatory** (and L3 makes a worktree decision mandatory — ironic here).
  **Recommended alternative that stays L2 and needs no protected-path change:** keep
  the STATE schema as-is and make the RESOLVER apply the answer through the EXISTING
  typed setters, driven by an explicit trigger→setter mapping declared in the prompt
  (e.g. trigger #7 → `state.mjs set-worktree --user-decision <inline|worktree|waiver>`;
  code-review waiver → `set-code-review --status waived`). Prompt-only change,
  reuses the single-writer CLI, no schema churn.
- The guardrail must be NARROWED, not deleted: the resolver may write `human_input`
  **plus the one STATE field the answered question governs**, via the typed CLI —
  nothing else. Keep that wording explicit so the resolver cannot drift into general
  STATE editing.
- Answer normalization: free-text human answers must map safely to the setter's enum
  (e.g. "i"/"inline" → `inline`); an unmappable answer must fail closed (leave the
  gate unresolved and re-ask) rather than guess.
- Prompt-diet byte floor: editing `.aai/*.prompt.md` grows the corpus — budget a
  `JUSTIFIED_ADDITIONS` ledger true-up (recurring in this repo, see LEARNED).
- No secret referenced — SECRETS PREFLIGHT skipped.

## Notes
- Downstream report (verbatim summary): decision saved to the decision artifact, but
  `worktree.user_decision` stayed `undecided`; the loop "didn't see progress" and its
  anti-stagnation protection stopped it. Their immediate unblock — writing
  `worktree.user_decision: inline` — is exactly the manual workaround used here.
- This is squarely the "the workflow itself must remove the problem" class: it will
  keep biting every deployment that pulls the layer until fixed upstream.
