#!/usr/bin/env node
// generate-docs-hub.mjs — deterministic AAI skills documentation catalog
// generator (CHANGE-0078 / spec-docs-hub-generator).
//
// Renders docs/SKILL_CATALOG.html (+ docs/skill-catalog-data.json): a
// searchable, self-contained catalog of every skill under .claude/skills/,
// assembled deterministically from committed artifacts:
//   - .claude/skills/*/SKILL.md   frontmatter (name, description, model)
//   - .aai/SKILL_*.prompt.md      the "## Goal" section, when the SKILL.md
//                                 body references one
//
// Replaces the old .aai/SKILL_DOCS_HUB.prompt.md flow (a ~70-file LLM
// fan-out re-run by hand on every skill addition, which drifted to 27/35
// skills stale by 2026-07-07). This script is read-only over its inputs and
// writes only the two output files — mirrors generate-overview.mjs's shape.
//
// Extraction is MECHANICAL, never inferred:
//   - name/description/model: regex line read of the SKILL.md frontmatter
//     block (same house style as generate-overview.mjs's readFrontmatter).
//   - promptFile: the first `.aai/SKILL_*.prompt.md` path literally referenced
//     in the SKILL.md body (every wrapper names its own prompt file this
//     way); a script-first skill with no such reference (e.g. aai-overview)
//     legitimately has none.
//   - goal: the body of prompt file's "## Goal" heading, up to the next
//     "## " heading.
//   - "when to use": SKILL.md's own `description` field IS this — every
//     description in the corpus already starts "Use when ..."; there is no
//     separate "## When to use" heading in the real prompt corpus, so this
//     is sourced from frontmatter, not guessed from prose.
// Any of the above that cannot be found produces a visible NOTE on that
// skill's card and in its JSON `notes` array — never a silent omission.
//
// Byte-idempotent on unchanged inputs: skills are sorted by directory name,
// object key order is fixed, and the HTML carries NO timestamp (unlike
// overview.html) — only docs/skill-catalog-data.json's `generatedAt` field
// varies run to run, so two back-to-back runs produce byte-identical HTML.
//
// Usage: node .aai/scripts/generate-docs-hub.mjs [--output <html>] [--data-only]
// Node stdlib only (docs/TECHNOLOGY.md).

import fs from 'node:fs';
import path from 'node:path';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

const ROOT = process.cwd();
const SKILLS_DIR = '.claude/skills';

function parseArgs(argv) {
  const args = { outputPath: 'docs/SKILL_CATALOG.html', dataOnly: false };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--output' && argv[i + 1]) { args.outputPath = argv[i + 1]; i += 1; continue; }
    if (tok === '--data-only') { args.dataOnly = true; continue; }
    if (tok === '-h' || tok === '--help') {
      console.log('Usage: generate-docs-hub.mjs [--output <html path>] [--data-only]');
      exit(0);
    }
    // The wrapper prompt promises exit 2 + nothing written on a typo'd flag
    // (review PR #180) — silent fall-through would run a full generation.
    console.error(`unknown flag: ${tok}`);
    console.error('Usage: generate-docs-hub.mjs [--output <html path>] [--data-only]');
    exit(2);
  }
  return args;
}

