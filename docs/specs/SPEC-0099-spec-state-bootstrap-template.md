---
id: spec-state-bootstrap-template
type: spec
number: 99
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0074-state-bootstrap-template.md
  rfc: null
  pr:
    - 176
  commits:
    - 3d028c3c022d836eeebb5d7f43e9288ba09f0471
---

# Implementation Spec — Ship STATE_TEMPLATE.yaml and teach check-state --repair to create a missing STATE

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0074-state-bootstrap-template.md
- Decision records: docs/project-sessions/2026-07-27-universality-proof.md (finding F1)
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: the change touches a core governance script
  (`.aai/scripts/check-state.mjs`) whose exact byte behavior on an existing
  file is regression-pinned, and introduces a new canonical schema source
  consumed by both the validator and (transitively, via the dispatch tick)
  the orchestrator's rule table. A test never observed failing proves
  nothing — RED-first is required for the new check-state pins and for the
  prompt-diet ledger true-up.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: small, single-surface change (one new template file +
  one script's missing-file branch + test/docs/governance true-ups); no
  protected L3 surface is touched (`.aai/scripts/state.mjs`,
  `.aai/scripts/lib/state-engine.mjs`, `.aai/scripts/lib/state-core.mjs` are
  explicitly untouched); already isolated on its own feature branch.
- User decision: waived
- Base ref: main
- Worktree branch/path: feat/state-bootstrap-template (current branch)
- Inline review scope: .aai/templates/STATE_TEMPLATE.yaml, .aai/scripts/check-state.mjs, .aai/SKILL_CHECK_STATE.prompt.md, .aai/system/PROFILES.yaml, tests/skills/test-aai-check-state.sh, tests/skills/suite-map.yaml, tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh, docs/specs/SPEC-0099-spec-state-bootstrap-template.md, docs/issues/CHANGE-0074-state-bootstrap-template.md

## Acceptance Criteria Mapping
For each requirement AC:

- Maps to: AC-001
- Spec-AC-01: `node .aai/scripts/check-state.mjs --repair <path>` on a tree
  where `<path>` does NOT exist creates parent directories and writes the
  file from `.aai/templates/STATE_TEMPLATE.yaml` (the template path resolved
  relative to the script's own location, not cwd), stamping
  `updated_at_utc` with the real current UTC time, printing a clear
  "created from template" line, and exiting 0. Running
  `node .aai/scripts/orchestration-dispatch.mjs --state <path> --root <repo>`
  against the created file yields verdict `needs_llm` with reason
  `no_focus_ref` — never `state_file_missing`.
- Verification: `bash tests/skills/test-aai-check-state.sh` (new TEST-001) exit 0.

- Maps to: AC-002
- Spec-AC-02: `.aai/templates/STATE_TEMPLATE.yaml` is the tracked canonical
  source of the STATE schema header. Its leading comment block byte-equals
  `docs/ai/STATE.yaml`'s header WHEN a live (gitignored, per-dev) file
  exists locally; the template itself is asserted standalone — it parses
  clean under `check-state.mjs`'s structural loader and carries every
  canonical top-level key named in the header
  (`project_status`, `current_focus`, `active_work_items`,
  `implementation_strategy`, `worktree`, `code_review`, `last_validation`,
  `updated_at_utc`). `.aai/SKILL_CHECK_STATE.prompt.md`'s AUTHORITATIVE
  SCHEMA paragraph is reworded to name the template (not the gitignored live
  file) as the canonical schema location.
- Verification: `bash tests/skills/test-aai-check-state.sh` (new TEST-002,
  TEST-003, TEST-004) exit 0.

- Maps to: AC-003
- Spec-AC-03: no regression — the full `tests/skills/test-aai-check-state.sh`
  suite (pre-existing TEST-004/005/006/010/011 plus the ISSUE-0007
  list-indent/orphan-item lint stanzas and the new TEST-001..005 below) exits
  0, and `--repair` on an EXISTING file's behavior is byte-unchanged (the
  create-from-template branch fires only when the target does not exist).
  `.aai/system/PROFILES.yaml` stays 100% classified (new template row added)
  and `tests/skills/suite-map.yaml`'s `aai-check-state` row covers the new
  template path.
- Verification: `bash tests/skills/test-aai-check-state.sh` exit 0;
  `bash tests/skills/test-aai-layer-profiles.sh` exit 0;
  `bash tests/skills/test-aai-suite-select.sh` exit 0.

## Constitution deviations

None.

## Companion obligations (Planning step 3a)
- Prompt-corpus diet ledger: TRIGGERED. `.aai/SKILL_CHECK_STATE.prompt.md`'s
  AUTHORITATIVE SCHEMA paragraph grew by 286 bytes (349254 -> 349540) naming
  the new template as canonical. Folded into scope:
  `tests/skills/lib/prompt-diet-ledger.sh` gained a new `JUSTIFIED_ADDITIONS`
  entry (`"286 state-bootstrap-template ..."`) and
  `tests/skills/test-aai-prompt-diet.sh` TEST-012's expected total was
  bumped 31025 -> 31311 (RED-first: docs/ai/tdd/red-20260727T212858Z-TEST-012.log,
  GREEN: docs/ai/tdd/green-*-TEST-012.log).
- New `.aai/**` file classification: TRIGGERED. `.aai/templates/STATE_TEMPLATE.yaml`
  is new. Folded into scope: `.aai/system/PROFILES.yaml` classifies it
  `core` (alphabetically among the other `.aai/templates/*` core rows — it is
  a template a core-owned flow, `check-state.mjs --repair`, instantiates).

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description                                                        | Status | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | missing-file --repair creates from template; dispatch yields no_focus_ref | done   | tests/skills/test-aai-check-state.sh TEST-001 | — | — |
| Spec-AC-02 | template is tracked canonical schema source; header pin + standalone parse; SKILL_CHECK_STATE reworded | done | tests/skills/test-aai-check-state.sh TEST-002/003/004 | — | — |
| Spec-AC-03 | no regression: full check-state/layer-profiles/suite-select suites green; existing-file repair byte-unchanged | done | tests/skills/test-aai-check-state.sh (full); tests/skills/test-aai-layer-profiles.sh; tests/skills/test-aai-suite-select.sh | — | — |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan
- Components/modules affected:
  - `.aai/templates/STATE_TEMPLATE.yaml` (new) — the schema header comment
    block copied verbatim from `docs/ai/STATE.yaml` lines 1-23, followed by
    empty canonical defaults for every top-level key the header documents,
    plus `metrics: {work_items: {}}`, plus a
    `updated_at_utc: TEMPLATE_PLACEHOLDER` sentinel the creator stamps.
  - `.aai/scripts/check-state.mjs` — new `createFromTemplate()` helper,
    wired into `main()`'s existing missing-file branch (only when `--repair`
    is passed): resolves the template relative to
    `path.dirname(fileURLToPath(import.meta.url))` (never cwd), replaces the
    placeholder line with a real ISO-8601 UTC stamp, `mkdir -p`s the parent
    directory, writes the file, prints a `CREATED: ... created from
    template ...` line, exits 0. The non-repair missing-file branch (`ERROR:
    STATE file not found` + exit 2) and every existing-file code path are
    untouched byte-for-byte.
  - `.aai/SKILL_CHECK_STATE.prompt.md` — AUTHORITATIVE SCHEMA paragraph
    reworded to name `.aai/templates/STATE_TEMPLATE.yaml` as the canonical
    schema source and state the live-header-must-match-template pin.
  - `.aai/system/PROFILES.yaml` — one new `core` row for the template.
  - `tests/skills/suite-map.yaml` — the template path added to the
    `aai-check-state` suite's globs (data-only).
  - `tests/skills/lib/prompt-diet-ledger.sh` /
    `tests/skills/test-aai-prompt-diet.sh` — ledger true-up (see Companion
    obligations above).
  - `tests/skills/test-aai-check-state.sh` — five new pinned tests (TEST-001..005).
