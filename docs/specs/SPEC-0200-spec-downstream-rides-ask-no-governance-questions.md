---
id: spec-downstream-rides-ask-no-governance-questions
type: spec
number: 200
status: done
mutation_gate: v1
frozen_sha256: 628c83f0f910a17e8efe125f933b5fadc477403b1716014af7af481c5317cf2a
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0200-downstream-rides-ask-no-governance-questions.md
  rfc: null
  pr:
    - 416
  commits:
    - a32205f3e2301a3ef0a3d9e346508614e1c9f219
---

# Spec — downstream rides ask no roadmap or amendment sign-off questions

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0200-downstream-rides-ask-no-governance-questions.md
- Owner direction 2026-10-01 (intake Notes): `/aai-intake` and `/aai-ship` are
  the entry points; everything else returns validated code, docs and tests
  autonomously; the owner is asked only at the merge.
- Prior specs this scope touches: SPEC-0168 (spec-roadmap-driven-ride-selection-with-budget,
  the gate), SPEC-0188 (spec-roadmap-takes-direction), SPEC-0165 / AUTONOMOUS_LOOP
  section 6a (the additive-with-disclosure amendment convention).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, bash suites).

## Implementation strategy
- Strategy: tdd
- Rationale: recorded at intake (`implementation_strategy.source: intake`,
  autopilot recommendation) and kept. The core of the scope is a behavioral
  flip on a gate every ride executes (`ride-select.mjs gate`); the flip must be
  observed RED against the pre-change tree (reproduced during planning: the
  absent-roadmap call exits 1 with `REFUSED — roadmap not readable`) before the
  green counts, and the narrowing must be proven not to admit a present but
  broken roadmap. Prose-pin rows are cheap to drive RED first as well.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: edits `.aai/scripts/ride-select.mjs`, which the ship
  skill, the loop and the autonomous dispatch all execute, plus four canon
  prose surfaces; PR-bound. The ride already runs in the dedicated worktree
  `/Users/ales/Projects/aai-autopilot` on branch
  `change/downstream-rides-ask-no-governance-questions`, so the recommendation
  is satisfied and no new isolation decision is owed.
- User decision: worktree (already in place; autopilot default 2 of SKILL_SHIP)
- Base ref: main
- Worktree branch/path: change/downstream-rides-ask-no-governance-questions / /Users/ales/Projects/aai-autopilot
- Inline review scope: not applicable

## Ceremony level

Level 2. None of the touched paths is in `protected_paths_l3`
(docs/ai/docs-audit.yaml names state.mjs, state-engine.mjs, state-core.mjs,
allocate-doc-number.mjs, pre-commit-checks.sh/.ps1, WORKFLOW.md,
CONSTITUTION.md — verified 2026-10-01). This scope deliberately does NOT add a
STATE field (see D5), which would have made it L3.

## What is established before this scope starts (measured 2026-10-01)

- `node .aai/scripts/ride-select.mjs gate --ref CHANGE-0001 --roadmap /nonexistent/roadmap.yaml`
  exits 1: `ride-select: REFUSED — roadmap not readable: ... — a gate that
  cannot read its roadmap admits nothing`. `next` on the same path exits 1,
  `validate` exits 2.
- `loadRoadmap()` (ride-select.mjs line ~57) maps EVERY read failure to one
  error; the header (lines 13-15) says "never 'no roadmap, anything goes'".
- `tests/skills/test-aai-ride-select.sh` `test_005_fail_closed` asserts the
  missing-roadmap refusal (SPEC-0168 Spec-AC-05).
- `.aai/scripts/orchestration-dispatch.mjs` `roadmapGate()` (line ~730)
  ALREADY treats `!fs.existsSync(docs/ai/roadmap.yaml)` as
  `{ admitted: true, consulted: false }`. The dispatch and the CLI gate
  disagree today on an absent roadmap; this scope makes the CLI agree with the
  dispatch.
- `.aai/AGENTS.md` operator contract (33 lines, cap 40 per TEST-007) already
  says rule 4 is opt-in downstream.
- `.aai/SKILL_SHIP.prompt.md` step 1a runs the gate unconditionally and lists
  "an unreadable roadmap" as a stop reason. `.aai/SKILL_LOOP.prompt.md` runs
  the same gate at loop start and EXITs on non-zero.
- `.aai/system/AUTONOMOUS_LOOP.md` 6a already prescribes
  `spec-amend.mjs add --signoff none` and "the ride proceeds", but opens with
  "section 6 assigns the decision to the owner"; `.aai/ROLE_COMMON.md` POST-FREEZE
  SPEC AMENDMENT opens with "the sign-off belongs to the owner"; SKILL_SHIP
  STRICT RULES say scope HITL questions are never auto-answered. Read
  together, a downstream agent reads an amendment as an owner question.
