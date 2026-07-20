---
id: spec-reaper-deterministic-age-guard
type: spec
number: 64
status: draft
ceremony_level: 2
links:
  requirement: reaper-deterministic-age-guard
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — Reaper deterministic step-start age guard

SPEC-FROZEN: true

Make the reaper's fresh-sibling-vs-survivor decision DETERMINISTIC — independent
of reaper overhead and host load — so the flaky `tests/skills/test-aai-run-tests.sh`
TEST-006/TEST-015 stop intermittently red-ing the `skill-suite` required CI check.

## Links
- Requirement / intake: docs/issues/ISSUE-0018-reaper-deterministic-age-guard.md
- Prior art: docs/specs/SPEC-0009-test-process-group-reaping-and-leak-accounting.md
  (the reaper's original workspace+etime contract), docs/specs/SPEC-0046-spec-test-wrapper-windows-fallback.md
  (the `.ps1` twin), docs/specs/SPEC-0062 / CHANGE-0043 (the 2s→5s margin widen that
  reduced but did not eliminate the flake).
- Technology contract: docs/TECHNOLOGY.md
- Learned rules: docs/knowledge/LEARNED.md (Session 2026-07-19 — BSD/GNU portability;
  CI-authoritative-when-only-CI-reproduces).

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: see template semantics

## Problem (root cause)

Guard 3 of `.aai/scripts/aai-reap-tests.sh` (lines 157-159) decides spare-vs-reap by
comparing a process's `ps` elapsed time (`etime`, whole-second granularity) to a
FIXED constant `AAI_REAP_MIN_AGE_SECS`:

```
age="$(etime_to_secs "$etime")"
[ "$age" -ge "$MIN_AGE" ] || continue
```

`age` GROWS with the reaper's own overhead (two `ps axo` snapshots + a PPID-subtree
walk) and with host load, while `MIN_AGE` is fixed. On a loaded Linux CI runner a
genuinely-fresh sibling (real age ~0s) can be SAMPLED with `etime` rounded up to
`>= MIN_AGE` and be WRONGLY reaped. Widening the margin (CHANGE-0043) only lowered
the flake probability; it did not remove the race.

## Fix (validated + refined from the intake candidate)

Replace the fixed-threshold comparison with a STEP-START-EPOCH-relative decision that
is invariant to reaper overhead:

- A producer captures the step boundary once: `AAI_REAP_STEP_START_EPOCH=$(date +%s)`
  at the START of the test step (before the test command launches), and passes it to
  the post-step reaper.
- In the reaper, capture `SNAP_NOW=$(date +%s)` at the single `ps` snapshot instant
  (immediately adjacent to `ps axo pid=,etime=,args=`). Per process compute
  `start_epoch = SNAP_NOW - age_secs` (age_secs from the existing `etime_to_secs`).
- REAP iff `start_epoch < STEP_START_EPOCH - GRACE`; otherwise SPARE.

Why this is deterministic: `SNAP_NOW` and `age_secs` are read at the SAME snapshot
instant, so if the snapshot happens later (more overhead / load) BOTH grow by the same
amount and `start_epoch` is unchanged. `STEP_START_EPOCH` is fixed from before the
step. The decision compares two fixed instants — reaper overhead cancels out. It uses
ONLY `ps etime` + `date +%s` (no `ps -o lstart` epoch parsing, no BSD-vs-GNU `date`
string parsing — the portability minefield LEARNED 2026-07-19 warns against).

### GRACE — value and justification
`GRACE` absorbs the two bounded, always-downward-on-a-fresh-sibling error sources:
1. `etime` is whole-second TRUNCATED (floor of real elapsed) → computed `start_epoch`
   can be up to <1s off.
2. `SNAP_NOW` (a separate `date +%s` read, whole-second) vs the `ps` sampling instant
   can skew up to ~1s.
