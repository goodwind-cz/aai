# Code Review — single-writer-canon-contradiction (adversarial, post-Validation-round-2 PASS)

```yaml
review:
  scope: git diff 061f3a1..HEAD (HEAD = edb2030, branch docs/single-writer-canon)
  spec: docs/specs/SPEC-0152-spec-single-writer-canon-contradiction.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/ORCHESTRATION.prompt.md:7-12; TEST-RG-PIN-04 PASS (42/45 lines); mutation M3 bites" }
      - { ac: Spec-AC-02, call: non-compliant,
          citation: ".aai/REMEDIATION.prompt.md:72 still directs `set-human-input` unconditionally; the carve at :67 scopes itself to steps 4-5" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/SUBAGENT_CONTRACT.md:73 + :81; .aai/SUBAGENT_PROTOCOL.md ENV row + merge step 3; TEST-RG-PIN-06 PASS" }
      - { ac: Spec-AC-04, call: non-compliant,
          citation: "flush-left YAML list under state_update_commands -> check-role-output.mjs exit 1, E-MALFORMED-LINE (probe below); PIN-07 covers only the indented rendering" }
      - { ac: Spec-AC-05, call: cannot-verify,
          citation: "RED log carries zero FAIL lines for PIN-07 (validator F3, re-confirmed by report); mutation half independently re-proved for PIN-04/05/06" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "tests/skills/suite-map.yaml:563-568; test-aai-hygiene-pack.sh exit 0" }
      - { ac: Spec-AC-07, call: non-compliant,
          citation: "measured 314067 -> 314930 = 863 B > the AC's 700 B; two JUSTIFIED_ADDITIONS entries (657 + 206) vs 'a single entry'" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "git diff main --name-only INTERSECT protected_paths_l3 = empty; registry closure deferred to close by design" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/REMEDIATION.prompt.md, line: 72,
          issue: "per-file sweep hole: the carve names steps 4-5, step 6 still directs a STATE mutator",
          failure_scenario: "dispatched Remediation blocked on a human decision runs `state.mjs set-human-input` -> R-GUARD S1 exit 3; the blocker is neither recorded nor returned, so the loop stalls with no human_input flag" }
      - { rank: BLOCKING, file: .aai/SUBAGENT_CONTRACT.md, line: 73,
          issue: "the claim 'this key never invalidates an otherwise-clean block' is false for a YAML-legal rendering, and the result-block template does not show the key",
          failure_scenario: "subagent emits the flush-left list form; check-role-output.mjs exits 1 with E-MALFORMED-LINE naming the command text, so the merge gate refuses the whole block and the diagnostic points at the wrong thing" }
      - { rank: NON-BLOCKING, file: .aai/ORCHESTRATION.prompt.md, line: 19,
          issue: "the exit-4 staleness lane dispatches roles but never names append-run or the returned state_update_commands",
          failure_scenario: "rule needs_llm dispatches Validation; the role returns its commands per the new rule; nobody runs them; the phase silently stops advancing (the intake's own named risk, which D4 claims is mitigated by pinning both ends)" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-r-guard.sh, line: 165,
          issue: "PIN-05/PIN-04 assert token presence, not the rule",
          failure_scenario: "replacing the PLANNING carve with 'NOTE: see .aai/SUBAGENT_CONTRACT.md for state_update_commands background.' deletes the rule and leaves the suite exit 0 (measured)" }
      - { rank: NON-BLOCKING, file: .aai/SKILL_TDD.prompt.md, line: 66,
          issue: "the 206-B clause is unpinned and aai-r-guard is not selected for this file",
          failure_scenario: "a later edit deletes the clause; no arm fails, CI does not even select the suite, and the ledger keeps paying 206 B for text that is gone" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0026-spec-work-item-brief.md, line: 217,
          issue: "delivered spec's TEST-006 row still describes the assertion this diff changed as '<=40 lines'",
          failure_scenario: "docs-audit verify SPEC-0026, or anyone reading the owning spec to justify the guard, gets a false record: the test now asserts <=45" }
  cannot_verify:
    - { claim: "the orchestrator actually executes returned state_update_commands on a live serial ride",
        closes_with: "one observed serial ride whose STATE mutations land from a returned block (or a runtime harness arm); prose pins cannot show it — the spec records this as residual risk" }
    - { claim: "Spec-AC-05's 'each arm observed FAILING' for TEST-RG-PIN-07",
        closes_with: "a RED log containing a PIN-07 FAIL line, or an honest AC rewording; the stored log has zero" }
  overall: fail
```

