// check-binding.mjs - the check_binding block of docs/ai/STATE.yaml
// (docs/specs/SPEC-0251-spec-recheck-verdict-binding.md, D1 to D4 and D13).
//
// A judged Validation or Code Review round is recorded in STATE by `state.mjs bind-check`,
// the one writer, and `recheckMode` (lib/recheck.mjs) compares that record when it decides
// a later round. Where docs/ai/STATE.yaml is gitignored, no commit, amend, rebase, squash, merge
// or replace object carries the block; nothing here checks that it is (fu-recheck-state-tracked-premise).
// This module owns reading the block, planning its writes, the
// D4 comparisons and the git environment those reads run in.
//
// A second block, check_sticky, keeps one record per ref: the security flag and every spec path
// that ref has been recorded with. Two commands write it, both through putStickyRaise: state.mjs
// bind-check (the ref it binds) and ride-handoff.mjs out (the origin entry of its ref, into the
// worktree STATE). The block replacement, the metrics flush, reset-block and check-state have no
// code that opens it. recheckMode compares the entry for the ref in the STATE file it decides.
// The record is per STATE file: a STATE file with no raised entry for the ref starts unraised
// (a worktree STATE ride-handoff.mjs out did not write, a STATE recreated in the same checkout,
// the origin STATE after a worktree raised the flag; nothing carries a record back).
//
// Wording rule (D9): a comment here names the comparison a check makes; it states no more.
// Residual: the comparisons read docs/ai/STATE.yaml and the bound report files as they are
// on disk, so an edit to either made outside state.mjs before the tick that binds or reads
// it, and a verdict the orchestrator itself records for the dispatched role with a new
// report, are taken as written; no shape outside the D5 table is claimed.
//
// Node stdlib plus the repo's own line engine. No new dependency.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { duplicateKeys, splitLines } from './state-core.mjs';
import { ensureBlock, findBlock, listFieldLines, nowIso, readScalar, scalarLine, unquoteScalar, yq } from './state-engine.mjs';

export const BINDING_BLOCK = 'check_binding';
export const STICKY_BLOCK = 'check_sticky';
export const ROLE_KEYS = ['validation', 'code_review'];
export const HEX40 = /^[0-9a-f]{40}$/;
const HEX64 = /^[0-9a-f]{64}$/;
// Forty zeros are a well-formed head that is never a commit: the ancestry comparison fails.
export const AMBIGUOUS_HEAD = '0'.repeat(40);

// --- git, in an environment that applies no replace object ---------------------------

// Every GIT_* variable of the inherited environment is removed and replace objects are
// switched off, so a replace ref under any GIT_REPLACE_REF_BASE, and a grafts file, are not
// applied to the reads recheckMode and bind-check make.
export function gitEnv(base = process.env) {
  const kept = {};
  for (const [k, v] of Object.entries(base)) if (!k.startsWith('GIT_')) kept[k] = v;
  return { ...kept, GIT_NO_REPLACE_OBJECTS: '1' };
}

export function gitOut(root, args) {
  return execFileSync('git', args, {
    cwd: root, encoding: 'utf8', env: gitEnv(), stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024,
  });
}

export function gitBytes(root, args) {
  return execFileSync('git', args, {
    cwd: root, env: gitEnv(), stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 64 * 1024 * 1024,
  });
}

export function gitOk(root, args) {
  try {
    gitOut(root, args);
    return true;
  } catch {
    return false;
  }
}

export function gitHeadOf(root) {
  try {
    const h = gitOut(root, ['rev-parse', 'HEAD']).trim();
    return HEX40.test(h) ? h : null;
  } catch {
    return null;
  }
}

// The realpath of the work tree root, or null when git cannot say.
export function checkoutOf(root) {
  try {
    return fs.realpathSync(gitOut(root, ['rev-parse', '--show-toplevel']).trim());
  } catch {
    return null;
  }
}

