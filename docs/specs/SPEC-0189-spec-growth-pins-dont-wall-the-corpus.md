---
id: spec-growth-pins-dont-wall-the-corpus
number: 189
type: spec
status: implementing
mutation_gate: v1
frozen_sha256: 35ff0896ea0d2345c6b8d2579eaf22c40d8435a7c57cd5f339405f8aae33375e
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0195-growth-pins-dont-wall-the-corpus.md
  rfc: null
  pr: []
  commits: []
---

# Spec — a ride's own growth pin stops walling every ride that comes after it

SPEC-FROZEN: true

Ceremony justification: one surface (`tests/skills/test-aai-prompt-diet.sh`),
no production code, no `.aai/**` byte change, no ledger entry and no credit
move. The change relaxes three assertions to a comparison already shipped and
proven in the same file (TEST-023), adds one ceiling arm and one corpus scan.
`tests/skills/` is not in `protected_paths_l3` (docs/ai/docs-audit.yaml:84-92),
so no protected surface is touched. The scope is small; the risk is that the
relaxed arms stop catching anything, which the Test Plan answers by giving
every arm a fabricated mis-credited input in the same run.

## Links
- Requirement: docs/issues/CHANGE-0195-growth-pins-dont-wall-the-corpus.md
- Decision records: docs/knowledge/LEARNED.md (guard-preconditions-downstream)
- Technology contract: docs/TECHNOLOGY.md

## Problem, re-measured

Every figure below was re-read from the repo at base `69b585ba`, under plain
`bash` with `/usr/bin/wc -c` and `/usr/bin/grep`, not taken from the intake.

Four arms in `tests/skills/test-aai-prompt-diet.sh` parse one past ride's
diet-ledger entry, take its `<before> -> <after>` measurement, and compare
`after` to the file's CURRENT on-disk size:

- `:1503` TEST-023, `.aai/ROLE_COMMON.md` — FLOOR (`-lt` fails, `-ne` only
  logs). The intake calls this one an equality pin. It is not, and it has not
  been since `unsigned-spec-amendment-has-no-outflow` fixed it; the live run
  prints the advisory line (disk 6760 B vs credited 5335 B) and still passes.
- `:1601` TEST-622, `.aai/SKILL_UPDATE.prompt.md` — EQUALITY (`-ne` fails).
- `:1661` TEST-697, `.aai/VALIDATION.prompt.md` — EQUALITY.
- `:1719` TEST-746, `.aai/AGENTS.md` — EQUALITY. The intake does not mention
  this arm at all. It shipped with `roadmap-takes-direction` (PR #399, the
  base commit of this ride) and `.aai/AGENTS.md` is the operator-contract
  surface every ride reads, so it is the wall most likely to be hit next.

So the count is right by accident: three walled arms, but a different three
than the intake names.

The wall: the only repair an equality arm accepts is editing the past entry,
which `tests/skills/test-aai-git-ref-guard.sh:935` (TEST-312) forbids by name
— `credit must be paid by ADDING an entry, never by editing history`. TEST-312
additionally EXECUTES this whole suite (`:886`), so one walled arm reddens two
suites.

PR #388's figures re-measured with `git show`: merge-base `f84f84ab` 21152 B,
`origin/main` 21570 B, `origin/feat/original-request-outcome-backcheck`
23163 B; merged = 23163 + 418 = 23581 B. TEST-697 credits `21152 -> 21570`, so
21570 is the only size it accepts and no merge order produces it. Confirmed.
(That branch is also stale — it deletes seven ledger entries `origin/main`
carries, which reddens TEST-312 for a second, unrelated reason that a rebase
fixes. Out of scope.)

What the pins buy today, per file:

| file | inside TEST-010's byte budget | uncredited growth caught by |
|---|---|---|
| `.aai/VALIDATION.prompt.md` | yes, `.aai/*.prompt.md` glob | TEST-010 headroom |
| `.aai/SKILL_UPDATE.prompt.md` | yes, same glob | TEST-010 headroom |
| `.aai/ROLE_COMMON.md` | yes, `extra` accounting (`:331`) | TEST-010 headroom |
| `.aai/AGENTS.md` | NO — not in the glob, not in `extra` | the equality pin, and nothing else |

That table is the whole design. For the first three the equality adds nothing
TEST-010 does not already do, which is why converting them to a floor is free.
For `.aai/AGENTS.md` the equality is the only on-disk control there is, so
converting it to a floor without a replacement would ship a hole — the exact
trap the intake names.

Rejected alternative — verify against `git show <sha>:<path>` (the intake's
suggested direction). It anchors on a state that cannot rot, but: no entry
records the ride's own SHA (two of four name only a merge-base), the commit
does not exist yet while the ride's own TDD runs, and a shallow CI checkout
cannot read it — so the arm would have to degrade to "not checked" on exactly
the input CI produces, which is the DEBT-0004 shape this repo already refuses
by name at `tests/skills/test-aai-git-ref-guard.sh:916`. Rejected.

Rejected alternative — put `.aai/AGENTS.md` into TEST-010's `extra` and raise
`BASELINE_PROMPT_BYTES` by its 22991 B. Arithmetically exact and byte-neutral
today (measured: reduction 30714, headroom 2042 both before and after), but
docs/knowledge/LEARNED.md:106 records a standing rule that rewriting
`BASELINE_PROMPT_BYTES` `would erase history and IS the blank-raise
anti-pattern`. Rejected on that rule; a declared ceiling carries the same
drift protection without touching the baseline.

## Implementation strategy
- Strategy: tdd
- Rationale: the whole risk is a relaxed arm that no longer catches anything.
  Only a RED observed against a fabricated mis-credited input distinguishes a
  working floor from a vacuous one, and the mutation gate then binds each row
  to the mutation that reddens it.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: this suite runs in every ride's companion obligations
  and inside `test-aai-git-ref-guard.sh` TEST-312; editing it in the shared
  checkout would redden other sessions' runs mid-flight.
- User decision: worktree
- Base ref: main (69b585ba)
- Worktree branch/path: fix/growth-pins-dont-wall-the-corpus, ../aai-fix-pins
- Inline review scope: tests/skills/test-aai-prompt-diet.sh

## Acceptance Criteria Mapping
- Maps to: docs/issues/CHANGE-0195-growth-pins-dont-wall-the-corpus.md
  "Desired Behavior (To-Be)"

## Constitution deviations

- Article 5 (Additive first). Spec-AC-05 adds a corpus scan that REFUSES a
  test shape the suite used to accept, which is a restriction at a shared
  boundary rather than an additive edit. Justified: the shape being refused is
  the defect this spec exists to remove, the scan is measured at zero hits
  across `tests/skills/*.sh` before it ships (Spec-AC-05 verification), so no
  existing suite and no ride in flight is newly blocked, and its failure
  message names the permitted floor form so the refusal is actionable
  (Article 4).

## Acceptance Criteria Status

Never use pipe characters inside cells.

