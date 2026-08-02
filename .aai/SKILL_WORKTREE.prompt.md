# Worktree Skill - Git Worktree Management

## Goal
Manage git worktrees for parallel isolated development without branch switching overhead.
Also provide the implementation-preparation gate that recommends worktree usage,
asks the user before creating one, and records an explicit inline override when
the user chooses to continue in the current working tree.

## Instructions

### Command: Recommendation Gate

Evaluate whether the current scope should use a worktree, then ask before any
worktree is created.

**Usage:**
```bash
/aai-worktree gate
```

**When invoked by orchestration:**
- Use this command when `worktree.recommendation` is `recommended` or `required`
  and `worktree.user_decision` is `undecided`.
- `required` means strongly recommended for safety. The user may still explicitly
  override to inline mode, but the decision and risk must be recorded.
- A worktree is not required for code review. Review operates on a clean diff
  scope.

**Steps:**

1. **Read scope and recommendation**
   - Read `docs/ai/STATE.yaml`.
   - Read the linked frozen spec.
   - Capture:
     - `worktree.recommendation`
     - `worktree.rationale`
     - `implementation_strategy.selected`
     - target `ref_id`
     - base ref, defaulting to the current branch's upstream or `main`/`master`.

2. **If no blocking decision is needed**
   - If recommendation is `not_needed`: set `worktree.user_decision: inline`
     and keep `inline_review_scope` explicit if known.
   - If recommendation is `optional`: continue inline by default unless the user
     explicitly requested a worktree.
   - Update `docs/ai/STATE.yaml` and return.

3. **Ask the user for recommended/required isolation**

   Output exactly:

   ```text
   WORKTREE DECISION REQUIRED
   Scope: <ref_id>
   Recommendation: <recommended|required>
   Reason: <worktree.rationale>

   Options:
   w - Create a git worktree and continue there
   i - Continue inline in the current working tree
   p - Pause before implementation

   Question: Use a worktree for this scope?
   ```

   Stop and wait for the answer.

4. **If the user chooses worktree**
   - Run Setup Worktree using the current scope name and chosen base branch.
   - Update `docs/ai/STATE.yaml`:
     ```yaml
     worktree:
       user_decision: worktree
       base_ref: <base>
       branch: <branch>
       path: <worktree_path>
       inline_review_scope: null
     ```
   - Append a `worktree_create` line to `docs/ai/METRICS.jsonl`.

5. **If the user chooses inline**
   - Run `git status --porcelain`.
   - Establish an explicit review scope:
     - Prefer the active spec's changed paths when known.
     - Otherwise use `git diff --name-only <base>...HEAD` for branch work.
     - Otherwise use `git diff --name-only` plus `git diff --staged --name-only`
       for local inline work.
   - If unrelated or ambiguous changes are present, ask one concise follow-up
     question for the exact paths/range to review. Do not implement until the
     review scope is clean.
   - Update `docs/ai/STATE.yaml`:
     ```yaml
     worktree:
       user_decision: inline
       base_ref: <base-or-null>
       branch: null
       path: null
       inline_review_scope: <paths-or-diff-range>
     ```
   - Record a decision in `docs/ai/decisions.jsonl` with:
     `ref_id`, recommendation, rationale, user decision, review scope, and UTC timestamp.

6. **If the user chooses pause**
   - Set `project_status: paused`.
   - Keep `worktree.user_decision: undecided`.
   - Update `updated_at_utc`.
   - Stop.

**Strict rules:**
- Never create a worktree without explicit user confirmation.
- Never block code review only because no worktree exists.
- Inline mode is valid only with a clean explicit review scope.
- If protected paths are touched inline after a `required` recommendation, record
  the user's override before implementation starts.

### Command: Setup Worktree

Create a new worktree for a feature/task.

**Usage:**
```bash
/aai-worktree setup <task-name> [base-branch]
```

**Steps:**

1. **Validate Environment**
   ```bash
   # Check if in git repository
   git rev-parse --git-dir >/dev/null 2>&1

   # Check for uncommitted changes in current directory
   git status --porcelain
   ```

2. **Determine Base Branch**
   - Default: `main` or `master`
   - User can specify custom base: `develop`, `staging`, etc.

3. **Create Worktree**
   ```bash
   # Sanitize task name for branch
   task_name="feature/[sanitized-task-name]"

   # Determine worktree path (sibling directory)
   repo_name=$(basename $(git rev-parse --show-toplevel))
   worktree_path="../${repo_name}-${task_name//\//-}"

   # Create worktree
   git worktree add "$worktree_path" -b "$task_name" "$base_branch"
   ```

