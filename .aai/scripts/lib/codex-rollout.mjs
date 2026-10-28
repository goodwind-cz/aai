// codex-rollout.mjs — read-only Codex rollout-log usage reader
// (spec-codex-usage-missing-from-run-budgets, D1..D6, D12).
//
// Reads ONLY metadata-shaped lines (session_meta, token_usage_record,
// event_msg/token_count, compacted, response_item/compaction). Never keeps or
// returns message text; nothing is written. Node stdlib only.

import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const ROLLOUT_DIRS = ['sessions', 'archived_sessions'];
const META_KEYS = ['id', 'session_id', 'parent_thread_id', 'timestamp', 'cwd', 'source'];
const COMPONENTS = ['input_tokens', 'output_tokens', 'total_tokens'];
const SUBSETS = [['cached_input_tokens', 'cached_input_tokens_subset'], ['reasoning_output_tokens', 'reasoning_output_tokens_subset']];
const MAX_META_SCAN_LINES = 50;

export function codexHome(env) {
  const e = env || process.env;
  const home = (e && e.HOME) || os.homedir();
  return e && e.CODEX_HOME ? path.resolve(e.CODEX_HOME) : path.join(home, '.codex');
}

function num(v) {
  const n = typeof v === 'number' ? v : NaN;
  if (!Number.isFinite(n)) return null;
  return n;
}

function parseTime(v, dflt) {
  if (v === undefined || v === null || v === '') return dflt;
  if (typeof v === 'number') return v;
  const ms = Date.parse(v);
  return Number.isNaN(ms) ? NaN : ms;
}

function unavailable(reason, extra) {
  return { status: 'unavailable', reason, usage: null, ...(extra || {}) };
}

function walk(dir, out) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full, out);
    else if (e.isFile() && e.name.endsWith('.jsonl')) out.push(full);
  }
  return out;
}

export function rolloutRoots(env) {
  const base = codexHome(env);
  return ROLLOUT_DIRS.map((d) => path.join(base, d));
}

export function listRollouts(env) {
  const roots = rolloutRoots(env);
  const readable = roots.filter((r) => { try { return fs.statSync(r).isDirectory(); } catch { return false; } });
  const files = [];
  for (const r of readable) walk(r, files);
  return { roots, readable, files: files.sort() };
}

function pickMeta(payload) {
  const out = {};
  for (const k of META_KEYS) out[k] = payload[k] === undefined ? null : payload[k];
  return out;
}

// First session_meta of a file (identity), read in chunks so a huge file or a
// huge instructions line never has to be held whole just to learn who owns it.
function firstMeta(file) {
  let fd;
  try { fd = fs.openSync(file, 'r'); } catch { return null; }
  try {
    const buf = Buffer.alloc(65536);
    let pending = '';
    let lines = 0;
    for (;;) {
      const n = fs.readSync(fd, buf, 0, buf.length, null);
      if (n === 0) break;
      pending += buf.toString('utf8', 0, n);
      let nl;
      while ((nl = pending.indexOf('\n')) >= 0) {
        const line = pending.slice(0, nl);
        pending = pending.slice(nl + 1);
        if (++lines > MAX_META_SCAN_LINES) return null;
        if (!line.includes('session_meta')) continue;
        try {
          const obj = JSON.parse(line);
          if (obj && obj.type === 'session_meta' && obj.payload) return pickMeta(obj.payload);
        } catch { /* keep scanning */ }
      }
    }
    if (pending.includes('session_meta')) {
      try {
        const obj = JSON.parse(pending);
        if (obj && obj.type === 'session_meta' && obj.payload) return pickMeta(obj.payload);
      } catch { /* none */ }
    }
    return null;
  } finally { fs.closeSync(fd); }
}

