---
id: focus-and-validation-state-go-stale-silently
type: issue
number: null
status: draft
links:
  pr: []
  commits: []
---

# Focus keeps a foreign spec, a validation verdict outlives the code it validated, and the sweep that finds both runs last

## Summary
- Three registry items about state that is stale but reads as current: retargeting focus
  leaves the previous scope's `spec_path` in place, a validation PASS survives a
  remediation that rewrites the validated code, and the only role that would catch either
  runs after every expensive role has finished. The fourth item in this registry group is
  the P1 probe incident, filed on its own.

## Type
- bug

## Impact
- Affected: `docs/ai/STATE.yaml` consumers, every dispatch that reads the Planning inputs
  line, and the routing that decides whether to re-validate.
- The observed cost is whole laps: one ride burned roughly 2.5 hours on two extra
  validate-remediate laps for defects only the full sweep sees.

## Current Behavior
Verified in a disposable clone of `origin/main` (`c6b32d0`):

- `fu-setfocus-keeps-stale-spec-path` (P2, observed 2026-08-14). `set-focus` to a new ref
  leaves the PREVIOUS scope's `spec_path` in `current_focus`, so the next dispatch hands
  the role a foreign spec as an input. Observed: retargeting focus to a new intake still
  listed SPEC-0131 from the finished scope on the Planning inputs line. Measured today at
  `.aai/scripts/state.mjs:13,206,417`: clearing it requires an explicit
  `--clear spec_path`, and nothing warns when `ref` and `spec_path` disagree.
- `fu-validation-staleness-undetected` (P2, observed 2026-08-14). Round 3 passed at 15:37Z;
  code review then failed and remediation rewrote the engine, the suite, the prompt and
  eight surfaces — yet SPEC-0012 G3 routing sends a pass-with-review-reset straight to rule
  13 and never re-fires rule 11. Only the validator noticing its own staleness caught it,
  and clearing it needed an owner-approved `reset-block --force`. The entry's own proposed
  shape: the verdict should carry the CONTENT HASH it was taken against, so staleness is
  mechanical rather than a matter of an agent volunteering it.
- `fu-tdd-skips-full-sweep` (P2, ticks 104-109, 2026-08-14). The TDD role declares done
  after targeted suites only, so defects visible only to the full framework sweep surface
  two roles later and cost a whole validate-remediate lap each. The cheap suites run early
  and the long one runs last, so its findings always arrive after the expensive roles have
  finished. Measured cost on that ride: two extra laps, roughly 2.5 hours, for a spec-lint
  allowlist defect and a CHANGELOG scaffold defect that only the sweep sees.

Where the members pull against each other: `fu-tdd-skips-full-sweep` argues for running
MORE of the sweep earlier, while `fu-dispatch-demands-full-sweep` (filed with the
per-suite-clone residuals) measured that mandating a full sweep on every round cost an hour
of wall-clock for findings reachable from targeted suites. Both are right about different
rounds, and planning must reconcile them rather than pick one: the question is WHICH suites
run WHEN, not whether the sweep is good.

## Expected Behavior
- Retargeting focus either clears `spec_path` or refuses while `ref` and `spec_path`
  disagree.
- A validation verdict is invalidated mechanically when the code it was taken against
  changes — by a recorded content hash, not by an agent remembering.
- The suites whose findings are expensive to receive late run early enough to be acted on.

## Steps to Reproduce (if applicable)
1) `set-focus --type <t> --ref <newRef>` after a scope that had a `spec_path`; read
   `current_focus` and observe the previous scope's `spec_path` still there.
2) Take a validation PASS, then remediate the validated code, and observe the routing send
   the ride onward without re-validating.

## Verification
- `set-focus` to a new ref leaves no `spec_path` from the previous scope, or emits a
  warning naming both values.
- A recorded verdict carries the hash it was taken against, and a mismatch blocks the
  routing that would otherwise skip re-validation.
- A ride's lap count for sweep-only defects drops measurably.

## Constraints / Risks
- `.aai/scripts/lib/state-engine.mjs` is in `protected_paths_l3`.
- Clearing `spec_path` automatically on retarget could drop a legitimately carried-over
  spec; the warning form may be the safer first step.
- Adding a content hash to the verdict changes the STATE schema and every reader of it.

## Notes
- OUT OF SCOPE: `fu-subagent-probe-hits-real-repo` (P1), the fourth item in this registry
  group. It is filed on its own as the agent-shell boundary intake.
- Registry ids covered: `fu-setfocus-keeps-stale-spec-path`,
  `fu-validation-staleness-undetected`, `fu-tdd-skips-full-sweep`,
  `fu-subagent-probe-hits-real-repo` (cross-referenced, filed separately).
