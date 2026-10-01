---
id: spec-roadmap-serves-downstream-projects
type: spec
number: 202
status: implementing
mutation_gate: v1
frozen_sha256: 42d0118456658e059162a0dc55229a0095cee04eb984a97ba49879d61f8e2547
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0201-roadmap-serves-downstream-projects.md
  rfc: null
  pr: []
  commits: []
---

# Spec — the roadmap is an ordered capability list with an opt-in maintenance budget and its own skill

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0201-roadmap-serves-downstream-projects.md
  (AC-001..AC-008; owner direction 2026-10-01 in its Notes).
- Prior specs this scope builds on: SPEC-0168 (spec-roadmap-driven-ride-selection-with-budget,
  the gate and the 1:1 budget), SPEC-0188 (spec-roadmap-takes-direction,
  `roadmap-propose.mjs` harvest/write/bind and its D11 "no automatic invocation"),
  SPEC-0200 (spec-downstream-rides-ask-no-governance-questions, the absent-file
  posture switch).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, no YAML library,
  bash suites).

## Implementation strategy
- Strategy: tdd
- Rationale: recorded at intake (`implementation_strategy.source: intake`,
  autopilot recommendation) and kept. The scope changes the decision of a gate
  every ride executes, adds the first automatic writer of
  `docs/ai/roadmap.yaml` on the ship and close paths, and must prove that the
  budgeted posture this repository runs under is byte-for-byte unchanged. Each
  of those is only evidence when observed RED first.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: a core gate script, a new writer of a governed file on the
  close path, a new skill on four harness trees, canon prose and a PR-bound
  multi-slice ride. The ride already runs in the dedicated worktree
  `/Users/ales/Projects/aai-roadmap` on branch
  `change/roadmap-serves-downstream-projects` (based on origin/main 219ce4ef),
  so the recommendation is satisfied and no new isolation decision is owed.
- User decision: worktree (already in place)
- Base ref: main
- Worktree branch/path: change/roadmap-serves-downstream-projects / /Users/ales/Projects/aai-roadmap
- Inline review scope: not applicable

## Ceremony level

Level 2. No touched path is in `protected_paths_l3` of docs/ai/docs-audit.yaml
(state.mjs, state-engine.mjs, state-core.mjs, allocate-doc-number.mjs,
pre-commit-checks.sh/.ps1, WORKFLOW.md, CONSTITUTION.md — read 2026-10-01).
The design deliberately leaves `.aai/scripts/close-work-item.mjs` and
`.aai/ORCHESTRATION.prompt.md` untouched (D4, D11) and adds no STATE field.

## What is established before this scope starts (measured 2026-10-01 at 219ce4ef)

- `ride-select.mjs` `loadRoadmap()` returns `missing budget.maintenance_per_capability`
  for a roadmap with no `budget:` block and `budget.maintenance_per_capability must be 1`
  for any other value. `tests/skills/test-aai-ride-select.sh` `test_001_validate`
  asserts the no-budget file exits 2 (`bad4.yaml`).
