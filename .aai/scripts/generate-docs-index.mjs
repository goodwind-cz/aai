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
  DOC_STATUS_ENUM, walk,
  parseFrontmatter, parseAcTable, parseReviewBy, extractReferences, toPosix,
  normalizeAcStatus,
} from './lib/docs-model.mjs';
import { runAudit, suggestedStep, loadConfig, firstCommitDate } from './lib/docs-audit-core.mjs';

const ROOT = process.cwd();
const ARGV = process.argv.slice(2);
// --strict / lint-docs: fatal-abort on any non-legacy schema violation (CI / pre-commit gate).
// Default (no flag): degrade-and-report — always write a best-effort index.
// --continue-on-error: retained as a no-op alias (degrade-and-report is now the default).
const strict = ARGV.includes('--strict') || ARGV.includes('lint-docs');
// RFC-0003 / SPEC-0002: index the canonical layer alongside the intake dirs.
// docs/_archive is deliberately NOT scanned here — archived originals are
// preserved-not-active and must not surface in the Active/Drafts sections.
const SCAN_DIRS = ['docs/issues', 'docs/rfc', 'docs/specs', 'docs/requirements', 'docs/releases', 'docs/canonical'];
const OUT_PATH = path.join(ROOT, 'docs/INDEX.md');
const VIOLATIONS_PATH = path.join(ROOT, 'docs/INDEX.violations.md');
// SPEC-0010 Group A (ISSUE-0003) — the git-history-dependent audit sections
// (Orphans + Drift report) are relocated here, OUT of the committed docs/INDEX.md,
// into a git-ignored, marker-guarded companion (see .gitignore; never staged by
// the AAI:INDEX-AUTOGEN pre-commit hook), so the committed index is a pure
// function of on-disk docs (idempotent).
const AUDIT_PATH = path.join(ROOT, 'docs/INDEX.audit.md');
const MARKER = '# Docs Index — auto-generated, DO NOT EDIT';
const VIOLATIONS_MARKER = '# Docs Index Violations — auto-generated, DO NOT EDIT';
const AUDIT_MARKER = '# Docs Index Audit — auto-generated, DO NOT EDIT';

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
function writeViolationsReport(skipped, acStatusViolations = []) {
  if (fs.existsSync(VIOLATIONS_PATH)) {
    const firstLine = fs.readFileSync(VIOLATIONS_PATH, 'utf8').split('\n').find(l => l.trim().length > 0) ?? '';
    if (firstLine.trim() !== VIOLATIONS_MARKER) {
      console.warn(`WARNING: ${path.relative(ROOT, VIOLATIONS_PATH)} exists without the auto-generated marker — leaving it untouched.`);
      return;
    }
  }
  if (skipped.length === 0 && acStatusViolations.length === 0) {
    if (fs.existsSync(VIOLATIONS_PATH)) fs.rmSync(VIOLATIONS_PATH);
    return;
  }
  const out = [
    VIOLATIONS_MARKER,
    '',
    `Generated: ${new Date().toISOString()}`,
    '',
  ];
  if (skipped.length > 0) {
    out.push(
      'These docs were SKIPPED (whole-doc) from docs/INDEX.md because their frontmatter',
      'or Acceptance-Criteria table violates the schema. The index is still produced',
      '(degrade-and-report); fix the docs below and re-run the generator. Run',
      '`node .aai/scripts/generate-docs-index.mjs --strict` to fail CI on these.',
      '',
      '## Skipped (whole-doc schema violations)',
      '',
      ...skipped.map(f => `- ${f}`),
      '',
    );
  }
  // SPEC-0010 Group C (ISSUE-0005) — row-level AC-status violations. The doc is
  // still INDEXED normally (not whole-doc-skipped); only the offending row is
  // flagged here. --strict promotes these to a fatal error (handled in main()).
  if (acStatusViolations.length > 0) {
    out.push(
      '## AC status violations (row-level)',
      '',
      'These rows carry a non-canonical AC status. The doc stays in the index; the',
      'row below is flagged. Fix the status (or use `<canonical> (<qualifier>)`).',
      '',
      ...acStatusViolations.map(v => `- ${v.rel}: unknown AC status "${v.raw}" for ${v.specAc}`),
      '',
    );
  }
  fs.mkdirSync(path.dirname(VIOLATIONS_PATH), { recursive: true });
  fs.writeFileSync(VIOLATIONS_PATH, out.join('\n'));
}

