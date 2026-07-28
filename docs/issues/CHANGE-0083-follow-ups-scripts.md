---
id: follow-ups-scripts
number: 83
type: change
status: draft
user_visible: false
links:
  pr: []
  commits: []
---

# Change — recorded follow-ups batch A: single STATE creator, reaper raw-line capture, structured migration verdict

## Summary
- Three small recorded follow-ups, batched (operator direction 2026-07-28
  "nejdriv dokonci ty drobnosti"):
  1. autonomous-loop.sh create_state_file() was a second, drifted STATE
     creator (missing implementation_strategy/code_review/worktree/metrics;
     extra locks/ai_os) — now delegates to check-state.mjs --repair (the
     CHANGE-0074 canonical template path); fail-loud when the checker is
     unavailable instead of writing a divergent stub (SPEC-0099 residual,
     Review-By 2026-08-25 closed early).
  2. aai-reap-tests.sh emits a new additive `reaped raw:` diagnostic — the
     ORIGINAL ps snapshot line for every reaped pid — so the next TEST-018
     CI flake shows which column produced an impossible age (SPEC-0083
     AC-04 follow-up; the 38-trillion-second etime anomaly from PR #150 is
     currently un-attributable). Emitted on both exit paths (stable shape).
  3. aai-doctor.mjs migrationVerdict() returns structured {msg, ok} and
     CAT-10 aggregates on the boolean — the verdict no longer re-parses its
     own prose, so rewording a message cannot silently flip PASS/WARN
     (PR #178 review techdebt).

## Acceptance Criteria
- AC-001: a missing-STATE tree with --auto-init-state gets a
  template-canonical STATE via check-state --repair (functional fixture);
  no inline heredoc creator remains in autonomous-loop.sh (grep pin).
- AC-002: reaper output carries `reaped raw:` with the verbatim snapshot
  line for each reaped pid; header present on the no-op path too
  (deterministic unit test, RED-first).
- AC-003: doctor CAT-10 verdict identical on the live repo before/after;
  a wording-only change to a migrationVerdict message cannot flip the
  aggregate (structured return; suite green).

## Verification
- bash tests/skills/test-aai-check-state.sh (extended)
- bash tests/skills/test-aai-run-tests.sh (extended, deterministic part)
- bash tests/skills/test-aai-doctor.sh

## Constraints / Risks
- Ceremony L2 (reaper is safety-critical tooling; additive-only output
  change, decision surface untouched); review: single dual-verdict pass.
