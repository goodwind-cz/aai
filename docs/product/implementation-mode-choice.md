---
id: implementation-mode-choice
type: product
capability: implementation-mode-choice
status: current
delivered_by:
  - CHANGE-DRAFT-implementation-mode-choice
spec: docs/specs/SPEC-DRAFT-spec-implementation-mode-choice.md
updated: 2026-07-31
---

# Choosing how much rigor an implementation gets

## What it does

At the end of every intake, AAI now **asks you how to implement** — with a
recommendation — instead of silently defaulting to the full TDD loop:

1. **Full TDD loop** — RED/GREEN ceremony, full evidence chain. For
   behavioral, multi-surface, or core/state/security changes.
2. **Direct + targeted tests** — implement first, then a few narrow
   regression tests. For small, single-surface, low-risk changes. Saves the
   bulk of the TDD loop's token cost.
3. **Direct without tests** — implement only, no test files. For tuning
   scripts, config knobs, run-scripts — the cases where generated tests are
   pure overhead. Requires a recorded rationale.

The recommendation is derived from stated signals (scope risk, surface count,
script-only vs behavioral). If you do not choose, nothing changes — the
planner decides exactly as before.

## How to use it

- Answer the intake's closing question ("Jak implementovat?") — or just say it
  up front in the intake text ("bez TDD, jen cílené testy"). Your words are
  recorded as the rationale.
- Change your mind later: Planning respects a recorded intake choice and will
  not override it without telling you.
- The chosen lane is visible in `docs/ai/STATE.yaml`
  (`implementation_strategy.selected` + `rationale`).

## Data model

- `implementation_strategy.selected` gains two values: `direct` and
  `untested` (alongside `loop`/`tdd`/`hybrid`/`undecided` — back-compatible).
- `untested` cannot be recorded without `--rationale` (the CLI exits 2 and
  writes nothing).

## Interfaces and contracts

- The cheap lane is **never self-selected by an agent**: only your intake
  choice (recorded with your words) or Planning with an explicit
  told-the-user clause can set it. Validation keys off the **recorded**
  strategy in STATE — an implementer who skips RED while the record says
  `tdd` still fails the evidence gate.
- Evidence demanded scales with the lane: `tdd`/`hybrid` unchanged (full
  RED-proof); `direct` = targeted-test exit codes; `untested` = the declared
  smoke/manual check plus the recorded rationale.
- The TDD lane is byte-for-byte unweakened — pinned by hostile-mutation
  tests.

## Limits and non-goals

- The recommendation is advisory prose, not a hard block — you may choose
  `untested` even where TDD is recommended (with a rationale on record).
- Automatic scope-size detection is out of scope (future work).

## Links

- Request: docs/issues/CHANGE-DRAFT-implementation-mode-choice.md
- Spec: docs/specs/SPEC-DRAFT-spec-implementation-mode-choice.md
