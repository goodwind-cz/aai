# Auto-Trigger System Skill

## Goal
Automatically detect user intent and invoke appropriate AAI skills without explicit slash commands.

## How It Works

The system uses pattern matching rules in `.claude/triggers.json` to map user input to skills.

When a user message matches a trigger pattern:
1. System detects the pattern
2. Automatically invokes the matching skill
3. Passes the original message as context

## Configuration File

Location: `.claude/triggers.json`

Structure:
```json
{
  "version": "1.0",
  "enabled": true,
  "triggers": [
    {
      "id": "intake-feature",
      "enabled": true,
      "priority": 10,
      "patterns": [
        "^(add|create|build|implement)\\s+(a|an|the)?\\s*feature",
        "i need (a|an) new feature",
        "can you (add|create|build)"
      ],
      "skill": "aai-intake",
      "args": "",
      "description": "Detect feature requests and trigger intake"
    },
    {
      "id": "intake-bug",
      "enabled": true,
      "priority": 20,
      "patterns": [
        "^(bug|issue|problem|error|broken)",
        "(doesn't|does not|won't|will not) work",
        "(fix|resolve) (the|this|a)"
      ],
      "skill": "aai-intake",
      "args": "",
      "description": "Detect bug reports and trigger intake"
    },
    {
      "id": "validate",
      "enabled": true,
      "priority": 30,
      "patterns": [
        "^(run|execute)\\s+(validation|tests?|checks?)",
        "validate (the|this)?\\s*(changes?|code|implementation)",
        "are (the )?tests? passing"
      ],
      "skill": "aai-validate-report",
      "args": "",
      "description": "Detect validation requests"
    },
    {
      "id": "tdd",
      "enabled": true,
      "priority": 40,
      "patterns": [
        "^(run|start|begin)\\s+tdd",
        "test[- ]driven",
        "write tests? (first|for)"
      ],
      "skill": "aai-tdd",
      "args": "",
      "description": "Detect TDD workflow requests"
    },
    {
      "id": "share",
      "enabled": true,
      "priority": 50,
      "patterns": [
        "^(share|publish|deploy)\\s+(the|this)?\\s*(report|doc)",
        "create.*shareable link",
        "make.*public"
      ],
      "skill": "aai-share",
      "args": "",
      "description": "Detect share/publish requests"
    }
  ]
}
```

## Operations

### 1. List Triggers (`/aai-auto-trigger list`)

Display all configured triggers:

```
Auto-Trigger Configuration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

System:    ✓ Enabled
Config:    .claude/triggers.json
Triggers:  5 total, 5 enabled, 0 disabled

┌────────────────┬──────────┬──────────┬─────────────────────────────────────┐
│ ID             │ Priority │ Status   │ Skill                              │
├────────────────┼──────────┼──────────┼─────────────────────────────────────┤
│ intake-feature │    10    │ Enabled  │ aai-intake                         │
│ intake-bug     │    20    │ Enabled  │ aai-intake                         │
│ validate       │    30    │ Enabled  │ aai-validate-report                │
│ tdd            │    40    │ Enabled  │ aai-tdd                            │
│ share          │    50    │ Enabled  │ aai-share                          │
└────────────────┴──────────┴──────────┴─────────────────────────────────────┘

Pattern Examples:
  intake-feature: "add a feature", "create new functionality"
  intake-bug:     "bug in login", "fix the header issue"
  validate:       "run tests", "validate changes"
  tdd:            "start tdd", "write tests first"
  share:          "publish report", "share this document"
```

### 2. Add Trigger (`/aai-auto-trigger add`)

Add a new trigger pattern:

**Interactive Mode:**
```
What skill should be triggered? aai-worktree
What should trigger it? (pattern): ^create.*worktree
Priority (1-100, lower = higher priority): 15
Description: Create worktree for isolated work
Enable immediately? (y/n): y

✓ Trigger added: worktree-create
  Skill:    aai-worktree
  Pattern:  ^create.*worktree
  Priority: 15
  Status:   Enabled
```

**Direct Mode:**
```bash
/aai-auto-trigger add \
  --skill aai-worktree \
  --pattern "^create.*worktree" \
  --priority 15 \
  --description "Create worktree for isolated work" \
  --enabled
```

### 3. Enable/Disable Triggers

**Disable a trigger:**
```
/aai-auto-trigger disable intake-feature

✓ Trigger disabled: intake-feature
  Auto-detection for feature requests is now OFF
```

**Enable a trigger:**
```
/aai-auto-trigger enable intake-feature

✓ Trigger enabled: intake-feature
  Auto-detection for feature requests is now ON
```

