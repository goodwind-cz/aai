---
id: spec-drain-the-tripwire-known-offender-list
type: spec
number: 146
status: done
ceremony_level: 1
capability: aai-suite-isolation
links:
  requirement: docs/issues/CHANGE-0158-drain-the-tripwire-known-offender-list.md
  rfc: null
  pr:
    - 276
  commits:
    - 7aee6f6b85b4971ca4adea6036b7438d142bb72a
---

# Spec — drain the tripwire known-offender list

SPEC-FROZEN: true

Ceremony justification: one surface (`tests/skills/test-framework.sh`, a four-line
array) plus its own gating suite. The change can only make the tripwire STRICTER,
so its failure mode is a red CI rather than a silent hole, and it is fully
covered by a suite that already exists.

## Links
- Requirement: docs/issues/CHANGE-0158-drain-the-tripwire-known-offender-list.md
- Prior art: docs/specs/SPEC-0137-spec-suites-must-not-touch-the-shipping-repo.md
  (the tripwire and the ratchet), docs/specs/SPEC-0138-spec-suites-run-in-a-disposable-worktree.md
  (the isolation that made the four exemptions dead)
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: loop
- Rationale: the production change is a four-line deletion whose behavior is
  already specified by SPEC-0137; the real work is in the gating suite, where
  each new arm's RED is produced by mutation against an unmutated green control
  and observed live. Stored RED artifacts buy nothing here because the mutation
  is a one-line edit to a byte copy inside the arm's own fixture.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: the edits are three files and inherently reviewable inline,
  but every measurement of the framework's behavior MUST run in a disposable
  `git worktree` — a full framework run mutates `docs/ai/tests/test-runs.jsonl`
  in whatever tree it runs in, and the mutation experiments deliberately break
  the framework.
- User decision: inline
- Base ref: main (862e069), branch feat/drain-the-tripwire-ratchet
- Worktree branch/path: measurement-only, disposable, under the session scratchpad
- Inline review scope: tests/skills/test-framework.sh,
  tests/skills/test-aai-repo-tripwire.sh,
  docs/specs/SPEC-0146-spec-drain-the-tripwire-known-offender-list.md

## Acceptance Criteria Mapping

