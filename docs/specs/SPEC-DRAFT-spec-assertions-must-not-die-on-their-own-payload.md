---
id: spec-assertions-must-not-die-on-their-own-payload
type: spec
number: null
status: implementing
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-DRAFT-assertions-must-not-die-on-their-own-payload.md
  rfc: null
  pr: []
  commits: []
---

# Spec — an assertion must not die on its own payload

SPEC-FROZEN: true

Ceremony justification: one surface (the `tests/skills/` corpus), no production
code, no protected path from `protected_paths_l3`. The change is a sourceable
assertion helper, a corpus ratchet arm in the suite that already owns test-corpus
hygiene, and a bounded set of measured conversions. Blast radius is the test
corpus itself, and the full framework is the regression net.

## Links
- Requirement: docs/issues/CHANGE-DRAFT-assertions-must-not-die-on-their-own-payload.md
- Related, NOT this defect: SPEC-0139 (`spec-cli-output-survives-a-pipe`,
  CHANGE-0153) fixed `follow-ups.mjs` truncating its own stdout at the same
  64 KiB boundary. Same buffer, different mechanism — that was a WRITER losing
  bytes; this is a READER (`grep -q`) exiting early and killing the writer. The
  two must not be conflated in any write-up.
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: direct
- Rationale: the defect is already reproduced and characterised by the intake's
  measurements, and re-proved in this scope's own baseline (a 216 000 B payload
  exits 141 under `set -o pipefail`, a 3 000 B payload exits 0). What is missing
  is not a red test but a measurement of WHICH sites carry a payload large
  enough to hit it. The conversions are therefore measurement-driven and each
  new assertion still carries its own bite proof plus an unmutated control.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single-surface test-corpus change on a dedicated branch;
  no parallel scope competes for `tests/skills/`.
- User decision: inline
- Base ref: main (67b9580)
- Worktree branch/path: fix/assertions-survive-large-payloads (inline)
- Inline review scope: `tests/skills/lib/assert-payload.sh`,
  `tests/skills/lib/pipe-grep-q-ratchet.sh`,
  `tests/skills/lib/pipe-grep-q-baseline.tsv`,
  `tests/skills/test-aai-hygiene-pack.sh`,
  `tests/skills/test-aai-docs-audit.sh`,
  `tests/skills/suite-map.yaml`,
  `docs/specs/SPEC-DRAFT-spec-assertions-must-not-die-on-their-own-payload.md`

## The measurement that sizes this change

The at-risk set is MEASURED at runtime, never read out of the source. Method:

- A `grep` shim is installed as an EXPORTED BASH FUNCTION, not as a `PATH`
  binary. A shim process cannot see its caller's `BASH_SOURCE`/`BASH_LINENO`,
  and darwin has no `/proc` to walk for parentage; a shell function runs in the
  caller's own shell, so `${BASH_SOURCE[1]}:${BASH_LINENO[0]}` is the exact call
  site. `export -f grep` carries it into every `bash <suite>` child the
  framework spawns (verified: a child script's call is attributed to the child
  script and its line).
- When `-q` (or `--quiet`/`--silent`) is present AND stdin is a pipe, the shim
  copies stdin to a temp file, records `bytes / file / line / function / args`,
  then runs the real `grep` against that file.
- The shim MASKS the defect by reading to EOF — that is deliberate. It is a SIZE
  CENSUS, not a reproduction. A green framework run under the shim is NOT
  evidence the defect is gone, and must never be reported as such.
- The census runs the FULL framework (`tests/skills/test-framework.sh`), once.

The recorded distribution decides Spec-AC-01's conversion set.

### Result (measured 2026-08-21, 81 suites, one full framework run)

13 091 `grep -q` calls with a pipe on stdin were recorded. Distribution:

```
0 B (empty)          23
1 B - 1 KiB       2 307
1 - 4 KiB           561
4 - 16 KiB       10 195
16 - 32 KiB           3
>= 32 KiB             0    <- the at-risk set, over REPOSITORY call sites
```

**The at-risk set is EMPTY.** The two rows at or above the floor are both this
scope's own `test_101` CONTROL A fixture (a temp-dir script that reproduces the
141 on purpose), not repository sites.

