#!/usr/bin/env node
// generate-overview.mjs — stakeholder-facing project overview generator.
//
// Renders docs/ai/overview.html (+ overview-data.json): a plain-language
// "what has been delivered / what is in progress / what waits on you" view,
// assembled deterministically from committed artifacts:
//   - docs/{issues,rfc,specs,requirements,releases}/*.md frontmatter
//   - docs/ai/EVENTS.jsonl        (close dates, lifecycle transitions)
//   - docs/ai/METRICS.jsonl       (agent effort per delivered item)
//   - docs/ai/reports|reviews     (evidence links per ref)
//   - docs/ai/STATE.yaml          (optional, local: focus/phase/blocked question)
//
// Unlike dashboard.html (operator telemetry), this page answers the
// non-technical question "what did the factory build and where does work
// stand?" and links every delivered item to its spec and evidence.
//
// Usage: node .aai/scripts/generate-overview.mjs [--output <html>] [--data-only]
// Read-only over inputs; writes only the two output files. No dependencies.

import fs from 'node:fs';
import path from 'node:path';
import { extractUsageTotal } from './lib/usage-note.mjs';

const ROOT = process.cwd();
const SCAN_DIRS = ['docs/issues', 'docs/rfc', 'docs/requirements', 'docs/releases'];
const SPEC_DIR = 'docs/specs';

function parseArgs(argv) {
  const args = { outputPath: 'docs/ai/overview.html', dataOnly: false };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--output' && argv[i + 1]) { args.outputPath = argv[i + 1]; i += 1; continue; }
    if (tok === '--data-only') { args.dataOnly = true; continue; }
    if (tok === '-h' || tok === '--help') {
      console.log('Usage: generate-overview.mjs [--output <html path>] [--data-only]');
      process.exit(0);
    }
  }
  return args;
}

