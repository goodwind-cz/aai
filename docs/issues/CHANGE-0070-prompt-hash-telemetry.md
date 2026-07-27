---
id: prompt-hash-telemetry
number: 70
type: change
status: done
user_visible: true
links:
  pr:
    - 170
  commits:
    - 1c2f602f7533fe80ccffd221778ae213a53e9970
---

# Change — Prompt-hash telemetry: content-addressed identity of effective role instructions

## Summary
- Adopt Promptbook's computeAgentHash idea (analysis extension 2026-07-27,
  candidate 3): compute a deterministic sha256 of the EFFECTIVE prompt a
  dispatched role ran under (role prompt file + SUBAGENT_CONTRACT.md +
  docs/knowledge/LEARNED.md snapshot), record it per run via a new
  append-run --prompt-hash flag, carry it through metrics-flush into
  METRICS.jsonl, and let metrics-report group runs by hash — so "did this
  role's instructions change between run A and run B" becomes a mechanical
  query and metric regressions correlate with prompt edits.

## Motivation / Business Value
- Telemetry knows model + duration + tokens but not WHICH VERSION of the
  instructions produced a run; prompt edits are the single most common
  change class in this factory (14 PRs touched prompts in 2 days) and are
  currently invisible in run history.

## Scope
- In scope:
  - New .aai/scripts/lib/prompt-hash.mjs: computeEffectivePromptHash(
    rolePromptPath) -> sha256 hex over role prompt bytes + CONTRACT bytes
    + LEARNED bytes (concatenated with filename separators; missing file
    => literal ABSENT marker, never throws); short 12-hex display form.
  - state.mjs append-run: new OPTIONAL --prompt-hash flag (validated
    12-64 hex chars), stored on the run entry as prompt_hash; absent flag
    => field omitted (never fabricated). PROTECTED SURFACE (L3).
  - metrics-flush: pass prompt_hash through to the ledger entry unchanged.
  - metrics-report: per-item runs show the short hash; a "Prompt versions"
    note groups run counts by hash per role when >1 hash exists.
  - orchestration-dispatch --human output prints the effective hash for
    the dispatched role (advisory; uses the lib).
  - Tests: hash determinism + ABSENT marker; append-run flag validation
    (bad hex rejected, absent omitted); flush passthrough; report
    grouping fixture.
- Out of scope: hashing per-scope briefs/inputs (only the durable
  instruction layer); enforcing hash match anywhere (observability only);
  historical backfill.

## Affected Area
- New .aai/scripts/lib/prompt-hash.mjs, .aai/scripts/state.mjs (append-run
  — PROTECTED L3), .aai/scripts/metrics-flush.mjs,
  .aai/scripts/metrics-report.mjs, .aai/scripts/orchestration-dispatch.mjs
  (--human line), tests/skills (state/metrics/dispatch suites + new
  stanzas), PROFILES.

## Desired Behavior (To-Be)
- Every orchestrated run can carry prompt_hash; ledger preserves it;
  report shows instruction-version groups; dispatch prints the hash it
  expects the role to run under.

## Acceptance Criteria
- AC-001: hash is deterministic (double-run identical), changes when any
  of the three inputs changes, and uses the ABSENT marker for a missing
  LEARNED (fixture-verified).
- AC-002: append-run stores a valid --prompt-hash, rejects non-hex with a
  usage error and no write, and omits the field entirely when absent
  (suite-verified; existing append-run goldens unchanged).
- AC-003: flush passes prompt_hash through byte-unchanged; runs without
  it produce ledger entries without the field (suite-verified).
- AC-004: report groups by hash only when >1 hash exists per role;
  otherwise no new section (fixture-verified).
- AC-005: dispatch --human prints the advisory hash line; JSON contract
  additive-only (existing TEST-002 key-set assert extended, not broken).
- AC-006: no regression — state + metrics + dispatch suites green
  locally; full run on PR CI.

## Verification
- bash tests/skills/test-aai-state.sh; bash tests/skills/test-aai-metrics.sh;
  bash tests/skills/test-aai-orchestration-dispatch.sh (+ new stanzas)
- PR CI full framework.

## Constraints / Risks
- CEREMONY LEVEL 3: state.mjs is on protected_paths_l3. Consequences:
  worktree rule-8 recorded decision (operator blanket run-level
  authorization 2026-07-27 recorded with rationale), code review MANDATORY
  most-capable tier, operator final-diff sign-off before merge.
- append-run change must be additive-only: existing flag behavior,
  warnings, and output lines byte-identical when --prompt-hash absent.
- Hash covers the durable instruction layer only — honest limitation
  documented (dispatch-time extra context not included).

## Notes
- Source: Promptbook analysis extension, adoption candidate 3
  (computeAgentHash content-addressing). Autopilot intake: metrics
  question skipped, human_time_minutes null.
