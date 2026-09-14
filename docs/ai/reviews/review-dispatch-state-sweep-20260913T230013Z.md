# Code Review — dispatch-state-sweep (wave 3, sweep 3) — ROUND 2 (final under the two-round cap)

```yaml
review:
  scope: "uncommitted worktree delta on feat/dispatch-state-sweep over main 082ad4aa (HEAD 2fb2f4cd) — 40 dirty paths; STATE code_review.scope (32 paths) + the spec's Review scope (35). Round 2 re-reviews the FULL scope, with a targeted re-derivation of the post-round-1 delta (watch-ci.mjs, test-aai-orchestration-dispatch.sh, test-aai-state.sh, the spec, decisions.jsonl, docs/INDEX.md)"
  spec: docs/specs/SPEC-DRAFT-spec-dispatch-state-sweep.md
  round: 2
  prior_report: docs/ai/reviews/review-dispatch-state-sweep-20260913T221903Z.md
  reviewer: claude-opus-5[1m] (independent of the implementer claude-sonnet-5 and of all validation rounds)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "unchanged since round 1 (state.mjs mtime 20:38 local, PRE-dating the round-1 report at 00:24 — this round touched no .mjs but watch-ci.mjs). `test-aai-state.sh` re-run by me in full: exit 0, 79 PASS" }
      - { ac: Spec-AC-02, call: compliant, citation: "unchanged; `test-aai-orchestration-dispatch.sh` re-run by me in full: exit 0, TEST-061 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "unchanged; TEST-062's clear-focus grep arm green in my own full re-run. NON-BLOCKING-1 of round 1 is now registered as fu-clearfocus-announces-unwritten-phase (P3)" }
      - { ac: Spec-AC-04, call: compliant, citation: "unchanged since round 1 (metrics-flush.mjs mtime 18:08)" }
      - { ac: Spec-AC-05, call: compliant, citation: "unchanged; wording residual carried as an accepted residual (round-1 NB-8)" }
      - { ac: Spec-AC-06, call: compliant, citation: "unchanged; the note-basis gap is now registered as fu-amend-run-overwrite-note-basis-number (P2)" }
      - { ac: Spec-AC-07, call: compliant, citation: "`grep -rln iso-time.mjs .aai/scripts` = append-event.mjs, follow-ups.mjs, spec-amend.mjs, update-check.mjs, lib/state-engine.mjs (+ the module). TEST-036 green in my full re-run; arm (e) re-engineered this round — see BLOCKING-CLOSED-2" }
      - { ac: Spec-AC-08, call: compliant, citation: "unchanged since round 1 (heartbeat.mjs mtime 18:44)" }
      - { ac: Spec-AC-09, call: compliant, citation: ".aai/scripts/watch-ci.mjs:168-171 — the bucket model now matches gh's OWN documented vocabulary verbatim; verified against `gh pr checks --help` on the installed gh (\"categorizes the `state` field into `pass`, `fail`, `pending`, `skipping`, or `cancel`\") and against a live read-only `gh pr checks 378 --json name,bucket,state` (8 pass + 1 skipping, gh exit 0). TEST-062 gains arms (e) and (f); my MUT-A and MUT-B redden exactly those two. See BLOCKING-CLOSED-1" }
      - { ac: Spec-AC-10, call: compliant, citation: "unchanged; the four D1 carve predicates re-read this round (SKILL_CODE_REVIEW:14-21, SKILL_WORKTREE:165-171, METRICS_FLUSH:45, STATE_FALLBACK:10-14) — wording reconciled, no 'explicit instruction' grant anywhere. TEST-063 green" }
      - { ac: Spec-AC-11, call: compliant, citation: "unchanged; I re-ran check-dispatch-text.mjs --strict over MY OWN round-2 dispatch text: exit 0, 'clean — no pre-rating shape found'. The self-referential false positive is registered as fu-dispatch-text-detector-self-ref-fp (P3)" }
      - { ac: Spec-AC-12, call: compliant, citation: "unchanged; state.mjs untouched this round (mtime 20:38 < the round-1 report's 00:24). t054a merge condition re-confirmed live — see 'The t054a merge condition'" }
      - { ac: Spec-AC-13, call: compliant, citation: "unchanged since round 1" }
      - { ac: Spec-AC-14, call: compliant, citation: "unchanged since round 1" }
      - { ac: Spec-AC-15, call: compliant, citation: "unchanged since round 1" }
      - { ac: Spec-AC-16, call: compliant, citation: "unchanged; TEST-065 green in my full re-run" }
      - { ac: Spec-AC-17, call: compliant, citation: "unchanged; the shrink-arm test gap is registered as fu-ledger-shrink-arm-unpinned (P3)" }
      - { ac: Spec-AC-18, call: compliant, citation: "unchanged; I re-ran `state.mjs --help` and the two NEW subcommands' help this round: `clear-focus --ref <value> [--state <path>] [--ticks <path>]` and `amend-run --ref --role <8 enum values> --started --tokens-total [...]`, both exit 0. TEST-038 green" }
      - { ac: Spec-AC-19, call: compliant, citation: "unchanged; the >= boundary is registered as fu-verdict-coverage-same-second-true (P3)" }
      - { ac: Spec-AC-20, call: compliant, citation: "unchanged since round 1" }
      - { ac: Spec-AC-21, call: compliant, citation: "unchanged; want_growth pin 28140 at tests/skills/test-aai-prompt-diet.sh:800 re-read this round" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/watch-ci.mjs, line: 168,
          issue: "the bucket model is a CLOSED set with no `else` — a check whose bucket is outside gh's five (a future gh value, or a `bucket` key absent from the object) belongs to none of pending/failed/passed/skipped and is silently absorbed into the settled-pass path, exit 0",
          failure_scenario: "Probed live against a stub gh: `[{name:build,bucket:pass},{name:weird,bucket:neutral}]` -> exit 0 printing `settled — all 2 check(s) passed (1 pass, 0 skipped)` — the arithmetic in the file's own settlement line (1+0 != 2) is the only trace, and nothing reads it. `[{name:a},{name:b,bucket:pass}]` (bucket key missing) behaves identically. This is the exact polarity the file's own header forbids ('alive, failed and I could not tell must never render as the same answer'), and it is a REGRESSION IN DIRECTION from the pre-fix model, which classified an unknown bucket as pending and therefore fail-CLOSED. NOT REACHABLE TODAY: `gh pr checks --help` on the installed gh documents exactly the five buckets the code handles, a gh too old to know `--json bucket` errors out (verified path: non-JSON -> degrade 3), and the live PR #378 read settles correctly. Recommended disposition: remediate-in-tree, one line — `const unknown = checks.filter((c) => !['pass','fail','pending','skipping','cancel'].includes(c.bucket)); if (unknown.length) degrade(...)` — or typed follow-up (P2) fu-watch-ci-unknown-bucket-passes." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-orchestration-dispatch.sh, line: 4462,
          issue: "TEST-062 does not pin either of watch-ci's two fail-closed guards: the all-`skipping` 'nothing ran' degrade, and the empty-checks-array continue (which is validation-round1 N1's OWN fix for the D8-forbidden shape)",
          failure_scenario: "Two mutations of mine, each on a scratch copy, single test run, restored byte-identical: MUT-C (`if (passed.length === 0)` -> `if (false)`, so an all-skipping PR exits 0 'settled') leaves test_062 GREEN; MUT-D (`if (checks.length === 0)` -> `if (false)`, so a PR with zero checks renders as a settled pass) also leaves test_062 GREEN. Both guards carry multi-line comments in watch-ci.mjs explaining that they exist precisely to stop 'an array of nothing meaningful rendering as a pass' — and both are unfalsifiable by the suite that claims to cover Spec-AC-09. Contrast MUT-A (revert the skipping fix) and MUT-B (drop `cancel` from failed), which redden arms (e) and (f) deterministically. Recommended disposition: typed follow-up (P3) fu-watch-ci-degrade-arms-unpinned, or two more stub-gh arms (empty array and all-skipping) in the same round." }
      - { rank: NON-BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 1619,
          issue: "B6/N19 corrects this comment BY DISCLOSURE in the spec, but the false comment itself stays in the shipped code of an in-scope file",
          failure_scenario: "`orchestration-dispatch.mjs:1619-1620` still reads 'Both timestamps are ISO 8601 UTC strings, but at DIFFERENT precision BY DESIGN ... append-event.mjs's auto-filled `ts` keeps milliseconds while state-engine.mjs's nowIso() truncates to the second.' D7 removed that asymmetry in THIS ride: append-event.mjs now imports lib/iso-time.mjs and the live EVENTS tail is second-precision. A maintainer reading the file (not the spec Amendment) is told the opposite of the shipped tree, in the very comment that justifies the comparison logic. The spec Amendment is the right place to DISCLOSE a stale frozen row; it is not a fix for a lying comment in a file this ride already edits. Recommended disposition: remediate-in-tree, two lines (correct the comment; the comparison logic is unaffected and correct under either precision) — or typed follow-up (P3) fu-dispatch-comment-claims-ms-asymmetry." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-dispatch-state-sweep.md, line: 45,
          issue: "the new 'Expected companions' paragraph — added this round to close round-1 NB-10 — itself carries a false count, and B6's closing sentence is in tension with the additive convention B6 states",
          failure_scenario: "The paragraph says `docs/ai/decisions.jsonl` 'carries BOTH of this spec's post-freeze spec_amendment records'. There are THREE (ts 2026-09-13T18:37:32Z, 21:16:41Z, 22:41:17Z), the third being B6's own record, appended in the same minute the sentence was written. Separately, the Amendment's closing line 'Every claim above was grepped or run TRUE against the shipped tree' still stands above B5 text that B6 itself declares stale (the '~60ms / two independent processes' arm-(e) description and Seam S8's consumer list, both corrected by disclosure rather than in place) — the sentence and the convention cannot both be read literally. Same class as the seven findings B6 exists to correct. Recommended disposition: (d) accepted residual, or fold into the close-ceremony pass — P3 prose, no behavioural claim depends on either." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-dispatch-state-sweep.md, line: 837,
          issue: "M17's claim that the mutation reddens arm (e) is true of the ARM but not observable from a suite run — arm (b) fires first and short-circuits the test",
          failure_scenario: "I applied M17 (drop the `.replace(/\\.\\d+Z$/, 'Z')` from lib/iso-time.mjs) and ran `bash tests/skills/test-aai-state.sh test_070_one_clock_iso_time`: it reddens at `FAIL: append-event.mjs ts must be second-precision (got: 2026-09-13T22:57:33.572Z)` — arm (b), never reaching arm (e). Arm (e) IS a genuine direction pin (isolated: 30/30 DIFFERENT under a millisecond nowIso, 0/30 under the shipped one), but the mutation-table row credits an arm the mutation never reaches in situ. Recommended disposition: (d) accepted residual — the direction property holds and I measured it directly; only the row's attribution is imprecise. P3." }
      - { rank: NON-BLOCKING, file: .aai/scripts/state.mjs, line: 1360,
          issue: "CARRIED from round 1, now registered — amend-run's 'never rewrites a number' guard tests only the tokens_total FIELD, so a note-basis number is silently overridden",
          failure_scenario: "Unchanged; the file was not touched this round. Registered as fu-amend-run-overwrite-note-basis-number (P2, 40 chars), text verified faithful to the round-1 finding." }
      - { rank: NON-BLOCKING, file: .aai/scripts/state.mjs, line: 515,
          issue: "CARRIED and ACCEPTED from round 1 — realpathDirTarget resolves the containing directory only, so a symlinked LEAF is judged by neither arm",
          failure_scenario: "Unchanged; proved harmless in round 1 (tmp+rename replaces the link, real STATE md5 unmoved). Accepted residual, no registry entry needed. The related PRE-EXISTING main-guard class (round-1 N27 / validator N27) turns out to be ALREADY OPEN in the registry as `fu-ismain-symlink-realpath` (P2, ref suites-run-in-a-disposable-worktree, filed 2026-08-20) — no new filing is owed." }
      - { rank: NON-BLOCKING, file: .aai/SKILL_CODE_REVIEW.prompt.md, line: 84,
          issue: "CARRIED and ACCEPTED from round 1 — Spec-AC-05's 'exactly one stderr line' is literally violated when the token flags are also absent",
          failure_scenario: "Unchanged. P3 wording, no behavioural defect, no false record." }
  cannot_verify:
    - { claim: "watch-ci.mjs settles correctly against a real, still-running GitHub PR",
        closes_with: "one live run against an open PR. I closed the round-1 half of this: `gh pr checks 378 --json name,bucket,state` (read-only, merged PR) returns 8 `pass` + 1 `skipping` at gh exit 0, and the shipped code settles that exact shape to exit 0 in a direct run. What remains unobserved is the POLLING loop against checks that actually transition pending -> settled over time" }
    - { claim: "the delivered tree passes a FULL suite sweep",
        closes_with: "`AAI_TEST_TIMEOUT=3000` full sweep by the orchestrator before close. `select-suites.mjs --files-from <dirty>` still returns `FULL_RUN reason=protected-l3 path=.aai/scripts/lib/state-engine.mjs`. I re-ran three suites end to end myself this round on a scratch copy: test-aai-orchestration-dispatch.sh exit 0 (all PASS), test-aai-state.sh exit 0 (79 PASS), test-aai-close-work-item.sh exit 1 with exactly one FAIL (t054a) and 52 PASS" }
    - { claim: "the t054a reconcile diff still applies to sweep 2's own uncommitted copy of new_fixture_repo()",
        closes_with: "reading sweep 2's worktree at merge time. Re-confirmed from here: the failure is byte-for-byte the one merge-reconcile-t054a.md describes (`FAIL: t054a: STATE.yaml must stay byte-identical under AAI_ROLE=subagent`), unchanged by this round" }
    - { claim: "TEST-036 arm (e)'s flake rate on CI hardware",
        closes_with: "a CI run. On this machine the new three-sample arm measured 0 false reds in 250 runs across five injected-stall levels (0/100/500/930/1500 ms, 50 each) — see BLOCKING-CLOSED-2" }
    - { claim: "downstream consumer impact of the D1 set-focus semantics change after /aai-update",
        closes_with: "running a vendored downstream project; unchanged from round 1, bounded the same way" }
    - { claim: "close-work-item.mjs calls clear-focus (seam S7 / R2)",
        closes_with: "sweep 2 landing the one line D3 writes out; SKILL_PR step 4c covers the PR lane only" }
    - { claim: "owner sign-off on the THREE post-freeze amendments",
        closes_with: "the owner signing; all three decisions.jsonl records carry owner_signoff false, tracked by fu-amend-spec-dispatch-state-sweep" }
  overall: pass
```

