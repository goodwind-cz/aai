---
id: spec-cli-output-survives-a-pipe
type: spec
number: 139
status: implementing
ceremony_level: 1
links:
  requirement: docs/issues/CHANGE-0153-cli-output-survives-a-pipe.md
  rfc: null
  pr: []
  commits: []
---

# Spec — CLI output must survive being piped

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0153-cli-output-survives-a-pipe.md
- Surface that changes (the only one): .aai/scripts/follow-ups.mjs
- Suite that gates this scope: tests/skills/test-aai-follow-ups.sh
- Prior spec owning that surface: docs/specs/SPEC-0129-spec-followup-registry.md
- Prior spec owning that surface: docs/specs/SPEC-0135-spec-followups-cli-hardening.md
- Registry item this closes: fu-followups-json-truncated-on-pipe (P2)
- Technology contract: docs/TECHNOLOGY.md

Ceremony justification: level 1. One production file, one existing suite, no new
file anywhere, no schema, no dependency, no `protected_paths_l3` path, and no
output-format change of any kind (Spec-AC-05 pins that byte-for-byte). The
intake fixed the acceptance criteria and the diagnosis was settled by
measurement before planning began, so Planning froze them rather than reopening
the approach.

## Summary

`.aai/scripts/follow-ups.mjs` ends every one of its ten exit paths with
`console.log(...)` (or `process.stderr.write(...)`) immediately followed by
`process.exit(<code>)`. To a FILE that is correct: Node's stdout is synchronous
on a regular file, so the write has completed by the time `process.exit` runs.
To a PIPE it is not: the write is asynchronous, only what the pipe buffer
accepted has reached the kernel, and `process.exit` discards the queued
remainder.

Measured on this repository on 2026-08-20, before any change:

- `list --json` to a file: **87012 bytes**, exit 0.
- `list --json` into `cat`: **65536 bytes** — exactly one pipe buffer.
- `list --json` into a `JSON.parse` reader: `Unterminated string in JSON at
  position 65522`.
- `list --json --ledger <synthetic 295252-byte ledger>` to a file: **495293
  bytes**; into `cat`: **65536 bytes**.

That the loss lands on exactly 65536 is the diagnosis. It is a pipe buffer, not
a data defect, and it makes this a silent-corruption defect at the READ side:
any caller that pipes the registry into a parser reads a prefix of the backlog,
derives wrong counts, and is told nothing.

Two things about the human listing are worth stating exactly, because a casual
measurement reads them backwards:

1. Through a FAST reader the human listing did NOT truncate before the change.
   `list --ledger <synthetic>` was 139071 bytes both to a file and into `cat`.
   That is not health, it is scheduling: the human branch emits one
   `console.log` per row, each small enough that `cat` drains it before the next
   arrives, so almost every write completes synchronously.
2. Through a SLOW reader the same command truncated at **65421 of 139071 bytes**
   before the change. A reader that does not drain immediately is the ordinary
   case for a parser, a pager, or any consumer doing work per chunk. So the
   human branch carries the identical defect, and the only reason the intake
   could call it "latent" is that the live listing is 35101 bytes today.

This is why the Spec-AC-02 arm reads through a deliberately SLOW reader: a
`cat`-based assertion on the human branch would pass on the unfixed tree and
prove nothing.

## Design decisions

- **D1 — the fix is structural, at the exit, not per call site.** A per-site
  flush (buffer the payload, `fs.writeSync(1, ...)` with an EAGAIN retry loop)
  would keep `process.exit` and have to be repeated, correctly, at ten sites and
  at every site added later. Instead there is exactly one way for this CLI to
  end: `exit(code)` throws an `ExitSignal`, and `runMain` catches it, assigns
  `process.exitCode = code`, and returns. Node then exits by the ordinary route,
  which is after the event loop has drained stdout and stderr. All ten
  `process.exit(<code>)` calls become `exit(<code>)`; no other statement in any
  of the ten paths moves.

- **D2 — throwing is safe here because no `catch` in this file wraps a call to
  `exit()`.** Checked site by site: the three `try` blocks in
  `readDecisionsLedger`, `appendLine` and `requireReadableLedger` wrap
  `fs.readFileSync`, `fs.statSync`, `fs.openSync` and `fs.accessSync` only, and
  the two `usageError` calls inside `requireReadableLedger` sit in the CATCH
  arms, not in the try bodies. An `ExitSignal` therefore always reaches
  `runMain`. `runMain` re-throws anything that is not an `ExitSignal`, so a
  genuine programming error is still a crash and not a silent exit 0.

