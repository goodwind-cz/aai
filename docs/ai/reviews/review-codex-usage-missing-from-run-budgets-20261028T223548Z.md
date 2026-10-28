```yaml
review:
  scope: "git show 6774766c (on top of 041aced9), PR #512 remediation round"
  spec: docs/specs/SPEC-0258-spec-codex-usage-missing-from-run-budgets.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "untouched by delta; TEST-3101..3103 PASS (suite rerun rc=0)" }
      - { ac: Spec-AC-02, call: compliant, citation: "untouched by delta; TEST-3104/3105 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "the four target-thread reasons unchanged; TEST-3106/3107 PASS. descendant_unavailable is an added fifth reason (see finding NB-1)" }
      - { ac: Spec-AC-04, call: compliant, citation: "untouched; TEST-3108/3109 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "codex-rollout.mjs:360-364 returns sum when every tree thread is ok; TEST-3110 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "unavailable path prints usage_capture=none (probe 5 output); TEST-3111/3112 PASS" }
      - { ac: Spec-AC-07, call: non-compliant, citation: "probe 2b: root total 150, limit 100, one meta-only child -> exit 4 unknown; AC-07 requires exit 3 when root plus descendants total is at or above N, and that total is provably >= 150 (finding B-1). Pre-fix head exited 3 here" }
      - { ac: Spec-AC-08, call: compliant, citation: "attribute() untouched by delta; TEST-3115 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "new fields are ids and a reason string only; TEST-3116 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "codex-usage.mjs:3 header now names probe (Copilot thread); TEST-3117 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: "no prose/registration change in delta; TEST-3118/3119 PASS" }
      - { ac: Spec-AC-12, call: cannot-verify, citation: "TEST-3121 opt-in smoke SKIP (AAI_CODEX_SMOKE unset), unchanged from prior round" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/lib/codex-rollout.mjs, line: 363,
          issue: "A lost descendant discards the known lower bound, so a provably exhausted run reads unavailable instead of exhausted",
          failure_scenario: "Root R has 150 tokens since S, limit 100, child C has session_meta only (spawned, first response in flight, or spawn aborted). budget exits 4 'NOT enforced (descendant_unavailable)' instead of 3. Attended loop (D11) prints NOT enforced and CONTINUES past a budget it has already exceeded; with a never-writing child this lasts the whole run. Before 6774766c the same input exited 3." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/codex-rollout.mjs, line: 362,
          issue: "Any meta-only descendant in the tree makes the whole tree unavailable, including idle or dead children and children spawned before --since",
          failure_scenario: "Unattended ride, parallel dispatch: at the 2f tick a child has written session_meta but no usage yet -> exit 4 -> D11 parks the ride (false park). A child whose spawn aborted before any model call never writes usage -> every resume parks again (probe 6: a meta-only child stamped a day before --since still gives exit 4)." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0258-spec-codex-usage-missing-from-run-budgets.md, line: 53,
          issue: "descendant_unavailable (with fields descendant, descendant_reason) is an observable output and a behaviour change of budget not stated in frozen D5/D10",
          failure_scenario: "A consumer or later reviewer reading D5's closed-looking list of four reasons treats descendant_unavailable as an undocumented reason; the spec no longer describes what budget does for a tree with an idle child." }
  cannot_verify:
    - { claim: "How long a real Codex child stays meta-only after spawn, and whether an aborted spawn leaves a permanent meta-only rollout", closes_with: "opt-in smoke over a real CODEX_HOME capturing a child rollout before its first response, and one interrupted spawn" }
    - { claim: "Whether forked children carry their own usage events soon after fork (probe 3 assumes forked parent records carry the parent thread_id)", closes_with: "real child rollout inspection under AAI_CODEX_SMOKE=1" }
    - { claim: "How often the 2f tick runs while children are in flight (serial vs parallel orchestration on Codex)", closes_with: "a recorded Codex parallel ride with tick timestamps vs child first-usage timestamps" }
  overall: fail
```

# Code Review (re-review after remediation) — PR #512, commit 6774766c

security_relevant: false

- Scope: `git show 6774766c` on top of `041aced9` (branch `fix/codex-usage-missing-from-run-budgets`). Files: `.aai/scripts/lib/codex-rollout.mjs` (+5/-1), `.aai/scripts/codex-usage.mjs` (header line), `tests/skills/test-aai-codex-usage.sh` (+11, TEST-3113).
- Spec: SPEC-0258 (frozen), decisions D5, D7, D10, D11.
- Prior review: `docs/ai/reviews/review-codex-usage-missing-from-run-budgets-20261028T220545Z.md`.
- Dispatch note (anti-gaming): the dispatch framed three questions and named a hazard to probe. It did not pre-rate severity. The whole delta was walked and every call below rests on a probe or a cited line.

