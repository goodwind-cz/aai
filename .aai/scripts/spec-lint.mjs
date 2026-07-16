#!/usr/bin/env node
// spec-lint — deterministic structural validation of spec documents
// (CHANGE spec-lint / SPEC spec-spec-lint, OpenSpec pattern per RES-0001 P3).
//
// BOUNDARY (SPEC spec-spec-lint D1): this tool owns INTRA-SPEC STRUCTURE —
// AC ids unique/sequential, AC status tokens, done-needs-evidence, Test Plan
// row -> Spec-AC mapping, SPEC-FROZEN vs strategy/AC-table consistency,
// ceremony_level enum, and AC rows the shared parser silently drops.
// docs-audit owns LIFECYCLE/DRIFT (orphans, frontmatter schema, staleness,
// false-done, close gate, telemetry, body lint). Shared token rules come from
// lib/docs-model.mjs so the engines cannot diverge on what a valid cell IS.
//
// Usage:
//   node .aai/scripts/spec-lint.mjs              # all docs/specs/**/*.md with type: spec
//   node .aai/scripts/spec-lint.mjs --path <p>   # exactly one file, any type
//   node .aai/scripts/spec-lint.mjs --json       # machine-readable result
//
// Exit codes: 0 clean / 1 findings / 2 usage error or unreadable --path.
// REPORT-ONLY: never writes any file, never emits events, never a hard gate
// in v1 — wired as an advisory line in PLANNING (post-freeze) and VALIDATION
// (step 1). No whitelist mechanism in v1: real corpus findings get FIXED.

import fs from 'node:fs';
import path from 'node:path';
import {
  normalizeNewlines, parseFrontmatter, parseAcTable, normalizeAcStatus,
  specFrozenInBody, walk, toPosix, parseLeanAcTable, parseDeltasSection,
} from './lib/docs-model.mjs';

const ROOT = process.cwd();
const CEREMONY_ENUM = ['0', '1', '2', '3'];
const AC_ID_RE = /^Spec-AC-(\d{2})$/;
const AC_RANGE_RE = /^Spec-AC-(\d{2})\.\.(\d{2})$/;

function usage() {
  console.error(
    'Usage: spec-lint [--path <file>] [--json]\n' +
    '  Lints spec documents for intra-spec structure (report-only).\n' +
    '  Default scope: docs/specs/**/*.md with frontmatter type: spec.\n' +
    '  Exit: 0 clean | 1 findings | 2 usage error / unreadable --path.',
  );
}

function fail(msg) {
  console.error(`spec-lint: ${msg}`);
  usage();
  process.exit(2);
}

function parseArgs(argv) {
  const args = { path: null, json: false };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--json') args.json = true;
    else if (tok === '--path') {
      args.path = argv[++i];
      if (args.path === undefined || args.path.startsWith('--')) fail('--path needs a value');
    } else fail(`unknown flag: ${tok}`);
  }
  return args;
}

// 1-based line number of a character offset in normalized content.
function lineAt(norm, offset) {
  return norm.slice(0, offset).split('\n').length;
}

// One-line local mirror of the docs-audit-core evidence rule (SPEC D2):
// an Evidence cell is empty when blank, em-dash, or dash.
const rowHasEvidence = (row) => {
  const e = (row['Evidence'] ?? '').trim();
  return e !== '' && e !== '—' && e !== '-';
};

// Split a markdown table line into cells, honoring escaped pipes (\|).
// NEW parser — nothing else in the repo reads the Test Plan table (SPEC D2).
function splitCells(line) {
  const parts = line.split(/(?<!\\)\|/).map((c) => c.trim());
  return parts.slice(1, parts.length - 1);
}

