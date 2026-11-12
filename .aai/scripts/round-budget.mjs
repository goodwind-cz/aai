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
//   node .aai/scripts/round-budget.mjs sweep-plan --ref <ref> [--events <file>] [--root <dir>]
//     prints exactly one `SWEEP full|reuse|not-applicable ...` line, exit 0 (D-SWEEP).
//   An EVENTS file that exists but cannot be read: status exits 1; sweep-plan answers
//   `SWEEP full reason=events-unreadable code=<CODE>` after its not-applicable checks (D-READ).

import fs from 'node:fs';
import path from 'node:path';
import { execSync, execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { nowIso } from './lib/iso-time.mjs';
import { parseSuiteMap, matchesGlob } from './select-suites.mjs';

export const ROUND_CAP_BASE = 2;
export const ROUND_CAP_EXIT = 5;
export const REUSE_GLOBS = ['tests/**', 'docs/**', '**/*.md', '.github/**', 'CHANGELOG.md'];
export function roundMenu(ref) {
  return '(1) split the ride: close what is green, file the rest as a new intake (recommended) '
    + `(2) one more round: node .aai/scripts/append-event.mjs --event round_extension --ref ${ref} --authority owner --reason <why> `
    + '(3) park the ride';
}

// Parse one EVENTS file. Absent file (ENOENT): no events. Any other read error is thrown with its `code`
// (D-READ: a ledger that exists but cannot be read is not an empty ledger). A line that is not a JSON
// object is counted, not thrown.
export function readEvents(eventsPath) {
  const out = { events: [], malformed: 0 };
  let raw;
  try { raw = fs.readFileSync(eventsPath, 'utf8'); } catch (err) {
    if (err.code === 'ENOENT') return out;
    throw err;
  }
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

export const errCode = (err) => (err && err.code) || 'UNKNOWN';

const forRef = (events, ref, name) => events.filter(e => e.event === name && e.ref === ref);

export function roundsUsed(events, ref) {
  return forRef(events, ref, 'round_reset').filter(e => e.payload?.same_round !== true).length;
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
  let events;
  try { ({ events } = readEvents(eventsPath)); } catch (err) {
    return {
      refused: true,
      unreadable: true,
      used: null,
      cap: null,
      ref,
      message: `REFUSED review-round-cap: cannot read ${eventsPath} (${errCode(err)}); the round count for ${ref} is unknown. Repair the file, then retry.`,
    };
  }
  const used = roundsUsed(events, ref);
  const cap = roundCap(events, ref);
  return {
    refused: used >= cap,
    used,
    cap,
    ref,
    message: `REFUSED review-round-cap: ${used}/${cap} rounds used for ${ref}. ${roundMenu(ref)}`,
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

// Append the round_reset lines of ONE reset call beside the STATE file's EVENTS, in one write: one line per
// payload, in order; every line after the first carries same_round true and is not a counted round (D-JOINT).
// A single payload object is the one-block form. Throws on an I/O error; the caller warns.
export function appendRoundReset(eventsPath, ref, payloads) {
  const list = Array.isArray(payloads) ? payloads : [payloads];
  const lines = list.map((payload, i) => JSON.stringify({
    v: 1, ts: nowIso(), actor: actorSlug(), event: 'round_reset', ref,
    payload: i === 0 ? payload : { ...payload, same_round: true },
  }) + '\n');
  fs.mkdirSync(path.dirname(eventsPath), { recursive: true });
  fs.appendFileSync(eventsPath, lines.join(''));
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

const git = (root, args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });

// The focus spec's ceremony level, read from the spec path STATE names (else the spec whose file name
// holds the ref). Absent or unreadable: null (not lightweight).
function ceremonyOf(root, ref) {
  let specPath = null;
  try {
    const st = fs.readFileSync(path.join(root, 'docs/ai/STATE.yaml'), 'utf8');
    const m = /^\s+spec_path:\s*(\S+)\s*$/m.exec(st);
    if (m && m[1] !== 'null') specPath = m[1].replace(/^["']|["']$/g, '');
  } catch { /* no STATE */ }
  if (!specPath || !fs.existsSync(path.join(root, specPath))) {
    try {
      const f = fs.readdirSync(path.join(root, 'docs/specs')).find(n => n.endsWith('.md') && n.includes(ref));
      specPath = f ? `docs/specs/${f}` : null;
    } catch { specPath = null; }
  }
  if (!specPath) return null;
  try {
    const fm = /^---\n([\s\S]*?)\n---/.exec(fs.readFileSync(path.join(root, specPath), 'utf8'));
    const lv = fm && /^ceremony_level:\s*(\S+)\s*$/m.exec(fm[1]);
    return lv ? lv[1] : null;
  } catch { return null; }
}

function suiteMapGlobs(root) {
  for (const base of [root, path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..')]) {
    try {
      const m = parseSuiteMap(fs.readFileSync(path.join(base, 'tests/skills/suite-map.yaml'), 'utf8'));
      return [...m.carryGlobs, ...m.inertGlobs];
    } catch { /* try next */ }
  }
  return [];
}

// D-SWEEP: does the ride owe the full sweep? Returns the one SWEEP line's parts.
export function sweepPlan(events, ref, root, eventsError = null) {
  if (!fs.existsSync(path.join(root, 'tests/skills/test-framework.sh'))) return { kind: 'not-applicable', reason: 'no-sweep-command' };
  const level = ceremonyOf(root, ref);
  if (level === '0' || level === '1') return { kind: 'not-applicable', reason: 'lightweight-lane' };
  if (eventsError) return { kind: 'full', reason: 'events-unreadable', extra: `code=${errCode(eventsError)}` };
  const sweeps = forRef(events, ref, 'full_sweep');
  const newest = sweeps[sweeps.length - 1];
  if (!newest) return { kind: 'full', reason: 'no-sweep' };
  const last = { ...newest.payload };
  const sha = last.head;
  const run = last.run_id;
  if (last.rc !== 0) return { kind: 'full', reason: 'red-sweep', extra: `run=${run}` };
  try { git(root, ['merge-base', '--is-ancestor', sha, 'HEAD']); } catch { return { kind: 'full', reason: 'not-ancestor', extra: `sha=${sha}` }; }
  let delta;
  try {
    delta = [...git(root, ['diff', '--name-only', '--no-renames', sha]).split('\n'),
      ...git(root, ['ls-files', '--others', '--exclude-standard']).split('\n')].filter(Boolean);
  } catch { return { kind: 'full', reason: 'not-ancestor', extra: `sha=${sha}` }; }
  const globs = [...REUSE_GLOBS, ...suiteMapGlobs(root)];
  const out = delta.find(f => !globs.some(g => matchesGlob(f, g)));
  if (out !== undefined) return { kind: 'full', reason: 'code-delta', extra: `path=${out}` };
  return { kind: 'reuse', sha, run };
}

export function sweepLine(plan) {
  if (plan.kind === 'reuse') return `SWEEP reuse sha=${plan.sha} run=${plan.run}`;
  return `SWEEP ${plan.kind} reason=${plan.reason}${plan.extra ? ` ${plan.extra}` : ''}`;
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
  if (cmd !== 'status' && cmd !== 'sweep-plan') {
    console.error('usage: round-budget.mjs status|sweep-plan --ref <ref> [--events <file>] [--root <dir>] [--json]');
    return 2;
  }
  const flags = parseFlags(argv.slice(1));
  if (typeof flags.ref !== 'string' || flags.ref === '') {
    console.error(`round-budget: ${cmd} requires --ref <ref>`);
    return 2;
  }
  const root = typeof flags.root === 'string' ? path.resolve(flags.root) : process.cwd();
  const eventsPath = typeof flags.events === 'string' ? path.resolve(flags.events) : path.join(root, 'docs/ai/EVENTS.jsonl');
  let events = [];
  let malformed = 0;
  let eventsError = null;
  try { ({ events, malformed } = readEvents(eventsPath)); } catch (err) { eventsError = err; }
  if (eventsError && cmd === 'status') {
    console.error(`round-budget: cannot read ${eventsPath} (${errCode(eventsError)})`);
    return 1;
  }
  if (malformed > 0) console.error(`NOTE: ignored ${malformed} malformed line(s) in ${eventsPath}`);
  if (cmd === 'sweep-plan') {
    console.log(sweepLine(sweepPlan(events, flags.ref, root, eventsError)));
    return 0;
  }
  const s = statusOf(events, flags.ref);
  if (flags.json === true) {
    console.log(JSON.stringify(s));
  } else {
    console.log(`rounds: ${s.used}/${s.cap} extensions: ${s.extensions} resets: validation=${s.validation} `
      + `code_review=${s.code_review} forced=${s.forced} sweeps: ${s.sweeps} green=${s.green} last_sweep=${s.last_sweep}`);
  }
  return 0;
}

const realOrResolve = (p) => { try { return fs.realpathSync(p); } catch { return path.resolve(p); } };
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  process.exitCode = main(process.argv.slice(2));
}