## Scope and method

Round 2 re-walked the whole uncommitted delta (40 dirty paths) against the
FROZEN spec and its Amendment (B1-B6), with the eight questions of the
round-2 dispatch driving the depth. Nothing was run against the shipping
worktree that writes: every probe, mutation and suite ran on an `rsync` copy
at `<scratch>/copy` with its own throwaway git repo. The real worktree's
`git status --porcelain` was captured before the first command and diffed
after the last — **identical**; `docs/ai/STATE.yaml` md5 `572abcaa…` before
and after. No tracked file was mutated, no page regenerated, no
`git checkout --` needed. The only file this role writes is this report.

Post-round-1 delta, established by mtime against the round-1 report (00:24
local): `test-aai-orchestration-dispatch.sh` (00:28), `watch-ci.mjs` (00:30),
`test-aai-state.sh` (00:31), the spec (00:40), `decisions.jsonl` (00:41),
`docs/INDEX.md` (00:46, regenerated). Everything else — **`state.mjs`
(20:38), `lib/state-engine.mjs` (17:09), `metrics-flush.mjs` (18:08),
`heartbeat.mjs` (18:44)** — predates the round-1 report. **The protected
surface was not touched this round**, and the single-writer path is
unchanged.

## BLOCKING-CLOSED-1 — watch-ci's bucket model, at cause

