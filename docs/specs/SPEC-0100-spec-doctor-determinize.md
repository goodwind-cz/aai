---
id: spec-doctor-determinize
type: spec
number: 100
status: done
ceremony_level: 2
links:
  requirement: CHANGE-0079
  rfc: null
  pr:
    - 178
  commits:
    - 8e167599068a3ce15c02cae2bd7d3175200b754e
---

## Links
- Requirement: docs/issues/CHANGE-0079-doctor-determinize.md
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md

## Summary
SKILL_DOCTOR.prompt.md was 10.7 KB prose, and only 2 of its 13 health-check
categories (CAT-11 docs hygiene, CAT-13 vendored layer drift) called a real
script — the other 11 (~20 file-existence/line-count checks, git-status
parsing, hook wiring, dynamic-skills presence, template presence, the
RFC-0001 migration matrix) were prose instructing the LLM to recompute what a
script computes cheaper and without variance. This spec covers a new
deterministic, zero-dependency engine (`.aai/scripts/aai-doctor.mjs`)
covering all 13 categories (CAT-11/CAT-13 as unchanged subprocess calls to
the existing `docs-audit.mjs`/`layer-drift.mjs`), and slims
`SKILL_DOCTOR.prompt.md` to a thin wrapper that runs the script and relays
its output — mirroring the proven CAT-11/CAT-13 pattern.

## Implementation strategy
- Strategy: tdd
- Rationale: new deterministic behavior (13 category verdicts, exit-code
  contract, --json shape) that downstream automation and users depend on;
  regression-proofing each category's PASS/WARN/FAIL/SKIP transition against
  fixtures is exactly what RED-GREEN-REFACTOR is for. Not a bugfix, but the
  behavior is risky to get silently wrong (a doctor that lies is worse than
  no doctor), so TDD over loop.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single-branch, no protected-surface (L3) paths, no
  schema/migration risk; already on a dedicated feature branch
  (feat/doctor-determinize); a small, clearly scoped script + prompt + test
  suite change.
- User decision: waived
- Base ref: main
- Worktree branch/path: feat/doctor-determinize (current checkout)
- Inline review scope: .aai/scripts/aai-doctor.mjs, .aai/SKILL_DOCTOR.prompt.md,
  tests/skills/test-aai-doctor.sh, tests/skills/test-aai-layer-drift.sh,
  tests/skills/test-aai-layer-profiles.sh, tests/skills/lib/prompt-diet-ledger.sh,
  tests/skills/test-aai-prompt-diet.sh, tests/skills/suite-map.yaml,
  .aai/system/PROFILES.yaml, docs/specs/SPEC-0100-spec-doctor-determinize.md

## Acceptance Criteria Mapping
- Maps to: CHANGE-0079 AC-001
- Spec-AC-01: `.aai/scripts/aai-doctor.mjs` computes all 13 health-check
  category verdicts deterministically (PASS/WARN/FAIL/SKIP + short reason),
  reproducing on this repo the verdicts the prose categories previously
  demanded, byte-stably across repeat runs, with a `--json` machine-readable
  mode and a documented exit-code contract (0 = CLEAN/warnings-only, 1 = any
  FAIL). CAT-11 and CAT-13 remain subprocess calls to `docs-audit.mjs
  --quick --no-event` and `layer-drift.mjs` honoring their documented exit
  codes (incl. layer-drift exit 4 = unverifiable, the normal verdict inside
  this canonical repo itself).
  - Verification: `bash tests/skills/test-aai-doctor.sh` (TEST-001..020);
    manual run `node .aai/scripts/aai-doctor.mjs --json` against this repo.
