---
id: spec-ac-table-premature-flip-recurs
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: ac-table-premature-flip-recurs
  rfc: null
  pr: []
  commits: []
---

# SPEC — the premature AC flip gets a mechanical guard at Implementation hand-off

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-DRAFT-ac-table-premature-flip-recurs.md
- Prior art, directly reused mechanism: docs/specs/SPEC-0160-spec-gate-ac-row-escaped-pipe-blind.md
  (one shared reconciliation function feeding two gate-level consumers, so the
  two can never drift; that spec fixed a live instance of exactly the
  divergence this scope must avoid)
- Prior art, the rule this scope mechanizes:
  docs/specs/SPEC-0151-spec-validation-defers-the-ac-flip-to-close.md
  (AC-FLIP DEFERRAL written into `.aai/VALIDATION.prompt.md` step 8a and
  `.aai/SKILL_PR.prompt.md` step 4c)
- Heuristic being reused: docs/specs/SPEC-0039-spec-false-open-drift-heuristic.md
  and docs/specs/SPEC-0040-spec-docs-audit-d2-evidence-hardening.md D2(c) v2
- Technology contract: docs/TECHNOLOGY.md

## Problem

`docs-audit.mjs`'s probable-false-open heuristic fires on one particular
content shape, its D2(c) arm (`.aai/scripts/lib/docs-audit-core.mjs`
`falseOpenEvidence`): a doc whose frontmatter `status` is still open
(`draft` / `implementing` / `accepted`) while its canonical
`## Acceptance Criteria Status` table is fully terminal, every `done` row
evidenced, and at least one `done` row cites DELIVERY-grade evidence — a
git-verifiable commit hash or a PR reference, as opposed to a
`docs/ai/tdd/*.log` proof path. Reaching that shape reddens every suite that
asserts a literal `Verdict: CLEAN` from a full strict audit
(`test-aai-doc-numbering.sh` TEST-013, `test-aai-deslop.sh` TEST-028,
`test-aai-docs-audit.sh`, `test-aai-delta-stage3.sh`,
`test-aai-doc-number-reservation.sh`, `test-aai-repo-tripwire.sh` TEST-006),
and unwinding it costs a full remediation round. Observed twice in one
session (the CHANGE-0168 ride, self-caught; the ISSUE-0046 ride, caught as
Validation round-1 FAIL).

Two facts make this a recurrence rather than an accident.

FIRST, nothing mechanical looks for this shape until Validation runs the full
strict audit — one role-dispatch cycle after Implementation introduced it.

SECOND, and this is the root cause the intake did not have: the canon at the
Implementation end still instructs the edit that produces the shape.
`.aai/ROLE_COMMON.md` "PRE-HANDOFF AC-TABLE RECONCILIATION" — the single
block inherited by `.aai/IMPLEMENTATION.prompt.md` step 9b and
`.aai/SKILL_TDD.prompt.md` Phase 4 step 1b — says: "Set each covered row to a
terminal status (done | deferred | blocked | rejected) with concrete Evidence
(commit SHA, RUN_ID, or log path)". A commit SHA IS the delivery-grade
citation the heuristic keys on. SPEC-0151 rewrote the Validation end and the
close end of this rule and left the Implementation end untouched, so an agent
that follows step 9b to the letter manufactures the exact state
`.aai/VALIDATION.prompt.md` step 8a forbids. The distinction that keeps a
mid-flight terminal table legitimate — cite the proof artifact, not the
delivery — is real, deliberate (SPEC-0040 D2(c) v2 exists to draw it), and
written down nowhere an implementer reads.

## Ceremony level

`ceremony_level: 2`. The scope edits the shared audit engine
(`.aai/scripts/lib/docs-audit-core.mjs`) that `docs-audit.mjs --check`,
`--gate` and the close ceremony all read, adds a CLI mode, and changes canon
prose in `.aai/ROLE_COMMON.md`. It is not a single-surface fix, and it
touches nothing on `protected_paths_l3` in docs/ai/docs-audit.yaml (checked:
state engine, allocator, `pre-commit-checks.sh`/`.ps1`, workflow canon,
CONSTITUTION — none of the planned paths match). Same surface, same level as
SPEC-0160.