- Reviewer: Code Review role, dispatched as a subagent (rule 13, adversarial pass after Validation round 2 PASS)
- Branch: `docs/single-writer-canon` (verified, not switched, not pushed)
- Started (UTC): 2026-08-24T16:54:55Z / Ended (UTC): 2026-08-24T17:02:44Z
- Coaching check (anti-gaming): the dispatch named six adversarial focus areas but pre-rated no severity, excluded no area, and pasted no diff. No coaching to record.

## Verdict

**FAIL** — two BLOCKING findings. Both are cheap to fix (one is a zero-byte
edit, one costs no corpus bytes at all), and neither invalidates the design:
option (a) is the right decision, the D1 phrasing is correct, and the seven
declared surfaces are otherwise aligned. The scope is one remediation round
from mergeable.

What I confirmed independently and found sound:
- **Zero content loss** in the contract condensation, checked base-to-HEAD (not
  just across 18c7957): a sorted word multiset of `.aai/SUBAGENT_CONTRACT.md`
  at 061f3a1 vs HEAD has **zero** words present in base and absent in head
  (625 -> 805 words). All five Standing hazards intact.
- **The D3 seam is real.** `check-role-output.mjs:461-462` genuinely consumes
  and ignores an unrecognized top-level key and its nested lines — for the
  indented rendering. See P1-2 for the rendering it does not tolerate.
- **DEBT-0002 backs the 40->45 raise.** `docs/issues/DEBT-0002...:74-75` and
  `docs/specs/SPEC-0048...:62-63,81` raised the TEST-011 thin-wrapper ceiling
  40 -> 45 on 2026-07-17; `WRAPPER_LINE_CEILING=45` at
  `tests/skills/test-aai-prompt-diet.sh:355`. test_060's private `<=40` was a
  stale duplicate of the pre-DEBT-0002 value. The raise is correct.
- **Ledger arithmetic and format are clean.** Sourcing the library emits
  nothing on stderr; `JUSTIFIED_GROWTH_BYTES=2273` = 1410 + 657 + 206; both new
  entries parse their leading field; no unescaped backticks (TEST-021 green).
- **Pins bite on deletion.** My own mutation probes in a disposable detached
  worktree: deleting the PLANNING carve fails PIN-05; deleting ORCHESTRATION's
  run-the-commands sentence fails PIN-04; controls green on both sides.
- All declared-scope suites exit 0: `aai-r-guard`, `aai-prompt-diet`,
  `aai-hygiene-pack`, `aai-state`, `aai-role-output`, `aai-token-capture`.

## BLOCKING findings

### P1-1 — `.aai/REMEDIATION.prompt.md:72` still directs a dispatched subagent to run a STATE mutator

The carve landed at `:67` and scopes itself explicitly:

```
67:   Dispatched, steps 4-5: return these as `state_update_commands:` instead of
68:   running them (.aai/SUBAGENT_CONTRACT.md). Sole agent: run them.
```

Step **6** is outside that scope and still says:

```
71:6) STOP after the reset + your agent-run append (METRICS below). Do NOT loop:
72:   ... If remaining blockers require
73:   explicit human decisions, record them via set-human-input and stop.
```

Why it bites. A dispatched Remediation agent that hits a human-decision
blocker follows step 6, runs `state.mjs set-human-input`, and R-GUARD S1
refuses with exit 3 — the exact time-loss this scope exists to remove. Worse
than a wasted call: because step 6 is not covered by the carve, the agent also
does not put the command in `state_update_commands:`, so the blocker is
recorded **nowhere** and the loop stalls with `human_input.required` still
false.

