// recheck.mjs - the delta re-check eligibility decision
// (docs/specs/SPEC-DRAFT-spec-cheap-transitions-slice.md, D1 to D5).
//
// A Validation or Code Review round that follows a judged round may run on a slim
// payload (contract + .aai/RECHECK_DELTA.prompt.md + a scope listing the delta)
// ONLY when every condition below holds. Anything else resolves to `full` and
// names every failing condition: the mode is opt-in by proof, never by default.
//
// This module only READS (git, STATE, EVENTS, the reports named in STATE, the
// docs-audit config); it never writes any of them. The verdict stamps that make a
// round "judged" are written by orchestration-dispatch.mjs through append-event.mjs.
//
// Node stdlib plus the repo's own read-only libraries. No new dependency.

import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { splitLines } from './state-core.mjs';
import { findBlock, readScalar, unquoteScalar } from './state-engine.mjs';
import { loadConfig } from './docs-audit-core.mjs';
import { SHARED_GENERATED_PAGES } from './docs-model.mjs';

export const RECHECK_ROLES = new Set(['Validation', 'Code Review']);
export const ROLE_TOKENS = { Validation: 'validation', 'Code Review': 'code_review' };
export const FORCE_ENV = 'AAI_RECHECK_MODE';
export const PROTECTED_LEVEL = 3;
export const RECHECK_PROMPT = '.aai/RECHECK_DELTA.prompt.md';
const HEX40 = /^[0-9a-f]{40}$/;

// D2: an explicit allowlist. Everything not matched here (and not a ledger or a
// generated page below) is production, including .aai/**, .github/**, .claude/**,
// docs/knowledge/** (LEARNED is part of every payload), docs/ai/*.yaml and every
// root file except CHANGELOG.md.
export const NON_PRODUCTION_PATTERNS = [
  /^tests\//,
  /^docs\/specs\//,
  /^docs\/issues\//,
  /^docs\/rfc\//,
  /^docs\/analysis\//,
  /^docs\/product\//,
  /^docs\/ai\/reviews\//,
  /^docs\/ai\/tdd\//,
  /^docs\/ai\/reports\//,
  /^CHANGELOG\.md$/,
];

// The append-only ledgers and generated pages; the dispatch tree hash excludes the
// same set (TEST-2702 compares the two lists so they cannot drift).
export const LEDGER_AND_PAGE_PATHS = new Set([
  'docs/ai/EVENTS.jsonl',
  'docs/ai/METRICS.jsonl',
  'docs/ai/decisions.jsonl',
  'docs/ai/tests/test-runs.jsonl',
  'docs/ai/dashboard.html',
  'docs/ai/dashboard-data.json',
  ...SHARED_GENERATED_PAGES,
]);

export function isNonProduction(p) {
  return LEDGER_AND_PAGE_PATHS.has(p) || NON_PRODUCTION_PATTERNS.some((re) => re.test(p));
}

function git(root, args) {
  return execFileSync('git', args, {
    cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024,
  });
}

export function gitHead(root) {
  try {
    const h = git(root, ['rev-parse', 'HEAD']).trim();
    return HEX40.test(h) ? h : null;
  } catch {
    return null;
  }
}

function refMatches(vref, ref) {
  if (vref == null || ref == null) return false;
  return vref === ref || String(vref).split('/').includes(ref);
}

// --- STATE (read only) -------------------------------------------------------

function listField(lines, blockKey, field) {
  const b = findBlock(lines, blockKey);
  if (!b) return [];
  const header = new RegExp(`^ {2}${field}:\\s*(.*)$`);
  for (let i = b.start + 1; i < b.end; i += 1) {
    const m = header.exec(lines[i]);
    if (!m) continue;
    const inline = m[1].trim();
    if (inline === '[]') return [];
    if (inline.startsWith('[')) {
      return inline.replace(/^\[|\]$/g, '').split(',').map((s) => unquoteScalar(s.trim())).filter(Boolean);
    }
    const out = [];
    for (let j = i + 1; j < b.end; j += 1) {
      const it = /^ {4}- (.*)$/.exec(lines[j]);
      if (!it) break;
      out.push(unquoteScalar(it[1].trim()));
    }
    return out;
  }
  return [];
}

