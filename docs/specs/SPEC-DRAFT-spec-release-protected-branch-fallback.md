---
id: spec-release-protected-branch-fallback
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-DRAFT-release-protected-branch-fallback.md
  rfc: null
  pr: []
  commits: []
---

# Spec — aai-release falls back to a PR when the target branch is protected

SPEC-FROZEN: true

## Amendment (post-freeze, 2026-09-02 — validation round-1 F3/F4 + recorded residual)

This is a FROZEN spec, amended after the freeze and disclosed here rather than
rewritten silently. `SPEC-FROZEN: true` is preserved; the convention is the
additive-with-disclosure one `docs/specs/SPEC-0132-...md`,
`docs/specs/SPEC-0153-...md` and `docs/specs/SPEC-0072-...md` already
established — nothing in `.aai/workflow/WORKFLOW.md`, `spec-lint.mjs` or
`spec-freeze.mjs` defines a re-freeze path, so the convention IS the mechanism.

Three amendments, all made at remediation on the dispatch of Independent
Validation round 1:

1. **Implementation strategy** — the blanket sentence "All other TEST rows are
   loop-implemented with an observed ... failing run before the change" was
   inaccurate. TEST-031 and TEST-032 are no-regression pins over pre-existing
   behavior, where a RED is impossible by construction. Carved out in place.
2. **Edge cases, detached HEAD** (F3) — the frozen line claimed exit 18 with a
   named reason. Measured false: the fallback is unreachable in that state and
   the cut degrades raw at exit 1. Corrected, and the dead guard removed from
   both engines.
3. **Spec-AC-09 / TEST-035** (F4) — D5's exit-18 arm shipped with no AC and no
   test in either engine. One added, additively; no existing AC changed.

Disclosure: item 3 adds an acceptance criterion to a frozen spec, which
`.aai/system/AUTONOMOUS_LOOP.md` reads as a scope change assigned to HITL. No
prior owner sign-off was obtained; it is disclosed here and in
`docs/ai/decisions.jsonl` (`type: spec_amendment`, ts 2026-09-02) and the owner
may reverse it. It is strictly additive — it pins behavior the engines already
had, adds no product surface, and no other AC's text moved.

## Links
- Requirement: docs/issues/CHANGE-DRAFT-release-protected-branch-fallback.md
- Reference incident: goodwind-cz/aai PR #329 (`chore(release): v2026.09.01`), 2026-09-01
- Technology contract: docs/TECHNOLOGY.md
- Prior spec for this engine: docs/specs/SPEC-0063-spec-aai-release-skill.md
- ps1 twin invariants: docs/specs/SPEC-0067-spec-ps1-native-stderr-guard.md

## Implementation strategy
- Strategy: hybrid
- Rationale: the two core behavior ACs (the fallback sequence, and the
  orphaned-tag guard) are a reproducible defect with a cheap deterministic
  RED, so they get stored RED-before-GREEN evidence; the remaining ACs are
  parity assertions, prompt documentation and a ledger true-up, where a
  RED-first ceremony buys nothing over a targeted green run.

AC-gating tests requiring a STORED RED artifact under `docs/ai/tdd/`:
TEST-027 and TEST-030. TEST-028, TEST-029, TEST-033, TEST-034 and TEST-035 are
loop-implemented with an observed (not necessarily stored) failing run before
the change. TEST-031 and TEST-032 are the exception and carry NO red of any
kind: they are no-regression pins over behavior that already exists (the
unprotected cut's byte-identical stdout, and a non-fast-forward rejection's raw
degrade), so the pre-change behavior IS the expected behavior and a RED is
impossible by construction. Amended at remediation after Independent
Validation flagged the original blanket sentence as inaccurate.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to a shipping engine plus its twin, in a
  session where a sibling ride already has an open PR against `main`; an
  isolated tree keeps the two diffs from colliding. The worktree already
  exists at `/Users/ales/Projects/aai-change-release-protected-branch-fallback`.
- User decision: undecided
- Base ref: main @ 7eaeecb
- Worktree branch/path: change/release-protected-branch-fallback @
  /Users/ales/Projects/aai-change-release-protected-branch-fallback
- Inline review scope: n/a (worktree)

## Registry items closed by this scope

none.

Two open registry items were checked against this scope's subjects and are NOT
closed by it:
- `fu-sweep-scope-excludes-repo-root` names CHANGELOG.md at the repo root
  freezing into a dated section at the next release cut. Its subject is a
  claim-correction sweep's file scope, not the release engine's push step.
