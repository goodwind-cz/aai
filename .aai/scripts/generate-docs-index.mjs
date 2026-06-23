#!/usr/bin/env node
// Generate docs/INDEX.md from frontmatter and Acceptance Criteria Status tables
// across docs/{issues,rfc,specs,requirements,releases}/**/*.md.
//
// RFC-0001 layer 4. Idempotent. Tolerant to legacy docs (no frontmatter,
// no Spec-AC table) — they appear in the Legacy section.
//
// Failure MODE: degrade-and-report by DEFAULT. Schema violations (unknown
// status enum, malformed Review-By/dates) never abort the run — the offending
// docs are skipped, listed in the "Skipped (schema violations)" section of the
// index, mirrored to a companion docs/INDEX.violations.md, and printed as
// warnings. A best-effort docs/INDEX.md is ALWAYS written. Pass --strict (or
// the `lint-docs` subcommand) to flip back to fatal-abort (exit 1 on any
// violation) for CI / pre-commit enforcement. The schema RULES are unchanged;
// only the failure mode differs between default and strict.
//
// Marker discipline: refuses to overwrite an existing INDEX.md whose
// first non-empty line is not the auto-generated marker.

import fs from 'node:fs';
import path from 'node:path';
import {
  DOC_STATUS_ENUM, AC_STATUS_ENUM, walk,
  parseFrontmatter, parseAcTable, parseReviewBy, extractReferences,
} from './lib/docs-model.mjs';
import { runAudit, suggestedStep, loadConfig, firstCommitDate } from './lib/docs-audit-core.mjs';

const ROOT = process.cwd();
const ARGV = process.argv.slice(2);
// --strict / lint-docs: fatal-abort on any non-legacy schema violation (CI / pre-commit gate).
// Default (no flag): degrade-and-report — always write a best-effort index.
// --continue-on-error: retained as a no-op alias (degrade-and-report is now the default).
const strict = ARGV.includes('--strict') || ARGV.includes('lint-docs');
const SCAN_DIRS = ['docs/issues', 'docs/rfc', 'docs/specs', 'docs/requirements', 'docs/releases'];
const OUT_PATH = path.join(ROOT, 'docs/INDEX.md');
const VIOLATIONS_PATH = path.join(ROOT, 'docs/INDEX.violations.md');
const MARKER = '# Docs Index — auto-generated, DO NOT EDIT';
const VIOLATIONS_MARKER = '# Docs Index Violations — auto-generated, DO NOT EDIT';

const today = new Date();
const todayUTC = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));

function checkMarker() {
  if (!fs.existsSync(OUT_PATH)) return true;
  const existing = fs.readFileSync(OUT_PATH, 'utf8');
  const firstLine = existing.split('\n').find(l => l.trim().length > 0) ?? '';
  return firstLine.trim() === MARKER;
}

function ymd(d) {
  return d.toISOString().slice(0, 10);
}

// Manage docs/INDEX.violations.md: write it when there are skipped violations,
// remove it when the repo is clean. Refuses to touch a pre-existing file whose
// first non-empty line is not our marker (don't clobber a user's file).
function writeViolationsReport(skipped) {
  if (fs.existsSync(VIOLATIONS_PATH)) {
    const firstLine = fs.readFileSync(VIOLATIONS_PATH, 'utf8').split('\n').find(l => l.trim().length > 0) ?? '';
    if (firstLine.trim() !== VIOLATIONS_MARKER) {
      console.warn(`WARNING: ${path.relative(ROOT, VIOLATIONS_PATH)} exists without the auto-generated marker — leaving it untouched.`);
      return;
    }
  }
  if (skipped.length === 0) {
    if (fs.existsSync(VIOLATIONS_PATH)) fs.rmSync(VIOLATIONS_PATH);
    return;
  }
  const out = [
    VIOLATIONS_MARKER,
    '',
    `Generated: ${new Date().toISOString()}`,
    '',
    'These docs were SKIPPED from docs/INDEX.md because their frontmatter or',
    'Acceptance-Criteria table violates the schema. The index is still produced',
    '(degrade-and-report); fix the docs below and re-run the generator. Run',
    '`node .aai/scripts/generate-docs-index.mjs --strict` to fail CI on these.',
    '',
    ...skipped.map(f => `- ${f}`),
    '',
  ].join('\n');
  fs.mkdirSync(path.dirname(VIOLATIONS_PATH), { recursive: true });
  fs.writeFileSync(VIOLATIONS_PATH, out);
}

