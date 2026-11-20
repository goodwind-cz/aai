```yaml
review:
  scope: "git diff 34fad51b..fdd3a37e (branch feat/bootstrap-node) over the STATE code_review.scope path list"
  spec: docs/specs/SPEC-DRAFT-bootstrap-on-node.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/lib/bootstrap-reference.mjs:48-72; tests/skills/test-aai-bootstrap-node.sh:59-76; reference sha256 19055401... equals git show 34fad51b; TEST-3940 (scan coverage gap is finding B-1, the property itself holds: the Pester file holds no such call)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:11-33 (node: imports, anchors, runChild), :795 main guard; TEST-3941" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:112-151,739-759; TEST-3942 incl. DR-11 (deviation from bash for a non-canonical PWD is finding N-1; D-ROOT text is followed literally)" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:167-328; TEST-3943" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:244-400; TEST-3944 (dockerTag My Proj--X -> my-proj-x-)" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:402-492; TEST-3945" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:497-605; TEST-3946 against aai-bootstrap-golden.json" }
      - { ac: Spec-AC-08, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:607-639,765-771; TEST-3947 (DR-7)" }
      - { ac: Spec-AC-09, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:643-675 vs .aai/scripts/lib/gitignore-block.sh aai_gitignore_seed_runtime; TEST-3948 (DR-4, DR-8)" }
      - { ac: Spec-AC-10, call: compliant, citation: "tests/skills/lib/aai-bootstrap.test.mjs:1348-1436; TEST-3949 masked corpus (K19 asserted divergence DR-10)" }
      - { ac: Spec-AC-11, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:698-726; TEST-3950" }
      - { ac: Spec-AC-12, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:729-734; TEST-3951" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-3952 full corpus K01-K38, stub lines gh/az only K35-K37" }
      - { ac: Spec-AC-14, call: compliant, citation: ".aai/scripts/aai-bootstrap.sh:1-9 equals D-LAUNCH text, mode 100755; PROFILES.yaml:87; TEST-3953" }
      - { ac: Spec-AC-15, call: compliant, citation: "tests/skills/test-aai-bootstrap.sh, test-aai-hooks-overlay.sh, test-aai-sync-seed.sh diffs; spec-amend records SPEC-0157 and SPEC-0029; TEST-3954" }
      - { ac: Spec-AC-16, call: compliant, citation: ".aai/scripts/aai-bootstrap.ps1:1-9 equals D-LAUNCH; tests/skills/aai-bootstrap.Tests.ps1; validate-skills.mjs:13 REQUIRED; TEST-3955 under pwsh 7 (5.1 is hosted H1, cannot_verify)" }
      - { ac: Spec-AC-17, call: compliant, citation: "tests/skills/lib/install-parity.mjs (TWINS.node ops, twinsFor, N5, BS-01..09); allowlist row win-bootstrap-target-root; TEST-3956; install-parity.test.mjs 73/73 rerun by this review (Windows is hosted H2, cannot_verify)" }
      - { ac: Spec-AC-18, call: compliant, citation: "tests/skills/test-aai-bootstrap-node.sh:484-540; TEST-3957" }
      - { ac: Spec-AC-19, call: compliant, citation: "suite-map.yaml aai-bootstrap-node row, suite-weights.tsv 196, hygiene test_090 138, cd baseline 1, ps1-quality.yml lists; check-test-registration and check-vendored-script-deps rc 0 (rerun); TEST-3958" }
      - { ac: Spec-AC-20, call: compliant, citation: "CHANGELOG.md heading once with Node.js 22 and aai-bootstrap.ps1; SKILL_BOOTSTRAP.prompt.md lines 16 and 23; DYNAMIC_SKILLS.md:28; RUNTIME_IGNORE.list header; RFC-0017 phase 5 row; TEST-3959 (body accuracy is finding N-3)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/lib/aai-bootstrap.test.mjs, line: 144,
          issue: "Test named 'the new test files hold no call of a container tool or a kill by pattern' scans NEW_TEST_FILES (lines 30-35), which omits the new Pester file tests/skills/aai-bootstrap.Tests.ps1 - a universal-negative name over a subset of the new test files",
          failure_scenario: "a later edit adds `docker ps` (or `& docker ...`) to aai-bootstrap.Tests.ps1; TEST-3940 and its mutation stay green and the Pester case reaches the container daemon in the windows-5_1/windows-wsl1/gate jobs. backed-by: repro /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/repro-b1-forbidden-scan-coverage.mjs (exit 1: NOT scanned tests/skills/aai-bootstrap.Tests.ps1)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-bootstrap.mjs, line: 150,
          issue: "With no target, the base PWD is returned verbatim; the reference runs cd \"$(pwd)\" && pwd, which canonicalizes it. Unrecorded divergence (not in D-DRIFT)",
          failure_scenario: "PWD=<dir>/ (trailing slash) or PWD=<dir>/sub/.. with cwd <dir>, then `sh .aai/scripts/aai-bootstrap.sh`: summary 'Target:' and the marker '- Target root:' read '<dir>/' or '<dir>/sub/..' where the reference writes '<dir>'. repro /private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/repro-n1-pwd-not-canonical.sh (exit 1)" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-bootstrap-node.sh, line: 52,
          issue: "Per-test scratch roots (new_own_scratch launcher/install/parity/wiring/docs) are removed only on the success path; log_fail exits and the EXIT trap removes only TEST_DIR, so every failing run leaks them",
          failure_scenario: "any RED, mutation or real failing run outside the aai-run-tests temp root: observed 42 leaked $TMPDIR/aai-bootstrap-node.{launcher,install,parity,wiring,docs}.* directories (49 MB, each install copy 5.2 MB) from this ride's runs" }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 35,
          issue: "Body says 'Arguments, exit codes and every generated byte stay as they were' and lists DR-1/2/4/5/9/10 but not DR-11, which changes the exit code; also a missing comma before 'DR-9'",
          failure_scenario: "a downstream user runs `aai-bootstrap.sh --` (or -P/-L): the old script bootstrapped HOME with exit 0, the new one exits 1; the release note says exit codes are unchanged" }
      - { rank: NON-BLOCKING, file: tests/skills/lib/install-parity.mjs, line: 744,
          issue: "twinsFor can leave zero twins for a scenario; runScenario then reads results[0].codes and crashes; with one twin a non-bootstrap scenario passes with no pair compared",
          failure_scenario: "`install-parity.mjs run --matrix smoke --twins node --scenario SY-01` exits 1 with 'TypeError: Cannot read properties of undefined (reading 'codes')' (reproduced by this review); `--twins sh,node` on SY-* reports PASS with zero comparisons" }
  cannot_verify:
    - { claim: "Pester aai-bootstrap.Tests.ps1 passes under Windows PowerShell 5.1 and pwsh 7 on native Windows (H1)", closes_with: "the PR's ps1-quality windows-5_1 and windows-wsl1 runs: passed, skipped 4, TotalCount >= 111, elapsed < 600 s" }
    - { claim: "BS scenarios agree on native Windows with only win-bootstrap-target-root covering a divergence (H2)", closes_with: "the PR's windows-parity job report with sh, ps1 and node twins and AAI-PARITY-ELAPSED" }
    - { claim: "Module stderr (conflict lines, hooks ERROR lines, usage) passes through aai-bootstrap.ps1 byte for byte under Windows PowerShell 5.1 when the caller captures stderr", closes_with: "a Pester case on 5.1 that runs the real launcher on a conflict fixture with redirected stderr and asserts the three exact lines (no NativeCommandError decoration); today Windows compares trees and exit codes only" }
    - { claim: "A target ending in a backslash and containing a space (e.g. 'C:\\My Proj\\') reaches the module intact through aai-bootstrap.ps1 under 5.1", closes_with: "a 5.1 Pester pass-through case with that argument" }
    - { claim: "Non-ASCII target paths are byte-equal between reference and module on Linux (GNU tr byte mode) and Windows", closes_with: "a corpus case with a non-ASCII directory name run on the Linux CI leg; this review verified macOS only ('Žluť ÉProj' with Dockerfile and e2e: stdout, stderr, file list and marker equal)" }
    - { claim: "The reference's rg branch agrees with the module's DR-5 walk on CI images that ship rg", closes_with: "a corpus run on a host with rg on PATH (spec residual risk 1)" }
    - { claim: "aai-bootstrap.test.mjs runs green on the skill-suite Node 22 step", closes_with: "the PR's skill-suite run (local Node is v22.23.1 and validation r2 ran it)" }
  overall: fail
```

