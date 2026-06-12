#!/usr/bin/env node
// Docs hygiene & drift audit CLI (RFC-0002 / SPEC-0001).
//
// Usage:
//   node .aai/scripts/docs-audit.mjs                # full audit, markdown digest
//   node .aai/scripts/docs-audit.mjs --check        # CI gate: exit 1 on hard failures
//   node .aai/scripts/docs-audit.mjs --quick        # counts only, no git/EVENTS probes
//   node .aai/scripts/docs-audit.mjs --path <p>     # scope to a file or subtree
//   node .aai/scripts/docs-audit.mjs --no-event     # skip docs_audit EVENTS append
//   node .aai/scripts/docs-audit.mjs --strict       # enforce even without config
//                                                   # (intake post-save check)
//
// Modes: enforced (docs/ai/docs-audit.yaml present), report-only (absent), quick.
// In report-only mode --check always exits 0 — first runs never drown the operator.
// The audit REPORTS; the operator DECIDES. This script never edits any doc.

import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { runAudit, suggestedStep, CONFIG_PATH } from './lib/docs-audit-core.mjs';

const ROOT = process.cwd();

function parseArgs(argv) {
  const args = { check: false, quick: false, path: null, event: true, strict: false };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--check') args.check = true;
    else if (tok === '--quick') args.quick = true;
    else if (tok === '--no-event') args.event = false;
    else if (tok === '--strict') args.strict = true;
    else if (tok === '--path') args.path = argv[++i];
  }
  return args;
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
  const result = runAudit(ROOT, { quick: args.quick, scopePath: args.path, strict: args.strict });
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

  if (!args.quick) {
    lines.push(`### Orphans (need triage): ${counts.orphans}`);
    lines.push('');
    if (counts.orphans === 0) lines.push('_None._');
    else {
      lines.push(...table(['Path', 'First commit', 'Age class', 'Problem'],
        [...result.orphansNew, ...result.orphansLegacy].map(d =>
          [d.rel, d.firstCommit ?? 'untracked', d.legacy ? 'legacy (soft)' : 'new (hard)', d.reasons.join('; ')])));
    }
    lines.push('');
    lines.push(`### Drift report: ${result.drift.length}`);
    lines.push('');
    if (result.drift.length === 0) lines.push('_None._');
    else {
      lines.push(...table(['Doc', 'Verdict', 'Evidence', 'Suggested next step'],
        result.drift.map(d => [d.id, d.verdict, d.reasons.join('; '), suggestedStep(d)])));
    }
    lines.push('');
    if (result.violations.length) {
      lines.push(`### Schema violations: ${result.violations.length}`);
      lines.push('');
      for (const v of result.violations) lines.push(`- ${v.rel}: ${v.msg}`);
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