// True when a ref under refs/replace/ or an info/grafts file exists; true also when git
// cannot say (an unreadable repository is not one the reads can vouch for).
export function replaceRefsPresent(root) {
  try {
    if (gitOut(root, ['for-each-ref', '--count=1', 'refs/replace/']).trim() !== '') return true;
    const common = path.resolve(root, gitOut(root, ['rev-parse', '--git-common-dir']).trim());
    return fs.existsSync(path.join(common, 'info', 'grafts'));
  } catch {
    return true;
  }
}

export function sha256OfFile(root, p) {
  try {
    return crypto.createHash('sha256').update(fs.readFileSync(path.resolve(root, p))).digest('hex');
  } catch {
    return null;
  }
}

// --- the security_relevant marker of one report text ------------------------------------

const FENCE_OPEN_RE = /^ {0,3}(`{3,}|~{3,})(.*)$/;
const FENCE_CLOSE_RE = /^ {0,3}(`{3,}|~{3,})[ \t]*$/;
const MARK_TRUE_RE = /^security_relevant: true\s*$/;
const MARK_FALSE_RE = /^security_relevant: false\s*$/;
const MARK_ANY_RE = /^security_relevant:/;

// A marker line counts only at column 0 outside every fenced code block (D13). A fence opens
// on a line of at most three spaces and three or more backticks or tildes (a backtick fence
// whose info string holds a backtick is no fence) and closes on a line of the same character,
// at least as many of them, and nothing else; an unclosed fence runs to the end of the text.
// Result: true when a counted line says true; null when a fence is still open; false when
// exactly one counted marker line exists and it says false; null otherwise.
export function markerOfText(text) {
  let fence = null;
  let sawTrue = false;
  let any = 0;
  let falses = 0;
  for (const line of String(text).split(/\r?\n/)) {
    if (fence !== null) {
      const close = FENCE_CLOSE_RE.exec(line);
      if (close && close[1][0] === fence.ch && close[1].length >= fence.len) fence = null;
      continue;
    }
    const open = FENCE_OPEN_RE.exec(line);
    if (open && !(open[1][0] === '`' && open[2].includes('`'))) {
      fence = { ch: open[1][0], len: open[1].length };
      continue;
    }
    if (!MARK_ANY_RE.test(line)) continue;
    any += 1;
    if (MARK_TRUE_RE.test(line)) sawTrue = true;
    else if (MARK_FALSE_RE.test(line)) falses += 1;
  }
  if (sawTrue) return true;
  if (fence !== null) return null;
  return any === 1 && falses === 1 ? false : null;
}

// The marker of one check role: true when any report says true, false when there is at least
// one report and every one says false, null otherwise (an unreadable report is null).
export function markerOfReports(root, paths) {
  if (paths.length === 0) return null;
  let allFalse = true;
  for (const p of paths) {
    let text;
    try { text = fs.readFileSync(path.resolve(root, p), 'utf8'); } catch { return null; }
    const m = markerOfText(text);
    if (m === true) return true;
    if (m !== false) allFalse = false;
  }
  return allFalse ? false : null;
}

// --- STATE (read only) ------------------------------------------------------------------

export function refMatches(vref, ref) {
  if (vref == null || ref == null) return false;
  return vref === ref || String(vref).split('/').includes(ref);
}

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
    if (/^ {2}- /.test(l)) cur = { ref: null, spec: null };
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

// The focus spec path STATE names: the work item spec_path, else current_focus.spec_path.
export function stateSpecPath(lines, ref) {
  return (ref && workItemSpecPath(lines, ref)) || readScalar(lines, 'current_focus', 'spec_path');
}

