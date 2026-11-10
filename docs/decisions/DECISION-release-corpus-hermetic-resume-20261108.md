# Decision: Resume current-head measurement

Date: 2026-11-08
Blocking ref: release-corpus-hermetic
Decided by: human

## Question

Resume with an admissible quiet-window corpus using an isolated PowerShell cache, or explicitly sign a re-defer of SPEC-0257 Spec-AC-05 to 2026-11-22.

## Decision

Pokračuj

## Assumptions

Continue toward fresh verification and a reviewed PR. No re-defer, signature, evidence waiver, merge or release was authorized. This answer is not treated as a guarantee that foreign suites have stopped: observe the host before and after the corpus and wait for foreign suites to finish. Use private PowerShell caches. Main has advanced to c88cf708 (#541), which is integrated into the owned worktree with main-first ledger union; repeat verification affected by this changed release implementation. All historical measurements remain immutable.
