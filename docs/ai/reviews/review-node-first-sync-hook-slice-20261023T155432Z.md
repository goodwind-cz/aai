# Code review: node-first-sync-hook-slice

```yaml
review:
  scope: "git diff 3b092c64..43e6f10a (branch change/node-first-sync-hook-slice, worktree /private/tmp/aai-node-first-slice)"
  spec: docs/specs/SPEC-0247-spec-node-first-sync-hook-slice.md (frozen, sha256 faaab3cd...3ccc, matches the round-2 validation outcome block)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/live-spool.mjs:18-20,25-39; TEST-2401 (node --test 12/12 rerun by reviewer)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/live-spool.mjs:28-31,41-51; TEST-2402..2406" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/live-spool.mjs:53-65,72-82; TEST-2407" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/live-spool.sh:7-14, .aai/scripts/live-spool.ps1:6-13; TEST-2408/2409/2410 rerun PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-2411 rerun PASS; TEST-2412 rerun PASS (Pester 7/7/0 skipped, local pwsh 7); test_001..039 bodies unchanged (diff has zero removed lines)" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-2413 (validation r2 PASS)" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2414 rerun PASS (aai-sync into 'target dir')" }
      - { ac: Spec-AC-08, call: compliant, citation: ".aai/system/PROFILES.yaml:332; tests/skills/suite-map.yaml:709-711; .github/workflows/ps1-quality.yml:75,95; TEST-2415..2418 (2416/2417/2418 rerun PASS)" }
      - { ac: Spec-AC-09, call: compliant, citation: "docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md:306; TEST-2419" }
      - { ac: Spec-AC-10, call: compliant, citation: "RFC row '133 to 109' = 82+14+13; TEST-2420 rerun PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/live-spool.sh, line: 8,
          issue: "When node is on PATH but live-spool.mjs cannot be run (missing next to the launcher, launcher symlinked or copied elsewhere, exported CDPATH with a relative invocation, module unparsable), node exits non-zero, stderr is discarded and the statusline prints nothing. The old script printed the passthrough unconditionally. Same shape in .aai/scripts/live-spool.ps1:8-9. (Validation F2.)",
          failure_scenario: "Reviewer probe: launcher copied without the module -> sh rc 0 stdout '' ; ps1 rc 0 stdout ''; launcher reached through a symlink ($S/link.sh -> .../live-spool.sh) -> stdout '' and no spool line. A Claude Code statusLine wired to such a launcher renders blank." }
      - { rank: NON-BLOCKING, file: .aai/scripts/live-spool.sh, line: 10,
          issue: "Node-absent branch drains stdin only for statusline; for hooks (and in .aai/scripts/live-spool.ps1:10-12 for every kind) the launcher exits without reading stdin. The old .sh always ran cat.",
          failure_scenario: "Reviewer probe, PATH without node: 2 MB piped into 'live-spool.sh hooks' -> writer PIPESTATUS 141 (SIGPIPE). Real hook payloads are small, so a bite needs a payload above the pipe buffer or a harness write that lands after the launcher exited; no harness-side bite observed." }
      - { rank: NON-BLOCKING, file: .aai/scripts/live-spool.mjs, line: 27,
          issue: "A UTF-8 BOM before the JSON payload makes JSON.parse throw, so the line is silently dropped (Validation F3). Same as the old .sh; differs from the old .ps1 (ConvertFrom-Json tolerated it).",
          failure_scenario: "Reviewer probe: printf '\\xef\\xbb\\xbf{\"cwd\":\"/bom\"}' | live-spool.sh -> passthrough printed, no spool line. A caller piping from Windows PowerShell 5.1 with a BOM-emitting $OutputEncoding into live-spool.ps1 loses every line." }
  cannot_verify:
    - { claim: "Windows PowerShell 5.1 started with -File hands its redirected stdin to the native node child (D2 stdin inheritance); the non-ASCII Pester case under 5.1", closes_with: "H1: ps1-quality windows-5_1 and windows-wsl1 logs on the PR head listing every live-spool.Tests.ps1 case passed" }
    - { claim: "The preinstalled Node on ubuntu-latest and windows-latest is major 22 or newer (ps1-quality.yml has no setup-node; the Pester 'runs on Node 22 or newer' case fails otherwise)", closes_with: "H1 log line 'node --version: v2x' in gate, windows-5_1 and windows-wsl1" }
    - { claim: "The .sh launcher works under Git Bash on Windows (the template path on Windows hosts): MSYS conversion of the POSIX MODULE path for node.exe, spaces in the path, and the realOrResolve main-guard equality with Windows drive-letter casing", closes_with: "a Git Bash run of the template statusLine command on a Windows runner, or a test in windows-5_1 that runs bash live-spool.sh" }
    - { claim: "Node 22 floor on CI picks up live-spool.test.mjs (local Node 22.23.1 passes 12/12)", closes_with: "H2: 'Node 22 compatibility (downstream floor)' step output listing TEST-2401..2407" }
    - { claim: "Claude Code tolerates EPIPE on hook stdin when the Node-absent hooks branch exits without reading", closes_with: "a harness run on a host without node with the overlay installed, or draining stdin in both branches" }
    - { claim: "Concurrent appends across a cap rewrite lose at most one line (pre-existing race, spec residual)", closes_with: "a concurrency stress test; not claimed by this scope" }
  overall: pass
```

