#!/usr/bin/env node
// ride-select.mjs — rides come from docs/ai/roadmap.yaml, and every maintenance
// ride is paired with a capability. SPEC roadmap-driven-ride-selection-with-budget.
//
// Owner decisions (hitl_decision, 2026-09-05): capability-roadmap-drives-rides,
// maintenance-budget-one-to-one, internal-work-without-asking, review-round-cap.
//
//   node .aai/scripts/ride-select.mjs validate [--roadmap <p>]
//   node .aai/scripts/ride-select.mjs next     [--roadmap <p>] [--docs <dir>] [--json]
//   node .aai/scripts/ride-select.mjs gate --ref <slug> [--intake <path>] [--roadmap <p>]
//        [--docs <dir>] [--events <p>] [--override "<reason>"]
//
// DENY BY DEFAULT. gate exits 0 only when the ref may start now; every refusal
// names ONE reason and its remedy. An unreadable or invalid roadmap REFUSES —
// never "no roadmap, anything goes". Exit: 0 admit · 1 refuse · 2 usage/invalid.
//
// Roadmap shape is CLOSED (see docs/ai/roadmap.yaml header); a line-level
// parser for exactly that shape, no YAML library, anything else is invalid.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
// A ref is a slug id OR a numbered display id (CHANGE-0042, RFC-0012): 36 docs carry the latter.
const SLUG = /^(?:[a-z0-9][a-z0-9-]{1,79}|[A-Z]{2,10}-\d{4})$/;
const DOC_STATUSES = new Set(['draft', 'implementing', 'done', 'deferred', 'rejected', 'superseded']);
const STARTED = new Set(['implementing', 'done']);
// Words in a slug that mark maintenance when the intake type does not already.
const MAINT_WORDS = /(^|-)(fix|guard|harness|hygiene|tripwire|flake|refactor|cleanup|lint|chore|test|ci)(-|$)/;
const MAINT_TYPES = new Set(['issue', 'hotfix', 'techdebt', 'chore', 'test', 'ci']);

function usage(msg) { process.stderr.write(`ride-select: ${msg}\n`); process.exit(2); }
function refuse(msg) { process.stderr.write(`ride-select: REFUSED — ${msg}\n`); process.exit(1); }

function parseArgs(argv) {
  const a = { cmd: argv[0], roadmap: path.join(ROOT, 'docs/ai/roadmap.yaml'), docs: path.join(ROOT, 'docs'), events: path.join(ROOT, 'docs/ai/EVENTS.jsonl'), ref: null, intake: null, override: null, json: false };
  const need = (k, v) => { if (v === undefined || v.startsWith('--')) usage(`${k} requires a value`); return v; };
  for (let i = 1; i < argv.length; i += 1) {
    const k = argv[i]; const v = argv[i + 1];
    if (k === '--roadmap') { a.roadmap = need(k, v); i += 1; }
    else if (k === '--docs') { a.docs = need(k, v); i += 1; }
    else if (k === '--events') { a.events = need(k, v); i += 1; }
    else if (k === '--ref') { a.ref = need(k, v); i += 1; }
    else if (k === '--intake') { a.intake = need(k, v); i += 1; }
    else if (k === '--override') { a.override = need(k, v); i += 1; }
    else if (k === '--json') { a.json = true; }
    else usage(`unknown argument ${k}`);
  }
  if (!['validate', 'next', 'gate'].includes(a.cmd)) usage('usage: ride-select.mjs <validate|next|gate> [flags]');
  return a;
}