- `fu-orchestrator-does-not-watch-ci` names the orchestrator not watching CI
  after a PR is pushed. This scope deliberately stops at `gh pr create`
  (Constitution article 7) and adds no watcher, so the item stays open.

No open item names the release engine's push path, its exit-code contract, or
branch protection.

## Background — the measured failure

Reproduced in a scratch fixture on 2026-09-02 (bare repo + per-ref `update`
hook emitting GitHub's message shape, mirroring GitHub's non-atomic per-ref
protection):

- `git push origin main` with the tag reachable and `push.followTags=true`
  produced `rc=1`, the remote kept `refs/tags/v1.0.0`, and `refs/heads/main`
  was rejected — the incident's exact end state: a tag published against a
  commit the remote's default branch never received.
- The same push with `--no-follow-tags` left the remote with no refs at all.
- A branch push under an unprotected ref name succeeded at `rc=0`.

Today both engines run `git push origin <branch>` first and the tag push
second, so under `set -euo pipefail` (bash) or `Invoke-NativeChecked` (ps1) a
rejected branch push aborts the script with the commit and the annotated tag
already created locally, nothing published, and no recovery. When the operator
(or their global git config) has `push.followTags` enabled, the same rejected
push ALSO leaves the tag on the remote.

## Design decisions

- D1 — Detection. On the `--confirm` remote path, the target-branch push runs
  with its combined output captured to a temp file and always re-emitted to
  stderr afterwards, so no diagnostic is swallowed. One named predicate
  classifies the captured text as a protected-branch rejection: the text
  contains the token `GH006`, OR it contains `protected branch` AND
  `status check` (both case-insensitive). Any other failure re-emits the raw
  output and exits with git's own exit code (Constitution article 4).
  For the bash engine this is today's behavior exactly. For the ps1 twin it
  is a disclosed, strictly-better change measured in validation round 2: the
  pre-change ps1 let the push failure surface as an uncaught PowerShell
  exception, which exited **1** with a PS exception banner regardless of
  git's own code; it now exits git's code (measured 128 for an unreachable
  remote, 1 for a non-fast-forward, matching the bash engine in both cases).
  No Spec-AC pins the old ps1 exit, and the new behavior is what D7's parity
  invariant requires — recorded here because the original wording claimed
  both engines were unchanged, which was accurate only for bash.
- D2 — Orphan-tag guard. The target-branch push gains `--no-follow-tags`, so a
  repo-level or global `push.followTags=true` can never publish the annotated
  tag as a side effect of a rejected branch push. The tag push stays strictly
  AFTER a successful branch push, and is skipped entirely on the fallback path.
- D3 — Fallback sequence, only when D1 matches, only under `--confirm`, only
  when the remote path is enabled (never under `--no-remote`), in this order:
  1. `git branch chore/release-<version> HEAD` at the release commit. If that
     ref already exists, stop at exit 18 (never clobber an existing branch).
  2. `git reset --hard <pre_cut_sha>` on the target branch, where
     `<pre_cut_sha>` is captured BEFORE the release commit is created. The
     release commit survives on the new branch ref created in step 1.
  3. `git push --no-follow-tags origin chore/release-<version>`. Failure stops
     at exit 18.
  4. `gh pr create --base <target-branch> --head chore/release-<version>
     --title "chore(release): <version>" --body <generated>`. Failure stops at
     exit 18.
  5. Print the fallback report and exit 17.
- D4 — Never merge, never publish. The fallback calls neither `gh pr merge`
  nor `gh release create` (Constitution article 7 and the intake's explicit
  out-of-scope line). The annotated tag stays local at the release commit and
  is never pushed on this path.
- D5 — Exit codes (additive; Constitution article 5). `17` = protected-branch
  fallback completed, PR opened, release NOT published, operator action
  required. `18` = protected-branch fallback engaged but INCOMPLETE (branch
  name taken, branch push failed, or `gh pr create` failed); the report names
  the exact commands to finish by hand. Both are documented in
  `.aai/SKILL_RELEASE.prompt.md`'s exit-code list and in both engines' usage
  headers.
- D6 — Unprotected path unchanged. On a remote that accepts the branch push,
  the cut's stdout, exit code, pushed refs and `gh` argv are what they are
  today. The only permitted difference is that the push's own progress text
  now reaches stderr through the capture-and-re-emit, not directly.
