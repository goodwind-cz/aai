#!/usr/bin/env node
// round-budget.mjs — the counted review round cap (SPEC-DRAFT spec-factory-round-cap D-COUNT, D-CAP, D-STATUS).
//
// One module owns the count. A round is one `state.mjs reset-block` call that changed a block; it is
// recorded as one `round_reset` EVENTS line. The cap is ROUND_CAP_BASE plus the `round_extension`
// lines of the same ref. state.mjs, orchestration-dispatch.mjs and append-event.mjs import this module
// and keep no copy of the count.
//
// CLI:
//   node .aai/scripts/round-budget.mjs status --ref <ref> [--events <file>] [--root <dir>] [--json]
//     prints `rounds: <used>/<cap> extensions: <n> resets: validation=<v> code_review=<c> forced=<f>
//     sweeps: <count> green=<g> last_sweep=<sha|none>`, exit 0. Reads only EVENTS. Default EVENTS
//     file: <root or cwd>/docs/ai/EVENTS.jsonl. A malformed line is skipped with a NOTE on stderr.

import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { nowIso } from './lib/iso-time.mjs';

export const ROUND_CAP_BASE = 2;
export const ROUND_CAP_EXIT = 5;
export const ROUND_MENU = '(1) split the ride: close what is green, file the rest as a new intake (recommended) '
  + '(2) one more round: append-event round_extension --authority owner (3) park the ride';

// Parse one EVENTS file. Absent file: no events. A line that is not a JSON object is counted, not thrown.
export function readEvents(eventsPath) {
  const out = { events: [], malformed: 0 };
  let raw;
  try { raw = fs.readFileSync(eventsPath, 'utf8'); } catch { return out; }
  for (const line of raw.split('\n')) {
    if (line.trim() === '') continue;
    try {
      const e = JSON.parse(line);
      if (e !== null && typeof e === 'object' && !Array.isArray(e)) out.events.push(e);
      else out.malformed += 1;
    } catch { out.malformed += 1; }
  }
  return out;
}

const forRef = (events, ref, name) => events.filter(e => e.event === name && e.ref === ref);

export function roundsUsed(events, ref) {
  return forRef(events, ref, 'round_reset').length;
}

export function roundCap(events, ref) {
  const extensions = forRef(events, ref, 'round_extension').length;
  return ROUND_CAP_BASE + extensions;
}

export function standingAExtensions(events, ref) {
  return forRef(events, ref, 'round_extension').filter(e => e.payload?.authority === 'standing-a').length;
}

// The gate reset-block asks before it changes a block.
export function resetGate(eventsPath, ref) {
  const { events } = readEvents(eventsPath);
  const used = roundsUsed(events, ref);
  const cap = roundCap(events, ref);
  return {
    refused: used >= cap,
    used,
    cap,
    ref,
    message: `REFUSED review-round-cap: ${used}/${cap} rounds used for ${ref}. ${ROUND_MENU}`,
  };
}

function actorSlug() {
  try {
    const email = execSync('git config user.email', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    return email.toLowerCase().replace(/[^a-z0-9._-]+/g, '_') || 'unknown';
  } catch {
    return 'unknown';
  }
}

// Append one round_reset line beside the STATE file's EVENTS. Throws on an I/O error; the caller warns.
export function appendRoundReset(eventsPath, ref, payload) {
  const entry = { v: 1, ts: nowIso(), actor: actorSlug(), event: 'round_reset', ref, payload };
  fs.mkdirSync(path.dirname(eventsPath), { recursive: true });
  fs.appendFileSync(eventsPath, JSON.stringify(entry) + '\n');
}

export function statusOf(events, ref) {
  const resets = forRef(events, ref, 'round_reset');
  const sweeps = forRef(events, ref, 'full_sweep');
  const last = sweeps[sweeps.length - 1];
  return {
    ref,
    used: roundsUsed(events, ref),
    cap: roundCap(events, ref),
    extensions: forRef(events, ref, 'round_extension').length,
    validation: resets.filter(e => e.payload?.block === 'last_validation').length,
    code_review: resets.filter(e => e.payload?.block === 'code_review').length,
    forced: resets.filter(e => e.payload?.forced === true).length,
    sweeps: sweeps.length,
    green: sweeps.filter(e => e.payload?.rc === 0).length,
    last_sweep: last?.payload?.head ?? 'none',
  };
}

function parseFlags(argv) {
  const flags = {};
  for (let i = 0; i < argv.length; i += 1) {
    if (!argv[i].startsWith('--')) continue;
    const key = argv[i].slice(2);
    const next = argv[i + 1];
    if (next !== undefined && !next.startsWith('--')) { flags[key] = next; i += 1; } else flags[key] = true;
  }
  return flags;
}

function main(argv) {
  const cmd = argv[0];
  if (cmd !== 'status') {
    console.error('usage: round-budget.mjs status --ref <ref> [--events <file>] [--root <dir>] [--json]');
    return 2;
  }
  const flags = parseFlags(argv.slice(1));
  if (typeof flags.ref !== 'string' || flags.ref === '') {
    console.error('round-budget: status requires --ref <ref>');
    return 2;
  }
  const root = typeof flags.root === 'string' ? path.resolve(flags.root) : process.cwd();
  const eventsPath = typeof flags.events === 'string' ? path.resolve(flags.events) : path.join(root, 'docs/ai/EVENTS.jsonl');
  const { events, malformed } = readEvents(eventsPath);
  if (malformed > 0) console.error(`NOTE: ignored ${malformed} malformed line(s) in ${eventsPath}`);
  const s = statusOf(events, flags.ref);
  if (flags.json === true) {
    console.log(JSON.stringify(s));
  } else {
    console.log(`rounds: ${s.used}/${s.cap} extensions: ${s.extensions} resets: validation=${s.validation} `
      + `code_review=${s.code_review} forced=${s.forced} sweeps: ${s.sweeps} green=${s.green} last_sweep=${s.last_sweep}`);
  }
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  process.exitCode = main(process.argv.slice(2));
}
