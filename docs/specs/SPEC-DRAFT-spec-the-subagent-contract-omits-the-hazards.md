---
id: spec-the-subagent-contract-omits-the-hazards
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-DRAFT-the-subagent-contract-omits-the-hazards.md
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — the standing hazards move into the per-dispatch payload

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-DRAFT-the-subagent-contract-omits-the-hazards.md
- Decision records: SPEC-0087 (subagent-protocol-slim — created the CONTRACT and
  its 60-line cap), SPEC-0094 (role-output-contracts — restated the 60-line cap
  and added the <=54 headroom guard), SPEC-0110 (cache-friendly dispatch — the
  CONTRACT is part of the STABLE dispatch prefix), SPEC-0096 (prompt-hash —
  the hashed inherits are role prompt + SUBAGENT_CONTRACT + LEARNED).
- Technology contract: docs/TECHNOLOGY.md

## Problem

`.aai/SUBAGENT_CONTRACT.md` is the per-dispatch payload every spawned role
receives. It is 53 lines and entirely about the result-block YAML and the
single-writer rule. It says nothing about restoring git commands, scratch paths,
append-only ledgers, worktree removal, or verifying a path before `cd`.

Those rules exist — retyped by hand into every dispatch. Measured recurrence:
`fu-subagent-probe-hits-real-repo` (P1, 2026-08-15) put two commits on `main`
from a validator probe, and on 2026-08-22 the same class recurred *with the rule
written verbatim in that dispatch* (`485a315`, reachable only from the reflog).
A rule that has been remembered every time and still failed twice is a rule in
the wrong PLACE, not a rule with the wrong WORDS.

## Solution (relocation into the payload + one cap re-base)

1. `.aai/SUBAGENT_CONTRACT.md` gains ONE named section, `## Standing hazards`,
   carrying five hazards, each stating its rule AND the measured incident that
   produced it, each anchored by a stable greppable id (`HAZ-RESTORE`,
   `HAZ-SCRATCH`, `HAZ-CD`, `HAZ-LEDGER`, `HAZ-WORKTREE`).
2. The section is placed BEFORE `## Result block`, immediately after the header:
   the whole finding is about placement, and a hazard read after the output
   format has already been read is a hazard read too late.
3. The CONTRACT line cap is RE-BASED, not removed: 60 -> 90 (hard) and 54 -> 84
   (the >=6-line headroom guard), in the three places that assert it.

Out of scope: any change to the result block, the single-writer rule, the
rationalization table, or the EXPECT pointer; any edit to
`.aai/SUBAGENT_PROTOCOL.md`; fixing the LEARNED.md sentence that contradicts
HAZ-RESTORE (filed, not fixed — see `## Notes`).

### D1 — why the cap MOVES rather than the hazards living in their own file

The alternative the intake names is a separate `.aai/SUBAGENT_HAZARDS.md` that
the CONTRACT points at in one line. It is rejected on four grounds:

- It reintroduces the exact defect. The rule was already one hop away (in
  dispatch prose), was read, and still failed twice. A pointer is a weaker
  placement than the payload, not a stronger one — the change would ship the
  finding's own failure mode as its remedy.
- The cap's PURPOSE is per-spawn cost, and this change IMPROVES that cost.
  SPEC-0087 capped the CONTRACT because a subagent re-pays the payload on every
  spawn (4-6 per work item). These bytes are not new: the intake measures ~40
  lines of hazards already retyped into every dispatch. Moving 30 of them into
  the CONTRACT moves them from the VARIABLE per-dispatch suffix into the STABLE
  prefix that SPEC-0110/SPEC-0096 hash and cache. Cheaper per spawn, not dearer.
- The cap is a proxy for "orchestrator-only material stays out". The hazards
  bind the dispatched unit's own hands — they are subagent-binding by the exact
  test SPEC-0087 used to classify every section. Capping them out would push
  subagent-binding rules back into orchestrator prose, inverting the split.
- A new `.aai/**` file owes a PROFILES classification and a second surface
  nobody pins for staleness. `.aai/SUBAGENT_CONTRACT.md` is already classified
  `core` and already selected by an always-on suite.

The cap is re-based, not deleted, and both tiers survive: hard cap 90, headroom
guard 84 (>=6 below), file lands at 83. That is the same 1-line/7-line shape the
file ships today (53 / 54 / 60), so the zero-headroom trap TEST-020 exists to
prevent is not reintroduced.