function workItemSpecPath(lines, ref) {
  const b = findBlock(lines, 'active_work_items');
  if (!b) return null;
  let cur = null;
  for (let i = b.start + 1; i < b.end; i += 1) {
    const l = lines[i];
    if (/^ {2}- /.test(l)) cur = { ref: null, spec: null, done: false };
    if (!cur) continue;
    const m = /^(?: {2}- | {4})([\w-]+):\s*(.*)$/.exec(l);
    if (!m) continue;
    const v = m[2].trim() === 'null' ? '' : unquoteScalar(m[2].trim());
    if (m[1] === 'ref_id') cur.ref = v;
    if (m[1] === 'spec_path') cur.spec = v || null;
    if (cur.ref === ref && cur.spec) return cur.spec;
  }
  return null;
}

// readCheckState(statePath) -> the fields the delta decision and the stamps read,
// or null when STATE is missing or unreadable.
export function readCheckState(statePath) {
  let raw;
  try {
    raw = fs.readFileSync(statePath, 'utf8');
  } catch {
    return null;
  }
  const { lines } = splitLines(raw);
  const focusRef = readScalar(lines, 'current_focus', 'ref_id');
  return {
    focusRef,
    specPath: (focusRef && workItemSpecPath(lines, focusRef)) || readScalar(lines, 'current_focus', 'spec_path'),
    validation: {
      status: readScalar(lines, 'last_validation', 'status'),
      ref: readScalar(lines, 'last_validation', 'ref_id'),
      runAt: readScalar(lines, 'last_validation', 'run_at_utc'),
      evidencePaths: listField(lines, 'last_validation', 'evidence_paths'),
    },
    review: {
      status: readScalar(lines, 'code_review', 'status'),
      scopeRef: readScalar(lines, 'code_review', 'scope_ref_id'),
      reportPaths: listField(lines, 'code_review', 'report_paths'),
    },
  };
}

// --- EVENTS (read only) ------------------------------------------------------

export function readEvents(root) {
  let raw;
  try {
    raw = fs.readFileSync(path.join(root, 'docs/ai/EVENTS.jsonl'), 'utf8');
  } catch {
    return [];
  }
  const out = [];
  for (const line of raw.split(/\r?\n/)) {
    const t = line.trim();
    if (t === '' || t.startsWith('#')) continue;
    try { out.push(JSON.parse(t)); } catch { /* an unparseable line is skipped */ }
  }
  return out;
}

function lastIndexWhere(events, pred) {
  for (let i = events.length - 1; i >= 0; i -= 1) if (pred(events[i])) return i;
  return -1;
}

function stampOf(events, type, ref, roleToken) {
  const i = lastIndexWhere(events, (e) => e && e.event === type && e.ref === ref && e.payload && e.payload.role === roleToken);
  return i === -1 ? null : { idx: i, payload: events[i].payload };
}

// --- the decision ------------------------------------------------------------

function protectedMatch(entry, p) {
  const e = String(entry).trim();
  if (e === '') return false;
  if (e.includes('*')) {
    const re = new RegExp('^' + e.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*\*/g, '\u0000').replace(/\*/g, '[^/]*').replace(/\u0000/g, '.*') + '$');
    return re.test(p);
  }
  return p === e || p.startsWith(e.endsWith('/') ? e : e + '/');
}

const MARK_TRUE_RE = /^security_relevant: true\s*$/m;
const MARK_FALSE_RE = /^security_relevant: false\s*$/gm;
const MARK_ANY_RE = /^security_relevant:/gm;

function ceremonyLevel(root, specPath) {
  if (!specPath) return null;
  let body;
  try {
    body = fs.readFileSync(path.resolve(root, specPath), 'utf8').replace(/\r\n?/g, '\n');
  } catch {
    return null;
  }
  const fm = /^---\n([\s\S]*?)\n---/.exec(body);
  if (!fm) return null;
  const m = /^ceremony_level:\s*(\S+)\s*$/m.exec(fm[1]);
  if (!m || !/^[0-9]+$/.test(m[1])) return null;
  return Number(m[1]);
}

