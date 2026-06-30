// Docs hygiene & drift audit core (RFC-0002 / SPEC-0001).
// Pure analysis: classifies every prefixed doc under docs/ and derives drift
// verdicts. REPORTS only — never writes to any doc, plan, or backlog file.

import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import {
  DOC_STATUS_ENUM, AC_STATUS_ENUM, TERMINAL_AC, DOC_TYPE_ENUM, DOC_ID_RE,
  DEFAULT_CATEGORY_PREFIXES, extractDocIds,
  parseFrontmatter, parseAcTable, parseISODate, parseReviewBy, specFrozenInBody,
  validateCanonicalFrontmatter, asList, toPosix,
} from './docs-model.mjs';

export const CONFIG_PATH = 'docs/ai/docs-audit.yaml';
export const EVENTS_PATH = 'docs/ai/EVENTS.jsonl';
const SCAN_ROOT = 'docs';
// RFC-0003 / SPEC-0002 SEAM-3: the canonicalization layer archives originals to
// `docs/_archive/` (with underscore). The historical exclude list named
// `archive` (no underscore), which would let archived docs be scanned and
// mis-flagged as orphans. Both names are excluded so the chosen archive dir is
// consistently treated as preserved-not-active.
const EXCLUDE_DIRS = new Set(['ai', 'knowledge', 'archive', '_archive', 'project-sessions', 'templates']);
const ID_FILE_RE = DOC_ID_RE;
const OPEN_STATUSES = new Set(['draft', 'implementing']);
const DEFAULT_STALE_DAYS = 90;
// closeout-candidate detection (SPEC-0003 / CHANGE-0004): parents are scoped to
// rfc/prd only (change docs also carry links.spec and would false-positive), and
// only non-terminal, ready statuses are eligible (draft excluded — not yet ready).
const CLOSEOUT_PARENT_TYPES = new Set(['rfc', 'prd']);
const CLOSEOUT_PARENT_STATUSES = new Set(['proposed', 'accepted', 'implementing']);

// SPEC-0006 Spec-AC-06 — open-decision-on-done guard. A body line that asserts an
// UNRESOLVED decision: a token below combined with a WARNING context (a literal
// WARNING word or a GitHub `> [!WARNING]` callout block), or an explicit
// `<!-- OPEN-DECISION -->` marker. Narrow on purpose — an ordinary informational
// note (no token, no WARNING) must NOT trip it (false-positive negative control).
const OPEN_DECISION_TOKEN_RE = /\b(?:unresolved|open decisions?|must be (?:resolved|confirmed|decided)|pending (?:confirmations?|decisions?)|to be (?:resolved|confirmed|decided))\b/i;
const OPEN_DECISION_COMMENT_RE = /<!--\s*OPEN-DECISION\s*-->/i;

// --- config -----------------------------------------------------------------

