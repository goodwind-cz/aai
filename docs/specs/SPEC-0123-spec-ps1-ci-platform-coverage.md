---
id: spec-ps1-ci-platform-coverage
type: spec
number: 123
status: done
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0136-ps1-ci-platform-coverage.md
  rfc: null
  pr:
    - 251
  commits:
    - 7e9e53f
---

# Spec — ps1-quality closes the three CI platform blind spots (functional WSL, 5.1-only hosts, image drift)

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0136-ps1-ci-platform-coverage.md
- Workflow this scope extends (never forks): `.github/workflows/ps1-quality.yml`
- Wrapper whose routing is finally proven live: `.aai/scripts/aai-run-tests.ps1` (SPEC-0046, SPEC-0120)
- Selftest reused as the WSL-leg smoke (never re-implemented): `.aai/scripts/aai-win-selftest.ps1` (SPEC-0122 D1/D3)
- Pinning suite this scope grows: `tests/skills/test-aai-win-fallback.sh` (test_014..test_018 style)
- Residual this scope closes in CI: docs/ai/decisions.jsonl 2026-08-13T02:26 entry for CHANGE-0135 ("WSL-branch marker translation is proven by payload-shape pin ... first downstream run on a WSL-functional host is the real proof")
- Product doc updated: docs/product/windows-test-wrapper.md
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1 — the intake declared level 1 and this scope
keeps it: one CI workflow file, its existing bash pinning suite, and truthful
doc updates; zero bytes change in any production `.aai/scripts/*` file, no
prompt-corpus bytes, no new `.aai/**` file, and no `protected_paths_l3` surface
(verified against docs/ai/docs-audit.yaml: state engine, allocator, guards,
workflow canon — none touched). Every acceptance criterion names a directly
executable command; the two live-CI criteria follow the SPEC-0122
planned-until-the-named-run-is-green discipline.

## Summary

After CHANGE-0135/PR #249, three blind spots remain in the Windows CI surface,
and two have already produced real escapes (both Codex P1 findings on PR #249
lived on the never-executed WSL branch):

1. **Functional WSL** — windows-latest ships `wsl.exe` with ZERO distros, so
   the wrapper's WSL branch has never run end-to-end in CI. A new sibling job
   `windows-wsl1` installs a WSL1 Debian distro, control-asserts it is
   genuinely functional (and genuinely WSL1), proves `AAI-BRANCH: WSL` routing
   on a real wrapper invocation, runs the three-arm smoke WITH WSL semantics
   through the vendored selftest (first real execution of the e398686 wslpath
   marker-translation guard and of the spawnfail decoy-PATH fix on a
   WSL-usable host), and runs the full Pester suite under Windows PowerShell
   5.1 with the same pinned result-floor discipline as the existing leg.
2. **5.1-only hosts** — runners carry both engines, so every
   prefer-pwsh-else-powershell fallback always takes the pwsh arm in CI. A new
   step in the existing `windows-5_1` job doctors a CHILD process's PATH so
   pwsh is not resolvable (control-asserted in both directions), then proves
   `Resolve-SelfTestEngine` and the doctor's engine pick take the
   powershell.exe arm for real, with all three CAT-14 arms passing under it.
3. **Image drift** — ps1-quality runs only on push/PR/dispatch. A weekly UTC
   cron plus a canary-marking run-name makes a runner-image update fail a
   scheduled run instead of the next unrelated PR.

