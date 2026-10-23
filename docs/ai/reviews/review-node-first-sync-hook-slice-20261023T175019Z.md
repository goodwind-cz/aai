# Code review (round 2): node-first-sync-hook-slice

```yaml
review:
  scope: "git diff 3b092c64..37fcaad0 (branch change/node-first-sync-hook-slice, worktree /private/tmp/aai-node-first-slice); focus 43e6f10a..37fcaad0 (spec amendment 0462e0ae + remediation 37fcaad0)"
  spec: docs/specs/SPEC-0247-spec-node-first-sync-hook-slice.md (frozen, amended; frozen_sha256 2efa069b...c561; spec-lint LINT PASS)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/live-spool.mjs:25-39 (unchanged since round 1); TEST-2401 (node --test 12/12 rerun)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/live-spool.mjs:28-31,41-51; TEST-2402..2406 (node --test rerun)" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/live-spool.mjs:53-65,72-82; TEST-2407" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/live-spool.sh:8-17, .aai/scripts/live-spool.ps1:6-17 (17 lines each, match amended D2 byte-for-byte); TEST-2408/2409/2410 rerun PASS; ps1 stderr clause verified by reviewer probe only (see NB-A)" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-2411 rerun PASS; TEST-2412 rerun PASS (Total=8 Passed=8 Failed=0 Skipped=0)" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-2413 (no change in 43e6f10a..37fcaad0; round-1 evidence stands)" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2414 (no change in focus range; round-1 rerun PASS)" }
      - { ac: Spec-AC-08, call: compliant, citation: "no change in focus range; round-1 citations stand" }
      - { ac: Spec-AC-09, call: compliant, citation: "docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md:306; TEST-2419" }
      - { ac: Spec-AC-10, call: compliant, citation: "RFC row '133 to 116' = 82+17+17 (wc -l); TEST-2420 rerun PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/live-spool.ps1, line: 14,
          issue: "The ps1 stdin drain (NB-2 on the PowerShell side) and the amended Spec-AC-04 'write nothing to stderr' clause for the ps1 launcher have no test. TEST-2410's module-absent half pipes a 12-byte payload and discards stderr (tests/skills/test-aai-live-status.sh:1222-1229); the new Pester case asserts neither drain nor stderr (tests/skills/live-spool.Tests.ps1:103-113).",
          failure_scenario: "Reviewer mutation m6 (delete line 14 of live-spool.ps1 in a scratch copy): TEST-2410 PASS and TEST-2412 PASS 8/8, yet the mutated launcher with the module absent gets SIGPIPE on its writer for a 2 MB hooks payload (writer rc 141; the unmutated launcher gives 0). A later edit can drop the drain without any red." }
      - { rank: NON-BLOCKING, file: .aai/scripts/live-spool.sh, line: 8,
          issue: "Two other sh hardenings from the amendment are not guarded by any test: the CDPATH-safe module path (line 8) and the tty guard on the drain (line 14).",
          failure_scenario: "Reviewer mutations m7 (CDPATH= cd -- -> cd) and m8 ('[[ -t 0 ]] || cat' -> 'cat') both leave TEST-2409 PASS. Probes show the current code behaves correctly (exported CDPATH with a relative invocation writes the spool line; tty stdin with the module absent returns at once). A regression would bring back the round-1 NB-1 CDPATH case or a statusline that hangs on a tty." }
  cannot_verify:
    - { claim: "Windows PowerShell 5.1 started with -File: native node inherits the redirected stdin, and after a failed node run [Console]::In.ReadToEnd() still drains it (the ConsoleHost has not buffered it). The new module-absent Pester case under 5.1", closes_with: "H1: ps1-quality windows-5_1 and windows-wsl1 logs on the PR head listing all 8 live-spool.Tests.ps1 cases passed, including 'prints the passthrough and writes nothing when the module is absent'" }
    - { claim: "The preinstalled Node on ubuntu-latest and windows-latest is major 22 or newer (ps1-quality.yml has no setup-node)", closes_with: "H1 log line 'node --version: v2x'" }
    - { claim: "Under Git Bash on Windows, the module's main guard (live-spool.mjs:70) is true for the MSYS-converted path. If it were false, node would exit 0 with no output, and the new fallback would not run. That would be the one remaining 'node present, module cannot run' path that still gives an empty statusline", closes_with: "a Git Bash run of the template statusLine command on a Windows runner" }
    - { claim: "Node 22 floor on CI picks up live-spool.test.mjs", closes_with: "H2: 'Node 22 compatibility (downstream floor)' step output listing TEST-2401..2407" }
    - { claim: "Claude Code closes the hook/statusline stdin after writing. The fallback cat/ReadToEnd now reads stdin in the node-absent hooks path, and would block if the writer kept it open (the node path's readFileSync(0) already had the same property)", closes_with: "a harness run on a host without node with the overlay installed" }
    - { claim: "Concurrent appends across a cap rewrite lose at most one line (pre-existing race, spec residual)", closes_with: "a concurrency stress test; not claimed by this scope" }
  overall: pass
```

