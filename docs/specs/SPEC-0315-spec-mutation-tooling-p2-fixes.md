---
id: spec-mutation-tooling-p2-fixes
type: spec
number: 315
status: done
mutation_gate: v1
frozen_sha256: 55aed7c77b728aa4e5aaffb3162b0d71961dd7a021a673ed1af531f688382e13
ceremony_level: 2
links:
  requirement: mutation-tooling-p2-fixes
  rfc: null
  pr: []
  commits: []
---

# Mutation tooling: close the ten open P2 follow-ups

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-0269-mutation-tooling-p2-fixes.md (owner
  brief 2026-11-25).
- Prior scopes whose frozen text or tests this scope changes (see D-AMEND):
  docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md (D2 rotated-record
  name, D12 close semantics for an absent evidence tree, and the rotated-name
  expectations of TEST-474, TEST-492 and TEST-500).
- Prior scopes that only describe an open follow-up in their residual-risk
  prose (history, not a contract; not amended): SPEC-0182 (TEST-553 note on
  the `m` flag), SPEC-0187 (Residual risks, `fu-mutation-sed-drops-multiline-flag`),
  SPEC-0278 (mutation anchor note).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 22 floor,
  bash 3.2 suites run through `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: every item has a defect that was observed on the unchanged
  tree (see Measurements), so every test can be watched failing first. The
  tooling is the layer that proves other tests can fail; its own fixes are
  held to the same RED-then-GREEN rule.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound ride touching five scripts and five suites;
  the main checkout is shared with other sessions.
- User decision: worktree (owner brief 2026-11-25 named the path)
- Base ref: origin/main at a83f7b0f
- Worktree branch/path: fix/p2-mutation-tooling at
  /Users/ales/Projects/aai-worktrees/p2-mutation-tooling
- Review required: true
- Review scope (explicit paths): .aai/scripts/mutation-run.mjs;
  .aai/scripts/mutation-gate.mjs; .aai/scripts/lib/mutation-record.mjs;
  .aai/scripts/close-work-item.mjs; .aai/scripts/spec-lint.mjs;
  .aai/scripts/spec-freeze.mjs; tests/skills/lib/close-work-item-pin.sh;
  tests/skills/test-aai-mutation-gate.sh;
  tests/skills/test-aai-close-work-item.sh; tests/skills/test-aai-spec-lint.sh;
  tests/skills/test-aai-session-lock.sh; tests/skills/test-aai-test-canon.sh;
  docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md; CHANGELOG.md.

## Measurements (origin/main a83f7b0f, 2026-11-25)

All runs below used a throwaway fixture repository under the Planning
scratch directory (cwd inside the fixture), never this checkout, except the
read-only suite and gate probes named as such.

| Item | Follow-up | Measured on the unchanged tree |
|---|---|---|
| 1 | fu-mutation-target-symlink-unchecked | An untracked `lib/link.sh` symlink to the suite, passed as `--target` with a sed that turns the suite's PASS line into `log_fail "TEST-9001 forged"`: exit 0, verdict RED, first_fail `FAIL: TEST-9001 forged`. A forged RED. `--target ../outside.txt` resolves into the clone's temp parent (ENOENT there, exit 2) instead of being refused by name. |
| 2 | fu-mutation-sed-drops-multiline-flag | `s/^const g = 'hello';$/const g = 'bye';/m` on a two-line file: exit 2, "left lib/greeting.mjs byte-identical". The parsed `m` flag is dropped. The live corpus holds 2 cells with an `m` flag and 69 with `g`, and none with `i`, `s`, `u` or `y`. |
| 3 | fu-mutation-selector-vs-bare-dispatch | Of the four named suites, `test-aai-branch-guard.sh`, `test-aai-run-tests.sh` and `test-aai-win-fallback.sh` already strip `test_` (fixed since). `bash tests/skills/test-aai-session-lock.sh test_409` prints `Unknown test: test_409`. A corpus scan for the same idiom found one more suite: `bash tests/skills/test-aai-test-canon.sh test_001` prints `test_test_001: command not found`. Both bare forms (`409`, `001`) pass. |
| 4 and 7 | fu-mutation-patch-consumes-own-source, fu-mutation-run-patch-self-rotate | A `--patch` run records RED; a second run with `--patch docs/ai/tdd/fx-spec/mutation-TEST-9001.patch` (the record's own canonical copy) crashes with a Node stack trace, and the directory then holds only `mutation-TEST-9001.2026-11-25T10:49:06Z.txt` and `.patch`. The canonical record and patch are gone. |
| 5 | fu-mutation-sed-replacement-unescaped | A suite that does not check the target's exit status, and `s/console\.log\(g\)/console.log\(g + 'x'\)/`: the mutated module fails with `SyntaxError: Invalid or unexpected token`, the suite prints its ordinary mismatch FAIL line, and the run records RED at exit 0. A false RED. |
| 6 | fu-mutation-gate-absent-tree-passes | `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0313-spec-node-first-cleanup.md` in this worktree (no evidence tree): `DEGRADED: evidence tree absent degraded=12 uncomparable=0`, exit 0. `close-work-item.mjs` reads exit 0 as no objection. |
| 8 | fu-mutation-overlay-tracked-deletes | A tracked `lib/doomed.txt` deleted in the working tree, plus a tracked binary change that makes `git apply` fail: exit 3, "added: lib/doomed.txt — the clone does not reproduce your tree", after `skipping tracked overlay lib/doomed.txt (ENOENT ...)`. The deletion alone (apply succeeds) records RED but still prints the skip line. |
| 9 | fu-mutation-rotation-colon-path | The rotation in item 4's probe wrote `mutation-TEST-9001.2026-11-25T10:49:06Z.txt`. A colon is invalid in a Windows path. `git ls-files docs/ai/tdd` lists only `docs/ai/tdd/.gitkeep`, so no colon name is tracked today; local gitignored records keep their names. |
| 10 | fu-frozen-mutation-cells-unusable | A tdd draft whose only Mutation cell is `sed:s#a#b#` on lib/x.mjs (a delimiter the shared grammar cannot read): `spec-lint.mjs` reports `LINT PASS`, and `spec-freeze.mjs --dry-run` says it would freeze. Over the 111 gated specs, 1782 of 1930 cells carry a machine-readable declaration; a target path is written in several free-text shapes (`on`, `in`, `target`), so no reliable target can be read from a cell. |