// SPEC-0010 Group A (ISSUE-0003) — write the git-ignored companion carrying the
// relocated (git-history-dependent) Orphans + Drift sections. Marker-guarded like
// the violations report. Because it is git-ignored and never staged by the hook,
// it does not affect the committed index's idempotence.
function writeAuditCompanion(body) {
  if (fs.existsSync(AUDIT_PATH)) {
    const firstLine = fs.readFileSync(AUDIT_PATH, 'utf8').split('\n').find(l => l.trim().length > 0) ?? '';
    if (firstLine.trim() !== AUDIT_MARKER) {
      console.warn(`WARNING: ${path.relative(ROOT, AUDIT_PATH)} exists without the auto-generated marker — leaving it untouched.`);
      return;
    }
  }
  fs.mkdirSync(path.dirname(AUDIT_PATH), { recursive: true });
  fs.writeFileSync(AUDIT_PATH, body);
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
  // SPEC-0010 Group C (ISSUE-0005) — row-level AC-status violations kept SEPARATE
  // from whole-doc `failures`: they never splice the doc out of the index (the doc
  // stays placed), they are surfaced in INDEX.violations.md, and under --strict
  // they remain fatal.
  const acStatusViolations = [];

  for (const dir of SCAN_DIRS) {
    for (const filePath of walk(path.join(ROOT, dir))) {
      // SPEC-0007 — emit POSIX paths wherever a path enters a record/row, so the
      // committed docs/INDEX.md is OS-independent. No-op on POSIX (path.sep === '/').
      // toPosix() splits on both separator types so it is unit-testable on any OS.
      const rel = toPosix(path.relative(ROOT, filePath));
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
        // SPEC-0010 Group C — normalize via the shared helper. A qualified
        // `<canonical> (<qualifier>)` normalizes to its base status (not a
        // violation, qualifier preserved on the row). A genuinely-invalid status
        // is a ROW-LEVEL violation (doc stays indexed) — NOT a whole-doc failure.
        const rawStatus = row['Status'] ?? '';
        const norm = normalizeAcStatus(rawStatus);
        row._baseStatus = norm.status;       // drives placement/progress/deferred-blocked reads
        row._acQualifier = norm.qualifier;   // preserved, never silently dropped
        if (rawStatus.trim() && !norm.canonical) {
          acStatusViolations.push({ rel, specAc: row['Spec-AC'], raw: rawStatus });
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
  // SPEC-0010 (ISSUE-0003) WARNING-1: the legacy-window auto-skip label uses
  // firstCommitDate (git history), which is NOT a pure function of on-disk docs
  // (null pre-commit, a date post-commit). The committed index lists violations
  // PLAINLY (git-invariant); the git-dependent "[legacy — auto-skipped]"
  // annotation is relocated to the git-ignored companion docs/INDEX.audit.md.
  // firstCommitDate is used ONLY for the --strict abort decision (an exit code,
  // not committed content).
  let legacySkipped = [];
  if (failures.length > 0) {
    const legacyUntil = loadConfig(ROOT)?.legacy_until_date ?? null;
    const hard = [];
    for (const f of failures) {
      const rel = f.slice(0, f.indexOf(': '));
      const first = legacyUntil ? firstCommitDate(ROOT, rel) : null;
      if (first && first < legacyUntil) legacySkipped.push(f);
      else hard.push(f);
      skipped.push(f);   // committed index: plain, git-invariant
    }
    if (hard.length > 0 && strict) {
      console.error('FAIL (strict): schema violations:');
      for (const f of hard) console.error(`  - ${f}`);
      console.error('Fix the docs above, or run without --strict for a best-effort index.');
      process.exit(1);
    }
    // Non-strict default: never abort — every violation is already in `skipped`.
    if (hard.length > 0) {
      console.warn(`WARNING: ${hard.length} schema violation(s) — skipped from index (run with --strict to fail):`);
      for (const f of hard) console.warn(`  - ${f}`);
    }
    const failedRels = new Set(failures.map(f => f.slice(0, f.indexOf(': '))));
    for (let i = docs.length - 1; i >= 0; i -= 1) {
      if (failedRels.has(docs[i].path)) docs.splice(i, 1);
    }
  }

  // SPEC-0010 Group C (ISSUE-0005) — row-level AC-status violations. Under
  // --strict / lint-docs they remain FATAL (detection is not weakened); by
  // default they are surfaced (INDEX.violations.md) while the doc stays indexed.
  if (acStatusViolations.length > 0) {
    if (strict) {
      console.error('FAIL (strict): row-level AC status violation(s):');
      for (const v of acStatusViolations) console.error(`  - ${v.rel}: unknown AC status "${v.raw}" for ${v.specAc}`);
      console.error('Use a canonical status or `<canonical> (<qualifier>)`; run without --strict for a best-effort index.');
      process.exit(1);
    }
    console.warn(`WARNING: ${acStatusViolations.length} row-level AC status violation(s) — doc(s) kept in index, rows flagged in INDEX.violations.md (run with --strict to fail):`);
    for (const v of acStatusViolations) console.warn(`  - ${v.rel}: unknown AC status "${v.raw}" for ${v.specAc}`);
  }

  // SPEC-0007 Spec-AC-06 — report-only legacy-ratio tripwire. SPEC-0006's
  // zero-section coverage invariant treats Legacy as a valid/exempt placement, so
  // it structurally cannot detect a parser failure (e.g. a CRLF checkout) that
  // collapses the whole corpus into Legacy. This guard closes that gap: a LOUD
  // stderr WARNING when the Legacy bucket exceeds 50% of scanned docs AND the
  // legacy count is greater than 1 (the >1 floor keeps a tiny corpus quiet). It
  // is report-only — it changes NO exit code (a --strict fatal is deferred until
  // the threshold is field-validated).
  const legacyCount = docs.filter(d => d.legacy).length;
  if (legacyCount > 1 && legacyCount / docs.length > 0.5) {
    console.warn(`WARNING: legacy-ratio guard — ${legacyCount} of ${docs.length} scanned docs are Legacy (no frontmatter), over 50%. This often indicates a parser failure (e.g. CRLF/lone-CR line endings) collapsing the corpus into Legacy. Investigate before trusting docs/INDEX.md. (report-only; exit code unchanged)`);
  }

  const knownIds = new Set(docs.map(d => d.id));
  const overdue = [];
  const deferredItems = [];
  const blockedItems = [];
  const brokenRefs = [];

  for (const d of docs) {
    for (const row of d.ac.rows) {
      // SPEC-0010 Group C — read the normalized BASE status so a qualified
      // `deferred (external)` / `blocked (upstream)` still lands in the right bucket.
      const s = row._baseStatus ?? (row['Status'] ?? '').toLowerCase();
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

  const isCanonical = (d) => String(d.fm?.type ?? d.type ?? '').toLowerCase() === 'canonical';
  const canonicalDocs = docs.filter(isCanonical);
  // canonical docs get a dedicated grouping; keep them out of the generic
  // status sections so they are not double-listed.
  const byStatus = (st) => docs.filter(d => d.status === st && !isCanonical(d));
  const progressFor = (d) => {
    if (!d.ac.hasGate || d.ac.rows.length === 0) return '—';
    const counts = {};
    // SPEC-0010 Group C — count by the normalized base status.
    for (const r of d.ac.rows) {
      const k = r._baseStatus || (r['Status']?.toLowerCase() ?? 'planned') || 'planned';
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return Object.entries(counts).map(([k, v]) => `${v} ${k}`).join(', ');
  };

  // SPEC-0006 — doc-level PLACEMENT sections. These are the only sections that
  // "place" a whole doc (as opposed to per-AC / cross-cutting sections like
  // Overdue, per-AC Deferred/Blocked, Broken references, or the audit sections).
  // Computed once and reused both to render and to drive the coverage invariant,
  // so the invariant is data-driven over actual section membership — any future
  // DOC_STATUS_ENUM value added without a section is caught automatically.
  const activeMembers = byStatus('implementing').concat(byStatus('accepted'), byStatus('proposed'), byStatus('frozen'));
  const doneMembers = byStatus('done');
  const draftMembers = byStatus('draft');
  const deferredMembers = byStatus('deferred');           // Spec-AC-01 whole-doc deferred
  const rejectedMembers = byStatus('rejected').concat(byStatus('superseded'));
  const placementMembers = [canonicalDocs, activeMembers, doneMembers, draftMembers, deferredMembers, rejectedMembers];

  // Spec-AC-02/03 — zero-section coverage invariant. A non-legacy doc that lands
  // in NO placement section silently vanished before; surface it. Under --strict
  // / lint-docs this is fatal (CI / pre-commit gate); otherwise degrade-and-report
  // (best-effort index still written, gap surfaced). Legacy (no-frontmatter) docs
  // are exempt — they land in the Legacy section.
  const placedDocs = new Set();
  for (const arr of placementMembers) for (const d of arr) placedDocs.add(d);
  // NOTE: d.legacy (boolean) is true only for no-frontmatter docs (exempt from
  // the invariant). d.status === 'legacy' is set for those same docs AND for any
  // doc with frontmatter `status: legacy` — the two are distinct; a doc with
  // `status: legacy` in its frontmatter has d.legacy = false and IS subject to
  // the coverage invariant (intentional: no byStatus('legacy') placement section).
  const coverageGaps = docs.filter(d => !d.legacy && !placedDocs.has(d));
  if (coverageGaps.length > 0) {
    if (strict) {
      console.error('FAIL (strict): coverage invariant — doc(s) land in zero placement sections:');
      for (const d of coverageGaps) console.error(`  - ${d.id} (${d.path}, status: ${d.status})`);
      console.error('Add a doc-level section for that status, or fix the doc frontmatter; run without --strict for a best-effort index.');
      process.exit(1);
    }
    console.warn(`WARNING: ${coverageGaps.length} doc(s) land in zero placement sections — surfaced as Coverage gaps (run with --strict to fail):`);
    for (const d of coverageGaps) console.warn(`  - ${d.id} (${d.path}, status: ${d.status})`);
  }

  const lines = [];
  lines.push(MARKER);
  lines.push('');
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push(`Source: docs/{issues,rfc,specs,requirements,releases,canonical}/**/*.md`);
  lines.push('');

  const renderSection = (target, title, items, renderRow) => {
    target.push(`## ${title} (${items.length})`);
    target.push('');
    if (items.length === 0) { target.push('_None._'); target.push(''); return; }
    for (const row of renderRow(items)) target.push(row);
    target.push('');
  };
  const section = (title, items, renderRow) => renderSection(lines, title, items, renderRow);

  section('Overdue reviews', overdue, items => {
    const out = ['| Doc | AC | Status | Was Due | Notes |', '|---|---|---|---|---|'];
    for (const e of items) out.push(`| ${e.doc} | ${e.ac} | ${e.status} | ${e.reviewBy} | ${e.notes} |`);
    return out;
  });

  section('Active (implementing)', activeMembers, items => {
    const out = ['| ID | Type | Status | Progress | Path |', '|---|---|---|---|---|'];
    for (const d of items) out.push(`| ${d.id} | ${d.type} | ${d.status} | ${progressFor(d)} | ${d.path} |`);
    return out;
  });

  // RFC-0003 / SPEC-0002 — canonical layer. Surfaces each canonical doc with
  // its domain and a count of contributing sources. Archived originals under
  // docs/_archive/ are preserved-not-active and intentionally not listed.
  section('Canonical layer', canonicalDocs, items => {
    const out = ['| ID | Domain | Sources | Path |', '|---|---|---|---|'];
    for (const d of items) {
      const domain = d.fm?.domain ?? '—';
      const srcCount = Array.isArray(d.fm?.sources) ? d.fm.sources.length
        : (d.fm?.sources ? 1 : 0);
      out.push(`| ${d.id} | ${domain} | ${srcCount} | ${d.path} |`);
    }
    return out;
  });

  section('Done', doneMembers, items => {
    const out = ['| ID | Type | Path |', '|---|---|---|'];
    for (const d of items) out.push(`| ${d.id} | ${d.type} | ${d.path} |`);
    return out;
  });

  section('Drafts', draftMembers, items => {
    const out = ['| ID | Type | Path |', '|---|---|---|'];
    for (const d of items) out.push(`| ${d.id} | ${d.type} | ${d.path} |`);
    return out;
  });

  // SPEC-0006 Spec-AC-01 — doc-level whole-doc `deferred` section. Distinct from
  // the per-AC "Deferred items" section below (which lists deferred AC *rows*).
  section('Deferred (whole-doc)', deferredMembers, items => {
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

  section('Rejected / Superseded', rejectedMembers, items => {
    const out = ['| ID | Type | Status | Path |', '|---|---|---|---|'];
    for (const d of items) out.push(`| ${d.id} | ${d.type} | ${d.status} | ${d.path} |`);
    return out;
  });

  section('Legacy (no frontmatter)', docs.filter(d => d.legacy), items => {
    const out = ['| Path |', '|---|'];
    for (const d of items) out.push(`| ${d.path} |`);
    return out;
  });

  // RFC-0002 audit data — broader scan (all prefixed docs under docs/),
  // classification + drift verdicts. Report-only; tolerant to missing git.
  // SPEC-0010 Group A (ISSUE-0003): these Orphans + Drift sections are
  // git-history-dependent (runAudit probes git), so they are NO LONGER embedded
  // in the committed docs/INDEX.md. They are written to the git-ignored companion
  // docs/INDEX.audit.md below; docs-audit.mjs remains the on-demand authority.
  const audit = runAudit(ROOT, { today: todayUTC });
  const auditOrphans = [...audit.orphansNew, ...audit.orphansLegacy];
  const auditLines = [
    AUDIT_MARKER,
    '',
    `Generated: ${new Date().toISOString()}`,
    '',
    'Git-ignored companion to docs/INDEX.md carrying the git-history-dependent',
    'Orphans + Drift sections relocated out of the committed index (SPEC-0010 /',
    'ISSUE-0003). NOT staged by the AAI:INDEX-AUTOGEN pre-commit hook. The same',
    'drift/orphan analysis is reported on demand by',
    '`node .aai/scripts/docs-audit.mjs`.',
    '',
  ];
  renderSection(auditLines, 'Orphans (need triage)', auditOrphans, items => {
    const out = ['| Path | Age class | Problem |', '|---|---|---|'];
    for (const d of items) out.push(`| ${d.rel} | ${d.legacy ? 'legacy (soft)' : 'new (hard)'} | ${d.reasons.join('; ')} |`);
    return out;
  });
  renderSection(auditLines, 'Drift report', audit.drift, items => {
    const out = ['| Doc | Verdict | Evidence | Suggested next step |', '|---|---|---|---|'];
    for (const d of items) out.push(`| ${d.id} | ${d.verdict} | ${d.reasons.join('; ')} | ${suggestedStep(d)} |`);
    return out;
  });
  // SPEC-0010 (ISSUE-0003) WARNING-1: which skipped docs were auto-demoted by the
  // legacy_until_date migration window is git-history-dependent (firstCommitDate),
  // so it lives in the companion, not the committed index.
  renderSection(auditLines, 'Legacy auto-skipped (migration window)', legacySkipped,
    items => items.map(f => `- ${f} [legacy — auto-skipped]`));
  if (skipped.length > 0) {
    section('Skipped (schema violations)', skipped, items => items.map(f => `- ${f}`));
  }
  // SPEC-0006 Spec-AC-03 — degrade-and-report surface for the coverage invariant:
  // non-legacy docs that land in zero placement sections (best-effort run only;
  // --strict aborted earlier). Rendered only when non-empty so a clean repo's
  // index is unchanged.
  if (coverageGaps.length > 0) {
    section('Coverage gaps (zero placement sections)', coverageGaps, items => {
      const out = ['| ID | Type | Status | Path |', '|---|---|---|---|'];
      for (const d of items) out.push(`| ${d.id} | ${d.type} | ${d.status} | ${d.path} |`);
      return out;
    });
  }

  const today = ymd(todayUTC);
  lines.push(`---`);
  lines.push(`Today (UTC): ${today} — counts above use this date for overdue checks.`);
  lines.push('');

  const output = lines.join('\n');
  fs.mkdirSync(path.dirname(OUT_PATH), { recursive: true });
  fs.writeFileSync(OUT_PATH, output);

  // Companion violations report — keeps skipped-doc problems and row-level
  // AC-status violations visible and machine-readable even when the
  // (degrade-and-report) index itself is clean. Written only when there are
  // violations; removed when the repo is clean so its mere existence is a signal.
  // Marker-guarded like the index.
  writeViolationsReport(skipped, acStatusViolations);

  // SPEC-0010 Group A — git-ignored companion carrying the relocated Orphans +
  // Drift sections (git-history-dependent; never in the committed index).
  writeAuditCompanion(auditLines.join('\n'));

  console.log(`Wrote ${path.relative(ROOT, OUT_PATH)} (${docs.length} docs, ${overdue.length} overdue, ${deferredItems.length} deferred, ${brokenRefs.length} broken refs)`);
  if (skipped.length > 0 || acStatusViolations.length > 0) {
    console.log(`Wrote ${path.relative(ROOT, VIOLATIONS_PATH)} (${skipped.length} whole-doc skipped, ${acStatusViolations.length} row-level AC-status violation(s))`);
  }
  if (warnings.length > 0) {
    console.warn(`${warnings.length} warning(s):`);
    for (const w of warnings) console.warn(`  - ${w}`);
  }
}

main();
