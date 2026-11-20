# Code review — precommit-residual-defects (r3, confirmation)

```yaml
review:
  scope: >-
    uncommitted worktree diff vs origin/main 152cad00 (branch fix/precommit-residual-defects), same explicit
    paths as r1/r2: .aai/scripts/pre-commit-checks.sh .aai/scripts/lib/docs-audit-core.mjs
    .aai/templates/git-hooks/pre-commit-index.sh tests/skills/test-aai-pre-commit-checks.sh
    tests/skills/test-aai-docs-audit.sh tests/skills/test-aai-git-ref-guard.sh CHANGELOG.md
    docs/product/docs-close-gate.md docs/issues/ISSUE-0124-precommit-residual-defects.md
    docs/specs/SPEC-0304-spec-precommit-residual-defects.md
  spec: docs/specs/SPEC-0304-spec-precommit-residual-defects.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "docs-audit-core.mjs:2033,2036; TEST-3915 (rm, cached, keep, sub) green" }
      - { ac: Spec-AC-02, call: compliant, citation: "pre-commit-index.sh:12-17,70-75,113; TEST-3916 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "pre-commit-index.sh:139-145,162; TEST-3917 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "pre-commit-checks.sh:131-141,179-180; TEST-3918 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "pre-commit-checks.sh:383,415,464,472-496; TEST-3919 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "no <<, subshell command -v only, builtin_redir_scan empty on the script; TEST-3920 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-3921 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "CHANGELOG.md:33; docs/product/docs-close-gate.md:87; TEST-3922 green" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "GNU userland and bash 5 behaviour of the script, the hook and the node-based scan", closes_with: "the Ubuntu CI run of both suites on the PR" }
    - { claim: "the hook under Git for Windows (Git Bash)", closes_with: "a Windows Git Bash run of TEST-3916/TEST-3917; not in CI" }
    - { claim: "Linux glibc regex on a STATE.yaml holding bytes invalid in the locale (r1 INFO-1)", closes_with: "a Linux run of the r1 INFO-1 fixture" }
    - { claim: "the pipe probe fails whenever the batch pipeline could not make its pipe, for every limit between 6 and 256", closes_with: "argument from equal descriptor needs plus TEST-3885 at ulimit -n 6" }
  overall: pass
```

security_relevant: true

## Scope and spec

- Scope: as in r1 and r2. Validation r4 PASS: `docs/ai/validation/VALIDATION-precommit-residual-defects-r4.md`.
- Production code is unchanged since r2: the sha256 of `git diff -- .aai` is still 2b7732a0e4e8f42665333b284c3a14f223b1aea462095d15fc9747ce1b54ebdb. The r1 production analysis stands.
- Delta reviewed in full:
  - `builtin_redir_scan` now blanks `$(...)` and backtick spans (nested spans by repetition), strips a `case X in` prefix, and skips case-pattern words.
  - Four new planted shapes in TEST-3920.
  - The caveat line in the helper header and in the spec's TEST-3920 row.
  - The spec's residual-risk entry for the TEST-3915 sub arm.
- Dispatch note: the request asked me to "mark anything that is not a genuine blocker as NON-BLOCKING / follow-up" because the round budget is at 2/2. That is a severity steer. Under the anti-gaming contract I record it here. It changed nothing: the severities below are the ones the review contract gives.
- Safety: `docker ps` failed against the nonexistent socket before any run. Mutations ran only on copies in private `mktemp` trees.

## AC walk (Verdict 1: spec_compliance = pass)

All eight Spec-ACs are compliant. The citations are in the block above, and every selector named there was green when I ran it in this round, along with TEST-308. Spec-lint exits 0. `mutation-gate.mjs --spec` gives GATE PASS on 8 rows (degraded 0). The r1 deviations (unsigned D3/D4 amendments, tracked by `fu-amend-spec-precommit-residual-defects`) are disclosed and still need the owner's sign-off. The TEST-3920 row's measurement amendment matches the test.

## r2 B1 re-checked: closed

- The r2 repro exits 0: M1 and M2 are both caught. The r1 repro also exits 0.
- An independent probe in scratch, with the helper extracted verbatim, put 19 unplanted builtin, function and compound-command redirections into copies of the script. All 19 are caught. They include:
  - the CHECK 9 arm form `"IGNORED_ADDED "*) error "x" >&2 ;;`
  - nested `$(basename $(pwd)) >`
  - `x="$(echo hi)" ; echo "$x" >`
  - `{ ..; } >`, `done <` and `eval .. >`
- No false positives: five external-command shapes stay clean. They include `git diff > f`, `dd <&3 > f`, a `tr` in a case arm, `( command -v node ) >` and `x="$(node .. 2>&1)"`. The scan is also empty on the delivered script.
- The test's claim now states what it compares and carries one general caveat ("a lexical scan, not a parser ... TEST-3919 guards the behaviour"), as agreed in r2. No further lexical-scan gap is raised.

## Findings (Verdict 2: code_quality = pass)

No BLOCKING and no NON-BLOCKING findings.

INFO (non-gating):
- INFO-r2-1, the TEST-3915 sub arm having no mutation row of its own, is recorded in the spec's residual risks. accepted residual: P3 assurance strength only; the arm reddens on a no-`--relative` mutant (r2 scratch run), no observed bite, no false record.
- r1 INFO-1 (whole-block regex in a UTF-8 locale; masked on macOS by awk's exit 2, disclosed in the spec) and r1 INFO-3 (the hook's scratch directory on every commit; fails closed) are unchanged.

## Warning dispositions (H6)

- r1 NB1: remediated in tree (TEST-3915 sub case).
- r1 NB2: (c) follow-up `fu-hook-gate-skips-renamed-doc`, P2.
- r1 B1 / r2 B1: remediated in tree.
- No open WARNING remains.

## Commands run (this round)

| Command | Exit |
|---|---|
| `docker ps` (nonexistent socket) | 1 (expected) |
| `env -u AAI_ROLE -u AAI_GIT_WRITE /bin/bash tests/skills/test-aai-pre-commit-checks.sh test_39{18..22}_*` | 0 each |
| `env -u AAI_ROLE -u AAI_GIT_WRITE /bin/bash tests/skills/test-aai-docs-audit.sh test_3861_* test_3915_* test_3916_* test_3917_*` | 0 each |
| `env -u AAI_ROLE -u AAI_GIT_WRITE /bin/bash tests/skills/test-aai-git-ref-guard.sh test_308_installer_contract` | 0 |
| r1 repro / r2 repro | 0 / 0 (caught) |
| scratch scan probe: 19 builtin shapes / 5 external shapes | 19 caught / 0 flagged |
| `node .aai/scripts/spec-lint.mjs --path <spec>` | 0 |
| `node .aai/scripts/mutation-gate.mjs --spec <spec>` | 0 (8 rows satisfied) |

No full sweep was run in this round; validation r4 ran one (`test-20261120-020617`, rc 0).

## Next steps

The review passes. The merge path still owes:
1. The owner's sign-off on the unsigned D3/D4 amendments (`fu-amend-spec-precommit-residual-defects`).
2. Staging the review reports and repros under `docs/ai/reviews/` with the scope commit.
3. The usual `git ls-files -ci` check before pushing.
