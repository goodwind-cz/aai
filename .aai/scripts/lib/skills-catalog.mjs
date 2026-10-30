// skills-catalog.mjs — SKILLS.md Quick Reference drift check and row generator
// (SPEC spec-provider-adapter-surfaces-closing-slice D1, D2; RFC-0017 phase 4).
//
// Opt-in: sync-harness-skills.mjs calls this only when HARNESS_SKILLS.yaml has
// a `catalog:` section with exactly one row `<file>|<heading>`. The skill set
// is the generator's own source set (.claude/skills/*), so the catalog cannot
// read a different source than the mirrors. A Quick Reference row is a table
// line whose first cell is a skill name; the section ends at the next `## `
// heading. Existing rows are never compared or rewritten; --write only removes
// orphan rows and appends one generated row per missing skill (codepoint order).
// Node stdlib only.

import fs from 'node:fs';
import path from 'node:path';

export class CatalogError extends Error {}

const NAME_RE = /^[a-z0-9][a-z0-9-]*$/;

export function loadCatalog(rows) {
  if (rows === null) return null;
  const parts = rows.length === 1 ? rows[0].split('|') : [];
  const [file, heading] = parts.map((p) => p.trim());
  if (parts.length !== 2 || !file || !heading
      || path.isAbsolute(file) || file.split('/').includes('..')) {
    throw new CatalogError('catalog section wants exactly one row <file>|<heading>');
  }
  return { file, heading };
}

function codexCell(root, name, body) {
  const key = name.replace(/^aai-/, '').toUpperCase().replace(/-/g, '_');
  if (fs.existsSync(path.join(root, `.aai/SKILL_${key}.prompt.md`))) return `\`--prompt-file .aai/SKILL_${key}.prompt.md\``;
  const cmd = /`(node \.aai\/scripts\/[A-Za-z0-9._-]+\.mjs)`/.exec(body);
  if (cmd) return `\`${cmd[1]}\``;
  throw new CatalogError(`catalog row for ${name} cannot be generated: no prompt file and no node command in the wrapper`);
}

// plan: read the catalog file, compare, and (always) return what --write would do.
export function planCatalog(root, cat, skills) {
  const abs = path.join(root, cat.file);
  let st;
  try { st = fs.lstatSync(abs); } catch { throw new CatalogError(`catalog file is absent: ${cat.file}`); }
  if (st.isSymbolicLink() || !st.isFile()) throw new CatalogError(`catalog file must be a regular file, not a symlink: ${cat.file}`);
  const raw = fs.readFileSync(abs, 'utf8');
  // Every line keeps its own terminator (a file may mix LF and CRLF); matching sees the text only.
  const pieces = raw.split(/(?<=\n)/);
  const lines = pieces.map((l) => l.replace(/\r?\n$/, ''));
  const start = lines.findIndex((l) => l === cat.heading);
  if (start === -1) throw new CatalogError(`catalog heading ${cat.heading} is absent from ${cat.file}`);
  let end = lines.findIndex((l, i) => i > start && l.startsWith('## '));
  if (end === -1) end = lines.length;
  const listed = new Map();
  let lastRow = -1;
  for (let i = start + 1; i < end; i++) {
    if (!lines[i].startsWith('|')) continue;
    lastRow = i;
    const cell = lines[i].split('|')[1].trim();
    if (NAME_RE.test(cell)) listed.set(cell, i);
  }
  const missing = [...skills.keys()].filter((n) => !listed.has(n)).sort();
  const orphans = [...listed.keys()].filter((n) => !skills.has(n)).sort();
  const drift = [...missing.map((n) => [n, `missing row ${n}`]), ...orphans.map((n) => [n, `orphan row ${n}`])]
    .sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
    .map((d) => `DIVERGE catalog ${cat.file}: ${d[1]}`);
  const ok = `OK: ${skills.size} skill(s) listed in the ${cat.file} Quick Reference`;
  const render = () => {
    const add = missing.map((n) => {
      const s = skills.get(n);
      if (s.description.includes('|')) throw new CatalogError(`catalog row for ${n} refused: description contains a pipe character`);
      return `| ${n} | ${s.description} | \`/${n}\` | ${codexCell(root, n, s.body)} |`;
    });
    const drop = new Set(orphans.map((n) => listed.get(n)));
    const at = lastRow === -1 ? start : lastRow;
    const eol = /\r\n$/.test(pieces[at]) ? '\r\n' : '\n';
    const out = [];
    pieces.forEach((l, i) => {
      if (!drop.has(i)) out.push(l);
      if (i === at && add.length) {
        if (!/\n$/.test(l)) out.push(eol);
        out.push(...add.map((r) => r + eol));
      }
    });
    return out.join('');
  };
  return { drift, ok, changed: missing.length + orphans.length, abs, render };
}

export function writeCatalog(plan, text) {
  if (text !== null) fs.writeFileSync(plan.abs, text);
  return plan.changed;
}