// recheckMode({ root, ref, role, env, statePath }) ->
//   { mode, reasons, base, head, changed_paths, prior_reports }
// `mode` is 'delta' only when `reasons` is empty. Reasons are collected, not
// first-match, in the order of the D1 table.
export function recheckMode({ root, ref, role, env = process.env, statePath = null }) {
  const reasons = [];
  const roleToken = ROLE_TOKENS[role] ?? null;
  if (!RECHECK_ROLES.has(role)) reasons.push('role_not_rechecked');
  if (env && env[FORCE_ENV] === 'full') reasons.push('forced_full');

  let gitFailed = false;
  const head = gitHead(root);
  if (head === null) gitFailed = true;

  const events = readEvents(root);
  const priorVerdict = roleToken ? stampOf(events, 'check_verdict', ref, roleToken) : null;
  let base = null;
  if (!priorVerdict) {
    reasons.push('first_round');
  } else if (HEX40.test(String(priorVerdict.payload.head))) {
    base = priorVerdict.payload.head;
  }

  let changed = [];
  let diffBase = null;
  if (!gitFailed) {
    if (base) {
      let ancestor = false;
      try {
        git(root, ['merge-base', '--is-ancestor', base, 'HEAD']);
        ancestor = true;
      } catch (err) {
        if (err && (err.status === 1 || err.status === 128)) ancestor = false;
        else gitFailed = true;
      }
      if (!gitFailed) {
        if (ancestor) diffBase = base;
        else reasons.push('base_not_ancestor');
      }
    } else if (priorVerdict) {
      reasons.push('base_not_ancestor');
    } else {
      diffBase = 'HEAD';
    }
  }
  if (!gitFailed && diffBase) {
    try {
      const tracked = git(root, ['diff', '--name-only', '--no-renames', '-z', diffBase, '--']).split('\0').filter(Boolean);
      const untracked = git(root, ['ls-files', '--others', '--exclude-standard', '-z']).split('\0').filter(Boolean);
      changed = [...new Set([...tracked, ...untracked])].sort();
    } catch {
      gitFailed = true;
    }
  }
  if (gitFailed) reasons.push('git_error');
  if (!gitFailed && base && diffBase && changed.length === 0) reasons.push('no_delta');

  for (const p of changed) if (!isNonProduction(p)) reasons.push(`production_path:${p}`);

  let protectedList = null;
  try {
    const cfg = loadConfig(root);
    if (cfg && Array.isArray(cfg.protected_paths_l3)) protectedList = cfg.protected_paths_l3;
  } catch {
    protectedList = null;
  }
  if (protectedList === null) {
    reasons.push('protected_config_unreadable');
  } else {
    for (const p of changed) if (protectedList.some((e) => protectedMatch(e, p))) reasons.push(`protected_path:${p}`);
  }

  const state = readCheckState(statePath || path.join(root, 'docs/ai/STATE.yaml'));
  const mine = state && refMatches(state.focusRef, ref) ? state : null;
  const level = mine ? ceremonyLevel(root, mine.specPath) : null;
  if (level === PROTECTED_LEVEL) reasons.push('ceremony_l3');
  else if (![0, 1, 2].includes(level)) reasons.push('ceremony_unknown');

  const priorReports = [];
  const roleReports = { validation: [], code_review: [] };
  if (mine) {
    if (refMatches(mine.validation.ref, ref)) {
      roleReports.validation = mine.validation.evidencePaths.filter((p) => /\.md$/i.test(p));
    }
    if (mine.review.scopeRef == null || refMatches(mine.review.scopeRef, ref)) {
      roleReports.code_review = mine.review.reportPaths;
    }
  }
  for (const p of [...roleReports.validation, ...roleReports.code_review]) if (!priorReports.includes(p)) priorReports.push(p);
  for (const p of priorReports) {
    let text;
    try {
      text = fs.readFileSync(path.resolve(root, p), 'utf8');
    } catch {
      reasons.push(`prior_report_unreadable:${p}`);
      continue;
    }
    if (MARK_TRUE_RE.test(text)) {
      reasons.push(`security_relevant:${p}`);
    } else if ((text.match(MARK_ANY_RE) || []).length !== 1 || (text.match(MARK_FALSE_RE) || []).length !== 1) {
      reasons.push(`security_marker_absent:${p}`);
    }
  }
  if (roleToken && roleReports[roleToken].length === 0) reasons.push(`security_marker_absent:${roleToken}`);

  if (reasons.length === 0) {
    return { mode: 'delta', reasons, base, head, changed_paths: changed, prior_reports: priorReports };
  }
  return { mode: 'full', reasons, base, head, changed_paths: changed, prior_reports: priorReports };
}