Round 1's single BLOCKING finding was that `skipping` — a bucket `gh` itself
treats as terminal — was counted as PENDING, so a PR carrying any skipped
check polled to `--max-wait-seconds` (default 3600) and degraded on a PR
whose checks had all passed. It is fixed at cause, not at symptom:

```
const pending = checks.filter((c) => c.bucket === 'pending');
const failed  = checks.filter((c) => c.bucket === 'fail' || c.bucket === 'cancel');
const passed  = checks.filter((c) => c.bucket === 'pass');
const skipped = checks.filter((c) => c.bucket === 'skipping');
```

**Against gh's real vocabulary.** `gh pr checks --help` on the installed
binary states it verbatim: *"it includes a `bucket` field, which categorizes
the `state` field into `pass`, `fail`, `pending`, `skipping`, or `cancel`."*
All five are now modeled, each on the side gh puts it. One live read-only
call (`gh pr checks 378 --json name,bucket,state` on the merged PR whose
shape produced the round-1 finding) returns 8 `pass` + 1 `skipping` at gh
exit 0; the shipped code settles that exact array to **exit 0** in a direct
run.

**Mutations (four, each on the scratch copy, single `test_062` run,
restored byte-identical).**

| # | Mutation | Result |
|---|----------|--------|
| MUT-A | revert `pending` to include `skipping` | **RED** — `FAIL: TEST-062: (e) pass+skipping must settle exit 0 within one poll, got 3` |
| MUT-B | drop `cancel` from `failed` | **RED** — `FAIL: TEST-062: (f) a cancelled check must exit 5, got 0` |
| MUT-C | drop the all-skipping "nothing ran" degrade | **GREEN — unpinned (NON-BLOCKING-2)** |
| MUT-D | render an empty checks array as a settled pass | **GREEN — unpinned (NON-BLOCKING-2)** |

