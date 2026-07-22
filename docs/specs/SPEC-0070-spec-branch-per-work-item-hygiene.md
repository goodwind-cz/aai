---
id: spec-branch-per-work-item-hygiene
type: spec
number: 70
status: draft
ceremony_level: 1
links:
  requirement: docs/issues/ISSUE-0024-branch-per-work-item-hygiene.md
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — deterministic branch-per-work-item hygiene guard

SPEC-FROZEN: true

Ceremony justification: the scope is exactly one NEW non-protected script
(`.aai/scripts/branch-guard.mjs`), its own new test suite
(`tests/skills/test-aai-branch-guard.sh`), one additive precondition paragraph
in `.aai/SKILL_PR.prompt.md` (prompt text, not `WORKFLOW.md`), and one additive
note in `.aai/AGENTS.md` (docs). None of these paths appear in
`protected_paths_l3` (docs/ai/docs-audit.yaml): `.aai/scripts/state.mjs`,
`.aai/scripts/lib/state-engine.mjs`, `.aai/scripts/lib/state-core.mjs`,
`.aai/scripts/allocate-doc-number.mjs`, `.aai/scripts/pre-commit-checks.sh`,
`.aai/scripts/pre-commit-checks.ps1`, `.aai/workflow/WORKFLOW.md`,
`docs/CONSTITUTION.md`. The new script IMPORTS two READ-ONLY helper functions
(`splitLines`, `findBlock`/`readScalar`) from `lib/state-core.mjs` /
`lib/state-engine.mjs` — the same read-only pattern already used by
`.aai/scripts/orchestration-dispatch.mjs` (a non-protected script) — but never
writes to those files or to `docs/ai/STATE.yaml`, so it does not touch the
protected surface. Single reviewable, reversible surface -> Level 1.

## Links
- Requirement: docs/issues/ISSUE-0024-branch-per-work-item-hygiene.md
- Decision records: n/a
- Technology contract: docs/TECHNOLOGY.md

## Problem

`SKILL_PR.prompt.md` step 5 pushes "the current branch" (`git push -u origin
<branch>`) without ever defining, creating, or checking `<branch>`. Branch
creation exists only in `SKILL_WORKTREE.prompt.md` (the L3 worktree path), so
every inline (L0-L2) work item pushes whatever branch happens to be checked
out. `AGENTS.md` gives no branch guidance at all. Observed downstream: an
agent kept doing new work-item work on a long-lived, misleadingly-named branch,
piling unrelated scopes onto one branch, with no gate to catch that the branch
did not correspond to the current `current_focus.ref_id`.

## Scope
- In scope: a new script `.aai/scripts/branch-guard.mjs`; a new test suite
  `tests/skills/test-aai-branch-guard.sh`; an additive "0. BRANCH HYGIENE"
  precondition in `.aai/SKILL_PR.prompt.md`; an additive one-branch-per-
  work-item note in `.aai/AGENTS.md`; this spec doc.
- Out of scope: `SKILL_WORKTREE.prompt.md` (already creates branches
  correctly for the L3 path), `WORKFLOW.md`, `state.mjs`/`state-engine.mjs`/
  `state-core.mjs`/`allocate-doc-number.mjs`/`pre-commit-checks.{sh,ps1}`/
  `CONSTITUTION.md` (no changes to any protected surface), any STATE.yaml
  schema change (the guard reads `current_focus.ref_id`/`.type` read-only),
  automatic branch creation/auto-carry of already-COMMITTED changes (fail
  closed with guidance instead — no history rewrite, no cherry-pick, no
  force-push).
- Protected paths touched: none.

## Design — branch-guard.mjs contract

CLI: `node .aai/scripts/branch-guard.mjs [--base <branch>] [--suggest] [--state <path>]`

- `--base <branch>`: base branch to compare against; default `main`.
- `--state <path>`: override the STATE.yaml path; default
  `<git-toplevel>/docs/ai/STATE.yaml` (toplevel resolved via
  `git rev-parse --show-toplevel`, so the guard works from any subdirectory
  of the current repo, including a throwaway test fixture repo).
