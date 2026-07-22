---
id: spec-ps1-native-stderr-guard
type: spec
number: 67
status: done
ceremony_level: 2
links:
  issue: ps1-native-stderr-guard
  rfc: null
  pr:
    - 125
  commits:
    - 81ed35dd5dbc1ca68440158d8754852400cefc1c
---

# SPEC — aai-release.ps1 native git/gh stderr guard (diagnostics-preserving)

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0021-ps1-native-stderr-guard.md (issue, ref_id `ps1-native-stderr-guard`)
- Related prior art: SPEC-0046 (Windows fallback — manual-verified residual-risk posture this spec mirrors); CHANGE-0044/SPEC-0063 (the aai-release skill that shipped this path); commit f13240f (the `*> $null` clone fix already on main in the sibling `aai-update.ps1`)
- Technology contract: docs/TECHNOLOGY.md

## Ceremony level

`ceremony_level: 2` (full pipeline). Honest reasoning:
- NOT level 1: although the primary code surface is one file, the scope is more
  than a trivial single-surface tweak — it changes the runtime behavior of an
  OUTWARD-FACING release/publish path, adds a new helper + a structural
  dot-source guard, adds a Pester unit + static contract tests, and carries a
  documented MANUAL-verification residual risk (the real Windows PowerShell 5.1
  effect is not reproducible in CI). `code_review.required: true`.
- NOT level 3: no path in `protected_paths_l3` (docs/ai/docs-audit.yaml — state
  engine, state-core, allocator, pre-commit guards, WORKFLOW.md, CONSTITUTION.md)
  is touched. The edited files — `.aai/scripts/aai-release.ps1`,
  `tests/skills/aai-win-dispatch.Tests.ps1` — are not protected surfaces.

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD for the helper's behavioral contract (TEST-002, TEST-003) and
  the dot-source guard (TEST-006) — genuinely RED-provable on this host (the
  helper does not exist yet; dot-sourcing today runs the whole script). Loop for
  the mechanical parts: swapping the cut-path call sites onto the helper, the
  static/grep contract assertions (TEST-001, TEST-004), the plan-mode regression
  smoke (TEST-007), and the parse/analyzer gate wiring (TEST-005, already
  auto-globbed).

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: two files, additive helper + a local structural wrap, no
  protected path, low blast radius. The operator branch
  `fix/ps1-native-stderr-guard` already exists (current HEAD) — inline is the
  effective mode; no worktree required.
- User decision: inline (branch already checked out)
- Base ref: main
- Worktree branch/path: fix/ps1-native-stderr-guard (inline; not a worktree)
- Inline review scope: see `## Code review scope`

## Code review scope
- code_review.required: true (runtime behavior change on the release/publish path)
- Explicit paths (inline review):
  - .aai/scripts/aai-release.ps1
  - tests/skills/aai-win-dispatch.Tests.ps1
  - docs/specs/SPEC-0067-spec-ps1-native-stderr-guard.md

## Testability constraint (shapes this whole plan)

