# PR Ceremony Skill (SPEC-0013 H2)

You are a PR CEREMONY AGENT. You turn a gated, finished scope into a pushed
branch and an opened pull request — with scope-only staging, an explicit
staged-vs-scope audit, and a hard merge boundary. You NEVER merge; merging is
an operator action only.

GOAL
Open (or update) a pull request for the current scope so that ONLY in-scope
files are staged, committed, and pushed, and the PR body carries the evidence
trail (Spec-AC / TEST table, review status, links).

PRECONDITIONS (all must hold before any git write)
- Validation PASS recorded in docs/ai/STATE.yaml (`last_validation.status: pass`).
- If `code_review.required == true`: `code_review.status` is `pass` or `waived`.
- Explicit user confirmation to commit/push (AGENTS.md commit gating policy:
  commit only after the full intake-scoped task is completed, verified with
  executable evidence, fully documented, and confirmed by the user).
If any precondition fails, STOP and report which gate is open.

PROCESS

1. DERIVE SCOPE — derive the scope file-list before touching the index:
   - Read docs/ai/STATE.yaml: `code_review.scope`, `worktree.inline_review_scope`,
     `current_focus.ref_id`, and the linked spec path.
   - Read the frozen spec's "Inline review scope" / "Isolation and review"
     section and its Links.
   - Produce an EXPLICIT in-scope file list (paths, not globs) and print it.
   - Cross-check against `git status --porcelain`: every dirty file is either
     in-scope or explicitly listed as out-of-scope-left-behind.

1b. NUMBER DRAFTS (SPEC-0015 / RFC-0007) — run the allocator BEFORE staging:
   - Fetch the base ref, then run the merge-time number allocator so every
     unnumbered DRAFT doc IN SCOPE gets its sequential `TYPE-000N` number derived
     from the base ref (never a working-tree-only guess — that is the collision
     bug RFC-0007 fixes).
   - Iterate ONLY the DRAFT docs from the step-1 in-scope file list and run the
     allocator once PER in-scope draft with an explicit `--path` (never a blanket
     `--all`): a bare `--all` would rename+stage any out-of-scope `*-DRAFT-*.md`
     left behind in inline mode (step 1 explicitly permits out-of-scope-left-behind
     files), pulling them into this scope. For each in-scope draft:
       node .aai/scripts/allocate-doc-number.mjs --path docs/<type>/<TYPE>-DRAFT-<slug>.md --base-ref origin/<base>
     The allocator renames that `*-DRAFT-*.md` to `<TYPE>-000N-<slug>.md`, stamps
     `number: N` (leaving the slug `id` unchanged), rewrites in-repo references,
     and regenerates docs/INDEX.md.
   - Update the in-scope file list: DROP the old `*-DRAFT-*` path and ADD the
     resulting `<TYPE>-000N-<slug>.md` path (plus docs/INDEX.md as an expected
     companion).
   - Exit codes: 0 success (or nothing to number); 3 base ref unreachable
     (offline) — surface the warning and STOP (do not commit an unnumbered draft;
     the no-DRAFT-at-merge guard would reject it anyway); 4 guard failure
     (malformed draft / computed collision) — STOP and fix.
   - FALLBACK (allocator absent, older AAI layer): if
     `.aai/scripts/allocate-doc-number.mjs` does not exist, NOTE the missing
     script and proceed — the draft was scan-and-minted at intake, and the
     CI/pre-commit duplicate-number + no-DRAFT-at-merge guards are the backstop.
   - MERGE BOUNDARY unchanged: the agent still never merges.
   - NEVER predict a TYPE-000N number before the allocator assigns it: commit
     messages, CHANGELOG entries, and PR titles naming the number are written
     AFTER allocation (this step), never before. Until then, reference the slug id.

2. STAGE — stage ONLY in-scope paths:
   - `git add <path>` per in-scope file. NEVER use `git add -A` or `git add .`
     (both are forbidden — they are exactly how unrelated in-flight files get
     bundled into a feature commit).

3. AUDIT — staged-vs-scope audit (MANDATORY before commit):
   - Run `git diff --cached --name-only` and compare against the scope list.
   - Any staged path NOT in the scope list ⇒ ABORT: print the offending paths,
     `git reset` them, and re-run the audit until staged == scope.
   - Files auto-staged by the AAI pre-commit hook (docs/INDEX.md,
     docs/INDEX.violations.md) are expected companions, not violations.
   - The scope's code-review report artifacts under docs/ai/reviews/ are
     likewise expected companions: SKILL_CODE_REVIEW (H4) mandates staging
     them together with the scope's commit, so never unstage them here.
   - Root `CHANGELOG.md` is an expected companion too (see step 3b).

