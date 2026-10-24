```yaml
review:
  scope: 8df911c5..82f2487c (branch change/node-first-second-slice, worktree /private/tmp/aai-node-first-2)
  spec: docs/specs/SPEC-0248-spec-node-first-second-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/triage.mjs:61-70; TEST-2501 (node --test 8/8, suite PASS)" }
      - { ac: Spec-AC-02, call: compliant, citation: "triage.mjs:15,16,36-37,57,62,75,22/50; TEST-2502..2506 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "triage.mjs:79-97; TEST-2507 PASS (stderr-empty clause weakly pinned, see NB-2)" }
      - { ac: Spec-AC-04, call: compliant, citation: "triage.mjs has no forbidden token; TEST-2508 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "triage.sh:1-9 and triage.ps1:1-13 match the D2 shapes verbatim; TEST-2509..2511 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-2512 PASS (7 fixtures); Invoke-Pester triage.Tests.ps1 8/8, 0 skipped, pwsh 7.6.3" }
      - { ac: Spec-AC-07, call: compliant, citation: "PROFILES.yaml:228; TEST-2514 PASS (spaced core target, real docs-audit)" }
      - { ac: Spec-AC-08, call: compliant, citation: "PROFILES.yaml:228, suite-map.yaml aai-triage row, ps1-quality.yml:76,97; TEST-2515..2517 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "RFC-0017 phase 3 row; TEST-2518 PASS; live-status suite PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "row records 140 to 129; wc -l 107+13+9=129; TEST-2519 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: "decisions.jsonl 7 classification records; TEST-2520 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/triage.ps1, line: 7,
          issue: "The ($args -contains '--check') clause is pinned by no test; deleting it survives TEST-2511, TEST-2512 and TEST-2513 because pwsh -File binds --check to -Check.",
          failure_scenario: "From a PowerShell prompt or -Command, `& ./.aai/scripts/triage.ps1 --check` puts --check in $args. With the clause removed, a NEEDS-TRIAGE audit exits 0 instead of 1 (measured on pwsh 7.6.3: real rc=1, mutant rc=0), so the CI gate passes silently." }
      - { rank: NON-BLOCKING, file: .aai/scripts/triage.mjs, line: 80,
          issue: "The child-stderr discard (D-12, Spec-AC-03 'nothing to stderr') is pinned by no test; every fixture is a git repository whose children write no stderr.",
          failure_scenario: "Changing stdio[2] from 'ignore' to 'inherit' survives TEST-2507/2508/2510/2512/2514. In a root that is not a git repository, the mutant then prints 'fatal: not a git repository' on stderr (measured). Under a 5.1 caller that runs with Stop, that stderr line can raise." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-hygiene-pack.sh, line: 2131,
          issue: "TEST-487 now asserts -eq 111, but its failure message still says 'want 110'.",
          failure_scenario: "When the next suite is added, the failure message names the wrong expected count, and the person moving the pin sees two different numbers." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0248-spec-node-first-second-slice.md, line: 301,
          issue: "The spec says 'D-6 is asserted on Linux and macOS' (also at line 400), but no test sends a non-ASCII byte through either launcher. All seven TEST-2512 fixtures are ASCII after the BOM strip.",
          failure_scenario: "A launcher change that captures and re-emits Node's output would pass every test, and the real docs-audit verdict line (em dash) would be garbled on Windows 5.1. The spec text then records an assertion that does not exist." }
  cannot_verify:
    - { claim: "Windows PowerShell 5.1 binds a literal --check (D-7) to $Check or $args and passes the launcher's inherited stdout through without re-encoding (D-6)", closes_with: "H1: ps1-quality windows-5_1 and windows-wsl1 logs showing triage.Tests.ps1 8/8, including the literal --check case" }
    - { claim: "The isMain realpath comparison and spawnSync('git') behave on native Windows", closes_with: "H1 (the same isMain pattern already passed hosted CI in live-spool.mjs:67-72)" }
    - { claim: "The module runs on the Node 22 floor in CI", closes_with: "H2: Node 22 compatibility step listing TEST-2501..2506 (verified locally on v22.23.1 only)" }
    - { claim: "The CHANGELOG entry naming D-1, D-4 and D-8 (D5, after LOOP COMPLETE)", closes_with: "a CHANGELOG.md diff at ship time; it is not in this range" }
    - { claim: "The real docs-audit --quick stays read-only when triage runs in a downstream install", closes_with: "a TEST-2508-style before/after diff around the real docs-audit (TEST-2508 uses a stub)" }
  overall: pass
```

# Code review: node-first-second-slice

- **Scope:** `8df911c5..82f2487c` (4 commits, 20 files). Worktree `/private/tmp/aai-node-first-2`; the tree was clean when the review started.
- **Spec:** `docs/specs/SPEC-0248-spec-node-first-second-slice.md`, frozen at sha256 `c32089f5…`.
- **Reviewer:** dispatched Code Review role, claude-opus-5-5. Read-only on implementation files. Probes ran in the scratch copy `…/scratchpad/cr12-copy`.