This host is macOS with pwsh 7; the defect is SPECIFIC to Windows PowerShell
5.1, where a native command's success-stderr under `$ErrorActionPreference =
'Stop'` is promoted to a terminating `NativeCommandError`. pwsh 7 does NOT
reproduce that promotion, and this repo has NO Windows-PowerShell-5.1 RUNTIME
CI job (only a PARSE-check under 5.1). Therefore the Test Plan is split honestly:

- PROVABLE HERE (pwsh 7 + Linux CI): the helper's LOGIC — that it localizes
  `$ErrorActionPreference` to `Continue`, gates on `$LASTEXITCODE`, throws WITH
  the captured stderr ONLY on non-zero exit, and never throws on a zero exit
  regardless of stderr; the dot-source guard; the static call-site contract;
  parse-check under both editions; PSScriptAnalyzer 5.1/7.0 syntax compat.
- CANNOT VERIFY ON THIS HOST (recorded, never claimed): the actual Windows
  PowerShell 5.1 stderr-promotion SUPPRESSION — i.e. that a real `git push`
  writing "To github.com…" to stderr no longer aborts the cut. This is the
  automatable proxy's blind spot; it is covered by the manual smoke MV-1/MV-2
  and remains explicit residual risk RR-1 until an operator run is recorded.
  No PASS claim in this repo asserts the 5.1-runtime fix (CLAUDE.md /
  Constitution Article 1: evidence before claims).

## Acceptance Criteria Mapping

Requirement AC (issue "Verification"/"Expected Behavior") -> Spec-AC -> verification:

1. "Native git/gh calls no longer abort on success-stderr under EAP=Stop …
   diagnostics-preserving guard, NOT a blanket `*> $null`" -> Spec-AC-01
   (helper contract) + Spec-AC-02 (all cut-path calls routed through it) ->
   TEST-001..005 + manual MV-1/MV-2.
2. "A genuine non-zero git exit STILL fails the cut AND prints git's stderr"
   -> Spec-AC-01 -> TEST-003 (throw carries the stderr text).
3. "Pester passes; ps1-quality CI stays green; test-ps1-quality.sh exits 0" ->
   Spec-AC-02 (parse/analyzer/Pester gate) -> TEST-005, plus all Pester rows.
4. Structural requirement enabling the unit test (dot-sourceable without a
   release side effect; `-File`/plan behavior unchanged) -> Spec-AC-03 ->
   TEST-006, TEST-007.

## Spec Acceptance Criteria (verifiable statements)

- Spec-AC-01 — Diagnostics-preserving checked-invoke helper.
  `.aai/scripts/aai-release.ps1` defines a function `Invoke-NativeChecked` that:
  (a) sets a LOCAL `$ErrorActionPreference = 'Continue'` for the duration of the
  native call (so a native command's success-stderr is never promoted to a
  terminating error under the script's outer `Stop`); (b) invokes the named
  executable with its arguments capturing MERGED output (`2>&1`); (c) on
  `$LASTEXITCODE -eq 0` returns the captured output and NEVER throws, regardless
  of whether the command wrote to stderr; (d) on `$LASTEXITCODE -ne 0` throws a
  terminating error whose message CONTAINS the captured stderr/output text, so a
  real failure (rejected push, auth, network) fails loudly WITH git's own
  diagnostic — never a blanket `*> $null` that hides it.
  Verification: grep TEST-001 (function defined + local `='Continue'` present);
  Pester TEST-002 (stub: stderr + exit 0 -> no throw, returns); Pester TEST-003
  (stub: stderr + exit 1 -> throws AND message contains the stderr text).

- Spec-AC-02 — All cut-path native git/gh calls route through the helper; probes
  untouched; parse-clean both editions. Every native call in the CONFIRM cut
  sequence — `git add`, `git commit`, `git tag`, the display
  `git rev-parse --short HEAD`, `git push origin <branch>`,
  `git push origin refs/tags/<version>`, `gh release create` — is invoked via
  `Invoke-NativeChecked`; NO bare/unguarded native git or gh statement remains in
  the cut path. The intentionally-tolerant preconditions/probes that read
  `$LASTEXITCODE` themselves — `git rev-parse -q --verify` (tag-exists),
  `gh auth status`, `git rev-parse --abbrev-ref HEAD`, and the precondition
  `git rev-parse --show-toplevel` / `git status --porcelain` — KEEP their
  existing `*> $null` / `2>$null` handling and are explicitly OUT of scope
  (they work; they must still tolerate non-zero). The file parses cleanly under
  BOTH Windows PowerShell 5.1 and pwsh 7 and passes PSScriptAnalyzer 5.1/7.0.
  Verification: grep TEST-004 (no bare `git -C $Root push|add|commit|tag` and no
  bare `gh release create` statement; each cut op appears as an
  `Invoke-NativeChecked` argument; the two probes retain `*> $null`); TEST-005
  (`bash tests/skills/test-ps1-quality.sh` exit 0 locally; the ps1-quality CI
  gate — parse under real 5.1 + pwsh 7, PSScriptAnalyzer, Pester — is
  authoritative).

- Spec-AC-03 — Dot-sourceable for unit test; `-File`/plan behavior unchanged.
  `aai-release.ps1` guards its executable body (arg-parse + the cut try/finally)
  behind `if ($MyInvocation.InvocationName -ne '.')` so that DOT-SOURCING the
  file (`. $path`) defines `Invoke-NativeChecked` (and any other functions)
  WITHOUT performing arg parsing or a release; direct/`pwsh -File` invocation
  runs Main exactly as before (same flags, exit codes, plan/cut output). This
  mirrors the proven pattern in `aai-run-tests.ps1` / `aai-reap-tests.ps1`.
  Verification: Pester TEST-006 (after `. $release`, `Get-Command
  Invoke-NativeChecked` succeeds and no commit/tag/exit side effect occurred);
  Pester TEST-007 (`pwsh -File aai-release.ps1 -DryRun` in a throwaway temp git
  fixture exits 0 and prints the plan header — the guard did not break normal
  `-File` execution).

## Constitution deviations

None.

(Article-by-article check at freeze: 1 Evidence-before-claims — the 5.1-runtime
effect is explicitly quarantined into MV-1/MV-2 + RR-1; validation PASS covers
only host-provable tests, never the 5.1 stderr suppression. 2 Simplicity — a
single small checked-invoke helper + a one-`if` structural guard; no speculative
abstraction, no retrofit of the wider ps1 family (declared out of scope by the
intake). 3 Portability — plain .ps1/.Tests.ps1 edits, tri-platform parse-checked.
4 Degrade-and-report — this change EXISTS to make the failure path fail fast WITH
git's real diagnostic instead of a cryptic NativeCommandError or a silent
`*> $null`; it is Article 4 in action. 5 Additive-first — the helper is additive;
the dot-source guard leaves `-File`/plan/cut behavior byte-equivalent (TEST-007).
6 Single-writer state — no STATE hand-edit; state.mjs only. 7 Operator-only merge
— PR ceremony unchanged.)

## Acceptance Criteria Status

| Spec-AC    | Description                                                     | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Diagnostics-preserving `Invoke-NativeChecked` helper (EAP-local, throw-with-stderr on non-zero only) | done | docs/ai/tdd/red-20260722T125824Z-ps1-native-stderr-guard.log (RED), docs/ai/tdd/green-20260722T130141Z-ps1-native-stderr-guard.log (GREEN); `.aai/scripts/aai-release.ps1` lines 39-67 | — | 5.1 stderr-promotion suppression itself is off-host -> MV-1/MV-2 (RR-1); host-provable tests only |
| Spec-AC-02 | All cut-path native git/gh calls routed through helper; probes untouched; parse-clean 5.1 + 7 | done | docs/ai/tdd/green-20260722T130141Z-ps1-native-stderr-guard.log; `bash tests/skills/test-ps1-quality.sh` exit 0 (PSScriptAnalyzer 5.1+7.0 clean, no aai-release.ps1 warnings) | — | ps1-quality CI is authoritative for the real 5.1 parse |
| Spec-AC-03 | Dot-source guard enables unit test; `-File`/plan behavior unchanged | done | docs/ai/tdd/green-20260722T130141Z-ps1-native-stderr-guard.log (TEST-006/007); in-repo dot-source smoke confirmed no exit/side effect | — | — |

## Implementation plan

Components:
- EDIT `.aai/scripts/aai-release.ps1`:
  1. Define `function Invoke-NativeChecked` near the top (above the executable
     body). Signature (illustrative — implementer may adjust names, keep the
     contract): `param([string]$Exe, [string[]]$Arguments)`; body sets a local
     `$ErrorActionPreference = 'Continue'`, runs `$out = & $Exe @Arguments 2>&1`,
     then `if ($LASTEXITCODE -ne 0) { throw "<$Exe ...> failed (exit
     $LASTEXITCODE): $($out -join [Environment]::NewLine)" }`; else returns `$out`.
  2. Swap the CUT-sequence call sites (current lines ~253-266) onto the helper:
     `git add -- CHANGELOG.md`, `git commit -q -m …`, `git tag -a … -m …`, the
     display `git rev-parse --short HEAD`, `git push origin $branch`,
     `git push origin "refs/tags/$Version"`, `gh release create …`.
  3. Wrap the executable body (the `$extra`/arg-parse loop through the closing
     `finally`, current lines ~39-275) inside `if ($MyInvocation.InvocationName
     -ne '.') { … }` so dot-sourcing defines only functions. Keep the helper
     definition OUTSIDE (above) that guard.
