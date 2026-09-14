# Code Review — dispatch-state-sweep (wave 3, sweep 3)

```yaml
review:
  scope: "uncommitted worktree delta on feat/dispatch-state-sweep over main 082ad4aa (HEAD 2fb2f4cd) — 39 dirty paths; STATE code_review.scope (32 paths) + the spec's Review scope (35)"
  spec: docs/specs/SPEC-0180-spec-dispatch-state-sweep.md
  reviewer: claude-opus-5[1m] (independent of the implementer claude-sonnet-5 and of all three validation rounds)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,   citation: ".aai/scripts/state.mjs:679-692 (set-focus else-branch writes spec_path null) + :782-793 (set-phase --spec-path refresh); TEST-032 green; my MUT-2 (revert the else-branch) reddens arm (a)" }
      - { ac: Spec-AC-02, call: compliant,   citation: ".aai/scripts/orchestration-dispatch.mjs:385 isVerdictStale, :576 rule arm (after 12, before 13/14), :119 RULES row, :1660 WARN names the rule; TEST-061 green; my MUT-5 (move after 13) and MUT-6 (unconditional restamp reason) both redden it" }
      - { ac: Spec-AC-03, call: compliant,   citation: ".aai/scripts/state.mjs:802-839 cmdClearFocus; .aai/scripts/generate-overview.mjs:128,271 second input; TEST-033 + TEST-009 green; my MUT-12 (single input) reddens the phase-closed arm; my MUT-3 (drop the --ref refusal) reddens the cmp arm. Deviation: NON-BLOCKING-1" }
      - { ac: Spec-AC-04, call: compliant,   citation: ".aai/scripts/metrics-flush.mjs:881-888 (required no longer written in applyPartialReset; applyFullReset unchanged); TEST-149 green; my MUT-8 (restore the line) reddens the primary arm" }
      - { ac: Spec-AC-05, call: compliant,   citation: ".aai/scripts/state.mjs:1165-1168 derived usage_basis, :1195 emitted, :1272-1279 the one stderr line; TEST-034 green; probed live: field / note / absent (malformed marker falls to absent), exit 0 in all three. Literal-wording note: NON-BLOCKING-8 (carried N4)" }
      - { ac: Spec-AC-06, call: compliant,   citation: ".aai/scripts/state.mjs:1291-1384 amendAgentRun, :1386-1400 cmdAmendRun; TEST-035 green; probed live: amend once, refuse on already-numeric (STATE byte-identical), refuse on 0 matches; my MUT-4 (matches.length < 1) reddens the ambiguity arm. Semantic gap: NON-BLOCKING-2" }
      - { ac: Spec-AC-07, call: compliant,   citation: ".aai/scripts/lib/iso-time.mjs; grep over .aai/scripts finds ZERO `function nowIso` outside it; append-event.mjs / follow-ups.mjs / spec-amend.mjs / update-check.mjs / lib/state-engine.mjs all import it; the live EVENTS.jsonl tail carries ts 2026-09-13T22:04:29Z (second precision). TEST-036 green" }
      - { ac: Spec-AC-08, call: compliant,   citation: ".aai/scripts/heartbeat.mjs:463-478; probed live: fresh -> 0, back-dated -> 4, ABSENT dir (cold start) -> 4, EACCES dir -> 3, three distinct stderr texts; `grep -rc newermt .aai/` returns zero hits. TEST-025 green" }
      - { ac: Spec-AC-09, call: compliant,   citation: ".aai/scripts/watch-ci.mjs; stub-gh probes: all-pass -> 0, one fail -> 5, gh absent -> 3 naming the degrade; .aai/SKILL_PR.prompt.md:263-266 names the command in the post-push step. TEST-062 green. The AC's four literal clauses hold — BLOCKING-1 is a defect OUTSIDE this AC's text" }
      - { ac: Spec-AC-10, call: compliant,   citation: "SKILL_CODE_REVIEW.prompt.md:14-21, SKILL_WORKTREE.prompt.md:165-171, METRICS_FLUSH.prompt.md:45, STATE_FALLBACK.md:10-14 all carry the D1 carve predicate; the 'an explicit instruction' grant is gone from the corpus. TEST-063 green" }
      - { ac: Spec-AC-11, call: compliant,   citation: ".aai/scripts/check-dispatch-text.mjs:73-95 (three detectors, advisory default, exit 6 under --strict); SUBAGENT_PROTOCOL.md:86-93 carries the rule. TEST-064 green; I ran it over three REAL dispatch texts (this review's own dispatch, VALIDATION.prompt.md, REMEDIATION.prompt.md, IMPLEMENTATION.prompt.md) — all exit 0, no false positive. See NON-BLOCKING-3 for the self-referential case" }
      - { ac: Spec-AC-12, call: compliant,   citation: ".aai/scripts/state.mjs:515-524 realpathDirTarget, :526-541 isGuardedStatePath, :1595 the call site; probed live under AAI_ROLE=subagent: relative --state from a cwd INSIDE the repo -> 3 (file byte-identical), `./docs/../docs/ai/STATE.yaml` -> 3, synthesized other AAI project -> 3, scratch fixture -> 0 (writes). `AAI_ROLE=subagent bash tests/skills/test-aai-check-state.sh` (no env scrub) -> exit 0, 17 PASS, re-run by me. TEST-037 + TEST-039 green; my MUT-1 (drop realpathDirTarget) reddens arm (a). Residual: NON-BLOCKING-4" }
      - { ac: Spec-AC-13, call: compliant,   citation: ".aai/scripts/heartbeat.mjs:301-316 pre-read collision report, :327 ref_id_raw; TEST-026 green" }
      - { ac: Spec-AC-14, call: compliant,   citation: ".aai/scripts/heartbeat.mjs:380 reap on the read path; TEST-027 green; my MUT-9 (remove the reap) reddens exactly the stale-file-gone arm while the listing arm stays green" }
      - { ac: Spec-AC-15, call: compliant,   citation: ".aai/scripts/heartbeat.mjs:250 validator requires writer_pid, :335 writer, :451 reader, :19-25 the header sentence; TEST-028 green" }
      - { ac: Spec-AC-16, call: compliant,   citation: ".aai/scripts/orchestration-dispatch.mjs:1225-1240 suffixed effort header recognized+ignored, :1269-1276 the NOTE; TEST-065 green (re-run by me)" }
      - { ac: Spec-AC-17, call: compliant,   citation: ".aai/scripts/check-committed-scope.mjs:210-218 ledger list, :221-247 committedBytes/appendedLineCount, :312-318 the append lane, :341 divergence naming; TEST-008 green; I drove the real CLI over a git fixture: append -> exit 0 'append +1 line(s)', middle-line rewrite -> exit 1 'divergence — not an append', SHRINK -> exit 1 divergence. My MUT-10b (empty the ledger list) reddens the append arm. Test-strength gap: NON-BLOCKING-6" }
      - { ac: Spec-AC-18, call: compliant,   citation: ".aai/scripts/state.mjs:190 currentCmd, :311-384 CMD_FLAG_META, :385-400 renderUsage/CMD_USAGE, :1552-1560 the --help wiring, :193-196 fail() appends it; I ran `--help` for ALL 13 CMD_FLAGS subcommands: exit 0 each, enums rendered from the constants (set-validation lists pass|fail|not_run and no `pending`), reset-block renders the `<block>` positional; every refusal I triggered in this review carried the same line. TEST-038 green" }
      - { ac: Spec-AC-19, call: compliant,   citation: ".aai/scripts/metrics-flush.mjs:560 IMPLEMENTER_ROLES, :568-578 lastVerdictInstant, :582-593 verdictAfterLastImplementer (null on any missing/unparseable instant), :773-776 additive on reliability; TEST-150 green. Boundary semantics: NON-BLOCKING-5" }
      - { ac: Spec-AC-20, call: compliant,   citation: ".aai/scripts/metrics-flush.mjs:1184-1193 re-append advice naming the missing count; `grep -n 'git restore|git checkout|git reset' .aai/scripts/metrics-flush.mjs` returns ZERO hits. TEST-151 green" }
      - { ac: Spec-AC-21, call: compliant,   citation: ".aai/system/PROFILES.yaml:127-133,148 classify watch-ci.mjs, check-dispatch-text.mjs and lib/iso-time.mjs; tests/skills/lib/prompt-diet-ledger.sh:200-201 carry both entries. I re-ran both suites myself: layer-profiles exit 0 (12 PASS), prompt-diet exit 0 (23 PASS, 'TEST-012 JUSTIFIED_GROWTH_BYTES == 28140 == independent re-sum', TEST-010 headroom 2046/2048)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/watch-ci.mjs, line: 160,
          issue: "the terminal `skipping` bucket is counted as PENDING, so a PR carrying any skipped check never settles: watch-ci polls to its --max-wait-seconds deadline (default 3600) and then exits 3 'degraded — checks still pending', on a PR whose checks all passed",
          failure_scenario: "`gh pr checks 378 --json name,bucket` on THIS repository returns {\"bucket\":\"skipping\",\"name\":\"skill suite (selected, via test-framework.sh --skill)\"} alongside eight passes, and gh itself exits 0 (settled). SKILL_PR step 5c (as amended by this ride) tells the ceremony to run `node .aai/scripts/watch-ci.mjs --pr <n>` after every `gh pr create`, and its own added line says 'a degrade is never a pass'. Reproduced with a stub gh: a 2-check fixture (pass + skipping) polls until the deadline and exits 3 — measured 3.08 s against --max-wait-seconds 3, i.e. one hour with the shipped defaults. Spec-AC-09's three stub arms never exercise a skipping bucket, so the suite is green on a probe that cannot reach its own pass path on the repository it was written for. Fix: `pending` = bucket 'pending' only (a skipped/neutral check is settled and non-failing), plus a fourth TEST-062 arm." }
      - { rank: NON-BLOCKING, file: .aai/scripts/state.mjs, line: 828,
          issue: "clear-focus REPLACES an existing `phase:`/`status:` line but never INSERTS a missing one, and reports success unconditionally — so it can announce 'work item phase=closed status=done' for a work item that has no phase key, or no work item at all",
          failure_scenario: "A fixture whose focused work item carries ref_id/title/status but no `phase:` (check-state.mjs enforces no phase key on work items — grep for 'phase' in that file returns nothing): `clear-focus --ref REF-1` exits 0 printing 'work item phase=closed status=done' while the item keeps no phase at all. Same message on `active_work_items: []`. D3's second overview input (phase == 'closed') then silently does not engage; only the nulled focus (the first input) saves the rendering. Recommended disposition: promote-to-follow-up (P3) fu-clearfocus-announces-unwritten-phase — report what was written, or insert the key." }
      - { rank: NON-BLOCKING, file: .aai/scripts/state.mjs, line: 1360,
          issue: "amend-run's 'never rewrites a number' guard tests only the tokens_total FIELD, so a run whose usage number lives in a well-formed --note marker (usage_basis: note) is amendable — the new number silently overrides a recorded one and the contradicting note stays in the record",
          failure_scenario: "Probed live: `append-run --note 'usage_total_tokens=1234'` writes usage_basis: note; `amend-run ... --tokens-total 4321` exits 0 and writes usage_basis: field, tokens_total: 4321, amended_at_utc — while `note: usage_total_tokens=1234` remains on the same run. The flush is field-first, so the ledger takes 4321 and the note's 1234 becomes a false record inside the same entry. D6's own title ('fills a hole once, and never rewrites a number') is not honoured for the note basis. Recommended disposition: typed follow-up (P2) fu-amend-run-overwrites-note-basis-number — refuse, or require an explicit override flag." }
      - { rank: NON-BLOCKING, file: .aai/scripts/check-dispatch-text.mjs, line: 76,
          issue: "PRE_RATING_PHRASE_RE is a bare substring match with no exclusion for quoting, negation or work-ordering prose, so the guard fires on the very rule it enforces and on legitimate orchestration text",
          failure_scenario: "`check-dispatch-text.mjs --path .aai/SUBAGENT_PROTOCOL.md --strict` exits 6 on three lines — including the D11 rule's own wording ('never a ranked answer key', 'a \"most likely\"/\"start with the\" steer') and line 357's legitimate 'Execute units sequentially in priority order (FAIL > VALIDATION > IMPLEMENTATION > PLANNING)'. `--path .aai/SKILL_CODE_REVIEW.prompt.md --strict` exits 6 on 'concurrency, error handling), ranked:'. D11's stated purpose is wiring this into the orchestration tick; a dispatch that quotes the standing rule (a very common shape) would be refused. Advisory-by-default is the mitigation and R5 discloses the closed set will MISS shapes, but not that it fires on its own statement. Recommended disposition: typed follow-up (P3) fu-dispatch-text-detector-self-referential-fp." }
      - { rank: NON-BLOCKING, file: .aai/scripts/state.mjs, line: 515,
          issue: "realpathDirTarget resolves a path's CONTAINING DIRECTORY only, so a symlinked LEAF into the repo's real STATE is not judged by either arm and the mutator runs",
          failure_scenario: "`ln -s <repo>/docs/ai/STATE.yaml <scratch>/STATE.yaml`, then `AAI_ROLE=subagent state.mjs set-human-input --state <scratch>/STATE.yaml` exits 0. PROVED HARMLESS and verified byte-for-byte: loadState reads THROUGH the link but writeState is tmp+rename, so the symlink is replaced by a regular file and the real STATE's md5 is unchanged — no shipping STATE is ever written. Recommended disposition: (d) accepted residual — a P3 assurance-strength edge with no observed bite, under D12's own 'guardrail against habit, not a security boundary' posture; the Amendment's B1 claim is about the DIRECTORY-symlink class and stays true." }
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 592,
          issue: "verdict_after_last_implementer uses `>=` where Spec-AC-19 says 'later than', and NO test pins the boundary — D7's second-precision coarsening widens the same-second window this decides wrongly",
          failure_scenario: "Mutation MUT-7 (`>=` -> `>`) leaves test_150_verdict_after_last_implementer GREEN, so the boundary is unasserted in either direction. An implementer run started at 12:00:00.900 and a verdict event stamped 12:00:00.100 both truncate to 12:00:00, so the ledger records `true` ('the verdict covers the final bytes') for a ride whose last work started AFTER its last verdict — the exact polarity D17 exists to make impossible ('a missing measurement must never render as good news'). Window < 1 s. Corroborates the validator's N5. Recommended disposition: typed follow-up (P3) fu-verdict-coverage-same-second-reads-true, or a two-character fix plus a TEST-150 boundary arm." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-learned-routing.sh, line: 519,
          issue: "TEST-008 does not pin the SHRINK arm of D15 — a ledger whose worktree content is SHORTER than the committed blob",
          failure_scenario: "Mutation MUT-10 (`appendedLineCount` returning 0 instead of null when worktree.length < committed.length, i.e. classifying a truncation as a 0-line append) leaves TEST-008 GREEN. The shipped code is CORRECT — I drove the real CLI over a git fixture and a 3-line -> 2-line shrink reports 'divergence — not an append' and exits 1 — but the arm that would catch a regression here is the HAZ-LEDGER incident class itself. Recommended disposition: typed follow-up (P3) fu-ledger-shrink-arm-unpinned (one extra fixture arm)." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-state.sh, line: 2991,
          issue: "TEST-036 arm (e) still false-reds under an event-loop stall > MARGIN_MS (50 ms): the bounded retry guards the ALIGNMENT, not the COMPARISON (validator N23, re-read here and confirmed by construction)",
          failure_scenario: "Once `a` is sampled there is no re-sample and no tolerance; the validator measured 6/50 false reds at a 100 ms injected stall, 22/50 at 500 ms. This repo's CI already flakes under load (the Windows Pester leg, the reaper cases), and this arm is on the CORE state suite. Recommended disposition: (a) remediate-in-tree BEFORE merge with the two-line fix the validator wrote out (capture Date.now() around the pair, retry only when the wall-clock second actually moved) — it is a test-only file, no protected surface, and M17 still reddens because under a millisecond nowIso `a !== b` holds with the seconds EQUAL." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0180-spec-dispatch-state-sweep.md, line: 858,
          issue: "six stale-prose defects in the frozen spec and its evidence, all carried un-fixed (validator N18, N19, N20, N21, N22, N24, N26) — including an Amendment whose closing sentence, 'Every claim above was grepped or run TRUE against the shipped tree', is false of three clauses",
          failure_scenario: "Re-verified here: :875 Seam S8 still names metrics-flush.mjs and orchestration-dispatch.mjs as lib/iso-time.mjs consumers (neither imports it — metrics-flush computes its own nowIsoStr at :1251, the very line R4 names as a DELIBERATE remaining copy); :858 M40 claims a mutation that does not redden; :1095 describes arm (e) as 'two independent processes ~60ms apart' when it is one process 20 ms apart. A future reader re-deriving the ride from the spec is misled at exactly the places this ride exists to make falsifiable. Recommended disposition: ONE amendment paragraph covering N18/N19/N20/N21/N22/N24/N26 plus a decisions.jsonl spec_amendment record — the validator's own recommendation, and it restores the round-1 disclosure pattern the round-2 remediation dropped." }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 1,
          issue: "the amendment record and the 18 close records live in a dirty ledger that is in NEITHER scope list and is not named an expected companion by SKILL_PR step 3 — it can be dropped at staging with every gate still green (validator N25)",
          failure_scenario: "The validator PROBED it: with decisions.jsonl reverted to HEAD, `spec-amend list --strict` exits 0 with this spec no longer listed at all, and `docs-audit --check --strict --no-event` reports CLEAN. A PR shipping an amended FROZEN spec with no amendment record passes every gate — the same unfalsifiable shape as B5's original `^export function nowIso` grep. I confirmed the ledger itself is append-only-clean (21 added lines, 0 removed, committed blob a byte-exact prefix). Recommended disposition: (a) remediate at staging — name docs/ai/decisions.jsonl and docs/ai/tests/test-runs.jsonl explicitly in the PR's in-scope staging list." }
      - { rank: NON-BLOCKING, file: .aai/scripts/state.mjs, line: 1291,
          issue: "amend-run CAN produce a STATE/ledger disagreement in the interrupted-flush window (the question the dispatch asked, answered precisely)",
          failure_scenario: "Normally safe: the flush DELETES the flushed metrics.work_items entry (header :18-22), so a post-flush amend-run finds 0 matches and exits 2 — verified from code and from the 0-match refusal I reproduced. The exception is a crash between the ledger append and the STATE commit (ordering documented at :34-40): the runs are still in STATE while their ledger line exists, and the resume lane is explicitly 'cleanup-only pass (no second append)'. An amend-run in that window writes a number that can never reach the ledger. Recommended disposition: (d) accepted residual — P3, crash-window only, the ledger stays authoritative and nothing false is recorded there." }
      - { rank: NON-BLOCKING, file: .aai/SKILL_CODE_REVIEW.prompt.md, line: 84,
          issue: "Spec-AC-05's 'exactly one stderr line SHALL name the ref and role' is literally violated whenever --tokens-in/--tokens-out are ALSO absent (carried validator N4)",
          failure_scenario: "Probed live: a bare append-run emits TWO WARNING lines that each name the ref and the role — the pre-existing token-capture warning and the new usage_basis one. The test counts only the usage_basis line, so the suite is green and the INTENT (one new line, exit 0) is met; the AC's wording is what is imprecise. Recommended disposition: (d) accepted residual — P3 wording, no behavioural defect, no false record." }
  cannot_verify:
    - { claim: "watch-ci.mjs settles correctly against a real GitHub PR",
        closes_with: "one live run against an open PR; I read PR #378's check buckets read-only (which is what makes BLOCKING-1 concrete) but never drove the poller against a live PR" }
    - { claim: "the t054a reconcile diff still applies to sweep 2's own uncommitted copy of new_fixture_repo()",
        closes_with: "reading sweep 2's worktree at merge time; from here only the failure is visible — `test-aai-close-work-item.sh` on this branch is exit 1 with exactly one FAIL (t054a), 52 PASS, which merge-reconcile-t054a.md's one-line fixture change resolves" }
    - { claim: "the delivered tree passes a FULL suite sweep",
        closes_with: "re-running the sweep with AAI_TEST_TIMEOUT=3000. `select-suites.mjs --files-from <dirty>` returns FULL_RUN reason=protected-l3 (.aai/scripts/lib/state-engine.mjs), and the recorded artifact sweep-20260913T170125.txt predates the round-2/3 remediations by ~3.5 h (sources changed to 20:39, the state suite to 23:14). 17 suites are green individually across the three validation rounds plus my own re-runs" }
    - { claim: "TEST-036 arm (e)'s flake rate on CI hardware",
        closes_with: "a CI run; every measurement in evidence is from one developer machine" }
    - { claim: "downstream consumer impact of the D1 set-focus semantics change after /aai-update",
        closes_with: "running a vendored downstream project. In-repo the exposure is bounded: orchestration-dispatch.mjs:920 reads the WORK ITEM's spec_path first and only falls back to current_focus, and PLANNING step 12's documented two-call sequence restores it via set-phase --spec-path (asserted by TEST-032's third arm). ORCHESTRATION_PARALLEL.prompt.md:127 omits --spec-path on BOTH calls, so a parallel retarget now nulls it and rule 5 re-plans — fail-closed, but D1's measurement ('the only in-repo caller of that shape is close-work-item.mjs') is narrower than the tree" }
    - { claim: "close-work-item.mjs calls clear-focus (seam S7 / R2)",
        closes_with: "sweep 2 landing the one line D3 writes out; until then only .aai/SKILL_PR.prompt.md:204-206 wires it, which covers the PR lane and not a close run outside it" }
    - { claim: "owner sign-off on the two post-freeze amendments",
        closes_with: "the owner signing; both decisions.jsonl records carry owner_signoff false, tracked by fu-amend-spec-dispatch-state-sweep" }
  overall: fail
```

