---
id: spec-reaper-epoch-survivor-robustness
type: spec
number: null
status: implementing
ceremony_level: 1
links:
  requirement: docs/issues/ISSUE-DRAFT-reaper-epoch-survivor-robustness.md
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — TEST-017 epoch-boundary margin fix (test-fixture only)

SPEC-FROZEN: true

Ceremony justification: the scope touches exactly one file,
`tests/skills/test-aai-run-tests.sh` (a test fixture), and is purely additive
(one widened `sleep`, one inline comment, one new self-contained test
function, one `ALL_TESTS` list entry). `.aai/scripts/aai-reap-tests.sh` (the
production reaper) is explicitly UNCHANGED. None of the touched paths appear
in `protected_paths_l3` (docs/ai/docs-audit.yaml): `.aai/scripts/state.mjs`,
`.aai/scripts/lib/state-engine.mjs`, `.aai/scripts/lib/state-core.mjs`,
`.aai/scripts/allocate-doc-number.mjs`, `.aai/scripts/pre-commit-checks.sh`,
`.aai/scripts/pre-commit-checks.ps1`, `.aai/workflow/WORKFLOW.md`,
`docs/CONSTITUTION.md`. Single reviewable, reversible, single-surface change
-> Level 1.

## Links
- Requirement: docs/issues/ISSUE-DRAFT-reaper-epoch-survivor-robustness.md
- Prior art: docs/specs/SPEC-0064-spec-reaper-deterministic-age-guard.md (the
  epoch-mode contract this fixture asserts against), SPEC-0009 (original
  reaper), SPEC-0062/CHANGE-0043 (an earlier margin-widen that reduced but did
  not eliminate a sibling flake — the same anti-pattern this spec must avoid
  repeating: widening without removing the boundary mechanism).
- Technology contract: docs/TECHNOLOGY.md
- Learned rules: docs/knowledge/LEARNED.md (Session 2026-07-19 — BSD/GNU
  portability; CI-authoritative-when-only-CI-reproduces).

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: see template semantics

## Problem (root cause, verified against the code)

`.aai/scripts/aai-reap-tests.sh` EPOCH MODE reaps a matched process iff:

```
start_epoch < STEP_START - GRACE          (GRACE default = 2)
start_epoch = SNAP_NOW - age
age         = etime_to_secs(etime)        # FLOOR-truncated to whole seconds
```

Confirmed in the script's own header contract (lines ~26-33) and its `GRACE`
comment (lines ~64-70): `GRACE=2` is documented as "1s etime truncation + 1s
snapshot sampling skew," and because `age` is floor-truncated, the computed
`start_epoch` can read up to ~1s LATER than the process's true start.

`tests/skills/test-aai-run-tests.sh::test_017` (lines 542-561) spawns a
survivor, `sleep 3`, then captures `step_start`. A nominal 3s gap is EXACTLY
`GRACE(2) + 1s(truncation)` — the minimum theoretically-reapable gap, with
ZERO slack. Whether the inequality clears depends on sub-second phase
alignment between the survivor's true start, the `ps` sample instant, and the
`date +%s` capture of `STEP_START`; CI load shifts that phase, producing the
intermittent `reaped: 0` failure (observed on PR #129, a diff that does not
touch the reaper).

CONCLUSION (per the intake, verified): the production reaper behaves exactly
per its documented contract. This is a test-fixture margin defect, not a
reaper defect — confirmed by reading `.aai/scripts/aai-reap-tests.sh` in full
during this planning pass; no discrepancy found between the documented
contract and the implementation.

## Scope
- In scope: `tests/skills/test-aai-run-tests.sh` only —
  1. Widen `test_017`'s survivor pre-step gap from `sleep 3` to `sleep 6`,
     with an inline comment stating the arithmetic and forbidding silent
     re-narrowing (mechanism decision below).
  2. Add a new test function (next free id: `test_021`) that drives the
     reaper with an INJECTED `AAI_REAP_STEP_START_EPOCH` derived by integer
     arithmetic from a captured reference epoch, to pin the spare-at-boundary
     vs reap-beyond-boundary decision deterministically — independent of a
     real-time race against host load.
  3. Add `"021"` to the `ALL_TESTS` dispatch list.
  4. This spec document.