- EDIT `tests/skills/aai-win-dispatch.Tests.ps1`: add a `Describe 'aai-release.ps1'`
  block that dot-sources the release script and exercises `Invoke-NativeChecked`
  (TEST-001..004, 006, 007). Uses a cross-platform stub — a child `pwsh
  -NoProfile -Command '[Console]::Error.WriteLine("<msg>"); exit <n>'` — so the
  stub deterministically writes stderr AND controls its exit code on pwsh 7
  (Linux CI + macOS). The static contract rows (TEST-001, TEST-004) assert
  against `Get-Content`/regex of the release file.

Edge cases: the two tolerant probes (`rev-parse -q --verify`, `gh auth status`)
must NOT be routed through the helper (they legitimately expect non-zero and
handle `$LASTEXITCODE` inline) — the grep contract asserts they keep `*> $null`.
The helper's throw message must join multi-line output so a real multi-line git
error is preserved. The dot-source guard must sit BELOW the helper (dot-source
must still define it). `$LASTEXITCODE` semantics: capture immediately after the
call, before any other statement can clobber it.

Seam analysis (cross-feature integration):
- Seam A — `aai-release.ps1` enters the ps1-quality CI gate (parse under real
  Windows PowerShell 5.1 + pwsh 7, PSScriptAnalyzer, Pester). The new helper and
  the guard `if` must parse under BOTH editions. Crossed by TEST-005 (the gate
  actually runs over the file) — contract.