This is a declared-surface, declared-AC gap, not successor material.
Spec-AC-02 requires that "no surface directs a dispatched subagent to run a
STATE mutator unconditionally"; intake AC-001 requires that "no surface
simultaneously forbids and directs direct subagent STATE mutation". Both are
false at `:72`.

Why both validation rounds missed it: round 2's Check 4 sweep used
`state\.mjs +(set-|append-|reset-|...)`, which requires the literal `state.mjs`
prefix. Line 72 names the mutator by bare verb. This is the per-file sweep hole
in its exact documented shape — a correction placed once, another occurrence
left standing in the same file.

I re-ran the sweep without the prefix requirement across all of `.aai/*.md`,
`.aai/workflow/`, `.aai/system/`. `:72` is the **only** uncovered directive;
`SKILL_LOOP.prompt.md:360` is the carved sole-agent lane, `INTAKE_COMMON.md:90`
is a prohibition, and the remaining hits are parentheticals inside already
carved steps.

**Minimal fix:** `:67` `steps 4-5` -> `steps 4-6`. Same byte length, so the
corpus delta and the ledger do not move.

### P1-2 — `.aai/SUBAGENT_CONTRACT.md:73` ships a false compatibility claim at the one declared seam

The new D1 paragraph states, without qualification:

> `check-role-output.mjs` ignores unrecognized top-level extension keys, so
> this key **never invalidates an otherwise-clean block**.

That is false for a YAML-legal rendering of the very instruction the sentence
gives ("one per list item ... under a top-level `state_update_commands:` key").
YAML permits block-sequence items at the same indentation as their parent key.
Measured against the real checker:

```
$ node .aai/scripts/check-role-output.mjs --file flat.md --now 2026-08-24T09:10:00Z
ROLE-OUTPUT-VIOLATION: E-MALFORMED-LINE unparseable block line: - node .aai/scripts/state.mjs set-phase --ref x --phase vali
EXIT=1
```

(the fixture is the PIN-07 valid block with the two `state_update_commands`
list items dedented by two spaces — every required field present and valid).

Root cause is visible at `.aai/scripts/check-role-output.mjs:428-434`: a
base-indent line that is not `key:` and not a comment is pushed to `malformed`,
which becomes `E-MALFORMED-LINE` and exit 1. Extension keys are only ignored
together with lines strictly **deeper** than base indent (`:438`).

Why it bites. The result-block YAML template at `.aai/SUBAGENT_CONTRACT.md:43-59`
does **not** contain `state_update_commands`, so a subagent filling the
template has no indentation exemplar for the new key and the prose gives none.
A block emitted in the flush-left style is refused **in its entirety** at the
mandatory merge gate, and the violation line quotes the `node ...` command, so
the orchestrator's most likely diagnosis is "bad command", not "bad
indentation". Spec-AC-04's generic wording ("a result block carrying a
`state_update_commands:` list ... SHALL exit 0") is therefore not universally
true; PIN-07 certifies only the indented rendering.

This is the finding I weight heaviest on principle: a scope whose entire
purpose is removing false canon must not ship a new absolute claim its own
artifacts disprove.

**Minimal fix (zero corpus cost — this file is outside the diet glob):**
1. add `  state_update_commands:` + one indented list item to the template
   block at `:43-59`, marked optional;
2. qualify the claim: "...ignores unrecognized top-level keys **and their
   indented nested lines**, so this key never invalidates an otherwise-clean
   block **written in the template's indentation**";
3. add a third PIN-07 arm asserting the flush-left rendering is refused (so the
   constraint is pinned rather than folklore).

## NON-BLOCKING findings (each carries a disposition duty, H6)

### P2-1 — ORCHESTRATION's exit-4 lane dispatches roles it never collects from

`.aai/ORCHESTRATION.prompt.md:19-20`:

```
19:   - validation_staleness_unknown / review_staleness_unknown: judge staleness
20:     against the current diff yourself; dispatch Validation / Code Review.
```

