#!/usr/bin/env node
// metrics-flush.mjs — deterministic METRICS_FLUSH (CHANGE-0009 D4-D6).
//
// Implements .aai/METRICS_FLUSH.prompt.md 1:1 as a STANDALONE multi-file
// transaction (deliberately NOT a state.mjs subcommand — state.mjs is a
// closed-contract single-file mutator; flush spans METRICS.jsonl + STATE +
// EVENTS + ephemeral files with its own partial-failure states):
//   - criteria gates (PASS verdict naming the ref, review pass/waived when
//     required, >=1 agent_run, not already in the ledger);
//   - human review time from LOOP_TICKS `human_resume` lines (ceil minutes;
//     a non-null STATE `reviews` value wins);
//   - cost via the SHARED PRICING lookup_rules resolver (lib/pricing.mjs):
//     strip one trailing bracket suffix -> aliases -> exact -> longest-prefix
//     -> unknown; cost only when BOTH tokens are present; null tokens keep
//     cost null and emit ONE VISIBLE WARNING line per run (never aggregated);
//   - timing fidelity: started/ended ISO-parseable, duration == delta (±1s),
//     not >300s future — else duration_seconds null, NEVER estimated;
//   - STATE cleanup is SURGICAL LINE EDITS ONLY via lib/state-engine.mjs —
//     remove the flushed metrics.work_items entry lines, remove done
//     active_work_items items, remove `metrics:` when it empties; never a
//     whole-file YAML re-serialization, so the commented schema header and all
//     untouched lines survive byte-identical by construction (mechanically
//     closes manual-flush mistake #1);
//   - ledger entries are built exclusively from strings/numbers/nulls read off
//     lines — no Date object can ever reach the ledger (closes mistake #2);
//     a guard asserts JSON.parse(JSON.stringify(entry)) deep-equals entry;
//   - truth-scoring (SPEC-DRAFT-truth-scoring / RES-0001 P3): every new entry
//     carries `strategy` (implementation_strategy.selected off STATE; null
//     when undecided/absent) and `reliability{validation_fails, review_fails,
//     remediation_runs, first_pass_clean}` derived ONLY from the recorded
//     runs (spec rules R1-R6): remediation count is structural (role contains
//     "remediation"), fail counts require the recorded "VERDICT: FAIL" marker
//     in the run note — never estimated, events are not a derivation source;
//   - ORDERING (mandatory): build + pre-validate EVERYTHING in memory first
//     (the mutated STATE must pass the check-state structural invariants),
//     then append the ledger line(s), then commit STATE via the engine's
//     atomic tmp+rename with the concurrency recheck, then ephemeral cleanup.
//     Ledger-before-reset: a crash between ledger append and STATE commit
//     leaves STATE original;
//   - IDEMPOTENT RESUME: a ref already IN the ledger but still present in
//     STATE metrics.work_items is an interrupted flush -> cleanup-only pass
//     (no second append, no duplicate ledger line);
//   - full reset (prompt 5d, STATE_FALLBACK.md flush-reset defaults) when NO
//     active work remains; partial-flush reset (5d2, SPEC-0013 H5) resets the
//     verdict blocks with FLUSH-provenance notes (never reset-block's
//     remediation marker) and nulls the leaked fields;
//   - ephemeral cleanup (6a-d) only on full reset; the protected set is a
//     hard constant (PROTECTED below);
//   - after the STATE commit the script runs check-state.mjs and reports its
//     verdict; a red check-state after commit is exit 1 with the pre-flush
//     STATE content saved to <state>.pre-flush-<ts> for recovery.
//
// Flags: --state/--metrics/--ticks/--pricing <path> (fixture injection),
// --events <path> (SPEC-0054/CHANGE-0038: flush never EMITS close-lifecycle
// events — close-work-item.mjs owns doc_lifecycle/work_item_closed — but
// metrics-flush-strands-completed-refs/SPEC-DRAFT-spec-metrics-flush-sweep
// READS this path under --sweep, and --retire both READS and APPENDS to it),
// --ref <id> (restrict),
// --dry-run (print the full plan JSON, write nothing), --sweep (OPT-IN:
// additionally flush every stranded metrics.work_items entry that carries
// DURABLE completion provenance — a committed work_item_closed event for the
// EXACT ref in EVENTS.jsonl AND active_work_items[ref].status==='done';
// fail-closed otherwise, reported, never fabricated — see D1 below and the
// spec), --now <ISO> (test-only clock pin; env AAI_FLUSH_NOW equivalent).
// AAI_FLUSH_INJECT_CRASH=after-ledger is a test-only fault hook.
//
// --retire <ref> [--reason "<text>"] (SPEC-DRAFT-spec-retire-stranded-
// nonworkitem-metric): the sanctioned exit for a metrics.work_items entry that
// is legitimately NOT a work item and would otherwise SKIP forever (satisfies
// neither flushability predicate). Structurally DISJOINT from the flush loop —
// when set, main() branches to handleRetire() and never touches the default
// path, so the no---retire behavior is byte-unchanged by construction. It is
// FAIL-CLOSED: it REFUSES (exit 1, nothing written) any ref that WOULD flush by
// EITHER existing predicate — the default (last_validation.status===pass naming
// the ref) OR the sweep (a committed work_item_closed event for the ref in
// EVENTS.jsonl, checked UNCONDITIONALLY), and any ref absent from
// metrics.work_items. On a genuinely-stranded ref it appends ONE durable
// metric_retired event (v/ts/actor/event/ref/payload{reason, discarded_runs:
// compact {role, model_id, duration_seconds} per run — telemetry preserved,
// not silently deleted}) to EVENTS.jsonl via a direct fs.appendFileSync
// (mirroring this script's own ledger-append idiom; NOT append-event.mjs),
// THEN removes the entry from STATE (ledger-before-STATE ordering). --dry-run
// --retire prints the plan and writes nothing, but STILL refuses a flushable
// ref (never a truth-gate bypass). --reason defaults to null when omitted.
//
// Exit codes: 0 flushed / nothing to flush / retired (or dry-run plan printed),
// 1 integrity refusal / post-commit check failure / retire refused (would
// flush, or ref absent) — original preserved or the recovery file named,
// 2 usage.

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { splitLines, duplicateKeys, inlineChildConflicts } from './lib/state-core.mjs';
import {
  setEngineFailPrefix, findBlock, editBlock, setField, scalarLine, textFieldLines,
  nullFieldIfPresent, readScalar, unquoteScalar, indentOf, writeState, bumpUpdatedAt,
} from './lib/state-engine.mjs';
import { loadPricing, runCostUsd } from './lib/pricing.mjs';

