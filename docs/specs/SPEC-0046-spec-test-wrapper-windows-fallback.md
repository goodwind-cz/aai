---
id: spec-test-wrapper-windows-fallback
type: spec
number: 46
status: done
ceremony_level: 2
links:
  issue: test-wrapper-windows-fallback
  rfc: null
  pr:
    - 98
  commits:
    - 7fc7912
---

# SPEC — Test-Wrapper Windows Fallback: deterministic interpreter resolution (ISSUE-0009)

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0009-test-wrapper-windows-fallback.md (issue, ref_id `test-wrapper-windows-fallback`)
- Fold-in: NB-1 from review-20260717T142458Z — tdd-evidence-check.mjs rejects a UTF-8 BOM-prefixed `RED_CLASS:` header (recorded in the issue's Notes)
- Related prior art: SPEC-0009 (process-group wrapper contract), SPEC-0044 (RED evidence classifier)
- Technology contract: docs/TECHNOLOGY.md

## Ceremony level

`ceremony_level: 2` (full pipeline). Honest reasoning:
- NOT level 1: the scope is multi-surface — two shell wrappers, two NEW
  PowerShell dispatchers, one Node script (BOM fold-in), the ps1-quality gate
  wiring, docs/TECHNOLOGY.md, and three test files. It also touches the
  ISSUE-0002/SPEC-0009 process-cleanup safety surface (never-global reaping),
  where a silent mistake is expensive.
- NOT level 3: no path in `protected_paths_l3` (docs/ai/docs-audit.yaml) is
  touched (state engine, allocator, pre-commit guards, workflow canon are all
  out of scope).
- BOM fold-in (NB-1) INCLUDED in this scope: it is Windows-capture-related
  (same platform theme as this issue), a one-line-class fail-closed fix
  (false rejection, never false accept), and fully provable on this host —
  splitting it out would spawn a micro-issue with more ceremony than code.

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD for the dispatcher behavior (TEST-001..007) and the BOM fix
  (TEST-010) — new process-cleanup/safety behavior and a bug fix that needs
  regression proof, both genuinely RED-provable on this host (the dispatcher
  files do not exist yet; the current classifier exits 2 on a BOM log). Loop
  for the mechanical parts: platform-matrix doc lines (TEST-009), ps1-quality
  gate wiring (TEST-012), manual-protocol section (TEST-013).

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: additive change on a single scope, PR-bound; the
  operator has ALREADY recorded the isolation decision in STATE
  (`user_decision: inline` on branch `fix/test-wrapper-windows-fallback`,
  which exists on origin at main's tip). Planning does not re-open it.
- User decision: inline (pre-recorded by operator)
- Base ref: main
- Inline review scope: see `## Code review scope` below
- code_review.required: true (shell + PowerShell + Node behavior changes on
  the test-safety surface)

## Code review scope
Explicit paths (inline review):
- .aai/scripts/aai-run-tests.ps1 (new)
- .aai/scripts/aai-reap-tests.ps1 (new)
- .aai/scripts/aai-run-tests.sh
- .aai/scripts/aai-reap-tests.sh
- .aai/scripts/tdd-evidence-check.mjs
- tests/skills/aai-win-dispatch.Tests.ps1 (new)
- tests/skills/test-aai-win-fallback.sh (new)
- tests/skills/test-aai-tdd-evidence.sh
- tests/skills/test-ps1-quality.sh
- .github/workflows/ps1-quality.yml
- docs/TECHNOLOGY.md
- docs/specs/SPEC-0046-spec-test-wrapper-windows-fallback.md
- docs/issues/ISSUE-0009-test-wrapper-windows-fallback.md

## Testability constraint (shapes this whole plan)

This host is macOS; there is no Windows, no WSL, no Git Bash, no MSYS here.
Therefore the Test Plan is split honestly into:
- PROVABLE HERE: dispatcher resolution/selection logic (Pester under local
  pwsh 7 at /opt/homebrew/bin/pwsh, with ALL environment probes injectable and
  mocked), the named-error contract, the forced-MSYS branch selection in the
  .sh (env-injected uname), the BOM fix (Node), the macOS/Linux regression
  backbone (existing SPEC-0009 suite), doc-presence greps, ps1 parse checks.
- CANNOT VERIFY ON THIS HOST (recorded, never claimed): real WSL delegation,
  real Git Bash/MSYS process semantics, real `taskkill /T` tree-kill
  completeness. These are covered by the documented manual verification
  protocol (Spec-AC-10) and remain an explicit residual risk until a Windows
  run is recorded. No PASS claim in this repo asserts Windows-host behavior.

## Acceptance Criteria Mapping

Requirement AC (issue "Verification" section) -> Spec-AC -> verification:

1. "Documented, deterministic interpreter-resolution step (WSL -> Git Bash ->
   named error)" -> Spec-AC-01, Spec-AC-02 -> TEST-001..004 (Pester, mocked
   probes; local pwsh + Linux CI).
