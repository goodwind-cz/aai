// Consumer-owned project config reader (spec-consumer-config-routing-override).
//
// docs/ai/project-config.yaml is written by the consumer only; no AAI script
// writes it and /aai-update never touches it. Its one tenant today is the
// `routing_override@<harness>:` section (role -> model id) and the `pricing:`
// section (project price rows, a cost fallback behind the shipped table).
// Line-based parse, no YAML library, ALL OR NOTHING: any error means no
// override and no price from the file.
//
// Maps are null-prototype throughout so a role or harness named
// `constructor` / `toString` never resolves an inherited member.
import fs from 'node:fs';
import path from 'node:path';
import { HARNESS_VALUES } from './harness.mjs';
import { runCostUsd, loadPricing, attachProjectPrices } from './pricing.mjs';

export const PROJECT_CONFIG_REL = 'docs/ai/project-config.yaml';

// HARNESS_VALUES minus `unknown`: an override keyed to "undetected" would
// apply to whatever undetected harness runs.
export const OVERRIDE_HARNESSES = Object.freeze(HARNESS_VALUES.filter((h) => h !== 'unknown'));

// Closed role set; pinned equal to the dispatch TIERS key set by TEST-3694.
export const OVERRIDE_ROLES = Object.freeze([
  'Planning',
  'Code Review',
  'Implementation',
  'TDD Implementation',
  'Remediation',
  'Validation',
  'Technology extraction',
  'Bootstrap',
  'Implementation Preparation / Worktree decision',
  'Metrics Flush',
]);

export const PRICING_HEADER = 'pricing:';
const PRICE_FIELDS = Object.freeze(['input_usd_per_m', 'output_usd_per_m', 'source_url', 'last_verified_utc', 'provider', 'unverified_utc']);
const PRICE_REQUIRED = Object.freeze(['input_usd_per_m', 'output_usd_per_m', 'source_url', 'last_verified_utc']);
const PRICE_KEY_RE = /^[A-Za-z0-9][A-Za-z0-9._/-]*$/;
const PRICE_ENTRY_RE = /^ {2}(\S+):\s*$/;
const PRICE_FIELD_RE = /^ {4}([a-z_]+):\s*(.*?)\s*$/;
const RATE_RE = /^[0-9]+([.][0-9]+)?$/;
const TS_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const PROVIDER_RE = /^[a-z][a-z0-9-]*$/;

function validTimestamp(v) {
  if (!TS_RE.test(v)) return false;
  const t = Date.parse(v);
  return Number.isFinite(t) && new Date(t).toISOString().replace('.000Z', 'Z') === v;
}

