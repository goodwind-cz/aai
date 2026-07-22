---
id: spec-planning-companion-obligations
type: spec
number: 71
status: done
ceremony_level: 1
links:
  requirement: docs/issues/ISSUE-0025-planning-companion-obligations.md
  rfc: null
  pr:
    - 130
  commits:
    - ac1af1f05b9bb451100f544ece34a2878a9b6671
---

# Implementation Spec — Planning companion-obligations checklist

SPEC-FROZEN: true

Ceremony justification: the scope touches only `.aai/PLANNING.prompt.md`
(prompt text — an additive checklist step), the prompt-diet ledger true-up
(`tests/skills/lib/prompt-diet-ledger.sh`, a data-only array append, plus the
matching literal bump in `tests/skills/test-aai-prompt-diet.sh` TEST-012), and
one structural test addition in `tests/skills/test-aai-hygiene-pack.sh`. None
of these paths appear in `protected_paths_l3` (docs/ai/docs-audit.yaml):
`.aai/scripts/state.mjs`, `.aai/scripts/lib/state-engine.mjs`,
`.aai/scripts/lib/state-core.mjs`, `.aai/scripts/allocate-doc-number.mjs`,
`.aai/scripts/pre-commit-checks.sh`, `.aai/scripts/pre-commit-checks.ps1`,
`.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md`. No new `.aai/**` file is
created (the checklist is added to an EXISTING prompt file), so the
PROFILES.yaml-classification companion itself is not triggered by this
scope's own edits — only the prompt-diet ledger companion applies, and it is
demonstrated on this very scope (see Spec-AC-04). Single reviewable,
reversible, additive surface -> Level 1.

## Links
- Requirement: docs/issues/ISSUE-0025-planning-companion-obligations.md
- Decision records: n/a
- Technology contract: docs/TECHNOLOGY.md

## Problem

`.aai/PLANNING.prompt.md` builds Spec-ACs, a Test Plan, strategy, isolation,
and review scope for the FEATURE a scope describes, but never reminds the
planner that two recurring classes of change carry a companion edit enforced
only later by CI:

1. Any scope that ADDS bytes to the prompt corpus (`.aai/*.prompt.md`,
   `.aai/AGENTS.md`) must add an itemized `JUSTIFIED_ADDITIONS` entry (and
   bump the `TEST-012` checkpoint) in
   `tests/skills/lib/prompt-diet-ledger.sh`, or `test-aai-prompt-diet.sh`
   TEST-010's byte-floor fails and cascades into every suite that re-runs it
   (ceremony-levels, constitution, debug-gate, advisory-skills,
   delta-stage2). This is already definition-of-done in
   `docs/knowledge/LEARNED.md` (2026-07-17, ~lines 131-134) but absent from
   the prompt the planner actually reads.
2. Any NEW `.aai/**` file must be classified in `.aai/system/PROFILES.yaml`
   (core or extended), or `test-aai-layer-profiles.sh` TEST-001 manifest
   conformance fails and cascades into `test-aai-release.sh` TEST-020.

Because the spec's scope is drafted before the companion is known to be
required, Implementation ships a "complete" change and CI fails on an
invariant Planning never surfaced — observed three times in one session per
the intake (HITL, sweep, and branch-per-work-item-hygiene PRs).

## Scope
- In scope: an additive "COMPANION OBLIGATIONS CHECK" step in
  `.aai/PLANNING.prompt.md` (closed, two entries, no auto-detection logic);
  the matching self-dogfooding prompt-diet ledger true-up for THIS scope's
  own prompt-corpus byte growth in `tests/skills/lib/prompt-diet-ledger.sh`
  (new `JUSTIFIED_ADDITIONS` entry) and `tests/skills/test-aai-prompt-diet.sh`
  (bumped `TEST-012` expected-sum literal); one new structural test function
  in `tests/skills/test-aai-hygiene-pack.sh` asserting the checklist text is
  present and names both companions + their target files; this spec doc.
- Out of scope: any auto-detection script or new guard that programmatically
  decides whether a companion is required (fail-safe stays the existing CI
  gates; this scope only moves the catch earlier, into the planner's
  checklist); a third companion obligation (the checklist is intentionally
  closed to two; a future recurring companion is a separate, later scope);
  `SKILL_PR.prompt.md` (a belt-and-suspenders precondition there is left for
  a future scope if review argues its cost is worth it — PLANNING is the
  primary home per the intake); any change to `.aai/system/PROFILES.yaml`
  itself (no new `.aai/**` file is created by this scope, so nothing needs
  classifying); any `protected_paths_l3` file (`WORKFLOW.md`,
  `CONSTITUTION.md`, `pre-commit-checks.*`, `state*.mjs`,
  `allocate-doc-number.mjs`).