// Parse one rollout file into the metadata-only events observe() needs.
function readFile(file) {
  const text = fs.readFileSync(file, 'utf8');
  const lines = text.split('\n');
  const terminated = text.endsWith('\n');
  while (lines.length && lines[lines.length - 1].trim() === '') lines.pop();
  let ownMeta = null;
  const res = { ownMeta: null, records: [], snapshots: [], compactions: [], malformed: 0, partialTail: false };
  lines.forEach((line, i) => {
    if (line.trim() === '') return;
    let obj;
    try { obj = JSON.parse(line); } catch {
      if (i === lines.length - 1 && !terminated) res.partialTail = true; else res.malformed += 1;
      return;
    }
    if (!obj || typeof obj !== 'object') return;
    const p = obj.payload && typeof obj.payload === 'object' ? obj.payload : {};
    const ts = Date.parse(obj.timestamp);
    if (obj.type === 'session_meta') {
      if (ownMeta === null) ownMeta = obj.payload;
    } else if (obj.type === 'token_usage_record') {
      res.records.push({ ts, thread_id: p.thread_id, response_id: p.response_id, usage: p.usage });
    } else if (obj.type === 'event_msg' && p.type === 'token_count') {
      const t = p.info && p.info.total_token_usage;
      if (t && typeof t === 'object') res.snapshots.push({ ts, ...t });
    } else if (obj.type === 'compacted' || (obj.type === 'response_item' && p.type === 'compaction')) {
      res.compactions.push(ts);
    }
  });
  if (ownMeta) res.ownMeta = pickMeta(ownMeta);
  res.digest = crypto.createHash('sha1').update(text).digest('hex');
  return res;
}

function sumComponent(list, key, reasons, optional) {
  let total = 0;
  for (const u of list) {
    const n = num(u && u[key]);
    if (n === null) { if (!optional) reasons.push(`missing_field:${key}`); return null; }
    total += n;
  }
  return total;
}

function recordsUsage(counted, reasons) {
  const usages = counted.map((r) => r.usage);
  const usage = {};
  const input = sumComponent(usages, 'input_tokens', reasons);
  const output = sumComponent(usages, 'output_tokens', reasons);
  const total = sumComponent(usages, 'total_tokens', reasons);
  const cached = sumComponent(usages, 'cached_input_tokens', reasons, true);
  const reasoning = sumComponent(usages, 'reasoning_output_tokens', reasons, true);
  usage.input_tokens = input;
  usage.output_tokens = output;
  usage.total_tokens = total;
  usage.cached_input_tokens_subset = cached;
  usage.reasoning_output_tokens_subset = reasoning;
  for (const u of usages) {
    const i = num(u && u.input_tokens); const o = num(u && u.output_tokens); const t = num(u && u.total_tokens);
    if (i !== null && o !== null && t !== null && t !== i + o) { reasons.push('inconsistent_total'); break; }
  }
  return usage;
}

function snapshotsUsage(snaps, fromMs, toMs, compactions, reasons) {
  const keys = [...COMPONENTS, ...SUBSETS.map((s) => s[0])];
  const acc = {}; const missing = new Set();
  const zero = { ts: -Infinity };
  for (const k of keys) { acc[k] = 0; zero[k] = 0; }
  let prev = zero;
  for (const cur of snaps) {
    if (cur.ts >= toMs) break;
    let reset = false;
    if (cur.total_tokens < prev.total_tokens) {
      reset = true;
    }
    const was = prev;
    prev = cur;
    if (cur.ts < fromMs) continue;
    for (const k of keys) {
      const c = num(cur[k]); const b = num(was[k]);
      if (c === null || b === null) { missing.add(k); continue; }
      acc[k] += reset ? c : Math.max(0, c - b);
    }
    if (reset && !reasons.includes('counter_reset')) reasons.push('counter_reset');
  }
  const usage = {};
  for (const k of keys) {
    const sub = SUBSETS.find((s) => s[0] === k);
    const outKey = sub ? sub[1] : k;
    if (missing.has(k)) { if (!sub) reasons.push(`missing_field:${k}`); usage[outKey] = null; } else usage[outKey] = acc[k];
  }
  if (compactions.some((c) => c >= fromMs && c < toMs)) reasons.push('cumulative_may_omit_compaction');
  return usage;
}

