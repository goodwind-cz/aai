---
id: spec-slim-standing-role-context
type: spec
number: 243
status: done
mutation_gate: v1
frozen_sha256: a98ab11d0ae6f2a20b0405c89874bbac2a68cd9a69679d9d98eb10fee26edcbd
ceremony_level: 2
links:
  requirement: slim-standing-role-context
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Slim the standing role context: split LEARNED.md into always-loaded and on-demand parts

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-0218-slim-standing-role-context.md
- Parent: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md (phase 4, child 1 of the owner-approved order of 2026-10-22)
- Related, not absorbed: docs/issues/DEBT-0005-hazard-canon-delivery-and-duplication.md
- Technology contract: docs/TECHNOLOGY.md

## Scope and baseline

Baseline tree: main `01de211960bf3df94c70da2d98d3a6fb81f50528`. The base
LEARNED blob used by every conservation test is
`01de211960bf3df94c70da2d98d3a6fb81f50528:docs/knowledge/LEARNED.md`
(27,638 bytes; last changed at `3edb9368`). An immutable SHA, never a moving ref.

Measured on that tree with `node .aai/scripts/canon.mjs build --role <R> --ref HEAD`
piped to `wc -c` (2026-10-22, Planning):

| Role | Bytes |
|---|---|
| Validation | 59,764 |
| Implementation | 45,303 |
| Planning | 46,570 |
| Remediation | 40,188 |
| TDD Implementation | 53,159 |
| Code Review | 47,017 |

The payload is four framed sections: contract (`.aai/SUBAGENT_CONTRACT.md`,
7,232 B), role prompt, `learned` (`docs/knowledge/LEARNED.md`, 27,638 B), scope.
The five `- HAZ-` standing hazards (`standing_hazards: 5` in
`.aai/system/CANON.yaml`) all live in the contract section; LEARNED.md
carries none.

### Target reconciliation (disclosed scope decision)

The intake's AC-001 (Validation at most 29,882 B, 50% of the baseline) is
arithmetically unreachable by any LEARNED-only slice. Measured: the Validation
build with the `learned` section reduced to a single 2-byte line is 32,128 B,
so the floor with zero LEARNED content is about 32,126 B (a 46.2% reduction,
still above 29,882). The remaining distance to RFC-0017's 50% target lives in
`.aai/VALIDATION.prompt.md` (24,568 B) and the contract, which the intake
places out of scope ("later RFC-0017 phase 4 slices").

This spec therefore replaces the intake's absolute AC-001 with a target this
slice can own: LEARNED.md's always-loaded part at most half its baseline, the
same moved byte count removed from every role, and Validation at most
45,945 B on the baseline tree shape (at least 23.1% smaller). RFC-0017's 50%
Validation target stays a program-level target owed by later slices. This is a
change to the intake's stated threshold, disclosed here per the
additive-with-disclosure convention; canon assigns the final call to the owner,
who may choose a different classification rule (see Residual risks R1) or widen
the slice.

## Implementation strategy

- Strategy: tdd
- Rationale: the change is a content move guarded by new deterministic checks (a lint rule, conservation and classification tests, hash/payload seam tests) and by edits to four existing suites that today read LEARNED.md alone. Each of those checks must be observed RED against the current tree (or against a planted fixture) before the move lands, otherwise a conservation test that only ever saw the split state proves nothing about loss. No intake-recorded strategy exists for this ref (the intake Notes carry no `Implementation mode (user choice):` line).

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound multi-surface change (knowledge file, lint, five suites, one prompt, prompt-diet ledger) in a checkout shared with other sessions that hold unrelated untracked drafts and an uncommitted INDEX/roadmap edit; the split must be committed as one coherent diff. Not L3: no protected path is touched. Planning creates nothing; Implementation Preparation decides.
- User decision: undecided
- Base ref: main
- Inline review scope: docs/knowledge/LEARNED.md, docs/knowledge/history/LEARNED-HISTORY.md, .aai/SKILL_REPLAY.prompt.md, tests/skills/lib/learned-guard-lints.mjs, tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh, tests/skills/test-aai-hygiene-pack.sh, tests/skills/test-aai-learned-routing.sh, tests/skills/test-aai-canon.sh, tests/skills/suite-map.yaml, CHANGELOG.md, docs/issues/CHANGE-0218-slim-standing-role-context.md, docs/specs/SPEC-0243-spec-slim-standing-role-context.md
- Code review: required, independent dual verdict over this explicit scope against main.