**Note on the dispatch:** it named focus areas and cited the precedent findings from SPEC-0247. It did not pre-rate severity or exclude any area. The full scope was reviewed.

## Commands run

| Command | Result |
|---|---|
| `node --test tests/skills/lib/triage.test.mjs` | 8 pass, 0 fail (Node v22.23.1) |
| `env -u AAI_ROLE bash tests/skills/test-aai-triage.sh` | rc 0, 19 functions PASS, about 19 s |
| `Invoke-Pester tests/skills/triage.Tests.ps1` (pwsh 7.6.3) | Total 8, Passed 8, Failed 0, Skipped 0 |
| `bash tests/skills/test-ps1-quality.sh` | rc 0, 173/173 Pester, 0 skipped |
| layer-profiles, suite-select, win-fallback and live-status suites (wrapper) | all PASS |
| hygiene-pack `test_090_suite_map_pin`, `test_129_mutation_gate_suite_registration` | PASS (pin at 111) |
| `mutation-gate.mjs --spec …` | GATE PASS: 20 rows, degraded=0 |
| `spec-lint.mjs`; `check-test-registration.mjs tests/skills` | LINT PASS; rc 0 |
| `check-cd-subshell-leak.mjs` | rc 0; after removing the new `test-aai-triage.sh` row in scratch: `FAIL: NEW … 0 -> 2`, so the row is required |

## AC walk

All 11 Spec-ACs are compliant; the YAML block above gives a citation for each. Each claimed TEST id exists and passes.

Both launchers match the D2 shapes byte for byte. The module carries every D1 mutation-anchor line and is 107 lines, ASCII only.

Checks against the drift decisions, each verified in code:
- **D-1:** ASCII header.
- **D-2:** `split(/\s+/)[1] ?? ''`, so `unknown`, matching awk `$2`.
- **D-3:** `readText` strips one BOM.
- **D-4:** case-sensitive `includes` and the anchored SHOWN regex.
- **D-5:** `stripCr`.
- **D-8:** UNKNOWN fallback.
- **D-9:** `fs.existsSync` gate.
- **D-11:** stdout is used regardless of status.
- **D-12:** git output is used only on status 0, and stderr is ignored.
- **D-13:** `toISOString` with the milliseconds cut; the last tick line.

`parseArgs` now accepts `--check` in any position. The old `.sh` copy honoured only `$1`. This follows the D1 anchor; it is a harmless widening.

## Launcher fallback: probes beyond the tests

- **Node absent, or module absent:** both launchers print exactly the UNKNOWN line, write nothing to stderr and exit 0, with and without the check flag. TEST-2510 and TEST-2511 cover both, with positive controls.
- **Module present but failing to load** (scratch syntax error):
  - `triage.sh` and `triage.sh --check`: rc 1, empty stdout, Node's stack on stderr.
  - `triage.ps1` and `triage.ps1 -Check`: the same.
  - This is the designed D2 behaviour ("a broken gate must not read as clean"). It is the opposite of live-spool, where the status line had to stay non-empty, and the spec chose it deliberately.
- **Non-ASCII passthrough on pwsh 7 (macOS):** a stub audit printing an em dash and é, plus a non-ASCII tick, gave byte-identical stdout through `triage.sh` and `triage.ps1`. Windows 5.1 remains in cannot_verify.
- **Flag binding on pwsh 7:**
  - `-File x.ps1 --check` binds `$Check=True`.
  - `-File x.ps1 foo --check` binds `$Check=True` and puts `foo` in `$args`.
  - `& x.ps1 --check` inside PowerShell gives `$Check=False` and `$args=[--check]`.
  - So the `$args` clause is load-bearing for in-PowerShell invocation. That leads to NB-1.

## Findings

No BLOCKING findings.

### NB-1: `triage.ps1:7`, the `$args --check` clause is unpinned
- **Mutation:** `if ($Check -or ($args -contains '--check'))` changed to `if ($Check)`. TEST-2511, TEST-2512 and TEST-2513 still pass (rc 0 each), because every test invokes the launcher through `-File`, which binds `--check` to `-Check` on pwsh 7.
- **Bite:** `pwsh -Command "& ./.aai/scripts/triage.ps1 --check"` against a NEEDS-TRIAGE stub gives rc 1 with the real launcher and rc 0 with the mutant. The gate passes silently.
- **Recommended disposition:** remediate in tree. Add a Pester case, plus optionally a TEST-2512 side, that invokes `& '<launcher>' --check; exit $LASTEXITCODE` through `-Command` and expects 1. P2.