## Evidence

- Suite: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-codex-usage.sh` gave rc=0. TEST-3101..3120 PASS, TEST-3121 SKIP (opt-in).
- RED/GREEN for the regression assertion: `docs/ai/tdd/codex-usage-pr512-p1-red.log` (line 2: `rc-desc-unavail: expected [4] got [0]`, out `within cumulative=150 enforcement=active`), then `codex-usage-pr512-p1-green.log` (TEST-3113 PASS). The External Review Response step 3 failing-first requirement is met.
- Probes on a synthetic CODEX_HOME in scratch (root R with one record of 150 total; HOME empty, CODEX_THREAD_ID unset):

| # | Tree | Limit | Result |
|---|------|-------|--------|
| 1 | R only | 1000 | rc 0, active, within 150 |
| 1b | R only | 100 | rc 3, exhausted |
| 2 | R + child C (session_meta only) | 1000 | rc 4, unavailable, descendant_unavailable; human line `NOT enforced`, no `within` |
| 2b | same | 100 | **rc 4, unknown** (was rc 3 before the fix) |
| 3 | C also carries forked parent meta and parent record (thread_id R) | 1000 | rc 4 (forked records correctly not counted for C) |
| 4 | C writes its first own record (15) | 1000 | rc 0, active, 165 |
| 6 | idle child O, meta stamped a day before --since | 1000 | rc 4 |
| 7 | R has no usage, C has 15 | 1000 | rc 0, active, 15 (root missing is tolerated, a descendant missing is not) |

## Questions from the dispatch

**(a) Is exit 4 rather than degraded the right reading?** Yes, as the default. D10 says degraded "still decides on the observed numbers". Here the observed numbers leave out a whole thread, so deciding on them means counting that thread as 0, which D5 ("missing is not zero") forbids. D5's own nearest case agrees: a component missing from a counted record makes `total_tokens` null, and budget turns a null total into unavailable (`total_tokens_missing`, exit 4). D10 also requires "root thread plus all descendants". The pre-fix filter (`sum.status === 'ok' ? sum : rootObs` over an `ok`-only sum) broke both. **One exception, finding B-1:** unknown means "not known to be within", but it does not mean "not known to be exhausted". Usage is never negative, so the sum of the readable threads is a lower bound. When that lower bound is already at or above N, D10 and AC-07 call for exit 3. The fix returns 4 there.

**(b) Is a fifth reason a contract change?** It is within D5's intent but beyond its text, so it needs disclosure (NB-1). D5's four reasons all describe the *target* thread. `descendant_unavailable` carries the fourth one (`no_usage_events`) up from a descendant, which D7/D10 bring into the tree. No consumer matches on reason strings: grep across `.aai/*.md` and `.aai/scripts` finds none outside the lib and the CLI. `invalid_interval` and `total_tokens_missing` already ship outside D5's list with no amendment, so the list was never closed in practice. The change is still visible, though. `budget` now exits 4 on a tree it previously decided, and that tree shape appears nowhere in D10. Recommended: additive-with-disclosure, `--signoff none`, class contract. The orchestrator records it and the spec is not edited by this reviewer:

```
node .aai/scripts/spec-amend.mjs add --spec docs/specs/SPEC-0258-spec-codex-usage-missing-from-run-budgets.md --ref codex-usage-missing-from-run-budgets --signoff none --class contract \
  --what "D5/D10: observe --descendants and budget return status unavailable, reason descendant_unavailable (fields descendant, descendant_reason; exit 4, enforcement unavailable) when a descendant thread in the tree has no usage events; budget still exits 3 exhausted when the readable threads alone reach the limit. D5's four reasons are the target thread's; invalid_interval and total_tokens_missing are likewise disclosed" \
  --why "PR #512 Codex P1: dropping an unreadable descendant reported active/within on an undercounted total, contrary to D5 missing-is-not-zero and D10 root-plus-all-descendants"
```

(Drop the "still exits 3" clause if B-1 is not remediated.)

**(c) Hazard of the just-spawned child.** Probes 2, 3 and 6 confirm it. A meta-only child makes the whole tree unavailable (rc 4), and an unattended ride then parks under D11. Rated **NON-BLOCKING with a follow-up**, for these reasons:
- The failure goes the safe way. The ride stops visibly and does not overspend. That matches D11's stated premise that "an unattended ride may only start with an armed budget".
- A serial Codex ride ticks 2f between roles, after the child has finished and written its usage. The window is real mainly for parallel dispatch, for the seconds before a child's first response.
- The serious form is permanence. A child that never writes usage, such as an aborted spawn, or a meta-only child from earlier in the same root session (probe 6, where descendants are not filtered by --since), leaves enforcement unavailable for the rest of the run. Every unattended resume then parks again, and an attended run is never budget-stopped. That is P2 work and not merge-blocking, because it is visible and fails closed. B-1's fix removes the attended over-run half of it once the readable total crosses N.
- "Missing is not zero" alone does not make it acceptable. The spec never weighed this trade, so it gets a tracked follow-up and not an accepted residual.

## Findings

**B-1 (BLOCKING), `.aai/scripts/lib/codex-rollout.mjs:363` with `.aai/scripts/codex-usage.mjs:99-101`.** When a descendant is lost, observe returns a bare `unavailable` and drops the readable partial sum. budget then reports `unknown` (exit 4) even when the partial sum alone is at or above the limit (probe 2b: 150 vs 100, rc 4). Before this commit the same input gave rc 3. Under D11's attended branch the loop prints NOT enforced and keeps running past a budget it has demonstrably exhausted. With a child that never writes usage, that lasts the whole run. AC-07 is non-compliant on this edge. Remediation (small): when a descendant is lost and every readable thread has a numeric `total_tokens`, put `lower_bound_total_tokens` (the sum of the ok threads) on the unavailable object. In `runBudget`, if `lower_bound_total_tokens >= limit`, emit `verdict: exhausted`, `enforcement: degraded`, `degraded: ['descendant_unavailable']` and exit 3. Below the limit, keep exit 4. Regression: extend TEST-3113 with the same idle-child fixture at `--max-run-tokens 100` expecting rc 3 / exhausted, RED against 6774766c first.

**NB-1 (NON-BLOCKING), spec D5/D10 (`SPEC-0258…md:53,67`).** An undisclosed fifth reason and a new budget behaviour. Disposition: remediate-in-tree, meaning the orchestrator records the spec-amend above (`--signoff none`).

**NB-2 (NON-BLOCKING, P2), `.aai/scripts/lib/codex-rollout.mjs:362`.** A false park on a just-spawned child, and a permanent "not enforced" state with a never-writing descendant (see (c)). Disposition: promote to follow-up, suggested id `fu-codex-idle-descendant-false-park` (suggested: not filed by this reviewer). Remedy options to weigh in Planning: give the gate a bounded grace for a descendant whose first meta is younger than N seconds (degraded, not unavailable), or exclude meta-only descendants stamped before `--since` and with no events, or have SKILL_LOOP 2f retry exit-4 `descendant_unavailable` once before parking. Each must keep D5's "never count unknown as zero toward `within`" for non-grace cases.

**INFO.** Asymmetry (probe 7): a root with `no_usage_events` is tolerated as 0 (line 356, pre-existing from 041aced9) while a descendant is not. The asymmetry is pre-existing and was not introduced by this delta. It has no realistic impact because the orchestrator that runs budget has itself made model calls by then. Worth one sentence in the NB-1 amendment or the follow-up.

**INFO.** The Copilot thread fix at `codex-usage.mjs:3` is correct. The header now lists all four subcommands, matching line 133.

## cannot_verify

1. How long a real Codex child stays meta-only after spawn, and whether an aborted spawn leaves a permanent meta-only rollout. Closes with an opt-in smoke over a real CODEX_HOME.
2. Whether a real forked child's own usage arrives promptly (probe 3 used synthetic forked lines). Closes with a real rollout inspection under `AAI_CODEX_SMOKE=1`.
3. How often 2f ticks while Codex children are in flight. Closes with a recorded Codex parallel ride.

## Next steps

1. Remediate B-1 with failing-first evidence (TEST-3113 extension), then run the re-review again.
2. Orchestrator records the NB-1 spec-amend (`--signoff none`) after the B-1 text is settled.
3. Orchestrator files `fu-codex-idle-descendant-false-park` (P2) for NB-2 and names it in `code_review.notes`.
4. Reply to the Codex P1 thread citing the fix commit and TEST-3113. Mention the lower-bound follow-on once B-1 lands.
