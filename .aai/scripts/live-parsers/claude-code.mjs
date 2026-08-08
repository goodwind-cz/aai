// claude-code.mjs — Claude Code harness parser (SPEC-0114-spec-live-status-dashboard).
//
// Session shape: ~/.claude/projects/<slug>/<session>.jsonl (or
// $CLAUDE_CONFIG_DIR/projects/<slug>/<session>.jsonl). `type: assistant`
// lines carry `requestId`, `message.id`, `message.model`,
// `message.usage.{input_tokens, output_tokens, cache_creation_input_tokens,
// cache_read_input_tokens}`, plus `cwd`, `sessionId`, `timestamp`. Usage is
// PER MESSAGE and the same message can repeat on disk — the dedup key is
// `message.id` + `requestId` (accumulation: event_sum_dedup, ccusage-style).
//
// Every root is built from os.homedir() (fallback) or the env's HOME
// override, plus the harness's own CLAUDE_CONFIG_DIR override, joined with
// path.join — never a hardcoded home string (Spec-AC-05).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

function roots(env) {
  const e = env || process.env;
  const home = (e && e.HOME) || os.homedir();
  const base = e && e.CLAUDE_CONFIG_DIR ? path.resolve(e.CLAUDE_CONFIG_DIR) : path.join(home, '.claude');
  return [path.join(base, 'projects')];
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

// usageTotal(u) -> the summed token count, Number()-coerced, or null when
// `u` itself is missing/wrong-shaped OR when any PRESENT field fails to
// coerce to a finite number. The bare `(u.input_tokens || 0) + ...` this
// replaced let a truthy non-numeric field (e.g. a string) turn `+` into
// string concatenation, so a hostile/drifted input_tokens flowed straight
// through usageToday accumulation into the rendered page (BLOCKING-II, code
// review re-review2). Returning null — not 0 — for a garbage field is the
// same honesty invariant Spec-AC-04 already states for a harness with no
// usage fields at all: never render a fabricated zero in place of a figure
// that could not actually be computed.
function usageTotal(u) {
  if (!u || typeof u !== 'object') return null;
  const fields = [u.input_tokens, u.output_tokens, u.cache_creation_input_tokens, u.cache_read_input_tokens];
  let total = 0;
  for (const f of fields) {
    if (f === undefined || f === null) continue;
    const n = Number(f);
    if (!Number.isFinite(n)) return null;
    total += n;
  }
  return total;
}

// parse(file, ctx) -> yields normalized {harness, sessionId, project, ts,
// model, usage|null, dedupKey|null, state|null} records. A malformed line
// (incl. a partial trailing line while the file is being appended to) is
// skipped and counted in ctx.notes, never fatal.
function* parse(file, ctx) {
  let raw;
  try { raw = fs.readFileSync(file.path, 'utf8'); } catch (e) {
    // Honesty gap (review NB-2/O1-family): a read failure (permissions,
    // mid-scan deletion, rotation) used to vanish this file's records with
    // no trace, producing a fabricated-looking verified zero. Name it.
    if (ctx && Array.isArray(ctx.notes)) ctx.notes.push(`claude-code: file read failed, skipped ${file.path}: ${e.code || e.message}`);
    return;
  }
  const lines = raw.split('\n');
  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i].trim();
    if (!line) continue;
    let obj;
    try { obj = JSON.parse(line); } catch {
      // A partial LAST line (writer mid-append) is expected and silent; any
      // other malformed line is skipped and named.
      if (i !== lines.length - 1 && ctx && Array.isArray(ctx.notes)) {
        ctx.notes.push(`claude-code: malformed line skipped ${file.path}:${i + 1}`);
      }
      continue;
    }
    if (!obj || obj.type !== 'assistant' || !obj.message) continue;
    const msg = obj.message;
    const usage = usageTotal(msg.usage);
    const dedupKey = (msg.id && obj.requestId) ? `${msg.id}|${obj.requestId}` : null;
    yield {
      harness: 'claude-code',
      sessionId: obj.sessionId || null,
      project: obj.cwd ? path.basename(obj.cwd) : null,
      ts: typeof obj.timestamp === 'string' ? obj.timestamp : null,
      model: msg.model || null,
      usage,
      dedupKey,
      state: null,
    };
  }
}

function project(record) { return record.project; }

export default {
  id: 'claude-code',
  roots,
  discover,
  parse,
  accumulation: 'event_sum_dedup',
  project,
};
