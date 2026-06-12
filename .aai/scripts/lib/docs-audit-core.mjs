// Docs hygiene & drift audit core (RFC-0002 / SPEC-0001).
// Pure analysis: classifies every prefixed doc under docs/ and derives drift
// verdicts. REPORTS only — never writes to any doc, plan, or backlog file.

import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import {
  DOC_STATUS_ENUM, AC_STATUS_ENUM, TERMINAL_AC,
  parseFrontmatter, parseAcTable, parseISODate,
} from './docs-model.mjs';

export const CONFIG_PATH = 'docs/ai/docs-audit.yaml';
export const EVENTS_PATH = 'docs/ai/EVENTS.jsonl';
const SCAN_ROOT = 'docs';
const EXCLUDE_DIRS = new Set(['ai', 'knowledge', 'archive', 'project-sessions', 'templates']);
const ID_FILE_RE = /^([A-Z]+-\d{3,5})(?:-|\.md$)/;
const OPEN_STATUSES = new Set(['draft', 'implementing']);
const DEFAULT_STALE_DAYS = 90;

// --- config -----------------------------------------------------------------

export function loadConfig(root) {
  const p = path.join(root, CONFIG_PATH);
  if (!fs.existsSync(p)) return null;
  const cfg = { legacy_until_date: null, stale_after_days: DEFAULT_STALE_DAYS, scan_exclude: [], backlog_globs: [] };
  let listKey = null;
  for (const raw of fs.readFileSync(p, 'utf8').split('\n')) {
    const line = raw.replace(/#.*$/, '').trimEnd();
    if (!line.trim()) continue;
    const item = line.match(/^\s+-\s+(.*)$/);
    if (item && listKey) { cfg[listKey].push(item[1].trim().replace(/^["']|["']$/g, '')); continue; }
    const kv = line.match(/^([a-zA-Z_]+):\s*(.*)$/);
    if (!kv) continue;
    const [, key, rawVal] = kv;
    const val = rawVal.trim();
    if (key === 'scan_exclude' || key === 'backlog_globs') {
      listKey = key;
      if (val && val !== '[]') {
        cfg[key] = val.replace(/^\[|\]$/g, '').split(',').map(s => s.trim().replace(/^["']|["']$/g, '')).filter(Boolean);
        listKey = null;
      }
      continue;
    }
    listKey = null;
    if (key === 'legacy_until_date') cfg.legacy_until_date = val || null;
    else if (key === 'stale_after_days') cfg.stale_after_days = Number(val) || DEFAULT_STALE_DAYS;
  }
  return cfg;
}

// --- git probes (skipped in quick mode) --------------------------------------

function git(root, cmd) {
  try {
    return execSync(`git ${cmd}`, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return null;
  }
}

export function firstCommitDate(root, rel) {
  const out = git(root, `log --diff-filter=A --follow --format=%cs -- "${rel}"`);
  if (!out) return null;
  const lines = out.split('\n').filter(Boolean);
  return lines.length ? lines[lines.length - 1] : null;
}

function lastEditDate(root, rel) {
  return git(root, `log -1 --format=%cs -- "${rel}"`) || null;
}

function lastIdMentionDate(root, id) {
  return git(root, `log -1 --grep="${id}" --format=%cs`) || null;
}

// --- events -----------------------------------------------------------------

export function readEvents(root) {
  const p = path.join(root, EVENTS_PATH);
  if (!fs.existsSync(p)) return [];
  const events = [];
  for (const line of fs.readFileSync(p, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    try { events.push(JSON.parse(line)); } catch { /* tolerate partial lines */ }
  }
  return events;
}

// --- scan -------------------------------------------------------------------

export function scanAuditDocs(root, { scopePath = null, scanExclude = [] } = {}) {
  const found = [];
  const base = path.join(root, SCAN_ROOT);
  const visit = (dir, depth) => {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (depth === 0 && entry.isDirectory() && EXCLUDE_DIRS.has(entry.name)) continue;
      const full = path.join(dir, entry.name);
      const rel = path.relative(root, full);
      if (scanExclude.some(g => rel === g || rel.startsWith(g.replace(/\/+$/, '') + '/'))) continue;
      if (entry.isDirectory()) { visit(full, depth + 1); continue; }
      if (!entry.name.endsWith('.md') || entry.name === 'INDEX.md') continue;
      const m = entry.name.match(ID_FILE_RE);
      if (!m) continue;
      if (scopePath) {
        const scope = path.relative(root, path.resolve(root, scopePath));
        if (rel !== scope && !rel.startsWith(scope.replace(/\/+$/, '') + '/')) continue;
      }
      found.push({ rel, fileId: m[1] });
    }
  };
  visit(base, 0);
  return found.sort((a, b) => a.rel.localeCompare(b.rel));
}

// --- backlog cross-check (read-only) -----------------------------------------

function backlogDoneClaims(root, globs, knownIds) {
  const claims = new Set();
  for (const g of globs) {
    const p = path.join(root, g);
    if (!fs.existsSync(p) || !fs.statSync(p).isFile()) continue;
    for (const line of fs.readFileSync(p, 'utf8').split('\n')) {
      if (!/✅|\bDone\b/i.test(line)) continue;
      for (const id of knownIds) {
        if (line.includes(id)) claims.add(id);
      }
    }
  }
  return claims;
}

// --- classification + drift ---------------------------------------------------

function daysBetween(fromYmd, toDate) {
  const d = parseISODate(fromYmd);
  if (!d || d.invalid) return null;
  return Math.floor((toDate.getTime() - d.getTime()) / 86400000);
}

function rowHasEvidence(row) {
  const e = (row['Evidence'] ?? '').trim();
  return e !== '' && e !== '—' && e !== '-';
}

export function runAudit(root, { quick = false, scopePath = null, today = new Date(), strict = false } = {}) {
  const config = loadConfig(root);
  const mode = quick ? 'quick' : ((config || strict) ? 'enforced' : 'report-only');
  const staleDays = config?.stale_after_days ?? DEFAULT_STALE_DAYS;
  const legacyUntil = config?.legacy_until_date ?? null;
  const todayUTC = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));

  const files = scanAuditDocs(root, { scopePath, scanExclude: config?.scan_exclude ?? [] });
  const events = quick ? [] : readEvents(root);
  const docs = [];
  const violations = [];

  for (const f of files) {
    const content = fs.readFileSync(path.join(root, f.rel), 'utf8');
    const fm = parseFrontmatter(content);
    const ac = parseAcTable(content);
    const id = fm?.id ?? f.fileId;
    const doc = { rel: f.rel, id, fm, ac, cls: null, verdict: null, reasons: [], legacy: false };
    docs.push(doc);

    // legacy/new split (D4): first-commit date vs legacy_until_date; untracked => new
    if (!quick && legacyUntil) {
      const first = firstCommitDate(root, f.rel);
      doc.firstCommit = first;
      doc.legacy = first != null && first < legacyUntil;
    } else if (quick || !legacyUntil) {
      // report-only / quick: nothing hard-fails; strict (intake post-save
      // check) treats every doc as new even without a config
      doc.legacy = !strict;
      doc.softLegacy = !strict;
    }

    if (!fm || !fm.id || !fm.status) {
      doc.cls = 'orphan';
      doc.reasons.push(!fm ? 'no frontmatter' : `missing ${!fm.id ? 'id' : 'status'} in frontmatter`);
      continue;
    }
    const status = String(fm.status).toLowerCase();
    if (!DOC_STATUS_ENUM.has(status)) {
      doc.cls = 'orphan';
      doc.reasons.push(`unknown status "${fm.status}"`);
      violations.push({ rel: f.rel, msg: `unknown frontmatter status "${fm.status}"` });
      continue;
    }
    for (const row of ac.rows) {
      const s = (row['Status'] ?? '').toLowerCase();
      if (s && !AC_STATUS_ENUM.has(s)) violations.push({ rel: f.rel, msg: `unknown AC status "${row['Status']}" for ${row['Spec-AC']}` });
    }
    doc.status = status;

    if (status === 'superseded' || status === 'rejected') { doc.cls = 'superseded'; continue; }

    // drift heuristics (deliverable 2)
    const type = (fm.type ?? '').toLowerCase();
    if (status === 'done') {
      const nonTerminal = ac.rows.filter(r => !TERMINAL_AC.has((r['Status'] ?? '').toLowerCase()));
      const doneNoEvidence = ac.rows.filter(r => (r['Status'] ?? '').toLowerCase() === 'done' && !rowHasEvidence(r));
      if (ac.hasGate && (nonTerminal.length || doneNoEvidence.length)) {
        doc.verdict = 'probable-false-done';
        if (nonTerminal.length) doc.reasons.push(`${nonTerminal.length} AC row(s) non-terminal`);
        if (doneNoEvidence.length) doc.reasons.push(`${doneNoEvidence.length} done AC row(s) without evidence`);
      } else if (!ac.hasGate && type === 'spec') {
        doc.verdict = 'probable-partial';
        doc.reasons.push('status done but mandated AC Status table is absent');
      } else if (!ac.hasGate && !quick) {
        const hasCommit = lastIdMentionDate(root, id) != null;
        const hasEvidence = events.some(e => e.event === 'ac_evidence' && String(e.ref).startsWith(id));
        if (!hasCommit && !hasEvidence) {
          doc.verdict = 'probable-false-done';
          doc.reasons.push('no commit and no ac_evidence event references this doc');
        }
      }
    } else if (OPEN_STATUSES.has(status) && !quick) {
      const lastEdit = lastEditDate(root, f.rel);
      const lastMention = lastIdMentionDate(root, id);
      const editAge = lastEdit ? daysBetween(lastEdit, todayUTC) : null;
      const mentionAge = lastMention ? daysBetween(lastMention, todayUTC) : null;
      if (editAge != null && editAge > staleDays && (mentionAge == null || mentionAge > staleDays)) {
        doc.verdict = 'probable-stale-open';
        doc.reasons.push(`status ${status}, last edit ${lastEdit}, last DOC-ID commit ${lastMention ?? 'never'} (> ${staleDays}d)`);
      }
    }
    if (doc.verdict) { doc.cls = 'drifted'; continue; }
    doc.verdict = 'aligned';

    if (status === 'done') { doc.cls = 'tracked-done'; continue; }

    // obsolete: deferred with every Review-By overdue, or inactive legacy doc
    if (status === 'deferred') {
      const reviewDates = ac.rows.map(r => parseISODate(r['Review-By'])).filter(d => d instanceof Date);
      if (reviewDates.length && reviewDates.every(d => d < todayUTC)) {
        doc.cls = 'obsolete';
        doc.reasons.push('deferred with all Review-By dates overdue');
        continue;
      }
    }
    doc.cls = 'tracked-open';
  }

  // backlog cross-check (read-only, strengthens false-done)
  if (!quick && config?.backlog_globs?.length) {
    const claims = backlogDoneClaims(root, config.backlog_globs, docs.map(d => d.id));
    for (const d of docs) {
      if (claims.has(d.id) && d.cls !== 'tracked-done' && d.cls !== 'superseded') {
        if (d.verdict === 'aligned') d.verdict = 'probable-false-done';
        if (d.cls === 'tracked-open' || d.cls === 'obsolete') d.cls = 'drifted';
        d.reasons.push('backlog row claims Done but doc state disagrees');
      }
    }
  }

  const orphans = docs.filter(d => d.cls === 'orphan');
  const orphansNew = orphans.filter(d => !d.legacy);
  const orphansLegacy = orphans.filter(d => d.legacy);
  const drift = docs.filter(d => d.cls === 'drifted');
  const counts = {
    total: docs.length,
    orphans: orphans.length,
    orphansNew: orphansNew.length,
    drifted: drift.length,
    stale: drift.filter(d => d.verdict === 'probable-stale-open').length,
    obsolete: docs.filter(d => d.cls === 'obsolete').length,
    trackedOpen: docs.filter(d => d.cls === 'tracked-open').length,
    trackedDone: docs.filter(d => d.cls === 'tracked-done').length,
    superseded: docs.filter(d => d.cls === 'superseded').length,
    violations: violations.length,
  };
  const hardFail = mode === 'enforced' && (orphansNew.length > 0 || violations.length > 0);

  return { mode, config, docs, orphansNew, orphansLegacy, drift, violations, counts, hardFail };
}

export function suggestedStep(doc) {
  if (doc.cls === 'orphan') return `add frontmatter per .aai/templates (type ${doc.rel.split('/')[1] ?? 'doc'})`;
  switch (doc.verdict) {
    case 'probable-false-done': return 'reconcile AC table / evidence, then re-confirm done status';
    case 'probable-partial': return 'add the Acceptance Criteria Status table, then re-validate';
    case 'probable-stale-open': return 'confirm whether work shipped elsewhere; close or revive';
    default: return doc.cls === 'obsolete' ? 're-decide overdue deferral' : '—';
  }
}