- Out of scope: `.aai/scripts/aai-reap-tests.sh` (byte-unchanged — in
  particular `GRACE` stays `2`); `.aai/scripts/aai-reap-tests.ps1` (Windows
  twin — untouched, no related flake reported); any retry/loop-until-pass
  wrapper around the assertion (explicitly forbidden by the intake — hides
  the boundary instead of removing it); any change to TEST-015/016/018/019/020
  (unrelated, already deterministic per SPEC-0064); any `protected_paths_l3`
  file.
- Protected paths touched: none.

## Design — mechanism decision

Two candidates were offered by the intake:
- (a) widen the survivor's pre-step gap so the inequality clears the boundary
  by ~2-3s of slack;
- (b) derive `step_start` deterministically from the survivor's observed
  start rather than from wall-clock sleep — noting a FUTURE `STEP_START`
  triggers the legacy fail-safe (TEST-018 covers that), so any offset must
  keep `STEP_START` in the past.

CHOSEN: **(a) for `test_017`** (widen `sleep 3` -> `sleep 6`), **plus a new
test using (b)'s spirit** (`test_021`, injected `AAI_REAP_STEP_START_EPOCH`
derived by arithmetic) to pin the boundary deterministically. Rationale:

- `test_017`'s job is to prove a *realistic* pre-step survivor (spawned via a
  real `sleep`, not a synthetically-injected epoch) is reaped — that is the
  scenario the reaper actually faces in production (a leaked process from a
  *previous* step). Replacing its real-time gap with a fully-injected
  `STEP_START` would stop it from exercising the real `ps`/`date` sampling
  path end-to-end. So (a) is the right fix for `test_017` itself: widen the
  gap, not the mechanism.
- (b) alone does not remove ambiguity — an injected `STEP_START` still has to
  be positioned relative to the survivor's *real*, sampled `start_epoch`,
  which is exactly what makes `test_017` boundary-sensitive today. (b)'s real
  value is a NEW test that asserts the arithmetic directly (Spec-AC-02 below),
  which is why it is added as `test_021` rather than used to rewrite
  `test_017`.
