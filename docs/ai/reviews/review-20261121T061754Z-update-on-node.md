# Code review: update-on-node (round 1)

```yaml
review:
  scope: "git diff 30c983ef...f707b98b (main...HEAD on feat/update-on-node), restricted to STATE code_review.scope (34 paths); docs/ai/EVENTS.jsonl and docs/ai/tests/test-runs.jsonl are append-only telemetry outside it"
  spec: docs/specs/SPEC-0307-spec-update-on-node.md (plus the 14 ref update-on-node records in docs/ai/decisions.jsonl, read through spec-amend list --json)
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: non-compliant, citation: "D-SAFETY: the new suite must assert a scratch-root repo for every update invocation it makes; tests/skills/test-aai-update-node.sh:501-510 run_launcher_in asserts nothing, and TEST-3960's shell scan (tests/skills/lib/aai-update.test.mjs:201-216, :348) checks no line of the suite (B-1)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/aai-update.mjs:13-33 (node: imports only, anchors once, one spawnSync in runChild, writeFd); TEST-3961 passed in this review (72/72 for TEST-3960..3968)" }
      - { ac: Spec-AC-03, call: compliant, citation: "aai-update.mjs:60-122 parseArgs/resolveBase; TEST-3962 passed in this review" }
      - { ac: Spec-AC-04, call: compliant, citation: "aai-update.mjs:126-155 normSlug/canonicalGuard, run:430-434 before any temp; TEST-3963 passed in this review" }
      - { ac: Spec-AC-05, call: compliant, citation: "aai-update.mjs:176-216 resolveSource; TEST-3964 passed in this review" }
      - { ac: Spec-AC-06, call: compliant, citation: "aai-update.mjs:373-396 createOwnTemp/removeOwnTemp, :450-453 finally, :491-499 handlers; TEST-3965 passed in this review" }
      - { ac: Spec-AC-07, call: compliant, citation: "aai-update.mjs:225-248, :459-470; TEST-3966 passed in this review" }
      - { ac: Spec-AC-08, call: compliant, citation: "aai-update.mjs:251-369; TEST-3967 passed in this review" }
      - { ac: Spec-AC-09, call: compliant, citation: "aai-update.mjs:343-358; TEST-3968 passed in this review" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-3969 green in the validation round 3 evidence (VALIDATION-20261121T055815Z, reused sweep test-20261121-053405); not re-run here" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-3970 green in the validation round 3 evidence; not re-run here" }
      - { ac: Spec-AC-12, call: compliant, citation: ".aai/scripts/aai-update.sh:1-11 equals the D-LAUNCH block; TEST-3971 passed in this review" }
      - { ac: Spec-AC-13, call: compliant, citation: ".aai/scripts/aai-update.ps1:1-13 equals the D-LAUNCH block; TEST-3972 (Pester 5 launcher cases) green in validation round 3" }
      - { ac: Spec-AC-14, call: compliant, citation: "tests/skills/test-aai-update.sh re-homes and EXIT-trap scratch root; four contract records present (spec-amend list); TEST-3973 green in validation round 3" }
      - { ac: Spec-AC-15, call: compliant, citation: "tests/skills/aai-update.Tests.ps1 diff; SPEC-0052 second and SPEC-0285 records present; both follow-ups closed (follow-ups list); TEST-3974 green in validation round 3" }
      - { ac: Spec-AC-16, call: compliant, citation: "tests/skills/lib/install-parity.mjs peers/pairAllowed/upref, allowlist row widened; TEST-3975 green in validation round 3; H2 is hosted" }
      - { ac: Spec-AC-17, call: compliant, citation: "tests/skills/test-aai-update-node.sh:512-575; TEST-3976 green in validation round 3" }
      - { ac: Spec-AC-18, call: compliant, citation: "suite-map aai-update-node row, weights row 196 with its fallback line, PROFILES core, ps1-quality lists; TEST-3977 green in validation round 3" }
      - { ac: Spec-AC-19, call: compliant, citation: "CHANGELOG heading, SKILL_UPDATE sentence and bullet, RFC-0017 sentence, ledger +182; TEST-3978 green in validation round 3" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/lib/aai-update.test.mjs, line: 204,
          issue: "TEST-3960 'every update invocation sets the network-free environment and a repo under the scratch root' claims a universal property but checks no line of the bash suite. The suite has no run_update(), and the entry regex matches 0 of its lines. The suite's real update runs (test-aai-update-node.sh:505-506, through set -- pwsh ... aai-update.ps1 and \"$shell\" .aai/scripts/aai-update.sh) are never seen, and run_launcher_in never asserts that its repo lies under the scratch root",
          failure_scenario: "remove ' GIT_ALLOW_PROTOCOL=file GH_CONFIG_DIR=\"$work/ghcfg\"' from run_launcher_in (or point --repo at the checkout): shellInvocationProblems still returns [], TEST-3960 stays green, and TEST-3976 then runs a real update with gh and https allowed. backed-by: scratchpad repro-scanner.mjs (output: 0 matched lines, [] before and after the mutation)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-update.mjs, line: 206,
          issue: "a clone attempt killed by a signal does not stop the chain: the remaining gh/git attempts still start (the same holds for the three local-checkout git commands at :183)",
          failure_scenario: "Ctrl-C during the gh clone. SIGINT reaches the whole foreground process group, gh dies, then attempts 2 and 3 run against the network with stdio closed, and the user sees nothing until both finish or time out. The bash reference exits on the first SIGINT-killed child. backed-by: scratchpad repro-sigint-chain.mjs (3 children started for {status:null, signal:'SIGINT'})" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-update.mjs, line: 275,
          issue: "changedFiles reads git status through spawnSync's default 1 MiB maxBuffer; ENOBUFS reads as 'no changes'",
          failure_scenario: "a target whose git status --short exceeds 1 MiB (status.showUntrackedFiles=all with an un-ignored generated tree, ~30k entries) prints '- Changed files: none (already up to date)' and drops the bootstrap clause, a false record the agent relays. The bash reference captures it in full. backed-by: scratchpad repro-enobufs.mjs (30000 real lines, 0 returned)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-update.ps1, line: 9,
          issue: "under Windows PowerShell 5.1 (and pwsh 7.0-7.2, legacy native argument passing), & node $Module @args quotes a spaced value with a trailing backslash as \"...\\\", which the C runtime reads as an escaped quote; the old in-process twin bound -Repo natively",
          failure_scenario: "PowerShell tab completion of a local source gives -Repo '..\\my aai\\' -Force. node receives the single argument '..\\my aai\" -Force', so --force is lost and the value is not a directory. It is treated as a slug: gh/https clone attempts, then exit 3. Unbacked (no Windows host here)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-update.ps1, line: 8,
          issue: "the runner is (Get-Process -Id $PID).Path, and resolveRunner refuses any basename other than pwsh/powershell (D-RUNNER, by spec). A host process that is not one of those executables now fails where the in-process twin worked",
          failure_scenario: "running .\\.aai\\scripts\\aai-update.ps1 from PowerShell ISE (powershell_ise.exe) or an embedded runspace host exits 1 with 'AAI_UPDATE_SYNC_RUNNER must be bash or a path to bash, pwsh or powershell, got ...powershell_ise.exe'. Unbacked" }
  cannot_verify:
    - { claim: "Windows behaviour of both launchers and the module (H1: Pester launcher cases under 5.1 and 7; H2: sh:node on windows-parity)", closes_with: "the PR's ps1-quality run, recorded in the validation report" }
    - { claim: "the literal runner 'bash' exported by aai-update.sh resolves to Git Bash when node spawns it on win32 (libuv searches the child cwd, then PATH), and Git Bash accepts the forward-slash C:/ paths", closes_with: "a Git Bash run of the .sh launcher on a hosted Windows runner (no Test Plan row exercises the literal value on win32)" }
    - { claim: "fs.rmSync removes a clone's read-only pack files on Windows under Node 22/24", closes_with: "the hosted Pester clone cases (TEST-009, TEST-3581/3582) on windows-5_1" }
    - { claim: "a Microsoft Store pwsh (WindowsApps path from Get-Process) can be spawned as the sync runner", closes_with: "a manual run on a Store-installed pwsh" }
    - { claim: "the real gh -> git -> anonymous-git chain against GitHub (every test is network-free by design)", closes_with: "a manual /aai-update against goodwind-cz/aai@main" }
    - { claim: "a consumer on an older layer updates once with its old twin, which vendors the launchers and the module, and the next update runs the module", closes_with: "an aai-sync scratch install of a pre-30c983ef tag, then two /aai-update runs" }
    - { claim: "'requires Node.js 22' is stated, not enforced; neither launcher checks the version", closes_with: "a run under Node 18/20, or a version check if the floor matters" }
    - { claim: "TEST-3969, 3970 and 3972 to 3978 pass at f707b98b", closes_with: "validation round 3 evidence (gitignored, not re-run in this review); TEST-3960 to 3968 and TEST-3971 were re-run here and pass" }
  overall: fail
```

