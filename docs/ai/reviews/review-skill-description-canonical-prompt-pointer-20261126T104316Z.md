# Code review (round 2): skill-description-canonical-prompt-pointer

```yaml
review:
  scope: "0cbb0394..084f53e0 (primary delta: commit 49661f08 remediation + 084f53e0 ledger), whole ride origin/main...HEAD (5f02b0e5...084f53e0) re-walked for the AC table; branch fix/skill-discovery-pointer"
  spec: docs/specs/SPEC-0318-spec-skill-description-canonical-prompt-pointer.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "live --check OK 42 (reviewer re-run inside the NB-1 repro consumer, rc 0); TEST-4130 independent reader enumerates every .claude/skills dir without an aai- filter (test-aai-harness-shims.sh:139), count=42" }
      - { ac: Spec-AC-02, call: compliant, citation: "sync-harness-skills.mjs:357-388 checkPointers D4 order unchanged by the delta; TEST-4131" }
      - { ac: Spec-AC-03, call: compliant, citation: "sync-harness-skills.mjs:309-315 unchanged; TEST-4132" }
      - { ac: Spec-AC-04, call: compliant, citation: "sync-harness-skills.mjs:364-367 unchanged; TEST-4133" }
      - { ac: Spec-AC-05, call: compliant, citation: "unchanged by the delta; TEST-4134" }
      - { ac: Spec-AC-06, call: compliant, citation: "sync-harness-skills.mjs:377 aai- scope (A6) + :379-382 marker SKIPPED; TEST-4135 incl. new deploy-notes / aai-no-pointer cases (test-aai-harness-shims.sh:1291-1300)" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-4136; reviewer consumer via aai-sync.mjs: --check rc 0 with a user skill present" }
      - { ac: Spec-AC-08, call: compliant, citation: ".aai/SKILL_SHIP.prompt.md:131-136 now five endings (a)-(e) per A6; TEST-4137 pin test-aai-downstream-autopilot.sh:279. Deviation: the AC row and the TEST-4137 plan row still say 'three legal endings'; A6 discloses the change" }
      - { ac: Spec-AC-09, call: compliant, citation: "park command text unchanged; TEST-4138" }
      - { ac: Spec-AC-10, call: compliant, citation: "no description changed in the delta; TEST-4139" }
      - { ac: Spec-AC-11, call: compliant, citation: "unchanged; TEST-4140" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/sync-harness-skills.mjs, line: 377,
          issue: "the A6 scope rule (startsWith 'aai-') disagrees with how the layer identifies its own wrappers elsewhere: aai-sync.mjs:667 treats aai-[a-z0-9-]+ AND NOT aai-project-* as layer-owned, and aai-sync.mjs:791 tells consumers to put project guidance in <tree>/aai-project-<topic>/SKILL.md; such a hand-written project skill still gets a false pointer DIVERGE",
          failure_scenario: "consumer installed by aai-sync.mjs follows the sync conflict advice and writes .claude/skills/aai-project-deploy/SKILL.md (no AAI-DYNAMIC-SKILL marker), runs --write then --check: exit 1 'DIVERGE pointer aai-project-deploy: description lacks the canonical pointer'. Repro: scratchpad/cr2-repro-aai-project-skill.sh (exit 0 = reproduced). Latent today (no vendored consumer caller of --check), bites as soon as fu-consumer-pointer-check-after-sync is built" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-harness-shims.sh, line: 1295,
          issue: "TEST-4135 is named 'the consumer-shaped exceptions are named, never silent' (spec D5 'named, never silently passed') yet its new case asserts the non-aai skill is passed with NO pointer line; the OK count line does not say how many skills were not checked",
          failure_scenario: "a reader of the --check output in a consumer with three own skills sees only 'OK: 42 wrapper description(s)'; nothing names the three skills as out of scope, contrary to D5's stated principle and the test's name" }
      - { rank: NON-BLOCKING, file: .aai/SKILL_SHIP.prompt.md, line: 132,
          issue: "ending (d) names 'the INPUT question for the need' but not the INPUT propose_maintenance ONE-menu (SKILL_SHIP.prompt.md:24-30), which round 1 NB-2 also named",
          failure_scenario: "ride-select answers propose_maintenance; the orchestrator prints the two-option menu and must end the turn; read strictly, that is not ending (a)-(e), so it runs ride-status and either picks option 1 itself (the menu asks the owner) or parks; a lenient reading of 'INPUT question' covers it" }
  cannot_verify:
    - { claim: "A model running /aai-ship obeys the five-ending END-OF-TURN INVARIANT (waits on (e) without re-dispatching, parks otherwise), so #593 does not recur", closes_with: "a recorded /aai-ship ride per harness that ends a turn on a background dispatch and resumes on its notification" }
    - { claim: "Ending (e) cannot strand a ride whose in-flight dispatch dies without a notification (validator NB-a)", closes_with: "a harness-level observation of a killed background subagent; the prompt cannot close it. The resume path (ride-status probe -> resume: loop) re-enters on the next /aai-ship and a dead dispatch wrote no STATE (single-writer), so re-dispatch on resume is safe" }
    - { claim: "Carried from round 1: non-Claude harnesses surface the suffix pointer; Codex listing truncation keeps it; Windows leg of the new harness-shims tests", closes_with: "hermes suite with AAI_HERMES_PYTHON, per-harness listing captures, hosted skill-suite Windows leg on the PR head" }
  overall: pass
```

