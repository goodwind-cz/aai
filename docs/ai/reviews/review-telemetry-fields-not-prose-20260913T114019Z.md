# Code Review — telemetry-fields-not-prose (dual verdict, ceremony 3, ROUND 2 / final)

```yaml
review:
  round: 2
  scope: >-
    working tree of /Users/ales/Projects/aai-fix-telemetry-fields-not-prose
    (branch fix/telemetry-fields-not-prose @ 5f650095, uncommitted); `git diff`
    over the 25 STATE-declared review paths plus the spec, focused on the
    remediation-3 delta against my round-1 report
    docs/ai/reviews/review-telemetry-fields-not-prose-20260913T105322Z.md
  spec: docs/specs/SPEC-0178-spec-telemetry-fields-not-prose.md (FROZEN, 14 Spec-AC, two ## Amendment sections)
  reviewer: claude-opus-5 (independent of implementer claude-sonnet-5 and of the validator)
  spec_compliance:
    verdict: pass
    basis: >-
      all 14 Spec-AC remain compliant (round-1 AC walk unchanged and re-verified
      by suite re-run); Spec-AC-06 gained the corroboration requirement, TEST-144
      and mutation M26 are in the spec's test/mutation tables, and both round-3
      errata (M9 cell TEST-135 -> TEST-136; seven-vs-eleven suite count) are fixed
      in the frozen text under a disclosed `## Amendment`.
    deviations:
      - id: D-4
        issue: >-
          Two test ids that SHIP are absent from the frozen spec's Test-plan table:
          TEST-145 (tests/skills/test-aai-metrics.sh test_145_field_note_disagreement,
          the NON-BLOCKING-B guard) and TEST-031 (tests/skills/test-aai-state.sh
          test_069_scope_ref_id_lifecycle, the NON-BLOCKING-A guard). `grep -c
          TEST-145 <spec>` = 0, `grep -c TEST-031 <spec>` = 0. The
          `docs/ai/decisions.jsonl` spec_amendment at 2026-09-13T11:05:33Z names
          only TEST-144 + M26. See NON-BLOCKING-2.
      - id: D-3
        issue: >-
          (carried, unchanged) `.aai/STATE_FALLBACK.md` still documents the
          hand-append fallback without the five fields; degrades honestly. INFO.
  code_quality:
    verdict: pass
    blocking_closed:
      - id: BLOCKING-1
        status: CLOSED AT CAUSE
        evidence: >-
          `eventContradictedByNewerFail` (metrics-flush.mjs:383-406) corroborates
          a source-3 pass event against (i) the D7 per-ref field, (ii)
          last_validation when it names the ref, (iii) any Validation agent_run's
          verdict field, falling back to the note marker; a missing/unparseable
          timestamp counts as newer (fail-closed). My round-1 reproduction fixture
          now SKIPS with a named reason and zero ledger bytes; the positive
          control (stranded ref, pass event, no contradicting fail) still flushes
          with basis event. Mutation M26 (corroboration -> hardcoded false)
          reddens TEST-144, run by me.
    findings:
      - rank: NON-BLOCKING
        id: 1
        file: .aai/scripts/metrics-flush.mjs
        line: 383
        issue: >-
          The BLOCKING-1 guard is proven only AS A WHOLE. Each of its three
          corroboration arms can be deleted independently with the owning tests
          still green, because TEST-144's fixture carries all three fail signals
          at once. The arm that matters most in production — (iii)'s note-marker
          fallback, the ONLY signal that protects a LEGACY stranded ref (pre-scope
          STATE has no per-ref `validation:` block, and `last_validation` names
          only the current focus) — is the least guarded of the three.
        failure_scenario: >-
          MX-A (delete the runs loop), MX-B (delete the last_validation arm) and
          MX-C (delete the per-ref-field arm) each leave TEST-144 AND TEST-139
          GREEN. My probe p1 confirms arm (iii) is load-bearing in production: a
          fixture with a pass event, last_validation naming a DIFFERENT ref, no
          per-ref field, and one legacy Validation run whose only fail signal is
          the `VERDICT: FAIL` note is correctly SKIPPED today — and would flush a
          false PASS with MX-A applied.
      - rank: NON-BLOCKING
        id: 2
        file: docs/specs/SPEC-0178-spec-telemetry-fields-not-prose.md
        line: 646
        issue: >-
          Two shipped test ids (TEST-145, TEST-031) are missing from the frozen
          spec's Test-plan table, and the 11:05:33Z spec_amendment record
          discloses only TEST-144 + M26. This is the SECOND occurrence in this
          ride of "the record and the tree disagree" — round-2's BLOCKING-1 was
          its mirror image (a decisions record claiming spec edits that had not
          landed). Deliberate or not, it is the exact defect class this ride
          exists to eliminate.
        failure_scenario: >-
          A reader auditing the frozen spec's coverage sees 15 tests where 17
          ship; the two guards that close review findings A/B are invisible to
          anyone who does not read the diff. No AC is left uncovered, and
          `check-test-registration.mjs` is rc 0 (both functions ARE wired into
          their suites' main()), so nothing is silently dead — the gap is
          disclosure only.
      - rank: NON-BLOCKING
        id: 3
        file: .aai/scripts/metrics-flush.mjs
        line: 385
        issue: >-
          `isNewer` is the one FAIL-OPEN spot in a deliberately fail-closed guard:
          it uses a STRICT `ms > eventMs`, while the repo's two clocks disagree in
          precision — `append-event` writes millisecond `ts`, `state.mjs`'s
          `nowIso()` truncates to the second. A fail recorded at the same second
          as the event, or at a second-truncated time inside the event's second,
          is therefore read as OLDER than the event and ignored.
        failure_scenario: >-
          Measured, real scripts, no mutation. p3b (event ts 2026-07-01T10:00:00Z,
          per-ref field fail at the same instant) -> `Flushed: CHANGE-0001`,
          ledger `verdict PASS / verdict_basis event`. p2b (event ts
          ...T10:00:00.750Z, per-ref field fail stamped by nowIso as ...T10:00:00Z
          — i.e. genuinely LATER in wall time) -> same false PASS. Control p3c
          (fail one second later) correctly SKIPS. Not reachable in the canonical
          ordering (the pass event is stamped at a validation round that ALREADY
          passed; a later fail is minutes or hours away), which is why this is not
          BLOCKING. One-line close: compare at second granularity and use `>=`, so
          a tie counts as newer.
      - rank: NON-BLOCKING
        id: 4
        file: .aai/scripts/metrics-flush.mjs
        line: 397
        issue: >-
          Arm (iii) mirrors reliabilityOf's field-first rule, so a Validation run
          recorded as `verdict: none` MASKS its own `VERDICT: FAIL` note for the
          corroboration gate. `none` is a legal value of the enum this scope adds
          and is what a Validation role passes when it declines to state one.
          Field-first is right for reliability COUNTS; it is the wrong default for
          a gate whose whole job is to refuse to manufacture a PASS.
        failure_scenario: >-
          Probe p4: one Validation run with `verdict: none` and note
          "VERDICT: FAIL ...", last_validation naming a different ref, no per-ref
          field, an older pass event -> FLUSHED, `verdict PASS`. Suggested rule
          for the gate only: treat `verdict !== 'pass'` PLUS a fail note as a
          contradiction (reliability counts stay field-first and unchanged).
      - rank: NON-BLOCKING
        id: 5
        file: .aai/scripts/metrics-flush.mjs
        line: 593
        issue: >-
          The pre-scope INFO line "undecomposed total <N> observed; cost
          unattributable by design" is now printed on the SAME run for which D5
          derives and writes a blended cost. The spec deliberately leaves this
          block byte-unchanged for golden stability, but the sentence has become
          false: the cost IS attributed, as a labelled estimate.
        failure_scenario: >-
          Legacy-consumer probe: two runs on claude-sonnet-5 with
          usage_total_tokens notes -> output carries "cost unattributable by
          design" for both while the ledger line carries cost_usd 1.08 / 4.50,
          `cost_basis: total-blended`, `totals.total_cost_usd: 5.58`. An operator
          reading the flush output and an operator reading the ledger reach
          opposite conclusions about the same run.
      - rank: NON-BLOCKING
        id: 6
        file: .aai/system/FRICTION_PROTOCOL.md
        line: 161
        issue: >-
          (Round-1 finding E, PARTIALLY closed.) The D6 key ROWS are now pinned to
          `aai-friction.mjs`'s `persisted{}` set — MX-I (delete the `harness` row)
          reddens friction TEST-001. The COUNT WORDS in the same section are still
          unguarded prose.
        failure_scenario: >-
          MX-J ("EXACTLY these nine keys" -> "eight", table untouched) leaves the
          friction suite's TEST-001 GREEN. Cheap close: derive the count from the
          table's row count in the same assertion.
  cannot_verify:
    - claim: "Spec-AC-14 for the ride's own production flush"
      closes_with: "the close-ceremony flush against the live docs/ai/METRICS.jsonl (only fixtures and scratch copies were exercised)"
    - claim: "the full 92-suite sweep"
      closes_with: "one FULL_RUN with AAI_TEST_TIMEOUT=3000 before close — `select-suites.mjs --files-from <diff>` re-run by me returns `FULL_RUN reason=protected-l3 path=.aai/scripts/state.mjs`; `sweep-<ts>.txt` still does not exist"
    - claim: "tests/skills/test-aai-friction.sh TEST-013 and test-aai-feedback-upsert.sh TEST-009 on a full tree"
      closes_with: "the sweep in the worktree — both need `.git`, which my rsync copy excludes; every scope-relevant test in those suites (TEST-001, TEST-002, TEST-113, TEST-064) was run selectively and is green"
    - claim: "Windows/PowerShell legs and CI-only behaviour of the new suites"
      closes_with: "the GitHub Actions run on the PR"
    - claim: "the live GitHub publish path of aai-feedback-upsert"
      closes_with: "a --publish --confirm dry run; only prepare-only was exercised"
    - claim: "downstream projects whose role prompts are NOT the vendored .aai copies"
      closes_with: "a consumer survey; every vendored caller is fixed and all of ROLE_COMMON.md, SUBAGENT_PROTOCOL.md, PRICING.yaml, lib/harness.mjs and lib/pricing.mjs are in PROFILES.yaml `core`, so /aai-update ships the refusing CLI and the prose that satisfies it in one step"
  overall: pass
```

## 1. How this round was run

Every probe, suite run and mutation below ran on an `rsync` copy of the worktree
under the session scratchpad (`cr2`, `.git` excluded). Each mutation used a
single-occurrence anchor check and was reverted by `cmp`-verified byte
comparison against the shipping worktree. **I wrote nothing to the shipping
worktree except this report** — `.aai/scripts/metrics-flush.mjs`,
`.aai/scripts/state.mjs` and `.aai/system/FRICTION_PROTOCOL.md` were re-verified
byte-identical to the worktree at the end of the mutation pass.

Anti-gaming note: the dispatch named four hypotheses to test against the new
guard (ref spelling/case, `verdict: none`, a `last_validation` naming a different
ref, second-vs-millisecond ties) and pre-rated none of them. Three of the four
turned out to be real fail-open paths (findings 3 and 4, plus the ref-case case
below which I judged unreachable and did NOT raise); I added six mutations and
five probes of my own choosing on top.

## 2. BLOCKING-1 — closed at cause

`eventContradictedByNewerFail` is the right shape: it corroborates the SNAPSHOT
(an EVENTS record that can never be corrected) against three CURRENT, durable
sources, and it fails CLOSED on a missing or unparseable timestamp. The skip
message names the corroboration refusal instead of falling back to the generic
"validation verdict is …" line, so the refusal is legible. The spec's D6 text
was updated to match, and the positive-control path D6 exists for is preserved
and tested.

Measured, on the copy:

| Probe | Fixture | Result |
|---|---|---|
| round-1 repro | per-ref fail + last_validation fail + run `verdict: fail` + older pass event | **SKIP**, 0 ledger bytes, reason names the refusal |
| positive control | pass event, no fail anywhere, last_validation names another ref | **Flushed**, `verdict_basis: event` |
| p1 (mine) | LEGACY run, fail only in the `VERDICT: FAIL` note, older pass event | **SKIP** — arm (iii)'s note fallback works in production |
| p3c control | per-ref fail one second AFTER the event | **SKIP** |
| p3b (mine) | per-ref fail at the SAME instant as the event | **Flushed**, false PASS -> finding 3 |
| p2b (mine) | event ts with ms, per-ref fail second-truncated inside that second | **Flushed**, false PASS -> finding 3 |
| p4 (mine) | Validation run `verdict: none` + `VERDICT: FAIL` note, no other signal | **Flushed**, false PASS -> finding 4 |
| p5 (mine) | fail only in `last_validation`, ref spelt `change-0001` vs key `CHANGE-0001` | Flushed — `refMatches` is case-sensitive. **Not raised**: no CLI path produces that divergence (`set-validation --ref` writes the global ref and the per-ref stamp from the same string, and `REF_RE` is uppercase-only). Noted so the next reviewer need not re-measure it. |

## 3. Mutations (mine, on copies)

| # | Mutation | Target | Result |
|---|---|---|---|
| MX-A | delete corroboration arm (iii) (the Validation-runs loop) | metrics 144, 139 | **NOT RED** -> finding 1 |
| MX-B | delete corroboration arm (ii) (`last_validation`) | metrics 144, 139 | **NOT RED** -> finding 1 |
| MX-C | delete corroboration arm (i) (the D7 per-ref field) | metrics 144 | **NOT RED** -> finding 1 |
| M26 | `eventContradictedByNewerFail(...)` -> `false` (the spec's own mutation) | metrics 144 | **RED** — BLOCKING-1's guard holds as a whole |
| MX-D | note marker OVERRIDES the verdict field in `reliabilityOf` (= round-1 MX2, which survived) | metrics 145 | **RED** — NON-BLOCKING-B closed |
| MX-E | drop the field/note disagreement NOTE | metrics 145 | **RED** — the NOTE itself is guarded |
| MX-F | per-ref stamp hardcodes `'pass'` (= round-1 MX6, which survived) | state 067 | **RED** — NON-BLOCKING-C closed |
| MX-G | remove the `scope_ref_id` refresh from `set-code-review` | state 069 **and** learned-routing 007 | **RED (both)** — NON-BLOCKING-A closed, double-guarded |
| MX-H | remove the `scope_ref_id` clear from `reset-block code_review` | state 069 | **RED** |
| MX-I | delete the `harness` row from the D6 privacy table | friction 001 | **RED** — NON-BLOCKING-E's core closed |
| MX-J | "EXACTLY these nine keys" -> "eight" (table untouched) | friction 001 | **NOT RED** -> finding 6 |

## 4. Round-1 findings — disposition check

| Round-1 | Fix landed | My call |
|---|---|---|
| **BLOCKING-1** | `eventContradictedByNewerFail` + TEST-144 + M26 + D6 spec text | **Closed at cause.** Not a test-only patch: the refusal is in the gate, the reason string is specific, and the pre-change behaviour is restored for the contradicted case while the recovery path D6 exists for is preserved. |
| **NB-A** `scope_ref_id` had no invalidation or repair path | refresh in `cmdSetCodeReview` from `current_focus.ref_id`; clear in `cmdResetBlock` (`code_review`) and in `applyFullReset`; TEST-031 + a TEST-007 arm | **Closed at cause**, and at the right seam — the writer of the scope now writes its provenance, rather than a consumer guessing. Both new write paths and the clear path redden under mutation. |
| **NB-B** field-over-note precedence untested; disagreement NOTE never built | field-first kept, one NOTE per DISAGREEING run, TEST-145 asserting both directions and the NOTE count | **Closed at cause**, and better than I asked: the dangerous direction (field `fail` + clean note) is asserted, which is what a note-overrides-field mutant would hide. |
| **NB-C** D7 stamp VALUE untested | `--status fail` arm in TEST-029 | **Closed.** MX-F now reddens. |
| **NB-D** `blendedCostUsd` silent 0.5 fallback | deferred to `fu-cost-blend-silent-default` (P3) in `decisions.jsonl` | **Correctly deferred**, and the record states the finding accurately. Risk is narrower than I wrote in round 1: `.aai/system/PRICING.yaml` is in PROFILES `core`, so `/aai-update` ships `cost_blend` alongside the code — only a consumer who LOCALLY edited PRICING.yaml can hit the silent default. |
| **NB-E** D6 privacy contract guarded only for presence | TEST-001 now equates the doc's key rows with `aai-friction.mjs`'s `persisted{}` set | **Closed for the key rows** (MX-I reddens); count words still drift silently (finding 6). |
| **NB-F** `docs/product/telemetry.md` silent on the new surface | telemetry.md rewritten (+56 lines) | **Closed, and it is the strongest document in the change** — see §7. |
| round-3 NB-1 (M9 cell), NB-3 (suite count) | both fixed in the frozen text under `## Amendment` | **Closed**, verified by grep. |

## 5. The decision NOT to stamp `fail` events (D6 text)

**Sound.** The spec's argument is that sources (i)-(iii) are already durable and
CURRENT, that a `validation_verdict: fail` event would duplicate that truth into
a second append-only-and-therefore-never-correctable channel, and that it would
pull `orchestration-dispatch.mjs` and its suite into this review's surface for no
added safety. I agree on all three, and I verified `orchestration-dispatch.mjs`
is untouched by this change.

**Residual, named:** "latest wins, never any-pass-ever" is still NOT a real rule
inside `EVENTS.jsonl` — the producer emits only `pass` (21 of 21 live records),
so the ordering clause in D6 source 3 and TEST-139's fail arm continue to
describe a line shape production never writes. The safeguard is now supplied
entirely by corroboration against STATE, not by event ordering. That is fine as
long as a reader is not misled into believing the event stream is
self-correcting; D6's new text does say so explicitly, so the residual is
documented rather than hidden. The practical consequence is finding 1: because
the event stream carries no fail, the corroboration arms are the whole defence,
and they are individually unguarded.

## 6. Protected surface — `.aai/scripts/state.mjs` (L3)

- **Single writer intact.** `writeState` is still called from exactly two places,
  both in `main()` (`:1158`, `:1151`-region), after the dispatched mutator
  returns. The remediation adds no write path: the `scope_ref_id` refresh lives
  INSIDE the existing `cmdSetCodeReview` `editBlock`, and the reset clear inside
  the existing `cmdResetBlock` `editBlock`. `cmdSetValidation` still has the two
  `editBlock` calls round 1 recorded (global block + D7 stamp) — one file write.
- **Refusal byte-identity intact.** Re-verified independently of the suite, both
  gated roles: `append-run --role "Code Review"` and `--role Validation` without
  `--verdict` exit 2 with a message naming the flag, and `cmp` says the STATE is
  byte-identical.
- **No new global.** The remediation adds none; the two module-level consts
  (`VERDICT_VALUES`, `VERDICT_REQUIRED_ROLES`) are round-1's and follow the
  existing `BOOLS`/`MODES` idiom. `readScalar` and `nullFieldIfPresent` are
  already imported from `lib/state-engine.mjs` — no new import.
- **`check-state` rc 0 on the new shapes.** Live worktree STATE: rc 0. A fixture
  STATE carrying BOTH new shapes at once (`code_review.scope_ref_id` and a
  per-ref `metrics.work_items[<ref>].validation: {status, at}`): rc 0.
- **No hash re-pin owed** — the repo's only content pin names
  `close-work-item.mjs`, untouched.

## 7. Consumer impact after `/aai-update` — is it stated truthfully?

Measured end-to-end on a legacy-shaped fixture (two runs with
`usage_total_tokens=` notes, no `verdict` fields, a `VERDICT: FAIL` note):

```
pre-scope : cost_usd null, null, totals.total_cost_usd null
post-scope: cost_usd 1.08, 4.50, totals.total_cost_usd 5.58,
            cost_basis total-blended, reliability.basis note,
            one NOTE per run: "no verdict field recorded — reliability falls
            back to the note marker (basis note)"
```

- **R8 is now stated where a consumer reads it.** `docs/product/telemetry.md`
  says outright that ledger lines flushed before and after this change are
  "COST-INCOMPARABLE without partitioning on `cost_basis`/`verdict_basis`" and
  that any report summing `cost_usd` across the boundary treats priced and
  unpriced rides as the same unit. That is the honest statement I asked for in
  round 1 and it is materially better than the spec's residual wording.
- **The Article-5 breaking change is stated** ("recorded without `--verdict` is
  REFUSED (exit 2, nothing written)"), and every vendored caller ships in
  PROFILES `core`, so the refusing CLI and the prose satisfying it arrive
  together. A consumer with HAND-WRITTEN role prompts still breaks loudly —
  correct degradation, but it is a BREAKING change for them.
- **What the CHANGELOG (written by the orchestrator at PR) must still say**, and
  the only consumer-visible fact not yet written down anywhere: *the first flush
  after the update can flush refs the old gate refused* (the widened D6 window),
  now bounded by corroboration but still a behaviour change on first run; and
  `--verdict` is REQUIRED for Validation / Code Review in any project with its
  own role prompts.

## 8. Scope discipline

`git status` vs `docs/ai/STATE.yaml` `code_review.scope` (25 paths):

- In scope, not modified: `.aai/scripts/lib/usage-note.mjs` (1) — fine.
- Modified, outside the 25: `docs/specs/SPEC-0178-spec-telemetry-fields-not-prose.md`,
  `docs/product/telemetry.md`, `docs/ai/decisions.jsonl`, `docs/ai/EVENTS.jsonl`,
  `docs/ai/tests/test-runs.jsonl`. All five are the expected companions (the
  ride's own spec, its product doc, and the ledgers). **No code or test file
  outside the declared scope was touched.**
- **Three files are drifting from a CONCURRENT process, not from this ride:**
  `docs/ai/overview.html` and `docs/ai/overview-data.json` (regenerated at
  11:29:41Z and again at 11:38:47Z during this review, picking up my round-1
  report path) and `docs/INDEX.md` (regenerated with a FROZEN clock —
  `Generated: 2026-09-10T12:00:00.000Z`, and `Today (UTC): 2026-09-10`, i.e. a
  suite's fixture date stamped into the repo's committed index). **I did not
  regenerate any of them**: every suite I ran executed in the scratchpad copy,
  whose `PROJECT_ROOT` resolves to the copy (the copy's own `docs/INDEX.md` was
  rewritten at 11:36:06Z with a real timestamp, the worktree's was not). I
  deliberately did NOT `git checkout --` them, because a live concurrent
  validation round is writing this tree and restoring mid-run could redden its
  assertions. **The orchestrator must restore all three immediately before
  staging** (`git checkout -- docs/INDEX.md docs/ai/overview.html
  docs/ai/overview-data.json`) and re-check `git status` at staging time; a
  frozen-date `docs/INDEX.md` in the PR will trip the stale-index check.

## 9. Suites and selection

All re-run by me on the copy, `env -u AAI_ROLE`: `test-aai-metrics.sh` rc 0
(17 s), `test-aai-state.sh` rc 0 (62 s), `test-aai-learned-routing.sh` rc 0,
`test-aai-factory-report.sh` rc 0, `test-aai-feedback-triage.sh` rc 0,
`test-aai-token-capture.sh` rc 0, `test-aai-overview.sh` rc 0,
`test-aai-prompt-diet.sh` rc 0. `test-aai-friction.sh` and
`test-aai-feedback-upsert.sh` fail in the copy ONLY at TEST-013 / TEST-009, both
of which need `.git` (excluded by my rsync); their scope-relevant tests run
selectively and pass (friction TEST-001, TEST-002, TEST-113; upsert TEST-064).
Not findings — see `cannot_verify`.

`select-suites.mjs --files-from <git diff --name-only>` -> `FULL_RUN
reason=protected-l3 path=.aai/scripts/state.mjs`. The FULL_RUN sweep
(`AAI_TEST_TIMEOUT=3000`) is owed before close and is the orchestrator's step;
`sweep-<ts>.txt` does not exist yet. `check-test-registration.mjs` rc 0.

## 10. Next steps

This is the last review round under the two-round cap and both verdicts are
PASS; nothing below blocks the PR.

1. Before staging: restore the three concurrent-process artefacts (§8) and
   re-check `git status`.
2. Cheap, in tree, recommended before the PR (documentation only): add the
   TEST-145 and TEST-031 rows to the spec's Test-plan table and one line to the
   amendment section naming them (finding 2).
3. File as follow-ups: findings 1, 3, 4 (one ref — all three harden
   `eventContradictedByNewerFail`: per-arm mutation tests, `>=` at second
   granularity, and `verdict: none` + fail note treated as a contradiction),
   finding 5 (the INFO line), finding 6 (derive the D6 count word).
4. Run the owed FULL_RUN sweep, then the close ceremony; the CHANGELOG must
   carry the two consumer facts named in §7.
