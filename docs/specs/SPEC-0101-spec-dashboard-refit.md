---
id: spec-dashboard-refit
type: spec
number: 101
status: done
ceremony_level: 2
links:
  requirement: CHANGE-0076
  rfc: null
  pr:
    - 179
  commits:
    - b695885524506ef91065b5cd2085ea27924b434b
---

## Links
- Requirement: docs/issues/CHANGE-0076-dashboard-refit.md
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md

## Summary
SKILL_DASHBOARD.prompt.md was 19173 B / 652 lines, of which ~330 lines were a
stale duplicate implementation dump of `.aai/scripts/generate-dashboard.mjs`
(which exists, works, and had diverged from the prose copy), the documented
METRICS.jsonl schema was the old flat-entries-only shape (not the real
work-item ledger with nested `agent_runs`), and a documented `--publish` flag
was never implemented. SKILL_TEST_SKILLS.prompt.md was 9218 B carrying a
stale hardcoded 11-skill Example Output block and a pytest/cargo CI snippet
this project does not use. Both are rewritten to thin script-first wrappers
mirroring SKILL_DOCTOR.prompt.md's proven shape; `--publish` is removed
entirely (publishing is `/aai-share`'s job, not a new intake).

## Implementation strategy
- Strategy: tdd
- Rationale: the deliverable is a prompt-corpus byte-budget change gated by a
  real, already-existing test suite (`tests/skills/test-aai-prompt-diet.sh`
  TEST-010/012) plus a new content-pin test (TEST-017). RED-GREEN evidence
  proves the pin actually bites against the old stale content before the
  rewrite, and passes after — a loop strategy would not produce that proof.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: small, clearly scoped doc/test edit; already on a
  dedicated feature branch (feat/dashboard-refit); no protected L3 surface
  (state engine, allocator, guards, workflow canon) is touched.
- User decision: waived
- Base ref: main
- Worktree branch/path: feat/dashboard-refit (current checkout)
- Inline review scope: .aai/SKILL_DASHBOARD.prompt.md,
  .aai/SKILL_TEST_SKILLS.prompt.md, tests/skills/lib/prompt-diet-ledger.sh,
  tests/skills/test-aai-prompt-diet.sh,
  docs/specs/SPEC-0101-spec-dashboard-refit.md

## Acceptance Criteria Mapping
- Maps to: CHANGE-0076 AC-001
- Spec-AC-01: SKILL_DASHBOARD.prompt.md is a script-first thin wrapper
  around `.aai/scripts/generate-dashboard.mjs`, documents both real input
  shapes the script parses (work-item ledger with nested agent_runs as the
  primary/real shape, and legacy flat entries as still-parsed), names the
  tokens-mostly-null reality (undecomposed usage_total_tokens notes), and
  never mentions the unimplemented --publish flag (points readers at
  /aai-share for publishing instead).
  - Verification: `wc -l -c .aai/SKILL_DASHBOARD.prompt.md`; `bash
    tests/skills/test-aai-prompt-diet.sh` TEST-017; manual live smoke of
    `generate-dashboard.mjs` in both invocation forms.
- Maps to: CHANGE-0076 AC-002
- Spec-AC-02: SKILL_TEST_SKILLS.prompt.md is trimmed of the stale hardcoded
  11-skill Example Output block and the pytest/cargo CI snippet, replaced
  with a live-discovery instruction (count the current
  tests/skills/test-aai-*.sh fleet rather than assume a fixed number), while
  keeping the real contracts: test-framework.sh invocation, the exit-42 SKIP
  convention, and the results-directory shape.
  - Verification: `bash tests/skills/test-aai-prompt-diet.sh` TEST-017;
    manual read confirming test-framework.sh / exit-42 / results-dir
    contracts are still present and accurate.
- Maps to: CHANGE-0076 AC-003
- Spec-AC-03: the prompt-diet byte-budget ledger
  (`tests/skills/lib/prompt-diet-ledger.sh`) carries a NEGATIVE RECLAIMED
  entry reflecting the measured corpus reduction, landing headroom back at
  exactly 636/2048 (the same steady-state the corpus was at before this
  scope); TEST-012's pinned JUSTIFIED_GROWTH_BYTES literal is bumped
  RED-first with paired RED/GREEN evidence logs under docs/ai/tdd/.
  - Verification: `bash tests/skills/test-aai-prompt-diet.sh` TEST-010
    (byte floor + headroom cap) and TEST-012 (ledger sum); RED/GREEN logs
    under docs/ai/tdd/.

## Constitution deviations

None.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | SKILL_DASHBOARD.prompt.md thin script-first wrapper, --publish removed | done | docs/ai/tdd/green-20260728T005214Z-dashboard-refit.log | — | 19173 B to 4152 B, 652 to 77 lines |
| Spec-AC-02 | SKILL_TEST_SKILLS.prompt.md trimmed of stale examples | done | docs/ai/tdd/green-20260728T005214Z-dashboard-refit.log | — | 9218 B to 2674 B, 404 to 58 lines |
| Spec-AC-03 | Prompt-diet ledger true-up, TEST-012 pin bumped RED-first | done | docs/ai/tdd/red-20260728T005204Z-dashboard-refit.log and docs/ai/tdd/green-20260728T005214Z-dashboard-refit.log | — | NEGATIVE entry -21565 B, JUSTIFIED_GROWTH_BYTES 14263 to -7302, headroom 636/2048 |

## Implementation plan
- `.aai/SKILL_DASHBOARD.prompt.md` (rewrite): Goal/Usage/Instructions/Input
  schema (both shapes)/Output/Troubleshooting, naming the real script and
  never re-deriving its logic in prose.
- `.aai/SKILL_TEST_SKILLS.prompt.md` (rewrite): Goal/Usage/Instructions
  around the real `tests/skills/test-framework.sh`, live fleet-count
  discovery instead of a hardcoded number, exit-code contract including
  exit-42 SKIP, results-dir shape, safety notes.
- `tests/skills/lib/prompt-diet-ledger.sh`: one new NEGATIVE
  `JUSTIFIED_ADDITIONS` entry (-21565 B) reclaiming exactly the measured
  corpus shrinkage so headroom lands back at 636/2048, mirroring the
  doctor-determinize precedent (CHANGE-0079).
- `tests/skills/test-aai-prompt-diet.sh`: TEST-012 pinned literal bumped
  14263 -> -7302 (a negative total is expected and allowed — TEST-013's
  leading-field regex accepts a `-` sign); new TEST-017 grep-contract pins
  (SKILL_DASHBOARD names generate-dashboard.mjs and never mentions
  --publish; SKILL_TEST_SKILLS never mentions pytest/cargo).
- No new files: `.aai/system/PROFILES.yaml` already lists both prompt paths
  (verified, no classification change needed); `tests/skills/suite-map.yaml`
  already covers `.aai/*.prompt.md` via the existing `aai-prompt-diet` row
  glob (verified, no new row needed).

## Edge cases
- A METRICS.jsonl mixing both schema shapes across lines: already handled by
  the script's per-line shape detection (`normalizeLedgerEntry` vs
  `normalizeOperationRecord`); documented as auto-detected, not a caller
  concern.
