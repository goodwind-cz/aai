# AAI Docs Hub Skill

Interactive documentation hub for AAI skills. Automatically discovers, catalogs, and generates a beautiful searchable HTML interface for all AAI skills in the project.

## What It Does

1. **Discovers** all AAI skills in `.claude/skills/*/SKILL.md`
2. **Reads** metadata and corresponding `.aai/*.prompt.md` files
3. **Categorizes** skills by purpose (Intake, Development, Workflow, Quality, Publishing)
4. **Extracts** relationships, dependencies, and usage patterns
5. **Generates** interactive HTML catalog with:
   - Real-time search
   - Category filtering
   - Dark/light theme toggle
   - Skill relationship flowchart
   - Usage examples and guidelines
   - Mobile-responsive design

## Usage

```bash
/aai-docs-hub
```

This will generate/update `docs/SKILL_CATALOG.html` with the latest skill information.

## Publishing

Share the documentation hub publicly:

```bash
/aai-share docs/SKILL_CATALOG.html
```

## Features

### Interactive Search
- Type to filter skills by name, description, command, or tags
- Keyboard shortcut: Press `/` to focus search

### Category Filters
- All Skills
- Intake & Planning
- Development & Testing
- Workflow & Orchestration
- Quality & Maintenance
- Publishing & Sharing

### Skill Cards
Each skill shows:
- Command name (e.g., `/aai-intake`)
- Description
- Usage example
- When to use / when NOT to use
- Prerequisites
- Related skills
- Quick actions (View Prompt, Copy Command)

### Skill Flowchart
Visual representation of the AAI workflow stages:
1. Intake & Planning
2. Development & Testing
3. Workflow & Orchestration
4. Quality & Maintenance
5. Publishing & Sharing

### Dark/Light Theme
- Toggle button in header
- Preference saved to localStorage
- Smooth transitions

### Mobile Friendly
- Responsive grid layout
- Touch-friendly controls
- Optimized for all screen sizes

## Maintenance

Re-run `/aai-docs-hub` whenever:
- New skills are added
- Skill descriptions change
- Prompt files are updated
- You want to refresh the catalog

The catalog is fully regenerated each time for consistency.

## Files

- `.claude/skills/aai-docs-hub/SKILL.md` - Skill definition
- `.aai/SKILL_DOCS_HUB.prompt.md` - Main prompt with instructions
- `docs/SKILL_CATALOG.html` - Generated interactive catalog (template included)

## Architecture

The system works in phases:

1. **Discovery**: Scan `.claude/skills/` for all `SKILL.md` files
2. **Metadata Extraction**: Parse YAML frontmatter and prompt files
3. **Categorization**: Auto-categorize based on skill purpose
4. **Relationship Mapping**: Extract dependencies from prompt text
5. **HTML Generation**: Create beautiful, functional catalog
6. **Publishing**: Optional sharing via `/aai-share`

## Template

The included `docs/SKILL_CATALOG.html` is a pre-populated template with example skills. Running `/aai-docs-hub` will regenerate it with actual project skills.

## Technology

- Pure HTML/CSS/JavaScript (no frameworks)
- CSS Grid and Flexbox for layout
- CSS Custom Properties for theming
- LocalStorage for preferences
- Responsive design with media queries
- Semantic HTML5
