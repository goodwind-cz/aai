# Code Review — release-on-node (round 1)

```yaml
review:
  scope: "main...refactor/release-on-node (a01e8db3); STATE code_review.scope path list (21 paths)"
  spec: docs/specs/SPEC-DRAFT-spec-release-on-node.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/release-cut.mjs:21-24,43-112,129-139; TEST-3462 (3 node:test cases pass)" }
      - { ac: Spec-AC-02, call: compliant, citation: "release-cut.mjs:95-112,148-161; TEST-3463 (sh + ps1 plan, snapshot unchanged)" }
      - { ac: Spec-AC-03, call: compliant, citation: "release-cut.mjs:57-73 + lib/release-rollup.mjs (unchanged); TEST-3464 DR-01..DR-09" }
      - { ac: Spec-AC-04, call: compliant, citation: "release-cut.mjs:75-83,95-112,143-174; TEST-3465 DR-10,DR-12..DR-18" }
      - { ac: Spec-AC-05, call: compliant, citation: "release-cut.mjs:129-139,153-157,177-188; aai-release.sh:97-100; aai-release.ps1:133-136,167; TEST-3466 DR-11,DR-19..DR-22" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-3467; 22 DR ids each begin exactly one case name in tests/skills/lib/release-cut.test.mjs" }
      - { ac: Spec-AC-07, call: compliant, citation: "aai-release.sh:154; aai-release.ps1:208; TEST-3468 byte compare vs rollup of base blob" }
      - { ac: Spec-AC-08, call: compliant, citation: "aai-release.sh:55-57,88-95,112-123; aai-release.ps1:99,123-131; TEST-3469" }
      - { ac: Spec-AC-09, call: compliant, citation: "aai-release.sh 119 code lines (<=160), no awk, 3 module calls at :122,:126,:154; TEST-3470" }
      - { ac: Spec-AC-10, call: compliant, citation: "aai-release.ps1 194 code lines (<=220); helpers above guard :37-80; TEST-3471, TEST-3472 (pwsh 7: 6/6, 15/111 selected, 4/4); 5.1 arm is hosted H1 (cannot_verify)" }
      - { ac: Spec-AC-11, call: compliant, citation: ".aai/system/PROFILES.yaml:97; TEST-3473" }
      - { ac: Spec-AC-12, call: compliant, citation: "test-aai-release.sh:2167, test-aai-learned-routing.sh:75 copy release-cut.mjs; TEST-3474; full caller suites per VALIDATION r3 (11/11)" }
      - { ac: Spec-AC-13, call: compliant, citation: "suite-map.yaml aai-release-cut row + aai-release row; suite-weights.tsv; hygiene-pack test_090 pin 131 / test_129 reads it; TEST-3428/3458 literals removed; ps1-quality.yml both lists; TEST-3475" }
      - { ac: Spec-AC-14, call: compliant, citation: "RFC-0017 inventory row + phase 5 sentence; CHANGELOG.md preamble lines 14-23; TEST-3476" }
      - { ac: Spec-AC-15, call: compliant, citation: "TEST-3477: before 641, after 313, removed 328, module 178; exit 1/12/13/15/20 documented in SKILL_RELEASE.prompt.md:78-86" }
      - { ac: Spec-AC-16, call: compliant, citation: "release-cut.mjs:200; TEST-3478 (two node:test cases pass)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-release.ps1, line: 172,
          issue: "Every refusal (12, 13, 15, 20, audit relay) now reaches the caller as native stderr of `& node` under `$ErrorActionPreference = 'Stop'` (line 97); before this slice the .ps1 wrote its own refusals with [Console]::Error.WriteLine. Windows PowerShell 5.1 can wrap native stderr into NativeCommandError records when its own stderr is redirected, which under Stop is terminating.",
          failure_scenario: "A harness on Windows runs `powershell.exe -File aai-release.ps1 -DryRun` with stderr captured on a CHANGELOG with `## [unreleased] foo`: the node child prints the REFUSED line and exits 12, PowerShell 5.1 promotes the stderr line to a terminating NativeCommandError and the script exits 1 with a decorated `node : REFUSED...` message instead of 12. Same for lines 167 and 208. Still fail-closed (non-zero), so no wrong cut; the exit-code contract breaks. The Pester file redirects stderr and asserts 12/15/20, so hosted H1 decides it." }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 39,
          issue: "The new entry says the preamble states 'the four conditions that every release path refuses with exit 12', which contradicts the preamble it describes (line 14-23: the remote finish refuses with exit 20 and does not check the encoding) and the entry's own line 36.",
          failure_scenario: "A downstream reader of the release notes expects `--confirm` (remote) to exit 12 on a non-UTF-8 CHANGELOG; it does not check encoding and refuses the heading cases with 20. A false statement ships in the release notes." }
      - { rank: NON-BLOCKING, file: .aai/scripts/release-cut.mjs, line: 200,
          issue: "Hand-rolled EPIPE handler instead of lib/cli-pipe-guard.mjs (already recorded by Validation r3 as N10); the spec mandates exit 141, which the shared guard does not provide.",
          failure_scenario: "None observed; a later change to the shared pipe discipline will not reach this module. Maintenance-only." }
  cannot_verify:
    - { claim: "Windows PowerShell 5.1 behaviour of aai-release.ps1: refusal exit codes through native stderr under EAP Stop (finding 1), the UTF-8 plan bytes on the success stream (DR-22, em dashes), DR-06 strict decoding replacing Get-Content's ANSI read, DR-21 missing-node line", closes_with: "hosted ps1-quality Windows jobs (H1) green with release-cut.Tests.ps1 discovered, 6/6, none skipped, under powershell.exe 5.1 and pwsh 7" }
    - { claim: "the three new test files stay within the release-dry-run CI budget as new CHANGELOG readers", closes_with: "required release-dry-run job green on the PR (H2)" }
    - { claim: "--online audit path of the plan (gh authenticated, real origin) behaves as before", closes_with: "a plan run in a repo with an authenticated gh and a reachable origin; unit-covered only via fakes (TEST-3462, DR-20)" }
  overall: pass