MUT-A is the decisive one: the fix is not merely present, it is *pinned* by
an arm that fails without it.

**Adversarial probes (eight, stub `gh`, direct runs).**

| Shape | Result | Right? |
|---|---|---|
| real PR-378 shape (pass x2 + skipping) | exit 0, `settled — all 3 check(s) passed (2 pass, 1 skipped)` | yes |
| all `skipping`, no pass | exit 3, `all 2 check(s) settled without a single pass — nothing ran (a, b)` | yes |
| non-JSON warning line before the JSON | exit 3, `returned non-JSON output (exit 0): Warning: …` | yes — fails closed |
| zero checks configured (`[]`, gh exit 0) | polls, then exit 3 `no checks reported after 2s` | yes |
| rate limit (gh exit 1, `HTTP 403: API rate limit exceeded` on stderr) | exit 3 naming the 403 | yes |
| check name with an embedded `\n` | exit 5, names the failing check | yes |
| check name with a `\|` | exit 5, `FAILED — a\|b` | yes |
| unknown bucket (`neutral`) / missing `bucket` key | **exit 0, counted as settled-pass** | **no — NON-BLOCKING-1** |

The name-with-newline / name-with-pipe shapes are harmless: `summary` is only
a change-detector (a `,`-joined `name:bucket` string compared to the previous
poll), never parsed back, so a name carrying a separator can at worst suppress
or duplicate one transition LINE — never an exit code. The transition line is
advisory output; the verdict is computed from the arrays.

