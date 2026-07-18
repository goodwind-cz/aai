---
id: spec-prompt-diet-itemized-growth-ledger
type: spec
number: 59
status: draft
ceremony_level: 1
links:
  requirement: CHANGE-0040
  rfc: null
  pr: []
  commits: []
---

# Spec: prompt-diet itemized justified-growth ledger (no magic-number bumps)

SPEC-FROZEN: true

Reserved display number (cross-branch collision check, RFC-0007): SPEC-0059.
Verified 2026-07-18 free across local `docs/specs/` (highest is SPEC-0058), every
`refs/aai/docnums/SPEC-*` reservation ref on `origin` (highest reserved
SPEC-0058), and the remote branch listing. The sequential integer is
minted/reserved at merge by `allocate-doc-number.mjs`; this file stays
`SPEC-DRAFT-<slug>.md` with `number: null` in-branch. The slug id is
`spec-`-prefixed (`spec-prompt-diet-itemized-growth-ledger`) per spec-lint's
`spec-id-shape` rule (SPEC-0058) so it can NEVER collide with the intake's id
(`prompt-diet-itemized-growth-ledger`).

Ceremony justification: single test-file change (`tests/skills/test-aai-prompt-diet.sh`)
— migrate an existing inline COMMENT ledger into a real bash array + portable
summation (behavior-preserving, sum stays 9239), improve one breach message, and
add regression stanzas. No engine/protected-path change: this test file is
verified NOT in `protected_paths_l3` (docs/ai/docs-audit.yaml — state engine,
allocator, guards, WORKFLOW.md, CONSTITUTION.md). Behavior-preserving, single
surface, reversible → L1 lean lane.

## Links
- Requirement: docs/issues/CHANGE-0040-prompt-diet-itemized-growth-ledger.md
- Origin: ISSUE-0016 process_finding (2026-07-18) — the recurring prompt-diet
  floor re-breach (main was red by 764 B until an ISSUE-0016 hygiene true-up).
  Completes the DEBT-0002 anti-bloat mechanism by making the credit
  auditable/self-documenting instead of a manually-bumped constant.
- Technology contract: docs/TECHNOLOGY.md (bash-3.2 test-suite floor; no
  `mapfile`, no `declare -A`, no bash-4+ features)

## Implementation strategy
- Strategy: tdd
- Rationale: this hardens a byte-budget anti-bloat guard that was silently
  breached twice this session; the change is behavior-preserving on the current
  corpus (sum MUST stay 9239) and adds new breach-message + cap-bite behavior.
  Every new stanza (array summation == 9239, deficit computation, paste-ready
  template, cap-bite proof) has a genuine RED state before the change — the
  array/helper/template do not exist yet, so the assertions fail under `set -u`
  / on absent output. RED-first is the discipline the recurring-breach motivation
  demands (regression proof, not a rubber-stamp).

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: one test file, low-risk, fully reversible, no protected
  surface; the operator-approved wave is already `inline`
  (STATE.worktree.user_decision: inline).
- User decision: inline
- Base ref: main
- Worktree branch/path: n/a (inline)
- Inline review scope: `tests/skills/test-aai-prompt-diet.sh`

## Acceptance Criteria Mapping

- Maps to: CHANGE-0040 AC-001
- Spec-AC-01: `JUSTIFIED_GROWTH_BYTES` is derived as the portable bash-3.2 sum of
  the leading `<bytes>` field of each `JUSTIFIED_ADDITIONS` array entry (no `bc`,
  no `mapfile`, no `declare -A` — a `for` loop over `${_entry%% *}` and `$(( ))`).
  The three entries migrated verbatim from the existing comment ledger
  (`6144 DEBT-0002`, `1309 CHANGE-0037`, `1786 CHANGE-0038+0039`) sum to EXACTLY
  9239; every entry carries `<bytes> <ref> <rationale>`. TEST-010 stays green with
  net reduction 29694 / headroom 1022/2048 (byte-identical credit to today).
  - Verification: `bash tests/skills/test-aai-prompt-diet.sh` → exit 0; the new
    summation stanza asserts `JUSTIFIED_GROWTH_BYTES == 9239` and that it equals a
    re-sum of `JUSTIFIED_ADDITIONS`; TEST-010 line reports `headroom 1022/2048`.