**Disable entire system:**
```
/aai-auto-trigger disable --all

✓ Auto-trigger system disabled
  All triggers are now inactive
  Use `/aai-auto-trigger enable --all` to re-enable
```

### 4. Remove Trigger

```
/aai-auto-trigger remove intake-feature

⚠️  Remove trigger: intake-feature
  Skill:    aai-intake
  Pattern:  ^(add|create|build|implement)\s+(a|an|the)?\s*feature

Confirm removal? (y/n): y

✓ Trigger removed: intake-feature
```

### 5. Test Pattern (`/aai-auto-trigger test`)

Test if user input matches any triggers:

```
/aai-auto-trigger test "add a new feature for user login"

Pattern Match Results
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Input: "add a new feature for user login"

✓ MATCH: intake-feature (priority 10)
  Skill:   aai-intake
  Pattern: ^(add|create|build|implement)\s+(a|an|the)?\s*feature
  Would invoke: /aai-intake

No other matches found.
```

### 6. Edit Trigger (`/aai-auto-trigger edit`)

Modify existing trigger:

```
/aai-auto-trigger edit intake-bug

Current configuration:
  ID:          intake-bug
  Skill:       aai-intake
  Priority:    20
  Enabled:     true
  Patterns:    3 patterns

What to edit? (pattern/priority/skill/description/enabled): pattern

Current patterns:
  1. ^(bug|issue|problem|error|broken)
  2. (doesn't|does not|won't|will not) work
  3. (fix|resolve) (the|this|a)

Add pattern (or 'done'): (is )?broken
Add pattern (or 'done'): done

✓ Trigger updated: intake-bug
  Added 1 pattern, now has 4 total
```

## Pattern Syntax

Patterns use JavaScript regex (case-insensitive by default):

**Anchors:**
- `^` - Start of string
- `$` - End of string

**Quantifiers:**
- `*` - 0 or more
- `+` - 1 or more
- `?` - 0 or 1

**Groups:**
- `(a|b|c)` - Match a, b, or c
- `(pattern)?` - Optional group

**Character classes:**
- `\s` - Whitespace
- `\w` - Word character
- `.` - Any character

**Examples:**
```regex
^(add|create|build).*feature      # Starts with add/create/build, contains "feature"
(bug|issue|error).*in             # Contains bug/issue/error followed by "in"
^run\s+(test|validation)          # Starts with "run" followed by test/validation
(doesn't|does not)\s+work         # Negative pattern for broken functionality
```

## Priority System

Priority determines which trigger fires when multiple patterns match:

- **Lower number = higher priority**
- Priority range: 1-100
- If multiple triggers match, the lowest priority number wins

**Recommended priorities:**
- 1-10: Critical/override triggers
- 11-30: Primary workflow triggers (intake, validate, tdd)
- 31-50: Secondary workflows (share, worktree, docs)
- 51-70: Utility triggers (check-state, flush)
- 71-100: Experimental/custom triggers

## Configuration Management

### Initialize Default Config

If `.claude/triggers.json` doesn't exist, create it:

```bash
mkdir -p .claude
cat > .claude/triggers.json << 'EOF'
{
  "version": "1.0",
  "enabled": true,
  "triggers": [
    {
      "id": "intake-feature",
      "enabled": true,
      "priority": 10,
      "patterns": [
        "^(add|create|build|implement)\\s+(a|an|the)?\\s*feature",
        "i need (a|an) new feature"
      ],
      "skill": "aai-intake",
      "args": "",
      "description": "Detect feature requests"
    },
    {
      "id": "intake-bug",
      "enabled": true,
      "priority": 20,
      "patterns": [
        "^(bug|issue|problem|error|broken)",
        "(doesn't|does not|won't|will not) work"
      ],
      "skill": "aai-intake",
      "args": "",
      "description": "Detect bug reports"
    },
    {
      "id": "validate",
      "enabled": true,
      "priority": 30,
      "patterns": [
        "^(run|execute)\\s+(validation|tests?|checks?)",
        "validate (the|this)?\\s*(changes?|code)"
      ],
      "skill": "aai-validate-report",
      "args": "",
      "description": "Detect validation requests"
    }
  ]
}
EOF
```

### Backup Config

```bash
cp .claude/triggers.json .claude/triggers.json.bak
```

### Restore Config

```bash
cp .claude/triggers.json.bak .claude/triggers.json
```

## Integration with Claude Skills

When a trigger fires:

1. System detects pattern match
2. Invokes skill: `Skill(skill: "aai-intake", args: "<original-message>")`
3. Skill receives original user message as context
4. Skill proceeds normally