security_relevant: true

## Scope and spec

- Scope: `git diff 30c983ef...HEAD` (HEAD `f707b98b`, branch `feat/update-on-node`, worktree
  `/Users/ales/Projects/aai-worktrees/update-on-node`), restricted to the 34 paths in STATE
  `code_review.scope`. `worktree.user_decision: worktree`, so this is the diff-range mode. `git status --porcelain` was clean.
- Spec: `docs/specs/SPEC-0307-spec-update-on-node.md` (frozen). Its post-freeze amendments were read with
  `node .aai/scripts/spec-amend.mjs list --json`. There are 14 ref `update-on-node` records: the mutation-cell escapes, the D-DOCS/D-WIRE
  additions, the TEST-3956 re-home, the async `run` and stage-boundary signal handling in D-TEMP, and the eight D-REHOME
  records for SPEC-0052 (two), SPEC-0124, SPEC-0020, SPEC-0179, SPEC-0285, SPEC-0284 and SPEC-0306. The amended D-TEMP text
  (yield after the guard, the source, the sync, git status and the doctor; listeners removed in `finally`) matches
  `aai-update.mjs:427-499`.
- Re-run in this review: `node --test --test-name-pattern 'TEST-396[0-8]' tests/skills/lib/aai-update.test.mjs`
  passed 72 of 72. `test-aai-update-node.sh test_3971_sh_launcher` passed. `spec-lint` on the spec reported LINT PASS. No sweep was run.