export function loadConfig(root) {
  const p = path.join(root, CONFIG_PATH);
  if (!fs.existsSync(p)) return null;
  const cfg = {
    legacy_until_date: null,
    stale_after_days: DEFAULT_STALE_DAYS,
    plan_scan_mode: 'lenient',
    scan_exclude: [],
    backlog_globs: [],
    review_by_methods: [],
    category_prefixes: [...DEFAULT_CATEGORY_PREFIXES],
  };
  const LIST_KEYS = new Set(['scan_exclude', 'backlog_globs', 'review_by_methods', 'category_prefixes']);
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
    if (LIST_KEYS.has(key)) {
      listKey = key;
      // an explicit value replaces the default (block items follow when empty)
      if (val && val !== '[]') {
        cfg[key] = val.replace(/^\[|\]$/g, '').split(',').map(s => s.trim().replace(/^["']|["']$/g, '')).filter(Boolean);
        listKey = null;
      } else {
        cfg[key] = [];
        if (val === '[]') listKey = null;
      }
      continue;
    }
    listKey = null;
    if (key === 'legacy_until_date') cfg.legacy_until_date = val || null;
    else if (key === 'stale_after_days') cfg.stale_after_days = Number(val) || DEFAULT_STALE_DAYS;
    else if (key === 'plan_scan_mode') cfg.plan_scan_mode = (val === 'strict') ? 'strict' : 'lenient';
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
  // no --follow: its rename detection mis-attributes a file's add commit to
  // an unrelated commit that added similar content (CHANGE-0002 D13 fixture)
  const out = git(root, `log --diff-filter=A --format=%cs -- "${rel}"`);
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
      // SPEC-0007 WARNING-1 — normalize to POSIX forward-slash separators so that
      // scanExclude glob matching (POSIX) and the Orphans section of docs/INDEX.md
      // carry forward-slash paths on every OS (no backslashes on Windows).
      const rel = toPosix(path.relative(root, full));
      if (scanExclude.some(g => rel === g || rel.startsWith(g.replace(/\/+$/, '') + '/'))) continue;
      if (entry.isDirectory()) { visit(full, depth + 1); continue; }
      if (!entry.name.endsWith('.md') || entry.name === 'INDEX.md') continue;
      const m = entry.name.match(ID_FILE_RE);
      // RFC-0003 / SPEC-0002: canonical docs are named <domain>.md (no ID
      // prefix); they carry their id in frontmatter and must still be scanned
      // so their canonical-provenance schema is validated. Their fileId is
      // derived from the frontmatter id at parse time.
      // rel is POSIX-normalized (SPEC-0007 WARNING-1), so compare against a
      // POSIX literal — path.join(...)+path.sep would be backslash on Windows
      // and never match the forward-slash rel, dropping canonical docs there.
      const inCanonical = rel.startsWith('docs/canonical/');
      if (!m && !inCanonical) continue;
      if (scopePath) {
        const scope = toPosix(path.relative(root, path.resolve(root, scopePath)));
        if (rel !== scope && !rel.startsWith(scope.replace(/\/+$/, '') + '/')) continue;
      }
      found.push({ rel, fileId: m ? m[1] : null });
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

// SPEC-0006 Spec-AC-06 — scan a doc body for an open-decision marker OUTSIDE
// fenced code blocks. Returns { marker, line } (1-based) for the first hit, or
// null. Fenced ``` / ~~~ regions are skipped so inline examples never trip it.
export function findOpenDecisionMarker(content) {
  const lines = String(content ?? '').split('\n');
  let inFence = false;
  let fenceCh = null;
  let calloutActive = false;
  for (let i = 0; i < lines.length; i += 1) {
    const raw = lines[i];
    const fence = raw.match(/^\s*(```|~~~)/);
    if (fence) {
      const ch = fence[1][0];
      if (!inFence) { inFence = true; fenceCh = ch; }
      else if (raw.trim()[0] === fenceCh) { inFence = false; fenceCh = null; }
      continue;
    }
    if (inFence) continue;

    // Strip inline code spans before any pattern test so markers that appear
    // only inside backticks (documentation examples, not real callouts) are not
    // matched. Fenced-code-block awareness is handled above; this covers the
    // single-line inline case.
    const stripped = raw.replace(/`[^`\n]*`/g, '');

    if (OPEN_DECISION_COMMENT_RE.test(stripped)) return { marker: 'OPEN-DECISION marker', line: i + 1 };

    // Track a `> [!WARNING]` callout: its contiguous blockquote lines are a
    // warning context too (the token may sit on a following quoted line).
    const isCalloutHeader = /^\s*>\s*\[!WARNING\]/i.test(raw);
    const isBlockquote = /^\s*>/.test(raw);
    if (isCalloutHeader) calloutActive = true;
    else if (calloutActive && !isBlockquote) calloutActive = false;

    const inWarning = /\bWARNING\b/.test(stripped) || (calloutActive && isBlockquote);
    if (inWarning && OPEN_DECISION_TOKEN_RE.test(stripped)) {
      return { marker: 'WARNING with open-decision token', line: i + 1 };
    }
  }
  return null;
}

export function runAudit(root, { quick = false, scopePath = null, today = new Date(), strict = false, strictTypes = false } = {}) {
  const config = loadConfig(root);
  const mode = quick ? 'quick' : ((config || strict) ? 'enforced' : 'report-only');
  const staleDays = config?.stale_after_days ?? DEFAULT_STALE_DAYS;
  const legacyUntil = config?.legacy_until_date ?? null;
  const todayUTC = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));

  const files = scanAuditDocs(root, { scopePath, scanExclude: config?.scan_exclude ?? [] });
  const events = quick ? [] : readEvents(root);
  const categoryPrefixes = config?.category_prefixes ?? DEFAULT_CATEGORY_PREFIXES;
  const extraMethods = config?.review_by_methods ?? [];
  const planMode = config?.plan_scan_mode ?? 'lenient';
  const docs = [];
  const violations = [];
  const typeWarnings = [];
  const annotations = [];
  const openDecisionDoneDocs = [];   // SPEC-0006 Spec-AC-06 (report-only)

  for (const f of files) {
    const content = fs.readFileSync(path.join(root, f.rel), 'utf8');
    const fm = parseFrontmatter(content);
    const ac = parseAcTable(content);
    // filename-derived primary/related/scope (CHANGE-0002 D14/D15)
    const ids = extractDocIds(path.basename(f.rel), categoryPrefixes) ?? { primary: f.fileId, related: [], scope: null };
    const id = fm?.id ?? ids.primary;
    const doc = {
      rel: f.rel, id, fileId: ids.primary, relatedIds: ids.related, scope: ids.scope,
      fm, ac, cls: null, verdict: null, reasons: [], legacy: false,
    };
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
      // operator plan files are work-tracking artifacts, not authored content
      // needing canonical schema (CHANGE-0002 D12)
      if (planMode === 'lenient' && f.rel.startsWith('docs/plans/')) {
        doc.cls = 'tracked-open';
        doc.verdict = 'aligned';
        doc.reasons.push('operator plan file (plan_scan_mode: lenient)');
        continue;
      }
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
      const rb = parseReviewBy(row['Review-By'], extraMethods);
      if (rb.kind === 'invalid') violations.push({ rel: f.rel, msg: `invalid Review-By "${rb.raw}" for ${row['Spec-AC']} (ISO date, skill label, label:date, or "<actor> <method>")` });
    }
    doc.status = status;

    // SPEC-0006 Spec-AC-06 — READ-ONLY: a done doc carrying a buried open-decision
    // marker (outside fenced code). Surfaced in its own digest section; NEVER
    // feeds hardFail/needsTriage or any exit code (RFC-0001 mechanism-over-
    // discipline: gated/indexed, not a hard gate until the signal is proven clean).
    if (status === 'done') {
      const od = findOpenDecisionMarker(content);
      if (od) openDecisionDoneDocs.push({ id, rel: f.rel, marker: od.marker, line: od.line });
    }

    // type validation (CHANGE-0001 D7): soft warning, hard with --strict-types
    if (fm.type && !DOC_TYPE_ENUM.has(String(fm.type).toLowerCase())) {
      const msg = `unknown type "${fm.type}" (allowed: ${[...DOC_TYPE_ENUM].join(', ')})`;
      typeWarnings.push({ rel: f.rel, id, msg });
      if (strictTypes) violations.push({ rel: f.rel, msg });
    }

    // canonical provenance validation (RFC-0003 / SPEC-0002 Spec-AC-02):
    // a canonical doc must carry a valid domain slug + non-empty sources list.
    // These are hard schema violations (count toward hardFail under --strict).
    if (String(fm.type ?? '').toLowerCase() === 'canonical') {
      const v = validateCanonicalFrontmatter(fm);
      for (const msg of v.violations) {
        violations.push({ rel: f.rel, msg: `canonical frontmatter: ${msg}` });
      }
    }

    // amendment annotations (CHANGE-0001 D3): recognized sibling fields
    for (const key of ['amendment_note', 'amended_by', 'superseded_by']) {
      if (fm[key]) annotations.push({ id, rel: f.rel, key, value: fm[key] });
    }

    if (status === 'superseded' || status === 'rejected') { doc.cls = 'superseded'; continue; }

    // legacy frozen-in-body marker (CHANGE-0001 D2): a draft doc carrying
    // SPEC-FROZEN: true is effectively frozen, not a stale-open candidate
    if (status === 'draft' && specFrozenInBody(content)) {
      doc.effectiveStatus = 'frozen';
      doc.reasons.push('SPEC-FROZEN marker in body');
      doc.verdict = 'aligned';
      doc.cls = 'tracked-open';
      continue;
    }

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
        // PARENT-ID/sub-item refs roll up to the parent, but sibling IDs
        // (CHANGE-0045 vs CHANGE-004) must not cross-match (CHANGE-0002 D11)
        const hasEvidence = events.some(e => e.event === 'ac_evidence'
          && (String(e.ref) === id || String(e.ref).startsWith(id + '/')));
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
      const reviewDates = ac.rows.map(r => parseReviewBy(r['Review-By']).date).filter(d => d instanceof Date);
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

  // closeout-candidate detection (SPEC-0003 / CHANGE-0004): READ-ONLY post-pass.
  // Surface every non-terminal rfc/prd parent whose every resolved linked spec
  // is `done`, so an operator can close the parent. Reuses the in-memory docs[]
  // id index and asList() — no second scan. NOT part of hardFail/needsTriage.
  const closeoutCandidates = closeoutCandidatesFor(docs);

  // pending-commit notice (CHANGE-0001 D6): the verdict already reflects the
  // working tree; this only tells the operator which scanned docs differ from git
  let pendingCommit = [];
  if (!quick) {
    const porcelain = git(root, 'status --porcelain -- docs');
    if (porcelain) {
      const dirty = new Set(porcelain.split('\n').map(l => l.slice(3).trim()).filter(Boolean));
      pendingCommit = docs.filter(d => dirty.has(d.rel)).map(d => d.rel);
    }
  }

  const orphans = docs.filter(d => d.cls === 'orphan');
  const orphansNew = orphans.filter(d => !d.legacy);
  const orphansLegacy = orphans.filter(d => d.legacy);
  const drift = docs.filter(d => d.cls === 'drifted');
  const planLenient = docs.filter(d => d.reasons.some(r => r.startsWith('operator plan file')));
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
    typeWarnings: typeWarnings.length,
    closeoutCandidates: closeoutCandidates.length,
    openDecisionDone: openDecisionDoneDocs.length,
  };
  // openDecisionDoneDocs is deliberately absent from hardFail (report-only).
  const hardFail = mode === 'enforced' && (orphansNew.length > 0 || violations.length > 0);

  return {
    mode, config, docs, orphansNew, orphansLegacy, drift, violations,
    typeWarnings, annotations, pendingCommit, planLenient, closeoutCandidates,
    openDecisionDoneDocs, counts, hardFail,
  };
}

// Resolve non-terminal rfc/prd parents whose every linked spec is done.
// Returns [{ id, rel, type, status, specs: [doneSpecId...], suggestedStep }].
// Linked-spec resolution = forward asList(links.spec) UNION reverse links
// (a scanned spec whose links.rfc / links.requirement names the parent). A
// parent is flagged iff it resolves >= 1 spec AND every resolved spec id maps to
// a scanned doc with status `done` (an unresolvable id => not flagged).
export function closeoutCandidatesFor(docs) {
  const byId = new Map();
  for (const d of docs) { if (d.id) byId.set(d.id, d); }
  const docType = (d) => String(d.fm?.type ?? '').toLowerCase();
  const out = [];
  for (const parent of docs) {
    if (!CLOSEOUT_PARENT_TYPES.has(docType(parent))) continue;
    if (!CLOSEOUT_PARENT_STATUSES.has(parent.status)) continue;
    const specIds = new Set(asList(parent.fm?.links?.spec));
    for (const d of docs) {
      if (docType(d) !== 'spec' || !d.id) continue;
      const reverse = [...asList(d.fm?.links?.rfc), ...asList(d.fm?.links?.requirement)];
      if (reverse.includes(parent.id)) specIds.add(d.id);
    }
    if (specIds.size === 0) continue;
    const resolved = [...specIds].map(sid => byId.get(sid));
    // Every resolved id must be an actual spec that is done. A forward
    // links.spec that names a non-spec (e.g. a done CHANGE) or an unresolvable
    // id does not count as "all linked specs done" (guards a misfiled link).
    if (resolved.some(r => !r || docType(r) !== 'spec' || r.status !== 'done')) continue;
    out.push({
      id: parent.id,
      rel: parent.rel,
      type: docType(parent),
      status: parent.status,
      specs: [...specIds].sort(),
      suggestedStep: `advance ${parent.id} to done/accepted; record the implementing commit`,
    });
  }
  return out.sort((a, b) => a.id.localeCompare(b.id));
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
