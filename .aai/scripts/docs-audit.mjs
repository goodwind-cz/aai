#!/usr/bin/env node
// Docs hygiene & drift audit CLI (RFC-0002 / SPEC-0001).
//
// Usage:
//   node .aai/scripts/docs-audit.mjs                # full audit, markdown digest
//   node .aai/scripts/docs-audit.mjs --check        # CI gate: exit 1 on hard failures
//   node .aai/scripts/docs-audit.mjs --quick        # counts only, no git/EVENTS probes
//   node .aai/scripts/docs-audit.mjs --list         # per-doc classification table
//   node .aai/scripts/docs-audit.mjs --path <p>     # scope to a file or subtree
//   node .aai/scripts/docs-audit.mjs --no-event     # skip docs_audit EVENTS append
//   node .aai/scripts/docs-audit.mjs --strict       # enforce even without config
//                                                   # (intake post-save check)
//   node .aai/scripts/docs-audit.mjs --strict-types # unknown frontmatter type
//                                                   # becomes a hard failure
//
// Modes: enforced (docs/ai/docs-audit.yaml present), report-only (absent), quick.
// In report-only mode --check always exits 0 — first runs never drown the operator.
// The audit REPORTS; the operator DECIDES. This script never edits any doc.

import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { runAudit, suggestedStep, gateDoc, gateFile, CONFIG_PATH } from './lib/docs-audit-core.mjs';

const ROOT = process.cwd();

function parseArgs(argv) {
  const args = { check: false, quick: false, path: null, event: true, strict: false };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--check') args.check = true;
    else if (tok === '--quick') args.quick = true;
    else if (tok === '--no-event') args.event = false;
    else if (tok === '--strict') args.strict = true;
    else if (tok === '--strict-types') args.strictTypes = true;
    else if (tok === '--list') args.list = true;
    else if (tok === '--path') args.path = argv[++i];
    else if (tok === '--gate') args.gate = argv[++i];
    else if (tok === '--gate-file') args.gateFile = argv[++i];
  }
  return args;
}

// SPEC-0011 G1 — `--gate <DOC-ID>` offline close-time predicate. Prints the
// reasons and exits 1 on fail, 0 on pass, 2 when the id resolves to no scanned
// doc. Scope-limited to the one doc; never emits a docs_audit event.
function runGate(docId) {
  emitGate(`## Close Gate — ${docId}`, gateDoc(ROOT, docId));
}

// SPEC-0011 G5 — `--gate-file <file>` gates the content of an explicit file path
// (e.g. a materialized STAGED blob) rather than resolving the doc by id from the
// worktree. Same exit contract as `--gate` (1 fail / 0 pass / 2 unreadable).
function runGateFile(filePath) {
  emitGate(`## Close Gate — ${filePath}`, gateFile(ROOT, filePath));
}

function emitGate(header, res) {
  console.log(header);
  console.log('');
  if (!res.found) {
    console.log(`GATE ERROR: ${res.reasons.join('; ')}`);
    process.exit(2);
  }
  if (res.ok) {
    console.log('GATE PASS: AC Status table complete (every row terminal, every done row evidenced, every Review-By valid).');
    process.exit(0);
  }
  console.log('GATE FAIL — the AC Status table is not reconciled:');
  for (const r of res.reasons) console.log(`- ${r}`);
  process.exit(1);
}

function table(header, rows) {
  const out = [`| ${header.join(' | ')} |`, `|${header.map(() => '---').join('|')}|`];
  for (const r of rows) out.push(`| ${r.join(' | ')} |`);
  return out;
}

function emitEvent(result, scope) {
  try {
    const helper = path.join(path.dirname(fileURLToPath(import.meta.url)), 'append-event.mjs');
    execFileSync('node', [
      helper, '--event', 'docs_audit', '--ref', `docs-audit/${scope}`,
      '--total', String(result.counts.total),
      '--orphans', String(result.counts.orphans),
      '--drifted', String(result.counts.drifted),
      '--stale', String(result.counts.stale),
      '--mode', result.mode,
    ], { stdio: 'ignore' });
  } catch {
    console.warn('warn: docs_audit event append failed (best-effort, continuing)');
  }
}