The largest real payload is 30 048 B at
`tests/skills/test-aai-ceremony-levels.sh:1147/1149/1151` — 46 % of the 64 KiB
buffer, 92 % of the declared floor, and more than twice the next largest
(12 604 B, `tests/skills/test-aai-doctor.sh:779/781`). It is BELOW the floor
Spec-AC-01 declared before the measurement, so it is filed
(`fu-ceremony-levels-nearest-miss-30kb`, P2), not converted here.

So no site was converted for AC-001, and that is the honest answer: the helper
and the ratchet ship, and the ratchet holds the 389 remaining occurrences at
their measured number.

WHAT THE CENSUS CANNOT SEE, stated plainly: it records only calls that STILL
pipe into `grep -q`. The four sites that produced the original incident were
already pipe-free on `main`, so their 46 KB and 90 KB payloads are outside the
census's lens by construction. The census answers "how big do the payloads of
the sites still at risk get", not "how big can a findings payload get".

## Acceptance Criteria Mapping

- Maps to: CHANGE AC-001
  - Spec-AC-01: WHEN the runtime census records a `grep -q` payload at or above
    the 32 768 B at-risk floor, THEN that call site SHALL be pipe-free in the
    shipped tree. The at-risk set is the census output, not a reading of the
    source.
  - Verification: the census TSV (`bytes / file / line / func / args`), sorted
    descending; every row at or above 32768 B maps to a converted site or to a
    site the spec records as out of the defect's reach with a stated reason.

- Maps to: CHANGE AC-002
  - Spec-AC-02: A sourceable pipe-free assertion helper SHALL exist at
    `tests/skills/lib/assert-payload.sh`, be used by the converted sites, and on
    failure name the needle and print AT MOST 512 bytes of the payload followed
    by the true total byte count.
  - Verification: `bash tests/skills/test-aai-hygiene-pack.sh` TEST-001/TEST-002
    — a >64 KiB MATCHING payload (measured 212 011 B) passes through the helper
    at exit 0, while the old idiom on the SAME payload exits 141 and on a small
    payload exits 0 (so the 141 is the threshold, not the fixture); a FAILING
    helper call emits a message under 1 200 B naming the needle and stating the
    true total.

- Maps to: CHANGE AC-003
  - Spec-AC-03: A ratchet arm SHALL count occurrences of the unsafe shape per
    file across `tests/skills/`, and FAIL naming the file when any file's count
    RISES above its recorded number or when a file not in the baseline carries
    the shape. A file whose count FALLS SHALL keep the recorded number and emit
    a NOTE — never silently lower the bar.
  - Verification: `bash tests/skills/test-aai-hygiene-pack.sh` TEST-003/TEST-005
    — injecting one occurrence into a fixture copy makes the arm fail and name
    that file; the unmutated control passes; deleting an occurrence produces a
    NOTE, exit 0, and an unchanged baseline.
  - **Two honest limits, both found by validation round 1 and stated here so the
    arm is not read as stronger than it is.**

    1. *Selection, fixed.* The arm can only gate a pull request that RUNS it,
       and `select-suites.mjs` did not select `aai-hygiene-pack` when an
       already-baselined suite file gained an occurrence — the ratchet never
       gated the change it exists to catch. `aai-hygiene-pack` is therefore now
       a `core:` suite (6 s, runs on every selected-mode PR). Verified: a diff
       touching only `tests/skills/test-aai-doctor.sh` now returns
       `CORE aai-hygiene-pack reason=core`. Registry:
       `fu-ratchet-not-selected-on-rise`.
    2. *Scan coverage, NOT fixed.* Validation planted eight unsafe variants and
       the scanner counted ONE. It misses a pipeline split across lines,
       `grep -F -q` flag order, an env-var prefix, an intermediate pipeline
       stage, an indirect binary, and anything under a SUBDIRECTORY — the glob
       is `tests/skills/*.sh`, so `tests/skills/lib/` and
       `tests/self-hosting/` are unscanned. The ratchet therefore holds the
       COMMON form of the idiom at its measured number; it does not prove the
       absence of the shape. Filed as `fu-pgq-scan-evadable-shapes` (P3) rather
       than fixed here: widening it is an arms race, and this spec's job is the
       measured hazard, not every way of writing it. A net-zero same-file edit
       (one occurrence removed, one added) also produces no verdict.