// Parse the "## Test Plan" table: rows whose first cell is TEST-xxx.
// Returns { present, rows: [{ testId, acCell, line }] }.
function parseTestPlan(norm) {
  const m = norm.match(/(?:^|\n)##\s+Test Plan\b[^\n]*\n([\s\S]+?)(?=\n##\s|\n*$)/i);
  if (!m) return { present: false, rows: [] };
  const sectionStart = m.index + m[0].indexOf(m[1]);
  const rows = [];
  let offset = 0;
  for (const line of m[1].split('\n')) {
    const lineNo = lineAt(norm, sectionStart + offset);
    offset += line.length + 1;
    if (!line.trim().startsWith('|')) continue;
    const cells = splitCells(line);
    if (!cells.length || !/^TEST-\d+$/.test(cells[0])) continue;
    rows.push({ testId: cells[0], acCell: cells[1] ?? '', line: lineNo });
  }
  return { present: true, rows };
}

// Expand a Test Plan Spec-AC cell into { ids, malformed } token lists.
// Grammar: comma/space-separated tokens, each `Spec-AC-NN` or `Spec-AC-NN..MM`.
function expandAcRefs(cell) {
  const ids = [];
  const malformed = [];
  const raw = String(cell ?? '').trim();
  if (raw === '' || raw === '—' || raw === '-') return { ids, malformed: [raw === '' ? '(empty)' : raw] };
  for (const tok of raw.split(/[,\s]+/).filter(Boolean)) {
    const single = tok.match(AC_ID_RE);
    if (single) { ids.push(tok); continue; }
    const range = tok.match(AC_RANGE_RE);
    if (range) {
      const from = Number(range[1]);
      const to = Number(range[2]);
      if (from <= to) {
        for (let n = from; n <= to; n += 1) ids.push(`Spec-AC-${String(n).padStart(2, '0')}`);
        continue;
      }
    }
    malformed.push(tok);
  }
  return { ids, malformed };
}

// Lint one document's content. Pure: no filesystem, no git. Returns findings
// [{ rule, detail, line }] — rel/id are attached by the caller.
export function lintContent(content) {
  const findings = [];
  const add = (rule, detail, line = null) => findings.push({ rule, detail, line });
  const norm = normalizeNewlines(content);
  const fm = parseFrontmatter(norm) ?? {};
  const ac = parseAcTable(norm);

  // ceremony_level enum (advisory freeze-time twin of the close-gate check;
  // absent or YAML null is legacy implicit level 2, never flagged).
  let level = 2;
  const clRaw = fm.ceremony_level;
  if (clRaw !== undefined && clRaw !== null) {
    if (!CEREMONY_ENUM.includes(String(clRaw))) {
      add('ceremony-level-invalid', `ceremony_level "${clRaw}" is not one of 0 | 1 | 2 | 3`);
    } else {
      level = Number(clRaw);
    }
  }

  // --- AC Status table structure ------------------------------------------
  const knownIds = new Set();
  if (ac.hasGate) {
    const nums = [];
    for (const row of ac.rows) {
      const id = row['Spec-AC'];
      if (knownIds.has(id)) add('ac-id-duplicate', `${id} appears more than once in the AC Status table`);
      knownIds.add(id);
      const m = id.match(AC_ID_RE);
      if (m) nums.push(Number(m[1]));
      else add('ac-id-malformed', `AC id "${id}" does not match Spec-AC-NN (two digits)`);
      const rawStatus = row['Status'] ?? '';
      const st = normalizeAcStatus(rawStatus);
      if (rawStatus.trim() && !st.canonical) {
        add('ac-status-invalid', `${id} status "${rawStatus}" is not a canonical AC status`);
      }
      if (st.status === 'done' && !rowHasEvidence(row)) {
        add('done-without-evidence', `${id} is done but Evidence is empty`);
      }
    }
    const uniq = [...new Set(nums)].sort((a, b) => a - b);
    if (uniq.length) {
      const missing = [];
      for (let n = 1; n <= uniq[uniq.length - 1]; n += 1) {
        if (!uniq.includes(n)) missing.push(`Spec-AC-${String(n).padStart(2, '0')}`);
      }
      if (missing.length) add('ac-id-gap', `AC ids are not sequential from Spec-AC-01: missing ${missing.join(', ')}`);
    }

    // Rows the shared parser silently DROPPED (cell-count mismatch, e.g.
    // markdown-escaped pipes in a cell): invisible to docs-audit, the index,
    // and the close gate — the exact SPEC-0012 Spec-AC-08 shape.
    const section = norm.match(/(?:^|\n)##\s+Acceptance Criteria Status\b[^\n]*\n([\s\S]+?)(?=\n##\s|\n*$)/i);
    if (section) {
      const sectionStart = section.index + section[0].indexOf(section[1]);
      let offset = 0;
      for (const line of section[1].split('\n')) {
        const lineNo = lineAt(norm, sectionStart + offset);
        offset += line.length + 1;
        // Review F1: anchor the capture to the id CELL — the old \S* greedily
        // swallowed pipes on compact rows (|Spec-AC-01|a|...), mangling the id
        // into the whole pipe-run and firing a spurious unparseable finding.
        const raw = line.match(/^\|\s*(Spec-AC-\d+)(?=\s|\|)/);
        if (raw && !knownIds.has(raw[1])) {
          add('ac-row-unparseable', `row for ${raw[1]} was dropped by the shared table parser (cell count breaks the header — check escaped/raw pipes in a cell); it is invisible to docs-audit, the index, and the close gate`, lineNo);
        }
      }
    }
  } else if (level <= 1) {
    // L0/L1 lean table (no canonical gate): seed knownIds so the Test-Plan
    // mapping check below doesn't flag every lean AC id as unknown (validation
    // F1 second face — the lean ids ARE the spec's ACs at these levels).
    const lean = parseLeanAcTable(norm);
    for (const row of lean.rows) {
      const id = row['Spec-AC'];
      if (id) knownIds.add(id);
    }
  }

  // --- Test Plan -> Spec-AC mapping -----------------------------------------
  const tp = parseTestPlan(norm);
  for (const row of tp.rows) {
    const { ids, malformed } = expandAcRefs(row.acCell);
    for (const tok of malformed) {
      add('test-ac-malformed', `${row.testId} Spec-AC cell token "${tok}" does not match Spec-AC-NN or Spec-AC-NN..MM`, row.line);
    }
    for (const id of ids) {
      if (!knownIds.has(id)) {
        add('test-ac-unknown', `${row.testId} references ${id}, which is not in the AC Status table`, row.line);
      }
    }
  }

  // --- Deltas shape validation (RFC-0011, delta-spec lifecycle) -------------
  // The optional `## Deltas` section declares intended requirement changes;
  // spec-lint checks their SHAPE via the shared parseDeltasSection reader (same
  // grammar the canonical layer accepts — one source of truth). A spec with NO
  // `## Deltas` section produces ZERO findings here (legacy specs untouched);
  // a present-but-empty section is a valid state. Each parsed violation renders
  // one-for-one into a finding with its D2 code and the block's line number.
  const deltas = parseDeltasSection(norm);
  for (const v of deltas.violations) add(v.code, v.detail, v.line ?? null);

  // --- SPEC-FROZEN consistency ----------------------------------------------
  // Strategy is exempt at levels 0/1 (RFC-0009 lean artifacts). The AC table:
  // L0 exempt (tech-note lives in the CHANGE doc); L1 satisfied by a LEAN
  // table (ids+status) — must match the close gate, which now accepts it
  // (CHANGE l1-close-gate); L2+ require the canonical gate table. Reporting a
  // frozen-without-ac-table on an L1 lean spec that the gate passes CLEAN was
  // a real tool-disagreement (validation F1).
  if (specFrozenInBody(norm)) {
    if (level >= 2) {
      const strat = norm.match(/^-\s*Strategy:\s*(\S+)/m);
      const strategy = strat ? strat[1].toLowerCase() : null;
      if (!strategy || strategy === 'undecided') {
        add('frozen-without-strategy', `SPEC-FROZEN is true but implementation strategy is ${strategy ? `"${strategy}"` : 'missing'}`);
      }
    }
    if (level >= 2 && !ac.hasGate) {
      add('frozen-without-ac-table', 'SPEC-FROZEN is true but no canonical Acceptance Criteria Status gate table is present');
    } else if (level === 1 && !ac.hasGate) {
      const lean = parseLeanAcTable(norm);
      if (lean.rows.length === 0) {
        add('frozen-without-ac-table', 'SPEC-FROZEN is true (ceremony_level 1) but no Acceptance Criteria table (lean or canonical) is present');
      }
    }
  }

  return findings;
}

function lintFileAt(absPath, rel) {
  let content;
  try {
    content = fs.readFileSync(absPath, 'utf8');
  } catch {
    return null;
  }
  const fm = parseFrontmatter(normalizeNewlines(content));
  const id = fm?.id ?? null;
  return { id, findings: lintContent(content).map((f) => ({ rel, id, ...f })) };
}

function main() {
  const args = parseArgs(process.argv);
  const findings = [];
  let scanned = 0;
  let skipped = 0;

  if (args.path) {
    const abs = path.isAbsolute(args.path) ? args.path : path.join(ROOT, args.path);
    if (!fs.existsSync(abs) || !fs.statSync(abs).isFile()) fail(`file not found or unreadable: "${args.path}"`);
    const res = lintFileAt(abs, toPosix(path.relative(ROOT, abs)));
    if (!res) fail(`file not found or unreadable: "${args.path}"`);
    scanned = 1;
    findings.push(...res.findings);
  } else {
    for (const abs of walk(path.join(ROOT, 'docs/specs'))) {
      const rel = toPosix(path.relative(ROOT, abs));
      let content;
      try {
        content = fs.readFileSync(abs, 'utf8');
      } catch {
        skipped += 1;
        continue;
      }
      const fm = parseFrontmatter(normalizeNewlines(content));
      if (String(fm?.type ?? '').toLowerCase() !== 'spec') { skipped += 1; continue; }
      scanned += 1;
      findings.push(...lintContent(content).map((f) => ({ rel, id: fm?.id ?? null, ...f })));
    }
  }

  const clean = findings.length === 0;
  if (args.json) {
    console.log(JSON.stringify({ scanned, skipped, findings, clean }, null, 2));
  } else {
    console.log(`## Spec Lint — ${new Date().toISOString().slice(0, 10)}`);
    console.log('');
    console.log(`- Scanned: ${scanned} spec doc(s) | Skipped: ${skipped} non-spec | Findings: ${findings.length}${args.path ? ` | Scope: ${args.path}` : ''}`);
    console.log('');
    if (clean) {
      console.log('LINT PASS: no structural findings.');
    } else {
      console.log('LINT FINDINGS (report-only — advisory, never a hard gate in v1):');
      for (const f of findings) {
        console.log(`- ${f.rel}${f.line ? `:${f.line}` : ''} [${f.rule}] ${f.detail}`);
      }
    }
  }
  process.exit(clean ? 0 : 1);
}

// Run only when executed directly (tests may import lintContent).
import { fileURLToPath } from 'node:url';
function realOrResolve(p) {
  try { return fs.realpathSync(p); } catch { return path.resolve(p); }
}
if (process.argv[1] && realOrResolve(process.argv[1]) === realOrResolve(fileURLToPath(import.meta.url))) {
  main();
}