## Implementation strategy
- Strategy: tdd
- Rationale: the whole value of this scope is a predicate that FIRES on one
  shape and stays silent on three neighbouring ones. A guard that has never
  been observed failing on the defect proves nothing, and the three
  must-not-fire cases are precisely where a hand-written guard would go
  wrong. Each of the four discrimination cases gets a RED observation before
  the mode exists.
- RED-proof obligation: before any edit, build the four fixtures below and
  record that `node .aai/scripts/docs-audit.mjs --ac-flip-check <ID>` exits 2
  as an unknown flag (the mode does not exist), while
  `node .aai/scripts/docs-audit.mjs --check` on the SAME defect fixture
  already reports `probable-false-open`. That contrast IS the RED: the
  knowledge exists in the engine and is unreachable at hand-off time. Save
  docs/ai/tdd/ac-table-premature-flip-recurs-red.log.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: this scope edits
  `tests/skills/lib/prompt-diet-ledger.sh` and
  `tests/skills/test-aai-prompt-diet.sh`, and an OPEN concurrent ride (PR
  #332, branch `change/release-protected-branch-fallback`) edits the same two
  files — its branch carries `want_growth=9319` where `main` carries 8127.
  Two rides appending to one append-only ledger in one working tree would
  interleave. A worktree branched from a clean `main` keeps the two ledger
  edits separable and rebasable.
- User decision: worktree (already realized —
  /Users/ales/Projects/aai-fix-ac-table-premature-flip-recurs on branch
  `fix/ac-table-premature-flip-recurs`)
- Base ref: main (960c3f1)
- Worktree branch/path: fix/ac-table-premature-flip-recurs at
  /Users/ales/Projects/aai-fix-ac-table-premature-flip-recurs
- Inline review scope: not applicable (worktree selected)

Explicit review scope (code_review):
- .aai/scripts/lib/docs-audit-core.mjs (D2(c) arm extracted to one exported
  predicate plus the new `acFlipCheckDoc` entry point)
- .aai/scripts/docs-audit.mjs (`--ac-flip-check <DOC-ID>` mode, header usage
  block)
- .aai/ROLE_COMMON.md (PRE-HANDOFF AC-TABLE RECONCILIATION: evidence-shape
  correction plus the guard invocation)
- tests/skills/test-aai-docs-audit.sh (new stanzas)
- tests/skills/test-aai-prompt-diet.sh (wiring pin, ledger pin bump)
- tests/skills/lib/prompt-diet-ledger.sh (JUSTIFIED_ADDITIONS entry)
- docs/specs/SPEC-DRAFT-spec-ac-table-premature-flip-recurs.md,
  docs/issues/ISSUE-DRAFT-ac-table-premature-flip-recurs.md
- docs/INDEX.md (regenerated, mechanical)

## Design decisions

### D1 — the guard's predicate IS the audit's arm, extracted once

`falseOpenEvidence`'s D2(c) block (`.aai/scripts/lib/docs-audit-core.mjs`,
the `if (ac?.hasGate && ac.rows.length > 0)` block computing `allTerminal`,
`allDoneEvidenced`, `hasDeliveryEvidence`) moves verbatim into one exported
function, `acTableDeliverySignal(root, ac)`, returning
`{ fires, deliveryRows }`. `falseOpenEvidence` calls it and keeps pushing the
byte-identical reason string `AC Status table fully terminal with evidence`.
The new mode calls the SAME function. One definition, two consumers — the
SPEC-0160 D2 pattern, applied to the heuristic the intake named.

