---
id: ps1-native-stderr-guard
number: 21
type: issue
status: draft
links:
  pr: []
  commits: []
---

# aai-release.ps1 `git push` trips NativeCommandError on Windows PowerShell 5.1

## Summary
- `.aai/scripts/aai-release.ps1` runs `git push` (and the surrounding `git
  add`/`commit`/`tag`) as native calls under `$ErrorActionPreference = 'Stop'`
  WITHOUT redirecting stderr. `git push` writes its normal progress ("To
  github.com…", object counts) to **stderr**; on Windows PowerShell 5.1 that
  stderr output is promoted to a terminating `NativeCommandError`, so the release
  CUT aborts **even though the push succeeded**. Same class as a downstream report
  where `aai-update.ps1`'s `git clone` failed identically (their copy predated the
  `*> $null` guard already on `main`).

## Type
- bug

## Impact
- `/aai-release --confirm` on Windows PowerShell 5.1 fails at the push step with a
  cryptic `NativeCommandError` after the local commit + annotated tag already
  exist — leaving a half-done release (tag created, push aborted) and no clear
  cause. Severity: medium — the release skill is documented to work "on any
  deployed project" including Windows; this path is in code shipped this session
  (CHANGE-0044/SPEC-0063). Also affects the tag push (line 264).

## Current Behavior
- `aai-release.ps1` top sets `$ErrorActionPreference = 'Stop'`. Lines ~263-264:
  `git -C $Root push origin $branch` / `git -C $Root push origin
  "refs/tags/$Version"` have no `2>`/`*>` redirect and no local EAP relaxation.
  On PS 5.1 the push's stderr progress → NativeCommandError → terminates the cut.
  (Lines 253-255 `git add`/`commit -q`/`tag -a` are quieter but share the same
  unguarded context.)

## Expected Behavior
- Native git/gh calls in `aai-release.ps1` do NOT abort on stderr-that-is-not-an-
  error; the cut fails ONLY on a genuine non-zero exit, and when it does it
  surfaces git's REAL error text (a real push failure — rejected, auth, network —
  must be diagnosable, not swallowed).

## Steps to Reproduce (if applicable)
1) On Windows PowerShell 5.1, in a repo with an `[unreleased]` CHANGELOG and a
   reachable remote, run `.aai/scripts/aai-release.ps1 --confirm`.
2) The local commit + tag are created, then the run aborts at `git push` with
   `NativeCommandError` citing git's normal "To <remote>…" stderr line.

## Verification
- `aai-release.ps1`'s native git/gh calls no longer abort on success-stderr under
  `$ErrorActionPreference = 'Stop'` (verified by the fix's structure — either a
  shared checked-invoke helper that runs with local `Continue` + gates on
  `$LASTEXITCODE`, or an equivalent that preserves diagnostics).
- A genuine non-zero git exit STILL fails the cut AND prints git's stderr (a
  diagnostics-preserving guard, NOT a blanket `*> $null` that hides real errors).
- `pwsh -NoProfile -Command "Invoke-Pester -Path tests/skills/aai-win-dispatch.Tests.ps1"`
  passes; the ps1-quality CI job (parse-check 5.1 + PSScriptAnalyzer + pwsh7
  Pester) stays green; `bash tests/skills/test-ps1-quality.sh` exits 0.

## Constraints / Risks
- **Verification limit (honest):** this defect is specific to Windows PowerShell
  5.1's native-stderr-as-error behavior. pwsh 7 does not reproduce it, and this
  repo's CI only PARSE-checks 5.1 (no 5.1 RUNTIME job). So automated coverage =
  parse + PSScriptAnalyzer + pwsh7 Pester + logic; the 5.1 runtime effect needs a
  DOCUMENTED MANUAL SMOKE on Windows PowerShell 5.1 (recorded as a residual risk,
  same posture as SPEC-0046's native-Windows manual-verified items).
- Prefer a DIAGNOSTICS-PRESERVING fix over `*> $null`: the rest of the ps1 family
  already uses `*> $null` (functional — it does not trip the bug — but it hides
  git's real error on genuine failure). For an OUTWARD-FACING push/publish, the
  operator must see a real failure's cause. A small shared "checked invoke" helper
  (local `$ErrorActionPreference='Continue'`, capture output, throw with stderr
  only on non-zero exit) is the robust option; scope it minimally.
- Out of scope: retro-fitting the whole ps1 family off `*> $null` — those calls
  work (they don't trip the bug); improving their diagnostics is a separate,
  lower-priority nicety. Fix the actual bug (aai-release push) cleanly; note the
  family-wide diagnostic-swallowing as a follow-up.
- Keep the PowerShell twin parseable on BOTH Windows PS 5.1 and pwsh 7 (the
  parse-check + ps1 gate CI jobs).
- No secret referenced — SECRETS PREFLIGHT skipped (`gh`/git read their own creds).

## Notes
- Downstream trigger: a stale vendored `aai-update.ps1` (clone fix `*> $null` is
  already on `main`, commit f13240f) — their immediate unblock is a one-time manual
  layer refresh, after which `/aai-update` works. THIS issue is the still-present
  sibling on the release path.
- Family audit (2026-07-22): every other native git/gh call in `.aai/scripts/*.ps1`
  already uses `*> $null`; `install-pre-commit-hook.ps1`'s git lines are bash
  here-string hook content, not PowerShell calls; `migrate-state-to-local.ps1`'s
  `git rm --cached … | Out-Null` is low-risk (rm writes to stdout). aai-release.ps1
  is the only outward-facing unguarded push.