- Maps to: CHANGE-0079 AC-002
- Spec-AC-02: `.aai/SKILL_DOCTOR.prompt.md` shrinks to a thin wrapper
  (script invocation + output relay + the one genuinely judgmental
  category note for CAT-06); the prompt-diet byte-budget ledger reflects
  the corpus REDUCTION via a NEGATIVE `JUSTIFIED_ADDITIONS` entry so
  headroom lands back at 636/2048; `tests/skills/test-aai-prompt-diet.sh`
  TEST-012's pinned `JUSTIFIED_GROWTH_BYTES` value is bumped RED-first.
  - Verification: `bash tests/skills/test-aai-doctor.sh` TEST-021 (thin
    wrapper shape); `bash tests/skills/test-aai-prompt-diet.sh` TEST-010
    (byte floor + headroom cap) and TEST-012 (ledger sum); RED/GREEN logs
    under docs/ai/tdd/.
- Maps to: CHANGE-0079 AC-003
- Spec-AC-03: no regression — a doctor smoke run against a synthetic
  "fully clean" fixture target project reports `DOCTOR CLEAN` with exit 0,
  and a live smoke run against this real repo completes without crashing
  and without an unexpected CAT-01/CAT-02 FAIL. Companion suites that
  previously asserted on the old CAT-13 prose (`test-aai-layer-drift.sh`,
  `test-aai-layer-profiles.sh`) are updated to assert on the new
  script-based wiring instead of silently breaking.
  - Verification: `bash tests/skills/test-aai-doctor.sh` TEST-014
    (clean fixture) and TEST-019 (real-repo smoke); `bash
    tests/skills/test-aai-layer-drift.sh`; `bash
    tests/skills/test-aai-layer-profiles.sh`.

## Constitution deviations

None.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | aai-doctor.mjs deterministic 13-category engine, CAT-11/13 subprocess-wired | done | docs/ai/tdd/green-20260727T233339Z-doctor-determinize.log | - | tests/skills/test-aai-doctor.sh all 22 TEST- assertions green |
| Spec-AC-02 | SKILL_DOCTOR.prompt.md thin wrapper + prompt-diet ledger true-up | done | docs/ai/tdd/green-20260727T233657Z-prompt-diet-doctor-determinize.log | - | -7534 B NEGATIVE ledger entry, TEST-012 bumped 21738 to 14204, headroom 636/2048 |
| Spec-AC-03 | No regression: clean-fixture smoke + real-repo smoke + companion suites | done | tests/skills/test-aai-layer-drift.sh and test-aai-layer-profiles.sh both green after CAT-13 wiring update | - | see Verification commands below |

## Implementation plan
- `.aai/scripts/aai-doctor.mjs` (new): 13 pure-ish category functions over a
  resolved `root`, zero deps (node:fs/path/child_process/url only),
  cwd-independent default root (derived from the script's own file
  location, two levels up), `--root` override for fixtures/foreign trees,
  `--json` flag. CAT-06/11/13 spawn the sibling scripts
  (`check-state.mjs`, `docs-audit.mjs`, `layer-drift.mjs`) found next to
  the INVOKED copy of `aai-doctor.mjs` (production: always the same
  vendored `.aai/scripts/`; tests: a fixture-local copy, mirroring the
  `test-aai-layer-drift.sh test_space_in_path` technique).
- `.aai/SKILL_DOCTOR.prompt.md` (rewrite): thin wrapper naming the script,
  relaying its output, and explicitly scoping CAT-06's shallow-check
  design decision (structural duplicate-key check only; full 14-invariant
  semantic validation stays `/aai-check-state`'s job — the one genuinely
  judgmental piece, not force-fit into the script).
- `.aai/system/PROFILES.yaml`: classify `.aai/scripts/aai-doctor.mjs` as
  `core` (distribution & health category, alongside `layer-drift.mjs` /
  `docs-audit.mjs`).
- `tests/skills/suite-map.yaml`: new `aai-doctor` row (globs:
  `.aai/scripts/aai-doctor.mjs`, `.aai/SKILL_DOCTOR.prompt.md`).
