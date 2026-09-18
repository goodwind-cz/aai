#!/usr/bin/env node
// Append a single audit event to docs/ai/EVENTS.jsonl (RFC-0001 layer 5).
//
// Event types (closed set): ac_status, ac_evidence, defer_extended, doc_lifecycle,
//   docs_audit, work_item_closed, code_review_completed (SPEC-0011 G2),
//   phase_confirmed, spec_scope_edited (CHANGE-0120),
//   validation_verdict (role-verification-guards G2),
//   pr_sweep (Spec-AC-33, CHANGE-0060 step 5d mechanization / GitHub issue 338).
// Required: --event, --ref. Auto-filled: v=1, ts (ISO UTC), actor (git slug).
//
// Examples:
//   append-event.mjs --event ac_status --ref SPEC-0042/Spec-AC-07 \
//     --from implementing --to deferred --review-by 2026-08-01 --notes "→ RFC-0051"
//   append-event.mjs --event ac_evidence --ref SPEC-0042/Spec-AC-01 --commit a1b2c3d
//   append-event.mjs --event defer_extended --ref SPEC-0042/Spec-AC-07 \
//     --old-review-by 2026-08-01 --new-review-by 2026-Q4 --notes "..."
//   append-event.mjs --event doc_lifecycle --ref RFC-0042 --from draft --to implementing
//   append-event.mjs --event pr_sweep --ref close-ceremony-sweep --pr 42 --lane heavy \
//     --reviewer-bots expected --threads-seen 2 --threads-unresolved 0 --outcome swept
//
// Multi-file parent IDs: use --ref PARENT-ID/<filename-suffix> for a
// file-specific transition, bare --ref PARENT-ID for a parent-level one.
// Sub-refs roll up to the parent in the docs audit (CHANGE-0002 D11).

import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';
import { exit, runMain } from './lib/cli-pipe-guard.mjs';
import { nowIso } from './lib/iso-time.mjs';
import { PR_SWEEP_OUTCOMES, sweepContradictions, parseSweepCount } from './lib/pr-sweep.mjs';

const EVENTS_PATH = path.join(process.cwd(), 'docs/ai/EVENTS.jsonl');
const SCHEMA_VERSION = 1;
const EVENT_TYPES = new Set(['ac_status', 'ac_evidence', 'defer_extended', 'doc_lifecycle', 'docs_audit', 'work_item_closed', 'code_review_completed', 'phase_confirmed', 'spec_scope_edited', 'validation_verdict', 'pr_sweep']);
// PR_SWEEP_OUTCOMES / sweepContradictions live in lib/pr-sweep.mjs — the SAME
// predicate lane-gate.mjs --sweep-check imports and re-runs on the read side
// (validation-round1 NB-2: two copies of one gate is the DEBT-0002 pattern
// this ride exists to avoid repeating).

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
  exit(exitCode);
}