### NB-2: `triage.mjs:80`, the child-stderr discard is unpinned
- **Mutation:** `stdio: ['ignore','pipe','ignore']` changed to `…'inherit'`. TEST-2507, 2508, 2510, 2512 and 2514 all still pass.
- **Bite:** in a root that is not a git repository, the mutant writes `fatal: not a git repository …` to stderr; the real module writes nothing (measured). This is the D-12 guarantee and the Spec-AC-03 "nothing to stderr" clause.
- **Recommended disposition:** remediate in tree. Add a non-git fixture to TEST-2507: no `git init`, expect `Working tree: clean` and an empty stderr. Promoting it to a follow-up is acceptable instead. P3.

### NB-3: `test-aai-hygiene-pack.sh:2131`, stale failure text
- The pin assertion moved to `-eq 111`, but the message still reads `want 110`. Its PASS text also says "(95)", which predates this diff.
- **Recommended disposition:** remediate in tree; one token. P3.

### NB-4: spec lines 301 and 400 claim a D-6 assertion that no test makes
- The spec says D-6 is asserted on Linux and macOS, but all seven TEST-2512 fixtures are ASCII-only.
- A launcher that re-encodes Node's output would pass every test, and only a hosted 5.1 run with a non-ASCII assertion would expose it.
- **Recommended disposition:** remediate in tree. Either add an em-dash stub-audit fixture to TEST-2512, which makes the Linux and macOS claim true (the probe above shows it passes), or amend the sentence additive-with-disclosure.
- (d) is not available here, because the spec text leaves a false record.

### INFO (no gate)
- **`triage.Tests.ps1:29-30`:** stdout and stderr are read with sequential `ReadToEnd`. A child that writes more than about 4 KB of stderr before closing stdout would deadlock. Node's error stack is about 1 KB, so this is theoretical.
- **`triage.Tests.ps1:43-45`:** the return codes of the fixture git calls are not checked. A failed commit would still surface as a failed "Working tree: clean" assertion, not as a false pass.
- **`triage.mjs:80`:** `maxBuffer` is 64 MiB. A larger porcelain output sets ENOBUFS and the module reports `Working tree: clean`. That needs about 1M changed paths.

## Wiring edits outside the spec's scope list

- **`tests/skills/suite-weights.tsv`** (`aai-triage 212`): follows the file's documented rule "Unsampled suites use the maximum measured weight (212)". This is the same shape as the `aai-ride-handoff` and `aai-state` rows. The 8b8a1526 commit message names it. Honest.
- **`tests/skills/test-aai-hygiene-pack.sh`** (pin 110 to 111, two places): required because the new suite-map row adds a top-level row. Spec D3 implies it ("the hygiene pin requires the row"), but the spec's inline review scope list does not name the file, and the commit message does not mention it. Honest and needed, but undisclosed. See NB-3 for the stale message.
- **`tests/skills/lib/cd-subshell-leak-baseline.tsv`** (hand-added `2 tests/skills/test-aai-triage.sh`):
  - The count matches the checker (2: the two `SCRIPT_DIR`/`PROJECT_ROOT` substitutions).
  - Without the row the checker fails `NEW … 0 -> 2`.
  - A full `--record` would also have lowered 5 unrelated rows (live-spool.sh 2 to 1, docs-audit 26 to 21, and others). Adding the one row by hand is the conservative choice.
  - The spec's condition named only a changed `triage.sh` count, which stayed 1 to 1. This row is a needed deviation that should be disclosed in the PR body.

## Pester 5.1 compatibility (by inspection)

Every construct used exists in Pester 5 on Windows PowerShell 5.1 with .NET Framework:
- `New-PesterConfiguration`
- `Should -BeGreaterOrEqual` and `Should -BeExactly`
- `ProcessStartInfo.StandardOutputEncoding`
- conversion of `object[]` to `byte[]` for `WriteAllBytes`
- `TrimEnd` with single-character strings

stdin is not redirected, so the child inherits it and the .NET Framework stdin BOM cannot reach Node. The module reads no stdin in any case. The file is ASCII only. The engine is `(Get-Process -Id $PID).Path`, so the 5.1 step really tests 5.1. Execution on 5.1 is in cannot_verify (H1).

## Warning dispositions (H6), recommended for the orchestrator to record

| Finding | Recommended disposition |
|---|---|
| NB-1 | remediate in tree (P2) |
| NB-2 | remediate in tree, or follow-up `suggested: fu-triage-stderr-discard-unpinned` (P3) |
| NB-3 | remediate in tree (P3) |
| NB-4 | remediate in tree: add a non-ASCII TEST-2512 fixture, or amend the sentence with disclosure (P3) |

## Next steps

1. Fold NB-1 through NB-4 in one remediation round. Each one is a test or a text edit; no module logic changes.
2. Disclose the hygiene-pack and cd-subshell baseline edits in the PR body.
3. Add the CHANGELOG entry after LOOP COMPLETE.
4. Run H1 and H2 on the PR head.
