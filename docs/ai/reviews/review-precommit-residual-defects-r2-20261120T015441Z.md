# Code review — precommit-residual-defects (r2)

```yaml
review:
  scope: >-
    uncommitted worktree diff vs origin/main 152cad00 (branch fix/precommit-residual-defects), same explicit
    paths as r1: .aai/scripts/pre-commit-checks.sh .aai/scripts/lib/docs-audit-core.mjs
    .aai/templates/git-hooks/pre-commit-index.sh tests/skills/test-aai-pre-commit-checks.sh
    tests/skills/test-aai-docs-audit.sh tests/skills/test-aai-git-ref-guard.sh CHANGELOG.md
    docs/product/docs-close-gate.md docs/issues/ISSUE-0124-precommit-residual-defects.md
    docs/specs/SPEC-0304-spec-precommit-residual-defects.md
  spec: docs/specs/SPEC-0304-spec-precommit-residual-defects.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "docs-audit-core.mjs:2033,2036; TEST-3915 (now 4 cases incl. project root below repo top) green; scratch no---relative mutant fails it" }
      - { ac: Spec-AC-02, call: compliant, citation: "pre-commit-index.sh:12-17,70-75,113; TEST-3916 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "pre-commit-index.sh:139-145,162; TEST-3917 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "pre-commit-checks.sh:131-141,179-180; TEST-3918 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "pre-commit-checks.sh:383,415,464,472-496; TEST-3919 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "no << and subshell command -v only; TEST-3920 green (see B1 on the broader claim of its scan)" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-3921 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "CHANGELOG.md:33; docs/product/docs-close-gate.md:87; TEST-3922 green" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-pre-commit-checks.sh, line: 1168,
          issue: "r1 B1 is only partly closed: TEST-3920 and its builtin_redir_scan now claim 'no redirection on a builtin, a function or a compound command', but the lexical scan misses a command in a case arm on the pattern's line and a builtin redirected after an unquoted command substitution",
          failure_scenario: "M1: '*) staged_read_fail \"malformed staged list\" >&2 ;;' in the parse's case; M2: 'echo $(date) >/dev/null' before CHECK 9: TEST-3920 passes on each mutant (repro docs/ai/reviews/review-precommit-residual-defects-r2-20261120T015441Z-repro-B1.sh exits 1, .out sibling)" }
  cannot_verify:
    - { claim: "GNU userland and bash 5 behaviour of the script, the hook and the new node-based scan", closes_with: "the Ubuntu CI run of both suites on the PR" }
    - { claim: "the hook under Git for Windows (Git Bash)", closes_with: "a Windows Git Bash run of TEST-3916/TEST-3917; not in CI" }
    - { claim: "Linux glibc regex on a STATE.yaml holding bytes invalid in the locale (r1 INFO-1)", closes_with: "a Linux run of the r1 INFO-1 fixture" }
    - { claim: "the pipe probe fails whenever the batch pipeline could not make its pipe, for every limit between 6 and 256", closes_with: "argument from equal descriptor needs plus TEST-3885 at ulimit -n 6" }
  overall: fail
```

security_relevant: true

## Scope and spec

- Scope: as in r1 (`docs/ai/reviews/review-precommit-residual-defects-20261120T011041Z.md`): the uncommitted worktree diff vs origin/main 152cad00 on the ten explicit paths. Validation r3 PASS: `docs/ai/validation/VALIDATION-precommit-residual-defects-r3.md`.
- Production code: `git diff --stat` for `.aai/` is unchanged from r1 (9, 87 and 40 lines), consistent with the orchestrator's "production blobs unchanged". The r1 production analysis (re-read loop, pipe probe, `-z` hook loops and filters, deleted-path skip, `pcc_next_line`) stands. Fingerprint of the current `git diff -- .aai` is sha256 2b7732a0e4e8f42665333b284c3a14f223b1aea462095d15fc9747ce1b54ebdb.
- Delta reviewed in full: TEST-3920 plus the new `builtin_redir_scan` helper, the new `sub` case of TEST-3915, the spec's Test Plan rows for TEST-3915 and TEST-3920, and the new `fu-hook-gate-skips-renamed-doc` ledger record.
- Dispatch: it listed what changed since r1. It did not pre-rate severity or exclude any area.
- Safety: `docker ps` failed against the nonexistent socket before any run. Mutations ran only on copies in private `mktemp` trees.

## AC walk (Verdict 1: spec_compliance = pass)

Every Spec-AC is compliant. The citations are in the block above, and every selector named there was green when I ran it in this round. Spec-lint exits 0. `mutation-gate.mjs --spec` gives GATE PASS on 8 rows (degraded 0). The Test Plan rows for TEST-3915 and TEST-3920 are amended in line with the new tests; the amendment is measurement-class and recorded in the ledger. The r1 deviations (unsigned D3/D4 amendments tracked by `fu-amend-spec-precommit-residual-defects`) are still open and still need the owner's sign-off.

## r1 findings re-checked