## Design and boundaries

### D1: Mechanism — a second file in a subdirectory, no assembly change

The on-demand part is a new file `docs/knowledge/history/LEARNED-HISTORY.md`.
`docs/knowledge/LEARNED.md` keeps its path and becomes the always-loaded part.

Consequences, each deliberate:
- `.aai/system/CANON.yaml`, `.aai/scripts/canon.mjs` and
  `.aai/scripts/lib/prompt-hash.mjs` are NOT changed. The `learned` section and
  both hash implementations already read exactly `docs/knowledge/LEARNED.md`, so
  "the hash covers exactly what is assembled" holds by construction; the history
  file is neither assembled nor hashed. Spec-AC-04 proves it rather than
  assuming it.
- A downstream project with a single unsplit LEARNED.md runs the identical
  code path it runs today (Spec-AC-05). The split is opt-in by layout: a
  project that never creates the history file sees nothing new.
- The subdirectory is load-bearing: both `aai-sync.sh` (`docs/knowledge/*`
  with a `-f` filter) and `aai-sync.ps1` (`Get-ChildItem -File`) copy
  top-level files only. A top-level `LEARNED-HISTORY.md` would be seeded into
  every downstream project on its next sync (measured 2026-10-22: a fresh
  scratch target receives every top-level `docs/knowledge` file). The
  subdirectory keeps this repository's history out of downstream projects
  without touching either sync script.

A section-marker mechanism inside one file was considered and rejected: it
needs a cut in `canon.mjs` and a matching cut in `prompt-hash.mjs` (the
TEST-682/683 pairing), changes downstream behavior for any project whose file
contains the marker, and is more code than a file move.

### D2: Classification rule (deterministic)

Definitions over the base blob. An ENTRY is a line starting `- ` that follows
the first `## ` heading, together with its continuation lines up to the next
line starting `- ` or `## `. The preamble (everything before the first `## `
heading) is not an entry.