- `--suggest`: print the canonical branch name only (see mapping below) and
  exit; skips every git-branch check (base/detached/mismatch) — it only needs
  `current_focus.ref_id`/`.type`, since it is meant to run before a branch
  exists yet.

Deterministic check order (guard mode, no `--suggest`) — EARLIER checks win
when more than one condition is true, so behavior is fully deterministic:

1. Confirm the cwd is inside a git work tree (`git rev-parse
   --is-inside-work-tree`). Not a repo -> exit 4 (config/usage error).
2. Read the current branch (`git rev-parse --abbrev-ref HEAD`). Literal
   `HEAD` means detached -> exit 2, remediation to stderr.
3. Read STATE.yaml (read-only, via the same `lib/state-core.mjs` /
   `lib/state-engine.mjs` helpers `orchestration-dispatch.mjs` already uses)
   and extract `current_focus.ref_id` and `current_focus.type`. Unreadable
   file, or empty/null `ref_id` -> exit 4, stderr names the missing piece
   (`current_focus.ref_id is not set in STATE.yaml`). No branch check is
   attempted without a ref_id (there is nothing to compare against).
4. Current branch equals the base branch -> exit 1, remediation to stderr.
5. Current branch does NOT contain the ref_id slug as a substring -> exit 3,
   remediation to stderr.
6. Otherwise -> exit 0, stdout confirms `<branch>` matches `current_focus.ref_id
   <ref_id>`.

Convention (per intake constraint): the branch name must CONTAIN the ref_id
slug; the `<type>` prefix is NOT validated on the pass path (tolerates the
existing repo convention, e.g. `fix/test-018-workspace-isolation`).

Remediation string (identical shape on every non-zero exit, printed to
stderr): `git checkout -b <type-token>/<ref-id> origin/<base>` — copy-
pasteable, using the type-token mapping below and the resolved `--base` value.

Type-token mapping (`current_focus.type` -> branch type-token), used ONLY to
construct the `--suggest` output and the remediation string, deterministic and
closed:

| current_focus.type    | type-token |
|------------------------|------------|
| intake_issue            | fix        |
| intake_hotfix            | fix        |
| intake_change            | feat       |
| intake_prd                | feat       |
| intake_rfc                | feat       |
| intake_release            | chore      |
| intake_research           | chore      |
| technology_extraction     | chore      |
| maintenance                | chore      |
| none / unrecognized          | chore      |

Exit code contract (closed set):
- 0 — branch matches `current_focus.ref_id`, neither base nor detached.
- 1 — current branch equals the base branch.
- 2 — HEAD is detached.
- 3 — current branch name does not contain the ref_id slug.
- 4 — config/usage error (not a git repo, STATE.yaml unreadable,
  `current_focus.ref_id` empty/null, bad flag).

## SKILL_PR.prompt.md change

