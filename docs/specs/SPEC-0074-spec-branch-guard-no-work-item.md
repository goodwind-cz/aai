---
id: spec-branch-guard-no-work-item
type: spec
number: 74
status: done
ceremony_level: 1
links:
  requirement: docs/issues/ISSUE-0028-branch-guard-no-work-item.md
  rfc: null
  pr:
    - 137
  commits:
    - 43a54c9d2727a682a7134b8576e585f7766ff4cd
---

# Implementation Spec — branch-guard no-work-item prefix allowlist

SPEC-FROZEN: true

Ceremony justification: the scope is confined to one EXISTING non-protected
script (`.aai/scripts/branch-guard.mjs`) and its EXISTING test suite
(`tests/skills/test-aai-branch-guard.sh`) — no new `.aai/**` file, no
prompt-corpus edit (`.aai/*.prompt.md` / `.aai/AGENTS.md` untouched), no
protected-path touch. `.aai/scripts/branch-guard.mjs` is confirmed NOT in
`protected_paths_l3` (docs/ai/docs-audit.yaml): the L3 set is
`.aai/scripts/state.mjs`, `.aai/scripts/lib/state-engine.mjs`,
`.aai/scripts/lib/state-core.mjs`, `.aai/scripts/allocate-doc-number.mjs`,
`.aai/scripts/pre-commit-checks.sh`, `.aai/scripts/pre-commit-checks.ps1`,
`.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md`. Single reviewable,
reversible, additive decision-order change inside one script -> Level 1
(same tier as the guard's own originating spec, SPEC-0070).

## Links
- Requirement: docs/issues/ISSUE-0028-branch-guard-no-work-item.md
- Decision records: GitHub #135
- Technology contract: docs/TECHNOLOGY.md

## Problem

`.aai/scripts/branch-guard.mjs` (SPEC-0070 / PR #129) assumes every branch
belongs to a work item: its decision order has no exit path for "this branch
correctly has no work item." A `chore/*`, `release/*`, or `docs/*` branch
either fails at order item 5 (branch does not contain `current_focus.ref_id`,
exit 3) or, with a cleared focus, at order item 3 (`ref_id` empty, exit 4).
As a `SKILL_PR` "0. BRANCH HYGIENE" precondition, this blocks routine chores
and, more importantly, every `/aai-release` cut (`release/v*` can never
contain a work-item ref). Reported live as GitHub #135.

## Scope
- In scope: `.aai/scripts/branch-guard.mjs` (decision-order change + header/
  usage-comment update documenting the new order items); `tests/skills/
  test-aai-branch-guard.sh` (new sub-cases appended to the existing suite);
  this spec doc.
- Out of scope: a `--no-work-item` flag (noted below as a possible future
  addition, not built now); widening the allowlist beyond `chore/`,
  `release/`, `docs/`; any change to `.aai/SKILL_PR.prompt.md` or
  `.aai/AGENTS.md` (the guard's own header/usage comments carry the new
  documentation, per the intake's explicit instruction to avoid a
  prompt-corpus companion); any STATE.yaml schema change (still read-only);
  `--suggest` mode (unaffected — it has no branch to allowlist against).
- Protected paths touched: none.

## Design — decision-order change

Add a closed constant `ALLOWLIST_PREFIXES = ['chore/', 'release/', 'docs/']`
and a `matchAllowlistPrefix(branch)` helper (returns the matched prefix or
`null`). The two-tier STATE-read distinction already implicit in the code
(a file that cannot be opened at all, vs. a file that opens fine but carries
an empty/null `ref_id`) becomes an EXPLICIT, separately-checked condition —
this is the mechanism that lets a cleared focus pass on an allowlisted branch
while a genuinely broken STATE file still fails closed everywhere.

New deterministic check order (guard mode; EARLIER items win):

1. cwd not inside a git work tree -> exit 4 (unchanged).
2. HEAD detached -> exit 2 (unchanged; precedes the STATE read entirely).
3. STATE.yaml cannot be opened/read at all ("Tier A" — file missing or
   unreadable) -> exit 4, unconditional, regardless of branch name. This is
   the ONLY STATE-read failure that still blocks an allowlisted branch.
4. current branch equals the base branch:
   4a. `current_focus.ref_id` is empty/null ("Tier B" — file opened fine, no
       focus recorded) -> exit 4 (identical result to today; this is the
       EXISTING base-vs-broken-STATE precedence, unchanged in outcome, now
       reached via an explicit nested check instead of the old combined
       item 3).
   4b. `ref_id` is set -> exit 1 (unchanged: base-branch violation).
5. NEW — current branch matches an allowlisted non-work-item prefix
   (`chore/`, `release/`, `docs/`) -> exit 0, with a message distinct from
   the normal pass message (e.g. `no work item claimed — recognized
   non-work-item branch prefix "chore/"`). Fires regardless of whether
   `ref_id` is set-but-unrelated (Tier-valid) or empty/null (Tier B) — the
   allowlist needs no focus at all. Only reachable once item 4 has already
   established the branch is NOT the base branch.
6. `current_focus.ref_id` is empty/null (Tier B) and the branch is NOT
   allowlisted -> exit 4 (same outcome as today's combined item 3, for every
   branch that isn't on the allowlist — e.g. `fix/whatever`).
7. current branch does not contain the `ref_id` slug -> exit 3 (unchanged;
   only reached with a non-empty `ref_id` — the #129 anti-drift guarantee).
8. otherwise -> exit 0 (unchanged pass path for a correctly-named
   `<type>/<ref-id>` branch).

Equivalent implementation shape (single function, not a flat if-chain, to
make the nesting at item 4 explicit):

```
if (!insideGitWorkTree) exit(4);
if (branch === 'HEAD') exit(2);           // detached
if (!stateFileReadable) exit(4);          // Tier A
const { refId } = readFocus();            // may be null/empty (Tier B)
if (branch === base) {
  exit(refId ? 1 : 4);                    // 4a/4b
}
const prefix = matchAllowlistPrefix(branch);
if (prefix) exit(0);                      // NEW — item 5
if (!refId) exit(4);                      // item 6 (Tier B, non-allowlisted)
if (!branch.includes(refId)) exit(3);     // item 7 — anti-drift intact
exit(0);                                  // item 8
```

No exit code is added or removed — the closed set `{0,1,2,3,4}` from
SPEC-0070 is unchanged; only the decision path leading to 0 and 4 gains a
new branch. The guard's own header comment (`.aai/scripts/branch-guard.mjs`
top-of-file doc block) is updated to document this new numbered order and
the Tier A / Tier B distinction — no separate prompt file carries this
documentation (per the intake's explicit constraint).

### Precedence guarantees (why this design is safe)

- Base wins over the allowlist: item 4 is checked and can return BEFORE
  item 5 is ever reached, so a branch that happens to equal `--base` (even
  one that would otherwise match an allowlisted prefix, e.g. `--base
  chore/legacy-main` with that same branch checked out) still exits 1/4 via
  item 4, never 0. A chore is still never committed straight to the base.
- Tier A (STATE truly unreadable) wins over the allowlist: item 3 is
  unconditional and runs before the branch name is even inspected for a
  prefix match, so a `chore/x` branch with a missing/corrupt STATE.yaml
  still exits 4.
- Anti-drift is unchanged: item 7 (mismatch -> exit 3) is reached only for
  non-allowlisted branches with a set `ref_id` — a real work-item branch
  (e.g. `feat/wrong`) that does not contain the current ref_id still exits
  3. `feat`/`fix` and other work-item type-token prefixes are deliberately
  NOT added to `ALLOWLIST_PREFIXES`.
- Tier B (cleared/empty focus) only helps an allowlisted, non-base branch:
  item 4a still exits 4 for a cleared focus on the base branch (identical
  to today), and item 6 still exits 4 for a cleared focus on any
  non-allowlisted branch (identical to today). Only item 5, reached before
  item 6, lets a cleared focus pass — and only for the closed prefix set.

### Future addition (explicitly out of scope now)

If a broader/less-safe exemption is ever wanted, prefer an explicit
`--no-work-item` flag the caller passes deliberately (an act, not an
accident) over widening `ALLOWLIST_PREFIXES`. Not built in this scope.

## Implementation strategy
- Strategy: tdd
- Rationale: this is a decision-order change to existing exit-code branch
  logic with two tiers of STATE-read failure that must not conflate — the
  exact defect class this session already hit twice (SPEC-0054 Problem #2,
  SPEC-0073). Clean, discriminating RED/GREEN states over throwaway git-repo
  fixtures (the same technique SPEC-0070 itself used) make the precedence
  claims verifiable rather than asserted. Unlike SPEC-0070, there is no
  prompt/doc-text component in this scope, so a single `tdd` strategy (not
  `hybrid`) applies to the whole change.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single non-protected script + its existing test file,
  small and fully reversible, already on a dedicated branch
  (`fix/branch-guard-no-work-item`) off `main`. No cross-cutting refactor,
  no migration, no protected-path touch.
- User decision: inline
- Base ref: main
- Worktree branch/path: fix/branch-guard-no-work-item (inline)
- Inline review scope: `.aai/scripts/branch-guard.mjs`,
  `tests/skills/test-aai-branch-guard.sh`

## Companion obligations (PLANNING step 3a)

- Adds bytes to the prompt corpus (`.aai/*.prompt.md`, `.aai/AGENTS.md`)?
  NO — the new order is documented in the guard's own header/usage comments,
  not in any prompt file. No prompt-diet ledger true-up.
- Adds a NEW `.aai/**` file? NO — `.aai/scripts/branch-guard.mjs` already
  exists (added in PR #129); `tests/skills/test-aai-branch-guard.sh` already
  exists and is extended, not created. No `.aai/system/PROFILES.yaml`
  classification entry.
- Outcome: neither obligation applies. Skipped, per the closed two-entry
  list in `.aai/PLANNING.prompt.md` step 3a.

## Acceptance Criteria Mapping

- Maps to: Intake Verification bullet 1 (allowlist exits 0 with a distinct
  message, regardless of `current_focus`)
- Spec-AC-01: A branch whose name starts with an allowlisted prefix
  (`chore/`, `release/`, `docs/`), that is NOT the base branch and has a
  genuinely readable STATE.yaml, exits 0 with a message distinct from the
  normal ref_id-match pass message and naming the matched prefix —
  regardless of whether `current_focus.ref_id` is set-to-an-unrelated-value
  or empty/null.
  - Verification: `bash tests/skills/test-aai-branch-guard.sh 009` -> exit 0
    (asserts all 3 prefixes with a set-but-unrelated ref_id).
    `bash tests/skills/test-aai-branch-guard.sh 010` -> exit 0 (asserts
    `chore/x` with a cleared ref_id).

- Maps to: Intake Verification bullet 2 (base-branch guard still fires
  first)
- Spec-AC-02: The base-branch check (exit 1, or exit 4 if `ref_id` is also
  empty) fires BEFORE the allowlist check — proven non-vacuously by a branch
  name that is simultaneously the configured base AND allowlist-prefix
  shaped (e.g. `--base chore/legacy-main` while that same branch is checked
  out): the guard exits 1 (or 4), never 0.
  - Verification: `bash tests/skills/test-aai-branch-guard.sh 012` -> exit 0
    (asserts the guard under test exits 1 for the collision fixture).
    `bash tests/skills/test-aai-branch-guard.sh 002` -> exit 0 (existing
    TEST-002, unmodified — confirms the plain base-branch path is
    unaffected).

- Maps to: Intake Verification bullet 3 (anti-drift unchanged)
- Spec-AC-03: A branch using a work-item type-token prefix (`feat/`, `fix/`,
  etc. — NOT on the allowlist) whose name does not contain the current
  `ref_id` still exits 3.
  - Verification: `bash tests/skills/test-aai-branch-guard.sh 004` -> exit 0
    (existing TEST-004, unmodified — `feat/unrelated-name` still exits 3
    after this change).

- Maps to: Intake Verification bullet 1 (fail-closed default unchanged for
  genuinely broken STATE)
- Spec-AC-04: A STATE.yaml that cannot be opened/read at all (Tier A) still
  exits 4 even on an allowlisted branch — the allowlist only overrides a
  merely-empty `ref_id` (Tier B), never a genuinely unreadable file.
  - Verification: `bash tests/skills/test-aai-branch-guard.sh 011` -> exit 0
    (asserts the guard under test exits 4 for `chore/x` with STATE.yaml
    absent).

- Maps to: Intake Verification bullet 4 (detached/not-a-repo unchanged)
- Spec-AC-05: HEAD detached (exit 2) and "not inside a git work tree" (exit
  4) are unaffected by this change — both checks run before any STATE read
  or branch-name inspection.
  - Verification: `bash tests/skills/test-aai-branch-guard.sh 003` -> exit 0
    (existing TEST-003, unmodified — detached HEAD, including the
    detached-plus-broken-STATE sub-case, still exits 2).

- Maps to: Intake Verification bullet 1 (correct branch path unchanged)
- Spec-AC-06: A correctly-named `<type>/<ref-id>` branch still exits 0 via
  the pre-existing pass path (item 8), unaffected by the new item 5.
  - Verification: `bash tests/skills/test-aai-branch-guard.sh 001` -> exit 0
    (existing TEST-001, unmodified).

## Constitution deviations

None. Art.1: measurable exit-code AC + TEST-xxx below, no PASS claim in
planning. Art.2: no new flag, no new file — the smallest change that closes
the gap (a 3-entry constant + one nested-branch restructure). Art.3: pure
`.mjs` (node stdlib only) + the existing bash-3.2-compatible test suite,
same portability discipline (full `mktemp` templates, `git init -b main`,
honors its own shebang) already established by SPEC-0070/LEARNED
2026-07-19. Art.4: every new/changed exit path still prints an explicit
message to stdout/stderr; nothing goes silent. Art.5: additive-only —
existing exit codes and their trigger conditions for every PRE-EXISTING
branch are provably unchanged (see Precedence guarantees above); only a new
decision branch is added. Art.6: the guard still never writes STATE.yaml —
no change to its read-only import of `lib/state-core.mjs`/
`lib/state-engine.mjs`. Art.7: no merge-boundary change; this only affects
the pre-push `SKILL_PR` "0. BRANCH HYGIENE" precondition's decision, not the
merge action itself.

## Seam analysis

No NEW seam. This change does not add a new consumer, a new producer, or a
new STATE.yaml field — it only refines how the EXISTING sole consumer
(`branch-guard.mjs`) interprets an already-read value (`current_focus.
ref_id`) once it is empty/null, and only for branch names matching a closed
prefix set. The producer/consumer seam across `docs/ai/STATE.yaml`
(`state.mjs` writes, `branch-guard.mjs` reads) is unchanged from SPEC-0070
and remains covered end-to-end by that spec's TEST-001 (real
`state.mjs set-focus` writer, `branch-guard.mjs` reader, in a throwaway
fixture repo) — re-run here as an unmodified regression check, not
duplicated.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Allowlisted prefix, non-base, readable STATE -> exit 0 (set-or-cleared ref_id) | done | docs/ai/tdd/green-20260724T074153Z.log (TEST-009 3->0, TEST-010 4->0) | 2026-10-24 | RED evidence docs/ai/tdd/red-20260724T074153Z.log |
| Spec-AC-02 | Base-branch check still fires before the allowlist                  | done | docs/ai/tdd/green-20260724T074153Z.log (TEST-012 exit 1, TEST-002 exit 1) | 2026-10-24 | non-discriminating pin (base wins) |
| Spec-AC-03 | Non-allowlisted mismatch still exits 3 (anti-drift intact)          | done | docs/ai/tdd/green-20260724T074153Z.log (TEST-004 exit 3) | 2026-10-24 | #129 anti-drift unchanged |
| Spec-AC-04 | Tier A (STATE unreadable) still exits 4 even on an allowlisted branch | done | docs/ai/tdd/green-20260724T074153Z.log (TEST-011 exit 4) | 2026-10-24 | non-discriminating pin (fail-closed) |
| Spec-AC-05 | Detached (2) / not-a-repo (4) unaffected                             | done | docs/ai/tdd/green-20260724T074153Z.log (TEST-003 exit 2) | 2026-10-24 | regression |
| Spec-AC-06 | Correct `<type>/<ref-id>` branch still exits 0                       | done | docs/ai/tdd/green-20260724T074153Z.log (TEST-001 exit 0) | 2026-10-24 | regression, seam-crossing |

## Implementation plan
- Components/modules affected: `.aai/scripts/branch-guard.mjs` (add
  `ALLOWLIST_PREFIXES`, `matchAllowlistPrefix()`, restructure `main()`'s
  guard-mode branch per the Design section, update the top-of-file doc
  block's numbered order comment and exit-code contract note); `tests/
  skills/test-aai-branch-guard.sh` (append `test_009`..`test_012`, extend
  `ALL_TESTS`).
- Data flow: unchanged — `git rev-parse` (read-only) + `docs/ai/STATE.yaml`
  (read-only) -> exit code + stdout/stderr text. No writes anywhere; no new
  inputs (the allowlist is a closed in-code constant, not a STATE field or
  CLI flag).
- Edge cases: a `--base` value that itself matches an allowlisted prefix and
  is the checked-out branch (item 4 must still win — Spec-AC-02, TEST-012);
  a branch matching an allowlisted prefix but ALSO containing the current
  `ref_id` as a substring (still exits 0, just via item 5 instead of item 8
  — no test needed, exit code is identical either way, not a distinguishable
  outward behavior); an allowlisted-prefix branch name that is a prefix
  match only in the string sense but not path-segment-safe, e.g.
  `choreography/x` — `matchAllowlistPrefix` uses `startsWith('chore/')`
  (WITH the trailing slash baked into the constant), so `choreography/x`
  does NOT match (`'choreography/x'.startsWith('chore/')` is false because
  the 6th character is `o`, not `/`); `--suggest` mode is untouched (it has
  no current branch to allowlist against, only `current_focus.ref_id`/
  `.type`, so its existing empty-ref_id exit-4 behavior is unaffected by
  design, confirmed by existing TEST-006 remaining unmodified).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                     | Description                                                                                                                                                                                                          | Status  |
|----------|------------|-------------|-------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-009 | Spec-AC-01 | integration | tests/skills/test-aai-branch-guard.sh     | Three throwaway repos, branches `chore/tenant-cleanup`, `release/v1.2.3`, `docs/typo-fix`, each with `current_focus.ref_id` SET to an unrelated value (e.g. `unrelated-work-item`) -> guard exits 0 for all three, stdout names the matched prefix. RED (pre-fix): each exits 3 (order item 5/7 mismatch) today. GREEN (post-fix): exit 0. Genuinely discriminating: 3 -> 0. | green   |
| TEST-010 | Spec-AC-01 | integration | tests/skills/test-aai-branch-guard.sh     | Branch `chore/tenant-cleanup`, `current_focus.ref_id` CLEARED (empty/null, STATE.yaml itself readable) -> guard exits 0. RED (pre-fix): exits 4 (today's combined item-3 check) today. GREEN (post-fix): exit 0. Genuinely discriminating: 4 -> 0.                                                             | green   |
| TEST-011 | Spec-AC-04 | integration | tests/skills/test-aai-branch-guard.sh     | Branch `chore/tenant-cleanup`, STATE.yaml FILE ABSENT (Tier A, not merely empty) -> guard exits 4 both before and after this change. NON-DISCRIMINATING BY DESIGN (pre-fix exit 4 == post-fix exit 4) — included to pin that Tier A still blocks an allowlisted branch, not to claim new coverage; the RED-proof obligation does not apply to this row (see Notes below).      | green   |
| TEST-012 | Spec-AC-02 | integration | tests/skills/test-aai-branch-guard.sh     | Branch AND `--base` both literally `chore/legacy-main` (base-vs-allowlist collision, `current_focus.ref_id` set to a valid unrelated value) -> guard exits 1 both before and after this change (item 4 always precedes item 5 by construction). NON-DISCRIMINATING BY DESIGN (pre-fix exit 1 == post-fix exit 1) — pins base-wins-over-allowlist precedence; RED-proof obligation does not apply (see Notes below). | green   |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-branch-guard.sh     | EXISTING, unmodified. Plain base-branch path (`main`) with a valid `ref_id` -> exit 1, exact remediation, including the coincidental-containment negative control. Re-run as a regression check for Spec-AC-02.                                                                                                | green   |
| TEST-004 | Spec-AC-03 | unit        | tests/skills/test-aai-branch-guard.sh     | EXISTING, unmodified. `feat/unrelated-name` (non-allowlisted work-item prefix, `ref_id` set but not matching) -> exit 3. Re-run as a regression check for Spec-AC-03 (anti-drift intact after this change).                                                                                                     | green   |
| TEST-003 | Spec-AC-05 | unit        | tests/skills/test-aai-branch-guard.sh     | EXISTING, unmodified. Detached HEAD, including the detached-plus-absent-STATE sub-case -> exit 2 both times. Re-run as a regression check for Spec-AC-05.                                                                                                                                                        | green   |
| TEST-001 | Spec-AC-06 | integration | tests/skills/test-aai-branch-guard.sh     | EXISTING, unmodified. Real `state.mjs set-focus` writer sets `ref_id`; correctly-named `fix/<ref>` branch -> guard exits 0. Re-run as a regression check for Spec-AC-06; also the seam-crossing test (see Seam analysis).                                                                                       | green   |

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- TEST-001..008 already exist in `tests/skills/test-aai-branch-guard.sh`
  (SPEC-0070). TEST-009..012 are NEW rows appended in this scope; `ALL_TESTS`
  in the suite is extended from `"001 002 003 004 005 006 007 008"` to
  `"001 002 003 004 005 006 007 008 009 010 011 012"`.
- RED-proof obligation: TEST-009 and TEST-010 are genuinely RED-proof — each
  was observed to produce a DIFFERENT exit code before this change (3 and 4
  respectively) than after (0 in both cases); this is captured as the RED
  evidence log before implementation begins. TEST-011 and TEST-012 are
  explicitly exempted from the RED-proof obligation because their pre- and
  post-fix values are IDENTICAL by design (they pin precedence guarantees
  that this change deliberately does not alter) — stating a fake RED for an
  already-passing assertion would be the tautological-test trap the
  RED-proof rule exists to catch, so instead this spec records honestly
  that these two rows are regression pins, not new coverage. TEST-001..004
  are cited as-is (already green under SPEC-0070) — re-run post-change as
  the regression evidence for Spec-AC-02/03/05/06; no new RED/GREEN pair is
  claimed for them.
- Behavioral tests build throwaway git repos (`git init -b main`, real
  branches, real commits) per the existing suite's `make_repo`/`write_state`
  helpers — full `mktemp` templates, POSIX-safe, honoring the suite's own
  `#!/usr/bin/env bash` shebang (docs/knowledge/LEARNED.md, Session
  2026-07-19), green on macOS + Linux CI.
- Table cell check: no cell in this table (or elsewhere in this spec)
  contains a literal `|` character (SPEC-0072 pipe-table-drop hazard) — the
  base-vs-allowlist collision branch name is written as `chore/legacy-main`
  (no pipe), and all exit-code lists use `/` or commas, never `|`.

## Verification
- `bash tests/skills/test-aai-branch-guard.sh` -> exit 0 (all 12 cases,
  001..012).
- `bash tests/skills/test-aai-branch-guard.sh 009 010 011 012` -> exit 0
  (new cases in isolation, for RED capture before the fix and GREEN capture
  after).
- `.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-branch-guard.sh`
  -> exit 0 (process-group-wrapped run, matches CI invocation).
- Manual spot check: `node .aai/scripts/branch-guard.mjs --base main` on a
  throwaway `chore/`-prefixed branch with `current_focus.ref_id` unset
  prints the new "no work item claimed" message and exits 0.
- Post-freeze advisory: `node .aai/scripts/spec-lint.mjs --path
  docs/specs/SPEC-0074-spec-branch-guard-no-work-item.md` (report-only).
- PASS criteria: all TEST-001..012 green; all Spec-AC-01..06 in a terminal
  (`done`) status with non-empty evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: branch-guard-no-work-item (SPEC-000N at merge; closes GitHub #135)
- Spec-AC and TEST-xxx links (Spec-AC-01/TEST-009+TEST-010,
  Spec-AC-02/TEST-012+TEST-002, Spec-AC-03/TEST-004, Spec-AC-04/TEST-011,
  Spec-AC-05/TEST-003, Spec-AC-06/TEST-001)
- command or review scope
- exit code or review verdict
- evidence path (RED/GREEN logs under `docs/ai/tdd/`; review under
  `docs/ai/reviews/`)
- commit SHA or diff range when available
- Close ceremony references GitHub #135 (per the intake's `github_issues:
  [135]` link).
