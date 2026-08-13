---
id: canonical-test-invocation
number: 139
type: change
status: draft
user_visible: true
ceremony_level: 1
capability: windows-test-wrapper
---

# Change — canonical test-invocation contract: one allowlist-stable command shape, wrapper never bypassed

## Summary
- Owner field transcript 2026-08-13 (downstream Codex/Windows): the agent
  invoked tests as `& 'C:\Program Files\Git\bin\bash.exe'
  ..\..\.aai\scripts\aai-run-tests.sh ...` — bypassing the vendored ps1
  dispatcher entirely (no env canonicalization, no watchdog, no exit
  contract; run produced no output) AND re-triggering the approval dialog
  on every call despite the owner having allowlisted .aai scripts: the
  command SHAPE varies per call (CWD-relative ..\..\ paths, ad-hoc quoting,
  direct bash.exe), so no allowlist prefix can ever match it stably.
- Root gap: the vendored guidance nowhere states HOW tests must be invoked
  — the canonical shape is not a contract, so each downstream agent
  improvises one.

## Acceptance Criteria
- AC-001 (the contract): the authoritative vendored guidance (TECHNOLOGY
  contract and the agent-facing guidance surface Planning identifies)
  states ONE canonical invocation per platform, from repo root, verbatim:
  Windows `powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1
  <command...>`, POSIX `bash .aai/scripts/aai-run-tests.sh <command...>`;
  and states the prohibition: never invoke bash.exe/sh/wsl directly for
  test runs, never via CWD-relative paths from subdirectories — the
  dispatcher owns interpreter routing.
- AC-002 (allowlist stability): the same doc states the rationale in one
  sentence — the fixed repo-root literal prefix is what approval
  allowlists match — and docs/USER_GUIDE.md gains the operator-facing
  counterpart: allowlist exactly these two prefixes once.
- AC-003 (self-observability): aai-doctor reports whether the vendored
  guidance on THIS machine carries the canonical-invocation contract
  (a cheap content probe in an existing category or CAT-16 detail —
  Planning decides placement; SKIP/degrade semantics per the doctor
  conventions; no new exit codes).
- AC-004 (governance): if any .aai prompt-corpus byte changes, the
  prompt-diet ledger + TEST-012 checkpoint move accordingly (measured,
  not estimated); prefer non-prompt guidance surfaces where equal.
- AC-005: tests per conventions, RED-first for new contracts (doc pins +
  doctor probe fixtures); truthful product-doc updates; no behavior change
  in the wrapper itself.
