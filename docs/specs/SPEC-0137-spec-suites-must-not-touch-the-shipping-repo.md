---
id: spec-suites-must-not-touch-the-shipping-repo
type: spec
number: 137
status: done
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0151-suites-must-not-touch-the-shipping-repo.md
  rfc: null
  pr:
    - 266
  commits:
    - 0067ffb3e1a30f369bf517ff8e1f78b41fc070a3
---

# Spec — a suite must not be able to write to the shipping repository

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0151-suites-must-not-touch-the-shipping-repo.md
- Funnel that CI runs (load-bearing): tests/skills/test-framework.sh
- Funnel roles invoke ad hoc: .aai/scripts/aai-run-tests.sh
- Shared tripwire library (new): .aai/scripts/lib/repo-tripwire.sh
- Suite that gates this scope (new): tests/skills/test-aai-repo-tripwire.sh
- Offending suites: tests/skills/test-aai-doc-numbering.sh, tests/skills/test-aai-deslop.sh, tests/skills/test-aai-spec-lint.sh
- Registry items closed: `fu-subagent-probe-hits-real-repo` (P1), `fu-docnumbering-t013-writes-real-tree` (P2), `fu-deslop-test014-no-restore-trap` (P3), and from the post-validation landability pass `fu-tripwire-unavailable-not-red` (P2), `fu-tripwire-unarmed-pass-line-unlabelled` (P3), `fu-tripwire-d7-not-in-library-header` (P3)
- Registry items the ratchet holds open, each named by the allowlist entry that
  covers it: `fu-hitl-propagation-writes-real-index`,
  `fu-state-suite-writes-real-index`, `fu-metrics-suite-writes-real-overview`,
  `fu-token-capture-writes-overview` (all P2)
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1. One new shell library of under 120 lines, two
call sites, and three test-suite edits of the same mechanical shape. No product
surface, no schema, no `protected_paths_l3` path, and the whole deliverable is
gated by one new suite whose every arm is a directly executable command. The
intake already fixed the acceptance criteria, so Planning froze them rather than
re-opening the design.

## Summary

Three registry items share one cause: a test or a probe runs a generator or a
git command against `PROJECT_ROOT` instead of a fixture, and nothing notices.
The worst instance is P1: a validator probe helper `cd`-ed into a fixture inside
a command substitution, which runs in a subshell, so the parent shell stayed in
the real repository and two commits landed on `main`.

Four things were measured on the pre-change tree during this ride. Two of them
contradict what the intake assumed, and both change the shipped design.

1. **CI enters through `tests/skills/test-framework.sh`, not through
   `.aai/scripts/aai-run-tests.sh`.** The framework invokes each suite with a
   bare `bash "$test_file"`. A tripwire placed only in the wrapper would miss
   every CI run, so the framework is where the tripwire fails a run.

2. **The framework's own run artifacts sit inside the repository, between the
   two snapshots.** `run_test` writes each suite's log into
   `tests/skills/results/<run-id>/` before the second snapshot is taken. That
   directory is git-ignored, which is the only reason a status comparison
   around a suite means anything at all. The dependency is invisible in the
   code, so it is asserted (Spec-AC-05 / TEST-005) rather than assumed.

3. **`docs/ai/tests/test-runs.jsonl` is tracked AND listed in `.gitignore`.**
   `.gitignore` has no effect on an already-tracked file, so the framework's
   own end-of-run metrics append dirties the working tree on every single run.
   It happens after the per-suite loop, so no suite is blamed for it — but it
   means the canonical whole-suite invocation
   `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh`
   would go red on every run if the wrapper turned dirt into an exit code.
   This is why D2 makes the wrapper report-only. Filed, not fixed here, as
   `fu-test-runs-jsonl-tracked-ignored`.

4. **The blast radius is three suites, not two.** Suites were run in throwaway
   copies of this repository with a `git rev-parse HEAD` plus
   `git status --porcelain=v1` comparison around each: 34 suites in one census
   and the 15 that invoke a generator in a second. Beyond the two suites
   the intake names, `tests/skills/test-aai-spec-lint.sh` TEST-011 regenerates
   `docs/INDEX.md` in `PROJECT_ROOT`, and `tests/skills/test-aai-delta-stage2.sh`
   TEST-006 inherits the same write by invoking the spec-lint suite. Both were
   caught by the tripwire itself, not by reading. Leaving spec-lint unfixed would
   have made this repository's own CI permanently red the day the tripwire
   landed, so the same mirror fix is applied there; the delta-stage2 symptom
   disappears with it.

   Measured on a CLEAN pre-change tree, one suite at a time: `test-aai-doc-numbering`
   DIRTY with `M docs/INDEX.md`, `test-aai-spec-lint` DIRTY with `M docs/INDEX.md`,
   `test-aai-deslop` clean. Measured on the post-change tree, same method:
   `test-aai-doc-numbering` clean, `test-aai-deslop` clean, and the twelve other
   generator-invoking suites clean.

   The post-change full framework run then found TWO MORE, and both censuses
   had missed them for the reason D7 records: `tests/skills/test-aai-hitl-propagation.sh`
   rewrites `docs/INDEX.md` and `tests/skills/test-aai-metrics.sh` rewrites
   `docs/ai/overview.html` and `docs/ai/overview-data.json`. Neither is fixed
   here and neither can be: the write does not come from a generator call the
   test owns, it comes from a production script (`metrics-flush.mjs`,
   `orchestration-dispatch.mjs`) invoked with `cd "$PROJECT_ROOT"` against a
   fixture STATE path, which regenerates the real pages as a side effect. The
   remedy is a change to those scripts or to their invocation contract, which is
   production code and a different scope. Filed as
   `fu-hitl-propagation-writes-real-index` and
   `fu-metrics-suite-writes-real-overview`, both P2. They are the tripwire
   working exactly as specified: two defects that had been invisible for as long
   as they have existed are now named, with the paths they touched, on the first
   run after it landed.

   The same census also corrected one assumption in the other direction:
   `tests/skills/test-aai-deslop.sh` was already net-clean on its happy path,
   because TEST-014 copied the two tracked artifacts back at the end. Its defect
   (`fu-deslop-test014-no-restore-trap`) is that the restore is not in a trap, so
   a crash, a watchdog kill or an early return between the generator and the two
   `cp` lines leaves the repository dirty. The fix removes the write, so there is
   nothing left to restore.

## Design decisions

