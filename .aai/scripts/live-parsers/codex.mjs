// codex.mjs — Codex CLI harness parser (SPEC-0114-spec-live-status-dashboard).
//
// Session shape: ~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-<ts>-<uuid>.jsonl
// (session_index.jsonl is a discovery convenience the generator does not
// need — the sessions tree alone is a complete corpus). `type: session_meta`
// carries `payload.session_id` / `payload.cwd`. `type: event_msg` with
// `payload.type: token_count` carries `payload.info.total_token_usage`
// (CUMULATIVE per session, not per turn) and
// `payload.rate_limits.primary.{used_percent, window_minutes, resets_at}`
// (server-authoritative quota, free of any tap).
//
// The parser yields ONE record per token_count event, each carrying that
// event's cumulative total — the generator's accumulation engine (mode
// session_cumulative_last) picks the LAST one per session. Summing every
// yielded record here would multiply the session's real spend by the number
// of token_count events; the parser never does that reduction itself so the
// same records/records-fixture shape backs both TEST-005 (generator-level
// dedup) and a direct read of "what actually happened" per event.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

function roots(env) {
  const e = env || process.env;
  const home = (e && e.HOME) || os.homedir();
  const base = e && e.CODEX_HOME ? path.resolve(e.CODEX_HOME) : path.join(home, '.codex');
  return [path.join(base, 'sessions')];
}

function walk(dir, out) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return out; }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) { walk(full, out); continue; }
    if (e.isFile() && e.name.endsWith('.jsonl')) {
      let st;
      try { st = fs.statSync(full); } catch { continue; }
      out.push({ path: full, mtimeMs: st.mtimeMs, size: st.size });
    }
  }
  return out;
}

function discover(rootList) {
  const out = [];
  for (const root of rootList) walk(root, out);
  return out;
}

// usageTotal(total_token_usage) -> the field's own `total_tokens` when present
// (verified authoritative against the owner's real corpus — it already sums
// input+output+cached, so trusting it directly is more robust than manually
// re-summing a subset of fields that could silently miss a future one, e.g.
// reasoning_output_tokens); falls back to a manual sum for older/partial
// shapes that lack it.
// usageTotal(t) -> Number()-coerced total, or null when `t` is missing/
// wrong-shaped, when a present `total_tokens` fails to coerce to a finite
// number, or when any field in the manual-sum fallback does. The old
// `typeof t.total_tokens === 'number'` guard only protected the authoritative
// branch; the manual-sum fallback below it did `(t.input_tokens || 0) + ...`
// with no coercion at all, so a string field there turned `+` into
// concatenation and reached the rendered page verbatim (BLOCKING-II, code
// review re-review2 — see claude-code.mjs's identical fix and rationale).
function usageTotal(t) {
  if (!t || typeof t !== 'object') return null;
  if (t.total_tokens !== undefined && t.total_tokens !== null) {
    const n = Number(t.total_tokens);
    return Number.isFinite(n) ? n : null;
  }
  const fields = [t.input_tokens, t.output_tokens, t.cached_input_tokens];
  let total = 0;
  for (const f of fields) {
    if (f === undefined || f === null) continue;
    const n = Number(f);
    if (!Number.isFinite(n)) return null;
    total += n;
  }
  return total;
}

function* parse(file, ctx) {
  let raw;
  try { raw = fs.readFileSync(file.path, 'utf8'); } catch (e) {
    // Honesty gap (review NB-2/O1-family): see claude-code.mjs's identical
    // guard — name the skipped file instead of silently dropping it.
    if (ctx && Array.isArray(ctx.notes)) ctx.notes.push(`codex: file read failed, skipped ${file.path}: ${e.code || e.message}`);
    return;
  }
  const lines = raw.split('\n');
  let sessionId = null;
  let cwd = null;
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i].trim();
    if (!line) continue;
    let obj;
    try { obj = JSON.parse(line); } catch {
      if (i !== lines.length - 1 && ctx && Array.isArray(ctx.notes)) {
        ctx.notes.push(`codex: malformed line skipped ${file.path}:${i + 1}`);
      }
      continue;
    }
    if (!obj) continue;
    if (obj.type === 'session_meta' && obj.payload) {
      sessionId = obj.payload.session_id || sessionId;
      cwd = obj.payload.cwd || cwd;
      continue;
    }
    if (obj.type === 'event_msg' && obj.payload && obj.payload.type === 'token_count') {
      const info = obj.payload.info;
      const usage = info ? usageTotal(info.total_token_usage) : null;
      const rateLimits = obj.payload.rate_limits && obj.payload.rate_limits.primary
        ? obj.payload.rate_limits.primary : undefined;
      yield {
        harness: 'codex',
        sessionId: sessionId || obj.payload.session_id || null,
        project: cwd ? path.basename(cwd) : null,
        ts: typeof obj.timestamp === 'string' ? obj.timestamp : null,
        model: null,
        usage,
        dedupKey: null,
        state: null,
        rateLimits,
      };
    }
  }
}

function project(record) { return record.project; }

// rateLimits(records) -> the LAST record (by array order) carrying a
// rate_limits payload, or null when no record ever reported one.
function rateLimits(records) {
  for (let i = records.length - 1; i >= 0; i -= 1) {
    if (records[i] && records[i].rateLimits) return records[i].rateLimits;
  }
  return null;
}

export default {
  id: 'codex',
  roots,
  discover,
  parse,
  accumulation: 'session_cumulative_last',
  project,
  rateLimits,
};