```

security_relevant: false

## Scope

- Diff: `git diff main...HEAD` on `refactor/release-on-node` at `a01e8db3` (worktree decision: worktree).
- STATE `code_review.scope` lists 21 paths. The branch also changes `docs/ai/EVENTS.jsonl`,
  `docs/ai/decisions.jsonl` and `docs/ai/tests/test-runs.jsonl` (append-only telemetry ledgers, no
  reviewable code). They are missing from the recorded scope; I read their branch hunks: append-only lines,
  nothing to review. Added to the scope in the state command for completeness.
- Spec: `docs/specs/SPEC-DRAFT-spec-release-on-node.md` (frozen, spec-lint PASS).
- Dispatch prompt: no coaching (no expected findings, severity or exclusions named).

## What I ran

- `env -u AAI_ROLE node --test tests/skills/lib/release-cut.test.mjs`: 29/29 pass, 8.3 s.
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release-cut.sh`:
  rc 0, all 17 rows PASS, 57 s (pwsh 7 present, Pester arm ran: release-cut 6/6, none skipped).
- `bash aai-release.sh --help` old vs new: identical output (awk to sed usage change is behaviour-neutral on BSD sed).
- Verification greps: no prompt or AGENTS change; the coordination files (release-dry-run.mjs, lib/release-rollup.mjs,
  release-finish.mjs, release-first suite/test, aai-win-dispatch.Tests.ps1, aai-update.Tests.ps1) unchanged; git modes
  100755/100644 kept; `git ls-files -ci --exclude-standard` empty (no gitignored artifact committed).
- No full sweep (per dispatch).

## AC table walk

All 16 Spec-ACs compliant (see the YAML block for the per-row citation). Spec-AC-10's Windows PowerShell 5.1 arm
rests on hosted H1 by the spec's own design and is listed under cannot_verify, not counted as a gap.

Deviations from the frozen spec: none found. Checked in particular: D-MOD constants and exports (release-cut.mjs:21-24,
exports at 43-112, 190); D-OUT plan line order and wording, including DR-14's confirm-will-refuse line under a block
(:103-107); DR-15 audit before any stdout (:157-159); DR-16 order 12/13, 15, audit (:163-168); DR-19 temp notes file
outside the root, removed in `finally` (:129-139); DR-20 probe via `config --get` with stderr captured and skipped when
gh blocks or the remote is skipped (:152-156); D-LAUNCH: the remote `--confirm` hand-off precedes the new missing-node
check in both scripts and the `--dry-run` reset block is untouched; D-WIRE pins (131, single literal); D-RFC sentence
and inventory note.

## Findings

### BLOCKING

None.

### NON-BLOCKING

1. **aai-release.ps1:172 (also :167, :208) — refusals now travel as native stderr under `$ErrorActionPreference = 'Stop'`.**
   Failure scenario: Windows PowerShell 5.1 with redirected stderr (any agent harness, CI) turns the node child's
   `REFUSED:` line into a terminating NativeCommandError; exit 1 instead of 12/13/15/20. Fail-closed, but the
   documented exit codes break on that engine. The spec already names the 5.1 stderr hazard (DR-20 row). Hosted H1
   (release-cut.Tests.ps1 redirects stderr and asserts 12, 15, 20) proves or disproves it.
   Recommended disposition: **(a) remediate-in-tree if H1 fails** (run the three `& node` calls with a local
   `$ErrorActionPreference = 'Continue'`, as the Pester helper `Invoke-Git` does); if H1 passes, record as
   `accepted residual: 5.1 native-stderr promotion did not bite on the hosted 5.1 job` (P3).
2. **CHANGELOG.md:39 — the entry misstates the preamble.** "every release path refuses with exit 12" contradicts the
   preamble (remote finish: exit 20, no encoding check) and the entry's line 36. Recommended disposition:
   **(a) remediate-in-tree** — reword to "that the plan, `--dry-run` and the local cut refuse with exit 12".
   It leaves a false record in shipped release notes, so (d) does not apply.
3. **release-cut.mjs:200 — hand-rolled EPIPE handler** (same as Validation r3 N10). The spec's exit-141 contract
   requires it; the shared guard exits with the decided code. Recommended disposition:
   **(d) accepted residual: P3 maintenance divergence mandated by Spec-AC-16, no observed bite, no false record.**

### INFO

- The module's header and both scripts' header comments still list exit 16; the spec documents the cut-path 16 as
  unreachable and leaves the header to slice (b). No failure mode.
- `check_deps` in the suite SKIPs (exit 42) when node is absent instead of using `need_tool`'s CI-fail; node is a hard
  prerequisite of every CI job, so no failure mode today.

## cannot_verify

See the YAML block: Windows PowerShell 5.1 parity (H1), the release-dry-run CI budget (H2), and the `--online` audit
path against a real authenticated origin.

## Next steps

- Remediate NON-BLOCKING 2 (one-line CHANGELOG wording) before the PR.
- After the PR is open, read the hosted ps1-quality 5.1 result; on failure, remediate NON-BLOCKING 1 as described.
- Orchestrator records the dispositions (decisions.jsonl / notes) per H6.
