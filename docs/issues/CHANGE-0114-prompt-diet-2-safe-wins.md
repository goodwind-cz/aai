---
id: prompt-diet-2-safe-wins
number: 114
type: change
status: done
user_visible: false
ceremony_level: 1
links:
  pr:
    - 218
  commits:
    - e7de20ea425ec0990b648cf4d53bf70b0b9ebb96
---

# Change — diet ride 2: execute the zero-pin safe immediate wins from the unhobbling audit

## Summary
Apply the "suggested first diet ride — safe immediate wins" rows of
`docs/analysis/unhobbling-audit.md` (the read-only Phase 0 pass of
`docs/issues/CHANGE-0113-altitude-prompt-experiment.md`) to the live role-prompt
corpus, and reconcile the prompt-diet ledger for the resulting shrink.

Strategy: `direct` (mechanical prose deletion against an existing audit; the
"tests" are the 20+ existing pin suites, which already encode every rule that
must survive).

## Motivation / Business Value
The audit measured 36,065 B (24.0 %) of the ten largest role prompts as
deletion or relocation candidates, and identified 13,558 B of them as carrying
ZERO pin coupling in classes the repo's own evidence says are safe to cut
(derivable-from-code, repeated-rule, verification-instruction). Those bytes are
loaded on every dispatch of the affected role. Removing them lowers per-run
prompt cost and, more importantly, removes guardrail prose that competes with
the model's judgment without any test depending on it.

## Scope
- In scope: `.aai/SKILL_WORKTREE.prompt.md`, `.aai/SKILL_TDD.prompt.md`,
  `.aai/SKILL_LOOP.prompt.md`, `.aai/VALIDATION.prompt.md`,
  `.aai/PLANNING.prompt.md`; the diet ledger
  (`tests/skills/lib/prompt-diet-ledger.sh`) and TEST-012's pin
  (`tests/skills/test-aai-prompt-diet.sh`); CHANGELOG.
- Out of scope: `.aai/INTAKE_*` and `.aai/ORCHESTRATION.prompt.md` (TEST-003
  line budget and the 40-line cap stay untouched); every audit row marked
  `needs-gate-first`; any new `.aai/**` file (no PROFILES companion obligation
  is incurred); any behavior change to a script.

## Affected Area
The role-prompt corpus inside TEST-010's live `.aai/*.prompt.md` glob, plus the
diet-ledger governance pin that gates every corpus deletion.

## Desired Behavior (To-Be)
Each cut row's rule keeps exactly one home, and that home is named below. No
pinned sentence is deleted. The corpus shrinks by a measured amount, the ledger
records that shrink as a NEGATIVE `JUSTIFIED_ADDITIONS` entry retiring the freed
credit, and headroom stays inside `HEADROOM_CAP`.

## Acceptance Criteria
- AC-001: 12,873 B removed from the live `.aai/*.prompt.md` glob
  (313,505 -> 300,632), only from rows dispositioned delete/keep-shortened with
  zero pin coupling in `docs/analysis/unhobbling-audit.md`. No
  `needs-gate-first` row is touched.
- AC-002: Zero semantic-rule loss — every deleted row's content verifiably
  survives at the location named in the evidence table below.
- AC-003: `tests/skills/lib/prompt-diet-ledger.sh` carries one new NEGATIVE
  entry sized to the measured shrink, and TEST-012's literal pin is moved from
  `1305` to `-11568` (== an independent re-sum of the array).
- AC-004: `bash tests/skills/test-aai-prompt-diet.sh` passes with TEST-010
  headroom in [1500, 2048] and TEST-012 green.
- AC-005: Every suite that greps a touched prompt passes, plus
  `test-aai-hygiene-pack.sh`, `test-aai-layer-profiles.sh`, and
  `test-aai-release.sh` TEST-022 (CHANGELOG scaffold invariant).
- AC-006: `node .aai/scripts/docs-audit.mjs --check --strict --no-event` is
  clean.

## Evidence table — where each cut row's content lives now