- **D1 — one library, armed at both funnels.** `.aai/scripts/lib/repo-tripwire.sh`
  is POSIX sh so the bash framework and the `/bin/sh` wrapper can both source it,
  and exposes three functions: `aai_tripwire_snapshot` (one snapshot: a
  `HEAD <sha>` line plus verbatim `git status --porcelain=v1`),
  `aai_tripwire_state` (`clean` / `dirty` / `unavailable`) and
  `aai_tripwire_report` (the named difference). Two more were added by the
  landability pass, each because a caller had to make a decision the verdict
  alone cannot support: `aai_tripwire_usable` (was this snapshot taken at all —
  D9) and `aai_tripwire_changed_paths` (which paths moved — D8). Code review
  added two more for the same reason: `aai_tripwire_hash_snapshot` and
  `aai_tripwire_hash_changed` (did the CONTENT of a named, bounded path set move
  — the D7 escape hatch the ratchet needs, plus `aai_tripwire_hash_usable` so a
  machine with no digest tool degrades with a note rather than silently). It lives under `.aai/` rather
  than `tests/` because `.aai/scripts/aai-run-tests.sh` is vendored into
  downstream projects that have no `tests/skills/` tree.

  The comparison is HEAD plus porcelain status, exactly as the intake specifies.
  Both halves are load-bearing and neither subsumes the other: a suite that
  commits leaves `git status` clean and is caught only by HEAD, and a suite that
  modifies a tracked file leaves HEAD alone and is caught only by status.
  Untracked files count, because a stray untracked file in the checkout is a
  write the next reader has to explain.

  The tripwire must not be a write itself: every git call uses
  `--no-optional-locks`, so arming it cannot refresh and rewrite `.git/index`.

- **D2 — the framework fails the run; the wrapper reports.** In
  `tests/skills/test-framework.sh` a dirty verdict overrides the suite's own
  exit code: the suite is counted FAILED, its `.result` reads FAIL, the run
  exits 1, and the violation block names the suite and every changed path.
  In `.aai/scripts/aai-run-tests.sh` the same violation is printed on stderr and
  the exit code is left exactly as it was.

  The asymmetry is a measurement, not a preference. The wrapper's exit code is a
  pinned contract (124 for the watchdog, the command's real status otherwise,
  125 reserved for the PowerShell dispatcher), and fact 3 above means the single
  most common invocation legitimately dirties a tracked file every time. A
  wrapper that went red there would be a check that always fires, which is worth
  no more than one that never does. The framework carries the teeth because the
  framework is what CI runs.

  Alternatives considered and rejected: making the wrapper exit non-zero (it
  breaks the canonical whole-suite invocation and re-opens a pinned exit-code
  contract); an OPEN allowlist of paths any suite may dirty (a curated-exemption
  mechanism that would let a future suite exempt itself); and snapshotting
  once around the whole framework run instead of per suite (it cannot name the
  offending suite, which is half of what the intake asks for).

  The open allowlist stayed rejected. What replaced it is D8, a closed and
  seeded one: four named suites, each bound to a filed registry item and to the
  exact paths it already dirties, which cannot grow without a filed reason and
  cannot cover a path or a suite it does not name.

- **D3 — `clean` never means `verified`.** A skipped or crashed suite touches
  nothing and is therefore trivially clean, which is precisely the reading that
  must not be available. The framework separates the tree verdict from the run
  verdict and reports a suite as ATTESTED only when it exited 0 AND the tree did
  not move. A suite that exited 42 is reported `tripwire NOT ATTESTED — suite
  skipped (exit 42), it never ran`; a suite that exited N is reported
  `tripwire NOT ATTESTED — suite exited N before completing`; a snapshot that
  could not be taken is reported `tripwire NOT ARMED`. The aggregate prints
  `attested clean` and `not attested` counts, and `metrics.jsonl` carries
  `tripwire` and `tripwire_attested` per suite. The exit-42-is-SKIP contract
  itself is untouched. The wrapper applies the same honesty rule in its own
  shape: silence means armed-and-clean, and an unarmed tripwire says so.