function main() {
  if (!checkMarker()) {
    console.error(`ERROR: ${path.relative(ROOT, OUT_PATH)} exists without the auto-generated marker.`);
    console.error(`       Rename or delete it, or restore the marker line: "${MARKER}"`);
    process.exit(2);
  }

  const docs = [];
  const warnings = [];
  const failures = [];

  for (const dir of SCAN_DIRS) {
    for (const filePath of walk(path.join(ROOT, dir))) {
      const rel = path.relative(ROOT, filePath);
      const content = fs.readFileSync(filePath, 'utf8');
      const fm = parseFrontmatter(content);
      const type = path.basename(path.dirname(filePath));
      if (!fm) {
        warnings.push(`legacy doc (no frontmatter): ${rel}`);
        docs.push({ path: rel, id: path.basename(rel, '.md'), type, status: 'legacy', legacy: true, ac: { hasGate: false, rows: [] } });
        continue;
      }
      const status = (fm.status ?? 'draft').toLowerCase();
      if (!DOC_STATUS_ENUM.has(status)) {
        failures.push(`${rel}: unknown frontmatter status "${fm.status}"`);
        continue;
      }
      const acTable = parseAcTable(content);
      for (const row of acTable.rows) {
        const s = (row['Status'] ?? '').toLowerCase();
        if (s && !AC_STATUS_ENUM.has(s)) {
          failures.push(`${rel}: unknown AC status "${row['Status']}" for ${row['Spec-AC']}`);
        }
        // ISO date, skill label (TDD/Loop/code-review/manual/deferred), or
        // label:date combo (CHANGE-0001 D4); only dated forms feed overdue checks
        const rb = parseReviewBy(row['Review-By']);
        if (rb.kind === 'invalid') {
          failures.push(`${rel}: invalid Review-By "${rb.raw}" for ${row['Spec-AC']} (ISO date, skill label, or label:date)`);
        }
        row._parsedReviewBy = rb.date;
      }
      docs.push({ path: rel, id: fm.id ?? path.basename(rel, '.md'), type, status, fm, ac: acTable, legacy: false });
    }
  }

  // Failure mode. DEFAULT: degrade-and-report — skip the offending docs, keep
  // generating, and surface the violations (index section + companion file +
  // stderr warnings). STRICT (--strict / lint-docs): fatal-abort on any
  // non-legacy violation, for CI / pre-commit enforcement.
  // CHANGE-0002 D13: during the legacy migration window (legacy_until_date
  // set), violations in legacy-classified docs auto-demote to the Skipped
  // section regardless of mode — the window closes itself once legacy docs
  // are migrated.
  let skipped = [];
  if (failures.length > 0) {
    const legacyUntil = loadConfig(ROOT)?.legacy_until_date ?? null;
    const hard = [];
    for (const f of failures) {
      const rel = f.slice(0, f.indexOf(': '));
      const first = legacyUntil ? firstCommitDate(ROOT, rel) : null;
      if (first && first < legacyUntil) skipped.push(`${f} [legacy — auto-skipped]`);
      else hard.push(f);
    }
    if (hard.length > 0 && strict) {
      console.error('FAIL (strict): schema violations:');
      for (const f of hard) console.error(`  - ${f}`);
      console.error('Fix the docs above, or run without --strict for a best-effort index.');
      process.exit(1);
    }
    // Non-strict default: never abort. Skip the offending docs and report them.
    skipped.push(...hard);
    if (hard.length > 0) {
      console.warn(`WARNING: ${hard.length} schema violation(s) — skipped from index (run with --strict to fail):`);
      for (const f of hard) console.warn(`  - ${f}`);
    }
    const failedRels = new Set(failures.map(f => f.slice(0, f.indexOf(': '))));
    for (let i = docs.length - 1; i >= 0; i -= 1) {
      if (failedRels.has(docs[i].path)) docs.splice(i, 1);
    }
  }

  const knownIds = new Set(docs.map(d => d.id));
  const overdue = [];
  const deferredItems = [];
  const blockedItems = [];
  const brokenRefs = [];

  for (const d of docs) {
    for (const row of d.ac.rows) {
      const s = (row['Status'] ?? '').toLowerCase();
      if (s === 'deferred' || s === 'blocked') {
        const entry = { doc: d.id, ac: row['Spec-AC'], status: s, reviewBy: row['Review-By'] ?? '—', notes: row['Notes'] ?? '—' };
        if (s === 'deferred') deferredItems.push(entry);
        else blockedItems.push(entry);
        if (row._parsedReviewBy && row._parsedReviewBy < todayUTC) {
          overdue.push(entry);
        }
      }
      for (const ref of extractReferences(row['Notes'])) {
        if (!knownIds.has(ref)) {
          brokenRefs.push({ source: `${d.id}/${row['Spec-AC']}`, ref });
        }
      }
    }
  }

  const sortByReviewBy = (a, b) => String(a.reviewBy).localeCompare(String(b.reviewBy));
  overdue.sort(sortByReviewBy);
  deferredItems.sort(sortByReviewBy);
  blockedItems.sort(sortByReviewBy);

  const byStatus = (st) => docs.filter(d => d.status === st);
  const progressFor = (d) => {
    if (!d.ac.hasGate || d.ac.rows.length === 0) return '—';
    const counts = {};
    for (const r of d.ac.rows) counts[r['Status']?.toLowerCase() ?? 'planned'] = (counts[r['Status']?.toLowerCase() ?? 'planned'] ?? 0) + 1;
    return Object.entries(counts).map(([k, v]) => `${v} ${k}`).join(', ');
  };

  const lines = [];
  lines.push(MARKER);
  lines.push('');
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push(`Source: docs/{issues,rfc,specs,requirements,releases}/**/*.md`);
  lines.push('');

  const section = (title, items, renderRow) => {
    lines.push(`## ${title} (${items.length})`);
    lines.push('');
    if (items.length === 0) { lines.push('_None._'); lines.push(''); return; }
    for (const row of renderRow(items)) lines.push(row);
    lines.push('');
  };

  section('Overdue reviews', overdue, items => {
    const out = ['| Doc | AC | Status | Was Due | Notes |', '|---|---|---|---|---|'];
    for (const e of items) out.push(`| ${e.doc} | ${e.ac} | ${e.status} | ${e.reviewBy} | ${e.notes} |`);
    return out;
  });

  section('Active (implementing)', byStatus('implementing').concat(byStatus('accepted'), byStatus('proposed'), byStatus('frozen')), items => {
    const out = ['| ID | Type | Status | Progress | Path |', '|---|---|---|---|---|'];
    for (const d of items) out.push(`| ${d.id} | ${d.type} | ${d.status} | ${progressFor(d)} | ${d.path} |`);
    return out;
  });

  section('Done', byStatus('done'), items => {
    const out = ['| ID | Type | Path |', '|---|---|---|'];
    for (const d of items) out.push(`| ${d.id} | ${d.type} | ${d.path} |`);
    return out;
  });

  section('Drafts', byStatus('draft'), items => {
    const out = ['| ID | Type | Path |', '|---|---|---|'];
    for (const d of items) out.push(`| ${d.id} | ${d.type} | ${d.path} |`);
    return out;
  });

  section('Deferred items (per-AC, across all specs)', deferredItems, items => {
    const out = ['| Source Doc | AC | Review-By | Notes |', '|---|---|---|---|'];
    for (const e of items) out.push(`| ${e.doc} | ${e.ac} | ${e.reviewBy} | ${e.notes} |`);
    return out;
  });

  section('Blocked items (per-AC, across all specs)', blockedItems, items => {
    const out = ['| Source Doc | AC | Review-By | Notes |', '|---|---|---|---|'];
    for (const e of items) out.push(`| ${e.doc} | ${e.ac} | ${e.reviewBy} | ${e.notes} |`);
    return out;
  });

  section('Broken references', brokenRefs, items => {
    const out = ['| Source | Reference | Status |', '|---|---|---|'];
    for (const b of items) out.push(`| ${b.source} | ${b.ref} | NOT FOUND |`);
    return out;
  });

  section('Rejected / Superseded', byStatus('rejected').concat(byStatus('superseded')), items => {
    const out = ['| ID | Type | Status | Path |', '|---|---|---|---|'];
    for (const d of items) out.push(`| ${d.id} | ${d.type} | ${d.status} | ${d.path} |`);
    return out;
  });

  section('Legacy (no frontmatter)', docs.filter(d => d.legacy), items => {
    const out = ['| Path |', '|---|'];
    for (const d of items) out.push(`| ${d.path} |`);
    return out;
  });

  // RFC-0002 audit sections — broader scan (all prefixed docs under docs/),
  // classification + drift verdicts. Report-only; tolerant to missing git.
  const audit = runAudit(ROOT, { today: todayUTC });
  const auditOrphans = [...audit.orphansNew, ...audit.orphansLegacy];
  section('Orphans (need triage)', auditOrphans, items => {
    const out = ['| Path | Age class | Problem |', '|---|---|---|'];
    for (const d of items) out.push(`| ${d.rel} | ${d.legacy ? 'legacy (soft)' : 'new (hard)'} | ${d.reasons.join('; ')} |`);
    return out;
  });
  section('Drift report', audit.drift, items => {
    const out = ['| Doc | Verdict | Evidence | Suggested next step |', '|---|---|---|---|'];
    for (const d of items) out.push(`| ${d.id} | ${d.verdict} | ${d.reasons.join('; ')} | ${suggestedStep(d)} |`);
    return out;
  });
  if (skipped.length > 0) {
    section('Skipped (schema violations)', skipped, items => items.map(f => `- ${f}`));
  }

  const today = ymd(todayUTC);
  lines.push(`---`);
  lines.push(`Today (UTC): ${today} — counts above use this date for overdue checks.`);
  lines.push('');

  const output = lines.join('\n');
  fs.mkdirSync(path.dirname(OUT_PATH), { recursive: true });
  fs.writeFileSync(OUT_PATH, output);

  // Companion violations report — keeps skipped-doc problems visible and
  // machine-readable even when the (degrade-and-report) index itself is clean.
  // Written only when there are violations; removed when the repo is clean so
  // its mere existence is a signal. Marker-guarded like the index.
  writeViolationsReport(skipped);

  console.log(`Wrote ${path.relative(ROOT, OUT_PATH)} (${docs.length} docs, ${overdue.length} overdue, ${deferredItems.length} deferred, ${brokenRefs.length} broken refs)`);
  if (skipped.length > 0) {
    console.log(`Wrote ${path.relative(ROOT, VIOLATIONS_PATH)} (${skipped.length} violation(s) skipped from index)`);
  }
  if (warnings.length > 0) {
    console.warn(`${warnings.length} warning(s):`);
    for (const w of warnings) console.warn(`  - ${w}`);
  }
}

main();