- `spec-amend.mjs add` requires `--signoff owner|none` (no CLI default) and
  co-creates a `fu-amend-*` item; `list --strict` is the PR gate.

## Decisions

- D1 — The roadmap FILE is the posture switch. `docs/ai/roadmap.yaml` absent
  means autopilot posture (gate not consulted); present means governed posture
  (the existing deny-by-default gate, unchanged). Nothing else is a switch: no
  flag, no env var, no config key.
- D2 — "Absent" is exactly `fs.existsSync(<roadmap path>) === false`, the SAME
  predicate `orchestration-dispatch.mjs` `roadmapGate()` already uses, so the
  CLI gate and the dispatch can never disagree about posture. Anything that
  exists at the path but cannot be read as a file (a directory, a permission
  error) or does not fit the closed shape is a DEFECT in a governed project
  and still REFUSES (exit 1). A dangling symlink reads as absent under this
  predicate in both places; disclosed as residual risk R2.
- D3 — Only `gate` changes. `validate` (exit 2) and `next` (exit 1) keep their
  current behavior on an absent roadmap (intake Out of scope). Usage checks on
  `--ref` (missing, non-slug) and an empty `--override` still exit 2 before the
  posture decision: a malformed call is malformed in either posture.
- D4 — The absent-roadmap admit is SIDE-EFFECT-FREE: one stdout line
  `ride-select: ADMIT <ref> — roadmap absent (<path>): gate not consulted ...`,
  exit 0, no file created at the roadmap path, no EVENTS record appended even
  when `--override` is passed (nothing was overridden). The line must contain
  the words `absent` and `not consulted` and no `?`.
- D5 — Intake said "record the skip in STATE". STATE has no free-form field for
  it and adding one means editing `state.mjs` (protected, L3) for a one-line
  report. DISCLOSED NARROWING: the posture is recorded instead as the gate's
  own ADMIT line, carried verbatim into the SKILL_SHIP step 6 merge checkpoint
  summary as `ride gate: <ADMIT line>`, with the rationale text
  `roadmap absent, gate not consulted (autopilot default)`. SKILL_SHIP still
  RUNS the gate in both postures (the script decides; the prompt does not
  re-derive the file check — PLANNING principle 4), so the prompt carries no
  second copy of the predicate.