- Data flows: `check-state.mjs --repair` is the only writer of a
  from-template STATE file; `orchestration-dispatch.mjs` reads the result
  read-only (its own `buildSnapshot()`/`decide()` logic is unchanged — the
  template is deliberately constructed to satisfy its existing required-block
  and enum checks, not a new code path in dispatch).
- Edge cases:
  - Template itself missing when `--repair` hits a missing target: fail
    loud with both paths named, exit 2 (never silently no-op).
  - Template missing its `updated_at_utc: TEMPLATE_PLACEHOLDER` sentinel
    (corrupted template): fail loud rather than writing an unstamped file,
    exit 1.
  - `--repair` on an EXISTING file (any shape, clean or dirty): the
    create-from-template branch never fires — regression-pinned byte-for-byte
    against the pre-existing behavior (TEST-005).
  - No live `docs/ai/STATE.yaml` present locally (fresh checkout, the exact
    F1 scenario): the header-parity test (TEST-002) skips cleanly instead of
    failing — it has nothing to compare against yet, which is the bug this
    scope fixes, not a test precondition failure.

## Test Plan
For each Spec-AC, enumerate concrete tests:

| Test ID  | Spec-AC    | Type | File path (expected)                    | Description                                                                                     | Status |
|----------|------------|------|------------------------------------------|---------------------------------------------------------------------------------------------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-check-state.sh | `--repair` on a missing nested target creates it (mkdir -p + template body + real stamp, "created from template" message); dispatch on the result yields `no_focus_ref`, never `state_file_missing` | green  |
| TEST-002 | Spec-AC-02 | unit | tests/skills/test-aai-check-state.sh | Template's leading comment header byte-equals the live `docs/ai/STATE.yaml` header when one exists locally; skips cleanly when absent | green  |
| TEST-003 | Spec-AC-02 | unit | tests/skills/test-aai-check-state.sh | Template parses clean under `check-state.mjs` standalone and carries every canonical top-level key | green  |
| TEST-004 | Spec-AC-02 | unit | tests/skills/test-aai-check-state.sh | `.aai/SKILL_CHECK_STATE.prompt.md` AUTHORITATIVE SCHEMA paragraph names the template as canonical and explains why (gitignored live file) | green  |
| TEST-005 | Spec-AC-03 | unit | tests/skills/test-aai-check-state.sh | `--repair` on an EXISTING, already-clean file is a byte-unchanged no-op; the create-from-template message never prints | green  |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-layer-profiles.sh + tests/skills/test-aai-suite-select.sh | Full layer-profiles and suite-select suites stay green (new template classified + mapped) | green  |