## Scope and method

Reviewed the whole uncommitted delta on `feat/dispatch-state-sweep` (39 dirty
paths; `git diff` + `git status`), against the FROZEN spec
`docs/specs/SPEC-0180-spec-dispatch-state-sweep.md` (21 AC, 23 TEST, D1-D18,
two post-freeze amendments), ISSUE-0040, and the three validation rounds.

Nothing was run against the shipping worktree that writes. Every probe,
mutation and suite ran on a `git clone --local` of the branch with the
worktree rsync'd over it (`git status --porcelain` of the copy diffed
IDENTICAL to the worktree's 39 entries before starting). The real worktree's
`git status --porcelain` was captured before the first command and re-diffed
after the last: **identical, byte for byte** — no tracked file was mutated, no
page regenerated, no `git checkout --` needed. Mutated files in the copy were
restored from pristine byte copies, never by a git restore command
(HAZ-RESTORE). The only file this role writes is this report.

## Twelve mutations of my own choosing

Each applied to the scratch copy, single test run, then restored.

| # | Mutation | Target test | Result |
|---|----------|-------------|--------|
| MUT-1 | `isGuardedStatePath` back to `path.resolve()` only (revert B1) | test_077 | RED — `FAIL: (a) a directory symlink into the repo's docs/ai must refuse exit 3 (got 0)` |
| MUT-2 | `cmdSetFocus` else-branch back to the `type === 'none'` conditional | test_072 | RED — `FAIL: (a) current_focus.spec_path must be null ...` |
| MUT-3 | delete `clear-focus`'s `--ref` mismatch refusal | test_075 | RED — `FAIL: (b) clear-focus --ref ISSUE-9999 (mismatch) must exit 2 (got 0)` |
| MUT-4 | `amend-run` accepts `matches.length < 1` instead of `!== 1` | test_074 | RED — `FAIL: (c) amend-run against 2 matches must exit 2 (got 0)` |
| MUT-5 | move rule 11s to AFTER rule 13 | test_061 | RED |
| MUT-6 | push `restamp_requires_confirm` unconditionally | test_061 | RED |
| MUT-7 | `verdictMs >= startedMs` -> `>` | test_150 | **GREEN — boundary unpinned (NON-BLOCKING-5)** |
| MUT-8 | restore `required: false` in `applyPartialReset` | test_149 | RED — `FAIL: code_review.required must HOLD true ...` |
| MUT-9 | remove the reap from `cmdRead` | TEST-027 | RED — the stale slot survived; the listing arm stayed green |
| MUT-10 | `appendedLineCount` treats a SHRINK as a 0-line append | test_008 | **GREEN — shrink arm unpinned (NON-BLOCKING-6)** |
| MUT-10b | empty the ledger path list | test_008 | RED — `(a) an append-only ledger ... must exit 0, got 1` |
| MUT-11a | metrics: field-first verdict counting -> note-first (sweep 1's gate) | test_144 | RED — sweep 1's BLOCKING-1 gate still bites after this ride's edits |
| MUT-11b | metrics: drop the `scope_ref_id` stamp (sweep 1's gate) | test_148 | RED — still bites |
| MUT-12 | `generate-overview` back to the single `focus_ref` input | test_dph06 | RED — `FAIL: (b) a phase-closed work item ... must omit the In-flight section` |

Behavioural probes beyond the mutations: the R-GUARD under `AAI_ROLE=subagent`
against a relative `--state` from a cwd inside the repo, a `..` traversal, a
LEAF symlink, a synthesized second AAI project, a `.aai`-without-`state.mjs`
project (R3's disclosed gap — permits the write, as documented), and an
ordinary scratch path; `append-run` in all three usage bases including a
malformed marker; `amend-run` in five arms; `heartbeat read --max-age-seconds`
in four states plus GC-on-read against a caller-named `--dir`; `watch-ci`
against a stub `gh` in five shapes; `check-committed-scope` over a real git
fixture in three shapes; `state.mjs <cmd> --help` for all 13 subcommands;
`check-dispatch-text --strict` over four real dispatch texts; and
`AAI_ROLE=subagent bash tests/skills/test-aai-check-state.sh` with no env
scrub (exit 0, 17 PASS — D12's friction claim re-derived first-hand).

## Registry verification

**The 18 closed ids.** `follow-ups.mjs list --status open --json` returns 155
open items and NONE of the 18 is among them; all 18 carry a `follow_up_status`
record with `status: done, resolved_by: dispatch-state-sweep` (ts
2026-09-13T22:03:49Z). `decisions.jsonl` is append-only-clean: 21 added lines,
0 removed, and the committed blob is a byte-exact prefix of the worktree file.
Spot-checked TRUE IN THE TREE, not merely in the ledger, for ten of the
eighteen: `fu-setfocus-keeps-stale-spec-path` (MUT-2), `fu-validation-staleness-undetected`
(MUT-5/6), `fu-overview-shows-closed-ride-inflight` (MUT-12), `fu-flush-vacates-code-review-gate`
(MUT-8), `fu-usage-marker-omission-unfixable` (live append-run/amend-run probes),
`fu-ts-precision-unify-source` (zero other definitions, four named consumers
importing, live EVENTS ts at second precision), `fu-orchestrator-monitor-uses-gnu-find`
(0/4/3 probe + zero `-newermt` under `.aai/`), `fu-role-guard-blocks-own-fixtures`
(CORE suite green under the marker, no scrub), `fu-heartbeat-gc-only-runs-on-write`
(MUT-9), `fu-blob-check-ledger-append-noise` (three-shape git-fixture probe).
`fu-metrics-flush-advises-git-restore` additionally verified by grep: zero
`git restore` / `git checkout` / `git reset` strings anywhere in
`metrics-flush.mjs`.

**The 13 rejected ids.** Ten are still open, exactly as the spec says; the
three it calls "already CLOSED by sweep 1" are indeed absent from the open set
— the rejection reasons and the ledger agree in both directions. Five reasons
spot-checked against each item's own recorded text: `fu-verify-staged-set-after-commit`
("verify `git show --stat` after every commit" — commit ceremony, sweep 4),
`fu-validation-ignores-suite-selector` ("validation picks its suites from the
declared review scope while CI picks them from select-suites" — the selector
is sweep 2's surface), `fu-routing-file-overwritten-on-update` ("MODEL_ROUTING.yaml
sits in PROFILES core and aai-sync copy_replaces core files" — confirmed at
`.aai/system/PROFILES.yaml:191`, sweep 5), `fu-role-guard-noops-close-work-item`
(its own re-filing record names the AAI_ROLE guard class and
`close-work-item.mjs`, which is sweep 2's file), `fu-amend-metrics-flush-invalidate-59abba`
(an owner-signoff item on SPEC-0163's unsigned amendments — no code can
discharge it). All five hold.

## Disposing the validator's carried findings

- **N18** (M40's wording does not redden) — REAL, re-read at `:858`. Fold into
  the single amendment paragraph (NON-BLOCKING-9).
- **N19** (Seam S8's consumer list names two non-consumers) — REAL,
  re-verified: neither `metrics-flush.mjs` nor `orchestration-dispatch.mjs`
  imports `lib/iso-time.mjs`. Same amendment.
- **N23** (arm (e) false-reds under a >50 ms stall) — REAL and the only
  carried finding I would fix BEFORE merge: it is a CORE-suite CI flake in a
  repository that already flakes under load. NON-BLOCKING-7, disposition (a).
- **N24** (the two scope lists are not identical) — REAL and harmless: the
  spec's list is a strict superset by the three doc paths, and SKILL_PR step 1
  unions both sources. Fold into the amendment.
- **N25** (the amendment record can be lost at staging) — REAL and actionable
  at staging, not in code. NON-BLOCKING-10, disposition (a).
- **N26** (the spec now misdescribes arm (e) in two places) — REAL. Same
  amendment.
- **N27** (`check-base-ref-pins.mjs` / `check-cd-subshell-leak.mjs` self-invocation
  guards are blind to a symlinked path) — REAL, PRE-EXISTING on main (the
  validator reproduced it on a pristine `082ad4aa` clone), OUT OF SCOPE for
  this ride. Suggested id `fu-selfinvocation-guard-blind-to-symlinked-path` —
  the orchestrator files it; it must not block this merge.
- Also carried and disposed above: **N4** (NON-BLOCKING-8), **N5**
  (NON-BLOCKING-5, now with mutation evidence that no test pins it), **N7**
  (bounded — see the cannot_verify entry on D1's downstream reach), **N20/N21/N22**
  (fold into the amendment). **N6**, **N10**, **N11**, **N13**, **N17** stand
  as the validator left them and change nothing here; N11's TEST-029 red is
  driven by precisely this spec's 18 closed ids and is already cleared by the
  orchestrator's close records.

## The dispatch's own questions, answered

- **Can `amend-run` change a run AFTER it was flushed?** Only in the
  interrupted-flush crash window — see NON-BLOCKING-11 for the exact
  ordering. In the normal lane the flush deletes the work_items entry and
  `amend-run` exits 2 with 0 matches.
- **A race between realpath and write?** Real and accepted in the Amendment's
  own words ("the residual TOCTOU between check and write is accepted under
  the guard's existing 'habit, not a security boundary' posture"). The write
  path is tmp+rename with an optimistic-concurrency recheck, so the losing
  side of a race fails closed with "concurrent modification detected" rather
  than silently clobbering.
- **Is the role-guard exemption a widening, and is it disclosed?** Yes and
  yes. A dispatched subagent may now write any STATE-shaped file outside
  every AAI project root (verified). It is disclosed three times — D12, R3,
  and the refusal message itself ("A scratch/mktemp --state fixture outside
  every AAI project root is unaffected"). The R3 gap (a project vendoring
  `.aai` without `scripts/state.mjs`) reproduces exactly as documented.
- **Timestamps to seconds — any downstream reader of ms?** None found: every
  EVENTS consumer parses with `Date.parse`, `metrics-flush.mjs`'s `ISO_RE`
  accepts both precisions, and `validation-waiver.mjs`'s exact-string check is
  what fixes the direction downward.
- **Is the SKILL_PR line enough until sweep 2 wires the planner?** For the PR
  lane, yes — step 4c now really runs `clear-focus` (the B2 remediation made
  the claim true) and TEST-062's grep arm pins it. For a close run OUTSIDE the
  PR ceremony, no — R2 says so, and D3 carries the exact line sweep 2 must add.
- **`select-suites` outcome:** `FULL_RUN reason=protected-l3 path=.aai/scripts/lib/state-engine.mjs`
  — consistent with ceremony 3, and it makes the stale full-sweep artifact a
  real pre-close obligation (cannot_verify).
- **Protected-surface hygiene:** one new module-level mutable (`state.mjs:190`
  `let currentCmd`), assigned once in `main()` before dispatch; `state.mjs` is
  imported by nothing (`grep -rln "from '.*state.mjs'"` over `.aai/scripts`
  and `tests/` is empty), so there is no cross-invocation reuse. Refusals are
  NOT byte-identical to pre-D16 — every refusal for a known subcommand now
  carries a `usage:` line, the R-GUARD refusal included — which is D16's
  intent and is covered by the updated pins (test_063 rguard_marker_absent_bytewise
  and the r-guard suite are green).

## Anti-gaming note (SUBAGENT_PROTOCOL review rule 1 / D11)

The dispatch text enumerated the surfaces to mutate and posed hypothesis
questions about several of them. It did NOT rank expected findings, pre-rate
severity, or exclude any area — `node .aai/scripts/check-dispatch-text.mjs
--path <the dispatch> --strict` exits 0 on it. Recorded for completeness: the
enumeration is a steer toward specific surfaces, and the one BLOCKING finding
returned here came from a named surface but not from any hypothesis the
dispatch posed. The full scope was reviewed regardless.

## Next steps (merge readiness)

1. **Fix BLOCKING-1** in `watch-ci.mjs` (one line) and add the missing
   TEST-062 arm for a `skipping` bucket. Nothing else gates the merge.
2. Apply NON-BLOCKING-7 (the two-line TEST-036 arm (e) fix) in the same round
   — it is test-only and removes a CI flake on a CORE suite.
3. Record the remaining NON-BLOCKING dispositions: three typed follow-ups
   (`fu-amend-run-overwrites-note-basis-number` P2,
   `fu-clearfocus-announces-unwritten-phase` P3,
   `fu-dispatch-text-detector-self-referential-fp` P3), two more
   (`fu-verdict-coverage-same-second-reads-true` P3,
   `fu-ledger-shrink-arm-unpinned` P3), three accepted residuals recorded in
   this report only (NON-BLOCKING-4, -11, -8), and ONE spec amendment
   paragraph covering N18/N19/N20/N21/N22/N24/N26 with its decisions.jsonl
   record.
4. Stage `docs/ai/decisions.jsonl` and `docs/ai/tests/test-runs.jsonl`
   explicitly (NON-BLOCKING-10) — the amendment record is otherwise droppable
   with every gate green.
5. Run the FULL sweep (`AAI_TEST_TIMEOUT=3000`) on the delivered tree before
   close; the recorded artifact predates the round-2/3 remediations and
   `select-suites` returns FULL_RUN.
6. Land the `merge-reconcile-t054a.md` fixture diff in the SAME merge —
   without it `test-aai-close-work-item.sh` turns main's CI red.
7. Owner sign-off is still owed on both post-freeze amendments.
8. The AC table's 21 rows are all `planned` / evidence `—`; the close ceremony
   flips them (8a). Not a review failure, but not yet the spec's own PASS
   criterion either.