The one real residual is the closed set with no `else` — see NON-BLOCKING-1.
It is latent, not reachable with `gh` as it exists today, and it is the
*direction* that makes it worth naming: the pre-fix model classified an
unknown bucket as pending and failed CLOSED; the new one fails OPEN.

## BLOCKING-CLOSED-2 — N23 / round-1 NB-7, TEST-036 arm (e)

The arm now samples **three** real `nowIso()` calls 20 ms apart (after the
round-2 wall-clock alignment) and requires only one ADJACENT pair to agree.
That is the right shape: a false red now needs TWO second boundaries inside
the sampling window, i.e. a stall long enough to cross a boundary AND an
unlucky ~2% landing phase for the surviving gap — where the two-sample arm
false-red on a single boundary crossing.

Measured on this machine, 50 runs per level, the arm's own probe extracted
verbatim:

| injected stall between a and b | SAME (pass) | DIFFERENT (false red) |
|---|---|---|
| 0 ms | 50 | 0 |
| 100 ms | 50 | 0 |
| 500 ms | 50 | 0 |
| 930 ms | 50 | 0 |
| 1500 ms | 50 | 0 |

Round 3 measured 12% / 44% / 76% at 100 / 500 / 930 ms on the two-sample arm.
**250 runs, zero false reds.**