- Maps to: CHANGE-0040 AC-002 (breach half)
- Spec-AC-02: on a floor breach (`reduction < REQUIRED_REDUCTION_BYTES`), the
  TEST-010 failure output computes the exact deficit
  (`deficit = REQUIRED_REDUCTION_BYTES - reduction`, a positive integer that
  restores headroom to 0) and prints a ready-to-paste ledger entry of the frozen
  shape `JUSTIFIED_ADDITIONS+=( "<deficit> <REF-ID> <rationale>" )` with
  `<deficit>` substituted by the computed integer. The anti-bloat headroom-cap
  guard (`0 <= headroom <= HEADROOM_CAP`) is UNCHANGED and still fails an
  over-padded array (headroom > CAP).
  - Verification: `bash tests/skills/test-aai-prompt-diet.sh` → exit 0; the new
    synthetic-input stanzas assert (a) a shrunk/under-credited synthetic input
    prints a line containing `JUSTIFIED_ADDITIONS+=( "` and the correct deficit
    integer, and (b) an over-padded synthetic credit is detected as
    `headroom > HEADROOM_CAP`.

- Maps to: CHANGE-0040 AC-002 (regression + seam half)
- Spec-AC-03: existing prompt-diet stanzas TEST-001..009 and TEST-011 remain
  unedited and green; `BASELINE_PROMPT_BYTES`, `REQUIRED_REDUCTION_BYTES`, and
  `HEADROOM_CAP` literals are untouched; the ceremony-levels seam
  (`tests/skills/test-aai-ceremony-levels.sh`, whose TEST-010 re-runs prompt-diet
  end-to-end) stays green.
  - Verification: `bash tests/skills/test-aai-prompt-diet.sh` → exit 0 (11+
    stanzas pass); `grep -E '^(BASELINE_PROMPT_BYTES=357457|REQUIRED_REDUCTION_BYTES=28672|HEADROOM_CAP=2048)$' tests/skills/test-aai-prompt-diet.sh`
    → 3 matches; `bash tests/skills/test-aai-ceremony-levels.sh` → exit 0.

## Constitution deviations

None. (Single test-file change; no article of docs/CONSTITUTION.md is touched —
no engine/state/schema/protected-surface change, behavior-preserving on the
current corpus.)

## Acceptance Criteria Status