4. **Initialize AAI State in Worktree**

   Seed from the canonical schema — never hand-roll a second copy of it.
   `.aai/templates/STATE_TEMPLATE.yaml` is the tracked source of truth (pinned
   by `.aai/SKILL_CHECK_STATE.prompt.md`); an inline copy here silently drifts.
   ```bash
   cd "$worktree_path"
   mkdir -p docs/ai
   # Preserve checked-out runtime state before overwriting it.
   [ -f docs/ai/STATE.yaml ] && cp docs/ai/STATE.yaml docs/ai/STATE.yaml.template
   cp .aai/templates/STATE_TEMPLATE.yaml docs/ai/STATE.yaml
   ```
   Then set ONLY the worktree-specific fields, leaving every other field at the
   template's default: `current_focus.ref_id`, the single `active_work_items`
   entry (`ref_id`/`branch`/`worktree_path`), `worktree.recommendation`,
   `worktree.user_decision: worktree`, `worktree.base_ref`, `worktree.branch`,
   `worktree.path`, and `updated_at_utc`.

5. **Update Worktree Registry**
   - Create/update `.git/worktrees-registry.jsonl` in main repo
   ```jsonl
   {"timestamp":"2026-03-02T09:00:00Z","action":"create","task":"feature/login","path":"../repo-feature-login","branch":"feature/login"}
   ```

6. **Report Success**
   ```
   ✅ Worktree created:
   Path: $worktree_path
   Branch: $task_name
   Base: $base_branch

   Next steps:
   1. cd $worktree_path
   2. /aai-intake [your task description]
   3. Start development

   Or use: /aai-worktree switch $task_name
   ```

### Command: Switch / List Worktrees

- `/aai-worktree switch <task-name>` — resolve the path with `git worktree list`,
  then `cd` into it. If the name matches more than one path, ask which one.
- `/aai-worktree list` — `git worktree list --porcelain`. Flag any worktree
  untouched for 7+ days as a cleanup candidate.

### Command: Cleanup Worktree

Remove a completed or abandoned worktree.

**Usage:**
```bash
/aai-worktree cleanup <task-name>
```

**Steps:**

1. **Validate Cleanup**
   - Check if worktree has uncommitted changes
   - Check if branch has been merged
   - Ask for confirmation if unmerged

2. **Save Final State**
   ```bash
   # Archive STATE.yaml
   mkdir -p docs/ai/archive/worktrees
   cp [worktree-path]/docs/ai/STATE.yaml \
      docs/ai/archive/worktrees/STATE-[task-name]-[timestamp].yaml
   ```

3. **Remove Worktree**
   ```bash
   git worktree remove [worktree-path]

   # Or force if needed (after confirmation)
   git worktree remove --force [worktree-path]
   ```

4. **Delete Branch (Optional)**
   ```bash
   # Ask user if they want to delete branch
   git branch -d [branch-name]

   # Or force delete
   git branch -D [branch-name]
   ```

5. **Update Registry**
   ```jsonl
   {"timestamp":"2026-03-02T10:00:00Z","action":"cleanup","task":"feature/login","path":"../repo-feature-login","merged":true}
   ```

6. **Report**
   ```
   ✅ Worktree cleaned up:
   Task: feature/login
   Branch: [deleted/kept]
   Archived state: docs/ai/archive/worktrees/STATE-feature-login-20260302.yaml
   ```

### Command: Sync Worktree

`/aai-worktree sync` — `git fetch origin`, then
`git rebase origin/<base-branch>` (base from `worktree.base_ref` in
`docs/ai/STATE.yaml`, else `main`). On conflict, report the conflicting paths
and block until they are resolved; never auto-resolve.

## Token Optimization

### Benefits

1. **No Context Pollution**
   - Each worktree has clean STATE.yaml
   - No need to track "which branch am I on?"
   - Reduced cognitive load

2. **Parallel Development**
   - Multiple agents can work simultaneously
   - No waiting for others to finish

3. **Quick Switching**
   - `cd` vs `git stash && git checkout && git stash pop`
   - Faster iteration

## Best Practices

The recommendation levels (`required` / `recommended` / `optional` /
`not_needed`) and the criteria that select them have ONE home:
`.aai/PLANNING.prompt.md` step 8. Read them there; do not restate them here.
Branch-to-path naming is the sibling-path convention in Setup Worktree step 3.

## Safety & Error Handling

`git worktree remove` refuses on a dirty tree and `git branch -d` refuses on an
unmerged branch, so let git do the checking. What git does NOT protect:

- **Archive `STATE.yaml` BEFORE `git worktree remove`** (Cleanup step 2 before
  step 3). Doing it in the other order destroyed unrecoverable metrics
  (`docs/knowledge/LEARNED.md` 2026-07-16/17); nothing enforces the ordering.
- Never pass `--force` to `git worktree remove` or `-D` to `git branch` without
  an explicit user confirmation naming what will be lost.
