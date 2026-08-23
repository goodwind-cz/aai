---
id: the-subagent-contract-omits-the-hazards
number: 159
type: change
status: done
user_visible: false
ceremony_level: 2
capability: aai-orchestration
links:
  pr:
    - 279
  commits:
    - 69faece46071c6b26fc8a9f9292cf7958465617b
---

# Change — the contract every subagent reads says how to format its answer and nothing about how not to destroy the repository

## Summary
- `.aai/SUBAGENT_CONTRACT.md` is the per-dispatch payload every spawned role
  receives. It is 53 lines and **entirely about the result-block YAML**.
- It contains no rule about restoring git commands, scratch paths, append-only
  ledgers, or worktree removal. Every one of those lives only in the
  orchestrator's hand-written dispatch text, retyped from memory each time.

## Evidence
Measured on `main` at `f46502e`:

```
.aai/SUBAGENT_CONTRACT.md                       53 lines, result-block only
occurrences of "git" / "scratch" / "restore"     0
.aai/IMPLEMENTATION.prompt.md, "scratchpad"      0
.aai/VALIDATION.prompt.md, "scratchpad"          1  (unrelated — monty output)
```

Six files reference the contract as the dispatch payload
(`IMPLEMENTATION`, `VALIDATION`, `SKILL_TDD`, `SKILL_LOOP`,
`ORCHESTRATION_PARALLEL`, `SUBAGENT_PROTOCOL`), so it is the surface a role
actually reads.

**The recurrence is the argument.** `fu-subagent-probe-hits-real-repo` (P1,
filed 2026-08-15): a validator probe helper ran git against the real repository
and created two commits on main. It happened **again on 2026-08-22**, in this
programme, with the rule written verbatim in that dispatch: a `local a=1 b=$a`
chain left a fixture path empty, `cd ""` stayed in the shipping repo, and the
harness committed there (`485a315`, now reachable only from the reflog).

A rule that is retyped per dispatch is a rule that depends on the orchestrator
remembering it. It has been remembered every time and it still failed twice,
which is the strongest evidence available that the placement is wrong, not the
wording.

## Impact
- The failure mode is a write to the shipping repository by an agent that
  believed it was in a fixture. Twice measured; both recovered by hand.
- Every dispatch pays ~40 lines of retyped hazards, which drift between
  dispatches and cannot be reviewed as a unit.

## Suspected Cause
The contract was created by CHANGE-0061 to hold the **result-block format**,
split out of `SUBAGENT_PROTOCOL.md`. Nothing was wrong with that split; the
hazards simply never had a home, so they accreted in dispatch prose instead.

## Desired Behavior
A dispatched role receives the standing hazards **by contract**, not by the
orchestrator's memory, and a dispatch can reference them instead of restating
them.

## Acceptance Criteria
- AC-001: the standing hazards live in `.aai/SUBAGENT_CONTRACT.md` as one
  named, greppable section. At minimum: no restoring git command on a tracked
  file; scratch work under an absolute scratch path only; append-only ledgers;
  targeted `git worktree remove`, never `prune`; verify a path is non-empty and
  absolute before `cd`.
- AC-002: each hazard states the **measured incident** that produced it, not
  just the rule. A rule without its scar gets deleted by the next person
  tidying up. Cite ids/commits that exist.
- AC-003: an arm asserts the section is present and non-empty, and bites when
  a hazard is removed. Prove by mutation with an unmutated green control.
- AC-004: the prompt-corpus governance is satisfied in the same change —
  diet-ledger entry with the measured byte delta, TEST-012 bump if the corpus
  glob covers it, PROFILES classification. Measure whether the contract is
  inside `TEST-010`'s glob rather than assuming either way.
- AC-005: **no rule is duplicated.** If a hazard already exists in
  `ROLE_COMMON.md` or a role prompt, the contract points at it rather than
  restating it — `spec-subagent-protocol-slim` TEST-002 pins that no rule
  sentence lives in two files, and TEST-003 pins CONTRACT-vs-PROTOCOL split.

## Verification
- prove AC-003 bites by deleting one hazard and watching the arm name it
- run `bash tests/skills/test-aai-hygiene-pack.sh` (TEST-082 pins the
  CONTRACT/PROTOCOL split) and the prompt-diet arm
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed>` returns

## Constraints / Risks
- **The prompt corpus is governed.** New or edited `.aai` prompt bytes need a
  diet-ledger entry at the measured delta; `TEST-010` fails on unaccounted
  growth and `HEADROOM_CAP` is 2048 B. Budget the section's size before writing
  it, and if it does not fit, say so rather than silently spending headroom.
- Ceremony level 2: this edits the payload every subagent receives, so a
  mistake reaches every future dispatch of every role.
- `spec-subagent-protocol-slim` caps the contract at 60 lines
  (TEST-001 asserts `<= 60`). It is at 53. **A hazards section will not fit
  under that cap** — resolving that is part of this scope: either the cap moves
  with a stated reason, or the hazards live in a file the contract points at.
  Do not silently breach it.
- Do not weaken the result-block section to make room.
- No secret is referenced by this scope.

## Notes
- Closes `fu-subagent-probe-hits-real-repo` (P1) if the arm holds; related
  `fu-adhoc-probes-unisolated-report-only` (P2) is NOT in scope — that is about
  the wrapper's guard being report-only for non-suite commands.
- Ride discipline: ship on these acceptance criteria and nothing else. A finding
  outside them is filed, not fixed here. Two validation rounds maximum.
- Worth knowing while working: `grep` resolves to a shell function even
  non-interactively here, zsh does not word-split unquoted variables,
  `find -newermt` is a hard error, reading an exit code after a pipe reports the
  pipe's last command, and in JavaScript `String.replace` a `$'` in the
  REPLACEMENT means "everything after the match".