- **D3 — the exit code is preserved exactly, including the code raised from
  inside argument parsing.** `usageError` throws through `parseArgs`, `main` and
  `runMain` to `process.exitCode = 2`; the two help paths reach 0 the same way;
  `cmdAdd` and `cmdClose` reach 1 on an unproven post-append re-read. Nothing in
  this file opens a timer, a socket, a watcher, or a stdin read, so once the
  streams have drained there is no handle left to keep the process alive and
  nothing to hang on. `process.exitCode` is also never overwritten later,
  because `runMain` returns immediately after setting it.

- **D4 — a reader that closes early is the reader's choice, not a tool failure,
  and the guard that keeps it that way is load-bearing on the STDERR path
  only.** Once `process.exit` no longer discards the pending writes, a reader
  that closes the pipe makes the remaining writes fail with `EPIPE`. Unhandled,
  that is an `error` event on the stream, which Node turns into an uncaught
  exception: exit 1 plus a stack trace. `installPipeGuard` attaches one `error`
  listener to each of `process.stdout` and `process.stderr` that ends the
  process with the code already meant (`process.exitCode`, defaulting to 0) on
  `EPIPE` and `ERR_STREAM_DESTROYED`, and re-throws anything else.
  `process.exit` is correct in that one handler and nowhere else: the far end is
  gone, so there is nothing left to flush.

  Which half of that is actually falsifiable was MEASURED, not assumed, and the
  answer is not the obvious one. Node's global `console` is constructed with
  `ignoreErrors: true`, so every `console.log` in this file already swallows
  EPIPE by itself: `list --json` into `head -n 1` exits 0 with an empty stderr
  with the guard removed, six runs out of six. The two `process.stderr.write`
  sites get no such treatment. With stderr merged into the same pipe and the
  reader gone before the write, the guard makes the difference between the code
  the caller should read and a crash:

  - with the guard: a usage error exits **2**, six runs out of six;
  - without it: the same usage error exits **1**, six runs out of six.

  That is the regression this change would have introduced if the guard were
  left out — a caller reads `1` and cannot tell a usage error from a write
  failure — and TEST-021(c) is the arm that holds it. Contrast measured with a
  bare `node -e 'process.stdout.write(<5 MB>)'` into an early-closing reader,
  which does exit 1 with a stack trace: the protection on the stdout path comes
  from `console`, not from Node's streams in general, so a later edit that
  switched a `console.log` here to a direct `process.stdout.write` would need
  this listener.

- **D5 — what this does NOT promise.** A reader that neither drains nor closes
  (`list --json` into `sleep 100`) now BLOCKS instead of truncating. That is the
  correct POSIX behaviour of every well-behaved writer and it is what
  `cat <bigfile>` does; before this change the command "did not block" only
  because it threw the unread remainder away. Spec-AC-04 is scoped to the
  early-CLOSE case, which is the one that occurs in practice.

- **D6 — no output format changes, and that is asserted rather than intended.**
  The change touches only the statement that ends each path. Spec-AC-05 pins the
  file-directed bytes of `list`, `list --json`, `add` and `close` (plus
  `--help`, the usage error and the idempotent re-close) before and after,
  byte-for-byte, and TEST-022 additionally pins the literal shape of each
  message inside the suite so a later edit cannot drift it unnoticed.

- **D7 — the same pattern elsewhere is filed, not fixed.** Other scripts under
  `.aai/scripts/` end the same way. A repo-wide sweep is its own scope; this
  ride touches one file. The sweep is filed as a follow-up.

## Implementation strategy
- Strategy: direct
- Rationale: recorded in STATE as `direct` before this ride began. The behaviour
  is "end the process a different way"; there is no algorithm to discover and no
  interface to negotiate. What can go wrong is entirely in the wiring — a
  swallowed throw, a changed exit code, an EPIPE turning into a crash, a handle
  that keeps the process alive — and wiring is proven by running the real CLI
  through a real pipe. Direct does not waive the failing-first observation: see
  the discipline paragraph under the Test Plan.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: two files, one of them a test suite, no
  `protected_paths_l3` path, and every fixture is a scratch ledger passed with
  `--ledger`. The live `docs/ai/decisions.jsonl` is READ by the demonstration
  and never written by it.
- User decision: undecided
- Base ref: main
- Inline review scope: .aai/scripts/follow-ups.mjs,
  tests/skills/test-aai-follow-ups.sh,
  docs/specs/SPEC-0139-spec-cli-output-survives-a-pipe.md,
  docs/issues/CHANGE-0153-cli-output-survives-a-pipe.md

Code review required: true (production script and test-suite change); scope =
the explicit path list above as a diff against main.