2. "Falls back to a defined native-Git-Bash path" -> Spec-AC-03, Spec-AC-04,
   Spec-AC-05 -> TEST-005..007 (mocked run contract; forced-MSYS branch), plus
   manual protocol MV-2/MV-3.
3. "Exits with a clear, named error when neither is available" -> Spec-AC-02
   -> TEST-004.
4. "Supported environment matrix documented" -> Spec-AC-07 -> TEST-009.
5. "Process-cleanup guarantee (or documented lack thereof) explicit, not
   silently assumed equivalent" -> Spec-AC-03 (header + docs statement),
   Spec-AC-04 (safety guards preserved) -> TEST-005, TEST-006, TEST-009.
6. "Manual verification on Windows in each of the three configurations" ->
   Spec-AC-10 -> TEST-013 (protocol documented here; execution is manual,
   off-host, recorded before issue close).
7. "Should not regress the existing macOS/Linux contract (SPEC-0009)" ->
   Spec-AC-06 -> TEST-008.
8. NB-1 fold-in (BOM-prefixed RED_CLASS header falsely UNCLASSIFIED) ->
   Spec-AC-08 -> TEST-010, TEST-011.
9. Repo quality gates for new PowerShell -> Spec-AC-09 -> TEST-012.

## Spec Acceptance Criteria (verifiable statements)

- Spec-AC-01 — Deterministic resolution order. A new Windows entry point
  `.aai/scripts/aai-run-tests.ps1` resolves the interpreter in a FIXED,
  documented order: (1) usable WSL (wsl.exe present AND a probe command
  succeeds in a default distro), (2) native Git Bash (fixed candidate list,
  first hit wins: `$env:ProgramFiles\Git\bin\bash.exe`,
  `${env:ProgramFiles(x86)}\Git\bin\bash.exe`, bash derived from `git.exe`
  `--exec-path`, PATH `bash.exe` that is NOT `System32\bash.exe` (WSL shim)),
  (3) named failure. Identical probe results always produce the identical
  choice. All probes are injectable (overridable functions/scriptblocks) so
  Pester can force each branch. `wsl.exe` present but with NO usable distro
  counts as WSL-absent and falls through to (2) — never a hang or a raw
  wsl error.
- Spec-AC-02 — Named fail-fast error. When neither WSL nor Git Bash resolves,
  the dispatcher writes EXACTLY ONE stderr line matching
  `^AAI-ENV-ERROR: no usable POSIX interpreter` (the line also names both
  probed options — WSL and Git for Windows — and a remediation hint) and exits
  with code 78 (sysexits EX_CONFIG; distinct from 1/2 test-and-usage failures,
  124 timeout, 127 not-found), so a caller can never mistake a missing
  interpreter for a test failure.
- Spec-AC-03 — Git-Bash fallback run contract, guarantee stated. On the
  Git-Bash path the dispatcher runs `.aai/scripts/aai-run-tests.sh <cmd...>`
  under the resolved bash.exe, passes `AAI_TEST_TIMEOUT` through, propagates
  the child's real exit code, and on timeout kills the launched process TREE
  (Windows `taskkill /T /F` semantics) and exits 124. The NARROWER guarantee
  is stated verbatim in the .ps1 header and the platform matrix: tree-kill
  covers the launched tree only; detached/reparented descendants are NOT
  guaranteed reaped (no POSIX sessions on Windows) — explicitly weaker than
  the SPEC-0009 macOS/Linux contract, never silently assumed equal.