- Widening `test_017`'s gap costs +3s of wall-clock time in one test (`sleep
  3` -> `sleep 6`); the new `test_021` costs one more short `sleep` (~4s) —
  both comfortably within "a few seconds, not tens" against an ~8-minute
  suite.

### Arithmetic — `test_017` gap widen (Spec-AC-01)

- Minimum theoretically-reapable gap under the intake's own model:
  `GRACE(2) + 1s(etime truncation) = 3s` — the CURRENT `sleep 3`, zero slack
  (the flake).
- Worst-case model (also counting the 1s `date +%s` quantization on
  `STEP_START` itself, per the intake's root-cause narrative): `GRACE(2) +
  1s(etime truncation) + 1s(STEP_START quantization) = 4s`.
- New gap: `sleep 6` (the intake's own example (a)).
- Slack under the lenient model: `6 - 3 = 3s`. Slack under the conservative
  worst-case model: `6 - 4 = 2s`. Both are strictly positive — the inequality
  clears the boundary under either model, with explicit, documented slack.
- Cost: +3s added to one test, once. Negligible against the ~8-minute suite.
- REQUIRED inline comment (enforced structurally by TEST-001 below) must
  state this arithmetic and explicitly forbid narrowing the gap back toward
  3s without re-deriving the slack — so a future maintainer cannot "tune" the
  margin away, repeating this defect (the anti-pattern flagged in the
  intake's Notes: "the pattern across all of them is the same").

### Arithmetic — `test_021` deterministic boundary probe (Spec-AC-02)

Algorithm (drives the REAL, unmodified `.aai/scripts/aai-reap-tests.sh`, so
this is an integration test crossing the test-file / reaper-contract seam
end-to-end, not two units mocking the boundary — see Seam analysis below):

1. `ref_epoch="$(date +%s)"` — captured via a single `date +%s` call
   IMMEDIATELY BEFORE spawning the survivor.
2. `survivor_pid="$(spawn_marked "vitest_boundary21_${ws}/worker")"`; `track`
   it (existing helpers, see `tests/skills/test-aai-run-tests.sh:61,79-85`).
3. `sleep 4` — comfortably clear of the `etime` 0-1s rounding edge (mirrors
   TEST-015's existing "comfortably beyond default GRACE(2)" idiom at line
   482), so the survivor's sampled elapsed time is a stable reading rather
   than itself boundary-adjacent.
4. `grace=2` — a LOCAL constant that MUST equal
   `aai-reap-tests.sh`'s own default `AAI_REAP_GRACE_SECS` (2). The test does
   NOT override `AAI_REAP_GRACE_SECS` — it exercises the PRODUCTION default,
   consistent with the "production reaper unchanged" constraint. Comment must
   note this coupling so a future default change in the reaper is caught
   (see Residual risk below).
5. Case A — SPARE at the boundary: `step_start=$((ref_epoch + grace))`. Run
   the reaper with `AAI_REAP_STEP_START_EPOCH="$step_start"`. Assert the
   survivor is still ALIVE and the reaper reports `reaped: 0`.
6. Case B — REAP just past the boundary: `step_start=$((ref_epoch + grace +
   2))`. Run the reaper again (same still-alive survivor) with the new
   `STEP_START`. Assert the survivor is now DEAD and the reaper reports
   `reaped: [1-9]...`.

Why this is deterministic rather than a repeat of the `test_017` bug:
- `ref_epoch` is captured BEFORE the survivor spawns, so `ref_epoch <=` the
  true spawn instant (a `date +%s` taken earlier can only floor to the same
  or an earlier second than one taken later).
- `aai-reap-tests.sh`'s own header contract states the reaper's computed
  `start_epoch` for a process reads "up to ~1s LATER than the process's true
  start" — never earlier. Combined with the point above, the reaper's
  computed `start_epoch >= ref_epoch` always holds.
- At `step_start = ref_epoch + grace`, `threshold = step_start - grace =
  ref_epoch`. `start_epoch < ref_epoch` is impossible per the bound above ->
  deterministic SPARE, by construction, not by hoping a sleep window lands
  outside a fuzzy band.
- The reap decision is invariant to how long after spawn the reaper actually
  runs (SPEC-0064 / `test_016`'s already-proven "overhead cancels" property:
  `start_epoch = SNAP_NOW - age` grows both terms together), so indeterminate
  wall-clock delay between steps 1-6 does not reintroduce ambiguity.
- At `step_start = ref_epoch + grace + 2`, `threshold = ref_epoch + 2`. Under
  the same documented slop band (`start_epoch` within ~[ref_epoch,
  ref_epoch+1]), `start_epoch < ref_epoch + 2` always holds -> deterministic
  REAP.

RESIDUAL RISK (stated honestly, not papered over): the `+2` offset in Case B
assumes the gap between the `date +%s` call in step 1 and the actual process
fork in step 2 is itself sub-second under CI load. This is a reasonable
assumption (two adjacent shell statements, no I/O between them) but is not a
mathematically airtight worst-case bound against extreme scheduler stalls.
Implementation MUST empirically RED/GREEN-confirm this offset (see Test Plan
RED-proof notes) and MAY widen `+2` to `+3` if CI evidence shows it
insufficient — but must keep the same inline-comment / no-silent-narrowing
discipline as Spec-AC-01 if it does. This is recorded as an explicit residual
risk rather than an unstated assumption.

RESIDUAL RISK — EMPIRICAL RESOLUTION (implementation, 2026-07-23, macOS
Darwin 25.5.0): the `+2` offset was measured before being asserted. A probe
drove the REAL reaper 5x at each of `step_start = ref_epoch + GRACE + k` for
`k = 0,1,2,3` (20 samples), recording the reaper's own inputs alongside the
outcome. Result: the reaper's computed `start_epoch - ref_epoch` was **0 in
all 20 samples** (never negative, never +1 in practice), so `k=0` SPARED 5/5
(`reaped: 0`) and `k=1`, `k=2`, `k=3` each REAPED 5/5 (`reaped: 1`). The
asserted outcomes therefore hold with margin: Case A (`k=0`) is spare-by-
construction as derived, and Case B (`k=2`) sits a full second beyond the
smallest offset that reaped (`k=1`) while still covering the theoretical
`ref_epoch+1` reading. **No adjustment to `+2` was needed** — it is kept as
specified, with the measurement recorded in `test_021`'s inline comment and
the same no-silent-narrowing discipline as Spec-AC-01.

### Seam analysis (step 6a)

The one seam this change touches: the test fixture's assumed default
(`grace=2`, hardcoded in `test_021`) versus `aai-reap-tests.sh`'s own actual
default (`AAI_REAP_GRACE_SECS` default `2`, declared independently in the
production script). If the production default ever changes without a
matching update here, `test_021`'s boundary arithmetic silently goes stale.
Both sides ARE exercised together end-to-end by `test_021` itself (it invokes
the real, unmodified `.aai/scripts/aai-reap-tests.sh` — not a stub), so this
is a genuine integration test crossing the seam, not two units mocking the
boundary. Residual risk: a future PR could change `GRACE`'s default in
`aai-reap-tests.sh` without touching this test; TEST-007 below (byte-diff
guard on the reaper file) does not protect against that FUTURE case, only
this scope's own diff. Recorded as an explicit residual risk — no automated
guard proposed here (out of scope; a cross-file constant-sync check would be
a separate, larger scope per the intake's own "closed list" discipline
mirrored from the companion-obligations check).

## Companion obligations check (PLANNING step 3a)

Closed list, two entries, evaluated against this scope's actual file list
(`tests/skills/test-aai-run-tests.sh`, this spec doc):

1. Adds bytes to the prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`)?
   **NO** — no prompt-corpus file is touched. Prompt-diet ledger true-up
   (`tests/skills/lib/prompt-diet-ledger.sh` + TEST-012 checkpoint bump) does
   **NOT** apply.