An entry MOVES to the history file if and only if:
- (a) its first line carries a guard marker `[guard → <id>]` (after an optional
  `[YYYY-MM-DD] ` prefix) AND either `<id>` does not start with `fu-` (it names
  a guard that already exists, per the file's own marker contract) or the entry
  text contains `guard shipped:` or `routed to canon`; or
- (b) the entry text contains `**RESOLVED `.

Every other entry STAYS: every `[local]` entry (by the file's own contract "the
note IS the fix", so it must stay loaded) and every guard entry whose guard is
still pending (nothing enforces it yet).

Rationale: the file's own preamble already defines a shipped-guard entry as one
whose control lives in the layer; once the guard is in force, the note is
history and the guard is the control. No judgement is applied per entry.
Measured on the base blob: 18 entries move (about 15,000 B), 17 stay.

Headings: the preamble and the five category headings (`## Code Style`,
`## Testing`, `## Workflow`, `## Architecture`, `## Conventions`) with their
example comments stay in LEARNED.md (they are `learned-append.mjs --section`
targets). A `## Session …` heading stays in LEARNED.md iff at least one of its
entries stays. In the history file, moved entries appear verbatim under a copy
of their original heading line, in base order. Entry text is never edited.

### D3: Pointer and the forward rule (in LEARNED.md, always loaded)

LEARNED.md gains one paragraph after the marker-contract paragraphs that states:
the history path; that it exists only where a project has created it ("when
present"); the read command
`grep -n '^## \|^- ' docs/knowledge/history/LEARNED-HISTORY.md`; the D2 rule
in one sentence; and the forward rule: new lessons append to LEARNED.md
(`learned-append.mjs` default target, unchanged), and a scope that ships an
entry's guard, or marks it `**RESOLVED`, moves that entry verbatim to the
history file in the same change. At most 900 bytes.

The forward rule is enforced in this repository by a new lint rule
`learned-standing` in `tests/skills/lib/learned-guard-lints.mjs`: it reports
every D2-moved-class entry found in a LEARNED.md. Run by the hygiene pack over
the live file. Downstream projects are not linted (tests/skills is not vendored).

`/aai-wrap-up` needs no change: it appends through `learned-append.mjs`, whose
default target is LEARNED.md, and a freshly learned lesson is `[local]` or a
pending guard, which D2 keeps. Spec-AC-06 pins that seam.

### D4: On-demand reach through replay

`.aai/SKILL_REPLAY.prompt.md` step 3a (the canonical "relevant prior learnings"
search) is extended to also search `docs/knowledge/history/*.md` when present,
labelled distinctly. Without it, replay would stop surfacing every moved lesson.
This adds bytes to the prompt corpus, so the companion obligation applies: one
`JUSTIFIED_ADDITIONS` entry in `tests/skills/lib/prompt-diet-ledger.sh` and the
matching TEST-012 checkpoint bump in `tests/skills/test-aai-prompt-diet.sh`. No
new `.aai/**` file, so no PROFILES.yaml entry.

### D5: Existing readers of LEARNED.md move to the union

Three existing checks read `docs/knowledge/LEARNED.md` alone and would go red or
vacuous after the move; each must read LEARNED.md plus the history file:
- `tests/skills/test-aai-learned-routing.sh` TEST-006 (triage markers, guard
  pointers resolve, no pre-edit body deleted against pin `9296160c`).
- `tests/skills/test-aai-hygiene-pack.sh` test_126 (six `fu-learned-*` markers
  cite `guard shipped:`; all six move under D2).
- `tests/skills/test-aai-hygiene-pack.sh` TEST-668 (session-marker): already
  walks `docs/knowledge` recursively, so it covers the history file unchanged;
  its header assertions stay on LEARNED.md, whose preamble is unchanged.
`tests/skills/suite-map.yaml` gains `docs/knowledge/history/**` for
aai-learned-routing, aai-hygiene-pack and aai-canon.

## Seams and residual risks

- S1: LEARNED.md (producer) -> `canon.mjs build` payload (consumer) -> byte
  delta in every role. Crossed by TEST-001 against the real manifest.
- S2: the same LEARNED.md -> `computeCanonPrintHash` and
  `computeEffectivePromptHash` -> telemetry digest. Crossed by TEST-005, which
  edits the history file and LEARNED.md in a fixture and asserts the real
  payload and both real digests.
- S3: this repository's `docs/knowledge/` -> `aai-sync.sh` -> a downstream
  project's `docs/knowledge/`. Crossed by TEST-007 with the real sync script on
  scratch targets.
- S4: LEARNED.md -> `learned-append.mjs` (wrap-up writer) -> the
  `learned-standing` lint. Crossed by TEST-009.
- S5: history file -> existing readers (TEST-006 routing, test_126) and the
  replay prompt. Crossed by TEST-008 and TEST-011.
- S6: a changed path -> `select-suites.mjs` -> the suites that guard it.
  Crossed by TEST-012.

Residual risks:
- R1: D2 moves 18 entries whose guard is in force. Some carry incidental advice
  their guard does not enforce (for example the `haz-restore-subagent-contract`
  entry's "serialize audit-touching suites", the `close-work-item-self-verify`
  entry's "hand-close those"). That advice leaves standing context and becomes
  reachable through the pointer and replay only. The alternative of also
  unloading the undated `[local]` Session log (about 6 KB more, Validation about
  36% smaller) was rejected because it unloads notes that are the only fix. The
  owner may choose it.
- R2: a fresh downstream install with no LEARNED.md today receives this
  repository's whole LEARNED.md through sync (pre-existing behavior, measured).
  After the split it receives the slim file, whose pointer names a history file
  it will not have; the pointer is phrased "when present" for that reason. The
  pre-existing seeding itself is out of scope (suggested follow-up below).
- R3: the 50% Validation target of RFC-0017 is not met by this slice (see
  Target reconciliation).
- R4: token benefit is measured in bytes only; RFC-0017's "confirm with actual
  task token usage" is not attested by this slice.

## Acceptance Criteria Mapping

| Requirement | Spec-AC | Verification and decisive observable | Evidence |
|---|---|---|---|
| AC-001 (revised, see Target reconciliation) | Spec-AC-01 | TEST-001: every manifest role shrinks by exactly bytes(base LEARNED) minus bytes(LEARNED.md); LEARNED.md at most 13,819 B; Validation at most 45,945 B on the baseline tree shape | docs/ai/tdd/slim-learned-ac01.log |
| AC-002 | Spec-AC-02 | TEST-002: five HAZ lines byte-identical in all six payloads; every D2-stay entry of the base blob present verbatim in LEARNED.md | docs/ai/tdd/slim-learned-ac02.log |
| AC-003 | Spec-AC-03 | TEST-003, TEST-004: every base line present in the union; history entries equal exactly the D2-move set; lint reports 0 live and bites planted fixtures | docs/ai/tdd/slim-learned-ac03.log |
| AC-004 | Spec-AC-04 | TEST-005: digests agree for six roles; a history edit changes neither payload nor digests; a LEARNED.md edit changes all three | docs/ai/tdd/slim-learned-ac04.log |
| AC-005 | Spec-AC-05 | TEST-006, TEST-007: unsplit fixture builds with learned section equal to its file; real sync leaves an owned LEARNED.md byte-identical and creates no history directory | docs/ai/tdd/slim-learned-ac05.log |
| AC-006 | Spec-AC-06 | TEST-008, TEST-009: pointer paragraph and replay line name the existing history path; the wrap-up writer lands in LEARNED.md and passes the lint | docs/ai/tdd/slim-learned-ac06.log |
| Verification (suites) | Spec-AC-07 | TEST-010, TEST-011, TEST-012: diet ledger and pin agree; union readers green; selector picks the guarding suites | docs/ai/tdd/slim-learned-ac07.log |

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN canon.mjs build runs for each of the six manifest roles the payload SHALL be smaller than the same-tree build with the base LEARNED blob by exactly bytes(base blob) minus bytes(LEARNED.md), LEARNED.md SHALL be at most 13,819 bytes, and with VALIDATION.prompt.md and SUBAGENT_CONTRACT.md byte-identical to 01de2119 the Validation payload SHALL be at most 45,945 bytes | done | docs/ai/tdd/slim-learned-ac01.log | — | D1, D2; replaces intake AC-001 threshold |
| Spec-AC-02 | WHEN the payload is built for any role the five HAZ standing-hazard lines SHALL be present byte-identical to the baseline and every base-blob entry that D2 classifies as stay SHALL occur verbatim in LEARNED.md | done | docs/ai/tdd/slim-learned-ac02.log | — | D2 |
| Spec-AC-03 | WHEN the split lands every line of the base blob SHALL occur in LEARNED.md or the history file, the history file's entries SHALL equal exactly the D2 move set in base order with unchanged text, and the learned-standing lint SHALL report zero on the live LEARNED.md and flag a planted shipped-guard entry and a planted RESOLVED entry while sparing a pending fu guard entry | done | docs/ai/tdd/slim-learned-ac03.log | — | D2, D3 |
| Spec-AC-04 | WHEN the history file changes the payload and both effective-prompt-hash digests SHALL stay unchanged, WHEN LEARNED.md changes the payload and both digests SHALL change, and canon.mjs print-hash SHALL equal computeEffectivePromptHash for all six roles on the live tree | done | docs/ai/tdd/slim-learned-ac04.log | — | D1; TEST-682/683 class |
| Spec-AC-05 | WHEN a project has a single unsplit LEARNED.md and no history file canon.mjs build SHALL exit 0 with the learned section byte-equal to that file, and WHEN aai-sync.sh runs into a project that owns its LEARNED.md that file SHALL stay byte-identical and no docs/knowledge/history directory SHALL be created | done | docs/ai/tdd/slim-learned-ac05.log | — | D1; R2 |
| Spec-AC-06 | WHEN a role needs the on-demand part LEARNED.md SHALL carry a pointer paragraph of at most 900 bytes naming the existing history path, the read command, the D2 rule and the forward rule, SKILL_REPLAY step 3a SHALL name the history path, and a learned-append.mjs dry-run against the live LEARNED.md SHALL land in LEARNED.md with a candidate the learned-standing lint accepts | done | docs/ai/tdd/slim-learned-ac06.log | — | D3, D4 |
| Spec-AC-07 | WHEN the scope is validated the prompt-diet ledger SHALL carry an entry equal to the SKILL_REPLAY byte growth with TEST-012 green, the routing TEST-006 and hygiene test_126 SHALL read the union and pass, and select-suites.mjs SHALL select aai-learned-routing, aai-hygiene-pack and aai-canon for a change to the history file | done | docs/ai/tdd/slim-learned-ac07.log | — | D4, D5 |

## Implementation plan

1. RED first (tdd): add TEST-001..TEST-012 against the untouched tree and record
   each RED in `docs/ai/tdd/slim-learned-acNN.log`. Expected REDs: TEST-001
   (delta 0), TEST-003 (history file absent), TEST-004 (rule absent), TEST-005
   (history file absent, so the history-edit arm cannot run; record as RED by
   absence and also prove the arm against a planted fixture), TEST-006/007
   (planted mutation per Test Plan, since the unsplit case is green today and
   must be proven sensitive), TEST-008/009/010/012 (pointer, replay line, ledger
   entry, glob absent), TEST-011 (planted deletion of a moved body from the
   union).
2. Implement the D2 classifier as a pure function inside the test library
   (`tests/skills/lib/learned-guard-lints.mjs`, exported for the tests and used
   by the `learned-standing` rule) so classification, lint and conservation
   tests share one definition.
3. Produce the split by moving entries verbatim (a mechanical script run once in
   scratch, its output reviewed and committed; the script itself is not
   shipped). Insert the D3 pointer paragraph. Do not edit any entry text.
4. Extend SKILL_REPLAY step 3a (D4); add the ledger entry and bump the TEST-012
   checkpoint; extend suite-map.yaml (D5).
5. Move routing TEST-006 and hygiene test_126 to the union (D5).
6. Measure all six roles before and after into the AC-01 log; run the selected
   suites plus canon, prompt-hash, hygiene-pack, learned-routing,
   learned-append, prompt-diet, suite-select, layer-profiles and update.

Edge cases: CRLF is normalized by canon.mjs but not by the conservation test;
compare on LF-normalized text. The `→` marker is U+2192; regexes must match it
(test_126's own comment records an ASCII-only regex passing vacuously). A
`## Session` heading line may legitimately appear in both files.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-canon.sh | For each of the six manifest roles build with the real manifest and with a scratch manifest whose learned path is the base blob extracted from 01de2119; assert each delta equals bytes(base) minus bytes(LEARNED.md); the two absolute ceilings (LEARNED.md at most 13,819 B, Validation at most 45,945 B) are measured once at hand-off into the AC-01 log and not pinned in the suite, since a standing ceiling would block legitimate lesson growth | `sed:s/path: docs\/knowledge\/LEARNED.md/path: docs\/knowledge\/history\/LEARNED-HISTORY.md/` on .aai/system/CANON.yaml | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-canon.sh | Extract HAZ lines from each role payload and from the base-tree payload and compare byte-for-byte (count 5); run the D2 classifier over the base blob and assert every stay entry occurs verbatim in LEARNED.md (a later scope that legitimately moves one re-pins the base SHA deliberately, as routing TEST-006 does) | `` sed:s/NEVER `git clean` under/NEVER gone under/ `` on docs/knowledge/LEARNED.md | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-hygiene-pack.sh | LF-normalize; every non-blank base-blob line occurs in LEARNED.md or the history file; the history file contains every D2 move-set entry of the base blob, in base order, with identical text; later appends to either file do not break the check | `sed:s/process-group reap/pgrp-reap/` on docs/knowledge/history/LEARNED-HISTORY.md | green |
| TEST-004 | Spec-AC-03 | unit | tests/skills/test-aai-hygiene-pack.sh | learned-standing lint: zero on the live LEARNED.md; flags a planted shipped-guard entry and a planted RESOLVED entry on a scratch fixture; spares a pending fu guard entry (control); positive control that the fixture was scanned | `sed:s/guard shipped:/guard-shipped-never:/g` on tests/skills/lib/learned-guard-lints.mjs | green |
| TEST-005 | Spec-AC-04 | integration | tests/skills/test-aai-canon.sh | Live tree: canon.mjs print-hash equals computeEffectivePromptHash for six roles. Fixture tree: appending to the history file leaves the payload and both digests unchanged; appending to LEARNED.md changes the payload and both digests | `sed:s/docs\/knowledge\/LEARNED.md/docs\/knowledge\/history\/LEARNED-HISTORY.md/g` on .aai/scripts/lib/prompt-hash.mjs | green |
| TEST-006 | Spec-AC-05 | integration | tests/skills/test-aai-canon.sh | Fixture project with the base blob as its only LEARNED.md and no history directory: canon.mjs build exits 0 for six roles and the learned section between its frame markers is byte-equal to the fixture file | `sed:s/path: docs\/knowledge\/LEARNED.md/path: docs\/knowledge\/history\/LEARNED-HISTORY.md/` on .aai/system/CANON.yaml | green |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-hygiene-pack.sh | Real aai-sync.sh into two scratch targets (absolute non-empty paths checked before use): an owned target keeps its LEARNED.md byte-identical and gains no docs/knowledge/history; a fresh target gains no docs/knowledge/history and its seeded LEARNED.md pointer carries the when-present qualifier | `sed:s/when present/always/` on docs/knowledge/LEARNED.md | green |
| TEST-008 | Spec-AC-06 | integration | tests/skills/test-aai-learned-routing.sh | LEARNED.md has exactly one pointer paragraph of at most 900 B naming docs/knowledge/history/LEARNED-HISTORY.md, the read command, the D2 rule and the forward rule; that path exists; SKILL_REPLAY step 3a names the same path | `sed:s/docs\/knowledge\/history\/LEARNED-HISTORY.md/docs\/knowledge\/LEARNED-HISTORY.md/` on .aai/SKILL_REPLAY.prompt.md | green |
| TEST-009 | Spec-AC-06 | integration | tests/skills/test-aai-learned-routing.sh | learned-append.mjs dry-run with no target and a sample rule against a scratch copy of the live tree: the candidate is LEARNED.md plus a pure tail append and the learned-standing lint over the candidate reports zero; with a guard flag naming a pending fu id it is still accepted | `sed:s/const DEFAULT_TARGET = 'docs\/knowledge\/LEARNED.md'/const DEFAULT_TARGET = 'docs\/knowledge\/history\/LEARNED-HISTORY.md'/` on .aai/scripts/learned-append.mjs | green |
| TEST-010 | Spec-AC-07 | integration | tests/skills/test-aai-prompt-diet.sh | Existing TEST-012 with the bumped checkpoint plus a new JUSTIFIED_ADDITIONS entry whose byte value equals the measured SKILL_REPLAY growth | `sed:s/ slim-standing-role-context / renamed-scope /` on tests/skills/lib/prompt-diet-ledger.sh | green |
| TEST-011 | Spec-AC-07 | integration | tests/skills/test-aai-learned-routing.sh | Routing TEST-006 and hygiene test_126 read LEARNED.md plus the history file: all six fu-learned markers found with guard shipped, no pinned-base body missing from the union | `sed:s/A pin described as immutable/A pin described as mutable/` on docs/knowledge/history/LEARNED-HISTORY.md | green |
| TEST-012 | Spec-AC-07 | integration | tests/skills/test-aai-suite-select.sh | select-suites.mjs given docs/knowledge/history/LEARNED-HISTORY.md selects aai-learned-routing, aai-hygiene-pack and aai-canon | `sed:s/docs\/knowledge\/history\/\*\*/docs\/knowledge\/history-x\/**/g` on tests/skills/suite-map.yaml | green |

### RED observations and negative controls

Every row's RED is recorded before its GREEN in the named AC log. For rows that
are green on the unsplit tree by design (TEST-002, TEST-006, TEST-007 owned
arm), the RED is the named mutation applied in a scratch copy, never in the
shipping tree (HAZ-SCRATCH, HAZ-RESTORE), with the unmutated positive control
run first. Mutation runs go through `mutation-run.mjs` against a copy.
Absence assertions (no history directory created, no digest change) each carry
a positive control proving the producing step ran (sync printed its knowledge
step; the fixture edit changed the file's own sha256).

## Verification

- Before/after table: `node .aai/scripts/canon.mjs build --role <R> --ref HEAD`
  piped to `wc -c` for all six roles, on the implementation head and on the
  same head with the base blob substituted, recorded in the AC-01 log.
- Suites, each via `env -u AAI_ROLE bash tests/skills/<suite>.sh`:
  test-aai-canon.sh, test-aai-prompt-hash.sh, test-aai-hygiene-pack.sh,
  test-aai-learned-routing.sh, test-aai-learned-append.sh,
  test-aai-prompt-diet.sh, test-aai-suite-select.sh,
  test-aai-layer-profiles.sh, test-aai-update.sh.
- `node .aai/scripts/docs-audit.mjs --strict` CLEAN; `node .aai/scripts/spec-lint.mjs --path <this spec>` clean.
- PASS criteria: all TEST-xxx green, all Spec-AC terminal.

## Evidence contract

Every artifact records ref `slim-standing-role-context`, Spec-AC and TEST ids,
the actual command and exit code, the head SHA, and the evidence path. RED and
GREEN logs per AC live under `docs/ai/tdd/slim-learned-acNN.log` (tdd: stored
RED per AC-gating test plus the verification matrix above). Validation's
authoritative report is returned as `outcome_report` and as the
`set-validation --evidence` path. Planning claims no implementation result.

### Evidence by strategy

| Strategy | Evidence this spec may demand |
|---|---|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop | per-TEST-xxx green runs; RED-proof observed, storage optional |
| direct | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |

## Registry review

`node .aai/scripts/follow-ups.mjs list` scanned 2026-10-22 for learned, canon,
prefix, hazard, knowledge, replay and wrap-up subjects.
fu-learned-header-format-stale names LEARNED.md's header Format comment; this
scope moves entries and adds one paragraph but does not rewrite that comment
(lesson-text and header rewrites are out of scope), so it stays open.
fu-orchestration-parallel-still-pastes and fu-subagent-protocol-input-row-stale
concern how other prompts describe the payload builder, not LEARNED.md.
DEBT-0005 (hazard canon delivery and duplication) is a separate, related debt
and is not absorbed. Suggested, not filed: `fu-sync-seeds-source-learned` (a
fresh downstream install receives this repository's own LEARNED.md through
sync; R2).
Registry items closed by this scope: none.
