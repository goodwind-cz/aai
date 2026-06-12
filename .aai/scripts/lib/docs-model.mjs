// Shared doc-model parsers for the RFC-0001 docs layer (SPEC-0001 / RFC-0002).
// Consumed by generate-docs-index.mjs and docs-audit.mjs. No side effects.

import fs from 'node:fs';
import path from 'node:path';

export const DOC_STATUS_ENUM = new Set([
  'draft', 'proposed', 'accepted', 'implementing', 'frozen',
  'done', 'deferred', 'rejected', 'superseded', 'legacy',
]);
export const AC_STATUS_ENUM = new Set([
  'planned', 'implementing', 'done', 'deferred', 'blocked', 'rejected',
]);
export const TERMINAL_AC = new Set(['done', 'deferred', 'blocked', 'rejected']);

export function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.isFile() && entry.name.endsWith('.md') && entry.name !== 'INDEX.md' && entry.name !== '.gitkeep') {
      out.push(full);
    }
  }
  return out;
}

export function parseFrontmatter(content) {
  if (!content.startsWith('---\n')) return null;
  const end = content.indexOf('\n---', 4);
  if (end < 0) return null;
  const block = content.slice(4, end);
  const fm = {};
  let currentKey = null;
  let nested = null;
  for (const rawLine of block.split('\n')) {
    if (!rawLine.trim() || rawLine.trim().startsWith('#')) continue;
    if (rawLine.startsWith('  ')) {
      if (currentKey == null) continue;
      if (nested == null) { nested = {}; fm[currentKey] = nested; }
      const m = rawLine.trim().match(/^([a-zA-Z_][\w-]*):\s*(.*)$/);
      if (m) {
        const v = m[2].trim();
        if (v === '' || v === '[]') nested[m[1]] = (v === '[]') ? [] : null;
        else if (v === 'null') nested[m[1]] = null;
        else nested[m[1]] = v.replace(/^["']|["']$/g, '');
      }
      continue;
    }
    nested = null;
    const m = rawLine.match(/^([a-zA-Z_][\w-]*):\s*(.*)$/);
    if (!m) continue;
    const v = m[2].trim();
    currentKey = m[1];
    if (v === '') fm[currentKey] = null;
    else if (v === '[]') fm[currentKey] = [];
    else if (v === 'null') fm[currentKey] = null;
    else fm[currentKey] = v.replace(/^["']|["']$/g, '');
  }
  return fm;
}

export function parseAcTable(content) {
  // Find "## Acceptance Criteria Status" section, then the first markdown table.
  const sectionRe = /##\s+Acceptance Criteria Status\b[^\n]*\n([\s\S]+?)(?=\n##\s|\n*$)/i;
  const m = content.match(sectionRe);
  if (!m) return { hasGate: false, rows: [] };
  const section = m[1];
  const lines = section.split('\n').filter(l => l.trim().startsWith('|'));
  if (lines.length < 2) return { hasGate: false, rows: [] };
  const header = lines[0].split('|').map(c => c.trim()).filter(Boolean);
  const hasGate = header.some(c => c === 'Review-By');
  if (!hasGate) return { hasGate: false, rows: [] };
  const sepIdx = lines.findIndex((l, i) => i > 0 && /^\|\s*[-:|\s]+\|/.test(l));
  if (sepIdx < 0) return { hasGate: true, rows: [] };
  const rows = [];
  for (const line of lines.slice(sepIdx + 1)) {
    const cells = line.split('|').map(c => c.trim()).slice(1, -1);
    if (cells.length !== header.length) continue;
    const row = {};
    header.forEach((h, i) => { row[h] = cells[i]; });
    if (!row['Spec-AC'] || row['Spec-AC'].startsWith('Spec-AC-xx') || row['Spec-AC'].startsWith('<')) continue;
    rows.push(row);
  }
  return { hasGate: true, rows };
}

export function parseISODate(s) {
  if (!s || s === '—' || s === '-') return null;
  const m = String(s).trim().match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) return { invalid: true, raw: s };
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  if (Number.isNaN(d.getTime())) return { invalid: true, raw: s };
  return d;
}

export function extractReferences(notes) {
  if (!notes) return [];
  const refs = [];
  for (const m of String(notes).matchAll(/→\s*([A-Z]+-\d{3,5})\b/g)) refs.push(m[1]);
  return refs;
}
