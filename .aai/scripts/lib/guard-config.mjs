// guard-config.mjs — the SINGLE JS reader of the committed guard-policy file
// docs-audit.yaml (CHANGE-0009 D8, promoted from SPEC-0018 review W2).
//
// Before this module, docs-audit.yaml was parsed by three independent
// implementations (state.mjs readIndependencePolicy, the pre-commit-checks.sh
// grep, the shell grep embedded in install-pre-commit-hook.ps1) plus an
// undocumented file-presence coupling in docs-audit.mjs — drift-prone. The
// SHELL greps stay as deliberate thin greps (hooks must not grow importable-
// module plumbing) but a conformance test (tests/skills/test-aai-hygiene-pack.sh
// test_031) feeds the same fixture configs to this reader and the grep patterns
// and asserts they agree — drift now fails a test instead of diverging silently.
//
// Semantics (fail-open, per the pre-refactor state.mjs behavior):
// - a COLUMN-0 line scan (same discipline as the STATE line engine — an
//   indented or commented key is never a dial);
// - dial values: `enforce` | `report-only`; a present-but-INVALID value falls
//   open to report-only AND says so on stderr (CHANGE-0010 review W1 — an
//   operator who typoed `enforced` must not believe enforcement is on);
// - absent file / absent key: report-only, silently.

import fs from 'node:fs';
import path from 'node:path';

export const GUARD_CONFIG_BASENAME = 'docs-audit.yaml';

// The closed set of enforce/report-only guard dials this reader owns.
export const GUARD_DIALS = ['independence', 'close_gate', 'doc_number_guard'];

// Presence probe shared with docs-audit.mjs mode detection (enforced vs
// report-only hangs off this file's existence — documented coupling, D8).
export function guardConfigPresent(dir) {
  return fs.existsSync(path.join(dir, GUARD_CONFIG_BASENAME));
}

// readGuardConfig(dir) -> { present, cfgPath, raw,
//                           independence, close_gate, doc_number_guard }
// `dir` is the directory CONTAINING docs-audit.yaml (docs/ai for the real
// repo; state.mjs passes dirname(statePath) so fixtures isolate for free).
// opts.warnPrefix prefixes the invalid-value stderr notice (state.mjs passes
// 'state' to keep its pre-refactor wording byte-identical); opts.warn
// overrides the sink (tests).
export function readGuardConfig(dir, opts = {}) {
  const warnPrefix = opts.warnPrefix ?? 'guard-config';
  const warn = opts.warn ?? (m => console.error(m));
  const cfgPath = path.join(dir, GUARD_CONFIG_BASENAME);
  const out = {
    present: false,
    cfgPath,
    raw: null,
    independence: 'report-only',
    close_gate: 'report-only',
    doc_number_guard: 'report-only',
  };
  let raw;
  try {
    raw = fs.readFileSync(cfgPath, 'utf8');
  } catch {
    return out;   // absent file: fail-open defaults, silently
  }
  out.present = true;
  out.raw = raw;
  const seen = new Set();
  for (const line of raw.split(/\r?\n/)) {
    // Value = the full non-whitespace token (review CHANGE-0009 W2): a glued
    // comment ("enforce# note") therefore yields the token "enforce#", which
    // fails the closed-set check below and falls open WITH a warning — the
    // same verdict the hooks' grep boundary (enforce([[:space:]]|$)) reaches.
    const m = line.match(/^(independence|close_gate|doc_number_guard):\s*(\S+)/);
    if (!m || seen.has(m[1])) continue;   // column-0 only; first occurrence wins
    seen.add(m[1]);
    if (m[2] !== 'enforce' && m[2] !== 'report-only') {
      warn(`${warnPrefix}: WARNING ${m[1]} value "${m[2]}" in ${cfgPath} is not `
        + '"enforce" or "report-only" — treating as report-only (fail-open default)');
    }
    out[m[1]] = m[2] === 'enforce' ? 'enforce' : 'report-only';
  }
  return out;
}

// coupled_families (CHANGE-0035 / SPEC-0047 D7) — an OPTIONAL list-shaped key,
// read separately from the enforce/report-only dials above (a genuinely
// different grammar: a YAML block list, not a scalar). Line-parser-friendly:
//   coupled_families:
//     - CHANGE+SPEC-CHANGE
// Each list item is a '+'-joined group of prefixes sharing one counter (D7).
// Absent key / absent file / a group with fewer than 2 members -> ignored
// (fail-open: no coupling). AAI core ships this key ABSENT.
export function readCoupledFamilies(dir) {
  const cfgPath = path.join(dir, GUARD_CONFIG_BASENAME);
  let raw;
  try {
    raw = fs.readFileSync(cfgPath, 'utf8');
  } catch {
    return [];
  }
  const groups = [];
  let inKey = false;
  for (const line of raw.split(/\r?\n/)) {
    if (/^coupled_families:\s*(#.*)?$/.test(line)) { inKey = true; continue; }
    if (!inKey) continue;
    const item = line.match(/^[ \t]+-\s*([A-Za-z0-9+_-]+)\s*(#.*)?$/);
    if (item) {
      const members = item[1].split('+').map((s) => s.trim().toUpperCase()).filter(Boolean);
      if (members.length > 1) groups.push(members);
      else console.error(`WARNING: coupled_families item "${item[1]}" has fewer than 2 members — ignored (coupling OFF for it)`);
      continue;
    }
    if (/^[^\s#]/.test(line)) inKey = false; // next column-0 key ends the block
    else if (/^[ \t]+-/.test(line) && line.trim() !== '-') {
      // list item that did NOT match the member grammar (spaces, bad chars):
      // silent ignore here would silently disable coupling (review-20260717T181026Z NB-2)
      console.error(`WARNING: coupled_families item ${JSON.stringify(line.trim())} does not match TYPE+TYPE grammar — ignored (coupling OFF for it)`);
    }
  }
  return groups;
}

// The full coupled group containing `prefix` (including `prefix` itself), or
// the singleton [prefix] when it is in no configured group (the default,
// uncoupled case — D7 "AAI core ships the key absent").
export function coupledGroupFor(groups, prefix) {
  const p = String(prefix).toUpperCase();
  for (const g of groups) {
    if (g.includes(p)) return g;
  }
  return [p];
}