// --- verdict stamps (D4), planned here and written by the dispatch -----------

function runAtMs(v) {
  return v ? Date.parse(v) : NaN;
}

// The identity of the current verdict of one check role, as the stamps compare it.
function currentIdentity(state, roleToken, ref) {
  if (!state) return null;
  if (roleToken === 'validation') {
    const v = state.validation;
    const judged = (v.status === 'pass' || v.status === 'fail') && refMatches(v.ref, ref);
    return { seen: `run_at:${v.runAt ?? 'null'}`, status: judged ? v.status : null, runAtMs: runAtMs(v.runAt) };
  }
  const r = state.review;
  const judged = (r.status === 'pass' || r.status === 'fail') && (r.scopeRef == null || refMatches(r.scopeRef, ref));
  return { seen: `reports:${r.reportPaths.length}`, status: judged ? r.status : null, count: r.reportPaths.length };
}

function isNewer(roleToken, marker, cur) {
  if (roleToken === 'validation') {
    const m = /^run_at:(.*)$/.exec(marker || '');
    const markerMs = m ? runAtMs(m[1]) : NaN;
    if (!Number.isFinite(cur.runAtMs)) return false;
    return !Number.isFinite(markerMs) || cur.runAtMs > markerMs;
  }
  const m = /^reports:([0-9]+)$/.exec(marker || '');
  return m ? cur.count > Number(m[1]) : false;
}

// planCheckStamps({ root, statePath, ref, dispatchRole }) -> [{ event, role, head, status|seen }]
// in append order. Pure: reads EVENTS, STATE and git HEAD, writes nothing.
export function planCheckStamps({ root, statePath = null, ref, dispatchRole = null }) {
  const head = gitHead(root);
  if (head === null || !ref) return [];
  const events = readEvents(root);
  const state = readCheckState(statePath || path.join(root, 'docs/ai/STATE.yaml'));
  if (!state) return [];
  const stamps = [];
  const verdictPlanned = new Set();
  for (const roleToken of ['validation', 'code_review']) {
    const lastD = stampOf(events, 'check_dispatched', ref, roleToken);
    if (!lastD) continue;
    const verdictAfter = lastIndexWhere(events, (e) => e && e.event === 'check_verdict' && e.ref === ref
      && e.payload && e.payload.role === roleToken) > lastD.idx;
    if (verdictAfter) continue;
    const cur = currentIdentity(state, roleToken, ref);
    if (cur && cur.status && isNewer(roleToken, lastD.payload.seen, cur) && HEX40.test(String(lastD.payload.head))) {
      stamps.push({ event: 'check_verdict', role: roleToken, head: lastD.payload.head, status: cur.status });
      verdictPlanned.add(roleToken);
    }
  }
  const dispatchToken = ROLE_TOKENS[dispatchRole] ?? null;
  if (dispatchToken) {
    const cur = currentIdentity(state, dispatchToken, ref);
    const lastD = stampOf(events, 'check_dispatched', ref, dispatchToken);
    const verdictSince = lastD && lastIndexWhere(events, (e) => e && e.event === 'check_verdict' && e.ref === ref
      && e.payload && e.payload.role === dispatchToken) > lastD.idx;
    const repeat = lastD && lastD.payload.head === head && lastD.payload.seen === cur.seen
      && !verdictSince && !verdictPlanned.has(dispatchToken);
    if (!repeat) stamps.push({ event: 'check_dispatched', role: dispatchToken, head, seen: cur.seen });
  }
  return stamps;
}
