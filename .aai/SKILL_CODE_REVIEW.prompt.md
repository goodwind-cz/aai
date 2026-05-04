# Code Review Skill

## TWO-STAGE REVIEW (MANDATORY ORDER)

**Stage 1 — Spec Compliance** (ALWAYS first)
Does the code match the requirements and spec?
- Read `docs/specs/SPEC-<id>.md` for the current scope (if it exists)
- Check every Spec-AC: is it implemented?
- Check TEST-xxx entries: do tests exist and pass?
- Report: COMPLIANT / NON-COMPLIANT per AC

**Stage 2 — Code Quality** (ONLY after Stage 1 is complete)
Is the code well-written?
- Security, performance, style, best practices (see categories below)

RED FLAG: Starting Stage 2 before Stage 1 = reviewing code that may not match requirements.
A well-written implementation of the wrong thing is still wrong.

## DIFF SCOPE PREFLIGHT (MANDATORY BEFORE STAGE 1)

Code review does not require a git worktree. It requires a clean, explicit diff scope.

Accepted review scopes:
- Worktree or feature branch: `git diff <base>...HEAD`
- Pull request: `gh pr diff <number>`
- Staged changes: `git diff --staged`
- Local inline changes: `git diff` plus `git diff --staged`
- Explicit paths: `git diff -- <path...>` and/or `git diff --staged -- <path...>`
- Commit/range: `git show <sha>` or `git diff <from>..<to>`

Before reviewing:
1. Read `docs/ai/STATE.yaml`.
2. Determine `worktree.user_decision` and `worktree.inline_review_scope`.
3. Run `git status --porcelain`.
4. Establish exactly one review scope.
5. If inline mode is selected and unrelated changes exist outside the scope,
   STOP and ask for exact paths or a diff range.
6. If no clean scope can be established, set `human_input.required: true` with
   a blocking reason and STOP.

Worktree policy:
- If `worktree.user_decision == worktree`, prefer `git diff <base>...HEAD`.
- If `worktree.user_decision == inline`, use `worktree.inline_review_scope`.
- If no worktree metadata exists, review can still proceed using an explicit
  caller-provided diff, PR number, staged diff, or path list.

## Goal
Automatically review code changes for common issues in security, performance, style, and best practices.

## Scope
- Git diffs (local changes)
- GitHub Pull Requests
- Specific files or directories
- Staged changes
- Worktree branch ranges
- Inline scopes recorded in `docs/ai/STATE.yaml`

## Review Categories

### 1. Security
- SQL injection vulnerabilities
- XSS (Cross-Site Scripting)
- Hardcoded credentials
- Insecure dependencies
- Authentication/authorization issues
- CSRF protection
- Input validation
- Unsafe deserialization

### 2. Performance
- N+1 queries
- Missing database indexes
- Inefficient loops
- Memory leaks
- Unbounded recursion
- Large object allocations
- Missing caching opportunities
- Expensive operations in loops

### 3. Style
- Code formatting inconsistencies
- Naming conventions
- Missing documentation
- Overly complex functions
- Magic numbers
- Dead code
- Unused imports
- Inconsistent error handling

### 4. Best Practices
- Missing error handling
- Poor separation of concerns
- Violation of DRY principle
- Missing tests for new code
- Breaking changes without deprecation
- Missing type hints/annotations
- Incorrect use of language features

## Severity Levels

**ERROR** - Must fix before merge
- Security vulnerabilities
- Breaking changes
- Data loss risks
- Critical bugs

**WARNING** - Should fix before merge
- Performance issues
- Code smells
- Missing tests
- Significant style violations

**INFO** - Nice to fix
- Minor style issues
- Suggestions for improvement
- Documentation improvements
- Refactoring opportunities

## Operations

### 1. Review Local Changes (`/aai-code-review`)

Review unstaged changes:

```bash
git diff > /tmp/review.diff
# Analyze diff for issues
```

Review staged changes:

```bash
git diff --staged > /tmp/review.diff
# Analyze diff for issues
```

### 2. Review Specific Files (`/aai-code-review <file>`)

```bash
/aai-code-review src/auth/login.ts

# Reviews only specified file
```

### 3. Review Commit (`/aai-code-review <commit-sha>`)

```bash
/aai-code-review abc123

git show abc123 > /tmp/review.diff
# Analyze commit changes
```

### 4. Review Pull Request (`/aai-code-review --pr <number>`)