The consequence to state plainly, because it is counter-intuitive: the guard
does NOT forbid a terminal AC table on an open doc. It forbids a terminal AC
table whose evidence claims DELIVERY on an open doc. A stricter guard
("never terminal while `status` is open") would be a second, diverging
heuristic — it would fire on states `docs-audit --check --strict` accepts as
CLEAN, and it would deadlock against `--gate`, which the same PRE-HANDOFF
step requires to exit 0 and which demands every row terminal. Keying on the
audit's own arm makes agreement structural rather than maintained.

### D2 — a new opt-in CLI mode, not a fold into `--gate`

`docs-audit.mjs` gains `--ac-flip-check <DOC-ID>`, mirroring `--gate`'s
resolution (the two-pass frontmatter-id then display-id scan of `gateDoc`)
and `--gate`'s exit contract: 0 clean, 1 defect, 2 when the id resolves to no
scanned doc or to more than one. It is scope-limited to the one doc and
emits no `docs_audit` event, like every other predicate mode.

Folding the check into `gateContent` instead was considered and REJECTED on a
concrete hazard: `.aai/SKILL_PR.prompt.md` step 4c flips the AC table and
clears VALIDATION step 8b's close gate on the flipped table BEFORE
`close-work-item.mjs` flips the frontmatter. In that window the doc is
legitimately terminal-and-delivery-evidenced under an open `status`, and a
`--gate` that refused it would block every close ceremony in the repo. A
separate opt-in mode leaves `--gate` byte-identical on every path that
already calls it.

### D3 — the check is gated on frontmatter status, which is what discriminates

`acFlipCheckDoc(root, docId)` resolves the doc, then returns clean without
consulting the table at all unless the frontmatter `status` is one of
`draft` / `implementing` / `accepted` (the module's existing
`FALSE_OPEN_STATUSES`, which stays private — the exported entry point does
the gating). It also returns clean for a doc carrying frontmatter
`umbrella: true`, the same frontmatter-only suppression `runAudit` applies
before it ever calls `falseOpenEvidence`.

That single condition satisfies the three discriminations the intake demands,
structurally rather than by heuristic:
- terminal table plus open frontmatter, written by Implementation: FIRES.
- terminal table plus `status: done`, written transactionally by
  `close-work-item.mjs`: the status test excludes it before the table is
  read. It cannot fire on the close ceremony's end state, and it cannot fire
  on the close ceremony's intermediate state either, because that state is
  never handed to this mode (D2).
- non-terminal table in flight: `allTerminal` is false, the shared predicate
  returns `fires: false`.

### D4 — the output names the fix, not just the fault

Exit 1 prints the doc's path, each `done` row whose Evidence cell carries a
delivery-grade citation with the offending token, and one remediation line
naming where the citation belongs: replace it with the run or proof artifact
now, and let `.aai/SKILL_PR.prompt.md` step 4c write the delivery citation at
the close flip, in the same transaction as the frontmatter. A guard whose
message does not say which of the two legitimate shapes to move to would send
the agent to the wrong one (Constitution Art. 4).

### D5 — the canon that instructs the defect is corrected at its single source

`.aai/ROLE_COMMON.md` "PRE-HANDOFF AC-TABLE RECONCILIATION" is the ONE place
both implementer prompts inherit this rule from, so both fixes land there and
nowhere else:
- the evidence-shape bullet stops naming a commit SHA as an acceptable
  pre-handoff citation and names the proof artifact instead (a
  `docs/ai/tdd/*.log` path, a RUN_ID, a suite output path), stating that the
  delivery citation is added by the close flip.
- the self-check bullet gains the second command next to the existing
  `--gate` invocation.

`.aai/IMPLEMENTATION.prompt.md` step 9b and `.aai/SKILL_TDD.prompt.md` Phase 4
step 1b are NOT edited: `tests/skills/test-aai-state.sh` TEST-017 pins the
literals `Acceptance Criteria Status`, `docs-audit.mjs --gate` and
`exit 0 before reporting complete` in both files, and those literals stay
true and untouched. The new command string appears exactly once in the whole
prompt corpus, which is the anti-duplication discipline SPEC-0151 D3
established.