// Thread files: every rollout whose FIRST session_meta id equals the thread id.
export function findThreadFiles(listing, threadId) {
  const hits = [];
  for (const file of listing.files) {
    const meta = firstMeta(file);
    if (meta && meta.id === threadId) hits.push({ file, meta });
  }
  return hits;
}

export function resolveThread(thread, env) {
  const e = env || process.env;
  if (thread === 'auto') return e.CODEX_THREAD_ID ? { id: e.CODEX_THREAD_ID, source: 'env' } : null;
  return thread ? { id: thread, source: 'flag' } : null;
}

// One thread's own usage over [fromMs, toMs); descendants are added by observe().
function observeThread(listing, ident, opts, fromMs, toMs) {
  const hits = findThreadFiles(listing, ident.id);
  if (hits.length === 0) return unavailable('thread_not_found');

  const ownId = ident.id;
  const reasons = [];
  const records = []; const snaps = []; const compactions = [];
  let partialTail = false; let hasRecordEvent = false;
  const digests = new Set(); const noRespDigests = new Set();
  for (const h of hits) {
    const f = readFile(h.file);
    if (!f.ownMeta || f.ownMeta.id !== ownId) continue;
    if (digests.has(f.digest)) continue; // the same rollout copied into sessions/ and archived_sessions/
    digests.add(f.digest);
    if (f.malformed > 0 && !reasons.includes('malformed_line')) reasons.push('malformed_line');
    if (f.partialTail) partialTail = true;
    const metaTs = Date.parse(h.meta.timestamp);
    for (const rec of f.records) {
      if (rec.thread_id !== ownId) continue;
      hasRecordEvent = true;
      if (rec.response_id === undefined || rec.response_id === null) noRespDigests.add(f.digest);
      records.push(rec);
    }
    for (const s of f.snapshots) {
      if (Number.isNaN(s.ts)) { if (!reasons.includes('missing_field:timestamp')) reasons.push('missing_field:timestamp'); continue; }
      if (Number.isNaN(metaTs) || s.ts >= metaTs) snaps.push(s);
    }
    compactions.push(...f.compactions);
  }

  let basis; let usage;
  if (hasRecordEvent) {
    basis = 'response_records';
    const seenResponses = new Map();
    const counted = [];
    for (const rec of records) {
      const ts = rec.ts;
      if (Number.isNaN(ts)) { if (!reasons.includes('missing_field:timestamp')) reasons.push('missing_field:timestamp'); continue; }
      const inWindow = ts >= fromMs && ts < toMs;
      if (!inWindow) continue;
      if (rec.response_id !== undefined && rec.response_id !== null) {
        const sig = JSON.stringify(rec.usage);
        const prior = seenResponses.get(rec.response_id);
        if (prior !== undefined && prior !== sig && !reasons.includes('conflicting_duplicate')) reasons.push('conflicting_duplicate');
        if (seenResponses.has(rec.response_id)) continue;
        seenResponses.set(rec.response_id, sig);
      }
      counted.push(rec);
    }
    // Without response ids, differing copies of one thread's rollout cannot be told apart from new work.
    if (noRespDigests.size > 0 && digests.size > 1) reasons.push('missing_field:response_id');
    usage = recordsUsage(counted, reasons);
  } else if (snaps.length > 0) {
    basis = 'cumulative_snapshot';
    const ordered = snaps.map((s, i) => ({ ...s, i })).sort((a, b) => (a.ts - b.ts) || (a.i - b.i));
    usage = snapshotsUsage(ordered, fromMs, toMs, compactions, reasons);
  } else {
    return unavailable('no_usage_events');
  }
  const degraded = [...new Set(reasons)];
  return {
    status: 'ok',
    thread: ownId,
    thread_source: ident.source,
    interval: { from: opts.from === undefined ? null : opts.from, to: opts.to === undefined ? new Date(toMs).toISOString() : opts.to },
    basis,
    usage,
    degraded,
    partial_tail: partialTail,
  };
}

