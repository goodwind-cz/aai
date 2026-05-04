# Worktree Skill - Git Worktree Management

## Goal
Manage git worktrees for parallel isolated development without branch switching overhead.
Also provide the implementation-preparation gate that recommends worktree usage,
asks the user before creating one, and records an explicit inline override when
the user chooses to continue in the current working tree.

Inspired by Superpowers framework's worktree-based parallel development.

## What are Git Worktrees?

Git worktrees allow multiple working directories from a single repository:
- Each worktree has its own branch checked out
- No need to stash changes when switching tasks
- Parallel development without conflicts
- Isolated context for subagents

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
   ```bash
   cd "$worktree_path"

   # Preserve checked-out runtime state as a template, then create isolated state.
   mkdir -p docs/ai
   if [ -f docs/ai/STATE.yaml ]; then
     cp docs/ai/STATE.yaml docs/ai/STATE.yaml.template
   fi

   now_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
   recommendation="${worktree_recommendation:-recommended}"
   cat > docs/ai/STATE.yaml <<EOF
   project_status: active

   current_focus:
     type: maintenance
     ref_id: "$task_name"
     primary_path: null

   locks:
     implementation: false
     implementation_reason: "Worktree-isolated implementation."
     protected_paths: []
     protected_paths_edit_allowed: true
     protected_paths_reason: "Worktree selected by user for isolated changes."

   active_work_items:
     - ref_id: "$task_name"
       status: in_progress
       phase: planning
       branch: "$task_name"
       worktree_path: "$worktree_path"

   implementation_strategy:
     selected: undecided
     source: null
     rationale: null

   worktree:
     recommendation: "$recommendation"
     user_decision: worktree
     base_ref: "$base_branch"
     branch: "$task_name"
     path: "$worktree_path"
     inline_review_scope: null
     rationale: "Isolated worktree selected by user."

   code_review:
     required: true
     status: not_run
     scope: "$base_branch...HEAD"
     base_ref: "$base_branch"
     head_ref: HEAD
     report_paths: []
     notes: "No code review run yet."

   last_validation:
     status: not_run
     run_at_utc: null
     validator_ref: .aai/VALIDATION.prompt.md
     evidence_paths: []
     notes: "No validation run yet."

   human_input:
     required: false
     question_ref: null
     blocking_reason: null

   ai_os:
     pin_path: .aai/system/AAI_PIN.md
     pin_version: null
     pin_commit: null

   updated_at_utc: "$now_utc"
   EOF
   ```

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

### Command: Switch Worktree

Switch to an existing worktree.

**Usage:**
```bash
/aai-worktree switch <task-name>
```

**Steps:**

1. **List Available Worktrees**
   ```bash
   git worktree list
   ```

2. **Find Matching Worktree**
   - Search for task name in worktree paths
   - Present options if multiple matches

3. **Switch Context**
   ```bash
   cd [worktree-path]
   ```

4. **Report Status**
   ```
   Switched to: [worktree-path]
   Branch: [branch-name]
   Last activity: [timestamp from STATE.yaml]
   ```

### Command: List Worktrees

Show all active worktrees.

**Usage:**
```bash
/aai-worktree list
```

**Steps:**

1. **Get Worktree List**
   ```bash
   git worktree list --porcelain
   ```

2. **Parse and Format**
   ```
   Active Worktrees:

   1. feature/login
      Path: ../repo-feature-login
      Branch: feature/login
      Status: in_progress
      Last activity: 2 hours ago

   2. bugfix/auth-error
      Path: ../repo-bugfix-auth-error
      Branch: bugfix/auth-error
      Status: blocked
      Last activity: 1 day ago
   ```

3. **Highlight Stale Worktrees**
   - Warn if worktree hasn't been touched in 7+ days
   - Suggest cleanup

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

Sync worktree with base branch.

**Usage:**
```bash
/aai-worktree sync
```

**Steps:**

1. **Fetch Latest**
   ```bash
   git fetch origin
   ```

2. **Rebase on Base Branch**
   ```bash
   # Determine base branch from STATE.yaml or default to main
   git rebase origin/[base-branch]
   ```

3. **Resolve Conflicts (if any)**
   - Report conflicts
   - Provide guidance for manual resolution
   - Block until conflicts resolved

4. **Report Status**
   ```
   ✅ Worktree synced with origin/main
   Commits ahead: 3
   Commits behind: 0
   Conflicts: none
   ```

## Integration with AAI Workflow

### Parallel Feature Development

