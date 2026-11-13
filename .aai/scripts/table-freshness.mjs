#!/usr/bin/env node
// table-freshness.mjs — keeper for the two shipped model tables
// (.aai/system/MODEL_ROUTING.yaml and .aai/system/PRICING.yaml), spec
// spec-routing-tables-have-an-owner-and-a-seam (D-CLI).
//
// Subcommands:
//   check [--root <dir>] [--now <ISO>] [--horizon-days <n>]
//     One line per table, MODEL_ROUTING then PRICING:
//       FRESH <relpath> <stamp> age=<n>d horizon=<h>d
//       LAPSED <relpath> <stamp> age=<n>d horizon=<h>d
//       INVALID <relpath> <reason>
//       ABSENT <relpath>
//     Exit 0 when no LAPSED or INVALID line, 1 otherwise, 2 on usage error.
//     ABSENT is not a finding (deleting MODEL_ROUTING.yaml is a documented
//     opt-out).
//
// Horizon precedence (D-LAPSE): --horizon-days, then AAI_TABLES_HORIZON_DAYS,
// then the table's own cadence_days. An override that is not a positive
// integer is a usage error (exit 2), never silently defaulted.
//
//   stamp-guard --base <rev> [--root <dir>] [--now <ISO>]
//     Compares each table at <rev> (git show) with the working tree. A change
//     to a routed (MODEL_ROUTING) or priced (PRICING) line must come with a
//     strictly later last_updated_utc. One line per table: UNCHANGED,
//     RESTAMPED, CHANGED-STAMPED or `VIOLATION <relpath> <reason>`. Exit 0
//     clean, 1 violation, 2 usage error or a base git cannot resolve.
//     Compared: MODEL_ROUTING tiers/roles(@h) headers and their two-space
//     rows plus validation_alternate(@h) lines; PRICING lines under models:
//     and model_aliases:. Never compared: comments, blank lines, trailing
//     whitespace, routing_meta/effort_* sections, pricing_meta, update_policy,
//     lookup_rules, cost_blend, sources. Caveat: the guard proves a stamp moved
//     when the compared lines moved; it does not prove the new values were
//     checked against a primary source.
//
//   routed --since <YYYY-MM-DD> [--allow-stale <id>[,<id>...]] [--root <dir>]
//     Walks every tiers@<h>, roles@<h> and validation_alternate@<h> entry of
//     MODEL_ROUTING.yaml and prints one line per entry:
//       OK <h> <section>/<key> <id> <last_verified>
//       STALE | UNPRICED | MISSING <h> <section>/<key> <id> [<last_verified>]
//       ALLOWED <h> <section>/<key> <id> <last_verified>   (stale, listed)
//       ORDER <h> <lowerTier> <higherTier>   (lower tier priced above higher)
//       ALLOW-UNUSED <id>                    (listed id that is not stale)
//     An id is OK only as an EXACT PRICING `models:` key with numeric rates, a
//     source_ref and last_verified_utc on or after <date>. Exit 0 only when
//     every line is OK or ALLOWED, 1 otherwise, 2 on usage error.
//
// Marker reading (D-READ) is line-based, no YAML library. Node stdlib only.

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';

const DAY_MS = 86400000;
const TABLES = [
  { rel: '.aai/system/MODEL_ROUTING.yaml', kind: 'routing' },
  { rel: '.aai/system/PRICING.yaml', kind: 'pricing' },
];

const POS_INT = /^[1-9]\d*$/;
const STAMP_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;

// Value of the two-space row `  <key>:` under column-0 `<header>:`.
function sectionRow(lines, header, key) {
  let inSection = false;
  for (const line of lines) {
    if (/^\S/.test(line)) {
      inSection = line.replace(/\s+$/, '') === `${header}:`;
      continue;
    }
    if (!inSection) continue;
    const m = new RegExp(`^  ${key}:\\s*(.*?)\\s*$`).exec(line);
    if (m) return m[1].replace(/^"(.*)"$/, '$1');
  }
  return null;
}