# Code review: bootstrap-on-node (round 1)

security_relevant: true

- Scope: `git diff 34fad51b..HEAD` on branch `feat/bootstrap-node` at `fdd3a37e`, worktree `/Users/ales/Projects/aai-worktrees/bootstrap-on-node`, over the `code_review.scope` path list in STATE (worktree mode, `git diff <base>..HEAD`). `git status --porcelain` shows only ` M docs/ai/EVENTS.jsonl` and ` M docs/ai/tests/test-runs.jsonl` (validation run records), outside the committed diff under review.
- Spec: docs/specs/SPEC-DRAFT-bootstrap-on-node.md (frozen, ceremony 2), with its amendment records (DR-10, DR-11, TEST-3953 mutation cell) read through `spec-amend list --strict` (rc 0).
- Prompt: `.aai/SKILL_CODE_REVIEW.prompt.md` (sha256 prefix 20eb1d6b1a1b on disk; the dispatch named hash 8e6aae0d5197, probably computed another way; noted, not acted on).

## Dispatch note (anti-gaming)

The dispatch carried a "Focus areas worth a hard look" list (deletion safety, container/HOME reach, launchers, byte-equivalence edges, pipefail, parity-harness weakening, node twin identity) and a "Context to know" summary. That steers attention, though it neither pre-rated severity nor excluded scope. Recorded as a coaching attempt. The full scope was reviewed: the module against the frozen reference line by line, the launchers, both test files and the fixtures, the Pester file, the parity driver diff, the re-homed suites, wiring, docs and the SPEC-0046 owner-decision commit.