| file | audit row | bytes | where the content lives now |
|---|---|---:|---|
| SKILL_WORKTREE | 1-18 intro + Superpowers attribution | part of -6019 | `git worktree --help`; provenance in `.aai/system/SUPERPOWERS_INTEGRATION.md` |
| SKILL_WORKTREE | 163-239 inline `STATE.yaml` heredoc | part of -6019 | `.aai/templates/STATE_TEMPLATE.yaml` (tracked, pinned by `.aai/SKILL_CHECK_STATE.prompt.md`); the deleted copy had already drifted (no `spec_path`, no `metrics`, no `orchestration`) |
| SKILL_WORKTREE | 262-292 Switch, 294-329 List, 385-418 Sync | part of -6019 | one-line-per-subcommand index kept in-file, each naming its `git worktree` command |
| SKILL_WORKTREE | 420-462 Integration walkthrough, 592-623 Example Session | part of -6019 | the surviving Command sections; the deleted text was invented paths and fabricated terminal output only |
| SKILL_WORKTREE | 481-519 Best Practices | part of -6019 | `.aai/PLANNING.prompt.md` step 8 (recommendation levels + selection criteria); sibling-path naming in Setup Worktree step 3 |
| SKILL_WORKTREE | 520-549 Prevent Data Loss, 550-582 Troubleshooting | part of -6019 | `git worktree remove` refuses on a dirty tree, `git branch -d` on an unmerged branch, `git worktree prune/repair/unlock`; the ONE rule git does not enforce (archive `STATE.yaml` BEFORE remove, `needs-gate-first` #7) is kept verbatim in Cleanup steps 2-3 and restated in Safety |
| SKILL_WORKTREE | 584-590 METRICS jsonl example | part of -6019 | schema owned by `.aai/scripts/state.mjs` / `metrics-flush.mjs`; the `worktree_create` append instruction stays in the Recommendation Gate |
| VALIDATION | 232-245 RATIONALIZATION TABLE | part of -2098 | every row's rule is already imperative in PROCESS 5a-5g, INVARIANT RULES, or the AC STATUS GATE |
| VALIDATION | 246-254 STRICT RULES | part of -2098 | INVARIANT RULES + step 5; the pinned `merged per .aai/SUBAGENT_PROTOCOL.md` line (hygiene-pack:828) is kept |
| SKILL_TDD | 13-78 Phase 0 steps 1-4 and 7 | part of -1860 | `.aai/ORCHESTRATION.prompt.md` + `.aai/scripts/orchestration-dispatch.mjs` compute the dispatch; the three stop rules are kept as prose. Steps 5 and 6 kept verbatim (implementation-mode TEST-005 pins `do NOT start RED`/`direct`/`untested`; `.aai/ROLE_COMMON.md:71` references "Phase 0 step 6") |
| SKILL_TDD | 148-158 / 214-222 / 279-287 phase checklists | part of -1860 | each checkbox restates a numbered step directly above it; the two pinned items survive at their source (`Fixture diversity checklist` heading, `tdd-evidence-check.mjs` in Phase 1 step 4) |
| SKILL_TDD | 9 Superpowers attribution | part of -1860 | `.aai/system/SUPERPOWERS_INTEGRATION.md` |
| PLANNING | 152-163 RATIONALIZATION TABLE | part of -1699 | steps 5/6/6a/7/8/9 and INVARIANT RULES |
| PLANNING | 165-168 STRICT RULES (2 of 3 lines) | part of -1699 | INVARIANT RULES L14 ("No code implementation in planning") and L16 ("Every acceptance criterion must be measurable and verifiable") + step 10 freeze conditions; contradictory requirements route through `[HITL-1]` in `.aai/ORCHESTRATION_HITL.prompt.md` |
| SKILL_LOOP | 253-298 CHECKPOINT GATE templates | part of -1197 | the gate's rules stay in-file (mode default is `none`); the deleted bytes were literal terminal layout. Mode enumeration also in `.aai/AGENTS.md` |
| SKILL_LOOP | 393-401 STRICT RULES (5 of 7 lines) | part of -1197 | stop conditions 2b/2d, step 1, step 4 dispatch contract, step 6 "Do not estimate timing"; the clock-source and always-log-the-tick rules are kept because their only other home is partial |

## Verification
- `bash tests/skills/test-aai-prompt-diet.sh` — TEST-010 headroom 1530/2048,
  TEST-012 `== -11568`.
- `bash tests/skills/test-aai-hygiene-pack.sh`
- Every suite that greps a touched prompt (23 files, from
  `grep -l <prompt> tests/skills/*.sh`), plus `tests/skills/*.Tests.ps1`
  re-checked for dynamic pin patterns.
- `bash tests/skills/test-aai-release.sh` (TEST-022 CHANGELOG scaffold).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`

## Constraints / Risks
- The audit's own caveat: its pin map covers grep assertions with quoted
  literals or resolvable regexes, not dynamically built patterns or
  `.Tests.ps1`. Mitigation: every candidate row was re-grepped before the cut,
  restricting the literal source to test files that actually reference the
  target prompt, and the two `.Tests.ps1` files were checked (neither
  references any `.aai/*.prompt.md`).
- Byte estimates in the audit are estimates; the ledger records MEASURED bytes.
- No secret is referenced by this change.

## Notes
- Rows deliberately SKIPPED and why: see the ride report. In short —
  `needs-gate-first` rows (untouched by rule), `obsolete-guardrail` rows other
  than the two rationalization tables, `severity-filter` rows, and the two
  `ROLE_COMMON.md` PATTERN CONTEXT relocations (net-zero ledger effect, since
  `ROLE_COMMON.md` sits inside TEST-010's extra accounting).
- The audit's disposition for SKILL_LOOP's CHECKPOINT GATE was
  `move-to-script-desc` into a new `.aai/system/CHECKPOINT_MODES.md`. Executed
  instead as `keep-shortened` in place, to avoid creating a new `.aai/**` file
  (PLANNING step 3a COMPANION OBLIGATIONS would require a PROFILES.yaml
  classification) during a ride whose whole point is removal.
