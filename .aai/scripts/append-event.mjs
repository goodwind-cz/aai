#!/usr/bin/env node
// Append a single audit event to docs/ai/EVENTS.jsonl (RFC-0001 layer 5).
//
// Event types (closed set): ac_status, ac_evidence, defer_extended, doc_lifecycle,
//   docs_audit, work_item_closed, code_review_completed (SPEC-0011 G2).
// Required: --event, --ref. Auto-filled: v=1, ts (ISO UTC), actor (git slug).
//
// Examples:
//   append-event.mjs --event ac_status --ref SPEC-0042/Spec-AC-07 \
//     --from implementing --to deferred --review-by 2026-08-01 --notes "→ RFC-0051"
//   append-event.mjs --event ac_evidence --ref SPEC-0042/Spec-AC-01 --commit a1b2c3d
//   append-event.mjs --event defer_extended --ref SPEC-0042/Spec-AC-07 \
//     --old-review-by 2026-08-01 --new-review-by 2026-Q4 --notes "..."
//   append-event.mjs --event doc_lifecycle --ref RFC-0042 --from draft --to implementing
//
// Multi-file parent IDs: use --ref PARENT-ID/<filename-suffix> for a
// file-specific transition, bare --ref PARENT-ID for a parent-level one.
// Sub-refs roll up to the parent in the docs audit (CHANGE-0002 D11).

import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const EVENTS_PATH = path.join(process.cwd(), 'docs/ai/EVENTS.jsonl');
const SCHEMA_VERSION = 1;
const EVENT_TYPES = new Set(['ac_status', 'ac_evidence', 'defer_extended', 'doc_lifecycle', 'docs_audit', 'work_item_closed', 'code_review_completed']);

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (!tok.startsWith('--')) continue;
    const key = tok.slice(2).replace(/-/g, '_');
    const val = (i + 1 < argv.length && !argv[i + 1].startsWith('--')) ? argv[++i] : true;
    args[key] = val;
  }
  return args;
}

function actorSlug() {
  try {
    const email = execSync('git config user.email', { encoding: 'utf8' }).trim();
    return email.toLowerCase().replace(/[^a-z0-9._-]+/g, '_') || 'unknown';
  } catch {
    return 'unknown';
  }
}

function fail(msg, exitCode = 2) {
  console.error(`append-event: ${msg}`);
  process.exit(exitCode);
}

function main() {
  const args = parseArgs(process.argv);
  if (!args.event) fail('missing --event');
  if (!EVENT_TYPES.has(args.event)) fail(`unknown event type "${args.event}" (allowed: ${[...EVENT_TYPES].join(', ')})`);
  if (!args.ref) fail('missing --ref');

  const entry = {
    v: SCHEMA_VERSION,
    ts: new Date().toISOString(),
    actor: actorSlug(),
    event: args.event,
    ref: args.ref,
  };

  switch (args.event) {
    case 'ac_status':
      if (!args.from || !args.to) fail('ac_status requires --from and --to');
      entry.payload = { from: args.from, to: args.to };
      if (args.review_by) entry.payload.review_by = args.review_by;
      if (args.notes) entry.payload.notes = args.notes;
      break;
    case 'ac_evidence':
      if (!args.commit && !args.evidence) fail('ac_evidence requires --commit or --evidence');
      entry.payload = {};
      if (args.commit) entry.payload.commit = args.commit;
      if (args.evidence) entry.payload.evidence = args.evidence;
      break;
    case 'defer_extended':
      if (!args.old_review_by || !args.new_review_by) fail('defer_extended requires --old-review-by and --new-review-by');
      entry.payload = { old_review_by: args.old_review_by, new_review_by: args.new_review_by };
      if (args.notes) entry.payload.notes = args.notes;
      break;
    case 'doc_lifecycle':
      if (!args.from || !args.to) fail('doc_lifecycle requires --from and --to');
      entry.payload = { from: args.from, to: args.to };
      break;
    case 'docs_audit':
      entry.payload = {
        total: Number(args.total ?? 0),
        orphans: Number(args.orphans ?? 0),
        drifted: Number(args.drifted ?? 0),
        stale: Number(args.stale ?? 0),
        mode: typeof args.mode === 'string' ? args.mode : 'full',
      };
      if (args.notes) entry.payload.notes = args.notes;
      break;
    case 'work_item_closed':
      // SPEC-0011 G2 — telemetry-at-close. --ref <DOC-ID> (already required above).
      // Payload: free-text validation + code_review status tokens.
      entry.payload = {};
      if (args.validation) entry.payload.validation = args.validation;
      if (args.code_review) entry.payload.code_review = args.code_review;
      if (args.notes) entry.payload.notes = args.notes;
      break;
    case 'code_review_completed':
      // SPEC-0011 G2 — code-review completion. --ref <DOC-ID> (required above),
      // --verdict <pass|fail>, optional --report <path>.
      if (!args.verdict) fail('code_review_completed requires --verdict');
      entry.payload = { verdict: args.verdict };
      if (args.report) entry.payload.report = args.report;
      if (args.notes) entry.payload.notes = args.notes;
      break;
  }

  fs.mkdirSync(path.dirname(EVENTS_PATH), { recursive: true });
  fs.appendFileSync(EVENTS_PATH, JSON.stringify(entry) + '\n');
  console.log(`Appended: ${JSON.stringify(entry)}`);
}

main();