- D6 — A post-freeze spec amendment during a ride is not a HITL question. The
  autonomous default is `spec-amend.mjs add --signoff none`, executed without
  asking; `--signoff owner --authority` is used only when an owner decision
  record already exists. The owed sign-offs are surfaced ONCE, as one line of
  the SKILL_SHIP step 6 merge checkpoint naming the open `fu-amend-*` ids whose
  ref is this ride's ref_id (derived with
  `node .aai/scripts/follow-ups.mjs list --status open --ref <ref_id>`), or the
  line is omitted when there are none. This is ADDITIVE text: 6a's existing
  sentences (scope change, owner's to close) stay; the new sentence says the
  owner's decision is owed at the merge, not asked mid-ride.
- D7 — `spec-amend.mjs` is not changed (no CLI default for `--signoff`, no
  record-schema change). The autonomy lives in the prose default plus the guard
  test that runs the real writer and gate.
- D8 — The canonical repository keeps its strictness because it has a
  `docs/ai/roadmap.yaml`; this very ride entered through an owner `--override`
  logged to EVENTS. A test pins that the shipped roadmap still refuses an
  off-roadmap ref through the DEFAULT roadmap path (no `--roadmap` flag).
- D9 — Supersession, not amendment: SPEC-0168 Spec-AC-05's "missing roadmap
  refuses" clause is superseded by Spec-AC-01 here for the ABSENT case only;
  its "invalid roadmap refuses" and "done ref refuses" clauses stand. SPEC-0168
  is `done` and its text is not edited (no frozen-anchor drift). The
  `test_005_fail_closed` arm is rewritten in place and its log text names this
  spec.
- D10 — Files outside the intake's Affected Area that this scope must also
  touch, because they state the same rule and would otherwise contradict it
  (PLANNING principle 2): `.aai/ROLE_COMMON.md` (POST-FREEZE SPEC AMENDMENT
  opening sentence), `tests/skills/suite-map.yaml` (row for the new suite),
  `tests/skills/lib/prompt-diet-ledger.sh` and
  `tests/skills/test-aai-prompt-diet.sh` (TEST-012 checkpoint). Additive
  disclosure of scope, not a change of the intake's intent.

## Constitution deviations

None.

Article 5 (additive first) was checked: the gate's absent-roadmap exit code
changes from 1 to 0 at a public CLI boundary. The change is explicit and
documented (ride-select header, AGENTS rule 4, SKILL_SHIP 1a, this spec D9)
and aligns the CLI with the dispatch that already admitted, so it is a
documented behavior change, not a silent one.

## Acceptance Criteria Mapping

- Spec-AC-01 (maps intake AC-001): WHEN `gate` runs with a roadmap path for
  which `fs.existsSync` is false, it SHALL exit 0 and print exactly one stdout
  line starting `ride-select: ADMIT <ref> — roadmap absent` and containing
  `not consulted`, write nothing at the roadmap path, and append nothing to the
  `--events` path even when `--override "<reason>"` is given.
  Verification: `bash tests/skills/test-aai-ride-select.sh test_005_fail_closed`
  and `... test_1202_absent_admit_is_side_effect_free`, exit 0.
- Spec-AC-02 (maps intake AC-002): WHEN the roadmap path exists but is a
  directory, or is a file that does not fit the closed shape, `gate` SHALL exit
  1 with a `REFUSED` line on stderr; `validate` on an absent path SHALL still
  exit 2 and `next` on an absent path SHALL still exit 1.
  Verification: TEST-1203, TEST-1204, TEST-1205 in test-aai-ride-select.sh, exit 0.
- Spec-AC-03 (maps intake AC-001, D3): WHEN the roadmap is absent and `--ref`
  is missing or not a slug, or `--override` is empty, `gate` SHALL exit 2.
  Verification: TEST-1206, exit 0.
- Spec-AC-04 (seam, D2): FOR each of three fixture roots (no roadmap; a
  directory at `docs/ai/roadmap.yaml`; a malformed `docs/ai/roadmap.yaml`), the
  `admitted` value of `orchestration-dispatch.mjs` `buildSnapshot()`'s
  open-intake candidate gate SHALL equal (ride-select `gate` exit code == 0)
  for the same fixture and ref, and `consulted` SHALL be false only for the
  absent case.
  Verification: TEST-1207 in the new guard suite, exit 0.
- Spec-AC-05 (D8): WHEN `gate` runs with NO `--roadmap` flag in this
  repository (default path = the shipped `docs/ai/roadmap.yaml`) for a fixture
  ref that is off-roadmap maintenance, it SHALL exit 1 with `REFUSED`.
  Verification: TEST-1208, exit 0.
- Spec-AC-06 (maps intake AC-007): the `ride-select.mjs` header comment (first
  20 lines) SHALL state that an absent roadmap admits without consulting and a
  present-but-invalid one refuses, and SHALL no longer contain
  `never "no roadmap, anything goes"`; `.aai/AGENTS.md` operator contract rule
  4 SHALL name `docs/ai/roadmap.yaml` as the switch (contains `absent` and
  `not consulted`) and the contract SHALL stay at most 40 lines.
  Verification: TEST-1209 plus the existing TEST-007, exit 0.
- Spec-AC-07 (maps intake AC-004): `.aai/SKILL_SHIP.prompt.md` step 1a SHALL
  state that an absent `docs/ai/roadmap.yaml` makes the gate admit with a
  `roadmap absent` line and carry the rationale
  `roadmap absent, gate not consulted (autopilot default)`, SHALL name
  "a present but unreadable or invalid roadmap" (not a bare
  "an unreadable roadmap") as a stop reason, and step 6 SHALL include a
  `ride gate:` line.
  Verification: TEST-1210, exit 0.
- Spec-AC-08 (maps intake AC-005): `.aai/system/AUTONOMOUS_LOOP.md` 6a,
  the `.aai/SKILL_PR.prompt.md` AMENDMENT GATE bullet and `.aai/ROLE_COMMON.md`
  POST-FREEZE SPEC AMENDMENT SHALL each state that `--signoff none` is the
  autonomous default and that no owner question is asked mid-ride; SKILL_SHIP
  SHALL carry that as an AUTOPILOT DEFAULT and its step 6 SHALL carry one
  `owed sign-offs:` line naming the `follow-ups.mjs list --status open --ref`
  derivation; the existing test-aai-spec-amend.sh TEST-013 arm 5 SHALL still pass.
  Verification: TEST-1211 plus `bash tests/skills/test-aai-spec-amend.sh`, exit 0.
- Spec-AC-09 (maps intake AC-006): IN a temporary fixture project that carries
  a copy of `.aai/scripts/` (whole `lib/`), no `docs/ai/roadmap.yaml` and one
  frozen spec, invoked from the fixture root with DEFAULT paths (no
  `--roadmap`, no `--ledger`): `ride-select.mjs gate` SHALL exit 0 printing
  `ADMIT` (positive control), `spec-amend.mjs add ... --signoff none` SHALL
  exit 0, `spec-amend.mjs list --strict` SHALL exit 0 and report
  `unsigned-tracked=1` (positive control), and the combined stdout+stderr of
  the three calls SHALL contain no `?`, no `AskUserQuestion` and no
  `owner must`. Negative control: after writing a malformed
  `docs/ai/roadmap.yaml` into the same fixture, `gate` SHALL exit 1.
  Verification: TEST-1212, TEST-1213, exit 0.
- Spec-AC-10 (seam, D6): IN the Spec-AC-09 fixture after the `add`,
  `node .aai/scripts/follow-ups.mjs list --status open --ref <fixture ref>`
  (the exact derivation SKILL_SHIP step 6 names) SHALL print exactly one line
  whose id starts `fu-amend-`.
  Verification: TEST-1214, exit 0.
- Spec-AC-11 (maps intake AC-007, companion obligations): the prompt-diet
  ledger SHALL carry one `JUSTIFIED_ADDITIONS` entry for
  `downstream-rides-ask-no-governance-questions` whose byte count equals the
  measured corpus growth of this diff, `bash tests/skills/test-aai-prompt-diet.sh`
  SHALL exit 0, and `tests/skills/suite-map.yaml` SHALL carry exactly one row
  for the new suite (hygiene-pack pin green). No new `.aai/**` file is added,
  so `.aai/system/PROFILES.yaml` is unchanged.
  Verification: TEST-1215, TEST-1216, exit 0.

## Acceptance Criteria Status

| Spec-AC    | Description | Status  | Evidence | Review-By | Notes |
|------------|-------------|---------|----------|-----------|-------|
| Spec-AC-01 | WHEN gate runs on an absent roadmap path it SHALL exit 0 with one ADMIT line containing absent and not consulted, and write nothing at the roadmap or events path | done | TEST-1201, TEST-1202 green (test-aai-ride-select.sh rc 0); absent and absent+override+events probes; RED logs accepted (docs/ai/reports/VALIDATION-20261001T000803Z-downstream-rides-ask-no-governance-questions.md) | — | D1 D2 D4 D9 |
| Spec-AC-02 | WHEN the roadmap path exists but is a directory or malformed gate SHALL exit 1 REFUSED; validate and next on an absent path SHALL keep exit 2 and exit 1 | done | TEST-1203 to TEST-1205 green; malformed, directory, validate and next probes (docs/ai/reports/VALIDATION-20261001T000803Z-downstream-rides-ask-no-governance-questions.md) | — | D2 D3 |
| Spec-AC-03 | WHEN the roadmap is absent and the ref is missing or not a slug or override is empty gate SHALL exit 2 | done | TEST-1206 green; absent+mismatched-intake probe exits 2 (docs/ai/reports/VALIDATION-20261001T000803Z-downstream-rides-ask-no-governance-questions.md) | — | D3 |
| Spec-AC-04 | FOR absent, directory and malformed fixtures the dispatch candidate gate admitted value SHALL equal the CLI gate verdict, consulted false only when absent | done | TEST-1207 green (seam S1); mutation replay reddens (docs/ai/reports/VALIDATION-20261001T000803Z-downstream-rides-ask-no-governance-questions.md) | — | seam S1, D2 |
| Spec-AC-05 | WHEN gate runs on the shipped default roadmap path for an off-roadmap maintenance ref it SHALL exit 1 REFUSED | done | TEST-1208 green; default-roadmap probe exits 1 (docs/ai/reports/VALIDATION-20261001T000803Z-downstream-rides-ask-no-governance-questions.md) | — | D8 governed posture kept |
| Spec-AC-06 | The ride-select header and AGENTS rule 4 SHALL both name the roadmap file as the posture switch, operator contract at most 40 lines | done | TEST-1209 green (docs/ai/reports/VALIDATION-20261001T000803Z-downstream-rides-ask-no-governance-questions.md) | — | intake AC-007 |
| Spec-AC-07 | SKILL_SHIP step 1a SHALL state the absent-roadmap admit and rationale text and name a present but unreadable or invalid roadmap as the stop; step 6 SHALL carry a ride gate line | done | TEST-1210 green (docs/ai/reports/VALIDATION-20261001T000803Z-downstream-rides-ask-no-governance-questions.md) | — | D5 |
| Spec-AC-08 | AUTONOMOUS_LOOP 6a, SKILL_PR amendment gate, ROLE_COMMON and SKILL_SHIP SHALL state signoff none as the no-question default; step 6 SHALL carry one owed sign-offs line | done | TEST-1211 green; test-aai-spec-amend.sh rc 0 (docs/ai/reports/VALIDATION-20261001T000803Z-downstream-rides-ask-no-governance-questions.md) | — | D6 D7 D10 |
| Spec-AC-09 | IN a no-roadmap fixture project with default paths gate, spec-amend add and list strict SHALL exit 0 with no question text, positive and negative controls observed | done | TEST-1212, TEST-1213 green (positive and negative controls) (docs/ai/reports/VALIDATION-20261001T000803Z-downstream-rides-ask-no-governance-questions.md) | — | end-to-end guard |
| Spec-AC-10 | IN that fixture follow-ups list open for the ride ref SHALL print exactly one fu-amend line | done | TEST-1214 green (seam S3) (docs/ai/reports/VALIDATION-20261001T000803Z-downstream-rides-ask-no-governance-questions.md) | — | seam S3, D6 |
| Spec-AC-11 | The diet ledger SHALL credit the measured corpus growth, the prompt-diet suite SHALL pass, and suite-map SHALL carry one row for the new suite | done | TEST-1215, TEST-1216 green; prompt-diet and hygiene-pack rc 0 (docs/ai/reports/VALIDATION-20261001T000803Z-downstream-rides-ask-no-governance-questions.md) | — | companion obligations |

### Amendment 2026-10-01 (Codex P1 on PR #416, additive to D2)

`fs.existsSync` is false for EVERY stat failure, not only not-found: a roadmap behind an unsearchable parent (EACCES) or a self-referential symlink (ELOOP) would read as absent and a governed project would be admitted as ungoverned. "Absent" is therefore narrowed to a stat failure with code ENOENT or ENOTDIR (`roadmapAbsent()` in ride-select.mjs and its twin in orchestration-dispatch.mjs); any other stat failure is a present-but-unreadable roadmap and refuses. The original D2 sentence stays; TEST-1217 pins the narrowing and TEST-1207 gains the eloop seam arm.

## Implementation plan

Components:
1. `.aai/scripts/ride-select.mjs`
   - In `main()`, for `cmd === 'gate'` only: run the existing `--ref`/SLUG/
     `--override` usage checks FIRST (move them above the `loaded.error`
     refusal, or duplicate the three checks into the new branch), then
     `if (!fs.existsSync(a.roadmap))` print the D4 line and `process.exit(0)`.
     Do not call `appendOverride` in that branch.
   - `loadRoadmap()` is unchanged: a directory still yields
     `roadmap not readable` (EISDIR) and refuses; `validate`/`next` untouched.
   - Header comment lines 13-15 rewritten to the D1/D2 posture statement.
2. `tests/skills/test-aai-ride-select.sh`
   - `test_005_fail_closed`: the missing-roadmap arm flips to ADMIT (exit 0,
     stdout `roadmap absent`); the invalid-roadmap and done-ref arms stay.
   - New functions `test_1202_*` .. `test_1206_*`, `test_1208_*`,
     `test_1209_*`, each wired into `main()` (hygiene `check-test-registration`).
3. New suite `tests/skills/test-aai-downstream-autopilot.sh` (TEST-1207,
   TEST-1210 .. TEST-1216) with a fixture-project builder: `mktemp -d` under
   `${TMPDIR:-/tmp}`, guard `[[ -n "$d" && "$d" = /* ]]` before every `cd`
   (HAZ-CD, LEARNED 2026-07-27), `git init -b main` only if a script needs it,
   `cp .aai/scripts/{ride-select,spec-amend,follow-ups,orchestration-dispatch}.mjs`
   plus `cp .aai/scripts/lib/*.mjs` (whole lib, per test-aai-orchestration-dispatch
   TEST-567 precedent), one frozen spec fixture (write it and run the fixture's
   own `spec-freeze.mjs` if list --strict requires an anchor; otherwise a spec
   with no `frozen_sha256` is a no-op for the anchor scan), one intake doc.
   Suite is `set -u` like its siblings, never `set -e` around `$?` captures
   (memory: test-harness shell-options trap).
4. Prose: `.aai/SKILL_SHIP.prompt.md` (1a text, AUTOPILOT DEFAULT 5 for
   amendments, step 6 `ride gate:` and `owed sign-offs:` lines, STRICT RULES
   clause that a post-freeze amendment is not a HITL question);
   `.aai/SKILL_PR.prompt.md` AMENDMENT GATE bullet (one sentence);
   `.aai/system/AUTONOMOUS_LOOP.md` 6a (one additive paragraph);
   `.aai/ROLE_COMMON.md` (one clause); `.aai/AGENTS.md` rule 4 (one sentence,
   contract stays at most 40 lines). Keep every addition terse; the diet
   ledger credits bytes, it does not excuse them.
5. `tests/skills/lib/prompt-diet-ledger.sh` JUSTIFIED_ADDITIONS entry +
   `tests/skills/test-aai-prompt-diet.sh` TEST-012 checkpoint bump, measured
   under bash with `/usr/bin/grep` (memory: shell measurement traps).
6. `tests/skills/suite-map.yaml`: row `aai-downstream-autopilot` with globs
   `.aai/scripts/ride-select.mjs`, `.aai/scripts/spec-amend.mjs`,
   `.aai/scripts/orchestration-dispatch.mjs`, `.aai/SKILL_SHIP.prompt.md`,
   `.aai/SKILL_PR.prompt.md`, `.aai/system/AUTONOMOUS_LOOP.md`,
   `.aai/ROLE_COMMON.md`, `.aai/AGENTS.md`.

Edge cases:
- `--roadmap` pointing into a non-existent directory: `existsSync` false,
  admits (same as dispatch). Only tests pass `--roadmap`; production callers
  use the fixed default path or dispatch's pre-checked absolute path.
- Empty `docs/ai/roadmap.yaml` file: exists, fails the closed shape
  (`missing budget...`), refuses.
- A ref already `done` in a no-roadmap project is admitted by the gate (not
  consulted); the loop's own STATE/spec checks own that case, exactly as the
  dispatch already behaves today.

## Test Plan

Rows TEST-1201..1206, 1208, 1209 land in `tests/skills/test-aai-ride-select.sh`;
the rest in the new `tests/skills/test-aai-downstream-autopilot.sh`. Every row
is observed RED on the pre-change tree (or under its Mutation) before green;
RED/mutation records go to `docs/ai/tdd/spec-downstream-rides-ask-no-governance-questions/`.
Mutation cells name the intended code/prose; the implementer reconciles an
anchor to the code as written and discloses any reconciliation.

| Test ID  | Spec-AC    | Type        | File path (expected)                          | Description | Mutation | Status  |
|----------|------------|-------------|-----------------------------------------------|-------------|----------|---------|
| TEST-1201 | Spec-AC-01 | integration | tests/skills/test-aai-ride-select.sh | test_005_fail_closed missing-roadmap arm rewritten: gate on a nonexistent roadmap exits 0 and stdout carries roadmap absent and not consulted; invalid and done arms unchanged | `sed:s/!fs\.existsSync\(a\.roadmap\)/false/` in .aai/scripts/ride-select.mjs gate branch | green |
| TEST-1202 | Spec-AC-01 | integration | tests/skills/test-aai-ride-select.sh | absent-roadmap admit with --override and --events creates neither the roadmap file nor the events file, and stdout is exactly one line | `patch:docs/ai/tdd/spec-downstream-rides-ask-no-governance-questions/mutation-TEST-1202.patch` inserts `appendOverride(a.events, a.ref, 'absent');` before the absent-branch exit in .aai/scripts/ride-select.mjs | green |
| TEST-1203 | Spec-AC-02 | integration | tests/skills/test-aai-ride-select.sh | a malformed roadmap file and an empty roadmap file each make gate exit 1 with REFUSED on stderr | `sed:s/if \(loaded\.error\) refuse/if (loaded.error) process.exit(0); if (false) refuse/` in .aai/scripts/ride-select.mjs (every unreadable or invalid roadmap is admitted at the refusal site) | green |
| TEST-1204 | Spec-AC-02 | integration | tests/skills/test-aai-ride-select.sh | a directory at the roadmap path makes gate exit 1 with REFUSED and roadmap not readable | `sed:s/if \(loaded\.error\) refuse/if (loaded.error) { if (fs.statSync(a.roadmap).isDirectory()) process.exit(0); } if (loaded.error) refuse/` in .aai/scripts/ride-select.mjs (a directory is admitted at the refusal site) | green |
| TEST-1205 | Spec-AC-02 | integration | tests/skills/test-aai-ride-select.sh | validate on an absent path still exits 2 and next on an absent path still exits 1 | `sed:s/  if \(a\.cmd === 'gate'\) \{/  if (true) {/` in .aai/scripts/ride-select.mjs (the absent branch leaks into validate and next) | green |
| TEST-1206 | Spec-AC-03 | integration | tests/skills/test-aai-ride-select.sh | absent roadmap plus missing --ref, plus a non-slug --ref, plus --override with an empty reason each exit 2 | `patch:docs/ai/tdd/spec-downstream-rides-ask-no-governance-questions/mutation-TEST-1206.patch` moves the absent-roadmap branch above the --ref usage checks in .aai/scripts/ride-select.mjs | green |
| TEST-1207 | Spec-AC-04 | integration | tests/skills/test-aai-downstream-autopilot.sh | seam: for absent, directory, malformed and eloop (self-symlink) fixture roots, buildSnapshot open-intake gate.admitted equals ride-select gate exit 0 and consulted is false only when absent | `sed:s/if \(!fs\.existsSync\(roadmap\)\) return \{ admitted: true, consulted: false/if (false) return { admitted: true, consulted: false/` in .aai/scripts/orchestration-dispatch.mjs roadmapGate | green |
| TEST-1208 | Spec-AC-05 | integration | tests/skills/test-aai-ride-select.sh | with no --roadmap flag (shipped default roadmap) an off-roadmap maintenance fixture ref is REFUSED exit 1 | `sed:s/path\.join\(ROOT, 'docs\/ai\/roadmap\.yaml'\)/path.join(ROOT, 'docs\/ai\/no-roadmap.yaml')/` in .aai/scripts/ride-select.mjs parseArgs | green |
| TEST-1209 | Spec-AC-06 | unit | tests/skills/test-aai-ride-select.sh | the ride-select header names absent-admits and present-invalid-refuses and lacks the old anything-goes sentence; AGENTS operator contract rule 4 names docs/ai/roadmap.yaml with absent and not consulted | `sed:s/not consulted/skipped/g` in .aai/AGENTS.md (rule 4 and the other occurrence) | green |
| TEST-1210 | Spec-AC-07 | unit | tests/skills/test-aai-downstream-autopilot.sh | SKILL_SHIP step 1a carries the absent-admit statement and the rationale text, names a present but unreadable or invalid roadmap as the stop, and step 6 carries a ride gate line | `sed:s/roadmap absent, gate not consulted \(autopilot default\)/roadmap absent/` in .aai/SKILL_SHIP.prompt.md | green |
| TEST-1211 | Spec-AC-08 | unit | tests/skills/test-aai-downstream-autopilot.sh | AUTONOMOUS_LOOP 6a, SKILL_PR AMENDMENT GATE bullet, ROLE_COMMON and SKILL_SHIP each state signoff none is the default with no mid-ride owner question; SKILL_SHIP step 6 carries the owed sign-offs line naming follow-ups.mjs list --status open --ref | `sed:s/owed sign-offs:/sign-offs:/` in .aai/SKILL_SHIP.prompt.md | green |
| TEST-1212 | Spec-AC-09 | e2e | tests/skills/test-aai-downstream-autopilot.sh | fixture project, default paths: gate exits 0 with ADMIT, spec-amend add --signoff none exits 0, list --strict exits 0 with unsigned-tracked=1, and combined output has no question mark, no AskUserQuestion, no owner must | `sed:s/(not consulted[\s\S]{0,12}\n      process\.exit\()0/$11/` in .aai/scripts/ride-select.mjs (the absent-roadmap branch exits 1) | green |
| TEST-1213 | Spec-AC-09 | e2e | tests/skills/test-aai-downstream-autopilot.sh | negative control: the same fixture with a malformed docs/ai/roadmap.yaml makes gate exit 1 | `sed:s/if \(loaded\.error\) refuse/if (loaded.error) process.exit(0); refuse/` in .aai/scripts/ride-select.mjs (an invalid roadmap is admitted at the refusal site) | green |
| TEST-1214 | Spec-AC-10 | integration | tests/skills/test-aai-downstream-autopilot.sh | seam: after the fixture add, follow-ups.mjs list --status open --ref for the fixture ref prints exactly one fu-amend line | `sed:s/const ITEM_PREFIX = 'fu-amend-'/const ITEM_PREFIX = 'fu-amnd-'/` in .aai/scripts/spec-amend.mjs | green |
| TEST-1215 | Spec-AC-11 | integration | tests/skills/test-aai-prompt-diet.sh | TEST-012 checkpoint and the ledger entry for this ref credit the measured corpus growth; the whole suite exits 0 | `sed:s/\nJUSTIFIED_ADDITIONS\+=\( "[0-9]* downstream-rides-ask-no-governance-questions[^\n]*//` in tests/skills/lib/prompt-diet-ledger.sh (deletes the ledger line) | green |
| TEST-1216 | Spec-AC-11 | integration | tests/skills/test-aai-downstream-autopilot.sh | suite-map.yaml carries exactly one aai-downstream-autopilot row and select-suites.mjs selects this suite for a diff touching .aai/SKILL_SHIP.prompt.md | `sed:s/  aai-downstream-autopilot:\n    globs:\n(?:      - [^\n]*\n)+\n//` in tests/skills/suite-map.yaml (deletes the row) | green |
| TEST-1217 | Spec-AC-02 | integration | tests/skills/test-aai-ride-select.sh | Amendment (Codex P1, PR #416): a roadmap path that exists but cannot be stat-ed (ELOOP self-symlink everywhere; EACCES unsearchable parent when not root) makes gate exit 1 REFUSED with roadmap not readable and never prints the absent admit line | `sed:s/return ABSENT_CODES/return true; return ABSENT_CODES/` in .aai/scripts/ride-select.mjs (every stat failure reads as absent) | green |

## Seams

| Seam | Producer | Consumer | Covered by |
|------|----------|----------|------------|
| S1   | presence of docs/ai/roadmap.yaml | ride-select.mjs gate and orchestration-dispatch.mjs roadmapGate (two readers of one switch) | TEST-1207 |
| S2   | ride-select.mjs ROOT-relative default roadmap path | a vendored copy in a downstream project root | TEST-1212, TEST-1213, TEST-1208 |
| S3   | spec-amend.mjs add writes the fu-amend item | follow-ups.mjs list, the reader SKILL_SHIP step 6 names | TEST-1214 |
| S4   | the canon prose that states the amendment and gate defaults (four files) | the agent that reads them together (no automated reader) | TEST-1210, TEST-1211 pin text only; residual R1 |
| S5   | prompt corpus bytes | test-aai-prompt-diet.sh TEST-010 and TEST-012 | TEST-1215 |

S1, S2 and S3 are crossed by executing the real consumer script, never by
asserting on the producer's output shape.

## Residual risks

- R1 — Prose pins prove the sentences exist, not that an agent reading the
  corpus stops asking. No automated test can run an LLM ride end to end here;
  the owner's next downstream `/aai-ship` is the real observation.
- R2 — A dangling symlink at `docs/ai/roadmap.yaml` reads as absent (both
  readers, D2), so a governed project whose roadmap symlink broke would drop
  to autopilot posture silently. Chosen for agreement with the dispatch; a
  lstat-based check in BOTH readers is a candidate follow-up
  (suggested: fu-roadmap-dangling-symlink-posture).
- R3 — Unattended chaining (SKILL_LOOP stop condition c) calls
  `ride-select.mjs next`, which still exits 1 on an absent roadmap (intake
  Out of scope). A downstream unattended run with no roadmap stops after its
  first PR instead of chaining. Suggested follow-up:
  fu-unattended-next-absent-roadmap.
- R4 — Planning's REGISTRY CONSUMER step still lists every open `fu-amend-*`
  item; they are read, not asked, but they add noise to downstream Planning.
  Not changed here.

## Verification

- `bash tests/skills/test-aai-ride-select.sh` — exit 0.
- `bash tests/skills/test-aai-downstream-autopilot.sh` — exit 0.
- `bash tests/skills/test-aai-spec-amend.sh` — exit 0 (AMENDMENT GATE pin).
- `bash tests/skills/test-aai-orchestration-dispatch.sh` — exit 0 (roadmapGate).
- `bash tests/skills/test-aai-unattended.sh` — exit 0 (calls the gate).
- `bash tests/skills/test-aai-prompt-diet.sh` — exit 0.
- `bash tests/skills/test-aai-hygiene-pack.sh` — exit 0 (suite-map row,
  test registration, learned-guard lints over the corpus).
- `bash tests/skills/test-aai-golden-flow.sh` — exit 0.
- `node .aai/scripts/check-vendored-script-deps.mjs` — CLEAN.
- `node .aai/scripts/ride-select.mjs gate --ref x-y --roadmap /nonexistent.yaml --docs docs` — exit 0.
- `node .aai/scripts/ride-select.mjs validate` — exit 0, summary unchanged.
- All suites run with `env -u AAI_ROLE`.
- PASS criteria: all TEST-xxx green, all Spec-AC terminal, a RED record for
  each of the 16 rows under
  `docs/ai/tdd/spec-downstream-rides-ask-no-governance-questions/`.

## Evidence contract

- ref_id: downstream-rides-ask-no-governance-questions
- Per TEST-xxx: the `mutation-run.mjs` record at
  `docs/ai/tdd/spec-downstream-rides-ask-no-governance-questions/mutation-<TEST-id>.txt`
  carrying `verdict: RED`.
- Per Spec-AC: the suite command above, its exit code, and the assertion text
  naming the observable.
- Review scope: branch diff `main...change/downstream-rides-ask-no-governance-questions`
  over `.aai/scripts/ride-select.mjs`, `.aai/SKILL_SHIP.prompt.md`,
  `.aai/SKILL_PR.prompt.md`, `.aai/system/AUTONOMOUS_LOOP.md`,
  `.aai/ROLE_COMMON.md`, `.aai/AGENTS.md`, `tests/skills/test-aai-ride-select.sh`,
  `tests/skills/test-aai-downstream-autopilot.sh`, `tests/skills/suite-map.yaml`,
  `tests/skills/lib/prompt-diet-ledger.sh`, `tests/skills/test-aai-prompt-diet.sh`.

### Evidence by strategy

Strategy `tdd`: a stored RED artifact per AC-gating test plus the full
verification matrix.

## Registry items closed by this scope

None.

Open items in the same neighbourhood, NOT CLOSED, and why (from
`node .aai/scripts/follow-ups.mjs list --status open`, 2026-10-01):
- `fu-amend-roadmap-driven-ride-sele-1e2448`, `fu-amend-spec-roadmap-takes-direction`
  and every other open `fu-amend-*` (P2) — owner sign-offs owed on earlier
  specs' amendments. This scope changes WHEN such an obligation is surfaced
  (at the merge, not mid-ride); discharging one is still the owner's decision.
- `fu-backlog-is-not-queryable` (P2) — ride selection from the backlog; a
  different capability, untouched here.
