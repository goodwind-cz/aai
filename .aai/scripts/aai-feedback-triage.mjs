// aai-feedback-triage.mjs — RFC-0012 Phase 2 / RFC-0013 Slice B offline triage.
//
// Reads the local friction spool, applies hard gates, scores each observation
// from its schema-v2 structured signals (with a v1 recurrence fallback), clusters
// by fingerprint, and writes a LOCAL triage report. This slice is OFFLINE: no
// GitHub token, no network I/O, no issue payloads. `review`/`auto` modes are
// recognized but have no network side effect here (later slices). `auto` is never
// producible: every cluster's `auto_publishable` is false by construction.
//
// Usage:
//   node .aai/scripts/aai-feedback-triage.mjs [--spool <path>] [--config <path>]
//                                             [--out <path>] [--help]
// Exit codes: 0 success / --help   2 usage error   1 internal error
//
// Node stdlib only (Technology contract: zero runtime dependencies).

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, '..', '..');
const DEFAULT_SPOOL = join(REPO_ROOT, 'docs', 'ai', 'friction', 'observations.jsonl');
const DEFAULT_CONFIG = join(REPO_ROOT, '.aai', 'feedback.yaml');
const DEFAULT_OUT = join(REPO_ROOT, 'docs', 'ai', 'friction', 'triage-report.json');
const REPORT_SCHEMA = 'aai-triage/v1';

// The FRICTION_PROTOCOL failure-class taxonomy (AAI-ownership gate).
const FAILURE_CLASSES = new Set([
  'contradictory_instructions',
  'missing_or_invalid_artifact',
  'deterministic_script_failure',
  'abstraction_leak_recovery',
  'human_corrected_defect',
  'contract_violation',
]);
// The persisted D6 allowlist (v1 eight + v2 extensions). Any key outside this set
// means the line was not produced by the capture tool -> drop (sanitization gate).
const ALLOWED_KEYS = new Set([
  'schema_version', 'os_family', 'aai_pin', 'node_major', 'skill_id', 'skill_phase',
  'failure_class', 'fingerprint',
  'reproducible', 'impact', 'confidence', 'workaround', 'evidence_ref',
  'redaction_status', 'summary',
]);
const IMPACT_SCORE = { low: 1, medium: 2, high: 3 };
const CONFIDENCE_SCORE = { low: 1, medium: 2, high: 3 };
const REPRODUCIBLE_BONUS = 2;
const RECURRENCE_CAP = 5; // recurrence contributes at most this many points

const MODES = new Set(['local', 'review', 'auto']);
const DEFAULT_THRESHOLD = 4;

const HELP = `aai-feedback-triage — RFC-0012 Phase 2 offline triage (local mode).

Usage:
  node .aai/scripts/aai-feedback-triage.mjs [--spool <path>] [--config <path>] [--out <path>]
  node .aai/scripts/aai-feedback-triage.mjs --help

Reads the friction spool, applies hard gates (schema, AAI-ownership taxonomy,
sanitization), scores each observation from its schema-v2 signals (impact,
confidence, reproducible) with a v1 recurrence fallback, clusters by fingerprint,
and writes a LOCAL triage report (default docs/ai/friction/triage-report.json).

Guarantees:
  - Offline: no token and no network access is ever used.
  - local mode (default) SUMMARIZES only; no issue payload is emitted. review/auto
    are parsed but have no network effect in this slice. No cluster is ever
    auto_publishable (auto is locked until a later slice).

Exit codes: 0 success / --help   2 usage error   1 internal error
`;

class UsageError extends Error {}

function parseArgs(argv) {
  const out = { spool: DEFAULT_SPOOL, config: DEFAULT_CONFIG, out: DEFAULT_OUT };
  let i = 0;
  while (i < argv.length) {
    const tok = argv[i];
    if (tok === '--help' || tok === '-h') { out.help = true; i += 1; continue; }
    if (tok === '--spool' || tok === '--config' || tok === '--out') {
      const val = argv[i + 1];
      if (val === undefined) throw new UsageError(`${tok} requires a <path> argument`);
      out[tok.slice(2)] = val;
      i += 2;
      continue;
    }
    throw new UsageError(`unrecognized argument: ${tok}`);
  }
  return out;
}

// Scoped, fail-closed read of the triage mode + threshold from feedback.yaml.
// Mirrors aai-friction's capture-block discipline: only keys DIRECTLY under the
// top-level `triage:` mapping count; anything unparseable degrades to local.
function loadConfig(path) {
  const cfg = { mode: 'local', threshold: DEFAULT_THRESHOLD };
  let text;
  try { text = readFileSync(path, 'utf8'); } catch { return cfg; }
  let inTriage = false;
  for (const line of text.split('\n')) {
    if (/^[ \t]/.test(line)) {
      if (!inTriage) continue;
      let m = line.match(/^[ \t]+mode[ \t]*:[ \t]*([A-Za-z]+)[ \t]*$/);
      if (m && MODES.has(m[1])) cfg.mode = m[1];
      m = line.match(/^[ \t]+review_candidate[ \t]*:[ \t]*(\d+)[ \t]*$/);
      if (m) cfg.threshold = parseInt(m[1], 10);
      continue;
    }
    inTriage = /^triage[ \t]*:/.test(line);
  }
  if (!MODES.has(cfg.mode)) cfg.mode = 'local'; // fail closed
  return cfg;
}