- **D4 — the offenders stop writing; they do not write-and-restore.**
  `generate-docs-index.mjs` and `generate-docs-hub.mjs` both take their root
  from `process.cwd()`. Each offending arm therefore runs the REAL generator
  over a MIRROR of its real inputs and asserts against the mirror's output:
  - `tests/skills/test-aai-doc-numbering.sh` TEST-013 copies `docs/` and runs
    the index generator there twice. Byte-idempotence is a property of two runs
    over one corpus; it never needed the corpus to be the live checkout. The
    `docs-audit --check --strict --no-event` half stays on the real tree because
    it was measured read-only.
  - `tests/skills/test-aai-deslop.sh` TEST-014 copies `.claude/` and
    `.aai/SKILL_*.prompt.md` (the generator's only inputs) and compares the
    mirror's freshly generated bytes against the COMMITTED artifacts. That is
    exactly what "the committed content matches the generator's output" means,
    so the drift check is unchanged in substance and the backup-and-restore
    dance disappears.
  - `tests/skills/test-aai-spec-lint.sh` TEST-011 gets the same `docs/` mirror
    as TEST-013.
  Restoring afterwards was rejected: it leaves a window in which a crash, a
  watchdog kill or an early return strands the repository dirty, which is the
  filed defect, and it would also hide the write from a tripwire that only
  compares endpoints.

- **D5 — the fixture that proves the bite cannot live in `tests/skills/`.**
  A permanently-dirty suite discovered by `find -name "test-aai-*.sh"` would
  turn every real run red. TEST-001 to TEST-004 therefore build a throwaway git
  repository containing a BYTE COPY of `tests/skills/test-framework.sh` and of
  the tripwire library, write the dirty, committing, skipping, crashing and
  clean fixture suites into its `tests/skills/`, and run the real framework
  there with no arguments — the same discovery-and-aggregate path CI takes. The
  fixtures can then commit to `main` and rewrite tracked files, which is what
  cannot be rehearsed against the real checkout at any price. Spec-AC-03's arm
  is the one that uses the live repository, and its entire assertion is that
  nothing changed.

- **D7 — the one thing this tripwire cannot see, stated rather than implied.**
  `git status --porcelain=v1` reports the change CLASS of a path, not its
  content. If a path is ALREADY dirty when a suite starts, a further change by
  that suite to the same path leaves the porcelain output byte-identical and the
  tripwire reads clean. This is not a hypothetical: it is why the pre-change
  census recorded `test-aai-doc-numbering` as clean on a tree where an earlier
  suite had already modified `docs/INDEX.md`, and why a fixture that dirties the
  same path twice cannot be used to prove the wrapper arm (TEST-007 carries that
  reasoning at the fixture).

  It is accepted for the tree at large, and CLOSED for the paths the ratchet
  names. The bound this spec first shipped — "on a CLEAN checkout the FIRST
  write to any path is always caught, so only second and later writes to an
  already-dirty path are missed" — was FALSE as written, and code review
  falsified it by measurement. It is true only of the first suite in a run. A
  framework run observes a SEQUENCE of suites against one checkout, so the run
  manufactures its own dirt: once any suite has dirtied a path, every later
  suite writing that same path leaves the porcelain output byte-identical, on a
  clean checkout exactly as much as on a dirty one. The ratchet made that the
  normal case rather than an edge one — its whole purpose is to let four listed
  suites dirty `docs/INDEX.md` and the two overview files early in every run.
  Measured on a clean throwaway repository carrying a byte copy of the
  framework: allowlisted `aai-hitl-propagation` wrote `docs/INDEX.md` and was
  reported ALLOWED, then an UNLISTED suite appended to the same file and got a
  bare `PASS`, a place in the attested-clean count and framework exit 0, with
  the write landed. Repeated with the real suites in CI's `--skill` form on a
  clean copy of this repository: `aai-state` and `aai-token-capture` both read
  clean while writing, and both had their live ratchet entries reported STALE by
  the drain report D8 has since deleted.

  So the honest statement of the limit is per PATH and per RUN, not per suite:
  the first observed write to a path is caught and no later one is. The fix does
  not annotate that — it removes it where it can bite. Every path any ratchet
  entry names is CONTENT-HASHED around every suite, listed or not
  (`aai_tripwire_hash_snapshot` / `aai_tripwire_hash_changed`), so a content
  change to one of those paths is a dirty verdict even when its status class did
  not move. Three paths, one read each per side per suite, and NO extra `git`
  call — Spec-AC-05's one-status-pair budget is untouched and TEST-004 still
  measures six calls over three suites. A whole-tree hash is still rejected for
  the reason given above; what is rejected with it is the idea that the
  exemption mechanism may manufacture the blind spot it is exempted under.
  Outside that named set the class-only bound stands, and
  `fu-tripwire-porcelain-class-not-content` stays open for it. The registry
  item's own `decision` line carries the superseded "on a clean checkout the
  FIRST write is always caught" wording; the ledger is append-only, so it is
  corrected here rather than rewritten there.

  A second, related property, stated because it bit during this ride's own
  verification: the tripwire attributes ANY repository change that happens
  during a suite to that suite, including one made by a human or another
  process in the same checkout. Running `spec-freeze.mjs` in a second terminal
  while `tests/skills/test-framework.sh` was mid-run appended to
  `docs/ai/EVENTS.jsonl` and would have failed whichever suite happened to be
  executing. Nothing short of running the suites in an isolated checkout can
  distinguish the two, which is a cost the tripwire cannot pay per suite. CI
  runs on a checkout nobody else is touching, so the exposure is local only,
  and the report always names the path — `docs/ai/EVENTS.jsonl` in that
  instance — which is what lets a reader tell a concurrent edit from a suite's
  own write.

- **D8 — the guard lands as a ratchet, because the tree it lands on already has
  four writers.** A complete clean-tree census taken during validation found
  four live writers to the shipping repository, not the two the census in the
  Summary names: `test-aai-hitl-propagation` and `test-aai-state` both rewrite
  `docs/INDEX.md`, and `test-aai-metrics` and `test-aai-token-capture` both
  rewrite `docs/ai/overview.html` and `docs/ai/overview-data.json`. The last two
  had been invisible for exactly the reason D7 records: they write the paths
  the earlier suites had already dirtied. Fixing them is production-script work
  and out of this scope; shipping a guard that turns CI red on a clean tree
  until all four are fixed is not landable.

  So `tests/skills/test-framework.sh` carries a seeded known-offender list, and
  the shape of that list is the whole design:
  - an entry names the suite AND the registry item that owes its fix
    (`fu-hitl-propagation-writes-real-index`, `fu-state-suite-writes-real-index`,
    `fu-metrics-suite-writes-real-overview`, `fu-token-capture-writes-overview`),
    so a suite cannot be exempted without a filed reason someone has to close;
  - an entry names the exact PATHS it covers. An allowlisted suite that dirties
    anything else still fails the run, and so does one that moves HEAD. An
    entry is not permission for the suite that holds it;
  - a suite that is not on the list fails exactly as before — Spec-AC-01 is
    unchanged, and TEST-008(c) asserts it in the same run as the ratchet arms;
  - an allowlisted write is reported as a WARNING block naming the suite, the
    registry item and every path it moved, counted on its own aggregate line,
    and never folded into the attested-clean count.

  The list is drained BY HAND. An earlier form of this decision had the run
  print a STALE line for any entry whose suite "changed nothing in this run",
  so the list would drain rather than rot. Code review falsified it: the line
  keyed on the tripwire verdict alone and never consulted whether the suite was
  ATTESTED, and a suite that skips (exit 42) or crashes touches nothing and is
  therefore trivially clean. Measured on the shipped table with two
  ratchet-named suites, one exiting 42 and one exiting 3: the run printed
  `NOT ATTESTED ... it never ran` for both and four lines later told the
  operator to delete both live entries and close both P2 registry items. The
  same line also asserted the verdict was a CONTENT one, which is false by
  construction whenever the no-hasher degrade is in force. Draining is a
  convenience, not part of the guard — it is not load-bearing for D1 or for
  Spec-AC-06 — so it was DELETED rather than conditioned. A feature that can
  tell an operator to close a real defect as fixed is worth less than nothing.
  The whole ratchet is transitional in any case (see the 2026-08-19
  `hitl_decision` in `docs/ai/decisions.jsonl`): once suites run in a disposable
  worktree, the tripwire, the ratchet and the hashing all go.

  **CORRECTION (2026-08-23).** The three lines above are WRONG and are left
  standing so the record shows what was believed, not a tidied version of it.
  The tripwire, the ratchet and the hashing do NOT all go, and their removal is
  not scheduled. The successor named there — one disposable worktree per suite —
  LANDED as SPEC-0138, and it does not remove the cause. Measured on `main` at
  `07e6d81` and re-taken by hand: inside a disposable worktree,
  `git rev-parse --git-common-dir` returns the SHIPPING repository's `.git`, and
  its `dirname` is the shipping working tree. Isolation relocates a suite's cwd
  and script path; it does not remove the suite's reach, and any absolute path a
  suite already holds still resolves. A suite that writes through that path
  dirties the shipping repository while the run correctly reports `isolated` —
  `degraded` cannot fire, because nothing degraded
  (`fu-isolated-suite-reaches-shipping-repo`, P1, open). The retirement scope
  measured the counterfactual: with the tripwire deleted and the proposed
  degraded-gate in place, a run exits 0 at `Passed: 2 (100%) / 0 degraded` with
  the write landed. The 2026-08-19 decision is therefore SUPERSEDED by the
  `hitl_decision` appended at **2026-08-23T20:05:00Z** in the same append-only
  ledger (owner-approved in the 2026-08-23 session, on that measurement); read
  both, and the later one wins. That entry also names the three measurable
  conditions that would reopen the deletion question. Spec:
  `spec-the-tripwire-is-permanent-not-transitional`.

  KNOWN LIMIT, stated not enforced: the entry path-subset test compares the
  paths a suite MOVED against the paths its entry names, and a path that was
  already dirty when the suite started does not move. So an allowlisted suite
  that writes both a listed path and an already-dirty NON-ratchet path reads
  `PASS [tripwire ALLOWED ... inside its listed path(s)]` at exit 0, with the
  out-of-entry write landed. Reproduced with a pre-existing `M docs/other.md`.
  It is bounded rather than closed because on a clean start the only way a
  non-ratchet path becomes pre-dirty is an earlier suite that already failed the
  run: it degrades a RED run's offender list, it cannot turn CI green. Ratchet
  paths are exempt from this — they are content-hashed. The framework holds
  `tw_before` and could name the already-dirty set per suite; that is
  `fu-tripwire-allowed-ignores-pre-dirty` (P2) — validation suggested
  `fu-tripwire-attested-clean-ignores-pre-dirty-paths`, which is 10 characters
  over the ledger's 40-char id limit — left open and mooted by the
  disposable-worktree successor above.

  **CORRECTION (2026-08-23).** "Mooted by the disposable-worktree successor" is
  withdrawn. The successor landed and does not moot it:
  `fu-tripwire-allowed-ignores-pre-dirty` (P2) is a live defect in a layer that
  now stays. It is one of FIFTEEN open tripwire defects that this correction does
  NOT fix and that no longer have "it is about to be deleted" as an excuse. See
  the `hitl_decision` at 2026-08-23T20:05:00Z in `docs/ai/decisions.jsonl`.

  Every path any entry names is CONTENT-HASHED around every suite, listed or
  not. This is not an optimisation, it is what makes the rules above true:
  without it the ratchet's own first write masks every later write to the same
  path (D7), so "a suite that is not on the list still fails" and "an
  allowlisted write is never folded into the attested-clean count" both stop
  holding from the second suite onward — measured, not feared, see D7. The
  hashed set is derived from the table itself,
  so it cannot drift from what the ratchet dirties, and it shrinks with the
  table.

  Two ways the table could lie about itself are named at startup rather than
  swallowed: a second entry for a suite the list already names is unreachable
  behind the first-match lookup and is reported DUPLICATE with the entry that
  is dead; and a path field is split under `set -f`, so `docs/*` matches
  literally (it exempts nothing) instead of expanding against the framework's
  working directory, and is reported as such.

  The list only shrinks. It is a table in the framework, not a configuration
  file, precisely so that adding to it is a code change that a reviewer sees.

- **D9 — an unavailable after-snapshot fails closed.** Validation measured the
  hole: a fixture suite that dirtied a tracked file and then removed `.git`
  produced framework exit 0 and a `PASS` line, because the after-snapshot could
  not be taken and `unavailable` was treated as merely not-attested. Any cause
  of a failed after-snapshot (removed `.git`, corrupt index, git off PATH) both
  hides that suite's write and leaves CI green, which is precisely the reading
  Spec-AC-04 exists to forbid.

  The framework now separates the two unavailable cases with
  `aai_tripwire_usable`, which is why the fix is not simply "unavailable fails":
  - the BEFORE snapshot could not be taken either — the tripwire was never
    armed (the framework is running outside a git checkout, which is a real
    downstream case). Degrade with the named `NOT ARMED` note; do not fail;
  - the before snapshot WAS taken and the after snapshot was not — the suite
    took the repository down with it. Fail the run, marked
    `[TRIPWIRE UNAVAILABLE]`.
  Filed as `fu-tripwire-unavailable-not-red`; closed by this change.

- **D10 — the wrapper applies the same split, and is SILENT on the
  never-armable side.** The wrapper shipped with one note for both unavailable
  cases, and CI measured the cost on the functional WSL1 leg: from inside WSL1
  git cannot read the `/mnt/d` checkout, so the state was `unavailable` on every
  Windows invocation and the note was permanent stderr noise there. Worse, that
  stderr write displaced `aai-run-tests.ps1`'s own `AAI-BRANCH: WSL` diagnostic
  across the WSL1 boundary — the routing proof read only the tripwire line and
  the leg went red (measured on PR #266; the same leg was green at `6fce072` on
  `main`, where the wrapper wrote nothing). The exact mechanism on that boundary
  (a non-shared file offset on the inherited stderr handle) is a hypothesis; the
  trigger is not — the note was the only new write and the diagnostic vanished
  with it.

  The wrapper therefore keys on `aai_tripwire_usable` exactly as the framework
  does, and takes the opposite decision on each side: the BEFORE-taken /
  AFTER-missing case is named on stderr, while the never-armable case says
  nothing per run. It is REPORT-ONLY either way — the exit code stays the
  wrapped command's own, so Spec-AC-02 is untouched. The framework funnel, whose
  output is a per-suite report rather than a stream sharing a handle with a
  parent process, still prints `tripwire NOT ARMED`, so the fact is not lost
  where it costs nothing. What is accepted here: on a machine with no usable
  git, the ad hoc funnel watches nothing and does not say so per invocation.

- **D6 — companion obligations (closed two-entry list).** PROMPT CORPUS BYTES
  MOVE: NO — no `.aai/*.prompt.md` and no `.aai/AGENTS.md` byte changes, so no
  prompt-diet ledger true-up is owed. NEW `.aai/**` FILE: YES —
  `.aai/scripts/lib/repo-tripwire.sh` is classified `core` in
  `.aai/system/PROFILES.yaml` (it is part of the test-execution engine, beside
  `.aai/scripts/aai-run-tests.sh`, which is already core).

  Three mechanical obligations outside that list also apply, because suites here
  enforce them: the new suite needs a `tests/skills/suite-map.yaml` row
  (`tests/skills/test-aai-hygiene-pack.sh`); every `test_*` function must be
  wired into `main()` (`.aai/scripts/check-test-registration.mjs`); and
  `tests/skills/test-aai-spec-lint.sh` TEST-011(clarify) holds a branch-diff
  allowlist of `.aai/` paths that this scope's two `.aai/` files must join
  (the standing `fu-test011-branch-diff-allowlist-tax`).

## Implementation strategy
- Strategy: direct
- Rationale: recorded in STATE before this ride began. The behavior is a
  before/after comparison of two git outputs — there is no algorithm to
  discover, no interface to negotiate and no new input shape. What can go wrong
  is entirely in the wiring (a `set -e` caller killed by `diff`'s exit 1, a
  snapshot taken on the wrong side of a write, a fixture that does not actually
  dirty anything), and wiring is proven by running the real funnels, not by a
  RED-first ceremony over a two-line function. Direct does not waive the
  failing-first observation: see the discipline paragraph under the Test Plan.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: five files plus one new library and one new suite. No
  `protected_paths_l3` path is touched. Isolation is offered only because the
  new suite runs two long real-tree suites and a concurrent close in a shared
  tree regenerates `docs/INDEX.md`, which would read as this scope's work.
- User decision: undecided
- Base ref: main
- Inline review scope: .aai/scripts/lib/repo-tripwire.sh,
  .aai/scripts/aai-run-tests.sh, .aai/system/PROFILES.yaml,
  tests/skills/test-framework.sh, tests/skills/test-aai-repo-tripwire.sh,
  tests/skills/test-aai-doc-numbering.sh, tests/skills/test-aai-deslop.sh,
  tests/skills/test-aai-spec-lint.sh, tests/skills/suite-map.yaml,
  docs/specs/SPEC-0137-spec-suites-must-not-touch-the-shipping-repo.md,
  docs/issues/CHANGE-0151-suites-must-not-touch-the-shipping-repo.md

Code review required: true (test-harness and vendored-script changes); scope =
the explicit path list above as a diff against main.

## Acceptance Criteria Mapping

- Maps to: CHANGE AC-001
- Spec-AC-01: a suite that changes the shipping repository turns the framework
  run red and the failure names that suite and the paths it touched. In a
  throwaway repository carrying a byte copy of `tests/skills/test-framework.sh`,
  a fixture suite that appends to a tracked file and creates an untracked one
  makes the framework exit 1, marks that suite FAIL with a TRIPWIRE marker,
  prints a block naming the suite by name and both changed status lines, counts
  the violation in the aggregate, and leaves the clean fixture suite in the same
  run passing. A second fixture suite that COMMITS is caught by the HEAD half
  and both shas are printed, which a status-only comparison could never see.
  - Verification: `bash tests/skills/test-aai-repo-tripwire.sh` TEST-001 and
    TEST-002. Evidence: suite stdout.

- Maps to: CHANGE AC-002
- Spec-AC-02: the same violation is caught at `.aai/scripts/aai-run-tests.sh`.
  A wrapped command that appends to a tracked file produces an
  `AAI-TRIPWIRE FAIL:` block on stderr naming the wrapped command and the
  changed path. The wrapper's exit code is unchanged in every case: 0 for a
  dirty command that exited 0, 7 for a dirty command that exited 7, 0 with no
  tripwire output at all for a clean command. A wrapper whose library is absent
  prints `AAI-TRIPWIRE: NOTE - not armed` rather than degrading silently. The
  two cases behind an `unavailable` state are split the way D9 splits them for
  the framework: a BEFORE snapshot that was taken and an AFTER snapshot that
  was not is named on stderr (the command left the repository unreadable), and
  a BEFORE snapshot that was never usable prints nothing per run — the tripwire
  could not arm in that ENVIRONMENT, which is a constant of the machine rather
  than an observation of the command, and repeating it on every invocation was
  measured to cost a real diagnostic (see D10).
  - Verification: `bash tests/skills/test-aai-repo-tripwire.sh` TEST-007.
    Evidence: suite stdout.

- Maps to: CHANGE AC-003
- Spec-AC-03: `tests/skills/test-aai-doc-numbering.sh` and
  `tests/skills/test-aai-deslop.sh` both run to completion against the real
  checkout leaving `git rev-parse HEAD` and `git status --porcelain=v1`
  byte-identical, demonstrated by running them. Completion means exit 0 or the
  documented exit 42, never an abort part way through.
  - Verification: `bash tests/skills/test-aai-repo-tripwire.sh` TEST-006, which
    snapshots the live repository around each suite; plus the same two suites
    run standalone under the framework's own per-suite tripwire. Evidence:
    suite stdout and the framework aggregate.

- Maps to: CHANGE AC-004
- Spec-AC-04: a suite that never ran, or that ran and left nothing observable
  behind, is not reported as clean. The exit-42-is-SKIP contract still holds
  (exit 42 counts as SKIP, not FAIL), and a skipped suite, a crashed suite and
  an unarmed snapshot are each labelled NOT ATTESTED on their own progress line
  — including the exit-0 case, which used to print a bare `PASS` — and excluded
  from the aggregate's attested count, which prints as
  `N/M suite(s) attested clean` beside the number not attested. A suite whose
  AFTER snapshot cannot be taken while its BEFORE snapshot could FAILS the run,
  marked `[TRIPWIRE UNAVAILABLE]`: an unreadable repository is not evidence of
  an unchanged one (D9).
  - Verification: `bash tests/skills/test-aai-repo-tripwire.sh` TEST-003, over a
    three-suite fixture run holding one clean, one crashing and one skipping
    suite; TEST-009, over a fixture suite that writes and then removes `.git`;
    TEST-010, over a framework run outside a git checkout. Evidence: suite
    stdout.

- Maps to: CHANGE AC-005
- Spec-AC-05: the tripwire costs one `git status` pair per suite and changes
  nothing when the tree is unchanged. Counted through a `git` shim placed first
  on PATH, a framework run over three suites issues exactly six
  `--no-optional-locks ... status --porcelain=v1` calls. A run in which nothing
  touches the repository exits 0, passes the passing suites, skips the skipping
  suite, reports no failure and emits no violation block. The framework's own
  per-suite log is written between the two snapshots, so the assertion that
  `tests/skills/results` is git-ignored in this repository is part of this
  criterion rather than an implementation detail.
  - Verification: `bash tests/skills/test-aai-repo-tripwire.sh` TEST-004 and
    TEST-005. Evidence: suite stdout, including the measured call count.

- Maps to: CHANGE AC-001
- Spec-AC-06: the guard is landable on the tree it lands on. The framework
  carries a seeded, closed known-offender list, and each entry names a suite,
  the registry item that owes its fix, and the exact paths that suite is known
  to dirty. An allowlisted suite that dirties only its listed paths is reported
  as a WARNING naming suite, registry item and every changed path, counted on
  its own aggregate line, kept out of the attested-clean count, and does NOT
  fail the run. An allowlisted suite that dirties any other path, or that moves
  HEAD, still fails. A suite that is not on the list still fails, so Spec-AC-01
  is unchanged. The list is drained by hand: the run prints nothing about an
  entry whose suite came back clean, because "changed nothing" is also true of a
  suite that skipped or crashed (D8).

  These properties hold from the SECOND suite of a run onward, not only the
  first: every path the list names is content-hashed around every suite, so a
  suite writing a path an earlier suite already dirtied is still seen — an
  unlisted one fails the run naming that path, and a listed one is reported
  ALLOWED and kept out of the attested-clean count. The entry path-subset test
  is bounded for paths that were already dirty at suite start and are not
  ratchet paths; D8 states that limit and
  `fu-tripwire-allowed-ignores-pre-dirty` tracks it.
  The table is also checked against itself at startup: a duplicate entry
  for one suite is named and stays dead, and an entry path holding a glob
  metacharacter is named and matched literally rather than expanded against the
  working directory.
  - Verification: `bash tests/skills/test-aai-repo-tripwire.sh` TEST-008, whose
    fixture suites are named after the SHIPPED entries and dirty the shipped
    paths, so the arm reads the same table CI reads; TEST-011, three suites
    writing one ratchet path in sequence; TEST-012, the injected-table arm for
    the two collisions. Evidence: suite stdout.

## Constitution deviations

None. Checked v1 articles 1 to 7.

Article 1 (evidence before claims): every Spec-AC names one executable command
and one read observable, and each new assertion is mutation-proved at full-suite
level with an unmutated control. Article 2 (simplicity): three functions in one
POSIX-sh file, two call sites, no allowlist and no configuration surface.
Article 3 (portability): POSIX sh and git only, no new dependency. Article 4
(degrade and report): a snapshot that cannot be taken is named NOT ARMED, a
truncated violation report names how many lines it dropped, and a suite that did
not run is named NOT ATTESTED. Article 5 (additive first): the wrapper's exit
codes are untouched, the exit-42-is-SKIP contract is untouched, and the only
behavior change a caller can observe is a run going red for a suite that was
already writing to the repository. Article 6 (single-writer state): no STATE
write outside `.aai/scripts/state.mjs`. Article 7 (operator-only merge): no
merge is performed.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | int  | tests/skills/test-aai-repo-tripwire.sh | run `bash tests/skills/test-aai-repo-tripwire.sh` — in a throwaway git repository holding a byte copy of the real framework, a fixture suite that appends to a tracked file and creates an untracked one drives the framework to exit 1, its line reads FAIL with a TRIPWIRE marker, the violation block names the suite by name and both changed status lines, the aggregate counts one failure and one violation, and the clean fixture suite in the same run still reads PASS | green |
| TEST-002 | Spec-AC-01 | int  | tests/skills/test-aai-repo-tripwire.sh | a fixture suite that COMMITS to the fixture repository is marked FAIL with a TRIPWIRE marker and the report prints the HEAD move with both shas, which a status-only comparison cannot see because a commit leaves the working tree clean; the arm also asserts the fixture really did move HEAD, so it cannot pass by not committing | green |
| TEST-003 | Spec-AC-04 | int  | tests/skills/test-aai-repo-tripwire.sh | a fixture run holding one clean, one crashing (exit 3) and one skipping (exit 42) suite keeps exit 42 mapped to SKIP and counted as skipped, labels the skipped suite NOT ATTESTED naming exit 42, labels the crashed suite NOT ATTESTED naming exit 3, reports exactly one of three suites attested clean and two not attested, and reports no tripwire violation | green |
| TEST-004 | Spec-AC-05 | int  | tests/skills/test-aai-repo-tripwire.sh | a fixture run over two clean suites and one skipping suite exits 0, passes both, skips one, prints no failure line and no violation block, reports two of three attested clean, and — counted through a git shim placed first on PATH rather than read off the source — issues exactly six status --porcelain=v1 calls, one pair per suite | green |
| TEST-005 | Spec-AC-05 | int  | tests/skills/test-aai-repo-tripwire.sh | `git check-ignore -q tests/skills/results` succeeds in this repository, so the framework's own per-suite log, written between the two snapshots, can never masquerade as a suite's write and make the tripwire fire on everything | green |
| TEST-006 | Spec-AC-03 | int  | tests/skills/test-aai-repo-tripwire.sh | tests/skills/test-aai-doc-numbering.sh and tests/skills/test-aai-deslop.sh are each run against the REAL checkout with a HEAD plus status --porcelain=v1 snapshot on both sides; each must come back clean and each must exit 0 or 42, so a suite that aborts part way through cannot pass this arm by touching nothing | green |
| TEST-007 | Spec-AC-02 | int  | tests/skills/test-aai-repo-tripwire.sh | in a throwaway repository holding a byte copy of .aai/scripts/aai-run-tests.sh, a clean wrapped command produces exit 0 and zero tripwire output, a dirty command exiting 0 produces exit 0 plus a violation block naming the command and the changed path, a dirty command exiting 7 still produces exit 7 plus the block, a wrapper whose library was removed prints the not-armed NOTE while still returning the command's own exit 5, a wrapper whose repository root is not a git checkout at all (the never-armable environment, D10) writes NOTHING while still returning exit 0, and a wrapped command that removes .git mid-run is still named on stderr while its own exit 9 surfaces | green |
| TEST-008 | Spec-AC-06 | int  | tests/skills/test-aai-repo-tripwire.sh | a five-suite fixture run whose suites are named after the SHIPPED ratchet entries: an allowlisted suite dirtying only its listed paths passes with an ALLOWED label plus a WARNING block naming suite, registry item and changed path and is counted on its own aggregate line; an allowlisted suite dirtying a path its entry does not name still FAILs and the failure names the entry it exceeded; a suite that is not on the list still FAILs (Spec-AC-01 intact); and the aggregate reports 2 of 5 attested clean, so an allowlisted write is never folded into the clean count. The fifth suite is an allowlisted one that writes nothing and is one of the two the attested-clean count covers; the arm asserts nothing about what the run says regarding its unused entry, so the deleted drain report (D8) is not constrained by any assertion here | green |
| TEST-009 | Spec-AC-04 | int  | tests/skills/test-aai-repo-tripwire.sh | a fixture suite that appends to a tracked file and then removes .git drives the framework to exit 1 with that suite marked FAIL [TRIPWIRE UNAVAILABLE], the report says the after-snapshot could not be taken and states the fail-closed rule, and no PASS line is printed for it; the arm also asserts .git really is gone, so it cannot pass by not destroying anything | green |
| TEST-010 | Spec-AC-04 | int  | tests/skills/test-aai-repo-tripwire.sh | a framework run in a directory that is NOT a git repository exits 0 (never being armed is not a suite failure) while its exit-0 suite's own progress line reads PASS followed by the NOT ARMED note rather than a bare PASS, and the aggregate reports 0 of 1 attested clean | green |
| TEST-011 | Spec-AC-06 | int  | tests/skills/test-aai-repo-tripwire.sh | a three-suite fixture run in which an allowlisted suite, a second allowlisted suite and an UNLISTED suite each append to docs/INDEX.md in that order, which is the only order in which the defect appears: the second listed writer reads PASS with the ALLOWED label rather than the bare PASS it used to print, the unlisted third writer FAILs with a TRIPWIRE marker and the block names docs/INDEX.md through the ratchet-path content hash, the run exits 1, none of the three is counted attested clean, and the arm asserts all three appends really landed so it cannot pass by nothing happening | green |
| TEST-012 | Spec-AC-06 | int  | tests/skills/test-aai-repo-tripwire.sh | the only ratchet arm that injects entries, into the byte copy's table, and says so: a second entry for a suite the table already names is reported DUPLICATE and stays dead, so that suite still FAILs on the path only the dead entry covers; and an entry path holding a glob metacharacter is reported and compared literally, so a suite writing the path that glob would expand to in the framework's working directory still FAILs, with the framework run from the fixture root so the widening had a target to hit | green |

Failing-first discipline (strategy `direct`, so exit codes are the record). Every
arm above asserts an observable that does not exist on the pre-change tree — the
tripwire library, the TRIPWIRE marker, the attestation counters, the wrapper
report — so each fails naturally before the edit. The load-bearing evidence is
therefore MUTATION at full-suite level with an unmutated green control, recorded
in the Implementation return record: for each new assertion, one named single-
point mutation of the shipped code that turns exactly the expected arm red while
the control run is green. An assertion verified only by reading is not accepted.

## Verification

- `bash tests/skills/test-aai-repo-tripwire.sh` exits 0
- `bash tests/skills/test-framework.sh` with `AAI_TEST_TIMEOUT=1800`; report the
  aggregate and name every failure
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-deslop.sh`
- every suite `node .aai/scripts/select-suites.mjs --files-from <changed files>`
  returns, plus `tests/skills/test-aai-layer-profiles.sh` and
  `tests/skills/test-aai-feedback-upsert.sh`
- `node .aai/scripts/spec-lint.mjs` clean and
  `node .aai/scripts/check-test-registration.mjs` clean
- `git status --porcelain=v1` byte-identical around each of the two suites named
  in Spec-AC-03

## Evidence contract

- The new suite's stdout, including TEST-004's measured status-call count.
- The framework aggregate, with every failure named.
- For every new assertion: the mutation applied, the arm that went red, and the
  unmutated control run that stayed green.
- The pre-change and post-change `git rev-parse HEAD` and
  `git status --porcelain=v1 -uno` line count for the whole ride.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN a suite changes the shipping repository THEN the framework run goes red and the failure names that suite and every path it touched, including a suite whose only change is a commit | done | TEST-001 green; TEST-002 green | — | the framework is the load-bearing funnel because CI runs it, not the wrapper; both halves of the snapshot are needed because a commit leaves git status clean. Bite proved by mutation at full-suite level: dropping the dirty-overrides-outcome branch in test-framework.sh turns TEST-001, TEST-002 and TEST-008(c) red and nothing else; dropping the HEAD line from the snapshot turns TEST-002 red alone, which is the arm no status comparison can cover. Unmutated control green at exit 0 |
| Spec-AC-02 | WHEN the same violation happens under .aai/scripts/aai-run-tests.sh THEN it is reported on stderr naming the command and the path, and no exit code changes | done | TEST-007 green | — | report-only by measurement, not preference: the wrapper's exit codes are a pinned contract and the canonical whole-suite invocation legitimately dirties the tracked-but-gitignored docs/ai/tests/test-runs.jsonl every run. Bite proved by two mutations at full-suite level, each turning TEST-007 red alone: removing the report call, and removing the not-armed NOTE so an unarmed tripwire degrades silently. Unmutated control green |
| Spec-AC-03 | WHEN test-aai-doc-numbering.sh and test-aai-deslop.sh run against the real checkout THEN both run to completion and leave HEAD and git status --porcelain=v1 byte-identical | done | TEST-006 green | — | both now run their generator over a mirror of its real inputs instead of writing to PROJECT_ROOT and copying files back; a third offender, test-aai-spec-lint.sh TEST-011, was found by the tripwire during this ride and given the same fix. Measured pre-change on a clean tree: doc-numbering DIRTY with M docs/INDEX.md, spec-lint DIRTY with M docs/INDEX.md, deslop already net-clean because its restore ran on the happy path. Bite proved by mutation: pointing doc-numbering's generator back at PROJECT_ROOT turns TEST-006 red alone. Unmutated control green |
| Spec-AC-04 | WHEN a suite is skipped, crashes, or leaves no readable snapshot THEN it is reported NOT ATTESTED rather than clean on its own progress line, an unreadable after-snapshot fails the run, and the exit-42-is-SKIP contract is unchanged | done | TEST-003 green; TEST-009 green; TEST-010 green | — | clean means the tree did not move, never that the suite ran; the aggregate prints attested and not-attested counts and metrics.jsonl carries them per suite. Two holes validation measured are closed here: an exit-0 suite whose tripwire could not arm printed a bare PASS (fu-tripwire-unarmed-pass-line-unlabelled), and a suite that removed .git read as clean at exit 0 (fu-tripwire-unavailable-not-red), which now fails closed while a run that was never armed at all still degrades green with a named note. Bite proved by mutation at full-suite level: forcing tw_attested true turns TEST-003 and TEST-004 red together, which is correct since both read the same accounting; treating an unavailable after-snapshot as NOT ARMED again turns TEST-009 red alone; restoring the bare PASS line turns TEST-010 red and TEST-008 with it, since both read that line. Unmutated control green |
| Spec-AC-06 | WHEN a suite named in the seeded known-offender list dirties only the paths its own entry names THEN the run warns, names the registry item and counts it separately instead of failing; any other suite, any other path and any HEAD move still fail | done | TEST-008 green; TEST-011 green; TEST-012 green | — | code review falsified the first shipped form of this row and TEST-011 is the arm that now holds it: the ratchet's own first write to docs/INDEX.md masked every later write to that path (D7), so from the second suite of a run onward an UNLISTED writer got a bare PASS at framework exit 0 and a live entry was drained while its suite was writing. Closed by content-hashing exactly the paths the table names, around every suite, listed or not — no extra git call, so TEST-004 still measures six status calls over three suites. Bite proved by mutation at full-suite level, each turning exactly the named arms red with the unmutated control green: neutralising aai_tripwire_hash_changed in the library, and disabling the clean-to-dirty escalation in the framework, each turn TEST-011 red alone; removing the noglob guard in tripwire_path_listed and removing the duplicate-entry warning each turn TEST-012 red alone. Reproduced both defects first on a genuinely clean throwaway repo and, in CI's --skill form, on a clean copy of this repository. the ratchet exists because the guard lands on a tree with four live writers (D8); without it the day this lands CI is red on a clean tree until four out-of-scope suites are fixed. The arm names its fixture suites after the SHIPPED entries and dirties the shipped paths, so it reads the same table CI reads rather than a test-only injection. Bite proved by mutation at full-suite level, each turning TEST-008 red alone: dropping the path-subset check so an entry becomes blanket permission, and ignoring the list so a known offender fails again. Spec-AC-01 is separately re-proved intact inside the same fixture run by TEST-008(c). A third mutation proved the drain line, which a second review round then falsified and this ride DELETED: it keyed on the tripwire verdict without consulting attestation, so a ratchet suite that skipped or crashed drained its own live entry. Measured on the shipped table, two live entries marked for deletion and two P2 items marked closed; after the deletion the same fixture prints zero STALE lines with the run verdict, the per-suite lines and the attestation count unchanged (D8). Unmutated control green |
| Spec-AC-05 | WHEN the tree is unchanged THEN no exit code changes and the tripwire has spent exactly one git status pair per suite | done | TEST-004 green; TEST-005 green | — | the pair count is measured through a PATH shim rather than read off the source; TEST-005 pins the git-ignored results directory the whole comparison silently depends on. Bite proved by two mutations at full-suite level: a duplicated snapshot call turns TEST-004 red alone at 9 calls over 3 suites, and removing tests/skills/results from .gitignore turns TEST-005 red alone. Unmutated control green. TEST-005 itself was corrected mid-ride after two lanes showed it failing for the wrong reason: a directory-only ignore pattern cannot be probed by path when the directory is absent, so the arm now probes the log path the framework actually writes |

Status values: planned | implementing | done | deferred | blocked | rejected

Every row read `implementing` until the close ceremony, measured rather than
preferred: `docs-audit`'s false-open heuristic fails CLOSED on a fully terminal
AC Status table whose delivery is un-timestampable — no delivery commit, no
`ac_evidence` event — and reports `probable-false-open`
(`.aai/scripts/lib/docs-audit-core.mjs`, the fail-closed branch of
`falseOpenEvidence`). That verdict removes the literal `CLEAN` token from the
audit output, which turns `tests/skills/test-aai-doc-numbering.sh` TEST-013 red
and, through it, this scope's own TEST-006. Attributed by measurement on
2026-08-19, reproduced twice: with these rows terminal and no delivery commit
the repo audit reports NEEDS-TRIAGE with exactly one drift item naming this
spec; with them non-terminal and nothing else changed it reports CLEAN. The
tension is filed as `fu-acgate-vs-falseopen-catch22` (P2). The rows were flipped
to `done` at the close ceremony of CHANGE-0151, once the delivery commit existed
and the heuristic had something dated to trust.

## Implementation plan

Components:

- `.aai/scripts/lib/repo-tripwire.sh` (NEW) — the three functions of D1, plus
  `aai_tripwire_usable` (D9 needs to tell "never armed" from "lost mid-run") and
  `aai_tripwire_changed_paths` (D8 needs the paths, not just the verdict). The
  header states the D7 limit, because this file is what downstream projects
  vendor and it already documents the sibling D3 limit.
- `tests/skills/test-framework.sh` (EDIT) — source the library or refuse to run
  suites unguarded; one snapshot pair around each `bash "$test_file"`; a dirty
  verdict overriding the suite's outcome; the attestation note on every
  non-clean line; two counters and the aggregate line; two new fields in
  `metrics.jsonl`. Plus, from the code-review pass: the ratchet-path content
  hash pair around every suite (`tripwire_ratchet_init` derives the watched set
  from the table), the literal-match guard and the two table-collision notes.
- `.aai/scripts/aai-run-tests.sh` (EDIT) — arm before launch, report after the
  group reap on every exit path, never touch the exit code, name itself unarmed
  when it cannot arm.
- `tests/skills/test-aai-doc-numbering.sh` (EDIT) — TEST-013's index half moves
  to a `docs/` mirror.
- `tests/skills/test-aai-deslop.sh` (EDIT) — TEST-014's catalog regeneration
  moves to a `.claude/` plus `.aai/SKILL_*.prompt.md` mirror; the
  backup-and-restore pair is deleted.
- `tests/skills/test-aai-spec-lint.sh` (EDIT) — TEST-011's index half moves to
  the same `docs/` mirror; TEST-011(clarify)'s branch-diff allowlist gains this
  scope's two `.aai/` paths.
- `tests/skills/test-aai-repo-tripwire.sh` (NEW) — the seven arms above.
- `tests/skills/suite-map.yaml` (EDIT) — the `aai-repo-tripwire` row.
- `.aai/system/PROFILES.yaml` (EDIT) — the new library classified `core`.