- Maps to: CHANGE AC-001
- Spec-AC-01: `TRIPWIRE_KNOWN_OFFENDERS` in `tests/skills/test-framework.sh`
  holds zero entries, and a full framework run with the drained list reports the
  same pass set and an attested-clean count no lower than the run taken before
  the drain on the same tree.
  - Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh`
    once before and once after the change, each inside its own disposable
    worktree; compare the `Tripwire: N/81 suite(s) attested clean` line, the
    `Failed:` line and the per-suite PASS/FAIL/SKIP set, not only the exit code.

- Maps to: CHANGE AC-002
- Spec-AC-02: WHEN a suite whose name matches a formerly exempt suite writes a
  formerly exempt path, the framework SHALL fail the run and name that suite,
  because the shipped table no longer exempts it.
  - Verification: `bash tests/skills/test-aai-repo-tripwire.sh` arm TEST-013,
    which runs a byte copy of the SHIPPED framework over fixture suites named
    `aai-hitl-propagation` and `aai-metrics` writing `docs/INDEX.md` and
    `docs/ai/overview.html`, and asserts framework exit 1, a
    `FAIL ... [TRIPWIRE]` line for each, and the absence of any
    `tripwire ALLOWED` label. Bite proof: re-inserting either entry into the
    byte copy turns the arm RED against an unmutated green control.

- Maps to: CHANGE AC-003
- Spec-AC-03: `fu-hitl-propagation-writes-real-index`,
  `fu-metrics-suite-writes-real-overview`, `fu-state-suite-writes-real-index`
  and `fu-token-capture-writes-overview` are each closed in the follow-up ledger
  against this scope, each carrying the per-suite measurement that justifies the
  closure as its `--source`.
  - Verification: `node .aai/scripts/follow-ups.mjs list --status open --json`
    contains none of the four ids, and `--status done --json` contains all four
    with `resolved_by` naming this scope.

- Maps to: CHANGE AC-004
- Spec-AC-04: WHEN the shipped `TRIPWIRE_KNOWN_OFFENDERS` table holds more
  entries than the arm's declared maximum, `tests/skills/test-aai-repo-tripwire.sh`
  SHALL fail and name the excess; the declared maximum is 0 today.
  - Verification: `bash tests/skills/test-aai-repo-tripwire.sh` arm TEST-014.
    Bite proof: adding one entry to the shipped table turns the arm RED. Vacuity
    guard: the arm refuses to read a count of zero from a file in which it cannot
    find the `TRIPWIRE_KNOWN_OFFENDERS=(` anchor and its closing `)` — that case
    reports UNCOVERED and fails, never passes.

- Maps to: CHANGE AC-005
- Spec-AC-05: nothing else about the tripwire changes. The snapshot pair, the
  HEAD half, the content-hash half, the ALLOWED accounting, the NOT-ATTESTED
  accounting, the unavailable-snapshot fail-closed branch, the unarmed labelling
  and the ratchet's own table-collision diagnostics all remain, and remain
  covered.
  - Verification: `bash tests/skills/test-aai-repo-tripwire.sh` exits 0 with all
    14 arms passing, including TEST-008 / TEST-011 / TEST-012, which continue to
    exercise the ratchet MECHANISM (allowed-inside-paths, failed-outside-paths,
    content-hash unmasking, duplicate and glob entries) against entries the arms
    inject into their own byte copy; plus `git diff` over
    `.aai/scripts/lib/repo-tripwire.sh` being empty.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the framework runs with a drained known-offender table the run SHALL keep the pre-drain pass set and attested-clean count | done | 7c5a09c; TRIPWIRE_KNOWN_OFFENDERS parses to 0 entries, read back by TEST-014 at head; implementer's two full runs before and after (81/81 PASS, 81/81 attested, identical pass sets, zero ALLOWED, run test-20260822-184502 after); validation did NOT re-run the full framework (both runs were required to be disposable so their ledger rows left with the clones) and instead ran the declared scope in a disposable worktree at 7c5a09c: aai-repo-tripwire 14/14 exit 0, aai-suite-isolation exit 0, aai-hygiene-pack / aai-check-state / aai-docs-audit / aai-spec-lint all exit 0 | — | full-run parity is the implementer's evidence and is not repo-reproducible by design; see fu-drained-suites-still-write-unisolated for what the zero-ALLOWED line does and does not prove |
| Spec-AC-02 | WHEN a formerly exempt suite writes a formerly exempt path the framework SHALL fail the run and name it | done | 7c5a09c; TEST-013 green in the 14/14 run; validation mutation M8 injected the two exemptions into the byte copy AFTER the vacuity guard and all six assertions fired (framework exit 0 instead of 1, neither suite FAIL [TRIPWIRE], neither named in a violation block, 'something still reads ALLOWED', wrong Failed count) against an unmutated green control; mutation M2b (unfindable anchor) turns the arm red as UNCOVERED rather than green | — | the assertions bite, not only the guard |
| Spec-AC-03 | The four registry items are closed against this scope with their measurements | done | 7c5a09c; follow-ups.mjs list --status open --json contains none of the four (open backlog re-read at 134 before this round's filings), --status done --json contains all four with resolved_by drain-the-tripwire-known-offender-list and a per-suite measurement in --source | — | measurements are scoped to isolated runs; see fu-drained-suites-still-write-unisolated |
| Spec-AC-04 | WHEN the shipped table exceeds the declared maximum of zero entries the gating suite SHALL fail | done | 7c5a09c; TEST-014 green at 0 entries under maximum 0; validation mutation M1 re-inserted one drained entry and the arm failed naming the count (1), the maximum (0) and the offending entry verbatim; M2b (unfindable anchor) and M2 (anchor with a trailing comment) both fail as UNCOVERED, never pass; the positive control proving the counter can see 2 seeded entries is asserted on the delta | — | line-based parse limits filed as fu-ratchet-counter-line-undercount |
| Spec-AC-05 | Nothing else about the tripwire changes and every existing arm stays green | done | 7c5a09c; .aai/scripts/lib/repo-tripwire.sh and .aai/scripts/aai-run-tests.sh are byte-identical to 862e069 (md5 23efde1d46ccf18758dcc39c2a1ff4fc and d8ba567838b81c81632ab68553506d5b on both sides, empty git diff); all 14 arms green (TEST-001 snapshot pair, TEST-002 HEAD half, TEST-003 NOT-ATTESTED accounting, TEST-004 one status pair per suite, TEST-008 ALLOWED accounting, TEST-009 fail-closed unavailable snapshot, TEST-010 unarmed labelling, TEST-011 content-hash half, TEST-012 table-collision diagnostics); the hashed path set is the same three paths as on main, now from TRIPWIRE_ALWAYS_WATCH instead of derived from the table, measured to catch a second same-run write that goes uncaught without it | — | the always-watch floor is a real behaviour-preserving change but carries no arm — fu-tripwire-always-watch-floor-uncovered; the spec body still describes it as filed-not-fixed — fu-drain-spec-says-d7-filed-not-fixed |

## Implementation plan

### Components affected
- `tests/skills/test-framework.sh` — `TRIPWIRE_KNOWN_OFFENDERS` becomes an empty
  array. The comment above it is rewritten: it stops describing four live
  entries and starts describing the format the parser still requires.
- `tests/skills/test-aai-repo-tripwire.sh` — TEST-008 and TEST-011 stop reading
  the shipped table and inject their own entries; TEST-013 and TEST-014 are new.
- Nothing in `.aai/scripts/lib/repo-tripwire.sh`. Nothing in
  `.aai/scripts/aai-run-tests.sh`. Nothing in `tests/skills/suite-map.yaml`
  (`tests/skills/test-framework.sh` already maps to `aai-repo-tripwire` and
  `aai-suite-isolation`).

### D1 — the four entries are dead, and their gating arms read the SHIPPED table
Measured, not assumed. `test_008_known_offender_ratchet` and
`test_011_ratchet_paths_are_content_watched` byte-copy the real framework and
then name their fixture suites `aai-metrics`, `aai-state` and
`aai-hitl-propagation` precisely so that the arm reads "the same table CI reads"
(its own header says so). Draining the table therefore turns both arms RED —
that is a consequence of the drain, not an unrelated defect, and it is inside
Spec-AC-01.

Both arms are converted to the injection technique TEST-012 already uses: the
entries they need are written into the byte copy by `awk` at the
`TRIPWIRE_KNOWN_OFFENDERS=(` anchor, and each arm asserts the injection landed
before it draws any conclusion. The MECHANISM stays covered exactly as before;
what stops being covered is "these four particular strings are in the shipped
file", which is the thing this change deletes. TEST-014 covers the shipped file
instead, from the opposite direction.

### D2 — length ratchet, not a bare emptiness assertion (Spec-AC-04)
At a maximum of zero the two are the SAME assertion — `count <= 0` and
`count == 0` accept exactly one table. The choice is therefore not about
detection power today; it is about which edit a future engineer reaches for when
a legitimate exemption has to exist.

- Under a bare emptiness arm there is no legal edit that keeps the arm alive and
  admits the entry. The cheapest path for someone in a hurry is to delete the
  arm. That failure is SILENT and total: the class of assertion disappears, and
  the only thing that would notice is a human reading the diff.
- Under a length ratchet the cheapest path is to bump the declared maximum by
  one. That failure is SLOW and LEGIBLE: the arm survives, the number is in the
  diff, and the trend is a number a reviewer can read.

I would rather have legible erosion than a silent hole, so the arm is a ratchet
on the length with `TRIPWIRE_RATCHET_MAX_ENTRIES=0`. Make the cheap path the
safe path. The failure message names the maximum, the actual count and every
entry over the line, so a bump is never anonymous.

The ratchet is only trustworthy if a zero it reports is a zero it MEASURED. The
arm's vacuity guard is therefore an anchor check: if
`TRIPWIRE_KNOWN_OFFENDERS=(` or its closing `)` cannot be found in the shipped
framework, the arm reports UNCOVERED and FAILS. A parse that found nothing is
not evidence of a table with nothing in it.

### D3 — the `<suite>|<registry id>|<paths>` convention survives, in the comment
The convention is not documentation. `tripwire_allowlist_entry` splits on `|`
and `tripwire_ratchet_init` strips two fields to reach the paths: the parser
enforces three fields whether or not any entry exists. Delete the comment and
the next person writes `<suite>|<paths>`, whose first path is silently consumed
as the registry id and whose entry then exempts one path fewer than its author
believes — a hole, filed by nobody, in the exact shape this scope exists to
close.

So the format comment stays, and changes register: it stops being a note about
four live entries and becomes the contract the parser will hold a future entry
to, including "nothing goes in here without a registry item id". Executable
instances of the convention do not disappear either — TEST-008, TEST-011,
TEST-012 and TEST-013 all construct entries in the canonical three-field form,
so the format keeps arms that go red if the parser's expectations drift.

### Edge cases and known consequences
- `TRIPWIRE_WATCH_PATHS` is DERIVED from the table, so draining the table empties
  the content-hash watch set. Every use site already guards with
  `"${ARRAY[@]:-}"`, and `${#TRIPWIRE_WATCH_PATHS[@]}` on an empty global array
  under `set -euo pipefail` is fine on bash 3.2.57 (verified on the host).
  CONSEQUENCE, in scope to NAME and out of scope to fix: the D7 status-class
  blind spot re-opens for those three paths. It re-opens because the writer that
  used to seed the masking is gone — but a FAILING suite does not revert its
  write, so a second writer of the same path later in the same run is again
  invisible. This is filed, not fixed: closing it means watching a path set that
  no longer derives from anything, which is a new mechanism and a different
  scope.
- The ratchet paths are hashed once per suite. With zero watch paths the
  framework does strictly less work; no accounting line changes shape, because
  the `Tripwire: N/M attested clean` line does not mention the ratchet unless
  `TRIPWIRE_ALLOWED > 0`.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                    | Description | Status |
|----------|------------|------|-----------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | int  | tests/skills/test-framework.sh          | Run `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh` in a disposable worktree before and after the drain; the after-run's pass set equals the before-run's and its attested-clean count is not lower | green |
| TEST-002 | Spec-AC-02 | int  | tests/skills/test-aai-repo-tripwire.sh  | Arm TEST-013 — against a byte copy of the SHIPPED framework, fixture suites named aai-hitl-propagation and aai-metrics writing docs/INDEX.md and docs/ai/overview.html drive exit 1, each reads FAIL with a TRIPWIRE marker, and no line reads tripwire ALLOWED | green |
| TEST-003 | Spec-AC-04 | int  | tests/skills/test-aai-repo-tripwire.sh  | Arm TEST-014 — the shipped table parses to at most TRIPWIRE_RATCHET_MAX_ENTRIES entries, the arm names count and maximum, and a missing table anchor reports UNCOVERED and fails instead of passing on an unmeasured zero | green |
| TEST-004 | Spec-AC-05 | int  | tests/skills/test-aai-repo-tripwire.sh  | Run `bash tests/skills/test-aai-repo-tripwire.sh` — all 14 arms pass, TEST-008 TEST-011 TEST-012 still exercise the ratchet mechanism against self-injected entries, and each asserts its injection landed before concluding | green |
| TEST-005 | Spec-AC-03 | int  | .aai/scripts/follow-ups.mjs             | Run `node .aai/scripts/follow-ups.mjs list --status open --json` and `--status done --json`; the four ids are absent from open and present in done with resolved_by naming this scope | green |

## Verification
- `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh` (full,
  disposable worktree, before and after) — compare the pass set, the `Failed:`
  count and the attested-clean count
- `bash tests/skills/test-aai-repo-tripwire.sh` — exit 0, 14/14 arms
- `bash tests/skills/test-aai-suite-isolation.sh` and
  `bash tests/skills/test-aai-hygiene-pack.sh` — the other suites
  `node .aai/scripts/select-suites.mjs` returns for the changed files
- `node .aai/scripts/check-test-registration.mjs tests/skills` — exit 0
- `node .aai/scripts/follow-ups.mjs list --status open --json` — the four ids gone
- Bite proofs, each against an unmutated green control, in a disposable worktree:
  re-insert one drained entry (TEST-014 red, TEST-013 red), remove the injection
  from TEST-008 (TEST-008 red), break the table anchor (TEST-014 UNCOVERED, red)
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status

## Evidence contract
- ref_id: drain-the-tripwire-known-offender-list
- Spec-AC / TEST links: as tabled above
- Commands, exit codes and log paths recorded in the implementation hand-off
- Evidence paths: the two full-run logs and the mutation logs under the session
  scratchpad, quoted with their attested counts in the hand-off
- Commit SHA or diff range: recorded at PR ceremony; this role does not commit
