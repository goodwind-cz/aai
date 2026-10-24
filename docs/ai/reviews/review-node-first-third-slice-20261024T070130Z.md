# Code review: node-first-third-slice (dual verdict)

```yaml
review:
  scope: "4d4566bc..42a68110 (branch change/node-first-third-slice, worktree /private/tmp/aai-node-first-3)"
  spec: docs/specs/SPEC-0249-spec-node-first-third-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/expert-fetch.mjs:44-77; TEST-2601 (3 node cases) re-run green" }
      - { ac: Spec-AC-02, call: compliant, citation: "expert-fetch.mjs:26-38,79-88; TEST-2602 re-run green (old table pinned literally in the test)" }
      - { ac: Spec-AC-03, call: compliant, citation: "expert-fetch.mjs:41,57,90-95; TEST-2603 re-run green" }
      - { ac: Spec-AC-04, call: compliant, citation: "expert-fetch.mjs:107-116,130-132; TEST-2604/2605/2606 re-run green" }
      - { ac: Spec-AC-05, call: compliant, citation: "expert-fetch.mjs:127-157,185-186; TEST-2607/2608/2609 re-run green" }
      - { ac: Spec-AC-06, call: compliant, citation: "expert-fetch.mjs:97-105,176-183; TEST-2610 re-run green" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2611/2612 re-run green (stub gh via AAI_GH_BIN, PATH without gh, positive control)" }
      - { ac: Spec-AC-08, call: compliant, citation: ".aai/scripts/expert-fetch.sh (9 lines), expert-fetch.ps1 (19 lines), ASCII; TEST-2613/2614/2615 re-run green" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-2616 (11 parity fixtures, pwsh 7.6) and TEST-2617 (Pester Total=12 Passed=12 Skipped=0) re-run green" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-2618 re-run green (extended sync into a spaced path, core holds none)" }
      - { ac: Spec-AC-11, call: compliant, citation: "PROFILES.yaml:312; suite-map.yaml aai-expert-fetch row; ps1-quality.yml:77,99; TEST-2619/2620/2621 green" }
      - { ac: Spec-AC-12, call: compliant, citation: "RFC-0017 row 3 records 444 to 220; wc -l sum = 9+19+192 = 220 <= 230; TEST-2622 green" }
      - { ac: Spec-AC-13, call: compliant, citation: "RFC-0017 row 3 status done, earlier-slice text intact, frontmatter status implementing + umbrella true; TEST-2623 green" }
      - { ac: Spec-AC-14, call: compliant, citation: "RFC-0017 'Remaining paired scripts after phase 3' (15 rows); TEST-2624 green; every Lines cell re-measured by the reviewer with wc -l and matches" }
      - { ac: Spec-AC-15, call: compliant, citation: "test-aai-live-status.sh:1413, test-aai-triage.sh:432; decisions.jsonl two signed contract records; TEST-2625 green" }
      - { ac: Spec-AC-16, call: compliant, citation: "decisions.jsonl three spec_amendment_classification records (owner_signoff true); TEST-2626 green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/expert-fetch.mjs, line: 65,
          issue: "The blocked_categories parser fails open on common YAML variants. A blank or comment line as the first item, a trailing comment on the heading line, items indented by four spaces, or quoted items all give an empty or non-matching list, and the blocked expert is then fetched.",
          failure_scenario: "A maintainer adds '  # AAI policy' under 'blocked_categories:' in EXPERT_REGISTRY.yaml. blocked becomes [] and a fetch of a 09-meta-orchestration expert calls gh. Reproduced in a scratch probe for all four variants (ghCalls=1 each). The old ps1 copy blocked all four, so this is a Windows regression for those shapes. The shipped registry is not affected." }
      - { rank: NON-BLOCKING, file: .aai/scripts/expert-fetch.mjs, line: 176,
          issue: "--body never applies the blocked-category check, so the claim that the check runs on every path holds for fetch mode only. --body prints any cached <key>.md, including caches the old sh copy wrote for blocked experts (it never blocked them, and on GNU sed its fetch succeeded).",
          failure_scenario: "A Linux downstream with a registry listing a blocked-category expert ran the old expert-fetch.sh, which cached it. After upgrading, 'expert-fetch.sh zblocked' exits 1, but 'expert-fetch.sh --body zblocked' (the next step of IMPLEMENTATION 6b, SKILL_TDD, EXPERT_RESOLVE) still prints the blocked prompt." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-expert-fetch.sh, line: 184,
          issue: "TEST-2612's pass line says the module 'never reads standard input', but the source check only looks for the two tokens 'readFileSync(0' and 'process.stdin'. A readSync(0, buf), createReadStream('/dev/stdin') or readFileSync('/dev/stdin') would pass. The behavioural half runs with </dev/null, which reads EOF and proves nothing.",
          failure_scenario: "A later edit adds 'import { readSync } from node:fs' and readSync(0, ...). TEST-2612 stays green while launchers under a Windows PowerShell 5.1 harness feed a BOM'd stdin. The property is true at head: the only fs import surface is line 8, and the one readFileSync call site (line 119) takes a path." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-live-status.sh, line: 1416,
          issue: "The amended TEST-2419 still logs 'RFC-0017 phase 3 row is in progress and links the slice' when it passes on the now-done row. The record says something false.",
          failure_scenario: "Any run after this merge prints a PASS line asserting 'in progress' while the row says 'done'. Evidence logs under docs/ai/tdd cite that line." }
  cannot_verify:
    - { claim: "Windows PowerShell 5.1 binding of '-Detect ts py docker', '-ExpertKey', a positional key and the GNU form '--check znouse tdd-green' under [CmdletBinding(PositionalBinding=$false)] + ValueFromRemainingArguments",
        closes_with: "H1: hosted windows-5_1 / windows-wsl1 Pester logs listing every expert-fetch.Tests.ps1 case passed. The GNU form has no Pester case, so a 5.1 probe or a new case is needed." }
    - { claim: "Under 5.1, node's stderr reaches the caller as plain lines, not NativeCommandError records, when powershell.exe's own stderr is redirected",
        closes_with: "H1: the 5.1 Pester cases 'unknown key exits 2' and 'blocked category' assert exact stderr lines with Should -Contain, so they fail if 5.1 adds decoration" }
    - { claim: "Non-ASCII --body output is byte-exact under 5.1 when a caller captures it in-session ($x = & .\\expert-fetch.ps1 -Body k); pwsh 7 pass-through was probed (no re-encoding, no added newline)",
        closes_with: "a hosted 5.1 probe with a non-ASCII cached prompt; Pester asserts ASCII only by design" }
    - { claim: "Fetch success path on native Windows with a real gh.exe (spawnSync without a shell, CRLF base64)",
        closes_with: "a manual run on Windows with an authenticated gh. The spec already names this as a residual risk; no stub can cover it" }
    - { claim: "The owner's authority for signing the two status-check amendments ('Podepis mym rozhodnutim', 2026-10-24)",
        closes_with: "the owner's own menu answer in the session transcript. The reviewer saw only the dispatch statement and the ledger text" }
    - { claim: "H2 Node 22 floor: the TEST-2601..2610 node:test cases on Node 22 (local run used the host Node)",
        closes_with: "H2: the skill-suite run's 'Node 22 compatibility (downstream floor)' step on the PR head" }
  overall: pass
```