- Real work-item ledger entries with `tokens_in`/`tokens_out` both null
  (the common case today): dashboard token totals read low/zero; documented
  explicitly as a known gap, not a bug to chase per-run.
- `docs/dashboard-template.html` missing (vendored-layer drift): script
  exits 1 naming the missing file; prompt points at /aai-update, does not
  fabricate output.
- Ledger literal going negative (JUSTIFIED_GROWTH_BYTES -7302): explicitly
  allowed by TEST-013's regex and documented in the ledger entry's own
  rationale text — it reflects a corpus that has shrunk below any owed
  credit, not an error state.

## Test Plan
For each Spec-AC, enumerate concrete tests:

| Test ID | Spec-AC | Type | File path (expected) | Description | Status |
|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-prompt-diet.sh | SKILL_DASHBOARD names generate-dashboard.mjs, never mentions --publish | green |
| TEST-002 | Spec-AC-02 | unit | tests/skills/test-aai-prompt-diet.sh | SKILL_TEST_SKILLS never mentions pytest or cargo | green |
| TEST-003 | Spec-AC-03 | unit | tests/skills/test-aai-prompt-diet.sh | TEST-010 byte floor + headroom cap after the ledger true-up | green |
| TEST-004 | Spec-AC-03 | unit | tests/skills/test-aai-prompt-diet.sh | TEST-012 JUSTIFIED_GROWTH_BYTES == -7302 == independent re-sum | green |
| TEST-005 | Spec-AC-01 | e2e | manual smoke | generate-dashboard.mjs runs clean in both positional and named-flag form, --data-only respected | green |

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- Test IDs are stable — do not renumber after freeze.
- TEST-001..004 live in the pre-existing companion suite
  tests/skills/test-aai-prompt-diet.sh (TEST-017/TEST-010/TEST-012 in that
  file's own numbering); numbered here for full traceability.

## Verification
- `bash tests/skills/test-aai-prompt-diet.sh`
- `bash tests/skills/test-aai-verify-gate.sh`
- `bash tests/skills/test-aai-hygiene-pack.sh`
- `node .aai/scripts/generate-dashboard.mjs docs/ai/METRICS.jsonl <tmp>/dashboard.html`
- `node .aai/scripts/generate-dashboard.mjs --metrics docs/ai/METRICS.jsonl --output <tmp>/dashboard2.html --data-only`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0101-spec-dashboard-refit.md`
- `node .aai/scripts/docs-audit.mjs --gate spec-dashboard-refit --no-event`
- Evidence artifacts: docs/ai/tdd/red-20260728T005204Z-dashboard-refit.log,
  docs/ai/tdd/green-20260728T005214Z-dashboard-refit.log
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal
  status.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: spec-dashboard-refit
- Spec-AC and TEST-xxx links: see Test Plan table above
- command or review scope: bash tests/skills/test-aai-prompt-diet.sh
- exit code or review verdict: 0 (suite green as of this freeze)
- evidence path: docs/ai/tdd/ logs listed under Verification
- commit SHA or diff range: uncommitted on feat/dashboard-refit at freeze
  time; see `git log` on this branch for the landing commit

## Notes
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
