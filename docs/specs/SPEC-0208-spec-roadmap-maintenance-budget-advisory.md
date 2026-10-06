---
id: spec-roadmap-maintenance-budget-advisory
type: spec
number: 208
status: done
mutation_gate: v1
frozen_sha256: c78e55b321a87a0f1bc5be259767eb43573c06703eca14901710da9e7e4675a6
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0203-roadmap-maintenance-budget-advisory.md
  rfc: null
  pr:
    - 431
  commits:
    - 0c75abc9960a5597725676e6c0d209151dae8398
---

# Spec — an advisory maintenance budget: the roadmap proposes maintenance, never requires it

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0203-roadmap-maintenance-budget-advisory.md
  (AC-001..AC-006, Desired Behavior, Constraints).
- Owner decision: docs/ai/decisions.jsonl `hitl_decision` ts 2026-10-05T12:48:44Z,
  ref_id roadmap-maintenance-budget-advisory — this repository's budget is OFF,
  maintenance is optional, and the owner wants a middle posture that PROPOSES
  maintenance when much is waiting or when it relates to the capability just
  delivered, never requires it.
- Prior specs this scope builds on: SPEC-0202
  (spec-roadmap-serves-downstream-projects — the opt-in budget, `show`,
  `roadmap-edit.mjs`, the shared parser in `lib/roadmap-model.mjs`), SPEC-0168
  (spec-roadmap-driven-ride-selection-with-budget — the gate and the 1:1
  budget), SPEC-0129 (spec-followup-registry — `follow-ups.mjs` fold).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, no YAML library,
  bash suites).