## Scope and preflight

- Scope: `git diff 3b092c64..37fcaad0`, six commits. The focus is on `43e6f10a..37fcaad0`: `0462e0ae` amends the spec (D2 launcher shapes, Spec-AC-04, TEST-2409/2410 rows) and `37fcaad0` is the remediation (both launchers, TEST-2409/2410 bodies, the Pester case, the RFC line count). Worktree mode.
- Working tree at review start: `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl` modified (ledger appends) and the untracked round-1 report. A parallel Validation round 3 is running. This review wrote only this report. All probes and mutations ran on copies under the session scratchpad (a `git archive 37fcaad0` tree).
- Dispatch note (anti-gaming): the dispatch listed round-1 findings and named specific questions (double passthrough, tty, PS 5.1 `$LASTEXITCODE`). That is context, not a severity rating. The whole range was reviewed, and every finding below was re-derived by probe or mutation.

## Reviewer reruns and probes (macOS arm64, Node 22.23.1, pwsh 7.6.3)

| Check | Result |
|---|---|
| `node --test tests/skills/lib/live-spool.test.mjs` | 12 pass, 0 fail |
| `test-aai-live-status.sh` 2408, 2409, 2410, 2411, 2412, 2420 | all PASS (2412: Total=8 Passed=8) |
| spec-lint on the spec | LINT PASS |
| `spec-amend list --strict` | amendment 2026-10-23T15:57:10Z listed as `unsigned-tracked` (class contract, fu-amend-spec-node-first-sync-hook-slice open); unsigned-untracked=0 |
| Mutation records TEST-2409/2410 | `target_sha256` equals the current launcher bytes (599166d8..., 54e9dc7c...); verdict RED |

Fallback matrix, 2 MB payload piped in, writer exit status captured:

| Case | sh | ps1 |
|---|---|---|
| node absent, statusline | rc 0, passthrough, writer 0, stderr 0 B, no spool | same |
| node absent, hooks | rc 0, no output, writer 0 (round-1 NB-2 closed) | same |
| module absent (copy), statusline / hooks | rc 0, passthrough / nothing, writer 0, stderr 0 B (round-1 NB-1 closed) | same |
| module fails at load (syntax error) | rc 0, passthrough, writer 0 | rc 0, passthrough |
| module ok, 2 MB invalid payload | passthrough once, no spool | n/a |
| launcher reached through a symlink | passthrough (falls back, no spool line); was empty in round 1 | n/a |
| exported CDPATH, relative invocation | spool line written, passthrough | n/a |
| tty stdin, module absent (pty) | returns at once, passthrough | returns at once, passthrough |
| fake module: prints passthrough then exits 3 | passthrough printed twice | printed twice |

### Answers to the dispatch questions

