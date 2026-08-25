# Code review — close-leaves-state-stale (adversarial, post-validation-round-4)

- ref_id: `close-leaves-state-stale`
- branch: `fix/post-close-state-truth` @ `5eb5ce4`
- scope: `git diff main..HEAD` (13 files, 10 commits `e23d4f2..5eb5ce4`)
- spec: `docs/specs/SPEC-DRAFT-close-leaves-state-stale.md` (SPEC-FROZEN, amended post-freeze 2026-08-25; 10 Spec-ACs, all rows `planned` per VALIDATION rule 8a)
- reviewer: dispatched subagent, read-only on implementation files
- started_utc: 2026-08-25T03:55:06Z
- ended_utc: 2026-08-25T04:08:28Z (system clock; the report body was written before this stamp and the stamp captured at commit time)

```yaml
review:
  scope: main..HEAD (fix/post-close-state-truth @ 5eb5ce4)
  spec: docs/specs/SPEC-DRAFT-close-leaves-state-stale.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/close-work-item.mjs:1120-1211 (planStateReconcile) + tests/skills/test-aai-close-work-item.sh test_051; my own --dry-run probe emitted both commands with the resolved numbered path" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/close-work-item.mjs:1473 (short-circuit tail calls runStateReconcile) + test_053; suite exit 0" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/close-work-item.mjs:1270-1290 (runStateReconcile) + test_054 arms 2/3; see finding Q-2 — D3's echo INTENT is violated on one reachable sub-path while the AC's own wording is satisfied" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/close-work-item.mjs:1226 execFileSync has no env key -> AAI_ROLE inherited; test_054 arm 1" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/orchestration-dispatch.mjs:450-474 (closedFocus guard after 4a/4b) + test_046 cases 1-7" }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/scripts/orchestration-dispatch.mjs:932-959 + :971 (closeEventSupersededByReopen) + test_047 part B" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "tdd-evidence-check.mjs --red -> ACCEPTED (product_red) x3: red-close-work-item-state-reconcile.log, red-orchestration-dispatch-closed-focus-guard.log, red-test055-...20260825T015522Z.log" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "re-measured by me: protected_paths_l3 n diff = []; one prompt path (.aai/SKILL_PR.prompt.md); AGENTS.md absent; corpus 314941 -> 315049 = 108; one added JUSTIFIED_ADDITIONS line, leading int 108; pin want_growth=2392; suite exit 0" }
      - { ac: Spec-AC-09, call: cannot-verify,
          citation: "close-time by design; follow-ups.mjs list --status all -> fu-dispatch-targets-closed-scope still open" }
      - { ac: Spec-AC-10, call: compliant,
          citation: "tests/skills/test-aai-close-work-item.sh:2704-2722 delivers all three AC clauses; BITE1 reproduced by me (main's pre-carve prompt -> exit 1 on needle 'other than 6'). The arm's assertion 3 and its comment are a separate code_quality defect (P1-1), not an AC gap" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-close-work-item.sh, line: 2724,
          issue: "Assertion 3 counts occurrences of the literal 'REVERT the flip' and its comment asserts as FACT that an inverting decoy 'cannot avoid' a second such trigger. The claim is false, the assertion protects nothing assertions 1-2 do not already cover, and it reddens on a lawful edit.",
          failure_scenario: "Reproduced by me in a disposable detached worktree at 5eb5ce4: (a) D-A decoy wraps both pinned sentences in 'SUPERSEDED WORDING, DO NOT FOLLOW' and states 'undo the flip ... exit 6 INCLUDED' -> arm exits 0, the exact F-1 hazard ships green; (b) D-B adds a lawful clarifying cross-reference inside step 5c -> arm exits 1 (found 2); (c) BITE1 (main's pre-carve prompt) fails on assertion 1's needle only, so assertion 3 adds zero AC-required bite. The false sentence is in a tracked file and in 5eb5ce4's commit message." }
      - { rank: NON-BLOCKING, file: .aai/scripts/close-work-item.mjs, line: 1207,
          issue: "planStateReconcile's `skip()` returns commands: [] / echo: [], so a reason raised by the SECOND arm silently discards a command the FIRST arm already planned. D3 requires the WARN to echo 'the exact state.mjs commands an operator or the orchestrator must run'; on this path it echoes none.",
          failure_scenario: "Reproduced: STATE with a healthy active_work_items entry for the closing ref and current_focus.type outside the mirrored enum -> --dry-run reports severity skip, commands []. The set-phase the operator must run to unstick the scope is never printed; the next tick then halts at the new closed-focus guard with no recovery command on the record. Symmetric in the other direction (a bad work-item phase vetoes a healthy focus arm)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/close-work-item.mjs, line: 1074,
          issue: "RECONCILE_PHASES / RECONCILE_FOCUS_TYPES duplicate state.mjs's PHASES / FOCUS_TYPES with no drift guard. They match today (verified), but nothing fails if state.mjs gains a value.",
          failure_scenario: "state.mjs adds a focus type (e.g. intake_bug). Every close whose current_focus carries it takes the skip arm -> combined with the finding above, a perfectly healthy STATE gets no reconcile and no echoed command, silently, forever." }
      - { rank: NON-BLOCKING, file: .aai/scripts/close-work-item.mjs, line: 1388,
          issue: "statePlan is computed pre-write; applyStateReconcile runs after the doc writes, self-verify, pruneBriefs, four best-effort regens and the friction capture. The plan replays `--phase <value read at plan time>`.",
          failure_scenario: "A concurrent state.mjs writer advancing the item's phase inside that multi-second window has its advance overwritten by the reconcile's stale --phase. Narrow (STATE is single-writer by discipline) but unguarded and untested." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-close-leaves-state-stale.md, line: 429,
          issue: "The Edge cases bullet claims 'TEST-005 asserts the new verdict explicitly' for a closed focus with a required-but-unsatisfied review. The delivered TEST-005 (test_046) has no such arm — all seven cases run review.required: false.",
          failure_scenario: "The behaviour is correct (I probed decide() directly: needs_llm rule 6 closed_focus_stale_state), but at close the Spec-AC-05 Evidence cell would cite a test that does not cover the case the spec says it covers — a false record of the exact class this ride removes." }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 0,
          issue: "The spec_amendment record's `authority` still carries the 'NOT an owner decision' argument that round-3 F-14 found true-but-incomplete. The correction lives only in the spec's addendum; the append-only ledger carries no pointer to it.",
          failure_scenario: "A reader auditing decisions.jsonl alone (the ledger is the durable authority record) never learns that AUTONOMOUS_LOOP.md:25 assigns scope changes to HITL and that prior sign-off was not obtained." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-close-work-item.sh, line: 2709,
          issue: "F-12 residual (inherited): assertions 1-2 still redden on three meaning-preserving edits (D-C1 'other than exit 6', D-C2 'commands', D-C3 'means that the close STOOD').",
          failure_scenario: "Ordinary copy-editing of step 5c turns the suite red with no semantic change. Reduced from round 3 (reflow now tolerated), not eliminated." }
  cannot_verify:
    - { claim: "Spec-AC-09 registry outflow (fu-dispatch-targets-closed-scope -> done, resolved_by this scope)",
        closes_with: "the close ceremony's own follow-ups.mjs resolve; both entries still read open at review time, by design" }
    - { claim: "the 'owner's standing autonomy mandate' the F-14 addendum acts under",
        closes_with: "an owner artifact (decision record or explicit ship-checkpoint confirmation); asserted in prose only" }
    - { claim: "reconcile correctness under a genuinely concurrent state.mjs writer",
        closes_with: "a concurrency arm (two writers, one window) — no test exercises it; see the plan/apply TOCTOU finding" }
    - { claim: "post-close behaviour when the close ran in a linked worktree (D6)",
        closes_with: "an end-to-end worktree close; only the advisory string is asserted, the main-checkout staleness residual is named in the spec, not tested" }
  overall: fail
```