Only the direction that makes a genuine fresh sibling look OLDER (reap risk) is unsafe;
`GRACE` guards exactly that. Default **`GRACE = 2`** (1s truncation + 1s sampling skew),
overridable via `AAI_REAP_GRACE_SECS` (non-integer/negative coerced to the default; the
override exists for deterministic testing, not for production tuning). 2s does not impair
reaping real survivors: a production survivor is a leaked tree from a PRIOR tick — many
seconds/minutes older than the step boundary, far outside a 2s cushion.

### Fail-safe fallback (SAFETY-CRITICAL — never widen kills)
`AAI_REAP_STEP_START_EPOCH` is EPOCH MODE only when it is a valid positive integer AND
`<= SNAP_NOW` (a future step-start is nonsense). On unset / empty / non-integer /
negative / future → fall back to the EXACT current LEGACY behavior: `reap iff age >= MIN_AGE`
(with the existing `MIN_AGE` default 0). The fallback is the shipping behavior today; it
is workspace+token scoped (Guards 1 & 2 unchanged) — it is NEVER "reap everything" / a
global kill. Both directions stay covered in each mode:
- EPOCH MODE: spares a genuine post-step sibling (`start_epoch >= STEP_START - GRACE`),
  reaps a genuine pre-step survivor (`start_epoch < STEP_START - GRACE`).
- LEGACY MODE: unchanged from SPEC-0009 (reap iff `age >= MIN_AGE`).

Epoch mode can only ever SPARE MORE than a naive constant would (it reaps strictly the
procs that predate the step) — it never broadens what is killed. Guards 1 (token) and 2
(workspace path-anchored) are untouched.

### PowerShell parity (aai-reap-tests.ps1)
The `.ps1` twin's `Get-ReapCandidates` already uses a REAL per-process `CreationDate`
(not truncated `etime`), so it does NOT have the whole-second rounding flake. Parity is
therefore CONTRACT parity, not a bug fix: add an OPTIONAL `-StepStart [datetime]` param
(from `AAI_REAP_STEP_START_EPOCH`) so a Windows step owner passing the same env var gets
consistent semantics — SPARE when `CreationDate >= StepStart - GRACE`; when `-StepStart`
is absent, behavior is byte-identical to today (falls back to `-MinAgeSeconds`). Verified
deterministically by Pester (injected `$Now` + fixture snapshot), the same way the
existing `TEST-006 (Spec-AC-04)` case tests it; native Windows kill remains manual-verified
(SPEC-0046 MV, not CI).

### Producer wiring (where the epoch is captured)
Intake-candidate refinement: the candidate said "capture it in `aai-run-tests.sh`", but
`aai-run-tests.sh` does NOT invoke the reaper (it does its own group-kill; the reaper is
run SEPARATELY by the step owner). A child wrapper's env cannot reach a sibling reaper
invocation, so the authoritative producer is the STEP OWNER: `SKILL_LOOP` (POST-TICK REAP)
and `VALIDATION` (step-boundary reap). Each captures `AAI_REAP_STEP_START_EPOCH=$(date +%s)`
at the start of the test step and exports it to the reaper it later runs. This is
documented in those prompt docs and grep-asserted (mirroring TEST-007/TEST-008). The env
contract stays fully back-compatible: a step owner that does not set it gets legacy mode.

## Implementation strategy
- Strategy: hybrid
- Rationale: the guard logic (epoch decision, GRACE, fail-safe fallback) is
  safety-critical branching that must be RED-GREEN proven per case (TDD); the `.ps1`
  parity is a deterministic Pester unit (TDD); the producer-wiring prose in
  SKILL_LOOP/VALIDATION, the reaper header/env docs, and the TECHNOLOGY.md matrix note
  are low-risk glue best covered by a single loop pass with grep asserts.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to SAFETY-CRITICAL process-killing code touching
  five surfaces (reaper `.sh`, reaper `.ps1`, two test files, two prompt docs); the RED
  proof needs a saved pre-change reaper copy and the tests spawn+kill processes — running
  them in the shared working tree (with inline `git stash`/`checkout` per the flake's
  RED-proof) risks destabilizing it (LEARNED 2026-07-19: prefer worktree isolation for
  git-mutating / process-mutating roles).