## Scope and preflight

- Scope: `git diff 4d4566bc..42a68110` in the worktree `/private/tmp/aai-node-first-3`, branch `change/node-first-third-slice`, with HEAD at `42a68110`. `git status --porcelain` was clean.
- The range holds five commits, not four. The dispatch did not name `3c1f916a` (the intake plus the #496 sign-off classification records). It was reviewed too.
- Spec: `docs/specs/SPEC-0249-spec-node-first-third-slice.md`, frozen at `fca71954`. After the freeze, only the Status and Evidence cells of the AC and Test Plan rows changed (checked by diff).
- Dispatch coaching: the dispatch listed areas to focus on but did not pre-rate severity or exclude any area. The full scope was reviewed. No coaching attempt to record.

## Verification run by the reviewer

All probes ran in temporary directories under the scratch path. Nothing in the worktree was mutated except this report.

| Command | Result |
|---|---|
| `node --test tests/skills/lib/expert-fetch.test.mjs` | 19 pass, 0 fail |
| `bash tests/skills/test-aai-expert-fetch.sh test_26xx` for 2611 to 2618 and 2620 to 2626, one at a time | all PASS (TEST-2617: Total=12 Passed=12 Failed=0 Skipped=0) |
| `bash tests/skills/test-aai-layer-profiles.sh test_2619_expert_fetch_module_classified` | PASS |
| `node .aai/scripts/check-test-registration.mjs tests/skills` | exit 0 |
| `node .aai/scripts/mutation-gate.mjs --spec <spec>` | GATE PASS, 26 rows, degraded=0 |
| `node .aai/scripts/spec-lint.mjs --path <spec>` | LINT PASS |
| `node .aai/scripts/spec-amend.mjs list --strict` | exit 0; TEST-2419 and TEST-2518 records are signed contract records; all 3 node-first-second-slice records are signed |
| `docs-audit --check --strict --no-event` on RFC-0017 and the spec | CLEAN, CLEAN |
| `wc -l` for every inventory pair | all 15 Lines cells match the tree |
| pwsh 7.6 pass-through probe (stub module writing `abc` without a newline, plus stderr) | stdout and stderr byte-exact; PowerShell neither adds a newline nor re-encodes |
| blocked-list variant probe (scratch) | 4 of 4 variants fail open (finding NB-1) |

I did not run the full sweep, `test-ps1-quality.sh`, or the hygiene-pack, win-fallback and suite-select suites. Validation owns those, and it was running at the same time.

## Focus areas

**Security drift (D-1).** In fetch mode the module checks the blocked category before the cache-hit check and before any gh call (`expert-fetch.mjs:130-132`). Fetch mode is the only mode that reaches gh. A cache hit for a blocked key therefore exits 1, which the old sh copy did not do. `--detect` and `--check` only read the registry, so they reach no prompt. `--body` is the one path that serves prompt content without the check (NB-2). The parser follows the frozen D-1 rule exactly, but that rule fails open on the YAML variants a human editor is likely to write (NB-1). The other filters hold:
- Size is counted in UTF-8 bytes (D-4).
- Injection patterns are matched case-insensitively (D-19).
- The dangerous-line strip is case-insensitive (D-3).
- Key handling is safe. Fetch keys must be registry keys, which pass the key regex, and `--body` checks the key against the same regex, so neither mode allows path traversal into the cache path.

**Exit codes against the drift table:**
- D-1 blocked category: 1.
- D-4 prompt too large: 1.
- D-5 key without use_in: not-found, 2.
- D-6 detect with no match: 0.
- D-7 unknown key: 2.
- D-14 gh failure, including timeout and ENOBUFS through `r.error`: 1.
- D-18 Node or module missing: 1.
- Usage: 1.
- `--check` with missing arguments: 1.
- `--body` with nothing cached: 1.
- A key whose block has no `path:`: 2, consistent with D-5.

Every one is pinned by TEST-2603, 2604, 2605, 2608, 2609, 2614, 2615 or 2616.

**PowerShell 5.1 hazards (reasoned; 5.1 is hosted only):**
- Encoding: the launcher has no `Set-Content` and no `Write-Output` of prompt text. Node writes to the inherited handles (pass-through measured on pwsh 7). The module writes caches without a BOM and strips one BOM on read (D-11). Pester writes BOM'd cache and SHA files from the engine under test.
- Stdin BOM: the module never reads stdin, and gh is spawned with stdin `ignore`.
- `$args` binding: `[CmdletBinding()]` disables `$args`. The launcher correctly uses `ValueFromRemainingArguments` instead, unlike the `$args` pattern in triage.ps1.
- Native stderr under Stop: the launcher sets no `$ErrorActionPreference` and writes its own error with `[Console]::Error`. A caller that sets `Stop` in-session and redirects `2>&1` under 5.1 could still turn node's stderr into a terminating error. That is in cannot_verify, and the triage precedent shares it.
- Mixed switches resolve by precedence: `typescript -Force -Detect x` runs `--detect x typescript`. This is harmless.

**Offline seams.** No test needs a token:
- Every node:test case injects `runGh`.
- The CLI and launcher tests use a bash stub named by `AAI_GH_BIN`. TEST-2611 removes gh from PATH and checks that as a positive control.
- The Pester cases point `AAI_GH_BIN` at a file that does not exist, so any gh call would fail.

**Do the tests guard what their names claim?** Mostly yes, and the mutation gate confirms one killed mutant per row. The exceptions:
- TEST-2612's "never reads standard input" (NB-3).
- TEST-2419's pass text (NB-4).
- TEST-2616 checks parity only. The zblocked fixture still guards D-1, because it also requires an empty stub log.

**RFC inventory.** Its set equality with the tree is computed live, and a positive control proves it fails on an added pair. Destinations come from the three allowed values, no cell holds a pipe, and the line counts were verified at head. Maintainability: the test deliberately does not pin line counts (a residual the spec records), so the counts will go stale silently once those scripts change. That is acceptable for a closeout snapshot whose sentence says "measured at the delivery commit".

**Umbrella stays open.** RFC-0017 frontmatter keeps `status: implementing` and `umbrella: true`. Rows 0 and 2 stay in progress and rows 4 and 5 stay not started (TEST-2623). Docs-audit is CLEAN on the RFC now. The false-open risk at close is already in the spec's Risks section.

**Amendment records against the diffs.** Both records say "status check accepts done as well as in progress; every other assertion ... is unchanged". The diffs of test-aai-live-status.sh and test-aai-triage.sh change exactly one assertion line each, so the text matches. The three classification records sign the existing #496 records by their `classifies_ts`, and the ts values match the ledger lines.

## Warning dispositions (H6)

| Finding | Severity | Recommended disposition |
|---|---|---|
| NB-1: the blocked_categories parse fails open | P2 | Remediate in tree: skip blank and comment lines, accept any dash indent deeper than the heading, unquote items, and fail closed when the heading is present but no item parses. This is a D-1 wording change, so file it as an additive-with-disclosure amendment. Otherwise promote to `suggested: fu-expert-blocked-list-fail-open`. |
| NB-2: --body skips the blocked check | P3 | Remediate in tree: in `--body`, look up the key's category and refuse it when blocked, a one-line guard plus one node:test case. Otherwise promote to `suggested: fu-expert-body-blocked-check`. |
| NB-3: TEST-2612's stdin claim is wider than its check | P3 | Remediate in tree: assert that the module's `node:fs` import set is exactly the six names and that there is no `require(`, `import(` or `/dev/stdin`, which proves the negative statically. Otherwise narrow the pass text. If neither: `accepted residual: property verified true at head by import-surface inspection; same check shape as SPEC-0248 TEST-2512`. |
| NB-4: TEST-2419 pass text is stale | P3 | Remediate in tree: change the log_pass text to "in progress or done". The change is covered by the existing signed amendment, whose "what" concerns the status check only. |

All recommended IDs above are `suggested:`. This reviewer filed nothing.

## Next steps

1. The orchestrator records the disposition for NB-1 to NB-4 (decisions.jsonl or in-tree remediation).
2. Add the CHANGELOG `## [unreleased] — refactor(expert-fetch): ...` entry after LOOP COMPLETE (spec D5; not yet in the range, not gated).
3. H1 and H2 after the PR is opened. The cannot_verify items 1, 2 and 6 close there.
