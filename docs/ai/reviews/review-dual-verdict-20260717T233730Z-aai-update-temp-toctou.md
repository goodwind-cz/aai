---
review: dual-verdict
scope: ISSUE-0012 / SPEC-0052 — aai-update temp-dir TOCTOU fix
base_ref: main
branch: fix/aai-update-temp-toctou
lane: lightweight / L1 (SECURITY-class)
reviewer: AAI Code Review (single dual-verdict, SPEC-0021)
timestamp: 20260717T233730Z
---

```yaml
review:
  scope: "git diff main -- .aai/scripts/aai-update.sh .aai/scripts/aai-update.ps1 tests/skills/test-aai-update.sh tests/skills/aai-update.Tests.ps1 docs/specs/SPEC-0052-*.md docs/issues/ISSUE-0012-*.md"
  spec: docs/specs/SPEC-0052-spec-aai-update-temp-toctou.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/aai-update.sh:85-86,94,98,107,116 + TEST-001/002/003 (test-aai-update.sh) green" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/aai-update.ps1:80-82,90-91,95-96,105-107,115 + TEST-006/007/008 (aai-update.Tests.ps1) green" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "sh:39 trap unchanged / ps1:162 finally unchanged; dry-run sh:120-128 & ps1:118-126; exit 2/3/4 unchanged; TEST-004/005/009/010 green (ran, not skipped)" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "the real multi-user attacker race on a hostile shared host with world-writable $TMPDIR",
        closes_with: "a hostile-host timing harness (RR-1, unobservable in single-user CI); structural closure verified instead — see below" }
  overall: pass
```

## Scope

Read-only review of the uncommitted diff vs `main` on branch
`fix/aai-update-temp-toctou` (working tree holds the change; inspected with
`git diff main -- <paths>`). Frozen spec: SPEC-0052 (`SPEC-FROZEN: true`),
requirement ISSUE-0012.

No orchestrator coaching to record: the dispatch named the fix shape (from the
frozen spec) but did not pre-rate severity or scope-exclude any area; I reviewed
the full diff independently.

## Verdict 1 — spec_compliance: PASS

AC table walk (every Spec-AC row in SPEC-0052 §Acceptance Criteria Status):

- **Spec-AC-01 (sh: retain mktemp parent; clone into `$TMP/src`; wipe only subdir)
  — compliant.** `TMP="$(mktemp -d …)"` (sh:85) is unchanged as the owned parent;
  `SRCDIR="$TMP/src"` (sh:86) is the clone target for all three attempts
  (sh:95, 99, 109). Each per-attempt wipe is `rm -rf "$SRCDIR"` (sh:94, 98, 107)
  — the parent is never `rm -rf`'d mid-run. `SRC="$SRCDIR"` (sh:116) so
  `SYNC="$SRC/.aai/scripts/aai-sync.sh"` (sh:130) resolves inside the owned
  parent. The only remaining `rm -rf "$TMP"` in the file is the exit-trap
  (sh:39). Evidence: TEST-001/002/003 green; RED proof
  `docs/ai/tdd/red-20260717T232118Z-…test001-002.log`. Re-ran the suite: 5/5 PASS.

- **Spec-AC-02 (ps1 parity) — compliant.** `$Tmp` created once as a directory
  (`New-Item -ItemType Directory -Path $Tmp -Force`, ps1:81); `$SrcDir = Join-Path
  $Tmp 'src'` (ps1:82) is the clone target for all three attempts (ps1:91, 96,
  107); each per-attempt wipe is `Remove-Item … $SrcDir` guarded by `Test-Path`
  (ps1:90, 95, 105); `$Src = $SrcDir` (ps1:115). The only `Remove-Item … $Tmp` is
  the `finally` block (ps1:163). Evidence: TEST-006/007 green; RED proof
  `docs/ai/tdd/red-20260717T233000Z-…test006-007.log`. Re-ran the Pester file:
  9/9 PASS (TEST-006/007/009 all green).

- **Spec-AC-03 (behavior unchanged) — compliant.** Exit-trap (sh:38-42) and
  `finally` (ps1:161-165) still remove the whole `$TMP`/`$Tmp` (incl. `src`);
  `--keep-temp`/`-KeepTemp` still retains the whole tree. Dry-run never creates
  the temp dir (mktemp/New-Item are inside the `DRY_RUN != 1` block; in dry-run
  `SRCDIR`/`$SrcDir` stay empty/null and `SRC` is unused because the dry-run block
  exits first). Canonical-repo guard (exit 2), exit 3 (fetch failure), exit 4
  (missing sync) unchanged. Evidence: TEST-004 (dry-run + negative control),
  TEST-005a/b (file:// clone happy path + failed-cascade exit 3, no stray
  `$SRCDIR`), TEST-009 (ps1 file:// parity), TEST-010 (4 pre-existing regression
  cases) — all green in my re-run. `bash -n` exit 0; `[Parser]::ParseFile` clean
  (ps1 "parses" case green).