The existing `windows-5_1` job's no-WSL semantics are NOT perturbed: the
zero-distro fallback path (field defect TEST-010's live regression bed) keeps
running unchanged on its own VM.

## Design decisions recorded at planning time (do not re-derive)

### D1 — WSL1 install mechanism: Vampire/setup-wsl, pinned major, Debian

- Mechanism: `Vampire/setup-wsl` pinned by MAJOR tag, with `wsl-version: 1`
  and `distribution: Debian`. Alternatives rejected: raw `wsl --install`
  (targets WSL2, needs virtualization/reboot semantics hosted runners do not
  have) and a hand-rolled `wsl --import` of a rootfs (re-implements what the
  action maintains, with no pinning story). GitHub-hosted Windows runners
  cannot run WSL2 at all — no nested virtualization — so WSL1 is the only
  installable coverage; the workflow header and the product doc must say so
  (Spec-AC-05), never paper over it. Implementation verifies the action's
  current major tag at build time and pins it; the bash pin asserts the
  `Vampire/setup-wsl@v` pinned SHAPE so a future major bump is a reviewed
  one-token change, not a suite rewrite.
- Distribution: Debian over Alpine. `aai-run-tests.sh` is `#!/bin/sh` but its
  full contract depends on `setsid` (util-linux), procps `ps` output shapes,
  `mktemp` and a perl fallback path; Alpine's busybox implements a different
  subset, and the Linux `gate` job already proves the wrapper against a
  GNU/Debian-class userland. The ~1–2 min larger install is accepted inside
  the budget (D2).
- `wslpath` is a WSL-provided binary present inside WSL1 distros; the leg
  CONTROL-ASSERTS it (`wsl.exe -e wslpath -a` on `C:\` must yield a `/mnt/c`
  path) rather than trusting this note.
- Functional sentinel: the control step runs `& wsl.exe -e sh -c "exit 42"`
  via the direct call operator (native argv — the Start-Process pre-quoting
  footgun does not apply to `&`) and requires `$LASTEXITCODE` exactly 42 —
  the SAME semantics as `Test-WslUsable`'s own probe, so a setup-wsl failure
  fails the control loudly instead of silently degrading the leg into a
  duplicate Git Bash run. A second control asserts `wsl.exe -l -v` reports
  VERSION 1, so the leg can never silently become a WSL2 claim.

### D2 — a separate sibling job, not steps inside windows-5_1

Installing a distro is HOST-GLOBAL: appended steps would flip
`Test-WslUsable` to true for every step of the existing job and destroy the
proven no-WSL/zero-distro fallback coverage — windows-latest's distro-less
`wsl.exe` is itself a tested input (the TEST-010 field defect's live
regression bed). Both legs must keep running, so the WSL coverage is a new
`windows-wsl1` job on its own VM.

- Skip-count audit (every PosixOnly skip re-checked against a WSL-usable
  host): exactly four `-Skip:$script:SkipOnWindows` tests exist
  (aai-win-dispatch.Tests.ps1 lines 249, 413, 709; aai-update.Tests.ps1 line
  136). All four predicates are driven solely by `Test-IsWindowsHostFor`
  (host OS), none by WSL state; the line-249 reason ("windows-latest always
  has a real Git Bash, so the dispatcher resolves it and runs the command")
  stays true on a WSL-usable host — the dispatcher resolves WSL and runs the
  command. The expected count is therefore 4 ON BOTH LEGS. Because
  test_017 pins the `AAI_EXPECTED_WIN_SKIP_COUNT:` declaration to EXACTLY
  ONCE in the workflow, the declaration moves from job-level to
  WORKFLOW-level `env` (inherited by both jobs; still declared once; the
  job-level comment moves with it). If a future change ever makes the counts
  diverge per leg, the pin goes per-leg — the count is never loosened.
- The WSL leg runs the full Pester discovery under Windows PowerShell 5.1
  ONLY: the two-engine matrix is already proven on the no-WSL leg, the
  dispatcher's routing logic is engine-independent, and one engine keeps the
  leg inside budget.
- The three-arm smoke on this leg is the VENDORED SELFTEST, not a third smoke
  implementation: the job runs `node .aai/scripts/aai-doctor.mjs --json` and
  asserts each CAT-14 arm per-name (success exit 3 with the marker written
  through the payload's `command -v wslpath` translation, timeout 124,
  spawnfail 125 with exactly one AAI-SPAWN-ERROR) plus CAT-15
  `wsl: functional`. This is deliberate reuse (SPEC-0122 D1 doctrine) AND it
  makes this run the first real execution of both e398686 fixes: the
  marker-translation guard on the success arm, and — because the spawnfail
  arm's reduced PATH must hide `wsl.exe` — the decoy-PATH fix is live-proven
  on a host where WSL would otherwise route around the decoy (the exact
  Codex P1 shape).
- Budget: the job is PARALLEL to `windows-5_1` (~10 min today), estimated
  5–8 min total (setup-wsl ~1–2 min, controls under 30 s, doctor selftest
  ~1–2 min, Pester install cached, full 5.1 Pester ~1–2 min), so workflow
  wall-clock is roughly unchanged unless it becomes the critical path;
  `timeout-minutes` caps the Pester step at 15 like the existing steps. This
  satisfies the intake's ~+5 min budget.

### D3 — the 5.1-only context is a doctored CHILD environment, never a host mutation

One new step in the EXISTING `windows-5_1` job (no WSL there — this also
covers the common corporate powershell.exe-plus-Git-Bash-only shape):

- The parent step first control-asserts pwsh IS resolvable undoctored (so the
  hiding check below can never pass vacuously).
- It computes a reduced PATH = the current PATH minus every directory in
  which `pwsh.exe` exists, and spawns a child `powershell.exe` (Start-Process
  with OS-handle stream capture, pre-quoted argument string, `.Handle`
  touched) whose inner script sets `$env:Path` to that reduced value INSIDE
  its own text — the same doctored-child-environment technique as
  CHANGE-0135 D3's decoy; nothing on the host is uninstalled, renamed or
  moved, and `Move-Item`/`Rename-Item` never appear in the step.
- Inside the doctored child, in order: control assertion that
  `Get-Command pwsh` resolves NOTHING (distinct loud exit code if it does —
  the hiding itself silently breaking is a named failure, per intake
  AC-002); assertion that `Resolve-SelfTestEngine` (dot-sourced from
  `aai-win-selftest.ps1`) returns `powershell`; then
  `node .aai/scripts/aai-doctor.mjs --json` runs in that context (node's
  directory survives the filter) and all three CAT-14 arms must be PASS —
  the doctor's own engine pick and every selftest child spawn genuinely take
  the powershell.exe arm.

### D4 — scheduled canary: weekly cron, run-name marker, one docs sentence

`schedule: cron '0 5 * * 1'` (Mondays 05:00 UTC — before the CET workday). A
conditional `run-name` names the canary on schedule events only
(`github.event_name == 'schedule'`), so a scheduled failure is visually
distinguishable from PR noise in the Actions list; non-schedule events keep
the default run name (the expression yields an empty string, which GitHub
replaces with the default). One sentence lands in the product doc's
fast-iteration section. No new notification plumbing — the Actions UI/scryer
is the visibility channel (intake AC-003 says that is enough).

### D5 — what the bash suite pins vs. what only the live run proves

The bash suite (test_019..test_023, RED-first) pins the WORKFLOW SHAPE: the
new job and step names, the pinned setup-wsl usage, the control-assertion
text (sentinel 42, VERSION 1, wslpath, pwsh-not-resolvable), the
`AAI-BRANCH: WSL` assertion text, the per-leg result-floor tokens, the
schedule/run-name declarations, and every docs sentence. What only the live
windows run proves — that the arms actually PASS with WSL routing and that
the doctored context actually picks powershell.exe — is carried by
Spec-AC-01/02/03, which stay `planned` until the NAMED ps1-quality run on
this scope's PR is green; the flip-evidence contract (run URL, per-arm exit
codes, the captured `AAI-BRANCH: WSL` line, the `PESTER OK` line) is written
into each row (SPEC-0122 Spec-AC-01 pattern).

### D6 — truth maintenance in TECHNOLOGY.md

docs/TECHNOLOGY.md currently states "Real Windows-host process-cleanup
semantics are documented but NOT verified by this repo's own CI". After this
scope that sentence is false for the WSL1 delegation path. The paragraph is
rewritten truthfully: WSL1 delegation (routing, timeout 124 group-kill via
the delegated `.sh` watchdog, marker write-back across the path boundary) is
CI-verified by the `windows-wsl1` job; the Git-Bash degraded-mode tree-kill
completeness, and ALL WSL2-specific semantics (e.g. the E_ACCESSDENIED
class), remain field/manual-only (SPEC-0046 MV-1..MV-3). The 5-row matrix
itself is NOT edited (it is pinned as kept-identical across five files by
test_009/test_015); the nuance lands in the prose below it.

## L3 check (recorded)

`protected_paths_l3` in docs/ai/docs-audit.yaml (state.mjs, state-engine,
state-core, allocate-doc-number.mjs, pre-commit-checks.*, WORKFLOW.md,
CONSTITUTION.md): none is in this scope.

## Companion obligations (closed list, checked)

- Prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`): NOT touched — no
  ledger entry, no TEST-012 bump owed.
- New `.aai/**` file: NONE — no PROFILES.yaml classification owed.

## Implementation strategy
- Strategy: loop
- Rationale: the scope is CI workflow YAML, grep-shape bash pins, and docs.
  Every local TEST has a deterministic RED on the pre-change tree observable
  in seconds (the workflow carries none of the pinned tokens yet), so a
  stored-RED TDD ceremony adds nothing; the genuinely risky behavior — real
  WSL routing — cannot be executed on this macOS host under ANY strategy, and
  its proof is the named CI run that the planned-until-green AC rows gate.
  No intake-sourced implementation-mode choice exists for CHANGE-0136 (its
  intake carries no `Implementation mode (user choice):` line).

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: seven files, no protected surface, and the scope
  already sits on its own branch `feat/ps1-ci-platform-coverage`; isolation
  pays only if another ride touches ps1-quality.yml or the win-fallback suite
  concurrently. Implementation Preparation asks and decides.
- User decision: undecided
- Base ref: feat/ps1-ci-platform-coverage
- Worktree branch/path: not selected
- Inline review scope: .github/workflows/ps1-quality.yml tests/skills/test-aai-win-fallback.sh docs/product/windows-test-wrapper.md docs/TECHNOLOGY.md docs/issues/CHANGE-0136-ps1-ci-platform-coverage.md docs/specs/SPEC-0123-spec-ps1-ci-platform-coverage.md CHANGELOG.md

## Acceptance Criteria Mapping

- Maps to: CHANGE-0136 AC-001 (functional-WSL leg)
  - Spec-AC-01: the `windows-wsl1` job installs WSL1 Debian, control-asserts
    genuine WSL1 functionality, and proves wrapper routing plus all three
    selftest arms with WSL semantics, live.
  - Verification: `bash tests/skills/test-aai-win-fallback.sh 019` (shape);
    the named `ps1-quality / windows-wsl1` job on this scope's PR (live).
- Maps to: CHANGE-0136 AC-001 + AC-004 (Pester with WSL usable, per-leg discipline)
  - Spec-AC-02: the `windows-wsl1` job runs the full Pester discovery under
    Windows PowerShell 5.1 with the identical result-floor discipline and the
    single workflow-level expected-skip-count of 4.
  - Verification: `bash tests/skills/test-aai-win-fallback.sh 020 017`
    (shape + declared-once pin); the named live job.
- Maps to: CHANGE-0136 AC-002 (5.1-only leg)
  - Spec-AC-03: a `windows-5_1` step proves the powershell.exe-only fallbacks
    in a doctored child context with non-vacuous controls in both directions.
  - Verification: `bash tests/skills/test-aai-win-fallback.sh 021` (shape);
    the named `ps1-quality / windows-5_1` job on this scope's PR (live).
- Maps to: CHANGE-0136 AC-003 (scheduled canary)
  - Spec-AC-04: weekly UTC cron plus canary run-name plus the product-doc
    sentence.
  - Verification: `bash tests/skills/test-aai-win-fallback.sh 022`.
- Maps to: CHANGE-0136 AC-004 (honesty: WSL1-vs-WSL2 statements)
  - Spec-AC-05: workflow header, product doc and TECHNOLOGY.md state the
    WSL1-only coverage truthfully; CHANGELOG carries the scope's entry.
  - Verification: `bash tests/skills/test-aai-win-fallback.sh 023`.
- Maps to: CHANGE-0136 AC-005 (tests per repo conventions)
  - Spec-AC-06: new pins registered, RED-observed first, whole suite and
    registration checker green, pre-existing pins (test_009/014..018) intact.
  - Verification: `bash tests/skills/test-aai-win-fallback.sh` and
    `node .aai/scripts/check-test-registration.mjs`.

## Constitution deviations

None.

- Article 1 (Evidence before claims) — every AC names one command and one
  observable; the three rows whose real proof is a Windows run stay `planned`
  until the named CI run URL exists.
- Article 2 (Simplicity) — no new scripts, no third smoke implementation (the
  vendored selftest is reused), and the rejected alternatives are recorded in
  D1/D2 rather than built.
- Article 3 (Portability) — all new PowerShell lives in workflow step bodies
  and must run under the step's declared engine (5.1 steps avoid
  pwsh-only syntax); the bash pins stay bash-3.2-compatible like the rest of
  the suite.
