---
id: spec-directed-merge-and-post-merge-cleanup
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: a66fc77acd33cb1b614bbbf7c3905b7d21cf31fa47f48d9bf434b60383fe85da
ceremony_level: 2
links:
  requirement: directed-merge-and-post-merge-cleanup
  rfc: null
  pr: []
  commits: []
---

# Spec — Directed merge and safe post-merge cleanup (`/aai-merge`)

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-DRAFT-directed-merge-and-post-merge-cleanup.md
- Related intake (overlap assessed, not closed): docs/issues/ISSUE-0091-merged-worktrees-linger-after-close.md
- Prior art: docs/specs/SPEC-0209-spec-worktree-lacks-vendored-aai-layer-downstream.md (PR #433, the originating incident), .aai/SKILL_PR.prompt.md step 6, .aai/SKILL_WORKTREE.prompt.md "Command: Cleanup Worktree", .aai/scripts/ledger-merge.mjs, .aai/scripts/lib/session-lock.mjs, .aai/scripts/lane-gate.mjs, docs/ai/merge-policy.yaml
- Technology contract: docs/TECHNOLOGY.md

## Registry items closed by this scope

Registry items closed by this scope: fu-seeded-copies-lesson-no-guard

Registry scan: `node .aai/scripts/follow-ups.mjs list` on 2026-10-10, filtered
for seeded, worktree, merge, cleanup, focus, draft.

- `fu-seeded-copies-lesson-no-guard` (P3) — CLOSED by Spec-AC-04: the
  pre-pull stale-untracked-copy cleanup becomes a deterministic, tested
  step (identity + merged-content proof, recoverable archival) instead of
  an operator habit.
- `fu-clearfocus-announces-unwritten-phase` (P3) — NOT closed. Adjacent:
  this scope calls `state.mjs clear-focus` only when the origin focus equals
  the merged ref, and never edits `state.mjs` (L3 surface). The defect in
  clear-focus's own announcement stays open.
- `fu-sweep-denial-did-not-stop-merge` (P2) — NOT closed, partially
  mitigated: `/aai-merge` runs the merge command only after the engine's
  preflight (which includes `lane-gate.mjs --sweep-check`) exits with the
  ready code. A manual operator merge outside `/aai-merge` is unchanged,
  and branch protection is not modified.
- `fu-merge-policy-ride-pr-binding` (P2) — NOT closed: lane merge is not
  touched; `/aai-merge` is the directed path only.
- ISSUE-0091 `merged-worktrees-linger-after-close` — overlap, NOT closed.
  This scope delivers the earned "finished" predicate (clean tree, PR
  MERGED, local tip equals the PR's `headRefOid`, squash-aware) and applies
  it to the ONE worktree of the named PR on explicit invocation. ISSUE-0091
  asks for a repository-wide reporter (all worktrees, scratch-worktree
  classification, `aai-doctor` home, no removal). Its later ride can reuse
  this scope's predicate (`merge-cleanup.mjs plan` output) rather than
  re-derive it.
- Main-checkout drafts `ISSUE-DRAFT-done-work-item-stays-in-current-focus`
  and its spec (another session's work, read only) — NOT overlapping: they
  fix `metrics-flush.mjs` / rule 4b for a closed ref with no
  `metrics.work_items` row. This scope never flushes metrics and never
  clears a focus that is not the merged ref.

## Implementation strategy

- Strategy: tdd
- Rationale: Planning's decision (the intake leaves the mode open and
  recommends full TDD). The scope performs destructive Git and filesystem
  operations (fast-forward of the base branch, worktree removal, branch
  deletion, file relocation) and touches append-only ledgers and the merge
  authorization boundary. Every fragile decision needs an observed RED on a
  real disposable repository before its GREEN counts. STATE carries a stale
  intake-sourced strategy for `slowest-suite-hot-spots`; its ref_id differs,
  so it is not this item's choice and is replaced.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: multi-surface PR-bound change (new engine, new prompt,
  four wrappers, three edited core prompts, CI path filter) whose fixtures
  run destructive Git commands; isolation keeps an escaped fixture away from
  the shared main checkout. Not `required`: no protected surface
  (`protected_paths_l3`) is touched. The ride already runs in the worktree
  `/Users/ales/Projects/aai-change-directed-merge-and-post-merge-cleanup`
  on branch `change/directed-merge-and-post-merge-cleanup`.
- User decision: undecided (Implementation Preparation records it; autopilot
  default for `recommended` is `worktree`)
- Base ref: main (origin/main 2836dcc5)
- Worktree branch/path: change/directed-merge-and-post-merge-cleanup at
  /Users/ales/Projects/aai-change-directed-merge-and-post-merge-cleanup
- Inline review scope: .aai/scripts/merge-cleanup.mjs,
  .aai/SKILL_MERGE.prompt.md, .claude/skills/aai-merge/SKILL.md,
  .agents/skills/aai-merge/SKILL.md, .codex/skills/aai-merge/SKILL.md,
  .gemini/skills/aai-merge/SKILL.md, .codex/skills/README.md,
  .gemini/skills/README.md, .aai/SKILL_PR.prompt.md,
  .aai/SKILL_SHIP.prompt.md, .aai/SKILL_WORKTREE.prompt.md,
  .aai/system/PROFILES.yaml, .github/workflows/ps1-quality.yml,
  tests/skills/test-aai-merge-cleanup.sh,
  tests/skills/aai-merge-cleanup.Tests.ps1, tests/skills/suite-map.yaml,
  tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh,
  docs/USER_GUIDE.md, CHANGELOG.md, docs/skill-catalog-data.json (only if its
  generator pins the skill list),
  docs/issues/CHANGE-DRAFT-directed-merge-and-post-merge-cleanup.md,
  docs/specs/SPEC-DRAFT-spec-directed-merge-and-post-merge-cleanup.md
- Code review required: true (code, workflow and test change).

## Phasing

One ride. Size: 10 Spec-ACs, 17 TEST rows, one new engine of moderate size,
expected 3 to 4 TDD dispatches of about 3 ACs each. A phased split was
considered and is NOT the plan, because every AC shares one engine and one
fixture builder; splitting would duplicate the fixture work.

Cut-line, only if the ride's budget runs out before Validation: Phase A
(shippable alone) = Spec-AC-01 (cleanup-only mode), 03, 04, 05, 06, 07, 08,
09, 10; Phase B = Spec-AC-02 (open-PR preflight and directed merge) plus the
merge mode of Spec-AC-01. Phase A without B is safe: `/aai-merge` on an open
PR would then refuse with `not_merged` and leave the merge to the operator,
which is today's behavior. Any cut is a post-freeze amendment disclosed at
the merge checkpoint, never silent.

## Design decisions

- D1 Packaging. New core prompt `.aai/SKILL_MERGE.prompt.md` (entrypoint
  `/aai-merge <PR>`), wrappers generated into all four skill trees by
  `node .aai/scripts/sync-harness-skills.mjs --write` from the hand-authored
  `.claude/skills/aai-merge/SKILL.md`, and ONE deterministic Node engine
  `.aai/scripts/merge-cleanup.mjs` (stdlib only, `spawnSync` for `git`,
  `gh`, and the existing AAI scripts). Node is the cross-platform carrier;
  no `.sh`/`.ps1` twin is written. The prompt carries a bash block and a
  PowerShell block, each between markers `# AAI_MERGE_BEGIN` /
  `# AAI_MERGE_END` (bash) and `# AAI_MERGE_PS_BEGIN` / `# AAI_MERGE_PS_END`,
  so tests execute the real prompt text (SPEC-0209 TEST-005 precedent).
- D2 Engine grammar (implementation may refine names; the exit contract is
  fixed):
  `merge-cleanup.mjs preflight --pr <n> --expect-head <sha> --directed-by human --direction "<verbatim owner words>" [--origin <abs>] [--json]`,
  `merge-cleanup.mjs plan --pr <n> [--origin <abs>] [--json]`,
  `merge-cleanup.mjs apply --pr <n> --pid <harness pid> [--origin <abs>] [--archive-divergent <path>]... [--json]`.
  Exit codes: 0 complete (all eligible steps done or named no-ops; owner
  actions may remain in `remaining`), 2 usage, 3 refused before any
  mutation (named reason line `REFUSE <reason> <detail>`), 4 stopped
  mid-way (partial report; a re-run resumes), 10 preflight ready (open PR,
  every gate passed, the one merge command printed).
- D3 Merge authority. The engine NEVER runs `gh pr merge`, in any mode.
  The prompt runs exactly the command `preflight` prints,
  `AAI_OPERATOR_MERGE=1 gh pr merge <n> --squash --match-head-commit <sha>`,
  only when (a) the human invoked `/aai-merge <n>` naming that PR in this
  session, and (b) `preflight` exited 10 for that PR and head. Never
  `--admin`, never `--auto`. This is the operator-directed merge SKILL_PR
  step 6 already describes ("an agent acting on the operator's explicit,
  recorded direction"); no standing authorization is created, and `/aai-ship`
  and the loop never invoke `/aai-merge`. The verbatim direction and head
  sha are written into the run report (D9). A lane merge stays SKILL_PR
  step 6's own path. See Constitution deviations.
- D4 Preflight gates (open PR). Read with ONE fixed call
  `gh pr view <n> --json number,state,isDraft,headRefOid,headRefName,baseRefName,mergeStateStatus,statusCheckRollup,mergeCommit,url`,
  then `node .aai/scripts/lane-gate.mjs --sweep-check --pr <n>`. Refusal
  reasons: `no_direction` (missing or empty `--direction`, or
  `--directed-by` other than `human`), `not_open`, `draft`, `head_changed`
  (`headRefOid` differs from `--expect-head`), `checks_failing` (any
  rollup entry not SUCCESS, NEUTRAL or SKIPPED, or any still pending),
  `not_mergeable` (`mergeStateStatus` other than CLEAN), `sweep_missing`
  (lane-gate non-zero; its message is relayed). A MERGED PR answers
  `already_merged` with exit 0 and points to `apply`.
- D5 Read-back gate. `apply` and every mutation behind it require the same
  `gh pr view` read to report `state` MERGED with a non-empty
  `mergeCommit.oid`, and after `git fetch origin <baseRefName>` the merge
  commit must be an ancestor of `origin/<baseRefName>`. Otherwise exit 3
  with `not_merged` or `merge_commit_not_on_base` and nothing written.
- D6 Superseded drafts (closes `fu-seeded-copies-lesson-no-guard`).
  Candidates are untracked `*-DRAFT-*.md` files under the origin's docs
  type directories (docs/issues, docs/specs, docs/rfc, docs/requirements,
  docs/research and any other directory docs-model already enumerates).
  Delivered ids are the frontmatter ids of docs the PR added or changed
  (diff between the merge commit's first parent and the merge commit).
  A candidate whose id is not delivered is retained as `unrelated_id`.
  A candidate whose id is delivered is SUPERSEDED only when its exact bytes
  (blob id via `git hash-object`) equal a blob that existed under any path
  in the PR's commit history (`<merge-base>..headRefOid`, objects taken from
  the local branch, else from `git fetch origin pull/<n>/head`); otherwise
  it is retained as `divergent_content` and listed as an owner decision.
  When history cannot be read it is retained as `unverifiable_history`.
  `--archive-divergent <path>` (repeatable, named path) is the explicit
  decision that archives a divergent copy. Filenames alone never decide.
- D7 Archive. One per-PR root,
  `docs/ai/archive/merge-cleanup/pr-<n>/` (gitignored by `docs/ai/archive/**`
  and outside the docs corpus), holding `manifest.jsonl` (one line per
  archived file: original path, archive path, sha256, reason, step,
  timestamp), `journal.jsonl` (one line per completed step), `files/`
  (original relative paths preserved) and `worktree/` (the removed
  worktree's STATE and ignored evidence). An archive write never overwrites
  a differing file; a second copy gets a numeric suffix. Archival is a
  copy, an fsync-free byte compare, then removal of the original.
- D8 Base sync. Preconditions, all checked before any write: origin's
  current branch equals `baseRefName` (`origin_not_on_base`), origin HEAD
  is an ancestor of `origin/<base>` (`base_diverged`), no dirty tracked
  path is changed between HEAD and target except the classes below
  (`overlap:<path>`), no untracked path collides with an incoming added path
  unless its bytes equal the incoming blob (`untracked_collision:<path>`).
  Classes: (a) append-only ledgers that are tracked and dirty
  (docs/ai/EVENTS.jsonl, docs/ai/decisions.jsonl, docs/ai/METRICS.jsonl,
  docs/ai/tests/test-runs.jsonl): the HEAD blob must be a byte-exact prefix
  of the working file (`ledger_rewritten` otherwise); the working bytes are
  archived, the file is rewritten to the HEAD blob, and after the
  fast-forward `ledger-merge.mjs --base <old HEAD blob> --ours <new HEAD
  file> --theirs <archived local> --out <file>` re-appends the local tail
  after the incoming bytes, so the incoming blob stays a byte-exact prefix
  and every local line survives exactly once; (b) docs/INDEX.md: archived,
  rewritten to the HEAD blob, regenerated after the sync by
  `node .aai/scripts/generate-docs-index.mjs`. The sync is
  `git merge --ff-only <origin/base sha>` with the caller's environment
  (the prompt sets `AAI_GIT_WRITE=1` for the ref-guard on the default
  branch). Afterwards HEAD, `refs/heads/<base>` and the target sha must be
  equal (the guarded-pull scar). On a failed fast-forward the archived
  ledger and index bytes are written back before exit 4. Never `git stash`,
  `git reset`, `git restore`, `git checkout --`, `git clean` or blanket
  staging.
- D9 Runtime state, index and report. Origin STATE: when
  `current_focus.ref_id` equals the merged ref (the PR's delivered work-item
  id), run `node .aai/scripts/state.mjs clear-focus --ref <ref>` in the
  origin; any other focus, including `none`, is the named no-op
  `focus_not_this_ref` and STATE bytes stay unchanged (the field-evidence
  usage-error case). Then `node .aai/scripts/docs-audit.mjs --strict` runs
  in the origin and its verdict line goes into the report; a non-CLEAN
  verdict is listed under `remaining`, never auto-remediated. The report is
  printed (and with `--json` emitted as one JSON object) and saved to
  `docs/ai/reports/merge-cleanup-pr<n>-<UTC>.md`: pr, merge commit, base,
  final HEAD, direction (when a merge ran), archived, retained (with
  reasons), no-ops, remaining (owner actions such as remote branch deletion
  and divergent-draft decisions).
- D10 Worktree and branch. The ride worktree is the registered worktree
  whose branch equals `headRefName` (none: named no-op `no_worktree`).
  Eligible only when: `git status --porcelain` in it is empty
  (`worktree_dirty`), its tip equals `headRefOid` (`tip_mismatch`; squash
  merges are recognized by this equality, never by ancestry),
  `session-lock.mjs status` shows no lock held by a live pid other than
  `--pid` (`session_locked`), and the engine's cwd is not inside it
  (`cwd_inside_target`). Before removal: the worktree's
  docs/ai/STATE.yaml and every git-ignored file under its
  docs/ai/{reports,tdd,validation,reviews,evidence} are copied to the
  archive; ignored evidence absent from the origin is also copied into the
  same origin path (a differing origin file is never overwritten; the
  existing close-work-item rescue in lib/evidence-paths.mjs is reused when
  its contract fits). A lock held by `--pid` is released. Removal is
  `git worktree remove <path>` without `--force` (Planning probe
  2026-10-10, git 2.50: a worktree holding only ignored files is removed
  without `--force`). The local branch is deleted by compare-and-swap
  `git update-ref -d refs/heads/<branch> <headRefOid>` (Planning probe: it
  refuses when the ref moved), never `git branch -D`. Remote branches are
  never deleted; a surviving remote branch is listed under `remaining`.
  Other worktrees, branches and locks are not read for mutation.
- D11 Steps, journal and resume. Fixed order: resolve, plan,
  archive-runtime, archive-drafts, sync-base, state, index-audit,
  remove-worktree, delete-branch, report. Each step re-derives its
  precondition from live state, so a completed step is detected as the
  named no-op `noop:<step>:<reason>` even without the journal; the journal
  only adds the original completion time to the report. A test-only
  environment seam `AAI_MERGE_CLEANUP_STOP_AFTER=<step>` exits 4 right after
  that step's journal line, to prove resume.
- D12 Gh access. The engine calls only the read in D4 plus the fetches in
  D5/D6. Tests use a deny-by-default gh stub that pins the exact argv
  skeleton and logs every call (LEARNED 2026-09-05 deny-default-mock), and a
  real bare `origin` repository that carries `refs/pull/<n>/head` and a
  squash commit on `main`.

## Acceptance Criteria Mapping

| Intake AC | Spec-AC | Verification | Observable and evidence |
|---|---|---|---|
| AC-001 entrypoint, cleanup-only, links | Spec-AC-01 | V1 TEST-001, TEST-002; V3 | wrappers in four trees, harness sync check exit 0, prompt block executed against a MERGED fixture completes cleanup; SKILL_PR, SKILL_SHIP and SKILL_WORKTREE point to `/aai-merge` |
| AC-002 merge refusals, read-back, no bypass | Spec-AC-02, Spec-AC-03 | V1 TEST-003, TEST-004, TEST-005 | named exit-3 refusals with unchanged fixture digest; ready path prints one bound command; gh log never shows `pr merge`, `--admin` or `--auto` from the engine; apply refuses before MERGED read-back |
| AC-003 PR #433 layout drafts | Spec-AC-04 | V1 TEST-006, TEST-007 | superseded drafts archived with sha-matching manifest; numbered docs present; unrelated and divergent copies retained with reasons; docs-audit strict CLEAN after archival |
| AC-004 base sync preserves work and ledgers | Spec-AC-05 | V1 TEST-008, TEST-009 | dirty and untracked files byte-equal; incoming ledger blob is byte prefix; local lines once; divergent and overlapping cases stop with HEAD unchanged and no stash |
| AC-005 worktree and branch cleanup | Spec-AC-06 | V1 TEST-010, TEST-011 | archive-before-remove sha proof; squash branch CAS-deleted; dirty, locked, moved-tip and cwd cases refused; other work intact; remote branch still present |
| AC-006 focus, index, report | Spec-AC-07 | V1 TEST-012 | focus cleared only for the merged ref; STATE bytes unchanged otherwise; index has no DRAFT row for the id; report fields present |
| AC-007 idempotent resume | Spec-AC-08 | V1 TEST-013, TEST-014 | second run all named no-ops with unchanged digest; interrupted run after every step converges to the control run's bytes; no duplicate ledger lines; no merge call |
| AC-008 real repos, downstream, Bash and Windows | Spec-AC-09, Spec-AC-10 | V1 TEST-015; V2 TEST-016; V3 TEST-017 | installed-layout fixture passes; Pester lane on Windows PowerShell 5.1 and pwsh 7 in PR CI; profile, suite-map, diet ledger and path filter green |

## Constitution deviations

- Article 7 (operator-only merge; lane merge the sole sanctioned
  exception). Deviation: `/aai-merge <n>` lets the agent run
  `gh pr merge` for the ONE PR a human names in that invocation, outside a
  merge-policy lane. Justification: this is the operator-directed merge
  that .aai/SKILL_PR.prompt.md step 6 already sanctions for "an agent acting
  on the operator's explicit, recorded direction" (hook marker
  `AAI_OPERATOR_MERGE`), recorded in practice by `directed_merge` entries in
  docs/ai/decisions.jsonl (2026-07-16; 2026-10-08 PR #434); the
  owner-authored intake asks for exactly this entrypoint. It adds no
  standing authorization: one invocation, one PR, one judged head
  (`--match-head-commit`), every existing gate (CI rollup, mergeability,
  sweep record, hook overlay) still applies, `--admin`/`--auto` are never
  used, and `/aai-ship` and the loop never invoke it. docs/CONSTITUTION.md
  is NOT edited (L3 surface); ratifying Article 7's wording to name the
  directed-merge carve remains the owner's decision, already open since the
  2026-07-16 review_disposition record. Surfaced at the merge checkpoint.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a human invokes `/aai-merge <n>` the system SHALL route through `.aai/SKILL_MERGE.prompt.md` (wrappers present in all four skill trees, harness sync check exit 0) and, for a MERGED PR, run cleanup only; SKILL_PR step 6, SKILL_SHIP step 6 and SKILL_WORKTREE cleanup SHALL point to `/aai-merge` as the completion procedure. | planned | — | — | D1; executed prompt block, not token matching alone |
| Spec-AC-02 | WHEN `preflight` runs for an open PR the system SHALL refuse with exit 3 and one named reason for each of no_direction, not_open, draft, head_changed, checks_failing, not_mergeable and sweep_missing, write nothing, and never call `gh pr merge`; WHEN every gate passes it SHALL exit 10 and print exactly one command binding `--match-head-commit` to the judged head with neither `--admin` nor `--auto`. | planned | — | — | D3, D4 |
| Spec-AC-03 | WHEN `apply` runs for a PR whose read-back is not MERGED with a merge commit reachable from origin's base branch the system SHALL exit 3 before any mutation, leaving files, worktrees, branches and STATE unchanged. | done | docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/green-TEST-005.log, docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-005.txt | tdd | D5; B1 TEST-005 green, mutation RED |
| Spec-AC-04 | WHEN the origin holds untracked DRAFT copies of docs the PR delivered the system SHALL archive only copies whose exact bytes appear in the PR's commit history, record each in the manifest with its sha256, keep the merged numbered documents, and retain unrelated or divergent copies with the reasons unrelated_id or divergent_content until `--archive-divergent` names them. | done | docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/green-TEST-006.log, docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/green-TEST-007.log, docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-006.txt, docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-007.txt | tdd | D6, D7; closes fu-seeded-copies-lesson-no-guard; B1 TEST-006/007 green, mutation RED |
| Spec-AC-05 | WHEN the origin is synchronized the system SHALL fast-forward only, keep unrelated dirty and untracked files byte-identical, keep the incoming ledger blob a byte-exact prefix with every local ledger line present exactly once, and SHALL stop without writing on origin_not_on_base, base_diverged, overlap, untracked_collision or ledger_rewritten. | planned | — | — | D8; no stash, reset, restore or clean |
| Spec-AC-06 | WHEN the ride worktree is eligible the system SHALL archive its STATE and ignored evidence before `git worktree remove` without force, delete its local branch only by compare-and-swap against the PR head (squash merge included), and SHALL refuse worktree_dirty, tip_mismatch, session_locked and cwd_inside_target while leaving other worktrees, branches and the remote branch intact. | planned | — | — | D10 |
| Spec-AC-07 | WHEN cleanup completes the system SHALL clear the origin focus through `state.mjs clear-focus` only if it names the merged ref (else the named no-op focus_not_this_ref with STATE bytes unchanged), regenerate docs/INDEX.md without a DRAFT row for the delivered id, and report base, final HEAD, archived, retained, no-ops and remaining steps. | planned | — | — | D9 |
| Spec-AC-08 | WHEN `apply` is repeated or resumed after an interruption at any step the system SHALL lose no file, duplicate no ledger line, never call a merge, report completed steps as named no-ops, and converge to the same final bytes as an uninterrupted run. | planned | — | — | D11 |
| Spec-AC-09 | WHEN run in a downstream installation whose `.aai/` and skill trees are gitignored, and on Windows PowerShell 5.1 and pwsh 7, the system SHALL complete the positive cleanup and the dirty-worktree refusal with the same results as on Bash. | planned | — | — | Native Windows verdict comes from PR CI only |
| Spec-AC-10 | The scope SHALL classify the new prompt and engine as core in PROFILES.yaml, add a suite-map row, credit the measured prompt-corpus growth in the diet ledger with the matching TEST-012 pin, and list the engine and prompt in the ps1-quality path filter, with the owning suites green. | planned | — | — | Companion obligations |

## Implementation plan

- NEW `.aai/scripts/merge-cleanup.mjs` (D2 to D12). Reuse, do not
  re-implement: `ledger-merge.mjs` (spawned), `lib/session-lock.mjs`
  (`status`/`release` spawned), `lane-gate.mjs --sweep-check`,
  `state.mjs clear-focus`, `generate-docs-index.mjs`, `docs-audit.mjs`,
  `lib/docs-model.mjs` for frontmatter ids and doc directories,
  `lib/evidence-paths.mjs` where its rescue contract fits,
  `lib/cli-pipe-guard.mjs` for exit/pipe safety.
- NEW `.aai/SKILL_MERGE.prompt.md` (thin: inputs, the two modes, the
  marked bash and PowerShell blocks, the D3 authority rule, report and
  stop rules). Keep it short; the engine owns the rules.
- NEW `.claude/skills/aai-merge/SKILL.md`, then
  `node .aai/scripts/sync-harness-skills.mjs --write` generates the three
  mirrors and README index lines.
- EDIT `.aai/SKILL_PR.prompt.md` step 6 (replace the last bullet's
  "post-merge work" sentence with a pointer to `/aai-merge <n>`),
  `.aai/SKILL_SHIP.prompt.md` step 6 (one line: merge and clean up with
  `/aai-merge <n>`; /aai-ship never invokes it), `.aai/SKILL_WORKTREE.prompt.md`
  Cleanup Worktree (one line: for a merged ride use `/aai-merge <n>`; the
  existing manual steps remain for abandoned worktrees).
- EDIT `.aai/system/PROFILES.yaml` (core), `tests/skills/suite-map.yaml`
  (row `aai-merge-cleanup`), `tests/skills/lib/prompt-diet-ledger.sh` and the
  TEST-012 pin in `tests/skills/test-aai-prompt-diet.sh` (credit = measured
  bytes, never copied from this spec), `.github/workflows/ps1-quality.yml`
  push and pull_request path filters (engine and prompt; the
  test-aai-win-fallback test_034..036 derivation decides), docs/USER_GUIDE.md
  skill table and CHANGELOG.md `## [unreleased] — <title>` entry.
- NEW `tests/skills/test-aai-merge-cleanup.sh` and
  `tests/skills/aai-merge-cleanup.Tests.ps1`.
- Edge cases: PR number of another repository (refuse on `url` repo
  mismatch with origin remote), base branch other than main, origin on the
  base branch but detached, worktree directory already deleted while still
  registered (report `worktree_missing`, never prune), branch already
  deleted (no-op), merge commit present but origin not yet fetched, spaces
  in paths, CRLF in drafts (byte identity, no normalization).

### Seams (each crossed by a real producer and a real consumer in a test)

- S1 PR history produces the draft's blob; the engine's identity proof
  consumes it — TEST-006/007 build real branch commits and a real squash.
- S2 Engine archival consumes the docs corpus that docs-audit reads —
  TEST-006 runs the real `docs-audit.mjs --strict` after archival.
- S3 Engine rewrites a ledger that `ledger-merge.mjs` merges and CI's
  append-only check reads — TEST-008 asserts the byte prefix against the
  incoming blob with `cmp`, not through the engine's own report.
- S4 `state.mjs clear-focus` writes the STATE the dispatcher reads —
  TEST-012 runs the real state.mjs on a fixture STATE produced by
  `check-state.mjs --repair` plus `state.mjs set-focus`.
- S5 `session-lock.mjs acquire` (another live pid) produces the lock the
  engine consumes — TEST-011.
- S6 `lane-gate.mjs --sweep-check` reads a fixture `pr_sweep` record the
  preflight consumes — TEST-003/004 run the real lane-gate.
- S7 The prompt's marked blocks are the consumer of the engine's CLI —
  TEST-002 (bash) and TEST-016 (PowerShell) execute the extracted blocks.
- S8 `aai-sync.sh` produces the downstream layout and `worktree-seed.mjs`
  the seeded worktree the engine removes — TEST-015.
- Residual (no automated crossing): real GitHub behavior of
  `gh pr view` fields and `gh pr merge --match-head-commit` is stubbed; the
  stub pins the argv skeleton only. The hooks overlay (`claude-hook-gate.sh`)
  intercepting the prompt's merge command is not executed by these tests;
  its own suite covers it. Native Windows evidence exists only in PR CI.

## Test Plan

All fixtures live under one private absolute scratch root from
`mktemp -d` with a full `XXXXXX` template; every path is checked non-empty
and absolute before `cd` or `git -C` (HAZ-CD); every fixture repository
sets its own `user.name`/`user.email`, uses `git init -b main`, sets
`symbolic-ref HEAD` on the bare origin, and every setup exit is checked.
No test writes Git state in the shipping repository. The gh stub is
deny-by-default (exact argv skeleton, logged). Each row is runnable alone
with `--test TEST-0xx`. Mutation patches are generated during TDD against
the implementation and change the named behavior, never a test.

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | contract | tests/skills/test-aai-merge-cleanup.sh | four wrapper trees carry aai-merge; sync-harness-skills --check exit 0; SKILL_PR step 6, SKILL_SHIP step 6, SKILL_WORKTREE cleanup reference /aai-merge; engine --help lists preflight, plan, apply | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-001.patch | pending |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-merge-cleanup.sh | extract the prompt's AAI_MERGE bash block, run it in a MERGED fixture from the origin; cleanup completes (exit 0, worktree gone, drafts archived) | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-002.patch | pending |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-merge-cleanup.sh | one arm per refusal reason (no_direction, not_open, draft, head_changed, checks_failing, not_mergeable, sweep_missing via real lane-gate and fixture ledger); exit 3, reason line, fixture digest unchanged, gh log has no pr merge | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-003.patch | pending |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-merge-cleanup.sh | all gates pass: exit 10, exactly one printed command with --squash and --match-head-commit equal to the head, no --admin or --auto; positive control that the pr view read and sweep check ran; digest unchanged | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-004.patch | pending |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-merge-cleanup.sh | apply on OPEN, CLOSED-unmerged and MERGED-but-merge-commit-not-on-base fixtures: exit 3 with not_merged or merge_commit_not_on_base; files, worktree list, branch list and STATE bytes unchanged | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-005.patch | green |
| TEST-006 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | PR 433 layout: origin untracked ISSUE-DRAFT and SPEC-DRAFT copies equal to blobs on the PR branch; squash merge renamed them to numbered docs; apply archives both with sha256 manifest lines, numbered docs exist in origin, real docs-audit --strict is CLEAN | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-006.patch | green |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | unrelated-id draft retained (unrelated_id); same-id edited draft retained (divergent_content, listed in remaining); rerun with --archive-divergent archives it; archived bytes cmp-equal to the original | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-007.patch | green |
| TEST-008 | Spec-AC-05 | integration | tests/skills/test-aai-merge-cleanup.sh | origin with dirty unrelated tracked file, untracked note, local EVENTS.jsonl tail and dirty INDEX: after apply the first two are byte-equal, cmp proves the incoming EVENTS blob is a prefix, each local line occurs once, INDEX regenerated, HEAD equals refs/heads/main equals origin/main | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-008.patch | pending |
| TEST-009 | Spec-AC-05 | integration | tests/skills/test-aai-merge-cleanup.sh | arms origin_not_on_base, base_diverged, overlap, untracked_collision, ledger_rewritten: non-zero with the reason, HEAD, refs and file bytes unchanged, git stash list unchanged, no reflog reset entry | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-009.patch | pending |
| TEST-010 | Spec-AC-06 | integration | tests/skills/test-aai-merge-cleanup.sh | eligible squash-merged worktree: archived STATE and ignored evidence sha-equal to pre-removal bytes; evidence copied into origin only where absent, differing origin file unchanged; worktree removed; branch deleted though not an ancestor; second worktree, its branch, an unrelated branch and the bare origin's remote branch remain | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-010.patch | pending |
| TEST-011 | Spec-AC-06 | integration | tests/skills/test-aai-merge-cleanup.sh | arms worktree_dirty, tip_mismatch (commit after merge), session_locked (lock acquired by a live helper pid other than --pid, killed in trap), cwd_inside_target: refusal named, worktree and branch still present | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-011.patch | pending |
| TEST-012 | Spec-AC-07 | integration | tests/skills/test-aai-merge-cleanup.sh | origin focus equals ref: real state.mjs clears it (ref_id null, item done); focus none and focus other ref: focus_not_this_ref, STATE bytes cmp-equal; INDEX has numbered rows and no DRAFT row for the id; JSON report carries base, head, archived, retained, noops, remaining | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-012.patch | pending |
| TEST-013 | Spec-AC-08 | integration | tests/skills/test-aai-merge-cleanup.sh | second apply after success: exit 0, every step reported as a named no-op, tree digest and ledger line counts unchanged, gh log shows no merge | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-013.patch | pending |
| TEST-014 | Spec-AC-08 | integration | tests/skills/test-aai-merge-cleanup.sh | for every step id: AAI_MERGE_CLEANUP_STOP_AFTER then rerun; final file set and bytes equal the uninterrupted control fixture; no duplicate ledger line; every pre-run dirty or untracked file present in origin or archive with equal sha | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-014.patch | pending |
| TEST-015 | Spec-AC-09 | integration | tests/skills/test-aai-merge-cleanup.sh | downstream layout: aai-sync.sh core install with .aai and skill trees ignored, worktree seeded by worktree-seed.mjs, apply from the origin's installed engine succeeds; git ls-files shows nothing under .aai; spaced scratch path | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-015.patch | pending |
| TEST-016 | Spec-AC-09 | integration | tests/skills/aai-merge-cleanup.Tests.ps1 | Pester on a spaced path: extract the prompt's AAI_MERGE_PS block, positive cleanup (drafts archived, worktree removed, branch CAS-deleted) and the worktree_dirty refusal; mutation measured by TEST-015 per the SPEC-0209 amendment precedent | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-016.patch | pending |
| TEST-017 | Spec-AC-10 | contract | tests/skills/test-aai-prompt-diet.sh | PROFILES core entries for prompt and engine, suite-map row, ledger credit equals measured growth with TEST-012 pin, ps1-quality filter lists engine and prompt; prompt-diet, layer-profiles, suite-select and win-fallback suites exit 0 | patch:docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-017.patch | pending |

RED first: for the new engine, land a parseable skeleton (`--help` and the
exit contract) and observe each semantic assertion fail; a missing module
or syntax error is not RED. TEST-001 and TEST-017 observe the absent
wiring and absent credit before adding them. TEST-009 and TEST-011 refusal
arms are each shown failing under their declared removal mutation. RED logs
go to `docs/ai/tdd/directed-merge-and-post-merge-cleanup-red.log`, labelled
with TEST id and platform.

## Verification

- V1: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh`
  exits 0 with every declared POSIX case executed and passed. Single case:
  append `--test TEST-0xx`.
- V2: `powershell -NoProfile -Command "Invoke-Pester -Path tests/skills/aai-merge-cleanup.Tests.ps1 -EnableExit"`
  and the same with `pwsh`, on native Windows in the ps1-quality and
  skill-suite PR CI jobs, zero failed or skipped declared tests. A local
  macOS pwsh run is pre-PR evidence only, never the Windows verdict;
  Spec-AC-09 stays non-terminal until the CI runs exist.
- V3: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`,
  `... test-aai-layer-profiles.sh`, `... test-aai-suite-select.sh`,
  `... test-aai-win-fallback.sh`, and
  `node .aai/scripts/sync-harness-skills.mjs --check` all exit 0.
- V4 regression: the suites `node .aai/scripts/select-suites.mjs` picks for
  the changed paths (expect at least test-aai-ledger-merge.sh,
  test-aai-worktree-seed.sh, test-aai-prompt-hash.sh and the SKILL_PR /
  SKILL_SHIP pins); `test-aai-worktree.sh` has a known local pre-existing
  failure (docs/knowledge/LEARNED.md 2026-07-15) — compare against a
  disposable worktree of the base, never by stashing.
- Lint: `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-directed-merge-and-post-merge-cleanup.md`.
- Mutation replay: `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-DRAFT-spec-directed-merge-and-post-merge-cleanup.md`.

Logs: `docs/ai/tdd/directed-merge-and-post-merge-cleanup-{red,green,validation}.log`;
mutation records at
`docs/ai/tdd/spec-directed-merge-and-post-merge-cleanup/mutation-TEST-0xx.{patch,txt}`.
PASS criteria: every TEST row green with evidence, every Spec-AC terminal,
Spec-AC-09 citing the native Windows CI run ids.

## Evidence contract

Every artifact records ref_id `directed-merge-and-post-merge-cleanup`, the
Spec-AC and TEST ids, the exact command and platform, exit code, log path
and diff or commit identity. TDD stores RED per AC-gating test, GREEN output
and behavior-relevant mutation records. Validation independently repeats
V1 to V4 and reports missing native Windows coverage as unverified, not as
a passing local substitute. Review covers the inline review scope above on
the full diff. The authoritative Validation report carries an admissible
aai-outcome-v1 block and its path is the `set-validation --evidence` value.

### Evidence by strategy

Strategy `tdd`: stored RED artifact per AC-gating test under docs/ai/tdd/
plus the full verification matrix V1 to V4.

## Assumptions (autopilot, recorded instead of questions)

- A1 The merged work item's ref is the frontmatter `id` of the delivered
  intake doc in the PR (the `links.pr` stamp written by close-work-item);
  when the PR delivers several intake ids, focus is cleared only for the
  one the origin STATE names, else `focus_not_this_ref`.
- A2 "Origin checkout" defaults to the repository's main worktree (first
  `git worktree list --porcelain` entry); `--origin` overrides it.
- A3 Remote branch deletion is out of scope (intake): neither the engine
  nor `/aai-merge` deletes a remote branch, and the merge command never
  carries `--delete-branch`; a surviving remote branch is reported under
  `remaining` as an owner action.
- A4 Archived drafts are never auto-purged; purge is an owner action.
- A5 `docs/ai/evidence` is treated like the other evidence directories
  only for files git reports as ignored.
