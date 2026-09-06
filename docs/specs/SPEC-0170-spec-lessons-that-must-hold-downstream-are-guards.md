---
id: spec-lessons-that-must-hold-downstream-are-guards
type: spec
number: 170
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0177-lessons-that-must-hold-downstream-are-guards.md
  rfc: null
  pr: []
  commits: []
---

# Spec — a lesson that must hold downstream is a guard, not a note

SPEC-FROZEN: true

## Links
- Requirement: `docs/issues/CHANGE-0177-lessons-that-must-hold-downstream-are-guards.md`
- Owner decision: `hitl_decision` `lessons-that-must-hold-downstream-are-guards` (2026-09-06), which also swapped this ride into wave 1 pair 2's maintenance half and moved `canon-one-line-report-and-downstream-rules` to wave 2
- Surfaces changed: `.aai/AGENTS.md` (vendored), `docs/knowledge/LEARNED.md` (+ its header), `.aai/scripts/aai-release.sh`, `.aai/SKILL_PR.prompt.md`, NEW `.aai/scripts/check-committed-scope.mjs`
- Reused, not reimplemented: `learned-append.mjs`'s pure-append gate (untouched — AC-004 is a deliberate corpus edit and is reviewed as one), `aai-release.sh`'s existing `## Preconditions` reporting style
- Technology contract: `docs/TECHNOLOGY.md` (Node stdlib only, zero deps, bash 3.2 suites)

Registry items: at the base commit (`9296160c`) the ledger held 127 open items, and NONE of them named the release-notes gap, the committed-blob check or the LEARNED routing rule. `fu-release-notes-miss-unlogged-prs` (P2) is opened AND discharged inside this scope — it is a defect this ride found, not a pre-existing item it inherited, and the earlier wording that presented it as one was wrong (validation, 2026-09-06). Spec-AC-02 discharges it. Review of this ride opened six further items rather than parking their lessons as notes: `fu-sweep-dies-at-wrapper-default`, `fu-triage-undated-learned-log`, `fu-learned-positive-control-for-absence`, `fu-learned-immutable-pin-lint`, `fu-learned-deny-by-default-mocks`, and the amendment sign-off item.

