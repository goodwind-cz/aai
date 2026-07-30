---
id: deterministic-friction-capture
number: 99
type: change
status: done
user_visible: false
links:
  pr:
    - 202
  commits:
    - e3ae4ac981b0d78a96dc11100f03ea00c8b0c658
---

# Change — deterministic friction capture points

## Summary
- RFC-0012 Phase 2 is stalled on ZERO data: `docs/ai/friction/observations.jsonl`
  never gets written despite days of intense factory use that contained textbook
  AAI-owned frictions (a Windows 5.1 install crash, a flaky concurrency test, a
  release-cut MALFORMED refusal, hygiene-pack false-fails on worktree copies,
  clock-skew append-run rejections).
- Root cause: the friction capture path is best-effort PROSE in role prompts (the
  ROLE_COMMON FRICTION HOOK and FRICTION_PROTOCOL.md "Skill wiring (shadow
  capture)"). It is recall-dependent and demonstrably never fires during real
  work, so the spool stays empty and triage has nothing to cluster.
- Fix (same philosophy as deterministic dispatch — prompt prose does not fire,
  scripts always do): wire DETERMINISTIC capture points into the two scripts
  where friction provably flows. No LLM judgment at write time (raw observation
  only, `confidence: low`); triage stays review-mode.

## Motivation / Business Value
- Unblocks RFC-0012 Phase 2: the review-mode triage/upsert machinery already
  exists but is starved of input. Deterministic capture gives it a real spool.
- Zero recall dependency: the write happens in the script, so an agent never has
  to remember the protocol to trigger it.

## Scope
- In scope:
  - CAPTURE POINT 1 — `.aai/scripts/aai-run-tests.sh`: on a non-zero exit (incl.
    124 timeout) append one raw schema-v2 observation via the existing
    `aai-friction.mjs record` CLI, best-effort, never changing the wrapper exit
    code.
  - CAPTURE POINT 2 — `.aai/scripts/close-work-item.mjs`: at close time, when the
    closing ride carried remediation runs (`role: Remediation` agent_runs in
    `docs/ai/STATE.yaml`), append one raw observation summarizing the recovery
    work, best-effort, never changing the close exit code.
  - The new pin suite `tests/skills/test-aai-friction-capture-points.sh` plus its
    `suite-map.yaml` row.
  - RFC-0012 phase-table row 2 updated to note the delivered capture points.
- Out of scope:
  - Any schema change (reuse the frozen v2 `record` contract exactly).
  - CAPTURE POINT 3 (CI-failure breadcrumb) — skipped: it needs CI context not
    available at the local capture site.
  - Removing or weakening the existing prose FRICTION HOOKs (they stay; this ride
    only ADDS deterministic points).
  - Phase 2's remaining work (auto-gate D8, fix-PR scaffolding).

## Affected Area
- `.aai/scripts/aai-run-tests.sh` (test wrapper), `.aai/scripts/close-work-item.mjs`
  (close ceremony), `tests/skills/` (new pin suite + suite-map row),
  `docs/rfc/RFC-0012-*.md` (phase-table row 2).

## Desired Behavior (To-Be)
- A failing test/build command through the wrapper leaves exactly one raw
  observation in the spool (`skill_id: aai-run-tests`); a timeout records
  `failure_class: stalled_progress`, any other non-zero records
  `deterministic_script_failure`. A succeeding command records nothing.
- A close whose ride carried >=1 remediation run leaves exactly one raw
  observation (`skill_id: close-work-item`, `failure_class:
  abstraction_leak_recovery`); a zero-remediation close records nothing.
- Neither capture ever changes its host script's exit code, even when the capture
  itself fails; neither fires from a fixture repo lacking `docs/ai/friction`.

## Acceptance Criteria
- AC-001: a failing command (exit N != 0, non-timeout) through
  `aai-run-tests.sh` appends exactly one observation with `skill_id:
  aai-run-tests` and `failure_class: deterministic_script_failure`; the wrapper
  still exits N.
- AC-002: a timed-out command through the wrapper exits 124 and appends exactly
  one observation with `failure_class: stalled_progress`.
- AC-003: a succeeding command through the wrapper exits 0 and appends nothing
  (success is not friction).
- AC-004: capture is isolated deterministically — it fires only when
  `AAI_FRICTION_CAPTURE` is not `0` AND the resolved spool DIR already exists; a
  missing spool dir and the off-switch each suppress capture with the exit code
  preserved, and a fixture repo lacking `docs/ai/friction` never creates or
  writes a spool (proven for both the wrapper and the close ceremony).
- AC-005: a capture that FAILS at the wrapper (unwritable spool) is swallowed and
  the wrapper exits the command's real exit code unchanged.
- AC-006: a close whose STATE carries `role: Remediation` agent_runs for the ref
  appends exactly one observation with `skill_id: close-work-item`; the close
  exits 0.
- AC-007: a close with zero remediation runs appends nothing; the close exits 0.
- AC-008: a capture that FAILS at close time is swallowed and the close exit code
  is unchanged.
- AC-009: the existing prose FRICTION HOOK pins and the wrapper/close regression
  suites stay green (this ride only ADDS deterministic points).

## Verification
- `bash tests/skills/test-aai-friction-capture-points.sh` -> exit 0 (TEST-001..009).
- `bash tests/skills/test-aai-friction.sh` and
  `bash tests/skills/test-aai-friction-wiring.sh` -> exit 0 (prompt pins intact).
- `bash tests/skills/test-aai-run-tests.sh` and
  `bash tests/skills/test-aai-close-work-item.sh` -> exit 0 (host-script regression).
- `bash tests/skills/test-aai-layer-profiles.sh`,
  `bash tests/skills/test-aai-hygiene-pack.sh`,
  `bash tests/skills/test-aai-suite-select.sh` -> exit 0 (suite-map row honored).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0.
- Dogfood: a deliberately failing command through the real wrapper appends a real
  observation to `docs/ai/friction/observations.jsonl` (gitignored).

## Constraints / Risks
- Ceremony L2. Internal telemetry only (`user_visible: false`); no user-facing
  surface changes.
- The taxonomy is a closed seven-value enum, so the raw capture maps a wrapper
  exit deterministically (`stalled_progress` for a timeout, else
  `deterministic_script_failure`) and a remediation-carrying close to
  `abstraction_leak_recovery`. This is coarse by design — deterministic capture
  makes NO ownership judgment; `confidence: low` and the review-mode triage
  threshold keep one-off/expected failures (e.g. TDD REDs) from surfacing as
  review candidates.
- No schema change: the frozen v2 `record` contract is reused verbatim, so
  identity fields remain excluded by construction and no new key can leak.
- Script-only ride: no `.aai/*.prompt.md` bytes added (no prompt-diet ledger
  entry) and no new `.aai/**` file added (no PROFILES entry). The only companion
  obligation is the `suite-map.yaml` row for the new test file (hygiene-pack pin).

## Notes
- Change-only ride (no numbered SPEC), mirroring CHANGE-0090/0092: the scope is
  two script edits plus a pin suite, fully covered by the AC table above and the
  new deterministic test file — a separate frozen spec would add ceremony without
  adding measurable AC coverage.