2. Adds a NEW `.aai/**` file? **NO** — no new file under `.aai/` is created;
   the only touched files are an existing test fixture and this new spec
   under `docs/specs/`. PROFILES.yaml classification does **NOT** apply.

OUTCOME: neither companion obligation applies to this scope. No ledger
true-up, no PROFILES.yaml classification required. (Confirmed structurally by
Spec-AC-06 / TEST-006 below.)

## Constitution deviations

None.

## Acceptance Criteria Mapping

- Maps to: intake "Expected Behavior" + "Verification" sections.
- Spec-AC-01: `test_017`'s pre-step gap is widened from `sleep 3` to `sleep
  6`, with an inline comment stating the GRACE+truncation arithmetic and
  explicitly forbidding silent re-narrowing.
  - Verification: structural grep on the `test_017` function body (TEST-001).
- Spec-AC-02: A new deterministic test (`test_021`) pins the reaper's
  spare-at-boundary vs reap-beyond-boundary decision via an injected
  `AAI_REAP_STEP_START_EPOCH` derived by integer arithmetic from a captured
  reference epoch — independent of a real-time race against host load.
  - Verification: `bash tests/skills/test-aai-run-tests.sh 021` (TEST-003).
- Spec-AC-03: `test_017` still proves its ORIGINAL property unchanged: with
  `AAI_REAP_MIN_AGE_SECS=999` (a legacy threshold that would SPARE), epoch
  mode still REAPS the pre-step survivor, and the reaper reports a non-zero
  reaped count.
  - Verification: `bash tests/skills/test-aai-run-tests.sh 017` (TEST-002),
    combined with the CI repeated-run evidence in Spec-AC-05 (local pass
    alone does not prove the flake is gone — see Test Plan notes).
- Spec-AC-04: `.aai/scripts/aai-reap-tests.sh` remains byte-for-byte
  unchanged (`GRACE` stays `2`).
  - Verification: `git diff --stat <base>...HEAD -- .aai/scripts/aai-reap-tests.sh`
    is empty (TEST-007).
- Spec-AC-05: The whole suite is green locally, and the CI `skill-suite` job
  is green on Ubuntu across repeated runs — CI is the AUTHORITATIVE
  environment for this load-dependent flake; a local pass is necessary but
  not sufficient evidence.
  - Verification: `bash tests/skills/test-aai-run-tests.sh` exits 0 (TEST-005)
    + `gh run list --workflow skill-suite.yml --branch <branch>` /
    `gh run view <id>` green across repeated runs (TEST-004).
- Spec-AC-06: Companion obligations check (step 3a) run and recorded; neither
  companion applies to this scope's own file list.
  - Verification: `git diff --name-only <base>...HEAD` contains no path
    matching `.aai/*.prompt.md` / `.aai/AGENTS.md`, and no newly-added path
    under `.aai/` (TEST-006).

## Acceptance Criteria Status

| Spec-AC    | Description                                                                 | Status  | Evidence | Review-By | Notes |
|------------|------------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | `test_017` pre-step gap widened `sleep 3`->`sleep 6` + margin comment         | done    | TEST-001 structural grep: RED before edit (4 failures: not `sleep 6`, still `sleep 3`, no `GRACE(2)` comment, no `DO NOT NARROW` note) -> GREEN after (exit 0). `bash tests/skills/test-aai-run-tests.sh 017` exit 0. | — | Inline margin comment states the GRACE(2)+truncation(+quantization) arithmetic and forbids re-narrowing. |
| Spec-AC-02 | New deterministic boundary probe (`test_021`) pins spare/reap via injected STEP_START | done    | RED (existence): `test_021: command not found` pre-edit. RED (non-tautological): `AAI_REAP_SCRIPT=<stub with GRACE=0> bash tests/skills/test-aai-run-tests.sh 021` -> `FAIL: Case A ... reaped: 1`, exit 1. GREEN: `bash tests/skills/test-aai-run-tests.sh 021` exit 0. | — | Offsets empirically confirmed (see Notes under Test Plan): 20 samples, `start_epoch - ref_epoch == 0` every time; `GRACE+0` spared 5/5, `GRACE+1..+3` reaped 5/5. `+2` kept as specified. |
| Spec-AC-03 | `test_017` still proves its original epoch-vs-legacy-MIN_AGE property        | done    | `bash tests/skills/test-aai-run-tests.sh 017` exit 0; `AAI_REAP_MIN_AGE_SECS=999` + non-zero `reaped:` assertions unchanged in the diff. | — | Only the margin moved; assertions untouched. |
| Spec-AC-04 | Production reaper `.aai/scripts/aai-reap-tests.sh` byte-unchanged             | done    | `git diff --stat main...HEAD -- .aai/scripts/aai-reap-tests.sh` -> empty; `git status --porcelain -- .aai/scripts/aai-reap-tests.sh` -> empty. | — | `GRACE` stays `2`. |
| Spec-AC-05 | Whole suite green locally + `skill-suite` CI green on Ubuntu across repeated runs | deferred | Local half DONE: `bash tests/skills/test-aai-run-tests.sh` exit 0, 1:49.29 total (baseline before the change: 1:39.11 -> +10.2s). CI half NOT YET RUN — branch not pushed at implementation time. | 2026-07-30 | Deferred, not done: CI is the AUTHORITATIVE environment for this load-dependent flake and a local pass is explicitly insufficient evidence. TEST-004 (repeated `skill-suite` green on Ubuntu) is owned by Validation/PR after push. |
| Spec-AC-06 | Companion obligations check (step 3a) recorded — neither obligation applies   | done    | Scope diff = `tests/skills/test-aai-run-tests.sh` + the two draft docs only; `grep -E '^\.aai/(.*\.prompt\.md\|AGENTS\.md)$'` -> no match (exit 1); newly-added paths under `.aai/` -> no match (exit 1). | — | No prompt-diet ledger true-up, no PROFILES.yaml classification. |

## Implementation plan
- Components/modules affected: `tests/skills/test-aai-run-tests.sh` only
  (function `test_017` edited; function `test_021` added; `ALL_TESTS` string
  updated).
- Data flows: none (no product code, no runtime state).
- Edge cases: covered by the existing suite (TEST-016/018 already prove
  overhead-invariance and the legacy fail-safe; this scope does not
  duplicate them). `test_021`'s own edge case (the residual risk on the `+2`
  offset) is documented above and must be empirically confirmed during
  implementation.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                          | Description | Status |
|----------|------------|------|------------------------------------------------|--------------|--------|
| TEST-001 | Spec-AC-01 | int  | tests/skills/test-aai-run-tests.sh (test_017)  | Structural: `test_017`'s survivor pre-step gap is `sleep 6` (not `sleep 3`), and an inline comment stating the GRACE+truncation arithmetic + no-silent-narrowing warning is present in/near the function. Cmd: `grep -n "sleep 6" tests/skills/test-aai-run-tests.sh` inside the `test_017` line range, plus a grep for the arithmetic comment text. Pre-fix value: gap is `sleep 3`, no such comment — grep FAILS (this is the RED-proof: run the same grep against the file's current, unmodified content before editing). Post-fix value: grep PASSES. | green |
| TEST-002 | Spec-AC-01, Spec-AC-03 | int | tests/skills/test-aai-run-tests.sh (test_017) | Behavioral: `test_017` still asserts `AAI_REAP_MIN_AGE_SECS=999` and a non-zero `reaped:` count — the ORIGINAL property is unchanged, only the margin moved. Cmd: `bash tests/skills/test-aai-run-tests.sh 017`. Pre-fix value: this assertion already exists and typically passes locally (the bug is CI-load-only, so a local pre/post diff here is NOT independently discriminating — see notes below; combine with TEST-004). | green |
| TEST-003 | Spec-AC-02 | int  | tests/skills/test-aai-run-tests.sh (test_021, new) | New deterministic boundary probe: Case A (`step_start=ref_epoch+GRACE`) spares the survivor with `reaped: 0`; Case B (`step_start=ref_epoch+GRACE+2`) reaps it with `reaped: [1-9]`. Cmd: `bash tests/skills/test-aai-run-tests.sh 021`. Pre-fix value: `test_021` / `021` do not exist — dispatch fails ("no such function") — this IS the RED-proof for a brand-new test. Additionally, RED-proof the arithmetic itself (not just existence) by pointing `AAI_REAP_SCRIPT` at a deliberately-broken stub reaper (e.g., `GRACE` hardcoded to `0`, or the pre-epoch fixed-threshold-only legacy reaper) — mirroring the existing stub-override pattern already used by TEST-001/TEST-005/TEST-016 in this suite — and confirming Case A or Case B flips to the wrong outcome, proving the new test is not tautological. | green |
| TEST-004 | Spec-AC-05 | e2e  | .github/workflows/skill-suite.yml (CI)         | AUTHORITATIVE evidence: `skill-suite` job green on Ubuntu across a REPEATED run (at least 2 consecutive runs on the branch, or re-run the same run at least once) — the flake is CI-load-only, so this is the only environment that can falsify the fix. Cmd: `gh run list --workflow skill-suite.yml --branch fix/reaper-epoch-survivor-robustness` + `gh run view <id>` (repeat). Pre-fix value: intermittent `reaped: 0` failure observed (PR #129); this fix must not recur across repeated CI runs. | pending (CI — owned by Validation after push) |
| TEST-005 | Spec-AC-05 | int  | tests/skills/test-aai-run-tests.sh             | Local sanity: whole suite exits 0 on macOS. Cmd: `bash tests/skills/test-aai-run-tests.sh`. Pre-fix value: also typically 0 locally (the bug does not reproduce locally by design) — NOT independently discriminating; required as a regression guard, not as flake-fix evidence (see TEST-004 for the authoritative row). | green |
| TEST-006 | Spec-AC-06 | int  | (scope diff, not a test file)                  | Structural scope-guard for the companion obligations outcome: the scope's own diff touches no `.aai/*.prompt.md` / `.aai/AGENTS.md` path and adds no new path under `.aai/`. Cmd: `git diff --name-only main...HEAD \| grep -E '^\.aai/(.*\.prompt\.md\|AGENTS\.md)$'` (expect no match) and `git diff --name-status main...HEAD \| awk '$1=="A"{print $2}' \| grep '^\.aai/'` (expect no match). Pre-fix value: N/A (no diff exists yet at plan time) — this is a scope-conformance check, not a RED/GREEN behavioral test; it fails FAST if a future edit strays into either companion's trigger paths. | green |
| TEST-007 | Spec-AC-04 | int  | .aai/scripts/aai-reap-tests.sh (not modified)  | Production reaper is byte-for-byte unchanged. Cmd: `git diff --stat main...HEAD -- .aai/scripts/aai-reap-tests.sh` (expect empty output). Pre-fix value: N/A at plan time; discriminates any accidental edit to the production script during implementation. | green |

Notes:
- Every Spec-AC has >=1 TEST-xxx. Test IDs are stable post-freeze.
- RED-proof obligation: TEST-001's RED is directly reproducible on demand —
  run the identical grep against the file's CURRENT (pre-edit) content; it
  fails today because the gap is `sleep 3` and the arithmetic comment does
  not exist. TEST-003's RED is twofold: (a) the test/dispatch-id does not
  exist before implementation (trivial existence RED), and (b) the boundary
  arithmetic itself must be RED-proofed against a deliberately-broken stub
  reaper per the existing suite convention (`AAI_REAP_SCRIPT` override), so
  the new test is demonstrated to actually catch a wrong decision and is not
  tautological. TEST-002/005 are HONESTLY NOT independently discriminating
  pre/post (the bug is CI-load-only and passes locally either way) — they are
  regression guards, not flake-fix evidence; TEST-004 (repeated CI green) is
  the sole authoritative evidence that the boundary mechanism, not luck,
  produced the fix. TEST-006/007 are structural scope-conformance checks with
  no meaningful "pre-fix" state (nothing to diff yet at plan time) but
  deterministically fail if the constraints they encode are violated during
  implementation.
- CI (Ubuntu, under load) is the authoritative environment for the
  load-dependent flake this scope addresses; a green local run is necessary
  but never sufficient to claim the fix, and must not be reported as
  standalone PASS evidence for Spec-AC-05.

## Verification
- Commands: the seven rows above (TEST-001..007).
- Evidence artifacts: RED/GREEN grep output for TEST-001; RED/GREEN run logs
  for TEST-002/003 (including the stub-reaper RED-proof for TEST-003); local
  suite run log for TEST-005; `gh run` output/URLs for TEST-004; `git diff`
  output for TEST-006/007.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status AND
  the `skill-suite` CI job green on Ubuntu across a repeated run (TEST-004),
  per the CI-authoritative note above.

## Evidence contract
For each implementation / validation / TDD / code-review artifact record:
- ref_id: reaper-epoch-survivor-robustness
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

## Implementation strategy
- Strategy: loop
- Rationale: every TEST-xxx modifies or adds test-fixture code with no
  product logic; the RED-proof obligation (mandatory regardless of strategy,
  per PLANNING step 6) is satisfied structurally — TEST-001 via a direct
  before/after grep on the unmodified file, TEST-003 via existence-RED plus a
  stub-reaper RED-proof that mirrors an existing, already-established pattern
  in this suite (TEST-001/005/016's `AAI_REAP_SCRIPT` override). Full
  RED-GREEN-REFACTOR staging per TEST-xxx would add process ceremony without
  added signal for a single-file, seven-row, test-fixture-only change; loop
  covers all TEST-xxx in one focused pass while the RED-proof evidence is
  still individually captured per row.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single test-fixture file, small (a widened `sleep`,
  one inline comment, one new ~25-line test function, one list entry),
  fully reversible, already on its own branch
  (`fix/reaper-epoch-survivor-robustness`) off `main`. No protected surface,
  no cross-cutting risk, no parallel subagent fan-out needed.
- User decision: inline
- Base ref: main
- Worktree branch/path: n/a (inline)
- Inline review scope: `tests/skills/test-aai-run-tests.sh`,
  `docs/specs/SPEC-DRAFT-spec-reaper-epoch-survivor-robustness.md`

Allowed worktree recommendation values:
- not_needed: small, low-risk, clearly scoped change
- optional: useful but not important for safety
- recommended: larger, experimental, PR-bound, or parallelizable work
- required: protected workflow/state/schema, migration, or high-risk work; user may still explicitly override inline

## Code review
- Required: true
- Scope: `tests/skills/test-aai-run-tests.sh` (inline diff review; the sole
  in-scope code file)
- Base ref: main