// readMarker(text, kind) -> { ok: true, stamp, cadence } | { ok: false, reason }
export function readMarker(text, kind) {
  const lines = text.split(/\r?\n/);
  const [stampHdr, cadHdr] = kind === 'pricing'
    ? ['pricing_meta', 'update_policy'] : ['routing_meta', 'routing_meta'];
  const stampRaw = sectionRow(lines, stampHdr, 'last_updated_utc');
  if (stampRaw === null || stampRaw === '') return { ok: false, reason: 'missing last_updated_utc' };
  let stamp = null;
  if (STAMP_RE.test(stampRaw)) {
    const d = new Date(stampRaw);
    if (!Number.isNaN(d.getTime()) && d.toISOString().replace('.000Z', 'Z') === stampRaw) stamp = d;
  }
  if (!stamp) return { ok: false, reason: 'malformed last_updated_utc' };
  const cadRaw = sectionRow(lines, cadHdr, 'cadence_days');
  if (cadRaw === null || cadRaw === '') return { ok: false, reason: 'missing cadence_days' };
  if (!POS_INT.test(cadRaw)) return { ok: false, reason: 'malformed cadence_days' };
  return { ok: true, stamp, cadence: Number(cadRaw) };
}

// validateMarker(text, kind, now) -> readMarker result, plus the D-READ
// future-stamp rule (a stamp more than one day after `now` is invalid). The
// single validity definition shared by `check` and `stamp-guard`.
export function validateMarker(text, kind, now = new Date()) {
  const m = readMarker(text, kind);
  if (m.ok && m.stamp.getTime() - now.getTime() > DAY_MS) {
    return { ok: false, reason: 'future last_updated_utc', stamp: m.stamp };
  }
  return m;
}

export function classifyAge(ageDays, horizon) {
  return ageDays > horizon ? 'LAPSED' : 'FRESH';
}

// checkTables(root, { now, horizonDays, env }) -> [{ file, status, ... }]
// horizonDays / env.AAI_TABLES_HORIZON_DAYS must already be validated by the
// caller (parseHorizon); an invalid value here throws.
export function checkTables(root, { now = new Date(), horizonDays = null, env = process.env } = {}) {
  const override = horizonDays !== null && horizonDays !== undefined
    ? horizonDays
    : (env.AAI_TABLES_HORIZON_DAYS !== undefined && env.AAI_TABLES_HORIZON_DAYS !== ''
      ? env.AAI_TABLES_HORIZON_DAYS : null);
  if (override !== null && !POS_INT.test(String(override))) {
    throw new RangeError('invalid horizon override');
  }
  const out = [];
  for (const t of TABLES) {
    const p = path.resolve(root, t.rel);
    if (!fs.existsSync(p)) { out.push({ file: t.rel, status: 'ABSENT' }); continue; }
    let text;
    try { text = fs.readFileSync(p, 'utf8'); } catch (e) {
      out.push({ file: t.rel, status: 'INVALID', reason: `unreadable (${e.code || e.message})` }); continue;
    }
    const marker = validateMarker(text, t.kind, now);
    if (!marker.ok) {
      const r = { file: t.rel, status: 'INVALID', reason: marker.reason };
      if (marker.stamp) r.stamp = marker.stamp.toISOString().replace('.000Z', 'Z');
      out.push(r); continue;
    }
    const stampIso = marker.stamp.toISOString().replace('.000Z', 'Z');
    const horizon = override !== null ? Number(override) : marker.cadence;
    const ageDays = Math.floor((now.getTime() - marker.stamp.getTime()) / DAY_MS);
    out.push({
      file: t.rel, status: classifyAge(ageDays, horizon), stamp: stampIso,
      age_days: ageDays, horizon_days: horizon,
    });
  }
  return out;
}

export function formatLine(r) {
  if (r.status === 'ABSENT') return `ABSENT ${r.file}`;
  if (r.status === 'INVALID') return `INVALID ${r.file} ${r.reason}`;
  return `${r.status} ${r.file} ${r.stamp} age=${r.age_days}d horizon=${r.horizon_days}d`;
}

const norm = (text) => text.split(/\r?\n/).map((l) => l.replace(/\s+$/, ''))
  .filter((l) => l.trim() !== '' && !l.trim().startsWith('#'));

// Routed content of MODEL_ROUTING.yaml (see header).
export function routedLines(text) {
  const out = [];
  let inSec = false;
  for (const l of norm(text)) {
    if (/^\S/.test(l)) {
      inSec = /^(tiers|roles)(@[A-Za-z0-9_-]+)?:\s*$/.test(l);
      if (inSec || /^validation_alternate(@[A-Za-z0-9_-]+)?:/.test(l)) out.push(l);
    } else if (inSec) out.push(l);
  }
  return out;
}