setEngineFailPrefix('metrics-flush');

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const FUTURE_SLACK_MS = 300 * 1000;
// The ephemeral-cleanup protected set (prompt 6d) — a HARD constant. Dotfile
// keepers (`.gitkeep` and any other dot-basename) are protected as a CLASS in
// the rm guard below: they are TRACKED placeholder files the gitignore
// carve-outs depend on, never ephemeral output (ISSUE-0007 bundled nit — the
// >7d tdd sweep deleted docs/ai/tdd/.gitkeep).
const PROTECTED = new Set(['METRICS.jsonl', 'decisions.jsonl', 'STATE.yaml', 'published']);

function fail(msg, code = 2) {
  console.error(`metrics-flush: ${msg}`);
  process.exit(code);
}

// git user.email -> a sanitized actor slug, mirroring append-event.mjs's own
// actorSlug() fallback semantics ("unknown" on any failure). Used only by the
// --retire audit event; spawnSync is already imported (no new dependency).
function actorSlug() {
  try {
    const r = spawnSync('git', ['config', 'user.email'], { encoding: 'utf8' });
    if (r.status !== 0 || typeof r.stdout !== 'string') return 'unknown';
    return r.stdout.trim().toLowerCase().replace(/[^a-z0-9._-]+/g, '_') || 'unknown';
  } catch {
    return 'unknown';
  }
}

// --- argv -----------------------------------------------------------------------

function parseArgs(argv) {
  const opts = {
    state: 'docs/ai/STATE.yaml',
    metrics: 'docs/ai/METRICS.jsonl',
    ticks: 'docs/ai/LOOP_TICKS.jsonl',
    pricing: '.aai/system/PRICING.yaml',
    events: 'docs/ai/EVENTS.jsonl',
    ref: null,
    dryRun: false,
    sweep: false,
    retire: null,
    reason: null,
    now: process.env.AAI_FLUSH_NOW ?? null,
  };
  const valueFlags = { '--state': 'state', '--metrics': 'metrics', '--ticks': 'ticks', '--pricing': 'pricing', '--events': 'events', '--ref': 'ref', '--retire': 'retire', '--reason': 'reason', '--now': 'now' };
  for (let i = 2; i < argv.length; i += 1) {
    const tok = argv[i];
    if (tok === '--dry-run') { opts.dryRun = true; continue; }
    if (tok === '--sweep') { opts.sweep = true; continue; }
    if (tok in valueFlags) {
      const v = argv[i + 1];
      if (v === undefined || v.startsWith('--')) fail(`${tok} requires a value`);
      opts[valueFlags[tok]] = v;
      i += 1;
      continue;
    }
    fail(`unknown flag "${tok}" (valid: --state --metrics --ticks --pricing --events --ref --dry-run --sweep --retire --reason --now)`);
  }
  if (opts.now !== null && (!ISO_RE.test(opts.now) || Number.isNaN(Date.parse(opts.now)))) {
    fail(`--now "${opts.now}" is not an ISO-8601 UTC timestamp`);
  }
  return opts;
}

// --- STATE read layer (line engine, no YAML lib) -----------------------------------

function scalarOrNull(v) {
  if (v === undefined || v === null) return null;
  const s = unquoteScalar(String(v).trim());
  return s === '' || s === 'null' ? null : s;
}

function asNumber(v) {
  if (v === null) return null;
  return /^-?\d+(\.\d+)?$/.test(v) ? Number(v) : v;
}

// Parse the metrics.work_items entries: [{ ref, start, end, intake, reviews, runs }]
// where runs = [{ fields..., _order }] read verbatim off the lines.
function parseMetricsEntries(lines) {
  const b = findBlock(lines, 'metrics');
  if (!b) return { block: null, entries: [] };
  const entries = [];
  let i = b.start + 1;
  while (i < b.end) {
    const m = lines[i].match(/^ {4}(\S.*?):\s*$/);
    if (!m) { i += 1; continue; }
    const ref = m[1];
    let end = b.end;
    for (let j = i + 1; j < b.end; j += 1) {
      const l = lines[j];
      if (l.trim() === '' || l.trim().startsWith('#')) continue;
      if (indentOf(l) < 6) { end = j; break; }
    }
    // Trim trailing blank lines out of the removable span (keep separators).
    let trimmed = end;
    while (trimmed > i + 1 && lines[trimmed - 1].trim() === '') trimmed -= 1;
    const entry = { ref, start: i, end: trimmed, intake: null, reviews: null, runs: [] };
    let run = null;
    for (let j = i + 1; j < trimmed; j += 1) {
      const l = lines[j];
      let mm = l.match(/^ {8}intake:\s*(.*)$/);
      if (mm) { entry.intake = asNumber(scalarOrNull(mm[1])); continue; }
      mm = l.match(/^ {8}reviews:\s*(.*)$/);
      if (mm) { entry.reviews = asNumber(scalarOrNull(mm[1])); continue; }
      mm = l.match(/^ {8}- role:\s*(.*)$/);
      if (mm) { run = { role: scalarOrNull(mm[1]) }; entry.runs.push(run); continue; }
      if (!run) continue;
      mm = l.match(/^ {10}([\w-]+):\s*(.*)$/);
      if (!mm) {
        // `>-` note continuation lines (folded scalar: join with a space).
        if (/^ {12}\S/.test(l) && typeof run.note === 'string') {
          run.note = run.note === '' ? l.trim() : `${run.note} ${l.trim()}`;
        }
        continue;
      }
      const key = mm[1];
      const rawV = mm[2].trim();
      if (key === 'note' && /^[|>]/.test(rawV)) { run.note = ''; continue; }
      const v = scalarOrNull(rawV);
      run[key] = ['duration_seconds', 'tokens_in', 'tokens_out', 'cost_usd', 'tdd_tests'].includes(key) ? asNumber(v) : v;
    }
    entries.push(entry);
    i = end;
  }
  return { block: b, entries };
}

