---
id: spec-aai-update-temp-toctou
type: spec
number: 52
status: done
ceremony_level: 1
links:
  issue: aai-update-temp-toctou
  rfc: null
  pr:
    - 104
  commits:
    - dfa9b10
---

# SPEC — aai-update temp-dir TOCTOU: retain the mktemp parent, clone into a subdir (ISSUE-0012)

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0012-aai-update-temp-toctou.md (issue, ref_id `aai-update-temp-toctou`)
- Origin finding: docs/ai/reviews/review-20260716-120448.md NB-2 (PR #67 post-merge review)
- Related prior art: SPEC-0020 (anonymous-clone fallback / canonical-repo seam this fix must not regress)
- Technology contract: docs/TECHNOLOGY.md
- Expected merged display id: SPEC-0052 (cross-branch collision check: local max SPEC-0051; reservation refs `refs/aai/docnums/SPEC-*` max SPEC-0051; 0052 free at freeze time)

## Ceremony level

`ceremony_level: 1` (small single-surface fix). Honest reasoning:
- NOT level 0: this is a behavior change to executable code (the temp-dir
  lifecycle), not typo/docs-only.
- NOT level 2: the change is a single LOGICAL surface — the source-clone
  temp-dir lifecycle — expressed in two sibling twins (`aai-update.sh` +
  `aai-update.ps1`) that must stay in parity, plus their tests. No engine,
  allocator, guard, state-schema, or workflow-canon change. Both updater
  scripts are behavior-preserving on every path EXCEPT the temp-dir lifecycle.
- NOT level 3: verified neither `.aai/scripts/aai-update.sh` nor
  `.aai/scripts/aai-update.ps1` appears in `protected_paths_l3`
  (docs/ai/docs-audit.yaml: state.mjs, state-engine.mjs, state-core.mjs,
  allocate-doc-number.mjs, pre-commit-checks.{sh,ps1}, WORKFLOW.md,
  CONSTITUTION.md). No protected path is touched.

Ceremony justification: security-correctness fix to two sibling updater scripts
(sh + ps1) + parity + tests; single temp-dir-lifecycle surface; no
engine/protected-path change (L1). Security class is honored WITHIN the lean
lane: validation must adversarially re-check the ownership/lifecycle invariant
(the mktemp parent is never freed-and-recreated mid-run; the clone target is
always a subdirectory of it), not merely re-run the suite. Review may
re-classify upward.

## Problem (WHAT is broken)

`aai-update.sh` creates a securely-owned temp dir with `mktemp -d` (sh:84), then
in each of the three clone attempts `rm -rf "$TMP"` (sh:89, 93, 102) and lets
`gh`/`git clone` non-atomically RECREATE the same path (sh:90, 94, 104). This
discards mktemp's ownership guarantee: on a shared multi-user host with a
world-writable `$TMPDIR`, a local attacker watching the freed path can win the
`rm`→`clone` window, recreate it as a dir they own, receive the clone, and swap
`aai-sync.sh` before the updater EXECUTES it (`bash "$SYNC" "$TARGET"`, sh:129)
— arbitrary code execution. `aai-update.ps1` has the analog shape (ps1:79 path,
ps1:84/89/99 wipes, ps1:126 execution); lower exposure because Windows
`GetTempPath()` is per-user, but parity is required.

## Frozen fix shape (the exact temp-dir lifecycle — sh + ps1)

### Bash (`aai-update.sh`)
1. KEEP `TMP="$(mktemp -d "${TMPDIR:-/tmp}/aai-src.XXXXXX")"` (sh:84) as the
   securely-owned PARENT for the whole run. It is NEVER `rm -rf`'d-and-recreated
   mid-run.
2. Introduce a clone-target SUBDIRECTORY of the parent, `SRCDIR="$TMP/src"`.
   Every clone attempt targets `$SRCDIR`, never `$TMP`.
3. Per-attempt wipe removes ONLY the subdirectory: replace each `rm -rf "$TMP"`
   (sh:89, 93, 102) with `rm -rf "$SRCDIR"` (partial-clone cleanup before retry;
   git still refuses a non-empty target, so the wipe is retained — just scoped
   to the subdir). The parent `$TMP` stays owned by the invoking user throughout.
4. `SRC="$SRCDIR"` instead of `SRC="$TMP"` (sh:111). `SYNC="$SRC/.aai/scripts/aai-sync.sh"`
   (sh:125) now resolves to `$TMP/src/.aai/...`; the executed sync runs from
   inside the securely-owned parent — the ownership-swap window is closed by
   construction.
5. Cleanup trap (sh:37-41) still `rm -rf "$TMP"` on exit — removes the whole
   parent (incl. `src`), unchanged. `--keep-temp` still retains `$TMP` (now
   including `src`) for inspection.
6. UNCHANGED paths: dry-run (never creates `$TMP` — mktemp is inside the
   `DRY_RUN != 1` block), the local-checkout branch (sh:75-80, `SRC=` the
   existing checkout, no temp used), exit codes (2/3/4), the 1..3 anonymous-clone
   cascade, and the GIT_TERMINAL_PROMPT=0 guard.

### PowerShell (`aai-update.ps1`, identical shape / parity)
1. `$Tmp = Join-Path (GetTempPath) ("aai-src-" + GetRandomFileName())` (ps1:79)
   is now the retained PARENT. Explicitly CREATE it once as a directory
   (`New-Item -ItemType Directory -Path $Tmp -Force | Out-Null`) so the parity
   with mktemp's "owned parent that already exists" holds (Windows per-user
   `%TEMP%` is not world-writable — see residual RR-1).