Dispatch notes, recorded under the anti-gaming contract:

- The dispatch prompt listed focus areas (Windows bash-runner paths, PS launcher restore, exit codes, quoting, safety,
  pipefail traps, downstream, DRY/KISS). That steers attention, although it neither pre-rates severity nor excludes an
  area. The full scope was reviewed anyway.
- The dispatch said to write the report to `docs/ai/reports/...`. The prompt says `docs/ai/reviews/`. This report follows
  the prompt.

## AC walk

See the yaml block. 18 of the 19 rows are compliant. Spec-AC-01 is non-compliant on its D-SAFETY clause. The JS
invocation helper `runUpdate` (`aai-update.test.mjs:105-119`) does build the network-free environment and calls
`assertRepoUnderRoot`. The bash suite's one real update helper `run_launcher_in` (`test-aai-update-node.sh:501-510`) sets
the environment, but its repo argument is never asserted, and TEST-3960's shell half verifies nothing (B-1). The suite's
current invocations do pass a scratch-root repo (`$work/source`). What is missing is the assertion D-SAFETY requires and
the check TEST-3960 claims to make.

Other deviations from the frozen text, none of which gates the review:

- The Test Plan Status column says `done` for TEST-3971 and TEST-3973 and `green` for the other rows (validation N-2, cosmetic).
- "Constitution deviations" says "two launchers of at most 13 lines", while D-LAUNCH says at most 20. The delivered
  launchers have 11 and 13 lines, so both texts hold. The spec contradicts itself.
- The D-REF lifetime and the D-FU follow-ups are present: the four P3 items are open and the two closed items are closed.

## Findings

### BLOCKING

**B-1. TEST-3960's universal invocation claim is vacuous for the bash suite**
(`tests/skills/lib/aai-update.test.mjs:201-216`, test at `:348`; `tests/skills/test-aai-update-node.sh:501-510`).