### D6 — scope boundaries

- `.aai/VALIDATION.prompt.md` is NOT edited. Its step 8a already states the
  rule correctly and its step 8b already re-runs the gate at close.
- The pre-commit hook is NOT wired to this mode. Beyond
  `.aai/scripts/pre-commit-checks.sh` being an L3 protected path, the hook's
  close-gate block in `.aai/scripts/install-pre-commit-hook.sh` only gates a
  staged spec whose staged diff ADDS a `status: done` line — it never looks
  at an open doc, so this defect class is invisible to it by construction.
- The LEAN (`ceremony_level` 0/1) AC table is NOT covered, because
  `falseOpenEvidence`'s D2(c) arm reads only the canonical `doc.ac` table and
  therefore cannot fire on a lean table today. Extending the arm would change
  the audit's verdicts, which is a different scope. Recorded as a residual
  risk and filed, not silently widened.
- `spec-lint.mjs` is not touched.

## Constitution deviations

None.

Honest per-article check (docs/CONSTITUTION.md v1): Art. 1 — the scope adds a
command that produces executable evidence at the moment the claim is made,
strengthening the evidence chain; Art. 2 — one extracted function, one CLI
flag, two corrected prose bullets, no new file and no new config surface;
Art. 3 — plain `.mjs` and Markdown, tri-platform, no service store; Art. 4 —
the new mode fails loudly with a named remediation and exits 2 rather than 0
when it cannot resolve the doc; Art. 5 — additive: a new flag, a new exported
function, byte-identical behavior for every existing caller of `--gate`,
`--check` and `falseOpenEvidence`; Art. 6 — no `docs/ai/STATE.yaml` write from
the audit engine; Art. 7 — the scope ends at `gh pr create`.

## Acceptance Criteria Mapping