## Decisions

### D1: a mutation target is a regular file inside the repository (item 1)

`mutation-run.mjs` gains `function assertRegularTarget(root, rel) {`. It
throws an `Error` (its return value is never used) when `rel` is absolute,
normalizes to a path that leaves `root`, has a symlink on any path component
under `root` (checked with `lstat`, never followed), or is not a regular
file. It runs on the source tree in the normal run before the clone is
built, and on the clone inside `applyMutation` before any read or write. A
normal-run refusal is exit 2 naming the reason, with no record and no clone
left. A replay refusal is an INCONCLUSIVE row (exit 4 class).

### D2: the sed applier honours every flag the grammar accepts (item 2)

`applySedExpr` builds its RegExp as `new RegExp(parsed.pattern, parsed.flags)`.
That text occurs exactly once in `mutation-run.mjs`. The grammar already
limits flags to `gimsuy`. A duplicated flag makes the RegExp constructor
throw, which the existing caller already turns into exit 2. The `g` and
no-flag behaviour does not change, so the 69 `g` cells replay as before. The
two `m` cells start to anchor per line.

### D3: bare-suffix dispatch is fixed in the two remaining suites and guarded corpus-wide (item 3)

`tests/skills/test-aai-session-lock.sh` strips the prefix with the line
`    t="${t#TEST-}"; t="${t#test_}"` (the idiom `test-aai-run-tests.sh`
already uses). `tests/skills/test-aai-test-canon.sh` dispatches with
`    "test_${arg#test_}" 2>&1 || exit 1`. A static corpus guard in
`tests/skills/test-aai-mutation-gate.sh` fails when any `tests/skills/*.sh`
or `tests/*.sh` file dispatches on a `"test_${VAR}"` expansion (in command
position or after `declare -f`/`declare -F`) without also holding a
`#test_}` strip or a `declare -f "$1"`/`declare -F "$1"` full-name fallback.
The guard has a positive control (a planted bare-only fixture is named) and
a negative control (a stripping fixture is not). A change to
`mutation-run.mjs` itself is not needed: the defect is in the suites, and
the guard keeps the class closed.

### D4: a patch's bytes are read once, before anything rotates (items 4 and 7)

The normal run reads the `--patch` file into memory once, before the clone is
built. `git apply` reads a copy written under the run's temp directory, and
`function storePatchCopy(dir, testId, patchBytes) {` writes those bytes. The
rotation can then move the canonical patch away safely, even when the
`--patch` path is that canonical patch. This one change closes both
follow-ups.

### D5: a mutation that breaks the target's syntax is refused (item 5)

`function parseCheck(file) {` returns `true` when the file parses, `false`
when it does not, and `null` when there is no checker for its extension.
The checkers are `node --check` for `.mjs`, `.cjs` and `.js`, and `bash -n`
for `.sh`. Both are run with an argv array and no shell. `applyMutation`
runs the check on the clone's target before and after writing the mutated
bytes. When the original parses and the mutated file does not, the normal
run refuses at exit 2 with the text `no longer parses` and writes no record,
the same class as the existing byte-identical refusal. A replay counts the
row INCONCLUSIVE. The replacement-escaping rule is unchanged: the
replacement stays literal apart from JavaScript `$` patterns, as `--help`
already says. The preflight is what turns the observed false RED into a
named refusal.

### D6: a close before merge requires the evidence tree (item 6)

Recorded trade-off: wiring the gate into `.github/workflows` was rejected.
The evidence is gitignored (`fu-mutation-evidence-is-gitignored`, P3, out of
scope), so a CI job would read `evidence tree absent` on every run and pass
without checking anything. It would also make this ride ceremony 3.
Instead:

- `mutation-gate.mjs` gains `--require-evidence`. Without the flag nothing
  changes, so SPEC-0181 D9 and SPEC-0187 Spec-AC-06 stay true. With the
  flag, an absent evidence directory is evaluated as an empty one, through
  the guard `if (!evidenceDirExists && !args.requireEvidence) {`. Each
  non-exempt row is then `OFFENDING <TEST-id>: missing record at ...` and
  the exit is 5. Exempt rows stay EXEMPT. An all-exempt plan keeps the
  existing `DEGRADED: every row exempt` exit 0.
- `close-work-item.mjs` passes the flag through
  `function mutationGateArgs(commit) {`. It returns `['--require-evidence']`
  unless the close is post-merge, and `[]` when it is. Post-merge means a
  `--commit` was given and is already an ancestor of the upstream default
  ref. That is the predicate `emitPostMergeCloseWarning` already uses,
  extracted as `function isPostMergeClose(root, commit) {` and shared by
  both. A close in the authoring worktree (the `/aai-pr` step, no
  `--commit`) is a merge criterion, so it now refuses an absent tree under
  `mutation_gate: enforce` (exit 8) and warns under report-only. A
  post-merge close (`close-reconcile.mjs --apply` on main, where the
  worktree's evidence no longer exists) keeps today's behaviour. Refusing
  there could not undo the merge; it would only leave a false-open document
  that fails the next pull request's docs audit.
- `close-work-item.mjs` is pinned. Its new allowlist entry in
  `tests/skills/lib/close-work-item-pin.sh` is written last. It states that
  the exit contract is unchanged (exit 8 already exists), and that the D6
  snapshot/rollback transaction and the no-follow-ups coupling are
  untouched.
- `evidence-digest.mjs` still calls the gate without the flag. It is an
  informational reader, not a merge criterion.

### D7: tracked deletions are reproduced in the clone (item 8)

In `overlayTrackedWorkingTreeBytes`, an `ENOENT` from the `lstat` of a
tracked source path calls
`function removeCloneTrackedDelete(cloneDir, rel) {`, which removes the
clone's leftover with `lstat` and `unlink`. It never follows a link. It
skips when a clone ancestor of `rel` is a symlink, and it removes a leftover
real directory recursively. Then the loop continues without the skip line.
Every other error keeps the existing skip-by-name line. The D4 tree-hash
comparison still decides fidelity.

### D8: rotated record names are valid on Windows (item 9)

`lib/mutation-record.mjs` gains
`export function stampForFileName(runAtUtc) {`. It maps every character
outside `[A-Za-z0-9._-]` to `-`, so `2026-11-25T10:49:06Z` becomes
`2026-11-25T10-49-06Z`. `rotatedFileName` and `rotatedPatchFileName` both use
it. This also closes a path-traversal shape: a hand-edited record whose
`run_at_utc` held a `/` used to rotate outside the evidence directory, and
now cannot. `isRotatedFileName` still matches the new names. The record's
own `run_at_utc` header value is unchanged. Existing local records with
colons are not renamed: they are gitignored (0 tracked), and the live
record name never had a colon.

### D9: Mutation cells are checked mechanically where a check can decide (item 10)

A cell can be checked in two ways, at two moments:

- At freeze: `spec-lint.mjs` gains the rule `mutation-cell-undeclared`,
  emitted as `add('mutation-cell-undeclared', ...)` exactly once in the
  file. It fires when the mutation gate applies, the spec is not yet frozen
  (the `mutationGateFrozenMarker` that `spec-freeze.mjs` already passes as
  `false`), the row's Status is not exempt (`deferred`, `dropped` or
  `rejected`, the gate's EXEMPT_STATUSES), and a non-empty, non-placeholder
  cell yields zero tokens from
  `extractDeclaredMutations` (the gate's own extractor from
  `lib/mutation-record.mjs`). `spec-freeze.mjs` adds the rule to
  `PRECONDITION_RULES`, so a cell the gate could never compare does not
  freeze. Frozen specs are not linted for it; their legacy prose cells stay
  governed by the `mutation_uncomparable` ratchet.
- Once the target exists: `mutation-run.mjs --check --target <path>
  (--sed <expr> | --patch <file>)` is a dry run. It takes the same
  arguments as a real run, minus spec, suite and selector. It builds no
  clone, runs no suite and writes nothing. Its first line is
  `CHECK OK: <target> ...` (exit 0) or `CHECK FAIL <class>: ...` (exit 5),
  where class is one of `TARGET-REFUSED` (D1), `UNPARSEABLE-EXPR` (the
  shared grammar refuses it), `NO-CHANGE` (byte-identical),
  `AMBIGUOUS` (a pattern without `g` matching more than once, with the
  count, decided by `function isAmbiguousSed(parsed, content) {`), or
  `PARSE-BREAK` (D5). Usage errors are exit 2. For `--patch` it runs
  `git apply --check` in the working tree plus the existing foreign-path
  refusal.

Residual risk, stated rather than hidden: most cells mutate code the ride
has not written yet, so no tool can run them at freeze. The ride's own
cells are an example. Semantic no-ops and matches in an unrelated stanza
still surface only as STAYED GREEN in the real run, which already records
them. A runtime-only crash (a ReferenceError) is not caught by the parse
check. The prompt corpus is not changed: the freeze refusal is mechanical,
and `--check` is described in `mutation-run.mjs --help`.

### D-AMEND: SPEC-0181

After the edits are checked with grep or diff, this scope appends one
additive section to docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md
with the exact heading `## Amendment 2026-11-25 (mutation-tooling-p2-fixes)`.
It leaves the original D2 and D12 sentences visible and withdraws them in
place, quotes the frozen text beside the new rule, and names the edited
TEST-474, TEST-492 and TEST-500 expectations (rotated names now use the
sanitized stamp). The section also states that canon assigns this scope
change to HITL, that no prior sign-off was obtained, and that the owner may
reverse it. Then it records
`spec-amend.mjs add --spec docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md --ref mutation-tooling-p2-fixes --class contract --signoff none --what "<...>" --why "<...>"`.
`spec-amend.mjs list --strict` must exit 0 afterwards (allocator-rename
memory: run it after any allocator step too).

### D-WIRE

- New tests live in existing suites; there is no new suite and no
  suite-weights row.
- No new `.aai/**` file (no PROFILES.yaml entry), and no prompt-corpus
  bytes (no diet-ledger entry).
- CHANGELOG.md gets one heading,
  `## [unreleased] — Mutation tooling: the ten P2 follow-ups`. It names
  each consumer-visible change: the symlink and outside-target refusal,
  sed flags, the parse preflight, self-sourced patch re-records,
  Windows-valid rotated names, tracked deletions in the clone, the
  pre-merge close requiring evidence, `mutation-cell-undeclared` at freeze,
  and `--check`. A release rolls `[unreleased]` to `[vYYYY.MM.DD]`, and
  the heading check accepts either form.
- Every new mutation test runs `mutation-run.mjs` and `mutation-gate.mjs`
  with cwd inside its own `mktemp -d` fixture repository (its own
  `git init -b main` and identity). It never writes into this checkout's
  `docs/ai/tdd`. Each fixture is registered for cleanup. No test touches
  docker or a real remote. An empty fixture path is a hard failure before
  any `cd` (HAZ-CD).

## Acceptance Criteria Mapping

- AC-001 (each item fixed RED-to-GREEN or dropped with reason) maps to
  Spec-AC-01 to Spec-AC-11. Every item is fixed; none is dropped or
  deferred (decision table under "Registry items closed by this scope").
- AC-002 (each follow-up closed with resolved-by this ride) maps to
  Spec-AC-12.
- AC-003 (the touched suites pass) is the Verification section: every
  Spec-AC's test lives in a suite that is run whole.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN mutation-run.mjs is given a --target that is a symlink, has a symlinked ancestor, leaves the repository or is not a regular file THEN it SHALL exit 2 naming the reason, write no record and leave the symlink destination byte-identical; a regular-file target SHALL still record RED. | done | TEST-4110 green; mutation record RED; docs/ai/reports/VALIDATION-20261125T173443Z-mutation-tooling-p2-fixes.md | — | D1, item 1 |
| Spec-AC-02 | WHEN a --sed expression carries the m flag (or i) THEN the applier SHALL apply it, so a per-line anchored pattern records RED at exit 0 instead of the byte-identical refusal. | done | TEST-4111 green; mutation record RED; docs/ai/reports/VALIDATION-20261125T173443Z-mutation-tooling-p2-fixes.md | — | D2, item 2 |
| Spec-AC-03 | The corpus guard SHALL report zero bare-only dispatch suites over tests/skills and tests, SHALL name a planted bare-only fixture, and SHALL not name a stripping fixture; WHEN test-aai-session-lock.sh is run with test_409 and test-aai-test-canon.sh with test_001 THEN each SHALL exit 0 with no Unknown test or command not found text. | done | TEST-4112, TEST-4113 green; mutation record RED; docs/ai/reports/VALIDATION-20261125T173443Z-mutation-tooling-p2-fixes.md | — | D3, item 3 |
| Spec-AC-04 | WHEN a --patch run's patch path is the record's own canonical mutation-TEST-id.patch THEN the run SHALL exit 0 RED, the canonical .txt and .patch SHALL exist with the patch bytes unchanged, and the rotated .txt SHALL name a rotated .patch that exists and holds the same bytes. | done | TEST-4114 green; mutation record RED; docs/ai/reports/VALIDATION-20261125T173443Z-mutation-tooling-p2-fixes.md | — | D4, items 4 and 7 |
| Spec-AC-05 | WHEN a --sed mutation turns a target that parses (node --check or bash -n) into one that does not THEN mutation-run.mjs SHALL exit 2 with the text no longer parses and write no record; a parse-preserving mutation of the same target SHALL still record RED. | done | TEST-4115 green; mutation record RED; docs/ai/reports/VALIDATION-20261125T173443Z-mutation-tooling-p2-fixes.md | — | D5, item 5 |
| Spec-AC-06 | WHEN mutation-gate.mjs runs with --require-evidence on a gated spec whose evidence directory is absent THEN it SHALL exit 5 naming each non-exempt row as a missing record and each exempt row as EXEMPT; without the flag the same spec SHALL keep DEGRADED evidence tree absent at exit 0. | done | TEST-4116 green; mutation record RED; docs/ai/reports/VALIDATION-20261125T173443Z-mutation-tooling-p2-fixes.md | — | D6, item 6 |
| Spec-AC-07 | WHEN close-work-item.mjs closes a gated spec with an absent evidence directory under mutation_gate enforce without a post-merge --commit THEN it SHALL exit 8 naming the missing record; WHEN the --commit is already an ancestor of origin/main THEN the mutation gate SHALL not refuse the close. | done | TEST-4117 green; mutation record RED; docs/ai/reports/VALIDATION-20261125T173443Z-mutation-tooling-p2-fixes.md | — | D6, item 6 |
| Spec-AC-08 | WHEN a tracked file is deleted in the working tree and git apply of the tracked diff fails THEN mutation-run.mjs SHALL build a matching clone and record RED at exit 0, with no skipping tracked overlay line for the deleted path. | done | TEST-4118 green; mutation record RED; docs/ai/reports/VALIDATION-20261125T173443Z-mutation-tooling-p2-fixes.md | — | D7, item 8 |
| Spec-AC-09 | Every file a rotation writes SHALL match the pattern mutation-TEST-n.stamp(.k).txt or .patch, with the stamp drawn from letters, digits, dot, underscore and hyphen only and holding no colon; a record whose run_at_utc holds a slash SHALL rotate inside its evidence directory. | done | TEST-4119 green; mutation record RED; docs/ai/reports/VALIDATION-20261125T173443Z-mutation-tooling-p2-fixes.md | — | D8, item 9 |
| Spec-AC-10 | WHEN a not-yet-frozen tdd spec has a non-exempt row whose Mutation cell holds no machine-readable declaration THEN spec-lint.mjs SHALL report mutation-cell-undeclared for that row and spec-freeze.mjs SHALL refuse without writing; the same spec with a declared sed cell SHALL freeze; a frozen spec with the same prose cell SHALL not get the finding. | done | TEST-4120 green; mutation record RED; docs/ai/reports/VALIDATION-20261125T173443Z-mutation-tooling-p2-fixes.md | — | D9, item 10 |
| Spec-AC-11 | WHEN mutation-run.mjs --check is run THEN it SHALL exit 0 with CHECK OK for a usable cell and exit 5 with the class name for NO-CHANGE, AMBIGUOUS (with the match count), PARSE-BREAK, UNPARSEABLE-EXPR and TARGET-REFUSED, without creating docs/ai/tdd or any clone. | done | TEST-4121 green; mutation record RED; docs/ai/reports/VALIDATION-20261125T173443Z-mutation-tooling-p2-fixes.md | — | D9, item 10 |
| Spec-AC-12 | CHANGELOG.md SHALL hold the D-WIRE heading, SPEC-0181 SHALL hold the D-AMEND heading, spec-amend.mjs list --strict SHALL exit 0, and follow-ups.mjs list --status open --json SHALL list none of the twelve ids under Registry items closed by this scope, each closed with resolved_by mutation-tooling-p2-fixes. | done | TEST-4122 green; mutation record RED; docs/ai/reports/VALIDATION-20261125T173443Z-mutation-tooling-p2-fixes.md | — | D-AMEND, D-WIRE |

## Implementation plan

Order. Each step is RED first, with the RED log under
`docs/ai/tdd/mutation-tooling-p2-fixes/red/TEST-xxxx.log` and the GREEN log
under `.../green/`. Mutation records go under
`docs/ai/tdd/spec-mutation-tooling-p2-fixes/`.

1. D8 (`lib/mutation-record.mjs`). Then update the rotated-name expectations
   of TEST-474, TEST-492 and TEST-500 to `stampForFileName(run_at_utc)`.
2. D1, then D2, D5, D4 and D7 (`mutation-run.mjs`). D4 has a side effect:
   apply then reads a copy under the temp dir, so TEST-513 (the
   foreign-path refusal) must stay green.
3. D9 `--check` (`mutation-run.mjs`). It reuses D1, D2 and D5.
4. D3: both suites and the corpus guard.
5. D6: the gate flag first, then `close-work-item.mjs`, then the pin entry
   last.
6. D9 freeze half (`spec-lint.mjs`, `spec-freeze.mjs`).
7. D-AMEND, D-WIRE (CHANGELOG), then the twelve ledger closes (the ids
   in "Registry items closed by this scope"):
   `node .aai/scripts/follow-ups.mjs close --id <id> --resolved-by mutation-tooling-p2-fixes --source docs/specs/SPEC-0315-spec-mutation-tooling-p2-fixes.md`.

Seams this scope crosses (each test produces on one side and asserts the
real result on the other):

- `close-work-item.mjs` runs the real `mutation-gate.mjs` (TEST-4117 copies
  the real gate into its fixture with `seed_mutation_gate_engine`, never a
  stub).
- `spec-freeze.mjs` uses the `spec-lint.mjs` finding list (TEST-4120 runs
  the real freeze CLI).
- `spec-lint.mjs` uses the extractor from `lib/mutation-record.mjs`, which
  the gate also uses, so a cell that freezes is a cell the gate can compare
  (TEST-4120 also runs the gate's extractor on the frozen cell's text).
- The `lib/mutation-record.mjs` naming is used by `rotateExisting` in
  `mutation-run.mjs` (TEST-4119 asserts on the files the real CLI writes).
- The test-suite dispatch reads the `--selector` value `mutation-run.mjs`
  passes (TEST-4113 calls the real suites with the full `test_*` name).

Edge cases: a `--target` that is a directory (refused, D1). A sed with
flags `gg` (RegExp throws, exit 2). A target with no checker extension
(`parseCheck` returns null, no refusal). A tracked delete under a
working-tree directory symlink (left to the existing
`sourceHasSymlinkAncestor` skip). A gated spec whose Test Plan has zero
rows under `--require-evidence` (the existing zero-row path, no new
refusal). A post-merge close where no upstream ref resolves (not
post-merge, so the flag is passed; this fails closed).

## Test Plan

TEST ids 4110 to 4122. Measured free range: the highest id on origin/main
is TEST-4059; the in-flight sibling rides hold 4070 to 4074 and 4080 to
4107.

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-4110 | Spec-AC-01 | integration | tests/skills/test-aai-mutation-gate.sh | test_4110_target_must_be_regular_file: fixture repo; an untracked relative symlink to the suite as --target (exit 2, no record, suite bytes unchanged), a target with a symlinked parent (exit 2), ../outside.txt (exit 2, outside named), a directory (exit 2), and a regular target that still records RED | `sed:s/function assertRegularTarget\(root, rel\) \{/function assertRegularTarget(root, rel) { return;/` on .aai/scripts/mutation-run.mjs | green |
| TEST-4111 | Spec-AC-02 | integration | tests/skills/test-aai-mutation-gate.sh | test_4111_sed_honours_flags: fixture repo; a per-line anchored pattern with the m flag and a case-folded pattern with the i flag each record RED at exit 0; a g-flag expression still changes every occurrence | `sed:s/new RegExp\(parsed\.pattern, parsed\.flags\)/new RegExp(parsed.pattern, '')/` on .aai/scripts/mutation-run.mjs | green |
| TEST-4112 | Spec-AC-03 | inspection | tests/skills/test-aai-mutation-gate.sh | test_4112_no_bare_only_dispatch: the static D3 corpus guard over tests/skills and tests reports zero bare-only suites; positive control names a planted bare-only fixture; negative control does not name a stripping fixture | `sed:s/t="\$\{t#TEST-\}"; t="\$\{t#test_\}"/t="${t#TEST-}"/` on tests/skills/test-aai-session-lock.sh | green |
| TEST-4113 | Spec-AC-03 | integration | tests/skills/test-aai-mutation-gate.sh | test_4113_full_selector_dispatches: runs test-aai-session-lock.sh test_409 and test-aai-test-canon.sh test_001 through the real suites; each exits 0 and prints no Unknown test or command not found text | `sed:s/"test_\$\{arg#test_\}"/"test_${arg}"/` on tests/skills/test-aai-test-canon.sh | green |
| TEST-4114 | Spec-AC-04 | integration | tests/skills/test-aai-mutation-gate.sh | test_4114_patch_rerecord_from_own_canonical: fixture repo; one --patch run, then a second run whose --patch is the canonical mutation-TEST-9001.patch; exit 0 RED, canonical pair present with unchanged patch bytes, rotated record names its rotated patch with the same bytes | `patch:docs/ai/tdd/spec-mutation-tooling-p2-fixes/mutation-TEST-4114.patch` (the patch moves the read of the patch bytes in mutation-run.mjs to after rotateExisting, so the run reads its own source after rotation moved it) | green |
| TEST-4115 | Spec-AC-05 | integration | tests/skills/test-aai-mutation-gate.sh | test_4115_parse_break_refused: fixture suite that ignores the target exit status; an escaped-replacement sed that breaks parsing exits 2 with no longer parses and writes no record; a parse-preserving sed on the same target records RED; a .sh target broken for bash -n is refused the same way | `sed:s/function parseCheck\(file\) \{/function parseCheck(file) { return null;/` on .aai/scripts/mutation-run.mjs | green |
| TEST-4116 | Spec-AC-06 | integration | tests/skills/test-aai-mutation-gate.sh | test_4116_require_evidence_absent_tree: fixture repo (cwd inside it) with a gated tdd spec, one pending row and one deferred row, no evidence directory; the default run keeps DEGRADED evidence tree absent at exit 0; --require-evidence exits 5 with OFFENDING missing record for the pending row and EXEMPT for the deferred row | `sed:s/if \(!evidenceDirExists && !args\.requireEvidence\) \{/if (!evidenceDirExists) {/` on .aai/scripts/mutation-gate.mjs | green |
| TEST-4117 | Spec-AC-07 | integration | tests/skills/test-aai-close-work-item.sh | test_4117_close_requires_evidence_before_merge: fixture with the real gate seeded, mutation_gate enforce, a gated spec with no evidence directory; a close without --commit exits 8 naming the missing record and writes nothing; a close whose --commit is an ancestor of origin/main is not refused by the mutation gate | `sed:s/function mutationGateArgs\(commit\) \{/function mutationGateArgs(commit) { return [];/` on .aai/scripts/close-work-item.mjs | green |
| TEST-4118 | Spec-AC-08 | integration | tests/skills/test-aai-mutation-gate.sh | test_4118_tracked_delete_reproduced: fixture repo; a tracked file deleted plus a tracked binary change that makes git apply fail; the run records RED at exit 0 and prints no skipping tracked overlay line for the deleted path | `sed:s/function removeCloneTrackedDelete\(cloneDir, rel\) \{/function removeCloneTrackedDelete(cloneDir, rel) { return;/` on .aai/scripts/mutation-run.mjs | green |
| TEST-4119 | Spec-AC-09 | integration | tests/skills/test-aai-mutation-gate.sh | test_4119_rotated_names_windows_valid: fixture repo; two --patch runs and a planted live record whose run_at_utc holds a colon stamp, then one whose run_at_utc holds a slash; every rotated .txt and .patch name matches the D8 pattern with no colon, and nothing is written outside the evidence directory | `sed:s/export function stampForFileName\(runAtUtc\) \{/export function stampForFileName(runAtUtc) { return String(runAtUtc);/` on .aai/scripts/lib/mutation-record.mjs | green |
| TEST-4120 | Spec-AC-10 | integration | tests/skills/test-aai-spec-lint.sh | test_4120_undeclared_cell_refuses_freeze: a scratch tdd draft with a sed cell using a hash delimiter gets mutation-cell-undeclared from spec-lint and a refusal with no write from spec-freeze; the same draft with a slash-delimited sed cell freezes and the gate extractor yields its token; a frozen spec with the prose cell gets no such finding | `sed:s/add\('mutation-cell-undeclared'/add('mutation-cell-undeclared-off'/` on .aai/scripts/spec-lint.mjs | green |
| TEST-4121 | Spec-AC-11 | integration | tests/skills/test-aai-mutation-gate.sh | test_4121_check_dry_run: fixture repo; --check returns CHECK OK exit 0 for a usable sed, and exit 5 for NO-CHANGE, AMBIGUOUS with count 2, PARSE-BREAK, UNPARSEABLE-EXPR and a symlink TARGET-REFUSED; docs/ai/tdd does not exist afterwards and no aai-mutation temp dir is left | `sed:s/function isAmbiguousSed\(parsed, content\) \{/function isAmbiguousSed(parsed, content) { return false;/` on .aai/scripts/mutation-run.mjs | green |
| TEST-4122 | Spec-AC-12 | inspection | tests/skills/test-aai-mutation-gate.sh | test_4122_changelog_and_amendment: CHANGELOG.md holds the D-WIRE heading in its unreleased or rolled version form, and SPEC-0181 holds the exact D-AMEND heading line | `sed:s/— Mutation tooling: the ten P2 follow-ups/— Mutation tooling/` on CHANGELOG.md | green |

Every new test is added to `main()` of its suite and resolves when called
with its own full `test_*` name.

## Verification

- Each touched suite runs whole through the canonical runner, with
  `env -u AAI_ROLE`, and exits 0: aai-mutation-gate, aai-close-work-item,
  aai-spec-lint, aai-session-lock, aai-test-canon, aai-spec-tools,
  aai-spec-amend, aai-hygiene-pack, aai-doc-numbering, aai-follow-ups,
  aai-doc-number-reservation and aai-repo-tripwire. The last four are the
  pin consumers: one byte in `close-work-item.mjs` affects four suites.
  Example:
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-mutation-gate.sh`.
- One full sweep before the close, with `AAI_TEST_TIMEOUT=3600`.
- `node .aai/scripts/spec-amend.mjs list --strict` exits 0.
- `node .aai/scripts/follow-ups.mjs list --status open --json` lists none
  of the twelve ids.
- `node .aai/scripts/mutation-run.mjs` writes one RED record per Test Plan
  row (`--check` first, D9), and `node .aai/scripts/mutation-gate.mjs --spec
  <this spec> --require-evidence` prints GATE PASS.
- Hosted: the skill-suite run on the pull request head, including the
  Windows legs, since item 9 is Windows-facing.
- PASS criteria: every TEST-xxx green, every Spec-AC in a terminal status.

## Evidence contract

- ref_id `mutation-tooling-p2-fixes`. RED and GREEN logs go under
  `docs/ai/tdd/mutation-tooling-p2-fixes/{red,green}/TEST-xxxx.log`, and
  mutation records go under `docs/ai/tdd/spec-mutation-tooling-p2-fixes/`.
- The validation report is
  `docs/ai/reports/VALIDATION-<ts>-mutation-tooling-p2-fixes.md`, and the
  review report is
  `docs/ai/reviews/review-mutation-tooling-p2-fixes-<ts>.md`.

### Evidence by strategy

tdd: a stored RED artifact for each AC-gating test plus the verification
above.

## Registry items closed by this scope

All ten intake items are fixed, none is dropped or deferred, and two
more open items with the same mechanism are closed by the same fixes.

| Follow-up | Decision | Spec-AC |
|---|---|---|
| fu-mutation-target-symlink-unchecked | fix (D1) | Spec-AC-01 |
| fu-mutation-sed-drops-multiline-flag | fix (D2) | Spec-AC-02 |
| fu-mutation-selector-vs-bare-dispatch | fix (D3: 3 of the 4 named suites were already fixed; session-lock and the newly found test-canon are fixed, and a corpus guard is added) | Spec-AC-03 |
| fu-mutation-patch-consumes-own-source | fix (D4) | Spec-AC-04 |
| fu-mutation-run-patch-self-rotate | fix (D4, the same mechanism) | Spec-AC-04 |
| fu-mutation-sed-replacement-unescaped | fix (D5, the parse preflight; replacement semantics unchanged) | Spec-AC-05 |
| fu-mutation-gate-absent-tree-passes | fix (D6, the merge-criterion close; CI wiring rejected with reason) | Spec-AC-06, Spec-AC-07 |
| fu-mutation-overlay-tracked-deletes | fix (D7) | Spec-AC-08 |
| fu-mutation-rotation-colon-path | fix (D8) | Spec-AC-09 |
| fu-frozen-mutation-cells-unusable | fix of the classes a tool can decide (D9); the residual is stated in D9 | Spec-AC-10, Spec-AC-11 |
| fu-writerecord-rotates-before-patch-copy (P2, not in the intake list, same subject) | fix (D4 is exactly its stated remedy: copy the bytes first, rotate second) | Spec-AC-04 |
| fu-mutation-run-reject-unparseable (P3, same subject) | fix (D5 is its stated remedy, refused at exit 2 rather than recorded INCONCLUSIVE) | Spec-AC-05 |

Open items on the same subject that this scope touches but does not close,
with the reason for each (registry consumer rule):

- NOT CLOSED: `fu-mutation-evidence-is-gitignored` (P3): out of scope per the intake.
  D6 is the merge-criterion half and does not change where evidence lives.
- NOT CLOSED: `fu-sed-replacement-dollar-trap` (P3): the `$`-pattern semantics of the
  replacement are documented in `--help`, and existing cells may rely on
  `$1`. Changing them is the design question the item names. D5 refuses
  the splice when it breaks parsing, but not when the spliced code still
  parses.
- NOT CLOSED: `fu-deferred-row-empty-mutation-cell` (P3): it concerns the existing
  `mutation-cell-missing` freeze precondition. The new
  `mutation-cell-undeclared` rule skips exempt-status rows from day one
  (D9), but changing the old rule is a separate decision.
- NOT CLOSED: `fu-replay-vanished-target-counter` (P3) and
  `fu-mutation-replay-skip-reads-green` (P3): replay arithmetic and skip
  classification, which no D-section changes.
- NOT CLOSED: `fu-mutation-anchors-undisclosed` (P3): a disclosure-policy item. D9's
  `--check` makes the anchors checkable but does not change disclosure.

## Residual risks

- D6 trusts the post-merge predicate (an ancestor of the upstream default
  ref). A stale `origin/main` makes a post-merge close look pre-merge, so
  it refuses (fails closed). The remedy is `git fetch`.
- D6 changes a pre-merge close only when the whole evidence directory is
  absent. A ride that ran its TDD in another worktree and closes from a
  third checkout now gets exit 8 where it used to close silently. That is
  the intent, and the remedy (close where the evidence is) is named in the
  refusal text.
- D5 makes a replay of an existing record whose mutation breaks syntax
  INCONCLUSIVE (exit 4) where it used to replay RED. The gate does not
  replay, so no close changes.
- D9 cannot run a cell against code that does not exist yet. The ride's own
  cells name functions this spec prescribes, and `--check` verifies them
  once the code exists. A mismatch is disclosed with `spec-amend` as
  before.
- D3's guard is static, so a dispatch idiom outside the `"test_${VAR}"`
  shape is not seen. The selector-probe corpus check (hygiene-pack TEST-473)
  still covers unknown selectors.
- Ceremony level 2: no file in `protected_paths_l3` and no workflow file is
  touched.
