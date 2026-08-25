# Code review — close-leaves-state-stale, ROUND 2 (fresh reviewer, post-remediation)

- ref_id: `close-leaves-state-stale`
- branch: `fix/post-close-state-truth` @ `fc788d4`
- scope: `git diff main..HEAD` (14 files, 11 commits `e23d4f2..fc788d4`); primary attention on the remediation commit `fc788d4`
- spec: `docs/specs/SPEC-0153-spec-close-leaves-state-stale.md` (SPEC-FROZEN, amended post-freeze 2026-08-25; 10 Spec-ACs, all rows `planned` per VALIDATION rule 8a — re-checked, still all `planned`)
- prior round: `docs/ai/reviews/review-20260825T040439Z-close-leaves-state-stale.md` (FAIL on P1-1)
- reviewer: fresh dispatched subagent, read-only on implementation files; every ruling below is from a command I ran myself
- started_utc: 2026-08-25T04:24:37Z
- ended_utc: 2026-08-25T04:38:48Z (captured from `date -u` at commit time)

```yaml
review:
  scope: main..HEAD (fix/post-close-state-truth @ fc788d4)
  spec: docs/specs/SPEC-0153-spec-close-leaves-state-stale.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/close-work-item.mjs:1120-1211 (planStateReconcile, byte-identical to the round-1 reviewed tree) + test_051; suite exit 0" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/close-work-item.mjs:1473 short-circuit tail + test_053 (run3 asserts byte-identical STATE and no WARN); suite exit 0" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "runStateReconcile :1270-1290 + test_054 arms a/b/c (WARN / WARN / PARTIAL exit 6, '1 of 2' + remaining set-focus echoed); Q-2 below is a code defect on a path the AC's own wording does not reach" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "execFileSync at :1226 passes no env key -> AAI_ROLE inherited; test_054 arm a; suite exit 0" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/orchestration-dispatch.mjs:450 (closedFocus), :453 and :473 (the ONLY two rule-5/6 Planning returns, both guarded) + test_046 cases 1-8; case 8 bite-proved by me with two independent mutations (MUT-A, MUT-B) in a disposable worktree" }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/scripts/orchestration-dispatch.mjs:932-971 (unchanged by fc788d4) + test_047 part B; suite exit 0" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "three RED transcripts under docs/ai/tdd/ (state-reconcile, closed-focus-guard, test055), one per new suite ARM. The case-8 CASE added by fc788d4 has no transcript of its own — see R2-6 for why arm-granularity is the only coherent reading of this AC (TEST-005's own description mandates negative-control cases that PASS pre-change) and for the mutation proof that stands in for it" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "re-measured by me at fc788d4: protected_paths_l3 (8 entries) n diff = []; prompt paths in diff = ['.aai/SKILL_PR.prompt.md']; .aai/AGENTS.md absent; corpus 314941 -> 315049 = delta exactly 108; one added JUSTIFIED_ADDITIONS line, leading int 108, zero real removals; pin want_growth=2392; prompt-diet suite exit 0. fc788d4 itself touches zero .aai bytes" }
      - { ac: Spec-AC-09, call: cannot-verify,
          citation: "close-time by design; fu-dispatch-targets-closed-scope still reads open at review time" }
      - { ac: Spec-AC-10, call: compliant,
          citation: "tests/skills/test-aai-close-work-item.sh:2704-2725. Both halves re-proved by me at fc788d4: BITE1 (main's pre-carve step 5c) -> exit 1 on needle 'other than 6'; BITE2 (exit-6 sentence deleted, everything else kept) -> exit 1 on needle 'Exit 6 means the close STOOD'. The AC does not claim inversion-resistance and the arm no longer claims it either" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-close-work-item.sh, line: 2682,
          issue: "The arm's header comment (':2682') and its log_pass line (':2727') still summarize TEST-055 as the carve being 'pinned as substance, not a surviving token', while the RESIDUAL comment 15 lines below now states the opposite limit (the arm pins DELETION, not WITHDRAWAL). The two sentences in the same function disagree in emphasis, and the log_pass wording is what lands in run logs and evidence transcripts.",
          failure_scenario: "A reader of a green run log (or of the file's header alone) concludes the substance of step 5c is pinned; my D-A decoy inverts that substance in one edit and the arm still exits 0. Not a false statement about the assertions themselves — 'substance' contrasts with the 'mention exit 6 in passing' case the last assertion rejects — but it overstates what a pass buys." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-orchestration-dispatch.sh, line: 3088,
          issue: "The new case-8 comment says the guard 'still wins over rule 13'. Rule 13 is not a contender for this snapshot in either tree: rule 6 precedes it, and rule 13 additionally requires validation pass while base() carries validation.status not_run. Round 1 recorded the same fact ('rule 13 was already unreachable for that state before this change').",
          failure_scenario: "A maintainer reading the case believes it pins a precedence contest between the D7 guard and the review dispatch. It does not — MUT-A (guard deleted) shows the pre-change verdict for this snapshot is rule 6 Planning, never rule 13. The assertion itself is correct and matches the spec; only the comment's mechanism claim is wrong." }
      - { rank: NON-BLOCKING, file: .aai/scripts/close-work-item.mjs, line: 1207,
          issue: "Q-2, inherited and unchanged (file byte-identical since 5eb5ce4, hash re-verified): planStateReconcile's skip() at :1123 hard-codes commands: [] / echo: [], and :1207 returns it whenever EITHER arm raised a reason, discarding a command the other arm already planned.",
          failure_scenario: "Round 1 reproduced it: healthy work-item arm + a current_focus.type outside the mirrored enum -> severity skip, commands []. The set-phase the operator needs is never echoed, and the next tick halts on the new closed-focus guard with no recovery command on the record." }
      - { rank: NON-BLOCKING, file: .aai/scripts/close-work-item.mjs, line: 1074,
          issue: "Q-3, inherited and unchanged: RECONCILE_PHASES / RECONCILE_FOCUS_TYPES mirror state.mjs PHASES / FOCUS_TYPES with no drift guard.",
          failure_scenario: "state.mjs gains a focus type; every close carrying it takes the skip arm and, combined with Q-2, produces no reconcile and no echoed command, silently." }
      - { rank: NON-BLOCKING, file: .aai/scripts/close-work-item.mjs, line: 1388,
          issue: "Q-4, inherited and unchanged: statePlan is computed pre-write and replayed after the doc writes / self-verify / regens (plan-apply TOCTOU on --phase).",
          failure_scenario: "A concurrent state.mjs writer inside that window has its phase advance overwritten by the stale --phase. Single-writer discipline makes it narrow; nothing guards or tests it." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-close-work-item.sh, line: 2704,
          issue: "Q-7, inherited and unchanged: assertions 1-2 still redden on three meaning-preserving edits (D-C1/C2/C3 from round 3/4).",
          failure_scenario: "Ordinary copy-editing of step 5c turns the suite red with no semantic change. The arm's comment no longer claims otherwise (that false half was deleted by fc788d4), so nothing on the record is false — only the maintenance cost remains." }
  cannot_verify:
    - { claim: "Spec-AC-09 registry outflow (fu-dispatch-targets-closed-scope -> done, resolved_by this scope)",
        closes_with: "the close ceremony's own follow-ups.mjs resolve; the entry still reads open at review time, by design" }
    - { claim: "the 'owner's standing autonomy mandate' the F-14 addendum and the new Q-6 ledger record both name",
        closes_with: "an owner artifact (a decision record or an explicit ship-checkpoint confirmation); asserted in prose only, in two places now" }
    - { claim: "reconcile correctness under a genuinely concurrent state.mjs writer (Q-4)",
        closes_with: "a two-writer concurrency arm; no test exercises it" }
    - { claim: "post-close behaviour when the close ran in a linked worktree (D6)",
        closes_with: "an end-to-end worktree close; only the advisory string is asserted" }
    - { claim: "full-framework sweep health at fc788d4",
        closes_with: "a FULL_RUN. I did NOT run the 20-minute sweep. Validation round 4 ran it green at 81/81 against 5eb5ce4 and the only change since is fc788d4, which touches two test files, decisions.jsonl and the regenerated docs/INDEX.md; I ran the six suites that consume those plus check-test-registration, all exit 0" }
  overall: pass
```