```
User: "Work on login and profile features in parallel"

1. Create worktrees:
   /aai-worktree setup login
   /aai-worktree setup profile

2. In worktree 1 (login):
   cd ../repo-feature-login
   /aai-intake "Add user login with email/password"
   /aai-planning
   /aai-tdd (implement login)

3. In worktree 2 (profile):
   cd ../repo-feature-profile
   /aai-intake "Add user profile page"
   /aai-planning
   /aai-tdd (implement profile)

4. Switch between worktrees as needed:
   /aai-worktree switch login
   /aai-worktree switch profile

5. Cleanup after merge:
   /aai-worktree cleanup login
   /aai-worktree cleanup profile
```

### Subagent Isolation

```
Main agent (orchestrator):
  ↓
  Spawns subagent for Task A in worktree-A
  Spawns subagent for Task B in worktree-B
  ↓
  Each subagent works in isolated context
  No conflicts, no branch switching
```

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

### When to Use Worktrees

Good use cases:
- Parallel feature development
- Long-running branches
- Experimental changes alongside stable work
- Subagent isolation
- PR-bound features with substantial scope
- Changes to protected AAI workflow, state schema, or orchestration prompts

Avoid for:
- Quick fixes (use regular branches)
- Short-lived changes (< 1 hour)
- When disk space is limited
- Documentation-only updates with a clean inline diff

Recommendation levels:
- `required`: strongly recommended for protected workflow/state/schema changes,
  high-risk migrations, or broad refactors. The user may explicitly override inline.
- `recommended`: useful for larger, experimental, PR-bound, or parallel work.
- `optional`: useful but not important for safety.
- `not_needed`: inline work is the normal path.

### Naming Conventions

```
feature/[feature-name]    → ../repo-feature-[feature-name]
bugfix/[issue-number]     → ../repo-bugfix-[issue-number]
experiment/[experiment]   → ../repo-experiment-[experiment]
```

### Cleanup Schedule

- Daily: Review active worktrees
- Weekly: Cleanup merged worktrees
- Monthly: Archive old worktree states

## Safety & Error Handling

### Prevent Data Loss

1. **Check for Uncommitted Changes**
   ```bash
   if [ -n "$(git status --porcelain)" ]; then
     echo "ERROR: Uncommitted changes in worktree"
     echo "Please commit or stash before cleanup"
     exit 1
   fi
   ```

2. **Confirm Before Force Operations**
   ```
   WARNING: Branch 'feature/login' is not fully merged.

   Options:
   1. Keep worktree for later review
   2. Force delete (IRREVERSIBLE)
   3. Merge/rebase now

   Choose [1-3]:
   ```

3. **Archive State Before Cleanup**
   - Always save STATE.yaml
   - Include git log summary
   - Store in `docs/ai/archive/worktrees/`

## Troubleshooting

### Worktree creation fails
```bash
# Common causes:
# 1. Branch already exists
git branch -D [branch-name]

# 2. Worktree path exists
rm -rf [worktree-path]

# 3. Locked worktree
git worktree prune
```

### Can't remove worktree
```bash
# If worktree is locked
git worktree unlock [worktree-path]
git worktree remove [worktree-path]

# If worktree directory is deleted manually
git worktree prune
```

### Lost worktree reference
```bash
# Repair worktree connections
git worktree repair

# List all worktrees
git worktree list
```

## Metrics

Track worktree usage in `docs/ai/METRICS.jsonl`:
```jsonl
{"timestamp":"2026-03-02T09:00:00Z","type":"worktree_create","task":"feature/login","path":"../repo-feature-login"}
{"timestamp":"2026-03-02T11:00:00Z","type":"worktree_cleanup","task":"feature/login","duration_hours":2,"commits":5,"merged":true}
```

## Example Session

```bash
# Start new feature in worktree
$ /aai-worktree setup login main
✅ Worktree created: ../my-app-feature-login

# Work on feature
$ cd ../my-app-feature-login
$ /aai-intake "Add JWT-based login"
$ /aai-tdd
$ git commit -m "feat: add login endpoint"

# Switch back to main worktree for hotfix
$ /aai-worktree switch main
Switched to: /workspace/my-app

# Quick hotfix
$ git checkout -b hotfix/critical-bug
$ # ... fix bug ...
$ git push origin hotfix/critical-bug

# Return to feature work
$ /aai-worktree switch login
Switched to: ../my-app-feature-login

# Complete feature and cleanup
$ git push origin feature/login
$ # ... PR merged ...
$ /aai-worktree cleanup login
✅ Worktree cleaned up
```