- Seam B — the helper ↔ the REAL `git`/`gh` process at runtime under Windows
  PowerShell 5.1 (the actual defect surface). This seam CANNOT be crossed by any
  automated test in this repo (pwsh 7 does not reproduce stderr-promotion; there
  is no 5.1 runtime CI). Recorded as residual risk RR-1, covered by MV-1/MV-2.
- Seam C — the Pester suite ↔ `aai-release.ps1` via dot-source. The dot-source
  must define the helper without side effects. Crossed by TEST-006 — integration
  (real dot-source of the real file, not a mock).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                     | Description                                                                                                  | Status  |
|----------|------------|-------------|------------------------------------------|--------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit/static | tests/skills/aai-win-dispatch.Tests.ps1  | aai-release.ps1 defines `function … Invoke-NativeChecked` AND contains a local `$ErrorActionPreference = 'Continue'` | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/aai-win-dispatch.Tests.ps1  | stub writes stderr AND exits 0 -> `Invoke-NativeChecked` returns, does NOT throw                              | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/aai-win-dispatch.Tests.ps1  | stub writes stderr AND exits non-zero -> `Invoke-NativeChecked` THROWS and the message CONTAINS the stderr text | green |
| TEST-004 | Spec-AC-02 | unit/static | tests/skills/aai-win-dispatch.Tests.ps1  | no bare `git -C $Root push|add|commit|tag` and no bare `gh release create` remains; each cut op is an `Invoke-NativeChecked` arg; probes keep `*> $null` | green |
| TEST-005 | Spec-AC-02 | contract    | tests/skills/test-ps1-quality.sh         | gate parses aai-release.ps1 under 5.1 + pwsh 7, PSScriptAnalyzer 5.1/7.0 clean, Pester green (local; CI authoritative) | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/aai-win-dispatch.Tests.ps1  | dot-sourcing aai-release.ps1 defines `Invoke-NativeChecked` WITHOUT performing a release (no commit/tag/exit side effect) | green |
| TEST-007 | Spec-AC-03 | integration | tests/skills/aai-win-dispatch.Tests.ps1  | `pwsh -File aai-release.ps1 -DryRun` in a throwaway temp git fixture exits 0 and prints the plan header (guard preserved `-File` execution) | green |

RED-proof obligations (regardless of hybrid split):
- TEST-002, TEST-003, TEST-006: genuinely RED first — `Invoke-NativeChecked`
  does not exist and dot-sourcing today runs the whole script, so the calls
  error / the side-effect assertion fails until the helper + guard land.
  TEST-003 is additionally RED against a naive `2>$null`-swallow variant (the
  `-ExpectedMessage`/contains-stderr assertion fails when the text is hidden)
  and against a helper that omits the `$LASTEXITCODE` check (no throw at all).