## Implementation strategy
- Strategy: tdd
- Rationale: the scope changes the answer of `ride-select.mjs next`, which
  `/aai-ship` acts on with no argument, extends the one closed-shape roadmap
  parser that three other scripts consume (gate, dispatch, nothing-left-behind,
  merge-policy), and must prove that the existing `on` and `off` postures are
  byte-for-byte unchanged. The previous ride on this surface
  (configurable-merge-policy-lanes, PR #430) needed 12 validation rounds because
  a hand-written config parser silently accepted values; each rejection and
  each trigger here is only evidence when it was observed RED first. STATE's
  `implementation_strategy` belongs to configurable-merge-policy-lanes (a stale
  ref_id) and the intake carries no `Implementation mode (user choice):` note,
  so no recorded human choice is overridden.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the main checkout at /Users/ales/Projects/aai is shared
  by several concurrent sessions (three foreign untracked drafts are present at
  planning time); the scope edits a gate script every ride executes, the
  shared roadmap parser (a merge-policy GUARD_PATH), two canonical prompts and
  a PR-bound multi-slice suite. No touched path is a protected L3 surface, so
  isolation is recommended, not required.
- User decision: undecided
- Base ref: main
- Worktree branch/path: suggested `change/roadmap-maintenance-budget-advisory`
  at `/Users/ales/Projects/aai-roadmap-advisory`
- Inline review scope: not applicable unless inline is chosen; then the explicit
  path list in `## Implementation plan` "Files".

## Ceremony level

Level 2. No touched path is in `protected_paths_l3` of docs/ai/docs-audit.yaml
(state.mjs, state-engine.mjs, state-core.mjs, allocate-doc-number.mjs,
pre-commit-checks.sh/.ps1, WORKFLOW.md, CONSTITUTION.md — read 2026-10-05).
Not lower: a gate script, a shared parser and two prompts change, and the
default `/aai-ship` path changes its answer.
Note for the merge step: `.aai/scripts/lib/roadmap-model.mjs` is listed in
`merge-policy.mjs` GUARD_PATHS, so this PR cannot ride a lane merge; merging
stays with the operator.

## What is established before this scope starts (measured 2026-10-05 at 6e257659)

- `lib/roadmap-model.mjs` `loadRoadmap` accepts exactly two postures: an absent
  `budget:` key (off) and `budget:` with exactly `maintenance_per_capability: 1`
  (on). Any other line inside `budget:` fails the closed shape (exit 2 from
  `validate`).
- Every consumer branches on the truthiness of `rm.budget`: `ride-select.mjs`
  `pickNext`, `gate` (`if (!rm.budget) return noBudgetGate`), `show`;
  `roadmap-edit.mjs` `cmdBudget`, `cmdShipAppend`, `cmdAdvance`.
- `nothing-left-behind.mjs` `readRoadmapPairs` is a second, line-level reader
  that treats ANY top-level `budget:` line as "pairing on".
- `merge-policy.mjs` `readRoadmapCapabilitiesAtBase` and
  `orchestration-dispatch.mjs` `roadmapGate` consume the roadmap through
  `loadRoadmap` and through the `ride-select.mjs gate` CLI respectively.
- `follow-ups.mjs` exports `loadRegistry(absPath)` (read-only fold; an absent
  ledger is empty, an unreadable one is reported in `unreadable`).
- Live backlog that would count as "waiting maintenance" under D3 below: 77
  open P2 follow-ups (0 open P1; 100 open P3 not counted) and 13 open issue or
  techdebt intakes in docs/issues (2 of them untracked drafts of another
  session) — 90 in total. Open follow-ups whose `ref_id` is
  `configurable-merge-policy-lanes` (the capability closed last, EVENTS
  `work_item_closed` 2026-10-05T05:03:41Z): 2 at P2, 1 at P3.
- This repository's `docs/ai/roadmap.yaml` has no `budget:` block (off),
  per the owner decision above. This scope does NOT change that.

## Decisions

- D1 — Shape. The advisory posture is a block form inside the existing closed
  shape, two lines in either order:
  ```
  budget:
    mode: advisory
    maintenance_threshold: 5
  ```
  `maintenance_per_capability: 1` alone stays the `on` form; no `budget:` key
  stays `off`. The block is parsed by the SAME `loadRoadmap` (no second parser).
  INVALID (validate exit 2, never defaulted): `mode` without
  `maintenance_threshold`; `maintenance_threshold` without `mode`; a threshold
  that is not `^[1-9][0-9]*$` (0, negative, decimal, leading zero, quoted,
  empty, trailing text or inline comment); a threshold above
  `Number.MAX_SAFE_INTEGER` (9007199254740991) — a shape-valid digit string
  past that point is read back as a different, rounded value once `Number()`
  runs, so the parser and `roadmap-edit.mjs --threshold` compare the raw
  digit string (via `BigInt`) and refuse before any conversion, never round
  silently (validation round 1 NB1); a `mode` value other than the bare
  word `advisory` (including `on`, `off`, `Advisory`, a quoted `"advisory"`);
  `mode` or `maintenance_threshold` appearing twice; either key combined with
  `maintenance_per_capability`; any other key inside `budget:`. An empty
  `budget:` block keeps today's exact message
  (`budget: block present but maintenance_per_capability is missing`).
- D2 — Model. `loadRoadmap` returns `rm.posture` (`on`, `advisory` or `off`) and
  `rm.advisory` (`{ maintenance_threshold: n }` or null). `rm.budget` KEEPS its
  meaning "the 1:1 budget is on" and stays null in advisory. Consequence by
  construction: every existing `rm.budget` consumer (gate, pickNext, ship-append,
  advance) treats advisory exactly as off; only code that is taught the new
  posture behaves differently. Code that must tell advisory from off reads
  `rm.posture`, never `rm.budget`.
- D3 — Waiting maintenance (`W`). The sum of (a) open follow-ups from
  `follow-ups.mjs` `loadRegistry` over `--ledger` (default
  docs/ai/decisions.jsonl) with severity exactly `P1` or `P2` and fold status
  not `done`/`dropped`; and (b) documents in `<docs>/issues/*.md` whose
  frontmatter (parsed by `lib/docs-model.mjs` `parseFrontmatter`) has `type`
  `issue` or `techdebt` and a `status` not in done, deferred, rejected,
  superseded (a missing status counts as open). P3 follow-ups never count.
  A follow-up with a missing or unknown severity never counts. Owner sign-off
  items (`fu-amend-*`, P2) count like any P2: the intake's definition is kept
  literally; excluding them is offered as HITL-2. Read-only: neither the
  ledger nor any document is written. A malformed non-comment `--ledger` line
  (`loadRegistry`'s own `malformed`/`notes`) and an unreadable `<docs>/issues/*.md`
  entry (permissions, transient I/O, a directory named with a `.md` suffix)
  are each excluded from the count exactly as before (D7 names them instead
  of dropping them with no trace).
- D4 — Most recently closed capability (`C`). Among the roadmap's pair
  capabilities, the one with the latest `ts` of a `work_item_closed` record in
  `--events` (default docs/ai/EVENTS.jsonl) whose `ref` equals the capability
  exactly (a `spec-<slug>` ref does not match); timestamps are compared with
  `Date.parse`, an unparseable `ts` or malformed line is skipped (D7 names the
  exclusion by count and kind); a tie goes to
  the pair listed later in the roadmap. When no pair capability has such a
  record (or the events file is absent or unreadable), `C` is the LAST pair in
  roadmap order whose roadmap `status` is `done`; with no done pair, `C` is
  none and the related trigger cannot fire. The JSON names the source as
  `capability_source: "events"` or `"roadmap_order"`.
- D5 — Triggers (advisory only). `related` fires when at least one open
  P1/P2 follow-up counted in D3 has `ref_id` equal to `C`. `threshold` fires
  when `W >= maintenance_threshold`. When both fire the reason is `related`
  (the more specific one). When neither fires, `next` prints exactly what the
  `off` posture prints for the same roadmap and docs (stdout bytes and exit
  code).
- D6 — Proposal shape. `next --json` prints one line, keys in this order:
  `{"action":"propose_maintenance","reason":"related|threshold","capability":<C or null>,"capability_source":<source or null>,"waiting":{"count":W,"threshold":T},"candidates":[...],"alternative":<the object off would print>,"degraded":[...]}`.
  `alternative` is the exact object the `off` posture's `next --json` prints for
  the same inputs (a `next`/`path` object, a `file-intake` object, or the
  `wave_1: complete` object). Candidates: for `related`, only the related
  follow-ups; for `threshold`, all counted items. Order: P1 follow-ups, then P2
  follow-ups, each in the fold's own order (oldest first, id tiebreak), then
  intakes by id in codepoint order; at most 5. A follow-up candidate is
  `{"kind":"follow_up","id","severity","ref","finding"}`; an intake candidate is
  `{"kind":"intake","id","type","status","path"}` — `id` is NEVER absent: an
  intake doc with no frontmatter `id` derives it the same way the docs model
  does elsewhere (`extractDocIds`'s numbered-filename primary, else the
  filename stem; validation round 1 NB2). `degraded` (D7, appended 2026-10-06
  as a disclosed contract amendment — PR #431 bot findings) is a string array,
  one entry per excluded reason, empty when the count behind this proposal
  was clean; it is the LAST key, after `alternative`, so a consumer reading
  only the keys this spec originally named still sees its exact prefix.
  Without `--json` it prints
  three lines: `maintenance proposed (<reason>): <id>[, <id>...]`,
  `waiting: <W> of threshold <T>; most recently closed capability: <C or none>`,
  `or continue with: <the off posture's one-line answer>`. Exit 0 always. It
  never prints `"action":"bind"` and never refuses.
- D7 — Degrade. In advisory, an unreadable `--ledger` (not ENOENT) makes `next`
  print the off answer unchanged on stdout, exit 0, and one stderr line
  starting `ride-select: advisory not evaluated — `. An absent ledger is an
  empty registry (intakes still count). A SEPARATE, narrower class of
  degradation never aborts the advisory count the way an unreadable `--ledger`
  does: a malformed non-comment `decisions.jsonl` line, an unreadable
  `<docs>/issues/*.md` entry, or a malformed/invalid `work_item_closed` record
  in `--events`. Each is excluded from `W`/`C` exactly as before this
  sub-clause (counts, triggers and exit codes are unchanged) but is now named —
  one `ride-select: degraded: <reason>` stderr line per reason (ledger/intake
  reasons name the path and OS error code; events reasons name the file, a
  count and a kind), printed whenever advisory evaluation runs, whether or not
  a trigger ends up firing — and, only when `next --json` goes on to print a
  `propose_maintenance` proposal, the SAME reasons populate that proposal's
  `degraded` array (D6). `waiting --json` (D8) carries the same reasons in its
  own `degraded` key, always present (empty array when clean). In `on` and
  `off`, `next` reads neither the ledger nor the events file (outputs
  byte-identical whatever those flags point at, with no `degraded` key).
- D8 — `ride-select.mjs waiting [--docs <dir>] [--ledger <p>] [--json]` — a
  read-only query that needs no roadmap and works in every posture. JSON:
  `{"count":W,"follow_ups":{"P1":a,"P2":b},"intakes":{"issue":c,"techdebt":d},"recommended_threshold":max(5, W + 5),"degraded":[...]}`
  (`degraded` per D7, always present, empty when clean);
  text: one line naming the same numbers (text form carries no degraded
  line beyond the stderr output D7 already specifies). Unreadable ledger:
  exit 2 with the
  reason (it is an explicit query, not a gate). The recommended threshold is
  "five more than are waiting today", so advisory does not fire on the very
  first call over an existing backlog (intake constraint: the default is
  measured, not guessed; for this repository it would be 95).
- D9 — `gate` in advisory is the `off` gate, byte for byte (D2 makes this
  structural). `show` in advisory prints `maintenance budget: advisory
  (threshold T)` as its first line; `show --json` keeps `budget: false` and adds
  `"advisory":{"maintenance_threshold":T}` after it. `show` in on/off is
  unchanged.
- D10 — `roadmap-edit.mjs budget <on|advisory|off> [--threshold <n>]`.
  `advisory` requires `--threshold` (positive integer, `^[1-9][0-9]*$`, else
  exit 2); `--threshold` with anything else is exit 2. Transitions: off, on or
  advisory with another threshold to `advisory N` replace or insert the budget
  block (directly before `pairs:`); advisory to `on` replaces it with the on
  form; advisory to `off` removes it. Refusals, exit 1 with the file
  byte-identical: `on` when on, `off` when off (today's messages), `advisory N`
  when already advisory with threshold N. Every write is certified by
  `ride-select.mjs validate` and restored on refusal (existing discipline).
  Success line for advisory: `roadmap: maintenance budget advisory (threshold
  N) — next proposes maintenance, the gate never refuses for it`.
- D11 — `nothing-left-behind.mjs` `readRoadmapPairs` returns no pairs when
  `loadRoadmap` parses the roadmap as valid with posture `advisory` or `off`;
  when the roadmap is invalid it keeps today's line-scan result. This removes
  the one place that would otherwise read an advisory `budget:` line as "1:1
  pairing on".
- D12 — Prompts. SKILL_ROADMAP action 7 becomes a three-option budget menu
  (on, advisory, off; recommended: leave as it is) and, for advisory, runs
  `ride-select.mjs waiting --json` first and offers its `recommended_threshold`
  as the default. SKILL_SHIP INPUT relays a `propose_maintenance` answer as ONE
  menu with two options and asks nothing else: (1, recommended) ride the first
  candidate — an `intake` candidate by its `path`, a `follow_up` candidate as
  the need with topic = its `finding`; (2) continue with `alternative`, handled
  exactly like a non-proposal answer.
- D13 — This repository's live `docs/ai/roadmap.yaml` keeps no `budget:` block.
  Switching it to advisory is an owner decision, offered as HITL-1, not done
  by this ride.

## Constitution deviations

None.

Article 5 (additive first) was checked: every currently valid roadmap keeps its
exact behavior; the advisory block is new syntax that was invalid before;
`ride-select.mjs` gains a `waiting` verb and a `--ledger` flag; `roadmap-edit.mjs
budget` gains one value and one flag. Article 4 (degrade and report) is D7/D8.
Article 2 (simplicity): one parser extended, no new script, no new `.aai` file.

## Acceptance Criteria Mapping

- Spec-AC-01 (maps AC-001): `ride-select.mjs validate` SHALL exit 0 and print
  `roadmap OK: <n> pair(s), <m> wave-2 item(s)` for an advisory roadmap with
  the two budget lines in either order and a threshold of 1 and of 12.
  Verification: TEST-1600.
- Spec-AC-02 (maps AC-001): `validate` SHALL exit 2, naming the defect on
  stderr and leaving the file's sha256 unchanged, for every invalid shape of
  D1 (threshold values, modes, duplicates, mixed forms, unknown key, inline
  comment), and an empty `budget:` block SHALL still print today's exact
  message. Verification: TEST-1601..1605.
- Spec-AC-03 (maps AC-002): over one fixture matrix (off-roadmap issue ref,
  off-roadmap change ref, out-of-order roadmap ref, done ref, ref without a
  document, ref in a done pair, an out-of-order ref with `--override`), `gate`
  on the advisory roadmap SHALL produce stdout, stderr, exit code and EVENTS
  bytes identical to `gate` on the same roadmap without a budget block.
  Verification: TEST-1606.
- Spec-AC-04 (maps AC-003): in advisory, WHEN W equals the threshold `next
  --json` SHALL print `propose_maintenance` with reason `threshold`; WHEN W is
  one below it SHALL print the off answer byte for byte; open P3, closed or
  dropped P1/P2 follow-ups, terminal (done, deferred, rejected, superseded)
  issue/techdebt intakes and change-type intakes SHALL never count; draft and
  implementing issue/techdebt intakes SHALL count. Verification:
  TEST-1607..1612.
- Spec-AC-05 (maps AC-003): in advisory, WHEN an open P1/P2 follow-up's ref_id
  equals C `next --json` SHALL print reason `related` with only related
  candidates and `capability` C; WHEN no follow-up references C, or only P3
  ones do, or the only one is closed, or it references an older closed
  capability, it SHALL print the off answer (threshold not reached); WHEN both
  triggers fire the reason SHALL be `related`. Verification: TEST-1613..1615.
- Spec-AC-06 (maps AC-003): C SHALL be decided by D4: latest `work_item_closed`
  ts wins, a tie goes to the later pair, a `spec-` prefixed ref never matches,
  without matching events the last done pair in roadmap order is used and
  named `roadmap_order`, and with no done pair and no events related never
  fires. Verification: TEST-1616..1620.
- Spec-AC-07 (maps AC-003): the proposal SHALL have D6's exact key order, its
  `alternative` SHALL equal the off posture's `next --json` object for each of
  the three alternative kinds, `"action":"bind"` SHALL appear nowhere in
  advisory output (including a started capability-only pair), candidates SHALL
  be ordered P1, P2, intakes and capped at 5, the text form SHALL be D6's three
  lines, an unreadable ledger SHALL degrade per D7, and on/off `next` SHALL be
  unaffected by `--ledger`/`--events`. Verification: TEST-1621..1627.
- Spec-AC-08 (maps the intake constraint "the default is measured"):
  `ride-select.mjs waiting --json` SHALL print D8's counts and
  `recommended_threshold` = max(5, W+5) with no roadmap present, SHALL leave the
  ledger and docs tree sha256 unchanged, SHALL exit 2 on an unreadable ledger
  and exit 0 counting intakes only on an absent one. Verification:
  TEST-1628, TEST-1629.
- Spec-AC-09 (maps AC-004, show): `show` SHALL print `maintenance budget:
  advisory (threshold 7)` for an advisory fixture with threshold 7, `show
  --json` SHALL carry `"budget":false` and `"advisory":{"maintenance_threshold":7}`,
  and the pre-existing TEST-1309 SHALL pass unmodified. Verification: TEST-1630.
- Spec-AC-10 (maps AC-004): `roadmap-edit.mjs budget advisory --threshold <n>`
  SHALL make each D10 transition with a file `validate` accepts, and every D10
  refusal SHALL exit 1 or 2 with the roadmap sha256 and its directory listing
  unchanged. Verification: TEST-1631..1635.
- Spec-AC-11 (seam): in advisory, `ship-append` SHALL append a change-type
  capability exactly as off does and `advance` SHALL flip a pair whose
  capability document is done although its bound maintenance document is
  draft, exactly as off does. Verification: TEST-1636.
- Spec-AC-12 (seam S3): `nothing-left-behind.mjs --json` SHALL report no paired
  maintenance half for an advisory fixture whose pair binds a draft
  maintenance document, one for the same fixture with the on block, and one
  for the invalid-roadmap control exactly as before. Verification: TEST-1637.
- Spec-AC-13 (seams S2, S4): `orchestration-dispatch.mjs` `buildSnapshot`
  candidate `gate.admitted` SHALL equal the CLI `gate` exit-0 verdict on the
  advisory fixture and equal the off fixture's; `loadRoadmap` SHALL return the
  same `pairs` for the advisory and the off variant of one roadmap (the input
  merge-policy consumes). Verification: TEST-1638.
- Spec-AC-14 (maps AC-004, skill): SKILL_ROADMAP action 7 SHALL name the three
  postures, the command `roadmap-edit.mjs budget advisory --threshold <n>`,
  `ride-select.mjs waiting --json` and `recommended_threshold`; the existing
  SKILL_ROADMAP tests SHALL pass unmodified. Verification: TEST-1639.
- Spec-AC-15 (maps AC-005): SKILL_SHIP INPUT SHALL name `propose_maintenance`,
  `candidates`, `alternative`, one menu whose first option is recommended, and
  that no other question is asked; the existing SKILL_SHIP tests SHALL pass
  unmodified. Verification: TEST-1640.
- Spec-AC-16 (maps AC-005, governance): the prompt-diet ledger SHALL carry one
  new entry for this ref equal to the measured growth of the two prompts, the
  TEST-012 checkpoint SHALL move by the same amount, and
  `test-aai-prompt-diet.sh` SHALL exit 0; no new `.aai/**` file is added, so
  PROFILES needs no entry. Verification: TEST-1641.
- Spec-AC-17 (maps AC-006): docs/USER_GUIDE.md "Roadmap: when and how" SHALL
  list the advisory posture in its posture table and carry an `Example 4: an
  advisory budget` with `/aai-roadmap budget` and `/aai-ship`; the
  `/aai-roadmap` reference note SHALL list `budget (on, advisory or off)`;
  docs/product/roadmap.md SHALL describe the three postures with a worked
  example each, naming `mode: advisory`, `maintenance_threshold`,
  `propose_maintenance` and `ride-select.mjs waiting`. Verification: TEST-1642,
  TEST-1643.
- Spec-AC-18 (suite selection): tests/skills/suite-map.yaml SHALL list
  `.aai/scripts/follow-ups.mjs` under the `aai-ride-select` suite, so a change
  to the fold that advisory now reads re-runs these tests. Verification:
  TEST-1644.
- Spec-AC-19 (D7 broadened, PR #431 bot findings — disclosed 2026-10-06 as a
  contract amendment to this frozen spec; widened 2026-10-06 in validation
  round 3 remediation to name three gaps the round found, each already true
  of the shipped code but previously untested/unspecified): a malformed
  non-comment `decisions.jsonl` line, an unreadable `<docs>/issues/*.md`
  entry (including the whole `issues` directory itself being unreadable),
  and a malformed/invalid `work_item_closed` record in `--events` (including
  `--events` itself being unreadable) SHALL each be named — one
  `ride-select: degraded: <reason>` stderr line per reason, whether or not a
  trigger fires, with any newline/CR/line-or-paragraph-separator/other
  control character in the reason escaped so it never splits one reason
  across more than one physical stderr line or forges a second
  `ride-select: degraded:` line — and SHALL populate a trailing `degraded`
  json array (carrying the RAW, unescaped reason) on `waiting --json`
  (always present) and on a firing `next --json` proposal (D6's last key);
  counts, triggers and exit codes SHALL be unchanged, and a clean input
  SHALL keep `degraded: []` with no stderr. Verification: TEST-1646..1653.

## Acceptance Criteria Status

| Spec-AC    | Description | Status  | Evidence | Review-By | Notes |
|------------|-------------|---------|----------|-----------|-------|
| Spec-AC-01 | WHEN a roadmap carries mode advisory and a positive integer maintenance_threshold in either line order validate SHALL exit 0 with the roadmap OK summary | done | TEST-1600 PASS (docs/ai/tdd/green-20261005T145011Z.log); RED docs/ai/tdd/red-20261005T144918Z.log; mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-1600.txt | — | D1 D2 |
| Spec-AC-02 | WHEN the budget block has any D1 invalid shape validate SHALL exit 2 naming it with the file unchanged; an empty block SHALL keep the old message | done | TEST-1601..1605 PASS (docs/ai/tdd/green-20261005T145011Z.log); RED docs/ai/tdd/red-20261005T144918Z.log; mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-160{1,2,3,4,5}.txt | — | D1 |
| Spec-AC-03 | gate on an advisory roadmap SHALL equal gate on the same roadmap without budget in stdout stderr exit code and EVENTS bytes over the fixture matrix | done | TEST-1606 PASS (docs/ai/tdd/green-20261005T152430Z.log); mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-1606.txt | — | D2 D9 |
| Spec-AC-04 | WHEN waiting maintenance reaches the threshold next SHALL propose with reason threshold and one below SHALL equal off; P3 closed terminal and change items SHALL never count | done | TEST-1607..1612 PASS (docs/ai/tdd/green-20261005T152430Z.log); mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-16{07,08,09,10,11,12}.txt | — | D3 D5 |
| Spec-AC-05 | WHEN an open P1 or P2 follow-up references the most recently closed capability next SHALL propose with reason related; each negation SHALL equal off; related SHALL win over threshold | done | TEST-1613..1615 PASS (docs/ai/tdd/green-20261005T152430Z.log); mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-16{13,14,15}.txt | — | D4 D5 |
| Spec-AC-06 | The most recently closed capability SHALL follow D4 events first with tie to the later pair and roadmap order fallback | done | TEST-1616..1620 PASS (docs/ai/tdd/green-20261005T152430Z.log); mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-16{16,17,18,19,20}.txt | — | D4 |
| Spec-AC-07 | The proposal SHALL keep the D6 shape and alternative equal to off, never bind, order and cap candidates, degrade per D7, and leave on and off next unaffected; an intake candidate's `id` is NEVER absent (validation round 1 NB2) | done | TEST-1621..1627, TEST-1645 PASS (docs/ai/tdd/green-20261005T163341Z.log); RED docs/ai/tdd/red-20261005T163332Z.log; mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-16{21,22,23,24,25,26,27,45}.txt | — | D6 D7 |
| Spec-AC-08 | ride-select waiting SHALL report counts and recommended_threshold max of 5 and W plus 5 read-only in every posture and exit 2 on an unreadable ledger | done | TEST-1628, TEST-1629 PASS (docs/ai/tdd/green-20261005T163341Z.log); RED docs/ai/tdd/red-20261005T163332Z.log; mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-16{28,29}.txt | — | D8 |
| Spec-AC-09 | show SHALL print the advisory posture line and json advisory key while on and off show stay unchanged | done | TEST-1630 PASS (docs/ai/tdd/green-20261005T163341Z.log); RED docs/ai/tdd/red-20261005T163332Z.log; mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-1630.txt | — | D9 |
| Spec-AC-10 | roadmap-edit budget advisory with threshold SHALL make each D10 transition and every refusal SHALL leave the roadmap byte-identical | done | TEST-1631..1635 PASS (docs/ai/tdd/green-20261005T175857Z-ac10-13.log); RED docs/ai/tdd/red-20261005T175851Z-ac10-13.log; mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-16{31,32,33,34,35}.txt | — | D10 |
| Spec-AC-11 | In advisory ship-append and advance SHALL behave exactly as in off | done | TEST-1636 PASS (docs/ai/tdd/green-20261005T175857Z-ac10-13.log); RED docs/ai/tdd/red-20261005T175851Z-ac10-13.log (mutation-only, structural by D2 construction); mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-1636.txt | — | D2 seam |
| Spec-AC-12 | nothing-left-behind SHALL report no paired maintenance half under advisory, one under on, and keep the invalid-roadmap result | done | TEST-1637 PASS (docs/ai/tdd/green-20261005T175857Z-ac10-13.log); RED docs/ai/tdd/red-20261005T175851Z-ac10-13.log; mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-1637.txt | — | D11 seam S3 |
| Spec-AC-13 | The dispatch candidate gate verdict SHALL equal the CLI gate and the off verdict under advisory, and loadRoadmap pairs SHALL equal off | done | TEST-1638 PASS (docs/ai/tdd/green-20261005T175857Z-ac10-13.log); RED docs/ai/tdd/red-20261005T175851Z-ac10-13.log (mutation-only, structural by D2 construction); mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-1638.txt | — | seams S2 S4 |
| Spec-AC-14 | SKILL_ROADMAP action 7 SHALL offer on advisory and off with the advisory command and the measured recommended threshold | done | TEST-1639 PASS (docs/ai/tdd/green-20261005T200506Z-ac14-18.log); RED docs/ai/tdd/red-20261005T200506Z-ac14-18.log; mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-1639.txt | — | D12 |
| Spec-AC-15 | SKILL_SHIP SHALL relay propose_maintenance as one two-option menu with the first recommended and ask nothing else | done | TEST-1640 PASS (docs/ai/tdd/green-20261005T200506Z-ac14-18.log); RED docs/ai/tdd/red-20261005T200506Z-ac14-18.log; mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-1640.txt | — | D12 |
| Spec-AC-16 | The diet ledger SHALL credit the measured prompt growth and prompt-diet SHALL pass | done | TEST-1641 PASS (tests/skills/test-aai-prompt-diet.sh exit 0); mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-1641.txt | — | companion obligation |
| Spec-AC-17 | USER_GUIDE and the roadmap product doc SHALL describe three postures with a worked example each | done | TEST-1642, TEST-1643 PASS (docs/ai/tdd/green-20261005T200506Z-ac14-18.log); RED docs/ai/tdd/red-20261005T200506Z-ac14-18.log; mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-1642.txt, mutation-TEST-1643.txt | — | AC-006 |
| Spec-AC-18 | suite-map SHALL list follow-ups.mjs under the aai-ride-select suite | done | TEST-1644 PASS (docs/ai/tdd/green-20261005T200506Z-ac14-18.log); RED docs/ai/tdd/red-20261005T200506Z-ac14-18.log; mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-1644.txt | — | suite selection |
| Spec-AC-19 | A malformed ledger line, an unreadable intake entry/directory and a malformed/invalid/unreadable EVENTS close source SHALL each be named (stderr, control-char-escaped, one line per reason, whether or not a trigger fires + a trailing `degraded` json array carrying the raw reason), never dropped with no trace, with counts/triggers/exit codes unchanged and a clean input keeping `degraded: []` | done | TEST-1646..1653 PASS (env -u AAI_ROLE bash tests/skills/test-aai-ride-select.sh); mutation docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-16{46,47,48,49,50,51,52,53}.txt | — | D7 (broadened, PR #431 bot findings; widened validation round 3 remediation) |

## Implementation plan

Slices (one TDD run each, about three ACs per run):
- A — parser and gate: Spec-AC-01, 02, 03, 09 (TEST-1600..1606, TEST-1630).
- B — advisory `next`: Spec-AC-04, 05, 06 (TEST-1607..1620).
- C — proposal shape, `waiting`, degrade: Spec-AC-07, 08 (TEST-1621..1629, TEST-1645).
- D — writer and seams: Spec-AC-10, 11, 12, 13, 18 (TEST-1631..1638, TEST-1644).
- E — prompts, docs, governance: Spec-AC-14, 15, 16, 17 (TEST-1639..1643).
- F — degrade disclosure (PR #431 bot findings, 2026-10-06; widened in
  validation round 3 remediation): Spec-AC-19 (TEST-1646..1653).

Files:
- .aai/scripts/lib/roadmap-model.mjs — D1, D2.
- .aai/scripts/ride-select.mjs — D3..D9 (`waiting` verb, `--ledger` flag,
  advisory branch of `next`, `show` line); imports `loadRegistry` from
  `./follow-ups.mjs` and `parseFrontmatter` (already imported).
- .aai/scripts/roadmap-edit.mjs — D10.
- .aai/scripts/nothing-left-behind.mjs — D11.
- .aai/SKILL_ROADMAP.prompt.md, .aai/SKILL_SHIP.prompt.md — D12.
- tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh
  (TEST-012 checkpoint) — companion obligation.
- tests/skills/test-aai-ride-select.sh, tests/skills/test-aai-roadmap.sh — new
  tests.
- tests/skills/suite-map.yaml — Spec-AC-18.
- docs/product/roadmap.md, docs/USER_GUIDE.md — Spec-AC-17.
- ride-select.mjs and roadmap-edit.mjs header comments document the new verb,
  flag and posture.

Intended anchor lines (the Mutation cells below name them; the implementer
reconciles an anchor to the code as written and discloses each reconciliation
as a restamp, never as an amendment):
- roadmap-model.mjs: `const THRESHOLD_RE = /^[1-9]\d*$/;`; per-line
  `if (bmode !== null) return { error: 'budget.mode appears twice' };` and
  `if (bthr !== null) return { error: 'budget.maintenance_threshold appears twice' };`;
  inside the `budgetDeclared` block:
  `if (rm.budget && (bmode !== null ... ))` (combined-form refusal),
  `if (!rm.budget && bmode === null && bthr === null) return` (today's empty-block
  message), `if (!rm.budget && bmode !== 'advisory')` (unknown mode),
  `if (!rm.budget && !THRESHOLD_RE.test(bthr ?? ''))` (threshold),
  `if (!rm.budget) rm.advisory = { maintenance_threshold: Number(bthr) };`;
  then `rm.posture = rm.budget ? 'on' : (rm.advisory ? 'advisory' : 'off');`.
- ride-select.mjs: `const WAITING_SEVERITIES = new Set(['P1', 'P2']);`,
  `const OPEN_INTAKE_TYPES = new Set(['issue', 'techdebt']);`,
  closed-intake statuses via the imported `TERMINAL_DOC_STATUS` (lib/docs-model.mjs)
  rather than a local `CLOSED_INTAKE_STATUSES` literal — restamped during
  TEST-1611 (measurement-class spec_amendment, ts 2026-10-05): a local
  `['done', 'deferred', 'rejected', 'superseded']` literal duplicated the one
  test-aai-golden-flow.sh TEST-008 pins to lib/docs-model.mjs alone (no forked
  canon);
  `const SEVERITY_RANK = { P1: 0, P2: 1 };`, `const CANDIDATE_CAP = 5;`;
  `waitingMaintenance(docsDir, ledgerPath)` with
  `reg.items.filter((i) => !i.closed && WAITING_SEVERITIES.has(i.severity))`;
  `lastClosedCapability(rm, eventsPath)` with `t > best.t`, `i > best.i`,
  `if (best) return { capability: best.cap, source: 'events' };`,
  `rm.pairs.filter((p) => p.status === 'done')` and
  `done[done.length - 1].capability`; `adviseMaintenance` with
  `const related = closed ? w.followUps.filter((f) => f.ref_id === closed.capability) : [];`,
  `const thresholdFired = w.count >= rm.advisory.maintenance_threshold;`,
  `const reason = related.length ? 'related' : (thresholdFired ? 'threshold' : null);`;
  in `main` `if (rm.posture === 'advisory') {`, `if (w.unreadable) {`, the
  proposal object's `alternative: offJson`; `waiting` with
  `recommended_threshold: Math.max(5, w.count + 5)` and
  `if (w.unreadable) usage(`; `show` with `maintenance budget: advisory`.
  `offJson`/the off text line come from ONE helper shared with the existing
  off printing, so the alternative cannot drift from the off answer.
- roadmap-edit.mjs: `--threshold` parsing with `/^[1-9]\d*$/`;
  `if (a.verb === 'budget' && a.state === 'advisory' && a.threshold === null)`;
  `cmdBudget` with `if (rm.posture === 'on') refuse(`,
  `if (rm.posture === 'off') refuse(`,
  `if (rm.posture === 'advisory' && rm.advisory.maintenance_threshold === a.threshold) refuse(`;
  `setBudgetBlock(text, body)` starting
  `const base = hasBudget(text) ? removeBudget(text) : text;`.
- nothing-left-behind.mjs: `readRoadmapPairs` calls `loadRoadmap` on the same
  path first: `if (!loaded.error && loaded.roadmap.posture !== 'on') return [];`.

Edge cases fixed by this plan: CRLF and comment lines inside `budget:` behave
as today (filtered before matching); a `maintenance:` line in an advisory pair
is inert as in off; `bind` remains available but inert in advisory; the
threshold has no upper bound (any positive integer).

Fixture discipline: every advisory test passes explicit `--ledger`, `--events`
and `--docs` fixture paths under its own scratch directory; no test reads the
live ledger, EVENTS or roadmap. Fixture follow-ups are written with
`follow-ups.mjs add`/`close --ledger <fixture>` (the sanctioned writer), never
hand-written JSON.

## Test Plan

Rows TEST-1600..1630 land in `tests/skills/test-aai-ride-select.sh`; rows
TEST-1631..1644 land in `tests/skills/test-aai-roadmap.sh` unless their file
path says otherwise. The range TEST-1600..1644 was chosen above the highest id
in use (TEST-1579 at 6e257659), leaving 1580..1599 for concurrent plannings.
Every row is observed RED under its Mutation (or on the pre-change tree) before
it counts green; records go to
`docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/`. Every off-equality
assertion compares against a run of the SAME fixture with the budget block
removed, captured in the same test, never against a stored string.

| Test ID  | Spec-AC    | Type        | File path (expected)                  | Description | Mutation | Status  |
|----------|------------|-------------|---------------------------------------|-------------|----------|---------|
| TEST-1600 | Spec-AC-01 | integration | tests/skills/test-aai-ride-select.sh | advisory block with mode first, with threshold first, threshold 1 and threshold 12: validate exit 0 with the roadmap OK summary each | `sed:s/if \(!rm\.budget && bmode !== 'advisory'\)/if (!rm.budget)/` in .aai/scripts/lib/roadmap-model.mjs | green |
| TEST-1601 | Spec-AC-02 | integration | tests/skills/test-aai-ride-select.sh | threshold 0, -3, 1.5, 05, quoted "5", quoted '5', empty value, 5 with an inline comment, threshold line missing, and (validation round 1 NB1) a shape-valid threshold above Number.MAX_SAFE_INTEGER (9007199254740993): exit 2, stderr names maintenance_threshold and the exact over-cap digit string (never a rounded one), sha256 unchanged; the cap value itself (9007199254740991) still validates | `sed:s/BigInt\(bthr\) > BigInt\(Number\.MAX_SAFE_INTEGER\)/false/` in .aai/scripts/lib/roadmap-model.mjs | green |
| TEST-1602 | Spec-AC-02 | integration | tests/skills/test-aai-ride-select.sh | mode on, mode off, mode Advisory, mode quoted "advisory", threshold without any mode line: exit 2, stderr names budget.mode, sha256 unchanged | `sed:s/bmode !== 'advisory'\)/false)/` in .aai/scripts/lib/roadmap-model.mjs | green |
| TEST-1603 | Spec-AC-02 | integration | tests/skills/test-aai-ride-select.sh | mode twice and maintenance_threshold twice (same and different values): exit 2 naming appears twice | `sed:s/if \(bmode !== null\) return \{ error: 'budget\.mode appears twice' \};//` in .aai/scripts/lib/roadmap-model.mjs | green |
| TEST-1604 | Spec-AC-02 | integration | tests/skills/test-aai-ride-select.sh | maintenance_per_capability 1 together with mode advisory and threshold, and together with threshold alone: exit 2 naming cannot be combined; an unknown key threshold 5 inside budget exits 2 with the closed-shape message | `sed:s/if \(rm\.budget && \(bmode/if (false && (bmode/` in .aai/scripts/lib/roadmap-model.mjs | green |
| TEST-1605 | Spec-AC-02 | integration | tests/skills/test-aai-ride-select.sh | an empty budget block exits 2 with exactly budget: block present but maintenance_per_capability is missing; TEST-1301 and TEST-1302 selectors exit 0 unmodified | `sed:s/if \(!rm\.budget && bmode === null && bthr === null\) return/if (false) return/` in .aai/scripts/lib/roadmap-model.mjs | green |
| TEST-1606 | Spec-AC-03 | integration | tests/skills/test-aai-ride-select.sh | gate matrix of seven refs (off-roadmap issue, off-roadmap change, out-of-order roadmap ref, done ref, ref without document, ref in a done pair, out-of-order ref with --override) on one roadmap path rewritten advisory then off: stdout, stderr, exit code and fixture EVENTS bytes identical per ref; positive control that the on variant refuses the out-of-order ref | `sed:s/if \(!rm\.budget\) rm\.advisory = \{ maintenance_threshold: Number\(bthr\) \};/if (!rm.budget) { rm.advisory = { maintenance_threshold: Number(bthr) }; rm.budget = { maintenance_per_capability: 1 }; }/` in .aai/scripts/lib/roadmap-model.mjs | green |
| TEST-1607 | Spec-AC-04 | integration | tests/skills/test-aai-ride-select.sh | two open P2 follow-ups, one draft issue, one draft techdebt intake, threshold 4: next json action propose_maintenance, reason threshold, waiting count 4 threshold 4 | `sed:s/w\.count >= rm\.advisory\.maintenance_threshold/w.count > rm.advisory.maintenance_threshold/` in .aai/scripts/ride-select.mjs | green |
| TEST-1608 | Spec-AC-04 | integration | tests/skills/test-aai-ride-select.sh | same items, threshold 5: next json and next text stdout and exit equal the off run of the same fixture; no stderr | `sed:s/const thresholdFired = w\.count >= rm\.advisory\.maintenance_threshold;/const thresholdFired = true;/` in .aai/scripts/ride-select.mjs | green |
| TEST-1609 | Spec-AC-04 | integration | tests/skills/test-aai-ride-select.sh | four countable items plus ten open P3 follow-ups, threshold 5: no proposal (equals off) and waiting json P1 0 P2 2 | `sed:s/WAITING_SEVERITIES = new Set\(\['P1', 'P2'\]\)/WAITING_SEVERITIES = new Set(['P1', 'P2', 'P3'])/` in .aai/scripts/ride-select.mjs | green |
| TEST-1610 | Spec-AC-04 | integration | tests/skills/test-aai-ride-select.sh | four countable items plus three P2 follow-ups closed done and one P1 closed dropped via follow-ups.mjs close, threshold 5: no proposal; positive control that reopening one makes it fire | `sed:s/!i\.closed && WAITING/WAITING/` in .aai/scripts/ride-select.mjs | green |
| TEST-1611 | Spec-AC-04 | integration | tests/skills/test-aai-ride-select.sh | four countable items plus issue and techdebt docs with status done, deferred, rejected and superseded, threshold 5: no proposal; an implementing issue doc added makes it fire | `sed:s/status !== null && TERMINAL_DOC_STATUS\.has\(status\)/false/` in .aai/scripts/ride-select.mjs (restamp, measurement-class, spec_amendment ts 2026-10-05: reuses lib/docs-model.mjs TERMINAL_DOC_STATUS instead of a local CLOSED_INTAKE_STATUSES literal, per test-aai-golden-flow.sh TEST-008's forked-canon guard) | green |
| TEST-1612 | Spec-AC-04 | integration | tests/skills/test-aai-ride-select.sh | four countable items plus three draft change-type docs, threshold 5: no proposal and waiting count 4 | `sed:s/OPEN_INTAKE_TYPES = new Set\(\['issue', 'techdebt'\]\)/OPEN_INTAKE_TYPES = new Set(['issue', 'techdebt', 'change'])/` in .aai/scripts/ride-select.mjs | green |
| TEST-1613 | Spec-AC-05 | integration | tests/skills/test-aai-ride-select.sh | pairs cap-a done and cap-b planned, EVENTS closes cap-a, one open P2 follow-up ref cap-a and one unrelated P2, threshold 50: reason related, capability cap-a, capability_source events, candidates exactly the cap-a follow-up | `sed:s/f\.ref_id === closed\.capability/false/` in .aai/scripts/ride-select.mjs | green |
| TEST-1614 | Spec-AC-05 | integration | tests/skills/test-aai-ride-select.sh | negations at threshold 50, each equal to the off run: no follow-up for cap-a; only a P3 for cap-a; the cap-a P2 closed; a P2 whose ref is an older closed capability cap-z | `sed:s/const related = closed \? w\.followUps\.filter\(\(f\) => f\.ref_id === closed\.capability\) : \[\];/const related = w.followUps.filter((f) => f.ref_id !== null);/` in .aai/scripts/ride-select.mjs | green |
| TEST-1615 | Spec-AC-05 | integration | tests/skills/test-aai-ride-select.sh | related follow-up present and W at the threshold: reason related and candidates only related | `sed:s/const reason = related\.length \? 'related' : \(thresholdFired \? 'threshold' : null\);/const reason = thresholdFired ? 'threshold' : (related.length ? 'related' : null);/` in .aai/scripts/ride-select.mjs | green |
| TEST-1616 | Spec-AC-06 | integration | tests/skills/test-aai-ride-select.sh | cap-a and cap-b done, EVENTS closes cap-b at 10:00 and cap-a at 11:00, follow-ups for cap-b only: no related proposal; for cap-a: related with capability cap-a | `sed:s/t > best\.t/t < best.t/` in .aai/scripts/ride-select.mjs | green |
| TEST-1617 | Spec-AC-06 | integration | tests/skills/test-aai-ride-select.sh | cap-a and cap-b closed at the same ts: capability is cap-b (listed later) | `sed:s/i > best\.i/i < best.i/` in .aai/scripts/ride-select.mjs | green |
| TEST-1618 | Spec-AC-06 | integration | tests/skills/test-aai-ride-select.sh | absent EVENTS path and an EVENTS file whose only close refs are spec-cap-a and an off-roadmap ref, cap-a and cap-b done: capability cap-b, capability_source roadmap_order | `sed:s/done\[done\.length - 1\]\.capability/done[0].capability/` in .aai/scripts/ride-select.mjs | green |
| TEST-1619 | Spec-AC-06 | integration | tests/skills/test-aai-ride-select.sh | EVENTS closes cap-a (listed first) while cap-b is also done without an event: capability cap-a, capability_source events | `sed:s/if \(best\) return \{ capability: best\.cap, source: 'events' \};//` in .aai/scripts/ride-select.mjs | green |
| TEST-1620 | Spec-AC-06 | integration | tests/skills/test-aai-ride-select.sh | no done pair, no EVENTS, an open P2 follow-up whose ref is the planned last capability, threshold 50: equals off | `sed:s/rm\.pairs\.filter\(\(p\) => p\.status === 'done'\)/rm.pairs.filter((p) => p.status !== 'x')/` in .aai/scripts/ride-select.mjs | green |
| TEST-1621 | Spec-AC-07 | integration | tests/skills/test-aai-ride-select.sh | proposal keys in D6 order; alternative deep-equals the off next json for a next-with-path roadmap, a file-intake roadmap and an all-done roadmap (wave_1 complete) | `sed:s/alternative: offJson/alternative: null/` in .aai/scripts/ride-select.mjs | green |
| TEST-1622 | Spec-AC-07 | integration | tests/skills/test-aai-ride-select.sh | a started capability-only pair under advisory, trigger firing and not firing: no action bind anywhere in stdout; the on variant of the same fixture does print bind (positive control) | `sed:s/  if \(!rm\.budget\) return nextNoBudget\(rm, docsDir\);/  if (rm.posture === 'off') return nextNoBudget(rm, docsDir);/` in .aai/scripts/ride-select.mjs | green |
| TEST-1623 | Spec-AC-07 | integration | tests/skills/test-aai-ride-select.sh | one P1, four P2 and two intakes at threshold 3: candidates are five, the P1 first, then the P2 follow-ups oldest first; with one P1, one P2 and two intakes the order is P1, P2, intakes by id | `sed:s/SEVERITY_RANK = \{ P1: 0, P2: 1 \}/SEVERITY_RANK = { P1: 1, P2: 0 }/` in .aai/scripts/ride-select.mjs | green |
| TEST-1624 | Spec-AC-07 | integration | tests/skills/test-aai-ride-select.sh | eight counted items at threshold 3: exactly five candidates and waiting count 8 | `sed:s/const CANDIDATE_CAP = 5;/const CANDIDATE_CAP = 50;/` in .aai/scripts/ride-select.mjs | green |
| TEST-1625 | Spec-AC-07 | integration | tests/skills/test-aai-ride-select.sh | next without json on a firing fixture: exit 0, three lines starting maintenance proposed (threshold), waiting:, or continue with: and the third ends with the off text answer | `sed:s/maintenance proposed \(/maintenance (/` in .aai/scripts/ride-select.mjs | green |
| TEST-1626 | Spec-AC-07 | integration | tests/skills/test-aai-ride-select.sh | advisory with --ledger pointing at a directory: stdout equals off, exit 0, stderr starts ride-select: advisory not evaluated; with an absent ledger path and three draft issues at threshold 3 it fires (intakes only) | `sed:s/if \(w\.unreadable\) \{/if (false) {/` in .aai/scripts/ride-select.mjs | green |
| TEST-1627 | Spec-AC-07 | integration | tests/skills/test-aai-ride-select.sh | on and off fixtures: next with --ledger and --events pointing at directories prints the same stdout, empty stderr and exit as without those flags | `sed:s/if \(rm\.posture === 'advisory'\) \{/if (rm.posture !== 'on') {/` in .aai/scripts/ride-select.mjs | green |
| TEST-1628 | Spec-AC-08 | integration | tests/skills/test-aai-ride-select.sh | no roadmap file: waiting json count 6, follow_ups P1 1 P2 2, intakes issue 2 techdebt 1, recommended_threshold 11; with one item recommended 5; ledger and docs tree sha256 identical before and after | `sed:s/Math\.max\(5, w\.count \+ 5\)/Math.max(5, w.count)/` in .aai/scripts/ride-select.mjs | green |
| TEST-1629 | Spec-AC-08 | integration | tests/skills/test-aai-ride-select.sh | waiting with --ledger pointing at a directory exits 2 naming the ledger; with an absent ledger exits 0 and counts intakes only | `sed:s/if \(w\.unreadable\) usage\(/if (false) usage(/` in .aai/scripts/ride-select.mjs | green |
| TEST-1630 | Spec-AC-09 | integration | tests/skills/test-aai-ride-select.sh | advisory threshold 7: show first line maintenance budget: advisory (threshold 7); show json budget false and advisory maintenance_threshold 7; TEST-1309 selector exits 0 unmodified | `sed:s/maintenance budget: advisory/maintenance budget: off/` in .aai/scripts/ride-select.mjs | green |
| TEST-1631 | Spec-AC-10 | integration | tests/skills/test-aai-roadmap.sh | budget advisory --threshold 9 from off, from on and from advisory 4: one budget block with exactly mode advisory and maintenance_threshold 9 before pairs, every pair line unchanged, validate exit 0, show prints advisory (threshold 9) | `sed:s/const base = hasBudget\(text\) \? removeBudget\(text\) : text;/const base = text;/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1632 | Spec-AC-10 | integration | tests/skills/test-aai-roadmap.sh | budget off from advisory removes the block, validate exit 0, show prints maintenance budget: off | `sed:s/if \(rm\.posture === 'off'\) refuse/if (!rm.budget) refuse/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1633 | Spec-AC-10 | integration | tests/skills/test-aai-roadmap.sh | budget on from advisory leaves exactly maintenance_per_capability 1, validate exit 0, show prints maintenance budget: on | `sed:s/if \(rm\.posture === 'on'\) refuse/if (rm.posture !== 'off') refuse/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1634 | Spec-AC-10 | integration | tests/skills/test-aai-roadmap.sh | usage refusals exit 2 with sha256 and directory listing unchanged: budget advisory without --threshold; --threshold 0, 1.5, -2, 05, abc; --threshold with budget on, budget off and add; budget sometimes; (validation round 1 NB1) --threshold above Number.MAX_SAFE_INTEGER (9007199254740993) | `sed:s/BigInt\(n\) > BigInt\(Number\.MAX_SAFE_INTEGER\)/false/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1635 | Spec-AC-10 | integration | tests/skills/test-aai-roadmap.sh | budget advisory --threshold 4 when already advisory 4 exits 1 byte-identical; budget on when on and budget off when off still exit 1 with today's messages | `sed:s/if \(rm\.posture === 'advisory' && rm\.advisory\.maintenance_threshold === a\.threshold\) refuse/if (false) refuse/` in .aai/scripts/roadmap-edit.mjs | green |
| TEST-1636 | Spec-AC-11 | integration | tests/skills/test-aai-roadmap.sh | advisory fixture: ship-append of a change intake prints roadmap: appended and adds an active pair; ship-append of an issue intake is a named no-op; advance flips a pair whose capability doc is done while its bound maintenance doc is draft; each matches the off fixture result | `sed:s/if \(!rm\.budget\) rm\.advisory = \{ maintenance_threshold: Number\(bthr\) \};/if (!rm.budget) { rm.advisory = { maintenance_threshold: Number(bthr) }; rm.budget = { maintenance_per_capability: 1 }; }/` in .aai/scripts/lib/roadmap-model.mjs | green |
| TEST-1637 | Spec-AC-12 | integration | tests/skills/test-aai-roadmap.sh | seam: pair binding a draft maintenance doc; nothing-left-behind json docs_open has no paired-half entry under advisory, one under on, and one for an invalid roadmap that carries a budget line (unchanged control) | `sed:s/loaded\.roadmap\.posture !== 'on'/false/` in .aai/scripts/nothing-left-behind.mjs | green |
| TEST-1638 | Spec-AC-13 | integration | tests/skills/test-aai-roadmap.sh | seam: buildSnapshot candidate gate admitted for an off-roadmap issue intake equals the CLI gate exit-0 verdict on the advisory root and equals the off root, consulted true; loadRoadmap pairs json equal for the advisory and off variants | `sed:s/rm\.posture = rm\.budget \? 'on' : \(rm\.advisory \? 'advisory' : 'off'\);/rm.posture = rm.budget ? 'on' : 'off'; if (rm.advisory) rm.budget = rm.advisory;/` in .aai/scripts/lib/roadmap-model.mjs | green |
| TEST-1639 | Spec-AC-14 | unit | tests/skills/test-aai-roadmap.sh | SKILL_ROADMAP action 7 names on, advisory and off, roadmap-edit.mjs budget advisory --threshold, ride-select.mjs waiting --json and recommended_threshold; TEST-1329 and TEST-1330 selectors exit 0 | `sed:s/budget advisory --threshold/budget advisory/` in .aai/SKILL_ROADMAP.prompt.md | green |
| TEST-1640 | Spec-AC-15 | unit | tests/skills/test-aai-roadmap.sh | SKILL_SHIP INPUT names propose_maintenance, candidates, alternative, one menu, recommended and no other question; TEST-1331 and TEST-1338 selectors exit 0; (validation round 1 B1) option (2)'s alternative is routed exactly as if next --json had answered it directly, never to the printed-verbatim/stop catch-all via the old ambiguous "any other answer below" link | `sed:s/handled exactly as if\s+`next --json` had answered it directly \(a `next` with a `path` is\s+ridden as that path; a `file-intake` is ridden as the need, per the\s+rules above\); any other answer/handled exactly as any other answer below; any other answer/` in .aai/SKILL_SHIP.prompt.md | green |
| TEST-1641 | Spec-AC-16 | integration | tests/skills/test-aai-prompt-diet.sh | the ledger entry for roadmap-maintenance-budget-advisory equals the measured byte growth of SKILL_ROADMAP and SKILL_SHIP, the TEST-012 checkpoint moves by the same amount, and the whole suite exits 0 | `sed:s/\nJUSTIFIED_ADDITIONS\+=\( "[0-9]* roadmap-maintenance-budget-advisory[^\n]*//` in tests/skills/lib/prompt-diet-ledger.sh | green |
| TEST-1642 | Spec-AC-17 | unit | tests/skills/test-aai-roadmap.sh | USER_GUIDE roadmap section has an advisory posture table row and an Example 4: an advisory budget H3 naming /aai-roadmap budget and /aai-ship; the /aai-roadmap note lists budget (on, advisory or off); TEST-1333 selector exits 0 | `sed:s/### Example 4: an advisory budget/### Example 4/` in docs/USER_GUIDE.md | green |
| TEST-1643 | Spec-AC-17 | unit | tests/skills/test-aai-roadmap.sh | docs/product/roadmap.md names mode: advisory, maintenance_threshold, propose_maintenance and ride-select.mjs waiting and carries one worked example per posture (off, on, advisory) | `sed:s/mode: advisory/mode: sometimes/g` in docs/product/roadmap.md | green |
| TEST-1644 | Spec-AC-18 | unit | tests/skills/test-aai-roadmap.sh | suite-map.yaml lists .aai/scripts/follow-ups.mjs inside the aai-ride-select block (read by block, not by a file-wide grep) | `patch:docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-1644.patch` removes the follow-ups.mjs line from the aai-ride-select block of tests/skills/suite-map.yaml | green |
| TEST-1645 | Spec-AC-07 | integration | tests/skills/test-aai-ride-select.sh | (validation round 1 NB2) an issue doc with no frontmatter `id` still counts toward W and yields an intake candidate whose id is derived from the filename (extractDocIds primary, else the filename stem), never empty/null; the text form names the derived id with no trailing empty-id comma | `sed:s/const id = fm\.id \?\? \(extractDocIds\(n\)\?\.primary \?\? n\.replace\(\/\\\.md\$\/i, ..\)\);/const id = fm.id;/` in .aai/scripts/ride-select.mjs | green |
| TEST-1646 | Spec-AC-19 | integration | tests/skills/test-aai-ride-select.sh | (PR #431 bot finding, Codex 4190003343) a malformed non-comment `decisions.jsonl` line (one meant to record a P1 follow-up) degrades `waiting --json` with a stderr `ride-select: degraded:` line and a non-empty `degraded` json entry naming the exclusion; the count is unaffected (still the 2 valid follow-ups) | `sed:s/if \(reg\.malformed\) \{/if (false) {/` in .aai/scripts/ride-select.mjs | green |
| TEST-1647 | Spec-AC-19 | integration | tests/skills/test-aai-ride-select.sh | (PR #431 bot finding, Codex 4190003349) an unreadable `issues/*.md` intake entry — a directory named with a `.md` suffix (EISDIR) and a chmod 000 file (EACCES) — degrades `waiting --json` with one path+code stderr line each and two `degraded` json entries; only the one readable intake counts | `sed:s/catch \(err\) \{ degraded\.push\(/catch (err) { false && degraded.push(/` in .aai/scripts/ride-select.mjs | green |
| TEST-1648 | Spec-AC-19 | integration | tests/skills/test-aai-ride-select.sh | (PR #431 bot finding, Codex 4190003356) a malformed JSON line and an invalid `work_item_closed` record (unparseable `ts`) in `--events` each degrade `next --json` with a stderr line naming the file, count and kind, and a `degraded` json entry; `C` still falls back to `roadmap_order` correctly | `sed:s/if \(invalidCloseRecords\) degraded\.push\(/if (false) degraded.push(/` in .aai/scripts/ride-select.mjs | green |
| TEST-1649 | Spec-AC-19 | integration | tests/skills/test-aai-ride-select.sh | clean-input control: a clean ledger/docs/events fixture reports `degraded: []` on both `waiting --json` and a firing `next --json` proposal, with no stderr; the proposal keeps D6's exact key order (`degraded` last) | `sed:s/let malformedLines = 0;/let malformedLines = 1;/` in .aai/scripts/ride-select.mjs | green |
| TEST-1650 | Spec-AC-19 | integration | tests/skills/test-aai-ride-select.sh | (validation round 3 B-1) a NON-firing advisory `next` (maintenance_threshold held above the visible W by one excluded chmod-000 intake) still discloses the exclusion on stderr; stdout equals the off answer byte-for-byte | `patch:docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-TEST-1650.patch` moves `reportDegraded(degraded);` from before the `adviseMaintenance` call to inside the `if (reason)` block in .aai/scripts/ride-select.mjs | green |
| TEST-1651 | Spec-AC-19 | integration | tests/skills/test-aai-ride-select.sh | (validation round 3 NB-1) a control character (newline) embedded in a degraded path stays on exactly one physical stderr line, with no forged second `ride-select: degraded:` line; the json `degraded` array keeps the raw (unescaped) reason | `sed:s/escapeControlChars\(reason\)/reason/` in .aai/scripts/ride-select.mjs | green |
| TEST-1652 | Spec-AC-19 | integration | tests/skills/test-aai-ride-select.sh | (validation round 3 NB-2) an unreadable `<docs>/issues` DIRECTORY itself (as opposed to one unreadable entry inside it) degrades `waiting --json` with a stderr line and a `degraded` json entry | `` sed:s/if \(err && err\.code !== 'ENOENT'\) degraded\.push\(\`\${dir}: unreadable/if (false) degraded.push(`${dir}: unreadable/ `` in .aai/scripts/ride-select.mjs | green |
| TEST-1653 | Spec-AC-19 | integration | tests/skills/test-aai-ride-select.sh | (validation round 3 NB-2) an unreadable `--events` FILE itself (as opposed to a malformed/invalid record inside it) degrades a firing `next --json` with a stderr line and a `degraded` json entry; `C` still falls back to `roadmap_order` | `` sed:s/if \(err && err\.code !== 'ENOENT'\) degraded\.push\(\`\${eventsPath}: unreadable/if (false) degraded.push(`${eventsPath}: unreadable/ `` in .aai/scripts/ride-select.mjs | green |

Counts: 54 rows; 49 integration, 5 unit. Seams crossed by executing the real
consumer: S1 (TEST-1606, TEST-1636), S2 and S4 (TEST-1638), S3 (TEST-1637),
S5 (TEST-1607..1629 run the real follow-ups fold over a ledger written by the
real `follow-ups.mjs add`/`close`).

## Seams

| Seam | Producer | Consumer | Covered by |
|------|----------|----------|------------|
| S1   | the advisory budget block parsed by lib/roadmap-model.mjs | ride-select gate and roadmap-edit ship-append and advance, which branch on rm.budget | TEST-1606, TEST-1636 |
| S2   | ride-select.mjs gate under advisory (CLI exit code) | orchestration-dispatch.mjs roadmapGate candidate admitted flag | TEST-1638 |
| S3   | the top-level budget line in docs/ai/roadmap.yaml | nothing-left-behind.mjs readRoadmapPairs (its own line reader) | TEST-1637 |
| S4   | loadRoadmap pairs under advisory | merge-policy.mjs readRoadmapCapabilitiesAtBase (exclude_roadmap_capability) | TEST-1638 parser arm; residual R4 |
| S5   | follow-ups.mjs add and close writing the decisions ledger, docs frontmatter, EVENTS work_item_closed written by close-work-item | ride-select.mjs waitingMaintenance and lastClosedCapability | TEST-1607..1629 |
| S6   | ride-select next json propose_maintenance | SKILL_SHIP INPUT menu (an LLM reads it) | TEST-1640 pins text; residual R1 |
| S7   | prompt corpus bytes | test-aai-prompt-diet.sh TEST-010 and TEST-012 | TEST-1641 |

## Residual risks

- R1 — S6 is prose: no automated test runs an LLM through `/aai-ship` with no
  argument against a firing advisory roadmap. TEST-1640 pins the wording only.
- R2 — The related trigger repeats on every `next` until the related P1/P2
  follow-ups are closed or a newer capability closes. That is the intended
  "propose, never require" posture (option 2 continues), but an owner who
  declines repeatedly is asked the same menu each time. No snooze exists in
  this scope; suggested: `fu-advisory-proposal-snooze`.
- R3 — A ride taken from a `follow_up` candidate files a new intake; nothing in
  this scope closes the follow-up when that ride closes, so the same follow-up
  keeps counting until `follow-ups.mjs close` runs. Suggested:
  `fu-maintenance-ride-closes-its-follow-up`.
- R4 — S4 is covered at the parser output (the exact `pairs` merge-policy maps
  to capabilities), not by a full merge-policy base-commit fixture; the
  merge-policy reader adds no posture logic of its own.
- R5 — `W` counts owner sign-off items (`fu-amend-*`, 32 of the 77 open P2 in
  this repository) that a maintenance ride cannot discharge (HITL-2).
- R6 — `waiting` reads the working tree's docs/issues, so untracked drafts of
  other sessions in a shared checkout count (2 at planning time).
- R7 — The pre-existing `fu-roadmap-docstatus-two-parsers` split remains:
  ride-select `findDoc` (line scan) and the new intake counter
  (`parseFrontmatter`) may read a quoted `status: "done"` differently.

## HITL items (recorded defaults; none blocks the freeze)

- HITL-1 — Switch this repository's live roadmap to advisory after delivery?
  Default: no (owner decision 2026-10-05 set it off; D13). If the owner wants
  it, the measured recommended threshold today is 95 (W = 90), and the related
  trigger would fire at once on the two open P2 follow-ups of
  configurable-merge-policy-lanes.
- HITL-2 — Exclude `fu-amend-*` owner sign-off items from `W` and from
  candidates? Default: no, the intake's definition is kept literally (D3).
- HITL-3 — Recommended threshold formula max(5, W+5). Default: kept; the owner
  may pick any positive integer in the menu.

## Registry items closed by this scope

None.

Open items in the same neighbourhood, NOT CLOSED, and why (from
`node .aai/scripts/follow-ups.mjs list`, 2026-10-05):
- `fu-backlog-is-not-queryable` (P2) — advisory `next` reads two of the four
  sources it names (follow-up ledger, doc lifecycle) and only in one posture;
  mutation-record drift and ac_evidence gaps are not read, so the item stays
  open.
- `fu-roadmap-docstatus-two-parsers` (P3) — this scope uses
  `parseFrontmatter` for the new intake count and does not re-route
  `findDoc`/`docStatus` (R7).
- `fu-merge-policy-ride-pr-binding`, `fu-merge-policy-glob-unicode-question`
  (P2), `fu-merge-policy-decision-ref-frac-ts` (P3) — merge-policy internals;
  untouched.
- `fu-amend-roadmap-driven-ride-sele-1e2448`, `fu-amend-spec-roadmap-takes-direction`,
  `fu-amend-roadmap-serves-downstrea-bc77da` (P2) — owner sign-offs owed on
  earlier amendments; discharging them is the owner's.
- `fu-bind-wave2-reason-generic`, `fu-harvest-write-excl-one-sided`,
  `fu-resolvedoc-stale-type-field`, `fu-t760-guard-narrows-to-fu-refs`,
  `fu-roadmap-pair-pinned-by-index`, `fu-ride-select-absent-intake-mismatch`
  (P3) — `roadmap-propose.mjs` internals and fixture pins; untouched.

## Verification

- `env -u AAI_ROLE bash tests/skills/test-aai-ride-select.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-roadmap.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-orchestration-dispatch.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-downstream-autopilot.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-merge-policy.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-golden-flow.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-hygiene-pack.sh` — exit 0.
- `env -u AAI_ROLE bash tests/skills/test-aai-layer-profiles.sh` — exit 0.
- `node .aai/scripts/ride-select.mjs validate` — exit 0; `node
  .aai/scripts/ride-select.mjs show` first line `maintenance budget: off`
  (D13, a one-time check, deliberately not a permanent test: pinning the live
  posture would break the day the owner switches it).
- `git diff main -- docs/ai/roadmap.yaml` adds no `budget:` line.
- `node .aai/scripts/check-vendored-script-deps.mjs` — clean (ride-select now
  imports follow-ups.mjs; nothing-left-behind imports lib/roadmap-model.mjs).
- `node .aai/scripts/mutation-gate.mjs` over this spec — every row RED under
  its mutation.
- One full sweep before close (`AAI_TEST_TIMEOUT=3000`).
- PASS criteria: all TEST-xxx green, all Spec-AC terminal, a RED record for
  each of the 50 rows under
  `docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/`.

## Evidence contract

- ref_id: roadmap-maintenance-budget-advisory
- Per TEST-xxx: the `mutation-run.mjs` record at
  `docs/ai/tdd/spec-roadmap-maintenance-budget-advisory/mutation-<TEST-id>.txt`
  carrying `verdict: RED`, plus the suite command, its exit code and the
  assertion text naming the observable.
- Review scope: branch diff `main...change/roadmap-maintenance-budget-advisory`
  over the Files list in `## Implementation plan`.

### Evidence by strategy

Strategy `tdd`: a stored RED artifact per AC-gating test plus the full
verification matrix.
