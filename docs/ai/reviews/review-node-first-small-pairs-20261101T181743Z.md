```yaml
review:
  scope: "git diff main...4ae8d883 over code_review.scope (STATE.yaml, 30 explicit paths)"
  spec: docs/specs/SPEC-0265-spec-node-first-small-pairs.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/validate-skills.mjs:9-37; TEST-3201, TEST-3202 PASS (suite run this round)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/validate-skills.sh:1-9 (9 lines), .aai/scripts/validate-skills.ps1:1-11 (11 lines), ASCII, mode 100755; TEST-3203, TEST-3204, TEST-3205 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/aai-live.mjs:19-65; TEST-3206, TEST-3207, TEST-3208 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/aai-live.sh:1-9, .aai/scripts/aai-live.ps1:1-12; TEST-3209 PASS, TEST-3210 PASS (Total=6 Skipped=0, pwsh on macOS; Windows leg is hosted check)" }
      - { ac: Spec-AC-05, call: compliant, citation: "tests/self-hosting/test-self-hosting-smoke.ps1:43; TEST-3211, TEST-3212 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "both pre-compact-save files deleted, PROFILES.yaml core entries removed; git grep outside docs/CHANGELOG names only aai-doctor.mjs and test-aai-doctor.sh (checked this round); TEST-3213 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/scripts/aai-doctor.mjs:310-319; TEST-3214, TEST-3215, test_009 PASS; record 047982fe1ff4 (ref node-first-small-pairs, unsigned-tracked)" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3216 PASS (extended sync into spaced path, PRESERVE kept, core holds neither module)" }
      - { ac: Spec-AC-09, call: compliant, citation: ".aai/system/PROFILES.yaml:322,361; tests/skills/suite-map.yaml:808-827; .github/workflows/ps1-quality.yml:78-79,102-103; TEST-3217..3219 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "wc -l of six files = 156 (checked), RFC-0017 paragraph says 481 to 156; TEST-3220 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: "docs/rfc/RFC-0017-...md:315-330; TEST-3221 PASS (wraps TEST-2624, TEST-2623)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/validate-skills.ps1, line: 7,
          issue: "Windows PowerShell 5.1 legacy native-argument passing wraps a spaced argument in quotes without escaping a trailing backslash; the old pure-PowerShell copy had no such path",
          failure_scenario: "PS 5.1: validate-skills.ps1 -TargetRoot 'D:\\AAI projects\\app\\' -> node receives argv[2] = D:\\AAI projects\\app\" -> ERROR: Target not found, exit 1, for a valid directory. pwsh 7.3+ is unaffected." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-live.mjs, line: 22,
          issue: "an absolute --output is returned as given, unnormalized; only relative values pass through path.join (which normalizes separators)",
          failure_scenario: "Windows: aai-live.ps1 --output C:/tmp/page.html -> explorer.exe receives C:/tmp/page.html; explorer handles forward-slash paths unreliably (opens a default folder instead of the page). Not exercised by any test. path.resolve(root, out) gives the same POSIX results and normalizes on win32." }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 2613,
          issue: "follow-up fu-amend-spec-doctor-determinize carries ref_id doctor-determinize (an already-merged ref), so this ride's merge/close does not close it even after it signs the re-filed record 047982fe1ff4 that points at it via tracked_by (carried from validation r2)",
          failure_scenario: "after merge, follow-ups list still shows a P2 'owner sign-off owed' item for a change that the merge signed: a false-open record." }
  cannot_verify:
    - { claim: "Windows parity: explorer.exe opening, .cmd opener in a spaced path receiving one argument (L-6), PS 5.1 launch of both ps1 launchers", closes_with: "hosted Windows Pester leg (spec Hosted delivery checks H1) green on the PR" }
    - { claim: "interactive Ctrl+C in a terminal under --watch (tty sends SIGINT to the whole group, launcher forwards a second one) exits cleanly", closes_with: "a manual run; by reading, generate-live-status.mjs:659 uses process.on (not once), so the second SIGINT re-enters shutdown, not the default handler" }
    - { claim: "downstream installs with a hand-wired PreCompact hook get the CAT-09 WARN and nothing else breaks", closes_with: "a downstream aai-sync + aai-doctor run on a real project with such a settings file (TEST-3214 covers fixtures only)" }
    - { claim: "CHANGELOG [unreleased] entry naming V-3, V-4, L-1, L-2, L-8 and the retirement (D4, after LOOP COMPLETE)", closes_with: "the ship step writing it; CHANGELOG.md has no diff at 4ae8d883, which the spec allows at this stage" }
  overall: pass
```

# Code review, round 1: node-first-small-pairs

security_relevant: false

- Scope: `git diff main...HEAD` (head 4ae8d883, branch feat/node-first-small-pairs) over the 30 paths in STATE `code_review.scope`. Out-of-scope diff paths (docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/ai/roadmap.yaml) not reviewed. The working tree has two modified telemetry files (EVENTS.jsonl, test-runs.jsonl), both outside the scope.
- Spec: docs/specs/SPEC-0265-spec-node-first-small-pairs.md (frozen, amended; four amendment records of this ref, all unsigned-tracked).
- Dispatch note (anti-gaming): the dispatch prompt named focus areas and relayed validation r2's non-blocking notes. It did not rate severity or exclude any area. I reviewed the full scope anyway.

## Verdict 1: spec_compliance = pass

AC walk: see the YAML block. I checked these by reading the code as well as by the test runs:

- **Launcher thinness:** sh launchers 9 lines, ps1 launchers 11 and 12 lines. They contain no byte above 0x7E. Both sh files are 100755 in the index. None holds REQUIRED, an opener name, `--output` or the warm-up.
- **Arg passing and exit codes:** sh `exec node "$MODULE" "$@"` (quoted, exit code is node's). ps1 `& node $Module $TargetRoot` / `@RestArgs`, then `exit $LASTEXITCODE`. aai-live.ps1 keeps the `[CmdletBinding()]` and `ValueFromRemainingArguments` binding of the main copy. `$PSScriptRoot`, `Join-Path`, `Test-Path -LiteralPath` and `[Console]::Error.WriteLine` all work on PS 5.1.
- **Signal forwarding:** `aai-live.mjs:62-64` forwards SIGINT and SIGTERM to the inherited-stdio child and resolves with its code (1 when the child exits by signal), per L-8. The sh launcher `exec`s, so signals reach node directly.
- **CAT-09:** `aai-doctor.mjs:313-318` matches D3:
  - no settings file names the hook: PASS
  - a settings file names it and neither copy exists: WARN naming the file(s)
  - a copy exists: PASS
  - an unreadable file: `readText` returns null, treated as absent

  The spec's "neither .sh nor .ps1 exists" is implemented literally: a hook naming `.ps1` with only `.sh` present gives PASS.
- **Retirement:** `git grep pre-compact-save` outside docs/ and CHANGELOG.md finds only aai-doctor.mjs and test-aai-doctor.sh. No template, aai-sync, `.claude` settings or Windows-fallback list names it. The .gitignore backup-file entry stays, per PC-1.
- **RFC inventory:** three rows removed, the other rows unchanged, the slice paragraph placed directly after the table, 156 equals the live `wc -l`. TEST-3221 runs TEST-2624 and TEST-2623, and both pass.
- **TEST-026 exemption:** one constant, `supersededRecord = "91c688d47ba3"`, used only in the `unsignedMerged` filter (`test-aai-merge-cleanup.sh:1559-1560`). `spec-amend list --json` shows that key is exactly the doctor-determinize SPEC-0100 record. The re-filed record 047982fe1ff4 is under ref node-first-small-pairs and is not exempted. TEST-026 PASS this round.

Deviations from the frozen spec: none found. Two small additions:

- `validate-skills.mjs:16` adds an `isDir` helper for V-4. It is not among the mandated anchors.
- `warmupArgs` keeps the mandated `const warm = ...` line, so the function has a redundant local (validation nit :25-28). The spec requires that exact line, so this is INFO only.

## Verdict 2: code_quality = pass

No BLOCKING findings. Three NON-BLOCKING findings, each with its recommended disposition:

| # | Finding | Severity | Recommended disposition |
|---|---|---|---|
| NB-1 | `validate-skills.ps1:7`: on PS 5.1, a spaced `-TargetRoot` that ends in a backslash gets a stray quote at the end. Trimming the backslash naively would turn `C:\` into the drive-relative `C:`, so there is no clean one-line fix. | P3 | (d) `accepted residual: PS 5.1-only quoting edge for a spaced target ending in a backslash; pwsh 7.3+ and the default (Get-Location) path are unaffected; no observed bite, no false record` |
| NB-2 | `aai-live.mjs:22`: an absolute `--output` is not normalized before it reaches explorer.exe. | P3 | (a) remediate in-tree: `return path.resolve(root, out);` gives identical POSIX results (TEST-3206 still holds) and normalizes on win32. Same line count. If deferred, (b) a follow-up under this ref. |
| NB-3 | `fu-amend-spec-doctor-determinize` (ref doctor-determinize) is not closed by this ride's close. It would become a false-open P2 record after the merge signs 047982fe1ff4. | P2 (record) | (a) the orchestrator closes it in the close ceremony after merge (`follow-ups.mjs` close, citing the signing merge), or re-tracks it under this ref before PR. A disposition (d) is not allowed here because the item would leave a false record. |

INFO notes. They have no failure scenario that bites and they do not gate the verdict.

- `aai-live.mjs:35`: opener discovery checks `isFile`, not the exec bit. A non-executable `open` earlier on PATH would win, and the spawn then fails silently. The bash copy used `command -v`.
- `aai-live.mjs:63`: signal handlers are installed after `spawn`. A signal in that window, or during the warm-up or opener, takes the default action.
- `aai-live.mjs:41`: the `.cmd` shell path quotes both parts. A target holding `%NAME%` could still be expanded by cmd.exe. The input is the user's own env var and path, so no trust boundary is crossed.
- `cd-subshell-leak-baseline.tsv` adds an allowance of 3 for the new test-aai-validate-skills.sh, instead of the new file being leak-free.

## cannot_verify

See the YAML block: the Windows/PS 5.1 runtime (closed by the hosted Windows Pester leg), interactive Ctrl+C, downstream hand-wired hooks, and the pending CHANGELOG entry.

## Tests run this round (targeted, env -u AAI_ROLE)

- `bash tests/skills/test-aai-validate-skills.sh`: all PASS (TEST-3201..3205, 3211..3213, 3216..3221).
- `bash tests/skills/test-aai-live-status.sh` test_3206..test_3210: PASS (Pester Total=6, Skipped=0).
- `bash tests/skills/test-aai-doctor.sh` test_009, test_3214, test_3215: PASS.
- `bash tests/skills/test-aai-merge-cleanup.sh test_026_backlog_signed_on_live_ledger`: PASS.

## Next steps

1. The orchestrator records the dispositions: NB-1 (d), NB-2 (a) or (b), NB-3 (a) at close.
2. Ship step: write the CHANGELOG entry and product docs, then open the PR.
3. Hosted Windows leg must be green before merge-readiness.