Add a new precondition, first in the PRECONDITIONS list (before "Validation
PASS recorded..."), so it gates staging AND push, not just push:

```
0. BRANCH HYGIENE — run `node .aai/scripts/branch-guard.mjs --base <base>`
   (base ref from `docs/ai/STATE.yaml` `worktree.base_ref`, default `main`)
   before any other precondition or git write. Exit 0: proceed. Non-zero:
   STOP — print the guard's stderr remediation verbatim; do not stage,
   commit, or push.
```

## AGENTS.md change

Add a short "one branch per work item" note (near the existing "Worktree and
review policy" subsection) stating: every work item is developed on a
dedicated branch containing its `current_focus.ref_id`; `SKILL_PR`'s "0.
BRANCH HYGIENE" precondition (`.aai/scripts/branch-guard.mjs`) fails closed
before any push if the branch is the base branch, detached, or does not
correspond to the current ref_id.

## Fail-closed / no-history-rewrite constraint

If in-scope changes are already COMMITTED on a wrong/shared branch, the guard
only reports the violation and prints remediation — it never cherry-picks,
rebases, or force-pushes. Only UNCOMMITTED working-tree changes may safely be
carried forward via `git checkout -b <type>/<ref-id> origin/<base>` (git
preserves uncommitted changes across a fresh branch checkout by design); this
is documented as operator/agent guidance in the remediation text, not
automated by the script.

## Implementation strategy
- Strategy: hybrid
- Rationale: `branch-guard.mjs` is new deterministic logic with five distinct
  exit-code branches and a precedence order that must not regress silently —
  TDD RED-GREEN-REFACTOR is warranted per TEST-001..006 (RED-proof: the file
  does not exist before implementation, so every invocation fails before the
  fix). The `.aai/SKILL_PR.prompt.md` precondition and `.aai/AGENTS.md` note
  (TEST-007/TEST-008) are simple additive prompt/doc text with no branching
  logic — loop implementation for those two files, verified by the same
  RED-proof discipline (grep observed failing before, passing after).

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single new script + its own test file + two additive
  prompt/doc edits, small, reversible, no protected path touched. The current
  session is already on a dedicated branch (`fix/branch-per-work-item-
  hygiene`) that itself satisfies the convention this spec formalizes.
- User decision: inline (already recorded in STATE: `worktree.user_decision:
  inline`, `base_ref: main`)
- Base ref: main
- Worktree branch/path: fix/branch-per-work-item-hygiene (inline)
- Inline review scope: `.aai/scripts/branch-guard.mjs`,
  `tests/skills/test-aai-branch-guard.sh`, `.aai/SKILL_PR.prompt.md`,
  `.aai/AGENTS.md`, `docs/specs/SPEC-DRAFT-spec-branch-per-work-item-
  hygiene.md`

## Acceptance Criteria Mapping

- Requirement (Verification bullet 1: fail-closed on base/detached/mismatch,
  pass on correct branch) -> Spec-AC-01, Spec-AC-02.
- Requirement (Verification bullet 1, fail-closed default when STATE/ref_id
  cannot be resolved) -> Spec-AC-03.
- Requirement (Verification bullet 2: `--suggest` mode) -> Spec-AC-04.
- Requirement (Verification bullet 3: SKILL_PR precondition) -> Spec-AC-05.
- Requirement (Verification bullet 3: AGENTS.md documents the rule) ->
  Spec-AC-06.
- Requirement (Verification bullet 4: executable tests, green on macOS and
  Linux CI) -> covered by every TEST-xxx below (portable bash/mktemp/git
  fixtures per docs/knowledge/LEARNED.md 2026-07-19 rules).

- Maps to: Requirement Verification bullet 1
- Spec-AC-01: On a branch whose name contains `current_focus.ref_id` and is
  neither the base branch nor detached, `branch-guard.mjs --base <base>`
  exits 0 and prints a confirmation naming the branch and the ref_id.
  - Verification: `bash tests/skills/test-aai-branch-guard.sh
    test_001_correct_branch_passes` -> exit 0.

- Maps to: Requirement Verification bullet 1
- Spec-AC-02: `branch-guard.mjs` FAILS CLOSED (non-zero) on each of the three
  violation classes, each with its own distinct exit code and a stderr
  remediation line of the exact form `git checkout -b <type-token>/<ref-id>
  origin/<base>`: on the base branch (exit 1), HEAD detached (exit 2), and a
  branch name that does not contain the ref_id slug (exit 3). The detached
  check does not require a readable STATE.yaml (checked before the STATE
  read).
  - Verification: `bash tests/skills/test-aai-branch-guard.sh
    test_002_on_base_branch_fails` -> exit 0 (test script itself always
    exits 0 on assertion success; it asserts the GUARD exits 1);
    `test_003_detached_head_fails` -> asserts guard exit 2;
    `test_004_mismatched_branch_fails` -> asserts guard exit 3.

- Maps to: Requirement Verification bullet 1 (fail-closed default)
- Spec-AC-03: When STATE.yaml is unreadable or `current_focus.ref_id` is
  empty/null, both guard mode and `--suggest` mode exit 4 with a stderr
  message naming the missing piece — never a silent pass. This precedence
  wins over base-branch and detached checks where STATE is the first
  resolvable failure per the check order (Design section item 3 before 4/5;
  detached at item 2 still wins over a broken STATE per item 2 before 3).
  - Verification: `bash tests/skills/test-aai-branch-guard.sh
    test_005_config_error_fails_closed` -> asserts guard mode exit 4,
    `--suggest` exit 4, and the base-branch-plus-broken-STATE /
    detached-plus-broken-STATE precedence sub-cases.

- Maps to: Requirement Verification bullet 2
- Spec-AC-04: `branch-guard.mjs --suggest` prints, to stdout only, exactly
  `<type-token>/<ref-id>` per the closed type-token mapping and exits 0,
  performing no git branch check (works identically from the base branch).
  - Verification: `bash tests/skills/test-aai-branch-guard.sh
    test_006_suggest_prints_canonical_name` -> asserts stdout equals the
    expected string for each of the 10 mapped `current_focus.type` values.

- Maps to: Requirement Verification bullet 3 (SKILL_PR precondition)
- Spec-AC-05: `.aai/SKILL_PR.prompt.md` contains a `0. BRANCH HYGIENE`
  precondition line that names `branch-guard.mjs` and instructs STOP on
  non-zero exit, positioned before every numbered PROCESS step (including
  step "5. PUSH + PR") so it gates staging and push alike.
  - Verification: `bash tests/skills/test-aai-branch-guard.sh
    test_007_skill_pr_precondition_present` -> exit 0. RED-proof: today's
    `.aai/SKILL_PR.prompt.md` contains no `BRANCH HYGIENE` text at all
    (`grep -c` = 0); the test is observed FAILING before this change.

- Maps to: Requirement Verification bullet 3 (AGENTS.md rule)
- Spec-AC-06: `.aai/AGENTS.md` contains a one-branch-per-work-item note that
  references `branch-guard.mjs`.
  - Verification: `bash tests/skills/test-aai-branch-guard.sh
    test_008_agents_md_documents_rule` -> exit 0. RED-proof: today's
    `.aai/AGENTS.md` contains no such note (`grep -c` = 0); the test is
    observed FAILING before this change.

## Constitution deviations

None.

<!-- Art.1 evidence-before-claims: measurable exit-code AC + TEST-xxx, no
  PASS claim in planning. Art.2 KISS/YAGNI: no STATE schema change, reuses
  the existing read-only lib helpers instead of a new parser. Art.3
  portability: plain `.mjs` (node stdlib only) + bash-3.2-compatible test
  suite, full mktemp templates, GNU-stat-first, `git init -b main` fixtures
  per docs/knowledge/LEARNED.md. Art.4 degrade-and-report: every failure path
  prints an explicit, actionable remediation to stderr; never silent. Art.5
  additive: new file + additive precondition/note, no existing contract
  changed. Art.6 single-writer: the guard NEVER writes STATE.yaml — read-only
  import of `lib/state-core.mjs`/`lib/state-engine.mjs` functions, same
  pattern as `orchestration-dispatch.mjs`. Art.7 operator-only merge: this
  spec does not touch the PR merge boundary; the SKILL_PR precondition only
  adds a pre-push STOP gate, never an auto-merge or auto-push override. -->

## Seam analysis

One seam: `docs/ai/STATE.yaml` `current_focus.ref_id`/`.type` is WRITTEN only
by `state.mjs` (Constitution Art. 6, single writer) and is now READ by a
second consumer (`branch-guard.mjs`) in addition to the existing
`orchestration-dispatch.mjs`. Mitigated by construction rather than by a
mocked unit test: `branch-guard.mjs` reuses the EXACT SAME read-only helper
functions (`splitLines`, `findBlock`, `readScalar`) from
`lib/state-core.mjs`/`lib/state-engine.mjs` that `orchestration-dispatch.mjs`
already uses — there is no independent parsing logic that could drift or
disagree with the writer's format. The seam is still crossed end-to-end by an
INTEGRATION test rather than a hand-written STATE.yaml fixture: TEST-001 sets
`current_focus.ref_id` via the REAL writer (`node .aai/scripts/state.mjs
set-focus ...`) in a throwaway fixture repo, then runs `branch-guard.mjs`
against that same repo's STATE.yaml and asserts it reads back the value the
writer produced — producer (state.mjs) and consumer (branch-guard.mjs) are
both exercised for real, not mocked on either side.

No other seam: the guard's own output (exit code + stderr text) is consumed
only by `SKILL_PR.prompt.md` (an LLM-followed prompt, not a second code
path) and by an interactive human/agent running `--suggest` directly; neither
is a second WRITER of any shared state.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Correct `<type>/<ref-id>` branch -> exit 0                          | done | TEST-001 green; docs/ai/tdd/green-branch-guard-20260722T214726Z.log | — | RED docs/ai/tdd/red-branch-guard-20260722T214622Z.log |
| Spec-AC-02 | Base branch / detached / mismatch -> distinct non-zero exit + remediation | done | TEST-002/003/004 green; docs/ai/tdd/green-branch-guard-20260722T214726Z.log | — | exit 1/2/3 asserted |
| Spec-AC-03 | STATE/ref_id unresolvable -> exit 4, fail-closed default, correct precedence | done | TEST-005 green; docs/ai/tdd/green-branch-guard-20260722T214726Z.log | — | base<-STATE, detached<-STATE precedence asserted |
| Spec-AC-04 | `--suggest` prints canonical `<type-token>/<ref-id>`                | done | TEST-006 green (all 10 types); docs/ai/tdd/green-branch-guard-20260722T214726Z.log | — | stdout-only |
| Spec-AC-05 | SKILL_PR gains "0. BRANCH HYGIENE" precondition before PUSH         | done | TEST-007 green; .aai/SKILL_PR.prompt.md | — | precedes PUSH step |
| Spec-AC-06 | AGENTS.md documents one-branch-per-work-item rule                   | done | TEST-008 green; .aai/AGENTS.md | — | names branch-guard.mjs |

## Implementation plan
- Components/modules affected: new `.aai/scripts/branch-guard.mjs` (imports
  read-only helpers from `.aai/scripts/lib/state-core.mjs` and
  `.aai/scripts/lib/state-engine.mjs`, same pattern as
  `.aai/scripts/orchestration-dispatch.mjs`); new
  `tests/skills/test-aai-branch-guard.sh`; additive edits to
  `.aai/SKILL_PR.prompt.md` (PRECONDITIONS list) and `.aai/AGENTS.md`
  (near "Worktree and review policy").
- Data flow: `git rev-parse` (branch/detached/repo-root probes, read-only) +
  `docs/ai/STATE.yaml` (read-only, via the shared line-engine helpers) ->
  deterministic exit code + stderr/stdout text. No writes anywhere.
- Edge cases: ref_id that is a substring of an unrelated longer branch name
  (accepted per the intake's explicit "CONTAINS" convention — not tightened
  here); base branch also containing the ref_id substring coincidentally
  (base-branch check runs BEFORE the containment check, so base always wins
  and is reported as exit 1, not exit 0); `--suggest` with an unmapped/blank
  `current_focus.type` falls back to the `chore` type-token (closed mapping,
  never throws); repo with no commits yet / no `main` branch (guard only
  needs the CURRENT branch name and STATE, not the base branch's existence,
  so it still resolves correctly — `--base` is a string comparison, not a
  ref lookup).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                     | Description                                                                                                                   | Status  |
|----------|------------|-------------|-------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-branch-guard.sh     | Throwaway git+AAI-fixture repo: `state.mjs set-focus` (real writer) sets `current_focus.ref_id`; checkout `fix/<ref-id>`; guard exits 0, stdout names branch+ref_id. RED-proof: script does not exist pre-fix, invocation fails (non-zero/ENOENT). | green   |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-branch-guard.sh     | On the base branch itself (same ref_id set) -> guard exit 1; stderr contains the exact `git checkout -b fix/<ref-id> origin/main` remediation line. RED-proof: pre-fix, script absent, cannot produce exit 1.                | green   |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-branch-guard.sh     | Detached HEAD (`git checkout --detach <sha>`), including a sub-case with STATE.yaml ALSO broken -> guard exit 2 both times (proves detached check precedes the STATE read); stderr remediation present. RED-proof: pre-fix, script absent. | green   |
| TEST-004 | Spec-AC-02 | unit        | tests/skills/test-aai-branch-guard.sh     | Branch name that does not contain the ref_id slug (e.g. `feat/unrelated-name`) -> guard exit 3; stderr remediation present. RED-proof: pre-fix, script absent.                                                                | green   |
| TEST-005 | Spec-AC-03 | unit        | tests/skills/test-aai-branch-guard.sh     | STATE.yaml with `current_focus.ref_id` empty/null -> guard mode exit 4 AND `--suggest` exit 4, stderr names `ref_id`; sub-case on the base branch with broken STATE still exits 4 (not 1), proving the documented precedence. RED-proof: pre-fix, script absent. | green   |
| TEST-006 | Spec-AC-04 | unit        | tests/skills/test-aai-branch-guard.sh     | `--suggest` on the base branch prints exactly `<type-token>/<ref-id>` to stdout and exits 0, for each of the 10 rows of the type-token mapping table. RED-proof: pre-fix, script absent.                                       | green   |
| TEST-007 | Spec-AC-05 | unit        | tests/skills/test-aai-branch-guard.sh     | `.aai/SKILL_PR.prompt.md` contains a `0. BRANCH HYGIENE` line naming `branch-guard.mjs` + STOP wording, at a line number before the `5. PUSH + PR` line. RED-proof: `grep -c 'BRANCH HYGIENE' .aai/SKILL_PR.prompt.md` = 0 today (observed failing pre-change). | green   |
| TEST-008 | Spec-AC-06 | unit        | tests/skills/test-aai-branch-guard.sh     | `.aai/AGENTS.md` contains a one-branch-per-work-item note naming `branch-guard.mjs`. RED-proof: `grep -c` = 0 today (observed failing pre-change).                                                                             | green   |

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- All eight tests live in ONE new suite file, `tests/skills/test-aai-branch-
  guard.sh`, following the existing `tests/skills/test-aai-*.sh` convention
  (bash-3.2 compatible, `set -euo pipefail`, full `mktemp -d
  ".../XXXXXX"` templates, `git init -b main` fixtures, honors its own
  `#!/usr/bin/env bash` shebang, exit 0 pass / 1 fail / 42 skip, auto-
  discovered — no manifest registration needed).
- RED-proof obligation: TEST-001..006 are RED-proof by construction — the
  script under test does not exist before implementation, so every
  invocation fails before the fix and is expected to pass only after
  `branch-guard.mjs` is implemented (a standard new-file RED-GREEN cycle,
  not a tautological always-green test). TEST-007/008 are RED-proof via an
  explicit pre-change `grep -c` = 0 assertion against the current file
  content, captured as evidence before the prompt/docs edit lands.
- Portability (docs/knowledge/LEARNED.md, Session 2026-07-19): full `mktemp`
  templates (no bare `-t` prefix), `git init -b main` (never assume a local
  `main` exists by default), honor the suite's own shebang when invoked by
  `aai-run-tests.sh`, no `stat -f`-first pattern anywhere in this suite (not
  needed here, but kept consistent with the rest of the test layer).

## Verification
- `bash tests/skills/test-aai-branch-guard.sh` -> exit 0 (all 8 cases).
- `.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-branch-guard.sh`
  -> exit 0 (process-group-wrapped run, matches CI invocation).
- Manual spot check: `node .aai/scripts/branch-guard.mjs --suggest` on this
  very branch (`fix/branch-per-work-item-hygiene`,
  `current_focus.ref_id: branch-per-work-item-hygiene`,
  `current_focus.type: intake_issue`) prints `fix/branch-per-work-item-
  hygiene`, matching the branch this session is already on.
- Post-freeze advisory: `node .aai/scripts/spec-lint.mjs --path
  docs/specs/SPEC-0070-spec-branch-per-work-item-hygiene.md` (report-only).
- PASS criteria: all TEST-001..008 green; all Spec-AC in a terminal (`done`)
  status with non-empty evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: branch-per-work-item-hygiene (SPEC-000N at merge)
- Spec-AC and TEST-xxx links (Spec-AC-01/TEST-001, Spec-AC-02/TEST-002..004,
  Spec-AC-03/TEST-005, Spec-AC-04/TEST-006, Spec-AC-05/TEST-007,
  Spec-AC-06/TEST-008)
- command or review scope
- exit code or review verdict
- evidence path (RED/GREEN logs under docs/ai/tdd/ for the TDD-strategy
  portion; review under docs/ai/reviews/)
- commit SHA or diff range when available