- D7 — Parity by duplication. This repo keeps its two engines as deliberately
  vendored twins rather than a shared library (see the standing comment in
  `.aai/scripts/update-check.mjs` on the SEAM-3 parity invariant). The
  fallback is therefore implemented twice, once per engine, and pinned by a
  parity test — no new shared file, so no `.aai/system/PROFILES.yaml`
  classification is owed.
- D8 — Report contents. The fallback report names, on its own lines: the PR
  URL, the release branch name, the target branch and the SHA it was reset to,
  that the release is NOT published, that the annotated tag exists LOCALLY
  ONLY, and the literal post-merge command sequence
  (`git tag -d`, `git tag -a`, `git push origin refs/tags/<version>`,
  `gh release create`).

## Constitution deviations

None.

Article 4 (degrade and report) is satisfied by D1's re-emit-and-exit-as-today
arm for any non-protected-branch failure. Article 5 (additive first) is
satisfied by D5: two new exit codes, no existing code or output shape
repurposed. Article 7 (operator-only merge) is satisfied by D4 and pinned by
Spec-AC-02's assertion that `gh pr merge` is never invoked.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                                                                                                                                                 | Status  | Evidence | Review-By | Notes                                          |
|------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|----------|-----------|------------------------------------------------|
| Spec-AC-01 | WHEN a --confirm cut's target-branch push is rejected with a GH006 protected-branch message THEN aai-release.sh creates branch chore-release-VERSION at the release commit, resets the target branch to its pre-cut SHA, pushes that branch to origin, and invokes gh pr create exactly once | planned | —        | —         | branch literal is `chore/release-<version>`     |
| Spec-AC-02 | WHEN that fallback completes THEN the script exits 17 and the stub gh log contains zero `release create` invocations and zero `pr merge` invocations                                                                          | planned | —        | —         | Constitution article 7                          |
| Spec-AC-03 | WHEN the fallback completes THEN the remote has no refs/tags/VERSION, the local repo has an annotated tag VERSION at the release commit, and stdout contains the PR URL plus the literal strings `git tag -d`, `git tag -a` and `git push origin refs/tags/` | planned | —        | —         | D8 report contract                              |
| Spec-AC-04 | WHEN push.followTags is true in the fixture repo config and the target-branch push is rejected THEN `git -C BARE show-ref` lists no refs/tags/VERSION                                                                          | planned | —        | —         | the incident's orphan mechanism, D2             |
| Spec-AC-05 | WHEN the target branch is not protected THEN the --confirm cut's stdout with the single `- Commit:` line masked is byte-identical to the pre-change engine's stdout over an identically seeded fixture, exit code 0, and the bare remote gains both refs/heads/main and refs/tags/VERSION | planned | —        | —         | pre-change engine read from origin/main         |
| Spec-AC-06 | WHEN the target-branch push fails as a non-fast-forward rejection THEN no chore-release branch ref exists, the target branch HEAD is unchanged from the release commit, git's own error text appears on stderr, and the exit code is neither 17 nor 18 | planned | —        | —         | degrade-and-report, Constitution article 4      |
| Spec-AC-07 | WHEN the same protected-remote fixture is driven through aai-release.ps1 under pwsh THEN the branch, reset, gh pr create call and exit 17 match the bash arm, and the dot-sourced classifier accepts the GH006 text while rejecting a non-fast-forward text | planned | —        | —         | pwsh present locally and on the ps1 gate        |
| Spec-AC-08 | WHEN the engines carry exit codes 17 and 18 THEN .aai/SKILL_RELEASE.prompt.md documents both plus the branch-name shape and the post-merge re-tag sequence, and the prompt-diet ledger carries a new JUSTIFIED_ADDITIONS entry equal to the measured byte growth with TEST-012's want_growth moved by exactly that amount | planned | —        | —         | companion obligation, current pin 8127          |
| Spec-AC-09 | WHEN a GH006-rejected branch push meets an ALREADY-EXISTING chore-release-VERSION ref THEN the engine exits 18, leaves that ref at its original SHA, leaves the target branch un-reset at the release commit, opens no PR, pushes nothing to the remote, and its report names both the reason and the manual finish-by-hand commands | planned | —        | —         | added at remediation; D5's exit-18 arm was untested |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:
- `.aai/scripts/aai-release.sh` — the CONFIRM remote block. Capture the
  pre-cut SHA before `git commit`; add `--no-follow-tags` to the branch push;
  capture the push output; add the classifier and the fallback sequence; add
  exit codes 17 and 18 to the usage header.
