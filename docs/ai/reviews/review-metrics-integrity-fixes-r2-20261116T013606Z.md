# Code Review — metrics-integrity-fixes (round 2)

```yaml
review:
  scope: "git diff 28fbdda8..HEAD (HEAD 3cbd5ee9, branch fix/metrics-integrity-fixes, worktree /Users/ales/Projects/aai-worktrees/metrics-integrity-fixes); paths: .aai/scripts/lib/metrics-flush-record.mjs; .aai/scripts/validation-outcome-check.mjs; tests/skills/test-aai-merge-cleanup.sh; tests/skills/test-aai-outcome-backcheck.sh; tests/skills/test-aai-role-output.sh; docs/product/telemetry.md; CHANGELOG.md; docs/issues/ISSUE-0118-metrics-integrity-fixes.md; docs/specs/SPEC-0295-spec-metrics-integrity-fixes.md"
  spec: docs/specs/SPEC-0295-spec-metrics-integrity-fixes.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/test-aai-merge-cleanup.sh TEST-026 second half (fixture repo F, L1/L2 via real spec-amend add/classify); TEST-026 rc 0 this review" }
      - { ac: Spec-AC-02, call: compliant, citation: "test_3771_test_026_is_hermetic; TEST-3771 rc 0 this review" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/lib/metrics-flush-record.mjs:191-208 readBaseLedger (A1 two-read classification); TEST-3772 rc 0 (removed blob, garbage/missing/tree ref shapes keep; noref/nofile recover 1)" }
      - { ac: Spec-AC-04, call: compliant, citation: "metrics-flush-record.mjs:175 inner try around writeFileSync, :181 finally swallows rmSync; TEST-3773 rc 0" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-3774 rc 0 (plan exit 0, digest equal, keep (ledger_runs_unchecked held ledger temp write failed ()" }
      - { ac: Spec-AC-06, call: compliant, citation: "validation-outcome-check.mjs:391,407,418; TEST-3775 in test-aai-outcome-backcheck.sh, suite rc 0" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-3776 in test-aai-role-output.sh, suite rc 0 and TEST-3776 selector rc 0" }
      - { ac: Spec-AC-08, call: compliant, citation: "CHANGELOG.md:33 heading (one); docs/product/telemetry.md:219; TEST-3777 rc 0" }
    deviations:
      - "D2 step 1 tightened by post-freeze amendment A1 (class contract, owner_signoff false, tracked by fu-amend-spec-metrics-integrity-fixes); code follows A1, not the frozen D2 step 1 text. Disclosed additive amendment, recorded in decisions.jsonl; owner sign-off still owed."
      - "Closure section relabelled by amendment A2 (class measurement, owner_signoff false); frozen_sha256 re-pinned; spec-amend list --strict rc 0, verify-closures 5/5 OK."
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Linux/CI git gives the same rev-parse rc and stderr for the garbage, missing-object and tree ref shapes TEST-3772 builds (probed on macOS git only)", closes_with: "a green CI run of test-aai-merge-cleanup.sh TEST-3772 on the ubuntu image at this head" }
    - { claim: "ENOBUFS / spawn-error branches of readBaseLedger and merge-cleanup apply over an unreadable base (spec R3, R4)", closes_with: "fixtures forcing maxBuffer overflow or a missing git binary, plus an apply-mode case" }
  overall: pass
```

security_relevant: false

## Scope and spec

- Scope: `git diff 28fbdda8..HEAD` on branch `fix/metrics-integrity-fixes` (commits 124cb6ba, 3cbd5ee9), worktree mode (STATE `worktree.user_decision: worktree`). `git status --porcelain`: only `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl` (telemetry appends, outside the reviewed paths). EVENTS.jsonl and decisions.jsonl: the base blob at 28fbdda8 is a byte-exact prefix of the head file.
- Spec: docs/specs/SPEC-0295-spec-metrics-integrity-fixes.md (ceremony 2, tdd) with amendments A1 (contract) and A2 (measurement).
- Dispatch note: the dispatch named the round-1 findings (CR-1, CR-2, CR-3) to verify and the amendments. That is a re-review input, not a characterization of new findings; the full scope was reviewed regardless.

## Round-1 findings — resolution

| Id | Round 1 | Now | Evidence |
|---|---|---|---|
| CR-1 (BLOCKING) | rev-parse exit 1 read as absent without the stderr condition | resolved | `metrics-flush-record.mjs:197-199`: `has` (no peel) exit 1 is absent only with empty stderr; other non-zero or stderr is `bad`. Round-1 repro `scratchpad/cr-repro/repro-broken-base-ref.sh` now exits 0 (garbage: `base ledger unreadable (git rev-parse exit 1)`; tree: `(git rev-parse commit exit 1)`). Mutation M1 (restore "any exit 1 is absent") in a scratch copy: TEST-3772 rc 1, `recovered:1`. |
| CR-2 (NB) | a ref to a missing object is silent | resolved in tree via A1 | `metrics-flush-record.mjs:200-201` commit peel after the ref resolves; TEST-3772 `missing` shape (deadbeef…). Mutation M2 (drop the peel check) in a scratch copy: TEST-3772 rc 1. |
| CR-3 (NB) | role-output selector refused TEST-id | resolved | `test-aai-role-output.sh` main maps `TEST-3776` to its function; `aai-run-tests.sh … test-aai-role-output.sh TEST-3776` rc 0. |