- Article 4 (Degrade and report) — every control failure is a NAMED loud
  failure (setup-wsl silently broken, WSL2 masquerading as WSL1, pwsh hiding
  silently stopped working), never a silent pass into a duplicate leg.
- Article 5 (Additive first) — the existing gate and windows-5_1 semantics
  are byte-preserved except the one env-declaration move and the one added
  step; no existing assertion is loosened.
- Articles 6 and 7 — untouched.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the ps1-quality workflow runs on this scope's PR THEN a new windows-wsl1 job on windows-latest installs a WSL1 distribution (Debian) via the major-pinned Vampire/setup-wsl action and, BEFORE any wrapper claim, control-asserts that wsl -l -v reports VERSION 1, that a direct call of wsl.exe -e sh -c "exit 42" returns exactly 42, and that wsl.exe -e wslpath -a translates C:\ to a path beginning /mnt/c, failing the job loudly on any of the three; AND one real aai-run-tests.ps1 invocation captured at OS-handle level exits 0 with a stderr line matching AAI-BRANCH: WSL; AND node .aai/scripts/aai-doctor.mjs --json in that job reports CAT-15 wsl functional and CAT-14 with the success arm exit 3 and its marker file written through the payload wslpath translation, the timeout arm exit 124, the spawnfail arm exit 125 with exactly one AAI-SPAWN-ERROR line, and the success-arm diag matching AAI-BRANCH: WSL | done | run 31685736396 (https://github.com/goodwind-cz/aai/actions/runs/31685736396) green, verbatim: WSL1 CONTROLS OK: sentinel 42 + VERSION 1 + wslpath /mnt/c; WSL ROUTING OK: wrapper exit 0 with AAI-BRANCH: WSL on stderr; CAT-15 OK: wsl functional; success arm OK: exit 3, marker translated+written, diag AAI-BRANCH: WSL, AAI-TIMEOUT 60s source=env; timeout arm OK: exit 124; spawnfail arm OK: exit 125, exactly one AAI-SPAWN-ERROR with wsl.exe hidden; SELFTEST OK (WSL semantics) | — | first-ever CI execution of the wrapper WSL branch, of the e398686 marker-translation guard, and of the spawnfail decoy on a WSL-usable host |
| Spec-AC-02 | WHEN the windows-wsl1 job runs THEN it executes the same tests/skills Pester discovery the other legs run, under Windows PowerShell 5.1, with the identical result-floor discipline — FailedCount 0, FailedContainersCount 0, TotalCount at least 111, measured elapsed at most 600 seconds, one AAI-WIN-SKIP line per skipped test reconciled in both directions against the expected count — and the expected count is the single workflow-level AAI_EXPECTED_WIN_SKIP_COUNT of 4, re-derived valid for a WSL-usable host because every PosixOnly skip predicate is host-OS-driven and none is WSL-state-driven; the CHANGE-0135 host-adaptive end-to-end test passes with WSL routing inside that run | done | run 31685736396: PESTER OK (Windows PowerShell 5.1, WSL1 leg): 137 passed, 4 skipped, 0 failed, 53.89s — floor 111, ceiling 600s and skip reconciliation enforced by the same gate block as the sibling job | — | the declaration MOVES from job-level to workflow-level env so test_017's declared-exactly-once pin keeps holding across two consumer jobs |
| Spec-AC-03 | WHEN the windows-5_1 job runs THEN a new step first control-asserts pwsh IS resolvable in the undoctored parent, then spawns a child powershell.exe whose own script text sets Path to the parent PATH minus every directory containing pwsh.exe, and inside that child a control assertion fails loudly with a distinct exit code if Get-Command pwsh still resolves anything, Resolve-SelfTestEngine dot-sourced from aai-win-selftest.ps1 returns powershell, and node .aai/scripts/aai-doctor.mjs --json run in that context reports all three CAT-14 arms PASS; the step contains no Move-Item, Rename-Item or uninstall of any host file | done | run 31685736396: CONTROL OK both directions (exits 97/98 non-vacuous), Resolve-SelfTestEngine -> powershell (5.1-only fallback taken for real), all three CAT-14 arms PASS under powershell.exe, verbatim: 5.1-ONLY FALLBACK OK | — | doctored CHILD environment only — same technique class as CHANGE-0135 D3; covers the corporate powershell.exe-plus-Git-Bash-only shape since this job has no WSL |
| Spec-AC-04 | WHEN .github/workflows/ps1-quality.yml is read THEN it declares a schedule trigger with a weekly cron in UTC and a run-name expression that names the canary for schedule events only, and docs/product/windows-test-wrapper.md carries one sentence stating the weekly canary run and what a scheduled failure means (runner-image drift, not PR changes) | done | bash tests/skills/test-aai-win-fallback.sh 022 exit 0 (2026-08-13; RED first in docs/ai/tdd/red-20260813T071157Z-ps1-ci-platform-coverage.log, GREEN in docs/ai/tdd/green-20260813T071611Z-ps1-ci-platform-coverage.log); cron '0 5 * * 1' plus schedule-conditioned run-name declared; first scheduled EVENT after merge (RR-1, shape-pinned) | — | no notification plumbing — Actions UI and the morning scryer are the visibility channel |
| Spec-AC-05 | WHEN the docs are read THEN the workflow header states that GitHub-hosted runners cannot run WSL2 (no nested virtualization) and the leg therefore proves WSL1 only, docs/product/windows-test-wrapper.md states the WSL1-coverage caveat naming WSL2-specific failures such as the E_ACCESSDENIED class as remaining field-only, docs/TECHNOLOGY.md replaces its now-stale not-verified-by-CI sentence with the truthful statement that WSL1 delegation is CI-verified while Git-Bash degraded-mode kill completeness and WSL2 semantics stay manual, the 5-row matrix itself byte-unchanged, and CHANGELOG.md carries one unreleased heading entry for this scope | done | bash tests/skills/test-aai-win-fallback.sh 023 exit 0 and full suite exit 0 incl. test_009/test_015 matrix pins (2026-08-13, GREEN log docs/ai/tdd/green-20260813T071611Z-ps1-ci-platform-coverage.log); matrix rows byte-unchanged (git diff shows only the prose paragraph replaced) | — | test_009 and test_015 pin the matrix concepts across five files — the nuance lands in prose below the matrix, never inside it |
| Spec-AC-06 | WHEN the repository hygiene commands run THEN every new test function is registered in ALL_TESTS and reported clean by check-test-registration.mjs, each new pin was observed failing on the pre-change tree before implementation (RED-first, recorded in the implementation evidence), the whole test-aai-win-fallback.sh suite passes including the unmodified test_009 and test_014 through test_018 pins, and test_017 still finds the expected-skip-count declared exactly once | done | RED recorded for all five new pins on the pre-change tree (docs/ai/tdd/red-20260813T071157Z-ps1-ci-platform-coverage.log, each exit 1 naming the missing contract); full suite 007..023 exit 0 and check-test-registration.mjs exit 0 (docs/ai/tdd/green-20260813T071611Z-ps1-ci-platform-coverage.log) | — | strategy is loop — the RED observation is recorded, storage optional |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:

- `.github/workflows/ps1-quality.yml` —
  - `env: AAI_EXPECTED_WIN_SKIP_COUNT: "4"` moves from the windows-5_1 job to
    the workflow level (comment moves with it, gaining the "both windows jobs
    consume it; test_017 pins the single declaration" sentence).
  - `on:` gains `schedule: [{cron: '0 5 * * 1'}]`; a top-level `run-name`
    expression marks schedule events as the weekly image-drift canary and
    yields the default name otherwise.
  - Header comment gains the three-blind-spots note, the WSL1-vs-WSL2
    statement (hosted runners: no nested virtualization, hence WSL1-only
    coverage), and one canary sentence.
  - New job `windows-wsl1` (runs-on windows-latest): checkout; the pinned
    `Vampire/setup-wsl` step (`wsl-version: 1`, `distribution: Debian`);
    a control step (VERSION 1 + sentinel 42 + wslpath, D1); a routing step
    that runs the real wrapper once via Start-Process with OS-handle stream
    capture and asserts exit 0 plus `AAI-BRANCH: WSL` on stderr; a selftest
    step that runs `node .aai/scripts/aai-doctor.mjs --json` (node child —
    plain shell redirection is already OS-handle capture) and asserts CAT-15
    wsl functional plus each CAT-14 arm by name and exit code with the
    success diag matching WSL; the Pester cache/install pair for 5.1 (same
    shape as the existing job, distinct cache key discriminator); the full
    Pester discovery step under `shell: powershell` with `timeout-minutes:
    15` and the identical floor/ceiling/skip-reconciliation block.
  - New step in `windows-5_1` (after the real-wrapper smokes): the 5.1-only
    doctored-child context of D3.
- `tests/skills/test-aai-win-fallback.sh` — new `test_019` (WSL-leg shape),
  `test_020` (WSL-leg Pester discipline + workflow-level declaration
  position), `test_021` (5.1-only step shape incl. the no-host-mutation
  negative pin), `test_022` (canary), `test_023` (honesty docs); all added to
  `ALL_TESTS`; test_017's comment updated for the declaration move (its
  assertions unchanged).
