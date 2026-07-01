// Shared doc-model parsers for the RFC-0001 docs layer (SPEC-0001 / RFC-0002).
// Consumed by generate-docs-index.mjs and docs-audit.mjs. No side effects.

import fs from 'node:fs';
import path from 'node:path';

// ISSUE-0001 / SPEC-0007 — normalize line endings ONCE at parser entry so every
// `\n`-splitting parser behaves identically for LF, CRLF (Windows / core.autocrlf),
// and lone-CR (classic-Mac) checkouts. CRLF first, then any remaining lone CR.
// Files on disk are never mutated — only the in-memory working copy is normalized.
export function normalizeNewlines(content) {
  return String(content).replace(/\r\n/g, '\n').replace(/\r/g, '\n');
}

// SPEC-0007 WARNING-1 — convert any filesystem path to POSIX forward-slash form.
// Splits on BOTH separator types so the helper is testable on any OS with a
// literal-backslash input (not just path.sep), making Windows bugs unit-catchable
// on macOS/Linux. No-op on POSIX (path.sep === '/').
export function toPosix(p) {
  return String(p).split(/[\\/]/).join('/');
}

export const DOC_STATUS_ENUM = new Set([
  'draft', 'proposed', 'accepted', 'implementing', 'frozen',
  'done', 'deferred', 'rejected', 'superseded', 'legacy',
]);
export const AC_STATUS_ENUM = new Set([
  'planned', 'implementing', 'done', 'deferred', 'blocked', 'rejected',
]);
export const TERMINAL_AC = new Set(['done', 'deferred', 'blocked', 'rejected']);

// SPEC-0010 Group C (ISSUE-0005) — shared AC-status normalizer consumed by BOTH
// generate-docs-index.mjs AND docs-audit-core.mjs so the two engines never drift
// on which AC statuses are accepted/terminal. Returns { status, qualifier,
// canonical }:
//   - bare canonical enum member (e.g. "done")            -> { status:'done', qualifier:null, canonical:true }
//   - "<canonical> (<qualifier>)" (e.g. "done (pre-existing)")
//                                                          -> { status:'done', qualifier:'pre-existing', canonical:true }
//   - anything else (e.g. "finished", "donee", "done ()", "done (a) (b)")
//                                                          -> { status:<lowered raw>, qualifier:null, canonical:false }
// Narrow by construction: the leading token MUST be a canonical AC_STATUS_ENUM
// member and there MUST be exactly ONE non-empty trailing parenthetical with no
// nested parentheses. Base status drives placement, progress, and drift terminal
// classification; the qualifier is preserved (never silently dropped).
export function normalizeAcStatus(raw) {
  const value = String(raw ?? '').trim().toLowerCase();
  const m = value.match(/^([a-z][a-z-]*)\s*\((.+)\)$/);
  if (m) {
    const token = m[1].trim();
    const qualifier = m[2].trim();
    if (AC_STATUS_ENUM.has(token) && qualifier !== ''
        && !qualifier.includes('(') && !qualifier.includes(')')) {
      return { status: token, qualifier, canonical: true };
    }
    return { status: value, qualifier: null, canonical: false };
  }
  if (AC_STATUS_ENUM.has(value)) return { status: value, qualifier: null, canonical: true };
  return { status: value, qualifier: null, canonical: false };
}
export const DOC_TYPE_ENUM = new Set([
  'issue', 'change', 'prd', 'decision', 'spec', 'rfc', 'techdebt',
  'plan', 'release', 'research', 'requirement',
  // RFC-0003 / SPEC-0002: canonicalization layer
  'canonical', 'archived',
]);

// RFC-0003 / SPEC-0002 — fixed hybrid layer sections, in order. The canonical
// synthesizer must emit exactly these five level-2 headings in this order, and
// any content classified `superseded` belongs only under the last one.
export const CANONICAL_SECTIONS = [
  'Overview / Intent',
  'UI',
  'Processes / Behavior',
  'Data model',
  'Superseded decisions',
];

// A domain slug is lowercased, starts alnum, then alnum/hyphen (RFC-0003 step 7).
export const DOMAIN_SLUG_RE = /^[a-z0-9][a-z0-9-]*$/;

// Doc IDs in filenames: PREFIX-DIGITS plus compound forms with letter
// segments between prefix and number (SPEC-CHANGE-027, DECISION-RFC-002,
// SPEC-PROC-10, DECISION-SPEC-FE-13). The lookahead stops half-matches
// like SPEC-001abc (CHANGE-0001 D1).
export const DOC_ID_RE = /^([A-Z]+(?:-[A-Z]+)*-\d{1,5}(?:-\d+)?)(?=[-.])/;