- User decision: undecided (recommendation is `recommended` → the operator decides
  worktree vs inline at Implementation Preparation before code starts).
- Base ref: fix/reaper-deterministic-age-guard
- Worktree branch/path: <if selected>
- Inline review scope: .aai/scripts/aai-reap-tests.sh, .aai/scripts/aai-reap-tests.ps1,
  tests/skills/test-aai-run-tests.sh, tests/skills/aai-win-dispatch.Tests.ps1,
  .aai/SKILL_LOOP.prompt.md, .aai/VALIDATION.prompt.md, docs/TECHNOLOGY.md

## Acceptance Criteria Mapping

- Maps to: intake "Expected Behavior" + "Verification" (deterministic spare/reap)
  - Spec-AC-01: In EPOCH mode the reaper SPARES any matching process whose
    `start_epoch = SNAP_NOW - etime >= STEP_START_EPOCH - GRACE` and REAPS any whose
    `start_epoch < STEP_START_EPOCH - GRACE`. Both directions hold with a fixed,
    known `STEP_START_EPOCH` (decision by construction, not by margin-hope).
    - Verification: `bash tests/skills/test-aai-run-tests.sh 016 017` → exit 0
      (016 spares the fresh sibling; 017 reaps the genuine survivor).
- Maps to: intake "the flake must be reproducible-then-fixed, not just margin-widened"
  - Spec-AC-02: The spare decision is INVARIANT to injected reaper delay / simulated
    load — the SAME fresh-sibling scenario yields SPARE at injected delay 0 and at
    injected delay `>= MIN_AGE + GRACE`; and the pre-change fixed-threshold reaper is
    OBSERVED FLIPPING to reap (RED) on that identical scenario.
    - Verification: `bash tests/skills/test-aai-run-tests.sh 016` GREEN against the
      fixed reaper; the same command with `AAI_REAP_SCRIPT=<pre-change reaper copy>`
      FAILS (recorded RED evidence). Migrated `... 006 015` pass deterministically.
- Maps to: intake "SAFETY: never widen what gets killed; fail-safe when unset/invalid"
  - Spec-AC-03: With `AAI_REAP_STEP_START_EPOCH` unset / empty / non-integer /
    negative / future, the reaper uses LEGACY `MIN_AGE` behavior exactly (reaps an
    aged match at `MIN_AGE=1`; spares a young one) and never issues a global kill.
    - Verification: `bash tests/skills/test-aai-run-tests.sh 018` → exit 0.
- Maps to: intake "Portability (LEARNED 2026-07-19): BSD+GNU etime + date +%s only"
  - Spec-AC-04: Epoch mode uses ONLY `ps etime` + `date +%s` (static guard: reaper
    source contains no `lstart` and no `date -d`/`date -j` string parsing) and runs
    clean under POSIX sh (dash) with no bashisms, reaping/sparing correctly.
    - Verification: `bash tests/skills/test-aai-run-tests.sh 013 019` → exit 0.
- Maps to: intake "keep the PowerShell twin in parity"
  - Spec-AC-05: `Get-ReapCandidates` honors an optional `-StepStart [datetime]`
    (from `AAI_REAP_STEP_START_EPOCH`): spares `CreationDate >= StepStart - GRACE`,
    reaps older; absent `-StepStart` → byte-identical to today's `-MinAgeSeconds` path.
    - Verification: `pwsh -Command "Invoke-Pester -Path tests/skills/aai-win-dispatch.Tests.ps1"`
      → 0 failed (the new StepStart context passes; existing contexts unchanged).
      If `pwsh` is absent on the host, evidence is the ps1-quality CI job / manual MV note.
- Maps to: intake "step-start epoch passed to the reaper"
  - Spec-AC-06: `SKILL_LOOP` (POST-TICK REAP) and `VALIDATION` (step-boundary reap)
    document capturing `AAI_REAP_STEP_START_EPOCH=$(date +%s)` at the start of the test
    step and passing it to the reaper.
    - Verification: `bash tests/skills/test-aai-run-tests.sh 020` → exit 0
      (greps both prompt docs for the capture + env handoff).