- `docs/product/windows-test-wrapper.md` — the fast-iteration section gains
  the canary sentence; a short "What CI proves per platform" note gains the
  WSL1 caveat (WSL2-specific failures such as E_ACCESSDENIED remain
  field-only) and the 5.1-only context.
- `docs/TECHNOLOGY.md` — the paragraph under the matrix is rewritten
  truthfully per D6; the matrix rows are byte-unchanged.
- `CHANGELOG.md` — one `## [unreleased] — <title>` heading entry.

Data flows and edge cases:

- The `AAI-BRANCH` diagnostic is written via `[Console]::Error` — it is
  invisible to an in-process `2>`; every assertion on it must capture a REAL
  child's stderr (Start-Process redirect for the wrapper invocation; for the
  doctor, node is already a separate process so shell redirection suffices).
- Fixture/marker paths crossing into WSL: Windows env vars do not propagate
  into WSL without WSLENV, and Windows paths are meaningless to POSIX sh —
  which is exactly why the leg reuses the selftest arms (payload-embedded
  `command -v wslpath` translation) instead of the existing raw smoke
  fixtures, whose `$AAI_SMOKE_MARKER_FILE` contract would silently arrive
  empty inside WSL.
- The spawnfail arm on a WSL-usable host only reaches the decoy because the
  selftest's reduced PATH hides wsl.exe (e398686) — a regression there makes
  the arm route through WSL and FAIL on the marker-must-not-exist check,
  which is the desired loud signal.