### D2 — how the shape satisfies TEST-002 and TEST-003 of spec-subagent-protocol-slim

- TEST-002 (`test_081_no_rule_duplication`) pins five canonical phrases to
  exactly one of {CONTRACT, PROTOCOL}. The hazards section adds no fenced
  `subagent_result:`, no `MUST NOT write \`docs/ai/STATE.yaml\``, no
  `duration_seconds\` MUST match`, and — deliberately — neither of the two
  PROTOCOL-only phrases. Checked before writing, re-checked by running the arm.
- TEST-003 (`test_082_dispatch_refs_name_contract`) pins the CONTRACT-vs-
  PROTOCOL split: payload refs name the CONTRACT, orchestrator-only refs name
  the PROTOCOL. This change adds only subagent-binding material to the CONTRACT
  and does not touch `.aai/SUBAGENT_PROTOCOL.md` or any dispatch reference, so
  every assertion in that arm is untouched.
- AC-005 more broadly: no hazard restates a rule that already lives elsewhere.
  Verified by grep over `.aai/` before writing — zero occurrences of
  `git restore`, `git reset --hard`, `worktree prune`, or a scratch-path rule
  anywhere in the layer. The two near-neighbours are cited, not copied:
  `.aai/SKILL_WORKTREE.prompt.md` owns "never `--force`" (a different rule from
  "never `prune`"), and `docs/knowledge/LEARNED.md` owns "never `git clean`
  under `docs/`" (deletes UNTRACKED files — disjoint from "no restoring command
  on a TRACKED file", which is why `git clean` is deliberately absent from
  HAZ-RESTORE's list).

### D3 — prompt-corpus governance, measured rather than assumed