- Maps to: intake "skill-suite CI job green on Ubuntu across repeated runs"
  - Spec-AC-07: The `skill-suite` GitHub Actions job is green on Ubuntu across a
    REPEATED run (re-run 2-3× — CI is the authoritative environment for this flake per
    LEARNED 2026-07-19), on the head SHA matching branch HEAD.
    - Verification: `gh run list --workflow skill-suite.yml --branch <branch>` shows the
      run(s) `success`; `gh run view <id>` conclusion `success` with headSha == HEAD.

## Constitution deviations

None.

- Article 5 (Additive first): the env vars `AAI_REAP_STEP_START_EPOCH` /
  `AAI_REAP_GRACE_SECS` are additive; unset → today's behavior byte-for-byte. Satisfied.
- Article 2 (Simplicity): reuses `etime_to_secs` + `date +%s`; no new parsing machinery,
  no `lstart`. Satisfied.
- Article 3 (Portability): `ps etime` + `date +%s` only, POSIX sh, BSD+GNU. Satisfied.
- Article 4 (Degrade and report): invalid/absent epoch degrades to legacy mode and still
  prints `reaped: N`. Satisfied.

## Acceptance Criteria Status

| Spec-AC    | Description                                                      | Status  | Evidence | Review-By | Notes |
|------------|------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Epoch-relative spare/reap decision (both directions)             | done | docs/ai/tdd/red-20260720T114129Z-test016.log (RED) + docs/ai/tdd/red-20260720T114129Z-test017.log (RED) + docs/ai/tdd/green-20260720T120138Z-reaper-deterministic-age-guard.log (GREEN, full suite incl. TEST-016/017) | —         | —     |
| Spec-AC-02 | Overhead-independence + RED-proof of the old fixed-threshold flip | done | docs/ai/tdd/red-20260720T114129Z-test016.log (pre-change reaper flips spare->reap at injected delay 7s, matching MIN_AGE+GRACE) + docs/ai/tdd/green-20260720T120138Z-reaper-deterministic-age-guard.log (TEST-016 spares at delay 0 AND 7) | —         | —     |
| Spec-AC-03 | Fail-safe fallback to MIN_AGE (unset/invalid/future), never global | done | docs/ai/tdd/green-20260720T120138Z-reaper-deterministic-age-guard.log (TEST-018: 6 invalid-shape cases all preserve exact legacy MIN_AGE behavior) | —         | —     |
| Spec-AC-04 | Portability: etime + date +%s only; clean under dash; no lstart  | done | docs/ai/tdd/red-20260720T114129Z-test019.log (RED) + docs/ai/tdd/green-20260720T120138Z-reaper-deterministic-age-guard.log (TEST-013 dash epoch path + TEST-019 static guard, GREEN) + `dash -n .aai/scripts/aai-reap-tests.sh` exit 0 | —         | —     |
| Spec-AC-05 | PowerShell parity: Get-ReapCandidates honors -StepStart          | done | `pwsh -Command "Invoke-Pester -Path tests/skills/aai-win-dispatch.Tests.ps1"` — 38/38 passed incl. new StepStart context; ps1-quality gate (PSScriptAnalyzer) clean | —         | —     |
| Spec-AC-06 | Producer wiring documented in SKILL_LOOP + VALIDATION            | done | docs/ai/tdd/red-20260720T114129Z-test020.log (RED) + docs/ai/tdd/green-20260720T120138Z-reaper-deterministic-age-guard.log (TEST-020, GREEN); .aai/SKILL_LOOP.prompt.md + .aai/VALIDATION.prompt.md updated | —         | —     |
| Spec-AC-07 | skill-suite CI green on Ubuntu across a repeated run              | done | CI run 29742208991 (headSha fdff86b == HEAD, 40/40 success) + run 29741627562 (d45fe4e, 40/40 success) — TWO consecutive green skill-suite runs on Ubuntu (independently confirmed by Validation) | — | anti-flake signal: reaper fix green on the authoritative Linux env across repeated runs; no re-run needed |