```bash
/aai-code-review --pr 42

# Fetch PR diff from GitHub
gh pr diff 42 > /tmp/review.diff
# Analyze and optionally post review
```

### 5. Review Range (`/aai-code-review <from>..<to>`)

```bash
/aai-code-review main..feature-branch

git diff main..feature-branch > /tmp/review.diff
# Analyze range of commits
```

## Review Process

### Step 1: Extract Changes

First run the mandatory Diff Scope Preflight above.

```bash
# For local changes
git diff > /tmp/review.diff

# For PR
gh pr diff 42 > /tmp/review.diff

# For commit
git show abc123 > /tmp/review.diff

# For range
git diff main..feature-branch > /tmp/review.diff
```

### Step 2: Parse Diff

Extract changed files and lines:

```javascript
function parseDiff(diffContent) {
  const files = [];
  let currentFile = null;

  diffContent.split('\n').forEach(line => {
    if (line.startsWith('diff --git')) {
      const match = line.match(/b\/(.+)$/);
      currentFile = {
        path: match[1],
        additions: [],
        deletions: []
      };
      files.push(currentFile);
    } else if (line.startsWith('+') && !line.startsWith('+++')) {
      currentFile.additions.push(line.substring(1));
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      currentFile.deletions.push(line.substring(1));
    }
  });

  return files;
}
```

### Step 3: Analyze Each File

Run checks based on file type:

**JavaScript/TypeScript:**
```javascript
const jsChecks = [
  {
    id: 'SEC-001',
    pattern: /eval\s*\(/,
    severity: 'error',
    category: 'security',
    message: 'Avoid using eval() - security risk'
  },
  {
    id: 'SEC-002',
    pattern: /innerHTML\s*=/,
    severity: 'warning',
    category: 'security',
    message: 'Using innerHTML may expose XSS vulnerabilities'
  },
  {
    id: 'PERF-001',
    pattern: /for\s*\([^)]+\)\s*\{[^}]*await/,
    severity: 'warning',
    category: 'performance',
    message: 'Avoid await in loops - use Promise.all() instead'
  },
  {
    id: 'STYLE-001',
    pattern: /console\.log\(/,
    severity: 'info',
    category: 'style',
    message: 'Remove console.log before committing'
  }
];
```

**Python:**
```javascript
const pyChecks = [
  {
    id: 'SEC-001',
    pattern: /eval\s*\(/,
    severity: 'error',
    category: 'security',
    message: 'Avoid using eval() - use ast.literal_eval()'
  },
  {
    id: 'SEC-002',
    pattern: /exec\s*\(/,
    severity: 'error',
    category: 'security',
    message: 'Avoid using exec() - security risk'
  },
  {
    id: 'PERF-001',
    pattern: /for\s+\w+\s+in\s+range\([^)]+\):\s+list\.append/,
    severity: 'warning',
    category: 'performance',
    message: 'Use list comprehension instead of for-loop with append'
  }
];
```

**SQL:**
```javascript
const sqlChecks = [
  {
    id: 'SEC-001',
    pattern: /\$\{|\%s|string\s+concatenation/,
    severity: 'error',
    category: 'security',
    message: 'SQL injection risk - use parameterized queries'
  },
  {
    id: 'PERF-001',
    pattern: /SELECT \* FROM/i,
    severity: 'warning',
    category: 'performance',
    message: 'Avoid SELECT * - specify columns explicitly'
  }
];
```

### Step 4: Generate Review Report

```javascript
function generateReport(findings) {
  const report = {
    summary: {
      total: findings.length,
      errors: findings.filter(f => f.severity === 'error').length,
      warnings: findings.filter(f => f.severity === 'warning').length,
      info: findings.filter(f => f.severity === 'info').length
    },
    findings: findings.sort((a, b) => {
      const severityOrder = { error: 0, warning: 1, info: 2 };
      return severityOrder[a.severity] - severityOrder[b.severity];
    })
  };

  return report;
}
```

### Step 5: Format Output