security_relevant: false

## Scope

Round 2, dispatched by the orchestrator (rule 13) because remediation commit `49661f08` changed code reviewed at `0cbb0394`. Primary scope is `git diff 0cbb0394..084f53e0`: the `aai-` scope line in `.aai/scripts/sync-harness-skills.mjs`, two new TEST-4135 cases, END-OF-TURN INVARIANT endings (d)/(e) in `.aai/SKILL_SHIP.prompt.md` with the TEST-4137 pin, the N=687 -> 836 re-pins (prompt-diet ledger, TEST-012 `want_growth` and `rh_now`, pr-preflight, TEST-3278), amendment A6, and two decisions.jsonl lines (A6 amendment, `fu-consumer-pointer-check-after-sync`). The AC table was re-walked against the whole ride.

Dispatch handoff check: the dispatch named areas to look at (prefix escape, prefix consistency with sync prune and catalog) as questions, not as expected findings or severities; it did not pre-rate anything. No coaching recorded. It also noted A5 is accepted and the validator's 429 residual; both were judged independently below.

## Round-1 findings

- **NB-1 (user skills got a false pointer DIVERGE): closed as written.** The round-1 repro (`scratchpad/cr-repro-user-skill-pointer.sh`) now exits 1 (not reproduced): the consumer's `--check` is rc 0 with `deploy-notes` present. TEST-4135 pins both sides (non-`aai-` skill passes, `aai-no-pointer` still fails). The class is only partly closed, see NB-4.
- **NB-2 (invariant ambiguous on a pending dispatch / INPUT): closed for the dispatch case.** Ending (e) makes waiting legal and says not to re-dispatch, and "is not a park" replaces "is not a stop", so the duplicate-dispatch and false-park paths are both closed. The "ask for the need" ending is (d). The `propose_maintenance` menu is not named explicitly, see NB-6 (P3).
- **NB-3:** unchanged; accepted residual stands as recorded in round 1.

## Does the `aai-` scope let a shipped wrapper escape?

No, not in a way that ships. Every shipped wrapper is `aai-` prefixed (42/42 under `.claude/skills`, zero others). A future shipped wrapper without the prefix would be skipped silently by `checkPointers`, but TEST-4130's independent reader (`test-aai-harness-shims.sh:139`) enumerates every directory under `.claude/skills` with no prefix filter and asserts `count=42` plus one D1 pointer each, so the source repo fails before it can ship. Consumers only receive what the source ships. The README the generator renders already says project skills must use the `aai-` prefix, and `aai-doctor.mjs:167` and `aai-sync.mjs:759` key on the same prefix.

## Code quality findings

### NB-4 (P2): the scope rule disagrees with the layer's own definition of its wrappers (sync-harness-skills.mjs:377)

`aai-sync.mjs:667` decides what is a layer-owned wrapper as `^aai-[a-z0-9-]+$` and not `aai-project-*`. Its conflict message at `aai-sync.mjs:791` tells consumers to move project guidance into `<tree>/aai-project-<topic>/SKILL.md`. The A6 check skips only names without the `aai-` prefix, so the layer's own recommended name for a project-owned skill still gets `DIVERGE pointer`. NB-1 is fixed for the unconventional name but not for the conventional one.

Repro (backed, exit 0 = reproduced): `/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/cr2-repro-aai-project-skill.sh <worktree>` installs a consumer with `aai-sync.mjs`, adds `aai-project-deploy`, runs `--write` and `--check`: rc 1, `DIVERGE pointer aai-project-deploy: description lacks the canonical pointer`.

Bite is latent: no vendored script or prompt runs `--check` in a consumer today. The orchestrator's own follow-up `fu-consumer-pointer-check-after-sync` would make it bite. That is why this is P2, the same class and rank as NB-1, and NON-BLOCKING.

Recommended disposition: **remediate-in-tree**. One line, `if (!skill.startsWith('aai-') || skill.startsWith('aai-project-')) continue;`, mirrors `aai-sync.mjs:667`, plus a TEST-4135 `aai-project-*` case. It does not change any SKILL_SHIP byte, so no pin moves. Alternative: fold it into `fu-consumer-pointer-check-after-sync` as a precondition (that is, edit its `what`), or file a new follow-up, suggested `fu-pointer-scope-aai-project`.