| r1 | Status | Evidence |
|---|---|---|
| B1 (TEST-3920 overclaims) | partly closed, see r2 B1 | The r1 repro now exits 0 ("TEST-3920 caught the builtin redirection"). The scan catches the ten planted shapes plus `echo` + backtick, `[ ] 2>`, `read <`, `printf >&2`, an assignment prefix, `{ ..; } >`, `done <`, `if ..; then .. >`, `eval .. >`, `x=1; echo >`, and quoted `;` and escaped spaces. It misses M1 and M2 (below). |
| NB1 (`--relative` unpinned) | closed | TEST-3915 `sub` case. A scratch copy with `--relative` removed fails TEST-3915: `FAIL: ... (git rm) must not pass the gate (got 0)`. Only the `sub` case can fail on that mutant, because at the top level the flag has no effect. |
| NB2 (hook skips renamed doc, pre-existing) | dispositioned (c) | `fu-hook-gate-skips-renamed-doc` P2 is in `docs/ai/decisions.jsonl` and shows as open in `follow-ups.mjs list --status open`. |
| INFO-2 (hook comment) | accepted | The orchestrator's reasoning holds: the comment is true for a doc the commit does not delete, and editing it would move the TEST-308 pin. |

## Findings (Verdict 2: code_quality = fail)

### B1 — BLOCKING — `tests/skills/test-aai-pre-commit-checks.sh:1168` (`builtin_redir_scan`) and `:1200` (TEST-3920)

Four places now claim the script "holds no redirection on a builtin, a function or a compound command (only the two exec opens)": the test's name, its `log_pass`, the helper's header and the spec row. The scan proves this only for the shapes it was planted with. Two shapes outside that set escape it:

- **M1, a case arm on the pattern's line.** The segment's first word is the pattern (`*)`, `D|U)`), so the command after it is never judged. This one-line `pat) cmd ;;` form is the script's own commonest idiom; the parse, CHECK 2, CHECK 4 and CHECK 9 all use it. Probe: `D|U) warn "x" >&2 ;;` and `case "$x" in *) echo x > f ;; esac` are both missed.
- **M2, an unquoted command substitution before the redirection.** The split at `$(` leaves `date) >/dev/null`, and the subshell rule (`/\)\s*[0-9]?(>>?|<)/`) then skips it. So `echo $(date) >/dev/null`, a builtin redirected by bash in the script's own process, is missed.

backed-by: repro `docs/ai/reviews/review-precommit-residual-defects-r2-20261120T015441Z-repro-B1.sh`, which exits 1. Its output is in the `.out` sibling. It runs the real TEST-3920 selector against two mutated copies in a private mktemp tree:
- M1 changes the parse's `case "$meta" in :*) ;; *) staged_read_fail "malformed staged list" >&2 ;; esac`.
- M2 inserts `echo $(date) >/dev/null` before CHECK 9.

TEST-3920 passes on both mutants.

Behaviour on the paths TEST-3919 reaches remains guarded: the r1 run showed that TEST-3919 fails on a builtin redirection before CHECK 9. The defect is that the static pin claims more than it proves. That is the rule's universal-negative shape, and the same finding r1 B1 raised.

Bounded remedy, so that this does not turn into another round:
1. In the scan, replace each `$(...)` and backtick span with `Q` before splitting, the same way quoted text is treated, and drop a leading case pattern (`^\s*[^()\s]+\)\s*` and `;; *pat)`) from a segment before taking its first word.
2. Plant M1 and M2 in the probe list.
3. Add ONE general caveat to the helper header and the spec row, for example: "a lexical scan, not a parser: a shape outside the planted set can escape it; TEST-3919 guards the behaviour".

With that caveat stated, the claim matches what the test compares. A re-review should not raise further lexical-scan gaps as BLOCKING.

### INFO (non-gating)

- INFO-r2-1: the new `sub` arm of TEST-3915 has no row of its own in the spec's mutation column. The column still names the `deleted.has` removal. The mutation replay therefore re-proves the main arm only. If the `sub` case is later deleted, nothing reddens, apart from this review's one-off scratch run. P3; if not remediated, it can be recorded as `accepted residual`.
- r1 INFO-1 and INFO-3 are unchanged and still non-gating.

## Commands run (this round)

| Command | Exit |
|---|---|
| `docker ps` (nonexistent socket) | 1 (expected) |
| `env -u AAI_ROLE -u AAI_GIT_WRITE /bin/bash tests/skills/test-aai-pre-commit-checks.sh test_39{18..22}_*` | 0 each |
| `env -u AAI_ROLE -u AAI_GIT_WRITE /bin/bash tests/skills/test-aai-docs-audit.sh test_3861_* test_3915_* test_3916_* test_3917_*` | 0 each |
| `env -u AAI_ROLE -u AAI_GIT_WRITE /bin/bash tests/skills/test-aai-git-ref-guard.sh test_308_installer_contract` | 0 |
| r1 repro `review-precommit-residual-defects-20261120T011041Z-repro-B1.sh` | 0 (caught) |
| TEST-3915 on a scratch copy without `--relative` | 1 (sub case reddens) |
| `builtin_redir_scan` on 16 unplanted shapes (scratch) | 14 caught, 3 missed (two case-arm forms, one `$(..)` form) |
| r2 repro `review-precommit-residual-defects-r2-20261120T015441Z-repro-B1.sh` | 1 (gap reproduced) |
| `node .aai/scripts/spec-lint.mjs --path <spec>` | 0 |
| `node .aai/scripts/mutation-gate.mjs --spec <spec>` | 0 (8 rows satisfied) |

No full sweep was run; validation r3 ran one (`test-20261120-013014`, rc 0).

## Warning dispositions (H6)

- r1 NB1: remediated in tree (TEST-3915 `sub` case).
- r1 NB2: (c) follow-up `fu-hook-gate-skips-renamed-doc`, P2, filed by the orchestrator.
- INFO items do not gate.

## Next steps

1. Apply the bounded remedy for B1: two scan fixes, two planted shapes, one caveat line. Then re-run TEST-3920 and the mutation replay.
2. Re-review only that delta.