Only step 2 names `append-run` and "Then run any returned
state_update_commands"; step 4 routes straight to step 5. Before this diff that
lane merely lost a metrics append. After it, the dispatched role **returns**
its state commands instead of running them, and nothing on this lane runs them
— the phase silently stops advancing. That is verbatim the intake's named risk
and D4's claim that "Both ends are pinned" does not hold for this lane.

**Fix:** `dispatch Validation / Code Review.` -> `dispatch Validation / Code
Review per step 2.` (+13 B in-corpus, so it needs a ledger true-up).
**Disposition:** remediate-in-tree with P1-1.

### P2-2 — PIN-04/PIN-05 pin tokens, not the rule (demonstrated, not theorised)

`tests/skills/test-aai-r-guard.sh:165-172` asserts only that
`state_update_commands` and `.aai/SUBAGENT_CONTRACT.md` occur **somewhere** in
each file. Measured decoy, in a disposable detached worktree at HEAD:

| step | mutation | suite |
|---|---|---|
| control | none | exit 0 |
| M1 | delete the PLANNING carve outright | exit 1, `PIN-05: PLANNING.prompt.md does not name state_update_commands` |
| **M2** | replace the carve with `NOTE: see .aai/SUBAGENT_CONTRACT.md for state_update_commands background.` | **exit 0 — rule gone, suite green** |
| M3 | delete ORCHESTRATION's `Then run any returned state_update_commands.` | exit 1, PIN-04 |
| control 2 | `cp` from pristine, `cmp` clean | exit 0 |

So the answer to "can a future editor gut the carve while keeping the pinned
phrases" is yes, and the edit that does it looks like a tidy-up. The arms match
Spec-AC-02's literal wording ("one clause **naming** both"), so this is an
assurance-strength defect, not an AC breach.

**Fix (test-only, zero corpus):** require the imperative shape — e.g.
`state_update_commands:. instead of running` plus `Sole agent: run them`, both
present verbatim in all five files today.
**Disposition:** remediate-in-tree (cheap) or a tracked follow-up.

### P2-3 — the SKILL_TDD clause is unpinned and unselectable (validator F7d, confirmed)

`.aai/SKILL_TDD.prompt.md:66` is the file's only occurrence of
`state_update_commands`; no arm asserts it, and `.aai/SKILL_TDD.prompt.md` is
absent from the `aai-r-guard` globs (it appears in eight other suites'
globs, none of which check this). It can be deleted with a green CI that never
even selects the guarding suite — while `JUSTIFIED_ADDITIONS` keeps paying
206 B for it.

**Fix:** extend PIN-05's loop to SKILL_TDD (clause present; the four
`set-tdd-cycle` sites at :109/:172/:223/:290 all below it) and add the path to
the `aai-r-guard` globs. Test + suite-map only, zero corpus.
**Disposition:** remediate-in-tree — it is the cheapest durable item in this
report.

### P2-4 — Spec-AC-07's 700 B budget is breached at 863 B, in two entries (validator F6, independently re-measured)

```
$ /bin/bash -c 'cat .aai/*.prompt.md | wc -c'   @061f3a1 = 314067
$ /bin/bash -c 'cat .aai/*.prompt.md | wc -c'   @HEAD    = 314930   -> delta 863
```

Ledger: `657` + `206` = 863; pin 1410 -> 2273; TEST-010 headroom 0/2048;
sourcing the library is silent. Every byte is honestly measured and paid 1:1 —
the failure is against the AC's own numeric budget and its "a single entry"
clause, both breached by the F2 remediation this validation loop demanded on a
file the frozen spec never declared.

I concur with the validator that this is not remediation material (fixing it
means amending a frozen spec, a Planning action). It is a **close-gate**
obligation: Spec-AC-07 must not flip to a plain `done` citing 657.
**Disposition:** promote to the close ceremony as an amended AC or a `done` row
whose Notes carry the 863/two-entry reality.

### P2-5 — SPEC-0026 now misdescribes the test this diff edited