## Implementation plan

Components / modules affected:
- `.aai/scripts/aai-reap-tests.sh` — Guard 3: capture `SNAP_NOW=$(date +%s)` adjacent to
  the `ps axo pid=,etime=,args=` snapshot; parse `AAI_REAP_STEP_START_EPOCH` (valid iff
  digits, `>0`, `<= SNAP_NOW`) and `AAI_REAP_GRACE_SECS` (default 2, coerce invalid→2);
  in epoch mode `start_epoch=$((SNAP_NOW-age)); [ "$start_epoch" -lt $((STEP_START-GRACE)) ]`
  decides reap, else spare; else legacy `age >= MIN_AGE`. Update the header env docs.
- `.aai/scripts/aai-reap-tests.ps1` — add optional `-StepStart [datetime]` to
  `Get-ReapCandidates` + plumb `AAI_REAP_STEP_START_EPOCH` through `Invoke-ReapDispatch` /
  `Get-EffectiveMinAge`-adjacent parsing and the WSL delegation args (mirror
  `AAI_REAP_MIN_AGE_SECS` forwarding).
- `tests/skills/test-aai-run-tests.sh` — MIGRATE the fresh-sibling paths of `test_006`
  and `test_015` from the `MIN_AGE=5` margin-hope to the deterministic epoch contract;
  ADD `test_016`..`test_020`; append them to `ALL_TESTS`.
- `tests/skills/aai-win-dispatch.Tests.ps1` — add a StepStart context to the
  `aai-reap-tests.ps1` Describe block.
- `.aai/SKILL_LOOP.prompt.md`, `.aai/VALIDATION.prompt.md` — document the step-start-epoch
  capture + handoff at the reap boundary.
- `docs/TECHNOLOGY.md` — note the deterministic epoch guard in the reaper row (kept in
  sync with the reaper headers, per the existing "kept identical across" contract).

Data flows: step owner `date +%s` → `AAI_REAP_STEP_START_EPOCH` env → reaper Guard 3
(`SNAP_NOW - etime` vs `STEP_START - GRACE`).

Edge cases: `STEP_START` in the future (clock skew) → invalid → legacy; process
`start_epoch` exactly at `STEP_START - GRACE` boundary → spared (`<` not `<=` for reap);
`etime` empty/malformed → `etime_to_secs` yields 0 → `start_epoch = SNAP_NOW` (newest
possible) → spared (safe); `GRACE=0` override → exact-boundary determinism for tests.

## Seam analysis

- SEAM 1 — reaper ↔ step owner (the epoch handoff): the reaper CONSUMES an env var the
  loop/validation PRODUCES. Covered end-to-end: `test_016`/`test_017` set
  `AAI_REAP_STEP_START_EPOCH` exactly as a producer would and assert the reaper's real
  spare/reap outcome (produce on one side, assert the kill decision on the other — not two
  mocked halves). `test_020` asserts the producer side documents the capture.
- SEAM 2 — reaper ↔ CI (the authoritative environment): the flake only reproduces under
  Linux CI load. Covered by Spec-AC-07 (`skill-suite` repeated-run green) PLUS the local
  delay-injection determinism test (`test_016`) that proves overhead-independence WITHOUT
  needing real CI load — so the loop's local Validation can attest determinism and CI
  attests green-on-Linux.
- SEAM 3 — reaper `.sh` ↔ reaper `.ps1` (cross-platform contract): the same
  `AAI_REAP_STEP_START_EPOCH` name/semantics on both. Covered by Spec-AC-05's Pester
  StepStart context. Residual risk: native Windows kill is manual-verified (SPEC-0046 MV),
  not CI — recorded, unchanged from the existing `.ps1` posture.

Residual risk: EPOCH mode's production semantics assume same-workspace concurrent runs
start close to the step boundary; cross-worktree siblings are already isolated by Guard 2
(workspace), so this guard is defence-in-depth, and `GRACE` plus the workspace scope keep
it safe. Not automatable beyond the unit scenarios above.

## Test Plan