// Review-By accepts ISO dates, skill literals, <label>:<date> combos
// (CHANGE-0001 D4), or "<actor> <method>" composition where the actor is a
// Claude model id or human/operator identity (CHANGE-0002 D10). Only dated
// forms feed overdue checks. A bare actor without a method is invalid —
// the method is what asserts the AC was validated.
export const REVIEW_BY_LABELS = new Set(['tdd', 'loop', 'code-review', 'manual', 'deferred']);
export const REVIEW_BY_METHODS = new Set([
  ...REVIEW_BY_LABELS, 'playwrightsuites', 'validation', 'tdd-snapshot-scripts',
]);
const REVIEW_BY_ACTOR_RE = /^(?:claude-(?:sonnet|opus|haiku|fable)-\d+(?:-\d+)?|(?:human|operator)(?::[\w.-]+)?)$/i;

function parseMethodToken(token, methods) {
  const combo = token.match(/^([A-Za-z][\w-]*):(\d{4}-\d{2}-\d{2})$/);
  if (combo && methods.has(combo[1].toLowerCase())) {
    const d = parseISODate(combo[2]);
    if (d instanceof Date) return { date: d, label: combo[1] };
    return null;
  }
  if (methods.has(token.toLowerCase())) return { date: null, label: token };
  return null;
}

export function parseReviewBy(s, extraMethods = []) {
  if (!s || s === '—' || s === '-') return { kind: 'none', date: null, label: null, actor: null };
  const raw = String(s).trim();
  const methods = extraMethods.length
    ? new Set([...REVIEW_BY_METHODS, ...extraMethods.map(m => String(m).toLowerCase())])
    : REVIEW_BY_METHODS;

  const tokens = raw.split(/\s+/);
  if (tokens.length === 2 && REVIEW_BY_ACTOR_RE.test(tokens[0])) {
    const method = parseMethodToken(tokens[1], methods);
    if (method) return { kind: 'actor-method', date: method.date, label: method.label, actor: tokens[0] };
    return { kind: 'invalid', date: null, label: null, actor: null, raw };
  }
  if (tokens.length > 1) return { kind: 'invalid', date: null, label: null, actor: null, raw };

  // single-token forms (CHANGE-0001 D4): bare labels stay on the narrow
  // whitelist; combos accept extended methods
  const combo = raw.match(/^([A-Za-z][\w-]*):(\d{4}-\d{2}-\d{2})$/);
  if (combo && methods.has(combo[1].toLowerCase())) {
    const d = parseISODate(combo[2]);
    if (d instanceof Date) return { kind: 'combo', date: d, label: combo[1], actor: null };
    return { kind: 'invalid', date: null, label: null, actor: null, raw };
  }
  if (REVIEW_BY_LABELS.has(raw.toLowerCase())) return { kind: 'label', date: null, label: raw, actor: null };
  const d = parseISODate(raw);
  if (d instanceof Date) return { kind: 'date', date: d, label: null, actor: null };
  return { kind: 'invalid', date: null, label: null, actor: null, raw };
}

// Filename ID extraction (CHANGE-0002 D14/D15). Returns the primary ID,
// related IDs encoded in the same filename (numeric siblings like
// PRD-022-024-025, embedded shapes like PRD-022-TEST-021-...), and a scope
// when the segment after the type prefix is a category (PHASE-0 etc.) —
// category-scoped files get the full filename slug as their unique ID.
export const DEFAULT_CATEGORY_PREFIXES = ['PHASE', 'MILESTONE', 'EPIC'];

export function extractDocIds(fileName, categoryPrefixes = DEFAULT_CATEGORY_PREFIXES) {
  const name = fileName.replace(/\.md$/i, '');
  const m = name.match(/^([A-Z]+(?:-[A-Z]+)*)-(\d{1,5})(?=-|$)/);
  if (!m) return null;
  const prefixSegs = m[1].split('-');
  const lastSeg = prefixSegs[prefixSegs.length - 1];
  if (prefixSegs.length >= 2 && categoryPrefixes.includes(lastSeg)) {
    return { primary: name, related: [], scope: `${lastSeg}-${m[2]}` };
  }
  const primary = `${m[1]}-${m[2]}`;
  const related = [];
  let rest = name.slice(primary.length);
  let sib;
  while ((sib = rest.match(/^-(\d{1,5})(?=-|$)/))) {
    related.push(`${m[1]}-${sib[1]}`);
    rest = rest.slice(sib[0].length);
  }
  for (const g of rest.matchAll(/(?:^|-)([A-Z]+(?:-[A-Z]+)*-\d{1,5})(?=-|$)/g)) {
    related.push(g[1]);
  }
  return { primary, related, scope: null };
}

// Legacy body freeze marker tolerance (CHANGE-0001 D2). Matches the forms
// seen in real projects: "SPEC-FROZEN: true", "**SPEC-FROZEN:** true",
// "**SPEC-FROZEN**: true", "📋 SPEC-FROZEN: true". Upstream templates
// dropped the marker in RFC-0001; this exists only for legacy docs.
const SPEC_FROZEN_TRUE_RE = /SPEC-FROZEN\s*(?::\s*(?:\*\*)?|\*\*\s*:)\s*true\b/i;