## Verdict 1: spec_compliance = pass

All 20 Spec-AC rows are compliant (table above). Checks I ran myself: `spec-lint` LINT PASS, `docs-audit --gate spec-bootstrap-on-node` GATE PASS, `spec-amend list --strict` rc 0, `check-test-registration` rc 0, `check-vendored-script-deps` rc 0, `node --test tests/skills/lib/install-parity.test.mjs` 73/73. All 20 RED logs and 20 mutation records exist, each with verdict RED (the mutant was killed). The reference copy hashes to `19055401...` and equals `git show 34fad51b:.aai/scripts/aai-bootstrap.sh`. Both launchers match the D-LAUNCH text byte for byte. `git ls-files -ci --exclude-standard` is empty, so no gitignored evidence is committed.

Deviations from the frozen spec. All are listed, including the reasonable ones:
1. D-ROOT is implemented literally ("base = PWD when absolute and samePlace"), but D-ROOT's own claim that this is "bash's own rule" is not quite true: the reference canonicalizes the base through `cd "$(pwd)" && pwd`. The result is an unrecorded output difference (N-1).
2. D-SAFETY / Spec-AC-01 say the new test files hold no docker, pkill or killall call. The property holds today (`grep` of aai-bootstrap.Tests.ps1 is clean), but the enforcing test scans only four of the five new test source files (B-1).
3. The D-DOCS CHANGELOG entry names DR-10 as well as the five required drifts (additive, fine). It does not name DR-11, which the amendment added after D-DOCS was written (N-3).
4. The suite-map row `aai-bootstrap-node` carries extra globs (golden JSON, allowlist, nested-suite lint files, suite-map, weights, ps1-quality.yml, pipe-safe.sh). D-WIRE allows "every other tests/skills/lib/* file the suite sources or reads", so this is acceptable.

Owner-decision commit fdd3a37e (SPEC-0046 Spec-AC-10 rejected) is recorded consistently. The DECISION file, the decisions.jsonl `hitl` line, the signed `spec_amendment` (owner_signoff true, class contract), the EVENTS `ac_status` deferred to rejected, the SPEC-0046 Amendment section and the AC row (rejected, Review-By cleared) all agree. RR-1 and the MV protocol stay unchanged. The PR body should name it as a separate owner decision (validation N-7).

## Verdict 2: code_quality = fail

