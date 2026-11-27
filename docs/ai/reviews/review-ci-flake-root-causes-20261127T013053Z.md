# Code review round 2: ci-flake-root-causes

```yaml
review:
  scope: "f7433abf..25454d87 (remediation round 1), plus a re-check of round-1 findings 1-6 over ec9bb00b..25454d87"
  spec: docs/specs/SPEC-DRAFT-spec-ci-flake-root-causes.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "append-lock.sh:72-79 (claim and the new rmdir of an empty orphan); TEST-4165, TEST-4166, TEST-005 re-run green" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "aai-release.mjs unchanged since round 1; TEST-4164 (mocked) and the new TEST-4168 (real spawn, git shim kills itself with SIGINT/SIGTERM/SIGKILL, so node is never signalled) re-run green, 9 of 9 with TEST-3537" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "close-reconcile.mjs:364,381-382: `not` inside the label or in the same clause before it now claims nothing, matching amended D3; TEST-4160 fixture gained t4160-negated under two negated Paired labels; TEST-4160 and TEST-526 re-run green" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "release-first.test.mjs:65-77,301-315: TEST-006 runs its node and shell halves always and only the Pester half is gated; TEST-006 and TEST-4163 re-run green" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "aai-run-tests.sh:936-943 still exits 125 in the shipped layout (re-run by hand); the degraded layout fails, see finding R2-1 (code_quality, not the AC row: the row's own scenario passes)" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "unchanged since round 1; new fu-claim-span-granularity (P3) and fu-amend-spec-ci-flake-root-causes owner-sign-off follow-ups present in decisions.jsonl" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 939,
          issue: "the new `rm -f -- \"$AAI_TW_BEFORE\" \"$AAI_TW_AFTER\"` dereferences variables that are assigned only when the tripwire library is found (lines 191-192), and the script runs under `set -u` (line 119)",
          failure_scenario: "wrapper with lib/repo-tripwire.sh absent (the supported 'AAI-TRIPWIRE: NOTE - not armed' degraded path, or AAI_SELF_DIR unresolvable) and TMPDIR unusable: prints the REFUSED line, then 'line 939: AAI_TW_BEFORE: unbound variable', exits 1 instead of 125, and skips aai_tree_finish and aai_residue_finish",
          backed_by: "repro: copy .aai/scripts to a scratch dir, delete lib/repo-tripwire.sh, run `env HOME=<empty> TMPDIR=<a regular file> sh <copy>/aai-run-tests.sh sh -c 'echo RAN'` gives rc=1 with the unbound-variable line; the same command on the shipped tree gives rc=125" }
  cannot_verify:
    - { claim: "the noclobber create is O_EXCL on the hosted ubuntu-26.04 image (uutils mkdir, dash)",
        closes_with: "hosted run 45913897767 (spec Notes); locally re-verified on round 1 only (macOS sh/bash/dash/zsh/ksh)" }
    - { claim: "uutils `rm -rf` cannot delete a new holder's stamp mid-traversal (release race)",
        closes_with: "a hosted race loop; unchanged since round 1" }
    - { claim: "the hosted SIGTERM ordering race is fixed. TEST-4168 proves that the child's own signal decides; the spec now marks the hosted cause INFERRED",
        closes_with: "repeated hosted runs of TEST-3537" }
    - { claim: "gitignored RED/GREEN logs and mutation records, including the re-anchored TEST-4166 cell and the new TEST-4168 cell",
        closes_with: "`mutation-gate.mjs --spec docs/specs/SPEC-DRAFT-spec-ci-flake-root-causes.md --require-evidence` in the ride worktree" }
    - { claim: "TEST-4161 (owned and inherited mode), from the whole aai-run-tests suite",
        closes_with: "the validator's whole-suite run (reported exit 0); no single-test selector exists, so the reviewer ran the inherited case by hand only" }
    - { claim: "TEST-006 and TEST-4163 on a host where Pester is importable under an empty HOME (CI's pass branch)",
        closes_with: "the PR's hosted skill-suite run" }
  overall: fail