- setup-wsl or the Debian download flaking: bounded by the job's
  timeout-minutes; the control step converts a half-broken install into a
  named failure, never into silently-Git-Bash coverage.
- The reduced 5.1-only PATH must keep node and git resolvable — the filter
  removes ONLY directories containing pwsh.exe.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description | Status |
|----------|------------|-------------|-----------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-win-fallback.sh   | test_019 shape pin: the workflow carries a windows-wsl1 job naming Vampire/setup-wsl with an @v major pin, wsl-version 1 and distribution Debian, the exit-42 sentinel control, the VERSION 1 assertion, the wslpath /mnt/c control, an OS-handle-captured wrapper invocation asserting AAI-BRANCH: WSL, and an aai-doctor.mjs --json step asserting the three arm names with exit codes 3, 124 and 125. Command: bash tests/skills/test-aai-win-fallback.sh 019 | green |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-win-fallback.sh   | test_020 discipline pin: the windows-wsl1 Pester step runs Invoke-Pester over tests/skills under shell powershell with timeout-minutes 15, the TotalCount floor of 111, the 600 second ceiling, the AAI-WIN-SKIP two-direction reconciliation, and the AAI_EXPECTED_WIN_SKIP_COUNT declaration sits at WORKFLOW level (before the jobs key) while test_017's declared-exactly-once and count-equals-actual pins still pass. Command: bash tests/skills/test-aai-win-fallback.sh 020 017 | green |
| TEST-003 | Spec-AC-03 | unit        | tests/skills/test-aai-win-fallback.sh   | test_021 shape pin: the windows-5_1 job carries the 5.1-only step with the undoctored-parent pwsh-resolvable control, the child-side Get-Command pwsh must-not-resolve control with a distinct exit code, the Resolve-SelfTestEngine powershell assertion, the aai-doctor.mjs --json CAT-14 arm assertions, and the step body contains neither Move-Item nor Rename-Item. Command: bash tests/skills/test-aai-win-fallback.sh 021 | green |
| TEST-004 | Spec-AC-04 | unit        | tests/skills/test-aai-win-fallback.sh   | test_022 canary pin: the workflow declares a schedule trigger with a weekly cron, a run-name expression conditioned on the schedule event naming the canary, and docs/product/windows-test-wrapper.md carries the canary sentence. Command: bash tests/skills/test-aai-win-fallback.sh 022 | green |
| TEST-005 | Spec-AC-05 | unit        | tests/skills/test-aai-win-fallback.sh   | test_023 honesty pin: the workflow header states the no-nested-virtualization WSL2 limitation, the product doc names the WSL1-coverage caveat with the E_ACCESSDENIED class as field-only, docs/TECHNOLOGY.md carries the WSL1-CI-verified sentence and no longer claims the WSL path is unverified by CI, and CHANGELOG.md carries the scope's unreleased heading. Command: bash tests/skills/test-aai-win-fallback.sh 023 | green |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-win-fallback.sh   | Whole-suite regression plus registration: all of test_007 through test_023 pass together (pre-existing matrix, smoke, Pester and skip-budget pins intact after the workflow edit) and the registration checker reports the new functions clean. Commands: bash tests/skills/test-aai-win-fallback.sh and node .aai/scripts/check-test-registration.mjs | green |
| TEST-007 | Spec-AC-01 | e2e         | .github/workflows/ps1-quality.yml       | Live proof on this scope's PR: the named windows-wsl1 job is green end-to-end — controls, routing line AAI-BRANCH: WSL, all three doctor arms PASS with WSL semantics. Command: gh run view for the named run, per-step logs excerpted into the Spec-AC-01 evidence cell | pending |
| TEST-008 | Spec-AC-02 | e2e         | .github/workflows/ps1-quality.yml       | Live proof: the windows-wsl1 Pester step prints its PESTER OK line with FailedCount 0, the pinned skip count 4 reconciled, TotalCount at or above the floor and elapsed under the ceiling, on the same named run. Command: gh run view for the named run | pending |
| TEST-009 | Spec-AC-03 | e2e         | .github/workflows/ps1-quality.yml       | Live proof: the windows-5_1 job's 5.1-only step is green — both controls held and all three CAT-14 arms PASS under powershell.exe with pwsh unresolvable in the doctored child. Command: gh run view for the named run | pending |