### NB-5 (P3): TEST-4135's name and D5 promise "never silent", and the new case asserts a silent pass (test-aai-harness-shims.sh:1295)

The marker exemption prints `SKIPPED pointer <skill>: ...`, but the non-`aai-` skip prints nothing, and the test asserts the output does not mention `deploy-notes`. A6 frames this as scope ("covers only `aai-` wrappers"), not as a third exemption, which is why this is not ranked under the misnamed-universal-negative rule: the skipped object is outside the wrapper set by A6's definition. The test name and D5's heading still overstate it.

Recommended disposition: **remediate-in-tree** together with NB-4: print `SKIPPED pointer <skill>: not an AAI wrapper` for every skipped name (non-`aai-` and `aai-project-*`), and assert that line in TEST-4135. Otherwise **accepted residual** (line below).

accepted residual: NB-5 — TEST-4135 / D5 say "never silent" while non-aai skills are skipped without a line; P3 naming/assurance, no bite, the skipped skills are outside the wrapper set by A6; close by emitting a SKIPPED line when NB-4 is remediated.

### NB-6 (P3): ending (d) does not name the INPUT `propose_maintenance` menu (SKILL_SHIP.prompt.md:132)

Round 1 named both the menu and the ask-for-need. Only the latter is spelled out. A lenient model reads "the INPUT question" as covering the menu. A strict model may answer its own menu (option 1 is marked recommended) or park. Fixing it costs bytes and re-pins all five N pins again.

Recommended disposition: **accepted residual** (line below), or fold it into the next SKILL_SHIP edit.

accepted residual: NB-6 — END-OF-TURN ending (d) "the INPUT question for the need" does not literally name the propose_maintenance ONE-menu; P3 prompt-wording, no observed bite, a lenient reading covers it; fix on the next SKILL_SHIP edit.

### Other delta checks (no finding)

- N=836 measured: `.aai/SKILL_SHIP.prompt.md` is 9788 B at HEAD versus 8952 B at `5f02b0e5` (`/usr/bin/wc -c`), +836. The ledger entry, `want_growth` 68174 -> 69010, `rh_now` -836, the pr-preflight `+836` term and the TEST-3278 `+ 836` all agree. A3 is updated by A6.
- Ending (e) is phrased "in-flight", so a dispatch that has died is no longer in flight and the rule does not forbid re-dispatching a fallen role. That matches the spend-limit recovery practice.
- Validator NB-a (in-flight dispatch dies, blocker none): the reviewer judges it **needs no follow-up** beyond its cannot_verify entry. A dead subagent wrote no STATE (single-writer rule), so STATE still points at the dispatch, and `/aai-ship` resume (`ride-status probe` -> `resume: loop`) re-enters and re-dispatches it. The only unrecoverable shape is a harness that neither notifies nor lets the session continue, and no prompt rule can address that. If the orchestrator wants a record, `accepted residual` in its notes is enough.
- decisions.jsonl: the two appended lines are at the end (HAZ-LEDGER prefix kept); the A6 record text matches the spec's A6 paragraph and the diff (verified by grep, not by the report).
- Full sweep at 084f53e0 (`test-20261126-091612`, 144 pass / 1 skip hermes exit 42) cited from the validation round 3 report. This review ran no suite, only the two scratch consumer repros.

## Deviations from the frozen spec (all disclosed)

A1-A5 as in round 1. A6 adds the `aai-` scope (the spec's AC-001 mapping says "Exemptions are the two named consumer shapes of D5, not a list". A6 treats non-`aai-` skills as out of scope rather than as a third exemption) and the endings (d)/(e). The Spec-AC-08 row and the TEST-4137 plan row still say "three legal endings". The A6 text is the disclosure. `owner_signoff: false`: the owner's merge direction signs it, per the spec's amendment header.

## Warning dispositions

| Finding | Sev | Recommended disposition |
|---|---|---|
| NB-4 aai-project-* skills still get a false pointer DIVERGE | P2 | remediate-in-tree (one line + TEST-4135 case, no pin moves); else follow-up `fu-pointer-scope-aai-project` (suggested) |
| NB-5 "never silent" vs a silent skip | P3 | remediate with NB-4 (SKIPPED line); else accepted residual (line above) |
| NB-6 (d) does not name the propose_maintenance menu | P3 | accepted residual (line above) |
| NB-3 (round 1) | P3 | accepted residual, unchanged |

## Next steps

- The orchestrator records a disposition for NB-4 (and NB-5 with it). Remediating NB-4 changes reviewed code, so it would need a RECHECK_DELTA or round 3. The ids above are suggestions, not filed.
- Carry forward from round 1: integrate origin/main after #595 (A5 superseded by main's TEST-4019), then run the hosted skill-suite Linux and Windows legs on the PR head.