function main() {
  const args = parseArgs(process.argv);
  if (!args.event) fail('missing --event');
  if (!EVENT_TYPES.has(args.event)) fail(`unknown event type "${args.event}" (allowed: ${[...EVENT_TYPES].join(', ')})`);
  if (!args.ref) fail('missing --ref');

  const entry = {
    v: SCHEMA_VERSION,
    ts: nowIso(),
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
        false_open: Number(args.false_open ?? 0),
        mode: typeof args.mode === 'string' ? args.mode : 'full',
      };
      if (args.notes) entry.payload.notes = args.notes;
      break;
    case 'work_item_closed':
      // SPEC-0011 G2 — telemetry-at-close. --ref <DOC-ID> (already required above).
      // Payload: validation + code_review status tokens, BOTH required so an empty
      // close event cannot satisfy the docs-audit missing-close-telemetry check while
      // carrying no real closeout signal.
      if (!args.validation || !args.code_review) fail('work_item_closed requires --validation and --code-review');
      entry.payload = { validation: args.validation, code_review: args.code_review };
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
    case 'phase_confirmed':
      // CHANGE-0120 confirm-by-script — orchestration-dispatch.mjs rule 9x
      // proved the frozen spec's AC/test contract green and UNCHANGED, so no
      // implementer was dispatched. `hash` is the spec content hash
      // (docs-model specContentHash) that the NEXT tick compares against, and
      // `phase` is the work item's phase at the moment of confirmation. This
      // line IS the comparison snapshot — never hand-write one.
      if (!args.phase || !args.hash) fail('phase_confirmed requires --phase and --hash');
      entry.payload = { phase: args.phase, hash: args.hash };
      if (args.notes) entry.payload.notes = args.notes;
      break;
    case 'spec_scope_edited':
      // CHANGE-0120 — spec-scope-edit.mjs moved ONE path in/out of a frozen
      // spec's review-scope list without a Planning dispatch. `target` is the
      // path, `op` is include|exclude, `base_ref` records which diff the
      // no-ride-touch refusal was evaluated against (the audit is worthless
      // without it).
      if (!args.op || !args.target) fail('spec_scope_edited requires --op and --target');
      entry.payload = { op: args.op, target: args.target };
      if (args.base_ref) entry.payload.base_ref = args.base_ref;
      if (args.spec) entry.payload.spec = args.spec;
      if (args.notes) entry.payload.notes = args.notes;
      break;
    case 'validation_verdict':
      // role-verification-guards G2 — orchestration-dispatch.mjs stamps the
      // TREE hash a recorded validation verdict was judged against. `hash` is
      // the sha256 tree_hash (rev-parse HEAD + `status --porcelain -uno` +
      // `diff HEAD`, both filtered by TREE_HASH_EXCLUDE_PATHS — the `diff`
      // fold-in was added at remediation B4 so a content edit inside an
      // already-dirty tracked file is not invisible to the hash; see
      // computeTreeHash in orchestration-dispatch.mjs for the exact
      // definition, never re-derive it here), `status` is the validation
      // status at stamp time. The NEXT tick's decide() compares this line's
      // hash against the current tree_hash to report staleness — never a
      // re-implemented hash function.
      if (!args.status || !args.hash) fail('validation_verdict requires --status and --hash');
      entry.payload = { status: args.status, hash: args.hash };
      if (args.notes) entry.payload.notes = args.notes;
      break;
    case 'pr_sweep': {
      // CHANGE-0060 step 5d mechanization (Spec-AC-33, GitHub issue 338): a
      // merge-readiness claim ("the post-open bot sweep happened") is a
      // sentence a role writes; lane-gate.mjs --sweep-check (Spec-AC-34)
      // reads this record back before a merge is judged allowed. A record
      // whose fields contradict each other is refused WHOLE — nothing
      // written — so the ledger can never carry a claim the record itself
      // disproves.
      if (!args.pr) fail('pr_sweep requires --pr');
      if (!args.lane || !['fast', 'heavy'].includes(args.lane)) fail('pr_sweep requires --lane fast|heavy');
      if (!args.reviewer_bots) fail('pr_sweep requires --reviewer-bots');
      if (!args.outcome || !PR_SWEEP_OUTCOMES.has(args.outcome)) {
        fail(`pr_sweep requires --outcome ${[...PR_SWEEP_OUTCOMES].join('|')}`);
      }
      // B3 (validation-round1): a count that is not a non-negative integer
      // is a usage error, not a silent NaN -- Number('abc') coerced past
      // every sweepContradictions comparison (NaN <= 0 and NaN > 0 are both
      // false) and wrote `null` counts. Refuse whole, nothing written, name
      // the field.
      let threadsSeen;
      let threadsUnresolved;
      try {
        threadsSeen = parseSweepCount(args.threads_seen, 'threads_seen');
        threadsUnresolved = parseSweepCount(args.threads_unresolved, 'threads_unresolved');
      } catch (err) {
        fail(`pr_sweep ${err.message}`);
      }
      const payload = {
        pr: Number(args.pr),
        lane: args.lane,
        reviewer_bots: args.reviewer_bots,
        threads_seen: threadsSeen,
        threads_unresolved: threadsUnresolved,
        outcome: args.outcome,
      };
      const bad = sweepContradictions(payload);
      if (bad.length) fail(`pr_sweep record contradicts itself: ${bad.join('; ')}`);
      entry.payload = payload;
      break;
    }
  }

  fs.mkdirSync(path.dirname(EVENTS_PATH), { recursive: true });
  fs.appendFileSync(EVENTS_PATH, JSON.stringify(entry) + '\n');
  console.log(`Appended: ${JSON.stringify(entry)}`);
}

runMain(() => main());