- `tests/skills/test-aai-doctor.sh` (new): fixture-driven TDD suite.
- `tests/skills/test-aai-layer-drift.sh` / `test-aai-layer-profiles.sh`:
  update the CAT-13-wiring assertions to check the new script instead of
  the retired prose (same intent, new location of truth).
- `tests/skills/lib/prompt-diet-ledger.sh` + `test-aai-prompt-diet.sh`:
  ledger true-up (NEGATIVE entry, TEST-012 pin bump).

## Edge cases
- STATE.yaml absent (fresh checkout, RFC-0001 per-dev file): CAT-01 FAILs
  (mirrors the original prose's explicit "report BROKEN immediately"
  instruction verbatim); CAT-06 separately WARNs rather than re-FAILing,
  naming the RFC-0001 per-dev nature.
- Non-git target directory: CAT-08 reports SKIP, not FAIL/WARN.
- No AAI_PIN.md / running inside the canonical repo itself: CAT-13 exit 4
  (unverifiable) is tolerated as WARN, never FAIL — this is the NORMAL
  verdict when running the doctor inside this repo.
- A universal skill's SKILL.md that names no `.aai/*.prompt.md` at all
  (e.g. aai-overview, which points at a script): healthy by definition,
  not an orphan.
- Helper script missing entirely (docs-audit.mjs / layer-drift.mjs /
  check-state.mjs not vendored): degrades to WARN naming `/aai-update`,
  never crashes.

## Test Plan
For each Spec-AC, enumerate concrete tests:

| Test ID | Spec-AC | Type | File path (expected) | Description | Status |
|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-doctor.sh | CAT-01 required file missing names the file, FAIL | green |
| TEST-002 | Spec-AC-01 | unit | tests/skills/test-aai-doctor.sh | CAT-02 role prompt missing names the file, FAIL | green |
| TEST-003 | Spec-AC-01 | unit | tests/skills/test-aai-doctor.sh | CAT-03 dangling SKILL.md prompt reference, WARN named | green |
| TEST-004 | Spec-AC-01 | unit | tests/skills/test-aai-doctor.sh | CAT-04 none found WARN, some found PASS | green |
| TEST-005 | Spec-AC-01 | unit | tests/skills/test-aai-doctor.sh | CAT-05 empty/missing knowledge files WARN, named | green |
| TEST-006 | Spec-AC-01 | integration | tests/skills/test-aai-doctor.sh | CAT-06 duplicate top-level key FAIL via real check-state.mjs; missing STATE.yaml WARN | green |
| TEST-007 | Spec-AC-01 | unit | tests/skills/test-aai-doctor.sh | CAT-07 telemetry jsonl line counts | green |
| TEST-008 | Spec-AC-01 | integration | tests/skills/test-aai-doctor.sh | CAT-08 dirty tree WARN, non-git SKIP | green |
| TEST-009 | Spec-AC-01 | unit | tests/skills/test-aai-doctor.sh | CAT-09 pre-compact hook presence | green |
| TEST-010 | Spec-AC-01 | integration | tests/skills/test-aai-doctor.sh | CAT-10 RFC-0001 migration matrix (LEGACY, INCONSISTENT cases) | green |
| TEST-011 | Spec-AC-01 | integration | tests/skills/test-aai-doctor.sh | CAT-11 docs-audit.mjs missing WARN; stubbed CLEAN PASS | green |
| TEST-012 | Spec-AC-01 | unit | tests/skills/test-aai-doctor.sh | CAT-12 pre-commit hook marker states | green |
| TEST-013 | Spec-AC-01 | integration | tests/skills/test-aai-doctor.sh | CAT-13 real layer-drift.mjs exit 4 tolerated as WARN, doctor exit 0 | green |
| TEST-014 | Spec-AC-03 | e2e | tests/skills/test-aai-doctor.sh | fully-clean fixture -> DOCTOR CLEAN, exit 0 | green |
| TEST-015 | Spec-AC-01 | unit | tests/skills/test-aai-doctor.sh | --json shape: 13 categories, CAT-01..13, documented keys | green |
| TEST-016 | Spec-AC-01 | unit | tests/skills/test-aai-doctor.sh | exit codes: FAIL category -> 1, WARN-only -> 0 | green |
| TEST-017 | Spec-AC-01 | integration | tests/skills/test-aai-doctor.sh | cwd-independence: identical output from two different caller cwds | green |
| TEST-018 | Spec-AC-01 | integration | tests/skills/test-aai-doctor.sh | default root resolves from invoked script's own location, no --root | green |
| TEST-019 | Spec-AC-03 | e2e | tests/skills/test-aai-doctor.sh | real-repo smoke: no crash, DOCTOR verdict line, no unexpected FAIL | green |
| TEST-020 | Spec-AC-01 | unit | tests/skills/test-aai-doctor.sh | CLI usage errors (unknown flag, missing --root value) exit 2 | green |
| TEST-021 | Spec-AC-02 | unit | tests/skills/test-aai-doctor.sh | SKILL_DOCTOR.prompt.md is a thin wrapper (<=100 lines, names script) | green |
| TEST-022 | Spec-AC-03 | unit | tests/skills/test-aai-doctor.sh | suite-map.yaml has an aai-doctor row (hygiene pin) | green |
| TEST-023 | Spec-AC-02 | unit | tests/skills/test-aai-prompt-diet.sh | TEST-010 byte floor + headroom cap after the ledger true-up | green |
| TEST-024 | Spec-AC-02 | unit | tests/skills/test-aai-prompt-diet.sh | TEST-012 JUSTIFIED_GROWTH_BYTES == 14204 == independent re-sum | green |
| TEST-025 | Spec-AC-03 | integration | tests/skills/test-aai-layer-drift.sh | CAT-13 wiring assertion updated to the new script location | green |
| TEST-026 | Spec-AC-03 | integration | tests/skills/test-aai-layer-profiles.sh | CAT-13 profile-display assertion updated to the new script location | green |

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- Test IDs are stable — do not renumber after freeze.
- TEST-023..026 live in pre-existing companion suites this scope touches;
  numbered here for full traceability even though their file paths are not
  tests/skills/test-aai-doctor.sh.