// Direct children and their metas, indexed from every rollout's FIRST session_meta.
function threadIndex(listing) {
  const metas = new Map(); const children = new Map();
  for (const file of listing.files) {
    const meta = firstMeta(file);
    if (!meta || metas.has(meta.id)) continue;
    metas.set(meta.id, meta);
    if (meta.parent_thread_id) {
      if (!children.has(meta.parent_thread_id)) children.set(meta.parent_thread_id, []);
      children.get(meta.parent_thread_id).push(meta.id);
    }
  }
  return { metas, children };
}

// Root first, then every thread whose parent chain reaches it in the same root session.
function treeIds(index, rootId) {
  const root = index.metas.get(rootId);
  const ids = [rootId]; const seen = new Set(ids); const queue = [rootId];
  while (queue.length) {
    for (const child of index.children.get(queue.shift()) || []) {
      const sess = index.metas.get(child).session_id;
      if (seen.has(child) || (root && root.session_id && sess && sess !== root.session_id)) continue;
      seen.add(child); ids.push(child);
      queue.push(child);
    }
  }
  return ids;
}

function sumKey(list, key) {
  let t = 0;
  for (const o of list) { if (o.usage[key] === null) return null; t += o.usage[key]; }
  return t;
}

function sumObservations(list) {
  const ok = list.filter((o) => o.status === 'ok');
  if (ok.length === 0) return list[0];
  const usage = {};
  for (const k of Object.keys(ok[0].usage)) usage[k] = sumKey(ok, k);
  const bases = [...new Set(ok.map((o) => o.basis))];
  return {
    ...ok[0],
    threads: ok.map((o) => o.thread),
    basis: bases.length === 1 ? bases[0] : 'mixed',
    usage,
    degraded: [...new Set(ok.flatMap((o) => o.degraded))],
    partial_tail: ok.some((o) => o.partial_tail),
  };
}

// observe({thread, from, to, descendants, env}) -> plain object. `thread` may be an id or 'auto'.
export function observe(opts) {
  const env = opts.env || process.env;
  const ident = resolveThread(opts.thread, env);
  if (!ident) return unavailable('thread_identity_unresolved');
  const fromMs = parseTime(opts.from, 0);
  const toMs = parseTime(opts.to, Date.now());
  if (Number.isNaN(fromMs) || Number.isNaN(toMs) || fromMs > toMs) return unavailable('invalid_interval');
  const listing = listRollouts(env);
  if (listing.readable.length === 0) return unavailable('source_unreadable');
  const one = (id) => observeThread(listing, { id, source: ident.source }, opts, fromMs, toMs);
  const rootObs = one(ident.id);
  if (!opts.descendants || (rootObs.status !== 'ok' && rootObs.reason !== 'no_usage_events')) return rootObs;
  const ids = treeIds(threadIndex(listing), ident.id);
  const all = ids.map((id) => (id === ident.id ? rootObs : one(id)));
  const sum = sumObservations(all);
  return sum.status === 'ok' ? sum : rootObs;
}

// attribute({parent, from, to, env}): D8 closed rule. One direct child spawned in
// [from, to) -> that child's tree; otherwise the parent's tree over the window.
export function attribute(opts) {
  const env = opts.env || process.env;
  const fromMs = parseTime(opts.from, NaN);
  const toMs = parseTime(opts.to, NaN);
  if (!opts.parent || Number.isNaN(fromMs) || Number.isNaN(toMs) || fromMs > toMs) return unavailable('invalid_interval');
  const listing = listRollouts(env);
  if (listing.readable.length === 0) return unavailable('source_unreadable');
  const index = threadIndex(listing);
  if (!index.metas.has(opts.parent)) return unavailable('thread_not_found');
  const spawned = (index.children.get(opts.parent) || []).filter((id) => {
    const t = Date.parse(index.metas.get(id).timestamp);
    return t >= fromMs && t < toMs;
  });
  const binding = spawned.length === 1 ? 'thread' : 'interval';
  const target = binding === 'thread' ? spawned[0] : opts.parent;
  const obs = observe({ thread: target, from: opts.from, to: opts.to, descendants: true, env });
  return obs.status === 'ok' ? { ...obs, attribution: binding } : obs;
}
