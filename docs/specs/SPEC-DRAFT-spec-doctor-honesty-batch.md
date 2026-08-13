---
id: spec-doctor-honesty-batch
type: spec
number: null
status: implementing
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0138-doctor-honesty-batch.md
  rfc: null
  pr: []
  commits: []
---

# Spec — doctor/config honesty batch: six recorded follow-ups, one scope

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0138-doctor-honesty-batch.md
- Source dispositions (contracts quoted, not re-derived): docs/ai/decisions.jsonl
  entries 2026-08-13T01:26 (CHANGE-0135 NB batch: F5, F6, N2),
  2026-08-13T10:50 (CHANGE-0137: NB-2 BOM parity) and 2026-08-13T11:22
  (CHANGE-0137 PR #252 batch: BOM first-line key, unreadable-config
  default-on, silent prune failures)
- Fixture provenance for the AC-01 flip targets: the F4/N2 adversarial battery in
  docs/ai/validation/validation-20260813T002100Z-CHANGE-0135-doctor-win-selftest-rescope.md
- Doctor engine EXTENDED (never forked): `.aai/scripts/aai-doctor.mjs` (SPEC-0100, SPEC-0122)
- Twin config parsers under the parity invariant (SEAM-3 of SPEC-0124):
  `.aai/scripts/update-doctor-report.mjs` and `.aai/scripts/update-check.mjs`
- Product docs updated by this scope: docs/product/aai-doctor.md, docs/product/aai-update.md
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1 — the intake declared level 1 and this scope
keeps it: six small recorded follow-ups on one already-delivered surface
(doctor + update helper), all additive honesty fixes with no new file, no
protected path (L3 check below), no exit-code or output-cardinality contract
change, zero network, and every acceptance criterion decided by one directly
executable local command on this POSIX host — nothing waits on CI or Windows.

## Summary

Three dispositions recorded on 2026-08-13 left six follow-ups that all live in
the doctor + update-config surface. The owner approved closing them as one
ride. The six, with their disposition of record:

1. N2 (01:26) — `probeCodexExecSubcommand`'s line-shape regex is tightened,
   not airtight: indented prose starting with `exec` still fabricates
   `available: true` (rescope fixtures A/G) and tab or single-space command
   lists false-negative (fixtures C/D). The proper fix anchors parsing to the
   `Commands:` block.
2. F5 (01:26) — `resolveCliVersion` overloads ABSENT: a resolved executable
   whose `--version` yields nothing reports `present: false`, and the
   `stdout || stderr` fallback can present a stderr diagnostic as the version.
3. F6 (01:26) — the CAT-16 one-line reason folds a timed-out (unknown) probe
   into the not-present count; the paste-able line cannot distinguish absent
   from unknown.
4. NB-2 / Copilot BOM (10:50, 11:22) — a UTF-8 BOM hides a FIRST-LINE config
   key from both column-0 parsers identically (`off` silently becomes `on`).
   Parity invariant: fix `update-doctor-report.mjs` AND `update-check.mjs`
   TOGETHER, never one side.
5. Codex P2 unreadable-config (11:22) — an update-config that EXISTS but
   cannot be read silently defaults on; a named degrade line is owed (the
   default direction stays on: the step is read-only and bounded).
6. Codex P2 silent prune failures (11:22) — retention prune swallows every
   unlink failure; a bounded stderr diagnostic is owed while stdout keeps its
   exactly-one-line contract.

Frozen contracts this scope MUST NOT move: the doctor exit map (0 clean or
WARN-only, 1 any FAIL, 2 usage; `--strict` opt-in), CAT-16 remaining a
PASS-only category, the helper's exactly-one-stdout-line and exit-0-runtime /
exit-2-usage contract, the update entrypoints' exit codes, and zero
network / zero LLM in every touched script.

## Design decisions recorded at planning time (do not re-derive)

### D1 — Commands:-anchored parse shape for the codex exec observation

The parser stops classifying single lines and instead finds command-list
BLOCKS, because that is what clap-style `--help` actually emits:

- Header: a column-0 line matching `/^(commands|subcommands):\s*$/i` (nothing
  after the colon but whitespace). This covers clap's `Commands:` and the
  `SUBCOMMANDS:` variant the rescope report suggested.
- Block extent: the lines following the header that start with at least one
  space or tab. A blank line does NOT end the block; the first NON-EMPTY line
  starting at column 0 (or EOF) ends it. Every such block in the combined
  stdout+stderr text is scanned; first `exec` row wins.
- Command row: `/^[ \t]+exec([ \t]|$)/` applied only INSIDE a block — any mix
  of tabs/spaces as indentation, the token exactly `exec` (so `execute` never
  matches), followed by any single whitespace (tab OR single space OR wider
  column gap) or end of line (a description is optional).
- Honest UNKNOWN: when NO Commands:/Subcommands: header exists anywhere in the
  output, the observation is `{ available: 'UNKNOWN', reason: 'codex --help
  output has no Commands: block' }` — prose-only output can no longer produce
  a boolean either way. A block WITHOUT an exec row is a genuine
  `available: false`; a block WITH one is `available: true`. Each of the three
  verdicts carries its own distinct reason string.

The 7-fixture battery becomes this 11-fixture battery (each fixture is a real
fake-codex `--help` driven through the REAL doctor, PATH-injected as TEST-033
does today). FX-01..FX-07 are the rescope report's A..G, hardened where the
old fixture could no longer discriminate; FX-08..FX-11 are new:

| Fixture | Shape | Expected |
|---------|-------|----------|
| FX-01 (was A) | prose-only help, 4-space-indented line starting `exec` plus two spaces, no Commands: header | UNKNOWN (was the false positive) |
| FX-02 (was B) | real clap Commands: block, 2-space indent, column-aligned separator | true |
| FX-03 (was C) | Commands: block, TAB separator after `exec` | true (was the false negative) |
| FX-04 (was D) | Commands: block, single-space separator after `exec` | true (was the false negative) |
| FX-05 (was E) | Commands: block listing `run` and `login` only, no `exec` token anywhere | false |
| FX-06 (was F) | the filed unindented prose sentence containing `exec`, placed above a Commands: block that lacks exec | false |
| FX-07 (was G) | Commands: block without exec, then a column-0 `Options:` line, then the 2-space-indented prose `exec  and eval are words we deliberately avoid.` | false (block bounding kills the second false positive) |
| FX-08 | `SUBCOMMANDS:` header variant with an exec row | true |
| FX-09 | Commands: block whose exec row is TAB-indented | true |
| FX-10 | prose-only help containing `exec` mid-sentence, no header anywhere | UNKNOWN |
| FX-11 | Commands: block listing `execute` but never `exec` | false |

RED targets on the pre-change tree: FX-01 and FX-07 currently read true,
FX-03 and FX-04 currently read false, FX-10 currently reads false instead of
UNKNOWN — five deterministic failures before the change.

### D2 — version-probe tri-state shape and the CAT-16 count line

Every record in `detail.clis` carries the SAME three fields:
`{ present: true | false | 'UNKNOWN', version: <string or null>, reason: <string or null> }`.

- present true, version verbatim, reason null — the executable resolved and
  `--version` produced a non-empty FIRST STDOUT LINE. Only stdout may ever
  become a version: the `stdout || stderr` fallback is deleted.
- present true, version null, reason named — the executable resolved and ran,
  but stdout's first line is empty (whatever stderr says, whatever the exit
  code). Example reasons: `--version produced no stdout (exit 1)`. This is the
  F5 fix: existence is no longer conflated with version knowledge, and a
  stderr diagnostic is never presented as a version.
- present false, version null, reason `not found on PATH` — no executable
  resolves (Windows PATH/PATHEXT scan miss, POSIX spawn ENOENT).