## 1. What I ran (command / exit / observation)

| # | Command | Exit | Observation |
|---|---|---|---|
| 1 | `env -u AAI_ROLE bash tests/skills/test-aai-close-work-item.sh` | 0 | ALL TESTS PASSED, incl. TEST-051..055 |
| 2 | `env -u AAI_ROLE bash tests/skills/test-aai-orchestration-dispatch.sh` | 0 | incl. TEST-046/047 |
| 3 | `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh` | 0 | TEST-012 pin 2392 |
| 4 | `node .aai/scripts/spec-lint.mjs --path <spec>` | 0 | `LINT PASS: no structural findings` |
| 5 | `node .aai/scripts/docs-audit.mjs --check --strict --no-event` | 0 | `Verdict: CLEAN` |
| 6 | `node .aai/scripts/check-test-registration.mjs` | 0 | no orphan test functions |
| 7 | `shasum -a 256 .aai/scripts/close-work-item.mjs` | 0 | `7e875729…6060` = the single allowlisted new hash (`grep -c` -> 1) |
| 8 | `/bin/bash -c 'cat .aai/*.prompt.md \| wc -c'` at HEAD vs main blobs | 0 | `315049` vs `314941` -> **delta exactly 108** |
| 9 | `git diff main..HEAD -- tests/skills/lib/prompt-diet-ledger.sh` | 0 | **exactly one** added `JUSTIFIED_ADDITIONS` line, leading integer `108`, zero removals |
| 10 | `protected_paths_l3` (8 entries) ∩ `git diff --name-only main...HEAD` | — | `[]`; prompt paths in diff = `['.aai/SKILL_PR.prompt.md']`, `.aai/AGENTS.md` absent |
| 11 | `head -c <main size> <file> \| cmp -` for `decisions.jsonl` / `EVENTS.jsonl` | 0 | main is a **byte-exact prefix** of HEAD in both (HAZ-LEDGER honored) |
| 12 | `node .aai/scripts/tdd-evidence-check.mjs --red <3 logs>` | 0 | all three `ACCEPTED (product_red)` |
| 13 | `node .aai/scripts/follow-ups.mjs list --status all` | 0 | `fu-dispatch-targets-closed-scope` open (close-time), `fu-setfocus-keeps-stale-spec-path` open, `fu-closeworkitem-pin-tail-wording` P3 open |
| 14 | decoy probes in a disposable detached worktree (`git worktree add --detach` … `git worktree remove`) | see §2 | control 0, D-A 0, D-B 1, BITE1 1 |
| 15 | `close-work-item.mjs --dry-run` against a hand-built STATE in a second disposable worktree | 0 | control: severity `apply`, both commands; probe: severity `skip`, `commands: []` (§3) |