// Same regex-line-read house style as generate-overview.mjs's readFrontmatter.
function parseFrontmatter(body) {
  const norm = body.replace(/\r\n?/g, '\n');
  const fm = norm.match(/^---\n([\s\S]*?)\n---/);
  const out = { name: null, description: null, model: null };
  if (fm) {
    for (const key of ['name', 'description', 'model']) {
      const m = fm[1].match(new RegExp(`^${key}:\\s*(.+?)\\s*$`, 'm'));
      if (m) out[key] = m[1].replace(/^["']|["']$/g, '');
    }
  }
  return out;
}

function findPromptRef(skillBody) {
  const m = skillBody.match(/\.aai\/(SKILL_[A-Z0-9_]+\.prompt\.md)/);
  return m ? m[1] : null;
}

const GOAL_HEADING_RE = /^##\s+Goal\s*$/i;

// extractSection(body, headingRe) -> trimmed body text between the FIRST
// line matching headingRe and the next "## " heading (or EOF), or null when
// the heading is absent or its body is empty after trimming.
function extractSection(body, headingRe) {
  const lines = body.replace(/\r\n?/g, '\n').split('\n');
  const start = lines.findIndex((l) => headingRe.test(l));
  if (start === -1) return null;
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i += 1) {
    if (/^##\s+/.test(lines[i])) { end = i; break; }
  }
  const section = lines.slice(start + 1, end).join('\n').trim();
  return section || null;
}

function discoverSkillDirs() {
  const abs = path.join(ROOT, SKILLS_DIR);
  let entries = [];
  try {
    entries = fs.readdirSync(abs, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort();
  } catch { /* no .claude/skills dir — empty catalog, not an error */ }
  return entries;
}

function buildSkill(dir) {
  const skillMdPath = `${SKILLS_DIR}/${dir}/SKILL.md`;
  const notes = [];
  let skillBody = null;
  try {
    skillBody = fs.readFileSync(path.join(ROOT, skillMdPath), 'utf8');
  } catch (err) {
    notes.push(`NOTE: ${skillMdPath} could not be read (${err.code ?? err.message})`);
  }
  const fm = skillBody !== null ? parseFrontmatter(skillBody) : { name: null, description: null, model: null };
  if (skillBody !== null && !fm.name) notes.push(`NOTE: ${skillMdPath} frontmatter is missing "name"`);
  if (skillBody !== null && !fm.description) notes.push(`NOTE: ${skillMdPath} frontmatter is missing "description"`);

  const promptRef = skillBody !== null ? findPromptRef(skillBody) : null;
  let promptFile = null;
  let goal = null;
  if (!promptRef) {
    if (skillBody !== null) {
      notes.push(`NOTE: no .aai/SKILL_*.prompt.md reference found in ${skillMdPath} (script-first skill — see description)`);
    }
  } else {
    promptFile = `.aai/${promptRef}`;
    let promptBody = null;
    try {
      promptBody = fs.readFileSync(path.join(ROOT, promptFile), 'utf8');
    } catch {
      notes.push(`NOTE: referenced prompt ${promptFile} was not found on disk`);
    }
    if (promptBody !== null) {
      goal = extractSection(promptBody, GOAL_HEADING_RE);
      if (!goal) notes.push(`NOTE: no "## Goal" section found in ${promptFile}`);
    }
  }

  return {
    dir,
    name: fm.name ?? dir,
    description: fm.description,
    model: fm.model,
    promptFile,
    goal,
    notes,
  };
}

function buildModel() {
  const dirs = discoverSkillDirs();
  const skills = dirs.map(buildSkill);
  const degradedCount = skills.filter((s) => s.notes.length > 0).length;
  return {
    generatedAt: new Date().toISOString(),
    skillsCount: skills.length,
    degradedCount,
    skills,
  };
}

function esc(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function skillCard(s) {
  const searchText = esc([s.name, s.description, s.goal, s.dir].filter(Boolean).join(' ').toLowerCase());
  const model = s.model ? `<span class="badge">${esc(s.model)}</span>` : '';
  const notes = s.notes.length
    ? `<ul class="notes">${s.notes.map((n) => `<li>${esc(n)}</li>`).join('')}</ul>`
    : '';
  return `<div class="skill-card" data-search="${searchText}">
  <h3>${esc(s.name)}${model}</h3>
  <p class="desc"><strong>When to use:</strong> ${esc(s.description ?? '—')}</p>
  <p class="goal"><strong>Goal:</strong> ${esc(s.goal ?? '—')}</p>
  ${notes}
  <p class="meta">${esc(SKILLS_DIR)}/${esc(s.dir)}/SKILL.md${s.promptFile ? ` · ${esc(s.promptFile)}` : ''}</p>
</div>`;
}

function renderHtml(model) {
  const cards = model.skills.map(skillCard).join('\n');
  const empty = model.skills.length ? '' : '<p class="meta">No skills found under .claude/skills/.</p>';
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AAI Skills Catalog</title>
<style>
  :root { color-scheme: light dark; --fg: #1c1c1c; --bg: #ffffff; --muted: #6b6b6b; --line: #e3e3e3; --accent: #0b62d6; --card-bg: #fafafa; --note-bg: #fff4e0; }
  @media (prefers-color-scheme: dark) { :root { --fg: #e8e8e8; --bg: #161616; --muted: #9a9a9a; --line: #333; --accent: #6fb0ff; --card-bg: #1e1e1e; --note-bg: #3a2c10; } }
  body { margin: 0 auto; max-width: 68rem; padding: 2rem 1.25rem 4rem; font: 16px/1.55 system-ui, sans-serif; color: var(--fg); background: var(--bg); }
  h1 { font-size: 1.6rem; margin-bottom: .25rem; }
  h3 { margin: 0 0 .4rem; font-size: 1.05rem; }
  .meta { color: var(--muted); font-size: .8rem; }
  #search { width: 100%; box-sizing: border-box; font: inherit; padding: .6rem .8rem; margin: 1rem 0; border: 1px solid var(--line); border-radius: .5rem; background: var(--bg); color: var(--fg); }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(19rem, 1fr)); gap: 1rem; }
  .skill-card { border: 1px solid var(--line); border-radius: .6rem; padding: .9rem 1rem; background: var(--card-bg); }
  .skill-card.hidden { display: none; }
  .desc, .goal { font-size: .9rem; margin: .3rem 0; }
  .badge { font-size: .7rem; color: var(--muted); border: 1px solid var(--line); border-radius: 999px; padding: .05rem .5rem; margin-left: .4rem; }
  ul.notes { margin: .4rem 0; padding: .4rem .8rem; background: var(--note-bg); border-radius: .4rem; font-size: .8rem; list-style: none; }
  ul.notes li { margin: .15rem 0; }
  footer { margin-top: 2rem; color: var(--muted); font-size: .85rem; border-top: 1px solid var(--line); padding-top: .8rem; }
</style>
</head>
<body>
<h1>AAI Skills Catalog</h1>
<p class="meta">Regenerate with <code>node .aai/scripts/generate-docs-hub.mjs</code></p>
<input id="search" type="text" placeholder="Search skills by name, description, or goal…">
<div class="grid" id="grid">
${cards}
</div>
${empty}
<footer>${model.skillsCount} skills${model.degradedCount ? ` (${model.degradedCount} with extraction notes)` : ''} · source: .claude/skills/*/SKILL.md + .aai/SKILL_*.prompt.md</footer>
<script>
  document.getElementById('search').addEventListener('input', function (e) {
    var term = e.target.value.trim().toLowerCase();
    document.querySelectorAll('.skill-card').forEach(function (card) {
      var hit = term === '' || card.dataset.search.indexOf(term) !== -1;
      card.classList.toggle('hidden', !hit);
    });
  });
</script>
</body>
</html>
`;
}

function main() {
  const args = parseArgs(process.argv);
  const model = buildModel();
  const dataPath = path.join(ROOT, 'docs/skill-catalog-data.json');
  fs.writeFileSync(dataPath, `${JSON.stringify(model, null, 2)}\n`);
  console.log(`docs-hub: ${model.skillsCount} skills (${model.degradedCount} with extraction notes)`);
  if (!args.dataOnly) {
    const htmlPath = path.resolve(ROOT, args.outputPath);
    fs.writeFileSync(htmlPath, renderHtml(model));
    console.log(`- ${path.relative(ROOT, htmlPath)}`);
  }
  console.log(`- docs/skill-catalog-data.json`);
}

runMain(() => main());