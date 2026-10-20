```yaml
review:
  scope: git diff main...HEAD (HEAD 3f586664, branch fix/sync-prune-retired-skill-wrappers)
  spec: docs/specs/SPEC-0237-spec-sync-prune-retired-skill-wrappers.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/aai-sync.sh:453-470,491,636; TEST-820 PASS (re-run 2026-10-19, 7s)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/aai-sync.sh:407 (tr -d CR), :421-428 (SUBAGENT-STOP), :441 (invoke clause); TEST-821, TEST-822 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/aai-sync.sh:386-451; TEST-823, TEST-824, TEST-825 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/aai-sync.sh:466 DELETIONS+=; TEST-826 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-827 PASS: 39 single-file wrappers per tree, aai-docs-hub kept" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-828 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/scripts/aai-sync.ps1:341-448,477,660; TEST-829, TEST-830 PASS with pwsh present (PWSH_ARM_SKIPPED=0)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-sync.ps1, line: 443,
          issue: "[System.IO.Directory]::Delete($entryPath, $true) is unguarded; on Windows it throws on a read-only file, and $ErrorActionPreference = 'Stop' turns that into a sync abort. bash rm -rf and the ps1 Copy-Replace path (Remove-Item -Force) both delete read-only files.",
          failure_scenario: "Windows target where a retired wrapper's SKILL.md has the ReadOnly attribute (Perforce workspace, copy from read-only media, a backup restore). The predicate accepts the file, Directory.Delete throws UnauthorizedAccessException, and aai-sync.ps1 terminates after .claude/skills but before .agents/skills, hooks and the advisory report. Every re-run aborts the same way until someone removes the directory by hand." }
  cannot_verify:
    - { claim: "Windows PowerShell 5.1 runs the ps1 predicate as written: an enum value 0 from -band is falsy, FileInfo.Attributes on a missing path returns -1, and Directory.GetFileSystemEntries / UTF8Encoding behave the same as on pwsh 7",
        closes_with: "Run TEST-829/830's fixtures through powershell.exe 5.1 on a Windows host. CI's Windows leg runs Pester suites, not this bash suite." }
    - { claim: "ps1 FIFO/device rejection depends on .NET reporting Length 0 for non-regular files, not on a real file-type check",
        closes_with: "pwsh 7 on macOS is covered (TEST-830 aai-fifo passes, bounded). Linux CI pwsh is not observed in this review; a CI log of TEST-830 on the Linux leg would close it." }
    - { claim: "Total suite cost on CI",
        closes_with: "CI timing for test-aai-sync-seed.sh on this branch. Locally the 11 new tests take about 122 s (bash arms about 43 s, ps1 parity arms about 79 s)." }
  overall: pass
```

# Code review: sync-prune-retired-skill-wrappers

