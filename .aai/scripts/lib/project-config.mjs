// Consumer-owned project config reader (spec-consumer-config-routing-override).
//
// docs/ai/project-config.yaml is written by the consumer only; no AAI script
// writes it and /aai-update never touches it. Its one tenant today is the
// `routing_override@<harness>:` section (role -> model id). Line-based parse,
// no YAML library, ALL OR NOTHING: any error means no override from the file.
//
// Maps are null-prototype throughout so a role or harness named
// `constructor` / `toString` never resolves an inherited member.
import fs from 'node:fs';
import path from 'node:path';
import { HARNESS_VALUES } from './harness.mjs';

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

const HEADER_RE = /^routing_override(?:@([^:\s]*))?:\s*$/;
const ROW_RE = /^ {2}(\S[^:#]*):\s*(\S+)\s*$/;
const MODEL_RE = /^[A-Za-z0-9][A-Za-z0-9._:/[\]-]*$/;

function unquote(v) {
  const m = v.match(/^(['"])(.*)\1$/);
  return m ? m[2] : v;
}

// parseProjectConfig(text) -> { ok, overrides, notes, errors }
export function parseProjectConfig(text) {
  const overrides = Object.create(null);
  const notes = [];
  const errors = [];
  const src = String(text ?? '').replace(/^﻿/, '');
  const lines = src.split(/\r?\n/);
  const seenHeaders = new Set();
  let section = null; // { kind: 'active' | 'ignored' | 'unknown', harness, roles }

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const n = i + 1;
    const trimmed = raw.trim();
    if (trimmed === '' || trimmed.startsWith('#')) continue;

    if (!/^\s/.test(raw)) {
      const header = raw.replace(/\s+$/, '');
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
    const rm = raw.match(ROW_RE);
    if (!rm) { errors.push(`line ${n}: malformed row "${trimmed}"`); continue; }
    const key = rm[1].trim();
    if (!OVERRIDE_ROLES.includes(key)) { errors.push(`line ${n}: unknown role "${key}"`); continue; }
    const model = unquote(rm[2]);
    if (model === 'null' || !MODEL_RE.test(model)) { errors.push(`line ${n}: invalid model id "${rm[2]}"`); continue; }
    if (section.roles[key] !== undefined) { errors.push(`line ${n}: duplicate role "${key}"`); continue; }
    section.roles[key] = model;
    if (section.kind === 'active') overrides[section.harness][key] = model;
  }

  if (errors.length) return { ok: false, overrides: Object.create(null), notes, errors };
  return { ok: true, overrides, notes, errors };
}

// loadProjectConfig(root) -> { status: absent | ok | malformed, file, overrides, notes, errors }
export function loadProjectConfig(root) {
  const file = path.join(root, PROJECT_CONFIG_REL);
  let text;
  try { text = fs.readFileSync(file, 'utf8'); } catch {
    return { status: 'absent', file: PROJECT_CONFIG_REL, overrides: Object.create(null), notes: [], errors: [] };
  }
  const r = parseProjectConfig(text);
  return { status: r.ok ? 'ok' : 'malformed', file: PROJECT_CONFIG_REL, overrides: r.overrides, notes: r.notes, errors: r.errors };
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