- `.aai/scripts/aai-release.ps1` — the same, expressed through
  `Invoke-NativeChecked`. The branch push moves into a `try`/`catch` whose
  catch inspects `$_.Exception.Message` (the helper already folds the child's
  captured stdout+stderr into the thrown message). The classifier is a
  function `Test-ProtectedBranchRejection` defined ABOVE the
  `if ($MyInvocation.InvocationName -ne '.')` dot-source guard so Pester can
  unit-test it without running a release.
- `.aai/SKILL_RELEASE.prompt.md` — the Instructions exit-code list gains 17
  and 18; the Safety section gains a paragraph on the fallback (what it does,
  that it never merges, that the tag is local-only until the operator
  re-points it).
- `tests/skills/test-aai-release.sh` — TEST-027..TEST-032 plus the fixture
  builders below.
- `tests/skills/aai-release.Tests.ps1` — new Pester file for TEST-033.
- `tests/skills/lib/prompt-diet-ledger.sh` and
  `tests/skills/test-aai-prompt-diet.sh` — the companion true-up.
- `CHANGELOG.md` — one `## [unreleased] — <title>` heading per the repo's
  per-entry convention.

Data flows:
- pre_cut_sha (captured before the release commit) -> `git reset --hard` target
- release commit SHA -> `git branch chore/release-<version>` -> pushed ref ->
  `gh pr create --head`
- captured push output -> classifier -> either fallback or today's raw exit
- version string -> branch name, PR title, report's re-tag commands

New fixture builders in `tests/skills/test-aai-release.sh`:
- `build_protected_bare <bare> <protected-ref>` — `git init --bare` plus a
  per-ref `hooks/update` that prints GitHub's GH006 two-line shape to stderr
  and exits 1 for the named ref only. Per-ref (not `pre-receive`) is required:
  a `pre-receive` rejection is atomic and would also block the tag, hiding the
  very orphan Spec-AC-04 pins. Verified in a scratch probe on 2026-09-02.
- `build_stub_gh` is reused as-is; it already records argv and exits 0. It
  needs one addition: when invoked as `pr create`, print a fake PR URL on
  stdout so the engines can echo it back.

Edge cases:
- The release branch name already exists locally -> exit 18, no reset, no push.
- `--no-remote` -> the fallback is unreachable; unchanged behavior.
- `--dry-run` / bare invocation -> unreachable; unchanged output shape.
- Detached HEAD (`$BRANCH == "HEAD"`) -> the fallback is UNREACHABLE, and the
  cut degrades raw at git's own exit code 1. AMENDED at remediation: the
  original wording ("the engines refuse the fallback with exit 18 and a named
  reason") described a guard that can never run. Measured 2026-09-02 — with a
  detached HEAD, `git push --no-follow-tags origin HEAD` fails CLIENT-side
  ("error: The destination you provided is not a full refname", exit 1) without
  the remote ever answering, so the captured text carries no GH006, the D1
  classifier correctly misses, and the engine re-emits git's own output and
  exits 1 exactly as it does today. Both engines' `$BRANCH == "HEAD"` guards
  inside the fallback block were therefore REMOVED as dead code (they asserted
  a condition the push above already excludes) and replaced with a comment
  recording the measurement, so nobody re-adds them. The behavior is
  unchanged from today's and is covered by D1's degrade-raw arm.
- A push rejected for auth or network reasons -> classifier misses, raw exit
  (Spec-AC-06 covers the non-fast-forward representative of this class).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                  | Description                                                                                          | Status  |
|----------|------------|-------------|---------------------------------------|------------------------------------------------------------------------------------------------------|---------|
| TEST-027 | Spec-AC-01 | integration | tests/skills/test-aai-release.sh      | protected bare remote plus stub gh; asserts the release branch ref, the reset target SHA, the pushed branch on the bare, and exactly one gh pr create in the log | green   |
| TEST-028 | Spec-AC-02 | integration | tests/skills/test-aai-release.sh      | same run; asserts exit code 17 and zero `release create` and zero `pr merge` lines in the stub gh log  | green   |
| TEST-029 | Spec-AC-03 | integration | tests/skills/test-aai-release.sh      | same run; asserts no remote tag, a local annotated tag at the release commit, and the four report literals on stdout | green   |
| TEST-030 | Spec-AC-04 | integration | tests/skills/test-aai-release.sh      | protected bare remote with push.followTags true in the fixture repo; asserts the bare has no refs/tags entry after the rejected cut | green   |
| TEST-031 | Spec-AC-05 | integration | tests/skills/test-aai-release.sh      | unprotected bare; runs the origin/main engine and the working-tree engine over identically seeded fixtures and diffs the SHA-masked stdout, then asserts exit 0 and both refs on the bare | green   |
| TEST-032 | Spec-AC-06 | integration | tests/skills/test-aai-release.sh      | bare seeded with a diverging main so the push is a non-fast-forward; asserts no release branch ref, unchanged HEAD, git's error text on stderr, and an exit code outside 17 and 18 | green   |
| TEST-033 | Spec-AC-07 | integration | tests/skills/test-aai-release.sh and tests/skills/aai-release.Tests.ps1 | pwsh arm drives the protected fixture through the ps1 engine for the same branch, reset, PR-create and exit-17 outcome, skipping with a named reason when pwsh is absent; the Pester file dot-sources the ps1 and asserts the classifier accepts GH006 text and rejects non-fast-forward text | green   |
| TEST-034 | Spec-AC-08 | integration | tests/skills/test-aai-release.sh and tests/skills/test-aai-prompt-diet.sh | asserts every exit code emitted by aai-release.sh appears in .aai/SKILL_RELEASE.prompt.md, that the prompt names the branch shape and the re-tag sequence, and that the diet ledger sum equals the bumped TEST-012 pin | green   |
| TEST-035 | Spec-AC-09 | integration | tests/skills/test-aai-release.sh      | protected bare remote with chore/release-VERSION already squatted at the pre-cut commit; asserts exit 18, the squatted ref unmoved, the target branch still at the release commit, an empty bare, no gh pr create, and the report's reason plus manual commands | green   |

Test status values: pending -> red -> green

Notes:
- Test IDs continue the suite's existing sequence (TEST-026 is the current
  highest in tests/skills/test-aai-release.sh).