## Scope and preflight

- Scope: `git diff 3b092c64..43e6f10a` on `change/node-first-sync-hook-slice` (four commits: intake, spec freeze, implementation c7da7caa, remediation 43e6f10a). Worktree mode (spec: User decision worktree). Working tree at review start: only `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl` modified (ledger appends), unchanged by this review.
- Spec: frozen `docs/specs/SPEC-0247-spec-node-first-sync-hook-slice.md`; sha256 matches the round-2 validation outcome block; `spec-lint` LINT PASS; `check-test-registration` exit 0.
- Inputs read: both validation reports (VALIDATION-20261023T150942Z, VALIDATION-20261023T154956Z), the module, both launchers and their baseline versions, both test files, the bash suite diff, the wiring diffs, the hook template, the ps1-quality jobs.
- Dispatch note (anti-gaming): the dispatch listed prior validation notes (F2, F3, H1, N1) and focus areas. That is context, not pre-rated severity; every finding below was re-derived and probed independently, and the whole scope was reviewed.

## Reviewer reruns (local, macOS arm64, Node 22.23.1, pwsh 7.6.3)

| Command | Result |
|---|---|
| `node --test tests/skills/lib/live-spool.test.mjs` | 12 pass, 0 fail |
| `bash tests/skills/test-aai-live-status.sh <fn>` for 2408, 2409, 2410, 2411, 2412, 2414, 2417, 2418, 2420 | all PASS (2412: Total=7 Passed=7 Failed=0 Skipped=0) |
| `bash tests/skills/test-aai-layer-profiles.sh test_2416_live_spool_module_classified` | PASS |
| Scratch probes (copy of the three files under a path with a space) | sh and ps1 launchers append one line and print the passthrough; unwritable spool dir -> rc 0, passthrough, empty stderr; closed stdout -> rc 0, empty stderr; launcher without module -> rc 0, empty stdout (finding 1); symlinked launcher -> empty stdout, no line (finding 1); BOM payload -> no line (finding 3); Node-absent hooks with 2 MB stdin -> writer SIGPIPE 141 (finding 2) |

## Verdict 1: spec_compliance = pass

All ten Spec-AC rows are compliant (walk in the YAML block). Deviations from the frozen spec, listed even where reasonable:

1. `tests/skills/suite-map.yaml:368` adds `.aai/scripts/live-spool.*` to the aai-doctor suite. D3 names only three additions to `aai-live-status`. Reason (commit 43e6f10a, validation r2): aai-doctor TEST-439 guards the argv[1] main-guard convention, so a module change must select that suite; the wildcard (not a literal) keeps the TEST-2417 mutation anchor on the aai-live-status entry. Accepted as correct; it means `.sh` and `.ps1` edits now also select aai-doctor (extra selection only).
2. The main-guard is `realOrResolve(argv[1]) === realOrResolve(module path)` instead of a bare realpath comparison. It meets D1's wording (real path comparison, works with a spaced path) and adds a resolve fallback.
3. `docs/ai/decisions.jsonl` gains a `spec_amendment_classification` line for a different ref (ci-node-24-baseline) and `docs/ai/roadmap.yaml` gains this capability as active; neither is in the spec's inline review scope. Ledger bookkeeping, no behavior.
4. Pending, not yet a deviation: D5's post-LOOP-COMPLETE items are not in the range. `docs/product/live-status-dashboard.md:99-100` still calls the `.ps1` a twin, and `CHANGELOG.md` has no `## [unreleased] — refactor(live): ...` entry. They are owed before PR.

The ten drift decisions (D-1 to D-10) are all implemented as recorded: D-1 `toISOString` (mjs:31), D-2 array/scalar return null (mjs:28-29), D-3 no depth limit, D-4 JSON.parse semantics, D-5/D-6 `'utf8'` with `EOL='\n'` and Node inheriting stdin in the ps1 launcher, D-7 temp file plus rename (mjs:46-50), D-8 parse failure returns null and no file, D-9 both launchers degrade (sh:10-12, ps1:10-12), D-10 unknown kind uses the statusline fields.

## Verdict 2: code_quality = pass