Shipping tree after every probe: `git status --porcelain` -> `M docs/ai/tests/test-runs.jsonl` only. Both worktrees removed with a targeted `git worktree remove` (HAZ-WORKTREE); no restoring git command was run on a tracked file (HAZ-RESTORE); the mutated `SKILL_PR.prompt.md` lived only in the worktree copy and was `cmp`-verified byte-identical to the shipping file before removal.

## 2. RULING ON ASSERTION 3 — **net-negative; delete it. P1-1, BLOCKING.**

The dispatch asked me to reproduce at least one of the validator's decoys before ruling. I reproduced three, of my own construction, plus a control.

| Probe | What it does | Expected if assertion 3 is a structural pin | Actual |
|---|---|---|---|
| control | unmutated worktree @ `5eb5ce4` | pass | **exit 0** |
| **D-A** | both pinned sentences kept **verbatim** under `SUPERSEDED WORDING, DO NOT FOLLOW — the withdrawn 2026-08 draft read: "…"`, then `CURRENT RULE (supersedes the above): if close-work-item.mjs exits non-zero for ANY reason, exit 6 INCLUDED, undo the flip and restore the pre-flip AC table before anything else.` | **red** — this is the F-1 hazard, live | **exit 0 — PASSES** |
| **D-B** | one lawful clarifying line added inside step 5c: `Reminder (cross-ref for reviewers): the ONLY exit on which you REVERT the flip is a non-zero exit other than 6; exit 6 is the carve described above.` | green — the carve is strengthened | **exit 1**, `must contain EXACTLY ONE 'REVERT the flip' trigger (found 2)` |
| **BITE1** | `git show main:.aai/SKILL_PR.prompt.md` (pre-carve blanket rule) | red | **exit 1**, and the **only** `FAIL` line is assertion 1's `needle: 'other than 6'` |