- Why: `shellInvocationProblems` anchors on a `run_update() {` function and on an entry regex that needs a literal
  `bash|sh|dash|node|pwsh` word right before the entry path. The suite has no `run_update`. Its real update runs go through
  `set -- pwsh -NoProfile -File .aai/scripts/aai-update.ps1 -Repo "$src" -Force` and
  `set -- "$shell" .aai/scripts/aai-update.sh --repo "$src" --force`, and the regex matches neither. It matches 0 lines of
  the suite. The scan returns `[]` as committed, and still returns `[]` after the network-free environment is stripped from
  `run_launcher_in`. The test name claims a universal property ("every update invocation ...") that it proves for no shell
  path. The review prompt ranks that BLOCKING. D-SAFETY also requires the suite to assert the scratch-root repo for every
  update invocation, and `run_launcher_in` has no such assertion.
- backed-by: `/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/review-repro/repro-scanner.mjs`
  prints `suite has run_update(): false`, `suite lines the entry regex matches: 0`, `problems on the mutated suite: []`.
- Minimal fix:
  1. Rename `run_launcher_in` to `run_update`, the anchor the scanner looks for.
  2. Inside it, before the `env` call, add
     `case "$src" in "$work"/*) ;; *) log_fail "run_update: repo $src lies outside the scratch root $work" ;; esac` and
     `[[ -z "$(ls -A "$work/ghcfg")" ]] || log_fail "run_update: GH_CONFIG_DIR is not empty"`.
  3. Make the scanner flag any non-comment line outside `run_update` that names `aai-update.(sh|ps1|mjs)` together with an
     update argument (`--repo`, `-Repo`, `--dry-run`, `-DryRun`), whatever word precedes the path.
  4. Add a positive control to the TEST-3960 case: the committed suite with the env stripped from `run_update` must report
     at least one problem.

  The stub pass-through runs (`expect_pass_through`) and the no-node refusals (`expect_refusal`, TEST-3976 `:567`) start
  no real update. Either route them through the same helper or exempt them by name in the scanner, for example any line
  whose launcher copy sits beside a stub module.

### NON-BLOCKING (WARNINGs, each needs a disposition before closeout)

**N-1. The clone chain survives a signal-killed attempt** (`.aai/scripts/aai-update.mjs:206-211`; also the local-checkout loop at `:183-189`).

- Failure scenario: the user presses Ctrl-C during `gh repo clone`. SIGINT goes to the foreground process group, so gh
  dies. The loop still starts the plain and the anonymous `git clone`, with stdio closed, so the user sees nothing for up
  to two more network timeouts. The run then exits 130, so the amended spec's "stops before the sync" holds.
- Validation's probes sent SIGTERM to the module only, which does not kill the clone child, so they could not see this.
- backed-by: `/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/review-repro/repro-sigint-chain.mjs`
  starts 3 children for `{ status: null, signal: 'SIGINT' }`.
- Fix: add `if (r && r.signal) break;` after `ran.push(...)`, the same in the local-checkout loop, and one injected-spawn
  case in TEST-3964.
- Recommended disposition: (a) remediate in tree. If deferred, use (b) `fu-update-clone-chain-ignores-sigint`, P3.

**N-2. A large `git status` reads as "already up to date"** (`.aai/scripts/aai-update.mjs:275`).

- Failure scenario: `spawnSync` defaults to `maxBuffer` 1 MiB. Beyond that it returns ENOBUFS, and `changedFiles` maps it
  to `[]`. The run then prints `- Changed files: none (already up to date)` and drops the bootstrap clause. That is a false
  record the agent relays.
- backed-by: `/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/review-repro/repro-enobufs.mjs`
  (30000 real status lines, `changedFiles()` returned 0).
- Fix: add `maxBuffer: Infinity` (or a large bound) to the options at `:275`, plus a test with an injected
  `{ error: { code: 'ENOBUFS' } }` that expects something other than the none line, or a larger real fixture.
- Recommended disposition: (a) remediate in tree. It leaves a false record, so (d) is not available. If deferred, use (b)
  `fu-update-status-maxbuffer`, P2.

**N-3. PowerShell 5.1 legacy argument passing breaks a spaced `-Repo` with a trailing backslash** (`.aai/scripts/aai-update.ps1:9`).