- **Scope:** `git diff main...HEAD` in /private/tmp/aai-sync-prune-retired-skill-wrappers-worktree (HEAD 3f586664). Files: `.aai/scripts/aai-sync.sh`, `.aai/scripts/aai-sync.ps1`, `tests/skills/test-aai-sync-seed.sh`, the spec and issue drafts, and ledger/INDEX lines. `docs/product/aai-update.md` and `CHANGELOG.md` are named in the spec's review scope but are written at ship time, after LOOP COMPLETE (spec Implementation plan), so they are absent from the diff by design.
- **Spec:** docs/specs/SPEC-0237-spec-sync-prune-retired-skill-wrappers.md. It is frozen, with post-freeze amendments recorded in docs/ai/decisions.jsonl (owner_signoff false; the dispatch says the owner's merge direction signs them).
- **Report location:** this report is in `docs/ai/reports/` (gitignored), not the canonical `docs/ai/reviews/` (tracked). The dispatch asked for this so the validation stamp stays valid. The orchestrator can copy it to docs/ai/reviews/ in the PR commit.

## Dispatch coaching record (anti-gaming contract)

The dispatch prompt listed "known non-blocking follow-ups" and a "Focus" list that included candidate findings, such as stale comments about U+FEFF and the backslash exclusion. That pre-characterizes expected findings. This is recorded here as required. The full scope was reviewed anyway, and every finding below was checked independently.

## Verdict 1: spec_compliance = pass

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | Bash helper and both call sites at aai-sync.sh:453-470, :491 and :636; ps1 at :431-448, :477 and :660. I re-ran TEST-820 (PASS), which covers the doctor CAT-03 PASS and the stale-prompt seam. |
| Spec-AC-02 | compliant | CR stripped at aai-sync.sh:407; trailing-blank trim and the SUBAGENT-STOP block at :413-428. TEST-821 and TEST-822 PASS. |
| Spec-AC-03 | compliant | The predicate at aai-sync.sh:386-451 has every D2 condition. TEST-823, 824 and 825 PASS (bounded runner, FIFO fixture included). |
| Spec-AC-04 | compliant | `DELETIONS+=` at :466 feeds the existing `## Deleted items` renderer. TEST-826 PASS. |
| Spec-AC-05 | compliant | TEST-827 PASS: 39 wrappers per tree, aai-docs-hub kept. |
| Spec-AC-06 | compliant | TEST-828 PASS. |
| Spec-AC-07 | compliant | TEST-829 and TEST-830 PASS with pwsh 7 present (not a SKIP). |

**TEST evidence:** I ran TEST-820 to TEST-830 myself at HEAD 3f586664, under the suite's own `set -euo pipefail`, through a scratch driver that sources the suite, so no tracked telemetry was written. All 11 passed and PWSH_ARM_SKIPPED=0. `mutation-gate.mjs --spec <spec>` returned `GATE PASS: 11 row(s) satisfied` (rc 0). RED and GREEN logs and mutation records are present under docs/ai/tdd/spec-sync-prune-retired-skill-wrappers/. D4 pinned literals: each one first occurs inside the new helper or predicate (aai-sync.sh lines 386, 394, 423, 438, 449, 453 and 467), and the ps1 signature is at :368.

**Deviations from the frozen spec.** All are edge cases outside the AC fixtures, and all were already named by validation:
1. D6 says "bash runs the predicate under `LC_ALL=C`", but the awk child that does every comparison (aai-sync.sh:410) gets no `LC_ALL=C` prefix. `local LC_ALL=C` is exported to children only when LC_ALL was already in the environment; I measured this on bash 3.2.57. This is fu-sync-lc-all-child-export.
2. D2 item 6 says the prompt "does not exist". Bash tests `! -e` (aai-sync.sh:449), so a dangling symlink counts as absent. ps1 uses Test-AnyEntry (aai-sync.ps1:425), which counts a dangling symlink as present. The engines diverge only when the source layer has a dangling prompt symlink. This is fu-sync-ps1-dangling-src-symlink.
3. D2 item 3 requires a regular file. In ps1 that check is attribute-based (ReparsePoint, Directory, Device) plus `Length >= 1`. A FIFO is rejected only because .NET reports Length 0, not by a real file-type test. TEST-830 shows the result is correct on pwsh 7/macOS (see cannot_verify).

## Verdict 2: code_quality = pass

### Removal path correctness (checked, no defect)
- **Bash:** `rm -rf` runs only on `$DST_ROOT/$tree/<name>`, after the predicate has proven it is a non-symlink directory with exactly one regular, non-symlink child named byte-exactly `SKILL.md`. `rm -rf` does not follow symlinks inside, and the predicate leaves no such entry anyway.
- **ps1:** the ReparsePoint check runs on the directory (aai-sync.ps1:372) and on the child (:381) before `Directory.Delete`.
- **Recording:** both engines record removals in the same list the advisory report uses (DELETIONS / `$script:deletions`, script scope confirmed at ps1:173).
- **Predicate call context:** the predicate is always called from an `if`, so `set -e` never aborts inside it. Every failure returns 1, which means the entry is kept.
- **Locale:** `local LC_ALL=C` is restored after the function returns on bash 3.2. I measured `${#v}` before, inside and after the function.
- **Enumeration:** `"$DST_ROOT/$tree/"*` quotes the root, so glob characters in the root path are not expanded.
- **Pre-filter:** the caller's allowlist pre-filter runs in the caller's locale. bash 3.2 under en_US.UTF-8 rejected both `aai-Foo` and `aai-naïve` in my probe. In any case the C-locale predicate re-checks before any delete.
- **Root symlinks:** a symlinked `.claude/skills` root or `.claude` parent is fu-sync-symlinked-tree-root (known, unchanged).

### Parity
The awk program and the ps1 code apply the same rules:
- trailing-blank trim
- body filter
- SUBAGENT-STOP with at least one inner line
- exactly two remaining lines
- first-occurrence `.prompt.md` split
- `[A-Z0-9_]+`
- the invoke clause and the no-further-`.aai/` rule
- the final `.`
- the exact not-found line, with the em dash built as `[char]0x2014` in ps1

The ps1 additions are pure ASCII (checked), which matters because PS 5.1 reads a BOM-less script as ANSI. The ps1 caller also skips `aai-project-*` before any stat, while bash leaves that to the predicate. Behavior is the same.

### PS 5.1 idioms
Inline parameter lists, `[string]::Equals(..., Ordinal)`, `String.IndexOf(string, StringComparison)`, `[regex]::IsMatch` with RegexOptions, and `New-Object` all exist in PS 5.1. No PS 7-only syntax (`?:`, `??`, `-AsByteStream`) is used. Runtime behavior on 5.1 is listed under cannot_verify.

### Readability and dead code
- The backslash-only exclusion is gone; the allowlist replaced it.
- The ps1 U+FEFF comment (:395) explains why no special case is needed. It is accurate, not stale.
- No dead branches.
- `[[ -n "$prompt" ]]` (bash :448) is redundant after awk's success exit but harmless.

### Findings

**NB-1 (NON-BLOCKING, P3): .aai/scripts/aai-sync.ps1:443.** `[System.IO.Directory]::Delete($entryPath, $true)` has no guard.
- **Failure scenario:** on Windows, a retired wrapper's `SKILL.md` has the ReadOnly attribute. This is the default for files in a Perforce workspace, and also happens after a copy from read-only media or a backup restore. Directory.Delete throws, `$ErrorActionPreference = "Stop"` (ps1:7) makes that terminating, and the sync stops after the `.claude/skills` block. The `.agents/skills` block, hooks and the advisory report never run, and every re-run aborts at the same point.
- **Why it is a ps1-only defect:** bash `rm -rf` deletes read-only files, and the ps1 Copy-Replace path uses `Remove-Item -Force`, which also does.
- **Fix within D6** (System.IO only): clear the attribute with `[System.IO.File]::SetAttributes($childPath, 'Normal')` before the delete, or wrap the delete in try/catch, print a WARN and keep the entry. Either way the entry must not be recorded as deleted.
- **Recommended disposition:** promote to follow-up (b), `fu-sync-ps1-readonly-delete-abort`, P3, with a fixture under pwsh on Windows.

### INFO (non-gating)
- **I-1:** the comment at aai-sync.sh:389, "(A shell-local LC_ALL does not reach child processes; children get the prefix explicitly.)", is wrong twice. awk gets no prefix, and the local IS exported when LC_ALL was already exported. Fix it together with fu-sync-lc-all-child-export.
- **I-2:** the variant list in the `_retired_shim_text` header comment (test-aai-sync-seed.sh, at the `_retired_shim_text` header) leaves out `tworef`.
- **I-3:** on macOS, a `.DS_Store` written into a retired wrapper directory makes the entry count 2, so that wrapper is kept and stays orphaned. This is a false negative in the safe direction (same for Windows `desktop.ini`/`Thumbs.db`). It falls under the spec's Out-of-scope residual for non-single-file wrappers.
- **I-4: suite cost.** The 11 tests add about 122 s locally, and the two ps1 parity arms are about 79 s of that. These arms run on the Linux CI leg, where pwsh is present; the Windows leg does not run this bash suite. `_retired_parity_pair` re-runs the bash engine over fixtures that TEST-823 already syncs. This is the same cost class as the open fu-sync-seed-cache-no-ci-gain (P2).
- **I-5: process.** The six follow-ups named as known are cited only in gitignored validation reports (VALIDATION-20261019T120548Z and the r6 addendum). This branch's docs/ai/decisions.jsonl has none of them; it holds only fu-amend-sync-prune-retired-skill-a93b78. They need `follow-ups.mjs add` before close, or they leave no durable record.

## cannot_verify
1. Windows PowerShell 5.1 runtime behavior of the predicate:
   - an enum value 0 from `-band` is treated as false
   - `FileInfo.Attributes` on a missing path returns -1
   - `GetFileSystemEntries` ordering and contents

   To close: run the TEST-829/830 fixtures through powershell.exe on Windows.
2. ps1 non-regular-file rejection on Linux pwsh: it relies on Length 0. To close: a Linux CI log of TEST-830.
3. CI wall-clock cost of the extended suite. To close: CI timing on this branch.

## Warning dispositions (H6)
- **NB-1:** recommended disposition (b), promote to typed follow-up `fu-sync-ps1-readonly-delete-abort` (P3, ref sync-prune-retired-skill-wrappers). The reviewer is read-only; the orchestrator records it.

## Next steps
1. Orchestrator runs the returned `state_update_commands`.
2. Orchestrator registers NB-1 and the six validation-named follow-ups (I-5) with `follow-ups.mjs add`.
3. Optionally fix I-1 when fu-sync-lc-all-child-export is remediated.

## Re-confirmation (resumed review, 2026-10-20, HEAD 3f586664 unchanged)
The interrupted attempt's report (review-sync-prune-retired-skill-wrappers-20261019T124957Z.md) was written against the same HEAD; it was re-checked rather than redone:
- Re-read both engines' predicate and removal path (aai-sync.sh:380-472, aai-sync.ps1:341-448): NB-1 (unguarded Directory.Delete, ps1:443), I-1 (stale LC_ALL comment, sh:389-390) and deviations 1-3 confirmed; no dead backslash/U+FEFF branch remains (the ps1 U+FEFF comment is accurate, not stale).
- `bash -n` aai-sync.sh and test-aai-sync-seed.sh: OK. pwsh Parser.ParseFile aai-sync.ps1: 0 errors. Added ps1 lines: 0 non-ASCII bytes, no BOM change (PS 5.1 ANSI-read safe).
- `git ls-files -ci --exclude-standard`: empty (no gitignored artifacts committed).
- `mutation-gate.mjs --spec ...`: GATE PASS 11 rows, degraded=0.
- Suites not re-run (round-5 full sweep + r6 sync-seed re-run + the interrupted reviewer's TEST-820..830 run all on byte-identical code).
Verdicts unchanged: spec_compliance pass, code_quality pass (1 NON-BLOCKING), overall pass.