**Console Output:**
```
Code Review Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Files Reviewed:  5
Lines Changed:   +147 / -23

Summary:
  ❌ Errors:      2
  ⚠️  Warnings:    5
  ℹ️  Info:        3

Findings:

src/auth/login.ts
  ❌ ERROR [SEC-001] Line 45
     Hardcoded API key detected
     Remove credentials from source code

  ⚠️  WARNING [PERF-001] Line 67
     Await in loop detected
     Use Promise.all() for parallel execution

src/utils/validator.ts
  ⚠️  WARNING [SEC-002] Line 23
     Using innerHTML may expose XSS vulnerabilities
     Use textContent or sanitize input

  ℹ️  INFO [STYLE-001] Line 89
     Remove console.log before committing
     Use proper logging framework

Verdict: ❌ FAILED (2 errors must be fixed)
```

**Markdown Output:**
Save to `docs/ai/reviews/review-<timestamp>.md`:

```markdown
# Code Review Report

**Date:** 2026-03-07 12:34:56 UTC
**Reviewer:** AAI Code Review Skill
**Scope:** Pull Request #42

## Summary

| Metric | Count |
|--------|-------|
| Files Reviewed | 5 |
| Lines Changed | +147 / -23 |
| Errors | 2 |
| Warnings | 5 |
| Info | 3 |

## Findings

### src/auth/login.ts

#### ❌ ERROR [SEC-001] Line 45
**Category:** Security
**Message:** Hardcoded API key detected

```typescript
45: const API_KEY = "sk-abc123...";
```

**Recommendation:** Remove credentials from source code. Use environment variables.

#### ⚠️ WARNING [PERF-001] Line 67
**Category:** Performance
**Message:** Await in loop detected

```typescript
67: for (const user of users) {
68:   await validateUser(user);
69: }
```

**Recommendation:** Use `Promise.all()` for parallel execution:
```typescript
await Promise.all(users.map(user => validateUser(user)));
```

## Verdict

❌ **FAILED** - 2 errors must be fixed before merge
```

### Step 6: Update STATE.yaml

After writing the review report, update `docs/ai/STATE.yaml`:

```yaml
code_review:
  required: <true|false>
  status: <pass|fail|waived>
  scope: <diff-range-or-paths-reviewed>
  base_ref: <base-or-null>
  head_ref: <head-or-null>
  report_paths:
    - docs/ai/reviews/review-<timestamp>.md
    - docs/ai/reviews/review-<timestamp>.json
  notes: <short summary>
```

Status rules:
- `pass`: Stage 1 compliant and no ERROR findings in Stage 2.
- `fail`: any Spec-AC non-compliance, missing required TEST-xxx evidence, or
  any ERROR finding.
- `waived`: only when the user explicitly waives review or accepts remaining
  findings. Record the waiver in `docs/ai/decisions.jsonl`.

Merge/PR readiness:
- ERROR findings block merge/PR readiness.
- WARNING findings require a recorded decision, remediation, or follow-up work item.
- INFO findings do not block.

## GitHub Integration

### Post Review to PR

```bash
/aai-code-review --pr 42 --post

# Generates review
# Posts comments to GitHub using gh CLI
```

**Post review comments:**
```bash
gh pr review 42 \
  --comment \
  --body "$(cat docs/ai/reviews/review-<timestamp>.md)"

# For inline comments:
gh pr review 42 \
  --comment \
  --body "❌ ERROR: Hardcoded credentials detected" \
  --file src/auth/login.ts \
  --line 45
```

### Review Status Check

Create GitHub status check:

```bash
gh api repos/:owner/:repo/statuses/:sha \
  -f state=failure \
  -f context="aai-code-review" \
  -f description="2 errors, 5 warnings" \
  -f target_url="https://your-project.aai-reports.pages.dev/review"
```

## Configuration

Create `.aai/code-review-config.json`:

```json
{
  "enabled_categories": ["security", "performance", "style", "best-practices"],
  "severity_threshold": "warning",
  "ignore_patterns": [
    "*.test.ts",
    "*.spec.js",
    "test/**",
    "**/__mocks__/**"
  ],
  "custom_rules": [
    {
      "id": "CUSTOM-001",
      "pattern": "TODO|FIXME|XXX",
      "severity": "info",
      "category": "style",
      "message": "Unresolved TODO comment",
      "file_types": ["js", "ts", "py"]
    }
  ],
  "github": {
    "post_review": false,
    "auto_approve_if_no_errors": false,
    "request_changes_if_errors": true
  }
}
```

## Usage Examples

### Example 1: Review Local Changes