2. `$SrcDir = Join-Path $Tmp 'src'` is the clone target for all three attempts.
3. Each per-attempt wipe (ps1:84, 89, 99) removes ONLY `$SrcDir`
   (`if (Test-Path $SrcDir) { Remove-Item -Recurse -Force $SrcDir ... }`), never
   `$Tmp`.
4. `$Src = $SrcDir` instead of `$Src = $Tmp` (ps1:109). `$Sync = Join-Path $Src
   ".aai/scripts/aai-sync.ps1"` (ps1:122) resolves within the owned parent.
5. `finally` cleanup (ps1:155-158) still `Remove-Item -Recurse -Force $Tmp`
   (whole parent), unchanged; `-KeepTemp` retains `$Tmp`.
6. UNCHANGED: dry-run, local-checkout branch (ps1:69-74), exit codes, cascade.

### Explicitly OUT OF SCOPE
- The self-relocation copy at sh:22 (`mktemp "${TMPDIR:-/tmp}/aai-update.XXXXXX"`,
  a mktemp FILE that is written and immediately `exec`'d) is NOT the reported
  vulnerability: it is a securely-owned mktemp file used directly, never
  `rm`'d-and-recreated, so it has no rm→recreate ownership-swap window. The
  review NB-2 and ISSUE-0012 target only the source-clone `$TMP`. Left unchanged.

## Deltas

(omitted — this change alters no canonical `REQ-*` requirement; it is a security
correctness fix to updater scripts.)

## Constitution deviations

None. (No docs/CONSTITUTION.md article is engaged: no protected surface, no
state-schema change, no merge/close-gate change; the fix strengthens an existing
security property without altering workflow canon.)

## Acceptance Criteria Mapping

- Maps to: ISSUE-0012 AC-001
  Spec-AC-01: In `aai-update.sh`, the `mktemp -d` parent (`$TMP`) is retained
  for the whole run and is NEVER `rm -rf`'d-and-recreated between attempts; every
  clone/retry targets a fresh SUBDIRECTORY (`$TMP/src`); only that subdirectory is
  wiped between attempts; the executed sync path resolves within the retained
  parent.
  Verification: static assertions on the script — the clone commands' target
  argument is `$SRCDIR`/`"$TMP/src"` (never bare `$TMP`); no mid-run `rm -rf "$TMP"`
  in the clone cascade (only the exit-trap `rm -rf "$TMP"` remains); per-attempt
  wipe targets `$SRCDIR`. Plus `bash -n aai-update.sh` exit 0. These assertions
  FAIL on the current (unfixed) script (genuine RED).

- Maps to: ISSUE-0012 AC-002
  Spec-AC-02: `aai-update.ps1` gets the identical retain-parent / clone-into-subdir
  shape — `$Tmp` created once and retained; clone target `$SrcDir = $Tmp/src`;
  per-attempt wipe scoped to `$SrcDir`; `$Src = $SrcDir`.
  Verification: static assertions on the ps1 (clone target is `$SrcDir`; no
  `Remove-Item ... $Tmp` in the attempt cascade; `$Tmp` explicitly created as a
  directory) + `[Parser]::ParseFile` clean. FAIL on the current ps1 (genuine RED).

- Maps to: ISSUE-0012 AC-003
  Spec-AC-03: Behavior is unchanged on the happy path and the anonymous-clone
  fallback — a real clone still succeeds and lands the repo at the subdir; the
  sync still executes; `--keep-temp`/`-KeepTemp` still retains the temp tree;
  dry-run, the canonical-repo guard (exit 2), and exit codes are unchanged;
  `bash -n` / pwsh parse clean; the existing `aai-update.Tests.ps1` cases stay
  green.
  Verification: happy-path dry-run exit 0 + "Would run" line; a real clone against
  a local `file://` fixture repo lands `.aai/scripts/aai-sync.sh` at `$TMP/src`
  and the parent `$TMP` remains present and owned by the invoker (`--keep-temp`
  inspection); existing Pester suite green.

## Implementation plan
- Components affected: `.aai/scripts/aai-update.sh`, `.aai/scripts/aai-update.ps1`
  (temp-dir lifecycle only); NEW `tests/skills/test-aai-update.sh`; extend
  `tests/skills/aai-update.Tests.ps1`.
- Data flow: mktemp parent (owned) → `$TMP/src` clone target (wiped per attempt)
  → `SRC=$TMP/src` → `SYNC=$SRC/.aai/scripts/aai-sync.sh` executed → exit-trap
  removes `$TMP`.
- Edge cases: first attempt (`$TMP/src` absent — `rm -rf` no-op, git creates it);
  retry after partial clone (`$TMP/src` present — wiped, re-cloned); dry-run
  (parent never created); local-checkout branch (no temp); `--keep-temp`
  (parent + src retained). git clone requires an existing parent dir — `$TMP`
  (mktemp -d) satisfies this; git creates only the leaf `src`.

## Seam analysis
- SEAM-1: `aai-update` → the CLONED, then EXECUTED `aai-sync.sh` (sh:129 /
  ps1:126). The fix relocates the execution root from `$TMP` to `$TMP/src`. This
  seam MUST be crossed end-to-end by an integration test: produce a real clone
  on one side (into the subdir) and assert the sync actually executes from it on
  the other — covered by TEST-005 (sh) / TEST-009 (ps1), a `file://` fixture
  clone with `--keep-temp` verifying the repo materialized at `$TMP/src` and the
  sync ran. Not two mocked unit halves.
- No DB/shared-record seams (shell updater; no persistence surface).
- Residual (RR-1): the REAL multi-user race timing (an attacker winning the
  rm→clone window on a hostile shared host) is NOT reproducible in single-user
  CI. The structural fix CLOSES the window by construction (the owned parent is
  never freed/recreated), so the static lifecycle assertions are the meaningful
  gate; the timing race is an unobservable-in-CI documented residual.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                 | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | sh: mktemp parent retained; clone into `$TMP/src`; only subdir wiped        | done | TEST-001/002 RED docs/ai/tdd/red-20260717T232118Z-aai-update-temp-toctou-test001-002.log -> GREEN docs/ai/tdd/green-20260717T232500Z-aai-update-temp-toctou-test001-005.log; TEST-003/004/005 same GREEN log | — | — |
| Spec-AC-02 | ps1 parity: same retain-parent / clone-into-subdir shape                    | done | TEST-006/007 RED docs/ai/tdd/red-20260717T233000Z-aai-update-temp-toctou-test006-007.log -> GREEN docs/ai/tdd/green-20260717T233500Z-aai-update-temp-toctou-test006-010.log; TEST-008 covered by pre-existing parse test | — | — |
| Spec-AC-03 | behavior unchanged (happy path, fallback, --keep-temp, dry-run, parse, Pester) | done | TEST-004/005/009/010 green; full regression docs/ai/tdd/refactor-20260717T234500Z-aai-update-temp-toctou.log (bash -n, sh suite, ps1 Pester incl. 4 pre-existing cases, ps1-quality gate incl. PSScriptAnalyzer 5.1+7.0) | — | — |

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                | Description                                                                                          | Status  |
|----------|------------|------|-------------------------------------|------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-update.sh     | Static: clone-target argument in all three attempts is `"$TMP/src"`/`$SRCDIR`, never bare `$TMP` (RED on current) | green |
| TEST-002 | Spec-AC-01 | unit | tests/skills/test-aai-update.sh     | Static: no mid-run `rm -rf "$TMP"` in the clone cascade — only the exit-trap removes `$TMP`; per-attempt wipe targets `$SRCDIR` (RED on current) | green |
| TEST-003 | Spec-AC-01 | unit | tests/skills/test-aai-update.sh     | `bash -n aai-update.sh` exits 0 (parse clean)                                                         | green |
| TEST-004 | Spec-AC-03 | unit | tests/skills/test-aai-update.sh     | Happy-path dry-run: `aai-update.sh --force --dry-run` exit 0 + "Would run" line (no-regression)       | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-update.sh | SEAM-1: real clone from a local `file://` fixture repo with `--keep-temp` → repo materializes at `$TMP/src`, parent `$TMP` retained and owned by invoker, sync executes (skips cleanly if git unavailable) | green |
| TEST-006 | Spec-AC-02 | unit | tests/skills/aai-update.Tests.ps1   | Static: ps1 clone-target is `$SrcDir` (`$Tmp/src`), never bare `$Tmp`; `$Tmp` created once as a directory (RED on current) | green |
| TEST-007 | Spec-AC-02 | unit | tests/skills/aai-update.Tests.ps1   | Static: no `Remove-Item ... $Tmp` in the attempt cascade; per-attempt wipe targets `$SrcDir` (RED on current) | green |
| TEST-008 | Spec-AC-02 | unit | tests/skills/aai-update.Tests.ps1   | `[Parser]::ParseFile` clean (existing "parses" case retained/extended)                               | green |
| TEST-009 | Spec-AC-03 | integration | tests/skills/aai-update.Tests.ps1 | SEAM-1 parity: `file://` fixture clone with `-KeepTemp` → clone at `$Tmp/src`, `$Tmp` retained (skips if git/pwsh unavailable) | green |
| TEST-010 | Spec-AC-03 | unit | tests/skills/aai-update.Tests.ps1   | Existing Pester regression cases (canonical-repo guard exit 2, dry-run Would-run, flag parity, unknown-arg warn) stay green | green |

RED-proof obligation: TEST-001, TEST-002 (sh) and TEST-006, TEST-007 (ps1) are
the AC-gating static-lifecycle assertions and MUST be observed FAILING against
the current (unfixed) scripts before their green counts as evidence — the
current scripts genuinely violate them (`rm -rf "$TMP"` mid-run; clone target is
bare `$TMP`). TEST-003/004/005/008/009/010 are regression guards that pass on the
current scripts (no RED expected); they gate "behavior unchanged," not the fix
itself.

## Verification
- `bash tests/skills/test-aai-update.sh` (via `.aai/scripts/aai-run-tests.sh`) — all pass.
- `pwsh -NoProfile -Command "Invoke-Pester tests/skills/aai-update.Tests.ps1"` — all pass
  (or clean skip where git/pwsh unavailable, per the existing test-ps1-quality.sh gate).
- `bash -n .aai/scripts/aai-update.sh` → exit 0; `[Parser]::ParseFile` on the ps1 → no errors.
- Adversarial re-check (validation, security class): confirm by reading the diff that
  the mktemp parent is never freed/recreated mid-run and every clone target is a
  subdir of it.
- PASS criteria: all TEST-xxx green (AC-gating ones RED-proven first) AND all Spec-AC terminal.

## Evidence contract
Per implementation/validation/TDD/review artifact record: ref_id
(`aai-update-temp-toctou`), Spec-AC + TEST-xxx links, command or review scope,
exit code or verdict, evidence path (docs/ai/tdd/*, tests/skills/results/*,
docs/ai/reviews/*), commit SHA / diff range.

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD lane for the AC-gating static-lifecycle assertions
  (TEST-001/002/006/007) which have a genuine RED against the current scripts —
  security class demands the RED that proves the current code is vulnerable and
  the fix closes it. Loop lane for the regression guards
  (TEST-003/004/005/008/009/010), which pass on the current scripts and cannot
  RED; they exist to prove "behavior unchanged" and are simple wiring.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: small, single logical surface (temp-dir lifecycle) across
  two sibling scripts + tests; behavior-preserving except the lifecycle; no
  protected path, no cross-cutting refactor. Operator already recorded
  `user_decision: inline` for this wave (branch fix/aai-update-temp-toctou).
- User decision: inline (operator-approved wave, already in STATE)
- Base ref: main
- Inline review scope: `.aai/scripts/aai-update.sh`, `.aai/scripts/aai-update.ps1`,
  `tests/skills/test-aai-update.sh`, `tests/skills/aai-update.Tests.ps1`

- code_review.required: true — security-class code change; L1 requires a single
  dual-verdict review. Scope = the four paths above.
