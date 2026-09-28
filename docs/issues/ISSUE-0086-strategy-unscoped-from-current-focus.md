---
id: strategy-unscoped-from-current-focus
type: issue
number: 86
status: draft
links:
  pr: []
  commits: []
---

# Issue — Global implementation_strategy can belong to a different work item than current_focus

## Summary
- `docs/ai/STATE.yaml` stores `implementation_strategy` as a single global block. `state.mjs set-strategy` writes `selected` / `source` / `rationale` without requiring or recording a `ref_id`.
- Observed pairing: `current_focus.ref_id` named `bezdinek-aggregation-block-failure` while `implementation_strategy.selected: untested` and its rationale belonged to a different item (`scada-history-chunk-import`).
- TDD preflight then judges the live scope by another item's strategy, which can force a full intake/TDD ceremony for a small edit of an already-open uncommitted scope.

## Type
- bug

## Impact
- Who/what is affected: any dispatch that reads `implementation_strategy` (TDD preflight, Validation, lane-gate strategy predicate) after `set-focus` without a matching `set-strategy`.
- Severity/priority: high — wrong rigor lane (tdd vs direct vs untested) and repeated ceremony the operator already asked not to rerun.

## Current Behavior
- `cmdSetStrategy` in `.aai/scripts/state.mjs` updates the global `implementation_strategy` block only. It does not take `--ref`, does not copy `current_focus.ref_id`, and does not refuse a write when strategy provenance disagrees with focus.
- `set-focus` retargets `current_focus` without clearing or rebinding `implementation_strategy` (siblings ISSUE-0069 / ISSUE-0040 covered stale `spec_path`, not strategy).
- Downstream observation (Windows working tree, 2026-09-24): focus on one feature, leftover `untested` rationale from another. TDD preflight treated the new scope as untested / forced a new ceremony. An explicit operator "do not repeat whole TDD" had to override it by hand.

## Expected Behavior
- `implementation_strategy` is bound to a work-item `ref_id` (stored with the strategy, or nested under that work item).
- `set-strategy` requires a `--ref` or derives it unambiguously from `current_focus.ref_id`.
- Writing a strategy whose `ref_id` disagrees with `current_focus` is refused (non-zero, named error).
- Readers (TDD preflight, Validation, lane-gate) ignore or refuse a strategy that does not match the live `current_focus.ref_id`.

## Steps to Reproduce (if applicable)
1. `state.mjs set-strategy --selected untested --source intake --rationale "belongs to item-A"`.
2. `state.mjs set-focus --ref item-B --type issue --path <item-B intake>` (or equivalent) without a new `set-strategy`.
3. Observe `current_focus.ref_id: item-B` still paired with item-A's `implementation_strategy`.
4. Invoke TDD / orchestration preflight against item-B and observe it consuming item-A's strategy.

## Verification
- Fixture: set strategy for ref A, retarget focus to ref B, `set-strategy` without `--ref` either binds B or refuses; TDD preflight does not apply A's `untested` to B.
- `set-strategy --ref A` while `current_focus` is B exits non-zero and names the mismatch.
- Existing `tests/skills/test-aai-state.sh` (and strategy-enum / untested-rationale pins) stay green.

## Constraints / Risks
- Known risks or constraints: CHANGE-0100 (`implementation-mode-choice`) and CHANGE-0107 (R-guard on strategy flips) assume a single global block. Binding strategy to `ref_id` must not silently drop the untested-rationale requirement or the R-guard watch. Do not invent a new STATE schema without Planning; the intake records the bug and the ownership invariant, not a frozen schema. Related "incremental fast path for a small uncommitted edit" and "operator skip-TDD wins over ceremony" are **out of this issue's primary scope** — see Notes.
- Secrets preflight results (if any secret referenced): none — no local secret is referenced.

## Notes
- Source: local Windows usage report 2026-09-24 (`internal/windows-usage-report.md` in the project store). Not previously filed upstream.
- Related done work that does **not** close this: ISSUE-0040 / ISSUE-0069 (stale `spec_path`), CHANGE-0100 (mode choice), CHANGE-0031 (dispatch after completed scope).
- Deferred from this bug (do not smuggle into the same ride unless Planning explicitly widens): a fast path for a small edit of the active uncommitted scope, and an operator instruction "do not repeat whole TDD" beating the recommended ceremony. Those are behavior/ceremony changes; file them as a CHANGE after this ownership bug if still needed.
- Assumption: `untested` in the observed STATE was leftover from a prior item, not an intentional operator choice for the live focus.