## Acceptance Criteria Mapping

- Maps to: CHANGE AC-001
- Spec-AC-01: `list --json` written into a pipe whose reader is a JSON parser
  yields a document that parses, at a payload above 64 KB, on both the LIVE
  ledger and a synthetic ledger whose `--json` payload is at least 174080 bytes.
  The parsed document is checked for its expected item count, so a reader that
  received an empty or otherwise degenerate document cannot pass the arm.
  - Verification: `bash tests/skills/test-aai-follow-ups.sh test_018_json_survives_a_pipe`.
    Evidence: the arm's stdout, naming both measured payload sizes and both item
    counts.

- Maps to: CHANGE AC-002
- Spec-AC-02: for both `list --json` and the human `list`, at a payload above
  64 KB, the byte count a reader receives equals the byte count the same command
  writes to a file. Measured against a reader that does NOT drain immediately,
  because a fast reader hides the defect on the human branch (see Summary
  point 1).
  - Verification: `bash tests/skills/test-aai-follow-ups.sh test_019_pipe_bytes_equal_file_bytes`.
    Evidence: the arm's stdout, naming the file size and the received size for
    each of the two branches.

- Maps to: CHANGE AC-003
- Spec-AC-03: every documented exit code still comes out, and none of them
  hangs. Exit 0 for `list`, `add`, `close`, an idempotent re-close and `--help`;
  exit 1 for a `close` whose post-append re-read is shadowed by a later-dated
  status record for the same id; exit 2 for an unknown subcommand, an unknown
  flag, a missing flag value and an unknown id on `close`. Each is run under a
  wall-clock bound so a process kept alive by a stray handle fails the arm
  instead of hanging the suite.
  - Verification: `bash tests/skills/test-aai-follow-ups.sh test_020_exit_codes_survive_the_flush`.
    Evidence: the arm's stdout, naming each case and the code observed.

- Maps to: CHANGE AC-004
- Spec-AC-04: `list --json` whose reader is `head -n 1` exits 0, writes nothing
  to stderr, and completes inside the same wall-clock bound. The reader still
  receives its first line, so the arm cannot pass by the writer producing
  nothing. And a usage error whose output pipe was closed BEFORE the write
  still exits 2 rather than the 1 an unhandled EPIPE would report — the half of
  this criterion that the change could actually have broken (D4).
  - Verification: `bash tests/skills/test-aai-follow-ups.sh test_021_early_close_is_not_a_failure`.
    Evidence: the arm's stdout, naming the writer's exit code, the stderr byte
    count, the first line the reader received, and the closed-pipe usage code.

- Maps to: CHANGE AC-005
- Spec-AC-05: no output format changes. The bytes written to a FILE are
  identical before and after the change for `list`, `list --json`, `add` and
  `close`. Two independent instruments: a whole-ride before/after capture
  diffed byte-for-byte outside the suite, and an in-suite pin of the literal
  message shapes so a later edit cannot drift them unnoticed.
  - Verification: `bash tests/skills/test-aai-follow-ups.sh test_022_output_format_is_pinned`,
    plus the ride's before/after capture diff. Evidence: the arm's stdout and
    the `diff -r` result over the two capture directories.

## Constitution deviations

None. Checked v1 articles 1 to 7.