export function specFrozenInBody(content) {
  return SPEC_FROZEN_TRUE_RE.test(content);
}

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
  content = normalizeNewlines(content);
  if (!content.startsWith('---\n')) return null;
  const end = content.indexOf('\n---', 4);
  if (end < 0) return null;
  const block = content.slice(4, end);
  const fm = {};
  let currentKey = null;
  let nested = null;
  let list = null;
  for (const rawLine of block.split('\n')) {
    if (!rawLine.trim() || rawLine.trim().startsWith('#')) continue;
    if (rawLine.startsWith('  ')) {
      if (currentKey == null) continue;
      // YAML block list item: "  - value" (RFC-0003 sources:, links lists).
      const li = rawLine.trim().match(/^-\s*(.*)$/);
      if (li) {
        if (list == null) { list = []; fm[currentKey] = list; nested = null; }
        const item = li[1].trim();
        if (item !== '') list.push(item.replace(/^["']|["']$/g, ''));
        continue;
      }
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
    list = null;
    const m = rawLine.match(/^([a-zA-Z_][\w-]*):\s*(.*)$/);
    if (!m) continue;
    const v = m[2].trim();
    currentKey = m[1];
    if (v === '') fm[currentKey] = null;
    else if (v === '[]') fm[currentKey] = [];
    else if (v === 'null') fm[currentKey] = null;
    else if (v.startsWith('[') && v.endsWith(']')) {
      fm[currentKey] = v.slice(1, -1).split(',').map(s => s.trim().replace(/^["']|["']$/g, '')).filter(Boolean);
    } else fm[currentKey] = v.replace(/^["']|["']$/g, '');
  }
  return fm;
}

export function parseAcTable(content) {
  // SPEC-0007 — normalize once at entry so the `.split('\n')` row scan below
  // yields identical cells for LF / CRLF / lone-CR (and no value carries \r).
  content = normalizeNewlines(content);
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
  for (const m of String(notes).matchAll(/→\s*([A-Z]+(?:-[A-Z]+)*-\d{1,5})\b/g)) refs.push(m[1]);
  return refs;
}

// --- RFC-0003 / SPEC-0002 canonicalization schema ---------------------------

// Normalize a frontmatter value that should be a list into a string array.
// Tolerates a single scalar, an inline [a, b] form, or an already-parsed array.
export function asList(value) {
  if (value == null) return [];
  if (Array.isArray(value)) return value.map(v => String(v).trim()).filter(Boolean);
  const s = String(value).trim();
  if (s === '' || s === '[]') return [];
  if (s.startsWith('[') && s.endsWith(']')) {
    return s.slice(1, -1).split(',').map(x => x.trim().replace(/^["']|["']$/g, '')).filter(Boolean);
  }
  return [s];
}

// Validate the frontmatter of a `type: canonical` doc (Spec-AC-02).
// Returns { ok, violations: [string] }. A canonical doc requires:
//   - type === 'canonical'
//   - domain: non-empty, matches DOMAIN_SLUG_RE (lowercased slug)
//   - sources: a non-empty list of contributing original doc paths
export function validateCanonicalFrontmatter(fm) {
  const violations = [];
  if (!fm) return { ok: false, violations: ['no frontmatter'] };
  if (String(fm.type ?? '').toLowerCase() !== 'canonical') {
    violations.push(`type must be "canonical" (got "${fm.type ?? ''}")`);
  }
  const domain = fm.domain == null ? '' : String(fm.domain).trim();
  if (domain === '') {
    violations.push('missing domain');
  } else if (!DOMAIN_SLUG_RE.test(domain)) {
    violations.push(`bad domain slug "${domain}" (must match ${DOMAIN_SLUG_RE})`);
  }
  const sources = asList(fm.sources);
  if (sources.length === 0) violations.push('empty sources list');
  return { ok: violations.length === 0, violations };
}

// Note: archived-doc frontmatter integrity (status: archived + a resolving
// canonical: pointer) is enforced by checkLinkIntegrity in docs-canon-core.mjs,
// which walks the docs/_archive/ tree directly. Archived docs are intentionally
// excluded from the docs-audit scan (EXCLUDE_DIRS), so no separate
// validate-on-scan helper is needed here.

// Validate that the body contains exactly the five fixed layer sections as
// level-2 headings, in order (Spec-AC-06). Returns { ok, violations }.
export function validateSectionContract(content) {
  const violations = [];
  const headings = [];
  for (const m of content.matchAll(/^##\s+(.+?)\s*$/gm)) headings.push(m[1].trim());
  let idx = 0;
  for (const want of CANONICAL_SECTIONS) {
    const at = headings.indexOf(want, idx);
    if (at < 0) {
      violations.push(`missing or out-of-order section "## ${want}"`);
      // continue checking remaining sections from current idx to report all gaps
    } else {
      idx = at + 1;
    }
  }
  return { ok: violations.length === 0, violations };
}