## 1. What I ran (command / exit / observation)

| # | Command | Exit | Observation |
|---|---|---|---|
| 1 | `env -u AAI_ROLE bash tests/skills/test-aai-close-work-item.sh` | 0 | `ALL TESTS PASSED` (incl. TEST-051..055) |
| 2 | `env -u AAI_ROLE bash tests/skills/test-aai-orchestration-dispatch.sh` | 0 | `All aai-orchestration-dispatch tests passed` (incl. TEST-046 case 8, TEST-047) |
| 3 | `env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh` | 0 | all passed |
| 4 | `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh` | 0 | all passed; pin `want_growth=2392` |
| 5 | `env -u AAI_ROLE bash tests/skills/test-aai-doc-numbering.sh` | 0 | all passed |
| 6 | `env -u AAI_ROLE bash tests/skills/test-aai-follow-ups.sh` | 0 | all passed |
| 7 | `node .aai/scripts/check-test-registration.mjs` | 0 | no orphan test functions |
| 8 | `node .aai/scripts/docs-audit.mjs --check --strict --no-event` | 0 | `Verdict: CLEAN` |
| 9 | `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0153-spec-close-leaves-state-stale.md` | 0 | `LINT PASS: no structural findings.` |
| 10 | `shasum -a 256 .aai/scripts/close-work-item.mjs` | 0 | `7e8757291b7b5e61d9aef3005f193361ff91f49575f3cb1ee4072a86ad696060`; `grep -c` in `tests/skills/lib/close-work-item-pin.sh` -> 1 |
| 11 | `git show --name-only --format= fc788d4` | 0 | `docs/INDEX.md`, `docs/ai/decisions.jsonl`, the two test files — **no production file** |
| 12 | `/bin/bash -c 'cat .aai/*.prompt.md \| wc -c'` at HEAD vs main blobs | 0 | `315049` vs `314941` -> **delta exactly 108** |
| 13 | `git diff main..HEAD -- tests/skills/lib/prompt-diet-ledger.sh` | 0 | one added `JUSTIFIED_ADDITIONS` line, leading int `108`, `grep -cE '^-[^-]'` -> **0 removals** |
| 14 | `protected_paths_l3` (8 entries) ∩ `git diff --name-only main...HEAD` (14 paths) | — | `[]`; prompt paths = `['.aai/SKILL_PR.prompt.md']`; `.aai/AGENTS.md` absent |
| 15 | `head -c <main size> <file> \| cmp -` for `decisions.jsonl` and `EVENTS.jsonl` | 0 | main is a **byte-exact prefix** of HEAD in both (HAZ-LEDGER honored) |
| 16 | `node -e` JSON.parse over every `decisions.jsonl` line | 0 | 537 JSON lines parse; the only non-JSON lines are the file's own 15-line `#` header (pre-existing convention). The appended record parses; keys `v,ts,actor,type,ref_id,amends,authority,finding,decision,source` |
| 17 | TEST-055 probes in a disposable detached worktree (control / BITE1 / BITE2 / D-A / D-B / REFLOW) | see §2 | 0 / 1 / 1 / 0 / 0 / 0 |
| 18 | TEST-046 probes in the same worktree (control / MUT-A / MUT-B) | see §3 | 0 / 1 / 1 |
| 19 | `git grep "cannot avoid restating\|only dropping or inverting\|EXACTLY ONE .REVERT"` | — | only the round-1 review report, which quotes them AS false. No withdrawn claim survives in any test file |
| 20 | AC table statuses in the spec | — | all 10 rows `planned` |

