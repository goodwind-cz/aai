---
id: spec-effort-direct-append
type: spec
number: 294
status: done
frozen_sha256: e9011edfc40ed45a519682add4d03960f68b66fc9c40f7f1280fd2f5269396d3
mutation_gate: v1
ceremony_level: 3
links:
  requirement: effort-direct-append
  rfc: null
  pr: []
  commits: []
---

# A directly executed role records how its effort was applied, and the effort report keeps it apart from history

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-0117-effort-direct-append.md (follow-up
  `fu-effort-direct-append-telemetry`, P2, source PR #552 Codex P2).
- Prior scope this one extends (closed, not edited):
  docs/specs/SPEC-0288-spec-model-effort-routing.md, D-RECORD (the
  `effort_applied` value set) and D-REPORT (the `--by-effort` table).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib, bash 3.2 suites
  through `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: each rule is a closed value set, a fixed table or a fixed canon
  line, and each can be seen failing on the unchanged tree: `--effort-applied
  direct` exits 2 today, the report has no applied column, and the
  ROLE_COMMON command writes no effort field. The intake's tdd note is an
  autopilot recommendation, not a recorded user choice.

## Isolation and review

- Worktree recommendation: required (ceremony L3)
- Worktree rationale: `.aai/scripts/state.mjs` is in `protected_paths_l3`;
  the main checkout is shared and holds uncommitted files owned by others.
- User decision: worktree (owner-directed in the session brief of
  2026-11-15, recorded in STATE before Planning)
- Base ref: origin/main at 16773cdf
- Worktree branch/path: fix/effort-direct-append at
  /Users/ales/Projects/aai-worktrees/effort-direct-append
- Review required: true (L3: mandatory, most capable tier)
- Review scope (explicit paths): .aai/scripts/state.mjs;
  .aai/scripts/metrics-report.mjs; .aai/ROLE_COMMON.md;
  .aai/SKILL_LOOP.prompt.md; tests/skills/test-aai-model-effort.sh;
  tests/skills/suite-map.yaml; tests/skills/lib/prompt-diet-ledger.sh;
  tests/skills/test-aai-prompt-diet.sh; tests/skills/test-aai-pr-preflight.sh;
  docs/product/telemetry.md; CHANGELOG.md;
  docs/issues/ISSUE-0117-effort-direct-append.md; this spec.

## Ceremony

Ceremony level 3. The scope edits `.aai/scripts/state.mjs` (the
`effort_applied` value set), which `protected_paths_l3` in
docs/ai/docs-audit.yaml lists. L3 brings the recorded worktree decision
(done), mandatory review on the most capable tier and an operator checkpoint
before merge. Round cap: two rounds, one full sweep before close.

Companion obligations: `.aai/ROLE_COMMON.md` and `.aai/SKILL_LOOP.prompt.md`
gain bytes, so the prompt-diet ledger true-up applies (a
`JUSTIFIED_ADDITIONS` entry in tests/skills/lib/prompt-diet-ledger.sh, the
TEST-012 pin in tests/skills/test-aai-prompt-diet.sh and the credit sum
pinned in tests/skills/test-aai-pr-preflight.sh, if that suite pins it). No new
`.aai/**` file, so PROFILES.yaml does not change. ORCHESTRATION.prompt.md is
not edited.

## Decisions

### D1. One new value, `direct`

- `EFFORT_APPLIED_VALUES` in state.mjs becomes `param`, `not_supported`,
  `overridden`, `direct`. `direct` means: the role ran in the orchestrating
  (or operator's) session, not as a dispatched subagent, so no per-dispatch
  effort knob was used and the run inherited the session's effort.
- An out-of-set value still exits 2 and writes nothing (SPEC-0288 D-RECORD).
- `metrics-flush.mjs` already copies any `effort_applied` string; it is not
  edited.
- Why not reuse `not_supported`: `not_supported` says the harness or session
  had no knob for a dispatch; a direct run had no dispatch. Keeping them
  apart lets the owner drop either from the comparison.

### D2. The shared direct append carries the fields (Planning's choice)

The canonical command in `.aai/ROLE_COMMON.md` METRICS is the direct
execution path only (its subagent carve-out forbids self-append when
dispatched). It gains `--effort-applied direct` (always) and
`[--requested-effort <the dispatch's suggested_effort>]` (when the dispatch
named a non-null one). One sentence states both.

`.aai/SKILL_LOOP.prompt.md` step 4's recording line adds `direct` to its
value list, for a role the loop executes in its own session and appends for
(the no-subagent fallback, roles without a ROLE_COMMON pointer).

Rejected: having the loop own every append. It would move the direct run's
append out of the five role prompts into the loop, and a role prompt run by
hand outside the loop would then record nothing. The chosen option changes
two lines of canon.

### D3. The report gains an `applied` column

- `metrics-report --by-effort` groups runs by role, requested effort and
  applied (`effort_applied`, `unset` when absent). The table gains an
  `applied` column after `effort`. Rows sort by role, then effort (low,
  medium, high, unset), then applied (param, overridden, not_supported,
  direct, unset).
- History recorded before SPEC-0288 has neither field and reads
  `unset | unset` (effort, applied). A direct or not-supported run with no
  requested effort reads `unset` effort with its own applied value, so it no
  longer shares a row with history.
- The Before and From tables of `--split` carry the same column. The Delta
  table is unchanged (per-role medians).
- The default report (without `--by-effort`) is unchanged.
- This changes the SPEC-0288 D-REPORT table shape; TEST-3640's expected
  tables are updated in this scope and the change is disclosed in the
  CHANGELOG entry.

### D4. History stays as it is

Nothing rewrites `docs/ai/METRICS.jsonl` or STATE. Runs without the fields
keep reading `unset`.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN state.mjs append-run runs with --effort-applied direct and --requested-effort high it SHALL exit 0 and the run SHALL carry effort_applied direct and requested_effort high; metrics-flush SHALL carry both into the METRICS line; WHEN it runs with --effort-applied direct alone the run SHALL carry effort_applied direct and no requested_effort; an out-of-set --effort-applied SHALL still exit 2 with STATE unchanged | done | TEST-3790 PASS docs/ai/tdd/effort-direct-append/green-test-aai-model-effort.sh.log, mutation docs/ai/tdd/spec-effort-direct-append/mutation-TEST-3790.txt | — | D1 |
| Spec-AC-02 | WHEN metrics-report --by-effort reads a ledger holding a history run with no effort fields, runs with effort_applied param, not_supported and direct at requested_effort high, and a direct run and a not_supported run with no requested_effort, it SHALL print exactly the D3 table with an applied column, one row per role, effort and applied, the history run alone in the row with effort unset and applied unset; --split SHALL print the same column in its Before and From tables; a ledger with no effort fields at all SHALL print only rows with applied unset | done | TEST-3791 PASS docs/ai/tdd/effort-direct-append/green-test-aai-model-effort.sh.log, mutation docs/ai/tdd/spec-effort-direct-append/mutation-TEST-3791.txt | — | D3, D4 |
| Spec-AC-03 | the .aai/ROLE_COMMON.md METRICS append-run command SHALL carry --effort-applied direct and an optional --requested-effort; WHEN that command is run with its placeholders filled (requested effort high) against a fixture STATE and the item is flushed, the METRICS run SHALL carry effort_applied direct and requested_effort high and --by-effort SHALL print a row for that role with effort high and applied direct; SKILL_LOOP step 4 SHALL name direct in its effort-applied values; the prompt-diet ledger SHALL credit the measured growth and test-aai-prompt-diet.sh SHALL pass | done | TEST-3792 PASS docs/ai/tdd/effort-direct-append/green-test-aai-model-effort.sh.log, mutation docs/ai/tdd/spec-effort-direct-append/mutation-TEST-3792.txt; test-aai-prompt-diet.sh green docs/ai/tdd/effort-direct-append/green-test-aai-prompt-diet.sh.log | — | D2; seam canon line to state.mjs to flush to report |
| Spec-AC-04 | docs/product/telemetry.md SHALL name effort_applied direct and the applied column of --by-effort; CHANGELOG.md SHALL hold exactly one per-entry heading for this fix in the form unreleased or a rolled vYYYY.MM.DD, then an em dash and fix, naming direct | done | TEST-3793 PASS docs/ai/tdd/effort-direct-append/green-test-aai-model-effort.sh.log, mutation docs/ai/tdd/spec-effort-direct-append/mutation-TEST-3793.txt | — | Consumer-visible |

## Implementation plan

Components:
- `.aai/scripts/state.mjs`: `EFFORT_APPLIED_VALUES` gains `direct`; the
  D-RECORD comment names it. Nothing else.
- `.aai/scripts/metrics-report.mjs`: `appliedOf`, `APPLIED_ORDER`, a
  `groupKey` over role, effort and applied, the header and divider with the
  `applied` column, the sort, the row.
- `.aai/ROLE_COMMON.md`: D2 command and one sentence.
- `.aai/SKILL_LOOP.prompt.md`: step 4 value list.
- Tests in `tests/skills/test-aai-model-effort.sh`; TEST-3640 expected
  tables and the TEST-3642 SKILL_LOOP pin updated; suite-map
  `aai-model-effort` globs gain `.aai/ROLE_COMMON.md`.
- Prompt-diet true-up, `docs/product/telemetry.md`, `CHANGELOG.md`.

Planned anchor lines (the Test Plan mutations target them; TDD may re-anchor
a mutation to the code it writes, disclosed as a measurement amendment):
- state.mjs: `const EFFORT_APPLIED_VALUES = ['param', 'not_supported', 'overridden', 'direct'];`
- metrics-report: `const groupKey = r => [roleBase(r), effortOf(r), appliedOf(r)].join('\u0000');`
- ROLE_COMMON: `--verdict <pass|fail|none> --effort-applied direct \`

Seams crossed (each by a real producer and a real reader):
- state.mjs append-run (producer) to metrics-flush and the METRICS line
  (reader): TEST-3790.
- METRICS line shape (producer: a fixture in the flushed shape) to the
  report (reader): TEST-3791.
- The canon command text (producer) to a real state.mjs run, flush and
  report (reader): TEST-3792 extracts and runs the command.
- Not crossed by a test: whether an agent executing a role directly actually
  follows the canon line (R1).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3790 | Spec-AC-01 | integration | tests/skills/test-aai-model-effort.sh | append-run with --effort-applied direct --requested-effort high, then a Planning run with --effort-applied direct only: both exit 0; flush; the METRICS runs carry direct with high and direct with no requested_effort; --effort-applied maybe exits 2 with STATE unchanged | target `.aai/scripts/state.mjs`; `sed:s/'overridden', 'direct'\]/'overridden']/` refuses direct and the case must fail | green |
| TEST-3791 | Spec-AC-02 | integration | tests/skills/test-aai-model-effort.sh | a fixture ledger with history, param, not_supported and direct runs at high and a direct and a not_supported run without requested effort: --by-effort prints the exact table with the applied column; --split prints it in Before and From; a ledger without effort fields prints applied unset only; TEST-3640's tables are updated to the new shape | target `.aai/scripts/metrics-report.mjs`; `sed:s/, appliedOf\(r\)\]\.join/].join/` merges applied values into one row and the case must fail | green |
| TEST-3792 | Spec-AC-03 | integration | tests/skills/test-aai-model-effort.sh | extract the ROLE_COMMON append-run command, fill its placeholders (role Remediation, requested effort high, optional note dropped), run it against a fixture STATE, flush, report: the run carries direct and high and --by-effort prints the Remediation high direct row; SKILL_LOOP step 4 names direct; test-aai-prompt-diet.sh TEST-010 and TEST-012 pass | target `.aai/ROLE_COMMON.md`; `sed:s/ --effort-applied direct//` drops the flag, the run has no effort_applied and the case must fail | green |
| TEST-3793 | Spec-AC-04 | unit | tests/skills/test-aai-model-effort.sh | CHANGELOG.md holds exactly one unreleased or vYYYY.MM.DD heading with an em dash and fix naming effort_applied direct; docs/product/telemetry.md names effort_applied direct and the applied column | target `CHANGELOG.md`; `sed:s/— fix: a directly executed role/— fix: x/` removes the named heading and the case must fail | green |

## Verification

All runs: `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh <cmd>`
from the worktree root; new test code must pass under the suite's
`set -euo pipefail` (no `printf | grep -q`; use qgrep).

1. RED before GREEN: `docs/ai/tdd/effort-direct-append/red-*.log` and
   `green-*.log`. RED for TEST-3790 is `invalid --effort-applied "direct"`
   (exit 2); RED for TEST-3791 is the table without the applied column; RED
   for TEST-3792 is a run with no effort_applied.
2. `bash tests/skills/test-aai-model-effort.sh`, `test-aai-prompt-diet.sh`,
   `test-aai-pr-preflight.sh` exit 0, plus the CORE set.
3. Mutation records for TEST-3790..3793 under
   `docs/ai/tdd/spec-effort-direct-append/` via `mutation-run.mjs`.
4. One full sweep before close with `AAI_TEST_TIMEOUT=4500`.
5. PASS criteria: every TEST row green, every Spec-AC done with evidence, CI
   green on the PR head.

## Evidence contract

Each artifact records ref_id effort-direct-append, its Spec-AC and TEST links,
the command, the exit code and the evidence path, plus the commit SHA once
one exists. RED and GREEN logs under docs/ai/tdd/effort-direct-append/,
mutation records under docs/ai/tdd/spec-effort-direct-append/.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Out of scope

- Rewriting or back-filling history: pre-feature runs stay `unset` (D4).
- Making `--effort-applied` mandatory on append-run: a consumer on an older
  canon would start failing role appends; a guard here would be a separate
  scope.
- The Delta table of `--split` (per-role medians over all runs): unchanged.
- `fu-effort-gain-remeasure`: the measurement itself stays open.

## Registry items closed by this scope

`fu-effort-direct-append-telemetry` (P2): closed by Spec-AC-01..03. Checked
`node .aai/scripts/follow-ups.mjs list` (345 open); the other open
model-effort-routing items (digest, cursor params, spec_path, override noise,
flush regenerating the overview, the remeasure) are different subjects.

## Residual risks

- R1. A role run directly still depends on the agent following the canon
  line; a run that omits it reads `unset`, as today. No test can make an agent
  obey prose.
- R2. Runs recorded between SPEC-0288 and this fix by direct execution stay
  `unset` and keep sharing the history row.