`tests/skills/test-aai-hygiene-pack.sh:728` moved `<=40` -> `<=45`
(correctly — see DEBT-0002 above). But the spec that owns that assertion still
says otherwise:

- `docs/specs/SPEC-0026-spec-work-item-brief.md:217` — TEST-006, status
  `green`: "ORCHESTRATION.prompt.md **<=40 lines** AND still routes dispatch
  through .aai/SUBAGENT_PROTOCOL.md"
- `:177` — Spec-AC-02 `done`, Evidence "ORCHESTRATION 40 lines"

A live test-plan row describing a live test is a record, and it is now false.
(`:157`/`:200`/`:118`, and SPEC-0019/SPEC-0098's `<=40` mentions, are
historical design prose superseded by DEBT-0002 — those I would leave.)

**Fix:** one Notes line on SPEC-0026 TEST-006 / Spec-AC-02 naming the
DEBT-0002 ceiling raise. **Disposition:** remediate-in-tree or a tracked
follow-up ref — this one cannot be an `accepted residual`, because it leaves a
false record.

## P3 / INFO

- **P3-1** `.aai/SUBAGENT_CONTRACT.md:73` — "or **this contract's own** review
  rule 2 for `set-code-review`". There is no numbered review rule in the
  contract; review rule 2 is in `.aai/SUBAGENT_PROTOCOL.md:70-73` (validator
  F9, confirmed). The *content* of the cross-reference is accurate — that rule
  really does say "the reviewer records it via `state.mjs set-code-review` when
  it is the sole agent" — only the attribution is wrong. Worth fixing with P1-2
  since both edits touch the same sentence.
- **P3-2** `.aai/REMEDIATION.prompt.md:17` — "Your only legal status **write**
  is the `reset-block` transition" reads, under D1, as an authorization to
  write. It is a scope-of-authority statement, not a directive, so it is not
  P1-1; "status change" would remove the ambiguity in the same edit.
- **P3-3** PIN-04's unset assertion is
  `grep -qiE 'unset|non-`?subagent`?|not carry|MUST NOT carry'` — bare `unset`
  matches anywhere in the file. Today there is exactly one occurrence (the new
  clause at `:9`), so it bites; it is simply the loosest of the four
  assertions and would stop discriminating the moment the word appears
  elsewhere.
- **INFO** the four new arms end with
  `[[ "$FAILED" == 0 ]] && log_pass ... || true`, coupling each arm's PASS line
  to the *global* FAILED, unlike PIN-01..03 which call `log_pass` directly. No
  bite while the suite is green (the state every AC cites), but a failing arm
  silences later arms' PASS lines and makes triage read as a cascade.

## F7 boundary judgment (dispatch focus 6)

The spec's authoritative surface list is its "Inline review scope" plus the
7-step implementation plan: SUBAGENT_CONTRACT, SUBAGENT_PROTOCOL, ORCHESTRATION,
PLANNING, IMPLEMENTATION, VALIDATION, REMEDIATION, the r-guard suite, suite-map,
and the diet ledger/test. Judged against that list:

- **F7a (SKILL_CODE_REVIEW:150), F7b (SKILL_WORKTREE:166-167), F7c
  (METRICS_FLUSH:42) — successor material, correctly NOT blocking.** None is in
  the declared list; none is a regression from this diff; F7b provably cannot
  be fixed by copying the clause (its writes target the new worktree's own
  STATE file after a `cd`, so returning them to a main-tree orchestrator writes
  the wrong file — that needs a decision, not a pointer). I agree with the
  validator, and I add that F7a is sharper than "the carve is on the wrong side
  of the payload boundary": `.aai/SKILL_CODE_REVIEW.prompt.md:9-14` grants the
  reviewer a STATE write "when the dispatch grants it (single-agent mode **or an
  explicit instruction**)", which is strictly broader than D1's sole-agent-only
  carve. The successor item should reconcile that wording, not just add a
  pointer.
- **F7d (SKILL_TDD unpinned) — a real gap in this scope**, because the diff
  itself created the clause and pays 206 corpus bytes for it. Raised as P2-3.