// --- roadmap: closed shape, line-level ------------------------------------------
function loadRoadmap(p) {
  let text;
  try { text = fs.readFileSync(p, 'utf8'); } catch { return { error: `roadmap not readable: ${p}` }; }
  const lines = text.replace(/\r\n?/g, '\n').split('\n').filter((l) => !/^\s*#/.test(l) && l.trim() !== '');
  const rm = { budget: null, pairs: [], wave_2: [] };
  let section = null; let cur = null; const seenSections = new Set();
  for (const line of lines) {
    let m;
    if ((m = /^([a-z_0-9]+):\s*$/.exec(line))) {
      section = m[1]; cur = null;
      if (!['budget', 'pairs', 'wave_2'].includes(section)) return { error: `unknown top-level key "${section}"` };
      if (seenSections.has(section)) return { error: `top-level key "${section}" appears twice` };
      seenSections.add(section); continue;
    }
    if (section === 'budget' && (m = /^  maintenance_per_capability:\s*(\d+)\s*$/.exec(line))) { if (rm.budget) return { error: 'budget.maintenance_per_capability appears twice' }; rm.budget = { maintenance_per_capability: Number(m[1]) }; continue; }
    if (section === 'pairs' && (m = /^  - capability:\s*(.+?)\s*$/.exec(line))) { cur = { capability: m[1], maintenance: null, status: null }; rm.pairs.push(cur); continue; }
    if (section === 'pairs' && cur && (m = /^    maintenance:\s*(.+?)\s*$/.exec(line))) { if (cur.maintenance !== null) return { error: `pair ${rm.pairs.length}: "maintenance" appears twice (last-wins would hide a second maintenance ref)` }; cur.maintenance = m[1]; continue; }
    if (section === 'pairs' && cur && (m = /^    status:\s*(planned|active|done)\s*$/.exec(line))) { if (cur.status !== null) return { error: `pair ${rm.pairs.length}: "status" appears twice` }; cur.status = m[1]; continue; }
    if (section === 'wave_2' && (m = /^  - (.+?)\s*$/.exec(line))) { rm.wave_2.push(m[1]); continue; }
    return { error: `line does not fit the closed roadmap shape: "${line.trim()}"` };
  }
  if (!rm.budget) return { error: 'missing budget.maintenance_per_capability' };
  if (rm.budget.maintenance_per_capability !== 1) return { error: `budget.maintenance_per_capability must be 1 (owner decision), got ${rm.budget.maintenance_per_capability}` };
  if (!rm.pairs.length) return { error: 'no pairs' };
  const seen = new Set();
  for (const [i, pr] of rm.pairs.entries()) {
    const n = i + 1;
    if (!pr.maintenance || !pr.status) return { error: `pair ${n} (${pr.capability}) is missing maintenance or status` };
    // Same-ref before the duplicate scan, or a pair naming one ref twice would be
    // reported as "appears twice" — true, but not the reason that matters.
    if (pr.capability === pr.maintenance) return { error: `pair ${n}: capability and maintenance are the same ref "${pr.capability}"` };
    for (const r of [pr.capability, pr.maintenance]) {
      if (!SLUG.test(r)) return { error: `pair ${n}: "${r}" is not a slug` };
      if (seen.has(r)) return { error: `pair ${n}: "${r}" appears twice in the roadmap` };
      seen.add(r);
    }
  }
  for (const r of rm.wave_2) {
    if (!SLUG.test(r)) return { error: `wave_2: "${r}" is not a slug` };
    if (seen.has(r)) return { error: `wave_2: "${r}" appears twice in the roadmap` };
    seen.add(r);
  }
  return { roadmap: rm };
}

// --- doc status by frontmatter id, from the docs tree ----------------------------
function findDoc(docsDir, ref) {
  const dirs = ['issues', 'specs', 'rfc', 'releases', 'requirements'].map((d) => path.join(docsDir, d));
  for (const d of dirs) {
    let names; try { names = fs.readdirSync(d); } catch { continue; }
    for (const n of names) {
      if (!n.endsWith('.md')) continue;
      const p = path.join(d, n);
      let head; try { head = fs.readFileSync(p, 'utf8').split('\n').slice(0, 30); } catch { continue; }
      const idLine = head.find((l) => /^id:\s*/.test(l));
      if (!idLine || idLine.replace(/^id:\s*/, '').trim() !== ref) continue;
      const fm = {};
      for (const l of head) { const m = /^([a-z_]+):\s*(.*)$/.exec(l); if (m) fm[m[1]] = m[2].trim(); }
      return { path: p, status: fm.status || null, type: fm.type || null, blocks: fm.blocks || null };
    }
  }
  return null;
}
function readIntake(p) {
  let head; try { head = fs.readFileSync(p, 'utf8').split('\n').slice(0, 30); } catch { return null; }
  const fm = {};
  for (const l of head) { const m = /^([a-z_]+):\s*(.*)$/.exec(l); if (m) fm[m[1]] = m[2].trim(); }
  const title = (head.find((l) => /^# /.test(l)) || '').replace(/^# /, '');
  return { path: p, id: fm.id || null, status: fm.status || null, type: fm.type || null, blocks: fm.blocks || null, title };
}
function statusOf(docsDir, ref) { const d = findDoc(docsDir, ref); return d ? d.status : null; }

// --- next -------------------------------------------------------------------------
function nextRide(rm, docsDir) {
  for (const pr of rm.pairs) {
    if (pr.status === 'done') continue;
    const cs = statusOf(docsDir, pr.capability); const ms = statusOf(docsDir, pr.maintenance);
    // D2: the capability comes first UNLESS it has already started; proposing a
    // ride that is already implementing is proposing to start it twice.
    if (!STARTED.has(cs || '')) return { ref: pr.capability, half: 'capability', pair: pr };
    if (ms !== 'done') return { ref: pr.maintenance, half: 'maintenance', pair: pr };
  }
  return null;
}

// --- gate --------------------------------------------------------------------------
function isMaintenance(ref, intake) {
  if (intake && intake.type && MAINT_TYPES.has(intake.type)) return true;
  if (intake && intake.title && /\b(fix|guard|harness|hygiene|tripwire|flake|refactor|cleanup|lint)\b/i.test(intake.title)) return true;
  return MAINT_WORDS.test(ref);
}
// House shape of docs/ai/EVENTS.jsonl records (append-event.mjs): actor is the
// git identity slug, never a role word. append-event.mjs itself has a CLOSED
// event set and no ledger-path flag, so the record is written here in the same
// shape rather than by widening that set.
function actorSlug() {
  try {
    const email = execFileSync('git', ['config', 'user.email'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    return email.toLowerCase().replace(/[^a-z0-9._-]+/g, '_') || 'unknown';   // exactly append-event.mjs actorSlug()
  } catch { /* fall through */ }
  return 'unknown';
}
function appendOverride(eventsPath, ref, reason) {
  const rec = { v: 1, ts: new Date().toISOString(), actor: actorSlug(), event: 'ride_gate_override', ref, payload: { reason } };
  fs.mkdirSync(path.dirname(eventsPath), { recursive: true });
  fs.appendFileSync(eventsPath, `${JSON.stringify(rec)}\n`);
}

function main() {
  const a = parseArgs(process.argv.slice(2));
  const loaded = loadRoadmap(a.roadmap);

  if (a.cmd === 'validate') {
    if (loaded.error) usage(`invalid roadmap ${a.roadmap}: ${loaded.error}`);
    process.stdout.write(`roadmap OK: ${loaded.roadmap.pairs.length} pair(s), ${loaded.roadmap.wave_2.length} wave-2 item(s)\n`);
    process.exit(0);
  }
  if (loaded.error) refuse(`${loaded.error} (${a.roadmap}) — a gate that cannot read its roadmap admits nothing`);
  const rm = loaded.roadmap;

  if (a.cmd === 'next') {
    const n = nextRide(rm, a.docs);
    if (!n) { process.stdout.write(a.json ? JSON.stringify({ next: null, wave_1: 'complete', wave_2: rm.wave_2 }) + '\n' : `wave 1 complete — wave 2 candidates: ${rm.wave_2.join(', ') || 'none'}\n`); process.exit(0); }
    process.stdout.write(a.json ? JSON.stringify({ next: n.ref, half: n.half, pair: n.pair }) + '\n' : `${n.ref}\n`);
    process.exit(0);
  }

  // gate
  if (!a.ref) usage('gate requires --ref <slug>');
  if (!SLUG.test(a.ref)) usage(`--ref "${a.ref}" is not a slug`);
  if (a.override !== null && a.override.trim() === '') usage('--override requires a reason');
  const intake = a.intake ? readIntake(a.intake) : findDoc(a.docs, a.ref);
  if (a.intake && intake && intake.id && intake.id !== a.ref) usage(`--intake ${a.intake} has id "${intake.id}", not --ref ${a.ref}`);
  const pair = rm.pairs.find((p) => p.capability === a.ref || p.maintenance === a.ref);
  const status = intake ? intake.status : statusOf(a.docs, a.ref);

  const admit = (why) => { process.stdout.write(`ride-select: ADMIT ${a.ref} — ${why}\n`); process.exit(0); };
  const deny = (why) => {
    if (a.override) { appendOverride(a.events, a.ref, a.override); process.stdout.write(`ride-select: OVERRIDE ${a.ref} — ${why}; owner reason logged to ${a.events}: "${a.override}"\n`); process.exit(0); }
    refuse(why);
  };

  if (status === 'done') return deny(`${a.ref} is already done — nothing to ride`);
  if (pair) {
    if (pair.status === 'done') return deny(`${a.ref} belongs to a pair already marked done in the roadmap`);
    if (pair.capability === a.ref) return admit('a roadmap capability');
    const cs = statusOf(a.docs, pair.capability);
    if (!STARTED.has(cs || '')) return deny(`pair first — ${a.ref} is the maintenance half of a pair whose capability ${pair.capability} is ${cs || 'not filed'}; start ${pair.capability} before it (1:1 budget)`);
    return admit(`the maintenance half of a pair whose capability ${pair.capability} is ${cs}`);
  }
  // off-roadmap
  if (intake && intake.blocks) {
    const b = intake.blocks;
    const target = rm.pairs.find((p) => p.capability === b || p.maintenance === b);
    if (!target) return deny(`blocks: names ${b}, which is not on the roadmap`);
    if (target.status === 'done' || statusOf(a.docs, b) === 'done') return deny(`blocks: names ${b}, which is already done`);
    return admit(`off-roadmap but blocks roadmap item ${b}`);
  }
  if (isMaintenance(a.ref, intake)) {
    return deny(`${a.ref} is maintenance and not on the roadmap — file it to the backlog: node .aai/scripts/follow-ups.mjs add --id fu-<slug> --ref <roadmap-ref> --severity P3 --what "…" --why "…" --source "…"; or add "blocks: <roadmap ref>" to its intake if it blocks one`);
  }
  return deny(`${a.ref} is not on the roadmap — add it to docs/ai/roadmap.yaml (an owner decision) or mark its intake "blocks: <roadmap ref>"`);
}

main();