1. **Double passthrough.** The design can print the passthrough twice, but only if the module writes it and node then exits non-zero. The real module writes synchronously (`fs.writeSync`, mjs:79) and then calls `process.exit(0)` (mjs:81). Every throw before that point is caught (mjs:59, 63, 74). So the only remaining trigger is an external signal that arrives between the write and the exit, and a harness kill would normally take the launcher down as well. The probe with a fake module confirms the shape. INFO only.
2. **tty stdin.** sh skips the drain on a tty (`[[ -t 0 ]]`), and ps1 does the same through `[Console]::IsInputRedirected`. In both probes the launcher returned at once. The sh tty guard has no test (NB-B).
3. **PowerShell `$LASTEXITCODE`.** The "`& node` not found" case cannot happen, because `Get-Command node` gates the call. If node is found and fails, `$LASTEXITCODE` holds node's code (1 for a missing module or a syntax error), so `$Ran` is false and the fallback runs. `$Ran` starts `$false` and is assigned only after `& node` runs, so a stale `$LASTEXITCODE` from the caller's session cannot leak in. Edge case, INFO: if `node` resolves to a function or alias rather than an Application, `$LASTEXITCODE` is not set by the call. `[Console]::IsInputRedirected` needs .NET 4.5, and Windows PowerShell 5.1 already requires that. The 5.1 runtime behavior is in cannot_verify.
4. **Is the amendment honest and minimal?** Yes. The amendment changes 36 lines, all confined to the D2 prose, the two code blocks, the Spec-AC-04 row and the TEST-2409/2410 rows. The spec text discloses it ("Amended after code review NB-1/NB-2 (2026-10-23)") and `frozen_sha256` was re-stamped. `decisions.jsonl` records a `spec_amendment` (class contract, `owner_signoff:false`) together with a P2 `fu-amend-spec-node-first-sync-hook-slice`, so the owner's sign-off is visibly owed rather than claimed. The RFC row was updated to 116 to keep TEST-2420 true. One overstatement: the amended Spec-AC-04 adds "write nothing to stderr" for each launcher, but only the sh test asserts it (NB-A).
5. **Do the new mutation cells guard the fallback?** Partly. Both recorded cells (`if [[ $rc -ne 0 ]]` -> `if false`, `if (-not $Ran)` -> `if ($false)`) disable the whole fallback block. They redden on the node-absent assertion, which predates the amendment, not on the new module-absent half. The new trigger is still guarded by the test bodies: reviewer mutation m4 (`&& rc=0` -> `; rc=0`) reddens TEST-2409 on the module-absent assertion, m5 (`$Ran = $true`) reddens TEST-2410, and m3 (drop the sh drain) reddens TEST-2409 with writer rc 141. Unguarded are the ps1 drain (m6), the sh CDPATH fix (m7) and the sh tty guard (m8): NB-A and NB-B.
6. **New hazards.** None of BLOCKING weight. The fallback now reads stdin on the node-absent hooks path where it used to exit at once. It would block on a writer that never closes stdin, which is the same property the node path's `readFileSync(0)` already has (cannot_verify item 5).

## Verdict 1: spec_compliance = pass

All ten Spec-AC rows are compliant (see the walk above). The launchers match the amended D2 code blocks exactly, and both are 17 lines (limit 20), ASCII only, with the passthrough literal appearing once.

Deviations, listed even where reasonable:
1. Carried over from round 1 (accepted): the aai-doctor suite-map wildcard, the `realOrResolve` main guard, and the unrelated ledger lines.
2. Still pending, as in round 1: the D5 product doc (`docs/product/live-status-dashboard.md` still calls the `.ps1` a twin) and the CHANGELOG `## [unreleased] — ...` entry. Both are due after LOOP COMPLETE and before the PR. The product doc should now describe the amended fallback (node absent, or node cannot run the module).
3. The amended Spec-AC-04 stderr clause is met by the ps1 launcher (probe: 0 B on stderr in every fallback case), but no TEST-xxx asserts it for ps1 (NB-A).