Three conclusions, each from a command I ran:

1. **The claim in the tracked file is false.** `tests/skills/test-aai-close-work-item.sh:2730-2732` states: *"What the decoy cannot avoid is restating the REVERT trigger a SECOND time to make that current rule operative, so step 5c must carry EXACTLY ONE such trigger."* D-A avoids it in one edit by writing "undo the flip". `5eb5ce4`'s commit message carries the same claim. Two more false sentences sit at `:2698-2700`: *"a meaning-preserving reword … cannot redden it either — only dropping or inverting the substance can"* — meaning-preserving rewords D-C1/C2/C3 **do** redden it (round 4), and inverting the substance (D-A) **does not**. Both halves of that sentence are wrong.
2. **Assertion 3 buys nothing.** BITE1 shows assertion 1 alone catches the deletion case Spec-AC-10 mandates; assertion 2 alone catches the other half. Assertion 3 fires only on a decoy that voluntarily reuses the pinned verb — the single shape round 3 happened to write. Every synonym walks through.
3. **Assertion 3 costs a real false positive.** D-B is exactly the kind of edit a maintainer makes on the step this arm protects, and it turns the suite red.

**Is it salvageable?** Not cheaply, and not in the direction the validator sketched. `assert_payload_not_contains` on `SUPERSEDED` / `DO NOT FOLLOW` / `for ANY reason` / `exit 6 INCLUDED` is the same lexical game one move later — D-A2 ("HISTORICAL NOTE (no longer operative)" / "WHAT TO ACTUALLY DO") already dodges that vocabulary — and it *adds* false-positive surface, because a step legitimately using the word "superseded" would redden. **The assertion that would actually pin withdrawal is not a string assertion at all**: step 5c would have to carry the exit→action mapping in a machine-readable form (a small fenced table the arm parses, asserting `6 -> keep flip` and `other non-zero -> revert`), so a second contradicting rule has nowhere to live that the parser does not see. That costs prompt-corpus bytes this scope's Spec-AC-08 budget does not have, and is successor work, not a same-ride fix.

**Why BLOCKING and not advisory.** Three reasons, weighed explicitly:
- The repo's own code-quality rubric in `.aai/SKILL_CODE_REVIEW.prompt.md` makes a test asserting a universal negative it does not prove a BLOCKING finding — *"rename it or prove the negative"*. I disproved the negative with a one-line decoy.
- This scope's entire subject is a ceremony that leaves a false record behind. Shipping a **demonstrably false factual claim in a tracked test file**, discovered before merge, on the ride that exists to remove that defect class, is not a residual — it is the defect.
- The fix is free: test-only, no prompt bytes, no movement of the `close-work-item.mjs` hash the ride just pinned, no AC affected (Spec-AC-10 stays MET on assertions 1-2, proved by BITE1), and both required bites survive.

**Exact minimal edit** (`tests/skills/test-aai-close-work-item.sh`):

- **Delete lines 2724-2739** — the whole `# Assertion 3 (F-11)` comment block, `revert_needle` / `revert_stripped` / `revert_count`, the `[[ … -eq 1 ]] || log_fail …`, and the trailing blank line.
- **Replace lines 2697-2700** (the tail of the preceding comment) with the true statement, e.g.:

```
  # exact sentence, so a pure line reflow cannot redden it. RESIDUAL, stated
  # plainly rather than papered over: this arm detects DELETION of the carve
  # (Spec-AC-10's requirement), never WITHDRAWAL of it — a decoy that keeps
  # both sentences under a "SUPERSEDED, DO NOT FOLLOW" banner and states an
  # inverted rule in other words ("undo the flip") passes. Pinning withdrawal
  # needs a machine-readable exit->action mapping in step 5c, not a string
  # count; that is successor work.
```