Worktree hygiene: one disposable worktree (`git worktree add --detach <scratch> HEAD`), every mutation written into that copy only, each probe reset with `git show <ref>:<path> > <path>` (a redirect, not a restoring git command — HAZ-RESTORE), both mutated files `cmp`-verified byte-identical to the shipping tree before teardown, and teardown by a targeted `git worktree remove` (HAZ-WORKTREE). Shipping-tree `git status --porcelain` after everything: `M docs/ai/EVENTS.jsonl`, `M docs/ai/tests/test-runs.jsonl` only — the EVENTS line is a pre-existing uncommitted `validation_verdict` append from 04:24:01Z that predates my session (see §6, note for close-prep), test-runs.jsonl is the suites' own append.

## 2. P1-1 — CLOSED, and the replacement comment survives sentence-by-sentence challenge

`fc788d4` deletes assertion 3 (the `revert_count -eq 1` check) and the two false comment sentences. I re-proved the whole arm from scratch rather than trusting the commit message.

| Probe | What it does | Expected | Actual |
|---|---|---|---|
| control | unmutated worktree @ `fc788d4` | pass | **exit 0** |
| **BITE1** | `git show main:.aai/SKILL_PR.prompt.md` (pre-carve blanket rule) | red | **exit 1**, `needle: 'other than 6'` |
| **BITE2** | HEAD's step 5c with ONLY the sentence `Exit 6 means the close STOOD: keep the flip; run the echoed remaining state.mjs command(s).` deleted | red | **exit 1**, `needle: 'Exit 6 means the close STOOD'`, exactly 1 FAIL |
| **D-A** | both pinned sentences kept **verbatim**, followed inside step 5c by `SUPERSEDED WORDING, DO NOT FOLLOW … CURRENT RULE (supersedes the above): if close-work-item.mjs exits non-zero for ANY reason, exit 6 INCLUDED, undo the flip …` | pass (that is the disclosed residual) | **exit 0** |
| **D-B** | round 1's lawful clarifying cross-reference, re-using the words `REVERT the flip` a second time | pass (the false positive is gone) | **exit 0** |
| **REFLOW** | the carve paragraph rewrapped across different line breaks, same words | pass | **exit 0** |

