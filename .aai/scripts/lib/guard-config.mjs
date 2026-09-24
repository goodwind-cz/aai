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
// `product_doc_gate` (spec-product-docs-enforced D3) mirrors `close_gate`:
// same grammar, same fail-open default, consulted by close-work-item.mjs to
// choose warn-vs-refuse for its pre-write product-doc gate.
// `usage_capture_gate` (spec-telemetry-completeness) mirrors product_doc_gate:
// same grammar and fail-open default, consulted by close-work-item.mjs to
// choose warn-vs-refuse for its pre-write close-time usage-capture gate. Like
// product_doc_gate it is a close-only dial (NOT a pre-commit-hook concern), so
// the shell greps in pre-commit-checks.{sh,ps1} deliberately do not cover it.
// `evidence_path_gate` (CHANGE-0131 / spec-evidence-path-gate) mirrors both:
// same grammar and fail-open default, consulted by close-work-item.mjs to
// choose warn-vs-refuse when a closing doc's AC Status Evidence cells cite a
// path-shaped token that does not resolve from the repo root. Close-only —
// the shell greps deliberately do not cover it either.
// `mutation_gate` (spec-mutation-gate-for-tests D12) is the sixth dial of the
// same shape: consulted by close-work-item.mjs to choose warn-vs-refuse when
// a closing ride's spec is applicable (mutation_gate: v1 marker + tdd/hybrid
// strategy) and mutation-gate.mjs exits non-zero for it. Unlike the other
// five, AAI core SHIPS this one `enforce` (this repository is the one making
// the mutation-evidence claim) rather than report-only — readGuardConfig's
// own fail-open DEFAULT below stays report-only regardless (an absent key in
// a vendored project must still fail open), only the shipped
// docs/ai/docs-audit.yaml line differs.
export const GUARD_DIALS = ['independence', 'close_gate', 'doc_number_guard', 'product_doc_gate', 'usage_capture_gate', 'evidence_path_gate', 'mutation_gate'];

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
    product_doc_gate: 'report-only',
    usage_capture_gate: 'report-only',
    evidence_path_gate: 'report-only',
    mutation_gate: 'report-only',
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
    const m = line.match(/^(independence|close_gate|doc_number_guard|product_doc_gate|usage_capture_gate|evidence_path_gate|mutation_gate):\s*(\S+)/);
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

// ref_guard: armed | declined (spec-update-installs-ref-guard-undisclosed D2/
// D3) — a SEPARATE closed vocabulary from GUARD_DIALS, deliberately NOT added
// to that array: the grammar differs (armed/declined, not enforce/report-
// only) and, more importantly, the FAIL DIRECTION differs. GUARD_DIALS is
// grep-mirrored by pre-commit-checks.{sh,ps1}; ref_guard's mirror lives in
// install-pre-commit-hook.sh (D5's own thin shell grep — no node import
// there, per check-vendored-script-deps.mjs), conformance-tested by
// tests/skills/test-aai-hygiene-pack.sh test_618.
export const REF_GUARD_POLICY = ['armed', 'declined'];

// readRefGuardPolicy(dir) -> 'armed' | 'declined'
// Column-0 `ref_guard: <value>` line scan in docs-audit.yaml, same line
// discipline as readGuardConfig (indented/commented lines are never a dial;
// the value is the full non-whitespace token, so a glued comment fails the
// closed-set check). UNLIKE every enforce/report-only dial above, this FAILS
// CLOSED to 'armed': an absent file, an absent key, an indented or commented
// key, and any value outside {armed, declined} all mean 'armed' (D3). Falling
// open on the OTHER dials degrades a REPORT; falling open here would
// silently disarm a SAFEGUARD on a typo — the asymmetry is deliberate. An
// out-of-vocabulary value is named on stderr, mirroring the other dials'
// invalid-value notice.
export function readRefGuardPolicy(dir, opts = {}) {
  const warnPrefix = opts.warnPrefix ?? 'guard-config';
  const warn = opts.warn ?? (m => console.error(m));
  const cfgPath = path.join(dir, GUARD_CONFIG_BASENAME);
  let raw;
  try {
    raw = fs.readFileSync(cfgPath, 'utf8');
  } catch {
    return 'armed';   // absent file: fail-CLOSED default (D3)
  }
  for (const line of raw.split(/\r?\n/)) {
    const m = line.match(/^ref_guard:\s*(\S+)/);
    if (!m) continue;   // column-0 only; first occurrence wins
    if (m[1] === 'armed' || m[1] === 'declined') {
      return m[1];
    }
    warn(`${warnPrefix}: WARNING ref_guard value "${m[1]}" in ${cfgPath} is not `
      + '"armed" or "declined" — treating as armed (fail-CLOSED default)');
    return 'armed';   // invalid value: fail-CLOSED default (D3)
  }
  return 'armed';   // absent key: fail-CLOSED default (D3)
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
