---
id: role-verification-guards
number: 146
type: change
status: done
user_visible: false
ceremony_level: 1
capability: aai-workflow
links:
  pr:
    - 261
  commits:
    - 797c742
---

# Change — four guards where roles trust each other instead of checking

## Summary
- Four places in the ride where one role accepts another's word and nothing
  verifies it. Each guard is a WARNING on an existing surface: no new script,
  no new gate, no new dependency, no new file.
- The CHANGE-0145 ride is the evidence for all four. It ran roughly 30 hours
  and at least five of those are directly attributable to these gaps.

## Motivation / Business Value
- G1 — close after merge: `close-work-item.mjs` already receives `--pr N`, so
  it can read that PR's state. On PR 260 the close ran AFTER the merge, so the
  close, autogen and telemetry commits landed on main under a
  "Bypassed rule violations, 3 of 3 required status checks are expected" push
  with no CI at all. The previous ride (PR 259) did it in the documented order,
  so this is an ordering hazard rather than a broken rule.
- G2 — stale validation verdict: a recorded `pass` survived a remediation that
  rewrote the engine, the suite, the prompt and eight description surfaces.
  Nothing detected it; the validator happened to run its own drift check after
  waking and disowned its verdict voluntarily. Clearing it needed
  `reset-block --force` under an explicit owner decision.
- G3 — TDD declares done without the sweep: the role finishes after targeted
  suites, so defects only the 79-suite framework run can see arrive two roles
  later and cost a full validate-remediate lap each. On CHANGE-0145 that was
  two blockers (a branch-diff allowlist entry and a CHANGELOG scaffold) and
  roughly 2.5 hours.
- G4 — a waiter that never fires: twice in one ride a subagent waited on a long
  background run and missed its completion; the second time it slept five hours
  after the sweep had already written `summary.txt`. Both waiters matched a
  pattern in the output stream; the framework prefixes its summary line with
  colour codes, so the pattern never matched.

## Scope
- In scope: one warning apiece at G1..G4, on surfaces that already exist.
- Out of scope: making any of them blocking; changing the dispatch rule table;
  the P1 `fu-subagent-probe-hits-real-repo` (a read-only role wrote to the real
  repository) — that is an isolation design question, not a warning, and gets
  its own scope.

## Affected Area
- `.aai/scripts/close-work-item.mjs` (G1)
- G2: see the L3 constraint below — the naive home is protected
- `.aai/SKILL_TDD.prompt.md` (G3)
- `.aai/SUBAGENT_PROTOCOL.md` and/or the role prompts that arm waiters (G4)

## Desired Behavior (To-Be)
- G1: closing a work item whose PR is already `MERGED` prints one named line
  saying the close commit will be part of neither the PR nor CI. Exit code
  unchanged — closing from another clone after a merge is legitimate.
- G2: a recorded validation verdict carries the content hash it was taken
  against, and the next dispatch can tell mechanically that the tree moved
  under it instead of relying on an agent to volunteer the fact.
- G3: the TDD role does not report done until the full framework sweep has run
  once, or it states plainly that it did not run and why.
- G4: waiting on a long background run polls the ARTIFACT ON DISK, never a
  pattern in the output stream. Where a role prompt teaches waiting, it teaches
  the disk-poll form.

## Acceptance Criteria
- AC-001: closing a work item against a merged PR emits the named warning
  exactly once; closing against an open PR emits nothing new.
- AC-002: the warning never changes the exit code, on either path.
- AC-003: a validation verdict recorded after this change carries the content
  hash of the tree state it judged.
- AC-004: a dispatch that runs after the judged content changed can report the
  verdict as stale without any agent volunteering it.
- AC-005: no new gate is introduced by AC-003 or AC-004 — a stale verdict is
  reported, not refused.
- AC-006: the TDD role prompt requires a full-sweep result, or an explicit
  named statement that it did not run, before reporting done.
- AC-007: no guidance anywhere instructs waiting on a pattern in a process
  output stream; the disk-artifact poll is the taught form.
- AC-008: every changed prompt keeps its diet-ledger entry and TEST-012 pin
  consistent, and no prompt exceeds its line cap.

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-close-work-item.sh`
  (or the suite that owns close-work-item, whichever exists)
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` clean
- Full framework sweep once, before reporting done (this scope's own G3 rule,
  applied to itself)

## Constraints / Risks
- **L3 TRAP, read this before designing G2.** The obvious home for a validation
  content hash is the `last_validation` block, written by
  `.aai/scripts/state.mjs` — which is in `protected_paths_l3`
  (docs/ai/docs-audit.yaml). Touching it makes the WHOLE scope ceremony L3:
  operator sign-off plus a mandatory FULL_RUN. There is a cheaper route worth
  evaluating first: `orchestration-dispatch.mjs` (not protected) ALREADY
  computes and prints the frozen spec's `content_hash` in its state summary,
  and `docs/ai/EVENTS.jsonl` is an append-only audit log written through
  `append-event.mjs` (not protected). Recording the judged hash as an event and
  comparing it at dispatch achieves AC-003 and AC-004 without entering the
  protected surface. If Planning concludes the STATE block is genuinely the
  right home, say so explicitly and STOP for operator sign-off rather than
  proceeding.
- G3 makes every ride pay one full sweep (~35 minutes) inside the TDD role. The
  bet is that paying it once early is cheaper than paying a validate-remediate
  lap later; on CHANGE-0145 it would have been. Planning should say plainly
  whether that trade holds for small rides, and consider tying it to the lane
  or ceremony level rather than applying it unconditionally.
- Every guard is report-only. A warning that becomes a gate is a scope
  violation here, not an improvement.
- No secret is referenced by this scope.

## Notes
- Explicit assumptions, recorded instead of asking (ship autopilot default 3):
  - A1 — `ceremony_level: 1` is an intake suggestion on the expectation that G2
    stays off the protected surface. If it cannot, the level is 3 and the ride
    stops for sign-off. Planning declares the binding value.
  - A2 — G4 may turn out to be documentation only, if no code arms a waiter.
    That is an acceptable outcome; say so rather than inventing code to change.
- Registry items closed by this scope: `fu-close-after-merge-bypasses-ci`,
  `fu-validation-staleness-undetected`, `fu-tdd-skips-full-sweep`,
  `fu-subagent-long-wait-never-wakes`.
- Deliberately NOT in this scope: `fu-subagent-probe-hits-real-repo` (P1).
