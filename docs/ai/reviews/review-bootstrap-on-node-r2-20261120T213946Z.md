```yaml
review:
  scope: "git diff 34fad51b..1a3288c5 (branch feat/bootstrap-node) over the STATE code_review.scope path list; remediation delta fdd3a37e..8566186b; 631510a8 and 1a3288c5 telemetry only"
  spec: docs/specs/SPEC-0306-spec-bootstrap-on-node.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/lib/aai-bootstrap.test.mjs:30-36 (Pester file now scanned), :176 completeness case; bootstrap-reference.mjs:48-72; test-aai-bootstrap-node.sh:59-98; TEST-3940 rerun 17/17 with TEST-3942" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:11-33,795; TEST-3941 (unchanged since r1)" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:142-151 (base = path.resolve(pwd) at :148); TEST-3942 incl. new non-canonical PWD case :468; rerun pass" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:167-328; TEST-3943" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:244-400; TEST-3944" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:402-492; TEST-3945" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:497-605; TEST-3946" }
      - { ac: Spec-AC-08, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:607-639,765-771; TEST-3947" }
      - { ac: Spec-AC-09, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:643-675; TEST-3948" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-3949 masked corpus (validation r3 full sweep)" }
      - { ac: Spec-AC-11, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:698-726; TEST-3950" }
      - { ac: Spec-AC-12, call: compliant, citation: ".aai/scripts/aai-bootstrap.mjs:729-734; TEST-3951" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-3952 full corpus" }
      - { ac: Spec-AC-14, call: compliant, citation: ".aai/scripts/aai-bootstrap.sh:1-9 (D-LAUNCH, unchanged); TEST-3953" }
      - { ac: Spec-AC-15, call: compliant, citation: "re-homed suites unchanged since r1; TEST-3954" }
      - { ac: Spec-AC-16, call: compliant, citation: ".aai/scripts/aai-bootstrap.ps1:1-9; aai-bootstrap.Tests.ps1; TEST-3955 under pwsh 7 (5.1 is hosted H1)" }
      - { ac: Spec-AC-17, call: compliant, citation: "tests/skills/lib/install-parity.mjs TWINS.node, twinsFor, N5, BS-01..09, new <2-twin refusal :872-876; TEST-3956; install-parity.test.mjs refusal cases and TEST-3566b rerun 10/10 (Windows is hosted H2)" }
      - { ac: Spec-AC-18, call: compliant, citation: "tests/skills/test-aai-bootstrap-node.sh test_3957; TEST-3957" }
      - { ac: Spec-AC-19, call: compliant, citation: "wiring unchanged since r1; TEST-3958" }
      - { ac: Spec-AC-20, call: compliant, citation: "CHANGELOG.md:33-35 (now names DR-11, comma fixed); TEST-3959" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Pester aai-bootstrap.Tests.ps1 passes under Windows PowerShell 5.1 and pwsh 7 on native Windows (H1)", closes_with: "the PR's ps1-quality windows-5_1 and windows-wsl1 runs" }
    - { claim: "BS scenarios agree on native Windows with only win-bootstrap-target-root covering a divergence (H2)", closes_with: "the PR's windows-parity job report" }
    - { claim: "Module stderr passes through aai-bootstrap.ps1 byte for byte under Windows PowerShell 5.1 when the caller captures stderr", closes_with: "a 5.1 Pester case on a conflict fixture asserting the three exact stderr lines" }
    - { claim: "A target ending in a backslash and containing a space reaches the module intact through aai-bootstrap.ps1 under 5.1", closes_with: "a 5.1 Pester pass-through case with that argument" }
    - { claim: "Non-ASCII target paths are byte-equal between reference and module on Linux and Windows", closes_with: "a corpus case with a non-ASCII directory name on the Linux CI leg (r1 verified macOS only)" }
    - { claim: "The reference's rg branch agrees with the module's DR-5 walk on hosts with rg", closes_with: "a corpus run with rg on PATH" }
    - { claim: "aai-bootstrap.test.mjs runs green on the skill-suite Node 22 step", closes_with: "the PR's skill-suite run" }
  overall: pass
```

# Code review: bootstrap-on-node (round 2)

security_relevant: true

- Scope: `git diff 34fad51b..HEAD` at `1a3288c5`, worktree `/Users/ales/Projects/aai-worktrees/bootstrap-on-node` on branch `feat/bootstrap-node`, over the `code_review.scope` list. This is the full re-review the canon requires, because round 1 was marked security_relevant.
  - The delta since round 1 is commit `8566186b` (remediation).
  - `631510a8` and `1a3288c5` are telemetry only. `git diff 8566186b..HEAD --numstat` shows 6+0 lines in `docs/ai/EVENTS.jsonl` and 1+0 in `docs/ai/tests/test-runs.jsonl`, with zero removed lines (append-only). Neither commit touches INDEX.md.
  - `git status` shows one uncommitted append to `docs/ai/EVENTS.jsonl`, outside the diff under review.
- Spec: docs/specs/SPEC-0306-spec-bootstrap-on-node.md, unchanged since round 1.
- Previous round: docs/ai/reviews/review-bootstrap-on-node-20261120T204528Z.md (FAIL on B-1). It is now committed in 8566186b, which satisfies report staging.
- Dispatch: names prompt hash 8e6aae0d5197 again (the file on disk hashes to sha256 20eb1d6b1a1b...; noted only). The dispatch did not pre-rate or exclude anything. It asked me to verify each fix by running it, and I did.