```

security_relevant: false

## Scope

- Delta: `git diff f7433abf..25454d87`, 13 files. All of it was read, including the spec amendment rows, the decisions.jsonl and EVENTS.jsonl additions, and the round-1 report moved into the branch.
- Re-check: each round-1 finding below was checked against the new head.
- Dispatch note: the request named the dispositions the orchestrator had taken. It did not pre-rate anything new, and the full delta was reviewed.
- Clone state: `git status --porcelain` is clean apart from this report.

## Verification run by the reviewer (targeted only)

| Check | Result |
|---|---|
| close-reconcile `test_4160_claim_not_mention` | rc 0 |
| close-reconcile `test_526_replays_the_two_real_ranges` | rc 0 |
| sweep-parallel `test_4165`, `test_4166`, `test_005` | rc 0, 0, 0 |
| `node --test` aai-release TEST-3537, TEST-4164, TEST-4168 | 9 pass, 0 fail |
| `node --test` release-first TEST-006 (PR workflow), TEST-4163 | 2 pass, 0 fail |
| aai-run-tests.sh with TMPDIR set to a file, shipped tree | rc 125 |
| the same with lib/repo-tripwire.sh removed (scratch copy) | rc 1, `AAI_TW_BEFORE: unbound variable` (R2-1) |
| claimSpans harness (scratch copy of the new function) | negated labels give no span; the real CHANGE-0173 and CHANGE-0174 shapes still claim; `(notes)` still claims; the 340 KB pathological line now takes 1 ms (was 8.5 s) |
| corpus grep for a Paired label with `not` in it or before it | none (the one hit is a filename) |

## Round-1 findings re-check

| # | Round 1 | Status at 25454d87 |
|---|---|---|
| 1 | Paired-label negation narrower than D3 (Spec-AC-03) | FIXED. close-reconcile.mjs:381-382; D3 amended to state the 40-character same-clause window; TEST-4160 fixture covers both shapes. Spec-AC-03 is now compliant. |
| 2 | Stampless orphan lock after a failed create | FIXED for the error path. append-lock.sh:77 `rmdir` removes only an empty dir; checked against the racing cases (another process's claim file is present, or a released dir is reclaimed: rmdir either fails or makes the reclaimer retry). A kill between mkdir and the create (a pre-existing window) still leaves an unbreakable empty dir. INFO, not a regression. |
| 3 | 125 refusal path skipped iso and tripwire cleanup | FIXED, but the fix introduces R2-1 (BLOCKING). |
| 4 | TEST-4165 leaked $d.o1/$d.o2 and hid their output | FIXED. The files now live in the registered `$d.shim/`, and are printed on failure. |
| 5 | claimSpans granularity (nested value, item over-reach, fences) | Promoted to fu-claim-span-granularity (P3) in decisions.jsonl. Accepted. |
| 6 | Quadratic PAIRED_LABEL_RE | FIXED. The word group is bounded to `{0,6}`; measured 1 ms on the round-1 input. The corpus's longest label has one word, so no real label is lost. |

## Findings (round 2)

R2-1. BLOCKING, .aai/scripts/aai-run-tests.sh:939. Introduced by the fix for round-1 finding 3; failure scenario and repro are in the YAML above. Fix: `rm -f -- "${AAI_TW_BEFORE:-}" "${AAI_TW_AFTER:-}" 2>/dev/null`, or initialise `AAI_TW_BEFORE=''` and `AAI_TW_AFTER=''` next to `AAI_TW_ARMED=0` at line 181. Optionally add a TEST-4161 arm that runs a wrapper copy without lib/repo-tripwire.sh and asserts rc 125. Disposition: remediate in tree.

INFO (never gates):
- tests/skills/test-aai-close-reconcile.sh:1426. TEST-4160's log_pass still says "none of the three mentioned ones". There are now four.
- The spec's Test Plan row for TEST-4160 says "six untouched draft docs"; the fixture now seeds seven.
- The TEST-4163 mutation cell (`if(!pesterOr(t))return;` removal) now matches only TEST-004, because TEST-006 calls `pesterOr(t);` without that guard. TEST-4163 still kills it through TEST-004, and its skip count of 2 also guards TEST-006's call.
- close-reconcile.mjs:382. `not only X but also the paired maintenance half:` within 40 characters is read as negated, a false negative. No such shape exists in the corpus; this falls under fu-claim-span-granularity.

## Warning dispositions

No NON-BLOCKING findings this round. Round-1 dispositions are recorded above. R2-1 must be remediated.

## Next steps

1. Fix R2-1 (one line) and re-run TEST-4161, plus the degraded-layout repro.
2. A round-3 review is needed only for that hunk.

state_update_commands:
```bash
node .aai/scripts/state.mjs set-code-review --required true --status fail \
  --scope "f7433abf..25454d87" --base-ref f7433abf \
  --report docs/ai/reviews/review-ci-flake-root-causes-20261127T013053Z.md \
  --notes "round 2: spec_compliance pass (Spec-AC-03 fixed); code_quality fail on BLOCKING R2-1 aai-run-tests.sh:939 unbound AAI_TW_BEFORE under set -u when the tripwire lib is absent (rc 1, not 125, finishers skipped); round-1 1,2,3,4,6 fixed in tree, 5 = fu-claim-span-granularity (P3)"
```
