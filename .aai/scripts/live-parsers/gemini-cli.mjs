// gemini-cli.mjs — Gemini CLI harness parser (SPEC-DRAFT-spec-live-status-dashboard).
//
// Session shape: ~/.gemini/tmp/<project>/logs.json — a JSON array of
// {sessionId, messageId, type, message, timestamp}. NO usage fields exist in
// this format at all: accumulation is 'none' and every record's `usage` is
// (and must stay) `null` all the way to the render, which shows the literal
// text "N/A" — never a fabricated zero or estimate (Spec-AC-04).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

function roots(env) {
  const e = env || process.env;
  const home = (e && e.HOME) || os.homedir();
  const base = e && e.GEMINI_HOME ? path.resolve(e.GEMINI_HOME) : path.join(home, '.gemini');
  return [path.join(base, 'tmp')];
}

function discover(rootList) {
  const out = [];
  for (const root of rootList) {
    let dirs;
    try { dirs = fs.readdirSync(root, { withFileTypes: true }); } catch { continue; }
    for (const d of dirs) {
      if (!d.isDirectory()) continue;
      const file = path.join(root, d.name, 'logs.json');
      let st;
      try { st = fs.statSync(file); } catch { continue; }
      out.push({ path: file, mtimeMs: st.mtimeMs, size: st.size, project: d.name });
    }
  }
  return out;
}

function* parse(file, ctx) {
  let raw;
  try { raw = fs.readFileSync(file.path, 'utf8'); } catch (e) {
    // Honesty gap (review NB-2/O1-family): see claude-code.mjs's identical
    // guard — name the skipped file instead of silently dropping it.
    if (ctx && Array.isArray(ctx.notes)) ctx.notes.push(`gemini-cli: file read failed, skipped ${file.path}: ${e.code || e.message}`);
    return;
  }
  let arr;
  try { arr = JSON.parse(raw); } catch {
    if (ctx && Array.isArray(ctx.notes)) ctx.notes.push(`gemini-cli: malformed file skipped ${file.path}`);
    return;
  }
  if (!Array.isArray(arr)) {
    if (ctx && Array.isArray(ctx.notes)) ctx.notes.push(`gemini-cli: malformed file skipped ${file.path} (not an array)`);
    return;
  }
  const proj = file.project || path.basename(path.dirname(file.path));
  for (const rec of arr) {
    if (!rec || typeof rec !== 'object') continue;
    yield {
      harness: 'gemini-cli',
      sessionId: rec.sessionId || null,
      project: proj,
      ts: typeof rec.timestamp === 'string' ? rec.timestamp : null,
      model: null,
      usage: null,
      dedupKey: null,
      state: null,
    };
  }
}

function project(record) { return record.project; }

export default {
  id: 'gemini-cli',
  roots,
  discover,
  parse,
  accumulation: 'none',
  project,
};