- `nextRide()` returns `action: bind` for a started capability whose
  `maintenance:` slot is unbound, so a capability-only roadmap never advances
  past a started capability; nothing flips a pair to `status: done` except a
  hand edit (all 11 pairs of this repository's roadmap were flipped by hand).
- `gate` refuses an off-roadmap ref: maintenance ("file it to the backlog") or
  not ("add it to docs/ai/roadmap.yaml"); `isMaintenance()` guesses from the
  intake type, title words and slug words.
- Four readers of `docs/ai/roadmap.yaml`: `ride-select.mjs` (closed-shape
  parser), `roadmap-propose.mjs` (lenient locators + certify by spawning
  `ride-select.mjs validate`, byte-exact rollback), `orchestration-dispatch.mjs`
  `roadmapGate()` (spawns the CLI gate, own absent-posture twin), and
  `nothing-left-behind.mjs` `readRoadmapPairs()` (lenient scan; reports an open
  paired maintenance half as `docs_open`).
- `roadmap-propose.mjs write` seeds an ABSENT roadmap with
  `budget:\n  maintenance_per_capability: 1` (buildWriteContent).
- `test_744_no_automatic_invocation_site` refuses any `.aai/*.prompt.md` or
  `orchestration-dispatch.mjs` that names `roadmap-propose` (SPEC-0188 D11).
- `close-work-item.mjs` is content-hash pinned (`tests/skills/lib/close-work-item-pin.sh`,
  TEST-533 requires the allowed-hash array to grow by exactly one per engine change).
- `/aai-ship` with no argument asks for the need and stops. No skill covers the
  roadmap; `docs/USER_GUIDE.md` and `README.md` do not explain it.
- `.aai/AGENTS.md` operator contract rule 4 reads "Rides come from the roadmap,
  1:1"; TEST-007 requires `1:1` somewhere in the contract and at most 40
  lines; TEST-1209 requires rule 4 to carry `docs/ai/roadmap.yaml`, `absent`,
  `not consulted`.
- This repository's `docs/ai/roadmap.yaml` carries `budget: 1`, 11 done pairs
  and 4 wave-2 items; `validate` prints `roadmap OK: 11 pair(s), 4 wave-2 item(s)`
  (TEST-718 pins it). This ride is off-roadmap and entered by an owner
  `--override`.

## Decisions

- D1 — "No budget" is the ABSENCE of the top-level `budget:` key. No new key,
  no `budget: off` value: the closed shape stays as is, a missing block is now
  legal. A `budget:` block that is present must still carry exactly
  `maintenance_per_capability: 1`; an empty `budget:` block, a duplicate, or any
  other value stays invalid (exit 2). This repository's file is untouched and
  validates and gates exactly as before (intake Out of scope).
- D2 — One parser. `loadRoadmap()`, `SLUG`, `MAINT_TYPES` and `roadmapAbsent()`
  move unchanged (except D1) from `ride-select.mjs` into a new
  `.aai/scripts/lib/roadmap-model.mjs`; `ride-select.mjs` and the new
  `roadmap-edit.mjs` import them. `orchestration-dispatch.mjs` keeps its own
  `roadmapAbsent` twin (it spawns the CLI and already has seam TEST-1207);
  `nothing-left-behind.mjs` keeps its lenient scan and gains only budget
  detection, pinned against the CLI by seam TEST-1324.
- D3 — Gate without a budget (`if (!rm.budget) return noBudgetGate(...)`,
  placed right after the existing done-ref refusal): refuses a ref whose own
  document is `done`, a ref in a pair already marked done, and a ref with no
  resolving document (Spec-AC-29 of SPEC-0168: the gate admits only refs that
  exist); admits everything else — maintenance on or off the roadmap, a
  capability off the roadmap, and an on-roadmap item out of order. The roadmap
  ORDER without a budget drives `next` (what `/aai-ship` with no argument
  takes), not a refusal of an explicitly requested ride; a project that wants
  ranked refusals turns the budget on. With a budget every arm is today's code,
  unchanged. Admit lines carry `no maintenance budget`.
- D4 — Roadmap advance on delivery lives in a SIBLING script invoked from
  `.aai/SKILL_PR.prompt.md` step 4c, not inside `close-work-item.mjs`. Reasons:
  the engine is hash-pinned and a one-byte edit reddens four suites with a
  signed re-pin; its `--paired` arm closes DOCUMENTS in one transaction, while
  the roadmap is a different file with its own certifier (`ride-select.mjs
  validate`) and its own rollback; a separate call keeps the close transaction
  and the roadmap edit independently refusable. Cost (residual R2): an operator
  who runs `close-work-item.mjs` by hand outside SKILL_PR does not advance the
  roadmap; `next` without a budget compensates by skipping a pair whose
  capability DOCUMENT is `done` even if the pair was never flipped (D7).
- D5 — Writes live in a new `.aai/scripts/roadmap-edit.mjs`, not in
  `roadmap-propose.mjs`. `roadmap-propose.mjs` keeps harvest/write/bind and its
  SPEC-0188 D11 guarantee (no automatic invocation, TEST-744 narrowed only for
  the user-invoked skill, D9). The automatic paths (ship append, close
  advance) and the menu edits get a small file with one write discipline:
  read original bytes, refuse before writing on any usage or semantic error,
  write, certify by spawning the sibling `ride-select.mjs validate --roadmap
  <p> --docs <d>` (the SPEC-0188 D10 precedent), restore the exact original
  bytes (or remove a file this run created) on a refused certification, exit 1.
  Grammar (exit 0 success or named no-op, 1 refusal with the file
  byte-identical, 2 usage with the file untouched):
  `add --ref <slug> [--at <n>]` · `move --ref <slug> --to <n>` ·
  `done --ref <slug>` · `drop --ref <slug>` · `budget on` · `budget off` ·
  `off --confirm` · `ship-append --ref <slug> --intake <path>` ·
  `advance --ref <slug>`; every verb takes `[--roadmap <p>] [--docs <dir>]`.
- D6 — Ship append (`ship-append`) is a NAMED NO-OP, exit 0, nothing written,
  one line, in each of these cases: roadmap absent (`roadmap absent, nothing
  appended` — ship never turns the gate on in a project that has none),
  budget on (an owner adds capabilities there, via `/aai-roadmap add`), the ref
  already a pair capability or maintenance, the intake type in `MAINT_TYPES`
  (issue, hotfix, techdebt, chore, test, ci). Otherwise it appends
  `  - capability: <ref>` / `    status: active` (the ride is starting now; an
  active pair must resolve to a document and the intake does) before
  `wave_2:`, removes the ref from `wave_2` if listed there (the SPEC-0188
  promotion rule), certifies, and prints exactly `roadmap: appended <ref>`.
  Classification uses the intake TYPE only — no title or slug words: without a
  budget a misclassified fix merely lands on the roadmap as an item that is
  marked done at close (residual R4).
- D7 — `next` without a budget (`nextNoBudget`): walks pairs in order, skips
  `status: done` and a pair whose capability document status is `done`;
  returns `file-intake` for a capability with no document; otherwise returns
  the capability ref (also when it is already implementing — in flight is
  still the next item). It never returns `bind` and never proposes a
  maintenance half. With a budget `nextRide` is unchanged. `next --json`
  gains an additive `path` field (the resolving document path) whenever it
  names a ref with a document, in both postures, so `/aai-ship` with no
  argument rides a path, not a guessed file.
- D8 — `advance --ref <slug>` (close path): absent roadmap, ref not on the
  roadmap, or pair already done: named no-op, exit 0, nothing written. Without
  a budget: the pair whose capability is the ref flips to `done` when that
  document's status is `done`, else no-op. With a budget: the pair containing
  the ref (either half) flips to `done` only when its capability document AND
  its bound maintenance document are both `done`; an unbound or open
  maintenance half leaves the pair as it is. Owner-facing `done --ref` is the
  strict twin: it refuses (exit 1) a ref that is not a pair capability and
  marks the pair done regardless of document status, still certified (a done
  pair whose capability has no document fails `validate` and is restored).
- D9 — Supersession, disclosed: SPEC-0188 D11 ("no prompt invokes
  roadmap-propose") is narrowed to "no prompt EXCEPT the user-invoked
  `.aai/SKILL_ROADMAP.prompt.md`, and never `orchestration-dispatch.mjs`".
  A user typing `/aai-roadmap harvest` is opt-in by name, which is what D11
  protected. `test_744_no_automatic_invocation_site` is amended in place with
  that one-file allowlist plus a positive control (TEST-1330). SPEC-0168
  Spec-AC-01's "a roadmap without budget is invalid" is superseded by
  Spec-AC-01 here; SPEC-0168 and SPEC-0188 are done and their text is not
  edited. `test_001_validate`'s `bad4.yaml` arm is the only pre-existing
  assertion rewritten (it now expects exit 0).
- D10 — `roadmap-propose.mjs write` on an ABSENT roadmap now seeds
  `pairs:` without a `budget:` block (budget is opt-in; the `/aai-roadmap
  harvest` action would otherwise opt a downstream project into the 1:1
  budget silently). The one-line edit in `buildWriteContent` is the only
  change to that file; its four open P3 follow-ups are not touched.
- D11 — Skill wiring. `/aai-roadmap` = `.claude/skills/aai-roadmap/SKILL.md`
  (thin wrapper, same shape as aai-ship) + `.aai/SKILL_ROADMAP.prompt.md`;
  mirrors in `.agents/skills`, `.codex/skills`, `.gemini/skills` (+ the two
  generated READMEs) are produced by `node .aai/scripts/sync-harness-skills.mjs
  --write`, never by hand; PROFILES classifies `SKILL_ROADMAP.prompt.md`,
  `scripts/roadmap-edit.mjs` and `scripts/lib/roadmap-model.mjs` as core (the
  roadmap subsystem travels together, and SKILL_SHIP/SKILL_PR, both core, call
  roadmap-edit); suite-map gains one `aai-roadmap` row for the new suite and
  its globs are also added to the existing `aai-ride-select` row only where
  that suite exercises them; USER_GUIDE gets a Skills Catalog chapter and a
  Quick Reference row (hygiene test_120). `docs/SKILL_CATALOG.html` and
  `docs/skill-catalog-data.json` are regenerated by the close ceremony, not by
  hand. `.aai/ORCHESTRATION.prompt.md` and `.aai/SKILL_LOOP.prompt.md` are NOT
  edited: the loop's gate and `next` calls already do the right thing once the
  scripts do (the intake listed SKILL_LOOP as affected; reading it found no
  sentence that contradicts the new behavior — disclosed narrowing).
- D12 — Skill action map (each WRITE is exactly one script call; the prompt
  never edits YAML): show = `node .aai/scripts/ride-select.mjs show`; add =
  `roadmap-edit.mjs add`; reorder = `roadmap-edit.mjs move`; harvest =
  `roadmap-propose.mjs harvest --direction` then, after the owner picks from a
  menu, `roadmap-propose.mjs write --pick --direction` (the only write);
  done = `roadmap-edit.mjs done`; drop = `roadmap-edit.mjs drop`; budget
  on/off = `roadmap-edit.mjs budget on` / `budget off`; off =
  `roadmap-edit.mjs off --confirm`. Every action is offered as a menu with a
  recommended default (operator contract rule 2); `off` defaults to keeping
  the roadmap. `ride-select.mjs show [--json]` is new and read-only: absent
  roadmap prints one `no roadmap` line and exits 0; invalid exits 2 like
  `validate`; otherwise it lists next item, done, planned/active, wave 2 and
  `maintenance budget: on` or `maintenance budget: off`.
- D13 — Ship wiring (`.aai/SKILL_SHIP.prompt.md`): INPUT with neither a need nor
  a path runs `node .aai/scripts/ride-select.mjs next --json`; a `next` with a
  `path` is ridden as if that path had been passed; any other answer (non-zero
  exit, `next: null`, `bind`, `file-intake`) is printed verbatim and the ride
  asks for the need and stops as today. Step 1a, after an ADMIT, runs
  `node .aai/scripts/roadmap-edit.mjs ship-append --ref <ref_id> --intake <primary_path>`
  and carries its one line into step 6 as `roadmap: <line>`. Close wiring
  (`.aai/SKILL_PR.prompt.md` step 4c): after `close-work-item.mjs` exits 0 or
  6 and before the close commit, run
  `node .aai/scripts/roadmap-edit.mjs advance --ref <slug>`; non-zero = STOP
  and print it (the script already restored the file); when
  `git status --porcelain -- docs/ai/roadmap.yaml` is non-empty, stage
  `docs/ai/roadmap.yaml` in the close commit and add it to the
  `check-committed-scope.mjs` path list. This also carries a ship-append edit
  made at step 1a into the PR.
- D14 — AGENTS.md operator contract rule 4 restated, contract stays at most 40
  lines: the roadmap orders capabilities; the maintenance budget is opt-in and
  only with `budget.maintenance_per_capability: 1` does the gate enforce the
  1:1 pairing and ranked refusals; absent file = not consulted (TEST-1209
  words kept); `/aai-roadmap` is the user path.
- D15 — Files outside the intake's Affected Area this scope must also touch
  (additive disclosure): `.aai/scripts/lib/roadmap-model.mjs` (D2), the three
  mirror trees and their READMEs (D11), `tests/skills/test-aai-prompt-diet.sh`
  (TEST-012 checkpoint). Not touched although listed by the intake:
  `.aai/scripts/orchestration-dispatch.mjs` (seam test only, D2),
  `.aai/scripts/close-work-item.mjs` (D4), `.aai/SKILL_LOOP.prompt.md` (D11).
- D16 — ADDITIVE AMENDMENT of D13 (validation round FAIL, findings F1/F2/F3,
  report VALIDATION-20261001T091301Z). Disclosure first: D7/D13 as frozen made
  no-argument ship ride only a capability that already had a document and
  STOP at `file-intake`, which narrowed the intake To-Be "`/aai-ship` with no
  argument starts the first unfinished capability" without saying so (F3); the
  result for a user was that `add` then `/aai-ship` stopped, a hand-stated need
  was filed under a topic-derived slug, `ship-append` added a second entry and
  the original item stayed `file-intake` forever (F1). The rule now is: when
  `ride-select.mjs next --json` returns `action: file-intake` for a capability,
  `/aai-ship` with no argument RIDES that roadmap item as the need (topic = the
  slug's words, assumptions instead of questions per autopilot default 3) and
  step 1 files the intake with frontmatter `id: <ref>` — the roadmap slug wins
  over the topic-derived slug of DURABLE DOC IDENTITY (the edit is one clause in
  SKILL_SHIP INPUT; the shared INTAKE_COMMON prompt is not touched). The gate
  then admits it and `ship-append` is the already-specified named no-op for a
  listed ref (D6), so the roadmap keeps exactly one entry; `next` afterwards
  names the document's `path`, and after delivery `advance` moves it on. Any
  other answer (non-zero exit, `next: null`, `bind`) is still printed and the
  ride asks for the need. With NO roadmap SKILL_SHIP runs `ride-select.mjs
  show` first and asks for the need without printing a gate refusal (NB1).
  Docs and skill (F2, NB2..NB4): a roadmap exists before a budget can be
  switched on, so USER_GUIDE Example 3 and the posture table start with
  `/aai-roadmap add`; SKILL_ROADMAP `budget on` with no roadmap offers "add a
  first capability" as its recommended menu option; Example 1 quotes the real
  ADMIT line; the item is marked done during the close ceremony before the push;
  `drop` says the last pair cannot be dropped and points to `off`. The
  amendment is recorded with `--signoff none` (autonomous default 5); the
  sign-off owed surfaces at the merge checkpoint.

## Constitution deviations

None.

Article 5 (additive first) was checked: a roadmap with no `budget:` block
moves from invalid to valid, `roadmap-propose.mjs write` stops seeding a budget
into a NEW file, and `next --json` gains a field. Each is a documented
behavior change at a CLI boundary (ride-select header, AGENTS rule 4,
USER_GUIDE section, this spec D1/D7/D10); every existing valid file keeps its
exact behavior. Article 2 (simplicity) was checked for D5: one new script
instead of growing an 838-line file whose own spec forbids automatic callers.

## Acceptance Criteria Mapping

- Spec-AC-01 (maps intake AC-001): `ride-select.mjs validate` SHALL exit 0 on a
  roadmap with no `budget:` block; SHALL exit 2 on an empty `budget:` block, a
  duplicated `budget:` block and `maintenance_per_capability: 2`; and SHALL
  print exactly `roadmap OK: 11 pair(s), 4 wave-2 item(s)` and exit 0 on this
  repository's `docs/ai/roadmap.yaml`.
  Verification: `env -u AAI_ROLE bash tests/skills/test-aai-ride-select.sh`
  (TEST-1301, TEST-1302, TEST-718), exit 0.
- Spec-AC-02 (maps intake AC-002): WHEN the roadmap has no budget, `gate` SHALL
  exit 0 with an ADMIT line containing `no maintenance budget` for an
  off-roadmap `type: issue` ref, an off-roadmap `type: change` ref and an
  on-roadmap ref behind an unfinished pair, and SHALL exit 1 for a ref whose
  document is done and for a ref with no resolving document; WHEN the same
  fixtures carry `budget.maintenance_per_capability: 1`, the first three SHALL
  exit 1 exactly as today, and every pre-existing ride-select test except the
  rewritten `bad4.yaml` arm SHALL pass unmodified.
  Verification: TEST-1303, TEST-1304, TEST-1305, exit 0.
- Spec-AC-03 (maps intake AC-003): WHEN the roadmap has no budget, `next --json`
  SHALL never print `"action":"bind"`; SHALL skip a pair marked done and a
  pair whose capability document is done; SHALL name a started capability-only
  pair's capability; and in both postures SHALL carry a `path` field equal to
  the resolving document path whenever it names a ref with a document.
  Verification: TEST-1306, TEST-1307, TEST-1308, exit 0.
- Spec-AC-04 (maps intake AC-005, show action): `ride-select.mjs show` SHALL
  exit 0 and print the next item and `maintenance budget: off` for a no-budget
  fixture, `maintenance budget: on` for a budget fixture, and one line
  containing `no roadmap` for an absent path; `show --json` SHALL carry
  `budget` (true or false), `next`, `pairs` and `wave_2`; an invalid roadmap
  SHALL exit 2.
  Verification: TEST-1309, exit 0.
- Spec-AC-05 (maps intake AC-005): each `roadmap-edit.mjs` verb `add`, `move`,
  `done`, `drop`, `budget on`, `budget off`, `off --confirm` SHALL perform its
  one edit and leave a file that `ride-select.mjs validate` accepts (or, for
  `off`, no file); for every verb an invalid input (unknown ref, duplicate add,
  non-slug ref, out-of-range position, budget already in the requested state,
  `off` without `--confirm`, a `done` that fails certification, an edit of an
  already-invalid roadmap) SHALL exit 1 or 2 with the roadmap's sha256
  unchanged and no extra file left in its directory.
  Verification: TEST-1311 .. TEST-1316, exit 0.
- Spec-AC-06 (maps intake AC-006): WHEN no budget is set and the intake is
  `type: change` and its ref is not on the roadmap, `roadmap-edit.mjs
  ship-append` SHALL append that ref as an `active` capability before
  `wave_2:`, print exactly `roadmap: appended <ref>`, and leave a roadmap
  `validate` accepts and `gate` admits for that ref; WHEN the roadmap is
  absent, the budget is on, the intake type is a maintenance type, or the ref
  is already on the roadmap, it SHALL exit 0, print one line naming the
  reason and leave the file byte-identical (or absent).
  Verification: TEST-1317, TEST-1318, TEST-1319, exit 0.
- Spec-AC-07 (maps intake AC-004): `roadmap-edit.mjs advance --ref <ref>`
  SHALL flip a no-budget pair to `status: done` exactly when the capability
  document is done, and a budget pair exactly when both its capability and
  bound maintenance documents are done; in every other case (absent roadmap,
  off-roadmap ref, document not done, maintenance half open or unbound) it
  SHALL exit 0, print one no-op line and write nothing.
  Verification: TEST-1320, TEST-1321, exit 0.
- Spec-AC-08 (seam, D4): IN a fixture git repository, after the REAL
  `close-work-item.mjs` closes a capability document, `advance` SHALL flip
  that pair and `ride-select.mjs next --json` SHALL then name the following
  pair; before the close, `advance` SHALL be a no-op; and
  `.aai/scripts/close-work-item.mjs` SHALL be byte-identical to its blob at
  the merge-base with origin/main.
  Verification: TEST-1322 plus `env -u AAI_ROLE bash tests/skills/test-aai-close-work-item.sh`, exit 0.
- Spec-AC-09 (seam, D2/D3): FOR a no-budget fixture root and a budget fixture
  root that each carry the same open off-roadmap `type: issue` intake,
  `orchestration-dispatch.mjs` buildSnapshot's candidate `gate.admitted` SHALL
  equal (CLI `gate` exit == 0) and SHALL be true for no budget and false for
  budget, with `consulted` true in both.
  Verification: TEST-1323, exit 0.
- Spec-AC-10 (seam, D2): FOR a roadmap pair whose bound maintenance document
  is still draft, `nothing-left-behind.mjs --ref <capability> --json` SHALL
  report `docs_open` 0 without a budget and 1 with a budget, and its budget
  reading SHALL agree with `ride-select.mjs show --json` `budget` on both
  fixtures.
  Verification: TEST-1324, exit 0.
- Spec-AC-11 (D10): `roadmap-propose.mjs write` against an absent roadmap
  SHALL create a file containing no `budget:` line that `validate` accepts
  and whose `next` never proposes `bind`.
  Verification: TEST-1310, exit 0.
- Spec-AC-12 (maps intake AC-005, registration): `.claude/skills/aai-roadmap/SKILL.md`
  SHALL exist with `name: aai-roadmap`, a `description:` line, a pointer to
  `.aai/SKILL_ROADMAP.prompt.md` and at most 45 lines;
  `node .aai/scripts/sync-harness-skills.mjs --check` SHALL exit 0 with
  `aai-roadmap/SKILL.md` present in all three mirror trees;
  `test-aai-layer-profiles.sh` SHALL exit 0 with the three new `.aai` files
  classified core; `tests/skills/suite-map.yaml` SHALL carry exactly one
  `aai-roadmap` row selected by a diff of `roadmap-edit.mjs` or
  `SKILL_ROADMAP.prompt.md`; hygiene-pack test_120 SHALL pass with
  `aai-roadmap` in both the Skills Catalog and the Quick Reference.
  Verification: TEST-1325 .. TEST-1328, exit 0.
- Spec-AC-13 (maps intake AC-005, actions): `.aai/SKILL_ROADMAP.prompt.md`
  SHALL name, for each of show, add, reorder, harvest, done, drop, budget on,
  budget off and off, the exact command of D12; SHALL state that each action
  is offered as a menu with a recommended default; SHALL contain
  `never hand-edit`; and no `.aai/*.prompt.md` other than it, and not
  `orchestration-dispatch.mjs`, SHALL contain `roadmap-propose`.
  Verification: TEST-1329, TEST-1330, TEST-1340, exit 0.
- Spec-AC-14 (maps intake AC-006 and AC-004 wiring): `.aai/SKILL_SHIP.prompt.md`
  INPUT SHALL name `ride-select.mjs next --json` and the `path` field for the
  no-argument case, step 1a SHALL name
  `roadmap-edit.mjs ship-append --ref <ref_id> --intake <primary_path>` and
  `roadmap: appended`, and step 6 SHALL carry a `roadmap:` line;
  `.aai/SKILL_PR.prompt.md` step 4c SHALL name
  `roadmap-edit.mjs advance --ref <slug>` after the `close-work-item.mjs`
  call and before the close commit, and SHALL name `docs/ai/roadmap.yaml` as
  staged in the close commit when changed; TEST-1210, TEST-1211 and
  golden-flow TEST-006 SHALL stay green.
  Verification: TEST-1331, TEST-1332, TEST-1338, exit 0.
- Spec-AC-15 (maps intake AC-007): `docs/USER_GUIDE.md` SHALL carry
  `## Roadmap: when and how` with a Table of Contents entry and three H3
  worked examples (no roadmap, roadmap without budget, roadmap with budget),
  each containing at least one `/aai-roadmap` or `/aai-ship` invocation;
  `README.md` SHALL link to that section; `docs/product/roadmap.md` SHALL pass
  `validateProductFrontmatter` and return no `missingProductSections`, with
  `capability: roadmap`; AGENTS.md rule 4 SHALL contain `order`,
  `budget is opt-in`, `1:1`, `docs/ai/roadmap.yaml`, `absent`,
  `not consulted` and `/aai-roadmap`, with the contract at most 40 lines.
  Verification: TEST-1333, TEST-1334, TEST-1335, TEST-1339 plus TEST-007, TEST-1209, exit 0.
- Spec-AC-16 (maps intake AC-008): the prompt-diet ledger SHALL carry one
  `JUSTIFIED_ADDITIONS` entry for `roadmap-serves-downstream-projects` whose
  byte count equals the measured corpus growth of this diff,
  `test-aai-prompt-diet.sh` SHALL exit 0 with the TEST-012 checkpoint bumped,
  and `.aai/ORCHESTRATION.prompt.md` SHALL be byte-identical to its blob at
  the merge-base with origin/main.
  Verification: TEST-1336, TEST-1337, exit 0.

## Acceptance Criteria Status

| Spec-AC    | Description | Status  | Evidence | Review-By | Notes |
|------------|-------------|---------|----------|-----------|-------|
| Spec-AC-01 | WHEN a roadmap has no budget block validate SHALL exit 0; an empty, duplicate or non-1 budget SHALL exit 2; the shipped roadmap summary SHALL stay byte-identical | planned | — | — | D1 D2 D9 |
| Spec-AC-02 | WHEN there is no budget gate SHALL admit off-roadmap maintenance, off-roadmap capability and out-of-order roadmap refs and refuse done or documentless refs; with a budget the same fixtures SHALL refuse as today | planned | — | — | D3 |
| Spec-AC-03 | WHEN there is no budget next SHALL never propose bind, SHALL skip done pairs and pairs whose capability doc is done, and next json SHALL carry a path field | planned | — | — | D7 |
| Spec-AC-04 | ride-select show SHALL print next item and budget on or off, say no roadmap for an absent path, emit json fields and exit 2 when invalid | planned | — | — | D12 |
| Spec-AC-05 | Each roadmap-edit verb SHALL make one certified edit and every refused input SHALL leave the roadmap sha256 unchanged | planned | — | — | D5 |
| Spec-AC-06 | ship-append SHALL append an active capability with one reported line when there is no budget and SHALL be a named no-op for absent, budget on, maintenance type or already listed | planned | — | — | D6 |
| Spec-AC-07 | advance SHALL flip a pair to done only when its documents are done per posture and otherwise write nothing | planned | — | — | D8 |
| Spec-AC-08 | IN a fixture repo the real close-work-item close followed by advance SHALL move next to the following pair, and close-work-item.mjs SHALL stay byte-identical | planned | — | — | seam S1 D4 |
| Spec-AC-09 | The dispatch candidate gate verdict SHALL equal the CLI gate verdict on a no-budget and a budget fixture | planned | — | — | seam S2 |
| Spec-AC-10 | nothing-left-behind SHALL report no paired maintenance half without a budget and one with a budget, agreeing with show json | planned | — | — | seam S3 |
| Spec-AC-11 | write against an absent roadmap SHALL create a budget-free file that validates and never proposes bind | planned | — | — | D10 |
| Spec-AC-12 | The aai-roadmap skill SHALL be registered in the wrapper, three mirrors, PROFILES, suite-map and both USER_GUIDE skill lists | planned | — | — | D11 |
| Spec-AC-13 | SKILL_ROADMAP SHALL map every action to one script command as a menu and no other prompt SHALL name roadmap-propose | planned | — | — | D9 D12 |
| Spec-AC-14 | SKILL_SHIP SHALL state the no-argument next path and the ship-append line; SKILL_PR 4c SHALL run advance and stage the roadmap in the close commit | planned | — | — | D13 seam S4 |
| Spec-AC-15 | USER_GUIDE SHALL carry the roadmap section with three examples, README SHALL point to it, the product doc SHALL pass the gate, AGENTS rule 4 SHALL state order and opt-in budget | planned | — | — | D14 |
| Spec-AC-16 | The diet ledger SHALL credit the measured growth, prompt-diet SHALL pass and ORCHESTRATION SHALL stay byte-identical | planned | — | — | companion obligations |

## Implementation plan

Components (by slice; the brief carries the same cut):

Slice A — budget switch in the read path, plus the write infrastructure.
1. New `.aai/scripts/lib/roadmap-model.mjs`: move `loadRoadmap`, `SLUG`,
   `MAINT_TYPES`, `ABSENT_CODES` and `roadmapAbsent` out of `ride-select.mjs`
   verbatim, then apply D1: replace the unconditional
   `if (!rm.budget) return { error: 'missing budget...' }` and the `!== 1` check
   with `const budgetDeclared = seenSections.has('budget');` and, when
   `budgetDeclared`, refuse `budget: block present but maintenance_per_capability is missing`
   and the existing `must be 1` message. Keep the line `if (!rm.pairs.length) return { error: 'no pairs' };`.
2. `.aai/scripts/ride-select.mjs`: import from the lib (no local copies left);
   header lines 1-20 keep `absent`, `not consulted`, `refuse` (TEST-1209) and
   add one sentence naming the opt-in budget and `show`; add
   `function noBudgetGate(ctx)` (ctx = { a, rm, pair, intake, admit, deny })
   with the three arms of D3, using `if (!ctx.intake) return ctx.deny(...)`;
   in the gate body, directly after the done-ref refusal,
   `if (!rm.budget) return noBudgetGate({ ... });`. Add
   `function nextNoBudget(rm, docsDir)` (D7; local `capStatus`, line
   `if (capStatus === 'done') continue;`) and
   `function pickNext(rm, docsDir)` whose body is
   `if (!rm.budget) return nextNoBudget(rm, docsDir);` then
   `return nextRide(rm, docsDir);`; `main()` (`next`) and `cmdShow` both call
   `pickNext`. Both walkers return `path` from `findDoc` for a resolved ref. The plain-ref JSON becomes
   `JSON.stringify({ next: n.ref, half: n.half, pair: n.pair, path: n.path })`.
   Add `show` to the command whitelist and `cmdShow(a, loaded)`: absent ->
   one line containing `no roadmap` and exit 0 (checked with `roadmapAbsent`
   before the load error); load error -> usage exit 2; text output prints
   `maintenance budget: on` or `maintenance budget: off`, the next item (same
   `pickNext`), done count, planned/active list, wave 2; `--json` prints
   `{ roadmap, budget, next, pairs, wave_2 }`.
3. `.aai/scripts/roadmap-propose.mjs` `buildWriteContent(null, block)`: seed
   `pairs:\n${appendedBlock}` without the budget lines (D10). Nothing else in
   the file changes.
4. New `.aai/scripts/roadmap-edit.mjs` (Node stdlib, imports the lib): argv
   parser per D5; shared `commitEdit(a, original, existed, newText, okLine)`
   that writes, certifies by spawning `ride-select.mjs validate --roadmap
   <p> --docs <d>` (sibling path via import.meta.url), and on refusal calls
   `restore(a.roadmap, original, existed);` then exits 1 with the validator's
   stderr. Before any write every verb loads the CURRENT file with
   `loadRoadmap` and refuses (exit 1) an already-invalid roadmap. Slice A
   ships `add` (`const at = a.at === null ? count : a.at - 1`, block insert
   before `wave_2:`, promotion out of `wave_2`, absent file -> create
   `pairs:` without budget and disclose `the ride gate is now ON`) and
   `ship-append` (D6: `if (roadmapAbsent(a.roadmap)) return noop('roadmap absent, nothing appended')`,
   `if (loaded.roadmap.budget) return noop(...)`,
   `if (MAINT_TYPES.has(intake.type)) return noop(...)`,
   `const SHIP_STATUS = 'active';`). `--intake` is read with the docs-model
   `parseFrontmatter`; an intake whose id differs from `--ref` is a usage
   error (exit 2).

Slice B — the remaining edit verbs, the close-path advance and the seams.
5. `roadmap-edit.mjs`: `move` (split the pairs section into pair blocks,
   `blocks.splice(to, 0, moved)`), `done` (`setPairStatus(text, a.ref, 'done')`),
   `drop` (remove the pair block or the `wave_2` line), `budget on` (insert
   `budget:\n  maintenance_per_capability: 1\n` before `pairs:`), `budget off`
   (`const stripped = removeBudget(text)`), `off --confirm`
   (`fs.unlinkSync(a.roadmap)`; without `--confirm` exit 2), `advance` (D8;
   `const capStatus = docStatus(a.docs, pair.capability)`,
   `if (capStatus !== 'done') return noop(...)`, and with a budget
   `if (maintStatus !== 'done') return noop(...)`; `docStatus` reads the
   frontmatter `status:` through `parseFrontmatter` over the same five doc
   dirs `ride-select.mjs findDoc` walks).
6. `.aai/scripts/nothing-left-behind.mjs` `readRoadmapPairs`: set
   `hasBudget` when a top-level `budget:` line is seen and end with
   `if (!hasBudget) return [];` so an unbudgeted roadmap reports no paired
   half (its lenient scan is otherwise unchanged).
7. `.aai/scripts/orchestration-dispatch.mjs`: no change; seam test only.
8. `.aai/scripts/close-work-item.mjs`: no change; seam test only.

Slice C — skill, canon prose, docs and governance.
9. `.claude/skills/aai-roadmap/SKILL.md` (thin wrapper modelled on aai-ship),
   `.aai/SKILL_ROADMAP.prompt.md` (D12, terse: no-action show then a menu;
   one command per action; refusal output is printed verbatim; `never
   hand-edit` docs/ai/roadmap.yaml), then
   `node .aai/scripts/sync-harness-skills.mjs --write` for the mirrors.
10. `.aai/SKILL_SHIP.prompt.md` INPUT, 1a and step 6 per D13 (keep every
    TEST-1210/TEST-1211 phrase); `.aai/SKILL_PR.prompt.md` step 4c bullet per
    D13 placed after the close-work-item exit-code paragraph and before
    `clear-focus`; `.aai/AGENTS.md` rule 4 per D14.
11. `.aai/system/PROFILES.yaml` core entries (with one comment line each,
    the house style); `tests/skills/suite-map.yaml` row `aai-roadmap` with
    globs `.aai/scripts/roadmap-edit.mjs`, `.aai/scripts/lib/roadmap-model.mjs`,
    `.aai/SKILL_ROADMAP.prompt.md`, `.claude/skills/aai-roadmap/SKILL.md`,
    `.aai/scripts/nothing-left-behind.mjs`, `.aai/scripts/ride-select.mjs`;
    add `.aai/scripts/lib/roadmap-model.mjs` to the `aai-ride-select` row.
12. Docs: `docs/USER_GUIDE.md` Quick Reference row, Skills Catalog chapter
    (under "2. Intake and Planning"), `## Roadmap: when and how` placed
    before `## Best Practices` with a TOC entry; `README.md` one pointer line
    in `## Orientation`; `docs/product/roadmap.md` from
    `.aai/templates/PRODUCT_TEMPLATE.md` (`capability: roadmap`,
    `delivered_by: [roadmap-serves-downstream-projects]`, this spec's path).
    The generated `## Delivered features (generated)` block is not
    hand-edited.
13. Governance last: measure the corpus growth under plain bash with
    `/usr/bin/wc -c` against the base commit, append ONE
    `JUSTIFIED_ADDITIONS` entry at the real end of the array in
    `tests/skills/lib/prompt-diet-ledger.sh`, bump the TEST-012 checkpoint in
    `tests/skills/test-aai-prompt-diet.sh`.

New suite `tests/skills/test-aai-roadmap.sh` (`set -u`, never `set -e`
around `$?`; every fixture dir guarded `[[ -n "$d" && "$d" = /* ]]` before a
`cd` or `git -C`; fixture repos `git init -b main` with their own
`user.email`/`user.name`; each test function wired into `main()`). Fixture
docs follow the `write_doc` helper shape of test-aai-ride-select.sh; the
close-seam fixture follows `new_fixture_repo` / `write_change_doc` /
`run_close` of test-aai-close-work-item.sh (copied, not sourced); the
dispatch seam follows TEST-1207 in test-aai-downstream-autopilot.sh.

Edge cases:
- A no-budget roadmap whose pairs still carry `maintenance:` lines (a
  project that ran `budget off`): legal; the lines are inert for `gate` and
  `next`, `nothing-left-behind` ignores them, `budget on` makes them live
  again — the toggle is reversible without data loss.
- `add --at` beyond the end, `move --to 0`: usage exit 2.
- `drop` of an `active` pair is allowed (owner decision through the menu);
  `drop` of a ref in neither pairs nor wave_2 refuses.
- `ship-append` when the intake id is already in `wave_2`: promoted (removed
  from wave_2, appended as active).
- `advance` on a maintenance ref without a budget: not a pair capability ->
  named no-op.
- A CRLF roadmap: `loadRoadmap` already normalizes; edit verbs write LF and
  the certification is the authority (disclosed, R5).

## Test Plan

Rows in slice A land in `tests/skills/test-aai-ride-select.sh` except
TEST-1311 and TEST-1317..1319; every other row lands in the new
`tests/skills/test-aai-roadmap.sh` unless its file path says otherwise. Every
row is observed RED on the pre-change tree or under its Mutation before it
counts green; RED and mutation records go to
`docs/ai/tdd/spec-roadmap-serves-downstream-projects/`. Mutation cells name
the intended code of the Implementation plan; the implementer reconciles an
anchor to the code as written and discloses each reconciliation (restamp).
Slice cut: A = TEST-1301..1311 and TEST-1317..1319; B = TEST-1312..1316 and
TEST-1320..1324; C = TEST-1325..1337.

| Test ID  | Spec-AC    | Type        | File path (expected)                  | Description | Mutation | Status  |
|----------|------------|-------------|---------------------------------------|-------------|----------|---------|
| TEST-1301 | Spec-AC-01 | integration | tests/skills/test-aai-ride-select.sh | test_001 bad4 arm rewritten plus a new arm: a pairs-only roadmap and a pairs plus wave_2 roadmap with no budget block validate exit 0 with the roadmap OK summary | `sed:s/  if \(!rm\.pairs\.length\) return/  if (!rm.budget) return { error: 'missing budget' }; if (!rm.pairs.length) return/` in .aai/scripts/lib/roadmap-model.mjs | green |
| TEST-1302 | Spec-AC-01 | integration | tests/skills/test-aai-ride-select.sh | an empty budget block, a duplicated budget block and maintenance_per_capability 2 each exit 2; the shipped roadmap still prints the exact TEST-718 summary | `sed:s/const budgetDeclared = seenSections\.has\('budget'\)/const budgetDeclared = false/` in .aai/scripts/lib/roadmap-model.mjs | green |
| TEST-1303 | Spec-AC-02 | integration | tests/skills/test-aai-ride-select.sh | no-budget fixture: gate admits an off-roadmap issue ref, an off-roadmap change ref and a ref of the second pair while the first is unfinished, each ADMIT line containing no maintenance budget, and no EVENTS line is written | `sed:s/if \(!rm\.budget\) return noBudgetGate/if (false) return noBudgetGate/` in .aai/scripts/ride-select.mjs | green |
| TEST-1304 | Spec-AC-02 | integration | tests/skills/test-aai-ride-select.sh | no-budget fixture: gate refuses exit 1 a ref whose document is done and a ref with no resolving document, each with REFUSED on stderr | `sed:s/if \(!ctx\.intake\) return ctx\.deny/if (false) return ctx.deny/` in .aai/scripts/ride-select.mjs | green |
| TEST-1305 | Spec-AC-02 | integration | tests/skills/test-aai-ride-select.sh | the same three admit fixtures with a budget block refuse exit 1 with today's reasons (maintenance not on the roadmap, not on the roadmap, pair ahead) | `sed:s/if \(!rm\.budget\) return noBudgetGate/if (true) return noBudgetGate/` in .aai/scripts/ride-select.mjs | green |
| TEST-1306 | Spec-AC-03 | integration | tests/skills/test-aai-ride-select.sh | no-budget next json over a started capability-only pair names that capability with half capability and no action bind; a done first pair is skipped | `sed:s/if \(!rm\.budget\) return nextNoBudget/if (false) return nextNoBudget/` in .aai/scripts/ride-select.mjs | green |
| TEST-1307 | Spec-AC-03 | integration | tests/skills/test-aai-ride-select.sh | no-budget next skips a pair whose status is planned but whose capability document status is done and names the following pair | `sed:s/if \(capStatus === 'done'\) continue;/void 0;/` in .aai/scripts/ride-select.mjs | green |
| TEST-1308 | Spec-AC-03 | integration | tests/skills/test-aai-ride-select.sh | next json carries path equal to the resolving fixture document in a no-budget and in a budget fixture | `sed:s/, path: n\.path//` in .aai/scripts/ride-select.mjs | green |
| TEST-1309 | Spec-AC-04 | integration | tests/skills/test-aai-ride-select.sh | show prints maintenance budget off and the next item for no budget, maintenance budget on for a budget fixture, a no roadmap line exit 0 for an absent path, json keys budget next pairs wave_2, and exit 2 for a malformed file | `sed:s/maintenance budget: off/maintenance budget: on/` in .aai/scripts/ride-select.mjs | green |
| TEST-1310 | Spec-AC-11 | integration | tests/skills/test-aai-ride-select.sh | write --pick 1 against an absent roadmap creates a file with no budget line that validate accepts and whose next json never carries action bind | `patch:docs/ai/tdd/spec-roadmap-serves-downstream-projects/mutation-TEST-1310.patch` restores the budget seed lines in buildWriteContent of .aai/scripts/roadmap-propose.mjs | green |
| TEST-1311 | Spec-AC-05 | integration | tests/skills/test-aai-roadmap.sh | add appends a planned capability-only pair before wave_2 with all prior pair bytes unchanged, add --at 1 puts it first, add on an absent path creates a budget-free roadmap and prints gate is now ON; validate exit 0 each time | `sed:s/const at = a\.at === null \? count : a\.at - 1/const at = count/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1312 | Spec-AC-05 | integration | tests/skills/test-aai-roadmap.sh | move --ref third --to 1 makes it the first pair, every pair block keeps its own lines, and no-budget next names it | `sed:s/blocks\.splice\(to, 0, moved\)/blocks.push(moved)/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1313 | Spec-AC-05 | integration | tests/skills/test-aai-roadmap.sh | done flips a capability pair with a document to status done; drop removes a pair block including its maintenance line and separately removes a wave_2 entry; validate exit 0 | `sed:s/setPairStatus\(text, a\.ref, 'done'\)/setPairStatus(text, a.ref, 'active')/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1314 | Spec-AC-05 | integration | tests/skills/test-aai-roadmap.sh | budget on adds the block and show json then reports budget true and next proposes bind for a started capability-only pair; budget off removes it and show json reports false; repeating either exits 1 byte-identical | `sed:s/const stripped = removeBudget\(text\)/const stripped = text/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1315 | Spec-AC-05 | integration | tests/skills/test-aai-roadmap.sh | off --confirm removes the roadmap file and gate then admits with roadmap absent; off without --confirm exits 2 with the file intact; off on an absent path exits 1 | `sed:s/fs\.unlinkSync\(a\.roadmap\)/void 0/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1316 | Spec-AC-05 | integration | tests/skills/test-aai-roadmap.sh | refusal matrix over every verb (unknown ref, duplicate add, non-slug, out-of-range position, done of a planned capability with no document which fails certification, edit of an already-invalid roadmap): exit 1 or 2, sha256 unchanged, directory listing unchanged; positive control that the certification refusal arm really wrote and restored (validator stderr is echoed) | `sed:s/restore\(a\.roadmap, original, existed\);/void 0;/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1317 | Spec-AC-06 | integration | tests/skills/test-aai-roadmap.sh | no-budget fixture, change-type intake off the roadmap: ship-append prints exactly roadmap: appended ref, the new pair carries status active before wave_2, validate exit 0 and gate admits the ref | `sed:s/const SHIP_STATUS = 'active'/const SHIP_STATUS = 'planned'/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1318 | Spec-AC-06 | integration | tests/skills/test-aai-roadmap.sh | named no-op arms exit 0 with the file byte-identical: budget on, issue-type intake, ref already a pair capability; positive control that the same call on the appendable fixture does write | `sed:s/if \(MAINT_TYPES\.has\(intake\.type\)\) return noop/if (false) return noop/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1319 | Spec-AC-06 | integration | tests/skills/test-aai-roadmap.sh | ship-append against an absent roadmap exits 0, prints roadmap absent, creates no file, and gate afterwards still admits with roadmap absent | `sed:s/if \(roadmapAbsent\(a\.roadmap\)\) return noop\('roadmap absent, nothing appended'\)/if (false) return 0/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1320 | Spec-AC-07 | integration | tests/skills/test-aai-roadmap.sh | no-budget advance flips the pair when the capability document is done; no-op and byte-identical when it is implementing, when the ref is off the roadmap, and when the roadmap is absent (no file created) | `sed:s/if \(capStatus !== 'done'\) return noop/if (false) return noop/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1321 | Spec-AC-07 | integration | tests/skills/test-aai-roadmap.sh | budget advance: capability done and maintenance draft leaves the pair unchanged; both done flips it via either ref; an unbound maintenance slot leaves it unchanged | `sed:s/if \(maintStatus !== 'done'\) return noop/if (false) return noop/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1322 | Spec-AC-08 | integration | tests/skills/test-aai-roadmap.sh | seam: fixture git repo, advance before close is a no-op, the real close-work-item.mjs closes the capability document, advance then flips the pair, next json names the second pair; close-work-item.mjs blob equals its merge-base blob | `sed:s/const capStatus = docStatus\(a\.docs, pair\.capability\)/const capStatus = 'done'/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1323 | Spec-AC-09 | integration | tests/skills/test-aai-roadmap.sh | seam: no-budget and budget fixture roots with the same open off-roadmap issue intake; buildSnapshot candidate gate admitted equals CLI gate exit 0, is true without budget and false with budget, consulted true in both | `sed:s/if \(!rm\.budget\) return noBudgetGate/if (false) return noBudgetGate/` in .aai/scripts/ride-select.mjs | green |
| TEST-1324 | Spec-AC-10 | integration | tests/skills/test-aai-roadmap.sh | seam: pair with a draft bound maintenance doc; nothing-left-behind json docs_open 0 without budget and 1 with budget; its budget reading agrees with ride-select show json on both fixtures | `sed:s/if \(!hasBudget\) return \[\];/void 0;/` in .aai/scripts/nothing-left-behind.mjs | green |
| TEST-1325 | Spec-AC-12 | integration | tests/skills/test-aai-roadmap.sh | wrapper carries name aai-roadmap, a description and the SKILL_ROADMAP pointer within 45 lines; sync-harness-skills --check exits 0 and all three mirror trees carry aai-roadmap/SKILL.md | `sed:s/name: aai-roadmap/name: aai-roadmaps/` in .agents/skills/aai-roadmap/SKILL.md | green |
| TEST-1326 | Spec-AC-12 | integration | tests/skills/test-aai-roadmap.sh | test-aai-layer-profiles.sh exits 0 and the core list names SKILL_ROADMAP.prompt.md, scripts/roadmap-edit.mjs and scripts/lib/roadmap-model.mjs; check-vendored-script-deps is clean | `sed:s/  - \.aai\/scripts\/roadmap-edit\.mjs\n//` in .aai/system/PROFILES.yaml | green |
| TEST-1327 | Spec-AC-12 | integration | tests/skills/test-aai-roadmap.sh | suite-map carries exactly one aai-roadmap row and select-suites selects aai-roadmap for a diff of roadmap-edit.mjs and of SKILL_ROADMAP.prompt.md | `sed:s/  aai-roadmap:\n    globs:\n(?:      - [^\n]*\n)+\n//` in tests/skills/suite-map.yaml | green |
| TEST-1328 | Spec-AC-12 | integration | tests/skills/test-aai-roadmap.sh | hygiene-pack test_120 selector exits 0 with aai-roadmap in the Skills Catalog and the Quick Reference | `sed:s/#### .\/aai-roadmap./#### X/` in docs/USER_GUIDE.md | green |
| TEST-1329 | Spec-AC-13 | unit | tests/skills/test-aai-roadmap.sh | SKILL_ROADMAP names the nine action commands of D12, the menu with a recommended default, and never hand-edit, and contains no instruction to edit the YAML | `sed:s/roadmap-edit\.mjs move/roadmap-edit.mjs reorder/` in .aai/SKILL_ROADMAP.prompt.md | green |
| TEST-1330 | Spec-AC-13 | unit | tests/skills/test-aai-ride-select.sh | test_744 amended in place: no .aai prompt except SKILL_ROADMAP.prompt.md and not orchestration-dispatch.mjs names roadmap-propose; positive control that SKILL_ROADMAP.prompt.md does | `sed:s/roadmap-edit\.mjs ship-append/roadmap-propose.mjs ship-append/` in .aai/SKILL_SHIP.prompt.md | green |
| TEST-1331 | Spec-AC-14 | unit | tests/skills/test-aai-roadmap.sh | SKILL_SHIP INPUT names ride-select.mjs next --json and the path field, step 1a names the ship-append command and roadmap: appended, step 6 carries a roadmap line; TEST-1210 and TEST-1211 selectors of test-aai-downstream-autopilot.sh exit 0 | `sed:s/ride-select\.mjs next --json/ride-select.mjs next/` in .aai/SKILL_SHIP.prompt.md | green |
| TEST-1332 | Spec-AC-14 | unit | tests/skills/test-aai-roadmap.sh | SKILL_PR step 4c names roadmap-edit.mjs advance --ref after the close-work-item.mjs call line and before the close commit line, and names docs/ai/roadmap.yaml as staged when changed; golden-flow TEST-006 selector exits 0 | `sed:s/roadmap-edit\.mjs advance/roadmap-edit.mjs advanc/` in .aai/SKILL_PR.prompt.md | green |
| TEST-1333 | Spec-AC-15 | unit | tests/skills/test-aai-roadmap.sh | USER_GUIDE carries the Roadmap when and how H2 with a TOC entry and three H3 examples each naming an aai-roadmap or aai-ship invocation; README links to the section anchor | `sed:s/## Roadmap: when and how/## Roadmap/` in docs/USER_GUIDE.md | green |
| TEST-1334 | Spec-AC-15 | unit | tests/skills/test-aai-roadmap.sh | docs/product/roadmap.md passes validateProductFrontmatter and missingProductSections is empty, capability roadmap, delivered_by names this ref | `sed:s/## What it does/## What it did/` in docs/product/roadmap.md | green |
| TEST-1335 | Spec-AC-15 | unit | tests/skills/test-aai-roadmap.sh | AGENTS rule 4 contains order, budget is opt-in, 1:1, docs/ai/roadmap.yaml, absent, not consulted and /aai-roadmap; operator contract at most 40 lines; TEST-007 and TEST-1209 selectors exit 0 | `sed:s/budget is opt-in/budget is optional/` in .aai/AGENTS.md | green |
| TEST-1336 | Spec-AC-16 | integration | tests/skills/test-aai-prompt-diet.sh | the ledger entry for this ref equals the measured corpus growth and the TEST-012 checkpoint moves by the same amount; the whole suite exits 0 | `sed:s/\nJUSTIFIED_ADDITIONS\+=\( "[0-9]* roadmap-serves-downstream-projects[^\n]*//` in tests/skills/lib/prompt-diet-ledger.sh | green |
| TEST-1337 | Spec-AC-16 | integration | tests/skills/test-aai-roadmap.sh | .aai/ORCHESTRATION.prompt.md git hash-object equals the blob at the merge-base with origin/main (skips with a named reason when origin/main is unresolvable, never passes vacuously) | `patch:docs/ai/tdd/spec-roadmap-serves-downstream-projects/mutation-TEST-1337.patch` appends one line to .aai/ORCHESTRATION.prompt.md | green |
| TEST-1338 | Spec-AC-14 | integration | tests/skills/test-aai-roadmap.sh | D16: add twice, then the no-argument ship steps run with the real scripts: next returns file-intake, the intake is filed with id equal to the roadmap slug under a topic-derived file name, the gate admits, ship-append is a no-op, the roadmap keeps exactly two entries, next then names the document path, and after the close advance the next ship takes the second item; a topic-derived id control duplicates the entry; SKILL_SHIP INPUT names the carve | `sed:s/wins over the topic-derived slug/loses to the topic-derived slug/` in .aai/SKILL_SHIP.prompt.md | green |
| TEST-1339 | Spec-AC-15 | integration | tests/skills/test-aai-roadmap.sh | D16: the command lines of USER_GUIDE Examples 2 and 3 are extracted from the guide and replayed in order in a fresh fixture project, each step exits 0 and the ship step rides the first item; Example 1 quotes the real ADMIT line | `sed:s/\/aai-roadmap add          # the first capability[^\n]*\n//` in docs/USER_GUIDE.md | green |
| TEST-1340 | Spec-AC-13 | unit | tests/skills/test-aai-roadmap.sh | D16: SKILL_ROADMAP offers add a first capability for budget on with no roadmap and says the last pair cannot be dropped and points to off; SKILL_SHIP INPUT runs show first and asks for the need on no roadmap; budget on over an absent roadmap refuses and creates no file | `sed:s/last remaining pair cannot be dropped/last pair may be dropped/` in .aai/SKILL_ROADMAP.prompt.md | green |

Test status values: pending → red → green.

## Seams

| Seam | Producer | Consumer | Covered by |
|------|----------|----------|------------|
| S1   | close-work-item.mjs writes status done on the capability document | roadmap-edit.mjs advance reads it, ride-select.mjs next reads the flipped pair | TEST-1322 |
| S2   | ride-select.mjs gate no-budget arm (CLI exit code) | orchestration-dispatch.mjs roadmapGate candidate admitted flag | TEST-1323 |
| S3   | the budget block in docs/ai/roadmap.yaml | nothing-left-behind.mjs readRoadmapPairs and ride-select.mjs show (two parsers of one switch) | TEST-1324 |
| S4   | SKILL_SHIP 1a ship-append edit (uncommitted, step 1a) | SKILL_PR 4c staging of docs/ai/roadmap.yaml into the close commit, nothing-left-behind files_left | TEST-1331, TEST-1332 pin text; residual R1 |
| S5   | roadmap-edit.mjs and roadmap-propose.mjs writes | ride-select.mjs validate as the one certifier (spawned, never re-implemented) | TEST-1316, TEST-1310 |
| S6   | prompt corpus bytes | test-aai-prompt-diet.sh TEST-010 and TEST-012 | TEST-1336 |

S1, S2, S3 and S5 are crossed by executing the real consumer script against
the producer's real output.

## Residual risks

- R1 — S4 is prose: no automated test runs an LLM through `/aai-ship` from
  step 1a to SKILL_PR 4c, so whether the appended roadmap line actually
  reaches the close commit is pinned only by the wording of both steps.
  If a ride is abandoned after 1a, `docs/ai/roadmap.yaml` stays dirty with an
  `active` pair in that checkout; `nothing-left-behind` (files_left) surfaces
  it at the next PR attempt.
- R2 — An operator who runs `close-work-item.mjs` by hand, outside SKILL_PR,
  does not advance the roadmap (D4). Mitigated without a budget by D7 (`next`
  skips a pair whose capability document is done); with a budget the pair
  stays open until `/aai-roadmap done` or the next SKILL_PR close.
- R3 — Without a budget the gate admits an on-roadmap item out of order (D3).
  An owner who wanted strict order without the 1:1 pairing has no switch for
  it in this scope; suggested follow-up: fu-roadmap-strict-order-without-budget.
- R4 — Ship append classifies by intake TYPE only (D6): a `type: change`
  intake that is really a fix lands on the roadmap and is marked done at
  close. Visible in the PR diff; harmless to ordering.
- R5 — Edit verbs write LF line endings and do not preserve comments inside a
  moved pair block's interior beyond what the block carries; certification by
  `validate` is the correctness authority, not byte-preservation of
  formatting. Header comments above `budget:`/`pairs:` are preserved.
- R6 — The mirror trees are generated; a hand edit of a mirror is caught by
  `sync-harness-skills.mjs --check` (TEST-1325) but only when that suite runs.

## Registry items closed by this scope

None.

Open items in the same neighbourhood, NOT CLOSED, and why (from
`node .aai/scripts/follow-ups.mjs list`, 2026-10-01):
- `fu-bind-wave2-reason-generic`, `fu-harvest-write-excl-one-sided`,
  `fu-resolvedoc-stale-type-field`, `fu-t760-guard-narrows-to-fu-refs` (P3,
  roadmap-takes-direction) — internals of `roadmap-propose.mjs` bind/harvest
  and their tests; this scope edits only `buildWriteContent`'s absent-file
  seed (D10) and does not touch those code paths.
- `fu-roadmap-pair-pinned-by-index` (P3) — about TEST-565/583 fixtures of the
  shipped roadmap; this scope's tests use their own fixtures.
- `fu-backlog-is-not-queryable` (P2) — ride selection from the backlog, a
  different capability.
- `fu-amend-roadmap-driven-ride-sele-1e2448`, `fu-amend-spec-roadmap-takes-direction`
  (P2) — owner sign-offs owed on earlier amendments; D9 supersedes parts of
  those specs going forward but discharging a sign-off is the owner's.
- `fu-ride-select-absent-intake-mismatch` (P3) — a test arm for the absent
  posture; untouched (the absent posture does not change here).

## Verification

- `env -u AAI_ROLE bash tests/skills/test-aai-ride-select.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-roadmap.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-downstream-autopilot.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-orchestration-dispatch.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-golden-flow.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-close-work-item.sh` — exit 0 (pin unchanged).
- `env -u AAI_ROLE bash tests/skills/test-aai-layer-profiles.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-unattended.sh` — exit 0.
- `node .aai/scripts/ride-select.mjs validate` — exit 0, summary unchanged.
- `node .aai/scripts/sync-harness-skills.mjs --check` — exit 0.
- `node .aai/scripts/check-vendored-script-deps.mjs` — clean.
- One full sweep before close (`AAI_TEST_TIMEOUT=3000`).
- PASS criteria: all TEST-xxx green, all Spec-AC terminal, a RED record for
  each of the 37 rows under
  `docs/ai/tdd/spec-roadmap-serves-downstream-projects/`.

## Evidence contract

- ref_id: roadmap-serves-downstream-projects
- Per TEST-xxx: the `mutation-run.mjs` record at
  `docs/ai/tdd/spec-roadmap-serves-downstream-projects/mutation-<TEST-id>.txt`
  carrying `verdict: RED`, plus the suite command, its exit code and the
  assertion text naming the observable.
- Review scope: branch diff `main...change/roadmap-serves-downstream-projects`
  over the explicit path list returned with this plan.

### Evidence by strategy

Strategy `tdd`: a stored RED artifact per AC-gating test plus the full
verification matrix.