- Maps to: CHANGE AC-004
  - Spec-AC-04: The ratchet's recorded number SHALL be produced by the scanner
    the arm itself runs (`--record` mode), never typed in from a document.
  - Verification: `bash tests/skills/test-aai-hygiene-pack.sh` TEST-004 — the
    arm plants a KNOWN number of occurrences in a fixture tree, runs the real
    `--record` against it, and asserts the written number equals the plant; then
    changes the plant and re-records and asserts the number MOVED. A recorder
    with a constant in it cannot follow. Plus: the committed baseline names its
    generator, every committed row names a real file with a non-zero count, and
    a zero-total live scan FAILS rather than validating a baseline vacuously.

- Maps to: CHANGE AC-005
  - Spec-AC-05: No converted assertion SHALL change what it asserts — each
    converted site keeps its needle and the substance of its message.
  - Verification: `bash tests/skills/test-aai-docs-audit.sh` exits 0 (the suite
    that owns every converted site), and TEST-006 pins each converted needle
    string as still present at its site.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                  | Status       | Evidence | Review-By | Notes                                            |
|------------|----------------------------------------------------------------------------------------------|--------------|----------|-----------|--------------------------------------------------|
| Spec-AC-01 | WHEN the census records a grep -q payload at or above 32768 B THEN that site is pipe-free      | implementing | census 2026-08-21 81 suites 13091 calls; at-risk set EMPTY | — | max real payload 30048 B, below the floor, filed as fu-ceremony-levels-nearest-miss-30kb |
| Spec-AC-02 | A sourceable pipe-free helper exists, is used, and bounds its failure message to 512 B         | implementing | —        | —         | tests/skills/lib/assert-payload.sh                 |
| Spec-AC-03 | The ratchet counts per file, fails on a rise naming the file, and never lowers on a shrink     | implementing | —        | —         | arm in test-aai-hygiene-pack.sh                    |
| Spec-AC-04 | The recorded number is produced by the scanner the arm runs, not typed from a document         | implementing | —        | —         | --record tracks a planted fixture tree             |
| Spec-AC-05 | No converted assertion changes what it asserts                                                 | implementing | —        | —         | needle pins plus the owning suite green            |

## Implementation plan

Components:
- `tests/skills/lib/assert-payload.sh` — PURE sourceable library (no `set -u`,
  no `cd`, no execution), bash-3.2 safe. Exports `assert_payload_contains`,
  `assert_payload_not_contains` and the public `payload_preview` (for an
  rc-check whose failure message prints the same payload without asserting on
  its content). The two assertions take `<payload> <needle> [message]`,
  match with `case`/`[[ == *needle* ]]` (no pipe, no subprocess), and on failure
  print `FAIL: <message> (needle: '<needle>')` followed by a payload preview
  bounded at 512 bytes with `... [<N> bytes total, truncated]`. The helper
  delegates to the caller's `log_fail` when one is defined so a suite's existing
  failure convention and exit code are preserved; otherwise it prints to stderr
  and returns 1.
- `tests/skills/lib/pipe-grep-q-ratchet.sh` — PURE sourceable library plus a
  `--record` entry point. `pgq_scan <dir>` emits `<count>\t<basename>` per file
  carrying the unsafe shape; `pgq_compare <baseline> <scan>` emits `RISE`,
  `NEW`, `SHRINK` and `GONE` lines. Scans with `/usr/bin/grep`-class ERE
  `(printf|echo)[^|]*\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*q`.
- `tests/skills/lib/pipe-grep-q-baseline.tsv` — generated by
  `bash tests/skills/lib/pipe-grep-q-ratchet.sh --record`.
- `tests/skills/test-aai-hygiene-pack.sh` — new arms; each registered in
  `main()` so `check-test-registration.mjs` stays clean.
- `tests/skills/suite-map.yaml` — the `aai-hygiene-pack` row gains the three new
  lib paths so a change to them re-selects the suite.

Decisions:
- D1 — the helper does NOT go in `tests/skills/test-framework.sh`. Measured: no
  suite sources it; the framework RUNS suites as subprocesses. A function added
  there would be invisible to all 83 suites. `tests/skills/lib/` is the house
  location for shared suite code (`prompt-diet-ledger.sh`,
  `close-work-item-pin.sh`).
- D2 — the helper does NOT touch `assert_contains`/`assert_not_contains`. Those
  grep a FILE with no pipe and are not affected; the intake forbids touching
  them. The new names are deliberately distinct (`assert_payload_*`) so the
  file-vs-payload distinction stays legible at the call site.
