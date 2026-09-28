---
id: spec-feedback-triage-missing-output-dir
type: spec
number: 190
status: done
frozen_sha256: f9f2ba78a6eb9ae29d4b2a8090d184ecca3bf4ff8f3a58a51675e856f968e23b
ceremony_level: 1
links:
  requirement: docs/issues/ISSUE-0084-feedback-triage-missing-output-dir.md
  rfc: null
  pr:
    - 403
  commits:
    - a79d17cab83def734e4b619be519084083a04cbe
---

# Spec — feedback triage creates the report parent directory before writing

SPEC-FROZEN: true

Ceremony justification: one production surface (`.aai/scripts/aai-feedback-triage.mjs` write path) plus one targeted arm in the existing triage suite. No protected path from `protected_paths_l3`. No new `.aai/**` file. No prompt-corpus byte growth. Direct strategy: implement first, then the regression test; no stored RED artifacts.

## Links
- Requirement: docs/issues/ISSUE-0084-feedback-triage-missing-output-dir.md
- Related done work, not this defect: CHANGE-0048 (`feedback-triage-offline`) — missing/invalid `feedback.yaml` degrades to local; it never required creating `--out`'s parent.
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: direct
- Rationale: owner invoked `/aai-ship` with direct + tests for this single-surface mkdir. The defect is already reproduced (ENOENT on a missing parent). What is missing is the create-parent write and one regression arm; no RED-first ceremony.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: one script plus one test arm on a dedicated branch; no parallel scope competes for these files.
- User decision: inline
- Base ref: main
- Worktree branch/path: cursor/feedback-triage-missing-output-dir-a7ce (inline)
- Inline review scope: `.aai/scripts/aai-feedback-triage.mjs`, `tests/skills/test-aai-feedback-triage.sh`, `docs/issues/ISSUE-0084-feedback-triage-missing-output-dir.md`, `docs/specs/SPEC-0190-spec-feedback-triage-missing-output-dir.md`, `docs/INDEX.md`, `docs/ai/EVENTS.jsonl`

## Acceptance Criteria Mapping
- Maps to: docs/issues/ISSUE-0084-feedback-triage-missing-output-dir.md Expected Behavior

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the parent directory of `--out` does not exist THEN the engine SHALL create it recursively, write the local triage report, and exit 0 | done | docs/ai/tdd/feedback-triage-missing-output-dir/green-TEST-652.log | — | the ENOENT defect |
| Spec-AC-02 | WHEN the spool file is also absent THEN the same run SHALL still exit 0 with a report whose `total_observations` is 0 | done | docs/ai/tdd/feedback-triage-missing-output-dir/green-TEST-652.log | — | empty-project first run |
| Spec-AC-03 | WHEN `tests/skills/test-aai-feedback-triage.sh` runs in full THEN it SHALL exit 0 | done | docs/ai/tdd/feedback-triage-missing-output-dir/green-TEST-653.log | — | no regression of CHANGE-0048 |

## Implementation plan
- `.aai/scripts/aai-feedback-triage.mjs`: import `mkdirSync`, call `mkdirSync(dirname(args.out), { recursive: true })` immediately before `writeFileSync`.
- `tests/skills/test-aai-feedback-triage.sh`: add TEST-652 pointing `--out` at a path whose parent does not exist and asserting exit 0 plus a written zero-observation report. Register in `main()`.
- Do not create a tracked `docs/ai/friction/` tree. Runtime mkdir of `--out`'s parent only.

## Test Plan

| Test ID  | Spec-AC | Type | File path (expected) | Description | Status |
|----------|---------|------|----------------------|-------------|--------|
| TEST-652 | Spec-AC-01, Spec-AC-02 | integration | tests/skills/test-aai-feedback-triage.sh | missing `--out` parent and missing spool: exit 0, report file exists, `total_observations` is 0 | green |
| TEST-653 | Spec-AC-03 | integration | tests/skills/test-aai-feedback-triage.sh | full existing suite still exits 0 | green |

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-feedback-triage.sh test_652_missing_outdir` — exit 0
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-feedback-triage.sh` — exit 0
- PASS criteria: TEST-652 and TEST-653 green (exit 0) plus the scoped diff. Direct strategy: no stored RED artifact.

## Evidence contract
- ref_id: feedback-triage-missing-output-dir
- Strategy: direct — targeted regression tests green (exit codes) plus the scoped diff. No stored RED artifact. No matrix beyond the declared suite.

### Evidence by strategy

| Strategy | Evidence this spec may demand |
|----------|-------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop | per-TEST-xxx green runs; RED-proof observed, storage optional |
| direct | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |

## Registry items closed by this scope
none

## Out of scope
- Creating a tracked `docs/ai/friction/` directory in the shipping repo
- Changing spool-read degrade behavior
- Network / upsert paths