## Verdict 2: code_quality = pass

No BLOCKING findings. Round-1 NB-1 (empty statusline when the module cannot run) and NB-2 (unread stdin, CDPATH) are closed on both shells by the probes above, with one remaining variant: a false main guard, which only Git Bash could plausibly produce (cannot_verify). Round-1 NB-3 (BOM payload dropped) is unchanged and remains an accepted residual.

**NB-A. The ps1 drain and the ps1 stderr clause have no test.** `.aai/scripts/live-spool.ps1:14`; tests at `tests/skills/test-aai-live-status.sh:1222-1229` and `tests/skills/live-spool.Tests.ps1:103-113`. Mutation m6 deletes the drain. Both TEST-2410 and Pester (8/8) still pass, but the mutated launcher gives writer rc 141 on a 2 MB hooks payload with the module absent.
Recommended disposition: (a) remediate in tree. In TEST-2410's module-absent half, mirror TEST-2409: a 1 MB redirected hooks payload with the writer exit status captured, and stderr sent to a file and asserted empty. Optionally record m6 as a second TEST-2410 mutation. If it is not remediated, use (b): follow-up P3, suggested id `fu-live-spool-ps1-drain-test` (suggested, not filed).

**NB-B. The sh CDPATH fix and the sh tty guard have no test.** `.aai/scripts/live-spool.sh:8,14`. Mutations m7 and m8 leave TEST-2409 green. Both behaviors are correct today (see the probes). This is an assurance-strength gap with no bite observed and no false record.
Recommended disposition: (d) `accepted residual: CDPATH-safe module path and tty drain guard in live-spool.sh are correct by probe but unguarded by a test; a regression would be silent`. Alternatively, fold it into NB-A's remediation: one `CDPATH=<dir with .aai/scripts>` relative-invocation case, and one `</dev/null` case is not enough for tty, so the tty half stays residual.

### INFO (non-gating)

- Double passthrough is reachable only through an external signal between `fs.writeSync` and `process.exit(0)` (answer 1 above).
- The recorded mutation cells for TEST-2409/2410 redden on the pre-amendment assertion. The module-absent trigger is guarded by the test bodies (m4/m5 RED), not by a recorded cell.
- If `Get-Command node` resolves a function or alias, `$LASTEXITCODE` is not set by the call, and the fallback behavior depends on the caller's state. Not reachable under `-File` with a clean profile.

## cannot_verify

Six items, listed in the YAML block. The items that decide merge readiness are still H1 (5.1 stdin inheritance, now together with the 5.1 drain after a failed node run and the new module-absent Pester case) and H2 (Node 22 floor). Both are hosted checks after PR creation.

## Warning dispositions (H6)

| Finding | Recommended disposition | Recorded by |
|---|---|---|
| NB-A | (a) remediate in tree (extend TEST-2410's module-absent half with a drain and stderr assertion); else (b) P3 follow-up, suggested `fu-live-spool-ps1-drain-test` | orchestrator |
| NB-B | (d) `accepted residual: CDPATH-safe module path and tty drain guard in live-spool.sh are correct by probe but unguarded by a test; a regression would be silent` | this report |
| round-1 NB-3 | (d) unchanged: `accepted residual: BOM-prefixed payload is dropped, parity with the old Bash copy; no shipped caller emits a BOM` | round-1 report |

## Next steps

1. Orchestrator decides NB-A: in-tree remediation, which is a test-only change and needs no further amendment, or a P3 follow-up. Record NB-B and NB-3 in `code_review.notes`.
2. Owner sign-off on `fu-amend-spec-node-first-sync-hook-slice` remains owed and should be disclosed in the PR body under Contract amendments.
3. D5 product doc (including the amended fallback and the BOM note) and the CHANGELOG entry after LOOP COMPLETE, then the PR, then H1/H2.