Article 1 (evidence before claims): every Spec-AC names one executable command
and one read observable, and each new assertion is mutation-proved with an
unmutated green control. Article 2 (simplicity): no new file, no new dependency,
no configuration; one throw-based exit and one stream error listener. Article 3
(portability): Node stdlib only, bash 3.2 in the suite. Article 4 (degrade and
report): an early-closing reader is handled explicitly and named in the design
rather than silently swallowed, and a non-EPIPE stream error is still re-thrown.
Article 5 (additive first): every exit code, every message and every byte of
output is unchanged, which Spec-AC-05 asserts rather than assumes. Article 6
(single-writer state): no STATE write. Article 7 (operator-only merge): no merge
is performed.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-018 | Spec-AC-01 | int  | tests/skills/test-aai-follow-ups.sh | `list --json` written into a pipe read by a `JSON.parse` reader, on a synthetic ledger whose payload is at least 174080 bytes and on the LIVE `docs/ai/decisions.jsonl`; both must parse, the synthetic one must report the exact item count seeded, and the arm prints both measured payload sizes. When the live payload is at or below 65536 bytes the arm says so on stdout and the synthetic half carries the threshold claim | green |
| TEST-019 | Spec-AC-02 | int  | tests/skills/test-aai-follow-ups.sh | the same synthetic ledger run twice per branch: once redirected to a file, once into a reader that waits 400 ms before it reads a byte; the received count must equal the file count for `list --json` AND for the human `list`, and both payloads must exceed 65536 bytes so the comparison is above the pipe buffer. The slow reader is what makes the human branch bite: through `cat` it passed on the unfixed tree | green |
| TEST-020 | Spec-AC-03 | int  | tests/skills/test-aai-follow-ups.sh | eleven invocations under a 20-second wall-clock bound, one per documented code: `list`, `add`, `close`, idempotent re-close, `--help` and `help` at 0; a shadowed `close` at 1; unknown subcommand, unknown flag, missing flag value and unknown id on `close` at 2. A bound breach is a failure, not a hang | green |
| TEST-021 | Spec-AC-04 | int  | tests/skills/test-aai-follow-ups.sh | three sub-arms under the same bound. (a) `list --json` on the oversized ledger with `head -n 1` as its reader: writer exits 0, stderr empty, reader received a first line that is an opening brace, so the arm cannot pass by the writer producing nothing. (b) the same on the human listing, whose first line is the count header. (c) the falsifiable one: a usage error with stderr merged into a pipe whose reader is gone before the write must still exit 2 rather than the 1 an unhandled EPIPE reports — (a) and (b) pass with no guard at all because Node's global console already ignores EPIPE, and (c) does not | green |
| TEST-022 | Spec-AC-05 | int  | tests/skills/test-aai-follow-ups.sh | the literal output shapes of the four commands are pinned: the `list` header line, a `list` row's field order, the `list --json` top-level key set and its two-space indentation, the `add` confirmation line and the `close` confirmation line, each matched against a frozen pattern; and for each of `list` and `list --json` the file-directed bytes equal the pipe-received bytes on the same above-buffer fixture, read through the same 400 ms slow reader TEST-019 uses — through a fast reader the human leg delivered its full byte count even on the unfixed tree, so it could not have gone red | green |

Failing-first discipline (strategy `direct`, so exit codes are the record).
Three arms fail NATURALLY on the pre-change tree — TEST-018, TEST-019 and
TEST-022 — because each of them measures a payload above 64 KB through a pipe,
which the pre-change tree truncates. Measured on the unfixed tree on macOS and
in a Linux container (round-1 validation). The other two do NOT fail there and
are not claimed to: TEST-020's exit codes are unchanged by the fix, and
TEST-021 is GREEN pre-change because the regression it guards is one the fix
itself would introduce (D4) — it is proved by MUTATION only, by making
`installPipeGuard` a no-op, which turns TEST-021 red and nothing else. The
load-bearing evidence is
MUTATION with an unmutated green control, recorded in the Implementation return
record: for each new assertion, one named single-point mutation of the shipped
code that turns exactly the expected arm red while the control run is green. An
assertion verified only by reading is not accepted.

## Verification

- `bash tests/skills/test-aai-follow-ups.sh` exits 0 with every arm passing
- every suite `node .aai/scripts/select-suites.mjs --files-from <changed files>`
  returns
