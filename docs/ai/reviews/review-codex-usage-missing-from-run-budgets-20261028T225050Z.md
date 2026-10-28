```yaml
review:
  scope: "git show 4cdedc4f (on top of 6774766c), PR #512 B-1 remediation round"
  spec: docs/specs/SPEC-0258-spec-codex-usage-missing-from-run-budgets.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "untouched by delta; TEST-3101..3103 PASS (suite rerun rc=0)" }
      - { ac: Spec-AC-02, call: compliant, citation: "untouched; TEST-3104/3105 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "target-thread reasons unchanged; descendant_unavailable now disclosed in D10 amendment; TEST-3106/3107 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "untouched; TEST-3108/3109 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "codex-rollout.mjs:365 still returns sum when every tree thread is ok (lower bound only added on the lost branch, :364); TEST-3110 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "observe/attribute unavailable path still prints usage_capture=none, lower bound never reaches append_run_flags (probe: observe --descendants, attribute); TEST-3111/3112 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "codex-usage.mjs:99-104; probe: root 150, meta-only child, limit 100 -> rc 3 exhausted degraded; limit 150 -> rc 3; limit 151 -> rc 4 unknown NOT enforced; pre-fix copy of 6774766c -> rc 4 at limit 100; TEST-3113/3114 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "attribute() untouched; TEST-3115 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "new field is an integer only; TEST-3116 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-3117 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: "no prose/registration change; TEST-3118/3119 PASS" }
      - { ac: Spec-AC-12, call: cannot-verify, citation: "TEST-3121 opt-in smoke SKIP (AAI_CODEX_SMOKE unset), unchanged" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-codex-usage.sh, line: 569,
          issue: "The new assertion uses lower bound 150 against limit 100, so it neither pins the at-limit boundary (>= vs >) nor asserts cumulative_total_tokens stays null",
          failure_scenario: "A later edit changes `lower >= limit` to `lower > limit` or sets cumulative_total_tokens: lower in the exhausted branch; TEST-3113 stays green. Today's code is correct on both (probe limit 150 -> rc 3; cumulative_total_tokens null)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/codex-usage.mjs, line: 102,
          issue: "The lower-bound exhausted verdict names only descendant_unavailable in degraded; degraded reasons of the readable threads (malformed_line, partial_tail, missing_field) are dropped because the lib's unavailable object does not carry sum.degraded",
          failure_scenario: "Root has a partial tail and a meta-only child, lower bound >= limit: verdict reads degraded: [descendant_unavailable] without partial_tail. Exit code and stop decision are unaffected; only the reason list is incomplete versus D10 'names its reasons'." }
  cannot_verify:
    - { claim: "How long a real Codex child stays meta-only after spawn, and whether an aborted spawn leaves a permanent meta-only rollout", closes_with: "opt-in smoke over a real CODEX_HOME (tracked by fu-codex-idle-descendant-false-park)" }
    - { claim: "Whether a real forked child's own usage arrives promptly", closes_with: "real rollout inspection under AAI_CODEX_SMOKE=1" }
    - { claim: "How often 2f ticks while Codex children are in flight", closes_with: "a recorded Codex parallel ride with tick timestamps" }
  overall: pass
```

# Code Review (re-review after B-1 remediation): PR #512, commit 4cdedc4f

security_relevant: false

- Scope: `git show 4cdedc4f` on top of `6774766c` (branch `fix/codex-usage-missing-from-run-budgets`, verified). Code files: `.aai/scripts/lib/codex-rollout.mjs` (+2/-1, now 387 lines, within the 420 cap), `.aai/scripts/codex-usage.mjs` (+7/-1), `tests/skills/test-aai-codex-usage.sh` (+6, TEST-3113). Ledger and spec: `docs/ai/decisions.jsonl` (+2: spec_amendment, follow_up), the D10 line of the spec plus a `frozen_sha256` restamp, and the prior review report.
- Spec: SPEC-0258, decisions D5, D10, D11.
- Prior report: `docs/ai/reviews/review-codex-usage-missing-from-run-budgets-20261028T223548Z.md` (B-1 BLOCKING, NB-1, NB-2).
- Anti-gaming: the dispatch named the checks to run and did not pre-rate anything. I walked the whole delta and re-derived every call below from a probe or a cited line.

## Evidence