Test status values: pending -> red -> green

## Seams crossed

- SEAM-1 — setup-wsl's installed distro versus `Test-WslUsable`'s functional
  probe: the control step asserts the probe's OWN sentinel semantics plus the
  WSL VERSION, so a silent install failure or a WSL2 surprise is a named leg
  failure, never a silent duplicate of Git Bash coverage. Crossed live by
  TEST-007.
- SEAM-2 — a Windows marker path crossing into WSL's POSIX sh: crossed by
  the selftest success arm's payload wslpath translation, executed for real
  for the first time (TEST-007); the alternative (reusing the raw smoke
  fixtures with `$AAI_SMOKE_MARKER_FILE`) was rejected because WSL drops
  un-WSLENV'd Windows env vars, which would make the assertion vacuously
  fail.
- SEAM-3 — the single `AAI_EXPECTED_WIN_SKIP_COUNT` declaration now feeds
  TWO consumer jobs AND test_017's declared-exactly-once pin: crossed by
  TEST-002 (which reruns test_017) and TEST-006.
- SEAM-4 — the doctored 5.1-only PATH versus everything the child still
  needs (node, git, the dispatcher's own Git Bash resolution): the filter is
  surgical (pwsh.exe directories only) and both control assertions bracket
  it. Crossed by TEST-003 and live by TEST-009.
- SEAM-5 — the run-name expression versus the GitHub event context: only the
  shape is pinnable locally; the first scheduled event fires after merge
  (RR-1). Crossed by TEST-004 for shape.
- SEAM-6 — the TECHNOLOGY/product-doc truth statements versus the
  pre-existing cross-file identity pins (test_009, test_015, test_018): the
  matrix stays byte-identical and the nuance lands in prose; TEST-006 reruns
  the whole suite to prove it.

## Residual risks (accepted)

- RR-1 — the cron EVENT cannot be observed before merge; its shape is pinned
  and the first Monday run is the live proof. Accepted: the failure mode is
  "canary silently absent", which the shape pin bounds to expression-level
  mistakes.
- RR-2 — WSL2 semantics (E_ACCESSDENIED class and friends) remain field-only
  by platform impossibility; documented in three places rather than covered.
- RR-3 — the wrapper's WSL-BRANCH spawn-failure path (Invoke-ViaWsl catch,
  exit 125) stays proven by unit mocks only: on a WSL-usable host the
  probe-first design makes a real WSL-branch spawn failure practically
  unconstructible without host mutation. The live spawnfail arm proves the
  125 contract via the decoy Git Bash branch with wsl.exe hidden — which is
  itself the live regression proof of the PR #249 decoy-PATH fix.