// Priced content of PRICING.yaml: rows under column-0 models: / model_aliases:.
export function pricedLines(text) {
  const out = [];
  let inSec = false;
  for (const l of norm(text)) {
    if (/^\S/.test(l)) { inSec = /^(models|model_aliases):/.test(l); if (inSec) out.push(l); }
    else if (inSec) out.push(l);
  }
  return out;
}

// Text of <rel> at <base>, or null when the path is genuinely absent at that
// revision. Any other git failure throws GitError (the guard fails closed).
export class GitError extends Error {}
function gitShow(root, base, rel) {
  const ls = spawnSync('git', ['-C', root, 'ls-tree', '--name-only', base, '--', rel], { encoding: 'utf8' });
  if (ls.error || ls.status !== 0) {
    throw new GitError(`git ls-tree failed for ${base}:${rel}: ${(ls.error && ls.error.message) || ls.stderr.trim()}`);
  }
  if (ls.stdout.trim() === '') return null;
  const r = spawnSync('git', ['-C', root, 'show', `${base}:${rel}`], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  if (r.error || r.status !== 0) {
    throw new GitError(`git show failed for ${base}:${rel}: ${(r.error && r.error.message) || r.stderr.trim()}`);
  }
  return r.stdout;
}

// stampGuard(root, base) -> { results: [{ file, verdict, reason }], violation }
// Throws RangeError when git cannot resolve <base>, GitError on any other git
// failure reading a table at <base>. Head and base markers use validateMarker.
export function stampGuard(root, base, { now = new Date() } = {}) {
  const rv = spawnSync('git', ['-C', root, 'rev-parse', '--verify', '--quiet', `${base}^{commit}`], { encoding: 'utf8' });
  if (rv.status !== 0) throw new RangeError(`base revision does not resolve: ${base}`);
  const results = [];
  for (const t of TABLES) {
    const lines = t.kind === 'pricing' ? pricedLines : routedLines;
    const baseText = gitShow(root, base, t.rel);
    const p = path.resolve(root, t.rel);
    const headText = fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : null;
    const viol = (reason) => results.push({ file: t.rel, verdict: 'VIOLATION', reason });
    if (baseText === null && headText === null) { results.push({ file: t.rel, verdict: 'UNCHANGED' }); continue; }
    if (headText === null) { viol('table deleted; deleting a shipped table is not a refresh'); continue; }
    const head = validateMarker(headText, t.kind, now);
    if (!head.ok) { viol(`invalid head marker: ${head.reason}`); continue; }
    const baseMarker = baseText === null ? { ok: false } : validateMarker(baseText, t.kind, now);
    const contentChanged = baseText === null
      || JSON.stringify(lines(baseText)) !== JSON.stringify(lines(headText));
    if (baseMarker.ok && head.stamp.getTime() < baseMarker.stamp.getTime()) {
      viol(`last_updated_utc lowered from ${baseMarker.stamp.toISOString()} to ${head.stamp.toISOString()}`); continue;
    }
    const stampAdvanced = !baseMarker.ok || head.stamp.getTime() > baseMarker.stamp.getTime();
    if (contentChanged && !stampAdvanced) {
      viol('routed/priced lines changed without a later last_updated_utc'); continue;
    }
    results.push({ file: t.rel, verdict: contentChanged ? 'CHANGED-STAMPED' : (stampAdvanced ? 'RESTAMPED' : 'UNCHANGED') });
  }
  return { results, violation: results.some((r) => r.verdict === 'VIOLATION') };
}

const HARNESSES = ['claude', 'codex', 'gemini'];
const TIER_ORDER = ['mechanical', 'standard', 'premium'];

// Routed entries of MODEL_ROUTING.yaml: [{ h, section, key, id }] for the
// harness set, in file order.
export function routedEntries(text) {
  const out = [];
  let cur = null;
  for (const l of norm(text)) {
    if (/^\S/.test(l)) {
      cur = null;
      let m = /^(tiers|roles)@([A-Za-z0-9_-]+):\s*$/.exec(l);
      if (m && HARNESSES.includes(m[2])) { cur = { section: m[1], h: m[2] }; continue; }
      m = /^validation_alternate@([A-Za-z0-9_-]+):\s*(.*?)\s*$/.exec(l);
      if (m && HARNESSES.includes(m[1]) && m[2] !== '') {
        out.push({ h: m[1], section: 'validation_alternate', key: '-', id: m[2].replace(/^"(.*)"$/, '$1') });
      }
    } else if (cur) {
      const m = /^  ([^:]+):\s*(\S.*?)\s*$/.exec(l);
      if (m) out.push({ h: cur.h, section: cur.section, key: m[1], id: m[2].replace(/^"(.*)"$/, '$1') });
    }
  }
  return out;
}

// Exact `models:` rows of PRICING.yaml: { id: { input, output, source_ref, last_verified } }.
export function pricingRows(text) {
  const models = {};
  let inModels = false;
  let cur = null;
  const val = (v) => { const x = v.replace(/\s+#.*$/, '').trim().replace(/^"(.*)"$/, '$1'); return x === 'null' || x === '' ? null : x; };
  for (const l of norm(text)) {
    if (/^\S/.test(l)) { inModels = /^models:\s*$/.test(l); cur = null; continue; }
    if (!inModels) continue;
    let m = /^ {2}([^\s:]+):\s*$/.exec(l);
    if (m) { cur = m[1].replace(/^"(.*)"$/, '$1'); models[cur] = { input: null, output: null, source_ref: null, last_verified: null }; continue; }
    m = /^ {4}(\w+):\s*(.*)$/.exec(l);
    if (!m || !cur) continue;
    const v = val(m[2]);
    if (m[1] === 'input_usd_per_m') models[cur].input = v === null ? null : Number(v);
    if (m[1] === 'output_usd_per_m') models[cur].output = v === null ? null : Number(v);
    if (m[1] === 'source_ref') models[cur].source_ref = v;
    if (m[1] === 'last_verified_utc') models[cur].last_verified = v;
  }
  return models;
}

// routedCheck(root, since, allowStale) -> { lines: [string], ok: boolean }
export function routedCheck(root, since, allowStale = []) {
  const lines = [];
  const routingPath = path.resolve(root, TABLES[0].rel);
  const pricingPath = path.resolve(root, TABLES[1].rel);
  if (!fs.existsSync(routingPath)) return { lines: [`ABSENT ${TABLES[0].rel}`], ok: true };
  if (!fs.existsSync(pricingPath)) return { lines: [`INVALID ${TABLES[1].rel} file is absent`], ok: false };
  const models = pricingRows(fs.readFileSync(pricingPath, 'utf8'));
  const entries = routedEntries(fs.readFileSync(routingPath, 'utf8'));
  const sinceMs = new Date(`${since}T00:00:00Z`).getTime();
  const allow = new Set(allowStale);
  const staleIds = new Set();
  let ok = true;
  const rate = (e) => typeof e.input === 'number' && Number.isFinite(e.input)
    && typeof e.output === 'number' && Number.isFinite(e.output);
  for (const en of entries) {
    const where = `${en.h} ${en.section}/${en.key} ${en.id}`;
    const id = en.id;
    if (!Object.hasOwn(models, id)) { lines.push(`MISSING ${where}`); ok = false; continue; }
    const e = models[id];
    if (!rate(e) || e.source_ref === null) { lines.push(`UNPRICED ${where}`); ok = false; continue; }
    const t = e.last_verified === null ? NaN : new Date(e.last_verified).getTime();
    if (Number.isNaN(t) || t < sinceMs) {
      staleIds.add(en.id);
      if (allow.has(en.id)) { lines.push(`ALLOWED ${where} ${e.last_verified}`); continue; }
      lines.push(`STALE ${where} ${e.last_verified}`); ok = false; continue;
    }
    lines.push(`OK ${where} ${e.last_verified}`);
  }
  for (const h of HARNESSES) {
    const tier = {};
    for (const en of entries) if (en.h === h && en.section === 'tiers') tier[en.key] = en.id;
    for (let i = 0; i < TIER_ORDER.length; i++) for (let j = i + 1; j < TIER_ORDER.length; j++) {
      const a = models[tier[TIER_ORDER[i]]], b = models[tier[TIER_ORDER[j]]];
      if (a && b && rate(a) && rate(b) && a.input > b.input) {
        lines.push(`ORDER ${h} ${TIER_ORDER[i]} ${TIER_ORDER[j]}`); ok = false;
      }
    }
  }
  for (const id of allowStale) {
    if (!staleIds.has(id)) { lines.push(`ALLOW-UNUSED ${id}`); ok = false; }
  }
  return { lines, ok };
}

function usage(msg) {
  process.stderr.write(`table-freshness: ${msg}\n`);
  process.stderr.write('usage: table-freshness.mjs check [--root <dir>] [--now <ISO>] [--horizon-days <n>]\n       table-freshness.mjs stamp-guard --base <rev> [--root <dir>] [--now <ISO>]\n       table-freshness.mjs routed --since <YYYY-MM-DD> [--allow-stale <id>[,<id>...]] [--root <dir>]\n');
  exit(2);
}

function parseFlags(args, allowed) {
  const flags = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (!allowed.includes(a)) usage(`unknown argument: ${a}`);
    if (i + 1 >= args.length) usage(`${a} needs a value`);
    flags[a] = args[++i];
  }
  return flags;
}

function main(argv) {
  const [cmd, ...rest] = argv;
  if (cmd === 'check') {
    const f = parseFlags(rest, ['--root', '--now', '--horizon-days']);
    const root = f['--root'] ? path.resolve(f['--root'])
      : path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
    let now = new Date();
    if (f['--now'] !== undefined) {
      now = new Date(f['--now']);
      if (Number.isNaN(now.getTime())) usage(`--now is not a valid date: ${f['--now']}`);
    }
    if (f['--horizon-days'] !== undefined && !POS_INT.test(f['--horizon-days'])) {
      usage(`--horizon-days must be a positive integer, got: ${f['--horizon-days']}`);
    }
    const envH = process.env.AAI_TABLES_HORIZON_DAYS;
    if (f['--horizon-days'] === undefined && envH !== undefined && envH !== '' && !POS_INT.test(envH)) {
      usage(`AAI_TABLES_HORIZON_DAYS must be a positive integer, got: ${envH}`);
    }
    const results = checkTables(root, { now, horizonDays: f['--horizon-days'] ?? null, env: process.env });
    for (const r of results) console.log(formatLine(r));
    exit(results.some((r) => r.status === 'LAPSED' || r.status === 'INVALID') ? 1 : 0);
  }
  if (cmd === 'stamp-guard') {
    const f = parseFlags(rest, ['--root', '--base', '--now']);
    if (f['--base'] === undefined) usage('stamp-guard needs --base <rev>');
    let gnow = new Date();
    if (f['--now'] !== undefined) {
      gnow = new Date(f['--now']);
      if (Number.isNaN(gnow.getTime())) usage(`--now is not a valid date: ${f['--now']}`);
    }
    const root = f['--root'] ? path.resolve(f['--root'])
      : path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
    let g;
    try { g = stampGuard(root, f['--base'], { now: gnow }); } catch (e) {
      if (e instanceof RangeError || e instanceof GitError) usage(e.message);
      throw e;
    }
    for (const r of g.results) {
      console.log(r.verdict === 'VIOLATION' ? `VIOLATION ${r.file} ${r.reason}` : `${r.verdict} ${r.file}`);
    }
    exit(g.violation ? 1 : 0);
  }
  if (cmd === 'routed') {
    const f = parseFlags(rest, ['--root', '--since', '--allow-stale']);
    if (f['--since'] === undefined) usage('routed needs --since <YYYY-MM-DD>');
    const sm = /^(\d{4})-(\d{2})-(\d{2})$/.exec(f['--since']);
    const sd = sm ? new Date(`${f['--since']}T00:00:00Z`) : null;
    if (!sd || Number.isNaN(sd.getTime()) || sd.toISOString().slice(0, 10) !== f['--since']) {
      usage(`--since must be a valid YYYY-MM-DD date, got: ${f['--since']}`);
    }
    const root = f['--root'] ? path.resolve(f['--root'])
      : path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
    const allow = f['--allow-stale'] === undefined ? []
      : f['--allow-stale'].split(',').map((x) => x.trim()).filter(Boolean);
    const r = routedCheck(root, f['--since'], allow);
    for (const line of r.lines) console.log(line);
    exit(r.ok ? 0 : 1);
  }
  usage(cmd ? `unknown subcommand: ${cmd}` : 'missing subcommand');
}

function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  runMain(() => main(process.argv.slice(2)));
}