Test status values: pending -> red -> green

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- RED-proof obligation: TEST-001..005 were each observed FAILING before their
  respective implementation piece existed (create-from-template branch,
  template file, reworded prose) — see TDD evidence paths in the Verification
  section below.
- Test IDs are stable — do not renumber after freeze.

## Seam analysis
- SEAM-1 (`.aai/templates/STATE_TEMPLATE.yaml` -> `check-state.mjs --repair`
  -> `orchestration-dispatch.mjs`'s `buildSnapshot()`/`decide()`): the
  template's field values must satisfy dispatch's required-block and enum
  checks (`current_focus`, `last_validation`, `code_review` present;
  `project_status`/`implementation_strategy.selected`/
  `worktree.recommendation`/`worktree.user_decision`/`code_review.required`/
  `code_review.status`/`last_validation.status` all valid enum members) or
  the created file would immediately re-trigger a DIFFERENT `needs_llm`
  reason (e.g. `unknown_enum_value:...`) instead of the intended
  `no_focus_ref`. Covered end-to-end by TEST-001, which runs the REAL
  `orchestration-dispatch.mjs` CLI against the file `check-state.mjs`
  actually created — not a mocked snapshot.
- SEAM-2 (template header <-> `docs/ai/STATE.yaml` header <->
  `.aai/SKILL_CHECK_STATE.prompt.md` prose): three independent surfaces
  describe the same schema; TEST-002 pins the first two never drifting, and
  TEST-004 pins the third naming the template as authoritative. A future
  header edit to only one of the three would be caught by these tests going
  RED, not silently accepted.
- Residual risk: `.aai/scripts/autonomous-loop.sh`'s pre-existing
  `create_state_file()` (its own `--auto-init-state` flag) has an
  independent, narrower inline STATE stub that does NOT match the new
  template's field set (it lacks `implementation_strategy`, `code_review`,
  `metrics`, for example) — this scope does not touch it (out of the
  dispatched task list) and it is not exercised by any test here. Two
  differently-shaped STATE creators now exist in the repo; recorded as a
  known follow-up gap, not fixed in this scope (Review-By 2026-08-25).

## Verification
- Commands to run:
  - `bash tests/skills/test-aai-check-state.sh`
  - `bash tests/skills/test-aai-layer-profiles.sh`
  - `bash tests/skills/test-aai-prompt-diet.sh`
  - `bash tests/skills/test-aai-suite-select.sh`
  - `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0099-spec-state-bootstrap-template.md`
  - `node .aai/scripts/docs-audit.mjs --gate spec-state-bootstrap-template --no-event`
- Evidence artifacts:
  - docs/ai/tdd/red-20260727T212858Z-TEST-012.log
  - docs/ai/tdd/green-*-TEST-012.log
  - docs/ai/tdd/red-20260727T213155Z-TEST-001-005.log (TEST-001)
  - docs/ai/tdd/red-20260727T213204Z-test_*.log (TEST-002..004, named per test function)
  - docs/ai/tdd/green-20260727T213403Z-final-check-state.log (full suite GREEN)
  - NOTE: TEST-005 is a tautological-by-design regression pin (existing-file
    no-op predates the change) — it has no observed-failing RED and claims
    none; the pin guards against FUTURE regressions of the untouched path.
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: state-bootstrap-template
- Spec-AC and TEST-xxx links: as in the Test Plan table above
- command or review scope: as in Verification above
- exit code: 0 for all commands (see logs)
- evidence path: docs/ai/tdd/red-20260727T213155Z-TEST-001-005.log, docs/ai/tdd/red-20260727T213204Z-test_*.log, docs/ai/tdd/green-20260727T213403Z-final-*.log, docs/ai/tdd/red-20260727T212858Z-TEST-012.log
- commit SHA or diff range: uncommitted at time of writing (single-writer:
  orchestrator commits); diff range = working tree vs `main` on
  `feat/state-bootstrap-template`

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
