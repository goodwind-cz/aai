---
role: Code Review
scope: role-verification-guards
spec: docs/specs/SPEC-0133-spec-role-verification-guards.md
reviewer_model: claude-opus-5
requested_model: claude-opus-4-8
prompt_hash: ae47ec0106c6b74822542b6557f8a7b4ab45a353e74ffc0ec770f0a86372eb4a
ceremony_level: 2
run_at_utc: 2026-08-16T19:18:52Z
---

# Code Review — role-verification-guards (adversarial, fresh context)

```yaml
review:
  scope: >-
    uncommitted working tree (git diff + untracked), 23 paths; declared
    code_review.scope = 17 paths
  spec: docs/specs/SPEC-0133-spec-role-verification-guards.md (FROZEN)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/close-work-item.mjs:495-545,1044-1048; TEST-001/002 (test_047/048); --dry-run carve-out at main() `if (!args.dryRun)`" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "stderr-only write at close-work-item.mjs:537-540; TEST-003 (test_049) pre/post cmp against PRE_G1_CLOSE_WORK_ITEM_BLOB=4594d98c" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/orchestration-dispatch.mjs:1172-1177 + recordValidationVerdict:1089-1099; append-event.mjs:143-153; TEST-004 (test_039)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "computeTreeHash:706-725 + filterExcludedDiff:677-690 + withStaleAdvisory:338-349; TEST-005/006/011/013" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "decide() wrapper at :316-323 returns {...out, advisories}; TEST-007 (test_042) incl. the pinned pre-G2 blob comparison" }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/SKILL_TDD.prompt.md:244-251 (Phase 4 step 0); TEST-008 (test_g3_sweep_gate_prompt_contract)" }
      - { ac: Spec-AC-07, call: compliant-as-worded,
          citation: ".aai/SKILL_TEST_SKILLS.prompt.md:48-53; TEST-009 (test_020). Second clause is unsubstantiated by its own regex — NB-3" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "prompt-diet-ledger.sh:166 (+828 B entry); TEST-012 pin -2919; 484+344=828 re-derived" }
      - { ac: Spec-AC-09, call: compliant,
          citation: "tests/skills/lib/close-work-item-pin.sh; callers test-aai-follow-ups.sh:531-545 and test-aai-doc-numbering.sh:1516-1529; TEST-012 (test_010)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 1176,
          issue: "the validation_verdict stamp is first-observation-only per REF, never per VERDICT, so a re-validation after remediation never refreshes it; the stale advisory latches permanently ON and loses all discriminating power",
          failure_scenario: "validation pass -> --confirm stamps H1 -> remediation edits a tracked file -> advisory fires (correct) -> validation round 2 passes on the current tree -> --confirm appends nothing -> every later tick still prints validation_verdict_stale against H1, forever. Reproduced end-to-end in an rsync copy (T1-T6 below). This is the exact scenario the intake wrote G2 for." }
      - { rank: NON-BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 336,
          issue: "the code comment still asserts the byte-identity claim Spec-AC-05 retracted at B3 AND still cites test_033, the citation the spec explicitly removed at N2b as a non-sequitur",
          failure_scenario: "a future maintainer reads the comment, believes non-stale stdout is byte-identical to the pre-G2 tree, and removes the two state_summary keys' deletion from test_042's comparison" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0133-spec-role-verification-guards.md, line: 296,
          issue: "D3's break-even sentence is arithmetically self-refuting (it presents ~36 h benefit against ~43 h cost as break-even at 1 hit in 5; real break-even is 1 in 4.29), and the cost model ignores that VALIDATION.prompt.md:127 already mandates the same full sweep at exactly the L2/L3 population",
          failure_scenario: "the standing rule ships on a stated break-even that its own numbers do not support, and pays a second full sweep one role before a mandatory one" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-prompt-diet.sh, line: 952,
          issue: "OUTPUT_STREAM_WAIT_RE matches only its own bite fixture's phrasing and is polarity-blind; Spec-AC-07's universal-negative clause is not substantiated by it",
          failure_scenario: "a prompt gains `Poll the run output until you see the green PASS line.` — the exact defect G4 exists to prevent — and the corpus scan stays at zero hits" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-follow-ups.sh, line: 113,
          issue: "caller_source_has_ok_guard is a literal-substring grep; a comment containing `!= \"OK\"` satisfies it after the real guard is deleted",
          failure_scenario: "the elif branch is removed from test_008_close_path and a comment mentioning the OK case remains; test_010 passes, both callers silently become denylist-only, and a gutted pin check reads as success" }
      - { rank: NON-BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 719,
          issue: "`git diff HEAD` carries maxBuffer 16 MB; overflow throws, computeTreeHash returns null, and G2 disarms with no signal. The exclusion denylist does not reduce the buffer (filtering happens after the read), and the two sibling git calls carry Node's 1 MB default",
          failure_scenario: "a working tree with >16 MB of uncommitted tracked diff (e.g. a regenerated large tracked artifact, including an excluded ledger) makes every dispatch tick compute tree_hash=null; no stamp is written and no advisory is ever printed" }
      - { rank: NON-BLOCKING, file: .aai/scripts/append-event.mjs, line: 146,
          issue: "the validation_verdict case comment describes the hash as `rev-parse HEAD + status --porcelain -uno`, omitting the `git diff HEAD` fold-in the B4 remediation added",
          failure_scenario: "a maintainer reading the event writer's own contract concludes the hash is status-only and reintroduces B4 on a future edit" }
      - { rank: NON-BLOCKING, file: tests/skills/suite-map.yaml, line: 744,
          issue: "tests/skills/lib/** is globbed only by aai-win-fallback, so editing the new shared pin library does not select either consuming suite; the same is true for .aai/scripts/close-work-item.mjs against those two suites",
          failure_scenario: "a future scope adds an allowlist hash (the INTENDED path) and neither test-aai-follow-ups.sh nor test-aai-doc-numbering.sh is selected, so the mechanism protecting two frozen specs is never exercised on the change that alters it" }
      - { rank: NON-BLOCKING, file: docs/ai/STATE.yaml, line: 0,
          issue: "six working-tree paths sit outside the declared 17-path code_review.scope (docs/ai/EVENTS.jsonl, docs/ai/decisions.jsonl, docs/INDEX.md, docs/ai/overview.html, docs/ai/overview-data.json, docs/ai/tests/test-runs.jsonl)",
          failure_scenario: "SKILL_PR stages only in-scope paths; a regenerated docs/INDEX.md left unstaged ships the dead-link shape CHANGE-0143 was built to remove" }
  cannot_verify:
    - { claim: "the sweep costs ~35 min and would have saved ~150 min on CHANGE-0145 (D3's two load-bearing inputs)",
        closes_with: "timing telemetry across several L2 rides run under the rule; RR-3 already names this" }
    - { claim: "G3 and G4 change role behavior at all (both are carried entirely by prompt compliance, RR-4)",
        closes_with: "role-run telemetry showing the sweep tally or the SWEEP NOT RUN line present in TDD hand-offs" }
    - { claim: "G1 fires correctly against a real merged PR",
        closes_with: "one observed close against a genuinely merged PR; the fixtures prove ancestry, which D1 states is a proxy" }
    - { claim: "every new arm bites (twelve mutations)",
        closes_with: "already closed by validation round 3's mutation table; I did not re-run the suite or the sweep, per dispatch instruction, and relied on that evidence" }
    - { claim: "G2 under concurrent multi-clone operation (two clones stamping the same ref)",
        closes_with: "a two-clone fixture; no arm covers it and RR-1/RR-2 do not name it" }
  overall: fail