## Verdict 1 — spec_compliance: PASS

All eight Spec-AC rows compliant (table above, each test re-run green in this review). TEST-xxx rows: all eight exist, are registered in their suites' default run and selector, and `mutation-gate.mjs --spec …` reports `GATE PASS: 8 row(s) satisfied degraded=0`. `spec-lint --path` LINT PASS. `spec-amend list --strict` rc 0. `follow-ups verify-closures --json`: the five claims of this spec are all `OK` (resolved_by metrics-integrity-fixes), and `fu-assertions-pinned-to-one-world` is no longer read as a claim (A2 works). Deviations listed above are disclosed amendments; A1/A2 carry `owner_signoff: false` and the open tracker `fu-amend-spec-metrics-integrity-fixes`.

## Verdict 2 — code_quality: PASS

No BLOCKING and no NON-BLOCKING findings.

Checked, no finding:
- readBaseLedger: `has.status === null` (signal) and spawn errors go to `bad`; the second `status === 1` branch is reached only with empty stderr. Order matches A1 (verify, peel, ls-tree, show).
- Any unrelated git warning on stderr for a genuinely missing ref makes the step kept rather than run: the conservative direction (no write, fallback command printed), consistent with A1. INFO only.
- D3 temp write: `tmp` set only when bytes exist, pushed to `held` only after a successful write, `finally` swallows its own rmSync error.
- keepText/fallbackOf hoisted with byte-identical keep text (TEST-3756/3761 unaffected; full sweep green).
- validation-outcome-check.mjs: no `.aai/STATE.yaml` path remains (TEST-3775 source grep).
- merge-cleanup.mjs untouched, 1490 lines (TEST-058 ceiling).
- New fixture git commits run under the suite's exported GIT_AUTHOR/COMMITTER identity and GIT_CONFIG_GLOBAL=/dev/null; new `cd` sites are in subshells with absolute checked paths; `check-cd-subshell-leak.mjs` rc 0; no `printf | grep -q` or bare `rc=$?` under `set -e` in added lines.
- Test names claim what they assert (TEST-3772 "keeps the step and writes nothing" is asserted by METRICS sha equality per shape).

INFO (not gating): spec residuals R1 (`fu-merged-unsigned-live-audit`) and R2 (`fu-merge-cleanup-mkdtemp-unguarded`, apply still throws one step later with an unwritable TMPDIR) are named as suggested follow-ups and are not in the ledger. They are pre-existing gaps the spec discloses, not defects of this diff; the orchestrator may file them so they are not lost.

## cannot_verify

1. Linux/CI git rc and stderr for the three broken-ref shapes (TEST-3772 probed on macOS git) — closes with green CI on the ubuntu image at this head.
2. ENOBUFS / spawn-error branches and an `apply` over an unreadable base (spec R3/R4) — closes with dedicated fixtures.

The round-1 item "full sweep green" is closed: run test-20261116-011403 at 3cbd5ee9, 135 pass / 0 fail / 1 skipped (docs/ai/tests/test-runs.jsonl, EVENTS full_sweep rc 0).

## Evidence (this review)

| Command | Exit |
|---|---|
| `aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh` TEST-3772 / 3773 / 3774 / 3777 / 026 / 3771 | 0 each |
| `aai-run-tests.sh bash tests/skills/test-aai-outcome-backcheck.sh` | 0 |
| `aai-run-tests.sh bash tests/skills/test-aai-role-output.sh` and `… TEST-3776` | 0, 0 |
| `bash scratchpad/cr-repro/repro-broken-base-ref.sh <worktree>` (round-1 CR-1 repro) | 0 (both shapes kept) |
| mutation M1 (exit 1 always absent) / M2 (no commit peel), scratch copy, TEST-3772 | 1 / 1 (bite) |
| `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0295-spec-metrics-integrity-fixes.md` | 0 |
| `node .aai/scripts/spec-lint.mjs --path <spec>` | 0 (LINT PASS) |
| `node .aai/scripts/spec-amend.mjs list --strict` | 0 |
| `node .aai/scripts/follow-ups.mjs verify-closures --json` | 0 (5/5 OK for this spec) |
| `node .aai/scripts/check-cd-subshell-leak.mjs` | 0 |

## Warning dispositions (H6)

No open WARNINGs this round. Round-1 CR-2 and CR-3 were remediated in tree (disposition (a)).

## Next steps

1. Owner sign-off on amendments A1/A2 remains owed (tracker `fu-amend-spec-metrics-integrity-fixes`).
2. Open the PR and confirm CI green on ubuntu (cannot_verify 1).
3. Optionally file R1/R2 residual follow-ups.