function readSpool(path) {
  let text;
  try { text = readFileSync(path, 'utf8'); } catch { return []; }
  const rows = [];
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    try {
      const obj = JSON.parse(line);
      if (obj && typeof obj === 'object' && !Array.isArray(obj)) rows.push(obj);
    } catch { /* tolerate a partial/corrupt line */ }
  }
  return rows;
}

// Hard gates. Returns { ok: true } or { ok: false, reason }.
function gate(obs) {
  if (obs.schema_version !== 1 && obs.schema_version !== 2) {
    return { ok: false, reason: 'bad_schema_version' };
  }
  if (!FAILURE_CLASSES.has(obs.failure_class)) {
    return { ok: false, reason: 'non_taxonomy_failure_class' };
  }
  for (const k of Object.keys(obs)) {
    if (!ALLOWED_KEYS.has(k)) return { ok: false, reason: 'unsanitized_key' };
  }
  if (typeof obs.fingerprint !== 'string' || obs.fingerprint.length === 0) {
    return { ok: false, reason: 'missing_fingerprint' };
  }
  return { ok: true };
}

// Per-observation signal from its v2 structured fields. A v1 record (no v2
// fields) yields 0 here and is scored purely by recurrence at the cluster level.
function observationSignal(obs) {
  let s = 0;
  if (obs.impact && IMPACT_SCORE[obs.impact]) s += IMPACT_SCORE[obs.impact];
  if (obs.confidence && CONFIDENCE_SCORE[obs.confidence]) s += CONFIDENCE_SCORE[obs.confidence];
  if (obs.reproducible === true) s += REPRODUCIBLE_BONUS;
  return s;
}

function triage(rows, config) {
  const dropped = new Map();
  const kept = [];
  for (const obs of rows) {
    const g = gate(obs);
    if (g.ok) kept.push(obs);
    else dropped.set(g.reason, (dropped.get(g.reason) || 0) + 1);
  }

  // Cluster kept observations by fingerprint.
  const byFp = new Map();
  for (const obs of kept) {
    const fp = obs.fingerprint;
    if (!byFp.has(fp)) byFp.set(fp, []);
    byFp.get(fp).push(obs);
  }

  const clusters = [];
  for (const [fp, members] of byFp) {
    const recurrence = members.length;
    const maxSignal = members.reduce((m, o) => Math.max(m, observationSignal(o)), 0);
    const recurrenceBonus = Math.min(recurrence - 1, RECURRENCE_CAP);
    const score = maxSignal + recurrenceBonus;
    // auto is LOCKED in this slice: never publishable regardless of score.
    const autoPublishable = false;
    const decision = score >= config.threshold ? 'review_candidate' : 'retain';
    clusters.push({
      fingerprint: fp,
      failure_class: members[0].failure_class,
      recurrence,
      score,
      decision,
      auto_publishable: autoPublishable,
    });
  }
  // Deterministic order: by fingerprint (no wall-clock anywhere in the report).
  clusters.sort((a, b) => (a.fingerprint < b.fingerprint ? -1 : a.fingerprint > b.fingerprint ? 1 : 0));

  const droppedList = [...dropped.entries()]
    .sort((a, b) => (a[0] < b[0] ? -1 : 1))
    .map(([reason, count]) => ({ reason, count }));

  return {
    schema: REPORT_SCHEMA,
    mode: config.mode,
    threshold: config.threshold,
    total_observations: rows.length,
    kept: kept.length,
    dropped: droppedList,
    clusters,
  };
}

function main() {
  const argv = process.argv.slice(2);
  let args;
  try { args = parseArgs(argv); }
  catch (e) {
    process.stderr.write(`aai-feedback-triage: ${e.message}\n`);
    process.exit(2);
  }
  if (args.help) { process.stdout.write(HELP); process.exit(0); }

  const config = loadConfig(args.config);
  const rows = readSpool(args.spool);
  const report = triage(rows, config);

  // LOCAL only: write the report. No issue payload is emitted, and there is no
  // network/send path anywhere in this module (review/auto land in a later slice).
  writeFileSync(args.out, JSON.stringify(report, null, 2) + '\n');

  const rc = report.clusters.filter((c) => c.decision === 'review_candidate').length;
  process.stdout.write(
    `triaged ${report.total_observations} observation(s): ${report.kept} kept, `
    + `${report.clusters.length} cluster(s), ${rc} review candidate(s) `
    + `[mode=${report.mode}] -> ${args.out}\n`
  );
}

main();