| Spec-AC    | Description                                                                                                                                                                      | Status  | Evidence | Review-By | Notes |
|------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | WHEN a diet-ledger arm compares a credited `after` to the file's current size THEN it FAILS only when the file is SMALLER than `after`, and passes when the size is equal or larger | done    | docs/ai/tdd/spec-growth-pins-dont-wall-the-corpus/green-TEST-766.log, docs/ai/tdd/spec-growth-pins-dont-wall-the-corpus/green-TEST-772.log | —         | the wall removal; floor semantics, TEST-023's already-shipped comparison |
| Spec-AC-02 | WHEN an entry's leading credited byte count disagrees with its own `<before> -> <after>` arithmetic THEN the arm FAILS, naming the credited figure and the measured one            | done    | docs/ai/tdd/spec-growth-pins-dont-wall-the-corpus/green-TEST-767.log | —         | the property the arms were written to catch, unchanged |
| Spec-AC-03 | All four diet-ledger arms decide both comparisons through ONE shared pure helper, and each arm exercises that helper against a fabricated mis-credited input in the same run       | done    | docs/ai/tdd/spec-growth-pins-dont-wall-the-corpus/green-TEST-768.log | —         | anti-vacuity: a relaxed operator has nowhere to hide |
| Spec-AC-04 | WHEN `.aai/AGENTS.md` exceeds its declared byte ceiling THEN the suite FAILS naming the ceiling and the overage, and the ceiling is at least the file's current size               | done    | docs/ai/tdd/spec-growth-pins-dont-wall-the-corpus/green-TEST-769.log | —         | replaces the only on-disk control AGENTS.md had; it is outside TEST-010's budget |
| Spec-AC-05 | A scan over `tests/skills/*.sh` reports ZERO arms comparing a live on-disk `.aai/**` byte count for EQUALITY against a value measured in the same arm, and the scan is proven to detect a fabricated arm of that shape | done    | docs/ai/tdd/spec-growth-pins-dont-wall-the-corpus/green-TEST-770.log | —         | the guard against rebuilding the wall |
| Spec-AC-06 | The helper accepts all four measured PR #388 states for the 418 B VALIDATION entry — 21152, 21570, 23163 and 23581 — rejecting only sizes below 21570                             | done    | docs/ai/tdd/spec-growth-pins-dont-wall-the-corpus/green-TEST-771.log | —         | the end-to-end outcome, in the bytes the defect was found in |

Status values: planned, implementing, done, deferred, blocked, rejected.

## Implementation plan

Single file: `tests/skills/test-aai-prompt-diet.sh`.

1. Add one pure helper next to the existing `compute_reduction_headroom`
   consumers, e.g.
   `diet_credit_verdict <label> <lead> <before> <after> <disk>`, echoing `ok`
   or a single reason line and returning 0 or 1. It owns exactly two
   decisions: `lead == after - before` (Spec-AC-02) and `disk >= after`
   (Spec-AC-01). Nothing else moves into it — the per-entry parsing, the
   `n -ne 1` uniqueness check and the ledger-prefix pin stay where they are.
   The reason line for a growth case is informational, never a failure, and
   points at TEST-010 (not TEST-012) as the control that actually catches
   uncredited glob growth — TEST-023's current advisory text names TEST-012,
   which re-sums the ledger array and cannot see a byte on disk.
2. Route TEST-023, TEST-622, TEST-697 and TEST-746 through it, deleting the
   four inline comparisons.
3. Give each of the four arms a bite block: call the helper with a fabricated
   `lead` that disagrees with the arithmetic, and with a fabricated `disk`
   below `after`, and fail the arm if either is ACCEPTED (the TEST-011 /
   TEST-015 synthetic-fixture idiom already used in this file).
4. Add `AGENTS_MD_CEILING` with its measured current value and declared
   headroom, an arm asserting `.aai/AGENTS.md <= AGENTS_MD_CEILING`, and a
   fabricated oversize fixture proving the comparison bites.
5. Add the corpus-scan arm: for each `tests/skills/*.sh`, find a `wc -c` of a
   `.aai/` path assigned to a variable and, within the next 3 lines, a `-ne`
   or `!=` comparison of that variable. Expect zero. Prove the matcher on a
   fabricated snippet carrying the TEST-697 shape verbatim.
6. Register the two new arms in `main()`.

Edge cases: `wc -c < file` pads with spaces on macOS — keep the existing
`tr -d ' '`. The suite runs under `set -euo pipefail`; a helper that returns 1
must be called in a condition, never bare. `qgrep`/`qhead` are the suite's
SIGPIPE-safe wrappers and stay in use. No `.aai/**` byte changes, so no ledger
entry and no PROFILES classification are owed (both companion obligations
skip).

## What happens to the three files and to any ride in flight

Measured at base `69b585ba`:

- `.aai/ROLE_COMMON.md` 6760 B vs credited 5335 B — already passing, stays
  passing, now via the helper.
- `.aai/SKILL_UPDATE.prompt.md` 3418 B vs credited 3418 B — passing, stays
  passing; later growth is now permitted instead of fatal.
- `.aai/VALIDATION.prompt.md` 21570 B vs credited 21570 B — passing, stays
  passing; PR #388's 23163 B and the merged 23581 B go from RED to GREEN.
- `.aai/AGENTS.md` 22991 B vs credited 22991 B — passing, stays passing;
  later growth permitted up to the declared ceiling.

No ride is newly blocked. On the four converted arms the suite accepts
strictly more than it did. The one new refusal is Spec-AC-05's scan, measured
at zero hits over all of `tests/skills/*.sh` before it ships, so nothing in
flight carries the shape it refuses. `TEST-010`'s corpus ratchet, `TEST-012`'s
re-sum, the ledger's append-only discipline and `TEST-312` are untouched: an
uncredited byte in the `.aai/*.prompt.md` glob is caught only once the
corpus ratchet's HEADROOM is exhausted — measured 2042 B on 2026-09-28,
so up to that much uncredited growth now reddens nothing where the
equality caught the first byte. That is a real reduction in cover, taken
knowingly: the equality it replaces made the file unmergeable for every
later ride, and TEST-010's `headroom -lt 0` remains the corpus-wide
control. `.aai/AGENTS.md` keeps a per-file control via Spec-AC-04.

## Seams

- S1 — this suite is EXECUTED by `tests/skills/test-aai-git-ref-guard.sh:886`
  inside TEST-312, which also compares the live ledger to `origin/main`'s.
  A change here can only be judged by running ref-guard too. TEST-772.
- S2 — `tests/skills/test-aai-verify-gate.sh:139-145` carries a second,
  LOOSER copy of the reduction formula that omits `.aai/ROLE_COMMON.md` from
  `extra`. This scope does not touch `BASELINE_PROMPT_BYTES` or the extra set,
  so the divergence neither widens nor narrows; the suite is run as a control
  and the divergence is recorded as R3.
- S3 — every ride's companion obligations run this suite. The change is
  accept-more-only on existing arms (see the section above), which is what
  keeps the seam safe; Spec-AC-05's scan is the single exception and is
  measured clean first.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                     | Description                                                                                                                                   | Mutation                                                       | Status  |