- Protected paths touched: none.

## Design — the checklist step

Insert a new step `3a)` in `.aai/PLANNING.prompt.md`, between the existing
step 3 ("Read the relevant requirement/intake artifacts for the scope.") and
step 4 ("Create or update docs/specs/SPEC-<id>.md..."), so the planner reads
it BEFORE drafting the spec's scope — the same placement pattern step 6a
(seam analysis) already uses relative to the Test Plan step:

```
3a) COMPANION OBLIGATIONS CHECK (closed list, two entries — do not add a
    third here; a new auto-detection script would be a separate, larger
    scope):
    - Scope ADDS BYTES to the prompt corpus (`.aai/*.prompt.md`,
      `.aai/AGENTS.md`) -> fold a prompt-diet ledger true-up (new
      JUSTIFIED_ADDITIONS entry + bumped TEST-012 checkpoint) into this
      scope's scope + Test Plan: tests/skills/lib/prompt-diet-ledger.sh.
    - Scope ADDS a NEW `.aai/**` file -> fold a classification entry into
      this scope's scope + Test Plan: .aai/system/PROFILES.yaml.
    Neither trigger applies -> skip, no note required.
```

Implementation may reflow whitespace/wording for house style, but MUST
preserve: the heading naming "COMPANION OBLIGATIONS"; both trigger
conditions (prompt-corpus byte growth; new `.aai/**` file); both companion
names ("ledger true-up" / "JUSTIFIED_ADDITIONS" and "classification" /
"PROFILES"); and both target file paths verbatim
(`tests/skills/lib/prompt-diet-ledger.sh`, `.aai/system/PROFILES.yaml`) —
these are the exact strings TEST-001/TEST-002 grep for.

## Self-dogfooding: this scope's own ledger true-up

This scope's own edit to `.aai/PLANNING.prompt.md` adds prompt-corpus bytes,
so trigger 1 of the very checklist being introduced applies to the scope
itself. Implementation MUST, in the same change:
- Append one new entry to `JUSTIFIED_ADDITIONS` in
  `tests/skills/lib/prompt-diet-ledger.sh`, `<bytes> planning-companion-
  obligations <rationale>`, where `<bytes>` is the measured deficit (or a
  small headroom-bounded credit, `HEADROOM_CAP` = 2048) for the actual
  prompt-corpus growth from step 3a's text — measured at implementation
  time, not predicted here.
- Update the hardcoded `JUSTIFIED_GROWTH_BYTES == <N>` literal (and its
  docstring) in `tests/skills/test-aai-prompt-diet.sh` TEST-012 to the new
  ledger sum.
- Confirm both consumers of the shared ledger (`test-aai-prompt-diet.sh` and
  `test-aai-verify-gate.sh` — see Seam analysis) stay green.

The exact byte credit is NOT hardcoded in this frozen spec (it depends on
Implementation's final wording of step 3a); the Test Plan therefore asserts
"suite green" (TEST-004) rather than a specific byte number, per the current
`JUSTIFIED_ADDITIONS` ledger's own convention of self-documenting itemized
entries rather than a recomputed magic constant.

## Implementation strategy
- Strategy: loop
- Rationale: every TEST-xxx below is a grep/text-presence assertion or a
  full-suite pass/fail check — prose additions to a prompt file, a data-only
  array append to a ledger, and a literal-constant bump. There is no new
  deterministic exit-code branching logic to drive through RED-GREEN-REFACTOR
  (contrast SPEC-0070's `branch-guard.mjs`, which had five distinct exit
  codes and warranted `hybrid`/TDD). RED-proof still holds without TDD
  discipline: TEST-001/002 are observed failing today (`grep -c` = 0, the
  checklist text does not exist yet) and TEST-004 is observed failing the
  moment the checklist bytes land without a matching ledger entry, because
  the current ledger runs at 0 B headroom (`tests/skills/lib/prompt-diet-
  ledger.sh`'s most recent entry: "credit chosen 494 B for 0 B headroom") —
  any unaccounted growth immediately breaks TEST-010.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: one additive prompt-text step, one data-only ledger
  array append, one literal-constant bump, and one new test function — four
  small, reversible, non-protected-surface edits in one file family; the
  session is already on branch `fix/planning-companion-obligations`.
- User decision: inline
- Base ref: main
- Worktree branch/path: fix/planning-companion-obligations (inline)
- Inline review scope: `.aai/PLANNING.prompt.md`,
  `tests/skills/lib/prompt-diet-ledger.sh`,
  `tests/skills/test-aai-prompt-diet.sh`,
  `tests/skills/test-aai-hygiene-pack.sh`,
  `docs/specs/SPEC-0071-spec-planning-companion-obligations.md`

## Acceptance Criteria Mapping

- Requirement (Verification bullet 1: checklist gains both triggers naming
  their companion + file) -> Spec-AC-01, Spec-AC-02.
- Requirement (Verification bullet: closed, additive, no auto-detection
  logic) -> Spec-AC-03.
- Requirement (Verification bullet 2: self-demonstration — the scope's own
  prompt growth is ledgered, full skills suite green) -> Spec-AC-04.

- Maps to: Requirement Verification bullet 1
- Spec-AC-01: `.aai/PLANNING.prompt.md` contains a "COMPANION OBLIGATIONS"
  checklist step, positioned before the existing step 4 ("Create or update
  docs/specs/SPEC-<id>.md"), that names trigger 1 (prompt-corpus byte
  growth in `.aai/*.prompt.md`/`.aai/AGENTS.md`) mapped to the prompt-diet
  ledger true-up companion and the concrete file
  `tests/skills/lib/prompt-diet-ledger.sh`.
  - Verification: `bash tests/skills/test-aai-hygiene-pack.sh` (function
    `test_070_companion_obligations`) -> exit 0. RED-proof:
    `grep -c "COMPANION OBLIGATIONS" .aai/PLANNING.prompt.md` = 0 today.

- Maps to: Requirement Verification bullet 1
- Spec-AC-02: the same checklist step names trigger 2 (a NEW `.aai/**` file)
  mapped to the PROFILES.yaml classification companion and the concrete file
  `.aai/system/PROFILES.yaml`.
  - Verification: `bash tests/skills/test-aai-hygiene-pack.sh` (function
    `test_070_companion_obligations`) -> exit 0. RED-proof:
    `grep -c "PROFILES.yaml" .aai/PLANNING.prompt.md` = 0 today (the string
    does not appear anywhere in the file).

- Maps to: Requirement (closed, additive, no auto-detection logic)
- Spec-AC-03: the checklist step contains EXACTLY two trigger entries (no
  third obligation, no auto-detection script/guard added anywhere in the
  scope's diff).
  - Verification: `bash tests/skills/test-aai-hygiene-pack.sh` (function
    `test_070_companion_obligations`) -> exit 0, asserting the extracted
    block between the "COMPANION OBLIGATIONS" heading and the next numbered
    step contains exactly 2 `->`/trigger bullet lines.

- Maps to: Requirement Verification bullet 2 (self-demonstration)
- Spec-AC-04: this scope's own prompt-corpus byte growth (the step-3a text
  added to `.aai/PLANNING.prompt.md`) is itself ledgered — a new
  `JUSTIFIED_ADDITIONS` entry referencing `planning-companion-obligations`
  exists in `tests/skills/lib/prompt-diet-ledger.sh`, `TEST-012`'s expected
  `JUSTIFIED_GROWTH_BYTES` literal in `tests/skills/test-aai-prompt-diet.sh`
  matches the new ledger sum, and both shared-ledger consumers stay green.
  - Verification: `bash tests/skills/test-aai-prompt-diet.sh` -> exit 0
    (TEST-010 byte floor + TEST-012 growth-sum match); `bash
    tests/skills/test-aai-verify-gate.sh` -> exit 0 (independent second
    consumer of the same shared ledger, TEST-006); `bash
    tests/skills/test-aai-layer-profiles.sh` -> exit 0 (regression guard:
    confirms no `.aai` file went unclassified even though this scope does
    not add one).

## Constitution deviations

None.

<!-- Art.1 evidence-before-claims: every Spec-AC is grep/exit-code
  measurable, no PASS claim in planning. Art.2 KISS/YAGNI: closed
  two-entry checklist, explicitly no new auto-detection script (that would
  be speculative scope). Art.3 portability: prose + a bash array append +
  a suite invocation, no new binary/service dependency. Art.4
  degrade-and-report: N/A — no new failure path is introduced (this scope
  adds documentation-time guidance, not a runtime guard). Art.5 additive:
  new PROCESS step + new ledger entry, no existing PLANNING step
  renumbered or removed, no existing ledger entry altered. Art.6
  single-writer: no STATE.yaml schema touched. Art.7 operator-only merge:
  N/A, no PR/merge-boundary change. -->

## Seam analysis

One seam: `tests/skills/lib/prompt-diet-ledger.sh` is a single-sourced
library (`JUSTIFIED_ADDITIONS`, `JUSTIFIED_GROWTH_BYTES`, and the two pure
helpers) consumed by TWO independent test files —
`tests/skills/test-aai-prompt-diet.sh` (TEST-010/012, this scope's own
self-dogfooding gate) and `tests/skills/test-aai-verify-gate.sh` (TEST-006) —
specifically so the two can never drift from each other (DEBT-0002 "two
copies of one gate" pattern, docs/knowledge/LEARNED.md 2026-07-17). This
scope WRITES one new array entry to that shared file. The seam is crossed by
an integration check rather than by asserting against only one consumer:
Spec-AC-04's Verification runs BOTH `test-aai-prompt-diet.sh` and
`test-aai-verify-gate.sh` against the real, single, post-edit ledger file —
proving the new entry produces the correct `JUSTIFIED_GROWTH_BYTES` for both
independent readers, not just the one this scope's own byte-floor cares
about.

No other seam: the new `.aai/PLANNING.prompt.md` checklist step is read only
by the LLM executing the Planning role at the next invocation — not by any
second machine-readable code path — so it carries no data-format seam of its
own (same conclusion SPEC-0070 reached for its SKILL_PR precondition text).

## Acceptance Criteria Status

| Spec-AC    | Description                                                              | Status  | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Checklist names trigger 1 (prompt-corpus growth) -> ledger companion/file | done    | test-aai-hygiene-pack.sh test_070 exit 0 (PLANNING step 3a names prompt corpus + JUSTIFIED_ADDITIONS + tests/skills/lib/prompt-diet-ledger.sh) | — | RED-proof: `grep -c "COMPANION OBLIGATIONS"` was 0 pre-edit |
| Spec-AC-02 | Checklist names trigger 2 (new .aai file) -> PROFILES companion/file      | done    | test-aai-hygiene-pack.sh test_070 exit 0 (block names `.aai/**` + classification + `.aai/system/PROFILES.yaml`) | — | RED-proof: `grep -c "PROFILES.yaml"` was 0 pre-edit |
| Spec-AC-03 | Checklist closed to exactly 2 entries, no auto-detection logic added     | done    | test-aai-hygiene-pack.sh test_070 exit 0 (extracted block has exactly 2 `->` trigger bullets; no script added) | — | — |
| Spec-AC-04 | Self-dogfooding: scope's own growth ledgered, shared suites green        | done    | prompt-diet TEST-010 net reduction 28672 (headroom 0/2048) + TEST-012 sum 20358; verify-gate TEST-006 credit=20358; layer-profiles exit 0 | — | 566 B corpus growth credited exactly (planning-companion-obligations ledger entry) |

## Implementation plan
- Components/modules affected: `.aai/PLANNING.prompt.md` (new step 3a, prose
  only); `tests/skills/lib/prompt-diet-ledger.sh` (one new
  `JUSTIFIED_ADDITIONS` array entry); `tests/skills/test-aai-prompt-diet.sh`
  (TEST-012's expected-sum literal + docstring bump); `tests/skills/test-aai-
  hygiene-pack.sh` (one new `test_070_companion_obligations` function,
  registered in `main()`).
- Data flow: none (no runtime code path; prompt prose read by the LLM at
  Planning time, ledger array summed by the existing bash loop in
  `prompt-diet-ledger.sh`).
- Edge cases: a scope that touches BOTH triggers simultaneously (adds prompt
  bytes AND a new `.aai/**` file) — the checklist's two bullets are
  independent and additive, so both companions apply; not specially tested
  here since the closed-list structure already makes each bullet
  independently gated. A scope that touches neither trigger — the checklist
  explicitly states "skip, no note required," so it imposes zero overhead on
  unrelated scopes (verified indirectly: TEST-003 asserts the block stays
  exactly 2 bullets, i.e., it cannot silently grow into a broader gate).

## Test Plan

| Test ID  | Spec-AC    | Type       | File path (expected)                          | Description                                                                                                                                                            | Status  |
|----------|------------|------------|------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit       | tests/skills/test-aai-hygiene-pack.sh           | `.aai/PLANNING.prompt.md` contains "COMPANION OBLIGATIONS" heading, positioned before the existing "4) Create or update docs/specs" line, naming prompt-corpus growth + `tests/skills/lib/prompt-diet-ledger.sh`. RED-proof: `grep -c "COMPANION OBLIGATIONS" .aai/PLANNING.prompt.md` = 0 today. | green |
| TEST-002 | Spec-AC-02 | unit       | tests/skills/test-aai-hygiene-pack.sh           | Same block names a new `.aai/**` file trigger + `.aai/system/PROFILES.yaml`. RED-proof: `grep -c "PROFILES.yaml" .aai/PLANNING.prompt.md` = 0 today.                    | green |
| TEST-003 | Spec-AC-03 | unit       | tests/skills/test-aai-hygiene-pack.sh           | The extracted "COMPANION OBLIGATIONS" block contains exactly 2 trigger bullets (no third entry, closed list). RED-proof: block does not exist today, so the extraction yields 0 (not 2).       | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-prompt-diet.sh, tests/skills/test-aai-verify-gate.sh, tests/skills/test-aai-layer-profiles.sh | Full run of all three suites exits 0 after the checklist + ledger true-up land — proving this scope's own prompt-corpus growth is correctly ledgered for both shared-ledger consumers, and no `.aai` file went unclassified. RED-proof: today the suites are green at 0 B headroom (`tests/skills/lib/prompt-diet-ledger.sh` last entry: "494 branch-per-work-item-hygiene ... 0 B headroom"); adding step 3a's bytes to `.aai/PLANNING.prompt.md` WITHOUT the matching ledger entry is observed to flip `test-aai-prompt-diet.sh` TEST-010 to FAIL (headroom goes negative) before the ledger entry is added. | green |

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- TEST-001/002/003 live in one new function, `test_070_companion_obligations`,
  in the existing `tests/skills/test-aai-hygiene-pack.sh` grep-wiring suite
  (bash-3.2 compatible, `set -euo pipefail`, no new fixtures/network needed —
  pure text assertions against tracked files), registered in that file's
  `main()` after `test_060_work_item_brief` (per the file's own increasing
  test-number convention).
- TEST-004 is the RED-proof for the self-dogfooding Spec-AC-04: because the
  ledger currently runs at 0 B headroom, Implementation will observe a real
  RED state (TEST-010 failing) the moment the checklist prose lands without
  a matching `JUSTIFIED_ADDITIONS` entry — this is a structural property of
  the shared ledger's current state, not a manufactured test double.
- Portability (docs/knowledge/LEARNED.md, 2026-07-19): the new test function
  uses only `grep`/`awk`/`wc` text assertions on tracked files — no
  `mktemp`, no `git init` fixture, so no additional portability surface is
  introduced beyond what `test-aai-hygiene-pack.sh` already requires.

## Verification
- `bash tests/skills/test-aai-hygiene-pack.sh` -> exit 0 (includes the new
  `test_070_companion_obligations`, TEST-001..003).
- `bash tests/skills/test-aai-prompt-diet.sh` -> exit 0 (TEST-004 half:
  byte-floor + growth-sum true-up).
- `bash tests/skills/test-aai-verify-gate.sh` -> exit 0 (TEST-004 half:
  second shared-ledger consumer).
- `bash tests/skills/test-aai-layer-profiles.sh` -> exit 0 (TEST-004 half:
  manifest-conformance regression guard).
- `.aai/scripts/aai-run-tests.sh` (or the project's full skills sweep) ->
  every suite that re-runs the byte floor (ceremony-levels, constitution,
  debug-gate, advisory-skills, delta-stage2 per LEARNED.md 2026-07-17) stays
  green — no suite-specific change needed there since they only re-consume
  the same shared ledger, already covered by TEST-004.
- Post-freeze advisory: `node .aai/scripts/spec-lint.mjs --path
  docs/specs/SPEC-0071-spec-planning-companion-obligations.md` (report-only).
- PASS criteria: all TEST-001..004 green; all Spec-AC in a terminal (`done`)
  status with non-empty evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: planning-companion-obligations (SPEC-000N at merge)
- Spec-AC and TEST-xxx links (Spec-AC-01/TEST-001, Spec-AC-02/TEST-002,
  Spec-AC-03/TEST-003, Spec-AC-04/TEST-004)
- command or review scope
- exit code or review verdict
- evidence path (loop-strategy evidence under docs/ai/tdd/ or the suite's own
  stdout capture; review under docs/ai/reviews/)
- commit SHA or diff range when available