- Optionally reword the header comment at `:2682` (`pinned as substance, not a surviving token`) to `pinned against DELETION of either half`, so the file's own summary matches what it does.

The remediation commit message should state that `5eb5ce4`'s claim is withdrawn — the commit message itself cannot be corrected without a history rewrite, so the withdrawal has to live in the successor commit and in this report.

After the edit, re-run `env -u AAI_ROLE bash tests/skills/test-aai-close-work-item.sh` (expect 0) and re-prove BITE1/BITE2 against `main`'s pre-carve prompt in a disposable worktree (expect exit 1 on assertion 1 and on assertion 2 respectively).

## 3. Production code, read end to end

### close-work-item.mjs reconcile

**Failure taxonomy matches the code on every path.** `runStateReconcile` (`:1270-1290`) is the single classifier and is shared by both success tails, so the two cannot diverge: `severity none -> 0`; `severity skip -> emitStateReconcileWarn + 0`; `failedAt === 0 -> WARN + 0`; `failedAt > 0 -> PARTIAL block + 6`; `failedAt === -1 -> 0`. `failedAt` is assigned in exactly one place, the `catch` at `:1228-1231`. There is no path that returns 6 without `applied > 0`.

**Exit 6 can never fire with the close not durable.** Both call sites are provably post-durability:
- `:1473` — reached only after the `!anyMutationTotal` short-circuit's own `selfVerify(refs)` returned zero problems (`:1463-1468` exits 1 otherwise). The docs were already closed before this run started.
- `:1552` — reached only after the `try` block completed, which means `selfVerify` returned clean (a non-empty `problems` rolls back and exits 1 at `:1517`) and no exception escaped (the `catch` rolls back and exits 1 at `:1527`).

**The reconcile is outside the rollback scope, in both directions.** It is lexically after the `try`/`catch` on the write path and lexically before it on the short-circuit path — the tail the short-circuit takes never enters the block at all. So the load-bearing invariant holds on both tails; only the *wording* in the exit-contract header and the pin entry is imprecise, which is the already-filed `fu-closeworkitem-pin-tail-wording` (P3) and is correctly deferred.

**No raw STATE write.** `/usr/bin/grep -n "writeFileSync" .aai/scripts/close-work-item.mjs` -> three sites: `:1009` (rollback restore), `:1498`, `:1501` (doc/product-doc mutation). None is `docs/ai/STATE.yaml`. Article 6 intact.

**`loadState` cannot hard-crash the close.** `loadState` has exactly two `fail()` paths — file-not-found and duplicate top-level keys — and `planStateReconcile` pre-checks both (`fs.existsSync` at `:1128`, `duplicateKeys` at `:1143`). The comment claiming the duplicate-key branch is "provably unreachable from here" is **true**, verified against `.aai/scripts/lib/state-engine.mjs:45-56`.

**The tail functions cannot swallow the reconcile.** `regenerateOverviewBestEffort`, `regenerateUserguideRollupBestEffort`, `regenerateDocsHubBestEffort`, `regenerateFactoryReportBestEffort` and `captureRemediationFriction` are each internally `try`/`catch`-wrapped, so none can throw past them into the module-level catch and skip `runStateReconcile` silently.

**Where it is wrong (Q-2, reproduced).** `skip()` at `:1123` hard-codes `commands: []` / `echo: []`, and `:1207` returns it whenever *either* arm raised a reason — discarding a command the *other* arm already planned. Probe, in a disposable worktree with a hand-built STATE:

```
control (current_focus.type: intake_issue):
  "severity": "apply",  commands: [ set-phase --ref … --status done --path …,
                                    set-focus --type intake_issue --ref … --path … ]
probe   (current_focus.type: intake_bug):
  "severity": "skip",
  "reason": "current_focus.type \"intake_bug\" is absent/outside the CLI's type enum — skipping the STATE reconcile",
  "commands": []
```