- D3 — the ratchet counts the NARROW shape the intake censused
  (`printf`/`echo` of a variable piped into `grep -q`), not the 657-occurrence
  superset of any pipe into `grep -q`. The narrow shape is the copied idiom with
  a drop-in pipe-free replacement; the superset includes producers whose output
  is structurally small (`git status --porcelain | grep -q`) and would ratchet
  in friction with no defect behind it. The arm prints the superset count as a
  non-gating INFO line so the wider surface stays visible.
- D4 — the ratchet counts BOTH occurrences and files. Per-file counts catch a
  new site inside an existing file; the file set catches a new file (absent from
  the baseline with a non-zero count is a RISE from 0). A shrink emits a NOTE
  and leaves the recorded number alone, matching the known-offender ratchet in
  `test-framework.sh`, which is drained by hand on purpose.
- D5 — an EMPTY needle matches every payload, so both helpers REFUSE one rather
  than answering it. Without that, an assertion whose needle variable expanded
  to nothing would pass forever while testing nothing — a vacuity hole opened by
  the very act of making assertions shorter.
- D6 — the ratchet arms live in `tests/skills/test-aai-hygiene-pack.sh`, which
  already owns `check-test-registration.mjs`, the suite-map hygiene pin and the
  phantom-API denylist scan. NOT `test-aai-test-canon.sh`, which owns the
  aai-test-canon SKILL rather than the corpus. There is no
  `check-test-registration` shell arm to sit beside — it is
  `.aai/scripts/check-test-registration.mjs`, invoked from hygiene-pack.
- D7 — the pipe character is PARAMETERISED in the new arms. The ratchet scans
  `tests/skills/*.sh` including the suite that implements it, and the fixtures
  must CONTAIN the unsafe shape to prove the ratchet bites. Measured while
  writing this: two PROSE COMMENTS describing the shape put this suite in the
  baseline at 2. The scanner does not care that an occurrence is a comment, and
  it should not.
- D8 — a new `.aai/**` file would trigger the PLANNING companion-obligations
  PROFILES.yaml classification. Everything here lives under `tests/skills/`, and
  no `.aai/*.prompt.md` or `.aai/AGENTS.md` bytes change, so NEITHER companion
  obligation applies.

Edge cases:
- The framework runs suites in a disposable worktree; the census normalises
  `/…/wt/tests/…` back to the repo-relative path.
- The scanner must be vacuity-guarded: a broken pattern yields zero hits and
  would otherwise pass a comparison against a baseline it never contradicts.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                  | Description                                                                                  | Status  |
|----------|------------|-------------|---------------------------------------|----------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-02 | unit        | tests/skills/test-aai-hygiene-pack.sh | helper contract: match, non-match, both directions, needle named, preview bounded to 512 B     | green   |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-hygiene-pack.sh | 216000 B matching payload passes the helper at exit 0 while the old idiom exits 141 (control)  | green   |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-hygiene-pack.sh | live gate over tests/skills plus a bite proof: one injected occurrence FAILs and names the file  | green   |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-hygiene-pack.sh | baseline is byte-identical to a fresh --record; zero-total scan FAILS (vacuity guard)          | green   |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-hygiene-pack.sh | a shrunk file yields a NOTE, exit 0, and an unchanged recorded number                          | green   |
| TEST-006 | Spec-AC-01, Spec-AC-05 | integration | tests/skills/test-aai-hygiene-pack.sh | every converted site sources the helper, keeps its needle, and dumps no unbounded payload       | green   |

## Verification
- `bash tests/skills/test-aai-hygiene-pack.sh` — exit 0, TEST-001..006 all PASS.
- `bash tests/skills/test-aai-docs-audit.sh` — exit 0 (owns the converted sites).
- `node .aai/scripts/select-suites.mjs --files-from <changed>` — run whatever it
  returns.
- `node .aai/scripts/check-test-registration.mjs tests/skills` — exit 0.
- Census artifact: the runtime TSV plus its size distribution, reported with the
  masking caveat stated.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
- ref_id: assertions-must-not-die-on-their-own-payload
- Spec-AC-01..05 map to TEST-001..006 as tabled above.
- Commands and exit codes recorded per run; the census TSV is the Spec-AC-01
  evidence artifact.
- Strategy is `direct`: targeted regression tests green (exit codes) plus the
  scoped diff. No stored RED artifact is demanded; every new assertion still
  carries an in-suite bite proof with an unmutated control.