const HEADER_RE = /^routing_override(?:@([^:\s]*))?:\s*$/;
const ROW_RE = /^ {2}(\S[^:#]*):\s*(\S+)\s*$/;
const MODEL_RE = /^[A-Za-z0-9][A-Za-z0-9._:/[\]-]*$/;

function unquote(v) {
  const m = v.match(/^(['"])(.*)\1$/);
  return m ? m[2] : v;
}

// parseProjectConfig(text) -> { ok, overrides, prices, notes, errors }
export function parseProjectConfig(text) {
  const overrides = Object.create(null);
  const prices = Object.create(null);
  const notes = [];
  const errors = [];
  const src = String(text ?? '').replace(/^﻿/, '');
  const lines = src.split(/\r?\n/);
  const seenHeaders = new Set();
  const seenPriceIds = new Set();
  let section = null; // { kind: 'active' | 'ignored' | 'unknown' | 'pricing', harness, roles }
  let entry = null;   // current pricing entry (dead: true when its header already errored)
  const closeEntry = () => {
    if (entry && !entry.dead) {
      const missing = PRICE_REQUIRED.find((f) => entry.seen[f] === undefined);
      if (missing) errors.push(`line ${entry.line}: model "${entry.id}" is missing field ${missing}`);
      else prices[entry.id] = entry.price;
    }
    entry = null;
  };

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const n = i + 1;
    const trimmed = raw.trim();
    if (trimmed === '' || trimmed.startsWith('#')) continue;

    if (!/^\s/.test(raw)) {
      closeEntry();
      const header = raw.replace(/\s+$/, '');
      if (header === PRICING_HEADER) {
        if (seenHeaders.has(header)) {
          errors.push(`line ${n}: repeated section "${header}"`);
          section = { kind: 'unknown', roles: Object.create(null) };
        } else {
          seenHeaders.add(header);
          section = { kind: 'pricing', roles: Object.create(null) };
        }
        continue;
      }
      const m = header.match(HEADER_RE);
      if (!m) {
        errors.push(`line ${n}: unknown section "${header}"`);
        section = { kind: 'unknown', roles: Object.create(null) };
        continue;
      }
      if (seenHeaders.has(header)) {
        errors.push(`line ${n}: repeated section "${header}"`);
        section = { kind: 'unknown', roles: Object.create(null) };
        continue;
      }
      seenHeaders.add(header);
      const suffix = m[1];
      if (suffix === undefined) {
        notes.push(`ignored section "${header}": no harness suffix (use routing_override@<harness>, one of ${OVERRIDE_HARNESSES.join(', ')})`);
        section = { kind: 'ignored', roles: Object.create(null) };
        continue;
      }
      if (!OVERRIDE_HARNESSES.includes(suffix)) {
        notes.push(`ignored section "${header}": harness "${suffix}" is not one of ${OVERRIDE_HARNESSES.join(', ')}`);
        section = { kind: 'ignored', roles: Object.create(null) };
        continue;
      }
      section = { kind: 'active', harness: suffix, roles: Object.create(null) };
      if (!overrides[suffix]) overrides[suffix] = Object.create(null);
      continue;
    }

    // Indented, non-comment line: a row.
    if (!section) { errors.push(`line ${n}: row outside a section`); continue; }
    if (section.kind === 'unknown') continue; // the header already errored
    if (section.kind === 'pricing') {
      const em = raw.match(PRICE_ENTRY_RE);
      if (em) {
        closeEntry();
        const id = unquote(em[1]);
        if (!PRICE_KEY_RE.test(id) || id.toLowerCase() === 'null' || id.toLowerCase() === 'unknown') {
          errors.push(`line ${n}: invalid model id "${em[1]}"`);
          entry = { dead: true };
        } else if (Object.prototype.hasOwnProperty.call(prices, id) || seenPriceIds.has(id)) {
          errors.push(`line ${n}: duplicate model "${id}"`);
          entry = { dead: true };
        } else {
          seenPriceIds.add(id);
          entry = { id, line: n, seen: Object.create(null), price: { input: null, output: null, source_url: null, last_verified_utc: null, provider: null, unverified_utc: null, line: n } };
        }
        continue;
      }
      const fm = raw.match(PRICE_FIELD_RE);
      if (!fm) { errors.push(`line ${n}: malformed row "${trimmed}"`); continue; }
      if (!entry) { errors.push(`line ${n}: field outside a model "${trimmed}"`); continue; }
      if (entry.dead) continue;
      const field = fm[1];
      if (!PRICE_FIELDS.includes(field)) { errors.push(`line ${n}: unknown field "${field}"`); continue; }
      if (entry.seen[field] !== undefined) { errors.push(`line ${n}: duplicate field "${field}"`); continue; }
      const val = unquote(fm[2]);
      entry.seen[field] = val;
      if (field === 'input_usd_per_m' || field === 'output_usd_per_m') {
        if (!RATE_RE.test(val)) { errors.push(`line ${n}: invalid rate "${fm[2]}" for ${field}`); continue; }
        entry.price[field === 'input_usd_per_m' ? 'input' : 'output'] = Number(val);
      } else if (field === 'source_url') {
        if (!/^https:\/\/\S+$/.test(val)) { errors.push(`line ${n}: invalid source_url "${fm[2]}"`); continue; }
        entry.price.source_url = val;
      } else if (field === 'provider') {
        if (!PROVIDER_RE.test(val)) { errors.push(`line ${n}: invalid provider "${fm[2]}"`); continue; }
        entry.price.provider = val;
      } else {
        if (!validTimestamp(val)) { errors.push(`line ${n}: invalid timestamp "${fm[2]}" for ${field}`); continue; }
        entry.price[field] = val;
      }
      continue;
    }
    const rm = raw.match(ROW_RE);
    if (!rm) { errors.push(`line ${n}: malformed row "${trimmed}"`); continue; }
    const key = rm[1].trim();
    if (!OVERRIDE_ROLES.includes(key)) { errors.push(`line ${n}: unknown role "${key}"`); continue; }
    const model = unquote(rm[2]);
    const isNullId = model.toLowerCase() === 'null';
    if (isNullId || !MODEL_RE.test(model)) { errors.push(`line ${n}: invalid model id "${rm[2]}"`); continue; }
    if (section.roles[key] !== undefined) { errors.push(`line ${n}: duplicate role "${key}"`); continue; }
    section.roles[key] = model;
    if (section.kind === 'active') overrides[section.harness][key] = model;
  }

  closeEntry();
  if (errors.length) return { ok: false, overrides: Object.create(null), prices: Object.create(null), notes, errors };
  return { ok: true, overrides, prices, notes, errors };
}

// loadProjectConfig(root) -> { status: absent | ok | malformed, file, overrides, notes, errors }
export function loadProjectConfig(root) {
  const file = path.join(root, PROJECT_CONFIG_REL);
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch (error) {
    // Only a missing file is absence. Anything else at the path (a directory,
    // an unreadable file) is a config the consumer meant to have and cannot
    // be read: malformed, so dispatch NOTEs it and CAT-22 WARNs, never silence.
    if (error && error.code === 'ENOENT') {
      return { status: 'absent', file: PROJECT_CONFIG_REL, overrides: Object.create(null), prices: Object.create(null), notes: [], errors: [] };
    }
    return { status: 'malformed', file: PROJECT_CONFIG_REL, overrides: Object.create(null), prices: Object.create(null), notes: [], errors: [`unreadable (${(error && error.code) || 'read error'})`] };
  }
  const r = parseProjectConfig(text);
  return { status: r.ok ? 'ok' : 'malformed', file: PROJECT_CONFIG_REL, overrides: r.overrides, prices: r.prices, notes: r.notes, errors: r.errors };
}

// loadCostPricing(root, pricingPath, cfg) -> the shipped pricing with the
// project prices attached when the file is valid (D-PREC); the shipped table
// alone for an absent or malformed file. The one costing seam of every reader.
export function loadCostPricing(root, pricingPath, cfg = loadProjectConfig(root)) {
  const pricing = loadPricing(pricingPath);
  return cfg.status === 'ok' ? attachProjectPrices(pricing, cfg.prices) : pricing;
}

// overrideFor(overrides, harness, role) -> model id or null.
export function overrideFor(overrides, harness, role) {
  const h = overrides[harness];
  return (h && h[role]) || null;
}

// projectConfigNotes(cfg) -> NOTE texts (without any tool prefix) shared by
// the dispatch (stderr) and the doctor.
export function projectConfigNotes(cfg) {
  const lines = [...cfg.notes];
  if (cfg.status === 'malformed') {
    for (const e of cfg.errors) lines.push(e);
    lines.push('file is malformed: no override from it is applied');
  }
  return lines;
}

// describeOverride({ harness, role, model }) -> "<harness>/<role> -> <model>";
// the one spelling shared by the dispatch NOTE and the doctor CAT-22 line.
export function describeOverride(o) {
  return o.harness + '/' + o.role + ' -> ' + o.model;
}

// isPricedModel(pricing, model) -> true when lib/pricing.mjs can cost the id
// (exact, bracket-suffixed or longest-prefix), the resolver metrics-flush uses.
export function isPricedModel(pricing, model) {
  if (runCostUsd(pricing, model, 1, 1) === null) return false;
  return true;
}

// unpricedOverrides(overrides, pricing) -> [{ harness, role, model }] for every
// active override whose model id cannot be costed.
export function unpricedOverrides(overrides, pricing) {
  const out = [];
  for (const harness of Object.keys(overrides)) {
    for (const role of Object.keys(overrides[harness])) {
      const model = overrides[harness][role];
      if (!isPricedModel(pricing, model)) out.push({ harness, role, model });
    }
  }
  return out;
}
