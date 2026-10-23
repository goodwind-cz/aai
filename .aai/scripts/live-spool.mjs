#!/usr/bin/env node
// live-spool.mjs - statusline/hook tap writer (SPEC-0114-spec-live-status-dashboard,
// moved to one Node module by spec-node-first-sync-hook-slice, RFC-0017 phase 3).
//
// Reads ONE JSON payload on stdin, projects a WHITELIST of fields, appends one
// line to docs/ai/live/<kind>.jsonl (kind = statusline|hooks, first argument,
// default statusline), caps the file by line count, and ALWAYS exits 0 - a
// statusline or hook writer must never disturb the harness it is tapping.
// The repo root is resolved from THIS module's own location, so the caller's
// cwd is irrelevant. AAI_LIVE_SPOOL_DIR overrides the spool directory.
// live-spool.sh and live-spool.ps1 are thin launchers of this file.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const MAX_LINES = 500;
export const PASSTHROUGH = '(aai-live tap active)';
const COMMON_FIELDS = ['session_id', 'cwd', 'model'];
const STATUSLINE_FIELDS = ['rate_limits', 'cost'];
const HOOK_FIELDS = ['hook_event_name'];
const EOL = '\n';

const MODULE_DIR = path.dirname(fileURLToPath(import.meta.url));

export function projectPayload(raw, kind, now = new Date()) {
  let obj;
  try { obj = JSON.parse(raw); } catch { return null; }
  if (obj === null || typeof obj !== 'object') return null;
  if (Array.isArray(obj)) return null;
  const allow = COMMON_FIELDS.concat(kind === 'hooks' ? HOOK_FIELDS : STATUSLINE_FIELDS);
  const ts = now.toISOString();
  const out = { ts };
  for (const key of allow) {
    if (key in obj) {
      out[key] = obj[key];
    }
  }
  return JSON.stringify(out);
}

export function appendCapped(file, line, maxLines = MAX_LINES) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.appendFileSync(file, line + EOL, 'utf8');
  const lines = fs.readFileSync(file, 'utf8').split(EOL);
  if (lines[lines.length - 1] === '') lines.pop();
  if (lines.length > maxLines) {
    const tmp = file + '.tmp';
    fs.writeFileSync(tmp, lines.slice(lines.length - maxLines).join(EOL) + EOL, 'utf8');
    fs.renameSync(tmp, file);
  }
}

export function runLiveSpool({ argv = [], env = {}, stdinText = '', stdout }) {
  const kind = argv[0] || 'statusline';
  try {
    const dir = env.AAI_LIVE_SPOOL_DIR || path.join(MODULE_DIR, '..', '..', 'docs', 'ai', 'live');
    const line = projectPayload(stdinText, kind);
    if (line) appendCapped(path.join(dir, kind + '.jsonl'), line);
  } catch {
    // A spool failure must never disturb the harness.
  }
  if (kind === 'statusline') {
    try { stdout.write(PASSTHROUGH + EOL); } catch { /* nothing may escape */ }
  }
}

function isMainModule() {
  try {
    return fs.realpathSync(process.argv[1]) === fs.realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return false;
  }
}

if (isMainModule()) {
  let stdinText = '';
  try { stdinText = fs.readFileSync(0, 'utf8'); } catch { stdinText = ''; }
  runLiveSpool({
    argv: process.argv.slice(2),
    env: process.env,
    stdinText,
    stdout: { write: (text) => fs.writeSync(1, text) },
  });
  process.exit(0);
}