| Test ID  | Spec-AC          | Type | File path (expected)                     | Description                                                                                          | Status  |
|----------|------------------|------|------------------------------------------|------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01, Spec-AC-02 | int  | tests/skills/test-aai-run-tests.sh (test_016) | Fresh sibling SPARED by epoch mode; reaper run at injected delay 0 AND delay ≥ MIN_AGE+GRACE both spare (overhead-independent); RED-proof against pre-change reaper. Cmd: `bash tests/skills/test-aai-run-tests.sh 016` | green |
| TEST-002 | Spec-AC-01       | int  | tests/skills/test-aai-run-tests.sh (test_017) | Genuine pre-step survivor REAPED in epoch mode even at a high MIN_AGE the fixed threshold would spare. Cmd: `bash tests/skills/test-aai-run-tests.sh 017` | green |
| TEST-003 | Spec-AC-03       | int  | tests/skills/test-aai-run-tests.sh (test_018) | Unset / non-integer / negative / future STEP_START → legacy MIN_AGE behavior (reap aged, spare young), never global. Cmd: `bash tests/skills/test-aai-run-tests.sh 018` | green |
| TEST-004 | Spec-AC-04       | int  | tests/skills/test-aai-run-tests.sh (test_019) | Epoch mode runs clean under dash (no bashisms) + static guard: no `lstart`, no `date -d`/`date -j` string parsing. Cmd: `bash tests/skills/test-aai-run-tests.sh 013 019` | green |
| TEST-005 | Spec-AC-05       | unit | tests/skills/aai-win-dispatch.Tests.ps1  | `Get-ReapCandidates -StepStart` spares CreationDate ≥ StepStart−GRACE, reaps older; absent StepStart unchanged. Cmd: `pwsh -Command "Invoke-Pester -Path tests/skills/aai-win-dispatch.Tests.ps1"` | green |
| TEST-006 | Spec-AC-06       | int  | tests/skills/test-aai-run-tests.sh (test_020) | SKILL_LOOP + VALIDATION document capturing `AAI_REAP_STEP_START_EPOCH=$(date +%s)` at the reap boundary. Cmd: `bash tests/skills/test-aai-run-tests.sh 020` | green |
| TEST-007 | Spec-AC-01, Spec-AC-02, Spec-AC-04 | int  | tests/skills/test-aai-run-tests.sh (test_006,015) | The originally-flaky tests, MIGRATED to the epoch contract, pass DETERMINISTICALLY (no margin-hope). Cmd: `bash tests/skills/test-aai-run-tests.sh 006 015` | green |
| TEST-008 | Spec-AC-07       | e2e  | .github/workflows/skill-suite.yml (CI)   | `skill-suite` job green on Ubuntu across a REPEATED run; headSha == HEAD. Cmd: `gh run list --workflow skill-suite.yml --branch <branch>` + `gh run view <id>` | green |

Notes:
- Every Spec-AC has ≥1 TEST-xxx. Test IDs are stable post-freeze.
- RED-proof obligation (all AC-gating tests): TEST-001 flips the pre-change fixed-threshold
  reaper to a wrongful reap under injected delay (deterministic reproduction of the flake,
  captured as RED) then passes against the fixed reaper. TEST-002 spares the survivor under
  the old reaper (high MIN_AGE) = RED, reaps under epoch mode = GREEN. TEST-003/004/005/006
  fail against the pre-change scripts (no epoch support / no wiring) and pass after.

## Verification
- Commands: the eight rows above (TEST-001..008), run against the fixed scripts.
- Evidence artifacts: RED/GREEN logs under docs/ai/tdd/ for TEST-001..005; the CI run
  URL + conclusion for TEST-008; grep output for TEST-006.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status AND the
  skill-suite CI job green on Ubuntu across a repeated run.

## Evidence contract
For each implementation / validation / TDD / code-review artifact record:
- ref_id: reaper-deterministic-age-guard
- Spec-AC and TEST-xxx links
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/*.log, docs/ai/reviews/*.md, CI run URL)
- commit SHA or diff range when available