- `node .aai/scripts/spec-lint.mjs` clean,
  `node .aai/scripts/check-test-registration.mjs` clean,
  `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- the live-ledger demonstration: `node .aai/scripts/follow-ups.mjs list --json`
  read through a pipe by `JSON.parse` succeeds
- the before/after capture diff for Spec-AC-05
- `git rev-parse HEAD` and `git status --porcelain=v1 -uno` line count at the
  start and end of the ride

## Evidence contract

- The suite's stdout, with the measured byte counts printed by TEST-018,
  TEST-019 and TEST-021 rather than asserted as constants.
- The pre-change and post-change pipe-versus-file measurements on the live
  ledger and on the synthetic one.
- The `diff -r` result over the before/after capture directories for
  Spec-AC-05.
- For every new assertion: the mutation applied, the arm that went red, and the
  unmutated control run that stayed green.
- The `git rev-parse HEAD` and `git status --porcelain=v1 -uno` pair for the
  whole ride.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN `list --json` is read through a pipe by a JSON parser at a payload above 64 KB THEN the document parses, on the live ledger and on a synthetic ledger of at least 174080 bytes of payload | implementing | TEST-018 green; live 87012 bytes / 84 items and synthetic 310698 bytes / 500 items both parsed whole through a pipe. Ride-level on an 800-entry fixture: 495293 bytes parsed after, 65536 bytes and a parse failure before | — | before the change the same two commands delivered exactly 65536 bytes and failed at position 65522; the 64 KB landing is the diagnosis, since it is the pipe buffer rather than anything about the data | 
| Spec-AC-02 | WHEN the payload exceeds 64 KB THEN the byte count a reader receives equals the byte count written to a file, for `list --json` and for the human listing | implementing | TEST-019 green; 310698 equals 310698 for `--json` and 87994 equals 87994 for the human listing, both through a 400 ms slow reader. Under the reverted-exit mutations the same reader got 65536 and 65524 | — | the human branch measured 139071 both ways through `cat` even BEFORE the change, and 65421 of 139071 through a slow reader, so a `cat`-based arm would have been vacuous here; the arm therefore reads slowly on purpose | 
| Spec-AC-03 | WHEN any subcommand exits THEN it exits with the code it did before, and does not hang | implementing | TEST-020 green over eleven invocations under a 20-second bound | — | the risk the fix most easily gets wrong: dropping `process.exit` can change the code or leave a handle alive. Nothing in this file opens a timer, socket, watcher or stdin read, and `runMain` returns immediately after setting `process.exitCode`, so the drain is the last thing that happens | 
| Spec-AC-04 | WHEN the reader closes the pipe early THEN the writer neither hangs nor reports a tool failure | implementing | TEST-021 green over three sub-arms; writer exit 0 and stderr 0 bytes on both listing branches, first line received, and a usage error into an already-closed pipe still exits 2 | — | this is the regression the fix itself introduces if EPIPE is left unhandled, and WHERE it bites was measured rather than assumed. Node's global console is built with ignoreErrors, so the `console.log` branches survive an early close with the guard removed (six runs out of six); the two `process.stderr.write` sites do not, and there the usage code 2 silently became 1. One `error` listener per stream closes it. A reader that neither drains nor closes now BLOCKS rather than truncating, which is correct POSIX behaviour and is stated in D5 rather than hidden | 
| Spec-AC-05 | WHEN the output goes to a file THEN it is byte-identical before and after the change, for `list`, `list --json`, `add` and `close` | implementing | `diff -r` over the before/after capture directories clean on all stdout, stderr and exit-code files; TEST-022 green on the in-suite format pins. Its byte-equality half reads through the same 400 ms slow reader as TEST-019 and is mutation-proved on BOTH legs: under M5 (only the human branch reverted to `process.exit`) the arm goes RED with a pipe delivering 65527 bytes against 87997 written to a file, and the unmutated control run of the same arm is green | — | the capture also covers `--help`, `help`, the usage error, the unknown-id `close` and the idempotent re-close. The only difference between the two capture directories is the fixture ledger's own `ts` values, which are wall-clock and not stdout | 

Status values: planned | implementing | done | deferred | blocked | rejected

Every row reads `implementing` until the close ceremony. This is measured
rather than preferred: `docs-audit`'s false-open heuristic fails CLOSED on a
fully terminal AC Status table whose delivery is un-timestampable — no delivery
commit, no `ac_evidence` event — and reports `probable-false-open`, which
removes the literal `CLEAN` token from the audit output and turns
`tests/skills/test-aai-doc-numbering.sh` TEST-013 red. The same reasoning is
recorded in SPEC-0137 and SPEC-0138 and tracked as
`fu-acgate-vs-falseopen-catch22`. The rows flip at the close ceremony, and the
flip must PRECEDE `close-work-item.mjs` rather than follow it
(`fu-ac-flip-must-precede-close`).

## Implementation plan

Components:

- `.aai/scripts/follow-ups.mjs` (EDIT) — one `ExitSignal` class, one `exit()`
  helper, one `installPipeGuard()` and one `runMain()`; the ten
  `process.exit(<code>)` call sites become `exit(<code>)`; the entry point calls
  `runMain()` instead of `main()`. The header's EXIT CONTRACT block gains the
  paragraph explaining why. No other statement changes.
- `tests/skills/test-aai-follow-ups.sh` (EDIT) — five new arms TEST-018 to
  TEST-022, three small helpers (a bounded runner, a pipeline runner that keeps
  both exit codes, and an oversized-ledger fixture builder), and the five new
  functions wired into `main()`.

Companion obligations (closed list). PROMPT CORPUS BYTES MOVE: NO — no
`.aai/*.prompt.md` and no `.aai/AGENTS.md` byte change, so no prompt-diet ledger
true-up is owed. NEW `.aai/**` FILE: NO — the change is inline in an existing
script, so no `.aai/system/PROFILES.yaml` classification is owed. The mechanical
obligation that DOES apply: every new `test_*` function must be wired into
`main()` (`.aai/scripts/check-test-registration.mjs`). No new suite, so
`tests/skills/suite-map.yaml` needs no new row — `aai-follow-ups` already globs
both changed paths.