- Suite: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-codex-usage.sh` gave rc=0. TEST-3101..3119 PASS, TEST-3121 SKIP (opt-in).
- `node .aai/scripts/spec-amend.mjs list --strict` gave rc=0, read without a pipe. The 2026-10-28T22:37:52Z SPEC-0258 record lists as `unsigned-tracked`, tracked_by `fu-amend-codex-usage-missing-from-909fcc` (open), class contract.
- RED log `docs/ai/tdd/codex-usage-pr512-b1-red.log` shows `rc-lower-bound: expected [3] got [4]` with the old `unavailable/unknown` output. I confirmed it independently: running the same fixture through a scratch copy of the 6774766c CLI and lib gives rc 4 at limit 100. The GREEN log shows TEST-3113 PASS.
- Probes on a synthetic scratch CODEX_HOME (root R with one record of total 150; HOME empty; CODEX_THREAD_ID unset):

| # | Tree | Limit | Result |
|---|------|-------|--------|
| 1 | R + meta-only child C | 100 | rc 3, exhausted, enforcement degraded, degraded [descendant_unavailable], lower_bound 150, cumulative_total_tokens **null**. The human line says `exhausted lower_bound=150 ...` |
| 2 | same | 150 (boundary) | rc 3 exhausted |
| 3 | same | 151 | rc 4, unknown, enforcement unavailable, `NOT enforced`, no `within`. Never active |
| 4 | same, `observe --descendants` | n/a | rc 4 unavailable, lower_bound 150, append_run_flags `usage_capture=none`, no token flags |
| 5 | same, `attribute` (C spawned in window) | n/a | rc 4 unavailable, `usage_capture=none` |
| 6 | + readable child K whose record lacks total_tokens | 100 | rc 4 unknown (sum total null, so no lower bound and no false exhausted) |
| 7 | R with no usage, child G 200, C lost | 100 | rc 3 exhausted, lower_bound 200 (the root tolerance stated in the amendment holds) |
| 8 | R with no usage, C lost, no other child | 1 | rc 4 `no_usage_events` |

## Checks from the dispatch

- **B-1 closed.** Probe 1 gives rc 3 where the prior round gave rc 4. Below the limit (probe 3) it gives rc 4 and is never active.
- **The lower bound is never presented as the total.** `cumulative_total_tokens` stays null and the value goes into a separately named `lower_bound_total_tokens`. Observe/attribute flags never turn it into `--tokens-*`.
- **No new silent-loss or false-active path.** The new branch can only move an exit-4 case to exit 3, which is stricter. Every other path is byte-identical. A null component on a readable thread yields no numeric bound (probe 6), so the code never guesses.
- **The amendment text matches the code.** The D10 line names the fields, exit 4 by default, exit 3 / degraded when bound >= N, and the root tolerance, and probes 1, 3, 4 and 7 confirm each. One small wording point: the amendment says the descendant "has no usage events". The code triggers on any non-ok descendant. In practice the only reachable non-ok reason for a tree member is `no_usage_events`, because the tree comes from metas that were found. `descendant_reason` is emitted either way, so this is not a finding.
- **Lib ≤ 420.** It is 387 lines.

## Findings

**NB-1 (NON-BLOCKING), `tests/skills/test-aai-codex-usage.sh:569`.** The regression fixture sits well above the limit (150 vs 100). A `>=` to `>` mutation of `codex-usage.mjs:100` therefore survives, and nothing asserts that `cumulative_total_tokens` stays null in the exhausted branch. The code is correct today (probe 2, probe 1). Disposition: remediate-in-tree if another round happens anyway (add `--max-run-tokens 150` expecting rc 3 and `expect_eq cum-null null ...`). Otherwise it is an accepted residual: it guards against a future regression, not a present defect.

**NB-2 (NON-BLOCKING), `.aai/scripts/codex-usage.mjs:102`.** The degraded list on the lower-bound exhausted verdict leaves out the readable threads' own degraded reasons. The decision is unaffected. Disposition: accepted residual. It is a reason-list completeness gap on an exit that already stops the run, and it can fold into `fu-codex-idle-descendant-false-park` when that is planned.

**Prior NB-1 (spec disclosure).** Closed by the D10 amendment and the spec-amend record above.
**Prior NB-2 (idle-descendant false park).** Promoted. The follow_up `fu-codex-idle-descendant-false-park` (P2) is present in `docs/ai/decisions.jsonl` at 2026-10-28T22:37:59Z.

## cannot_verify

1. Real Codex child meta-only duration, and whether an aborted spawn leaves a permanent meta-only rollout. Closes with the opt-in smoke.
2. Prompt arrival of a real forked child's own usage. Closes with `AAI_CODEX_SMOKE=1` rollout inspection.
3. 2f tick frequency during parallel Codex dispatch. Closes with a recorded parallel ride.

## Next steps

1. Orchestrator records this verdict (pass) and replies to the Codex P1 thread citing 4cdedc4f and TEST-3113 (lower-bound clause). Resolve the thread afterwards.
2. Optionally fold NB-1's two assertions into the next commit on this branch, with no re-review needed for a test-only tightening.