function readFrontmatter(body) {
  const norm = body.replace(/\r\n?/g, '\n');
  const fm = norm.match(/^---\n([\s\S]*?)\n---/);
  const out = { id: null, type: null, status: null, title: null };
  if (fm) {
    for (const key of ['id', 'type', 'status', 'title']) {
      const m = fm[1].match(new RegExp(`^${key}:\\s*(.+?)\\s*$`, 'm'));
      if (m) out[key] = m[1].replace(/^["']|["']$/g, '');
    }
  }
  if (!out.title) {
    const h1 = norm.match(/^#\s+(.+)$/m);
    if (h1) out.title = h1[1].trim();
  }
  return out;
}

function scanDocs() {
  const docs = [];
  for (const dir of [...SCAN_DIRS, SPEC_DIR]) {
    const abs = path.join(ROOT, dir);
    let files = [];
    try { files = fs.readdirSync(abs).filter(f => f.endsWith('.md')).sort(); } catch { continue; }
    for (const fname of files) {
      if (fname === 'INDEX.md' || fname.startsWith('.')) continue;
      let body;
      try { body = fs.readFileSync(path.join(abs, fname), 'utf8'); } catch { continue; }
      const fm = readFrontmatter(body);
      docs.push({ ...fm, path: `${dir}/${fname}`, dir, file: fname });
    }
  }
  return docs;
}

function readJsonl(rel) {
  const abs = path.join(ROOT, rel);
  const rows = [];
  if (!fs.existsSync(abs)) return rows;
  for (const line of fs.readFileSync(abs, 'utf8').split(/\r?\n/)) {
    const t = line.trim();
    if (t === '' || t.startsWith('#')) continue;
    try { rows.push(JSON.parse(t)); } catch { /* skip bad line */ }
  }
  return rows;
}

// Minimal STATE probe (optional local file; absent on a fresh clone).
function readState() {
  const abs = path.join(ROOT, 'docs/ai/STATE.yaml');
  if (!fs.existsSync(abs)) return null;
  const raw = fs.readFileSync(abs, 'utf8');
  const scalar = (block, key) => {
    const m = raw.match(new RegExp(`^${block}:\\n(?:^ {2}.*\\n)*?^ {2}${key}:\\s*(.*)$`, 'm'));
    if (!m) return null;
    const v = m[1].trim();
    return v === '' || v === 'null' ? null : v.replace(/^["']|["']$/g, '');
  };
  return {
    focus_ref: scalar('current_focus', 'ref_id'),
    focus_type: scalar('current_focus', 'type'),
    human_required: scalar('human_input', 'required') === 'true',
    human_question: scalar('human_input', 'question'),
  };
}

// Evidence links: newest validation report / review file naming the ref.
function evidenceFor(ref, dir) {
  const abs = path.join(ROOT, dir);
  let files = [];
  try { files = fs.readdirSync(abs).filter(f => f.includes(ref)).sort(); } catch { return null; }
  return files.length ? `${dir}/${files[files.length - 1]}` : null;
}

function esc(s) {
  return String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

// readReleaseMembers(body) -> array of work-item ref strings from a release
// doc's ADDITIVE frontmatter `links.members` list (Spec-AC-05, token-economics
// end-to-end). Backward compatible: a release with no `members:` key (e.g.
// REL-0001) yields [] and every one of its items takes the close-month
// fallback path. Supports both inline (`members: [a, b]`) and block
// (`members:\n  - a\n  - b`) YAML list forms; line-discipline parse, no YAML
// library (docs/TECHNOLOGY.md), same house style as lib/pricing.mjs.
function readReleaseMembers(body) {
  const norm = body.replace(/\r\n?/g, '\n');
  const fm = norm.match(/^---\n([\s\S]*?)\n---/);
  if (!fm) return [];
  const lines = fm[1].split('\n');
  const linksIdx = lines.findIndex((l) => /^links:\s*$/.test(l));
  if (linksIdx === -1) return [];
  let membersIdx = -1;
  for (let i = linksIdx + 1; i < lines.length; i += 1) {
    if (/^\S/.test(lines[i])) break; // dedented out of the links: block
    if (/^ {2}members:/.test(lines[i])) { membersIdx = i; break; }
  }
  if (membersIdx === -1) return [];
  const inline = lines[membersIdx].match(/^ {2}members:\s*\[(.*)\]\s*$/);
  if (inline) {
    return inline[1].split(',').map((s) => s.trim().replace(/^["']|["']$/g, '')).filter(Boolean);
  }
  const members = [];
  for (let i = membersIdx + 1; i < lines.length; i += 1) {
    const m = lines[i].match(/^ {4}-\s*(.+?)\s*$/);
    if (!m) break;
    members.push(m[1].replace(/^["']|["']$/g, ''));
  }
  return members;
}

// tokensByRef(metrics) -> Map<ref_id, integer token total>, summing valid
// usage_total_tokens markers (extractUsageTotal, the SAME shared grammar
// metrics-flush/metrics-report use) across every run of every METRICS entry
// for that ref. A ref with NO valid marker anywhere is absent from the map
// (decorate() reads that absence as null — never a fabricated zero).
function tokensByRef(metrics) {
  const map = new Map();
  for (const m of metrics) {
    if (!m.ref_id) continue;
    let sum = 0;
    let any = false;
    for (const r of m.agent_runs ?? []) {
      const t = extractUsageTotal(r.note);
      if (t !== null) { sum += t; any = true; }
    }
    if (any) map.set(m.ref_id, (map.get(m.ref_id) ?? 0) + sum);
  }
  return map;
}

function buildModel() {
  const docs = scanDocs();
  const events = readJsonl('docs/ai/EVENTS.jsonl');
  const metrics = readJsonl('docs/ai/METRICS.jsonl');
  const state = readState();

  const closedAt = new Map();
  for (const e of events) {
    if (e.event === 'work_item_closed' && e.ref && e.ts) closedAt.set(e.ref, e.ts.slice(0, 10));
    if (e.event === 'doc_lifecycle' && e.payload && e.payload.to === 'done' && e.ref && e.ts
        && !closedAt.has(e.ref)) closedAt.set(e.ref, e.ts.slice(0, 10));
  }
  const effort = new Map();
  for (const m of metrics) {
    if (!m.ref_id) continue;
    const secs = (m.agent_runs ?? []).reduce((a, r) => a + (r.duration_seconds || 0), 0);
    effort.set(m.ref_id, (effort.get(m.ref_id) || 0) + secs);
  }
  const tokens = tokensByRef(metrics);
  const specs = docs.filter(d => d.dir === SPEC_DIR);
  const specsByRef = new Map();
  for (const d of specs) {
    // A spec's frontmatter id is usually the work-item slug/ref it serves.
    if (d.id) specsByRef.set(d.id, d.path);
  }
  // Fallback join: spec filenames carry the work-item slug
  // (SPEC-0041-spec-loop-ceremony-aware-dispatch.md serves loop-ceremony-aware-dispatch).
  const specByFilename = ref => {
    const hit = specs.find(d => d.file.includes(ref));
    return hit ? hit.path : null;
  };

  const items = docs.filter(d => d.dir !== SPEC_DIR && d.dir !== 'docs/releases');
  const decorate = d => {
    const ref = d.id ?? d.file.replace(/\.md$/, '');
    const closeKey = [...closedAt.keys()].find(k => k === d.id || d.file.startsWith(k) || k === d.file.replace(/\.md$/, ''));
    return {
      ref,
      title: d.title ?? d.file,
      type: d.type ?? d.dir.split('/')[1],
      status: d.status ?? 'unknown',
      path: d.path,
      closed_on: closeKey ? closedAt.get(closeKey) : null,
      agent_minutes: effort.has(ref) ? Math.round(effort.get(ref) / 60) : null,
      token_total: tokens.has(ref) ? tokens.get(ref) : null,
      spec: specsByRef.get(ref) ?? specByFilename(ref),
      validation: evidenceFor(ref, 'docs/ai/reports'),
      review: evidenceFor(ref, 'docs/ai/reviews'),
    };
  };

  const delivered = items.filter(d => d.status === 'done').map(decorate)
    .sort((a, b) => String(b.closed_on ?? '').localeCompare(String(a.closed_on ?? '')));
  const inProgress = items.filter(d => ['draft', 'implementing', 'in_progress'].includes(d.status)).map(decorate);
  const releaseDocs = docs.filter(d => d.dir === 'docs/releases');
  const releases = releaseDocs.map(decorate);

  // Spec-AC-05: group Delivered by release membership (additive frontmatter
  // links.members), close-month fallback for items no release names. Reads
  // each release doc's raw body again (scanDocs() keeps only parsed fields).
  const releaseMembership = new Map(); // ref -> {id, title, path}
  for (const d of releaseDocs) {
    let body;
    try { body = fs.readFileSync(path.join(ROOT, d.path), 'utf8'); } catch { continue; }
    for (const member of readReleaseMembers(body)) {
      if (!releaseMembership.has(member)) {
        releaseMembership.set(member, { id: d.id ?? d.file, title: d.title ?? d.id ?? d.file, path: d.path });
      }
    }
  }
  const groups = new Map(); // key -> {key, kind, label, ref, path, items}
  for (const d of delivered) {
    const rel = releaseMembership.get(d.ref);
    if (rel) {
      const key = `release:${rel.id}`;
      if (!groups.has(key)) groups.set(key, { key, kind: 'release', label: rel.title, ref: rel.id, path: rel.path, items: [] });
      groups.get(key).items.push(d);
    } else {
      const month = d.closed_on ? d.closed_on.slice(0, 7) : 'undated';
      const key = `month:${month}`;
      if (!groups.has(key)) groups.set(key, { key, kind: 'month', label: month === 'undated' ? 'Undated' : month, items: [] });
      groups.get(key).items.push(d);
    }
  }
  const releaseGroups = [...groups.values()].filter(g => g.kind === 'release').sort((a, b) => a.label.localeCompare(b.label));
  const monthGroups = [...groups.values()].filter(g => g.kind === 'month').sort((a, b) => b.label.localeCompare(a.label));
  const deliveredGroups = [...releaseGroups, ...monthGroups];

  const tokensTotal = delivered.reduce((a, d) => a + (d.token_total ?? 0), 0);

  return {
    generatedAt: new Date().toISOString(),
    project: path.basename(ROOT),
    counts: { delivered: delivered.length, in_progress: inProgress.length, releases: releases.length, tokens_total: tokensTotal },
    waiting_on_you: state && state.human_required
      ? { question: state.human_question, focus: state.focus_ref }
      : null,
    current_focus: state ? { ref: state.focus_ref, type: state.focus_type } : null,
    in_progress: inProgress,
    delivered,
    delivered_groups: deliveredGroups,
    releases,
  };
}

function itemCard(it) {
  const meta = [
    it.closed_on ? `delivered ${esc(it.closed_on)}` : null,
    it.agent_minutes != null ? `${it.agent_minutes} min agent time` : null,
    it.token_total != null ? `${it.token_total} tokens` : null,
    esc(it.type),
  ].filter(Boolean).join(' · ');
  const links = [
    ['request', it.path],
    ['spec', it.spec],
    ['validation evidence', it.validation],
    ['code review', it.review],
  ].filter(([, p]) => p)
    .map(([label, p]) => `<a href="../../${esc(p)}">${label}</a>`)
    .join(' · ');
  return `<li><strong>${esc(it.title)}</strong><br><span class="meta">${meta}</span><br><span class="links">${links}</span></li>`;
}

function renderHtml(model) {
  const waiting = model.waiting_on_you
    ? `<section class="alert"><h2>Waiting on you</h2><p>${esc(model.waiting_on_you.question ?? 'A decision is required.')}${model.waiting_on_you.focus ? ` <span class="meta">(scope: ${esc(model.waiting_on_you.focus)})</span>` : ''}</p></section>`
    : '';
  const inProg = model.in_progress.length
    ? `<section><h2>In progress (${model.in_progress.length})</h2><ul>${model.in_progress.map(itemCard).join('\n')}</ul></section>`
    : '<section><h2>In progress</h2><p class="meta">Nothing in flight.</p></section>';
  const delivered = model.delivered.length
    ? `<section><h2>Delivered (${model.delivered.length})</h2>${model.delivered_groups.map(g => `<h3>${esc(g.label)}</h3><ul>${g.items.map(itemCard).join('\n')}</ul>`).join('\n')}</section>`
    : '<section><h2>Delivered</h2><p class="meta">Nothing delivered yet.</p></section>';
  const releases = model.releases.length
    ? `<section><h2>Releases</h2><ul>${model.releases.map(itemCard).join('\n')}</ul></section>`
    : '';
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(model.project)} — Project Overview</title>
<style>
  :root { color-scheme: light dark; --fg: #1c1c1c; --bg: #ffffff; --muted: #6b6b6b; --line: #e3e3e3; --accent: #0b62d6; --alert-bg: #fff4e0; }
  @media (prefers-color-scheme: dark) { :root { --fg: #e8e8e8; --bg: #161616; --muted: #9a9a9a; --line: #333; --accent: #6fb0ff; --alert-bg: #3a2c10; } }
  body { margin: 0 auto; max-width: 60rem; padding: 2rem 1.25rem 4rem; font: 16px/1.55 system-ui, sans-serif; color: var(--fg); background: var(--bg); }
  h1 { font-size: 1.6rem; margin-bottom: .25rem; }
  h2 { font-size: 1.15rem; border-bottom: 1px solid var(--line); padding-bottom: .3rem; margin-top: 2rem; }
  .meta { color: var(--muted); font-size: .85rem; }
  .counts { display: flex; gap: 1.5rem; margin: 1rem 0; flex-wrap: wrap; }
  .counts div { border: 1px solid var(--line); border-radius: .5rem; padding: .6rem 1.1rem; }
  .counts b { font-size: 1.4rem; display: block; }
  ul { list-style: none; padding: 0; }
  li { border: 1px solid var(--line); border-radius: .5rem; padding: .7rem .9rem; margin: .5rem 0; }
  a { color: var(--accent); text-decoration: none; }
  a:hover { text-decoration: underline; }
  .links { font-size: .85rem; }
  .alert { background: var(--alert-bg); border-radius: .5rem; padding: .2rem 1rem .8rem; margin-top: 1.5rem; }
</style>
</head>
<body>
<h1>${esc(model.project)} — Project Overview</h1>
<p class="meta">Generated ${esc(model.generatedAt)} · regenerate with <code>node .aai/scripts/generate-overview.mjs</code></p>
<div class="counts">
  <div><b>${model.counts.delivered}</b>delivered</div>
  <div><b>${model.counts.in_progress}</b>in progress</div>
  <div><b>${model.counts.releases}</b>releases</div>
  <div><b>${model.counts.tokens_total}</b>agent tokens (delivered)</div>
</div>
${waiting}
${inProg}
${delivered}
${releases}
</body>
</html>
`;
}

function main() {
  const args = parseArgs(process.argv);
  const model = buildModel();
  const dataPath = path.join(ROOT, 'docs/ai/overview-data.json');
  fs.writeFileSync(dataPath, `${JSON.stringify(model, null, 2)}\n`);
  if (!args.dataOnly) {
    const htmlPath = path.resolve(ROOT, args.outputPath);
    fs.writeFileSync(htmlPath, renderHtml(model));
    console.log(`overview: ${model.counts.delivered} delivered, ${model.counts.in_progress} in progress`);
    console.log(`- ${path.relative(ROOT, htmlPath)}`);
  }
  console.log(`- docs/ai/overview-data.json`);
}

main();