TEST-010's corpus is `cat .aai/*.prompt.md` plus an explicit extra list of
`.aai/INTAKE_COMMON.md`, `.aai/STATE_FALLBACK.md`, `.aai/ROLE_COMMON.md`
(`tests/skills/test-aai-prompt-diet.sh:327-331`). `.aai/SUBAGENT_CONTRACT.md`
has no `.prompt.md` suffix and is not in the extra list, so it is OUTSIDE the
measured corpus. NO diet-ledger entry is owed and NO TEST-012 pin bump is owed.
This is not a novel reading: the ledger's own `r-guard-runtime-enforcement`
entry records the same finding for the sibling `.aai/SUBAGENT_PROTOCOL.md`
("sits OUTSIDE TEST-010's live `.aai/*.prompt.md` glob AND its extra
accounting ... the same out-of-glob treatment CHANGE-0061 applied"). Adding a
ledger entry that no measurement demands would pad the credit, which is the
anti-pattern `HEADROOM_CAP` exists to catch.

PROFILES: `.aai/SUBAGENT_CONTRACT.md` is already in `.aai/system/PROFILES.yaml`
`core:` (line 76). No new `.aai/**` file is created, so no classification is
owed. Test registration: the one new arm is a `test_*` function referenced from
`main()`, which is what `check-test-registration.mjs` (hygiene `test_093`)
requires. No new suite, so no `suite-map.yaml` row; the hygiene pack is a `core`
always-on suite, so the change cannot escape its own gate.

## Implementation strategy
- Strategy: direct
- Rationale: prose relocation into one canon file plus a cap re-base in three
  assertions, delivered with one new targeted regression arm. The arm carries
  its own bite proof IN-SUITE (five mutations plus an unmutated control), which
  is a stronger and re-runnable form of the evidence a stored RED log would
  carry once. Per `### Evidence by strategy`, `direct` owes no stored RED
  artifact; it owes the targeted regression arm, which this scope ships.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: documentation/prompt/test edits, one logical scope, no
  runtime, state, schema, or protected surface. Fully reversible by ordinary
  editing.
- User decision: inline
- Base ref: main (f46502e)
- Worktree branch/path: —
- Inline review scope: `.aai/SUBAGENT_CONTRACT.md`,
  `tests/skills/test-aai-hygiene-pack.sh`, `tests/skills/test-aai-role-output.sh`

## Acceptance Criteria Mapping

- Maps to: CHANGE AC-001
  - Spec-AC-01: `.aai/SUBAGENT_CONTRACT.md` carries ONE named section
    `## Standing hazards` holding five greppable hazard anchors — `HAZ-RESTORE`
    (no restoring git command on a tracked file), `HAZ-SCRATCH` (one reused copy
    under the absolute scratch path), `HAZ-LEDGER` (append-only ledgers),
    `HAZ-WORKTREE` (targeted `git worktree remove`, never `prune`), `HAZ-CD`
    (verify a path is non-empty and absolute before `cd`) — and the section is
    non-empty.
  - Verification: `bash tests/skills/test-aai-hygiene-pack.sh` (new
    `test_083`, control half).
- Maps to: CHANGE AC-002
  - Spec-AC-02: each of the five hazards states the measured incident behind it,
    citing an id or commit that EXISTS in this repository —
    `fu-orchestrator-mutated-real-file`, `fu-subagent-probe-hits-real-repo`,
    `485a315`, `.aai/scripts/follow-ups.mjs`,
    `fu-prune-repair-error-string-misquoted`.
  - Verification: the new arm asserts every citation token is present in the
    section; each cited id is separately resolvable
    (`node .aai/scripts/follow-ups.mjs list --status all`, `git cat-file -t`).
- Maps to: CHANGE AC-003
  - Spec-AC-03: WHEN any one hazard anchor is removed from a copy of the
    CONTRACT, the arm SHALL fail and name that hazard; the unmutated original
    SHALL stay green in the same run; and when the mutation lever is
    unavailable (no writable scratch dir, or a mutation that did not change the
    file) the arm SHALL report UNCOVERED and fail, never pass.
  - Verification: `bash tests/skills/test-aai-hygiene-pack.sh` — `test_083`
    runs five mutations plus the unmutated control plus the vacuity guard on
    every invocation.
- Maps to: CHANGE AC-004
  - Spec-AC-04: prompt-corpus governance satisfied by MEASUREMENT — the
    CONTRACT is outside TEST-010's glob and extra accounting, so no ledger entry
    and no TEST-012 bump are owed (D3); PROFILES already classifies the file;
    `check-test-registration` sees the new arm.
  - Verification: `bash tests/skills/test-aai-prompt-diet.sh` (TEST-010/012
    unchanged and green), `bash tests/skills/test-aai-layer-profiles.sh`,
    `bash tests/skills/test-aai-hygiene-pack.sh` (`test_093`).
- Maps to: CHANGE AC-005
  - Spec-AC-05: no rule sentence is duplicated — the five-phrase CONTRACT/
    PROTOCOL spot-grep and the dispatch-split arm both stay green, and no hazard
    restates a rule already stated in `.aai/ROLE_COMMON.md`, a role prompt, or
    `.aai/SKILL_WORKTREE.prompt.md` (D2).
  - Verification: `bash tests/skills/test-aai-hygiene-pack.sh`
    (`test_081`, `test_082`), plus the D2 grep record.

## Constitution deviations

None. Article 5 (additive first) is the only one in tension: raising a line cap
is strictly additive — every file that passed the old cap passes the new one —
and both tiers of the guard are preserved rather than removed.

## Acceptance Criteria Status

| Spec-AC    | Description                                                          | Status       | Evidence | Review-By | Notes |
|------------|----------------------------------------------------------------------|--------------|----------|-----------|-------|
| Spec-AC-01 | Standing hazards section present with five greppable anchors, non-empty | implementing | —        | —         | —     |
| Spec-AC-02 | Each hazard cites a measured incident whose id or commit exists       | implementing | —        | —         | —     |
| Spec-AC-03 | Arm bites per-hazard on mutation, control green, UNCOVERED never passes | implementing | —        | —         | —     |
| Spec-AC-04 | Corpus governance measured — no ledger entry owed, PROFILES already set | implementing | —        | —         | —     |
| Spec-AC-05 | No rule sentence duplicated across canon files                        | implementing | —        | —         | —     |

## Implementation plan

Components/files affected:
- `.aai/SUBAGENT_CONTRACT.md` — header sentence naming the hazards as
  subagent-binding, plus the `## Standing hazards` section before
  `## Result block`. 53 -> 83 lines.
- `tests/skills/test-aai-hygiene-pack.sh` — `test_080` cap 60 -> 90; NEW
  `test_083_subagent_contract_hazards` plus its `main()` registration.
- `tests/skills/test-aai-role-output.sh` — `test_010_canon_wiring` cap 60 -> 90;
  `test_020_contract_headroom` cap 54 -> 84 (and the comment that explains the
  >=6-line relation).

Data flows: none — prose plus grep assertions.

Edge cases:
- The first ```yaml fence must remain the result block. The hazards section
  contains no fence, and both extractors (`hygiene test_060`,
  `role-output TEST-014`) take the FIRST fence, so inserting above the result
  block is safe.
- `test_083`'s mutation must never touch the tracked file. It copies the
  CONTRACT into the suite's own `TEST_DIR` and mutates the copy; the tracked
  file is only ever READ. The arm is itself an instance of HAZ-RESTORE.
- A mutation that removes nothing (anchor absent, unwritable dir) must be
  UNCOVERED, not a pass — checked by comparing mutated vs original before the
  bite assertion runs.

## Seam analysis

- SEAM-1 CONTRACT line count <-> the three cap assertions in two suites. Both
  suites are run; a cap left at 60 in either turns the whole change red.
- SEAM-2 CONTRACT result-block fence <-> BRIEF_TEMPLATE byte-identity
  (`hygiene test_060`) and the role-output skeleton extraction (TEST-014). Both
  covered by running those suites; the section adds no fence.
- SEAM-3 CONTRACT bytes <-> the prompt-hash stable prefix (SPEC-0096). Changing
  the CONTRACT changes the dispatch hash BY DESIGN; `test-aai-prompt-hash.sh`
  asserts the hash is sensitive to CONTRACT bytes with its own fixtures, never
  against the live file, so no pinned hash goes stale.
- SEAM-4 CONTRACT <-> `.aai/system/PROFILES.yaml` union over the live tree. No
  new file, so the union is unchanged; layer-profiles run to confirm.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                  | Description | Status |
|----------|------------|-------------|---------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-hygiene-pack.sh (new test_083) | Section anchor present; all five HAZ ids present; the section between its heading and the next heading is non-empty | pending |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-hygiene-pack.sh (new test_083) | All five incident citation tokens present inside the section | pending |
| TEST-003 | Spec-AC-03 | unit        | tests/skills/test-aai-hygiene-pack.sh (new test_083) | Per-hazard mutation on a COPY bites and names the removed hazard; unmutated control green; no-op mutation reports UNCOVERED | pending |
| TEST-004 | Spec-AC-01 | unit        | tests/skills/test-aai-hygiene-pack.sh (test_080, edit) | CONTRACT cap re-based 60 -> 90; existing token greps unchanged | pending |
| TEST-005 | Spec-AC-01 | unit        | tests/skills/test-aai-role-output.sh (test_010, test_020, edit) | Hard cap 60 -> 90 and headroom guard 54 -> 84, the >=6 relation preserved | pending |
| TEST-006 | Spec-AC-05 | unit        | tests/skills/test-aai-hygiene-pack.sh (test_081, test_082, existing) | Five-phrase spot-grep and the dispatch-split arm stay green with the section added | pending |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-prompt-diet.sh (TEST-010/012, existing) | Corpus byte count and JUSTIFIED_GROWTH_BYTES unchanged — the CONTRACT is outside the glob | pending |
| TEST-008 | Spec-AC-04 | integration | tests/skills/test-aai-layer-profiles.sh (TEST-001, existing) | PROFILES union still equals the live `.aai` tree (no new file) | pending |
| TEST-009 | Spec-AC-01 | integration | tests/skills/test-aai-role-output.sh (TEST-014, existing) | The result-block skeleton still extracts from the FIRST fence and still passes the checker | pending |

## Verification
- `bash tests/skills/test-aai-hygiene-pack.sh`
- `bash tests/skills/test-aai-role-output.sh`
- `bash tests/skills/test-aai-prompt-diet.sh`
- `bash tests/skills/test-aai-layer-profiles.sh`
- whatever `node .aai/scripts/select-suites.mjs --files-from <changed>` returns
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
For each Implementation / Validation / Code Review artifact record: ref_id;
Spec-AC + TEST-xxx links; command; exit code; evidence path; commit SHA or diff
range when available. Strategy is `direct`, so no stored RED artifact is owed;
the bite evidence is the in-suite mutation half of `test_083`, re-run on every
invocation.

Notes:
- Residual, filed not fixed: `docs/knowledge/LEARNED.md` recommends
  `git checkout -- docs/ai/EVENTS.jsonl docs/ai/METRICS.jsonl docs/INDEX.md`
  as a between-runs cleanup. That is a restoring git command on tracked files
  and it directly contradicts HAZ-RESTORE and HAZ-LEDGER — and LEARNED.md is
  loaded into the SAME dispatch payload as the CONTRACT (SPEC-0096 inherits).
  Reconciling it is outside AC-001..005; filed as a follow-up.
- This document defines HOW, not WHAT/WHY. It does not define workflow.
