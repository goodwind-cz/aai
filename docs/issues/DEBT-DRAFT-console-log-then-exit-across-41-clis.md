---
id: console-log-then-exit-across-41-clis
type: techdebt
number: null
status: draft
links:
  pr: []
  commits: []
---

# 41 CLIs still print and then exit, and the arm that proves the one fix works does not hold it

## Debt Summary
- `follow-ups.mjs list --json` used to stop at exactly 65536 bytes when stdout was a pipe,
  emitting invalid JSON, because the process printed with `console.log` and then called
  `process.exit`. That ONE file was fixed. Forty-one of the fifty-two `.aai/scripts/*.mjs`
  CLIs still have the same shape, the arm that pins the fix does not assert its own
  precondition, and two of the four items in this registry group are orchestrator
  incidents that rode in with the same scope.

## Root Cause
- `process.exit` does not wait for a pending asynchronous write on a pipe. `console.log`
  to a pipe is asynchronous. Every CLI written in that idiom truncates its own output the
  day the payload crosses the buffer.

## Current Cost / Risk
Verified in a disposable clone of `origin/main` (`c6b32d0`):

- `fu-cli-exit-truncates-pipe-sweep` (P2). Measured today: of the 52 files matching
  `.aai/scripts/*.mjs`, 41 contain BOTH `console.log` and `process.exit` — matching the
  count the registry entry recorded. The largest payloads named there are `docs-audit.mjs`
  (23 logs), `test-canon.mjs` (28), `docs-canon.mjs` (23) and `metrics-flush.mjs` (15). The
  guard that fixes the shape (`installPipeGuard`) is present in exactly two files:
  `.aai/scripts/follow-ups.mjs` and `.aai/scripts/sync-harness-skills.mjs`.
- The originating scope deliberately fixed ONE file. A repo-wide sweep needs its own scope,
  its own per-CLI exit-code proof and its own regression pins; doing it inside that ride
  would have made the diff unreviewable.
- The fix demonstrably works where it is applied. Measured today:
  `node .aai/scripts/follow-ups.mjs list --status open --json | wc -c` gives 106502 bytes,
  identical to the same command redirected to a file — well past the old 65536 cut.
- `fu-test021c-precondition-unasserted` (P2, code review NB-1). TEST-021(c) in
  `tests/skills/test-aai-follow-ups.sh` (the arm block begins at `:1318`) never asserts its
  own precondition that the reader is GONE before the write, so the arm reaches the same
  observable with the guard removed and an open reader. Measured 10 of 10 both ways: the
  arm can go green without ever invoking `installPipeGuard`. It is the ONLY arm holding the
  load-bearing half of the EPIPE guard, and it does not hold it.
- `fu-orchestrator-mutated-real-file` (P2, 2026-08-21). The orchestrator ran a bite-proof
  mutation against the tracked suite file `tests/skills/test-aai-follow-ups.sh` instead of a
  copy, and the first restore attempt silently failed on a mis-anchored `sed`. Detected by
  `git diff --stat`, reversed and re-verified. The near-miss was shipping a test with a
  shrunken fixture that cannot fail — inside a ride about assertions that cannot fail. This
  is the scar HAZ-RESTORE now cites, and it is an orchestration hazard rather than a CLI
  defect.
- `fu-main-push-conflicts-open-pr` (P2, 2026-08-21). The orchestrator pushed a commit to
  main that regenerated `docs/INDEX.md` while a PR shipping the same generated file was
  open, turning PR 268 CONFLICTING. Fourth instance in two days of writing to a tree
  something else depends on (parallel roles, a merge mid-framework-run, a commit mid-run,
  now a push mid-PR), and the shared generated files `docs/INDEX.md`, `overview.*` and
  `factory-report.*` make it near-certain whenever a doc lands on main during an open PR.
  Also an orchestration hazard, not a CLI defect.

Where the members disagree: two of the four are about CLI output discipline and two are
about the orchestrator's own git hygiene. They share a ride, not a mechanism; the pairing
is recorded so neither half is lost.

## Target State
- Every `.aai/scripts/*.mjs` CLI either installs the pipe guard or does not exit before its
  output has drained; a caller piping any of them into a parser gets complete output.
- The arm that proves the guard works asserts its precondition, so removing the guard
  reddens it.
- The orchestrator's mutations happen in copies, and generated shared files are not
  regenerated on main while a PR carrying them is open.

## Scope
- In scope: the repo-wide CLI sweep with a per-CLI exit-code proof; the TEST-021(c)
  precondition.
- Out of scope: `follow-ups.mjs` itself, already fixed and measured above.
- Out of scope: assertions that die on their own INPUT payload (the `grep -q` pipe
  ratchet), filed with its own cluster. That is consumers; this is producers.

## Plan / Migration
- Fix TEST-021(c) first, so the guard has a real regression pin before 41 files start
  depending on it.
- Convert the CLIs largest-payload first, each with a proof that its exit code is unchanged
  and its output survives a pipe.
- Record the orchestration hazards where the orchestrator will actually read them rather
  than as CLI work.

## Verification
- For each converted CLI: pipe its largest realistic output into `wc -c` and into a
  parser; compare against the same command redirected to a file; confirm the exit code is
  unchanged for the success, usage-error and internal-error paths.
- Remove `installPipeGuard` from `follow-ups.mjs` in a disposable copy and confirm
  TEST-021(c) turns red.

## Constraints / Risks
- Touching 41 files at once is exactly the unreviewable diff the originating scope avoided;
  the sweep must be batched with per-batch proofs.
- Some CLIs rely on `process.exit` for a specific code on an error path; the conversion must
  not change any exit contract.

## Notes
- Registry ids covered: `fu-cli-exit-truncates-pipe-sweep`,
  `fu-test021c-precondition-unasserted`, `fu-orchestrator-mutated-real-file`,
  `fu-main-push-conflicts-open-pr`.