Now every sentence of the replacement comment (`:2694-2702`), challenged:

1. *"matched against a single whitespace-normalized string so a pure line reflow cannot redden this arm (F-12)"* — **true**, REFLOW probe.
2. *"this arm pins DELETION and pre-carve wording, not WITHDRAWAL"* — **true in both halves**: BITE2 proves deletion detection, BITE1 proves pre-carve detection, D-A proves withdrawal is NOT detected. Nothing here overclaims; it is the first statement in this file that matches what the assertions do.
3. *"a decoy that keeps the sentences verbatim under a 'superseded / do not follow' framing and states an inverted rule elsewhere in step 5c passes"* — **true**, D-A, and stated as a limitation rather than dressed up.
4. *"Pinning withdrawal would need a machine-readable exit->action mapping in step 5c, which costs corpus bytes the amended Spec-AC-08 does not budget (successor work)"* — a design judgement, and I looked for the cheap assertion the dispatch asked about. Every string-level guard I could construct (`assert_payload_not_contains` on `SUPERSEDED` / `DO NOT FOLLOW` / `for ANY reason` / `exit 6 INCLUDED`) is defeated by re-wording the banner — round 1 already exhibited D-A2 for that — and each one *adds* false-positive surface on a step that may legitimately use those words. **One counterexample exists and is worth naming**: a whole-block golden snapshot (byte-compare step 5c against a fixture) would pin withdrawal at zero prompt-corpus cost, because any inserted decoy changes the block. It is not cheap in the sense that matters here — it is strictly more brittle than the assertions F-12 was raised to loosen, i.e. this ride already rejected that direction on the record. So the sentence's *necessity* framing is a little strong, its *conclusion* (successor work, not a same-ride fix) is right. Filed as R2-5, INFO.

