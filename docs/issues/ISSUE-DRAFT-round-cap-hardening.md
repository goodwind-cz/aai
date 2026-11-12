---
id: round-cap-hardening
type: issue
number: null
status: draft
links:
  pr: []
  commits: []
---

# The round cap fails open on an unreadable EVENTS file and half-resets a remediation that fails both checks

## Summary
The counted review-round cap shipped by `factory-round-cap` (SPEC-0286, PR #549)
has two P2 defects, recorded as open follow-ups by that ride:

- `fu-round-budget-events-fail-closed`: `readEvents` in
  `.aai/scripts/round-budget.mjs` swallows every read error. An EVENTS file that
  exists but cannot be read (EACCES, EISDIR, EIO, ENOTDIR) is treated as empty,
  so `resetGate` sees 0/2 and lets `state.mjs reset-block` through, and
  `append-event --event round_extension --authority standing-a` sees no earlier
  standing-a extension and records a second one.
- `fu-round-cap-dual-reset`: a remediation that fixes both a validation FAIL and
  a code-review FAIL runs two `reset-block` calls and pays two rounds. At 1/2 the
  first call succeeds and the second exits 5, leaving STATE half-reset
  (`last_validation` not_run, `code_review` fail). ORCHESTRATION has no rule for
  a `reset-block` that returns exit 5.

Folded in because it is the same constant in the same file: P3
`fu-round-menu-full-command`, the owner menu's option (2) names
`append-event round_extension --authority owner` without `--event`, `--ref` and
`--reason`, so copying it verbatim fails.

## Type
bug

## Impact
- Every ride from v2026.11.12 on (the cap ships downstream through aai-sync).
- An unreadable ledger silently removes the cap the owner decided
  (`review-round-cap`, 2026-09-05) and the single-use limit of STANDING
  DECISION (a) (`wave-2-roadmap`).
- A ride whose last round fails both checks is charged double and can be left
  with a mixed STATE that dispatch then routes to a fresh validation while the
  review FAIL stays open.
- Severity/priority: P2 (as filed).

## Current Behavior
Measured on origin/main b65ca681 in a scratch directory whose
`docs/ai/EVENTS.jsonl` is a directory:
- `resetGate(<dir>, 'x')` returns `refused: false, used: 0, cap: 2`.
- `state.mjs reset-block last_validation` on a fail block exits 0, writes STATE
  and prints `WARNING ... round_reset event was not (EISDIR ...)`.
- `round-budget.mjs status` prints `rounds: 0/2` and exits 0.
- `round-budget.mjs sweep-plan` prints `SWEEP full reason=no-sweep` (conservative,
  but the reason is wrong) in a repo that has the sweep command.
- `orchestration-dispatch.mjs` exits 1 with `internal error: Error: EISDIR`
  (already fail-closed, not a dispatch).
- `check-role-output.mjs` reads the same `readEvents`; an unreadable file reads
  as "no sweep", so E-SWEEP-OWED fires with reason `no-sweep` (closed, wrong
  reason).
- A write-only EVENTS file (mode 0200: EACCES on read, append allowed) that
  already holds 3 resets and a standing-a extension (3/3 used): reset-block
  exits 0 and appends a fourth reset; a second standing-a `round_extension`
  exits 0 and is appended (measured, macOS, non-root).

## Expected Behavior
- Any EVENTS read error other than ENOENT fails closed: `reset-block` refuses
  with exit 5 and a REFUSED line naming the file and the error code, writing
  neither STATE nor EVENTS; a standing-a `round_extension` is refused (exit 1);
  `status` exits non-zero with a clear message; `sweep-plan` answers
  `SWEEP full reason=events-unreadable` after its not-applicable checks;
  check-role-output's E-SWEEP-OWED names that reason. An absent file still
  counts 0.
- One remediation is one round: when both blocks failed, the remediation resets
  both in one call that is gated once, written in one STATE write, and counted
  once. A refusal leaves both blocks as they were.
- ORCHESTRATION and REMEDIATION say what to do when reset-block exits 5, and
  dispatch at the cap returns the owner menu even when the last run was a
  Remediation.
- The menu's option (2) is a complete, runnable command for the ref.

## Steps to Reproduce
1. In a scratch directory, `mkdir -p docs/ai/EVENTS.jsonl` and create a STATE
   with a focus ref and `last_validation.status: fail`.
2. `node .aai/scripts/state.mjs --state <dir>/docs/ai/STATE.yaml reset-block last_validation`.
3. Observe exit 0, a WARNING and the block reset with no round counted.

## Verification
- New cases in `tests/skills/test-aai-round-budget.sh` reproduce each defect RED
  on the unchanged tree (EISDIR fixture, plus an EACCES fixture skipped under
  root) and pass after the fix.
- The existing TEST-3600..3615 stay green; the selected suites for the diff plus
  CORE pass; one full sweep per the ride's own sweep-plan.

## Constraints / Risks
- The joint reset needs `state.mjs` (`protected_paths_l3`): ceremony L3, worktree,
  most capable review tier, operator final-diff checkpoint before merge.
- The new round-cap rules apply to this ride itself: 2 rounds, a FAIL needs a
  backed BLOCKING entry, one full sweep.
- Prompt edits (REMEDIATION, ORCHESTRATION) need a prompt-diet ledger entry,
  the TEST-012 bump and the pr-preflight TEST-008 term; ORCHESTRATION stays at
  or under 45 lines.
- Secrets preflight: no secret referenced.

## Notes
- Assumptions (autopilot, no questions asked): the error code is surfaced but
  reset-block keeps the cap's exit 5 so every caller has one stop rule; the
  joint reset is a two-block form of the existing `reset-block` command, not a
  new subcommand; `set-validation`/`set-code-review --status not_run` stay
  uncounted (SPEC-0286 R7, out of scope).
- Source follow-ups: `fu-round-budget-events-fail-closed` (PR #549 Codex thread
  on round-budget.mjs:34), `fu-round-cap-dual-reset` and
  `fu-round-menu-full-command` (docs/ai/reviews/review-20261112T113449Z.md).
- Prior scope: docs/specs/SPEC-0286-spec-factory-round-cap.md (closed).
- Metrics: human_time_minutes null (autopilot default 1).
