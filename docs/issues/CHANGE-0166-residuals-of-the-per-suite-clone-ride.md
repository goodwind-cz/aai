---
id: residuals-of-the-per-suite-clone-ride
type: change
number: 166
status: done
ceremony_level: 2
links:
  pr:
    - 307
  commits:
    - 12112e4f
---

# What the per-suite-clone ride leaves behind: a 32-minute sequential sweep it no longer has to be

## Closeout (spec-test-framework-sweep, 2026-09-13)

This intake sat `status: draft` with no PR link for two weeks after its work actually
shipped. **The work is not a build; it was a verification, a measurement and a close** —
established directly against the tree, not asserted.

- **What PR #307** ("perf(harness): run the sweep concurrently at a bounded width
  (CHANGE-0166) [L2] (#307)", commit `12112e4f`) **already shipped**, closing AC-001
  through AC-004 below: `tests/skills/test-framework.sh` gained a bounded-width wave
  scheduler (`PARALLEL_WIDTH`, `parallel_probe`, `run_wave`), default
  `min(8, cpus - 2)`, an `AAI_TEST_PARALLEL` override with `1` as a first-class serial
  value, isolation-off forcing serial execution, a tripwire window scoped to the WAVE
  (a dirty wave is discarded and re-run one suite at a time, widening
  `TRIPWIRE_WATCH_PATHS` with the wave's changed paths), `docs/ai/tests/test-runs.jsonl`
  appends serialised through `.aai/scripts/lib/append-lock.sh` (a `mkdir` mutex), and
  `RUN_ID` collisions resolved through an atomic `mkdir` without `-p`. The registry
  entries `fu-sweep-is-strictly-sequential`, `fu-dispatch-demands-full-sweep` and
  `fu-framework-rundir-same-second` were all already `done`, resolved by PR #307,
  before this closeout ride started.
- **What this ride added:** the fixed-wave BARRIER cost (`run_wave` waits for every wave
  member before the next wave starts) was replaced by a refilling work-queue scheduler
  (`run_queue`) — a freed slot takes the next suite immediately — and the wave-scoped
  tripwire attribution window became a rolling window over the whole concurrent phase, a
  dirty phase re-running EVERY suite serially with the same widened watch set (Spec-AC-06
  / Spec-AC-07 of `spec-test-framework-sweep`, with TEST-411 through TEST-414 as the
  mutation-tested evidence). `.aai/VALIDATION.prompt.md` already named the SELECTED-plus-
  CORE selector (AC-004, landed with #307); this ride wired `.aai/SKILL_TDD.prompt.md`'s
  own Phase-4 step 0 to the same selector, which it had not been (Spec-AC-16).
- **Measured wall-clock, before and after** (both at width 8, 93 suites, `/usr/bin/time
  -p`; full detail in `docs/ai/tdd/spec-test-framework-sweep/sweep-before.txt` and
  `sweep-after.txt`):
  - Canonical BEFORE (pre-this-ride scheduler, run `test-20260913-040817`, the live
    worktree): **1632 s (27.2 min)**.
  - AFTER (this ride's refilling-queue scheduler, run `test-20260913-094504`, the live
    worktree): **835.29 s (13.9 min)** — 51.2% of the canonical baseline, comfortably
    inside the Spec-AC-06 gate of `<= 65%` (threshold 1060.8 s).
  - A same-day scratch reproduction of the PRE-this-ride scheduler (`sweep-before.txt`,
    run `test-20260913-094459`, a throwaway one-commit clone) measured 1053.53 s; the
    canonical 1632 s figure — not this reproduction — is what Spec-AC-06 is written
    against, and is the number carried here.
- **The Motivation section's "1914 s" and "32 minutes" figures below are the pre-#307
  baseline**, measured before ANY parallel scheduler existed (run `test-20260827-154347`,
  fully sequential). They are left as originally written, as the historical record of why
  this intake was filed; the canonical before/after pair for what actually shipped is the
  1632 s / 835.29 s pair above.

## Summary
- The ride `isolation-shares-the-shipping-git` (branch `fix/suite-isolation-owns-its-git`)
  gives every suite its own `git clone --local --no-hardlinks`. Its own follow-ups are the
  subject here, scoped to what remains AFTER it merges. The largest is an opportunity its
  mechanism creates rather than a defect it leaves: sequential execution was forced by
  suites sharing one `.git`, and that constraint is gone.

## Motivation / Business Value
- A full framework sweep costs 1914 s (32 minutes), measured on run
  `test-20260827-154347`. The isolation ride paid it four times — roughly an hour of
  wall-clock for rounds whose findings were all reachable from targeted suites.
- Verified today in a disposable clone of `origin/main` (`c6b32d0`):
  `/usr/bin/grep -cE 'xargs -P|[^&]& *$|^ *wait$|parallel' tests/skills/test-framework.sh`
  returns (the `-E` matters: with plain `-c` the `|` are literals, so the command would
  return zero even on a file full of parallel constructs — a vacuous probe, corrected
  after bot review on PR #297, then widened again on #298 because ` & *$` missed the
  spaceless `cmd&` form; re-measured pattern by pattern after each change, all zero)
  0. The file contains no parallel constructs at all.
- Also measured on that run: median suite 6 s, 47 of 81 suites under 10 s, top 12 suites
  1172 s = 61 percent of the total (`aai-delta-stage3` 227 s, `aai-docs-audit` 140 s,
  `aai-run-tests` 129 s, `aai-doctor` 102 s). Four-way execution puts the critical path
  near the longest suite: order of 10 to 12 minutes instead of 32.

## Scope
- In scope: parallel execution of the sweep, now that the shared-`.git` constraint is
  removed; and the dispatch policy that demands a full sweep where none is required.
- Out of scope: the per-suite clone mechanism, the `git-common-dir` gate, and the two
  registry items that ride closes fully — all land with it.
- Out of scope: the probe items below, which are covered in full by the agent-shell
  boundary intake and are named here only because they belong to this registry group.

## Affected Area
- `tests/skills/test-framework.sh` (execution model, tripwire snapshot window,
  `docs/ai/tests/test-runs.jsonl` appends).
- The orchestrator's own validation and remediation dispatch habits.

## Desired Behavior (To-Be)
- The sweep runs suites concurrently at a bounded width, with the tripwire snapshot window
  and the run-record appends made safe under concurrency.
- Intermediate validation and remediation rounds run the SELECTED plus CORE suites; ONE
  full sweep runs before the close ceremony as the evidence the TEST rows cite.

## Acceptance Criteria
- AC-001: SATISFIED. A full sweep now completes in materially less wall-clock time than
  the sequential baseline, with the same pass/fail set — 835.29 s vs. the 1632 s canonical
  baseline (51.2%), TEST-412 (spec-test-framework-sweep) proving verdict-set identity at
  width 1 vs. width N on a fixture carrying one of each outcome.
- AC-002: SATISFIED. Concurrent tripwire snapshots do not interfere: the wave/window
  attribution mechanism (PR #307, refined by spec-test-framework-sweep TEST-413/TEST-414)
  names the actual writer and blames no sibling; `waves_reattributed: 0` on every
  full-sweep record inspected (this corpus never writes the shipping repository today).
- AC-003: SATISFIED. `docs/ai/tests/test-runs.jsonl` appends are serialised through
  `.aai/scripts/lib/append-lock.sh` (PR #307); the append-only byte-prefix property is
  covered by TEST-005/TEST-006 of `tests/skills/test-aai-sweep-parallel.sh`.
- AC-004: SATISFIED. `.aai/VALIDATION.prompt.md` already named the SELECTED-plus-CORE
  selector (PR #307); `spec-test-framework-sweep` Spec-AC-16 closed the other half —
  `.aai/SKILL_TDD.prompt.md`'s own Phase-4 step 0 now names it too (TEST-429).

## Verification
- Time a full sweep before and after; compare the per-suite verdict set byte for byte.
- Run two suites that both write watched paths concurrently and confirm each is attributed
  to the right suite.
- `node .aai/scripts/select-suites.mjs --files-from <changed files>` output is what an
  intermediate round runs.

## Constraints / Risks
- Parallelism is NOT free, and the ride that filed this said so: the tripwire snapshots the
  shipping tree around each suite and concurrent snapshots would interfere — observed once
  as a HEAD-moved detection — and the `test-runs.jsonl` appends would need serialising.
- `fu-framework-rundir-same-second` (filed with another cluster) becomes sharper under
  concurrency: a second-resolution `RUN_ID` shared by two processes is a collision the
  parallel work must not inherit.
- Measured today: `/usr/bin/grep -c 'test-framework.sh|full sweep' .aai/VALIDATION.prompt.md`
  returns 0 — canon never required the sweep. The corrective for
  `fu-dispatch-demands-full-sweep` is an orchestration habit, not a code change, so it
  cannot be verified by a test alone.

## Notes
- Registry ids covered, read from `docs/ai/decisions.jsonl` on branch
  `fix/suite-isolation-owns-its-git` (they are not yet on `origin/main`):
  `fu-sweep-is-strictly-sequential` (P2), `fu-dispatch-demands-full-sweep` (P2),
  `fu-userguide-catalog-drifts-both-ways` (P2),
  `fu-probe-redirect-lands-in-shipping-cwd` (P2),
  `fu-orchestrator-probe-touched-git` (P3).
- `fu-test210-branch-now-dead-code` is named by the dispatch as a member of this group,
  filed hours before this intake. It is NOT present in `docs/ai/decisions.jsonl` on any ref
  in this clone (checked across `refs/heads` and `origin/main` and
  `fix/suite-isolation-owns-its-git`), so nothing is claimed about its content here.
  Planning should read it directly.
- `fu-userguide-catalog-drifts-both-ways` measured today looks ADDRESSED on `origin/main`
  by commits `2420497` ("give the six undocumented skills a catalog entry, and guard the
  set") and `c6b32d0` ("complete the Quick Reference and guard it too"): all six previously
  missing skills (`aai-ship`, `aai-overview`, `aai-issues`, `aai-routine`,
  `aai-feedback-triage`, `aai-feedback-upsert`) now appear in `docs/USER_GUIDE.md` and all
  six exist under `.claude/skills`. The remaining hits for the seven non-skills are prose
  and example URLs, not catalog rows. Verify before planning work on it.
- The probe items are the AGENT-shell class. The spec's own "NOT CLOSED" section says this
  ride "makes the SUITE path structurally safe and leaves the AGENT path exactly where it
  was". They are scoped in the agent-shell boundary intake, not here.