// Parse active_work_items into [{ ref_id, status, start, end }] with spans.
function parseWorkItems(lines) {
  const b = findBlock(lines, 'active_work_items');
  if (!b) return { block: null, items: [] };
  const items = [];
  let cur = null;
  for (let i = b.start + 1; i < b.end; i += 1) {
    const l = lines[i];
    if (/^ {2}- /.test(l)) {
      if (cur) cur.end = i;
      cur = { start: i, end: b.end, ref_id: null, status: null };
      items.push(cur);
    }
    if (!cur) continue;
    const m = l.match(/^(?: {2}- | {4})([\w-]+):\s*(.*)$/);
    if (m && indentOf(l) <= 4) {
      if (m[1] === 'ref_id') cur.ref_id = scalarOrNull(m[2]);
      if (m[1] === 'status') cur.status = scalarOrNull(m[2]);
    }
  }
  if (cur) {
    let e = b.end;
    while (e > cur.start + 1 && lines[e - 1].trim() === '') e -= 1;
    cur.end = e;
  }
  return { block: b, items };
}

function refMatches(vref, ref) {
  if (vref == null || ref == null) return false;
  return vref === ref || String(vref).split('/').includes(ref);
}

// --- ledger / ticks / doc probes ----------------------------------------------------

function ledgerRefs(metricsPath) {
  const refs = new Set();
  if (!fs.existsSync(metricsPath)) return refs;
  for (const line of fs.readFileSync(metricsPath, 'utf8').split(/\r?\n/)) {
    const t = line.trim();
    if (t === '' || t.startsWith('#')) continue;
    try {
      const o = JSON.parse(t);
      if (o && typeof o.ref_id === 'string') refs.add(o.ref_id);
    } catch { /* best-effort matching probe */ }
  }
  return refs;
}

// metrics-flush-strands-completed-refs (--sweep, D1/D2): the set of refs with
// a committed `work_item_closed` event in EVENTS.jsonl — the SAME predicate
// close-work-item.mjs:hasWorkItemClosed uses (exact ref match). READ-ONLY:
// called only when opts.sweep; never creates the file; empty Set when absent
// (fail-closed, not a crash).
function closedRefs(eventsPath) {
  const refs = new Set();
  if (!fs.existsSync(eventsPath)) return refs;
  for (const line of fs.readFileSync(eventsPath, 'utf8').split(/\r?\n/)) {
    const t = line.trim();
    if (t === '' || t.startsWith('#')) continue;
    try {
      const o = JSON.parse(t);
      if (o && o.event === 'work_item_closed' && typeof o.ref === 'string') refs.add(o.ref);
    } catch { /* best-effort matching probe */ }
  }
  return refs;
}

// Sum of human_resume review_duration_seconds -> minutes rounded UP; null when
// the ticks file is absent or carries no resume lines.
function ticksReviewMinutes(ticksPath) {
  if (!fs.existsSync(ticksPath)) return null;
  let sum = 0;
  let seen = false;
  for (const line of fs.readFileSync(ticksPath, 'utf8').split(/\r?\n/)) {
    const t = line.trim();
    if (t === '') continue;
    try {
      const o = JSON.parse(t);
      if (o && o.type === 'human_resume' && typeof o.review_duration_seconds === 'number') {
        sum += o.review_duration_seconds;
        seen = true;
      }
    } catch { /* ignore unparseable tick lines */ }
  }
  return seen ? Math.ceil(sum / 60) : null;
}

// Repo root: <stateDir>/../.. when the STATE lives in the canonical docs/ai/.
function repoRootOf(statePath) {
  const stateDir = path.dirname(statePath);
  const parts = stateDir.split(path.sep);
  if (parts.length >= 2 && parts[parts.length - 2] === 'docs' && parts[parts.length - 1] === 'ai') {
    return path.dirname(path.dirname(stateDir));
  }
  return stateDir;
}