```bash
/aai-code-review

Reviewing local changes...

✓ Found 3 modified files
✓ Analyzing changes...
✓ Detected 2 issues

Code Review Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Files Reviewed:  3
Lines Changed:   +45 / -12

Summary:
  ⚠️  Warnings:    2
  ℹ️  Info:        0

Findings:

src/api/users.ts
  ⚠️  WARNING [PERF-001] Line 23
     N+1 query detected
     Use eager loading with .include()

Verdict: ⚠️  WARNINGS - Review before merge
```

### Example 2: Review PR with Auto-Post

```bash
/aai-code-review --pr 42 --post

Fetching PR #42...
✓ Fetched diff (5 files, 147 additions, 23 deletions)

Analyzing changes...
✓ Found 7 issues (2 errors, 5 warnings)

Generating review report...
✓ Report saved: docs/ai/reviews/review-20260307-123456.md

Posting to GitHub...
✓ Review posted to PR #42
✓ Requested changes (2 errors must be fixed)

View: https://github.com/owner/repo/pull/42
```

### Example 3: Review Specific Commit

```bash
/aai-code-review abc123

Reviewing commit abc123...
✓ Extracted diff

Code Review Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Commit:  abc123 - "Add user authentication"
Author:  John Doe
Files:   2 modified

Summary:
  ✓ No issues found

Verdict: ✅ PASSED
```

## Advanced Features

### Custom Rules

Add project-specific rules in `.aai/code-review-config.json`:

```json
{
  "custom_rules": [
    {
      "id": "PROJECT-001",
      "pattern": "import.*from\\s+['\"]\\.\\..*['\"]",
      "severity": "warning",
      "category": "best-practices",
      "message": "Avoid deep relative imports - use path aliases",
      "file_types": ["ts", "tsx"]
    },
    {
      "id": "PROJECT-002",
      "pattern": "any\\s+\\w+\\s*:",
      "severity": "warning",
      "category": "best-practices",
      "message": "Avoid using 'any' type - use specific types",
      "file_types": ["ts", "tsx"]
    }
  ]
}
```

### Auto-Fix Suggestions

For certain issues, provide auto-fix diffs:

```javascript
{
  id: 'STYLE-001',
  pattern: /console\.log\(/,
  severity: 'info',
  category: 'style',
  message: 'Remove console.log',
  autoFix: (line) => line.replace(/console\.log\([^)]*\);?\s*/g, '')
}
```

### Integration with CI/CD

Run in GitHub Actions:

```yaml
# .github/workflows/code-review.yml
name: AAI Code Review
on: [pull_request]

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run AAI Code Review
        run: |
          npm install -g @anthropic-ai/claude-cli
          claude --skill aai-code-review --pr ${{ github.event.pull_request.number }}
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `gh: not found` | Install GitHub CLI: `brew install gh` or `apt install gh` |
| Cannot fetch PR | Run `gh auth login` to authenticate |
| No issues found | Check that files match review patterns |
| Too many false positives | Adjust severity threshold or disable specific rules |
| Review not posting | Check GitHub permissions for `gh` CLI |

## Output Files

```
docs/ai/reviews/
├── review-<timestamp>.md         # Markdown review report
├── review-<timestamp>.json       # JSON format for programmatic access
└── LATEST.md                     # Symlink to latest review
```

## Best Practices

1. **Run before committing**: Catch issues early
2. **Configure ignore patterns**: Skip test files if desired
3. **Customize rules**: Add project-specific patterns
4. **Review the reviewer**: Check for false positives
5. **Integrate with CI**: Block merges on errors
6. **Document exceptions**: Add comments for intentional violations

## Output Format

```
Code Review Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Scope:       Pull Request #42
Reviewed:    2026-03-07 12:34:56 UTC
Files:       5 files, +147 / -23 lines

Summary:
  ❌ Errors:      2
  ⚠️  Warnings:    5
  ℹ️  Info:        3

Findings by Category:
  Security:        2 errors, 1 warning
  Performance:     0 errors, 3 warnings
  Style:           0 errors, 1 warning, 3 info

Verdict: ❌ FAILED (2 errors must be fixed)

Report saved:
  Markdown: docs/ai/reviews/review-20260307-123456.md
  JSON:     docs/ai/reviews/review-20260307-123456.json

GitHub:
  ✓ Review posted to PR #42
  ✓ Changes requested

Next steps:
  1. Fix 2 security errors in src/auth/login.ts
  2. Address 5 warnings
  3. Re-run: /aai-code-review --pr 42
```

BEGIN NOW.