**Does it keep M17 reddening?** Yes, and deterministically: under a
millisecond `nowIso` every call differs by real elapsed time regardless of
where in the second it lands, so no pair is ever equal — **30/30 DIFFERENT**
against a millisecond module, **0/30** against the shipped one. The
sensitivity the fix buys is not paid for in the mutation's detection.
(Caveat: in a full `test_070` run the M17 mutation reddens at arm (b) first
and never reaches arm (e) — NON-BLOCKING-5. The property is real; the
mutation-table attribution is imprecise.)

## Amendment B6 — every sub-claim checked

All seven re-derived against the shipped tree, independently of the
Amendment's own wording:

| Sub-claim | Verdict | Evidence |
|---|---|---|
| **N18** M40's row misdescribes the recorded mutation | **TRUE** | `:860` says "Bump the corpus by one byte without crediting it"; `mutation-M40.txt` records bumping the LEDGER ENTRY's claimed count 1226 -> 1227 against an unmoved `want_growth`, observing `JUSTIFIED_GROWTH_BYTES=27958 (want 27957)`. Two different mutations. |
| **N19** Seam S8 names two non-consumers | **TRUE**, and B6's replacement list is exact | `grep -rln iso-time.mjs .aai/scripts` = append-event, follow-ups, spec-amend, update-check, lib/state-engine (+ the module). `metrics-flush.mjs:1251` computes its own `nowIsoStr`; `orchestration-dispatch.mjs` contains exactly ONE occurrence of the string `nowIso`, inside the comment N20 is about — no definition, no import. |
| **N20** the dispatch comment describes a removed asymmetry | **TRUE** | `orchestration-dispatch.mjs:1619-1620` still reads "at DIFFERENT precision BY DESIGN … append-event.mjs's auto-filled `ts` keeps milliseconds". It does not. *But see NON-BLOCKING-3: disclosed in the spec, still false in the code.* |
| **N21** measurements.txt pins the stale 27957 | **TRUE** | `measurements.txt:43` says 27957; `test-aai-prompt-diet.sh:800` is `local want_growth=28140`. |
| **N22** `diff_range:` holds prose | **TRUE** | e.g. `diff_range: heartbeat.mjs D13 (writer_pid replaces pid; …)` — a description, not a range. |
| **N24** the two scope lists are a strict superset, not identical | **TRUE**, and the delta is exactly the three named paths | Computed: spec 35 entries, STATE 32; `spec \ STATE` = the spec's own file, `CHANGE-DRAFT-dispatch-state-sweep.md`, `ISSUE-0040-…md`; `STATE \ spec` = **empty**. |
| **N26** M17/B5 describe arm (e) as two processes ~60 ms apart | **TRUE** | `:837` still says "two REAL, independently-timed `nowIso()` calls ~60ms apart"; the shipped arm is one process, `GAP_MS = 20`, three calls. B6's own parenthetical ("three calls 20ms apart, not two") is accurate. |

**Round-1 NB-10 is properly closed.** The new "Expected companions"
paragraph sits INSIDE the `## Isolation and review` section — the exact
section `SKILL_PR.prompt.md` step 1 is told to read when deriving the
in-scope list — and it names precisely the two paths the ceremony would
otherwise drop. I checked the complement: SKILL_PR step 3's own
expected-companion list already covers `docs/INDEX.md`,
`docs/INDEX.violations.md`, the `docs/ai/reviews/` report, `CHANGELOG.md`,
`METRICS.jsonl` and `EVENTS.jsonl`, and step 1b adds
`docs/ai/overview.html` + `overview-data.json` by name. `decisions.jsonl` and
`test-runs.jsonl` were the only two uncovered, and they are now covered.

## The five follow-ups

All registered in `docs/ai/decisions.jsonl`, all ids within the 40-character
budget, all texts faithful to the round-1 findings (I diffed each `finding` /
`decision` against my own report):