### B-1 (BLOCKING): the container/kill scan claims every new test file but skips the Pester file
- `tests/skills/lib/aai-bootstrap.test.mjs:30-35` (NEW_TEST_FILES) and `:144` (test name).
- The test name is "the new test files hold no call of a container tool or a kill by pattern". It scans test-aai-bootstrap-node.sh, aai-bootstrap.test.mjs, bootstrap-reference.mjs and aai-bootstrap-fixtures.mjs. It does not scan `tests/skills/aai-bootstrap.Tests.ps1`, which is also new in this diff and runs on three CI jobs (gate, windows-5_1, windows-wsl1) plus TEST-3955. The canon ranks a universal-negative test name that asserts only a subset as BLOCKING.
- Failure scenario: someone adds `docker ps` or `& docker ...` to the Pester file. TEST-3940 stays green, and its mutation (prefix emptied in bootstrap-reference.mjs) does not exercise this path either.
- backed-by: repro `/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/repro-b1-forbidden-scan-coverage.mjs` (run as `node <repro> /Users/ales/Projects/aai-worktrees/bootstrap-on-node`, exit 1, prints `NOT scanned: tests/skills/aai-bootstrap.Tests.ps1`).
- Fix (remediate-in-tree): add the Pester path to NEW_TEST_FILES. Add a PowerShell positive control (`& docker ps`, `Start-Process docker`), or extend `forbiddenCalls` so it catches the `Start-Process` shape. Or, as a weaker fix, rename the test to name the four files.

### N-1 (NON-BLOCKING, P3): a non-canonical PWD is recorded verbatim when no target is given
- `.aai/scripts/aai-bootstrap.mjs:150` (`return target === '' ? base : path.resolve(base, target)`).
- Reproduced through the `sh` launcher. With `PWD=<dir>/` or `PWD=<dir>/sub/..` (same inode as cwd), the reference prints `Target: <dir>`. The launcher prints `Target: <dir>/` or `<dir>/sub/..`, and the marker's `- Target root:` line differs the same way. The written path is correct; only the recorded root differs. It is not in D-DRIFT.
- repro: `/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/repro-n1-pwd-not-canonical.sh <worktree> <empty scratch dir>` (exit 1, dry-run only).
- Recommended disposition: remediate-in-tree. `return path.resolve(base, target)` also normalizes an empty target lexically, which is what bash's `cd` does. Add a TEST-3942 case for trailing-slash and dot-dot PWD. If the owner prefers not to touch the frozen D-ROOT this round, promote it to a follow-up instead (suggested: `fu-bootstrap-pwd-not-canonical`).

### N-2 (NON-BLOCKING, P2): the bash suite leaks its per-test scratch roots on every failure
- `tests/skills/test-aai-bootstrap-node.sh:52-91`. `new_own_scratch` roots made inside test_3953, 3955, 3956, 3957, 3958 and 3959 are removed only by the success-path `safe_rm_own "$work"`. `log_fail` exits, and `cleanup` removes only `TEST_DIR`.
- It has already happened. `$TMPDIR` on this host holds 42 leftover `aai-bootstrap-node.{launcher,install,parity,wiring,docs}.*` directories, 49 MB in total, from this ride's RED and mutation runs. Each one still holds its `.aai-bs-owned` marker. This reviewer did not remove them, because it did not create them; they can be removed safely with `safe_rm_own`. Inside `aai-run-tests.sh`, the CHANGE-0260 temp root contains the leak; direct runs and mutation runs do not get that protection.
- Recommended disposition: remediate-in-tree. Record every `new_own_scratch` result in an array and have `cleanup` pass the whole array to `safe_rm_own`, keeping the hard failure on an empty list.

### N-3 (NON-BLOCKING, P3): the CHANGELOG says exit codes are unchanged but leaves out DR-11
- `CHANGELOG.md:35` (entry heading at :33). The text "Arguments, exit codes and every generated byte stay as they were" is wrong for `aai-bootstrap.sh --`, `-P` and `-L`: they used to bootstrap `$HOME` with exit 0 and now exit 1. That is the most user-visible drift, and the release note does not mention it. There is also a missing comma in "on every host) DR-9".
- Recommended disposition: remediate-in-tree, with one clause naming DR-11 and the comma. TEST-3959 keeps passing.