The work item still needs `status: done` and the operator is told nothing about it. D3 promises the WARN "echoes the exact `state.mjs` commands an operator or the orchestrator must run"; here it echoes none. Spec-AC-03's own wording ("echoing every *planned* command") is satisfied vacuously, which is why I call the AC compliant and the code defective rather than the reverse. Minimal fix, for the successor that already has to re-pin the hash: `const skip = (reason, planned = []) => ({ severity: 'skip', reason, statePath, commands: [], echo: planned });` and `if (reason !== null) return skip(reason, echo);`.

### orchestration-dispatch.mjs closedFocus guard

**Rules 4a/4b cannot be starved.** `const closedFocus` is declared at `:450`, strictly after the 4a and 4b blocks return, and neither block reads it. `test_046` cases 6 and 7 pin the precedence (`4a` no_action, `4b` Metrics Flush) on snapshots where `closedFocus` would be true. I probed the one reachable state the spec flags as a knock-on — closed focus, `review.required: true`, `status: not_run` — and got `{"verdict":"needs_llm","rule":"6","reasons":["closed_focus_stale_state"]}`: a flagged halt where the pre-change code dispatched Planning. Strictly better; rule 13 was already unreachable for that state before this change.

**`close_event_superseded_by_reopen` cannot be computed from a foreign ref.** The scan's `if (!refMatches(e.ref, focusRef)) continue;` gates both indices, and `refMatches` (`:127-130`) is exact equality or a `/`-separated component match — no substring looseness. Nothing about the new field widens that gate.

**A truncated EVENTS file degrades to the pre-change behaviour, never worse.** Unparseable lines are skipped by the existing `catch` at `:958`; the ordinals are line indices, so skipped lines never reorder the parsed ones. A truncated final `work_item_closed` would clear `close_event_present` — which disables the new guard and restores exactly today's rule 5/6 Planning verdict, and equally affects the pre-existing rule 4b. Not a new failure mode.

**Additivity holds.** The new `else if` branch matches only `doc_lifecycle`, an event name no other branch in the chain claims, so `phase_confirmed` / `validation_verdict` handling is byte-equivalent. The `!== true` polarity makes a legacy snapshot lacking the field behave as "not superseded" (pinned by `test_046` case 5).

## 4. The pin re-affirmation — verified true, clause by clause

`tests/skills/lib/close-work-item-pin.sh:40`. This is a signed human statement; I checked every clause against the code rather than against the validation reports.

| Clause | Verified |
|---|---|
| hash `7e875729…6060` | `shasum -a 256` on the working file matches exactly; `grep -c` in the pin file -> 1 |
| "adds planStateReconcile/applyStateReconcile" | present at `:1105` / `:1220` |
| "writing ONLY through the sanctioned state.mjs CLI (set-phase/set-focus), never a raw STATE byte write" | true — the only `writeFileSync` sites are the doc/rollback ones; the two command shapes are `set-phase` and `set-focus` |
| "DELIBERATELY WIDENS the exit contract 0/1/2/3/4/5 to include 6" | true and correctly framed as deliberate; the widening is what the D5 freeze exists to force a human to see |
| "a NAMED PARTIAL where the close itself STOOD: docs already flipped, close events already emitted, self-verify already CLEAN before this exit is ever reached" | true on both call paths (see §3) |
| "the D6 snapshot/rollback transaction and its four best-effort regen calls are UNTOUCHED" | true — `git diff main..HEAD` touches neither the `try` body, `rollback()`, nor the four regen calls |
| "no --resolves flag, no follow-ups.mjs invocation, no decisions.jsonl reference added" | `grep -n -- "--resolves\|follow-ups.mjs\|decisions.jsonl" .aai/scripts/close-work-item.mjs` -> no match |
| "runs STRICTLY AFTER the existing try/catch" | **imprecise** on the D6.2 short-circuit tail — already known, already filed as `fu-closeworkitem-pin-tail-wording` (P3, in `decisions.jsonl`), with the deferral reasoning recorded in the spec Notes. The invariant the pin exists to protect (outside the rollback transaction) is true on both tails |