## The measurement this scope rests on
`docs/knowledge/LEARNED.md` carries **15** entries. The entry of 2026-07-03 says
a pre-commit content check must read the STAGED blob, never the worktree. On
2026-09-06 the author broke exactly that twice (PR #346, PR #347): `git add`
took a path the allocator had renamed, the add aborted, and the commit looked
whole because the allocator stages the rename and the hook stages `INDEX.md`.
**7 of the 15** entries name a vendored script, prompt or suite — the population
this scope triages.

## Design decisions
- **D1 — the routing rule is canon, not advice.** `.aai/AGENTS.md` gains rule 5
  of the Operator contract, so it vendors downstream with `/aai-update`. A rule
  that lives only here would repeat the very mistake it describes.
- **D2 — the release check NAMES, it does not block.** `aai-release.sh` already
  reports `## Preconditions`; an unlogged PR joins that list. A release has one
  shot and a false positive (a PR whose section was merged under another title)
  must not stop a legitimate cut. The dry run shows it before `--confirm`.
- **D3 — the committed-scope check compares BLOBS, not status.** For every
  in-scope path, `git show :<path>` must equal the worktree. `git status` says
  "modified" for both a legitimate later edit and a lost stamp; only the blob
  comparison separates them. It runs in SKILL_PR before the push.
- **D4 — nothing is deleted from LEARNED.md.** Each entry gains a `[local]` or
  `[guard → …]` marker in place, the pointer being an open follow-up or an
  already-shipped guard. Removing a lesson because its enforcement
  moved is how the lesson is lost; the marker points at the guard instead.
- **D5 — the triage is a reviewed edit, not an append.** `learned-append.mjs`
  accepts only a byte-exact pure append and is NOT modified; AC-004 edits the
  corpus directly and says so, so the gate's contract stays true.

## Implementation strategy
- Strategy: tdd
- Rationale: both new checks are refusals over shapes that already occurred in
  this repository's history, so each has a real failing input to write first;
  and a check that cannot fail is exactly what this ride exists to stop.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | `.aai/AGENTS.md` Operator contract carries a fifth rule stating that a lesson which must hold wherever AAI is installed is implemented as a guard in the vendored layer, and that `LEARNED.md` records only what is local to this repository and its environment; the contract stays within its stated line budget | done | TEST-001 green; rule 5 at .aai/AGENTS.md:315-321, both halves present; Operator contract measured at 30 lines against the ≤40 budget already enforced by test-aai-ride-select.sh:212; preamble corrected to bind rule 5 (validation D6) [validation + code review 2026-09-06] | 2026-09-06 | D1; vendored downstream |
| Spec-AC-02 | `aai-release.sh --dry-run` lists, under `## Preconditions`, every PR merged since the previous tag that has no matching rolled-up section; a cut where every merged PR is accounted for produces the same output as today, byte for byte | done | TEST-002 green, both arms mutation-proved RED; validation diffed the all-logged dry run against `git show HEAD:.aai/scripts/aai-release.sh` — byte identical. Remediation: `grep -qF --` (a subject starting with a dash reached grep as an option), an or-true guard on the call (a failing pipeline would otherwise have aborted the cut silently under set -euo pipefail — the named HAZ), the precondition now runs on the real `--confirm` cut too, and `none — ready to cut` is no longer printed under a list of named PRs [code review F9-F12 + validation D3] | 2026-09-06 | D2; both arms, and it NAMES rather than blocks |
| Spec-AC-03 | `check-committed-scope.mjs` exits non-zero and names each in-scope path whose `git show :<path>` differs from the worktree; it exits 0 when they match, and 0 with a named degrade when a path is untracked or the repo is unreadable | done | TEST-003 and TEST-004 green and mutation-proved RED. Remediation: comparison handed to `git diff --quiet` instead of a hand-rolled byte compare of `git show`. Verified in a fixture repo that an untouched file under core.autocrlf=true, a tracked symlink and a 3 MB blob now all read clean, while a real 3 MB change still exits 1 — the old code STOPPED every PR on Windows, always mismatched a symlink, and reported an over-1-MiB blob as untracked and PASSED it [code review F2, F3, F14] Round two: a directory in scope holding a file that was never added compared clean, because git diff is blind to untracked files — the drop shape the guard exists to catch; `git ls-files --others` now names each one. A `--rev` that does not resolve is a usage error (exit 2), not a degrade that passes every path. | 2026-09-06 | D3; the exact 2026-09-06 shape is the fixture |
| Spec-AC-04 | `.aai/SKILL_PR.prompt.md` invokes that check before the push and STOPS on non-zero, quoting its message | done | TEST-005 green and mutation-proved RED. Remediation: the step was physically placed before `2. STAGE` while its own text said after committing; moved to 4a between COMMIT (line 124) and CLOSE BEFORE PUSH (line 145), and given --strict. TEST-005 now asserts commit < check < push and scopes the STOP grep to the step's own block — the earlier version compared against the LAST push mention and was true for any placement in the first 236 lines [code review F1 (blocking) + validation D2, D5] Round two: the step is titled VERIFY THE COMMITTED BLOB but the default comparison reads the INDEX, so a path staged after the commit and never committed read clean; the invocation gained `--rev HEAD` and TEST-005 now proves the two readings differ on that exact state. | 2026-09-06 | D3 wiring |
| Spec-AC-05 | Every one of the 15 `LEARNED.md` entries carries exactly one `[local]` or `[guard → …]` marker; a guard pointer names EITHER an open follow-up id OR a script that already exists in the vendored layer (Amendment 1); no entry text is removed (the pre-edit entry bodies are a byte-exact subset of the post-edit file) | done | TEST-006 green. Remediation: the no-deletion half is now ASSERTED, not promised — the pre-edit bodies are read from the immutable pin 9296160c and each must still occur verbatim, plus a floor on the entry count. Probe: deleting the 2026-08-07 entry used to PASS, now fails with `an entry was deleted`. Four entries mis-marked [local] while stating general engineering lessons were re-triaged to guards with follow-ups filed [validation D1, D10 + code review F5] | 2026-09-06 | D4; the no-deletion half is asserted, not promised |
| Spec-AC-06 | `LEARNED.md`'s header states the routing rule; `learned-append.mjs` is unmodified and its suite stays green | done | TEST-007 green; learned-append.mjs untouched (absent from git status) and its suite exits 0. Remediation: the header claimed every entry carries a marker while ~20 undated session-log entries carry none; it now names the dated entries explicitly and points at fu-triage-undated-learned-log [code review F4] | 2026-09-06 | D5; the append gate's contract is untouched |
| Spec-AC-07 | Companion obligations (closed list): `PROFILES.yaml` entry for the new script, `suite-map.yaml` row, prompt-diet credit equal to the MEASURED growth of `.aai/SKILL_PR.prompt.md` and `.aai/AGENTS.md` with a matching TEST-012 bump, layer-profiles green | done | PROFILES.yaml:121 core entry; suite-map row widened to AGENTS.md, SKILL_PR.prompt.md and aai-release.sh — TEST-001/002/005 assert on all three and editing them previously did not select this suite (verified: select-suites.mjs now returns SELECTED aai-learned-routing). Prompt growth RE-MEASURED after remediation: SKILL_PR 27121→28092 = +971, AGENTS 21987→22568 = +581, sum 1552; credit and pin moved 1053→1552 and 16854→17353. layer-profiles green [code review F13; bytes measured, never copied] Re-measured again after round two: SKILL_PR 27121→28320 = +1199, AGENTS +581, sum 1780; credit and pin 1552→1780 and 17353→17581. | 2026-09-06 | bytes measured by Implementation, never copied from here |
| Spec-AC-08 | The local dashboard reports the test sweep: it reads the run directory the framework already writes under `tests/skills/results/`, states how many suites have STARTED (one `<suite>.log` each) and how many are DONE (one `<suite>.result` each) and how many failed, names the newest finished one and its age, marks a run active while the newest thing it produced — a result, or the run directory itself before any suite finishes — is inside the stale window, and reports an old run as finished rather than hiding it; with no results directory it says so instead of inventing a run, and it never publishes an expected total, because nothing on disk states one (Amendment 2) | done | TEST-009 (TEST-012 in test-aai-live-serve.sh) green; 12/12 mutations caught. Two defects found by pointing the panel at a REAL sweep: a 40-second-old run read inactive, and the panel could say only `0 done` while eight .log markers sat on disk. Remediation after review: run discovery filters to directories and NAMES a stray `test-…` file in `degraded` (a single stray file used to blank the panel silently), and a finished run is read from summary.txt's Total line rather than waiting out the 300 s stale window [code review F8, F15 + validation D7] Round two: every sweep read is now bounded to a regular file under a 1 MiB cap — a FIFO or a symlink to /dev/zero used to wedge the request thread forever, and this read runs inside every /data.json request; and a run still in flight outranks a finished one, so a one-suite selected run finishing mid-sweep no longer reports `finished` over a sweep that is still going. The completion arm of TEST-009 was itself vacuous (the fixture was already an hour old, so `active:false` held for the age alone) and was mutation-proved after the fix. | 2026-09-06 | owner-authorized addition; a read of existing artefacts, no new plumbing |

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                          | Description | Status |
|----------|------------|------|-----------------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | int  | tests/skills/test-aai-learned-routing.sh | AGENTS carries the fifth rule, names both halves (guard in the layer / local in LEARNED), and the contract is within budget | pending |
| TEST-002 | Spec-AC-02 | int  | tests/skills/test-aai-learned-routing.sh | fixture repo with two merged PRs since a tag, one without a section: dry run names exactly that one; with both logged, the Preconditions block is unchanged | pending |
| TEST-003 | Spec-AC-03 | int  | tests/skills/test-aai-learned-routing.sh | the 2026-09-06 shape — allocator renames, `git add` takes the old path, a frontmatter stamp stays uncommitted: the check names that path and exits non-zero | pending |
| TEST-004 | Spec-AC-03 | int  | tests/skills/test-aai-learned-routing.sh | matching blobs exit 0; an untracked in-scope path and an unreadable repo each exit 0 with a NAMED degrade, never a silent pass | pending |
| TEST-005 | Spec-AC-04 | unit | tests/skills/test-aai-learned-routing.sh | SKILL_PR names `check-committed-scope.mjs` before its push step and states the STOP | pending |
| TEST-006 | Spec-AC-05 | int  | tests/skills/test-aai-learned-routing.sh | every entry has exactly one marker; every `guard →` id resolves to an OPEN follow-up; the pre-edit bodies all still occur in the file | pending |
| TEST-007 | Spec-AC-06 | int  | tests/skills/test-aai-learned-append.sh | the header carries the routing rule and the existing append gate is unchanged and green | pending |
| TEST-008 | Spec-AC-07 | int  | tests/skills/test-aai-prompt-diet.sh | credit equals measured growth; pin bumped; layer-profiles green | pending |
| TEST-009 | Spec-AC-08 | int  | tests/skills/test-aai-live-serve.sh | six started and four done with exactly one failed (a SKIP and a log mentioning failure are not failures) and the run named and active; a just-started run with no result yet is active with done=0; an hour-old run reads inactive yet is still reported; a missing results directory yields null; no total is invented | pending |

## Implementation plan
- **NEW** `.aai/scripts/check-committed-scope.mjs` — reads a scope list (argv or `--from-state`), compares `git show :<path>` to the worktree, names every mismatch, degrades named on untracked/unreadable.
- **NEW** `tests/skills/test-aai-learned-routing.sh`.
- **EDIT** `.aai/AGENTS.md` (rule 5), `docs/knowledge/LEARNED.md` (header + 15 markers), `.aai/scripts/aai-release.sh` (precondition), `.aai/SKILL_PR.prompt.md` (invoke before push), `PROFILES.yaml`, `suite-map.yaml`, prompt-diet ledger + pin.

## Constraints / Risks
- **HAZ**: `aai-release.sh` runs once per release. The new precondition must be
  reportable and never abort a legitimate cut (D2), and the dry run must show it.
- `LEARNED.md` is edited in place; `learned-append.mjs` stays untouched so its
  pure-append contract remains true for every future append.
- The committed-scope check must not be fooled by CRLF or by a file whose only
  difference is a trailing newline; compare bytes.

## Amendment 1 (unsigned, 2026-09-06) — a guard marker may point at a guard that exists

AC-005 as frozen required every `guard` marker to name a follow-up id. One entry
— the 2026-07-03 staged-blob rule, the very lesson that motivated this ride — is
enforced by `check-committed-scope.mjs`, which THIS scope ships. Pointing it at a
follow-up would mean opening an item for work already done, purely to satisfy the
marker's grammar.

The vocabulary therefore admits both: `[guard → fu-…]` for enforcement still
owed, `[guard → <script>]` for enforcement that exists. The test asserts each
kind against reality — a follow-up id must be OPEN, a script must be present in
`.aai/scripts/` — so neither pointer can be a dead end.

This amendment is NOT owner-authorized. It is recorded in `docs/ai/decisions.jsonl`
with `owner_signoff: false` and carries an open tracked item.

## Amendment 2 (owner-authorized, 2026-09-06) — the dashboard can see the sweep

Three times in one session the operator asked whether anything was running, and
three times the honest answer needed `pgrep`. The page lists heartbeat slots and
the test runner writes none, so the longest job in the factory — a ~30 minute
sweep — was the one thing the dashboard could not see. Asked whether to file this
separately or fold it in, the owner chose to fold it into this ride: it belongs
to the same lesson, that something which must behave correctly wherever AAI is
installed is fixed in the vendored layer rather than noted.

Scope added: `readSweep()` in `.aai/scripts/aai-live-serve.mjs` plus its panel,
a `--results-dir` test seam alongside the existing `--state` / `--answers` /
`--heartbeat-dir` seams, and TEST-009 above.

Two defects were found by pointing the finished panel at a REAL sweep rather
than only at its fixture, and both are covered by TEST-009: a run 40 seconds old
reported `active: false`, because liveness was dated from the newest `.result`
and a sweep that has just started has none; and the panel read `0 suites done`
with nothing else to say, when the run directory already held eight `<suite>.log`
markers. Started-minus-done is the number in flight, and it is measured.

Deliberately NOT added: an expected suite total. Nothing on disk publishes how
many suites a run intends to execute, so a percentage would be invented. The
page reports the count done and lets the reader judge.

Owner sign-off recorded in `docs/ai/decisions.jsonl` with `owner_signoff: true`.

## Review rounds

Two rounds, which is the cap the owner set on 2026-09-05 (`review-round-cap`).
Round one returned 15 findings, one blocking. Round two verified the
remediation and returned 10 more, of which the sharpest was mine: the arm I had
just written to prove a finished run stops reading as running was VACUOUS — the
fixture was already an hour old, so the assertion held for the age alone and
dropping the new condition from the engine left the test green. It is now
mutation-proved, along with three sibling arms.

No third round was run. Under the cap a third finding-bearing round means the
scope was cut wrong and the ride should split — so the round-two fixes were
verified by mutation battery (16 mutations across the two suites, all caught)
and by the full sweep, not by asking a third reviewer to bless them.