- Failure scenario: tab completion yields `-Repo '..\my aai\' -Force`. Windows PowerShell 5.1 builds `"..\my aai\"`, and
  node receives `..\my aai" -Force` as one argument. `--force` is lost, the value is treated as a slug, the https clone
  attempts run, and the update exits 3.
- The old twin bound `-Repo` in process and never hit this. pwsh 7.3 and later pass the argument correctly.
- Unbacked: no Windows host was available.
- Recommended disposition: (b) `fu-update-ps51-trailing-backslash-arg`, P3. A Pester case with a trailing-backslash value
  on the windows-5_1 job would back or close it.

**N-4. PowerShell hosts other than pwsh or powershell are refused** (`.aai/scripts/aai-update.ps1:8` with `aai-update.mjs:229-234`).

- Failure scenario: from PowerShell ISE (`powershell_ise.exe`) or an embedded runspace host, the launcher passes the host
  executable, and the module exits 1 with the runner line. The in-process twin worked there.
- This is spec-mandated (D-RUNNER refuses any other value), so it is a downstream consequence of a frozen decision, not an
  implementation slip.
- Unbacked.
- Recommended disposition: (b) `fu-update-ps1-non-console-host`, P3. A possible remedy is for the launcher to fall back to
  `powershell.exe` or `pwsh` on PATH when the basename is not one of the four.

### INFO (never gate)

- `test-aai-update-node.sh:68-69` and `update-reference.mjs:63-65`: the marker "re-read right before removal" reads the
  same file twice back to back. The second read adds no protection. It is harmless, but the comment promises more than the code does.
- `test-aai-update-node.sh:344-349` repeats the `amend_found` logic that `:406-413` defines (DRY). The function could be
  defined once above `test_3973`.
- `test-aai-update.sh` test_002 regex `removeOwnTemp\((state|watched)\.tmp, ...` keeps a vestigial `watched`
  alternative from before the round-2 fix.
- `test-aai-update.sh` 0137-TEST-009 keeps the pre-existing `if tr ... | LC_ALL=C grep -q` under pipefail. The region
  is far below a pipe buffer, so `tr` cannot take SIGPIPE in practice. This ride did not introduce it.
- `test-aai-win-fallback.sh` `ps1f_derive`: `first_file` from `mktemp` has no trap. Only greps run between create and
  `rm -f`, so the leak window is negligible.
- Pipefail audit of the new and changed bash code found no `cmd | grep -q` or `| head` outside `qgrep`/`qhead`, and no
  bare `rc=$?` after a failing command. Every capture uses `|| rc=$?` or `|| true`.
- Safety audit: the module removes only `path.join(<own mkdtemp>, 'src')` (per attempt) and its own mkdtemp directory,
  through `removeOwnTemp` with identity, prefix, lstat and parent-realpath checks. The tests delete only through
  `removeOwnScratch` or the two `safe_rm_own` helpers. No `docker`, `pkill` or `killall` appears (TEST-3960's
  `forbiddenCalls` scan, positive controls included). The PowerShell launcher restores `AAI_UPDATE_SYNC_RUNNER` in
  `finally` (`$null` unsets it), and exit codes pass through `exec` and `exit $LASTEXITCODE`.

## Warning dispositions (H6)

| WARNING | Recommended disposition | Artifact to record |
|---|---|---|
| N-1 | (a) remediate in tree; else (b) P3 | fix commit, or `fu-update-clone-chain-ignores-sigint` |
| N-2 | (a) remediate in tree; else (b) P2 (false record: (d) not allowed) | fix commit, or `fu-update-status-maxbuffer` |
| N-3 | (b) P3 | `fu-update-ps51-trailing-backslash-arg` |
| N-4 | (b) P3 | `fu-update-ps1-non-console-host` |

The orchestrator records the chosen artifacts. A read-only reviewer files no refs.

## Next steps

1. Remediate B-1 in the test code only (rename, two assertions, a wider scan, a positive control), re-run
   `test-aai-update-node.sh test_3960_scratch_safety` and `test_3976_scratch_install`, and refresh the TEST-3960 mutation record.
2. Fold N-1 and N-2 into the same remediation pass (two one-line module changes, each with a unit case), or file them as follow-ups.
3. File N-3 and N-4 as P3 follow-ups.
4. Re-review the remediation delta.