- present 'UNKNOWN', version null, reason named — the probe could not
  determine presence: `--version` timed out (the intake names timed-out as
  unknown, keeping today's conservative semantics) or the spawn failed with a
  non-ENOENT error. The ad-hoc `unknown: true` flag is retired in favor of the
  tri-state `present` value.

The one-line CAT-16 reason is composed from strict equality (present === true)
so UNKNOWN can never inflate the present count:

`<p>/3 agent CLI(s) present` then, only when the count is non-zero,
` (<n> without version)` then, only when non-zero, `, <u> unknown` then the
unchanged capability tail
`; four SUBAGENT_PROTOCOL capability fields reported UNKNOWN (<reason>)`.

A present-no-version CLI counts inside `<p>` (it IS present) and is named by
the `without version` segment — that is the D2 answer for what the line shows.
CAT-16 stays a PASS-only category: the honesty lives in the line and the
detail, never in the exit code (`--strict` semantics frozen). All strings are
ASCII.

### D3 — BOM strip mechanics: twin-identical lines, never a shared import

Both parsers read the same file and both miss a first-line key behind a UTF-8
BOM because `^` anchors at the BOM character. The fix is one statement placed
immediately after each parser's `readFileSync`, byte-identical in both files:

`if (raw.charCodeAt(0) === 0xFEFF) raw = raw.slice(1);`

A shared helper module was REJECTED after checking how the files are vendored:
both scripts deliberately import node built-ins only (their headers state the
standalone/zero-dependency discipline), they are spawned on independent paths
(SessionStart hook vs update entrypoints), and a new `.aai/scripts/lib` file
would add a partial-vendor failure mode (one file arrives without the other)
plus the new-`.aai`-file companion obligation — all for one line. The parity
invariant is instead pinned in BOTH directions: behaviorally (a BOM-prefixed
first-line key honored by each parser, TEST-004) and structurally (a twin pin
asserting the identical strip statement exists in both files, TEST-005), so
neither side can be fixed or reverted alone.

### D4 — stderr-diagnostic budget for prune failures: one line per run, max

`pruneReports` stays best-effort (a prune failure never degrades the run, the
stdout line, or the exit code) but stops being silent: the run emits AT MOST
ONE stderr line, never one per file —
`update-doctor-report: WARNING retention prune failed for <path> (<code>)`
with ` and <n> more` appended when several files failed; an unreadable reports
directory produces the same single line naming the directory. Zero prune
failures emit zero prune stderr. The same one-line-per-run budget applies to
the D5-companion unreadable-config warning, so a fully degraded run adds at
most two stderr lines while stdout keeps its exactly-one-line contract.

### D5 — everything here is locally provable; no planned rows may survive

Unlike SPEC-0122 (whose Spec-AC-01 was gated on a Windows CI job), every
behavior in this batch is Node + bash on any POSIX host: fake CLIs on PATH,
BOM bytes in fixtures, a directory-shaped config path for EISDIR, a
directory-shaped report name for a portable unlink failure, a sleeping fake
CLI for the timeout arm. Consequently NO Spec-AC row is allowed to remain
`planned` at validation time with a nothing-downstream excuse — 100 percent of
this spec is provable before the PR opens. Portable failure-injection choices
recorded here so tests never need root or chmod tricks:

- exists-but-unreadable config: point `--config` at a DIRECTORY —
  `readFileSync` fails EISDIR, which is exists-but-unreadable and works even
  as root (a chmod-000 arm may be added where non-root, but is not required).
- undeletable report: create a DIRECTORY whose name matches `REPORT_SHAPE` —
  `unlinkSync` on a directory fails on every platform, no permissions games.

## L3 check (recorded)

`protected_paths_l3` in docs/ai/docs-audit.yaml lists `state.mjs`,
`lib/state-engine.mjs`, `lib/state-core.mjs`, `allocate-doc-number.mjs`,
`pre-commit-checks.sh`, `pre-commit-checks.ps1`, `.aai/workflow/WORKFLOW.md`
and `docs/CONSTITUTION.md`. None of them is in this scope.

## Companion obligations (closed list, checked)

- Prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`): NOT touched.
  `.aai/SKILL_DOCTOR.prompt.md` relays the script output verbatim and the
  CAT-16 line stays one line; no new prompt bytes, so no diet-ledger entry and
  no TEST-012 bump are owed.
- New `.aai/**` file: NONE (D3 deliberately avoids one), so no PROFILES.yaml
  classification is owed. `tests/skills/suite-map.yaml` already selects every
  touched file (aai-doctor, aai-update, aai-update-check rows) — no row change.

## Implementation strategy
- Strategy: hybrid
- Rationale: the five behavior ACs (Spec-AC-01..05) have cheap deterministic
  REDs on this host today — D1 names five fixture flips, the tri-state shape
  and count line do not exist yet, a BOM-prefixed `post_update_doctor: off` is
  demonstrably ignored, EISDIR configs default on silently, and prune failures
  are silent — so they take the TDD lane with a stored RED per AC-gating test
  under `docs/ai/tdd/`. Spec-AC-06 is registration plus documentation and
  takes the loop lane with the RED observation recorded (the new doc pins fail
  on the pre-change docs). No intake-sourced implementation-mode choice
  exists for CHANGE-0138 — the intake carries no
  `Implementation mode (user choice):` line.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: eight files, no protected surface, and the scope already
  sits on its own branch `feat/doctor-honesty-batch`. Isolation pays only if
  another ride touches the doctor or update helper concurrently.
  Implementation Preparation asks and decides.
- User decision: undecided
- Base ref: feat/doctor-honesty-batch
- Worktree branch/path: not selected
- Inline review scope: .aai/scripts/aai-doctor.mjs .aai/scripts/update-doctor-report.mjs .aai/scripts/update-check.mjs tests/skills/test-aai-doctor.sh tests/skills/test-aai-update.sh tests/skills/test-aai-update-check.sh docs/product/aai-doctor.md docs/product/aai-update.md docs/issues/CHANGE-0138-doctor-honesty-batch.md docs/specs/SPEC-DRAFT-spec-doctor-honesty-batch.md CHANGELOG.md

## Acceptance Criteria Mapping

- Maps to: CHANGE-0138 AC-001 (N2, Commands:-anchored parse)
  - Spec-AC-01: `probeCodexExecSubcommand` classifies via the D1 block parse;
    the four rescope flip targets flip and the battery grows to 11 fixtures
    covering tab and single-space separators, tab indentation, header
    variants, block bounding and the honest no-block UNKNOWN.
  - Verification: `bash tests/skills/test-aai-doctor.sh` (extended TEST-033
    battery through the real doctor).
- Maps to: CHANGE-0138 AC-002 (F5, ABSENT overload)
  - Spec-AC-02: `resolveCliVersion` returns the D2 tri-state; a resolved
    executable with an empty or failed `--version` reports present true,
    version null, named reason; stderr text never appears as a version.
  - Verification: `bash tests/skills/test-aai-doctor.sh` (fake-CLI fixtures:
    stderr-only, empty-output, absent).
- Maps to: CHANGE-0138 AC-003 (F6, absent vs unknown on the line)
  - Spec-AC-03: the CAT-16 one-line reason composes per D2 — unknown probes
    appear as their own `, N unknown` segment and never deflate or inflate the
    present count; present-no-version is named by the `without version`
    segment.
  - Verification: `bash tests/skills/test-aai-doctor.sh` (mixed-state PATH
    fixture incl. a hanging CLI).
- Maps to: CHANGE-0138 AC-004 (BOM parity)
  - Spec-AC-04: a UTF-8 BOM no longer hides a first-line column-0 key from
    either parser; the twin-identical strip lands in BOTH files in one commit
    and is pinned behaviorally on both sides plus structurally.
  - Verification: `bash tests/skills/test-aai-update.sh` and
    `bash tests/skills/test-aai-update-check.sh`.
- Maps to: CHANGE-0138 AC-005 (config/retention honesty)
  - Spec-AC-05: an exists-but-unreadable config yields one named stderr
    degrade line and still defaults on (ENOENT stays silent); prune failures
    yield at most one stderr line per run naming the first undeletable path;
    stdout keeps exactly one line and exit stays 0 in every arm.
  - Verification: `bash tests/skills/test-aai-update.sh` (EISDIR config arm,
    directory-shaped report arm).
- Maps to: CHANGE-0138 AC-006 (tests, docs, frozen contracts)
  - Spec-AC-06: new tests registered and selected; product docs tell the new
    truth; doctor exit map, CAT-16 PASS-only status, helper one-line contract
    and zero-network pins all still hold.
  - Verification: `node .aai/scripts/check-test-registration.mjs`,
    `bash tests/skills/test-aai-doctor.sh`,
    `bash tests/skills/test-aai-update.sh`,
    `bash tests/skills/test-aai-update-check.sh`,
    `bash tests/skills/test-aai-hygiene-pack.sh`.

## Constitution deviations

None.

- Article 1 (Evidence before claims) — every AC names one command and one
  observable; D5 forbids any nothing-downstream residue.
- Article 2 (Simplicity) — no new file, no shared-helper abstraction (D3
  records the rejection), no speculative config surface.
- Article 3 (Portability) — all fixtures are plain files; the failure
  injections (EISDIR config, directory-shaped report) work identically on
  macOS, Linux and Windows; all emitted strings are ASCII.
- Article 4 (Degrade and report) — this scope IS article 4: unreadable config,
  prune failure, unknown probe and no-Commands-block all become named,
  bounded reports instead of silence or fabrication.
- Article 5 (Additive first) — exit maps, line cardinalities and JSON keys are
  preserved; the one widening (`present` may be the string UNKNOWN) replaces
  the ad-hoc `unknown: true` flag, is confined to `--json` detail, and is
  documented in the product doc.
- Articles 6 and 7 — untouched.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN codex --help output is probed THEN the exec observation is derived only from Commands:/Subcommands: blocks per D1 — a column-0 header line, an indented block bounded by the next non-empty column-0 line, and an exec row whose token is exactly exec with tab or single-space or wider separators all accepted — and WHEN no such header exists anywhere THEN available is the literal UNKNOWN with a reason naming the missing block; the 11-fixture battery of D1 produces exactly the expected verdict per fixture, flipping FX-01 and FX-07 away from true, FX-03 and FX-04 to true, and FX-10 to UNKNOWN | planned | — | — | fixtures run through the REAL doctor via PATH-injected fake codex, never a unit-mocked parser |
| Spec-AC-02 | WHEN an agent CLI resolves on PATH and its --version yields no non-empty first stdout line THEN its record reports present true, version null and a named reason, and WHEN it does not resolve THEN present false with reason not found on PATH, and WHEN the probe times out or fails to spawn for a non-ENOENT cause THEN present is the literal UNKNOWN with a named reason; every record carries the same three fields present, version, reason; no stderr text is ever presented as a version string | planned | — | — | deletes the stdout-or-stderr fallback and the ad-hoc unknown flag; TEST-026 assertions updated in the same commit |
| Spec-AC-03 | WHEN CAT-16 composes its one-line reason THEN the present count uses strict equality on present true, a non-zero present-without-version count appears as a parenthesized without version segment, a non-zero unknown count appears as a comma-separated N unknown segment, a timed-out or unreadable probe is never folded into absence, and the capability tail plus the PASS-only category status and the doctor exit map are byte-preserved | planned | — | — | ASCII only; CAT-16 can still never emit WARN or FAIL |
| Spec-AC-04 | WHEN docs/ai/update-config.yaml begins with a UTF-8 BOM immediately followed by a column-0 key on line one THEN update-doctor-report.mjs honors that key (BOM plus post_update_doctor off prints the exact disabled line and writes no report) AND update-check.mjs honors that key (BOM plus mode auto resolves effective_mode auto on the throttled fast path) — fixed in both files together via the byte-identical strip statement of D3, pinned behaviorally on each parser and structurally across both | planned | — | — | parity invariant, SEAM-3 of SPEC-0124; neither file may be fixed or reverted alone |
| Spec-AC-05 | WHEN the config path exists but cannot be read (any readFileSync error other than ENOENT, proven with a directory-shaped config) THEN update-doctor-report.mjs emits exactly one stderr WARNING naming the path and the error code and behaves as on, while an absent file stays silent-on; AND WHEN retention prune cannot delete one or more shaped reports (proven with a directory-shaped report name) THEN exactly one stderr line per run names the first failed path and the count of additional failures; in every arm stdout carries exactly one line, the exit code is 0, and a fully writable run adds zero new stderr | planned | — | — | D4 budget: at most one prune line plus at most one config line per run |
| Spec-AC-06 | WHEN the hygiene commands run THEN check-test-registration.mjs reports the new test functions clean, the doctor and update suites pass end to end, the existing exit-matrix, zero-network and one-stdout-line pins still hold unmodified in their contracts, docs/product/aai-doctor.md documents the tri-state and unknown-vs-absent line semantics, docs/product/aai-update.md documents the BOM tolerance and the named config/prune degrade lines, and CHANGELOG.md carries one unreleased heading entry for this scope | planned | — | — | no suite-map or PROFILES change is owed (no new file) |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:

- `.aai/scripts/aai-doctor.mjs` — `probeCodexExecSubcommand` replaces the
  line-anchored regex with the D1 block parse (three distinct reason strings);
  `resolveCliVersion` returns the D2 tri-state record; `catAgentCliProbe`
  composes the new count line from strict-equality tallies. No other category
  and no CLI surface changes.
- `.aai/scripts/update-doctor-report.mjs` — the D3 strip line in
  `resolvePostUpdateDoctor`; ENOENT-vs-other split in its catch (one stderr
  WARNING for the non-ENOENT arm, unchanged silent default for ENOENT);
  `pruneReports` collects failures and emits the single D4 line.
- `.aai/scripts/update-check.mjs` — the byte-identical D3 strip line in
  `resolveConfig`. Nothing else moves in this file.
- `tests/skills/test-aai-doctor.sh` — TEST-033 grows into the 11-fixture
  battery; new functions for the tri-state fixtures and the count-line
  composition (a sleeping fake CLI drives the timeout/UNKNOWN arm); TEST-026
  assertions updated to the tri-state shape; the documentation pin extended to
  the new product-doc truths. All bash pins use here-strings, never pipes into
  the assertion (the suite runs under set -euo pipefail).
- `tests/skills/test-aai-update.sh` — new 0138-labelled functions: BOM arm for
  the helper, structural twin pin over both .mjs files, EISDIR config arm,
  prune-failure arm (directory-shaped report), one-stdout-line re-assertion in
  every new arm.
- `tests/skills/test-aai-update-check.sh` — BOM arm for `resolveConfig`
  (BOM plus mode auto on the throttled fast path, zero network).
- `docs/product/aai-doctor.md` — CAT-16 tri-state and unknown-vs-absent line
  semantics, honest-UNKNOWN for the exec observation.
- `docs/product/aai-update.md` — BOM tolerance, named unreadable-config and
  prune degrade lines and their one-line budgets.
- `CHANGELOG.md` — one `## [unreleased] — <title>` heading entry (per-entry
  heading convention; the aai-release cut refuses bullets under a scaffold).

Data flows and edge cases:

- codex `--help` text crosses a process boundary into the block parser; CRLF
  output must parse identically (split tolerant of `\r`).
- The `clis` record shape crosses from `resolveCliVersion` into the count line
  AND into the field report (update-doctor-report embeds doctor JSON
  verbatim), so the shape change and the line change are asserted from the
  same real `--json` run.
- One config file, two parsers (SPEC-0124 SEAM-3): the BOM fix must land in
  both in the same commit.
- A BOM on a NON-first line is not a BOM (it is a ZWNBSP in content) — only
  index 0 is stripped, exactly once.
- The stderr budget lines must never leak into stdout under `set -euo
  pipefail` wrappers: stdout cardinality is re-asserted in every new arm.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description | Status |
|----------|------------|-------------|-----------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-doctor.sh         | The 11-fixture battery of D1: each fixture is a fake codex --help on PATH driven through node .aai/scripts/aai-doctor.mjs --json; asserts the exact expected verdict AND reason class per fixture, including UNKNOWN with the no-Commands-block reason on FX-01 and FX-10. RED on the pre-change tree: FX-01/FX-07 true, FX-03/FX-04 false, FX-10 false. Command: bash tests/skills/test-aai-doctor.sh | pending |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-doctor.sh         | Tri-state fixtures through the real doctor: a fake CLI printing its version to stderr only reports present true, version null, named reason, and the stderr text appears nowhere in the CAT-16 detail as a version; a fake CLI printing nothing reports present true, version null; an empty PATH reports present false with reason not found on PATH; every record carries all three fields. Command: bash tests/skills/test-aai-doctor.sh | pending |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-doctor.sh         | Count-line composition: PATH carrying one versioned fake claude, one no-stdout fake codex and one sleeping fake gemini yields the CAT-16 reason segment 2/3 agent CLI(s) present (1 without version), 1 unknown with status PASS and the capability tail unchanged; an all-versioned PATH yields 3/3 with neither optional segment. Command: bash tests/skills/test-aai-doctor.sh | pending |
| TEST-004 | Spec-AC-04 | unit        | tests/skills/test-aai-update.sh         | BOM behavioral pin, helper side: a config whose first bytes are EF BB BF then post_update_doctor: off yields the exact disabled-by-config line, no report, exit 0, exactly one stdout line. RED pre-change: the doctor runs and a report is written. Command: bash tests/skills/test-aai-update.sh | pending |
| TEST-005 | Spec-AC-04 | unit        | tests/skills/test-aai-update-check.sh   | BOM behavioral pin, update-check side: a config of BOM then mode: auto plus a fresh throttle cache and --now resolves effective_mode auto with throttled true (zero network) under --json; the structural twin pin in tests/skills/test-aai-update.sh asserts the byte-identical strip statement exists in BOTH .mjs files so neither side can drift alone. Commands: bash tests/skills/test-aai-update-check.sh and bash tests/skills/test-aai-update.sh | pending |
| TEST-006 | Spec-AC-05 | unit        | tests/skills/test-aai-update.sh         | Unreadable-config honesty: --config pointing at a DIRECTORY yields exactly one stderr WARNING naming the path and the error code, still runs the doctor (default on), one stdout line, exit 0; an absent config stays stderr-silent. RED pre-change: zero stderr on the directory arm. Command: bash tests/skills/test-aai-update.sh | pending |
| TEST-007 | Spec-AC-05 | unit        | tests/skills/test-aai-update.sh         | Prune-failure budget: a reports directory holding max-reports shaped files plus an OLDER directory-shaped name yields exactly one stderr line naming that path, while the shaped FILES beyond the cap are still pruned, stdout carries exactly one line and exit is 0; a fully writable run emits zero prune stderr. RED pre-change: zero stderr, failure swallowed. Command: bash tests/skills/test-aai-update.sh | pending |
| TEST-008 | Spec-AC-06 | integration | tests/skills/test-aai-doctor.sh         | Frozen-contract regression: the pre-existing exit matrix, zero-network pins and helper one-stdout-line assertions all still pass with their contracts unmodified, and CAT-16 status is PASS on every battery fixture. Commands: bash tests/skills/test-aai-doctor.sh and bash tests/skills/test-aai-update.sh and bash tests/skills/test-aai-update-check.sh | pending |
| TEST-009 | Spec-AC-06 | integration | tests/skills/test-aai-hygiene-pack.sh   | Registration and hygiene: every new test function is registered, the suite map still selects the touched suites, and the docs pins hold — docs/product/aai-doctor.md states the tri-state and unknown-vs-absent semantics, docs/product/aai-update.md states the BOM tolerance and the degrade-line budgets, CHANGELOG.md carries one unreleased heading for this scope. Commands: node .aai/scripts/check-test-registration.mjs and bash tests/skills/test-aai-hygiene-pack.sh and bash tests/skills/test-aai-doctor.sh | pending |

Test status values: pending -> red -> green

## Seams crossed

- SEAM-A — codex `--help` text crosses from a spawned child into the block
  parser. Unit-testing the regex would test the mock; TEST-001 drives every
  fixture through the real doctor process with a PATH-injected executable.
- SEAM-B — the `clis` record is produced by `resolveCliVersion` and consumed
  by BOTH the count-line composer and the `--json` detail that the field
  report embeds verbatim. TEST-002/TEST-003 assert the detail AND the composed
  line from the same real run, so the two consumers cannot drift apart.
- SEAM-C — one config file, two parsers (SPEC-0124 SEAM-3). TEST-004 and
  TEST-005 produce the same BOM byte sequence and assert the real result on
  each consumer, plus the structural twin pin across both files.
- SEAM-D — the helper's stdout crosses into the update wrappers under
  `set -euo pipefail`; new stderr diagnostics must never change stdout
  cardinality. Every new arm in TEST-004/006/007 re-asserts exactly one
  stdout line, and TEST-008 re-runs the existing wrapper-crossing pins.

## Residual risks (accepted)

- RR-1 — other column-0 scanners in the repo (for example
  `.aai/scripts/lib/guard-config.mjs`) share the BOM class. The recorded
  parity invariant names exactly the two update parsers; a repo-wide BOM sweep
  is a separate scope, noted here so it is a decision, not an omission.
- RR-2 — a codex `--help` with a localized or renamed command-list header
  yields honest UNKNOWN, never a fabricated boolean. That is the designed
  degrade direction.
- RR-3 — prose INSIDE a genuine Commands: block whose first token is `exec`
  would still read true. Not a shape clap emits; accepted.
- RR-4 — the sleeping-CLI arm adds one 5-second timeout wait to each
  test-aai-doctor.sh run.
- RR-5 — `present` widening from boolean to boolean-or-UNKNOWN is visible to
  any downstream consumer of the embedded field-report JSON; consumers must
  treat non-true as not-present. Confined to `--json` detail, documented in
  docs/product/aai-doctor.md.

## Verification

Commands to run:

- `bash tests/skills/test-aai-doctor.sh`
- `bash tests/skills/test-aai-update.sh`
- `bash tests/skills/test-aai-update-check.sh`
- `bash tests/skills/test-aai-hygiene-pack.sh`
- `node .aai/scripts/check-test-registration.mjs`
- `node .aai/scripts/aai-doctor.mjs` and `node .aai/scripts/aai-doctor.mjs --json`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-doctor-honesty-batch.md`
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`

Evidence artifacts: stored RED logs under `docs/ai/tdd/` for the TDD-lane
AC-gating tests (TEST-001, TEST-002, TEST-003, TEST-004, TEST-006, TEST-007);
the recorded RED observation for the loop-lane rows; full stdout with exit
codes for every command above.

PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status. Per
D5, a `planned` row at validation time is a defect of this spec, not a
by-design wait: nothing in this batch depends on CI, Windows or the network.

## Evidence contract

For each implementation, validation, TDD, and code review artifact, record:
- ref_id
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

### Evidence by strategy

Strategy is `hybrid`, so the full contract applies: a stored RED artifact
under `docs/ai/tdd/` per AC-gating test on the TDD lane (TEST-001, TEST-002,
TEST-003, TEST-004, TEST-006, TEST-007), plus the full verification matrix
above. For the loop-lane rows (TEST-005 structural half, TEST-008, TEST-009)
the RED observation is the pin failing on the pre-change tree, recorded but
not necessarily stored.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.