```

## Dispatch coaching — recorded per the anti-gaming contract

The dispatch prompt characterized expected findings, pre-ranked them, and
named the pattern it wanted weighed first (`SKILL_CODE_REVIEW.prompt.md`
ANTI-GAMING CONTRACT forbids exactly this). Recorded, and the full scope was
reviewed anyway. The BLOCKING finding and NB-1, NB-2 and NB-6 below are not on
the dispatch's list and were found by reading the code and the spec against
each other.

## Scope preflight

`worktree.user_decision: inline`. `git status --porcelain` = 23 paths; the
declared `code_review.scope` and the spec's inline review scope are set-equal
at 17. The 6 extra paths are append-only/generated byproducts; I read all of
them (NB-8). Review scope established as the whole uncommitted working tree.

## THE HEADLINE QUESTION — has this scope escaped the pattern?

No. The pattern is present at the top level of G2's own design, not only in
its test scaffolding.

B1, B4 and N1 were each a check that measured something adjacent to what it
protected. G2's *product* has the same shape and it survived three rounds:

- what it protects: "can I trust the pass verdict I am about to act on?"
- what it measures: "has the tracked tree moved since the FIRST tick that ever
  observed a pass for this ref?"

Those two are the same thing exactly once per ref — until the first
remediation. From then on they are permanently different, and the guard says
"stale" about a verdict that is not the one anybody holds. Full detail as
BLOCKING-1.

## BLOCKING-1 — the stamp is per-ref-forever, so the advisory latches after the first remediation

**File:** `.aai/scripts/orchestration-dispatch.mjs:1172-1177` (stamp
condition), read with `:338-349` (`withStaleAdvisory`) and `:805-807`
(`snapshot.validation` carries only `status` and `ref_id`).

The stamp guard is `&& !snapshot.last_validation_verdict`. That field is the
*event*, not the *verdict*. Nothing in the condition references the recency,
identity or timestamp of the verdict being stamped. So the reference hash is
written once per ref, ever, and a later validation round that passes on the
current tree cannot move it. `withStaleAdvisory` then compares the current
tree against a reference that is one or more remediations old.

### Reproduction (rsync copy under the session scratchpad; this repo untouched)

| Tick | Action | `validation_verdict` events | stale lines |
|---|---|---|---|
| T1 | `--confirm`, first observation of pass | 1 (stamps H1) | — |
| T2 | dispatch, nothing changed | 1 | **0** (correct) |
| T3 | remediation edit to a tracked file, dispatch | 1 | **1** (correct) |
| T4 | new validation round records pass on the current tree, `--confirm` | **1 — not re-stamped** | — |
| T5 | dispatch | 1 | **1 — false** |
| T6 | dispatch again | 1 | **1 — false** |

(`grep -c` on a zsh `2>&1 >/dev/null` pipeline double-counts because MULTIOS
also tees stdout; the raw `od -c` dump confirms exactly one stderr line per
invocation, so Spec-AC-04's "exactly one line" clause is intact. The
presence/absence pattern above is the finding.)

### Why this is BLOCKING and not another residual

1. **It lands on the guard's own motivating incident.** The intake's G2
   paragraph is *"a recorded `pass` survived a remediation that rewrote the
   engine, the suite, the prompt and eight description surfaces."* The ride
   shape G2 exists for is precisely the one where its reference point goes
   wrong.
2. **It is the modal L2 ride, not an edge case.** Any ride with FAIL →
   remediate → PASS hits it. This scope itself ran three validation rounds.
   From the first remediation onward the advisory is on 100% of ticks, so it
   carries zero bits: a reviewer cannot distinguish "the verdict you are about
   to trust is stale" from "the light has been on since Tuesday". The guard is
   simultaneously a permanent false positive and functionally blind.
3. **D1's own stated principle rules it out.** *"a false alarm in the close
   ceremony trains people to ignore the line."* B1 was blocked for producing a
   permanent latch with nothing changed; this is the same symptom via a
   different trigger, and it is undisclosed.
4. **The spec's honesty inventory contradicts it.** RR-1 is the only place
   stamp freshness is discussed and it says the exposure is *"Bounded to
   seconds on a normal tick."* That is false for every multi-round ride: after
   round 1's stamp, every subsequent verdict is unguarded **and**
   misreported. D5's Limits list — which the spec introduces as *"recorded
   because the failure mode of a warning is that people believe it means more
   than it does"* — does not name it.
5. **The rejection of a refresh design does not cover this.** The comment at
   `:1078-1085` rejects *refresh-on-hash-mismatch*, correctly: it would print
   one line per delta before self-healing. Refresh-on-**new-verdict** is a
   different trigger and has none of that behaviour — it fires only when a
   validator records something new.

### Smallest fix (~6 lines, no new surface, no protected path, no schema change)

`append-event.mjs` already auto-fills `ts` on every line, and STATE already
carries `last_validation.run_at_utc`.

1. `buildSnapshot`, EVENTS loop at `:856` — carry the event timestamp:
   `lastValidationVerdict = { status: ..., hash: ..., ts: e.ts ?? null }`.
2. `buildSnapshot`, `:805-807` — one more `readScalar` beside the two
   existing ones: `run_at_utc: readScalar(lines, 'last_validation', 'run_at_utc')`.
3. `main()` `:1176` — replace `!snapshot.last_validation_verdict` with
   "no stamp yet **or** the recorded stamp predates the current verdict":
   `(!lvv || (v.run_at_utc && lvv.ts && v.run_at_utc > lvv.ts))`.

`decide()` stays pure and untouched; `withStaleAdvisory` already takes the last
event, so a refreshed stamp clears the advisory on the next tick. One new arm
in `tests/skills/test-aai-orchestration-dispatch.sh`: stamp, mutate, rewrite
`last_validation.run_at_utc` to a later value, `--confirm`, assert a second
`validation_verdict` line **and** zero stale lines on the following tick.

If the owner prefers not to build it, the minimum acceptable alternative is an
honest one: correct RR-1, add the latch to D5's Limits, and say in the
CHANGELOG that the advisory is a per-ref one-shot reference rather than a
per-verdict one. I do not recommend that route — the fix is smaller than the
disclosure.

## Directed questions, answered

### Q1 — N-C (`git diff HEAD` maxBuffer): agree, non-blocking

Agreed, and for a sharper reason than round 3 gave. The failure class you are
worried about is "fails open exactly when most needed." That is not quite this
one: the threshold is on the **absolute** size of the working-tree diff, while
the guard triggers on a **delta**. A ride going from a 110 KB to a 200 KB diff
is detected perfectly; to reach ENOBUFS you need ~150x this repository's
routine diff in *uncommitted tracked* content. The correlation between "big
absolute diff" and "the verdict is stale" is weak, so this is not the
guard-disarms-when-needed shape — it is an ordinary environmental fail-open,
already the documented contract for every git path in the scope.

Two things round 3 did not say, which is why I still rank it NB-5 rather than
dropping it:

- `TREE_HASH_EXCLUDE_PATHS` does **not** protect the buffer.
  `filterExcludedDiff` runs on the string *after* `execFileSync` returns, so a
  large regenerated **excluded** ledger (`METRICS.jsonl`,
  `factory-report-data.json`) counts against the 16 MB in full. The denylist's
  own reason for existing — "these move as a byproduct and must not affect the
  guard" — is exactly inverted at the buffer boundary.
- The two sibling calls (`rev-parse HEAD`, `status --porcelain=v1 -uno`) carry
  Node's **1 MB** default, not 16 MB. Far from binding here, but it means the
  scope has three thresholds and named none.

Fix: raise the diff `maxBuffer` (64–256 MB costs nothing when unused) and add
one sentence to D5's Limits naming buffer overflow as a disarm mode.

### Q2 — N-A: no, Spec-AC-07 is not honest as written

AC-07's second clause asserts a property of *guidance*: "a corpus-wide scan of
`.aai/**` finds zero guidance instructing a wait on a pattern in a process
output stream." What the arm verifies is a property of *one phrasing*. Round
3's four-phrasing probe is right, and there is a second defect it did not
name: **the regex is polarity-blind.** It has no notion of prohibition, so a
prompt line correctly teaching *"never wait for a pattern in the output
stream"* would be reported as a violation. G4's own new sentence escapes only
by accident — the `.` in `` `$RUN_DIR/summary.txt` `` truncates the `[^.]*`
window, and the sentence is line-wrapped so a line-based grep cannot span it.
The scan's clean result is therefore doubly uninformative.

I considered whether the role prompt's BLOCKING trigger fires here ("a test
whose NAME claims a universal negative while asserting only a subset of paths
is BLOCKING — rename it or prove the negative (corpus sweep / mutation)"). It
does not: `test_020_g4_disk_artifact_poll_contract` claims nothing universal
in its name, and the arm does perform both remedies the rule names — a full
`.aai/**` sweep and a bite check. What is thin is regex recall, not path
coverage. NB, not BLOCKING.

Smallest fix: reword AC-07's second clause to what is verified ("no `.aai/**`
file matches the output-stream-wait pattern `<regex>`"), which costs nothing
and makes the claim true. Widening the alternation is the better follow-up
(`fu-test020-corpus-regex-thin` already carries it) but does not by itself
make a universal negative honest.

### Q3 — N-B: yes, it is the same defect one level out, but bounded

`caller_source_has_ok_guard` greps an extracted function body for `!= "OK"`.
It measures *the presence of a string that resembles the guard*, not *the
guard's behaviour*. That is the same substitution as N1 (which pinned a copy
of the guard rather than the caller) and as B1/B4 before it. Round 3 proved a
comment satisfies it. So: yes — the fix moved the measurement one level closer
to the real thing without changing its kind.

Two things keep it NB rather than BLOCKING. The consequence chain is three
deep and requires deliberate evasion at each step (delete the guard, leave a
matching comment, then gut the pin check) before anything real is at risk, and
what is finally at risk is a byte-freeze on `close-work-item.mjs`, not a
product surface. And it is a strict improvement on round 2, which caught
nothing.

But I would not accept it as the resting place, because a fourth recurrence of
one pattern in one ride is a signal about the method, not about any single
test. The structural fix is cheap and it *terminates* the recursion instead of
pushing it out again: hoist the whole if/elif into
`close_work_item_pin_assert <root> <test-id>` in
`tests/skills/lib/close-work-item-pin.sh`, and have both callers become one
line. Then there is one guard, in one place, and `test_010`'s existing dynamic
probe can shadow `close_work_item_pin_check` and drive the **real**
`close_work_item_pin_assert` — a behavioural pin with nothing textual left to
grep for. Recommended disposition: **remediate in tree** (~15 lines).

### Q4 — G3: the inference is not sound enough for a standing rule

Two independent problems, one of which is arithmetic.

**The stated break-even is false on its own numbers.** D3 line 296: *"break-
even on 73 L2/L3 rides is roughly 1 hit in every 5 rides (73/5 x 150 min = ~36
h against ~43 h)"*. 36 against 43 is not break-even — it is a 15% net loss.
Actual break-even is 2555/150 = 17.0 hits over 73 rides, i.e. **1 in 4.29**.
The spec presents a losing ratio as the break-even point and then hedges it as
"plausible but not proven", which reads as more support than it has.

**The cost model omits the duplicate.** `.aai/VALIDATION.prompt.md:127` —
*"When `lane.selected == "full"` (ceremony_level 2/3 ...), run the full
discovery/execution sweep exactly as today."* Validation already runs the full
79-suite sweep at **exactly** the L2/L3 population G3 targets; round 3's own
report has a "MANDATORY FULL SWEEP — RUN, GREEN" section proving it. So G3
adds a second full sweep one role before a mandatory one, and adds another on
every remediation lap. The marginal benefit is not "catches it two roles
earlier" but "catches it one role earlier, where the same role can fix it in
place" — real, but smaller than the 150 min D3 credits it with, since the
counterfactual already ends at Validation rather than at code review.

Neither point is visible from testing the guard, which is why three validation
rounds did not surface it — it is a planning-inference defect, correctly mine.

**Recommendation:** ship G3 as a *recommendation* ("run the full sweep before a
done claim at L2/L3; if you did not, say `SWEEP NOT RUN — <reason>`") rather
than a REQUIRED standing rule, until the two numbers are measured. Note the
prompt's escape hatch already makes the two nearly identical in practice — an
un-run sweep is permitted at every level provided it is named — so demoting
the word REQUIRED costs almost nothing and stops the spec asserting a trade it
has not established. At minimum, D3's break-even sentence must be corrected
and the Validation duplicate acknowledged. The L0/L1 exemption is
independently sound and is not in question.

### Q5 — the new file: yes, it belongs, and it did not belong in an existing one

Agreed. The two alternatives are both worse:

- **Duplicate the allowlist in both suites** reinstates precisely the failure
  the unification removes — two independently frozen pins on one file that can
  silently disagree (they already did: "a keyword-scan escape hatch here, a
  hard byte-diff failure there").
- **Put it in one suite and source it from the other** makes
  `test-aai-doc-numbering.sh` depend on `test-aai-follow-ups.sh`'s internals;
  both are standalone executables under `set -euo pipefail` with top-level
  fixture setup, so sourcing one from the other executes that setup.

`tests/skills/lib/` already exists for exactly this, `prompt-diet-ledger.sh` is
the same shape under the same discipline (pure, sourceable, no `set -u`, no
`cd`, bash-3.2 safe), and the SPEC-0060 precedent is genuinely parallel rather
than reached for. The intake's "no new file" was scoped to `.aai/**`, which the
spec's companion-obligations section reads correctly.

The one real cost of the new file is NB-7: the mechanism now protecting two
frozen specs has worse suite-map routing than the two pins it replaced. That
is two lines in `tests/skills/suite-map.yaml` and I would fix it here rather
than leave it as a P3 follow-up — a routing gap on the guard's own file is the
same self-referential hole as everything else on this ride.

### Q6 — honesty sweep: one surviving false sentence in code, one in the spec

I read the current spec against the current code. The spec text is, with two
exceptions, now accurate — the B1/B2/B3/B4/N2b corrections are real and each
one narrowed a claim rather than restating it. D5's Limits, RR-2's
committed-excluded-path residual and RR-4's prompt-compliance admission are all
honest and all match the code.

**False sentence 1 — in the code, and it is the retracted claim itself.**
`.aai/scripts/orchestration-dispatch.mjs:336-337`:

> `// on either side yields the input unchanged, so non-stale JSON stays`
> `// byte-identical to the pre-G2 tree (Spec-AC-05 / test_033).`

Both halves are what B3 and N2b removed from the spec, surviving one level out
in the source. Non-stale stdout is **not** byte-identical to the pre-G2 tree —
`buildSnapshot` unconditionally adds `tree_hash` and `last_validation_verdict`
to `state_summary`, which is exactly why Spec-AC-05 was reworded to
"additive-only modulo those two keys". And `test_033_stable_segment_byte_
identity` pins `prompt_hash`/`inherits` stability across two ticks
(`test-aai-orchestration-dispatch.sh:1989-1997`), which the spec explicitly
says "is not evidence for this paragraph's claim; the citation above is removed
rather than repeated." The citation was removed from the spec and left in the
code. Fix: reword to the decide()-level guarantee actually held ("`decide()`'s
own output is unchanged; stdout is additive-only by two `state_summary` keys")
and cite `test_042` / Spec-AC-05.

**False sentence 2 — D3's break-even arithmetic** (Q4 above).

**Stale, not false — NB-6.** `append-event.mjs:146` still describes the payload
hash as "rev-parse HEAD + `status --porcelain -uno`". The B4 remediation added
`git diff HEAD` to the hash and updated the comment in
`orchestration-dispatch.mjs` but not in the event writer, which is the file a
maintainer reads to learn what the field means.

Everything else I checked held: the `--dry-run` carve-out matches
`if (!args.dryRun)`; D1's "shells out only to node and `git worktree list`"
still holds; the "one new file, outside `.aai/**`" accounting is right; the
`usage()` widening names both writes; Spec-AC-08's arithmetic
(484+344 = 828; −3747+828 = −2919) re-derives exactly. One cosmetic drift: the
Links section cites "the comment at `orchestration-dispatch.mjs` line 694",
which the diff has moved — INFO only.

## Findings, ranked

| Rank | Id | File:line | Disposition (orchestrator records) |
|---|---|---|---|
| **BLOCKING** | B-1 | `.aai/scripts/orchestration-dispatch.mjs:1176` | remediate in tree |
| NB-1 | retracted byte-identity claim + `test_033` citation live on in code | `.aai/scripts/orchestration-dispatch.mjs:336` | remediate in tree |
| NB-2 | D3 break-even arithmetic + omitted Validation sweep duplicate | `docs/specs/SPEC-0133-spec-role-verification-guards.md:296` | remediate in tree |
| NB-3 | AC-07's universal negative unsubstantiated; regex polarity-blind | `tests/skills/test-aai-prompt-diet.sh:952` + spec Spec-AC-07 | reword AC in tree; widen regex under `fu-test020-corpus-regex-thin` |
| NB-4 | literal-grep caller pin | `tests/skills/test-aai-follow-ups.sh:113` | remediate in tree (hoist to `close_work_item_pin_assert`) |
| NB-5 | 16 MB maxBuffer silent disarm; denylist does not reduce the buffer | `.aai/scripts/orchestration-dispatch.mjs:719` | remediate in tree (raise buffer + one D5 sentence) |
| NB-6 | stale hash description in the event writer | `.aai/scripts/append-event.mjs:146` | remediate in tree |
| NB-7 | suite-map does not route the new shared pin library to its consumers | `tests/skills/suite-map.yaml:744` | remediate in tree (supersedes `fu-pin-lib-suite-map-route`) |
| NB-8 | six paths outside the declared review scope | `docs/ai/STATE.yaml` `code_review.scope` | name them in the PR staging list |
| INFO | Links cites a moved line number (`orchestration-dispatch.mjs` line 694) | spec Links | none |
| INFO | G3's prompt does not say WHERE to read `ceremony_level`; fail-closed-to-2 bounds the harm | `.aai/SKILL_TDD.prompt.md:248` | none |

## What is genuinely good here, said plainly

The remediation work across three rounds is real and I could not break most of
it. `filterExcludedDiff` is `^`-anchored and correctly matches both sides of a
rename. The pinned pre-change blob shas are the right answer to B2 and survive
the delivery commit. `decide()`'s split into `decideRuleTable` +
`withStaleAdvisory` keeps the rule table literally untouched and makes the
purity pin meaningful. TEST-013's fixture invariant — asserting the git status
letter is byte-identical before and after the second edit, so the arm cannot
silently stop exercising the content-only case — is better discipline than
most of the suite. G1 is small, hermetic, fail-open in the right direction, and
its report-only proof is done properly against a pinned blob rather than a
moving HEAD. The 828 B ledger true-up re-derives exactly.

The scope's problem is not craft. It is that the one guard with a real
mechanism compares against the wrong reference point, and the spec's honesty
inventory — which is unusually good everywhere else — does not say so.

## Next steps

1. Fix BLOCKING-1 (per-verdict stamp refresh) with one new arm proving the
   advisory clears after a fresh verdict.
2. Fix NB-1, NB-2, NB-6 (three text edits; no behaviour change).
3. Recommended in tree: NB-4 (hoist the guard), NB-5 (buffer + D5 sentence),
   NB-7 (two suite-map lines), NB-3's AC rewording.
4. Re-review after remediation: same single pass, per RE-REVIEW.