| Spec-AC    | Description                                             | Status   | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------|----------|----------|-----------|-------|
| Spec-AC-01 | array + portable bash-3.2 summation, sum == 9239         | done     | docs/ai/tdd/red-20260718T181000Z.log, docs/ai/tdd/green-20260718T181107Z.log; `bash tests/skills/test-aai-prompt-diet.sh` exit 0, TEST-012/TEST-013 pass, TEST-010 headroom 1022/2048 | —         | —     |
| Spec-AC-02 | breach prints deficit + paste-ready entry; cap still bites | done     | docs/ai/tdd/red-20260718T181000Z.log, docs/ai/tdd/green-20260718T181107Z.log; TEST-014 (synthetic deficit=1234) + TEST-015 (synthetic headroom 2049 > cap 2048) pass; real `headroom > HEADROOM_CAP` branch text byte-unchanged | —         | —     |
| Spec-AC-03 | TEST-001..009/011 + BASELINE/REQUIRED/CAP + seam green   | done  | `bash tests/skills/test-aai-prompt-diet.sh` exit 0 (all 15 stanzas, incl. TEST-001..009/011 unedited+green); BASELINE_PROMPT_BYTES=357457 / REQUIRED_REDUCTION_BYTES=28672 / HEADROOM_CAP=2048 lines present byte-identical | 2026-08-01 | `tests/skills/test-aai-ceremony-levels.sh` (the seam, TEST-006) is currently RED for a reason outside this scope: its own `test_016_misuse_guard_survival` fixture id `fixture-lean-doc` trips the newer spec-lint `spec-id-shape` rule (merged separately, PR #111), aborting the suite under `set -euo pipefail` before it reaches `test_010_seam_survival` (which re-runs prompt-diet). Reproduced byte-identically on HEAD before any SPEC-0059 edit — not introduced by this change, and out of this spec's single-file scope (`tests/skills/test-aai-prompt-diet.sh`). Needs a separate fix/waiver for the ceremony-levels fixture. |

## Implementation plan
- Components/modules affected: `tests/skills/test-aai-prompt-diet.sh` only.
- Migration (Spec-AC-01): replace the `JUSTIFIED_GROWTH_BYTES=9239` literal (and
  keep the itemizing prose it summarizes) with:
  ```
  JUSTIFIED_ADDITIONS=(
    "6144 DEBT-0002 <rationale>"
    "1309 CHANGE-0037 <rationale>"
    "1786 CHANGE-0038+0039 <rationale>"
  )
  JUSTIFIED_GROWTH_BYTES=0
  for _entry in "${JUSTIFIED_ADDITIONS[@]}"; do
    JUSTIFIED_GROWTH_BYTES=$(( JUSTIFIED_GROWTH_BYTES + ${_entry%% *} ))
  done
  ```
  `${_entry%% *}` (leading field) + `$(( ))` is bash-3.2 portable across the
  Windows/Git-Bash matrix. Rationales are carried in-array (each entry is
  self-documenting); the existing prose comment block may be trimmed to point at
  the array as the source of truth.
- Breach message (Spec-AC-02): in the `headroom < 0` branch of TEST-010, compute
  `deficit=$((REQUIRED_REDUCTION_BYTES - reduction))` and additionally
  `log_info` a paste-ready line `  JUSTIFIED_ADDITIONS+=( "$deficit <REF-ID> <rationale>" )`.
  The `headroom > HEADROOM_CAP` branch (anti-bloat cap) is left UNCHANGED.
- Testability (Spec-AC-02): factor the reduction/headroom/deficit-and-message
  evaluation so the new stanzas can drive it with SYNTHETIC `after/extra/credit`
  inputs (mirrors TEST-011's synthetic-fixture "the guard must actually bite"
  pattern) — proving both the deficit template and the cap-bite WITHOUT mutating
  the real ledger. Exact factoring (helper function vs. inline re-derivation) is
  an implementation choice; the frozen contract is the array format, the portable
  summation, the deficit formula, and the `JUSTIFIED_ADDITIONS+=( "` template shape.
- Edge cases: deficit is always a positive integer on breach (reduction <
  REQUIRED); the template restores headroom to exactly 0 (inside the cap). Empty
  or malformed array entries are out of scope (the three entries are fixed data).

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                   | Description                                                                                 | Status  |
|----------|------------|------|----------------------------------------|---------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-prompt-diet.sh   | `JUSTIFIED_GROWTH_BYTES == 9239` AND equals an independent re-sum of `JUSTIFIED_ADDITIONS`   | green |
| TEST-002 | Spec-AC-01 | unit | tests/skills/test-aai-prompt-diet.sh   | array has ≥3 entries; each is `<numeric-bytes> <ref> <rationale>` (leading field numeric)     | green |
| TEST-003 | Spec-AC-02 | unit | tests/skills/test-aai-prompt-diet.sh   | synthetic breach input prints `JUSTIFIED_ADDITIONS+=( "` with the correct computed deficit    | green |
| TEST-004 | Spec-AC-02 | unit | tests/skills/test-aai-prompt-diet.sh   | synthetic over-padded credit is detected as `headroom > HEADROOM_CAP` (cap still bites)        | green |
| TEST-005 | Spec-AC-03 | unit | tests/skills/test-aai-prompt-diet.sh   | full suite exit 0; TEST-010 `headroom 1022/2048`; BASELINE/REQUIRED/CAP literals unchanged     | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-ceremony-levels.sh | ceremony-levels suite exit 0 — its TEST-010 re-runs prompt-diet end-to-end (crosses the seam) | done |

RED-proof obligation (regardless of strategy): TEST-001..004 gate NEW behavior
and each has a real RED state before the change — `JUSTIFIED_ADDITIONS` is unbound
(fails under `set -u`), the re-sum/entry-shape assertions have nothing to read,
and the paste-ready template / cap-bite helper output does not yet exist. TEST-005
and TEST-006 are behavior-preserving regression/seam guards (green-stays-green):
they cannot go RED without the change because they assert the current behavior is
preserved — their signal is "the migration broke nothing."

### Seam analysis
- SEAM: `tests/skills/test-aai-ceremony-levels.sh` TEST-010 invokes
  `bash tests/skills/test-aai-prompt-diet.sh` end-to-end (a consumer this change
  does not own). Covered by TEST-006, a real integration run of the ceremony
  suite (not a mocked boundary). No other feature reads `JUSTIFIED_ADDITIONS` /
  `JUSTIFIED_GROWTH_BYTES` — they are file-local to the prompt-diet suite.

## Verification
- `bash tests/skills/test-aai-prompt-diet.sh` → exit 0; TEST-010 reports
  `net reduction 29694 bytes (headroom 1022/2048)`.
- `bash tests/skills/test-aai-ceremony-levels.sh` → exit 0 (seam).
- `grep -E '^(BASELINE_PROMPT_BYTES=357457|REQUIRED_REDUCTION_BYTES=28672|HEADROOM_CAP=2048)$' tests/skills/test-aai-prompt-diet.sh`
  → exactly 3 matches (untouched literals).
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, TDD, validation, and code review artifact, record:
- ref_id: prompt-diet-itemized-growth-ledger (CHANGE-0040)
- Spec-AC and TEST-xxx links
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