## Round 1 findings, verified against the diff and by running them

- B-1: fixed.
  - `NEW_TEST_FILES` now holds `tests/skills/aai-bootstrap.Tests.ps1` (aai-bootstrap.test.mjs:32).
  - `forbiddenCalls` gained PowerShell shapes and has positive and negative controls: the call operator, `.exe`, `Start-Process`, `Stop-Process -Name`, `Get-Process | Stop-Process` and `taskkill /IM`.
  - A completeness case (:176) fails when a bootstrap-named test file under tests/skills or its lib is missing from the list.
  - My r1 repro `repro-b1-forbidden-scan-coverage.mjs` now exits 0 ("every added test file is scanned").
  - `node --test --test-name-pattern 'TEST-394[02]'` gives 17/17.
- N-1: fixed.
  - `base = path.resolve(pwd)` (aai-bootstrap.mjs:148).
  - My r1 repro now gives identical `Target:` lines from the reference and the `sh` launcher for both `<dir>/` and `<dir>/sub/..`. I also probed `<dir>/.`, which matches.
  - The new TEST-3942 case (:468) compares six PWD shapes (trailing slash, dot-dot, `/./`, `//`, symlink, symlink with slash) against the reference.
- N-2: fixed.
  - `cleanup` (test-aai-bootstrap-node.sh:87-98) now also sweeps every `$TMPDIR/aai-bootstrap-node.*` directory whose marker equals `$$`, through `safe_rm_own`.
  - I checked this in an isolated harness: the suite's own function definitions, a scratch `TMPDIR` under my session scratchpad, and a simulated `log_fail` failure. Both own per-test scratch roots were removed. A foreign-pid marked directory and an unmarked own-prefix directory survived. A `( exit 0 )` subshell did not trigger the sweep, and the exit code stayed 1.
  - The 42 directories left by earlier runs in the real `$TMPDIR` are untouched (still 42), as intended, because they carry other pids.
- N-3: fixed. The CHANGELOG body now reads "stay as they were (one exception, DR-11 below)" and names DR-11 with its exit-code change. The comma before DR-9 is in place.
- N-4: fixed.
  - `dispatch` refuses with a UsageError (exit 2) any selected scenario that fewer than two twins run (install-parity.mjs:872-876).
  - Two new node:test cases cover `--twins node` and `--twins sh` on SY-01, and TEST-3566b now uses two hanging twins. That rerun gives 10/10.
  - Existing callers keep at least two twins:
    - the default twins;
    - `--twins sh,ps1` with or without a module twin;
    - test-aai-install-parity.sh:287 (`--twins sh` plus `rec`);
    - TEST-3956's skew run (`sh` plus `skew`).
  - install-parity.Tests.ps1 uses the default twins.

## Verdict 1: spec_compliance = pass

All 20 Spec-AC rows are compliant (table above). `docs-audit --gate spec-bootstrap-on-node` gives GATE PASS, and `git ls-files -ci --exclude-standard` is empty.

Deviation note: D-ROOT says the base is "the environment's PWD". The module now normalizes that PWD lexically. This realizes D-ROOT's stated intent ("the module reports the logical path where bash does"). It changes no promise, so I see no amendment owed.

## Verdict 2: code_quality = pass

No BLOCKING or NON-BLOCKING findings. INFO notes, none of which gates:
- I-1 to I-5 from round 1 stand as written: stale `.sh` mentions in shared-code comments, the `-` target, a symlinked launcher, the back-to-back marker re-read, and files over 512 MB in the auth search.
- I-6: a PWD with a leading `//` keeps the double slash in the reference (bash keeps POSIX `//`) but becomes `/` in the module. Probed: `Target: //…` against `Target: /…`. A parent would have to export such a PWD on purpose.
- I-7: the failure sweep keys on `$$`. If a pid is reused, a leftover from an earlier run of this same suite with that pid would also be removed. It is still a marked directory this suite created, validated again by `safe_rm_own`.
- I-8: the remediation stored no new RED logs under docs/ai/tdd. The new cases would fail at fdd3a37e:
  - the completeness case, because the Pester file was missing from the list;
  - the non-canonical PWD case, which my r1 repro reproduced against fdd3a37e;
  - the refusal cases, because fdd3a37e exits 1 with a TypeError instead of 2.
  The r1 repro outputs stand as that RED evidence. N-2 has no automated case; the harness above is the evidence.

## Verdict 3: cannot_verify

Unchanged from round 1 (YAML above): H1, H2, 5.1 stderr fidelity through the `.ps1`, a 5.1 trailing-backslash spaced argument, non-ASCII paths on Linux and Windows, the rg branch, and the Node 22 CI step. None blocks; H1 and H2 close at the PR.

## Warning dispositions (H6)

Round 1's N-1, N-2, N-3 and N-4 were all remediated in-tree (disposition (a)) in 8566186b. This round has no open WARNING.

## Next steps

1. PR: name fdd3a37e in the body as a separate owner decision. Record H1 and H2 from ps1-quality.
2. Owner housekeeping, optional: the 42 marked `aai-bootstrap-node.*` leftovers from earlier runs under `$TMPDIR`. A future run will not remove them, because their pids differ.