|----------|------------|-------------|------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------|---------|
| TEST-766 | Spec-AC-01 | unit        | tests/skills/test-aai-prompt-diet.sh     | `diet_credit_verdict` rejects a disk size one byte BELOW the credited `after` naming both numbers, and accepts sizes equal to and above it       | sed:s/disk -lt after/disk -gt after/                            | green |
| TEST-767 | Spec-AC-02 | unit        | tests/skills/test-aai-prompt-diet.sh     | `diet_credit_verdict` rejects a fabricated entry whose lead credit is off by one from `after - before`, and accepts the matching one             | sed:s/lead -ne measured/false/                                   | green |
| TEST-768 | Spec-AC-03 | integration | tests/skills/test-aai-prompt-diet.sh     | Each of TEST-023, TEST-622, TEST-697 and TEST-746 calls the helper and fails if a fabricated mis-credited or below-floor input is ACCEPTED       | sed:s/diet_credit_verdict/true diet_credit_verdict/             | green |
| TEST-769 | Spec-AC-04 | integration | tests/skills/test-aai-prompt-diet.sh     | `.aai/AGENTS.md` is at or below `AGENTS_MD_CEILING`, and a fabricated oversize fixture is rejected by the same comparison                        | sed:s/AGENTS_MD_CEILING=/AGENTS_MD_CEILING=99999999 #/          | green |
| TEST-770 | Spec-AC-05 | integration | tests/skills/test-aai-prompt-diet.sh     | The scan over tests/skills/*.sh reports zero equality pins on a live `.aai` byte count, and detects a fabricated arm carrying the TEST-697 shape | sed:s/-ne/-XX-never-matches/                                     | green |
| TEST-771 | Spec-AC-06 | unit        | tests/skills/test-aai-prompt-diet.sh     | For the 418 B VALIDATION entry the helper accepts 21570, 23163 and 23581 and rejects 21152, the merge-base size the file no longer carries       | sed:s/disk -lt after/disk -ne after/                            | green |
| TEST-772 | Spec-AC-01 | e2e         | tests/skills/test-aai-git-ref-guard.sh   | TEST-312 exits 0 with the converted suite, so the embedded run and the ledger append-only comparison both still hold (seam S1)                   | sed:s/disk -lt after/disk -ne after/                            | green |

Test status values: pending, red, green.

RED is observed FIRST for every row, against a fabricated mis-credited input
rather than against the absence of the feature — a row that has only been
observed green proves nothing here and the whole spec exists because three
such rows shipped this month. Each RED run is stored under `docs/ai/tdd/`.

## Verification
- `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh` exits 0 and
  prints PASS lines for TEST-023, TEST-622, TEST-697, TEST-746, TEST-769 and
  TEST-770.
- `env -u AAI_ROLE bash tests/skills/test-aai-git-ref-guard.sh` exits 0 (S1).
- `env -u AAI_ROLE bash tests/skills/test-aai-verify-gate.sh` exits 0 (S2
  control).
- `node .aai/scripts/mutation-run.mjs` produces a RED record per Test Plan row
  and `node .aai/scripts/mutation-gate.mjs` exits 0 at close.
- Rehearsal evidence for Spec-AC-06, recorded once under `docs/ai/tdd/`: grow
  `.aai/VALIDATION.prompt.md` by 1593 B in the worktree to reproduce PR #388's
  23163 B, run the suite, observe TEST-697 GREEN, then restore the file
  and re-run to a clean exit 0. (TEST-010 was predicted RED here and is
  NOT: measured headroom 449/2048, so a 1593 B growth breaches neither
  bound. The rc 1 -> 0 transition on TEST-697 is what the rehearsal proves.)
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
- ref_id: growth-pins-dont-wall-the-corpus
- Spec-AC and TEST-xxx links per row above.
- Commands and exit codes as listed under Verification.
- Evidence paths: `docs/ai/tdd/` RED and GREEN logs per TEST-xxx, the mutation
  records under `docs/ai/mutation/`, and the Spec-AC-06 rehearsal log.
- Diff range: `main..fix/growth-pins-dont-wall-the-corpus`.

### Evidence by strategy

Strategy is `tdd`, so this spec demands a stored RED artifact per AC-gating
test plus the full verification matrix above.

## Registry items closed by this scope

none.

`node .aai/scripts/follow-ups.mjs list` (130 open) carries no item on this
subject. The nearest class-sibling is `fu-roadmap-pair-pinned-by-index` — the
same "pinned by a value that legitimately moves" class, a different subject
(the roadmap's admissible pair, already repaired at its own site). It is not
closed here.

## Residual risks

- R1 — a single uncredited byte of `.aai/AGENTS.md` growth is no longer
  caught; only drift beyond the declared ceiling is. This is a deliberate
  trade: the equality that caught it is the wall, and `.aai/AGENTS.md` sits
  outside TEST-010's byte budget. The same slack already governs the prompt
  glob (headroom 2042 of 2048).
- R2 — Spec-AC-05's matcher is textual. An author who measures into an
  intermediate variable more than three lines from the comparison evades it.
  It is scoped to the observed mechanism: all three walled arms were
  copy-pasted from each other and kept the shape verbatim.
- R3 — `tests/skills/test-aai-verify-gate.sh` TEST-006 omits
  `.aai/ROLE_COMMON.md` from its `extra` set, so its floor is 6760 B looser
  than TEST-010's. Pre-existing, untouched by this scope, recorded as a
  follow-up rather than fixed here.