- Maps to ISSUE Expected Behavior (a mechanical guard runs at or before
  Implementation's hand-off)
  - Spec-AC-01: WHEN `node .aai/scripts/docs-audit.mjs --ac-flip-check <ID>`
    runs against a spec whose frontmatter status is `implementing` and whose
    canonical AC Status table is fully terminal with every done row evidenced
    and at least one done row citing a git-verifiable commit hash or a PR
    reference, THEN it SHALL exit 1 and print the doc path, each offending
    done row with its citation token, and a remediation line naming the close
    flip as the citation's proper home.
  - Verification: TEST-001.
- Maps to ISSUE Verification bullet 2 (a correctly deferred table must not
  trip the guard)
  - Spec-AC-02: WHEN the same mode runs against a spec whose frontmatter
    status is open and whose AC Status table carries any non-terminal row,
    THEN it SHALL exit 0. The same holds for a fully terminal table whose
    every done row cites only a `docs/ai/tdd/` proof path, which is the
    mid-flight state `docs-audit --check --strict` accepts as CLEAN.
  - Verification: TEST-002.
- Maps to ISSUE Verification bullet 3 and Constraints bullet 1 (the close
  ceremony's own transactional flip must not trip the guard)
  - Spec-AC-03: WHEN the same mode runs against a spec whose frontmatter
    status is `done` and whose AC Status table is fully terminal with
    delivery-grade evidence, which is exactly what `close-work-item.mjs`
    leaves behind, THEN it SHALL exit 0. `docs-audit.mjs --gate` SHALL return
    the same exit code and the same printed reasons on every fixture in this
    spec as it did before the change, so the close path is provably untouched.
  - Verification: TEST-003.
- Maps to ISSUE Constraints bullet 2 (reuse the existing detection rather
  than reimplementing it)
  - Spec-AC-04: The terminal-plus-evidenced-plus-delivery-citation predicate
    SHALL exist as exactly ONE function in
    `.aai/scripts/lib/docs-audit-core.mjs`, called by both `falseOpenEvidence`
    and the new mode. On one fixture corpus covering all four discrimination
    cases, `--ac-flip-check` exiting 1 and `--check` classifying that doc
    `probable-false-open` with the reason
    `AC Status table fully terminal with evidence` SHALL agree case for case,
    in both directions.
  - Verification: TEST-004.
- Maps to ISSUE Impact (the fix must not itself redden the sweep the defect
  reddens)
  - Spec-AC-05: After the extraction, `node .aai/scripts/docs-audit.mjs
    --check --strict --no-event` over the real repository SHALL exit 0 with
    `Verdict: CLEAN`, and `tests/skills/test-aai-docs-audit.sh`,
    `test-aai-ceremony-levels.sh`, `test-aai-close-work-item.sh`,
    `test-aai-doc-numbering.sh` and `test-aai-state.sh` SHALL exit 0.
  - Verification: TEST-005.
- Maps to ISSUE Current Behavior (nothing at Implementation time checks; and
  the canon there instructs the defect)
  - Spec-AC-06: `.aai/ROLE_COMMON.md` PRE-HANDOFF AC-TABLE RECONCILIATION
    SHALL name the `--ac-flip-check` command and SHALL NOT offer a commit SHA
    as a pre-handoff Evidence citation; the command string SHALL appear
    exactly once across `.aai/*.prompt.md`, `.aai/AGENTS.md` and
    `.aai/ROLE_COMMON.md`; and `tests/skills/test-aai-state.sh` TEST-017 SHALL
    stay green, proving the two implementer prompts kept their pinned
    literals.
  - Verification: TEST-006.
- Maps to the PLANNING companion obligation (prompt-corpus growth owes a
  ledger true-up)
  - Spec-AC-07: The `.aai/ROLE_COMMON.md` byte growth SHALL be measured with
    `wc -c` before and after, credited 1:1 by one new `JUSTIFIED_ADDITIONS`
    entry in `tests/skills/lib/prompt-diet-ledger.sh` whose leading integer
    equals the measured delta, with `want_growth` in
    `test_012_growth_sum_matches_ledger` moved by exactly that integer, and
    `bash tests/skills/test-aai-prompt-diet.sh` SHALL exit 0 with TEST-010
    headroom unchanged.
  - Verification: TEST-007.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                   | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | The guard exits 1 on an open doc whose terminal AC table carries a delivery-grade citation      | planned | —        | —         | —     |
| Spec-AC-02 | The guard exits 0 on a non-terminal in-flight table and on a terminal table cited only by a proof log | planned | —        | —         | —     |
| Spec-AC-03 | The guard exits 0 on the close ceremony's terminal-plus-done end state; --gate stays byte-identical | planned | —        | —         | —     |
| Spec-AC-04 | One shared predicate; guard and --check agree case for case in both directions                  | planned | —        | —         | —     |
| Spec-AC-05 | Repo-wide strict audit stays CLEAN and the five named suites stay green                         | planned | —        | —         | —     |
| Spec-AC-06 | ROLE_COMMON names the guard and drops the commit-SHA citation; the command appears once; TEST-017 green | planned | —        | —         | —     |
| Spec-AC-07 | Measured corpus growth credited 1:1 in the ledger with the TEST-012 pin moved by the same integer | planned | —        | —         | —     |

## Implementation plan

- Components affected:
  - `.aai/scripts/lib/docs-audit-core.mjs` — extract `acTableDeliverySignal`
    (exported), add `acFlipCheckDoc(root, docId)` (exported) reusing the
    `gateDoc` two-pass resolution.
  - `.aai/scripts/docs-audit.mjs` — `--ac-flip-check` in `parseArgs` through
    `requireValue`, a `runAcFlipCheck` emitter mirroring `emitGate`, one
    dispatch line in `main()` next to the other predicate modes, and a usage
    line in the header block.
  - `.aai/ROLE_COMMON.md` — two bullets in one existing block.
  - Tests and the prompt-diet ledger.
- Data flow: `acFlipCheckDoc(root, id)` resolves content, reads
  `parseFrontmatter` for `status` and `umbrella`, and only then calls
  `parseAcTable` and `acTableDeliverySignal(root, ac)`; the CLI turns the
  result into the exit code and the printed lines.
- Edge cases: a doc with no AC Status table (`hasGate` false) is clean; an
  empty table (`rows.length === 0`) is clean; a done row whose Evidence cell
  carries a hex token that is NOT a git object is clean, because
  `cellHasDeliveryCitation` verifies each token against the repository's
  object store; a doc resolving to two files exits 2 with both candidates
  named, inherited from the shared resolution.
- Ordering note for Implementation: this scope's OWN spec doc must be handed
  off with its rows non-terminal or cited only by its proof log. Run the new
  guard on this spec before reporting complete — the scope dogfoods itself.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description                                                                                              | Status  |
|----------|------------|-------------|-----------------------------------------|----------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh     | Fixture repo, spec status implementing, all rows done, one Evidence cell citing a real commit hash in the fixture repo: --ac-flip-check exits 1, stdout names the row and the token and the close-flip remediation; a PR-reference variant exits 1 too | green   |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh     | Same fixture with one row left planned: exit 0. Same fixture fully terminal but every Evidence cell citing only docs/ai/tdd/x.log: exit 0 | green   |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh     | Same fixture with frontmatter status done and delivery-grade evidence: exit 0. An umbrella true open doc in the same shape: exit 0. --gate on all fixtures returns the pre-change exit codes and reasons | green   |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh     | Cross-check over the four fixtures: --ac-flip-check exit 1 if and only if --check classifies that doc probable-false-open citing the AC Status table reason; plus a grep asserting one definition site of the predicate | green   |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-docs-audit.sh     | Repo-wide docs-audit --check --strict --no-event exits 0 CLEAN post-change; the five named suites re-run green; generate-docs-index.mjs idempotent on a second run | green   |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-prompt-diet.sh    | ROLE_COMMON PRE-HANDOFF block carries the --ac-flip-check invocation and no longer offers a commit SHA as pre-handoff evidence; corpus-wide occurrence count of the command string is 1; test-aai-state.sh TEST-017 re-run green | green   |
| TEST-007 | Spec-AC-07 | integration | tests/skills/test-aai-prompt-diet.sh    | The measured wc -c delta of .aai/ROLE_COMMON.md equals the new ledger entry's leading integer and the want_growth movement; TEST-010 and TEST-012 exit 0 with headroom unchanged | green   |

Seam analysis:
- Seam S1 — `falseOpenEvidence` is the producer whose D2(c) arm moves. Its
  consumers are `runAudit`'s drift classification, which feeds `--check`, the
  digest, the `docs_audit` event counts and six downstream suites. TEST-004
  crosses this seam in both directions on one corpus rather than asserting
  the extracted function in isolation; TEST-005 crosses it on the real
  repository, which is the only place the corpus is realistic.
- Seam S2 — `--gate` and the new mode share `gateDoc`'s two-pass id
  resolution and both are reached by the close path. TEST-003 asserts
  `--gate`'s exit codes and reasons on every fixture, so a resolution change
  made for the new mode cannot silently move the close gate.
- Seam S3 — `.aai/ROLE_COMMON.md` is a producer for two prompt consumers that
  a test pins by literal (`test-aai-state.sh` TEST-017 on the prompts,
  `test-aai-prompt-diet.sh` on the ROLE_COMMON pointers). TEST-006 asserts
  both sides in one stanza so the edit cannot satisfy one pin by breaking the
  other.
- Residual risk, recorded: the lean (`ceremony_level` 0/1) AC table is out of
  scope (D6). A premature flip on a lean table does not redden the audit
  today, so the guard staying silent there is agreement, not a gap — but it
  becomes a gap the day the D2(c) arm learns the lean shape. File as
  `fu-ac-flip-guard-lean-table-blind` (P3).
- Residual risk, recorded: the guard runs when an agent runs it. Nothing
  forces an Implementation agent that skips the PRE-HANDOFF block to reach
  it. Bounded by the fact that Validation's full strict audit remains the
  backstop it is today, so the worst case is exactly today's cost, never
  worse.
- Residual risk, recorded: `tests/skills/suite-map.yaml`'s `aai-state` globs
  do not list `.aai/ROLE_COMMON.md`, so a future edit to the PRE-HANDOFF
  block alone will not select the suite carrying TEST-017. This scope does
  not introduce the gap and does not widen the glob; file as
  `fu-suitemap-state-missing-role-common` (P3).
- Registry items closed by this scope: none.
- Adjacent open registry items, deliberately left open (split out of the
  bullet above so `follow-ups.mjs verify-closures` cannot read these ids as
  closure claims — its inline-label scan runs to the next bullet, and
  test-aai-follow-ups.sh TEST-029 reported both as MISSes when they shared a
  bullet with the "closed by this scope" label): `node
  .aai/scripts/follow-ups.mjs list` carries one open item on an adjacent
  subject, `fu-ac-flip-must-precede-close` (P3), which is about the ORDER of
  two steps INSIDE the close ceremony (flip before `close-work-item.mjs`, not
  after) and is already canon in `.aai/SKILL_PR.prompt.md` step 4c. Closing
  it needs an ordering refusal inside `close-work-item.mjs`, a different
  mechanism from a pre-handoff predicate, so this scope deliberately leaves
  it open. `fu-mask-duplicates-docs-audit-core` (P2) is the same
  two-copies-of-one-heuristic family but concerns `spec-lint.mjs`'s specimen
  masker, untouched here.

## Verification
- `node .aai/scripts/docs-audit.mjs --ac-flip-check <fixture-id>` on the four
  fixtures: exit 1, 0, 0, 0 as mapped in Spec-AC-01 through Spec-AC-03.
- `bash tests/skills/test-aai-docs-audit.sh` exits 0 with the new stanzas.
- `bash tests/skills/test-aai-prompt-diet.sh` exits 0.
- `bash tests/skills/test-aai-state.sh` exits 0 (TEST-017 unchanged).
- `bash tests/skills/test-aai-ceremony-levels.sh` exits 0.
- `bash tests/skills/test-aai-close-work-item.sh` exits 0.
- `bash tests/skills/test-aai-doc-numbering.sh` exits 0 (TEST-013 CLEAN).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exits 0,
  `Verdict: CLEAN`, run over the real repository.
- `node .aai/scripts/generate-docs-index.mjs` twice, second run idempotent.
- `node .aai/scripts/check-state.mjs docs/ai/STATE.yaml` OK.
- Full framework sweep before close.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract
For each artifact record: ref_id `ac-table-premature-flip-recurs`, the Spec-AC
and TEST-xxx links, the command, the exit code, the evidence path
(docs/ai/tdd/ac-table-premature-flip-recurs-red.log and
docs/ai/tdd/ac-table-premature-flip-recurs-green.log), and the diff range when
available.

### Evidence by strategy
Strategy is `tdd`: a stored RED artifact per AC-gating test under docs/ai/tdd/
plus the full verification matrix above, per
`.aai/templates/SPEC_TEMPLATE.md` "Evidence by strategy".

## Notes for Implementation
- The prompt-diet pin on this worktree's base (`main` @ 960c3f1) is
  `want_growth=8127`. The concurrent PR #332 branch carries 9319. MEASURE the
  pin in the tree you are actually editing at the moment you edit it, and if
  #332 merges first, rebase and re-measure before touching the ledger. Never
  copy a number from this spec into code.
- Adding this spec file makes `test-aai-docs-audit.sh` TEST-003 (index
  regeneration diff) RED until `docs/INDEX.md` is regenerated — the known
  `fu-docsaudit-t003-red-on-new-doc` shape. Regenerate the index; do not
  chase it as a defect.