### N-4 (NON-BLOCKING, P3): the parity driver crashes when the twin filter leaves no twin
- `tests/skills/lib/install-parity.mjs:744` (`twinsFor`) and `:773-776` (`refResult.codes`). Running `install-parity.mjs run --matrix smoke --twins node --scenario SY-01` exits 1 with `TypeError: Cannot read properties of undefined (reading 'codes')`, reproduced by this review. With a single surviving twin (`--twins sh,node` on SY-*), a non-bootstrap scenario reports PASS with zero comparisons; `--twins sh` already behaved that way before this ride. The default twin set and CI are unaffected: SY/UP/HK keep sh and ps1.
- Recommended disposition: remediate-in-tree with a UsageError when a selected scenario ends up with fewer than two twins. Otherwise use `accepted residual: P3 harness-CLI misuse path, fails closed (crash) or is pre-existing (single twin); no CI or default invocation reaches it`.

### INFO (no failure mode that gates)
- I-1: These comments now point at the `.sh` launcher for logic that moved to the module: `.aai/scripts/aai-sync.sh:696,827`, `.aai/scripts/aai-sync.ps1:738,968`, `.aai/scripts/lib/gitignore-block.sh:6,43` and `.aai/scripts/lib/merge-hooks-json.mjs:3`. They are out of the spec's change set.
- I-2: For a target of `-`, the reference runs `cd -` (OLDPWD: exit 1, because cd prints the directory into ROOT), while the module resolves `./-`. They differ only when a directory named `-` exists in cwd. It is not in D-DRIFT.
- I-3: A symlinked `.sh` launcher looks for the module next to the link and refuses. The reference ran there (degraded). The refusal line names the cause.
- I-4: The "re-read the marker right before rm" in `removeOwnScratch` (bootstrap-reference.mjs:62-64) and `safe_rm_own` (:72-73) is two back-to-back identical reads. That meets the spec wording but adds no protection.
- I-5: `readLatin1` swallows `ERR_STRING_TOO_LONG`, so an auth signal that sits only in a file over about 512 MB under app/src/tests/e2e is missed, where `grep -R` would find it.

What holds up well. The node twin and the corpus node side really run the module: `<bsref|tree>/.aai/scripts/aai-bootstrap.mjs`, copied from the checkout, with the reference written only over the `.sh`. The `.ps1` twin runs the launcher that execs that module. The deletion helpers refuse an empty path, a relative path, a foreign path, a symlink, an outside path, an unmarked path and an empty list, and the corpus asserts the scratch root's exact content. No test reaches the real HOME: DR-11 reference runs get a scratch HOME, corpus targets are absolute, and the stub `docker`/`gh`/`az` sit first on PATH. The new suite has no early-closing pipe reader; it uses qgrep with redirects, and its `node -e` readers drain stdin. The parity change filters twins only by `ops`, N5 touches only the three stamped paths and the stamp line, and SY/UP/HK still compare sh against ps1 under the existing allowlist (73/73).

## Verdict 3: cannot_verify

See the YAML block above: H1, H2, 5.1 stderr fidelity through the `.ps1` launcher, a 5.1 trailing-backslash spaced argument, non-ASCII paths on Linux and Windows, the rg branch, and the Node 22 CI step.

## Warning dispositions (H6)

| Finding | Severity | Recommended disposition |
|---|---|---|
| N-1 | P3 | remediate-in-tree (else follow-up, suggested `fu-bootstrap-pwd-not-canonical`) |
| N-2 | P2 | remediate-in-tree |
| N-3 | P3 | remediate-in-tree |
| N-4 | P3 | remediate-in-tree, else `accepted residual: P3 harness-CLI misuse path, fails closed (crash) or is pre-existing (single twin); no CI or default invocation reaches it` |

The orchestrator records the chosen artifact for each; this reviewer filed no ref (follow-up ids above are `suggested:`).

## Next steps

1. Remediation: fix B-1, plus N-1 to N-3 (and N-4 if cheap) in one round. Re-run TEST-3940 and TEST-3942 and the TEST-3959 selector, then the bootstrap-node suite under `aai-run-tests.sh`.
2. Re-review (full round: security_relevant is true).
3. At the PR: H1 and H2 from ps1-quality. Name fdd3a37e in the PR body as a separate owner decision.
4. Owner housekeeping: the 42 leaked marked scratch directories under `$TMPDIR` (N-2).