- TEST-001, TEST-004: RED now by construction — the function/EAP-local pattern
  is absent and the bare unguarded push/add/commit/tag/gh statements are still
  present (capture the failing grep as the RED artifact).
- TEST-007: RED-lineage is the guard wrap — before the `if` guard the script has
  no separable Main to prove "unchanged"; after the wrap it must still exit 0 in
  dry-run. Its role is a regression backbone for the structural change (proves
  the wrap did not break `-File`), not a new-behavior RED.
- TEST-005: regression/contract gate — deliberately green-once-correct; its RED
  lineage is any parse/analyzer break introduced by the edit. It gates
  "still parses/analyzes", not new behavior.

Provable-here vs not:
- Runnable on this host (pwsh 7 + git + bash): TEST-001..004, TEST-006, TEST-007;
  TEST-005 (PSScriptAnalyzer step skips-with-note if the module is absent
  locally — CI authoritative).
- NOT runnable here: the real Windows-PowerShell-5.1 stderr-promotion
  suppression (Seam B) — MV-1/MV-2 only; residual risk RR-1.

## Manual verification protocol (Windows PowerShell 5.1) — MV-1..MV-2

To be executed on a native Windows machine under Windows PowerShell 5.1 (NOT
pwsh 7) by the operator or a downstream contributor; results attached to the
issue before it is closed. In a checkout with an `[unreleased]` CHANGELOG entry
and a reachable remote:

- MV-1 (no-remote cut, offline-safe): `powershell -File
  .aai\scripts\aai-release.ps1 --confirm --no-remote` -> the CHANGELOG rolls, a
  local commit + annotated tag are created, exit 0, NO NativeCommandError. This
  exercises `git add`/`commit`/`tag` + the display `rev-parse` through the
  helper without touching the network.
- MV-2 (real push/publish): with a disposable tag/version, `powershell -File
  .aai\scripts\aai-release.ps1 --confirm` -> `git push` and
  `git push refs/tags/…` succeed and the run does NOT abort on git's "To
  <remote>…" stderr progress; `gh release create` publishes; exit 0. Then force
  a FAILURE (e.g. push to a ref with no permission, or disconnect the network)
  and confirm the cut FAILS with git's REAL error text surfaced (rejected/auth/
  network) — not swallowed, not a bare NativeCommandError.

Residual risk RR-1 (explicit): until MV-1/MV-2 are recorded, the Windows
PowerShell 5.1 stderr-promotion suppression is DOCUMENTED and logically
guarded but not verified by this repo. Automated coverage = parse (5.1 + 7) +
PSScriptAnalyzer + pwsh 7 Pester (helper LOGIC) + static contract. This repo's
validation PASS asserts only those host-provable tests; it does NOT claim the
5.1 runtime fix. Same posture as SPEC-0046's MV-1..3 / RR-1.

## Verification
- `pwsh -NoProfile -Command "Invoke-Pester -Path tests/skills/aai-win-dispatch.Tests.ps1 -Output Detailed"` -> all pass (TEST-001..004, 006, 007)
- `bash tests/skills/test-ps1-quality.sh` -> exit 0 (TEST-005; PSScriptAnalyzer may skip-with-note locally, CI authoritative)
- ps1-quality CI (`.github/workflows/ps1-quality.yml`) green: parse under real Windows PowerShell 5.1 + pwsh 7, PSScriptAnalyzer 5.1/7.0, Pester (authoritative for the 5.1 PARSE; NOT for the 5.1 runtime effect — RR-1)
- PASS criteria: all non-manual TEST-xxx green AND every Spec-AC in a terminal
  status. Spec-AC-01/02/03 terminal at validation = host-provable tests green +
  RR-1 recorded; MV-1/MV-2 EXECUTION tracks on the ISSUE, not this spec's PASS.

## Evidence contract
For each implementation/TDD/validation/review artifact record: ref_id
(`ps1-native-stderr-guard`), Spec-AC + TEST-xxx links, command or review scope,
exit code or verdict, evidence path (docs/ai/tdd/ RED/GREEN logs carry
`RED_CLASS:` headers per SPEC-0044), commit SHA or diff range.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