| id | len | sev | text true? |
|---|---|---|---|
| `fu-amend-run-overwrite-note-basis-number` | 40 | P2 | yes — reproduces the live probe verbatim |
| `fu-clearfocus-announces-unwritten-phase` | 39 | P3 | yes |
| `fu-dispatch-text-detector-self-ref-fp` | 37 | P3 | yes — quotes the three real lines |
| `fu-verdict-coverage-same-second-true` | 36 | P3 | yes — carries MUT-7 and the 12:00:00.900 / .100 example |
| `fu-ledger-shrink-arm-unpinned` | 29 | P3 | yes — carries MUT-10 |

`docs/ai/decisions.jsonl` is still append-only clean: 828 committed lines are
a byte-exact prefix of the 855 in the worktree, 0 removed.

Round-1 N27 needed no filing after all: the class is **already open** as
`fu-ismain-symlink-realpath` (P2, ref `suites-run-in-a-disposable-worktree`,
filed 2026-08-20) — "every .mjs CLI guards main() with
`path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)`, which is
FALSE whenever the checkout is reached through a symlink".

## Scope discipline

Dirty-but-out-of-scope, computed mechanically (`git status` vs STATE's 32):
`docs/INDEX.md`, `docs/ai/EVENTS.jsonl`, `docs/ai/decisions.jsonl`,
`docs/ai/overview-data.json`, `docs/ai/overview.html`,
`docs/ai/tests/test-runs.jsonl`, the spec, and the two review reports. Every
one of those is either in the spec's 35-path list (the spec itself), an
auto-staged pre-commit companion, an allocator output named by step 1b, or
a newly-named expected companion. **The remediation introduced no new
out-of-scope path**, and it touched nothing outside the five files the
dispatch named plus the regenerated `docs/INDEX.md`.

## Consumer impact for the CHANGELOG (the orchestrator writes it)

`CHANGELOG.md` is currently clean — no `[unreleased]` entry for this ride
exists yet. Everything below is a behaviour change a downstream project
inherits at `/aai-update`; each is disclosed somewhere in the spec, but the
CHANGELOG is where a consumer meets it.

1. **`state.mjs` gains two subcommands.** `clear-focus --ref <slug>` nulls
   `current_focus` and marks the focused work item terminal;
   `amend-run --ref --role --started --tokens-total` fills a missing usage
   number on an already-appended run. Both are additive — no existing
   invocation changes.
2. **`set-focus` semantics change (the one real behaviour break).**
   Retargeting to a new ref now clears `spec_path` unconditionally instead of
   only when the focus type was `none`. A caller that relied on `set-focus`
   preserving the previous scope's `spec_path` must now pass it explicitly via
   `set-phase --spec-path`. In-repo this fails CLOSED (rule 5 re-plans), and
   `ORCHESTRATION_PARALLEL.prompt.md:127` omits `--spec-path` on both calls —
   a downstream fork with its own orchestration prompts should be told.
3. **The role guard is WIDENED, not only narrowed.** Under `AAI_ROLE` set
   (a dispatched subagent), `state.mjs` previously refused EVERY `--state`
   path; it now refuses only (A) a path inside the running script's own repo
   root or (B) a `.../docs/ai/STATE.yaml` with a sibling
   `.aai/scripts/state.mjs`. A subagent may therefore now write a
   STATE-shaped file outside every AAI project root. That is the point (it
   unblocks a role's own fixtures), it is disclosed three times (D12, R3, and
   the refusal message itself), and the narrowing is what forces the t054a
   merge condition below — but a CHANGELOG that only says "the guard was
   fixed" understates it. Say: *narrowed to ask WHICH file, which permits a
   scratch fixture a dispatched role writes.*
4. **Timestamps drop to second precision.** `EVENTS.jsonl` `ts` and every
   STATE instant now come from one module (`lib/iso-time.mjs`). Any
   downstream consumer that sorts EVENTS by string within a single second, or
   that string-matches a millisecond form, changes behaviour. In-repo no such
   consumer exists (`Date.parse` everywhere, `ISO_RE` accepts both).
5. **Two new CLIs.** `node .aai/scripts/watch-ci.mjs` (exit 0 settled-pass /
   5 a check failed / 3 could-not-tell / 2 usage) is wired into
   `SKILL_PR.prompt.md`'s post-push step; `node .aai/scripts/check-dispatch-text.mjs`
   is advisory by default and exits 6 under `--strict`. Neither runs
   automatically on any existing path.
6. **`--help` grammar on `state.mjs`.** All 13 `CMD_FLAGS` subcommands now
   answer `--help` (exit 0) with the flag list and rendered enums, and every
   refusal for a known subcommand now carries the same `usage:` line — so
   refusal stderr is **no longer byte-identical to pre-D16** for anything
   parsing it.
7. `metrics-flush.mjs` partial reset no longer writes
   `code_review.required: false`; the flush ledger gains
   `verdict_after_last_implementer`; the `git restore` advice is gone.

Suggested entry title, in the house voice:
`## [unreleased] — fix(state): focus and validation state stop going stale silently, and the CI watch is a command rather than a habit`

## select-suites, the full sweep, and t054a

- `select-suites.mjs --files-from <dirty>` returns
  **`FULL_RUN reason=protected-l3 path=.aai/scripts/lib/state-engine.mjs`** —
  unchanged from round 1. The recorded sweep artifact still predates the
  remediation rounds, so a fresh full sweep with `AAI_TEST_TIMEOUT=3000`
  remains owed before close. I re-ran the two changed suites end to end
  myself: `test-aai-orchestration-dispatch.sh` exit 0 (all PASS, TEST-062
  included), `test-aai-state.sh` exit 0 (79 PASS, TEST-036 included).
- **t054a merge condition stands, unchanged and verified this round.**
  `test-aai-close-work-item.sh` on this branch is exit 1 with exactly ONE
  FAIL — `FAIL: t054a: STATE.yaml must stay byte-identical under
  AAI_ROLE=subagent` — and 52 PASS. `merge-reconcile-t054a.md`'s one-line
  fixture change (give `new_fixture_repo()` a sibling
  `.aai/scripts/state.mjs`) is the documented resolution and **must land in
  the same merge**, or main's CI turns red on a test neither sweep broke
  alone.

## Anti-gaming note (SUBAGENT_PROTOCOL review rule 1 / D11)

The round-2 dispatch enumerated eight review questions and named specific
surfaces and adversarial shapes to try. It did NOT rank expected findings,
pre-rate severity, or exclude any area; it explicitly asked for at least four
mutations "of your own", which is a demand for independent work rather than a
steer to a conclusion. `node .aai/scripts/check-dispatch-text.mjs --path <the
dispatch> --strict` exits 0 on it: *"clean — no pre-rating shape found"*.
Recorded for completeness: two of the five NON-BLOCKING findings returned
here (the unknown-bucket else, and the two unpinned degrade arms) came from
adversarial shapes the dispatch did not name.

## Next steps (merge readiness)

1. **Nothing gates the merge on code quality.** BLOCKING-1 is closed at
   cause and pinned; both verdicts are PASS.
2. Two of the five NON-BLOCKING findings are cheap, in-scope, one-to-two-line
   fixes the orchestrator may take now or file: the `watch-ci` unknown-bucket
   `else` (NON-BLOCKING-1) and the false `orchestration-dispatch.mjs:1619`
   comment (NON-BLOCKING-3). The other three are P3 prose/test-strength and
   should be filed, not fixed: `fu-watch-ci-degrade-arms-unpinned`,
   plus the two spec-prose residuals recorded here only.
3. Run the FULL sweep (`AAI_TEST_TIMEOUT=3000`) on the delivered tree before
   close; `select-suites` returns FULL_RUN and the recorded artifact is stale.
4. Land `merge-reconcile-t054a.md`'s fixture diff in the SAME merge.
5. Stage `docs/ai/decisions.jsonl` and `docs/ai/tests/test-runs.jsonl` (the
   spec now names them; SKILL_PR step 3's own list does not).
6. Write the CHANGELOG entry from the consumer-impact section above — item 2
   (`set-focus` semantics) and item 3 (the guard WIDENING) are the two a
   downstream reader must not miss.
7. Owner sign-off is owed on **three** post-freeze amendment records, not two.
8. The AC table's 21 rows are still `planned` / evidence `—`; the close
   ceremony flips them (8a).