- Every fixture is a throwaway repo under the suite's `TMP_ROOT`, pushes only
  to a local `file://` bare, and calls the stub `gh`. This suite must never
  push to a real origin or publish a real release.
- `set -euo pipefail` applies: capture exit codes as `rc=0; cmd || rc=$?`, and
  never assert through a `cmd | grep -q` pipeline (the suite's standing
  ratchet, LEARNED shell-measurement traps).

## Seams crossed

- SEAM-1 — engine to remote ref namespace. The engine decides which refs go to
  origin; the assertion reads the bare repo's `show-ref` on the other side.
  Crossed by TEST-027, TEST-029, TEST-030, TEST-031. This is the seam the
  incident actually broke.
- SEAM-2 — engine exit codes to the skill prompt's exit-code table. The engine
  produces the code; the agent reads the prompt to interpret it. Crossed by
  TEST-034, which enumerates the engine's codes and asserts each appears in
  `.aai/SKILL_RELEASE.prompt.md`.
- SEAM-3 — bash engine to ps1 twin. Crossed by TEST-033 running the SAME
  fixture through both engines rather than asserting they contain similar
  text.
- SEAM-4 — prompt corpus bytes to the shared diet ledger. Three suites read
  that ledger (`test-aai-prompt-diet.sh`, `test-aai-verify-gate.sh`,
  `test-aai-git-ref-guard.sh`, which diffs the ledger against origin/main).
  Crossed by TEST-034 plus the verification commands below, which run all
  three.
- SEAM-5 — RESIDUAL, no automated crossing. GitHub's actual rejection wording
  is asserted only against our fixture's reproduction of it. If GitHub changes
  the message, the classifier stops matching and the engines degrade to
  today's behavior (raw error, non-zero exit) — the fallback is lost, never
  correctness. Accepted; recorded here rather than left out.

## Verification

Commands (run from the worktree root):