- RR-4 — Vampire/setup-wsl is a third-party action: pinned by major; a broken
  release fails the canary/PR leg loudly and blocks nothing downstream (the
  vendored product is unchanged by this scope).
- RR-5 — a per-leg divergence in future skip counts would demand per-leg
  declarations; today's equality is re-derived and pinned, not assumed
  (test_017 equality catches count drift the moment it lands).

## Verification

Commands to run:

- `bash tests/skills/test-aai-win-fallback.sh` (all, incl. the five new pins)
- `bash tests/skills/test-ps1-quality.sh` (local Pester + parse gate stay green)
- `node .aai/scripts/check-test-registration.mjs`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0123-spec-ps1-ci-platform-coverage.md`
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- `gh workflow run ps1-quality.yml` then `gh run watch` / `gh run view` — the
  named run on this scope's PR (windows-wsl1 AND windows-5_1 green)

Evidence artifacts: full stdout with exit codes for every command above; the
recorded RED observation for each new bash pin on the pre-change tree; the
named CI run URL with per-step excerpts copied into the Spec-AC-01/02/03
evidence cells.

PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.
Spec-AC-01, Spec-AC-02 and Spec-AC-03 may only reach `done` once the named
ps1-quality run on this scope's PR is green with the demanded lines captured;
until then they stay `planned`, which blocks PASS by design.

## Evidence contract

For each implementation, validation, and code review artifact, record:
- ref_id
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

### Evidence by strategy

Strategy is `loop`: per-TEST-xxx green runs with the RED observation recorded
(each new bash pin run against the pre-change tree and seen failing) — stored
RED artifacts are optional. The three e2e rows' evidence is the named CI run
URL plus the excerpted step output.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