TEST-xxx existence/pass check: all ten TEST ids claimed in the spec exist in the
two test files and pass. Referenced TDD logs (red/green/refactor) are all present
under `docs/ai/tdd/`. No deviation from the frozen spec found.

## Verdict 2 — code_quality: PASS

No BLOCKING or NON-BLOCKING findings. Specific-attention items judged
independently:

1. **`$TMP/src` creation window on the parent.** The subdir is created by
   `git clone` (leaf), not pre-`mkdir`'d — this is correct and stronger than a
   pre-mkdir: the parent `$TMP` is `mktemp -d` (mode 0700, invoker-owned) and is
   never removed until cleanup, so no other user can create/pre-seed `$TMP/src`
   inside it. No window on the parent. First attempt: `rm -rf "$SRCDIR"` is a
   no-op (absent), git creates it — fine.

2. **Cascade `rm -rf "$SRCDIR"` safety.** `SRCDIR="$TMP/src"` is always strictly
   inside `$TMP`, always double-quoted, `set -u` active. `TMP` is guaranteed set:
   `mktemp -d` runs under `set -e`, so a mktemp failure exits before `SRCDIR` is
   assigned. Even a hypothetical empty `TMP` yields `SRCDIR="/src"`, never `""`
   or `"/"` — no `rm -rf ""` / `rm -rf "/"` risk. Sound.

3. **ps1 `New-Item -Force` / `Remove-Item` when absent.** `$Tmp` comes from
   `GetRandomFileName()` (collision-negligible), so `New-Item -Force` effectively
   creates fresh; `-Force` means an existing empty dir would not error. This is a
   deliberate, spec-acknowledged deviation from mktemp's atomic-exclusive create
   (RR-1: Windows `%TEMP%` is per-user, not world-writable) — acceptable.
   `Remove-Item $SrcDir` is guarded by `if (Test-Path $SrcDir)` AND
   `-ErrorAction SilentlyContinue`, so an absent target never errors.

4. **Executed sync path.** `bash "$SYNC"` / `& $Sync` resolve to
   `$TMP/src/.aai/scripts/aai-sync.{sh,ps1}`, existence-checked (`-f` / `Test-Path`)
   before execution, and run from inside the owned parent — the ownership-swap
   window is closed by construction.

5. **`--keep-temp` + exit trap.** Cleanup/`finally` operate on the whole
   `$TMP`/`$Tmp` (parent incl. `src`); no separate subdir cleanup path exists, so
   no leaked subdir on either keep or remove. TEST-005a/b assert the retained
   parent survives (keep) and the failed cascade leaves no stray `src`.

6. **Behavior drift.** None in exit codes, the canonical-repo guard, or dry-run
   (verified by reading + TEST-004/010). The out-of-scope self-relocation mktemp
   FILE (sh:22) is correctly left unchanged (used directly, never rm'd-recreated
   — no swap window).

Independent test execution (this review, macOS, git + pwsh + Pester available):
- `bash tests/skills/test-aai-update.sh` → ALL 5 PASS.
- `pwsh Invoke-Pester tests/skills/aai-update.Tests.ps1` → 9 passed, 0 failed,
  0 skipped (integration TEST-009 actually ran).
- `bash -n .aai/scripts/aai-update.sh` → exit 0.

## Verdict 3 — cannot_verify

- The REAL multi-user attacker timing race (winning the historic rm→clone window
  on a hostile shared host with world-writable `$TMPDIR`) is not reproducible in
  single-user CI — this is the spec's documented residual RR-1. What IS verifiable
  from the diff and IS verified: the structural invariant that eliminates the race
  by construction (mktemp parent owned + never freed/recreated mid-run; every
  clone target a subdir of it; execution from within the owned parent). Closes
  with a hostile-host timing harness, out of scope for this fix.

## Warning dispositions (H6)

No NON-BLOCKING (WARNING) findings — nothing to disposition. No decisions.jsonl
entry or follow-up ref required from the orchestrator.

## Overall: PASS

Both verdicts pass; the single cannot_verify item is the spec-acknowledged,
by-construction-closed residual and does not gate merge readiness.

## Next steps

- Orchestrator: record `code_review.status: pass` (done by this reviewer per
  single-agent dispatch grant).
- Stage this report with the scope commit (SPEC-0013 H4 report-staging).
- Ready for PR: spec_compliance pass + code_quality pass, no open warnings.