The re-affirmation is honest. The one imprecision is disclosed, filed, and does not touch a load-bearing claim.

## 5. The spec amendment — additive with disclosure, and the reasoning holds

Verified mechanically: `SPEC-FROZEN: true` is preserved (`:16`); no original sentence was rewritten in place — D3's exit-6 bullet keeps its wrong clause **visible** and appends "The clause … was WRONG and is withdrawn" (`:165-168`); Spec-AC-08's Notes cell quotes the frozen original verbatim before stating the narrowing; Verification step 4 and Test Plan TEST-010 do the same. That is withdrawal-in-place, not silent replacement — the correct shape.

**The trade argument holds.** The two options really were mutually exclusive (keep the byte count and ship the false-record hazard, or fix the prompt and move the spec), and the amendment picks the one that protects what Spec-AC-08 exists to protect. Cost is stated in measured units (108 B, one ledger entry, one pin move) rather than in adjectives. The zero-byte target is narrowed to a byte-exact carve, so the AC stays falsifiable in both directions — a later scope adding 109 B to `SKILL_PR` fails it just as a scope touching `AGENTS.md` does.

**Spec-AC-08 as amended is measurable and honest.** Five conjuncts, all of which I re-measured independently (§1 rows 8-10) and all of which are true at HEAD. It is stronger than the frozen original in one respect: the original pinned a *direction* (zero growth) for a corpus with zero headroom; the amendment pins an *exact number*.

**The F-14 addendum discloses rather than retro-authorizes.** `:37-45` names `.aai/system/AUTONOMOUS_LOOP.md:25`, concedes the widening IS a scope change, states that canon assigns it to HITL, and says plainly that prior sign-off was **not** obtained and that the owner may reverse it. "Standing autonomy mandate" appears only as what the orchestrator acted under, immediately qualified. That is a disclosure. My one reservation is Q-6 below: the disclosure lives in the spec, while the argument it corrects lives in the append-only `decisions.jsonl`, with no pointer from the ledger to the correction.

**Spec-AC-10 as added.** Measurable and honest, and — importantly — it does **not** claim inversion-resistance. That is why P1-1 is a code_quality defect, not an AC failure: the arm meets its AC and lies about what meeting it buys.

## 6. Ledger and governance

- `JUSTIFIED_ADDITIONS`: **exactly one** entry added this ride (`git diff … | grep -c '^+JUSTIFIED_ADDITIONS'` -> 1, zero removals). Its leading integer is `108`, which equals the measured corpus delta — measured, not padded. Its prose names the file, the cause (F-1), the before/after byte counts, and the pin move.
- TEST-012 pin: `tests/skills/test-aai-prompt-diet.sh:721` -> `local want_growth=2392` = 2284 + 108. Suite exit 0.
- `decisions.jsonl`: two new records, both parse as valid JSON, both truthful against the artifacts (the follow-up's deferral reasoning matches the spec Notes and the registry entry exists; the amendment record's finding/decision/cost match the spec and the measured delta). `main` is a byte-exact prefix of HEAD (HAZ-LEDGER).
- `EVENTS.jsonl`: one appended line, a `doc_lifecycle draft -> implementing` for the spec. Byte-exact prefix preserved.
- `docs/INDEX.md`: regenerated output only (date + the two new draft/active rows). No hand edit.
- Prompt-corpus governance (per LEARNED): one edited `.aai` prompt, one diet-ledger entry, one TEST-012 bump. `ORCHESTRATION.prompt.md` untouched (its zero-byte omission is deliberate and recorded in the spec Notes with the alternative costed at ~29 B).

## 7. Findings, severities and dispositions