function main() {
  const args = parseArgs(process.argv);
  if (args.gate) runGate(args.gate);   // exits 1/0/2; never returns
  if (args.gateFile) runGateFile(args.gateFile);   // exits 1/0/2; never returns
  const result = runAudit(ROOT, {
    quick: args.quick, scopePath: args.path, strict: args.strict,
    strictTypes: Boolean(args.strictTypes),
  });
  const { counts, mode } = result;
  const scope = args.path ?? 'full';
  const lines = [];

  lines.push(`## Docs Audit — ${new Date().toISOString().slice(0, 10)}`);
  lines.push('');
  lines.push(`- Mode: ${mode}${args.path ? ` | Scope: ${args.path}` : ''}`);
  lines.push(`- Scanned: ${counts.total} docs | Orphans: ${counts.orphans} (${counts.orphans - counts.orphansNew} legacy soft) | Drifted: ${counts.drifted} | Stale: ${counts.stale} | Obsolete: ${counts.obsolete}`);
  lines.push(`- Tracked: ${counts.trackedOpen} open, ${counts.trackedDone} done, ${counts.superseded} superseded/rejected`);
  lines.push('');

  if (mode === 'report-only') {
    lines.push(`Note: ${CONFIG_PATH} not found — running report-only (nothing hard-fails).`);
    lines.push(`Enable enforcement by creating it with a legacy_until_date (see RFC-0002).`);
    lines.push('');
  }

  if (args.list) {
    const CLASS_ORDER = ['orphan', 'drifted', 'obsolete', 'tracked-open', 'tracked-done', 'superseded'];
    const sorted = [...result.docs].sort((a, b) =>
      (CLASS_ORDER.indexOf(a.cls) - CLASS_ORDER.indexOf(b.cls)) || a.rel.localeCompare(b.rel));
    lines.push(`### Classification: ${result.docs.length} docs`);
    lines.push('');
    lines.push(...table(['Doc', 'Class', 'Status', 'Verdict', 'Scope', 'Path'],
      sorted.map(d => [
        d.id, d.cls, d.effectiveStatus ?? d.status ?? '—',
        d.verdict ?? '—', d.scope ?? '—', d.rel,
      ])));
    lines.push('');
  }

  if (!args.quick) {
    lines.push(`### Orphans (need triage): ${counts.orphans}`);
    lines.push('');
    if (counts.orphans === 0) lines.push('_None._');
    else {
      lines.push(...table(['Path', 'Suggested ID', 'First commit', 'Age class', 'Problem'],
        [...result.orphansNew, ...result.orphansLegacy].map(d => {
          const suggested = d.relatedIds?.length
            ? `${d.fileId} (primary) + ${d.relatedIds.join(' + ')}`
            : (d.fileId ?? '—');
          return [d.rel, suggested, d.firstCommit ?? 'untracked', d.legacy ? 'legacy (soft)' : 'new (hard)', d.reasons.join('; ')];
        })));
    }
    if (result.planLenient.length) {
      lines.push('');
      lines.push(`Note: ${result.planLenient.length} operator plan file(s) inventoried leniently (plan_scan_mode: lenient) — no frontmatter required.`);
    }
    lines.push('');
    lines.push(`### Drift report: ${result.drift.length}`);
    lines.push('');
    if (result.drift.length === 0) lines.push('_None._');
    else {
      lines.push(...table(['Doc', 'Verdict', 'Evidence', 'Suggested next step'],
        result.drift.map(d => [d.id, d.verdict, d.reasons.join('; '), suggestedStep(d)])));
      lines.push('');
      lines.push('Triage commands:');
      for (const d of result.drift) {
        lines.push(`- ${d.id}: \`git log --grep="${d.id}" --oneline\` | \`head -50 ${d.rel}\``);
      }
    }
    lines.push('');
    if (result.violations.length) {
      lines.push(`### Schema violations: ${result.violations.length}`);
      lines.push('');
      for (const v of result.violations) lines.push(`- ${v.rel}: ${v.msg}`);
      lines.push('');
    }
    if (result.typeWarnings.length) {
      lines.push(`### Type warnings: ${result.typeWarnings.length}`);
      lines.push('');
      for (const w of result.typeWarnings) lines.push(`- ${w.id} (${w.rel}): ${w.msg}`);
      lines.push('');
    }
    if (result.annotations.length) {
      lines.push(`### Annotations`);
      lines.push('');
      for (const a of result.annotations) lines.push(`- ${a.id}: ${a.key} = ${a.value}`);
      lines.push('');
    }
    // Closeout candidates (SPEC-0003 / CHANGE-0004): report-only — never feeds
    // the exit-code path; surfaces non-terminal parents whose specs are all done.
    lines.push(`### Closeout candidates: ${result.closeoutCandidates.length}`);
    lines.push('');
    if (result.closeoutCandidates.length === 0) lines.push('_None._');
    else {
      lines.push(...table(['Parent', 'Type', 'Status', 'Satisfying spec(s)', 'Suggested next step'],
        result.closeoutCandidates.map(c => [
          c.id, c.type, c.status, c.specs.join(' + '), c.suggestedStep,
        ])));
    }
    lines.push('');
    // Open decisions on done docs (SPEC-0006 / Spec-AC-06): report-only — never
    // feeds the exit-code path; surfaces done docs whose body buries an
    // unresolved decision as a free-text WARNING.
    lines.push(`### Open decisions on done docs: ${result.openDecisionDoneDocs.length}`);
    lines.push('');
    if (result.openDecisionDoneDocs.length === 0) lines.push('_None._');
    else {
      lines.push(...table(['Doc', 'Marker', 'Line', 'Path'],
        result.openDecisionDoneDocs.map(d => [d.id, d.marker, String(d.line), d.rel])));
      lines.push('');
      lines.push('Report-only: resolve each decision before close, or promote it to a tracked item (a per-AC blocked/deferred row with Review-By, or a follow-up tracked doc).');
    }
    lines.push('');
    // SPEC-0011 G4 — near-miss AC tables (report-only; never feeds the exit-code
    // path). A table that LOOKS like an AC Status table but is not the canonical
    // shape, so the drift verdict may be inaccurate.
    lines.push(`### Near-miss AC tables: ${result.nearMissWarnings.length}`);
    lines.push('');
    if (result.nearMissWarnings.length === 0) lines.push('_None._');
    else {
      const rows = [];
      for (const d of result.nearMissWarnings) {
        for (const w of d.warnings) rows.push([d.id, w.kind, w.detail, d.rel]);
      }
      lines.push(...table(['Doc', 'Kind', 'Detail', 'Path'], rows));
    }
    lines.push('');
    // SPEC-0011 G3 — Review-By claims not backed by an event/artifact (report-only).
    lines.push(`### Review-By claims (unbacked): ${result.reviewClaimUnbacked.length}`);
    lines.push('');
    if (result.reviewClaimUnbacked.length === 0) lines.push('_None._');
    else {
      lines.push(...table(['Doc', 'Spec-AC', 'Review-By', 'Verdict', 'Path'],
        result.reviewClaimUnbacked.map(r => [r.id, r.specAc, r.reviewBy, r.verdict, r.rel])));
      lines.push('');
      lines.push('Report-only: a `Review-By: code-review` claim with no corroborating code_review_completed / work_item_closed(code_review: pass*) event and no docs/ai/{reviews,reports}/*<ID>* artifact.');
    }
    lines.push('');
    // SPEC-0011 G2 — telemetry-at-close: done docs missing a work_item_closed
    // event (report-only).
    lines.push(`### Missing close telemetry: ${result.missingCloseTelemetry.length}`);
    lines.push('');
    if (result.missingCloseTelemetry.length === 0) lines.push('_None._');
    else {
      lines.push(...table(['Doc', 'Verdict', 'Path'],
        result.missingCloseTelemetry.map(d => [d.id, 'missing-close-telemetry', d.rel])));
      lines.push('');
      lines.push('Report-only: emit `append-event.mjs --event work_item_closed --ref <ID> --validation <v> --code-review <cr>` on close.');
    }
    lines.push('');
    if (result.pendingCommit.length) {
      lines.push(`### Pending commit (verdicts reflect the working tree)`);
      lines.push('');
      for (const p of result.pendingCommit) lines.push(`- ${p}`);
      lines.push('');
    }
  }

  const needsTriage = counts.orphans + counts.drifted + counts.obsolete + counts.violations;
  lines.push(`### Verdict: ${needsTriage === 0 ? 'CLEAN' : `NEEDS-TRIAGE (${needsTriage} items)`}`);
  if (result.hardFail) {
    lines.push('');
    lines.push(`CHECK FAILED: ${counts.orphansNew} new orphan(s), ${counts.violations} schema violation(s).`);
  }

  console.log(lines.join('\n'));

  if (!args.quick && args.event) emitEvent(result, scope);

  if (args.check && result.hardFail) process.exit(1);
}

main();