## Verification
- `bash tests/skills/test-aai-doctor.sh`
- `bash tests/skills/test-aai-prompt-diet.sh`
- `bash tests/skills/test-aai-layer-drift.sh`
- `bash tests/skills/test-aai-layer-profiles.sh`
- `bash tests/skills/test-aai-suite-select.sh`
- `bash tests/skills/test-aai-hygiene-pack.sh`
- `bash tests/skills/test-aai-verify-gate.sh`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0100-spec-doctor-determinize.md`
- `node .aai/scripts/docs-audit.mjs --gate spec-doctor-determinize --no-event`
- Evidence artifacts: docs/ai/tdd/red-20260727T233008Z-doctor-determinize.log,
  docs/ai/tdd/green-20260727T233339Z-doctor-determinize.log,
  docs/ai/tdd/red-20260727T233607Z-prompt-diet-doctor-determinize.log,
  docs/ai/tdd/red-20260727T233649Z-prompt-diet-test012-doctor-determinize.log,
  docs/ai/tdd/green-20260727T233657Z-prompt-diet-doctor-determinize.log
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: spec-doctor-determinize
- Spec-AC and TEST-xxx links: see Test Plan table above
- command or review scope: bash tests/skills/test-aai-doctor.sh (and the
  companion suites listed under Verification)
- exit code or review verdict: 0 (all suites green as of this freeze)
- evidence path: docs/ai/tdd/ logs listed under Verification
- commit SHA or diff range: uncommitted on feat/doctor-determinize at
  freeze time; see `git log` on this branch for the landing commit

## Notes
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
