// recheck.mjs - the delta re-check eligibility decision
// (docs/specs/SPEC-0250-spec-cheap-transitions-slice.md, D1 to D5).
//
// A Validation or Code Review round that follows a judged round may run on a slim
// payload (contract + .aai/RECHECK_DELTA.prompt.md + a scope listing the delta)
// ONLY when every condition below holds. Anything else resolves to `full` and
// names every failing condition: the mode needs proof (the conditions below) and
// AAI_RECHECK_MODE=full turns it off for a run.
//
// This module only READS (git, STATE, EVENTS, the reports named in STATE, the
// docs-audit config); it never writes any of them. The judged round it compares is the
// check_binding block (and the per-ref check_sticky record) of STATE, written by
// state.mjs bind-check; the verdict stamps in EVENTS.jsonl are telemetry only.
//
// Node stdlib plus the repo's own read-only libraries. No new dependency.

import fs from 'node:fs';
import path from 'node:path';
import {
  AMBIGUOUS_HEAD, boundBinding, gitBytes, gitHeadOf, gitOut, judgeBinding, markerOfReports, markerOfText, readBinding, readSticky,
  readCheckState, refMatches, roleReportsOf,
} from './check-binding.mjs';
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
//
// Under tests/ only TEST CODE is non-production: a suite, a Pester file or a node:test
// file, named by pattern. Production scripts read other files under tests/ as gate
// inputs (suite-map.yaml and suite-weights.tsv choose which suites CI runs, the
// *-baseline.tsv, *-ratchet.sh and prompt-diet-ledger.sh files set ratchets, and
// merge-policy.mjs lists suite-map.yaml among its GUARD_PATHS), so a new file there
// defaults to production and a remediation that edits one gets the full payload.
// TEST-2730 derives the files the scripts name and holds this list to them.
export const NON_PRODUCTION_PATTERNS = [
  /^tests\/skills\/test-aai-[^/]+\.sh$/,
  /^tests\/skills\/[^/]+\.Tests\.ps1$/,
  /^tests\/skills\/lib\/[^/]+\.test\.mjs$/,
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

// Owner decision 2026-10-24 ("Zapnout po ověření"): delta is the default now that the judged round
// is bound to STATE (check-binding.mjs). AAI_RECHECK_MODE is trimmed and lower-cased: unset, empty,
// blank and `delta` enable the mode; `full` and every other value (a misspelling included) give the
// reason `recheck_disabled` and keep the round full.
const DEFAULT_ON = true;
export function deltaEnabled(env) {
  const raw = env ? env[FORCE_ENV] : undefined;
  if (raw === undefined || raw === null) return DEFAULT_ON;
  const v = String(raw).trim().toLowerCase();
  if (v === '') return DEFAULT_ON;
  return v === 'delta';
}

// N5: a role name is looked up as an own key only, so `__proto__`, `constructor` and the
// like are unknown roles (role_not_rechecked), never a prototype property.
export function tokenOfRole(role) {
  return Object.hasOwn(ROLE_TOKENS, role) ? ROLE_TOKENS[role] : null;
}

export function isNonProduction(p) {
  return LEDGER_AND_PAGE_PATHS.has(p) || NON_PRODUCTION_PATTERNS.some((re) => re.test(p));
}

// Every git call runs in the environment of check-binding.gitEnv(): no inherited GIT_*
// variable and no replace object.
const git = gitOut;
const gitBuf = gitBytes;

function git_ok(root, args) {
  try {
    git(root, args);
    return true;
  } catch {
    return false;
  }
}

const EVENTS_REL = 'docs/ai/EVENTS.jsonl';

// The ledger blob of one rev as bytes; a rev that has no such file reads as empty (a
// ledger that did not exist yet cannot have been rewritten). null when git cannot say.
function eventsBlob(root, rev) {
  try {
    if (!git_ok(root, ['cat-file', '-e', `${rev}:${EVENTS_REL}`])) return Buffer.alloc(0);
    return gitBuf(root, ['show', `${rev}:${EVENTS_REL}`]);
  } catch {
    return null;
  }
}

function startsWithBytes(big, prefix) {
  return big.length >= prefix.length && big.subarray(0, prefix.length).equals(prefix);
}

// ledger_rewritten: this comparison compares only the live ledger file, the ledger blobs at
// the base and at HEAD, and the blobs of the commits of base..HEAD that touched the file. It is
// true when the live file begins with the exact bytes of its blobs at `base` and at HEAD and
// every such commit begins with its first parent's blob. An unreadable blob is not append-only.
// The verdict that decides eligibility is not read from the ledger (check_binding, D4).
export function eventsAppendOnly(root, base) {
  const baseBlob = eventsBlob(root, base);
  if (baseBlob === null) return false;
  let live;
  try {
    live = fs.existsSync(path.join(root, EVENTS_REL)) ? fs.readFileSync(path.join(root, EVENTS_REL)) : Buffer.alloc(0);
  } catch {
    return false;
  }
  if (!startsWithBytes(live, baseBlob)) return false;
  const headBlob = eventsBlob(root, 'HEAD');
  if (headBlob === null || !startsWithBytes(live, headBlob)) return false;
  let commits;
  try {
    commits = git(root, ['rev-list', '--reverse', '--topo-order', `${base}..HEAD`, '--', EVENTS_REL]).split('\n').filter(Boolean);
  } catch {
    return false;
  }
  for (const c of commits) {
    const prev = eventsBlob(root, `${c}^`);
    const cur = eventsBlob(root, c);
    if (prev === null || cur === null || !startsWithBytes(cur, prev)) return false;
  }
  return true;
}

export function gitHead(root) {
  return gitHeadOf(root);
}

export { readCheckState };

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

export { markerOfText };

// NB-6: the marker of one check role, read from the reports STATE names for it at the
// moment its verdict is first seen, and recorded in the check_verdict stamp (telemetry).
function markerOfRole(root, state, roleToken, ref) {
  return markerOfReports(root, roleReportsOf(state, roleToken, ref));
}

// The level of a spec as one source states it: the live file, or the blob at `base`.
// The delta may edit the focus spec (docs/specs/** is non-production), so the decision
// reads BOTH and takes the stricter one (NB-1); a source that cannot be read is null.
function ceremonyLevelAt(root, specPath, base = null) {
  if (!specPath) return null;
  let body;
  try {
    body = base
      ? git(root, ['show', `${base}:${specPath}`])
      : fs.readFileSync(path.resolve(root, specPath), 'utf8');
  } catch {
    return null;
  }
  body = body.replace(/\r\n?/g, '\n');
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
export function recheckMode({ root, ref, role, env = process.env, statePath = null, ownDispatch = false }) {
  const reasons = [];
  const token = tokenOfRole(role);
  if (!RECHECK_ROLES.has(role)) reasons.push('role_not_rechecked');
  if (!deltaEnabled(env)) reasons.push('recheck_disabled');

  let gitFailed = false;
  const head = gitHead(root);
  if (head === null) gitFailed = true;

  // The judged round comes from check_binding in STATE (D4): no check_ line of the ledger is read.
  const statePathUsed = statePath || path.join(root, 'docs/ai/STATE.yaml');
  const binding = readBinding(statePathUsed);
  const bound = boundBinding(binding, ref, token);
  const sticky = readSticky(statePathUsed);
  let base = null;
  if (!bound) reasons.push('first_round');
  else {
    const judged = judgeBinding({ root, binding: bound, token, head, ownDispatch, sticky });
    reasons.push(...judged.reasons);
    base = judged.base;
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
  if (!gitFailed && base && diffBase === base && !eventsAppendOnly(root, base)) reasons.push('ledger_rewritten');
  // A merge commit in the range can drop a side-branch commit (merge -s ours) that the
  // first-parent ledger chain never sees, so any merge in base..HEAD refuses delta.
  if (!gitFailed && base && diffBase === base) {
    try {
      if (git(root, ['rev-list', '--min-parents=2', '--max-count=1', `${base}..HEAD`]).trim() !== '') reasons.push('merge_in_range');
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

  const state = readCheckState(statePathUsed);
  const mine = state && refMatches(state.focusRef, ref) ? state : null;
  const specPath = mine ? mine.specPath : null;
  // D13: the level is the stricter of the spec the binding recorded and the spec STATE names
  // now, each read live and at the base commit.
  let levelPaths = [specPath];
  if (bound) {
    if (bound.specPath === null) reasons.push('spec_path_unbound:binding');
    else if (bound.specPath !== specPath) reasons.push('spec_path_changed:binding');
    levelPaths = [...new Set([bound.specPath, specPath])];
    // The spec paths the per-ref check_sticky record holds are read for the level as well.
    const recorded = sticky && sticky.entries.get(ref) ? sticky.entries.get(ref).specPaths : [];
    for (const rp of recorded) if (!levelPaths.includes(rp)) levelPaths.push(rp);
  }
  const levels = [];
  for (const sp of levelPaths) {
    levels.push(ceremonyLevelAt(root, sp));
    if (base && !gitFailed) levels.push(ceremonyLevelAt(root, sp, base));
  }
  const known = levels.filter((l) => l !== null);
  if (known.includes(PROTECTED_LEVEL)) reasons.push('ceremony_l3');
  if (known.length !== levels.length || !known.every((l) => [0, 1, 2, PROTECTED_LEVEL].includes(l))) reasons.push('ceremony_unknown');

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
    // NB-1: a report that already existed at the base is judged from the base blob and
    // refuses delta when the delta touched it (an edit there could flip the marker).
    // A report written after the base is the judged round's own output and is read live.
    let text;
    const atBase = base && !gitFailed && git_ok(root, ['cat-file', '-e', `${base}:${p}`]);
    if (atBase && changed.includes(p)) reasons.push(`prior_report_changed:${p}`);
    try {
      text = atBase ? git(root, ['show', `${base}:${p}`]) : fs.readFileSync(path.resolve(root, p), 'utf8');
    } catch {
      reasons.push(`prior_report_unreadable:${p}`);
      continue;
    }
    const m = markerOfText(text);
    if (m === true) reasons.push(`security_relevant:${p}`);
    else if (m === null) reasons.push(`security_marker_absent:${p}`);
  }
  if (token && roleReports[token].length === 0) reasons.push(`security_marker_absent:${token}`);

  if (reasons.length === 0) {
    return { mode: 'delta', reasons, base, head, spec_path: specPath, changed_paths: changed, prior_reports: priorReports };
  }
  return { mode: 'full', reasons, base, head, spec_path: specPath, changed_paths: changed, prior_reports: priorReports };
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

// The head a verdict is stamped with when it cannot be placed (D4): forty zeros are a
// valid HEAD_SHA_RE value that is never a commit, so the next round's ancestry test
// fails and the round runs full. The stamp still lands, so the role is not stuck.
export { AMBIGUOUS_HEAD };

// The unverdicted dispatches of one role: every check_dispatched of the ref and role
// after the last check_verdict of that role, in append order.
function unjudgedDispatches(events, ref, roleToken) {
  const lastV = lastIndexWhere(events, (e) => e && e.event === 'check_verdict' && e.ref === ref
    && e.payload && e.payload.role === roleToken);
  const out = [];
  for (let i = lastV + 1; i < events.length; i += 1) {
    const e = events[i];
    if (e && e.event === 'check_dispatched' && e.ref === ref && e.payload && e.payload.role === roleToken) out.push({ idx: i, payload: e.payload });
  }
  return out;
}

// D4: the verdict base is the head the checker was actually handed. A --confirm re-tick
// while a check is in flight appends a newer check_dispatched, so the base is the
// EARLIEST unjudged dispatch of the role, never the latest. When the other unjudged
// heads do not all descend from it (or git cannot say), the base is ambiguous and the
// stamp carries AMBIGUOUS_HEAD: fail closed, no delta from it.
function verdictBase(root, dispatches) {
  const first = dispatches[0].payload.head;
  if (!HEX40.test(String(first))) return AMBIGUOUS_HEAD;
  for (const d of dispatches.slice(1)) {
    const h = d.payload.head;
    if (h === first) continue;
    if (!HEX40.test(String(h)) || !git_ok(root, ['merge-base', '--is-ancestor', first, h])) return AMBIGUOUS_HEAD;
  }
  return first;
}

// planCheckStamps({ root, statePath, ref, dispatchRole }) -> [{ event, role, head, status|seen }]
// in append order. Pure: reads EVENTS, STATE and git, writes nothing.
export function planCheckStamps({ root, statePath = null, ref, dispatchRole = null }) {
  const head = gitHead(root);
  if (head === null || !ref) return [];
  const events = readEvents(root);
  const state = readCheckState(statePath || path.join(root, 'docs/ai/STATE.yaml'));
  if (!state) return [];
  const stamps = [];
  const verdictPlanned = new Set();
  for (const roleToken of ['validation', 'code_review']) {
    const open = unjudgedDispatches(events, ref, roleToken);
    if (open.length === 0) continue;
    const cur = currentIdentity(state, roleToken, ref);
    if (cur && cur.status && isNewer(roleToken, open[0].payload.seen, cur)) {
      const stamp = { event: 'check_verdict', role: roleToken, head: verdictBase(root, open), status: cur.status };
      const marker = markerOfRole(root, state, roleToken, ref);
      if (marker !== null) stamp.security_relevant = marker;
      stamps.push(stamp);
      verdictPlanned.add(roleToken);
    }
  }
  const dispatchToken = tokenOfRole(dispatchRole);
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