export function readCheckStateLines(lines) {
  const focusRef = readScalar(lines, 'current_focus', 'ref_id');
  return {
    focusRef,
    specPath: stateSpecPath(lines, focusRef),
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

// readCheckState(statePath) -> the fields the delta decision and the stamps read, or null
// when STATE is missing or unreadable.
export function readCheckState(statePath) {
  let raw;
  try {
    raw = fs.readFileSync(statePath, 'utf8');
  } catch {
    return null;
  }
  return readCheckStateLines(splitLines(raw).lines);
}

// The report paths STATE names for one check role, for the ref.
export function roleReportsOf(state, token, ref) {
  if (token === 'validation') {
    return refMatches(state.validation.ref, ref) ? state.validation.evidencePaths.filter((p) => /\.md$/i.test(p)) : [];
  }
  return state.review.scopeRef == null || refMatches(state.review.scopeRef, ref) ? state.review.reportPaths : [];
}

// pass or fail when STATE holds a verdict of the role for the ref, else null.
function verdictStatusOf(state, token, ref) {
  if (token === 'validation') {
    const v = state.validation;
    return (v.status === 'pass' || v.status === 'fail') && refMatches(v.ref, ref) ? v.status : null;
  }
  const r = state.review;
  return (r.status === 'pass' || r.status === 'fail') && (r.scopeRef == null || refMatches(r.scopeRef, ref)) ? r.status : null;
}

// --- the block: parse -------------------------------------------------------------------

const TOP_SCALARS = new Set(['ref_id', 'checkout', 'spec_path', 'security_sticky']);
const ROLE_SCALARS = new Set(['head', 'status', 'security', 'bound_at_utc']);
const ROLE_LISTS = new Set(['pending_heads', 'pending_reports', 'reports', 'digests']);

function emptyRole() {
  return { pendingHeads: [], pendingReports: [], head: null, status: null, reports: [], digests: [], security: undefined, boundAt: null };
}

function emptyBinding() {
  return { present: false, problems: [], refId: null, checkout: null, specPath: null, securitySticky: false,
    roles: { validation: emptyRole(), code_review: emptyRole() } };
}

function scalarOf(raw) {
  const v = unquoteScalar(raw.trim());
  return v === 'null' || v === '' ? null : v;
}

function parseBlock(lines, b, out) {
  if (lines[b.start].slice(lines[b.start].indexOf(':') + 1).trim() !== '') out.problems.push('block_header_inline');
  const seen = new Set();
  let list = null;
  for (let i = b.start + 1; i < b.end; i += 1) {
    const l = lines[i];
    if (l.trim() === '' || l.startsWith('#')) continue;
    let m = /^ {2}([a-z_]+):(?:\s+(.*))?$/.exec(l);
    if (m) {
      list = null;
      const key = m[1];
      const rest = m[2] === undefined ? '' : m[2].trim();
      if (seen.has(key)) { out.problems.push(`duplicate_key:${key}`); continue; }
      seen.add(key);
      const role = ROLE_KEYS.find((r) => key.startsWith(`${r}_`));
      const field = role ? key.slice(role.length + 1) : null;
      if (TOP_SCALARS.has(key)) {
        const v = scalarOf(rest);
        if (key === 'ref_id') out.refId = v;
        else if (key === 'checkout') out.checkout = v;
        else if (key === 'spec_path') out.specPath = v;
        else if (v === 'true' || v === 'false') out.securitySticky = v === 'true';
        else out.problems.push('security_sticky');
      } else if (role && ROLE_LISTS.has(field)) {
        const target = out.roles[role];
        const prop = { pending_heads: 'pendingHeads', pending_reports: 'pendingReports', reports: 'reports', digests: 'digests' }[field];
        if (rest === '[]') target[prop] = [];
        else if (rest === '') list = target[prop];
        else out.problems.push(`list_inline:${key}`);
      } else if (role && ROLE_SCALARS.has(field)) {
        const target = out.roles[role];
        const v = scalarOf(rest);
        if (field === 'head') target.head = v;
        else if (field === 'status') target.status = v;
        else if (field === 'bound_at_utc') target.boundAt = v;
        else if (v === 'true') target.security = true;
        else if (v === 'false') target.security = false;
        else if (v === null) target.security = null;
        else out.problems.push(`${key}`);
      } else {
        out.problems.push(`unknown_key:${key}`);
      }
      continue;
    }
    m = /^ {4}- (.*)$/.exec(l);
    if (m && list !== null) { list.push(unquoteScalar(m[1].trim())); continue; }
    out.problems.push(`unparsed_line:${i - b.start}`);
  }
  if (out.refId === null) out.problems.push('ref_id');
  for (const token of ROLE_KEYS) {
    const r = out.roles[token];
    for (const h of r.pendingHeads) if (!HEX40.test(h)) out.problems.push(`${token}_pending_heads`);
    const verdict = r.status !== null || r.head !== null || r.reports.length > 0 || r.digests.length > 0;
    if (!verdict) continue;
    if (r.status !== 'pass' && r.status !== 'fail') out.problems.push(`${token}_status`);
    if (r.head === null || !HEX40.test(r.head)) out.problems.push(`${token}_head`);
    if (r.security === undefined) out.problems.push(`${token}_security`);
    if (r.reports.length === 0 || r.reports.length !== r.digests.length) out.problems.push(`${token}_reports`);
    if (!r.digests.every((d) => HEX64.test(d))) out.problems.push(`${token}_digests`);
  }
}

// readBindingBlock(lines) -> the parsed block, `present: false` when STATE holds none. Any
// field that does not parse as the D1 table says, an unknown key, a repeated key or a
// duplicate top-level key of STATE is listed in `problems`.
export function readBindingBlock(lines) {
  const out = emptyBinding();
  for (const d of duplicateKeys(lines)) out.problems.push(`duplicate_top_level_key:${d.key}`);
  const b = findBlock(lines, BINDING_BLOCK);
  if (!b) return out;
  out.present = true;
  parseBlock(lines, b, out);
  return out;
}

// readBinding(statePath) -> the parsed block; `present: false` when STATE is unreadable.
export function readBinding(statePath) {
  let raw;
  try {
    raw = fs.readFileSync(statePath, 'utf8');
  } catch {
    return emptyBinding();
  }
  const { lines } = splitLines(raw);
  return readBindingBlock(lines);
}

// The block when it names this ref and holds a verdict of the role, else null.
export function boundBinding(binding, ref, token) {
  if (!binding.present || !token || binding.refId !== ref) return null;
  return binding.roles[token].status !== null ? binding : null;
}

// --- the D4 comparisons -----------------------------------------------------------------

// judgeBinding({ root, binding, token, head, ownDispatch }) -> { reasons, base }. `base` is the
// bound role head, null when the block does not parse. `ownDispatch` is set by canon.mjs, which
// builds the payload of the round a tick has just dispatched: a pending list whose only entry is
// the current head is that round's own record and gives no binding_pending.
export function judgeBinding({ root, binding, token, head = null, ownDispatch = false, sticky = null }) {
  const reasons = [];
  if (binding.problems.length > 0) {
    reasons.push('binding_ambiguous');
    return { reasons, base: null };
  }
  const bound = binding.roles[token];
  if (binding.checkout !== checkoutOf(root)) reasons.push('binding_other_checkout');
  const ownRecord = ownDispatch && bound.pendingHeads.length === 1 && bound.pendingHeads[0] === head;
  if (bound.pendingHeads.length > 0 && !ownRecord) reasons.push(`binding_pending:${token}`);
  for (let i = 0; i < bound.reports.length; i += 1) {
    const p = bound.reports[i];
    if (sha256OfFile(root, p) !== bound.digests[i]) reasons.push(`binding_report_changed:${p}`);
  }
  if (binding.securitySticky === true || binding.roles.validation.security === true
    || binding.roles.code_review.security === true) reasons.push('security_relevant:binding');
  // The per-ref record outlives every replacement of the block above; it is compared by name.
  if (sticky === null || sticky.problems.length > 0) reasons.push('sticky_record_ambiguous');
  else {
    const entry = sticky.entries.get(binding.refId);
    if (entry === undefined) reasons.push('sticky_record_absent:binding');
    else if (entry.security === true) reasons.push('security_relevant:sticky');
  }
  if (bound.security !== false) reasons.push(`security_marker_absent:binding:${token}`);
  if (replaceRefsPresent(root)) reasons.push('replace_refs_present');
  return { reasons, base: bound.head };
}

// --- the block: serialize ---------------------------------------------------------------

function copyRole(r) {
  return { ...r, pendingHeads: [...r.pendingHeads], pendingReports: [...r.pendingReports], reports: [...r.reports], digests: [...r.digests] };
}

function carry(prior, lines, ref, root) {
  return {
    refId: ref,
    checkout: prior.checkout ?? checkoutOf(root),
    specPath: prior.specPath ?? stateSpecPath(lines, ref),
    securitySticky: prior.securitySticky === true,
    roles: { validation: copyRole(prior.roles.validation), code_review: copyRole(prior.roles.code_review) },
  };
}

function serialize(m) {
  const out = [`${BINDING_BLOCK}:`, scalarLine(2, 'ref_id', yq(m.refId)), scalarLine(2, 'checkout', m.checkout === null ? 'null' : yq(m.checkout)),
    scalarLine(2, 'spec_path', m.specPath === null ? 'null' : yq(m.specPath)), scalarLine(2, 'security_sticky', m.securitySticky ? 'true' : 'false')];
  for (const token of ROLE_KEYS) {
    const r = m.roles[token];
    if (r.pendingHeads.length > 0) out.push(...listFieldLines(2, `${token}_pending_heads`, r.pendingHeads));
    if (r.pendingReports.length > 0) out.push(...listFieldLines(2, `${token}_pending_reports`, r.pendingReports));
    if (r.status === null) continue;
    out.push(scalarLine(2, `${token}_head`, r.head), scalarLine(2, `${token}_status`, r.status));
    out.push(...listFieldLines(2, `${token}_reports`, r.reports), ...listFieldLines(2, `${token}_digests`, r.digests));
    out.push(scalarLine(2, `${token}_security`, r.security === null ? 'null' : String(r.security)));
    if (r.boundAt) out.push(scalarLine(2, `${token}_bound_at_utc`, r.boundAt));
  }
  return out;
}

// Replace the block (or create it before updated_at_utc) with `blockLines`, keeping the blank
// lines that followed the old block.
function putBlock(lines, blockLines, key = BINDING_BLOCK) {
  const existing = findBlock(lines, key);
  if (!existing) ensureBlock(lines, key, []);
  const b = findBlock(lines, key);
  let tail = b.end;
  while (tail > b.start + 1 && lines[tail - 1].trim() === '') tail -= 1;
  const blanks = lines.slice(tail, b.end);
  lines.splice(b.start, b.end - b.start, ...blockLines, ...(blanks.length ? blanks : ['']));
}

// --- the check_sticky block: one record per ref, each write ORs the flag and adds paths ----

// readStickyRecords(lines) -> { present, problems, entries: Map(ref_id -> { security, specPaths }) }.
// Every list item is one JSON object {"ref_id": string, "security": boolean, "spec_paths": [string]};
// an item that is anything else, a repeated ref_id or an unknown key is listed in `problems`.
export function readStickyRecords(lines) {
  const out = { present: false, problems: [], entries: new Map(), keptLines: [], headerLine: null };
  const b = findBlock(lines, STICKY_BLOCK);
  if (!b) return out;
  out.present = true;
  if (lines[b.start].slice(lines[b.start].indexOf(':') + 1).trim() !== '') { out.problems.push('sticky_header_inline'); out.headerLine = lines[b.start]; }
  for (let i = b.start + 1; i < b.end; i += 1) {
    const l = lines[i];
    if (l.trim() === '' || l.startsWith('#')) continue;
    const m = /^ {2}- (.*)$/.exec(l);
    if (!m) { out.problems.push(`sticky_unparsed_line:${i - b.start}`); out.keptLines.push(l); continue; }
    let o;
    try { o = JSON.parse(unquoteScalar(m[1].trim())); } catch { out.problems.push(`sticky_item:${i - b.start}`); out.keptLines.push(l); continue; }
    const okKeys = o && typeof o === 'object' && !Array.isArray(o)
      && Object.keys(o).sort().join(',') === 'ref_id,security,spec_paths';
    if (!okKeys || typeof o.ref_id !== 'string' || o.ref_id === '' || typeof o.security !== 'boolean'
      || !Array.isArray(o.spec_paths) || !o.spec_paths.every((x) => typeof x === 'string' && x !== '')) {
      out.problems.push(`sticky_item:${i - b.start}`);
      out.keptLines.push(l);
      continue;
    }
    if (out.entries.has(o.ref_id)) {
      // A repeated ref is a problem for the reader; the entry keeps the highest flag and every path.
      const first = out.entries.get(o.ref_id);
      out.problems.push(`sticky_duplicate_ref:${i - b.start}`);
      out.entries.set(o.ref_id, { security: first.security || o.security, specPaths: [...new Set([...first.specPaths, ...o.spec_paths])] });
      continue;
    }
    out.entries.set(o.ref_id, { security: o.security, specPaths: [...new Set(o.spec_paths)] });
  }
  return out;
}

export function readSticky(statePath) {
  let raw;
  try {
    raw = fs.readFileSync(statePath, 'utf8');
  } catch {
    return null;
  }
  return readStickyRecords(splitLines(raw).lines);
}

function serializeSticky(entries, { headerLine = null, keptLines = [] } = {}) {
  const out = [headerLine === null ? `${STICKY_BLOCK}:` : headerLine];
  for (const ref of [...entries.keys()].sort()) {
    const e = entries.get(ref);
    out.push(`  - ${yq(JSON.stringify({ ref_id: ref, security: e.security === true, spec_paths: [...new Set(e.specPaths)].sort() }))}`);
  }
  out.push(...keptLines);
  return out;
}

// putStickyRaise(lines, ref, { security, specPaths, unknownPrior }) -> the entry now recorded.
// The flag written is the OR of the recorded flag and the given one, the paths are the union.
// A record that does not parse is rebuilt from its parseable items; the lines that did not parse
// (and an inline header) are kept byte for byte, so the reader stays ambiguous for every ref they
// might have named, and a repeated ref is merged to the highest flag and the union of its paths.
// This ref is written with the flag raised; `unknownPrior` raises it as well (a prior block that
// did not parse).
export function putStickyRaise(lines, ref, { security = false, specPaths = [], unknownPrior = false } = {}) {
  const cur = readStickyRecords(lines);
  const had = cur.entries.get(ref);
  const entry = {
    security: (had ? had.security : false) || security === true || unknownPrior === true || cur.problems.length > 0,
    specPaths: [...new Set([...(had ? had.specPaths : []), ...specPaths.filter((x) => typeof x === 'string' && x !== '')])],
  };
  const entries = new Map(cur.entries);
  entries.set(ref, entry);
  putBlock(lines, serializeSticky(entries, { headerLine: cur.headerLine, keptLines: cur.keptLines }), STICKY_BLOCK);
  return entry;
}

// --- bind-check: planning ---------------------------------------------------------------

function sameSet(a, b) {
  return a.length === b.length && [...a].sort().join('\n') === [...b].sort().join('\n');
}

function isAncestor(root, a, b) {
  try {
    gitOut(root, ['merge-base', '--is-ancestor', a, b]);
    return true;
  } catch {
    return false;
  }
}

// planBindCheck({ lines, root, on, role, ref }) -> { lines, note } or null when nothing is to
// be written. Reads `lines` (STATE), the report files STATE names and git in `root`; it takes
// no head, report, digest or marker from its caller.
export function planBindCheck({ lines, root, on, role, ref }) {
  const state = readCheckStateLines(lines);
  const parsed = readBindingBlock(lines);
  // A block of another ref, one that does not parse, or one written by another checkout is
  // replaced as a whole; its verdict fields are never carried.
  const usable = parsed.present && parsed.problems.length === 0 && parsed.refId === ref
    && parsed.checkout === checkoutOf(root) ? parsed : null;
  const prior = usable ?? emptyBinding();
  const head = gitHeadOf(root);
  if (head === null) return null;
  const reports = roleReportsOf(state, role, ref);
  const next = carry(prior, lines, ref, root);
  const r = next.roles[role];
  // What a replaced block of this ref said is folded into the per-ref record before the block goes.
  const gone = !usable && parsed.present && parsed.problems.length === 0 && parsed.refId === ref ? parsed : null;
  const goneSecurity = gone !== null && (gone.securitySticky === true || gone.roles.validation.security === true
    || gone.roles.code_review.security === true);
  const unknownPrior = parsed.present && parsed.problems.length > 0;
  const goneSpecPaths = [gone && gone.specPath, next.specPath].filter(Boolean);
  const writeSticky = (out, security) => {
    const rec = putStickyRaise(out, ref, { security: security || goneSecurity, specPaths: goneSpecPaths, unknownPrior });
    next.securitySticky = rec.security;
    return rec;
  };

  if (on === 'dispatch') {
    const samePending = r.pendingHeads.length > 0 && r.pendingHeads[r.pendingHeads.length - 1] === head && sameSet(reports, r.pendingReports);
    if (samePending) return null;
    if (r.pendingHeads.length === 0) r.pendingReports = reports;
    r.pendingHeads.push(head);
    const out = [...lines];
    writeSticky(out, prior.securitySticky === true);
    putBlock(out, serialize(next));
    return { lines: out, note: `dispatch ${role} pending head ${head.slice(0, 12)}` };
  }

  if (usable === null || r.pendingHeads.length === 0) return null;
  const status = verdictStatusOf(state, role, ref);
  if (status === null) return null;
  const fresh = reports.filter((p) => !r.pendingReports.includes(p));
  if (fresh.length === 0) return null;
  let bound = r.pendingHeads[0];
  for (const h of r.pendingHeads.slice(1)) if (!isAncestor(root, bound, h)) bound = AMBIGUOUS_HEAD;
  if (!HEX40.test(bound)) bound = AMBIGUOUS_HEAD;
  const marker = markerOfReports(root, reports);
  const sticky = prior.securitySticky === true ? true : marker === true;
  next.securitySticky = sticky;
  next.roles[role] = {
    pendingHeads: [],
    pendingReports: [],
    head: bound,
    status,
    reports,
    digests: reports.map((p) => sha256OfFile(root, p)),
    security: marker,
    boundAt: nowIso(),
  };
  if (next.roles[role].digests.includes(null)) return null;
  const out = [...lines];
  writeSticky(out, sticky);
  putBlock(out, serialize(next));
  return { lines: out, note: `verdict ${role} ${status} bound head ${bound.slice(0, 12)}` };
}

// --- the flush ---------------------------------------------------------------------------

// Partial reset of flushed refs: when the block names one of them, both roles' verdict and
// pending fields are cleared and ref_id, checkout, spec_path and security_sticky are kept. A
// block that does not parse is removed. Returns true when STATE changed.
export function clearCheckBinding(lines, flushedRefs) {
  const parsed = readBindingBlock(lines);
  if (!parsed.present) return false;
  if (parsed.problems.length > 0) return removeCheckBinding(lines);
  if (!flushedRefs.includes(parsed.refId)) return false;
  const next = { refId: parsed.refId, checkout: parsed.checkout, specPath: parsed.specPath, securitySticky: parsed.securitySticky,
    roles: { validation: emptyRole(), code_review: emptyRole() } };
  putBlock(lines, serialize(next));
  return true;
}

// Full reset: the block goes. Returns true when STATE changed.
export function removeCheckBinding(lines) {
  const b = findBlock(lines, BINDING_BLOCK);
  if (!b) return false;
  lines.splice(b.start, b.end - b.start);
  return true;
}