No BLOCKING findings. Module never-throw contract holds: every I/O path is inside try/catch (mjs:55-61, 63, 68, 74), the CLI ends `process.exit(0)` after a synchronous `fs.writeSync`, and nothing writes to stderr. The APIs used are all present in Node 22 (`fs.readFileSync(0)`, optional catch binding, `fileURLToPath`). Launcher quoting is right: `"$MODULE"` and `"$@"` in sh, and `Join-Path $PSScriptRoot` passed as one argument in ps1. Both launchers end `exit 0`. Profiles: the module sits in `extended` next to both launchers, the template and the generator. A `core` install gets none of them and an `extended` install gets all, so no profile combination ships a launcher without its module.

### NON-BLOCKING findings

**NB-1. Silent statusline when node is present but the module cannot run.** `.aai/scripts/live-spool.sh:8-9`, `.aai/scripts/live-spool.ps1:8-9`. Probed: if the launcher is copied without the module, or reached through a symlink (dirname is the link's directory), you get rc 0, empty stdout and no spool line. An exported CDPATH with a relative invocation does the same, because `cd` echoes into `MODULE`. The old script always printed the passthrough. The frozen D2 shape mandates this exactly, so fixing it needs a D2 amendment, for example a `||` passthrough after a non-zero node exit, restructured so the passthrough literal still appears once (TEST-2408).
Recommended disposition: (b) promote to a typed follow-up, P3, together with NB-2 because both amend D2. Suggested id `fu-live-spool-launcher-fallbacks` (suggested, not filed).

**NB-2. Node-absent branch leaves stdin unread for hooks (sh) and for every kind (ps1).** `.aai/scripts/live-spool.sh:10-13`, `.aai/scripts/live-spool.ps1:10-12`. Probed: a 2 MB write into `live-spool.sh hooks` with no node on PATH gets SIGPIPE (141). The old `.sh` always drained. Real hook payloads fit in the pipe buffer, so no harness bite has been seen.
Recommended disposition: fold into the NB-1 follow-up (same D2 amendment: `cat >/dev/null` before the kind test). If it is not folded, it qualifies as `accepted residual: Node-absent hooks branch does not drain stdin; only payloads above the pipe buffer can EPIPE the writer, none observed`.

**NB-3. A BOM-prefixed payload is dropped.** `.aai/scripts/live-spool.mjs:27`. This matches the old `.sh`. The old `.ps1` behaved differently and accepted the payload. Probed: no line is written and the passthrough still prints. Claude Code sends no BOM. The case that bites is a hand-wired PowerShell 5.1 caller with a BOM-emitting `$OutputEncoding`.
Recommended disposition: (d) `accepted residual: BOM-prefixed payload is dropped, parity with the old Bash copy; no shipped caller emits a BOM`. In addition, name it in the D5 product-doc edit next to D-1, D-2 and D-9.

### INFO (non-gating)

- N1 (validation): the TEST-2417 mutation anchor is tied to the order of globs in suite-map (doctor glob at line 368 is a wildcard, live-status literal at 709). If someone later adds a literal `live-spool.mjs` above line 709, mutation replay reports a record that no longer reddens. That is loud, not silent, so no action.
- `kind` is joined into the spool path unchecked (mjs:58; `../escape` writes one directory up). This is unchanged from both old copies, and the only caller is the fixed template.
- Under Windows PowerShell 5.1, a caller that sets `$ErrorActionPreference='Stop'` and invokes the launcher with `&` can turn node stderr into a terminating NativeCommandError despite `2>$null`. The module writes no stderr on any path, so this needs a missing module (NB-1).
- Test robustness was checked. `run_spool_node_tests` guards against a vacuous pass (rc check plus `pass [1-9]`). The positive controls in 2409, 2410 and 2411 come first. The Pester helper drives the launcher by bytes through ProcessStartInfo, so the 5.1 step really tests 5.1, and its scratch path has a space. node:test temp dirs are now removed (validation r1 F4 fixed).

## cannot_verify

See the YAML block. Six items. The two that decide merge readiness are H1 (5.1 stdin inheritance, and the Node major on the runner images, because ps1-quality has no setup-node) and H2 (Node 22 floor step). Both are hosted checks the spec already schedules after PR creation.

## Warning dispositions (H6)

| Finding | Recommended disposition | Recorded by |
|---|---|---|
| NB-1 | (b) follow-up P3, suggested `fu-live-spool-launcher-fallbacks` (D2 amendment) | orchestrator |
| NB-2 | fold into NB-1's follow-up, else (d) accepted residual (text above) | orchestrator |
| NB-3 | (d) `accepted residual: BOM-prefixed payload is dropped, parity with the old Bash copy; no shipped caller emits a BOM` and the product doc names it | this report |

## Next steps

1. Orchestrator files or folds NB-1 and NB-2, and records the NB-3 residual in `code_review.notes`.
2. Write the D5 delivery documents (product doc and CHANGELOG entry) after LOOP COMPLETE and before PR. In the product doc, name D-1, D-2 and D-9, plus the NB-3 BOM note.
3. After PR creation, run H1 and H2. If the 5.1 non-ASCII case fails, use the D2 fallback as a recorded amendment.