**Example flow:**
```
User: "add a feature for user authentication"
  ↓
Auto-trigger detects pattern: "^(add|create|build).*feature"
  ↓
Invokes: /aai-intake "add a feature for user authentication"
  ↓
Intake skill processes request normally
```

## Safety Features

**Confirmation for destructive actions:**
- Triggers for `/aai-flush` or other destructive operations should ask for confirmation
- Set `"confirm": true` in trigger config

**Dry-run mode:**
```json
{
  "enabled": false,
  "dry_run": true,
  "triggers": [...]
}
```
When `dry_run: true`:
- Patterns are matched
- Skills are NOT invoked
- System reports what would have been triggered

## Usage Examples

### Example 1: Auto-detect Feature Request

```
User: "I need to add user authentication to the app"

[Auto-trigger matches: intake-feature]
✓ Detected: Feature request
  Triggering: /aai-intake

[Intake skill runs normally]
Detected type: prd — new feature with measurable criteria
What are the acceptance criteria for this feature?
```

### Example 2: Auto-detect Bug Report

```
User: "The login button doesn't work on mobile"

[Auto-trigger matches: intake-bug]
✓ Detected: Bug report
  Triggering: /aai-intake

[Intake skill runs normally]
Detected type: issue — bug with reproducible steps
What are the steps to reproduce this issue?
```

### Example 3: Manual Override

```
User: "add a feature to the database schema"

[Auto-trigger matches: intake-feature, but user can override]

System: Detected feature request. Trigger /aai-intake? (y/n/manual)
User: manual

[User can then specify exact command]
User: /aai-intake --type=techdebt "refactor database schema"
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Triggers not firing | Check `.claude/triggers.json` has `"enabled": true` |
| Wrong skill triggered | Adjust pattern specificity or priority values |
| Multiple matches | Lower priority number for preferred trigger |
| Pattern not matching | Test with `/aai-auto-trigger test "your input"` |
| Config not found | Run `/aai-auto-trigger init` to create default config |
| Regex errors | Escape special characters: `\.` `\?` `\+` etc. |

## Advanced Features

### Conditional Triggers

Trigger only if certain files exist:

```json
{
  "id": "tdd-auto",
  "enabled": true,
  "priority": 40,
  "patterns": ["^implement"],
  "skill": "aai-tdd",
  "conditions": {
    "file_exists": ["package.json", "jest.config.js"]
  },
  "description": "Auto-start TDD if test framework detected"
}
```

### Context-aware Triggers

Pass extracted context to skills:

```json
{
  "id": "validate-file",
  "enabled": true,
  "priority": 35,
  "patterns": ["^validate\\s+(.+\\.ts)$"],
  "skill": "aai-validate-report",
  "args": "--file ${1}",
  "description": "Validate specific file"
}
```

### Chained Triggers

Trigger multiple skills in sequence:

```json
{
  "id": "full-cycle",
  "enabled": true,
  "priority": 5,
  "patterns": ["^full cycle"],
  "skill": "aai-intake",
  "chain": ["aai-tdd", "aai-validate-report"],
  "description": "Run full intake → TDD → validate cycle"
}
```

## Best Practices

1. **Start specific, then generalize**: Add narrow patterns first, broaden if needed
2. **Test before enabling**: Use `/aai-auto-trigger test` to verify patterns
3. **Document patterns**: Add clear descriptions for maintainability
4. **Use priority wisely**: Reserve low numbers (1-10) for override triggers
5. **Backup config**: Save `.claude/triggers.json.bak` before major changes
6. **Monitor false positives**: Disable triggers that fire incorrectly
7. **Keep it simple**: Prefer multiple simple patterns over complex regex

## Output Format

When listing triggers:
```
Auto-Trigger Configuration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

System:    ✓ Enabled / ✗ Disabled / ⚠ Dry-run
Config:    .claude/triggers.json
Triggers:  <total> total, <enabled> enabled, <disabled> disabled

[Table of triggers with ID, Priority, Status, Skill]

Recent Activity:
  <timestamp>: intake-feature → /aai-intake (matched: "add new feature")
  <timestamp>: validate → /aai-validate-report (matched: "run tests")

Commands:
  /aai-auto-trigger list                    - Show all triggers
  /aai-auto-trigger add                     - Add new trigger
  /aai-auto-trigger edit <id>               - Edit trigger
  /aai-auto-trigger enable|disable <id>     - Toggle trigger
  /aai-auto-trigger remove <id>             - Delete trigger
  /aai-auto-trigger test "<input>"          - Test pattern matching
  /aai-auto-trigger enable|disable --all    - Toggle entire system
```

BEGIN NOW.