- Spec-AC-04 — Reaper dispatcher keeps both safety guards. A new
  `.aai/scripts/aai-reap-tests.ps1` mirrors the resolution order; its native
  path reaps ONLY processes whose command line contains a `vitest`/`esbuild`
  token AND the workspace path (AAI_REAP_WORKSPACE, default $PWD) AND whose
  age >= AAI_REAP_MIN_AGE_SECS. It never issues a global kill and prints
  `reaped: N` like the .sh reaper. The snapshot source is injectable for
  tests.
- Spec-AC-05 — MSYS-deterministic .sh launch chain. When
  `.aai/scripts/aai-run-tests.sh` runs where uname reports `MSYS*`/`MINGW*`
  (i.e. directly inside Git Bash), the launch chain deterministically selects
  a documented degraded branch (no setsid/perl-setsid pretence; best-effort
  tree kill via `taskkill //T` when available, POSIX kill otherwise) and says
  so once on stderr. Branch SELECTION is injectable via an `AAI_UNAME`
  override (used only when set) so it is unit-testable on this host; with
  `AAI_UNAME` unset on macOS/Linux the chain is byte-for-byte the current
  behavior.
- Spec-AC-06 — macOS/Linux regression backbone. The existing SPEC-0009 suite
  `tests/skills/test-aai-run-tests.sh` passes unchanged against the modified
  wrappers on this host (same pass/fail set as clean main). This is the
  non-negotiable regression gate for every .sh edit in this scope.
- Spec-AC-07 — Supported platform matrix documented. Both wrapper headers AND
  docs/TECHNOLOGY.md carry the same 5-row matrix: macOS (full SPEC-0009
  contract), Linux (full), Windows+WSL (full, via WSL delegation),
  Windows+Git-Bash-only (degraded — tree-kill only, documented weaker
  guarantee), Windows with neither (deterministic `AAI-ENV-ERROR:` + exit 78).
- Spec-AC-08 — BOM fold-in. `tdd-evidence-check.mjs` strips a single leading
  U+FEFF from the file content before line matching. A BOM-prefixed, otherwise
  valid `RED_CLASS: product_red` log (CRLF or LF) exits 0; all fail-closed
  behaviors are unchanged (zero headers / two headers / unknown value -> exit
  2; infra_fail -> exit 1; a BOM anywhere other than byte 0 changes nothing).