- **REMEDIATION:72 — a delivery gap that MUST block** (P1-1). It is inside a
  declared file, inside Spec-AC-02 and intake AC-001, and is the same class the
  spec was written to eliminate.

Note for the close: SKILL_TDD and hygiene-pack were both edited outside the
frozen spec's declared surface list (see Deviations). Fixing SKILL_TDD while
leaving SKILL_CODE_REVIEW is defensible (IMPLEMENTATION:49 dispatches *into*
SKILL_TDD, making it an extension of a declared surface) but the boundary is
thin, and the registry item must therefore be closed with a qualified
`resolved_by` plus a successor item, exactly as the validator's obligation 3
says.

## Deviations from the frozen spec (all reasonable, all recorded)

1. `.aai/SKILL_TDD.prompt.md` edited — not in the spec's inline review scope or
   the 7-step plan. Necessary (round-1 F2), and it is what pushed Spec-AC-07
   over budget.
2. `tests/skills/test-aai-hygiene-pack.sh` edited — not in the inline review
   scope. Unavoidable: the spec budgeted ORCHESTRATION at "42 of 45" without
   noticing test_060's private `<=40`, which would have failed at 42.
3. Intake constraint "ORCHESTRATION.prompt.md is capped at 40 lines" superseded
   by the spec's 45 (DEBT-0002-backed). Delivered at 42 lines / +104 B, matching
   the spec's "+2 lines, roughly +110 bytes" budget.
4. Spec-AC-07 breached as measured (P2-4).
5. Spec-AC-05 not literally satisfiable for PIN-07 (validator F3, carried).

## Checks performed

| Command | Exit | Note |
|---|---|---|
| `git branch --show-current` | 0 | `docs/single-writer-canon` |
| `env -u AAI_ROLE bash tests/skills/test-aai-r-guard.sh` | 0 | PIN-01..07 PASS, 42/45 lines |
| `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh` | 0 | TEST-010/011/012 green, pin 2273 |
| `env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh` | 0 | test_060 at the raised ceiling |
| `env -u AAI_ROLE bash tests/skills/test-aai-state.sh` | 0 | TEST-014 intact |
| `env -u AAI_ROLE bash tests/skills/test-aai-role-output.sh` | 0 | TEST-020 headroom (F1) fixed |
| `env -u AAI_ROLE bash tests/skills/test-aai-token-capture.sh` | 0 | TEST-003 one-line phrase survived the step-2 rewrite |
| `node check-role-output.mjs --file <flush-left fixture>` | **1** | `E-MALFORMED-LINE` — **P1-2** |
| `node check-role-output.mjs --file <indented fixture>` | 0 | extension key ignored as designed |
| word-multiset `comm -23` base vs HEAD, SUBAGENT_CONTRACT.md | 0 | **zero** removals (625 -> 805 words) |
| `/bin/bash -c 'cat .aai/*.prompt.md \| wc -c'` @061f3a1 / @HEAD | 0 | 314067 / 314930 -> 863 B |
| `. tests/skills/lib/prompt-diet-ledger.sh` | 0 | `2273`, silent stderr |
| bare-verb mutator sweep over `.aai/*.md`, `workflow/`, `system/` | 0 | one uncovered directive: REMEDIATION:72 — **P1-1** |
| mutation M1/M2/M3 + 2 controls, disposable detached worktree | 1/0/1, 0/0 | **P2-2** (M2 green with the rule deleted) |
| `wc -c/-l` ORCHESTRATION base vs HEAD | 0 | 3076->3180 B, 40->42 lines |
| `git worktree remove <path>` x2, `git worktree list` | 0 | only the shipping tree remains |

Hazards honored: both probe worktrees were disposable detached worktrees under
the scratch path, mutations were applied to the worktree copy and undone by
`cp` from a pristine copy (HAZ-RESTORE: no restoring git command on a tracked
file), removed with targeted `git worktree remove` (HAZ-WORKTREE, never
`prune`). All measurement ran under `/bin/bash -c` with `/usr/bin/grep`.
`docs/ai/STATE.yaml` was not written. Nothing committed.