// Title: the first `# ` heading of the item's primary doc, else null.
function titleFor(root, docPath) {
  if (!docPath) return null;
  const abs = path.resolve(root, docPath);
  if (!fs.existsSync(abs)) return null;
  for (const line of fs.readFileSync(abs, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^#\s+(.*\S)\s*$/);
    if (m) return m[1];
  }
  return null;
}

// The item's primary_path (else spec_path) — parseWorkItems keeps spans lean,
// so the doc-path fields are read in a dedicated scan here.
function workItemDocPath(lines, ref) {
  const b = findBlock(lines, 'active_work_items');
  if (!b) return null;
  let inItem = false;
  let primary = null;
  let specp = null;
  for (let i = b.start + 1; i < b.end; i += 1) {
    const l = lines[i];
    if (/^ {2}- /.test(l)) {
      if (inItem) break;
      inItem = false;
      primary = null;
      specp = null;
    }
    const m = l.match(/^(?: {2}- | {4})([\w-]+):\s*(.*)$/);
    if (!m || indentOf(l) > 4) continue;
    if (m[1] === 'ref_id' && scalarOrNull(m[2]) === ref) inItem = true;
    if (m[1] === 'primary_path') primary = scalarOrNull(m[2]);
    if (m[1] === 'spec_path') specp = scalarOrNull(m[2]);
  }
  if (inItem) return primary ?? specp;
  return null;
}

// --- entry construction (strings/numbers/nulls ONLY) ---------------------------------

function trustedDuration(run, nowMs) {
  const st = run.started_utc;
  const en = run.ended_utc;
  if (typeof st !== 'string' || typeof en !== 'string') return null;
  if (!ISO_RE.test(st) || !ISO_RE.test(en)) return null;
  const sMs = Date.parse(st);
  const eMs = Date.parse(en);
  if (Number.isNaN(sMs) || Number.isNaN(eMs)) return null;
  if (sMs - nowMs > FUTURE_SLACK_MS || eMs - nowMs > FUTURE_SLACK_MS) return null;
  if (typeof run.duration_seconds !== 'number') return null;
  const delta = Math.round((eMs - sMs) / 1000);
  if (Math.abs(delta - run.duration_seconds) > 1) return null;
  return run.duration_seconds;
}

// Truth-scoring reliability (SPEC-DRAFT-truth-scoring rules R1-R6): counts of
// what was RECORDED, never a reconstruction. A fail cycle whose run note is
// null or lacks the verdict marker is invisible to the fail counters —
// remediation_runs stays the structural witness (a Remediation run is only
// dispatched after a recorded FAIL), so first_pass_clean requires ALL THREE
// counts to be zero rather than trusting the marker-gated counts alone.
const FAIL_MARKER_RE = /\bVERDICT:\s*FAIL\b/i;

function reliabilityOf(runs) {
  let validationFails = 0;
  let reviewFails = 0;
  let remediationRuns = 0;
  for (const r of runs) {
    const role = typeof r.role === 'string' ? r.role.toLowerCase() : '';
    const failNoted = typeof r.note === 'string' && FAIL_MARKER_RE.test(r.note);
    if (role.includes('remediation')) remediationRuns += 1;
    if (role.includes('validation') && failNoted) validationFails += 1;
    if (role.includes('review') && failNoted) reviewFails += 1;
  }
  return {
    validation_fails: validationFails,
    review_fails: reviewFails,
    remediation_runs: remediationRuns,
    first_pass_clean: validationFails === 0 && reviewFails === 0 && remediationRuns === 0,
  };
}

function buildEntry(entry, ctx) {
  const { pricing, nowMs, dateUtc, reviewsFromTicks, title, strategy } = ctx;
  const warnings = [];
  const runs = entry.runs.map(r => {
    const tokensIn = typeof r.tokens_in === 'number' ? r.tokens_in : null;
    const tokensOut = typeof r.tokens_out === 'number' ? r.tokens_out : null;
    let cost = typeof r.cost_usd === 'number' ? r.cost_usd : null;
    if (cost === null) cost = runCostUsd(pricing, r.model_id, tokensIn, tokensOut);
    if (tokensIn === null || tokensOut === null) {
      warnings.push(`WARNING ${entry.ref} run ${r.role} (${r.model_id ?? 'unknown'}): cost unattributable — tokens not recorded`);
    }
    const out = { role: r.role, model_id: r.model_id ?? 'unknown' };
    if (typeof r.note === 'string' && r.note !== '') out.note = r.note;
    out.started_utc = typeof r.started_utc === 'string' ? r.started_utc : null;
    out.ended_utc = typeof r.ended_utc === 'string' ? r.ended_utc : null;
    out.duration_seconds = trustedDuration(r, nowMs);
    out.tokens_in = tokensIn;
    out.tokens_out = tokensOut;
    out.cost_usd = cost;
    if (typeof r.tdd_tests === 'number') out.tdd_tests = r.tdd_tests;
    return out;
  });
  const reviews = entry.reviews !== null && typeof entry.reviews === 'number'
    ? entry.reviews          // STATE non-null value wins (human override)
    : reviewsFromTicks;      // else the LOOP_TICKS auto-measure (may be null)
  const intake = typeof entry.intake === 'number' ? entry.intake : null;
  const human = (intake ?? 0) + (reviews ?? 0);
  const agentSeconds = runs.reduce((a, r) => a + (r.duration_seconds ?? 0), 0);
  const anyNullCost = runs.some(r => r.cost_usd === null);
  const totalCost = anyNullCost ? null : runs.reduce((a, r) => a + r.cost_usd, 0);
  const ledgerEntry = {
    date_utc: dateUtc,
    ref_id: entry.ref,
    title,
    human_time_minutes: { intake, reviews },
    agent_runs: runs,
    totals: {
      human_time_minutes: human,
      agent_duration_seconds: agentSeconds,
      total_cost_usd: totalCost,
    },
    strategy,
    reliability: reliabilityOf(entry.runs),
    verdict: 'PASS',
  };
  // No-Date/JSON-safety guard (manual-flush mistake #2, mechanically closed):
  // the entry must deep-equal its own JSON round-trip.
  const roundTrip = JSON.parse(JSON.stringify(ledgerEntry));
  if (JSON.stringify(roundTrip) !== JSON.stringify(ledgerEntry)) {
    fail(`internal guard: ledger entry for ${entry.ref} is not JSON-round-trip stable — refusing to append`, 1);
  }
  return { ledgerEntry, warnings };
}

// --- STATE mutation (in memory; surgical line edits only) ------------------------------

function removeMetricsEntries(lines, refs) {
  // Remove bottom-up so spans stay valid.
  const { entries } = parseMetricsEntries(lines);
  const doomed = entries.filter(e => refs.includes(e.ref)).sort((a, b) => b.start - a.start);
  for (const e of doomed) lines.splice(e.start, e.end - e.start);
  // Drop the whole metrics block when work_items has no entries left.
  const after = parseMetricsEntries(lines);
  if (after.block && after.entries.length === 0) {
    lines.splice(after.block.start, after.block.end - after.block.start);
  }
}

function removeDoneWorkItems(lines, refs) {
  const { block, items } = parseWorkItems(lines);
  if (!block) return;
  const doomed = items
    .filter(it => refs.includes(it.ref_id) && it.status === 'done')
    .sort((a, b) => b.start - a.start);
  for (const it of doomed) lines.splice(it.start, it.end - it.start);
  const after = parseWorkItems(lines);
  if (after.block && after.items.length === 0) {
    lines.splice(after.block.start, after.block.end - after.block.start, 'active_work_items: []');
  }
}

function applyPartialReset(lines, flushedRefs, nowIso) {
  const note = `reset after flush of ${flushedRefs.join(', ')}`;
  editBlock(lines, 'last_validation', bl => {
    setField(bl, 2, 'status', [scalarLine(2, 'status', 'not_run')]);
    setField(bl, 2, 'run_at_utc', [scalarLine(2, 'run_at_utc', nowIso)]);
    setField(bl, 2, 'ref_id', [scalarLine(2, 'ref_id', 'null')]);
    setField(bl, 2, 'evidence_paths', [scalarLine(2, 'evidence_paths', '[]')]);
    setField(bl, 2, 'notes', textFieldLines(2, 'notes', note));
    return bl;
  });
  editBlock(lines, 'code_review', bl => {
    setField(bl, 2, 'required', [scalarLine(2, 'required', 'false')]);
    setField(bl, 2, 'status', [scalarLine(2, 'status', 'not_run')]);
    setField(bl, 2, 'scope', [scalarLine(2, 'scope', 'null')]);
    setField(bl, 2, 'base_ref', [scalarLine(2, 'base_ref', 'null')]);
    setField(bl, 2, 'head_ref', [scalarLine(2, 'head_ref', 'null')]);
    setField(bl, 2, 'report_paths', [scalarLine(2, 'report_paths', '[]')]);
    setField(bl, 2, 'notes', textFieldLines(2, 'notes', note));
    return bl;
  });
}

// Full reset — the STATE_FALLBACK.md flush-reset defaults, via engine edits.
function applyFullReset(lines) {
  editBlock(lines, 'last_validation', bl => {
    setField(bl, 2, 'status', [scalarLine(2, 'status', 'not_run')]);
    setField(bl, 2, 'run_at_utc', [scalarLine(2, 'run_at_utc', 'null')]);
    setField(bl, 2, 'ref_id', [scalarLine(2, 'ref_id', 'null')]);
    setField(bl, 2, 'evidence_paths', [scalarLine(2, 'evidence_paths', '[]')]);
    setField(bl, 2, 'notes', [scalarLine(2, 'notes', 'null')]);
    return bl;
  });
  editBlock(lines, 'implementation_strategy', bl => {
    setField(bl, 2, 'selected', [scalarLine(2, 'selected', 'undecided')]);
    setField(bl, 2, 'source', [scalarLine(2, 'source', 'null')]);
    setField(bl, 2, 'rationale', [scalarLine(2, 'rationale', 'null')]);
    return bl;
  });
  editBlock(lines, 'worktree', bl => {
    setField(bl, 2, 'recommendation', [scalarLine(2, 'recommendation', 'not_needed')]);
    setField(bl, 2, 'user_decision', [scalarLine(2, 'user_decision', 'undecided')]);
    for (const f of ['base_ref', 'branch', 'path', 'inline_review_scope', 'rationale']) {
      setField(bl, 2, f, [scalarLine(2, f, 'null')]);
    }
    return bl;
  });
  editBlock(lines, 'code_review', bl => {
    setField(bl, 2, 'required', [scalarLine(2, 'required', 'false')]);
    setField(bl, 2, 'status', [scalarLine(2, 'status', 'not_run')]);
    for (const f of ['scope', 'base_ref', 'head_ref']) {
      setField(bl, 2, f, [scalarLine(2, f, 'null')]);
    }
    setField(bl, 2, 'report_paths', [scalarLine(2, 'report_paths', '[]')]);
    setField(bl, 2, 'notes', [scalarLine(2, 'notes', 'null')]);
    return bl;
  });
  editBlock(lines, 'current_focus', bl => {
    setField(bl, 2, 'type', [scalarLine(2, 'type', 'none')]);
    setField(bl, 2, 'ref_id', [scalarLine(2, 'ref_id', 'null')]);
    setField(bl, 2, 'primary_path', [scalarLine(2, 'primary_path', 'null')]);
    nullFieldIfPresent(bl, 2, 'spec_path');
    return bl;
  });
  editBlock(lines, 'locks', bl => {
    setField(bl, 2, 'implementation', [scalarLine(2, 'implementation', 'true')]);
    return bl;
  });
}

// --- ephemeral cleanup (full reset only) ------------------------------------------------

function ageDays(nowMs, mtimeMs) {
  return Math.floor((nowMs - mtimeMs) / 86400000);
}

function cleanupEphemeral(stateDir, ticksPath, nowMs, report) {
  const rm = (p, why) => {
    const base = path.basename(p);
    if (PROTECTED.has(base)) return;   // hard constant, belt & braces
    if (base.startsWith('.')) return;  // dotfile keepers (.gitkeep) are tracked placeholders, never ephemeral
    fs.rmSync(p, { recursive: true, force: true });
    report.push(`Cleaned: ${p} (${why})`);
  };
  if (fs.existsSync(ticksPath) && !PROTECTED.has(path.basename(ticksPath))) {
    rm(ticksPath, 'runtime tick log, consumed by this flush');
  }
  const tddDir = path.join(stateDir, 'tdd');
  if (fs.existsSync(tddDir)) {
    for (const name of fs.readdirSync(tddDir)) {
      const p = path.join(tddDir, name);
      const st = fs.statSync(p);
      if (st.isFile() && ageDays(nowMs, st.mtimeMs) > 7) rm(p, `tdd evidence, age ${ageDays(nowMs, st.mtimeMs)}d > 7d`);
    }
  }
  const reportsDir = path.join(stateDir, 'reports');
  if (fs.existsSync(reportsDir)) {
    for (const name of fs.readdirSync(reportsDir)) {
      if (name === 'LATEST.md') continue;   // always kept
      const p = path.join(reportsDir, name);
      const st = fs.statSync(p);
      if (st.isFile() && /^validation-.*\.md$/.test(name) && ageDays(nowMs, st.mtimeMs) > 30) {
        rm(p, `validation report, age ${ageDays(nowMs, st.mtimeMs)}d > 30d`);
      }
    }
    const shots = path.join(reportsDir, 'screenshots');
    if (fs.existsSync(shots)) {
      for (const name of fs.readdirSync(shots)) {
        const p = path.join(shots, name);
        const st = fs.statSync(p);
        if (st.isDirectory() && ageDays(nowMs, st.mtimeMs) > 30) {
          rm(p, `screenshots, age ${ageDays(nowMs, st.mtimeMs)}d > 30d`);
        }
      }
    }
  }
}

// --- retire (SPEC-DRAFT-spec-retire-stranded-nonworkitem-metric) --------------------------
// The sanctioned exit for a stranded, legitimately-not-a-work-item entry. A
// FAIL-CLOSED branch reached ONLY when opts.retire is set (structurally
// disjoint from the flush loop). It REUSES the two existing flushability
// predicates verbatim — never a new/looser check — so it can never be a
// truth-gate bypass. Ledger(EVENTS)-before-STATE ordering mirrors the default
// flush's D-invariant.
function handleRetire(ctx) {
  const {
    ref, reason, entries, vStatus, vRef, eventsPath, statePath,
    origLines, trailingNewline, raw, nowIsoStr, opts,
  } = ctx;

  // 1) Existence guard — exact match (metrics.work_items keys are literal).
  const entry = entries.find(e => e.ref === ref);
  if (!entry) {
    fail(`retire refused: "${ref}" is not present in metrics.work_items — nothing to retire`, 1);
  }

  // 2) FAIL-CLOSED flushability guards (BOTH before the --dry-run branch, so a
  // dry-run on a flushable ref is STILL refused — never a preview of a bypass).
  //   (a) the DEFAULT predicate, verbatim from the flush loop.
  if (vStatus === 'pass' && refMatches(vRef, ref)) {
    fail(`retire refused: "${ref}" would flush (last_validation.status is pass and names ${ref}) `
      + '— flush it, do not retire (fail-closed truth-gate)', 1);
  }
  //   (b) the SWEEP predicate — closedRefs() called UNCONDITIONALLY for retire
  //   (regardless of whether --sweep was also passed).
  if (closedRefs(eventsPath).has(ref)) {
    fail(`retire refused: "${ref}" would flush (a committed work_item_closed event exists for ${ref} in EVENTS.jsonl) `
      + '— flush it, do not retire (fail-closed truth-gate)', 1);
  }

  // 3) Build the audit record — compact discarded_runs read VERBATIM off the
  // entry's own parsed runs (no re-derivation, no re-scoring).
  const discardedRuns = entry.runs.map(r => ({
    role: r.role ?? null,
    model_id: r.model_id ?? null,
    duration_seconds: typeof r.duration_seconds === 'number' ? r.duration_seconds : (r.duration_seconds ?? null),
  }));
  const event = {
    v: 1,
    ts: nowIsoStr,
    actor: actorSlug(),
    event: 'metric_retired',
    ref,
    payload: { reason: reason ?? null, discarded_runs: discardedRuns },
  };
  // Same JSON-round-trip safety guard buildEntry applies to ledger entries.
  const roundTrip = JSON.parse(JSON.stringify(event));
  if (JSON.stringify(roundTrip) !== JSON.stringify(event)) {
    fail(`internal guard: metric_retired event for ${ref} is not JSON-round-trip stable — refusing to append`, 1);
  }

  // 4) --dry-run: report the plan, write nothing (guards already passed above).
  if (opts.dryRun) {
    console.log(JSON.stringify({
      dry_run: true,
      retire: ref,
      reason: reason ?? null,
      would_remove_from_state: true,
      event,
    }, null, 2));
    process.exit(0);
  }

  // 5) Mutate a COPY of origLines via the EXISTING surgical helper (drops the
  // whole metrics: block when it empties). Retire never touches the verdict
  // blocks — a stranded non-work-item was never wired into them.
  const lines = [...origLines];
  removeMetricsEntries(lines, [ref]);
  bumpUpdatedAt(lines, nowIsoStr);

  // 6) In-memory pre-validation (same structural invariants as the flush path).
  const mDups = duplicateKeys(lines);
  const mConf = inlineChildConflicts(lines);
  if (mDups.length > 0 || mConf.length > 0) {
    fail('integrity refusal: the planned STATE cleanup would violate structural invariants '
      + `(duplicates: [${mDups.map(d => d.key).join(', ')}], inline conflicts: [${mConf.map(c => c.key).join(', ')}]) `
      + '— nothing written, original preserved', 1);
  }

  // 7) LEDGER(EVENTS)-BEFORE-STATE: the audit record is durable before STATE
  // changes at all. Direct append-only fs.appendFileSync (never a rewrite).
  fs.mkdirSync(path.dirname(eventsPath), { recursive: true });
  fs.appendFileSync(eventsPath, `${JSON.stringify(event)}\n`);

  // 8) STATE commit via the engine's atomic tmp + concurrency recheck + rename.
  writeState(statePath, lines, trailingNewline, raw);

  // 9) Post-commit check-state; red => exit 1 with a recovery file.
  const check = spawnSync(process.execPath, [path.join(SCRIPT_DIR, 'check-state.mjs'), statePath], { encoding: 'utf8' });
  if (check.status !== 0) {
    const recovery = `${statePath}.pre-flush-${nowIsoStr.replace(/[-:]/g, '')}`;
    fs.writeFileSync(recovery, raw);
    fail(`post-commit check-state FAILED — pre-flush STATE saved to ${recovery} for recovery:\n${check.stdout}${check.stderr}`, 1);
  }

  console.log(`Retired: ${ref} -> ${path.relative(process.cwd(), eventsPath)} (metric_retired)`);
  console.log(`check-state: OK (${path.relative(process.cwd(), statePath)})`);
  process.exit(0);
}

// --- main -----------------------------------------------------------------------------------

function main() {
  const opts = parseArgs(process.argv);
  const statePath = path.resolve(process.cwd(), opts.state);
  const metricsPath = path.resolve(process.cwd(), opts.metrics);
  const ticksPath = path.resolve(process.cwd(), opts.ticks);
  const pricingPath = path.resolve(process.cwd(), opts.pricing);
  // opts.events resolves to a path but is only ever READ, and only under
  // --sweep (D1/D2, metrics-flush-strands-completed-refs); the default
  // (no-flag) path never opens it — flush still never WRITES/creates
  // EVENTS.jsonl (SPEC-0054/CHANGE-0038: close-work-item.mjs owns the close
  // lifecycle).
  const eventsPath = path.resolve(process.cwd(), opts.events);
  if (!fs.existsSync(statePath)) fail(`STATE file not found: ${statePath}`);

  const raw = fs.readFileSync(statePath, 'utf8');
  const { lines: origLines, trailingNewline } = splitLines(raw);
  const dups = duplicateKeys(origLines);
  if (dups.length > 0) {
    fail(`refusing to flush: STATE has duplicate top-level key(s) [${dups.map(d => d.key).join(', ')}] `
      + `— repair first with: node .aai/scripts/check-state.mjs --repair ${statePath}`, 1);
  }

  const nowMs = opts.now ? Date.parse(opts.now) : Date.now();
  const nowIsoStr = new Date(nowMs).toISOString().replace(/\.\d+Z$/, 'Z');
  const dateUtc = nowIsoStr.slice(0, 10);
  const root = repoRootOf(statePath);
  const stateDir = path.dirname(statePath);
  const pricing = loadPricing(pricingPath);
  const inLedger = ledgerRefs(metricsPath);
  const reviewsFromTicks = ticksReviewMinutes(ticksPath);
  // D1/D2: the closed-event set is read ONLY under --sweep (never opened on
  // the default path, keeping the "flush never touches EVENTS" invariant
  // intact for TEST-012/019 et al.). The done-status lookup is a pure
  // in-memory re-read of origLines (already loaded) — cheap either way.
  const closed = opts.sweep ? closedRefs(eventsPath) : new Set();
  const { items: workItemsList } = parseWorkItems(origLines);
  const statusByRef = new Map(workItemsList.map(it => [it.ref_id, it.status]));

  const { entries } = parseMetricsEntries(origLines);
  const vStatus = readScalar(origLines, 'last_validation', 'status');
  const vRef = scalarOrNull(readScalar(origLines, 'last_validation', 'ref_id'));
  const rRequired = readScalar(origLines, 'code_review', 'required') === 'true';
  const rStatus = readScalar(origLines, 'code_review', 'status');
  const focusRef = scalarOrNull(readScalar(origLines, 'current_focus', 'ref_id'));
  // Truth-scoring R5: the strategy singleton is scoped to the refs the PASS
  // verdict names (every flushed ref, by the gate above) — 'undecided' or an
  // absent block records null, never a guess.
  const stratSel = scalarOrNull(readScalar(origLines, 'implementation_strategy', 'selected'));
  const strategy = stratSel !== null && stratSel !== 'undecided' ? stratSel : null;

  // --retire (SPEC-DRAFT-spec-retire-stranded-nonworkitem-metric): a
  // structurally-disjoint branch that NEVER reaches the default flush loop —
  // this is what keeps the no---retire behavior byte-unchanged by construction.
  if (opts.retire !== null) {
    handleRetire({
      ref: opts.retire, reason: opts.reason, entries, vStatus, vRef,
      eventsPath, statePath, origLines, trailingNewline, raw, nowIsoStr, opts,
    });
    return; // unreached — handleRetire always process.exit()s.
  }

  const skipped = {};
  const toFlush = [];
  const toResume = [];
  const sweptRefs = [];
  for (const entry of entries) {
    const ref = entry.ref;
    if (opts.ref && ref !== opts.ref) { skipped[ref] = 'not selected (--ref restriction)'; continue; }
    if (inLedger.has(ref)) { toResume.push(entry); continue; }   // interrupted flush

    // DEFAULT gate — BYTE-UNCHANGED from the pre-sweep logic (D2): the
    // current-validation ref, review pass/waived when required, runs>0.
    let defaultReason = null;
    if (!(vStatus === 'pass' && refMatches(vRef, ref))) {
      defaultReason = vStatus === 'pass'
        ? `validation verdict does not name ${ref} (last_validation.ref_id: ${vRef ?? 'null'}) — needs PASS for this ref`
        : `validation verdict is "${vStatus ?? 'null'}" (needs PASS or CANCELLED)`;
    } else if (rRequired && !['pass', 'waived'].includes(rStatus ?? '')) {
      defaultReason = `code_review required but status "${rStatus ?? 'null'}" (needs pass or waived)`;
    } else if (entry.runs.length === 0) {
      defaultReason = 'no agent_runs recorded in STATE metrics';
    }

    if (defaultReason === null) { toFlush.push(entry); continue; }

    // D1 sweep gate (STRICT / fail-closed) — an ADDITIONAL OR path, only when
    // --sweep is set; never removes/weakens what the default gate would flush.
    if (opts.sweep) {
      if (entry.runs.length === 0) {
        skipped[ref] = 'no agent_runs recorded in STATE metrics';
        continue;
      }
      if (!closed.has(ref)) {
        skipped[ref] = 'no durable work_item_closed event in EVENTS.jsonl — fail-closed';
        continue;
      }
      const status = statusByRef.get(ref);
      if (status !== 'done') {
        skipped[ref] = `active_work_items status is "${status ?? 'null'}" (needs done for --sweep; in-flight items are never swept) — fail-closed`;
        continue;
      }
      toFlush.push(entry);
      sweptRefs.push(ref);
      continue;
    }

    skipped[ref] = defaultReason;
  }

  // Build ledger entries + warnings in memory FIRST.
  const built = toFlush.map(entry => buildEntry(entry, {
    pricing,
    nowMs,
    dateUtc,
    reviewsFromTicks,
    title: titleFor(root, workItemDocPath(origLines, entry.ref)),
    strategy,
  }));

  const completedRefs = [...toFlush.map(e => e.ref), ...toResume.map(e => e.ref)];

  // Mutate a COPY of the lines in memory (surgical edits only).
  const lines = [...origLines];
  let fullReset = false;
  let partialRefs = [];
  if (completedRefs.length > 0) {
    removeMetricsEntries(lines, completedRefs);
    removeDoneWorkItems(lines, completedRefs);
    const { items: remaining } = parseWorkItems(lines);
    fullReset = remaining.length === 0 || remaining.every(it => it.status === 'done');
    if (fullReset) {
      applyFullReset(lines);
    } else {
      partialRefs = completedRefs.filter(r => r === focusRef || refMatches(vRef, r));
      if (partialRefs.length > 0) applyPartialReset(lines, partialRefs, nowIsoStr);
    }
    bumpUpdatedAt(lines, nowIsoStr);
  }

  // In-memory pre-validation: the mutated STATE must pass the structural
  // invariants BEFORE anything is written (integrity refusal otherwise).
  const mDups = duplicateKeys(lines);
  const mConf = inlineChildConflicts(lines);
  if (mDups.length > 0 || mConf.length > 0) {
    fail(`integrity refusal: the planned STATE cleanup would violate structural invariants `
      + `(duplicates: [${mDups.map(d => d.key).join(', ')}], inline conflicts: [${mConf.map(c => c.key).join(', ')}]) `
      + '— nothing written, original preserved', 1);
  }

  const report = [];
  if (opts.dryRun) {
    const plan = {
      dry_run: true,
      flush: toFlush.map(e => e.ref),
      swept: sweptRefs,
      resume: toResume.map(e => e.ref),
      skipped,
      entries: built.map(b => b.ledgerEntry),
      warnings: built.flatMap(b => b.warnings),
      partial_reset: partialRefs,
      full_reset: fullReset,
      cleanup_planned: fullReset,
    };
    console.log(JSON.stringify(plan, null, 2));
    process.exit(0);
  }

  if (completedRefs.length === 0) {
    for (const [ref, why] of Object.entries(skipped)) console.log(`SKIP ${ref}: ${why}`);
    console.log('Nothing to flush.');
    process.exit(0);
  }

  // 1) LEDGER FIRST (durable history lives in the ledger, never in STATE).
  if (built.length > 0) {
    fs.mkdirSync(path.dirname(metricsPath), { recursive: true });
    fs.appendFileSync(metricsPath, built.map(b => JSON.stringify(b.ledgerEntry) + '\n').join(''));
  }
  if (process.env.AAI_FLUSH_INJECT_CRASH === 'after-ledger') {
    // Test-only fault hook: die between the ledger append and the STATE
    // commit — STATE must stay original; a re-run resumes cleanup-only.
    process.kill(process.pid, 'SIGKILL');
  }

  // 2) STATE commit via the engine's atomic tmp + concurrency recheck + rename.
  writeState(statePath, lines, trailingNewline, raw);

  // 3) Post-commit check-state; red => exit 1 with a recovery file.
  const check = spawnSync(process.execPath, [path.join(SCRIPT_DIR, 'check-state.mjs'), statePath], { encoding: 'utf8' });
  if (check.status !== 0) {
    const recovery = `${statePath}.pre-flush-${nowIsoStr.replace(/[-:]/g, '')}`;
    fs.writeFileSync(recovery, raw);
    fail(`post-commit check-state FAILED — pre-flush STATE saved to ${recovery} for recovery:\n${check.stdout}${check.stderr}`, 1);
  }

  // 4) Ephemeral cleanup ONLY on full reset.
  if (fullReset) cleanupEphemeral(stateDir, ticksPath, nowMs, report);

  // Report.
  for (const b of built) console.log(`Flushed: ${b.ledgerEntry.ref_id} -> ${path.relative(process.cwd(), metricsPath)}`);
  for (const b of built) for (const w of b.warnings) console.log(w);
  for (const e of toResume) console.log(`RESUME ${e.ref}: already in ledger — cleanup-only pass (interrupted flush resume, no duplicate line)`);
  for (const [ref, why] of Object.entries(skipped)) console.log(`SKIP ${ref}: ${why}`);
  if (partialRefs.length > 0) console.log(`Partial-flush reset applied (SPEC-0013 H5) for: ${partialRefs.join(', ')} — verdict blocks reset with flush provenance`);
  if (fullReset) console.log('Full reset applied: no active work remains (flush-reset defaults per .aai/STATE_FALLBACK.md)');
  for (const l of report) console.log(l);
  console.log(`check-state: OK (${path.relative(process.cwd(), statePath)})`);
  process.exit(0);
}

main();