| ID | Rank | Where | Disposition |
|---|---|---|---|
| **P1-1** | **BLOCKING** | `tests/skills/test-aai-close-work-item.sh:2694-2700, 2724-2739` — assertion 3 plus three false sentences | **remediate-in-tree** before PR. Exact edit in §2. Reproduced by me (D-A pass, D-B red, BITE1). Also withdraws `5eb5ce4`'s commit-message claim in the successor commit message |
| Q-2 | NON-BLOCKING (P2) | `.aai/scripts/close-work-item.mjs:1123, 1207` — `skip()` discards already-planned commands; WARN echoes nothing | **successor-item** — bundle with `fu-closeworkitem-pin-tail-wording`, which already forces the allowlist re-pin and the two consumer-suite re-proofs. Fixing it here would move the hash this ride just pinned for a second time |
| Q-3 | NON-BLOCKING (P3) | `.aai/scripts/close-work-item.mjs:1074-1076` — mirrored enums, no drift guard | **successor-item**, same bundle. Cheap form: one test arm comparing the two literal lists (test-only, no hash move) |
| Q-4 | NON-BLOCKING (P3) | `.aai/scripts/close-work-item.mjs:1388` vs `:1552` — plan/apply TOCTOU on `--phase` | **accepted residual**: STATE is single-writer by discipline, no bite observed, and no record is left false by it. Named here so it is on the durable record |
| Q-5 | NON-BLOCKING (P3) | `docs/specs/…:429` Edge cases — "TEST-005 asserts the new verdict explicitly" is not delivered | **remediate-in-tree** (preferred): one more `decide()` case in `test_046` with `review: { required: true, status: 'not_run' }` asserting rule 6 `needs_llm closed_focus_stale_state` — ~10 lines, test-only, no hash move. Alternative: the close must not cite TEST-005 for that bullet |
| Q-6 | NON-BLOCKING (P3) | `docs/ai/decisions.jsonl` — the ledger's `authority` argument is uncorrected in-ledger | **remediate-in-tree**: append one record (append-only-safe) pointing at the spec's F-14 addendum, so the ledger alone tells the whole story |
| Q-7 | NON-BLOCKING (P3) | `tests/skills/test-aai-close-work-item.sh:2709-2722` — F-12 residual, three meaning-preserving edits still redden | **accepted residual**: assurance-strength/maintenance only, no bite observed, no false record left once P1-1's comment is corrected |
| F-13 | NON-BLOCKING (P3, orchestrator-owned) | `docs/ai/briefs/close-leaves-state-stale.md:49-50, :67-69` still carry the withdrawn zero-byte contract | **close-ceremony / before the next dispatch**: refresh both sites or delete the brief. Gitignored, so outside this diff, but a live hazard for any further dispatch on this ride |
| F-7 | close-ceremony obligation | `CHANGELOG.md` has no `## [unreleased] — <title>` entry for this scope | **close-ceremony** (orchestrator, at PR time), as the dispatch instructs. Note: writing it re-opens F-15 — `docs/ai/STATE.yaml:440-441`'s review scope must gain `CHANGELOG.md` in the same step or the scope list stops matching the diff |
| INFO | — | The carve sits inside a parenthetical that interrupts the `FLIP THE AC TABLE FIRST` bullet mid-sentence (`.aai/SKILL_PR.prompt.md:224-230`) | Pre-existing on `main`; inherited, not created. Straightening it costs corpus bytes outside Spec-AC-08's carve. No action |

No coaching attempt to record: the dispatch named the open question and demanded independent reproduction rather than pre-rating it, and I reviewed the full scope regardless.

## 8. Next steps

1. Apply the §2 edit (test-only). Re-run the close-work-item suite -> expect 0; re-prove BITE1/BITE2 in a disposable worktree.
2. Decide Q-5 and Q-6 (both cheap, both in-tree, both remove a claim the artifacts do not support).
3. Re-review is a single pass on the changed arm; every other verdict in this report stands on byte-identity.
4. At close: CHANGELOG heading + STATE scope line (F-7/F-15), brief refresh or deletion (F-13), and the Spec-AC Evidence cells — Spec-AC-05's must not cite a TEST-005 arm that does not exist unless Q-5 is remediated first.