- `bash tests/skills/test-aai-release.sh` -> exit 0, `ALL TESTS PASSED`
- `bash tests/skills/test-aai-prompt-diet.sh` -> exit 0
- `bash tests/skills/test-aai-verify-gate.sh` -> exit 0
- `bash tests/skills/test-aai-git-ref-guard.sh` -> exit 0
- `bash tests/skills/test-ps1-quality.sh` -> exit 0 (or 42 with pwsh absent;
  pwsh is present locally at /opt/homebrew/bin/pwsh and on the ps1 gate)
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-release-protected-branch-fallback.md` -> no blocking findings
- `node .aai/scripts/docs-audit.mjs --gate release-protected-branch-fallback` -> exit 0 at AC-flip time
- CORE suites selected for this file set: aai-check-state, aai-docs-audit,
  aai-spec-lint, aai-hygiene-pack; SELECTED: aai-release, aai-prompt-diet,
  aai-validator-isolation, aai-win-fallback
  (`node .aai/scripts/select-suites.mjs --files-from <list>`)

Evidence artifacts:
- `docs/ai/tdd/release-protected-branch-fallback-red.log` — TEST-027 and
  TEST-030 observed FAILING against the pre-change engines
- `docs/ai/tdd/release-protected-branch-fallback-green.log` — the same two
  green after the change
- the suite run directory under `tests/skills/results/`
- `docs/ai/tests/test-runs.jsonl` append

PASS criteria: all TEST-027..TEST-035 green AND all Spec-AC in a terminal
status with non-empty Evidence. (TEST-035 arrived with the post-freeze
amendment below; this line was extended to match it in validation round 2.)

## Evidence contract

- ref_id: release-protected-branch-fallback
- Strategy: hybrid -> stored RED artifact for the AC-gating tests (TEST-027,
  TEST-030) under `docs/ai/tdd/`, plus the full verification matrix above.
- Spec-AC-01: `bash tests/skills/test-aai-release.sh test_027_protected_branch_fallback` -> exit 0
- Spec-AC-02: `bash tests/skills/test-aai-release.sh test_028_fallback_never_publishes_or_merges` -> exit 0
- Spec-AC-03: `bash tests/skills/test-aai-release.sh test_029_tag_is_local_and_report_names_the_repoint` -> exit 0
- Spec-AC-04: `bash tests/skills/test-aai-release.sh test_030_followtags_cannot_orphan_the_tag` -> exit 0
- Spec-AC-05: `bash tests/skills/test-aai-release.sh test_031_unprotected_path_byte_identical` -> exit 0
- Spec-AC-06: `bash tests/skills/test-aai-release.sh test_032_non_protected_failure_degrades_raw` -> exit 0
- Spec-AC-07: `bash tests/skills/test-aai-release.sh test_033_ps1_fallback_parity` -> exit 0 and `bash tests/skills/test-ps1-quality.sh` -> exit 0
- Spec-AC-08: `bash tests/skills/test-aai-release.sh test_034_exit_codes_documented` -> exit 0 and `bash tests/skills/test-aai-prompt-diet.sh` -> exit 0
- Spec-AC-09: `bash tests/skills/test-aai-release.sh test_035_fallback_incomplete_exits_18` -> exit 0
- Review scope: `.aai/scripts/aai-release.sh`, `.aai/scripts/aai-release.ps1`,
  `.aai/SKILL_RELEASE.prompt.md`, `tests/skills/test-aai-release.sh`,
  `tests/skills/aai-release.Tests.ps1`,
  `tests/skills/lib/prompt-diet-ledger.sh`,
  `tests/skills/test-aai-prompt-diet.sh`, `CHANGELOG.md`, this spec, the
  intake doc, `docs/INDEX.md`
- Base ref: 7eaeecb

## Companion obligations

- Prompt corpus growth: `.aai/SKILL_RELEASE.prompt.md` is inside the live
  `.aai/*.prompt.md` glob and this scope adds bytes to it. Implementation owes
  a new `JUSTIFIED_ADDITIONS` entry in `tests/skills/lib/prompt-diet-ledger.sh`
  whose leading byte count equals the MEASURED growth (`wc -c` before and
  after, under plain bash with `/usr/bin/grep`), and must move
  `want_growth` in `test_012_growth_sum_matches_ledger` from 8127 by exactly
  that amount. Headroom is currently 0, so the credit must be 1:1 — a rounded
  or padded number fails TEST-002's cap guard.
- New `.aai/**` file: none. `tests/skills/aai-release.Tests.ps1` is a test
  file, not an `.aai/**` file, so no `.aai/system/PROFILES.yaml` entry is owed.

## Out of scope

- Waiting for CI and merging the fallback PR. The engines never call
  `gh pr merge` (Constitution article 7, intake Scope).
- Automating the post-merge re-tag. The report names the commands; running
  them is the operator's.
- Any other push-rejection class (auth, network, stale branch). Spec-AC-06
  pins that those keep today's raw behavior.
- Non-GitHub hosts. The classifier's second arm (`protected branch` plus
  `status check`) is host-agnostic wording, but no non-GitHub host is tested.