- Spec-AC-09 — ps1 quality gates cover the new scripts. Both new .ps1 parse
  under Windows PowerShell 5.1 + pwsh 7 and pass PSScriptAnalyzer via the
  existing ps1-quality gate (auto-globbed from .aai/scripts/*.ps1), and
  `tests/skills/test-ps1-quality.sh` + the workflow paths are extended to run
  the new Pester file `tests/skills/aai-win-dispatch.Tests.ps1`.
- Spec-AC-10 — Manual Windows verification protocol. This spec's
  `## Manual verification protocol (Windows)` section defines the three-config
  checklist (MV-1..MV-3) with expected observations; the residual risk
  ("Windows-host semantics not verified in this repo") is recorded below and
  stays open until an operator/downstream run is attached to the issue.

## Constitution deviations

None.

(Article-by-article check at freeze: 1 — no Windows-host claim is made without
evidence; unverifiable-here behavior is explicitly quarantined into MV-1..3 +
residual risk, and validation PASS covers only host-provable tests. 2 — the
dispatcher is a thin resolution shim, no speculative abstraction. 3 — this
change exists to improve tri-platform portability; all artifacts are plain
files. 4 — the core deliverable IS degrade-and-report (named AAI-ENV-ERROR,
fail fast, documented degraded mode). 5 — additive: new .ps1 entry points; the
.sh edits are inert on macOS/Linux (Spec-AC-06). 6 — STATE only via state.mjs.
7 — PR ceremony unchanged, operator merges.)

## Acceptance Criteria Status

| Spec-AC    | Description                                        | Status   | Evidence | Review-By | Notes |
|------------|----------------------------------------------------|----------|----------|-----------|-------|
| Spec-AC-01 | Deterministic WSL->GitBash->error resolution       | done     | TEST-001..003 green; docs/ai/tdd/green-20260717T155511Z-test001-006-ps1-dispatchers.log | —         | — |
| Spec-AC-02 | AAI-ENV-ERROR + exit 78 fail-fast                  | done     | TEST-004 green; docs/ai/tdd/green-20260717T155511Z-test001-006-ps1-dispatchers.log | —         | — |
| Spec-AC-03 | Git-Bash run contract + stated narrower guarantee  | done     | TEST-005 green; docs/ai/tdd/green-20260717T155511Z-test001-006-ps1-dispatchers.log | —         | Windows-host semantics unverified on this host -> MV-2 (residual risk RR-1) |
| Spec-AC-04 | Reaper dispatcher keeps workspace+age guards       | done     | TEST-006 green; docs/ai/tdd/green-20260717T155511Z-test001-006-ps1-dispatchers.log | —         | Windows-host semantics unverified on this host -> MV-2 (residual risk RR-1) |
| Spec-AC-05 | MSYS-deterministic .sh branch (injectable)         | done     | TEST-007 green; docs/ai/tdd/green-20260717T155744Z-test007-msys-branch.log | —         | Windows-host semantics unverified on this host -> MV-3 (residual risk RR-1) |
| Spec-AC-06 | macOS/Linux regression backbone unchanged          | done     | TEST-008 green (same 15/15 pass set as clean main); docs/ai/tdd/green-20260717T155744Z-test007-msys-branch.log | — | — |
| Spec-AC-07 | 5-row platform matrix in headers + TECHNOLOGY.md   | done     | TEST-009 green; tests/skills/test-aai-win-fallback.sh | —         | — |
| Spec-AC-08 | BOM strip in tdd-evidence-check.mjs (NB-1)         | done     | TEST-010/011 green; docs/ai/tdd/green-20260717T154550Z-test010-011-bom-foldin.log | — | — |
| Spec-AC-09 | ps1 parse/analyzer/Pester gate wiring              | done     | TEST-012 green; tests/skills/test-ps1-quality.sh (local pwsh; CI is authoritative) | — | — |
| Spec-AC-10 | Manual Windows protocol documented + residual risk | deferred | TEST-013 doc-presence green; tests/skills/test-aai-win-fallback.sh | 2026-10-17 | Protocol section + RR-1 recorded in this spec; MV-1..MV-3 EXECUTION is a real-Windows requirement, off-host — tracked on ISSUE-0009, not claimed here |

## Implementation plan

Components:
- NEW `.aai/scripts/aai-run-tests.ps1` — Windows dispatcher (PS 5.1-compatible;
  probes as overridable functions for Pester injection; WSL delegation with
  `wslpath` translation; Git-Bash launch + ps1-side watchdog + `taskkill /T`;
  `AAI-ENV-ERROR` path).
- NEW `.aai/scripts/aai-reap-tests.ps1` — reaper dispatcher (same resolution;
  native path: command-line match token+workspace, age guard, tree-kill,
  `reaped: N` output; snapshot injectable).
- EDIT `.aai/scripts/aai-run-tests.sh` — MSYS-detected degraded branch in the
  launch/reap chain (selection via `uname -s`, test-injectable via `AAI_UNAME`),
  header platform matrix. Inert on macOS/Linux.
- EDIT `.aai/scripts/aai-reap-tests.sh` — header platform matrix (+ MSYS note).
- EDIT `.aai/scripts/tdd-evidence-check.mjs` — strip one leading U+FEFF before
  splitting lines.
- EDIT `docs/TECHNOLOGY.md` — platform matrix rows under Testing/Constraints.
- NEW `tests/skills/aai-win-dispatch.Tests.ps1`, NEW
  `tests/skills/test-aai-win-fallback.sh`; EDIT
  `tests/skills/test-aai-tdd-evidence.sh`, `tests/skills/test-ps1-quality.sh`,
  `.github/workflows/ps1-quality.yml` (paths + Pester wiring).

Edge cases: wsl.exe present but no distro (fall through, no hang);
`System32\bash.exe` WSL shim never treated as Git Bash; `ProgramFiles(x86)`;
paths with spaces; AAI_TEST_TIMEOUT coercion parity with the .sh (non-integer
/ <=0 -> 300); exit-code namespace (78 reserved, 124 kept for timeout); BOM
stripped ONLY at byte 0; BOM + CRLF combined.

Seam analysis (cross-feature integration):
- Seam A — loop/skills invoke `.aai/scripts/aai-run-tests.sh` by literal path
  (LEARNED.md rule; SKILL_LOOP/VALIDATION wiring greps). Dispatchers are
  additive; the .sh path stays valid everywhere. Crossed by TEST-008 (the
  existing suite includes the wiring asserts) — integration.
- Seam B — Windows-captured RED logs (BOM+CRLF) flow into
  `tdd-evidence-check.mjs`, which gates TDD GREEN. Crossed end-to-end by
  TEST-010 (real bytes on disk -> real exit code) — integration.
- Seam C — new .ps1 files enter the ps1-quality CI gate. Crossed by TEST-012
  (gate script actually runs over them) — contract.
- Seam D — reaper safety invariant shared with SPEC-0009 (never-global kill)
  now has a second implementation. Crossed by TEST-006 on the mocked side;
  the real-Windows half CANNOT be crossed by an automated test in this repo —
  recorded as residual risk RR-1 (below), covered by MV-2.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description                                                                 | Status  |
|----------|------------|-------------|-----------------------------------------|-----------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/aai-win-dispatch.Tests.ps1 | mocked WSL probe usable -> WSL branch selected (delegation argv correct)    | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/aai-win-dispatch.Tests.ps1 | WSL absent/unusable + Git Bash candidates -> first-hit-wins, shim excluded  | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/aai-win-dispatch.Tests.ps1 | all probes negative -> error branch chosen (never a partial launch)         | green |
| TEST-004 | Spec-AC-02 | unit        | tests/skills/aai-win-dispatch.Tests.ps1 | error branch: exit 78, exactly one stderr line ^AAI-ENV-ERROR: with names   | green |
| TEST-005 | Spec-AC-03 | unit        | tests/skills/aai-win-dispatch.Tests.ps1 | Git-Bash run: wrapper path+args+AAI_TEST_TIMEOUT passthrough; timeout->124 + tree-kill call; normal->child code | green |
| TEST-006 | Spec-AC-04 | unit        | tests/skills/aai-win-dispatch.Tests.ps1 | reap: mocked snapshot — other-workspace spared, young spared, old match killed as tree; prints reaped: N | green |
| TEST-007 | Spec-AC-05 | unit        | tests/skills/test-aai-win-fallback.sh   | AAI_UNAME=MSYS_NT-10.0 -> degraded branch marker on stderr; unset -> current chain untouched | green |
| TEST-008 | Spec-AC-06 | integration | tests/skills/test-aai-run-tests.sh      | full existing SPEC-0009 suite passes unchanged (regression backbone)        | green |
| TEST-009 | Spec-AC-07 | unit        | tests/skills/test-aai-win-fallback.sh   | grep asserts: 5-row matrix present in both wrapper headers + TECHNOLOGY.md  | green |
| TEST-010 | Spec-AC-08 | integration | tests/skills/test-aai-tdd-evidence.sh   | BOM+CRLF `RED_CLASS: product_red` log -> exit 0 ACCEPTED (currently exit 2) | green |
| TEST-011 | Spec-AC-08 | unit        | tests/skills/test-aai-tdd-evidence.sh   | fail-closed unchanged: 0/2 headers, bad value -> 2; infra_fail -> 1; mid-file BOM inert | green |
| TEST-012 | Spec-AC-09 | contract    | tests/skills/test-ps1-quality.sh        | gate parses/analyzes new .ps1 and runs aai-win-dispatch.Tests.ps1 (local pwsh; authoritative in CI) | green |
| TEST-013 | Spec-AC-10 | manual      | docs/specs/SPEC-0046-spec-test-wrapper-windows-fallback.md | MV protocol section exists (grep in TEST-009 stanza); MV-1..3 EXECUTION is manual, off-host | pending |

Provable-here vs not:
- Runnable on this host: TEST-001..007 (pwsh 7 at /opt/homebrew/bin/pwsh +
  bash), TEST-008, TEST-009, TEST-010, TEST-011, TEST-012 (analyzer step
  skips-with-note if module absent locally; CI is authoritative).
- NOT runnable here: real-Windows halves of Spec-AC-03/04/05 — MV-1..MV-3
  only. TEST-013's automated part checks only that the protocol is documented.

RED-proof obligations (regardless of hybrid split):
- TEST-001..007, TEST-009, TEST-012: genuinely RED first — the .ps1 files, the
  MSYS branch, the matrix text, and the gate wiring do not exist yet.
- TEST-010: RED now by construction — current tdd-evidence-check.mjs exits 2
  on a BOM-prefixed valid log (capture the RED log via the classifier run).
- TEST-008, TEST-011: regression backbones, deliberately green-on-main; their
  RED lineage is the original SPEC-0009/SPEC-0044 stub RED-proofs. They gate
  "unchanged", not "new", behavior — no new RED is manufactured for them.

## Manual verification protocol (Windows) — MV-1..MV-3

To be executed on a native Windows machine (or Windows CI runner) by the
operator or a downstream contributor; results attached to ISSUE-0009 before
the issue is closed. From a plain cmd.exe/PowerShell prompt in a checkout:

- MV-1 (WSL present): `powershell -File .aai\scripts\aai-run-tests.ps1 sh -c "exit 7"`
  -> exit 7 (delegated via WSL); a sleep-based command times out with 124 when
  AAI_TEST_TIMEOUT=2.
- MV-2 (WSL absent, Git Bash present): same invocations -> exit-code fidelity
  and 124-on-timeout via the Git-Bash path; start a command that spawns a
  child sleeper, confirm `taskkill /T` reaped the tree (no survivor in Task
  Manager/`tasklist`); `aai-reap-tests.ps1` with a decoy process from ANOTHER
  directory confirms the workspace guard (decoy survives).
- MV-3 (inside Git Bash directly): `bash .aai/scripts/aai-run-tests.sh sh -c "exit 7"`
  -> exit 7 plus the one-line degraded-mode notice; timeout path exits 124.
- MV-neither (no WSL, no Git Bash): dispatcher exits 78 with the single
  `AAI-ENV-ERROR:` line — visibly distinct from a test failure.

Residual risk RR-1 (explicit): until MV-1..3 are recorded, the Windows-host
process-cleanup semantics of the fallback are DOCUMENTED but not verified by
this repo. This repo's validation PASS asserts only the host-provable tests.

## Verification
- `pwsh -NoProfile -Command "Invoke-Pester -Path tests/skills/aai-win-dispatch.Tests.ps1 -Output Detailed"` -> all pass (TEST-001..006)
- `bash tests/skills/test-aai-win-fallback.sh` -> exit 0 (TEST-007, TEST-009, TEST-013 doc-presence)
- `bash tests/skills/test-aai-run-tests.sh` -> exit 0 / same result set as clean main (TEST-008)
- `bash tests/skills/test-aai-tdd-evidence.sh` -> exit 0 (TEST-010, TEST-011)
- `bash tests/skills/test-ps1-quality.sh` -> exit 0 (TEST-012; analyzer may skip-with-note locally, CI authoritative)
- PASS criteria: all non-manual TEST-xxx green AND every Spec-AC in a terminal
  status (Spec-AC-10's terminal state at validation time = protocol section
  present + RR-1 recorded; MV execution tracks on the ISSUE, not this spec's
  PASS).

## Evidence contract
For each implementation/TDD/validation/review artifact record: ref_id
(`test-wrapper-windows-fallback`), Spec-AC + TEST-xxx links, command or review
scope, exit code or verdict, evidence path (docs/ai/tdd/ RED/GREEN logs must
carry `RED_CLASS:` headers per SPEC-0044), commit SHA or diff range.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
