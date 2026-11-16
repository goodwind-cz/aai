---
id: metrics-integrity-fixes
type: issue
number: null
status: draft
links:
  pr: []
  commits: []
---

# Four open follow-ups: a live-ledger test pin, two silent held-ledger failures, an outcome check reading the wrong STATE

## Summary
One ride closes four open follow-ups from `docs/ai/decisions.jsonl`:

1. `fu-merge-cleanup-026-live-decisions-pin` (P2, filed by
   `flush-drops-reopened-runs`): `tests/skills/test-aai-merge-cleanup.sh`
   TEST-026 reads the live `docs/ai/decisions.jsonl` and the live
   `origin/main` ref. Its verdict depends on what the ledger holds today, not
   on the code under test; it went red on origin/main when PR #553 merged the
   ride it pinned as unmerged, and PR #555 patched it with a second arm. Any
   later ledger write can redden it again.
2. `fu-held-ledger-git-show-silent` (P3, filed by `archive-ledger-check`):
   `recoverStateCopy` (`.aai/scripts/lib/metrics-flush-record.mjs`) reads the
   ledger at `refs/remotes/origin/<base>` with `git show`. When that call
   fails (corrupt object, output over the buffer), the held ledger is dropped
   without a word, so a run already merged on the base but not yet pulled can
   be written a second time.
3. `fu-held-ledger-tmp-write-throws` (P3, filed by `archive-ledger-check`):
   `recoverStateCopy` writes the held-ledger temp file before its `try`. An
   unwritable `os.tmpdir()` throws out of `merge-cleanup.mjs` step
   `archive-runtime` on every resume.
4. `fu-outcome-check-state-path` (P2, filed by `factory-round-cap`):
   `.aai/scripts/validation-outcome-check.mjs` binds the scope sources
   (intake, spec) from `.aai/STATE.yaml`, while the runtime STATE lives at
   `docs/ai/STATE.yaml`. A PASS outcome block is refused
   `E-OUTCOME-REPORT` unless the caller passes `--intake` and `--spec`.

## Type
bug

## Impact
- (1) Every full sweep is at risk of a red merge-cleanup suite that no code
  change caused; rides lose time chasing it.
- (2, 3) Every project that vendors the layer: merge-cleanup can double-write
  a role run into `docs/ai/METRICS.jsonl` (2) or stop with an uncaught error
  (3). Telemetry and cleanup only.
- (4) The loop's standing-PASS check (SKILL_LOOP step 1) refuses a valid
  PASS without explicit flags, forcing a needless fresh Validation.
- Severity: P2 (1, 4), P3 (2, 3).

## Current Behavior
- (1) TEST-026's second half runs `spec-amend list --json/--strict` and
  `follow-ups list` over `$ROOT/docs/ai/decisions.jsonl` and greps
  `origin/main` of the checkout under test.
- (2) `git show refs/remotes/origin/<base>:docs/ai/METRICS.jsonl` with a
  non-zero status or a spawn error leaves the held list without the base
  ledger; recovery then writes.
- (3) `fs.writeFileSync(tmp, …)` runs outside the `try`; its exception is not
  caught.
- (4) `readStateFocus` reads `<root>/.aai/STATE.yaml`.

## Expected Behavior
- (1) TEST-026 builds its own ledger and git fixture and proves the same
  contract over it: merged-ride contract amendments fold to signed, an
  unsigned merged record fails, an unmerged ride is not signed,
  `spec-amend list --strict` passes over a clean fixture ledger. No read of
  the live ledger or the live `origin/main`.
- (2) When the base ledger exists but cannot be read, the step is kept as
  `ledger_runs_unchecked` with the command to run; nothing is written. A
  base without the ref or without the file stays the existing "nothing held"
  case.
- (3) A failing temp write is kept as `ledger_runs_unchecked`; no throw.
- (4) The outcome check reads `docs/ai/STATE.yaml`, the path every other
  script uses.

## Steps to Reproduce (if applicable)
1) (4) In a checkout whose `docs/ai/STATE.yaml` focuses ref X with
   `primary_path` and `spec_path`, run
   `node .aai/scripts/validation-outcome-check.mjs --report <PASS report of X> --ref X --since <ts>`.
   Actual: refused, "scope sources are unbound".
2) (3) Run merge-cleanup `apply` with `TMPDIR` pointing at a read-only
   directory: uncaught `EACCES` from `archive-runtime`.
3) (2) Make the base ledger blob unreadable (delete its object file) and run
   merge-cleanup `apply` over a ride STATE whose run is in that blob: the run
   is written to the ride ledger.

## Verification
- New failing-first cases in `tests/skills/test-aai-merge-cleanup.sh` (2, 3,
  and the hermetic TEST-026), `tests/skills/test-aai-outcome-backcheck.sh`
  (4), and where the library is unit-covered, `tests/skills/test-aai-metrics.sh`.
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>`
  passes for each touched suite.

## Constraints / Risks
- `merge-cleanup.mjs` has a line ceiling of 1490 (TEST-058); the fixes belong
  in `lib/metrics-flush-record.mjs`.
- merge-cleanup and metrics-flush are vendored: CHANGELOG entry needed.
- Do not touch files of the parallel `effort-direct-append` ride
  (SKILL_LOOP, ROLE_COMMON).
- Secrets preflight results: no secret referenced.

## Notes
- Implementation mode (autopilot recommendation): tdd. Data-integrity fixes
  in a vendored cleanup engine plus a test hermeticity fix.
- Autopilot defaults: human_time_minutes null.