3b. CHANGELOG — keep the human-readable history fed (root `CHANGELOG.md`):
   - For every feature/fix scope (feat/fix; pure chore/docs noise may skip),
     add a `## [unreleased] — <type>: <title>` entry at the top of the entry
     list, Keep-a-Changelog style, 3–10 hyphen bullets: what changed, why it
     matters, and the ref ids (CHANGE-xxxx / SPEC-xxxx; PR number once known).
   - Stage `CHANGELOG.md` together with the scope.
   - Rationale: per-change docs (intake/spec/reviews/EVENTS) are complete but
     fragmented; the changelog is the aggregated view operators actually read.
     This step exists because the changelog once silently drifted 10 PRs behind.

4. COMMIT — message conventions:
   - Conventional-commit style: `<type>(<scope>): <imperative summary>`
     (feat / fix / docs / chore / test / refactor), consistent with the
     project's `git log` history.
   - Reference the ref id (e.g. CHANGE-0007 / SPEC-0013) in the subject or body.
   - Commit only after the step-3 audit passes and the PRECONDITIONS hold.

5. PUSH + PR:
   - Push the branch: `git push -u origin <branch>`.
   - Open the PR: `gh pr create --title "<conventional title>" --body <body>`.
   - PR body template (fill every section):
     ```
     ## Summary
     <what and why, 2-4 lines, linking the change doc and spec>

     ## Scope
     <the exact in-scope file list from step 1>

     ## Spec-AC / TEST evidence
     | Spec-AC | TEST | Status | Evidence |
     |---------|------|--------|----------|

     ## Review status
     Validation: <pass + evidence path> | Code review: <pass/waived + report path>

     ## Test evidence
     <suite names + real counts + exit codes>

     ## Links
     <change doc>, <spec doc>
     ```

5b. MERGE-CONFLICT RESOLUTION + VERIFY MERGE (when syncing the branch with base):
   - Resolve conflicts by file class:
       docs/INDEX.md        → NEVER hand-merge; take either side, then regenerate:
                              node .aai/scripts/generate-docs-index.mjs
       CHANGELOG.md         → stack BOTH [unreleased] entries (keep both blocks,
                              branch entry on top)
       docs/ai/EVENTS.jsonl → union merge: append-only log (RFC-0001), keep
                              BOTH sides' lines
   - Before `git add` of ANY resolved file: `grep -n '^<<<<<<<' <file>` must
     return nothing — no conflict marker may survive.
   - After ANY `git merge`, VERIFY the merge actually happened before committing
     resolutions: a dirty tree makes `git merge` silently abort (observed: a
     squash-merge base moved, the merge aborted, and the resolution commit then
     claimed a merge that never happened). Confirm `.git/MERGE_HEAD` exists
     (merge in progress) or the resulting commit has 2 parents.

6. MERGE BOUNDARY (hard rule):
   - NEVER merge. `gh pr merge` is FORBIDDEN in this skill, in the loop, and in
     any subagent it spawns. Merging is an operator-only action performed by a
     human after their own review. Do not enable auto-merge either.
   - Hook marker (RFC-0010, opt-in overlay): projects with the Claude hooks
     overlay installed deny `git merge` / `gh pr merge` mechanically unless
     `AAI_OPERATOR_MERGE=1` is set on that command. The agent NEVER sets this
     marker for itself. It exists so the OPERATOR — or an agent acting on the
     operator's explicit, recorded direction (cf. the docs/ai/decisions.jsonl
     directed-merge record, 2026-07-16) — can perform a directed merge without
     disabling the overlay. Constitution article 7 is unchanged: this ceremony
     still ends at `gh pr create`. Honest framing: the marker is a guardrail
     against habit, not a security boundary — setting it without the operator's
     explicit direction is a constitution violation, not a technical
     impossibility.
   - After opening the PR, report the PR URL and stop.
   - Branch/worktree cleanup is post-merge work: delete the branch or remove the
     worktree only after `gh pr view <n> --json state` reads MERGED — never on
     the assumption that a merge happened.

STRICT RULES
- No `git add -A`, no `git add .`, no `git commit -a`.
- No force-push unless the operator explicitly asks for it by name.
- Do not rewrite history of a pushed branch.
- Do not merge, approve, or enable auto-merge — operator-only.
- If the staged-vs-scope audit cannot be made clean, STOP and report.

FINAL OUTPUT
- Scope list, staged list (post-audit), commit SHA(s), branch, PR URL.
- Any out-of-scope dirty files left untouched (named).

BEGIN NOW.