**The header and the log_pass are the one place where wording still runs ahead of the assertions.** `:2682` (`pinned as substance, not a surviving token`) and `:2727` (`carve pinned as substance: …`) were left unchanged; round 1 flagged the reword as optional. I do not call it BLOCKING: read in context the contrast is with a passing token mention (which the fifth assertion's own message names), the same function now carries the explicit WITHDRAWAL residual, no Spec-AC claims inversion-resistance, and the sentence makes no checkable universal-negative claim of the kind the rubric makes blocking (that sentence was deleted). It is still the last summary in the tree that a hurried reader can over-read, and the log_pass text is what lands in evidence transcripts — R2-1, remediate-in-tree at close-prep, comment-only.

## 3. Q-5 — the new test_046 case 8 asserts what the spec claims, and it bites

Spec `docs/specs/SPEC-0153-spec-close-leaves-state-stale.md:425-429`: *"A closed focus with a required-but-unsatisfied review reaches rule 6 today and gets Planning; under D7 it gets `needs_llm closed_focus_stale_state`. … TEST-005 asserts the new verdict explicitly."*

Case 8 (`tests/skills/test-aai-orchestration-dispatch.sh:3085-3099`) builds exactly that snapshot — `spec.frontmatter_status = 'done'`, `close_event_present = true`, `close_event_superseded_by_reopen = false`, `review = { required: true, status: 'not_run' }` — and asserts `verdict === 'needs_llm'`, `rule === '6'`, `role === null`, `reasons.includes('closed_focus_stale_state')`. That is the spec's sentence, clause for clause. **The spec sentence is now true; no further amendment is needed** — the Test Plan's TEST-005 row describes a set of cases without claiming exhaustiveness, so an added case does not contradict it.

Bite proof, mine, in the disposable worktree (control first, file restored by `git show … >` between runs and `cmp`-verified after):

| Probe | Mutation | Result |
|---|---|---|
| control | none | **exit 0** |
| **MUT-B** (targeted) | `if (closedFocus && !(s.review && s.review.required === true)) return needsLlm(…, '6')` — narrows the guard so only review-required states bypass it; cases 1-7 all carry `review.required: false` and are untouched | **exit 1**, `AssertionError: expected needs_llm, got dispatch ([])` — case 8's own message. Case 8 therefore carries INDEPENDENT bite, not bite borrowed from case 2 |
| **MUT-A** | the rule-6 `if (closedFocus) return needsLlm(…, '6')` line deleted outright | **exit 1** |

MUT-A also settles the mechanism question: with the guard gone this snapshot returns rule 6 **Planning**, not rule 13 — which is why the case comment's "still wins over rule 13" is wrong (R2-2). Rule 13 additionally requires `validation pass` and `base()` carries `validation.status: not_run`, so it was unreachable twice over.

Structural check backing Spec-AC-05's universal claim: `/usr/bin/grep -n "dispatchFor('Planning', s, '[56]')"` returns exactly two sites (`:454`, `:474`), each immediately preceded by its `if (closedFocus) return needsLlm(...)`. The "never gets rule 5/6 Planning" wording in the arm's `log_info` is therefore provable, not a subset claim.

## 4. Q-6 — the appended ledger record is valid, append-only, and points the right way

- **Valid JSON**: parses; 10 keys; `ts 2026-08-25T04:18:23Z`, `actor: remediation`.
- **Append-only**: `head -c $(wc -c < main-copy) docs/ai/decisions.jsonl | cmp -` -> identical. `main` is a byte-exact prefix of HEAD; exactly one line added by `fc788d4` (three across the branch).
- **Pointer accuracy**: `amends` names *"docs/ai/decisions.jsonl line 551 (ts 2026-08-25T01:52:00Z, type spec_amendment)"* — `sed -n '551p'` is exactly that record. `decision` names *"SPEC-0153-spec-close-leaves-state-stale.md lines 37-45, the '2026-08-25 addendum (round-3 F-14)' paragraph"* — the addendum runs `:37-44` (line 45 is the blank separator), and it does say what the pointer claims: it names `.aai/system/AUTONOMOUS_LOOP.md:25`, states the widening IS a scope change, that canon assigns it to HITL, that prior sign-off was not obtained, that it was disclosed in-session, and that the owner may reverse it. I checked the cited canon line: `sed -n '25p' .aai/system/AUTONOMOUS_LOOP.md` -> *"Resolves disputed decisions, scope changes, and high-impact risk decisions."* Every hop of the citation chain holds.
- **Not a retro-authorization**: the record's `authority` is its own provenance (*"code review Q-6, … remediated per dispatch"*), not a claim of owner approval; the `finding` says in plain words that no prior owner sign-off was obtained. It reads as a disclosure pointer, which is what Q-6 asked for. The phrase *"under the owner's standing autonomy mandate"* recurs here as the actor's stated basis — still unevidenced, still in my cannot_verify list, now in two artifacts instead of one.
- One nit (R2-4, INFO): the record is typed `spec_amendment` although it amends a *ledger record*, not the spec. A future query for `type: spec_amendment && ref_id: close-leaves-state-stale` now returns two records where one spec amendment occurred. No tool consumes the field today (`follow-ups.mjs` reads only `follow_up` / `follow_up_status`), and the record's own `amends` string is unambiguous, so this is cosmetic.

## 5. No regression from fc788d4

- `close-work-item.mjs` hash `7e8757291b7b5e61d9aef3005f193361ff91f49575f3cb1ee4072a86ad696060` — unchanged, allowlisted exactly once in `tests/skills/lib/close-work-item-pin.sh`.
- `orchestration-dispatch.mjs` — **not in `fc788d4`'s file list**; the commit's only touch of that surface is the test file. Production code byte-identical to the round-1-reviewed tree.
- Prompt corpus: `315049` at HEAD, `314941` at main, delta **108**; pin `2392`; one JUSTIFIED_ADDITIONS line, zero removals; `.aai/AGENTS.md` untouched. `fc788d4` adds **zero** prompt bytes.
- `protected_paths_l3` ∩ diff = `[]`.
- AC table: all 10 rows `planned`.
- Ledger prefixes: `decisions.jsonl` and `EVENTS.jsonl` both keep main as a byte-exact prefix.
- Suites 1-9 above all exit 0. **I did not run the 20-minute full framework sweep**; validation round 4 ran it green at 81/81 against `5eb5ce4`, and the only landing since is `fc788d4` (two test files + one ledger append + the regenerated `docs/INDEX.md` timestamp). I ran every suite that consumes those surfaces.

## 6. Round-1 findings, re-dispositioned at fc788d4

| Round-1 id | Status now | Basis |
|---|---|---|
| **P1-1** | **CLOSED** | Assertion 3 and both false sentences deleted; replacement comment true (§2); D-B false positive gone; BITE1/BITE2 still red; the withdrawn claims survive nowhere in the tree except the round-1 report that names them as false, and `fc788d4`'s message withdraws `5eb5ce4`'s claim explicitly |
| Q-2 | unchanged, still NON-BLOCKING (P2) | `close-work-item.mjs` byte-identical (hash re-verified); `skip()` at `:1123` still returns `commands: []` and `:1207` still returns it when either arm raised a reason. **successor-item**, bundled with `fu-closeworkitem-pin-tail-wording` (which already forces the allowlist re-pin) |
| Q-3 | unchanged, still NON-BLOCKING (P3) | mirrored enums at `:1074-1076`, no drift guard. **successor-item**, same bundle |
| Q-4 | unchanged, **accepted residual** | plan/apply TOCTOU; single-writer discipline, no bite observed, no false record. Recorded here for the durable record |
| Q-5 | **CLOSED (remediated)** | §3; the spec's `:429` claim is now true and bite-proved |
| Q-6 | **CLOSED (remediated)** | §4 |
| Q-7 | unchanged, **accepted residual** | assertions 1-2 untouched; the comment half that made it a false record was deleted by `fc788d4`, so the round-1 precondition for this disposition ("no false record left once P1-1's comment is corrected") is now satisfied |
| F-13 | still outstanding, orchestrator-owned | `docs/ai/briefs/close-leaves-state-stale.md` still carries the withdrawn zero-byte contract; gitignored, outside this diff, but a live hazard for any further dispatch on this ride |
| F-7 | still outstanding, **close-ceremony obligation** — confirmed, NOT blocking | `CHANGELOG.md` has `## [unreleased]` at `:12` and one unrelated titled entry at `:14`; nothing for this scope. Writing it re-opens F-15: `docs/ai/STATE.yaml:440-441`'s review scope must gain `CHANGELOG.md` in the same step |

Two close-prep notes I owe the orchestrator, neither blocking:
- `docs/ai/EVENTS.jsonl` carries an **uncommitted** `validation_verdict` append (`2026-08-25T04:24:01Z`, status pass) at review time. It must be staged with the close commit; dropping it re-creates the `EVENTS restore wipes close telemetry` failure.
- `docs/ai/STATE.yaml:441`'s review scope list does not name `docs/ai/reviews/…` — round 1's report is covered by `report_paths` (SKILL_PR treats scope-cited reports as expected companions) and this round-2 report will be too once the returned `set-code-review --report` runs.

## 7. Findings and dispositions (round 2)

| ID | Rank | Where | Disposition |
|---|---|---|---|
| R2-1 | NON-BLOCKING (P3) | `tests/skills/test-aai-close-work-item.sh:2682` header + `:2727` log_pass — "pinned as substance, not a surviving token" outruns what D-A shows the arm buys | **remediate-in-tree at close-prep** (comment/message-only, zero risk, no hash move, no prompt bytes): `pinned against DELETION of either half` in both places. Re-run `test-aai-close-work-item.sh` only; no re-review needed |
| R2-2 | NON-BLOCKING (P3) | `tests/skills/test-aai-orchestration-dispatch.sh:3088` — "still wins over rule 13" names a rule that is unreachable for this snapshot in both trees | **remediate-in-tree at close-prep**, same edit pass: e.g. "the closedFocus guard at rule 6 fires first — this snapshot got rule 6 Planning before D7 and gets needs_llm now; rule 13 is never reached". Assertion unchanged |
| R2-3 | INFO | `tests/skills/test-aai-close-work-item.sh:2694` — "Pipe-free throughout" while `joined=$(printf … \| tr \| tr)` uses two pipes | No action. The cited hazard (an assertion dying on its own payload) is unreachable through `printf \| tr \| tr` — `tr` consumes all input, so no SIGPIPE and no pipefail path; the claim is about the assertion helpers, which are pipe-free |
| R2-4 | INFO | `docs/ai/decisions.jsonl` last line — typed `spec_amendment` though it amends a ledger record; `lines 37-45` is really `37-44` | No action (append-only; a correction would be another line for a cosmetic type). Noted so a future `type` query is read with this in mind |
| R2-5 | INFO | `tests/skills/test-aai-close-work-item.sh:2701` — "would need a machine-readable exit->action mapping" is a necessity claim with one counterexample (whole-block golden snapshot) | No action. The counterexample is strictly more brittle than what F-12 loosened, i.e. already rejected on this ride's record; the sentence's conclusion (successor work) stands |
| R2-6 | INFO | no RED transcript under `docs/ai/tdd/` for the case-8 CASE added by `fc788d4` | No action, and Spec-AC-07 stays **compliant**: the AC's "every new suite arm" can only be read at arm/TEST-row granularity, because TEST-005's own spec description mandates negative-control cases (`close_event_present false still dispatches Planning`) that PASS against the pre-change tree by design. The arm `test_046` has its RED transcript (`red-orchestration-dispatch-closed-focus-guard.log`); case 8's non-vacuity is proved instead by MUT-A/MUT-B in §3. If the close ceremony wants case-level completeness in the Spec-AC-07 Evidence cell, cite this report rather than manufacturing a post-hoc "RED-first" log |
| Q-2 | NON-BLOCKING (P2) | `.aai/scripts/close-work-item.mjs:1123, 1207` | **successor-item** (bundle with `fu-closeworkitem-pin-tail-wording`) — carried from round 1, basis unchanged |
| Q-3 | NON-BLOCKING (P3) | `.aai/scripts/close-work-item.mjs:1074-1076` | **successor-item**, same bundle — carried |
| Q-4 | NON-BLOCKING (P3) | `.aai/scripts/close-work-item.mjs:1388` vs `:1552` | **accepted residual**: single-writer by discipline, no bite observed, no false record left — carried |
| Q-7 | NON-BLOCKING (P3) | `tests/skills/test-aai-close-work-item.sh:2704-2725` | **accepted residual**: assurance-strength/maintenance only, no bite, and no false record now that the comment half is deleted — carried |
| F-13 | NON-BLOCKING (P3, orchestrator-owned) | `docs/ai/briefs/close-leaves-state-stale.md:49-50, :67-69` | **close-ceremony / before the next dispatch**: refresh or delete the brief |
| F-7 | close-ceremony obligation | `CHANGELOG.md` | **close-ceremony** (orchestrator at PR time), with the F-15 STATE-scope coupling |

No coaching attempt to record: the dispatch named the open questions and demanded independent reproduction rather than pre-rating severity, and I reviewed the full `main..HEAD` diff regardless.

## 8. Verdict and next steps

**PASS** — `spec_compliance: pass`, `code_quality: pass`, `overall: pass`. P1-1 is genuinely closed, the replacement comment is the first statement in that file that matches the assertions, Q-5 and Q-6 are remediated and independently verified, and `fc788d4` moved no production byte.

1. Close-prep: the R2-1 + R2-2 comment corrections (one edit pass over two test files, re-run those two suites).
2. Close-prep: F-7 CHANGELOG heading + the F-15 STATE review-scope line in the same step; F-13 brief refresh/delete; stage the uncommitted `EVENTS.jsonl` validation_verdict append.
3. At close: Spec-AC-05's Evidence cell may now cite TEST-005 for the required-but-unsatisfied-review edge case (case 8); Spec-AC-07's cell should cite the three RED transcripts and, if it wants case-level completeness, this report's §3 mutation proof.
4. Then PR + close ceremony. No re-review is required for items 1-3.
